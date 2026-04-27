# NextMosaic Cluster DB Failover (2026-04-22) — 통합 RCA 보고서

> 내부 분석본(DBfailover원인분석석), Grok 분석, Gemini 분석을 교차 검증하고  
> 로그·벤더 문서에 근거한 사실(Ground Truth)과 추론을 분리하여 작성한 통합 보고서.

---

## 0. 한 줄 결론

> **Storage micro-burst(NetApp Flexvol 50 Large Block Write)는 트리거의 일부일 뿐, 단독으로 SBD majority lost(5초 heartbeat fail)를 설명하지 못한다. 진짜 근본 원인은 "만성 iSCSI SBD 네트워크 불안정성"과 "60초 OCF resource monitor timeout의 보수적 설정"의 결합이며, 4/22에 storage burst가 chronic instability를 임계점 이상으로 밀어올린 것으로 판단된다. 두 외부 분석(Grok, Gemini)은 핵심 사실 누락(QDevice 미인지)과 데이터로 반증되는 비약(VMXNET3 RX Ring 고갈, DRBD Protocol C 가산 latency)을 포함한다.**

---

## 1. 검증 가능한 사실 (Ground Truth)

### 1.1 시스템 구성 (원본 line 174, 178 근거)
- RHEL 8.10, Pacemaker 2.1.0
- SBD: iSCSI 기반 3개 servant (pcmk + iSCSI device × 2), target IP 198.19.19.168, 198.19.57.168
- DRBD: 양 노드 cross-storage replication (001=iscsi01-is361-krw1, 002=iscsi01-is501-krw3+iscsi02-is501-krw3)
- **QDevice(net ffsplit) — 이미 구성 완료**
- 클러스터 properties: `no-quorum-policy=suicide`, `stonith-enabled=true`, `have-watchdog=true`
- SBD fencing delay: `pcmk_delay_base=5`, `pcmk_delay_max=15` 이미 설정됨

### 1.2 측정된 성능 데이터

| 항목 | 값 | 출처 |
|------|----|----|
| Flexvol 50 응답 peak (07:01) | 6ms (평소 1~2ms) | 원본 line 405-407 |
| Flexvol 50 워크로드 | Large Block Write >300MB/s 연속 | 원본 line 433 |
| vmnic2 packet drop 율 | 0.0000326% (9,423 / 28.9B) | 원본 line 485 |
| vmnic5 packet drop 율 | 0.000187% (53,740 / 28.8B) | 원본 line 486 |
| vmnic2/5 allocRxBuffFailed | **0** (모든 24개 RX 큐) | 원본 line 516-539, 611-634 |
| vmnic2 TxXoff (cumulative) | 11,575 | 원본 line 567 |
| vmnic5 TxXoff (cumulative) | **391,997** | 원본 line 662 |
| vNIC RX ring (current) | 1024 (max 4096) | 원본 line 569-581 |
| 25GbE 사용률 | 10% 이하 | 원본 line 422 |
| Storage CPU | 평균 80% 이하 | 원본 line 415 |
| NetApp performance archive 보관 | 24~26일 (목표 미달) | 원본 line 342, 359 |

### 1.3 SBD/Pacemaker 이벤트 (UTC = KST-9)

| 시각 (KST) | 이벤트 |
|-----------|-------|
| 07:01:00 경 | Flexvol 50 Large Block Write burst 시작 |
| 07:05:58 | DB Insert 28,933ms 지연 (shared hit 16, read 2) |
| 07:07 | mysbd 통신 이슈 (정상화) |
| 07:15:15~07:15:32 | SBD 11회 majority lost (pcmk age:5, iSCSI×2 age:4) |
| 07:17:49 | 마지막 정상 pgsys health check 인증 |
| 07:17:56 | OCF Filesystem/pgsql resource monitor 60s timeout 도달 → DB 강제 abort |
| 07:18:14 | PostgreSQL 완전 down |
| 07:19:23 | STONITH → VM hard reset (vmware.log "CPU reset: hard") |
| 07:19:31~07:20:07 | Pacemaker policy engine, DRBD promote on 002, HA-GROUP migrate |
| 07:20:08 | 002에서 PostgreSQL 16.8 listening 시작 (서비스 정상화) |

