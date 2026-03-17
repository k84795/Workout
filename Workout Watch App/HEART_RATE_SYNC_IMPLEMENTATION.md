# iPhone心拍数連携機能の実装

## 概要
iPhoneアプリで表示される平均心拍数を、連携しているApple Watchから取得するように修正しました。

## 変更内容

### 1. 新規ファイルの追加

#### `PhoneWorkoutConnectivityManager.swift` (iOS専用)
- Watch Connectivityを使用してApple Watchからワークアウトデータを受信
- 心拍数データを`WorkoutManager`に転送
- `PhoneMusicConnectivityManager`と同様の構造

#### `WatchWorkoutConnectivityManager.swift` (watchOS専用)
- Apple WatchからiPhoneにワークアウトデータを送信
- 心拍数を含む複数のメトリクスをサポート
- `sendHeartRateToPhone(_:)` メソッドで心拍数を送信

### 2. 既存ファイルの修正

#### `WorkoutManager.swift`
- **Import追加**: iOS用に`WatchConnectivity`をインポート
- **新規メソッド**: `updateHeartRateFromWatch(_:)` 
  - iPhoneでWatchから受信した心拍数を処理
  - 心拍数履歴を更新し、平均値を計算
  - iOS専用（`#if os(iOS)`）
- **心拍数送信**: watchOS側で心拍数更新時にiPhoneに送信
  - `updateForStatistics(_:)` 内の心拍数処理に送信コード追加
  - watchOS専用（`#if os(watchOS)`）

#### `WorkoutApp_iOS.swift`
- **初期化処理追加**: `onAppear`内で以下を追加
  - `PhoneWorkoutConnectivityManager`の初期化
  - `WorkoutManager`への参照設定
  - Watch Connectivityセッションの有効化

## 動作フロー

### Apple Watch → iPhone の心拍数送信
1. **Apple Watch**: HealthKitから心拍数を取得
2. **Apple Watch**: `WatchWorkoutConnectivityManager.sendHeartRateToPhone(_:)` を呼び出し
3. **Watch Connectivity**: iPhoneにメッセージ送信
4. **iPhone**: `PhoneWorkoutConnectivityManager` がメッセージ受信
5. **iPhone**: `WorkoutManager.updateHeartRateFromWatch(_:)` を呼び出し
6. **iPhone**: 心拍数履歴を更新し、平均値を計算してUIに反映

## プラットフォーム固有の処理

### watchOS（Apple Watch）
- HealthKitから直接心拍数を測定
- 測定した心拍数をiPhoneに送信
- 自身のUIにも表示

### iOS（iPhone）
- Apple Watchからの心拍数データのみを使用
- HealthKitセッションは距離・カロリー・歩数のみ記録
- Watch Connectivityで受信した心拍数を表示

## メッセージフォーマット

### Watchからの送信
```swift
[
    "workoutData": true,
    "heartRate": Double  // bpm単位
]
```

### iPhoneでの受信処理
- `workoutData`フラグでワークアウトデータと判定
- `heartRate`キーから心拍数値を取得
- `WorkoutManager.updateHeartRateFromWatch(_:)` に渡す

## 注意事項

1. **Watch Connectivityの前提条件**
   - iPhoneとApple Watchが接続されている必要がある
   - `WCSession.isReachable` が `true` の場合のみ送信

2. **心拍数の有効範囲**
   - 40〜220 bpm の範囲のみ有効
   - 範囲外の値は無視される

3. **一時停止時の動作**
   - 一時停止中も心拍数履歴は内部的に更新
   - UI表示は一時停止時の値で凍結

4. **履歴の管理**
   - 最大30個の心拍数サンプルを保持
   - 古いサンプルは自動的に削除

## テスト方法

1. Apple WatchとiPhoneの両方でアプリを起動
2. Apple Watchでワークアウトを開始
3. iPhoneアプリを開いて平均心拍数が表示されることを確認
4. Apple Watchの心拍数が変化すると、iPhoneの表示も更新されることを確認

## ログ出力

- **Watch送信時**: `📱💓 Heart rate sent to iPhone: XXX bpm`
- **iPhone受信時**: `⌚️💓 Heart rate received from Watch: XXX bpm`
- **平均値更新時**: `⌚️💓 Average heart rate updated: XXX bpm (samples: XX)`
