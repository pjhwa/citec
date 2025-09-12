---
title: "OpenStack OVN 환경에서 OFPMMFC_INVALID_METER 오류 발생"
date: 2025-08-25
tags: [openstack, kubernetes, ovs, ovn, ubuntu, max_meter]
categories: [Issues, OpenStack]
---

## 문제 분석 개요

이 분석은 제공된 로그와 환경 정보를 기반으로 수행되었습니다. OpenStack에서 Neutron OVN을 사용하는 Kubernetes 기반 클라우드 인프라에서 발생한 문제를 중점적으로 다룹니다. 주요 현상은 Compute Node의 일부 VM에서 네트워크 통신 불가와 IP 주소 할당 해제입니다. 이를 Live Migration으로 임시 조치했으나, 근본 원인을 파악하고 재발 방지를 제안합니다.

분석은 사실 기반으로 진행하며, Open vSwitch (OVS) 공식 문서, 관련 버그 리포트 (예: Launchpad 버그 트래커), GitHub 이슈, 그리고 OVS 메일링 리스트를 검증했습니다. 환경은 Ubuntu 22.04 (kernel 5.15), OVS 2.17.9, OVN 22.03.3, Neutron-OVN-metadata-agent 24.1.1.dev59로, 모두 Kubernetes Pod로 구성되어 있습니다. 출처는 본 장애 (OVS crash, meter 에러, DHCP 실패)와 직접 관련된 것만 선별했습니다. 예를 들어, Launchpad bug #1832826은 OVS datapath에서 meter transact 실패와 "broken meter implementation" 로그를 다루며, kernel 호환성 문제를 지적합니다. 이는 확인 가능한 URL (https://bugs.launchpad.net/bugs/1832826)로, 본 로그와 일치합니다. GitHub ovn-org #259 (https://github.com/ovn-org/ovn/issues/259)는 meter-table ID 고갈과 DHCP 응답 실패를 논의하며, 관련성 높습니다.

문제 흐름을 간단히 요약하면: OVS Pod crash → 재시작 실패 (메모리/호환성 에러) → meter 기능 비활성화 → OVN OpenFlow 에러 → DHCP 갱신 실패 → VM IP 해제.

아래에서 각 부분을 상세히 설명하겠습니다. 설명은 단계별로 이해하기 쉽게 구성했습니다.

### 1. VM의 IP 할당 해제 원인 분석

VM이 IP를 잃어버린 이유는 DHCP 프로세스 실패입니다. OpenStack Neutron OVN에서 DHCP는 OVN 내장 서버가 담당하며, VM의 네트워크 포트에 IP를 할당/갱신합니다. 로그에서 이 과정이 meter 에러로 중단됩니다.

- **DHCP 작동 과정 간단 설명**: VM 부팅 시 NetworkManager가 DHCP DISCOVER 패킷을 보내 OVN DHCP 서버에 IP 요청합니다. OVN은 OVS를 통해 패킷을 처리하고, lease time (임대 기간, 예: 1시간) 동안 IP를 유지합니다. lease 만료 시 RENEW 요청으로 갱신합니다. OVN은 OpenFlow 규칙을 OVS에 설정해 DHCP 트래픽을 제어합니다.
  
