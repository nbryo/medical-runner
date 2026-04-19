extends CharacterBody2D
# ============================================================
# Player.gd
# プレイヤーキャラクター + コミカル死亡演出。
#
# 通常時:
# - 画面左寄りに固定。地面側が左スクロールするので走って見える
# - 重力 + 2段ジャンプ
# - 穴に落ちて y が DEATH_Y を越えたら死亡演出を開始
#
# 死亡演出 (start_death_sequence 経由で発動):
#   1. ヒットストップ(time_scale 0 → 0.3 → 1.0)
#   2. 画面全体の赤フラッシュ(α 0.8 → 0)
#   3. カメラシェイク(±8px, 0.3 秒)
#   4. プレイヤー吹っ飛び(物理無視、velocity+gravity+rotation)
#   5. プレイヤーの表情と色を変更
#   6. "💥" と "ぐえっ!" の演出ラベル
#   7. 気絶星 3 つが頭上で回転
#   8. DEATH_DURATION (2秒) 経過後に died シグナル → Main がゲームオーバー画面を表示
#   9. play_hit_sound() / play_death_music() は将来の音対応用の空関数
# ============================================================

# --- 通常挙動の定数 ---
const GRAVITY := 1800.0
const JUMP_VELOCITY := -650.0
const MAX_JUMPS := 2
const DEATH_Y := 700.0                  # これ以下に落ちたら穴落下扱い

# --- プレイヤーの画面内固定位置 ---
# 画面幅 960 の 1/3 = 320 に毎フレームスナップする。レベルアップ等で
# 物理の副作用によるじわじわ左ズレが起きるのを防ぐ。Main.gd 側の PLAYER_X と
# 必ず同じ値にしておくこと。
const PLAYER_WORLD_X: float = 320.0

# デバッグ: true にすると 1 秒ごとに Player の global_position を print する
const DEBUG_POSITION: bool = false

# --- 死亡演出の調整パラメータ(ここを変えれば演出がガラッと変わる) ---
const DEATH_DURATION := 2.0             # 演出を見せる総時間。終わったらゲームオーバー
const HITSTOP_FREEZE := 0.1             # time_scale=0 で停止する時間
const HITSTOP_SLOW_SCALE := 0.3         # スロー時の time_scale
const HITSTOP_SLOW_DURATION := 0.5      # スロー状態を維持する時間
const KNOCKBACK_VELOCITY := Vector2(300.0, -600.0) # 吹っ飛びの初速(右・上)
const KNOCKBACK_ROTATION_PER_FRAME := 0.3 # 毎フレーム加算する回転量 (rad)
const SHAKE_DURATION := 0.3             # カメラ揺れの秒数
const SHAKE_AMPLITUDE := 8.0            # 揺れ幅 (±px)
const SHAKE_STEPS := 18                 # 揺れを更新する回数
const RED_FLASH_START_ALPHA := 0.8      # 赤フラッシュの最大α
const RED_FLASH_DURATION := 0.1         # 赤フラッシュのフェード時間
const RED_FLASH_STEPS := 6              # フェードの分割数(time_scale非依存で段階的)
const STAR_COUNT := 3                   # 気絶星の数
const STAR_ORBIT_RADIUS := 32.0         # 星が回る半径
const STAR_ORBIT_PERIOD := 1.0          # 星が 1 周する秒数
const STAR_Y_OFFSET := -40.0            # 星の回転中心(プレイヤー中心からの相対Y)
const DEATH_BODY_COLOR := Color(0.3, 0.3, 0.5, 1.0) # 死亡時のプレイヤー本体色
const BURST_RISE_DISTANCE := 60.0       # 💥 が上昇するピクセル数
const BURST_DURATION := 0.5             # 💥 が消えるまでの時間

# --- ランタイム状態 ---
var jumps_remaining: int = MAX_JUMPS
var was_on_floor: bool = false
var is_dying: bool = false              # 演出中かどうか(Main からも参照)
var _death_cause: String = "obstacle"   # "obstacle"(障害物) / "hole"(穴落下)

