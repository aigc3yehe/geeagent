# Gear 開発

## 状態と日付

文書日付：2026-05-01。

状態：Gear Platform V1 公開開発標準。この文書は現在の実装状態と目標アーキテクチャの両方を記録する。すでに実装されている挙動は「現在」として扱い、まだ完全には実装されていないが方針が確定している内容は「目標」または「V1 標準」として扱う。

この文書の読者は GeeAgent のオープンソース協力者、Gear 開発者、そして GeeAgent の内蔵 app / widget system の境界を理解する必要がある人である。これはマーケティング文書ではなく、長期的な marketplace 構想でもない。最初に実装可能な Gear platform 標準である。

## 目的

Gear は GeeAgent の optional built-in apps と Home widgets のための platform である。目的は app-specific business logic を main workbench に追加し続けることではない。目的は local-first で copy-install できる小さな app ecosystem を作ることである。

Core goals:

- gear は独立した package である。
- gear は copy、import、default enable、update、remove できる。V1 catalog は user-facing な gear disable control を表示しない。
- gear folder を削除すると、restart または registry refresh 後にその gear は表示されなくなる。
- 有効な gear folder を user data location にコピーすると、restart または registry refresh 後に表示される。
- broken、missing、policy-blocked、partially installed の gear は GeeAgent chat、tasks、settings、runtime startup、または unrelated gears を壊してはいけない。
- gear は `gear.json` で name、description、developer、cover image、version、entry、dependencies、permissions、future agent capabilities を宣言する。
- GeeAgent は discovery、validation、preparation、default enablement、window opening、widget rendering、future agent bridge を担当する。
- gear は business logic、resources、data、dependency declarations、callable capability declarations を担当する。
- future root agent は one control bridge を通じて gear を制御する。agent runtime に gear-specific pseudo-tools を追加しない。

V1 は実用的であるべきで、過度に複雑にしない。V1 の焦点は local copy/import、bundled gears、dependency preflight と first-run setup、default enablement、native macOS UX、future `gear.invoke` readiness である。V1 catalog は disable affordance を表示しない。policy-level disablement は internal protection state であり、normal user action ではない。V1 は remote marketplace、payments、ratings、reviews、remote automatic updates、mandatory developer signing を含まない。

## 用語

- `Gear`：GeeAgent 内で optional install / default enable される local app または widget package。
- `Gear app`：Gears catalog から開く full application。複雑な gear は GeeAgent main window の中に埋め込むのではなく、独立した macOS window を開くべきである。
- `Gear widget`：Home に表示される小さな情報 component。例は BTC price、CPU / memory monitoring。
- `Gear package`：gear id と同じ名前の folder。`gear.json`、README、assets、scripts、setup metadata、source、app files を含む。
- `GearHost`：GeeAgent 内で gear の discovery、validation、import、preparation、open、state tracking を担当する layer。future agent bridge へ ready capability list も提供する。
- `GearKit`：GearHost、first-party native gears、future adapters が共有する stable contract。concrete app business concepts を含めてはいけない。
- `gear.json`：gear manifest。最小 discovery file であり、catalog metadata、dependency setup、future agent capabilities の宣言元である。
- `Dependency preflight`：gear を open または render する前に required dependencies、versions、permissions を確認する process。
- `Capability`：future root agent が呼び出せる manifest-declared operation。capability は declaration であり、別個の global agent tool ではない。
- `Codex plugin projection`：GeeAgent が生成する Codex-compatible package と Gee MCP export bridge。Codex が明示的に export された GeeAgent capabilities を discover and invoke できるようにする。これは Gear の export view であり、Gear package、native Gear UI、GearHost、GeeAgent runtime semantics を置き換えない。

## 現在の実装状態

現在の active macOS app path:

```text
apps/macos-app/
```

現在の GearKit code:

```text
apps/macos-app/Sources/GearKit/
├── GearCapabilityRecord.swift
├── GearDependencyManifest.swift
├── GearKind.swift
├── GearManifest.swift
└── ModuleDisplayMode.swift
```

現在の GearHost code:

```text
apps/macos-app/Sources/GearHost/
├── GearDependencyPreflight.swift
├── GearPreparationService.swift
├── GearRecordMapping.swift
├── GearHost.swift
├── GearNativeWindowDescriptor.swift
└── GearRegistryCompatibility.swift
```

現在の bundled gear package skeletons:

```text
apps/macos-app/Gears/
├── media.library/
├── hyperframes.studio/
├── media.generator/
├── smartyt.media/
├── twitter.capture/
├── bookmark.vault/
├── wespy.reader/
├── app.icon.forge/
├── btc.price/
└── system.monitor/
```

現在の first-party native gear implementations はまだ host によって compile されている:

```text
apps/macos-app/Sources/GeeAgentMac/Modules/MediaLibrary/
apps/macos-app/Sources/GeeAgentMac/Modules/HyperframesStudio/
apps/macos-app/Sources/GeeAgentMac/Modules/MediaGenerator/
apps/macos-app/Sources/GeeAgentMac/Modules/SmartYTMedia/
apps/macos-app/Sources/GeeAgentMac/Modules/TwitterCapture/
apps/macos-app/Sources/GeeAgentMac/Modules/BookmarkVault/
apps/macos-app/Sources/GeeAgentMac/Modules/WeSpyReader/
apps/macos-app/Sources/GeeAgentMac/Modules/AppIconForge/
apps/macos-app/Sources/GeeAgentMac/Views/Content/HomeWidgetsView.swift
```

現在すでにある capabilities:

- `GearKit` と `GearHost` の file boundaries は存在する。現在はまだ one SwiftPM executable target を維持している。
- bundled gear packages は main app source tree から `apps/macos-app/Gears` に移動済みである。
- bundled resources と user Application Support から `gear.json` を scan できる。
- invalid manifest folders は crash ではなく Gears catalog の install issue として degrade する。
- folder name は manifest id と一致する必要があり、一致しない場合は install issue として表示される。
- Gears は default enabled である。internal policy-disabled state は残すが、V1 catalog は user disable affordance を表示しない。
- dependency preflight と setup snapshot model がある。
- `hyperframes.studio` には Node、npm、Hyperframes、FFmpeg、FFprobe の dependency plan がある。
- Gears catalog には checking、installing、failed、open の states がある。
- first-party `media.library` と `hyperframes.studio` は native windows として開ける。
- `media.generator` は現在の first-party Gear app である。Native media generation surface を提供し、image generation は global Xenodia provider channel を使い、models list、generation task creation、task state read の structured agent capabilities を公開する。
- `gee.app.openSurface`、progressive Gear capability disclosure、shared Gear invocation の first V1 host bridge surface がある。
- `bookmark.vault` は現在の first-party Gear app である。任意の text または URL を `gear-data/bookmark.vault` に保存し、media URL は `smartyt.media` と同じ `yt-dlp` metadata family で enrich する。Twitter/X tweet URL は embed metadata path を先に使い、その他の site は basic web metadata fetch に fallback する。
- `wespy.reader` は現在の first-party Gear app である。MIT licensed WeSpy Python package を wrap し、WeChat public-account articles、WeChat albums、general article pages を Markdown-first local task files に保存する。
- `app.icon.forge` は現在の first-party Gear app である。One local source image を macOS app icon package に変換し、rounded safe-area rendering、`AppIcon.icns`、`AppIcon.iconset`、`AppIcon.appiconset`、1024px preview を生成する。
- `telegram.bridge` は現在の first-party Gear である。Native Telegram Bridge surface、GearHost/Keychain-backed push-only Telegram delivery、Codex remote control と GeeAgent direct chat 用 worker polling service、Gee direct messages の Phase 3 channel ingress を提供する。Codex export は status/list/send push capabilities で enabled であり、channel creation は bot token binding と target confirmation が local configuration steps であるため Gee-native setup のままにする。
- full SDK/MCP tool exposure が完了するまでの transition path として、`host_action_intents` が first-party runtime turn から native Gear actions を GeeAgentMac に渡し、順番に適用できる。
- external Codex calls は generated `geeagent-codex` plugin と Gee MCP server により shared-store external invocations を作成する。GeeAgentMac はその queue を poll し、`gee_invoke_capability` / `gee_open_surface` を runtime と同じ GearHost bridge で drain し、Codex は `gee_get_invocation` で結果を読む。Exported built-in capabilities には low-risk な `media.generator` model/task queries、explicit user request 専用の high-risk `media.generator/media_generator.create_task` image task or batch creation、`media.library` view filtering/folder focus と explicit local file import、explicit user request 専用の high-risk `app.icon.forge/app_icon.generate` icon package generation、medium-risk な `bookmark.vault/bookmark.save` の Gear-owned bookmark writes、そして medium-risk な `telegram.bridge/telegram_push.send_message` configured push-only Telegram channel delivery が含まれる。
- `btc.price` と `system.monitor` は Home widgets の方向として存在する。

