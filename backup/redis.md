# 11개 Timeout 사건 종합 분석표

## 표 1: 각 시점별 이벤트 매트릭스

| Timeout (KST) | UTC | cluster_wd stall | aof_slow_disk_io | sar vDisk await peak | LB 에러 | NSX BFD flap (확인) | 추정 책임 호스트 |
|---|---|---|---|---|---|---|---|
| 5/3 12:06 | 5/3 03:06 | 7s, 3 evt | — | (sar 5/3 미수집) | 없음 | 미확인 | pifpmd01? (5/3 R-lat 3.87) |
| 5/4 21:14 | 5/4 12:14 | 23s, 13 evt | — | (sar 5/4 미수집) | 없음 | 미확인 | pifpmd01 (5/4 R-lat 2.67) |
| 5/5 01:26 | 5/4 16:26 | 19s, 13 evt | — (REAR 백업 01:24 종료) | pifpmd02 16.8ms | 9건 | 미확인 | pifpmd02 (R-lat 3.6) |
| 5/5 05:38 | 5/4 20:38 | 22s, 19 evt | — | pifpmd01 15.2ms | 2건 | **★ 확인 (pifpmd01 호스트, 5개 TEP 동시 flap)** | **pifpmd01 (호스트 underlay 격리)** |
| 5/5 09:50 | 5/5 00:50 | 24s, 18 evt | — | pifpmd01 36ms (튐) | 1건 | 미확인 | 다중 추정 |
| 5/5 14:03 | 5/5 05:03 | 22s, 13 evt | **★ node:2 (14:02:43~14:03:13)** | pifpmd02 97.5ms | 6건 | 미확인 | pifpmd02 |
| 5/5 18:15 | 5/5 09:15 | 21s, 17 evt | — | pifpmd01 24.9ms | 4건 | 미확인 | pifpmd01 |
| 5/5 22:27 | 5/5 13:27 | 25s, 16 evt | **★ node:2 (22:27:12~22:27:42)** | pifpmd02 23.9ms | 5건 | 미확인 | pifpmd02 |
| 5/6 02:39 (missing) | 5/5 17:39 | 24s, 15 evt | — | pifpmd01 47.6ms | 1건 | 미확인 | pifpmd01 |
| 5/6 06:52 | 5/5 21:52 | 23s, 18 evt | — | pifpmd01 137ms (★최대) | 1건 | **★ 확인 (pifpmd03 호스트, 3개 TEP flap, "Neighbor Signaled Session Down")** | **pifpmd03 (호스트 underlay 격리)** |
| 5/6 11:05 | 5/6 02:05 | 14s, 9 evt | — | pifpmd02 52.8ms | 1건 | 미확인 | 다중 |
| 5/6 15:21 | 5/6 06:21 | 21s, 18 evt | — | pifpmd02 89.4ms | 없음 | 미확인 | pifpmd02 |

---

## 표 2: Layer별 신호 강도 (각 Layer가 timeout과 얼마나 일치하는가)

| Layer | 11/11 timeout 매칭? | 매칭 강도 | 진원지 가능성 |
|---|---|---|---|
| **NSX overlay BFD flap** (ESXi vmkernel) | **2/2 검증된 건은 ★완벽 매칭** | **Very High** | **★★★ 진원지 후보 1순위** |
| **cluster_wd 통신 timeout** (Redis Enterprise) | **11/11 완벽 매칭** | **Very High** | 증상 (BFD flap의 결과) |
| sar vDisk await spike (pifpmd01/02) | 10/11 매칭 (5/3 미수집) | High | **증상** (NAS/datastore I/O가 BFD flap 시 동시 saturate) |
| LB Datapath connection failure | 9/11 매칭 (5/3, 5/6 15:21 0건) | Moderate | 증상 |
| aof_slow_disk_io (Redis) | 2/11 매칭 (14:03, 22:27만) | Low | 우연 동시 발생 (별개 메커니즘) |
| dmcproxy "Connection reset" | 0/11 (상시 발생) | None | Background noise, 무관 |
| OS journal (kernel/oom/io error) | 0/11 | None | 완전 정상 |
| NetApp NFS I/O (NFS call/s) | 0/11 (NFS call 0.17/s 일정) | None | 완전 무관 |
| Redis master shard 로그 | 0/11 (4/11 이후 침묵) | None | 완전 무관 |

---

## 표 3: 노드/호스트별 영향 비대칭성

