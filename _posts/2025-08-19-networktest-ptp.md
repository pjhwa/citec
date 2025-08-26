---
title: "네트워크 테스트를 위한 정밀 시간 동기화"
date: 2025-08-19
tags: [network, test, ptp, precision, time, protocol, "1588"]
categories: [Howtos, Network]
---


PTP(Precision Time Protocol, IEEE 1588)는 네트워크에서 높은 정밀도로 시간 동기화를 제공하는 프로토콜로, NTP(Network Time Protocol)보다 훨씬 정밀한 시간 동기화(마이크로초 또는 나노초 수준)를 필요로 하는 환경에서 사용됩니다. MGEN 테스트와 같은 네트워크 성능 측정에서 음수 latency 문제나 타임스탬프 불일치를 해결하기 위해 PTP를 설정하면 효과적일 수 있습니다. 아래는 RHEL 8.4 환경에서 PTP를 설정하는 방법을 단계별로 자세히 설명합니다. 현재 날짜와 시간(2025년 8월 19일 오전 11:27 KST)을 기준으로 최신 정보를 반영하며, OpenStack 환경(k1~k10 VM)과 MGEN multicast/broadcast 테스트 맥락을 고려합니다.

---

## 1. **PTP 설정 개요**
- **PTP의 목적**: 송신/수신 서버 간 시간 차이를 최소화해 latency와 jitter 계산 정확성 향상. MGEN 로그에서 recv_time - sent_time이 음수가 되는 문제를 해결.
- **필요 조건**: PTP 마스터(시간 제공 서버)와 클라이언트(동기화 대상), PTP 하드웨어 지원(예: NIC에 1588 하드웨어 타임스탬프).
- **환경 가정**: k1을 PTP 마스터, k2~k10을 클라이언트로 설정. OpenStack VM에서 하드웨어 타임스탬프 지원 여부 확인 필요(가상화 환경은 소프트웨어 PTP에 의존 가능).

**비판적 검증**: OpenStack VM은 기본적으로 하드웨어 PTP 지원 제한(가상 NIC 문제). 소프트웨어 PTP(ptp4l)는 마이크로초 수준 동기화 가능하나, 하드웨어 지원 시 나노초 수준 달성(웹 검색 ). RHEL 8.4의 linuxptp 패키지가 기본 제공되며, VM 클러스터에서 동작 확인 필요.

---

## 2. **PTP 설정 단계**

### **2.1. 패키지 설치**
모든 VM(k1~k10)에서 PTP 소프트웨어 설치:
```bash
sudo dnf install linuxptp -y
```
- **설명**: `linuxptp` 패키지는 ptp4l(시간 동기화 데몬), phc2sys(하드웨어 클럭 동기화), pmc(PTP 관리 클라이언트)를 포함.
- **확인**: `ptp4l --version`으로 설치 확인.

### **2.2. PTP 마스터 설정 (k1)**
k1을 PTP 마스터로 설정해 시간 소스를 제공합니다.
1. **구성 파일 생성/수정**:
   - `/etc/ptp4l.conf` 생성:
     ```bash
     sudo tee /etc/ptp4l.conf <<EOF
     [global]
     priority1 128
     gmCapable 1
     domainNumber 0

     [eth0]  # 인터페이스 이름, ifconfig로 확인
     network_transport L2  # 레이어 2 (Ethernet) 사용, L3(IP)도 가능
     EOF
     ```
   - **설명**:
     - `priority1 128`: 마스터 우선순위(낮을수록 우선, 0~255).
     - `gmCapable 1`: Grandmaster 기능 활성화.
     - `domainNumber 0`: PTP 도메인(0~255, 동일 네트워크 내 동일 설정).
     - `eth0`: 네트워크 인터페이스, VM 환경에 따라 `enp0s3` 등으로 변경.

