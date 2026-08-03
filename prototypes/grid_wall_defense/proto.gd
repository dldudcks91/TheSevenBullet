# PROTOTYPE - NOT FOR PRODUCTION
# Question: 9명을 3×3 어디에 놓느냐가 결과를 유의미하게 바꾸는가, 그리고 그게 화면에서 읽히는가?
# Date: 2026-08-03
#
# 검증 대상만 남긴다. 상점·런 구조·골드·전술카드·아이템·상태이상·방어특성은 전부 없음.
# 몬스터는 매번 동일 — 배치만 바꿔가며 "성벽 잔여 %"를 비교하는 게 이 프로토의 측정 방식이다.

extends Node2D

# ─── 레이아웃 (하드코딩, 1920×1080) ────────────────────────────────────────
const WALL_RECT := Rect2(60.0, 240.0, 80.0, 600.0)
const GRID_ORIGIN := Vector2(230.0, 300.0)
const CELL_SIZE := 150.0
const STOP_LINE_X := 790.0
const MONSTER_START_X := 1790.0
const MONSTER_Y := 540.0
const MONSTER_RADIUS := 62.0
const TRAY_ORIGIN := Vector2(230.0, 900.0)
const TRAY_CARD := Vector2(200.0, 130.0)
const TRAY_GAP := 20.0

# ─── 밸런스 (전부 임시값) ──────────────────────────────────────────────────
const MONSTER_HP := 2800.0
const MONSTER_SPEED := 100.0          # px/s — 1000px 이동 = 접근에 10초
const WALL_HP := 400.0
const WALL_HIT_DAMAGE := 40.0
const WALL_HIT_INTERVAL := 1.5

const CLERIC_FLAT_ATK := 4.0          # 인접에 공격력 +고정 → 공속 빠른 쪽이 이득이 큼
const BARD_FLAT_ASPD := 0.35          # 인접에 공속 +고정 → 한방 큰 쪽이 이득이 큼
const RAMP_GAIN := 1.0                # 광전사: 때릴 때마다 공격력 누적

# 성격이 "숫자"가 아니라 "구조"로 달라야 배치가 의미를 갖는다.
const HEROES := [
	{"id": "warrior",   "name": "전사",     "atk": 12.0, "aspd": 1.00, "kind": "basic",
	 "desc": "기준선", "color": Color(0.85, 0.35, 0.30)},
	{"id": "archer",    "name": "궁수",     "atk": 5.0,  "aspd": 2.50, "kind": "rapid",
	 "desc": "속사 — 딜 작고 잦음", "color": Color(0.40, 0.75, 0.42)},
	{"id": "mage",      "name": "마법사",   "atk": 30.0, "aspd": 0.50, "kind": "burst",
	 "desc": "버스트 — 느리고 큼", "color": Color(0.42, 0.48, 0.92)},
	{"id": "berserker", "name": "광전사",   "atk": 8.0,  "aspd": 1.20, "kind": "ramp",
	 "desc": "램프 — 칠수록 강해짐", "color": Color(0.92, 0.55, 0.20)},
	{"id": "cleric",    "name": "성직자",   "atk": 2.0,  "aspd": 1.00, "kind": "buff_flat",
	 "desc": "인접 공격력 +6", "color": Color(0.95, 0.85, 0.45)},
	{"id": "bard",      "name": "음유시인", "atk": 2.0,  "aspd": 1.00, "kind": "buff_aspd",
	 "desc": "인접 공속 +0.8", "color": Color(0.78, 0.45, 0.88)},
]

enum State { PLACING, BATTLE, RESULT }

var _state: int = State.PLACING
var _cells: Array = []                # 9칸 — null 또는 런타임 영웅 Dictionary
var _picked: Dictionary = {}          # 트레이에서 집어든 영웅 정의 (비어있으면 없음)
var _speed: float = 1.0

var _monster_x: float = MONSTER_START_X
var _monster_hp: float = MONSTER_HP
var _wall_hp: float = WALL_HP
var _wall_timer: float = 0.0
var _elapsed: float = 0.0
var _won: bool = false

var _font: Font = ThemeDB.fallback_font


func _ready() -> void:
	_reset_board()


# ─── 상태 전이 ────────────────────────────────────────────────────────────
func _reset_board() -> void:
	_cells.clear()
	for _i in 9:
		_cells.append(null)
	_picked = {}
	_state = State.PLACING
	queue_redraw()


