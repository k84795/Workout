//
//  WorkoutManager.swift
//  Workout Watch App
//
//  Created by 山中雄樹 on 2026/03/04.
//

import Foundation
import HealthKit

@MainActor
@Observable
class WorkoutManager: NSObject {
    let healthStore = HKHealthStore()
    
    // ワークアウトセッション
    var session: HKWorkoutSession?
    var builder: HKLiveWorkoutBuilder?
    
    // ワークアウト状態
    var isWorkoutActive = false
    var isPaused = false
    var workoutName = ""
    
    // 権限の状態
    private var isAuthorized = false
    
    // 連続操作の防止
    private var isProcessingPauseResume = false
    
    // メトリクス
    var distance: Double = 0.0 // メートル
    var activeCalories: Double = 0.0
    var averageHeartRate: Double = 0.0
    var elapsedTime: TimeInterval = 0.0
    
    // 1km毎のペース計算用
    private var lastKmTimestamp: Date?
    private var lastKmDistance: Double = 0.0
    var currentPace: TimeInterval = 0.0 // 秒/km
    
    // 心拍数の履歴（平均計算用）
    private var heartRateHistory: [Double] = []
    
    // タイマー
    private var timer: Timer?
    
    override init() {
        super.init()
        requestAuthorization()
        checkAuthorizationStatus()
    }
    
    private func checkAuthorizationStatus() {
        let typesToCheck = [
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!
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
            HKObjectType.activitySummaryType()
        ]
        
        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { [weak self] success, error in
            Task { @MainActor in
                if let error = error {
                    print("❌ Authorization failed: \(error.localizedDescription)")
                    self?.isAuthorized = false
                } else {
                    print("✅ HealthKit authorization success: \(success)")
                    self?.isAuthorized = success
                }
            }
        }
    }
    
    // MARK: - Workout Control
    
