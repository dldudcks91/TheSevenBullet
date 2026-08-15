# PROTOTYPE - NOT FOR PRODUCTION
# Question: 체급 3단 + 병사카드 합류제 위에서 "매대-리롤" 판단이 성립하는가?
#           (부수 측정: 킬 속도가 여유 시간으로 환산되는가 /
#            감산·비율 두 공식이 "보스마다 답이 갈린다"를 실제로 만드는가)
# Date: 2026-08-14
#
# 기준 문서: docs/game_design/GAME_DESIGN.md — 실시간 로그라이크 TD.
# 넣은 것: 3×3(한 칸=한 부대) · 무정지 실시간 · 스폰 스케줄과 겹침 · 최근접 타게팅 ·
#          **체급 3단**(소형·중형·대형 — 타격당 딜을 고정하고 인원 상한을 정한다) ·
#          **병사카드 합류제**(카드마다 마릿수가 다르고, 같은 유닛 칸에 부어 상한까지 채운다) ·
#          물리 감산 / 마법 원소별 비율 / **명중 판정은 물리에만** · 원소 4종 ·
#          **직업 7종 리듬**(확률=전사·소드마스터 / 크리=궁수·암살자 / 캐스팅=마법사·사제) ·
#          **유닛 고유 스킬**(units.csv·skills.csv에서 읽는다 — 매대 풀 20종, effect 17종) ·
#          유물(전역 보유 · [직업] 태그 · 자동 발동 · **타격 수로 찬다**) · **상태이상 9종** ·
#          **적 = 베이스 + 접두사 굴림**(정예 8종 접두사 / 막보스는 고정 조합) · 4막 구조 ·
#          **보스의 병력 디버프**(주박) · 5슬롯 매대 + 드래그 구매 + 유료 리롤 ·
#          **킬은 매대를 갱신하지 않는다** · 시간 골드 ·
#          **병사카드 가격 = 마릿수 × 체급 단가** · 성벽 HP 지속 + 수리/업그레이드 ·
#          예고 슬롯 · 칸별 기여도
# 뺀 것:   리더(발동 방식 미결 — 풀에서 제외) · 사기(증감 규칙 미결) ·
#          전술카드(세 종류만 확정이고 등급·칸 수·효과 풀이 전부 미결) · 언락 · 밸런싱 ·
#          유닛 티어(기획에서 폐기) · 아군 상태이상 중 저주·저항감소(부여원이 아직 없다)
#
# 「미결」을 프로토가 임의로 고른 자리 (기획서에 적지 않는다):
#   - **빗나감 = 0.** 「빗나감이 0인가 약화된 타격인가」의 한쪽 극단을 태운다
#   - **빼낸 부대는 환불 없이 사라진다.** 「빼낸 부대의 처리」의 한쪽 극단
#   - **병사카드 마릿수 분포**는 체급별 고정 범위로 잡았다 (소형 2~4 / 중형 1~2 / 대형 1)
#
# 수치는 전부 임시값이다. src/data/ 의 CSV는 **읽기만** 하고, 미확정 수치는
# 아래 TUNE_UNITS / TUNE_SKILLS 에 모아둔다 — 이 폴더는 버리는 코드다.

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

# 하단 밴드 — 왼쪽부터 **리롤 · 매대 5장 · 성벽 패널 · 보유 슬롯 블록**. 쇼핑 동선이
# 하단 한 밴드 안에서 끝난다. 리롤이 맨 왼쪽인 것은 TFT와 같은 자리다 (3차 · 사용자 확정).
const REROLL_RECT := Rect2(56.0, 706.0, 120.0, 250.0)
const SHOP_ORIGIN := Vector2(190.0, 706.0)
const CARD := Vector2(196.0, 250.0)
const CARD_GAP := 14.0
const SHOP_SLOTS := 5

# 성벽 패널은 없다 (3차 · 사용자 확정). 성벽 자체가 구매처다 — 클릭 = 수리, 우클릭 = 최대 HP.
# 가격·회복량은 성벽 호버 상세에서만 보인다.
# 측정 패널은 프로토 전용 디버그다 — 정지 중에만 레인 위에 뜬다 (자리를 차지하지 않는다)
const STATS_RECT := Rect2(800.0, 240.0, 298.0, 250.0)
# 상세 카드는 고정 위치가 없다 — **호버한 대상 옆에 뜬다** (발라트로·StS·TFT의 인접 툴팁
# 문법 · 3차 사용자 확정). 위치는 _detail_rect_now() 가 대상별로 정하고 화면 안으로 클램프한다.
const DETAIL_SIZE := Vector2(298.0, 322.0)

# 보유 슬롯 블록 — 우측 하단 **정사각 5+5** (3차 · 사용자 확정). 보유물은 아이콘으로 압축하고
# 상세는 호버로 — 발라트로 소모품·StS 유물 줄과 같은 문법이다. 슬롯 5칸은 보유 상한의
# 실험값이다 (상한 수 자체는 「미결」 — 데이터).
# 슬롯이 하단 밴드(250px)를 **꽉 채운다** — 두 줄 118px가 매대 카드와 같은 무게로 선다.
# 줄 이름표(유물/전술)는 블록 왼쪽 세로 여백에 둔다.
const RELIC_SLOT := Vector2(118.0, 118.0)
const RELIC_GAP := 8.0
const RELIC_SLOTS := 5
const RELICROW_ORIGIN := Vector2(1290.0, 708.0)
const TACTICROW_ORIGIN := Vector2(1290.0, 834.0)

# 예고 슬롯 — 화면 구석. 다음 보스의 정체를 미리 알린다
const FORECAST_RECT := Rect2(1584.0, 190.0, 280.0, 112.0)

# ─── 밸런스 (전부 임시값) ──────────────────────────────────────────────────
# 유한 런이다 — 클리어가 있다. 4막 × (정예 2 + 막보스 1) = 12마리.
const RUN_BOSSES := 12
const WALL_HP_START := 500.0

const GOLD_START := 130
const KILL_GOLD_BASE := 30
const KILL_GOLD_STEP := 10
# 골드는 두 곳에서 나온다 — 시간이 바닥을 깔고, 킬이 템포를 보상한다.
# 시간 유입이 없으면 첫 몇 초에 다 쓰고 남은 시간엔 매대를 볼 이유가 사라진다.
const GOLD_PER_SEC := 3.0

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

# 병력 디버프(주박) — 적은 병력을 때리지 못하지만 성능은 떨어뜨린다. **일시적이고
# 런 전체에 누적되지 않는다.** 인원이 많은 부대일수록 덜 흔들린다(머릿수가 완충재).
const BIND_INTERVAL := 4.0            # 주박 보스가 디버프를 거는 주기
const BIND_AMOUNT := 0.45             # 단독 부대 기준 성능 감소율. 인원이 이걸 완충한다
const BIND_DURATION := 5.0

# 경화가 올릴 수 있는 방어력의 상한. 중형 타격당 딜(12~15) 하나를 닫을 만큼이고,
# 대형과 마법은 끝까지 살아 있다 — "장기전을 막는다"까지만 하고 판을 지우지는 않는다.
const HARDEN_CAP := 14.0

const CHILL_MOVE := 0.55              # 빙결 — 이동·공격속도에 곱해진다
# 화상은 **회복 감소만** 한다. 틱딜을 겸하면 중독과 하는 일이 같아져 원소가 넷인 이유가 흐려진다.
const BURN_DURATION := 6.0
const BURN_REGEN_CUT := 0.5           # 화상 — 회복 감소
const POISON_TICK := 3.0              # 중독 스택당 초당 지속딜
const POISON_DURATION := 7.0
const VULN_DURATION := 5.0
const SHRED_DURATION := 6.0
const RES_SHRED_DURATION := 6.0       # 저항 감소 — 원소별 4갈래
const CURSE_DURATION := 6.0           # 저주 — 아군 타격마다 고정 추가피해
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
const MAX_MEMBERS := 9                # 소형의 인원 상한
const MAX_BOSS_SPRITES := 8

# ─── 체급 — 소형 · 중형 · 대형 ────────────────────────────────────────────
# 체급 배정의 단일 출처는 sprite_catalog.csv 의 size_tier(실측 픽셀 크기)이고,
# 그 배정에 따른 **인원 상한**이 units.csv 의 crew 다. 둘 다 읽기만 한다.
#
#   cap   — 인원 상한. 부대는 병사카드를 부어 여기까지 자란다
#   hit   — **타격당 딜 배율.** cap 과 반비례한다(1:3:9 ↔ 9:3:1) —
#           상한까지 채운 부대의 총 화력이 체급이 달라도 같아지도록.
#           그래서 체급이 정하는 것은 "이 보스에게 통하는가"뿐이고,
#           "제때 잡는가"는 인원 × 주기가 답한다(기획 「체급과 화력은 직교한다」)
#   scale — 개체 크기. 정수배만 쓴다(기획 「프레젠테이션」). 상한이 클수록 하나하나가 작다
#   unit  — 마리당 단가. 대형은 딜 0이 잘 안 나는 안전 자산이라 프리미엄이 붙는다
const SIZES := {
	"small": {"name": "소형", "cap": 9, "hit": 1.0, "scale": 2, "unit": 5},
	"mid":   {"name": "중형", "cap": 3, "hit": 3.0, "scale": 3, "unit": 16},
	"large": {"name": "대형", "cap": 1, "hit": 9.0, "scale": 4, "unit": 54},
}
const SIZE_ORDER := ["small", "mid", "large"]
const SIZE_KO := {"소형": "small", "중형": "mid", "대형": "large", "초대형": "large"}

# 병사카드에 담기는 마릿수 — 체급별 범위. **분포는 「미결」이라 프로토가 임의로 잡은 값이다.**
# 소형은 여러 장을 부어야 차는 투자형, 대형은 한 장에 완성되는 즉전력이다.
const CARD_CREW := {"small": [2, 4], "mid": [1, 2], "large": [1, 1]}

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
# 직업은 "스킬이 언제 터지는가" = 리듬을 정한다. 발동은 세 유형뿐이라 외울 것이 직업 수보다 적다.
#   atk     — 평타의 피해 타입. "none"이면 평타가 없다
#   cast    — 평타를 포기하고 주기마다 큰 것을 내보낸다
#   trigger — 스킬이 터지는 조건. "chance"(평타마다 고정 확률) / "crit"(크리가 곧 발동) /
#             "cast"(캐스팅 자체가 발동) / "none"(발동 미결)
# 주기는 직업이 아니라 **유닛**이 갖는다 — 같은 직업 안에서 다수/소수정예가 갈려야 하기 때문이다.
#
# 리더는 발동이 리더별 개별이라 아직 「미결」이다. 매대 풀에서 통째로 뺐고,
# 여기 남긴 것은 로더가 CSV의 "리더" 행을 만났을 때 조용히 죽지 않게 하기 위해서다.
const JOBS := {
	"warrior":     {"name": "전사",      "atk": "phys", "cast": false, "trigger": "chance",
	 "rhythm": "평타마다 확률 발동 — 자신을 강화", "color": Color(0.88, 0.42, 0.34)},
	"swordmaster": {"name": "소드마스터", "atk": "phys", "cast": false, "trigger": "chance",
	 "rhythm": "평타마다 확률 발동 — 적을 벤다", "color": Color(0.94, 0.62, 0.30)},
	"archer":      {"name": "궁수",      "atk": "phys", "cast": false, "trigger": "crit",
	 "rhythm": "크리티컬이 발동 — 다수라 리듬이 된다", "color": Color(0.45, 0.78, 0.46)},
	"assassin":    {"name": "암살자",    "atk": "phys", "cast": false, "trigger": "crit",
	 "rhythm": "크리티컬이 발동 — 소수라 잭팟이 된다", "color": Color(0.62, 0.84, 0.78)},
	"mage":        {"name": "마법사",    "atk": "none", "cast": true,  "trigger": "cast",
	 "rhythm": "캐스팅 — 보스에게", "color": Color(0.46, 0.52, 0.94)},
	"cleric":      {"name": "사제",      "atk": "none", "cast": true,  "trigger": "cast",
	 "rhythm": "캐스팅 — 아군에게", "color": Color(0.95, 0.86, 0.48)},
	"leader":      {"name": "리더",      "atk": "phys", "cast": false, "trigger": "none",
	 "rhythm": "리더별 개별 — 발동 미결", "color": Color(0.80, 0.78, 0.86)},
}

# 크리는 궁수·암살자만 갖는 **스탯**이다 (기본 0%, 나머지 직업은 공급원이 있어야만 생긴다).
# 궁수는 자주·얕게, 암살자는 드물게·깊게 — 같은 "크리가 곧 발동"인데 체감이 갈린다.
const CRIT_BASE := {"archer": 0.25, "assassin": 0.12}
const CRIT_MULT_BASE := {"archer": 2.2, "assassin": 3.2}

const BLESS_HOLD := 1.7               # 축복 지속 = 사제 캐스팅 주기 × 이 값 (끊기지 않게)

# ─── 데이터 ───────────────────────────────────────────────────────────────
# 로스터·스킬 구성은 src/data 의 CSV가 단일 출처다. **읽기만 한다.**
# .import 가 importer="keep" 이라 FileAccess 로 원문이 그대로 열린다.
const DATA_ROOT := "res://src/data"

# CSV의 한글 리터럴 → 내부 코드. i18n 마이그레이션이 실제로 돌면 **여기만** 고치면 된다.
const JOB_KO := {
	"전사": "warrior", "소드마스터": "swordmaster", "궁수": "archer",
	"암살자": "assassin", "마법사": "mage", "사제": "cleric", "리더": "leader",
}
const ELEM_KO := {"냉기": "cold", "화염": "fire", "독": "poison", "번개": "shock", "랜덤": "random"}

# ─── 임시 수치 ────────────────────────────────────────────────────────────
# CSV의 attack_period·attack_power·스킬 수치 칸은 아직 비어 있다. 확정될 때까지 여기서
# 잡는다 — CSV를 건드리지 않고 프로토만 굴리기 위한 자리다.
# **crew(인원 상한)는 여기 없다.** units.csv 의 crew 가 확정 데이터라 그쪽을 읽는다.
#
# period — 평타 주기. 캐스팅 직업은 TUNE_SKILLS 의 cast_time 이 대신한다
# might  — **유닛의 화력 눈금.** 체급 프로필이 걸리기 전의 값이다.
#          타격당 딜 = might × SIZES[체급].hit  →  체급이 정하는 것은 "이 보스에게 통하는가"뿐.
#          총 화력 = 인원 × 타격당 딜 ÷ 주기  →  "제때 잡는가"는 인원과 주기가 답한다.
#          hit 이 cap 과 반비례하므로 **상한까지 채운 부대의 총 화력은 체급이 달라도 같다.**
#          캐스팅 직업에서는 시전당 딜(마법사)·축복량(사제)이 같은 규칙을 탄다 —
#          인원수가 곧 시전 횟수다(기획 「인원이 하는 일」).
const TUNE_UNITS := {
	# 전사 — 근접 물리. 확률 발동으로 자신을 강화한다
	"U_VK_BERSERKER":   {"period": 0.90, "might": 4.8},   # 중형
	"U_DM_HIGH":        {"period": 1.40, "might": 5.6},   # 대형 — 풀에 하나뿐인 관통 프로필
	# 소드마스터 — 근접 물리. 확률 발동으로 적을 벤다
	"U_DE_SWORD":       {"period": 0.95, "might": 4.6},   # 중형
	"U_UD_DREADKNIGHT": {"period": 1.10, "might": 5.0},   # 소형
	# 궁수 — 크리가 리듬. 인원이 많을수록 한 박자에 여러 번 굴린다
	"U_HUM_ARCHER":     {"period": 0.55, "might": 3.8},   # 소형
	"U_UD_SKELARCHER":  {"period": 0.58, "might": 3.9},   # 소형
	"U_DE_ARCHER":      {"period": 0.60, "might": 4.0},   # 중형
	"U_DM_FIREIMP":     {"period": 0.70, "might": 4.4},   # 소형
	# 암살자 — 크리가 잭팟
	"U_DE_ASSASSIN":    {"period": 0.85, "might": 4.2},   # 중형
	"U_BM_CAT":         {"period": 0.80, "might": 3.9},   # 중형
	"U_UD_REAPER":      {"period": 1.20, "might": 5.2},   # 중형
	# 마법사 — 평타 없음. 주기는 cast_time, 시전당 딜은 might × 체급 hit
	"U_HUM_MAGE":       {"period": 0.0, "might": 11.0},   # 소형
	"U_DE_WIZARD":      {"period": 0.0, "might": 8.5},   # 중형 — 독은 낮게 잡고 상태이상을 싣는 결
	"U_UD_LICH":        {"period": 0.0, "might": 8.0},   # 중형 — 냉기. 빙결을 함께 싣는다
	"U_BM_RABBIT":      {"period": 0.0, "might": 10.0},   # 중형 — 랜덤 원소
	"U_DM_FIREKEEPER":  {"period": 0.0, "might": 12.5},   # 중형 — 화염은 순수 딜로 높게
	# 사제 — 평타 없음. 축복량이 might × 체급 hit 이다.
	# 소형 사제는 얇은 축복을 여러 칸에 흩고, 중형은 굵게 몇 칸에 건다 — 인원 = 시전 횟수의 결과다
	"U_HUM_PRINCE":     {"period": 0.0, "might": 2.6},    # 소형
	"U_UD_NECROMANCER": {"period": 0.0, "might": 0.0},    # 소형 — CLEANSE. 축복이 아니다
	"U_BM_DEER":        {"period": 0.0, "might": 2.2},    # 소형
	"U_DM_DEMONESS":    {"period": 0.0, "might": 4.4},    # 중형
}

# chance     — "chance" 직업(전사·소드마스터)의 평타당 발동 확률. 고정값이라 자라지 않는다
# cast_time  — 캐스팅 직업의 주기. 그대로 부대 period 가 된다
# damage     — **타격 크기와 무관한 고정 수치만 남긴다** (EMPOWER_STRIKE·CRIT_BONUS_FLAT의
#              추가피해, GOLD_STEAL의 골드). NUKE 딜과 축복량은 TUNE_UNITS.might 가 정한다 —
#              둘 다 체급 프로필을 타야 해서 유닛 쪽에 있어야 한다
# multiplier — 그 타격에 곱해지는 배율 (크리 배율에 다시 곱해진다)
# dur        — 상태이상·버프 지속. 안 쓰는 칸은 비운다
#
# 원소별 딜 프로필은 기획의 설계 지침을 따랐다 — 냉기·독은 낮게 잡고 상태이상을 싣고,
# 화염·번개는 순수 딜로 높게. (번개의 "분산이 크다"는 프로토 미구현 — 평균값만 둔다)
const TUNE_SKILLS := {
	"SK_VK_BERSERKER":   {"chance": 0.20, "multiplier": 1.60, "dur": 3.0},
	"SK_DM_HIGH":        {"chance": 0.18, "damage": 26.0},
	"SK_DE_SWORD":       {"chance": 0.22},
	"SK_UD_DREADKNIGHT": {"chance": 0.25, "multiplier": 1.10},
	"SK_HUM_ARCHER":     {"multiplier": 1.50, "dur": 2.5},
	"SK_UD_SKELARCHER":  {},
	"SK_DE_ARCHER":      {"multiplier": 1.60},
	"SK_DM_FIREIMP":     {"damage": 8.0},
	"SK_DE_ASSASSIN":    {"multiplier": 0.25, "dur": VULN_DURATION},
	"SK_BM_CAT":         {"damage": 4.0},
	"SK_UD_REAPER":      {"multiplier": 1.80},
	"SK_HUM_MAGE":       {"cast_time": 2.60},
	"SK_DE_WIZARD":      {"cast_time": 2.40},
	"SK_UD_LICH":        {"cast_time": 3.00, "dur": 2.2},
	"SK_BM_RABBIT":      {"cast_time": 2.60},
	"SK_DM_FIREKEEPER":  {"cast_time": 2.80},
	"SK_HUM_PRINCE":     {"cast_time": 3.20},
	"SK_UD_NECROMANCER": {"cast_time": 3.00},
	"SK_BM_DEER":        {"cast_time": 3.00, "multiplier": 1.35, "dur": 3.0},
	"SK_DM_DEMONESS":    {"cast_time": 3.40},
}

# 로더가 채운다. 매대 풀 = 리더 제외 + 스킬 없는 유닛 제외 = 20종.
# 런타임 키 이름은 UI 60여 곳이 참조하므로 CSV를 이 모양으로 옮겨 담는다.
var UNITS: Array = []

# ─── 유물 = 옵션이 붙은 물건 ──────────────────────────────────────────────
# 전역 보유다. 칸에 장착하지 않고 유물 슬롯 줄에 둔다.
#
# **등급이 옵션 줄 수를 정하고, 태그가 옵션을 받을 부대를 정한다.**
# 태그는 유물 하나에 하나뿐이고 **베이스(형상)가 고정한다** — 굴려지지 않는다.
# 그래서 카드 얼굴(형상)만 보고 내 판과 맞는지가 걸러지고, 맞는 것만 호버해 읽으면 된다.
# 태그가 좁을수록 수치가 크다([직업] > [종족] > [전체]) — **몰빵의 보상이 여기서 나온다.**
const RELIC_TAG_MULT := {"job": 1.60, "race": 1.30, "all": 1.00}

