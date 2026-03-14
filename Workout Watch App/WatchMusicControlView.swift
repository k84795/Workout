//
//  WatchMusicControlView.swift
//  Workout Watch App
//
//  Created by 山中雄樹 on 2026/03/12.
//

#if os(watchOS)
import SwiftUI
import WatchKit
import AVFoundation

struct MusicControlView: View {
    @StateObject private var musicManager = WatchMusicConnectivityManager.shared
    @State private var volume: Double = 0.5  // 0.0 ~ 1.0
    @FocusState private var isVolumeFocused: Bool
    
    // 画面サイズに応じたスケール係数
    private var sizeScale: CGFloat {
        let screenWidth = WKInterfaceDevice.current().screenBounds.width
        // 40mm (162pt) を基準 (1.0)、45mm (184pt) で約1.14、Ultra (205pt) で約1.26
        return screenWidth / 162.0
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 上部の余白
            Spacer(minLength: 16)
            
            // 曲情報表示エリア（アートワーク付き）
            VStack(spacing: 4) {
                // アルバムアート風のアイコン
                ZStack {
                    // グラデーション背景
                    LinearGradient(
                        colors: [.pink.opacity(0.6), .purple.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    
                    Image(systemName: musicManager.isPlaying ? "music.note" : "music.note.list")
                        .font(.system(size: 40 * sizeScale, weight: .medium))
                        .foregroundStyle(.white)
                        .symbolEffect(.pulse, isActive: musicManager.isPlaying)
                }
                .frame(width: 65 * sizeScale, height: 65 * sizeScale)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .pink.opacity(0.3), radius: 8, x: 0, y: 4)
                
                // 曲情報
                if let title = musicManager.currentTrackTitle {
                    Text(title)
                        .font(.system(size: 14 * sizeScale, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    
                    if let artist = musicManager.currentArtist {
                        Text(artist)
                            .font(.system(size: 12 * sizeScale))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                } else {
                    Text("再生していません")
                        .font(.system(size: 13 * sizeScale))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            
            Spacer(minLength: 6)
            
            // 再生コントロールボタン
            HStack(spacing: 32 * sizeScale) {
                // 前の曲へ
                Button {
                    musicManager.skipToPrevious()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 18 * sizeScale))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                
                // 再生/一時停止
                Button {
                    musicManager.togglePlayPause()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.pink)
                            .frame(width: 44 * sizeScale, height: 44 * sizeScale)
                        
                        Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18 * sizeScale))
                            .foregroundStyle(.white)
                            .symbolEffect(.bounce, value: musicManager.isPlaying)
                    }
                }
                .buttonStyle(.plain)
                
                // 次の曲へ
                Button {
                    musicManager.skipToNext()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 18 * sizeScale))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            
            Spacer(minLength: 6)
            
            // 音量コントロール（Digital Crown対応）
            VStack(spacing: 4) {
                HStack {
                    // 左: 音量ダウンボタン（-5%）
                    Button {
                        decreaseVolume()
                    } label: {
                        Image(systemName: volume == 0 ? "speaker.slash.fill" : "speaker.fill")
                            .font(.system(size: 14 * sizeScale))
                            .foregroundStyle(.pink)
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    // 音量パーセンテージ表示
                    Text("\(Int(volume * 100))%")
                        .font(.system(size: 15 * sizeScale, weight: .medium))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    
                    Spacer()
                    
                    // 右: 音量アップボタン（+5%）
                    Button {
                        increaseVolume()
                    } label: {
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: 14 * sizeScale))
                            .foregroundStyle(.pink)
                    }
                    .buttonStyle(.plain)
                }
                
                // Digital Crown対応の音量バー
                VolumeSliderView(volume: $volume, isFocused: $isVolumeFocused, musicManager: musicManager)
                    .frame(height: 6)
            }
            .padding(.horizontal, 10)
            
            // 下部の余白
            Spacer(minLength: 35)
        }
        .padding(.horizontal, 8)
        .onAppear {
            // 画面表示時に音楽情報を更新
            musicManager.requestNowPlayingInfo()
            
            // システム音量を取得
            updateVolumeFromSystem()
            
            // 自動的に音量コントロールにフォーカス
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isVolumeFocused = true
            }
        }
    }
    
    // システム音量を取得
    private func updateVolumeFromSystem() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            volume = Double(AVAudioSession.sharedInstance().outputVolume)
            print("🔊 Current system volume: \(Int(volume * 100))%")
        } catch {
            print("❌ Failed to get system volume: \(error.localizedDescription)")
        }
    }
    
    // 音量を5%下げる
    private func decreaseVolume() {
        let newVolume = max(0.0, volume - 0.05)
        volume = newVolume
        
        // iPhoneの音量を設定
        musicManager.setVolume(newVolume)
        
        // ハプティックフィードバック
        WKInterfaceDevice.current().play(.click)
        
        // 0%に到達した場合は特別な振動
        if newVolume == 0.0 {
            WKInterfaceDevice.current().play(.notification)
        }
        
        print("🔊 Volume decreased to: \(Int(newVolume * 100))%")
    }
    
    // 音量を5%上げる
    private func increaseVolume() {
        let newVolume = min(1.0, volume + 0.05)
        volume = newVolume
        
        // iPhoneの音量を設定
        musicManager.setVolume(newVolume)
        
        // ハプティックフィードバック
        WKInterfaceDevice.current().play(.click)
        
        // 100%に到達した場合は特別な振動
        if newVolume == 1.0 {
            WKInterfaceDevice.current().play(.notification)
        }
        
        print("🔊 Volume increased to: \(Int(newVolume * 100))%")
    }
}

