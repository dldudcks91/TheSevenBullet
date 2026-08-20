# PROTOTYPE - NOT FOR PRODUCTION (임시 스모크 — 검증 끝나면 지운다)
# Question: 5차 개편(던전 구조 · 격자 상시 정비 화면)의 새 경로가 죽지 않는가?
#           팩 구매→개봉→**제시에서 격자로 바로 드래그** / 클릭 택1→트레이 / 빈 칸 배치 / 점유 칸 드롭 거부 /
#           빼내기 / 스킬카드 발동·사기 소모·**구간 버프 상실** / 「전투 시작」 전환 /
#           핵심 전멸 조기 종료 / **타임아웃 정산** / 일반 연속 스폰 / 막보스 상시 표시 /
#           유닛 고유 스킬 effect 20종이 전부 도는가
# Date: 2026-08-21
# 사용: godot --headless --fixed-fps 60 --script prototypes/realtime_defense/_smoke.gd -- adaptive
#       godot --fixed-fps 60 --script prototypes/realtime_defense/_smoke.gd -- shots=<폴더>
extends SceneTree

# 인덱스가 아니라 **unit_id** 로 고른다 — 팩 풀이 CSV에서 오므로 순서에 기대면 안 된다.
# effect 20종을 세 판에 나눠 태운다(한 판은 9칸뿐이다). 판 교체는 정비에서 일어나므로
# 겸사겸사 "빼내기 → 빈 칸 → 새 카드"의 4차 배치 문법을 매번 밟는다.
const COMP_A := [
	"U_VK_BERSERKER",   # 전사 — HASTE_STACK (광란 스택화, 2026-08-19 신규)
	"U_DE_SWORD",       # 소드마스터 — EXTRA_STRIKE
	"U_DE_ARCHER",      # 궁수 — CRIT_AMP
	"U_UD_SKELARCHER",  # 궁수 — EXTRA_SHOT
	"U_HUM_PRINCE",     # 사제 — BUFF_ATK (중앙)
	"U_UD_LICH",        # 마법사 — NUKE_FREEZE
	"U_DM_HIGH",        # 전사 — EMPOWER_STRIKE
	"U_UD_DREADKNIGHT", # 소드마스터 — MAGIC_STRIKE
	"U_DE_ASSASSIN",    # 암살자 — VULNERABLE
]
const COMP_B := [
	"U_HUM_MAGE",       # 마법사 — NUKE
	"U_BM_RABBIT",      # 마법사 — NUKE_RANDOM
	"U_BM_DEER",        # 사제 — BUFF_RANDOM
	"U_DM_DEMONESS",    # 사제 — PACT_BUFF
	"U_UD_NECROMANCER", # 사제 — CLEANSE (3막 주박이 걸려야 정화할 것이 생긴다)
	"U_DM_FIREIMP",     # 궁수 — CRIT_BONUS_FLAT
	"U_UD_REAPER",      # 암살자 — HEAVY_STRIKE
	"U_BM_CAT",         # 암살자 — GOLD_STEAL
	"U_HUM_ARCHER",     # 궁수 — HASTE
]
# 2026-08-19 커밋으로 새로 생긴 둘. 나머지 일곱은 화력용으로 A에서 가져온다
const COMP_C := [
	"U_BM_PANDA",       # 전사 — RANDOM_STACK (취권, 신규)
	"U_BM_FOX",         # 소드마스터 — MAGIC_STRIKE_RANDOM (여우불, 신규)
	"U_DE_SWORD", "U_DE_ARCHER", "U_UD_SKELARCHER", "U_HUM_PRINCE",
	"U_UD_LICH", "U_DM_HIGH", "U_DE_ASSASSIN",
]
# 판 교체가 일어나는 던전 인덱스 (정비에서). 던전은 4개뿐이다:
# A = 던전 1 · 던전 2(정산 검증·5s 컷) / B = 던전 3 (3막 주박이 걸려야 CLEANSE가 돈다) / C = 던전 4
const SWAP_B_ROUND := 2
const SWAP_C_ROUND := 3
# **정산 경로를 확정적으로 밟는 던전.** 전투 시작 직후 제한시간을 몇 초로 줄여
# 반드시 타임아웃이 나게 한다. (격자를 비우는 방식은 성벽이 먼저 깨져 정산까지 못 간다)
# 던전 1은 안 된다 — 첫 정비는 경로 검증 분기로 처리돼 제한시간 컷이 안 걸린다
const SETTLE_ROUND := 1
const SETTLE_LIMIT := 5.0

