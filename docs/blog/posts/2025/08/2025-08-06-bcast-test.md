---
title: "Broadcast 성능 테스트 방안"
date: 2025-08-06
tags: [cloud, network, performance, test, broadcast, ostinato]
---

# Broadcast 성능 테스트 방안

Ostinato에 별도의 CLI 명령어(예: ostinato --broadcast)는 없지만, Python 스크립트를 CLI에서 실행하여 Broadcast 패킷 생성/전송/측정이 가능합니다. 이는 RHEL 8.4 같은 서버 환경에서 자동화에 유용하며, Sender VM 1개에서 Broadcast를 보내 Receiver VM 9개(호스트 3대, Placement Group 활용)에서 분석할 수 있습니다. 아래는 RHEL 8.4 기준 단계별 가이드입니다. 2025년 기준으로 Ostinato v1.3과 Python 3.6+ (RHEL 8.4 기본)를 사용합니다.

## 1. 준비: Ostinato와 Python API 설치 (RHEL 8.4)
Ostinato의 Drone(트래픽 생성 에이전트)을 설치하고 Python API를 활성화하세요. CLI 테스트는 Drone을 백그라운드에서 실행하고 Python 스크립트로 제어합니다.

- **시스템 업데이트 및 의존성 설치**:
  ```bash
  sudo dnf update -y
  sudo dnf install epel-release -y
  sudo dnf install qt5-qtbase-devel qt5-qtmultimedia-devel libpcap-devel protobuf-devel protobuf-compiler gcc gcc-c++ make cmake git python3-pip -y
  ```

- **Ostinato 소스 빌드 및 설치** (GitHub에서 최신 v1.3):
  ```bash
  git clone https://github.com/pstavirs/ostinato.git
  cd ostinato
  mkdir build && cd build
  cmake ..
  make -j$(nproc)
  sudo make install
  ```

- **Python API 설치** (pip로 python-ostinato 패키지):
  ```bash
  sudo pip3 install python-ostinato
  export PYTHONPATH=$PYTHONPATH:/usr/local/lib/python3.6/site-packages/ostinato  # RHEL 8.4 Python 경로 맞춤, 필요 시 영구 설정: ~/.bashrc 추가
  ```

- **Drone 실행** (트래픽 생성 서버, 백그라운드 CLI 모드):
  ```bash
  sudo drone &  # 포트 7878 리스닝, 방화벽 허용: sudo firewall-cmd --add-port=7878/tcp --permanent; sudo firewall-cmd --reload
  ```
  Drone은 CLI에서 독립 실행되며, Python 스크립트가 API로 연결합니다.

## 2. 기본 개념: Python API로 Broadcast 테스트
Python API는 protobuf 기반으로 패킷 구조를 정의합니다. Broadcast는 Ethernet 레이어(MAC FF:FF:FF:FF:FF:FF) 또는 IP 레이어(255.255.255.255)에서 설정합니다. 스크립트는 example.py를 기반으로 하며, 포트 선택 → 스트림 생성 → 전송 → 통계 수집 순서입니다. PPS(rate), 패킷 수, 크기를 제어하세요.

- **예시 스크립트 구조**:
  - Drone 연결 (localhost:7878).
  - 포트 선택 (eth0 등).
  - 스트림 생성: 프로토콜 스택(Ethernet + IP + UDP) + Broadcast 주소.
  - Rate 설정: PPS 1000 (초당 1000 패킷, 부하 조절).
  - 전송 및 캡처.
  - 통계 출력: Tx/Rx 패킷, throughput, loss %.

## 3. Broadcast 테스트 스크립트 예시 (CLI 실행)
아래 스크립트를 파일로 저장(broadcast_test.py)한 후 CLI에서 `python3 broadcast_test.py`로 실행하세요. 이는 UDP Broadcast 패킷을 생성. Ethernet MAC Broadcast와 IP Broadcast를 결합했습니다.

