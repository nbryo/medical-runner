extends Node2D
# ============================================================
# Main.gd
# 「医療職あるある」版 エンドレスランナーの中枢。
#
# このファイルで扱うもの:
# - 地面/障害物/コインのランダム生成(重み抽選 + 最低間隔 + 穴連続防止)
# - 地形セクション(flat / stairs_up / stairs_down)による高低差
# - 心理的余裕(mental_reserve)ゲージとダメージ処理
# - キャリア(レベル)システムと難易度カーブ
# - 連休取得時の派手演出、昇格バナー、赤フラッシュ、汗マーク…
# - GameOver 画面の呼び出しと PlayUI の表示切替
# ============================================================

# --- デバッグ ---
const DEBUG_MODE: bool = false   # true にすると 1 秒ごとに Lv / Mental を print

# --- スクロール/座標 ---
const SCROLL_SPEED := 300.0
const TILE_SIZE := 64.0
const GROUND_TOP_Y := 420.0
# プレイヤーの画面内 X 座標(画面幅 960 の 1/3 = 320)。
# Player.gd の PLAYER_WORLD_X と必ず同じ値にする。
const PLAYER_X := 320.0
const SPAWN_BUFFER := 120.0
const DISTANCE_PER_SECOND := 10.0

# --- カメラ追従(デッドゾーン方式) ---
# X はワールド固定、Y はプレイヤーが画面中央 ±DEADZONE_Y_HALF の帯を
# 越えそうになったときだけ追従する。普通に走ってる間はカメラ完全静止で
# 画面酔いを防ぐ。マリオ等のプロ実装で定番の方式。
const CAMERA_FIXED_X: float = 480.0
const DEADZONE_Y_HALF: float = 120.0     # 画面中央から上下の「安全地帯」の半幅
const CAMERA_FOLLOW_SPEED: float = 8.0   # はみ出したときの追従速度(大きいほど硬く追う)

# --- 穴/障害物/コインの最低間隔と基本確率 ---
const MIN_TILES_AFTER_HOLE := 6      # 穴が終わってから次の穴が来るまでの最低タイル数(連続穴防止)
const MIN_TILES_BEFORE_OBSTACLE := 3
const MIN_TILES_BEFORE_COIN := 2
const HOLE_CHANCE := 0.10
const OBSTACLE_CHANCE := 0.18
const COIN_CHANCE := 0.28
const HOLE_MIN_WIDTH := 1
const HOLE_MAX_WIDTH := 2

# --- コイン重み ---
const COIN_WEIGHTS: Array[Dictionary] = [
	{"type": "reward",   "weight": 0.50},
	{"type": "sweets",   "weight": 0.25},
	{"type": "thanks",   "weight": 0.20},
	{"type": "vacation", "weight": 0.05},
]

# --- 障害物重み ---
const OBSTACLE_WEIGHTS: Array[Dictionary] = [
	{"type": "senior_nurse",    "weight": 0.20},
	{"type": "complaint_call",  "weight": 0.17},
	{"type": "emergency",       "weight": 0.17},
	{"type": "paperwork",       "weight": 0.17},
	{"type": "call_bell",       "weight": 0.14},
	{"type": "medical_records", "weight": 0.15},
]

# ============================================================
# 心理的余裕(Mental Reserve)システム
# ============================================================
const MENTAL_MAX: float = 100.0
const MENTAL_START: float = 50.0
const MENTAL_LOW_THRESHOLD: float = 30.0      # 以下で汗マーク + バー点滅
const MENTAL_CRITICAL_THRESHOLD: float = 10.0 # 以下で画面が赤く染まる
# MentalGauge Control 内の左右余白(2px * 2)。バー塗りの最大幅は
# mental_gauge.size.x - GAUGE_INNER_MARGIN で毎フレーム動的に求める。
const GAUGE_INNER_MARGIN: float = 4.0

# タップフィードバック用のリングスクリプト(TapRing.gd)を preload
const TAP_RING_SCRIPT := preload("res://TapRing.gd")

# コインの種類ごとの回復量
const COIN_MENTAL_GAIN: Dictionary = {
	"reward":   5.0,
	"sweets":  10.0,
	"thanks":  15.0,
	"vacation": 50.0,
}

