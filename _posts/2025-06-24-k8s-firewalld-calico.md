--- 
title: "Kubernetes 클러스터 환경에서 firewalld 서비스와 calico plugin 통합 운영"
date: 2025-06-24
tags: [k8s, kubernetes, firewalld, calico, iptables]
categories: [Issues, Kubernetes]
---


## 이슈 개요

Kubernetes 클러스터에서 OS 상의 firewalld 데몬이 enable 되었을 때, calico plugin 관련 통신이슈가 확인됩니다.

1. firewalld disable
   내부 pod -> 외부 XXX.XXX.XXX.XXX (Internal Web Proxy) 통신: 정상 

2. firewalld enable
   내부 pod -> 외부 XXX.XXX.XXX.XXX (Internal Web Proxy) 통신: timeout

3. calico pod 재구동
   내부 pod -> 외부 XXX.XXX.XXX.XXX (Internal Web Proxy) 통신: 정상

4. firewalld restart
   내부 pod -> 외부 XXX.XXX.XXX.XXX (Internal Web Proxy) 통신: timeout

5. calico pod 재구동
   내부 pod -> 외부 XXX.XXX.XXX.XXX (Internal Web Proxy) 통신: 정상

### 발생 조건

- Kubernetes 사용 노드(VM) 중 calico pod로 통신이 되는 장비
- OS Reboot이 발생되거나 firewalld가 enable(restart)되는 상황에서 통신 불가 상황 발생
- firewalld enable 하는 것이 전체 OS의 보안 기준임

### calico 관련 참고 문서

아래는 calico 공식 문서 및 oracle cloud calico 설치 관련 문서에 적힌 firewalld disable 관련 requirement 입니다.

- https://docs.tigera.io/calico/latest/getting-started/kubernetes/requirements
  Linux 배포판에 Firewalld 또는 다른 iptables 관리자가 설치되어 있는 경우 이를 비활성화해야 합니다. 이러한 관리자는 Calico에서 추가한 규칙을 방해하여 예기치 않은 동작이 발생할 수 있습니다.

- https://docs.oracle.com/en/operating-systems/olcne/1.9/calico/install.html
  각 Kubernetes 노드에서 방화벽 서비스를 비활성화합니다.

---

## 해결 방안 

### **`calico` 규칙의 특징**
`iptables-save` 출력에서 보듯, `calico`는 다음과 같은 주요 목적으로 규칙을 생성합니다.
- **Pod 간 통신**: `cali-FORWARD`, `cali-from-wl-dispatch` 등으로 트래픽 포워딩 관리
- **네트워크 정책**: `cali-fw-caliXXXXXX`, `cali-po-XXXXXX` 등으로 정책 적용
- **NAT 및 Masquerading**: `cali-POSTROUTING`, `cali-nat-outgoing` 등으로 IP 변환 처리
- **BGP 통신**: 포트 179번을 통한 통신 허용
- **가상 인터페이스**: `cali+` 인터페이스를 통한 트래픽 제어

규칙의 수가 많고, Pod나 네트워크 정책에 따라 동적으로 생성되기 때문에 이를 모두 `firewalld`에 수동으로 추가하는 것은 비현실적입니다. 따라서 실용적인 통합 방안을 제안합니다.

---

### **`firewalld`와의 통합 방법**
`firewalld`의 `direct interface`를 사용해 `calico` 규칙을 통합할 수 있지만, 모든 규칙을 추가하기보다는 핵심 통신을 보장하는 최소한의 규칙만 추가하거나, 더 나은 대안을 선택하는 것이 좋습니다. 아래는 주요 방법입니다.

### **방법 1: `direct interface`로 주요 규칙 수동 추가**
`calico`의 핵심 통신을 허용하는 최소한의 규칙을 `firewalld`에 추가하는 방식입니다.

#### **구현 예시**
1. **BGP 포트(179번) 허용**:
   ```bash
   firewall-cmd --direct --add-rule ipv4 filter INPUT 0 -p tcp --dport 179 -j ACCEPT
   firewall-cmd --direct --add-rule ipv4 filter OUTPUT 0 -p tcp --sport 179 -j ACCEPT
   ```
