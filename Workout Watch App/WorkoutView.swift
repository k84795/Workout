//
//  WorkoutView.swift
//  Workout Watch App
//
//  Created by 山中雄樹 on 2026/03/04.
//

import SwiftUI

struct WorkoutView: View {
    @EnvironmentObject var workoutManager: WorkoutManager
    @State private var currentPage = 1
    @State private var isTogglingPause = false
    @State private var isEndingWorkout = false
    
    // タイマーベースの点滅制御
    @State private var blinkTimer: Timer?
    @State private var isButtonVisible = true
    @State private var clockTriggerActive = false

    @Environment(\.scenePhase) private var scenePhase
    
    // 画面サイズに応じたスケール係数
    private var sizeScale: CGFloat {
        let screenWidth = WKInterfaceDevice.current().screenBounds.width
        // 40mm (162pt) を基準 (1.0)、45mm (184pt) で約1.14、Ultra (205pt) で約1.26
        return screenWidth / 162.0
    }
    
    var body: some View {
        TabView(selection: $currentPage) {
            // コントロールページ（0番目・左側）
            controlView
                .tag(0)
            
            // メインページ（1番目・中央）
            mainWorkoutView
                .tag(1)
            
            // ミュージックコントロールページ（2番目・右側）
            MusicControlView()
                .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onChange(of: workoutManager.isPaused) { oldValue, newValue in
            print("🔄 isPaused changed from \(oldValue) to \(newValue)")
            // 点滅状態を確実に同期
            if newValue {
                // 一時停止になったら点滅開始
                print("🔄 Starting blink animation...")
                startBlinking()
            } else {
                // 再開したら点滅停止
                print("🔄 Stopping blink animation...")
                stopBlinking()
            }
        }
        .onChange(of: currentPage) { oldValue, newValue in
            if workoutManager.isPaused {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    startBlinking()
                }
            }
        }
        .onAppear {
            currentPage = 1
            clockTriggerActive = false
            isTogglingPause = false
            isEndingWorkout = false
            isButtonVisible = true
            if workoutManager.isPaused {
                startBlinking()
            }
            // watchOSはセーフエリアゾーンのコンテンツが「変化」した時のみ時計位置を更新する。
            // クロスフェード(0.3s)完了後にignoresSafeAreaをトグルして変化を作り時計を右上へ移動させる。
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                guard workoutManager.isWorkoutActive else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    clockTriggerActive = true
                }
            }
        }
        .onDisappear {
            stopBlinking()
            isTogglingPause = false
            isEndingWorkout = false
        }
    }
    
    private func calculateMarathonPrediction() -> String {
        let marathonDistance = 42195.0
        let currentDistance = workoutManager.distance
        let elapsedTime = workoutManager.elapsedTime

        guard currentDistance > 0 && elapsedTime > 0 else { return "--:--:--" }

        let estimatedTotal = marathonDistance * (elapsedTime / currentDistance)
        let hours = Int(estimatedTotal / 3600)
        let minutes = Int(estimatedTotal.truncatingRemainder(dividingBy: 3600) / 60)
        let seconds = Int(estimatedTotal.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }

    // メイン画面
    private var mainWorkoutView: some View {
        GeometryReader { geometry in
            let cellSpacing: CGFloat = 2
            let horizontalPadding: CGFloat = 4
            let footerHeight: CGFloat = 8
            let availableWidth = geometry.size.width - horizontalPadding * 2
            let cellWidth = (availableWidth - cellSpacing) / 2

            VStack(spacing: 0) {
                // ワークアウトタイトル
                Text(workoutManager.workoutName)
                    .font(.system(size: 12 * sizeScale, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                // 経過時間
                Text(workoutManager.elapsedTimeString)
                    .font(.system(size: 21 * sizeScale, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.bottom, 2)

                // 2x3 メトリクスグリッド（残り領域を3行に均等分配）
                VStack(spacing: cellSpacing) {
                    // Row 1: 距離 | カロリー
                    HStack(spacing: cellSpacing) {
                        WatchMetricCell(
                            icon: "figure.run",
                            label: "距離",
                            value: String(format: "%.2f", workoutManager.distance / 1000),
                            unit: "km",
                            color: .blue,
                            sizeScale: sizeScale
                        )
                        .frame(width: cellWidth)

                        WatchMetricCell(
                            icon: "flame.fill",
                            label: "カロリー",
                            value: String(format: "%.0f", workoutManager.activeCalories),
                            unit: "kcal",
                            color: .orange,
                            sizeScale: sizeScale
                        )
                        .frame(width: cellWidth)
                    }
                    .frame(maxHeight: .infinity)

                    // Row 2: 平均心拍数 | ペース
                    HStack(spacing: cellSpacing) {
                        WatchMetricCell(
                            icon: "heart.fill",
                            label: "平均心拍数",
                            value: workoutManager.averageHeartRate > 0 ? String(format: "%.0f", workoutManager.averageHeartRate) : "--",
                            unit: "bpm",
                            color: .red,
                            sizeScale: sizeScale
                        )
                        .frame(width: cellWidth)

                        WatchMetricCell(
                            icon: "speedometer",
                            label: "ペース",
                            value: workoutManager.currentPaceString,
                            unit: "/km",
                            color: .green,
                            sizeScale: sizeScale
                        )
                        .frame(width: cellWidth)
                    }
                    .frame(maxHeight: .infinity)

                    // Row 3: 歩数 | フルマラソン予想
                    HStack(spacing: cellSpacing) {
                        WatchMetricCell(
                            icon: "figure.walk.motion",
                            label: "歩数",
                            value: String(format: "%.0f", workoutManager.stepCount),
                            unit: "歩",
                            color: .purple,
                            sizeScale: sizeScale
                        )
                        .frame(width: cellWidth)

                        WatchMarathonCell(
                            prediction: calculateMarathonPrediction(),
                            sizeScale: sizeScale
                        )
                        .frame(width: cellWidth)
                    }
                    .frame(maxHeight: .infinity)
                }
                .padding(.horizontal, horizontalPadding)
                .frame(maxHeight: .infinity)

                // フッター（画面下の空白）
                Color.clear
                    .frame(height: footerHeight)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea(edges: clockTriggerActive ? [.top, .bottom] : [.bottom])
    }
    
    // コントロール専用画面
    private var controlView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            // 一時停止/再開ボタン
            Button {
                guard !isTogglingPause && !isEndingWorkout else {
                    print("⚠️ Already toggling pause, ignoring tap")
                    return
                }

                let wasPaused = workoutManager.isPaused
                togglePause()

                if wasPaused == true {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation {
                            currentPage = 1
                        }
                    }
                }
                // 一時停止時：その画面に留まる（何もしない）
            } label: {
                HStack {
                    Image(systemName: workoutManager.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 22 * sizeScale))
                    Text(workoutManager.isPaused ? "再開" : "一時停止")
                        .font(.system(size: 20 * sizeScale, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(workoutManager.isPaused ? .green : .orange)
            .disabled(isTogglingPause || isEndingWorkout)
            .opacity(isTogglingPause ? 0.5 : (workoutManager.isPaused && !isButtonVisible ? 0.4 : 1.0))
            .animation(.easeInOut(duration: 0.2), value: isButtonVisible)

            // ワークアウト終了ボタン
            Button {
                endWorkout()
            } label: {
                Text("ワークアウトを終了")
                    .font(.system(size: 28 * sizeScale, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(isEndingWorkout)
            .opacity(isEndingWorkout ? 0.5 : 1.0)
            
            Spacer()
        }
        .padding()
    }
    
    private func togglePause() {
        guard !isTogglingPause else { return }

        isTogglingPause = true

        if workoutManager.isPaused {
            workoutManager.resumeWorkout()
        } else {
            workoutManager.pauseWorkout()
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            isTogglingPause = false
        }
    }
    
    private func startBlinking() {
        stopBlinking()
        isButtonVisible = true

        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { _ in
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.4)) {
                    self.isButtonVisible.toggle()
                }
            }
        }

        if let timer = blinkTimer {
            RunLoop.current.add(timer, forMode: .common)
        }
    }

    private func stopBlinking() {
        blinkTimer?.invalidate()
        blinkTimer = nil

        Task { @MainActor in
            withAnimation(.easeOut(duration: 0.2)) {
                isButtonVisible = true
            }
        }
    }
    
    private func endWorkout() {
        // 連続タップを防止（履歴の重複保存を防ぐ）
        guard !isEndingWorkout else {
            print("⚠️ endWorkout: Already ending, ignoring tap")
            return
        }
        isEndingWorkout = true

        // ワークアウト履歴のスナップショットを即座に取得（後続のリセットに備える）
        let shouldSaveRecord = workoutManager.elapsedTime >= 10
        let record: WorkoutHistoryRecord? = shouldSaveRecord ? WorkoutHistoryRecord(
            workoutName: workoutManager.workoutName,
            elapsedTime: workoutManager.elapsedTime,
            distance: workoutManager.distance,
            activeCalories: workoutManager.activeCalories,
            averageHeartRate: workoutManager.averageHeartRate,
            stepCount: workoutManager.stepCount,
            lapTimes: workoutManager.lapTimes,
            deviceSource: "watch"
        ) : nil

        stopBlinking()

        // 一時停止関連の状態をリセット
        isTogglingPause = false
        isButtonVisible = true

        Task { @MainActor in
            defer { isEndingWorkout = false }

            print("🔴 WorkoutView: Starting workout end sequence")

            // ボタンの視覚フィードバックを優先するため一度yieldしてから保存
            if let record {
                await Task.yield()
                WorkoutHistoryStore.shared.save(record: record)
            }

            // ワークアウトを終了
            await workoutManager.endWorkout()

            print("🔴 WorkoutView: isWorkoutActive = \(workoutManager.isWorkoutActive)")
            print("🔴 WorkoutView: session = \(workoutManager.session != nil)")

            // ページを初期状態に戻す
            currentPage = 1

            // フォールバック: 万が一 isWorkoutActive が残っていれば強制リセット
            try? await Task.sleep(for: .milliseconds(100))
            if workoutManager.isWorkoutActive {
                print("⚠️ WorkoutView: isWorkoutActive is still true after endWorkout!")
                workoutManager.isWorkoutActive = false
            }
        }
    }
}

// Apple Watch用メトリクスセル
struct WatchMetricCell: View {
    let icon: String
    let label: String
    let value: String
    let unit: String
    let color: Color
    let sizeScale: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 1) {
                Image(systemName: icon)
                    .font(.system(size: 11 * sizeScale))
                Text(label)
                    .font(.system(size: 11 * sizeScale, weight: .medium))
            }
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.5)

            Spacer(minLength: 0)

            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value)
                    .font(.system(size: 22 * sizeScale, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.3)
                Text(unit)
                    .font(.system(size: 11 * sizeScale))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.3)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 1)
        .padding(.horizontal, 2)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// Apple Watch用フルマラソン予想セル
struct WatchMarathonCell: View {
    let prediction: String
    let sizeScale: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 1) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 11 * sizeScale))
                    Text("フルマラソン")
                        .font(.system(size: 11 * sizeScale, weight: .medium))
                }
                Text("予想")
                    .font(.system(size: 11 * sizeScale, weight: .medium))
            }
            .foregroundStyle(.cyan)
            .lineLimit(1)
            .minimumScaleFactor(0.5)

            Spacer(minLength: 0)

            Text(prediction)
                .font(.system(size: 19 * sizeScale, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.3)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 1)
        .padding(.horizontal, 2)
        .background(Color.cyan.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

#Preview {
    WorkoutView()
        .environmentObject(WorkoutManager())
}
