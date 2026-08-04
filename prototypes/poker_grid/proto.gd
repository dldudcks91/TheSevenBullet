# PROTOTYPE - NOT FOR PRODUCTION
# Question: 같은 16장을 4×4 어디에 놓느냐가 결과를 유의미하게 바꾸는가, 그리고 그게 화면에서 읽히는가?
# Date: 2026-08-03
#
# grid_wall_defense(3×3 인접)와 짝을 이루는 비교용 프로토다.
# 몬스터·성벽·측정 방식(성벽 잔여 %)을 동일하게 맞춰 두 격자 모델을 직접 비교한다.
#
# 3×3과 결정적으로 다른 점: 카드 풀이 고정이다.
# 딜된 16장을 전부 놓아야 전투가 시작되므로, 변수는 오직 "배치 순서" 하나다.
# (3×3은 어떤 영웅을 쓸지도 변수라 배치 효과가 섞여 들어간다)
#
# GRID_MODEL_OPTIONS.md 결정 반영: 핸드 모델이므로 인접 버프는 넣지 않는다.
#
# 에셋: TheSevenAutoBattle에서 쓰던 minifolks 스프라이트 + Galmuri 픽셀 폰트를 이 폴더로 복사해 왔다.
# 스프라이트 로딩 방식도 그쪽 sprite_frame_loader.gd 를 베껴온 것이다(프로토는 import 금지, 복사만 허용).

extends Node2D

# ─── 레이아웃 (하드코딩, 1920×1080) ────────────────────────────────────────
# 병력(4×4) → 성벽 → 몬스터 순으로 왼쪽에서 오른쪽.
# 성벽은 병력 오른쪽 타격 지점에 서고, 몬스터는 성벽 앞에서 멈춰 성벽을 때린다.
const GRID_ORIGIN := Vector2(60.0, 262.0)
const CELL := 145.0
const ROW_LABEL_X := 656.0
const WALL_RECT := Rect2(850.0, 250.0, 76.0, 600.0)
const MONSTER_STOP_X := 1010.0         # 몬스터 중심이 멈추는 곳 — 성벽 바로 오른쪽
const MONSTER_START_X := 1770.0        # 760px 이동 = 접근에 10초
const MONSTER_Y := 550.0               # 성벽 세로 중앙
const TRAY_ORIGIN := Vector2(60.0, 878.0)
const TRAY_CARD := Vector2(96.0, 128.0)
const TRAY_GAP := 14.0

# ─── 밸런스 (전부 임시값) ──────────────────────────────────────────────────
# 성벽/타격 수치는 3×3 프로토와 동일하게 맞춰 두 모델을 같은 자로 잰다.
# 헤드리스 시뮬로 맞춘 값 — 최적 배치는 12/12 승리(잔여 평균 57%), 무작위 배치는 8/12 패배.
# 즉 "배치를 생각했는가"가 승패를 가르는 구간에 몬스터 체력을 세웠다.
const MONSTER_HP := 5000.0
const MONSTER_SPEED := 76.0
const WALL_HP := 400.0
const WALL_HIT_DAMAGE := 40.0
const WALL_HIT_INTERVAL := 1.5         # → 성벽이 버티는 시간 15초, 총 예산 약 25초

const CLERIC_FLAT_ATK := 3.0           # Q: 같은 행·열의 다른 카드에 공격력 +고정
const LEADER_ASPD := 0.10              # K: 전군 공속 +고정 (K 1장당)
const CLUB_LINE_BONUS := 0.15          # ♣: 자기가 속한 줄의 핸드 보너스 가산
const BURN_TICK := 0.55                # ♥: 화상 1스택당 초당 피해

enum { SPADE, HEART, DIAMOND, CLUB }

const RANK_ACE := 14

const SUIT_COLOR := {
	SPADE: Color(0.94, 0.38, 0.34),
	HEART: Color(0.96, 0.62, 0.26),
	DIAMOND: Color(0.40, 0.78, 0.96),
	CLUB: Color(0.68, 0.55, 0.95),
}

const SUIT_NAME := {
	SPADE: "공격형", HEART: "지속형", DIAMOND: "속도형", CLUB: "유틸형",
}

# ─── 스프라이트 ───────────────────────────────────────────────────────────
# 카드 문법을 그대로 스프라이트에 옮긴다: 무늬 = 진영, 랭크 = 역할.
# ♥가 화상이라 불의 교단, ♦가 속도형이라 다크엘프 — 무늬 성격과 진영을 맞춰 뒀다.
const SPRITE_ROOT := "res://assets/units"
const ANIMS := {
	"idle":   {"folders": ["Idle"],         "fps": 8.0,  "loop": true},
	"walk":   {"folders": ["Walk", "Move"], "fps": 10.0, "loop": true},
	# attack은 루프다 — 전투 중 유닛은 idle로 돌아가지 않고 자기 공격속도로 계속 돈다.
	# (몬스터만 예외로 _ready에서 loop를 꺼서 한 번씩만 휘두르게 한다)
	"attack": {"folders": ["Attack"],       "fps": 12.0, "loop": true},
	"hit":    {"folders": ["Hit"],          "fps": 12.0, "loop": false},
	"death":  {"folders": ["Death"],        "fps": 8.0,  "loop": false},
}
const SUIT_FACTION := {
	SPADE:   "minifolks/MiniBeastmens",
	HEART:   "minifolks/MiniOrderOfTheFire",
	DIAMOND: "minifolks/MiniDarkElves",
	CLUB:    "minifolks/MinifolksHumans",
}
const ROLE_UNIT := {
	SPADE: {"soldier": "MiniFoxSwordsman", "ranged": "MiniWolfPathfinder", "elite": "MiniBearWarrior",
		"priest": "MiniDeerDruid", "leader": "MiniLionKnight", "wild": "MiniCatRobber"},
	HEART: {"soldier": "MiniFireWarrior", "ranged": "MiniFireMage", "elite": "MiniFirePrince",
		"priest": "MiniFirePriestess", "leader": "MiniFirePrincess", "wild": "MiniFireElemental"},
	DIAMOND: {"soldier": "MiniDarkElfSwordsman", "ranged": "MiniDarkElfArcher", "elite": "MiniDarkElfGuard",
		"priest": "MiniDarkElfSorceress", "leader": "MiniDarkElfSpellstealer", "wild": "MiniDarkElfAssassin"},
	CLUB: {"soldier": "MiniSwordMan", "ranged": "MiniArcherMan", "elite": "MiniShieldMan",
		"priest": "MiniArchMage", "leader": "MiniKingMan", "wild": "MiniPrinceMan"},
}
const MONSTER_SPRITE := "minifolks/MiniBigMonsters/MiniOrcMutant/no_outline"
const CARD_SPRITE_SCALE := 2.5
const TRAY_SPRITE_SCALE := 1.5
const MONSTER_SPRITE_SCALE := 4.5

