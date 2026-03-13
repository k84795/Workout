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
        let _ = print("🟡 ContentView body evaluated - isWorkoutActive: \(workoutManager.isWorkoutActive)")
        
        return Group {
            if workoutManager.isWorkoutActive {
                WorkoutView()
                    .id("workout-view")
                    .transition(.opacity)
            } else {
                WorkoutTypeSelectionView()
                    .id("selection-view")
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: workoutManager.isWorkoutActive)
        .onChange(of: workoutManager.isWorkoutActive) { oldValue, newValue in
            print("🟡 ContentView: isWorkoutActive changed from \(oldValue) to \(newValue)")
            print("🟡 ContentView: session exists = \(workoutManager.session != nil)")
            print("🟡 ContentView: builder exists = \(workoutManager.builder != nil)")
            
            if !newValue {
                print("🟡 ContentView: Should now display WorkoutTypeSelectionView")
            } else {
                print("🟡 ContentView: Should now display WorkoutView")
            }
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