const SKILL_PICK := ["sc_push", "sc_chill", "sc_clean", "sc_shred", "sc_fire"]
# 유물은 3차 모델 그대로다(4차에서 재정의를 의도적으로 뺐다) — 유니크 4종으로 동사 경로만 태운다
const UNIQUE_PICK := ["breaker", "brand", "fetter", "mark"]
# **「로마의 필룸」(최소 보장)은 일부러 안 든다** — 플로어가 딜 0을 없애 「딜 0 타격 %」
# 지표가 통째로 0%로 읽힌다(3차에서 확인된 것). 감산 세계가 유지되는지를 봐야 하므로 뺐다
const TACTIC_PICK := ["TC_CANNAE", "TC_HAKIK", "TC_RULE_CRITDMG"]

var _proto: Node2D
var _f: int = 0
var _adaptive: bool = false
var _shot_dir: String = ""

var _fail: Array = []
var _pass: Array = []
var _prep_done: int = -1              # 이 라운드의 정비를 이미 처리했는가
var _rounds_early: int = 0
var _rounds_settled: int = 0
var _last_round_seen: int = -1
var _bossbar_ok: int = 0
var _card_tries: int = 0
var _shot_stage: int = 0
var _shot_hold: int = 0
var _shot_done: int = 0


func _initialize() -> void:
	_adaptive = OS.get_cmdline_user_args().has("adaptive")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shots="):
			_shot_dir = a.substr(6)
	var scene: PackedScene = load("res://prototypes/realtime_defense/proto.tscn")
	_proto = scene.instantiate()
	root.add_child(_proto)
	print("=== 모드: %s ===" % ("킬 연동(ADAPTIVE)" if _adaptive else "고정 스케줄(FIXED)"))


func _ck(name: String, ok: bool) -> void:
	if ok:
		_pass.append(name)
	else:
		_fail.append(name)
	print("  [%s] %s" % ["PASS" if ok else "FAIL", name])


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


func _drag(from: Vector2, to: Vector2) -> void:
	_proto._press(from)
	_proto._mouse = to
	_proto._drag_moved = true
	_proto._release(to)


# 팩 랜덤을 기다릴 수 없으므로 봇은 **트레이 카드를 직접 만들어** 배치 경로만 태운다.
# (팩 구매→제시→택1 경로 자체는 아래 _path_checks 가 진짜로 밟는다)
func _tray_put(card: Dictionary) -> void:
	_proto._tray.clear()
	_proto._tray.append(card)


func _hold_unit(unit_id: String, count: int) -> void:
	var d: Dictionary = _proto._unit_by_id(unit_id)
	_tray_put({"kind": "unit", "def": d,
		"count": count if count > 0 else int(d["cap"])})


func _place(unit_id: String, cell: int) -> void:
	_hold_unit(unit_id, 0)
	_drag(_proto._tray_rect(0).get_center(), _proto._cell_rect(cell).get_center())
	_proto._tray.clear()          # 실패해도 다음 카드를 위해 손을 비운다


func _pull(cell: int) -> void:
	if _proto._cells[cell] == null:
		return
	_drag(_proto._cell_rect(cell).get_center(), Vector2(1700.0, 300.0))


func _set_comp(comp: Array) -> void:
	for i in 9:
		_pull(i)
	for i in 9:
		_place(str(comp[i]), i)


