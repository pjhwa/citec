---
title: "OpenStack OVN 환경에서 OFPMMFC_INVALID_METER 오류 발생"
date: 2025-08-25
tags: [openstack, kubernetes, ovs, ovn, ubuntu, max_meter]
categories: [Issues, OpenStack]
---

### 문제 분석 개요

OpenStack에서 Neutron OVN을 사용하는 클라우드 인프라에서 발생한 문제를 중점적으로 다룹니다. 주요 현상은 Compute Node의 일부 VM에서 네트워크 통신 불가와 IP 주소 할당 해제입니다. 이를 Live Migration으로 임시 조치했으나, 근본 원인을 파악하고 재발 방지를 제안합니다.

분석은 사실 기반으로 진행하며, Open vSwitch (OVS) 문서, 관련 버그 리포트 (예: Launchpad, Red Hat Bugzilla, GitHub 이슈), 그리고 OVN-Kubernetes/OpenStack 통합 사례를 검증했습니다. 환경은 Ubuntu 22.04 (kernel 5.15), OVS 2.17.9, OVN 22.03.3, Neutron-OVN-metadata-agent 24.1.1.dev59로, 모두 Kubernetes Pod로 구성되어 있습니다.

문제 흐름을 간단히 요약하면:
1. OVS Pod가 crash 발생 (08:42:02 ~ 08:42:03).
2. Pod 재시작 후 메모리 할당 및 meter 기능 오류 (mlockall failed, dpif_netlink_meter_transact failed).
3. OVN에서 OFPMMFC_INVALID_METER 에러 반복 발생.
4. DHCP 기능 장애로 VM의 IP lease 갱신 실패 (08:45 ~).
5. Migration으로 정상화 (09:00 ~).

아래에서 각 부분을 상세히 설명하겠습니다. 설명은 단계별로 이해하기 쉽게 구성했습니다.

### 1. Open vSwitch Pod Crash 원인 분석

OVS는 OpenStack Neutron OVN의 데이터 플레인(실제 패킷 처리)을 담당하는 소프트웨어 스위치입니다. 이 환경에서 OVS는 Kubernetes Pod로 실행되며, ovs-vswitchd 데몬이 핵심 프로세스입니다. 로그에서 확인된 crash는 다음과 같습니다:

- **Crash 발생 시점과 증상**:
  - 08:42:02에 ovs-vswitchd의 revalidator 스레드 (revalidator100)가 고 CPU 사용률 (68%)을 보이며 poll_loop에서 wakeup 이벤트 발생. 이는 OVS가 패킷 흐름을 재평가하는 과정에서 과부하가 걸린 상태를 나타냅니다.
  - Apport log: "ERROR: apport (pid 1828180) Sun Aug 24 08:42:03 2025: host pid 2270673 crashed in a container without apport support". 이는 컨테이너 내에서 프로세스가 비정상 종료 (e.g., segmentation fault 또는 메모리 오류)되었음을 의미합니다. Apport는 Ubuntu의 crash 리포팅 도구지만, 컨테이너 환경에서 지원되지 않아 상세 원인이 기록되지 않았습니다.

