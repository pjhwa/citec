이틀전 사내시스템 운영DB(DBaaS Postgresql 이중화)에 아래와 같이 장애가 발생하였습니다. 



현재까지 확인된 원인은 OS Kernel Hang으로 인한 문제로 추정되는데, 

Active node가 reboot이 되지 않고 hang 상황으로 이중화 구성(Pacemaker+DRBD)이 동작하지 않아 

VMware에서 강제 종료하여 서비스를 정상화한 이중화 전환 실패사례입니다. 



이에 에스코어를 통해 기술지원을 받아 아래와 같이 분석을 진행하였는데, 

이중화 전환 실패 사례이다 보니 이슈가 될 수 있어 CI-TEC 전문가 분들께도 함께 기술 분석 지원을 부탁드리고자 합니다. 



참고로 해당 DB의 경우 rhel 7.4 버전으로 os버전이 낮은점(22.6월 생성) 과 SAR가 설치되어있지 않아 

Cloud Monitoring의 모니터링 factor로 분석된 아쉬운 부분이 있습니다. 

(rhel 8버전 배포판은 sar가 구성되어있고, 현재 rhel 7.4의 경우 7.9 os kernel update기능을 제공하고 있어 

후속대책으로 7버전에도 sar 설치와 고객에겐 7.9 업그레이드는 후속 대책으로 요청드리고자 합니다.)

아래는 에스코어의 분석 내용
----------------------------------------
추가로 metric beat 에서 수집한 메모리 사용량 excel 을 참고해서 분석한 내용 공유 드립니다.

 

1. 증상
DB 서비스 불가 및 OS 접속 불가

 

2. 환경
Red Hat Enterprise Linux Server release 7.4 (Maipo)

3.10.0-693.el7.x86_64

VMware Virtual Platform 

 

3. 문제
7월 9일 11:45:09에 DB resource에서 monitor timeout이 최초 발생하였으며, 이후 연쇄적으로 모든 클러스터 리소스에 영향 발생.

장애 진행 과정 (표)

시간

증상

영향 범위

분석

11:45:09

DB_monitor_60000 timeout

DB 리소스

파일시스템 접근 시도 실패

11:45:15

drbd_res_monitor_60000 timeout

DRBD 리소스

"

11:45:15

VIP_monitor_30000 timeout

VIP 리소스

"

11:45:18

Filesystem_monitor_60000 timeout

파일시스템 리소스

파일시스템 접근 전면 차단

11:45:15~23

모든 모니터링 프로세스 "will not die!"

전체 클러스터

프로세스 강제 종료 불가

11:45:22

kswapd0 Block 시작

시스템 핵심 기능

메모리 관리 데몬 정지

11:47:22

kswapd0 등 시스템 프로세스 120초 이상 Block 상태 지속

시스템 전체

커널 레벨 hang 상태



4. 주요 증상
시스템 핵심 프로세스 Block: kswapd0(메모리 관리), crmd(클러스터 관리), vmtoolsd(VMware 통신) 등이 TASK_UNINTERRUPTIBLE인 D state 로 유지.

XFS 파일시스템 mutex 데드락: 모든 파일 접근이 동일 mutex lock에서 무한 대기.

클러스터 자동 복구 기능 상실: monitoring, fencing, resource 절체와 같은 모든 기능 정지.

VMware Tools 통신 중단: 하이퍼바이저와의 통신 차단.
5. 확인 내용
5. 1 메모리 사용량 분석

구분

장애 시점 (11:40)

재부팅 후 (13:20)

비고

 총 메모리

64GB 

64GB 

VMware 할당 메모리

 Memory Used [Actual]

 15.83GB (25.16%) 

 2.63GB (4.18%) 

실제 프로세스 사용량

 Memory Free [Actual]

 47.3GB (75%) 

 61.13GB (96%) 

실제 여유 메모리

 Memory Used [Swap]

 108MB (5.27%) 

 0MB (0%) 

스왑 사용량

 Cache/Buffer

 ~46GB 

 ~0GB 

파일시스템 캐시

   

분석 결과

Cache + Buffer 사용량을 제외한 실제 점유 중인 메모리 사용률은 25%로 충분한 여유 공간이 확보된 상태로 운영 중이였기 때문에 메모리 부족을 원인으로 보긴 힘든 상황.

