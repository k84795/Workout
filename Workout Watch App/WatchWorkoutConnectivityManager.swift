//
//  WatchWorkoutConnectivityManager.swift
//  Workout Watch App
//
//  Created on 2026/03/17.
//

#if os(watchOS)
import Foundation
import WatchConnectivity
import Combine

// Apple Watch側 Watch Connectivity Manager for Workout Data
class WatchWorkoutConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchWorkoutConnectivityManager()
    
    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil
    
    private override init() {
        super.init()
        
        if let session = session {
            session.delegate = self
            session.activate()
            print("📱 WatchWorkoutConnectivityManager initialized and WCSession activated")
        }
    }
    
    /// iPhoneに心拍数データを送信
    func sendHeartRateToPhone(_ heartRate: Double) {
        guard let session = session else {
            print("⚠️ WCSession is not supported")
            return
        }
        
        // セッションの状態をログ
        print("📱 Session activated: \(session.activationState == .activated)")
        print("📱 iPhone reachable: \(session.isReachable)")
        
        // iPhoneが到達可能かチェック
        guard session.isReachable else {
            print("📱⚠️ iPhone is not reachable, cannot send heart rate")
            // iPhoneが到達不可でもUser Infoで送信を試みる（バックグラウンド転送）
            print("📱 Attempting to send via transferUserInfo as fallback...")
            let userInfo: [String: Any] = [
                "workoutData": true,
                "heartRate": heartRate,
                "timestamp": Date().timeIntervalSince1970
            ]
            session.transferUserInfo(userInfo)
            return
        }
        
        let message: [String: Any] = [
            "workoutData": true,
            "heartRate": heartRate,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        // メッセージを送信（返信不要）
        session.sendMessage(message, replyHandler: { reply in
            print("📱✅ Heart rate message acknowledged by iPhone: \(reply)")
        }) { error in
            print("📱❌ Error sending heart rate to iPhone: \(error.localizedDescription)")
            // エラー時はUser Infoで再試行
            session.transferUserInfo(message)
            print("📱 Retrying with transferUserInfo...")
        }
        
        print("📱💓 Heart rate sent to iPhone: \(Int(heartRate)) bpm")
    }
    
    /// iPhoneに歩数データを送信
    func sendStepCountToPhone(_ stepCount: Double) {
        guard let session = session else {
            print("⚠️ WCSession is not supported")
            return
        }
        
        guard session.isReachable else {
            print("📱⚠️ iPhone is not reachable, cannot send step count")
            // バックグラウンド転送を試行
            let userInfo: [String: Any] = [
                "workoutData": true,
                "stepCount": stepCount,
                "timestamp": Date().timeIntervalSince1970
            ]
            session.transferUserInfo(userInfo)
            print("📱 Step count sent via transferUserInfo: \(Int(stepCount)) steps")
            return
        }
        
        let message: [String: Any] = [
            "workoutData": true,
            "stepCount": stepCount,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        session.sendMessage(message, replyHandler: { reply in
            print("📱✅ Step count message acknowledged by iPhone: \(reply)")
        }) { error in
            print("📱❌ Error sending step count to iPhone: \(error.localizedDescription)")
            // エラー時はUser Infoで再試行
            session.transferUserInfo(message)
            print("📱 Retrying step count with transferUserInfo...")
        }
        
        print("📱🚶 Step count sent to iPhone: \(Int(stepCount)) steps")
    }
    
    /// iPhoneにワークアウトデータを送信（複数のメトリクス）
    func sendWorkoutDataToPhone(heartRate: Double? = nil, distance: Double? = nil, calories: Double? = nil) {
        guard let session = session else {
            print("⚠️ WCSession is not supported")
            return
        }
        
        guard session.isReachable else {
            print("📱 iPhone is not reachable, cannot send workout data")
            return
        }
        
        var message: [String: Any] = ["workoutData": true]
        
        if let heartRate = heartRate {
            message["heartRate"] = heartRate
        }
        if let distance = distance {
            message["distance"] = distance
        }
        if let calories = calories {
            message["calories"] = calories
        }
        
        session.sendMessage(message, replyHandler: nil) { error in
            print("❌ Error sending workout data to iPhone: \(error.localizedDescription)")
        }
        
        print("📱 Workout data sent to iPhone: \(message)")
    }
}

extension WatchWorkoutConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("📱❌ WCSession activation failed: \(error.localizedDescription)")
        } else {
            print("📱✅ WCSession activated with state: \(activationState.rawValue)")
            print("📱 Session reachable: \(session.isReachable)")
        }
    }
    
    // iPhone接続状態の変化を監視
    func sessionReachabilityDidChange(_ session: WCSession) {
        print("📱 Session reachability changed: \(session.isReachable)")
    }
}
#endif // os(watchOS)
