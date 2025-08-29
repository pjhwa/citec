---
title: "MariaDB 클러스터의 일시적 통신 단절"
date: 2025-08-29
tags: [mariadb, drbd, maxscale, ntp, chrony, vmware, network]
categories: [Issues, Network]
---

## 장애 내용 정리

이 장애는 VMware 기반의 MariaDB 클러스터(db01, db02)에서 발생한 일시적 통신 단절로, Heartbeat 네트워크(DRBD 동기화용)와 Service 네트워크(MaxScale 연결용)에 영향을 미쳤습니다. 아래에 주요 사실을 일목요연하게 정리하겠습니다. 이해하기 쉽게 시간 순서와 영향을 중심으로 분류했습니다.

### 1. **장애 발생 시간 및 범위**
- **발생 기간**: 2024년 8월 26일 08:31:51 ~ 08:32:18 (약 27초 동안 연결 끊어짐).
- **영향 범위**:
  - Heartbeat 통신: DRBD 동기화 중단 (db01과 db02 간).
  - MaxScale 통신: 순간 단절, 고객 서비스 영향 (DB 쿼리 연결 실패 가능).
  - 전체 시스템: MariaDB VM은 정상 운영되었으나, 클러스터 상태 변경으로 데이터 동기화 지연 발생.
- **관련 구성**:
  - VMware 환경: vCenter, ESXi, vRops – 해당 시간대 VM 관련 특이 이벤트 없음 (CPU, 메모리, 네트워크 로그 특이사항 없음).
  - 스토리지: HPE 블록 스토리지 (5개 디스크 사용) – 5분 단위 통계에서 특이점 없음 (세밀한 실시간 로그 부족으로 확인 어려움).
  - 네트워크: Heartbeat 네트워크 (Local Subnet, DRBD용)와 Service 네트워크 (DB-MaxScale용) 별도 구성. DRBD는 서비스 영향 없어야 하나, 실제로 MaxScale까지 영향.

### 2. **주요 로그 및 이벤트 순서** (시간 순)
- **08:31:33**: NTP 서버 변경 – chronyd가 198.19.1.53으로 재선택 (기존 서버에서 전환). NTP는 slew 모드(클럭 점진적 조정)로 설정됨.
- **08:31:49 ~ 08:32:14**: DRBD 타임아웃 시작 (db01 관점).
  - db01 kernel 로그: "drbd drbd_res01 db02: sending time expired, ko=6" (ko-count: 6 → 5 → 4 → 3 → 2로 감소).
  - 이는 DRBD의 ping-timeout(기본 500ms)과 ko-count(기본 7, 여기서는 6부터 시작)가 초과되어 연결 불안정 감지.
- **08:32:18**: DRBD 연결 완전 단절 – 42,147ms (약 42초) 응답 지연 후 해제. 재연결 시도 (sender/receiver 스레드 재시작).
- **08:32:39**: db02 관점 단절 감지 (db02 kernel 로그).
  - "drbd drbd_res01 db01: error receiving P_DATA, e: -5 l: 278528!" (278KB 데이터 패킷 수신 중 I/O error -5 발생, -5는 일반적으로 Input/Output error를 의미).
  - "meta connection shut down by peer" – 피어(db01)로부터 메타 연결 종료.
  - db02에서 21초 지연 후 단절 감지 (db01: Connected → Timeout, db02: Connected → NetworkFailure).
- **08:32:59**: DRBD 재연결 성공 – 핸드셰이크 완료, 프로토콜 121 협상.
- **08:33:00 ~ 08:34:46**: 데이터 재동기화 – drbd0: 2.6GB, drbd1: 60MB 동기화.
- **08:33:10, 08:35:13**: 클러스터 상태 변경 – Pacemaker에서 datasync 마스터 상태 감지 (MariaDB 클러스터 복구).
- **기타 관찰**:
  - netstat: 에러 통계나 패킷 손실 특이사항 없음 (그러나 실시간 캡처 부족으로 순간적 문제 감지 어려움).
  - CPU, 네트워크, 메모리 로그: DRBD 단절 외 특이 기록 없음.

