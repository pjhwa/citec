# Claude Code 핸드오프: host-minimize-safe v5.x 서버 릴레이 테스트

- **작성자**: Jerry (CI-TEC, Samsung SDS)
- **작성일**: 2026-04-22
- **문서 버전**: v2 (서버 릴레이 모델)
- **대상 세션**: Claude Code (Opus 4.7+) with shell/file tools
- **트리거 명령**: `삭제 테스트 시작`

---

## 0. 이 문서를 읽는 방법

- 테스트는 **여러 테스트 서버를 순차적으로** 돌면서 진행된다 (용도별 서버 1대씩).
- 각 서버에서 너는 **"삭제 테스트 시작"** 트리거 한 번에 응답하여 전체 워크플로우를 수행한다.
- 이전 서버의 산출물이 **현재 서버의 현재 작업 디렉토리에 이미 복사되어 있다**고 가정한다.
- **§15 워크플로우가 실전 지침의 핵심**이다. 앞 섹션들은 맥락 제공용.

---

## 1. 역할과 행동 원칙

너는 **Samsung SDS CI-TEC의 인프라 보안 엔지니어 보조**이자 **테스트 엔지니어 + 스크립트 개발자**를 겸한다. 최종 목적은 **프로덕션 운영 서버에서 안전하게 쓸 수 있는 `host-minimize-safe` 완성본**이다.

**행동 원칙**:

- **파괴적 작업은 반드시 사전 승인 요청**: `apt purge`, `rm -rf`, `dpkg --remove`, reboot 계열은 "명령어 + 예상 영향 + 되돌리기 방법" 3줄로 확인.
- **Dry-run을 먼저, 항상**: 모든 제거 작업은 `--execute` 없이 결과 검토 후 진행.
- **체크리스트 기반**: 각 단계 완료 시 ✅/❌/⏭ 기록.
- **모호하면 멈추고 물어라**: 지침과 현실 충돌 시 진행 중단 후 보고.
- **문제 발견 = 스크립트 개선**: 단순 기록이 아니라 **스크립트를 직접 수정**하고 재테스트 (§12 이터레이션 루프).
- **산출물은 다음 서버로 이동할 것을 전제**: 경로와 포맷 일관성 유지 (§16 계주 규칙).
- **한국어 Markdown, 간결체, bullet 선호**.

---

## 2. 프로젝트 배경

### 2.1 조직/환경

- **조직**: Samsung SDS CI-TEC (Cloud & Infrastructure Technical Expert Center)
- **대상 환경**: SCPv2 Sovereign (Samsung Cloud Platform v2, 주권형 클라우드)
- **기반 OS**: Ubuntu 24.04 Noble
- **CSAP 감사**: 2026년 5월 말 (KISA 형식 심사)
- **관련 통제**:
  - **2.4** 평문 프로토콜 금지 (telnet, ftp, rsh)
  - **8.5** 민감 정보 외부 유출 방지 (apport, whoopsie)
  - **9.3** 불필요 서비스/패키지 제거 ← 본 테스트 직접 대상

### 2.2 왜 호스트 최소화가 필요한가

SCPv2 노드는 Ubuntu Server 기본 설치 위에 OpenStack/Ceph/K8s가 얹혀 있다. 레거시 디버깅/멀티미디어/GUI/평문 프로토콜 패키지들이 상주 → 공격면 증가, CSAP 감사 지적 위험, CVE 부담. 반면 **무턱대고 제거 시** `podman`(cephadm), `containerd`(K8s), `strace`(장애 진단) 등 필수 기능 파괴 → 노드 장애.

### 2.3 스크립트 이력

- **v4.2** (2026-04-21): 초안. 치명적 버그 4건 + 안전성 부족 12건 발견.
- **v5.0** (2026-04-21): 버그 수정 + 프로파일 세분화 + `--risk-report` + `--plan-out` + Extended baseline + 사후 검증. **테스트 시작 버전.**
- **v5.0.1** (2026-04-23): test-nn 테스트에서 발견된 버그 5건 수정. rollback 복원 실패(P1), k8s-worker 프로파일 체크 과도(P2), cascade count 중복 합산(P2), NIC Link Down 오탐(P3), rc 상태 패키지 오인식(P2).
- **v5.x** (테스트 진행 중): 이 테스트에서 발견되는 이슈에 따라 증분 개선.

### 2.4 프로덕션 대상 노드 구성

| 노드명 | 역할 추정 | 패키지 수 | v5 profile | 테스트 서버 이름 예시 |
|--------|----------|:---:|-------------|----------------------|
| `k-cepho01-sto301-krw1b` | Ceph storage (cephadm) | 781 | `cephadm` | `test-cepho` |
| `k-log01-com301-krw1b` | K8s worker + Ceph client | 734 | `k8s-worker` | `test-log` |
| `k-nn01-con301-krw1b` | K8s worker | 685 | `k8s-worker` | `test-nn` |
| `k-scn01-con301-krw1b` | K8s worker | 686 | `k8s-worker` | `test-scn` |
| `k-wproxy01-con301-krw1b` | K8s worker | 685 | `k8s-worker` | `test-wproxy` |
| `k-vfwc01-nr303-krw1b` | Compute (GUI 포함) | 1,661 | `compute` | `test-vfwc` |

> **실제 프로덕션 노드는 절대 건드리지 않는다.**

---

## 3. 테스트 아키텍처: 서버 릴레이 모델

### 3.1 전체 구조

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│ 테스트 서버 1 │ ──→ │ 테스트 서버 2 │ ──→ │ 테스트 서버 N │
│  (nn용)     │     │  (scn용)    │     │  (vfwc용)   │
└─────┬───────┘     └─────┬───────┘     └─────┬───────┘
      │ 산출물 번들       │ 산출물 번들       │ 최종 번들
      ▼                   ▼                   ▼
  [계주 전달]          [계주 전달]        PRODUCTION-READY v5.x
