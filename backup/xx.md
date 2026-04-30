# ■ NextMosaic Cluster DB(DBaaS) Failover 이슈 분석 지원

* **요청 배경**: NextMosaic mspcollaboprd DB(DBaaS) failover 발생(04.22 07:17 ~ 07:20)에 대한 상세 원인 분석 요청
* **요청 부서**: MSP인프라기술그룹, SCP시스템 운영그룹, SCP Compute 그룹
* **지원 담당**: 조윤석, 박희태, 이광호, 권상득, 박영철, 전력식, 박재화
* **지원 일시**: 04.22 ~

---

## 한 줄 요약
> **단일 PVSCSI Controller에 4개 대용량 vDisk가 집중되어 디스크 큐 병목 발생 → I/O 지연이 DB 트랜잭션·Cluster 헬스체크에 연쇄 전파 → Cluster가 응답 없는 노드로 판단해 강제 Shutdown 및 Failover 수행**

---

## 지원 내용

### 1. DB 분석 — 증상 흐름
* 약 **15분간** DB 지표가 간헐적으로 수집되며 장애 진행
* 수집 가능했던 구간에는 Insert/Delete/Update가 수행되었으나, **long transaction 지표 동반 상승** → I/O 지연이 트랜잭션 처리를 지연시킴
* **장애 진행 순서**:
  1. 단순 Insert 성능 급격 지연 (최대 **28,933ms**)
  2. Cluster에 의한 **강제 DB Shutdown**
  3. Cluster DB Health Connection **1/2/3/4차 접속 지연**
  4. DB Failover 후 정상화

### 2. Linux 로그 분석 — 의심 원인
* **첫째**: SBD iSCSI 측 네트워크 문제 (또는 호스트 측 네트워크) 확인 필요
* **둘째**: CPU/Memory 등 리소스 부족 또는 내부 CPU 소모성 loop (또는 호스트 측 자원) 확인 필요

### 3. Linux 성능 분석 — 측정 결과
* **문제 시간대**: 07:05~07:19 (CPU/Memory/Disk/Block 지표 집중)
* **CPU 특성**: 평상시에도 core별 100% 사용 일부 존재하나, 전체 평균은 낮음
* **장애 시점 급증 지표**:
  - sys/iowait 상승
  - free page 부족
  - uninterruptible state 프로세스 증가
  - runq(실행 대기 큐) 길이 증가

### 4. VMware 분석 — 핵심 원인 식별

#### 4-1. CPU/리소스 상태 (정상 범위)
| 지표 | 1주 최대 | 장애 시점 | 판정 |
|------|---------|----------|------|
| Usage | 87% | 75% | 양호 |
| Ready | 0.73% | 0.3% | 양호 |
| CoStop, Demand | (1주 최대) | 그 이하 | 양호 |

→ **CPU 리소스 자체는 문제 아님**

#### 4-2. 호스트 가상화율 (참고)
* 호스트: `hcn04-ls361-krw1.ps`
* mspcollabo001: 48 vCPU, 192GB (2 NUMA node)
* **CPU 가상화율: 448 / 96(4 socket × 24) × 100 = 467%**

#### 4-3. 장애 시점 결정적 로그 (★ 핵심)

**[1] VM Hard Reset 발생**
```
2026-04-21T22:19:23.111(UTC) — VM hard reset
```

**[2] No VMkernel vSCSI handler for disk** — 4개 디스크 모두 동일 controller(ctrl:1000)
```
22:19:23.173Z  scsi0:0 (ctrl:1000) [SWN-CN-V45] mspcollabo001.vmdk
22:19:23.173Z  scsi0:1 (ctrl:1000) [SWN-CN-V43] mspcollabo001_1000_1_7943.vmdk
22:19:23.173Z  scsi0:2 (ctrl:1000) [SWN-CN-V53] mspcollabo001_1000_2_7477.vmdk
22:19:23.173Z  scsi0:3 (ctrl:1000) [SWN-CN-V08] mspcollabo001_1000_3_2759.vmdk
```

**[3] PVSCSI Busy 에러**
```
22:19:24.002Z  PVSCSI: 2682: Failed to issue sync i/o : Busy (btstat=0x0 sdstat=0x8)
```

#### 4-4. 근본 원인 — 단일 PVSCSI Controller 병목

**Broadcom KB 435544 인용**:
> *"The virtual machine's performance is bottlenecked because all high-intensity data disks are routed through a single PVSCSI Controller (SCSI 0)"*

**현재 구성 (문제 있음)**:

| Device | Size | Controller |
|--------|------|------------|
| scsi0:0 | 1,001 GB | **PVSCSI 0 (단일)** |
| scsi0:1 | 5,120 GB | **PVSCSI 0 (단일)** |
| scsi0:2 | 3,072 GB | **PVSCSI 0 (단일)** |
| scsi0:3 | 1,024 GB | **PVSCSI 0 (단일)** |

→ **총 10TB+ 대용량 vDisk가 단일 컨트롤러 큐 공유** = I/O 폭주 시 즉시 병목

#### 4-5. 권고 조치

**① PVSCSI Controller 분리** (KB 435544)
* 현재: 4개 vDisk → 1개 controller
* 권고: 4개 vDisk → 4개 controller (scsi0~scsi3로 분산)

**② Linux VM PVSCSI 큐 깊이 튜닝** (KB 343323)
```
vmw_pvscsi.cmd_per_lun=254     (default 64 → 254, 약 4배)
vmw_pvscsi.ring_pages=32       (default 8 → 32, 4배)
```

**참고 KB**:
* [KB 435544 — High disk latency on VMs and hard reset](https://knowledge.broadcom.com/external/article/435544/high-disk-latency-on-vms-and-hard-reset.html)
* [KB 343323 — Large-scale workloads with intensive I/O patterns](https://knowledge.broadcom.com/external/article/343323/largescale-workloads-with-intensive-io-p.html)
