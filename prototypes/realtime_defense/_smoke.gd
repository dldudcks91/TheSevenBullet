# PROTOTYPE - NOT FOR PRODUCTION (임시 스모크 — 검증 끝나면 지운다)
# Question: 무입력 헤드리스로는 안 타는 경로(구매 드래그·합류·빼내기·유물 구매·패널 구매)가
#           죽지 않는가? 직업 7종의 발동과 스킬 effect가 실제로 전부 도는가?
# Date: 2026-08-14
# 사용: godot --headless --fixed-fps 60 --script prototypes/realtime_defense/_smoke.gd -- adaptive
extends SceneTree

# 인덱스가 아니라 **unit_id** 로 고른다 — 매대 풀이 CSV에서 오므로 순서에 기대면 안 된다.
# 여섯 직업이 전부 타도록 골랐고, 사제를 중앙(4)에 두어 축복이 이웃 아닌 랜덤 대상으로
# 나가는 것까지 본다. 스킬 effect도 서로 다른 것만 모았다:
#   전사 HASTE / 전사 EMPOWER_STRIKE / 소드마스터 EXTRA_STRIKE / 소드마스터 MAGIC_STRIKE /
#   궁수 CRIT_AMP / 궁수 EXTRA_SHOT / 암살자 VULNERABLE / 마법사 NUKE_FREEZE / 사제 BUFF_ATK
const COMP := [
	"U_VK_BERSERKER",   # 0 전사 — HASTE
	"U_DE_SWORD",       # 1 소드마스터 — EXTRA_STRIKE
	"U_DE_ARCHER",      # 2 궁수 — CRIT_AMP
	"U_UD_SKELARCHER",  # 3 궁수 — EXTRA_SHOT
	"U_HUM_PRINCE",     # 4 사제 — BUFF_ATK (중앙)
	"U_UD_LICH",        # 5 마법사 — NUKE_FREEZE
	"U_DM_HIGH",        # 6 전사 — EMPOWER_STRIKE
	"U_UD_DREADKNIGHT", # 7 소드마스터 — MAGIC_STRIKE
	"U_DE_ASSASSIN",    # 8 암살자 — VULNERABLE
]
# 한 판에 9칸뿐이라 effect 17종이 한 번에 다 안 돈다. 중반에 판을 통째로 갈아
# 나머지 8종을 태운다 — 겸사겸사 "재배치는 즉시·무료"도 실제로 밟는다.
const COMP2 := [
	"U_HUM_MAGE",       # 마법사 — NUKE
	"U_BM_RABBIT",      # 마법사 — NUKE_RANDOM (원소를 매번 굴린다)
	"U_BM_DEER",        # 사제 — BUFF_RANDOM
	"U_DM_DEMONESS",    # 사제 — PACT_BUFF
	"U_UD_NECROMANCER", # 사제 — CLEANSE (3막 주박이 걸려야 정화할 것이 생긴다)
	"U_DM_FIREIMP",     # 궁수 — CRIT_BONUS_FLAT
	"U_UD_REAPER",      # 암살자 — HEAVY_STRIKE
	"U_BM_CAT",         # 암살자 — GOLD_STEAL
	"U_HUM_ARCHER",     # 궁수 — HASTE (궁수 쪽 발동도 본다)
]
const SWAP_AT := 4200                 # ≈70s — 앞판의 리듬을 충분히 본 뒤
# 유물은 이제 굴려진다 — 봇은 **유니크 4종을 직접 만들어** 동사 경로를 태운다.
# 네 직업에 하나씩 걸리게 골랐다 (소드마스터 파쇄 / 궁수 화상 / 마법사 빙결 / 사제 취약).
# 밀어내기를 보려면 "breaker" 를 "hammer" 로 바꾼다.
const UNIQUE_PICK := ["breaker", "brand", "fetter", "mark"]
# 전술카드 세 종류를 하나씩 — 칸·골드·규칙이 전부 도는지 본다.
# 목록이 tactic_cards.csv에서 오므로 카탈로그 id를 쓴다. t_pilum은 카탈로그 밖 실험 카드다.
const TACTIC_PICK := ["TC_CANNAE", "TC_GOLD_TIME", "t_pilum"]

var _proto: Node2D
var _f: int = 0
var _adaptive: bool = false
var _shot_dir: String = ""
# 킬이 매대를 갱신하지 않는다가 이번 규칙 변경의 핵심이라, 킬 전후의 매대를 대조한다
var _prev_kills: int = 0
var _prev_sig: String = ""
var _shop_kept: int = 0
var _shop_broke: int = 0
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