func _start_battle() -> void:
	_monster_x = MONSTER_START_X
	_monster_hp = MONSTER_HP
	_wall_hp = WALL_HP
	_wall_timer = 0.0
	_elapsed = 0.0
	_won = false
	_apply_adjacency_buffs()
	for h in _cells:
		if h != null:
			h["cd"] = 1.0 / h["aspd"]
			h["dmg"] = 0.0
			h["hits"] = 0
			h["ramp"] = 0.0
			h["flash"] = 0.0
	_state = State.BATTLE


# 버프는 전투 시작 시 1회 계산 — 전투 중 배치가 바뀌지 않으므로 정적이다.
func _apply_adjacency_buffs() -> void:
	for i in 9:
		var h = _cells[i]
		if h == null:
			continue
		h["atk"] = float(h["def"]["atk"])
		h["aspd"] = float(h["def"]["aspd"])
	for i in 9:
		var h = _cells[i]
		if h == null:
			continue
		for j in _neighbors(i):
			var n = _cells[j]
			if n == null:
				continue
			match n["def"]["kind"]:
				"buff_flat":
					h["atk"] += CLERIC_FLAT_ATK
				"buff_aspd":
					h["aspd"] += BARD_FLAT_ASPD


# 상하좌우 4방향. 중앙칸 4개 / 변 3개 / 모서리 2개 — 칸 가치 기울기가 공짜로 생긴다.
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


# ─── 전투 루프 ────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if _state != State.BATTLE:
		return
	var dt: float = delta * _speed
	_elapsed += dt

	if _monster_x > STOP_LINE_X:
		_monster_x = maxf(STOP_LINE_X, _monster_x - MONSTER_SPEED * dt)
	else:
		_wall_timer -= dt
		if _wall_timer <= 0.0:
			_wall_timer += WALL_HIT_INTERVAL
			_wall_hp -= WALL_HIT_DAMAGE

	for h in _cells:
		if h == null:
			continue
		h["flash"] = maxf(0.0, float(h["flash"]) - dt * 6.0)
		h["cd"] = float(h["cd"]) - dt
		while float(h["cd"]) <= 0.0 and _monster_hp > 0.0:
			h["cd"] = float(h["cd"]) + 1.0 / float(h["aspd"])
			var dmg: float = float(h["atk"]) + float(h["ramp"])
			_monster_hp -= dmg
			h["dmg"] = float(h["dmg"]) + dmg
			h["hits"] = int(h["hits"]) + 1
			h["flash"] = 1.0
			if h["def"]["kind"] == "ramp":
				h["ramp"] = float(h["ramp"]) + RAMP_GAIN

	if _monster_hp <= 0.0:
		_monster_hp = 0.0
		_won = true
		_state = State.RESULT
	elif _wall_hp <= 0.0:
		_wall_hp = 0.0
		_won = false
		_state = State.RESULT

	queue_redraw()


# ─── 입력 ─────────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1: _speed = 1.0
			KEY_2: _speed = 2.0
			KEY_3: _speed = 4.0
		queue_redraw()
		return

	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var mp: Vector2 = event.position

	if _btn_rect_primary().has_point(mp):
		if _state == State.PLACING and _placed_count() > 0:
			_start_battle()
		elif _state == State.RESULT:
			_state = State.PLACING
		queue_redraw()
		return

	if _state == State.PLACING and _btn_rect_clear().has_point(mp):
		_reset_board()
		return

	if _state != State.PLACING:
		return

	# 트레이에서 집기
	for i in HEROES.size():
		if _tray_rect(i).has_point(mp):
			_picked = HEROES[i]
			queue_redraw()
			return

	# 칸에 놓기 / 빼기
	for i in 9:
		if not _cell_rect(i).has_point(mp):
			continue
		if _cells[i] != null:
			_cells[i] = null
		elif not _picked.is_empty():
			_cells[i] = {"def": _picked, "atk": 0.0, "aspd": 0.0,
				"cd": 0.0, "dmg": 0.0, "hits": 0, "ramp": 0.0, "flash": 0.0}
		queue_redraw()
		return


func _placed_count() -> int:
	var n: int = 0
	for h in _cells:
		if h != null:
			n += 1
	return n


# ─── 히트박스 ─────────────────────────────────────────────────────────────
func _cell_rect(idx: int) -> Rect2:
	return Rect2(GRID_ORIGIN + Vector2(float(idx % 3) * CELL_SIZE, float(idx / 3) * CELL_SIZE),
		Vector2(CELL_SIZE - 6.0, CELL_SIZE - 6.0))


func _tray_rect(idx: int) -> Rect2:
	return Rect2(TRAY_ORIGIN + Vector2(float(idx) * (TRAY_CARD.x + TRAY_GAP), 0.0), TRAY_CARD)


