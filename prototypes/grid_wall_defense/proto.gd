# PROTOTYPE - NOT FOR PRODUCTION
# Question: 9명을 3×3 어디에 놓느냐가 결과를 유의미하게 바꾸는가, 그리고 그게 화면에서 읽히는가?
# Date: 2026-08-03
#
# 검증 대상만 남긴다. 상점·런 구조·골드·전술카드·아이템·상태이상·방어특성은 전부 없음.
# 몬스터는 매번 동일 — 배치만 바꿔가며 "성벽 잔여 %"를 비교하는 게 이 프로토의 측정 방식이다.
#
# 에셋: TheSevenAutoBattle에서 쓰던 minifolks 스프라이트 + Galmuri 픽셀 폰트를 이 폴더로 복사해 왔다.
# 스프라이트 로딩 방식도 그쪽 sprite_frame_loader.gd 를 베껴온 것이다(프로토는 import 금지, 복사만 허용).

extends Node2D

# ─── 레이아웃 (하드코딩, 1920×1080) ────────────────────────────────────────
# 병력(3×3) → 성벽 → 몬스터 순으로 왼쪽에서 오른쪽. 몬스터는 성벽 앞에서 멈춰 성벽을 때린다.
const GRID_ORIGIN := Vector2(170.0, 250.0)
const CELL_SIZE := 165.0
const WALL_RECT := Rect2(700.0, 230.0, 76.0, 540.0)
const MONSTER_STOP_X := 900.0        # 몬스터 중심이 멈추는 곳 — 성벽 바로 오른쪽
const MONSTER_START_X := 1800.0      # 900px 전진 = 접근에 9초
const MONSTER_Y := 500.0             # 성벽 세로 중앙
const TRAY_ORIGIN := Vector2(170.0, 880.0)
const TRAY_CARD := Vector2(210.0, 140.0)
const TRAY_GAP := 18.0

# ─── 밸런스 (전부 임시값) ──────────────────────────────────────────────────
const MONSTER_HP := 2800.0
const MONSTER_SPEED := 100.0          # px/s
const WALL_HP := 400.0
const WALL_HIT_DAMAGE := 40.0
const WALL_HIT_INTERVAL := 1.5

const CLERIC_FLAT_ATK := 4.0          # 인접에 공격력 +고정 → 공속 빠른 쪽이 이득이 큼
const BARD_FLAT_ASPD := 0.35          # 인접에 공속 +고정 → 한방 큰 쪽이 이득이 큼
const RAMP_GAIN := 1.0                # 광전사: 때릴 때마다 공격력 누적

# ─── 스프라이트 ───────────────────────────────────────────────────────────
const SPRITE_ROOT := "res://assets/units"
const ANIMS := {
	"idle":   {"folder": "Idle",   "fps": 8.0,  "loop": true},
	"walk":   {"folder": "Walk",   "fps": 10.0, "loop": true},
	# attack은 루프다 — 전투 중 영웅은 idle로 돌아가지 않고 자기 공격속도로 계속 돈다.
	# (몬스터만 예외로 _ready에서 loop를 꺼서 한 번씩만 휘두르게 한다)
	"attack": {"folder": "Attack", "fps": 12.0, "loop": true},
	"hit":    {"folder": "Hit",    "fps": 12.0, "loop": false},
	"death":  {"folder": "Death",  "fps": 8.0,  "loop": false},
}
const HERO_SPRITE_SCALE := 3.4
const MONSTER_SPRITE_SCALE := 4.5