# 베이스 = 형상. 태그 종류와 그 값(어느 직업·어느 종족)까지 여기서 굳는다.
# 리더는 매대 풀에 없으므로 [직업 리더] 베이스도 두지 않는다.
const RELIC_BASES := [
	{"id": "b_war",  "name": "전사의 각인",   "tag": "job",  "val": "warrior"},
	{"id": "b_swd",  "name": "검사의 숫돌",   "tag": "job",  "val": "swordmaster"},
	{"id": "b_arc",  "name": "궁수의 시위",   "tag": "job",  "val": "archer"},
	{"id": "b_asn",  "name": "암살자의 장막", "tag": "job",  "val": "assassin"},
	{"id": "b_mag",  "name": "마법사의 첨탑", "tag": "job",  "val": "mage"},
	{"id": "b_clr",  "name": "사제의 성해",   "tag": "job",  "val": "cleric"},
	{"id": "b_hum",  "name": "인간의 군기",   "tag": "race", "val": "인간"},
	{"id": "b_de",   "name": "다크엘프의 밀서", "tag": "race", "val": "다크엘프"},
	{"id": "b_ud",   "name": "언데드의 유해", "tag": "race", "val": "언데드"},
	{"id": "b_bm",   "name": "수인족의 토템", "tag": "race", "val": "수인족"},
	{"id": "b_dm",   "name": "악마의 계약서", "tag": "race", "val": "악마"},
	{"id": "b_all1", "name": "군단 깃발",     "tag": "all",  "val": ""},
	{"id": "b_all2", "name": "왕가의 인장",   "tag": "all",  "val": ""},
]

# 등급이 옵션 줄 수를 정한다. 매직·레어는 접두사·접미사로 굴려지고, 유니크만 고정 세트다.
const RELIC_GRADES := {
	"normal": {"name": "일반",   "pre": 0, "suf": 1, "price": 30,
	 "color": Color(0.74, 0.76, 0.82)},
	"magic":  {"name": "매직",   "pre": 1, "suf": 1, "price": 55,
	 "color": Color(0.52, 0.66, 0.98)},
	"rare":   {"name": "레어",   "pre": 2, "suf": 2, "price": 95,
	 "color": Color(0.96, 0.86, 0.42)},
	"unique": {"name": "유니크", "pre": 0, "suf": 0, "price": 130,
	 "color": Color(0.90, 0.60, 0.30)},
}

# **접두사와 접미사가 각각 무엇을 담는지는 「미결」이다.** 프로토는 디아블로의 관례를 따라
# 접두사에 공격 계열을, 접미사에 보조·성장 계열을 담았다.
#   stat — dmg(데미지 %) · spd(공격속도 %) · elem(그 원소 데미지 %) · crit(크리 확률) ·
#          critmult(크리 배율) · flat(타격당 고정값) · grow(성장형 — 아래)
# **성장형은 조건이 충족될 때마다 값이 누적된다** — 여기서는 보스를 잡을 때마다다.
# 조건은 자라는 속도를 정할 뿐이고 자란 결과는 상시 수치라, 전술카드가 아니라 유물의 몫이다.
const RELIC_PREFIX := [
	{"id": "sharp", "name": "날카로운", "stat": "dmg",  "min": 0.10, "max": 0.24},
	{"id": "swift", "name": "신속한",   "stat": "spd",  "min": 0.08, "max": 0.18},
	{"id": "keen",  "name": "예리한",   "stat": "crit", "min": 0.05, "max": 0.14},
	{"id": "burn",  "name": "타오르는", "stat": "elem", "elem": "fire",   "min": 0.15, "max": 0.35},
	{"id": "frost", "name": "서리 낀",  "stat": "elem", "elem": "cold",   "min": 0.15, "max": 0.35},
	{"id": "toxic", "name": "역병의",   "stat": "elem", "elem": "poison", "min": 0.15, "max": 0.35},
	{"id": "storm", "name": "뇌운의",   "stat": "elem", "elem": "shock",  "min": 0.15, "max": 0.35},
]
const RELIC_SUFFIX := [
	{"id": "might",   "name": "의 완력", "stat": "flat",     "min": 0.6,  "max": 2.2},
	{"id": "exec",    "name": "의 처형", "stat": "critmult", "min": 0.20, "max": 0.60},
	{"id": "vigor",   "name": "의 기세", "stat": "dmg",      "min": 0.08, "max": 0.18},
	# 성장형 — 값은 "킬 하나당 누적치"다. 런이 길어질수록 값진다
	{"id": "hoard",   "name": "의 축적", "stat": "grow",     "min": 0.03, "max": 0.07},
	{"id": "trophy",  "name": "의 전리", "stat": "grow",     "min": 0.04, "max": 0.09},
]

# 유니크만 고정이다 — 이름도 옵션도 정해져 있어 한 번 배우면 카드 얼굴만 보고 판단할 수 있다.
#
# **동사(상태이상·밀어내기)는 유니크에만 붙인다.** 유물이 스킬·동사를 주는지는 「미결」이고
# 나온 안이 셋인데, 프로토는 (2)번 — "유니크에만 붙는다" — 을 골라 태운다. 셋 중 유일하게
# [전체] 태그에 동사가 붙어 "태그가 좁을수록 세다"를 뒤집는 일이 없고, 무엇보다
# **이걸 빼면 상태이상 9종 중 7종의 공급원이 사라져** 프로토가 상태이상 축을 못 묻는다
# (유닛 스킬이 거는 상태이상은 취약·빙결 둘뿐이다).
#
# hits 는 중형(한 박자에 3타) 기준이다 — 소형은 3배 자주, 대형은 3배 드물게 터진다.
const RELIC_UNIQUES := [
	{"id": "hammer", "base": "b_war", "verb": "push", "name": "충격 망치", "hits": 21,
	 "opts": [{"stat": "flat", "val": 1.8}, {"stat": "dmg", "val": 0.15}],
	 "color": Color(0.96, 0.76, 0.36), "short": "밀어내기",
	 "desc": "최근접 보스를 밀어낸다. 거리는 타격당 딜에 비례한다."},
	{"id": "breaker", "base": "b_swd", "verb": "shred", "name": "균열 정", "hits": 27,
	 "opts": [{"stat": "dmg", "val": 0.20}, {"stat": "spd", "val": 0.10}],
	 "color": Color(0.86, 0.62, 0.50), "short": "파쇄 — 방어력 감소",
	 "desc": "보스의 방어력을 깎는다. 감산이라 딜 0인 칸을 한 번에 되살리는 폭발형이다."},
	{"id": "brand", "base": "b_arc", "verb": "burn", "name": "화염 낙인", "hits": 42,
	 "opts": [{"stat": "elem", "elem": "fire", "val": 0.30}, {"stat": "crit", "val": 0.08}],
	 "color": Color(0.98, 0.46, 0.30), "short": "화상 — 화염",
	 "desc": "화상 스택을 얹는다. 회복을 깎는다 — 재생을 정통으로 친다."},
	{"id": "venom", "base": "b_asn", "verb": "poison", "name": "독 바른 촉", "hits": 36,
	 "opts": [{"stat": "elem", "elem": "poison", "val": 0.30}, {"stat": "critmult", "val": 0.40}],
	 "color": Color(0.60, 0.86, 0.42), "short": "중독 — 독",
	 "desc": "중독 스택을 얹는다. 지속딜은 방어력을 보지 않는다."},
	{"id": "fetter", "base": "b_mag", "verb": "chill", "name": "서리 족쇄", "hits": 9,
	 "opts": [{"stat": "elem", "elem": "cold", "val": 0.30}, {"stat": "spd", "val": 0.12}],
	 "color": Color(0.55, 0.82, 0.98), "short": "빙결 — 냉기",
	 "desc": "이동·공격속도를 떨어뜨린다. 걸어오는 시간이 곧 공격 가능 시간이다."},
	{"id": "bolt", "base": "b_mag", "verb": "stun", "name": "뇌격 인장", "hits": 15,
	 "opts": [{"stat": "elem", "elem": "shock", "val": 0.28}, {"stat": "dmg", "val": 0.12}],
	 "color": Color(0.86, 0.74, 0.98), "short": "스턴",
	 "desc": "모든 행동을 멈춘다. 성벽 타격 중이면 그 동안 피해가 멎는다."},
	{"id": "mark", "base": "b_clr", "verb": "vuln", "name": "표적 성흔", "hits": 9,
	 "opts": [{"stat": "flat", "val": 1.4}, {"stat": "grow", "val": 0.06}],
	 "color": Color(0.98, 0.88, 0.55), "short": "취약",
	 "desc": "받는 피해를 비율로 올린다. 비율이라 한 방이 굵은 소수정예와 맞는다."},
]

# ─── 전술카드 = 전역에 거는 카드 ──────────────────────────────────────────
# **무엇에 거는지로 세 종류다 — 칸 · 골드 · 규칙.** 앞의 둘은 더해주고, 셋째는 바꾼다.
# 종류마다 카드 얼굴이 달라서, 호버해 읽기 전에 무엇에 거는 카드인지가 잡힌다.
#
# **직업·종족은 종류가 아니라 조건절이다** — 세 종류 어디에나 붙는다.
# 시너지를 세는 시스템(카운트 비례·문턱 보너스)은 두지 않는다. 조건절이 붙은 카드는
# 조건에 맞는 부대가 많을수록 저절로 세진다 — **몰빵의 보상이 여기서 난다.**
#
# 보유 상한이 있다 — 상한이 없으면 후반에 규칙이 쌓여 아무도 자기 게임의 규칙을 못 읽는다.
const TACTIC_SLOTS := 5

# **카드 목록의 단일 출처는 src/data/tactic_cards.csv 다** — 종류·등급·칠하는 칸·텍스트 키.
# 이름·효과 설명·역사 유래는 text.csv 의 키로 잇는다(기획 「전술카드 — 세 종류」).
# 목록은 _load_tactics() 가 CSV에서 채운다 — 아래 상수들은 CSV가 아직 담지 않는 것들이다:
# **효과의 내용·수치·가격은 전부 미결이라**(기획 「미결」) TACTIC_FX 가 프로토 눈대중으로 얹는다.
var TACTICS: Array = []

# cells 패턴명 → 격자 인덱스(0~8). 왼쪽이 후열, 오른쪽(2·5·8)이 성벽 쪽 전열이다.
# 전열·후열을 따로 정의하지 않는다 — 패턴이 곧 정의다(기획 「배치」).
# "ROW"는 전장의 열(성벽과 평행한 세로줄), "COLS"는 그 직각이다.
const TACTIC_CELLS := {
	"FRONT_ROW": [2, 5, 8], "MID_ROW": [1, 4, 7], "BACK_ROW": [0, 3, 6],
	"SIDE_COLS": [0, 1, 2, 6, 7, 8], "CROSS": [1, 3, 4, 5, 7],
	"RING": [0, 1, 2, 3, 5, 6, 7, 8], "DIAG": [0, 4, 8], "CORNERS": [0, 2, 6, 8],
	"ALL": [0, 1, 2, 3, 4, 5, 6, 7, 8], "NONE": [],
}
const TACTIC_KIND_KO := {"칸": "cell", "골드": "gold", "규칙": "rule"}
# 규칙 종류는 등급 자체가 미결이라 CSV가 비어 있다 — 프로토는 희귀(2)로 태운다
const TACTIC_GRADE_KO := {"일반": 1, "희귀": 2, "레어": 3}
const TACTIC_PRICES := {1: 60, 2: 85, 3: 120}

# 카드별 효과 글루 — **stat·val 은 전부 임시값이다.**
# name 은 name_key 가 빈 카드(골드 6종·규칙 2종 — 실존 전술명 미정)의 프로토 임시 이름이다.
# 이름 미결이 채워질 곳은 text.csv 지 여기가 아니다 — 여기 이름은 확정이 아니다.
# cells 를 여기서 덮으면 "받는 칸"이 CSV 패턴과 다르다는 뜻이다 — 청야유인은 칠한 모서리가
# **비어야** 나머지 다섯이 받는다. empty 는 "비어 있어야 하는 칸"이다.
const TACTIC_FX := {
	"TC_HAKIK":        {"stat": "dmg", "val": 0.30},
	"TC_SANDAN":       {"stat": "spd", "val": 0.22},
	"TC_CROSSFIRE":    {"stat": "crit", "val": 0.15},
	# 「배수진」 — 보스가 성벽에 가까울수록 오른다. val 은 도달 직전의 최대치다
	"TC_BAESU":        {"stat": "dmg_near", "val": 0.55},
	"TC_JUNGANG":      {"stat": "spd", "val": 0.32},
	"TC_CANNAE":       {"stat": "dmg", "val": 0.26, "empty": [4]},
	# 사선진법 — **효과 미정**(기획 「미결」). 프로토는 타격당 고정값을 임시로 태운다
	"TC_SASUN":        {"stat": "flat", "val": 2.6},
	"TC_CHEONGYA":     {"stat": "dmg", "val": 0.60, "cells": [1, 3, 4, 5, 7], "empty": [0, 2, 6, 8]},
	"TC_GOLD_KILL":    {"stat": "kill_gold", "val": 0.35, "name": "사략 허가장"},
	"TC_GOLD_TIME":    {"stat": "gold_sec", "val": 2.5, "name": "마케도니아의 병참"},
	"TC_GOLD_REROLL":  {"stat": "reroll_cut", "val": 0.5, "name": "제노바의 환전상"},
	# 「파동」— 이 게임의 파동은 적 하나다. 킬마다 목돈이 따로 떨어지는 것으로 해석해 태운다
	"TC_GOLD_WAVE":    {"stat": "wave_gold", "val": 14.0, "name": "개선식의 전리품"},
	"TC_GOLD_SHIELD":  {"stat": "gold_shield", "val": 2.0, "name": "용병의 방패삯"},
	"TC_GOLD_HOARD":   {"stat": "gold_hoard", "val": 0.05, "name": "푸거가의 금고"},
	"TC_RULE_DIAG":    {"stat": "rule_diag", "val": 1.0, "name": "봉수의 사슬"},
	"TC_RULE_CRITDMG": {"stat": "rule_critmult", "val": 0.35, "name": "비엔나의 돌격"},
}

# 카탈로그 밖 — **프로토 실험 카드다. tactic_cards.csv 에 없다.**
# 규칙 둘은 「규칙 종류가 건드리는 것」의 채택 미정 후보를 태우는 것이고(필룸 = 최소 보장,
# 팔랑크스 = 인원 판정 묶기), 아쟁쿠르는 **조건절**(직업·종족은 종류가 아니라 조건절이다 —
# 확정)을 태울 카드가 카탈로그에 아직 없어서 남겼다.
const TACTIC_EXTRA := [
	{"id": "t_agincourt", "kind": "cell", "grade": 2, "name": "아쟁쿠르의 진창",
	 "cells": [2, 5, 8], "empty": [], "cond": {"job": "archer"}, "stat": "crit", "val": 0.22,
	 "desc": "", "lore": "1415년, 진창에 갇힌 기병 위로 장궁이 쏟아졌다.", "price": 85},
	{"id": "t_phalanx", "kind": "rule", "grade": 3, "name": "테베의 팔랑크스",
	 "cells": [], "empty": [], "cond": {}, "stat": "rule_unify", "val": 1.0,
	 "desc": "", "lore": "창을 든 팔들이 한 몸처럼 움직였다.", "price": 130},
	# 최소 보장 1.0은 감산을 통째로 껐다(봇이 딜 0 타격 0%로 무피해 클리어) — 0.5로 내려 태운다
	{"id": "t_pilum", "kind": "rule", "grade": 2, "name": "로마의 필룸",
	 "cells": [], "empty": [], "cond": {}, "stat": "rule_floor", "val": 0.5,
	 "desc": "", "lore": "방패를 뚫지 못해도 박혀서 방패를 버리게 했다.", "price": 100},
]

# ─── 적 ───────────────────────────────────────────────────────────────────
# 적은 **정예 · 막보스** 두 단뿐이다. **잡몹은 두지 않는다** — 9칸 전원이 최근접 하나를
# 함께 때리므로 플레이어가 "저건 무시하고 이걸 때린다"를 고를 수 없고, 그러면 잡몹은
# 어떻게 설계해도 순서대로 처리되는 대기열로만 남는다(기획 「적」). 대신 하나하나가 길다.
#
# 정예 하나 = **그 막 진영의 베이스 + 접두사 몇 개.** 디아블로의 유니크와 같은 구조다.
# 막보스는 접두사를 굴리지 않는다 — 조합이 고정이며 손으로 만든다.
#
# 베이스는 스프라이트·체급과 맨몸 스탯만 갖는다. **성격은 전부 접두사가 얹는다.**
# res 는 원소 저항. 값을 그대로 감소율로 쓴다 — 0.60이면 60% 감소. 상한은 RES_CAP.
# evade 는 회피 — **물리 명중 판정의 대응 축이다. 마법에는 걸리지 않는다**(기획 「변별 축」).
const BASES := {
	# 막1 · 침공 — 오크. 저방어라 아무거나 통한다
	"orc_warrior":   {"name": "오크 전사",   "size": "중형", "hp": 2028.0, "armor": 1.0,
	 "speed": 64.0, "evade": 0.05, "wall_dmg": 30.0, "wall_int": 1.5, "push_res": 0.30,
	 "sprite": "minifolks/MinifolksOrcs/MiniOrcWarrior/outline"},
	"orc_thrower":   {"name": "오크 투척병", "size": "중형", "hp": 1833.0, "armor": 0.0,
	 "speed": 70.0, "evade": 0.10, "wall_dmg": 26.0, "wall_int": 1.3, "push_res": 0.25,
	 "sprite": "minifolks/MinifolksOrcs/MiniOrcAxeThrower/outline"},
	"goblin":        {"name": "고블린",      "size": "소형", "hp": 1482.0, "armor": 0.0,
	 "speed": 88.0, "evade": 0.16, "wall_dmg": 20.0, "wall_int": 1.1, "push_res": 0.15,
	 "sprite": "minifolks/MinifolksOrcs/MiniGoblin/outline"},
	"warg_rider":    {"name": "와르그 기수", "size": "중형", "hp": 1950.0, "armor": 2.0,
	 "speed": 82.0, "evade": 0.08, "wall_dmg": 28.0, "wall_int": 1.4, "push_res": 0.35,
	 "sprite": "minifolks/MinifolksOrcs/MiniWargRider/outline"},

	# 막2 · 야생 — 야수·놀. 질주와 중장갑이 한 진영 안에 정반대로 들어 있다
	"panther":       {"name": "흑표범",      "size": "대형", "hp": 2418.0, "armor": 2.0,
	 "speed": 104.0, "evade": 0.22, "wall_dmg": 34.0, "wall_int": 1.1, "push_res": 0.30,
	 "sprite": "minifolks/MiniFolksPlusAnimals/MiniPanther/outline"},
	"turtle":        {"name": "바위거북",    "size": "중형", "hp": 3510.0, "armor": 9.0,
	 "speed": 40.0, "evade": 0.0, "wall_dmg": 40.0, "wall_int": 1.8, "push_res": 0.60,
	 "sprite": "minifolks/MiniFolksPlusAnimals/MiniTurtle/outline"},
	"gnoll_berserk": {"name": "놀 광전사",   "size": "중형", "hp": 2574.0, "armor": 3.0,
	 "speed": 76.0, "evade": 0.12, "wall_dmg": 36.0, "wall_int": 1.3, "push_res": 0.35,
	 "sprite": "minifolks/MiniGnolls/MiniGnollBerserk/outline"},
	"hyena":         {"name": "하이에나",    "size": "중형", "hp": 2106.0, "armor": 1.0,
	 "speed": 96.0, "evade": 0.26, "wall_dmg": 26.0, "wall_int": 1.0, "push_res": 0.20,
	 "sprite": "minifolks/MiniGnolls/MiniHyena/outline"},
	"rhino":         {"name": "코뿔소",      "size": "대형", "hp": 3354.0, "armor": 7.0,
	 "speed": 58.0, "evade": 0.0, "wall_dmg": 44.0, "wall_int": 1.6, "push_res": 0.65,
	 "sprite": "minifolks/MiniFolksPlusAnimals/MiniRhino/outline"},

	# 막3 · 죽음 — 할로윈·언데드 괴수. 유령의 회피가 물리 명중 축을 정면으로 시험한다
	"werewolf":      {"name": "늑대인간",    "size": "중형", "hp": 3042.0, "armor": 3.0,
	 "speed": 82.0, "evade": 0.14, "wall_dmg": 38.0, "wall_int": 1.3, "push_res": 0.40,
	 "sprite": "minifolks/MiniHalloweenMonsters/MiniWerewolf/outline"},
	"ghost":         {"name": "원귀",        "size": "중형", "hp": 2496.0, "armor": 0.0,
	 "speed": 66.0, "evade": 0.40, "wall_dmg": 34.0, "wall_int": 1.4, "push_res": 0.45,
	 "sprite": "minifolks/MiniHalloweenMonsters/MiniGhost/outline"},
	"scarecrow":     {"name": "허수아비",    "size": "대형", "hp": 3666.0, "armor": 4.0,
	 "speed": 52.0, "evade": 0.05, "wall_dmg": 42.0, "wall_int": 1.6, "push_res": 0.55,
	 "sprite": "minifolks/MiniHalloweenMonsters/MiniScarecrow/outline"},
	"vampire":       {"name": "흡혈귀",      "size": "소형", "hp": 2730.0, "armor": 2.0,
	 "speed": 74.0, "evade": 0.20, "wall_dmg": 32.0, "wall_int": 1.2, "push_res": 0.35,
	 "sprite": "minifolks/MiniHalloweenMonsters/MiniVampire/outline"},

	# 막4 · 심연 — 심연군단·거대몬스터. 원소 강화가 몰빵을 처벌한다
	"abyss_golem":   {"name": "심연 골렘",   "size": "대형", "hp": 4446.0, "armor": 10.0,
	 "speed": 48.0, "evade": 0.0, "wall_dmg": 50.0, "wall_int": 1.6, "push_res": 0.70,
	 "sprite": "minifolks/MiniFolksPlusAbyssArmy/MiniAbyssGolem/outline"},
	"abyss_exec":    {"name": "심연 처형자", "size": "대형", "hp": 3900.0, "armor": 5.0,
	 "speed": 68.0, "evade": 0.12, "wall_dmg": 54.0, "wall_int": 1.3, "push_res": 0.55,
	 "sprite": "minifolks/MiniFolksPlusAbyssArmy/MiniAbyssAbyssExecutioner/outline"},
	"abyss_elem":    {"name": "심연 정령",   "size": "중형", "hp": 3432.0, "armor": 2.0,
	 "speed": 78.0, "evade": 0.18, "wall_dmg": 44.0, "wall_int": 1.2, "push_res": 0.40,
	 "sprite": "minifolks/MiniFolksPlusAbyssArmy/MiniAbyssElemental/outline"},
	"dark_lord":     {"name": "암흑군주",    "size": "대형", "hp": 4212.0, "armor": 6.0,
	 "speed": 62.0, "evade": 0.08, "wall_dmg": 48.0, "wall_int": 1.4, "push_res": 0.60,
	 "sprite": "minifolks/MiniBigMonsters/MiniDarkLord/outline"},

	# 막보스 — 초대형·대형. 접두사를 굴리지 않고 조합이 고정이다
	"orc_warchief":  {"name": "오크 대족장", "size": "대형", "hp": 4600.0, "armor": 4.0,
	 "speed": 58.0, "evade": 0.05, "wall_dmg": 56.0, "wall_int": 1.4, "push_res": 0.50,
	 "sprite": "minifolks/MinifolksOrcs/MiniOrcWarChief/outline"},
	"giant_bear":    {"name": "거대곰",      "size": "대형", "hp": 5900.0, "armor": 6.0,
	 "speed": 62.0, "evade": 0.0, "wall_dmg": 64.0, "wall_int": 1.3, "push_res": 0.60,
	 "sprite": "minifolks/MiniBigMonsters/MiniGiantBear/outline"},
	"skel_dragon":   {"name": "해골룡",      "size": "초대형", "hp": 7200.0, "armor": 7.0,
	 "speed": 54.0, "evade": 0.10, "wall_dmg": 72.0, "wall_int": 1.4, "push_res": 0.65,
	 "sprite": "minifolks/MiniBigMonsters/MiniSkeletonDragon/outline"},
	"black_dragon":  {"name": "흑룡",        "size": "초대형", "hp": 8600.0, "armor": 9.0,
	 "speed": 56.0, "evade": 0.08, "wall_dmg": 80.0, "wall_int": 1.3, "push_res": 0.70,
	 "sprite": "minifolks/MiniBigMonsters/MiniBlackDragon/outline"},
}

