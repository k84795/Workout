//
//  MusicControlView.swift
//  Workout Watch App
//
//  Created on 2026/03/09.
//

import SwiftUI
import WatchKit
import Combine
import MediaPlayer
import WatchConnectivity
import AVFoundation

struct MusicControlView: View {
    @Environment(\.scenePhase) var scenePhase
    @StateObject private var musicController = WatchMusicController()
    @State private var volume: Double = 0.5
    
    // 画面サイズに応じたスケール係数
    private var sizeScale: CGFloat {
        let screenWidth = WKInterfaceDevice.current().screenBounds.width
        return screenWidth / 162.0
    }
    
    var body: some View {
        VStack(spacing: 2) {
            // 曲情報表示
            nowPlayingInfo
                .padding(.top, 16)
                .padding(.horizontal, 8)
            
            // 再生コントロール（上部）
            playbackControls
                .padding(.top, 2)
                .padding(.bottom, 2)
            
            // 音量スライダー
            volumeControl
                .padding(.horizontal, 8)
                .padding(.vertical, 1)
            
            Spacer(minLength: 0)
        }
        .scrollIndicators(.hidden)
        .focusable()
        .digitalCrownRotation(
            $volume,
            from: 0.0,
            through: 1.0,
            by: 0.003,
            sensitivity: .low,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: volume) { oldValue, newValue in
            // 0から1の範囲に制限
            let clampedValue = max(0.0, min(1.0, newValue))
            if clampedValue != newValue {
                volume = clampedValue
            }
            musicController.setVolume(clampedValue)
        }
        .onAppear {
            print("🎵 MusicControlView appeared")
            volume = musicController.volume
            musicController.startMonitoring()
        }
        .onDisappear {
            print("🎵 MusicControlView disappeared")
            musicController.stopMonitoring()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            print("🎵 Scene phase changed from \(oldPhase) to \(newPhase)")
            if newPhase == .background {
                print("🎵 App moved to background - workout continues")
            } else if newPhase == .active {
                print("🎵 App became active again")
                // 音量を再同期
                volume = musicController.volume
            }
        }
    }
    
    // 曲情報表示
    private var nowPlayingInfo: some View {
        VStack(spacing: 2) {
            // 接続状態インジケーター
            if !musicController.isConnectedToPhone {
                HStack(spacing: 4) {
                    Image(systemName: "applewatch")
                        .font(.system(size: 10 * sizeScale))
                    Text("Watch単体")
                        .font(.system(size: 9 * sizeScale))
                }
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)
            }
            
            if let title = musicController.currentTrackTitle {
                Text(title)
                    .font(.system(size: 12 * sizeScale, weight: .semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("再生していません")
                    .font(.system(size: 14 * sizeScale, weight: .medium))
                    .foregroundStyle(.white)
            }
            
            if let artist = musicController.currentArtist {
                Text(artist)
                    .font(.system(size: 11 * sizeScale))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            
            if let album = musicController.currentAlbum {
                Text(album)
                    .font(.system(size: 10 * sizeScale))
                    .lineLimit(1)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
    
    // 再生コントロール
    private var playbackControls: some View {
        HStack(spacing: 20 * sizeScale) {
            // 前の曲
            Button {
                musicController.skipToPrevious()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 22 * sizeScale))
                    .foregroundStyle(Color.pink)
            }
            .buttonStyle(.plain)
            
            // 再生/一時停止
            Button {
                musicController.togglePlayPause()
            } label: {
                Image(systemName: musicController.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 44 * sizeScale))
                    .foregroundStyle(Color.pink)
            }
            .buttonStyle(.plain)
            
            // 次の曲
            Button {
                musicController.skipToNext()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 22 * sizeScale))
                    .foregroundStyle(Color.pink)
            }
            .buttonStyle(.plain)
        }
    }
    
