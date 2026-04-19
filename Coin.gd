extends Area2D
# ============================================================
# Coin.gd
# 医療職モチーフのご褒美アイテム。coin_type で 4 種類に化ける。
#
#   - reward   : 診療報酬点数 (金貨画像: Kenney coinGold.png) (+10)
#   - sweets   : お菓子 (ピンクベージュ + 茶色チョコチップ ColorRect) (+10)
#   - thanks   : 患者からのありがとう (ハート画像: Kenney heart.png) (+10)
#   - vacation : 連休 ★レア (星画像: Kenney star.png) (+100)
# ============================================================

@export var scroll_speed: float = 300.0
@export var coin_type: String = "reward"

signal collected(value: int, type: String)

# タイプごとの基本データ(color は ColorRect 表示時の背景色、text は表示ラベル)
const TYPE_DATA := {
	"reward":   {"color": Color(1.0, 0.85, 0.2, 1.0),    "text": "診療報酬", "value": 10},
	"sweets":   {"color": Color(0.957, 0.76, 0.76, 1.0), "text": "お菓子",   "value": 10},
	"thanks":   {"color": Color(1.0, 0.55, 0.75, 1.0),   "text": "感謝",    "value": 10},
	"vacation": {"color": Color(1.0, 0.843, 0.0, 1.0),   "text": "連休",    "value": 100},
}

@onready var bg: ColorRect = $Background
@onready var chip1: ColorRect = $SweetsChip1
@onready var chip2: ColorRect = $SweetsChip2
@onready var chip3: ColorRect = $SweetsChip3
@onready var coin_sprite: Sprite2D = $CoinSprite
@onready var heart_sprite: Sprite2D = $HeartSprite
@onready var star_sprite: Sprite2D = $StarSprite
@onready var type_label: Label = $TypeLabel


func _ready() -> void:
	_apply_type()
	body_entered.connect(_on_body_entered)


# coin_type に合わせて表示する Sprite / ColorRect を切り替える
func _apply_type() -> void:
	var data: Dictionary = TYPE_DATA.get(coin_type, TYPE_DATA["reward"])
	type_label.text = data["text"]

	# まず全部非表示
	bg.visible = false
	chip1.visible = false
	chip2.visible = false
	chip3.visible = false
	coin_sprite.visible = false
	heart_sprite.visible = false
	star_sprite.visible = false

	match coin_type:
		"reward":
			coin_sprite.visible = true
		"thanks":
			heart_sprite.visible = true
		"vacation":
			star_sprite.visible = true
			star_sprite.modulate = Color(1.0, 0.95, 0.3, 1.0)
		"sweets":
			# ピンクベージュのクッキー本体 + 3 つの茶色チップ
			bg.visible = true
			bg.color = data["color"]
			chip1.visible = true
			chip2.visible = true
			chip3.visible = true
		_:
			bg.visible = true
			bg.color = data["color"]


func _process(delta: float) -> void:
	position.x -= scroll_speed * delta
	if position.x < -100.0:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		var data: Dictionary = TYPE_DATA.get(coin_type, TYPE_DATA["reward"])
		collected.emit(data["value"], coin_type)
		queue_free()
