# Apple Music 連携機能の実装ガイド

## 📱 実装完了

Watch ConnectivityフレームワークでiPhoneとApple Watchを連携し、Apple Musicをコントロールできるようになりました。

## 🔧 実装ファイル

### Watch側
- **MusicControlView.swift** - UI と Watch側のコントローラー
  - `WatchMusicController` - 音楽コントロールのロジック
  - `WatchConnectivityManager` - iPhoneとの通信管理

### iPhone側
- **PhoneMusicConnectivityManager.swift** - iPhone側の通信管理とMPMusicPlayerController
- **WorkoutApp.swift** - iPhoneアプリのエントリーポイント

## 🎵 機能

### 1. 再生情報の表示
- 曲名
- アーティスト名
- アルバム名
- 再生/一時停止状態

### 2. 再生コントロール
- ▶️ 再生/⏸️ 一時停止
- ⏭️ 次の曲
- ⏮️ 前の曲

### 3. 音量コントロール
- Digital Crownで調整
- ボタンで±5%調整
- パーセンテージ表示

## 📋 セットアップ手順

### 1. プロジェクト設定

#### iPhone アプリターゲット
1. **Capabilities** タブを開く
2. **Background Modes** を有効化
3. ✅ `Remote notifications` をチェック（オプション）
4. **Info.plist** に追加:
```xml
<key>NSAppleMusicUsageDescription</key>
<string>ワークアウト中に音楽を制御するために使用します</string>
```

#### Watch アプリターゲット
1. **Capabilities** タブを開く
2. **Background Modes** を有効化（必要に応じて）

### 2. ファイルの配置

#### iPhoneアプリターゲットに追加:
- `WorkoutApp.swift`
- `PhoneMusicConnectivityManager.swift`

#### Watchアプリターゲットに追加:
- `MusicControlView.swift`

### 3. ビルド設定

両方のターゲットで以下のフレームワークがリンクされていることを確認:
- `MediaPlayer.framework`
- `WatchConnectivity.framework`

## 🚀 使い方

### 初回起動時
1. iPhoneアプリを起動（バックグラウンドでOK）
2. Apple Watchでワークアウトアプリを起動
3. 音楽コントロール画面に移動

### Apple Musicで音楽を再生
1. iPhoneまたはApple WatchでApple Musicアプリを開く
2. 好きな曲を再生
3. ワークアウトアプリの音楽コントロール画面に自動で表示

### コントロール
- **再生ボタン** - タップで再生/一時停止
- **⏭️/⏮️ボタン** - 曲送り/曲戻し
- **Digital Crown** - 回して音量調整
- **±ボタン** - タップで音量を5%ずつ調整

## 🔍 トラブルシューティング

### 曲情報が表示されない
1. iPhoneアプリが起動していることを確認
2. Apple WatchとiPhoneがBluetooth接続されていることを確認
3. Apple Musicアプリで音楽が再生されていることを確認

### ボタンが反応しない
1. iPhoneアプリのコンソールログを確認
2. `🎵` アイコン付きのログで通信状態を確認
3. WatchアプリとiPhoneアプリを両方とも再起動

### デバッグログ
コンソールで以下のログを確認:
```
🎵 WCSession activated
🎵 Now Playing: (曲名)
🎵 Play/Pause command sent
🎵 Received music info from iPhone
```

## ⚠️ 制限事項

1. **iPhoneが必要** - WatchアプリだけではApple Musicを制御できません
2. **接続範囲** - Bluetooth範囲内（約10m）で動作
3. **バッテリー** - 常時通信するためバッテリー消費が増加
4. **音量制御** - システム制限により完全な音量制御はできない場合があります

## 🎯 最適化のヒント

### バッテリー節約
- 音楽情報のポーリング間隔を調整（現在2秒）
```swift
// MusicControlView.swift の startMonitoring() 内
timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) // 2.0 → 3.0
```

### 応答性の向上
- iPhoneアプリをフォアグラウンドで起動しておく
- 両デバイスを近くに置く

## 📝 今後の拡張案

1. **再生時間の表示** - プログレスバーとタイムスタンプ
2. **アルバムアートワーク** - 画像の転送と表示
3. **プレイリスト選択** - iPhoneから選択して再生
4. **お気に入り登録** - ハートボタンで曲をお気に入りに追加
5. **歌詞表示** - スクロール歌詞の表示

## 💡 参考

- [Apple Developer - Watch Connectivity](https://developer.apple.com/documentation/watchconnectivity)
- [Apple Developer - MediaPlayer Framework](https://developer.apple.com/documentation/mediaplayer)
- [Apple Developer - MPMusicPlayerController](https://developer.apple.com/documentation/mediaplayer/mpmusicplayercontroller)