# --- シグナル ---
signal death_started       # 演出開始直後に発射(Main がスポーン停止などに使う)
signal died(cause: String) # 演出終了時に発射。cause で死因を通知

@onready var sprite: AnimatedSprite2D = $Sprite


func _ready() -> void:
	add_to_group("player")
	# シーン側 autoplay="idle" で既に再生中だが、明示しておく
	sprite.play(&"idle")


func _physics_process(delta: float) -> void:
	if is_dying:
		# 死亡中は通常の物理は走らせず、吹っ飛び処理だけ行う
		_process_death_motion(delta)
		return

	# --- 通常時の挙動 ---
	var on_floor := is_on_floor()
	if on_floor:
		jumps_remaining = MAX_JUMPS
	elif was_on_floor:
		# 崖落ちで空中ジャンプを 2 回使えないようにするペナルティ
		jumps_remaining = min(jumps_remaining, MAX_JUMPS - 1)
	if not on_floor:
		velocity.y += GRAVITY * delta
	if Input.is_action_just_pressed("jump") and jumps_remaining > 0:
		velocity.y = JUMP_VELOCITY
		jumps_remaining -= 1
	velocity.x = 0
	move_and_slide()
	was_on_floor = on_floor

	# --- 水平位置を強制スナップ ---
	# move_and_slide の depenetration や、動く地面の副作用で X が少しずつ
	# ズレるのを毎フレーム矯正する。Y は重力/ジャンプに任せる。
	# 死亡演出(_process_death_motion)はこの関数の先頭で早期 return しているので
	# ここには来ない = 吹っ飛び中は無視される。
	global_position.x = PLAYER_WORLD_X

	# 接地/空中に応じてアニメを切り替える(毎フレーム呼んでも差分だけ反映)
	_update_animation()

	# デバッグ表示(1秒に1回、Engine の物理フレームカウンタで間引き)
	if DEBUG_POSITION and Engine.get_physics_frames() % 60 == 0:
		print("[Player] global_position=", global_position, "  on_floor=", on_floor)

	# 穴に落ちた
	if global_position.y > DEATH_Y:
		start_death_sequence("hole")


# 死亡中の動き。move_and_slide は使わず、地面をすり抜けて吹っ飛ばす。
# delta が 0(time_scale=0 のヒットストップ中)の間は回転も移動もしない。
func _process_death_motion(delta: float) -> void:
	if delta <= 0.0:
		return
	rotation += KNOCKBACK_ROTATION_PER_FRAME
	velocity.y += GRAVITY * delta
	position += velocity * delta


# ============================================================
# 死亡シーケンスのエントリーポイント
# cause: "obstacle"(障害物ヒット) / "fall"(穴に落下)
# ============================================================
func start_death_sequence(cause: String = "obstacle") -> void:
	if is_dying:
		return
	is_dying = true
	_death_cause = cause  # 演出完了時に GameOver へ受け渡す

	# やられポーズへ即切り替え(1フレームだけの非ループなので以降そのまま)
	sprite.play(&"hit")

	# Main 側で「スポーン停止・距離スコア加算停止」させるための合図
	death_started.emit()

	# 効果音フック(空実装、将来 AudioStreamPlayer を使う)
	play_hit_sound()
	play_death_music()

	# 各演出を独立に発火(どれも内部で await するので fire-and-forget)
	_apply_knockback(cause)
	_change_face()
	_spawn_burst_emoji()
	_spawn_pain_label_delayed()
	_spawn_stunned_stars()
	_spawn_red_flash()
	_shake_camera()
	_run_hitstop()
	_finalize_after_delay()


# 吹っ飛び初速。穴落下時は現在の落下ベクトルを尊重(上書きしない)
func _apply_knockback(cause: String) -> void:
	if cause == "hole":
		return
	velocity = KNOCKBACK_VELOCITY