# ─── 경로 검증 — 첫 정비에서 한 번만 ─────────────────────────────────────
func _path_checks() -> void:
	_proto._gold = 100000
	_proto._spawn_mode = 1 if _adaptive else 0
	print("유닛팩 풀 %d종 / 스킬카드 %d종" % [_proto.UNITS.size(), _proto.SKILL_CARDS.size()])
	_ck("유닛팩 풀 22종", _proto.UNITS.size() == 22)

	# 1) 팩 구매 → 3장 제시 → 클릭 택1 (나머지 소멸 → 트레이로)
	var g0: int = _proto._gold
	var bought: bool = _proto._try_buy_pack("unit")
	_ck("팩 구매 — 3장 제시", bought and _proto._offer.size() == 3
		and _proto._gold == g0 - int(_proto.PACKS[0]["price"]))
	# 제시 중에는 다른 팩을 못 산다 — 택1이 끝나야 다음 판단이다
	var g1: int = _proto._gold
	_proto._try_buy_pack("tactic")
	_ck("제시 중 추가 구매 차단", _proto._gold == g1 and _proto._offer.size() == 3)
	var picked: bool = _proto._pick_offer(1)
	_ck("택1 — 트레이로", picked and _proto._tray.size() == 1 and _proto._offer.is_empty())
	_proto._tray.clear()

	# 1b) **제시에서 격자로 바로 드래그** — "팩에서 바로 전투에 넣는다"(사용자 확정 2차).
	# 유닛팩을 다시 열어 제시 0번을 빈 칸 4로 끌어다 놓는다 — 배치되고 나머지는 소멸한다
	_proto._try_buy_pack("unit")
	_drag(_proto._offer_rect(0).get_center(), _proto._cell_rect(4).get_center())
	_ck("제시 → 격자 바로 배치 (나머지 소멸)",
		_proto._cells[4] != null and _proto._offer.is_empty() and _proto._tray.is_empty())
	_drag(_proto._cell_rect(4).get_center(), Vector2(1700.0, 300.0))   # 빼서 판을 비운다

	# 2) 병사카드는 **빈 칸에만** 놓인다
	_place(str(COMP_A[0]), 0)
	_ck("빈 칸 배치", _proto._cells[0] != null)

	# 3) **점유 칸 드롭 거부** — 합류제 폐지가 실제로 지켜지는가
	var before_id: String = str(_proto._cells[0]["def"]["id"])
	var before_n: int = int(_proto._cells[0]["members"])
	_hold_unit(str(COMP_A[0]), 2)                 # 같은 유닛 — 3차라면 합쳐졌다
	_drag(_proto._tray_rect(0).get_center(), _proto._cell_rect(0).get_center())
	var same_kept: bool = not _proto._tray.is_empty() \
		and int(_proto._cells[0]["members"]) == before_n
	_hold_unit(str(COMP_A[1]), 2)                 # 다른 유닛
	_drag(_proto._tray_rect(0).get_center(), _proto._cell_rect(0).get_center())
	var other_kept: bool = not _proto._tray.is_empty() \
		and str(_proto._cells[0]["def"]["id"]) == before_id
	_ck("점유 칸 드롭 거부 (같은 유닛 — 합류 없음)", same_kept)
	_ck("점유 칸 드롭 거부 (다른 유닛)", other_kept)
	_proto._tray.clear()

	# 4) 빼내기 — 격자 밖으로. 환불은 없다
	_pull(0)
	_ck("빼내기", _proto._cells[0] == null and _proto._placed_count() == 0)

	# 5) 잘못된 목적지 — 카드가 트레이에 남아야 한다(결제는 이미 끝났으므로 잃으면 안 된다)
	_hold_unit(str(COMP_A[0]), 0)
	_drag(_proto._tray_rect(0).get_center(), Vector2(1700.0, 400.0))
	_ck("무효 목적지 — 트레이 카드 유지", not _proto._tray.is_empty())
	_proto._tray.clear()

	# 6) 유물·전술 — 3차 그대로 각자의 줄에만
	for i in UNIQUE_PICK.size():
		_tray_put({"kind": "relic", "def": _unique_by_id(str(UNIQUE_PICK[i]))})
		_drag(_proto._tray_rect(0).get_center(), _proto._relic_rect(i).get_center())
	_proto._tray.clear()
	_ck("유물 4칸", _proto.RELIC_SLOTS - _proto._empty_relics() == 4)
	for i in TACTIC_PICK.size():
		_tray_put({"kind": "tactic", "def": _tactic_by_id(str(TACTIC_PICK[i]))})
		_drag(_proto._tray_rect(0).get_center(), _proto._tactic_rect(i).get_center())
	_proto._tray.clear()
	var held: int = 0
	for t in _proto._tactics:
		if t != null:
			held += 1
	_ck("전술 3칸", held == 3)
	# 전술카드를 격자에 떨구면 무효 — 목적지가 문법을 정한다
	_tray_put({"kind": "tactic", "def": _tactic_by_id("TC_SANDAN")})
	_drag(_proto._tray_rect(0).get_center(), _proto._cell_rect(4).get_center())
	_ck("전술카드 칸 드롭 무효", not _proto._tray.is_empty() and _proto._cells[4] == null)
	_proto._tray.clear()

	# 7) 스킬 슬롯 5칸 + **교환**(꽉 차면 바꾼다, 버린 카드는 소멸)
	for i in SKILL_PICK.size():
		_tray_put({"kind": "skill", "def": _proto._skill_card_by_id(str(SKILL_PICK[i]))})
		_drag(_proto._tray_rect(0).get_center(), _proto._skill_rect(i).get_center())
	_proto._tray.clear()
	var sk_held: int = 0
	for c in _proto._skills:
		if c != null:
			sk_held += 1
	_ck("스킬 슬롯 5칸", sk_held == 5)
	# 이미 가진 카드는 다시 못 넣는다
	_tray_put({"kind": "skill", "def": _proto._skill_card_by_id("sc_push")})
	_drag(_proto._tray_rect(0).get_center(), _proto._skill_rect(2).get_center())
	_ck("중복 스킬카드 거부", not _proto._tray.is_empty())
	_proto._tray.clear()
	# 교환 — 슬롯 0의 카드를 슬롯 4로 밀어넣으면 슬롯 4가 갈린다
	var slot0_id: String = str(_proto._skills[0]["id"])
	_proto._skills[0] = null
	_tray_put({"kind": "skill", "def": _proto._skill_card_by_id(slot0_id)})
	_drag(_proto._tray_rect(0).get_center(), _proto._skill_rect(4).get_center())
	_ck("슬롯 교환 — 기존 카드 소멸",
		_proto._tray.is_empty() and str(_proto._skills[4]["id"]) == slot0_id)
	_proto._skills[0] = _proto._skill_card_by_id("sc_fire")   # 5장을 다시 채운다

	# 8) 막보스 상시 표시 — 막이 시작될 때부터 그 막의 막보스가 뜬다
	var e: Dictionary = _proto._act_boss_entry(0)
	_ck("막보스 상시 표시", not e.is_empty() and bool(e["boss"])
		and not (e["pre"] as Array).is_empty())

	# 9) 던전 핵심 스케줄 — 정예 3 + 보스 1 (일반은 스케줄 밖 무한 스폰)
	var elite: int = 0
	var boss_n: int = 0
	for en in _proto._round_sched:
		if str(en["tier"]) == "elite":
			elite += 1
		elif str(en["tier"]) == "boss":
			boss_n += 1
	print("던전1 핵심: 정예 %d · 보스 %d · 제한시간 %.0fs"
		% [elite, boss_n, _proto._round_limit])
	_ck("핵심 스케줄 = 정예 3 + 보스 1",
		elite == 3 and boss_n == 1 and _proto._round_sched.size() == 4)

	# 10) 전투 중에는 판을 못 바꾼다 — 나중에 COMBAT에서 확인한다
	_set_comp(COMP_A)
	print("배치 %d/9 · 인원 %d (천장 %d)"
		% [_proto._placed_count(), _proto._crew_now(), _proto._crew_cap()])


