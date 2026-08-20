# PROTOTYPE - NOT FOR PRODUCTION (밸런스 측정 봇 — 검증 끝나면 지운다)
# Question: "아무리 초보"가 플레이해도 1막(오크)이 깨지는가?
#           초보 모델 = 리롤 모름(매대가 다 비면 그제야 리롤) · 왼쪽부터 살 수 있는 카드를
#           그냥 삼 · 빈 칸에 순서대로 배치 · 1초에 한 행동 · 수리는 성벽이 빨개져야(35%) 누름.
# Date: 2026-08-17
# 사용: godot --headless --fixed-fps 60 --script prototypes/realtime_defense/_balance_bot.gd
#       -- seeds=10 [novice|basic]   (novice = 수리도 안 함)
extends SceneTree

var _proto: Node2D
var _f: int = 0
var _seed_i: int = 0
var _seeds: int = 10
var _novice: bool = false             # true면 수리마저 안 한다 — 최악의 초보
var _act1_at: float = -1.0
var _results: Array = []
var _done: bool = false
const RUN_CAP := 480.0                # 한 판 상한(초) — 이 넘게 끌리면 "지지부진"으로 기록
const ACT1_KILLS := 8                 # 하급 5 + 정예 2 + 대족장 = 1막 돌파선
const STEPS := 32                     # 엔진 프레임당 시뮬 스텝 — 실시간의 32배로 돌린다
const DT := 1.0 / 60.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seeds="):
			_seeds = int(a.substr(6))
		if a == "novice":
			_novice = true
	var scene: PackedScene = load("res://prototypes/realtime_defense/proto.tscn")
	_proto = scene.instantiate()
	root.add_child(_proto)
	# 엔진이 부르는 _process를 끄고 봇이 직접 여러 번 돌린다 — 실시간보다 빨리 재기 위해서다
	_proto.set_process(false)
	print("=== 초보 봇 · %s · %d시드 ===" % ["수리 없음" if _novice else "수리 35%", _seeds])


func _begin_seed() -> void:
	_proto._rng.seed = hash("bal-%d" % _seed_i)
	_proto._start_run()
	_f = 0
	_act1_at = -1.0


func _drag(from: Vector2, to: Vector2) -> void:
	_proto._press(from)
	_proto._mouse = to
	_proto._drag_moved = true
	_proto._release(to)


# 이 병사카드가 놓일 곳 — 같은 유닛의 안 찬 부대가 먼저, 없으면 첫 빈 칸
func _dest_cell(d: Dictionary) -> int:
	for i in 9:
		var sq = _proto._cells[i]
		if sq != null and str(sq["def"]["id"]) == str(d["id"]) \
				and int(sq["members"]) < int(sq["def"]["cap"]):
			return i
	for i in 9:
		if _proto._cells[i] == null:
			return i
	return -1


func _free_slot(arr: Array) -> int:
	for i in arr.size():
		if arr[i] == null:
			return i
	return -1


# 1초에 한 행동. 왼쪽부터 "살 수 있고 놓을 곳 있는" 카드 하나를 사는 게 전부다.
func _act_once() -> void:
	if not _novice and _proto._wall_hp < _proto._wall_max * 0.35 \
			and _proto._gold >= _proto._repair_price:
		_proto._try_repair()
		return
	var empty: int = 0
	for i in _proto.SHOP_SLOTS:
		var card = _proto._shop[i]
		if card == null:
			empty += 1
			continue
		if _proto._gold < int(card["price"]):
			continue
		match str(card["kind"]):
			"unit":
				var to: int = _dest_cell(card["def"])
				if to < 0:
					continue
				_drag(_proto._card_rect(i).get_center(), _proto._cell_rect(to).get_center())
				return
			"relic":
				var rs: int = _free_slot(_proto._relics)
				if rs < 0:
					continue
				_drag(_proto._card_rect(i).get_center(), _proto._relic_rect(rs).get_center())
				return
			_:
				var ts: int = _free_slot(_proto._tactics)
				if ts < 0:
					continue
				_drag(_proto._card_rect(i).get_center(), _proto._tactic_rect(ts).get_center())
				return
	# 초보도 매대가 텅 비면 리롤 버튼을 눌러본다 — 그 전에는 존재를 모른다
	if empty >= _proto.SHOP_SLOTS and _proto._gold >= _proto._reroll_price:
		_proto._press(_proto.REROLL_RECT.get_center())


func _finish_seed() -> void:
	var outcome: String = "지지부진"
	if _proto._phase == 1:
		outcome = "클리어"
	elif _proto._phase == 2:
		outcome = "패배"
	var times: String = ""
	for t in _proto._log_kill_times:
		times += "%.0f " % float(t)
	_results.append({"act1": _act1_at, "outcome": outcome, "killed": _proto._killed})
	print("시드 %2d  %s  처치 %2d/17  1막 %s  t=%.0fs  성벽 %d  골드 %d  처치소요[%s]" % [
		_seed_i, outcome, _proto._killed,
		("%.0fs" % _act1_at) if _act1_at >= 0.0 else "실패",
		_proto._elapsed, int(_proto._wall_hp), _proto._gold, times.strip_edges()])


func _process(_delta: float) -> bool:
	if _done:
		return true
	if _f == 0 and _seed_i == 0:
		_begin_seed()
	for _s in STEPS:
		_f += 1
		_proto._process(DT)
		if _f % 60 == 30:
			_act_once()
		if _act1_at < 0.0 and _proto._killed >= ACT1_KILLS:
			_act1_at = _proto._elapsed

		if _proto._phase != 0 or _proto._elapsed > RUN_CAP:
			_finish_seed()
			_seed_i += 1
			if _seed_i >= _seeds:
				var a1: int = 0
				var clr: int = 0
				for r in _results:
					if float(r["act1"]) >= 0.0:
						a1 += 1
					if str(r["outcome"]) == "클리어":
						clr += 1
				print("=== 합계: 1막 돌파 %d/%d · 런 클리어 %d/%d ===" % [a1, _seeds, clr, _seeds])
				_done = true
				return true
			_begin_seed()
	return false