# 랭크 = 직업 원형. 무늬 = 변형. 둘의 곱으로 52종이 나온다.
const HAND_BONUS := {
	"하이카드": 0.00,
	"원페어": 0.20,
	"투페어": 0.55,
	"플러시": 0.55,
	"스트레이트": 0.60,
	"트리플": 0.60,
	"스트레이트 플러시": 1.60,
	"포카드": 2.00,
}

enum State { PLACING, BATTLE, RESULT }

var _state: int = State.PLACING
var _board: Array = []                 # 16칸 — null 또는 런타임 카드 Dictionary
var _tray: Array = []                  # 아직 안 놓은 카드 정의
var _picked: Dictionary = {}           # {"src": "tray"|"board", "i": int}
var _lines: Array = []                 # 8줄 평가 결과 (행 4 + 열 4)
var _deal_seed: int = 1
var _shuffle_n: int = 0
var _speed: float = 1.0

var _monster_x: float = MONSTER_START_X
var _monster_hp: float = MONSTER_HP
var _wall_hp: float = WALL_HP
var _wall_timer: float = 0.0
var _wall_flash: float = 0.0
var _elapsed: float = 0.0
var _burn_total: float = 0.0
var _won: bool = false

var _font: Font = load("res://assets/fonts/Galmuri11.ttf")
var _font_b: Font = load("res://assets/fonts/Galmuri11-Bold.ttf")
var _font_s: Font = load("res://assets/fonts/Galmuri9.ttf")

var _frames: Dictionary = {}           # sprite_dir → SpriteFrames (처음 쓸 때 만들어 캐시)
var _board_sprites: Array = []         # 16개 — 칸 중앙 고정
var _tray_sprites: Array = []          # 16개 — 손패 칸 고정
var _monster_sprite: AnimatedSprite2D
var _overlay: Node2D                   # 결과 패널 — 스프라이트 위에 그려야 해서 따로 둔다


func _ready() -> void:
	for i in 16:
		var s := _make_sprite(CARD_SPRITE_SCALE)
		s.position = _cell_rect(i).position + Vector2(69.0, 74.0)
		_board_sprites.append(s)
	for i in 16:
		var t := _make_sprite(TRAY_SPRITE_SCALE)
		t.position = _tray_rect(i).position + Vector2(48.0, 58.0)
		_tray_sprites.append(t)

	_monster_sprite = _make_sprite(MONSTER_SPRITE_SCALE)
	_monster_sprite.sprite_frames = _get_frames(MONSTER_SPRITE)
	# 몬스터는 1.5초에 한 번만 때린다 — 휘두르고 idle로 돌아가야 한다
	_monster_sprite.sprite_frames.set_animation_loop("attack", false)
	_monster_sprite.flip_h = true          # 좌측(성벽)을 바라본다
	_monster_sprite.position = Vector2(MONSTER_START_X, MONSTER_Y)
	_monster_sprite.visible = true          # 배치 중에도 진입로 끝에 서 있어야 무엇과 싸우는지 읽힌다
	_monster_sprite.play("idle")

	_overlay = Node2D.new()
	_overlay.z_index = 100
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)

	_deal(_deal_seed)


func _make_sprite(scale_mult: float) -> AnimatedSprite2D:
	var s := AnimatedSprite2D.new()
	s.scale = Vector2.ONE * scale_mult
	s.centered = true
	s.visible = false
	add_child(s)
	return s


# TheSevenAutoBattle/src/battle/sprite_frame_loader.gd 를 프로토용으로 줄여 베낀 것.
# 폴더가 없으면 그 애니메이션만 비워 두고 넘어간다.
func _get_frames(sprite_dir: String) -> SpriteFrames:
	if _frames.has(sprite_dir):
		return _frames[sprite_dir]
	var frames := SpriteFrames.new()
	if frames.has_animation(&"default"):
		frames.remove_animation(&"default")
	for anim_name in ANIMS.keys():
		var conf: Dictionary = ANIMS[anim_name]
		frames.add_animation(anim_name)
		frames.set_animation_speed(anim_name, conf["fps"])
		frames.set_animation_loop(anim_name, conf["loop"])
		var dir_path: String = ""
		var dir: DirAccess = null
		for folder in conf["folders"]:
			var p: String = "%s/%s/%s" % [SPRITE_ROOT, sprite_dir, folder]
			var d := DirAccess.open(p)
			if d != null:
				dir_path = p
				dir = d
				break
		if dir == null:
			push_warning("프레임 폴더 없음: %s/%s" % [sprite_dir, ",".join(conf["folders"])])
			continue
		var pngs: Array[String] = []
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if not dir.current_is_dir() and fname.ends_with(".png"):
				pngs.append(fname)
			fname = dir.get_next()
		dir.list_dir_end()
		pngs.sort()
		for f in pngs:
			var tex: Texture2D = load("%s/%s" % [dir_path, f])
			if tex != null:
				frames.add_frame(anim_name, tex)
	_frames[sprite_dir] = frames
	return frames


func _role_of(rank: int) -> String:
	match rank:
		11: return "elite"      # J 전사 — 단일 최강 딜러
		12: return "priest"     # Q 성직자
		13: return "leader"     # K 리더
		14: return "wild"       # A 와일드
	return "soldier" if rank <= 6 else "ranged"


func _sprite_dir(card: Dictionary) -> String:
	var suit: int = int(card["suit"])
	return "%s/%s/no_outline" % [SUIT_FACTION[suit], ROLE_UNIT[suit][_role_of(int(card["rank"]))]]