### 3. **영향 분석 요약**
- DRBD는 블록 레벨 동기화 도구로, 단절 시 데이터 동기화만 중단되며 MariaDB 서비스 자체는 영향 없어야 함. 그러나 실제로 Heartbeat(클러스터 헬스 체크)와 MaxScale(로드 밸런싱/프록시) 통신까지 단절되어 고객 이슈 발생.
- NTP 변경 후 16초 만에 DRBD 타임아웃 시작 – 우연이 아닌 연관성 의심.
- db02에서 수신 오류 중심: db01은 타임아웃, db02은 네트워크 실패로 보아 db02 쪽 네트워크 입력 문제 가능.

이 정리로 장애의 흐름을 한눈에 파악할 수 있습니다. 이제 근본 원인을 추정하겠습니다.

## 근본 원인 추정

깊이 분석한 결과, 이 장애의 근본 원인은 **네트워크 수준의 일시적 지연 또는 플랩(flap, 순간적 연결 불안정)**으로 보입니다. 이는 Heartbeat 네트워크(DRBD용)에서 시작되어 Service 네트워크(MaxScale용)까지 확산된 것으로, NTP 서버 재선택이 그 증상으로 나타났습니다. 아래에 기술적 근거와 통찰을 바탕으로 자세히 설명하겠습니다.

### 1. **주요 추정 원인: 네트워크 지연/플랩**
- **설명**: DRBD는 TCP 기반으로 동작하며, ping-interval(기본 10초), ping-timeout(기본 500ms), ko-count(기본 7) 설정으로 연결을 모니터링합니다. 로그에서 ko=6부터 시작해 점차 감소한 것은 네트워크 지연이 누적되어 핑 응답이 초과된 증거입니다. db02의 "error receiving P_DATA, e: -5"는 TCP 소켓 수준 I/O 오류로, 패킷 손실이나 지연으로 인해 데이터 수신 실패를 의미합니다. 이는 VMware 가상 네트워크(vSwitch 또는 NSX)나 물리 스위치에서 순간적 플랩(예: 링크 업/다운 또는 ARP 테이블 불안정)이 발생했을 가능성을 시사합니다.
- **통찰**: Heartbeat 네트워크와 Service 네트워크가 별도 서브넷이지만, VMware 환경에서 공유된 vNIC이나 호스트 ESXi의 네트워크 스택을 사용하므로, 하이퍼바이저 수준 문제(예: vMotion 트리거 없으나, 네트워크 버퍼 오버플로)가 양쪽에 영향을 줄 수 있습니다. netstat에 특이사항 없음에도 불구하고, 이는 순간적(밀리초 단위) 문제로 캡처되지 않았을 수 있습니다. DRBD 단절이 서비스에 영향 준 것은 Pacemaker가 Heartbeat 실패를 감지해 클러스터 failover를 시도했기 때문으로 보입니다.
- **NTP 연관성**: 08:31:33에 chronyd가 NTP 서버를 198.19.1.53으로 재선택한 것은 기존 NTP 서버 접근에 지연이 발생했음을 의미합니다. chronyd는 stratum, 지연, 오프셋을 기반으로 서버를 선택하므로, 네트워크 지연으로 기존 서버의 응답이 느려지면 자동 전환합니다. slew 모드라 클럭이 급변하지 않지만, NTP 쿼리 자체가 네트워크를 사용하므로 이는 네트워크 문제의 초기 증상입니다. NTP 변경 후 16초 만에 DRBD 타임아웃: NTP 전환이 네트워크 부하를 증가시키거나, 이미 존재하던 지연을 드러냈을 수 있습니다.
- **대안적 가능성 (배제 이유)**:
  - 스토리지 문제: 5분 통계 정상, DRBD는 블록 레벨이지만 로그가 네트워크 타임아웃 중심.
  - VM 리소스 부족: vRops 이벤트 없음, CPU/메모리 로그 정상.
  - DRBD 구성 오류: ko-count가 표준값이지만, 네트워크가 안정적이라면 발생 안 함.
  - 클럭 스큐: slew 모드로 점진적 조정되므로 DRBD(타이밍 민감) 영향 적음. 그러나 큰 오프셋 시 간접 영향 가능.

전체적으로, 이는 "네트워크 불안정"이 루트로, NTP와 DRBD가 그 피해자입니다. 만약 NTP 재선택이 원인이 아니라 증상이라면, 물리/가상 네트워크 계층 문제입니다.

