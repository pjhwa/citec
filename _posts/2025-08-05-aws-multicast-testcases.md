---
title: "AWS Multicast 성능 테스트 방안"
date: 2025-08-05
tags: [aws, multicast, performance, test, cases, iperf]
categories: [Howtos, Benchmark]
---

# SCP와 AWS의 L2 멀티캐스트 성능 비교(대역폭, 지터, 손실률 등), 한계 파악(OVN 문제 vs TGW 오버헤드), 고객 서비스 안정성 증명.

## 1. 테스트 환경 구성
회의에서 언급된 AWS TGW 구성과 Receiver VM 9개(호스트 3대, 호스트당 3개, Placement Group 활용), Sender VM 1개(별도 호스트)를 기반으로 SCP에도 유사하게 맞춥니다. 구성도는 텍스트로 묘사(실제 Visio 등으로 작성 추천).

### 1.1 공통 구성
- **테스트 범위**: L2 멀티캐스트(동일 서브넷 내). M-Route 미구성. 내부 트래픽 초점(외부-내부 불필요).
- **멀티캐스트 그룹**: 239.0.0.1 (글로벌 표준).
- **IGMP 설정**: v2로 통일(회의 확인 중). Querier 설정 확인(OVN/TGW).
- **VM 사양**: Sender/Receiver 모두 표준 인스턴스(예: t3.medium, 2vCPU, 4GB RAM). OS: Ubuntu 22.04, iperf v2 설치.
- **측정 도구**: iperf v2 (주), perfSONAR(네트워크 분석), mtrace(경로 추적), mrouted(라우팅 확인), tcpdump(패킷 캡처). Winsend/MC HAMMER(보조 부하 테스트).
- **반복/기록**: 각 테스트 5회, 평균값. 로그: CloudWatch(SCP/AWS), 그래프 시각화.
- **구성도 개요**: Sender VM → 서브넷(멀티캐스트 그룹) → Receiver VM 9개(호스트 3대 분산). 호스트 간 화살표로 트래픽 흐름 표시.

### 1.2 SCP 환경 구성
- **플랫폼**: SCP v2 PP VPC (OpenStack 기반).
- **네트워크**: 단일 VPC/서브넷(예: 10.0.0.0/24). IGMP Snooping ON (수원/상암 센터 설정 참고), TRM OFF. OVN: IGMP Snooping 활성화(기본 disable라 neutron.conf 수정), Querier ON.
- **VM 배치**: Sender 1개(별도 호스트), Receiver 9개(호스트 3대, 호스트당 3개). OpenStack 호스트 affinity로 Placement Group 유사 구현.
- **특이점**: L3 미지원으로 VPC 수 제한 피하기. 운영계 스위치 영향 없게 격리.

### 1.3 AWS 환경 구성
- **플랫폼**: AWS VPC with TGW.
- **네트워크**: TGW 생성 → 멀티캐스트 도메인 활성화 → 단일 서브넷(10.0.0.0/24) 등록/associate. IGMPv2 ON, Static sources OFF. VPC attachment.
- **VM 배치**: Sender EC2 1개(별도 호스트), Receiver EC2 9개(호스트 3대, 호스트당 3개, Placement Group 클러스터링).
- **특이점**: 기본 VPC 멀티캐스트 미지원 → TGW 필수. 비용 관리: 테스트 후 삭제.

## 2. 테스트 시나리오
iperf v2 기본 명령: Sender `iperf -s -u -G 239.0.0.1 -T 1 -i 10` (-u UDP, -T TTL=1 for L2), Receiver `iperf -c 239.0.0.1 -u`. 변형으로 깊이 더함: iperf 옵션 변화(부하), VM 스케일링(확장성), IGMP 토글(플러딩), Query 간격(동적 관리), 장기 지속(안정성), 패킷 로스 시뮬(회복력), 도구 통합(종합 분석), 호스트 간 트래픽(분산 효과). 각 변형은 기존과 조합(예: 고부하 + IGMP OFF). 목적: 성능 수치 + 원인 분석(OVN 브로드캐스트 vs TGW 오버헤드).

### 2.1 기본 절차 (모든 변형 공통)
1. **준비**: VM 생성, 그룹 가입 확인(mtrace). IGMP Querier 설정.
2. **실행**: Sender 데이터 전송, Receiver 수신 측정. 보조 도구 병행(perfSONAR 등).
3. **종료**: 로그 분석, SCP vs AWS 비교 테이블 작성.
4. **위험 관리**: 격리 환경, 운영계 미영향. 실패 시 재설정(예: OVN Snooping ON).

