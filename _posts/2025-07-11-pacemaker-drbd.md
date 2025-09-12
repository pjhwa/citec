---
title: "Database 서비스 불가 및 OS 접속 불가 문제"
date: 2025-07-11
tags: [redhat, pacemaker, drbd, xfs, kernel, hang]
categories: [Issues, Linux]
---


## 문제 상황 설명

### 증상

Database 서비스 불가 및 OS 접속 불가

### 환경

- Red Hat Enterprise Linux Server release 7.4 (Maipo)
- 3.10.0-693.el7.x86_64
- VMware Virtual Platform 

### 주요 증상

- 시스템 핵심 프로세스 Block: kswapd0(메모리 관리), crmd(클러스터 관리), vmtoolsd(VMware 통신) 등이 TASK_UNINTERRUPTIBLE인 D state 로 유지.
- XFS 파일시스템 mutex 데드락: 모든 파일 접근이 동일 mutex lock에서 무한 대기.
- 클러스터 자동 복구 기능 상실: monitoring, fencing, resource 절체와 같은 모든 기능 정지.
- VMware Tools 통신 중단: 하이퍼바이저와의 통신 차단.

### 관련 로그

```
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: INFO: task kswapd0:100 blocked for more than 120 seconds.
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: "echo 0 > /proc/sys/kernel/hung_task_timeout_secs" disables this message.
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: kswapd0         D ffff880fc76e3570     0   100      2 0x00000000
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: INFO: task vmtoolsd:1135 blocked for more than 120 seconds.
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: "echo 0 > /proc/sys/kernel/hung_task_timeout_secs" disables this message.
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: vmtoolsd        D ffff88017f80c0f0     0  1135      1 0x00000080
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: INFO: task irqbalance:1161 blocked for more than 120 seconds.
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: "echo 0 > /proc/sys/kernel/hung_task_timeout_secs" disables this message.
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: irqbalance      D ffff880fc76e3570     0  1161      1 0x00000080
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: INFO: task crmd:2092 blocked for more than 120 seconds.
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: "echo 0 > /proc/sys/kernel/hung_task_timeout_secs" disables this message.
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: crmd            D ffff88017f80c0f0     0  2092   2086 0x00000080
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: INFO: task metricbeat:2611 blocked for more than 120 seconds.
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: "echo 0 > /proc/sys/kernel/hung_task_timeout_secs" disables this message.
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: metricbeat      D ffff88017f80c0f0     0  2611      1 0x00000080
...
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: metricbeat      D ffff88017f80c0f0     0  2616      1 0x00000080
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: metricbeat      D ffff88017f80c0f0     0  2625      1 0x00000080
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: metricbeat      D ffff88017f80c0f0     0  2626      1 0x00000080
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: metricbeat      D ffff880fdb7d3b50     0  3099      1 0x00000080
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: metricbeat      D ffff88017f80c0f0     0 10896      1 0x00000080
```

```
Jul  9 11:45:09 scp-sdspgdb4p02 lrmd[2089]: warning: DB_monitor_60000 process (PID 2254) timed out
Jul  9 11:45:15 scp-sdspgdb4p02 lrmd[2089]: warning: drbd_res_monitor_60000 process (PID 2256) timed out
Jul  9 11:45:15 scp-sdspgdb4p02 lrmd[2089]:    crit: DB_monitor_60000 process (PID 2254) will not die!
Jul  9 11:45:15 scp-sdspgdb4p02 lrmd[2089]: warning: VIP_monitor_30000 process (PID 2258) timed out
Jul  9 11:45:18 scp-sdspgdb4p02 lrmd[2089]: warning: Filesystem_monitor_60000 process (PID 2264) timed out
Jul  9 11:45:20 scp-sdspgdb4p02 lrmd[2089]:    crit: drbd_res_monitor_60000 process (PID 2256) will not die!
Jul  9 11:45:20 scp-sdspgdb4p02 lrmd[2089]:    crit: VIP_monitor_30000 process (PID 2258) will not die!
Jul  9 11:45:23 scp-sdspgdb4p02 lrmd[2089]:    crit: Filesystem_monitor_60000 process (PID 2264) will not die!
```

