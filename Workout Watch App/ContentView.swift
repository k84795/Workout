//
//  ContentView.swift
//  Workout Watch App
//
//  Created by 山中雄樹 on 2026/03/04.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var workoutManager: WorkoutManager
    
    var body: some View {
        ZStack {
            if workoutManager.isWorkoutActive {
                WorkoutView()
                    .id("workout-view")
            } else {
                WorkoutTypeSelectionView()
                    .id("selection-view")
            }
        }
        .animation(.easeInOut(duration: 0.3), value: workoutManager.isWorkoutActive)
        .onChange(of: workoutManager.isWorkoutActive) { oldValue, newValue in
            print("🟡 ContentView: isWorkoutActive changed from \(oldValue) to \(newValue)")
            print("🟡 ContentView: session exists = \(workoutManager.session != nil)")
            print("🟡 ContentView: builder exists = \(workoutManager.builder != nil)")
        }
        .task {
            print("🟡 ContentView: Initial state - isWorkoutActive = \(workoutManager.isWorkoutActive)")
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(WorkoutManager())
}