## 근거 확인 방법

근본 원인을 사실 기반으로 검증하려면, 아래 방법을 순차적으로 적용하세요. 이는 로그 수집과 실시간 모니터링을 중심으로 합니다.

1. **네트워크 로그 상세 확인**:
   - ESXi 호스트: `esxcli network nic stats get -n vmnicX` (vmnicX는 해당 NIC)로 패킷 드롭/에러 카운트 확인. `pktcap-uw --switchport X --dir 0 --count 1000`로 실시간 패킷 캡처 (Wireshark-like).
   - vCenter: Network I/O Control (NIOC) 로그 확인 – 지연 발생 시 bandwidth allocation 문제.
   - 물리 스위치: Cisco/Juniper 등에서 `show interfaces` 또는 `show log`로 CRC 에러, 플랩 로그 검색.

2. **NTP 로그 및 구성 검증**:
   - chronyd 로그: `/var/log/chrony/measurements.log` 또는 `chronyc tracking` / `chronyc sources` 명령으로 서버 선택 이유(지연, 오프셋) 확인. 재선택 시점의 지연 값이 높으면 네트워크 문제 증거.
   - 왜 재설정? `chronyc sourcestats`로 기존 서버의 poll interval과 jitter 확인 – jitter 높으면 네트워크 불안정.

3. **DRBD 및 Pacemaker 로그 분석**:
   - DRBD: `/proc/drbd` 또는 `drbdadm status`로 현재 상태, `cat /var/log/messages | grep drbd`로 타임아웃 상세. ko-count 설정 확인 (`drbdadm dump-config`).
   - Pacemaker: `crm_mon -1` 또는 `/var/log/pacemaker.log`로 클러스터 이벤트. Heartbeat 실패가 MaxScale에 어떻게 전파되었는지 추적.

4. **실시간 모니터링 도입**:
   - tcpdump: `tcpdump -i ethX -nnvvS port 7788` (DRBD 포트 기본 7788)로 패킷 캡처, 지연/재전송 분석.
   - iperf: db01-db02 간 `iperf -s` / `iperf -c db02`로 대역폭/지터 테스트.
   - vRops 커스텀: 실시간 메트릭(밀리초 단위 네트워크 latency) 추가.

이 방법으로 네트워크 지연을 증명하면 근본 원인 확정됩니다.

## 재발 방지 방법

재발을 막기 위해 네트워크 안정성과 구성 최적화를 중점으로 하세요. 아래는 단계별 권장 사항입니다.

1. **네트워크 강화**:
   - Redundancy 도입: Heartbeat/Service 네트워크에 NIC bonding (Linux: `nmcli con add type bond`) 또는 VMware vSwitch에 NIC Teaming 적용. 다중 경로로 플랩 방지.
   - 모니터링: Prometheus + Node Exporter로 네트워크 메트릭(패킷 드롭, latency) 실시간 감시. Alertmanager로 지연 임계치(예: 100ms) 초과 시 알림.
   - VMware 최적화: NSX 사용 시 Edge Node redundancy, 또는 DRS(분산 리소스 스케줄러)에서 네트워크 affinity 규칙 설정.

2. **NTP 안정화**:
   - 서버 다중화: chrony.conf에 3~4개 NTP 서버 추가 (예: pool.ntp.org). `iburst` 옵션으로 초기 동기화 빠르게.
   - 모니터링: `chronyc ntpdata` 스크립트로 주기적 서버 상태 체크, 재선택 시 로그 알림.
   - slew 모드 유지하되, maxslewrate 조정으로 큰 오프셋 시 안정적 처리.

3. **DRBD 및 클러스터 튜닝**:
   - Timeout 증가: drbd.conf에서 `ping-timeout = 1000;` (1초), `ko-count = 10;`으로 여유 주기. `drbdadm adjust`로 적용.
   - Dual-primary 피하기: 만약 dual-primary라면 single-primary로 변경 (split-brain 방지).
   - Pacemaker 통합: `crm configure`로 Heartbeat timeout 증가, MaxScale에 failover 지연 추가.