# 성격이 "숫자"가 아니라 "구조"로 달라야 배치가 의미를 갖는다.
const HEROES := [
	{"id": "warrior",   "name": "전사",     "atk": 12.0, "aspd": 1.00, "kind": "basic",
	 "desc": "기준선", "color": Color(0.85, 0.35, 0.30),
	 "sprite": "minifolks/MinifolksHumans/MiniSwordMan/no_outline"},
	{"id": "archer",    "name": "궁수",     "atk": 5.0,  "aspd": 2.50, "kind": "rapid",
	 "desc": "속사 — 딜 작고 잦음", "color": Color(0.40, 0.75, 0.42),
	 "sprite": "minifolks/MinifolksHumans/MiniArcherMan/no_outline"},
	{"id": "mage",      "name": "마법사",   "atk": 30.0, "aspd": 0.50, "kind": "burst",
	 "desc": "버스트 — 느리고 큼", "color": Color(0.42, 0.48, 0.92),
	 "sprite": "minifolks/MinifolksHumans/MiniMage/no_outline"},
	{"id": "berserker", "name": "광전사",   "atk": 8.0,  "aspd": 1.20, "kind": "ramp",
	 "desc": "램프 — 칠수록 강해짐", "color": Color(0.92, 0.55, 0.20),
	 "sprite": "minifolks/MinifolksVikings/MiniVikingBerserker/no_outline"},
	{"id": "cleric",    "name": "성직자",   "atk": 2.0,  "aspd": 1.00, "kind": "buff_flat",
	 "desc": "인접 공격력 +4", "color": Color(0.95, 0.85, 0.45),
	 "sprite": "minifolks/MinifolksHumans/MiniArchMage/no_outline"},
	{"id": "bard",      "name": "음유시인", "atk": 2.0,  "aspd": 1.00, "kind": "buff_aspd",
	 "desc": "인접 공속 +0.35", "color": Color(0.78, 0.45, 0.88),
	 "sprite": "minifolks/MinifolksHumans/MiniPrinceMan/no_outline"},
]
const MONSTER_SPRITE := "minifolks/MiniBigMonsters/MiniOrcMutant/no_outline"

enum State { PLACING, BATTLE, RESULT }

var _state: int = State.PLACING
var _cells: Array = []                # 9칸 — null 또는 런타임 영웅 Dictionary
var _picked: Dictionary = {}          # 트레이에서 집어든 영웅 정의 (비어있으면 없음)
var _speed: float = 1.0

var _monster_x: float = MONSTER_START_X
var _monster_hp: float = MONSTER_HP
var _wall_hp: float = WALL_HP
var _wall_timer: float = 0.0
var _wall_flash: float = 0.0
var _elapsed: float = 0.0
var _won: bool = false

var _font: Font = load("res://assets/fonts/Galmuri11.ttf")
var _font_b: Font = load("res://assets/fonts/Galmuri11-Bold.ttf")
var _font_s: Font = load("res://assets/fonts/Galmuri9.ttf")

var _frames: Dictionary = {}          # sprite_dir → SpriteFrames (한 번만 만들어 돌려 쓴다)
var _cell_sprites: Array = []         # 9개
var _tray_sprites: Array = []         # 6개
var _monster_sprite: AnimatedSprite2D
var _overlay: Node2D                  # 결과 패널 — 스프라이트 위에 그려야 해서 따로 둔다


func _ready() -> void:
	for d in HEROES:
		_frames[d["sprite"]] = _build_frames(d["sprite"])
	_frames[MONSTER_SPRITE] = _build_frames(MONSTER_SPRITE)

	for i in 9:
		var s := _make_sprite(HERO_SPRITE_SCALE)
		s.position = _cell_rect(i).get_center() + Vector2(0.0, 10.0)
		_cell_sprites.append(s)
	for i in HEROES.size():
		var t := _make_sprite(2.6)
		t.position = _tray_rect(i).position + Vector2(46.0, 78.0)
		t.sprite_frames = _frames[HEROES[i]["sprite"]]
		t.play("idle")
		_tray_sprites.append(t)

	_monster_sprite = _make_sprite(MONSTER_SPRITE_SCALE)
	_monster_sprite.sprite_frames = _frames[MONSTER_SPRITE]
	# 몬스터는 1.5초에 한 번만 때린다 — 휘두르고 idle로 돌아가야 한다
	_monster_sprite.sprite_frames.set_animation_loop("attack", false)
	_monster_sprite.flip_h = true          # 좌측(성벽)을 바라본다
	_monster_sprite.position = Vector2(MONSTER_START_X, MONSTER_Y)

	_overlay = Node2D.new()
	_overlay.z_index = 100
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)

	_reset_board()