하지만 장애 당시 46GB 정도의 대용량 파일시스템 캐시가 점유 중 이였으며, 이는 kswapd0 데몬에서 정리 대상.

5. 2 시스템 프로세스 Block 상태 상세 분석

A. kswapd0 (PID: 100) - 핵심 Block 프로세스

역할: 커널 메모리 회수 데몬 (정기적 캐시 정리)

블록 위치: xfs_reclaim_inodes_ag (XFS inode 정리)

블록 시점: 11:45:22 (추정) - 120초 후인 11:47:22에 감지

원인: 46GB 캐시 정리 과정에서 I/O 지연으로 mutex 획득 실패



B. 연쇄 Block된 프로세스들

프로세스

Block 위치

원인

영향

 crmd (PID: 2092)

파일 open 시 mutex 대기

kswapd0와 동일 mutex 경합

클러스터 관리 마비

 vmtoolsd (PID: 1135)

파일 open 시 mutex 대기

VMware 통신 파일 접근 실패

하이퍼바이저 통신 중단

 irqbalance (PID: 1161)

XFS inode 정리 mutex 대기

kswapd0와 동일한 작업 시도

CPU 부하 불균형

 metricbeat (6개 프로세스)

파일 lookup/open 대기

/proc, /sys 접근 시 블록

모니터링 데이터 수집 중단

****
5. 3 Call Trace 분석: 정기적 메모리 관리 흐름 확인 

 kswapd0 정상적인 메모리 관리 흐름

 [<ffffffff81199323>] kswapd                    # 메모리 회수 데몬 실행

 [<ffffffff81199081>] balance_pgdat             # 메모리 균형 조정

 [<ffffffff81195413>] shrink_slab               # 슬랩 캐시 축소

 [<ffffffff81203888>] prune_super               # 수퍼블록 정리

 [<ffffffffc02806f5>] xfs_fs_free_cached_objects # XFS 캐시 객체 해제 요청

 [<ffffffffc0270df3>] xfs_reclaim_inodes_nr     # XFS inode 회수 요청

 [<ffffffffc026fe7c>] xfs_reclaim_inodes_ag     # AG별 inode 정리 ← Block 지점



 공통 Block 지점

 1. kswapd0: xfs_reclaim_inodes_ag에서 mutex_lock+0x1f/0x2f

 2. crmd: 파일 open 시 mutex_lock+0x1f/0x2f

 3. vmtoolsd: 파일 open 시 mutex_lock+0x1f/0x2f

 4. irqbalance: XFS inode 정리에서 mutex_lock+0x1f/0x2f

 5. matricbeat: 파일 lookup/open 에서 mutex_lock+0x1f/0x2f



핵심 발견사항

모든 Block 프로세스에서 공통적으로 다음 패턴 확인 → __mutex_lock_slowpath → mutex_lock → XFS 관련 함수

동일한 mutex 주소에서 여러 프로세스 대기 (ffff88017f80c0f0, ffff880fc76e3570)

XFS 파일시스템 내부 락 경합으로 인한 데드락 상황(Block된 프로세스들은 TASK_UNINTERRUPTIBLE인 D state 상태)
관련 로그

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

 ( metricbeat 프로세스의 경우 다수 발생된 상황으로 일부 로그 생략 )



6. 결론
근본 원인

kswapd0 정기 메모리 관리 중 XFS 파일시스템 mutex 데드락으로 인한 시스템 전체 hang 발생.

메모리 부족 현상이 아닌, 커널에서 효율적인 메모리 관리 과정에서 XFS inode cache 회수 중에 발생한 시스템 레벨 데드락.

모든 파일시스템 접근이 동일 mutex 에서 Block된점으로 보아 시스템 전체 파일 접근이 차단되었을 가능성이 높음.

클러스터 동작에 있어, 중요 결정을 담당하는 crmd 프로세스 Block으로 클러스터 관련 파일 접근 불가로 기능 상실.

절체 및 펜싱이 동작하지 않은 이유

Pacemaker crmd 프로세스 자체가 블록되어 클러스터 의사결정 기능 마비.

파일시스템 hang으로 인한 블록 디바이스 접근 차단.

시스템 레벨 hang 상태가 높은 확률로 예상되며, 그로인한 클러스터 전체 동작 불가.