```
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: INFO: task kswapd0:100 blocked for more than 120 seconds.
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: "echo 0 > /proc/sys/kernel/hung_task_timeout_secs" disables this message.
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: kswapd0         D ffff880fc76e3570     0   100      2 0x00000000
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: ffff880ffc2cba20 0000000000000046 ffff880ffc250fd0 ffff880ffc2cbfd8
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: ffff880ffc2cbfd8 ffff880ffc2cbfd8 ffff880ffc250fd0 ffff880fc76e3568
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: ffff880fc76e356c ffff880ffc250fd0 00000000ffffffff ffff880fc76e3570
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: Call Trace:
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: [<ffffffff816aa3e9>] schedule_preempt_disabled+0x29/0x70
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: [<ffffffff816a8317>] __mutex_lock_slowpath+0xc7/0x1d0
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: [<ffffffff816a772f>] mutex_lock+0x1f/0x2f
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: [<ffffffffc026fe7c>] xfs_reclaim_inodes_ag+0x2dc/0x390 [xfs]
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: [<ffffffff810ce8d8>] ? check_preempt_wakeup+0x148/0x250
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: [<ffffffff810c12d5>] ? check_preempt_curr+0x85/0xa0
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: [<ffffffff8113914d>] ? call_rcu_sched+0x1d/0x20
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: [<ffffffff8121819c>] ? d_free+0x4c/0x70
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: [<ffffffff8121a3b4>] ? shrink_dentry_list+0x274/0x490
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: [<ffffffffc0270df3>] xfs_reclaim_inodes_nr+0x33/0x40 [xfs]
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: [<ffffffffc02806f5>] xfs_fs_free_cached_objects+0x15/0x20 [xfs]
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: [<ffffffff81203888>] prune_super+0xe8/0x170
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: [<ffffffff81195413>] shrink_slab+0x163/0x330
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: [<ffffffff811f7537>] ? vmpressure+0x87/0x90
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: [<ffffffff81199081>] balance_pgdat+0x4b1/0x5e0
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: [<ffffffff81199323>] kswapd+0x173/0x440
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: [<ffffffff810b1910>] ? wake_up_atomic_t+0x30/0x30
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: [<ffffffff811991b0>] ? balance_pgdat+0x5e0/0x5e0
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: [<ffffffff810b098f>] kthread+0xcf/0xe0
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: [<ffffffff810b08c0>] ? insert_kthread_work+0x40/0x40
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: [<ffffffff816b4f18>] ret_from_fork+0x58/0x90
Jul  9 11:47:22 scp-sdspgdb4p02 kernel: [<ffffffff810b08c0>] ? insert_kthread_work+0x40/0x40
```

## 문제 원인 분석

제공된 로그, 메모리 사용량 데이터, Pacemaker 구성 정보, 그리고 내 통찰을 바탕으로 문제를 재분석하였다. 기술지원 업체는 kswapd0 프로세스의 XFS 파일시스템 mutex 데드락을 주요 원인으로 지목하며, 메모리 부족이 아닌 정기 메모리 관리 과정에서의 I/O 지연으로 인한 시스템 hang을 강조했다. 이를 바탕으로 로그를 검토한 결과, 이는 맞지만 더 깊이 파고들면 **XFS 파일시스템의 inode reclaim 과정에서 발생한 락 경합(lock contention)이 커널 수준의 데드락으로 확대된 것**으로 보인다. 이는 RHEL 7.4의 오래된 커널(3.10.0-693.el7.x86_64)에서 알려진 취약점과 관련이 깊다. 내 통찰로는, DRBD 기반의 이중화 환경에서 동기 복제 과정이 I/O 부하를 증폭시켜 mutex lock 지연을 유발했을 가능성이 높다. 로그에서 보듯, kswapd0가 xfs_reclaim_inodes_ag 함수에서 블록된 후 crmd, vmtoolsd 등 시스템 핵심 프로세스가 연쇄적으로 동일 mutex(예: 주소 ffff88017f80c0f0)에서 대기 상태(D state)로 전환된 점이 이를 뒷받침한다.

배경 설명 (난이도 높은 부분): XFS는 고성능 파일시스템으로, inode(파일 메타데이터)를 효율적으로 관리하기 위해 Allocation Group(AG) 단위로 캐싱한다. kswapd0는 메모리 압력이 있을 때(여기서는 캐시가 46GB로 과도하게 쌓임) inode를 reclaim(회수)하는데, 이 과정에서 mutex_lock을 사용해 동시 접근을 제어한다. 만약 I/O 지연(예: DRBD 복제 지연이나 SAN 스토리지 응답 느림)이 발생하면 lock 획득이 실패하고, 데드락이 일어난다. 데드락이란 두 개 이상의 프로세스가 서로의 자원을 기다리며 영원히 대기하는 상태로, 여기서는 XFS 내부 락이 시스템 전체 파일 접근을 차단했다. RHEL 7.4 커널은 XFS 관련 버그가 많아 후속 버전(7.9)에서 패치되었다.

추가 통찰: 메모리 분석에서 실제 사용률 25%지만 캐시가 46GB로 높았던 점은 DB 워크로드(PostgreSQL)가 대량의 파일 읽기/쓰기를 유발했음을 시사한다. metricbeat 프로세스(모니터링)가 다수 블록된 점은 /proc이나 /sys 파일 접근 시 XFS 락에 걸린 것으로, 이는 시스템 모니터링 자체를 마비시켰다. VMware 환경에서 vmtoolsd 블록은 가상 머신과 호스트 간 통신 중단을 초래해 자동 복구를 방해했다.