func _btn_rect_primary() -> Rect2:
	return Rect2(1600.0, 900.0, 260.0, 130.0)


func _btn_rect_clear() -> Rect2:
	return Rect2(1600.0, 800.0, 260.0, 70.0)


# ─── 그리기 ───────────────────────────────────────────────────────────────
func _draw() -> void:
	draw_rect(Rect2(0.0, 0.0, 1920.0, 1080.0), Color(0.10, 0.11, 0.14))
	_draw_wall()
	_draw_stop_line()
	_draw_grid()
	_draw_monster()
	_draw_hud()
	if _state == State.PLACING:
		_draw_tray()
	if _state == State.RESULT:
		_draw_result()


func _draw_wall() -> void:
	var ratio: float = _wall_hp / WALL_HP
	draw_rect(WALL_RECT, Color(0.22, 0.22, 0.26))
	var filled := Rect2(WALL_RECT.position + Vector2(0.0, WALL_RECT.size.y * (1.0 - ratio)),
		Vector2(WALL_RECT.size.x, WALL_RECT.size.y * ratio))
	draw_rect(filled, Color(0.55, 0.72, 0.90) if ratio > 0.35 else Color(0.90, 0.40, 0.35))
	draw_rect(WALL_RECT, Color(0.75, 0.80, 0.90), false, 3.0)
	draw_string(_font, Vector2(46.0, 210.0), "성벽  %d%%" % int(round(ratio * 100.0)),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(0.85, 0.90, 1.0))


func _draw_stop_line() -> void:
	draw_line(Vector2(STOP_LINE_X, 200.0), Vector2(STOP_LINE_X, 880.0), Color(0.45, 0.30, 0.30), 3.0)
	draw_string(_font, Vector2(STOP_LINE_X - 40.0, 190.0), "타격 지점",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.65, 0.45, 0.45))


