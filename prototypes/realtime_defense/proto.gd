# PROTOTYPE - NOT FOR PRODUCTION
# Question: 흐르는 시간 속에서 구매·배치·아이템 발동 판단이 실제로 성립하는가?
#           (부수 측정: 킬 속도가 여유 시간으로 환산되는가 / 문턱 통함·막힘이 구매를 바꾸는가)
# Date: 2026-08-05
#
# 기준 문서: docs/game_design/GAME_DESIGN.md — 실시간 로그라이크 TD 확정본.
# 넣은 것: 3×3(한 칸=한 부대) · 무정지 실시간 · 스폰 스케줄과 겹침 · 최근접 타게팅 ·
#          5슬롯 매대 + 드래그 구매 + 유료 리롤 · 성벽 HP 지속 + 수리/업그레이드 ·
#          방어력/마법저항 문턱과 통함·막힘 사전 표시 · 아이템 3종의 실시간 발동 · 칸별 기여도
# 뺀 것:   전술카드 · 종족 시너지 · 리더 · 기사 · 보스 디버프 · 구간/거물 연출 · 언락 · 밸런싱
#
# 수치는 전부 임시값이다. src/data/ 로 옮기지 않는다 — 이 폴더는 버리는 코드다.

extends Node2D

# ─── 레이아웃 (하드코딩, 1920×1080) ────────────────────────────────────────
const W := 1920.0
const H := 1080.0

const GRID_ORIGIN := Vector2(56.0, 196.0)
const CELL := 152.0
const CELL_PAD := 8.0

const WALL_RECT := Rect2(528.0, 176.0, 64.0, 480.0)
const LANE_TOP := 176.0
const LANE_BOT := 656.0
const BOSS_STOP_X := 652.0            # 보스 중심이 멈추는 곳 — 성벽 바로 오른쪽
const BOSS_SPAWN_X := 1880.0          # 1228px 전진 = 접근 구간
const BOSS_BASE_Y := 480.0

const SHOP_ORIGIN := Vector2(56.0, 706.0)
const CARD := Vector2(196.0, 250.0)
const CARD_GAP := 14.0
const SHOP_SLOTS := 5

const REROLL_RECT := Rect2(1106.0, 706.0, 132.0, 250.0)
const WALLPANEL_RECT := Rect2(1252.0, 706.0, 300.0, 250.0)
const STATS_RECT := Rect2(1566.0, 706.0, 298.0, 250.0)

# ─── 밸런스 (전부 임시값) ──────────────────────────────────────────────────
const RUN_BOSSES := 12
const WALL_HP_START := 500.0

const GOLD_START := 130
const KILL_GOLD_BASE := 30
const KILL_GOLD_STEP := 10

const REROLL_BASE := 14
const REROLL_STEP := 10               # 연속 리롤마다 가산 (킬 시 원가 복귀)

const REPAIR_HEAL := 110.0
const REPAIR_PRICE_BASE := 40
const REPAIR_PRICE_MULT := 1.5
const UPGRADE_GAIN := 90.0
const UPGRADE_PRICE_BASE := 70
const UPGRADE_PRICE_MULT := 1.6

const BLOCKED_RATIO := 0.08           # 문턱에 막힌 타격이 남기는 비율. 완전 면역은 두지 않는다
const SLOW_FACTOR := 0.45
const BURN_TICK := 2.2                # 스택당 초당 딜. 화상은 문턱을 무시한다
const BURN_DURATION := 6.0

const FIRST_SPAWN := 5.0
const INTERVAL_EARLY := 16.0
const INTERVAL_LATE := 9.0
const ADAPTIVE_REST := 3.5            # ADAPTIVE 모드에서 킬 후 다음 스폰까지의 숨돌릴 틈

# ─── 스프라이트 ───────────────────────────────────────────────────────────
const SPRITE_ROOT := "res://assets/units"
const ANIMS := {
	"idle":   {"folder": "Idle",   "fps": 8.0,  "loop": true},
	"walk":   {"folder": "Walk",   "fps": 10.0, "loop": true},
	"attack": {"folder": "Attack", "fps": 12.0, "loop": true},
	"spell":  {"folder": "Spell",  "fps": 10.0, "loop": true},
	"death":  {"folder": "Death",  "fps": 8.0,  "loop": false},
}
const MAX_MEMBERS := 6
const MAX_BOSS_SPRITES := 8
# 인원이 적을수록 개체가 크다 — 체급이 실루엣으로 읽혀야 한다
const MEMBER_SCALE := {6: 1.9, 4: 2.3, 3: 2.7, 2: 3.1, 1: 4.0}

# ─── 직업 ─────────────────────────────────────────────────────────────────
# 직업은 데미지 타입과 주기만 정한다. 동사(밀어내기·상태이상)는 전부 아이템 몫이다.
const JOBS := {
	"warrior": {"name": "전사",   "dtype": "phys", "period": 1.00, "color": Color(0.88, 0.42, 0.34)},
	"archer":  {"name": "궁수",   "dtype": "phys", "period": 0.55, "color": Color(0.45, 0.78, 0.46)},
	"mage":    {"name": "마법사", "dtype": "mag",  "period": 1.90, "color": Color(0.46, 0.52, 0.94)},
	"cleric":  {"name": "사제",   "dtype": "none", "period": 1.50, "color": Color(0.95, 0.86, 0.48)},
}

# power = 칸의 박자당 총 공격력. 인원은 이걸 나눠 타격당 딜을 만든다 (곱하지 않는다).
const UNITS := [
	{"id": "sw1", "job": "warrior", "tier": 1, "name": "검사대",       "race": "인간",
	 "members": 6, "power": 30.0, "flat": 0.0, "price": 30,
	 "sprite": "minifolks/MinifolksHumans/MiniSwordMan/no_outline"},
	{"id": "sw2", "job": "warrior", "tier": 2, "name": "오크 전사단",   "race": "오크",
	 "members": 3, "power": 44.0, "flat": 0.0, "price": 60,
	 "sprite": "minifolks/MinifolksOrcs/MiniOrcWarrior/no_outline"},
	{"id": "sw3", "job": "warrior", "tier": 3, "name": "오크 정예",     "race": "오크",
	 "members": 1, "power": 60.0, "flat": 0.0, "price": 110,
	 "sprite": "minifolks/MinifolksOrcs/MiniOrcVeteran/no_outline"},

	{"id": "ar1", "job": "archer",  "tier": 1, "name": "궁수대",        "race": "인간",
	 "members": 6, "power": 20.0, "flat": 0.0, "price": 30,
	 "sprite": "minifolks/MinifolksHumans/MiniArcherMan/no_outline"},
	{"id": "ar2", "job": "archer",  "tier": 2, "name": "해골 궁수단",   "race": "언데드",
	 "members": 4, "power": 26.0, "flat": 0.0, "price": 60,
	 "sprite": "minifolks/MinifolksUndead/MiniSkeletonArcher/no_outline"},
	{"id": "ar3", "job": "archer",  "tier": 3, "name": "명사수",        "race": "다크엘프",
	 "members": 2, "power": 30.0, "flat": 0.0, "price": 110,
	 "sprite": "minifolks/MiniDarkElves/MiniDarkElfArcher/no_outline"},

	{"id": "mg1", "job": "mage",    "tier": 1, "name": "견습 마법사단", "race": "인간",
	 "members": 4, "power": 55.0, "flat": 0.0, "price": 30,
	 "sprite": "minifolks/MinifolksHumans/MiniMage/no_outline"},
	{"id": "mg2", "job": "mage",    "tier": 2, "name": "다크엘프 술사", "race": "다크엘프",
	 "members": 2, "power": 70.0, "flat": 0.0, "price": 60,
	 "sprite": "minifolks/MiniDarkElves/MiniDarkElfWizard/no_outline"},
	{"id": "mg3", "job": "mage",    "tier": 3, "name": "리치",          "race": "언데드",
	 "members": 1, "power": 88.0, "flat": 0.0, "price": 110,
	 "sprite": "minifolks/MinifolksUndead/MiniLich/no_outline"},

	{"id": "cl1", "job": "cleric",  "tier": 1, "name": "빛의 사제",     "race": "별방랑자",
	 "members": 4, "power": 0.0,  "flat": 1.2, "price": 35,
	 "sprite": "minifolks/MiniStarWanderers/MiniSWPriestess/no_outline"},
	{"id": "cl2", "job": "cleric",  "tier": 2, "name": "불의 사제",     "race": "불의교단",
	 "members": 2, "power": 0.0,  "flat": 2.2, "price": 65,
	 "sprite": "minifolks/MiniOrderOfTheFire/MiniFirePriestess/no_outline"},
	{"id": "cl3", "job": "cleric",  "tier": 3, "name": "숲의 드루이드", "race": "수인족",
	 "members": 1, "power": 0.0,  "flat": 3.5, "price": 115,
	 "sprite": "minifolks/MiniBeastmens/MiniDeerDruid/no_outline"},
]