// Digital Crown対応の音量スライダー
struct VolumeSliderView: View {
    @Binding var volume: Double
    @FocusState.Binding var isFocused: Bool
    @ObservedObject var musicManager: WatchMusicConnectivityManager
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // 背景
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 6)
                
                // 音量レベル（緑色）
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.green)
                    .frame(width: geometry.size.width * volume, height: 6)
                    .animation(.easeInOut(duration: 0.1), value: volume)
                
                // フォーカスインジケーター（Digital Crownで操作中）
                if isFocused {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Color.green, lineWidth: 1.5)
                        .frame(height: 6)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // スワイプ/タップ位置に基づいて音量を設定
                        let newVolume = max(0.0, min(1.0, value.location.x / geometry.size.width))
                        
                        // 前回の値と異なる場合のみ更新
                        if abs(newVolume - volume) > 0.01 {
                            volume = newVolume
                            
                            // ハプティックフィードバック（5%ごと）
                            let percent = Int(newVolume * 20)
                            let oldPercent = Int(volume * 20)
                            if percent != oldPercent {
                                WKInterfaceDevice.current().play(.click)
                            }
                        }
                    }
                    .onEnded { value in
                        // 最終位置で音量を確定
                        let newVolume = max(0.0, min(1.0, value.location.x / geometry.size.width))
                        volume = newVolume
                        
                        // iPhoneに音量を送信
                        musicManager.setVolume(newVolume)
                        
                        print("🔊 Volume set to: \(Int(newVolume * 100))%")
                        
                        // 0%と100%の時は特別な振動
                        if newVolume == 0.0 || newVolume == 1.0 {
                            WKInterfaceDevice.current().play(.notification)
                        }
                    }
            )
        }
        .focusable(true)
        .focused($isFocused)
        .digitalCrownRotation(
            $volume,
            from: 0.0,
            through: 1.0,
            by: 0.005,  // 0.5%ずつ調整
            sensitivity: .low,
            isContinuous: false,
            isHapticFeedbackEnabled: false
        )
        .onChange(of: volume) { oldValue, newValue in
            // 音量変更時のログ
            print("🔊 Volume changed: \(Int(newValue * 100))%")
            
            // ハプティックフィードバック（5%ごと）
            let oldPercent = Int(oldValue * 20)
            let newPercent = Int(newValue * 20)
            if oldPercent != newPercent {
                WKInterfaceDevice.current().play(.click)
                
                // iPhoneに音量を送信
                musicManager.setVolume(newValue)
            }
            
            // 0%と100%の時は特別な振動
            if (oldValue != 0.0 && newValue == 0.0) || (oldValue != 1.0 && newValue == 1.0) {
                WKInterfaceDevice.current().play(.notification)
            }
        }
    }
}

#Preview {
    MusicControlView()
}
#endif // os(watchOS)
