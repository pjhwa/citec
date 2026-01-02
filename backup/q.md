

### 이슈사항

12/29(화) 9:00:43 ~ 9:09:06 2~10초가량 증권 주문/체결 서비스 지연 발생
   - 주문내역, 주문가능수량, 미체결 조회 지연
   - AP서버 2대 중 1대에서만 발생됨
     ( ProLiant DL380 G9, 28core 64G, RHEL 7.2)
   - 특정 종목 상장일로 사용률 증가

### 환경
RHEL 7.2 기반에 Kernel만 7.9 버전으로 업데이트.
Linux Kernel: 3.10.0-1160.132.1.el7.x86_64

### 진행사항 
  - 서비스 지연 시점, CPU 노드가 분산되지 못한 병목 현상 발생 부분 확인 및 분석 진행
  - Numa 설정 및 세마포어 설정값 변경 테스트 진행함

### 테스트 진행 이력
 . 대상서버 : 트레이딩 AP서버 (tnexia01,02), 
   - ProLiant DL380 G9, 28core 64G, RHEL 7.2
   - 테스트 서버 : 검증 (tnexia51)
테스트 서버 환경: tnexia51
Cpuinfo: Intel® Xeon® CPU E5-2699 v4 @ 2.20GHz
Cpuinfo: Hz=1770.000 bogomips=4399.44
Cpuinfo: ProcessorChips=2 PhysicalCores=6
Cpuinfo: Hyperthreads =0 VirtualCPUs =12
Number of CPUs: 12

#### 테스트 시나리오  ( 12월 30일 오전, /w 레드햇 ) 
   - 목적 
      1) node 0번이 부하상황일때 1번으로 넘어가는지
      2) 프로세스 구동될때 0,1 고루 분산되는지 
      3) 어플리케이션 특성에 따라 다른지 

   - 테스트환경 
      * tnexia51 <--  부하테스트 대상 서버  , saab51 (  Config 참고 ) 
      * 부하발생 테스트 시 방안 : 임의 shell로 node 0 번 부하발생 
   - 테스트케이스  ( 1,2,3,4 순서로 ) 

#### 테스트 시나리오 별 결과

##### 테스트 케이스 1)
     1) numa = off    // node 구분없이 전체 CPU 다 사용하는지 확인

     1-1) numa = off & log level = "I"
     주문시간 기준 12:20:58~12:21:38 
     주문 4000, 체결 3300, 미들 2000     

     1-2) numa = off & log level = "W"
       주문시간 기준 112:58:52~12:59:32
       주문 4000, 체결 3300, 미들 2000

##### 테스트 케이스 2)
     2) numactl --interleave=all > 자원을 모두 골고루 쓰겠다고 선언 // numa 켜있는 상태이서
       * Numa 상태에 따른 프로세스 CPU 할당 분포 확인
      2-1) 일반기동 : kernel.numa_balancing=1
      2-2) 일반기동 : kernel.numa_balancing=0
      2-3) numactl기동 : kernel.numa_balancing=1 
      2-4) numactl기동 : kernel.numa_balancing=0

 (AP성능) 
|   |NUMA_BALANCE=1|NUMA_BALANCE=0|
|---|---|---|
|일반 기동|2-1) 14:17:41~14:20:38<br>주문 4000, 체결 3300, 미들 2400|2-2) 14:05:54~14:06:34<br>주문 4000, 체결 3300, 미들 2400|
|numactl 기동|2-3) 14:31:04~14:34:24<br>주문 4000, 체결 3300, 미들 2400|2-4) 13:48:21~13:49:01<br>주문 4000, 체결 3300, 미들 2400|

- 참고: 로그 Off  설정

(턱시도AC/데몬 분배상태) 
|   |NUMA_BALANCE=1|NUMA_BALANCE=0|
|---|---|---|
|일반 기동|2-1)<br>AC<br> 노드 0 : 877<br> 노드 1: 44<br><br>데몬<br>노드 0 : 392<br>노드1 : 7<br>[담당자] 2025-12-30 14:29<br>초기 시작은 이랬으나 부하가 한참 증가될때 331 / 75 까지 변화했습니다|2-2)<br>AC<br>노드 0 : 880<br>노드 1 : 41<br><br> 데몬<br>노드0:387<br>노드1: 11<br>2-2)는 359/45 까지 올라갔습니다.|
|numactl --interleave=all <실행할_명령어>|2-3)<br>AC<br> 노드 0 : 872<br>노드1 : 49<br><br>데몬<br> 노드 0 : 389<br>노드1 : 10<br>[담당자] 2025-12-30 14:38<br>337 / 64<br>최대 노드1에 64개까지 증가했습니다|2-4)|


- 메모리를 노드 0, 1에 균등하게 분산하여 실행
numactl --interleave=all <실행할_명령어>

