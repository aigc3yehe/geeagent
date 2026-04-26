<p align="center">
  <img src="gee-nyko.png" alt="GeeAgent icon" width="112" style="border-radius: 24px;" />
</p>

<h1 align="center">GeeAgent</h1>

<p align="center"><strong>エージェントを際立たせる</strong></p>

<p align="center">
  <img alt="macOS 15+" src="https://img.shields.io/badge/macOS-15%2B-000000?logo=apple&logoColor=white" />
  <img alt="Swift 6.1" src="https://img.shields.io/badge/Swift-6.1-FA7343?logo=swift&logoColor=white" />
  <img alt="SwiftUI" src="https://img.shields.io/badge/SwiftUI-Native_UI-0A84FF?logo=swift&logoColor=white" />
  <img alt="AppKit" src="https://img.shields.io/badge/AppKit-macOS_Framework-1F6FEB" />
  <img alt="TypeScript Agent Runtime" src="https://img.shields.io/badge/TypeScript-Agent_Runtime-3178C6?logo=typescript&logoColor=white" />
  <img alt="MIT License" src="https://img.shields.io/badge/License-MIT-green.svg" />
</p>

<p align="center">
  <a href="README.md">English</a> | <a href="README.zh-CN.md">中文</a>
</p>

GeeAgent は、agent persona、ローカルアプリ支援、AI ビジュアル制作のための軽量な macOS AI ワークベンチです。

GeeAgent は、あらゆるワークフローを飲み込む巨大で重い万能 agent を目指していません。もっと小さく、手元に近い存在でありたいと考えています。日常タスク、ファイル、ローカルアプリ、創作計画、画像生成、動画生成、編集、公開を支えるネイティブなデスクトップコンパニオンです。

GeeAgent に込めている願いはシンプルです。Agent をそれぞれ違う存在にすること。固有の presence、memory、taste、そして人を助ける方法を持てるようにすることです。

## なぜ GeeAgent なのか

多くの agent ツールは、まだ空白のチャットボックスから始まります。GeeAgent は別の問いから始めます。もし agent が単なるプロンプト画面ではなく、継続する創作人格として感じられるなら、何が変わるのでしょうか。

GeeAgent は次の 3 つの考えを中心にしています。

- **Agent Persona**: agent には安定した identity、voice、visual presence、boundaries、tool posture が必要です。Persona は装飾ではありません。人が AI agent と信頼、記憶、美意識、協働関係を築くための層です。
- **Gear**: 便利な agent 機能を 1 つの巨大アプリに閉じ込めるべきではありません。Gears はオプションのローカルアプリ、ウィジェット、capability package であり、将来的には開かれたデスクトップアプリ市場へ育てられます。
- **Lightweight Focus**: GeeAgent はシンプルで、高速で、読みやすいべきです。日常のローカル作業を助けながら、画像、動画、クリップ、公開フロー、クリエイター運用といった AI ビジュアル制作に強く寄せています。

<p align="center">
  <img src="ui.png" alt="GeeAgent UI preview" />
</p>

## Agent Persona

GeeAgent は persona を第一級のプロダクトレイヤーとして扱います。Persona は、agent の話し方、関心、見え方、好む skill、使用できる tool を定義できます。

長期的には、persona を agent actor protocol と接続していきます。その未来では、persona は単なるローカルスキンやプロンプトファイルではありません。identity、capabilities、creative history、licensing rules、attribution、economic participation を含む、より深い actor record の人間に読める表面になります。デスクトップ agent は、その actor を体験し、演出し、信頼し、仕事に向かわせる場所になります。

これは創作 AI にとって特に重要です。AI characters、performers、assistants、collaborators が物語、動画、ツール、市場をまたいで現れるなら、必要なのは一度きりのプロンプトではありません。継続性です。

## Gear: 開かれたアプリ市場

GeeAgent の Gear system は、開かれたローカルアプリ市場へ向かうための道筋です。

Gear は、ネイティブアプリ、Home widget、ローカルツール画面、capability package になれます。Gears は常にオプションであるべきです。Gear が存在しない、無効、壊れている、未インストールである場合でも、メインワークベンチを壊してはいけません。

目標は実用的で、クリエイターにやさしいことです。

- コアアプリを重くせず、小さなローカルツールをインストールまたはコピーできる
- アプリ固有のロジックを Gear 境界の内側に保つ
- 宣言された capability だけを agent に公開する
- メディア、自動化、公開、ローカルワークフローのための focused tool を第三者が作れる道を残す

GeeAgent は、プラグイン迷宮ではなく、小さな制作スタジオの作業台のように感じられるべきです。

## ビジュアルクリエイターのために

GeeAgent は 2 つの強いユースケースを中心に形作られています。

第一に、ローカルアプリ支援です。ファイル、コマンド、タスク状態、承認、設定、そして agent が流れを見られることで進めやすくなる小さなデスクトップ作業を助けます。

第二に、AI ビジュアル制作に最適化されています。プロダクトの方向性として、次の領域を特に重視します。

- 画像生成とプロンプト反復
- 動画生成とショット設計
- クリップ選定、編集、パッケージング
- ショートフィルム、ソーシャル動画、ビジュアルアセットの公開フロー
- スタイル、美意識、役割の一貫性を保てる persona-driven creative agents

GeeAgent は有能であるべきですが、重くある必要はありません。最良の姿は、AI で作品を作る人のためのコンパクトな creative cockpit です。

## For Builders

GeeAgent はまだ若いプロジェクトです。だからこそ面白い。まだ地面に近く、これから参加する人も、その言葉づかい、習慣、拡張文化に影響を与えられます。

Codebase には 2 つの中心があります。Native macOS workbench と TypeScript runtime です。その周囲で、persona と Gear が大きな入口になります。Persona は agent に continuity と presence を与え、Gear は creators に小さく集中した tools を届けます。

よい contribution は、必ずしも大きい必要はありません。ひとつの workflow をわかりやすくする、ひとつの creative tool に手が届きやすくする、ひとつの persona を理解しやすくする、ひとつの local task を agent に安全に任せられるようにする。それだけでも GeeAgent は前に進みます。

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

特に次の領域でのコントリビューションを歓迎します。

- persona package、visual presence、creative agent design
- ローカルツール、メディアワークフロー、creator utility のための Gear development
- ネイティブ macOS interaction、accessibility、desktop polish
- runtime reliability、task continuation、approvals、observable execution

PR はできるだけ focused に保ち、local secrets、cache、machine-specific files はコミットしないでください。

## ライセンス

MIT

## Public Docs

Public docs は、この README より少し深い場所にあります。ただし、実装メモを積み上げるためではありません。GeeAgent が育っていく中で、失いたくない考え方を残すための場所です。

[Public Docs](https://aigc3yehe.github.io/geeagent/) | [Agent Persona](https://aigc3yehe.github.io/geeagent/?doc=docs/ja/agent-persona.md) | [Gear Development](https://aigc3yehe.github.io/geeagent/?doc=docs/ja/gear-development.md) | [Gee Basic Development](https://aigc3yehe.github.io/geeagent/?doc=docs/ja/gee-basic-development.md)