### 2.2 변형 케이스 및 인사이트
아래 테이블로 모든 변형 정리. SCP/AWS 모두 적용. 측정 지표: 대역폭(Mbps), 지터(ms), 손실률(%), CPU(%). 목표: 손실률 <0.1%, 지터 <1ms.

| 변형 유형 | 세부 케이스 | iperf 옵션/방법 (기본 조합) | 이유 (회의 연결) | 인사이트 (통찰) |
|-----------|-------------|------------------------------|-------------------|----------|
| **iperf 옵션 변화 (부하 테스트)** | 저부하: -b 1M, -l 512, -t 30<br>중부하: -b 10M, -l 1470, -t 60<br>고부하: -b 100M, -l 8192, -t 120 | VM 고정(9개). tcpdump 캡처. | 글로벌 옵션으로 성능 테스트 필요. 내부 트래픽 포화 지점 확인. | 고부하 시 SCP 손실 ↑ (OVN 플러딩) vs AWS 안정(TGW 효율). 통찰: 고객 비디오 서비스에서 대역폭 한계 파악, SCP 개선(IGMP v3 도입). |
| **VM 스케일링 변화 (확장성)** | 소규모: 호스트당 1/총 3<br>중규모: 2/6<br>대규모: 3/9 | 고정 옵션(-b 10M 등). Placement/Affinity 활용. | Receiver 9개 분산 강조. OVN 동일 호스트 브로드캐스트 처리. | VM 증가 시 지터 ↑ (SCP 2ms vs AWS 1ms). 통찰: 스케일링 한계 – PP 기업용 VPC에서 호스트 분산 추천. |
| **IGMP Snooping 토글** | ON (기본)<br>OFF (disable 설정) | 중부하 + VM 9개. mtrace 플러딩 추적. | OVN disable 상태 확인 필요. 수원/상암 센터 설정 반영. | OFF 시 손실 10%↑. 통찰: 브로드캐스트 변질 원인(OVN 기본값) – 운영 시 자동 ON 설정 제안, AWS TGW 우위. |
| **IGMP Query 간격 변화** | 짧음: 10초<br>표준: 125초<br>길음: 300초 | -t 300 장기 + 대규모 VM. Querier 조정. | IGMP v2 확인 중, OVN Querier 설정 필요. | 짧은 간격 시 CPU ↑ but 지터 ↓. 통찰: 실시간 앱(주식 업데이트) 최적화 – SCP OVN 수동 vs AWS 자동 관리 비교. |
| **장기 지속 테스트** | 단기: -t 60<br>중기: -t 600<br>장기: -t 3600 | 고부하 + VM 9개. perfSONAR 지속 모니터. | 내부 성능 중요, 도구 조사(perfSONAR). | 장기 시 누적 손실 2%↑. 통찰: 지속 안정성 – 컨퍼런스 서비스에서 열화 원인(OVN/TGW 오버헤드) 분석. |
| **패킷 로스 시뮬레이션** | 정상<br>저로스: 1% (tc/netem)<br>고로스: 5% | 중부하 + VM 6개. mrouted 재시도 확인. | 운영계 영향 시뮬. 도구 조사(mrouted). | 로스 시 지연 ↑ (SCP 취약). 통찰: 회복력 – 네트워크 불안정(백본 연계) 대응, L3 미지원 이유 보강. |
| **도구 통합 (Hybrid)** | iperf + mtrace(경로)<br>+ perfSONAR(지표)<br>+ MC HAMMER(부하) | 기존 변형 + 병행. Winsend 크로스 확인. | iperf 외 도구 조사 필요. | 종합: 패킷 손실 위치 파악. 통찰: 숨은 문제(포트 플러딩) – CSP 서비스 실전 증명, CISCO 사례 참고. |
| **호스트 간 vs 동일 호스트** | 동일 호스트 (모두 1호스트)<br>호스트 간 (3호스트 분산) | 중부하 + VM 9개. | 호스트 분산 강조, OVN 동일 호스트 브로드캐스트. | 호스트 간 지터 ↑. 통찰: 분산 효과 – 클라우드 스케일링 필수, AWS Placement 우위. |

## 3. 예상 결과 및 분석
- **비교 테이블 예시** (테스트 후 작성):

| 플랫폼 | 대역폭 (고부하) | 지터 (대규모 VM) | 손실률 (IGMP OFF) | 인사이트 요약 |
|--------|-----------------|-------------------|-------------------|--------------|
| SCP | 80Mbps | 2ms | 8% | OVN 문제로 취약, L2 안정적 개선 필요. |
| AWS | 95Mbps | 1ms | 3% | TGW 효율적, 스케일링 강점. |