```

- 각 서버는 **하나의 노드 역할 전담**. 해당 노드의 `apt_list.txt`와 동일한 패키지 구성.
- 완료 시 산출물 번들을 **다음 서버로 복사**.
- 다음 서버는 **이전 서버 번들을 참고**하여 개선된 스크립트로 이어서 테스트.
- 모든 서버에서 문제 없이 통과할 때까지 반복.

### 3.2 테스트 서버 구성 방식 (사용자 담당)

사용자가 각 테스트 서버 준비 시:

1. Ubuntu 24.04 Noble 기본 설치.
2. 해당 노드의 `*_apt_list.txt` 파일을 서버로 복사.
3. 설치된 패키지와 목록 파일을 **동기화**: 목록에 있는데 없으면 설치, 목록에 없는데 있으면 제거.
4. 이전 서버의 산출물 번들을 **현재 작업 디렉토리**에 복사.

**결과**: 각 서버는 해당 프로덕션 노드와 거의 동일한 패키지 구성 상태.

### 3.3 테스트 순서 (권장)

복잡도가 낮고 파괴 위험이 낮은 순서:

| 순번 | 서버 | 이유 |
|:---:|------|------|
| 1 | `test-nn` (k8s-worker) | 가장 단순, 패키지 수 적음, 전체 흐름 최초 검증 |
| 2 | `test-scn` (k8s-worker) | nn과 유사, 재현성 확인 |
| 3 | `test-wproxy` (k8s-worker) | 동일 프로파일 안정성 재확인 |
| 4 | `test-log` (k8s-worker + Ceph client) | Ceph 관련 보호 확인 |
| 5 | `test-cepho` (cephadm) | **podman 보호 결정적 검증** ← 핵심 |
| 6 | `test-vfwc` (compute, GUI) | 가장 대규모, 마지막에 |

순서 변경은 Jerry와 협의 후.

### 3.4 테스트 환경 요구사항

| 항목 | 조건 |
|------|------|
| OS | Ubuntu 24.04 Noble |
| 리소스 | 최소 4 vCPU / 8 GB / 50 GB (compute는 8/16/100 권장) |
| 스토리지 | 제약 없음 (LVM 불요) |
| 네트워크 | APT mirror 접근 가능 |
| 권한 | sudo |
| 격리 | 프로덕션과 완전 분리 |

### 3.5 LVM 스냅샷 불가 환경의 롤백

3단계 방어선:

1. 스크립트 내장 `rollback-v5-<TS>.sh` (`dpkg --set-selections`)
2. 작업 시작 시 생성한 외부 백업 (`$BACKUP_DIR`)
3. 테스트 서버 재프로비저닝

---

## 4. 최종 목표

### 4.1 Must-have

1. v5.0 실전 안전성 검증: 모든 용도 서버에서 dry-run/risk-report/execute 완주
2. **발견된 모든 문제를 스크립트에 반영**: 단순 기록 아닌 직접 패치
3. **프로덕션 ready 상태**: 6개 용도 서버 모두 통과한 **v5.x 최종본** 산출
4. v4.2 버그 4건 비재현 증명
5. 운영 투입 Runbook 작성

### 4.2 Nice-to-have

- 노드별 plan 파일로 프로덕션 연쇄 제거 규모 정량화
- CSAP 감사 증빙 번들
- 대형 노드 성능 측정

### 4.3 Non-goals

- 클러스터 기능 테스트 (패키지 레벨만)
- 성능 벤치마크
- RHEL/Rocky 포팅
- v5→v6 대규모 리팩토링 (패치만)

### 4.4 성공 기준 (Acceptance Criteria)

- [ ] 6개 용도 서버 모두 Phase A~F 통과
- [ ] 마지막 2개 서버에서 **새 버그 0건** (수렴)
- [ ] 연속 3회 dry-run 결과 동일 (determinism)
- [ ] `dpkg --audit` / `apt-get check` 사후 에러 0건
- [ ] Rollback 2단계 검증 통과
- [ ] 모든 버그는 fix 또는 KNOWN-ISSUES.md 문서화
- [ ] CHANGELOG.md가 v5.0→최종 모든 변경 기록
- [ ] PRODUCTION-RUNBOOK.md 작성 완료

---

## 5. 입력 자료

### 5.1 첫 번째 테스트 서버

| 파일 | 용도 |
|------|------|
| `host-minimize-safe-v5.0.sh` | 테스트 대상 스크립트 (원본) |
| `<해당 노드>_apt_list.txt` | 서버 패키지 구성 기준 목록 |
| `v5-review-report.md` | (선택) v4.2 대비 개선 리포트 |

### 5.2 두 번째 이후 (계주 번들)

이전 서버에서 생성된 번들이 **현재 작업 디렉토리에 복사되어 있음**:

- `host-minimize-safe-v5.x.sh` (최신 개선본)
- `v5.0-original-snapshot.sh` (원본, 변경 금지)
- `CHANGELOG.md`
- `summary.md` (누적)
- `KNOWN-ISSUES.md`
- `test-matrix.csv` (누적)
- 이전 서버들의 `plan-*.yaml`, `risk-*.log`, `execute-*.log`, `rollback-verification-*.txt`
- `<현재 노드>_apt_list.txt` (현재 서버용)

Claude Code는 시작 시 **번들 존재 여부를 자동 확인**하고 없으면 "첫 번째 서버" 모드.

---

## 6. 산출물 번들 구성

### 6.1 프로덕션 투입 직접 자료 (필수)

1. **`host-minimize-safe-v5.x.sh`** — 현재까지 개선된 스크립트
2. **`CHANGELOG.md`** — v5.0부터 모든 변경 기록
3. **`KNOWN-ISSUES.md`** — 미수정 limitation + 우회법
4. **`PRODUCTION-RUNBOOK.md`** — 운영 투입 절차서 (마지막 서버에서 작성)
5. `v5.0-original-snapshot.sh` — 원본 (수정 금지)

### 6.2 테스트 근거 자료 (필수)

6. **`summary.md`** — 모든 서버 모든 Phase 결과 누적
7. **`test-matrix.csv`** — 서버 × Phase × 결과 매트릭스
8. **`test-report-<server>.md`** — 서버별 테스트 진행/결과 상세 보고서 (**Phase G에서 반드시 생성**)
9. `plan-<server>-<profile>.yaml` — 서버별 plan
10. `risk-<server>-<profile>.log` — 서버별 risk report
11. `baseline-<server>-<TS>.tar.gz` — baseline snapshot
12. `execute-<server>-<iter>.log` — execute 로그
13. `rollback-verification-<server>.txt` — 롤백 검증 diff
14. `edge-case-results-<server>.md` — edge case 결과

### 6.3 번들 디렉토리 구조 (권장)

```
~/minimize-test-bundle/
├── scripts/
│   ├── host-minimize-safe-v5.x.sh        # 현재 버전
│   └── v5.0-original-snapshot.sh         # 원본 (수정 금지)
├── docs/
│   ├── CHANGELOG.md
│   ├── KNOWN-ISSUES.md
│   ├── summary.md
│   ├── test-report-<server>.md           # 서버별 상세 보고서 (필수)
│   ├── BUNDLE-CHECKSUMS.txt              # §16.4 참조
│   └── PRODUCTION-RUNBOOK.md             # 마지막 서버에서만
├── test-results/
│   ├── test-matrix.csv
│   ├── <server1>/
│   │   ├── plan-*.yaml
│   │   ├── risk-*.log
│   │   ├── execute-*.log
│   │   ├── baseline-*.tar.gz
│   │   └── rollback-verification-*.txt
│   ├── <server2>/...
│   └── <current-server>/
└── apt-lists/
    └── <current-node>_apt_list.txt
