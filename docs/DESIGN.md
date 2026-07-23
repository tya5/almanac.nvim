# almanac.nvim 設計ドキュメント (v1)

## 1. これは何か

**汎用の月グリッド・カレンダー表示UIプラグイン。** snacks.nvimの`Snacks.picker`/`Snacks.win`が「汎用の一覧UI」「汎用のウィンドウUI」を提供し、多数のプラグインがそれを土台にしているのと同じ立ち位置を、カレンダー/予定表示について担う。

- almanac.nvim自身は**データソースを一切知らない**。Outlook・Google Calendar・org-mode・ローカルの`.ics`ファイル等、何であっても「予定のリスト」を渡せれば表示できる
- [outlook.nvim](https://github.com/tya5/outlook.nvim) はこのプラグインの最初の利用者(データプロバイダ)になる想定。outlook.nvim側にカレンダーUIは実装せず、Outlook COMから取得した予定をalmanac.nvimの`Event`形式に変換して渡すだけにする

## 2. ゴールと非ゴール(v1)

**ゴール**
- 月グリッド表示(`calendar.nvim`のような伝統的なカレンダー見た目)
- 任意のデータソースから予定を受け取れる汎用API/IF(このドキュメントの核心)
- snacks.nvimの設計作法(`snacks.win`の公開API)に倣った、他プラグインが違和感なく使えるAPI

**非ゴール(v1)**
- アジェンダ(縦一覧)表示 — 将来検討。同じ`Event`データモデルの上に別レンダラとして足せる設計にはしておく
- 予定の編集・作成(read-only表示のみ。書き込みは呼び出し元プラグインの責務)
- 出欠回答・招待送信などの操作(そもそもalmanac.nvimはデータソースを知らないため対象外)
- 年表示・週表示(将来検討)

### 2.1 UI言語ポリシー

グローバルなOSSとして公開するため、**almanac.nvimが表示・生成するUI文言(ハイライトのヒント、通知、ヘルプ表示、コマンド説明等)はすべて英語**とする。日本語(または他言語)は一切使わない。例外は`almanac.Event.title`等、**呼び出し元/ユーザーが渡したコンテンツそのもの**(件名や場所などのデータ)のみで、これは元の言語のまま無変換で表示する。ドキュメント(README/DESIGN.md等)は日本語で書いてよいが、コード内の文字列リテラル(通知・プロンプト・キー説明)は英語で統一する。

## 3. 公開API

### 3.1 エントリポイント

`snacks.win`の作法(`M(opts)`/`M.new(opts)`両対応、戻り値はメソッドチェーン可能なインスタンス)に倣う。

```lua
---@overload fun(opts?: almanac.Config): almanac.Calendar
local Almanac = require("almanac")

local cal = Almanac({
  date = os.time(),        -- 初期表示月(既定: 今日)
  events = my_event_provider, -- 3.2節参照
})

cal:show()
cal:next_month()
cal:prev_month()
cal:goto(os.time({year=2026, month=8, day=1}))
cal:today()
cal:refresh()             -- 現在表示中の月についてeventsを再取得
cal:close()
cal:toggle()
cal:selected_day()        -- カーソルがある日付(epoch integer)を返す
cal:selected_events()      -- その日のEvent[]を返す
cal:on(event, cb)          -- 3.5節
cal:map(lhs, action, opts) -- 3.4節のkeysと同じ形式を後から追加登録
cal:set_position(pos)      -- "left"|"right"|"top"|"bottom"|"float" へ切り替え(4節)
cal:cycle_position()       -- left → right → top → bottom → left … と巡回切り替え
```

### 3.2 データモデルと `EventProvider`(最重要: ここがOSSとしての再利用性を決める)

```lua
---@class almanac.Event
---@field id string                 -- 呼び出し元が発行する安定ID(表示上のキー。almanacはopaqueに扱う)
---@field title string
---@field start integer              -- os.time()由来のepoch秒。文字列日付は受け付けない(タイムゾーン処理を呼び出し元に一任するための設計判断)
---@field stop integer?              -- 省略時は終日/時刻未定として扱う
---@field all_day boolean?
---@field location string?
---@field busy? "busy"|"free"|"tentative"|"out_of_office"
---@field hl_group string?           -- このイベント個別のハイライト上書き(既定は3.6節のグループ)
---@field data any?                  -- 呼び出し元専用の不透明ペイロード。selected_events()/on("select_event")でそのまま返る(例: outlook.nvimなら{entry_id=, store_id=})

---@alias almanac.EventProvider
---| almanac.Event[]                                              # 同期: 固定リスト
---| fun(range: almanac.Range, cb: fun(events: almanac.Event[]))   # 非同期: 表示範囲が変わるたびに呼ばれる

---@class almanac.Range
---@field from integer  -- 表示している月グリッドの最初の日(epoch, 前月の余白日を含む)
---@field to integer    -- 最後の日(epoch, 翌月の余白日を含む)
```

- `snacks.picker`の`finder`契約(テーブル固定 or 非同期コールバック関数のどちらでも渡せる)を踏襲。月を送る/戻るたびに`range`が変わり、`EventProvider`が関数であれば毎回呼び出される(snacksのfinderが「フィルタ変更時に再実行」される契約と同じ形)
- **日付はepoch秒(`integer`)で統一**し、ISO文字列等は受け付けない。タイムゾーン変換・"月"の境界の解釈(ローカルタイムかUTCか)は呼び出し元の責務とし、almanac.nvim自身はタイムゾーンを一切意識しない。これによりOutlook(`ReceivedTime`はPowerShell側で既にローカル`DateTime`)でもorg-mode(`os.time`ベース)でも同じ契約で渡せる
- `id`はalmanac内部では文字列キーとしてのみ扱う(重複防止・選択状態の追跡に使うのみで、意味は一切解釈しない)
- `data`フィールドが「呼び出し元の秘密の抜け道」で、outlook.nvimなら`{entry_id=, store_id=}`を積んでおき、`cal:on("select_event", function(ev) ... end)`で受け取って`get_message`を呼ぶ、という使い方を想定

### 3.3 Config

```lua
---@class almanac.Config
---@field date? integer                        -- 初期表示月(epoch)。既定: 今日
---@field events? almanac.EventProvider
---@field week_start? "sunday"|"monday"         -- 既定: "monday"
---@field position? "left"|"right"|"top"|"bottom"|"float"  -- 4節参照。既定: "left"
---@field size? number                          -- サイドバーの幅(left/right時)/高さ(top/bottom時)。既定: 30 (列) / 0.3 (行の割合)
---@field manage_position? "auto"|"always"      -- 既定"auto": edgy.nvim検出時はcycle_position()を無効化しedgy側に位置管理を譲る(6節)。"always"ならedgy有無に関わらずalmanac自前で管理
---@field wo? vim.wo|{}                          -- window-local options (snacks.win踏襲)
---@field bo? vim.bo|{}                          -- buffer-local options (snacks.win踏襲)
---@field keys? table<string, false|string|fun(self:almanac.Calendar)|{[1]:string, desc:string}>  -- 3.4節
---@field format_day? fun(self: almanac.Calendar, day: almanac.Day): string[]  -- セル内テキストのカスタマイズ
---@field on_open? fun(self: almanac.Calendar)
---@field on_close? fun(self: almanac.Calendar)
```

`wo`/`bo`/`keys`のテーブル形式・命名は`snacks.win`とできるだけ揃え、snacksに慣れたユーザーが初見で使える設計にする。

### 3.4 キーマップ

`snacks.win`の`keys`テーブル形式(文字列=アクション名 / 関数 / `{アクション名, desc=...}`)をそのまま踏襲。

```lua
keys = {
  h = "prev_day", l = "next_day", j = "next_week", k = "prev_week",
  ["<C-f>"] = "next_month", ["<C-b>"] = "prev_month",
  gt = "today",
  ["<CR>"] = "select",  -- on("select_day")/on("select_event") 発火
  ["<C-w><C-w>"] = "cycle_position", -- 4節: サイドバーの配置(左/右/上/下)を巡回切り替え
  q = "close",
}
```

既定のアクション名は`next_day`/`prev_day`/`next_week`/`prev_week`/`next_month`/`prev_month`/`today`/`select`/`close`/`toggle`/`cycle_position`。`actions`テーブルで独自アクションを追加登録可能(snacksの`actions`踏襲)。

### 3.5 イベント/フック

`snacks.win`の`:on(event, cb, opts)`をそのまま踏襲。

```lua
cal:on("month_changed", function(self, range) ... end)
cal:on("day_selected", function(self, day) ... end)
cal:on("event_selected", function(self, event) ... end) -- event.data に呼び出し元のペイロード
cal:on("position_changed", function(self, position) ... end) -- 4節: left/right/top/bottom/float切り替え時
cal:on("close", function(self) ... end)
```

### 3.6 ハイライトグループ

`Almanac`プレフィックスで登録し、`default = true`でカラースキームからの上書きを許可(outlook.nvimの`OutlookUnread`、snacksの`Snacks*`と同じ作法)。

| Group | 用途 |
|---|---|
| `AlmanacToday` | 今日のセル |
| `AlmanacWeekend` | 土日のセル |
| `AlmanacSelected` | カーソル位置 |
| `AlmanacHasEvent` | 予定がある日 |
| `AlmanacOtherMonth` | 前後月の余白セル |

すべて`vim.api.nvim_set_hl(0, name, { ..., default = true })`でリンク登録し、**ハードコードした色は使わない**(snacks.nvimの`Snacks{Level}{Icon,Border,Title}`等と同じ作法)。カラースキームが`Almanac*`をリンクし直せば即座に反映される。

### 3.7 LuaCATS型注釈

`snacks.win`同様、`---@class`/`---@field`/`---@overload`で公開APIを型注釈する。`almanac.Calendar`(インスタンス)、`almanac.Config`、`almanac.Event`、`almanac.EventProvider`、`almanac.Range`、`almanac.Day`を公開型として整備し、利用側プラグイン(outlook.nvim等)からも`---@type almanac.Event`等を参照できるようにする。

## 4. レンダリング方式: nvim-tree/neo-tree風のサイドウィンドウ

フローティングでも「現在のウィンドウのバッファ」でもなく、**エクスプローラ系プラグイン(nvim-tree, neo-tree, aerial等)と同じ「固定サイドバー」**として実装する。理由: カレンダーは他の編集中バッファを見ながら参照し続けたいことが多く(予定を横目にコードを書く、等)、フローティングは他作業を遮り、現在ウィンドウ乗っ取りは編集中バッファを退避させてしまう。サイドバーなら常駐させたまま他の作業ができる。

- **配置は4方向 + フローティングを`opts.position`(既定`"left"`)で選択可能**: `"left"`/`"right"`(垂直分割、幅は`opts.size`列)、`"top"`/`"bottom"`(水平分割、高さは`opts.size`行 or 画面比率)、`"float"`(必要なら一時的にフローティングも可、既存のoutlook.nvimでの知見同様あくまで選択肢の一つ)。
- **`cal:cycle_position()`(既定キー`<C-w><C-w>`)で実行中に配置を巡回切り替え**できる。nvim-treeの`:NvimTreeFocus`的な「常にこの位置」ではなく、垂直⇔水平を都度スイッチする使い方を想定(縦に長いウィンドウ配置の時は左右サイドバー、横長ならボトムペイン、といった切り替え)。
- ウィンドウ管理はnvim-tree同様、「同じウィンドウを使い回す」(`show()`/`toggle()`で既存のサイドバーウィンドウを再利用し、閉じるまで新規ウィンドウを増やさない)。位置変更(`set_position`/`cycle_position`)は一度閉じて指定位置に開き直す形で実装する想定(ウィンドウのその場移動APIはNeovim側に無いため)。
- サイズは固定値(`opts.size`、列数 or 行数)。ウィンドウ全体に対する追従リサイズ(vim.o.columns変化時の自動調整)は`snacks.win`の`width`/`height`が関数を受け付ける仕組み(3.3節参照)を踏襲すれば将来対応できるが、v1では固定値のみ
- グリッド再描画は月送り・`refresh()`のたびにバッファ全体を書き換える単純な方式(v1では差分更新はしない)
- セルのテキストは既定で「日付 + 予定がある場合はドット等のインジケータ」。`format_day`で完全にカスタマイズ可能

### 4.1 描画の実装技術(ネットで実現手段を調査した結果の反映)

「今どき見える」ためだけの機能追加をv1に詰め込まない(過剰実装を避ける)方針は保ちつつ、以下は"設計として決めておくべき前提"としてここに残す。

- グリッド自体は**Unicode罫線 + ハイライトグループ**で組む。ターミナルUIとして現状これに代わる標準的手法は無い(画像プロトコルは5節参照)。
- セルの「予定あり」バッジ・件数表示は`nvim_buf_set_extmark`の仮想テキスト(`virt_text`)で本体テキストに重ねる。extmarkは**バッファ単位**でありウィンドウ単位ではない点に注意(同一バッファを複数ウィンドウに同時表示しない設計 = 4節の「サイドバーを使い回す」方針と両立する)。
- ウィンドウごとの見た目の独立性(サイドバー用パレットを他ウィンドウから隔離する等)が要る場合は、古い`winhighlight`ではなく**`nvim_win_set_hl_ns()`**(ハイライト名前空間ごとウィンドウに適用)を使う。v1で必須ではないが、将来「サイドバー全体だけ少し暗くする」等をやる時の実装先として記録しておく。
- アイコン(予定の種類分けなど)を使う場合は、決め打ちの絵文字/グリフではなく**アイコンプロバイダ抽象化**(`nvim-web-devicons`または`mini.icons`。存在すれば使い、無ければプレーンテキストにフォールバック)を経由する。outlook.nvimの`OutlookUnread`ハイライト設計と同じ「無ければ劣化するが壊れない」思想。
- 月送りアニメーション等の**モーションはv1では実装しない**。ただし`snacks.nvim`が入っていれば`Snacks.animate`に乗せて将来追加できる程度の余地は意識しておく(無ければ即時切り替えにフォールバックする設計を崩さない)。
- 画像プロトコル(kitty graphics/Sixel, `image.nvim`)は採用しない。対応端末が限定的でパフォーマンスも不安定、かつカレンダー/アジェンダ系プラグインでの採用実績も無い。テキスト+extmark+ハイライトの方が可搬性が高く用途にも合う。

## 5. outlook.nvimとの接続(将来作業、このリポジトリでは実装しない)

outlook.nvim側に`lua/outlook/calendar.lua`を追加し、
1. Outlook COMの`list_events`(新規PSメソッド、`GetDefaultFolder(olFolderCalendar)` + `Restrict`で日付範囲フィルタ)を呼び、
2. 結果を`almanac.Event`形式(`start`/`stop`をepochに変換、`data = {entry_id=, store_id=}`)に変換し、
3. `require("almanac")({ events = function(range, cb) ... end })`として起動する

という薄い変換層になる想定。almanac.nvim自体はこの接続作業を待たずに単体で開発・公開できる。

## 6. エコシステム連携(調査結果)

- **`folke/edgy.nvim`**(サイドバー統括管理プラグイン)は**LazyVim公式extra**(`lazyvim.plugins.extras.ui.edgy`、`:LazyExtras`で有効化)として配布されており、neo-tree/Trouble/help/noice/grug-far等を最初から`left`/`right`/`bottom`エッジバーに登録して協調管理している。LazyVimユーザーにとって「サイドバー的なUI」の事実上の標準的な受け皿であるため、**再発明を避けて積極的に連携する**方針に変更(調査前は「オプトインの飾り」程度の位置づけだったが、実態を踏まえて格上げ)。
  - almanac自体は引き続きedgy.nvimに**ハード依存はしない**(edgy未導入でも単体で動く必要があるため)。サイドバーバッファに一貫した`filetype = "almanac"`を付けておくだけで、edgy側の`ft`/`filter`によるウィンドウ自動収集の仕組みに乗る
  - READMEに「edgy.nvim(LazyVimの`:LazyExtras` → ui.edgy)ユーザー向けスタンザ例」を明記する: `opts.left`(or `right`)に`{ ft = "almanac", title = "Calendar", size = { width = 30 }, pinned = true }`を1つ足すだけで、他の既存サイドバー(neo-tree等)と自動的にリサイズ・協調配置される
  - **棲み分け**: edgy.nvimが検出された場合(`pcall(require, "edgy")`)、almanac自身の`cycle_position()`(位置巡回切り替え)は既定で無効化し、位置管理をedgy側に譲る(`opts.manage_position = "auto"`が既定。`"always"`にすればedgy有無に関わらずalmanac自前の位置切り替えを使い続けられる)。両者が同時に同じウィンドウを動かそうとして競合するのを避けるための設計
- **アイコンプロバイダ**(`nvim-web-devicons`/`mini.icons`)も同様にハード依存せず、`pcall(require, ...)`で存在確認して使う/使わないをフォールバックする(outlook.nvimの`snacks.nvim`有無判定と同じ作法)
- **`mini.calendar`は存在しない**ことを確認済み(2026年時点)。カレンダーグリッドUIの強い先行実装は無く、almanac.nvimが埋める空き地になっている
- 参考にした/差別化した先行事例: `wsdjeg/calendar.nvim`(月グリッド+データソース拡張登録という発想の先例だが、ハイライトはリンク済みで悪くない一方UI自体の作り込みは薄い。almanacは同種のデータ抽象化をしつつUIの質で差別化する)

## 7. 段階的ロードマップ

- **v1**: 月グリッド表示、静的/非同期`EventProvider`、キーマップ・ハイライトのカスタマイズ、`snacks.win`踏襲のLuaCATS型注釈、サイドバー配置切り替え(left/right/top/bottom/float)
- **v2**: アジェンダ(縦一覧)レンダラを同じ`Event`データモデルの上に追加
- **v3**: 週表示・年表示
