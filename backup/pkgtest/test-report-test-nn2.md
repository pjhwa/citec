# 테스트 보고서: test-nn2 (k8s-worker) — 2026-04-23

## 서버 정보

| 항목 | 값 |
|------|-----|
| 호스트명 | test-nn (hostname) |
| 테스트 서버 ID | test-nn2 |
| 대상 프로파일 | k8s-worker |
| 대응 프로덕션 노드 | k-nn01-con301-krw1b (추정) |
| OS | Ubuntu 24.04 Noble |
| 테스트 일시 | 2026-04-23 03:51 ~ 04:09 (강제 재부팅) |
| 사용 스크립트 | v5.0.2 (execute), v5.0.4 (번들 출력) |
| 번들 모드 | 계주 서버 (relay) — test-nn 번들 인수 |

---

## Phase A — 환경 진단

- **번들 모드**: 계주 서버 (test-nn 산출물 인수)
- **이전 서버 이슈 검토**: v5.0.1 인수, BUG-01~05 모두 Fixed
- **OS 확인**: Ubuntu 24.04.4 LTS ✅
- **디스크 여유**: ~79 GB ✅
- **apt/dpkg 상태**: 정상 ✅
- **apt_list.txt**: k-nn02-con301-krw1b_apt_list.txt 적용
- **판정**: ✅

## Phase B — 패키지 정합성

- apt_list.txt 기준 비교 수행
- 실질적 테스트 기준: 현재 시스템 설치 패키지 (CSAP 분석 목적)
- **판정**: ✅

## Phase C — Dry-run

| 항목 | 값 |
|------|-----|
| 프로파일 감지 | auto → k8s-worker (kubelet 비활성, --profile k8s-worker 명시) |
| 직접 제거 대상 | 19개 |
| 연쇄 제거 예상 | 27개 |
| 총 영향 패키지 | 46개 |

### 체크리스트
- [x] `openssh-server` 제거 대상 없음
- [x] `containerd*`, `kubelet`, `kubeadm`, `kubectl` 보호
- [x] `runc`, `cni-plugins`, `conntrack`, `socat` 보호
- [x] `telnet`, `ftp`, `apport`, `snapd` 제거 대상 포함
- [x] Critical 역의존 0건

- **판정**: ✅

## Phase D — Execute

### 실행 정보

```
03:51:26  스크립트 시작 (v5.0.2, --profile k8s-worker --execute --yes --skip-snapshot-check)
03:51:38  Phase 1 (역의존 검사) 완료
03:54:55  Phase 2 (위상 정렬 + cascade 분석) 완료 — 3분 17초 소요
03:54:55  사용자 YES 입력
03:57:20  첫 번째 패키지 제거 시작 (get_removal_order 재실행 2분 25초)
03:59:24  마지막 패키지(tmux) 제거
03:59:28  autoremove 시작
03:59:36  사후 검증 시작
03:59:43  스크립트 "정상 완료" 기록
```

### 제거된 패키지 (19개 직접)

apport, apport-core-dump-handler, apport-symptoms, bind9-dnsutils, bind9-host,
bpfcc-tools, bpftrace, byobu, crash, ftp, git, inetutils-telnet, screen,
snapd, strace, sysstat, telnet, tmux, trace-cmd

### autoremove 추가 제거 (28개) — 사후 dpkg.log 확인

bind9-libs, git-man, ieee-data, libbpfcc, libclang-cpp18, libclang1-18,
liberror-perl, libllvm18, liblmdb0, libmaxminddb0, libsensors-config,
libsensors5, libtraceevent1-plugin, libtracefs1, libutempter0, libuv1t64,
pastebinit, python3-apport, python3-bpfcc, python3-netaddr, python3-newt,
python3-problem-report, python3-systemd, python3-zstandard, run-one,
squashfs-tools, **systemd-coredump**, **python3-systemd**

> ⚠ `systemd-coredump` 및 `python3-systemd` 가 autoremove에 의해 제거됨.
> whitelist에 `systemd*` 패턴 존재하나 autoremove는 스크립트 whitelist 무시.

### 사후 검증 결과 (스크립트 기준)

- sshd:22 listen ✅
- chrony active ✅
- 제거 대상 잔류 0개 ✅
- dpkg --audit ✅ (스크립트 내)

### 서버 Hang 발생

```
03:59:43  스크립트 종료
03:59:52  kubelet restart loop 재개 (NRestarts ~500+ 누적)
04:08:55  kubelet restart #572 — 마지막 정상 로그
04:09:31  재부팅 (journal "corrupted or uncleanly shut down" 확인)
```