# 보스 스프라이트 배율 — 정수배만 쓴다(기획 「프레젠테이션」).
const BOSS_SCALE := {"소형": 4, "중형": 5, "대형": 6, "초대형": 7}

# 접두사는 「무엇이 막히는가」로 정의한다 — "무엇이 통하는가"가 아니다. 물리가 감산이라
# *아예 안 통하는* 편성이 실제로 생기고, 그것이 매대를 뒤지게 만드는 유일한 동력이다.
# 접두사 하나는 **플레이어 빌드 하나를 정확히 죽여야** 값을 한다(기획 「정예는 접두사 조합이다」).
#
# 이름이 곧 표식이다 — 적 아래에 붙는 단어가 그대로 접두사 이름이고,
# 예고 슬롯에서 본 단어가 전투에서 다시 보인다.
const PREFIXES := {
	"heavy":    {"name": "중장갑", "armor_add": 12.0, "speed_mul": 0.75,
	 "blocks": "다수 물리 전원이 딜 0", "answer": "마법 / 소수정예"},
	"harden":   {"name": "경화", "harden": 0.32,
	 "blocks": "장기전", "answer": "빠른 킬 / 파쇄"},
	"hex_cold": {"name": "냉기 강화", "hex": "cold",
	 "blocks": "냉기 몰빵", "answer": "물리 / 다른 원소 / 냉기 저항 감소"},
	"hex_fire": {"name": "화염 강화", "hex": "fire",
	 "blocks": "화염 몰빵", "answer": "물리 / 다른 원소 / 화염 저항 감소"},
	"hex_pois": {"name": "독 강화", "hex": "poison",
	 "blocks": "독 몰빵", "answer": "물리 / 다른 원소 / 독 저항 감소"},
	"hex_shock": {"name": "번개 강화", "hex": "shock",
	 "blocks": "번개 몰빵", "answer": "물리 / 다른 원소 / 번개 저항 감소"},
	"rush":     {"name": "질주", "speed_mul": 1.85,
	 "blocks": "느린 주기 부대 — 쇼핑할 시간을 안 준다", "answer": "빙결 · 밀어내기"},
	"stubborn": {"name": "완고", "push_add": 0.34,
	 "blocks": "밀어내기 의존 빌드", "answer": "순수 딜"},
	"frenzy":   {"name": "광폭", "frenzy": 1.20,
	 "blocks": "마무리 못 하는 편성", "answer": "한 번에 끝내기"},
	"regen":    {"name": "재생", "regen_add": 15.0,
	 "blocks": "찔끔딜", "answer": "순간 화력 / 화상"},
	"bind":     {"name": "주박", "bind": true,
	 "blocks": "소수정예 — 완충재가 없다", "answer": "인원 많은 부대 / 정화"},
}
const HEX_RES := 0.70                 # 원소 강화가 정통으로 막는 그 한 원소

# 막 — 진영이 곧 얼굴이다. 막마다 적 진영이 통째로 바뀌므로 화면의 실루엣이 갈린다.
# 컨셉은 분위기가 아니라 **「무엇으로 못 잡게 되는가」**로 잡는다.
#
# pool     — 그 막의 정예 베이스. **이단아를 한둘 섞는다** (2막 거북이, 3막 원귀)
# prefixes — 그 막에서 굴릴 수 있는 접두사. **1막에는 중장갑을 걸지 않는다** —
#            학습 구간이 살려면 아무 편성이나 통해야 한다
# npre     — 접두사 개수 [최소, 최대]. 막이 넘어갈수록 늘어난다
# boss     — 막보스. 접두사 조합이 고정이고, 막이 시작될 때부터 예고에 상시 표시된다
const ACTS := [
	{"name": "1 · 침공", "elites": 2, "tint": Color(0.62, 0.80, 0.44),
	 "pool": ["orc_warrior", "orc_thrower", "goblin", "warg_rider"],
	 "prefixes": ["rush", "stubborn", "frenzy", "regen"], "npre": [1, 1],
	 "boss": "orc_warchief", "boss_pre": ["harden", "stubborn"]},
	{"name": "2 · 야생", "elites": 2, "tint": Color(0.86, 0.68, 0.38),
	 "pool": ["panther", "turtle", "gnoll_berserk", "hyena", "rhino"],
	 "prefixes": ["rush", "heavy", "stubborn", "frenzy", "harden"], "npre": [1, 2],
	 "boss": "giant_bear", "boss_pre": ["heavy", "frenzy"]},
	{"name": "3 · 죽음", "elites": 2, "tint": Color(0.66, 0.56, 0.86),
	 "pool": ["werewolf", "ghost", "scarecrow", "vampire"],
	 "prefixes": ["regen", "bind", "harden", "heavy", "frenzy"], "npre": [2, 2],
	 "boss": "skel_dragon", "boss_pre": ["regen", "bind", "heavy"]},
	{"name": "4 · 심연", "elites": 2, "tint": Color(0.90, 0.42, 0.52),
	 "pool": ["abyss_golem", "abyss_exec", "abyss_elem", "dark_lord"],
	 "prefixes": ["hex_cold", "hex_fire", "hex_pois", "hex_shock", "heavy", "stubborn"],
	 "npre": [2, 3],
	 "boss": "black_dragon", "boss_pre": ["heavy", "harden", "hex_fire", "stubborn"]},
]

enum Phase { RUNNING, CLEAR, DEFEAT }
enum SpawnMode { FIXED, ADAPTIVE }

# ─── 상태 ─────────────────────────────────────────────────────────────────
var _phase: int = Phase.RUNNING
var _spawn_mode: int = SpawnMode.FIXED
var _paused: bool = false

var _elapsed: float = 0.0
var _gold: int = GOLD_START
var _gold_frac: float = 0.0           # 시간 골드의 소수부 — 정수 골드만 표시하므로 여기 모은다
var _wall_hp: float = WALL_HP_START
var _wall_max: float = WALL_HP_START
var _wall_flash: float = 0.0

var _cells: Array = []                # 9칸 — null 또는 부대 Dictionary
var _bosses: Array = []               # 등장 순서대로. 죽으면 death 연출 후 제거
var _shop: Array = []                 # 5슬롯 — null(구매됨) 또는 카드 Dictionary
var _relics: Array = []               # RELIC_SLOTS — null 또는 굴려진 유물 인스턴스. 전역 보유다
var _tactics: Array = []              # TACTIC_SLOTS — null 또는 전술카드 정의. 전역 보유다
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
var _log_missed: int = 0              # 회피에 빗나간 물리 타격 — 명중 판정은 물리에만 있다
var _log_relic_fires: int = 0
var _log_skill_fires: Dictionary = {}  # effect → 발동 횟수. 17종이 실제로 도는지 보는 눈금

# 로더가 채우는 읽기 전용 사전 — CSV 원문을 코드가 쓰는 모양으로 옮겨 담은 것뿐이다
var _text: Dictionary = {}            # 번역 키 → ko
var _collection: Dictionary = {}      # sprite_entry → 컬렉션 폴더명
var _size_tier: Dictionary = {}       # sprite_entry → 실측 체급(소형·중형·대형·초대형)

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
	_load_data()                      # 스프라이트 경로가 여기서 정해지므로 _frames 빌드보다 먼저다
	for u in UNITS:
		_frames[u["sprite"]] = _build_frames(u["sprite"])
	for k in BASES:
		_frames[BASES[k]["sprite"]] = _build_frames(str(BASES[k]["sprite"]))

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


# ─── CSV 로더 ─────────────────────────────────────────────────────────────
# src/data/*.csv 는 .import 가 importer="keep" 이라 FileAccess 로 원문이 그대로 열린다
# (csv_translation 임포터를 태우면 컬럼명이 로케일로 오인된다 — CLAUDE.md).
func _load_csv(path: String) -> Array:
	var out: Array = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("CSV를 열 수 없다: %s" % path)
		return out
	var head: PackedStringArray = f.get_csv_line()
	while not f.eof_reached():
		var row: PackedStringArray = f.get_csv_line()
		if row.size() < 2:
			continue                  # 파일 끝의 빈 줄
		var d: Dictionary = {}
		for i in head.size():
			d[head[i]] = row[i] if i < row.size() else ""
		out.append(d)
	f.close()
	return out


func _tr(key: String) -> String:
	if key == "":
		return ""
	return str(_text.get(key, key))   # 키가 그대로 보이면 text.csv 에 빠진 것이다


# 매대 풀을 만든다 — 리더(발동 미결)와 스킬 없는 유닛을 빼면 20종이 남는다.
# 런타임 키 이름(members/power/period/elem/sprite/name/race/job/bless)은 UI 60여 곳이
# 참조하므로 **여기서** CSV를 그 모양으로 옮겨 담는다. 아래쪽 코드는 CSV를 모른다.
func _load_data() -> void:
	UNITS.clear()
	for r in _load_csv("%s/i18n/text.csv" % DATA_ROOT):
		_text[str(r["keys"])] = str(r["ko"])
	# 체급 배정의 단일 출처는 size_tier(실측 픽셀 크기)다 — 화면상 크기와 체급이 어긋나면
	# 실루엣 원칙이 거짓말이 된다(기획 「체급」).
	for r in _load_csv("%s/sprite_catalog.csv" % DATA_ROOT):
		_collection[str(r["entry"])] = str(r["collection"])
		_size_tier[str(r["entry"])] = str(r["size_tier"])

	# effect 가 빈 행은 아직 내용이 정해지지 않은 것이다 (SK_BM_LION) — 통째로 건너뛴다
	var skills: Dictionary = {}
	for r in _load_csv("%s/skills.csv" % DATA_ROOT):
		if str(r["effect"]) == "":
			continue
		var sid: String = str(r["skill_id"])
		var tune: Dictionary = TUNE_SKILLS.get(sid, {})
		skills[str(r["unit_id"])] = {
			"id": sid,
			"effect": str(r["effect"]),
			"target": str(r["target"]),
			"name": _tr(str(r["name_key"])),
			"desc": _tr(str(r["desc_key"])),
			"chance": float(tune.get("chance", 0.0)),
			"cast_time": float(tune.get("cast_time", 0.0)),
			"damage": float(tune.get("damage", 0.0)),
			"multiplier": float(tune.get("multiplier", 1.0)),
			"dur": float(tune.get("dur", 0.0)),
		}

	for r in _load_csv("%s/units.csv" % DATA_ROOT):
		var uid: String = str(r["unit_id"])
		var job_ko: String = str(r["job"])
		if not JOB_KO.has(job_ko):
			push_error("모르는 직업: %s (%s)" % [job_ko, uid])
			continue
		var job: String = str(JOB_KO[job_ko])
		if job == "leader" or not skills.has(uid):
			continue                  # 리더는 발동 미결, 스킬 없는 유닛은 태울 리듬이 없다
		var elem: String = ""
		var elem_ko: String = str(r["element"])
		if elem_ko != "":
			if not ELEM_KO.has(elem_ko):
				push_error("모르는 원소: %s (%s)" % [elem_ko, uid])
				continue
			elem = str(ELEM_KO[elem_ko])
		var entry: String = str(r["sprite_entry"])
		if not _collection.has(entry):
			push_error("스프라이트 카탈로그에 없다: %s (%s)" % [entry, uid])
			continue
		var sk: Dictionary = skills[uid]
		var tu: Dictionary = TUNE_UNITS.get(uid, {})
		var casts: bool = bool(JOBS[job]["cast"])

		# 체급은 스프라이트 실측이 정하고, 인원 상한(crew)은 그 배정에 따라 units.csv 가 갖는다.
		# 둘이 어긋나면 units.csv 쪽이 확정 데이터이므로 그쪽을 믿고 경고만 남긴다.
		var tier_ko: String = str(_size_tier.get(entry, ""))
		var size: String = str(SIZE_KO.get(tier_ko, "mid"))
		var cap: int = int(str(r["crew"])) if str(r["crew"]) != "" else int(SIZES[size]["cap"])
		if cap != int(SIZES[size]["cap"]):
			push_warning("체급과 인원 상한이 어긋난다: %s (%s → %d, crew=%d)"
				% [uid, tier_ko, int(SIZES[size]["cap"]), cap])
		# 타격당 딜 = 유닛 화력 눈금 × 체급 프로필. **인원으로 나누지 않는다** —
		# 인원이 정하는 것은 총 화력이지 타격당 딜이 아니다(기획 「체급과 화력은 직교한다」).
		var hit: float = float(tu.get("might", 0.0)) * float(SIZES[size]["hit"])

		UNITS.append({
			"id": uid,
			"job": job,
			"race": str(r["faction"]),
			"name": _tr(str(r["name_key"])),
			"size": size,
			"cap": cap,
			# 타격당 딜(평타) · 시전당 딜(마법사) · 축복량(사제) 이 전부 같은 눈금을 쓴다
			"hit": hit,
			# 캐스팅 직업은 캐스팅 시간이 곧 박자다
			"period": float(sk["cast_time"]) if casts else float(tu.get("period", 1.0)),
			"elem": elem,
			"skill": sk,
			# outline 강제 — no_outline 은 프로토에서도 쓰지 않는다 (기획 「프레젠테이션」)
			"sprite": "minifolks/%s/%s/outline" % [str(_collection[entry]), entry],
			# 마리당 단가는 체급이 정한다 (소형 < 중형 < 대형). 카드값은 마릿수에 비례한다
			"unit_price": int(SIZES[size]["unit"]),
		})
	if UNITS.size() != 20:
		push_warning("매대 풀이 20종이 아니다 — %d종" % UNITS.size())
	_load_tactics()


# 전술카드 — 목록·종류·등급·칠하는 칸·텍스트는 CSV가 정하고, 효과·수치는 TACTIC_FX(임시)가
# 얹는다. 런타임 키 모양은 TACTIC_EXTRA 와 같다 — 아래쪽 코드는 CSV를 모른다.
func _load_tactics() -> void:
	TACTICS.clear()
	for r in _load_csv("%s/tactic_cards.csv" % DATA_ROOT):
		var id: String = str(r["card_id"])
		if not TACTIC_FX.has(id):
			push_warning("효과 글루가 없는 전술카드 — 매대에 안 나온다: %s" % id)
			continue
		var fx: Dictionary = TACTIC_FX[id]
		var kind_ko: String = str(r["kind"])
		if not TACTIC_KIND_KO.has(kind_ko):
			push_error("모르는 전술카드 종류: %s (%s)" % [kind_ko, id])
			continue
		var grade: int = int(TACTIC_GRADE_KO.get(str(r["grade"]), 2))
		var pattern: String = str(r["cells"])
		if not TACTIC_CELLS.has(pattern):
			push_error("모르는 칸 패턴: %s (%s)" % [pattern, id])
			continue
		var nk: String = str(r["name_key"])
		TACTICS.append({
			"id": id, "kind": str(TACTIC_KIND_KO[kind_ko]), "grade": grade,
			"name": _tr(nk) if nk != "" else str(fx.get("name", id)),
			"cells": fx.get("cells", TACTIC_CELLS[pattern]),
			"empty": fx.get("empty", []), "cond": fx.get("cond", {}),
			"stat": str(fx["stat"]), "val": float(fx["val"]),
			"desc": _tr(str(r["desc_key"])), "lore": _tr(str(r["hist_key"])),
			"price": int(TACTIC_PRICES[grade]),
		})
	for e in TACTIC_EXTRA:
		TACTICS.append(e)


func _unit_by_id(id: String) -> Dictionary:
	for u in UNITS:
		if str(u["id"]) == id:
			return u
	push_error("그런 유닛이 없다: %s" % id)
	return {}


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
	_log_missed = 0
	_log_relic_fires = 0
	_log_skill_fires.clear()
	_gold_frac = 0.0
	_drag_kind = ""
	_pin_kind = ""

	_cells.clear()
	for _i in 9:
		_cells.append(null)
	_relics.clear()
	for _i in RELIC_SLOTS:
		_relics.append(null)
	_tactics.clear()
	for _i in TACTIC_SLOTS:
		_tactics.append(null)
	_bosses.clear()
	_build_schedule()
	_next_spawn = 0
	_refresh_shop(true)
	queue_redraw()
	_overlay.queue_redraw()


# 런은 네 개의 막이다. 막마다 진영이 통째로 바뀌고, 막 끝에 막보스가 온다.
# **문법은 고정하고 문장은 굴린다** — 막 진영·순서·막보스는 고정이고,
# 정예의 접두사 조합과 등장 순서만 굴린다(기획 「무엇이 고정이고 무엇이 랜덤인가」).
func _build_schedule() -> void:
	_schedule.clear()
	var t: float = FIRST_SPAWN
	var idx: int = 0
	for ai in ACTS.size():
		var act: Dictionary = ACTS[ai]
		var n: int = int(act["elites"])
		for e in n + 1:
			var boss: bool = e == n
			var base_id: String = str(act["boss"]) if boss \
				else str(act["pool"][_rng.randi_range(0, (act["pool"] as Array).size() - 1)])
			var pre: Array = _fixed_prefixes(act) if boss else _roll_prefixes(act)
			_schedule.append(_make_entry(idx, ai, base_id, pre, boss, t))
			idx += 1
			# 막이 넘어갈수록 스폰 간격이 좁아진다 — 난이도를 적 스탯이 아니라 **쇼핑 시간**으로
			# 조인다. 파워 천장(9칸·유물 상한)을 건드리지 않으면서 후반이 조여진다.
			t += lerpf(INTERVAL_EARLY, INTERVAL_LATE, float(ai) / float(maxi(1, ACTS.size() - 1)))


func _fixed_prefixes(act: Dictionary) -> Array:
	var out: Array = []
	for p in act["boss_pre"]:
		out.append(str(p))
	return out


# 접두사가 겹치면 답이 좁아진다 — 「중장갑 · 화염 강화」는 물리도 화염도 막으므로
# 남은 원소나 저항 감소로만 뚫린다. **조합 수가 곧 정예의 다양성이다.**
func _roll_prefixes(act: Dictionary) -> Array:
	var span: Array = act["npre"]
	var want: int = _rng.randi_range(int(span[0]), int(span[1]))
	var bag: Array = (act["prefixes"] as Array).duplicate()
	var out: Array = []
	while out.size() < want and not bag.is_empty():
		var i: int = _rng.randi_range(0, bag.size() - 1)
		var pick: String = str(bag[i])
		bag.remove_at(i)
		# 원소 강화 둘이 한 놈에 붙지 않게 한다 — 「접두사 조합 규칙」은 「미결」이라
		# 프로토가 한쪽을 골랐다. 둘이 겹치면 그 판의 마법이 통째로 죽어 답이 사라진다.
		if str(pick).begins_with("hex_") and _has_hex(out):
			continue
		out.append(pick)
	return out


func _has_hex(pre: Array) -> bool:
	for p in pre:
		if str(p).begins_with("hex_"):
			return true
	return false