# 障害物の種類ごとのダメージ量
const OBSTACLE_DAMAGE: Dictionary = {
	"senior_nurse":    30.0,
	"complaint_call":  25.0,
	"emergency":       20.0,
	"paperwork":       15.0,
	"medical_records": 15.0,
	"call_bell":       10.0,
}

const OBSTACLE_INVULN_DURATION: float = 0.5   # 耐えた時に障害物を無効化する時間

# ============================================================
# キャリア(階級)システム
# ============================================================
const LEVELS: Array[String] = [
	"新卒", "2年目", "3年目", "中堅", "主任",
	"師長", "ベテラン", "レジェンド", "伝説の医療職",
]
const LEVEL_DURATION := 30.0
const MAX_LEVEL := 8

const LEVEL_SCROLL_BONUS := 20.0
const LEVEL_OBSTACLE_CHANCE_PER_LVL := 0.12
const LEVEL_COIN_CHANCE_PER_LVL := 0.05
const LEVEL_HOLE_START_LVL := 5
const LEVEL_HOLE_CHANCE_PER_LVL := 0.15
const MIN_CHANCE_MULT_CLAMP := 3.0

# ============================================================
# セクション(地形)システム
# ============================================================
const SECTION_WEIGHTS: Array[Dictionary] = [
	{"type": "flat",        "weight": 0.60},
	{"type": "stairs_up",   "weight": 0.20},
	{"type": "stairs_down", "weight": 0.20},
]
const STAIRS_TILE_Y_STEP: float = 16.0        # 階段 1 段あたりの高さ差
const STAIRS_SECTION_MIN_LEN: int = 5
const STAIRS_SECTION_MAX_LEN: int = 8
const FLAT_SECTION_MIN_LEN: int = 10
const FLAT_SECTION_MAX_LEN: int = 20
const STAIRS_LANDING_TILES: int = 2           # 階段セクションの最初と最後に入れる踊り場タイル数

# --- エディタで差し替え可能なシーン参照 ---
@export var ground_scene: PackedScene
@export var obstacle_scene: PackedScene
@export var coin_scene: PackedScene
@export var game_over_scene: PackedScene
@export var hole_warning_scene: PackedScene

# --- ノード参照 ---
@onready var player: CharacterBody2D = $Player
@onready var play_ui: CanvasLayer = $PlayUI
@onready var score_label: Label = $PlayUI/ScoreLabel
@onready var coin_label: Label = $PlayUI/CoinLabel
@onready var rank_label: Label = $PlayUI/RankLabel
@onready var mental_gauge: Control = $PlayUI/MentalGauge
@onready var mental_label: Label = $PlayUI/MentalGauge/Label
@onready var mental_bar_fill: ColorRect = $PlayUI/MentalGauge/BarFill
@onready var red_tint_overlay: ColorRect = $PlayUI/RedTintOverlay
@onready var notification_label: Label = $PlayUI/Notification
@onready var edge_light_left: ColorRect = $PlayUI/EdgeLightLeft
@onready var edge_light_right: ColorRect = $PlayUI/EdgeLightRight
@onready var red_light_flash: ColorRect = $RedLightOverlay/Flash
@onready var camera: Camera2D = $Camera2D
@onready var debug_deadzone: ColorRect = $PlayUI/DebugDeadzone

# --- スコア/進行状態 ---
var distance_score: float = 0.0
var coin_score: int = 0
var vacation_count: int = 0
var game_active: bool = true

# --- レベル状態 ---
var current_level: int = 0
var level_up_timer: float = 0.0

# --- 難易度スケーリング(レベルごとに変動) ---
var current_scroll_speed: float = SCROLL_SPEED
var obstacle_chance_mult: float = 1.0
var coin_chance_mult: float = 1.0
var hole_chance_mult: float = 1.0

# --- スポナー状態 ---
var next_ground_x: float = 0.0
var tiles_since_hole_ended: int = 99
var tiles_since_obstacle: int = 99
var tiles_since_coin: int = 99
var pending_hole_tiles: int = 0

# --- セクション状態 ---
var current_section: String = "flat"
var section_tile_index: int = 0
var section_length: int = 15
var current_y_offset: float = 0.0             # ワールドの基準 Y からのずれ(階段で変動)

# --- 心理的余裕 ---
var mental_reserve: float = MENTAL_START
var _sweat_timer: float = 0.0
var _mental_blink_tween: Tween = null
var _notification_tween: Tween = null
var _debug_timer: float = 0.0

