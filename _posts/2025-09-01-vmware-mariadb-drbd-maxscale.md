---
title: "VMware 기반 MariaDB VM에서 네트워크 단절 장애"
date: 2025-09-01
tags: [vmware, mariadb, pacemaker, maxscale, drbd]
categories: [Issues, Network]
---

### 장애 내용 정리

| 시간 (2025-08-26) | 주요 이벤트 | 상세 설명 | 영향 및 결과 |
|--------------------|-------------|-----------|--------------|
| 이전 (Aug 24~25) | NTP 서버 주기적 재선택 | db01 chronyd 로그: xxx.xx.xx.1(ntp1.xxx.com) → xxx.xx.xx.2(ntp2.xxx.com) 등 반복. slew 모드로 설정됨. | chrony의 정상 동작으로 보임. 서버 품질(지연, 안정성)에 따라 자동 선택. 직접적 문제 아님. |
| 08:31:33 | NTP 서버 재선택 | chronyd가 xxx.xx.xx.2로 재선택. | 네트워크 지연 초기 증상. slew 모드로 클럭 점진적 조정, 큰 영향 없음. |
| 08:31:36 | DRBD/MaxScale 연결 이상 시작 | DRBD: db01-db02 통신 지연 (42,147ms 후 단절). MaxScale: 연결 이상. | Heartbeat 네트워크 플랩(flap, 순간 불안정) 의심. |
| 08:31:39 | Application 이슈 | MariaDBmon: 'show all slaves status;' 쿼리 실패 ('lost connection'). | DB 클러스터 모니터링 오류. |
| 08:31:49 ~ 08:32:14 | DRBD 타임아웃 | db01 kernel: "sending time expired" (ko=6 → 2). | DRBD 동기화 중단. 데이터 일관성 영향. |
| 08:31:51 ~ 08:32:18 | MaxScale 연결 단절 | MaxScale 로그: "Lost connection during query" → server1 [Master, Running] → [Down]. | 고객 서비스 영향 (27초 통신 끊어짐). MaxScale 파라미터로 인해 타임아웃 발생 (backend_connect_timeout: 3s, backend_read_timeout: 3s). |
| 08:32:18 | DRBD 완전 단절 | 연결 해제 후 재연결 시도. | 클러스터 불안정 확대. |
| 08:32:39 | db02 단절 감지 | db02 kernel: "error receiving P_DATA, e: -5" (I/O error, 278KB 수신 실패). "meta connection shut down by peer". | db02 쪽 네트워크 실패. 연결 상태: db01 (Timeout), db02 (NetworkFailure). |
| 08:32:59 | DRBD 재연결 성공 / MaxScale 정상화 | 핸드셰이크 완료. MaxScale: [Down] → [Master, Running]. | 연결 복구. |
| 08:33:00 ~ 08:34:46 | 데이터 재동기화 | drbd0: 2.6GB, drbd1: 60MB. | 데이터 일관성 회복. |
| 08:33:10, 08:35:13 | 클러스터 상태 변경 | Pacemaker: master-datasync [db02] 10 → 10000. | 클러스터 정상화. |

- **전체 요약**: VMware 기반 MariaDB VM(db01, db02)에서 Heartbeat (DRBD용)과 Service 네트워크 (MaxScale용)가 약 27초 동안 단절. vCenter/ESXi 이벤트 없음, HPE 스토리지 5분 통계 정상. netstat 패킷 손실 없음. NTP 재선택은 주기적 현상으로 정상.

### 근본 원인 추정

깊이 분석한 결과, 근본 원인은 **네트워크 수준의 일시적 지연 또는 플랩(flap)**으로 추정됩니다. 이는 NTP, DRBD, MaxScale 모두에 영향을 주었으며, 추가 로그로 더 명확해졌습니다. 아래에 사실 기반으로 자세히 설명하겠습니다.

#### 1. **NTP 서버 재설정 이유 (왜 일어났는지?)**
- **추정 원인**: chronyd는 NTP 서버를 자동으로 재선택합니다. 이는 서버의 안정성, 동기화 품질(오프셋, 지연), 네트워크 근접성에 따라 발생하는 정상 동작입니다. 제공된 로그처럼 주기적(Aug 24~25 반복)이라면, chrony가 설정된 풀(pool)에서 최적 서버를 랜덤하게 또는 지연 증가 시 선택하는 것입니다. slew 모드라 시간 급변 없지만, 네트워크 지연이 있으면 기존 서버를 버리고 새로 선택합니다.
- **통찰**: 08:31:33 재선택 후 16초 만에 DRBD 타임아웃 – NTP 쿼리가 네트워크 지연을 드러낸 증상. 주기적 재선택은 chrony 버전 업그레이드나 poor server 때문일 수 있음. 그러나 이 자체가 원인이 아니라 네트워크 문제의 결과입니다.
- **배제 이유**: 클럭 드리프트가 크지 않음 (slew 모드). 로그에서 큰 오프셋 없음.