    // 音量コントロール
    private var volumeControl: some View {
        VStack(spacing: 2) {
            HStack(spacing: 12 * sizeScale) {
                // 音量を下げる
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        volume = max(0.0, volume - 0.05)
                    }
                } label: {
                    Image(systemName: "speaker.minus.fill")
                        .font(.system(size: 18 * sizeScale))
                        .foregroundStyle(Color.pink)
                        .frame(width: 32 * sizeScale, height: 32 * sizeScale)
                }
                .buttonStyle(.plain)
                .disabled(volume <= 0.0)
                .opacity(volume <= 0.0 ? 0.3 : 1.0)
                
                // 音量表示（横長バー）
                VStack(spacing: 4) {
                    // 音量バー
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // 背景バー
                            RoundedRectangle(cornerRadius: 2)
                                .fill(.secondary.opacity(0.3))
                                .frame(height: 6)
                            
                            // 音量レベルバー
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.green)
                                .frame(width: geometry.size.width * volume, height: 6)
                                .animation(.easeInOut(duration: 0.2), value: volume)
                        }
                    }
                    .frame(height: 6)
                    
                    // 音量パーセンテージ
                    Text("\(Int(round(volume * 100)))%")
                        .font(.system(size: 11 * sizeScale, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity)
                
                // 音量を上げる
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        volume = min(1.0, volume + 0.05)
                    }
                } label: {
                    Image(systemName: "speaker.plus.fill")
                        .font(.system(size: 18 * sizeScale))
                        .foregroundStyle(Color.pink)
                        .frame(width: 32 * sizeScale, height: 32 * sizeScale)
                }
                .buttonStyle(.plain)
                .disabled(volume >= 1.0)
                .opacity(volume >= 1.0 ? 0.3 : 1.0)
            }
        }
    }
    
    // 音量に応じたアイコン（使用していませんが保持）
    private var volumeIcon: String {
        if volume == 0 {
            return "speaker.slash.fill"
        } else if volume < 0.33 {
            return "speaker.wave.1.fill"
        } else if volume < 0.66 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }
}

// watchOS用ミュージックコントローラー（ハイブリッド実装）
@MainActor
class WatchMusicController: ObservableObject {
    @Published var isPlaying: Bool = false
    @Published var volume: Double = 0.5
    @Published var currentTrackTitle: String? = nil
    @Published var currentArtist: String? = nil
    @Published var currentAlbum: String? = nil
    @Published var isConnectedToPhone: Bool = false
    
    private var timer: Timer?
    private let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
    private let remoteCommandCenter = MPRemoteCommandCenter.shared()
    private var connectivityManager: WatchConnectivityManager?
    