```

---

## 7. 중단 조건

다음 발생 시 **즉시 테스트 중단 후 Jerry 보고**:

1. `podman`이 cephadm 프로파일 제거 대상에 포함 → v5 설계 결함
2. `containerd` 또는 `kubelet`이 k8s 프로파일 제거 대상에 포함
3. `openssh-server`가 어떤 프로파일에서든 제거 대상에 포함
4. 스크립트 crash/세그폴트
5. 테스트 서버 SSH 접근 불가
6. 연쇄 제거 수가 plan 예상치의 **2배 이상** 초과
7. `dpkg --audit` 또는 `apt-get check` 에러
8. 테스트 서버가 프로덕션 네트워크에 있다는 증거
9. 이전 서버 번들 손상/불완전 (§16.3 검증 실패)

---

## 8. 통신/보고 규칙

### 8.1 일상 보고

- `✅ Phase A: 번들 검증 통과 — 7개 필수 파일 모두 확인`
- `⚠ [확인 필요] 이전 서버에서 BUG-03 미해결로 넘어옴 — 재현 시 fix 진행`
- 명령어는 블록 코드, 실행 전 예상 결과 1줄.

### 8.2 BUG 표준 포맷

```
🐛 BUG-<번호> (P<0~3>) @ <server>
- 발견 Phase: <Phase C.2>
- 재현 명령: <command>
- 증상: <observed>
- 기대 동작: <expected>
- 로그 스니펫: <3~5줄>
- 원인 추정: <hypothesis>
- 영향 범위: <profile/feature>
- 심각도 근거: <P0~P3 선택 이유>
```

### 8.3 PATCH 제안 포맷

```
🔧 PATCH for BUG-<N>
- 대상 버전: v5.0.N → v5.0.(N+1)
- 수정 위치: <function/line>
- 변경 요약: <1줄>
- Diff: <unified diff>
- 회귀 테스트 범위: <§12.5 기준>
- CHANGELOG 엔트리 초안: <1줄>
- 승인 요청: 진행할까요?
```

### 8.4 Phase/서버 종료 보고

```
📊 Phase <X> @ <server> 종료
- 결과: ✅/❌/⏭
- 소요 시간: <분>
- 새 버그: <번호 나열>
- 수정된 버그: <번호 나열>
- 번들 상태: <파일 개수 / 총 크기>
- 다음 진행 준비: Yes/No
```

---

## 9. 참고: 사용자 맥락

- Jerry는 Samsung SDS CI-TEC에서 26명 인프라/보안 엔지니어링 팀 리드.
- 본 스크립트는 CSAP 9.3 통제 기술적 증빙.
- 과거 관련 작업: CSAP 9.1.4-③(MAC/AppArmor), OpenStack Helm on K8s, IBM Power 장애 분석.
- 작업 스타일: 기술 깊이 선호, 불확실성 솔직 표기, 과장 금지, bullet 선호.

---

## 10. 전체 테스트 완료 정의 (Definition of Done)

- [ ] 6개 용도 서버 모두에서 Phase A~F 통과
- [ ] 마지막 2개 서버에서 새 버그 0건 (수렴)
- [ ] §4.4 성공 기준 8개 항목 모두 충족
- [ ] 번들이 프로덕션 투입에 필요한 13종 산출물 완비
- [ ] PRODUCTION-RUNBOOK.md 작성, Jerry 리뷰 대기

> 개별 서버 DoD는 §15.G.5 기준.

---

## 11. 시작 신호

사용자가 **`삭제 테스트 시작`** 을 입력하면 §15 워크플로우를 수행한다. 다른 표현(예: "테스트 해봐", "진행해")에도 동일하게 동작하되, 트리거 명령을 명시적으로 확인.

사용자가 이 문서만 제시하고 다른 지시가 없으면 네가 먼저:

```
✅ v2 핸드오프 문서 확인 완료.
🎯 목적: 서버 릴레이 방식으로 v5.x 스크립트 검증 및 개선

`삭제 테스트 시작` 을 입력하시면 §15 워크플로우를 시작합니다.
작업 디렉토리를 스캔하여 첫 번째 서버인지 계주 서버인지 자동 판별합니다.
```

---

## 12. 이터레이션 루프 정책

### 12.1 문제 발견 시 4단계

1. **관찰/진단** (5~10분): 재현 조건, 로그 추출, `🐛 BUG-N` 임시 기록
2. **분류(Severity)**: 아래 표
3. **패치**: Jerry 승인 → CHANGELOG 기록 → 버전 증가 → 코드 수정 → `bash -n`/`shellcheck` → 재테스트
4. **검증/회귀**: 수정 확인 + 이전 통과 Phase 재실행 + 상태 `✅ Fixed in v5.0.N`

### 12.2 Severity 분류

| 레벨 | 정의 | 대응 |
|------|------|------|
| P0 | 프로덕션 서비스 장애 유발 | 즉시 중단, 패치 필수 |
| P1 | 스크립트 주요 기능 불가 | 현 Phase 종료 후 패치 |
| P2 | 기능 동작하나 부정확 | Phase 묶음 끝에 일괄 패치 |
| P3 | UX/표현만 | KNOWN-ISSUES.md 또는 시간 여유 시 |

### 12.3 버전 규칙

- v5.0 → v5.0.1 → ... → v5.0.N (Hotfix)
- 전체 완료 시 → v5.1 (프로덕션 투입본)
- 파일명과 `SCRIPT_VERSION` 변수 일치 유지

### 12.4 최소 침습 원칙

- 기존 함수 시그니처 변경 금지
- 전역 상수 추가는 섹션 끝
- 하나의 패치는 하나의 문제만
- 대규모 리팩토링 판단 시 → **중단하고 보고**

### 12.5 회귀 테스트 매트릭스

| 수정 범위 | 재실행 범위 |
|-----------|-------------|
| whitelist 변경 | 해당 프로파일 dry-run + risk-report |
| 의존성 분석 함수 | 모든 프로파일 dry-run |
| baseline/rollback | 현재 서버 Phase D + E |
| 사전 체크 로직 | Phase A 전체 + 해당 프로파일 Phase D |
| 로깅/출력 포맷 | Phase F.9 (ANSI 체크) |
| 인자 파싱 | `--help` + 모든 옵션 smoke test |

### 12.6 이터레이션 종료 조건

- 연속 2개 서버에서 새 버그 0건 → 수렴 판정
- Jerry가 "충분하다" 판정
- 테스트 시간/리소스 한계 → 잔여 이슈는 KNOWN-ISSUES.md

---

## 13. 프로덕션 투입 Runbook 템플릿 (참조)

마지막 서버 완료 후 `PRODUCTION-RUNBOOK.md`를 아래 템플릿으로 작성:

```markdown
# host-minimize-safe v5.x 프로덕션 투입 Runbook

