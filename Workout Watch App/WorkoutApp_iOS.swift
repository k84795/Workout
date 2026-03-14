//
//  WorkoutApp_iOS.swift
//  Workout - iOS
//
//  Created by 山中雄樹 on 2026/03/04.
//

import SwiftUI
import Combine
import MediaPlayer
import AVFoundation
import WatchConnectivity
import HealthKit

@main
struct WorkoutPhoneApp: App {
    @StateObject private var workoutManager = WorkoutManager()
    
    var body: some Scene {
        WindowGroup {
            PhoneContentView()
                .environmentObject(workoutManager)
                .onAppear {
                    // 起動時にWatch Connectivity Managerを初期化
                    if WCSession.isSupported() {
                        _ = PhoneMusicConnectivityManager.shared
                    }
                }
        }
    }
}

struct PhoneContentView: View {
    @EnvironmentObject private var workoutManager: WorkoutManager
    
    var body: some View {
        Group {
            if workoutManager.isWorkoutActive {
                PhoneWorkoutView()
                    .id("workout-view")
                    .transition(.opacity)
            } else {
                PhoneWorkoutTypeSelectionView()
                    .id("selection-view")
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: workoutManager.isWorkoutActive)
    }
}

struct PhoneWorkoutTypeSelectionView: View {
    @EnvironmentObject private var workoutManager: WorkoutManager
    @State private var isStarting = false
    @State private var showError = false
    
    let workoutTypes: [(name: String, type: HKWorkoutActivityType, icon: String, color: Color)] = [
        ("ウォーキング", .walking, "figure.walk", .green),
        ("ジョギング", .running, "figure.run", .orange),
        ("ランニング", .running, "figure.run.circle", .red)
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                List {
                    ForEach(workoutTypes, id: \.name) { workout in
                        Button {
                            startWorkout(type: workout.type, name: workout.name)
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: workout.icon)
                                    .font(.system(size: 32))
                                    .foregroundStyle(workout.color)
                                    .frame(width: 50)
                                
                                Text(workout.name)
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 12)
                        }
                        .disabled(isStarting)
                    }
                }
                .opacity(isStarting ? 0.3 : 1.0)
                .disabled(isStarting)
                
                if isStarting {
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                        Text("ワークアウトを準備中...")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                    .padding(32)
                    .background(Color.black.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
            .navigationTitle("ワークアウト")
            .alert("エラー", isPresented: $showError) {
                Button("OK") {
                    workoutManager.errorMessage = nil
                    isStarting = false
                }
            } message: {
                if let errorMessage = workoutManager.errorMessage {
                    Text(errorMessage)
                }
            }
            .onChange(of: workoutManager.errorMessage) { oldValue, newValue in
                if newValue != nil {
                    showError = true
                    isStarting = false
                }
            }
            .onChange(of: workoutManager.isWorkoutActive) { oldValue, newValue in
                if newValue {
                    isStarting = false
                }
            }
        }
    }
    
    private func startWorkout(type: HKWorkoutActivityType, name: String) {
        guard !isStarting else { return }
        guard !workoutManager.isWorkoutActive else { return }
        
        isStarting = true
        
        // タイムアウトタイマーを設定（10秒）
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))
            
            if isStarting {
                print("⚠️ Workout start timeout - forcing UI update")
                isStarting = false
                
                // タイムアウト後もワークアウトがアクティブでない場合はエラー表示
                if !workoutManager.isWorkoutActive {
                    workoutManager.errorMessage = "ワークアウトの開始がタイムアウトしました。もう一度お試しください。"
                }
            }
        }
        
        Task { @MainActor in
            await workoutManager.startWorkout(activityType: type, workoutName: name)
            isStarting = false
        }
    }
}

