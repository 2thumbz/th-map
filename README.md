# TH MAP

로컬 DB(오프라인)와 백엔드(DB/API) 모드를 모두 지원하는 Flutter 경로 안내 앱입니다.

## 1. 기능 명세

### 1.1 지도/경로 표시

- 현재 위치, 목적지, 계산된 경로(polyline) 표시
- 차량 아이콘 heading(방향각) 기반 회전 표시
- 경로 도로 시퀀스(요약)와 총 거리 표시

### 1.2 검색/목적지 선택

- 노드 ID 검색(SQLite 또는 PostgreSQL 제안)
- 좌표 직접 입력 검색(`lat,lng`)
- 지도 길게 누르기(long press)로 목적지 설정

### 1.3 내비게이션

- GPS 기반 실시간 주행(속도/방향/위치 추적)
- 다음 회전 안내(좌회전/우회전/유턴)
- 안내 중 속도(km/h) 카드 표시
- 목적지 근접(20m 이내) 시 자동 종료

### 1.4 자동 재탐색

- 거리 기반 재탐색: 현재 위치가 경로에서 일정 거리 이상 이탈하면 재탐색 후보
- 후보 시작점 보정: 현재 위치 주변 노드 중 차량 heading과 가장 잘 맞는 노드를 우선 선택
- 재탐색 쿨다운: 짧은 시간 내 과도한 재탐색 방지

현재 기본값(코드 상수):

- 경로 이탈 임계 거리: `30m`
- 연속 감지 횟수: `2회`
- 재탐색 쿨다운: `3초`

### 1.5 오프라인 우선 동작

- 기본 동작은 SQLite 오프라인 모드
- 네트워크/백엔드 미연결이어도 앱 사용 가능
- 오프라인 타일 존재 시 타일 에셋 우선 사용
- GPS 추적 오류 시 시뮬레이션 주행 모드 폴백

## 2. 데이터 소스 모드

### 2.1 SQLite 모드(기본)

- `ENABLE_BACKEND=false` (기본값)
- 로컬 `nodes`, `links`, `TB_TURNINFO` 테이블 사용
- DB가 비어 있으면 복구 로직 시도

### 2.2 PostgreSQL 모드(옵션)

- `ENABLE_BACKEND=true` 지정 시 백엔드 연결 시도
- 연결 실패 시 자동으로 SQLite로 폴백
- 기본 백엔드 URL:
	- Android 에뮬레이터: `http://10.0.2.2:3000`
	- 그 외: `http://localhost:3000`

## 3. 런타임 설정값(dart-define)

### 3.1 앱 실행 예시

```bash
# 기본: 오프라인(SQLite)
flutter run

# 백엔드 활성화
flutter run --dart-define=ENABLE_BACKEND=true

# 백엔드 URL 명시
flutter run \
	--dart-define=ENABLE_BACKEND=true \
	--dart-define=API_BASE_URL=http://192.168.0.10:3000

# 온라인 타일 강제(디버깅)
flutter run --dart-define=OFFLINE_MAP_TILES=false
```

### 3.2 지원 설정 키

- `ENABLE_BACKEND` : 백엔드 모드 사용 여부 (`true/false`)
- `API_BASE_URL` : 백엔드 API 기본 URL
- `OFFLINE_MAP_TILES` : 오프라인 타일 우선 여부 (`true/false`)

## 4. 오프라인 자원 구성

### 4.1 지도 타일

타일 에셋 경로 규칙:

```text
assets/tiles/{z}_{x}_{y}.png
```

주의:

- 특정 줌/영역 타일이 없으면 해당 영역은 빈 지도처럼 보일 수 있습니다.

### 4.2 SQLite DB 에셋

사전 생성 DB를 앱에 포함하려면:

1. `assets/db/nav_database.db` 위치에 파일 배치
2. `flutter pub get`
3. 앱 실행/빌드

최초 실행 시 로컬 DB가 없으면 에셋 DB를 복사합니다.

## 5. 백엔드 데이터에서 SQLite 생성

`backend`에서 SQLite 추출:

```bash
cd backend
npm run export:sqlite
```

백엔드 URL을 직접 지정하는 경우:

```bash
py backend/src/export_sqlite_from_api.py --api-base-url http://<host>:3000
```

추출 시 검증:

- `nodes.id`, `links.id` 중복 검증
- 필수 필드 누락 검증
- `links.start_node`, `links.end_node` 참조 무결성 검증
- `TB_TURNINFO` 검증 SQL은 `backend/src/turninfo_report.sql`에서 별도 제공

## 6. 빌드

### 6.1 Android APK

```bash
flutter build apk
```

디버그 APK 검증:

```bash
flutter build apk --debug
```

릴리즈 APK 산출물:

`build/app/outputs/flutter-apk/app-release.apk`

디버그 APK 산출물:

`build/app/outputs/flutter-apk/app-debug.apk`

## 7. 업데이트 로그


### 2026-03-18

- 하단 UI safe area 보정 적용으로 시스템 네비게이션 바에 가려지던 패널 위치 수정
- 내비게이션 정지 시 기존 경로/거리/턴 안내/경로선이 즉시 사라지도록 상태 초기화 개선
- GPS 속도 표시 안정화
	- 노드 변경/재탐색 시 속도가 0km/h로 깜빡이던 문제 수정
	- 정차 중 1~3km/h 수준의 GPS 노이즈를 0km/h로 더 강하게 억제하도록 필터 보강
- 재탐색 정책 개선
	- 최근접 노드 변경만으로는 재탐색하지 않도록 변경
	- 실제 경로 이탈이 충분히 클 때만 재탐색하도록 단순화
	- 재탐색 시 현재 진행 방향과 반대인 역방향 링크로 바로 붙지 않도록 시작 노드 선택 보정 추가
- 다음 안내 정확도 개선
	- 다음 회전 안내 거리와 안내 전환 기준을 노드 기준이 아니라 현재 GPS 위치의 경로 투영 기준으로 계산
	- 교차로 직전/직후 안내가 너무 빨리 또는 늦게 넘어가지 않도록 handoff 거리 보정 추가
- 지도 추적 UX 개선
	- 내비게이션 중 줌/중심을 사용자가 변경하면 5초 뒤 현재 위치 중심 + 주행 줌으로 자동 복귀
	- 내비게이션 중이 아닐 때도 GPS 갱신 시 현재 위치가 지도 중심이 되도록 변경
- 타일 지도 안정성 개선
	- 오프라인 타일의 지원 줌 범위를 인식하도록 보강
	- 인터넷 연결 시 온라인 타일을 백업 레이어로 사용해 줌 변경/안내 시작 시 빈 지도 현상 완화
- 경로선 디자인 개선
	- 이중 톤 경로선 적용
	- 경로 위에 진행 방향 화살표를 연속 배치해 T맵 스타일의 방향성 표현 추가
- 내비게이션 중 화면 꺼짐 방지(wakelock) 적용

### 2026-03-19

- `TB_TURNINFO` 기반 회전 제약 경로탐색 반영
	- `(PREV_LINK_ID, NEXT_LINK_ID)` 전이쌍을 기준으로 `TURN_TYPE` 적용
	- 금지 코드(`002`, `003`, `101`, `102`, `103`) 전이는 경로 탐색에서 제외
- 데이터 모델/스키마 확장
	- 앱 SQLite/백엔드 스키마에 `TB_TURNINFO` 테이블 및 인덱스 추가
	- 전이쌍 유니크 인덱스(`uq_turninfo_transition`) 및 링크 FK 연결
- 데이터 정합성 보강
	- 전이 중복/고아 링크/교차로 불일치 전이 자동 정리 로직 추가
	- `ON DELETE RESTRICT` 적용으로 링크 삭제 시 고아 전이 생성 방지
- 검증 리포트 추가
	- `backend/src/turninfo_report.sql` 신설
	- 요약 카운트 + 상세 이상행(고아/불일치/중복/코드오류) 조회 지원
- 테스트 추가
	- `test/nav_engine_turn_type_test.dart` 추가
	- 회전금지(`003`) 우회 및 허용(`011`) 통과 시나리오 검증
- 빌드 안정화
	- Android Java 컴파일 경고(source/target 8 obsolete) 억제 설정 추가
	- `flutter build apk --debug` 재검증 완료

### 2026-03-25

