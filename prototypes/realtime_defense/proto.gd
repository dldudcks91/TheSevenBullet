# PROTOTYPE - NOT FOR PRODUCTION
# Question: 흐르는 시간 속에서 구매·배치 판단이 실제로 성립하는가?
#           (부수 측정: 킬 속도가 여유 시간으로 환산되는가 /
#            감산·비율 두 공식이 "보스마다 답이 갈린다"를 실제로 만드는가)
# Date: 2026-08-11
#
# 기준 문서: docs/game_design/GAME_DESIGN.md — 실시간 로그라이크 TD.
# 넣은 것: 3×3(한 칸=한 부대) · 무정지 실시간 · 스폰 스케줄과 겹침 · 최근접 타게팅 ·
#          물리 감산 / 마법 원소별 비율 · 원소 4종 · 직업 리듬(평타·확률·캐스팅) ·
#          유물(전역 보유 · [직업] 태그 · 자동 발동) · 상태이상 7종 ·
#          5슬롯 매대 + 드래그 구매 + 유료 리롤 · 성벽 HP 지속 + 수리/업그레이드 ·
#          예고 슬롯 · 칸별 기여도
# 뺀 것:   기사·암살자·리더(발동 방식 미결) · 사기(증감 규칙 미결) · 저주(갈래 미결) ·
#          전술카드 · 종족 시너지 · 보스 디버프 · 구간/거물 연출 · 언락 · 밸런싱
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
# 상세 카드는 측정 패널 자리에 뜬다 — 레인을 가리지 않고, 시선이 매대 옆이라 싸다.
# 아래로 조금 더 뻗어 읽을 줄 수를 번다 (그 아래는 비어 있다).
const DETAIL_RECT := Rect2(1566.0, 706.0, 298.0, 322.0)

# 유물 슬롯 줄 — 유물은 칸이 아니라 여기에 놓는다 (전역 보유)
const RELICROW_ORIGIN := Vector2(56.0, 966.0)
const RELIC_SLOT := Vector2(150.0, 56.0)
const RELIC_GAP := 10.0
const RELIC_SLOTS := 4

# 예고 슬롯 — 화면 구석. 다음 보스의 정체를 미리 알린다
const FORECAST_RECT := Rect2(1584.0, 190.0, 280.0, 112.0)

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

# 원소 저항 상한. 어떤 보스도 이 이상은 막지 못한다. 실제 값은 「미결」이라 임시값이다.
const RES_CAP := 0.75

const CHILL_MOVE := 0.55              # 빙결 — 이동·공격속도에 곱해진다
const BURN_TICK := 2.4                # 화상 스택당 초당 고정 추가피해
const BURN_DURATION := 6.0
const BURN_REGEN_CUT := 0.5           # 화상 — 회복 감소
const POISON_TICK := 3.0              # 중독 스택당 초당 지속딜
const POISON_DURATION := 7.0
const VULN_DURATION := 5.0
const SHRED_DURATION := 6.0
const STUN_DURATION := 1.1

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

# ─── 원소 ─────────────────────────────────────────────────────────────────
# 저항 하나가 두 일을 한다 — 그 원소 피해의 감소율이면서, 그 원소 상태이상의 저항이다.
const ELEMENTS := {
	"cold":   {"name": "냉기", "short": "냉", "color": Color(0.55, 0.82, 0.98)},
	"fire":   {"name": "화염", "short": "화", "color": Color(0.98, 0.52, 0.32)},
	"poison": {"name": "독",   "short": "독", "color": Color(0.60, 0.86, 0.42)},
	"shock":  {"name": "번개", "short": "번", "color": Color(0.86, 0.74, 0.98)},
}
const ELEM_ORDER := ["cold", "fire", "poison", "shock"]

# ─── 직업 ─────────────────────────────────────────────────────────────────
# 직업은 "스킬이 언제 터지는가" = 리듬을 정한다. 동사(밀어내기·상태이상)는 전부 유물 몫이다.
#   atk    — 평타의 피해 타입. "none"이면 평타가 없다
#   cast   — 평타를 포기하고 주기마다 큰 것을 내보낸다
#   period — 평타 주기 또는 캐스팅 시간. 유물이 차는 "박자"의 단위이기도 하다
#
# 기사·암살자·리더는 발동 방식이 「미결」이라 넣지 않았다. 전사는 확정된 발동 방식이 없어
# 스킬 없이 평타만 친다 — 감산 공식의 기준선 역할이다.
const JOBS := {
	"warrior": {"name": "전사",   "atk": "phys", "cast": false, "period": 1.00,
	 "rhythm": "평타만 — 스킬 없음", "color": Color(0.88, 0.42, 0.34)},
	"archer":  {"name": "궁수",   "atk": "phys", "cast": false, "period": 0.55,
	 "rhythm": "평타마다 확률 발동", "color": Color(0.45, 0.78, 0.46)},
	"mage":    {"name": "마법사", "atk": "none", "cast": true,  "period": 2.60,
	 "rhythm": "캐스팅 — 보스에게", "color": Color(0.46, 0.52, 0.94)},
	"cleric":  {"name": "사제",   "atk": "none", "cast": true,  "period": 3.20,
	 "rhythm": "캐스팅 — 아군에게", "color": Color(0.95, 0.86, 0.48)},
}

# power  — 물리는 "칸의 박자당 총 공격력"이다. 인원이 이걸 나눠 타격당 딜을 만든다.
#          마법은 "캐스팅 1회의 딜"이고 인원과 무관하다 — 마법은 인원 곡선에서 벗어난다.
# skill  — 유닛 고유. 터지는 시점은 직업이 정한다.
const UNITS := [
	{"id": "sw1", "job": "warrior", "tier": 1, "name": "검사대",       "race": "인간",
	 "members": 6, "power": 30.0, "price": 30,
	 "sprite": "minifolks/MinifolksHumans/MiniSwordMan/no_outline"},
	{"id": "sw2", "job": "warrior", "tier": 2, "name": "오크 전사단",   "race": "오크",
	 "members": 3, "power": 44.0, "price": 60,
	 "sprite": "minifolks/MinifolksOrcs/MiniOrcWarrior/no_outline"},
	{"id": "sw3", "job": "warrior", "tier": 3, "name": "오크 정예",     "race": "오크",
	 "members": 1, "power": 60.0, "price": 110,
	 "sprite": "minifolks/MinifolksOrcs/MiniOrcVeteran/no_outline"},

	# 궁수의 확률은 인원을 탄다 — 6명은 한 박자에 6번 굴려 거의 확정, 2명은 드물게 터진다.
	{"id": "ar1", "job": "archer",  "tier": 1, "name": "궁수대",        "race": "인간",
	 "members": 6, "power": 22.0, "price": 30, "crit": 0.25, "crit_mult": 2.2,
	 "sprite": "minifolks/MinifolksHumans/MiniArcherMan/no_outline"},
	{"id": "ar2", "job": "archer",  "tier": 2, "name": "해골 궁수단",   "race": "언데드",
	 "members": 4, "power": 28.0, "price": 60, "crit": 0.25, "crit_mult": 2.2,
	 "sprite": "minifolks/MinifolksUndead/MiniSkeletonArcher/no_outline"},
	{"id": "ar3", "job": "archer",  "tier": 3, "name": "명사수",        "race": "다크엘프",
	 "members": 2, "power": 33.0, "price": 110, "crit": 0.25, "crit_mult": 2.2,
	 "sprite": "minifolks/MiniDarkElves/MiniDarkElfArcher/no_outline"},

	{"id": "mg1", "job": "mage",    "tier": 1, "name": "견습 마법사단", "race": "인간",
	 "members": 4, "power": 88.0, "price": 30, "elem": "fire",
	 "sprite": "minifolks/MinifolksHumans/MiniMage/no_outline"},
	{"id": "mg2", "job": "mage",    "tier": 2, "name": "다크엘프 술사", "race": "다크엘프",
	 "members": 2, "power": 128.0, "price": 60, "elem": "cold",
	 "sprite": "minifolks/MiniDarkElves/MiniDarkElfWizard/no_outline"},
	{"id": "mg3", "job": "mage",    "tier": 3, "name": "리치",          "race": "언데드",
	 "members": 1, "power": 190.0, "price": 110, "elem": "shock",
	 "sprite": "minifolks/MinifolksUndead/MiniLich/no_outline"},

	# 사제의 축복은 캐스팅으로 나간다. 고정값이라 인원 많고 박자 빠른 부대에서 가장 크게 불어난다.
	{"id": "cl1", "job": "cleric",  "tier": 1, "name": "빛의 사제",     "race": "별방랑자",
	 "members": 4, "power": 0.0, "price": 35, "bless": 1.6,
	 "sprite": "minifolks/MiniStarWanderers/MiniSWPriestess/no_outline"},
	{"id": "cl2", "job": "cleric",  "tier": 2, "name": "불의 사제",     "race": "불의교단",
	 "members": 2, "power": 0.0, "price": 65, "bless": 2.8,
	 "sprite": "minifolks/MiniOrderOfTheFire/MiniFirePriestess/no_outline"},
	{"id": "cl3", "job": "cleric",  "tier": 3, "name": "숲의 드루이드", "race": "수인족",
	 "members": 1, "power": 0.0, "price": 115, "bless": 4.5,
	 "sprite": "minifolks/MiniBeastmens/MiniDeerDruid/no_outline"},
]

const BLESS_HOLD := 1.7               # 축복 지속 = 사제 캐스팅 주기 × 이 값 (끊기지 않게)