現在の gaps:

- first-party gear business logic はまだ main app source tree の中にある。
- Gear package folders はまだ full implementation boundary ではない。
- third-party gear import はまだ実装されていない。
- every Gear capability に対する full agent-runtime SDK/MCP tool injection はまだ完了していない。
- external Codex coverage は意図的に狭い。`exports.codex.enabled: true` を明示した capabilities だけが Codex から見える。Additional provider generation、download、import、user-file、高 side-effect capabilities は、approval、artifact、failure semantics が end to end で audit されるまで hidden または explicitly disabled のままにする。
- `telegram.bridge` は production daemon management と broader setup polish がまだ必要だが、現在の bridge は native GearHost push delivery、Keychain token lookup、push-channel creation、worker polling、Codex remote commands、Phase 3 direct-chat ingress を含む。
- `GearKit` と `GearHost` はまだ separate SwiftPM targets には分割されていない。

## 目標アーキテクチャ

目標アーキテクチャは四層である。

```text
GeeAgentMac main app
        |
        v
GearHost
        |
        v
GearKit
        |
        v
Gear Packages
```

## GeeAgentMac Main App

main app は workbench を担当する。gear business logic は担当しない。

Responsibilities:

- Main workspace shell、Home、chat、tasks、settings、side rail、app chrome。
- Gears catalog を開く。
- GearHost に existing gears と各 state を問い合わせる。
- GearHost に gear の prepare と open を依頼する。
- GearHost adapters が提供する gear windows または Home widget surfaces を host する。

Non-responsibilities:

- gear business logic を持たない。
- `WorkbenchStore` に gear dependency recipe logic を持たない。
- third-party gear の internal files を直接理解しない。
- agent runtime 内に gear-specific tools を実装しない。

## GearHost

GearHost は Gear platform manager である。macOS file system locations、Application Support、windows、processes、permissions、native UI と直接統合する必要があるため、Swift で実装するべきである。

Responsibilities:

- bundled と user-installed gear folders を discover する。
- `gear.json` を decode and validate する。
- bundled と user gear records を merge する。
- default enablement と policy-blocked state を管理する。
- install / preparation state を track する。
- dependency preflight と setup を実行する。
- `.geegear.zip` または gear folder を import する。
- open requests を正しい adapter に route する。
- Home widget records を提供する。
- future agent bridge に ready and policy-allowed capability declarations を提供する。
- per-gear setup logs と status snapshots を保存する。

GearHost は Eagle folder shapes、Hyperframes project internals、BTC formatting など app-specific business details を知らないべきである。それらは gear の責任である。

## GearKit

GearKit は GearHost、first-party native gears、future adapters が使う stable shared contract である。

V1 contents:

- `GearManifest`
- `GearKind`
- `GearEntry`
- `GearDependencyPlan`
- `GearDependencyItem`
- `GearPreparationState`
- `GearCapability`
- `GearPermission`
- `GearRecord`
- `GearAppAdapter`
- `GearWidgetAdapter`
- `GearProcessAdapter`
- `GearWebViewAdapter`

GearKit は app-specific concepts を避けるべきである。Eagle folders、media duration filters、Hyperframes project templates、BTC price formatting は GearKit に属さない。

## Gear Packages

各 gear は一つの folder を所有する。その folder を削除すると restart または registry refresh 後に gear は消える。有効な package を user gear directory にコピーすると restart または registry refresh 後に gear は表示される。

Target development bundled gear location:

```text
apps/macos-app/Gears/<gear-id>/
```

Migration 中、registry は legacy と current の bundled resource directory names を両方 scan する:

```text
gears/
Gears/
```

Runtime user-installed gear location:

```text
~/Library/Application Support/GeeAgent/gears/<gear-id>/
```

Gear user data location:

```text
~/Library/Application Support/GeeAgent/gear-data/<gear-id>/
```

Gear log location:

```text
~/Library/Application Support/GeeAgent/gear-data/<gear-id>/logs/
```

V1 package layout:

```text
<gear-id>/
├── gear.json
├── README.md
├── assets/
├── setup/
├── scripts/
├── data/
└── src/ or app/
```

Package rules:

- Folder name must equal `gear.json.id`。
- `gear.json` is required。
- Deliverable gears must include `README.md`。
- A folder containing only `gear.json` is a manifest stub, not a complete deliverable gear。
- Package files are treated as app code and static resources。
- Mutable user data must be written to `gear-data/<gear-id>/`。
- A gear must not read another gear's private package files。
- A gear must not write GeeAgent source folders。
- A gear must not store business data in `WorkbenchStore`。

## Language And Runtime Policy

V1 は multiple implementation styles を support するが、それぞれの安全性と用途を明確にする必要がある。

Host、GearHost、GearKit は Swift を使うべきである。

Reasons:

- GeeAgent は native macOS app である。
- Gear windows、menus、keyboard shortcuts、drag/drop、Quick Look、Finder handoff、permissions、accessibility は native に感じられるべきである。
- Gear management は macOS Application Support、process supervision、window lifecycle、sandbox、permissions と密接に統合される。

First-party native gear UI は Swift、SwiftUI、AppKit を使うべきである。

Applies to:

- `media.library`
- `hyperframes.studio`
- Quick Look、Finder handoff、native video / image preview、drag/drop、menus、keyboard shortcuts が必要な complex apps。

AA-style third-party sharing では V1 は次を優先する:

- `webview`：GeeAgent が native window shell の中で local UI files を host する。
- `external_process`：GeeAgent が local process を start and supervise し、stdio-json または local protocol で通信する。

Reasons:

- users は gear folder または `.geegear.zip` を Application Support に copy / import できる。
- GeeAgent は V1 で arbitrary Swift source を main process に dynamic compile / load すべきではない。
- external processes は arbitrary in-process code より stop、log、timeout、isolate しやすい。

