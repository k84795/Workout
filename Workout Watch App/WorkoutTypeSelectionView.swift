//
//  WorkoutTypeSelectionView.swift
//  Workout Watch App
//
//  Created by 山中雄樹 on 2026/03/04.
//

import SwiftUI
import HealthKit

struct WorkoutTypeSelectionView: View {
    @Environment(WorkoutManager.self) var workoutManager
    
    let workoutTypes: [(name: String, type: HKWorkoutActivityType, icon: String, color: Color)] = [
        ("ウォーキング", .walking, "figure.walk", .green),
        ("ジョギング", .running, "figure.run", .orange),
        ("ランニング", .running, "figure.run.circle", .red)
    ]
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(workoutTypes, id: \.name) { workout in
                    Button {
                        startWorkout(type: workout.type, name: workout.name)
                    } label: {
                        HStack {
                            Image(systemName: workout.icon)
                                .font(.title2)
                                .foregroundStyle(workout.color)
                                .frame(width: 40)
                            
                            Text(workout.name)
                                .font(.headline)
                            
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("ワークアウト")
        }
    }
    
    private func startWorkout(type: HKWorkoutActivityType, name: String) {
        Task {
            await workoutManager.startWorkout(activityType: type, workoutName: name)
        }
    }
}

#Preview {
    WorkoutTypeSelectionView()
        .environment(WorkoutManager())
}
