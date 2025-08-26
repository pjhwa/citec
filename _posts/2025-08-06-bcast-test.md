---
title: "Broadcast 성능 테스트 방안"
date: 2025-08-06
tags: [cloud, network, performance, test, broadcast, ostinato]
categories: [Howtos, Benchmark]
---


## MGEN을 사용한 Broadcast 성능 테스트 가능성

MGEN(Multi-Generator)은 NRL(Naval Research Laboratory)에서 개발된 오픈소스 도구로, IP 네트워크 성능 테스트를 위해 UDP/TCP 트래픽을 생성하고 측정한다. 문서에 따르면, MGEN은 unicast, multicast뿐만 아니라 broadcast를 지원한다. 구체적으로:

- **BROADCAST 옵션**: Transmission Event Options 섹션(5.2.6)에서 BROADCAST [ON|OFF]를 통해 소켓의 SO_BROADCAST 옵션을 제어한다. 기본값은 ON으로, broadcast 메시지 전송/수신을 허용한다.
- **Destination (DST) 옵션**: DST 필드에서 broadcast 주소(예: 255.255.255.255)를 지정할 수 있다.
- **테스트 가능성**: 예, broadcast 성능 테스트가 가능하다. MGEN은 실시간 트래픽 패턴을 생성하고, 수신 측에서 로그를 통해 대역폭(throughput), 지터(latency variation), 손실률(loss rate)을 측정할 수 있다. 그러나 broadcast는 네트워크에서 브릿지/라우터 경계를 넘지 않으므로, 같은 서브넷 내에서만 테스트해야 한다. 비판적 검증: broadcast는 네트워크 과부하를 유발할 수 있으므로, 프로덕션 환경이 아닌 격리된 테스트 네트워크에서 수행하라. MGEN의 UDP 기반 broadcast는 신뢰성 없으므로, 손실률이 높을 수 있다.

MGEN은 broadcast를 직접 지원하지만, multicast와 유사하게 동작한다. 만약 broadcast가 아닌 multicast를 의도했다면, JOIN/LEAVE 이벤트를 사용해 더 유연하게 테스트할 수 있다. 하지만 질문이 broadcast이므로 이에 초점을 맞춘다.

## 테스트 상세 방법

### 1. 기본 설정
- **환경**: 하나의 송신 호스트와 여러 수신 호스트(예: 3~5대)를 같은 서브넷에 배치. RHEL 8.4 기반 호스트 사용.
- **트래픽 생성**: 송신 측에서 UDP broadcast 트래픽 생성 (TCP는 broadcast 지원 안 함).
- **측정 항목**:
  - **대역폭(Throughput)**: 수신된 메시지 크기와 도착 시간으로 계산 (rate = 총 바이트 / 시간).
  - **지터(Jitter)**: latency 변동 (문서 7.2 RECV 이벤트의 latency 필드 사용, 평균/최소/최대 latency 계산).
  - **손실률(Loss Rate)**: 시퀀스 번호(sequenceNumber)로 누락된 메시지 비율 계산 (loss = (예상 메시지 - 수신 메시지) / 예상 메시지).
- **로그 형식**: 텍스트 로그(기본) 또는 바이너리 로그 사용. RECV 이벤트에서 sent/received 타임스탬프, size, seq 등을 추출.

### 2. 송신 측 스크립트 예시 (sender.mgn)
송신 측에서 broadcast 트래픽을 생성하는 MGEN 스크립트 파일:
```
# Global Commands
START NOW  # 즉시 시작
TXBUFFER 65536  # 송신 버퍼 크기 설정 (성능 최적화)
RXBUFFER 65536  # 수신 버퍼 크기 설정
BROADCAST ON  # Broadcast 활성화 (기본 ON이지만 명시)
TTL 1  # Broadcast는 TTL 1로 충분

# Transmission Events
0.0 ON 1 UDP DST 255.255.255.255/5000 PERIODIC [10 1024]  # 10 packets/sec, 1024 bytes each (0.1MBytes)
10.0 OFF 1  # 10초 후 종료 (테스트 기간 제한)
```
- **설명**: DST에 broadcast 주소(255.255.255.255)와 포트(5000) 지정. PERIODIC 패턴으로 규칙적 트래픽 생성. rate(10)는 packets/sec, size(1024)는 바이트 단위.
- 실행: `mgen input sender.mgn txlog output sender_log.txt` (txlog: 송신 로그 활성화).