## A. 개요
- 대상 환경: SCPv2 Sovereign
- 대상 노드 수: <N대, 프로파일별 분포>
- 실행 스크립트: host-minimize-safe-v<ver>.sh
- 예상 영향: <테스트 측정 평균/최대 제거 패키지 수>
- CSAP 통제 매핑: 2.4.1, 8.5, 9.3

## B. 사전 조건
- [ ] CAB 승인 번호: ________
- [ ] SCPv2 VM 스냅샷 확인
- [ ] 프로파일별 dry-run plan 사전 검토
- [ ] 노드 Cordon(K8s)/Maintenance(Ceph) 설정
- [ ] 관제 통보

## C. 실행 순서 (Canary)
1. Canary 1대 (K8s worker, 비중요) → 24시간 관찰
2. 같은 프로파일 나머지 (배치 3~5대)
3. 프로파일 순서: k8s-worker → k8s-control → compute → cephadm → network

## D. 노드당 절차
1. SSH 세션 2개 확보
2. 외부 백업: ~/minimize-prod-backup/<hostname>-<TS>/
3. Cordon/Drain 확인
4. dry-run 재확인
5. Jerry 최종 승인
6. execute 실행
7. 사후 검증
8. Uncordon / 서비스 복귀

## E. 사후 검증
- [ ] sshd:22 listen
- [ ] 필수 서비스 active (프로파일별)
- [ ] K8s Ready / Ceph HEALTH_OK / Compute 정상
- [ ] `dpkg --audit` / `apt-get check` 에러 0건
- [ ] `systemctl list-units --failed` 비어있음

## F. 롤백
- 1차: 스크립트 내장 rollback
- 2차: 외부 백업 수동 복원
- 3차: 노드 재프로비저닝

## G. 위험 요소
- <테스트 발견 특이사항>
- <P0/P1 fix 요약>
- <KNOWN-ISSUES 주의 항목>

## H. 연락처
- 기술: Jerry (CI-TEC)
- 관제: <팀/핫라인>
- 승인: <CAB PM>
```

---

# § 15. 「삭제 테스트 시작」 워크플로우 (현재 서버 1회 사이클)

> **여기가 Claude Code가 매번 실제로 수행하는 절차**다. 사용자가 "삭제 테스트 시작"을 입력하면 Phase A → H를 순서대로 수행한다. 각 Phase 종료 시 §8.4 포맷으로 보고하고 다음 Phase 승인을 받는다.

## Phase A. 현재 상황 진단 (항상 첫 단계)

### A.1 작업 디렉토리 스캔

```bash
pwd
ls -la
find . -maxdepth 3 -type f \( \
    -name "host-minimize-safe-*.sh" -o \
    -name "CHANGELOG.md" -o \
    -name "summary.md" -o \
    -name "KNOWN-ISSUES.md" -o \
    -name "test-matrix.csv" -o \
    -name "*_apt_list.txt" -o \
    -name "*_apt.txt" \
\) | sort
```

판별 로직:
- **첫 번째 서버 모드**: `v5.0` 스크립트만 있고 `CHANGELOG.md`/`summary.md` 없음
- **계주 서버 모드**: 위 번들 파일이 있음 → 번들 검증 모드로 진행

### A.2 현재 서버 식별

```bash
hostname
cat /etc/os-release | head -3
ls *_apt_list.txt *_apt.txt 2>/dev/null
```

hostname 또는 파일명 패턴으로 **이번 테스트의 프로파일 추정**:
- `cepho*` → `cephadm`
- `log*`, `nn*`, `scn*`, `wproxy*` → `k8s-worker`
- `vfwc*` → `compute`

추정 실패 시 Jerry에게 질문.

### A.3 이전 서버 산출물 검토 (계주 서버만)

계주 서버인 경우 **반드시 순서대로**:

1. `CHANGELOG.md` 읽고 현재 스크립트 버전 확인
2. `summary.md` 마지막 서버 섹션 읽고 **발견/수정/미해결 버그** 상태 요약
3. `KNOWN-ISSUES.md` 읽고 현재 서버에 영향 줄 수 있는 이슈 파악
4. `test-matrix.csv` 마지막 줄 확인 — 어디까지 통과
5. `v5.0-original-snapshot.sh` 존재 + md5 무결성 확인

**읽은 결과를 3~5줄로 Jerry에게 요약 보고** — 다음 Phase 진행 전 컨텍스트 공유.

### A.4 번들 무결성 검증 (계주 서버만)

§16.3의 `bundle-verify.sh` 실행. 불일치 발견 시 **중단 후 보고**.

### A.5 테스트 서버 환경 확인

```bash
echo "=== 환경 확인 ==="
lsb_release -a 2>/dev/null
df -h / /var
sudo -n true 2>&1 && echo "sudo OK"
# apt-get -s update 는 update 서브커맨드에 -s 불가 — 아래로 대체
sudo apt-get check 2>&1 | tail -3
# rc(설정파일 잔류) 제외, 실제 설치(ii) 패키지만 카운트
dpkg -l | awk '/^ii/ {print $2}' | wc -l
sudo dpkg --audit 2>&1 | head -5
systemctl --version | head -1
```

문제 발견 시 중단 후 보고.

## Phase B. 패키지 구성 정합성 확인

### B.1 기준 파일 vs 현재 상태 비교

> **주의**: apt_list.txt 비교는 참고용. **실제 목적은 현재 시스템 설치 패키지 기준 CSAP 분석**이다.
> rc(설정파일 잔류) 상태 패키지는 실제 설치가 아니므로 반드시 ii 상태만 카운트.

```bash
APT_LIST=$(ls *_apt_list.txt *_apt.txt 2>/dev/null | head -1)
echo "기준: $APT_LIST"

grep -E '\[installed' "$APT_LIST" \
  | awk -F'/' '{print $1}' \
  | sort -u > /tmp/target-packages.txt