- **전체 통찰**: SCP L2 멀티캐스트는 설정 간단하지만 OVN disable로 플러딩 위험 – 회의처럼 L3 지원 미비 이유(연계 복잡) 이해. AWS TGW는 L2에서도 우위지만 비용/설정 복잡. 추천: SCP에 IGMP 자동 ON, AWS 대안으로 고객 제안. 이 데이터로 PP 기업 서비스 향상.

---

## 1. 테스트 스크립트
iperf v2를 주로 사용하며, 쉘 스크립트로 자동화. Sender 스크립트(데이터 전송)와 Receiver 스크립트(수신 측정)를 별도로 작성. 변형은 파라미터로 전달(예: 대역폭, 시간). 보조 도구(mtrace, tcpdump)는 스크립트에 통합. 로그는 /tmp에 저장.

### 1.1 Sender VM 스크립트 (sender_test.sh)
이 스크립트는 Sender에서 실행. 멀티캐스트 데이터 전송 + 변형 적용. 사용법: `./sender_test.sh <bandwidth> <length> <time> <igmp_snoop>`

```
#!/bin/bash

# 파라미터: 대역폭(-b, e.g. 10M), 패킷 길이(-l, e.g. 1470), 시간(-t, e.g. 60), IGMP Snooping (on/off)
BANDWIDTH=${1:-10M}
LENGTH=${2:-1470}
TIME=${3:-60}
IGMP_SNOOP=${4:-on}

# IGMP Snooping 토글 (SCP OVN 예시, 실제 환경에 맞게 조정. AWS TGW는 콘솔에서 설정)
if [ "$IGMP_SNOOP" = "off" ]; then
  echo "IGMP Snooping OFF 시뮬레이션 (OVN/TGW disable 가정)"
  # 실제: neutron.conf 수정 또는 TGW 설정 변경 후 재시작
fi

# iperf 실행 (기본: 그룹 239.0.0.1, TTL=1 for L2, 보고 간격 10초)
iperf -s -u -G 239.0.0.1 -T 1 -i 10 -b $BANDWIDTH -l $LENGTH -t $TIME > /tmp/sender_log.txt

# 보조: mtrace로 경로 추적 (멀티캐스트 그룹 확인)
mtrace 239.0.0.1 >> /tmp/sender_log.txt

# 로그 출력
echo "Sender 테스트 완료. 로그: /tmp/sender_log.txt"
```

- **예시 실행**:
  - 중부하: `./sender_test.sh 10M 1470 60 on`
  - 고부하 + IGMP OFF: `./sender_test.sh 100M 8192 120 off`
  - 장기 테스트: `./sender_test.sh 10M 1470 3600 on`

### 1.2 Receiver VM 스크립트 (receiver_test.sh)
Receiver 각 VM에서 실행(9개 VM 병렬 실행 추천). 수신 측정 + 패킷 캡처. 사용법: `./receiver_test.sh <time> <query_interval> <loss_sim>`

```
#!/bin/bash

# 파라미터: 시간(-t), Query 간격(초, e.g. 125), 로스 시뮬(0/1/5 %)
TIME=${1:-60}
QUERY_INTERVAL=${2:-125}
LOSS_SIM=${3:-0}

# IGMP Query 간격 시뮬 (OVN/TGW 설정 변경 가정, 실제 명령어로 대체)
echo "IGMP Query 간격: $QUERY_INTERVAL 초 설정 (Querier 조정 가정)"

# 패킷 로스 시뮬 (tc/netem 사용, sudo 필요)
if [ $LOSS_SIM -gt 0 ]; then
  sudo tc qdisc add dev eth0 root netem loss ${LOSS_SIM}%
fi

# iperf 수신 (그룹 가입)
iperf -c 239.0.0.1 -u -t $TIME > /tmp/receiver_log.txt

# 보조: tcpdump로 패킷 캡처 (10초만, 플러딩 확인)
tcpdump -i any -n -c 100 udp port 5001 -w /tmp/receiver_capture.pcap &  # iperf 기본 포트 5001
sleep 10
killall tcpdump

# perfSONAR 통합 (설치 가정, 네트워크 지표 측정)
perfsonar-ps-traceroute 239.0.0.1 >> /tmp/receiver_log.txt  # 예시, 실제 perfSONAR 명령어

# 로스 시뮬 해제
if [ $LOSS_SIM -gt 0 ]; then
  sudo tc qdisc del dev eth0 root
fi

# 로그 출력
echo "Receiver 테스트 완료. 로그: /tmp/receiver_log.txt, 캡처: /tmp/receiver_capture.pcap"
```

