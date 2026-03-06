//
//  WorkoutTypeSelectionView.swift
//  Workout Watch App
//
//  Created by 山中雄樹 on 2026/03/04.
//

import SwiftUI
import HealthKit

struct WorkoutTypeSelectionView: View {
    @Environment(WorkoutManager.self) private var workoutManager
    @State private var isStarting = false
    
    let workoutTypes: [(name: String, type: HKWorkoutActivityType, icon: String, color: Color)] = [
        ("ウォーキング", .walking, "figure.walk", .green),
        ("ジョギング", .running, "figure.run", .orange),
        ("ランニング", .running, "figure.run.circle", .red)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                    .disabled(isStarting)
                }
            }
            .listStyle(.plain)
        }
    }
    
    private func startWorkout(type: HKWorkoutActivityType, name: String) {
        guard !isStarting else { 
            print("⚠️ Already starting, ignoring tap")
            return 
        }
        
        guard !workoutManager.isWorkoutActive else {
            print("⚠️ Workout already active, ignoring tap")
            return
        }
        
        print("🟢 Button tapped: \(name)")
        print("🟢 Current isWorkoutActive: \(workoutManager.isWorkoutActive)")
        print("🟢 Current session exists: \(workoutManager.session != nil)")
        
        isStarting = true
        
        Task { @MainActor in
            print("🟢 Starting workout task...")
            await workoutManager.startWorkout(activityType: type, workoutName: name)
            print("🟢 After startWorkout, isWorkoutActive: \(workoutManager.isWorkoutActive)")
            
            // ワークアウトが正常に開始されたか確認
            if workoutManager.isWorkoutActive {
                print("🟢 ✅ Workout started successfully!")
            } else {
                print("⚠️ Workout did not start, resetting UI")
            }
            
            // 起動状態をリセット
            try? await Task.sleep(for: .milliseconds(500))
            isStarting = false
            print("🟢 UI ready for next workout")
        }
    }
}

#Preview {
    WorkoutTypeSelectionView()
        .environment(WorkoutManager())
}
