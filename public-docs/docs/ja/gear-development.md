# Gear 開発

## 状態と日付

文書日付：2026-04-27。

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
├── smartyt.media/
├── twitter.capture/
├── bookmark.vault/
├── btc.price/
└── system.monitor/
```

現在の first-party native gear implementations はまだ host によって compile されている:

```text
apps/macos-app/Sources/GeeAgentMac/Modules/MediaLibrary/
apps/macos-app/Sources/GeeAgentMac/Modules/HyperframesStudio/
apps/macos-app/Sources/GeeAgentMac/Modules/SmartYTMedia/
apps/macos-app/Sources/GeeAgentMac/Modules/TwitterCapture/
apps/macos-app/Sources/GeeAgentMac/Modules/BookmarkVault/
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
- `gee.app.openSurface`、progressive Gear capability disclosure、shared Gear invocation の first V1 host bridge surface がある。
- `bookmark.vault` は現在の first-party Gear app である。任意の text または URL を `gear-data/bookmark.vault` に保存し、media URL は `smartyt.media` と同じ `yt-dlp` metadata family で enrich する。Twitter/X tweet URL は embed metadata path を先に使い、その他の site は basic web metadata fetch に fallback する。
- full SDK/MCP tool exposure が完了するまでの transition path として、`host_action_intents` が first-party runtime turn から native Gear actions を GeeAgentMac に渡し、順番に適用できる。
- `btc.price` と `system.monitor` は Home widgets の方向として存在する。

現在の gaps:

- first-party gear business logic はまだ main app source tree の中にある。
- Gear package folders はまだ full implementation boundary ではない。
- third-party gear import はまだ実装されていない。
- every Gear capability に対する full agent-runtime SDK/MCP tool injection はまだ完了していない。
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

## Agent Control Bridge

Gear は full agent protocol を定義しない。agent runtime が control protocol、permission semantics、run events、approval flow、continuation semantics を所有する。

Current V1 implements the first native Gee host bridge surface:

- `gee.app.openSurface` opens a Gee surface or Gear window by id, such as `media.library`。
- `gee.gear.listCapabilities` progressively discloses enabled Gear capabilities。
- `gee.gear.invoke` invokes one declared Gear capability through the shared host bridge。
- phase-2 SDK runtime は active agent に対して、`gee` MCP bridge tools の `app_open_surface`、`gear_list_capabilities`、`gear_invoke` としてこれらの controls を公開します。
- MCP Gear tools は same SDK run を pause し、`host_action_intents` を emit し、GeeAgentMac に native Gear action を実行させ、その structured host results で same run を resume します。Agent が結果を inspect した後に別の Gear step が必要なら、同じ pause / execute / resume loop を繰り返します。
- SDK session が `gee` MCP tools を公開していない場合、agent は source code を調べたり、shell で product internal command を探したり、bridge が unavailable だと主張したりしてはいけない。代わりに generic `<gee-host-actions>` fallback directive を使う。この directive は同じ三つの bridge operations を使い、run を pause して GeeAgentMac host execution に渡す。
- `host_action_intents` also allow a runtime turn to return native actions that GeeAgentMac applies in order。This shortcut path is only for simple deterministic first-party Gear requests, such as asking the media library to show only video files。Complex capture or multi-Gear requests should use the agent-planned MCP bridge。
- During this transition, direct first-party media-library requests can route English and Chinese video、image、all-files、starred、and extension-specific filters such as PNG into `media.filter` instead of entering the coding loop。
- `media.filter` で設定された media-library filters は native UI の active filters として表示されます。User は `All` または `Clear filters` から full media view に戻れます。
- `media.filter`、`media.focus_folder`、`media.import_files` require an authorized media library。Media Gear should first try to restore saved macOS security-scoped access。If access is missing or stale, it must return a structured failure with `code: "gear.media.authorization_required"` and a `navigate.module` intent for `media.library` instead of reporting a misleading success。
- Runtime turns must persist tool-use and tool-result events incrementally as they arrive。GeeAgentMac should be able to refresh the active Chat transcript while a Gear workflow is still running, so users see each bridge call appear step by step instead of receiving several completed tool cards only after the final reply。