장애 재발 방지 및 성능 개선을 위해 Redhat 공식 문서 및 내부 사례들을 찾아보았지만, 현재 사용 중인 커널이 3.10.0-693.el7.x86_64 버전으로 너무 오래된 버전을 사용 중이라 개선될 여지는 없어 보입니다.

추후에도 동일 현상이 발생될 경우에는 RHEL7.9 버전에서 제공하는 latest 버전까지 업데이트 고려 부탁 드립니다.

-----------------------------
DB 서비스 비정상 동작 상태에 따른 문의 내역 답변 드립니다.



문제 발생 증상으로 보이는 11:45:09경 DB resource 에서 monitor timeout 이 발생되었습니다.

resource에서 monitoring이 실패된 이후에는 on-fail=restart(default) 에 의해 재시작하게되는데 이후 로그들을 보면, 전부 다 중지를 할 수 없었던 상태로 확인 됩니다.

Jul  9 11:45:09 scp-sdspgdb4p02 lrmd[2089]: warning: DB_monitor_60000 process (PID 2254) timed out

Jul  9 11:45:15 scp-sdspgdb4p02 lrmd[2089]: warning: drbd_res_monitor_60000 process (PID 2256) timed out

Jul  9 11:45:15 scp-sdspgdb4p02 lrmd[2089]:    crit: DB_monitor_60000 process (PID 2254) will not die!

Jul  9 11:45:15 scp-sdspgdb4p02 lrmd[2089]: warning: VIP_monitor_30000 process (PID 2258) timed out

Jul  9 11:45:18 scp-sdspgdb4p02 lrmd[2089]: warning: Filesystem_monitor_60000 process (PID 2264) timed out

Jul  9 11:45:20 scp-sdspgdb4p02 lrmd[2089]:    crit: drbd_res_monitor_60000 process (PID 2256) will not die!

Jul  9 11:45:20 scp-sdspgdb4p02 lrmd[2089]:    crit: VIP_monitor_30000 process (PID 2258) will not die!

Jul  9 11:45:23 scp-sdspgdb4p02 lrmd[2089]:    crit: Filesystem_monitor_60000 process (PID 2264) will not die!



처음 문제로 인지했던 DB 뿐만 아니라 전체 resource(VIP, DB, Filesystem, DRBD) resource에서 영향을 받은 상황으로 이후 기록된 로그를 토대로 추측해볼 수 있습니다.



kswapd0 데몬은 효율적인 메모리 사용을 위해 정기적으로 수행되지만 xfs 파일시스템에서 mutex lock 경합으로 인해 120초 이상 block된 상황 입니다.

이는 I/O와 관련된 서브시스템과 연관되어있으며, 파일시스템 및 DRBD 복제 과정이나 하위 스토리지(디스크 컨트롤러 hang & SAN array 응답 지연) 문제로 발생될 수 있는 현상 입니다.
처음 문제로 인지했던 DB 뿐만 아니라 전체 resource(VIP, DB, Filesystem, DRBD) resource에서 영향을 받은 상황으로 이후 기록된 로그를 토대로 추측해볼 수 있습니다.



kswapd0 데몬은 효율적인 메모리 사용을 위해 정기적으로 수행되지만 xfs 파일시스템에서 mutex lock 경합으로 인해 120초 이상 block된 상황 입니다.

이는 I/O와 관련된 서브시스템과 연관되어있으며, 파일시스템 및 DRBD 복제 과정이나 하위 스토리지(디스크 컨트롤러 hang & SAN array 응답 지연) 문제로 발생될 수 있는 현상 입니다.



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



해당 시스템에 sysstat이 설치되어있지 않아서 sar 데이터가 없는 관계로 정확한 resource 사용률 추이는 확인되지 않지만,

공유해주신 사내 시스템에서 당시 메모리 사용량을 점유하고 있는 수치를 보면 실제 메모리 사용량은 Memory Usage [Actual]: 26%대로 그다지 높지 않은 수치로 확인 됩니다.



Memory Usage 98~99%로 되어있는 수치가 정확히 어떤 방식으로 집게되는지는 모르겠지만 buffer + cache 값이 더해진 수치일 것으로 보이며, 실제 가용 메모리는 충분했을 것으로 예상 됩니다.

결론적으로, 메모리 부족 상황은 아닌 것으로 예상되지만 I/O hang과 같은 상태가 발생되면서 전체 resource 에도 영향을 미쳤을 것으로 분석 됩니다.