func _make_entry(idx: int, act_i: int, base_id: String, pre: Array, boss: bool,
		at: float) -> Dictionary:
	var base: Dictionary = BASES[base_id]
	# **스탯 인플레는 막보스에만 건다.** 정예의 난이도는 스탯이 아니라 진영 교체와
	# 접두사 개수로 오른다 (기획 「막」).
	var mult: float = (1.0 + float(act_i) * 0.22) if boss else 1.0
	# 맨몸 저항은 막을 따라 완만히 오른다. 원소 강화가 붙은 원소만 HEX_RES 로 튄다 —
	# 낙차가 큰 대신 예고 슬롯이 미리 알린다.
	var floor_res: float = 0.05 + float(act_i) * 0.05
	var res: Dictionary = {}
	for el in ELEM_ORDER:
		res[el] = floor_res

	var e: Dictionary = {
		"base": base, "act": act_i, "index": idx, "at": at, "boss": boss, "pre": pre,
		"name": ("%s ★" % str(base["name"])) if boss else str(base["name"]),
		"tint": ACTS[act_i]["tint"],       # 막 진영의 색 — 막이 바뀌면 화면이 통째로 갈린다
		"hp": float(base["hp"]) * mult,
		"armor": float(base["armor"]) * mult,
		"speed": float(base["speed"]),
		"evade": float(base["evade"]),
		"wall_dmg": float(base["wall_dmg"]) * mult,
		"push_res": float(base["push_res"]),
		"res": res,
		"regen": 0.0,
		"harden": 0.0,                # 경화 — 초당 방어력 상승분
		"frenzy": 0.0,                # 광폭 — 체력이 0일 때의 속도 배율 가산
		"bind": false,                # 주박 — 병력 디버프
		"gold": int((KILL_GOLD_BASE + KILL_GOLD_STEP * idx) * (2 if boss else 1)),
	}
	for p in pre:
		var d: Dictionary = PREFIXES[str(p)]
		e["armor"] = float(e["armor"]) + float(d.get("armor_add", 0.0))
		e["speed"] = float(e["speed"]) * float(d.get("speed_mul", 1.0))
		e["push_res"] = float(e["push_res"]) + float(d.get("push_add", 0.0))
		e["regen"] = float(e["regen"]) + float(d.get("regen_add", 0.0)) * mult
		e["harden"] = maxf(float(e["harden"]), float(d.get("harden", 0.0)))
		e["frenzy"] = maxf(float(e["frenzy"]), float(d.get("frenzy", 0.0)))
		e["bind"] = bool(e["bind"]) or bool(d.get("bind", false))
		if d.has("hex"):
			(e["res"] as Dictionary)[str(d["hex"])] = HEX_RES
	return e


# 접두사가 곧 표식이다 — 적 아래에 붙는 단어가 그대로 접두사 이름이고,
# 예고 슬롯에서 본 단어가 전투에서 다시 보인다.
func _entry_tags(entry: Dictionary) -> Array:
	var tags: Array = []
	for p in entry["pre"]:
		tags.append(str(PREFIXES[str(p)]["name"]))
	return tags


# ─── 매대 ─────────────────────────────────────────────────────────────────
func _roll_card(units_only: bool) -> Dictionary:
	# 풀은 순수 랜덤이다. 종류별 가중치는 두지 않고 시작한다. 단 첫 매대는 병사카드로 채운다 —
	# 빈 격자에 전술·유물은 살 수 없는 매물이다.
	if not units_only:
		var k: float = _rng.randf()
		if k < 0.22:
			var it: Dictionary = _roll_relic()
			return {"kind": "relic", "def": it, "price": int(it["price"])}
		if k < 0.42:
			var tc: Dictionary = TACTICS[_rng.randi_range(0, TACTICS.size() - 1)]
			return {"kind": "tactic", "def": tc, "price": int(tc["price"])}
	# 유닛에 등급 축이 없으므로 가중치도 없다 — 20종 순수 랜덤이다.
	# 진행도에 따라 고티어를 섞던 장치는 티어와 함께 폐기됐다(기획 「체급」).
	var d: Dictionary = UNITS[_rng.randi_range(0, UNITS.size() - 1)]
	# 병사카드는 부대가 아니라 **병사 묶음**이다 — 마릿수가 카드마다 다르고,
	# 같은 유닛의 칸에 부으면 합쳐진다(기획 「배치」).
	var span: Array = CARD_CREW[str(d["size"])]
	var cnt: int = _rng.randi_range(int(span[0]), int(span[1]))
	# 가격은 마릿수에 비례하고, 마리당 단가는 체급이 정한다 (소형 < 중형 < 대형)
	return {"kind": "unit", "def": d, "count": cnt, "price": cnt * int(d["unit_price"])}


func _refresh_shop(units_only: bool) -> void:
	_shop.clear()
	for _i in SHOP_SLOTS:
		_shop.append(_roll_card(units_only))


func _try_reroll() -> void:
	if _gold < _reroll_price:
		return
	_gold -= _reroll_price
	# 「제노바의 환전상」 — 연속 리롤의 가산을 깎는다. 전투가 길어질수록 급한 답이 싸진다
	_reroll_price += int(round(REROLL_STEP * maxf(0.0, 1.0 - _gold_val("reroll_cut"))))
	_refresh_shop(false)


# ─── 유물 굴림 ────────────────────────────────────────────────────────────
# 같은 등급이라도 매물마다 조합이 다르다 — 매직·레어의 옵션은 접두사·접미사로 굴려진다.
# 유니크만 고정 세트라, 한 번 배우면 카드 얼굴만 보고 즉시 판단할 수 있다.
func _roll_relic() -> Dictionary:
	var r: float = _rng.randf()
	if r < 0.14:
		return _make_unique(RELIC_UNIQUES[_rng.randi_range(0, RELIC_UNIQUES.size() - 1)])
	var grade: String = "normal" if r < 0.48 else ("magic" if r < 0.84 else "rare")
	var base: Dictionary = RELIC_BASES[_rng.randi_range(0, RELIC_BASES.size() - 1)]
	var g: Dictionary = RELIC_GRADES[grade]
	var opts: Array = []
	var name: String = str(base["name"])
	# 태그가 좁을수록 수치가 크다 — 한 직업·한 종족으로 칸을 몰면 좁은 태그가
	# [전체]와 같은 범위를 덮으면서 수치는 더 크다
	var mult: float = float(RELIC_TAG_MULT[str(base["tag"])])
	for i in int(g["pre"]):
		var a: Dictionary = RELIC_PREFIX[_rng.randi_range(0, RELIC_PREFIX.size() - 1)]
		opts.append(_roll_opt(a, mult))
		if i == 0:
			name = "%s %s" % [str(a["name"]), name]
	for i in int(g["suf"]):
		var b: Dictionary = RELIC_SUFFIX[_rng.randi_range(0, RELIC_SUFFIX.size() - 1)]
		opts.append(_roll_opt(b, mult))
		if i == 0:
			name = "%s%s" % [name, str(b["name"])]
	return {
		"uid": "%s_%s_%d" % [grade, str(base["id"]), _rng.randi()],
		"grade": grade, "base": base, "tag": str(base["tag"]), "val": str(base["val"]),
		"name": name, "opts": opts, "verb": "", "hits": 0, "grown": 0,
		"price": int(g["price"]), "color": Color(g["color"]),
	}


func _roll_opt(a: Dictionary, mult: float) -> Dictionary:
	var v: float = _rng.randf_range(float(a["min"]), float(a["max"])) * mult
	return {"stat": str(a["stat"]), "elem": str(a.get("elem", "")), "val": v,
		"label": str(a["name"])}


func _make_unique(u: Dictionary) -> Dictionary:
	var base: Dictionary = {}
	for b in RELIC_BASES:
		if str(b["id"]) == str(u["base"]):
			base = b
			break
	var opts: Array = []
	for o in u["opts"]:
		opts.append({"stat": str(o["stat"]), "elem": str(o.get("elem", "")),
			"val": float(o["val"]), "label": "유니크"})
	return {
		"uid": str(u["id"]), "grade": "unique", "base": base,
		"tag": str(base["tag"]), "val": str(base["val"]),
		"name": str(u["name"]), "opts": opts,
		"verb": str(u["verb"]), "hits": int(u["hits"]), "grown": 0,
		"short": str(u["short"]), "desc": str(u["desc"]),
		"price": int(RELIC_GRADES["unique"]["price"]), "color": Color(u["color"]),
	}


# 이 유물의 옵션이 이 부대에 걸리는가 — **태그가 정한다.**
func _relic_covers(r: Dictionary, d: Dictionary) -> bool:
	match str(r["tag"]):
		"job":
			return str(d["job"]) == str(r["val"])
		"race":
			return str(d["race"]) == str(r["val"])
	return true                       # [전체] — 아무 판에나 맞는 바닥


# ─── 옵션·전술 합산 ───────────────────────────────────────────────────────
# 유물 옵션과 전술카드가 같은 눈금을 쓴다. idx 는 격자 칸(-1이면 아직 안 놓인 매물) —
# 「칸」 전술카드는 칠한 칸 위에 선 부대에만 걸리므로 매대 미리보기에는 들어가지 않는다.
func _mods_for(d: Dictionary, idx: int) -> Dictionary:
	var m: Dictionary = {"dmg": 0.0, "spd": 0.0, "crit": 0.0, "critmult": 0.0,
		"flat": 0.0, "elem": {"cold": 0.0, "fire": 0.0, "poison": 0.0, "shock": 0.0}}
	for r in _relics:
		if r == null or not _relic_covers(r, d):
			continue
		for o in r["opts"]:
			# 성장형은 조건(킬)이 충족될 때마다 누적된다. 자란 결과는 상시 수치다
			var v: float = float(o["val"]) * (float(r["grown"]) if str(o["stat"]) == "grow" else 1.0)
			match str(o["stat"]):
				"grow", "dmg":
					m["dmg"] = float(m["dmg"]) + v
				"spd":
					m["spd"] = float(m["spd"]) + v
				"crit":
					m["crit"] = float(m["crit"]) + v
				"critmult":
					m["critmult"] = float(m["critmult"]) + v
				"flat":
					m["flat"] = float(m["flat"]) + v
				"elem":
					var e: String = str(o["elem"])
					(m["elem"] as Dictionary)[e] = float(m["elem"][e]) + v
	# 전술카드 — 조건절이 붙은 카드는 조건에 맞는 부대가 많을수록 저절로 세진다.
	# 시너지를 따로 세는 시스템이 없는 이유가 이것이다(기획 「시너지는 별도 시스템이 아니다」).
	for t in _tactics:
		if t == null or not _tactic_covers(t, d, idx):
			continue
		var st: String = str(t["stat"])
		if st == "dmg_near":
			# 「배수진」 — 보스가 성벽에 가까울수록 오른다. 접근 시작 0 → 도달 직전 val
			m["dmg"] = float(m["dmg"]) + float(t["val"]) * _wall_closeness()
			continue
		if st.begins_with("rule_") or st.begins_with("gold_") \
				or st in ["reroll_cut", "kill_gold", "wave_gold"]:
			continue                  # 규칙·골드 종류는 부대 수치가 아니다
		m[st] = float(m[st]) + float(t["val"])
	# 「비엔나의 돌격」 — 전 부대 치명타 피해. 배수라 크리 공급원(궁수·암살자·유물)이 있어야 산다
	m["critmult"] = float(m["critmult"]) + _rule_val("rule_critmult")
	# 「푸거가의 금고」 — 보유 골드에 비례한다. 쓰지 않고 쥔 골드가 화력이 된다
	m["dmg"] = float(m["dmg"]) + _gold_val("gold_hoard") * (float(_gold) / 100.0)
	return m


# 최근접 보스의 성벽 접근율 — 등장 0.0, 성벽 도달 1.0. 「배수진」이 쓴다.
func _wall_closeness() -> float:
	var b = _target_boss()
	if b == null:
		return 0.0
	return clampf(1.0 - (float(b["x"]) - BOSS_STOP_X) / (BOSS_SPAWN_X - BOSS_STOP_X), 0.0, 1.0)


# 전술카드가 이 부대에 걸리는가 — 「칸」이면 칠한 칸 위여야 하고, 조건절이 있으면 그것도 맞아야 한다.
func _tactic_covers(t: Dictionary, d: Dictionary, idx: int) -> bool:
	if str(t["kind"]) == "cell":
		if idx < 0 or not (t["cells"] as Array).has(idx):
			return false
		# 비어 있어야 하는 칸 — 칸나이(중앙)·청야유인(모서리). 채우면 효과가 통째로 꺼진다
		for e in (t.get("empty", []) as Array):
			if _cells[int(e)] != null:
				return false
	var c: Dictionary = t["cond"]
	if c.has("job") and str(d["job"]) != str(c["job"]):
		return false
	if c.has("race") and str(d["race"]) != str(c["race"]):
		return false
	return true


# 규칙 종류는 게임의 기본 규칙 자체를 바꾼다. 켜져 있는지만 보면 되는 것은 _rule_on,
# 값이 필요한 것은 _rule_val 로 읽는다.
func _rule_on(id: String) -> bool:
	for t in _tactics:
		if t != null and str(t["stat"]) == id:
			return true
	return false


func _rule_val(id: String) -> float:
	var v: float = 0.0
	for t in _tactics:
		if t != null and str(t["stat"]) == id:
			v += float(t["val"])
	return v


func _gold_val(id: String) -> float:
	return _rule_val(id)


func _free_tactic_slot() -> int:
	for i in TACTIC_SLOTS:
		if _tactics[i] == null:
			return i
	return -1


func _has_tactic(id: String) -> bool:
	for t in _tactics:
		if t != null and str(t["id"]) == id:
			return true
	return false


# 조건절에 맞는 부대가 몇 칸인가. **이것이 시너지의 전부다** — 카운트 UI도, 문턱 보너스도 없다.
func _cells_matching(cond: Dictionary) -> int:
	var n: int = 0
	for i in 9:
		var sq = _cells[i]
		if sq == null:
			continue
		if cond.has("job") and str(sq["def"]["job"]) != str(cond["job"]):
			continue
		if cond.has("race") and str(sq["def"]["race"]) != str(cond["race"]):
			continue
		n += 1
	return n


# ─── 부대 ─────────────────────────────────────────────────────────────────
# 한 칸 = 한 부대이고, 칸에 서는 것은 **같은 유닛의 병사들이 모인 무리**다.
# 부대는 병사카드를 부어 체급이 정한 인원 상한까지 자란다 — 이것이 유닛 티어를 대신하는
# 성장 런웨이다. 소형은 오래 걸리지만 계속 자라는 투자형, 대형은 한 장에 완성되는 즉전력이다.
func _make_squad(d: Dictionary, count: int) -> Dictionary:
	var job_id: String = str(d["job"])
	var period: float = maxf(0.05, float(d["period"]))
	return {
		"def": d,
		"members": clampi(count, 1, int(d["cap"])),
		"bless": 0.0,                 # 걸린 축복 합계 — 아래 bless_src 에서 매 프레임 다시 센다
		"bless_src": {},              # 사제 칸 idx → {"amt", "t"}. 사제마다 따로 들고 있어야
		                              # 캐스팅이 반복돼도 자기 몫을 덮어쓰기만 하고 쌓이지 않는다
		"period": period,
		"cd": period,
		"beats": 0,
		"dmg": 0.0,
		"hits": 0,
		"crits": 0,
		# 크리는 스탯이다 — 궁수·암살자만 기본치를 갖고, 나머지는 0이라 영영 안 터진다.
		# 지금은 올릴 공급원이 없지만 자리를 부대에 두는 것이 기획의 "크리는 자란다"와 맞다.
		"crit": float(CRIT_BASE.get(job_id, 0.0)),
		"crit_mult": float(CRIT_MULT_BASE.get(job_id, 2.0)),
		"haste_t": 0.0,               # 공속 버프 남은 시간
		"haste_mult": 1.0,
		# 주박 — 적이 거는 병력 디버프. **일시적이라 시간이 지나면 완전히 회복된다.**
		# 회복에 자원을 쓰게 하지 않는다 — 유료 회복 자원은 성벽 HP 하나로 충분하다(기획).
		"bind": 0.0,                  # 성능 감소율 (0~1)
		"bind_t": 0.0,
		"empower": 0.0,               # 다음 타격 하나에 실릴 고정 추가피해
		"skill_fires": 0,
		"skill_flash": 0.0,
		"flash": 0.0,
		"cast_flash": 0.0,
		"relic_beats": {},            # 유물 id → 쌓인 박자
		"relic_flash": 0.0,
	}


# 인접 판정. **「봉수의 사슬」(규칙)이 여기에 대각선을 더한다** — 사제 옆의 정의가 달라져
# 판을 다시 짜게 된다. 기획이 「규칙 종류가 건드리는 것」 후보로 지목한 항목이다.
func _neighbors(idx: int) -> Array:
	var row: int = idx / 3
	var col: int = idx % 3
	var out: Array = []
	var diag: bool = _rule_on("rule_diag")
	for dr in [-1, 0, 1]:
		for dc in [-1, 0, 1]:
			if dr == 0 and dc == 0:
				continue
			if not diag and dr != 0 and dc != 0:
				continue
			var r2: int = row + dr
			var c2: int = col + dc
			if r2 < 0 or r2 > 2 or c2 < 0 or c2 > 2:
				continue
			out.append(r2 * 3 + c2)
	return out


# 타격당 딜. **체급이 고정한다 — 인원으로 나누지 않는다.**
# 인원이 채워져도 타격당 딜은 변하지 않으므로, 부대가 자라도 관통 프로필이 그대로다 —
# 실루엣과 통함/막힘 표시가 거짓말하지 않는다(기획 「체급」).
# 축복은 타격마다 고정값으로 붙어서, 인원 많고 박자 빠른 부대에서 가장 크게 불어난다.
func _per_hit(sq: Dictionary) -> float:
	var m: Dictionary = _mods_for(sq["def"], _index_of(sq))
	# 데미지 %는 체급이 고정한 타격당 딜에 곱해지고, 고정값(유물 flat·축복)은 그 위에 더해진다.
	# 고정값이라 인원 많고 박자 빠른 부대에서 가장 크게 불어난다.
	var base: float = float(sq["def"]["hit"]) * (1.0 + float(m["dmg"])) \
		+ float(m["flat"]) + float(sq["bless"])
	return maxf(0.0, base * _bind_mult(sq))


# 부대가 지금 선 칸. 「칸」 전술카드가 좌표를 보므로 필요하다 — 자리 교체로 바뀌니 캐시하지 않는다.
func _index_of(sq: Dictionary) -> int:
	for i in 9:
		if _cells[i] == sq:
			return i
	return -1


# 원소 데미지 옵션 — 그 원소로 나가는 것에만 곱해진다
func _elem_amp(d: Dictionary, idx: int, elem: String) -> float:
	if elem == "" or not ELEMENTS.has(elem):
		return 1.0
	return 1.0 + float((_mods_for(d, idx)["elem"] as Dictionary)[elem])


# 병력 디버프의 실효 배율. **인원이 많은 부대일수록 덜 흔들린다** — 머릿수가 완충재다.
# 단독(대형·리더)은 완충재가 없어 정통으로 맞는다(기획 「적이 병력에게 하는 것」).
func _bind_mult(sq: Dictionary) -> float:
	if float(sq["bind"]) <= 0.0:
		return 1.0
	var buffer: float = 2.0 / (1.0 + float(sq["members"]))
	return clampf(1.0 - float(sq["bind"]) * buffer, 0.2, 1.0)


# ─── 데미지 계산 ──────────────────────────────────────────────────────────
# 물리는 빼고, 마법은 곱한다. 성격이 정반대라 보스마다 답이 갈린다.
func _armor_now(boss) -> float:
	if boss == null:
		return 0.0
	return maxf(0.0, float(boss["armor"]) - float(boss["shred"]))


func _res_now(boss, elem: String) -> float:
	if boss == null or elem == "" or not (boss["res"] as Dictionary).has(elem):
		return 0.0
	# 저항 감소는 **원소별 4갈래**다 — 전원소 감소는 존재하지 않는다(기획 「상태이상」).
	# 감소는 여기 한곳에서만 적용한다. 저항은 음수까지 내려가고(100% 초과 피해) 상한만 둔다.
	return minf(float(boss["res"][elem]) - float(boss["res_shred"][elem]), RES_CAP)


func _vuln_mult(boss) -> float:
	if boss == null:
		return 1.0
	return 1.0 + float(boss["vuln"])


# 물리 — 감산. 최소 보장은 두지 않는다. 딜이 방어력 이하면 0이다.
# **다만 「로마의 필룸」(규칙 전술카드)이 최소 보장을 만든다** — 딜 0인 칸이 되살아난다.
# 기획이 「규칙 종류가 건드리는 것」 후보로 직접 지목한 항목이라 그대로 태운다.
# 보장 1.0은 감산을 통째로 껐다(2차 개조 봇이 딜 0 타격 0%로 무피해 클리어) — 값을 카드가 갖는다.
func _phys_damage(per: float, boss) -> float:
	if boss == null:
		return per
	var out: float = maxf(0.0, per - _armor_now(boss))
	if out <= 0.0 and per > 0.0:
		out = minf(per, _rule_val("rule_floor"))
	return out * _vuln_mult(boss)