# rc 상태 제외 — 실제 설치(ii)된 패키지만
dpkg -l | awk '/^ii/ {print $2}' \
  | awk -F: '{print $1}' \
  | sort -u > /tmp/current-packages.txt

comm -23 /tmp/target-packages.txt /tmp/current-packages.txt > /tmp/to-install.txt
comm -13 /tmp/target-packages.txt /tmp/current-packages.txt > /tmp/to-remove.txt

echo "설치 필요: $(wc -l < /tmp/to-install.txt)개"
echo "제거 후보: $(wc -l < /tmp/to-remove.txt)개"
```

### B.2 정합성 판단

- **차이 10개 이하**: 정합 — Phase C 진행
- **차이 11~100개**: Jerry에게 diff 요약 보고 후 **선택 요청**:
  - (a) 현재 상태로 테스트 진행
  - (b) 차이 해소 후 진행
- **차이 100개 초과**: 서버 초기 세팅 문제 → 중단, Jerry가 서버 재구성

### B.3 차이 해소 (필요 시, Jerry 승인 후)

> **주의**: 이 단계는 **환경 정비**이지 본 테스트가 아니다. `host-minimize-safe` 스크립트를 사용하지 않는다.

```bash
# 설치 (승인 후)
sudo apt-get install -y $(cat /tmp/to-install.txt)

# 제거는 신중: whitelist 보호되는 필수 패키지가 to-remove에 있는지 먼저 확인
# 진짜 불필요한 것만 제거 — 이 부분은 Jerry와 목록 재확인 후 실행
```

## Phase C. Dry-run 및 Risk Report

### C.1 스크립트 준비

```bash
SCRIPT=$(ls host-minimize-safe-v5*.sh | grep -v original | sort -V | tail -1)
echo "사용할 스크립트: $SCRIPT"
chmod +x "$SCRIPT"
bash -n "$SCRIPT" && echo "syntax OK"
shellcheck -s bash -S warning "$SCRIPT" 2>&1 | head -20
"$SCRIPT" --help
```

### C.2 프로파일 자동 감지 테스트

```bash
SERVER=$(hostname)
mkdir -p ./test-results/$SERVER

sudo "$SCRIPT" --plan-out "./test-results/$SERVER/plan-auto.yaml" \
  2>&1 | tee "./test-results/$SERVER/auto-detect.log"

grep "Detected/Selected node type" "./test-results/$SERVER/auto-detect.log"
```

**감지 결과와 A.2 추정 일치 여부 확인**. 불일치 시 `🐛 BUG` 기록.

### C.3 명시 프로파일 Dry-run

```bash
PROFILE=<A.2에서 확정한 프로파일>

sudo "$SCRIPT" \
  --profile "$PROFILE" \
  --plan-out "./test-results/$SERVER/plan-$PROFILE.yaml" \
  2>&1 | tee "./test-results/$SERVER/dryrun-$PROFILE.log"
```

### C.4 Risk Report

```bash
sudo "$SCRIPT" --profile "$PROFILE" --risk-report \
  > "./test-results/$SERVER/risk-$PROFILE.log" 2>&1
```

### C.5 Dry-run 결과 검증

**공통 체크** (모든 서버):
- [ ] `openssh-server` 제거 대상에 **없음**
- [ ] `systemd*`, `udev`, `dbus*` 제거 대상에 없음
- [ ] `apt`, `dpkg` 제거 대상에 없음
- [ ] `telnet`, `ftp`, `snapd`, `apport`는 제거 대상에 **있음**
- [ ] baseline/rollback 디렉토리 생성 확인

**k8s-worker 서버**:
- [ ] `containerd*`, `runc`, `kubelet`, `kubeadm`, `kubectl` 모두 제거 대상에 **없음**
- [ ] `cni-plugins`, `conntrack`, `socat` 보호
- [ ] `test-log`의 경우 `ceph-common` 보호

**cephadm 서버**:
- [ ] **`podman` 제거 대상에 없음** ← **가장 중요**
- [ ] `containers-common`, `runc`, `crun`, `skopeo` 보호
- [ ] `ceph*`, `rados*`, `rbd*` 보호

**compute 서버**:
- [ ] `libvirt*`, `qemu*`, `openvswitch*` 보호
- [ ] `gnome-*`, `xserver-xorg*`, `gdm3` 제거 대상 포함
- [ ] 연쇄 제거 수 기록

**문제 발견 시** → §12.1 4단계 프로토콜 발동.

## Phase D. Execute (조건부)

### D.1 Execute 여부 결정

| 서버 타입 | Execute |
|-----------|:---:|
| k8s-worker 첫 서버 (`test-nn`) | **예** |
| k8s-worker 후속 (`test-scn/wproxy/log`) | **조건부** — 앞 서버 통과 + 변경 없음이면 dry-run만, 새 버그/패치 있으면 다시 execute |
| cephadm (`test-cepho`) | **예** (podman 보호 실전 증명) |
| compute (`test-vfwc`) | **아니오** (GUI 대량 제거, plan 분석만) |

Jerry 승인 후 진행.

### D.2 외부 백업 (D 진행 시 필수)

```bash
BACKUP_DIR="$HOME/minimize-test-backup/$SERVER/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

sudo dpkg --get-selections              > "$BACKUP_DIR/dpkg-selections.txt"
sudo dpkg -l                            > "$BACKUP_DIR/dpkg-l.txt"
sudo apt-mark showmanual                > "$BACKUP_DIR/apt-manual.txt"
sudo apt-mark showauto                  > "$BACKUP_DIR/apt-auto.txt"
sudo systemctl list-unit-files --state=enabled > "$BACKUP_DIR/services-enabled.txt"
sudo ss -tlnpu                          > "$BACKUP_DIR/ports.txt"
sudo tar --exclude='/etc/shadow*' --exclude='/etc/gshadow*' \
    -czf "$BACKUP_DIR/etc.tar.gz" /etc 2>/dev/null

echo "백업: $BACKUP_DIR"
```

### D.3 Execute 실행

```bash
sudo "$SCRIPT" \
  --profile "$PROFILE" \
  --execute --yes --skip-snapshot-check \
  2>&1 | tee "./test-results/$SERVER/execute-$PROFILE.log"
```

### D.4 사후 검증

```bash
# 필수 서비스
for svc in ssh sshd rsyslog chrony auditd apparmor; do
  systemctl is-active --quiet $svc 2>/dev/null \
    && echo "✅ $svc active" \
    || echo "⚠ $svc NOT active"
done

