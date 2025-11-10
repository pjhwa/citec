Oracle 문서(Doc ID 3079200.1, 마지막 업데이트 2025년 10월 19일)
Linux kernel errata(ELSA-2025-17161, 2025년 10월 20일 발행)

1. CPU Scale Down 트리거 (버그의 시작점)  
사용자가 CPU 수를 64개에서 32개로 scale down 수행
Linux kernel(Oracle UEK 버전)은 hotplug 기능을 가지며, 
hotplug 기능은 CPU를 온라인에서 오프라인 상태로 전환함
이는 KVM 기반 Exadata VMs에서 자원 재배치를 위해 설계됨
그러나 RDS/IB와 결합 시 문제가 됨
CPU 오프라인 시 네트워크 패킷 처리 작업이 대기 큐에 쌓임
이 과정에서 Orabug 34039271 같은 버그가 큐를 stuck 상태로 만듬

* Orabug 34039271: RDS 연결에서 rx path가 stuck 시 복구 기능을 추가하려 했으나
복구 과정에서 연결 실패를 더 유발함
RDS 연결을 불안정하게 하여 reconnection 시간이 길어짐
또는 kernel panic이 발생하여 패치를 취소했음

2. RDS/IB 연결 리셋 (문제의 촉발)  
CPU 변경으로 RDS 연결이 자동 리셋됨
InfiniBand 드라이버가 hotplug 이벤트를 제대로 처리하지 못함
오프라인 CPU에 바인딩된 socket이 cancel operation 오류를 발생시킴
이는 Orabug 34319530 같은 namespace 제한 버그와 연관됨
결과로 연결이 dropped 상태가 됨

3. Reconnection 시도와 지연 축적 (버그의 확대)  
kernel이 끊어진 RDS 연결을 reconnection하려 함
그러나 버그로 과정이 매우 느려짐
RDS 모듈에서 stuck rx path가 발생함
이는 오프라인 CPU에 작업이 잘못 큐잉되어 이동하지 못함
고부하 시(OGG 복제나 tracefile 생성) 메모리 압력이 증가함
DMA 할당 실패가 쌓임

4. 지연의 DB 전파 (버그의 끝단)  
kernel 지연이 Oracle DB 상위 레이어로 전파됨
IO 작업이 멈춤
RDS 지연이 cell_disk_open 이벤트로 나타남
이는 네트워크 지연 → IO 대기 → timeout의 연쇄 반응임