### 1.4 만성 패턴
- 3~4월: SBD outdated 30+회 (대부분 회복)
- 4/22: 17초 동안 11회 집중 (단일 날짜 최고치)
- **4/13: CDP 백업 정책 변경 시 "파일시스템 응답없음 → DB restart" 동일 패턴 발생**

---

## 2. 세 분석 자료 교차 검증

### 2.1 평가 매트릭스

| 항목 | 원본 (DBfailover...) | Grok | Gemini |
|------|---------------------|------|--------|
| QDevice 인식 | ✅ | ❌ "3-node 검토" 권고 | ❌ "QDevice 도입" 권고 |
| pcmk_delay 기존 설정 인식 | ✅ | ⚠️ 일부 인식하면서도 25~30 상향 권고 | ⚠️ 동일 (25~30) |
| Flexvol 50 / Back-to-Back CP | ✅ 정확 | ✅ 인용 | ✅ 인용 + NVRAM 고갈 추론 |
| VMXNET3 RX Ring 고갈 | — (언급 없음) | ⚠️ rx drop 가볍게 | ❌ **단정** (allocRxBuffFailed=0으로 반증) |
| DRBD 영향 | ⚠️ 분석 누락 | ✅ "직접 원인 아님" | ❌ Protocol C 단정 + 가산 latency 핵심 촉매 |
| 6ms↔SBD 5초 인과관계 검증 | ❌ | ❌ 단정 | ❌ 단정 |
| Cross-storage DRBD 인식 | ✅ (002 측 데이터스토어 명시) | ❌ | ❌ |
| 4/13 CDP 변경 단서 추적 | ⚠️ 언급만 | ⚠️ 1줄 인용 | ⚠️ 1줄 인용 |
| Q3 timeout 권고값 | — | 90~120s / 120s (합리) | 90~120s / 120s (합리) |
| Q4 max 미감지 시간 | — | 150s (정확) | 150s (정확, 계산 상세) |
| TxXoff 391997 해석 | ❌ 무시 | ❌ 무시 | ❌ 무시 |
| NetApp archive 부족 인식 | ⚠️ 메시지 보였지만 권고 안함 | ⚠️ "30일 확보" 권고 | ❌ "30일 확보" 권고 |

### 2.2 두 외부 분석에 공통된 비약 4가지

#### 비약 #1 — QDevice 미인지 (Critical)
- **두 분석 모두 "QDevice 도입 / 3-node 전환"을 제안**
- 사실: 원본 line 174에 "**QDevice(net ffsplit) 구성됨**" 명시
- 의미: 두 외부 분석이 원본 자료를 정독하지 않았거나, 핵심 정보를 놓쳤음

#### 비약 #2 — VMXNET3 RX Ring Buffer Exhaustion 단정 (Gemini)
- 주장: "RX Ring 고갈 → iSCSI packet drop → mysbd 통신 이슈 유발"
- 반증: 24개 RX 큐 모두 `allocRxBuffFailed=0` (line 516-539, 611-634)
- 실제 drop 율은 0.0000326%~0.000187%로 **백그라운드 노이즈 수준**
- 결론: VMXNET3 RX Ring 고갈은 **데이터로 반증됨**

#### 비약 #3 — DRBD Protocol C 가산 latency 단정 (Gemini)
- 주장: "Protocol C로 양쪽 disk latency가 합산되어 disk await 증폭"
- 반증 1: 원본에 DRBD Protocol 설정 명시되지 않음 (Gemini의 추론)
- 반증 2: 양 노드가 **서로 다른 NetApp 클러스터** 사용. 002로 failover 후 즉시 정상화 → standby 측 storage는 정상이었음. Protocol C라면 Active의 burst가 Standby에도 영향을 주었어야 하는데, 002의 sbd outdated/error 흔적 없음

