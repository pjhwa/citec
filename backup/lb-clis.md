| 명령어 Syntax | 설명 |
|---------------|------|
| scpcli loadbalancer lb-server-group-member add --lb_server_group_id (value) --members (value) | 서버 그룹 멤버를 추가합니다. lb_server_group_id는 서버 그룹 ID, members는 추가할 멤버 목록(예: IP와 포트 조합)입니다. 이 명령은 기존 서버 그룹에 새로운 백엔드 서버를 등록하여 부하 분산 대상으로 만듭니다. |
| scpcli loadbalancer lb-health-check create --protocol (value) --port (value) --interval (value) --timeout (value) --healthy_threshold (value) --unhealthy_threshold (value) --path (value) --response_code (value) | LB 헬스 체크를 생성합니다. protocol은 TCP 또는 HTTP, port는 헬스 체크 포트, interval은 체크 간격(초), timeout은 타임아웃(초), healthy_threshold와 unhealthy_threshold는 건강/비건강 임계값, path는 HTTP 경로, response_code는 예상 응답 코드입니다. 이 명령은 서버 상태를 모니터링하기 위한 헬스 체크를 설정합니다. |
| scpcli loadbalancer lb-listener create --loadbalancer_id (value) --protocol (value) --port (value) --lb_server_group_id (value) --certificate_id (value) --priority (value) | LB 리스너를 생성합니다. loadbalancer_id는 LB ID, protocol은 HTTP/HTTPS/TCP, port는 리스너 포트, lb_server_group_id는 연결 서버 그룹, certificate_id는 SSL 인증서 ID(HTTPS 시), priority는 우선순위입니다. 이 명령은 외부 트래픽을 수신하고 백엔드로 라우팅하는 리스너를 만듭니다. |
| scpcli loadbalancer lb-server-group create --loadbalancer_id (value) --name (value) --lb_method (value) --protocol (value) --connection_limit (value) --description (value) | LB 서버 그룹을 생성합니다. loadbalancer_id는 LB ID, name은 그룹 이름, lb_method은 ROUND_ROBIN 또는 LEAST_CONNECTION, protocol은 백엔드 프로토콜, connection_limit은 연결 제한, description은 설명입니다. 이 명령은 백엔드 서버들을 그룹화하여 부하 분산을 관리합니다. |
| scpcli loadbalancer loadbalancer create --vpc_id (value) --subnet_id (value) --name (value) --type (value) --description (value) | LB를 생성합니다. vpc_id는 VPC ID, subnet_id는 서브넷 ID, name은 LB 이름, type은 APPLICATION 또는 NETWORK, description은 설명입니다. 이 명령은 부하 분산 인스턴스를 프로비저닝합니다. |
| scpcli loadbalancer loadbalancer-public-nat-ip create --loadbalancer_id (value) | 퍼블릭 NAT IP를 LB에 할당합니다. loadbalancer_id는 LB ID입니다. 이 명령은 LB를 외부 인터넷에 노출하기 위한 공용 IP를 연결합니다. |
| scpcli loadbalancer lb-health-check delete --lb_health_check_id (value) | LB 헬스 체크를 삭제합니다. lb_health_check_id는 헬스 체크 ID입니다. 이 명령은 더 이상 사용하지 않는 헬스 체크를 제거합니다. 상태 ACTIVE (CURRENT)이며, 버전 1.0, 생성/수정 202507, 최소 지원 20260701입니다. |
| scpcli loadbalancer lb-listener delete --lb_listener_id (value) | LB 리스너를 삭제합니다. lb_listener_id는 리스너 ID입니다. 이 명령은 트래픽 수신 리스너를 제거합니다. |
| scpcli loadbalancer lb-server-group delete --lb_server_group_id (value) | LB 서버 그룹을 삭제합니다. lb_server_group_id는 서버 그룹 ID입니다. 이 명령은 백엔드 그룹을 제거합니다. |
| scpcli loadbalancer loadbalancer delete --loadbalancer_id (value) | LB를 삭제합니다. loadbalancer_id는 LB ID입니다. 이 명령은 전체 LB 인스턴스를 종료합니다. |
| scpcli loadbalancer loadbalancer-public-nat-ip delete --public_nat_ip_id (value) | 퍼블릭 NAT IP를 삭제합니다. public_nat_ip_id는 NAT IP ID입니다. 이 명령은 공용 IP 할당을 해제합니다. |
| scpcli loadbalancer lb-health-check list --loadbalancer_id (value) | LB 헬스 체크 목록을 조회합니다. loadbalancer_id는 LB ID입니다. 이 명령은 연결된 헬스 체크를 나열합니다. |
| scpcli loadbalancer lb-listener list --loadbalancer_id (value) | LB 리스너 목록을 조회합니다. loadbalancer_id는 LB ID입니다. 이 명령은 LB의 리스너를 나열합니다. |
| scpcli loadbalancer lb-server-group-member list --lb_server_group_id (value) | 서버 그룹 멤버 목록을 조회합니다. lb_server_group_id는 서버 그룹 ID입니다. 이 명령은 그룹 내 백엔드 멤버를 나열합니다. |
| scpcli loadbalancer lb-server-group list --loadbalancer_id (value) | LB 서버 그룹 목록을 조회합니다. loadbalancer_id는 LB ID입니다. 이 명령은 LB의 서버 그룹을 나열합니다. |
| scpcli loadbalancer loadbalancer-certificate list --loadbalancer_id (value) | LB 인증서 목록을 조회합니다. loadbalancer_id는 LB ID입니다. 이 명령은 SSL 인증서를 나열합니다. |
| scpcli loadbalancer loadbalancer list | LB 목록을 조회합니다. 이 명령은 모든 LB를 나열합니다. |
| scpcli loadbalancer lb-server-group-member remove --member_id (value) --lb_server_group_id (value) | 서버 그룹 멤버를 제거합니다. member_id는 멤버 ID, lb_server_group_id는 서버 그룹 ID입니다. 이 명령은 백엔드 서버를 그룹에서 제외합니다. |
| scpcli loadbalancer lb-health-check set --lb_health_check_id (value) --protocol (value) --port (value) --interval (value) --timeout (value) --healthy_threshold (value) --unhealthy_threshold (value) --path (value) --response_code (value) | LB 헬스 체크를 업데이트합니다. lb_health_check_id는 헬스 체크 ID, 나머지 옵션은 생성 시와 동일합니다. 이 명령은 기존 헬스 체크 설정을 변경합니다. |
| scpcli loadbalancer lb-listener set --lb_listener_id (value) --protocol (value) --port (value) --lb_server_group_id (value) --certificate_id (value) --priority (value) | LB 리스너를 업데이트합니다. lb_listener_id는 리스너 ID, 나머지 옵션은 생성 시와 동일합니다. 이 명령은 리스너 설정을 수정합니다. |
| scpcli loadbalancer lb-server-group set --lb_server_group_id (value) --lb_method (value) --protocol (value) --connection_limit (value) --description (value) | LB 서버 그룹을 업데이트합니다. lb_server_group_id는 서버 그룹 ID, 나머지 옵션은 생성 시와 동일합니다. 이 명령은 그룹 설정을 변경합니다. |
| scpcli loadbalancer lb-server-group-member set --member_id (value) --lb_server_group_id (value) --port (value) --weight (value) --enabled (value) | 서버 그룹 멤버를 업데이트합니다. member_id와 lb_server_group_id는 ID, port는 포트, weight는 가중치, enabled는 활성화 여부입니다. 이 명령은 멤버 설정을 수정합니다. |
| scpcli loadbalancer loadbalancer set --loadbalancer_id (value) --name (value) --description (value) --type (value) | LB를 업데이트합니다. loadbalancer_id는 LB ID, 나머지 옵션은 생성 시와 동일합니다. 이 명령은 LB 메타데이터를 변경합니다. |
| scpcli loadbalancer lb-health-check show --lb_health_check_id (value) | LB 헬스 체크 상세를 조회합니다. lb_health_check_id는 헬스 체크 ID입니다. 이 명령은 헬스 체크 세부 정보를 출력합니다. |
| scpcli loadbalancer lb-listener show --lb_listener_id (value) | LB 리스너 상세를 조회합니다. lb_listener_id는 리스너 ID입니다. 이 명령은 리스너 세부 정보를 출력합니다. |
| scpcli loadbalancer lb-server-group show --lb_server_group_id (value) | LB 서버 그룹 상세를 조회합니다. lb_server_group_id는 서버 그룹 ID입니다. 이 명령은 그룹 세부 정보를 출력합니다. |
| scpcli loadbalancer lb-server-group-member show --member_id (value) --lb_server_group_id (value) | 서버 그룹 멤버 상세를 조회합니다. member_id와 lb_server_group_id는 ID입니다. 이 명령은 멤버 세부 정보를 출력합니다. |
| scpcli loadbalancer loadbalancer show --loadbalancer_id (value) | LB 상세를 조회합니다. loadbalancer_id는 LB ID입니다. 이 명령은 LB 전체 정보를 출력합니다. |
| scpcli loadbalancer loadbalancer-certificate show --certificate_id (value) | LB 인증서 상세를 조회합니다. certificate_id는 인증서 ID입니다. 이 명령은 인증서 세부 정보를 출력합니다.
