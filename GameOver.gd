extends CanvasLayer
# ============================================================
# GameOver.gd
# 医療職あるある版の休職画面。
# Main.gd から setup(stats: Dictionary) で情報一式を受け取る。
# stats に入るキー:
#   distance       : 勤続時間(int)
#   points         : 獲得診療報酬(int)
#   cause          : "burnout" / "obstacle" / "hole"
#   vacation_count : 連休取得回数(int)
#   rank           : 到達階級名(String)
#   level          : 到達階級レベル(int) -> フレーバーテキストの判定に使用
#   mental         : 最終余裕 0〜100(int)
# ============================================================

signal retry_pressed

# setup が _ready より前に呼ばれることもあるので一旦貯める
var _distance: int = 0
var _points: int = 0
var _cause: String = "burnout"
var _vacation_count: int = 0
var _rank: String = "新卒"
var _level: int = 0
var _mental: int = 0

@onready var cause_label: Label = $Panel/CauseLabel
@onready var rank_label: Label = $Panel/RankLabel
@onready var flavor_label: Label = $Panel/FlavorLabel
@onready var score_label: Label = $Panel/ScoreLabel
@onready var duration_label: Label = $Panel/DurationLabel
@onready var points_label: Label = $Panel/PointsLabel
@onready var mental_label: Label = $Panel/MentalLabel
@onready var vacation_label: Label = $Panel/VacationLabel
@onready var retry_button: Button = $Panel/RetryButton


func _ready() -> void:
	_apply_values()
	retry_button.pressed.connect(_on_retry_pressed)
	retry_button.grab_focus()


# Main.gd から呼ばれる外部 API。キーがなければ各自の初期値のまま。
func setup(stats: Dictionary) -> void:
	_distance = int(stats.get("distance", 0))
	_points = int(stats.get("points", 0))
	_cause = String(stats.get("cause", "burnout"))
	_vacation_count = int(stats.get("vacation_count", 0))
	_rank = String(stats.get("rank", "新卒"))
	_level = int(stats.get("level", 0))
	_mental = int(stats.get("mental", 0))
	if is_node_ready():
		_apply_values()


func _apply_values() -> void:
	cause_label.text = _cause_to_subtext(_cause)
	rank_label.text = "到達階級: %s" % _rank
	flavor_label.text = _level_to_flavor(_level)
	score_label.text = "最終スコア: %d" % (_distance + _points)
	duration_label.text = "勤続時間: %d 秒" % _distance
	points_label.text = "獲得診療報酬: %d 点" % _points
	mental_label.text = "最終余裕: %d / 100" % _mental
	if _vacation_count > 0:
		vacation_label.visible = true
		vacation_label.text = "取得した連休: %d 回" % _vacation_count
	else:
		vacation_label.visible = false


# 死因ごとのサブテキスト。"obstacle" は古い互換用。
func _cause_to_subtext(cause: String) -> String:
	match cause:
		"burnout", "obstacle":
			return "バーンアウトで倒れました"
		"hole":
			return "過労で休職に追い込まれました"
		_:
			return ""


func _level_to_flavor(level: int) -> String:
	if level == 0:
		return "まだまだこれから…"
	elif level <= 3:
		return "お疲れ様でした"
	elif level <= 6:
		return "立派な中堅です"
	else:
		return "伝説を刻みました"


func _on_retry_pressed() -> void:
	retry_pressed.emit()
