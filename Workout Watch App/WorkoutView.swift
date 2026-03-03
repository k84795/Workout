//
//  WorkoutView.swift
//  Workout Watch App
//
//  Created by 山中雄樹 on 2026/03/04.
//

import SwiftUI

struct WorkoutView: View {
    @EnvironmentObject var workoutManager: WorkoutManager
    
    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            HStack {
                Text(workoutManager.workoutName)
                    .font(.headline)
                Spacer()
                Button {
                    endWorkout()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.title3)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            // メトリクス表示
            ScrollView {
                VStack(spacing: 16) {
                    // 距離
                    MetricCardView(
                        title: "距離",
                        value: String(format: "%.2f", workoutManager.distance / 1000),
                        unit: "km",
                        icon: "figure.run",
                        color: .blue
                    )
                    
                    // 1km毎のペース
                    MetricCardView(
                        title: "現在のペース",
                        value: workoutManager.currentPaceString,
                        unit: "min/km",
                        icon: "speedometer",
                        color: .orange
                    )
                    
                    // カロリー
                    MetricCardView(
                        title: "カロリー",
                        value: String(format: "%.0f", workoutManager.activeCalories),
                        unit: "kcal",
                        icon: "flame.fill",
                        color: .red
                    )
                    
                    // 平均心拍数
                    MetricCardView(
                        title: "平均心拍数",
                        value: String(format: "%.0f", workoutManager.averageHeartRate),
                        unit: "bpm",
                        icon: "heart.fill",
                        color: .pink
                    )
                    
                    // 経過時間
                    MetricCardView(
                        title: "時間",
                        value: workoutManager.elapsedTimeString,
                        unit: "",
                        icon: "timer",
                        color: .green
                    )
                }
                .padding()
            }
        }
    }
    
    private func endWorkout() {
        Task {
            await workoutManager.endWorkout()
        }
    }
}

struct MetricCardView: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.1))
        )
    }
}

#Preview {
    WorkoutView()
        .environmentObject(WorkoutManager())
}