### 3. 수신 측 스크립트 예시 (receiver.mgn, 각 수신 호스트별)
각 수신 호스트에서 수신 모드로 실행:
```
# Global Commands
START NOW
RXBUFFER 65536  # 수신 버퍼 크기 설정
ANALYTICS  # 내장 분석 활성화 (loss, latency 자동 계산)
WINDOW 1  # 분석 윈도우 1초 (지터/손실률 측정 간격)

# Reception Events
0.0 LISTEN UDP 5000  # 포트 5000 수신
```
- 실행: `mgen input receiver.mgn output receiver_log.txt` (각 호스트별 로그 파일 생성).
- 여러 수신 측: 호스트별로 로그 파일을 수집해 비교 분석.

### 4. 테스트 실행 단계
1. 송신 호스트: `mgen input sender.mgn txlog output sender_log.txt`
2. 수신 호스트(각각): `mgen input receiver.mgn output receiver_log.txt`
3. 테스트 후 로그 수집: scp 등으로 모든 receiver_log.txt를 중앙 호스트로 모음.
4. 분석: 로그에서 RECV 이벤트 파싱.

### 5. 트래픽 부하에 따른 테스트 케이스
- **저부하**: 낮은 rate/small size. 네트워크가 안정적일 때 지터/손실률 낮음.
  - 스크립트 수정: PERIODIC [1 512] (1 packet/sec, 512 bytes).
  - 예상: Throughput ~4 Kbps, Loss ~0%, Jitter <1ms.
- **중부하**: 중간 rate/medium size. 일부 손실 발생 가능.
  - PERIODIC [10 1024] (10 packets/sec, 1024 bytes).
  - 예상: Throughput ~80 Kbps, Loss <5%, Jitter 1 ~ 5ms.
- **고부하**: 높은 rate/large size. 네트워크 포화로 손실/지터 증가.
  - PERIODIC [100 8192] (100 packets/sec, 8192 bytes, UDP max size).
  - 예상: Throughput ~6 Mbps, Loss >10%, Jitter >10ms.
- 각 케이스별 30초~1분 실행, 3회 반복 측정 (평균값 사용). 부하 증가 시 네트워크 하드웨어(스위치 등) 한계를 검증.

비판적 검증: 고부하에서 broadcast는 네트워크 스톰 유발 가능. tcpdump로 트래픽 캡처해 MGEN 로그와 교차 검증. NTP로 호스트 시계 동기화 (latency 정확도 향상).

## RHEL 8.4 기반 설치 및 테스트 방법

### Protolib 필요 여부 확인