Third-party native Swift plugins は後続の signed bundle または XPC route とし、V1 default capability にはしない。

Gear-internal data processing は TypeScript、Python、CLI tools、wasm、local models、その他 runtimes を使ってよい。ただし manifest で entry、dependencies、permissions を宣言する必要がある。

## Manifest V1

Minimal V1 manifest:

```json
{
  "schema": "gee.gear.v1",
  "id": "aa.cool.gear",
  "name": "Cool Gear",
  "description": "A useful local gear.",
  "developer": "AA",
  "version": "0.1.0",
  "category": "Utilities",
  "kind": "app",
  "entry": {
    "type": "external_process",
    "command": "scripts/start.sh",
    "protocol": "stdio-json"
  },
  "permissions": [],
  "dependencies": {
    "install_strategy": "on_open",
    "items": []
  },
  "agent": {
    "enabled": false,
    "capabilities": []
  }
}
```

Required fields:

- `schema`
- `id`
- `name`
- `description`
- `developer`
- `version`
- `kind`
- `entry`

Recommended fields:

- `category`
- `icon`
- `cover`
- `homepage`
- `license`
- `platforms`
- `permissions`
- `dependencies`
- `agent.capabilities`

Migration 中、V1 は existing `kind` values を受け入れるべきである:

- `atmosphere`：catalog から開ける full app surface。
- `widget`：small Home widget。

Recommended future wording:

- `app`
- `widget`

`category` は product grouping を表す:

- `Atmosphere`
- `Media`
- `Utilities`
- `Monitoring`
- `Creative`

`kind` は runtime and presentation behavior を決める。`category` は catalog organization のためだけに使う。

## Entry Standard

V1 entry types:

- `native`：first-party or host-known native adapter。
- `widget`：Home widget adapter。
- `external_process`：GearHost が supervise する local process。
- `webview`：native WebView shell で local files を render する。

`native` example:

```json
{
  "entry": {
    "type": "native",
    "native_id": "media.library"
  }
}
```

`widget` example:

```json
{
  "entry": {
    "type": "widget",
    "widget_id": "btc.price"
  }
}
```

`external_process` example:

```json
{
  "entry": {
    "type": "external_process",
    "command": "scripts/start.sh",
    "protocol": "stdio-json",
    "health_timeout_seconds": 20
  }
}
```

`webview` example:

```json
{
  "entry": {
    "type": "webview",
    "root": "app/index.html",
    "allow_remote_content": false
  }
}
```

V1 は real gear が必要とし、GearHost が対応 adapter を持つ場合以外、entry type を増やすべきではない。

## Dependency Standard

Dependency strategy は global-first である。

Rules:

- compatible global dependency が既に存在する場合、gear はそれを使う。
- required dependency が missing の場合、user がその gear を open したとき setup が trigger される。
- GeeAgent startup では dependencies を install しない。
- policy-blocked gears の installers は run しない。
- dependency failure は current gear のみ影響する。
- global installers は user developer environment を mutate するため、user-visible でなければならない。
- gear-local installers は allowed gear package または gear-data locations の中だけに write できる。

Dependency manifest example:

```json
{
  "dependencies": {
    "install_strategy": "on_open",
    "items": [
      {
        "id": "node",
        "kind": "runtime",
        "scope": "global",
        "required": true,
        "detect": {
          "command": "node",
          "args": ["--version"],
          "min_version": "22.0.0"
        },
        "installer": {
          "type": "recipe",
          "id": "brew.install.node"
        }
      },
      {
        "id": "ffmpeg",
        "kind": "binary",
        "scope": "global",
        "required": true,
        "detect": {
          "command": "ffmpeg",
          "args": ["-version"]
        },
        "installer": {
          "type": "recipe",
          "id": "brew.install.ffmpeg"
        }
      }
    ]
  }
}
```

Supported dependency kinds:

- `binary`：executable helper or CLI。
- `framework`：native framework or dylib bundle。
- `model`：local model、embedding index、inference asset。
- `data`：seed database、lookup table、templates、static content。
- `runtime`：external process gear が必要とする language or runtime。

Supported dependency scopes:

- `global`：system environment または known install locations から resolve し、missing の場合は user-visible setup flow で install する。
- `gear_local`：gear folder relative に resolve し、その gear のためだけに prepare する。

Supported installer types:

- `recipe`：Homebrew install、npm global install、guided official installer など host-known install recipe。
- `script`：gear-local installer script。
- `archive`：gear-local archive を declared target に展開する。
- `none`：dependency が already present である必要がある。

Installer requirements:

- idempotent でなければならない。
- 二回実行しても gear を壊してはいけない。
- `gear_local` installers は temporary files を除き gear boundary 外に write してはいけない。
- `global` installers は action、logs、failure、retry を user-visible flow で表示する。
- network access が必要な installers は `network.download` を declare する。

## First-Run Install Flow

User が gear を open または enable し、required dependencies が missing の場合、GeeAgent は open action を即失敗させるべきではない。その gear の setup flow に入るべきである。

State machine:

```text
installed -> checking -> ready
installed -> checking -> needs_setup
needs_setup -> installing -> ready
needs_setup -> installing -> install_failed
install_failed -> installing -> ready
policy_blocked -> checking/installing only after policy changes
```

State meanings:

- `invalid`：manifest or package invalid。
- `installed`：package discoverable and manifest valid, but dependencies have not been confirmed ready。
- `disabled`：internal または policy により disabled。V1 catalog は user disable button を提供しない。
- `checking`：dependency or permission preflight is running。
- `needs_setup`：required dependency missing or incompatible。
- `installing`：setup is running。
- `ready`：can open or render。
- `install_failed`：setup failed and unrelated features keep working。
- `blocked`：policy or permission prevents use。

Gears catalog button meanings:

- `Open`：gear is ready and can launch。
- `Checking...`：preflight is running。
- `Install Dependencies`：dependencies are missing and setup can run。
- `Installing...`：setup is running and button must not trigger another install。
- `Retry Install`：previous install failed and clicking retries。
- V1 catalog は user-facing な `Enable` / `Disabled` actions を表示しない。Gears は default enabled であり、利用できない gear は blocked、installing、failed state として表示する。

Home widgets は同じ dependency flow を使う。missing dependencies の widget は broken Home card を render せず、Gears catalog で installing または failed state を表示する。

## Import And Install Standard

V1 は二種類の local install inputs を support する:

- Gear folder。
- `.geegear.zip`。

Install target:

```text
~/Library/Application Support/GeeAgent/gears/<gear-id>/
```

Import flow:

- User selects a folder or `.geegear.zip`。
- zip の場合は temporary directory に extract する。
- path traversal を reject する。
- multiple top-level packages を reject する。
- `gear.json` を validate する。
- folder name equals manifest `id` を確認する。
- schema、version、platforms、entry type を check する。
- same ID が存在する場合、replace / update / cancel を尋ねる。
- Application Support に atomically copy する。
- GearHost registry を refresh する。
- Gears catalog に status を表示する。

V1 は remote marketplace を必要としない。V1 は local sharing を先に良くする必要がある。AA が gear を作り、folder または `.geegear.zip` を他者に送り、受け取った user が user data directory に copy するか `Import Gear...` を実行すれば install できる状態を目指す。