struct PhoneWorkoutView: View {
    @EnvironmentObject var workoutManager: WorkoutManager
    @State private var selectedTab = 1
    @State private var isButtonVisible = true
    @State private var blinkTimer: Timer?
    @State private var shouldScrollToTop = false
    @State private var cachedBestLapText: String? = nil
    @State private var lastLapCount: Int = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // ページスタイルのTabView（スワイプアニメーション対応）
            TabView(selection: $selectedTab) {
                lapTimesView
                    .tag(0)
                
                mainWorkoutView
                    .tag(1)
                
                PhoneMusicControlView()
                    .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            
            // カスタムタブバー
            customTabBar
        }
        .onChange(of: workoutManager.isPaused) { oldValue, newValue in
            if newValue {
                startBlinking()
            } else {
                stopBlinking()
            }
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            if newValue == 0 && (oldValue == 1 || oldValue == 2) {
                if !workoutManager.isPaused {
                    shouldScrollToTop = true
                }
            }
        }
        .onAppear {
            if workoutManager.isPaused {
                startBlinking()
            }
            updateBestLapTextIfNeeded()
        }
        .onDisappear {
            stopBlinking()
        }
        .onChange(of: workoutManager.lapTimes.count) { oldValue, newValue in
            if newValue != lastLapCount {
                updateBestLapTextIfNeeded()
            }
        }
    }
    
    // シンプルなタブバー（Liquid Glass付き）
    private var customTabBar: some View {
        VStack(spacing: 0) {
            // 上部の区切り線
            Divider()
            
            GlassEffectContainer(spacing: 20) {
                HStack(spacing: 12) {
                    // ラップタブ
                    tabButton(
                        index: 0,
                        icon: "list.bullet",
                        label: "ラップ",
                        isSelected: selectedTab == 0
                    )
                    
                    // ワークアウトタブ
                    tabButton(
                        index: 1,
                        icon: "figure.run",
                        label: "ワークアウト",
                        isSelected: selectedTab == 1
                    )
                    
                    // 音楽タブ
                    tabButton(
                        index: 2,
                        icon: "music.note",
                        label: "音楽",
                        isSelected: selectedTab == 2
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(.regularMaterial)
        }
        .ignoresSafeArea(edges: .bottom)
    }
    
    private func tabButton(index: Int, icon: String, label: String, isSelected: Bool) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = index
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .frame(height: 28)
                
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .contentShape(Rectangle())
        }
        .glassEffect(
            isSelected ? 
                .regular.tint(tabColor(for: index)).interactive() : 
                .regular.interactive(),
            in: .rect(cornerRadius: 16)
        )
    }
    
    private func tabColor(for index: Int) -> Color {
        switch index {
        case 0: return .blue
        case 1: return .green
        case 2: return .pink
        default: return .blue
        }
    }
    
    private var mainWorkoutView: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 6) {
                        Text(workoutManager.workoutName)
                            .font(.title3)
                            .fontWeight(.bold)
                            .padding(.top, 6)
                        
                        VStack(spacing: 1) {
                            Text("経過時間")
                                .font(.system(size: 21))
                                .foregroundStyle(.secondary)
                            Text(workoutManager.elapsedTimeString)
                                .font(.system(size: 60, weight: .bold, design: .rounded))
                                .monospacedDigit()
                        }
                        .padding(.vertical, 4)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            MetricCard(
                                title: "距離",
                                value: String(format: "%.2f", max(0, workoutManager.distance / 1000.0)),
                                unit: "km",
                                icon: "figure.walk",
                                color: .blue
                            )
                            .onChange(of: workoutManager.distance) { oldValue, newValue in
                                print("📱 iOS UI - Distance changed: \(String(format: "%.2f", oldValue))m -> \(String(format: "%.2f", newValue))m (displayed: \(String(format: "%.3f", newValue/1000.0))km)")
                            }
                            
                            MetricCard(
                                title: "カロリー",
                                value: String(format: "%.0f", max(0, workoutManager.activeCalories)),
                                unit: "kcal",
                                icon: "flame.fill",
                                color: .orange
                            )
                            
                            MetricCard(
                                title: "平均心拍数",
                                value: workoutManager.averageHeartRate > 0 ? String(format: "%.0f", workoutManager.averageHeartRate) : "--",
                                unit: "bpm",
                                icon: "heart.fill",
                                color: .red
                            )
                            
                            MetricCardWithRecord(
                                title: "ペース",
                                value: workoutManager.currentPaceString,
                                unit: "/km",
                                icon: "timer",
                                color: .green,
                                recordText: cachedBestLapText
                            )
                            .id("pace-card-\(workoutManager.lapTimes.count)")
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: cachedBestLapText)
                            
                            MetricCard(
                                title: "歩数",
                                value: String(format: "%.0f", max(0, workoutManager.stepCount)),
                                unit: "歩",
                                icon: "figure.walk.motion",
                                color: .purple
                            )
                            
                            MarathonTimeCard(
                                title: "フルマラソン予想",
                                remainingTime: calculateMarathonRemainingTime(),
                                icon: "flag.checkered",
                                color: .cyan
                            )
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 12)
                    }
                }
                
                // ボタンを下部に固定
                controlButtons()
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
                    .background(Color(UIColor.systemBackground))
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private var lapTimesView: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    if workoutManager.lapTimes.isEmpty {
                        Text("ラップタイムはまだありません")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    } else {
                        ForEach(Array(workoutManager.lapTimes.enumerated()), id: \.offset) { index, time in
                            HStack {
                                Text("\(index + 1)km")
                                    .font(.headline)
                                Spacer()
                                Text(formatLapTime(time))
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .monospacedDigit()
                                    .foregroundStyle(lapColor(for: time, at: index))
                            }
                            .padding(.vertical, 8)
                            .id(index)  // 各行にIDを付与
                        }
                    }
                }
                .navigationTitle("ラップタイム")
                .onChange(of: selectedTab) { oldValue, newValue in
                    // ラップタイム画面に切り替わった時
                    if newValue == 0 && !workoutManager.lapTimes.isEmpty {
                        // 最新のラップタイム（最後の要素）にスクロール
                        let lastIndex = workoutManager.lapTimes.count - 1
                        withAnimation {
                            proxy.scrollTo(lastIndex, anchor: .bottom)
                        }
                    }
                }
                .onAppear {
                    // 画面が表示された時も最新のラップタイムを表示
                    if !workoutManager.lapTimes.isEmpty {
                        let lastIndex = workoutManager.lapTimes.count - 1
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation {
                                proxy.scrollTo(lastIndex, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func lapColor(for time: TimeInterval, at index: Int) -> Color {
        guard !workoutManager.lapTimes.isEmpty else { return .green }
        guard workoutManager.lapTimes.count > 1 else { return .green }
        
        let fastest = workoutManager.lapTimes.min() ?? 0
        let slowest = workoutManager.lapTimes.max() ?? 0
        
        // 最速記録は常に赤（抜かれない限り赤文字）
        if time == fastest {
            return .red
        }
        // 最遅記録は青
        else if time == slowest && fastest != slowest {
            return .blue
        }
        // その他は緑
        else {
            return .green
        }
    }
    
    private func controlButtons() -> some View {
        HStack(spacing: 12) {
            Button {
                if workoutManager.isPaused {
                    workoutManager.resumeWorkout()
                } else {
                    workoutManager.pauseWorkout()
                }
            } label: {
                Label(
                    workoutManager.isPaused ? "再開" : "一時停止",
                    systemImage: workoutManager.isPaused ? "play.fill" : "pause.fill"
                )
                .font(.system(size: 20, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .opacity(isButtonVisible ? 1.0 : 0.3)
            
            Button {
                Task {
                    await workoutManager.endWorkout()
                }
            } label: {
                Label("終了", systemImage: "xmark")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.red)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }
    
    private func formatLapTime(_ time: TimeInterval) -> String {
        let hours = Int(time / 3600)
        let minutes = Int(time.truncatingRemainder(dividingBy: 3600) / 60)
        let seconds = Int(time.truncatingRemainder(dividingBy: 60))
        
        // 1時間未満の場合は mm:ss 形式
        if hours == 0 {
            return String(format: "%02d:%02d", minutes, seconds)
        } else {
            // 1時間以上の場合は h:mm:ss 形式
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
    }
    
    private func startBlinking() {
        stopBlinking()
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                isButtonVisible.toggle()
            }
        }
    }
    
    private func stopBlinking() {
        blinkTimer?.invalidate()
        blinkTimer = nil
        isButtonVisible = true
    }
    
    private func updateBestLapTextIfNeeded() {
        let currentLapCount = workoutManager.lapTimes.count
        
        // ラップ数が変わった場合のみ更新
        if currentLapCount != lastLapCount {
            lastLapCount = currentLapCount
            cachedBestLapText = calculateBestLapText()
        }
    }
    
    private func calculateBestLapText() -> String? {
        guard !workoutManager.lapTimes.isEmpty else { return nil }
        
        // 全ラップの中で最速のタイムを取得
        guard let fastest = workoutManager.lapTimes.min() else { return nil }
        
        // 最速ラップのインデックスを取得（1-based）
        guard let fastestIndex = workoutManager.lapTimes.firstIndex(of: fastest) else { return nil }
        let kmNumber = fastestIndex + 1
        
        // 最速記録を formatLapTime と同じ形式で表示
        let hours = Int(fastest / 3600)
        let minutes = Int(fastest.truncatingRemainder(dividingBy: 3600) / 60)
        let seconds = Int(fastest.truncatingRemainder(dividingBy: 60))
        
        // 1時間未満の場合は mm:ss 形式
        let timeString: String
        if hours == 0 {
            timeString = String(format: "%02d:%02d", minutes, seconds)
        } else {
            // 1時間以上の場合は h:mm:ss 形式
            timeString = String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        
        return "\(kmNumber)km/\(timeString)"
    }
    
    private func calculateMarathonRemainingTime() -> TimeInterval? {
        let marathonDistance = 42195.0 // メートル
        let currentDistance = workoutManager.distance // メートル
        let elapsedTime = workoutManager.elapsedTime // 秒
        
        // 走行距離が0の場合は計算できない
        guard currentDistance > 0 && elapsedTime > 0 else { return nil }
        
        // 現在のペース（秒/メートル）
        let currentPace = elapsedTime / currentDistance
        
        // フルマラソン完走までの予想時間
        let estimatedTotalTime = marathonDistance * currentPace
        
        // 残り時間
        let remainingTime = estimatedTotalTime - elapsedTime
        
        return max(0, remainingTime)
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 0) {
            // アイコンエリア（固定）
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.system(size: 22))
                Spacer()
            }
            .padding(.top, 10)
            .padding(.horizontal, 10)
            
            Spacer()
            
            // 新記録スペース（ペースカードと高さを揃えるため）
            VStack(spacing: 0) {
                Text(" ")
                    .font(.system(size: 16, weight: .bold))
                    .lineLimit(1)
            }
            .frame(height: 20) // 固定高さ
            .padding(.bottom, 2)
            .padding(.horizontal, 10)
            
            // タイトルと値エリア（固定）
            VStack(spacing: 2) {
                HStack {
                    Text(title)
                        .font(.system(size: 19))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.system(size: 66, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                    Text(unit)
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
            
            Spacer()
        }
        .frame(minHeight: 150, maxHeight: 150)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct MetricCardWithRecord: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    let recordText: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // アイコンエリア（固定）
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.system(size: 22))
                Spacer()
            }
            .padding(.top, 10)
            .padding(.horizontal, 10)
            
            Spacer()
            
            // 新記録表示エリア（固定高さ）
            VStack(spacing: 0) {
                if let recordText = recordText {
                    Text("新記録 \(recordText)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.red)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                } else {
                    // 空のスペースを確保して高さを固定
                    Text(" ")
                        .font(.system(size: 16, weight: .bold))
                        .lineLimit(1)
                }
            }
            .frame(height: 20) // 固定高さ
            .padding(.bottom, 2)
            .padding(.horizontal, 10)
            
            // タイトルと値エリア（固定）
            VStack(spacing: 2) {
                HStack {
                    Text(title)
                        .font(.system(size: 19))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.system(size: 66, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                    Text(unit)
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
            
            Spacer()
        }
        .frame(minHeight: 150, maxHeight: 150)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct MarathonTimeCard: View {
    let title: String
    let remainingTime: TimeInterval?
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 0) {
            // アイコン上部の空間
            Spacer()
                .frame(height: 8)
            
            // アイコンエリア（固定）
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.system(size: 22))
                Spacer()
            }
            .padding(.top, 10)
            .padding(.horizontal, 10)
            
            Spacer()
            
            // 「今のペースなら」表示エリア（他のカードと高さを揃えるため）
            VStack(spacing: 0) {
                Text("今のペースなら")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.cyan)
                    .lineLimit(1)
            }
            .frame(height: 20)
            .padding(.bottom, 2)
            .padding(.horizontal, 10)
            
            // タイトルと値エリア
            VStack(spacing: 2) {
                HStack {
                    Text(title)
                        .font(.system(size: 19))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                
                VStack(spacing: -2) {
                    // 「残り」を左寄せ
                    HStack {
                        Text("残り")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    
                    // タイムを歩数カードと同じサイズ(48pt)で表示
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        if let time = remainingTime {
                            Text(formatMarathonTime(time))
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .minimumScaleFactor(0.5)
                                .lineLimit(1)
                        } else {
                            Text("--:--:--")
                                .font(.system(size: 20, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    // 「でゴール」を右寄せ
                    HStack {
                        Spacer()
                        Text("でゴール")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
            
            Spacer()
        }
        .frame(minHeight: 150, maxHeight: 150)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func formatMarathonTime(_ time: TimeInterval) -> String {
        let hours = Int(time / 3600)
        let minutes = Int(time.truncatingRemainder(dividingBy: 3600) / 60)
        let seconds = Int(time.truncatingRemainder(dividingBy: 60))
        
        // h:mm:ss 形式で表示
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
}

struct PhoneMusicControlView: View {
    @StateObject private var musicController = PhoneMusicController()
    @State private var volume: Double = 0.5
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                artworkView
                    .padding(.top, 20)
                nowPlayingInfo
                playbackControls
                    .padding(.vertical, 8)
                volumeControl
                    .padding(.horizontal)
                Spacer()
            }
            .navigationTitle("音楽")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                volume = musicController.volume
                musicController.startMonitoring()
            }
            .onDisappear {
                musicController.stopMonitoring()
            }
            .onChange(of: volume) { oldValue, newValue in
                musicController.setVolume(newValue)
            }
        }
    }
    
    // アートワーク表示
    private var artworkView: some View {
        Group {
            if let artwork = musicController.currentArtwork {
                Image(uiImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 280, height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                    .transition(.scale.combined(with: .opacity))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(
                        colors: [Color.pink.opacity(0.6), Color.purple.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 280, height: 280)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 80))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: musicController.currentArtwork)
    }
    
    private var nowPlayingInfo: some View {
        VStack(spacing: 8) {
            if let title = musicController.currentTrackTitle {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal)
                if let artist = musicController.currentArtist {
                    Text(artist)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                }
                if let album = musicController.currentAlbum {
                    Text(album)
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                }
            } else {
                Text("再生していません")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
        }
        .padding(.horizontal)
    }
    
    private var playbackControls: some View {
        HStack(spacing: 60) {
            Button {
                musicController.skipToPrevious()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.pink)
            }
            Button {
                musicController.togglePlayPause()
            } label: {
                Image(systemName: musicController.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(Color.pink)
            }
            Button {
                musicController.skipToNext()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.pink)
            }
        }
    }
    
    private var volumeControl: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "speaker.fill")
                Slider(value: $volume, in: 0...1)
                    .tint(.pink)
                Image(systemName: "speaker.wave.3.fill")
            }
            Text("\(Int(round(volume * 100)))%")
                .font(.headline)
                .monospacedDigit()
        }
    }
}

@MainActor
class PhoneMusicController: ObservableObject {
    @Published var isPlaying: Bool = false
    @Published var volume: Double = 0.5
    @Published var currentTrackTitle: String? = nil
    @Published var currentArtist: String? = nil
    @Published var currentAlbum: String? = nil
    @Published var currentArtwork: UIImage? = nil
    
    private var timer: Timer?
    private let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
    private let remoteCommandCenter = MPRemoteCommandCenter.shared()
    
    init() {
        loadVolume()
        setupRemoteCommands()
    }
    
    private func setupRemoteCommands() {
        remoteCommandCenter.playCommand.isEnabled = true
        remoteCommandCenter.playCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            Task { @MainActor [weak self] in
                self?.isPlaying = true
                self?.updateNowPlayingInfo()
            }
            return .success
        }
        remoteCommandCenter.pauseCommand.isEnabled = true
        remoteCommandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            Task { @MainActor [weak self] in
                self?.isPlaying = false
            }
            return .success
        }
        remoteCommandCenter.nextTrackCommand.isEnabled = true
        remoteCommandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            Task { @MainActor [weak self] in
                self?.updateNowPlayingInfo()
            }
            return .success
        }
        remoteCommandCenter.previousTrackCommand.isEnabled = true
        remoteCommandCenter.previousTrackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            Task { @MainActor [weak self] in
                self?.updateNowPlayingInfo()
            }
            return .success
        }
    }
    
    func startMonitoring() {
        updateNowPlayingInfo()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                self?.updateNowPlayingInfo()
            }
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    private func updateNowPlayingInfo() {
        guard let nowPlayingInfo = nowPlayingInfoCenter.nowPlayingInfo else {
            currentTrackTitle = nil
            currentArtist = nil
            currentAlbum = nil
            currentArtwork = nil
            return
        }
        
        currentTrackTitle = nowPlayingInfo[MPMediaItemPropertyTitle] as? String
        currentArtist = nowPlayingInfo[MPMediaItemPropertyArtist] as? String
        currentAlbum = nowPlayingInfo[MPMediaItemPropertyAlbumTitle] as? String
        
        // アートワークを取得
        if let artworkData = nowPlayingInfo[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork {
            // 280x280のサイズでアートワークを取得
            let artwork = artworkData.image(at: CGSize(width: 280, height: 280))
            currentArtwork = artwork
        } else {
            currentArtwork = nil
        }
        
        if let rate = nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] as? Double {
            isPlaying = rate > 0
        }
    }
    
    func togglePlayPause() {
        isPlaying.toggle()
    }
    
    func skipToNext() {
        print("🎵 Skip to next")
    }
    
    func skipToPrevious() {
        print("🎵 Skip to previous")
    }
    
    func setVolume(_ newVolume: Double) {
        volume = newVolume
        saveVolume()
        MPVolumeView.setSystemVolume(Float(newVolume))
    }
    
    private func saveVolume() {
        UserDefaults.standard.set(volume, forKey: "musicVolume")
    }
    
    private func loadVolume() {
        let savedVolume = UserDefaults.standard.double(forKey: "musicVolume")
        volume = savedVolume > 0 ? savedVolume : 0.5
    }
}

extension MPVolumeView {
    static func setSystemVolume(_ volume: Float) {
        let volumeView = MPVolumeView()
        let slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            slider?.value = volume
        }
    }
}