- TUXEDO 엔진 및 AC 기동
numactl --interleave=all tmboot -A
numactl --interleave=all tmboot -S
- daemon controller 기동
numactl --interleave=all /unify/smid/smid/smidadm/bin/ss_damer -s init
- daemon start
numactl --interleave=all /unify/smid/smid/smidadm/bin/ss_damer -e 0

##### 테스트 케이스 3)
     3) 부하발생 
      3-1) kernel.numa_balancing=1 
      3-2) kernel.numa_balancing=0

##### 테스트 케이스 4)
4) 특정 프로세스를 노드 1의 CPU와 메모리에 고정
      4-1)  numactl --cpunodebind=1 --membind=1 <실행할_명령어>

     [담당자] 2025-12-30 15:13
       현재 node 0  : 0 
               node1 : 362

    [AP담당자] 2025-12-30 15:35
    15:28:43~15:32:03
    주문 4000, 체결 3300, 미들 2600 ← 미들 성능 향상

       4-2) numactl --cpunodebind=0,1 --membind=0,1 <실행할_명령어>

##### 테스트 케이스 5) 
LACP는 증권사 환경에서 사용할 수 없는 선택지이나, 분산이 되는지를 확인하기 위한 테스트 수행.
     5) 본딩 LACP 설정   // 설정가능한 경우 

     5-1) 본딩 LACP 설정 + 일반기동 +  kernel.numa_balancing=0 
     5-2) 본딩 LACP 설정 + 일반기동 +  kernel.numa_balancing=1 

     5-1) 결과 // 본딩 LACP 설정 + 일반기동 +  kernel.numa_balancing=0 

    - 16:16:29~16:19:49 주문 4000, 체결 3300, 미들 2400
AC 
노드 0 : 417 
노드 1: 504 

데몬 
노드 0: 215 
노드 1: 190

nmon 수행결과, CPU Utilization에서
CPU 1 ~ 12 까지 Usr%는 14 ~ 17%, SYS%는 51 ~ 59% 로 기록. (SYS%가 높음)

 5-2) 본딩 LACP 설정 + 일반기동 +  kernel.numa_balancing=1  
AC 
노드 0 :  455
노드1 :   466
데몬 
노드 0 :  193
노드1 :   207

nmon 수행결과, CPU Utilization에서
CPU 1 ~ 12 까지 Usr%는 15 ~ 23%, SYS%는 49 ~ 61% 로 기록. (SYS%가 높음)

참고) saab51
nmon 수행결과, CPU Utilization에서
CPU 1 ~ 44 까지 Usr%는 71 ~ 90%, SYS%는 13 ~ 22% 로 기록.

##### 테스트 케이스 6)
6) IRQ밸런싱 옵션 off (LACP와 비슷한 SW적 기능)

     - 일반기동 +  kernel.numa_balancing=0

 16:57:34~17:00:54
 주문 4000, 체결 3300, 미들 2400

구동직후
AC 
노드 0 :  899
노드1 :   22
데몬 
노드 0 :  393
노드1 :   7

데몬 부하직후

234/165

230/178

244/168

nmon 수행결과, CPU Utilization에서
|CPU|User%|Sys%|Wait%|Idle|
|---|---|---|---|---|
|1|8.6|30.2|0.0|61.2|
|2|8.3|27.7|0.0|64.0|
|3|7.8|30.5|0.0|61.7|
|4|21.6|73.5|0.0|4.9|
|5|23.6|62.8|0.0|13.6|
|6|22.0|62.3|0.0|15.7|
|7|7.2|28.5|0.0|64.3|
|8|6.1|28.2|0.0|65.6|
|9|7.8|27.0|0.0|65.2|
|10|21.4|61.7|0.0|16.9|
|11|21.2|60.9|0.0|17.8|
|12|20.5|62.6|0.0|16.9|
|Avg|14.9|46.5|0.0|38.6|

|CPU|User%|Sys%|Wait%|Idle|
|---|---|---|---|---|
|1|25.1|66.4|0.0|8.5|
|2|27.5|46.7|0.0|25.8|
|3|22.7|46.5|0.0|30.8|
|4|2.4|10.0|0.0|87.6|
|5|7.5|6.8|0.0|85.6|
|6|1.7|5.5|0.0|92.8|
|7|21.1|44.2|0.0|34.7|
|8|18.5|41.8|0.0|39.7|
|9|17.7|38.9|0.0|43.3|
|10|4.4|11.9|0.0|83.6|
|11|2.4|5.2|0.0|92.4|
|12|4.8|13.3|0.0|81.9|
|Avg|13.1|28.4|0.0|58.5|


##### 테스트 케이스 7)
20260102 오전테스트(saat,세마포어,shm 영향도)

