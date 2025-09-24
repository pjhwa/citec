### 사전 정보 요약
NSX-T는 VM의 IP 주소를 학습해 DFW/GFW 규칙을 적용함. 학습 방식은 두 가지: VM Tools(VM 내부 도구가 IP 직접 보고)와 ARP Snooping(네트워크 ARP 패킷 감시로 IP-MAC 바인딩). default-ip-discovery-profile에서 TOFU(Trust on First Use)는 최초 IP를 신뢰해 변경 막음. ARP binding limit 1은 포트당 IP 1개만 허용.

### 이슈 개요
C-VDS 전환 위한 vMotion 중 150대 이상 VM이 19초 중단됨. VRLI 로그에서 IP별 DFW/GFW timeout 확인됨. 이는 vMotion 시 VM Tools IP가 addrset에서 제거되어 규칙 미적용으로 발생.

### 원인
- vMotion 중 VM Tools status stopped로 IP addrset 제거됨.
- ARP Snooping IP가 남아 규칙 적용 가능하나, VM Template의 172 대역 IP가 최초 바인딩되어 잘못 유지됨.
- 배포 후 192 대역 변경 시 TOFU로 업데이트 안 됨. ARP binding limit 1로 stale entry 고착.
- CCP 업데이트 지연으로 규칙 미적용, ARP 바인딩 정상 시 문제 없음.

### 해결 방안
1. 근본 해결: NSX 4.1.1 + ESXi 8.0 GA 이상 업그레이드 적용.
   - C-VDS 전환 완료 후 가능하므로 현재 불가임.
   - Workaround 핵심: VM Tools IP 제거 시 ARP Snooping IP 정상 유지.
2. Workaround #1: 신규 ip-discovery-profile 생성, TOFU off 후 ARP binding limit 2 이상 설정으로 정상 IP 추가 적용.
   - Segment별 적용, CMP 삭제 가능 확인 필요. Stale entry 무시하거나 ignored bindings로 관리.
3. Workaround #2: Ignored bindings로 잘못된 ARP IP 제거, 정상 IP 갱신 적용.
   - VM별 작업, default profile 변경 없음. 다중 IP VM(예: postgresql)은 #1 필수.

수동 작업 불가능(1200개 segment)하므로 벤더에 일괄 적용 요청: 
- 다중 VM Tools IP VM 검색 후 #1 일괄.
- 불일치 IP VM 검색 후 #2 일괄.

### 추가 사항
- GFW도 dynamic addrset으로 vMotion 영향 받음.
- VM Template 172 대역 제거로 최초 ARP 바인딩 정상화 적용 필요.
