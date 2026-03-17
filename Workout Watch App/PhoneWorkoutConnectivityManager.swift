//
//  PhoneWorkoutConnectivityManager.swift
//  Workout (iPhone App)
//
//  Created on 2026/03/17.
//

#if os(iOS)
import Foundation
import Combine
import WatchConnectivity

// iPhone側 Watch Connectivity Manager for Workout Data
class PhoneWorkoutConnectivityManager: NSObject, ObservableObject {
    static let shared = PhoneWorkoutConnectivityManager()
    
    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil
    
    // WorkoutManagerへの参照（weak）
    weak var workoutManager: WorkoutManager?
    
    private override init() {
        super.init()
        
        if let session = session {
            session.delegate = self
            session.activate()
            print("⌚️ PhoneWorkoutConnectivityManager initialized and WCSession activated")
        }
    }
    
    // Watchからワークアウトデータを受信したときに呼ばれる
    nonisolated private func handleWorkoutDataFromWatch(_ data: [String: Any]) {
        Task { @MainActor in
            guard let workoutManager = workoutManager else {
                print("⚠️ WorkoutManager reference is nil in handleWorkoutDataFromWatch")
                return
            }
            
            print("⌚️ Received workout data from Watch: \(data.keys)")
            
            // 心拍数データを取得
            if let heartRate = data["heartRate"] as? Double {
                print("⌚️💓 Processing heart rate from Watch: \(Int(heartRate)) bpm")
                workoutManager.updateHeartRateFromWatch(heartRate)
            }
            
            // 歩数データを取得
            if let stepCount = data["stepCount"] as? Double {
                print("⌚️🚶 Processing step count from Watch: \(Int(stepCount)) steps")
                workoutManager.updateStepCountFromWatch(stepCount)
            }
            
            // 必要に応じて他のメトリクスも受信可能
            // if let distance = data["distance"] as? Double {
            //     workoutManager.updateDistanceFromWatch(distance)
            // }
        }
    }
}

extension PhoneWorkoutConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("⌚️❌ WCSession activation failed: \(error.localizedDescription)")
        } else {
            print("⌚️✅ WCSession activated with state: \(activationState.rawValue)")
            print("⌚️ Session reachable: \(session.isReachable)")
            print("⌚️ Session paired: \(session.isPaired)")
            print("⌚️ Session watch app installed: \(session.isWatchAppInstalled)")
        }
    }
    
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        print("⌚️ WCSession became inactive")
    }
    
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        print("⌚️ WCSession deactivated - reactivating...")
        session.activate()
    }
    
    // Watch接続状態の変化を監視
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        print("⌚️ Session reachability changed: \(session.isReachable)")
    }
    
    // Watchからのメッセージを受信
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        print("⌚️📩 Received message from Watch with reply handler: \(message)")
        
        // ワークアウトデータの場合
        if let isWorkoutData = message["workoutData"] as? Bool, isWorkoutData {
            handleWorkoutDataFromWatch(message)
            replyHandler(["success": true])
            return
        }
        
        replyHandler([:])
    }
    
    // Watchからのメッセージを受信（返信不要）
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        print("⌚️📩 Received message from Watch (no reply): \(message)")
        
        // ワークアウトデータの場合
        if let isWorkoutData = message["workoutData"] as? Bool, isWorkoutData {
            handleWorkoutDataFromWatch(message)
        }
    }
    
    // WatchからUserInfoを受信（バックグラウンド対応）
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        print("⌚️📦 Received UserInfo from Watch: \(userInfo)")
        
        // ワークアウトデータの場合
        if let isWorkoutData = userInfo["workoutData"] as? Bool, isWorkoutData {
            handleWorkoutDataFromWatch(userInfo)
        }
    }
}
#endif // os(iOS)
