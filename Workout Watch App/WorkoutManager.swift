//
//  WorkoutManager.swift
//  Workout Watch App
//
//  Created by 山中雄樹 on 2026/03/04.
//

import Foundation
import HealthKit
import Combine

@MainActor
class WorkoutManager: NSObject, ObservableObject {
    let healthStore = HKHealthStore()
    
    // ワークアウトセッション
    @Published var session: HKWorkoutSession?
    @Published var builder: HKLiveWorkoutBuilder?
    
    // ワークアウト状態
    @Published var isWorkoutActive = false {
        didSet {
            print("⚠️⚠️⚠️ isWorkoutActive changed from \(oldValue) to \(isWorkoutActive)")
            print("⚠️⚠️⚠️ Stack trace:")
            Thread.callStackSymbols.forEach { print("  \($0)") }
        }
    }
    @Published var isPaused = false
    @Published var workoutName = ""
    @Published var errorMessage: String?
    
    // 権限の状態
    private var isAuthorized = false
    
    // 連続操作の防止
    private var isProcessingPauseResume = false
    
    // メトリクス
    @Published private(set) var distance: Double = 0.0 // メートル - 外部から直接変更不可
    @Published private(set) var activeCalories: Double = 0.0
    @Published private(set) var averageHeartRate: Double = 0.0
    @Published private(set) var elapsedTime: TimeInterval = 0.0
    @Published private(set) var stepCount: Double = 0.0 // 歩数
    
    // 距離の最大値を追跡（減少を防ぐ）
    private var maxDistance: Double = 0.0
    // カロリーの最大値を追跡（減少を防ぐ）
    private var maxCalories: Double = 0.0
    // 歩数の最大値を追跡（減少を防ぐ）
    private var maxStepCount: Double = 0.0
    
    // 1km毎のペース計算用
    private var lastKmTimestamp: Date?
    private var lastKmDistance: Double = 0.0
    @Published var currentPace: TimeInterval = 0.0 // 秒/km
    
    // ラップタイム記録（1kmごと）
    @Published var lapTimes: [TimeInterval] = [] // 各ラップの所要時間（秒）
    
    // 心拍数の履歴（平均計算用・最大30個まで保持）
    private var heartRateHistory: [Double] = []
    private let maxHeartRateHistory = 30
    
    // タイマー
    private var timer: Timer?
    
    // 歩数監視用（ウォーキング専用）
    private var stepCountTimer: Timer?
    private var workoutStartDate: Date?
    
    // シミュレータ用のテストデータ生成
    #if targetEnvironment(simulator)
    private var simulatorDataTimer: Timer?
    private var simulatorDistance: Double = 0.0
    private var simulatorSteps: Double = 0.0
    #endif
    
    override init() {
        super.init()
        
        print("🔵 WorkoutManager initialized")
        checkAuthorizationStatus()
        requestAuthorization()
    }
    
    private func checkAuthorizationStatus() {
        let typesToCheck = [
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKQuantityType.quantityType(forIdentifier: .stepCount)!
        ]
        
        for type in typesToCheck {
            let status = healthStore.authorizationStatus(for: type)
            print("📋 Authorization status for \(type.identifier): \(status.rawValue)")
        }
    }
    
    // MARK: - Authorization
    
    func requestAuthorization() {
        let typesToShare: Set<HKSampleType> = [
            HKWorkoutType.workoutType()
        ]
        
        let typesToRead: Set<HKObjectType> = [
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKQuantityType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.activitySummaryType()
        ]
        
        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { success, error in
            Task { @MainActor in
                if let error = error {
                    print("❌ Authorization failed: \(error.localizedDescription)")
                    self.isAuthorized = false
                } else {
                    print("✅ HealthKit authorization success: \(success)")
                    self.isAuthorized = success
                }
            }
        }
    }
    
    // MARK: - Workout Control
    
