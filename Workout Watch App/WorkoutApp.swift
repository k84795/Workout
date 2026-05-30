//
//  WorkoutApp.swift
//  RUX Watch App
//
//  Created by 山中雄樹 on 2026/03/04.
//

import SwiftUI
import HealthKit

@main
struct RUX_Watch_AppApp: App {
    @StateObject private var workoutManager = WorkoutManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(workoutManager)
        }
    }
}