# 救急車風フラッシュ(赤3連点滅) / 画面端の emergency 警告用
var _red_light_tween: Tween = null
var _edge_light_tween: Tween = null


func _ready() -> void:
	randomize()
	player.position = Vector2(PLAYER_X, GROUND_TOP_Y - 100.0)
	player.died.connect(_on_player_died)
	player.death_started.connect(_on_player_death_started)

	# 初期セクション設定(必ず flat 長め、スタート地点を安全にする)
	current_section = "flat"
	section_length = FLAT_SECTION_MAX_LEN
	section_tile_index = 0
	current_y_offset = 0.0

	# 初期地面(画面を埋めるだけ。穴や障害物は抽選しない)
	var viewport_w := get_viewport_rect().size.x
	next_ground_x = 0.0
	while next_ground_x < viewport_w + SPAWN_BUFFER:
		_spawn_ground_tile(next_ground_x, GROUND_TOP_Y)
		next_ground_x += TILE_SIZE

	_update_rank_ui()
	_update_ui()
	_update_mental_gauge()

	# カメラ初期位置は画面中央。プレイヤーは開幕すぐ落下するが、
	# デッドゾーンが ±120 あるので着地までに動かすほどではない。
	camera.position = Vector2(CAMERA_FIXED_X, 270.0)
	# デッドゾーンの可視化(DEBUG_MODE 時のみ)
	debug_deadzone.visible = DEBUG_MODE


func _process(delta: float) -> void:
	if not game_active:
		return

	distance_score += delta * DISTANCE_PER_SECOND

	# レベルアップ
	if current_level < MAX_LEVEL:
		level_up_timer += delta
		if level_up_timer >= LEVEL_DURATION:
			level_up_timer -= LEVEL_DURATION
			_level_up()

	# 汗マーク(余裕不足時に定期的に出す)
	if mental_reserve < MENTAL_LOW_THRESHOLD:
		_sweat_timer -= delta
		if _sweat_timer <= 0.0:
			_sweat_timer = 1.0
			_spawn_sweat_drop()

	# スポーン
	next_ground_x -= current_scroll_speed * delta
	var viewport_w := get_viewport_rect().size.x
	while next_ground_x < viewport_w + SPAWN_BUFFER:
		_spawn_one_tile_slot(next_ground_x)
		next_ground_x += TILE_SIZE

	# 画面内に緊急入院が居れば画面端を赤くパルス
	_update_edge_lights()

	# カメラ Y 追従(デッドゾーン方式)。
	# 死亡演出に入ると game_active=false でこの関数自体が早期 return するので、
	# カメラはその場で止まり吹っ飛びを静止カメラから見送る形になる。
	_update_camera_deadzone(delta)

	# デバッグログ
	if DEBUG_MODE:
		_debug_timer += delta
		if _debug_timer >= 1.0:
			_debug_timer = 0.0
			print("[DEBUG] Lv=", current_level, " (", LEVELS[min(current_level, LEVELS.size() - 1)], ")  mental=", int(mental_reserve), "/", int(MENTAL_MAX), "  speed=", int(current_scroll_speed))

	_update_ui()


# ============================================================
# タイル単位のスポーン
# ============================================================

