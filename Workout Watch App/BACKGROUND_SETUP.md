# バックグラウンド実行設定ガイド

このワークアウトアプリがバックグラウンドで動作するためには、Watch App の Info.plist に以下の設定を追加する必要があります。

## 必要な設定

### 1. Background Modes を追加

Info.plistに以下のキーを追加します：

```xml
<key>UIBackgroundModes</key>
<array>
    <string>workout-processing</string>
    <string>health</string>
</array>
```

### 2. Privacy - Health Share Usage Description

HealthKitのデータにアクセスするための説明文を追加します：

```xml
<key>NSHealthShareUsageDescription</key>
<string>ワークアウトの測定データ（心拍数、消費カロリー、距離など）を記録するためにHealthKitにアクセスします。</string>
```

### 3. Privacy - Health Update Usage Description

HealthKitにデータを書き込むための説明文を追加します：

```xml
<key>NSHealthUpdateUsageDescription</key>
<string>ワークアウトデータをHealthKitに保存して、フィットネスの記録を管理します。</string>
```

## Xcodeでの設定方法

### 方法1: Info.plistを直接編集

1. `Workout Watch App/Info.plist` ファイルを開く
2. 上記のXMLコードを追加

### 方法2: Xcodeの設定画面から（推奨）

1. プロジェクトナビゲーターで `Workout Watch App` ターゲットを選択
2. 「Signing & Capabilities」タブを開く
3. 「+ Capability」ボタンをクリック
4. 「Background Modes」を検索して追加
5. 以下のオプションにチェックを入れる：
   - ✅ **Audio, AirPlay, and Picture in Picture** （音楽再生用）
   - ✅ **Background fetch** （データ更新用）
   - ✅ **Remote notifications** （オプション）

6. 「Info」タブを開く
7. 「Custom iOS Target Properties」セクションで以下を追加：
   - `Privacy - Health Share Usage Description`
   - `Privacy - Health Update Usage Description`

## 動作確認

設定が正しく行われていれば、以下の動作が可能になります：

1. ✅ ワークアウト中にDigital Crownを押してホーム画面に戻れる
2. ✅ ホーム画面からミュージックアプリを起動できる
3. ✅ ミュージックアプリで音楽を再生しながら、ワークアウトがバックグラウンドで継続
4. ✅ アプリに戻ると、ワークアウトのデータが継続して記録されている

## ホーム画面に戻る方法

ユーザーがホーム画面に戻る方法は2つあります：

### 1. Digital Crownを押す（推奨）
- Digital Crownボタンを1回押すとホーム画面に戻る
- ワークアウトはバックグラウンドで継続

### 2. ミュージックコントロール画面の説明を参照
- アプリ内のミュージックコントロール画面に、Digital Crownの使い方が表示される
- 「Digital Crownを押すとホーム画面に戻ります」という案内が表示される

## トラブルシューティング

### ワークアウトがバックグラウンドで停止する場合

1. Info.plistの設定を確認
2. HealthKitの権限が正しく設定されているか確認
3. ワークアウトセッション（`HKWorkoutSession`）が適切に開始されているか確認
4. コンソールログで `🎵 App moved to background - workout continues` が表示されているか確認

### Digital Crownでの音量調整ができない場合

1. ミュージックコントロール画面が表示されているか確認
2. `.focusable()` モディファイアが適用されているか確認
3. `.digitalCrownRotation()` モディファイアが正しく設定されているか確認
4. 他のビューが焦点を奪っていないか確認

## 注意事項

- watchOSでは、アプリから直接的にホーム画面を開くAPIは提供されていません
- `WKExtension.shared().openSystemURL()` は一部のシステムURLでのみ動作します
- ユーザーにDigital Crownを使うよう案内することが推奨されます
- バックグラウンド実行には電力消費が伴うため、ワークアウトが不要になったら必ず終了してください