4. **전체 시스템 점검**:
   - 정기 테스트: HA 테스트 스크립트로 네트워크 단절 시뮬레이션 (예: `tc qdisc add dev ethX root netem delay 500ms`로 지연 인위적 생성).
   - 로그 세밀화: syslog-ng 또는 ELK 스택으로 밀리초 단위 로그 수집.
   - 펌웨어/패치: ESXi, HPE 스토리지 펌웨어 업데이트 – 알려진 버그(네트워크 플랩) 수정.

---
## 참고: NTP 로그 및 구성 검증: chronyc 명령어 출력 분석

사용자가 제공한 chronyc 명령어 출력 결과를 바탕으로, 각 필드의 의미를 자세히 설명하겠습니다. 설명은 chrony 공식 문서와 관련 자료를 기반으로 하며, 사실 검증을 위해 chrony 프로젝트의 공식 매뉴얼(예: chronyc(1) man page)을 참고했습니다. 각 값을 이해하기 쉽게, 실제 출력 예시를 들어 단계적으로 풀어 설명하겠습니다. chrony는 NTP 클라이언트/서버로, 시스템 클럭을 동기화하는 도구입니다. slew 모드(점진적 시간 조정)에서 동작할 때, 이러한 명령어는 NTP 서버의 상태, 오차, 안정성을 확인하는 데 유용합니다.

이 분석은 NTP 재선택 사건(예: 198.19.1.53으로 전환)이 네트워크 지연과 연관될 수 있음을 검증하는 데 초점을 맞춥니다. 값이 높거나 불안정하면 네트워크 문제(지연, 패킷 손실)를 의심할 수 있습니다.

### 1. chronyc sources 출력 분석
이 명령어는 chronyd가 현재 접근 중인 NTP 소스(서버) 목록과 상태를 보여줍니다. 출력은 각 소스의 품질과 동기화 상태를 한눈에 파악할 수 있게 합니다. chrony는 여러 소스 중 가장 신뢰할 수 있는 하나를 선택해 동기화합니다.

**출력 필드 상세 설명 및 이해 방법**:
- **MS (Mode/State)**: 소스의 모드와 상태를 나타냅니다.
  - '^' (서버 모드), '=' (피어 모드), '#' (로컬 참조 클럭)으로 모드 표시.
  - 상태: '*' (현재 동기화된 소스), '+' (선택된 소스와 결합 가능한 소스), '-' (제외된 소스), '?' (연결 끊김 또는 테스트 미통과), 'x' (falseticker, 다른 소스와 불일치), '~' (변동성 너무 큼).
  - 이해: '*'가 있는 소스가 주요 동기화 대상입니다. 만약 '?'나 'x'가 많으면 네트워크 문제나 잘못된 소스 설정을 의심하세요.
- **Name/IP address**: 소스의 이름 또는 IP 주소.
  - 이해: 목록에 있는 서버가 chrony.conf에 설정된 것입니다. IP가 실제로 접근 가능한지 확인하세요.
- **Stratum**: 소스의 stratum 레벨 (1: 로컬 클럭, 2 이상: 상위 서버로부터의 홉 수).
  - 이해: 낮을수록 (예: 2) 더 신뢰할 수 있습니다. 높은 stratum은 지연이 누적될 수 있음.
- **Poll**: 폴링 간격의 base-2 로그 (예: 10은 2^10=1024초 간격).
  - 이해: chrony가 자동으로 조정합니다. 높은 값은 안정적 소스, 낮은 값은 자주 확인 Needed.
- **Reach**: 도달 가능성 레지스터 (8비트 octal, 최대 377=11111111).
  - 이해: 최근 8번 전송 중 성공한 횟수. 377은 모두 성공, 낮으면 패킷 손실(네트워크 문제) 의심.
- **LastRx**: 마지막 샘플 수신 시간 (초 단위, m/h/d/y 접미사 가능).
  - 이해: 최근이면 소스가 활성, 오래되면 연결 문제.
- **Last sample**: 마지막 측정 오프셋 (브라켓 안: 실제 측정값, +/-: 오차 범위).
  - 이해: 음수(-)는 로컬 클럭이 느림, 양수(+)는 빠름. us/ms 단위로 작을수록 좋음. 큰 변동은 네트워크 지터(jitter)나 클럭 드리프트.

