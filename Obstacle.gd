extends Area2D
# ============================================================
# Obstacle.gd
# 医療現場の敵キャラ。obstacle_type で 6 種類に化ける。
#
#   - senior_nurse    : AI生成画像(フォールバック: Kenney Female)
#                       小刻みにプルプル震える(怒り・威圧)
#   - complaint_call  : 黒 ColorRect
#                       左右にゆっくり揺れる(受話器の揺れ)
#   - emergency       : 赤 ColorRect + α 点滅
#                       上下にフワフワ浮く(警告灯の浮遊感)
#                       画面内に居る間は Main が画面端を赤くパルスさせる
#   - paperwork       : 木箱 3 段スタック
#                       縦にわずかに伸縮(書類の揺れ)
#   - medical_records : 32x64 ベージュ + 赤背表紙
#                       上下にゆっくり波打ち + 左右にもわずかに揺れ
#   - call_bell       : 赤 ColorRect + 黄色ハンドル
#                       細かく左右ビリビリ振動 + 色が赤↔オレンジに鳴動
#
# Area2D の原点 = 足元(地面の上面)。ビジュアルは全部原点より上に伸ばす。
# hit_player シグナルは (type, 自身) を送る。
# ============================================================

# ---- AI 生成画像(お局様の差し替え用) ----
const AI_SENIOR_NURSE_PATH := "res://assets/ai_generated/senior_nurse.png"
const AI_SENIOR_NURSE_SCALE := Vector2(0.12, 0.12)
const AI_SENIOR_NURSE_COLLISION_SIZE := Vector2(55.0, 90.0)

# Godot セッション全体で 1 度だけ成功/失敗ログを出すための静的フラグ。
# 毎スポーンで print したくないが、存在しないときは気付きたいので最初の spawn で教える。
static var _logged_senior_nurse_attempt: bool = false

@export var scroll_speed: float = 300.0
@export var obstacle_type: String = "senior_nurse"

# (obstacle_type, self) を渡す。Main が damage 計算と一時無効化に使う
signal hit_player(type: String, obstacle: Area2D)

const DEFAULT_WIDTH := 32.0
const NORMAL_HEIGHT := 32.0
const TALL_HEIGHT := 64.0

const TYPE_DATA: Dictionary = {
	"senior_nurse":    {"color": Color(0.776, 0.082, 0.522, 1.0), "text": "お局様",     "height": NORMAL_HEIGHT},
	"complaint_call":  {"color": Color(0.1, 0.1, 0.1, 1.0),       "text": "クレーム",   "height": NORMAL_HEIGHT},
	"emergency":       {"color": Color(1.0, 0.1, 0.1, 1.0),       "text": "緊急入院",   "height": NORMAL_HEIGHT},
	"paperwork":       {"color": Color(0.85, 0.75, 0.55, 1.0),    "text": "書類",      "height": TALL_HEIGHT},
	"call_bell":       {"color": Color(0.95, 0.2, 0.2, 1.0),      "text": "コール",    "height": NORMAL_HEIGHT},
	"medical_records": {"color": Color(0.98, 0.92, 0.84, 1.0),    "text": "カルテ地獄", "height": TALL_HEIGHT},
}

@onready var visual: ColorRect = $Visual
@onready var female_sprite: Sprite2D = $FemaleSprite
@onready var paperwork_stack: Node2D = $PaperworkStack
@onready var medical_records_stack: Node2D = $MedicalRecordsStack
@onready var bell_handle: ColorRect = $BellHandle
@onready var type_label: Label = $TypeLabel
@onready var collision: CollisionShape2D = $CollisionShape2D

# --- アイドル揺れの時間カウンタと基準位置 ---
var _idle_time: float = 0.0
var _base_visual_x: float = 0.0
var _base_label_x: float = 0.0
var _base_bell_x: float = 0.0
var _base_female_x: float = 0.0
var _base_female_y: float = 0.0
var _base_mr_stack_x: float = 0.0
var _base_paperwork_scale_y: float = 1.0
var _base_y: float = 0.0                   # 自分(Area2D)の開始 Y


func _ready() -> void:
	_apply_type()
	# 基準値は _apply_type 後に保存(AI画像で position が書き換わる可能性があるので)
	_base_visual_x = visual.position.x
	_base_label_x = type_label.position.x
	_base_bell_x = bell_handle.position.x
	_base_female_x = female_sprite.position.x
	_base_female_y = female_sprite.position.y
	_base_mr_stack_x = medical_records_stack.position.x
	_base_paperwork_scale_y = paperwork_stack.scale.y
	_base_y = position.y
	body_entered.connect(_on_body_entered)


func _apply_type() -> void:
	var data: Dictionary = TYPE_DATA.get(obstacle_type, TYPE_DATA["senior_nurse"])
	type_label.text = data["text"]
	var h: float = float(data["height"])

	# デフォルトの当たり判定(高さに合わせて再生成)
	var shape := RectangleShape2D.new()
	shape.size = Vector2(DEFAULT_WIDTH, h)
	collision.shape = shape
	collision.position.y = -h / 2.0
	type_label.offset_top = -h - 30.0
	type_label.offset_bottom = -h - 4.0

	visual.visible = false
	female_sprite.visible = false
	paperwork_stack.visible = false
	medical_records_stack.visible = false
	bell_handle.visible = false

	match obstacle_type:
		"senior_nurse":
			female_sprite.visible = true
			if _try_apply_ai_senior_nurse_texture():
				_resize_for_ai_senior_nurse()
			else:
				female_sprite.modulate = Color(1.2, 0.7, 0.9)
		"paperwork":
			paperwork_stack.visible = true
		"medical_records":
			medical_records_stack.visible = true
		"call_bell":
			_show_rect_visual(data["color"], h)
			bell_handle.visible = true
		"emergency":
			_show_rect_visual(data["color"], h)
			_start_blink()
			# Main 側で画面端パルスを制御するためのグループ登録。
			# queue_free されると自動で外れる。
			add_to_group("active_emergency_obstacle")
		_:
			# complaint_call
			_show_rect_visual(data["color"], h)


