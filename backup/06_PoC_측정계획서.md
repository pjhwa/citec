# 백신 도입 PoC 측정 계획서 (Proof of Concept)

| 항목 | 내용 |
|------|------|
| 문서번호 | SCPv2-SEC-POC-2026-006 |
| 버전 | v0.1 |
| 작성일 | 2026-04-15 |
| 목적 | SCPv2 컴퓨트 노드 백신 도입 시 성능·안정성 영향 정량 측정 |
| 일정 | 2026-04-19 환경 구축 ~ 2026-04-25 결과 보고 |
| 산출물 | PoC 결과 보고서 (운영정책서 v1.0 확정 근거) |

---

## 1. 목적

CSAP 9.1.4-③ 대응을 위한 컴퓨트 노드 백신 설치가 OpenStack KVM 가상화 워크로드에 미치는 정량적 영향을 측정하고, **실시간 스캔 비활성화 결정의 정당성을 데이터로 입증**한다.

### 1.1 검증 가설
| 가설 | 내용 |
|------|------|
| H1 | 실시간 스캔 활성화 시 VM I/O 성능이 유의미하게 저하된다 |
| H2 | 실시간 스캔 활성화 시 라이브 마이그레이션 성공률 또는 시간이 악화된다 |
| H3 | 디렉터리·프로세스 예외 처리 시 H1·H2의 영향이 합격기준 이내로 감소한다 |
| H4 | 예약 스캔(전체 노드)은 야간 저부하 시간대에 합격기준 이내로 완료 가능하다 |

---

## 2. PoC 환경

### 2.1 하드웨어
- 컴퓨트 노드 2대 (운영 동일 사양)
- 컨트롤러 노드 1대
- Ceph 또는 NFS 공유 스토리지 (라이브 마이그레이션 검증용)
- 네트워크: 운영과 동일한 분리 구성 (관리/데이터/스토리지)

### 2.2 소프트웨어
- Ubuntu LTS (운영과 동일 버전)
- OpenStack (운영과 동일 버전, 예: Antelope/Bobcat)
- libvirt + QEMU/KVM (운영과 동일)
- 백신: 후보 솔루션 (V3 Net for Linux Server / TrendMicro DSAS / ViRobot Server 중 1~2종)

### 2.3 테스트 VM
- 게스트 OS: Ubuntu 22.04 / CentOS 9 / Windows Server 2022 각 1대
- 사양: 4 vCPU, 8GB RAM, 100GB qcow2 디스크
- 부하 도구 사전 설치: fio, iperf3, sysbench

---

## 3. 측정 시나리오 매트릭스

다음 4가지 환경에서 동일 부하 테스트를 반복하여 비교한다.

| 환경 | 백신 설치 | 실시간 스캔 | 예외 처리 | 비고 |
|------|:--------:|:----------:|:---------:|------|
| **E0 — Baseline** | × | × | - | 백신 없음 (대조군) |
| **E1 — RT On / NoExclude** | ○ | ON | × | 최악 시나리오 |
| **E2 — RT On / Excluded** | ○ | ON | ○ | 정책서 §5 예외 적용 |
| **E3 — Scheduled Only (운영 정책)** | ○ | OFF | ○ | **본 정책 권장 운영방식** |

각 환경에서 각 시나리오 3회 반복 측정 후 평균값 사용 (변동성 확인 위해 표준편차도 기록).

---

## 4. 측정 시나리오 상세

### 4.1 [S1] VM 디스크 I/O 성능 (fio)

**목적**: 백신 실시간 스캔이 qcow2 이미지 I/O에 미치는 영향 측정

**테스트 명령** (게스트 내부에서 실행):
```bash
# 4K Random Write IOPS
fio --name=randwrite --ioengine=libaio --iodepth=32 \
    --rw=randwrite --bs=4k --direct=1 --size=4G \
    --numjobs=4 --runtime=120 --group_reporting

# 4K Random Read IOPS
fio --name=randread --ioengine=libaio --iodepth=32 \
    --rw=randread --bs=4k --direct=1 --size=4G \
    --numjobs=4 --runtime=120 --group_reporting

# Sequential Write Throughput
fio --name=seqwrite --ioengine=libaio --iodepth=8 \
    --rw=write --bs=1M --direct=1 --size=8G \
    --numjobs=2 --runtime=120 --group_reporting

# Sequential Read Throughput
fio --name=seqread --ioengine=libaio --iodepth=8 \
    --rw=read --bs=1M --direct=1 --size=8G \
    --numjobs=2 --runtime=120 --group_reporting
```

**기록 지표**:
- IOPS (4K randwrite, randread)
- Throughput (1M seqwrite, seqread, MB/s)
- Latency p50, p95, p99 (μs)
- 호스트 측 iowait, steal time (sar로 동시 수집)

**합격 기준** (E0 대비):
| 환경 | 4K randwrite IOPS | latency p99 | 결과 판정 |
|------|:-----------------:|:-----------:|:---------:|
| E1 | - | - | (참고용 — 통과 불요) |
| E2 | ≥ E0의 90% | ≤ E0의 120% | 합격 |
| **E3** | **≥ E0의 95%** | **≤ E0의 110%** | **반드시 합격** |