# ─── 정비 처리 — 던전마다 ────────────────────────────────────────────────
func _do_prep() -> void:
	_proto._gold = 100000
	if _proto._round_idx == SWAP_B_ROUND:
		_set_comp(COMP_B)
		print("  판 교체 → B (R%d)" % (_proto._round_idx + 1))
	elif _proto._round_idx == SWAP_C_ROUND:
		_set_comp(COMP_C)
		print("  판 교체 → C (R%d)" % (_proto._round_idx + 1))
	elif _proto._placed_count() < 9:
		_set_comp(COMP_A)
	# 막보스 상시 표시가 매 막에서 살아 있는가
	var e: Dictionary = _proto._act_boss_entry(_proto._act_of_round(_proto._round_idx))
	if not e.is_empty() and bool(e["boss"]):
		_bossbar_ok += 1
	var settle_now: bool = _proto._round_idx == SETTLE_ROUND
	_proto._press(_proto.START_BUTTON.get_center())
	if settle_now and _proto._phase == 1:
		# **정산 경로를 확정적으로 밟는다** — 제한시간을 잘라 반드시 타임아웃을 낸다
		_proto._round_limit = SETTLE_LIMIT
		print("  정산 검증 — R%d 제한시간을 %.0fs로 줄였다"
			% [_proto._round_idx + 1, SETTLE_LIMIT])


# ─── 전투 중 — 스킬카드를 실제로 쓴다 ────────────────────────────────────
# 사람 손이 아니다. 라운드 절반은 "쓸 수 있으면 쓴다"(구간 버프 상실이 몇 번 물리는지),
# 절반은 아예 안 쓴다(아꼈을 때 상위 구간이 실제로 열리는지) — 트레이드오프의 양끝을
# 한 런에서 다 밟는다. 홀수 라운드(R2·R4·…)가 아끼는 쪽이다.
func _do_combat() -> void:
	if _f % 24 != 0:
		return
	if _proto._round_idx % 2 == 1:
		return
	for i in _proto.SKILL_SLOTS:
		if not _proto._can_fire_card(i):
			continue
		_card_tries += 1
		_proto._press(_proto._skill_rect(i).get_center())
		return