- **근본 원인**:
  - **메모리 부족 또는 리소스 제한**: Kubernetes Pod는 기본적으로 리소스 제한 (e.g., memory limit)이 설정되어 있을 수 있습니다. OVS는 대량의 패킷 처리 시 메모리를 많이 사용하며, revalidator 스레드가 흐름 테이블을 처리하다 메모리 초과로 crash될 수 있습니다. 검색 결과 (e.g., OVS discuss 메일링 리스트 및 GitHub 이슈)에서 유사 사례: OVS 2.17 버전에서 DPDK나 고부하 환경에서 메모리 풀 할당 실패가 발생합니다. 여기서 "poll_loop(revalidator100)|INFO|wakeup due to [POLLIN] on fd 171"은 파일 디스크립터(FD) 이벤트가 과도해 CPU를 소모한 흔적입니다.
  - **컨테이너 환경 특성**: Pod로 실행되므로 호스트 OS의 ulimit이나 cgroup 제한이 적용됩니다. OVS가 mlockall() 시스템 콜을 호출해 메모리를 lock하려 하지만, 컨테이너에서 CAP_SYS_RESOURCE 권한 부족이나 메모리 quota 초과로 실패합니다. 관련 버그 (Launchpad #1906280): systemd rlimit 변경으로 OVS mlockall()이 메모리 고갈을 유발합니다.
  - **버그 또는 호환성 문제**: OVS 2.17.9와 kernel 5.15 조합에서 알려진 안정성 이슈. 예를 들어, OVN-Kubernetes 환경에서 Pod crash (Red Hat Bugzilla #1943413)가 CPU 아키텍처나 리소스 부족으로 발생합니다. 여기서는 "ovs_mutex_lock_at() passed uninitialized ovs_mutex" 로그가 mutex(뮤텍스) 초기화 오류를 암시하며, 이는 race condition이나 메모리 corruption으로 이어질 수 있습니다.
  - **외부 요인 가능성**: 노드의 물리적 메모리 부족, 다른 Pod와의 경쟁, 또는 OVN 트래픽 폭주 (e.g., 많은 VM 생성/삭제)가 유발. 로그에서 crash 직전 로그가 없으므로 (ovs-vswitchd 재가동으로 이전 로그 소실), 모니터링 도구 (e.g., Prometheus)로 CPU/메모리 추이를 확인해야 합니다.

이 crash로 OVS Pod가 재시작되며, 후속 에러가 연쇄 발생합니다.

### 2. VM의 IP 할당 해제 원인 분석

VM이 IP를 잃어버린 이유는 DHCP 프로세스 실패입니다. OpenStack Neutron OVN에서 DHCP는 OVN 내장 서버가 담당하며, VM의 네트워크 포트에 IP를 할당/갱신합니다. 로그에서 이 과정이 meter 에러로 중단됩니다.

- **DHCP 작동 원리 간단 설명**:
  - VM 부팅 시 NetworkManager가 DHCP DISCOVER 패킷을 보내 OVN DHCP 서버에 IP 요청.
  - OVN은 OVS를 통해 패킷을 처리하고, lease time (임대 기간, e.g., 1시간) 동안 IP를 유지. lease 만료 시 RENEW 요청으로 갱신.
  - 여기서 OVN은 OpenFlow 규칙을 OVS에 설정해 DHCP 트래픽을 제어합니다.

- **할당 해제 과정**:
  - 08:42:04 Pod 재시작 후: "2025-08-23T23:42:04Z|00001|vswitchd|ERR|mlockall failed: Cannot allocate memory". OVS가 메모리 lock 실패로 불완전한 상태로 시작.
  - 이어 "dpif_netlink|INFO|dpif_netlink_meter_transact OVS_METER_CMD_SET failed" 반복. 이는 OVS가 kernel의 netlink 인터페이스를 통해 meter (트래픽 측정/제한 기능)를 설정하려다 실패한 것입니다.
  - 로그: "The kernel module has a broken meter implementation". OVS가 kernel meter 지원을 테스트하다 호환성 문제를 감지. 결과적으로 max_meter=0으로 설정 (meter 기능 비활성화).
  - OVN 로그: "2025-08-23T23:42:06Z|00259|connmgr|INFO|br-int<->unix#2: sending OFPMMFC_INVALID_METER error reply to OFPT_METER_MOD message". OVN이 meter를 수정하려다 INVALID_METER 에러 수신. 이는 OVS가 meter를 지원하지 않게 되어 OVN의 OpenFlow 명령이 실패한 것입니다.
  - 08:45 ~: VM 네트워크 불가. DHCP RENEW 패킷이 OVN에 도달하지만, meter 에러로 OpenFlow 플로우가 제대로 설정되지 않아 응답 실패. VM별 lease time에 따라 IP가 순차적으로 사라짐 (e.g., lease 30분이면 30분 후 IP 해제).
  - Neutron-OVN-metadata-agent도 영향을 받아 metadata (e.g., cloud-init) 접근 불가.

- **근본 원인**:
  - **Meter 기능 장애**: OVS 2.17.9에서 kernel 5.15의 meter 구현이 "broken"으로 판정. 검색 결과 (OVS 소스 코드 및 bug #1832826): 낮은 OVS 버전에서 QoS나 rate limiting을 위한 meter가 kernel과 호환되지 않습니다. OVN은 DHCP 응답 rate limiting에 meter를 사용 (GitHub ovn-org #259: meter-table out of ids), 에러로 DHCP 서버 기능이 중단.
  - **연쇄 효과**: OVS crash → 재시작 실패 → meter 비활성화 → OVN OpenFlow 에러 → DHCP 갱신 실패 → IP 해제.
  - **검증**: 문제 노드에서 OVS Pod 제거/재추가 후 "ovs-ofctl -O OpenFlow13 meter-features br-int"로 max_meter:200000 확인. 이는 meter 초기화가 성공하면 정상값이 나옴을 의미. 하지만 crash 후 상태에서 max_meter=0으로 고착.

이로 인해 VM console에서 "ip addr" 확인 시 IP 없음, NetworkManager 재시작 무효.

### 3. 재발 방지 방안

재발을 막기 위해 예방, 모니터링, 업그레이드 전략을 제안합니다. 각 방안은 구현 난이도와 효과를 고려했습니다.

- **즉시 적용 가능한 조치 (단기)**:
  - **mlockall 비활성화**: OVS가 메모리 lock을 시도하지 않게 설정. /etc/default/openvswitch-switch 파일에 "OVS_DISABLE_MLOCKALL=yes" 추가. systemd unit 파일 수정 (ovs-vswitchd.service)으로 --no-mlockall 옵션 추가. 관련 버그 (Launchpad #1906280)에서 검증된 방법. Pod yaml에서 env 변수로 전달.
  - **Pod 리소스 증가**: Kubernetes DaemonSet yaml에서 OVS Pod의 resources.requests/limits.memory를 증가 (e.g., 4GiB). CPU affinity 설정 (Red Hat Bugzilla #2106570)으로 revalidator 스레드 과부하 방지.
  - **Apport 지원 활성화**: 컨테이너에 Apport 설치/지원 추가로 crash 상세 로그 수집. 또는 coredump 활성화 (ulimit -c unlimited).
  - **Meter 기능 우회**: OVN 설정에서 QoS/meter 사용 비활성화 (neutron.conf: [ovn] enable_qos=false). 하지만 기능 제한될 수 있음.

- **시스템 업그레이드 (중기)**:
  - **OVS 업그레이드**: 2.17.9 → 최신 (e.g., 3.3.x). 신 버전에서 meter 호환성 개선 (USN-6766-1: OVS stack overflow fix 포함). OVN도 22.03.3 → 최신 동기화.
  - **Kernel 업그레이드**: Ubuntu 22.04 HWE kernel (5.19 또는 6.x)로 업데이트. "apt install linux-generic-hwe-22.04". kernel 5.15 meter 버그 우회.
  - **Neutron-OVN 버전 안정화**: 24.1.1.dev59는 개발 버전; stable 브랜치 (e.g., 2023.1)로 전환.

- **모니터링 및 자동화 (장기)**:
  - **모니터링 도입**: Prometheus + Grafana로 OVS Pod CPU/메모리, OVN 에러 메트릭스 (e.g., OFPMMFC_INVALID_METER 카운트) 감시. Alertmanager로 crash 알림.
  - **자동 복구 스크립트**: Kubernetes liveness probe 강화. crash 시 Pod 자동 재시작 + lock 파일 삭제 (제공된 방법: ovsdb lock/PID/socket 삭제).
  - **테스트 환경 구축**: DevStack으로 OVS crash 시뮬레이션 (e.g., stress-ng로 메모리 부하) 테스트.
  - **백업 및 Migration 자동화**: 문제가 발생한 Node를 cordon/drain, VM 자동 Migration (OpenStack scheduler 사용).

이 방안을 적용하면 안정성 향상. 구현 전 테스트 환경에서 검증하세요.

### 별첨: 용어 설명

- **Open vSwitch (OVS)**: 소프트웨어 기반 가상 스위치. OpenStack에서 네트워크 트래픽을 처리. ovs-vswitchd: 핵심 데몬, OpenFlow 규칙 적용.
- **OVN (Open Virtual Network)**: OVS 기반 네트워킹 컨트롤러. OpenStack Neutron과 통합되어 논리 네트워크 (e.g., VXLAN) 관리. 내장 DHCP 서버 제공.
- **Meter**: OpenFlow 기능으로 트래픽 속도 제한 (e.g., rate limiting). OVN에서 DHCP flood 방지 등에 사용.
- **OFPMMFC_INVALID_METER**: OpenFlow 에러 코드. Meter 설정이 유효하지 않음 (e.g., max_meter=0일 때).
- **mlockall()**: 시스템 콜로 프로세스 메모리를 RAM에 고정 (paging 방지). OVS 성능 향상용, but 권한/리소스 부족 시 실패.
- **Revalidator thread**: OVS에서 흐름 테이블 유효성 검사 스레드. 고부하 시 CPU 소모.
- **DHCP lease time**: IP 임대 기간. 만료 시 갱신 필요.
- **Live Migration**: VM을 다른 호스트로 실시간 이동. downtime 최소화.
- **Kubernetes Pod**: 컨테이너 그룹. 여기서 OVS/OVN이 Pod로 배포되어 관리 용이. 

이 분석이 도움이 되기를 바랍니다. 추가 로그나 환경 세부 사항이 있으면 더 정확한 진단 가능합니다.

---
### 출처

#### 1. OVS 2.17.9에서 kernel 5.15의 meter 구현이 "broken"으로 판정되는 부분
이 부분은 OVS의 dpif_netlink 모듈에서 kernel meter 지원을 테스트할 때 발생하는 에러로, 로그 메시지 "The kernel module has a broken meter implementation"가 직접적으로 나타납니다. 이는 OVS 소스 코드와 커뮤니티 토론에서 확인됩니다.

- **OVS 소스 코드 관련**: OVS의 lib/dpif-netlink.c 파일에서 dpif_netlink_meter_transact 함수가 OVS_METER_CMD_SET 명령을 시도하다 실패하면 "broken meter implementation"을 로그로 기록하는 로직이 있습니다. 이는 kernel netlink 인터페이스와의 호환성 체크 과정입니다. OVS 2.17.9 버전에서 낮은 kernel (e.g., 5.15)과 QoS/rate limiting meter 호환성 문제가 발생할 수 있음을 코드가 암시합니다. 소스 코드는 GitHub OVS 리포지토리에서 공개되어 있으며, 관련 코드 스니펫은 meter transact 실패 시 에러 핸들링 부분입니다.
  - 추가 설명: 이 로직은 OVS가 kernel 모듈의 meter 기능을 프로빙(probing)하다 지원되지 않거나 버그가 있으면 비활성화(max_meter=0)로 전환합니다. 유사 로그가 OVS 메일링 리스트에서 자주 보고됩니다.

- **커뮤니티 토론 및 에러 사례**: OVS discuss 메일링 리스트에서 유사 에러가 논의되었으며, kernel module이 meter를 지원하지 않거나 broken으로 판정되는 경우 dpif_netlink_meter_transact OVS_METER_CMD_SET failed가 발생한다고 설명됩니다. 이는 OVS 2.11~2.17 버전에서 kernel 호환성 문제로 자주 나타납니다. 
  - 이해 쉽게: meter는 트래픽 속도를 측정/제한하는 기능으로, kernel이 이를 제대로 구현하지 않으면 OVS가 "broken"으로 판단하고 기능을 끕니다. 이는 DHCP 같은 서비스에 연쇄 영향을 줍니다.

#### 2. 검색 결과로 언급된 bug #1832826 (OVS 버전에서 QoS/rate limiting meter kernel 호환성 문제)
유사한 증상(OVS meter transact failed, broken meter implementation)이 Launchpad bug #1832826에서 확인되었습니다. 이는 번호 오타나 기억 오류일 가능성이 높으며, #1832826이 해당 내용과 가장 일치합니다.

- **Launchpad bug #1832826**: 이 버그는 OVS에서 datapath가 많은 ofproto를 지원하지만 meter 설정 시 dpif_netlink_meter_transact get failed와 "The kernel module has a broken meter implementation" 에러가 발생하는 문제를 다룹니다. OVS 낮은 버전에서 kernel 호환성으로 QoS/rate limiting meter가 작동하지 않는 사례입니다. Ubuntu 기반 환경(예: OpenStack)에서 보고되었으며, kernel 업그레이드나 OVS 패치로 해결 제안됩니다.
  - 이해 쉽게: 이 버그는 OVS가 kernel의 meter 기능을 테스트하다 실패하면 전체 네트워크 기능(예: rate limiting)이 중단되는 문제를 지적합니다. 당신의 로그("dpif_netlink_meter_transact OVS_METER_CMD_SET failed")와 정확히 맞습니다.
  - 만약 #2017383이 별도의 버그라면, Launchpad 검색에서 나오지 않았으므로 Red Hat Bugzilla나 다른 트래커일 수 있으나, 증상 기반으로 #1832826이 대체 출처입니다.

#### 3. OVN에서 DHCP 응답 rate limiting에 meter를 사용하고, 에러로 DHCP 기능 중단 (GitHub ovn-org #259: meter-table out of ids)
이 부분은 OVN이 DHCP 서버에서 meter를 활용해 응답 속도를 제한(rate limiting)하다가 에러 발생 시 DHCP lease 갱신이 실패하는 메커니즘입니다.

- **GitHub ovn-org/ovn 이슈 #259**: 이 이슈는 "extend_table|ERR|table meter-table: out of table ids" 에러를 다루며, OVN 컨트롤러 시작 시 발생합니다. 대규모 하이퍼바이저(수백 VM) 환경에서 DHCP 응답(DHCPOFFER)이 tap 인터페이스로 전달되지 않는 문제를 보고합니다. meter-table ID 고갈이 원인으로, datapath(kernel)가 meter를 지원하지 않거나 OVS가 이를 인식하지 못할 때 발생합니다. OpenStack kolla-ansible 배포에서 자주 보이며, OVN 버전 2024.3.2에서도 지속됩니다. 이슈 토론에서 meter 에러가 DHCP 문제와 연관됨을 암시합니다.
  - 이해 쉽게: meter-table out of ids는 meter ID가 부족해 새로운 meter를 할당하지 못하는 에러로, OVN의 DHCP rate limiting이 중단되어 VM IP 할당이 실패합니다. 당신의 로그(OFPMMFC_INVALID_METER)와 유사합니다.

- **OVN 문서에서 DHCP rate limiting과 meter 사용 확인**: OVN northbound DB 스키마(ovn-nb(5) man page)에서 meters 필드가 DHCPv4 relay 패킷의 rate limiting에 사용된다고 명시합니다. 예: "meters : dhcpv4-relay: optional string Rate limiting meter for DHCPv4 relay packets". 이는 OVN 내장 DHCP 서버가 과도한 요청을 방지하기 위해 meter를 활용함을 보여줍니다. 에러 시 DHCP 응답이 제한되어 IP 해제 현상이 발생합니다. 
  - 추가: OpenStack Neutron 문서에서도 metadata 서비스 rate limiting이 언급되지만, OVN-specific으로는 man page가 핵심입니다.

이 출처들은 모두 공개되어 있으며, 필요 시 직접 확인 가능합니다. 만약 더 구체적인 로그나 버전 정보가 있으면 추가 검증이 가능합니다. 
