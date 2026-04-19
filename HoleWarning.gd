extends Node2D
# ============================================================
# HoleWarning.gd
# 穴の中に表示する警告用の装飾シーン。
# - 黒い背景で穴を明示
# - 両脇と上辺に黄色い工事現場風のストライプ
# - 上空に赤い三角の警告アイコン(薄め)
# - 中央に「休職注意」ラベル
# 原点は穴の上端(地面の上面と同じY)。下方向に伸びる。
# Main.gd が 1 タイル分ずつ spawn する。左スクロールで画面外になれば自動削除。
# ============================================================

@export var scroll_speed: float = 300.0


func _process(delta: float) -> void:
	position.x -= scroll_speed * delta
	if position.x < -100.0:
		queue_free()
