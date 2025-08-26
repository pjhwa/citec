---
title: "OpenStack OVN 환경에서 OFPMMFC_INVALID_METER 오류 발생"
date: 2025-08-25
tags: [openstack, kubernetes, ovs, ovn, ubuntu, max_meter]
---

## 문제 분석 개요
문제 현상은 OpenStack 기반의 클라우드 환경에서 OVN(OVN: Open Virtual Network)과 OpenvSwitch(OVS)를 사용 중 발생한 네트워크 이슈다. 구체적으로, 일부 VM(Virtual Machine)이 네트워크 통신 및 접속 불가 상태가 되었고, VM 내부에서 IP 주소가 할당되지 않는 문제가 나타났다. 이는 DHCP 서버로부터 IP를 받지 못하는 것으로 보이며, 임시 조치로 Live Migration을 통해 다른 Compute Node로 이동시켰다.

로그에서 발견된 핵심 에러는 `OFPMMFC_INVALID_METER`로, 이는 OpenFlow 프로토콜에서 meter(트래픽 속도 제한 등을 위한 기능)를 추가하거나 수정할 때 발생하는 실패 코드다. OVS의 meter-features 확인 시 `max_meter=0`으로 설정되어 meter 기능을 사용할 수 없었기 때문이다. 이는 OVN이 ACL(Access Control List)이나 QoS(Quality of Service) 등을 구현할 때 meter를 사용하므로, 네트워크 흐름(flow) 설치 실패로 이어져 VM의 DHCP 요청이 처리되지 않은 원인으로 보인다.

환경 정보:
- OVS 버전: v2.17.9
- Linux kernel: 5.15
- OVN internal version: 22.03.3-20.21.0-62.4
- neutron-ovn-metadata-agent version: 24.1.1.dev59
- OS: Ubuntu 22.04
- 구성: OVS와 OpenvSwitch가 Kubernetes Pod로 운영됨

분석은 OVS/OVN 문서, 알려진 버그 리포트, 그리고 유사 사례 검색 결과를 바탕으로 한다. OVS의 meter 지원은 kernel datapath에서 Linux kernel 4.15 이상과 OVS 2.10 이상에서 가능하며, 사용자 환경(5.15 kernel, OVS 2.17)은 이를 만족하지만, 특정 상태에서 문제가 발생했다.

## 1. 커널 파라미터가 변경된 근본 원인?
먼저, "커널 파라미터 변경"이라는 표현은 약간 오해의 소지가 있을 수 있다. `max_meter`는 엄밀히 말해 Linux kernel의 직접적인 파라미터(예: sysctl나 modprobe 옵션)가 아니다. 이는 OVS datapath(패킷 처리 엔진)의 기능 쿼리 결과로, `ovs-ofctl meter-features` 명령이 datapath의 meter 지원 능력을 조회한 값이다. `max_meter=0`은 "meter를 지원하지 않음"을 의미하며, OVS가 meter를 추가하려 할 때 `OFPMMFC_INVALID_METER` 에러를 유발한다.

### 근본 원인 분석
- **발생 시점과 증상 연결**: 에러는 08-24 08:42 이후부터 지속되었고, 이 시점에 ovs-vswitchd(OVS의 주요 데몬)가 재가동되었다. 재가동 전 로그가 없다는 점은 프로세스가 비정상적으로 종료되었을 가능성을 시사한다. 재가동 후 OVS datapath가 제대로 초기화되지 않아 `max_meter=0` 상태가 되었다.
  
- **주요 원인: stale 파일(잠금 파일, 소켓, PID 파일) 잔존으로 인한 초기화 실패**
  - OVS Pod가 Kubernetes에서 운영되므로, ovs-vswitchd 재시작 시 이전 프로세스가 제대로 종료되지 않으면 `/var/run/openvswitch/` 디렉토리에 db.sock(OVSDB 소켓 파일), .pid(PID 파일), .lock(잠금 파일) 등이 남아 있을 수 있다.
  - 이 파일들이 잔존하면 새 ovs-vswitchd 인스턴스가 OVSDB(OVS 데이터베이스)에 제대로 연결되지 못하거나, datapath를 초기화할 때 오류가 발생한다. 결과적으로 datapath가 meter 기능을 인식하지 못해 `max_meter=0`으로 나타난다.
  - 유사 사례: OVS 문서와 Stack Overflow 등에서 재부팅이나 재시작 후 db.sock 파일 누락/잠금으로 연결 실패가 보고되었다. 특히 컨테이너 환경(Pod)에서 호스트 볼륨 마운트(hostPath)를 사용하면 이런 stale 파일 문제가 빈번하다.
  - 왜 08:42에 재가동되었나? 로그가 없어 정확히 알 수 없으나, Pod crash, Kubernetes scheduler에 의한 restart, 또는 외부 이벤트(예: 노드 리소스 부족, 네트워크 플랩)가 원인일 수 있다. kernel update나 module reload가 발생했다면 DKMS 빌드 실패로 kernel module 로드가 안 되어 datapath가 degrade될 수 있지만, 주어진 정보로는 stale 파일이 더 맞는 원인이다.

