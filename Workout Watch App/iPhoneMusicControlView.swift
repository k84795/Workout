//
//  iPhoneMusicControlView.swift
//  Workout (iPhone App)
//
//  Created on 2026/03/12.
//

#if os(iOS)
import SwiftUI
import MediaPlayer

struct iPhoneMusicControlView: View {
    @StateObject private var musicManager = PhoneMusicConnectivityManager.shared
    @State private var volume: Double = 0.5
    
    var body: some View {
        VStack(spacing: 20) {
            // 曲情報表示
            nowPlayingInfo
                .padding(.top, 20)
            
            // 再生コントロール
            playbackControls
                .padding(.vertical, 20)
            
            // 音量スライダー
            volumeControl
                .padding(.horizontal, 30)
                .padding(.bottom, 20)
            
            Spacer()
        }
        .padding()
        .onAppear {
            print("🎵 iPhone MusicControlView appeared")
            loadVolume()
        }
    }
    
    // 曲情報表示
    private var nowPlayingInfo: some View {
        VStack(spacing: 12) {
            // アルバムアートワークのプレースホルダー
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 200, height: 200)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)
                )
            
            if let title = musicManager.currentTrackTitle {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            } else {
                Text("再生していません")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            
            if let artist = musicManager.currentArtist {
                Text(artist)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            if let album = musicManager.currentAlbum {
                Text(album)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            
            // 再生時間表示
            if musicManager.duration > 0 {
                VStack(spacing: 8) {
                    // プログレスバー
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 4)
                            
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.pink)
                                .frame(
                                    width: geometry.size.width * (musicManager.playbackTime / musicManager.duration),
                                    height: 4
                                )
                        }
                    }
                    .frame(height: 4)
                    
                    // 時間表示
                    HStack {
                        Text(formatTime(musicManager.playbackTime))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        
                        Spacer()
                        
                        Text(formatTime(musicManager.duration))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal, 30)
                .padding(.top, 8)
            }
        }
    }
    
    // 再生コントロール
    private var playbackControls: some View {
        HStack(spacing: 50) {
            // 前の曲
            Button {
                musicManager.skipToPrevious()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 35))
                    .foregroundStyle(Color.pink)
            }
            
            // 再生/一時停止
            Button {
                musicManager.togglePlayPause()
            } label: {
                Image(systemName: musicManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 70))
                    .foregroundStyle(Color.pink)
            }
            
            // 次の曲
            Button {
                musicManager.skipToNext()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 35))
                    .foregroundStyle(Color.pink)
            }
        }
    }
    
    // 音量コントロール
    private var volumeControl: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "speaker.fill")
                    .foregroundStyle(.secondary)
                
                Slider(value: $volume, in: 0...1)
                    .tint(.pink)
                    .onChange(of: volume) { oldValue, newValue in
                        musicManager.setVolume(newValue)
                        saveVolume()
                    }
                
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundStyle(.secondary)
            }
            
            Text("\(Int(round(volume * 100)))%")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
    
    // 時間をフォーマット
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // 音量を保存
    private func saveVolume() {
        UserDefaults.standard.set(volume, forKey: "iPhoneMusicVolume")
    }
    
    // 音量を読み込み
    private func loadVolume() {
        let savedVolume = UserDefaults.standard.double(forKey: "iPhoneMusicVolume")
        if savedVolume > 0 {
            volume = savedVolume
        } else {
            volume = 0.5
        }
    }
}

#Preview {
    iPhoneMusicControlView()
}
#endif // os(iOS)
