# almanac.nvim 設計ドキュメント (v1)

## 1. これは何か

**汎用のカレンダー/予定表示UIプラグイン。** 月・週・日の3ビューを切り替えられる。snacks.nvimの`Snacks.picker`/`Snacks.win`が「汎用の一覧UI」「汎用のウィンドウUI」を提供し、多数のプラグインがそれを土台にしているのと同じ立ち位置を、カレンダー/予定表示について担う。

- almanac.nvim自身は**データソースを一切知らない**。Outlook・Google Calendar・org-mode・ローカルの`.ics`ファイル等、何であっても「予定のリスト」を渡せれば表示できる
- [outlook.nvim](https://github.com/tya5/outlook.nvim) はこのプラグインの最初の利用者(データプロバイダ)になる想定。outlook.nvim側にカレンダーUIは実装せず、Outlook COMから取得した予定をalmanac.nvimの`Event`形式に変換して渡すだけにする

## 2. ゴールと非ゴール(v1)

**ゴール**
- **月・週・日の3ビュー**表示、キー1つで切り替え可能(`gm`/`gw`/`gd`、`cycle_view()`)。3ビューとも同じ`Event`データモデル・同じ`EventProvider`の上に別レンダラとして実装する(3.8節)
- 任意のデータソースから予定を受け取れる汎用API/IF(このドキュメントの核心)
- snacks.nvimの設計作法(`snacks.win`の公開API)に倣った、他プラグインが違和感なく使えるAPI

**非ゴール(v1)**
- 予定の編集・作成(read-only表示のみ。書き込みは呼び出し元プラグインの責務)
- 出欠回答・招待送信などの操作(そもそもalmanac.nvimはデータソースを知らないため対象外)
- 年表示(将来検討)

### 2.1 UI言語ポリシー

グローバルなOSSとして公開するため、**almanac.nvimが表示・生成するUI文言(ハイライトのヒント、通知、ヘルプ表示、コマンド説明等)はすべて英語**とする。日本語(または他言語)は一切使わない。例外は`almanac.Event.title`等、**呼び出し元/ユーザーが渡したコンテンツそのもの**(件名や場所などのデータ)のみで、これは元の言語のまま無変換で表示する。ドキュメント(README/DESIGN.md等)は日本語で書いてよいが、コード内の文字列リテラル(通知・プロンプト・キー説明)は英語で統一する。

## 3. 公開API

### 3.1 エントリポイント

`snacks.win`の作法(`M(opts)`/`M.new(opts)`両対応、戻り値はメソッドチェーン可能なインスタンス)に倣う。

```lua
---@overload fun(opts?: almanac.Config): almanac.Calendar
local Almanac = require("almanac")

local cal = Almanac({
  date = os.time(),        -- 初期表示日(既定: 今日)
  view = "month",          -- "month"|"week"|"day"(既定: "month")
  events = my_event_provider, -- 3.2節参照
})

cal:show()
cal:next()        cal:prev()          -- 現在のビュー単位でページ送り(month→月送り, week→週送り, day→日送り。既定キー<C-f>/<C-b>。3.4節)
cal:next_day()    cal:prev_day()      -- フォーカス移動(日単位)。ビューに関わらず同じ意味
cal:next_week()   cal:prev_week()    -- フォーカス移動(週単位)
cal:next_month()  cal:prev_month()   -- 直接月送り(ビューに関わらず月送り。next()の内部実装、独立にも呼べる)
cal:move_down()   cal:move_up()      -- フォーカスを次/前の**実際に描画されている行**(グリッド行/アジェンダ日ラベル/予定行)へ移動。描画範囲の端まで来た時だけpage送り(3.4節)
cal:move_left()   cal:move_right()   -- 現在の行のセル間で移動(monthビューのグリッド)。1行1項目のビューではno-op
cal:next_event()  cal:prev_event()   -- 現在描画されている範囲内の予定行だけを直接飛び越えて移動(page送りしない。端で折り返す)
cal:goto_date(os.time({year=2026, month=8, day=1}))
cal:today()
cal:refresh()             -- 現在の表示範囲(view依存)についてeventsを再取得
cal:close()
cal:toggle()
cal:set_view("week")       -- "month"|"week"|"day" へ切り替え(3.8節)
cal:cycle_view()           -- month → week → day → month … と巡回切り替え(既定キー: 3.4節)
cal:selected_day()        -- フォーカスしている日付(epoch integer)を返す
cal:selected_events()      -- その日のEvent[]を返す
cal:focused_event()        -- フォーカスが予定行に乗っている場合そのEventを返す(日/セルならnil)
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
---@field from integer  -- 表示範囲の最初の日(epoch)。monthビューなら月グリッドの前月余白日を含む、weekビューならその週の月曜(week_start依存)、dayビューならその日0時
---@field to integer    -- 表示範囲の最後の日(epoch)。monthビューは翌月余白日を含む、weekビューはその週の日曜、dayビューはその日
```

- `snacks.picker`の`finder`契約(テーブル固定 or 非同期コールバック関数のどちらでも渡せる)を踏襲。月/週/日を送る・ビューを切り替えるたびに`range`が変わり、`EventProvider`が関数であれば毎回呼び出される(snacksのfinderが「フィルタ変更時に再実行」される契約と同じ形)。**`range`の粒度は現在のビューに依存する**(3.8節) — 呼び出し元は`view`を意識せず「この期間のイベントをくれ」とだけ実装すればよく、月/週/日の切り替えロジックはalmanac側に閉じる
- **日付はepoch秒(`integer`)で統一**し、ISO文字列等は受け付けない。タイムゾーン変換・"月"の境界の解釈(ローカルタイムかUTCか)は呼び出し元の責務とし、almanac.nvim自身はタイムゾーンを一切意識しない。これによりOutlook(`ReceivedTime`はPowerShell側で既にローカル`DateTime`)でもorg-mode(`os.time`ベース)でも同じ契約で渡せる
- `id`はalmanac内部では文字列キーとしてのみ扱う(重複防止・選択状態の追跡に使うのみで、意味は一切解釈しない)
- `data`フィールドが「呼び出し元の秘密の抜け道」で、outlook.nvimなら`{entry_id=, store_id=}`を積んでおき、`cal:on("select_event", function(ev) ... end)`で受け取って`get_message`を呼ぶ、という使い方を想定

### 3.3 Config

```lua
---@class almanac.Config
---@field date? integer                        -- 初期表示日(epoch)。既定: 今日
---@field view? "month"|"week"|"day"            -- 既定: "month"(3.8節)
---@field events? almanac.EventProvider
---@field week_start? "sunday"|"monday"         -- 既定: "monday"
---@field position? "left"|"right"|"top"|"bottom"|"float"  -- 4節参照。既定: "left"
---@field size? number                          -- サイドバーの幅(left/right時)/高さ(top/bottom時)。既定: 30 (列) / 0.3 (行の割合)
---@field manage_position? "auto"|"always"      -- 既定"auto": edgy.nvim検出時はcycle_position()を無効化しedgy側に位置管理を譲る(6節)。"always"ならedgy有無に関わらずalmanac自前で管理
---@field wo? vim.wo|{}                          -- window-local options (snacks.win踏襲)
---@field bo? vim.bo|{}                          -- buffer-local options (snacks.win踏襲)
---@field keys? table<string, false|string|fun(self:almanac.Calendar)|{[1]:string, desc:string}>  -- 3.4節
---@field on_open? fun(self: almanac.Calendar)
---@field on_close? fun(self: almanac.Calendar)
```

`wo`/`bo`/`keys`のテーブル形式・命名は`snacks.win`とできるだけ揃え、snacksに慣れたユーザーが初見で使える設計にする。

### 3.4 キーマップ

`snacks.win`の`keys`テーブル形式(文字列=アクション名 / 関数 / `{アクション名, desc=...}`)をそのまま踏襲。

```lua
keys = {
  -- スクリーン駆動のフォーカス移動: どのキーも「今カーソルがある場所から
  -- 見て、画面上ですぐ隣にある行・セル(=line_mapに載っている行)」へ
  -- 移動するだけで、日付を先に足し算/引き算してから画面上の位置を
  -- 逆算する、という順序には**しない**。ユーザーはUIを見ながら操作する
  -- ため、キー1つの移動先は常に「今実際に描画されているもの」から
  -- 決まるべき、というフィードバックにより設計を修正した経緯がある
  -- (最初は月ビュー週送り/週・日ビュー日送りのような固定の日付演算を
  -- 主役に据えた設計を提案したが、「四則演算はそっちの都合を押し付ける
  -- な」と却下された)。日付演算(next_day/next_week等)は、
  -- 画面に描画されている範囲の端まで移動が行き着いた時だけ発動する
  -- 裏方のページ送りフォールバックに格下げされている。
  --  h/l(左右): 現在の行のセル間移動(monthビューのグリッド行のみ意味を
  --  持つ)。1行1項目のビュー(week/day)ではセルが無いのでno-op。
  --  j/k(下/上): line_map上で次/前に実際に描画されている行(グリッド行/
  --  アジェンダの日ラベル行/予定行)へ移動するだけ。monthビューのグリッド
  --  行は、そのままアジェンダの予定行へ「降りて」いける(別扱いしない)。
  --  week/dayビューは日ラベル行と予定行が混在した縦リストを1行ずつ辿るため、
  --  予定にも自然に止まる。**今描画されている範囲の一番下/上まで来て次に
  --  動く行が無い時だけ**、初めてページ送り(next()/prev())する。
  h = "move_left", l = "move_right", j = "move_down", k = "move_up",
  -- 現在描画されている範囲内の予定行だけを直接飛び越えて次/前に移動
  -- (端で折り返す。ページ送りはしない)。
  ["]e"] = "next_event", ["[e"] = "prev_event",
  -- ページ送り(現在のビュー単位。monthなら月送り、weekなら週送り、dayなら日送り)。
  -- next_month/next_week/next_day のように粒度ごとに別キーを用意せず、
  -- 「ビューが変われば送る単位も変わる」1組のキーに統一する設計(ユーザーからのフィードバックで
  -- 粒度別バインドは使いづらいと判断し、統一した)。
  ["<C-f>"] = "next", ["<C-b>"] = "prev",
  gt = "today",
  gm = "view_month", gw = "view_week", gd = "view_day", -- 3.8節: g+ニーモニックでビュー直接切り替え(gg/gt等のVim慣習に倣う)
  ["<Tab>"] = "cycle_view", -- month → week → day → month … と巡回切り替え
  ["<CR>"] = "select",  -- on("day_selected")/on("event_selected") 発火
  ["<C-w><C-w>"] = "cycle_position", -- 4節: サイドバーの配置(左/右/上/下)を巡回切り替え
  q = "close",
}
```

既定のアクション名は`next_day`/`prev_day`/`next_week`/`prev_week`/`next_month`/`prev_month`/`next`/`prev`/`move_down`/`move_up`/`move_left`/`move_right`/`next_event`/`prev_event`/`today`/`view_month`/`view_week`/`view_day`/`cycle_view`/`select`/`close`/`toggle`/`cycle_position`。`next`/`prev`は`next_month`等と違い**現在の`self.view`を見て粒度を呼び分ける**薄いディスパッチ(3.1節)、`next_day`等は日付演算そのもの(page送りのフォールバック実装として内部でも使われるが、独立したアクション名としても呼べる)。`move_down`等は日付演算を一切呼ばず`self._line_map`だけを見て動くスクリーン駆動の移動で、描画範囲の端まで来た時だけ`next()`/`prev()`にフォールバックする。`actions`テーブルで独自アクションを追加登録可能(snacksの`actions`踏襲)。

**用語**: `self.date`(=「フォーカスしている日」)と`self._focused_event`(=フォーカスが予定行に乗っている時のその予定、`focused_event()`で取得可能)がこのプラグインの状態の中心概念で、`move_down`/`next_day`等はすべて**フォーカスを移動する**操作。Vimの実カーソル(点滅する位置)は`_sync_cursor_to_date()`によってフォーカスに追従させているだけの表示上の同期先であり、「カーソル移動」と呼ぶとこの2つが混同されるため、以後「フォーカス移動」と呼ぶ。

### 3.5 イベント/フック

`snacks.win`の`:on(event, cb, opts)`をそのまま踏襲。

```lua
cal:on("range_changed", function(self, range) ... end)  -- 月送り/週送り/日送り/ビュー切り替え、いずれでも range が変われば発火
cal:on("view_changed", function(self, view) ... end)      -- "month"|"week"|"day"
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
| `AlmanacHasEvent` | 予定がある日(month/weekビューのドット等) |
| `AlmanacOtherMonth` | 前後月の余白セル(monthビュー) |
| `AlmanacWeekdayLabel` | weekビューの曜日ラベル行(today/selected/weekendのいずれでもない場合の既定色。`AlmanacEventTitle`とは別グループにして予定行と混同しないようにする) |
| `AlmanacEventTitle` | イベント名(week/dayビューの一覧行) |
| `AlmanacEventTime` | イベントの時刻表示 |
| `AlmanacTimeAxis` | dayビューの時間軸(罫線・時刻ラベル) |
| `AlmanacHeader` | ヘッダ行(`« August 2026 »`等)・`[Month]`/`[Week]`/`[Day]`表示 |

すべて`vim.api.nvim_set_hl(0, name, { ..., default = true })`でリンク登録し、**ハードコードした色は使わない**(snacks.nvimの`Snacks{Level}{Icon,Border,Title}`等と同じ作法)。カラースキームが`Almanac*`をリンクし直せば即座に反映される。

### 3.7 LuaCATS型注釈

`snacks.win`同様、`---@class`/`---@field`/`---@overload`で公開APIを型注釈する。`almanac.Calendar`(インスタンス)、`almanac.Config`、`almanac.Event`、`almanac.EventProvider`、`almanac.Range`、`almanac.Day`を公開型として整備し、利用側プラグイン(outlook.nvim等)からも`---@type almanac.Event`等を参照できるようにする。

### 3.8 月/週/日ビューのレンダリング仕様

3ビューとも同じ`Event`データモデル・同じ`EventProvider`契約(3.2節)を共有する、単なる「レンダラの差し替え」として実装する(`lua/almanac/render/{month,week,day}.lua`のように分離し、共通インターフェース`render(events, range, opts) -> {lines: string[], highlights: ...}`に揃える)。

- **共通ヘッダ**: 1行目に`[Month]`/`[Week]`/`[Day]`のビュー表示、2行目に`« <期間> »`のナビゲーション行(monthなら`August 2026`、weekなら`Aug 3 – Aug 9`、dayなら`Fri, Aug 7 2026`)。書式は`AlmanacHeader`ハイライト。
- **monthビュー**: 伝統的な週×曜日グリッド(`calendar.nvim`踏襲)。1日1セル、予定は件数によらずドット(`AlmanacHasEvent`)のみ。カーソル行の下に選択日の予定を件名+開始時刻で簡潔に列挙(全件ではなく数件、詳細はweek/dayビューか呼び出し元の責務)。
- **weekビュー**: 月〜日(`week_start`依存)を縦に7行、各曜日の下にその日の予定を時刻+件名で列挙するアジェンダ形式。予定が無い日は曜日行のみ。曜日ラベルは`Mon 3`/`Wed 22`のように**3文字略称+2桁固定幅の日付**で統一し(フルスペル`Monday`/`Wednesday`だと長さがバラついて縦に並べた時にガタつくため)、`AlmanacWeekdayLabel`ハイライトで予定行(`AlmanacEventTitle`)とは別の色になるようにする。
- **dayビュー**: 選択日の時間軸(1時間刻みの罫線、0-23時固定)を縦に描画し、予定をその時間帯に挿入する形で表示。`location`等の付加情報も表示。
- ビュー切り替え(`set_view`/`cycle_view`)時は、現在のカーソル位置の日付を保持したまま新ビューの`range`を計算し直し、必要なら`EventProvider`を再度呼ぶ(`range`が変わるため。3.2節)。

## 4. レンダリング方式: nvim-tree/neo-tree風のサイドウィンドウ

フローティングでも「現在のウィンドウのバッファ」でもなく、**エクスプローラ系プラグイン(nvim-tree, neo-tree, aerial等)と同じ「固定サイドバー」**として実装する。理由: カレンダーは他の編集中バッファを見ながら参照し続けたいことが多く(予定を横目にコードを書く、等)、フローティングは他作業を遮り、現在ウィンドウ乗っ取りは編集中バッファを退避させてしまう。サイドバーなら常駐させたまま他の作業ができる。

- **配置は4方向 + フローティングを`opts.position`(既定`"left"`)で選択可能**: `"left"`/`"right"`(垂直分割、幅は`opts.size`列)、`"top"`/`"bottom"`(水平分割、高さは`opts.size`行 or 画面比率)、`"float"`(必要なら一時的にフローティングも可、既存のoutlook.nvimでの知見同様あくまで選択肢の一つ)。
- **`cal:cycle_position()`(既定キー`<C-w><C-w>`)で実行中に配置を巡回切り替え**できる。nvim-treeの`:NvimTreeFocus`的な「常にこの位置」ではなく、垂直⇔水平を都度スイッチする使い方を想定(縦に長いウィンドウ配置の時は左右サイドバー、横長ならボトムペイン、といった切り替え)。
- ウィンドウ管理はnvim-tree同様、「同じウィンドウを使い回す」(`show()`/`toggle()`で既存のサイドバーウィンドウを再利用し、閉じるまで新規ウィンドウを増やさない)。位置変更(`set_position`/`cycle_position`)は一度閉じて指定位置に開き直す形で実装する想定(ウィンドウのその場移動APIはNeovim側に無いため)。
- サイズは固定値(`opts.size`、列数 or 行数)。ウィンドウ全体に対する追従リサイズ(vim.o.columns変化時の自動調整)は`snacks.win`の`width`/`height`が関数を受け付ける仕組み(3.3節参照)を踏襲すれば将来対応できるが、v1では固定値のみ
- グリッド再描画は月送り・`refresh()`のたびにバッファ全体を書き換える単純な方式(v1では差分更新はしない)
- セルのテキストは「日付 + 予定がある場合はドット(•)」固定(v1)。任意のテキストへのカスタマイズフックは持たない(過剰実装を避け、必要になれば`format_day`/`format_event`としてv2以降で追加検討)

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

- **v1**: 月/週/日の3ビュー表示・切り替え、静的/非同期`EventProvider`、キーマップ・ハイライトのカスタマイズ、`snacks.win`踏襲のLuaCATS型注釈、サイドバー配置切り替え(left/right/top/bottom/float)、edgy.nvim連携
- **v2**: 年表示、`format_day`/`format_event`フックによるセル・イベント表示のカスタマイズ