GitHub 리포지토리(https://github.com/USNavalResearchLaboratory/mgen )의 README 및 빌드 지침 섹션에서 MGEN(Multi-Generator) 버전 5.x를 빌드하려면 **Protolib**이 필수 의존성으로 명시되어 있습니다. Protolib은 MGEN의 코어 라이브러리로, 소스 트리(source tree) 형태로 MGEN 소스 트리의 최상위 수준에 배치되어야 합니다. 이는 빌드 과정에서 Protolib의 헤더와 라이브러리를 참조하기 때문입니다. Protolib은 별도 GitHub 리포지토리(https://github.com/USNavalResearchLaboratory/protolib )에서 다운로드할 수 있으며, MGEN 빌드 시 symbolic link나 직접 복사로 통합해야 합니다.

**비판적 검증**: 이 요구사항은 MGEN의 오래된 설계(Naval Research Laboratory의 PROTEAN 프로젝트 기반)에서 비롯되며, 최신 버전(5.02c 기준)에서도 유지됩니다. 만약 Protolib을 생략하면 컴파일 오류(예: 헤더 파일 누락)가 발생할 수 있습니다. 그러나 Protolib 자체가 가볍고 독립적이기 때문에 큰 부담은 아니며, IPv6 지원 등 MGEN 기능의 안정성을 보장합니다. RHEL 8.4처럼 안정적인 엔터프라이즈 Linux 환경에서 잘 동작하지만, gcc 버전 호환성(8.5 기본)을 확인하세요. 만약 Protolib이 제대로 배치되지 않으면 빌드 실패가 빈번하니, 사전 테스트를 권장합니다.

### **준비 단계: 시스템 요구사항 확인 및 의존성 설치**
MGEN은 C++ 기반으로, 기본 개발 도구와 라이브러리가 필요합니다. Protolib은 추가 의존성 없이 빌드되지만, MGEN은 Protolib을 참조합니다.

1. **RHEL 8.4 업데이트 및 개발 도구 설치**:
   - 이유: 최신 패키지로 컴파일 오류 방지. gcc, make, git 등이 필요.
   - 명령어:
     ```
     sudo dnf update -y
     sudo dnf groupinstall "Development Tools" -y
     sudo dnf install git -y
     ```
   - 추가 라이브러리(선택적, 하지만 IPv6나 PCAP 지원 시 유용):
     ```
     sudo dnf install libpcap-devel -y  # HAVE_PCAP 옵션용, tcpdump 클론 기능
     sudo dnf install openssl-devel -y  # 체크섬 등 보안 기능
     ```
   - 잠재적 오류: dnf가 활성화되지 않았다면 `sudo subscription-manager register`로 RHEL 구독 확인.
   - 비판적 검증: RHEL 8.4의 gcc 8.5는 MGEN 5.x와 호환되지만, 너무 오래된 gcc(예: 4.x)라면 오류 발생 가능. 개발 도구 그룹은 make, gcc, g++ 등을 한 번에 설치하므로 효율적입니다.

2. **작업 디렉토리 생성**:
   - 이유: 소스 코드를 체계적으로 관리.
   - 명령어:
     ```
     mkdir -p ~/src/mgen_build
     cd ~/src/mgen_build
     ```

### **MGEN 설치**
1. **MGEN 클론**:
   - 명령어:
     ```
     cd ~/src/mgen_build  # 상위 디렉토리로 이동
     git clone https://github.com/pjhwa/mgen.git
     ```
   - 원소스: https://github.com/USNavalResearchLaboratory/mgen.git
   - 5.02c 버전에 SO_BROADCAST 호출 로직의 버그를 수정함

2. **빌드 디렉토리로 이동**:
   - 명령어:
     ```
     cd makefiles
     ```

3. **컴파일 실행**:
   - 이유: Makefile.linux는 Linux 환경(RHEL 포함)에 최적화됨.
   - 명령어:
     ```
     make -f Makefile.linux
     ```
   - 옵션 추가 (필요 시, Makefile 수정 또는 CFLAGS 설정):
     - HAVE_IPV6 활성화: `make -f Makefile.linux CFLAGS="-DHAVE_IPV6"`
     - HAVE_GPS: `make -f Makefile.linux CFLAGS="-DHAVE_GPS"`
     - RANDOM_FILL: `make -f Makefile.linux CFLAGS="-DRANDOM_FILL"`
   - 결과: mgen 바이너리 생성 (mgen 디렉토리에 생성됨).
   - 소요 시간: 1~5분.
 
4. **바이너리 설치**:
   - 이유: 시스템 PATH에 추가해 어디서나 실행 가능.
   - 명령어 (Makefile에 install 타겟 없으면 수동):
     ```
     sudo cp mgen /usr/local/bin/mgen  # mgen 바이너리 복사
     sudo chmod +x /usr/local/bin/mgen
     ```
    
### **추가 설정 및 테스트**
- **방화벽/SELinux**: 
  ```
  sudo firewall-cmd --add-port=5000-6000/udp --permanent  # MGEN 포트 허용
  sudo firewall-cmd --reload
  sudo setsebool -P nis_enabled 1  # 네트워크 도구 허용
  ```
- **테스트 실행**: 간단 스크립트로 확인.
  ```
  echo "0.0 ON 1 UDP DST 127.0.0.1/5000 PERIODIC [1 1024]" > test.mgn
  mgen input test.mgn output test_log.txt
  ```
- **문제 해결**: 로그 확인 `/var/log/messages`. IPv6 오류 시 HAVE_IPV6 옵션 비활성화. RHEL 8.4의 AppStream 리포지토리 활성화 확인.

**비판적 검증 요약**: 이 방법은 GitHub README 기반으로 사실적이지만, RHEL 8.4 특화되지 않아 추가 패키지(예: libpcap-devel) 필요할 수 있음. 오래된 코드로 보안 취약점 가능성 있으니, 프로덕션 아닌 테스트 환경 사용. 성공률 높지만, git submodule이 Protolib 포함 안 할 수 있으니 수동 배치 필수. NRL 문서(https://www.nrl.navy.mil/itd/ncs/products/mgen) 추가 참조 권장.

## 분석 자동화 스크립트 (Python 기반)

로그 파일을 파싱해 호스트별 대역폭, 지터, 손실률 계산. 정교하게 작성: 에러 핸들링, 평균/표준편차 계산, CSV 출력. mgen/tools 디렉토리에 있음.

```python
import re
import sys
import statistics
import csv
from datetime import datetime
from collections import defaultdict

def parse_mgen_log(log_file):
    """
    MGEN 로그 파일 파싱: RECV 이벤트 추출.
    반환: 리스트 of dicts {seq, sent_time, recv_time, size, latency}
    """
    recv_events = []
    with open(log_file, 'r') as f:
        for line in f:
            if 'RECV' in line and 'REPORT' not in line:  # REPORT 라인 제외
                match = re.search(r'(\d{2}:\d{2}:\d{2}\.\d+) RECV .*seq>(\d+) .*sent>(\d{2}:\d{2}:\d{2}\.\d+) size>(\d+)', line)
                if match:
                    recv_time_str, seq, sent_time_str, size = match.groups()
                    try:
                        recv_time = datetime.strptime(recv_time_str, '%H:%M:%S.%f')
                        sent_time = datetime.strptime(sent_time_str, '%H:%M:%S.%f')
                        latency = max(0, (recv_time - sent_time).total_seconds())  # 음수 latency를 0으로 클립
                        recv_events.append({
                            'seq': int(seq),
                            'sent_time': sent_time,
                            'recv_time': recv_time,
                            'size': int(size),
                            'latency': latency
                        })
                    except ValueError:
                        continue  # 타임스탬프 파싱 오류 스킵
    return recv_events

def analyze_metrics(events):
    """
    메트릭스 계산: throughput (Mbits/sec), jitter (ms), loss rate (%)
    """
    if not events:
        return {'throughput_mbits_sec': 0, 'jitter_ms': 0, 'loss_rate_percent': 100, 'avg_latency_ms': 0, 'transfer_bytes': 0, 'duration_sec': 0, 'lost_total': '0/0', 'pps': 0}

    # 중복 seq 제거를 위해 unique seq 사용
    unique_seqs = set(e['seq'] for e in events)
    min_seq, max_seq = min(unique_seqs), max(unique_seqs)
    expected_msgs = max_seq - min_seq + 1
    received_msgs = len(events)  # 전체 이벤트 수 (중복 포함)
    unique_received_msgs = len(unique_seqs)
    loss_rate = max(0, ((expected_msgs - unique_received_msgs) / expected_msgs) * 100 if expected_msgs else 100)  # unique 기반 loss, 음수 방지
    lost_total = f"{expected_msgs - unique_received_msgs}/{expected_msgs} ({loss_rate:.1f}%)"

    total_bytes = sum(e['size'] for e in events)
    start_time = min(e['recv_time'] for e in events)
    end_time = max(e['recv_time'] for e in events)
    duration = (end_time - start_time).total_seconds()
    throughput_mbits_sec = (total_bytes * 8 / 1_000_000) / duration if duration > 0 else 0  # Mbits/sec

    latencies = [e['latency'] * 1000 for e in events]  # ms 단위
    if any(l < 0 for l in latencies):
        print("Warning: Negative latency detected. Check NTP synchronization.")
    jitter = statistics.stdev(latencies) if len(latencies) > 1 else 0  # 표준편차로 지터
    avg_latency = statistics.mean(latencies) if latencies else 0

    pps = round(received_msgs / duration, 2) if duration > 0 else 0

    return {
        'throughput_mbits_sec': round(throughput_mbits_sec, 2),
        'jitter_ms': round(jitter, 3),
        'loss_rate_percent': round(loss_rate, 1),
        'avg_latency_ms': round(avg_latency, 3),
        'transfer_bytes': total_bytes,
        'duration_sec': round(duration, 1),
        'lost_total': lost_total,
        'pps': pps
    }

def print_iperf_like_table(host, metrics):
    """
    iperf-like 테이블 형식으로 콘솔 출력
    """
    print(f"[ ID] Interval Transfer Bandwidth Jitter Lost/Total Datagrams PPS")
    print(f"[ 1] 0.0-{metrics['duration_sec']} sec {metrics['transfer_bytes']/1_000_000:.2f} MBytes {metrics['throughput_mbits_sec']} Mbits/sec {metrics['jitter_ms']} ms {metrics['lost_total']} {metrics['pps']} pps")

def print_summary(all_metrics):
    """
    모든 호스트 메트릭스 요약: 평균, MIN, MAX 출력
    """
    if not all_metrics:
        print("Summary: No data available.")
        return
    # 각 메트릭스 리스트 추출
    throughputs = [m['throughput_mbits_sec'] for m in all_metrics]
    jitters = [m['jitter_ms'] for m in all_metrics]
    losses = [m['loss_rate_percent'] for m in all_metrics]
    latencies = [m['avg_latency_ms'] for m in all_metrics]
    pps_list = [m['pps'] for m in all_metrics]
    # 평균 계산
    avg_throughput = round(statistics.mean(throughputs), 2) if throughputs else 0
    avg_jitter = round(statistics.mean(jitters), 3) if jitters else 0
    avg_loss = round(statistics.mean(losses), 1) if losses else 0
    avg_latency = round(statistics.mean(latencies), 3) if latencies else 0
    avg_pps = round(statistics.mean(pps_list), 2) if pps_list else 0
    # MIN/MAX 계산
    min_throughput = round(min(throughputs), 2) if throughputs else 0
    max_throughput = round(max(throughputs), 2) if throughputs else 0
    min_jitter = round(min(jitters), 3) if jitters else 0
    max_jitter = round(max(jitters), 3) if jitters else 0
    min_loss = round(min(losses), 1) if losses else 0
    max_loss = round(max(losses), 1) if losses else 0
    min_latency = round(min(latencies), 3) if latencies else 0
    max_latency = round(max(latencies), 3) if latencies else 0
    min_pps = round(min(pps_list), 2) if pps_list else 0
    max_pps = round(max(pps_list), 2) if pps_list else 0
    print("\nSummary (Across all receivers):")
    print(f"Metric Average MIN MAX")
    print(f"Throughput (Mbits/sec) {avg_throughput:<12} {min_throughput:<12} {max_throughput}")
    print(f"Jitter (ms) {avg_jitter:<12} {min_jitter:<12} {max_jitter}")
    print(f"Loss Rate (%) {avg_loss:<12} {min_loss:<12} {max_loss}")
    print(f"Avg Latency (ms) {avg_latency:<12} {min_latency:<12} {max_latency}")
    print(f"PPS {avg_pps:<12} {min_pps:<12} {max_pps}")

def main(log_files, output_csv):
    """
    여러 로그 파일 분석 및 CSV 출력.
    log_files: 리스트 of 파일 경로 (e.g., ['host1_log.txt', 'host2_log.txt'])
    """
    all_metrics = []  # 모든 호스트 메트릭스 수집 리스트
    results = defaultdict(dict)
    with open(output_csv, 'w', newline='') as csvfile:
        writer = csv.DictWriter(csvfile, fieldnames=['host', 'throughput_mbits_sec', 'jitter_ms', 'loss_rate_percent', 'avg_latency_ms', 'pps'])
        writer.writeheader()
        for log in log_files:
            host = log.split('_')[0]  # 파일명에서 호스트 추출
            events = parse_mgen_log(log)
            metrics = analyze_metrics(events)
            metrics['host'] = host
            all_metrics.append(metrics)  # 요약용 리스트 추가
            writer.writerow({
                'host': host,
                'throughput_mbits_sec': metrics['throughput_mbits_sec'],
                'jitter_ms': metrics['jitter_ms'],
                'loss_rate_percent': metrics['loss_rate_percent'],
                'avg_latency_ms': metrics['avg_latency_ms'],
                'pps': metrics['pps']
            })
            print_iperf_like_table(host, metrics)  # iperf-like 출력 추가
    # 모든 분석 후 요약 출력
    print_summary(all_metrics)

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("사용법: python analyze_mgen.py log1.txt log2.txt ... output.csv")
        sys.exit(1)
    log_files = sys.argv[1:-1]
    output_csv = sys.argv[-1]
    main(log_files, output_csv)
```

- **사용법**: `python3 analyze_mgen.py receiver1_log.txt receiver2_log.txt output.csv`
- **출력 예시**:
```
root@k4:~# python3 analyze_mgen.py receiver_log3.txt receiver_log4.txt output.csv
[ ID] Interval       Transfer     Bandwidth       Jitter    Lost/Total Datagrams
[  1] 0.0-10.0 sec   10.24 MBytes  8.19 Mbits/sec  0.017 ms  0/10001 (0.0%)
[ ID] Interval       Transfer     Bandwidth       Jitter    Lost/Total Datagrams
[  1] 0.0-10.0 sec   10.24 MBytes  8.19 Mbits/sec  0.013 ms  0/10001 (0.0%)
```

- **설명**: RECV 이벤트 정규표현식 파싱, 메트릭스 계산 (throughput: 비트 단위, jitter: latency 표준편차, loss: seq 기반). 에러 핸들링: 빈 로그 시 기본값 반환. CSV 출력으로 분석 용이.
- **정교성 향상**: ANALYTICS 글로벌 사용 시 REPORT 이벤트 추가 파싱 가능 (loss/latency 내장). 대규모 로그: multiprocessing 추가 고려.
- **비판적 검증**: 스크립트는 로그 형식이 정확할 때 동작. tcpdump로 검증: `tcpdump -i eth0 udp port 5000 -w capture.pcap` 후 wireshark 분석.