    init() {
        // 初期化
        loadVolume()
        setupAudioSession()
        setupRemoteCommands()
        setupConnectivity()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // オーディオセッションのセットアップ
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
            print("🎵 Audio session activated")
        } catch {
            print("🎵 Failed to setup audio session: \(error)")
        }
    }
    
    // Watch Connectivityのセットアップ
    private func setupConnectivity() {
        guard WCSession.isSupported() else {
            print("🎵 WCSession not supported")
            isConnectedToPhone = false
            return
        }
        
        connectivityManager = WatchConnectivityManager.shared
        
        // iPhone接続状態を監視
        connectivityManager?.onConnectionStatusChanged = { [weak self] isConnected in
            Task { @MainActor in
                self?.isConnectedToPhone = isConnected
                print("🎵 iPhone connection: \(isConnected ? "✅ Connected" : "❌ Disconnected")")
            }
        }
        
        // 音楽情報を受信
        connectivityManager?.onMusicInfoReceived = { [weak self] info in
            Task { @MainActor in
                self?.handleMusicInfoFromPhone(info)
            }
        }
    }
    
    // リモートコマンドのセットアップ
    private func setupRemoteCommands() {
        // 再生コマンド
        remoteCommandCenter.playCommand.isEnabled = true
        remoteCommandCenter.playCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            Task { @MainActor [weak self] in
                self?.isPlaying = true
                self?.updateNowPlayingInfoLocal()
            }
            return .success
        }
        
        // 一時停止コマンド
        remoteCommandCenter.pauseCommand.isEnabled = true
        remoteCommandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            Task { @MainActor [weak self] in
                self?.isPlaying = false
            }
            return .success
        }
        
        // 次の曲
        remoteCommandCenter.nextTrackCommand.isEnabled = true
        remoteCommandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            Task { @MainActor [weak self] in
                self?.updateNowPlayingInfoLocal()
            }
            return .success
        }
        
        // 前の曲
        remoteCommandCenter.previousTrackCommand.isEnabled = true
        remoteCommandCenter.previousTrackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            Task { @MainActor [weak self] in
                self?.updateNowPlayingInfoLocal()
            }
            return .success
        }
    }
    
    func startMonitoring() {
        print("🎵 Music monitoring started")
        
        // 初期の接続状態を確認
        if let session = WCSession.default as WCSession?, session.isReachable {
            isConnectedToPhone = true
            connectivityManager?.requestNowPlayingInfo()
        } else {
            isConnectedToPhone = false
            updateNowPlayingInfoLocal()
        }
        
        // 定期的に更新
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                if self.isConnectedToPhone {
                    // iPhoneから情報を取得
                    self.connectivityManager?.requestNowPlayingInfo()
                } else {
                    // ローカルで情報を取得
                    self.updateNowPlayingInfoLocal()
                }
            }
        }
    }
    
    func stopMonitoring() {
        print("🎵 Music monitoring stopped")
        timer?.invalidate()
        timer = nil
    }
    
    // ローカルの再生情報を更新（Watch単体）
    private func updateNowPlayingInfoLocal() {
        guard let nowPlayingInfo = nowPlayingInfoCenter.nowPlayingInfo else {
            print("🎵 No track currently playing (local)")
            
            // iPhoneからの情報がない場合のみクリア
            if !isConnectedToPhone {
                currentTrackTitle = nil
                currentArtist = nil
                currentAlbum = nil
            }
            return
        }
        
        // 曲名を取得
        if let title = nowPlayingInfo[MPMediaItemPropertyTitle] as? String {
            currentTrackTitle = title
        }
        
        // アーティスト名を取得
        if let artist = nowPlayingInfo[MPMediaItemPropertyArtist] as? String {
            currentArtist = artist
        }
        
        // アルバム名を取得
        if let album = nowPlayingInfo[MPMediaItemPropertyAlbumTitle] as? String {
            currentAlbum = album
        }
        
        // 再生状態を取得
        if let rate = nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] as? Double {
            isPlaying = rate > 0
        }
        
        print("🎵 Now Playing (Watch): \(currentTrackTitle ?? "unknown")")
    }
    
    // iPhoneから受信した音楽情報を処理
    private func handleMusicInfoFromPhone(_ info: [String: Any]) {
        if let title = info["title"] as? String {
            currentTrackTitle = title
        }
        
        if let artist = info["artist"] as? String {
            currentArtist = artist
        }
        
        if let album = info["album"] as? String {
            currentAlbum = album
        }
        
        if let playing = info["isPlaying"] as? Bool {
            isPlaying = playing
        }
        
        print("🎵 Now Playing (iPhone): \(currentTrackTitle ?? "unknown")")
    }
    
    // 再生/一時停止のトグル
    func togglePlayPause() {
        WKInterfaceDevice.current().play(.click)
        
        if isConnectedToPhone {
            // iPhoneに送信
            connectivityManager?.sendCommand("togglePlayPause")
            isPlaying.toggle()
            print("🎵 Play/Pause → iPhone")
        } else {
            // Watch単体では表示のみ（実際の制御はApple Musicアプリで）
            print("🎵 Play/Pause → Watch単体モード（制御不可）")
            // Note: ユーザーにApple Musicアプリで操作するよう促すことも可能
        }
    }
    
    // 次の曲へ
    func skipToNext() {
        WKInterfaceDevice.current().play(.click)
        
        if isConnectedToPhone {
            connectivityManager?.sendCommand("skipToNext")
            print("🎵 Skip Next → iPhone")
            
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
                self?.connectivityManager?.requestNowPlayingInfo()
            }
        } else {
            print("🎵 Skip Next → Watch単体モード（制御不可）")
        }
    }
    
    // 前の曲へ
    func skipToPrevious() {
        WKInterfaceDevice.current().play(.click)
        
        if isConnectedToPhone {
            connectivityManager?.sendCommand("skipToPrevious")
            print("🎵 Skip Previous → iPhone")
            
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
                self?.connectivityManager?.requestNowPlayingInfo()
            }
        } else {
            print("🎵 Skip Previous → Watch単体モード（制御不可）")
        }
    }
    
    // 音量を設定
    func setVolume(_ newVolume: Double) {
        let oldVolume = volume
        volume = newVolume
        saveVolume()
        
        if isConnectedToPhone {
            // iPhoneに送信
            connectivityManager?.sendVolumeChange(newVolume)
        }
        
        // 軽いハプティックフィードバック（5%刻みごと）
        let oldLevel = Int(oldVolume * 20)
        let newLevel = Int(newVolume * 20)
        
        if oldLevel != newLevel {
            WKInterfaceDevice.current().play(.click)
            print("🎵 Volume: \(Int(newVolume * 100))%")
        }
    }
    
    // 音量を保存
    private func saveVolume() {
        UserDefaults.standard.set(volume, forKey: "musicVolume")
    }
    
    // 音量を読み込み
    private func loadVolume() {
        let savedVolume = UserDefaults.standard.double(forKey: "musicVolume")
        if savedVolume > 0 {
            volume = savedVolume
        } else {
            volume = 0.5
        }
        print("🎵 Loaded volume: \(Int(volume * 100))%")
    }
}