# ─── 딜 / 배치 ────────────────────────────────────────────────────────────
func _deal(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var deck: Array = []
	for suit in 4:
		for rank in range(2, 15):
			deck.append({"rank": rank, "suit": suit})
	# Fisher-Yates — Array.shuffle()은 전역 RNG를 써서 재현이 안 된다
	for i in range(deck.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var t = deck[i]
		deck[i] = deck[j]
		deck[j] = t

	_board.clear()
	for _i in 16:
		_board.append(null)
	_tray = deck.slice(0, 16)
	_picked = {}
	_shuffle_n = 0
	_state = State.PLACING
	_monster_x = MONSTER_START_X
	_monster_hp = MONSTER_HP
	_wall_hp = WALL_HP
	_wall_flash = 0.0
	_elapsed = 0.0
	_burn_total = 0.0
	_monster_sprite.position.x = MONSTER_START_X
	_monster_sprite.play("idle")
	_recalc()


func _random_arrange() -> void:
	var all: Array = []
	for c in _tray:
		all.append(c)
	for h in _board:
		if h != null:
			all.append(h["card"])
	_shuffle_n += 1
	var rng := RandomNumberGenerator.new()
	rng.seed = _deal_seed * 7919 + _shuffle_n
	for i in range(all.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var t = all[i]
		all[i] = all[j]
		all[j] = t
	for i in 16:
		_board[i] = _make_runtime(all[i])
	_tray.clear()
	_picked = {}
	_recalc()


func _clear_board() -> void:
	for i in 16:
		if _board[i] != null:
			_tray.append(_board[i]["card"])
			_board[i] = null
	_picked = {}
	_recalc()


func _make_runtime(card: Dictionary) -> Dictionary:
	return {"card": card, "atk": 0.0, "aspd": 0.0, "mult": 1.0,
		"cd": 0.0, "dmg": 0.0, "hits": 0, "burn": 0.0, "burn_dmg": 0.0, "flash": 0.0}


func _placed_count() -> int:
	var n: int = 0
	for h in _board:
		if h != null:
			n += 1
	return n


# ─── 카드 스탯 ────────────────────────────────────────────────────────────
# 랭크(원형)로 뼈대를 잡고 무늬(변형)로 곱한다. 신규 카드는 원형만 늘리면 된다.
func _base_stats(card: Dictionary) -> Dictionary:
	var rank: int = int(card["rank"])
	var atk: float
	var aspd: float
	match rank:
		11: atk = 14.0; aspd = 0.70      # J 전사 — 단일 최강 딜러
		12: atk = 4.0;  aspd = 0.60      # Q 성직자 — 자체 딜은 버리고 줄을 버프
		13: atk = 10.0; aspd = 0.60      # K 리더 — 전군 공속
		14: atk = 5.0;  aspd = 0.50      # A 와일드 — 성능을 핸드로 돌려받는다
		_:  atk = 3.0 + float(rank) * 0.9; aspd = 0.60   # 숫자 = 병사, 클수록 강함
	match int(card["suit"]):
		SPADE:   atk *= 1.35
		HEART:   atk *= 0.90
		DIAMOND: atk *= 0.75; aspd *= 1.60
		CLUB:    atk *= 0.90
	return {"atk": atk, "aspd": aspd}


func _card_dps(card: Dictionary) -> float:
	var s: Dictionary = _base_stats(card)
	return float(s["atk"]) * float(s["aspd"])


func _rank_text(rank: int) -> String:
	match rank:
		11: return "J"
		12: return "Q"
		13: return "K"
		14: return "A"
	return str(rank)


# ─── 핸드 평가 ────────────────────────────────────────────────────────────
# A는 랭크·무늬 양쪽으로 와일드다. 벤치가 없어 드래프트가 빡빡한 구조라
# 무늬 변경 수단이 사실상 필수 — 그 역할을 A가 맡는지 여기서 본다.
func _eval_line(cards: Array) -> Dictionary:
	if cards.size() < 4:
		return {"name": "미완성", "bonus": 0.0, "clubs": 0}

	var wilds: int = 0
	var nat_ranks: Array = []
	var nat_suits: Array = []
	var clubs: int = 0
	for c in cards:
		if int(c["suit"]) == CLUB:
			clubs += 1
		if int(c["rank"]) == RANK_ACE:
			wilds += 1
		else:
			nat_ranks.append(int(c["rank"]))
			nat_suits.append(int(c["suit"]))

	var is_flush: bool = true
	for s in nat_suits:
		if s != nat_suits[0]:
			is_flush = false
			break

	var dup: bool = false
	var seen: Dictionary = {}
	var counts: Dictionary = {}
	for r in nat_ranks:
		if seen.has(r):
			dup = true
		seen[r] = true
		counts[r] = int(counts.get(r, 0)) + 1

	var is_straight: bool = false
	if not dup:
		if nat_ranks.is_empty():
			is_straight = true
		else:
			is_straight = (int(nat_ranks.max()) - int(nat_ranks.min())) <= 3

	var c1: int = 0
	var c2: int = 0
	for k in counts:
		var v: int = int(counts[k])
		if v > c1:
			c2 = c1
			c1 = v
		elif v > c2:
			c2 = v

	# 성립하는 족보를 전부 모아 가장 높은 보너스를 취한다 — 우선순위 표를 따로 두지 않는다
	var best_name: String = "하이카드"
	var best: float = 0.0
	var cands: Array = []
	if c1 + wilds >= 2:
		cands.append("원페어")
	if (c1 >= 2 and c2 >= 2) or (c1 >= 2 and wilds >= 1) or wilds >= 2:
		cands.append("투페어")
	if c1 + wilds >= 3:
		cands.append("트리플")
	if c1 + wilds >= 4:
		cands.append("포카드")
	if is_flush:
		cands.append("플러시")
	if is_straight:
		cands.append("스트레이트")
	if is_flush and is_straight:
		cands.append("스트레이트 플러시")
	for n in cands:
		var b: float = float(HAND_BONUS[n])
		if b > best:
			best = b
			best_name = n

	return {"name": best_name, "bonus": best + CLUB_LINE_BONUS * float(clubs), "clubs": clubs}


func _line_indices(line: int) -> Array:
	# 0~3 = 행, 4~7 = 열. 모든 칸이 정확히 한 행과 한 열에 속한다 —
	# 그래서 4×4에서는 칸마다 "줄 두 개"가 걸리고, 위치가 곧 결정이 된다.
	var out: Array = []
	if line < 4:
		for c in 4:
			out.append(line * 4 + c)
	else:
		for r in 4:
			out.append(r * 4 + (line - 4))
	return out


# 배치가 바뀔 때마다 다시 계산한다 — 배치 중에도 배수가 실시간으로 보여야 판단이 된다.
func _recalc() -> void:
	_lines.clear()
	for line in 8:
		var cards: Array = []
		for i in _line_indices(line):
			if _board[i] != null:
				cards.append(_board[i]["card"])
		_lines.append(_eval_line(cards))

	var leaders: int = 0
	for h in _board:
		if h != null and int(h["card"]["rank"]) == 13:
			leaders += 1

	for i in 16:
		var h = _board[i]
		if h == null:
			continue
		var s: Dictionary = _base_stats(h["card"])
		h["atk"] = float(s["atk"])
		h["aspd"] = float(s["aspd"]) + LEADER_ASPD * float(leaders)

	# Q는 같은 행·열의 다른 카드를 버프한다. 인접이 아니라 "줄"로 거는 게 이 모델의 문법이다.
	for i in 16:
		var q = _board[i]
		if q == null or int(q["card"]["rank"]) != 12:
			continue
		for j in 16:
			if j == i:
				continue
			if (j / 4 == i / 4) or (j % 4 == i % 4):
				if _board[j] != null:
					_board[j]["atk"] = float(_board[j]["atk"]) + CLERIC_FLAT_ATK

	for i in 16:
		var h = _board[i]
		if h == null:
			continue
		h["mult"] = 1.0 + float(_lines[i / 4]["bonus"]) + float(_lines[4 + i % 4]["bonus"])

	_sync_sprites()
	_redraw()


func _hit_damage(h: Dictionary) -> float:
	return float(h["atk"]) * float(h["mult"])


# ─── 상태 전이 ────────────────────────────────────────────────────────────
func _start_battle() -> void:
	_recalc()
	_monster_x = MONSTER_START_X
	_monster_hp = MONSTER_HP
	_wall_hp = WALL_HP
	_wall_timer = 0.0
	_wall_flash = 0.0
	_elapsed = 0.0
	_burn_total = 0.0
	_won = false
	for h in _board:
		if h != null:
			h["cd"] = 1.0 / float(h["aspd"])
			h["dmg"] = 0.0
			h["hits"] = 0
			h["burn"] = 0.0
			h["burn_dmg"] = 0.0
			h["flash"] = 0.0
	_picked = {}
	_monster_sprite.position.x = MONSTER_START_X
	_monster_sprite.visible = true
	_monster_sprite.play("walk")
	_state = State.BATTLE


# ─── 전투 루프 ────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if _state != State.BATTLE:
		return
	var dt: float = delta * _speed
	_elapsed += dt
	_wall_flash = maxf(0.0, _wall_flash - dt * 4.0)

	if _monster_x > MONSTER_STOP_X:
		_monster_x = maxf(MONSTER_STOP_X, _monster_x - MONSTER_SPEED * dt)
		if _monster_x <= MONSTER_STOP_X:
			_wall_timer = WALL_HIT_INTERVAL * 0.5
	else:
		_wall_timer -= dt
		if _wall_timer <= 0.0:
			_wall_timer += WALL_HIT_INTERVAL
			_wall_hp -= WALL_HIT_DAMAGE
			_wall_flash = 1.0
			_monster_sprite.play("attack")

	for h in _board:
		if h == null:
			continue
		h["flash"] = maxf(0.0, float(h["flash"]) - dt * 6.0)

		# 화상은 직접타격과 별개 채널이다 — 핸드 배수를 타지 않는 대신 시간이 갈수록 누적된다
		if float(h["burn"]) > 0.0:
			var bd: float = float(h["burn"]) * BURN_TICK * dt
			_monster_hp -= bd
			h["burn_dmg"] = float(h["burn_dmg"]) + bd
			h["dmg"] = float(h["dmg"]) + bd
			_burn_total += bd

		h["cd"] = float(h["cd"]) - dt
		while float(h["cd"]) <= 0.0 and _monster_hp > 0.0:
			h["cd"] = float(h["cd"]) + 1.0 / float(h["aspd"])
			var dmg: float = _hit_damage(h)
			_monster_hp -= dmg
			h["dmg"] = float(h["dmg"]) + dmg
			h["hits"] = int(h["hits"]) + 1
			h["flash"] = 1.0
			if int(h["card"]["suit"]) == HEART:
				h["burn"] = float(h["burn"]) + 1.0

	if _monster_hp <= 0.0:
		_monster_hp = 0.0
		_won = true
		_monster_sprite.play("death")
		_state = State.RESULT
	elif _wall_hp <= 0.0:
		_wall_hp = 0.0
		_won = false
		_state = State.RESULT

	_sync_sprites()
	_redraw()


# 스프라이트는 전투 수치와 분리해서 "보이는 것"만 담당한다.
func _sync_sprites() -> void:
	for i in 16:
		var s: AnimatedSprite2D = _board_sprites[i]
		var h = _board[i]
		if h == null:
			s.visible = false
			continue
		s.visible = true
		var f: SpriteFrames = _get_frames(_sprite_dir(h["card"]))
		if s.sprite_frames != f:
			s.sprite_frames = f
			s.play("idle")

		# 공격 애니메이션 한 바퀴 = 공격 한 번이 되도록 재생속도를 유닛마다 맞춘다.
		# 이렇게 안 하면 애니메이션 길이(0.5~0.9초)와 공격 간격(0.7~2.0초)이 어긋나
		# 사이에 idle이 한 프레임씩 끼어들어 깜빡이고, 빠른 유닛은 중간에 끊긴다.
		# 덤으로 "빨리 움직이는 유닛 = 공속 빠른 유닛"이 눈으로 읽힌다.
		if _state == State.BATTLE:
			# 하한 0.5 — 느린 유닛이 슬로모션으로 보이지 않게. 루프라 어긋나도 티가 안 난다.
			var fc: float = maxf(1.0, float(f.get_frame_count("attack")))
			s.speed_scale = _speed * clampf(fc * float(h["aspd"]) / float(ANIMS["attack"]["fps"]), 0.5, 2.0)
			if s.animation != &"attack":
				s.play("attack")
		else:
			s.speed_scale = 1.0
			if s.animation != &"idle" or not s.is_playing():
				s.play("idle")
		s.modulate = Color.WHITE.lerp(Color(1.5, 1.4, 1.1), float(h.get("flash", 0.0)) * 0.22)

	for i in 16:
		var t: AnimatedSprite2D = _tray_sprites[i]
		if _state != State.PLACING or i >= _tray.size():
			t.visible = false
			continue
		t.visible = true
		var tf: SpriteFrames = _get_frames(_sprite_dir(_tray[i]))
		if t.sprite_frames != tf:
			t.sprite_frames = tf
			t.play("idle")
		elif not t.is_playing():
			t.play("idle")

	_monster_sprite.position.x = _monster_x
	_monster_sprite.speed_scale = _speed if _state == State.BATTLE else 1.0
	if not _monster_sprite.is_playing():
		_monster_sprite.play("walk" if _state == State.BATTLE and _monster_x > MONSTER_STOP_X else "idle")
	_monster_sprite.modulate = Color.WHITE.lerp(Color(1.0, 0.45, 0.45), 1.0 - _monster_hp / MONSTER_HP)


func _redraw() -> void:
	queue_redraw()
	_overlay.queue_redraw()


# ─── 입력 ─────────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1: _speed = 1.0
			KEY_2: _speed = 2.0
			KEY_3: _speed = 4.0
			KEY_R:
				if _state == State.PLACING:
					_random_arrange()
			KEY_D:
				if _state != State.BATTLE:
					_deal_seed += 1
					_deal(_deal_seed)
		_sync_sprites()
		_redraw()
		return

	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var mp: Vector2 = event.position

	if _btn_primary().has_point(mp):
		if _state == State.PLACING and _placed_count() == 16:
			_start_battle()
		elif _state == State.RESULT:
			_state = State.PLACING
			_monster_x = MONSTER_START_X
			_monster_hp = MONSTER_HP
			_wall_hp = WALL_HP
			_monster_sprite.position.x = MONSTER_START_X
			_monster_sprite.play("idle")
		_sync_sprites()
		_redraw()
		return

	# 새 딜은 결과 화면에서도 눌린다 — 딜을 바꾸려고 한 번 더 클릭할 이유가 없다
	if _state != State.BATTLE and _btn_deal().has_point(mp):
		_deal_seed += 1
		_deal(_deal_seed)
		return

	if _state != State.PLACING:
		return

	if _btn_random().has_point(mp):
		_random_arrange()
		return
	if _btn_clear().has_point(mp):
		_clear_board()
		return

	for i in _tray.size():
		if _tray_rect(i).has_point(mp):
			if _picked.get("src", "") == "tray" and int(_picked.get("i", -1)) == i:
				_picked = {}
			else:
				_picked = {"src": "tray", "i": i}
			_redraw()
			return

	for c in 16:
		if not _cell_rect(c).has_point(mp):
			continue
		_click_cell(c)
		return


# 판이 꽉 차면 남는 동사는 "맞바꾸기"뿐이다. 그게 이 프로토의 주된 조작이 된다.
func _click_cell(c: int) -> void:
	if _picked.is_empty():
		if _board[c] != null:
			_picked = {"src": "board", "i": c}
		_redraw()
		return

	if _picked["src"] == "board":
		var src: int = int(_picked["i"])
		_picked = {}
		if src == c:
			_redraw()
			return
		var t = _board[src]
		_board[src] = _board[c]
		_board[c] = t
		_recalc()
		return

	var ti: int = int(_picked["i"])
	if ti >= _tray.size():
		_picked = {}
		_redraw()
		return
	var card: Dictionary = _tray[ti]
	if _board[c] != null:
		_tray[ti] = _board[c]["card"]
	else:
		_tray.remove_at(ti)
	_board[c] = _make_runtime(card)
	_picked = {}
	_recalc()


# ─── 히트박스 ─────────────────────────────────────────────────────────────
func _cell_rect(i: int) -> Rect2:
	return Rect2(GRID_ORIGIN + Vector2(float(i % 4) * CELL, float(i / 4) * CELL),
		Vector2(CELL - 6.0, CELL - 6.0))


func _tray_rect(i: int) -> Rect2:
	return Rect2(TRAY_ORIGIN + Vector2(float(i) * (TRAY_CARD.x + TRAY_GAP), 0.0), TRAY_CARD)


func _btn_primary() -> Rect2:
	return Rect2(1520.0, 60.0, 340.0, 96.0)


func _btn_random() -> Rect2:
	return Rect2(1520.0, 170.0, 340.0, 62.0)


func _btn_clear() -> Rect2:
	return Rect2(1520.0, 244.0, 340.0, 62.0)


func _btn_deal() -> Rect2:
	return Rect2(1520.0, 318.0, 340.0, 62.0)


# ─── 그리기 ───────────────────────────────────────────────────────────────
func _draw() -> void:
	_draw_field()
	_draw_lines_hud()
	_draw_grid()
	_draw_wall()
	_draw_monster_hud()
	_draw_hud()
	if _state == State.PLACING:
		_draw_tray()


func _draw_field() -> void:
	draw_rect(Rect2(0.0, 0.0, 1920.0, 1080.0), Color(0.10, 0.11, 0.14))
	# 몬스터가 걸어오는 레인 — 성벽 오른쪽이 전장이라는 걸 보이게 한다
	draw_rect(Rect2(WALL_RECT.end.x, WALL_RECT.position.y, 1920.0 - WALL_RECT.end.x, WALL_RECT.size.y),
		Color(0.13, 0.12, 0.15))
	draw_line(Vector2(WALL_RECT.end.x, MONSTER_Y + 132.0), Vector2(1920.0, MONSTER_Y + 132.0),
		Color(0.20, 0.19, 0.23), 3.0)
	draw_string(_font_s, Vector2(WALL_RECT.end.x + 260.0, WALL_RECT.position.y - 16.0), "몬스터 진입로",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.42, 0.40, 0.46))


func _draw_suit(c: Vector2, s: float, suit: int) -> void:
	var col: Color = SUIT_COLOR[suit]
	match suit:
		SPADE:
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0.0, -0.80 * s), c + Vector2(0.74 * s, 0.20 * s),
				c + Vector2(-0.74 * s, 0.20 * s)]), col)
			draw_circle(c + Vector2(-0.38 * s, 0.14 * s), 0.38 * s, col)
			draw_circle(c + Vector2(0.38 * s, 0.14 * s), 0.38 * s, col)
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(-0.10 * s, 0.20 * s), c + Vector2(0.10 * s, 0.20 * s),
				c + Vector2(0.28 * s, 0.82 * s), c + Vector2(-0.28 * s, 0.82 * s)]), col)
		HEART:
			draw_circle(c + Vector2(-0.34 * s, -0.24 * s), 0.40 * s, col)
			draw_circle(c + Vector2(0.34 * s, -0.24 * s), 0.40 * s, col)
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(-0.72 * s, -0.14 * s), c + Vector2(0.72 * s, -0.14 * s),
				c + Vector2(0.0, 0.80 * s)]), col)
		DIAMOND:
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0.0, -0.84 * s), c + Vector2(0.58 * s, 0.0),
				c + Vector2(0.0, 0.84 * s), c + Vector2(-0.58 * s, 0.0)]), col)
		CLUB:
			draw_circle(c + Vector2(0.0, -0.36 * s), 0.37 * s, col)
			draw_circle(c + Vector2(-0.42 * s, 0.22 * s), 0.37 * s, col)
			draw_circle(c + Vector2(0.42 * s, 0.22 * s), 0.37 * s, col)
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(-0.10 * s, 0.10 * s), c + Vector2(0.10 * s, 0.10 * s),
				c + Vector2(0.28 * s, 0.84 * s), c + Vector2(-0.28 * s, 0.84 * s)]), col)