func _unique_by_id(id: String) -> Dictionary:
	for u in _proto.RELIC_UNIQUES:
		if str(u["id"]) == id:
			return _proto._make_unique(u)
	push_error("그런 유니크가 없다: %s" % id)
	return {}


func _tactic_by_id(id: String) -> Dictionary:
	for t in _proto.TACTICS:
		if str(t["id"]) == id:
			return t
	push_error("그런 전술카드가 없다: %s" % id)
	return {}


# 레이아웃 검증용 매대 채우기 — 레어 유물(옵션 4줄) · 「칸」 비움 조건 · 골드 · 규칙.
# 봇은 리롤하지 않고 킬은 매대를 갱신하지 않으므로, 여기 심은 카드는 촬영 시점까지 남는다.
func _stock_shop_for_shot() -> void:
	var rel: Dictionary = _proto._roll_relic()
	var guard: int = 0
	while str(rel["grade"]) != "rare" and guard < 300:
		rel = _proto._roll_relic()
		guard += 1
	_proto._shop[0] = {"kind": "relic", "def": rel, "price": int(rel["price"])}
	_proto._shop[1] = {"kind": "tactic", "def": _tactic_by_id("TC_CHEONGYA"), "price": 120}
	_proto._shop[2] = {"kind": "tactic", "def": _tactic_by_id("TC_GOLD_SHIELD"), "price": 85}
	_proto._shop[3] = {"kind": "tactic", "def": _tactic_by_id("TC_RULE_CRITDMG"), "price": 85}


func _boss_point() -> Vector2:
	for b in _proto._bosses:
		if not b["dead"]:
			return Vector2(float(b["x"]), float(b["lane_y"]))
	return _proto._cell_rect(4).get_center()


func _shop_sig() -> String:
	var s: String = ""
	for c in _proto._shop:
		s += ("-" if c == null else str(c["def"]["name"])) + "|"
	return s


func _drag(from: Vector2, to: Vector2) -> void:
	_proto._press(from)
	_proto._mouse = to
	_proto._drag_moved = true
	_proto._release(to)


# 병사카드를 슬롯 0에 꽂아 넣고 칸으로 끌어다 놓는다. 매대 풀이 CSV에서 오므로
# 원하는 유닛이 뜰 때까지 리롤할 수는 없다 — 봇은 카드를 직접 만들어 경로만 태운다.
func _buy(unit_id: String, cell: int, count: int) -> void:
	var d: Dictionary = _proto._unit_by_id(unit_id)
	_proto._shop[0] = {"kind": "unit", "def": d, "count": count,
		"price": count * int(d["unit_price"])}
	_drag(_proto._card_rect(0).get_center(), _proto._cell_rect(cell).get_center())


# 상한까지 부어 채운다 — 병사카드 합류제가 이번 개조의 핵심이라 실제로 밟아본다.
func _fill(cell: int) -> void:
	var sq = _proto._cells[cell]
	if sq == null:
		return
	var uid: String = str(sq["def"]["id"])
	var cap: int = int(sq["def"]["cap"])
	var guard: int = 0
	while int(_proto._cells[cell]["members"]) < cap and guard < 12:
		_buy(uid, cell, cap)
		guard += 1


# 칸을 비운다 — 다른 유닛으로 바꾸려면 먼저 빼내야 한다. 격자 밖(레인)으로 끌면 해체된다.
func _pull(cell: int) -> void:
	if _proto._cells[cell] == null:
		return
	_drag(_proto._cell_rect(cell).get_center(), Vector2(1700.0, 300.0))