# ─── 유물 = 동사의 공급원 ─────────────────────────────────────────────────
# 전역 보유다. 칸에 장착하지 않고 유물 슬롯 줄에 둔다.
# [직업] 태그가 수행 주체를 정하고, 효과는 그 직업 부대들의 박자에 실려 자동으로 나간다.
# 쿨다운이 초가 아니라 "몸의 박자 수"라서, 같은 밀어내기도 다수·빠른 부대에선 잦고 작게,
# 소수정예에선 드물고 크게 나간다 — 동사의 변형을 체급 시스템이 공짜로 만든다.
const RELICS := [
	{"id": "hammer", "verb": "push", "job": "warrior", "name": "충격 망치", "beats": 7, "price": 55,
	 "elem": "", "color": Color(0.96, 0.76, 0.36), "short": "넉백",
	 "desc": "최근접 보스를 밀어낸다. 거리는 타격당 딜에 비례한다."},
	{"id": "breaker", "verb": "shred", "job": "warrior", "name": "균열 정", "beats": 9, "price": 55,
	 "elem": "", "color": Color(0.86, 0.62, 0.50), "short": "파쇄 — 방어력 감소",
	 "desc": "보스의 방어력을 깎는다. 감산이라 딜 0인 칸을 한 번에 되살리는 폭발형이다."},
	{"id": "brand", "verb": "burn", "job": "archer", "name": "화염 낙인", "beats": 14, "price": 55,
	 "elem": "fire", "color": Color(0.98, 0.46, 0.30), "short": "화상 — 화염",
	 "desc": "화상 스택을 얹는다. 틱당 고정값이라 타격 횟수 많은 부대와 맞는다. 회복도 깎는다."},
	{"id": "venom", "verb": "poison", "job": "archer", "name": "독 바른 촉", "beats": 12, "price": 55,
	 "elem": "poison", "color": Color(0.60, 0.86, 0.42), "short": "중독 — 독",
	 "desc": "중독 스택을 얹는다. 지속딜은 방어력을 보지 않는다."},
	{"id": "fetter", "verb": "chill", "job": "mage", "name": "서리 족쇄", "beats": 3, "price": 55,
	 "elem": "cold", "color": Color(0.55, 0.82, 0.98), "short": "빙결 — 냉기",
	 "desc": "이동·공격속도를 떨어뜨린다. 걸어오는 시간이 곧 공격 가능 시간이다."},
	{"id": "bolt", "verb": "stun", "job": "mage", "name": "뇌격 인장", "beats": 5, "price": 65,
	 "elem": "", "color": Color(0.86, 0.74, 0.98), "short": "스턴",
	 "desc": "모든 행동을 멈춘다. 성벽 타격 중이면 그 동안 피해가 멎는다."},
	{"id": "mark", "verb": "vuln", "job": "cleric", "name": "표적 성흔", "beats": 3, "price": 55,
	 "elem": "shock", "color": Color(0.98, 0.88, 0.55), "short": "취약 — 번개",
	 "desc": "받는 피해를 비율로 올린다. 비율이라 한 방이 굵은 소수정예와 맞는다."},
]

# ─── 보스 ─────────────────────────────────────────────────────────────────
# res 는 원소 저항. 값을 그대로 감소율로 쓴다 — 0.60이면 60% 감소. 상한은 RES_CAP.
#
# tags 는 디아블로의 유니크 접두사처럼 쓴다 — **가진 것만 적는다.** 이름 아래 한 줄로 붙어서
# "이 놈이 무엇인가"를 수치 없이 먼저 알린다. 없는 것(저방어·느림 같은 약점)은 적지 않는다.
const ARCHETYPES := [
	{"id": "rush", "name": "돌격형", "scale": 4.6, "tint": Color(0.96, 0.58, 0.36),
	 "hp": 480.0, "armor": 2.0, "speed": 108.0, "tags": ["질주"],
	 "res": {"cold": 0.10, "fire": 0.10, "poison": 0.10, "shock": 0.10},
	 "wall_dmg": 24.0, "wall_int": 1.3, "push_res": 0.35, "regen": 0.0,
	 "hint": "빠르다 — 지연·밀어내기가 값진다",
	 "sprite": "minifolks/MiniMonsters/MiniMinotaur/no_outline"},
	{"id": "armor", "name": "장갑형", "scale": 5.0, "tint": Color(0.76, 0.80, 0.90),
	 "hp": 700.0, "armor": 13.0, "speed": 62.0, "tags": ["중장갑"],
	 "res": {"cold": 0.05, "fire": 0.05, "poison": 0.05, "shock": 0.05},
	 "wall_dmg": 38.0, "wall_int": 1.6, "push_res": 0.55, "regen": 0.0,
	 "hint": "잘게 쪼갠 물리는 0이 된다",
	 "sprite": "minifolks/MiniBigMonsters/MiniOrcMutant/no_outline"},
	{"id": "hex", "name": "주술형", "scale": 4.8, "tint": Color(0.74, 0.56, 0.96),
	 "hp": 640.0, "armor": 3.0, "speed": 70.0, "tags": [],
	 "res": {"cold": 0.12, "fire": 0.12, "poison": 0.12, "shock": 0.12},
	 "wall_dmg": 32.0, "wall_int": 1.4, "push_res": 0.45, "regen": 0.0,
	 "hint": "막히면 다른 원소로 갈아탄다",
	 "sprite": "minifolks/MiniBigMonsters/MiniDarkLord/no_outline"},
	{"id": "regen", "name": "재생형", "scale": 5.0, "tint": Color(0.56, 0.86, 0.80),
	 "hp": 760.0, "armor": 7.0, "speed": 58.0, "tags": ["재생"],
	 "res": {"cold": 0.25, "fire": 0.25, "poison": 0.25, "shock": 0.25},
	 "wall_dmg": 28.0, "wall_int": 1.5, "push_res": 0.50, "regen": 13.0,
	 "hint": "화력이 모자라면 안 죽는다",
	 "sprite": "minifolks/MiniBigMonsters/MiniYeti/no_outline"},
	{"id": "tyrant", "name": "거물", "scale": 5.4, "tint": Color(0.96, 0.38, 0.42),
	 "hp": 1200.0, "armor": 15.0, "speed": 66.0, "tags": ["거물", "중장갑", "재생", "강인"],
	 "res": {"cold": 0.40, "fire": 0.40, "poison": 0.40, "shock": 0.40},
	 "wall_dmg": 50.0, "wall_int": 1.4, "push_res": 0.70, "regen": 9.0,
	 "hint": "구간의 끝 — 축이 전부 높다",
	 "sprite": "minifolks/MiniBigMonsters/MiniHydra/no_outline"},
]
const HEX_RES := 0.70                 # 주술형이 정통으로 막는 한 원소

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
var _relics: Array = []               # RELIC_SLOTS — null 또는 유물 정의. 전역 보유다
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
var _log_zero_hits: int = 0           # 감산에 먹혀 딜 0이 된 타격
var _log_total_hits: int = 0
var _log_phys_raw: float = 0.0        # 방어력 빼기 전 물리 총합
var _log_phys_out: float = 0.0        # 실제로 들어간 물리 총합
var _log_relic_fires: int = 0

# 드래그
var _drag_kind: String = ""           # "" | "shop" | "cell"
var _drag_from: int = -1
var _drag_moved: bool = false
var _mouse: Vector2 = Vector2.ZERO
var _mouse_down_at: Vector2 = Vector2.ZERO

# 상세 카드 — 캐릭터 위에서 걷어낸 글자가 전부 여기로 모인다.
# 읽기는 호버, 클릭은 고정(핀). 호버가 있으면 호버가 이기고, 없으면 고정된 것이 남는다.
var _pin_kind: String = ""            # "" | "shop" | "cell" | "relic" | "boss" | "forecast"
var _pin_idx: int = -1
var _detail_kind: String = ""         # 이번 프레임에 카드가 실제로 보여주는 것
var _detail_idx: int = -1

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
	_log_zero_hits = 0
	_log_total_hits = 0
	_log_phys_raw = 0.0
	_log_phys_out = 0.0
	_log_relic_fires = 0
	_drag_kind = ""
	_pin_kind = ""

	_cells.clear()
	for _i in 9:
		_cells.append(null)
	_relics.clear()
	for _i in RELIC_SLOTS:
		_relics.append(null)
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
		var res: Dictionary = (arch["res"] as Dictionary).duplicate()
		var hex_elem: String = ""
		if str(arch["id"]) == "hex":
			# 어느 원소를 막을지는 개체가 정한다 — 내 빌드를 정통으로 막을 수도, 허공에 뜰 수도 있다
			hex_elem = ELEM_ORDER[_rng.randi_range(0, ELEM_ORDER.size() - 1)]
			res[hex_elem] = HEX_RES
		for e in ELEM_ORDER:
			res[e] = minf(float(res[e]) + float(i) * 0.012, 0.92)
		_schedule.append({
			"arch": arch,
			"index": i,
			"at": t,
			"hp": float(arch["hp"]) * mult,
			"armor": float(arch["armor"]) * (1.0 + float(i) * 0.06),
			"res": res,
			"hex_elem": hex_elem,
			"wall_dmg": float(arch["wall_dmg"]) * (1.0 + float(i) * 0.05),
			"regen": float(arch["regen"]) * mult,
			"gold": (KILL_GOLD_BASE + KILL_GOLD_STEP * i) * (2 if arch["id"] == "tyrant" else 1),
		})
		t += lerpf(INTERVAL_EARLY, INTERVAL_LATE, float(i) / float(RUN_BOSSES - 1))


func _entry_tags(entry: Dictionary) -> Array:
	var tags: Array = []
	for tg in entry["arch"]["tags"]:
		tags.append(str(tg))
	if str(entry["hex_elem"]) != "":
		tags.append("%s 저항" % str(ELEMENTS[entry["hex_elem"]]["name"]))
	return tags