- 주행 UX/표시 안정화 개선
	- 내비 중 지도는 GPS 헤딩이 아니라 현재 따라가야 할 경로 세그먼트 방향을 기준으로 회전하도록 변경
	- 지도 회전에 스무딩 적용으로 정지/저속 시 진북 방향으로 튀는 현상 완화
	- 차량 마커와 지도 추적 중심에 UI 전용 위치 보간 적용으로 GPS 샘플 간 순간이동처럼 보이던 현상 완화
	- 내비 follow 줌을 완화하고 차량 마커가 화면 중앙보다 아래쪽에 보이도록 중심 오프셋 적용
- 경로 시작/도착 판단 개선
	- 내비 시작 시 현재 차량 heading과 맞는 시작 링크를 우선 선택하도록 시작 노드 보정 강화
	- 시작 방향이 첫 링크와 크게 어긋나면 2초간 출발 방향 확인 후 경로를 재확정하도록 변경
	- 도착지 30m 이내이면서 마지막 방향전환 전이면 `목적지 인근에 도착했습니다.`로 조기 종료 허용
- 음성 안내(TTS) 추가
	- `flutter_tts` 기반 한국어 음성 안내 추가
	- 내비 시작, 500m/150m/즉시 회전, 재탐색, 도착 음성 안내 지원
- `TB_TURNINFO` 데이터 재정비
	- PostgreSQL 원본 `public."TB_TURNINFO"`는 `st_link`, `ed_link`, `turn_type`, `remark` 구조를 사용함
	- 앱 라우팅에서는 원본 `st_link/ed_link`를 `TB_AY_MOCT_LINK.LINK_ID`를 거쳐 앱의 `links.id`로 재매핑해서 사용
	- 백엔드 API 기준 매핑 가능한 turninfo 전이는 `505건`, SQLite 번들 export 후 최종 유효 전이는 `499건`
	- 누락 전이는 링크 미존재/매핑 실패/중복 제거 등 데이터 부재 또는 정합성 문제일 수 있으므로 현재 로직은 유지하고 데이터 보강을 우선 권장
	- `flutter build apk --debug` 재검증 완료

### 2026-03-26

- 내비게이션 시작 줌 레벨 조정
	- 안내 시작 시 기본 줌 레벨을 `15.0 → 16.0`으로 변경 (`_navigationFollowZoomDefault`)
- 차량 마커 크기 축소
	- 마커 및 화살표 이미지 크기를 `64 → 52`로 조정 (기존 대비 약 0.8배)
- 마커 방향 개선
	- 안내 중 차량 마커가 GPS heading 대신 경로 진행 방향(route bearing)을 바라보도록 변경
	- 경로 투영(`_routeBearingForLocation`) 기반으로 마커 회전 각도 결정
	- GPS heading 미확보 시 차량 heading으로 fallback
- 내비게이션 마커/경로 화면 배치 개선
	- 마커와 경로는 항상 화면 가로 중심선에 고정
	- 하단 남은거리 패널(`NavigationBottomPanel`) 실측 높이를 기반으로 마커 Y 위치를 패널 바로 위로 동적 계산
	- 패널 높이 측정에 `GlobalKey` + `postFrameCallback` 활용, 고정값 오프셋 제거

## 8. 화면 구성 요약

- 지도 레이어: 타일/경로선/마커
- 상단: 목적지 검색 패널
- 우측 상단: 다음 회전 안내 카드
- 좌측 하단: 실시간 속도 카드
- 하단: 현재위치/내비 시작·정지 + 상태 배지

## 9. 주의/운영 팁

- 실제 주행 테스트 시 위치 권한/정확도 설정 확인 필요
- 실내 환경에서는 GPS 수신 품질이 낮아 재탐색이 잦아질 수 있음
- 재탐색 민감도는 상수값(이탈 거리/연속 횟수)으로 조정 가능
- `TB_TURNINFO`의 실제 경로 제약은 `(PREV_LINK_ID, NEXT_LINK_ID)` 전이행이 있어야 적용됨
- 코드 사전행(`PREV_LINK_ID`, `NEXT_LINK_ID`가 `NULL`)만 있으면 회전 제약은 적용되지 않음
- PostgreSQL 원본 `TB_TURNINFO`는 앱 스키마와 컬럼명이 다를 수 있으며, 현재는 `st_link/ed_link -> LINK_ID -> links.id` 재매핑을 통해 사용함
- 잘못된 좌/우회전 안내가 남아 있으면 로직 문제보다 `TB_TURNINFO` 전이 부재 또는 링크 매핑 누락일 가능성을 먼저 점검하는 것이 맞음
