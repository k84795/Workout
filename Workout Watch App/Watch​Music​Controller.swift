//
//  Watch​Music​Controller.swift
//  Workout Watch App
//
//  Created by 山中雄樹 on 2026/03/12.
//

import SwiftUI
import WatchKit

struct MusicControlView: View {
    @State private var showHomeHint = false
    @State private var showMusicLaunchMessage = false
    
    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 20) {
                    // タイトル
                    Text("音楽")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 10)
                    
                    // 説明テキスト
                    VStack(spacing: 8) {
                        Text("再生していません")
                            .font(.body)
                            .multilineTextAlignment(.center)
                        
                        Text("音楽アプリを起動して")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Text("音楽を再生できます")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 20)
                    
                    // ミュージックアプリ起動ボタン
                    Button {
                        openMusicApp()
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "music.note")
                                .font(.system(size: 40))
                            Text("ミュージックアプリ")
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.pink.opacity(0.2))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    
                    // アプリ一覧ボタン
                    Button {
                        openAppGrid()
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "square.grid.3x3")
                                .font(.system(size: 30))
                            Text("アプリ一覧")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    
                    // 説明
                    VStack(spacing: 4) {
                        Text("Digital Crownを押して")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("他のアプリを起動できます")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.bottom, 10)
                }
                .padding(.horizontal)
            }
            
            // アプリ一覧への案内メッセージ
            if showHomeHint {
                VStack(spacing: 12) {
                    Image(systemName: "hand.point.up.left.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.pink)
                    
                    Text("⬜ Digital Crownを押すと")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    
                    Text("アプリ一覧に戻れます")
                        .font(.body)
                        .multilineTextAlignment(.center)
                    
                    Text("他の音楽アプリを起動できます")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
                .background(.ultraThinMaterial)
                .cornerRadius(16)
                .shadow(radius: 10)
                .padding()
                .transition(.scale.combined(with: .opacity))
            }
            
            // ミュージックアプリ起動メッセージ
            if showMusicLaunchMessage {
                VStack(spacing: 12) {
                    Image(systemName: "music.note")
                        .font(.system(size: 50))
                        .foregroundStyle(.pink)
                    
                    Text("🎵 ミュージックアプリを起動中")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    
                    Text("ワークアウトは継続します")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
                .background(.ultraThinMaterial)
                .cornerRadius(16)
                .shadow(radius: 10)
                .padding()
                .transition(.scale.combined(with: .opacity))
            }
        }
    }
    
    // アプリ一覧画面を開く（ヒントメッセージを表示）
    private func openAppGrid() {
        print("🏠 User tapped App Grid button")
        
        // 案内メッセージを表示
        withAnimation(.spring()) {
            showHomeHint = true
        }
        
        // 3秒後にメッセージを非表示
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation(.spring()) {
                showHomeHint = false
            }
        }
        
        print("💡 Digital Crownボタンを押してアプリ一覧に戻ることもできます")
        print("💡 ワークアウトはバックグラウンドで継続します")
    }
    
    // ミュージックアプリを起動
    private func openMusicApp() {
        print("🏠 Attempting to open Music app or home screen...")
        
        // ミュージックアプリ起動メッセージを表示
        withAnimation(.spring()) {
            showMusicLaunchMessage = true
        }
        
        // 2.5秒後にメッセージを非表示
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.spring()) {
                showMusicLaunchMessage = false
            }
        }
        
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
                
                // 最初のURLスキームを試したらループを抜ける
                // （複数同時に開くのを防ぐため）
                break
            }
        }
        
        // フォールバック: watch:// (ホーム画面)
        if let fallbackURL = URL(string: "watch://") {
            WKExtension.shared().openSystemURL(fallbackURL)
            print("🎵 Tried fallback: watch://")
        }
        
        print("💡 ワークアウトはバックグラウンドで継続します")
    }
}

#Preview {
    MusicControlView()
}