#### 2. **DRBD와 MaxScale 단절 연계**
- **DRBD 측**: ko-count 감소는 TCP 기반 핑 타임아웃(기본 500ms) 누적으로, 네트워크 지연이 원인. db02의 I/O error(-5)는 패킷 수신 실패로, 입력 측 문제.
- **MaxScale 측**: monitor_interval 2000ms(2s)로 주기적 모니터링 중 backend_connect_timeout 3s, backend_read_timeout 3s 초과 시 서버를 [Down]으로 표시. failcount 5는 5회 실패 후 다운 선언. 로그의 "Lost connection during query"는 정확히 이 타임아웃 패턴.
- **통찰**: Heartbeat (Local Subnet)과 Service 네트워크가 별도지만, VMware vNIC 공유로 지연이 양쪽에 전파. NTP 재선택 → DRBD (30초 지속) → MaxScale (27초 단절). DRBD 중단은 동기화만 영향 주지만, Pacemaker가 클러스터 상태 변경으로 MaxScale에 간접 영향.

- **전체 근본 원인**: 네트워크 플랩 (예: vSwitch 버퍼 오버플로, ARP 불안정). 스토리지/VM 리소스 문제 배제 (로그 정상).

### 근거 확인 방법

근본 원인을 검증하려면 아래 방법을 적용하세요. 사실 기반으로 세밀하게 설명합니다.

1. **NTP 재선택 원인 확인**:
   - 명령어: `chronyc sources` / `chronyc sourcestats` – 서버 지연(jitter, offset) 확인. 높은 값이면 네트워크 문제.
   - 로그: `/var/log/chrony/measurements.log` – 재선택 시점의 poll interval과 root delay 분석.
   - 추가: `chronyc selectdata` – 선택 기준(score) 확인.

2. **네트워크 지연 검증**:
   - ESXi: `esxcli network nic stats get -n vmnicX` – 드롭/에러 누적 확인 (변화량 모니터링).
   - 실시간: `pktcap-uw --vmnic vmnicX --dir 0` – 패킷 캡처로 지연 포착.
   - iperf: db01-db02 간 대역폭/지터 테스트.

3. **MaxScale 확인**:
   - 로그: maxscale.log 상세 분석 – 타임아웃 이벤트 횟수 (failcount 5 초과 여부).
   - 명령어: `maxctrl show monitors` – 현재 상태와 파라미터 검증.

4. **전체 모니터링**:
   - vRops: 실시간 네트워크 latency 그래프 추가.
   - tcpdump: DRBD 포트(7788) 캡처 – 재전송 패킷 확인.

### 재발 방지 방법

재발을 막기 위해 네트워크와 구성 최적화를 중점으로 하세요. 사실 기반으로 단계별 추천합니다.

1. **NTP 안정화**:
   - chrony.conf: 서버 풀 확대 (3~4개 추가, iburst 옵션). minpoll/maxpoll 조정으로 재선택 빈도 줄임.
   - 모니터링: cron 스크립트로 `chronyc tracking` 주기적 체크.

2. **네트워크 강화**:
   - VMware: NIC teaming 또는 bonding 도입 (다중 경로). NIOC (Network I/O Control)로 대역폭 할당.
   - 물리 스위치: 포트 미러링으로 플랩 로그 확인.

3. **DRBD/MaxScale 튜닝**:
   - DRBD: ping-timeout 1000ms, ko-count 10으로 증가 (drbd.conf 수정).
   - MaxScale: backend_connect_timeout/backend_read_timeout 5~10s로 증가, monitor_interval 5000ms로 조정. failcount 10으로 여유.

4. **전체 시스템**:
   - 정기 테스트: 네트워크 지연 시뮬레이션 (tc netem 명령).
   - 로그 통합: ELK 스택으로 밀리초 단위 모니터링.
   - 펌웨어 업데이트: ESXi/HPE 최신 버전 적용.