```python
import time
from ostinato.core import ost_pb
from ostinato.protocols.mac_pb2 import Mac
from ostinato.protocols.ethernet_pb2 import Ethernet
from ostinato.protocols.ip4_pb2 import Ip4
from ostinato.protocols.udp_pb2 import Udp
from ostinato.protocols.payload_pb2 import Payload

# Drone 연결 (localhost:7878)
drone = ost_pb.DroneProxy('127.0.0.1', 7878)
drone.connect()

# 포트 목록 가져오기 (eth0 가정, 실제 인터페이스 확인: drone.getPortIdList())
port_list = drone.getPortIdList()
port_id = port_list.port_id[0]  # 첫 번째 포트 (eth0)

# 포트 구성 가져오기 및 스트림 생성
port_config = drone.getPortConfig(port_id)
stream_id_list = ost_pb.StreamIdList()
stream_id_list.port_id.CopyFrom(port_id)
stream_id_list.stream_id.add().id = 1  # 스트림 ID 1

# 스트림 프로토콜 스택 정의: Ethernet (Broadcast MAC) + IP (Broadcast IP) + UDP + Payload
stream = ost_pb.Stream()
stream.core.name = 'Broadcast Test Stream'
stream.core.is_enabled = True
stream.control.packets = 10000  # 전송 패킷 수 (테스트 시간 제어)
stream.control.mode = ost_pb.StreamControl.e_sm_fixed  # 고정 패킷 수 모드
stream.control.rate.pps = 1000  # PPS 1000 (부하: 100 PPS부터 증가 추천)

# 프로토콜 추가
eth = stream.protocol.add()
eth.protocol_id.id = ost_pb.Protocol.k_ethernet
eth.Ethernet.dst_mac = 0xFFFFFFFFFFFF  # Broadcast MAC: FF:FF:FF:FF:FF:FF
eth.Ethernet.src_mac = 0x001122334455  # 소스 MAC (VM MAC 맞춤)

ip = stream.protocol.add()
ip.protocol_id.id = ost_pb.Protocol.k_ip4
ip.Ip4.dst_ip = 0xFFFFFFFF  # Broadcast IP: 255.255.255.255
ip.Ip4.src_ip = 0xC0A80101  # 소스 IP (192.168.1.1 예시)

udp = stream.protocol.add()
udp.protocol_id.id = ost_pb.Protocol.k_udp
udp.Udp.src_port = 1234
udp.Udp.dst_port = 5678

payload = stream.protocol.add()
payload.protocol_id.id = ost_pb.Protocol.k_payload
payload.Payload.pattern_mode = ost_pb.Payload.e_pp_fixed
payload.Payload.pattern = b'Test Broadcast Data'  # 페이로드 데이터

# 스트림 추가 및 저장
drone.addStream(stream_id_list, stream)
drone.saveStreamConfig(port_id)

# 통계 초기화
drone.clearStats(port_id)

# 전송 시작
drone.startTransmit(port_id)
time.sleep(10)  # 10초 대기 (패킷 전송 시간, 조절)
drone.stopTransmit(port_id)

# 통계 가져오기 및 출력
stats = drone.getStats(port_id)
print(f"Tx Packets: {stats.tx_pkts}")
print(f"Rx Packets: {stats.rx_pkts}")
print(f"Packet Loss %: {(stats.tx_pkts - stats.rx_pkts) / stats.tx_pkts * 100 if stats.tx_pkts > 0 else 0}")
print(f"Tx Rate (bps): {stats.tx_rate_bit_rate}")
print(f"Rx Rate (bps): {stats.rx_rate_bit_rate}")

# 연결 종료
drone.disconnect()
```

- **실행 방법** (CLI에서):
  ```bash
  python3 broadcast_test.py
  ```
  - 출력 예: Tx Packets: 10000, Rx Packets: 9990, Packet Loss %: 0.1, Tx Rate: 8000000 bps (환경에 따라 다름).
  - 팁: 서브넷 Broadcast(예: 192.168.1.255)로 변경 시 ip.Ip4.dst_ip = 0xC0A801FF.

## 4. 테스트 수행 및 분석
- **Sender VM (CLI에서 스크립트 실행)**: 위 스크립트로 Broadcast 생성. PPS 증가로 네트워크 포화 테스트.
- **Receiver VM (분석)**: Receiver VM 9개에서 tcpdump CLI로 캡처: `tcpdump -i eth0 -nn broadcast -w broadcast.pcap -c 10000`. 분석: `tshark -r broadcast.pcap -qz io,stat,1` (throughput, loss 계산).
- **고급 옵션**: 스크립트에 캡처 추가 (drone.startCapture(port_id), drone.stopCapture(port_id), drone.getCaptureBuffer(port_id)로 pcap 저장). IGMP v2 지원 시 udp.Udp.dst_port를 IGMP 포트로 변경.
- **문제 해결**: 연결 오류 시 Drone IP 확인 (127.0.0.1 대신 VM IP). 패킷 손실 높으면 Placement Group 또는 IGMP Querier 설정 점검.