# 포트
sudo ss -tlnp | grep ':22 ' && echo "✅ sshd:22" || echo "❌ sshd down"

# 패키지 DB
sudo dpkg --audit
sudo apt-get check
systemctl list-units --failed

# 서버별 추가 체크
# k8s-worker: 없음 (kubelet active 필요 없이 설치만 된 상태이므로)
# cephadm: (가능 시) ceph -s
# compute: (가능 시) virsh list
```

> **Reboot 금지** — LVM 스냅샷 없어 부팅 실패 시 복구 어려움.

## Phase E. Rollback 검증

### E.1 스크립트 내장 Rollback

```bash
ROLLBACK=$(sudo ls -t /var/lib/host-minimize/rollback/rollback-v5-*.sh | head -1)
echo "$ROLLBACK"
sudo "$ROLLBACK"
# "yes" 입력
```

### E.2 외부 백업 기반 Diff 검증

```bash
diff "$BACKUP_DIR/dpkg-selections.txt" \
     <(sudo dpkg --get-selections) \
  > "./test-results/$SERVER/rollback-verification-dpkg.txt"

diff "$BACKUP_DIR/apt-manual.txt" \
     <(sudo apt-mark showmanual) \
  > "./test-results/$SERVER/rollback-verification-manual.txt"

wc -l ./test-results/$SERVER/rollback-verification-*.txt
```

- [ ] diff 0줄 → 완전 복원 ✅
- [ ] 차이 있음 → `🐛 BUG` 기록 후 분석

## Phase F. Edge Case 회귀 테스트

서버별로 관련 항목만:

| # | 검증 목적 | 테스트 |
|---|-----------|--------|
| F.1 | v4.2 Bug #1 회귀 (`set -e` + `(())`) | dry-run 완주 (이미 Phase C) |
| F.2 | v4.2 Bug #2 회귀 (grep 매칭) | `--full-tree` spot check |
| F.3 | v4.2 Bug #3 회귀 (로케일) | `LC_ALL=ko_KR.UTF-8 sudo ./스크립트 ...` 결과 비교 |
| F.4 | v4.2 Bug #4 회귀 (podman) | cephadm 서버에서만 수행 |
| F.5 | Lock 파일 | 2개 세션 동시 실행 → CRIT |
| F.6 | SSH 안정성 체크 | (파괴적, optional) |
| F.7 | Invalid profile | `--profile foo` → exit 2 |
| F.8 | Exclude 병합 | config + CLI 동시 |
| F.9 | Plain log ANSI 없음 | `grep -P '\x1b\[' plain.log` |
| F.10 | 사후검증 sshd down 탐지 | (파괴적, optional) |

## Phase G. 번들 업데이트

### G.1 산출물 정리

```bash
BUNDLE=~/minimize-test-bundle
mkdir -p $BUNDLE/{scripts,docs,test-results,apt-lists}

# 스크립트
cp host-minimize-safe-v5*.sh $BUNDLE/scripts/
[[ -f $BUNDLE/scripts/v5.0-original-snapshot.sh ]] || \
  cp v5.0-original-snapshot.sh $BUNDLE/scripts/ 2>/dev/null || true

# 문서
cp CHANGELOG.md KNOWN-ISSUES.md summary.md $BUNDLE/docs/ 2>/dev/null || true

# 테스트 진행/결과 보고서 — 반드시 포함
cp test-report-${SERVER}.md $BUNDLE/docs/ 2>/dev/null || true

# 현재 서버 테스트 결과
cp -r ./test-results/$SERVER $BUNDLE/test-results/

# test-matrix.csv 업데이트 (§16.2)
```

### G.2 서버별 상세 테스트 보고서 작성 (필수)

> **원칙**: 보고서는 **절대 요약하지 않는다.** 이전 서버의 `test-report-<server>.md` 형식과 동일한 수준의 상세도를 유지한다.
> 기준 형식: `docs/test-report-test-nn2.md` (상세 보고서의 기준 템플릿)

`docs/test-report-<server>.md` 에 아래 항목을 모두 포함해 작성:

```markdown
# 테스트 보고서: <server> (<profile>) — <날짜>

## 서버 정보
| 항목 | 값 |   ← 호스트명, 테스트 ID, 프로파일, OS, 테스트 일시,
                        사용 스크립트 IN/OUT, 번들 모드 전부 기재

## Phase A — 환경 진단
- 번들 모드, 이전 버그 검토, OS·디스크·sudo·dpkg 체크 결과 상세
- 판정: ✅/❌

## Phase B — 패키지 정합성
- 기준 파일명, 현재 패키지 수, diff 결과, 조치 내용
- 판정: ✅/❌

## Phase C — Dry-run
- 프로파일 감지 결과, 직접/연쇄 제거 수, 총 영향 수
- 제거 대상 목록 (직접 N개 전체 나열)
- 발견 버그 (있으면) 상세: 현상·원인·수정 내용·재검증
- 보호 체크리스트 전항목 ✅/❌
- 판정: ✅/❌

## Phase D — Execute
- 사전 조치 (kubelet mask 등) 상세
- 외부 백업 경로
- 실행 타임라인 (시:분:초 → 주요 이벤트)
- 직접 제거 목록, 연쇄 제거 목록, autoremove 결과
- 발견 버그 상세 (현상·원인 분석·채택/불채택 해결책·확정 수정 내용)
- 사후 검증 결과 표 (항목별 ✅/❌)
- 판정: ✅/❌/⚠

## Phase E — Rollback 검증
- 실행 방법, 복원 대상 수
- dpkg-selections diff, apt-mark diff, comm 비교 결과
- 수동 정리 내용 (있으면)
- 판정: ✅/❌

## Phase F — Edge Case
- F.1~F.10 결과 표 (통과/스킵/실패 사유 포함)
- 주요 항목 검증 상세
- 판정: ✅/❌

## 발견 버그 (N건)
- 표: ID, 심각도, Phase, 설명, 상태
- 각 버그별 상세 섹션: 발견 시점, 원인, 수정 내용, 검증 결과

## 주요 검증 확인 표
- 이전 서버에서 발견된 버그 수정 효과를 현 서버에서 재확인한 항목

## 다음 서버로 인계 사항
- 번호 매긴 목록으로 구체적으로 기재

## 산출물 목록
- 표: 파일명, 위치, 비고
```

### G.3 summary.md 증분 작성

현재 서버 섹션을 `summary.md`에 **추가**:

```markdown
## Server: <hostname> (<profile>) — <날짜>

### Phase A: 진단
- 번들 모드: <첫번째/계주>
- 이전 서버 이슈 검토: <요약>
- 환경 체크: ✅/❌