# **명중 판정은 물리에만 있다. 마법은 무조건 적중한다**(기획 「데미지 계산」).
# 로스터가 물리에 크게 기울어 있어(30유닛 중 마법 딜러 5), 물리에만 붙는 비용이 없으면
# 마법을 고를 이유가 얇아진다. 적의 대응 축은 회피다.
#
# **빗나감 = 0.** 「빗나감이 0인가 약화된 타격인가」는 「미결」이고, 프로토가 한쪽 극단을
# 골라 태운 것이다 — 단독(대형)이 한 박자를 통째로 날리는 체감이 실제로 어떤지 보기 위해서다.
func _phys_hits(boss) -> bool:
	if boss == null:
		return true
	return _rng.randf() >= float(boss["evade"])


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
		"entry": entry,
		"base": entry["base"],
		"boss": bool(entry["boss"]),
		"index": int(entry["index"]),
		"tags": _entry_tags(entry),
		"x": BOSS_SPAWN_X,
		"lane_y": BOSS_BASE_Y + float((_bosses.size() % 3) - 1) * 44.0,
		"hp": float(entry["hp"]),
		"hp_max": float(entry["hp"]),
		"armor": float(entry["armor"]),
		"armor_base": float(entry["armor"]),   # 경화가 여기 위로 쌓인다
		"evade": float(entry["evade"]),
		"res": (entry["res"] as Dictionary).duplicate(),
		"wall_dmg": float(entry["wall_dmg"]),
		"regen": float(entry["regen"]),
		"harden": float(entry["harden"]),
		"frenzy": float(entry["frenzy"]),
		"bind": bool(entry["bind"]),
		"bind_cd": BIND_INTERVAL,
		"gold": int(entry["gold"]),
		"speed": float(entry["speed"]),
		"push_res": float(entry["push_res"]),
		"wall_cd": 0.0,
		# 상태이상 9종 — 보스도 아군도 걸릴 수 있는 공용 개념이지만, 프로토는 보스 쪽만 태운다
		"chill": 0.0,                 # 빙결 — 이동·공격속도 저하
		"burn": 0, "burn_t": 0.0,     # 화상 — 회복 감소 (틱딜 아님)
		"pois": 0, "pois_t": 0.0,     # 중독 — 지속딜
		"vuln": 0.0, "vuln_t": 0.0,   # 취약 — 받는 피해 비율 증가
		"shred": 0.0, "shred_t": 0.0, # 파쇄 — 방어력 감소
		# 저항 감소 — 원소별 4갈래. 각각 따로 걸리고 따로 풀린다
		"res_shred": {"cold": 0.0, "fire": 0.0, "poison": 0.0, "shock": 0.0},
		"res_shred_t": {"cold": 0.0, "fire": 0.0, "poison": 0.0, "shock": 0.0},
		# 저주 — 걸린 동안 아군 타격마다 고정 추가피해. 넉백은 x 를 직접 되돌린다
		"curse": 0.0, "curse_t": 0.0,
		"stun": 0.0,                  # 스턴 — 모든 행동 정지 + 캐스팅 초기화
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
	return clampf(1.0 - float(b["push_res"]) - float(b["alive"]) * 0.020, 0.12, 1.0)


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
	for e in ELEM_ORDER:
		if float(b["res_shred"][e]) > 0.0:
			out.append("%s저항 -%d%%" % [str(ELEMENTS[e]["short"]),
				int(round(float(b["res_shred"][e]) * 100.0))])
	if float(b["curse"]) > 0.0:
		out.append("저주 +%.0f/타" % float(b["curse"]))
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

	var dt: float = delta
	_elapsed += dt

	# 시간 골드 — 킬만으로는 쇼핑이 게임플레이가 되지 못한다. 시간이 바닥을 깔고
	# 킬이 템포를 보상한다(기획 「골드는 두 곳에서 나온다」).
	_gold_frac += (GOLD_PER_SEC + _gold_val("gold_sec")) * dt
	if _gold_frac >= 1.0:
		var whole: int = int(_gold_frac)
		_gold += whole
		_gold_frac -= float(whole)

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
		b["curse_t"] = maxf(0.0, float(b["curse_t"]) - dt)
		if float(b["curse_t"]) <= 0.0:
			b["curse"] = 0.0
		# 저항 감소는 원소마다 따로 걸리고 따로 풀린다
		for e in ELEM_ORDER:
			if float(b["res_shred"][e]) <= 0.0:
				continue
			b["res_shred_t"][e] = maxf(0.0, float(b["res_shred_t"][e]) - dt)
			if float(b["res_shred_t"][e]) <= 0.0:
				b["res_shred"][e] = 0.0

		# 화상 — **회복 감소만** 한다. 틱딜은 중독의 몫이라 여기서 겹치지 않는다
		if int(b["burn"]) > 0:
			b["burn_t"] = float(b["burn_t"]) - dt
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

		# 경화 — 시간이 갈수록 방어력이 오른다. 장기전을 막으므로 답은 빠른 킬이나 파쇄다.
		# **상한을 둔다.** 상한이 없으면 긴 싸움에서 방어력이 무한히 올라 어느 순간 전 편성이
		# 수학적으로 무력화된다 — 기획이 엔드리스를 배제한 이유("감산 방어는 스탯 인플레와
		# 양립이 안 된다")와 같은 문제다. 상한값은 「미결」이라 프로토가 임의로 골랐다.
		if float(b["harden"]) > 0.0:
			b["armor"] = float(b["armor_base"]) \
				+ minf(HARDEN_CAP, float(b["harden"]) * float(b["alive"]))

		if float(b["stun"]) > 0.0:
			if float(b["hp"]) <= 0.0:
				_kill(b)
			continue                  # 스턴 — 모든 행동 정지

		# 주박 — 적은 병력을 때리지 못하지만 성능은 떨어뜨린다. 반격 없는 전투에
		# **전투 중 사건**을 공급하는 유일한 통로다. 병력은 사라지지 않으므로
		# 죽음의 소용돌이는 생기지 않는다.
		if bool(b["bind"]):
			b["bind_cd"] = float(b["bind_cd"]) - dt
			if float(b["bind_cd"]) <= 0.0:
				b["bind_cd"] = BIND_INTERVAL
				_cast_bind()

		var spd: float = float(b["speed"])
		# 광폭 — 체력이 낮아질수록 빨라진다. 마무리 못 하는 편성을 처벌한다.
		if float(b["frenzy"]) > 0.0:
			var lost: float = 1.0 - float(b["hp"]) / maxf(1.0, float(b["hp_max"]))
			spd *= 1.0 + float(b["frenzy"]) * lost
		if float(b["chill"]) > 0.0:
			spd *= CHILL_MOVE

		if float(b["x"]) > BOSS_STOP_X:
			b["x"] = maxf(BOSS_STOP_X, float(b["x"]) - spd * dt)
			if float(b["x"]) <= BOSS_STOP_X:
				b["wall_cd"] = float(b["base"]["wall_int"]) * 0.5
		else:
			# 빙결은 공격속도도 떨어뜨린다
			var atk_dt: float = dt * (CHILL_MOVE if float(b["chill"]) > 0.0 else 1.0)
			b["wall_cd"] = float(b["wall_cd"]) - atk_dt
			if float(b["wall_cd"]) <= 0.0:
				b["wall_cd"] = float(b["wall_cd"]) + float(b["base"]["wall_int"])
				var dmg: float = float(b["wall_dmg"])
				# 「용병의 방패삯」 — 성벽 HP 대신 골드가 먼저 소모된다 (HP 1당 rate 골드).
				# 성벽은 런 관통 자원이고 골드는 매 판 흐르는 자원이라, 환율이 곧 카드 값이다
				var rate: float = _gold_val("gold_shield")
				if rate > 0.0 and _gold > 0:
					var absorb: float = minf(dmg, floorf(float(_gold) / rate))
					_gold -= int(ceili(absorb * rate))
					dmg -= absorb
				_wall_hp -= dmg
				_log_wall_lost += dmg
				_wall_flash = 1.0

		if float(b["hp"]) <= 0.0:
			_kill(b)


# 주박이 병력에 거는 디버프. **어디에 걸리는지는 「미결」**(전체인지 칸을 지정하는지)이라
# 프로토는 배치된 칸 중 랜덤 하나를 골랐다 — 그래야 "이 칸이 지금 흔들린다"가 화면에서 읽힌다.
func _cast_bind() -> void:
	var live: Array = []
	for i in 9:
		if _cells[i] != null:
			live.append(i)
	if live.is_empty():
		return
	var sq: Dictionary = _cells[live[_rng.randi_range(0, live.size() - 1)]]
	sq["bind"] = maxf(float(sq["bind"]), BIND_AMOUNT)
	sq["bind_t"] = maxf(float(sq["bind_t"]), BIND_DURATION)


func _kill(b: Dictionary) -> void:
	b["hp"] = 0.0
	b["dead"] = true
	b["death_t"] = 0.9
	_killed += 1
	# 「사략 허가장」 — 킬 골드 배율. 조건절이 붙어 있으면 맞는 칸마다 — 몰빵의 보상이다
	var bonus: float = 0.0
	for t in _tactics:
		if t == null or str(t["stat"]) != "kill_gold":
			continue
		var c: Dictionary = t["cond"]
		bonus += float(t["val"]) * (float(_cells_matching(c)) if not c.is_empty() else 1.0)
	_gold += int(round(float(b["gold"]) * (1.0 + bonus)))
	# 「개선식의 전리품」 — 적 하나를 넘길 때마다 목돈이 따로 떨어진다
	_gold += int(round(_gold_val("wave_gold")))
	# **성장형 유물 옵션이 여기서 자란다.** 조건은 자라는 속도를 정할 뿐이고,
	# 자란 결과는 상시 수치라 유물의 영역이다(기획 「유물 — 등급과 태그」).
	for r in _relics:
		if r == null:
			continue
		for o in r["opts"]:
			if str(o["stat"]) == "grow":
				r["grown"] = int(r["grown"]) + 1
				break
	_last_kill_at = _elapsed
	_pull_at = _elapsed + ADAPTIVE_REST
	_log_kill_times.append(_elapsed - float(b["born_at"]))
	# **강제 갱신은 없다.** 매대를 바꾸는 것은 플레이어의 리롤뿐이다 — 킬로 저절로 갈리면
	# 마음에 든 매물을 놓칠까 봐 서두르게 된다(기획 「매물 규칙」).
	# 킬이 주는 것은 목돈과 "리롤가 원가 복귀" 둘뿐이다.
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
		sq["skill_flash"] = maxf(0.0, float(sq["skill_flash"]) - dt * 2.0)
		sq["haste_t"] = maxf(0.0, float(sq["haste_t"]) - dt)
		if float(sq["haste_t"]) <= 0.0:
			sq["haste_mult"] = 1.0
		# 디버프로 잃은 성능은 시간이 지나면 **완전히** 회복된다. 누적되지 않는다.
		sq["bind_t"] = maxf(0.0, float(sq["bind_t"]) - dt)
		if float(sq["bind_t"]) <= 0.0:
			sq["bind"] = 0.0
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
			sq["cd"] = float(sq["cd"]) + _period_now(sq)
			sq["beats"] = int(sq["beats"]) + 1
			var job: Dictionary = JOBS[sq["def"]["job"]]
			var strikes: int = 0
			if bool(job["cast"]):
				strikes = _do_cast(idx, sq, target)
			else:
				strikes = _do_basic(idx, sq, target)
			# 유물은 **타격 수**로 찬다 — 박자가 아니다. 스택이 타격마다 붙으므로
			# 인원이 곧 스택 속도가 된다(기획 「상태이상」). 다수 부대는 방어력에 막히는 대신
			# 상태이상을 빨리 쌓고, 소수정예는 뚫는 대신 느리게 쌓는다.
			_tick_relics(sq, target, strikes)
			target = _target_boss()


# 지금 이 부대의 실제 박자. 공속 버프(HASTE)와 유물·전술의 공격속도 옵션이 주기를 나눈다.
func _period_now(sq: Dictionary) -> float:
	var spd: float = 1.0 + float(_mods_for(sq["def"], _index_of(sq))["spd"])
	return maxf(0.05, float(sq["period"]) / maxf(0.1, float(sq["haste_mult"]) * spd))


# 스턴을 맞으면 캐스팅 사이클이 통째로 날아간다 — 평타가 없어 그동안 아무것도 못 한다
# (기획 「직업」). 지금은 아군에게 스턴을 거는 공급원이 없어 아무도 부르지 않는다.
# 훅만 세워둔다 — 보스 디버프가 들어오면 그것이 여기로 온다.
func _stun_squad(sq: Dictionary) -> void:
	sq["cd"] = _period_now(sq)
	sq["cast_flash"] = 0.0


# 평타 — 한 박자에 인원 수만큼 개별 판정. 부대원이 각자 자기 주기로 때리지 않는다.
# 타격당 딜은 체급이 고정하므로, 인원이 늘면 **총 화력이 그만큼 는다.**
# 인원 하나의 판정 순서:
#   ① 명중 굴림 — **물리에만 있다.** 빗나가면 그 타격은 통째로 0이다
#   ② 크리 굴림 (모든 유닛이 갖는 공통 스탯. 기본 0이라 공급원이 있어야 터진다)
#   ③ 발동 판정 — 크리 직업은 크리가 곧 발동, 확률 직업은 스킬에 박힌 고정 확률
#   ④ 스킬이 돌려준 타격 변형(추가타·배율·마법 전환·고정딜)을 그 타격에 반영
# 돌려주는 값은 **실제로 나간 타격 수**다 — 유물이 이것으로 찬다.
func _do_basic(idx: int, sq: Dictionary, target) -> int:
	if target == null or target["dead"]:
		return 0
	var idx0: int = _index_of(sq)
	var mods: Dictionary = _mods_for(sq["def"], idx0)
	var trigger: String = str(JOBS[sq["def"]["job"]]["trigger"])
	var chance: float = float(sq["def"]["skill"]["chance"])
	var per: float = _per_hit(sq)
	var curse: float = float(target["curse"])
	var total: float = 0.0
	var landed: int = 0
	# **「테베의 팔랑크스」(규칙)가 인원 판정을 하나로 묶는다** — 한 박자에 인원 수만큼
	# 쪼개 때리던 것을 한 방으로 합친다. 다수 부대가 감산을 뚫게 되는 대신,
	# 타격 수가 1이 되어 상태이상 스택 속도와 유물 발동이 함께 느려진다.
	var rolls: int = 1 if _rule_on("rule_unify") else int(sq["members"])
	if rolls < int(sq["members"]):
		per *= float(sq["members"])
	# 크리는 모든 유닛의 공통 스탯이고, 유물·전술이 그 위에 얹는다
	var crit_p: float = float(sq["crit"]) + float(mods["crit"])
	var crit_m: float = float(sq["crit_mult"]) + float(mods["critmult"])
	for _m in rolls:
		var crit: bool = crit_p > 0.0 and _rng.randf() < crit_p
		if crit:
			sq["crits"] = int(sq["crits"]) + 1
		var fire: bool = crit if trigger == "crit" \
			else (trigger == "chance" and _rng.randf() < chance)
		var fx: Dictionary = _fire_skill(idx, sq, target) if fire else _no_fx()
		# EMPOWER_STRIKE 가 얹어둔 몫은 다음 타격 하나가 소비한다
		var emp: float = float(sq["empower"])
		sq["empower"] = 0.0
		var hit: float = (per + emp + float(fx["bonus"])) * float(fx["amp"])
		if crit:
			hit *= crit_m
		var one: float = 0.0
		var shots: int = 1 + int(fx["extra_hits"])
		if str(fx["convert"]) != "":
			# MAGIC_STRIKE — 그 타격만 마법으로 나간다. 감산이 아니라 비율을 타고,
			# **마법이 된 순간 명중 판정도 사라진다** — 마법은 무조건 적중한다
			one = _mag_damage(hit * _elem_amp(sq["def"], idx0, str(fx["convert"])),
				str(fx["convert"]), target)
		elif not _phys_hits(target):
			# 빗나감 — 그 타격은 통째로 날아간다. 저주도 함께 날아간다(타격이 없었으므로)
			_log_total_hits += shots
			_log_missed += shots
			_log_phys_raw += hit * float(shots)
			continue
		else:
			one = _phys_damage(hit, target)
			_log_phys_raw += hit
			_log_phys_out += one
			_log_total_hits += 1
			if one <= 0.0:
				_log_zero_hits += 1
		# 저주는 타격마다 붙는 고정 추가피해다. 통함/막힘 미리보기가 _phys_damage 를 그대로
		# 쓰므로 그 안에 넣지 않고 **여기서** 더한다 — 미리보기가 거짓말을 하면 안 된다.
		one += curse
		total += one * float(shots)
		landed += shots
	if landed > 0:
		sq["hits"] = int(sq["hits"]) + landed
		sq["flash"] = 1.0
	if total <= 0.0:
		return landed
	target["hp"] = float(target["hp"]) - total
	target["flash"] = 1.0
	sq["dmg"] = float(sq["dmg"]) + total
	if float(target["hp"]) <= 0.0:
		_kill(target)
	return landed


# 캐스팅 — 평타를 포기한 둘. 캐스팅 자체가 곧 발동이라 스킬 엔진에 넘기기만 한다.
# 대상만 다르다: 마법사는 보스에게, 사제는 아군에게 — 그 갈림도 CSV의 target 컬럼이 정한다.
#
# **캐스터도 인원 축을 탄다 — 인원수가 곧 시전 횟수다**(기획 「인원이 하는 일」).
# 소형 캐스터는 작은 마법을 여럿이, 체급이 클수록 굵은 마법을 소수가 시전한다.
# 사제가 ALLY_RANDOM 이면 시전마다 대상을 다시 굴리므로, 소형 사제는 얇은 축복을
# 여러 칸에 흩고 중형 사제는 굵게 몇 칸에 건다 — 같은 규칙에서 저절로 갈린다.
func _do_cast(idx: int, sq: Dictionary, target) -> int:
	sq["cast_flash"] = 1.0
	var n: int = int(sq["members"])
	for _m in n:
		if _cells[idx] == null:
			break
		_fire_skill(idx, sq, target)
	return n


# ─── 스킬 엔진 ────────────────────────────────────────────────────────────
# 유닛 고유 스킬은 전부 이 한 match 를 지난다. 직업은 "언제"만 정하고, "무엇을"은
# skills.csv 의 effect 가 정한다. 모르는 effect 는 조용히 흘려보낸다 —
# CSV가 프로토보다 먼저 자라도 게임이 죽으면 안 된다.
#
# 리턴 dict 는 **그 타격 하나**를 어떻게 바꿀지다 (평타 직업만 읽는다):
#   extra_hits — 같은 타격을 몇 번 더 낼지
#   amp        — 그 타격에 곱할 배율 (크리 배율에 다시 곱해진다)
#   convert    — 빈 문자열이 아니면 그 원소의 마법으로 나간다
#   bonus      — 타격당 고정 추가피해
func _no_fx() -> Dictionary:
	return {"extra_hits": 0, "amp": 1.0, "convert": "", "bonus": 0.0}


# 원소는 발동할 때마다 굳힌다 — 수인족의 "랜덤"은 색이 없는 게 아니라 매번 굴리는 것이 색이다.
func _elem_of(sq: Dictionary) -> String:
	var e: String = str(sq["def"]["elem"])
	if e == "random":
		return str(ELEM_ORDER[_rng.randi_range(0, ELEM_ORDER.size() - 1)])
	return e


# 대상 해석은 CSV의 target 컬럼이 한다.
# ALLY / ALLY_RANDOM = 배치된 부대 중 랜덤 하나, ALLY_ADJACENT = 인접한 배치 칸 전부.
# (ALLY_ADJACENT 는 리더 전용이라 지금 풀에는 없다 — 문법만 열어둔다)
func _skill_targets(idx: int, sk: Dictionary) -> Array:
	var out: Array = []
	match str(sk["target"]):
		"SELF":
			out.append(idx)
		"ALLY_ADJACENT":
			for j in _neighbors(idx):
				if _cells[j] != null:
					out.append(j)
		"ALLY", "ALLY_RANDOM":
			var live: Array = []
			for j in 9:
				if _cells[j] != null:
					live.append(j)
			if not live.is_empty():
				out.append(live[_rng.randi_range(0, live.size() - 1)])
	return out


func _fire_skill(idx: int, sq: Dictionary, target) -> Dictionary:
	var fx: Dictionary = _no_fx()
	var sk: Dictionary = sq["def"]["skill"]
	var eff: String = str(sk["effect"])
	sq["skill_fires"] = int(sq["skill_fires"]) + 1
	sq["skill_flash"] = 1.0
	_log_skill_fires[eff] = int(_log_skill_fires.get(eff, 0)) + 1
	var dur: float = float(sk["dur"])
	var mult: float = float(sk["multiplier"])
	var amount: float = float(sk["damage"])
	match eff:
		"NUKE", "NUKE_RANDOM", "NUKE_FREEZE":
			# 시전당 딜은 체급이 정하고, 인원은 시전 횟수를 정한다. **마법은 무조건 적중한다** —
			# 명중 판정은 물리에만 있다. 다만 마법은 비율이라 시전이 굵든 잘든 총딜이 같다:
			# 관통을 두고 다수 vs 소수정예를 고르는 선택이 마법 쪽에는 성립하지 않는다(기획).
			if target == null or target["dead"]:
				return fx
			var elem: String = _elem_of(sq)
			# 원소 데미지 옵션은 그 원소로 나가는 것에만 곱해진다 — 몰빵의 보상이 여기서도 난다
			var amt: float = _per_hit(sq) * _elem_amp(sq["def"], idx, elem)
			var one: float = _mag_damage(amt, elem, target) + float(target["curse"])
			target["hp"] = float(target["hp"]) - one
			target["flash"] = 1.0
			sq["dmg"] = float(sq["dmg"]) + one
			sq["hits"] = int(sq["hits"]) + 1
			sq["flash"] = 1.0
			if eff == "NUKE_FREEZE":
				# 냉기 계열은 딜을 낮게 잡는 대신 자기 상태이상을 함께 싣는다(설계 지침)
				_apply_chill(target, dur)
			if float(target["hp"]) <= 0.0:
				_kill(target)
		"HASTE":
			for j in _skill_targets(idx, sk):
				_grant_haste(_cells[j], mult, dur)
		"BUFF_ATK", "PACT_BUFF":
			# PACT_BUFF 의 "대가"(사기 감소)는 미구현이다 — 사기 시스템 자체가 「미결」이라
			# 이득만 넣고 그만큼 값을 크게 잡았다
			_grant_bless(idx, sq, sk, _bless_amount(sq))
		"BUFF_RANDOM":
			# 수인족은 주사위가 정체성이다 — 축복이 나올지 공속이 나올지 매번 굴린다
			if _rng.randf() < 0.5:
				_grant_bless(idx, sq, sk, _bless_amount(sq))
			else:
				for j in _skill_targets(idx, sk):
					_grant_haste(_cells[j], mult, dur)
		"EXTRA_STRIKE", "EXTRA_SHOT":
			fx["extra_hits"] = 1
		"CRIT_AMP", "HEAVY_STRIKE":
			fx["amp"] = mult
		"CRIT_BONUS_FLAT":
			fx["bonus"] = amount
		"EMPOWER_STRIKE":
			sq["empower"] = float(sq["empower"]) + amount
		"MAGIC_STRIKE":
			fx["convert"] = _elem_of(sq)
			fx["amp"] = mult
		"VULNERABLE":
			if target != null and not target["dead"]:
				_apply_vuln(target, mult, dur)
		"GOLD_STEAL":
			_gold += int(amount)
		"CLEANSE":
			# 주박이 들어오면서 정화할 것이 생겼다 — 「주박」 접두사의 답 중 하나다
			for j in _skill_targets(idx, sk):
				_cells[j]["bind"] = 0.0
				_cells[j]["bind_t"] = 0.0
		_:
			pass    # 리더 전용(MORALE·KILL_STACK_ATK·DEVOUR_STACK) 등 아직 없는 effect
	return fx