func _draw_grid() -> void:
	for i in 9:
		var r: Rect2 = _cell_rect(i)
		var h = _cells[i]
		if h == null:
			draw_rect(r, Color(0.15, 0.16, 0.20))
			draw_rect(r, Color(0.30, 0.32, 0.38), false, 2.0)
			draw_string(_font, r.position + Vector2(10.0, 26.0), "%d" % _neighbors(i).size(),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.35, 0.37, 0.42))
			continue
		var col: Color = h["def"]["color"]
		var flash: float = float(h["flash"])
		draw_rect(r, col.darkened(0.55).lerp(col, flash * 0.5))
		draw_rect(r, col.lerp(Color.WHITE, flash), false, 2.0 + flash * 3.0)
		draw_string(_font, r.position + Vector2(10.0, 32.0), str(h["def"]["name"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.95, 0.95, 0.98))
		if _state == State.PLACING:
			draw_string(_font, r.position + Vector2(10.0, 62.0),
				"공%.0f 속%.2f" % [float(h["def"]["atk"]), float(h["def"]["aspd"])],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(0.70, 0.72, 0.78))
		else:
			draw_string(_font, r.position + Vector2(10.0, 62.0),
				"공%.0f 속%.2f" % [float(h["atk"]), float(h["aspd"])],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(0.75, 0.85, 0.75))
			draw_string(_font, r.position + Vector2(10.0, 92.0), "누적 %d" % int(h["dmg"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1.0, 0.92, 0.60))
			var share: float = float(h["dmg"]) / maxf(1.0, MONSTER_HP - _monster_hp)
			draw_rect(Rect2(r.position + Vector2(10.0, 108.0), Vector2(124.0 * share, 8.0)),
				Color(1.0, 0.85, 0.45))


func _draw_monster() -> void:
	var ratio: float = _monster_hp / MONSTER_HP
	var pos := Vector2(_monster_x, MONSTER_Y)
	draw_circle(pos, MONSTER_RADIUS, Color(0.40, 0.18, 0.22))
	draw_circle(pos, MONSTER_RADIUS * ratio, Color(0.80, 0.25, 0.30))
	draw_string(_font, pos + Vector2(-MONSTER_RADIUS, -MONSTER_RADIUS - 46.0),
		"몬스터  %d / %d" % [int(_monster_hp), int(MONSTER_HP)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1.0, 0.78, 0.78))
	if _state == State.BATTLE and _monster_x > STOP_LINE_X:
		var eta: float = (_monster_x - STOP_LINE_X) / MONSTER_SPEED
		draw_string(_font, pos + Vector2(-MONSTER_RADIUS, -MONSTER_RADIUS - 14.0),
			"도달까지 %.1fs" % eta, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.95, 0.80, 0.45))


func _draw_hud() -> void:
	var total: float = MONSTER_HP - _monster_hp
	var dps: float = total / maxf(0.001, _elapsed)
	draw_string(_font, Vector2(230.0, 120.0),
		"경과 %.1fs      누적딜 %d      DPS %.0f      배치 %d/9" %
		[_elapsed, int(total), dps, _placed_count()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(0.80, 0.84, 0.92))
	draw_string(_font, Vector2(230.0, 160.0),
		"칸의 숫자 = 인접 칸 수 (중앙 4 / 변 3 / 모서리 2)      속도 %.0fx  [1][2][3]" % _speed,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.50, 0.54, 0.62))

	var label: String = ""
	if _state == State.PLACING:
		label = "전투 시작" if _placed_count() > 0 else "영웅을 놓으세요"
	elif _state == State.BATTLE:
		label = "전투 중"
	else:
		label = "다시 배치"
	var br: Rect2 = _btn_rect_primary()
	draw_rect(br, Color(0.22, 0.34, 0.48) if _state != State.BATTLE else Color(0.18, 0.19, 0.23))
	draw_rect(br, Color(0.55, 0.70, 0.90), false, 2.0)
	draw_string(_font, br.position + Vector2(24.0, 76.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(0.92, 0.95, 1.0))

	if _state == State.PLACING:
		var cr: Rect2 = _btn_rect_clear()
		draw_rect(cr, Color(0.26, 0.20, 0.22))
		draw_rect(cr, Color(0.60, 0.45, 0.48), false, 2.0)
		draw_string(_font, cr.position + Vector2(24.0, 46.0), "판 비우기",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.90, 0.80, 0.82))


func _draw_tray() -> void:
	for i in HEROES.size():
		var d: Dictionary = HEROES[i]
		var r: Rect2 = _tray_rect(i)
		var col: Color = d["color"]
		var on: bool = not _picked.is_empty() and _picked["id"] == d["id"]
		draw_rect(r, col.darkened(0.60) if not on else col.darkened(0.30))
		draw_rect(r, col if on else col.darkened(0.30), false, 3.0 if on else 2.0)
		draw_string(_font, r.position + Vector2(12.0, 34.0), str(d["name"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.95, 0.95, 0.98))
		draw_string(_font, r.position + Vector2(12.0, 64.0),
			"공%.0f 속%.2f" % [float(d["atk"]), float(d["aspd"])],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.75, 0.78, 0.84))
		draw_string(_font, r.position + Vector2(12.0, 92.0), str(d["desc"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.65, 0.68, 0.75))
		draw_string(_font, r.position + Vector2(12.0, 116.0), "DPS %.1f" % (float(d["atk"]) * float(d["aspd"])),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.85, 0.80, 0.55))


func _draw_result() -> void:
	var panel := Rect2(560.0, 300.0, 800.0, 480.0)
	draw_rect(panel, Color(0.12, 0.13, 0.17, 0.96))
	draw_rect(panel, Color(0.55, 0.60, 0.72), false, 3.0)
	var head: String = "몬스터 처치" if _won else "성벽 붕괴"
	draw_string(_font, panel.position + Vector2(36.0, 66.0), head,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 44, Color(0.60, 0.90, 0.65) if _won else Color(0.92, 0.45, 0.42))
	var score: String = ""
	if _won:
		score = "성벽 잔여 %d%%     소요 %.1fs" % [int(round(_wall_hp / WALL_HP * 100.0)), _elapsed]
	else:
		score = "몬스터 잔여 %d%%     버틴 시간 %.1fs" % [int(round(_monster_hp / MONSTER_HP * 100.0)), _elapsed]
	draw_string(_font, panel.position + Vector2(36.0, 112.0), score,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(0.85, 0.88, 0.94))

	var ranked: Array = []
	for i in 9:
		if _cells[i] != null:
			ranked.append(_cells[i])
	ranked.sort_custom(func(a, b): return float(a["dmg"]) > float(b["dmg"]))
	var y: float = 170.0
	var total: float = maxf(1.0, MONSTER_HP - _monster_hp)
	for h in ranked:
		var pct: float = float(h["dmg"]) / total
		draw_string(_font, panel.position + Vector2(36.0, y), str(h["def"]["name"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 24, h["def"]["color"])
		draw_string(_font, panel.position + Vector2(180.0, y),
			"%d  (%d%%)  %d타" % [int(h["dmg"]), int(round(pct * 100.0)), int(h["hits"])],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.80, 0.83, 0.90))
		draw_rect(Rect2(panel.position + Vector2(430.0, y - 16.0), Vector2(320.0 * pct, 14.0)),
			Color(h["def"]["color"]).darkened(0.2))
		y += 34.0
