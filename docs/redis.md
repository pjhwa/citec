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