- **예시 실행**:
  - 표준: `./receiver_test.sh 60 125 0`
  - 장기 + 저로스: `./receiver_test.sh 3600 125 1`
  - 짧은 Query + 고로스: `./receiver_test.sh 60 10 5`

### 1.3 전체 테스트 자동화 스크립트 (master_test.sh)
SCP/AWS 콘솔이나 Ansible 같은 도구로 VM에서 호출. VM 스케일링 변형 포함(호스트당 VM 수 조정 가정).

```
#!/bin/bash

# VM 스케일링: 호스트당 VM 수 (1,2,3)
VM_PER_HOST=${1:-3}

# Sender 시작
ssh sender-vm "./sender_test.sh 10M 1470 60 on" &

# Receiver 병렬 실행 (9개 예시, 실제 VM IP 리스트로 루프)
for i in {1..9}; do
  ssh receiver-vm-$i "./receiver_test.sh 60 125 0" &
done

# 대기 및 로그 수집
wait
echo "테스트 완료. 로그 수집: scp 각 VM에서 /tmp/* 로컬로 복사"

# 분석: 간단 Python으로 로그 파싱 (별도 실행)
python -c "
with open('/tmp/sender_log.txt') as f: print('Sender 대역폭:', f.read().split('Bandwidth')[1])
"  # 예시, 실제 파싱 로직 추가
```

- **변형 적용**: 파라미터 전달로 조합(예: 고부하 + 대규모 VM + IGMP OFF).
- **도구 통합**: 스크립트에 mrouted 추가 가능: `mrouted -d` (라우팅 데몬 시작).
- **주의**: 실제 환경에서 sudo 권한, 방화벽(ufw disable), IGMP 설정(OVN: ovn-nbctl set ... ) 확인. 회의처럼 운영계 영향 피하세요.

## 2. 테스트 다이어그램
회의에서 "테스트 구성도 작성 필요"라고 했으니, 간단한 네트워크 다이어그램을 텍스트 기반 ASCII 아트로 표현하겠습니다. (실제 도구로 그릴 때는 Draw.io 추천: Sender → 서브넷 → Receiver 그룹화.) 두 플랫폼(SCP/AWS) 공통 구조지만, SCP는 OVN, AWS는 TGW로 라벨링.

### 2.1 기본 구성도 (L2 멀티캐스트 환경)
```
[Sender VM]  ------------>  [멀티캐스트 그룹: 239.0.0.1 (L2 서브넷: 10.0.0.0/24)]
                            |
                            | (IGMP v2, Snooping ON, Query 간격 125초)
                            |
                            v
[호스트 1]                  [호스트 2]                  [호스트 3]
  |                           |                           |
  +-- Receiver VM1            +-- Receiver VM4            +-- Receiver VM7
  +-- Receiver VM2            +-- Receiver VM5            +-- Receiver VM8
  +-- Receiver VM3            +-- Receiver VM6            +-- Receiver VM9
                              (Placement Group / Affinity)

SCP 특이: OVN (IGMP Snooping ON, TRM OFF)
AWS 특이: TGW 멀티캐스트 도메인 (서브넷 associate, IGMPv2 ON)
```

- **설명**: Sender가 멀티캐스트 데이터를 서브넷으로 전송 → IGMP가 그룹 멤버(Receiver)만 필터링. 호스트 3대로 분산(회의: 호스트당 3개 VM). 화살표는 트래픽 흐름, 변형 시 (예: IGMP OFF) 플러딩 표시 추가: "----> 모든 포트로 브로드캐스트".

### 2.2 변형 구성도 예시 (VM 스케일링: 소규모)
```
[Sender VM]  ------------>  [서브넷]
                            |
                            v
[호스트 1]                  [호스트 2]                  [호스트 3]
  |                           |                           |
  +-- Receiver VM1            +-- Receiver VM2            +-- Receiver VM3
                              (총 3개 VM, 호스트당 1개)
```

- **변형 추가**: 고부하 시 "고대역폭 트래픽" 라벨, 패킷 로스 시 "노이즈 시뮬" 아이콘(예: !) 추가. 장기 테스트는 시간 축 표시: [0s] --> [3600s].

---

## 1. 로그 분석: iperf 로그와 보조 도구 결과 해석
iperf v2 테스트 후 생성되는 로그(/tmp/sender_log.txt, /tmp/receiver_log.txt)는 대역폭, 지터, 패킷 손실 등의 핵심 지표를 포함해요. 회의에서 글로벌 옵션(-i 10으로 10초 간격 보고)으로 테스트하라고 했으니, 로그는 시간대별로 세밀하게 나옵니다. 분석은 "왜 성능이 떨어지는가?"를 파악하는 데 초점 – 예: OVN disable 시 브로드캐스트 플러딩으로 손실률 증가.

