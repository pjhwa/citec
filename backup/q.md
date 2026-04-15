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
