# godot-dodge ― 医療職あるある版

Godot 4.6 製、横スクロールのエンドレスランナー。
プレイヤーは白衣を着た医療従事者(OT)で、日々降りかかる業務の
障害物を避け、小さなご褒美を拾いつつ「休職」を回避し続けるゲーム。

## 必要なもの

- [Godot Engine 4.6](https://godotengine.org/) 以上

## モバイル / Web 対応

- **画面タップでジャンプ**: InputMap の `jump` アクションに `InputEventScreenTouch` と `InputEventMouseButton` を追加済み。PC のキーボード(Space / ↑)操作もそのまま残っています
- **横画面専用**: `window/handheld/orientation = "landscape"`
- **stretch 設定**: `mode = canvas_items` / `aspect = keep` / `scale = 1.0` で、どんな解像度のスマホでも 16:9 を維持したままフィット(はみ出す場合は黒帯)
- **UI サイズ**: 勤続時間・診療報酬・階級ラベルを 28pt、心理的余裕ゲージを画面幅の **60%** に拡大、GameOver 画面はタイトル 40pt / 本文 24pt / ボタン 28pt に引き上げ。スマホでも読める大きさに
- **PWA (Progressive Web App) 有効**: ホーム画面追加に対応、`display=fullscreen` / `orientation=landscape`
- **Web エクスポート**: `export_presets.cfg` に "Web" プリセットを定義済み。Godot の「プロジェクト → エクスポート → Web → プロジェクトをエクスポート」で `build/web/index.html` に出力される。HTTPS サーバ必須(PWA のため)

PWA アイコン(144/180/512)は空で用意してあるので、必要なら `export_presets.cfg` の `progressive_web_app/icon_*` に画像パスを入れてください。

## 起動方法

1. Godot Engine を起動する。
2. プロジェクトマネージャで「インポート」を選び、本フォルダ内の `project.godot` を指定。
3. インポートが終わったら「編集」でエディタを開き、右上の ▶ ボタン(または F5)で実行。

初回実行時に「メインシーンが未設定」と聞かれた場合は `Main.tscn` を選んでください
(`project.godot` で設定済みなので通常は聞かれません)。

## 操作方法

| 操作 | PC | モバイル |
|---|---|---|
| ジャンプ | Space / ↑ | 画面タップ(どこでも) |
| 2段ジャンプ | 空中でもう一度 Space / ↑ | 空中でもう一度タップ |
| 復職(リトライ) | 「復職する」ボタンをクリック | ボタンをタップ |

タップ/クリックした位置に白い円のリングがポワッと広がる視覚フィードバックが出ます。

## ルール

- 勤続時間に応じて自動的にスコアが加算される(1 秒 = +10)
- 障害物に当たる → バーンアウトで倒れて休職
- 地面の穴に落ちる → 過労で休職
- コイン(ご褒美)を拾うと点数が入る
- 死亡時は約 2 秒のコミカルな死亡演出(ヒットストップ・赤フラッシュ・吹っ飛び・気絶星など)が挟まってからゲームオーバー画面に切り替わる

## 登場するコイン(ご褒美)

| 種類(type) | 見た目 | 点数 | 出現率 |
|---|---|---|---|
| 診療報酬(reward) | Kenney coinGold + 「診療報酬」 | +10 | 50% |
| お菓子(sweets) | ピンクベージュ + 茶色チップ + 「お菓子」 | +10 | 25% |
| 患者からのありがとう(thanks) | Kenney heart + 「感謝」 | +10 | 20% |
| 連休(vacation)★レア | Kenney star + 「連休」 | +100 | 5%、取得時に黄色フラッシュ演出 |

## 登場する障害物(業務)

| 種類(type) | 見た目 | 出現率 |
|---|---|---|
| お局様ナース(senior_nurse) | 女性キャラ + ピンク modulate + 「お局様」 | 20% |
| クレーム電話(complaint_call) | 黒 + 「クレーム」 | 17% |
| 緊急入院(emergency) | 赤 + 「緊急入院」、α 点滅 | 17% |
| 書類地獄(paperwork) | 木箱 3 段積み + 「書類」、縦 64 | 17% |
| ナースコール(call_bell) | 赤 + 黄色ハンドル + 「コール」、左右に微小振動 | 14% |
| カルテ地獄(medical_records) | ベージュ 32x64 + 赤背表紙 + 「カルテ地獄」、上下にゆっくり波打つ | 15% |

穴の位置には `HoleWarning` シーン(黒背景 + 工事現場風の黄色ストライプ + 赤い警告三角 + 「休職注意」赤ラベル)がスポーンされて、穴だと一目で分かるようになっています。直前の地面タイルにも警告テキストが浮きます。

穴は `MIN_TILES_AFTER_HOLE`(既定 **6 タイル**)以上の間隔を空けて配置するので、連続で穴が来てプレイ不能箇所ができることはありません。幅も 1〜2 タイルでランダムに決まり、その幅ぶんをまとめて 1 つの穴として生成 → 「幅1の穴が2つ並ぶ」ことは起きません。

## プレイヤー位置の固定とカメラ追従

プレイヤーは **画面幅 960 の 1/3 = X = 320** に毎フレーム強制スナップされます(`Player.gd` の `global_position.x = PLAYER_WORLD_X`)。レベルアップに伴う動く地面との副作用やスロープで左にじわじわ流れるのを防止しています。

カメラは **X 固定・Y はデッドゾーン方式で追従**(画面酔い対策):

- `Camera2D.position.x = 480` 固定(プレイヤーが画面左から 1/3 に見える)
- 画面中央 ±`DEADZONE_Y_HALF`(既定 120px)を **デッドゾーン(安全地帯)** として確保
- プレイヤーがデッドゾーン内にいる間は **カメラ完全静止**(普通に走ってる時は揺れない)
- プレイヤーが上端/下端を越えそうになった瞬間だけ、`lerp(cam_y, target_y, CAMERA_FOLLOW_SPEED * delta)` でじわっと追従
- `CAMERA_FOLLOW_SPEED = 8.0`(大きいほど硬く追う / 小さいほどフワッと遅れる)
- 死亡演出中は `game_active = false` + `player.is_dying` チェックで追従停止。吹っ飛びを静止カメラから見送る
- `DEBUG_MODE = true` でデッドゾーン範囲が緑枠で可視化される(`PlayUI/DebugDeadzone`)

酔う/追従が遅すぎる場合は `Main.gd` 冒頭の `DEADZONE_Y_HALF`(大=酔いにくい、小=追従早い)と `CAMERA_FOLLOW_SPEED` を調整してください。
- 死亡演出(吹っ飛び)中は `is_dying` フラグで早期 return されるためスナップされません(物理無視で飛んでいく)
- `Player.gd` の `DEBUG_POSITION` を `true` にすると 1 秒ごとに `[Player] global_position=...` を print
- `Main.gd` の `DEBUG_MODE` を `true` にするとレベルアップごとに `[LV UP] ... player_pos=...` を print

## 敵のアイドル揺れ

各障害物がその場で動いて "生きてる感" を出します(`Obstacle.gd::_apply_idle_motion`)。

| type | 動き |
|---|---|
| senior_nurse | 小刻みにプルプル震える(x: sin(t*25)*1.5 / y: sin(t*30)*0.8) |
| complaint_call | 左右にゆっくり揺れる(x: sin(t*4)*3.0) |
| emergency | 上下にフワフワ浮く(y: sin(t*3)*4.0)+ α 点滅 |
| paperwork | 縦方向にわずかに伸縮(scale.y に sin(t*5)*0.05) |
| medical_records | 上下波(y: sin(t*2.5)*2.0)+ 左右にも(x: sin(t*2)*2.0) |
| call_bell | 細かくビリビリ振動(x: sin(t*35)*2.0)+ 色が赤↔オレンジに鳴動 |

基準位置 (`_base_*`) は `_ready` 後に保存しており、スクロール(root の x)を上書きしないよう子ビジュアル側のオフセットだけを動かしています。

## 救急車風演出

障害物にぶつかって余裕が減った瞬間(耐えた場合を含む)、パトライト風の赤 3 連点滅が画面全体に被さります(`Main.gd::_play_emergency_light_flash`)。

- `Main.tscn` の `RedLightOverlay`(CanvasLayer layer=5)にある Flash ColorRect を 0 ↔ 0.6 で 0.15 秒刻みに 3 回点滅(計 ~0.9 秒)
- 連打時は古い tween を `kill()` してから仕切り直すため α が暴れない
- 死亡確定時はここを呼ばず、既存の死亡シーケンス(赤フラッシュ + ヒットストップ)に任せる
- 画面内に `emergency`(緊急入院)が 1 体でも居る間、左右の `EdgeLight`(4px 幅)がα 0.2 ↔ 0.5 の 0.4 秒サイクルで常時パルス。全部流れて居なくなると自動で停止・非表示

## 心理的余裕(Mental Reserve)システム

障害物は「即死」ではなく、「心理的余裕」というダメージバッファを削ります。

- 最大値 100 / 開始値 50、0 を下回るとバーンアウト死亡演出 → ゲームオーバー(cause=`burnout`)
- コインで回復: 診療報酬 +5 / お菓子 +10 / 感謝 +15 / 連休 +50(上限 100)
- 障害物ダメージ: お局様 -30 / クレーム -25 / 緊急入院 -20 / 書類 -15 / カルテ地獄 -15 / コール -10
- 耐えた時の演出: 小さな赤フラッシュ + プレイヤーの左右振動、当たった障害物は 0.5 秒無効化して素通り扱い
- 画面下中央にゲージ表示(80+ 青 / 50+ 緑 / 30+ 黄 / 30 未満 赤 + 点滅)
- 30 未満で 1 秒ごとに青い汗マークがプレイヤー周辺にランダム出現
- 10 未満で画面全体に薄い赤フィルタがかかって危険を示す

## 地形セクション(階段)

地面がずっと平面だと単調なので、3 種類のセクションをランダムで繋ぐ:

| type | 長さ | y 変化 |
|---|---|---|
| flat | 10〜20 タイル | 変化なし |
| stairs_up | 5〜8 タイル | 中央部で 1 タイルにつき −16px(登る) |
| stairs_down | 5〜8 タイル | 中央部で 1 タイルにつき +16px(降りる) |

- 重み抽選: flat 60% / stairs_up 20% / stairs_down 20%
- stairs_up と stairs_down が連続しないように排他制御
- 階段セクションの最初と最後は 2 タイル分「踊り場」として水平を保つ(急な変化を避ける)
- 入った瞬間に画面下部中央に「上り階段」「下り階段」の通知を 1.5 秒表示

## キャリアシステム(レベルアップ制)

勤続 30 秒ごとに階級が上がり、画面全体が黄色くフラッシュ + 中央に「昇格!  旧階級  →  新階級」の大バナー。

| Lv | 階級 |
|---|---|
| 0 | 新卒 (0-30秒) |
| 1 | 2年目 (30-60秒) |
| 2 | 3年目 |
| 3 | 中堅 |
| 4 | 主任 |
| 5 | 師長 |
| 6 | ベテラン |
| 7 | レジェンド |
| 8+ | 伝説の医療職 |

レベルが上がると難易度も連動:
- スクロール速度が `+20 px/s / Lv`(既存の障害物・地面にも即反映)
- 障害物スポーン確率が `+12% / Lv`(倍率、上限 3.0)
- コイン確率が `+5% / Lv`
- **Lv5 以降**、穴確率が `+15% / Lv` 乗算
- Lv3-5 ではプレイヤースプライトの modulate が少し暗く(疲れ気味)、Lv6 以降さらに暗く(目のクマ的表現)
- `play_levelup_sound()` は空関数として用意(将来 AudioStreamPlayer を刺せば鳴る)

画面右上に「階級: 〇〇」が常時表示されます。

## ファイル構成

```
project.godot             プロジェクト設定 (ウィンドウ 960x540 / InputMap "jump")
icon.svg                  アイコン
player_animations.tres    プレイヤーの SpriteFrames (idle/run/jump/hit)
assets/                   Kenney Platformer Characters / Deluxe の素材

Main.tscn / Main.gd       ステージ全体、スポナー、重み抽選、スコア、ゲームオーバー遷移
Player.tscn / .gd         プレイヤー(AnimatedSprite2D + OT ラベル)。重力・2段ジャンプ・死亡演出
Ground.tscn / .gd         地面タイル。左スクロール。穴直前なら警告ラベルを追加
Obstacle.tscn / .gd       障害物(Area2D)。obstacle_type で見た目と挙動が変わる
Coin.tscn / .gd           コイン(Area2D)。coin_type で見た目と得点が変わる
GameOver.tscn / .gd       休職画面。死因サブテキスト + 勤続時間/点数/連休回数 + 復職ボタン
```

## チューニング早見表

| やりたいこと | 触る場所 |
|---|---|
| 全体のスクロール速度 | `Main.gd` の `SCROLL_SPEED` |
| 重力 / ジャンプ力 | `Player.gd` の `GRAVITY` / `JUMP_VELOCITY` |
| ジャンプ回数 | `Player.gd` の `MAX_JUMPS` |
| 穴・障害物・コインの出現率 | `Main.gd` の `HOLE_CHANCE` / `OBSTACLE_CHANCE` / `COIN_CHANCE` |
| コインの種類別確率 | `Main.gd` の `COIN_WEIGHTS` |
| 障害物の種類別確率 | `Main.gd` の `OBSTACLE_WEIGHTS` |
| 1レベル上がる秒数 | `Main.gd` の `LEVEL_DURATION` |
| 階級名リスト | `Main.gd` の `LEVELS` |
| レベルごとの難易度上昇量 | `Main.gd` の `LEVEL_SCROLL_BONUS` / `LEVEL_*_CHANCE_PER_LVL` |
| 心理的余裕の初期値・上限 | `Main.gd` の `MENTAL_START` / `MENTAL_MAX` |
| コインの回復量 | `Main.gd` の `COIN_MENTAL_GAIN` |
| 障害物のダメージ量 | `Main.gd` の `OBSTACLE_DAMAGE` |
| 階段1段の高さ | `Main.gd` の `STAIRS_TILE_Y_STEP` |
| セクション長 | `Main.gd` の `*_SECTION_MIN_LEN` / `*_SECTION_MAX_LEN` |
| デバッグ出力 | `Main.gd` の `DEBUG_MODE` を true に |
| 連続で出ないための最低間隔 | `Main.gd` の `MIN_TILES_BEFORE_*` |
| 勤続時間スコアの伸び | `Main.gd` の `DISTANCE_PER_SECOND` |
| 死亡演出の長さ / ヒットストップ | `Player.gd` の `DEATH_DURATION` / `HITSTOP_*` |
| コインの色・テキスト・点数 | `Coin.gd` の `TYPE_DATA` |
| 障害物の色・テキスト・高さ | `Obstacle.gd` の `TYPE_DATA` |

## 見た目(病院テイスト化)

- **背景**: 壁はクリーム色 `#F5F0E0`、床の奥はリノリウム調の淡いグレー `#D1D1D9`
- **天井**: 画面上端 60px に薄いグレーのバーを固定(`CanvasLayer` なのでカメラシェイクの影響を受けない)。バーの下辺に 8 本の白い蛍光灯帯 (60x12, 120px 間隔) を等間隔配置
- **地面**: 病院床の中間グレー `#B3B3B8` + 上辺 2px の濃いグレーで継ぎ目の線
- **コイン**: Kenney の画像素材をそのまま使用
  - 診療報酬 → `coinGold.png`
  - 感謝 → Candy expansion の `heart.png`
  - 連休 → `star.png`(少し大きめ + 黄色modulateでキラキラ)
  - コーヒー → 画像が無いので茶色 ColorRect にクリーム色のフタ ColorRect を重ねて「マグカップ」風
- **障害物**: 一部を画像素材に差し替え
  - お局様ナース → `female_stand.png` にピンク `Color(1.2, 0.7, 0.9)` の modulate
  - 書類地獄 → `box.png` を 3 段スタック(縦64の当たり判定付き)
  - ナースコール → 赤い ColorRect に黄色いハンドル風 ColorRect を乗せる(振動は継続)
  - クレーム電話 / 緊急入院 → ColorRect のまま(緊急入院は α 点滅を継続)
- **ラベル**: すべて 18px に拡大、`StyleBoxFlat`(角丸 + 半透明黒)で読みやすく

## 実装メモ

- プレイヤーは X 方向に動かない(`velocity.x = 0`)。地面側を左に動かすことで走っているように見せている。
- 地面は `StaticBody2D` を `_physics_process` で手動移動。`CharacterBody2D.is_on_floor()` での接地判定はそのまま動く。
- 障害物・コインは `Area2D` なのでプレイヤーを物理的に押さず、`body_entered` シグナルで接触検知している。
- 「穴」は地面タイルを意図的にスポーンしない枠として表現(穴オブジェクトは存在しない)。
- 死亡演出中は `Engine.time_scale` を一時的に 0 / 0.3 / 1.0 と切り替えてヒットストップ → スロー → 通常復帰する。タイマーは `ignore_time_scale=true` を使って実時間で駆動。
- 絵文字は Godot のデフォルトフォントで豆腐化しやすいので、ラベルは日本語テキストのみで構成している(必要に応じて絵文字フォントを読み込めば追加可)。
- Coin / Obstacle は「画像スプライト + ColorRect + 装飾用 ColorRect」を同じシーンに並べておき、`_apply_type()` で `visible` を切り替えることで type ごとの見た目を出し分けている。未対応 type は ColorRect にフォールバック。
- お局様(senior_nurse)は AI 生成画像のフォールバックに対応済み。`res://assets/ai_generated/senior_nurse.png` が存在すると自動で差し替わる(無ければ Kenney の `female_stand.png` を使う)。`Obstacle.gd` の `_try_apply_ai_senior_nurse_texture` が `ResourceLoader.exists` でチェックして `load()` し、Godot セッション中 1 回だけ「`[senior_nurse] 画像読み込み: 成功/失敗`」をコンソールに出力する(spam 防止のため `static var` で制御)。詳細は同フォルダの README 参照。
- レベルアップ時には `_apply_level_effects()` が既存の子ノードを走査して `scroll_speed` を書き換えるので、既に流れてきている地面・障害物・コイン・穴警告も即座に新しい速度になる。
- プレイ中 UI (`PlayUI` CanvasLayer layer=2) とゲームオーバー (layer=10) を別レイヤーに分離した。死亡時は `play_ui.visible = false` で全プレイ中 UI を隠すため、スコアやゲージがゲームオーバー画面に重なることはない。
- 障害物に耐えた場合、Main.gd が `obstacle.monitoring = false` + `CollisionShape2D.disabled = true` で 0.5 秒無効化し、`modulate.a = 0.5` で半透明化する。既に画面外に流れていれば自動で `queue_free` されるので復帰処理は走らない。
