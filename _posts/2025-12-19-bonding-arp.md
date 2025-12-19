---
title: "Unidirectional link failure 상황에서의 bonding 설정"
date: 2025-12-19
tags: [linux, bonding, link, failure, arp]
categories: [Howtos, Linux]
---

### 문제 요약

**환경**  
- OS: Red Hat Enterprise Linux (RHEL) 8 또는 9 (신규 구축 서버)  
- 네트워크 bonding 모드: active-backup (mode=1)  
- 상대 장비: Cisco 스위치  
- LACP (mode=4, 802.3ad)로 변경은 현재 어려운 상황  

**발생 현상**  
active NIC에서 **단방향 링크 장애(unidirectional link failure)** 가 발생했습니다.  
- 서버 OS 측에서는 해당 NIC의 링크 상태가 **up** 으로 표시됨  
- Cisco 스위치 측에서는 해당 포트가 **down** 으로 표시됨  

이로 인해 bonding 드라이버가 active slave의 링크를 정상으로 판단하여 standby NIC로의 **failover가 발생하지 않고**, 결국 통신이 완전히 불가능해지는 현상이 발생했습니다.

**테스트로 확인된 동작**  
- 스위치 측 TX/RX 모두 정상 연결: 양측 모두 link up  
- 서버 측 TX만 연결 또는 RX만 연결:  
  → 서버는 link up으로 판단  
  → 스위치 포트는 link down으로 판단  
  (전형적인 단방향 장애 재현)

**요청 사항**  
서버 또는 스위치 측에서 링크 상태가 한쪽만 down이 되는 상황(단방향 장애)에서도 **반대쪽 링크도 자동으로 down 처리**되거나, bonding 레벨에서 이를 감지하여 **standby NIC로 정상적으로 failover** 되도록 설정할 수 있는 방법이 있는지 알려주세요.  

(LACP 변경이 어려운 상황이므로 active-backup 모드를 유지하면서 해결 가능한 방안을 우선적으로 원함)

### 문제 분석 및 해결 방향

사용자께서 설명하신 현상은 **unidirectional link failure** (단방향 링크 장애)로, 광케이블(single strand failure)이나 배선 문제에서 자주 발생합니다. 서버 쪽 NIC은 carrier signal(RX)을 받아 링크 업으로 판단하지만, 스위치 쪽은 TX 신호를 받지 못해 링크 다운으로 판단하는 불일치가 원인입니다.

이로 인해 active-backup 모드(mode=1) bonding에서 miimon 기반 모니터링만 사용할 경우 active slave의 물리적 링크가 업으로 보이므로 failover가 발생하지 않습니다.

**목표**: 한쪽(서버 또는 스위치)에서 링크 다운만 발생해도 반대쪽도 효과적으로 다운으로 처리하여 bonding failover를 유도하고 통신을 유지하는 것.

**제약**: LACP(mode=4, 802.3ad) 변경이 어렵고, Cisco UDLD(UniDirectional Link Detection)는 Linux와 호환성 문제로 aggressive 모드 사용 시 오히려 정상 포트가 errdisable 될 수 있어 추천하지 않습니다.

**추천 해결책**: 서버 쪽 Linux bonding에서 **ARP link monitoring**을 활성화합니다. 이는 L2 레벨에서 실제 연결성(ARP reply 수신 여부)을 확인하므로 unidirectional 장애를 논리적으로 감지하고 failover를 유도합니다.

- miimon(MII polling)은 물리적 carrier 기반으로 unidirectional을 완벽히 감지하지 못할 수 있습니다.
- ARP monitoring은 ARP request를 주기적으로 보내 reply를 확인하며, reply가 없으면 slave를 down으로 간주합니다.
- Kernel bonding 드라이버에서는 miimon과 arp_interval을 동시에 사용하지 않는 것을 권장합니다(하나만 활성화).

따라서 miimon을 비활성화(miimon=0)하고 ARP monitoring만 사용합니다.

**주의사항**:
- 네트워크 설정 변경은 통신 단절을 유발할 수 있습니다. **유지보수 창구에서 수행**하고, 가능하면 콘솔 접근을 확보하세요.
- 변경 전 현재 설정 백업: `nmcli con show <bond-name> > backup.txt`
- 잘못된 arp_ip_target 지정 시 불필요한 failover가 발생할 수 있으니, 안정적인 타겟(예: default gateway)을 선택하세요.
- ARP monitoring은 약간의 ARP 트래픽을 발생시킵니다(간격에 따라 다름).

