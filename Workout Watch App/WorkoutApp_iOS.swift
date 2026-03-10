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
    @State private var selectedTab = 0
    @State private var isButtonVisible = true
    @State private var blinkTimer: Timer?
    @State private var shouldScrollToTop = false
    
    var body: some View {
        TabView(selection: $selectedTab) {
            mainWorkoutView
                .tabItem {
                    Label("ワークアウト", systemImage: "figure.run")
                }
                .tag(0)
            
            lapTimesView
                .tabItem {
                    Label("ラップ", systemImage: "list.bullet")
                }
                .tag(1)
            
            PhoneMusicControlView()
                .tabItem {
                    Label("音楽", systemImage: "music.note")
                }
                .tag(2)
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
        }
        .onDisappear {
            stopBlinking()
        }
    }
    
    private var mainWorkoutView: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 24) {
                        Text(workoutManager.workoutName)
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.top)
                            .id("top")
                        
                        VStack(spacing: 4) {
                            Text("経過時間")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(workoutManager.elapsedTimeString)
                                .font(.system(size: 56, weight: .bold, design: .rounded))
                                .monospacedDigit()
                        }
                        .padding(.vertical)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                            MetricCard(
                                title: "距離",
                                value: String(format: "%.2f", workoutManager.distance / 1000.0),
                                unit: "km",
                                icon: "figure.walk",
                                color: .blue
                            )
                            
                            MetricCard(
                                title: "カロリー",
                                value: String(format: "%.0f", workoutManager.activeCalories),
                                unit: "kcal",
                                icon: "flame.fill",
                                color: .orange
                            )
                            
                            MetricCard(
                                title: "平均心拍数",
                                value: String(format: "%.0f", workoutManager.averageHeartRate),
                                unit: "bpm",
                                icon: "heart.fill",
                                color: .red
                            )
                            
                            MetricCard(
                                title: "ペース",
                                value: workoutManager.currentPaceString,
                                unit: "/km",
                                icon: "timer",
                                color: .green
                            )
                            
                            if workoutManager.workoutName == "ウォーキング" {
                                MetricCard(
                                    title: "歩数",
                                    value: String(format: "%.0f", workoutManager.stepCount),
                                    unit: "歩",
                                    icon: "figure.walk.motion",
                                    color: .purple
                                )
                            }
                        }
                        .padding(.horizontal)
                        
                        Spacer(minLength: 20)
                        
                        controlButtons(proxy: proxy)
                            .padding(.bottom, 40)
                    }
                }
                .onChange(of: shouldScrollToTop) { _, newValue in
                    if newValue {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo("top", anchor: .top)
                            }
                            shouldScrollToTop = false
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private var lapTimesView: some View {
        NavigationStack {
            List {
                if workoutManager.lapTimes.isEmpty {
                    Text("ラップタイムはまだありません")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    ForEach(Array(workoutManager.lapTimes.enumerated()), id: \.offset) { index, time in
                        HStack {
                            Text("ラップ \(index + 1)")
                                .font(.headline)
                            Spacer()
                            Text(formatLapTime(time))
                                .font(.title3)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("ラップタイム")
        }
    }
    
    private func controlButtons(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 20) {
            Button {
                let wasPaused = workoutManager.isPaused
                if workoutManager.isPaused {
                    workoutManager.resumeWorkout()
                } else {
                    workoutManager.pauseWorkout()
                }
                if wasPaused == true {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo("top", anchor: .top)
                        }
                    }
                }
            } label: {
                Label(
                    workoutManager.isPaused ? "再開" : "一時停止",
                    systemImage: workoutManager.isPaused ? "play.fill" : "pause.fill"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .opacity(isButtonVisible ? 1.0 : 0.3)
            
            Button {
                Task {
                    await workoutManager.endWorkout()
                }
            } label: {
                Label("終了", systemImage: "xmark")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.red)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.horizontal)
    }
    
    private func formatLapTime(_ time: TimeInterval) -> String {
        let minutes = Int(time / 60)
        let seconds = Int(time.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d", minutes, seconds)
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
}

struct MetricCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.title3)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct PhoneMusicControlView: View {
    @StateObject private var musicController = PhoneMusicController()
    @State private var volume: Double = 0.5
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                nowPlayingInfo
                    .padding(.top)
                playbackControls
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
    
    private var nowPlayingInfo: some View {
        VStack(spacing: 12) {
            if let title = musicController.currentTrackTitle {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                if let artist = musicController.currentArtist {
                    Text(artist)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                if let album = musicController.currentAlbum {
                    Text(album)
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text("再生していません")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
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
            return
        }
        currentTrackTitle = nowPlayingInfo[MPMediaItemPropertyTitle] as? String
        currentArtist = nowPlayingInfo[MPMediaItemPropertyArtist] as? String
        currentAlbum = nowPlayingInfo[MPMediaItemPropertyAlbumTitle] as? String
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