**제공된 출력 예시 해석**:
```
MS Name/IP address         Stratum Poll Reach LastRx Last sample
===============================================================================
^- prod-ntp-5.ntp4.ps5.cano>     2  10   377   397  -3878us[-3930us] +/-  126ms
...
^* time.ravnus.com               2  10   377   350   -705us[ -756us] +/- 5828us
...
```
- '*'가 time.ravnus.com에 있으므로 이 소스가 현재 동기화 대상 (재선택된 서버일 수 있음).
- 모든 Reach가 377: 최근 8회 모두 성공, 패킷 손실 없음. 하지만 과거 지연 사건 시 이 값이 떨어질 수 있음.
- Last sample: 대부분 us 단위로 작음 (예: -705us), 안정적. 그러나 any.time.nl의 +13ms는 큰 오프셋으로, 네트워크 지연 의심.
- 이해 팁: 만약 NTP 재선택(198.19.1.53)이 발생했다면, 이 출력에서 새 서버가 나타나고 오프셋이 초기화될 수 있습니다. 지연 원인으로, +/- 값이 ms 단위로 크면 네트워크 불안정.

**추가 확인 명령어**:
- `chronyc sources -v`: verbose 모드로 컬럼 설명 추가 출력 (초보자 추천).
- `chronyc ntpdata [소스 이름]`: 특정 소스의 상세 NTP 데이터 (예: remote addr, local addr, leap status, scores 등). 예: `chronyc ntpdata time.ravnus.com`으로 지연 원인(예: root delay) 확인.
- `chronyc activity`: 온라인/오프라인 소스 수 요약 (빠른 상태 체크).

### 2. chronyc sourcestats 출력 분석
이 명령어는 각 소스의 드리프트율(drift rate)과 오프셋 추정 프로세스 정보를 보여줍니다. chrony가 선형 회귀(linear regression)를 통해 클럭 오차를 예측하는 데 사용됩니다.

**출력 필드 상세 설명 및 이해 방법**:
- **Name/IP Address**: 소스 이름 (sources와 동일).
- **NP (Number of Points)**: 유지된 샘플 포인트 수 (선형 회귀에 사용).
  - 이해: 많을수록 (예: 64) 안정적 추정. 적으면 초기 단계 또는 샘플 삭제됨.
- **NR (Number of Runs)**: 마지막 회귀 후 동일 부호 잔차(residuals) 연속 수.
  - 이해: NP에 비해 낮으면 선형 적합 좋음. 높으면 드리프트 불안정, chrony가 오래된 샘플 버림.
- **Span**: 가장 오래된/새로운 샘플 간 간격 (초 단위, m/h/d/y 접미사).
  - 이해: 길수록 (예: 18h) 장기 추정 정확. 짧으면 최근 데이터만.
- **Frequency**: 추정된 잔여 주파수 (ppm, parts per million). 로컬 클럭이 소스 대비 느림/빠름.
  - 이해: 0에 가까울수록 좋음. 양수: 로컬 빠름, 음수: 느림.
- **Freq Skew**: 주파수 추정 오차 범위 (ppm).
  - 이해: 작을수록 (예: 0.044) 정확. 크면 불안정.
- **Offset**: 추정 오프셋 (us/ms 등).
  - 이해: 소스 대비 로컬 클럭 차이. 작을수록 동기화 좋음.
- **Std Dev (Standard Deviation)**: 샘플 표준편차.
  - 이해: 작을수록 (예: 1810us) 일관성 있음. 크면 지터나 노이즈.

**제공된 출력 예시 해석**:
```
Name/IP Address            NP  NR  Span  Frequency  Freq Skew  Offset  Std Dev
==============================================================================
prod-ntp-5.ntp4.ps5.cano>  64  38   18h     +0.025      0.045  -3021us  1989us
...
time.ravnus.com            33  17  552m     -0.001      0.070   -237ns   979us
...
```
- NP가 64인 소스들: 장기 데이터 축적, 안정적. time.ravnus.com은 33으로 최근 선택된 듯 (NTP 재선택 증거?).
- Frequency 대부분 +0.02x ppm: 로컬 클럭 약간 빠름, slew 모드로 조정 중.
- Std Dev us 단위: 대부분 안정, 하지만 any.time.nl의 +16ms Offset은 큰 편차로 네트워크 지연 가능성.
- 이해 팁: NTP 재설정이 왜 일어났는지? Freq Skew나 Std Dev가 높은 소스가 기존 서버라면, chrony가 더 나은 소스(낮은 skew)로 전환. 예: time.ravnus.com의 -0.001 ppm은 우수.

