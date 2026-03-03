//
//  ContentView.swift
//  Workout Watch App
//
//  Created by 山中雄樹 on 2026/03/04.
//

import SwiftUI

struct ContentView: View {
    @Environment(WorkoutManager.self) var workoutManager
    
    var body: some View {
        if workoutManager.isWorkoutActive {
            WorkoutView()
        } else {
            WorkoutTypeSelectionView()
        }
    }
}

#Preview {
    ContentView()
        .environment(WorkoutManager())
}
