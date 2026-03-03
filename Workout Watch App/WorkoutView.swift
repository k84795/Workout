//
//  WorkoutView.swift
//  Workout Watch App
//
//  Created by 山中雄樹 on 2026/03/04.
//

import SwiftUI

struct WorkoutView: View {
    @Environment(WorkoutManager.self) var workoutManager
    
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // ヘッダー - コンパクト化
                HStack {
                    Text(workoutManager.workoutName)
                        .font(.caption)
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding(.horizontal, 4)
                
                // 主要メトリクス - 距離とペースを大きく表示
                VStack(spacing: 4) {
                    // 距離
                    VStack(spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(String(format: "%.2f", workoutManager.distance / 1000))
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                            Text("km")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 4) {
                            Image(systemName: "figure.run")
                                .font(.caption2)
                            Text("距離")
                                .font(.caption2)
                        }
                        .foregroundStyle(.blue)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    
                    // ペース
                    VStack(spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(workoutManager.currentPaceString)
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                            Text("min/km")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 4) {
                            Image(systemName: "speedometer")
                                .font(.caption2)
                            Text("ペース")
                                .font(.caption2)
                        }
                        .foregroundStyle(.orange)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                
                // サブメトリクス - 2列グリッド
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 4),
                    GridItem(.flexible(), spacing: 4)
                ], spacing: 4) {
                    // 時間
                    CompactMetricView(
                        icon: "timer",
                        value: workoutManager.elapsedTimeString,
                        label: "時間",
                        color: .green
                    )
                    
                    // カロリー
                    CompactMetricView(
                        icon: "flame.fill",
                        value: String(format: "%.0f", workoutManager.activeCalories),
                        label: "kcal",
                        color: .red
                    )
                    
                    // 心拍数
                    CompactMetricView(
                        icon: "heart.fill",
                        value: String(format: "%.0f", workoutManager.averageHeartRate),
                        label: "bpm",
                        color: .pink
                    )
                    
                    // プレースホルダー（将来の拡張用）
                    CompactMetricView(
                        icon: "figure.walk",
                        value: "--",
                        label: "歩数",
                        color: .purple
                    )
                }
                
                // コントロールボタン
                VStack(spacing: 8) {
                    // 一時停止/再開ボタン
                    Button {
                        togglePause()
                    } label: {
                        HStack {
                            Image(systemName: workoutManager.isPaused ? "play.fill" : "pause.fill")
                                .font(.title3)
                            Text(workoutManager.isPaused ? "再開" : "一時停止")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(workoutManager.isPaused ? .green : .orange)
                    
                    // ワークアウト終了ボタン
                    Button {
                        endWorkout()
                    } label: {
                        Text("ワークアウトを終了")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                .padding(.top, 8)
            }
            .padding(4)
        }
        .ignoresSafeArea(edges: .bottom)
    }
    
    private func togglePause() {
        if workoutManager.isPaused {
            workoutManager.resumeWorkout()
        } else {
            workoutManager.pauseWorkout()
        }
    }
    
    private func endWorkout() {
        Task {
            await workoutManager.endWorkout()
        }
    }
}

// コンパクトなメトリクスビュー
struct CompactMetricView: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}



#Preview {
    WorkoutView()
        .environment(WorkoutManager())
}