# 축복량도 체급이 정한다 — 대형 사제는 굵게 한 칸, 소형 사제는 얇게 여러 칸.
# **축복 자체에는 축복이 붙지 않는다** (_per_hit 이 아니라 def.hit 을 쓴다) —
# 사제끼리 서로 부풀리는 되먹임을 막는다. 주박은 그대로 탄다.
func _bless_amount(sq: Dictionary) -> float:
	return float(sq["def"]["hit"]) * _bind_mult(sq)


# 축복 — 사제 칸 idx 를 열쇠로 둔다. 같은 사제의 재캐스팅은 자기 몫을 덮어쓸 뿐이고,
# 사제가 둘이면 둘 다 걸린다(기획 「효과는 전부 중첩된다」).
# 고정값이라 인원 많고 박자 빠른 부대에서 가장 크게 불어난다.
func _grant_bless(idx: int, sq: Dictionary, sk: Dictionary, amount: float) -> void:
	if amount <= 0.0:
		return
	for j in _skill_targets(idx, sk):
		_cells[j]["bless_src"][idx] = {"amt": amount, "t": float(sq["period"]) * BLESS_HOLD}


func _grant_haste(sq, mult: float, dur: float) -> void:
	if sq == null or mult <= 1.0 or dur <= 0.0:
		return
	sq["haste_mult"] = maxf(float(sq["haste_mult"]), mult)
	sq["haste_t"] = maxf(float(sq["haste_t"]), dur)


# ─── 상태이상 부여 ────────────────────────────────────────────────────────
# 유물과 유닛 스킬이 같은 문을 쓴다 — 부여원이 둘이라 규칙이 갈리면 곧 어긋난다.
# 저항은 여기서 한 번만 본다: 원소 저항 하나가 두 일을 한다 —
# 그 원소 피해의 감소율이면서, 그 원소 상태이상의 저항이다(기획 「상태이상」).
func _apply_chill(b, sec: float) -> void:
	if b == null:
		return
	b["chill"] = maxf(float(b["chill"]), sec * (1.0 - _res_now(b, "cold")))


func _apply_burn(b, stacks: int) -> void:
	if b == null:
		return
	b["burn"] = mini(12, int(b["burn"]) + maxi(1, stacks))
	b["burn_t"] = BURN_DURATION


func _apply_poison(b, stacks: int) -> void:
	if b == null:
		return
	b["pois"] = mini(12, int(b["pois"]) + maxi(1, stacks))
	b["pois_t"] = POISON_DURATION


func _apply_vuln(b, amount: float, dur: float) -> void:
	if b == null:
		return
	b["vuln"] = maxf(float(b["vuln"]), amount * (1.0 - _res_now(b, "shock")))
	b["vuln_t"] = maxf(float(b["vuln_t"]), maxf(dur, VULN_DURATION))


# 파쇄는 **방어력만** 깎는다. 원소 저항은 아래 _apply_res_shred 가 원소별로 따로 깎는다.
func _apply_shred(b, amount: float) -> void:
	if b == null:
		return
	b["shred"] = minf(float(b["armor"]), float(b["shred"]) + amount)
	b["shred_t"] = SHRED_DURATION


# 저항 감소 — 원소별 4갈래. **부여원이 아직 없다**(유물 재정의가 「보류」라 공급처가 비었다).
# 계산 경로(_res_now)만 살려두고 문은 열어둔다.
func _apply_res_shred(b, elem: String, amount: float) -> void:
	if b == null or not (b["res_shred"] as Dictionary).has(elem):
		return
	b["res_shred"][elem] = float(b["res_shred"][elem]) + amount
	b["res_shred_t"][elem] = RES_SHRED_DURATION


func _apply_stun(b, sec: float) -> void:
	if b == null:
		return
	b["stun"] = maxf(float(b["stun"]), sec)


# 저주 — 아군 타격마다 고정 추가피해. **부여원이 아직 없다**(고급 상태라 공급처가 미결).
# 취약과 증폭의 두 갈래를 이룬다 — 저주는 타격 횟수 많은 다수와, 취약은 소수정예와 맞는다.
func _apply_curse(b, amount: float) -> void:
	if b == null:
		return
	b["curse"] = maxf(float(b["curse"]), amount)
	b["curse_t"] = CURSE_DURATION


func _apply_push(b, dist: float) -> void:
	if b == null:
		return
	b["x"] = minf(BOSS_SPAWN_X, float(b["x"]) + dist * _push_mult(b))
	b["push_flash"] = 1.0
	if float(b["x"]) > BOSS_STOP_X:
		b["wall_cd"] = 0.0            # 성벽 타격 중에 밀리면 피해가 즉시 멎는다


# ─── 유물 발동 ────────────────────────────────────────────────────────────
# 쿨다운이 초가 아니라 **타격 수**로 찬다. 스택은 타격마다 붙으므로 인원이 곧 스택 속도다 —
# 같은 밀어내기도 다수 부대에선 잦고 작게, 소수정예에선 드물고 크게 나간다.
# 동사의 변형을 체급 시스템이 공짜로 만든다(기획 「상태이상」·「구성 요소」).
func _tick_relics(sq: Dictionary, target, strikes: int) -> void:
	if strikes <= 0:
		return
	for r in _relics:
		# **동사를 가진 것은 유니크뿐이다.** 나머지 등급은 옵션만 얹으므로 발동할 것이 없다
		if r == null or str(r["verb"]) == "":
			continue
		if not _relic_covers(r, sq["def"]):
			continue
		var id: String = str(r["uid"])
		var n: int = int(sq["relic_beats"].get(id, 0)) + strikes
		var need: int = int(r["hits"])
		if n < need:
			sq["relic_beats"][id] = n
			continue
		sq["relic_beats"][id] = n % need
		if target == null or target["dead"]:
			continue
		_fire_relic(r, sq, target)


func _fire_relic(r: Dictionary, sq: Dictionary, target: Dictionary) -> void:
	sq["relic_flash"] = 1.0
	_log_relic_fires += 1
	# 효과량은 그 부대의 타격당 딜에 비례한다 — 체급이 그 값을 고정하므로,
	# 대형 하나가 거는 밀어내기는 소형 아홉이 거는 것보다 한 번에 훨씬 크다.
	var per: float = maxf(1.0, _per_hit(sq))
	# 부여는 스킬과 같은 문(_apply_*)을 쓴다 — 저항·상한 규칙이 한곳에만 있어야 어긋나지 않는다
	match str(r["verb"]):
		"push":
			_apply_push(target, clampf(70.0 + per * 1.6, 70.0, 340.0))
		"shred":
			_apply_shred(target, clampf(per * 0.55, 2.0, 12.0))
		"chill":
			_apply_chill(target, clampf(1.6 + per * 0.05, 1.6, 5.0))
		"burn":
			_apply_burn(target, 1 + int(per / 8.0))
		"poison":
			_apply_poison(target, 1 + int(per / 10.0))
		"vuln":
			_apply_vuln(target, clampf(0.12 + per * 0.010, 0.12, 0.45), VULN_DURATION)
		"stun":
			_apply_stun(target, STUN_DURATION)


# 이 유물의 옵션을 실제로 받고 있는 칸이 몇 개인가 — 태그가 내 판과 맞는지의 눈금이다
func _relic_live(r: Dictionary) -> int:
	var n: int = 0
	for sq in _cells:
		if sq != null and _relic_covers(r, sq["def"]):
			n += 1
	return n


# 유니크는 같은 것을 두 번 갖지 않는다. 굴려진 매직·레어는 매물마다 다르므로 중복 개념이 없다.
func _has_relic(uid: String) -> bool:
	for r in _relics:
		if r != null and str(r["uid"]) == uid:
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
			KEY_ESCAPE:
				_pin_kind = ""
		return

	if _paused or _phase != Phase.RUNNING:
		return
	if not event is InputEventMouseButton:
		return
	# 성벽 우클릭 = 최대 HP 업그레이드. 패널이 사라져서(3차) 성벽이 자기 구매를 다 받는다
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed and WALL_RECT.grow(10.0).has_point(event.position):
			_try_upgrade()
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
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
	# 수리는 성벽을 직접 클릭한다 — 얻어맞는 그 자리를 고치는 조작이 직관이다.
	# 보스 핀보다 먼저 본다: 수리가 급한 것은 보스가 성벽에 붙은 초읽기 순간이라서다
	if WALL_RECT.grow(10.0).has_point(mp):
		_try_repair()
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
	for i in TACTIC_SLOTS:
		if _tactic_rect(i).has_point(mp) and _tactics[i] != null:
			_toggle_pin("tactic", i)
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
		if to >= 0:
			if to != from:
				var tmp = _cells[to]                # 재배치는 즉시·무료 (미결 항목의 한쪽 극단)
				_cells[to] = _cells[from]
				_cells[from] = tmp
			return
		# 격자 밖으로 끌어내면 **부대를 뺀다.** 칸을 다른 유닛으로 바꾸려면 먼저 빼내야 한다.
		# 「빼낸 부대의 처리」는 「미결」이라 프로토가 한쪽 극단을 골랐다 — **환불 없이 사라진다.**
		if not _shop_area(mp):                      # 매대 위에 떨군 것은 오조작으로 보고 무시한다
			_cells[from] = null
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
		# 병사카드는 **빈 칸이나 같은 유닛의 칸에만** 놓인다. 다른 유닛 위에는 못 놓는다 —
		# 칸을 갈아치우려면 기존 부대를 먼저 빼내야 한다(기획 「배치」).
		var sq2 = _cells[to2]
		var cnt: int = int(card["count"])
		if sq2 == null:
			_cells[to2] = _make_squad(card["def"], cnt)
		elif str(sq2["def"]["id"]) == str(card["def"]["id"]):
			# 카드의 마릿수가 부대에 합쳐지고, 체급이 정한 상한까지 자란다.
			# **상한을 넘는 마릿수는 사라진다** — 만석에 붓는 것은 플레이어의 손해다.
			sq2["members"] = mini(int(sq2["def"]["cap"]), int(sq2["members"]) + cnt)
			sq2["flash"] = 1.0
		else:
			return                                  # 다른 유닛의 칸 — 취소·무과금
	elif card["kind"] == "relic":
		var slot: int = _relic_at(mp)
		if slot < 0:
			return                                  # 유물은 유물 슬롯 줄에만 놓인다
		if _has_relic(str(card["def"]["uid"])):
			return                                  # 같은 유니크를 두 번 갖지 않는다
		_relics[slot] = card["def"]
		for sq in _cells:
			if sq != null:
				sq["relic_beats"][str(card["def"]["uid"])] = 0
	else:
		# 전술카드는 전술 슬롯 줄에만 놓인다 — 목적지가 문법을 정한다
		var tslot: int = _tactic_at(mp)
		if tslot < 0:
			return
		if _has_tactic(str(card["def"]["id"])):
			return                                  # 같은 전술을 두 번 갖지 않는다
		_tactics[tslot] = card["def"]
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


# 매대·유물 줄 위 — 부대를 여기에 떨군 것은 빼내려던 게 아니라 오조작으로 본다.
# 전투를 곁눈질하며 조작하는 게임에서 오클릭이 부대 상실이 되면 안 된다.
func _shop_area(mp: Vector2) -> bool:
	return mp.y >= SHOP_ORIGIN.y


func _relic_at(mp: Vector2) -> int:
	for i in RELIC_SLOTS:
		if _relic_rect(i).has_point(mp):
			return i if _relics[i] == null else _free_relic_slot()
	return -1


func _tactic_at(mp: Vector2) -> int:
	for i in TACTIC_SLOTS:
		if _tactic_rect(i).has_point(mp):
			return i if _tactics[i] == null else _free_tactic_slot()
	return -1


# ─── 히트박스 ─────────────────────────────────────────────────────────────
func _cell_rect(idx: int) -> Rect2:
	return Rect2(GRID_ORIGIN + Vector2(float(idx % 3) * CELL, float(idx / 3) * CELL),
		Vector2(CELL - CELL_PAD, CELL - CELL_PAD))


func _card_rect(idx: int) -> Rect2:
	return Rect2(SHOP_ORIGIN + Vector2(float(idx) * (CARD.x + CARD_GAP), 0.0), CARD)


func _relic_rect(idx: int) -> Rect2:
	return Rect2(RELICROW_ORIGIN + Vector2(float(idx) * (RELIC_SLOT.x + RELIC_GAP), 0.0), RELIC_SLOT)


func _tactic_rect(idx: int) -> Rect2:
	return Rect2(TACTICROW_ORIGIN + Vector2(float(idx) * (RELIC_SLOT.x + RELIC_GAP), 0.0),
		RELIC_SLOT)


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


# ─── 스프라이트 ───────────────────────────────────────────────────────────
# 한 칸 안의 무리는 줄을 맞추지 않고 어긋나게 세운다. 정렬하면 오히려 빈약해 보인다.
# 인원 상한이 아니라 **지금 서 있는 인원수**로 세운다 — 보이는 인원수가 곧 타격 분할이라
# 화면이 거짓말하지 않는다. 부대가 자라면 실루엣이 그대로 두꺼워진다.
const MEMBER_SPOTS := [
	Vector2(-38.0, -20.0), Vector2(-6.0, -26.0), Vector2(26.0, -18.0),
	Vector2(-44.0, 4.0),   Vector2(-12.0, -2.0), Vector2(20.0, 6.0),
	Vector2(-30.0, 26.0),  Vector2(2.0, 30.0),   Vector2(36.0, 22.0),
]


func _member_offsets(n: int) -> Array:
	match n:
		1: return [Vector2(0.0, 8.0)]
		2: return [Vector2(-24.0, -6.0), Vector2(22.0, 14.0)]
		3: return [Vector2(-28.0, -10.0), Vector2(6.0, 10.0), Vector2(32.0, -4.0)]
		4: return [Vector2(-30.0, -14.0), Vector2(4.0, -4.0), Vector2(-16.0, 20.0),
			Vector2(28.0, 14.0)]
	var out: Array = []
	for i in mini(n, MEMBER_SPOTS.size()):
		out.append(MEMBER_SPOTS[i])
	return out


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
			# 개체 크기는 **체급**이 정한다 — 인원이 채워져도 하나하나의 크기는 그대로다.
			# 실루엣이 두꺼워지는 것이 곧 부대가 자란 표식이 된다. 정수배만 쓴다.
			s.scale = Vector2.ONE * float(SIZES[d["size"]]["scale"])
			s.position = base + offs[m]
			# 애니 한 바퀴 ≈ 박자 한 번. 칸마다 리듬이 달라 직업이 박자로 식별된다.
			if running:
				var anim: StringName = &"spell" if casts else &"attack"
				_play(s, anim)
				var fc: float = maxf(1.0, float(f.get_frame_count(s.animation)))
				s.speed_scale = clampf(fc / (_period_now(sq) * 12.0), 0.4, 2.4)
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
		# 카드에 담긴 **마릿수 그대로** 세운다 — 실루엣이 체급과 마릿수를 읽기 전에 전달한다
		var n2: int = int(card["count"])
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
			s3.scale = Vector2.ONE * float(SIZES[ud["size"]]["scale"]) * 0.75
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
		var bf: SpriteFrames = _frames[b["base"]["sprite"]]
		if bs.sprite_frames != bf:
			bs.sprite_frames = bf
			bs.animation = &"idle"
		bs.scale = Vector2.ONE * float(BOSS_SCALE.get(str(b["base"]["size"]), 5))
		bs.position = Vector2(float(b["x"]), float(b["lane_y"]))
		bs.speed_scale = 1.0
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
	if card["kind"] == "tactic":
		return _tactic_color(card["def"])
	if card["kind"] == "relic":
		return card["def"]["color"]
	return JOBS[card["def"]["job"]]["color"]


# 종류마다 카드 얼굴이 다르다 — 호버해 읽기 전에 무엇에 거는 카드인지가 잡혀야 한다
func _tactic_color(t: Dictionary) -> Color:
	match str(t["kind"]):
		"cell":
			return Color(0.58, 0.82, 0.72)
		"gold":
			return Color(0.96, 0.84, 0.42)
	return Color(0.82, 0.56, 0.92)      # 규칙 — 유일하게 "바꾸는" 종류라 색이 확실히 갈린다


func _tactic_kind_name(t: Dictionary) -> String:
	match str(t["kind"]):
		"cell":
			return "전술 · 칸"
		"gold":
			return "전술 · 골드"
	return "전술 · 규칙"


# 조건절을 사람이 읽는 문장으로. **직업·종족은 종류가 아니라 조건절이다.**
func _tactic_cond_text(t: Dictionary) -> String:
	var c: Dictionary = t["cond"]
	if c.has("job"):
		return "%s 부대만" % str(JOBS[str(c["job"])]["name"])
	if c.has("race"):
		return "%s 부대만" % str(c["race"])
	return ""


func _tactic_effect_text(t: Dictionary) -> String:
	var v: float = float(t["val"])
	match str(t["stat"]):
		"dmg":
			return "데미지 +%d%%" % int(round(v * 100.0))
		"spd":
			return "공격속도 +%d%%" % int(round(v * 100.0))
		"crit":
			return "치명타 확률 +%d%%" % int(round(v * 100.0))
		"critmult":
			return "치명타 배율 +%d%%" % int(round(v * 100.0))
		"flat":
			return "타격당 +%.1f" % v
		# 카드 폭(한 줄 11~12자)에서 수치가 잘리면 안 된다 — 수치를 앞쪽에 둔다
		"dmg_near":
			return "성벽에 가까울수록 +0~%d%%" % int(round(v * 100.0))
		"gold_sec":
			return "시간 골드 +%.1f/s" % v
		"reroll_cut":
			return "연속 리롤 가산 -%d%%" % int(round(v * 100.0))
		"kill_gold":
			return "킬 골드 +%d%%" % int(round(v * 100.0))
		"wave_gold":
			return "킬마다 골드 +%d" % int(round(v))
		"gold_shield":
			return "성벽 피해, 골드 먼저 (HP당 %dG)" % int(round(v))
		"gold_hoard":
			return "100골드마다 데미지 +%d%%" % int(round(v * 100.0))
		"rule_unify":
			return "인원 판정을 하나로 묶는다"
		"rule_floor":
			return "물리 최소 보장 %.1f" % v
		"rule_critmult":
			return "치명타 피해 +%d%%" % int(round(v * 100.0))
		"rule_diag":
			return "인접에 대각선 포함"
	return ""


# 「칸」 종류의 얼굴이자, 세 종류 공통의 우측 상세 표기다.
# 이 카드의 효과가 어느 칸에 걸리는지를 미니 격자로 칠해 보여준다 —
# 칸과 무관한 효과(경제·규칙)면 비워 둔다.
func _draw_mini_grid(pos: Vector2, cell: float, cells: Array, col: Color, empty: Array = []) -> void:
	for i in 9:
		var r := Rect2(pos + Vector2(float(i % 3) * cell, float(i / 3) * cell),
			Vector2(cell - 2.0, cell - 2.0))
		if cells.has(i):
			_overlay.draw_rect(r, col)
		elif empty.has(i):
			# 비어 있어야 하는 칸 — 부대를 세우면 효과가 꺼진다 (칸나이·청야유인)
			_overlay.draw_rect(r, Color(0.60, 0.28, 0.28))
		else:
			_overlay.draw_rect(r, Color(0.22, 0.23, 0.28))