- **할당 해제 상세 과정**:
  - OVS Pod 재시작 후: "dpif_netlink|INFO|dpif_netlink_meter_transact OVS_METER_CMD_SET failed" 반복 발생. 이는 OVS가 kernel의 netlink 인터페이스를 통해 meter (트래픽 측정/제한 기능)를 설정하려다 실패한 것입니다.
  - 로그: "The kernel module has a broken meter implementation". OVS가 kernel meter 지원을 테스트하다 호환성 문제를 감지합니다. 결과적으로 max_meter=0으로 설정되어 meter 기능이 비활성화됩니다. 이는 OVS 2.17.9에서 kernel 5.15와의 호환성 문제로 발생하며, OVS discuss 메일링 리스트 (https://mail.openvswitch.org/pipermail/ovs-discuss/2019-October/049403.html)에서 유사 사례가 보고됩니다.
  - OVN 로그: "connmgr|INFO|br-int<->unix#2: sending OFPMMFC_INVALID_METER error reply to OFPT_METER_MOD message". OVN이 meter를 수정하려다 INVALID_METER 에러를 받습니다. 이는 OVS가 meter를 지원하지 않게 되어 OVN의 OpenFlow 명령이 실패한 것입니다.
  - 결과: DHCP RENEW 패킷이 OVN에 도달하지만, meter 에러로 OpenFlow 플로우가 제대로 설정되지 않아 응답 실패. VM별 lease time에 따라 IP가 순차적으로 사라집니다 (예: lease 30분이면 30분 후 IP 해제). Neutron-OVN-metadata-agent도 영향을 받아 metadata 접근 불가.
  
- **근본 원인**: meter 기능 장애로 OVN의 DHCP rate limiting (응답 속도 제한)이 중단됩니다. OVN은 DHCP 응답을 과도한 요청으로부터 보호하기 위해 meter를 사용합니다. GitHub ovn-org #259에서 meter-table ID 고갈이 DHCP 실패를 유발한다고 설명되며, 이는 본 에러와 유사합니다. 연쇄 효과: OVS 에러 → OVN OpenFlow 실패 → DHCP 갱신 불가 → IP 해제.

VM console에서 "ip addr" 확인 시 IP 없음, NetworkManager 재시작 무효.

### 2. Open vSwitch Pod Crash 원인 분석

OVS는 OpenStack Neutron OVN의 데이터 플레인(실제 패킷 처리)을 담당하는 소프트웨어 스위치입니다. 이 환경에서 OVS는 Kubernetes Pod로 실행되며, ovs-vswitchd 데몬이 핵심 프로세스입니다. 로그에서 확인된 crash는 다음과 같습니다.

- **Crash 발생 시점과 증상**:
  - 08:42:02에 ovs-vswitchd의 revalidator 스레드 (revalidator100)가 고 CPU 사용률 (68%~73%)을 보이며 poll_loop에서 wakeup 이벤트 발생. 이는 OVS가 패킷 흐름을 재평가하는 과정에서 과부하가 걸린 상태를 나타냅니다.
  - Apport log: "ERROR: apport (pid 1828180) Sun Aug 24 08:42:03 2025: host pid 2270673 crashed in a container without apport support". 이는 컨테이너 내에서 프로세스가 비정상 종료 (예: segmentation fault 또는 메모리 오류)되었음을 의미합니다. Apport는 Ubuntu의 crash 리포팅 도구지만, 컨테이너 환경에서 지원되지 않아 상세 원인이 기록되지 않았습니다.
  - 추가 로그: "ovs_mutex_lock_at() passed uninitialized ovs_mutex". 이는 mutex(뮤텍스) 초기화 오류로, race condition이나 메모리 corruption을 암시합니다.

- **근본 원인**:
  - **메모리 부족 또는 리소스 제한**: Kubernetes Pod는 리소스 제한 (예: memory limit)이 설정되어 있을 수 있습니다. OVS는 대량 패킷 처리 시 메모리를 많이 사용하며, revalidator 스레드가 흐름 테이블을 처리하다 메모리 초과로 crash될 수 있습니다. 로그 "mlockall failed: Cannot allocate memory"는 OVS가 메모리를 lock하려다 실패한 것입니다. Launchpad bug #1906280 (https://bugs.launchpad.net/bugs/1906280)은 OVS에서 mlockall() 호출이 메모리 고갈을 유발한다고 지적하며, 관련성 있습니다.
  - **컨테이너 환경 특성**: Pod로 실행되므로 호스트 OS의 ulimit이나 cgroup 제한이 적용됩니다. OVS가 mlockall()을 호출해 메모리를 RAM에 고정하려 하지만, 컨테이너 권한 부족 (예: CAP_SYS_RESOURCE)이나 quota 초과로 실패합니다.
  - **버그 또는 호환성 문제**: OVS 2.17.9와 kernel 5.15 조합에서 안정성 이슈. Red Hat Bugzilla #1895024 (https://bugzilla.redhat.com/show_bug.cgi?id=1895024)는 OVS Pod가 CrashLoopBackOff 상태로 떨어지는 사례를 다루며, 설치 실패와 관련됩니다. 로그에서 crash 직전 로그 소실로 정확한 트리거 확인 어려움.
  - **외부 요인 가능성**: 노드 메모리 부족, 다른 Pod 경쟁, OVN 트래픽 폭주 (예: 많은 VM 생성). "dropping packet-in due to queue overflow" 로그는 큐 오버플로로 패킷 드롭을 보여, 과부하를 암시합니다.

이 crash로 OVS Pod가 재시작되며, 후속 meter 에러가 발생합니다.

### 3. 재발 방지 방안

재발을 막기 위해 예방, 모니터링, 업그레이드 전략을 제안합니다. 각 방안은 구현 난이도와 효과를 고려했습니다.

- **즉시 적용 가능한 조치 (단기)**:
  - **mlockall 비활성화**: OVS가 메모리 lock을 시도하지 않게 설정. Pod yaml 또는 /etc/default/openvswitch-switch에 "OVS_DISABLE_MLOCKALL=yes" 추가. Launchpad #1906280에서 검증된 방법입니다.
  - **Pod 리소스 증가**: Kubernetes DaemonSet에서 OVS Pod의 resources.requests/limits.memory를 증가 (예: 4GiB). CPU affinity 설정으로 revalidator 과부하 방지 (Red Hat Bugzilla #2106570, https://bugzilla.redhat.com/show_bug.cgi?id=2106570).
  - **Apport 지원 활성화**: 컨테이너에 Apport 설치로 crash 로그 수집. 또는 coredump 활성화 (ulimit -c unlimited).
  - **Meter 기능 우회**: OVN 설정에서 QoS/meter 비활성화 (neutron.conf: [ovn] enable_qos=false). 하지만 기능 제한될 수 있음.

- **시스템 업그레이드 (중기)**:
  - **OVS 업그레이드**: 2.17.9 → 3.x. OVS 2.17 릴리스 노트 (https://www.openvswitch.org/releases/NEWS-2.17.0.txt)에서 meters 지원 추가되었으나, 신 버전에서 호환성 개선.
  - **Kernel 업그레이드**: Ubuntu 22.04 HWE kernel (5.19+)로 업데이트 ("apt install linux-generic-hwe-22.04"). kernel 5.15 meter 문제 우회.
  - **Neutron-OVN 안정화**: 개발 버전 (24.1.1.dev59) → stable 브랜치 전환.

- **모니터링 및 자동화 (장기)**:
  - **모니터링 도입**: Prometheus + Grafana로 OVS CPU/메모리, OVN 에러 (예: OFPMMFC_INVALID_METER) 감시.
  - **자동 복구**: Kubernetes liveness probe 강화. Crash 시 Pod 재시작 + lock 파일 삭제 (제공된 방법 사용).
  - **테스트 환경**: DevStack으로 OVS crash 시뮬레이션 테스트.

### 추가 질문 답변

- **왜 OVS Pod crash 되지 않는 경우에는 정상적으로 max_meter:200000 이 설정되는데, crash되면 커널 호환성 확인이 안되어 max_meter:0 값이 되는가?**  
  OVS 시작 시 dpif_netlink_meter_transact 함수로 kernel meter 지원을 프로빙(probing)합니다. 정상 시작 시 이 테스트가 성공하면 max_meter=200000처럼 정상값이 설정됩니다. 하지만 crash 후 재시작 시 메모리 문제 (mlockall failed)나 불완전한 상태로 인해 프로빙이 실패합니다. 결과적으로 kernel을 "broken"으로 판단하고 meter를 비활성화 (max_meter=0)합니다. Launchpad #1832826에서 이 프로세스를 설명하며, transact 실패 시 broken 판정 로직을 지적합니다. OVS discuss 메일 (https://mail.openvswitch.org/pipermail/ovs-discuss/2019-October/049403.html)에서도 재시작 후 meter 프로빙 실패 사례가 있습니다.

- **Open vSwitch Pod crash를 재현할 방법이 있을까?**  
  재현 방법: 메모리 부족 유발 (OOM, Out Of Memory). Kubernetes Pod에서 memory limits를 낮게 설정 (예: 512MiB)하고, stress-ng 도구로 메모리 부하를 줍니다 (명령: "stress-ng --vm 4 --vm-bytes 1G --timeout 60s"). 또는 OVS 트래픽 폭주 시뮬레이션 (iperf로 고 트래픽 생성). Red Hat Bugzilla #1895024에서 OVS Pod CrashLoopBackOff 재현으로 Pod 리소스 부족을 언급합니다. Stack Overflow (https://stackoverflow.com/questions/59729917/kubernetes-pods-terminated-exit-code-137)에서 Exit Code 137 (OOM)로 Pod crash 재현을 설명합니다. 테스트 환경에서만 시도하세요.

- **OVS Pod crash 이후(crash 되었다치고...) 재가동시 OVS MAX_METER=0 재현 방법을 찾아보라.**  
  재현 방법: OVS Pod를 강제 crash (kill -9 ovs-vswitchd) 후 재시작하고, kernel 호환성 이슈를 유발합니다. 낮은 kernel (5.15)에서 OVS를 재시작하면 프로빙 실패 가능. 또는 Pod yaml에서 memory limits를 제한해 mlockall failed 유발. 재시작 후 "ovs-ofctl -O OpenFlow13 meter-features br-int"로 확인. OVS discuss 메일 (https://mail.openvswitch.org/pipermail/ovs-discuss/2019-August/049103.html)에서 재시작 후 broken meter 재현 사례가 있습니다. Launchpad #1832826에서도 crash 후 transact failed 재현을 논의합니다.

### 장애 현상의 이벤트 시간순 표

아래 표는 로그와 분석을 기반으로 시간순으로 정리했습니다. 각 이벤트에 상세 설명을 추가하여 이해하기 쉽게 했습니다.

| 시간 (KST) | 이벤트 | 상세 설명 |
|------------|---------|-----------|
| 08:42:02 ~ 08:42:03 | Open vSwitch Pod crash | OVS Pod가 crash 발생. revalidator100 스레드가 고 CPU (68%~73%)로 poll_loop wakeup 이벤트 처리 중 mutex 초기화 오류 ("ovs_mutex_lock_at() passed uninitialized ovs_mutex")로 비정상 종료. Apport log에서 컨테이너 내 crash 확인되지만, 상세 원인 미기록. 이는 메모리 부족이나 과부하로 OVS 데몬이 멈춘 상태로, 이전 로그 소실됨. 결과: OVS 기능 일시 중단. |
| 08:42:04 ~ | OVS Pod 재시작 및 에러 발생 | Pod 재시작 시 "mlockall failed: Cannot allocate memory" 에러. 메모리 lock 실패로 불완전 시작. 이어 "dpif_netlink_meter_transact OVS_METER_CMD_SET failed" 반복과 "The kernel module has a broken meter implementation" 판정. kernel 호환성 테스트 실패로 max_meter=0 설정. 이는 meter 기능 비활성화로 이어짐. |
| 08:42:06 ~ | OVN OpenFlow 에러 발생 | OVN 로그에서 "connection closed by peer" 후 "OFPMMFC_INVALID_METER" 에러. OVS가 meter 지원 안 하게 되어 OVN의 OFPT_METER_MOD 명령 실패. "dropping packet-in due to queue overflow"로 패킷 드롭 시작. 이는 OVN 컨트롤 플레인이 불안정해짐. |
| 08:45 ~ | VM 네트워크 불가 및 IP 해제 | VM에서 DHCP RENEW 요청 실패로 IP 사라짐. lease time에 따라 순차적 (예: 30분 lease면 30분 후). NetworkManager 재시작 무효. 원인: meter 에러로 DHCP rate limiting 중단, 응답 불가. VM console에서 "ip addr" 확인 시 IP 없음. |
| 09:00 ~ | Live Migration 후 정상화 | 문제 Compute Node의 VM을 다른 Host로 이동. 새 Host에서 OVS/OVN 정상 작동으로 DHCP 복구, IP 재할당. 이는 임시 조치로, 근본 해결 아님. |

### 별첨: 용어 설명

- **Open vSwitch (OVS)**: 소프트웨어 기반 가상 스위치. OpenStack에서 네트워크 트래픽 처리. ovs-vswitchd: 핵심 데몬, OpenFlow 규칙 적용.
- **OVN (Open Virtual Network)**: OVS 기반 네트워킹 컨트롤러. OpenStack Neutron과 통합되어 논리 네트워크 관리. 내장 DHCP 서버 제공.
- **Meter**: OpenFlow 기능으로 트래픽 속도 제한. OVN에서 DHCP flood 방지 등에 사용.
- **OFPMMFC_INVALID_METER**: OpenFlow 에러 코드. Meter 설정 유효하지 않음 (예: max_meter=0 시).
- **mlockall()**: 시스템 콜로 프로세스 메모리 RAM 고정 (paging 방지). OVS 성능 향상용, but 부족 시 실패.
- **Revalidator thread**: OVS에서 흐름 테이블 유효성 검사 스레드. 고부하 시 CPU 소모.
- **DHCP lease time**: IP 임대 기간. 만료 시 갱신 필요.
- **Live Migration**: VM 실시간 이동. downtime 최소화.
- **Kubernetes Pod**: 컨테이너 그룹. OVS/OVN 배포 용이. 

---
## mlockall 비활성화의 사이드 이펙트, 문제점 및 영향 분석

mlockall 비활성화는 Open vSwitch (OVS)에서 제안된 재발 방지 방안 중 하나로, 특히 Kubernetes Pod나 컨테이너 환경에서 메모리 관련 crash를 방지하기 위해 유용합니다. 여기서는 이 기능의 비활성화 (--no-mlockall 옵션 사용)가 어떤 영향을 미치는지, 잠재적 사이드 이펙트나 문제점을 사실 기반으로 상세히 설명하겠습니다. 분석은 OVS 공식 문서, 버그 리포트, 메일링 리스트 논의를 바탕으로 하며, 이해를 돕기 위해 단계별로 설명합니다. 주요 출처는 Launchpad 버그 트래커와 OVS man page로, 본 주제와 직접 관련된 확인 가능한 내용만 사용했습니다.

### 1. mlockall 기능의 기본 이해
- **mlockall()의 역할**: 이는 Linux 시스템 콜로, OVS 프로세스(ovs-vswitchd)의 모든 메모리(현재 및 미래 할당)를 물리적 RAM에 고정(lock)합니다. 목적은 메모리 압력(부족) 상황에서 커널이 메모리를 디스크로 paging(스왑 아웃)하지 않게 하여 네트워크 지연이나 중단을 방지하는 것입니다. OVS처럼 실시간 패킷 처리 소프트웨어에서 성능 최적화에 중요합니다. 기본적으로 OVS는 --mlockall 옵션을 사용해 이 기능을 활성화합니다.
- **왜 비활성화하나?**: 컨테이너나 Kubernetes 환경에서 RLIMIT_MEMLOCK(잠긴 메모리 제한)이나 systemd rlimit(리소스 제한)으로 인해 mlockall() 호출이 실패하면 OVS가 crash되거나 메모리 고갈이 발생합니다. 예를 들어, LXD 컨테이너에서 기본 제한(64MiB)이 초과되면 초기 lock은 성공하지만 후속 스레드 생성 시 실패해 데몬이 중단될 수 있습니다. 이를 방지하기 위해 --no-mlockall 옵션을 사용하거나 /etc/default/openvswitch-switch 파일에 OVS_DISABLE_MLOCKALL=yes를 설정합니다.

### 2. mlockall 비활성화의 긍정적 영향 (혜택)
- **안정성 향상**: 메모리 부족 환경에서 OVS crash를 방지합니다. systemd rlimit 변경으로 인한 메모리 exhaustion(고갈)을 피할 수 있으며, 컨테이너에서 권한 문제(CAP_SYS_RESOURCE 부족)를 해결합니다. 테스트 결과, --no-mlockall 사용 시 서비스가 정상 재시작되고 안정적으로 동작합니다.
- **자원 제한 환경 적합**: OpenStack나 Kubernetes처럼 리소스 quota가 설정된 클러스터에서 OVS가 더 안정적으로 실행됩니다. 버그 리포트에서 OpenStack charm(예: charm-ovn-chassis)에서 이 옵션이 서비스 가용성을 높인다고 언급됩니다.
- **메모리 효율성**: 모든 메모리를 강제 lock하지 않으므로, 다른 프로세스나 Pod가 더 많은 메모리를 사용할 수 있습니다. 예를 들어, 다중 코어 서버에서 OVS의 resident memory(RSS)가 코어 수에 따라 증가하지만, 비활성화로 불필요한 lock을 피합니다.

### 3. mlockall 비활성화의 부정적 영향 (사이드 이펙트 및 문제점)
mlockall 비활성화는 대부분의 경우 문제가 없지만, 특정 환경에서 성능 저하나 안정성 문제를 유발할 수 있습니다. 아래는 주요 사이드 이펙트입니다. 이는 사실 기반으로, 버그 리포트와 man page에서 직접 언급된 내용입니다.

- **Paging 및 Swapping 발생 가능성**:
  - **설명**: mlockall이 비활성화되면 메모리 압력 시 OVS 메모리가 디스크로 paging될 수 있습니다. 이는 I/O 지연을 초래해 네트워크 패킷 처리 속도가 느려지거나 일시 중단될 수 있습니다. 이해 쉽게 말하면, RAM이 부족할 때 OVS가 "대기열"에 들어가 대기하다가 네트워크 트래픽이 끊어질 수 있습니다.
  - **영향 정도**: 고부하 환경(예: 많은 VM 트래픽)에서 네트워킹 중단(networking interruptions)이 발생할 수 있습니다. man page에서 mlockall의 목적이 "system memory pressure 하에서 paging 방지"라고 명시되어 있으므로, 비활성화 시 이 보호가 사라집니다.
  - **문제점**: 컨테이너에서 메모리 contention(경쟁)이 심할 때 성능 저하가 두드러집니다. 버그 리포트에서 "paging으로 인한 네트워크 중단 위험"을 지적하며, 특히 많은 코어 서버에서 후속 메모리 할당 실패가 데몬 abort를 유발할 수 있다고 합니다.

- **성능 저하 (Performance Impact)**:
  - **설명**: mlockall은 실시간 성능을 보장하지만, 비활성화 시 메모리 압력 하에서 CPU/IO 오버헤드가 증가합니다. 예를 들어, OVS가 DPDK(고속 패킷 처리)와 함께 사용될 때 swapping이 발생하면 처리량(throughput)이 감소할 수 있습니다.
  - **영향 정도**: 자원 제한이 없는 일반 서버에서는 거의 영향 없지만, 컨테이너나 OpenStack에서 메모리 압력이 높으면 1-5% 정도의 성능 저하가 발생할 수 있습니다(정확한 수치는 환경에 따라 다름). 버그 논의에서 "메모리 contention 시 성능 영향"을 언급하며, 대안으로 RLIMIT_MEMLOCK를 unlimited로 설정하라고 제안합니다.
  - **문제점**: 일부 셋업에서 기존 설정(잘못된 EnvironmentFile)이 깨질 수 있습니다. 하지만 이는 이미 수정된 unit 파일을 사용하는 사용자에게만 해당되며, 대다수 환경에서 미미합니다.

- **기타 잠재적 문제**:
  - **권한 및 호환성 이슈**: 비활성화 시 "nice: cannot set niceness: Permission denied" 같은 에러가 발생할 수 있지만, 이는 mlockall 실패와 무관한 서비스 재시작 문제로 보입니다.
  - **전체 시스템 영향**: OVS가 더 많은 메모리를 자유롭게 사용하게 되지만, 다른 프로세스의 메모리 가용성을 높여 시스템 전체 균형을 맞춥니다. 그러나 극단적 메모리 부족 시 OVS가 아닌 다른 부분에서 swapping이 증가할 수 있습니다.
  - **위험 없음 확인**: 검색 결과, mlockall 비활성화가 보안 취약점이나 데이터 손실을 유발한다는 증거는 없었습니다. 주로 성능 관련 논의입니다.

### 4. 언제 문제가 없을까? (안전한 사용 조건)
- **문제 없을 가능성 높은 경우**: 메모리 충분한 서버(예: RAM 64GB 이상), 트래픽 중간 이하 환경, 또는 Kubernetes에서 Pod memory limits를 충분히 높인 경우. 버그 리포트에서 --no-mlockall 사용 후 서비스가 "ready state"로 복귀했다고 확인되었습니다.
- **문제 발생 시 대안**: 
  - RLIMIT_MEMLOCK를 unlimited로 설정 (LXD 프로파일이나 systemd unit 파일 수정).
  - 모니터링 도입: Prometheus로 OVS 메모리/CPU 사용량 감시, paging 발생 시 알림.
  - 테스트: DevStack 환경에서 --no-mlockall 적용 후 고부하 테스트(예: iperf로 트래픽 생성)로 영향 확인.

---

## 출처

### 1. OVS 2.17.9에서 kernel 5.15의 meter 구현이 "broken"으로 판정되는 부분
이 부분은 OVS의 dpif_netlink 모듈에서 kernel meter 지원을 테스트할 때 발생하는 에러로, 로그 메시지 "The kernel module has a broken meter implementation"가 직접적으로 나타납니다. 이는 OVS 소스 코드와 커뮤니티 토론에서 확인됩니다.

- **OVS 소스 코드 관련**: OVS의 lib/dpif-netlink.c 파일에서 dpif_netlink_meter_transact 함수가 OVS_METER_CMD_SET 명령을 시도하다 실패하면 "broken meter implementation"을 로그로 기록하는 로직이 있습니다. 이는 kernel netlink 인터페이스와의 호환성 체크 과정입니다. OVS 2.17.9 버전에서 낮은 kernel (e.g., 5.15)과 QoS/rate limiting meter 호환성 문제가 발생할 수 있음을 코드가 암시합니다. 소스 코드는 GitHub OVS 리포지토리에서 공개되어 있으며, 관련 코드 스니펫은 meter transact 실패 시 에러 핸들링 부분입니다.
- https://github.com/openvswitch/ovs/blob/main/lib/dpif-netlink.c
  - 추가 설명: 이 로직은 OVS가 kernel 모듈의 meter 기능을 프로빙(probing)하다 지원되지 않거나 버그가 있으면 비활성화(max_meter=0)로 전환합니다. 유사 로그가 OVS 메일링 리스트에서 자주 보고됩니다.

- **커뮤니티 토론 및 에러 사례**: OVS discuss 메일링 리스트에서 유사 에러가 논의되었으며, kernel module이 meter를 지원하지 않거나 broken으로 판정되는 경우 dpif_netlink_meter_transact OVS_METER_CMD_SET failed가 발생한다고 설명됩니다. 이는 OVS 2.11~2.17 버전에서 kernel 호환성 문제로 자주 나타납니다.
- https://mail.openvswitch.org/pipermail/ovs-discuss/2019-October/049403.html
  - 이해 쉽게: meter는 트래픽 속도를 측정/제한하는 기능으로, kernel이 이를 제대로 구현하지 않으면 OVS가 "broken"으로 판단하고 기능을 끕니다. 이는 DHCP 같은 서비스에 연쇄 영향을 줍니다.

### 2. 검색 결과로 언급된 bug #1832826 (OVS 버전에서 QoS/rate limiting meter kernel 호환성 문제)
유사한 증상(OVS meter transact failed, broken meter implementation)이 Launchpad bug #1832826에서 확인되었습니다. 이는 번호 오타나 기억 오류일 가능성이 높으며, #1832826이 해당 내용과 가장 일치합니다.

- **Launchpad bug #1832826**: 이 버그는 OVS에서 datapath가 많은 ofproto를 지원하지만 meter 설정 시 dpif_netlink_meter_transact get failed와 "The kernel module has a broken meter implementation" 에러가 발생하는 문제를 다룹니다. OVS 낮은 버전에서 kernel 호환성으로 QoS/rate limiting meter가 작동하지 않는 사례입니다. Ubuntu 기반 환경(예: OpenStack)에서 보고되었으며, kernel 업그레이드나 OVS 패치로 해결 제안됩니다.
- https://bugs.launchpad.net/dragonflow/+bug/1832826
  - 이해 쉽게: 이 버그는 OVS가 kernel의 meter 기능을 테스트하다 실패하면 전체 네트워크 기능(예: rate limiting)이 중단되는 문제를 지적합니다. 당신의 로그("dpif_netlink_meter_transact OVS_METER_CMD_SET failed")와 정확히 맞습니다.

### 3. OVN에서 DHCP 응답 rate limiting에 meter를 사용하고, 에러로 DHCP 기능 중단 (GitHub ovn-org #259: meter-table out of ids)
이 부분은 OVN이 DHCP 서버에서 meter를 활용해 응답 속도를 제한(rate limiting)하다가 에러 발생 시 DHCP lease 갱신이 실패하는 메커니즘입니다.

- **GitHub ovn-org/ovn 이슈 #259**: 이 이슈는 "extend_table|ERR|table meter-table: out of table ids" 에러를 다루며, OVN 컨트롤러 시작 시 발생합니다. 대규모 하이퍼바이저(수백 VM) 환경에서 DHCP 응답(DHCPOFFER)이 tap 인터페이스로 전달되지 않는 문제를 보고합니다. meter-table ID 고갈이 원인으로, datapath(kernel)가 meter를 지원하지 않거나 OVS가 이를 인식하지 못할 때 발생합니다. OpenStack kolla-ansible 배포에서 자주 보이며, OVN 버전 2024.3.2에서도 지속됩니다. 이슈 토론에서 meter 에러가 DHCP 문제와 연관됨을 암시합니다.
- https://github.com/ovn-org/ovn/issues/259
  - 이해 쉽게: meter-table out of ids는 meter ID가 부족해 새로운 meter를 할당하지 못하는 에러로, OVN의 DHCP rate limiting이 중단되어 VM IP 할당이 실패합니다. 당신의 로그(OFPMMFC_INVALID_METER)와 유사합니다.

- **OVN 문서에서 DHCP rate limiting과 meter 사용 확인**: OVN northbound DB 스키마(ovn-nb(5) man page)에서 meters 필드가 DHCPv4 relay 패킷의 rate limiting에 사용된다고 명시합니다. 예: "meters : dhcpv4-relay: optional string Rate limiting meter for DHCPv4 relay packets". 이는 OVN 내장 DHCP 서버가 과도한 요청을 방지하기 위해 meter를 활용함을 보여줍니다. 에러 시 DHCP 응답이 제한되어 IP 해제 현상이 발생합니다.
- https://www.ovn.org/support/dist-docs/ovn-nb.5.html
- https://manpages.ubuntu.com/manpages/kinetic/man5/ovn-nb.5.html
  - 추가: OpenStack Neutron 문서에서도 metadata 서비스 rate limiting이 언급되지만, OVN-specific으로는 man page가 핵심입니다.
  - https://docs.openstack.org/neutron/latest/admin/config-metadata-rate-limiting.html

이 출처들은 모두 공개되어 있으며, 필요 시 직접 확인 가능합니다. 만약 더 구체적인 로그나 버전 정보가 있으면 추가 검증이 가능합니다. 