func _spawn_one_tile_slot(tile_x: float) -> void:
	tiles_since_hole_ended += 1
	tiles_since_obstacle += 1
	tiles_since_coin += 1

	# 穴生成中
	if pending_hole_tiles > 0:
		_spawn_hole_warning(tile_x, GROUND_TOP_Y + current_y_offset)
		pending_hole_tiles -= 1
		if pending_hole_tiles == 0:
			tiles_since_hole_ended = 0   # 穴が終わった → ここから MIN_TILES_AFTER_HOLE 待つ
		section_tile_index += 1
		return

	# セクション終了判定
	if section_tile_index >= section_length:
		_advance_section()

	# 階段セクションなら、踊り場ではない中央部分で Y オフセットを変化させる
	var is_landing: bool = (section_tile_index < STAIRS_LANDING_TILES) or (section_tile_index >= section_length - STAIRS_LANDING_TILES)
	if current_section != "flat" and not is_landing:
		if current_section == "stairs_up":
			current_y_offset -= STAIRS_TILE_Y_STEP
		elif current_section == "stairs_down":
			current_y_offset += STAIRS_TILE_Y_STEP

	var ground_y: float = GROUND_TOP_Y + current_y_offset

	# 地面スポーン
	var ground := _spawn_ground_tile(tile_x, ground_y)

	# 穴の開始判定(MIN_TILES_AFTER_HOLE だけ余裕があるときのみ)
	if tiles_since_hole_ended >= MIN_TILES_AFTER_HOLE and randf() < HOLE_CHANCE * hole_chance_mult:
		if ground.has_method("mark_hole_warning"):
			ground.mark_hole_warning()
		pending_hole_tiles = randi_range(HOLE_MIN_WIDTH, HOLE_MAX_WIDTH)
		section_tile_index += 1
		return

	# 障害物
	if tiles_since_obstacle >= MIN_TILES_BEFORE_OBSTACLE and randf() < OBSTACLE_CHANCE * obstacle_chance_mult:
		_spawn_obstacle(tile_x + TILE_SIZE * 0.5, ground_y)
		tiles_since_obstacle = 0
		section_tile_index += 1
		return

	# コイン
	if tiles_since_coin >= MIN_TILES_BEFORE_COIN and randf() < COIN_CHANCE * coin_chance_mult:
		_spawn_coin(tile_x + TILE_SIZE * 0.5, ground_y)
		tiles_since_coin = 0

	section_tile_index += 1


func _spawn_ground_tile(tile_x: float, ground_top_y: float) -> Node2D:
	var g := ground_scene.instantiate()
	g.position = Vector2(tile_x + TILE_SIZE * 0.5, ground_top_y + 60.0)
	g.scroll_speed = current_scroll_speed
	add_child(g)
	return g


func _spawn_hole_warning(tile_x: float, ground_top_y: float) -> void:
	if hole_warning_scene == null:
		return
	var hw := hole_warning_scene.instantiate()
	hw.position = Vector2(tile_x + TILE_SIZE * 0.5, ground_top_y)
	hw.scroll_speed = current_scroll_speed
	add_child(hw)


func _spawn_obstacle(center_x: float, ground_top_y: float) -> void:
	var o := obstacle_scene.instantiate()
	o.position = Vector2(center_x, ground_top_y)
	o.scroll_speed = current_scroll_speed
	o.obstacle_type = _pick_obstacle_type()
	o.hit_player.connect(_on_obstacle_hit)
	add_child(o)


func _spawn_coin(center_x: float, ground_top_y: float) -> void:
	var c := coin_scene.instantiate()
	var y_offset := randf_range(60.0, 160.0)
	c.position = Vector2(center_x, ground_top_y - y_offset)
	c.scroll_speed = current_scroll_speed
	c.coin_type = _pick_coin_type()
	c.collected.connect(_on_coin_collected)
	add_child(c)


# ============================================================
# セクション切替(flat / stairs_up / stairs_down)
# ============================================================

func _advance_section() -> void:
	# stairs_up と stairs_down が続かないよう、前と同じ向きの逆を除外する
	var prev := current_section
	var candidates: Array[Dictionary] = []
	for entry in SECTION_WEIGHTS:
		var t: String = String(entry["type"])
		if t == "stairs_up" and prev == "stairs_down":
			continue
		if t == "stairs_down" and prev == "stairs_up":
			continue
		candidates.append(entry)

	current_section = _weighted_pick(candidates)
	section_tile_index = 0
	if current_section == "flat":
		section_length = randi_range(FLAT_SECTION_MIN_LEN, FLAT_SECTION_MAX_LEN)
	else:
		section_length = randi_range(STAIRS_SECTION_MIN_LEN, STAIRS_SECTION_MAX_LEN)

	# 階段セクション開始時に通知
	if current_section == "stairs_up":
		_show_notification("上り階段")
	elif current_section == "stairs_down":
		_show_notification("下り階段")


# ============================================================
# シグナル受け取り
# ============================================================

func _on_coin_collected(value: int, type: String) -> void:
	coin_score += value
	# 心理的余裕を回復
	var gain: float = float(COIN_MENTAL_GAIN.get(type, 5.0))
	mental_reserve = clamp(mental_reserve + gain, 0.0, MENTAL_MAX)
	_update_mental_gauge()
	# 連休の派手演出
	if type == "vacation":
		vacation_count += 1
		_play_vacation_flash()


