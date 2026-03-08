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
    @Published var isWorkoutActive = false
    @Published var isPaused = false
    @Published var workoutName = ""
    @Published var errorMessage: String?
    
    // 権限の状態
    private var isAuthorized = false
    
    // 連続操作の防止
    private var isProcessingPauseResume = false
    
    // メトリクス
    @Published var distance: Double = 0.0 // メートル
    @Published var activeCalories: Double = 0.0
    @Published var averageHeartRate: Double = 0.0
    @Published var elapsedTime: TimeInterval = 0.0
    @Published var stepCount: Double = 0.0 // 歩数
    
    // 1km毎のペース計算用
    private var lastKmTimestamp: Date?
    private var lastKmDistance: Double = 0.0
    @Published var currentPace: TimeInterval = 0.0 // 秒/km
    
    // ラップタイム記録（1kmごと）
    @Published var lapTimes: [TimeInterval] = [] // 各ラップの所要時間（秒）
    
    // 心拍数の履歴（平均計算用）
    private var heartRateHistory: [Double] = []
    
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
    
    func startWorkout(activityType: HKWorkoutActivityType, workoutName: String) async {
        print("🔵 ========================================")
        print("🔵 startWorkout called with: \(workoutName)")
        print("🔵 Current isPaused: \(isPaused)")
        print("🔵 Current isWorkoutActive: \(isWorkoutActive)")
        print("🔵 Existing session: \(session != nil), builder: \(builder != nil)")
        print("🔵 Authorization status: \(isAuthorized)")
        print("🔵 ========================================")
        
        // HealthKitが利用可能か確認
        guard HKHealthStore.isHealthDataAvailable() else {
            print("❌ HealthKit is not available on this device")
            errorMessage = "HealthKit is not available on this device"
            return
        }
        
        print("🔵 HealthKit is available")
        
        // シミュレータでは権限チェックを緩和
        #if targetEnvironment(simulator)
        print("⚠️ Running in simulator, setting authorized to true")
        isAuthorized = true
        #endif
        
        // 権限確認（実機のみ厳密にチェック）
        if !isAuthorized {
            print("⚠️ Not authorized, requesting...")
            requestAuthorization()
            try? await Task.sleep(for: .milliseconds(500))
            
            #if !targetEnvironment(simulator)
            if !isAuthorized {
                print("❌ Authorization failed")
                errorMessage = "HealthKit権限が必要です。iPhoneで許可してください。"
                return
            }
            #endif
        }
        
        print("🔵 Authorization OK, proceeding...")
        errorMessage = nil
        
        // 既存のセッションがあればクリーンアップ
        if let existingSession = session {
            print("🔵 Found existing session (state: \(existingSession.state.rawValue)), cleaning up...")
            
            // デリゲートをクリア
            existingSession.delegate = nil
            builder?.delegate = nil
            
            existingSession.end()
            
            // 簡易的な待機（最大500ms）
            for attempt in 0..<5 {
                if existingSession.state == .ended {
                    print("🔵 Existing session ended after \(attempt * 100)ms")
                    break
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            
            // ビルダーもクリーンアップ
            if let existingBuilder = builder {
                do {
                    try await existingBuilder.endCollection(at: Date())
                    try await existingBuilder.finishWorkout()
                    print("🔵 Existing builder cleaned up")
                } catch {
                    print("⚠️ Error cleaning up builder (continuing anyway): \(error.localizedDescription)")
                }
            }
        }
        
        // 参照をクリア
        session = nil
        builder = nil
        stopTimer()
        stopStepCountMonitoring()
        resetMetrics()
        isWorkoutActive = false
        isPaused = false
        
        #if targetEnvironment(simulator)
        stopSimulatorDataGeneration()
        #endif
        
        // 短い待機（クリーンアップ完了を待つ）
        try? await Task.sleep(for: .milliseconds(300))
        
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activityType
        configuration.locationType = .outdoor
        
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
            
            // デリゲートを設定
            newSession.delegate = self
            newBuilder.delegate = self
            
            print("🔵 Delegates set")
            
            let startDate = Date()
            
            // プロパティに割り当て
            self.session = newSession
            self.builder = newBuilder
            self.workoutName = workoutName
            self.workoutStartDate = startDate
            self.lastKmTimestamp = startDate
            self.lastKmDistance = 0.0
            self.isPaused = false
            
            print("🔵 Starting session with date: \(startDate)")
            newSession.startActivity(with: startDate)
            
            // セッションの開始を待つ
            var sessionReady = false
            
            #if targetEnvironment(simulator)
            // シミュレータでは状態遷移が遅いか不完全なため、短い待機のみ
            print("⚠️ Simulator mode: Using shorter wait time")
            try await Task.sleep(for: .milliseconds(500))
            let currentState = newSession.state
            print("🔵 Simulator session state after 500ms: \(currentState.rawValue)")
            
            // シミュレータでは .prepared または .running を許容
            if currentState == .running || currentState == .prepared || currentState == .notStarted {
                print("🔵 ✅ Session ready in simulator (state: \(currentState.rawValue))")
                sessionReady = true
            }
            #else
            // 実機では .running 状態になるまで待つ
            for attempt in 0..<20 {
                let currentState = newSession.state
                print("🔵 Attempt \(attempt): Session state = \(currentState.rawValue)")
                
                if currentState == .running {
                    print("🔵 ✅ Session is running after \(attempt * 100)ms")
                    sessionReady = true
                    break
                } else if currentState == .prepared {
                    print("🔵 Session is prepared, waiting for running state...")
                }
                
                try await Task.sleep(for: .milliseconds(100))
            }
            #endif
            
            if !sessionReady {
                print("⚠️ Session state: \(newSession.state.rawValue), attempting to start collection anyway")
            }
            
            // beginCollectionを呼び出す
            do {
                print("🔵 Calling beginCollection with date: \(startDate)")
                try await newBuilder.beginCollection(at: startDate)
                print("🔵 ✅ Collection started successfully")
            } catch let error as NSError {
                print("❌ beginCollection failed!")
                print("❌ Error domain: \(error.domain)")
                print("❌ Error code: \(error.code)")
                print("❌ Error description: \(error.localizedDescription)")
                print("❌ Error userInfo: \(error.userInfo)")
                
                #if targetEnvironment(simulator)
                // シミュレータでのエラーは警告として扱い、続行を試みる
                print("⚠️ Simulator: Ignoring beginCollection error and continuing...")
                #else
                // 実機ではエラーを再スロー
                throw error
                #endif
            }
            
            // 歩数監視を開始（ウォーキングの場合）
            if activityType == .walking {
                print("🔵 Starting step count monitoring")
                startStepCountMonitoring()
            }
            
            // タイマー開始
            print("🔵 Starting timer")
            startTimer()
            
            #if targetEnvironment(simulator)
            // シミュレータ用の模擬データ生成を開始
            print("⚠️ Simulator: Starting mock data generation")
            startSimulatorDataGeneration()
            #endif
            
            // 🔥 重要: isWorkoutActiveを更新してUI遷移をトリガー
            print("🔵 ========================================")
            print("🔵 ⭐️ Setting isWorkoutActive = true")
            self.isWorkoutActive = true
            print("🔵 ✅ isWorkoutActive is now: \(self.isWorkoutActive)")
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
                errorMessage = "シミュレータモード: データ収集は制限されています"
                
                // UIは遷移させる（テスト用）
                self.isWorkoutActive = true
                print("⚠️ Simulator: Set isWorkoutActive = true for testing")
                return
            }
            #endif
            
            errorMessage = "ワークアウトの開始に失敗しました: \(error.localizedDescription)"
            
            // エラー時のクリーンアップ
            if let errorSession = session {
                print("❌ Ending failed session...")
                errorSession.delegate = nil
                errorSession.end()
            }
            
            builder?.delegate = nil
            session = nil
            builder = nil
            isWorkoutActive = false
            isPaused = false
            stopTimer()
            stopStepCountMonitoring()
            resetMetrics()
            
            #if targetEnvironment(simulator)
            stopSimulatorDataGeneration()
            #endif
            
            print("❌ Cleanup complete after error")
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
            
            session.resume()
            print("🟢 Resume requested, isPaused set to false")
            
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
                session.resume()
                print("🟢 Resume attempted from unexpected state")
                
                // 処理完了フラグを一定時間後にリセット
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(200))
                    isProcessingPauseResume = false
                    print("🟢 Resume processing complete (from unexpected state)")
                }
            }
        }
    }
    
    nonisolated func endWorkout() async {
        print("🔴 endWorkout called")
        
        // MainActorで値を取得
        let (currentSession, currentBuilder) = await MainActor.run {
            let currentSession = self.session
            let currentBuilder = self.builder
            
            print("🔴 Current session state: \(self.session?.state.rawValue ?? -1)")
            print("🔴 Current builder: \(self.builder != nil)")
            
            // タイマーと歩数監視を停止
            self.stopTimer()
            self.stopStepCountMonitoring()
            
            #if targetEnvironment(simulator)
            self.stopSimulatorDataGeneration()
            #endif
            
            return (currentSession, currentBuilder)
        }
        
        // セッションがアクティブな場合は一旦停止
        if let currentSession = currentSession, currentSession.state == .running {
            print("🔴 Pausing session before ending...")
            currentSession.pause()
            
            // 停止を待つ
            for attempt in 0..<10 {
                if currentSession.state == .paused {
                    print("🔴 Session paused after \(attempt * 100)ms")
                    break
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        
        // ビルダーの終了
        if let currentBuilder = currentBuilder {
            do {
                print("🔴 Ending builder collection...")
                try await currentBuilder.endCollection(at: Date())
                
                print("🔴 Finishing builder workout...")
                try await currentBuilder.finishWorkout()
                print("🔴 Builder finished successfully")
            } catch {
                print("❌ Failed to end builder: \(error.localizedDescription)")
                // エラーが発生してもクリーンアップは続行
            }
        }
        
        // セッションの終了
        if let currentSession = currentSession {
            print("🔴 Ending session...")
            currentSession.end()
            
            print("🔴 Waiting for session to end...")
            for attempt in 0..<50 {
                if currentSession.state == .ended {
                    print("🔴 Session successfully ended after \(attempt * 100)ms")
                    break
                }
                try? await Task.sleep(for: .milliseconds(100))
                
                if attempt % 10 == 0 {
                    print("🔴 Still waiting... session state: \(currentSession.state.rawValue)")
                }
            }
            
            if currentSession.state != .ended {
                print("⚠️ Session did not end within timeout, state: \(currentSession.state.rawValue)")
            }
        }
        
        // 全ての処理が完了してからUIを更新
        await MainActor.run {
            print("🔴 Clearing session references and updating UI")
            
            // デリゲートをクリア
            self.session?.delegate = nil
            self.builder?.delegate = nil
            
            // 参照をクリア
            self.session = nil
            self.builder = nil
            
            // UIの状態を更新
            self.isWorkoutActive = false
            self.isPaused = false
            
            // メトリクスをリセット
            self.resetMetrics()
        }
        
        print("🔴 Workout cleanup complete")
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
        timer?.invalidate()
        timer = nil
        print("⏱️ Timer stopped")
    }
    
    // MARK: - Simulator Mock Data
    
    #if targetEnvironment(simulator)
    private func startSimulatorDataGeneration() {
        // 既存のタイマーがあれば停止
        stopSimulatorDataGeneration()
        
        print("⚠️ Simulator: Starting mock data generation")
        
        // 初期化
        simulatorDistance = 0.0
        simulatorSteps = 0.0
        
        // 1秒ごとにデータを更新（ウォーキングペース: 約1.4m/s = 5km/h）
        simulatorDataTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            Task { @MainActor in
                // 一時停止中は更新しない
                guard !self.isPaused else { return }
                
                // 距離を増加（約1.4m/秒 = 5km/h のウォーキングペース）
                self.simulatorDistance += 1.4
                self.distance = self.simulatorDistance
                
                // 歩数を増加（1秒で約2歩）
                self.simulatorSteps += 2.0
                self.stepCount = self.simulatorSteps
                
                // カロリーを増加（体重70kgの人が5km/hで歩く場合、約3.5kcal/分 = 約0.058kcal/秒）
                self.activeCalories += 0.058
                
                // 心拍数をシミュレート（ウォーキング時の典型的な心拍数: 100-120bpm）
                let randomHeartRate = Double.random(in: 100...120)
                self.heartRateHistory.append(randomHeartRate)
                if self.heartRateHistory.count > 10 {
                    self.heartRateHistory.removeFirst()
                }
                self.averageHeartRate = self.heartRateHistory.reduce(0, +) / Double(self.heartRateHistory.count)
                
                // ペースを更新
                self.updateCurrentPace(newDistance: self.simulatorDistance)
                
                // 100mごとにログ出力
                if Int(self.simulatorDistance) % 100 == 0 && Int(self.simulatorDistance) > 0 {
                    print("⚠️ Simulator data: \(String(format: "%.1f", self.simulatorDistance))m, \(Int(self.simulatorSteps)) steps, \(String(format: "%.1f", self.activeCalories))kcal, HR: \(Int(self.averageHeartRate))bpm")
                }
            }
        }
        
        RunLoop.current.add(simulatorDataTimer!, forMode: .common)
        print("⚠️ Simulator mock data timer started")
    }
    
    private func stopSimulatorDataGeneration() {
        simulatorDataTimer?.invalidate()
        simulatorDataTimer = nil
        simulatorDistance = 0.0
        simulatorSteps = 0.0
        print("⚠️ Simulator mock data generation stopped")
    }
    #endif
    
    // MARK: - Metrics Update
    
    func updateForStatistics(_ statistics: HKStatistics?) {
        guard let statistics = statistics else { return }
        
        switch statistics.quantityType {
        case HKQuantityType.quantityType(forIdentifier: .heartRate):
            let heartRateUnit = HKUnit.count().unitDivided(by: .minute())
            if let heartRate = statistics.mostRecentQuantity()?.doubleValue(for: heartRateUnit) {
                heartRateHistory.append(heartRate)
                averageHeartRate = heartRateHistory.reduce(0, +) / Double(heartRateHistory.count)
            }
            
        case HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned):
            let energyUnit = HKUnit.kilocalorie()
            activeCalories = statistics.sumQuantity()?.doubleValue(for: energyUnit) ?? 0
            
        case HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning):
            let meterUnit = HKUnit.meter()
            let newDistance = statistics.sumQuantity()?.doubleValue(for: meterUnit) ?? 0
            distance = newDistance
            
            // 1km毎のペース計算
            updateCurrentPace(newDistance: newDistance)
            
        case HKQuantityType.quantityType(forIdentifier: .stepCount):
            let stepUnit = HKUnit.count()
            stepCount = statistics.sumQuantity()?.doubleValue(for: stepUnit) ?? 0
            print("🚶 Step count from HealthKit: \(stepCount)")
            
        default:
            break
        }
    }
    
    private func updateCurrentPace(newDistance: Double) {
        let distanceSinceLastKm = newDistance - lastKmDistance
        
        // 🧪 テスト用: 10m毎にラップを記録（ラップ表示を早く確認するため）
        // 本番環境では 1000.0 (1km) に変更してください
        let lapDistance: Double = 10.0
        
        if distanceSinceLastKm >= lapDistance {
            if let lastTime = lastKmTimestamp {
                let timeElapsed = Date().timeIntervalSince(lastTime)
                // テスト時も1kmあたりに換算してペースを表示
                currentPace = timeElapsed * (1000.0 / lapDistance)
                
                // ラップタイムを記録（実際の所要時間）
                lapTimes.append(timeElapsed)
                print("🏃 Lap \(lapTimes.count): \(formatLapTime(timeElapsed)) (距離: \(lapDistance)m)")
                
                lastKmTimestamp = Date()
                lastKmDistance = newDistance
            }
        } else if distance > 0 && elapsedTime > 0 {
            // まだラップ到達していない場合は、現在のペースを推定
            let avgPace = elapsedTime / (distance / 1000.0)
            currentPace = avgPace
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
        print("🔄 Resetting all metrics")
        distance = 0.0
        activeCalories = 0.0
        averageHeartRate = 0.0
        elapsedTime = 0.0
        currentPace = 0.0
        stepCount = 0.0
        heartRateHistory.removeAll()
        lastKmTimestamp = nil
        lastKmDistance = 0.0
        workoutStartDate = nil
        lapTimes.removeAll()
        
        #if targetEnvironment(simulator)
        simulatorDistance = 0.0
        simulatorSteps = 0.0
        #endif
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
        print("🚶 Fetching steps from \(startDate) to \(now)")
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
                        print("🚶 Query returned \(steps) steps")
                        if steps != self.stepCount {
                            print("🚶 Step count updated: \(steps) (previous: \(self.stepCount))")
                            self.stepCount = steps
                        }
                    } else {
                        print("⚠️ No step count data available from query")
                        // データがない場合でも0にはしない（既存の値を保持）
                    }
                    
                    continuation.resume()
                }
            }
            
            self.healthStore.execute(query)
        }
    }
    
    private func stopStepCountMonitoring() {
        stepCountTimer?.invalidate()
        stepCountTimer = nil
        print("🚶 Stopped step count monitoring")
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
            print("🔄 Workout state changed from \(fromState.rawValue) to \(toState.rawValue)")
            print("🔄 Current session matches: \(workoutSession === session)")
            print("🔄 Date of change: \(date)")
            
            // 現在のセッションでない場合は無視
            guard workoutSession === session else {
                print("⚠️ State change from different session, ignoring")
                return
            }
            
            switch toState {
            case .notStarted:
                print("🔄 Workout not started")
                
            case .running:
                print("🔄 Workout is now running")
                print("🔄 Setting isPaused = false")
                isPaused = false
                // タイマーが停止している場合は再開
                if timer == nil {
                    print("🔄 Timer was nil, starting timer")
                    startTimer()
                } else {
                    print("🔄 Timer already running")
                }
                print("🔄 isPaused is now: \(isPaused)")
                
            case .paused:
                print("🔄 Workout is now paused")
                print("🔄 Setting isPaused = true")
                isPaused = true
                print("🔄 isPaused is now: \(isPaused)")
                // 一時停止中もタイマーは動かし続ける（経過時間を正確に表示するため）
                
            case .ended:
                print("🔄 Workout ended")
                print("🔄 Current session ended, cleaning up references")
                stopTimer()
                
            case .prepared:
                print("🔄 Workout is prepared")
                
            case .stopped:
                print("🔄 Workout is stopped")
                stopTimer()
                
            @unknown default:
                print("🔄 Workout in unknown state: \(toState.rawValue)")
            }
            
            // 状態変更後、少し待ってからUIが正しく更新されたか確認
            try? await Task.sleep(for: .milliseconds(100))
            print("🔄 After state change - isPaused: \(isPaused), session.state: \(workoutSession.state.rawValue)")
        }
    }
    
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            print("❌ Workout session failed: \(error.localizedDescription)")
            print("❌ Failed session matches current: \(workoutSession === session)")
            
            // エラーが発生したセッションが現在のセッションの場合、クリーンアップ
            if workoutSession === session {
                print("❌ Cleaning up failed session")
                session = nil
                builder = nil
                isWorkoutActive = false
                isPaused = false
                stopTimer()
                resetMetrics()
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