#### 비약 #4 — Storage 6ms peak가 SBD 5초 heartbeat fail의 직접 원인이라는 인과관계
- 주장 (Grok+Gemini): "Back-to-Back CP → iSCSI 지연 → SBD majority lost"
- 반증 1: **6ms ≪ 5,000ms** — 단일 I/O latency가 SBD watchdog 5초 timeout을 직접 유발할 수 없음
- 반증 2: SBD 디바이스의 iSCSI target은 **별도 IP(198.19.x.x)** — 데이터 LUN(SWN-CN-V**)과 다른 경로. Flexvol 50의 latency가 SBD 경로에 직접 전달된다는 증거 없음
- 의미: 6ms peak는 "동일 시간대 발생한 또 다른 증상"일 뿐, SBD majority lost와 **다른 root cause를 공유**할 가능성 ("storage stack과 iSCSI fabric 자체의 동시 불안정")

### 2.3 원본 분석의 강점
- QDevice 등 시스템 구성 정확
- Cross-storage 사실 식별
- SBD majority lost = Pacemaker 위임 메커니즘 정확
- 만성 패턴 정량화 (3월 3회 / 4/1 5회 / 4/22 11회)

### 2.4 원본 분석의 약점
- DRBD 영향 분석 부재
- 6ms↔SBD 5s 인과관계 검증 안 함
- TxXoff 391997 (vmnic5) 해석 누락
- 4/13 CDP 변경 후 누적 효과 추적 부재

---

## 3. 통합 근본 원인 분석

### 3.1 확정 가능한 인과 사슬

```
[Layer 1: Trigger]
    07:01 NetApp Flexvol 50 Large Block Write 300MB/s+
    → Back-to-Back CP 발생 (NetApp KB 근거)
    → 데이터 LUN의 응답시간 1~2ms → 6ms peak

[Layer 2: Chronic Vulnerability]
    iSCSI SBD 경로 (198.19.x.x) 만성 불안정성
    → 3~4월 30+회 outdated (warning만)
    → 4/22에 storage stack 동시 부하로 임계점 초과

[Layer 3: SBD]
    07:15:15~32 SBD 3개 servant 모두 outdated (pcmk age:5, iSCSI×2 age:4)
    → "Majority of devices lost - surviving on pacemaker"
    → SBD가 fencing 권한을 Pacemaker에 위임

[Layer 4: OCF Resource]
    07:17:49~07:17:56 Filesystem/pgsql resource monitor (60s timeout)
    → 60초 내 응답 실패 (root cause: 디스크 I/O 지연)
    → on-fail=fence 트리거

[Layer 5: STONITH]
    pacemaker-controld S_IDLE → S_POLICY_ENGINE
    07:19:23 VM hard reset (vmware.log "CPU reset: hard")
    07:19:31~07:20:07 DRBD promote on 002, HA-GROUP migrate

[Recovery]
    07:20:08 PostgreSQL on 002 listening (총 다운타임 ~2분 12초)
```

### 3.2 미해결 의문점 (추가 데이터 필요)