**원인 확정** (dpkg.log + journalctl 사후 분석):
1. `autoremove`가 `systemd-coredump`를 whitelist 검사 없이 제거
2. 제거 과정 중 `daemon-reload` 트리거
3. 이미 NRestarts ≈ 500+ 의 kubelet restart storm 상태인 systemd에 추가 부하
4. systemd deadlock → 서버 hard hang

- **판정**: ⚠ (스크립트 실행 자체는 완료, 사후 서버 hang 발생)

## Phase E — Rollback 검증

- **실행 여부**: ❌ — 서버 hang으로 인해 강제 재부팅, rollback 미수행
- **판정**: ❌ (skip)

## Phase F — Edge Case

- **실행 여부**: ❌ — Phase D 이후 hang으로 미수행
- **판정**: ❌ (skip)

---

## 발견 버그 (7건, 전량 수정)

| ID | 심각도 | Phase | 설명 | 상태 |
|----|--------|-------|------|------|
| BUG-A | P0 | D | autoremove가 whitelist 우회 → systemd-coredump 제거 → hang | ✅ Fixed v5.0.3 |
| BUG-B | P1 | D | kubelet restart storm 미탐지/미차단 | ✅ Fixed v5.0.3/5.0.4 |
| BUG-C | P1 | C/D | get_removal_order O(N²) 중복 실행 (~6분 낭비) | ✅ Fixed v5.0.3 |
| BUG-D | P1 | C/D | 모든 apt 호출 timeout 없음 | ✅ Fixed v5.0.3 |
| BUG-E | P1 | D | snapd 제거 전 snap 목록 사전 확인 없음 | ✅ Fixed v5.0.3 |
| BUG-F | P2 | D | autoremove 실제 제거 목록 사용자 미표시 | ✅ Fixed v5.0.3 |
| BUG-G | P2 | D | 패키지당 purge timeout 없음 | ✅ Fixed v5.0.3 |

### 핵심 수정 내용 (v5.0.3)
- `protect_whitelist_packages()`: autoremove 전 whitelist 패키지 `apt-mark manual`
- `do_autoremove()`: dry-run 표시 → whitelist 침범 시 중단 → systemd 계열 경고
- `check_apt_lock()`: dpkg lock 사전 점검
- `ORDERED_PACKAGES` 전역 캐시: O(N²) 정렬 중복 제거
- 모든 apt/apt-cache 호출 timeout (120s/30s/300s/600s)
- `check_snapd_safety()`: snap 목록 확인 후 사용자 확인

### 핵심 수정 내용 (v5.0.4)
- `check_k8s_health()` 확장: NRestarts > 50 탐지 시 자동 mask/stop 승인 요청
- `KUBELET_MASKED_BY_SCRIPT` 전역 추적 + on_exit() unmask 안내

---

## 다음 서버로 인계 사항

1. **v5.0.4 사용** — autoremove whitelist 보호, kubelet storm 자동 차단 포함
2. **테스트 시작 전 필수**: `sudo systemctl mask kubelet` (k8s-worker 서버에서)
   → v5.0.4 스크립트가 자동으로 감지하고 승인 요청하므로, 스크립트 실행 시 처리 가능
3. **Phase E (rollback) 반드시 수행**: 이번 서버에서 skip됨 — 다음 서버에서 검증
4. **autoremove dry-run 결과 확인**: v5.0.3 이후 do_autoremove()가 표시하는 목록 검토
5. **BUG-A 재현 없음 확인**: protect_whitelist_packages() 동작으로 systemd 계열 보호 확인

---

## 산출물 목록

| 파일 | 위치 | 비고 |
|------|------|------|
| execute-k8s-worker.log | test-results/test-nn2/ | 실제 제거 로그 |
| plan-k8s-worker.yaml | test-results/test-nn2/ | dry-run plan |
| dryrun-k8s-worker.log | test-results/test-nn2/ | dry-run 상세 |
| risk-k8s-worker.log | test-results/test-nn2/ | risk report |
| auto-detect.log | test-results/test-nn2/ | profile 자동감지 |
| host-minimize-safe-v5.0.4.sh | scripts/ | 최종 개선 스크립트 |
| CHANGELOG.md | docs/ | v5.0.2~5.0.4 변경 기록 |
| KNOWN-ISSUES.md | docs/ | KI-02, KI-03 추가 |
