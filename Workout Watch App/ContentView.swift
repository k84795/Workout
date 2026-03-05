//
//  ContentView.swift
//  Workout Watch App
//
//  Created by 山中雄樹 on 2026/03/04.
//

import SwiftUI

struct ContentView: View {
    @Environment(WorkoutManager.self) private var workoutManager
    
    var body: some View {
        @Bindable var manager = workoutManager
        
        Group {
            if manager.isWorkoutActive {
                WorkoutView()
                    .transition(.opacity)
            } else {
                WorkoutTypeSelectionView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: manager.isWorkoutActive)
        .onChange(of: manager.isWorkoutActive) { oldValue, newValue in
            print("🟡 ContentView: isWorkoutActive changed from \(oldValue) to \(newValue)")
        }
    }
}

#Preview {
    ContentView()
        .environment(WorkoutManager())
}