| 측정 | node:1 (pifpmd01) | node:2 (pifpmd02) | node:3 (pifpmd03) |
|---|---|---|---|
| ESXi 호스트 | cn05-ss107-krw2 | cn08-ss106-krw2 | cn11-ss101-krw2 |
| Master shard | redis:22 (slot 0-5460) | redis:26 (slot 10923-16383) | redis:24 (slot 5461-10922) |
| Slave shard | redis:25 | redis:23 | redis:27 |
| AOF rewrite 횟수 | 23 | 38 | **55** (가장 활발) |
| sar vDisk await spike (5/5-5/6) | 매번 2~137ms | 매번 6~97ms | **항상 ≤1.4ms** |
| sar Read Latency (NSX 보고) | 0.13~4.73ms | 0.27~8.0ms | **0.067~0.13ms** |
| OS journal 5월 비정상 키워드 | 일부 (REAR, aof events) | 0 | 0 |
| cluster_wd reporter→target 합계 | →node:3 70건, →node:2 0건 | →node:3 76건, →node:1 0건 | →node:1 60건, →node:2 57건 |
| BFD flap 확인 | **★ 5/5 05:38 (다중 TEP flap)** | 미확인 | **★ 5/6 06:52 (다중 TEP flap)** |

**핵심 비대칭**: pifpmd03만 storage I/O latency가 깨끗 → ESXi 호스트(cn11-ss101-krw2)의 datastore가 다른 두 호스트보다 우수하거나, noisy neighbor 영향이 적음. 그러나 **NSX overlay BFD 단절은 모든 호스트에서 발생** — 호스트별 underlay 차이는 별 문제가 안 됨.

---

## 표 4: 각 layer별 Confidence 등급화

| 결론 | Confidence | 근거 |
|---|---|---|
| 11개 timeout 모두 cluster_wd 통신 정지로 직접 매칭 | **Very High** | 11/11, 평균 21초 stall |
| 252분 정확한 주기성 (5/4 21:13 락온 후) | **Very High** | std deviation 1.5분 |
| 진정한 원인은 NSX-T overlay BFD flap | **High** | 2/2 확인된 시각에서 정확 매칭, 나머지 9건은 vmkernel.log 추가 검증 필요 |
| 트리거는 underlay network 또는 NSX 측 정기 작업 | **Moderate-High** | 252분 주기는 cron의 일반적 단위가 아님, NSX/underlay 정기 작업 추정 |
| storage I/O는 진원지 아님 (증상일 뿐) | **High** | NFS 0.17/s 일정, OS journal 깨끗, aof_slow_disk_io는 2건만 |
| Redis 자체 결함 아님 | **Very High** | master shard 로그 4월부터 침묵, 정상 운영 |
| Lettuce timeout 3S는 가시화 임계 (원인 아님) | **Very High** | stall이 ~21초이므로 3초든 30초든 stall 동안 명령 실패 |
| node:3 (pifpmd03)가 단독 진원지 | **부인** (이전 분석 정정) | 확인된 BFD flap에 pifpmd01, pifpmd03 양 호스트 모두 등장 |

---

## 표 5: 각 시점별 인과 사슬 추정

| Timeout | 1차 트리거 | 2차 영향 | 3차 결과 (timeout) |
|---|---|---|---|
| 5/3 12:06 | NSX BFD flap (추정, 7초 짧음 — 첫 발생) | 단일 노드 일시 격리 | 1건 timeout |
| 5/4 21:14 | NSX BFD flap (252분 락온 시작) | 다중 노드 격리 시작 | 1건 timeout |
| 5/5 01:26 | NSX BFD flap **+ REAR mkbackup 후폭풍** (01:24 종료, page cache flush) | pifpmd01 디스크 부하 + 네트워크 stall 동시 | 1건 timeout (이중 증폭) |
| 5/5 05:38 | **★ NSX BFD flap 확인 (pifpmd01 호스트 5 TEP)** | pifpmd01 격리, master:redis-22 응답 정지 | 1건 timeout |
| 5/5 09:50 | NSX BFD flap (추정) | pifpmd01 vDisk 36ms | 1건 timeout |
| 5/5 14:03 | NSX BFD flap (추정) **+ node:2 AOF fsync stall 우연 동시** | pifpmd02 격리 + 디스크 stall | 1건 timeout (가장 강력 증폭) |
| 5/5 18:15 | NSX BFD flap (추정) | pifpmd01 vDisk 24ms | 1건 timeout |
| 5/5 22:27 | NSX BFD flap (추정) **+ node:2 AOF fsync stall 우연 동시** | pifpmd02 격리 + 디스크 stall | 1건 timeout (이중) |
| 5/6 02:39 | NSX BFD flap (추정) | pifpmd01 vDisk 47ms | **사용자 알림 누락** |
| 5/6 06:52 | **★ NSX BFD flap 확인 (pifpmd03 호스트, "Neighbor Signaled Session Down")** | pifpmd03 격리, master:redis-24 응답 정지, **pifpmd01 vDisk 137ms (cascading)** | 1건 timeout |
| 5/6 11:05 | NSX BFD flap (추정), 짧은 stall (14s, 9 evt) | 일시 격리 | 1건 timeout |
| 5/6 15:21 | NSX BFD flap (추정) | pifpmd02 vDisk 89ms | 1건 timeout |