# 성벽은 병력 오른쪽, 몬스터의 타격 지점에 선다. 위에서부터 무너진다.
func _draw_wall() -> void:
	var ratio: float = _wall_hp / WALL_HP
	var top: float = WALL_RECT.position.y + WALL_RECT.size.y * (1.0 - ratio)

	# 무너져 나간 부분 — 잔해만 남는다
	draw_rect(Rect2(WALL_RECT.position, Vector2(WALL_RECT.size.x, WALL_RECT.size.y * (1.0 - ratio))),
		Color(0.14, 0.13, 0.15))

	var stone := Color(0.52, 0.54, 0.60) if ratio > 0.35 else Color(0.62, 0.40, 0.38)
	stone = stone.lerp(Color(1.0, 0.55, 0.45), _wall_flash * 0.7)
	var standing := Rect2(Vector2(WALL_RECT.position.x, top),
		Vector2(WALL_RECT.size.x, WALL_RECT.end.y - top))
	draw_rect(standing, stone.darkened(0.35))

	# 돌 쌓기 결 — 픽셀 톤을 맞추려고 격단으로 긋는다
	var y: float = top
	var band: int = 0
	while y < WALL_RECT.end.y:
		var bh: float = minf(30.0, WALL_RECT.end.y - y)
		draw_rect(Rect2(WALL_RECT.position.x + 4.0, y + 3.0, WALL_RECT.size.x - 8.0, bh - 6.0),
			stone.darkened(0.12 if band % 2 == 0 else 0.22))
		if band % 2 == 0:
			draw_line(Vector2(WALL_RECT.position.x + WALL_RECT.size.x * 0.5, y + 3.0),
				Vector2(WALL_RECT.position.x + WALL_RECT.size.x * 0.5, y + bh - 3.0),
				stone.darkened(0.45), 2.0)
		y += 30.0
		band += 1
	draw_rect(standing, Color(0.80, 0.84, 0.92), false, 3.0)

	# 성벽이 곧 타격 지점이다 — 한 줄로 붙여 쓴다
	draw_string(_font_b, Vector2(WALL_RECT.position.x - 26.0, WALL_RECT.position.y - 16.0),
		"성벽 %d%%  ← 타격 지점" % int(round(ratio * 100.0)),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22,
		Color(0.85, 0.90, 1.0) if ratio > 0.35 else Color(0.95, 0.55, 0.50))