# ─── 아이템 = 동사 ────────────────────────────────────────────────────────
# 쿨다운은 초가 아니라 "몸의 박자 수"로 찬다. 그래서 같은 아이템도 빠른 부대에선 잦고
# 작게, 소수정예에선 드물고 크게 나간다 — 동사의 변형을 체급이 공짜로 만든다.
const ITEMS := [
	{"id": "hammer", "verb": "push", "name": "충격 망치", "beats": 7, "price": 50,
	 "color": Color(0.96, 0.76, 0.36), "short": "밀어내기",
	 "desc": "최근접 보스를 밀어낸다. 거리는 타격당 딜에 비례한다."},
	{"id": "fetter", "verb": "slow", "name": "서리 족쇄", "beats": 9, "price": 50,
	 "color": Color(0.55, 0.82, 0.98), "short": "둔화",
	 "desc": "최근접 보스를 둔화시킨다. 지속은 타격당 딜에 비례한다."},
	{"id": "brand",  "verb": "burn", "name": "화염 낙인", "beats": 8, "price": 50,
	 "color": Color(0.98, 0.46, 0.30), "short": "화상 — 문턱 무시",
	 "desc": "화상 스택을 얹는다. 화상은 문턱을 무시한다 — 막힌 편성의 탈출구."},
]

# ─── 보스 ─────────────────────────────────────────────────────────────────
const ARCHETYPES := [
	{"id": "rush", "name": "돌격형", "scale": 4.6, "tint": Color(0.96, 0.58, 0.36),
	 "hp": 480.0, "armor": 3.0, "mres": 3.0, "speed": 108.0,
	 "wall_dmg": 24.0, "wall_int": 1.3, "push_res": 0.35, "regen": 0.0,
	 "hint": "빠르다 — 지연·밀어내기의 값이 오른다",
	 "sprite": "minifolks/MiniMonsters/MiniMinotaur/no_outline"},
	{"id": "armor", "name": "장갑형", "scale": 5.0, "tint": Color(0.76, 0.80, 0.90),
	 "hp": 700.0, "armor": 12.0, "mres": 4.0, "speed": 62.0,
	 "wall_dmg": 38.0, "wall_int": 1.6, "push_res": 0.55, "regen": 0.0,
	 "hint": "물리 문턱이 높다 — 잘게 쪼갠 타격은 튕긴다",
	 "sprite": "minifolks/MiniBigMonsters/MiniOrcMutant/no_outline"},
	{"id": "hex", "name": "주술형", "scale": 4.8, "tint": Color(0.74, 0.56, 0.96),
	 "hp": 640.0, "armor": 4.0, "mres": 16.0, "speed": 70.0,
	 "wall_dmg": 32.0, "wall_int": 1.4, "push_res": 0.45, "regen": 0.0,
	 "hint": "마법 문턱이 높다 — 마법사가 막힌다",
	 "sprite": "minifolks/MiniBigMonsters/MiniDarkLord/no_outline"},
	{"id": "regen", "name": "재생형", "scale": 5.0, "tint": Color(0.56, 0.86, 0.80),
	 "hp": 760.0, "armor": 8.0, "mres": 8.0, "speed": 58.0,
	 "wall_dmg": 28.0, "wall_int": 1.5, "push_res": 0.50, "regen": 12.0,
	 "hint": "초당 회복한다 — 총 화력이 모자라면 영원히 안 죽는다",
	 "sprite": "minifolks/MiniBigMonsters/MiniYeti/no_outline"},
	{"id": "tyrant", "name": "거물", "scale": 5.4, "tint": Color(0.96, 0.38, 0.42),
	 "hp": 1200.0, "armor": 14.0, "mres": 14.0, "speed": 66.0,
	 "wall_dmg": 50.0, "wall_int": 1.4, "push_res": 0.70, "regen": 8.0,
	 "hint": "구간의 끝 — 축이 전부 높다",
	 "sprite": "minifolks/MiniBigMonsters/MiniHydra/no_outline"},
]

enum Phase { RUNNING, CLEAR, DEFEAT }
enum SpawnMode { FIXED, ADAPTIVE }

# ─── 상태 ─────────────────────────────────────────────────────────────────
var _phase: int = Phase.RUNNING
var _spawn_mode: int = SpawnMode.FIXED
var _speed: float = 1.0
var _paused: bool = false

var _elapsed: float = 0.0
var _gold: int = GOLD_START
var _wall_hp: float = WALL_HP_START
var _wall_max: float = WALL_HP_START
var _wall_flash: float = 0.0

var _cells: Array = []                # 9칸 — null 또는 부대 Dictionary
var _bosses: Array = []               # 등장 순서대로. 죽으면 death 연출 후 제거
var _shop: Array = []                 # 5슬롯 — null(구매됨) 또는 카드 Dictionary
var _schedule: Array = []             # 보스 정의 + 스폰 시각
var _next_spawn: int = 0
var _killed: int = 0
var _last_kill_at: float = -999.0
# ADAPTIVE 모드에서 "킬이 당긴 스폰 시각". 킬 하나가 당기는 것은 다음 한 마리뿐이라
# 스폰될 때 소모한다 — 안 그러면 킬 한 번에 남은 보스가 전부 쏟아진다.
var _pull_at: float = -999.0

var _reroll_price: int = REROLL_BASE
var _repair_price: int = REPAIR_PRICE_BASE
var _upgrade_price: int = UPGRADE_PRICE_BASE

var _rng := RandomNumberGenerator.new()

# 측정용 — 리포트에 옮겨 적을 숫자들
var _log_kill_times: Array = []       # 보스별 [등장→처치] 소요
var _log_overlap_peak: int = 1
var _log_wall_lost: float = 0.0
var _log_blocked_hits: int = 0
var _log_total_hits: int = 0

# 드래그
var _drag_kind: String = ""           # "" | "shop" | "cell"
var _drag_from: int = -1
var _drag_moved: bool = false
var _mouse: Vector2 = Vector2.ZERO
var _mouse_down_at: Vector2 = Vector2.ZERO

# 노드
var _font: Font = load("res://assets/fonts/Galmuri11.ttf")
var _font_b: Font = load("res://assets/fonts/Galmuri11-Bold.ttf")
var _font_s: Font = load("res://assets/fonts/Galmuri9.ttf")

var _frames: Dictionary = {}          # sprite_dir → SpriteFrames
var _cell_sprites: Array = []         # 9 × MAX_MEMBERS
var _card_sprites: Array = []         # 5 × MAX_MEMBERS
var _boss_sprites: Array = []         # MAX_BOSS_SPRITES
var _overlay: Node2D                  # 스프라이트 위에 얹는 전부 (HUD·매대·툴팁·패널)


func _ready() -> void:
	_rng.randomize()
	for u in UNITS:
		_frames[u["sprite"]] = _build_frames(u["sprite"])
	for a in ARCHETYPES:
		_frames[a["sprite"]] = _build_frames(a["sprite"])

	for i in 9:
		var row: Array = []
		for m in MAX_MEMBERS:
			row.append(_make_sprite(5))
		_cell_sprites.append(row)
	for i in SHOP_SLOTS:
		var row2: Array = []
		for m in MAX_MEMBERS:
			row2.append(_make_sprite(5))
		_card_sprites.append(row2)
	for i in MAX_BOSS_SPRITES:
		var s := _make_sprite(5)
		s.flip_h = true               # 좌측(성벽)을 바라본다
		_boss_sprites.append(s)

	_overlay = Node2D.new()
	_overlay.z_index = 100
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)

	_start_run()


func _make_sprite(z: int) -> AnimatedSprite2D:
	var s := AnimatedSprite2D.new()
	s.centered = true
	s.visible = false
	s.z_index = z
	add_child(s)
	return s


# TheSevenAutoBattle/src/battle/sprite_frame_loader.gd 를 프로토용으로 줄여 베낀 것.
# 프레임이 0인 애니는 아예 넣지 않는다 — 없는 애니를 play()하면 조용히 멈춘다.
func _build_frames(sprite_dir: String) -> SpriteFrames:
	var frames := SpriteFrames.new()
	if frames.has_animation(&"default"):
		frames.remove_animation(&"default")
	for anim_name in ANIMS.keys():
		var conf: Dictionary = ANIMS[anim_name]
		var dir_path: String = "%s/%s/%s" % [SPRITE_ROOT, sprite_dir, conf["folder"]]
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		var pngs: Array[String] = []
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if not dir.current_is_dir() and fname.ends_with(".png"):
				pngs.append(fname)
			fname = dir.get_next()
		dir.list_dir_end()
		if pngs.is_empty():
			continue
		pngs.sort()
		frames.add_animation(anim_name)
		frames.set_animation_speed(anim_name, conf["fps"])
		frames.set_animation_loop(anim_name, conf["loop"])
		for f in pngs:
			var tex: Texture2D = load("%s/%s" % [dir_path, f])
			if tex != null:
				frames.add_frame(anim_name, tex)
	return frames


func _play(s: AnimatedSprite2D, anim: StringName) -> void:
	if s.sprite_frames == null:
		return
	var want: StringName = anim
	if not s.sprite_frames.has_animation(want):
		want = &"idle"
	if not s.sprite_frames.has_animation(want):
		return
	if s.animation != want or not s.is_playing():
		s.play(want)


# ─── 런 초기화 ────────────────────────────────────────────────────────────
func _start_run() -> void:
	_phase = Phase.RUNNING
	_elapsed = 0.0
	_gold = GOLD_START
	_wall_max = WALL_HP_START
	_wall_hp = WALL_HP_START
	_wall_flash = 0.0
	_killed = 0
	_last_kill_at = -999.0
	_pull_at = -999.0
	_reroll_price = REROLL_BASE
	_repair_price = REPAIR_PRICE_BASE
	_upgrade_price = UPGRADE_PRICE_BASE
	_log_kill_times.clear()
	_log_overlap_peak = 1
	_log_wall_lost = 0.0
	_log_blocked_hits = 0
	_log_total_hits = 0
	_drag_kind = ""

	_cells.clear()
	for _i in 9:
		_cells.append(null)
	_bosses.clear()
	_build_schedule()
	_next_spawn = 0
	_refresh_shop(true)
	queue_redraw()
	_overlay.queue_redraw()