## Permission Standard

V1 permissions は explicit and minimal でなければならない。

Recommended permission IDs:

- `filesystem.read.user_selected`
- `filesystem.write.user_selected`
- `filesystem.read.gear_storage`
- `filesystem.write.gear_storage`
- `network.download`
- `network.api`
- `process.spawn`
- `shell.execute`
- `camera`
- `microphone`
- `automation.apple_events`

Rules:

- undeclared high-risk capabilities は run してはいけない。
- files を download する installers は `network.download` を declare する。
- external process gears は `process.spawn` を declare する。
- shell scripts は `shell.execute` を declare する。
- high-risk permissions は user confirmation が必要である。
- manifest permissions は gear needs を表す。macOS system permissions の代替ではない。

## Storage Standard

Package directory:

```text
~/Library/Application Support/GeeAgent/gears/<gear-id>/
```

Mutable data directory:

```text
~/Library/Application Support/GeeAgent/gear-data/<gear-id>/
```

Recommended data layout:

```text
gear-data/<gear-id>/
├── config.json
├── state/
├── cache/
├── logs/
├── projects/
└── exports/
```

Rules:

- package directory stores manifest, code, static resources, setup files, and scripts。
- data directory stores user data, state, caches, generated output, and logs。
- A gear must not write another gear's data directory。
- A gear must not write GeeAgent source directories。
- package 内の `data/` は seed or static data のためだけに使い、runtime user state を置かない。

## UIUX Standard

Gears は native macOS experience を提供しなければならない。

Rules:

- Gear apps should feel like native macOS apps, not web pages embedded inside the main window。
- Complex apps should open their own independent windows。
- Prefer SwiftUI / AppKit windows, menus, keyboard commands, system sheets, popovers, drag/drop, Quick Look, Finder handoff, and accessibility patterns。
- WebView gears must still be hosted by a native shell。
- Home widgets must stay lightweight and must not embed full app navigation。
- Missing dependencies should show setup state, not broken UI。
- Components may be visually customized, but behavior should match macOS user expectations。
- Gears catalog should avoid excessive nested containers。Prefer shallow navigation, clear lists, state badges, and necessary action buttons。
- Button groups and component groups should not rely on parent container borders to express hierarchy。Prefer proximity and consistent styling。
- Dropdowns, popovers, buttons, sliders, and context menus need custom visual polish while keeping macOS-like interaction models。

## Provider And Channel Ownership

Provider と channel configuration は GeeAgent global infrastructure であり、Gear state ではありません。

Rules:

- Main app runtime owns provider routing, API keys, endpoint URLs, readiness checks, and secret storage。
- Gear packages must not store provider API keys, long-term tokens, or channel-specific secrets in `gear.json`, package files, or `gear-data/<gear-id>/`。
- Gear は Xenodia image generation のような global network capability が必要であることを宣言できますが、configured channel は Gee host/runtime boundary を通じて request しなければなりません。
- Xenodia image generation は chat routing と同じ infrastructure layer の global provider channel として公開されます。現在の channel には image generation endpoint と task retrieval endpoint があり、将来 dedicated storage upload endpoint を追加できます。
- Generation reference images should use the global Xenodia media channel。Separate Xenodia storage API が設定されていない場合、local reference images は Xenodia image generation request の multipart `image_input` として直接送れます。Gears must not reintroduce Qiniu or another package-local object store。
- First-party Gears may show future provider placeholders, such as video or audio generation, but they must not wire non-Xenodia providers copied from reference projects until the global provider layer supports them。
- Provider failures must return structured errors to the active run。Gear UI may show a concise state, but final user-facing prose still belongs to the active agent/LLM。

## Agent Control Bridge

Gear は full agent protocol を定義しない。agent runtime が control protocol、permission semantics、run events、approval flow、continuation semantics を所有する。

Current V1 implements the first native Gee host bridge surface:

- `gee.app.openSurface` opens a Gee surface or Gear window by id, such as `media.library`。
- `gee.gear.listCapabilities` は compact summary から enabled Gear capabilities を公開し、capability id と required arguments を含めます。
- `gee.gear.invoke` invokes one declared Gear capability through the shared host bridge。
- phase-2 SDK runtime は active agent に対して、`gee` MCP bridge tools の `app_open_surface`、`gear_list_capabilities`、`gear_invoke` としてこれらの controls を公開します。
- MCP Gear tools は same SDK run を pause し、`host_action_intents` を emit し、GeeAgentMac に native Gear action を実行させ、その structured host results で same run を resume します。Agent が結果を inspect した後に別の Gear step が必要なら、同じ pause / execute / resume loop を繰り返します。
- SDK session が `gee` MCP tools を公開していない場合、GeeAgent は structured runtime failure を返し、fallback execution path に切り替えたり、source code inspection を bridge の代替にしたり、task complete と主張したりしてはいけません。
- Legacy host-action control frames は migration-only data です。Runtime は transcript projection の前に consume または reject し、GeeAgentMac は normal chat text として表示してはいけません。Visible chat は user text、typed plan/focus/stage activity rows、meaningful thinking state、tool invocation/result rows、assistant replies を transcript event order で表示します。Final assistant reply が存在する場合、earlier work trace rows は compact な `Worked` section に collapse でき、その中の各 row は個別に expand できます。setup、delegation、same-run Gear pause/resume breadcrumbs、finalize、model-authored `Stage complete:` progress fragments などの low-signal runtime plumbing は prominent thinking block や chat bubble として表示しません。
- `host_action_intents` は active SDK run の MCP Gear bridge によって作成され、GeeAgentMac が順番に適用します。Complex capture or multi-Gear requests must remain agent-planned through the MCP bridge。
- `media.filter` で設定された media-library filters は native UI の active filters として表示されます。User は `All` または `Clear filters` から full media view に戻れます。
- `media.filter`、`media.focus_folder`、`media.import_files` require an authorized media library。Media Gear should first try to restore saved macOS security-scoped access, then fall back to the saved last-library path and let macOS show a visible one-time authorization prompt when needed。Opening the Media Library window must not wait on that restore attempt; the window should appear first and show bounded restore progress。If no library can be restored before the restore timeout, Gear actions must return a structured failure with `code: "gear.media.authorization_required"` and a `navigate.module` intent for `media.library` instead of reporting a misleading success。
- Runtime turns must persist tool-use and tool-result events incrementally as they arrive。GeeAgentMac should be able to refresh the active Chat transcript while a Gear workflow is still running, so users see each bridge call appear step by step instead of receiving several completed tool cards only after the final reply。
- Tool requests must pass through GeeAgent's Tool Boundary Gateway before execution。The gateway normalizes arguments、validates the target、chooses the execution adapter、and normalizes results before transcript projection。This applies to provider-converted tool calls、Claude SDK native tools、and Gear bridge calls。UI-only cleanup is not enough。
- Focused runtime stages may carry deterministic `capability_args` extracted from the user's request or prior structured results。The Tool Boundary Gateway may merge those arguments into the matching same-stage Gear invocation when the model omits them, but conflicting values fail as structured argument errors instead of being silently overwritten。
- Gear に一致する requests では bridge が preferred execution path です。User が GeeAgent 自体の debug を明示した場合を除き、agent は GeeAgent source files を inspect したり、SDK `Skill` aliases を call したり、Bash で product internals を discover したりしてはいけません。

