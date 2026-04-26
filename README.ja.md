# GeeAgent

[English](README.md) | [中文](README.zh-CN.md)

![macOS](https://img.shields.io/badge/macOS-15%2B-000000?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-6.1-FA7343?logo=swift&logoColor=white)
![SwiftUI](https://img.shields.io/badge/SwiftUI-Native_UI-0A84FF?logo=swift&logoColor=white)
![AppKit](https://img.shields.io/badge/AppKit-macOS_Framework-1F6FEB)
![TypeScript](https://img.shields.io/badge/TypeScript-Agent_Runtime-3178C6?logo=typescript&logoColor=white)
![Node.js](https://img.shields.io/badge/Node.js-SDK_Sidecar-339933?logo=node.js&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green.svg)

GeeAgent は、コンパニオン型インタラクション、可視化されたタスク実行、そしてモジュール化されたランタイムオーケストレーションを中心に設計された macOS 向け AI ワークベンチです。

本プロジェクトは、ネイティブ macOS アプリと TypeScript agent runtime を組み合わせることで、対話、ルーティング、承認フロー、タスク状態、モジュール実行を継続的に観測しやすく、拡張しやすい形で維持することを目指しています。

## 目的

多くの AI 製品は、依然としてチャットボックスや CLI を主要な入口にしています。GeeAgent はそれとは異なる操作モデルを探求しています。

- ブラウザタブではなく、呼び出し可能なデスクトップネイティブアシスタント
- タスク状態、承認、実行進行を可視化するワークベンチ
- 単一のブラックボックス的 agent loop ではなく、モジュール化された実行経路
- ユーザー固有の状態やワークフローに適した local-first 設定
- 拡張、デバッグ、コントリビュートがしやすいオープンな設計

## 技術スタック

GeeAgent は現在、主に以下のコンポーネントで構成されています。

- `SwiftUI` と `AppKit`：ネイティブ macOS シェルと UI
- `Swift Package Manager`：macOS アプリのパッケージ管理
- `TypeScript` と `Node.js`：GeeAgent runtime と Agent SDK session loop
- `TOML`：ルーティングとモジュール設定

## アーキテクチャ

GeeAgent は大きく次の 4 層で構成されています。

1. コンパニオン、ワークベンチ、メニューバーなどを担うネイティブ macOS シェル
2. ルーティング、実行契約、ワークスペース状態、承認、会話、タスク進行を担う TypeScript runtime
3. TypeScript runtime 内で実際の agent loop を担う Agent SDK session layer
4. ファーストパーティ機能と外部サービスを接続するモジュール化された統合境界

代表的な runtime モジュール：

- `apps/agent-runtime/src/native-runtime`：永続化状態、スナップショット、ツール、turn、承認、コマンド分配
- `apps/agent-runtime/src/session.ts`：Agent SDK session wrapper と permission callback
- `apps/agent-runtime/src/gateway.ts`：現在のモデルルート向け Anthropic-compatible gateway
- `apps/agent-runtime/src/chat-runtime.ts`：チャットルーティング設定と provider readiness

主要パス：

- `apps/macos-app`：ネイティブ macOS アプリ
- `apps/agent-runtime`：TypeScript GeeAgent runtime と Agent SDK integration
- `config/*`：ルーティングとモジュール設定
- `examples/agent-packs/*`：サンプル agent pack

## Getting Started

### 前提条件

- macOS 15+
- Swift 6.1 をサポートする Xcode
- Node.js と npm

### ネイティブアプリをビルドする

```bash
swift build --package-path apps/macos-app --scratch-path apps/macos-app/.swift-build
```

### ネイティブワークベンチアプリをビルドして起動する

```bash
bash apps/macos-app/script/build_and_run.sh
```

このコマンドは TypeScript runtime をビルドし、ネイティブ macOS アプリを起動します。

### ランタイムテストを実行する

```bash
npm run test --prefix apps/agent-runtime
swift test --package-path apps/macos-app --scratch-path apps/macos-app/.swift-build
```

## コントリビュート

コントリビューションは歓迎します。リポジトリを読みやすく保つため、次の方針を推奨します。

- 目的が明確で範囲の絞られた PR を優先する
- マシン固有ファイル、秘密情報、キャッシュ、ローカル計画資料はコミットしない
- ルーティング、タスクライフサイクル、ワークベンチスナップショット、モジュール境界に影響する変更は PR で明記する
- runtime 挙動を変える場合は、可能な限りテストを追加する

ランタイム面を拡張する場合は、どの TypeScript モジュールが契約を定義し、どの UI がそれを利用するのかを書いてもらえると助かります。

## ライセンス

MIT
