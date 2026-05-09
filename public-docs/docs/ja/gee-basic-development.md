# Gee 基礎開発

## 状態

プレースホルダー項目です。

このセクションでは GeeAgent の基本開発 workflow、project structure、build setup、runtime startup、verification、一般的な contribution rules を記録します。

## 現在のルール

system behavior が変わる場合、English、Simplified Chinese、Japanese の関連する公開 docs を同期して更新します。

Gear または capability behavior が変わる場合、Codex plugin projection、Gee MCP export schema、generated skills、generated capability reference files、plugin metadata も更新が必要か確認します。Substantial Gear change に Codex export update が不要な場合は、work summary でそれを明示します。

## Runtime Context Spine

GeeAgent の runtime context spine は、product behavior を維持しながら repeated prompt history を減らすための現在の方向性です。GeeAgent は完全な conversation transcript と runtime events をローカルの truth として保持します。目標の model-facing path は active SDK session lineage を優先し、context projection は old sessions、lost SDK lineage、cross-engine handoff、budget telemetry のために残します。

現在の first slice では、live SDK session ごとに runtime bootstrap instructions を一度だけ注入し、same-run continuation が完全な GeeAgent runtime prompt を繰り返さないようにしています。後続の slice では通常の multi-turn workspace continuation を persisted SDK lineage に移し、大きな tool results は summary または local artifact reference として扱い、完全な output は GeeAgent history に残します。

## Runtime Foundation

GeeAgent の runtime foundation は Phase 3 Runtime Workbench から来ており、現在は Phase 4 product deepening の中で carry forward されます。現在の方向性は、conversation、task、tool、approval、Gear、artifact、context-budget の各 surface を、単一の append-only runtime event truth の projection として扱うことです。

Phase 3 は complete として mark しません。GeeAgent には、stable run identity、same-run continuation、typed transcript events、strict Gear evidence、bounded artifact/context handling、replay projection、run-state classification、golden replay tests と macOS projection tests で covered された minimum inspector projection を含む、validated runtime-trust slice があります。この foundation は Phase 4 の product use の中で継続的に refinement されます。

## Phase 4 Product Deepening

Phase 4 は広い product-deepening stage です。GeeAgent は実際の利用を通じて、agent system と Gear modules の両方を含む system 全体を改善し、豊かにしていきます。この stage の work は、narrow runtime-only checklist ではなく、dogfood evidence、user workflows、reliability gaps、product opportunities によって進めます。

Assistant text は、最終完了後にだけ表示されるのではなく、transcript event の live delta として frontend に流れ始めます。Tool と Gear completion の失敗は、実際の failed または degraded run state を保持する必要があります。GeeAgent は別の execution path に切り替えたり、未完了の runtime continuation を completed に見せたりしてはいけません。

Workspace chat は、local image、file、folder references を structured input attachments として submit できるようになりました。Full Chat surface と Home focused chat composer は file/folder picker、window-level local file URL drag-and-drop、pasted image を local PNG reference として staging する flow に対応し、compact thumbnail も表示します。送信後、transcript は user message 上に compact attachment chips を保持し、kind、status、利用可能な size、local path inspection を表示します。Chat inspector も attachment provenance、resolved path、access scope、image dimensions、limits、errors、`fallback_attempted` を表示します。Runtime はそれらの attachments を user message と transcript event に記録し、`fallback_attempted: false` を保持し、attachment manifest を active run に公開し、scoped-root と byte-limit の検証後に ready な PNG/JPEG/GIF/WebP images を SDK image content blocks として送信し、local gateway では OpenAI-compatible image parts として保持します。folder references は同じ run 内の bounded directory snapshot/listing tool で inspection し、local paths や media を plain chat text に詰め込む形にはしません。Replay projection は user message の attachment ids/statuses を保持し、directory snapshot evidence を通常の tool invocation/result rows として表示します。Screenshot-vs-folder tasks では、agent が image を読み、referenced folder を list し、構造を自分で比較します。専用の screenshot comparison tool はありません。通常の image understanding と image text extraction は model vision context を first に使います。通常の image-only turn は no-tool chat profile を使うため、user が tool-based verification を求める場合、または image を local file/folder context と組み合わせる場合を除き、OCR、filesystem reads、metadata probes は利用できません。Image failure の後の短い retry turn は、まだ成功処理されていない直近の ready image attachment を active run に保持します。Configured backend model が vision-capable でない場合、gateway は upstream に contact する前に `model_unsupported_multimodal` を返し、images を drop したり OCR fallback を試したりしません。