### 1.1 iperf 로그 예시와 해석
- **Sender 로그 예시** (iperf -s ... 실행 후):
  ```
  [ ID] Interval           Transfer     Bandwidth
  [  3]   0.0-10.0 sec  1.25 MBytes  1.05 Mbits/sec
  [  3]  10.0-20.0 sec  1.25 MBytes  1.05 Mbits/sec
  [  3]   0.0-60.0 sec  7.50 MBytes  1.05 Mbits/sec
  ```
  - **해석**: Interval은 시간 구간, Transfer는 전송 데이터량, Bandwidth는 평균 속도. 고부하(-b 100M) 시 Bandwidth가 목표치 미달(예: 80M)하면 네트워크 포화 – SCP에서 OVN 플러딩 원인 가능(회의: 모든 포트로 전송). 인사이트: 고객 영상 스트리밍에서 끊김 예측.

- **Receiver 로그 예시** (iperf -c ... 실행 후, 각 VM별):
  ```
  [ ID] Interval           Transfer     Bandwidth       Jitter    Lost/Total Datagrams
  [  3]   0.0-10.0 sec  1.25 MBytes  1.05 Mbits/sec  0.123 ms  0/ 892 (0%)
  [  3]  10.0-20.0 sec  1.25 MBytes  1.05 Mbits/sec  0.150 ms  2/ 892 (0.22%)
  [  3]   0.0-60.0 sec  7.50 MBytes  1.05 Mbits/sec  0.140 ms  5/5352 (0.09%)
  ```
  - **해석**: Jitter는 지연 변동(실시간 서비스에 치명적), Lost/Total은 손실률. IGMP OFF 변형 시 Lost가 10% 이상 ↑ – 통찰: OVN disable 상태(회의: 브로드캐스트 처리)로 인해, 호스트 간 트래픽에서 패킷 충돌. AWS TGW ON 시 Jitter <0.1ms 유지 가능.

- **분석 방법**:
  - **수동 분석**: 로그를 cat/grep으로 필터링 – 예: `grep "Lost" /tmp/receiver_log.txt`로 손실률 평균 계산.
  - **자동 분석 Python 스크립트** (로그 파싱용, VM에 Python 설치 가정. master_test.sh에 추가 추천):
    ```python
    import re
    import sys

    # 로그 파일 경로 (예: /tmp/receiver_log.txt)
    log_file = sys.argv[1]

    with open(log_file, 'r') as f:
        log = f.read()

    # 지표 추출 (정규식으로 파싱)
    bandwidths = re.findall(r'(\d+\.\d+) Mbits/sec', log)
    jitters = re.findall(r'(\d+\.\d+) ms', log)
    losses = re.findall(r'(\d+)/\d+ \((\d+\.\d+)%\)', log)

    avg_bandwidth = sum(float(b) for b in bandwidths) / len(bandwidths) if bandwidths else 0
    avg_jitter = sum(float(j) for j in jitters) / len(jitters) if jitters else 0
    avg_loss = sum(float(l[1]) for l in losses) / len(losses) if losses else 0

    print(f"평균 대역폭: {avg_bandwidth:.2f} Mbits/sec")
    print(f"평균 지터: {avg_jitter:.2f} ms")
    print(f"평균 손실률: {avg_loss:.2f}%")

    # 인사이트: 손실률 >5% 시 OVN 문제 경고
    if avg_loss > 5:
        print("경고: 브로드캐스트 플러딩 가능성 (IGMP Snooping 확인)")
    ```
    - **사용법**: `python parse_log.py /tmp/receiver_log.txt`. 5회 반복 테스트 평균 계산. 통찰: VM 스케일링 변형(9개) 시 손실 ↑ → 호스트 분산(회의: Placement Group) 효과 확인.

- **보조 도구 로그 분석**:
  - **mtrace**: 로그 예: "Mtrace from 239.0.0.1 to Sender IP" – 경로 홉 수 확인. IGMP Query 변형 시 홉 지연 ↑ → Querier 간격 최적화(짧을수록 좋지만 CPU 부하).
  - **tcpdump 캡처 (.pcap)**: Wireshark로 열기 – 멀티캐스트 패킷(UDP 5001 포트) 필터. IGMP OFF 시 모든 Receiver에 불필요 패킷 → 플러딩 규모 측정(패킷 수 10배 ↑).
  - **perfSONAR**: 로그 예: "Latency: 0.5ms, Throughput: 10Mbps" – 장기 테스트(-t 3600)에서 누적 지연 트렌드 그래프화(Matplotlib 사용 추천).
  - **전체 비교**: SCP vs AWS 테이블 생성 – 예: Python으로 여러 로그 합쳐 CSV 출력, Excel로 시각화. 인사이트: AWS TGW가 고부하 시 안정적(오버헤드 적음) vs SCP OVN 취약(브로드캐스트).

