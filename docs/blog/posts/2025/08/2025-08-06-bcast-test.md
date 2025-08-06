---
title: "Broadcast 성능 테스트 방안"
date: 2025-08-06
tags: [cloud, network, performance, test, broadcast, ostinato]
---

# Broadcast 성능 테스트 방안

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
0.0 ON 1 UDP DST 255.255.255.255/5000 PERIODIC [10 1024]  # 10 packets/sec, 1024 bytes each (중부하 예시)
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
  - 예상: Throughput ~80 Kbps, Loss <5%, Jitter 1~5ms.
- **고부하**: 높은 rate/large size. 네트워크 포화로 손실/지터 증가.
  - PERIODIC [100 8192] (100 packets/sec, 8192 bytes, UDP max size).
  - 예상: Throughput ~6 Mbps, Loss >10%, Jitter >10ms.
- 각 케이스별 30초~1분 실행, 3회 반복 측정 (평균값 사용). 부하 증가 시 네트워크 하드웨어(스위치 등) 한계를 검증.

비판적 검증: 고부하에서 broadcast는 네트워크 스톰 유발 가능. tcpdump로 트래픽 캡처해 MGEN 로그와 교차 검증. NTP로 호스트 시계 동기화 (latency 정확도 향상).

## RHEL 8.4 기반 설치 및 테스트 방법

RHEL 8.4에서 MGEN 설치/실행:
1. **의존성 설치**: 기본 라이브러리 필요 (문서 10. Compile options 참조).
   - 명령어: `sudo dnf install gcc gcc-c++ make libpcap-devel` (HAVE_PCAP 옵션용, 필수 아님).
   - IPv6 지원: `sudo dnf install libipv6-devel` (HAVE_IPV6 옵션).

