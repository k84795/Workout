//
//  ContentView.swift
//  RUX Watch App
//
//  Created by 山中雄樹 on 2026/03/04.
//

import SwiftUI
import HealthKit

struct ContentView: View {
    @EnvironmentObject private var workoutManager: WorkoutManager
    @StateObject private var locationManager = LocationManager()
    @State private var workoutViewID = 0
    @State private var showCountdown = false
    @State private var pendingWorkoutType: HKWorkoutActivityType?
    @State private var pendingWorkoutName = ""

    var body: some View {
        ZStack {
            Group {
                if workoutManager.isWorkoutActive {
                    WorkoutView(locationManager: locationManager)
                        .id(workoutViewID)
                        .transition(.opacity)
                } else {
                    WorkoutTypeSelectionView(onWorkoutSelected: startWorkoutWithCountdown)
                        .id("selection-view")
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: workoutManager.isWorkoutActive)
            .onChange(of: workoutManager.isWorkoutActive) { _, newValue in
                if newValue {
                    workoutViewID += 1
                    showCountdown = false
                }
            }

            if showCountdown {
                WatchCountdownView(onCancel: {
                    showCountdown = false
                }) {
                    startPendingWorkout()
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showCountdown)
        .onChange(of: workoutManager.errorMessage) { _, newValue in
            if newValue != nil {
                showCountdown = false
            }
        }
        .task {
            // アプリ起動時に権限リクエストとCoreMotion初期化を先行実行
            await workoutManager.prewarm()
            // GPS をワークアウト選択画面の段階から起動しておく
            locationManager.requestAndStart()
        }
    }

    private func startWorkoutWithCountdown(type: HKWorkoutActivityType, name: String) {
        pendingWorkoutType = type
        pendingWorkoutName = name
        // ワークアウト選択ボタンを押した瞬間の GPS 座標をスタート地点として確定
        locationManager.captureStartCoordinate()
        showCountdown = true
    }

    private func startPendingWorkout() {
        guard let type = pendingWorkoutType else { return }
        let name = pendingWorkoutName
        Task { @MainActor in
            await workoutManager.startWorkout(activityType: type, workoutName: name)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(WorkoutManager())
}
