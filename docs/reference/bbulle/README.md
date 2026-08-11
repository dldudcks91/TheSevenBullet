# 대용병시대 뿔레전쟁 — 수집 자료

외부 게임 참고자료. **이 프로젝트의 기획 확정 내용이 아니다.**

## 대상 게임

| 이름 | 비고 |
|---|---|
| 대용병시대 - 뿔레전쟁 시즌2 | 구 「뿔레전쟁 클리커」(2016). 패키지 `com.BbulleGames.BbulleWarClicker` |
| 대용병시대 뿔레전쟁 시즌3 | 2019~, iOS `id1471588673`. 개발사 (주)순순팩토리 |

원작은 워크래프트3 유즈맵 「뿔레전쟁」이고, 위 둘은 그 세계관을 쓴 모바일 방치형 게임이다.
게임 내 유닛은 '영웅'이 아니라 **용병**이며 300여 종이라고 스토어에 표기돼 있다.

## 파일

| 파일 | 내용 |
|---|---|
| `bbulle_mercenaries.csv` | 확인된 용병 이름 84종 + 알아낸 등급·공격타입·스킬 단서 |
| `bbulle_systems.csv` | 공격타입·스탯·스킬·덱 용어 정의 |

`confidence` 컬럼: `medium` = 위키/블로그에 서술이 있음, `low` = 이름만 확인됨(스토어 패치노트 등).
표기 오차 가능성이 있으므로 확정 데이터로 쓰기 전 대조 필요.

## 수집 범위와 한계

**개별 용병 300종의 스킬표는 공개 웹에 존재하지 않는다.** 확보한 건 이름 84종과 시스템 용어까지다.

접근이 막혀 못 뚫은 곳:

- 네이버 전 도메인 — WebFetch 불가. 공식 개발일지 블로그(`blog.naver.com/bbulle`)에 용병별 소개 글이 실재하는 것까지는 검색 결과로 확인했으나 본문 접근 실패. 실질적 정보 창구인 [공식 카페](http://cafe.naver.com/bbulle)도 동일.
- `web.archive.org` — 차단. 우회 아카이브 불가.
- `bbulle.shop` (팬 DB 추정) — TLS 핸드셰이크 실패.
- `soonsoons.com`(개발사), `day7games.com`(구 퍼블리셔) — 커넥션 거부, 사이트 사망.
- `thewiki.kr` / `apkpure` / `appbrain` / `dogdrip` — 403.

뚫렸으나 데이터가 없던 곳: 나무위키(본편·클리커), 디시 방치형·모바일게임 갤러리(전용 갤러리 없음), 루리웹, 헝그리앱, QooApp, TapTap, 앱스토어, 티스토리 리뷰 블로그 다수.
용병명 역검색(`"RBD-719" 뿔레전쟁`)은 결과 0건 — 위키화가 안 된 게임이다.

남은 경로는 **게임 내 도감 스크린샷** 또는 **네이버 카페 글 본문 전달**뿐이다.

## 출처

- [나무위키 — 뿔레전쟁 클리커](https://namu.wiki/w/%EB%BF%94%EB%A0%88%EC%A0%84%EC%9F%81%20%ED%81%B4%EB%A6%AC%EC%BB%A4) — 시스템·용어의 주 출처
- [나무위키 — 뿔레전쟁](https://namu.wiki/w/%EB%BF%94%EB%A0%88%EC%A0%84%EC%9F%81) / [뿔레전쟁/영웅](https://namu.wiki/w/%EB%BF%94%EB%A0%88%EC%A0%84%EC%9F%81/%EC%98%81%EC%9B%85) — 원작 유즈맵. 이쪽은 영웅 30여 명의 스킬 전문이 정리돼 있어 필요하면 추가 수집 가능
- [App Store — 시즌3](https://apps.apple.com/kr/app/id1471588673) / [QooApp — 시즌2](https://m-apps.qoo-app.com/ko-KR/app/7289) — 패치노트에서 용병명 확보
- [nowordeath.tistory.com/306](https://nowordeath.tistory.com/306), [junklab.net](https://junklab.net/2017/12/%EB%BF%94%EB%A0%88%EC%A0%84%EC%9F%81-%ED%81%B4%EB%A6%AC%EC%BB%A4-300%EA%B0%81-%EB%8B%AC%EC%84%B1/) — 니모·라꽈 조합 등 단편 정보