# プレイヤーの見た目を変更: スプライトに暗色modulateを掛け、顔に "×_×" を貼る
func _change_face() -> void:
	# AnimatedSprite2D には color プロパティが無いので modulate(乗算カラー)を使う。
	# 乗算なので RGB < 1.0 の色を掛けると全体が暗くなる = やられ感。
	sprite.modulate = DEATH_BODY_COLOR
	var face := Label.new()
	face.name = "DeathFace"
	face.text = "×_×"
	face.add_theme_font_size_override("font_size", 14)
	face.add_theme_color_override("font_color", Color.WHITE)
	# ColorRect (32x48、中心原点) のおおよそ中央に配置
	face.position = Vector2(-14, -11)
	add_child(face)


# 衝突地点に "💥" を出し、上にフワッと上がりながらフェードアウト
func _spawn_burst_emoji() -> void:
	var lbl := Label.new()
	lbl.text = "💥"
	lbl.add_theme_font_size_override("font_size", 56)
	lbl.add_theme_color_override("font_color", Color(1, 0.8, 0.3))
	lbl.add_theme_color_override("font_shadow_color", Color(0.5, 0.2, 0, 0.8))
	lbl.add_theme_constant_override("shadow_offset_x", 2)
	lbl.add_theme_constant_override("shadow_offset_y", 2)
	lbl.z_index = 100

	# プレイヤー本体(回転する)にぶら下げると一緒に回ってしまうので、
	# 親を Main(current_scene)にして、世界座標に貼り付ける。
	var parent := get_tree().current_scene
	parent.add_child(lbl)
	lbl.global_position = global_position + Vector2(-30, -80)

	# 上昇 + 透明化を同時進行、終わったら自動削除
	var tween := create_tween().set_parallel(true)
	tween.tween_property(lbl, "global_position:y", lbl.global_position.y - BURST_RISE_DISTANCE, BURST_DURATION)
	tween.tween_property(lbl, "modulate:a", 0.0, BURST_DURATION)
	tween.chain().tween_callback(lbl.queue_free)