Gear の実行結果は structured data であり、final prose ではありません。Gear capability、native adapter、または transition router は state changes、counts、artifacts、warnings、errors を返せますが、ユーザーに表示する最終完了文を hardcode してはいけません。1 turn 内のすべての Gear actions が完了した後、GeeAgent は structured results を active agent/LLM に戻し、agent が結果とユーザーの言語に合わせて最終返信を生成します。LLM continuation が実行できない場合、GeeAgent は fake hardcoded success message ではなく、明確な pending または failure state を表示するべきです。

Native host が Gear action を完了したら、短い summary と bounded な `result_json` payload を continuation turn に返せます。summary は quick display 用であり、`result_json` が task id、paths、counts、artifacts、captured records、structured errors の source of truth です。大きな結果 payload は agent context に大量投入せず、Gear data directory に保存して path で参照するべきです。

Continuation では、GeeAgent が大きな `result_json` payload を `result_artifact` reference に置き換える場合があります。Model-facing payload には ids、status、summary、error、artifact path、hash、byte count、token estimate を残し、full JSON は明示的に必要な follow-up inspection のために disk に保存されます。

Complex Gear work must be agent-planned, not router-planned。Local Gear capabilities should be decomposed into small tool primitives such as save bookmark、fetch tweet、sniff media、download media、import files、and attach local paths。The active agent should create a plan, invoke one primitive, inspect the structured result, and then choose the next primitive。Local routers and `host_action_intents` must not pre-build a full multi-step workflow such as “capture Tweet, discover media, download video, import to Media Library, and update Bookmark” because that prevents result-driven correction。

runtime plan が stage focus を locked している場合、capability discovery は stage-scoped にします。GeeAgent はまず current stage の focused summary を要求し、必要な structured result が存在してから later stage の focus set に進むべきです。

Stage advancement には、完了した Gear と capability identifier を含む structured `result_json` evidence が必要です。Human-readable summary は UI 表示には使えますが、それだけでは stage complete として扱いません。

Gear invocation も stage-scoped です。Focused runtime stage が active の間、GeeAgent はその stage の `required_capabilities` に含まれない Gear capability invocation を拒否し、stage が進むか明示的に replan されるまで実行しません。

Deterministic stage arguments は runtime plan の一部であり、fallback route ではありません。They can only fill the selected stage's declared capability invocation, and they remain visible through normalized tool input and structured results。

Progressive disclosure is still required, but the summary is now an invocation index rather than a forced prelude to every schema call。The agent should first request `detail: "summary"`; if the compact record contains the needed capability and its required arguments are clear, it may invoke directly。It should request `detail: "capabilities"` or `detail: "schema"` only when optional argument types or exact semantics are unclear。GeeAgent should not dump every Gear capability schema into the model context by default。

Current host invocation shape:

```json
{
  "tool": "gee.gear.invoke",
  "gear_id": "media.library",
  "capability_id": "media.filter",
  "args": {
    "kind": "video",
    "starred_only": true
  }
}
```

Current SDK MCP tool shape:

```json
{
  "tool": "mcp__gee__gear_invoke",
  "gear_id": "media.library",
  "capability_id": "media.filter",
  "args": {
    "kind": "video"
  }
}
```

### Codex Plugin Projection

目標は、GeeAgent で使える capability を、安全で明示的に export された場合に Codex からも使えるようにすることである。実装モデルは、Codex が local Gee MCP export server を呼べるように one GeeAgent Codex plugin を生成する形である。

これは Gear を Codex plugin に変換することではない。Gear は引き続き authoritative package、native app/widget、data、permission、dependency、execution boundary である。Codex plugin は plugin metadata、MCP configuration、Codex に Gee bridge の呼び出し方を教える skills を含む installable projection にすぎない。

Core export standard は `docs/planning/gee-capability-export-standard-v0.md` にある。

Current implementation status: agent runtime には manifest-backed export status/list/describe commands、Codex-facing MCP stdio server、shared-store external invocation queue、local `geeagent-codex` plugin generator、home-local install command がある。Generated `gee-capabilities` skill は Codex の first entry point であり、GeeAgent plugin とは何かを説明し、generated capability index と per-Gear reference files に誘導し、invocation 前に live MCP discovery / describe を要求する。Install command は default で `~/plugins/geeagent-codex` を書き込み、`~/.agents/plugins/marketplace.json` を refresh する。`gee_status`、`gee_list_capabilities`、`gee_describe_capability` は manifest projection によって提供される。`gee_invoke_capability` と `gee_open_surface` は external invocation を作成し、GeeAgentMac が live GearHost bridge 経由で drain する。`gee_get_invocation` は recorded status/result を返す。`media.generator/media_generator.create_task` は explicit user-requested image generation 用に export され、`batch_count` 1-4 fan-out を含み、同じ queue から task または batch status/artifact references を返す。`telegram.bridge/telegram_push.send_message` は configured push-only Telegram channels 用に export され、real Telegram delivery metadata または structured failed/degraded state を返す。GeeAgentMac が running でない、または queue を drain できない場合、Codex は `fallback_attempted: false` を含む pending/failed/blocked/degraded structured result を受け取る。Stale `running` invocation は degraded になり、automatic retry ではなく manual-retry recovery を返す。MCP server は Gear business logic を実行せず、fallback scripts も実行しない。

Target Codex-facing package shape:

```text
geeagent-codex/
├── .codex-plugin/
│   └── plugin.json
├── .mcp.json
├── skills/
│   └── gee-capabilities/
│       ├── SKILL.md
│       └── references/
│           ├── capability-index.md
│           └── <gear-id>.md
└── assets/
```

Target Gee MCP export tools:

- `gee_status`
- `gee_list_capabilities`
- `gee_describe_capability`
- `gee_invoke_capability`
- `gee_open_surface`
- `gee_get_invocation`

Generated plugin package には `.codex-plugin/plugin.json`、`.mcp.json`、`skills/gee-capabilities/SKILL.md`、`references/capability-index.md`、generated per-Gear reference files が含まれる。References は offline orientation snapshot である。`.mcp.json` は Codex を `native-runtime codex-mcp` に接続し、installed Gear availability は static plugin metadata ではなく MCP server の live data であり続ける。

Codex から見えるのは ready、enabled、policy-allowed、export-eligible な Gear capabilities だけである。disabled、failed、installing、invalid、blocked、または明示的に non-exported な Gear は Codex から見えない。Export bridge は Gear feature ごとに Codex tool を作らず、Gear business logic を複製せず、provider secrets を保存せず、package-local fallback scripts を呼ばない。

Codex-originated calls は external invocations である。caller metadata、normalized input、structured results、artifact references、failure or recovery reasons を記録する。これらは hidden GeeAgent chat turns にはならない。GeeAgent、GearHost、target Gear、provider channel、permission、または live bridge が unavailable の場合、Codex は real reason を持つ structured pending、failed、blocked、または degraded result を受け取る。

Gear capabilities は `gear.json` の `agent.capabilities[].exports.codex` で Codex export policy を宣言できる。GeeAgent native surface の外では unsafe または meaningless な capability は、理由付きで Codex export disabled と明示するべきである。

Gear、capability、result shape、artifact、permission、provider requirement、dependency behavior、failure code が変わる場合、maintainer は Codex plugin projection、Gee MCP export schema、generated skills、plugin metadata も更新が必要か確認しなければならない。Substantial Gear change に Codex export impact がない場合、final work summary でそれを明示する。

