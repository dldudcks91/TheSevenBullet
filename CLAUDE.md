# TheSevenBullet

## 프로젝트 개요

> 이 파일은 Claude와의 **협업 규칙 + 문서 지도("어디를 봐야 하는지")**만 담는다.
> **게임 디자인·시스템 규칙·수치는 여기에 적지 않는다** — 단일 출처는 [docs/game_design/GAME_DESIGN.md](docs/game_design/GAME_DESIGN.md) 다.

> **현재 상태:** 기획 중. 전투 모델은 큰 틀이 잡혔고 구현은 시작 전이다. 장르·방향은 [GAME_DESIGN.md](docs/game_design/GAME_DESIGN.md)에만 적는다 — **오토배틀러가 아니라 로그라이크 타워디펜스다.** 다음에 무엇을 정해야 하는지는 그 문서의 「미결」에 모여 있다.
>
> 툴링(스킬·에이전트·컨벤션)은 TheSevenAutoBattle에서 가져온 골격이라, 오토배틀러/오토체스 전제가 남은 서술이 곳곳에 있다. `prototypes/` 두 개도 현재 설계보다 앞선 시점의 것이라 그대로 참고하면 안 된다.

---

## 작업 규칙

- **모든 개발 작업 진행 전 `docs/` 폴더의 관련 기획 문서를 확인한다.**
- 코드 변경 전 반드시 현재 파일을 Read한 후 Edit한다.
- 커밋은 사용자가 명시적으로 요청할 때만 생성한다.
- **유닛·몬스터 스탯 데이터는 반드시 `src/data/` 폴더의 CSV 파일로 저장한다. MD 파일에 스탯 표를 작성하지 않는다.**
- **표시 텍스트(이름·설명 등)는 `src/data/i18n/text.csv`에 모은다.** 데이터 CSV의 텍스트 컬럼은 `*_key` 형식의 번역 키(`UNIT_SOLDIER`, `ITEM_BOOTS_BASIC` 등)만 담고, 코드에서 `tr(key)`로 꺼내 쓴다. 데이터 CSV의 `.import`는 `importer="keep"`으로 두어 Godot의 csv_translation 임포터를 거치지 않게 한다(컬럼명이 로케일로 오인됨).

### 문서 단일 출처 (Single Source of Truth)

- **하나의 결정은 한 곳에만 적는다.** 같은 내용이 두 파일에 있으면, 한쪽만 고쳐졌을 때 어느 쪽이 진실인지 알 수 없게 된다.
- 책임 분리:
  | 무엇 | 어디 |
  |---|---|
  | 수치 (스탯·가격·코스트·확률) | `src/data/**.csv` 또는 코드 상수 |
  | 게임 시스템 규칙·의도·미결 항목 | `docs/game_design/*.md` |
  | 작업 규칙·컨벤션 | `.claude/skills/<skill-name>/SKILL.md` |
  | 협업 규칙 + 문서 지도 | `CLAUDE.md` (이 파일) |
- **CLAUDE.md에 기획 세부를 옮겨 적지 않는다.** 여기에는 방향 감각과 "어디를 봐야 하는지"만 둔다.
- 설계가 바뀌면 **단일 출처 문서를 고치고, 다른 문서의 상충 서술은 그 자리에서 지운다.** 낡은 서술을 남겨두지 않는다.

### 규칙 저장 위치

- **프로젝트 규칙·컨벤션은 항상 `.claude/skills/<skill-name>/SKILL.md` 에 작성한다.**
- 메모리(`memory/`)에는 규칙을 넣지 않는다 — 규칙은 휘발되면 안 되고 프로젝트와 함께 버전 관리되어야 하므로 skills가 정확한 위치다.
- 메모리는 사용자 정보·작업 컨텍스트·일시적 사실 등 비-규칙성 메모에만 사용한다.
- 새 규칙이 정해지면: skill 파일을 만들고, 필요하면 CLAUDE.md 또는 기존 skill에서 참조한다.

> **참고:** `.claude/skills/*` 는 AutoBattle에서 복사한 골격이라 일부 스킬(`combat-tuning`, `client-implement` 등)에 오토체스 모델 특정 서술이 남아 있을 수 있다. 해당 스킬을 처음 쓸 때 이 프로젝트 기준으로 정리한다.

---

## 문서 지도 (어디를 봐야 하는지)

> 게임 디자인의 단일 출처는 [GAME_DESIGN.md](docs/game_design/GAME_DESIGN.md) 다. 아래는 주제별 진입점만 둔다.

| 주제 | 문서 |
|---|---|
| **게임 전체 설계** — 기획 단일 출처 | [GAME_DESIGN.md](docs/game_design/GAME_DESIGN.md) |
| 격자 모델 갈림길 (3×3 영웅 / 4×4 포커) — **결정 완료**, 왜 그렇게 정했는지의 기록 | [GRID_MODEL_OPTIONS.md](docs/game_design/GRID_MODEL_OPTIONS.md) |
| 스프라이트 카탈로그 — 진영 × 역할, 사용 가능 등급 | [sprite_catalog.csv](src/data/sprite_catalog.csv) |

> 세부 문서(전투·시너지·유닛·씬 등)는 기획이 진행되며 이 표에 추가한다. **문서를 만들기 전에 항목을 미리 적어두지 않는다** — 없는 파일을 가리키는 죽은 링크를 남기지 않기 위함이다.

---

## 기술 스택

- Engine: Godot 4 (GDScript)
- Platform: Steam (PC)

---

## 디렉토리 구조

```
docs/
  game_design/  # 게임 디자인 문서 (기획 단일 출처)
  reference/    # 레퍼런스 자료
src/
  data/         # 밸런스 데이터 (CSV) + i18n 텍스트
    i18n/       # 번역 CSV (keys,ko,en) — Godot이 .translation 파일로 자동 임포트
```

> 위는 현재 존재하는 골격이다. `src/battle`, `src/ui` 등 코드 디렉토리는 구현이 시작되며 추가하고, 구조가 정해지면 이 표를 갱신한다.
