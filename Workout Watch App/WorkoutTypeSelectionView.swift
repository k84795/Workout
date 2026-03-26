//
//  WorkoutTypeSelectionView.swift
//  Workout Watch App
//
//  Created by 山中雄樹 on 2026/03/04.
//

import SwiftUI
import HealthKit

struct WorkoutTypeSelectionView: View {
    @EnvironmentObject private var workoutManager: WorkoutManager
    @State private var isStarting = false
    @State private var showError = false
    
    let workoutTypes: [(name: String, type: HKWorkoutActivityType, icon: String, color: Color)] = [
        ("ウォーキング", .walking, "walking", .green),
        ("ジョギング", .running, "jogging", .blue),
        ("ランニング", .running, "running", .red)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List {
                ForEach(workoutTypes, id: \.name) { workout in
                    Button {
                        startWorkout(type: workout.type, name: workout.name)
                    } label: {
                        HStack(spacing: 8) {
                            Image(workout.icon)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 32, height: 32)
                            
                            Text(workout.name)
                                .font(.body)
                                .foregroundStyle(workout.color)
                            
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                    .disabled(isStarting)
                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                }
            }
            .listStyle(.plain)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {
                workoutManager.errorMessage = nil
            }
        } message: {
            if let errorMessage = workoutManager.errorMessage {
                Text(errorMessage)
            }
        }
        .onChange(of: workoutManager.errorMessage) { oldValue, newValue in
            if newValue != nil {
                showError = true
            }
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
        
        print("🟢 ========================================")
        print("🟢 Button tapped: \(name)")
        print("🟢 Current isWorkoutActive: \(workoutManager.isWorkoutActive)")
        print("🟢 Current session exists: \(workoutManager.session != nil)")
        print("🟢 ========================================")
        
        isStarting = true
        
        Task { @MainActor in
            print("🟢 Starting workout task...")
            
            await workoutManager.startWorkout(activityType: type, workoutName: name)
            
            print("🟢 ========================================")
            print("🟢 After startWorkout completed")
            print("🟢 isWorkoutActive: \(workoutManager.isWorkoutActive)")
            print("🟢 session exists: \(workoutManager.session != nil)")
            print("🟢 session state: \(workoutManager.session?.state.rawValue ?? -1)")
            print("🟢 builder exists: \(workoutManager.builder != nil)")
            print("🟢 errorMessage: \(workoutManager.errorMessage ?? "nil")")
            print("🟢 ========================================")
            
            // 追加の待機時間を入れてUIの更新を確実にする
            try? await Task.sleep(for: .milliseconds(100))
            
            // ワークアウトが正常に開始されたか確認
            if workoutManager.isWorkoutActive {
                print("🟢 ✅ Workout started successfully!")
            } else {
                print("⚠️ ❌ Workout did not start")
                if let error = workoutManager.errorMessage {
                    print("⚠️ Error: \(error)")
                }
            }
            
            // 起動状態をリセット
            isStarting = false
            print("🟢 isStarting reset to false")
        }
    }
}

#Preview {
    WorkoutTypeSelectionView()
        .environmentObject(WorkoutManager())
}
