# [기술지원] 모니모 원앱 DB3 서비스 응답속도 증가 분석
## 배경
- 모니모 원앱 DB3 서비스 (RAC 클러스터)
- 데이터서비스플랫폼 배치 작업
- DB Patch & SMR 적용 후 03/16 06시 기상 미션 실행 중 응답시간·처리시간 증가 발생

## 요청부서
- 금융인프라운영그룹 금융인프라운영파트 천윤중파트장

## 일정
- 2026.03.16(월) ~ 19(목)

## 인력
- 전력식, 민연홍, 김형일, 박영철

## 지원내용

 - **분석 결과 (원앱)**
    . 문제점: DB Patch & SMR 적용 후 03/16 06시 기상 미션 실행 중 성능 지연
    . 분석:
       . DB#1/DB#2: ‘gc buffer busy acquired’ → RAC 환경에서 Buffer Cache Contention 심화
       . DB#3: ‘log file sync’ → 트랜잭션 커밋 속도 저하
       . 이전(01/18) 대비 CPU 코어 수 감소 → log_buffer 자동 축소(93 MB → 21 MB) → ‘log file sync’ 대기 시간 급증
    . 조치:
       . 03/17 저녁에 Log Buffer를 93 MB로 증설
       . 증설 후 DB#3 ‘log file sync’ Wait 개선 (4.3 ms → 181 µs)
       . DB#1/DB#2 ‘gc buffer busy acquired’ 사라짐
       . 기타 Wait Event 정상화, 이슈 해결 판단

 - **분석 결과 (데이터서비스플랫폼)**
    . 문제점: SRM 패치 적용 후 주요 배치 성능 저하
    . 분석:
       . Workload Profile 변화 확인 (03/03, 03/10, 03/17)
       . Top Wait Event: ‘free buffer waits’ 증가 → 버퍼 캐시 부족
       . Top SQL of Buffer Gets: 신규 대량 DML에 의한 Buffer Get 과점 현상
       . Top SQL of Elapsed Time: 동일 수행횟수·시간 유지 → 인프라 환경은 동일
    . Action Items:
       1. 1회성 Top Buffer Cache Query에 대한 SQL Tuning 수행
       2. ‘free buffer waits’ 해소를 위한 DB buffer cache 증설
       3. Hard Parsing 발생 1회성 Query에 대한 Bind 변수 처리

 - **진행 상황 (03/23 ~ 03/29)**
    . 03/24: 원앱 OCPU 동적 축소 (86 → 32)
    . DRCC(OCI) 클라우드 운영 환경 안정성 TF 진행 (CI‑TEC 참여: 박영철, 민연홍)
    . 일정: 3/30(월) ~ 4/17(금)
       - 금번 이슈 대응: Exa, DBCS 파라미터 검증 및 자원 증감 절차 검증/체계화
       - 클라우드 Run‑book 작성: SDS 운영 사례 기반 개선항목 도출 → Oracle 검토 → 최종 개선항목 도출, 타사 레퍼런스 제공 및 CI‑TEC 검증

 - **진행 상황 (03/30 ~ 04/06) – 원앱 PIFPC13 Instance Crash 분석**
    . DB#3 Instance Crash 원인 추정:
       - OCPU Scale Up/Down 시 Redo Allocation Latch 경합 → CPU Starvation → Resource Manager 개입 → GCS/GES 메시지 지연 → Time Drift → ASM 응답 지연 → Instance Termination

 - **장애 개요**
    . 발생 일시: 2026‑03‑15 14:06 ~ 14:11
    . 장애 유형: DB#3 Instance Hang 후 Crash
    . 영향 범위: RAC Cluster 전체 (DB#1, DB#2 포함) 서비스 지연/Timeout

 - **DB#3 Instance Crash 발생 원인 (추정 단계)**
    . Redo Latch Contention 증가
    . Spin 증가
    . CPU Saturation 발생
    . Resource Manager (resmgr:cpu quantum) 개입
    . GCS/GES 메시지 처리 지연
    . Time Drift 발생
    . ASM 응답 지연 (ASMB stuck)
    . DB#3 Instance Termination

 - **권고 사항**
    | 파라미터명                     | 설정값          |
    |------------------------------|----------------|
    | log_buffer                  | 97,501,184     |
    | gcs_server_processes        | 10             |
    | db_writer_processes         | 8              |
    | _ges_server_processes       | 3              |
    | _log_parallelism_max        | 11             |
    | _log_simultaneous_copies    | 128            |

 - **관련 Confluence URL**
    - [99. DB 분석 - Oracle (13/15 DB#3 Instance Crashed)](https://devops.sdsdev.co.kr/confluence/x/b2jMgw)
