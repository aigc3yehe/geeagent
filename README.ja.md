# GeeAgent

[English](README.md) | [中文](README.zh-CN.md)

![macOS](https://img.shields.io/badge/macOS-15%2B-000000?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-6.1-FA7343?logo=swift&logoColor=white)
![SwiftUI](https://img.shields.io/badge/SwiftUI-Native_UI-0A84FF?logo=swift&logoColor=white)
![AppKit](https://img.shields.io/badge/AppKit-macOS_Framework-1F6FEB)
![Rust](https://img.shields.io/badge/Rust-Workspace-000000?logo=rust&logoColor=white)
![Cargo](https://img.shields.io/badge/Cargo-Build_System-8C4A2F?logo=rust&logoColor=white)
![Tauri](https://img.shields.io/badge/Tauri-v2-24C8DB?logo=tauri&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green.svg)

GeeAgent は、コンパニオン型インタラクション、可視化されたタスク実行、そしてモジュール化されたランタイムオーケストレーションを中心に設計された macOS 向け AI ワークベンチです。

本プロジェクトは、ネイティブ macOS シェルと Rust ベースのランタイム層を組み合わせることで、対話、ルーティング、承認フロー、タスク状態、モジュール実行を継続的に観測しやすく、拡張しやすい形で維持することを目指しています。

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
- `Rust` と `Cargo`：ランタイムロジック、実行契約、ルーティング、ワークスペース状態
- `Tauri v2`：シェルとランタイムを接続するブリッジ要素
- `TOML`：ルーティングとモジュール設定

## アーキテクチャ

GeeAgent は大きく次の 3 層で構成されています。

1. コンパニオン、ワークベンチ、メニューバーなどを担うネイティブ macOS シェル
2. ルーティング、実行契約、ワークスペース状態、モジュール分配、タスク進行を担う Rust ランタイム層
3. ファーストパーティ機能と外部サービスを接続するモジュール化された統合境界

代表的なランタイム crate：

- `agent-kernel`：agent pack の検証と読み込み
- `automation-engine`：自動化ポリシーとスケジューリング
- `execution-runtime`：プロンプト実行と自動化ドラフト
- `model-router`：モデルおよび provider のルーティング
- `module-gateway`：モジュールマニフェストと実行契約
- `runtime-kernel`：ファーストパーティツール呼び出しルール
- `task-engine`：タスク段階とライフサイクル
- `workspace-runtime`：ワークベンチスナップショット契約

主要パス：

- `apps/macos-bridge`：ネイティブ macOS シェル
- `apps/desktop-shell/src-tauri`：Rust bridge / runtime 統合層
- `crates/*`：コアランタイム crate
- `config/*`：ルーティングとモジュール設定
- `examples/agent-packs/*`：サンプル agent pack

## Getting Started

### 前提条件

- macOS 15+
- Swift 6.1 をサポートする Xcode
- Rust toolchain
- Cargo

### ネイティブアプリをビルドする

```bash
swift build --package-path apps/macos-bridge
```

### ワークベンチシェルをビルドして起動する

```bash
bash apps/macos-bridge/script/build_and_run.sh
```

このコマンドは、ネイティブ macOS アプリと、シェルが利用する Rust runtime bridge を一緒にビルドします。

### Rust ワークスペースのテストを実行する

```bash
cargo test
```

## コントリビュート

コントリビューションは歓迎します。リポジトリを読みやすく保つため、次の方針を推奨します。

- 目的が明確で範囲の絞られた PR を優先する
- マシン固有ファイル、秘密情報、キャッシュ、ローカル計画資料はコミットしない
- ルーティング、タスクライフサイクル、ワークベンチスナップショット、モジュール境界に影響する変更は PR で明記する
- crate レベルのランタイム挙動を変える場合は、可能な限りテストを追加する

ランタイム面を拡張する場合は、どの crate が契約を定義し、どの UI がそれを利用するのかを書いてもらえると助かります。

## ライセンス

MIT