func _build_schedule() -> void:
	_schedule.clear()
	var t: float = FIRST_SPAWN
	for i in RUN_BOSSES:
		# 구간의 끝(4마리마다)은 거물. 나머지는 네 아키타입을 돌린다.
		var arch: Dictionary = ARCHETYPES[4] if (i + 1) % 4 == 0 else ARCHETYPES[i % 4]
		var mult: float = 1.0 + float(i) * 0.28
		_schedule.append({
			"arch": arch,
			"index": i,
			"at": t,
			"hp": float(arch["hp"]) * mult,
			"armor": float(arch["armor"]) * (1.0 + float(i) * 0.06),
			"mres": float(arch["mres"]) * (1.0 + float(i) * 0.06),
			"wall_dmg": float(arch["wall_dmg"]) * (1.0 + float(i) * 0.05),
			"regen": float(arch["regen"]) * mult,
			"gold": (KILL_GOLD_BASE + KILL_GOLD_STEP * i) * (2 if arch["id"] == "tyrant" else 1),
		})
		t += lerpf(INTERVAL_EARLY, INTERVAL_LATE, float(i) / float(RUN_BOSSES - 1))


# ─── 매대 ─────────────────────────────────────────────────────────────────
func _roll_card(units_only: bool) -> Dictionary:
	# 풀은 순수 랜덤이다. 단 첫 매대는 병사카드로 채운다 — 빈 격자에 아이템은 살 수 없는 매물이다.
	if not units_only and _rng.randf() < 0.3:
		var it: Dictionary = ITEMS[_rng.randi_range(0, ITEMS.size() - 1)]
		return {"kind": "item", "def": it, "price": int(it["price"])}
	# 진행할수록 고티어가 섞인다 (구간 경계 = 티어 전환점의 대체물)
	var prog: float = float(_killed) / float(RUN_BOSSES)
	var pool: Array = []
	for u in UNITS:
		var tier: int = int(u["tier"])
		var weight: int = 1
		if tier == 1:
			weight = 5 if prog < 0.35 else (3 if prog < 0.7 else 1)
		elif tier == 2:
			weight = 2 if prog < 0.35 else 4
		else:
			weight = 0 if prog < 0.25 else (2 if prog < 0.6 else 4)
		for _k in weight:
			pool.append(u)
	var d: Dictionary = pool[_rng.randi_range(0, pool.size() - 1)]
	return {"kind": "unit", "def": d, "price": int(d["price"])}


func _refresh_shop(units_only: bool) -> void:
	_shop.clear()
	for _i in SHOP_SLOTS:
		_shop.append(_roll_card(units_only))


func _try_reroll() -> void:
	if _gold < _reroll_price:
		return
	_gold -= _reroll_price
	_reroll_price += REROLL_STEP
	_refresh_shop(false)


# ─── 부대 ─────────────────────────────────────────────────────────────────
func _make_squad(d: Dictionary) -> Dictionary:
	return {
		"def": d,
		"members": int(d["members"]),
		"power": float(d["power"]),
		"flat": 0.0,                  # 인접 사제가 채운다
		"period": float(JOBS[d["job"]]["period"]),
		"cd": float(JOBS[d["job"]]["period"]),
		"beats": 0,
		"dmg": 0.0,
		"hits": 0,
		"flash": 0.0,
		"item": {},
		"item_beats": 0,
		"item_flash": 0.0,
	}


# 배치가 바뀔 때마다 다시 계산한다 — 실시간이라 정적일 수 없다.
func _recalc_buffs() -> void:
	for i in 9:
		var sq = _cells[i]
		if sq == null:
			continue
		var flat: float = 0.0
		for j in _neighbors(i):
			var n = _cells[j]
			if n != null and n["def"]["job"] == "cleric":
				flat += float(n["def"]["flat"])
		sq["flat"] = flat


func _neighbors(idx: int) -> Array:
	var row: int = idx / 3
	var col: int = idx % 3
	var out: Array = []
	if row > 0:
		out.append(idx - 3)
	if row < 2:
		out.append(idx + 3)
	if col > 0:
		out.append(idx - 1)
	if col < 2:
		out.append(idx + 1)
	return out


func _per_hit(sq: Dictionary) -> float:
	return float(sq["power"]) / float(sq["members"]) + float(sq["flat"])


func _threshold(boss, dtype: String) -> float:
	if boss == null:
		return 0.0
	return float(boss["armor"]) if dtype == "phys" else float(boss["mres"])


# 문턱은 순수 이진이다. 넘으면 감쇄 없이 그대로, 못 넘으면 8%만.
# 단순 감쇄면 모든 보스가 "체력 많은 놈"으로 수렴하고, 완전 면역이면 손에 답이 없을 때 그냥 진다.
func _hit_damage(per: float, dtype: String, boss) -> float:
	if dtype == "none":
		return 0.0
	if boss == null:
		return per
	return per if per > _threshold(boss, dtype) else per * BLOCKED_RATIO


func _pierces(per: float, dtype: String, boss) -> bool:
	if dtype == "none" or boss == null:
		return true
	return per > _threshold(boss, dtype)


# ─── 보스 ─────────────────────────────────────────────────────────────────
func _target_boss():
	# 9칸 전원이 성벽에 제일 가까운 놈을 함께 때린다.
	var best = null
	for b in _bosses:
		if b["dead"]:
			continue
		if best == null or float(b["x"]) < float(best["x"]):
			best = b
	return best


func _spawn(entry: Dictionary) -> void:
	var live: int = 0
	for b in _bosses:
		if not b["dead"]:
			live += 1
	_bosses.append({
		"arch": entry["arch"],
		"index": int(entry["index"]),
		"x": BOSS_SPAWN_X,
		"lane_y": BOSS_BASE_Y + float((_bosses.size() % 3) - 1) * 44.0,
		"hp": float(entry["hp"]),
		"hp_max": float(entry["hp"]),
		"armor": float(entry["armor"]),
		"mres": float(entry["mres"]),
		"wall_dmg": float(entry["wall_dmg"]),
		"regen": float(entry["regen"]),
		"gold": int(entry["gold"]),
		"speed": float(entry["arch"]["speed"]),
		"wall_cd": 0.0,
		"slow": 0.0,
		"burn": 0,
		"burn_t": 0.0,
		"alive": 0.0,
		"flash": 0.0,
		"push_flash": 0.0,
		"dead": false,
		"death_t": 0.0,
		"born_at": _elapsed,
	})
	_log_overlap_peak = maxi(_log_overlap_peak, live + 1)


func _push_mult(b: Dictionary) -> float:
	# 밀어내기 저항은 시간이 갈수록 커진다 — 밀어내기만으로 무한히 버티는 것을 스스로 꺾는다.
	return clampf(1.0 - float(b["arch"]["push_res"]) - float(b["alive"]) * 0.020, 0.12, 1.0)


# ─── 메인 루프 ────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	_wall_flash = maxf(0.0, _wall_flash - delta * 4.0)
	if _phase != Phase.RUNNING or _paused:
		_sync_sprites()
		queue_redraw()
		_overlay.queue_redraw()
		return

	var dt: float = delta * _speed
	_elapsed += dt

	_tick_spawn()
	_tick_bosses(dt)
	_tick_squads(dt)
	_cleanup_bosses(dt)
	_check_end()

	_sync_sprites()
	queue_redraw()
	_overlay.queue_redraw()


func _tick_spawn() -> void:
	if _next_spawn >= _schedule.size():
		return
	var entry: Dictionary = _schedule[_next_spawn]
	var at: float = _spawn_due()
	if _elapsed >= at:
		_spawn(entry)
		_next_spawn += 1
		_pull_at = -999.0        # 이 킬이 당길 수 있는 몫은 여기서 소모된다


func _spawn_due() -> float:
	if _next_spawn >= _schedule.size():
		return INF
	var at: float = float(_schedule[_next_spawn]["at"])
	# 킬이 다음 보스를 당긴다. 스케줄은 상한으로만 남는다 — 안 죽여도 결국 온다.
	if _spawn_mode == SpawnMode.ADAPTIVE and _pull_at > 0.0:
		at = minf(at, _pull_at)
	return at


func _tick_bosses(dt: float) -> void:
	for b in _bosses:
		if b["dead"]:
			continue
		b["alive"] = float(b["alive"]) + dt
		b["flash"] = maxf(0.0, float(b["flash"]) - dt * 6.0)
		b["push_flash"] = maxf(0.0, float(b["push_flash"]) - dt * 2.5)

		# 화상 — 문턱을 무시한다
		if int(b["burn"]) > 0:
			b["burn_t"] = float(b["burn_t"]) - dt
			b["hp"] = float(b["hp"]) - BURN_TICK * float(b["burn"]) * dt
			if float(b["burn_t"]) <= 0.0:
				b["burn"] = 0

		if float(b["regen"]) > 0.0:
			b["hp"] = minf(float(b["hp_max"]), float(b["hp"]) + float(b["regen"]) * dt)

		var spd: float = float(b["speed"])
		if float(b["slow"]) > 0.0:
			b["slow"] = float(b["slow"]) - dt
			spd *= SLOW_FACTOR

		if float(b["x"]) > BOSS_STOP_X:
			b["x"] = maxf(BOSS_STOP_X, float(b["x"]) - spd * dt)
			if float(b["x"]) <= BOSS_STOP_X:
				b["wall_cd"] = float(b["arch"]["wall_int"]) * 0.5
		else:
			b["wall_cd"] = float(b["wall_cd"]) - dt
			if float(b["wall_cd"]) <= 0.0:
				b["wall_cd"] = float(b["wall_cd"]) + float(b["arch"]["wall_int"])
				_wall_hp -= float(b["wall_dmg"])
				_log_wall_lost += float(b["wall_dmg"])
				_wall_flash = 1.0

		if float(b["hp"]) <= 0.0:
			_kill(b)