7) tnexia51 / saab51 두개 서버간 동일 어플리케션 부하 점검

  - 목적 : AP서버 OS 버전에서 CPU 분배 상태 확인 

   . saab51 : Red Hat Enterprise Linux Server release 7.1 (Maipo)

   . tnexia51: Red Hat Enterprise Linux Server release 7.2 (Maipo)

  - 설정

   . irqbalance ON  + numa_balancing = 0  ( saab, tnexia 동일하게 ) 

  - 부하 : 

   . saab51 : 주문 + 체결 fw1호기 

   . tneixa51:  체결 fw2호기



▶baseline   <-- CPU 비정상

 * kfep 에이전트 구동 +  anyframe f/w 구동  + AC/데몬 미구동 ( 주문체결부하) 

 * 지금 tnexia51 상태  : 주문 agent 전체 on  + shm  upload + 세마포어 기동



▶ "kfep 에이전트 구동 +  anyframe f/w 미구동"상태에서 1,2번 ( 주문체결부하만) 테스트 

7-0. 다 내리고 지운상태    <-- CPU 정상

 * 지금 tnexia51 상태  : 주문 agent 전체 off  + shm  all clear  + 세마포어 제거

7-1. shm 만 지우기  <-- CPU 정상적으로 판단

 * 지금 tnexia51 상태  : 주문 agent 전체 off  + shm  all clear  + 세마포어 기동중

7-2. 세마포어만 지우기 <-- CPU정상 

 * 지금 tnexia51 상태  : 주문 agent 전체 on  + shm  upload + 세마포어 제거

7-3. sem포어가 생성 and agent 기동<-- CPU정상 

 * 지금 tnexia51 상태  : 주문 agent 전체 on  + shm  제거 + 세마포어 기동

7-4. sem포어가 생성 and agent 기동<-- CPU정상 

 * 지금 tnexia51 상태  : 주문 agent 전체 on  + shm  upload + 세마포어 기동

7-5. sem포어가 생성 and agent 기동 + anyframe f/w 기동     ( =baseline 과 동일 ) <-- CPU정상 

 * 지금 tnexia51 상태  : 주문 agent 전체 on  + shm  upload + 세마포어 기동

7-6. sem포어가 생성 and agent 기동 + anyframe f/w 기동    + ac/데몬 기동  ( 주문체결부하만) <-- CPU정상 

 * 지금 tnexia51 상태  : 주문 agent 전체 on  + shm  upload + 세마포어 기동

7-7. sem포어가 생성 and agent 기동 + anyframe f/w 기동    + ac/데몬 기동  ( 주문체결 + 영업일메모리? ) <-- CPU정상 

 * 지금 tnexia51 상태  : 주문 agent 전체 on  + shm  upload + 세마포어 기동

7-8. sem포어가 생성 and agent 기동 + anyframe f/w 기동    + ac/데몬 기동  ( 데몬처리만 ) <-- USER CPU 사용 늘어간듯<-- CPU정상인듯

 * 지금 tnexia51 상태  : 주문 agent 전체 on  + shm  upload + 세마포어 기동

7-9. sem포어가 생성 and agent 기동 + anyframe f/w 기동    + ac/데몬 기동  (주문체결 + 데몬처리 ) <-- CPU정상 

 * 지금 tnexia51 상태  : 주문 agent 전체 on  + shm  upload + 세마포어 기동

##### 테스트 케이스 8)
8. 서버리붓 / AP구동 ( 새로운 마음으로  , cpu비정상을 재현 ) 

현재 상태 irqbalance ON  + numa_balancing = 0


 8-0. 주문FEP,턱시도AP,데몬 기동 : Tuxedo 조회부하 + 데몬처리  

14:41:01        all     23.63      0.00     19.27      0.00      0.00     57.10     42.9
14:41:31        all     32.29      0.00     30.21      0.00      0.00     37.50     62.5
14:42:01        all     32.59      0.00     30.36      0.00      0.00     37.04     62.96
14:42:31        all     32.06      0.00     30.34      0.00      0.00     37.60     62.4
14:43:01        all     32.38      0.00     30.36      0.00      0.00     37.27     62.73

주문 3400
체결 3400
미들 2000


##### 테스트 케이스 8) 재테스트
20260102 재현테스트(CPU비정상 상황)

* tnexia51 설정 

irqbalance ON  + numa_balancing = 0

8. 서버리붓 / AP구동 ( 새로운 마음으로  , cpu비정상을 재현 ) 

 8-0. 주문FEP,턱시도AP,데몬 기동 : Tuxedo 조회부하 + 데몬처리  

 8-0-1 numa_balancing = 1   15:06:55~15:10:49

 8-0-2  db2trc alloc(세마포어 1개 점유)



 8-1. 주문FEP,턱시도AP,데몬 기동 + tnexia51 주문체결 기동 : 주문체결 

 (케이스추가) -> 세마포, shm 날리면 서비스 수행 불가이므로, 부적절한 테스트임. 

 8-2. 세마포 , shm 날리기 : Tuxedo 조회부하 + 데몬처리  

 8-3. 세마포 , shm 날리기 : 주문체결