# ─── 매대 ─────────────────────────────────────────────────────────────────
func _roll_card(units_only: bool) -> Dictionary:
	# 풀은 순수 랜덤이다. 단 첫 매대는 병사카드로 채운다 — 빈 격자에 유물은 살 수 없는 매물이다.
	if not units_only and _rng.randf() < 0.3:
		var it: Dictionary = RELICS[_rng.randi_range(0, RELICS.size() - 1)]
		return {"kind": "relic", "def": it, "price": int(it["price"])}
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
	var job: Dictionary = JOBS[d["job"]]
	return {
		"def": d,
		"members": int(d["members"]),
		"power": float(d["power"]),
		"bless": 0.0,                 # 인접 사제의 축복 합계 — 아래 bless_src 에서 매 프레임 다시 센다
		"bless_src": {},              # 사제 칸 idx → {"amt", "t"}. 사제마다 따로 들고 있어야
		                              # 캐스팅이 반복돼도 자기 몫을 덮어쓰기만 하고 쌓이지 않는다
		"period": float(job["period"]),
		"cd": float(job["period"]),
		"beats": 0,
		"dmg": 0.0,
		"hits": 0,
		"crits": 0,
		"flash": 0.0,
		"cast_flash": 0.0,
		"relic_beats": {},            # 유물 id → 쌓인 박자
		"relic_flash": 0.0,
	}


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


# 물리 타격당 딜. 인원이 총 공격력을 나누고, 축복이 타격마다 고정값으로 붙는다.
func _per_hit(sq: Dictionary) -> float:
	if float(sq["power"]) <= 0.0:
		return float(sq["bless"])
	return float(sq["power"]) / float(sq["members"]) + float(sq["bless"])


# ─── 데미지 계산 ──────────────────────────────────────────────────────────
# 물리는 빼고, 마법은 곱한다. 성격이 정반대라 보스마다 답이 갈린다.
func _armor_now(boss) -> float:
	if boss == null:
		return 0.0
	return maxf(0.0, float(boss["armor"]) - float(boss["shred"]))


func _res_now(boss, elem: String) -> float:
	if boss == null or elem == "":
		return 0.0
	# 저항은 음수까지 내려간다(100% 초과 피해). 상한만 둔다.
	return minf(float(boss["res"][elem]), RES_CAP)


func _vuln_mult(boss) -> float:
	if boss == null:
		return 1.0
	return 1.0 + float(boss["vuln"])


# 물리 — 감산. 최소 보장은 두지 않는다. 딜이 방어력 이하면 0이다.
func _phys_damage(per: float, boss) -> float:
	if boss == null:
		return per
	return maxf(0.0, per - _armor_now(boss)) * _vuln_mult(boss)


# 마법 — 비율. 타격 횟수와 무관하다.
func _mag_damage(amount: float, elem: String, boss) -> float:
	if boss == null:
		return amount
	return amount * (1.0 - _res_now(boss, elem)) * _vuln_mult(boss)


# 상태이상의 지속딜. 방어력을 보지 않고 원소 저항만 본다.
func _dot_damage(amount: float, elem: String, boss) -> float:
	return amount * (1.0 - _res_now(boss, elem)) * _vuln_mult(boss)


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
		"tags": _entry_tags(entry),
		"x": BOSS_SPAWN_X,
		"lane_y": BOSS_BASE_Y + float((_bosses.size() % 3) - 1) * 44.0,
		"hp": float(entry["hp"]),
		"hp_max": float(entry["hp"]),
		"armor": float(entry["armor"]),
		"res": (entry["res"] as Dictionary).duplicate(),
		"hex_elem": str(entry["hex_elem"]),
		"wall_dmg": float(entry["wall_dmg"]),
		"regen": float(entry["regen"]),
		"gold": int(entry["gold"]),
		"speed": float(entry["arch"]["speed"]),
		"wall_cd": 0.0,
		# 상태이상 — 보스도 아군도 걸릴 수 있는 공용 개념이지만, 프로토는 보스 쪽만 태운다
		"chill": 0.0,
		"burn": 0, "burn_t": 0.0,
		"pois": 0, "pois_t": 0.0,
		"vuln": 0.0, "vuln_t": 0.0,
		"shred": 0.0, "shred_t": 0.0,
		"stun": 0.0,
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


func _boss_states(b: Dictionary) -> Array:
	var out: Array = []
	if float(b["chill"]) > 0.0:
		out.append("빙결 %.1fs" % float(b["chill"]))
	if int(b["burn"]) > 0:
		out.append("화상 x%d" % int(b["burn"]))
	if int(b["pois"]) > 0:
		out.append("중독 x%d" % int(b["pois"]))
	if float(b["vuln"]) > 0.0:
		out.append("취약 +%d%%" % int(round(float(b["vuln"]) * 100.0)))
	if float(b["shred"]) > 0.0:
		out.append("파쇄 -%.0f" % float(b["shred"]))
	if float(b["stun"]) > 0.0:
		out.append("스턴")
	return out


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

		# 상태이상 지속시간
		b["chill"] = maxf(0.0, float(b["chill"]) - dt)
		b["stun"] = maxf(0.0, float(b["stun"]) - dt)
		b["vuln_t"] = maxf(0.0, float(b["vuln_t"]) - dt)
		if float(b["vuln_t"]) <= 0.0:
			b["vuln"] = 0.0
		b["shred_t"] = maxf(0.0, float(b["shred_t"]) - dt)
		if float(b["shred_t"]) <= 0.0:
			b["shred"] = 0.0

		# 화상 — 틱당 고정 추가피해 + 회복 감소
		if int(b["burn"]) > 0:
			b["burn_t"] = float(b["burn_t"]) - dt
			b["hp"] = float(b["hp"]) - _dot_damage(BURN_TICK * float(b["burn"]), "fire", b) * dt
			if float(b["burn_t"]) <= 0.0:
				b["burn"] = 0
		# 중독 — 지속딜
		if int(b["pois"]) > 0:
			b["pois_t"] = float(b["pois_t"]) - dt
			b["hp"] = float(b["hp"]) - _dot_damage(POISON_TICK * float(b["pois"]), "poison", b) * dt
			if float(b["pois_t"]) <= 0.0:
				b["pois"] = 0

		if float(b["regen"]) > 0.0:
			var rg: float = float(b["regen"]) * (BURN_REGEN_CUT if int(b["burn"]) > 0 else 1.0)
			b["hp"] = minf(float(b["hp_max"]), float(b["hp"]) + rg * dt)

		if float(b["stun"]) > 0.0:
			if float(b["hp"]) <= 0.0:
				_kill(b)
			continue                  # 스턴 — 모든 행동 정지

		var spd: float = float(b["speed"])
		if float(b["chill"]) > 0.0:
			spd *= CHILL_MOVE

		if float(b["x"]) > BOSS_STOP_X:
			b["x"] = maxf(BOSS_STOP_X, float(b["x"]) - spd * dt)
			if float(b["x"]) <= BOSS_STOP_X:
				b["wall_cd"] = float(b["arch"]["wall_int"]) * 0.5
		else:
			# 빙결은 공격속도도 떨어뜨린다
			var atk_dt: float = dt * (CHILL_MOVE if float(b["chill"]) > 0.0 else 1.0)
			b["wall_cd"] = float(b["wall_cd"]) - atk_dt
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
	for idx in 9:
		var sq = _cells[idx]
		if sq == null:
			continue
		sq["flash"] = maxf(0.0, float(sq["flash"]) - dt * 6.0)
		sq["cast_flash"] = maxf(0.0, float(sq["cast_flash"]) - dt * 2.0)
		sq["relic_flash"] = maxf(0.0, float(sq["relic_flash"]) - dt * 2.0)
		# 축복은 시간이 지나면 걷힌다 — 사제가 자리를 뜨면 자연히 사라진다.
		# 사제별로 따로 세므로 같은 사제가 다시 걸어도 값이 쌓이지 않고, 사제가 둘이면 합쳐진다.
		var bless_sum: float = 0.0
		for k in sq["bless_src"].keys():
			var ent: Dictionary = sq["bless_src"][k]
			ent["t"] = float(ent["t"]) - dt
			if float(ent["t"]) <= 0.0:
				sq["bless_src"].erase(k)
			else:
				bless_sum += float(ent["amt"])
		sq["bless"] = bless_sum

		sq["cd"] = float(sq["cd"]) - dt
		while float(sq["cd"]) <= 0.0:
			sq["cd"] = float(sq["cd"]) + float(sq["period"])
			sq["beats"] = int(sq["beats"]) + 1
			var job: Dictionary = JOBS[sq["def"]["job"]]
			if bool(job["cast"]):
				_do_cast(idx, sq, target)
			else:
				_do_basic(sq, target)
			# 유물은 부대의 박자에 실려 자동으로 나간다
			_tick_relics(sq, target)
			target = _target_boss()


# 평타 — 한 박자에 인원 수만큼 개별 판정. 부대원이 각자 자기 주기로 때리지 않는다.
func _do_basic(sq: Dictionary, target) -> void:
	if target == null or target["dead"]:
		return
	var d: Dictionary = sq["def"]
	var is_archer: bool = str(d["job"]) == "archer"
	var per: float = _per_hit(sq)
	var total: float = 0.0
	for _m in int(sq["members"]):
		var hit: float = per
		# 궁수 — 평타마다 n% 확률로 스킬이 터진다. 크리는 기본 0이고 궁수만 갖는다.
		if is_archer and _rng.randf() < float(d["crit"]):
			hit = per * float(d["crit_mult"])
			sq["crits"] = int(sq["crits"]) + 1
		var one: float = _phys_damage(hit, target)
		_log_phys_raw += hit
		_log_phys_out += one
		_log_total_hits += 1
		if one <= 0.0:
			_log_zero_hits += 1
		total += one
	if total <= 0.0:
		return
	target["hp"] = float(target["hp"]) - total
	target["flash"] = 1.0
	sq["dmg"] = float(sq["dmg"]) + total
	sq["hits"] = int(sq["hits"]) + int(sq["members"])
	sq["flash"] = 1.0
	if float(target["hp"]) <= 0.0:
		_kill(target)