func _kill(b: Dictionary) -> void:
	b["hp"] = 0.0
	b["dead"] = true
	b["death_t"] = 0.9
	_killed += 1
	_gold += int(b["gold"])
	_last_kill_at = _elapsed
	_pull_at = _elapsed + ADAPTIVE_REST
	_log_kill_times.append(_elapsed - float(b["born_at"]))
	# 보스를 잡으면 매대가 무료로 갱신되고 리롤가가 원가로 돌아온다 — 킬 템포가 곧 상점 회전율.
	_refresh_shop(false)
	_reroll_price = REROLL_BASE


func _tick_squads(dt: float) -> void:
	var target = _target_boss()
	for sq in _cells:
		if sq == null:
			continue
		sq["flash"] = maxf(0.0, float(sq["flash"]) - dt * 6.0)
		sq["item_flash"] = maxf(0.0, float(sq["item_flash"]) - dt * 2.0)
		sq["cd"] = float(sq["cd"]) - dt
		while float(sq["cd"]) <= 0.0:
			sq["cd"] = float(sq["cd"]) + float(sq["period"])
			sq["beats"] = int(sq["beats"]) + 1
			if not sq["item"].is_empty():
				sq["item_beats"] = int(sq["item_beats"]) + 1
			var dtype: String = str(JOBS[sq["def"]["job"]]["dtype"])
			if dtype == "none" or target == null or target["dead"]:
				continue
			# 한 박자에 인원 수만큼 개별 판정 — 부대원이 각자 자기 주기로 때리지 않는다.
			var per: float = _per_hit(sq)
			var one: float = _hit_damage(per, dtype, target)
			var total: float = one * float(sq["members"])
			target["hp"] = float(target["hp"]) - total
			target["flash"] = 1.0
			sq["dmg"] = float(sq["dmg"]) + total
			sq["hits"] = int(sq["hits"]) + int(sq["members"])
			sq["flash"] = 1.0
			_log_total_hits += int(sq["members"])
			if not _pierces(per, dtype, target):
				_log_blocked_hits += int(sq["members"])
			if float(target["hp"]) <= 0.0:
				_kill(target)
				target = _target_boss()


func _cleanup_bosses(dt: float) -> void:
	var i: int = _bosses.size() - 1
	while i >= 0:
		var b: Dictionary = _bosses[i]
		if b["dead"]:
			b["death_t"] = float(b["death_t"]) - dt
			if float(b["death_t"]) <= 0.0:
				_bosses.remove_at(i)
		i -= 1


func _check_end() -> void:
	if _wall_hp <= 0.0:
		_wall_hp = 0.0
		_phase = Phase.DEFEAT
	elif _killed >= RUN_BOSSES:
		_phase = Phase.CLEAR


# ─── 아이템 발동 ──────────────────────────────────────────────────────────
func _item_ready(sq) -> bool:
	if sq == null or sq["item"].is_empty():
		return false
	return int(sq["item_beats"]) >= int(sq["item"]["beats"])


func _fire_item(idx: int) -> void:
	var sq = _cells[idx]
	if not _item_ready(sq):
		return
	var target = _target_boss()
	if target == null:
		return
	sq["item_beats"] = 0
	sq["item_flash"] = 1.0
	var per: float = _per_hit(sq)
	match str(sq["item"]["verb"]):
		"push":
			var dist: float = clampf(70.0 + per * 1.6, 70.0, 340.0) * _push_mult(target)
			target["x"] = minf(BOSS_SPAWN_X, float(target["x"]) + dist)
			target["push_flash"] = 1.0
			if float(target["x"]) > BOSS_STOP_X:
				target["wall_cd"] = 0.0
		"slow":
			target["slow"] = maxf(float(target["slow"]), clampf(1.8 + per * 0.05, 1.8, 5.0))
		"burn":
			target["burn"] = mini(12, int(target["burn"]) + 1 + int(per / 8.0))
			target["burn_t"] = BURN_DURATION


# ─── 성벽 패널 ────────────────────────────────────────────────────────────
func _try_repair() -> void:
	if _gold < _repair_price or _wall_hp >= _wall_max:
		return
	_gold -= _repair_price
	_wall_hp = minf(_wall_max, _wall_hp + REPAIR_HEAL)
	_repair_price = int(round(float(_repair_price) * REPAIR_PRICE_MULT))


func _try_upgrade() -> void:
	if _gold < _upgrade_price:
		return
	_gold -= _upgrade_price
	_wall_max += UPGRADE_GAIN
	_wall_hp += UPGRADE_GAIN
	_upgrade_price = int(round(float(_upgrade_price) * UPGRADE_PRICE_MULT))


# ─── 입력 ─────────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse = event.position
		if _drag_kind != "" and _mouse.distance_to(_mouse_down_at) > 6.0:
			_drag_moved = true
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				_paused = not _paused          # 정지 중에는 모든 입력이 차단된다
			KEY_R:
				_start_run()
			KEY_S:
				_spawn_mode = SpawnMode.ADAPTIVE if _spawn_mode == SpawnMode.FIXED else SpawnMode.FIXED
			KEY_Z:
				_speed = 1.0
			KEY_X:
				_speed = 2.0
			KEY_C:
				_speed = 4.0
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
				if not _paused:
					_fire_item(event.keycode - KEY_1)
		return

	if _paused or _phase != Phase.RUNNING:
		return
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		return
	_mouse = event.position
	if event.pressed:
		_press(event.position)
	else:
		_release(event.position)


func _press(mp: Vector2) -> void:
	_drag_kind = ""
	_drag_from = -1
	_drag_moved = false
	_mouse_down_at = mp

	if REROLL_RECT.has_point(mp):
		_try_reroll()
		return
	if _repair_rect().has_point(mp):
		_try_repair()
		return
	if _upgrade_rect().has_point(mp):
		_try_upgrade()
		return

	for i in SHOP_SLOTS:
		if _card_rect(i).has_point(mp) and _shop[i] != null:
			_drag_kind = "shop"
			_drag_from = i
			return
	for i in 9:
		if _cell_rect(i).has_point(mp) and _cells[i] != null:
			_drag_kind = "cell"
			_drag_from = i
			return


func _release(mp: Vector2) -> void:
	var kind: String = _drag_kind
	var from: int = _drag_from
	var moved: bool = _drag_moved
	_drag_kind = ""
	_drag_from = -1
	_drag_moved = false
	if kind == "":
		return

	var to: int = _cell_at(mp)

	if kind == "cell":
		if not moved or to == from:
			_fire_item(from)                        # 제자리 클릭 = 아이템 발동
		elif to >= 0:
			var tmp = _cells[to]                    # 재배치는 즉시·무료 (미결 항목의 한쪽 극단)
			_cells[to] = _cells[from]
			_cells[from] = tmp
			_recalc_buffs()
		return

	# 매대에서 끌어온 것 — 결제는 드롭 순간에만 이루어진다
	if to < 0 or _shop[from] == null:
		return
	var card: Dictionary = _shop[from]
	var price: int = int(card["price"])
	if _gold < price:
		return
	if card["kind"] == "unit":
		_cells[to] = _make_squad(card["def"])       # 칸이 차 있으면 교체 — 벤치가 없으니 이게 성장이다
		_recalc_buffs()
	else:
		if _cells[to] == null:
			return                                  # 아이템은 부대 위에만 놓인다
		_cells[to]["item"] = card["def"]
		_cells[to]["item_beats"] = 0
	_gold -= price
	_shop[from] = null                              # 구매한 슬롯은 다음 갱신까지 빈 채로 둔다


func _cell_at(mp: Vector2) -> int:
	for i in 9:
		if _cell_rect(i).has_point(mp):
			return i
	return -1


# ─── 히트박스 ─────────────────────────────────────────────────────────────
func _cell_rect(idx: int) -> Rect2:
	return Rect2(GRID_ORIGIN + Vector2(float(idx % 3) * CELL, float(idx / 3) * CELL),
		Vector2(CELL - CELL_PAD, CELL - CELL_PAD))


func _card_rect(idx: int) -> Rect2:
	return Rect2(SHOP_ORIGIN + Vector2(float(idx) * (CARD.x + CARD_GAP), 0.0), CARD)


func _repair_rect() -> Rect2:
	return Rect2(WALLPANEL_RECT.position + Vector2(14.0, 56.0), Vector2(272.0, 84.0))


func _upgrade_rect() -> Rect2:
	return Rect2(WALLPANEL_RECT.position + Vector2(14.0, 150.0), Vector2(272.0, 84.0))


# ─── 스프라이트 ───────────────────────────────────────────────────────────
# 한 칸 안의 무리는 줄을 맞추지 않고 어긋나게 세운다. 정렬하면 오히려 빈약해 보인다.
func _member_offsets(n: int) -> Array:
	match n:
		1: return [Vector2(0.0, 8.0)]
		2: return [Vector2(-24.0, -6.0), Vector2(22.0, 14.0)]
		3: return [Vector2(-28.0, -10.0), Vector2(6.0, 10.0), Vector2(32.0, -4.0)]
		4: return [Vector2(-30.0, -14.0), Vector2(4.0, -4.0), Vector2(-16.0, 20.0), Vector2(28.0, 14.0)]
		_: return [Vector2(-36.0, -16.0), Vector2(-8.0, -22.0), Vector2(20.0, -10.0),
			Vector2(-26.0, 14.0), Vector2(2.0, 22.0), Vector2(30.0, 12.0)]


