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
        
        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { success, error in
            if let error = error {
                print("Authorization failed: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Workout Control
    
    func startWorkout(activityType: HKWorkoutActivityType, workoutName: String) async {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activityType
        configuration.locationType = .outdoor
        
        do {
            session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            builder = session?.associatedWorkoutBuilder()
            
            builder?.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )
            
            session?.delegate = self
            builder?.delegate = self
            
            self.workoutName = workoutName
            
            let startDate = Date()
            session?.startActivity(with: startDate)
            try await builder?.beginCollection(at: startDate)
            
            isWorkoutActive = true
            lastKmTimestamp = startDate
            lastKmDistance = 0.0
            
            // タイマー開始
            startTimer()
            
        } catch {
            print("Failed to start workout: \(error.localizedDescription)")
        }
    }
    
    func pauseWorkout() {
        session?.pause()
        isPaused = true
    }
    
    func resumeWorkout() {
        session?.resume()
        isPaused = false
    }
    
    func endWorkout() async {
        session?.end()
        
        do {
            try await builder?.endCollection(at: Date())
            try await builder?.finishWorkout()
        } catch {
            print("Failed to end workout: \(error.localizedDescription)")
        }
        
        stopTimer()
        resetMetrics()
        isWorkoutActive = false
        isPaused = false
    }
    
    // MARK: - Timer
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self,
                      let session = self.session,
                      session.state == .running else { return }
                
                self.elapsedTime = session.startDate?.timeIntervalSinceNow.magnitude ?? 0
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
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
            switch toState {
            case .running:
                print("Workout started")
            case .ended:
                print("Workout ended")
            default:
                break
            }
        }
    }
    
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        print("Workout session failed: \(error.localizedDescription)")
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        Task { @MainActor in
            for type in collectedTypes {
                guard let quantityType = type as? HKQuantityType else { continue }
                let statistics = workoutBuilder.statistics(for: quantityType)
                updateForStatistics(statistics)
            }
        }
    }
    
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // イベント収集時の処理（必要に応じて実装）
    }
}
