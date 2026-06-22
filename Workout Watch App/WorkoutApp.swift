//
//  WorkoutApp.swift
//  RUX Watch App
//
//  Created by 山中雄樹 on 2026/03/04.
//

import SwiftUI
import HealthKit
import WatchConnectivity
import WatchKit

// クラッシュ・強制終了後にwatchOSがアプリを再起動したとき handleActiveWorkoutRecovery() を受け取る
class WorkoutAppDelegate: NSObject, WKApplicationDelegate {
    func handleActiveWorkoutRecovery() {
        print("🔄 watchOS: handleActiveWorkoutRecovery called")
        NotificationCenter.default.post(name: .workoutSessionRecoveryNeeded, object: nil)
    }
}

@main
struct RUX_Watch_AppApp: App {
    @WKApplicationDelegateAdaptor(WorkoutAppDelegate.self) var appDelegate
    @StateObject private var workoutManager = WorkoutManager()

    init() {
        if WCSession.isSupported() {
            _ = WatchMusicConnectivityManager.shared
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(workoutManager)
        }
    }
}
