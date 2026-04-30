# Agent Persona

## 目的

GeeAgent は単なる汎用 agent runtime ではありません。共有 runtime の上に agent persona という製品レイヤーを持ちます。persona は agent の identity、振る舞い、視覚的な存在感、推奨または制約されるローカル能力を定義します。

persona レイヤーは runtime execution truth から分離されます。run、session、event、approval、task continuation、tool execution は phase-2 runtime spine に属します。

## 現在の状態

現在の persona system は基礎段階であり、完成した persona marketplace ではありません。

- persona definition はローカルフォルダまたは zip archive から import できます。
- import された persona はローカル persona workspace にコピーされます。
- active persona は runtime snapshot に公開されます。
- active persona は SDK system prompt に影響します。
- 明示的に追加された skill source metadata は prompt に公開できますが、完全な `SKILL.md` 本文は注入されません。
- persona tool allow-list は native runtime tool dispatcher によって強制されます。
- visual assets が存在する場合、persona visual layer は native Home surface を駆動します。

## Agent Definition v2

主要な公開形式は `Agent Definition v2` です。

必須 package 形状：

```text
agent.json
identity-prompt.md
soul.md
playbook.md
appearance/
```

任意ファイル：

```text
tools.md
memory.md
heartbeat.md
skills/
README.md
LICENSE
```

visual resources は任意です。persona は visual layer を完全に省略でき、その場合は default abstract surface に fallback します。

## Manifest Fields

`agent.json` は小さな宣言的 manifest です。長い prompt text を直接持つのではなく、ファイルを参照します。

必須 fields：

- `definition_version`：`2` でなければなりません。
- `id`：安定した persona id。
- `name`：表示名。
- `tagline`：短い要約。
- `identity_prompt_path`：identity layer への path。
- `soul_path`：voice と personality layer への path。
- `playbook_path`：behavior layer への path。
- `appearance`：任意の視覚定義。
- `source`：通常は `module_pack` または `user_created`。
- `version`：人が読める version。

一般的な任意 fields：

- `tools_context_path`
- `memory_seed_path`
- `heartbeat_path`
- `skills`
- `allowed_tool_ids`

## Layered Context

GeeAgent は persona context を次の順序で compile します。

- `identity-prompt.md`：role、responsibilities、task boundary。
- `soul.md`：personality、tone、communication posture。
- `playbook.md`：working rules、autonomy posture、escalation、approval behavior。
- `tools.md`：宣言されている場合の local tool-use hints。
- `memory.md`：宣言されている場合の initial portable memory seed。
- `heartbeat.md`：宣言されている場合の recurring behavioral guidance。

compile 結果は persona の runtime `personality_prompt` になります。

## Skill Sources

GeeAgent は、user が明示的に追加した skill folders だけを認識します。ローカルの agent skill directories 全体を自動 scan することはありません。

Settings では system-level skill source folders を追加できます。これらの sources はすべての persona に適用され、runtime が新しい snapshot または prompt を構築するときに hot update されます。

Agents detail view では persona-level skill source folders を追加できます。これらの sources はその persona にだけ適用されます。persona-level skill list は persona Reload 時に refresh されます。

skill source は、`SKILL.md` を含む単一の skill folder、または直接の child folders が `SKILL.md` を含む collection folder のどちらでもかまいません。

runtime は name、description、scope、file path などの skill metadata だけを active agent prompt に公開します。完全な `SKILL.md` contents は自動注入されません。agent が完全な instructions を必要とする場合、通常の runtime file/tool path と permission model を通じて skill file を inspect する必要があります。GeeAgent の skill metadata は SDK `Skill` tool registration ではありません。`skill_file_path` がある場合、agent は SDK skill alias を invoke せず、その file を直接 read するべきです。

skill availability は context であり、security sandbox ではありません。tool execution は引き続き GeeAgent runtime permissions、approval flow、persona `allowed_tool_ids` によって制御されます。

## Visual Layer

対応する persona visual kind：

- `live2d`：Cubism `*.model3.json` bundle descriptor を参照します。
- `video`：ローカル loop video を参照します。
- `static_image` または `image`：画像 asset を参照します。