# 캐스팅 — 평타를 포기한 둘. 대상만 다르다: 마법사는 보스에게, 사제는 아군에게.
func _do_cast(idx: int, sq: Dictionary, target) -> void:
	var d: Dictionary = sq["def"]
	sq["cast_flash"] = 1.0
	if str(d["job"]) == "mage":
		if target == null or target["dead"]:
			return
		# 마법은 인원과 무관하다 — 인원이 몇이든 결과가 같다
		var one: float = _mag_damage(float(sq["power"]), str(d["elem"]), target)
		target["hp"] = float(target["hp"]) - one
		target["flash"] = 1.0
		sq["dmg"] = float(sq["dmg"]) + one
		sq["hits"] = int(sq["hits"]) + 1
		sq["flash"] = 1.0
		if float(target["hp"]) <= 0.0:
			_kill(target)
	else:
		# 사제 — 인접 칸에 축복. 고정값이라 인원 많고 박자 빠른 부대에서 가장 크게 불어난다.
		# 중첩은 막지 않는다 — 사제가 둘이면 둘 다 걸린다. 다만 같은 사제의 재캐스팅은
		# 자기 몫을 덮어쓸 뿐이라 혼자서 무한히 쌓이지는 않는다.
		var amount: float = float(d["bless"])
		for j in _neighbors(idx):
			var n = _cells[j]
			if n == null:
				continue
			n["bless_src"][idx] = {"amt": amount, "t": float(sq["period"]) * BLESS_HOLD}


# ─── 유물 발동 ────────────────────────────────────────────────────────────
func _tick_relics(sq: Dictionary, target) -> void:
	for r in _relics:
		if r == null:
			continue
		if str(r["job"]) != str(sq["def"]["job"]):
			continue
		var id: String = str(r["id"])
		var n: int = int(sq["relic_beats"].get(id, 0)) + 1
		if n < int(r["beats"]):
			sq["relic_beats"][id] = n
			continue
		sq["relic_beats"][id] = 0
		if target == null or target["dead"]:
			continue
		_fire_relic(r, sq, target)


func _fire_relic(r: Dictionary, sq: Dictionary, target: Dictionary) -> void:
	sq["relic_flash"] = 1.0
	_log_relic_fires += 1
	# 효과량은 그 부대의 타격당 딜에 비례한다 — 다수는 잦고 작게, 소수정예는 드물고 크게
	# 평타가 없는 둘은 눈금이 다르므로 맞춰준다 — 마법사는 캐스팅 딜, 사제는 축복값이 기준이다
	var per: float = maxf(1.0, _per_hit(sq))
	match str(sq["def"]["job"]):
		"mage":
			per = float(sq["power"]) / 6.0
		"cleric":
			per = float(sq["def"]["bless"]) * 4.0
	var elem: String = str(r["elem"])
	var resist: float = _res_now(target, elem)
	match str(r["verb"]):
		"push":
			var dist: float = clampf(70.0 + per * 1.6, 70.0, 340.0) * _push_mult(target)
			target["x"] = minf(BOSS_SPAWN_X, float(target["x"]) + dist)
			target["push_flash"] = 1.0
			if float(target["x"]) > BOSS_STOP_X:
				target["wall_cd"] = 0.0
		"shred":
			# 파쇄는 방어력만 깎는다. 원소 저항은 건드리지 않는다
			target["shred"] = minf(float(target["armor"]),
				float(target["shred"]) + clampf(per * 0.55, 2.0, 12.0))
			target["shred_t"] = SHRED_DURATION
		"chill":
			target["chill"] = maxf(float(target["chill"]),
				clampf(1.6 + per * 0.05, 1.6, 5.0) * (1.0 - resist))
		"burn":
			target["burn"] = mini(12, int(target["burn"]) + 1 + int(per / 8.0))
			target["burn_t"] = BURN_DURATION
		"poison":
			target["pois"] = mini(12, int(target["pois"]) + 1 + int(per / 10.0))
			target["pois_t"] = POISON_DURATION
		"vuln":
			target["vuln"] = maxf(float(target["vuln"]),
				clampf(0.12 + per * 0.010, 0.12, 0.45) * (1.0 - resist))
			target["vuln_t"] = VULN_DURATION
		"stun":
			target["stun"] = maxf(float(target["stun"]), STUN_DURATION)


func _relic_count(job: String) -> int:
	var n: int = 0
	for r in _relics:
		if r != null and str(r["job"]) == job:
			n += 1
	return n


func _has_relic(id: String) -> bool:
	for r in _relics:
		if r != null and str(r["id"]) == id:
			return true
	return false


func _free_relic_slot() -> int:
	for i in RELIC_SLOTS:
		if _relics[i] == null:
			return i
	return -1


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
			KEY_ESCAPE:
				_pin_kind = ""
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
	if FORECAST_RECT.has_point(mp):
		_toggle_pin("forecast", 0)
		return
	for i in RELIC_SLOTS:
		if _relic_rect(i).has_point(mp) and _relics[i] != null:
			_toggle_pin("relic", i)
			return
	var bi: int = _boss_at(mp)
	if bi >= 0:
		_toggle_pin("boss", bi)
		return
	_pin_kind = ""
	_pin_idx = -1


func _release(mp: Vector2) -> void:
	var kind: String = _drag_kind
	var from: int = _drag_from
	var moved: bool = _drag_moved
	_drag_kind = ""
	_drag_from = -1
	_drag_moved = false
	if kind == "":
		return

	# 제자리 클릭 = 상세 고정(핀). 실시간이라 "읽으려면 클릭"은 무겁고, 클릭은 고정 용도다
	if not moved:
		_toggle_pin(kind, from)
		return

	if kind == "cell":
		var to: int = _cell_at(mp)
		if to >= 0 and to != from:
			var tmp = _cells[to]                    # 재배치는 즉시·무료 (미결 항목의 한쪽 극단)
			_cells[to] = _cells[from]
			_cells[from] = tmp
		return

	# 매대에서 끌어온 것 — 결제는 드롭 순간에만 이루어진다
	if _shop[from] == null:
		return
	var card: Dictionary = _shop[from]
	var price: int = int(card["price"])
	if _gold < price:
		return

	if card["kind"] == "unit":
		var to2: int = _cell_at(mp)
		if to2 < 0:
			return                                  # 무효한 곳에 놓으면 취소·무과금
		_cells[to2] = _make_squad(card["def"])      # 칸이 차 있으면 교체 — 벤치가 없으니 이게 성장이다
	else:
		var slot: int = _relic_at(mp)
		if slot < 0:
			return                                  # 유물은 유물 슬롯 줄에만 놓인다
		if _has_relic(str(card["def"]["id"])):
			return                                  # 같은 유물을 두 번 갖지 않는다
		_relics[slot] = card["def"]
		for sq in _cells:
			if sq != null:
				sq["relic_beats"][str(card["def"]["id"])] = 0
	_gold -= price
	_shop[from] = null                              # 구매한 슬롯은 다음 갱신까지 빈 채로 둔다


func _toggle_pin(kind: String, idx: int) -> void:
	if _pin_kind == kind and _pin_idx == idx:
		_pin_kind = ""
		_pin_idx = -1
	else:
		_pin_kind = kind
		_pin_idx = idx


func _cell_at(mp: Vector2) -> int:
	for i in 9:
		if _cell_rect(i).has_point(mp):
			return i
	return -1


func _relic_at(mp: Vector2) -> int:
	for i in RELIC_SLOTS:
		if _relic_rect(i).has_point(mp):
			return i if _relics[i] == null else _free_relic_slot()
	return -1


# ─── 히트박스 ─────────────────────────────────────────────────────────────
func _cell_rect(idx: int) -> Rect2:
	return Rect2(GRID_ORIGIN + Vector2(float(idx % 3) * CELL, float(idx / 3) * CELL),
		Vector2(CELL - CELL_PAD, CELL - CELL_PAD))


func _card_rect(idx: int) -> Rect2:
	return Rect2(SHOP_ORIGIN + Vector2(float(idx) * (CARD.x + CARD_GAP), 0.0), CARD)


func _relic_rect(idx: int) -> Rect2:
	return Rect2(RELICROW_ORIGIN + Vector2(float(idx) * (RELIC_SLOT.x + RELIC_GAP), 0.0), RELIC_SLOT)


# 보스는 배열 인덱스가 아니라 스케줄 번호로 가리킨다 — 앞 보스가 죽으면 배열이 밀리기 때문이다
func _boss_rect(b: Dictionary) -> Rect2:
	return Rect2(float(b["x"]) - 76.0, float(b["lane_y"]) - 140.0, 152.0, 240.0)


func _boss_at(mp: Vector2) -> int:
	for b in _bosses:
		if b["dead"]:
			continue
		if _boss_rect(b).has_point(mp):
			return int(b["index"])
	return -1