# **얼굴은 최소로** — 이름·종류·얼굴 그림·가격이 전부다. 효과·조건·유래는 호버로.
# 그림이 곧 정보라는 확정 문법 그대로다(기획 「상점」) — 「칸」은 3×3에 칠한 칸이,
# 골드·규칙은 표식과 영향 칸 그림이 "무엇에 거는 카드인지"를 글자 없이 답한다.
func _draw_tactic_card(r: Rect2, t: Dictionary, col: Color, afford: bool) -> void:
	_txtw(_font, r.position + Vector2(10.0, 28.0), str(t["name"]), 20,
		Color(0.97, 0.97, 1.0) if afford else Color(0.55, 0.55, 0.60), CARD.x - 20.0)
	_txt(_font_s, r.position + Vector2(10.0, 50.0),
		"%s · %d등급" % [_tactic_kind_name(t), int(t["grade"])], 17, col)
	# 카드 얼굴 — 「칸」은 3×3 그림, 나머지 둘은 각자의 표식
	var face := r.position + Vector2(10.0, 62.0)
	if str(t["kind"]) == "cell":
		_draw_mini_grid(face, 22.0, t["cells"], col, t.get("empty", []))
	else:
		var mark := Rect2(face, Vector2(64.0, 64.0))
		_overlay.draw_rect(mark, col.darkened(0.55))
		_txt(_font_b, face + Vector2(18.0, 44.0),
			"G" if str(t["kind"]) == "gold" else "R", 34, col)
		# 공통 상세 표기 — 영향 칸 3×3(기획 「전술카드」). 전 부대면 9칸, 칸과 무관(경제)이면 빈 그림
		_draw_mini_grid(face + Vector2(72.0, 10.0), 14.0, t["cells"], col.darkened(0.25))
	if _has_tactic(str(t["id"])):
		_txt(_font_s, r.position + Vector2(96.0, r.size.y - 14.0), "이미 보유", 17,
			Color(0.95, 0.72, 0.55))


# ─── 그리기: 오버레이 (스프라이트 위) ─────────────────────────────────────
func _draw_overlay() -> void:
	_resolve_detail()          # 칸·보스가 "지금 보고 있는 것"에 테두리를 치므로 먼저 정한다
	_draw_top_hud()
	_draw_forecast()
	_draw_cells_hud()
	_draw_bosses_hud()
	_draw_shop_text()
	_draw_relic_row()
	_draw_tactic_row()
	_draw_side_panels()
	if _paused:
		_draw_stats_panel()    # 측정은 프로토 디버그다 — 정지 중에만 레인 위에 뜬다
	if _detail_kind != "":
		_draw_detail_card()
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


# 유저에게 필요한 것만 남긴다 (3차 · 사용자 확정) — 골드 · 성벽 · 진행. 경과·레인 마리수·
# 조작 안내·스폰 모드는 전부 걷어냈다. 키([Space]/[R]/[S])는 표시 없이 그대로 작동한다.
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

	# 예고 슬롯이 다음 한 마리를 크게 알린다. 그 뒤로 오는 것들은 줄로만 둔다.
	var qx: float = 56.0
	_txt(_font_s, Vector2(qx, 100.0), "그 다음", 20, Color(0.50, 0.53, 0.60))
	qx += 90.0
	for i in range(_next_spawn + 1, mini(_schedule.size(), _next_spawn + 6)):
		var e: Dictionary = _schedule[i]
		var tint: Color = e["tint"]
		_overlay.draw_rect(Rect2(qx, 84.0, 150.0, 26.0), tint.darkened(0.72))
		_txt(_font_s, Vector2(qx + 8.0, 104.0),
			"%s %.0fs" % [e["name"], maxf(0.0, float(e["at"]) - _elapsed)], 19, tint)
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
	var tint: Color = e["tint"]
	var left: float = maxf(0.0, _spawn_due() - _elapsed)
	_overlay.draw_rect(r, tint.darkened(0.35), false, 2.0)
	# **모든 적이 예고된다.** 적이 정예와 막보스뿐이라 예고가 뜸하게 갱신되고,
	# 그래서 "예고가 떴다 = 생각할 것이 왔다"가 신호로 고정된다(기획 「예고 슬롯」).
	_txt(_font_s, r.position + Vector2(12.0, 24.0),
		"예고 · %s" % str(ACTS[int(e["act"])]["name"]), 18, Color(0.60, 0.63, 0.70))
	_txt(_font_b, r.position + Vector2(r.size.x - 82.0, 26.0), "%.0fs" % left, 24,
		Color(0.95, 0.82, 0.45) if left > 5.0 else Color(1.0, 0.50, 0.44))
	# 이름이 길어졌다(진영 베이스 이름) — 남은 시간과 줄을 나눠 겹치지 않게 한다
	_txtw(_font_b, r.position + Vector2(12.0, 56.0), str(e["name"]), 26, tint, r.size.x - 24.0)
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
		if rel == null or str(rel["verb"]) == "" or not _relic_covers(rel, sq["def"]):
			continue
		var got: int = int(sq["relic_beats"].get(str(rel["uid"]), 0))
		var prog: float = clampf(float(got) / float(rel["hits"]), 0.0, 1.0)
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
		var e: Dictionary = b["entry"]
		var x: float = float(b["x"])
		var y: float = float(b["lane_y"])
		var tint: Color = e["tint"]
		var ratio: float = clampf(float(b["hp"]) / float(b["hp_max"]), 0.0, 1.0)
		var bar := Rect2(x - 110.0, y - 132.0, 220.0, 15.0)
		_bar(bar, ratio, Color(0.84, 0.28, 0.32), Color(0.16, 0.09, 0.11))
		_overlay.draw_rect(bar, Color(0.90, 0.85, 0.60) if b == target else Color(0.45, 0.30, 0.34),
			false, 2.0)
		_txt(_font, Vector2(bar.position.x, bar.position.y - 30.0),
			"%s #%d" % [e["name"], int(b["index"]) + 1], 21, tint)
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
			continue
		var afford: bool = _gold >= int(card["price"])
		var col: Color = _card_color(card)
		if card["kind"] == "unit":
			_draw_unit_card(r, card["def"], int(card["count"]), col, afford, target)
		elif card["kind"] == "tactic":
			_draw_tactic_card(r, card["def"], col, afford)
		else:
			_draw_relic_card(r, card["def"], col, afford)
		_txt(_font_b, r.position + Vector2(10.0, r.size.y - 14.0), "%dG" % int(card["price"]), 24,
			Color(1.0, 0.88, 0.45) if afford else Color(0.60, 0.42, 0.35))


# 원소 표기 — "random"은 ELEMENTS 에 없다. 수인족은 매 캐스트마다 굴리는 것이 색이라
# (기획 「종족」) 여기 한곳에서만 갈라준다. 키 에러로 죽는 것을 막는 자리이기도 하다.
func _elem_name(e: String) -> String:
	if e == "random":
		return "랜덤"
	return str(ELEMENTS[e]["name"]) if ELEMENTS.has(e) else "—"


func _elem_color(e: String) -> Color:
	return Color(ELEMENTS[e]["color"]) if ELEMENTS.has(e) else Color(0.86, 0.80, 0.62)


# 스킬이 언제 터지는지는 직업이 정한다 — 카드에는 그 리듬을 그대로 옮겨 적는다.
func _skill_when(d: Dictionary) -> String:
	var sk: Dictionary = d["skill"]
	match str(JOBS[d["job"]]["trigger"]):
		"chance":
			return "평타마다 %d%%" % int(round(float(sk["chance"]) * 100.0))
		"crit":
			return "크리티컬이 터질 때"
		"cast":
			return "캐스팅 %.2fs마다" % float(d["period"])
	return "발동 미결"


# text.csv 의 설명문 일부가 @damage@ 같은 자리표시자를 쓴다 — 값은 TUNE_SKILLS 에 있으므로
# 여기서 끼워 넣는다. 없는 자리표시자는 그대로 남아 눈에 띈다(빠진 것이 보여야 한다).
func _skill_desc(d: Dictionary) -> String:
	var sk: Dictionary = d["skill"]
	return str(sk["desc"]) \
		.replace("@damage@", "%.0f" % float(sk["damage"])) \
		.replace("@cast_time@", "%.1f" % float(sk["cast_time"])) \
		.replace("@multiplier@", "%.2f" % float(sk["multiplier"])) \
		.replace("@chance@", "%d%%" % int(round(float(sk["chance"]) * 100.0))) \
		.replace("@dur@", "%.1f" % float(sk["dur"]))


# **카드 얼굴은 최소로, 상세는 호버로** (기획 「상점」 — 병사카드 = 실루엣 + 이름·마릿수).
# 얼굴에 남는 글자는 이름·종족·직업·마릿수·가격이고, 사전 판정 칩 하나만 예외다 —
# 통함/딜 0(물리)·원소 저항(마법)은 흐르는 시간 속에서 호버 없이 읽혀야 해서(기획
# 「실시간이 요구하는 것」). 박자·스킬·계산 과정은 전부 호버로.
# **타격당 딜은 체급이 고정하므로 마릿수와 무관하다** — 칩이 부대를 채운 뒤에도 거짓말하지 않는다.
func _draw_unit_card(r: Rect2, d: Dictionary, count: int, col: Color, afford: bool,
		target) -> void:
	_txtw(_font, r.position + Vector2(10.0, 28.0), str(d["name"]), 21,
		Color(0.97, 0.97, 1.0) if afford else Color(0.55, 0.55, 0.60), CARD.x - 62.0)
	# 마릿수 — 실루엣이 이미 말하지만, 합류(부어 채우기) 판단은 숫자가 빨라 우측에 남긴다
	_txt(_font, r.position + Vector2(r.size.x - 46.0, 28.0), "×%d" % count, 20,
		Color(0.86, 0.88, 0.94))
	# 이름 아래 종족·직업 — 편성(조건절·유물 태그)이 종족×직업 축이라 얼굴에서 보여야 한다
	_txt(_font_s, r.position + Vector2(10.0, 50.0),
		"%s · %s" % [str(d["race"]), str(JOBS[d["job"]]["name"])], 17, col)
	var per: float = float(d["hit"])
	if str(d["job"]) == "cleric":
		return                        # 아군 대상 — 보스 상대 사전 판정이 없다. 나머지는 호버로
	if str(JOBS[d["job"]]["atk"]) == "phys":
		var chip := Rect2(r.position + Vector2(r.size.x - 66.0, r.size.y - 34.0),
			Vector2(56.0, 20.0))
		if target == null:
			_overlay.draw_rect(chip, Color(0.20, 0.21, 0.26))
			_txt(_font_s, chip.position + Vector2(22.0, 16.0), "—", 16, Color(0.62, 0.65, 0.72))
			return
		var ok: bool = _phys_damage(per, target) > 0.0
		_overlay.draw_rect(chip, Color(0.18, 0.45, 0.24) if ok else Color(0.52, 0.14, 0.16))
		_txt(_font_s, chip.position + Vector2(7.0, 16.0), "통함" if ok else "딜 0", 16,
			Color(0.75, 1.0, 0.80) if ok else Color(1.0, 0.70, 0.68))
		return
	var elem: String = str(d["elem"])
	var ecol: Color = _elem_color(elem)
	var chip2 := Rect2(r.position + Vector2(r.size.x - 84.0, r.size.y - 34.0),
		Vector2(74.0, 20.0))
	_overlay.draw_rect(chip2, ecol.darkened(0.55))
	_txt(_font_s, chip2.position + Vector2(6.0, 16.0),
		"%s %d%%" % [_elem_name(elem), int(round(_res_now(target, elem) * 100.0))], 16, ecol)


# 태그를 사람이 읽는 한 단어로. **태그는 유물 하나에 하나뿐**이라 이 한 줄이면 걸러진다.
func _relic_tag_text(it: Dictionary) -> String:
	match str(it["tag"]):
		"job":
			return "[%s]" % str(JOBS[str(it["val"])]["name"])
		"race":
			return "[%s]" % str(it["val"])
	return "[전체]"


func _opt_text(o: Dictionary, grown: int) -> String:
	var v: float = float(o["val"])
	match str(o["stat"]):
		"dmg":
			return "데미지 +%d%%" % int(round(v * 100.0))
		"spd":
			return "공격속도 +%d%%" % int(round(v * 100.0))
		"crit":
			return "치명타 확률 +%d%%" % int(round(v * 100.0))
		"critmult":
			return "치명타 배율 +%d%%" % int(round(v * 100.0))
		"flat":
			return "타격당 +%.1f" % v
		"elem":
			return "%s 데미지 +%d%%" % [_elem_name(str(o["elem"])), int(round(v * 100.0))]
		"grow":
			# 성장형 — 조건이 충족될 때마다 값이 누적된다. 지금까지 얼마나 자랐는지를 같이 적는다.
			# 수치를 앞에 둔다 — 카드 폭에서 뒷부분이 잘려도 "얼마씩 크는지"는 보여야 한다
			return "데미지 +%d%%/킬 (현재 +%d%%)" % [int(round(v * 100.0)),
				int(round(v * float(grown) * 100.0))]
	return ""


# **얼굴은 최소로** — 이름·등급·태그·가격이 전부다. 옵션 줄은 호버로.
# 이름이 이미 정보다(기획 「접사는 7죄종으로」 — 이름이 옵션을 그대로 가리킨다).
# **얼굴 그림은 전술카드와 같은 자리·같은 크기의 64×64 박스다** — 매대에서 카드 종류가
# 달라도 얼굴의 무게가 같아야 한다. 박스 안 두 글자가 태그다(본편에선 형상 그림이 이 자리).
func _draw_relic_card(r: Rect2, it: Dictionary, col: Color, afford: bool) -> void:
	var g: Dictionary = RELIC_GRADES[str(it["grade"])]
	_txtw(_font, r.position + Vector2(10.0, 28.0), str(it["name"]), 20,
		Color(0.97, 0.97, 1.0) if afford else Color(0.55, 0.55, 0.60), CARD.x - 20.0)
	_txt(_font_s, r.position + Vector2(10.0, 50.0), "유물 · %s" % str(g["name"]), 17, col)
	var face := r.position + Vector2(10.0, 62.0)
	_overlay.draw_rect(Rect2(face, Vector2(64.0, 64.0)), col.darkened(0.55))
	_txt(_font_b, face + Vector2(8.0, 42.0), _relic_tag_short(it), 24, col)
	var live: int = _relic_live(it)
	_txt(_font_s, face + Vector2(72.0, 16.0), "받는 칸 %d" % live, 17,
		Color(0.85, 0.90, 0.98) if live > 0 else Color(1.0, 0.66, 0.60))
	# 유니크만 동사 한 단어를 더 갖는다 — "카드 얼굴만 보고 즉시 판단"이 유니크의 문법이다
	if str(it["verb"]) != "":
		_txtw(_font_s, face + Vector2(72.0, 40.0), str(it["short"]), 17, col,
			CARD.x - 92.0)
	if _has_relic(str(it["uid"])):
		_txt(_font_s, r.position + Vector2(10.0, r.size.y - 34.0), "이미 보유", 18,
			Color(1.0, 0.70, 0.62))


# 보유 슬롯은 **정사각 아이콘**이다 — 이름·수치는 호버 상세로. 테두리 색이 등급을,
# 태그 두 글자가 "누구 것인가"를 말한다 (본편에선 형상 그림이 이 자리다).
func _draw_relic_row() -> void:
	_txt(_font_s, Vector2(RELICROW_ORIGIN.x - 50.0, RELICROW_ORIGIN.y + 66.0), "유물", 17,
		Color(0.55, 0.58, 0.66))
	for i in RELIC_SLOTS:
		var r: Rect2 = _relic_rect(i)
		var rel = _relics[i]
		if rel == null:
			_overlay.draw_rect(r, Color(0.10, 0.105, 0.13))
			_overlay.draw_rect(r, Color(0.22, 0.23, 0.28), false, 2.0)
			continue
		var col: Color = rel["color"]
		var live: int = _relic_live(rel)
		_overlay.draw_rect(r, col.darkened(0.78))
		_overlay.draw_rect(r, col.darkened(0.15 if live > 0 else 0.65), false, 2.0)
		# 전술 슬롯의 표식(3×3 그림·G/R)과 같은 급으로 채운다 — 두 줄의 아이콘 무게가 같아야
		# 블록이 한 덩어리로 읽힌다
		_txt(_font_b, r.position + Vector2(24.0, 72.0), _relic_tag_short(rel), 34,
			Color(0.92, 0.94, 1.0) if live > 0 else Color(1.0, 0.66, 0.60))
		# 동사(유니크) 표식 — 자동 발동이 있는 물건이라는 점만 점 하나로 남긴다
		if str(rel["verb"]) != "":
			_overlay.draw_rect(Rect2(r.end - Vector2(22.0, 22.0), Vector2(12.0, 12.0)), col)


func _relic_tag_short(it: Dictionary) -> String:
	match str(it["tag"]):
		"job":
			return str(JOBS[str(it["val"])]["name"]).left(2)
		"race":
			return str(it["val"]).left(2)
	return "전체"


# 전술 슬롯 — 보유 상한이 있다. 상한이 없으면 후반에 규칙이 쌓여
# 아무도 자기 게임의 규칙을 못 읽는다(기획 「구성 요소」).
# 「칸」은 3×3 그림 자체가 아이콘이다 — 재배치 중 곁눈질로 패턴만 보면 된다.
func _draw_tactic_row() -> void:
	_txt(_font_s, Vector2(TACTICROW_ORIGIN.x - 50.0, TACTICROW_ORIGIN.y + 66.0), "전술", 17,
		Color(0.55, 0.58, 0.66))
	for i in TACTIC_SLOTS:
		var r: Rect2 = _tactic_rect(i)
		var t = _tactics[i]
		if t == null:
			_overlay.draw_rect(r, Color(0.10, 0.105, 0.13))
			_overlay.draw_rect(r, Color(0.22, 0.23, 0.28), false, 2.0)
			continue
		var col: Color = _tactic_color(t)
		_overlay.draw_rect(r, col.darkened(0.78))
		_overlay.draw_rect(r, col.darkened(0.15), false, 2.0)
		if str(t["kind"]) == "cell":
			_draw_mini_grid(r.position + Vector2(8.0, 8.0), 35.0,
				t["cells"], col, t.get("empty", []))
		else:
			_txt(_font_b, r.position + Vector2(38.0, 80.0),
				"G" if str(t["kind"]) == "gold" else "R", 52, col)


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

	# 성벽 패널은 없다 (3차 · 사용자 확정 — 화면에서 완전히 제거). 수리는 성벽 클릭이고,
	# 수리가·회복량·최대 HP 업그레이드 전부 성벽 호버 상세에만 산다. 업그레이드는 우클릭이다.
	# 성벽 호버 중이면 성벽에 테두리 — "이걸 클릭하면 된다"가 보여야 한다
	if _detail_kind == "wall":
		var can_rep: bool = _gold >= _repair_price and _wall_hp < _wall_max
		_overlay.draw_rect(WALL_RECT.grow(4.0),
			Color(0.60, 0.95, 0.70) if can_rep else Color(0.75, 0.85, 1.0), false, 3.0)


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
	_txt(_font_s, p + Vector2(14.0, 158.0), "딜 0 %.0f%% · 빗나감 %.0f%%" % [zero, _miss_ratio()],
		18, Color(0.95, 0.72, 0.68) if zero > 30.0 else Color(0.72, 0.76, 0.84))
	_txt(_font_s, p + Vector2(14.0, 182.0), "물리 감산 손실  %.0f%%" % _phys_loss(), 18,
		Color(0.72, 0.76, 0.84))
	_txt(_font_s, p + Vector2(14.0, 206.0), "유물 %d회 · 스킬 %d회" %
		[_log_relic_fires, _skill_fire_total()], 18, Color(0.72, 0.76, 0.84))
	# 격자가 얼마나 찼는지 — 9칸을 몇 칸 잡았는지와 **인원을 얼마나 채웠는지**는 다른 축이다
	_txt(_font_s, p + Vector2(14.0, 230.0), "배치 %d/9 (인원 %d/%d) · 유물 %d/%d" %
		[_placed_count(), _crew_now(), _crew_cap(), RELIC_SLOTS - _empty_relics(), RELIC_SLOTS],
		18, Color(0.72, 0.76, 0.84))


func _avg_kill() -> float:
	if _log_kill_times.is_empty():
		return 0.0
	var s: float = 0.0
	for t in _log_kill_times:
		s += float(t)
	return s / float(_log_kill_times.size())


func _skill_fire_total() -> int:
	var n: int = 0
	for k in _log_skill_fires.keys():
		n += int(_log_skill_fires[k])
	return n


func _zero_ratio() -> float:
	if _log_total_hits <= 0:
		return 0.0
	return float(_log_zero_hits) / float(_log_total_hits) * 100.0


func _miss_ratio() -> float:
	if _log_total_hits <= 0:
		return 0.0
	return float(_log_missed) / float(_log_total_hits) * 100.0


func _phys_loss() -> float:
	if _log_phys_raw <= 0.0:
		return 0.0
	return (1.0 - _log_phys_out / _log_phys_raw) * 100.0


# 인원 채움 — 병사카드 합류제가 만든 성장 런웨이가 실제로 얼마나 도는지의 눈금이다
func _crew_now() -> int:
	var n: int = 0
	for sq in _cells:
		if sq != null:
			n += int(sq["members"])
	return n


func _crew_cap() -> int:
	var n: int = 0
	for sq in _cells:
		if sq != null:
			n += int(sq["def"]["cap"])
	return n


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

	# 유효한 목적지만 밝힌다 — 무효한 곳에 놓으면 취소·무과금이다.
	# 만석에 붓는 칸은 노란색 — 놓이긴 하지만 초과분이 사라진다
	for i in 9:
		if not _valid_cell_drop(i):
			continue
		var waste: bool = _wasteful_cell_drop(i)
		var cr: Rect2 = _cell_rect(i)
		_overlay.draw_rect(cr, Color(0.90, 0.78, 0.35, 0.16) if waste
			else Color(0.55, 0.85, 0.60, 0.16))
		_overlay.draw_rect(cr, Color(1.0, 0.86, 0.42, 0.80) if waste
			else Color(0.60, 0.95, 0.66, 0.75), false, 3.0)
	for i in RELIC_SLOTS:
		if not _valid_relic_drop(i):
			continue
		var rr2: Rect2 = _relic_rect(i)
		_overlay.draw_rect(rr2, Color(0.55, 0.85, 0.60, 0.16))
		_overlay.draw_rect(rr2, Color(0.60, 0.95, 0.66, 0.75), false, 3.0)
	for i in TACTIC_SLOTS:
		if not _valid_tactic_drop(i):
			continue
		var tr2: Rect2 = _tactic_rect(i)
		_overlay.draw_rect(tr2, Color(0.55, 0.85, 0.60, 0.16))
		_overlay.draw_rect(tr2, Color(0.60, 0.95, 0.66, 0.75), false, 3.0)