2. **MGEN 다운로드 및 컴파일**:
   - NRL 사이트(https://www.nrl.navy.mil/itd/ncs/products/mgen)에서 최신 버전(5.02 이상) 다운로드 (mgen-5.02.tar.gz).
   - 압축 해제: `tar -xvf mgen-5.02.tar.gz`
   - 컴파일: `cd mgen-5.02/protolib; make unix` (protolib 먼저 빌드).
     - MGEN 빌드: `cd ../mgen; make unix` (UNIX 옵션으로 RHEL 지원).
     - 옵션 추가: Makefile에서 HAVE_IPV6, RANDOM_FILL 등 활성화 (broadcast 테스트에 불필요하지만, RANDOM_FILL로 페이로드 랜덤화 가능).
   - 설치: `sudo make install` (기본 /usr/local/bin/mgen).

3. **테스트 환경 설정**:
   - 방화벽: `sudo firewall-cmd --add-port=5000/udp --permanent; sudo firewall-cmd --reload` (포트 5000 UDP 허용).
   - SELinux: `sudo setsebool -P nis_enabled 1` (필요 시, 네트워크 도구 허용).
   - NTP 동기: `sudo dnf install chrony; sudo systemctl enable chronyd` (latency 측정 정확도).
   - 여러 호스트: SSH 키 공유로 원격 실행/로그 수집 자동화.

4. **실행 및 디버그**:
   - `mgen --version`으로 확인.
   - 로그: /var/log/messages에서 오류 확인.
   - 문제: Windows-Mac 상호작용 이슈(11.1) 없음 (RHEL 기반). 버퍼 크기(11.2)는 TX/RXBUFFER로 설정.

## 분석 자동화 스크립트 (Python 기반)

로그 파일을 파싱해 호스트별 대역폭, 지터, 손실률 계산. 정교하게 작성: 에러 핸들링, 평균/표준편차 계산, CSV 출력.

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
            if 'RECV' in line:
                # 예: 01:17:01.983235 RECV proto>UDP flow>1 seq>1 src>127.0.0.1/5000 dst>127.0.0.1/5000 sent>01:17:01.983000 size>1024 latency>0.000235
                match = re.search(r'(\d{2}:\d{2}:\d{2}\.\d+) RECV .*seq>(\d+) .*sent>(\d{2}:\d{2}:\d{2}\.\d+) size>(\d+) latency>(\d+\.\d+)', line)
                if match:
                    recv_time_str, seq, sent_time_str, size, latency = match.groups()
                    recv_time = datetime.strptime(recv_time_str, '%H:%M:%S.%f')
                    sent_time = datetime.strptime(sent_time_str, '%H:%M:%S.%f')
                    recv_events.append({
                        'seq': int(seq),
                        'sent_time': sent_time,
                        'recv_time': recv_time,
                        'size': int(size),
                        'latency': float(latency)
                    })
    return recv_events

def analyze_metrics(events):
    """
    메트릭스 계산: throughput (kbps), jitter (ms), loss rate (%)
    """
    if not events:
        return {'throughput': 0, 'jitter': 0, 'loss': 100}

    seqs = [e['seq'] for e in events]
    min_seq, max_seq = min(seqs), max(seqs)
    expected_msgs = max_seq - min_seq + 1
    received_msgs = len(events)
    loss_rate = ((expected_msgs - received_msgs) / expected_msgs) * 100 if expected_msgs else 100

    total_bytes = sum(e['size'] for e in events)
    start_time = min(e['recv_time'] for e in events)
    end_time = max(e['recv_time'] for e in events)
    duration = (end_time - start_time).total_seconds()
    throughput = (total_bytes * 8 / 1024) / duration if duration > 0 else 0  # kbps

    latencies = [e['latency'] * 1000 for e in events]  # ms 단위
    jitter = statistics.stdev(latencies) if len(latencies) > 1 else 0  # 표준편차로 지터

    return {
        'throughput_kbps': round(throughput, 2),
        'jitter_ms': round(jitter, 2),
        'loss_rate_percent': round(loss_rate, 2),
        'avg_latency_ms': round(statistics.mean(latencies), 2) if latencies else 0
    }

def main(log_files, output_csv):
    """
    여러 로그 파일 분석 및 CSV 출력.
    log_files: 리스트 of 파일 경로 (e.g., ['host1_log.txt', 'host2_log.txt'])
    """
    results = defaultdict(dict)
    with open(output_csv, 'w', newline='') as csvfile:
        writer = csv.DictWriter(csvfile, fieldnames=['host', 'throughput_kbps', 'jitter_ms', 'loss_rate_percent', 'avg_latency_ms'])
        writer.writeheader()

        for log in log_files:
            host = log.split('_')[0]  # 파일명에서 호스트 추출 (e.g., receiver1_log.txt -> receiver1)
            events = parse_mgen_log(log)
            metrics = analyze_metrics(events)
            metrics['host'] = host
            writer.writerow(metrics)
            print(f"{host} 분석: {metrics}")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("사용법: python analyze_mgen.py log1.txt log2.txt ... output.csv")
        sys.exit(1)
    log_files = sys.argv[1:-1]
    output_csv = sys.argv[-1]
    main(log_files, output_csv)
```

- **사용법**: `python analyze_mgen.py receiver1_log.txt receiver2_log.txt output.csv`
- **설명**: RECV 이벤트 정규표현식 파싱, 메트릭스 계산 (throughput: 비트 단위, jitter: latency 표준편차, loss: seq 기반). 에러 핸들링: 빈 로그 시 기본값 반환. CSV 출력으로 분석 용이.
- **정교성 향상**: ANALYTICS 글로벌 사용 시 REPORT 이벤트 추가 파싱 가능 (loss/latency 내장). 대규모 로그: multiprocessing 추가 고려.
- **비판적 검증**: 스크립트는 로그 형식이 정확할 때 동작. tcpdump로 검증: `tcpdump -i eth0 udp port 5000 -w capture.pcap` 후 wireshark 분석.
