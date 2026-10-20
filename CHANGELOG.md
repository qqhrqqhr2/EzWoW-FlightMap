# Changelog - EzWoW - Flight Map

## v2.0.0

### English

- Fixed map and window dragging offsets at different UI scales.
- Added faction-coloured World Map flight-master markers and saved faction filters.
- Improved World Map button alignment and removed obsolete flight nodes.
- Improved destination-label layout, route calculations and language switching.

### 한국어

- UI 배율에 따라 지도·창을 끌 때 위치가 어긋나는 문제를 수정했습니다.
- 진영별 색상의 비행 조련사 지도 표식과 진영 필터 저장을 추가했습니다.
- 세계지도 버튼 정렬을 개선하고 사용하지 않는 옛 비행 노드를 제외했습니다.
- 목적지 이름표 배치, 비행 경로 계산과 언어 전환을 개선했습니다.

## v0.6.2
- 드래그 시 마우스 포인터와 아이콘/프레임 좌표가 어긋나거나 벌어지는 스케일 오차(`EffectiveScale`) 및 초기 점프 현상 수정
- **모듈 구조 재설계 (`Core/`, `Data/`, `Modules/`, `UI/`) 및 성능 개선**:
  - `Core/Init.lua`, `Core/Locales.lua`, `Core/UIKit.lua`, `Core/WorldMapDock.lua`
  - `Data/RouteDistances.lua`, `Modules/FlightRouteEngine.lua`
  - `UI/FlightMapWindow.lua`, `UI/FlightBar.lua`, `UI/OptionsWindow.lua`, `UI/WorldMapPins.lua`
  - 이름표 충돌 회피 그리드 및 다익스트라 경로 탐색 캐시 최적화
- **세계지도 진영별 비행 조련사 표시 및 도킹 연동**:
  - 세계지도·대륙·지역 지도에 얼라이언스(파랑)·호드(빨강)·중립(금색) 비행 조련사 14px 마커 표시 및 구형 `zzOLD` 노드 자동 제외
  - `EzWoWWorldMapDock`(순번 2) 좌하단 자동 정렬 및 진영별 필터 저장 지원
- **8개 언어(`Auto` 포함) 실시간 전환 및 `/ezfl`, `/ezwowflightmap`, `/비행지도` 명령어 통일**

## v0.6.1
- 소지금 부족 요금 빨간색 표시 및 툴팁 안내 추가
- 비행 조련사별 마지막 이용 목적지 `최근` 상단 고정 추가
- 남은 비행 시간 막대에 총 경유지 수 및 현재 경유 구간 표시 추가
- 지도 열릴 때 검색창 자동 포커스 옵션 추가

## v0.6.0
- 지도 우측 목적지 검색·정렬(이름/시간/요금)·즐겨찾기(`★`) 목록 및 현재 위치 파동 효과 추가
- 남은 비행 시간 막대에 현지 도착 예정 시각 표시 추가
