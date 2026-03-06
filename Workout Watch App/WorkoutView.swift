//
//  WorkoutView.swift
//  Workout Watch App
//
//  Created by 山中雄樹 on 2026/03/04.
//

import SwiftUI

struct WorkoutView: View {
    @Environment(WorkoutManager.self) var workoutManager
    @State private var currentPage = 0
    @State private var scrollViewID = UUID()
    @State private var isBlinking = false
    @State private var shouldScrollToTop = false
    @State private var isTogglingPause = false
    
    var body: some View {
        TabView(selection: $currentPage) {
            // コントロールページ（0番目・左側）
            controlView
                .tag(0)
            
            // メインページ（1番目・右側）
            mainWorkoutView
                .tag(1)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onChange(of: workoutManager.isPaused) { oldValue, newValue in
            // 点滅状態を確実に同期
            if newValue {
                // 一時停止になったら点滅開始
                startBlinking()
            } else {
                // 再開したら点滅停止
                stopBlinking()
            }
        }
        .onChange(of: currentPage) { oldValue, newValue in
            // ページが切り替わったときに一時停止中なら点滅を再開
            if workoutManager.isPaused {
                // 少し遅延させてからアニメーションを再開（TabViewのアニメーション後）
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    startBlinking()
                }
            }
        }
        .onAppear {
            // 初期表示はメイン画面
            currentPage = 1
            // 既に一時停止状態なら点滅を開始
            if workoutManager.isPaused {
                startBlinking()
            }
        }
    }
    
    // メイン画面
    private var mainWorkoutView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 4) {
                    // スクロール位置の起点
                    Color.clear
                        .frame(height: 0)
                        .id("top")
                    
                    // ヘッダー - コンパクト化（時計と同じ高さ）
                    HStack {
                        Text(workoutManager.workoutName)
                            .font(.caption)
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 6)
                    
                    // 主要メトリクス - 距離とペースを大きく表示
                    VStack(spacing: 2) {
                        // 距離
                        VStack(spacing: 0) {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(String(format: "%.2f", workoutManager.distance / 1000))
                                    .font(.system(size: 38, weight: .bold, design: .rounded))
                                Text("km")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 3) {
                                Image(systemName: "figure.run")
                                    .font(.caption2)
                                Text("距離")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.blue)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        
                        // ペース
                        VStack(spacing: 0) {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(workoutManager.currentPaceString)
                                    .font(.system(size: 30, weight: .bold, design: .rounded))
                                Text("min/km")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 3) {
                                Image(systemName: "speedometer")
                                    .font(.caption2)
                                Text("ペース")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.orange)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    
                    // サブメトリクス - 2列グリッド
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 2),
                        GridItem(.flexible(), spacing: 2)
                    ], spacing: 2) {
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
                        
                        // 歩数
                        CompactMetricView(
                            icon: "figure.walk",
                            value: String(format: "%.0f", workoutManager.stepCount),
                            label: "歩数",
                            color: .purple
                        )
                    }
                    
                    // コントロールボタン
                    VStack(spacing: 8) {
                        // 一時停止/再開ボタン
                        Button {
                            guard !isTogglingPause else {
                                print("⚠️ Already toggling pause, ignoring tap")
                                return
                            }
                            
                            let wasPaused = workoutManager.isPaused
                            togglePause()
                            
                            // 一時停止時：その画面に留まる（何もしない）
                            // 再開時：スクロールを一番上に戻す
                            if wasPaused == true {
                                // 再開した直後、スクロールを一番上に
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    withAnimation {
                                        proxy.scrollTo("top", anchor: .top)
                                    }
                                }
                            }
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
                        .opacity(workoutManager.isPaused ? (isBlinking ? 0.4 : 1.0) : 1.0)
                        .disabled(isTogglingPause)
                        
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
                .padding(.horizontal, 4)
                .padding(.top, 2)
                .padding(.bottom, 4)
            }
            .ignoresSafeArea(edges: [.top, .bottom])
            .id(scrollViewID)
            .onChange(of: shouldScrollToTop) { _, newValue in
                // 左画面から再開された時にスクロールを一番上に戻す
                if newValue {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation {
                            proxy.scrollTo("top", anchor: .top)
                        }
                        shouldScrollToTop = false
                    }
                }
            }
        }
    }
    
    // コントロール専用画面
    private var controlView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            // 一時停止/再開ボタン
            Button {
                guard !isTogglingPause else {
                    print("⚠️ Already toggling pause, ignoring tap")
                    return
                }
                
                let wasPaused = workoutManager.isPaused
                togglePause()
                
                // 再開時：メイン画面に遷移して一番上にスクロール
                if wasPaused == true {
                    // 状態変更後、メイン画面に遷移
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation {
                            currentPage = 1
                        }
                        // メイン画面に遷移後、スクロールを一番上に
                        shouldScrollToTop = true
                    }
                }
                // 一時停止時：その画面に留まる（何もしない）
            } label: {
                HStack {
                    Image(systemName: workoutManager.isPaused ? "play.fill" : "pause.fill")
                        .font(.title3)
                    Text(workoutManager.isPaused ? "再開" : "一時停止")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(workoutManager.isPaused ? .green : .orange)
            .opacity(workoutManager.isPaused ? (isBlinking ? 0.4 : 1.0) : 1.0)
            .disabled(isTogglingPause)
            
            // ワークアウト終了ボタン
            Button {
                endWorkout()
            } label: {
                Text("ワークアウトを終了")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            
            Spacer()
        }
        .padding()
    }
    
    private func togglePause() {
        // 連続タップを防止
        guard !isTogglingPause else {
            print("⚠️ togglePause: Already toggling, ignoring")
            return
        }
        
        isTogglingPause = true
        
        print("🔄 togglePause: isPaused = \(workoutManager.isPaused)")
        
        if workoutManager.isPaused {
            print("🔄 togglePause: Calling resumeWorkout()")
            workoutManager.resumeWorkout()
        } else {
            print("🔄 togglePause: Calling pauseWorkout()")
            workoutManager.pauseWorkout()
        }
        
        // 一定時間後に再度タップ可能にする
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            isTogglingPause = false
            print("🔄 togglePause: Ready for next toggle")
        }
    }
    
    private func startBlinking() {
        // 既存のアニメーションを完全に停止
        withAnimation(.linear(duration: 0)) {
            isBlinking = false
        }
        
        // 新しいアニメーションを開始
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                self.isBlinking = true
            }
        }
    }
    
    private func stopBlinking() {
        // アニメーションを停止して、完全に不透明に戻す
        withAnimation(.easeOut(duration: 0.2)) {
            isBlinking = false
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
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
            
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .padding(.horizontal, 3)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}



#Preview {
    WorkoutView()
        .environment(WorkoutManager())
}
