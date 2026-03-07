//
//  WorkoutView.swift
//  Workout Watch App
//
//  Created by 山中雄樹 on 2026/03/04.
//

import SwiftUI

struct WorkoutView: View {
    @EnvironmentObject var workoutManager: WorkoutManager
    @State private var currentPage = 0
    @State private var scrollViewID = UUID()
    @State private var shouldScrollToTop = false
    @State private var isTogglingPause = false
    
    // タイマーベースの点滅制御
    @State private var blinkTimer: Timer?
    @State private var isButtonVisible = true
    
    // スリープ解除検知用
    @Environment(\.scenePhase) private var scenePhase
    @State private var shouldResetScroll = false
    
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
        .onDisappear {
            // ビューが消えたらタイマーをクリーンアップ
            stopBlinking()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            // スリープ解除時（バックグラウンド→アクティブ、非アクティブ→アクティブ）
            if newPhase == .active && (oldPhase == .background || oldPhase == .inactive) {
                print("🌟 Scene became active (woke up), resetting scroll positions")
                // どの画面にいてもスクロールをリセット（メイン画面のスクロール状態を更新）
                shouldResetScroll = true
            }
        }
    }
    
    // メイン画面
    private var mainWorkoutView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
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
                    .padding(.top, 12)
                    
                    // 主要メトリクス - 距離とペースを大きく表示
                    VStack(spacing: 2) {
                        // 距離と経過時間
                        HStack(spacing: 1) {
                            // 距離
                            VStack(spacing: 0) {
                                HStack(alignment: .firstTextBaseline, spacing: 1) {
                                    Text(String(format: "%.2f", workoutManager.distance / 1000))
                                        .font(.system(size: 30, weight: .bold, design: .rounded))
                                    Text("km")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                }
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                
                                Spacer()
                                
                                HStack(spacing: 2) {
                                    Image(systemName: "figure.run")
                                        .font(.system(size: 11))
                                    Text("距離")
                                        .font(.system(size: 14))
                                }
                                .foregroundStyle(.blue)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            
                            // 経過時間
                            VStack(spacing: 2) {
                                Text(workoutManager.elapsedTimeString)
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                
                                HStack(spacing: 2) {
                                    Image(systemName: "timer")
                                        .font(.system(size: 11))
                                    Text("時間")
                                        .font(.system(size: 14))
                                }
                                .foregroundStyle(.green)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 2)
                            .padding(.horizontal, 2)
                            .background(Color.green.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        
                        // ペースとカロリー
                        HStack(spacing: 1) {
                            // ペース
                            VStack(spacing: 0) {
                                HStack(alignment: .firstTextBaseline, spacing: 1) {
                                    Text(workoutManager.currentPaceString)
                                        .font(.system(size: 20, weight: .bold, design: .rounded))
                                    Text("min/km")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                }
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                
                                Spacer()
                                
                                HStack(spacing: 2) {
                                    Image(systemName: "speedometer")
                                        .font(.system(size: 11))
                                    Text("ペース")
                                        .font(.system(size: 14))
                                }
                                .foregroundStyle(.orange)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            
                            // カロリー
                            VStack(spacing: 2) {
                                Text(String(format: "%.0f", workoutManager.activeCalories))
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .lineLimit(1)
                                
                                HStack(spacing: 2) {
                                    Image(systemName: "flame.fill")
                                        .font(.system(size: 11))
                                    Text("kcal")
                                        .font(.system(size: 14))
                                }
                                .foregroundStyle(.red)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 2)
                            .padding(.horizontal, 2)
                            .background(Color.red.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    
                    // ラップタイム表示セクション
                    if !workoutManager.lapTimes.isEmpty {
                        lapTimesView
                            .padding(.top, 2)
                            .padding(.bottom, 4)
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
                        .opacity(isTogglingPause ? 0.5 : (workoutManager.isPaused && !isButtonVisible ? 0.4 : 1.0))
                        .animation(.easeInOut(duration: 0.2), value: isButtonVisible)
                        
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
            .onChange(of: shouldResetScroll) { _, newValue in
                // スリープ解除時にスクロールを一番上にリセット
                if newValue {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        withAnimation {
                            proxy.scrollTo("top", anchor: .top)
                        }
                        shouldResetScroll = false
                    }
                }
            }
        }
    }
    
    // ラップタイム表示ビュー
    private var lapTimesView: some View {
        VStack(spacing: 0) {
            // ヘッダー
            HStack(spacing: 4) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.cyan)
                Text("ラップタイム")
                    .font(.system(size: 12))
                    .fontWeight(.semibold)
                
                // 新記録表示
                if let bestLap = getBestLapInfo() {
                    Text("新記録 \(bestLap.lapNumber)km／\(formatLapTime(bestLap.lapTime))")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.red)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                
                Spacer()
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)
            .padding(.bottom, 1)
            
            // 独立したスクロールビュー（固定高さ）
            ScrollViewReader { lapProxy in
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 0) {
                        // グリッド表示（5列）
                        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 5)
                        
                        LazyVGrid(columns: columns, spacing: 0) {
                            ForEach(Array(workoutManager.lapTimes.enumerated()), id: \.offset) { index, lapTime in
                                LapTimeCell(
                                    lapNumber: index + 1,
                                    lapTime: lapTime,
                                    color: lapColor(for: lapTime, in: workoutManager.lapTimes)
                                )
                                .id("lap-\(index)")
                            }
                        }
                        .padding(.horizontal, 2)
                        
                        // スクロール位置の目印（最後に追加）
                        Color.clear
                            .frame(height: 1)
                            .id("lapBottom")
                    }
                }
                .frame(height: 70) // 固定高さ（2行分のラップが見える：1-5km、6-10km）
                .onChange(of: workoutManager.lapTimes.count) { oldCount, newCount in
                    // 新しいラップが追加されたとき（カウントが増加したとき）
                    if newCount > oldCount && newCount > 0 {
                        print("📊 New lap detected: lap count \(oldCount) -> \(newCount), scrolling to bottom")
                        // レイアウトが確定してからスクロール
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation(.easeOut(duration: 0.35)) {
                                // 最下部にスクロール
                                lapProxy.scrollTo("lapBottom", anchor: .bottom)
                            }
                        }
                    }
                }
                .onAppear {
                    // 初期表示時も最新のラップにスクロール
                    let lapCount = workoutManager.lapTimes.count
                    if lapCount > 0 {
                        print("📊 Initial lap scroll: \(lapCount) laps")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            lapProxy.scrollTo("lapBottom", anchor: .bottom)
                        }
                    }
                }
                .onChange(of: shouldResetScroll) { _, newValue in
                    // スリープ解除時にラップタイムを最新（一番下）にスクロール
                    if newValue && workoutManager.lapTimes.count > 0 {
                        print("📊 Woke up: scrolling laps to bottom")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            lapProxy.scrollTo("lapBottom", anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
    
    // ラップタイムの色を決定（最速=赤、最遅=青、それ以外=緑）
    private func lapColor(for lapTime: TimeInterval, in lapTimes: [TimeInterval]) -> Color {
        // ラップが1つしかない場合はデフォルト色
        guard lapTimes.count > 1 else {
            return .green
        }
        
        let minLap = lapTimes.min() ?? 0
        let maxLap = lapTimes.max() ?? 0
        
        if lapTime == minLap && minLap != maxLap {
            return .red // 最速
        } else if lapTime == maxLap && minLap != maxLap {
            return .blue // 最遅
        } else {
            return .green // 通常
        }
    }
    
    // 新記録（最速ラップ）の情報を取得
    private func getBestLapInfo() -> (lapNumber: Int, lapTime: TimeInterval)? {
        guard !workoutManager.lapTimes.isEmpty else {
            return nil
        }
        
        // 最速タイムを見つける
        if let minLapTime = workoutManager.lapTimes.min(),
           let minIndex = workoutManager.lapTimes.firstIndex(of: minLapTime) {
            return (lapNumber: minIndex + 1, lapTime: minLapTime)
        }
        
        return nil
    }
    
    // ラップタイムをフォーマット
    private func formatLapTime(_ time: TimeInterval) -> String {
        let minutes = Int(time / 60)
        let seconds = Int(time.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d", minutes, seconds)
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
            .opacity(isTogglingPause ? 0.5 : (workoutManager.isPaused && !isButtonVisible ? 0.4 : 1.0))
            .animation(.easeInOut(duration: 0.2), value: isButtonVisible)
            
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
        
        // 短い時間でフラグをリセット（WorkoutManagerの処理時間と合わせる）
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            isTogglingPause = false
            print("🔄 togglePause: Ready for next toggle")
        }
    }
    
    private func startBlinking() {
        print("🔴 startBlinking called")
        
        // 既存のタイマーを停止
        stopBlinking()
        
        // 初期状態を設定
        isButtonVisible = true
        
        // 0.8秒ごとに切り替え
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { _ in
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.4)) {
                    self.isButtonVisible.toggle()
                }
                print("🔴 Blink toggle: isButtonVisible = \(self.isButtonVisible)")
            }
        }
        
        // タイマーをRunLoopに追加
        if let timer = blinkTimer {
            RunLoop.current.add(timer, forMode: .common)
            print("🔴 Blink timer started")
        }
    }
    
    private func stopBlinking() {
        print("🟢 stopBlinking called")
        
        // タイマーを停止
        blinkTimer?.invalidate()
        blinkTimer = nil
        
        // 完全に表示状態に戻す
        withAnimation(.easeOut(duration: 0.2)) {
            isButtonVisible = true
        }
        
        print("🟢 Blink timer stopped, isButtonVisible = \(isButtonVisible)")
    }
    
    private func endWorkout() {
        Task {
            await workoutManager.endWorkout()
        }
    }
}

// ラップタイムセル
struct LapTimeCell: View {
    let lapNumber: Int
    let lapTime: TimeInterval
    let color: Color
    
    var body: some View {
        VStack(spacing: 0) {
            // 距離（km）- 上段
            Text("\(lapNumber)km")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            
            // ラップタイム - 下段
            Text(formatLapTime(lapTime))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 1)
        .padding(.horizontal, 1)
        .background(color.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
    
    private func formatLapTime(_ time: TimeInterval) -> String {
        let minutes = Int(time / 60)
        let seconds = Int(time.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d", minutes, seconds)
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
                .font(.system(size: 20, weight: .bold, design: .rounded))
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
        .environmentObject(WorkoutManager())
}