func _boss_by_index(n: int):
	for b in _bosses:
		if not b["dead"] and int(b["index"]) == n:
			return b
	return null


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
		var casts: bool = bool(JOBS[d["job"]]["cast"])
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
			# 애니 한 바퀴 ≈ 박자 한 번. 칸마다 리듬이 달라 직업이 박자로 식별된다.
			if running:
				var anim: StringName = &"spell" if casts else &"attack"
				_play(s, anim)
				var fc: float = maxf(1.0, float(f.get_frame_count(s.animation)))
				s.speed_scale = _speed * clampf(fc / (float(sq["period"]) * 12.0), 0.4, 2.4)
				# 연출만 몇 프레임씩 어긋낸다 — 판정은 동시지만 화면에서는 흩어져야 무리로 읽힌다
				if s.frame == 0 and m > 0 and s.frame_progress < 0.02:
					s.frame_progress = fmod(float(m) * 0.17, 1.0)
			else:
				s.speed_scale = 1.0
				_play(s, &"idle")
			var glow: float = maxf(float(sq["flash"]), float(sq["cast_flash"]))
			s.modulate = Color.WHITE.lerp(Color(1.6, 1.5, 1.2), glow * 0.30)

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
			if float(b["stun"]) > 0.0:
				_play(bs, &"idle")
			elif float(b["x"]) > BOSS_STOP_X:
				_play(bs, &"walk")
			else:
				_play(bs, &"attack")
			var tint: Color = Color.WHITE
			if b == target:
				tint = Color(1.15, 1.10, 1.05)
			tint = tint.lerp(Color(1.8, 0.6, 0.6), float(b["flash"]) * 0.5)
			if int(b["burn"]) > 0:
				tint = tint.lerp(Color(1.7, 0.7, 0.4), 0.35)
			if int(b["pois"]) > 0:
				tint = tint.lerp(Color(0.7, 1.4, 0.6), 0.30)
			if float(b["chill"]) > 0.0:
				tint = tint.lerp(Color(0.7, 0.9, 1.6), 0.35)
			if float(b["stun"]) > 0.0:
				tint = tint.lerp(Color(1.5, 1.4, 0.7), 0.45)
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
		var fl: float = maxf(float(sq["flash"]), float(sq["cast_flash"]))
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
	if card["kind"] == "relic":
		return card["def"]["color"]
	return JOBS[card["def"]["job"]]["color"]


# ─── 그리기: 오버레이 (스프라이트 위) ─────────────────────────────────────
func _draw_overlay() -> void:
	_resolve_detail()          # 칸·보스가 "지금 보고 있는 것"에 테두리를 치므로 먼저 정한다
	_draw_top_hud()
	_draw_forecast()
	_draw_cells_hud()
	_draw_bosses_hud()
	_draw_shop_text()
	_draw_relic_row()
	_draw_side_panels()
	if _detail_kind == "":
		_draw_stats_panel()    # 카드가 없을 때만 측정 패널이 보인다 — 자리를 나눠 쓴다
	else:
		_draw_detail_card()
	_draw_hint()
	_draw_drag()
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

	var mode: String = "고정 스케줄" if _spawn_mode == SpawnMode.FIXED else "킬 연동"
	_txt(_font_s, Vector2(1500.0, 34.0), "스폰 %s  [S]" % mode, 20, Color(0.58, 0.62, 0.70))
	_txt(_font_s, Vector2(1500.0, 60.0), "속도 %.0fx  [Z][X][C]   [Space] 정지   [R] 재시작" % _speed,
		20, Color(0.58, 0.62, 0.70))

	# 예고 슬롯이 다음 한 마리를 크게 알린다. 그 뒤로 오는 것들은 줄로만 둔다.
	var qx: float = 56.0
	_txt(_font_s, Vector2(qx, 100.0), "그 다음", 20, Color(0.50, 0.53, 0.60))
	qx += 90.0
	for i in range(_next_spawn + 1, mini(_schedule.size(), _next_spawn + 6)):
		var e: Dictionary = _schedule[i]
		var a: Dictionary = e["arch"]
		var tint: Color = a["tint"]
		_overlay.draw_rect(Rect2(qx, 84.0, 150.0, 26.0), tint.darkened(0.72))
		_txt(_font_s, Vector2(qx + 8.0, 104.0),
			"%s %.0fs" % [a["name"], maxf(0.0, float(e["at"]) - _elapsed)], 19, tint)
		qx += 160.0


# 예고 슬롯 — 다음 보스의 정체와 남은 시간. 상세는 호버로 편다(매대와 같은 문법).
func _draw_forecast() -> void:
	var r: Rect2 = FORECAST_RECT
	_overlay.draw_rect(r, Color(0.08, 0.085, 0.11, 0.92))
	if _next_spawn >= _schedule.size():
		_overlay.draw_rect(r, Color(0.30, 0.32, 0.38), false, 2.0)
		_txt(_font_s, r.position + Vector2(14.0, 34.0), "예고 — 남은 보스 없음", 19,
			Color(0.55, 0.58, 0.66))
		return
	var e: Dictionary = _schedule[_next_spawn]
	var a: Dictionary = e["arch"]
	var tint: Color = a["tint"]
	var left: float = maxf(0.0, _spawn_due() - _elapsed)
	_overlay.draw_rect(r, tint.darkened(0.35), false, 2.0)
	_txt(_font_s, r.position + Vector2(12.0, 24.0), "예고", 18, Color(0.60, 0.63, 0.70))
	_txt(_font_b, r.position + Vector2(12.0, 54.0), "%s #%d" % [str(a["name"]), _next_spawn + 1], 26, tint)
	_txt(_font_b, r.position + Vector2(r.size.x - 82.0, 54.0), "%.0fs" % left, 26,
		Color(0.95, 0.82, 0.45) if left > 5.0 else Color(1.0, 0.50, 0.44))
	# 태그 — 예고·구매·식별에서 같은 단어가 그대로 읽혀야 한다
	_txtw(_font_s, r.position + Vector2(12.0, 80.0), " · ".join(_entry_tags(e)), 19,
		Color(0.82, 0.86, 0.94), r.size.x - 24.0)
	_bar(Rect2(r.position + Vector2(12.0, 92.0), Vector2(r.size.x - 24.0, 6.0)),
		1.0 - clampf(left / 12.0, 0.0, 1.0), tint, Color(0.18, 0.18, 0.22))


# 칸 위에는 **이름만** 둔다. 스펙(체급·타격당 딜·통함 여부·축복)은 전부 상세 카드로 갔다.
# 아홉 칸이 동시에 도는 화면에서 칸마다 네댓 줄이 떠 있으면 무리 실루엣이 글자에 파묻힌다.
# 글자가 아닌 것 — 기여 막대와 유물 게이지 — 은 남긴다. 읽는 데 시간이 들지 않기 때문이다.
func _draw_cells_hud() -> void:
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
		# 글자가 무리 실루엣 위에 얹히므로 띠를 깔아 대비를 만든다
		_overlay.draw_rect(Rect2(r.position + Vector2(2.0, 2.0), Vector2(r.size.x - 4.0, 30.0)),
			Color(0.04, 0.04, 0.06, 0.55))
		_txtw(_font, r.position + Vector2(7.0, 24.0), str(sq["def"]["name"]), 20,
			Color(0.96, 0.96, 0.99), r.size.x - 14.0)

		# 칸별 기여 — 왜 이겼는지 항상 알 수 있어야 한다. 숫자는 카드에, 여기는 막대만
		if float(sq["dmg"]) > 0.0:
			var share: float = float(sq["dmg"]) / maxf(1.0, total_dmg)
			_overlay.draw_rect(Rect2(r.position + Vector2(6.0, r.size.y - 8.0),
				Vector2(r.size.x - 12.0, 5.0)), Color(0.16, 0.15, 0.12))
			_overlay.draw_rect(Rect2(r.position + Vector2(6.0, r.size.y - 8.0),
				Vector2((r.size.x - 12.0) * share, 5.0)), Color(1.0, 0.85, 0.45))

		# 이 칸에 실려 나가는 유물 — [직업] 태그가 맞는 것만
		_draw_cell_relics(r, sq)

		# 상세 카드를 보고 있는 칸은 테두리로 알린다
		if _detail_kind == "cell" and _detail_idx == i:
			_overlay.draw_rect(r, Color(0.95, 0.95, 1.0, 0.85), false, 3.0)


func _draw_cell_relics(r: Rect2, sq: Dictionary) -> void:
	var x: float = r.size.x - 34.0
	for rel in _relics:
		if rel == null or str(rel["job"]) != str(sq["def"]["job"]):
			continue
		var got: int = int(sq["relic_beats"].get(str(rel["id"]), 0))
		var prog: float = clampf(float(got) / float(rel["beats"]), 0.0, 1.0)
		var ir := Rect2(r.position + Vector2(x, 36.0), Vector2(26.0, 8.0))
		_overlay.draw_rect(ir, Color(0.15, 0.15, 0.19))
		_overlay.draw_rect(Rect2(ir.position, Vector2(ir.size.x * prog, ir.size.y)), rel["color"])
		x -= 30.0
	if float(sq["relic_flash"]) > 0.0:
		_overlay.draw_rect(r, Color(1.0, 1.0, 1.0, float(sq["relic_flash"]) * 0.30), false, 4.0)


func _res_line(b: Dictionary) -> String:
	var parts: Array = []
	for e in ELEM_ORDER:
		parts.append("%s%d" % [str(ELEMENTS[e]["short"]), int(round(float(b["res"][e]) * 100.0))])
	return " ".join(parts)