func _sync_sprites() -> void:
	var running: bool = _phase == Phase.RUNNING and not _paused
	var target = _target_boss()

	for i in 9:
		var sq = _cells[i]
		var row: Array = _cell_sprites[i]
		if sq == null:
			for s in row:
				s.visible = false
			continue
		var d: Dictionary = sq["def"]
		var n: int = int(sq["members"])
		var offs: Array = _member_offsets(n)
		var base: Vector2 = _cell_rect(i).get_center() + Vector2(0.0, 6.0)
		var job: String = str(d["job"])
		for m in MAX_MEMBERS:
			var s: AnimatedSprite2D = row[m]
			if m >= n:
				s.visible = false
				continue
			s.visible = true
			var f: SpriteFrames = _frames[d["sprite"]]
			if s.sprite_frames != f:
				s.sprite_frames = f
				s.animation = &"idle"
			s.scale = Vector2.ONE * float(MEMBER_SCALE.get(n, 2.5))
			s.position = base + offs[m]
			# 애니 한 바퀴 ≈ 공격 한 번. 칸마다 리듬이 달라 직업이 박자로 식별된다.
			if running:
				var anim: StringName = &"spell" if job == "cleric" else &"attack"
				_play(s, anim)
				var fc: float = maxf(1.0, float(f.get_frame_count(s.animation)))
				s.speed_scale = _speed * clampf(fc / (float(sq["period"]) * 12.0), 0.4, 2.4)
				# 연출만 몇 프레임씩 어긋낸다 — 판정은 동시지만 화면에서는 흩어져야 무리로 읽힌다
				if s.frame == 0 and m > 0 and s.frame_progress < 0.02:
					s.frame_progress = fmod(float(m) * 0.17, 1.0)
			else:
				s.speed_scale = 1.0
				_play(s, &"idle")
			s.modulate = Color.WHITE.lerp(Color(1.6, 1.5, 1.2), float(sq["flash"]) * 0.30)

	for i in SHOP_SLOTS:
		var row2: Array = _card_sprites[i]
		var card = _shop[i]
		if card == null or card["kind"] != "unit":
			for s2 in row2:
				s2.visible = false
			continue
		var ud: Dictionary = card["def"]
		var n2: int = int(ud["members"])
		var offs2: Array = _member_offsets(n2)
		var c: Vector2 = _card_rect(i).position + Vector2(CARD.x * 0.5, 126.0)
		for m in MAX_MEMBERS:
			var s3: AnimatedSprite2D = row2[m]
			if m >= n2:
				s3.visible = false
				continue
			s3.visible = true
			var f2: SpriteFrames = _frames[ud["sprite"]]
			if s3.sprite_frames != f2:
				s3.sprite_frames = f2
			s3.scale = Vector2.ONE * float(MEMBER_SCALE.get(n2, 2.5)) * 0.72
			s3.position = c + offs2[m] * 0.78
			s3.modulate = Color.WHITE
			_play(s3, &"idle")

	for i in MAX_BOSS_SPRITES:
		var bs: AnimatedSprite2D = _boss_sprites[i]
		if i >= _bosses.size():
			bs.visible = false
			continue
		var b: Dictionary = _bosses[i]
		bs.visible = true
		var bf: SpriteFrames = _frames[b["arch"]["sprite"]]
		if bs.sprite_frames != bf:
			bs.sprite_frames = bf
			bs.animation = &"idle"
		bs.scale = Vector2.ONE * float(b["arch"]["scale"])
		bs.position = Vector2(float(b["x"]), float(b["lane_y"]))
		bs.speed_scale = _speed if running else 1.0
		if b["dead"]:
			_play(bs, &"death")
			bs.modulate = Color(1.0, 1.0, 1.0, clampf(float(b["death_t"]) / 0.9, 0.0, 1.0))
		else:
			if float(b["x"]) > BOSS_STOP_X:
				_play(bs, &"walk")
			else:
				_play(bs, &"attack")
			var tint: Color = Color.WHITE
			if b == target:
				tint = Color(1.15, 1.10, 1.05)
			tint = tint.lerp(Color(1.8, 0.6, 0.6), float(b["flash"]) * 0.5)
			if int(b["burn"]) > 0:
				tint = tint.lerp(Color(1.7, 0.7, 0.4), 0.35)
			if float(b["slow"]) > 0.0:
				tint = tint.lerp(Color(0.7, 0.9, 1.6), 0.35)
			bs.modulate = tint


# ─── 그리기: 배경 (스프라이트 아래) ───────────────────────────────────────
func _draw() -> void:
	draw_rect(Rect2(0.0, 0.0, W, H), Color(0.085, 0.09, 0.115))
	# 레인 — 성벽 오른쪽이 전장이다
	draw_rect(Rect2(WALL_RECT.end.x, LANE_TOP, W - WALL_RECT.end.x, LANE_BOT - LANE_TOP),
		Color(0.115, 0.105, 0.135))
	# 성벽 앞 위험 구간 — 여기 들어오면 초읽기다
	draw_rect(Rect2(WALL_RECT.end.x, LANE_TOP, BOSS_STOP_X + 40.0 - WALL_RECT.end.x, LANE_BOT - LANE_TOP),
		Color(0.26, 0.10, 0.12, 0.55))
	draw_line(Vector2(WALL_RECT.end.x, LANE_BOT), Vector2(W, LANE_BOT), Color(0.20, 0.19, 0.24), 3.0)

	_draw_grid_bg()
	_draw_wall()
	draw_rect(Rect2(0.0, 690.0, W, H - 690.0), Color(0.065, 0.07, 0.09))
	_draw_shop_bg()


func _draw_grid_bg() -> void:
	for i in 9:
		var r: Rect2 = _cell_rect(i)
		var sq = _cells[i]
		if sq == null:
			draw_rect(r, Color(0.135, 0.145, 0.18))
			draw_rect(r, Color(0.26, 0.28, 0.34), false, 2.0)
			continue
		var col: Color = JOBS[sq["def"]["job"]]["color"]
		var fl: float = float(sq["flash"])
		draw_rect(r, col.darkened(0.78).lerp(col.darkened(0.5), fl))
		draw_rect(r, col.lerp(Color.WHITE, fl * 0.7), false, 2.0 + fl * 2.0)


func _draw_wall() -> void:
	var ratio: float = clampf(_wall_hp / _wall_max, 0.0, 1.0)
	var top: float = WALL_RECT.position.y + WALL_RECT.size.y * (1.0 - ratio)
	draw_rect(Rect2(WALL_RECT.position, Vector2(WALL_RECT.size.x, WALL_RECT.size.y * (1.0 - ratio))),
		Color(0.13, 0.12, 0.145))
	var stone := Color(0.52, 0.54, 0.60) if ratio > 0.35 else Color(0.64, 0.40, 0.38)
	stone = stone.lerp(Color(1.0, 0.55, 0.45), _wall_flash * 0.7)
	var standing := Rect2(Vector2(WALL_RECT.position.x, top),
		Vector2(WALL_RECT.size.x, WALL_RECT.end.y - top))
	draw_rect(standing, stone.darkened(0.35))
	var y: float = top
	var band: int = 0
	while y < WALL_RECT.end.y:
		var hh: float = minf(28.0, WALL_RECT.end.y - y)
		draw_rect(Rect2(WALL_RECT.position.x + 4.0, y + 3.0, WALL_RECT.size.x - 8.0, hh - 6.0),
			stone.darkened(0.12 if band % 2 == 0 else 0.22))
		y += 28.0
		band += 1
	draw_rect(standing, Color(0.80, 0.84, 0.92), false, 3.0)


func _draw_shop_bg() -> void:
	for i in SHOP_SLOTS:
		var r: Rect2 = _card_rect(i)
		var card = _shop[i]
		if card == null:
			draw_rect(r, Color(0.10, 0.105, 0.13))
			draw_rect(r, Color(0.20, 0.21, 0.26), false, 2.0)
			continue
		var col: Color = _card_color(card)
		var afford: bool = _gold >= int(card["price"])
		draw_rect(r, col.darkened(0.80 if afford else 0.90))
		draw_rect(r, col.darkened(0.15 if afford else 0.60), false, 2.0)


func _card_color(card: Dictionary) -> Color:
	if card["kind"] == "item":
		return card["def"]["color"]
	return JOBS[card["def"]["job"]]["color"]


# ─── 그리기: 오버레이 (스프라이트 위) ─────────────────────────────────────
func _draw_overlay() -> void:
	_draw_top_hud()
	_draw_cells_hud()
	_draw_bosses_hud()
	_draw_shop_text()
	_draw_side_panels()
	_draw_hint()
	_draw_drag()
	_draw_hover()
	_draw_end_panel()
	if _paused:
		_txt(_font_b, Vector2(W * 0.5 - 120.0, 120.0), "일시정지 — 모든 입력 차단", 30, Color(0.95, 0.85, 0.45))


func _txt(f: Font, p: Vector2, s: String, size: int, c: Color) -> void:
	_overlay.draw_string(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, c)