func _make_sprite(scale_mult: float) -> AnimatedSprite2D:
	var s := AnimatedSprite2D.new()
	s.scale = Vector2.ONE * scale_mult
	s.centered = true
	add_child(s)
	return s


# TheSevenAutoBattle/src/battle/sprite_frame_loader.gd 를 프로토용으로 줄여 베낀 것.
func _build_frames(sprite_dir: String) -> SpriteFrames:
	var frames := SpriteFrames.new()
	if frames.has_animation(&"default"):
		frames.remove_animation(&"default")
	for anim_name in ANIMS.keys():
		var conf: Dictionary = ANIMS[anim_name]
		frames.add_animation(anim_name)
		frames.set_animation_speed(anim_name, conf["fps"])
		frames.set_animation_loop(anim_name, conf["loop"])
		var dir_path: String = "%s/%s/%s" % [SPRITE_ROOT, sprite_dir, conf["folder"]]
		var dir := DirAccess.open(dir_path)
		if dir == null:
			push_warning("프레임 폴더 없음: %s" % dir_path)
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
	return frames


# ─── 상태 전이 ────────────────────────────────────────────────────────────
func _reset_board() -> void:
	_cells.clear()
	for _i in 9:
		_cells.append(null)
	_picked = {}
	_state = State.PLACING
	_monster_x = MONSTER_START_X
	_monster_hp = MONSTER_HP
	_wall_hp = WALL_HP
	_wall_flash = 0.0
	_elapsed = 0.0
	_monster_sprite.position.x = MONSTER_START_X
	_monster_sprite.visible = false
	_sync_sprites()
	_redraw()


func _start_battle() -> void:
	_monster_x = MONSTER_START_X
	_monster_hp = MONSTER_HP
	_wall_hp = WALL_HP
	_wall_timer = 0.0
	_wall_flash = 0.0
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
			h["swing"] = false
	_monster_sprite.visible = true
	_monster_sprite.play("walk")
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
		_wall_flash = maxf(0.0, _wall_flash - delta * 4.0)
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
			h["swing"] = true
			if h["def"]["kind"] == "ramp":
				h["ramp"] = float(h["ramp"]) + RAMP_GAIN

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
	for i in 9:
		var s: AnimatedSprite2D = _cell_sprites[i]
		var h = _cells[i]
		if h == null:
			s.visible = false
			continue
		s.visible = true
		var f: SpriteFrames = _frames[h["def"]["sprite"]]
		if s.sprite_frames != f:
			s.sprite_frames = f
			s.play("idle")

		# 공격 애니메이션 한 바퀴 = 공격 한 번이 되도록 재생속도를 영웅마다 맞춘다.
		# 이렇게 안 하면 애니메이션 길이와 공격 간격이 어긋나 사이에 idle이 끼어 깜빡인다.
		# 덤으로 "빨리 움직이는 영웅 = 공속 빠른 영웅"이 눈으로 읽힌다.
		if _state == State.BATTLE:
			var fc: float = maxf(1.0, float(f.get_frame_count("attack")))
			s.speed_scale = _speed * clampf(fc * float(h["aspd"]) / float(ANIMS["attack"]["fps"]), 0.5, 2.0)
			if s.animation != &"attack":
				s.play("attack")
		else:
			s.speed_scale = 1.0
			if s.animation != &"idle" or not s.is_playing():
				s.play("idle")
		s.modulate = Color.WHITE.lerp(Color(1.5, 1.4, 1.1), float(h.get("flash", 0.0)) * 0.22)

	for t in _tray_sprites:
		t.visible = (_state == State.PLACING)

	if _monster_sprite.visible:
		_monster_sprite.position.x = _monster_x
		_monster_sprite.speed_scale = _speed if _state == State.BATTLE else 1.0
		if _state == State.BATTLE and not _monster_sprite.is_playing():
			_monster_sprite.play("walk" if _monster_x > MONSTER_STOP_X else "idle")
		var ratio: float = _monster_hp / MONSTER_HP
		_monster_sprite.modulate = Color.WHITE.lerp(Color(1.0, 0.45, 0.45), 1.0 - ratio)


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
		_sync_sprites()
		_redraw()
		return

	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var mp: Vector2 = event.position

	if _btn_rect_primary().has_point(mp):
		if _state == State.PLACING and _placed_count() > 0:
			_start_battle()
		elif _state == State.RESULT:
			_state = State.PLACING
			_monster_x = MONSTER_START_X
			_monster_sprite.position.x = MONSTER_START_X
			_monster_sprite.visible = false
		_sync_sprites()
		_redraw()
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
			_redraw()
			return

	# 칸에 놓기 / 빼기
	for i in 9:
		if not _cell_rect(i).has_point(mp):
			continue
		if _cells[i] != null:
			_cells[i] = null
		elif not _picked.is_empty():
			_cells[i] = {"def": _picked, "atk": 0.0, "aspd": 0.0,
				"cd": 0.0, "dmg": 0.0, "hits": 0, "ramp": 0.0, "flash": 0.0, "swing": false}
		_sync_sprites()
		_redraw()
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
		Vector2(CELL_SIZE - 8.0, CELL_SIZE - 8.0))