## 2. 설정 상세: SCP와 AWS의 멀티캐스트 구성 단계
회의에서 IGMP Snooping/TRM/IGMP Query 설정 필요하다고 했으니, 세부 명령어와 단계 설명. L2만 지원(L3 미지원으로 VPC 절반 줄음)하니 격리된 테스트 VPC 사용.

### 2.1 SCP (OpenStack 기반) 설정 상세
- **IGMP Snooping 활성화** (OVN 기본 disable, 회의: 모든 포트 브로드캐스트 문제):
  - 명령어: OpenStack 컨트롤러에서 `ovn-nbctl set logical_switch <switch-name> other_config:mcast_snoop=true` (IGMP Snooping ON). TRM OFF: `ovn-nbctl set logical_router <router-name> options:mcast_relay=false`.
  - IGMP v2 확인: `ovn-nbctl show`로 버전 체크(회의 확인 중, v2만 지원 가정).
  - Querier 설정: `ovn-nbctl set logical_switch <switch-name> other_config:mcast_querier=true other_config:mcast_query_interval=125` (표준 125초).
- **VM 생성 및 서브넷**: `openstack network create test-net --provider-network-type vxlan` (VxLAN for L2, 회의 CISCO 사례 참고). VM: `openstack server create --flavor m1.small --image ubuntu sender-vm` 등. Affinity: `openstack server group create --policy affinity test-group` (호스트 분산).
- **테스트 전 확인**: `tcpdump -i <interface> igmp`로 IGMP 메시지 캡처 – Snooping ON 시 그룹 가입만 패킷.

### 2.2 AWS TGW 설정 상세
- **TGW 멀티캐스트 도메인 생성** (기본 VPC 미지원, 회의: TGW 활성화):
  - AWS 콘솔: Transit Gateways → Create Transit Gateway → Multicast 지원 체크.
  - 도메인 생성: TGW 선택 → Multicast domains → Create multicast domain.
  - 서브넷 등록: VPC → Subnets → Actions → Associate to multicast domain (단일 서브넷 for L2).
  - IGMPv2 ON: 도메인 설정 → IGMPv2 support enable. Static sources OFF (동적 그룹 가입).
- **VM 생성**: EC2 콘솔 → Launch instance → t3.medium, Placement Group: Cluster (회의: 호스트당 3개 VM 분산).
- **테스트 전 확인**: `aws ec2 describe-transit-gateway-multicast-domains` CLI로 도메인 상태. IGMP Query: 기본 125초, 조정 불가(스크립트 시뮬).

- **공통 세부**: 방화벽: Security Group에서 UDP 5001 포트 허용. 운영계 영향 피하기: 별도 VPC(회의: M-Route 건드리지 말기).

## 3. 세부 조정: 스크립트/시나리오 미세 튜닝과 위험 관리
스크립트는 기본 제공했지만, 변형에 따라 조정하세요. 회의에서 iperf 외 도구 조사(perfSONAR 등)하라고 했으니 통합.

- **스크립트 세부 조정**:
  - **VM 스케일링**: master_test.sh에서 VM_PER_HOST=1로 하면 루프 {1..3}으로 변경 – 호스트 affinity/Placement Group으로 지연 최소화.
  - **패킷 로스 시뮬**: receiver_test.sh의 tc/netem – 고로스(5%) 시 "sudo apt install iproute2" 필요. 조정: LOSS_SIM=10으로 극한 테스트.
  - **장기 테스트**: -t 3600 시 메모리 초과 방지 – VM RAM 4GB 이상. perfSONAR 설치: `sudo apt install perfsonar-ps-toolkit` (로그에 traceroute 추가).
  - **IGMP 토글 조정**: sender_test.sh에서 OFF 시 실제 OVN/TGW disable 명령 실행 – SCP: ovn-nbctl set ... mcast_snoop=false. AWS: 콘솔에서 IGMP disable (테스트 후 재활성화).
  - **호스트 간 트래픽**: 다이어그램처럼 호스트 1개 vs 3개 – 스크립트 루프에서 VM IP 그룹화(예: 호스트1 VM1-3).
  - **커스터마이징**: Multi-thread 불가(회의: iperf v2 한계)하니 병렬 스크립트(ssh)로 대체. 에러 핸들링 추가: `if ! command -v iperf; then sudo apt install iperf; fi`.