# 폭을 넘기면 잘라낸다 — 칸 이름이 옆 칸으로 새는 것을 막는다
func _txtw(f: Font, p: Vector2, s: String, size: int, c: Color, wide: float) -> void:
	_overlay.draw_string(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, wide, size, c)


func _bar(r: Rect2, ratio: float, fg: Color, bg: Color) -> void:
	_overlay.draw_rect(r, bg)
	_overlay.draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(ratio, 0.0, 1.0), r.size.y)), fg)


func _draw_top_hud() -> void:
	_txt(_font_b, Vector2(56.0, 52.0), "골드 %d" % _gold, 34, Color(1.0, 0.88, 0.45))

	var ratio: float = clampf(_wall_hp / _wall_max, 0.0, 1.0)
	var wr := Rect2(300.0, 26.0, 360.0, 30.0)
	_bar(wr, ratio, Color(0.70, 0.76, 0.92) if ratio > 0.35 else Color(0.92, 0.42, 0.40),
		Color(0.16, 0.16, 0.20))
	_overlay.draw_rect(wr, Color(0.45, 0.48, 0.56), false, 2.0)
	_txt(_font, Vector2(308.0, 50.0), "성벽 %d / %d" % [int(_wall_hp), int(_wall_max)], 24,
		Color(0.12, 0.13, 0.18) if ratio > 0.35 else Color(0.98, 0.92, 0.92))

	_txt(_font, Vector2(700.0, 50.0), "처치 %d / %d" % [_killed, RUN_BOSSES], 26,
		Color(0.85, 0.88, 0.95))
	_txt(_font, Vector2(880.0, 50.0), "경과 %.1fs" % _elapsed, 26, Color(0.65, 0.68, 0.78))

	var live: int = 0
	for b in _bosses:
		if not b["dead"]:
			live += 1
	_txt(_font_b, Vector2(1060.0, 50.0), "레인 %d마리" % live, 26,
		Color(0.70, 0.74, 0.82) if live <= 1 else Color(0.98, 0.45, 0.42))

	var nxt: String = "—"
	if _next_spawn < _schedule.size():
		nxt = "%.1fs" % maxf(0.0, _spawn_due() - _elapsed)
	_txt(_font, Vector2(1250.0, 50.0), "다음 스폰 %s" % nxt, 26, Color(0.90, 0.78, 0.50))

	var mode: String = "고정 스케줄" if _spawn_mode == SpawnMode.FIXED else "킬 연동"
	_txt(_font_s, Vector2(1500.0, 34.0), "스폰 %s  [S]" % mode, 20, Color(0.58, 0.62, 0.70))
	_txt(_font_s, Vector2(1500.0, 60.0), "속도 %.0fx  [Z][X][C]   [Space] 정지   [R] 재시작" % _speed,
		20, Color(0.58, 0.62, 0.70))

	# 다음에 올 보스 — 대기열이 미리 보여야 쇼핑이 판단이 된다
	var qx: float = 56.0
	_txt(_font_s, Vector2(qx, 100.0), "대기열", 20, Color(0.50, 0.53, 0.60))
	qx += 80.0
	for i in range(_next_spawn, mini(_schedule.size(), _next_spawn + 6)):
		var e: Dictionary = _schedule[i]
		var a: Dictionary = e["arch"]
		var tint: Color = a["tint"]
		_overlay.draw_rect(Rect2(qx, 84.0, 150.0, 26.0), tint.darkened(0.72))
		_txt(_font_s, Vector2(qx + 8.0, 104.0),
			"%s %.0fs" % [a["name"], maxf(0.0, float(e["at"]) - _elapsed)], 19, tint)
		qx += 160.0


func _draw_cells_hud() -> void:
	var target = _target_boss()
	var total_dmg: float = 0.0
	for sq in _cells:
		if sq != null:
			total_dmg += float(sq["dmg"])

	for i in 9:
		var r: Rect2 = _cell_rect(i)
		var sq = _cells[i]
		if sq == null:
			_txt(_font_s, r.position + Vector2(8.0, 24.0), "%d" % _neighbors(i).size(), 18,
				Color(0.32, 0.34, 0.40))
			continue
		var d: Dictionary = sq["def"]
		var job: Dictionary = JOBS[d["job"]]
		# 글자가 무리 실루엣 위에 얹히므로 띠를 깔아 대비를 만든다
		_overlay.draw_rect(Rect2(r.position + Vector2(2.0, 2.0), Vector2(r.size.x - 4.0, 48.0)),
			Color(0.04, 0.04, 0.06, 0.55))
		_overlay.draw_rect(Rect2(r.position + Vector2(2.0, r.size.y - 54.0),
			Vector2(r.size.x - 4.0, 52.0)), Color(0.04, 0.04, 0.06, 0.55))
		var name_w: float = r.size.x - (46.0 if not sq["item"].is_empty() else 12.0)
		_txtw(_font, r.position + Vector2(7.0, 24.0), str(d["name"]), 20,
			Color(0.96, 0.96, 0.99), name_w)
		_txt(_font_s, r.position + Vector2(7.0, 44.0),
			"%s T%d · %d명" % [job["name"], int(d["tier"]), int(sq["members"])], 17,
			Color(0.72, 0.75, 0.82))

		# 통함 / 막힘 — 계산은 게임이 대신한다
		var dtype: String = str(job["dtype"])
		var per: float = _per_hit(sq)
		if dtype == "none":
			_txt(_font_s, r.position + Vector2(7.0, r.size.y - 32.0),
				"인접 +%.1f" % float(d["flat"]), 17, Color(0.95, 0.88, 0.55))
		else:
			var ok: bool = _pierces(per, dtype, target)
			var chip := Rect2(r.position + Vector2(6.0, r.size.y - 48.0), Vector2(56.0, 20.0))
			_overlay.draw_rect(chip, Color(0.18, 0.45, 0.24) if ok else Color(0.48, 0.16, 0.18))
			_txt(_font_s, chip.position + Vector2(7.0, 16.0), "통함" if ok else "막힘", 16,
				Color(0.75, 1.0, 0.80) if ok else Color(1.0, 0.72, 0.70))
			_txt(_font_s, r.position + Vector2(68.0, r.size.y - 32.0),
				"%.1f→%.0f" % [per, _threshold(target, dtype)], 16, Color(0.70, 0.73, 0.80))

		# 칸별 기여 — 왜 이겼는지 항상 알 수 있어야 한다
		if float(sq["dmg"]) > 0.0:
			var share: float = float(sq["dmg"]) / maxf(1.0, total_dmg)
			_txt(_font_s, r.position + Vector2(7.0, r.size.y - 12.0),
				"%d (%d%%)" % [int(sq["dmg"]), int(round(share * 100.0))], 17, Color(1.0, 0.90, 0.58))
			_overlay.draw_rect(Rect2(r.position + Vector2(6.0, r.size.y - 6.0),
				Vector2((r.size.x - 12.0) * share, 4.0)), Color(1.0, 0.85, 0.45))

		# 아이템 — 준비되면 [숫자]로 발동
		if not sq["item"].is_empty():
			var it: Dictionary = sq["item"]
			var icol: Color = it["color"]
			var ready: bool = _item_ready(sq)
			var prog: float = clampf(float(sq["item_beats"]) / float(it["beats"]), 0.0, 1.0)
			var ir := Rect2(r.position + Vector2(r.size.x - 40.0, 6.0), Vector2(34.0, 34.0))
			_overlay.draw_rect(ir, icol.darkened(0.2 if ready else 0.75))
			_overlay.draw_rect(ir, Color(1.0, 1.0, 1.0, 0.85 if ready else 0.3), false, 2.0)
			_txt(_font_s, ir.position + Vector2(11.0, 24.0), "%d" % (i + 1), 20,
				Color(0.1, 0.1, 0.1) if ready else Color(0.8, 0.8, 0.85))
			if not ready:
				_bar(Rect2(ir.position + Vector2(0.0, 36.0), Vector2(34.0, 4.0)), prog,
					icol, Color(0.2, 0.2, 0.24))
			if float(sq["item_flash"]) > 0.0:
				_overlay.draw_rect(r, Color(1.0, 1.0, 1.0, float(sq["item_flash"]) * 0.35), false, 4.0)