func _tray_rect(idx: int) -> Rect2:
	return Rect2(TRAY_ORIGIN + Vector2(float(idx) * (TRAY_CARD.x + TRAY_GAP), 0.0), TRAY_CARD)


func _btn_rect_primary() -> Rect2:
	return Rect2(1600.0, 880.0, 260.0, 140.0)


func _btn_rect_clear() -> Rect2:
	return Rect2(1600.0, 790.0, 260.0, 70.0)


# ─── 그리기 ───────────────────────────────────────────────────────────────
func _draw() -> void:
	_draw_field()
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
	draw_line(Vector2(WALL_RECT.end.x, MONSTER_Y + 130.0), Vector2(1920.0, MONSTER_Y + 130.0),
		Color(0.20, 0.19, 0.23), 3.0)
	draw_string(_font_s, Vector2(WALL_RECT.end.x + 40.0, WALL_RECT.position.y - 16.0), "몬스터 진입로",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.42, 0.40, 0.46))


func _draw_grid() -> void:
	for i in 9:
		var r: Rect2 = _cell_rect(i)
		var h = _cells[i]
		if h == null:
			draw_rect(r, Color(0.15, 0.16, 0.20))
			draw_rect(r, Color(0.30, 0.32, 0.38), false, 2.0)
			draw_string(_font_s, r.position + Vector2(10.0, 26.0), "%d" % _neighbors(i).size(),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.35, 0.37, 0.42))
			continue
		var col: Color = h["def"]["color"]
		var flash: float = float(h["flash"])
		draw_rect(r, col.darkened(0.72).lerp(col.darkened(0.45), flash))
		draw_rect(r, col.lerp(Color.WHITE, flash), false, 2.0 + flash * 3.0)
		# 이름/수치는 칸 위아래 가장자리에 — 가운데는 스프라이트 자리다
		draw_string(_font, r.position + Vector2(8.0, 26.0), str(h["def"]["name"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.95, 0.95, 0.98))
		if _state == State.PLACING:
			draw_string(_font_s, r.position + Vector2(8.0, r.size.y - 12.0),
				"공%.0f 속%.2f" % [float(h["def"]["atk"]), float(h["def"]["aspd"])],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.70, 0.72, 0.78))
		else:
			draw_string(_font_s, r.position + Vector2(8.0, r.size.y - 36.0),
				"공%.0f 속%.2f" % [float(h["atk"]), float(h["aspd"])],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.75, 0.85, 0.75))
			draw_string(_font, r.position + Vector2(8.0, r.size.y - 12.0), "누적 %d" % int(h["dmg"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1.0, 0.92, 0.60))
			var share: float = float(h["dmg"]) / maxf(1.0, MONSTER_HP - _monster_hp)
			draw_rect(Rect2(r.position + Vector2(8.0, r.size.y - 8.0), Vector2((r.size.x - 16.0) * share, 5.0)),
				Color(1.0, 0.85, 0.45))


# 성벽은 병력 오른쪽, 몬스터의 타격 지점에 선다. 위에서부터 무너진다.
func _draw_wall() -> void:
	var ratio: float = _wall_hp / WALL_HP
	var top: float = WALL_RECT.position.y + WALL_RECT.size.y * (1.0 - ratio)

	# 무너져 나간 부분 — 잔해만 남는다
	draw_rect(Rect2(WALL_RECT.position, Vector2(WALL_RECT.size.x, WALL_RECT.size.y * (1.0 - ratio))),
		Color(0.14, 0.13, 0.15))

	var stone := Color(0.52, 0.54, 0.60) if ratio > 0.35 else Color(0.62, 0.40, 0.38)
	stone = stone.lerp(Color(1.0, 0.55, 0.45), _wall_flash * 0.7)
	var standing := Rect2(Vector2(WALL_RECT.position.x, top), Vector2(WALL_RECT.size.x, WALL_RECT.end.y - top))
	draw_rect(standing, stone.darkened(0.35))

	# 돌 쌓기 결 — 픽셀 톤을 맞추려고 격단으로 긋는다
	var y: float = top
	var band: int = 0
	while y < WALL_RECT.end.y:
		var h: float = minf(30.0, WALL_RECT.end.y - y)
		draw_rect(Rect2(WALL_RECT.position.x + 4.0, y + 3.0, WALL_RECT.size.x - 8.0, h - 6.0),
			stone.darkened(0.12 if band % 2 == 0 else 0.22))
		if band % 2 == 0:
			draw_line(Vector2(WALL_RECT.position.x + WALL_RECT.size.x * 0.5, y + 3.0),
				Vector2(WALL_RECT.position.x + WALL_RECT.size.x * 0.5, y + h - 3.0), stone.darkened(0.45), 2.0)
		y += 30.0
		band += 1
	draw_rect(standing, Color(0.80, 0.84, 0.92), false, 3.0)

	draw_string(_font_b, Vector2(WALL_RECT.position.x - 22.0, WALL_RECT.position.y - 16.0),
		"성벽 %d%%" % int(round(ratio * 100.0)),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.85, 0.90, 1.0) if ratio > 0.35 else Color(0.95, 0.55, 0.50))
	draw_string(_font_s, Vector2(WALL_RECT.position.x - 30.0, WALL_RECT.end.y + 28.0), "타격 지점",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.60, 0.45, 0.45))