visual layer は 3 種類すべてを同時に宣言できます。GeeAgent は次の優先順位で適用します。

- Live2D；
- video；
- image。

すべての persona visual fields が missing の場合、app は default abstract surface を使います。

Home surface では、GeeAgent は active persona 用の compact visual switcher を表示できます。対応する files が存在する visual modes だけを表示し、abstract mode は常に表示します。たとえば persona に Live2D と image assets があり video がない場合、video option は hidden になります。

abstract mode を選ぶと persona visual は非表示になり、`global_background` が設定されている場合はその背景だけが残ります。`global_background` がない場合、GeeAgent は default abstract surface を表示します。

`image` asset は image display mode のためのものです。Live2D background ではありません。

visual layer は `global_background` も宣言できます。global background は Live2D を含む persona visual の背後に full-coverage Home background として描画されます。対応する種類：

- video；
- image。

global background の優先順位は video、次に image です。

Live2D persona が `global_background` を宣言していない場合、GeeAgent は default abstract Home background の上に Live2D を描画します。

Live2D persona はローカル UI から poses、actions、expressions、viewport position、scale を扱えます。Home surface では、表示されている character をクリックすると利用可能な actions や expression changes を発火でき、local interaction layer は viewport position や scale の調整後も整合します。

## Runtime Influence

persona の影響は意図的に軽量です。

persona が影響できるもの：

- system prompt content；
- explicitly configured skill metadata；
- tool allow-list recommendations and constraints；
- visual presentation；
- local appearance interaction state。

core runtime prompt は Gee の default task boundary を所有します。Gee は default では coding-first ではありません。user が code development、bug fix、refactor、code edit を明示的に依頼しない限り、ordinary app control、file management、research、configuration requests を local project source code の変更で解決すべきではありません。この boundary は、必要な scripts、data-processing helpers、inspection utilities、一時的な automation code を implementation detail として書いて実行することを禁止しません。

persona が所有してはいけないもの：

- run lineage；
- session continuation；
- approval state；
- event truth；
- task persistence；
- provider routing truth；
- host security policy。

## Local Storage

runtime profile は GeeAgent config directory に保存されます。persona workspace はローカル `Personas` directory に保存されます。active persona id は runtime state であり、persona package 自体には含まれません。

import 後の profile files は編集可能です。Reload はローカル workspace を再読込し、runtime profile を再生成します。reload に失敗した場合、最後に有効だった profile が維持されます。

## Tool Allow-Lists

`allowed_tool_ids` は persona ごとの native runtime tools を制約できます。

field が省略された場合、persona は workspace defaults を使います。field が存在する場合、match した tools のみ許可されます。pattern は `navigate.*` のような末尾 `*` prefix match を使えます。

frontend は persona の non-Gee tool permissions を昇格できません。shell や file operations などの ordinary local tools では、native runtime が active persona を解決し、実行前に allow-list を強制します。

`gee.app.*` と `gee.gear.*` のような Gee host-managed bridge tools は first-party product controls であり、persona-owned generic tools ではありません。これらは persona allow-list filtering を bypass しますが、Gee host bridge の中で enabled gears、declared capabilities、policy state、arguments を引き続き validate します。

## Import, Reload, Delete

Import：

- package を validate する；
- package 全体を local persona workspace にコピーする；
- layered context を compile する；
- normalized runtime profile を生成する；
- desktop と CLI surfaces を refresh する。

Reload：

- local persona workspace を再読込する；
- layered context を再 compile する；
- persona-level skill source metadata を refresh する；
- validation が失敗した場合、以前に load 済みの profile を保持する。

Delete：

- local workspace を削除する；
- generated runtime profile を削除する；
- first-party persona は削除できない。

## Boundaries

persona package は宣言的です。executable scripts、native binaries、application bundles、machine-specific runtime state を含めるべきではありません。

現在の公開 docs は実装済みの foundation を説明します。persona market distribution、signing、trust metadata、automation heartbeat execution、より広い multi-profile orchestration は future work です。
