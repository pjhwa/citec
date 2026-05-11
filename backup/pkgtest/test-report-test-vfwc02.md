# 테스트 보고서: test-vfwc02 (compute) — 2026-05-11

## 서버 정보

| 항목 | 값 |
|------|----|
| 호스트명 | test-vfwc02 |
| 테스트 ID | vfwc02-20260511 |
| 프로파일 | compute |
| OS | Ubuntu 24.04.4 LTS Noble, 커널 6.8.0-110-generic |
| systemd | 255 (255.4-1ubuntu8.15) |
| 테스트 일시 | 2026-05-11 |
| 투입 스크립트 | host-minimize-safe-v5.0.9.sh |
| 산출 스크립트 | host-minimize-safe-v5.0.10.sh |
| 번들 모드 | 계주 서버 (vfwc01 인수) |
| 릴레이 순서 | 6번째 (test-nn → test-nn2 → test-nn3 → test-scn → vfwc01 → test-vfwc02) |

---

## Phase A — 환경 진단

### 번들 모드 판정
- 번들 모드: **계주** (vfwc01에서 인계)
- `minimize-bundle-after-vfwc01-20260429.tar.gz` 압축 해제 완료, 번들 디렉토리 존재 확인

### 이전 서버 (vfwc01) 버그 검토
| 버그 | 상태 |
|------|------|
| BUG-K (P1): false CRIT (--no-recommends 누락) | ✅ v5.0.8 수정 완료 |
| BUG-L (P2): gnome 가상 패키지 gap (notification-daemon, policykit-1-gnome) | ⚠ KI-06 등록, 이번 서버에서 재현 및 확장 분석 |
| BUG-M (P3): ANSI plain log 오염 | ✅ v5.0.9 수정 완료 |

### 번들 무결성 검증 (§16.3)
- ✅ CHANGELOG.md, summary.md, test-matrix.csv 존재
- ✅ host-minimize-safe-v5.0.9.sh 존재
- ✅ 원본 md5 일치 (`d4d0acec252ecb9efbd920b2cf524080`)
- ✅ summary.md 서버 섹션 있음
- ✅ **번들 무결성 OK**

### OS / 환경 체크
| 항목 | 결과 |
|------|------|
| OS | Ubuntu 24.04.4 LTS Noble ✅ |
| 디스크 | 96G 중 16G 사용 (76G 여유) ✅ |
| sudo | OK ✅ |
| 설치 패키지 | 1,663개 (ii 기준) ✅ |
| dpkg --audit | 에러 없음 ✅ |
| apt-get check | 에러 없음 ✅ |
| systemd | 255 (255.4-1ubuntu8.15) ✅ |

**판정**: ✅

---

## Phase B — 패키지 정합성

- 기준 파일: `test-vfwc02_apt_list.txt` (1,663개)
- 현재 패키지 수: 1,663개 (ii 기준)
- 설치 필요: **0개**
- 제거 후보: **0개**
- 조치: **none (완전 정합)**

**판정**: ✅

---

## Phase C — Dry-run

### 프로파일 감지
- auto 감지: `compute` ✅ (A.2 추정과 일치)
- 명시 프로파일: `compute`

### 직접 제거 대상 76개 (v5.0.9 기준)
GUI 계열 (53개): gnome-shell, gdm3, xserver-xorg, xserver-xorg-core, xserver-xorg-legacy, xserver-xorg-video-all, xserver-xorg-video-amdgpu, xserver-xorg-video-ati, xserver-xorg-video-fbdev, xserver-xorg-video-intel, xserver-xorg-video-nouveau, xserver-xorg-video-qxl, xserver-xorg-video-radeon, xserver-xorg-video-vesa, xserver-xorg-video-vmware, xwayland, ubuntu-desktop-minimal, gnome-accessibility-themes, gnome-bluetooth-3-common, gnome-bluetooth-sendto, gnome-calculator, gnome-characters, gnome-clocks, gnome-control-center, gnome-control-center-data, gnome-control-center-faces, gnome-desktop3-data, gnome-disk-utility, gnome-font-viewer, gnome-initial-setup, gnome-keyring, gnome-logs, gnome-menus, gnome-online-accounts, gnome-power-manager, gnome-remote-desktop, gnome-session-bin, gnome-session-canberra, gnome-session-common, gnome-settings-daemon, gnome-settings-daemon-common, gnome-shell-common, gnome-shell-extension-appindicator, gnome-shell-extension-desktop-icons-ng, gnome-shell-extension-ubuntu-dock, gnome-shell-extension-ubuntu-tiling-assistant, gnome-startup-applications, gnome-system-monitor, gnome-terminal, gnome-terminal-data, gnome-text-editor, gnome-themes-extra-data, gnome-user-docs

