# my_nav_app

로컬 DB(오프라인)와 백엔드(DB/API) 모드를 모두 지원하는 Flutter 경로 안내 앱입니다.

## 1. 기능 명세

### 1.1 지도/경로 표시

- 현재 위치, 목적지, 계산된 경로(polyline) 표시
- 차량 아이콘 heading(방향각) 기반 회전 표시
- 경로 도로 시퀀스(요약)와 총 거리 표시

### 1.2 검색/목적지 선택

- 지명 검색(Kakao Local Search)
- 노드 ID 검색(SQLite 또는 PostgreSQL 제안)
- 좌표 직접 입력 검색(`lat,lng`)
- 지도 길게 누르기(long press)로 목적지 설정

### 1.3 내비게이션

- GPS 기반 실시간 주행(속도/방향/위치 추적)
- 다음 회전 안내(좌회전/우회전/유턴)
- 안내 중 속도(km/h) 카드 표시
- 목적지 근접(20m 이내) 시 자동 종료

### 1.4 자동 재탐색

- 노드 기반 재탐색: 최근접 노드가 바뀌면 재탐색 후보
- 거리 기반 재탐색: 현재 위치가 경로에서 일정 거리 이상 이탈 시 재탐색 후보
- 재탐색 쿨다운: 짧은 시간 내 과도한 재탐색 방지

현재 기본값(코드 상수):

- 경로 이탈 임계 거리: `20m`
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
- 로컬 `nodes`, `links` 테이블 사용
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

# 카카오 지명 검색 키 설정
flutter run --dart-define=KAKAO_REST_API_KEY=YOUR_REST_API_KEY
```

### 3.2 지원 설정 키

- `ENABLE_BACKEND` : 백엔드 모드 사용 여부 (`true/false`)
- `API_BASE_URL` : 백엔드 API 기본 URL
- `OFFLINE_MAP_TILES` : 오프라인 타일 우선 여부 (`true/false`)
- `KAKAO_REST_API_KEY` : 지명 검색 API 키

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

## 6. 빌드

### 6.1 Android APK

```bash
flutter build apk
```

릴리즈 APK 산출물:

`build/app/outputs/flutter-apk/app-release.apk`

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

## 8. 화면 구성 요약

- 지도 레이어: 타일/경로선/마커
- 상단: 목적지 검색 패널
- 우측 상단: 다음 회전 안내 카드
- 좌측 하단: 실시간 속도 카드
- 하단: 현재위치/경로계산/내비 시작·정지 + 상태 배지

## 9. 주의/운영 팁

- 실제 주행 테스트 시 위치 권한/정확도 설정 확인 필요
- 실내 환경에서는 GPS 수신 품질이 낮아 재탐색이 잦아질 수 있음
- 재탐색 민감도는 상수값(이탈 거리/연속 횟수)으로 조정 가능
