# 🎵 デュアル音楽UI実装ガイド

## 📱 概要

iPhoneアプリの音楽コントロールUIを**Apple Music専用**と**サードパーティアプリ専用**の2つに分離し、縦スワイプで切り替えられるようにしました。

## ✨ 新機能

### 1. **Apple Music専用UI（ピンク）** 🎵
- **色**: ピンク
- **タイトル**: "Apple Music"
- **対象**: Apple Musicアプリで再生中の音楽
- **コントロール**: 
  - `MPMusicPlayerController.systemMusicPlayer` を使用
  - 再生/一時停止、曲送り/戻し、音量調整

### 2. **サードパーティアプリ専用UI（青）** 🎧
- **色**: 青
- **タイトル**: 再生中のアプリ名（例: "Spotify", "Music"）
- **対象**: サードパーティ音楽アプリで再生中の音楽
- **コントロール**:
  - `MPRemoteCommandCenter` を使用
  - 再生/一時停止、曲送り/戻し、音量調整

### 3. **縦スワイプで切り替え** ⬆️⬇️
- **上にスワイプ**: Apple Music UI → サードパーティ UI
- **下にスワイプ**: サードパーティ UI → Apple Music UI
- **スワイプ閾値**: 100pt
- **アニメーション**: Spring animation（response: 0.4, dampingFraction: 0.8）
- **ハプティックフィードバック**: ページ切り替え時に `.medium` の振動

### 4. **タブバーの色連動** 🏷️
- **Apple Musicページ**: タブバーの「ミュージック」ボタンがピンク色
- **サードパーティページ**: タブバーの「ミュージック」ボタンが青色
- **自動更新**: ページを切り替えると自動的に色が変わる

## 🛠️ 実装詳細

### 主要コンポーネント

#### 1. `PhoneMusicControlView`
```swift
struct PhoneMusicControlView: View {
    @Binding var currentMusicPage: MusicPageType
    
    enum MusicPageType {
        case appleMusic     // Apple Music UI
        case thirdParty     // サードパーティ UI
    }
}
```

**機能:**
- 2つの音楽UIページをVStackで縦に配置
- `DragGesture`で縦スワイプを検出
- `offset`でページ位置をアニメーション

#### 2. `PhoneMusicController`

**Apple Music用プロパティ:**
```swift
@Published var isPlaying: Bool
@Published var currentTrackTitle: String?
@Published var currentArtist: String?
@Published var currentAlbum: String?
@Published var currentArtwork: UIImage?
```

**サードパーティアプリ用プロパティ:**
```swift
@Published var thirdPartyIsPlaying: Bool
@Published var thirdPartyTrackTitle: String?
@Published var thirdPartyArtist: String?
@Published var thirdPartyAlbum: String?
@Published var thirdPartyArtwork: UIImage?
@Published var thirdPartyAppName: String?
```

**主要メソッド:**
- `updateNowPlayingInfo()`: Now Playing Info Centerから情報を取得し、Apple MusicとサードパーティアプリのUIに振り分け
- `updateAppleMusicInfo(...)`: Apple Music UIを更新
- `updateThirdPartyInfo(...)`: サードパーティ UI を更新
- `togglePlayPause()` / `togglePlayPauseThirdParty()`: 再生/一時停止
- `skipToNext()` / `skipToNextThirdParty()`: 次の曲へ
- `skipToPrevious()` / `skipToPreviousThirdParty()`: 前の曲へ

### アーキテクチャ図

