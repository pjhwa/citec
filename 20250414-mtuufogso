## RHEL 9.2와 9.5에서 MTU를 1340으로 설정하는 방법과 UDP 패킷의 IP 레벨 fragmentation을 방지하는 설정 방법을 설명하겠습니다.

---

### **1. MTU를 1340으로 설정하는 방법**

MTU(Maximum Transmission Unit)는 네트워크 인터페이스가 전송할 수 있는 최대 패킷 크기를 의미합니다. RHEL 9.2와 9.5에서 MTU를 1340으로 설정하려면 아래 단계를 따르세요. 여기서는 네트워크 인터페이스 이름이 `eth0`라고 가정합니다.

#### **(1) 현재 MTU 확인**
먼저, 현재 MTU 값을 확인합니다. 다음 명령어를 사용하세요:
```bash
ip link show eth0
```
출력에서 `mtu` 값(예: `mtu 1500`)을 확인할 수 있습니다.

#### **(2) MTU 임시 설정**
MTU를 1340으로 즉시 변경하려면 아래 명령어를 실행합니다:
```bash
ip link set eth0 mtu 1340
```
이 설정은 재부팅 시 초기화되므로, 영구 적용을 원한다면 추가 설정이 필요합니다.

#### **(3) MTU 영구 설정**
RHEL에서는 NetworkManager를 사용하여 네트워크 설정을 관리합니다. MTU를 영구적으로 설정하려면 네트워크 설정 파일을 수정해야 합니다. 아래 단계를 따르세요:
1. 네트워크 설정 파일을 엽니다:
   ```bash
   vi /etc/sysconfig/network-scripts/ifcfg-eth0
   ```
2. 파일에 다음 줄을 추가하거나 수정합니다:
   ```
   MTU=1340
   ```
3. 수정 후 네트워크 서비스를 재시작합니다:
   ```bash
   systemctl restart NetworkManager
   ```
이제 MTU가 1340으로 영구 설정됩니다.

---

### **2. UDP 패킷의 IP 레벨 Fragmentation 방지 방법**

UDP 패킷은 MTU보다 크면 IP 레벨에서 fragmentation(분할)이 발생할 수 있습니다. 이를 방지하려면 패킷 크기를 MTU에 맞게 조정해야 합니다. MTU가 1340일 때, IP 헤더(20바이트)와 UDP 헤더(8바이트)를 고려하면 최대 페이로드 크기는 다음과 같습니다:
```
1340 (MTU) - 20 (IP 헤더) - 8 (UDP 헤더) = 1312 바이트
```
따라서 UDP 패킷의 페이로드를 1312바이트 이하로 설정하면 fragmentation이 발생하지 않습니다.

#### **(1) 애플리케이션에서 패킷 크기 조정**
가장 효과적인 방법은 UDP를 사용하는 애플리케이션에서 패킷 크기를 직접 제한하는 것입니다. 예를 들어:
- **DNS 서버** 사용 시, `edns-buffer-size`를 1312 이하로 설정합니다.
- 기타 애플리케이션에서는 송신 패킷 크기를 MTU에 맞게 조정하도록 코드를 수정합니다.

#### **(2) iptables로 패킷 크기 제한**
시스템 레벨에서 fragmentation을 방지하려면 `iptables`를 사용하여 큰 UDP 패킷을 드롭할 수 있습니다. 예시 명령어는 다음과 같습니다:
```bash
iptables -A OUTPUT -p udp -m length --length 1313:65535 -j DROP
```
이 규칙은 1313바이트 이상의 UDP 패킷을 드롭합니다. 특정 포트(예: 53번 DNS)에만 적용하려면 `--dport` 옵션을 추가하세요:
```bash
iptables -A OUTPUT -p udp --dport 53 -m length --length 1313:65535 -j DROP
```

#### **(3) Path MTU Discovery (PMTUD) 고려**
PMTUD는 경로상의 최소 MTU를 감지해 패킷 크기를 조정하는 방법입니다. 하지만 UDP는 기본적으로 PMTUD를 지원하지 않으므로, 애플리케이션에서 이를 구현해야 합니다. 구현이 복잡할 경우, 위의 패킷 크기 조정 방법을 사용하는 것이 더 간단합니다.

---

### **요약**
- **MTU 설정**: `ip link set eth0 mtu 1340`으로 임시 설정하거나, `/etc/sysconfig/network-scripts/ifcfg-eth0`에 `MTU=1340`을 추가하고 `systemctl restart NetworkManager`로 영구 적용합니다.
- **Fragmentation 방지**: UDP 페이로드를 1312바이트 이하로 설정하거나, `iptables`로 큰 패킷을 드롭합니다. 애플리케이션에서 크기를 조정하는 것이 가장 권장됩니다.