# ─── 스크린샷 3컷 — 정비(격자+팩 진열) · 팩 개봉 택1 · COMBAT ───────────
# 렌더가 fixed-fps 를 못 따라와 몇십 프레임 늦으므로, 찍기 전 60프레임 내내
# 같은 상태·같은 호버를 붙잡아 둔다.
func _shots_step() -> void:
	match _shot_stage:
		0:
			# 보유·배치를 채워두고 찍는다 — 빈 화면은 정보가 없다
			if _proto._placed_count() < 9:
				_proto._gold = 100000
				for i in SKILL_PICK.size():
					_proto._skills[i] = _proto._skill_card_by_id(str(SKILL_PICK[i]))
				for i in UNIQUE_PICK.size():
					_proto._relics[i] = _unique_by_id(str(UNIQUE_PICK[i]))
				for i in TACTIC_PICK.size():
					_proto._tactics[i] = _tactic_by_id(str(TACTIC_PICK[i]))
				_set_comp(COMP_A)
			_proto._mouse = _proto._pack_rect(0).get_center()
			_shot_hold += 1
			if _shot_hold > 70:
				_save("a_prep")
				_shot_stage = 1
				_shot_hold = 0
		1:
			if _proto._offer.is_empty():
				_proto._try_buy_pack("unit")
			_proto._mouse = _proto._offer_rect(0).get_center()
			_shot_hold += 1
			if _shot_hold > 70:
				_save("b_offer")
				_proto._pick_offer(0)          # 트레이로 — 전투 컷의 하단 밴드에 보인다
				_shot_stage = 2
				_shot_hold = 0
		2:
			if _proto._phase == 0:
				_proto._press(_proto.START_BUTTON.get_center())
			# 레인에 적이 서고 사기가 찼을 때를 잡는다 — 빈 레인만 찍히면 의미가 없다
			if _proto._lane_alive() >= 1 and _proto._morale >= 30.0:
				_proto._mouse = _proto._skill_rect(0).get_center()
				_shot_hold += 1
			if _shot_hold > 70:
				_save("c_combat")
				_shot_done = 1


func _save(name: String) -> void:
	if _shot_dir == "":
		return
	var img: Image = root.get_texture().get_image()
	if img != null:
		img.save_png("%s/%s.png" % [_shot_dir, name])
		print("shot %s" % name)


func _process(_delta: float) -> bool:
	_f += 1
	if _f < 20:
		return false

	if _shot_dir != "":
		_shots_step()
		if _shot_done == 1:
			return true
		return _f > 8000

	# 첫 정비에서 경로 검증을 한 번만 돌린다
	if _prep_done < 0 and _proto._phase == 0:
		print("--- 경로 검증 ---")
		_path_checks()
		# R1 정비는 _do_prep 을 안 거치므로 여기서 센다 — 검증 자체는 8)에서 했다.
		# 안 세면 클리어 시 카운트가 11인데 기준이 12라 항상 1 모자란다 (4차 FAIL의 정체)
		_bossbar_ok += 1
		_prep_done = 0
		_proto._press(_proto.START_BUTTON.get_center())
		# 전투 중에는 판을 못 바꾼다
		var n0: int = _proto._placed_count()
		_drag(_proto._cell_rect(0).get_center(), Vector2(1700.0, 300.0))
		_hold_unit(str(COMP_A[0]), 0)
		_drag(_proto._tray_rect(0).get_center(), _proto._cell_rect(0).get_center())
		_proto._tray.clear()
		_ck("전투 중 배치 차단", _proto._phase == 1 and _proto._placed_count() == n0)
		var g2: int = _proto._gold
		var combat_buy: bool = _proto._try_buy_pack("unit")
		_ck("전투 중 팩 구매 차단", not combat_buy and _proto._gold == g2
			and _proto._offer.is_empty())
		_proto._press(_proto.WALL_RECT.get_center())
		_ck("전투 중 수리 차단", _proto._gold == g2)
		print("--- 런 ---")
		return false

	# 라운드가 끝났는지 — 정비로 돌아온 프레임을 잡는다
	if _proto._round_idx != _last_round_seen:
		if _last_round_seen >= 0:
			if _proto._round_settled > 0:
				_rounds_settled += 1
			else:
				_rounds_early += 1
			print("  R%d 종료: %s · 처치 %d · 정산 %d마리 · 성벽 %d · 사기최고 %d" % [
				_last_round_seen + 1,
				"정산" if _proto._round_settled > 0 else "전멸(조기)",
				_proto._round_killed, _proto._round_settled, int(_proto._wall_hp),
				int(_proto._log_morale_peak)])
		_last_round_seen = _proto._round_idx

	match _proto._phase:
		0:
			_do_prep()
		1:
			_do_combat()
		_:
			_report()
			return true
	return _f > 200000


