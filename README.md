# SleepMate (iPhone) — 1단계: Apple Watch 수면 데이터 불러오기

> **무료 Apple ID로 설치했다면** HealthKit 직접 연결이 막히므로 **단축어로 가져오기**를 씁니다 → [docs/shortcut-guide.md](docs/shortcut-guide.md)

맥 없이 개발합니다. Linux에서 코드를 작성하고 GitHub에 푸시하면 GitHub Actions의 macOS runner가 **서명 없는 `.ipa`** 를 빌드합니다. 그 파일을 Windows PC에서 **Sideloadly**(무료 Apple ID 사용)로 아이폰에 설치합니다.

## 현재 기능
- HealthKit 수면 읽기 권한 요청
- 최근 14일 수면 조회 → 밤 단위로 묶기 (18:00 이후 잠든 수면은 다음 날로 묶음)
- 지난밤 총 수면, 취침→기상 시각, 단계별(깊은/코어/REM/깨어 있음) 시간
- 날짜별 상세: 데이터 소스, 원시 구간 목록
- 앱 내 로그 화면 (왼쪽 위 아이콘). 디버거가 없으므로 문제 추적에 사용

아이폰과 워치가 같은 밤을 동시에 기록하면 시간이 이중으로 합산됩니다. 그래서 단계 데이터를 남긴 소스(Apple Watch)를 우선 사용하고, 겹치는 구간은 병합해서 계산합니다.

## 구조
```
project.yml                     XcodeGen 설정 (Info.plist·entitlements도 여기서 생성)
SleepMate/Sources/
  SleepMateApp.swift            앱 진입점
  SleepStore.swift              HealthKit 권한·조회·밤 단위 묶기
  SleepModels.swift             수면 단계, 구간, 하룻밤 집계 모델
  ContentView.swift             UI (요약 카드, 목록, 상세, 로그)
  AppLog.swift                  앱 내 로그
.github/workflows/build-ipa.yml macOS runner 빌드 → SleepMate.ipa 업로드
```

## 빌드 (GitHub Actions)
1. 이 폴더를 GitHub 저장소로 푸시합니다 (`main` 브랜치).
   - macOS runner는 private 저장소에서 무료 사용량을 빨리 소모합니다. public 저장소면 무료입니다.
2. 저장소의 **Actions** 탭 → `Build unsigned IPA` 실행을 확인합니다 (수동 실행: Run workflow).
3. 실행 페이지 하단 **Artifacts**에서 `SleepMate-ipa-N`을 내려받아 압축을 풀면 `SleepMate.ipa`가 나옵니다.
4. 실패하면 `xcodebuild-log` 아티팩트에서 오류를 확인합니다.

## 아이폰 설치 (Windows + Sideloadly, 무료 Apple ID)
1. **iTunes**(Apple 웹사이트 설치판 권장)와 **Sideloadly**를 설치합니다.
2. 아이폰을 USB로 연결하고 "이 컴퓨터 신뢰"를 누릅니다.
3. Sideloadly에 `SleepMate.ipa`를 끌어다 놓고 Apple ID를 입력한 뒤 Start를 누릅니다.
4. 아이폰 설정
   - 설정 → 개인정보 보호 및 보안 → **개발자 모드** 켜기 (재시동 필요)
   - 설정 → 일반 → VPN 및 기기 관리 → 내 Apple ID → **신뢰**
5. 앱 실행 → "건강 데이터 연결하기" → **수면** 읽기 허용

무료 계정 제약: 설치한 앱은 **7일 후 만료**되므로 다시 설치해야 합니다.

## 문제 해결
| 증상 | 확인할 것 |
|---|---|
| 데이터가 0개 | 건강 앱 → 수면에 기록이 있는지, 설정 → 건강 → 데이터 접근 및 기기 → SleepMate → 수면이 켜져 있는지 |
| 권한 요청 시 바로 오류 | HealthKit entitlement가 빠진 것. 로그 화면을 확인하고 Sideloadly 고급 옵션에서 entitlements 유지 여부 확인 |
| 단계 데이터가 없음 | Apple Watch를 착용하고 수면 집중 모드/수면 추적을 켰는지 |
| 설치 직후 앱이 안 열림 | 개발자 모드와 Apple ID 신뢰 설정 확인 |

iOS는 개인정보 보호 때문에 **읽기 권한을 거부했는지 앱에 알려주지 않습니다.** 거부한 경우에도 오류 없이 "데이터 0개"로 보입니다.

## 다음 단계
- 수면 점수 산식 (수면 시간·규칙성·깬 시간·개인 평균 대비)
- 심박·걸음 수 읽기
- 워치 앱 (유료 계정 또는 학교 계정으로 TestFlight 배포 시)
- Claude API 연동 (수면 요약 생성, Console API 키 + 프록시 서버)