### Phase B: 패키지 정합성
- 설치 필요: N개
- 제거 후보: N개
- 조치: <none/partial/full>

### Phase C: Dry-run
- 프로파일 감지: auto=<X>, 실제=<Y>
- 제거 대상: 직접 N개 + 연쇄 M개
- 검증: ✅/❌ 체크리스트

### Phase D: Execute
- 실행 여부: <예/아니오/이유>
- 소요 시간: <분>
- 사후 검증: ✅/❌

### Phase E: Rollback
- 스크립트 내장: ✅/❌
- 외부 diff: ✅/❌

### Phase F: Edge Case
- 통과: F.1, F.2, F.7, F.9
- 스킵: F.5(파괴적), F.10

### 발견 버그
- BUG-N (P0): <요약> → Fixed in v5.0.M
- BUG-N+1 (P2): <요약> → KNOWN-ISSUES 등록

### 다음 서버로 인계 사항
- <중요 메모>
```

### G.3.1 test-matrix.csv 업데이트

```csv
server,profile,phase_a,phase_b,phase_c,phase_d,phase_e,phase_f,bugs_found,bugs_fixed,script_version_in,script_version_out,timestamp
test-nn,k8s-worker,✅,✅,✅,✅,✅,✅,2,2,v5.0,v5.0.2,2026-04-22T14:30:00
```

### G.4 인계 문서 전체 반영 확인 (번들 패키징 전 필수)

번들을 생성하기 **전에** 아래 모든 문서가 현재 서버 테스트 내용을 완전히 반영하고 있는지 확인한다.
이 단계를 건너뛰면 번들을 수신한 다음 서버가 구버전 정보를 기반으로 작업하게 된다.

| 문서 | 확인 항목 |
|------|-----------|
| `docs/test-report-<server>.md` | 상세 보고서 작성 완료 (G.2.R 참조) |
| `docs/summary.md` | 현재 서버 섹션 추가 완료 (G.2 참조) |
| `docs/CHANGELOG.md` | 이번 테스트에서 수정된 스크립트 버전 전체 기재 |
| `docs/KNOWN-ISSUES.md` | 새로 발견된 KI 등록, 수정된 KI는 Fixed 표시 |
| `test-results/test-matrix.csv` | 현재 서버 행 추가, `bugs_fixed`·`script_version_out` 정확 기재 |
| `docs/BUNDLE-CHECKSUMS.txt` | 이번 테스트에서 생성된 스크립트 파일 md5 추가 |

```bash
# 확인 방법 (빠른 검토)
grep -c "$SERVER" $BUNDLE/docs/summary.md          # 1 이상이면 OK
grep -c "$SERVER" $BUNDLE/test-results/test-matrix.csv  # 1 이상이면 OK
ls $BUNDLE/docs/test-report-${SERVER}.md           # 파일 존재 확인
```

> ⚠ 위 확인 중 하나라도 실패하면 해당 문서를 먼저 업데이트한 후 G.4로 진행.

### G.5 번들 패키징 (다음 서버로 옮기기 용이)

```bash
cd ~
tar czf minimize-bundle-after-$SERVER-$(date +%Y%m%d).tar.gz minimize-test-bundle/
ls -lh minimize-bundle-after-$SERVER-*.tar.gz
```

### G.6 Jerry에게 최종 보고

```
📊 서버 <hostname> 테스트 완료

✅ 결과 요약
- 프로파일: <k8s-worker/cephadm/compute>
- Phase A~F 통과: 6/6
- 새 버그: <N>건 (<M>건 fix)
- 스크립트 버전: v5.0 → v5.0.M

🎯 번들 준비 완료
- 위치: ~/minimize-bundle-after-<server>-<date>.tar.gz
- 크기: <MB>
- 포함: 스크립트, 문서, test-results/<서버>/

🔜 다음 서버 권장
- <다음 서버명> (프로파일: <X>)
- 이유: <정합성/순서 논리>

이 번들을 다음 테스트 서버로 복사 후 `삭제 테스트 시작` 입력하시면 이어 진행합니다.
```

## Phase H. 마지막 서버 전용 — 최종본 빌드

마지막 서버(`test-vfwc` 등) 테스트 통과 시 추가 수행:

### H.1 최종본 명명

```bash
# v5.0.N → v5.1 프로모션
cp $BUNDLE/scripts/host-minimize-safe-v5.0.*.sh $BUNDLE/scripts/host-minimize-safe-v5.1.sh
sed -i 's/^SCRIPT_VERSION=.*/SCRIPT_VERSION="5.1"/' $BUNDLE/scripts/host-minimize-safe-v5.1.sh
bash -n $BUNDLE/scripts/host-minimize-safe-v5.1.sh
```

### H.2 PRODUCTION-RUNBOOK.md 작성

§13 템플릿 기반. 테스트 중 측정한 실제 수치 반영.

### H.3 최종 검증

```bash
bash -n $BUNDLE/scripts/host-minimize-safe-v5.1.sh
shellcheck -s bash -S warning $BUNDLE/scripts/host-minimize-safe-v5.1.sh
```

### H.4 최종 번들 패키징

```bash
cd ~
tar czf minimize-bundle-FINAL-$(date +%Y%m%d).tar.gz minimize-test-bundle/
```

### H.5 최종 보고

```
🎉 전체 서버 릴레이 테스트 완료

📦 최종 번들: ~/minimize-bundle-FINAL-<date>.tar.gz

주요 내용:
- host-minimize-safe-v5.1.sh (프로덕션 투입본)
- CHANGELOG.md (v5.0 → v5.1 총 N건 변경)
- KNOWN-ISSUES.md (미해결 M건)
- PRODUCTION-RUNBOOK.md
- 6개 서버 전체 테스트 결과

§4.4 성공 기준 8개 항목 모두 충족 ✅

Jerry 리뷰 대기 중.
```

---

# § 16. 서버 간 산출물 계주 규칙

## 16.1 계주 원칙

- 각 서버 종료 시 번들은 **자기 완결적** (self-contained). 누가 봐도 현재까지 상태 재현 가능.
- `CHANGELOG.md` 는 append-only, 기록 삭제 금지.
- `v5.0-original-snapshot.sh` 는 md5 비교로 무결성 체크 대상.
- `summary.md` 는 각 서버 섹션이 **독립적으로** 작성 (다른 서버 파일 참조 최소화).
- `test-matrix.csv` 행 순서는 timestamp 기준 유지.
- **`test-report-<server>.md`** 는 서버별로 독립 생성. Phase G에서 반드시 작성 후 번들에 포함.

## 16.2 test-matrix.csv 스키마

```
server, profile, phase_a, phase_b, phase_c, phase_d, phase_e, phase_f, bugs_found, bugs_fixed, script_version_in, script_version_out, timestamp
```

각 Phase 컬럼 값: `✅` | `❌` | `⏭` | `⚠` | `skip(reason)`

## 16.3 번들 무결성 체크 (Phase A.4 자동 실행)

```bash
#!/bin/bash
# bundle-verify.sh
set -e
BUNDLE="${1:-$PWD}"
cd "$BUNDLE" || exit 1