평문 프로토콜 (3개): ftp, telnet, inetutils-telnet

정보유출 방지 (5개): apport, apport-symptoms, whoopsie, apport-core-dump-handler, ubuntu-report

멀티플렉서 (3개): byobu, screen, tmux

디버그/트레이스 (6개): strace, gdb, crash, bpftrace, bpfcc-tools, trace-cmd

개발/VCS (1개): git

DNS (2개): bind9-dnsutils, bind9-host

퍼포먼스 (2개): htop, sysstat

Snap (1개): snapd

### Dry-run 요약

| 항목 | vfwc01 | vfwc02 (v5.0.9) |
|------|--------|-----------------|
| 직접 제거 | 76개 | 76개 |
| 연쇄 제거 | 52개 | 52개 |
| 총 영향 | 128개 | 128개 |
| CRIT/crash | 0건 | 0건 |

**vfwc01과 100% 동일 → 재현성 확인**

### 보호 체크리스트
- ✅ openssh-server: 제거 대상 아님
- ✅ systemd*, udev, dbus*: 보호됨
- ✅ apt, dpkg: 보호됨
- ✅ libvirt*, qemu*, openvswitch*: 보호됨 (compute whitelist)
- ✅ gnome-*, gdm3, xserver-xorg*: 제거 대상 (정상)
- ✅ telnet, ftp, snapd, apport: 제거 대상 (정상)
- ✅ CRIT/crash: 없음

**판정**: ✅

---

## Phase D — Execute

### 사전 조치
- kubelet: 미설치 (compute 서버) — mask 불필요
- pending 업그레이드 20개 WARN 확인 (apparmor, coreutils, fwupd 등)

### 외부 백업
- 위치: `~/minimize-test-backup/test-vfwc02/20260511-031800/`
- 파일: dpkg-selections.txt, dpkg-l.txt, apt-manual.txt, apt-auto.txt, services-enabled.txt, ports.txt, etc.tar.gz (1.7M)

### 실행 타임라인

| 시각 | 이벤트 |
|------|--------|
| 03:19:53 | Execute 시작, compute 감지 |
| 03:19:55 | pending 업그레이드 20개 WARN |
| 03:19:59 | Baseline 저장 완료 |
| 03:19:59 | Rollback 스크립트 생성 |
| 03:20:00 | snapd 안전 경고 (snap 6개: bare, core24, firefox, gnome-46-2404, gtk-common-themes, mesa-2404) |
| 03:20:00 | Phase 1 — 역의존 검사 시작 |
| 03:20:40 | Critical 역의존 없음 |
| 03:20:40 | Phase 2 — 연쇄 제거 및 위상 정렬 시작 |
| 03:24:10 | DRY-RUN SUMMARY 출력 (76+52=128) |
| 03:24:10 | REAL REMOVAL MODE 진입 |
| 03:24:13 | 실제 제거 대상 76개 확인 (ii 상태) |
| 03:24:14 | batch purge 시작 (76개) |
| 03:24:55 | batch purge 완료 (41초) |
| 03:24:56 | whitelist 107개 apt-mark manual |
| 03:24:59 | autoremove 대상 없음 (whitelist 보호) |
| 03:25:05 | 아직 설치된 제거 대상: 0개 |
| 03:25:16 | sshd:22 OK |
| 03:25:16 | dpkg audit OK |
| 03:25:16 | failed 유닛 4개 → reset-failed 자동 처리 |
| 03:25:16 | **BUG-L 재현: notification-daemon, policykit-1-gnome 신규 설치 WARN** |
| 03:25:16 | Execute 완료 (exit=0) |

### BUG-L 확장 분석 → BUG-N 발견

**BUG-L (KI-06) 재현**:
- notification-daemon, policykit-1-gnome 자동 설치됨 (vfwc01과 동일)