### 단계별 설정 방법 (RHEL 8/9, NetworkManager 사용 추천)

1. **현재 bonding 설정 확인**
   ```bash
   nmcli con show <bond-name>  # 예: bond0
   cat /proc/net/bonding/<bond-name>
   ip link show <slave1> up  # slave interface link 상태 확인 (예: eno1, eno2)
   ```

2. **ARP monitoring 활성화 (nmcli 사용)**
   - bond 연결 수정 (miimon 비활성화, ARP 활성화):
     ```bash
     sudo nmcli con mod <bond-name> bond.options "mode=active-backup,miimon=0,arp_interval=500,arp_ip_target=192.168.1.1"
     ```
     - **arp_interval**: ARP 요청 주기(ms). 500~1000 추천 (빠른 감지 위해 200~500, 너무 작으면 트래픽 과다).
     - **arp_ip_target**: ARP 타겟 IP (같은 L2 네트워크 내, 항상 응답하는 호스트). 여러 개 지정 가능 (콤마 구분, 최대 16개). 예: gateway IP + 다른 서버 IP.
       - 예시: "arp_interval=500,arp_ip_target=10.0.0.1,10.0.0.254"

   - 추가 옵션 (선택, 안정성 향상):
     - primary=<slave-ifname>: 기본 active slave 지정 (예: eno1).
     - downdelay=200: down 판단 지연(ms, flapping 방지).
     - updelay=200: up 판단 지연.

     전체 예시:
     ```bash
     sudo nmcli con mod bond0 bond.options "mode=active-backup,miimon=0,arp_interval=500,arp_ip_target=10.0.0.1,10.0.0.254,primary=eno1,downdelay=200"
     ```

3. **변경 적용**
   ```bash
   sudo nmcli con down <bond-name>
   sudo nmcli con up <bond-name>
   ```
   - brief한 통신 단절 발생 가능. active slave 변경 시 gratuitous ARP 자동 전송.

4. **설정 확인**
   ```bash
   cat /proc/net/bonding/<bond-name>  # ARP Monitor 상태, 타겟, 간격 확인
   nmcli con show <bond-name> | grep bond.options
   journalctl -u NetworkManager -f  # 로그 모니터링
   ```

5. **테스트 방법**
   - active slave 케이블 일부(RX/TX 중 하나) 분리 → ARP reply 없음 → 수초 내 slave down 판단 → standby로 failover 확인.
   - `/proc/net/bonding/bond0`에서 "Link Failure Count" 증가 및 active slave 변경 확인.

**대안 (miimon만 사용할 경우)**: unidirectional 감지가 약하므로 추천하지 않으나, 기본 설정은 miimon=100입니다. trunk failover 지원 스위치라면 miimon으로 충분할 수 있습니다.

**스위치 쪽 추가 조치 (Cisco)**: 특별한 unidirectional 강제 down 기능은 UDLD aggressive 외에 제한적입니다. carrier-delay 조정으로 up/down 통지 지연 가능하나, 근본 해결 아님. 가능하다면 switch port에 "spanning-tree portfast trunk"나 "keepalive" 확인, 하지만 active-backup bonding에서는 제한적.

이 설정으로 unidirectional 장애 시 ARP reply 부재를 감지해 failover가 발생하며 통신이 유지됩니다. 물리적 링크 상태는 업으로 남을 수 있으나 bonding 레벨에서 slave를 비활성화하므로 문제 없음.

### 참조 출처
- [Redhat] Configuring network bonding in RHEL 9: https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/configuring_and_managing_networking/configuring-network-bonding_configuring-and-managing-networking
- [Redhat] Common bonding options reference (RHEL 9): https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html-single/configuring_and_managing_networking/index#reference_common-bonding-options_configuring-and-managing-networking
- [Kernel] Linux bonding driver documentation: https://www.kernel.org/doc/html/latest/networking/bonding.html (miimon과 arp_interval 동시 사용 금지, ARP monitoring 추천 사례 포함)
- [SNS] Kernel bonding ARP monitoring for unidirectional/fiber issues (Stack Overflow/Reddit discussions): https://serverfault.com/questions/822912/bond-active-backup-linux , https://www.reddit.com/r/sysadmin/comments/gquba/linux_bonding/
- [SNS] Cisco UDLD non-Cisco compatibility issues: https://community.cisco.com/t5/other-network-architecture/cisco-udld-with-non-cisco-device/td-p/529284

추가 질문(현재 bond 이름, slave interface, 네트워크 토폴로지, gateway IP 등)이 있으시면 더 구체적으로 조정해 드리겠습니다!