## 각 수신 측 서버에서 대역폭, 지터, 손실률 분석 구현 방법
CSP 환경의 네트워크 엔지니어로서, Ostinato를 사용한 Broadcast 트래픽 테스트에서 각 수신 측 서버(Receiver VM 9개, 호스트 3대에 Placement Group 활용)에서 대역폭(throughput, bps 단위), 지터(jitter, ms 단위), 손실률(packet loss, lost/total datagrams %)을 분석하는 방법을 설명하겠습니다. 이는 SCP v2 PP VPC의 L2 Broadcast 케이스(SCP M-Route 미구성 L2)나 OVN의 Multicast flood(IGMP Snooping disable 시 모든 포트로 Broadcast 처리)에서 유용하며, AWS TGW Multicast 비교(Subnet 간 L3 미지원 환경)에도 적용 가능합니다. Ostinato는 Python API를 통해 CLI 기반으로 이러한 지표를 수집할 수 있으며, 각 Receiver VM에서 개별적으로 실행하여 중앙 집중 분석(예: 로그 수집 스크립트)할 수 있습니다.

분석 원리:
- **대역폭(Throughput)**: Rx rate (bps) 직접 측정. Ostinato stats에서 rx_rate_bit_rate를 가져옴.
- **손실률(Packet Loss)**: Tx packets vs Rx packets 비교 (lost = tx_pkts - rx_pkts, % = (lost / tx_pkts) * 100). Sender와 Receiver 간 공유 필요 (예: Sender에서 tx_pkts 로그).
- **지터(Jitter)**: Latency 변동으로 계산. Ostinato는 TimingTag (TTAG) 프로토콜을 추가해 소프트웨어 타임스탬프 기반 latency 측정, 이를 바탕으로 jitter 계산 (평균 latency 차이). TTAG는 5초마다 삽입되어 비용 효과적.
- RHEL 8.4 호환: 이전 설치 가이드(Ostinato 소스 빌드 + python-ostinato pip) 사용. 각 Receiver VM에서 Drone 실행 후 Python 스크립트로 분석.

테스트 구성도 추가 팁: Sender VM 1개 → Broadcast 전송, 각 Receiver VM에서 Drone + 스크립트 실행 → 로그 중앙 서버로 전송 (SCP v2 OpenStack 기반이므로 rsync/scp 사용).

### 1. 준비: 각 Receiver VM에서 Ostinato 설정
- **Drone 실행** (트래픽 수신 에이전트, CLI 백그라운드):
  ```bash
  sudo drone &  # 포트 7878 리스닝, 방화벽 허용: sudo firewall-cmd --add-port=7878/tcp --permanent; sudo firewall-cmd --reload
  ```
- **Sender 측 수정**: Broadcast 스트림에 TTAG 추가 (Python API에서 stream.protocol.add()로 TimingTag 프로토콜 삽입, 이전 스크립트 예시 확장). TTAG는 TX 타임스탬프 삽입, RX에서 파싱.

### 2. Python API 스크립트로 구현 (각 Receiver에서 실행)
각 Receiver VM에서 아래 스크립트를 파일(receiver_analysis.py)로 저장 후 `python3 receiver_analysis.py` 실행. 이는 Drone 연결 → 캡처 시작 → 통계 수집 → 계산을 자동화합니다. TTAG 기반 jitter/latency를 위해 캡처 버퍼 파싱 추가 (Ostinato v1.3 이상, 2025년 기준 지원).