2. **PTP 데몬 실행**:
   ```bash
   sudo ptp4l -f /etc/ptp4l.conf -i eth0 -m  # -m은 로그 콘솔 출력
   ```
   - **출력 예**: `selected best master clock ...`, `master offset ... ns`로 동기화 상태 확인.
   - **백그라운드 실행**: `sudo ptp4l -f /etc/ptp4l.conf -i eth0 &`.

3. **상태 확인**:
   ```bash
   sudo pmc -u -b 0 'GET CURRENT_DATA_SET'  # 도메인 0 상태
   ```
   - `gmPriority1: 128` 등 출력.

**비판적 검증**: VM에서 하드웨어 타임스탬프 지원 안 되면 소프트웨어 동기화로 제한(마이크로초). 네트워크 스위치가 PTP 지원 필요(예: IEEE 1588 호환).

### **2.3. PTP 클라이언트 설정 (k2~k10)**
k2~k10을 클라이언트로 설정해 k1에서 제공하는 시간에 동기화합니다.
1. **구성 파일 생성/수정**:
   - `/etc/ptp4l.conf` 생성:
     ```bash
     sudo tee /etc/ptp4l.conf <<EOF
     [global]
     priority1 129  # 마스터보다 높음
     domainNumber 0

     [eth0]  # 인터페이스 이름
     network_transport L2
     EOF
     ```

2. **PTP 데몬 실행**:
   ```bash
   sudo ptp4l -f /etc/ptp4l.conf -i eth0 -m
   ```
   - **출력 예**: `selected master ... offset ... ns`로 마스터(k1) 동기화 확인.

3. **하드웨어 클럭 동기화 (옵션)**:
   - VM에서 소프트웨어 동기화:
     ```bash
     sudo phc2sys -s eth0 -w -m  # 시스템 클럭과 동기화
     ```
   - **출력**: `phc offset ... ns`로 오차 확인.

4. **상태 확인**:
   ```bash
   sudo pmc -u -b 0 'GET TIME_STATUS_NP'
   ```
   - `master_offset`가 나노초 단위로 0에 가까우면 성공.

**비판적 검증**: VM 간 네트워크 지연(마이크로초)이 남을 수 있음. OpenStack 네트워크 설정(브릿지 모드) 확인 필요. 검색 기반 에서 소프트웨어 PTP 한계 논의.

### **2.4. MGEN 테스트 재실행**
- PTP 동기화 후 MGEN 재실행:
  - sender.mgn: 이전 multicast 설정 유지.
  - receiver.mgn: 동일.
  - 실행: `mgen input /root/sender.mgn ...` 후 로그 분석.
- **기대 효과**: 음수 latency 제거, loss율 정확성 향상.

---

## 3. **주의사항 및 문제 해결**
- **하드웨어 지원 확인**:
  - `ethtool -T eth0`로 1588 지원 확인. VM은 소프트웨어만 가능할 수 있음.
  - 지원 안 되면 소프트웨어 PTP로 제한(마이크로초 수준).
- **네트워크 설정**:
  - 스위치가 PTP 지원 필요(예: Cisco/HP 1588 호환).
  - 방화벽: `sudo firewall-cmd --add-port=319/udp --add-port=320/udp --permanent` (PTP 포트).
- **문제 발생 시**:
  - 로그: `/var/log/messages` 또는 `ptp4l -l 7`로 디버깅.
  - 오차 크면 하드웨어 PTP 장치 추가 검토.

---

## 4. **결론 및 추가 팁**
- **설정 가능성**: RHEL 8.4에서 linuxptp로 PTP 설정 가능. VM 환경에서는 소프트웨어 PTP로 충분하나, 정밀도 요구 시 하드웨어 지원 필요.
- **MGEN 효과**: 음수 latency 문제 해결, 테스트 결과 신뢰성 향상.
- **팁**: 테스트 전 `chronyc tracking`으로 동기화 상태 확인. OpenStack 관리자에게 네트워크 PTP 지원 문의. 웹 검색 에서 PTP 설정 가이드 참고.

PTP 설정 후 MGEN 테스트를 재실행해 결과를 공유하면 추가 조정이 가능합니다!