func _on_obstacle_hit(obstacle_type: String, obstacle: Area2D) -> void:
	if not game_active:
		return
	if player.is_dying:
		return

	var damage: float = float(OBSTACLE_DAMAGE.get(obstacle_type, 15.0))
	mental_reserve -= damage
	_update_mental_gauge()

	if DEBUG_MODE:
		print("[HIT] ", obstacle_type, "  -", int(damage), "  (", int(mental_reserve), "/", int(MENTAL_MAX), ")")

	if mental_reserve < 0.0:
		# バーンアウト死亡
		player.start_death_sequence("burnout")
	else:
		# 耐えた → 演出 + その障害物を一時無効化
		_play_hurt_effect()
		_disable_obstacle_briefly(obstacle)


func _on_player_death_started() -> void:
	game_active = false


func _on_player_died(cause: String) -> void:
	# ゲームオーバー画面の表示中は PlayUI を隠す
	play_ui.visible = false

	var go := game_over_scene.instantiate()
	var rank: String = LEVELS[min(current_level, LEVELS.size() - 1)]
	go.setup({
		"distance": int(distance_score),
		"points": coin_score,
		"cause": cause,
		"vacation_count": vacation_count,
		"rank": rank,
		"level": current_level,
		"mental": int(max(mental_reserve, 0.0)),
	})
	go.retry_pressed.connect(_on_retry)
	add_child(go)


func _on_retry() -> void:
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


# ============================================================
# モバイル対応: タッチ/クリック → ジャンプ + 視覚フィードバック
# ============================================================

