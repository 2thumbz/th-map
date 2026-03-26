# ROOT SOURCE Prompt

아래 프롬프트를 그대로 복사해서 코딩 에이전트(예: Copilot Chat)에 넣으면, 이 프로젝트에서 지금까지 진행한 내비게이션 기능 개선을 같은 방향으로 구현/수정할 수 있다.

---

## Master Prompt

당신은 Flutter 내비게이션 앱 유지보수 시니어 엔지니어다.
작업 대상은 `c:/nav-app/my_nav_app`이며, 핵심 파일은 `lib/main.dart`다.
목표는 오프라인 지도 안정성, 재탐색 품질, 안내 정확도, 지도 UX, 시각화, 디바이스 동작 안정성, 회전 제약 데이터 품질을 실사용 수준으로 개선하는 것이다.

아래 요구사항을 모두 반영해 코드 수정, 패키지 반영, 빌드 검증까지 끝내라.

### 1) 오프라인 타일 안정화
- 오프라인 타일 파일명에서 zoom 레벨을 추출해 min/max zoom 범위를 동적으로 계산한다.
- `TileLayer`에 `minNativeZoom`, `maxNativeZoom`, `panBuffer`를 적용한다.
- nullable zoom 값으로 인한 타입 오류를 방지하기 위해 안전한 fallback(`??`)을 넣는다.
- 인터넷 연결 시 온라인 OSM 레이어를 백업 배경으로 함께 렌더링한다.

### 2) 재탐색(reroute) 정책 개선
- 재탐색 트리거는 "경로 이탈 거리 기반"만 사용한다.
- 기존 "가까운 노드 변경" 기반 트리거는 제거한다.
- 재탐색 시작 노드는 현재 위치 근처 후보 중에서 차량 heading과 가장 일치하는 노드를 우선 선택한다.
- 역방향 링크로 잘못 진입하는 가능성을 줄이기 위해 heading 오차 허용치 기반 필터/점수화를 적용한다.

### 3) 안내 거리/다음 기동작 지점 정확도 개선
- 다음 안내 거리 계산을 "현재 GPS 위치" 기준으로 바꾼다.
- 경로 폴리라인 상에 현재 위치를 투영(project)하는 공용 헬퍼를 만든다.
- `_updateNextManeuver`, `_distanceToManeuverMeters`, `_remainingDistanceMetersFromLocation`가 동일한 투영 로직을 재사용하게 한다.
- 교차로 직전 안내 handoff 튐 현상을 줄이기 위해 handoff 거리 임계값(예: 12m)을 둔다.

### 4) 지도 Follow UX 개선
- 내비 중 사용자가 지도 드래그/줌하면 자동 따라가기를 일시 정지한다.
- 5초 후 자동으로 follow 상태로 복귀한다.
- 내비 중 follow 줌 값을 별도 상태로 유지한다.
- 내비 여부와 무관하게 위치 업데이트 시 지도 중심은 현재 위치를 따라가도록 정리한다(단, 일시정지 상태는 존중).
- 타이머 lifecycle(시작/종료/dispose) 누수 없이 정리한다.

### 5) 경로 시각화 개선 (T-map 스타일 방향성)
- 경로선을 이중 폴리라인(바깥 진한색 + 안쪽 밝은색)으로 렌더링한다.
- 일정 간격(예: 45m)으로 경로 방향 화살표 마커를 배치한다.
- 화살표는 실제 진행 방향을 바라봐야 한다. 아이콘 기본 방향축과 bearing 축 차이를 보정한다.
- 마커 개수 상한을 둬 렌더링 성능을 보호한다.

### 6) 주행 중 화면 꺼짐 방지
- `wakelock_plus` 패키지를 추가한다.
- 내비 시작 시 화면 켜짐 유지 enable.
- 내비 종료 및 dispose 시 disable.

### 7) 정차 중 속도 노이즈 억제
- GPS 저속 노이즈(예: 2km/h) 제거를 위해 아래 로직을 넣는다.
- 속도가 낮고 이동거리도 작은 상태가 연속 N회 이상이면 속도를 0으로 보정한다.
- 시작/종료/시뮬레이션 종료 등 내비 상태 전환 시 카운터를 초기화한다.

### 8) UI 정리
- 하단 액션에서 필요 없는 `경로계산` 버튼은 제거한다.
- 기존 기능 동작(경로 존재 시 시작/정지 버튼 동작)은 유지한다.

### 9) 문서화
- `README.md`에 업데이트 로그 섹션을 추가/유지하고, 이번 변경사항을 날짜별로 기록한다.

