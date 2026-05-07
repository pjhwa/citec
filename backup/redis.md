### 종합 매칭 표

| Timeout | Node | iowait peak | DEV await max | NFS call/s |
|---|---|---|---|---|
| 5/5 01:26 | 01 / 02 / **03** | 0.34/0.53/**0.04**% | 8.4 / 16.8 / **0.8** ms | 0.17 / 0.17 / 0.17 |
| 5/5 05:38 | 01 / 02 / **03** | 0.45/0.33/**0.02**% | 15.2 / 10.1 / **0.9** ms | 0.17 / 0.17 / 0.18 |
| 5/5 09:50 | 01 / 02 / **03** | 0.15/0.17/**0.02**% | **36.0** / 6.7 / **0.8** ms | 0.17 / 0.16 / 0.17 |
| 5/5 14:03 | 01 / 02 / **03** | 0.66/1.17/**0.02**% | 19.4 / **97.5** / **0.8** ms | 0.17 / 0.18 / 0.17 |
| 5/5 18:15 | 01 / 02 / **03** | 0.45/0.21/**0.02**% | 24.9 / 13.0 / **0.7** ms | 0.17 / 0.17 / 0.17 |
| 5/5 22:27 | 01 / 02 / **03** | 0.52/1.49/**0.02**% | 16.9 / 23.9 / **0.9** ms | 0.18 / 0.16 / 0.17 |
| 5/6 02:39 | 01 / 02 / **03** | 0.47/1.08/**0.02**% | 47.6 / 33.6 / **0.8** ms | 0.17 / 0.17 / 0.17 |
| 5/6 06:52 | 01 / 02 / **03** | 0.31/0.52/**0.03**% | **137.7** / 17.4 / **1.0** ms | 0.17 / 0.17 / 0.17 |
| 5/6 11:05 | 01 / 02 / **03** | 0.12/0.70/**0.02**% | 10.0 / **52.8** / **1.4** ms | 0.17 / 0.18 / 0.18 |
| 5/6 15:21 | 01 / 02 / **03** | 0.27/1.36/**0.02**% | 24.3 / **89.4** / **1.3** ms | 0.17 / 0.17 / 0.16 |

10건 중 10건에서 **pifpmd01 또는 pifpmd02의 vDisk await가 폭증**, **pifpmd03는 일관되게 안정**. 5/6 02:39(missing 건)도 동일 패턴 — 이전 분석에서 추정만 했던 사건이 sar로도 정확히 검증됐다.

### 정정 #1: NetApp NAS는 진원이 아니다

**`NFS call/s = 0.17`(=6초당 1번 호출)** 모든 노드/시각에 동일. 한마디로 **NAS는 idle**. retrans/s 0. 즉:
- NSX 보고서가 명시한 `198.19.212.50:/fs_pifpmd_dataa_bak_y34ky3` 마운트는 **단순 백업/덤프 파일용**이고, **Redis 데이터/AOF/RDB 경로가 아니다**.
- 이전 분석에서 MetroCluster NVRAM mirror, SVM-mc, dedup schedule을 의심한 부분은 **모두 무관**으로 정정.

### 정정 #2: 진짜 진원은 ESXi datastore의 vDisk(VMDK) latency

stall이 일어나는 디바이스는 **로컬 SCSI 디바이스**(`dev8-0/dev8-48/dev253-X` 계열). 이는 VMDK virtual disk이고, backend는 ESXi datastore다.

증거:
- sar의 vDisk await 폭증과 **ESXi 분석의 "datastore Read Latency"·"vDisk total latency" spike가 같은 것을 측정**
- NSX 분석의 "pifpmd01/02 storage Read Latency 증가"는 datastore latency를 가리키는 것이 맞다
- 3노드 모두 **같은 NetApp NAS를 마운트하지만 거의 안 쓰고**, **ESXi 호스트는 서로 다름** (01: cn05-ss107-krw2, 02: cn08-ss106-krw2, 03: cn11-ss101-krw2)

→ **stall은 datastore backend에서 발생**. 03번이 깨끗한 것은 다른 ESXi 호스트의 datastore이거나, datastore가 같더라도 다른 VM의 noisy neighbor 영향에서 비교적 자유롭다는 뜻.

### 정정 #3: dev253-9 등 “거의 idle한 디바이스의 작은 write가 매번 매우 느림” 패턴

**작은 write 단발성(<0.5 tps, <2 KB/s)인데 await 15~140ms**. 이는 **ESXi/datastore 단의 transient queue stall**의 전형적 시그니처. 호스트 OS는 정상이고 vSCSI virtual queue가 가끔 lock-up되는 상태. SAN/datastore 측 latency p99 spike와 일치.

### iowait spike가 작은 이유

대부분 0.1~1.5%. 8 vCPU 시스템에서 1.5%는 약 0.12 core가 I/O wait. 즉 **시스템 전체가 막힌 게 아니라 특정 프로세스(=Redis Enterprise)만 fsync로 막힘**. 다른 프로세스는 영향 없음. journal에서 OS 단 비정상이 0건이었던 것과 일치.

### 252분 주기에 대한 갱신된 가설

vDisk write 패턴은 **상시 일정**(dev8-48: 4~5 tps, 100~200 KB/s 안정). 트래픽이 252분 주기로 spike하는 게 아니다. **stall만 252분에 발생**.

이는 두 가지 중 하나를 강하게 시사:

1. **Redis Enterprise 내부 작업이 252분 주기로 큰 write를 시도** → 그 큰 write가 stall에 걸림
   - 5/6 11:06~07에 pifpmd01의 dev8-0 wkB/s가 평소 30 KB/s에서 **5,570 KB/s로 180배 폭증** — AOF rewrite 또는 RDB snapshot 시그니처. **이 시점이 11:05 timeout 직후이므로 timeout으로 stall된 write가 다음 분에 한꺼번에 풀린 것일 수 있음**.
   - 비슷하게 5/5 01:23~01:25 pifpmd01의 dev8-16 wkB/s가 9000~12000 KB/s — 이건 REAR mkbackup 시점과 일치
2. **ESXi datastore 측 정기 작업(VM snapshot, replication, dedup, scrub)** 이 252분 주기로 spike

**가설 1을 강하게 지지**하는 추가 단서: 모든 timeout 시각의 정확히 다음 분(timeout +1분)에 pifpmd01/02의 dev8-0 또는 dev8-48 write가 평소보다 큼. 이는 stall된 write가 풀려서 한꺼번에 flush 되는 것.

## 갱신된 최종 결론 (Confidence 명시)

### 인과 사슬 (정정판)

```
Redis Enterprise master shard가 252분 주기로 큰 write 작업
   (BGREWRITEAOF / RDB snapshot — 추정)
   ↓
ESXi datastore vSCSI queue / backend SAN latency가 saturate
   (작은 write조차 await 수십~수백ms)
   ↓
Redis fsync 정지 (everysec 정책 가정 시 1초 임계 초과)
   → event_log: aof_slow_disk_io throttle
   ↓
master shard의 모든 명령 응답 정지 (수~수십초)
   ↓
LB가 backend 응답 못 받음
   ↓
Lettuce 3초 timeout → application redis-timeout 알림
```

### Confidence 표 (전체 갱신)

| 결론 | Confidence | 핵심 근거 |
|---|---|---|
| stall은 ESXi datastore vDisk layer | **Very High** | 10/10 매칭, NFS 0.17/s 일관, sar+ESXi 보고서 일치 |
| NetApp NAS는 무관 | **Very High** | NFS call/s 0.17, retrans 0 |
| pifpmd03는 stall 없음 | **Very High** | 모든 시각 await<1.5ms, iowait<0.05% |
| 252분 트리거는 Redis 내부의 정기 작업 | **Moderate-High** | timeout +1분에 large write flush 패턴 |
| stall은 OS 위 layer (fsync stall, 시스템 멈춤 아님) | **Very High** | iowait <2%, OS journal 깨끗 |
| Lettuce 3S timeout은 가시화 임계, 근본 원인 아님 | **High** | stall이 30~수초이므로 timeout 늘려도 stall 자체 안 사라짐 |
| MetroCluster NVRAM mirror 의심 | **부인** | NFS 사용량이 0이라 NAS layer 무관 |

### 다음 단계 권장 (정정된 우선순위)

1. **ESXi datastore 단 점검** — 가장 중요
   - pifpmd01(cn05-ss107-krw2) datastore와 pifpmd02(cn08-ss106-krw2) datastore가 같은 SAN/aggregate인지 확인
   - 5/5 14:00~14:05, 22:25~22:30 datastore latency p99(esxtop / vROPS)
   - 같은 datastore 위 noisy neighbor VM (대량 vMotion, 대용량 snapshot, backup VM)
   - HBA queue depth, multipathing 상태
   - 만약 vSAN이면 cache disk 상태, slab/segment cleanup schedule

2. **Redis Enterprise persistence 정책 확인**
   - `rladmin info db <id>`: persistence type, AOF policy
   - `/var/opt/redislabs/log/redis_<uid>.log`에서 `Background AOF rewrite started/finished` 시각이 timeout과 일치하는지 (5/5 14:00~14:05, 22:25~22:30)
   - **AOF rewrite 시점이 252분 주기와 일치하면 가설 확정**

3. **Redis Enterprise master shard 위치**
   - `rladmin status databases extra all` — master shard가 어느 노드에 있는지
   - master shard가 pifpmd01/02에만 있으면 timeout이 3번 영향 안 받는 이유 자동 설명
   - master shard가 분산되어 있으면 추가 분석 필요

4. **NSX 보고팀과 NetApp 보고팀에 정정 공유**
   - sar의 NFS metric을 보여주고 NAS layer가 진원이 아님을 설명
   - 점검 자원을 ESXi datastore / VMDK backend로 redirect

5. **Workaround (근본 해결 아님)**
   - Lettuce `timeout: 3S → 30S`, `pool.maxActive: 8 → 32`
   - Resilience4j retry/circuit breaker
   - **임시로 pifpmd03 만 master shard로 끌어오기 가능하면**(ras `rladmin migrate ... target_node 3`) 증상 사라질지 검증 — 진단용

근본 해결은 1번(ESXi datastore 점검)과 2번(Redis persistence 정책 확인)에서 나온다. 특히 **AOF 또는 RDB snapshot 위치를 로컬 NVMe(vDisk가 아닌 host pass-through 또는 별도 datastore)**로 옮기거나, datastore backend의 latency 문제를 해결해야 한다.
