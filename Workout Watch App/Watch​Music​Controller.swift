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
        VStack(spacing: 4) {
            // 上部: 曲情報エリア（コンパクト化）
            VStack(spacing: 3) {
                // アルバムアート風のアイコン（サイズ縮小）
                Image(systemName: "music.note")
                    .font(.system(size: 32))
                    .foregroundStyle(.pink)
                    .frame(width: 50, height: 50)
                    .background(Color.pink.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                
                // 曲名（小さく）
                Text("再生していません")
                    .font(.subheadline)
                    .lineLimit(1)
                
                // アーティスト名（小さく）
                Text("音楽を再生してください")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
            
            Spacer(minLength: 8)
            
            // 中央: 再生コントロール（コンパクト化）
            HStack(spacing: 35) {
                // 前の曲ボタン
                Button {
                    print("⏮️ Previous track")
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(!isPlaying)
                .opacity(isPlaying ? 1.0 : 0.4)
                
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
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                
                // 次の曲ボタン
                Button {
                    print("⏭️ Next track")
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(!isPlaying)
                .opacity(isPlaying ? 1.0 : 0.4)
            }
            .padding(.vertical, 8)
            
            Spacer(minLength: 8)
            
            // 下部: Digital Crown対応の音量スライダー（コンパクト化）
            VStack(spacing: 6) {
                HStack {
                    // 左: 音量ダウンボタン（-5%）
                    Button {
                        decreaseVolume()
                    } label: {
                        Image(systemName: volume == 0 ? "speaker.slash.fill" : "speaker.fill")
                            .font(.system(size: 16))  // 10 → 16に拡大
                            .foregroundStyle(.pink)  // ピンク色に変更
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    // 音量パーセンテージ表示
                    Text("\(Int(volume * 100))%")
                        .font(.system(size: 16))  // 10 → 16に拡大
                        .foregroundStyle(.white)  // より見やすく白色に
                        .monospacedDigit()
                    
                    Spacer()
                    
                    // 右: 音量アップボタン（+5%）
                    Button {
                        increaseVolume()
                    } label: {
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: 16))  // 10 → 16に拡大
                            .foregroundStyle(.pink)  // ピンク色に変更
                    }
                    .buttonStyle(.plain)
                }
                
                // Digital Crown対応の音量バー
                VolumeSliderView(volume: $volume, isFocused: $isVolumeFocused)
                    .frame(height: 6)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 32)  // さらに2倍に拡大（16 → 32）
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
    
    // 音量を5%下げる
    private func decreaseVolume() {
        let newVolume = max(0.0, volume - 0.05)
        volume = newVolume
        
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
        }
        .focusable(true)
        .focused($isFocused)
        .digitalCrownRotation(
            $volume,
            from: 0.0,
            through: 1.0,
            by: 0.0001,  // 0.01%ずつ調整（非常に小さく、かなり回さないと変化しない）
            sensitivity: .low,  // 低感度
            isContinuous: false,
            isHapticFeedbackEnabled: false  // 細かすぎるのでハプティックOFF
        )
        .onChange(of: volume) { oldValue, newValue in
            // 音量変更時のログ
            print("🔊 Volume changed: \(Int(newValue * 100))%")
            
            // ハプティックフィードバック（0%と100%の時のみ）
            if newValue == 0.0 || newValue == 1.0 {
                WKInterfaceDevice.current().play(.notification)
            }
        }
    }
}

#Preview {
    MusicControlView()
}
