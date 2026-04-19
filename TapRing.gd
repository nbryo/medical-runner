extends Node2D
# ============================================================
# TapRing.gd
# 画面をタップ/クリックした位置に 1 回だけ描画される、白い円のリング演出。
# 0.3 秒で半径が 8 → 50、α が 0.8 → 0 と変化して自動削除される。
# Main.gd が _unhandled_input 経由で Node2D を new して set_script → add_child、
# その後 animate() を呼ぶ。
# ============================================================

const INITIAL_RADIUS: float = 8.0
const FINAL_RADIUS: float = 50.0
const DURATION: float = 0.3
const LINE_WIDTH: float = 3.0

var radius: float = INITIAL_RADIUS
var alpha: float = 0.8


func _draw() -> void:
	# α がほぼ 0 の時は描画コストを節約
	if alpha <= 0.0:
		return
	draw_arc(
		Vector2.ZERO,           # 中心
		radius,                 # 半径
		0.0,                    # 開始角
		TAU,                    # 終了角(円一周)
		48,                     # 解像度
		Color(1.0, 1.0, 1.0, alpha),
		LINE_WIDTH,
		true                    # アンチエイリアス
	)


# 広がりながらフェードアウト → 完了したら自動で queue_free。
# Main.gd が add_child 後に呼ぶ。
func animate() -> void:
	# ignore_time_scale はデフォルト false(通常の時間で動く)
	var tween := create_tween().set_parallel(true)
	tween.tween_method(_set_radius, INITIAL_RADIUS, FINAL_RADIUS, DURATION)
	tween.tween_method(_set_alpha, 0.8, 0.0, DURATION)
	tween.chain().tween_callback(queue_free)


# tween_method 用のセッター。queue_redraw で再描画を要求する。
func _set_radius(v: float) -> void:
	radius = v
	queue_redraw()


func _set_alpha(v: float) -> void:
	alpha = v
	queue_redraw()