- **시나리오 세부 조정**:
  - **변형 조합**: 고부하 + IGMP OFF + 대규모 VM – 인사이트 최대화(예: 손실 15% ↑, OVN 문제 드러남).
  - **반복 횟수**: 5회 → 10회로 늘려 통계 신뢰성(평균/표준편차 계산, Python 스크립트에 추가).
  - **비교 분석 조정**: SCP L2 vs AWS L2 – 테이블에 "원인" 열 추가(예: 지터 ↑ = OVN 플러딩).
  - **보조 도구 세부**: MC HAMMER 설치(회의 조사): `git clone https://github.com/...` (가정), 실행: `mc_hammer -g 239.0.0.1 -r 100` (부하 생성). Winsend: Windows VM에서 멀티캐스트 보내기(크로스 플랫폼 테스트).

- **위험 관리와 추가 팁**:
  - **운영계 영향**: 테스트 VPC 격리 – SCP: 별도 프로젝트, AWS: 별도 계정. M-Route 건드리지 말기(회의: 전체 서비스 영향).
  - **비용 조정**: AWS TGW 비용(시간당 $0.05) – 장기 테스트 후 즉시 삭제: `aws ec2 delete-transit-gateway-multicast-domain`.
  - **디버깅**: 실패 시(예: iperf 연결 안 됨) – `ping 239.0.0.1`으로 그룹 확인, `netstat -g`로 IGMP 멤버십.
  - **인사이트 추출**: 로그 분석 후 보고서 작성 – "SCP OVN 개선: IGMP 자동 ON" 제안(회의: L3 지원 계획 없음, CISCO 사례 부족 반영). 고객 PP 서비스에 적용: 영상 회의 안정성 증대.

---

## 3. 최종 테스트 시나리오 (mcast/iperf 통합, 글로벌 스탠다드)
mcast를 주력으로, iperf v2로 비교. 변형 케이스: 부하(Throughput), VM 스케일링, IGMP 시뮬, 장기 지속, 패킷 로스, 도구 통합, 호스트 간 트래픽. 각 테스트 5회 반복, 평균/표준편차 계산.

### 3.1 기본 절차
1. **준비**: VM 생성, mcast/iperf 설치, IGMP 확인(mtrace `mtrace 239.1.1.5`).
2. **실행**: Sender(mcast send/iperf -s), Receiver(mcast receive/iperf -c). 병행: perfSONAR/mtrace.
3. **종료**: 로그 분석(Python), SCP vs AWS 비교 테이블.
4. **위험 관리**: 격리 VPC, M-Route 미사용(회의: 운영계 영향 방지).

### 3.2 변형 케이스 (글로벌 스탠다드 반영)
| 변형 유형 | 세부 케이스 | mcast 옵션 (iperf 비교) | 이유 (회의 연결) | 인사이트 (mcast 통찰) |
|-----------|-------------|-------------------------|-------------------|------------------------|
| **Throughput/부하** | 저부하: mcast -interval 1000ms, -padding 512 (iperf -b 1M, -l 512)<br>중부하: -interval 100ms, -padding 1470 (-b 10M, -l 1470)<br>고부하: -interval 10ms, -padding 8192 (-b 100M, -l 8192) | mcast send/receive -group 239.1.1.5 -max 1000. Throughput: (패킷 수 * 크기) / 시간. iperf -u -T 1. | 글로벌 옵션, 내부 성능. | mcast 통계로 손실 위치(예: SCP 8% vs AWS 2%) – 통찰: OVN 플러딩 vs TGW 안정, 고객 앱(스트리밍) 최적 대역폭. |
| **VM 스케일링** | 소규모: 3개<br>중규모: 6개<br>대규모: 9개 | mcast receive VM별 로그, CIDR(239.1.1.0/24). iperf -c 병렬. | Receiver 9개 분산. | Receiver별 지연 분포(mcast) – 통찰: 9개 시 SCP 지터 2ms ↑, AWS 1ms 유지, PP 서비스 스케일링 전략. |
| **IGMP 시뮬** | 조인: mtrace<br>리브: 수동 탈퇴<br>쿼리: -interval 10/125/300s | mcast receive + mtrace. iperf -t 300. | OVN Querier 확인. | 조인 지연(ms, mcast 로그) – 통찰: SCP OVN disable 취약, AWS TGW 빠른 재조인, IGMP v3 고려. |
| **장기 지속** | 단기: -max 100 (-t 60)<br>중기: -max 1000 (-t 600)<br>장기: -max 0 (-t 3600) | mcast -text "{c}" (카운터). perfSONAR 병행. | 내부 성능, 도구 조사. | 누적 손실(mcast 카운터) – 통찰: 장기 안정성, 비디오 컨퍼런스 열화 원인(OVN vs TGW). |
| **패킷 로스** | 저로스: tc 1%<br>고로스: tc 5% | mcast receive + tcpdump. iperf 손실률 비교. | 운영계 시뮬. | 회복 시간(mcast 통계) – 통찰: SCP 취약, AWS 회복 빠름, L3 미지원 이유 보강. |
| **도구 통합** | mcast + mtrace + perfSONAR | mcast 병행 실행, mrouted 추가. | 도구 조사. | 종합 통계 – 통찰: mcast 유연성으로 멀티그룹 분석, SCP/AWS 비교 깊이. |
| **호스트 간** | 동일 vs 분산 호스트 | mcast -interface-ip. iperf -B. | 호스트 분산. | 지연 분포 – 통찰: 분산 효과, AWS Placement 우위. |

