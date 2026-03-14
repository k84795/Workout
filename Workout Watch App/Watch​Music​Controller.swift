//
//  Watch​Music​Controller.swift
//  Workout Watch App
//
//  Created by 山中雄樹 on 2026/03/12.
//

import SwiftUI
import WatchKit
import AVFoundation

struct MusicControlView: View {
    @State private var isPlaying = false
    @State private var volume: Double = 0.5  // 0.0 ~ 1.0
    @FocusState private var isVolumeFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // 上部の余白
            Spacer(minLength: 16)
            
            // 上部: 曲情報エリア（少しコンパクトに）
            VStack(spacing: 4) {
                // アルバムアート風のアイコン（少し小さく）
                ZStack {
                    // グラデーション背景
                    LinearGradient(
                        colors: [.pink.opacity(0.6), .purple.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    
                    Image(systemName: isPlaying ? "music.note" : "music.note.list")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(.white)
                        .symbolEffect(.pulse, isActive: isPlaying)
                }
                .frame(width: 65, height: 65)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .pink.opacity(0.3), radius: 8, x: 0, y: 4)
                
                // 曲名（見やすく）
                Text(isPlaying ? "Now Playing" : "再生していません")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                
                // アーティスト名・ステータス
                Text(isPlaying ? "Apple Music" : "音楽を再生してください")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            
            Spacer(minLength: 6)
            
            // 中央: 再生コントロール
            HStack(spacing: 32) {
                // 前の曲ボタン
                Button {
                    print("⏮️ Previous track")
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                
                // 再生/一時停止ボタン（中央）
                Button {
                    if isPlaying {
                        print("⏸️ Pause")
                        isPlaying = false
                    } else {
                        print("▶️ Play - Opening Music app...")
                        openMusicApp()
                    }
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.pink)
                        .symbolEffect(.bounce, value: isPlaying)
                }
                .buttonStyle(.plain)
                
                // 次の曲ボタン
                Button {
                    print("⏭️ Next track")
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            
            Spacer(minLength: 6)
            
            // 下部: Digital Crown対応の音量スライダー
            VStack(spacing: 4) {
                HStack {
                    // 左: 音量ダウンボタン（-5%）
                    Button {
                        decreaseVolume()
                    } label: {
                        Image(systemName: volume == 0 ? "speaker.slash.fill" : "speaker.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.pink)
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    // 音量パーセンテージ表示
                    Text("\(Int(volume * 100))%")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    
                    Spacer()
                    
                    // 右: 音量アップボタン（+5%）
                    Button {
                        increaseVolume()
                    } label: {
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.pink)
                    }
                    .buttonStyle(.plain)
                }
                
                // Digital Crown対応の音量バー
                VolumeSliderView(volume: $volume, isFocused: $isVolumeFocused)
                    .frame(height: 6)
            }
            .padding(.horizontal, 10)
            
            // 下部の余白（音量バーの下）
            Spacer(minLength: 35)
        }
        .padding(.horizontal, 8)
        .onAppear {
            // 現在のシステム音量を取得
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
    
    // Apple Watch自体のシステム音量を設定
    private func setWatchVolume(_ volume: Double) {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setActive(true)
            
            // AVAudioSessionで音量設定を試みる
            // 注意: watchOSでは直接的な音量設定が制限されている場合があります
            print("🔊 Attempting to set Watch volume to: \(Int(volume * 100))%")
            
            // MPVolumeViewを使った代替手段（watchOSでは利用できない可能性あり）
            // このため、UIのバーだけが変わり、実際の音量は変わらない可能性があります
            
        } catch {
            print("❌ Failed to set Watch volume: \(error.localizedDescription)")
        }
    }
    
    // 音量を5%下げる
    private func decreaseVolume() {
        let newVolume = max(0.0, volume - 0.05)
        volume = newVolume
        
        // Apple Watch自体の音量を設定
        setWatchVolume(newVolume)
        
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
        
        // Apple Watch自体の音量を設定
        setWatchVolume(newVolume)
        
        // ハプティックフィードバック
        WKInterfaceDevice.current().play(.click)
        
        // 100%に到達した場合は特別な振動
        if newVolume == 1.0 {
            WKInterfaceDevice.current().play(.notification)
        }
        
        print("🔊 Volume increased to: \(Int(newVolume * 100))%")
    }
    
    // ミュージックアプリを起動
    private func openMusicApp() {
        print("🎵 Opening Music app...")
        
        // 複数の音楽アプリURLスキームを試す
        let musicURLs = [
            "music://",           // Apple Music
            "spotify://",         // Spotify
            "amazonmusic://",     // Amazon Music
            "youtube://"          // YouTube Music
        ]
        
        // 順番に試す
        for urlString in musicURLs {
            if let url = URL(string: urlString) {
                WKExtension.shared().openSystemURL(url)
                print("🎵 Tried to open: \(urlString)")
                break
            }
        }
        
        print("💡 ワークアウトはバックグラウンドで継続します")
    }
}

// Digital Crown対応の音量スライダー
struct VolumeSliderView: View {
    @Binding var volume: Double
    @FocusState.Binding var isFocused: Bool
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // 背景
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 6)
                
                // 音量レベル（緑色）
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.green)  // 緑色
                    .frame(width: geometry.size.width * volume, height: 6)
                    .animation(.easeInOut(duration: 0.1), value: volume)
                
                // フォーカスインジケーター（Digital Crownで操作中）
                if isFocused {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Color.green, lineWidth: 1.5)  // 緑色
                        .frame(height: 6)
                }
            }
            .contentShape(Rectangle())  // タップ可能領域を拡大
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
            by: 0.005,  // 0.5%ずつ調整（細かく調整可能）
            sensitivity: .low,  // 低感度で急激な変化を防ぐ
            isContinuous: false,
            isHapticFeedbackEnabled: false  // 細かい変化なのでハプティックOFF
        )
        .onChange(of: volume) { oldValue, newValue in
            // 音量変更時のログ
            print("🔊 Volume changed: \(Int(newValue * 100))%")
            
            // ハプティックフィードバック（5%ごと）
            let oldPercent = Int(oldValue * 20)  // 5%単位に丸める
            let newPercent = Int(newValue * 20)
            if oldPercent != newPercent {
                WKInterfaceDevice.current().play(.click)
            }
            
            // 0%と100%の時は特別な振動
            if newValue == 0.0 || newValue == 1.0 {
                WKInterfaceDevice.current().play(.notification)
            }
        }
    }
}

#Preview {
    MusicControlView()
}