func _draw_bosses_hud() -> void:
	var target = _target_boss()
	for b in _bosses:
		if b["dead"]:
			continue
		var a: Dictionary = b["arch"]
		var x: float = float(b["x"])
		var y: float = float(b["lane_y"])
		var tint: Color = a["tint"]
		var ratio: float = clampf(float(b["hp"]) / float(b["hp_max"]), 0.0, 1.0)
		var bar := Rect2(x - 110.0, y - 132.0, 220.0, 15.0)
		_bar(bar, ratio, Color(0.84, 0.28, 0.32), Color(0.16, 0.09, 0.11))
		_overlay.draw_rect(bar, Color(0.90, 0.85, 0.60) if b == target else Color(0.45, 0.30, 0.34),
			false, 2.0)
		_txt(_font, Vector2(bar.position.x, bar.position.y - 8.0),
			"%s #%d  %d" % [a["name"], int(b["index"]) + 1, int(b["hp"])], 21, tint)
		_txt(_font_s, Vector2(bar.position.x, bar.position.y + 32.0),
			"방%.0f 마저%.0f" % [float(b["armor"]), float(b["mres"])], 17, Color(0.78, 0.80, 0.86))

		var tags: String = ""
		if float(b["slow"]) > 0.0:
			tags += "둔화 %.1fs  " % float(b["slow"])
		if int(b["burn"]) > 0:
			tags += "화상 x%d  " % int(b["burn"])
		if float(b["regen"]) > 0.0:
			tags += "회복 %.0f/s" % float(b["regen"])
		if tags != "":
			_txt(_font_s, Vector2(bar.position.x, bar.position.y + 54.0), tags, 17,
				Color(0.70, 0.92, 0.95))

		# 성벽 도달까지 — 초읽기가 판단거리이려면 남은 여유가 보여야 한다
		if x > BOSS_STOP_X:
			var spd: float = float(b["speed"]) * (SLOW_FACTOR if float(b["slow"]) > 0.0 else 1.0)
			var eta: float = (x - BOSS_STOP_X) / maxf(1.0, spd)
			_txt(_font_b, Vector2(x - 40.0, y + 112.0), "%.1fs" % eta, 24,
				Color(0.95, 0.82, 0.45) if eta > 4.0 else Color(1.0, 0.45, 0.42))
			_overlay.draw_line(Vector2(BOSS_STOP_X, y + 126.0), Vector2(x, y + 126.0),
				Color(0.45, 0.40, 0.30, 0.55), 2.0)
		else:
			_txt(_font_b, Vector2(x - 52.0, y + 112.0), "성벽 타격 중", 22, Color(1.0, 0.40, 0.38))

		if float(b["push_flash"]) > 0.0:
			_txt(_font_b, Vector2(x - 30.0, y - 160.0), "밀림!", 26,
				Color(1.0, 0.9, 0.5, float(b["push_flash"])))


func _draw_shop_text() -> void:
	var target = _target_boss()
	for i in SHOP_SLOTS:
		var r: Rect2 = _card_rect(i)
		var card = _shop[i]
		if card == null:
			_txt(_font_s, r.position + Vector2(56.0, 130.0), "다음 갱신까지", 18, Color(0.34, 0.36, 0.42))
			_txt(_font_s, r.position + Vector2(80.0, 152.0), "빈 칸", 18, Color(0.34, 0.36, 0.42))
			continue
		var afford: bool = _gold >= int(card["price"])
		var col: Color = _card_color(card)
		if card["kind"] == "unit":
			var d: Dictionary = card["def"]
			var job: Dictionary = JOBS[d["job"]]
			_txt(_font, r.position + Vector2(10.0, 28.0), str(d["name"]), 21,
				Color(0.97, 0.97, 1.0) if afford else Color(0.55, 0.55, 0.60))
			_txt(_font_s, r.position + Vector2(10.0, 50.0),
				"%s · %s T%d" % [str(d["race"]), str(job["name"]), int(d["tier"])], 17, col)
			_txt(_font_s, r.position + Vector2(10.0, 72.0),
				"%d명 · 박자 %.2fs" % [int(d["members"]), float(job["period"])], 17,
				Color(0.70, 0.73, 0.80))
			var dtype: String = str(job["dtype"])
			if dtype == "none":
				_txt(_font_s, r.position + Vector2(10.0, r.size.y - 48.0),
					"인접 칸 타격당 +%.1f" % float(d["flat"]), 17, Color(0.95, 0.88, 0.55))
			else:
				var per: float = float(d["power"]) / float(d["members"])
				var ok: bool = _pierces(per, dtype, target)
				var chip := Rect2(r.position + Vector2(10.0, r.size.y - 74.0), Vector2(56.0, 20.0))
				_overlay.draw_rect(chip, Color(0.18, 0.45, 0.24) if ok else Color(0.48, 0.16, 0.18))
				_txt(_font_s, chip.position + Vector2(7.0, 16.0), "통함" if ok else "막힘", 16,
					Color(0.75, 1.0, 0.80) if ok else Color(1.0, 0.72, 0.70))
				_txt(_font_s, r.position + Vector2(74.0, r.size.y - 58.0),
					"타격당 %.1f" % per, 17, Color(0.82, 0.86, 0.92))
				_txt(_font_s, r.position + Vector2(10.0, r.size.y - 34.0),
					"통하면 초당 %.0f" % (float(d["power"]) / float(job["period"])), 17,
					Color(0.70, 0.73, 0.80))
		else:
			var it: Dictionary = card["def"]
			_txt(_font, r.position + Vector2(10.0, 28.0), str(it["name"]), 21,
				Color(0.97, 0.97, 1.0) if afford else Color(0.55, 0.55, 0.60))
			_txt(_font_s, r.position + Vector2(10.0, 50.0), "아이템 · %d박자" % int(it["beats"]), 17, col)
			_txtw(_font, r.position + Vector2(10.0, 108.0), str(it["short"]), 20, col, CARD.x - 20.0)
			_txt(_font_s, r.position + Vector2(10.0, 150.0), "부대 위에", 18, Color(0.66, 0.68, 0.75))
			_txt(_font_s, r.position + Vector2(10.0, 172.0), "끌어다 놓는다", 18, Color(0.66, 0.68, 0.75))
		_txt(_font_b, r.position + Vector2(10.0, r.size.y - 14.0), "%dG" % int(card["price"]), 24,
			Color(1.0, 0.88, 0.45) if afford else Color(0.60, 0.42, 0.35))


func _draw_side_panels() -> void:
	# 리롤
	var can_reroll: bool = _gold >= _reroll_price
	_overlay.draw_rect(REROLL_RECT, Color(0.18, 0.20, 0.28) if can_reroll else Color(0.12, 0.12, 0.15))
	_overlay.draw_rect(REROLL_RECT, Color(0.45, 0.52, 0.68) if can_reroll else Color(0.24, 0.25, 0.30),
		false, 2.0)
	_txt(_font_b, REROLL_RECT.position + Vector2(28.0, 110.0), "리롤", 28,
		Color(0.92, 0.95, 1.0) if can_reroll else Color(0.50, 0.52, 0.58))
	_txt(_font, REROLL_RECT.position + Vector2(24.0, 146.0), "%dG" % _reroll_price, 24,
		Color(1.0, 0.88, 0.45) if can_reroll else Color(0.55, 0.42, 0.35))
	_txt(_font_s, REROLL_RECT.position + Vector2(10.0, 176.0), "연속마다 +%d" % REROLL_STEP, 17,
		Color(0.55, 0.58, 0.66))
	_txt(_font_s, REROLL_RECT.position + Vector2(10.0, 198.0), "킬하면 원가", 17, Color(0.55, 0.58, 0.66))

	# 성벽 패널 — 매대 밖 고정 구매
	_overlay.draw_rect(WALLPANEL_RECT, Color(0.13, 0.14, 0.18))
	_overlay.draw_rect(WALLPANEL_RECT, Color(0.32, 0.36, 0.44), false, 2.0)
	_txt(_font_b, WALLPANEL_RECT.position + Vector2(14.0, 36.0), "성벽", 24, Color(0.85, 0.90, 1.0))

	var rr: Rect2 = _repair_rect()
	var can_rep: bool = _gold >= _repair_price and _wall_hp < _wall_max
	_overlay.draw_rect(rr, Color(0.20, 0.30, 0.24) if can_rep else Color(0.13, 0.14, 0.16))
	_overlay.draw_rect(rr, Color(0.45, 0.70, 0.52) if can_rep else Color(0.24, 0.26, 0.30), false, 2.0)
	_txt(_font, rr.position + Vector2(12.0, 32.0), "수리  +%d" % int(REPAIR_HEAL), 22,
		Color(0.90, 1.0, 0.92) if can_rep else Color(0.50, 0.52, 0.58))
	_txt(_font, rr.position + Vector2(12.0, 62.0), "%dG" % _repair_price, 22,
		Color(1.0, 0.88, 0.45) if can_rep else Color(0.55, 0.42, 0.35))

	var ur: Rect2 = _upgrade_rect()
	var can_up: bool = _gold >= _upgrade_price
	_overlay.draw_rect(ur, Color(0.22, 0.24, 0.34) if can_up else Color(0.13, 0.14, 0.16))
	_overlay.draw_rect(ur, Color(0.50, 0.56, 0.78) if can_up else Color(0.24, 0.26, 0.30), false, 2.0)
	_txt(_font, ur.position + Vector2(12.0, 32.0), "최대HP +%d" % int(UPGRADE_GAIN), 22,
		Color(0.92, 0.94, 1.0) if can_up else Color(0.50, 0.52, 0.58))
	_txt(_font, ur.position + Vector2(12.0, 62.0), "%dG" % _upgrade_price, 22,
		Color(1.0, 0.88, 0.45) if can_up else Color(0.55, 0.42, 0.35))

	# 측정 패널
	_overlay.draw_rect(STATS_RECT, Color(0.11, 0.12, 0.15))
	_overlay.draw_rect(STATS_RECT, Color(0.28, 0.30, 0.36), false, 2.0)
	var p: Vector2 = STATS_RECT.position
	_txt(_font_b, p + Vector2(14.0, 34.0), "측정", 22, Color(0.80, 0.84, 0.92))
	var avg: float = 0.0
	for t in _log_kill_times:
		avg += float(t)
	if not _log_kill_times.is_empty():
		avg /= float(_log_kill_times.size())
	_txt(_font_s, p + Vector2(14.0, 64.0), "평균 처치 소요  %.1fs" % avg, 18, Color(0.72, 0.76, 0.84))
	_txt(_font_s, p + Vector2(14.0, 90.0), "마지막 처치     %.1fs" %
		(float(_log_kill_times[-1]) if not _log_kill_times.is_empty() else 0.0), 18,
		Color(0.72, 0.76, 0.84))
	_txt(_font_s, p + Vector2(14.0, 116.0), "최대 겹침       %d마리" % _log_overlap_peak, 18,
		Color(0.72, 0.76, 0.84))
	_txt(_font_s, p + Vector2(14.0, 142.0), "성벽 총 손실    %d" % int(_log_wall_lost), 18,
		Color(0.72, 0.76, 0.84))
	var blocked: float = 0.0
	if _log_total_hits > 0:
		blocked = float(_log_blocked_hits) / float(_log_total_hits) * 100.0
	_txt(_font_s, p + Vector2(14.0, 168.0), "막힌 타격 비율  %.0f%%" % blocked, 18,
		Color(0.95, 0.72, 0.68) if blocked > 30.0 else Color(0.72, 0.76, 0.84))
	var dps: float = 0.0
	for sq in _cells:
		if sq != null:
			dps += float(sq["dmg"])
	_txt(_font_s, p + Vector2(14.0, 194.0), "누적 딜         %d" % int(dps), 18, Color(0.72, 0.76, 0.84))
	_txt(_font_s, p + Vector2(14.0, 220.0), "배치            %d/9" % _placed_count(), 18,
		Color(0.72, 0.76, 0.84))