# 1. 필수 파일 존재
FAIL=0
for f in CHANGELOG.md summary.md test-matrix.csv; do
  if ! find . -name "$f" -type f -print -quit | grep -q .; then
    echo "❌ MISSING: $f"; FAIL=1
  fi
done

# 2. 스크립트 존재
if ! find . -name "host-minimize-safe-v5*.sh" -type f -print -quit | grep -q .; then
  echo "❌ MISSING: host-minimize-safe-v5*.sh"; FAIL=1
fi

# 3. 원본 md5 대조 (BUNDLE-CHECKSUMS.txt 있을 때)
CHECKSUM_FILE=$(find . -name "BUNDLE-CHECKSUMS.txt" -type f | head -1)
if [[ -n "$CHECKSUM_FILE" ]]; then
  ORIG=$(find . -name "v5.0-original-snapshot.sh" -type f | head -1)
  if [[ -n "$ORIG" ]]; then
    EXPECTED=$(grep "v5.0-original" "$CHECKSUM_FILE" | awk '{print $1}')
    ACTUAL=$(md5sum "$ORIG" | awk '{print $1}')
    [[ "$EXPECTED" == "$ACTUAL" ]] \
      || { echo "❌ 원본 변조 의심: $ORIG"; FAIL=1; }
  fi
fi

# 4. CHANGELOG 마지막 버전 vs 현재 스크립트 SCRIPT_VERSION
CURRENT_SCRIPT=$(find . -name "host-minimize-safe-v5*.sh" -type f \
                 ! -name "*original*" | sort -V | tail -1)
if [[ -n "$CURRENT_SCRIPT" ]]; then
  SCRIPT_VER=$(grep '^SCRIPT_VERSION=' "$CURRENT_SCRIPT" | head -1 | cut -d'"' -f2)
  CHANGELOG=$(find . -name "CHANGELOG.md" -type f | head -1)
  LOG_LAST=$(grep -oE 'v5\.[0-9.]+' "$CHANGELOG" 2>/dev/null | tail -1 | tr -d v)
  if [[ -n "$LOG_LAST" ]] && [[ "$SCRIPT_VER" != "$LOG_LAST" ]]; then
    echo "⚠ 버전 불일치: script=$SCRIPT_VER, changelog=$LOG_LAST"
  fi
fi

# 5. summary 구조
SUMMARY=$(find . -name "summary.md" -type f | head -1)
[[ -n "$SUMMARY" ]] && grep -q "^## Server:" "$SUMMARY" \
  || echo "⚠ summary.md 에 서버 섹션 없음"

[[ $FAIL -eq 0 ]] && echo "✅ 번들 무결성 OK" || { echo "❌ 무결성 실패"; exit 1; }
```

검증 실패 시 **테스트 시작하지 말고 Jerry에게 보고**.

## 16.4 첫 번째 서버에서 생성해야 할 기준값

첫 번째 서버 (`test-nn` 권장) 종료 시 **번들에 기록**:

```bash
# BUNDLE-CHECKSUMS.txt 생성
cd ~/minimize-test-bundle
md5sum scripts/v5.0-original-snapshot.sh > docs/BUNDLE-CHECKSUMS.txt
# 이후 서버에서 Phase A.4가 이 파일과 대조
```

프로파일별 baseline 제거 패키지 수도 기록 (다음 서버들의 비정상 증감 감지용):

```bash
echo "# Baseline 제거 패키지 수 (첫 번째 서버 기준)" >> docs/BUNDLE-CHECKSUMS.txt
echo "# 다음 서버들이 이 값과 큰 차이면 조사 필요" >> docs/BUNDLE-CHECKSUMS.txt
echo "k8s-worker-removal-count: <N>" >> docs/BUNDLE-CHECKSUMS.txt
```

## 16.5 병렬 테스트 금지 원칙

여러 서버를 **동시에** 돌리지 않는다. 이유:

- CHANGELOG / summary 병합 시 충돌
- BUG 번호 중복 가능
- 스크립트 수정이 병렬 반영되면 어느 버전이 검증됐는지 불명

부득이 병렬 필요 시 Jerry와 사전 합의. 병합 절차:
- CHANGELOG: 시간순, 동일 BUG 번호 충돌 시 접미사(BUG-5a, BUG-5b)
- summary: 서버 섹션 단순 추가, timestamp 기준 정렬
- test-matrix: 행 단위 병합
- **스크립트 병합 금지** — Jerry 수동 통합

## 16.6 KNOWN-ISSUES.md 포맷

```markdown
# KNOWN-ISSUES — host-minimize-safe v5.x

## KI-01: <한 줄 제목>
- **발견 서버**: test-nn
- **발견 Phase**: C.2
- **심각도**: P3
- **증상**: <간단히>
- **원인**: <분석>
- **수정 안 한 이유**: <테스트 범위/시간/영향 판단>
- **우회 방법**: <운영 시 대처>
- **프로덕션 영향**: <있음/없음/제한적>
- **재검토 예정**: <v5.2 / 다음 감사 전 / 조건부>
```

각 KI 항목은 **프로덕션 Runbook §G(위험 요소)에 반드시 반영**.

## 16.7 서버 간 이동 시 체크리스트 (Jerry 측)

이 섹션은 사용자(Jerry)용 참고. Claude Code는 검증만 수행.

```
[ ] 이전 서버에서 Phase G.5 "최종 보고" 받음
[ ] ~/minimize-bundle-after-<server>-<date>.tar.gz 생성 확인
[ ] 번들 tar.gz 를 다음 서버로 복사 (scp/rsync/물리 USB 등)
[ ] 다음 서버에서 홈 디렉토리에 압축 해제
[ ] 다음 노드의 apt_list.txt 를 번들 내 apt-lists/ 에 교체/추가
[ ] 작업 디렉토리를 ~/minimize-test-bundle 로 이동
[ ] Claude Code 세션 시작
[ ] "삭제 테스트 시작" 입력
```

---

# 끝