---

## Ubuntu 22.04 호스트(KVM)의 VM으로 RHEL 9.2 를 운영중이다. GSO, UFO를 VM단에서 disable 할 수 있는가?

### 직접 답변

- RHEL 9.2 VM에서 GSO와 UFO를 비활성화할 수 있는 것으로 보입니다.  
- VM 내부에서 `ethtool`이나 `nmcli`를 사용하여 설정 가능하며, 가상 NIC(보통 virtio)에서 지원됩니다.  
- 그러나 호스트 설정과의 상호작용 가능성 때문에 주의가 필요합니다.  

#### 설정 방법  
- **임시 비활성화**: VM에서 다음 명령어 사용:  
  ```
  ethtool -K eth0 gso off
  ethtool -K eth0 ufo off
  ```
- **영구 비활성화**: NetworkManager를 통해:  
  ```
  nmcli connection modify eth0 ethtool.feature-gso off
  nmcli connection modify eth0 ethtool.feature-ufo off
  nmcli connection up eth0
  ```

#### 주의사항  
- 성능 저하 가능성 있으므로, 비활성화 후 네트워크 성능 테스트 권장.  
- UFO는 최근 커널에서 지원이 제한될 수 있으나, 가상 환경에서는 여전히 사용 가능할 수 있습니다.  

자세한 내용은 [Red Hat Documentation](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/configuring_and_managing_networking/configuring-ethtool-settings-in-networkmanager-connection-profiles_configuring-and-managing-networking)에서 확인하세요.

---

### 조사 보고서

RHEL 9.2를 Ubuntu 22.04 호스트(KVM)에서 가상 머신으로 운영 중인 환경에서 GSO(Generic Segmentation Offload)와 UFO(UDP Fragmentation Offload)를 VM 수준에서 비활성화할 수 있는지에 대한 상세한 분석을 진행하였습니다. 이 보고서는 관련 기술적 배경, 설정 방법, 주의사항, 그리고 관련 문서 및 사례를 포함하여 포괄적으로 다룹니다.

#### 기술적 배경  
GSO와 UFO는 네트워크 스택에서 성능을 향상시키기 위해 NIC로 특정 작업을 오프로드하는 기능입니다. GSO는 TCP 및 UDP 패킷의 세그먼테이션을, UFO는 UDP 패킷의 프래그먼테이션을 처리합니다. KVM 환경에서 이러한 기능은 가상 NIC(예: virtio)를 통해 게스트 OS에서 관리될 수 있습니다. 조사 결과, RHEL 9.2 VM에서도 이러한 오프로드 기능을 제어할 수 있는 것으로 나타났습니다. 이는 VM이 자체 네트워크 스택을 가지며, 가상 인터페이스에서 ethtool과 같은 도구를 통해 설정이 가능하기 때문입니다.

특히, virtio 드라이버는 KVM에서 널리 사용되며, GSO와 UFO를 포함한 다양한 오프로드 기능을 지원합니다. 그러나 UFO는 최근 리눅스 커널에서 보안 문제로 인해 일부 제거되었거나 제한되었으나, 가상 환경에서는 tuntap 및 packet 장치와 같은 특정 케이스에서 여전히 지원될 수 있습니다. 이는 2017년 커널 4.14 이후 UFO가 부분적으로 복원되었으며, RHEL 9.2(커널 5.14 기반)에서도 가상 인터페이스에서 사용 가능할 가능성을 시사합니다.

#### 설정 방법  
VM 내부에서 GSO와 UFO를 비활성화하는 방법은 다음과 같습니다:

- **임시 비활성화**:  
  ethtool 명령어를 사용하여 즉시 비활성화할 수 있습니다. 예를 들어, 네트워크 인터페이스가 `eth0`인 경우:  
  ```
  ethtool -K eth0 gso off
  ethtool -K eth0 ufo off
  ```
  이 설정은 재부팅 시 초기화됩니다.

- **영구 비활성화**:  
  RHEL 9.2는 NetworkManager를 기본적으로 사용하므로, nmcli를 통해 영구 설정이 가능합니다:  
  ```
  nmcli connection modify eth0 ethtool.feature-gso off
  nmcli connection modify eth0 ethtool.feature-ufo off
  nmcli connection up eth0
  ```
  이 설정은 재부팅 후에도 유지됩니다. 영구 설정을 위해 rc.local에 ethtool 명령어를 추가하거나 libvirt 후크를 사용하는 방법도 고려될 수 있습니다.

설정 후, 비활성화가 제대로 적용되었는지 확인하려면 다음 명령어를 사용하세요:  
```
ethtool -k eth0 | grep -E "generic-segmentation-offload|udp-fragmentation-offload"
```
출력에서 `off`로 표시되면 성공적으로 비활성화된 것입니다.