## 4. 테스트 스크립트 (mcast/iperf 통합)
### 4.1 Sender (sender_test.sh)
```bash
#!/bin/bash
INTERVAL=${1:-100}  # ms
PADDING=${2:-1470}
MAX=${3:-1000}
SNOOP=${4:-on}
GROUP="239.1.1.5"

# IGMP Snooping (실제 환경에서 OVN/TGW 설정)
[ "$SNOOP" = "off" ] && echo "Snooping OFF 가정"

# mcast
mcast send -group $GROUP -interval $INTERVAL -padding $PADDING -max $MAX -text "Test {c}" > /tmp/mcast_sender_log.txt &
# iperf 비교
iperf -s -u -G $GROUP -T 1 -i 10 -b ${INTERVAL}M -l $PADDING -t $((MAX/10)) > /tmp/iperf_sender_log.txt &
mtrace $GROUP >> /tmp/mcast_sender_log.txt
echo "Sender 완료: /tmp/mcast_sender_log.txt, /tmp/iperf_sender_log.txt"
```

### 4.2 Receiver (receiver_test.sh)
```bash
#!/bin/bash
TIME=${1:-60}
QUERY=${2:-125}
LOSS=${3:-0}
GROUP="239.1.1.5"

# 패킷 로스 시뮬
[ $LOSS -gt 0 ] && sudo tc qdisc add dev eth0 root netem loss ${LOSS}%

# mcast
mcast receive -group $GROUP -show true > /tmp/mcast_receiver_log.txt &
# iperf
iperf -c $GROUP -u -t $TIME > /tmp/iperf_receiver_log.txt &
# 보조
tcpdump -i any -n -c 100 udp -w /tmp/mcast_capture.pcap &
perfsonar-ps-traceroute $GROUP >> /tmp/mcast_receiver_log.txt
sleep $TIME
killall tcpdump
[ $LOSS -gt 0 ] && sudo tc qdisc del dev eth0 root
echo "Receiver 완료: /tmp/mcast_receiver_log.txt, /tmp/iperf_receiver_log.txt"
```

### 4.3 로그 분석 (parse_logs.py)
```python
import re, sys
log_file = sys.argv[1]
tool = sys.argv[2]  # mcast or iperf
with open(log_file, 'r') as f:
    log = f.read()
if tool == "mcast":
    packets = len(re.findall(r'Test \d+', log))
    loss = (1000 - packets) / 1000 * 100 if "max 1000" in log else 0
    print(f"mcast: 수신 패킷 {packets}, 손실률 {loss:.2f}%")
else:
    bandwidths = re.findall(r'(\d+\.\d+) Mbits/sec', log)
    jitters = re.findall(r'(\d+\.\d+) ms', log)
    losses = re.findall(r'\d+/\d+ \((\d+\.\d+)%\)', log)
    print(f"iperf: 평균 대역폭 {sum(float(b) for b in bandwidths)/len(bandwidths):.2f} Mbits/sec, 지터 {sum(float(j) for j in jitters)/len(jitters):.2f} ms, 손실률 {sum(float(l) for l in losses)/len(losses):.2f}%")
```

## 5. 세부 조정 및 인사이트
- **조정**: mcast -interval 1ms로 극한 테스트, IGMP 리브 시뮬(mtrace + 수동 인터페이스 다운: `ip link set eth0 down`), perfSONAR로 그래프(Matplotlib). 운영계 격리: SCP 프로젝트/AWS 계정 분리.
- **인사이트**: mcast 통계로 SCP OVN의 플러딩(손실률 10%↑), AWS TGW의 안정성(지연 1ms 미만) 비교. PP 서비스에 적용: 멀티캐스트 안정성 증대, OVN 개선 제안(IGMP v3 도입).