# 병사카드는 **빈 칸이나 같은 유닛의 칸에만** 놓인다. 다른 유닛 위에는 못 놓으므로
# 그 칸은 아예 밝히지 않는다 — 드롭 전에 결과가 미리 보여야 한다.
func _valid_cell_drop(cell_idx: int) -> bool:
	if _drag_kind == "cell":
		return cell_idx != _drag_from
	if _drag_kind != "shop":
		return false
	var card = _shop[_drag_from]
	if card == null or _gold < int(card["price"]) or card["kind"] != "unit":
		return false
	var sq = _cells[cell_idx]
	return sq == null or str(sq["def"]["id"]) == str(card["def"]["id"])


# 만석인 같은 유닛 칸 — 놓을 수는 있지만 초과분이 사라진다. 색을 갈라 미리 알린다.
func _wasteful_cell_drop(cell_idx: int) -> bool:
	if _drag_kind != "shop":
		return false
	var card = _shop[_drag_from]
	var sq = _cells[cell_idx]
	if card == null or sq == null or card["kind"] != "unit":
		return false
	return str(sq["def"]["id"]) == str(card["def"]["id"]) \
		and int(sq["members"]) + int(card["count"]) > int(sq["def"]["cap"])


func _valid_tactic_drop(slot: int) -> bool:
	if _drag_kind != "shop":
		return false
	var card = _shop[_drag_from]
	if card == null or _gold < int(card["price"]) or card["kind"] != "tactic":
		return false
	if _has_tactic(str(card["def"]["id"])):
		return false
	return _tactics[slot] == null


# 전술카드 상세 — 세 종류 공통으로 **영향 칸 3×3 표시**와 **역사 유래 한 줄**이 붙는다.
# 칸 종류는 얼굴과 같은 그림이 반복되는 셈이고, 골드·규칙도 "누가 받는가"를 그림으로 답한다.
func _view_tactic(t, equipped: bool) -> Dictionary:
	if t == null:
		return {}
	var l: Array = []
	l.append(_tactic_kind_name(t) + " · %d등급" % int(t["grade"]))
	l.append(">%s" % _tactic_effect_text(t))
	var cond: String = _tactic_cond_text(t)
	if cond != "":
		l.append(">조건 — %s" % cond)
		# 조건절이 붙은 카드는 조건에 맞는 부대가 많을수록 저절로 세진다.
		# **몰빵의 보상이 여기서 난다** — 카운트 UI도 문턱 보너스도 없다
		l.append("지금 맞는 칸 %d" % _cells_matching(t["cond"]))
	if str(t["kind"]) == "cell":
		var on: int = 0
		for i in t["cells"]:
			if _cells[int(i)] != null:
				on += 1
		l.append("칠한 칸 %d — 부대가 선 칸 %d" % [(t["cells"] as Array).size(), on])
		if on == 0 and equipped:
			l.append("!칠한 칸이 비어 있다 — 아무도 못 받는다")
		# 칸나이·청야유인 — 지정 칸이 비어 있어야 켜진다. 배치가 곧 스위치다
		var emp: Array = t.get("empty", [])
		if not emp.is_empty():
			var blocked: int = 0
			for e in emp:
				if _cells[int(e)] != null:
					blocked += 1
			if blocked > 0:
				l.append("!붉은 %d칸이 차 있다 — 효과 꺼짐" % blocked)
			else:
				l.append("붉은 %d칸이 비어 있다 — 켜짐" % emp.size())
	if str(t["lore"]) != "":
		l.append("")
		l.append("~%s" % str(t["lore"]))
	return {"title": str(t["name"]), "color": _tactic_color(t), "lines": l}


func _valid_relic_drop(slot: int) -> bool:
	if _drag_kind != "shop":
		return false
	var card = _shop[_drag_from]
	if card == null or _gold < int(card["price"]) or card["kind"] != "relic":
		return false
	if _has_relic(str(card["def"]["uid"])):
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
		for i in TACTIC_SLOTS:
			if _tactic_rect(i).has_point(_mouse) and _tactics[i] != null:
				_detail_kind = "tactic"
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
		# 성벽 — 보스보다 뒤에 본다. 겹치면 보스 정보가 우선이다 (클릭은 반대로 수리가 우선)
		if WALL_RECT.grow(10.0).has_point(_mouse):
			_detail_kind = "wall"
			_detail_idx = 0
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
		"tactic":
			return idx >= 0 and idx < TACTIC_SLOTS and _tactics[idx] != null
		"boss":
			return _boss_by_index(idx) != null
		"forecast":
			return true
		"wall":
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
		"tactic":
			return _view_tactic(_tactics[_detail_idx], true)
		"boss":
			return _view_boss(_boss_by_index(_detail_idx))
		"forecast":
			return _view_forecast()
		"wall":
			return _view_wall()
	return {}


func _view_wall() -> Dictionary:
	var l: Array = []
	l.append(">HP %d / %d" % [int(_wall_hp), int(_wall_max)])
	l.append(">클릭 = 수리 +%d (%dG)" % [int(REPAIR_HEAL), _repair_price])
	l.append(">우클릭 = 최대 HP +%d (%dG)" % [int(UPGRADE_GAIN), _upgrade_price])
	if _wall_hp >= _wall_max:
		l.append("가득 찼다")
	elif _gold < _repair_price:
		l.append("!골드가 모자라다")
	return {"title": "성벽", "color": Color(0.62, 0.70, 0.86), "lines": l}


# 상세 카드의 위치 — **호버한 대상 옆에 뜬다.** 시선이 왕복하지 않는 것이 실시간의 전제다.
# 매대 카드는 카드 위, 격자 칸은 칸 오른쪽, 보유 슬롯은 슬롯 왼쪽(바닥 정렬), 보스는 보스 왼쪽,
# 예고는 예고 아래. 어디서든 화면 안으로 클램프한다.
func _detail_rect_now(h: float) -> Rect2:
	var p := Vector2(W - DETAIL_SIZE.x - 16.0, 706.0)
	match _detail_kind:
		"shop":
			var cr := _card_rect(_detail_idx)
			p = Vector2(cr.position.x, cr.position.y - h - 10.0)
		"cell":
			var ce := _cell_rect(_detail_idx)
			p = Vector2(ce.end.x + 12.0, ce.position.y - 20.0)
		"relic":
			var rr := _relic_rect(_detail_idx)
			p = Vector2(rr.position.x - DETAIL_SIZE.x - 12.0, rr.end.y - h)
		"tactic":
			var tr := _tactic_rect(_detail_idx)
			p = Vector2(tr.position.x - DETAIL_SIZE.x - 12.0, tr.end.y - h)
		"boss":
			var b = _boss_by_index(_detail_idx)
			if b != null:
				var br := _boss_rect(b)
				p = Vector2(br.position.x - DETAIL_SIZE.x - 12.0, br.position.y - 20.0)
		"forecast":
			p = Vector2(FORECAST_RECT.position.x, FORECAST_RECT.end.y + 10.0)
		"wall":
			p = Vector2(WALL_RECT.end.x + 16.0, 300.0)
	p.x = clampf(p.x, 8.0, W - DETAIL_SIZE.x - 8.0)
	p.y = clampf(p.y, 8.0, H - h - 8.0)
	return Rect2(p, Vector2(DETAIL_SIZE.x, h))


# 줄 앞의 표식으로 색을 정한다 — ">"는 강조(그 대상의 핵심 수치), "!"는 경고(딜 0 등)
func _draw_detail_card() -> void:
	if _detail_kind == "":
		return
	var view: Dictionary = _detail_view()
	if view.is_empty():
		return
	# 내용만큼만 자란다 — 빈 상자가 남으면 "뭔가 더 있나" 하고 읽게 된다.
	# 높이를 먼저 정하고 자리를 잡는다 — 카드 위에 띄울 때는 바닥이 카드에 붙어야 한다
	var lines: Array = view["lines"]
	var sk: Dictionary = view.get("skill", {})
	var body: float = 60.0 + float(lines.size()) * 21.0 + 10.0
	if not sk.is_empty():
		body += 76.0                   # 스킬 블록 — 아이콘 + 이름 + 설명 두 줄
	var h: float = clampf(body, 110.0, DETAIL_SIZE.y)
	var r: Rect2 = _detail_rect_now(h)
	var col: Color = view["color"]
	_overlay.draw_rect(r, Color(0.085, 0.095, 0.125, 0.98))
	_overlay.draw_rect(r, col.lerp(Color(0.6, 0.63, 0.72), 0.35), false, 2.0)
	_overlay.draw_rect(Rect2(r.position, Vector2(r.size.x, 36.0)), col.darkened(0.60))
	_txtw(_font_b, r.position + Vector2(12.0, 26.0), str(view["title"]), 21,
		Color(0.98, 0.98, 1.0), r.size.x - 62.0)
	if _pin_kind == _detail_kind and _pin_idx == _detail_idx:
		_txt(_font_s, r.position + Vector2(r.size.x - 46.0, 25.0), "고정", 16,
			Color(1.0, 0.88, 0.45))

	var bottom: float = r.size.y - (88.0 if not sk.is_empty() else 12.0)
	var y: float = 60.0
	for raw in lines:
		# 박스를 넘길 줄은 그리지 않는다 — 넘친 글줄이 스킬 블록 위에 얹히면 못 읽는다.
		# 잘렸다는 것만 표식으로 남긴다 (4막 막보스처럼 접두사·상태가 긴 카드에서 실제로 넘친다)
		if y > bottom:
			_txt(_font_s, r.position + Vector2(12.0, y), "…", 17, Color(0.55, 0.58, 0.66))
			break
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
		# "라벨\t값" — 능력치 표는 두 컬럼으로 정렬해 그린다 (3차 · 사용자 확정 서식)
		if "\t" in s:
			var parts: PackedStringArray = s.split("\t")
			_txt(_font_s, r.position + Vector2(12.0, y), parts[0], 17, Color(0.60, 0.64, 0.72))
			_txtw(_font_s, r.position + Vector2(150.0, y), parts[1], 17, c, r.size.x - 162.0)
		else:
			_txtw(_font_s, r.position + Vector2(12.0, y), s, 17, c, r.size.x - 24.0)
		y += 21.0

	# 스킬 블록 — 맨 아래 고정. 아이콘 하나 + 이름·발동 + 짧은 설명 (3차 · 사용자 확정)
	if not sk.is_empty():
		var fy: float = r.position.y + r.size.y - 74.0
		_overlay.draw_line(Vector2(r.position.x + 12.0, fy - 6.0),
			Vector2(r.end.x - 12.0, fy - 6.0), Color(0.30, 0.32, 0.40), 1.0)
		var scol: Color = sk["color"]
		var ic := Rect2(Vector2(r.position.x + 12.0, fy + 2.0), Vector2(34.0, 34.0))
		_overlay.draw_rect(ic, scol.darkened(0.45))
		_overlay.draw_rect(ic, scol, false, 2.0)
		_txt(_font_b, ic.position + Vector2(8.0, 26.0), str(sk["name"]).left(1), 22,
			Color(0.97, 0.97, 1.0))
		_txtw(_font_s, Vector2(ic.end.x + 10.0, fy + 16.0),
			"%s — %s" % [str(sk["name"]), str(sk["when"])], 17,
			Color(1.0, 0.90, 0.58), r.size.x - 70.0)
		_overlay.draw_multiline_string(_font_s, Vector2(ic.end.x + 10.0, fy + 38.0),
			str(sk["desc"]), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 70.0, 15, 2,
			Color(0.72, 0.76, 0.84))


# 카드 폭이 298px이라 한 줄에 30자 남짓이다. 문장을 늘어놓지 않고 짧게 끊는다.
func _view_cell(idx: int) -> Dictionary:
	var sq: Dictionary = _cells[idx]
	var d: Dictionary = sq["def"]
	var job: Dictionary = JOBS[d["job"]]
	var target = _target_boss()
	# 스탯 시트 (3차 · 사용자 확정) — 정체 한 줄, 라벨\t값 능력치 표, 맨 아래 스킬 블록(footer)
	var l: Array = []
	l.append("[%s] [%s] · %s %d/%d" % [str(d["race"]), str(job["name"]),
		str(SIZES[d["size"]]["name"]), int(sq["members"]), int(d["cap"])])
	l.append("")
	l.append_array(_stat_rows(d, _per_hit(sq), _period_now(sq),
		float(sq["crit"]), float(sq["crit_mult"]), target))
	if float(sq["bind"]) > 0.0:
		l.append("!주박 -%d%% (%.1fs)"
			% [int(round((1.0 - _bind_mult(sq)) * 100.0)), float(sq["bind_t"])])
	if str(job["atk"]) == "phys" and target != null \
			and _phys_damage(_per_hit(sq), target) <= 0.0:
		l.append("!지금 보스에게 딜 0")
	return {"title": str(d["name"]), "color": Color(job["color"]), "lines": l,
		"skill": _skill_footer(d)}


# 능력치 표 — 공격력 · 공격속도 · 명중률 · 치명타 확률 · 치명타 데미지 (3차 · 사용자 확정 서식).
# "라벨\t값"은 상세 카드가 두 컬럼으로 그린다. 명중률은 현재 보스의 회피를 반영한 값이다.
func _stat_rows(d: Dictionary, per: float, period: float, crit: float, critmult: float,
		target) -> Array:
	var l: Array = []
	if str(d["job"]) == "cleric":
		l.append("축복\t%s" % (("+%.1f/타격" % per) if per > 0.0 else "정화"))
		l.append("공격속도\t%.2fs" % period)
		l.append("명중률\t—")
	elif str(JOBS[d["job"]]["atk"]) == "phys":
		l.append("공격력\t%.1f" % per)
		l.append("공격속도\t%.2fs" % period)
		var acc: float = 1.0 if target == null else 1.0 - float(target["evade"])
		l.append("명중률\t%d%%" % int(round(acc * 100.0)))
	else:
		l.append("공격력\t%.0f · %s" % [per, _elem_name(str(d["elem"]))])
		l.append("공격속도\t%.2fs" % period)
		l.append("명중률\t100%")
	l.append("치명타 확률\t%d%%" % int(round(crit * 100.0)))
	l.append("치명타 데미지\t×%.1f" % critmult)
	return l


func _skill_footer(d: Dictionary) -> Dictionary:
	return {"name": str(d["skill"]["name"]), "when": _skill_when(d),
		"desc": _skill_desc(d), "color": Color(JOBS[d["job"]]["color"])}


func _view_shop(card) -> Dictionary:
	if card == null:
		return {}
	if card["kind"] == "relic":
		var v: Dictionary = _view_relic(card["def"], false)
		(v["lines"] as Array).append(">%dG" % int(card["price"]))
		return v
	if card["kind"] == "tactic":
		var v2: Dictionary = _view_tactic(card["def"], false)
		(v2["lines"] as Array).append(">%dG" % int(card["price"]))
		return v2
	# 병사카드도 같은 스탯 시트 — 매물은 기본값(버프 없음)을 보여준다. 가격은 카드 얼굴에 있다
	var d: Dictionary = card["def"]
	var job: Dictionary = JOBS[d["job"]]
	var target = _target_boss()
	var cnt: int = int(card["count"])
	var l: Array = []
	l.append("[%s] [%s] · %s %d명 (상한 %d)" % [str(d["race"]), str(job["name"]),
		str(SIZES[d["size"]]["name"]), cnt, int(d["cap"])])
	l.append("")
	l.append_array(_stat_rows(d, float(d["hit"]), float(d["period"]),
		float(CRIT_BASE.get(str(d["job"]), 0.0)),
		float(CRIT_MULT_BASE.get(str(d["job"]), 2.0)), target))
	if str(job["atk"]) == "phys" and target != null \
			and _phys_damage(float(d["hit"]), target) <= 0.0:
		l.append("!지금 보스에게 딜 0")
	return {"title": str(d["name"]), "color": Color(job["color"]), "lines": l,
		"skill": _skill_footer(d)}


func _view_relic(it: Dictionary, equipped: bool) -> Dictionary:
	var l: Array = []
	l.append("유물 · %s · %s" % [str(RELIC_GRADES[str(it["grade"])]["name"]),
		str(it["base"]["name"])])
	l.append(">%s  받는 칸 %d" % [_relic_tag_text(it), _relic_live(it)])
	for o in it["opts"]:
		l.append(_opt_text(o, int(it["grown"])))
	if str(it["verb"]) != "":
		l.append("")
		l.append(">%s — %d타격마다" % [str(it["short"]), int(it["hits"])])
		l.append(str(it["desc"]))
	if _relic_live(it) == 0:
		l.append("!받는 칸이 없다 — 아무 일도 안 한다")
	return {"title": str(it["name"]), "color": Color(it["color"]), "lines": l}


func _view_boss(b) -> Dictionary:
	if b == null:
		return {}
	var e: Dictionary = b["entry"]
	var l: Array = []
	l.append(">%s" % (" · ".join(b["tags"]) if not (b["tags"] as Array).is_empty() else "접두사 없음"))
	l.append("체력 %d / %d" % [int(b["hp"]), int(b["hp_max"])])
	if float(b["shred"]) > 0.0:
		l.append(">방어력 %.0f  (파쇄 -%.0f)" % [_armor_now(b), float(b["shred"])])
	elif float(b["harden"]) > 0.0:
		l.append(">방어력 %.0f  (경화 — 계속 오른다)" % _armor_now(b))
	else:
		l.append("방어력 %.0f" % _armor_now(b))
	l.append(_res_line(b))
	if float(b["evade"]) > 0.0:
		l.append(">회피 %d%% — 물리만 빗나간다" % int(round(float(b["evade"]) * 100.0)))
	l.append("전진 %.0f%s" % [float(b["speed"]),
		"  (빙결)" if float(b["chill"]) > 0.0 else ""])
	if float(b["regen"]) > 0.0:
		var rg: float = float(b["regen"]) * (BURN_REGEN_CUT if int(b["burn"]) > 0 else 1.0)
		l.append(">회복 %.0f/s%s" % [rg, "  (화상이 절반 깎음)" if int(b["burn"]) > 0 else ""])
	if bool(b["bind"]):
		l.append(">%.1fs마다 아군 한 칸을 주박한다" % BIND_INTERVAL)
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
			float(b["base"]["wall_int"])])
	for line in _prefix_hints(e):
		l.append("~%s" % line)
	return {"title": "%s #%d" % [str(e["name"]), int(b["index"]) + 1],
		"color": Color(e["tint"]), "lines": l}


# 접두사는 「무엇이 막히는가」로 정의되므로, 상세 카드도 막는 것과 답을 그대로 적는다.
# 예고에서 본 단어가 전투에서 다시 보이고, 같은 문장이 두 곳에서 읽힌다.
func _prefix_hints(e: Dictionary) -> Array:
	var out: Array = []
	for p in e["pre"]:
		var d: Dictionary = PREFIXES[str(p)]
		out.append("%s: %s → %s" % [str(d["name"]), str(d["blocks"]), str(d["answer"])])
	if out.is_empty():
		out.append("맨몸이다 — 아무거나 통한다")
	return out


func _view_forecast() -> Dictionary:
	if _next_spawn >= _schedule.size():
		return {"title": "예고", "color": Color(0.5, 0.53, 0.6),
			"lines": ["~남은 보스가 없다"]}
	var e: Dictionary = _schedule[_next_spawn]
	var l: Array = []
	l.append(">%s" % (" · ".join(_entry_tags(e)) if not (e["pre"] as Array).is_empty()
		else "접두사 없음"))
	l.append("%s · %s" % [str(ACTS[int(e["act"])]["name"]),
		"막보스" if bool(e["boss"]) else "정예"])
	l.append("%.0fs 뒤 등장" % maxf(0.0, _spawn_due() - _elapsed))
	l.append("")
	l.append("체력 %.0f · %s" % [float(e["hp"]), str(e["base"]["size"])])
	l.append("방어력 %.0f · 전진 %.0f · 회피 %d%%" % [float(e["armor"]), float(e["speed"]),
		int(round(float(e["evade"]) * 100.0))])
	var parts: Array = []
	for el in ELEM_ORDER:
		parts.append("%s %d%%" % [str(ELEMENTS[el]["short"]),
			int(round(float(e["res"][el]) * 100.0))])
	l.append(" ".join(parts))
	l.append("")
	for line in _prefix_hints(e):
		l.append("~%s" % line)
	return {"title": "예고 — %s #%d" % [str(e["name"]), _next_spawn + 1],
		"color": Color(e["tint"]), "lines": l}


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
		"딜 0 타격 %.0f%% · 빗나감 %.0f%% · 물리 감산 손실 %.0f%%"
			% [_zero_ratio(), _miss_ratio(), _phys_loss()],
		"유물 발동 %d회 · 스킬 발동 %d회" % [_log_relic_fires, _skill_fire_total()],
		"인원 채움 %d / %d · 남은 골드 %d" % [_crew_now(), _crew_cap(), _gold],
	]
	var y: float = 140.0
	for r in rows:
		_txt(_font, panel.position + Vector2(36.0, y), str(r), 24, Color(0.86, 0.89, 0.95))
		y += 38.0
	_txt(_font_s, panel.position + Vector2(36.0, 390.0), "[R] 다시 시작", 20, Color(0.65, 0.70, 0.80))
