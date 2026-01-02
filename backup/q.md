. 이슈사항 : 12/29(화) 9:00:43 ~ 9:09:06 2~10초가량 서비스 지연발생

   - 주문내역, 주문가능수량, 미체결 조회 지연

   - AP서버 2대 중 1대에서만 발생됨

     ( ProLiant DL380 G9, 28core 64G, RHEL 7.2)

  - 상장날로 사용률 증가 



. 진행사항 

  - 서비스 지연 시점, CPU 노드가 분산되지 못한 병목 현상 발생 부분 확인 및 분석 진행

  - Numa 설정 및 세마포어 설정값 변경 테스트 진행함



. 1/5(월) 09:30 여의도 회의 진행예정

   → 현재까지 Redhat 분석 결과 리뷰 진행할 예정으로, 

         자료는 일요일까지 벤더사에서 전달 받을 예정입니다





※ [참고] 테스트 진행 이력  ( 요약하지 않고 내부 공유하고 있는 내용 그대로 전달합니다. )

 . 대상서버 : 트레이딩 AP서버 (tnexia01,02), 

   - ProLiant DL380 G9, 28core 64G, RHEL 7.2

   - 테스트 서버 : 검증 (tnexia51)





테스트 시나리오  ( 12.30일 오전, /w 레드햇 ) 
   - 목적 
      1) node 0번이 부하상황일때 1번으로 넘어가는지
      2) 프로세스 구동될때 0,1 고루 분산되는지 
      3) 어플리케이션 특성에 따라 다른지 

   - 테스트환경 
      * tnexia51 <--  부하테스트 대상 서버  , saab51 (  Config 참고 ) 
      * 부하발생 테스트 시 방안 : 임의 shell로 node 0 번 부하발생 
   - 테스트케이스  ( 1,2,3,4 순서로 ) 

테스트 시나리오 별 결과

     1) numa = off    // node 구분없이 전체 CPU 다 사용하는지 확인

     1-) numa = off & log level = "I"
     주문시간 기준 12:20:58~12:21:38 
     주문 4000, 체결 3300, 미들 2000     

     1-2) numa = off & log level = "W"

       주문시간 기준 112:58:52~12:59:32
       주문 4000, 체결 3300, 미들 2000

     2) numactl --interleave=all > 자원을 모두 골고루 쓰겠다고 선언 // numa 켜있는 상태이서
       * Numa 상태에 따른 프로세스 CPU 할당 분포 확인
      2-1) 일반기동 : kernel.numa_balancing=1
      2-2) 일반기동 : kernel.numa_balancing=0
      2-3) numactl기동 : kernel.numa_balancing=1 
      2-4) numactl기동 : kernel.numa_balancing=0

 (AP성능) 
|---|---|---|
|   |NUMA_BALANCE=1|NUMA_BALANCE=0|
|일반 기동|2-1) 14:17:41~14:20:38
주문 4000, 체결 3300, 미들 2400|2-2) 14:05:54~14:06:34
주문 4000, 체결 3300, 미들 2400|
|numactl 기동|2-3) 14:31:04~14:34:24
주문 4000, 체결 3300, 미들 2400|2-4) 13:48:21~13:49:01
주문 4000, 체결 3300, 미들 2400|

*로그 Off  설정

(턱시도AC/데몬 분배상태) 
|---|---|---|
|   |NUMA_BALANCE=1|NUMA_BALANCE=0|
|일반 기동|2-1)
AC 
노드 0 : 877 
노드 1: 44

데몬
노드 0 : 392
노드1 : 7

[강제훈] 2025-12-30 14:29
초기 시작은 이랬으나 부하가 한참 증가될때 
331 / 75  
이렇게까지 변화했습니다|2-2)
AC 
노드 0 : 880
노드 1 : 41 

데몬 
노드0:387 
노드1: 11

2-2)는 359/45 까지 올라갔습니다.|
|numactl --interleave=all <실행할_명령어>|2-3)
AC 
노드 0 : 872
노드1 : 49
데몬 
노드 0 : 389
노드1 : 10

[강제훈] 2025-12-30 14:38
337 / 64
최대 노드1에 64개까지 증가했습니다|2-4)|



# 메모리를 노드 0, 1에 균등하게 분산하여 실행
numactl --interleave=all <실행할_명령어>

#TUXEDO 엔진 및 AC 기동
numactl --interleave=all tmboot -A
numactl --interleave=all tmboot -S
# daemon controller 기동
numactl --interleave=all /unify/smid/smid/smidadm/bin/ss_damer -s init
# daemon start
numactl --interleave=all /unify/smid/smid/smidadm/bin/ss_damer -e 0

     3) 부하발생 
      3-1) kernel.numa_balancing=1 
      3-2) kernel.numa_balancing=0
4) 특정 프로세스를 노드 1의 CPU와 메모리에 고정
      4-1)  numactl --cpunodebind=1 --membind=1 <실행할_명령어>

     [강제훈] 2025-12-30 15:13
       현재 node 0  : 0 
               node1 : 362

    [정상원 (국내주식,장내채권 트레이딩 시스템 분석 및 설계)] 2025-12-30 15:35
    15:28:43~15:32:03
    주문 4000, 체결 3300, 미들 2600 ← 미들 성능 향상

       4-2) numactl --cpunodebind=0,1 --membind=0,1 <실행할_명령어>


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


 5-2) 본딩 LACP 설정 + 일반기동 +  kernel.numa_balancing=1  
AC 
노드 0 :  455
노드1 :   466
데몬 
노드 0 :  193
노드1 :   207

참고) saab51
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

20260102 오전테스트(saat,세마포어,shm 영향도)

7. tnexia51 / saab51 두개 서버간 동일 어플리케션 부하 점검

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

