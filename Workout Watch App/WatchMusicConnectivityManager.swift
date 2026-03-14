//
//  WatchMusicConnectivityManager.swift
//  Workout Watch App
//
//  Created on 2026/03/14.
//

#if os(watchOS)
import Foundation
import Combine
import WatchConnectivity

// Apple Watch側 Watch Connectivity Manager
class WatchMusicConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchMusicConnectivityManager()
    
    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil
    
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
            session.activate()
        }
        
        // 初期の音楽情報を取得
        requestNowPlayingInfo()
    }
    
    // 現在再生中の音楽情報を取得
    func requestNowPlayingInfo() {
        guard let session = session, session.isReachable else {
            print("🎵 iPhone is not reachable")
            return
        }
        
        let message = ["command": "getNowPlayingInfo"]
        
        session.sendMessage(message, replyHandler: { [weak self] reply in
            DispatchQueue.main.async {
                self?.updateMusicInfo(from: reply)
            }
        }, errorHandler: { error in
            print("🎵 Error requesting music info: \(error.localizedDescription)")
        })
    }
    
    // 受信した音楽情報を更新
    private func updateMusicInfo(from info: [String: Any]) {
        if let playing = info["isPlaying"] as? Bool {
            isPlaying = playing
        }
        
        currentTrackTitle = info["title"] as? String
        currentArtist = info["artist"] as? String
        currentAlbum = info["album"] as? String
        
        if let time = info["playbackTime"] as? TimeInterval {
            playbackTime = time
        }
        
        if let dur = info["duration"] as? TimeInterval {
            duration = dur
        }
        
        print("🎵 Music info updated: \(currentTrackTitle ?? "Unknown")")
    }
    
    // 再生/一時停止のトグル
    func togglePlayPause() {
        sendCommand("togglePlayPause")
    }
    
    // 次の曲へ
    func skipToNext() {
        sendCommand("skipToNext")
    }
    
    // 前の曲へ
    func skipToPrevious() {
        sendCommand("skipToPrevious")
    }
    
    // 音量を設定
    func setVolume(_ volume: Double) {
        guard let session = session, session.isReachable else {
            print("🔊 iPhone is not reachable for volume control")
            return
        }
        
        let message: [String: Any] = [
            "command": "setVolume",
            "volume": volume
        ]
        
        session.sendMessage(message, replyHandler: { reply in
            if let success = reply["success"] as? Bool, success {
                print("🔊 Volume set to \(Int(volume * 100))% on iPhone")
            }
        }, errorHandler: { error in
            print("🔊 Error setting volume: \(error.localizedDescription)")
        })
    }
    
    // コマンドを送信（汎用）
    private func sendCommand(_ command: String) {
        guard let session = session, session.isReachable else {
            print("🎵 iPhone is not reachable for command: \(command)")
            return
        }
        
        let message = ["command": command]
        
        session.sendMessage(message, replyHandler: { [weak self] reply in
            // コマンド実行後、音楽情報を更新
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self?.requestNowPlayingInfo()
            }
        }, errorHandler: { error in
            print("🎵 Error sending command '\(command)': \(error.localizedDescription)")
        })
    }
}

extension WatchMusicConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("🎵 WCSession activation failed: \(error.localizedDescription)")
        } else {
            print("🎵 WCSession activated with state: \(activationState.rawValue)")
            
            // アクティベーション完了後、音楽情報を取得
            if activationState == .activated {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.requestNowPlayingInfo()
                }
            }
        }
    }
    
    // iPhoneからのメッセージを受信
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        print("🎵 Received message from iPhone: \(message)")
        
        // 音楽情報の更新
        if message["musicInfo"] != nil {
            DispatchQueue.main.async { [weak self] in
                self?.updateMusicInfo(from: message)
            }
        }
    }
}
#endif // os(watchOS)
