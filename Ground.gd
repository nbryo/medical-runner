extends StaticBody2D
# ============================================================
# Ground.gd
# 地面タイル1ブロック分。ベルトコンベア的に左へ動かす。
# - StaticBody2D なので CharacterBody2D のプレイヤーがちゃんと乗れる
# - 「穴」は Main.gd 側で「このタイルはスポーンしない」と判断することで表現する
#   (= 個別タイルに穴データは持たない)
# - 画面外に出たら自分で queue_free() してメモリを解放する
# ============================================================

# Main.gd から instantiate 時に好きな値をセットできるよう export。
# 既定値 300 px/s は仕様どおり。
@export var scroll_speed: float = 300.0


func _physics_process(delta: float) -> void:
	# StaticBody2D の位置を毎フレーム更新することで
	# プレイヤーから見て地面が左に流れていくように見せる。
	# _process ではなく _physics_process で動かすことで、
	# プレイヤーの物理判定(is_on_floor など)とズレが出にくい。
	position.x -= scroll_speed * delta

	# 画面の左外まで流れたら破棄
	if position.x < -200.0:
		queue_free()


# Main.gd が「この地面の次は穴」と判断したときに呼ぶ。
# 地面タイルの上面より少し浮かせた位置に警告ラベルを追加する。
func mark_hole_warning() -> void:
	var warn := Label.new()
	warn.name = "HoleWarning"
	warn.text = "休職注意"
	warn.add_theme_font_size_override("font_size", 11)
	warn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
	warn.add_theme_color_override("font_shadow_color", Color(0.3, 0.0, 0.0, 0.9))
	warn.add_theme_constant_override("shadow_offset_x", 1)
	warn.add_theme_constant_override("shadow_offset_y", 1)
	# 地面タイル(中心 y = GROUND_TOP_Y+60)に対して、上面のさらに少し上へ
	warn.position = Vector2(-28.0, -86.0)
	add_child(warn)