# 💥 の直後に "いてっ!" ラベルをちょっと遅れて登場
func _spawn_pain_label_delayed() -> void:
	# ignore_time_scale=true にしてヒットストップの影響を受けない実時間タイマー
	await get_tree().create_timer(0.15, true, false, true).timeout
	var lbl := Label.new()
	lbl.text = "いてっ!"
	lbl.add_theme_font_size_override("font_size", 44)
	lbl.add_theme_color_override("font_color", Color(1, 0.95, 0.3))
	lbl.add_theme_color_override("font_shadow_color", Color(0.2, 0.05, 0.05))
	lbl.add_theme_constant_override("shadow_offset_x", 3)
	lbl.add_theme_constant_override("shadow_offset_y", 3)
	lbl.z_index = 100
	var parent := get_tree().current_scene
	parent.add_child(lbl)
	lbl.global_position = global_position + Vector2(-40, -130)
	# ぽよんと拡大して強調(Back ease で行き過ぎ→戻る感じ)
	lbl.scale = Vector2(0.6, 0.6)
	var tween := create_tween()
	tween.tween_property(lbl, "scale", Vector2(1.2, 1.2), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# 頭上で黄色い星 3 つがグルグル回る気絶演出
func _spawn_stunned_stars() -> void:
	var pivot := Node2D.new()
	pivot.name = "StunStars"
	pivot.position = Vector2(0, STAR_Y_OFFSET)
	pivot.z_index = 10
	add_child(pivot)
	for i in STAR_COUNT:
		var star := _make_star_polygon()
		var angle := TAU * float(i) / float(STAR_COUNT)
		star.position = Vector2.RIGHT.rotated(angle) * STAR_ORBIT_RADIUS
		pivot.add_child(star)
	# 無限ループ。プレイヤーが queue_free されるまで回り続ける。
	# TAU(2π)→0 の戻りは角度的に同じなので継ぎ目は見えない
	var tween := create_tween().set_loops()
	tween.tween_property(pivot, "rotation", TAU, STAR_ORBIT_PERIOD)


# 5 つの尖りを持つ星形を Polygon2D で作成
func _make_star_polygon() -> Polygon2D:
	var poly := Polygon2D.new()
	var pts := PackedVector2Array()
	var outer := 9.0
	var inner := 4.0
	var n := 10  # 外/内が交互なので点数は 2*尖り数
	for i in n:
		var r: float = outer if i % 2 == 0 else inner
		var a := TAU * float(i) / float(n) - PI / 2.0
		pts.append(Vector2(cos(a), sin(a)) * r)
	poly.polygon = pts
	poly.color = Color(1.0, 0.9, 0.2)
	return poly


# 画面全体に赤いオーバーレイを出し、段階的にフェードアウト。
# ignore_time_scale=true のタイマーで駒送りするため、ヒットストップ中でも一瞬で消える。
func _spawn_red_flash() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 50  # UI (layer 1) より前面
	get_tree().current_scene.add_child(canvas)
	var flash := ColorRect.new()
	flash.color = Color(1, 0, 0, RED_FLASH_START_ALPHA)
	flash.anchor_right = 1.0
	flash.anchor_bottom = 1.0
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(flash)
	var step_time := RED_FLASH_DURATION / float(RED_FLASH_STEPS)
	for i in RED_FLASH_STEPS:
		await get_tree().create_timer(step_time, true, false, true).timeout
		var a := RED_FLASH_START_ALPHA * (1.0 - float(i + 1) / float(RED_FLASH_STEPS))
		flash.color = Color(1, 0, 0, max(a, 0.0))
	canvas.queue_free()


# アクティブな Camera2D を掴んで、offset をランダムに振る。
# ignore_time_scale=true で実時間進行なのでヒットストップ中も揺れる。
func _shake_camera() -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var original := cam.offset
	var step_time := SHAKE_DURATION / float(SHAKE_STEPS)
	for i in SHAKE_STEPS:
		cam.offset = original + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * SHAKE_AMPLITUDE
		await get_tree().create_timer(step_time, true, false, true).timeout
	cam.offset = original


# ヒットストップ本体: 0 → 0.3 → 1.0 と段階的に戻す
func _run_hitstop() -> void:
	Engine.time_scale = 0.0
	await get_tree().create_timer(HITSTOP_FREEZE, true, false, true).timeout
	Engine.time_scale = HITSTOP_SLOW_SCALE
	await get_tree().create_timer(HITSTOP_SLOW_DURATION, true, false, true).timeout
	Engine.time_scale = 1.0


# 死亡演出の総時間経過後に died を出してゲームオーバー遷移
func _finalize_after_delay() -> void:
	await get_tree().create_timer(DEATH_DURATION, true, false, true).timeout
	# 念のため time_scale を戻しておく(途中で中断された場合の保険)
	Engine.time_scale = 1.0
	died.emit(_death_cause)


# 既存コードとの互換のため残している外部 API
func kill() -> void:
	start_death_sequence("obstacle")


# ============================================================
# アニメーション制御
# ============================================================

# 状態に応じて AnimatedSprite2D のアニメーションを切り替える。
# 死亡中(is_dying)は start_death_sequence で "hit" に切り替え済みなので何もしない。
func _update_animation() -> void:
	if is_dying:
		return
	if is_on_floor():
		_play_if_different(&"run")
	else:
		# ジャンプ上昇中も落下中も同じ "jump" ポーズを使う
		_play_if_different(&"jump")


# 現在と違うアニメ名のときだけ play する。毎フレーム同じ名前で play すると
# 先頭フレームに巻き戻って不自然になるので、この差分チェックが要る。
func _play_if_different(anim_name: StringName) -> void:
	if sprite.animation != anim_name:
		sprite.play(anim_name)


# ============================================================
# 音のフック(空関数 / 将来実装用)
# 例: 子ノードに AudioStreamPlayer を追加し、ここから play() する
# ============================================================

# 衝突時の単発 SE
func play_hit_sound() -> void:
	pass

# 死亡ジングル / BGM 差し替え
func play_death_music() -> void:
	pass