Gear execution has no public textual fallback directive. Legacy directive-shaped
records may be normalized for migration safety, but new agent turns must use the
MCP Gear bridge. Missing bridge tools, invalid arguments, or stale pending host
actions must fail with structured reasons instead of replaying side effects or
presenting partial work as complete.

Rules:

- only `ready + policy-allowed` gears expose capabilities。
- `policy-blocked`、`invalid`、`installing`、`install_failed`、`blocked` gears are invisible to the agent。
- capabilities are declared in `gear.json`。
- Gear adapters validate `capability_id` and `args`。
- Gear adapters return structured results。The active agent/LLM owns the final natural-language reply after execution。
- Do not add one global pseudo-tool per gear feature。
- root agent enters gear surfaces only through the shared bridge。
- First-party Gear business logic remains inside the Gear adapter boundary, not in generic runtime glue。

Capability example:

```json
{
  "agent": {
    "enabled": true,
    "capabilities": [
      {
        "id": "media.filter",
        "title": "Filter media",
        "description": "Change visible media by folder, type, star state, duration, or search text.",
        "input_schema": {
          "type": "object",
          "properties": {
            "folder_name": { "type": "string" },
            "kind": { "type": "string", "enum": ["all", "image", "video"] },
            "extensions": { "type": "array", "items": { "type": "string" } },
            "starred_only": { "type": "boolean" },
            "minimum_duration_seconds": { "type": "number" },
            "search_text": { "type": "string" }
          }
        },
        "examples": [
          "Show only videos",
          "Show only starred images",
          "Show mp4 files longer than 3 minutes"
        ]
      }
    ]
  }
}
```

## First-Party Gear Migration

First-party gears は段階的に real package boundaries へ移行するべきである。

`media.library`:

- Target: complete Eagle-compatible local media manager。
- Package includes manifest, README, assets, setup metadata, storage notes, and future capability declarations。
- Native Swift implementation may remain host-compiled during migration, but the business boundary must move out of the main app。
- Folder management, filtering, starring, Quick Look, Finder handoff, video / gif hover playback, and live presentation mode belong to the media gear, not the main workbench。
- Agent capabilities include `media.filter`, `media.focus_folder`, and `media.import_files`。Current user が local files の import を明示した場合、`media.import_files` は GeeAgent root-agent conversations と Codex conversations の両方から trigger できる。It imports local media paths into the authorized media library, restores saved access when possible, and returns item proof for multi-Gear workflows。New files は `imported_items` に入り、duplicate files は idempotent success として `action: "import_noop"`、`existing_items`、`duplicate_paths` を返す。Requested source files が見つからない場合は `missing_paths`、unsupported files は `unsupported_paths` で報告する。Supported imported or existing media item が 1 件もない場合、`imported_count: 0` の成功として扱わず、`code: "gear.media.no_supported_files"` の structured failure を返す。Authorization が missing の場合、readable paths を `pending_paths` として保持し、Media Library surface を開き、active agent/LLM が説明できる structured failure を返す。

`hyperframes.studio`:

- Target: creative gear requiring Node, npm, Hyperframes, FFmpeg, and FFprobe。
- Must use dependency preflight and setup snapshots。
- Dependency failure affects only Hyperframes。
- Business logic and project data must not enter the main app store。

`media.generator`:

- Target: Dailystarter generator module から adapted した native media generation Gear。
- Gear は image generation を first に support し、global Xenodia channel を使う。現在 enabled models は `nano-banana-pro` と `gpt-image-2`。`image-2` は `gpt-image-2` の user-facing alias として受け付ける。
- Nano Banana Pro exposes `n=1`, `async`, `response_format=url`, `aspect_ratio`, `resolution`, `output_format`, and reference images。GPT Image-2 exposes `n=1`, `async`, `response_format=url`, `aspect_ratio`, `resolution`, and reference images。GPT Image-2 には `output_format` または `nsfw_checker` を送らない。
- Multi-image generation は Gear-level `batch_count` 1-4 を使う。Gee は requested image ごとに persisted Xenodia `n=1` child task を作成し、同じ `batch_id` で group 化し、native task list では one batch row と result grid として表示する。
- Reference image limits are model-specific: Nano Banana Pro は up to 8 total inputs、GPT Image-2 は up to 16 total inputs。Local references must be JPEG, PNG, or WebP and 30MB or smaller。
- Video and audio generation are present as product surfaces and capability placeholders, but V1 must not connect the reference project's non-Xenodia providers。Xenodia-backed endpoints が global provider channel から利用可能になるまでは structured unsupported-category results を返す。
- Reference image upload must not use Qiniu from the reference project。Local references should flow through the Xenodia request or a future global Xenodia storage upload endpoint owned by the main app runtime。
- Task state belongs in `~/Library/Application Support/GeeAgent/gear-data/media.generator/tasks/<task-id>/task.json`。Batch rows は child task records の projection であり、task storage path を置き換えない。Current batch task records use schema version 2；this schema cutover may clear older task history。
- Generated results should be cached under `~/Library/Application Support/GeeAgent/gear-data/media.generator/tasks/<task-id>/outputs/` when possible。Preview and download should prefer the Gear-owned local artifact while preserving the remote URL as fallback。
- Reusable quick prompts は `~/Library/Application Support/GeeAgent/gear-data/media.generator/quick-prompts.json` に保存する。Users can add, edit, delete, and reset them from the native Gear UI。
- Pasted URLs と local files からの recent reference images は `~/Library/Application Support/GeeAgent/gear-data/media.generator/image-history.json` に保存する。History sheet は file picker を開かず、それらの references を reuse する。Generated results は task records と output caches に残し、reference history へ自動追加しない。
- Async task polling は Gear open または history reload 時に `running` / `queued` tasks を resume しなければならない。Polling should treat Xenodia `success` as completed、`fail` as failed、and read generated URLs from the normalized `result` payload。
- Xenodia image generation は long-running task として扱う。create、multipart、task-status requests は minimum 30-minute timeout floor を使う。Status request が timed out した場合、provider が still generating の間に failed とせず、local task は `running` のまま polling を続ける。
- Native Generate button は task row が local queue に入った後も new prompts に使える状態を保つ。Provider creation、result caching、polling は background task state として継続し、creation control を長時間占有してはならない。
- Native task workbench は status filters、model filters、search、starred results、local-cache badges、Finder reveal、large preview、URL copy、user-chosen download、task Apply による prompt/model/parameters/references restore、separate reuse-as-reference、confirmed task-history deletion を support する。
- Agent capabilities are `media_generator.list_models`, `media_generator.create_task`, and `media_generator.get_task`。`media_generator.create_task` can be triggered from both GeeAgent root-agent conversations and Codex conversations。Multi-image requests use `batch_count` 1-4 while provider `n` stays 1。Each returns structured task or batch/model data for the active agent/LLM to summarize。

`smartyt.media`:

