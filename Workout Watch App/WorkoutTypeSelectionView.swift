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
    @State private var isRequestingPermission = false
    
    let workoutTypes: [(name: String, type: HKWorkoutActivityType, icon: String, color: Color)] = [
        ("ウォーキング", .walking, "walking", .green),
        ("ジョギング", .running, "jogging", .blue),
        ("ランニング", .running, "running", .red)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 🔥 改善: 権限が未確定または拒否されている場合、権限リクエストセクションを表示
            if workoutManager.authorizationStatus != .authorized {
                VStack(spacing: 8) {
                    if workoutManager.authorizationStatus == .requesting {
                        ProgressView()
                            .progressViewStyle(.circular)
                        Text("権限を確認中...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if workoutManager.authorizationStatus == .denied {
                        Text("HealthKit権限が必要です")
                            .font(.headline)
                            .foregroundColor(.orange)
                        
                        Button {
                            requestPermission()
                        } label: {
                            HStack {
                                Image(systemName: "heart.text.square")
                                Text("権限を許可")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                        
                        Text("ワークアウトデータを記録するには、HealthKitへのアクセス権限が必要です。")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    } else {
                        Button {
                            requestPermission()
                        } label: {
                            HStack {
                                Image(systemName: "heart.text.square")
                                Text("HealthKit権限を許可")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }
                }
                .padding(.vertical, 12)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            
            List {
                ForEach(workoutTypes, id: \.name) { workout in
                    HStack {
                        Image(workout.icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 30, height: 30)
                        
                        Text(workout.name)
                            .font(.system(size: 19.5, weight: .semibold))
                            .foregroundColor(workout.color)
                        
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if !isStarting {
                            startWorkout(type: workout.type, name: workout.name)
                        }
                    }
                    .listRowBackground(Color.clear)
                    // 🔥 改善: 権限がない場合はワークアウトボタンを無効化
                    .opacity(workoutManager.authorizationStatus == .authorized ? 1.0 : 0.5)
                    .disabled(workoutManager.authorizationStatus != .authorized)
                }
            }
            .listStyle(.plain)
            .tint(.clear)
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
        .onAppear {
            // 🔥 改善: 画面表示時に権限状態を確認
            if workoutManager.authorizationStatus == .notDetermined {
                requestPermission()
            }
        }
    }
    
    private func requestPermission() {
        guard !isRequestingPermission else { return }
        
        isRequestingPermission = true
        
        Task {
            await workoutManager.requestAuthorization()
            isRequestingPermission = false
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