    nonisolated func startWorkout(activityType: HKWorkoutActivityType, workoutName: String) async {
        print("🔵 ========================================")
        print("🔵 START WORKOUT CALLED: \(workoutName)")
        print("🔵 ========================================")
        
        // 🔥 重要: まず全てのタイマーとリソースを完全にクリーンアップ
        await MainActor.run {
            print("🔵 PRE-CLEANUP: Stopping all timers and clearing state...")
            
            // 全てのタイマーを強制停止
            self.stopTimer()
            self.stopStepCountMonitoring()
            
            #if targetEnvironment(simulator)
            self.stopSimulatorDataGeneration()
            #endif
            
            // 処理中フラグをリセット
            self.isProcessingPauseResume = false
            
            // エラーメッセージをクリア
            self.errorMessage = nil
            
            print("🔵 Current isPaused: \(self.isPaused)")
            print("🔵 Current isWorkoutActive: \(self.isWorkoutActive)")
            print("🔵 Existing session: \(self.session != nil), builder: \(self.builder != nil)")
            print("🔵 Authorization status: \(self.isAuthorized)")
        }
        
        print("🔵 ========================================")
        
        // HealthKitが利用可能か確認
        guard HKHealthStore.isHealthDataAvailable() else {
            print("❌ HealthKit is not available on this device")
            await MainActor.run {
                self.errorMessage = "HealthKit is not available on this device"
            }
            return
        }
        
        print("🔵 HealthKit is available")
        
        // シミュレータでは権限チェックを緩和
        #if targetEnvironment(simulator)
        print("⚠️ Running in simulator, setting authorized to true")
        await MainActor.run {
            self.isAuthorized = true
        }
        #endif
        
        // 権限確認（実機のみ厳密にチェック）
        let isAuthorizedValue = await MainActor.run { self.isAuthorized }
        if !isAuthorizedValue {
            print("⚠️ Not authorized, requesting...")
            await MainActor.run {
                self.requestAuthorization()
            }
            try? await Task.sleep(for: .milliseconds(500))
            
            #if !targetEnvironment(simulator)
            let stillNotAuthorized = await MainActor.run { !self.isAuthorized }
            if stillNotAuthorized {
                print("❌ Authorization failed")
                await MainActor.run {
                    self.errorMessage = "HealthKit権限が必要です。iPhoneで許可してください。"
                }
                return
            }
            #endif
        }
        
        print("🔵 Authorization OK, proceeding...")
        
        // 🔥 重要: 既存のセッションがあれば完全にクリーンアップ
        let existingSession = await MainActor.run { self.session }
        let existingBuilder = await MainActor.run { self.builder }
        
        if let existingSession = existingSession {
            print("🔵 ========================================")
            print("🔵 FOUND EXISTING SESSION - FORCING CLEANUP")
            print("🔵 State: \(existingSession.state.rawValue)")
            print("🔵 ========================================")
            
            // デリゲートをクリア（コールバックを防ぐ）
            await MainActor.run {
                existingSession.delegate = nil
                self.builder?.delegate = nil
            }
            
            // 実行中なら停止
            if existingSession.state == .running {
                print("🔵 Pausing existing running session...")
                existingSession.pause()
                try? await Task.sleep(for: .milliseconds(200))
            }
            
            // セッションを終了
            print("🔵 Ending existing session...")
            existingSession.end()
            
            // 終了を短時間待機（最大1秒）
            for attempt in 0..<10 {
                if existingSession.state == .ended {
                    print("🔵 ✅ Existing session ended after \(attempt * 100)ms")
                    break
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            
            // ビルダーもクリーンアップ（エラーは無視、タイムアウト付き）
            if let existingBuilder = existingBuilder {
                print("🔵 Cleaning up existing builder...")
                Task {
                    do {
                        // タイムアウト1秒
                        try await withThrowingTaskGroup(of: Void.self) { group in
                            group.addTask {
                                try await existingBuilder.endCollection(at: Date())
                                try await existingBuilder.finishWorkout()
                            }
                            
                            group.addTask {
                                try await Task.sleep(for: .seconds(1))
                                throw NSError(domain: "WorkoutManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Builder cleanup timeout"])
                            }
                            
                            try await group.next()
                            group.cancelAll()
                        }
                        print("🔵 ✅ Existing builder cleaned up")
                    } catch {
                        print("⚠️ Builder cleanup error (ignoring): \(error.localizedDescription)")
                    }
                }
            }
        }
        
        // 🔥 重要: 全ての参照とタイマーを完全にクリア
        await MainActor.run {
            print("🔵 ========================================")
            print("🔵 COMPLETE STATE RESET")
            print("🔵 ========================================")
            
            self.session = nil
            self.builder = nil
            
            // タイマーを再度確実に停止
            self.stopTimer()
            self.stopStepCountMonitoring()
            
            #if targetEnvironment(simulator)
            self.stopSimulatorDataGeneration()
            #endif
            
            // 状態をリセット - ⚠️ isWorkoutActiveは触らない！
            // self.isWorkoutActive = false  // ← これを削除！
            self.isPaused = false
            self.isProcessingPauseResume = false
            
            // メトリクスをリセット
            self.resetMetrics()
            
            print("🔵 ✅ State completely reset (keeping isWorkoutActive unchanged)")
            print("🔵 isWorkoutActive: \(self.isWorkoutActive)")
            print("🔵 session: \(self.session == nil ? "nil ✅" : "NOT NIL ❌")")
            print("🔵 builder: \(self.builder == nil ? "nil ✅" : "NOT NIL ❌")")
            print("🔵 timer: \(self.timer == nil ? "nil ✅" : "NOT NIL ❌")")
            print("🔵 stepCountTimer: \(self.stepCountTimer == nil ? "nil ✅" : "NOT NIL ❌")")
            print("🔵 ========================================")
        }
        
        // 短い待機時間を入れてリソースが完全に解放されるのを待つ
        try? await Task.sleep(for: .milliseconds(300))
        
        print("🔵 ========================================")
        print("🔵 READY TO CREATE NEW SESSION")
        print("🔵 ========================================")
        
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activityType
        configuration.locationType = .outdoor
        
        // healthStoreを取得
        let healthStore = await MainActor.run { self.healthStore }
        
        do {
            print("🔵 Creating new workout session...")
            let newSession = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let newBuilder = newSession.associatedWorkoutBuilder()
            
            print("🔵 Session and builder created")
            
            newBuilder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )
            
            print("🔵 Data source configured")
            
            // デリゲートを設定（MainActorで）
            await MainActor.run {
                newSession.delegate = self
                newBuilder.delegate = self
            }
            
            print("🔵 Delegates set")
            
            let startDate = Date()
            
            // プロパティに割り当て（MainActorで）
            await MainActor.run {
                self.session = newSession
                self.builder = newBuilder
                self.workoutName = workoutName
                self.workoutStartDate = startDate
                self.lastKmTimestamp = startDate
                self.lastKmDistance = 0.0
                self.isPaused = false
            }
            
            print("🔵 Starting session with date: \(startDate)")
            newSession.startActivity(with: startDate)
            
            // 待機を削除 - デリゲートメソッドでUI更新を行う
            print("🔵 Session started, state will change via delegate")
            
            // beginCollectionを呼び出す（タイムアウト付き - シミュレータでは短縮）
            print("🔵 Calling beginCollection with date: \(startDate)")
            
            #if targetEnvironment(simulator)
            let timeoutDuration: Duration = .seconds(1)  // シミュレータでは1秒
            print("⚠️ Simulator: Using short timeout of 1 second for beginCollection")
            #else
            let timeoutDuration: Duration = .seconds(5)  // 実機では5秒
            #endif
            
            do {
                // タイムアウト処理を追加
                try await withThrowingTaskGroup(of: Void.self) { group in
                    // beginCollection タスク
                    group.addTask {
                        try await newBuilder.beginCollection(at: startDate)
                    }
                    
                    // タイムアウトタスク
                    group.addTask {
                        try await Task.sleep(for: timeoutDuration)
                        throw NSError(domain: "WorkoutManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "beginCollection timeout"])
                    }
                    
                    // 最初に完了したタスクの結果を使用
                    try await group.next()
                    
                    // 残りのタスクをキャンセル
                    group.cancelAll()
                }
                
                print("🔵 ✅ Collection started successfully")
            } catch {
                print("❌ beginCollection failed or timed out: \(error.localizedDescription)")
                
                #if targetEnvironment(simulator)
                // シミュレータではエラーを無視して即座に続行
                print("⚠️ Simulator: Ignoring beginCollection error and continuing immediately...")
                // エラーメッセージを設定（警告として表示）
                await MainActor.run {
                    self.errorMessage = "シミュレータモード: データ収集は制限されています"
                }
                // エラーを再スローしない - 処理を続行
                #else
                // 実機でもタイムアウトの場合は続行を試みる
                if error.localizedDescription.contains("timeout") {
                    print("⚠️ Timeout occurred, continuing anyway...")
                    await MainActor.run {
                        self.errorMessage = "データ収集の開始に時間がかかりましたが、続行します"
                    }
                    // タイムアウトの場合は続行
                } else {
                    // その他のエラーは致命的なので再スロー
                    throw error
                }
                #endif
            }
            
            // 歩数監視を開始（ウォーキングの場合）
            if activityType == .walking {
                print("🔵 Starting step count monitoring")
                await MainActor.run {
                    self.startStepCountMonitoring()
                }
            }
            
            // タイマー開始
            print("🔵 Starting timer")
            await MainActor.run {
                self.startTimer()
            }
            
            #if targetEnvironment(simulator)
            // シミュレータ用の模擬データ生成を開始
            print("⚠️ Simulator: Starting mock data generation")
            await MainActor.run {
                self.startSimulatorDataGeneration()
            }
            #endif
            
            // 🔥 重要: isWorkoutActiveを更新してUI遷移をトリガー
            print("🔵 ========================================")
            print("🔵 ⭐️ Setting isWorkoutActive = true")
            print("🔵 About to call MainActor.run for UI update...")
            print("🔵 Current isWorkoutActive BEFORE: \(await MainActor.run { self.isWorkoutActive })")
            await MainActor.run {
                print("🔵 Inside MainActor.run block")
                print("🔵 isWorkoutActive before change: \(self.isWorkoutActive)")
                
                // シミュレータの警告メッセージ以外のエラーメッセージをクリア
                if self.errorMessage != "シミュレータモード: データ収集は制限されています" {
                    self.errorMessage = nil
                }
                
                // 強制的にobjectWillChangeを発火
                print("🔵 Sending objectWillChange (before)")
                self.objectWillChange.send()
                
                self.isWorkoutActive = true
                print("🔵 ✅ isWorkoutActive changed to: \(self.isWorkoutActive)")
                
                // 再度objectWillChangeを発火（確実に通知）
                print("🔵 Sending objectWillChange (after)")
                self.objectWillChange.send()
                
                print("🔵 session: \(self.session != nil)")
                print("🔵 builder: \(self.builder != nil)")
            }
            print("🔵 MainActor.run completed")
            print("🔵 Current isWorkoutActive AFTER: \(await MainActor.run { self.isWorkoutActive })")
            
            // UI更新を確実にするため、少し待機
            try? await Task.sleep(for: .milliseconds(100))
            
            print("🔵 Session state: \(newSession.state.rawValue)")
            print("🔵 Builder: \(newBuilder)")
            print("🔵 ========================================")
            
            print("🔵 ✅ Workout startup complete!")
            
        } catch let error as NSError {
            print("❌ ========================================")
            print("❌ Failed to start workout!")
            print("❌ Error domain: \(error.domain)")
            print("❌ Error code: \(error.code)")
            print("❌ Error description: \(error.localizedDescription)")
            print("❌ Error userInfo: \(error.userInfo)")
            
            #if targetEnvironment(simulator)
            print("⚠️ Running in simulator")
            #endif
            
            print("❌ ========================================")
            
            #if targetEnvironment(simulator)
            // シミュレータでは一部のエラーを無視して動作テストを可能にする
            if error.domain == "com.apple.healthkit" || error.domain == NSCocoaErrorDomain {
                print("⚠️ Simulator: Treating HealthKit error as warning, allowing UI to proceed")
                await MainActor.run {
                    self.errorMessage = "シミュレータモード: データ収集は制限されています"
                    
                    // UIは遷移させる（テスト用）
                    self.isWorkoutActive = true
                    print("⚠️ Simulator: Set isWorkoutActive = true for testing")
                }
                return
            }
            #endif
            
            await MainActor.run {
                self.errorMessage = "ワークアウトの開始に失敗しました: \(error.localizedDescription)"
            }
            
            // エラー時のクリーンアップ
            let errorSession = await MainActor.run { self.session }
            if let errorSession = errorSession {
                print("❌ Ending failed session...")
                await MainActor.run {
                    errorSession.delegate = nil
                }
                errorSession.end()
            }
            
            await MainActor.run {
                self.builder?.delegate = nil
                self.session = nil
                self.builder = nil
                self.isWorkoutActive = false
                self.isPaused = false
                self.stopTimer()
                self.stopStepCountMonitoring()
                self.resetMetrics()
                
                #if targetEnvironment(simulator)
                self.stopSimulatorDataGeneration()
                #endif
                
                print("❌ Cleanup complete after error")
            }
        }
    }
    
    func pauseWorkout() {
        print("🟡 pauseWorkout called")
        print("🟡 Session state before pause: \(session?.state.rawValue ?? -1)")
        print("🟡 Current isPaused flag: \(isPaused)")
        print("🟡 isProcessingPauseResume: \(isProcessingPauseResume)")
        
        // 既に処理中なら無視
        guard !isProcessingPauseResume else {
            print("⚠️ Cannot pause: already processing pause/resume")
            return
        }
        
        guard let session = session else {
            print("⚠️ Cannot pause: session is nil")
            return
        }
        
        // すでに一時停止状態なら何もしない
        if session.state == .paused {
            print("ℹ️ Session is already paused")
            // UIとの同期を確実にする
            if !isPaused {
                print("⚠️ UI was out of sync, correcting isPaused to true")
                isPaused = true
            }
            return
        }
        
        guard session.state == .running else {
            print("⚠️ Cannot pause: session is not running (state: \(session.state.rawValue))")
            return
        }
        
        // 処理開始フラグを設定
        isProcessingPauseResume = true
        
        // UIを先に更新（レスポンシブに）
        isPaused = true
        
        session.pause()
        print("🟡 Pause requested, isPaused set to true")
        
        // 処理完了フラグを一定時間後にリセット
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            isProcessingPauseResume = false
            print("🟡 Pause processing complete")
        }
    }
    
