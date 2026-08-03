# combat-tuning — 방법론 출처

> 본 skill에서 쓰는 임계값·공식의 근거. 의문이 생기면 여기에서 출처를 확인한다.

---

## 1. TTK / TTD — 전투 밸런스 단일 핵심 메트릭

> "전투 밸런스에서 가장 비판적 메트릭은 TTK — 두 엔티티가 서로를 파괴하는 데 걸리는 시간."

- TTK가 짧을수록(0.2s급) 첫 타격·반응속도가 결과를 좌우 → 긴장감↑ 전략깊이↓
- TTK가 길수록(1s+) 지속 교환·포지셔닝 비중↑ → 전략깊이↑ 페이스↓
- 우리 게임은 오토배틀(플레이어 입력 없음) → TTK 자체보다 **TTK 비율(아군/적)** 이 더 중요. 비율이 의도와 맞으면 "이긴다", 어긋나면 "진다".

**우리 프로젝트 적용**:
- 표준 매치업의 TTK는 시뮬에서 자동 추출
- 비율 1.0 ± 0.15 면 균형 매치업, 1.5 이상이면 한쪽 압승
- 보스 TTK는 잡몹의 5~6배가 의도값(WAVE_DESIGN.md 기준)

출처:
- [Time to kill — Game Balance Project Wiki](https://tgbp.fandom.com/wiki/Time_to_kill)
- [Game Balancing Tips for Fair & Fun Play (Hitem3D)](https://www.hitem3d.ai/blog/en-Game-Balancing-How-to-Create-Fair-and-Engaging-Gameplay/)

---

## 2. Riot 밸런스 프레임워크 — 비대칭 임계값

> 버프와 너프의 임계값을 다르게 둔다. 너프는 빠르고, 버프는 느리다.

Riot의 LoL/TFT 공식:
- **너프 조건**: 단 한 그룹(Average/Skilled/Elite/Pro)에서라도 OP면 즉시
- **버프 조건**: 모든 그룹에서 동시에 약화되어야

이유: OP 카드는 메타를 빠르게 망가뜨리지만(다른 카드를 dominated로 만듦), 약한 카드는 메타에 손해를 적게 줌. 따라서 너프는 false positive를 감수하고 빠르게, 버프는 false positive를 피해 신중하게.

**우리 프로젝트 적용 (PvE이므로 변형)**:
- 4개 그룹 → 우리는 **3개 단계** (Early W1~5 / Mid W6~12 / Late W13~20)
- 너프: 한 단계에서라도 카드가 매치업 승률 70% 초과면 너프 후보
- 버프: 세 단계 모두에서 픽률 평균 미만 + 매치업 승률 35% 미만이어야 버프 후보

출처:
- [/dev: Balance Framework Update — Riot Games](https://www.leagueoflegends.com/en-us/news/dev/dev-balance-framework-update/)

---

## 3. LUDUS — 오토배틀러 카드 밸런싱 프레임워크

학술 논문(AAAI 2022). 오토배틀러 카드 밸런스를 최적화 문제로 정식화.

**핵심 아이디어**:
1. N장 카드에서 K장씩 뽑아 라인업 생성 (모든 조합)
2. 라인업끼리 라운드로빈 토너먼트
3. 각 카드의 **참여 라인업들의 승률 표준편차** 계산
4. 표준편차가 클수록 그 카드는 "라인업 의존적" (= 좋은 밸런스)
5. 표준편차가 작으면 그 카드는 무조건 강하거나 무조건 약함 (= 균형 깨짐)
6. 유전 알고리즘으로 카드 스탯을 정수 1~10 범위에서 최적화

**우리 프로젝트 적용**:
- 우리는 PvE라 "라인업 vs 라인업"이 아니라 "라인업 vs 웨이브"
- 변형: 같은 코스트 유닛 N개 단독 편성 vs 표준 웨이브 → 클리어 시간의 분산 측정
- 분산이 0에 가까우면(어떤 편성이든 똑같이 클리어) 의사결정이 사라짐
- 분산이 너무 크면(특정 편성만 클리어) 지배 전략 존재

출처:
- [LUDUS: An Optimization Framework to Balance Auto Battler Cards (AAAI)](https://ojs.aaai.org/index.php/AAAI/article/view/21550/21299)

---

## 4. Mechabellum 패치 패턴 — 노브 우선순위

실제 라이브 게임 데이터:

- **OP 유닛 너프**: 단순 수치보다 **cost↑ + 효과↓** 묶음 (예: Smoke Bomb 250→350코스트 + 폭탄수 10→8)
- **역할 재정의 너프**: DPS는 유지하면서 attack speed만 늦춰 "작은 유닛 청소" 역할 박탈 (Vortex)
- **거대 유닛 미세조정**: HP −5% 같은 작은 단위 (Fortress)

→ **권장 노브 순서 (큰 → 작은)**:
1. ROLE_MULT (역할 자체 재정의)
2. archetype 비율 (tank↔dps 무게중심)
3. cost (가격 흡수)
4. 스킬 효과 (조건/수치)
5. raw 스탯 (마지막, ±10% 이내)

출처:
- [Mechabellum 패치노트 모음 (MechaMonarch)](https://mechamonarch.com/news/)
- [Mechabellum Brawl Patch Strategy Guide (Z League)](https://www.zleague.gg/theportal/cobrak-strategy-sandworm-buffs-huge-fortress-and-melter-nerfs-mechabellum-balance-update-guide/)

---

## 5. Dominant / Dominated Strategy

게임이론 기본 개념을 게임 디자인에 적용:

- **Dominant**: 다른 모든 옵션보다 항상 좋음 → 모든 플레이어가 이걸만 픽 → 의사결정 없음
- **Dominated**: 다른 어떤 옵션보다 항상 나쁨 → 누구도 안 픽 → 죽은 카드

**Intransitive 메카닉(가위바위보)**:
- A > B > C > A 구조를 의도적으로 만듦
- 어떤 카드도 항상 우월하지 않음 → 메타 다양성 보장

**우리 프로젝트 적용**:
- 직업 9종 × 죄종 7종 매트릭스에 의도된 가위바위보 관계가 있어야 함
- 변경 후 시뮬에서 한 카드가 모든 매치업에서 1등이면 dominant 후보
- 어떤 매치업에서도 픽되지 않으면 dominated 후보

출처:
- [Strategic dominance — Wikipedia](https://en.wikipedia.org/wiki/Strategic_dominance)
- [RTS-balancing-research](https://valdiviadev.github.io/RTS-balancing-research/)
- [What is Dominant Strategy? — Machinations.io](https://machinations.io/glossary/dominant-strategy)

---

## 6. Power Score 공식 — Designer-Facing

`docs/reference/ref_unit_balancing_process.md` 와 동일 출처. 핵심 공식만 재기재:

```
DPS   = ATK / attack_speed
EHP   = HP × (1 + DEF × k_arm)        k_arm = 0.10 잠정
POWER = DPS × EHP × ROLE_MULT
```

기준 유닛 `orc` = POWER 1.0. 모든 다른 유닛은 "기준의 N배"로 표현.

ROLE_MULT 잠정값:

| 특성 | 배수 |
|---|---|
| 원거리 | ×1.20 |
| 고기동 (move_speed≥150) | ×1.15 |
| 부활/사망 강화 | ×1.30 |
| 디버프 (공깎/공감) | ×1.20 |
| 분열·소환 | ×1.30 |
| 미니보스 | ×1.40 |
| 보스 | ×1.80 |

출처:
- [Balancing a Game the Right Way: Make Stats Designer-Facing — Game Developer](https://www.gamedeveloper.com/design/balancing-a-game-the-right-way-make-stats-designer-facing)
- [Tracking Power Curves Through Progression — Game Wisdom](https://game-wisdom.com/critical/power-curves-game-design)

---

## 7. 시뮬레이션 인프라 — Unity Game Simulation 모델

Unity의 Game Simulation 서비스가 보여준 패턴:

> 실제 게임 코드를 헤드리스로 수만 회 자동 플레이 → 클라우드에서 분산 실행 → 결과 통계.

**우리 프로젝트 적용 방향** (인프라 미구축 시 권장 가이드):

1. `BattleSimulator` 를 헤드리스로 동작하도록 분리 (시각 효과·HUD 제거된 변형)
2. `src/tools/sim_runner.gd` — 매치업 입력(라인업 A, B, 시드)을 받아 결과(승자, TTK, 잔존)를 JSON으로 반환
3. Godot CLI: `godot --headless --script src/tools/sim_runner.gd -- --matchup config.json --runs 200`
4. 결과 집계 스크립트 (Python 또는 GDScript) → 매치업 표 생성

출처:
- [Optimize your game balance with Unity Game Simulation](https://blog.unity.com/technology/optimize-your-game-balance-with-unity-game-simulation)
- [Run automated tests for your Godot game on CI — David Saltares](https://saltares.com/run-automated-tests-for-your-godot-game-on-ci/)
- [GUT — Godot Unit Test](https://github.com/bitwes/Gut)

---

## 8. 검증 임계값 요약 (본 skill 기본값)

| 항목 | 임계값 | 판정 |
|---|---|---|
| POWER 의도 곡선 편차 | ±15% | 정상 |
| 〃 | ±15~30% | 경계 (재검토) |
| 〃 | ±30% 초과 | 이상 (즉시 재조정) |
| 매치업 승률 | 35~65% | 균형 |
| 〃 | 30~70% | 허용 |
| 〃 | 30% 미만 또는 70% 초과 | 깨짐 |
| 거울전 tie 비율 | 5% 미만 | 결정론 정상 |
| 시너지 브레이크포인트 power 증가 | ×1.15~1.30 | 적정 |
| 〃 | ×1.5 이상 | 강제 시너지 (자유도 상실) |
| TTK 비율 (아군/적) | 0.85~1.15 | 균형 매치업 |
| 보스 TTK / 잡몹 TTK | 5~6배 | 의도값 |

이 표는 본 skill 출력의 "판정" 칼럼 기준이다. 사용자 합의로 조정 가능.