// Watch Connectivity Manager (Watch側)
class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()
    
    private var session: WCSession?
    
    var onMusicInfoReceived: (([String: Any]) -> Void)?
    var onConnectionStatusChanged: ((Bool) -> Void)?
    
    private override init() {
        super.init()
        
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
    }
    
    // iPhoneに現在の再生情報を要求
    func requestNowPlayingInfo() {
        guard let session = session, session.isReachable else {
            print("🎵 iPhone is not reachable")
            onConnectionStatusChanged?(false)
            return
        }
        
        let message = ["command": "getNowPlayingInfo"]
        session.sendMessage(message, replyHandler: { [weak self] response in
            print("🎵 Received music info from iPhone")
            self?.onMusicInfoReceived?(response)
            self?.onConnectionStatusChanged?(true)
        }, errorHandler: { error in
            print("🎵 Error requesting music info: \(error.localizedDescription)")
        })
    }
    
    // iPhoneにコマンドを送信
    func sendCommand(_ command: String) {
        guard let session = session, session.isReachable else {
            print("🎵 iPhone is not reachable")
            onConnectionStatusChanged?(false)
            return
        }
        
        let message = ["command": command]
        session.sendMessage(message, replyHandler: nil, errorHandler: { error in
            print("🎵 Error sending command: \(error.localizedDescription)")
        })
    }
    
    // iPhoneに音量変更を送信
    func sendVolumeChange(_ volume: Double) {
        guard let session = session, session.isReachable else {
            print("🎵 iPhone is not reachable")
            return
        }
        
        let message = ["command": "setVolume", "volume": volume] as [String : Any]
        session.sendMessage(message, replyHandler: nil, errorHandler: { error in
            print("🎵 Error sending volume change: \(error.localizedDescription)")
        })
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("🎵 WCSession activation failed: \(error.localizedDescription)")
            onConnectionStatusChanged?(false)
        } else {
            print("🎵 WCSession activated with state: \(activationState.rawValue)")
            let isConnected = session.isReachable
            onConnectionStatusChanged?(isConnected)
        }
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        let isConnected = session.isReachable
        print("🎵 Session reachability changed: \(isConnected)")
        onConnectionStatusChanged?(isConnected)
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        print("🎵 Received message from iPhone: \(message)")
        
        // iPhoneからの音楽情報更新を受信
        if let _ = message["musicInfo"] {
            onMusicInfoReceived?(message)
        }
    }
}

#Preview {
    MusicControlView()
}