**추가 확인 명령어**:
- `chronyc sourcestats -v`: verbose로 컬럼 설명 추가.
- `chronyc selectdata`: 소스 선택 기준 상세 (예: combined offset, root distance). 재선택 이유(낮은 score 소스 제외) 확인.
- `chronyc serverstats`: chronyd 서버 통계 (NTP 패킷 수, 드롭 등). 클라이언트 요청 과부하나 지연 검출.

### 3. chronyc tracking 출력 분석
이 명령어는 시스템 클럭의 전체 성능 파라미터를 보여줍니다. chrony가 NTP 소스를 기반으로 로컬 클럭을 어떻게 추적하는지 요약합니다.

**출력 필드 상세 설명 및 이해 방법**:
- **Reference ID**: 현재 동기화된 소스의 ID와 이름/IP.
  - 이해: 동기화 대상 확인. 변경되면 재선택 발생.
- **Stratum**: 시스템의 stratum (참조 소스 +1).
  - 이해: 낮을수록 상위 계층.
- **Ref time (UTC)**: 마지막 참조 시간 (UTC).
  - 이해: 최신 동기화 시점.
- **System time**: NTP 시간 대비 로컬 시간 차이 (초).
  - 이해: 0에 가까울수록 좋음. slow/fast 표시.
- **Last offset**: 최근 오프셋 조정 (초).
  - 이해: slew 적용된 값. 작을수록 안정.
- **RMS offset**: 루트 평균 제곱 오프셋 (초).
  - 이해: 평균 오차. 낮을수록 정확.
- **Frequency**: 클럭 주파수 (ppm, slow/fast).
  - 이해: 로컬 클럭 드리프트율.
- **Residual freq**: 잔여 주파수 오차 (ppm).
  - 이해: 0에 가까울수록 좋음.
- **Skew**: 주파수 skew (ppm).
  - 이해: 주파수 추정 불확실성.
- **Root delay**: 루트 지연 (초, 왕복 시간).
  - 이해: 작을수록 (네트워크 지연 적음).
- **Root dispersion**: 루트 분산 (초, 오차 누적).
  - 이해: 낮을수록 신뢰성 높음.
- **Update interval**: 업데이트 간격 (초).
  - 이해: 자주 업데이트되면 불안정.
- **Leap status**: 리프 초 상태 (Normal: 정상).

**제공된 출력 예시 해석**:
```
Reference ID    : DD97764E (mail.pyeongga.com)
Stratum         : 3
Ref time (UTC)  : Fri Aug 29 00:01:41 2025
System time     : 0.000106650 seconds slow of NTP time
Last offset     : -0.000051298 seconds
RMS offset      : 0.000148047 seconds
Frequency       : 29.683 ppm slow
Residual freq   : -0.001 ppm
Skew            : 0.072 ppm
Root delay      : 0.006277970 seconds
Root dispersion : 0.000998642 seconds
Update interval : 1036.1 seconds
Leap status     : Normal
```
- Reference ID: mail.pyeongga.com (동기화 대상, 재선택된 서버?).
- System time: 0.000106650 초 slow – 매우 미세, slew 모드로 잘 조정 중.
- Frequency: 29.683 ppm slow – 로컬 클럭 느림, chrony가 보정.
- Root delay: 0.006초 (6ms) – 네트워크 지연 작음, 정상.
- 이해 팁: NTP 재설정 원인으로, Root delay나 dispersion이 과거 로그에서 높았을 수 있음. Skew 0.072 ppm은 낮아 안정적.

**추가 확인 명령어**:
- `chronyc makestep`: 강제 동기화 (테스트용, slew 무시).
- `chronyc offset`: 현재 오프셋만 확인 (빠른 체크).
- 로그 파일 확인: `/var/log/chrony/measurements.log` (상세 측정 로그, tail -f로 실시간 모니터링).