func _line_color(bonus: float) -> Color:
	if bonus <= 0.001:
		return Color(0.42, 0.44, 0.50)
	if bonus < 0.5:
		return Color(0.62, 0.72, 0.60)
	if bonus < 1.0:
		return Color(0.70, 0.90, 0.60)
	return Color(1.0, 0.84, 0.42)


func _draw_lines_hud() -> void:
	for col in 4:
		var d: Dictionary = _lines[4 + col]
		var x: float = GRID_ORIGIN.x + float(col) * CELL
		draw_string(_font_s, Vector2(x + 4.0, GRID_ORIGIN.y - 38.0), str(d["name"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, _line_color(float(d["bonus"])))
		draw_string(_font_s, Vector2(x + 4.0, GRID_ORIGIN.y - 14.0), "+%.2f" % float(d["bonus"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, _line_color(float(d["bonus"])))
	for row in 4:
		var d2: Dictionary = _lines[row]
		var cy: float = GRID_ORIGIN.y + float(row) * CELL + CELL * 0.5
		draw_string(_font, Vector2(ROW_LABEL_X, cy - 4.0), str(d2["name"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22, _line_color(float(d2["bonus"])))
		draw_string(_font_s, Vector2(ROW_LABEL_X, cy + 24.0), "+%.2f" % float(d2["bonus"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, _line_color(float(d2["bonus"])))


func _draw_grid() -> void:
	var picked_board: int = -1
	if _picked.get("src", "") == "board":
		picked_board = int(_picked["i"])

	for i in 16:
		var r: Rect2 = _cell_rect(i)
		var h = _board[i]
		if h == null:
			draw_rect(r, Color(0.15, 0.16, 0.20))
			draw_rect(r, Color(0.30, 0.32, 0.38), false, 2.0)
			continue

		var card: Dictionary = h["card"]
		var scol: Color = SUIT_COLOR[int(card["suit"])]
		var flash: float = float(h["flash"])
		var sel: bool = (i == picked_board)
		draw_rect(r, scol.darkened(0.78).lerp(scol.darkened(0.55), flash))
		draw_rect(r, Color.WHITE if sel else scol.lerp(Color.WHITE, flash),
			false, 4.0 if sel else 2.0 + flash * 3.0)

		# 위쪽 띠: 무늬 + 랭크 + 배수. 가운데는 스프라이트 자리다.
		draw_rect(Rect2(r.position, Vector2(r.size.x, 32.0)), scol.darkened(0.62))
		_draw_suit(r.position + Vector2(18.0, 17.0), 13.0, int(card["suit"]))
		draw_string(_font_b, r.position + Vector2(32.0, 25.0), _rank_text(int(card["rank"])),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.96, 0.96, 0.99))
		draw_string(_font_b, r.position + Vector2(0.0, 25.0), "×%.2f" % float(h["mult"]),
			HORIZONTAL_ALIGNMENT_RIGHT, int(r.size.x) - 8, 22, _line_color(float(h["mult"]) - 1.0))

		# 아래쪽 띠: 배치 중엔 예상 DPS, 전투 중엔 누적딜
		if _state == State.PLACING:
			draw_string(_font_s, r.position + Vector2(8.0, r.size.y - 10.0),
				"DPS %.1f" % (_hit_damage(h) * float(h["aspd"])),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.74, 0.78, 0.84))
		else:
			draw_string(_font, r.position + Vector2(8.0, r.size.y - 14.0), "%d" % int(h["dmg"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1.0, 0.92, 0.60))
			var share: float = float(h["dmg"]) / maxf(1.0, MONSTER_HP - _monster_hp)
			draw_rect(Rect2(r.position + Vector2(8.0, r.size.y - 8.0),
				Vector2((r.size.x - 16.0) * share, 5.0)), Color(1.0, 0.85, 0.45))


func _draw_monster_hud() -> void:
	if not _monster_sprite.visible:
		return
	var ratio: float = _monster_hp / MONSTER_HP
	# 몬스터가 화면 오른쪽 끝에 서 있을 땐 바가 잘리므로 안쪽으로 물린다
	var bar := Rect2(clampf(_monster_x - 120.0, WALL_RECT.end.x + 20.0, 1620.0),
		MONSTER_Y - 110.0, 240.0, 16.0)
	draw_rect(bar, Color(0.18, 0.10, 0.12))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)), Color(0.82, 0.28, 0.32))
	draw_rect(bar, Color(0.55, 0.35, 0.38), false, 2.0)
	draw_string(_font, Vector2(bar.position.x, bar.position.y - 10.0),
		"몬스터 %d / %d" % [int(_monster_hp), int(MONSTER_HP)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1.0, 0.78, 0.78))

	var burn: float = 0.0
	for h in _board:
		if h != null:
			burn += float(h["burn"])
	var y: float = bar.position.y + 40.0
	if burn > 0.0:
		draw_string(_font_s, Vector2(bar.position.x, y),
			"화상 %d스택 (%.0f/s)" % [int(burn), burn * BURN_TICK],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, SUIT_COLOR[HEART])
		y += 26.0
	if _state == State.BATTLE and _monster_x > MONSTER_STOP_X:
		draw_string(_font_s, Vector2(bar.position.x, y),
			"성벽까지 %.1fs" % ((_monster_x - MONSTER_STOP_X) / MONSTER_SPEED),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.95, 0.80, 0.45))


func _board_dps() -> float:
	var t: float = 0.0
	for h in _board:
		if h != null:
			t += _hit_damage(h) * float(h["aspd"])
	return t


func _draw_hud() -> void:
	var total: float = MONSTER_HP - _monster_hp
	draw_string(_font_b, Vector2(60.0, 96.0),
		"딜 #%d      배치 %d/16      예상 DPS %.0f" % [_deal_seed, _placed_count(), _board_dps()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.80, 0.84, 0.92))
	if _state == State.PLACING:
		draw_string(_font_s, Vector2(60.0, 132.0),
			"행 4 + 열 4 = 8줄. 카드 배수 = 1 + 행 보너스 + 열 보너스.   A는 랭크·무늬 와일드.",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.52, 0.56, 0.64))
		draw_string(_font_s, Vector2(60.0, 162.0),
			"Q: 같은 행·열 공격력 +3   K: 전군 공속 +0.10   ♣: 그 줄 보너스 +0.15   ♥: 타격당 화상 +1",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.52, 0.56, 0.64))
		draw_string(_font_s, Vector2(60.0, 192.0),
			"무늬 = 진영, 랭크 = 역할.   판의 카드끼리 클릭 두 번 = 맞바꾸기.",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.45, 0.49, 0.57))
	else:
		draw_string(_font_s, Vector2(60.0, 132.0),
			"경과 %.1fs      누적딜 %d      DPS %.0f      화상 기여 %d      속도 %.0fx [1][2][3]" %
			[_elapsed, int(total), total / maxf(0.001, _elapsed), int(_burn_total), _speed],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.62, 0.66, 0.74))

	var label: String = ""
	if _state == State.PLACING:
		label = "전투 시작" if _placed_count() == 16 else "16장을 모두 놓으세요"
	elif _state == State.BATTLE:
		label = "전투 중"
	else:
		label = "다시 배치"
	var br: Rect2 = _btn_primary()
	var ready: bool = (_state == State.RESULT) or (_state == State.PLACING and _placed_count() == 16)
	draw_rect(br, Color(0.22, 0.34, 0.48) if ready else Color(0.18, 0.19, 0.23))
	draw_rect(br, Color(0.55, 0.70, 0.90), false, 2.0)
	draw_string(_font_b, br.position + Vector2(22.0, 58.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.92, 0.95, 1.0))

	if _state == State.PLACING:
		_draw_button(_btn_random(), "무작위 배치  [R]", Color(0.20, 0.28, 0.24), Color(0.50, 0.72, 0.55))
		_draw_button(_btn_clear(), "판 비우기", Color(0.26, 0.20, 0.22), Color(0.60, 0.45, 0.48))
	if _state != State.BATTLE:
		_draw_button(_btn_deal(), "새 딜  [D]", Color(0.20, 0.22, 0.30), Color(0.50, 0.55, 0.75))