- Target: native URL media acquisition gear adapted from the SmartYT reference project。
- Gear は URL を受け取り、media metadata を sniff し、audio、video、または direct image artifacts を download し、transcript text を抽出する。
- V1 uses `yt-dlp` for metadata, downloads, and subtitle extraction, and `ffmpeg` / `ffprobe` for media conversion support。
- Transcript extraction should prefer platform subtitles first。If no subtitle is available, the Gear may fall back to local speech tooling such as Whisper when installed。If no speech backend is available, the Gear must return a structured failure that explains the missing transcription backend instead of pretending the conversion completed。
- Job state belongs in `~/Library/Application Support/GeeAgent/gear-data/smartyt.media/`, while downloaded media, extracted subtitles, and transcript text default to `~/Downloads/SmartYT/<job-id>/` unless an agent call provides an explicit `output_dir`。
- Agent capabilities are `smartyt.sniff`, `smartyt.download`, `smartyt.download_now`, and `smartyt.transcribe`。`smartyt.download` は app UI 向けに queue し、`smartyt.download_now` は artifacts が生成されるまで待って `output_paths` を返す。Direct image URLs, including Twitter/X image URLs with an image extension or a `format=` query hint, are treated as image downloads instead of video downloads。The active agent/LLM owns the final user-facing reply。

`twitter.capture`:

- Target: Workbench reference project の Twikit capture flow から adapted した native Twitter/X content capture gear。
- Gear は single Tweet URL、List URL plus limit、または username / profile URL plus limit を受け取る。
- V1 は `apps/macos-app/Gears/twitter.capture/scripts/` にある package-local Python sidecar と `twikit` library を使う。Sidecar は user-provided authenticated Twitter/X cookie JSON file を必要とし、GeeAgent は credentials を bundle しない。
- Task state と captured results は `~/Library/Application Support/GeeAgent/gear-data/twitter.capture/tasks/<task-id>/task.json` に保存する。
- Native UI は、その Gear-owned task database から saved Twitter Capture task records をすべて clear できる。
- Captured tweet records には ids、URLs、author handles、text、language、counts、tweet timestamps、reply / retweet flags、利用可能な場合は normalized media metadata が含まれる。
- Native task surface は task creation time を local time として表示する。Main result card には tweet publish timestamps を表示しない。
- Agent capabilities are `twitter.fetch_tweet`, `twitter.fetch_list`, and `twitter.fetch_user`。Each capability creates a Gear task, stores the result in the file database, and returns structured task/result data for the active agent/LLM to summarize。
- Missing cookies、expired sessions、rate limits、Twikit failures は structured task failures として返す必要がある。Gear は successful capture を fake してはいけない。

`bookmark.vault`:

- Target: universal information capture Gear。
- Gear は arbitrary raw content を保存する。Content に URL が含まれる場合、Twitter/X embed metadata、`yt-dlp` media metadata、basic web fetch の順に metadata enrichment を試みる。
- Bookmark records belong in `~/Library/Application Support/GeeAgent/gear-data/bookmark.vault/bookmarks/<bookmark-id>/bookmark.json`。
- Agent capability `bookmark.save` accepts `content` and optional `local_media_paths`。Multi-Gear workflows should pass Media Library imported item paths when related media has been downloaded and imported。

`wespy.reader`:

- Target: external WeSpy Python package によって動作する native article reader Gear。
- Gear は single article URL、article list 用の WeChat public-account album URL、または batch Markdown capture 用の WeChat album URL を受け取る。
- V1 は `apps/macos-app/Gears/wespy.reader/scripts/` にある package-local Python sidecar を使い、user-installed `wespy` package を import する。GeeAgent は WeSpy source を main runtime に vendor しない。
- Task state と generated file paths は `~/Library/Application Support/GeeAgent/gear-data/wespy.reader/tasks/<task-id>/task.json` に保存する。
- Agent capabilities are `wespy.fetch_article`, `wespy.list_album`, and `wespy.fetch_album`。Each capability returns structured task data, article counts, generated file paths, article metadata, and structured errors for the active agent/LLM to summarize。
- Missing Python packages、site structure changes、blocked source pages、network failures は structured task failures として返す必要がある。Gear は successful article capture を fake してはいけない。

`app.icon.forge`:

- Target: native macOS app icon production Gear。
- Gear は user-selected local image を一つ受け取り、center-crop で square 化し、transparent 1024px canvas の rounded safe-area に描画して complete icon package を export する。
- Generated artifacts include `<name>.icns`, `<name>.iconset`, `<name>.appiconset`, `preview-1024.png`, and `icon-export.json`。
- Agent capability `app_icon.generate` accepts `source_path`, optional `output_dir`, `name`, `content_scale`, `corner_radius_ratio`, and `shadow`, then returns structured artifact paths and generation specs。
- Capability は GearHost bridge を通じて GeeAgent root-agent conversations と Codex conversations から利用できる。Codex callers は user が明示した local paths だけを渡し、GearHost が返す artifact paths をそのまま報告し、package-local image scripts を実行してはいけない。

Information capture workflow:

- Pure text should go straight to `bookmark.save`。
- URL metadata capture should save through `bookmark.save`; use `twitter.capture` or `smartyt.media` only when the user asks for deeper Twitter/media content or when the URL strongly implies media acquisition。
- WeChat public-account article or album URLs should use `wespy.reader` when the user asks for Markdown, article extraction, or batch album capture; use `bookmark.save` only when the user asks to save the URL itself as a bookmark。
- Twitter/X status URLs default to media acquisition unless the user explicitly asks to save metadata only or not to download media。Tweet/media details が必要な場合は `twitter.fetch_tweet` を使い、その後 downloadable video または image URL ごとに `smartyt.download_now` を使う。
- YouTube URLs should use `smartyt.sniff` as the lightweight duration probe before default download decisions。Default download is allowed only when `duration_seconds` is below 300 seconds; longer or unknown-duration videos should be saved as metadata unless the user explicitly asks to download。
- Strong media acquisition should use `smartyt.download_now` for each media URL, then `media.import_files`, then `bookmark.save` with `local_media_paths`。
- If no media library is authorized, `media.import_files` should preserve downloaded paths as `pending_paths`, open the Media Library surface, and ask the user to choose or create a library before claiming import succeeded。Bookmark Vault may still keep the downloaded paths so the workflow can resume after authorization。
- `media.import_files` に依存する runtime stage は、media import completed と主張する前に `available_count > 0`、または non-empty `imported_items` / `existing_items` を要求する。Successful invocation と bare `imported_count: 0` だけでは completion proof として不十分である。

`btc.price`:

- Target: Home widget。
- Must be lightweight, draggable, and refreshable。
- Network access must be declared。
- Widget must not contain full app navigation。

`system.monitor`:

- Target: Home widget。
- Shows local CPU / memory and similar information。
- Must stay lightweight and avoid high-frequency sampling that harms the main app。

## Suggested Directory Upgrade

Target directory:

```text
apps/macos-app/
├── Gears/
│   ├── media.library/
│   ├── hyperframes.studio/
│   ├── smartyt.media/
│   ├── twitter.capture/
│   ├── bookmark.vault/
│   ├── wespy.reader/
│   ├── app.icon.forge/
│   ├── btc.price/
│   └── system.monitor/
└── Sources/
    ├── GearKit/
    ├── GearHost/
    └── GeeAgentMac/
```

Migration principles:

- Establish `GearKit` and `GearHost` folder boundaries first。
- The first implementation may keep a single SwiftPM target while making file structure and import boundaries clear。
- Later, split `GearKit` and `GearHost` into SwiftPM targets。
- Move bundled gear packages from `Sources/GeeAgentMac/gears` to `apps/macos-app/Gears`。
- The main app should obtain catalog, window, and widget surfaces only through GearHost。

