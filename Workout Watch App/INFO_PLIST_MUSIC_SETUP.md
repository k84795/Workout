# Info.plist 音楽機能設定手順

iPhoneアプリで音楽機能を使用するには、Info.plistに以下の設定が必要です。

## 必要な設定

### 1. 音楽ライブラリへのアクセス許可

`Info.plist`に以下のキーを追加してください：

```xml
<key>NSAppleMusicUsageDescription</key>
<string>ワークアウト中に音楽を再生・コントロールするために、音楽ライブラリへのアクセスが必要です。</string>
```

### 2. Xcodeでの設定方法

1. **プロジェクトナビゲーター**で`Workout (iOS)`ターゲットを選択
2. **Info**タブを開く
3. **Custom iOS Target Properties**セクションで右クリック→**Add Row**
4. キーとして`Privacy - Media Library Usage Description`を選択
5. 値として`ワークアウト中に音楽を再生・コントロールするために、音楽ライブラリへのアクセスが必要です。`を入力

または、Info.plistファイルを直接編集：

1. プロジェクトナビゲーターで`Info.plist`ファイルを探す
2. 右クリック→**Open As**→**Source Code**
3. 上記のXMLコードを`<dict>`タグ内に追加

## 実機での確認手順

1. アプリをビルドして実機にインストール
2. アプリを起動してワークアウトを開始
3. ミュージックタブに移動
4. 初回は**音楽ライブラリへのアクセス許可**ダイアログが表示される
5. **許可**を選択

### 許可を間違えて拒否した場合

1. iPhoneの**設定**アプリを開く
2. 下にスクロールして**Workout**アプリを探す
3. **メディアとApple Music**をタップ
4. **許可**に変更

## トラブルシューティング

### 音楽が表示されない場合

1. iPhoneのミュージックアプリで何か曲を再生してみる
2. 当アプリのミュージックタブに戻る
3. それでも表示されない場合は、アプリを完全に終了して再起動

### 音量スライダーが動かない場合

- iPhoneの音量ボタンを押してみる
- システム音量スライダー（MPVolumeView）が正しく表示されているか確認
- アプリを再起動

### ミュージックアプリと共存できない場合

- AVAudioSessionが`.ambient`カテゴリーで設定されているか確認
- コンソールログで`🔊 AVAudioSession configured: .ambient with .mixWithOthers`が表示されているか確認

## 主な変更内容

### 1. 音楽ライブラリアクセスの要求

```swift
func requestMusicLibraryAccess(completion: @escaping (Bool) -> Void) {
    MPMediaLibrary.requestAuthorization { status in
        DispatchQueue.main.async {
            completion(status == .authorized)
        }
    }
}
```

### 2. システム音量スライダーの実装

```swift
struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let volumeView = MPVolumeView(frame: .zero)
        volumeView.showsRouteButton = false
        return volumeView
    }
}
```

### 3. AVAudioSessionの設定

```swift
try audioSession.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
```

これで音楽機能が正常に動作するはずです！