func _draw_button(r: Rect2, label: String, fill: Color, edge: Color) -> void:
	draw_rect(r, fill)
	draw_rect(r, edge, false, 2.0)
	draw_string(_font, r.position + Vector2(20.0, 40.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, edge.lightened(0.45))


func _draw_tray() -> void:
	if _tray.is_empty():
		draw_string(_font, TRAY_ORIGIN + Vector2(0.0, 60.0),
			"손패 비었음 — 16장 모두 판 위에 있다",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.45, 0.49, 0.57))
		return
	for i in _tray.size():
		var card: Dictionary = _tray[i]
		var r: Rect2 = _tray_rect(i)
		var scol: Color = SUIT_COLOR[int(card["suit"])]
		var on: bool = _picked.get("src", "") == "tray" and int(_picked.get("i", -1)) == i
		draw_rect(r, scol.darkened(0.78) if not on else scol.darkened(0.50))
		draw_rect(r, Color.WHITE if on else scol.darkened(0.25), false, 4.0 if on else 2.0)
		draw_rect(Rect2(r.position, Vector2(r.size.x, 30.0)), scol.darkened(0.62))
		_draw_suit(r.position + Vector2(16.0, 16.0), 12.0, int(card["suit"]))
		draw_string(_font_b, r.position + Vector2(30.0, 23.0), _rank_text(int(card["rank"])),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.96, 0.96, 0.99))
		draw_string(_font_s, r.position + Vector2(6.0, r.size.y - 30.0), str(SUIT_NAME[int(card["suit"])]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, scol)
		draw_string(_font_s, r.position + Vector2(6.0, r.size.y - 8.0), "DPS %.1f" % _card_dps(card),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.78, 0.80, 0.86))