---

### 4.2 [S2] VM 네트워크 처리량 (iperf3)

**목적**: 백신 네트워크 모듈이 트래픽에 미치는 영향 (해당 시)

**테스트**:
```bash
# 호스트 → VM
iperf3 -c <vm_ip> -t 60 -P 4

# VM → VM (동일 노드)
iperf3 -c <vm2_ip> -t 60 -P 4

# VM → VM (다른 노드, 라이브 마이그레이션 동일 경로)
iperf3 -c <vm_other_node_ip> -t 60 -P 4
```

**기록 지표**: 평균 throughput (Gbps), retransmits 수

**합격 기준 (E3)**: E0 대비 95% 이상

---

### 4.3 [S3] VM CPU 성능 (sysbench)

**테스트** (게스트 내부):
```bash
sysbench cpu --cpu-max-prime=20000 --threads=4 run
sysbench memory --memory-block-size=1K --memory-total-size=10G --threads=4 run
```

**기록 지표**: events/sec, throughput (MB/s)

**합격 기준 (E3)**: E0 대비 98% 이상 (CPU는 백신 영향이 가장 작아야 함)

---

### 4.4 [S4] 라이브 마이그레이션 (가장 중요)

**목적**: 백신이 라이브 마이그레이션 성공률과 소요시간에 미치는 영향

**테스트 절차**:
```bash
# 부하 인가 상태에서 마이그레이션 (스트레스 시나리오)
# 1) VM 게스트에서 stress-ng로 메모리·CPU 부하
ssh ubuntu@<vm_ip> "stress-ng --vm 2 --vm-bytes 4G --timeout 600s &"

# 2) 시작 시간 기록 후 마이그레이션
START=$(date +%s.%N)
openstack server migrate --live-migration --wait <vm_id>
END=$(date +%s.%N)
echo "Migration time: $(echo $END - $START | bc) sec"

# 3) 결과 확인
openstack server show <vm_id> -c OS-EXT-SRV-ATTR:host
```

**반복**: 각 환경별 10회 (성공률 통계 확보)

**기록 지표**:
- 성공률 (성공 횟수 / 전체)
- 평균 소요 시간 (초)
- p95 소요 시간 (초)
- 마이그레이션 중 게스트 다운타임 (ping loss 측정)

**합격 기준**:
| 환경 | 성공률 | 평균 소요시간 | 결과 판정 |
|------|:------:|:------------:|:---------:|
| E1 | - | - | (참고용) |
| E2 | ≥ 95% | E0 대비 +30% 이내 | 합격 |
| **E3** | **≥ 99%** | **E0 대비 +10% 이내** | **반드시 합격** |

---

### 4.5 [S5] VM 부팅 시간

**목적**: 인스턴스 launch 시간에 미치는 영향

**테스트**:
```bash
# 표준 이미지로 VM 생성 후 SSH 접속 가능 시점까지 측정
START=$(date +%s)
openstack server create --image ubuntu-22.04 --flavor m1.small \
  --network internal --key-name test --wait test-vm
# 게스트 부팅 완료 대기
while ! ssh -o ConnectTimeout=2 ubuntu@<ip> "uptime" 2>/dev/null; do sleep 1; done
END=$(date +%s)
echo "Boot time: $((END-START)) sec"
```

**합격 기준 (E3)**: E0 대비 +10% 이내

---

### 4.6 [S6] 예약 스캔 영향 (E3 환경 전용)

**목적**: 운영 정책의 예약 스캔이 야간 저부하 시점에 합격기준 내 완료되는지 검증

**테스트 절차**:
1. 노드에 30개 VM 배포 (운영 평균 밀도 가정)
2. 각 VM에 평균적 부하 인가 (idle 70%, light I/O 30%)
3. 예약 스캔 실행
4. 다음 측정:
   - 스캔 소요 시간 (전체 노드 스캔)
   - 스캔 중 호스트 평균 CPU/메모리/iowait
   - 스캔 중 VM의 fio 4K randread 성능 변동
   - 스캔 중 라이브 마이그레이션 1회 시도 (성공 여부)

**합격 기준**:
- 스캔 완료 시간: < 6시간 (야간 시간대 내 완료)
- 호스트 iowait 증가: < +15%p
- VM I/O 성능 저하: < 30% (스캔 중)
- 라이브 마이그레이션 성공: 가능

---

### 4.7 [S7] 호스트 리소스 사용량 (백그라운드 측정)

모든 시나리오 진행 중 다음을 5초 간격으로 수집:

```bash
# CPU/메모리/iowait
sar -u -r -b 5 > host_metrics_${ENV}_${SCENARIO}.log &

# 백신 프로세스 자원 사용
top -b -d 5 -p $(pgrep -d, <vendor-daemon>) > av_proc_${ENV}_${SCENARIO}.log &
```

---

## 5. 측정 데이터 수집 양식