func _draw_monster_hud() -> void:
	if not _monster_sprite.visible:
		return
	var ratio: float = _monster_hp / MONSTER_HP
	var bar := Rect2(_monster_x - 110.0, MONSTER_Y - 150.0, 220.0, 16.0)
	draw_rect(bar, Color(0.18, 0.10, 0.12))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)), Color(0.82, 0.28, 0.32))
	draw_rect(bar, Color(0.55, 0.35, 0.38), false, 2.0)
	draw_string(_font, Vector2(bar.position.x, bar.position.y - 10.0),
		"몬스터  %d / %d" % [int(_monster_hp), int(MONSTER_HP)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1.0, 0.78, 0.78))
	if _state == State.BATTLE and _monster_x > MONSTER_STOP_X:
		var eta: float = (_monster_x - MONSTER_STOP_X) / MONSTER_SPEED
		draw_string(_font_s, Vector2(bar.position.x, bar.position.y + 44.0),
			"성벽까지 %.1fs" % eta, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.95, 0.80, 0.45))


func _draw_hud() -> void:
	var total: float = MONSTER_HP - _monster_hp
	var dps: float = total / maxf(0.001, _elapsed)
	draw_string(_font_b, Vector2(170.0, 120.0),
		"경과 %.1fs      누적딜 %d      DPS %.0f      배치 %d/9" %
		[_elapsed, int(total), dps, _placed_count()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.80, 0.84, 0.92))
	draw_string(_font_s, Vector2(170.0, 160.0),
		"칸의 숫자 = 인접 칸 수 (중앙 4 / 변 3 / 모서리 2)      속도 %.0fx  [1][2][3]" % _speed,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.50, 0.54, 0.62))

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
	draw_string(_font_b, br.position + Vector2(20.0, 80.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.92, 0.95, 1.0))

	if _state == State.PLACING:
		var cr: Rect2 = _btn_rect_clear()
		draw_rect(cr, Color(0.26, 0.20, 0.22))
		draw_rect(cr, Color(0.60, 0.45, 0.48), false, 2.0)
		draw_string(_font, cr.position + Vector2(20.0, 44.0), "판 비우기",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.90, 0.80, 0.82))