---

## 핵심 통찰 5가지

### 1. **AOF fsync stall과 client timeout은 별개 메커니즘**
- `aof_slow_disk_io`는 11건 중 2건(14:03, 22:27)만 우연히 동시 발생
- 5/5 12:15~12:48에는 30분간 다발성 aof_slow_disk_io 발생했지만 사용자 알림 0건 → **AOF stall ≠ timeout**
- **이유**: master는 `aof_enabled:0` (AOF 사용 안 함), AOF는 slave에서만. client는 master만 보므로 AOF stall이 직접 timeout 일으키지 않음

### 2. **storage layer는 진원지가 아니라 동반 증상**
- BFD flap 시각에 **vDisk await도 동시에 spike** → underlay network/datastore 백본의 **공통 saturation**
- pifpmd03가 항상 깨끗한 이유 = 호스트(cn11-ss101)의 datastore가 우수 또는 noisy neighbor 적음. 그러나 **BFD flap에는 동등하게 영향 받음** (5/6 06:52)
- 사용자 ESXi 분석의 "5/4 tx drop 증가, CSTOP 4/27 증가"도 같은 underlay 문제의 증상

### 3. **252분 주기 = 4시간 12분 = NSX 또는 underlay의 정기 작업**
- cron의 자연 단위(5/10/15/30/60분)가 아님 → application/시스템의 시작-기준 상대 타이머
- NSX edge HA failback timer, route refresh, BFD config sync, security policy reload 가능성
- **NSX 4.2.3에서 BFD probe 짧은 default가 underlay jitter에 민감하게 반응**하는 것이 증폭 요인

### 4. **cluster_wd 비대칭 패턴은 reporter 편향 효과**
- 이전 분석에서 "node:3 reporter 절반"으로 봤으나, 이는 cluster_wd가 RTT 가장 긴 페어를 더 자주 fail로 판정한 결과일 수 있음
- 실제 BFD 단절은 **호스트별 다른 시각에 발생** (5/5 05:38=pifpmd01, 5/6 06:52=pifpmd03)
- **cluster_wd는 stall의 결과를 보여줄 뿐, 어느 호스트가 진원인지는 vmkernel BFD 로그가 결정**

### 5. **Lettuce 3초 timeout은 진원이 아니라 가시화 임계값**
- BFD flap이 ~3~10초 → 3초 timeout이면 즉시 노출, 30초면 일부 회복
- timeout 늘리는 것은 **사용자 가시 횟수만 줄임**, 근본 stall은 그대로
- 동시에: **pool 8개 → 32개 상향, retry/circuit breaker는 의미 있음** (in-flight 명령 영향 최소화)

---

## 즉시 실행 가능한 조치

| 우선순위 | 조치 | 예상 효과 |
|---|---|---|
| 1 | nsx vmkernel.log 추가 검증 (위 표의 9개 미확인 UTC 시각) | 가설 100% 확정 |
| 2 | NSX BFD multiplier 3 → 5~7 상향 | underlay jitter 둔감화, BFD flap 빈도 감소 |
| 3 | NSX 측 252분 주기 정기 작업 식별 (NSX manager log, edge node task log) | 진정한 트리거 식별 |
| 4 | underlay network 측 점검 (ToR 스위치, NSX TEP VLAN) | 진정한 트리거 식별 |
| 5 | Lettuce timeout 3S → 30S, pool 8 → 32, retry/CB 추가 | 사용자 영향 완화 |
| 6 | (참고) Redis cluster_wd timeout 상향 | cluster topology 흔들림 감소 |

근본 해결은 1~4번. 5~6번은 사용자 영향 완화용 임시책.



---
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