# 결과 패널만 z_index를 올려 스프라이트 위에 그린다.
func _draw_overlay() -> void:
	if _state != State.RESULT:
		return
	var panel := Rect2(470.0, 170.0, 980.0, 740.0)
	_overlay.draw_rect(panel, Color(0.12, 0.13, 0.17, 0.97))
	_overlay.draw_rect(panel, Color(0.55, 0.60, 0.72), false, 3.0)
	_overlay.draw_string(_font_b, panel.position + Vector2(34.0, 64.0),
		"몬스터 처치" if _won else "성벽 붕괴", HORIZONTAL_ALIGNMENT_LEFT, -1, 44,
		Color(0.60, 0.90, 0.65) if _won else Color(0.92, 0.45, 0.42))

	var score: String
	if _won:
		score = "성벽 잔여 %d%%     소요 %.1fs" % [int(round(_wall_hp / WALL_HP * 100.0)), _elapsed]
	else:
		score = "몬스터 잔여 %d%%     버틴 시간 %.1fs" % [int(round(_monster_hp / MONSTER_HP * 100.0)), _elapsed]
	_overlay.draw_string(_font, panel.position + Vector2(34.0, 110.0),
		"딜 #%d      %s" % [_deal_seed, score],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.85, 0.88, 0.94))

	_overlay.draw_string(_font, panel.position + Vector2(34.0, 158.0), "줄 구성",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.60, 0.64, 0.72))
	for line in 8:
		var d: Dictionary = _lines[line]
		var lx: float = 34.0 + float(line / 4) * 260.0
		var ly: float = 192.0 + float(line % 4) * 30.0
		_overlay.draw_string(_font_s, panel.position + Vector2(lx, ly),
			"%s%d  %s  +%.2f" % ["행" if line < 4 else "열", line % 4 + 1, str(d["name"]), float(d["bonus"])],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, _line_color(float(d["bonus"])))

	_overlay.draw_string(_font, panel.position + Vector2(34.0, 348.0),
		"기여도      (화상 총합 %d / 전체의 %d%%)" %
		[int(_burn_total), int(round(_burn_total / maxf(1.0, MONSTER_HP - _monster_hp) * 100.0))],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.60, 0.64, 0.72))

	var ranked: Array = []
	for h in _board:
		if h != null:
			ranked.append(h)
	ranked.sort_custom(func(a, b): return float(a["dmg"]) > float(b["dmg"]))
	var total: float = maxf(1.0, MONSTER_HP - _monster_hp)
	for k in ranked.size():
		var h2: Dictionary = ranked[k]
		var x: float = 34.0 + float(k / 8) * 470.0
		var y: float = 384.0 + float(k % 8) * 40.0
		var pct: float = float(h2["dmg"]) / total
		_draw_suit_on(_overlay, panel.position + Vector2(x + 12.0, y - 8.0), 13.0, int(h2["card"]["suit"]))
		_overlay.draw_string(_font_b, panel.position + Vector2(x + 30.0, y),
			_rank_text(int(h2["card"]["rank"])), HORIZONTAL_ALIGNMENT_LEFT, -1, 22,
			SUIT_COLOR[int(h2["card"]["suit"])])
		_overlay.draw_string(_font_s, panel.position + Vector2(x + 60.0, y),
			"×%.2f  %d (%d%%)" % [float(h2["mult"]), int(h2["dmg"]), int(round(pct * 100.0))],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.80, 0.83, 0.90))
		_overlay.draw_rect(Rect2(panel.position + Vector2(x + 250.0, y - 15.0),
			Vector2(190.0 * pct * 4.0, 13.0)), SUIT_COLOR[int(h2["card"]["suit"])].darkened(0.25))