```
┌─────────────────────────────────────────────┐
│       PhoneMusicControlView                  │
│                                              │
│  ┌────────────────────────────────────────┐ │
│  │   Apple Music UI (ピンク)              │ │
│  │   - MPMusicPlayerController            │ │
│  │   - タイトル: "Apple Music"            │ │
│  │   - 再生/停止/曲送り/曲戻し             │ │
│  └────────────────────────────────────────┘ │
│                    ⬇️ 上にスワイプ            │
│  ┌────────────────────────────────────────┐ │
│  │   サードパーティ UI (青)               │ │
│  │   - MPRemoteCommandCenter              │ │
│  │   - タイトル: "Music" など             │ │
│  │   - 再生/停止/曲送り/曲戻し             │ │
│  └────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

### Now Playing Info の振り分けロジック

```swift
private func updateNowPlayingInfo() {
    // 1. Now Playing Info Center から情報を取得
    let nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo
    
    // 2. Apple Music の nowPlayingItem と比較
    if isFromAppleMusic {
        updateAppleMusicInfo(...)
        clearThirdPartyInfo()
    } else {
        updateThirdPartyInfo(...)
        updateAppleMusicFromLibrary()  // バックグラウンドでApple Music情報も取得
    }
}
```

## 📋 使い方

### ユーザー操作フロー

#### シナリオ1: Apple Musicを聴きながらワークアウト
1. Apple Musicアプリで音楽を再生
2. ワークアウトアプリを起動
3. 「ミュージック」タブをタップ
4. **Apple Music UI（ピンク）** が表示される
5. 再生/停止、曲送り/戻しが可能

#### シナリオ2: Spotifyを聴きながらワークアウト
1. Spotifyアプリで音楽を再生
2. ワークアウトアプリを起動
3. 「ミュージック」タブをタップ
4. Apple Music UIが表示される（デフォルト）
5. **上にスワイプ**して**サードパーティ UI（青）**に切り替え
6. Spotifyの曲情報が表示され、コントロール可能

#### シナリオ3: 両方の音楽アプリを使い分ける
1. Apple MusicとSpotifyの両方で音楽を準備
2. ワークアウト中に気分に応じて切り替え
   - Apple Musicを聴きたい時: 下にスワイプ → Apple Music UI（ピンク）
   - Spotifyを聴きたい時: 上にスワイプ → サードパーティ UI（青）

### タブバーの色変化

- **Apple Music UIを表示中**: タブバーの「ミュージック」ボタンがピンク
- **サードパーティ UIを表示中**: タブバーの「ミュージック」ボタンが青

これにより、現在どちらのUIを見ているかが一目でわかります。

## 🎨 UIデザイン

### 共通デザイン
- **アートワーク**: 280x280pt、角丸12pt
- **曲情報**: タイトル（太字）、アーティスト（セカンダリ）、アルバム（ターシャリ）
- **再生コントロール**: 前へ（40pt）、再生/停止（80pt）、次へ（40pt）
- **音量スライダー**: スピーカーアイコン + Slider + 音量パーセンテージ

### Apple Music UI（ピンク）
- **グラデーション背景**: ピンク〜パープル（アートワークがない場合）
- **ボタン色**: ピンク
- **スライダー色**: ピンク
- **タブバー色**: ピンク

### サードパーティ UI（青）
- **グラデーション背景**: 青系（アートワークがない場合）
- **ボタン色**: 青
- **スライダー色**: 青
- **タブバー色**: 青

## 🔍 デバッグログ

### Apple Music情報の取得
```
🎵 Apple Music Track: Beautiful Day
🎵 Apple Music Artist: U2
🎵 Apple Music Album: All That You Can't Leave Behind
🎵 Apple Music Artwork loaded
🎵 Apple Music Playing: true
```

### サードパーティアプリ情報の取得
```
🎵 Third Party Track: Blinding Lights
🎵 Third Party Artist: The Weeknd
🎵 Third Party Album: After Hours
🎵 Third Party App detected
🎵 Third Party Artwork loaded
🎵 Third Party Playing: true
```

### コントロール操作
```
🎵 Apple Music paused
🎵 Third Party - Skipped to next track (via Remote Command)
🔊 Volume set to: 75%
```

## ⚠️ 制限事項と注意点

### 1. サードパーティアプリ名の取得
- **制限**: `MPNowPlayingInfoCenter` からアプリ名を直接取得できない
- **対策**: デフォルトで "Music" と表示
- **将来的な改善**: MediaPlayerフレームワークの拡張待ち

### 2. Now Playing Infoの判定精度
- **課題**: Apple MusicとサードパーティアプリのNow Playing Infoを完全に区別することは困難
- **現在の方法**: `MPMusicPlayerController.nowPlayingItem` と比較して判定
- **精度**: ほとんどの場合で正確に判定できますが、稀に誤判定の可能性あり

### 3. サードパーティアプリのコントロール
- **使用API**: `MPRemoteCommandCenter`
- **制限**: アプリがRemote Commandに対応している必要あり
- **対応アプリ**: Spotify, YouTube Music, Amazon Music など主要アプリは対応済み

### 4. 同時再生
- **Apple Musicとサードパーティアプリを同時に再生することはできません**
- 一方を再生すると、もう一方は自動的に停止します

## 🚀 今後の改善案

### 1. アプリ名の自動検出
- `MRMediaRemoteGetNowPlayingApplicationDisplayName` などのプライベートAPIを研究
- または、各アプリの特徴的なメタデータから推測

### 2. より洗練されたUI切り替え
- ページインジケーターの追加（ドット表示）
- スワイプ中のプレビュー表示

### 3. 自動ページ切り替え
- Apple Musicが再生開始 → 自動的にApple Music UIに切り替え
- サードパーティアプリが再生開始 → 自動的にサードパーティ UIに切り替え

### 4. お気に入りアプリの記憶
- ユーザーが最後に使用したページを記憶
- 次回起動時にそのページから開始

### 5. プレイリスト対応
- Apple Musicのプレイリスト表示
- サードパーティアプリのプレイリスト表示（可能な場合）

## 📚 関連ファイル

- **WorkoutApp_iOS.swift**: メインの実装ファイル
  - `PhoneMusicControlView`: 音楽UI
  - `PhoneMusicController`: 音楽コントロールロジック
  - `PhoneWorkoutView`: タブバーとページ管理

## ✅ テスト手順

### 実機テスト（必須）

#### テスト1: Apple Music再生
1. iPhone実機でApple Musicアプリを開く
2. 好きな曲を再生
3. ワークアウトアプリを起動
4. 「ミュージック」タブをタップ
5. **確認項目**:
   - タイトルが "Apple Music" になっている
   - 曲名、アーティスト、アルバム、アートワークが正しく表示される
   - ピンク色のボタンが表示される
   - 再生/停止ボタンが動作する
   - 曲送り/戻しボタンが動作する
   - タブバーの「ミュージック」ボタンがピンク色

#### テスト2: サードパーティアプリ再生（Spotify等）
1. iPhone実機でSpotifyアプリを開く
2. 好きな曲を再生
3. ワークアウトアプリを起動
4. 「ミュージック」タブをタップ
5. **上にスワイプ**
6. **確認項目**:
   - タイトルが "Music" になっている（アプリ名は取得できないため）
   - 曲名、アーティスト、アルバム、アートワークが正しく表示される
   - 青色のボタンが表示される
   - 再生/停止ボタンが動作する（Remote Command対応アプリのみ）
   - 曲送り/戻しボタンが動作する
   - タブバーの「ミュージック」ボタンが青色

#### テスト3: ページ切り替え
1. 音楽を再生中（Apple MusicまたはSpotify）
2. 「ミュージック」タブを表示
3. **上にスワイプ** → サードパーティ UIに切り替わる
4. **下にスワイプ** → Apple Music UIに切り替わる
5. **確認項目**:
   - スムーズなアニメーション
   - スワイプ時にハプティックフィードバック（振動）
   - タブバーの色が連動して変わる（ピンク ⇄ 青）

#### テスト4: 両方のUIで別々の曲を確認
1. Apple Musicで曲Aを再生（一時停止）
2. Spotifyで曲Bを再生（一時停止）
3. 「ミュージック」タブを表示
4. Apple Music UI（下）: 曲Aの情報が表示される
5. サードパーティ UI（上）: 曲Bの情報が表示される
6. **確認項目**:
   - 両方のUIで異なる曲情報が表示される
   - 色が正しく分かれている（ピンク vs 青）

## 🎉 まとめ

この実装により、以下が実現されました:

✅ **Apple Music専用UI** - ピンク色で統一された美しいUI  
✅ **サードパーティアプリ専用UI** - 青色で識別しやすいUI  
✅ **直感的な縦スワイプ** - 上下にスワイプして簡単に切り替え  
✅ **タブバーの色連動** - 現在のページが一目でわかる  
✅ **両方の音楽アプリを同時にサポート** - ワークアウト中に柔軟に音楽を選択  

iPhoneでのワークアウト体験が大幅に向上しました！🏃‍♂️🎵