## Implementation Phases

## Phase 0: Boundary Freeze

Goal: prevent new gear business logic from entering the main app。

Deliverables:

- Record existing gear entry points。
- Mark legacy host-compiled adapters。
- Do not add gear business state to `WorkbenchStore`。
- Do not add gear-specific pseudo-tools。

Acceptance:

- New features land inside the gear package, GearHost, or GearKit boundary。
- The main app calls only generic gear APIs。

## Phase 1: Extract GearKit And GearHost

Goal: make the module boundary real in the file structure。

Deliverables:

- Create `Sources/GearKit`。
- Create `Sources/GearHost`。
- Move manifest, dependency, preparation, and registry types。
- Keep current behavior unchanged。
- Add public APIs for scan, list, prepare, open, widget records, and capability records。Policy-disable APIs は internal protection mechanisms として残せるが、V1 catalog actions ではない。

Acceptance:

- `swift build` passes。
- Gears catalog behavior stays the same。
- Deleting an unrelated gear does not break app startup。
- Invalid `gear.json` still appears as an install issue。

## Phase 2: Move Bundled Gear Packages

Goal: make development gear packages structurally independent。

Deliverables:

- Create `apps/macos-app/Gears`。
- Move `media.library`, `hyperframes.studio`, `btc.price`, and `system.monitor` package skeletons。
- Update SwiftPM resource copy。
- Registry supports the new bundled root。
- Old root remains compatible during migration。

Acceptance:

- Bundled gears still appear in the catalog。
- If a package is deleted, that gear disappears or shows a clear install issue。
- Merge behavior for same-ID packages in user Application Support is explicit。

## Phase 3: Migrate First-Party Native Gear Boundaries

Goal: make first-party native gear boundaries clear。

Deliverables:

- Register `media.library` adapter in GearHost。
- Register `hyperframes.studio` adapter in GearHost。
- Register Home widgets through widget adapters。
- README explains which parts are still host-compiled during migration。
- Move gear-specific state out of generic stores。

Acceptance:

- The main app does not directly open the MediaLibrary window。
- The main app does not directly know Hyperframes dependency recipes。
- GearHost owns prepare and open。

## Phase 4: Import Local Gear

Goal: support AA-style local sharing。

Deliverables:

- Add `Import Gear...` to the Gears catalog。
- Folder import。
- `.geegear.zip` import。
- Manifest validation。
- Atomic copy into Application Support。
- Same-ID conflict handling。
- Invalid package issue UI。

Acceptance:

- A valid folder import appears in the catalog。
- A valid zip import appears in the catalog。
- An invalid package does not crash and shows an issue。
- Duplicate IDs offer replace / update / cancel。

## Phase 5: Dependency Setup UX

Goal: make dependency setup trustworthy, visible, and recoverable。

Deliverables:

- Setup details sheet。
- Global environment mutation warning。
- Live setup logs。
- Retry install。
- Manual setup message for unsupported installers。
- Per-gear setup snapshot persistence。

Acceptance:

- Opening a dependency-missing gear changes the button to `Checking...`, then `Installing...` or `Retry`。
- Policy-blocked gear does not run setup。
- Failed setup only affects that gear。
- Logs are saved under `gear-data/<gear-id>/logs/`。

## Phase 6: External Process And WebView Entry

Goal: make third-party gears usable without dynamic Swift loading。

Deliverables:

- `external_process` adapter。
- `webview` adapter for local files。
- Process lifecycle supervision。
- Timeout and stop behavior。
- stdout / stderr logs。
- Startup health protocol。

Acceptance:

- A sample AA gear can be copied or imported and opened。
- Process exit is surfaced as gear launch failure。
- V1 WebView gear loads only local package files。

## Phase 7: Agent Control Bridge

Goal: expose ready gear capabilities through one bridge。

Deliverables:

- GearHost provides ready and policy-allowed capability list。
- `gear.invoke` adapter surface plus the SDK `gee` MCP bridge tools。
- Initial `media.library` capability execution。
- Same-run pause / execute / resume continuation between the SDK runtime and GeeAgentMac host actions。

Acceptance:

- Agent sees only ready and policy-allowed capabilities。
- Policy-blocked, failed, installing, or invalid gears are invisible to the agent。
- No gear-specific pseudo-tools are added。
- Missing MCP bridge tools or invalid Gear arguments fail explicitly; GeeAgent does not use fallback task execution to hide runtime issues。

## Quality Gates

Every phase must satisfy:

- `swift build` passes in `apps/macos-app`。
- Gears catalog still opens。
- Missing gear does not break main app startup。
- Invalid `gear.json` appears as an install issue。
- Policy-blocked gear does not run dependency setup。
- Policy-blocked gear does not expose capabilities。
- Gear-specific data does not enter `WorkbenchStore`。
- Gear UI follows native macOS experience。
- Public docs are updated in English, Simplified Chinese, and Japanese。
- Gear capability changes check the Codex plugin projection and update export metadata、MCP schema、generated skills、or plugin metadata when needed。

Package and import phases must also satisfy:

- Path traversal is rejected。
- Folder name must match manifest id。
- Duplicate ID has explicit user choice。
- Import is atomic or rolls back cleanly。
- Dependency failure has per-gear logs。

## Non-Goals For V1

V1 does not include:

- Remote marketplace。
- Payments, ratings, reviews。
- Mandatory developer signing。
- Automatic remote update。
- Cross-gear private API。
- Background daemons。
- Dynamic Swift source loading from user-copied folders。
- One agent tool per gear feature。
- Silent dependency installation at app startup。

## Developer Workflow

Recommended local gear development flow:

- Create a `<gear-id>/` folder。
- Add `gear.json`。
- Add `README.md`。
- Add `assets/`, `setup/`, `scripts/`, `src/`, or `app/`。
- Declare entry, permissions, dependencies, and agent capabilities。
- During development, place it under `apps/macos-app/Gears/<gear-id>/`。
- For distribution, package it as a folder or `.geegear.zip`。
- The user copies it to `~/Library/Application Support/GeeAgent/gears/<gear-id>/` or imports it through `Import Gear...`。
- GearHost scan makes it appear in the Gears catalog。
- Opening or enabling it runs dependency preflight。
- Once ready, it opens an app window or renders a Home widget。

Minimal shareable package:

```text
aa.cool.gear/
├── gear.json
├── README.md
├── assets/
│   └── icon.png
├── scripts/
│   └── start.sh
└── app/
    └── index.html
```

Minimal `.geegear.zip` should extract into one top-level folder:

```text
aa.cool.gear.geegear.zip
└── aa.cool.gear/
    ├── gear.json
    └── README.md
```

## Immediate Recommendation

Start with Phase 1 and Phase 2。

Do not start with marketplace, signing, remote update, or the full agent bridge. The most valuable next step is to make the local module boundary real:

- Extract `GearKit` and `GearHost` directories。
- Move bundled gear packages to `apps/macos-app/Gears`。
- Centralize native and widget adapter registration in GearHost。
- Keep current user behavior unchanged while making the package boundary explicit。

This gives GeeAgent a credible platform base without overbuilding the ecosystem: gears become independent, optional, manageable, copy-installable, and ready for future agent control。
