# Gee 基礎開発

## 状態

プレースホルダー項目です。

このセクションでは GeeAgent の基本開発 workflow、project structure、build setup、runtime startup、verification、一般的な contribution rules を記録します。

## 現在のルール

system behavior が変わる場合、English、Simplified Chinese、Japanese の関連する公開 docs を同期して更新します。

Gear または capability behavior が変わる場合、Codex plugin projection、Gee MCP export schema、generated skills、plugin metadata も更新が必要か確認します。Substantial Gear change に Codex export update が不要な場合は、work summary でそれを明示します。

## Runtime Context Spine

GeeAgent の runtime context spine は、product behavior を維持しながら repeated prompt history を減らすための現在の方向性です。GeeAgent は完全な conversation transcript と runtime events をローカルの truth として保持します。目標の model-facing path は active SDK session lineage を優先し、context projection は old sessions、lost SDK lineage、cross-engine handoff、budget telemetry のために残します。

現在の first slice では、live SDK session ごとに runtime bootstrap instructions を一度だけ注入し、same-run continuation が完全な GeeAgent runtime prompt を繰り返さないようにしています。後続の slice では通常の multi-turn workspace continuation を persisted SDK lineage に移し、大きな tool results は summary または local artifact reference として扱い、完全な output は GeeAgent history に残します。

## Phase 3 Runtime Workbench

GeeAgent の現在の runtime mainline は Phase 3 Runtime Workbench です。現在の方向性は、conversation、task、tool、approval、Gear、artifact、context-budget の各 surface を、単一の append-only runtime event truth の projection として扱うことです。

Assistant text は、最終完了後にだけ表示されるのではなく、transcript event の live delta として frontend に流れ始めます。Tool と Gear completion の失敗は、実際の failed または degraded run state を保持する必要があります。GeeAgent は別の execution path に切り替えたり、未完了の runtime continuation を completed に見せたりしてはいけません。

Gear work では live SDK run と Gee MCP bridge が必須 path です。SDK runtime または bridge が live でない場合、GeeAgent は alternate native route で task を実行せず、structured failure を報告します。

Host-action completion は、同じ SDK run がまだ生きている場合はその run に戻ります。run が失われている場合、GeeAgent は structured Gear result を記録し、その turn を failed または degraded として扱います。隠れた separate completion turn は開始しません。

Gear invocation arguments は、native host が Gear を実行する前に TypeScript runtime boundary で normalize と validate されます。Focused runtime plan は matching capability に deterministic stage arguments を提供できます。Missing or conflicting required fields still return structured tool errors so the active agent run can correct the call。

Gear-first runtime plan can also include model-only stages, such as current web research or final synthesis after all Gear storage work is done。Active stage に Gear focus も required Gear capability もない場合、GeeAgent は同じ run の中で normal approved SDK tool policy に戻り、それらの SDK tool results を fallback path ではなく stage evidence として記録します。Final-result validation は active plan stage に従うため、同じ run で先行する Gear stages が完了していれば、research または synthesis continuation は、その segment で追加の Gear call がないことだけでは reject されません。

Local SDK gateway は、provider に転送する前に `chat-runtime.toml` の chat output budget と temperature を適用します。Upstream provider または model が unavailable または timeout した場合、GeeAgent は別の provider や model を retry せず、その failure を直接報告します。