### 이중화 전환 실패 원인

Pacemaker+DRBD 기반 이중화는 Active 노드 장애 시 fencing(문제 노드 격리)과 failover(자원 이전)를 자동 수행하도록 설계되었다. 그러나 실패한 이유는 다음과 같다:

- **crmd 프로세스 블록**: Pacemaker의 핵심 데몬(crmd)이 XFS mutex 데드락으로 D state에 빠져 클러스터 의사결정을 할 수 없었다. 로그에서 crmd가 파일 open 시 mutex_lock에서 블록된 점이 확인된다. 이는 resource monitor(예: DB_monitor_60000)가 timeout 후 restart 시도조차 실패("will not die!")하게 만들었다.
  
- **파일시스템 및 DRBD 접근 차단**: 모든 리소스(DRBD, Filesystem, VIP, DB)가 파일/블록 디바이스 접근에 의존하는데, XFS hang으로 인해 DRBD 복제 상태 확인이나 Filesystem mount가 불가능해졌다. DRBD는 Master/Slave 모드로 동작하며, promote/demote가 I/O를 요구하나 이는 블록되었다.

- **Fencing 실패**: Stonith(fence_sbd)가 구성되어 있지만, crmd 블록으로 fencing 트리거가 일어나지 않았다. SBD는 공유 디스크(/dev/disk/by-path/... )를 사용하나, I/O hang으로 디스크 접근이 불가했다. Pacemaker 속성(stonith-enabled: true)이지만, 시스템 hang 상태에서 작동하지 않았다.

- 내 통찰: 구성에서 DataSync(DRBD)와 HA-GROUP(Filesystem+DB+VIP)의 colocation/ordering이 Mandatory로 되어 있어, DRBD Master 역할 이전이 실패하면 전체 failover가 멈춘다. 또한, no-quorum-policy: suicide는 quorum 상실 시 노드 자살을 유발하나, crmd 블록으로 quorum 체크조차 안 됐다. VMware 환경에서 vmtoolsd 블록은 호스트 수준의 fencing(VMware fence_vmware_soap 등)을 방해했을 수 있다.

배경 설명: 이중화 전환(failover)은 클러스터 소프트웨어(Pacemaker)가 노드 상태를 모니터링하고, 장애 시 자원을 이동시키는 과정이다. Fencing은 장애 노드가 여전히 자원을 잡고 있지 않도록 강제 종료(stonith: shoot the other node in the head)한다. 여기서 crmd는 "뇌" 역할을 하며, 블록되면 전체 시스템이 "마비"된다.

### 이슈 발생과 결과 관련 사안 시간순 표

아래 표는 로그와 기술지원 업체 분석을 기반으로 시간순으로 주요 이벤트를 정리한 것이다. 시간은 2025년 7월 9일 기준(현재 날짜 July 11, 2025로부터 이틀 전).

| 시간          | 이벤트/증상                                                                 | 영향 범위                          | 분석/결과                                                                 |
|---------------|-----------------------------------------------------------------------------|------------------------------------|---------------------------------------------------------------------------|
| 11:40        | 메모리 사용량: 실제 15.83GB (25%), 캐시/버퍼 ~46GB, 스왑 108MB             | 시스템 메모리                      | 정상 운영 중 캐시 과도 축적. kswapd0가 정리 준비 중.                     |
| 11:45:09     | DB_monitor_60000 timeout 발생                                              | DB 리소스                          | 파일시스템 접근 실패로 모니터링 타임아웃. DB 서비스 불가 시작.           |
| 11:45:15     | drbd_res_monitor_60000, VIP_monitor_30000 timeout                          | DRBD, VIP 리소스                   | 연쇄 타임아웃. DRBD 복제 및 VIP 접근 차단.                               |
| 11:45:18     | Filesystem_monitor_60000 timeout                                           | Filesystem 리소스                  | XFS 파일시스템 전체 접근 차단.                                            |
| 11:45:15~23  | 모든 모니터링 프로세스 "will not die!" (재시작 실패)                       | 전체 클러스터 리소스               | crmd 등 프로세스 블록으로 restart 불가. 클러스터 기능 마비.              |
| 11:45:22     | kswapd0 블록 시작 (xfs_reclaim_inodes_ag에서 mutex_lock)                   | 시스템 메모리 관리                 | 메모리 캐시 정리 중 I/O 지연으로 데드락. 시스템 hang 시작.               |
| 11:47:22     | kswapd0, crmd, vmtoolsd, irqbalance, metricbeat 등 120초 이상 블록 로그 기록 | 시스템 전체 (커널 수준)            | TASK_UNINTERRUPTIBLE D state 확인. 전체 프로세스 연쇄 블록. OS 접속 불가. |
| ~12:00 이후  | 클러스터 failover 시도 실패 (crmd 블록으로 fencing/trigger 안 됨)          | 이중화 전체                        | Active 노드 hang 지속. 수동 개입 필요.                                   |
| 13:20        | VMware 강제 종료 후 재부팅. 메모리 사용량: 실제 2.63GB (4%)               | 시스템 전체                        | 서비스 정상화. 하지만 이중화 자동 전환 실패로 인해 다운타임 발생.         |