# 画面タップ or マウスクリックを拾う。
# ジャンプ自体は InputMap の "jump" に ScreenTouch/MouseButton を追加済みなので
# Player 側の Input.is_action_just_pressed("jump") が自動で発火する。
# この関数はタップの「見た目のフィードバック(白いリング)」を出すだけ。
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed and not event.canceled:
		_spawn_tap_feedback(event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_spawn_tap_feedback(event.position)


# タップ位置に一瞬だけ白い円のリングを出して消す演出。
# CanvasLayer の上に TapRing(自作 Node2D スクリプト)をぶら下げる。
func _spawn_tap_feedback(screen_pos: Vector2) -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 80    # UI(layer=2) や RedLightOverlay(layer=5) より上
	get_tree().current_scene.add_child(canvas)

	var ring := Node2D.new()
	ring.set_script(TAP_RING_SCRIPT)
	canvas.add_child(ring)
	ring.position = screen_pos
	ring.animate()
	# リングが自動 queue_free したら、それを入れていた canvas も消す
	ring.tree_exited.connect(canvas.queue_free)


# ============================================================
# UI 更新
# ============================================================

func _update_ui() -> void:
	score_label.text = "勤続時間: %d" % int(distance_score)
	coin_label.text = "診療報酬: %d" % coin_score


func _update_rank_ui() -> void:
	var rank: String = LEVELS[min(current_level, LEVELS.size() - 1)]
	rank_label.text = "階級: %s" % rank


# 心理的余裕ゲージの塗り・色・点滅・赤フィルタを更新
func _update_mental_gauge() -> void:
	var clamped: float = clamp(mental_reserve, 0.0, MENTAL_MAX)
	mental_label.text = "心理的余裕 %d / %d" % [int(clamped), int(MENTAL_MAX)]

	var ratio: float = clamped / MENTAL_MAX
	# MentalGauge の実サイズから毎フレーム計算(画面幅・アンカー変更にも追随)
	var inner_w: float = max(0.0, mental_gauge.size.x - GAUGE_INNER_MARGIN)
	mental_bar_fill.offset_right = mental_bar_fill.offset_left + inner_w * ratio

	if clamped >= 80.0:
		mental_bar_fill.color = Color(0.3, 0.7, 1.0)
	elif clamped >= 50.0:
		mental_bar_fill.color = Color(0.3, 0.9, 0.4)
	elif clamped >= MENTAL_LOW_THRESHOLD:
		mental_bar_fill.color = Color(1.0, 0.9, 0.2)
	else:
		mental_bar_fill.color = Color(1.0, 0.3, 0.3)

	_update_mental_blink(clamped < MENTAL_LOW_THRESHOLD)
	red_tint_overlay.visible = clamped < MENTAL_CRITICAL_THRESHOLD


# バーの点滅 tween を要求時だけ起動、解除時だけ kill する
func _update_mental_blink(should_blink: bool) -> void:
	if should_blink and _mental_blink_tween == null:
		_mental_blink_tween = create_tween().set_loops()
		_mental_blink_tween.tween_property(mental_bar_fill, "modulate:a", 0.5, 0.4)
		_mental_blink_tween.tween_property(mental_bar_fill, "modulate:a", 1.0, 0.4)
	elif not should_blink and _mental_blink_tween != null:
		_mental_blink_tween.kill()
		_mental_blink_tween = null
		mental_bar_fill.modulate.a = 1.0


# 画面下部中央に短時間の通知テキストを出す(階段通知に使用)
func _show_notification(text: String) -> void:
	notification_label.text = text
	if _notification_tween != null:
		_notification_tween.kill()
	notification_label.modulate.a = 0.0
	_notification_tween = create_tween()
	_notification_tween.tween_property(notification_label, "modulate:a", 1.0, 0.2)
	_notification_tween.tween_interval(1.1)
	_notification_tween.tween_property(notification_label, "modulate:a", 0.0, 0.2)


# ============================================================
# ダメージ演出 / 障害物の一時無効化
# ============================================================

func _play_hurt_effect() -> void:
	_play_emergency_light_flash()
	_shake_player_sprite()


# 救急車のパトライト風に赤い全画面フラッシュを 3 回点滅させる。
# 毎回 0.15 秒で α 0 → 0.6 → 0 を往復、合計 3 フラッシュ(~0.9秒)。
# 二重起動すると α が暴れるので、前の tween が残っていたら kill する。
func _play_emergency_light_flash() -> void:
	if _red_light_tween != null and _red_light_tween.is_valid():
		_red_light_tween.kill()
	red_light_flash.color.a = 0.0
	_red_light_tween = create_tween()
	for i in 3:
		_red_light_tween.tween_property(red_light_flash, "color:a", 0.6, 0.15)
		_red_light_tween.tween_property(red_light_flash, "color:a", 0.0, 0.15)


# プレイヤーの Sprite(子ノード)を左右に細かく震わせる。
# Player 本体の position.x は変えない(ゲームロジックに影響させないため)。
func _shake_player_sprite() -> void:
	if player == null:
		return
	var sprite := player.get_node_or_null("Sprite")
	if sprite == null:
		return
	var orig_x: float = sprite.position.x
	var tween := create_tween()
	tween.tween_property(sprite, "position:x", orig_x - 4.0, 0.04)
	tween.tween_property(sprite, "position:x", orig_x + 4.0, 0.04)
	tween.tween_property(sprite, "position:x", orig_x - 2.0, 0.04)
	tween.tween_property(sprite, "position:x", orig_x + 2.0, 0.04)
	tween.tween_property(sprite, "position:x", orig_x, 0.04)


# 当たった障害物を 0.5 秒無効化(再度当たらないようにして、視覚的に少し薄くする)
func _disable_obstacle_briefly(obstacle: Area2D) -> void:
	if not is_instance_valid(obstacle):
		return
	obstacle.monitoring = false
	var cs := obstacle.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs != null:
		cs.set_deferred("disabled", true)
	var tween := create_tween()
	tween.tween_property(obstacle, "modulate:a", 0.5, 0.1)
	# 一定時間後に復帰(この頃にはもう画面外に流れている可能性が高い)
	var timer := get_tree().create_timer(OBSTACLE_INVULN_DURATION)
	timer.timeout.connect(func():
		if is_instance_valid(obstacle):
			obstacle.monitoring = true
			if cs != null:
				cs.set_deferred("disabled", false)
			obstacle.modulate.a = 1.0
	)


# 余裕 < 30 のときに 1 秒ごとに出る汗マーク(プレイヤー周辺にランダム配置 → 1秒でフェード)
func _spawn_sweat_drop() -> void:
	if player == null or not is_instance_valid(player):
		return
	var drop := ColorRect.new()
	drop.color = Color(0.4, 0.7, 1.0, 0.9)
	drop.size = Vector2(6.0, 10.0)
	drop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drop.top_level = true   # 親の変形を継承しない(ワールド座標に貼り付け)
	var offset := Vector2(randf_range(-24.0, 24.0), randf_range(-32.0, -16.0))
	get_tree().current_scene.add_child(drop)
	drop.global_position = player.global_position + offset - drop.size * 0.5
	var tween := create_tween()
	tween.tween_property(drop, "modulate:a", 0.0, 1.0)
	tween.tween_callback(drop.queue_free)


# ============================================================
# レベルアップ処理
# ============================================================

func _level_up() -> void:
	var old_rank: String = LEVELS[min(current_level, LEVELS.size() - 1)]
	current_level += 1
	var new_rank: String = LEVELS[min(current_level, LEVELS.size() - 1)]
	_apply_level_effects()
	_update_rank_ui()
	_show_levelup_banner(old_rank, new_rank)
	_play_levelup_flash()
	play_levelup_sound()

	# プレイヤー位置の左ズレ検証用。DEBUG_MODE=true にしたときだけ出る。
	if DEBUG_MODE:
		print("[LV UP] Lv=", current_level, " rank=", new_rank,
			" player_pos=", player.global_position,
			" scroll=", current_scroll_speed)


func _apply_level_effects() -> void:
	current_scroll_speed = SCROLL_SPEED + float(current_level) * LEVEL_SCROLL_BONUS
	obstacle_chance_mult = clamp(1.0 + float(current_level) * LEVEL_OBSTACLE_CHANCE_PER_LVL, 1.0, MIN_CHANCE_MULT_CLAMP)
	coin_chance_mult = clamp(1.0 + float(current_level) * LEVEL_COIN_CHANCE_PER_LVL, 1.0, MIN_CHANCE_MULT_CLAMP)
	var hole_extra: float = 0.0
	if current_level >= LEVEL_HOLE_START_LVL:
		hole_extra = float(current_level - LEVEL_HOLE_START_LVL + 1) * LEVEL_HOLE_CHANCE_PER_LVL
	hole_chance_mult = clamp(1.0 + hole_extra, 1.0, MIN_CHANCE_MULT_CLAMP)

	# 世界に居る scroll 対象のスピードも一斉更新
	for child in get_children():
		if "scroll_speed" in child:
			child.scroll_speed = current_scroll_speed

	_update_player_modulate()


func _update_player_modulate() -> void:
	if player == null:
		return
	if "is_dying" in player and player.is_dying:
		return
	var sprite := player.get_node_or_null("Sprite")
	if sprite == null:
		return
	if current_level <= 2:
		sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
	elif current_level <= 5:
		sprite.modulate = Color(0.90, 0.90, 0.95, 1.0)
	else:
		sprite.modulate = Color(0.85, 0.85, 0.90, 1.0)


func _show_levelup_banner(old_rank: String, new_rank: String) -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 70
	get_tree().current_scene.add_child(canvas)

	var lbl := Label.new()
	lbl.text = "昇格!  %s  →  %s" % [old_rank, new_rank]
	lbl.add_theme_font_size_override("font_size", 42)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3, 1.0))
	lbl.add_theme_color_override("font_shadow_color", Color(0.3, 0.15, 0.0, 1.0))
	lbl.add_theme_constant_override("shadow_offset_x", 4)
	lbl.add_theme_constant_override("shadow_offset_y", 4)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.anchor_left = 0.0
	lbl.anchor_right = 1.0
	lbl.anchor_top = 0.28
	lbl.anchor_bottom = 0.46
	lbl.modulate.a = 0.0
	canvas.add_child(lbl)

	var tween := create_tween()
	tween.tween_property(lbl, "modulate:a", 1.0, 0.3)
	tween.tween_interval(2.0)
	tween.tween_property(lbl, "modulate:a", 0.0, 0.5)
	tween.tween_callback(canvas.queue_free)