#### 주의사항 및 성능 영향  
GSO와 UFO를 비활성화하면 네트워크 성능에 영향을 미칠 수 있습니다. 이러한 오프로드 기능은 CPU 부하를 줄이고 처리 속도를 높이는 역할을 하므로, 비활성화 시 VM의 네트워크 스택이 더 많은 작업을 처리해야 하여 성능 저하가 발생할 수 있습니다. 따라서 비활성화 후 네트워크 성능을 테스트하여 영향을 평가하는 것이 권장됩니다.

또한, 호스트와 게스트 간의 오프로드 설정 간 상호작용 가능성이 있습니다. 예를 들어, 호스트에서 GSO 또는 UFO가 활성화된 경우, 게스트의 설정이 호스트 설정에 따라 달라질 수 있습니다. 이는 특히 KVM 네트워크 성능 최적화와 관련된 문서에서 논의된 바 있습니다([KVM Network Performance](https://kris.io/2015/10/01/kvm-network-performance-tso-and-gso-turn-it-off/)).

UFO의 경우, 보안 취약점(CVE-2017-1000112)으로 인해 리눅스 커널에서 제거 논의가 있었으며, 일부 환경에서는 더 이상 지원되지 않을 수 있습니다. 그러나 가상 환경에서는 VIRTIO_NET_HDR_GSO_UDP와 같은 기능을 통해 여전히 사용 가능할 수 있습니다. 이는 특히 라이브 마이그레이션 시 호환성을 유지하기 위해 필요할 수 있습니다.

#### 관련 사례 및 문서  
조사 과정에서 여러 관련 문서와 사례를 확인하였습니다. 예를 들어, Server Fault 포럼에서 KVM 게스트에서 TCP 체크섬 오프로드를 비활성화하는 방법에 대해 논의되었으며, ethtool을 사용하는 것이 효과적이라는 의견이 있었습니다([Disable TCP checksum offloading](https://serverfault.com/questions/581265/disable-tcp-checksum-offloading-on-kvm-virtual-network)). 또한, Red Hat 문서에서는 NetworkManager를 통해 ethtool 설정을 구성하는 방법을 상세히 설명하며, VM 환경에서도 동일하게 적용 가능하다고 명시되어 있습니다([Red Hat Documentation](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/configuring_and_managing_networking/configuring-ethtool-settings-in-networkmanager-connection-profiles_configuring-and-managing-networking)).

또한, KVM 네트워크 성능 최적화 관련 블로그 포스트에서는 호스트 수준에서 GSO와 TSO를 비활성화하는 것이 권장되지만, 게스트에서도 이를 제어할 수 있다는 점이 암시됩니다([KVM Network Performance](https://kris.io/2015/10/01/kvm-network-performance-tso-and-gso-turn-it-off/)). 이는 VM 내부에서 ethtool을 사용하여 오프로드 기능을 관리할 수 있음을 뒷받침합니다.

#### 요약 표  
아래 표는 주요 설정 방법과 주의사항을 정리한 것입니다:

| **항목**               | **설명**                                                                 |
|-----------------------|-------------------------------------------------------------------------|
| 임시 비활성화 명령어   | `ethtool -K eth0 gso off`, `ethtool -K eth0 ufo off`                   |
| 영구 비활성화 방법     | `nmcli connection modify eth0 ethtool.feature-gso off` 등 사용         |
| 주의사항               | 성능 저하 가능성, 호스트-게스트 상호작용 고려 필요                     |
| UFO 지원 상태          | 가상 환경에서는 부분적으로 지원, 보안 문제로 제한 가능성                 |

#### 결론  
RHEL 9.2 VM에서 GSO와 UFO를 비활성화하는 것은 가능하며, ethtool과 nmcli를 통해 설정할 수 있습니다. 그러나 성능 영향과 호스트 설정과의 상호작용을 고려하여 신중히 진행해야 합니다. 추가적인 세부 사항은 관련 문서를 참고하시기 바랍니다.

### 주요 인용
- [KVM Network Performance: TSO and GSO - Turn it off](https://kris.io/2015/10/01/kvm-network-performance-tso-and-gso-turn-it-off/)
- [Disable TCP checksum offloading on KVM virtual network](https://serverfault.com/questions/581265/disable-tcp-checksum-offloading-on-kvm-virtual-network)
- [Red Hat Documentation: Configuring ethtool settings in NetworkManager connection profiles](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/configuring_and_managing_networking/configuring-ethtool-settings-in-networkmanager-connection-profiles_configuring-and-managing-networking)
- [Linux Kernel: UFO removal and partial reintroduction](https://cdn.kernel.org/pub/linux/kernel/v4.x/ChangeLog-4.14.7)