- **보조 원인: kernel module 로드 문제 (openvswitch.ko)**
  - Ubuntu 22.04의 기본 openvswitch-switch 패키지는 kernel module을 포함하지 않는다 (Launchpad 버그 #1979846 참조). 사용자 환경에서 OVS 2.17.9는 커스텀 빌드(소스 컴파일 또는 타 repo)로 보이므로, DKMS(Dynamic Kernel Module Support)를 사용해 kernel module을 빌드했을 가능성이 크다.
  - 재가동 시 modprobe openvswitch가 실패하면 kernel datapath 대신 userspace datapath로 fallback할 수 있지만, 초기화 오류로 meter 지원이 0으로 보일 수 있다. kernel 5.15는 meter를 지원하지만, module 버전 mismatch나 빌드 옵션 누락으로 지원이 꺼질 수 있다.
  - 사실 검증: OVS 2.17.9 릴리스 노트에서 특별한 meter 버그는 없으나, 오래된 OVN 22.03 버전에서 OVS와의 상호작용 이슈가 있을 수 있다 (OVN은 OVS를 제어하므로).

- **왜 IP 할당 실패로 이어졌나?**
  - OVN은 VM 네트워크를 위해 OpenFlow flow를 설치하는데, 여기서 meter가 사용된다 (예: rate limiting in ACL).
  - meter 추가 실패 → flow 설치 불가 → DHCP 패킷(UDP port 67/68)이 처리되지 않음 → VM에 IP 미할당.
  - neutron-ovn-metadata-agent가 metadata/DHCP를 담당하나, OVS 에러로 영향을 받음.

이 원인은 사실 기반으로, OVS/OVN 문서(intro/install/userspace, faq/issues)와 유사 버그 리포트에서 유추했다. 만약 kernel update 로그가 있다면 더 정확히 확인 가능하다.

## 2. max_meter가 0이 되지 않도록 하는 근본 조치?
임시 조치처럼 Pod 제거 후 stale 파일 삭제(ovsdb lock, socket, PID 파일)하고 재배포하면 `max_meter:200000`으로 정상화되는 점을 고려해, 재발 방지를 위한 근본 조치를 제안한다. 목표는 OVS 초기화의 안정성과 datapath의 meter 지원을 보장하는 것이다.

### 근본 조치 단계
1. **Pod 시작 스크립트 수정: stale 파일 자동정리**
   - OVS Pod의 entrypoint나 init container에 cleanup 로직 추가.
   - 예시 쉘 스크립트 (Pod의 컨테이너 내에서 실행):
     ```
     #!/bin/bash
     # Stale 파일 삭제
     rm -f /var/run/openvswitch/*.pid
     rm -f /var/run/openvswitch/*.lock
     rm -f /var/run/openvswitch/db.sock
     rm -f /var/run/openvswitch/ovs-vswitchd.pid  # 추가로 ovs-vswitchd 관련 파일

     # OVS 모듈 로드 확인 및 강제 로드
     modprobe openvswitch || echo "Failed to load openvswitch module"

     # OVS 시작
     ovs-ctl start --system-id=$(hostname)
     ```
   - Kubernetes DaemonSet이나 Deployment yaml에 volume mount 확인: /var/run/openvswitch를 hostPath로 마운트하면 호스트와 공유되므로, Pod restart 시 호스트 측 파일도 cleanup 고려.
   - 이해 쉽게: 이 스크립트는 Pod가 시작할 때마다 이전 "쓰레기" 파일을 지워 새로 시작하도록 한다. ovs-ctl은 OVS startup helper로, kernel module 로드를 자동 시도한다.

2. **datapath 타입 명시적 설정: userspace datapath 우선 사용**
   - kernel datapath에서 문제가 빈번하다면, br-int 브리지의 datapath_type을 netdev(userspace)로 설정.
   - 명령어:
     ```
     ovs-vsctl set bridge br-int datapath_type=netdev
     ```
   - 이유: userspace datapath는 kernel module 의존도가 낮아 안정적이며, meter 지원이 강력 (max_meter 보통 65536 이상, 사용자 경우 200000처럼 커스텀 가능). 성능 저하가 있지만, 컨테이너 환경에서 적합. OVS 문서(intro/install/userspace) 참조.
   - 만약 kernel datapath 필수라면, DKMS 재빌드:
     - apt install dkms openvswitch-common openvswitch-switch (하지만 2.17.9는 소스 빌드 필요).
     - 소스 빌드: `./configure --with-linux=/lib/modules/$(uname -r)/build && make && make install && make modules_install`

3. **버전 업그레이드 및 패치 적용**
   - OVN을 최신 버전(예: 24.x)으로 업그레이드: 22.03은 오래되어 안정성 이슈 가능. neutron-ovn-metadata-agent는 이미 최신이니 OVN과 맞춤.
   - OVS 2.17.9는 안정적이지만, 최신 3.x로 업그레이드 고려 (릴리스 노트 확인: meter 관련 개선).
   - Ubuntu 22.04에서 OVS kernel module을 안정적으로 사용하려면, PPA(예: ppa:openvswitch/ovs)나 소스 빌드 사용.

4. **모니터링 및 자동 복구 설정**
   - Prometheus나 ELK 스택으로 OVS 로그 모니터링: `OFPMMFC_INVALID_METER`나 `max_meter`를 키워드로 알림 설정.
   - Kubernetes liveness/readiness probe 추가: Pod에서 `ovs-ofctl meter-features br-int | grep max_meter` 실행해 값이 0이면 restart.
   - 노드 재부팅 후 자동 검사: systemd 서비스나 cron job으로 ovs module 로드 확인 (`lsmod | grep openvswitch`).

5. **테스트 및 검증**
   - 조치 후, `kubectl -n openstack exec -it $OVS_POD -c openvswitch-vswitchd -- ovs-ofctl -O OpenFlow13 meter-features br-int`로 max_meter 확인 (정상: 200000처럼 양수).
   - VM 생성/마이그레이션 테스트: DHCP 할당 확인 (`ip addr`).

이 조치는 이해하기 쉽게 단계별로 설명했으며, OVS/OVN 공식 문서와 검색된 사실(버그 리포트, 설치 가이드)을 기반으로 한다. 추가 로그나 config 파일 공유 시 더 세밀한 분석 가능하다.