func _play_levelup_flash() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 65
	get_tree().current_scene.add_child(canvas)
	var flash := ColorRect.new()
	flash.color = Color(1.0, 0.95, 0.4, 0.5)
	flash.anchor_right = 1.0
	flash.anchor_bottom = 1.0
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(flash)
	var tween := create_tween()
	tween.tween_property(flash, "color:a", 0.0, 0.45)
	tween.tween_callback(canvas.queue_free)


func play_levelup_sound() -> void:
	pass   # 将来の実装用フック


# ============================================================
# 抽選 / 連休フラッシュ
# ============================================================

func _pick_coin_type() -> String:
	return _weighted_pick(COIN_WEIGHTS)


func _pick_obstacle_type() -> String:
	return _weighted_pick(OBSTACLE_WEIGHTS)


# weights の合計が 1.0 でなくても動くように、合計で正規化してから抽選
func _weighted_pick(weights: Array[Dictionary]) -> String:
	var total: float = 0.0
	for entry in weights:
		total += float(entry["weight"])
	if total <= 0.0:
		return String(weights[0]["type"])
	var r: float = randf() * total
	var acc: float = 0.0
	for entry in weights:
		acc += float(entry["weight"])
		if r < acc:
			return String(entry["type"])
	return String(weights[0]["type"])