# 보스 위에도 **이름과 접두사만** 둔다 — 디아블로의 "질주 · 냉기 저항 · 재생"처럼.
# 방어력·저항 수치와 걸린 상태이상은 상세 카드로 갔다. 남는 것은 글자가 아닌 정보다:
# HP 막대, 성벽까지 남은 시간(초읽기), 그리고 스프라이트 틴트가 알리는 상태.
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
		_txt(_font, Vector2(bar.position.x, bar.position.y - 30.0),
			"%s #%d" % [a["name"], int(b["index"]) + 1], 21, tint)
		_txtw(_font_s, Vector2(bar.position.x, bar.position.y - 8.0),
			" · ".join(b["tags"]), 17, Color(0.88, 0.90, 0.96), 260.0)

		# 성벽 도달까지 — 초읽기가 판단거리이려면 남은 여유가 보여야 한다
		if float(b["stun"]) > 0.0:
			_txt(_font_b, Vector2(x - 32.0, y + 112.0), "스턴", 24, Color(1.0, 0.95, 0.55))
		elif x > BOSS_STOP_X:
			var spd: float = float(b["speed"]) * (CHILL_MOVE if float(b["chill"]) > 0.0 else 1.0)
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

		# 상세 카드를 보고 있는 보스는 테두리로 알린다
		if _detail_kind == "boss" and _detail_idx == int(b["index"]):
			_overlay.draw_rect(_boss_rect(b), Color(0.92, 0.94, 1.0, 0.32), false, 2.0)


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
			_draw_unit_card(r, card["def"], col, afford, target)
		else:
			_draw_relic_card(r, card["def"], col, afford)
		_txt(_font_b, r.position + Vector2(10.0, r.size.y - 14.0), "%dG" % int(card["price"]), 24,
			Color(1.0, 0.88, 0.45) if afford else Color(0.60, 0.42, 0.35))


func _draw_unit_card(r: Rect2, d: Dictionary, col: Color, afford: bool, target) -> void:
	var job: Dictionary = JOBS[d["job"]]
	_txt(_font, r.position + Vector2(10.0, 28.0), str(d["name"]), 21,
		Color(0.97, 0.97, 1.0) if afford else Color(0.55, 0.55, 0.60))
	_txt(_font_s, r.position + Vector2(10.0, 50.0),
		"%s · %s T%d" % [str(d["race"]), str(job["name"]), int(d["tier"])], 17, col)
	var beat_label: String = "캐스팅 %.2fs" % float(job["period"]) if bool(job["cast"]) \
		else "박자 %.2fs" % float(job["period"])
	_txt(_font_s, r.position + Vector2(10.0, 72.0),
		"%d명 · %s" % [int(d["members"]), beat_label], 17, Color(0.70, 0.73, 0.80))

	if str(d["job"]) == "cleric":
		_txt(_font_s, r.position + Vector2(10.0, r.size.y - 48.0),
			"인접 칸에 타격당 +%.1f" % float(d["bless"]), 17, Color(0.95, 0.88, 0.55))
		_txt(_font_s, r.position + Vector2(10.0, r.size.y - 30.0),
			"캐스팅마다 다시 건다", 17, Color(0.70, 0.73, 0.80))
		return
	if str(job["atk"]) == "phys":
		var per: float = float(d["power"]) / float(d["members"])
		var one: float = _phys_damage(per, target)
		var ok: bool = one > 0.0
		var chip := Rect2(r.position + Vector2(10.0, r.size.y - 74.0), Vector2(56.0, 20.0))
		if target == null:
			_overlay.draw_rect(chip, Color(0.20, 0.21, 0.26))
			_txt(_font_s, chip.position + Vector2(22.0, 16.0), "—", 16, Color(0.62, 0.65, 0.72))
		else:
			_overlay.draw_rect(chip, Color(0.18, 0.45, 0.24) if ok else Color(0.52, 0.14, 0.16))
			_txt(_font_s, chip.position + Vector2(7.0, 16.0), "통함" if ok else "딜 0", 16,
				Color(0.75, 1.0, 0.80) if ok else Color(1.0, 0.70, 0.68))
		var per_txt: String = "타격당 %.1f" % per
		if target != null:
			per_txt = "%.1f - 방 %.0f" % [per, _armor_now(target)]
		_txtw(_font_s, r.position + Vector2(74.0, r.size.y - 58.0), per_txt, 17,
			Color(0.82, 0.86, 0.92), CARD.x - 84.0)
		if target != null:
			_txtw(_font_s, r.position + Vector2(10.0, r.size.y - 38.0),
				"초당 %.0f" % (one * float(d["members"]) / float(job["period"])), 17,
				Color(0.70, 0.73, 0.80) if ok else Color(1.0, 0.66, 0.62), CARD.x - 20.0)
		return
	var elem: String = str(d["elem"])
	var rs: float = _res_now(target, elem)
	var out: float = _mag_damage(float(d["power"]), elem, target)
	var ecol: Color = ELEMENTS[elem]["color"]
	var chip2 := Rect2(r.position + Vector2(10.0, r.size.y - 74.0), Vector2(74.0, 20.0))
	_overlay.draw_rect(chip2, ecol.darkened(0.55))
	_txt(_font_s, chip2.position + Vector2(6.0, 16.0),
		"%s %d%%" % [str(ELEMENTS[elem]["name"]), int(round(rs * 100.0))], 16, ecol)
	_txtw(_font_s, r.position + Vector2(94.0, r.size.y - 58.0),
		"%.0f → %.0f" % [float(d["power"]), out], 17, Color(0.82, 0.86, 0.92), CARD.x - 104.0)
	_txtw(_font_s, r.position + Vector2(10.0, r.size.y - 38.0),
		"초당 %.0f · 인원 무관" % (out / float(job["period"])), 17,
		Color(0.70, 0.73, 0.80) if rs < 0.5 else Color(1.0, 0.72, 0.66), CARD.x - 20.0)


func _draw_relic_card(r: Rect2, it: Dictionary, col: Color, afford: bool) -> void:
	_txt(_font, r.position + Vector2(10.0, 28.0), str(it["name"]), 21,
		Color(0.97, 0.97, 1.0) if afford else Color(0.55, 0.55, 0.60))
	_txt(_font_s, r.position + Vector2(10.0, 50.0), "유물 · %d박자" % int(it["beats"]), 17, col)
	# [직업] 태그가 수행 주체를 정한다 — 그 직업이 없으면 살 수는 있어도 나가지 않는다
	var jname: String = str(JOBS[it["job"]]["name"])
	var have: int = _relic_count(str(it["job"]))
	_txt(_font_s, r.position + Vector2(10.0, 72.0), "[%s]  보유 %d칸" % [jname, have], 17,
		Color(0.85, 0.90, 0.98) if have > 0 else Color(1.0, 0.66, 0.60))
	_txtw(_font, r.position + Vector2(10.0, 116.0), str(it["short"]), 20, col, CARD.x - 20.0)
	if _has_relic(str(it["id"])):
		_txt(_font_s, r.position + Vector2(10.0, 156.0), "이미 보유", 18, Color(1.0, 0.70, 0.62))
	else:
		_txt(_font_s, r.position + Vector2(10.0, 156.0), "유물 슬롯 줄에", 18, Color(0.66, 0.68, 0.75))
		_txt(_font_s, r.position + Vector2(10.0, 178.0), "끌어다 놓는다", 18, Color(0.66, 0.68, 0.75))


func _draw_relic_row() -> void:
	for i in RELIC_SLOTS:
		var r: Rect2 = _relic_rect(i)
		var rel = _relics[i]
		if rel == null:
			_overlay.draw_rect(r, Color(0.10, 0.105, 0.13))
			_overlay.draw_rect(r, Color(0.22, 0.23, 0.28), false, 2.0)
			_txt(_font_s, r.position + Vector2(46.0, 34.0), "빈 슬롯", 18, Color(0.34, 0.36, 0.42))
			continue
		var col: Color = rel["color"]
		var jname: String = str(JOBS[rel["job"]]["name"])
		var live: int = 0
		for sq in _cells:
			if sq != null and str(sq["def"]["job"]) == str(rel["job"]):
				live += 1
		_overlay.draw_rect(r, col.darkened(0.78))
		_overlay.draw_rect(r, col.darkened(0.15 if live > 0 else 0.65), false, 2.0)
		_txt(_font, r.position + Vector2(8.0, 24.0), str(rel["name"]), 19, Color(0.96, 0.96, 1.0))
		_txt(_font_s, r.position + Vector2(8.0, 46.0), "[%s] %d칸" % [jname, live], 17,
			col if live > 0 else Color(1.0, 0.66, 0.60))


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


# 측정 패널 — 상세 카드와 자리를 나눠 쓴다. 카드가 뜨면 가려진다
func _draw_stats_panel() -> void:
	_overlay.draw_rect(STATS_RECT, Color(0.11, 0.12, 0.15))
	_overlay.draw_rect(STATS_RECT, Color(0.28, 0.30, 0.36), false, 2.0)
	var p: Vector2 = STATS_RECT.position
	_txt(_font_b, p + Vector2(14.0, 34.0), "측정", 22, Color(0.80, 0.84, 0.92))
	_txt(_font_s, p + Vector2(14.0, 62.0), "평균 처치 소요  %.1fs" % _avg_kill(), 18,
		Color(0.72, 0.76, 0.84))
	_txt(_font_s, p + Vector2(14.0, 86.0), "마지막 처치     %.1fs" %
		(float(_log_kill_times[-1]) if not _log_kill_times.is_empty() else 0.0), 18,
		Color(0.72, 0.76, 0.84))
	_txt(_font_s, p + Vector2(14.0, 110.0), "최대 겹침       %d마리" % _log_overlap_peak, 18,
		Color(0.72, 0.76, 0.84))
	_txt(_font_s, p + Vector2(14.0, 134.0), "성벽 총 손실    %d" % int(_log_wall_lost), 18,
		Color(0.72, 0.76, 0.84))
	var zero: float = _zero_ratio()
	_txt(_font_s, p + Vector2(14.0, 158.0), "딜 0 타격 비율  %.0f%%" % zero, 18,
		Color(0.95, 0.72, 0.68) if zero > 30.0 else Color(0.72, 0.76, 0.84))
	_txt(_font_s, p + Vector2(14.0, 182.0), "물리 감산 손실  %.0f%%" % _phys_loss(), 18,
		Color(0.72, 0.76, 0.84))
	_txt(_font_s, p + Vector2(14.0, 206.0), "유물 발동       %d회" % _log_relic_fires, 18,
		Color(0.72, 0.76, 0.84))
	_txt(_font_s, p + Vector2(14.0, 230.0), "배치 %d/9 · 유물 %d/%d" %
		[_placed_count(), RELIC_SLOTS - _empty_relics(), RELIC_SLOTS], 18, Color(0.72, 0.76, 0.84))