    func resumeWorkout() {
        print("🟢 resumeWorkout called")
        print("🟢 Session state before resume: \(session?.state.rawValue ?? -1)")
        print("🟢 Current isPaused flag: \(isPaused)")
        print("🟢 isProcessingPauseResume: \(isProcessingPauseResume)")
        
        // 既に処理中なら無視
        guard !isProcessingPauseResume else {
            print("⚠️ Cannot resume: already processing pause/resume")
            return
        }
        
        guard let session = session else {
            print("⚠️ Cannot resume: session is nil")
            return
        }
        
        print("🟢 Session exists, state: \(session.state.rawValue)")
        
        // すでに実行中の場合
        if session.state == .running {
            print("ℹ️ Session is already running")
            // UIの状態が不一致の場合のみ同期
            if isPaused {
                print("⚠️ UI was out of sync, correcting isPaused to false")
                isPaused = false
                
                // 🔥 一時停止中に蓄積された内部値をUI表示に反映
                syncUIWithInternalValues()
            }
            return
        }
        
        // 一時停止状態または準備状態からの再開を試みる
        if session.state == .paused || session.state == .prepared {
            print("🟢 Resuming session from state: \(session.state.rawValue)")
            
            // 処理開始フラグを設定
            isProcessingPauseResume = true
            
            // UIを先に更新（レスポンシブに）
            isPaused = false
            
            // 🔥 一時停止中に蓄積された内部値をUI表示に反映
            syncUIWithInternalValues()
            
            session.resume()
            print("🟢 Resume requested, isPaused set to false, UI synced with internal values")
            
            // セッションの状態変化を非同期で確認
            Task { @MainActor in
                // まず処理フラグをリセット
                try? await Task.sleep(for: .milliseconds(200))
                isProcessingPauseResume = false
                print("🟢 Resume processing complete")
                
                // 状態確認（デリゲートが呼ばれなかった場合の保険）
                try? await Task.sleep(for: .milliseconds(300))
                
                // デリゲートで既に更新されていればスキップ
                if session.state == .running && isPaused {
                    print("⚠️ Session resumed but isPaused still true, correcting")
                    isPaused = false
                    syncUIWithInternalValues()
                } else if session.state != .running && !isPaused {
                    print("⚠️ Session did not resume properly (state: \(session.state.rawValue)), correcting")
                    isPaused = true
                    
                    // もう一度リトライ
                    print("🟢 Retrying resume...")
                    if session.state == .paused {
                        session.resume()
                        print("🟢 Resume retry requested")
                    }
                }
                
                print("🟢 Final state check - session: \(session.state.rawValue), isPaused: \(isPaused)")
            }
        } else {
            print("⚠️ Session is in unexpected state: \(session.state.rawValue)")
            // 状態が不整合でもUIが一時停止中ならresumeを試行
            if isPaused {
                print("🟢 UI shows paused, attempting resume despite session state")
                
                isProcessingPauseResume = true
                isPaused = false
                
                // 🔥 一時停止中に蓄積された内部値をUI表示に反映
                syncUIWithInternalValues()
                
                session.resume()
                print("🟢 Resume attempted from unexpected state, UI synced")
                
                // 処理完了フラグを一定時間後にリセット
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(200))
                    isProcessingPauseResume = false
                    print("🟢 Resume processing complete (from unexpected state)")
                }
            }
        }
    }
    
    // 🔥 一時停止中に蓄積された内部値をUI表示に同期
    private func syncUIWithInternalValues() {
        print("🔄 Syncing UI with internal values accumulated during pause...")
        
        let oldDistance = distance
        let oldCalories = activeCalories
        let oldSteps = stepCount
        
        // 最大値（内部記録）をUI表示に反映
        distance = maxDistance
        activeCalories = maxCalories
        stepCount = maxStepCount
        
        // 心拍数の平均を再計算してUI反映
        if !heartRateHistory.isEmpty {
            averageHeartRate = heartRateHistory.reduce(0, +) / Double(heartRateHistory.count)
        }
        
        print("🔄 ✅ UI synced:")
        print("  Distance: \(String(format: "%.2f", oldDistance))m → \(String(format: "%.2f", distance))m")
        print("  Calories: \(String(format: "%.1f", oldCalories))kcal → \(String(format: "%.1f", activeCalories))kcal")
        print("  Steps: \(Int(oldSteps)) → \(Int(stepCount)) steps")
        print("  Heart Rate: \(Int(averageHeartRate)) bpm")
    }
    
    nonisolated func endWorkout() async {
        print("🔴 ========================================")
        print("🔴 endWorkout called - FULL CLEANUP")
        print("🔴 ========================================")
        
        // 🔥 重要: UIを即座に更新（ユーザーフィードバック優先）
        await MainActor.run {
            print("🔴 ⚡️ IMMEDIATE UI UPDATE for responsiveness")
            
            // UIをすぐに初期状態に戻す（Apple Watch対策）
            self.isWorkoutActive = false
            self.isPaused = false
            self.isProcessingPauseResume = false
            
            // タイマーを即座に停止
            print("🔴 Stopping all timers and monitoring...")
            self.stopTimer()
            self.stopStepCountMonitoring()
            
            #if targetEnvironment(simulator)
            self.stopSimulatorDataGeneration()
            #endif
            
            print("🔴 ✅ UI immediately responsive, background cleanup starting...")
        }
        
        // MainActorで値を取得
        let (currentSession, currentBuilder) = await MainActor.run {
            let currentSession = self.session
            let currentBuilder = self.builder
            
            print("🔴 Current session state: \(self.session?.state.rawValue ?? -1)")
            print("🔴 Current builder: \(self.builder != nil)")
            
            return (currentSession, currentBuilder)
        }
        
        // デリゲートを先にクリア（コールバックを防ぐ）
        await MainActor.run {
            print("🔴 Clearing delegates to prevent callbacks...")
            currentSession?.delegate = nil
            currentBuilder?.delegate = nil
            self.session?.delegate = nil
            self.builder?.delegate = nil
        }
        
        // 🔥 バックグラウンドタスクでビルダーとセッションを処理（UIをブロックしない）
        Task.detached(priority: .background) {
            print("🔴 ⚙️ Background: Starting async cleanup...")
            
            // セッションがアクティブな場合は一旦停止
            if let currentSession = currentSession, currentSession.state == .running {
                print("🔴 Background: Pausing session before ending...")
                currentSession.pause()
                
                // 停止を待つ（短時間のみ）
                for attempt in 0..<10 {
                    if currentSession.state == .paused || currentSession.state == .ended {
                        print("🔴 Background: Session paused/ended after \(attempt * 100)ms")
                        break
                    }
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            
            // ビルダーの終了（タイムアウト付き - Apple Watch用に短縮）
            if let currentBuilder = currentBuilder {
                do {
                    print("🔴 Background: Ending builder collection...")
                    
                    // Apple Watch用にタイムアウトを2秒に短縮
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask {
                            try await currentBuilder.endCollection(at: Date())
                        }
                        
                        group.addTask {
                            try await Task.sleep(for: .seconds(2))  // 3秒→2秒に短縮
                            throw NSError(domain: "WorkoutManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "endCollection timeout"])
                        }
                        
                        try await group.next()
                        group.cancelAll()
                    }
                    
                    print("🔴 Background: Collection ended, finishing workout...")
                    
                    // finishWorkout もタイムアウト付き（Apple Watch用に2秒に短縮）
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask {
                            try await currentBuilder.finishWorkout()
                        }
                        
                        group.addTask {
                            try await Task.sleep(for: .seconds(2))  // 3秒→2秒に短縮
                            throw NSError(domain: "WorkoutManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "finishWorkout timeout"])
                        }
                        
                        try await group.next()
                        group.cancelAll()
                    }
                    
                    print("🔴 Background: ✅ Builder finished successfully")
                } catch {
                    print("❌ Background: Failed to end builder: \(error.localizedDescription)")
                    
                    #if targetEnvironment(simulator)
                    print("⚠️ Background: Simulator - Ignoring builder error...")
                    #else
                    print("⚠️ Background: Real device - Ignoring builder error...")
                    #endif
                }
            }
            
            // セッションの終了（タイムアウト短縮）
            if let currentSession = currentSession {
                print("🔴 Background: Ending session...")
                currentSession.end()
                
                print("🔴 Background: Waiting for session to end (max 1.5 seconds)...")
                for attempt in 0..<15 {  // 2秒→1.5秒に短縮
                    if currentSession.state == .ended {
                        print("🔴 Background: ✅ Session successfully ended after \(attempt * 100)ms")
                        break
                    }
                    try? await Task.sleep(for: .milliseconds(100))
                    
                    if attempt == 14 {
                        print("⚠️ Background: Session did not end within 1.5 seconds, forcing cleanup (state: \(currentSession.state.rawValue))")
                    }
                }
            }
            
            // 🔥 バックグラウンド処理完了後、最終クリーンアップ
            await MainActor.run {
                print("🔴 ========================================")
                print("🔴 FINAL CLEANUP - Clearing all references")
                print("🔴 ========================================")
                
                // 全ての参照を完全にクリア
                self.session = nil
                self.builder = nil
                
                // 全てのタイマーを再度停止（念のため）
                self.stopTimer()
                self.stopStepCountMonitoring()
                
                #if targetEnvironment(simulator)
                self.stopSimulatorDataGeneration()
                #endif
                
                // メトリクスをリセット
                self.errorMessage = nil
                self.workoutName = ""
                self.resetMetrics()
                
                print("🔴 ✅ Complete cleanup finished")
                print("🔴 isWorkoutActive: \(self.isWorkoutActive)")
                print("🔴 isPaused: \(self.isPaused)")
                print("🔴 session: \(self.session == nil ? "nil ✅" : "NOT NIL ❌")")
                print("🔴 builder: \(self.builder == nil ? "nil ✅" : "NOT NIL ❌")")
                print("🔴 timer: \(self.timer == nil ? "nil ✅" : "NOT NIL ❌")")
                print("🔴 stepCountTimer: \(self.stepCountTimer == nil ? "nil ✅" : "NOT NIL ❌")")
                
                #if targetEnvironment(simulator)
                print("🔴 simulatorDataTimer: \(self.simulatorDataTimer == nil ? "nil ✅" : "NOT NIL ❌")")
                #endif
                
                print("🔴 ========================================")
                print("🔴 READY FOR NEW WORKOUT")
                print("🔴 ========================================")
            }
        }
    }
    
    // MARK: - Timer
    
    private func startTimer() {
        // 既存のタイマーがあれば停止
        stopTimer()
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // セッションの状態に関わらず経過時間を更新（一時停止中も表示するため）
            Task { @MainActor in
                guard let session = self.session else { return }
                self.elapsedTime = session.startDate?.timeIntervalSinceNow.magnitude ?? 0
            }
        }
        
        // タイマーをRunLoopに追加（バックグラウンドでも動作するように）
        RunLoop.current.add(timer!, forMode: .common)
        
        print("⏱️ Timer started")
    }
    
    private func stopTimer() {
        if timer != nil {
            timer?.invalidate()
            timer = nil
            print("⏱️ Timer stopped and cleared")
        }
    }
    
    // MARK: - Simulator Mock Data
    
    #if targetEnvironment(simulator)
    private func startSimulatorDataGeneration() {
        // 既存のタイマーがあれば停止
        stopSimulatorDataGeneration()
        
        print("⚠️ Simulator: Starting mock data generation (with realistic GPS noise)")
        
        // 初期化
        simulatorDistance = 0.0
        simulatorSteps = 0.0
        maxDistance = 0.0
        maxCalories = 0.0
        maxStepCount = 0.0
        
        // 1秒ごとにデータを更新（ウォーキングペース: 約1.4m/s = 5km/h）
        simulatorDataTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            Task { @MainActor in
                // 🔥 重要: 一時停止中でもラップ記録のため、距離は内部的に増加させ続ける
                
                // 🔧 実機に近いランダムな揺らぎを追加
                let baseSpeed = 1.4  // 基本速度: 5km/h
                
                // GPS精度のシミュレーション（初期は不安定、徐々に安定）
                let elapsedSeconds = self.elapsedTime
                let gpsStabilityFactor: Double
                
                if elapsedSeconds < 30 {
                    // 最初の30秒: GPS不安定（大きな揺らぎ）
                    gpsStabilityFactor = 0.5
                    let variation = Double.random(in: -0.5...0.5)  // ±0.5m の大きな揺らぎ
                    let noisySpeed = max(0, baseSpeed + variation)
                    self.simulatorDistance += noisySpeed
                    
                } else if elapsedSeconds < 60 {
                    // 30〜60秒: GPS安定化中（中程度の揺らぎ）
                    gpsStabilityFactor = 0.8
                    let variation = Double.random(in: -0.3...0.3)  // ±0.3m の揺らぎ
                    let noisySpeed = max(0, baseSpeed + variation)
                    self.simulatorDistance += noisySpeed
                    
                } else {
                    // 60秒以降: GPS安定（小さな揺らぎ）
                    gpsStabilityFactor = 1.0
                    let variation = Double.random(in: -0.1...0.1)  // ±0.1m の小さな揺らぎ
                    let noisySpeed = max(0, baseSpeed + variation)
                    self.simulatorDistance += noisySpeed
                }
                
                // 🔥 一時停止中でもラップ記録のため、maxDistanceは常に更新
                // ただし、UI表示（distance）は一時停止中は更新しない
                if !self.isPaused {
                    // 通常時: UI表示も更新
                    self.updateDistance(self.simulatorDistance)
                } else {
                    // 一時停止中: 内部的な最大距離のみ更新（UI表示は凍結）
                    // 履歴に追加
                    if self.simulatorDistance > self.maxDistance {
                        self.recentDistanceUpdates.append(self.simulatorDistance)
                        if self.recentDistanceUpdates.count > self.maxDistanceHistory {
                            self.recentDistanceUpdates.removeFirst()
                        }
                        
                        // スムージング: 移動平均を使用
                        let smoothedDistance = self.recentDistanceUpdates.reduce(0, +) / Double(self.recentDistanceUpdates.count)
                        
                        // 内部的な最大値を更新（ラップ記録用）
                        self.maxDistance = max(self.maxDistance, smoothedDistance)
                        print("⏸️ Paused - Internal distance updated: \(String(format: "%.2f", self.maxDistance))m (UI frozen at \(String(format: "%.2f", self.distance))m)")
                    }
                }
                
                // 🔥 ラップ記録用に即座にペース更新（一時停止中も継続）
                self.updateCurrentPace(newDistance: self.maxDistance)
                
                // 一時停止中はUI表示用のメトリクスは更新しない
                guard !self.isPaused else { 
                    // 10秒ごとにログ出力（一時停止中）
                    let secondsInt = Int(elapsedSeconds)
                    if secondsInt % 10 == 0 && secondsInt > 0 {
                        print("⏸️ PAUSED [\(secondsInt)s]: Internal=\(String(format: "%.2f", self.maxDistance))m, Display=\(String(format: "%.2f", self.distance))m (frozen)")
                    }
                    return 
                }
                
                // 以下は一時停止中でない場合のみ実行（UI表示用のメトリクス更新）
                
                // 歩数を増加（1秒で約2歩、こちらも少し揺らぎを追加）
                let stepVariation = Double.random(in: -0.3...0.3)
                self.simulatorSteps += max(0, 2.0 + stepVariation)
                self.updateStepCount(self.simulatorSteps)
                
                // カロリーを増加（体重70kgの人が5km/hで歩く場合、約3.5kcal/分 = 約0.058kcal/秒）
                let calorieVariation = Double.random(in: -0.01...0.01)
                let calorieIncrease = max(0, 0.058 + calorieVariation)
                
                if self.activeCalories + calorieIncrease > self.maxCalories {
                    self.maxCalories = self.activeCalories + calorieIncrease
                    self.activeCalories = self.maxCalories
                }
                
                // 心拍数をシミュレート（ウォーキング時の典型的な心拍数: 100-120bpm）
                // より現実的な揺らぎパターン（急激な変化を避ける）
                let targetHeartRate = Double.random(in: 100...120)
                let currentAvg = self.averageHeartRate > 0 ? self.averageHeartRate : 110
                let smoothedHeartRate = currentAvg * 0.7 + targetHeartRate * 0.3  // スムーズな変化
                
                self.heartRateHistory.append(smoothedHeartRate)
                
                // 履歴が上限を超えたら古いものを削除
                if self.heartRateHistory.count > self.maxHeartRateHistory {
                    self.heartRateHistory.removeFirst()
                }
                
                self.averageHeartRate = self.heartRateHistory.reduce(0, +) / Double(self.heartRateHistory.count)
                
                // 10秒ごとにログ出力（詳細なデバッグ情報）
                let secondsInt = Int(elapsedSeconds)
                if secondsInt % 10 == 0 && secondsInt > 0 {
                    let stability = Int(gpsStabilityFactor * 100)
                    print("⚠️ Simulator [\(secondsInt)s, GPS:\(stability)%]: Raw=\(String(format: "%.2f", self.simulatorDistance))m, Display=\(String(format: "%.2f", self.distance))m, \(Int(self.stepCount)) steps, \(String(format: "%.1f", self.activeCalories))kcal, HR: \(Int(self.averageHeartRate))bpm, Pace: \(self.currentPaceString)")
                }
            }
        }
        
        RunLoop.current.add(simulatorDataTimer!, forMode: .common)
        print("⚠️ Simulator mock data timer started with realistic GPS simulation")
    }
    
    private func stopSimulatorDataGeneration() {
        if simulatorDataTimer != nil {
            simulatorDataTimer?.invalidate()
            simulatorDataTimer = nil
            simulatorDistance = 0.0
            simulatorSteps = 0.0
            print("⚠️ Simulator mock data generation stopped and cleared")
        }
    }
    #endif
    
    // MARK: - Metrics Update
    
    func updateForStatistics(_ statistics: HKStatistics?) {
        guard let statistics = statistics else { return }
        
        switch statistics.quantityType {
        case HKQuantityType.quantityType(forIdentifier: .heartRate):
            let heartRateUnit = HKUnit.count().unitDivided(by: .minute())
            if let heartRate = statistics.mostRecentQuantity()?.doubleValue(for: heartRateUnit) {
                // 有効な心拍数のみ記録（40〜220bpm）
                guard heartRate >= 40 && heartRate <= 220 else {
                    print("⚠️ Invalid heart rate: \(heartRate) bpm, ignoring")
                    return
                }
                
                // 🔥 一時停止中でも心拍数の履歴は更新（内部記録）
                heartRateHistory.append(heartRate)
                
                // 履歴が上限を超えたら古いものを削除
                if heartRateHistory.count > maxHeartRateHistory {
                    heartRateHistory.removeFirst()
                }
                
                // 平均心拍数を計算
                let calculatedAverage = heartRateHistory.reduce(0, +) / Double(heartRateHistory.count)
                
                // 一時停止中でない場合のみUI表示を更新
                if !isPaused {
                    averageHeartRate = calculatedAverage
                    print("💓 Heart rate: \(Int(heartRate)) bpm, average: \(Int(averageHeartRate)) bpm (samples: \(heartRateHistory.count))")
                } else {
                    print("⏸️ Paused - Internal heart rate updated: \(Int(heartRate)) bpm, average: \(Int(calculatedAverage)) bpm (UI frozen at \(Int(averageHeartRate)) bpm)")
                }
            }
            
        case HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned):
            let energyUnit = HKUnit.kilocalorie()
            let newCalories = statistics.sumQuantity()?.doubleValue(for: energyUnit) ?? 0
            
            // 🔥 一時停止中でも内部的な最大値は更新（UI表示は凍結）
            if newCalories > maxCalories {
                maxCalories = newCalories
                
                // 一時停止中でない場合のみUI表示を更新
                if !isPaused {
                    activeCalories = newCalories
                    print("🔥 Active calories: \(String(format: "%.1f", activeCalories)) kcal")
                } else {
                    print("⏸️ Paused - Internal calories updated: \(String(format: "%.1f", maxCalories)) kcal (UI frozen at \(String(format: "%.1f", activeCalories)) kcal)")
                }
            } else if newCalories < maxCalories {
                // 減少した場合は無視（最大値を維持）
                let decreaseAmount = maxCalories - newCalories
                if decreaseAmount > 0.1 {
                    print("⚠️ Calories decreased from \(String(format: "%.1f", maxCalories)) to \(String(format: "%.1f", newCalories)), keeping max value")
                }
            } else {
                // 同じ値の場合、一時停止中でなければ明示的に設定
                if !isPaused {
                    activeCalories = maxCalories
                }
            }
            
        case HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning):
            let meterUnit = HKUnit.meter()
            let newDistance = statistics.sumQuantity()?.doubleValue(for: meterUnit) ?? 0
            
            // 🔥 一時停止中でもラップ記録のため、内部的な距離は更新し続ける
            if !isPaused {
                // 通常時: UI表示も更新
                updateDistance(newDistance)
            } else {
                // 一時停止中: 内部的な最大距離のみ更新（UI表示は凍結）
                if newDistance > maxDistance {
                    // 履歴に追加
                    recentDistanceUpdates.append(newDistance)
                    if recentDistanceUpdates.count > maxDistanceHistory {
                        recentDistanceUpdates.removeFirst()
                    }
                    
                    // スムージング: 移動平均を使用
                    let smoothedDistance = recentDistanceUpdates.reduce(0, +) / Double(recentDistanceUpdates.count)
                    
                    // 内部的な最大値を更新（ラップ記録用）
                    maxDistance = max(maxDistance, smoothedDistance)
                    print("⏸️ Paused - Internal distance updated: \(String(format: "%.2f", maxDistance))m (UI frozen at \(String(format: "%.2f", distance))m)")
                }
            }
            
            // 🔥 ラップ記録用に即座にペース更新（一時停止中も継続）
            updateCurrentPace(newDistance: maxDistance)
            
        case HKQuantityType.quantityType(forIdentifier: .stepCount):
            let stepUnit = HKUnit.count()
            let newStepCount = statistics.sumQuantity()?.doubleValue(for: stepUnit) ?? 0
            
            // 🔥 一時停止中でも内部的な最大値は更新（UI表示は凍結）
            if newStepCount > maxStepCount {
                maxStepCount = newStepCount
                
                // 一時停止中でない場合のみUI表示を更新
                if !isPaused {
                    stepCount = newStepCount
                    print("🚶 Step count: \(Int(stepCount)) steps")
                } else {
                    print("⏸️ Paused - Internal steps updated: \(Int(maxStepCount)) steps (UI frozen at \(Int(stepCount)) steps)")
                }
            } else if newStepCount < maxStepCount {
                // 減少した場合は無視
                print("⚠️ Step count data decreased (\(Int(newStepCount)) < \(Int(maxStepCount))), ignoring")
            }
            
        default:
            break
        }
    }
    
    private func updateCurrentPace(newDistance: Double) {
        // 距離が有効かチェック
        guard newDistance >= 0 else {
            print("⚠️ Invalid distance: \(newDistance), ignoring pace update")
            return
        }
        
        // 🔥 ラップ記録には内部的な最大距離（maxDistance）を使用（スムージングをバイパス）
        // これにより、UI表示のラグに関係なく、即座にラップを記録できる
        let actualDistance = maxDistance
        let distanceSinceLastKm = actualDistance - lastKmDistance
        
        // 10m ごとにラップを記録（テスト用に大幅短縮）
        let lapDistance: Double = 10.0
        
        if distanceSinceLastKm >= lapDistance {
            if let lastTime = lastKmTimestamp {
                let timeElapsed = Date().timeIntervalSince(lastTime)
                
                // 有効な時間経過かチェック（0秒以上、24時間以内）
                guard timeElapsed > 0 && timeElapsed < 86400 else {
                    print("⚠️ Invalid time elapsed: \(timeElapsed), ignoring lap")
                    return
                }
                
                // 10mあたりの実際のペース（テスト用）
                currentPace = timeElapsed
                
                // ⚠️ テスト用：ランダムなラップタイムを生成（30秒〜90秒の範囲）
                let randomLapTime = Double.random(in: 30.0...90.0)
                
                // ラップタイムを記録（10mの所要時間）
                lapTimes.append(randomLapTime)
                print("🏃 Lap \(lapTimes.count): \(formatLapTime(randomLapTime)) (10m完走, ペース: \(currentPaceString)) [実際:\(formatLapTime(timeElapsed)), ランダム:\(formatLapTime(randomLapTime))]")
                print("🏃   Actual distance: \(String(format: "%.2f", actualDistance))m, Display distance: \(String(format: "%.2f", distance))m")
                
                // ラップ基準点を更新（実際の距離を使用）
                lastKmTimestamp = Date()
                lastKmDistance = actualDistance
            } else {
                // 初回のラップ基準点を設定
                lastKmTimestamp = Date()
                lastKmDistance = actualDistance
                print("🏃 First lap checkpoint set at actual \(String(format: "%.2f", actualDistance))m (display: \(String(format: "%.2f", distance))m)")
            }
        } else if distance > 0 && elapsedTime > 0 {
            // まだラップ到達していない場合は、現在のペースを推定
            // 走行距離（km）あたりの時間を計算
            let distanceInKm = distance / 1000.0
            if distanceInKm > 0 {
                let avgPace = elapsedTime / distanceInKm
                
                // 異常なペース値を防ぐ（0〜60分/km の範囲内）
                if avgPace > 0 && avgPace <= 3600 {
                    currentPace = avgPace
                } else {
                    print("⚠️ Invalid pace calculated: \(avgPace), ignoring")
                }
            }
        }
    }
    
    // ラップタイムのフォーマット
    private func formatLapTime(_ time: TimeInterval) -> String {
        let minutes = Int(time / 60)
        let seconds = Int(time.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // MARK: - Helper Properties
    
    var currentPaceString: String {
        guard currentPace > 0 && currentPace.isFinite else {
            return "--:--"
        }
        
        let minutes = Int(currentPace / 60)
        let seconds = Int(currentPace.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var elapsedTimeString: String {
        let hours = Int(elapsedTime) / 3600
        let minutes = (Int(elapsedTime) % 3600) / 60
        let seconds = Int(elapsedTime) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    private func resetMetrics() {
        print("🔄 ========================================")
        print("🔄 RESETTING ALL METRICS AND STATE")
        print("🔄 ========================================")
        
        // メトリクスをリセット
        distance = 0.0
        maxDistance = 0.0
        lastDisplayedDistance = 0.0
        activeCalories = 0.0
        maxCalories = 0.0
        averageHeartRate = 0.0
        elapsedTime = 0.0
        currentPace = 0.0
        stepCount = 0.0
        maxStepCount = 0.0
        
        // 配列をクリア
        heartRateHistory.removeAll()
        recentDistanceUpdates.removeAll()
        lapTimes.removeAll()
        
        // タイムスタンプをリセット
        lastKmTimestamp = nil
        lastKmDistance = 0.0
        workoutStartDate = nil
        
        // 処理フラグをリセット
        isProcessingPauseResume = false
        
        #if targetEnvironment(simulator)
        simulatorDistance = 0.0
        simulatorSteps = 0.0
        #endif
        
        print("🔄 ✅ All metrics reset to zero")
        print("🔄 ✅ All arrays cleared")
        print("🔄 ✅ All timestamps reset")
        print("🔄 ========================================")
    }
    
    // MARK: - Distance Update (単調増加を保証)
    
    // 距離更新の履歴（スムージング用）
    private var recentDistanceUpdates: [Double] = []
    private let maxDistanceHistory = 5
    private var lastDisplayedDistance: Double = 0.0 // UI表示用の距離
    
    private func updateDistance(_ newDistance: Double) {
        // 負の距離は拒否
        guard newDistance >= 0 else {
            print("⚠️ updateDistance: Invalid negative distance \(newDistance), ignoring")
            return
        }
        
        // 🔧 改善: ワークアウト開始直後（100m未満）はより厳しい閾値を使用
        let isEarlyStage = maxDistance < 100.0
        let maxAllowedJump: Double = isEarlyStage ? 20.0 : 50.0  // 初期は20mまで
        
        // 極端な変化を検出
        if maxDistance > 0 {
            let delta = newDistance - maxDistance
            
            // 急激な増加は無視（GPS誤差の可能性が高い）
            if delta > maxAllowedJump {
                print("⚠️ Distance jump too large: +\(String(format: "%.2f", delta))m (max: \(maxAllowedJump)m), ignoring (likely GPS error)")
                return
            }
            
            // 🔧 改善: 初期段階では減少をより厳しく制限
            let minAllowedDecrease: Double = isEarlyStage ? -1.0 : -2.0
            if delta < minAllowedDecrease {
                print("⚠️ Distance decreased: \(String(format: "%.2f", delta))m (min: \(minAllowedDecrease)m), ignoring")
                return
            }
            
            // わずかな減少は測定誤差として無視
            if delta < 0 && delta > minAllowedDecrease {
                print("⚠️ Minor distance fluctuation: \(String(format: "%.2f", delta))m, ignoring")
                return
            }
        }
        
        if newDistance > maxDistance {
            // 履歴に追加
            recentDistanceUpdates.append(newDistance)
            if recentDistanceUpdates.count > maxDistanceHistory {
                recentDistanceUpdates.removeFirst()
            }
            
            // 🔧 改善: 初期段階ではより多くのサンプルで平均化
            let requiredSamples = isEarlyStage ? 3 : 1
            guard recentDistanceUpdates.count >= requiredSamples else {
                print("📊 Distance buffering: \(recentDistanceUpdates.count)/\(requiredSamples) samples collected")
                return
            }
            
            // スムージング: 移動平均を使用（全履歴の平均）
            let smoothedDistance = recentDistanceUpdates.reduce(0, +) / Double(recentDistanceUpdates.count)
            
            // 内部的な最大値を更新（常に最新の最大値を保持）
            maxDistance = max(maxDistance, smoothedDistance)
            
            // 🔧 改善: 初期段階ではより大きな閾値でUI更新（安定性重視）
            let displayThreshold: Double = isEarlyStage ? 5.0 : 3.0
            let displayDelta = smoothedDistance - lastDisplayedDistance
            
            if displayDelta >= displayThreshold {
                lastDisplayedDistance = smoothedDistance
                distance = smoothedDistance
                
                let stageLabel = isEarlyStage ? "EARLY" : "STABLE"
                print("✅ Distance UI UPDATED [\(stageLabel)]: \(String(format: "%.2f", distance))m (+\(String(format: "%.2f", displayDelta))m, smoothed from \(recentDistanceUpdates.count) samples)")
                
                // ペース計算は外部（updateForStatistics）で実行されるため、ここでは呼ばない
            } else {
                // 内部的には更新されているが、UI表示は変えない（安定性のため）
                if displayDelta > 0 {
                    print("📊 Distance buffered [\(isEarlyStage ? "EARLY" : "STABLE")]: \(String(format: "%.2f", smoothedDistance))m (delta: +\(String(format: "%.2f", displayDelta))m, waiting for \(displayThreshold)m threshold)")
                }
            }
            
        } else if newDistance < maxDistance {
            // 減少した場合は無視（最大値を維持）
            let decreaseAmount = maxDistance - newDistance
            if decreaseAmount > 2.0 {
                print("⚠️ Distance data decreased significantly (\(String(format: "%.2f", newDistance))m < \(String(format: "%.2f", maxDistance))m, -\(String(format: "%.2f", decreaseAmount))m), ignoring")
            }
        }
    }
    
    // MARK: - Step Count Update (単調増加を保証)
    
    private func updateStepCount(_ newStepCount: Double) {
        // 負の歩数は拒否
        guard newStepCount >= 0 else {
            print("⚠️ updateStepCount: Invalid negative count \(newStepCount), ignoring")
            return
        }
        
        if newStepCount > maxStepCount {
            // 増加した場合のみ更新
            maxStepCount = newStepCount
            stepCount = newStepCount
            print("🚶 Step count: \(Int(stepCount)) steps")
            
        } else if newStepCount < maxStepCount {
            // 減少した場合は無視
            print("⚠️ Step count data decreased (\(Int(newStepCount)) < \(Int(maxStepCount))), ignoring")
        }
    }
    
    // MARK: - Step Count Monitoring
    
    private func startStepCountMonitoring() {
        // 既存のタイマーを停止
        stopStepCountMonitoring()
        
        print("🚶 Starting step count monitoring with timer")
        
        // 2秒ごとに歩数を取得
        stepCountTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.fetchStepCount()
            }
        }
        
        RunLoop.current.add(stepCountTimer!, forMode: .common)
    }
    
    private func fetchStepCount() async {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount),
              let startDate = workoutStartDate else {
            print("⚠️ Cannot fetch step count - stepType or startDate is nil")
            return
        }
        
        let now = Date()
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: now, options: .strictStartDate)
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let query = HKStatisticsQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                Task { @MainActor in
                    if let error = error {
                        print("❌ Step count query error: \(error.localizedDescription)")
                        continuation.resume()
                        return
                    }
                    
                    if let sum = result?.sumQuantity() {
                        let steps = sum.doubleValue(for: .count())
                        
                        // 専用メソッドで歩数を更新（単調増加を保証）
                        self.updateStepCount(steps)
                    } else {
                        print("⚠️ No step count data available from query")
                    }
                    
                    continuation.resume()
                }
            }
            
            self.healthStore.execute(query)
        }
    }
    
    private func stopStepCountMonitoring() {
        if stepCountTimer != nil {
            stepCountTimer?.invalidate()
            stepCountTimer = nil
            print("🚶 Step count monitoring stopped and cleared")
        }
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            print("🔄 ========================================")
            print("🔄 Workout state changed: \(fromState.rawValue) → \(toState.rawValue)")
            print("🔄 Current session matches: \(workoutSession === session)")
            print("🔄 Date: \(date)")
            print("🔄 ========================================")
            
            // 現在のセッションでない場合は無視
            guard workoutSession === session else {
                print("⚠️ State change from different session, ignoring")
                return
            }
            
            switch toState {
            case .notStarted:
                print("🔄 Workout not started")
                
            case .running:
                print("🔄 Workout is now RUNNING")
                
                // 🔥 一時停止から再開した場合、UI表示を内部値に同期
                if isPaused {
                    syncUIWithInternalValues()
                }
                
                isPaused = false
                
                // タイマーが停止している場合は再開
                if timer == nil {
                    print("🔄 Timer was nil, starting timer")
                    startTimer()
                }
                print("🔄 ✅ isPaused = false")
                
            case .paused:
                print("🔄 Workout is now PAUSED")
                isPaused = true
                print("🔄 ✅ isPaused = true")
                // 一時停止中もタイマーは動かし続ける（経過時間を正確に表示するため）
                
            case .ended:
                print("🔄 ========================================")
                print("🔄 Workout ENDED (via delegate)")
                print("🔄 ========================================")
                
                // 全てのタイマーを停止
                stopTimer()
                stopStepCountMonitoring()
                
                #if targetEnvironment(simulator)
                stopSimulatorDataGeneration()
                #endif
                
                // UIを更新
                isWorkoutActive = false
                isPaused = false
                isProcessingPauseResume = false
                
                print("🔄 ✅ State cleared: isWorkoutActive=false, isPaused=false")
                print("🔄 ========================================")
                
            case .prepared:
                print("🔄 Workout is prepared")
                
            case .stopped:
                print("🔄 ========================================")
                print("🔄 Workout STOPPED (via delegate)")
                print("🔄 ========================================")
                
                // 全てのタイマーを停止
                stopTimer()
                stopStepCountMonitoring()
                
                #if targetEnvironment(simulator)
                stopSimulatorDataGeneration()
                #endif
                
                // UIを更新
                isWorkoutActive = false
                isPaused = false
                isProcessingPauseResume = false
                
                print("🔄 ✅ State cleared: isWorkoutActive=false, isPaused=false")
                print("🔄 ========================================")
                
            @unknown default:
                print("🔄 Workout in unknown state: \(toState.rawValue)")
            }
            
            // 状態変更後の確認
            try? await Task.sleep(for: .milliseconds(100))
            print("🔄 Final state - isPaused: \(isPaused), session.state: \(workoutSession.state.rawValue)")
        }
    }
    
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            print("❌ ========================================")
            print("❌ Workout session FAILED")
            print("❌ Error: \(error.localizedDescription)")
            print("❌ Failed session matches current: \(workoutSession === session)")
            print("❌ ========================================")
            
            // エラーが発生したセッションが現在のセッションの場合、完全にクリーンアップ
            if workoutSession === session {
                print("❌ Performing complete cleanup after error...")
                
                // デリゲートをクリア
                session?.delegate = nil
                builder?.delegate = nil
                
                // 全てのタイマーを停止
                stopTimer()
                stopStepCountMonitoring()
                
                #if targetEnvironment(simulator)
                stopSimulatorDataGeneration()
                #endif
                
                // 参照をクリア
                session = nil
                builder = nil
                
                // 状態をリセット
                isWorkoutActive = false
                isPaused = false
                isProcessingPauseResume = false
                
                // メトリクスをリセット
                resetMetrics()
                
                // エラーメッセージを設定
                errorMessage = "ワークアウトでエラーが発生しました: \(error.localizedDescription)"
                
                print("❌ ✅ Complete cleanup finished after error")
                print("❌ ========================================")
            }
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        Task { @MainActor in
            print("📊 workoutBuilder didCollectDataOf called")
            print("📊 Collected types count: \(collectedTypes.count)")
            
            for type in collectedTypes {
                guard let quantityType = type as? HKQuantityType else { 
                    print("📊 Type is not a quantity type: \(type)")
                    continue 
                }
                
                let statistics = workoutBuilder.statistics(for: quantityType)
                
                // データ収集のログ
                if quantityType == HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) {
                    let meterUnit = HKUnit.meter()
                    let newDistance = statistics?.sumQuantity()?.doubleValue(for: meterUnit) ?? 0
                    print("📊 Distance collected: \(newDistance)m, Session state: \(session?.state.rawValue ?? -1)")
                } else if quantityType == HKQuantityType.quantityType(forIdentifier: .heartRate) {
                    let heartRateUnit = HKUnit.count().unitDivided(by: .minute())
                    let heartRate = statistics?.mostRecentQuantity()?.doubleValue(for: heartRateUnit) ?? 0
                    print("📊 Heart rate collected: \(heartRate) bpm")
                } else if quantityType == HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
                    let energyUnit = HKUnit.kilocalorie()
                    let calories = statistics?.sumQuantity()?.doubleValue(for: energyUnit) ?? 0
                    print("📊 Calories collected: \(calories) kcal")
                } else if quantityType == HKQuantityType.quantityType(forIdentifier: .stepCount) {
                    let stepUnit = HKUnit.count()
                    let steps = statistics?.sumQuantity()?.doubleValue(for: stepUnit) ?? 0
                    print("📊 Steps collected: \(steps) steps")
                }
                
                updateForStatistics(statistics)
            }
        }
    }
    
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // イベント収集時の処理（必要に応じて実装）
    }
}