## 문제 해결 방법 및 이중화 전환 실패 예방 방법

### 문제 해결 방법 (근본 원인: XFS mutex 데드락 및 커널 hang)
1. **OS 커널 업데이트**: 현재 RHEL 7.4 (커널 3.10.0-693.el7.x86_64)를 7.9로 업그레이드. 이는 XFS 관련 버그(예: inode reclaim 데드락)를 패치한 최신 커널(3.10.0-1160.el7.x86_64)을 제공한다. 방법: `yum update` 후 재부팅. 배경: Red Hat은 7.4에서 XFS I/O 지연 시 락 문제를 인정하고, 7.9에서 kswapd의 타임아웃 메커니즘을 강화했다. 업그레이드 전 테스트 환경에서 시뮬레이션 테스트 추천.

2. **SAR 설치 및 모니터링 강화**: sysstat 패키지 설치(`yum install sysstat`)해 sar 명령으로 I/O, 메모리, CPU 추세를 실시간 모니터링. Cloud Monitoring에 SAR factor 추가. 이는 캐시 과부하를 조기 감지. 추가로, vm.swappiness=10으로 낮춰 kswapd 트리거를 줄임. 배경: SAR는 시스템 활동 리포터로, /proc 파일 대신 전용 로그를 사용해 hang 시에도 유용. 현재 metricbeat만으로는 /proc 접근 블록 문제를 피할 수 없다.

3. **스토리지 최적화**: DRBD 복제 지연 확인. SAN array(공유 스토리지) 응답 시간을 모니터링하고, I/O 옵션(Filesystem: noatime)을 강화하거나, DRBD 프로토콜을 비동기(C)로 변경(현재 동기 A 또는 B로 추정). VMware에서 VM I/O 우선순위 높임.

4. **이중화 전환 실패 예방 방법**:
   - **Pacemaker 구성 개선**: stonith-timeout을 60s로 줄이고, fence_sbd의 pcmk_delay_max를 10s로 조정해 빠른 fencing. 추가 stonith 에이전트(fence_vmware_soap) 도입으로 VMware 수준 fencing 지원. no-quorum-policy를 "ignore"로 변경해 quorum 상실 시 failover 강제. crmd 프로세스에 별도 watchdog(하드웨어 타이머) 설정: `modprobe softdog` 후 systemd로 crmd 감시.
   
   배경: Watchdog은 프로세스가 hang되면 자동 재시동하는 하드웨어/소프트웨어 메커니즘. 현재 구성에서 crmd 블록을 방지하기 위해, Pacemaker에 "op monitor interval=10s timeout=30s"처럼 더 빈번한 체크 추가.

   - **테스트 및 시뮬레이션**: crm_simulate로 failover 시뮬레이션 테스트. XFS hang 유발 스크립트(dd로 대량 I/O 생성))로 테스트.

   - **백업 노드 강화**: Passive node에 SAR 설치하고, DRBD split-brain 자동 복구 스크립트 배포.

   - **전체 아키텍처 업그레이드**: RHEL 8로 마이그레이션 고려 (sar 기본 포함, XFS 개선). DBaaS에서 PostgreSQL 워크로드를 분산(예: read replica 추가)해 캐시 축적 방지.

## 요약 (운영자용 쉬운 설명)
이 문제는 컴퓨터의 '메모리 청소기'(kswapd0)가 파일 정리 중에 '문이 잠겨' 버려 (XFS 락) 전체 시스템이 멈춘 (hang) 거예요. 메모리는 충분했지만, 파일 캐시가 너무 쌓여 청소가 실패했어요. 이 때문에 DB 서비스가 안 되고, 자동 백업 시스템(이중화)이 작동하지 않아 손으로 꺼서 다시 켜야 했습니다. 원인은 오래된 OS 버전 때문이에요. 해결은 OS 업데이트와 모니터링 프로그램 설치로, 앞으로는 문 잠김을 미리 감지하고 백업이 자동으로 넘어가게 설정하세요. 다운타임 방지를 위해 정기 테스트를 해보세요.