func _draw_tray() -> void:
	for i in HEROES.size():
		var d: Dictionary = HEROES[i]
		var r: Rect2 = _tray_rect(i)
		var col: Color = d["color"]
		var on: bool = not _picked.is_empty() and _picked["id"] == d["id"]
		draw_rect(r, col.darkened(0.72) if not on else col.darkened(0.45))
		draw_rect(r, col if on else col.darkened(0.30), false, 3.0 if on else 2.0)
		# 왼쪽은 스프라이트 자리, 글자는 오른쪽으로 민다
		draw_string(_font, r.position + Vector2(92.0, 32.0), str(d["name"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.95, 0.95, 0.98))
		draw_string(_font_s, r.position + Vector2(92.0, 58.0),
			"공%.0f 속%.2f" % [float(d["atk"]), float(d["aspd"])],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.75, 0.78, 0.84))
		draw_string(_font_s, r.position + Vector2(92.0, 82.0), "DPS %.1f" % (float(d["atk"]) * float(d["aspd"])),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.85, 0.80, 0.55))
		draw_string(_font_s, r.position + Vector2(10.0, 128.0), str(d["desc"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.65, 0.68, 0.75))


# 결과 패널만 z_index를 올려 스프라이트 위에 그린다.
func _draw_overlay() -> void:
	if _state != State.RESULT:
		return
	var panel := Rect2(560.0, 260.0, 800.0, 520.0)
	_overlay.draw_rect(panel, Color(0.12, 0.13, 0.17, 0.96))
	_overlay.draw_rect(panel, Color(0.55, 0.60, 0.72), false, 3.0)
	var head: String = "몬스터 처치" if _won else "성벽 붕괴"
	_overlay.draw_string(_font_b, panel.position + Vector2(36.0, 70.0), head,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 44, Color(0.60, 0.90, 0.65) if _won else Color(0.92, 0.45, 0.42))
	var score: String = ""
	if _won:
		score = "성벽 잔여 %d%%     소요 %.1fs" % [int(round(_wall_hp / WALL_HP * 100.0)), _elapsed]
	else:
		score = "몬스터 잔여 %d%%     버틴 시간 %.1fs" % [int(round(_monster_hp / MONSTER_HP * 100.0)), _elapsed]
	_overlay.draw_string(_font, panel.position + Vector2(36.0, 118.0), score,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.85, 0.88, 0.94))

	var ranked: Array = []
	for i in 9:
		if _cells[i] != null:
			ranked.append(_cells[i])
	ranked.sort_custom(func(a, b): return float(a["dmg"]) > float(b["dmg"]))
	var y: float = 180.0
	var total: float = maxf(1.0, MONSTER_HP - _monster_hp)
	for h in ranked:
		var pct: float = float(h["dmg"]) / total
		_overlay.draw_string(_font, panel.position + Vector2(36.0, y), str(h["def"]["name"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22, h["def"]["color"])
		_overlay.draw_string(_font_s, panel.position + Vector2(180.0, y),
			"%d  (%d%%)  %d타" % [int(h["dmg"]), int(round(pct * 100.0)), int(h["hits"])],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.80, 0.83, 0.90))
		_overlay.draw_rect(Rect2(panel.position + Vector2(430.0, y - 16.0), Vector2(320.0 * pct, 14.0)),
			Color(h["def"]["color"]).darkened(0.2))
		y += 36.0