**BUG-N 신규 발견 (P2)**:
- `dpkg --purge notification-daemon` 시 의존성 오류: update-notifier가 blocking
- `dpkg --purge policykit-1-gnome` 시 의존성 오류: update-manager, network-manager-gnome이 blocking
- 원인 분석:
  - update-notifier → gnome-shell | notification-daemon
  - update-manager → gnome-shell | policykit-1-gnome | polkit-1-auth-agent
  - network-manager-gnome → gnome-shell | policykit-1-gnome | polkit-1-auth-agent
  - gnome-shell 제거 후, 이 패키지들이 virtual package provider인 notification-daemon / policykit-1-gnome을 요구
  - update-manager, update-notifier, ubuntu-release-upgrader-gtk, network-manager-gnome이 DEFAULT_SAFE_REMOVE에 미등록 → 제거되지 않아 blocking 발생

**수동 정리 순서**:
1. network-manager-gnome: `dpkg --purge` 성공
2. 나머지 4개 (ubuntu-release-upgrader-gtk, update-manager, update-notifier, notification-daemon, policykit-1-gnome): 개별 순차 실패 → batch `dpkg --purge` 성공

### 사후 검증 결과

| 항목 | 결과 |
|------|------|
| sshd:22 listen | ✅ |
| ssh service active | ✅ |
| rsyslog active | ✅ |
| chrony active | ✅ |
| apparmor active | ✅ |
| auditd | ⏭ 미설치 (compute 서버 정상) |
| dpkg --audit | ✅ 에러 없음 |
| apt-get check | ✅ 에러 없음 |
| Failed 유닛 | ✅ 0건 (reset-failed 자동 처리) |
| 신규 패키지 | ⚠ notification-daemon, policykit-1-gnome (KI-06) → 수동 정리 완료 |
| 최종 패키지 수 | 1,663 → 1,555개 (108개 감소) |

**판정**: ✅ (BUG-L/BUG-N 수동 정리 완료, v5.0.10 패치로 향후 자동 처리)

---

## Phase E — Rollback 검증

### E.1 스크립트 내장 Rollback
- 스크립트: `/var/lib/host-minimize/rollback/rollback-v5-20260511-031953.sh`
- 결과: 복원 완료 메시지 ("복원 완료. reboot 권장.")
- apt-mark manual 대상 패키지 전체 복원됨

### E.2 외부 백업 Diff 검증

| 항목 | diff 줄 수 | 판정 |
|------|-----------|------|
| dpkg-selections | **0줄** | ✅ 완전 복원 |
| apt-manual | 244줄 | ⚠ 정상 (whitelist apt-mark manual 잔류 — 기존 동작) |

- 최종 패키지 수: **1,663개** ✅ 원상 복원 확인
- apt-manual 244줄 차이: `protect_whitelist_packages()`가 execute 시 적용한 107개 apt-mark manual이 rollback 후에도 유지되는 알려진 동작 (vfwc01과 동일)

**판정**: ✅

---

## Phase F — Edge Case

| # | 항목 | 결과 | 비고 |
|---|------|------|------|
| F.1 | v4.2 Bug#1 회귀 (set-e + (( ))) | ✅ | Phase C dry-run 정상 완주 |
| F.2 | --full-tree spot check | ✅ | 76+52=128 동일 |
| F.3 | 로케일 ko_KR.UTF-8 | ✅ | 76+52=128 동일 |
| F.4 | podman 보호 (cephadm 전용) | ⏭ 스킵 | cephadm 서버 전용 |
| F.5 | Lock 파일 (파괴적) | ⏭ 스킵 | 파괴적 옵션 |
| F.6 | SSH 안정성 (파괴적) | ⏭ 스킵 | 파괴적 옵션 |
| F.7 | Invalid profile → exit 2 | ✅ | `--profile foo` → exit 2 확인 |
| F.8 | Exclude 병합 | ⏭ 스킵 | 변경 없음 |
| F.9 | Plain log ANSI 없음 | ✅ | 0건 (BUG-M v5.0.9 fix 재확인) |
| F.10 | sshd down 탐지 (파괴적) | ⏭ 스킵 | 파괴적 옵션 |

**판정**: ✅