func _avg_kill() -> float:
	if _log_kill_times.is_empty():
		return 0.0
	var s: float = 0.0
	for t in _log_kill_times:
		s += float(t)
	return s / float(_log_kill_times.size())


func _zero_ratio() -> float:
	if _log_total_hits <= 0:
		return 0.0
	return float(_log_zero_hits) / float(_log_total_hits) * 100.0


func _phys_loss() -> float:
	if _log_phys_raw <= 0.0:
		return 0.0
	return (1.0 - _log_phys_out / _log_phys_raw) * 100.0


func _placed_count() -> int:
	var n: int = 0
	for sq in _cells:
		if sq != null:
			n += 1
	return n


func _empty_relics() -> int:
	var n: int = 0
	for r in _relics:
		if r == null:
			n += 1
	return n


func _draw_hint() -> void:
	_txt(_font_s, Vector2(720.0, 996.0),
		"병사카드 → 칸 · 유물카드 → 유물 슬롯 줄 · 부대끼리 끌면 자리 교체(즉시·무료)",
		20, Color(0.48, 0.52, 0.60))
	_txt(_font_s, Vector2(720.0, 1022.0),
		"부대 · 보스 · 카드에 마우스를 올리면 오른쪽에 상세가 뜬다. 클릭하면 고정, [Esc] 해제",
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
		if not _valid_cell_drop(i):
			continue
		var cr: Rect2 = _cell_rect(i)
		_overlay.draw_rect(cr, Color(0.55, 0.85, 0.60, 0.16))
		_overlay.draw_rect(cr, Color(0.60, 0.95, 0.66, 0.75), false, 3.0)
	for i in RELIC_SLOTS:
		if not _valid_relic_drop(i):
			continue
		var rr2: Rect2 = _relic_rect(i)
		_overlay.draw_rect(rr2, Color(0.55, 0.85, 0.60, 0.16))
		_overlay.draw_rect(rr2, Color(0.60, 0.95, 0.66, 0.75), false, 3.0)


func _valid_cell_drop(cell_idx: int) -> bool:
	if _drag_kind == "cell":
		return cell_idx != _drag_from
	if _drag_kind != "shop":
		return false
	var card = _shop[_drag_from]
	if card == null or _gold < int(card["price"]):
		return false
	return card["kind"] == "unit"


func _valid_relic_drop(slot: int) -> bool:
	if _drag_kind != "shop":
		return false
	var card = _shop[_drag_from]
	if card == null or _gold < int(card["price"]) or card["kind"] != "relic":
		return false
	if _has_relic(str(card["def"]["id"])):
		return false
	return _relics[slot] == null


# 이번 프레임에 카드가 무엇을 보여줄지 정한다. 호버가 이기고, 호버가 없으면 고정된 것이 남는다.
# 그리기보다 먼저 불려야 한다 — 칸·보스가 "지금 보고 있는 것"에 테두리를 치기 때문이다.
func _resolve_detail() -> void:
	_detail_kind = ""
	_detail_idx = -1
	if _drag_kind == "":
		for i in SHOP_SLOTS:
			if _card_rect(i).has_point(_mouse) and _shop[i] != null:
				_detail_kind = "shop"
				_detail_idx = i
				return
		for i in 9:
			if _cell_rect(i).has_point(_mouse) and _cells[i] != null:
				_detail_kind = "cell"
				_detail_idx = i
				return
		for i in RELIC_SLOTS:
			if _relic_rect(i).has_point(_mouse) and _relics[i] != null:
				_detail_kind = "relic"
				_detail_idx = i
				return
		if FORECAST_RECT.has_point(_mouse):
			_detail_kind = "forecast"
			_detail_idx = 0
			return
		var bi: int = _boss_at(_mouse)
		if bi >= 0:
			_detail_kind = "boss"
			_detail_idx = bi
			return
	if _pin_kind != "" and _pin_alive(_pin_kind, _pin_idx):
		_detail_kind = _pin_kind
		_detail_idx = _pin_idx


# 고정해둔 대상이 사라졌을 수 있다 — 보스는 죽고, 카드는 팔리고, 칸은 교체된다
func _pin_alive(kind: String, idx: int) -> bool:
	match kind:
		"shop":
			return idx >= 0 and idx < SHOP_SLOTS and _shop[idx] != null
		"cell":
			return idx >= 0 and idx < 9 and _cells[idx] != null
		"relic":
			return idx >= 0 and idx < RELIC_SLOTS and _relics[idx] != null
		"boss":
			return _boss_by_index(idx) != null
		"forecast":
			return true
	return false


func _detail_view() -> Dictionary:
	match _detail_kind:
		"cell":
			return _view_cell(_detail_idx)
		"shop":
			return _view_shop(_shop[_detail_idx])
		"relic":
			return _view_relic(_relics[_detail_idx], true)
		"boss":
			return _view_boss(_boss_by_index(_detail_idx))
		"forecast":
			return _view_forecast()
	return {}


# 줄 앞의 표식으로 색을 정한다 — ">"는 강조(그 대상의 핵심 수치), "!"는 경고(딜 0 등)
func _draw_detail_card() -> void:
	if _detail_kind == "":
		return
	var view: Dictionary = _detail_view()
	if view.is_empty():
		return
	# 내용만큼만 자란다 — 빈 상자가 남으면 "뭔가 더 있나" 하고 읽게 된다
	var lines: Array = view["lines"]
	var r: Rect2 = DETAIL_RECT
	r.size.y = clampf(60.0 + float(lines.size()) * 21.0 + 10.0, 110.0, DETAIL_RECT.size.y)
	var col: Color = view["color"]
	_overlay.draw_rect(r, Color(0.085, 0.095, 0.125, 0.98))
	_overlay.draw_rect(r, col.lerp(Color(0.6, 0.63, 0.72), 0.35), false, 2.0)
	_overlay.draw_rect(Rect2(r.position, Vector2(r.size.x, 36.0)), col.darkened(0.60))
	_txtw(_font_b, r.position + Vector2(12.0, 26.0), str(view["title"]), 21,
		Color(0.98, 0.98, 1.0), r.size.x - 62.0)
	if _pin_kind == _detail_kind and _pin_idx == _detail_idx:
		_txt(_font_s, r.position + Vector2(r.size.x - 46.0, 25.0), "고정", 16,
			Color(1.0, 0.88, 0.45))

	var y: float = 60.0
	for raw in lines:
		var s: String = str(raw)
		var c: Color = Color(0.82, 0.85, 0.92)
		if s.begins_with("!"):
			s = s.substr(1)
			c = Color(1.0, 0.62, 0.58)
		elif s.begins_with(">"):
			s = s.substr(1)
			c = Color(1.0, 0.90, 0.58)
		elif s.begins_with("~"):
			s = s.substr(1)
			c = Color(0.60, 0.64, 0.72)
		_txtw(_font_s, r.position + Vector2(12.0, y), s, 17, c, r.size.x - 24.0)
		y += 21.0
		if y > r.size.y - 8.0:
			break


# 카드 폭이 298px이라 한 줄에 30자 남짓이다. 문장을 늘어놓지 않고 짧게 끊는다.
func _view_cell(idx: int) -> Dictionary:
	var sq: Dictionary = _cells[idx]
	var d: Dictionary = sq["def"]
	var job: Dictionary = JOBS[d["job"]]
	var target = _target_boss()
	var l: Array = []
	l.append("%s · %s T%d · %d명" % [str(d["race"]), str(job["name"]), int(d["tier"]),
		int(sq["members"])])
	l.append("~%s" % str(job["rhythm"]))
	if str(d["job"]) == "cleric":
		l.append("캐스팅 %.2fs" % float(sq["period"]))
		l.append(">인접 %d칸에 타격당 +%.1f" % [_neighbors(idx).size(), float(d["bless"])])
		l.append("~고정값이라 인원 많고 빠른")
		l.append("~부대 옆에서 크게 불어난다")
	elif str(job["atk"]) == "phys":
		l.append("박자 %.2fs · 한 박자에 %d회" % [float(sq["period"]), int(sq["members"])])
		if float(sq["bless"]) > 0.0:
			l.append(">타격당 %.1f  (기본 %.1f + 축복 %.1f)" %
				[_per_hit(sq), float(sq["power"]) / float(sq["members"]), float(sq["bless"])])
		else:
			l.append(">타격당 %.1f" % _per_hit(sq))
		if target == null:
			l.append("~레인에 보스가 없다")
		else:
			var one: float = _phys_damage(_per_hit(sq), target)
			var calc: String = "%.1f - 방 %.0f = %.1f" % [_per_hit(sq), _armor_now(target), one]
			if one <= 0.0:
				l.append("!" + calc)
				l.append("!이 보스에게 아무것도 못 한다")
			else:
				l.append(">" + calc)
				l.append("초당 %.0f" % (one * float(sq["members"]) / float(sq["period"])))
		if str(d["job"]) == "archer":
			l.append("스킬 %d%% ×%.1f — %d회 터짐" % [int(round(float(d["crit"]) * 100.0)),
				float(d["crit_mult"]), int(sq["crits"])])
	else:
		var e: String = str(d["elem"])
		l.append("캐스팅 %.2fs · 인원 무관" % float(sq["period"]))
		l.append(">%s %.0f" % [str(ELEMENTS[e]["name"]), float(sq["power"])])
		if target == null:
			l.append("~레인에 보스가 없다")
		else:
			l.append(">%s 저항 %d%% → %.0f" % [str(ELEMENTS[e]["name"]),
				int(round(_res_now(target, e) * 100.0)),
				_mag_damage(float(sq["power"]), e, target)])
			l.append("초당 %.0f" % (_mag_damage(float(sq["power"]), e, target) /
				float(sq["period"])))
	l.append("누적 %d · %d타" % [int(sq["dmg"]), int(sq["hits"])])
	for rel in _relics:
		if rel == null or str(rel["job"]) != str(d["job"]):
			continue
		l.append("%s %d/%d박자" % [str(rel["name"]),
			int(sq["relic_beats"].get(str(rel["id"]), 0)), int(rel["beats"])])
	return {"title": str(d["name"]), "color": Color(job["color"]), "lines": l}


func _view_shop(card) -> Dictionary:
	if card == null:
		return {}
	if card["kind"] == "relic":
		var v: Dictionary = _view_relic(card["def"], false)
		(v["lines"] as Array).append(">%dG" % int(card["price"]))
		return v
	var d: Dictionary = card["def"]
	var job: Dictionary = JOBS[d["job"]]
	var target = _target_boss()
	var l: Array = []
	l.append("%s · %s T%d · %d명" % [str(d["race"]), str(job["name"]), int(d["tier"]),
		int(d["members"])])
	l.append("~%s" % str(job["rhythm"]))
	if str(d["job"]) == "cleric":
		l.append("캐스팅 %.2fs" % float(job["period"]))
		l.append(">인접 칸에 타격당 +%.1f" % float(d["bless"]))
		l.append("~인원 많고 빠른 부대 옆이 좋다")
	elif str(job["atk"]) == "phys":
		var per: float = float(d["power"]) / float(d["members"])
		l.append("박자 %.2fs · 한 박자에 %d회" % [float(job["period"]), int(d["members"])])
		l.append(">타격당 %.1f  (공격력 %.0f ÷ %d명)" % [per, float(d["power"]),
			int(d["members"])])
		if target == null:
			l.append("~레인에 보스가 없다")
		else:
			var one: float = _phys_damage(per, target)
			if one <= 0.0:
				l.append("!%.1f - 방 %.0f = 0 — 안 통한다" % [per, _armor_now(target)])
			else:
				l.append(">%.1f - 방 %.0f = %.1f · 초당 %.0f" % [per, _armor_now(target), one,
					one * float(d["members"]) / float(job["period"])])
		if str(d["job"]) == "archer":
			l.append("스킬 %d%% 확률 ×%.1f" % [int(round(float(d["crit"]) * 100.0)),
				float(d["crit_mult"])])
			l.append("~인원이 많을수록 자주 터진다")
	else:
		var e: String = str(d["elem"])
		l.append("캐스팅 %.2fs · 인원 무관" % float(job["period"]))
		l.append(">%s %.0f" % [str(ELEMENTS[e]["name"]), float(d["power"])])
		if target != null:
			l.append(">저항 %d%% → %.0f · 초당 %.0f" % [
				int(round(_res_now(target, e) * 100.0)),
				_mag_damage(float(d["power"]), e, target),
				_mag_damage(float(d["power"]), e, target) / float(job["period"])])
		l.append("~저항 상한 %d%% — 완전 면역은 없다" % int(round(RES_CAP * 100.0)))
	l.append(">%dG" % int(card["price"]))
	return {"title": str(d["name"]), "color": Color(job["color"]), "lines": l}


func _view_relic(it: Dictionary, equipped: bool) -> Dictionary:
	var jname: String = str(JOBS[it["job"]]["name"])
	var l: Array = []
	l.append("유물 (동사) · [%s]" % jname)
	l.append(">%s" % str(it["short"]))
	l.append(str(it["desc"]))
	l.append("")
	l.append("%s 부대의 %d박자마다" % [jname, int(it["beats"])])
	l.append("자동으로 나간다 — 발동 버튼 없음")
	l.append("~효과량은 그 부대의 타격당 딜에")
	l.append("~비례한다. 다수는 잦고 작게,")
	l.append("~소수정예는 드물고 크게")
	var live: int = 0
	for sq in _cells:
		if sq != null and str(sq["def"]["job"]) == str(it["job"]):
			live += 1
	if equipped or live == 0:
		l.append(("%s 부대 %d칸" % [jname, live]) if live > 0 else
			("!%s 부대가 없다 — 나가지 않는다" % jname))
	return {"title": str(it["name"]), "color": Color(it["color"]), "lines": l}


func _view_boss(b) -> Dictionary:
	if b == null:
		return {}
	var a: Dictionary = b["arch"]
	var l: Array = []
	l.append(">%s" % " · ".join(b["tags"]))
	l.append("체력 %d / %d" % [int(b["hp"]), int(b["hp_max"])])
	if float(b["shred"]) > 0.0:
		l.append(">방어력 %.0f  (파쇄 -%.0f)" % [_armor_now(b), float(b["shred"])])
	else:
		l.append("방어력 %.0f" % _armor_now(b))
	l.append(_res_line(b))
	l.append("전진 %.0f%s" % [float(b["speed"]),
		"  (빙결)" if float(b["chill"]) > 0.0 else ""])
	if float(b["regen"]) > 0.0:
		var rg: float = float(b["regen"]) * (BURN_REGEN_CUT if int(b["burn"]) > 0 else 1.0)
		l.append(">회복 %.0f/s%s" % [rg, "  (화상이 절반 깎음)" if int(b["burn"]) > 0 else ""])
	var st: Array = _boss_states(b)
	if st.is_empty():
		l.append("~걸린 상태이상 없음")
	else:
		l.append(">" + "  ".join(st))
	if float(b["x"]) > BOSS_STOP_X:
		var spd: float = float(b["speed"]) * (CHILL_MOVE if float(b["chill"]) > 0.0 else 1.0)
		l.append("성벽까지 %.1fs" % ((float(b["x"]) - BOSS_STOP_X) / maxf(1.0, spd)))
	else:
		l.append("!성벽 타격 중 — %.0f / %.1fs" % [float(b["wall_dmg"]),
			float(a["wall_int"])])
	l.append("~%s" % str(a["hint"]))
	return {"title": "%s #%d" % [str(a["name"]), int(b["index"]) + 1],
		"color": Color(a["tint"]), "lines": l}


func _view_forecast() -> Dictionary:
	if _next_spawn >= _schedule.size():
		return {"title": "예고", "color": Color(0.5, 0.53, 0.6),
			"lines": ["~남은 보스가 없다"]}
	var e: Dictionary = _schedule[_next_spawn]
	var a: Dictionary = e["arch"]
	var l: Array = []
	l.append(">%s" % " · ".join(_entry_tags(e)))
	l.append("%.0fs 뒤 등장" % maxf(0.0, _spawn_due() - _elapsed))
	l.append("")
	l.append("체력 %.0f" % float(e["hp"]))
	l.append("방어력 %.0f · 전진 %.0f" % [float(e["armor"]), float(a["speed"])])
	var parts: Array = []
	for el in ELEM_ORDER:
		parts.append("%s %d%%" % [str(ELEMENTS[el]["short"]),
			int(round(float(e["res"][el]) * 100.0))])
	l.append(" ".join(parts))
	l.append("")
	l.append("~%s" % str(a["hint"]))
	return {"title": "예고 — %s #%d" % [str(a["name"]), _next_spawn + 1],
		"color": Color(a["tint"]), "lines": l}


func _draw_end_panel() -> void:
	if _phase == Phase.RUNNING:
		return
	var panel := Rect2(560.0, 230.0, 800.0, 420.0)
	_overlay.draw_rect(panel, Color(0.10, 0.11, 0.15, 0.97))
	_overlay.draw_rect(panel, Color(0.55, 0.60, 0.72), false, 3.0)
	var win: bool = _phase == Phase.CLEAR
	_txt(_font_b, panel.position + Vector2(36.0, 74.0), "클리어" if win else "성벽 붕괴", 46,
		Color(0.60, 0.92, 0.66) if win else Color(0.94, 0.44, 0.42))
	var rows: Array = [
		"처치 %d / %d · 경과 %.1fs" % [_killed, RUN_BOSSES, _elapsed],
		"성벽 %d / %d (총 손실 %d)" % [int(_wall_hp), int(_wall_max), int(_log_wall_lost)],
		"평균 처치 소요 %.1fs · 최대 겹침 %d마리" % [_avg_kill(), _log_overlap_peak],
		"딜 0 타격 %.0f%% · 물리 감산 손실 %.0f%%" % [_zero_ratio(), _phys_loss()],
		"유물 발동 %d회 · 남은 골드 %d" % [_log_relic_fires, _gold],
	]
	var y: float = 140.0
	for r in rows:
		_txt(_font, panel.position + Vector2(36.0, y), str(r), 24, Color(0.86, 0.89, 0.95))
		y += 38.0
	_txt(_font_s, panel.position + Vector2(36.0, 390.0), "[R] 다시 시작", 20, Color(0.65, 0.70, 0.80))