func _placed_count() -> int:
	var n: int = 0
	for sq in _cells:
		if sq != null:
			n += 1
	return n


func _draw_hint() -> void:
	_txt(_font_s, Vector2(56.0, 984.0),
		"카드를 칸으로 끌어다 놓으면 구매 · 아이템은 부대 위로 · 배치된 부대끼리 끌면 자리 교체 · "
		+ "부대를 그냥 클릭하거나 [1]~[9]로 아이템 발동",
		20, Color(0.48, 0.52, 0.60))
	_txt(_font_s, Vector2(56.0, 1012.0),
		"칸의 '5.0→20'은 타격당 딜 5.0 대 보스 문턱 20 이라는 뜻이다. 넘으면 통함(전부), 못 넘으면 막힘(8%). "
		+ "화상만 문턱을 무시한다.",
		20, Color(0.44, 0.48, 0.56))


func _draw_drag() -> void:
	if _drag_kind == "" or not _drag_moved:
		return
	var label: String = ""
	var col: Color = Color(0.7, 0.7, 0.8)
	if _drag_kind == "shop":
		var card = _shop[_drag_from]
		if card == null:
			return
		label = str(card["def"]["name"])
		col = _card_color(card)
	else:
		var sq = _cells[_drag_from]
		if sq == null:
			return
		label = str(sq["def"]["name"])
		col = JOBS[sq["def"]["job"]]["color"]
	var r := Rect2(_mouse - Vector2(80.0, 26.0), Vector2(160.0, 52.0))
	_overlay.draw_rect(r, col.darkened(0.55))
	_overlay.draw_rect(r, col, false, 2.0)
	_txt(_font, r.position + Vector2(10.0, 32.0), label, 20, Color(1.0, 1.0, 1.0))

	# 유효한 목적지만 밝힌다 — 무효한 곳에 놓으면 취소·무과금이다
	for i in 9:
		if not _valid_drop(i):
			continue
		var cr: Rect2 = _cell_rect(i)
		_overlay.draw_rect(cr, Color(0.55, 0.85, 0.60, 0.16))
		_overlay.draw_rect(cr, Color(0.60, 0.95, 0.66, 0.75), false, 3.0)


func _valid_drop(cell_idx: int) -> bool:
	if _drag_kind == "cell":
		return cell_idx != _drag_from
	if _drag_kind != "shop":
		return false
	var card = _shop[_drag_from]
	if card == null or _gold < int(card["price"]):
		return false
	if card["kind"] == "item":
		return _cells[cell_idx] != null
	return true


func _draw_hover() -> void:
	if _drag_kind != "":
		return
	# 실시간이라 "읽으려면 클릭"은 무겁다 — 호버로 바로 편다
	for i in SHOP_SLOTS:
		if not _card_rect(i).has_point(_mouse) or _shop[i] == null:
			continue
		var card: Dictionary = _shop[i]
		var lines: Array = []
		if card["kind"] == "unit":
			var d: Dictionary = card["def"]
			var job: Dictionary = JOBS[d["job"]]
			lines.append("%s — %s / %s T%d" % [str(d["name"]), str(d["race"]), str(job["name"]),
				int(d["tier"])])
			if str(job["dtype"]) == "none":
				lines.append("비공격. 인접 칸의 타격마다 +%.1f 고정 부여" % float(d["flat"]))
				lines.append("고정값이라 인원 많고 박자 빠른 부대 옆에서 가장 크게 불어난다")
			else:
				lines.append("칸 공격력 %.0f 를 %d명이 나눠 친다 → 타격당 %.1f" %
					[float(d["power"]), int(d["members"]), float(d["power"]) / float(d["members"])])
				lines.append("%.2fs 박자마다 %d회 판정 · 초당 %.0f (통할 때)" %
					[float(job["period"]), int(d["members"]), float(d["power"]) / float(job["period"])])
				lines.append("타격당 딜이 보스 문턱을 넘어야 통한다 — 인원이 많을수록 잘게 쪼개져 막힌다")
		else:
			var it: Dictionary = card["def"]
			lines.append("%s — 아이템 (동사)" % str(it["name"]))
			lines.append(str(it["desc"]))
			lines.append("%d박자마다 준비된다. 박자는 몸이 정하므로 빠른 부대는 자주, 소수정예는 크게" %
				int(it["beats"]))
		_tooltip(_card_rect(i).position + Vector2(0.0, -14.0), lines)
		return

	for i in 9:
		if not _cell_rect(i).has_point(_mouse) or _cells[i] == null:
			continue
		var sq: Dictionary = _cells[i]
		var d2: Dictionary = sq["def"]
		var job2: Dictionary = JOBS[d2["job"]]
		var l2: Array = []
		l2.append("%s — %s T%d · %d명" % [str(d2["name"]), str(job2["name"]), int(d2["tier"]),
			int(sq["members"])])
		if str(job2["dtype"]) != "none":
			l2.append("타격당 %.1f (기본 %.1f + 인접 사제 %.1f) · 박자 %.2fs" %
				[_per_hit(sq), float(d2["power"]) / float(sq["members"]), float(sq["flat"]),
				float(sq["period"])])
		else:
			l2.append("인접 %d칸에 타격당 +%.1f" % [_neighbors(i).size(), float(d2["flat"])])
		l2.append("누적 %d · %d타" % [int(sq["dmg"]), int(sq["hits"])])
		if not sq["item"].is_empty():
			l2.append("%s — %d/%d박자%s" % [str(sq["item"]["name"]), int(sq["item_beats"]),
				int(sq["item"]["beats"]), "  [준비됨]" if _item_ready(sq) else ""])
		_tooltip(_cell_rect(i).position + Vector2(0.0, -14.0), l2)
		return


func _tooltip(anchor: Vector2, lines: Array) -> void:
	var wide: float = 0.0
	for l in lines:
		wide = maxf(wide, _font_s.get_string_size(str(l), HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x)
	var box := Rect2(anchor - Vector2(0.0, float(lines.size()) * 26.0 + 16.0),
		Vector2(wide + 28.0, float(lines.size()) * 26.0 + 16.0))
	box.position.x = clampf(box.position.x, 8.0, W - box.size.x - 8.0)
	box.position.y = maxf(8.0, box.position.y)
	_overlay.draw_rect(box, Color(0.08, 0.09, 0.12, 0.97))
	_overlay.draw_rect(box, Color(0.45, 0.50, 0.60), false, 2.0)
	var y: float = box.position.y + 28.0
	for l in lines:
		_txt(_font_s, Vector2(box.position.x + 14.0, y), str(l), 19, Color(0.86, 0.89, 0.95))
		y += 26.0


func _draw_end_panel() -> void:
	if _phase == Phase.RUNNING:
		return
	var panel := Rect2(560.0, 230.0, 800.0, 420.0)
	_overlay.draw_rect(panel, Color(0.10, 0.11, 0.15, 0.97))
	_overlay.draw_rect(panel, Color(0.55, 0.60, 0.72), false, 3.0)
	var win: bool = _phase == Phase.CLEAR
	_txt(_font_b, panel.position + Vector2(36.0, 74.0), "클리어" if win else "성벽 붕괴", 46,
		Color(0.60, 0.92, 0.66) if win else Color(0.94, 0.44, 0.42))
	var avg: float = 0.0
	for t in _log_kill_times:
		avg += float(t)
	if not _log_kill_times.is_empty():
		avg /= float(_log_kill_times.size())
	var blocked: float = 0.0
	if _log_total_hits > 0:
		blocked = float(_log_blocked_hits) / float(_log_total_hits) * 100.0
	var rows: Array = [
		"처치 %d / %d · 경과 %.1fs" % [_killed, RUN_BOSSES, _elapsed],
		"성벽 %d / %d (총 손실 %d)" % [int(_wall_hp), int(_wall_max), int(_log_wall_lost)],
		"평균 처치 소요 %.1fs · 최대 겹침 %d마리" % [avg, _log_overlap_peak],
		"막힌 타격 비율 %.0f%%" % blocked,
		"남은 골드 %d" % _gold,
	]
	var y: float = 140.0
	for r in rows:
		_txt(_font, panel.position + Vector2(36.0, y), str(r), 24, Color(0.86, 0.89, 0.95))
		y += 38.0
	_txt(_font_s, panel.position + Vector2(36.0, 390.0), "[R] 다시 시작", 20, Color(0.65, 0.70, 0.80))