# 오버레이 노드에 무늬를 그리려면 그 노드의 draw_* 를 써야 해서 한 벌 더 둔다.
func _draw_suit_on(node: CanvasItem, c: Vector2, s: float, suit: int) -> void:
	var col: Color = SUIT_COLOR[suit]
	match suit:
		SPADE:
			node.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0.0, -0.80 * s), c + Vector2(0.74 * s, 0.20 * s),
				c + Vector2(-0.74 * s, 0.20 * s)]), col)
			node.draw_circle(c + Vector2(-0.38 * s, 0.14 * s), 0.38 * s, col)
			node.draw_circle(c + Vector2(0.38 * s, 0.14 * s), 0.38 * s, col)
		HEART:
			node.draw_circle(c + Vector2(-0.34 * s, -0.24 * s), 0.40 * s, col)
			node.draw_circle(c + Vector2(0.34 * s, -0.24 * s), 0.40 * s, col)
			node.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-0.72 * s, -0.14 * s), c + Vector2(0.72 * s, -0.14 * s),
				c + Vector2(0.0, 0.80 * s)]), col)
		DIAMOND:
			node.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0.0, -0.84 * s), c + Vector2(0.58 * s, 0.0),
				c + Vector2(0.0, 0.84 * s), c + Vector2(-0.58 * s, 0.0)]), col)
		CLUB:
			node.draw_circle(c + Vector2(0.0, -0.36 * s), 0.37 * s, col)
			node.draw_circle(c + Vector2(-0.42 * s, 0.22 * s), 0.37 * s, col)
			node.draw_circle(c + Vector2(0.42 * s, 0.22 * s), 0.37 * s, col)
