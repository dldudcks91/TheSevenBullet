# PROTOTYPE - NOT FOR PRODUCTION (임시 스모크 — 검증 끝나면 지운다)
# Question: 무입력 헤드리스로는 안 타는 경로(구매 드래그·자리 교체·유물 구매·패널 구매)가 죽지 않는가?
#           그리고 스폰 스케줄이 두 모드에서 의도대로 도는가?
# Date: 2026-08-11
# 사용: godot --headless --fixed-fps 60 --script prototypes/realtime_defense/_smoke.gd -- adaptive
extends SceneTree

# 사제를 중앙에 두고 전사·궁수·마법사를 섞는다 — 축복과 감산·비율을 동시에 태우기 위한 편성
# 인덱스: 0~2 전사 / 3~5 궁수 / 6~8 마법사 / 9~11 사제
const COMP := [0, 3, 6, 1, 9, 7, 4, 2, 8]
# 네 직업 전부에 유물이 하나씩 걸리도록 고른다 (전사·궁수·마법사·사제).
# 전사 몫은 파쇄로 잡았다 — "딜 0인 칸을 방깎이 되살리는가"가 지금 제일 궁금한 것이라서다.
# 넉백을 보려면 1 → 0 으로 바꾼다.
const RELIC_PICK := [1, 2, 4, 6]

var _proto: Node2D
var _f: int = 0
var _adaptive: bool = false
var _shot_dir: String = ""
# 시점은 "보스가 레인에 살아 있을 때"로 골랐다 — 초반엔 킬이 빨라 빈 레인만 찍힌다
var _shots := {900: "a_early", 3700: "b_mid", 7300: "c_late"}
const SHOT_LAST := 7300


func _initialize() -> void:
	_adaptive = OS.get_cmdline_user_args().has("adaptive")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shots="):
			_shot_dir = a.substr(6)
	var scene: PackedScene = load("res://prototypes/realtime_defense/proto.tscn")
	_proto = scene.instantiate()
	root.add_child(_proto)
	print("=== 모드: %s ===" % ("킬 연동(ADAPTIVE)" if _adaptive else "고정 스케줄(FIXED)"))


func _boss_point() -> Vector2:
	for b in _proto._bosses:
		if not b["dead"]:
			return Vector2(float(b["x"]), float(b["lane_y"]))
	return _proto._cell_rect(4).get_center()


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
		# 유물은 칸이 아니라 유물 슬롯 줄에 놓는다. 발동은 자동이라 눌러줄 것이 없다
		for i in RELIC_PICK.size():
			var rel: Dictionary = _proto.RELICS[RELIC_PICK[i]]
			_proto._shop[0] = {"kind": "relic", "def": rel, "price": int(rel["price"])}
			_drag(_proto._card_rect(0).get_center(), _proto._relic_rect(i).get_center())
		print("유물 %d/%d" % [_proto.RELIC_SLOTS - _proto._empty_relics(), _proto.RELIC_SLOTS])

	if _f == 90:
		_drag(_proto._cell_rect(0).get_center(), _proto._cell_rect(8).get_center())
		_proto._press(_proto.REROLL_RECT.get_center())
		_proto._press(_proto._repair_rect().get_center())
		_proto._press(_proto._upgrade_rect().get_center())
		var before: int = _proto._gold
		_drag(_proto._card_rect(1).get_center(), Vector2(1700.0, 400.0))
		print("빈 곳 드롭 무과금: %s / 배치 유지 %d" % [str(before == _proto._gold), _proto._placed_count()])

	if _f == 120:
		# 유물카드를 칸에 떨구면 무효여야 한다 — 목적지가 문법을 정한다
		var before2: int = _proto._gold
		_proto._shop[1] = {"kind": "relic", "def": _proto.RELICS[1], "price": 55}
		_drag(_proto._card_rect(1).get_center(), _proto._cell_rect(4).get_center())
		# 병사카드를 유물 줄에 떨구는 것도 무효
		var d2: Dictionary = _proto.UNITS[0]
		_proto._shop[2] = {"kind": "unit", "def": d2, "price": int(d2["price"])}
		_drag(_proto._card_rect(2).get_center(), _proto._relic_rect(3).get_center())
		print("잘못된 목적지 무과금: %s" % str(before2 == _proto._gold))

	if _f % 120 == 0:
		_proto._mouse = _proto._card_rect(2).get_center()
	elif _f % 120 == 40:
		_proto._mouse = _proto._cell_rect(4).get_center()
	elif _f % 120 == 80:
		_proto._mouse = _proto.FORECAST_RECT.get_center()
	# 스크린샷은 직전 프레임의 렌더다 — 한 프레임 먼저 상세 카드를 띄울 곳에 마우스를 둔다
	if _shots.has(_f + 1):
		# 후반일수록 보스가 오래 살아 있어서, 보스 카드는 마지막 컷으로 잡는다
		match str(_shots[_f + 1]):
			"a_early": _proto._mouse = _proto._cell_rect(0).get_center()
			"b_mid":   _proto._mouse = _proto.FORECAST_RECT.get_center()
			_:         _proto._mouse = _boss_point()

	if _shot_dir != "" and _shots.has(_f):
		var img: Image = root.get_texture().get_image()
		if img != null:
			img.save_png("%s/%s.png" % [_shot_dir, _shots[_f]])
			print("shot %s" % _shots[_f])
		if _f == SHOT_LAST:
			return true

	if _f % 1800 == 0:
		print("  t=%3.0fs  처치 %2d  성벽 %4d  레인 %d  겹침최대 %d  유물발동 %d" % [
			_proto._elapsed, _proto._killed, int(_proto._wall_hp),
			_proto._bosses.size(), _proto._log_overlap_peak, _proto._log_relic_fires])

	if _proto._phase != 0:
		print("종료: %s  처치 %d/%d  경과 %.1fs  성벽 %d  평균처치 %.1fs  최대겹침 %d" % [
			"클리어" if _proto._phase == 1 else "패배",
			_proto._killed, _proto.RUN_BOSSES, _proto._elapsed, int(_proto._wall_hp),
			_proto._avg_kill(), _proto._log_overlap_peak])
		print("딜 0 타격 %.0f%%  물리 감산 손실 %.0f%%  유물 발동 %d회" % [
			_proto._zero_ratio(), _proto._phys_loss(), _proto._log_relic_fires])
		var times: String = ""
		for t in _proto._log_kill_times:
			times += "%.0f " % float(t)
		print("보스별 처치 소요: %s" % times)
		var per_cell: String = ""
		for sq in _proto._cells:
			if sq == null:
				continue
			per_cell += "%s %d / " % [str(sq["def"]["name"]), int(sq["dmg"])]
		print("칸별 기여: %s" % per_cell)
		return true
	return _f > 36000
