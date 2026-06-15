//
//  ContentView.swift
//  RUX Watch App
//
//  Created by 山中雄樹 on 2026/03/04.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var workoutManager: WorkoutManager
    // ワークアウト開始のたびにインクリメントし、WorkoutViewを確実に新規生成する
    @State private var workoutViewID = 0

    var body: some View {
        Group {
            if workoutManager.isWorkoutActive {
                WorkoutView()
                    .id(workoutViewID)
                    .transition(.opacity)
            } else {
                WorkoutTypeSelectionView()
                    .id("selection-view")
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: workoutManager.isWorkoutActive)
        .onChange(of: workoutManager.isWorkoutActive) { _, newValue in
            if newValue {
                workoutViewID += 1
            }
        }
        .task {
            // アプリ起動時に権限リクエストとCoreMotion初期化を先行実行し、
            // 初回ワークアウト開始の遅延・失敗を防ぐ
            await workoutManager.prewarm()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(WorkoutManager())
}