func _report() -> void:
	print("=== 종료: %s ===" % ("클리어" if _proto._phase == 2 else "패배"))
	print("던전 %d/%d · 처치 %d · 전투 경과 %.0fs · 성벽 %d/%d" % [
		mini(_proto._round_idx, _proto.RUN_ROUNDS), _proto.RUN_ROUNDS, _proto._killed,
		_proto._elapsed, int(_proto._wall_hp), int(_proto._wall_max)])
	print("조기 종료 %d라운드 / 정산 %d라운드 (정산 피해 %d · 성벽 총 손실 %d)" % [
		_rounds_early, _rounds_settled, int(_proto._log_settle_dmg),
		int(_proto._log_wall_lost)])
	print("평균 처치 소요 %.1fs · 최대 겹침 %d마리" % [_proto._avg_kill(),
		_proto._log_overlap_peak])
	# 단별 분리 — 일반은 짧아야 하고 정예·막보스는 초읽기가 서야 한다
	var tl: String = ""
	for tier in ["normal", "elite", "boss"]:
		var arr: Array = _proto._log_kill_tier.get(tier, [])
		var mx: float = 0.0
		for t in arr:
			mx = maxf(mx, float(t))
		tl += "%s %.1fs(최대 %.1f · %d마리) / " % [
			{"normal": "일반", "elite": "정예", "boss": "막보스"}[tier],
			_proto._avg_kill_tier(tier), mx, arr.size()]
	print("단별 처치 소요: %s" % tl)
	print("딜 0 타격 %.0f%% · 빗나감 %.0f%% · 물리 감산 손실 %.0f%%" % [
		_proto._zero_ratio(), _proto._miss_ratio(), _proto._phys_loss()])
	print("스킬카드 발동 %d회 (사기 %d 소모) · **구간 버프 상실 %d회** · 사기 최고 %d" % [
		_proto._log_card_fires, int(_proto._log_card_spent), _proto._log_band_drops,
		int(_proto._log_morale_peak)])
	print("유물 발동 %d회 · 유닛 스킬 %d회" % [_proto._log_relic_fires,
		_proto._skill_fire_total()])
	var fires: String = ""
	var keys: Array = _proto._log_skill_fires.keys()
	keys.sort()
	for k in keys:
		fires += "%s %d / " % [str(k), int(_proto._log_skill_fires[k])]
	print("스킬 발동(effect별 %d종): %s" % [keys.size(), fires])
	var per_cell: String = ""
	for sq in _proto._cells:
		if sq == null:
			continue
		per_cell += "%s %d / " % [str(sq["def"]["name"]), int(sq["dmg"])]
	print("칸별 기여: %s" % per_cell)
	_ck("조기 종료 경로", _rounds_early > 0)
	_ck("타임아웃 정산 경로", _rounds_settled > 0)
	_ck("스킬카드 발동", _proto._log_card_fires > 0)
	_ck("구간 버프 상실 발생", _proto._log_band_drops > 0)
	# 아끼는 던전에서 상위 구간(75)이 실제로 열리는가 — 4차 재튜닝의 목표 그 자체
	_ck("사기 상위 구간 도달(75+)", _proto._log_morale_peak >= 75.0)
	# 일반 무한 스폰이 실제로 돈다 — 던전당 핵심 4를 빼고도 일반 킬이 두 자릿수는 나와야 한다
	_ck("일반 연속 스폰", (_proto._log_kill_tier.get("normal", []) as Array).size() >= 10)
	_ck("막보스 상시 표시 — 던전마다", _bossbar_ok >= mini(_proto._round_idx, 4))
	_ck("effect 20종 전부 발동", keys.size() >= 20)
	print("경로 검증: 통과 %d / 실패 %d" % [_pass.size(), _fail.size()])
	if not _fail.is_empty():
		print("실패 목록: %s" % ", ".join(_fail))