### 10) TURNINFO 기반 회전 제약
- `TB_TURNINFO` 테이블을 기준으로 링크 전이 제약을 반영한다.
- `PREV_LINK_ID`, `NEXT_LINK_ID`는 모두 `links.id`를 참조해야 한다.
- 제약 키는 node가 아니라 `(PREV_LINK_ID, NEXT_LINK_ID)` 전이쌍이다.
- `TURN_TYPE` 금지 코드(`002`, `003`, `101`, `102`, `103`)는 경로 탐색에서 제외한다.
- 허용 코드(`001`, `011`, `012`)는 통과시킨다.
- 라우팅 엔진은 이전 링크 상태를 함께 들고 다니도록 구현한다.
- PostgreSQL 원본 테이블은 앱 SQLite 스키마와 다를 수 있다. 현재 기준 원본 `public."TB_TURNINFO"` 컬럼은 `gid`, `node_id`, `turn_id`, `st_link`, `ed_link`, `turn_type`, `turn_oper`, `remark` 구조다.
- 원본 `st_link`, `ed_link`는 앱의 `links.id`가 아니라 원천 도로 링크 식별자(`TB_AY_MOCT_LINK.LINK_ID`)이므로, API/export 단계에서 `LINK_ID -> links.id`로 재매핑해서 전달해야 한다.
- 원본 turninfo 총건수와 앱에 최종 반영되는 유효 전이 수가 다를 수 있다. 링크 미존재, 매핑 실패, 중복 제거, 교차로 불일치가 있으면 일부 전이는 제외해도 된다.
- 특정 잘못된 회전 안내가 남을 때는 로직을 더 복잡하게 만들기보다 먼저 전이 데이터 부재/누락 여부를 점검하고, 데이터가 없으면 현재 로직을 유지하는 편이 낫다.

### 11) TURNINFO 데이터 검증
- `TB_TURNINFO`에 전이쌍 유니크 인덱스를 둔다.
- `PREV_LINK_ID`, `NEXT_LINK_ID`는 `links.id` FK로 연결한다.
- 고아 링크, 중복 전이, 교차로 불일치(`prev.end_node != next.start_node`)를 정리하거나 리포트로 검출한다.
- `backend/src/turninfo_report.sql` 같은 검증 SQL을 유지한다.
- SQLite 번들 DB와 백엔드 스키마가 같은 규칙을 따르도록 맞춘다.

### 13) 내비게이션 카메라/마커 UX
- 안내 시작 줌은 `_navigationFollowZoomDefault = 16.0`으로 고정한다.
- 차량 마커 크기는 52x52px(기존 64x64의 약 0.8배).
- 안내 중 마커 회전은 GPS heading 대신 경로 투영 bearing(`_routeBearingForLocation`)을 우선한다. 투영 실패 시 `_carHeadingDeg`로 fallback.
- 화면 배치:
	- 가로: X 오프셋 = 0(중심선 고정)
	- 세로: `NavigationBottomPanel` 실측 높이를 `GlobalKey`로 읽어 패널 바로 위에 마커가 오도록 Y 오프셋을 매 프레임 동적 계산
	- 패널 높이 미확보 시 추정값(`_navigationBottomPanelEstimatedHeightPx = 86.0`) 사용

### 12) 검증/빌드
- `dart format` 적용.
- 정적 오류를 확인하고 타입 오류(특히 nullable 관련)를 모두 해결.
- 최종적으로 `flutter build apk` 성공까지 확인.
- 필요 시 `flutter build apk --debug`까지 확인하고 경고를 정리한다.
- 산출물 경로와 파일 크기를 결과로 보고.

## 구현 제약
- 기존 public API/화면 구조를 불필요하게 깨지 말 것.
- 변경은 최소 침습적으로 하되, 로직 중복은 공용 함수로 정리할 것.
- Timer, stream, state는 dispose 안전성을 우선할 것.
- 에러가 나면 원인-수정-재검증 순서로 진행할 것.

## 최종 보고 형식
1. 변경 파일 목록
2. 핵심 변경점 요약
3. 타입/런타임 이슈 해결 내역
4. 빌드 결과 (`flutter build apk`)
5. 후속 튜닝 포인트(임계값, UX 상수)

---

## 현재 주요 상수 (2026-03-26 기준)

| 상수 | 값 | 설명 |
|---|---|---|
| `_navigationFollowZoomDefault` | `16.0` | 안내 시작 줌 레벨 |
| `_navigationBottomPanelEstimatedHeightPx` | `86.0` | 하단 패널 추정 높이(실측 전 fallback) |
| `_navigationMarkerGapAbovePanelPx` | `18.0` | 패널 위 마커 여백 |
| `_rerouteOffPathThresholdMeters` | `30` | 경로 이탈 재탐색 임계 거리 |
| `_rerouteOffPathConsecutiveHits` | `2` | 이탈 연속 감지 횟수 |
| `_destinationArrivalMeters` | `20` | 도착 자동 종료 반경 |
| `_ttsPreviewFarMeters` | `500` | TTS 미리 안내 거리(원거리) |
| `_ttsPreviewNearMeters` | `150` | TTS 미리 안내 거리(근거리) |
| `_ttsNowMeters` | `30` | TTS 즉시 안내 거리 |

## Quick Use

- 이 파일의 "Master Prompt" 본문 전체를 복사해 에이전트에 입력한다.
- 필요 시 임계값만 프로젝트 상황에 맞게 바꿔서 재사용한다.