2. **`cali+` 인터페이스 통신 허용**:
   ```bash
   firewall-cmd --direct --add-rule ipv4 filter FORWARD 0 -i cali+ -j ACCEPT
   firewall-cmd --direct --add-rule ipv4 filter FORWARD 0 -o cali+ -j ACCEPT
   ```
3. **NAT 규칙 추가**:
   ```bash
   firewall-cmd --direct --add-rule ipv4 nat POSTROUTING 0 -s 10.244.0.0/16 -o eth0 -j MASQUERADE
   ```
   (Pod IP 대역과 외부 인터페이스는 환경에 맞게 조정 필요)

#### **장점**
- `firewalld`를 통해 `calico`의 기본 통신을 제어 가능

#### **단점**
- 규칙이 동적으로 변하므로 모든 경우를 수동으로 커버하기 어려움
- 유지보수가 복잡하고 시간이 많이 소요됨

---

### **방법 2: `calico` 백엔드를 `nftables`로 변경**
`calico`가 `iptables` 대신 `nftables`를 사용하도록 설정하면, `firewalld`와 동일한 백엔드를 사용하므로 충돌을 줄일 수 있습니다.

#### **구현 절차**
1. `calico`의 `ConfigMap` 수정:
   ```yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: calico-config
     namespace: kube-system
   data:
     felix_iptables_backend: "nft"
   ```
2. `calico-node` 재배포:
   ```bash
   kubectl rollout restart daemonset calico-node -n kube-system
   ```

#### **장점**
- `firewalld`와 `calico` 간 규칙 충돌 최소화
- 동적 규칙을 수동으로 관리할 필요 없음

#### **단점**
- `calico` 버전이 `nftables`를 지원해야 함
- 설정 변경 후 통신 테스트 필요

---

### **방법 3: `firewalld` 신뢰 구역 활용**
`calico`가 사용하는 인터페이스(`cali+`)나 포트를 `firewalld`의 `trusted zone`에 추가해 통신을 허용합니다.

#### **구현 예시**
1. **`cali+` 인터페이스 추가**:
   ```bash
   firewall-cmd --zone=trusted --add-interface=cali+ --permanent
   ```
2. **BGP 포트(179번) 허용**:
   ```bash
   firewall-cmd --zone=trusted --add-port=179/tcp --permanent
   ```
3. **설정 적용**:
   ```bash
   firewall-cmd --reload
   ```

#### **장점**
- 설정이 간단하고 빠르게 적용 가능

#### **단점**
- `trusted zone`은 모든 트래픽을 허용하므로 보안 주의 필요
- 세밀한 제어가 필요한 경우 추가 조정 필요

---

## **권장 방안**
`firewalld`의 `direct interface`를 통해 모든 `calico` 규칙을 수동으로 통합하는 것은 비효율적이며, 규칙의 동적 특성 때문에 장기적인 해결책이 되지 않습니다. 따라서 다음 두 가지 중 하나를 추천합니다:

### **최우선 추천: 방법 2 (`nftables` 백엔드 전환)**
- **이유**: `firewalld`와 `calico`가 동일한 백엔드(`nftables`)를 사용하면 충돌이 줄어들고, 동적 규칙을 별도로 관리할 필요가 없습니다.
- **구현**:
  1. `calico`의 `felix_iptables_backend`를 `"nft"`로 설정
  2. `calico-node` pod 재배포
  3. 테스트 환경에서 Pod 간 및 외부 통신 확인 후 운영 환경 적용
- **주의**: `calico` 버전이 `nftables`를 지원하는지 확인하세요.

### **대안: 방법 3 (신뢰 구역 활용)**
- **이유**: 설정이 간단하며, 빠르게 `calico` 통신 문제를 해결할 수 있습니다.
- **구현**: `cali+` 인터페이스와 필요한 포트(예: 179번)를 `trusted zone`에 추가
- **주의**: 보안 요구사항이 엄격한 경우, `trusted zone` 대신 더 세밀한 구역 설정을 고려하세요.
