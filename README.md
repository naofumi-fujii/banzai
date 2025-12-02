# banzai

macOS メニューバー常駐型のクリップボード履歴監視ツール

## 機能

- クリップボードの変更を自動検知・保存
- メニューバーに常駐してバックグラウンド動作
- 履歴をJSONL形式で永続化

## インストール

```bash
cargo build --release
```

## 使い方

```bash
cargo run
```

起動するとメニューバーにクリップボードアイコンが表示されます。
コピーした内容は自動的に保存されます。

## 履歴の保存場所

- macOS: `~/Library/Application Support/banzai/clipboard_history.jsonl`

## 依存クレート

- `arboard` - クリップボードアクセス
- `chrono` - タイムスタンプ
- `serde` / `serde_json` - シリアライズ
- `dirs` - プラットフォーム固有のディレクトリ取得
- `tao` / `tray-icon` - システムトレイ