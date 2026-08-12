# i18n 텀코드 마이그레이션 계획

> **상태: 미실행** — 이 문서는 실행 계획이다. 실행 후 이 문서를 삭제하거나 「완료」로 표기한다.
> 2026-08-12 사용자 확정: 데이터 CSV의 카테고리 컬럼(faction·job·element)을 한글 리터럴 → 영문 코드로 바꾸고, 표시용 텀 키를 text.csv에 추가한다.

## 배경 · 원칙

언어 추가 비용을 "text.csv에 컬럼 하나 추가"로 끝내려면, **표시 텍스트가 i18n 밖에 존재하면 안 된다.**
현재 유일한 위반이 [units.csv](../../src/data/units.csv)의 `faction`/`job`/`element` 한글 리터럴이다 (식별자 겸 표시 텍스트로 이중 사용 중).

- 데이터 CSV: 영문 코드만 (`HUMAN`, `KNIGHT`, `FIRE` …)
- 표시: `tr("FACTION_" + faction)` 처럼 텀 키로
- skills.csv는 `target`/`effect`가 이미 영문 코드라 **변경 불필요**

## 작업 1 — units.csv 값 치환

### faction (5종)

| 현재 | 코드 |
|---|---|
| 인간 | `HUMAN` |
| 다크엘프 | `DARKELF` |
| 언데드 | `UNDEAD` |
| 수인족 | `BEAST` |
| 악마 | `DEMON` |

주의: 바이킹 유닛(U_VK_*)의 faction은 인간 → `HUMAN`이다 (unit_id 접두사 VK와 무관).

### job (7종)

| 현재 | 코드 |
|---|---|
| 기사 | `KNIGHT` |
| 궁수 | `ARCHER` |
| 마법사 | `MAGE` |
| 사제 | `PRIEST` |
| 암살자 | `ASSASSIN` |
| 전사 | `WARRIOR` |
| 리더 | `LEADER` |

### element (5종)

| 현재 | 코드 |
|---|---|
| 번개 | `LIGHTNING` |
| 독 | `POISON` |
| 냉기 | `COLD` |
| 화염 | `FIRE` |
| 랜덤 | `RANDOM` |

빈 칸(원소 없음)은 빈 칸 그대로 둔다.

## 작업 2 — text.csv 텀 키 추가

[text.csv](../../src/data/i18n/text.csv) 끝에 추가한다. en 표기는 실행 시점에 조정 가능.

```csv
FACTION_HUMAN,인간,Human
FACTION_DARKELF,다크엘프,Dark Elf
FACTION_UNDEAD,언데드,Undead
FACTION_BEAST,수인족,Beastfolk
FACTION_DEMON,악마,Demon
JOB_KNIGHT,기사,Knight
JOB_ARCHER,궁수,Archer
JOB_MAGE,마법사,Mage
JOB_PRIEST,사제,Priest
JOB_ASSASSIN,암살자,Assassin
JOB_WARRIOR,전사,Warrior
JOB_LEADER,리더,Leader
ELEMENT_LIGHTNING,번개,Lightning
ELEMENT_POISON,독,Poison
ELEMENT_COLD,냉기,Cold
ELEMENT_FIRE,화염,Fire
ELEMENT_RANDOM,랜덤,Random
```

키 규칙: 텀 키는 `카테고리_코드` 형식이라 코드값으로부터 기계적으로 만들 수 있다 — `tr("JOB_" + job)`.

## 작업 3 — 코드 영향

**2026-08-12 기준 없음.** units.csv·skills.csv를 읽는 .gd 파일이 없다 (프로토타입 2종은 자체 하드코딩 데이터 사용).
실행 시점에 재확인할 것:

```
grep -rn "units.csv\|skills.csv" --include="*.gd" .
```

결과가 나오면 해당 파일이 faction/job/element 값을 비교·표시하는 부분을 새 코드값 기준으로 고쳐야 한다.

## 검증

1. units.csv에 한글이 남아 있지 않은지 확인 (`name_key` 컬럼은 원래 키만 있음):
   `grep -n "[가-힣]" src/data/units.csv` → 결과 0줄이어야 함
2. Godot 에디터에서 재임포트 후 `src/data/i18n/text.ko.translation` 생성 확인.
   - **별건 이슈:** 현재 ko translation 파일이 없고, [text.csv.import](../../src/data/i18n/text.csv.import)의 `dest_files`에 en이 두 번 기재되어 있다(ko 자리에 en). 재임포트로 해결되는지 확인하고, 안 되면 .import 파일 삭제 후 재임포트.
3. 게임(또는 프로토타입이 데이터 CSV를 읽게 된 이후) 실행 시 진영·직업·원소가 로케일에 맞게 표시되는지 확인.