---

## 발견 버그 (1건)

| ID | 심각도 | Phase | 설명 | 상태 |
|----|--------|-------|------|------|
| BUG-N | P2 | D | compute 프로파일: update-manager 등 4개 GNOME GUI 관리 도구 DEFAULT_SAFE_REMOVE 누락 | ✅ v5.0.10 수정 완료 |

### BUG-N 상세

**발견 시점**: Phase D Execute 사후 검증 (KI-06 수동 정리 중)

**현상**:
- `dpkg --purge notification-daemon` 실패: update-notifier 의존성 blocking
- `dpkg --purge policykit-1-gnome` 실패: update-manager, network-manager-gnome 의존성 blocking
- vfwc01에서는 동일 상황이었으나 상세 분석하지 않고 통과

**원인**:
- update-manager, update-notifier, ubuntu-release-upgrader-gtk, network-manager-gnome은 GNOME 계열 GUI 관리 도구이나 패키지명이 `gnome-*` 패턴에 해당하지 않아 DEFAULT_SAFE_REMOVE 누락
- gnome-shell 제거 후 이 패키지들이 notification-daemon / policykit-1-gnome(KI-06 자동 설치 패키지) 의존성을 잡아 `dpkg --purge` 실패

**수정 내용** (v5.0.10):
```bash
# DEFAULT_SAFE_REMOVE GUI 섹션에 추가:
"update-manager" "update-notifier" "ubuntu-release-upgrader-gtk" "network-manager-gnome"
```

**검증**: v5.0.10 dry-run 결과 직접 제거 대상 76→80개 (+4개 정확히 포함) ✅

**KI-06 개선 효과**:
- batch purge 시 gnome-shell과 4개 패키지가 동시 제거되므로 notification-daemon / policykit-1-gnome 자동 설치 발생하지 않을 것으로 예상
- 차기 서버에서 v5.0.10으로 재검증 필요

---

## 주요 검증 확인 표

| 항목 | vfwc01 검증 | vfwc02 재확인 |
|------|-------------|---------------|
| BUG-K (false CRIT --no-recommends) | ✅ v5.0.8 수정 | ✅ 미재현 |
| BUG-M (ANSI plain log 오염) | ✅ v5.0.9 수정 | ✅ F.9 0건 |
| BUG-L (gnome 가상 패키지 gap) | ⚠ KI-06 등록 | ⚠ 재현 + BUG-N 연장 발견 |
| whitelist 107개 apt-mark manual | ✅ vfwc01 | ✅ vfwc02 |
| autoremove 0건 (whitelist 보호) | ✅ vfwc01 | ✅ vfwc02 |

---

## 다음 서버로 인계 사항

1. **v5.0.10 사용** (최신본) — BUG-N 패치 포함
2. **BUG-N (KI-06 확장) v5.0.10에서 수정** — 차기 compute 서버에서 재현 없는지 확인 권장
3. **미테스트 서버**: test-wproxy, test-log, test-cepho — 릴레이 계획 재확인 필요
4. test-cepho에서 **podman 보호 F.4** 검증 필수
5. rollback 후 apt-mark manual 잔류(244줄)는 정상 동작 — 이후 서버 rollback 검증 시 동일 현상 예상
6. pending 업그레이드 20개 존재 — 프로덕션 투입 전 변경관리 절차에 따라 선처리 권장

---

## 산출물 목록

| 파일명 | 위치 | 비고 |
|--------|------|------|
| host-minimize-safe-v5.0.10.sh | scripts/ | BUG-N 수정 최신본 |
| host-minimize-safe-v5.0.9.sh | scripts/ | 이전 버전 (참조용) |
| test-report-test-vfwc02.md | docs/ | 본 문서 |
| plan-auto.yaml | test-results/test-vfwc02/ | 자동감지 plan |
| plan-compute.yaml | test-results/test-vfwc02/ | compute 명시 plan |
| risk-compute.log | test-results/test-vfwc02/ | risk report |
| execute-compute.log | test-results/test-vfwc02/ | execute 로그 |
| rollback-verification-dpkg.txt | test-results/test-vfwc02/ | diff 0줄 |
| rollback-verification-manual.txt | test-results/test-vfwc02/ | diff 244줄 (정상) |