| # | 의문 | 가설 | 검증 방법 |
|---|------|-----|----------|
| Q1 | 4/22에만 chronic이 임계점을 넘은 이유? | 4/13 CDP 변경 후 누적 부하 + 4/22 특정 워크로드 | CDP 백업 LUN 추적, 4/22 07:00경 추가 워크로드 확인 |
| Q2 | TxXoff 391997 (vmnic5)의 의미? | 호스트 RX buffer 자주 포화 → noisy neighbor | esxtop %DRPRX/%DRPTX 시계열 |
| Q3 | iSCSI 198.19.x.x 경로의 5초 단절 원인? | L2/L3 경로상 ARP/STP/MTU/MSS 또는 vmk port-binding 이슈 | vmnic↔vmk10/vmk11↔NetApp LIF 추적 |
| Q4 | DRBD가 cross-storage replication인데, 한쪽 storage burst가 어떻게 전체 영향? | Protocol 미상. C라면 동기 → 영향 / A라면 무영향 | drbdadm status, /etc/drbd.d/*.res 확인 |
| Q5 | 6ms peak는 SBD heartbeat 5초와 어떻게 연결되는가? | 직접 연결 안 됨 (반증). 별도 root cause 가능성 | SBD iSCSI LIF의 4/22 07:15 packet/RTT 데이터 |

### 3.3 비약 없이 말할 수 있는 것 vs 추론

**확실 (로그/벤더 문서 근거)**:
- ✅ Storage Flexvol 50의 Back-to-Back CP 발생
- ✅ SBD 11회 majority lost (07:15:15~32, 17초 윈도우)
- ✅ OCF resource monitor 60s timeout 발동 → fence
- ✅ QDevice 구성됨, no-quorum-policy=suicide + stonith=true 동작
- ✅ 만성 iSCSI SBD 불안정 (3~4월 30+회)
- ✅ 4/22 다운타임 약 2분 12초

**합리적 추론 (근거는 있으나 직접 증거 없음)**:
- ⚠️ Flexvol 50 burst가 "전체 storage 컨트롤러 stress"로 SBD 경로에 간접 영향
- ⚠️ CDP 정책 변경 후 누적 부하가 임계점 도달
- ⚠️ vmnic5 TxXoff burst가 noisy neighbor 신호

**비약/반증된 주장**:
- ❌ VMXNET3 RX Ring 고갈 (Gemini)
- ❌ DRBD Protocol C 가산 latency가 핵심 촉매 (Gemini)
- ❌ QDevice/3-node 도입 필요 (Grok, Gemini)
- ❌ Storage 6ms peak이 SBD 5초 heartbeat fail의 직접 원인 (Grok, Gemini)

---

## 4. 고객 질의 답변 (사실 기반)

### Q1. 특별한 배치 작업이 없었는데 파일시스템 Hang 걸린 이유는?

**답변**: 4/22 당일 명시적 배치 부재는 사실. 그러나 **NetApp Flexvol 50에 외부 워크로드 또는 NetApp 내부 백그라운드(WAFL Scan, fp.est.scan 등)에 의한 Large Block Write가 발생**했고, 이것이 storage 컨트롤러 응답 지연(Back-to-Back CP)을 유발한 후 OCF Filesystem/pgsql resource monitor의 60s timeout 임계치를 넘긴 것이 직접 트리거. 단, 단일 storage burst만으로는 SBD majority lost(5초 heartbeat fail)을 설명하기 부족하므로, **만성적 iSCSI 네트워크 불안정성**(3~4월 30+회)이 동시 작용했다고 판단됨. **4/13 CDP 정책 변경 시 동일 패턴이 한 번 더 있었던 점은 결정적 단서**이며, 백업 워크로드 누적 영향 추가 검증 필요.

### Q2. DRBD Sync로 disk await 유발 가능한가?

**답변**: 이번 장애에서는 **DRBD가 직접 disk await을 유발한 증거 없음**. 근거:
1. 양 노드가 별도 NetApp 클러스터 사용 (cross-storage replication) — 002 측은 정상
2. 002로 failover 후 즉시 정상화 → standby disk 영향 없었음
3. messages 로그에 DRBD 관련 명시적 에러 없음

다만 **DRBD Protocol 설정 (`/etc/drbd.d/*.res`)을 확인할 필요**가 있음. Protocol C(완전 동기)면 이론적으로는 영향 가능하나, 이번 장애의 직접 원인 아님. 원본 분석의 "DRBD 직접 원인 아님" 판단이 정확함.

### Q3. 대용량 I/O 상황 시 Resource monitor / timeout (현재 60초)의 권고값은?

**답변** (Red Hat OCF 권장 + 본 장애 컨텍스트):
- **OCF Filesystem resource**: timeout `120s` (interval `20~30s` 유지)
- **OCF pgsql resource**: timeout `120s` (interval `30s`)
- pcmk_delay_max `15s`는 현 설정 유지 (이미 적용됨)
- **단, SBD 자체 timeout(`msgwait`, `watchdog_timeout`)을 동시에 점검 필요**. 현재 추정값(`watchdog≈5s`, `msgwait≈10s`)이 너무 공격적일 가능성

근거: 현재 60s는 RHEL 기본값이지만 iSCSI SBD + DRBD 환경에서는 일시 storage stall 시 false-positive 위험. 단, 무한정 늘리는 것은 실제 fault 시 다운타임 증가 트레이드오프.

### Q4. Monitor 주기/timeout을 권고값으로 늘렸을 때 hang 미감지 max 시간은?

**답변**: **약 150초 (2분 30초)**

계산식: `interval (30s) + timeout (120s) = 150s`

시나리오:
1. T=0: 정상 health check 완료
2. T=1: 시스템 hang 발생
3. T=30: 다음 monitor 시도, 응답 없음 → timeout 카운트 시작
4. T=150: timeout 만료 → fail 선언 → policy engine → fencing → failover

**현재 60s timeout 환경**: 약 90초 (interval 30s + timeout 60s)

**트레이드오프**:
- ❌ 짧은 timeout: false-positive로 멀쩡한 노드 fencing → 이번 장애 패턴
- ❌ 긴 timeout: 실제 hang 시 다운타임 증가
- ✅ 120s가 엔터프라이즈 환경에서 일반적 권고 (Red Hat KB 다수)

추가로 SBD `msgwait` 값과 같이 보아야 하며, `msgwait < OCF timeout`이 보장되어야 fencing이 fail-fast 상태로 동작.

---

## 5. 담당자별 추가 확인 포인트

### 5.1 OS / Cluster 담당

| # | 명령어 / 확인 항목 | 핵심 질문 |
|---|----|----|
| 1 | `pcs config` 전체 출력 | OCF Filesystem/pgsql resource의 monitor `interval`, `timeout`, `on-fail` 정확값? |
| 2 | `sbd dump` | SBD `msgwait`, `watchdog_timeout`, `Timeout (loop)`, `Timeout (allocate)` 실제값? |
| 3 | `crm_mon -1 --include=fencing-history` | 이번 fencing 외 과거 stonith 이력? |
| 4 | `/etc/iscsi/iscsid.conf` | `node.session.timeo.replacement_timeout`, `node.conn[0].timeo.noop_out_interval/timeout`, SBD 디바이스용 별도 설정 존재? |
| 5 | `drbdadm status`, `/etc/drbd.d/*.res` | **Protocol(A/B/C 중)**, `c-plan-ahead`, `disk-flushes`, `md-flushes`, `al-extents`, `c-fill-target` 설정? |
| 6 | **장애 시점 sar 데이터** (CPU, mem, disk, net) | **07:15~07:18 구간**: `sda/sdb await`, `iowait`, swap, network packet rate 변동? **(가장 중요)** |
| 7 | `dmesg`, `/var/log/messages` 4/22 06:50~07:25 풀 텍스트 | iSCSI session error/recovery, multipath path failure 등 추가 단서 |
| 8 | `multipath -ll` | iSCSI multipath 구성과 path별 health/priority |
| 9 | corosync `votequorum.expected_votes`, QDevice net ffsplit 설정 | QDevice가 4/22 07:15~20 동안 정상 응답했는지? `corosync-qdevice-tool -s` |

### 5.2 Storage 담당 (NetApp)

| # | 확인 항목 | 핵심 질문 |
|---|----|----|
| 1 | iscsi01-is361-krw1 양 노드 4/22 06:50~07:25 perfstat / Active IQ Unified Manager | Back-to-Back CP 정확한 횟수? `cp_phase_times`, volume별 `read/write_latency`, `total_ops`? |
| 2 | Flexvol 50의 4/22 07:01경 I/O 발생 클라이언트(LUN→Initiator) 추적 | **300MB/s 워크로드의 출처는 어느 VM/LUN/Initiator?** mspcollabo001 자체인가, 다른 VM인가, NetApp 백그라운드(WAFL/fp.est.scan)인가? |
| 3 | iSCSI LIF (198.19.19.168, 198.19.57.168) 4/22 통계 | SBD 디바이스용 LIF에서 07:15:15~32 packet drop / TCP retransmit / RTT 이상? |
| 4 | NetApp performance archive 용량 | **현재 24~26일만 보관 (목표 미달)** — 즉시 확장 필요. 본 장애 추가 분석에 제약 |
| 5 | 만료 인증서 갱신 (vs01, iscsi01-is361-krw1) | 4/18~21 매일 expired 경고 발생. 갱신 일정과 영향도? |
| 6 | `fp.est.scan.start.failed: CDE disabled` (V33, V50) | Compression Data Efficiency 비활성 사유? **Flexvol 50이 여기 포함되는 점이 의미심장** |
| 7 | iSCSI session count, throughput per LUN, QoS policy 적용 여부 | Flexvol 50 QoS 미적용 시 적용 검토 |

### 5.3 VMware 담당

| # | 확인 항목 | 핵심 질문 |
|---|----|----|
| 1 | 장애 시점 ESXi 호스트 esxtop / vCenter 성능 차트 | 07:01~07:20 구간 vmnic2/5 PAUSE frame 송신 burst? CPU steal time? %DRPRX/%DRPTX? |
| 2 | 동일 pNIC 공유 VM (line 474-481): ske-ip1core-cvnz2-5txt8, **scp-srmpd001**, **scp-amsdbe002** 등 | 4/22 07:01경 대용량 트래픽 유발 VM? 특히 DB 명칭 패턴 VM의 백업 동시 수행? |
| 3 | mspcollabo001 게스트 OS `ethtool -g eth0/eth1` | VM 내부 RX ring 현재값 (1024 추정), max(4096) 대비 |
| 4 | iSCSI vmkernel 포트(vmk10, vmk11) port-binding 구성과 health | iSCSI multipath 구성 및 fault tolerance |
| 5 | vmware.log 외 다른 VM의 fence/reset 발생 여부 | 동일 ESXi 호스트의 다른 cluster 영향? |
| 6 | DVS(CVDS-SWN) MTU=9000 일관성 | end-to-end MTU 점검 (vNIC, vSwitch, pSwitch, NetApp) |

### 5.4 DB 담당 (PostgreSQL/EDB)

| # | 확인 항목 | 핵심 질문 |
|---|----|----|
| 1 | 장애 시점 EDB Audit + WAL 활동 | 07:00경 `pg_stat_bgwriter`, `pg_stat_archiver` 변동? |
| 2 | `shared_buffers`, `effective_cache_size`, `wal_buffers`, `max_wal_size`, `checkpoint_timeout`, `checkpoint_completion_target` | 현재값 + 최적화 여지 |
| 3 | OCF pgsql resource agent 동작 방식 | `pg_isready`인지 `psql -c "select 1"`인지? local socket인지 TCP인지? |
| 4 | **4/13 CDP 백업 정책 변경 내역** | 어떤 LUN/Flexvol에 대한 CDP인가? 백업 주기/대역폭은? **Flexvol 50과 관계 있는가?** |
| 5 | `pg_stat_database`, `pg_stat_activity` 장애 시점 스냅샷 | active connection 누적 상황, lock contention |

---

## 6. 즉각 조치 권고 (우선순위)

### 🔴 High (1주 이내)
| # | 조치 | 근거 |
|---|------|------|
| H1 | OCF Filesystem resource timeout: 60s → **120s** | Q3 답변. 일시 storage stall에 대한 false-positive 방지 |
| H2 | OCF pgsql resource timeout: 60s → **120s** | 동일 근거 |
| H3 | NetApp performance archive 용량 확장: 24일 → **90일+** | F10. 향후 분석 능력 확보 |
| H4 | SBD `msgwait`, `watchdog_timeout` 실제값 점검 + OCF timeout과 정합성 확인 | OS 담당 #2 |
| H5 | iSCSI SBD 경로(198.19.x.x) L2/L3 추적 (`mtr`, `tcpdump` SBD LIF) | 만성 outdated의 진짜 원인 규명 |
| H6 | NetApp 만료 인증서(vs01, iscsi01-is361-krw1) 갱신 | F10 자매 이슈 |

### 🟡 Medium (1개월 이내)
| # | 조치 | 근거 |
|---|------|------|
| M1 | VMware esxtop 상시 수집 + ESXi 호스트별 noisy neighbor 분석 | TxXoff 391997 미해결 의문 |
| M2 | NetApp Flexvol 50에 QoS Max MB/s 적용 검토 | 의도 외 워크로드 차단 |
| M3 | CDP 백업 정책(4/13 변경분) 재검토 | Q1 핵심 단서 |
| M4 | DRBD `Protocol`, `c-plan-ahead`, `disk-flushes` 점검 후 필요 시 튜닝 | DRBD 영향 미해결 |
| M5 | `fp.est.scan.start.failed: CDE disabled` 의미 분석 후 조치 | NetApp 운영 위생 |

### ⚪ Hold (현재 데이터로는 불필요)
| # | 항목 | 사유 |
|---|------|------|
| X1 | QDevice 도입 | **이미 구성됨** (Grok, Gemini 권고 무효) |
| X2 | 3-node cluster 전환 | QDevice가 동등 역할 |
| X3 | VMXNET3 RX Ring 4096 상향 | `allocRxBuffFailed=0`으로 현재 장애와 무관 (장기적으로는 무해함) |
| X4 | DRBD 전용 네트워크 분리 | 본 장애와 직접 관련성 미입증 |

---

## 7. 마무리 — 솔직한 한계

### 본 분석의 한계
1. **6ms peak ↔ SBD 5초 heartbeat fail의 인과관계 미해결**: 추가 데이터(SBD iSCSI LIF의 4/22 07:15 packet/RTT)가 있어야 확정 가능
2. **300MB/s Large Block Write의 출처 미확인**: NetApp 백그라운드인지 외부 워크로드인지 불분명
3. **TxXoff 391997의 정확한 의미 미해석**: cumulative 카운터로는 시점 분석 불가, esxtop 시계열 필요
4. **DRBD Protocol 미확인**: drbdadm 출력 없이는 정확한 영향 평가 불가

### 추가 데이터 확보 후 재분석 권장
- 5.1~5.4의 추가 확인 항목들이 확보되면, 본 보고서를 v2로 업데이트하여 인과관계를 더 정밀하게 확정 가능

### 본 분석의 핵심 가치
- **두 외부 분석(Grok, Gemini)이 동일하게 범한 4가지 비약**을 데이터 기반으로 반박
- **원본 분석에서 누락된 의문점** (TxXoff, cross-storage DRBD, 6ms↔5s gap, CDP 누적 효과) 식별
- **즉각 적용 가능한 조치**(timeout 120s, archive 확장, 인증서 갱신)와 **추가 검증 필요 항목** 분리

---

*문서 작성: 2026-04-27 / 버전: v1.0*
*근거 자료: DBfailover원인분석석 (1,784 lines), Grok-장애분석.md, Gemini-장애분석.md*
