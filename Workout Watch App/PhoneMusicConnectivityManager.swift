//
//  PhoneMusicConnectivityManager.swift
//  Workout (iPhone App)
//
//  Created on 2026/03/09.
//

#if os(iOS)
import Foundation
import Combine
import WatchConnectivity
import MediaPlayer

// iPhone側 Watch Connectivity Manager
class PhoneMusicConnectivityManager: NSObject, ObservableObject {
    static let shared = PhoneMusicConnectivityManager()
    
    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil
    private let musicPlayer = MPMusicPlayerController.systemMusicPlayer
    
    private override init() {
        super.init()
        
        if let session = session {
            session.delegate = self
            session.activate()
        }
        
        // 音楽プレイヤーの通知を監視
        setupMusicNotifications()
    }
    
    // 音楽の通知をセットアップ
    private func setupMusicNotifications() {
        musicPlayer.beginGeneratingPlaybackNotifications()
        
        // 再生状態の変更を監視
        NotificationCenter.default.addObserver(
            forName: .MPMusicPlayerControllerPlaybackStateDidChange,
            object: musicPlayer,
            queue: .main
        ) { [weak self] _ in
            self?.sendMusicInfoToWatch()
        }
        
        // 曲の変更を監視
        NotificationCenter.default.addObserver(
            forName: .MPMusicPlayerControllerNowPlayingItemDidChange,
            object: musicPlayer,
            queue: .main
        ) { [weak self] _ in
            self?.sendMusicInfoToWatch()
        }
    }
    
    // 現在の再生情報を取得
    private func getCurrentMusicInfo() -> [String: Any] {
        var info: [String: Any] = [:]
        
        // 再生状態
        info["isPlaying"] = musicPlayer.playbackState == .playing
        
        // 現在再生中の曲情報
        if let nowPlayingItem = musicPlayer.nowPlayingItem {
            if let title = nowPlayingItem.title {
                info["title"] = title
            }
            if let artist = nowPlayingItem.artist {
                info["artist"] = artist
            }
            if let album = nowPlayingItem.albumTitle {
                info["album"] = album
            }
            
            // 再生時間
            info["playbackTime"] = musicPlayer.currentPlaybackTime
            let duration = nowPlayingItem.playbackDuration
            if duration > 0 {
                info["duration"] = duration
            }
        }
        
        return info
    }
    
    // Watchに音楽情報を送信
    private func sendMusicInfoToWatch() {
        guard let session = session, session.isReachable else {
            print("🎵 Watch is not reachable")
            return
        }
        
        let musicInfo = getCurrentMusicInfo()
        var message = musicInfo
        message["musicInfo"] = true // フラグを追加
        
        session.sendMessage(message, replyHandler: nil, errorHandler: { error in
            print("🎵 Error sending music info to Watch: \(error.localizedDescription)")
        })
    }
    
    // 再生/一時停止のトグル
    private func togglePlayPause() {
        if musicPlayer.playbackState == .playing {
            musicPlayer.pause()
            print("🎵 Music paused")
        } else {
            musicPlayer.play()
            print("🎵 Music playing")
        }
        
        // すぐにWatchに更新を送信
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.sendMusicInfoToWatch()
        }
    }
    
    // 次の曲へ
    private func skipToNext() {
        musicPlayer.skipToNextItem()
        print("🎵 Skipped to next track")
        
        // 少し遅延してから情報を送信
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.sendMusicInfoToWatch()
        }
    }
    
    // 前の曲へ
    private func skipToPrevious() {
        musicPlayer.skipToPreviousItem()
        print("🎵 Skipped to previous track")
        
        // 少し遅延してから情報を送信
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.sendMusicInfoToWatch()
        }
    }
    
    // 音量を設定
    private func setVolume(_ volume: Double) {
        // MPMusicPlayerControllerには音量設定がないため、
        // MPVolumeViewやAVAudioSessionを使用する必要がある
        // ここではログのみ
        print("🎵 Volume change requested: \(Int(volume * 100))%")
        
        // Note: システム音量を変更するには、MPVolumeViewのスライダーを
        // プログラム的に操作する必要がありますが、Appleは推奨していません
    }
}

extension PhoneMusicConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("🎵 WCSession activation failed: \(error.localizedDescription)")
        } else {
            print("🎵 WCSession activated with state: \(activationState.rawValue)")
        }
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {
        print("🎵 WCSession became inactive")
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        print("🎵 WCSession deactivated")
        session.activate()
    }
    
    // Watchからのメッセージを受信
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        print("🎵 Received message from Watch: \(message)")
        
        guard let command = message["command"] as? String else {
            replyHandler([:])
            return
        }
        
        switch command {
        case "getNowPlayingInfo":
            // 現在の再生情報を返す
            let musicInfo = getCurrentMusicInfo()
            replyHandler(musicInfo)
            
        case "togglePlayPause":
            togglePlayPause()
            replyHandler(["success": true])
            
        case "skipToNext":
            skipToNext()
            replyHandler(["success": true])
            
        case "skipToPrevious":
            skipToPrevious()
            replyHandler(["success": true])
            
        case "setVolume":
            if let volume = message["volume"] as? Double {
                setVolume(volume)
            }
            replyHandler(["success": true])
            
        default:
            print("🎵 Unknown command: \(command)")
            replyHandler([:])
        }
    }
}
#endif // os(iOS)

