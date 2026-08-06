# PROTOTYPE - NOT FOR PRODUCTION (임시 스모크 — 검증 끝나면 지운다)
# Question: 무입력 헤드리스로는 안 타는 경로(구매 드래그·자리 교체·아이템 발동·패널 구매)가 죽지 않는가?
#           그리고 스폰 스케줄이 두 모드에서 의도대로 도는가?
# Date: 2026-08-05
# 사용: godot --headless --fixed-fps 60 --script prototypes/realtime_defense/_smoke.gd -- adaptive
extends SceneTree

# 사제를 중앙에 두고 궁수·전사·마법사를 섞는다 — 인접 버프와 문턱을 동시에 태우기 위한 편성
const COMP := [3, 0, 6, 3, 9, 7, 1, 4, 2]

var _proto: Node2D
var _f: int = 0
var _adaptive: bool = false
var _shot_dir: String = ""
var _shots := {900: "a_early", 3000: "b_mid", 5400: "c_late"}


func _initialize() -> void:
	_adaptive = OS.get_cmdline_user_args().has("adaptive")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shots="):
			_shot_dir = a.substr(6)
	var scene: PackedScene = load("res://prototypes/realtime_defense/proto.tscn")
	_proto = scene.instantiate()
	root.add_child(_proto)
	print("=== 모드: %s ===" % ("킬 연동(ADAPTIVE)" if _adaptive else "고정 스케줄(FIXED)"))


func _drag(from: Vector2, to: Vector2) -> void:
	_proto._press(from)
	_proto._mouse = to
	_proto._drag_moved = true
	_proto._release(to)


func _process(_delta: float) -> bool:
	_f += 1

	if _f == 30:
		_proto._gold = 100000
		_proto._spawn_mode = 1 if _adaptive else 0
		for i in 9:
			var d: Dictionary = _proto.UNITS[COMP[i]]
			_proto._shop[0] = {"kind": "unit", "def": d, "price": int(d["price"])}
			_drag(_proto._card_rect(0).get_center(), _proto._cell_rect(i).get_center())
		print("배치 %d/9" % _proto._placed_count())

	if _f == 60:
		for i in 9:
			_proto._shop[0] = {"kind": "item", "def": _proto.ITEMS[i % 3], "price": 50}
			_drag(_proto._card_rect(0).get_center(), _proto._cell_rect(i).get_center())
		var armed: int = 0
		for sq in _proto._cells:
			if sq != null and not sq["item"].is_empty():
				armed += 1
		print("아이템 장착 %d/9" % armed)

	if _f == 90:
		_drag(_proto._cell_rect(0).get_center(), _proto._cell_rect(8).get_center())
		_proto._press(_proto.REROLL_RECT.get_center())
		_proto._press(_proto._repair_rect().get_center())
		_proto._press(_proto._upgrade_rect().get_center())
		var before: int = _proto._gold
		_drag(_proto._card_rect(1).get_center(), Vector2(1700.0, 400.0))
		print("빈 곳 드롭 무과금: %s / 배치 유지 %d" % [str(before == _proto._gold), _proto._placed_count()])

	if _f > 100:
		for i in 9:
			_proto._fire_item(i)

	if _f % 120 == 0:
		_proto._mouse = _proto._card_rect(2).get_center()
	elif _f % 120 == 60:
		_proto._mouse = _proto._cell_rect(4).get_center()
	# 스크린샷은 직전 프레임의 렌더다 — 한 프레임 먼저 툴팁을 치운다
	if _shots.has(_f + 1):
		_proto._mouse = Vector2(-500.0, -500.0)

	if _shot_dir != "" and _shots.has(_f):
		var img: Image = root.get_texture().get_image()
		if img != null:
			img.save_png("%s/%s.png" % [_shot_dir, _shots[_f]])
			print("shot %s" % _shots[_f])
		if _f == 5400:
			return true

	if _f % 1800 == 0:
		print("  t=%3.0fs  처치 %2d  성벽 %4d  레인 %d  겹침최대 %d" % [
			_proto._elapsed, _proto._killed, int(_proto._wall_hp),
			_proto._bosses.size(), _proto._log_overlap_peak])

	if _proto._phase != 0:
		var avg: float = 0.0
		for t in _proto._log_kill_times:
			avg += float(t)
		if not _proto._log_kill_times.is_empty():
			avg /= float(_proto._log_kill_times.size())
		print("종료: %s  처치 %d/%d  경과 %.1fs  성벽 %d  평균처치 %.1fs  최대겹침 %d  막힘 %.0f%%" % [
			"클리어" if _proto._phase == 1 else "패배",
			_proto._killed, _proto.RUN_BOSSES, _proto._elapsed, int(_proto._wall_hp), avg,
			_proto._log_overlap_peak,
			(float(_proto._log_blocked_hits) / maxf(1.0, float(_proto._log_total_hits))) * 100.0])
		var times: String = ""
		for t in _proto._log_kill_times:
			times += "%.0f " % float(t)
		print("보스별 처치 소요: %s" % times)
		return true
	return _f > 36000