# ============================================================
# カメラ追従(デッドゾーン方式)
# ============================================================

# プレイヤーが画面中央 ±DEADZONE_Y_HALF の安全地帯にいる間は何もしない。
# その外に出そうになった時だけ lerp でじわっとカメラを寄せる。
# → 画面酔い防止(普段はピタッと静止、必要な時だけ動く)。
# X は固定なので触らない(Player 側で強制スナップ済み)。
func _update_camera_deadzone(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	# 死亡演出は既存の知見を優先(吹っ飛びをカメラが追わないようここで止める)
	if "is_dying" in player and player.is_dying:
		return

	var player_y: float = player.global_position.y
	var cam_y: float = camera.global_position.y
	var top_edge: float = cam_y - DEADZONE_Y_HALF
	var bottom_edge: float = cam_y + DEADZONE_Y_HALF

	if player_y < top_edge:
		# プレイヤーがデッドゾーン上端より上 → デッドゾーン上端に載せる
		var target_y: float = player_y + DEADZONE_Y_HALF
		camera.global_position.y = lerp(cam_y, target_y, CAMERA_FOLLOW_SPEED * delta)
	elif player_y > bottom_edge:
		# プレイヤーがデッドゾーン下端より下 → デッドゾーン下端に載せる
		var target_y: float = player_y - DEADZONE_Y_HALF
		camera.global_position.y = lerp(cam_y, target_y, CAMERA_FOLLOW_SPEED * delta)
	# デッドゾーン内は何もしない(カメラ完全静止)


# ============================================================
# 緊急入院が画面内に居る間の画面端パルス
# ============================================================

# 画面内に "emergency" 障害物が 1 つでも居れば、左右の EdgeLight を
# ゆっくり明滅させる。居なくなれば停止して非表示に戻す。
func _update_edge_lights() -> void:
	var has_emergency: bool = not get_tree().get_nodes_in_group("active_emergency_obstacle").is_empty()
	if has_emergency and _edge_light_tween == null:
		_start_edge_light_pulse()
	elif not has_emergency and _edge_light_tween != null:
		_stop_edge_light_pulse()


func _start_edge_light_pulse() -> void:
	edge_light_left.visible = true
	edge_light_right.visible = true
	# tween_method で両サイドのα値を同時に動かす(点滅が揃う)
	_edge_light_tween = create_tween().set_loops()
	_edge_light_tween.tween_method(_set_edge_light_alpha, 0.2, 0.5, 0.4)
	_edge_light_tween.tween_method(_set_edge_light_alpha, 0.5, 0.2, 0.4)


func _stop_edge_light_pulse() -> void:
	if _edge_light_tween != null:
		_edge_light_tween.kill()
		_edge_light_tween = null
	edge_light_left.visible = false
	edge_light_right.visible = false


func _set_edge_light_alpha(value: float) -> void:
	edge_light_left.color.a = value
	edge_light_right.color.a = value


# ============================================================
# その他の演出
# ============================================================

func _play_vacation_flash() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 60
	get_tree().current_scene.add_child(canvas)
	var flash := ColorRect.new()
	flash.color = Color(1.0, 0.95, 0.3, 0.55)
	flash.anchor_right = 1.0
	flash.anchor_bottom = 1.0
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(flash)
	var tween := create_tween()
	tween.tween_property(flash, "color:a", 0.0, 0.5)
	tween.tween_callback(canvas.queue_free)

	var tween2 := create_tween()
	tween2.tween_property(coin_label, "scale", Vector2(1.4, 1.4), 0.15)
	tween2.tween_property(coin_label, "scale", Vector2(1.0, 1.0), 0.3)
