---
name: client-review
description: "변경된 GDScript 파일의 품질을 검토한다. 게임 디자인 정합성, GDScript 코드 품질을 확인하고 APPROVED / CHANGES REQUIRED 판정을 출력한다."
argument-hint: "[검토할 파일 경로]"
user-invocable: true
allowed-tools: Read, Glob, Grep
---

# Client Review

## Phase 1: 파일 로드

대상 파일과 CLAUDE.md를 읽는다.
경로가 없으면 최근 변경된 `src/` 파일을 Glob으로 찾아 확인한다.

---

## Phase 2: 게임 디자인 정합성

CLAUDE.md의 핵심 방향을 기준으로 확인:
- [ ] 병사는 교체 가능한 카드로 취급되는가 (개별 서사 로직 없는가)
- [ ] 재화 수치가 `src/data/`에 분리되어 있는가
- [ ] 적 유닛 정보 공개 타이밍이 라운드 시작인가
- [ ] 프로토타입 코드가 `src/`에 혼입되지 않았는가

---

## Phase 3: GDScript 품질

- [ ] 공개 메서드에 설명 주석이 있는가
- [ ] 메서드 길이가 40줄 이하인가
- [ ] 시스템 간 통신에 signal을 사용하는가
- [ ] 게임 상태를 직접 참조하는 전역 싱글톤이 없는가
- [ ] 업데이트 루프에 불필요한 객체 생성이 없는가

---

## Phase 4: 판정 출력

```
## 코드 리뷰: [파일명]

### 디자인 정합성: [통과 / 이슈 있음]
[이슈가 있으면 구체적으로 기술]

### GDScript 품질: [통과 항목 수]/5
[실패 항목과 해당 줄 번호]

### 긍정적인 부분
[잘 된 점 반드시 포함]

### 판정: APPROVED / CHANGES REQUIRED
[필수 수정 사항 목록, 없으면 "없음"]
```