Settings は audio transcription 用の default STT service を 1 つ公開します。Chat voice input と Audio Capture shortcut bar は同じ保存済み provider を使います。現在の選択肢は Local Whisper、Local SenseVoice、ElevenLabs です。Local backend が欠けている場合は、別 provider に fallback せず明示的に失敗します。Audio Capture bar は menu-bar panel から開けるほか、Control+Option+A / Shift+Command+A でも開けます。Microphone と system-audio permission failure は macOS の current authorization state、bundle id、running app path を表示します。Permission request は bar を Starting のままにせず timeout し、stale TCC entry も直接示します。

Gear work では live SDK run と Gee MCP bridge が必須 path です。SDK runtime または bridge が live でない場合、GeeAgent は alternate native route で task を実行せず、structured failure を報告します。

Host-action completion は、同じ SDK run がまだ生きている場合はその run に戻ります。run が失われている場合、GeeAgent は structured Gear result を記録し、その turn を failed または degraded として扱います。隠れた separate completion turn は開始しません。

Gear invocation arguments は、native host が Gear を実行する前に TypeScript runtime boundary で normalize と validate されます。Focused runtime plan は matching capability に deterministic stage arguments を提供できます。Missing or conflicting required fields still return structured tool errors so the active agent run can correct the call。

Gear-first runtime plan can also include model-only stages, such as current web research or final synthesis after all Gear storage work is done。Active stage に Gear focus も required Gear capability もない場合、GeeAgent は同じ run の中で normal approved SDK tool policy に戻り、それらの SDK tool results を fallback path ではなく stage evidence として記録します。Final-result validation は active plan stage に従うため、同じ run で先行する Gear stages が完了していれば、research または synthesis continuation は、その segment で追加の Gear call がないことだけでは reject されません。

現在の runtime planning behavior は引き続き adaptive です。Ordinary turn は direct runtime path を使い、light Gear-first turn は full deterministic stage plan を作らずに Gear bridge を使います。Multi-stage または cross-domain Gear request だけが structured planning に入ります。Direct と light turn は historical stage capsules を model-facing prompt に注入しません。詳細な runtime events は transcript、Worked trace、inspector、replay surfaces に残り、model に自動的に戻されません。Conversation preview と final-answer surface は `Stage complete` のような stage-progress prose を抑制します。その evidence は Worked と inspector views に残します。New turn は transcript event、host action、approval、stage capsule にまたがる stable `run_id` も受け取り、product projection と replay tooling が prompt context を増やさずに同じ work を group できるようにします。Developer replay commands は run export、artifact membership 付きの deterministic projection row reconstruction、malformed event order diagnostics、completed/host/tool/approval/session-lost/event-silence state classification を提供します。

Attachments がない greetings、thanks、small talk などの plain conversational turns は、shell、file、Gear bridge、auto-approved tools を持たない chat-only SDK profile を使います。Attachments を含む turn、または local inspection、file work、Gear work、その他の action を明示的に依頼する turn は、通常の runtime tool policy を使います。Chat request-error banner は active chat send に scope されます。Background Gear または host-action failures は、それぞれの surface または global state に残り、無関係な chat message の failure として表示されません。User-facing run failures は product-level wording を使います。Model API が agent の reply 生成前に失敗した場合、GeeAgent は raw provider JSON ではなく、configuration、vision-support、timeout、stopped-run の fixed message を直接表示できます。Chat sends は run が active な間、explicit pending activity を表示します。Runtime または tool activity が出た後も assistant chat text がまだ来ていない場合は thinking/reply-wait placeholder を維持し、assistant text chunks は final completion の前から conversation に stream されます。Run が active の間、composer の Send button は Stop に変わり、user は active request を interrupt し、run を cancelled として mark し、pending host actions を clear して、新しい message を開始できます。

Local SDK gateway は、provider に転送する前に `chat-runtime.toml` の chat output budget と temperature を適用します。Upstream provider または model が unavailable または timeout した場合、GeeAgent は別の provider や model を retry せず、その failure を直接報告します。