Gear の実行結果は structured data であり、final prose ではありません。Gear capability、native adapter、または transition router は state changes、counts、artifacts、warnings、errors を返せますが、ユーザーに表示する最終完了文を hardcode してはいけません。1 turn 内のすべての Gear actions が完了した後、GeeAgent は structured results を active agent/LLM に戻し、agent が結果とユーザーの言語に合わせて最終返信を生成します。LLM continuation が実行できない場合、GeeAgent は fake hardcoded success message ではなく、明確な pending または failure state を表示するべきです。

Native host が Gear action を完了したら、短い summary と bounded な `result_json` payload を continuation turn に返せます。summary は quick display 用であり、`result_json` が task id、paths、counts、artifacts、captured records、structured errors の source of truth です。大きな結果 payload は agent context に大量投入せず、Gear data directory に保存して path で参照するべきです。

Complex Gear work must be agent-planned, not router-planned。Local Gear capabilities should be decomposed into small tool primitives such as save bookmark、fetch tweet、sniff media、download media、import files、and attach local paths。The active agent should create a plan, invoke one primitive, inspect the structured result, and then choose the next primitive。Local routers and `host_action_intents` must not pre-build a full multi-step workflow such as “capture Tweet, discover media, download video, import to Media Library, and update Bookmark” because that prevents result-driven correction。

Progressive disclosure is required。The agent should first request `detail: "summary"`、then request `detail: "capabilities"` for one `gear_id`、then request `detail: "schema"` for one `capability_id` before invoking。GeeAgent should not dump every Gear capability schema into the model context by default。

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

Current SDK fallback directive shape:

```xml
<gee-host-actions>{"actions":[{"tool_id":"gee.gear.invoke","arguments":{"gear_id":"media.library","capability_id":"media.filter","args":{"kind":"video"}}}]}</gee-host-actions>
```

Fallback directive rules:

- Allowed `tool_id` values are `gee.app.openSurface`, `gee.gear.listCapabilities`, and `gee.gear.invoke`。
- The directive is a transport fallback for the shared Gear bridge, not a Gear-specific workaround。
- The agent should emit one bounded directive, wait for structured host results, then continue planning from those results。
- The final user-facing reply is still generated by the active agent/LLM after execution, not by the directive parser, Gear adapter, or local router。
- App restart 後に残った pending host actions は structured failure result として expire し、自動 replay してはいけません。これにより download、capture、import、bookmark write などの side effect が重複実行されることを防ぎます。

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
- Agent capabilities include `media.filter`, `media.focus_folder`, and `media.import_files`。`media.import_files` は local media paths を authorized media library に import し、可能な場合は saved access を restore し、multi-Gear workflows が続けて使える imported item paths を返し、requested source files が見つからない場合は `missing_paths` で報告する。Authorization が missing の場合、readable paths を `pending_paths` として保持し、Media Library surface を開き、active agent/LLM が説明できる structured failure を返す。

`hyperframes.studio`:

- Target: creative gear requiring Node, npm, Hyperframes, FFmpeg, and FFprobe。
- Must use dependency preflight and setup snapshots。
- Dependency failure affects only Hyperframes。
- Business logic and project data must not enter the main app store。

`smartyt.media`:

- Target: native URL media acquisition gear adapted from the SmartYT reference project。
- The Gear accepts a URL, sniffs media metadata, downloads audio or video, and extracts transcript text。
- V1 uses `yt-dlp` for metadata, downloads, and subtitle extraction, and `ffmpeg` / `ffprobe` for media conversion support。
- Transcript extraction should prefer platform subtitles first。If no subtitle is available, the Gear may fall back to local speech tooling such as Whisper when installed。If no speech backend is available, the Gear must return a structured failure that explains the missing transcription backend instead of pretending the conversion completed。
- Job state belongs in `~/Library/Application Support/GeeAgent/gear-data/smartyt.media/`, while downloaded media, extracted subtitles, and transcript text default to `~/Downloads/SmartYT/<job-id>/` unless an agent call provides an explicit `output_dir`。
- Agent capabilities are `smartyt.sniff`, `smartyt.download`, `smartyt.download_now`, and `smartyt.transcribe`。`smartyt.download` は app UI 向けに queue し、`smartyt.download_now` は artifacts が生成されるまで待って `output_paths` を返す。The active agent/LLM owns the final user-facing reply。