### 5.1 Master Sheet (예시)

| 시나리오 | 환경 | 시도# | 측정값 | 단위 | 비고 |
|----------|:----:|:-----:|:------:|:----:|------|
| S1-randwrite | E0 | 1 | 12,500 | IOPS | |
| S1-randwrite | E0 | 2 | 12,300 | IOPS | |
| S1-randwrite | E0 | 3 | 12,600 | IOPS | |
| S1-randwrite | **E0 평균** | - | **12,467** | **IOPS** | **σ=153** |
| S1-randwrite | E1 | 1 | 6,200 | IOPS | 실시간 스캔 영향 |
| ... | ... | ... | ... | ... | ... |

### 5.2 결과 요약표 (보고서용)

| 시나리오 | E0 (Baseline) | E1 (RT On / NoExc) | E2 (RT On / Exc) | **E3 (정책 권장)** | 합격 |
|----------|:-------------:|:------------------:|:----------------:|:-----------------:|:----:|
| S1 4K randwrite IOPS | 12,467 | _____ (_%) | _____ (_%) | _____ (**_%**) | ☐ |
| S1 4K randread IOPS | _____ | _____ (_%) | _____ (_%) | _____ (**_%**) | ☐ |
| S1 latency p99 (μs) | _____ | _____ | _____ | _____ | ☐ |
| S2 throughput (Gbps) | _____ | _____ (_%) | _____ (_%) | _____ (**_%**) | ☐ |
| S3 CPU events/sec | _____ | _____ (_%) | _____ (_%) | _____ (**_%**) | ☐ |
| S4 마이그레이션 성공률 | _____ | _____ | _____ | _____ | ☐ |
| S4 마이그레이션 평균시간(초) | _____ | _____ | _____ | _____ | ☐ |
| S5 부팅 시간(초) | _____ | _____ | _____ | _____ | ☐ |
| S6 야간 예약스캔 완료시간(시간) | - | - | - | _____ | ☐ |

---

## 6. 종합 합격 기준 및 의사결정

### 6.1 합격 조건
- E3 환경의 모든 합격 기준 통과 시 → **운영정책서의 §3~5 정책 확정**
- E3에서 일부 미통과 항목 발생 시 → 예외 정책 보강 후 재측정

### 6.2 불합격 시 대응
| 항목 미통과 | 대응 |
|------------|------|
| S1 (디스크 I/O) | 예외 경로 추가, I/O 스케줄링 클래스 idle 강제 |
| S4 (마이그레이션) | 백신 솔루션 변경 검토, 또는 마이그레이션 시 일시 중지 정책 추가 |
| S6 (예약 스캔) | 노드 시차 확대, 부분 스캔 분할, 스캔 빈도 조정 |

---

## 7. 보고서 산출 양식

PoC 종료 후 5일 이내 다음 산출물을 작성:

1. **PoC 결과 보고서 (PDF)** — 임원 보고용 10페이지 이내
   - 요약 (1페이지)
   - 환경 및 방법 (2페이지)
   - 결과 (5페이지, §5.2 결과 요약표 + 그래프)
   - 결론 및 권고 (2페이지)

2. **상세 측정 데이터 (xlsx)** — 모든 raw 데이터, 계산식, 통계
3. **호스트/백신 자원 사용 그래프** — 시계열 시각화 (Grafana 캡처)
4. **사례 로그** — 마이그레이션 성공/실패 케이스별 로그 보존

---

## 8. PoC 일정 (Gantt)

| 일자 | 활동 | 담당 |
|------|------|------|
| 4/19 | 환경 구축 (하드웨어, OS, OpenStack 설치) | CI-TEC |
| 4/20 | 베이스라인(E0) 측정 | CI-TEC |
| 4/21 | 백신 설치 + E1 (RT On / NoExc) 측정 | CI-TEC |
| 4/22 | 예외 정책 적용 + E2 측정 | CI-TEC |
| 4/23 | 실시간 스캔 OFF + E3 측정 | CI-TEC |
| 4/24 | S6 예약 스캔 영향 측정 | CI-TEC |
| 4/25 | 데이터 정리, 보고서 작성, 운영정책서 v1.0 반영 | CI-TEC |

---

## 9. 리스크 및 가정

| 리스크 | 대응 |
|--------|------|
| PoC 환경이 운영과 사양 차이 | 동일 사양 노드 확보, 차이 발생 시 보고서 명시 |
| 백신 솔루션 일정 지연 | 후보 2종 병행 준비, 1종이라도 측정 가능하면 진행 |
| 측정 변동성으로 합격 판단 어려움 | 시도 횟수 증가, 통계 분석(t-test 등)으로 유의성 확인 |
| 라이브 마이그레이션 자체 실패 빈도 | 베이스라인에서도 실패하면 환경 문제 → CI-TEC 디버깅 |

---

## 10. 변경 이력

| 버전 | 일자 | 변경 내역 | 작성자 |
|------|------|----------|--------|
| v0.1 | 2026-04-15 | 최초 작성 | CI-TEC |