```python
import time
import statistics  # Jitter 계산용
from ostinato.core import ost_pb
from ostinato.protocols.mac_pb2 import Mac  # 필요 프로토콜 import (확장 가능)

# Drone 연결 (localhost:7878, 각 VM 로컬)
drone = ost_pb.DroneProxy('127.0.0.1', 7878)
drone.connect()

# 포트 ID 가져오기 (eth0 가정)
port_list = drone.getPortIdList()
port_id = port_list.port_id[0]  # 첫 번째 포트

# 캡처 시작 (Broadcast 필터 적용)
drone.startCapture(port_id)
time.sleep(60)  # 테스트 시간 (Sender 전송 시간과 동기화, 60초)
drone.stopCapture(port_id)

# 캡처 버퍼 가져오기 및 저장 (pcap 형식, TTAG 파싱용)
capture_buffer = drone.getCaptureBuffer(port_id)
with open('broadcast_capture.pcap', 'wb') as f:
    f.write(capture_buffer)

# 통계 가져오기
drone.clearStats(port_id)  # 초기화 (옵션)
time.sleep(1)  # 지연
stats = drone.getStats(port_id)

# 대역폭 (Throughput): Rx rate bps
throughput_bps = stats.rx_rate_bit_rate
print(f"Throughput (bps): {throughput_bps}")

# 손실률: Tx 값 Sender로부터 공유 가정 (예: 로그 파일, 실제로는 Sender 스크립트에서 tx_pkts 추출)
tx_pkts = 10000  # Sender tx_pkts 예시 (동기화 필요, 공유 스크립트로 자동화)
rx_pkts = stats.rx_pkts
lost_pkts = tx_pkts - rx_pkts
loss_percent = (lost_pkts / tx_pkts * 100) if tx_pkts > 0 else 0
print(f"Packet Loss (%): {loss_percent} (Lost/Total: {lost_pkts}/{tx_pkts})")

# 지터/Jitter: TTAG 기반 latency 데이터로부터 계산 (캡처 파싱 예시, 실제 TTAG 타임스탬프 추출)
# TTAG 파싱: Wireshark/tshark 통합 또는 custom (여기 간단 예시, latency 리스트 가정)
latencies = []  # TTAG RX-TX diff 리스트 (ms 단위, tshark로 추출)
# 예: tshark -r broadcast_capture.pcap -Y "ostinato.ttag" -T fields -e frame.time_delta >> latencies.txt
# 파일 읽기 및 계산 (실제 구현 시 tshark 호출 subprocess)
# 가정: latencies = [0.5, 0.6, 0.4, 0.7]  # ms
jitter_ms = statistics.stdev(latencies) if len(latencies) > 1 else 0  # 표준편차로 jitter
print(f"Jitter (ms): {jitter_ms}")

# 연결 종료
drone.disconnect()
```

- **실행 및 출력 예**: 각 VM에서 스크립트 실행 → 로그 파일 저장 (e.g., redirect > analysis_log.txt). 출력: Throughput (bps): 8000000, Packet Loss (%): 0.1 (Lost/Total: 10/10000), Jitter (ms): 0.2.
- **TTAG/Jitter 상세**: Sender 스트림에 TimingTag 프로토콜 추가 (stream.protocol.add().protocol_id.id = ost_pb.Protocol.k_timing_tag). RX에서 캡처 버퍼 파싱으로 TX/RX 타임스탬프 diff 계산 (per-stream 평균 latency → jitter as stdev). OVN flood 시 호스트별 jitter 증가 관찰.

### 3. 자동화 및 중앙 분석
- **Tx 값 공유**: Sender 스크립트에서 tx_pkts를 파일로 저장 → Receiver로 전송 (rsync 또는 공유 스토리지, SCP v2 OpenStack 기반 활용).
- **tshark 통합 (Jitter 세밀화)**: 스크립트에 subprocess 추가:
  ```python
  import subprocess
  latencies = []
  result = subprocess.run(['tshark', '-r', 'broadcast_capture.pcap', '-Y', 'ostinato.ttag', '-T', 'fields', '-e', 'frame.time_delta'], capture_output=True)
  for line in result.stdout.decode().splitlines():
      if line.strip():
          latencies.append(float(line.strip()))
  jitter_ms = statistics.stdev(latencies) if len(latencies) > 1 else 0
  ```
- **9개 VM 중앙화**: 각 Receiver에서 로그를 중앙 서버로 보내 집계 (bash 루프 스크립트). L2/L3 케이스별 평균 계산.

### 4. 주의사항 및 최적화
- **IGMP 영향**: SCP v2 IGMP v2 지원 시 Broadcast flood 제한, 지터 증가 가능. IGMP Querier 설정으로 안정화.
- **성능**: 고부하(PPS 1000+) 시 VM CPU 확인 (Placement Group으로 latency 최소화).
- **대안**: iperf v2로 전환 시 -u -i 옵션으로 jitter/loss 직접 출력, but Broadcast workaround 필요.