`twitter.capture`:

- Target: Workbench reference project の Twikit capture flow から adapted した native Twitter/X content capture gear。
- Gear は single Tweet URL、List URL plus limit、または username / profile URL plus limit を受け取る。
- V1 は `apps/macos-app/Gears/twitter.capture/scripts/` にある package-local Python sidecar と `twikit` library を使う。Sidecar は user-provided authenticated Twitter/X cookie JSON file を必要とし、GeeAgent は credentials を bundle しない。
- Task state と captured results は `~/Library/Application Support/GeeAgent/gear-data/twitter.capture/tasks/<task-id>/task.json` に保存する。
- Captured tweet records には ids、URLs、author handles、text、language、counts、timestamps、reply / retweet flags、利用可能な場合は normalized media metadata が含まれる。
- Agent capabilities are `twitter.fetch_tweet`, `twitter.fetch_list`, and `twitter.fetch_user`。Each capability creates a Gear task, stores the result in the file database, and returns structured task/result data for the active agent/LLM to summarize。
- Missing cookies、expired sessions、rate limits、Twikit failures は structured task failures として返す必要がある。Gear は successful capture を fake してはいけない。

`bookmark.vault`:

- Target: universal information capture Gear。
- Gear は arbitrary raw content を保存する。Content に URL が含まれる場合、Twitter/X embed metadata、`yt-dlp` media metadata、basic web fetch の順に metadata enrichment を試みる。
- Bookmark records belong in `~/Library/Application Support/GeeAgent/gear-data/bookmark.vault/bookmarks/<bookmark-id>/bookmark.json`。
- Agent capability `bookmark.save` accepts `content` and optional `local_media_paths`。Multi-Gear workflows should pass Media Library imported item paths when related media has been downloaded and imported。

Information capture workflow:

- Pure text should go straight to `bookmark.save`。
- URL metadata capture should save through `bookmark.save`; use `twitter.capture` or `smartyt.media` only when the user asks for deeper Twitter/media content or when the URL strongly implies media acquisition。
- Twitter/X status URLs default to video acquisition unless the user explicitly asks to save metadata only or not to download media。Tweet/media details が必要な場合は `twitter.fetch_tweet` を使い、その後 `smartyt.download_now` で video acquisition を行う。
- YouTube URLs should use `smartyt.sniff` as the lightweight duration probe before default download decisions。Default download is allowed only when `duration_seconds` is below 300 seconds; longer or unknown-duration videos should be saved as metadata unless the user explicitly asks to download。
- Strong media acquisition should use `smartyt.download_now`, then `media.import_files`, then `bookmark.save` with `local_media_paths`。
- If no media library is authorized, `media.import_files` should preserve downloaded paths as `pending_paths`, open the Media Library surface, and ask the user to choose or create a library before claiming import succeeded。Bookmark Vault may still keep the downloaded paths so the workflow can resume after authorization。

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
- Generic `<gee-host-actions>` SDK fallback directive for sessions where the MCP tools are not exposed。
- Initial `media.library` capability execution。
- Same-run pause / execute / resume continuation between the SDK runtime and GeeAgentMac host actions。

Acceptance:

- Agent sees only ready and policy-allowed capabilities。
- Policy-blocked, failed, installing, or invalid gears are invisible to the agent。
- No gear-specific pseudo-tools are added。
- Fallback directives support every ready Gear through `gear_id` and `capability_id`; they must not special-case Twitter、media、bookmarks、or any other single Gear。

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