func _show_rect_visual(col: Color, h: float) -> void:
	visual.visible = true
	visual.color = col
	visual.offset_top = -h
	visual.offset_bottom = 0.0


func _start_blink() -> void:
	var tween := create_tween().set_loops()
	tween.tween_property(self, "modulate:a", 0.5, 0.3)
	tween.tween_property(self, "modulate:a", 1.0, 0.3)


# AI画像があれば差し替え。戻り値 = 差し替えたかどうか。
# 存在有無を Godot セッションで 1 回だけコンソールに出力する。
func _try_apply_ai_senior_nurse_texture() -> bool:
	var exists: bool = ResourceLoader.exists(AI_SENIOR_NURSE_PATH)
	if not exists:
		if not _logged_senior_nurse_attempt:
			_logged_senior_nurse_attempt = true
			print("[senior_nurse] 画像読み込み: 失敗 (", AI_SENIOR_NURSE_PATH, " が見つからない or import 未完了)")
		return false

	var tex := load(AI_SENIOR_NURSE_PATH) as Texture2D
	if tex == null:
		if not _logged_senior_nurse_attempt:
			_logged_senior_nurse_attempt = true
			print("[senior_nurse] 画像読み込み: 失敗 (Texture2D として読み込めず)")
		return false

	if not _logged_senior_nurse_attempt:
		_logged_senior_nurse_attempt = true
		print("[senior_nurse] 画像読み込み: 成功 (", AI_SENIOR_NURSE_PATH, ")")

	female_sprite.texture = tex
	female_sprite.scale = AI_SENIOR_NURSE_SCALE
	female_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)
	return true


# AI画像は縦長なので、ラベル位置・コリジョンを画像サイズに合わせ直す
func _resize_for_ai_senior_nurse() -> void:
	var col_size := AI_SENIOR_NURSE_COLLISION_SIZE
	female_sprite.position = Vector2(0.0, -col_size.y / 2.0)
	var shape := RectangleShape2D.new()
	shape.size = col_size
	collision.shape = shape
	collision.position.y = -col_size.y / 2.0
	type_label.offset_top = -col_size.y - 30.0
	type_label.offset_bottom = -col_size.y - 4.0
	type_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35, 1.0))


func _process(delta: float) -> void:
	# 左スクロールは全タイプ共通
	position.x -= scroll_speed * delta

	# アイドル揺れ用の時間を進める(delta ベース = fps 非依存)
	_idle_time += delta
	_apply_idle_motion()

	if position.x < -100.0:
		queue_free()


# タイプごとのアイドル揺れ。スクロール後にビジュアル側のオフセットだけを動かす。
# 当たり判定(Area2D 原点)は揺らさないので、ヒット位置が意図せずブレない。
# ただし emergency と medical_records は "浮遊感" を出すため root の y も動かす。
func _apply_idle_motion() -> void:
	match obstacle_type:
		"senior_nurse":
			# 小刻みにプルプル(x,y 高周波)
			female_sprite.position.x = _base_female_x + sin(_idle_time * 25.0) * 1.5
			female_sprite.position.y = _base_female_y + sin(_idle_time * 30.0) * 0.8
		"complaint_call":
			# 受話器が揺れる感じ(低速 x のみ)
			visual.position.x = _base_visual_x + sin(_idle_time * 4.0) * 3.0
			type_label.position.x = _base_label_x + sin(_idle_time * 4.0) * 3.0
		"emergency":
			# 警告灯がフワフワ浮くように上下移動(既存の α 点滅と独立)
			position.y = _base_y + sin(_idle_time * 3.0) * 4.0
		"paperwork":
			# 書類が揺れて積み増しされる感じで縦方向に伸縮
			paperwork_stack.scale.y = _base_paperwork_scale_y + sin(_idle_time * 5.0) * 0.05
		"medical_records":
			# 既存の上下波動きに加え、左右にもわずかに揺れ
			position.y = _base_y + sin(_idle_time * 2.5) * 2.0
			medical_records_stack.position.x = _base_mr_stack_x + sin(_idle_time * 2.0) * 2.0
		"call_bell":
			# 細かくビリビリ振動 + 色が赤↔オレンジに"鳴動"
			var dx: float = sin(_idle_time * 35.0) * 2.0
			visual.position.x = _base_visual_x + dx
			type_label.position.x = _base_label_x + dx
			bell_handle.position.x = _base_bell_x + dx
			var mix: float = sin(_idle_time * 6.0) * 0.5 + 0.5
			# 赤 (0.95, 0.2, 0.2) と オレンジ (1.0, 0.55, 0.15) を lerp
			visual.color = Color(0.95, 0.2, 0.2).lerp(Color(1.0, 0.55, 0.15), mix)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		hit_player.emit(obstacle_type, self)