func _process(_delta: float) -> bool:
	_f += 1

	if _f == 30:
		_proto._gold = 100000
		_proto._spawn_mode = 1 if _adaptive else 0
		print("매대 풀 %d종" % _proto.UNITS.size())
		for i in 9:
			_buy(COMP[i], i, 1)
		print("배치 %d/9 · 인원 %d/%d" %
			[_proto._placed_count(), _proto._crew_now(), _proto._crew_cap()])
		# 합류제 — 한 장 놓은 뒤 상한까지 부어 채운다. 밸런스가 아니라 경로 검증이다
		for i in 9:
			_fill(i)
		print("채움 후 인원 %d/%d" % [_proto._crew_now(), _proto._crew_cap()])
		# 다른 유닛의 칸에는 못 놓는다 — 취소·무과금이어야 한다
		var g0: int = _proto._gold
		var m0: int = int(_proto._cells[0]["members"])
		_buy(COMP[1], 0, 2)
		print("다른 유닛 칸 거부: %s" % str(g0 == _proto._gold and m0 == int(_proto._cells[0]["members"])))
		# 만석에 부으면 결제는 되고 초과분은 사라진다
		var cap0: int = int(_proto._cells[0]["def"]["cap"])
		_buy(COMP[0], 0, cap0)
		print("만석 초과분 소멸: %s" % str(int(_proto._cells[0]["members"]) == cap0))

	if _f == 60:
		# 유물은 칸이 아니라 유물 슬롯 줄에 놓는다. 발동은 자동이라 눌러줄 것이 없다
		for i in UNIQUE_PICK.size():
			var rel: Dictionary = _unique_by_id(str(UNIQUE_PICK[i]))
			_proto._shop[0] = {"kind": "relic", "def": rel, "price": int(rel["price"])}
			_drag(_proto._card_rect(0).get_center(), _proto._relic_rect(i).get_center())
		print("유물 %d/%d" % [_proto.RELIC_SLOTS - _proto._empty_relics(), _proto.RELIC_SLOTS])
		# 전술카드 — 전술 슬롯 줄에만 놓인다
		for i in TACTIC_PICK.size():
			var tc: Dictionary = _tactic_by_id(str(TACTIC_PICK[i]))
			_proto._shop[0] = {"kind": "tactic", "def": tc, "price": int(tc["price"])}
			_drag(_proto._card_rect(0).get_center(), _proto._tactic_rect(i).get_center())
		var held: int = 0
		for t in _proto._tactics:
			if t != null:
				held += 1
		print("전술 %d/%d" % [held, _proto.TACTIC_SLOTS])
		# 전술카드를 칸에 떨구면 무효여야 한다 — 목적지가 문법을 정한다
		var g1: int = _proto._gold
		_proto._shop[0] = {"kind": "tactic", "def": _tactic_by_id("TC_HAKIK"), "price": 85}
		_drag(_proto._card_rect(0).get_center(), _proto._cell_rect(4).get_center())
		print("전술카드 칸 드롭 무과금: %s" % str(g1 == _proto._gold))

	if _f == 90:
		_drag(_proto._cell_rect(0).get_center(), _proto._cell_rect(8).get_center())
		_proto._press(_proto.REROLL_RECT.get_center())
		_proto._press(_proto.WALL_RECT.get_center())   # 수리 = 성벽 클릭 (3차)
		_proto._try_upgrade()   # 업그레이드 = 성벽 우클릭 (3차) — 봇은 함수를 직접 부른다
		var before: int = _proto._gold
		_drag(_proto._card_rect(1).get_center(), Vector2(1700.0, 400.0))
		print("빈 곳 드롭 무과금: %s / 배치 유지 %d" % [str(before == _proto._gold), _proto._placed_count()])

	if _f == 120:
		# 유물카드를 칸에 떨구면 무효여야 한다 — 목적지가 문법을 정한다
		var before2: int = _proto._gold
		_proto._shop[1] = {"kind": "relic", "def": _unique_by_id("breaker"), "price": 55}
		_drag(_proto._card_rect(1).get_center(), _proto._cell_rect(4).get_center())
		# 병사카드를 유물 줄에 떨구는 것도 무효
		var d2: Dictionary = _proto.UNITS[0] as Dictionary
		_proto._shop[2] = {"kind": "unit", "def": d2, "count": 1, "price": int(d2["unit_price"])}
		_drag(_proto._card_rect(2).get_center(), _proto._relic_rect(3).get_center())
		print("잘못된 목적지 무과금: %s" % str(before2 == _proto._gold))

	if _f == SWAP_AT:
		# 칸을 다른 유닛으로 바꾸려면 **먼저 빼내야 한다.** 빼기 → 새 유닛 → 상한까지 채우기
		for i in 9:
			_pull(i)
		print("빼내기 후 배치 %d/9" % _proto._placed_count())
		for i in 9:
			_buy(COMP2[i], i, 1)
			_fill(i)
		print("판 교체 %d/9 · 인원 %d/%d (t=%.0fs)" % [_proto._placed_count(),
			_proto._crew_now(), _proto._crew_cap(), _proto._elapsed])

	if _f % 120 == 0:
		_proto._mouse = _proto._card_rect(2).get_center()
	elif _f % 120 == 40:
		_proto._mouse = _proto._cell_rect(4).get_center()
	elif _f % 120 == 80:
		_proto._mouse = _proto.FORECAST_RECT.get_center()
	# 스크린샷은 지난 프레임의 렌더인데, 창 렌더가 fixed-fps를 못 따라와 몇십 프레임 늦을 수
	# 있다 — 그래서 촬영 전 60프레임 내내 같은 곳에 호버를 붙잡아 둔다.
	# 후반일수록 보스가 오래 살아 있어서, 보스 카드는 마지막 컷으로 잡는다.
	# 앞의 두 컷은 "제일 길게 그려지는" 카드들을 매대에 심고 찍는다 — 레어 유물(옵션 4줄)과
	# 전술카드 세 얼굴이 카드 높이 안에 들어가는지가 이 컷의 질문이다
	if _shots.has(_f + 60) and str(_shots[_f + 60]) == "a_early":
		_stock_shop_for_shot()
	for sf in _shots:
		if _f >= int(sf) - 60 and _f < int(sf):
			match str(_shots[sf]):
				"a_early":
					_proto._mouse = _proto._card_rect(0).get_center()
				"b_mid":
					# 슬롯 4는 심지 않은 자연 매물 — 병사카드 상세(정체/능력치/스킬 구조)를 찍는다
					_proto._mouse = _proto._card_rect(4).get_center()
				_:
					_proto._mouse = _boss_point()

	if _shot_dir != "" and _shots.has(_f):
		var img: Image = root.get_texture().get_image()
		if img != null:
			img.save_png("%s/%s.png" % [_shot_dir, _shots[_f]])
			print("shot %s" % _shots[_f])
		if _f == SHOT_LAST:
			return true

	# 킬 프레임에 매대가 그대로인가 — "강제 갱신은 없다"가 실제로 지켜지는지 본다
	var sig: String = _shop_sig()
	if _proto._killed > _prev_kills:
		_prev_kills = _proto._killed
		if sig == _prev_sig:
			_shop_kept += 1
		else:
			_shop_broke += 1
	_prev_sig = sig

	if _f % 1800 == 0:
		print("  t=%3.0fs  처치 %2d  성벽 %4d  레인 %d  겹침최대 %d  골드 %d  유물 %d  스킬 %d" % [
			_proto._elapsed, _proto._killed, int(_proto._wall_hp),
			_proto._bosses.size(), _proto._log_overlap_peak, _proto._gold,
			_proto._log_relic_fires, _proto._skill_fire_total()])

	if _proto._phase != 0:
		print("종료: %s  처치 %d/%d  경과 %.1fs  성벽 %d  평균처치 %.1fs  최대겹침 %d" % [
			"클리어" if _proto._phase == 1 else "패배",
			_proto._killed, _proto.RUN_BOSSES, _proto._elapsed, int(_proto._wall_hp),
			_proto._avg_kill(), _proto._log_overlap_peak])
		print("딜 0 타격 %.0f%%  빗나감 %.0f%%  물리 감산 손실 %.0f%%  유물 발동 %d회" % [
			_proto._zero_ratio(), _proto._miss_ratio(), _proto._phys_loss(),
			_proto._log_relic_fires])
		print("인원 채움 %d/%d" % [_proto._crew_now(), _proto._crew_cap()])
		var times: String = ""
		for t in _proto._log_kill_times:
			times += "%.0f " % float(t)
		print("보스별 처치 소요: %s" % times)
		var per_cell: String = ""
		for sq in _proto._cells:
			if sq == null:
				continue
			per_cell += "%s(%s) %d / " % [str(sq["def"]["name"]),
				str(_proto.JOBS[sq["def"]["job"]]["name"]), int(sq["dmg"])]
		print("칸별 기여: %s" % per_cell)
		# 직업 리듬이 실제로 도는지 — effect 별로 몇 번 터졌는가
		var fires: String = ""
		var keys: Array = _proto._log_skill_fires.keys()
		keys.sort()
		for k in keys:
			fires += "%s %d / " % [str(k), int(_proto._log_skill_fires[k])]
		print("스킬 발동(effect별 %d종): %s" % [keys.size(), fires])
		print("킬 시 매대 유지 %d회 / 갈림 %d회  · 남은 골드 %d · 리롤가 %d" %
			[_shop_kept, _shop_broke, _proto._gold, _proto._reroll_price])
		return true
	return _f > 36000
