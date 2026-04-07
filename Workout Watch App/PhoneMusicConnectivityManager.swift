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
    
    // 公開プロパティ（iPhone単体モードで使用）
    @Published var isPlaying: Bool = false
    @Published var currentTrackTitle: String? = nil
    @Published var currentArtist: String? = nil
    @Published var currentAlbum: String? = nil
    @Published var playbackTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    
    private override init() {
        super.init()
        
        if let session = session {
            session.delegate = self
            // WCSessionのactivateは非同期で呼ぶべき
            DispatchQueue.global(qos: .userInitiated).async {
                session.activate()
            }
        }
        
        // 音楽プレイヤーの通知を監視
        setupMusicNotifications()
        
        // 初期状態を更新
        updateMusicState()
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
            self?.updateMusicState()
            self?.sendMusicInfoToWatch()
        }
        
        // 曲の変更を監視
        NotificationCenter.default.addObserver(
            forName: .MPMusicPlayerControllerNowPlayingItemDidChange,
            object: musicPlayer,
            queue: .main
        ) { [weak self] _ in
            self?.updateMusicState()
            self?.sendMusicInfoToWatch()
        }
    }
    
    // 音楽の状態を更新（iPhone単体モード用）
    private func updateMusicState() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 再生状態
            self.isPlaying = self.musicPlayer.playbackState == .playing
            
            // 現在再生中の曲情報
            if let nowPlayingItem = self.musicPlayer.nowPlayingItem {
                self.currentTrackTitle = nowPlayingItem.title
                self.currentArtist = nowPlayingItem.artist
                self.currentAlbum = nowPlayingItem.albumTitle
                
                // 再生時間
                self.playbackTime = self.musicPlayer.currentPlaybackTime
                self.duration = nowPlayingItem.playbackDuration
            } else {
                self.currentTrackTitle = nil
                self.currentArtist = nil
                self.currentAlbum = nil
                self.playbackTime = 0
                self.duration = 0
            }
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
    
    // 再生/一時停止のトグル（公開メソッド - iPhone単体モードでも使用可能）
    func togglePlayPause() {
        if musicPlayer.playbackState == .playing {
            musicPlayer.pause()
            print("🎵 Music paused")
        } else {
            musicPlayer.play()
            print("🎵 Music playing")
        }
        
        // すぐにWatchに更新を送信
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.updateMusicState()
            self?.sendMusicInfoToWatch()
        }
    }
    
    // 次の曲へ（公開メソッド - iPhone単体モードでも使用可能）
    func skipToNext() {
        musicPlayer.skipToNextItem()
        print("🎵 Skipped to next track")
        
        // 少し遅延してから情報を更新
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.updateMusicState()
            self?.sendMusicInfoToWatch()
        }
    }
    
    // 前の曲へ（公開メソッド - iPhone単体モードでも使用可能）
    func skipToPrevious() {
        musicPlayer.skipToPreviousItem()
        print("🎵 Skipped to previous track")
        
        // 少し遅延してから情報を更新
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.updateMusicState()
            self?.sendMusicInfoToWatch()
        }
    }
    
    // 音量を設定（Watchからのリクエスト用 - 実装は保留）
    func setVolume(_ volume: Double) {
        print("🔊 Volume change requested: \(Int(volume * 100))% - Feature not implemented in new UI")
        // 新しいUIでは音量バーを廃止したため、この機能は使用しない
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