    func startWorkout(activityType: HKWorkoutActivityType, workoutName: String) async {
        print("🔵 startWorkout called with: \(workoutName)")
        print("🔵 Current isPaused: \(isPaused)")
        print("🔵 Current isWorkoutActive: \(isWorkoutActive)")
        print("🔵 Existing session: \(session != nil), builder: \(builder != nil)")
        print("🔵 Authorization status: \(isAuthorized)")
        
        // 既存のセッションがあればクリーンアップ
        if let existingSession = session {
            print("🔵 Found existing session (state: \(existingSession.state.rawValue)), cleaning up...")
            
            // 既存のビルダーもクリーンアップ
            if let existingBuilder = builder {
                do {
                    print("🔵 Cleaning up existing builder...")
                    try await existingBuilder.endCollection(at: Date())
                    try await existingBuilder.finishWorkout()
                    print("🔵 Existing builder cleaned up")
                } catch {
                    print("⚠️ Error cleaning up builder: \(error.localizedDescription)")
                }
            }
            
            // セッションを終了
            existingSession.end()
            
            // セッションの終了を待つ
            print("🔵 Waiting for existing session to end...")
            for attempt in 0..<30 { // 最大3秒待つ
                if existingSession.state == .ended {
                    print("🔵 Existing session ended successfully after \(attempt * 100)ms")
                    break
                }
                try? await Task.sleep(for: .milliseconds(100))
                
                if attempt % 10 == 0 && attempt > 0 {
                    print("🔵 Still waiting for session to end... (attempt \(attempt))")
                }
            }
            
            if existingSession.state != .ended {
                print("⚠️ Existing session did not end properly (state: \(existingSession.state.rawValue)), forcing cleanup")
            }
        }
        
        // 参照を完全にクリア
        session = nil
        builder = nil
        stopTimer()
        resetMetrics()
        
        // 状態を確実にリセット
        isWorkoutActive = false
        isPaused = false
        
        // HealthKitのクリーンアップを確実にするため待機
        print("🔵 Waiting for HealthKit cleanup...")
        try? await Task.sleep(for: .milliseconds(500))
        
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activityType
        configuration.locationType = .outdoor
        
        do {
            print("🔵 Creating new workout session...")
            let newSession = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let newBuilder = newSession.associatedWorkoutBuilder()
            
            print("🔵 New session created successfully")
            print("🔵 New builder created successfully")
            
            newBuilder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )
            
            print("🔵 Data source configured: \(newBuilder.dataSource != nil)")
            
            // デリゲートを設定
            newSession.delegate = self
            newBuilder.delegate = self
            
            print("🔵 Delegates configured")
            
            // プロパティに割り当て
            self.session = newSession
            self.builder = newBuilder
            self.workoutName = workoutName
            
            let startDate = Date()
            
            print("🔵 Starting session activity...")
            newSession.startActivity(with: startDate)
            
            // セッションの開始を待つ
            print("🔵 Waiting for session to start...")
            for attempt in 0..<20 {
                if newSession.state == .running {
                    print("🔵 Session started successfully after \(attempt * 50)ms")
                    break
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
            
            if newSession.state != .running {
                print("⚠️ Session is not running yet (state: \(newSession.state.rawValue)), continuing anyway")
            }
            
            // コレクション開始
            print("🔵 Beginning collection...")
            try await newBuilder.beginCollection(at: startDate)
            print("🔵 Collection started successfully")
            
            // 状態を更新（最後に実行してUIを切り替える）
            print("🔵 Setting isWorkoutActive = true")
            isWorkoutActive = true
            isPaused = false
            lastKmTimestamp = startDate
            lastKmDistance = 0.0
            
            // タイマー開始
            startTimer()
            
            // 最終確認
            print("🔵 ✅ Workout startup complete!")
            print("🔵 Final state - isWorkoutActive: \(isWorkoutActive), isPaused: \(isPaused)")
            print("🔵 Session state: \(newSession.state.rawValue)")
            print("🔵 Builder has data source: \(newBuilder.dataSource != nil)")
            
        } catch {
            print("❌ Failed to start workout: \(error.localizedDescription)")
            print("❌ Error details: \(error)")
            
            // エラーの場合は状態を完全にリセット
            if let errorSession = session {
                print("❌ Cleaning up failed session...")
                errorSession.end()
                // 終了を待つ
                for _ in 0..<10 {
                    if errorSession.state == .ended { 
                        print("❌ Failed session cleaned up")
                        break 
                    }
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            
            // ビルダーのクリーンアップ
            if let errorBuilder = builder {
                do {
                    try await errorBuilder.endCollection(at: Date())
                    try await errorBuilder.finishWorkout()
                    print("❌ Failed builder cleaned up")
                } catch {
                    print("❌ Error cleaning up failed builder: \(error.localizedDescription)")
                }
            }
            
            session = nil
            builder = nil
            isWorkoutActive = false
            isPaused = false
            stopTimer()
            resetMetrics()
            
            print("❌ Error cleanup complete")
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
            try? await Task.sleep(for: .milliseconds(500))
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
                try? await Task.sleep(for: .milliseconds(500))
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
                    try? await Task.sleep(for: .milliseconds(500))
                    isProcessingPauseResume = false
                    print("🟢 Resume processing complete (from unexpected state)")
                }
            }
        }
    }
    
    func endWorkout() async {
        print("🔴 endWorkout called")
        print("🔴 Current session state: \(session?.state.rawValue ?? -1)")
        print("🔴 Current builder: \(builder != nil)")
        
        // タイマーを先に停止
        stopTimer()
        
        // セッションの参照を保持
        let currentSession = session
        let currentBuilder = builder
        
        // 参照を即座にクリア（新しいワークアウト開始をブロックしないため）
        session = nil
        builder = nil
        
        // UIの状態を先に更新（即座に画面を切り替える）
        isWorkoutActive = false
        isPaused = false
        
        // メトリクスをリセット
        resetMetrics()
        
        // バックグラウンドでクリーンアップを実行
        Task.detached(priority: .userInitiated) {
            // ビルダーの終了を先に実行
            if let currentBuilder = currentBuilder {
                do {
                    print("🔴 Ending builder collection...")
                    try await currentBuilder.endCollection(at: Date())
                    print("🔴 Finishing builder workout...")
                    try await currentBuilder.finishWorkout()
                    print("🔴 Builder finished successfully")
                } catch {
                    print("❌ Failed to end builder: \(error.localizedDescription)")
                }
                
                // ビルダーの処理完了を待つ
                try? await Task.sleep(for: .milliseconds(200))
            }
            
            // セッションの終了
            if let currentSession = currentSession {
                print("🔴 Ending session...")
                await MainActor.run {
                    currentSession.end()
                }
                
                print("🔴 Waiting for session to end...")
                // セッションの状態が.endedになるまで待機
                for attempt in 0..<50 { // 最大5秒待つ
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
                    print("⚠️ Forcing cleanup despite session state")
                }
            }
            
            // 最終的なクリーンアップ待機
            try? await Task.sleep(for: .milliseconds(500))
            
            await MainActor.run {
                print("🔴 Workout cleanup complete")
                print("🔴 Session is nil: \(self.session == nil)")
                print("🔴 Builder is nil: \(self.builder == nil)")
                print("🔴 isWorkoutActive: \(self.isWorkoutActive)")
            }
        }
    }
    
    // MARK: - Timer
    
    private func startTimer() {
        // 既存のタイマーがあれば停止
        stopTimer()
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self,
                      let session = self.session else { return }
                
                // セッションの状態に関わらず経過時間を更新（一時停止中も表示するため）
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
            
        default:
            break
        }
    }
    
    private func updateCurrentPace(newDistance: Double) {
        let distanceSinceLastKm = newDistance - lastKmDistance
        
        // 1km (1000m) 毎にペースを更新
        if distanceSinceLastKm >= 1000 {
            if let lastTime = lastKmTimestamp {
                let timeElapsed = Date().timeIntervalSince(lastTime)
                currentPace = timeElapsed // 1kmあたりの秒数
                
                lastKmTimestamp = Date()
                lastKmDistance = newDistance
            }
        } else if distance > 0 && elapsedTime > 0 {
            // まだ1km到達していない場合は、現在のペースを推定
            let avgPace = elapsedTime / (distance / 1000.0)
            currentPace = avgPace
        }
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
        heartRateHistory.removeAll()
        lastKmTimestamp = nil
        lastKmDistance = 0.0
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
                }
                
                updateForStatistics(statistics)
            }
        }
    }
    
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // イベント収集時の処理（必要に応じて実装）
    }
}
