//
//  WorkoutApp.swift
//  RUX Watch App
//
//  Created by 山中雄樹 on 2026/03/04.
//

import SwiftUI
import HealthKit
import WatchConnectivity

@main
struct RUX_Watch_AppApp: App {
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

