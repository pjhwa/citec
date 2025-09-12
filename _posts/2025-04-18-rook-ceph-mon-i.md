---
title: "Rook-Ceph 설치 중단 문제 분석 및 해결 방법"
date: 2025-04-18
tags: [ceph, rook-ceph, install, 설치, 문제, mon]
categories: [Issues, Ceph]
---

사용자가 제공한 로그와 상태 정보를 바탕으로 Rook-Ceph 설치 과정에서 발생한 문제를 분석하고, 현재 상태, 설치가 중단된 이유, 그리고 해결 방법을 자세히 설명하겠습니다. 이 설명은 전문가의 관점에서 문제를 진단하고 해결하기 위해 필요한 단계를 포함하며, 이해하기 쉽게 단계별로 구성되었습니다.

---

### **현재 상태**

Rook-Ceph 클러스터는 설치 중 `Progressing` 단계에서 멈춰 있습니다. `CephCluster` 리소스의 상태는 다음과 같습니다:

```
NAME        DATADIRHOSTPATH   MONCOUNT   AGE   PHASE         MESSAGE                                                                                                                                                                                                         HEALTH   EXTERNAL   FSID
rook-ceph   /var/lib/rook     3          17h   Progressing   failed to create cluster: failed to start ceph monitors: failed to start mon pods: failed to check mon quorum a: failed to wait for mon quorum: exceeded max retry count waiting for monitors to reach quorum
```

- **상태**: `Progressing` (진행 중)
- **문제 메시지**: "failed to wait for mon quorum: exceeded max retry count waiting for monitors to reach quorum"  
  → Ceph 모니터(monitor, 이하 mon)들이 쿼럼(quorum)을 형성하지 못해 클러스터 초기화가 실패했습니다.

`kubectl -n rook-ceph get pods` 명령어로 확인한 결과, 세 개의 mon 파드(`rook-ceph-mon-a`, `rook-ceph-mon-b`, `rook-ceph-mon-c`)는 모두 `Running` 상태입니다:

```
NAME                   READY   STATUS    RESTARTS       AGE   IP               NODE
rook-ceph-mon-a-...    1/1     Running   0              17h   10.244.105.140   k1
rook-ceph-mon-b-...    1/1     Running   1 (3h8m ago)   17h   10.244.195.149   k3
rook-ceph-mon-c-...    1/1     Running   0              16h   10.244.99.18     k2
```

하지만 쿼럼이 형성되지 않았기 때문에 클러스터가 정상적으로 동작하지 않습니다.

---

### **설치가 중단된 이유**

Rook-Ceph 클러스터가 설치 중단된 핵심 이유는 **Ceph 모니터들이 쿼럼을 형성하지 못했기 때문**입니다. 쿼럼은 Ceph 클러스터에서 mon들이 서로 통신하여 다수결을 통해 리더를 선출하고 클러스터 상태를 동기화하는 필수 과정입니다. 쿼럼이 없으면 클러스터가 동작할 수 없습니다. 이를 확인하기 위해 각 mon의 `mon_status`를 분석했습니다:

1. **`mon-a` 상태**:
   - `"state": "probing"` → 아직 다른 mon들과 연결되지 않음
   - `"quorum": []` → 쿼럼에 포함된 mon 없음
   - `"fsid": "f1ed7497-46ae-4186-b2c6-46aac10df99c"`
   - `"monmap"`: mon-a와 mon-c만 포함

2. **`mon-b` 상태**:
   - `"state": "probing"`
   - `"quorum": []`
   - `"fsid": "f1ddd33d-5812-4dcd-b83e-58a66a2dd8cf"` → mon-a, mon-c와 다름!
   - `"monmap"`: mon-b, mon-a, mon-c 포함, 하지만 mon-a와 mon-c의 주소가 `0.0.0.0:0`으로 잘못됨

3. **`mon-c` 상태**:
   - `"state": "probing"`
   - `"quorum": []`
   - `"fsid": "f1ed7497-46ae-4186-b2c6-46aac10df99c"` → mon-a와 동일
   - `"monmap"`: mon-a와 mon-c만 포함

#### **핵심 문제: FSID 불일치**
- `mon-a`와 `mon-c`는 동일한 FSID(`f1ed7497-46ae-4186-b2c6-46aac10df99c`)를 사용하지만, `mon-b`는 다른 FSID(`f1ddd33d-5812-4dcd-b83e-58a66a2dd8cf`)를 가지고 있습니다.
- FSID는 Ceph 클러스터의 고유 식별자로, 모든 mon이 동일한 FSID를 가져야 쿼럼을 형성할 수 있습니다. FSID가 다르면 mon들이 서로 다른 클러스터로 인식되어 통신이 불가능합니다.

#### **추가 문제: Monmap 불일치**
- `mon-a`와 `mon-c`의 monmap에는 mon-a와 mon-c만 포함되어 있으며, mon-b가 누락되어 있습니다.
- 반면, `mon-b`의 monmap에는 mon-a와 mon-c가 포함되어 있지만, 이들의 주소가 `0.0.0.0:0`으로 잘못 설정되어 있어 통신이 불가능합니다.

#### **발생 원인 추정**
- `mon-b`는 과거 OOMKilled로 인해 재시작된 기록이 있습니다(3시간 8분 전). 이 과정에서 mon 데이터 디렉토리(`/var/lib/rook/mon-b/data`)에 남아 있던 이전 클러스터의 데이터가 재사용되었을 가능성이 높습니다.
- Rook-Ceph는 hostPath 볼륨을 사용하여 mon 데이터를 저장하므로, 디렉토리가 초기화되지 않은 상태에서 `ceph-mon --mkfs`가 실행되면 기존 FSID를 유지했을 수 있습니다.

---

### **로그 분석**

#### **rook-ceph-operator 로그**
```
2025-04-17 23:25:58.651358 E | ceph-cluster-controller: failed to reconcile CephCluster "rook-ceph/rook-ceph". failed to reconcile cluster "rook-ceph": failed to configure local ceph cluster: failed to create cluster: failed to start ceph monitors: failed to start mon pods: failed to check mon quorum c: failed to wait for mon quorum: exceeded max retry count waiting for monitors to reach quorum
```
- Operator가 mon 쿼럼을 기다리다 최대 재시도 횟수를 초과하여 실패했습니다.
- `"mons running: [a c b]"` 로그는 세 mon이 실행 중임을 나타내지만, 쿼럼 형성에는 실패했습니다.

#### **mon 로그**
- 세 mon 모두 `"state": "probing"` 상태로, 다른 mon을 찾고 있지만 연결에 실패하고 있습니다.
- `"slow ops"` 경고가 반복적으로 나타나며, 이는 mon이 정상적으로 동작하지 못함을 시사합니다.

---

### **문제 해결을 위한 확인 방법**

전문가로서 문제를 해결하기 위해 다음 단계를 통해 원인을 확인했습니다:

1. **Pod 상태 확인**:
   - `kubectl -n rook-ceph get pods` → 모든 mon 파드가 Running 상태인지 확인.
   - 결과: mon-b에 재시작 기록(OOMKilled)이 있음.

2. **CephCluster 상태 확인**:
   - `kubectl -n rook-ceph describe cephcluster rook-ceph` → 쿼럼 실패 메시지 확인.

3. **Mon 상태 확인**:
   - `kubectl -n rook-ceph exec -it rook-ceph-mon-<x> -- ceph --admin-daemon /run/ceph/ceph-mon.<x>.asok mon_status`
   - 결과: FSID 불일치와 monmap 불일치를 발견.

4. **네트워크 문제 점검**:
   - `kubectl -n rook-ceph get endpoints` → mon 엔드포인트 IP가 올바른지 확인.
   - `kubectl -n rook-ceph get networkpolicies` → 네트워크 정책이 통신을 차단하는지 확인 (없음).
   - `sudo iptables -L -v -n` → 방화벽 규칙 점검 (Calico 규칙만 존재, 차단 없음).
   - 결과: 네트워크 문제는 없음.

5. **호스트 데이터 확인**:
   - mon 데이터 디렉토리(`/var/lib/rook/mon-<x>/data`)가 예상대로 초기화되었는지 확인 필요.

---

### **해결 방법**

FSID 불일치를 해결하고 mon들이 동일한 클러스터로 동작하도록 데이터를 초기화해야 합니다. 클러스터가 아직 완전히 설정되지 않았으므로 데이터를 모두 정리하고 재설정하는 것이 안전합니다. 다음 단계를 따르세요:

#### **1. Mon 파드 중지**
- `CephCluster`의 mon 개수를 0으로 설정하여 mon 파드를 중지합니다:
```
kubectl -n rook-ceph edit cephcluster rook-ceph
```
  - `spec.mon.count`를 `3`에서 `0`으로 변경하고 저장합니다.
- Operator가 mon 파드를 삭제할 때까지 기다립니다:
```
kubectl -n rook-ceph get pods -w
```

#### **2. Mon 데이터 디렉토리 삭제**
- 각 노드에 접속하여 mon 데이터 디렉토리를 삭제합니다:
  - `k1`: `sudo rm -rf /var/lib/rook/mon-a/data`
  - `k3`: `sudo rm -rf /var/lib/rook/mon-b/data`
  - `k2`: `sudo rm -rf /var/lib/rook/mon-c/data`
- 이 단계는 이전 FSID와 monmap 데이터를 제거하여 새로 초기화되도록 합니다.

#### **3. Mon 파드 재시작**
- `CephCluster`의 mon 개수를 다시 3으로 설정합니다:
```
kubectl -n rook-ceph edit cephcluster rook-ceph
```
  - `spec.mon.count`를 `0`에서 `3`으로 변경하고 저장합니다.
- Operator가 mon 파드를 재생성하고 쿼럼을 형성하는지 확인합니다:
```
kubectl -n rook-ceph get pods -w
```

#### **4. 상태 확인**
- Mon 쿼럼이 형성되었는지 확인합니다:
```
kubectl -n rook-ceph exec -it rook-ceph-mon-a-<pod-hash> -- ceph --admin-daemon /run/ceph/ceph-mon.a.asok mon_status
```
  - `"state": "leader"` 또는 `"state": "peon"`이고 `"quorum": [0, 1, 2]`와 같은 결과가 나오면 성공.
- 클러스터 상태 확인:
```
kubectl -n rook-ceph get cephcluster rook-ceph
```
  - `PHASE`가 `Ready`로 변경되어야 합니다.

#### **대안: 전체 클러스터 재설치**
- 위 방법으로 해결되지 않으면, `CephCluster` 리소스를 삭제하고 데이터를 정리한 후 재생성합니다:
```
kubectl -n rook-ceph delete cephcluster rook-ceph
sudo rm -rf /var/lib/rook/*  # 모든 노드에서 실행
kubectl -n rook-ceph apply -f cluster.yaml
```

---

### **결론**

- **문제 원인**: mon-b의 FSID가 mon-a, mon-c와 달라 쿼럼 형성이 실패했습니다. 이는 mon-b의 재시작과 기존 데이터 재사용으로 발생한 것으로 보입니다.
- **해결책**: mon 데이터를 삭제하고 재초기화하여 모든 mon이 동일한 FSID로 동작하도록 합니다.
- **예방**: 향후 mon 파드에 리소스 제한(`limits.memory`)을 설정하여 OOM 문제를 방지하세요.

이 단계를 수행하면 Rook-Ceph 클러스터가 정상적으로 설치되고 쿼럼이 형성되어 `Ready` 상태로 전환될 것입니다. 

### **Ceph 설치 관련 원시 로그**

```
citec@k1:~/osh$ kubectl -n rook-ceph get pods -o wide
NAME                                            READY   STATUS    RESTARTS       AGE   IP               NODE   NOMINATED NODE   READINESS GATES
csi-cephfsplugin-6j8dj                          2/2     Running   0              17h   172.16.2.52      k2     <none>           <none>
csi-cephfsplugin-8gjx8                          2/2     Running   0              17h   172.16.2.223     k3     <none>           <none>
csi-cephfsplugin-lttg6                          2/2     Running   0              17h   172.16.2.161     k4     <none>           <none>
csi-cephfsplugin-provisioner-5fd86644fb-6btf4   5/5     Running   0              17h   10.244.99.16     k2     <none>           <none>
csi-cephfsplugin-provisioner-5fd86644fb-vsczw   5/5     Running   0              17h   10.244.194.141   k4     <none>           <none>
csi-cephfsplugin-pzc5t                          2/2     Running   0              17h   172.16.2.149     k1     <none>           <none>
csi-rbdplugin-5tcx9                             2/2     Running   0              17h   172.16.2.52      k2     <none>           <none>
csi-rbdplugin-6lxnn                             2/2     Running   0              17h   172.16.2.223     k3     <none>           <none>
csi-rbdplugin-khcs2                             2/2     Running   0              17h   172.16.2.149     k1     <none>           <none>
csi-rbdplugin-l54sz                             2/2     Running   0              17h   172.16.2.161     k4     <none>           <none>
csi-rbdplugin-provisioner-5cdcfc4cbd-982p6      5/5     Running   0              17h   10.244.194.140   k4     <none>           <none>
csi-rbdplugin-provisioner-5cdcfc4cbd-xcz7q      5/5     Running   0              17h   10.244.195.145   k3     <none>           <none>
rook-ceph-mon-a-6b84b89d56-jv6hm                1/1     Running   0              17h   10.244.105.140   k1     <none>           <none>
rook-ceph-mon-b-66789dfd6-c9pct                 1/1     Running   1 (3h8m ago)   17h   10.244.195.149   k3     <none>           <none>
rook-ceph-mon-c-648dbbff5c-b8vth                1/1     Running   0              16h   10.244.99.18     k2     <none>           <none>
rook-ceph-operator-6d97579698-prld8             1/1     Running   0              17h   10.244.99.15     k2     <none>           <none>
rook-ceph-tools-56fbc74755-8st8v                1/1     Running   0              17h   10.244.195.147   k3     <none>           <none>

citec@k1:~/osh$ kubectl -n rook-ceph get cephcluster rook-ceph
NAME        DATADIRHOSTPATH   MONCOUNT   AGE   PHASE         MESSAGE                                                                                                                                                                                                         HEALTH   EXTERNAL   FSID
rook-ceph   /var/lib/rook     3          17h   Progressing   failed to create cluster: failed to start ceph monitors: failed to start mon pods: failed to check mon quorum a: failed to wait for mon quorum: exceeded max retry count waiting for monitors to reach quorum
citec@k1:~/osh$
citec@k1:~/osh$ kubectl -n rook-ceph describe cephcluster rook-ceph
Name:         rook-ceph
Namespace:    rook-ceph
Labels:       <none>
Annotations:  <none>
API Version:  ceph.rook.io/v1
Kind:         CephCluster
Metadata:
  Creation Timestamp:  2025-04-17T07:09:17Z
  Finalizers:
    cephcluster.ceph.rook.io
  Generation:        2
  Resource Version:  183220
  UID:               ff6c4290-ddb9-44c4-a12e-824f999a48a5
Spec:
  Ceph Version:
    Image:  quay.io/ceph/ceph:v18.2.4
  Cleanup Policy:
    Sanitize Disks:
  Crash Collector:
  Csi:
    Cephfs:
    Read Affinity:
      Enabled:  false
  Dashboard:
    Enabled:           true
  Data Dir Host Path:  /var/lib/rook
  Disruption Management:
  External:
  Health Check:
    Daemon Health:
      Mon:
      Osd:
      Status:
  Log Collector:
  Mgr:
  Mon:
    Count:  3
  Monitoring:
  Network:
    Multi Cluster Service:
  Security:
    Key Rotation:
      Enabled:  false
    Kms:
  Storage:
    Flapping Restart Interval Hours:  0
    Migration:
    Store:
    Use All Devices:  true
    Use All Nodes:    true
Status:
  Conditions:
    Last Heartbeat Time:   2025-04-18T00:03:22Z
    Last Transition Time:  2025-04-18T00:03:22Z
    Message:               failed to create cluster: failed to start ceph monitors: failed to start mon pods: failed to check mon quorum a: failed to wait for mon quorum: exceeded max retry count waiting for monitors to reach quorum
    Reason:                ClusterProgressing
    Status:                False
    Type:                  Progressing
  Message:                 failed to create cluster: failed to start ceph monitors: failed to start mon pods: failed to check mon quorum a: failed to wait for mon quorum: exceeded max retry count waiting for monitors to reach quorum
  Phase:                   Progressing
  State:                   Error
  Version:
    Image:    quay.io/ceph/ceph:v18.2.4
    Version:  18.2.4-0
Events:
  Type     Reason           Age                 From                          Message
  ----     ------           ----                ----                          -------
  Warning  ReconcileFailed  49m (x15 over 16h)  rook-ceph-cluster-controller  failed to reconcile CephCluster "rook-ceph/rook-ceph". failed to reconcile cluster "rook-ceph": failed to configure local ceph cluster: failed to create cluster: failed to start ceph monitors: failed to start mon pods: failed to check mon quorum c: failed to wait for mon quorum: exceeded max retry count waiting for monitors to reach quorum
  Warning  ReconcileFailed  12m (x9 over 16h)   rook-ceph-cluster-controller  failed to reconcile CephCluster "rook-ceph/rook-ceph". failed to reconcile cluster "rook-ceph": failed to configure local ceph cluster: failed to create cluster: failed to start ceph monitors: failed to start mon pods: failed to check mon quorum a: failed to wait for mon quorum: exceeded max retry count waiting for monitors to reach quorum

citec@k1:~/osh$ kubectl get nodes -o wide
NAME   STATUS   ROLES           AGE   VERSION    INTERNAL-IP    EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION       CONTAINER-RUNTIME
k1     Ready    control-plane   22h   v1.29.15   172.16.2.149   <none>        Ubuntu 22.04.5 LTS   5.15.0-136-generic   containerd://1.7.27
k2     Ready    <none>          22h   v1.29.15   172.16.2.52    <none>        Ubuntu 22.04.5 LTS   5.15.0-136-generic   containerd://1.7.27
k3     Ready    <none>          22h   v1.29.15   172.16.2.223   <none>        Ubuntu 22.04.5 LTS   5.15.0-136-generic   containerd://1.7.27
k4     Ready    <none>          22h   v1.29.15   172.16.2.161   <none>        Ubuntu 22.04.5 LTS   5.15.0-136-generic   containerd://1.7.27
citec@k1:~/osh$ kubectl describe nodes
Name:               k1
Roles:              control-plane
Labels:             beta.kubernetes.io/arch=amd64
                    beta.kubernetes.io/os=linux
                    kubernetes.io/arch=amd64
                    kubernetes.io/hostname=k1
                    kubernetes.io/os=linux
                    node-role.kubernetes.io/control-plane=
                    node.kubernetes.io/exclude-from-external-load-balancers=
Annotations:        csi.volume.kubernetes.io/nodeid: {"rook-ceph.cephfs.csi.ceph.com":"k1","rook-ceph.rbd.csi.ceph.com":"k1"}
                    kubeadm.alpha.kubernetes.io/cri-socket: unix:///var/run/containerd/containerd.sock
                    node.alpha.kubernetes.io/ttl: 0
                    projectcalico.org/IPv4Address: 172.16.2.149/24
                    projectcalico.org/IPv4IPIPTunnelAddr: 10.244.105.128
                    volumes.kubernetes.io/controller-managed-attach-detach: true
CreationTimestamp:  Thu, 17 Apr 2025 10:53:50 +0900
Taints:             <none>
Unschedulable:      false
Lease:
  HolderIdentity:  k1
  AcquireTime:     <unset>
  RenewTime:       Fri, 18 Apr 2025 09:17:00 +0900
Conditions:
  Type                 Status  LastHeartbeatTime                 LastTransitionTime                Reason                       Message
  ----                 ------  -----------------                 ------------------                ------                       -------
  NetworkUnavailable   False   Thu, 17 Apr 2025 10:57:53 +0900   Thu, 17 Apr 2025 10:57:53 +0900   CalicoIsUp                   Calico is running on this node
  MemoryPressure       False   Fri, 18 Apr 2025 09:15:08 +0900   Thu, 17 Apr 2025 10:53:48 +0900   KubeletHasSufficientMemory   kubelet has sufficient memory available
  DiskPressure         False   Fri, 18 Apr 2025 09:15:08 +0900   Thu, 17 Apr 2025 10:53:48 +0900   KubeletHasNoDiskPressure     kubelet has no disk pressure
  PIDPressure          False   Fri, 18 Apr 2025 09:15:08 +0900   Thu, 17 Apr 2025 10:53:48 +0900   KubeletHasSufficientPID      kubelet has sufficient PID available
  Ready                True    Fri, 18 Apr 2025 09:15:08 +0900   Thu, 17 Apr 2025 10:57:20 +0900   KubeletReady                 kubelet is posting ready status. AppArmor enabled
Addresses:
  InternalIP:  172.16.2.149
  Hostname:    k1
Capacity:
  cpu:                4
  ephemeral-storage:  50477964Ki
  hugepages-2Mi:      0
  memory:             32863612Ki
  pods:               110
Allocatable:
  cpu:                4
  ephemeral-storage:  46520491546
  hugepages-2Mi:      0
  memory:             32761212Ki
  pods:               110
System Info:
  Machine ID:                 7bfddc5cd46e4ca4a11fa8048636e21a
  System UUID:                3cfd3b42-2148-ef4f-57b8-1b3f9ba15708
  Boot ID:                    90f5d324-eff7-471a-aff7-b1122132b60a
  Kernel Version:             5.15.0-136-generic
  OS Image:                   Ubuntu 22.04.5 LTS
  Operating System:           linux
  Architecture:               amd64
  Container Runtime Version:  containerd://1.7.27
  Kubelet Version:            v1.29.15
  Kube-Proxy Version:         v1.29.15
PodCIDR:                      10.244.0.0/24
PodCIDRs:                     10.244.0.0/24
Non-terminated Pods:          (13 in total)
  Namespace                   Name                                        CPU Requests  CPU Limits  Memory Requests  Memory Limits  Age
  ---------                   ----                                        ------------  ----------  ---------------  -------------  ---
  ceph                        ingress-nginx-ceph-controller-txszj         100m (2%)     0 (0%)      90Mi (0%)        0 (0%)         19h
  kube-system                 calico-node-qfqtq                           250m (6%)     0 (0%)      0 (0%)           0 (0%)         22h
  kube-system                 etcd-k1                                     100m (2%)     0 (0%)      100Mi (0%)       0 (0%)         22h
  kube-system                 ingress-nginx-cluster-controller-9bplr      100m (2%)     0 (0%)      90Mi (0%)        0 (0%)         19h
  kube-system                 kube-apiserver-k1                           250m (6%)     0 (0%)      0 (0%)           0 (0%)         22h
  kube-system                 kube-controller-manager-k1                  200m (5%)     0 (0%)      0 (0%)           0 (0%)         22h
  kube-system                 kube-proxy-qr85k                            0 (0%)        0 (0%)      0 (0%)           0 (0%)         22h
  kube-system                 kube-scheduler-k1                           100m (2%)     0 (0%)      0 (0%)           0 (0%)         22h
  metallb-system              metallb-speaker-vm7pz                       0 (0%)        0 (0%)      0 (0%)           0 (0%)         22h
  openstack                   ingress-nginx-openstack-controller-cts8w    100m (2%)     0 (0%)      90Mi (0%)        0 (0%)         19h
  rook-ceph                   csi-cephfsplugin-pzc5t                      300m (7%)     0 (0%)      640Mi (2%)       1280Mi (4%)    17h
  rook-ceph                   csi-rbdplugin-khcs2                         300m (7%)     0 (0%)      640Mi (2%)       1280Mi (4%)    17h
  rook-ceph                   rook-ceph-mon-a-6b84b89d56-jv6hm            0 (0%)        0 (0%)      0 (0%)           0 (0%)         17h
Allocated resources:
  (Total limits may be over 100 percent, i.e., overcommitted.)
  Resource           Requests     Limits
  --------           --------     ------
  cpu                1800m (45%)  0 (0%)
  memory             1650Mi (5%)  2560Mi (8%)
  ephemeral-storage  0 (0%)       0 (0%)
  hugepages-2Mi      0 (0%)       0 (0%)
Events:              <none>


Name:               k2
Roles:              <none>
Labels:             beta.kubernetes.io/arch=amd64
                    beta.kubernetes.io/os=linux
                    kubernetes.io/arch=amd64
                    kubernetes.io/hostname=k2
                    kubernetes.io/os=linux
Annotations:        csi.volume.kubernetes.io/nodeid: {"rook-ceph.cephfs.csi.ceph.com":"k2","rook-ceph.rbd.csi.ceph.com":"k2"}
                    kubeadm.alpha.kubernetes.io/cri-socket: unix:///var/run/containerd/containerd.sock
                    node.alpha.kubernetes.io/ttl: 0
                    projectcalico.org/IPv4Address: 172.16.2.52/24
                    projectcalico.org/IPv4IPIPTunnelAddr: 10.244.99.0
                    volumes.kubernetes.io/controller-managed-attach-detach: true
CreationTimestamp:  Thu, 17 Apr 2025 10:55:27 +0900
Taints:             <none>
Unschedulable:      false
Lease:
  HolderIdentity:  k2
  AcquireTime:     <unset>
  RenewTime:       Fri, 18 Apr 2025 09:16:57 +0900
Conditions:
  Type                 Status  LastHeartbeatTime                 LastTransitionTime                Reason                       Message
  ----                 ------  -----------------                 ------------------                ------                       -------
  NetworkUnavailable   False   Thu, 17 Apr 2025 10:58:03 +0900   Thu, 17 Apr 2025 10:58:03 +0900   CalicoIsUp                   Calico is running on this node
  MemoryPressure       False   Fri, 18 Apr 2025 09:13:10 +0900   Thu, 17 Apr 2025 10:55:27 +0900   KubeletHasSufficientMemory   kubelet has sufficient memory available
  DiskPressure         False   Fri, 18 Apr 2025 09:13:10 +0900   Thu, 17 Apr 2025 10:55:27 +0900   KubeletHasNoDiskPressure     kubelet has no disk pressure
  PIDPressure          False   Fri, 18 Apr 2025 09:13:10 +0900   Thu, 17 Apr 2025 10:55:27 +0900   KubeletHasSufficientPID      kubelet has sufficient PID available
  Ready                True    Fri, 18 Apr 2025 09:13:10 +0900   Thu, 17 Apr 2025 10:57:20 +0900   KubeletReady                 kubelet is posting ready status. AppArmor enabled
Addresses:
  InternalIP:  172.16.2.52
  Hostname:    k2
Capacity:
  cpu:                4
  ephemeral-storage:  50477964Ki
  hugepages-2Mi:      0
  memory:             32863612Ki
  pods:               110
Allocatable:
  cpu:                4
  ephemeral-storage:  46520491546
  hugepages-2Mi:      0
  memory:             32761212Ki
  pods:               110
System Info:
  Machine ID:                 7bfddc5cd46e4ca4a11fa8048636e21a
  System UUID:                07c83b42-3c5f-0088-6896-22f46a6039b3
  Boot ID:                    db064921-778b-42a1-a983-95e551d25d83
  Kernel Version:             5.15.0-136-generic
  OS Image:                   Ubuntu 22.04.5 LTS
  Operating System:           linux
  Architecture:               amd64
  Container Runtime Version:  containerd://1.7.27
  Kubelet Version:            v1.29.15
  Kube-Proxy Version:         v1.29.15
PodCIDR:                      10.244.2.0/24
PodCIDRs:                     10.244.2.0/24
Non-terminated Pods:          (12 in total)
  Namespace                   Name                                             CPU Requests  CPU Limits  Memory Requests  Memory Limits  Age
  ---------                   ----                                             ------------  ----------  ---------------  -------------  ---
  ceph                        ingress-nginx-ceph-controller-7ssh8              100m (2%)     0 (0%)      90Mi (0%)        0 (0%)         19h
  kube-system                 calico-node-z4tkv                                250m (6%)     0 (0%)      0 (0%)           0 (0%)         22h
  kube-system                 coredns-b87576b6c-x2s4f                          100m (2%)     0 (0%)      70Mi (0%)        170Mi (0%)     22h
  kube-system                 ingress-nginx-cluster-controller-cxlzh           100m (2%)     0 (0%)      90Mi (0%)        0 (0%)         19h
  kube-system                 kube-proxy-lmffv                                 0 (0%)        0 (0%)      0 (0%)           0 (0%)         22h
  metallb-system              metallb-speaker-69fvw                            0 (0%)        0 (0%)      0 (0%)           0 (0%)         22h
  openstack                   ingress-nginx-openstack-controller-zdw66         100m (2%)     0 (0%)      90Mi (0%)        0 (0%)         19h
  rook-ceph                   csi-cephfsplugin-6j8dj                           300m (7%)     0 (0%)      640Mi (2%)       1280Mi (4%)    17h
  rook-ceph                   csi-cephfsplugin-provisioner-5fd86644fb-6btf4    650m (16%)    0 (0%)      1Gi (3%)         2Gi (6%)       17h
  rook-ceph                   csi-rbdplugin-5tcx9                              300m (7%)     0 (0%)      640Mi (2%)       1280Mi (4%)    17h
  rook-ceph                   rook-ceph-mon-c-648dbbff5c-b8vth                 0 (0%)        0 (0%)      0 (0%)           0 (0%)         16h
  rook-ceph                   rook-ceph-operator-6d97579698-prld8              200m (5%)     0 (0%)      128Mi (0%)       512Mi (1%)     17h
Allocated resources:
  (Total limits may be over 100 percent, i.e., overcommitted.)
  Resource           Requests     Limits
  --------           --------     ------
  cpu                2100m (52%)  0 (0%)
  memory             2772Mi (8%)  5290Mi (16%)
  ephemeral-storage  0 (0%)       0 (0%)
  hugepages-2Mi      0 (0%)       0 (0%)
Events:              <none>


Name:               k3
Roles:              <none>
Labels:             beta.kubernetes.io/arch=amd64
                    beta.kubernetes.io/os=linux
                    kubernetes.io/arch=amd64
                    kubernetes.io/hostname=k3
                    kubernetes.io/os=linux
Annotations:        csi.volume.kubernetes.io/nodeid: {"rook-ceph.cephfs.csi.ceph.com":"k3","rook-ceph.rbd.csi.ceph.com":"k3"}
                    kubeadm.alpha.kubernetes.io/cri-socket: unix:///var/run/containerd/containerd.sock
                    node.alpha.kubernetes.io/ttl: 0
                    projectcalico.org/IPv4Address: 172.16.2.223/24
                    projectcalico.org/IPv4IPIPTunnelAddr: 10.244.195.128
                    volumes.kubernetes.io/controller-managed-attach-detach: true
CreationTimestamp:  Thu, 17 Apr 2025 10:56:56 +0900
Taints:             <none>
Unschedulable:      false
Lease:
  HolderIdentity:  k3
  AcquireTime:     <unset>
  RenewTime:       Fri, 18 Apr 2025 09:16:59 +0900
Conditions:
  Type                 Status  LastHeartbeatTime                 LastTransitionTime                Reason                       Message
  ----                 ------  -----------------                 ------------------                ------                       -------
  NetworkUnavailable   False   Thu, 17 Apr 2025 10:58:25 +0900   Thu, 17 Apr 2025 10:58:25 +0900   CalicoIsUp                   Calico is running on this node
  MemoryPressure       False   Fri, 18 Apr 2025 09:15:40 +0900   Thu, 17 Apr 2025 10:56:56 +0900   KubeletHasSufficientMemory   kubelet has sufficient memory available
  DiskPressure         False   Fri, 18 Apr 2025 09:15:40 +0900   Thu, 17 Apr 2025 10:56:56 +0900   KubeletHasNoDiskPressure     kubelet has no disk pressure
  PIDPressure          False   Fri, 18 Apr 2025 09:15:40 +0900   Thu, 17 Apr 2025 10:56:56 +0900   KubeletHasSufficientPID      kubelet has sufficient PID available
  Ready                True    Fri, 18 Apr 2025 09:15:40 +0900   Thu, 17 Apr 2025 10:57:20 +0900   KubeletReady                 kubelet is posting ready status. AppArmor enabled
Addresses:
  InternalIP:  172.16.2.223
  Hostname:    k3
Capacity:
  cpu:                4
  ephemeral-storage:  50477964Ki
  hugepages-2Mi:      0
  memory:             32863612Ki
  pods:               110
Allocatable:
  cpu:                4
  ephemeral-storage:  46520491546
  hugepages-2Mi:      0
  memory:             32761212Ki
  pods:               110
System Info:
  Machine ID:                 7bfddc5cd46e4ca4a11fa8048636e21a
  System UUID:                1cef3b42-89bb-af10-5fe7-8a9f7ecaf8ef
  Boot ID:                    26e84f31-31e4-4a6e-82ba-fdc9993244bb
  Kernel Version:             5.15.0-136-generic
  OS Image:                   Ubuntu 22.04.5 LTS
  Operating System:           linux
  Architecture:               amd64
  Container Runtime Version:  containerd://1.7.27
  Kubelet Version:            v1.29.15
  Kube-Proxy Version:         v1.29.15
PodCIDR:                      10.244.3.0/24
PodCIDRs:                     10.244.3.0/24
Non-terminated Pods:          (12 in total)
  Namespace                   Name                                          CPU Requests  CPU Limits  Memory Requests  Memory Limits  Age
  ---------                   ----                                          ------------  ----------  ---------------  -------------  ---
  ceph                        ingress-nginx-ceph-controller-pnh5c           100m (2%)     0 (0%)      90Mi (0%)        0 (0%)         19h
  kube-system                 calico-node-9knwk                             250m (6%)     0 (0%)      0 (0%)           0 (0%)         22h
  kube-system                 coredns-b87576b6c-55dr8                       100m (2%)     0 (0%)      70Mi (0%)        170Mi (0%)     22h
  kube-system                 ingress-nginx-cluster-controller-4f7k9        100m (2%)     0 (0%)      90Mi (0%)        0 (0%)         19h
  kube-system                 kube-proxy-wvcx2                              0 (0%)        0 (0%)      0 (0%)           0 (0%)         22h
  metallb-system              metallb-speaker-lq49d                         0 (0%)        0 (0%)      0 (0%)           0 (0%)         22h
  openstack                   ingress-nginx-openstack-controller-vj2kd      100m (2%)     0 (0%)      90Mi (0%)        0 (0%)         19h
  rook-ceph                   csi-cephfsplugin-8gjx8                        300m (7%)     0 (0%)      640Mi (2%)       1280Mi (4%)    17h
  rook-ceph                   csi-rbdplugin-6lxnn                           300m (7%)     0 (0%)      640Mi (2%)       1280Mi (4%)    17h
  rook-ceph                   csi-rbdplugin-provisioner-5cdcfc4cbd-xcz7q    400m (10%)    0 (0%)      1Gi (3%)         2Gi (6%)       17h
  rook-ceph                   rook-ceph-mon-b-66789dfd6-c9pct               0 (0%)        0 (0%)      0 (0%)           0 (0%)         16h
  rook-ceph                   rook-ceph-tools-56fbc74755-8st8v              0 (0%)        0 (0%)      0 (0%)           0 (0%)         17h
Allocated resources:
  (Total limits may be over 100 percent, i.e., overcommitted.)
  Resource           Requests     Limits
  --------           --------     ------
  cpu                1650m (41%)  0 (0%)
  memory             2644Mi (8%)  4778Mi (14%)
  ephemeral-storage  0 (0%)       0 (0%)
  hugepages-2Mi      0 (0%)       0 (0%)
Events:              <none>


Name:               k4
Roles:              <none>
Labels:             beta.kubernetes.io/arch=amd64
                    beta.kubernetes.io/os=linux
                    kubernetes.io/arch=amd64
                    kubernetes.io/hostname=k4
                    kubernetes.io/os=linux
Annotations:        csi.volume.kubernetes.io/nodeid: {"rook-ceph.cephfs.csi.ceph.com":"k4","rook-ceph.rbd.csi.ceph.com":"k4"}
                    kubeadm.alpha.kubernetes.io/cri-socket: unix:///var/run/containerd/containerd.sock
                    node.alpha.kubernetes.io/ttl: 0
                    projectcalico.org/IPv4Address: 172.16.2.161/24
                    projectcalico.org/IPv4IPIPTunnelAddr: 10.244.194.128
                    volumes.kubernetes.io/controller-managed-attach-detach: true
CreationTimestamp:  Thu, 17 Apr 2025 10:55:26 +0900
Taints:             <none>
Unschedulable:      false
Lease:
  HolderIdentity:  k4
  AcquireTime:     <unset>
  RenewTime:       Fri, 18 Apr 2025 09:16:52 +0900
Conditions:
  Type                 Status  LastHeartbeatTime                 LastTransitionTime                Reason                       Message
  ----                 ------  -----------------                 ------------------                ------                       -------
  NetworkUnavailable   False   Thu, 17 Apr 2025 10:58:14 +0900   Thu, 17 Apr 2025 10:58:14 +0900   CalicoIsUp                   Calico is running on this node
  MemoryPressure       False   Fri, 18 Apr 2025 09:16:31 +0900   Thu, 17 Apr 2025 10:55:26 +0900   KubeletHasSufficientMemory   kubelet has sufficient memory available
  DiskPressure         False   Fri, 18 Apr 2025 09:16:31 +0900   Thu, 17 Apr 2025 10:55:26 +0900   KubeletHasNoDiskPressure     kubelet has no disk pressure
  PIDPressure          False   Fri, 18 Apr 2025 09:16:31 +0900   Thu, 17 Apr 2025 10:55:26 +0900   KubeletHasSufficientPID      kubelet has sufficient PID available
  Ready                True    Fri, 18 Apr 2025 09:16:31 +0900   Thu, 17 Apr 2025 10:57:19 +0900   KubeletReady                 kubelet is posting ready status. AppArmor enabled
Addresses:
  InternalIP:  172.16.2.161
  Hostname:    k4
Capacity:
  cpu:                4
  ephemeral-storage:  50477964Ki
  hugepages-2Mi:      0
  memory:             32863616Ki
  pods:               110
Allocatable:
  cpu:                4
  ephemeral-storage:  46520491546
  hugepages-2Mi:      0
  memory:             32761216Ki
  pods:               110
System Info:
  Machine ID:                 7bfddc5cd46e4ca4a11fa8048636e21a
  System UUID:                c4f03b42-9128-e878-eaac-042d6e6ed0b5
  Boot ID:                    71d0eff6-8926-4c93-a5e0-be081e5019cd
  Kernel Version:             5.15.0-136-generic
  OS Image:                   Ubuntu 22.04.5 LTS
  Operating System:           linux
  Architecture:               amd64
  Container Runtime Version:  containerd://1.7.27
  Kubelet Version:            v1.29.15
  Kube-Proxy Version:         v1.29.15
PodCIDR:                      10.244.1.0/24
PodCIDRs:                     10.244.1.0/24
Non-terminated Pods:          (12 in total)
  Namespace                   Name                                             CPU Requests  CPU Limits  Memory Requests  Memory Limits  Age
  ---------                   ----                                             ------------  ----------  ---------------  -------------  ---
  ceph                        ingress-nginx-ceph-controller-vfzwd              100m (2%)     0 (0%)      90Mi (0%)        0 (0%)         19h
  kube-system                 calico-kube-controllers-6b78c44475-7gm9j         0 (0%)        0 (0%)      0 (0%)           0 (0%)         22h
  kube-system                 calico-node-ltwdm                                250m (6%)     0 (0%)      0 (0%)           0 (0%)         22h
  kube-system                 ingress-nginx-cluster-controller-gqb7r           100m (2%)     0 (0%)      90Mi (0%)        0 (0%)         19h
  kube-system                 kube-proxy-8sw4c                                 0 (0%)        0 (0%)      0 (0%)           0 (0%)         22h
  metallb-system              metallb-controller-5f9bb77dcd-lbx7z              0 (0%)        0 (0%)      0 (0%)           0 (0%)         22h
  metallb-system              metallb-speaker-qmhx5                            0 (0%)        0 (0%)      0 (0%)           0 (0%)         22h
  openstack                   ingress-nginx-openstack-controller-7v45t         100m (2%)     0 (0%)      90Mi (0%)        0 (0%)         19h
  rook-ceph                   csi-cephfsplugin-lttg6                           300m (7%)     0 (0%)      640Mi (2%)       1280Mi (4%)    17h
  rook-ceph                   csi-cephfsplugin-provisioner-5fd86644fb-vsczw    650m (16%)    0 (0%)      1Gi (3%)         2Gi (6%)       17h
  rook-ceph                   csi-rbdplugin-l54sz                              300m (7%)     0 (0%)      640Mi (2%)       1280Mi (4%)    17h
  rook-ceph                   csi-rbdplugin-provisioner-5cdcfc4cbd-982p6       400m (10%)    0 (0%)      1Gi (3%)         2Gi (6%)       17h
Allocated resources:
  (Total limits may be over 100 percent, i.e., overcommitted.)
  Resource           Requests      Limits
  --------           --------      ------
  cpu                2200m (55%)   0 (0%)
  memory             3598Mi (11%)  6656Mi (20%)
  ephemeral-storage  0 (0%)        0 (0%)
  hugepages-2Mi      0 (0%)        0 (0%)
Events:              <none>

citec@k1:~/osh$ kubectl -n rook-ceph logs rook-ceph-operator-6d97579698-prld8
2025-04-17 20:36:00.672743 I | op-mon: checking for basic quorum with existing mons
2025-04-17 20:36:00.696472 I | op-mon: mon "a" cluster IP is 10.96.11.92
2025-04-17 20:36:00.717421 I | op-mon: mon "c" cluster IP is 10.96.170.97
2025-04-17 20:36:01.077497 I | op-mon: mon "b" cluster IP is 10.96.228.121
2025-04-17 20:36:01.677751 I | op-mon: saved mon endpoints to config map map[csi-cluster-config-json:[{"clusterID":"rook-ceph","monitors":["10.96.11.92:6789","10.96.170.97:6789","10.96.228.121:6789"],"cephFS":{"netNamespaceFilePath":"","subvolumeGroup":"","radosNamespace":"","kernelMountOptions":"","fuseMountOptions":""},"rbd":{"netNamespaceFilePath":"","radosNamespace":"","mirrorDaemonCount":0},"nfs":{"netNamespaceFilePath":""},"readAffinity":{"enabled":false,"crushLocationLabels":null},"namespace":""}] data:b=10.96.228.121:6789,a=10.96.11.92:6789,c=10.96.170.97:6789 externalMons: mapping:{"node":{"a":{"Name":"k1","Hostname":"k1","Address":"172.16.2.149"},"b":{"Name":"k3","Hostname":"k3","Address":"172.16.2.223"},"c":{"Name":"k2","Hostname":"k2","Address":"172.16.2.52"}}} maxMonId:2 outOfQuorum:]
2025-04-17 20:36:01.683297 I | op-mon: created/updated IPv4 endpointslice with addresses: [10.96.11.92 10.96.170.97 10.96.228.121]
2025-04-17 20:36:02.276482 I | cephclient: writing config file /var/lib/rook/rook-ceph/rook-ceph.config
2025-04-17 20:36:02.276734 I | cephclient: generated admin config in /var/lib/rook/rook-ceph
2025-04-17 20:36:02.685251 I | op-mon: deployment for mon rook-ceph-mon-a already exists. updating if needed
2025-04-17 20:36:02.692444 I | op-k8sutil: deployment "rook-ceph-mon-a" did not change, nothing to update
2025-04-17 20:36:02.692527 I | op-mon: waiting for mon quorum with [a c b]
2025-04-17 20:36:03.279755 I | op-mon: mons running: [a c b]
2025-04-17 20:36:23.475712 I | op-mon: mons running: [a c b]
2025-04-17 20:36:43.677229 I | op-mon: mons running: [a c b]
2025-04-17 20:37:03.878026 I | op-mon: mons running: [a c b]
2025-04-17 20:37:24.066655 I | op-mon: mons running: [a c b]
2025-04-17 20:37:44.288514 I | op-mon: mons running: [a c b]
2025-04-17 20:38:04.476682 I | op-mon: mons running: [a c b]
2025-04-17 23:25:58.651358 E | ceph-cluster-controller: failed to reconcile CephCluster "rook-ceph/rook-ceph". failed to reconcile cluster "rook-ceph": failed to configure local ceph cluster: failed to create cluster: failed to start ceph monitors: failed to start mon pods: failed to check mon quorum c: failed to wait for mon quorum: exceeded max retry count waiting for monitors to reach quorum
2025-04-17 23:42:38.652824 I | ceph-cluster-controller: reconciling ceph cluster in namespace "rook-ceph"
2025-04-17 23:42:38.658324 I | ceph-spec: parsing mon endpoints: a=10.96.11.92:6789,c=10.96.170.97:6789,b=10.96.228.121:6789
2025-04-17 23:42:38.674428 I | ceph-spec: detecting the ceph image version for image quay.io/ceph/ceph:v18.2.4...
2025-04-17 23:42:40.702830 I | ceph-spec: detected ceph image version: "18.2.4-0 reef"
2025-04-17 23:42:40.702870 I | ceph-cluster-controller: validating ceph version from provided image
2025-04-17 23:42:40.709708 I | ceph-spec: parsing mon endpoints: a=10.96.11.92:6789,c=10.96.170.97:6789,b=10.96.228.121:6789
2025-04-17 23:42:40.713232 I | cephclient: writing config file /var/lib/rook/rook-ceph/rook-ceph.config
2025-04-17 23:42:40.713448 I | cephclient: generated admin config in /var/lib/rook/rook-ceph
2025-04-17 23:42:55.892453 E | ceph-cluster-controller: failed to get ceph daemons versions, this typically happens during the first cluster initialization. failed to run 'ceph versions'. . timed out: exit status 1
2025-04-17 23:42:55.892509 I | ceph-cluster-controller: cluster "rook-ceph": version "18.2.4-0 reef" detected for image "quay.io/ceph/ceph:v18.2.4"
2025-04-17 23:42:55.922792 I | op-mon: start running mons
2025-04-17 23:42:55.926431 I | ceph-spec: parsing mon endpoints: a=10.96.11.92:6789,c=10.96.170.97:6789,b=10.96.228.121:6789
2025-04-17 23:42:55.940125 I | op-mon: saved mon endpoints to config map map[csi-cluster-config-json:[{"clusterID":"rook-ceph","monitors":["10.96.11.92:6789","10.96.170.97:6789","10.96.228.121:6789"],"cephFS":{"netNamespaceFilePath":"","subvolumeGroup":"","radosNamespace":"","kernelMountOptions":"","fuseMountOptions":""},"rbd":{"netNamespaceFilePath":"","radosNamespace":"","mirrorDaemonCount":0},"nfs":{"netNamespaceFilePath":""},"readAffinity":{"enabled":false,"crushLocationLabels":null},"namespace":""}] data:a=10.96.11.92:6789,c=10.96.170.97:6789,b=10.96.228.121:6789 externalMons: mapping:{"node":{"a":{"Name":"k1","Hostname":"k1","Address":"172.16.2.149"},"b":{"Name":"k3","Hostname":"k3","Address":"172.16.2.223"},"c":{"Name":"k2","Hostname":"k2","Address":"172.16.2.52"}}} maxMonId:2 outOfQuorum:]
2025-04-17 23:42:55.947872 I | op-mon: created/updated IPv4 endpointslice with addresses: [10.96.228.121 10.96.11.92 10.96.170.97]
2025-04-17 23:42:56.117499 I | cephclient: writing config file /var/lib/rook/rook-ceph/rook-ceph.config
2025-04-17 23:42:56.118095 I | cephclient: generated admin config in /var/lib/rook/rook-ceph
2025-04-17 23:42:57.717778 I | op-mon: targeting the mon count 3
2025-04-17 23:42:57.725297 I | op-config: applying ceph settings for "global"
2025-04-17 23:43:12.726983 I | exec: exec timeout waiting for process ceph to return. Sending interrupt signal to the process
2025-04-17 23:43:12.731998 E | op-config: failed to open assimilate output file /var/lib/rook/2829811856.out. open /var/lib/rook/2829811856.out: no such file or directory
2025-04-17 23:43:12.732018 E | op-config: failed to run command ceph [config assimilate-conf -i /var/lib/rook/2829811856 -o /var/lib/rook/2829811856.out]
2025-04-17 23:43:12.732026 E | op-config: failed to apply ceph settings for "global"
2025-04-17 23:43:12.732146 E | op-config: failed to remove file "/var/lib/rook/2829811856.out". remove /var/lib/rook/2829811856.out: no such file or directory
2025-04-17 23:43:12.732218 W | op-mon: failed to set Rook and/or user-defined Ceph config options before starting mons; will retry after starting mons. failed to apply default Ceph configurations: failed to set all keys: failed to set ceph config in the centralized mon configuration database; output: Cluster connection aborted: exit status 1
2025-04-17 23:43:12.732227 I | op-mon: checking for basic quorum with existing mons
2025-04-17 23:43:12.747183 I | op-mon: mon "a" cluster IP is 10.96.11.92
2025-04-17 23:43:12.758721 I | op-mon: mon "c" cluster IP is 10.96.170.97
2025-04-17 23:43:13.136815 I | op-mon: mon "b" cluster IP is 10.96.228.121
2025-04-17 23:43:13.735532 I | op-mon: saved mon endpoints to config map map[csi-cluster-config-json:[{"clusterID":"rook-ceph","monitors":["10.96.11.92:6789","10.96.170.97:6789","10.96.228.121:6789"],"cephFS":{"netNamespaceFilePath":"","subvolumeGroup":"","radosNamespace":"","kernelMountOptions":"","fuseMountOptions":""},"rbd":{"netNamespaceFilePath":"","radosNamespace":"","mirrorDaemonCount":0},"nfs":{"netNamespaceFilePath":""},"readAffinity":{"enabled":false,"crushLocationLabels":null},"namespace":""}] data:a=10.96.11.92:6789,c=10.96.170.97:6789,b=10.96.228.121:6789 externalMons: mapping:{"node":{"a":{"Name":"k1","Hostname":"k1","Address":"172.16.2.149"},"b":{"Name":"k3","Hostname":"k3","Address":"172.16.2.223"},"c":{"Name":"k2","Hostname":"k2","Address":"172.16.2.52"}}} maxMonId:2 outOfQuorum:]
2025-04-17 23:43:13.741444 I | op-mon: created/updated IPv4 endpointslice with addresses: [10.96.11.92 10.96.170.97 10.96.228.121]
2025-04-17 23:43:14.334907 I | cephclient: writing config file /var/lib/rook/rook-ceph/rook-ceph.config
2025-04-17 23:43:14.335168 I | cephclient: generated admin config in /var/lib/rook/rook-ceph
2025-04-17 23:43:14.745257 I | op-mon: deployment for mon rook-ceph-mon-a already exists. updating if needed
2025-04-17 23:43:14.753217 I | op-k8sutil: deployment "rook-ceph-mon-a" did not change, nothing to update
2025-04-17 23:43:14.753241 I | op-mon: waiting for mon quorum with [a c b]
2025-04-17 23:43:15.339105 I | op-mon: mons running: [a c b]
2025-04-17 23:43:35.536885 I | op-mon: mons running: [a c b]
2025-04-17 23:43:55.755761 I | op-mon: mons running: [a c b]
2025-04-17 23:44:15.962454 I | op-mon: mons running: [a c b]
2025-04-17 23:44:36.167529 I | op-mon: mons running: [a c b]
2025-04-17 23:44:56.364380 I | op-mon: mons running: [a c b]
2025-04-17 23:45:16.573287 I | op-mon: mons running: [a c b]
2025-04-17 23:45:36.763855 I | op-mon: mons running: [a c b]
2025-04-17 23:45:56.969402 I | op-mon: mons running: [a c b]
2025-04-17 23:46:17.179948 I | op-mon: mons running: [a c b]
2025-04-17 23:46:37.353634 I | op-mon: mons running: [a c b]
2025-04-17 23:46:57.540521 I | op-mon: mons running: [a c b]
2025-04-17 23:47:17.755551 I | op-mon: mons running: [a c b]
2025-04-17 23:47:37.949213 I | op-mon: mons running: [a c b]
2025-04-17 23:47:58.149528 I | op-mon: mons running: [a c b]
2025-04-17 23:48:18.335377 I | op-mon: mons running: [a c b]
2025-04-17 23:48:38.526128 I | op-mon: mons running: [a c b]
2025-04-17 23:48:58.724431 I | op-mon: mons running: [a c b]
2025-04-17 23:49:18.915118 I | op-mon: mons running: [a c b]
2025-04-17 23:49:39.120109 I | op-mon: mons running: [a c b]
2025-04-17 23:49:59.340772 I | op-mon: mons running: [a c b]
2025-04-17 23:50:19.530682 I | op-mon: mons running: [a c b]
2025-04-17 23:50:39.741572 I | op-mon: mons running: [a c b]
2025-04-17 23:50:59.939298 I | op-mon: mons running: [a c b]
2025-04-17 23:51:20.158261 I | op-mon: mons running: [a c b]
2025-04-17 23:51:40.354413 I | op-mon: mons running: [a c b]
2025-04-17 23:52:00.545609 I | op-mon: mons running: [a c b]
2025-04-17 23:52:20.739755 I | op-mon: mons running: [a c b]
2025-04-17 23:52:40.935105 I | op-mon: mons running: [a c b]
2025-04-17 23:53:01.157014 I | op-mon: mons running: [a c b]
2025-04-17 23:53:21.353860 I | op-mon: mons running: [a c b]
2025-04-17 23:53:41.548232 I | op-mon: mons running: [a c b]
2025-04-17 23:54:01.747291 I | op-mon: mons running: [a c b]
2025-04-17 23:54:21.954893 I | op-mon: mons running: [a c b]
2025-04-17 23:54:42.151168 I | op-mon: mons running: [a c b]
2025-04-17 23:55:02.348145 I | op-mon: mons running: [a c b]
2025-04-17 23:55:22.533632 I | op-mon: mons running: [a c b]
2025-04-17 23:55:42.747988 I | op-mon: mons running: [a c b]
2025-04-17 23:56:02.939990 I | op-mon: mons running: [a c b]
2025-04-17 23:56:23.136201 I | op-mon: mons running: [a c b]
2025-04-17 23:56:43.328812 I | op-mon: mons running: [a c b]
2025-04-17 23:57:03.518955 I | op-mon: mons running: [a c b]
2025-04-17 23:57:23.722088 I | op-mon: mons running: [a c b]
2025-04-17 23:57:43.933937 I | op-mon: mons running: [a c b]
2025-04-17 23:58:04.128198 I | op-mon: mons running: [a c b]
2025-04-17 23:58:24.323718 I | op-mon: mons running: [a c b]
2025-04-17 23:58:44.531577 I | op-mon: mons running: [a c b]
2025-04-17 23:59:04.749423 I | op-mon: mons running: [a c b]
2025-04-17 23:59:24.949133 I | op-mon: mons running: [a c b]
2025-04-17 23:59:45.132600 I | op-mon: mons running: [a c b]
2025-04-18 00:00:05.366264 I | op-mon: mons running: [a c b]
2025-04-18 00:00:25.567696 I | op-mon: mons running: [a c b]
2025-04-18 00:00:45.769002 I | op-mon: mons running: [a c b]
2025-04-18 00:01:05.971304 I | op-mon: mons running: [a c b]
2025-04-18 00:01:26.164306 I | op-mon: mons running: [a c b]
2025-04-18 00:01:46.369513 I | op-mon: mons running: [a c b]
2025-04-18 00:02:06.573625 I | op-mon: mons running: [a c b]
2025-04-18 00:02:26.760011 I | op-mon: mons running: [a c b]
2025-04-18 00:02:46.957772 I | op-mon: mons running: [a c b]
2025-04-18 00:03:07.173274 I | op-mon: mons running: [a c b]
2025-04-18 00:03:22.358331 E | ceph-cluster-controller: failed to reconcile CephCluster "rook-ceph/rook-ceph". failed to reconcile cluster "rook-ceph": failed to configure local ceph cluster: failed to create cluster: failed to start ceph monitors: failed to start mon pods: failed to check mon quorum a: failed to wait for mon quorum: exceeded max retry count waiting for monitors to reach quorum

citec@k1:~/osh$ kubectl -n rook-ceph describe pod rook-ceph-mon-a-6b84b89d56-jv6hm
Name:             rook-ceph-mon-a-6b84b89d56-jv6hm
Namespace:        rook-ceph
Priority:         0
Service Account:  rook-ceph-default
Node:             k1/172.16.2.149
Start Time:       Thu, 17 Apr 2025 16:09:55 +0900
Labels:           app=rook-ceph-mon
                  app.kubernetes.io/component=cephclusters.ceph.rook.io
                  app.kubernetes.io/created-by=rook-ceph-operator
                  app.kubernetes.io/instance=a
                  app.kubernetes.io/managed-by=rook-ceph-operator
                  app.kubernetes.io/name=ceph-mon
                  app.kubernetes.io/part-of=rook-ceph
                  ceph_daemon_id=a
                  ceph_daemon_type=mon
                  mon=a
                  mon_cluster=rook-ceph
                  mon_daemon=true
                  pod-template-hash=6b84b89d56
                  rook.io/operator-namespace=rook-ceph
                  rook_cluster=rook-ceph
Annotations:      cni.projectcalico.org/containerID: 2f38b95470c13fcd1ce6ce3370c9613210fff87c3f441d0c5c95eaf6f367a2ad
                  cni.projectcalico.org/podIP: 10.244.105.140/32
                  cni.projectcalico.org/podIPs: 10.244.105.140/32
Status:           Running
IP:               10.244.105.140
IPs:
  IP:           10.244.105.140
Controlled By:  ReplicaSet/rook-ceph-mon-a-6b84b89d56
Init Containers:
  chown-container-data-dir:
    Container ID:  containerd://70564fa15b4534ea45786740c7968f40b6997320a44fd42d96aebbb2bbf7d988
    Image:         quay.io/ceph/ceph:v18.2.4
    Image ID:      quay.io/ceph/ceph@sha256:6ac7f923aa1d23b43248ce0ddec7e1388855ee3d00813b52c3172b0b23b37906
    Port:          <none>
    Host Port:     <none>
    Command:
      chown
    Args:
      --verbose
      --recursive
      ceph:ceph
      /var/log/ceph
      /var/lib/ceph/crash
      /run/ceph
      /var/lib/ceph/mon/ceph-a
    State:          Terminated
      Reason:       Completed
      Exit Code:    0
      Started:      Thu, 17 Apr 2025 16:09:56 +0900
      Finished:     Thu, 17 Apr 2025 16:09:56 +0900
    Ready:          True
    Restart Count:  0
    Environment:    <none>
    Mounts:
      /etc/ceph from rook-config-override (ro)
      /etc/ceph/keyring-store/ from rook-ceph-mons-keyring (ro)
      /run/ceph from ceph-daemons-sock-dir (rw)
      /var/lib/ceph/crash from rook-ceph-crash (rw)
      /var/lib/ceph/mon/ceph-a from ceph-daemon-data (rw)
      /var/log/ceph from rook-ceph-log (rw)
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-9cxjj (ro)
  init-mon-fs:
    Container ID:  containerd://4f0cd854abb049d9b5b89937a84015936a8457fe64fb71ed49238359286ef767
    Image:         quay.io/ceph/ceph:v18.2.4
    Image ID:      quay.io/ceph/ceph@sha256:6ac7f923aa1d23b43248ce0ddec7e1388855ee3d00813b52c3172b0b23b37906
    Port:          <none>
    Host Port:     <none>
    Command:
      ceph-mon
    Args:
      --fsid=d9bb6004-5817-4d33-b7bf-f869d457973c
      --keyring=/etc/ceph/keyring-store/keyring
      --default-log-to-stderr=true
      --default-err-to-stderr=true
      --default-mon-cluster-log-to-stderr=true
      --default-log-stderr-prefix=debug
      --default-log-to-file=false
      --default-mon-cluster-log-to-file=false
      --mon-host=$(ROOK_CEPH_MON_HOST)
      --mon-initial-members=$(ROOK_CEPH_MON_INITIAL_MEMBERS)
      --id=a
      --setuser=ceph
      --setgroup=ceph
      --public-addr=10.96.11.92
      --mkfs
    State:          Terminated
      Reason:       Completed
      Exit Code:    0
      Started:      Thu, 17 Apr 2025 16:09:57 +0900
      Finished:     Thu, 17 Apr 2025 16:09:57 +0900
    Ready:          True
    Restart Count:  0
    Environment:
      CONTAINER_IMAGE:                quay.io/ceph/ceph:v18.2.4
      POD_NAME:                       rook-ceph-mon-a-6b84b89d56-jv6hm (v1:metadata.name)
      POD_NAMESPACE:                  rook-ceph (v1:metadata.namespace)
      NODE_NAME:                       (v1:spec.nodeName)
      POD_MEMORY_LIMIT:               node allocatable (limits.memory)
      POD_MEMORY_REQUEST:             0 (requests.memory)
      POD_CPU_LIMIT:                  node allocatable (limits.cpu)
      POD_CPU_REQUEST:                0 (requests.cpu)
      CEPH_USE_RANDOM_NONCE:          true
      ROOK_CEPH_MON_HOST:             <set to the key 'mon_host' in secret 'rook-ceph-config'>             Optional: false
      ROOK_CEPH_MON_INITIAL_MEMBERS:  <set to the key 'mon_initial_members' in secret 'rook-ceph-config'>  Optional: false
    Mounts:
      /etc/ceph from rook-config-override (ro)
      /etc/ceph/keyring-store/ from rook-ceph-mons-keyring (ro)
      /run/ceph from ceph-daemons-sock-dir (rw)
      /var/lib/ceph/crash from rook-ceph-crash (rw)
      /var/lib/ceph/mon/ceph-a from ceph-daemon-data (rw)
      /var/log/ceph from rook-ceph-log (rw)
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-9cxjj (ro)
Containers:
  mon:
    Container ID:  containerd://91ac07ffca6d8fd4cbbde2b8204d0ea3db09a9ebc786ecae7eb2dcb7c83be6f8
    Image:         quay.io/ceph/ceph:v18.2.4
    Image ID:      quay.io/ceph/ceph@sha256:6ac7f923aa1d23b43248ce0ddec7e1388855ee3d00813b52c3172b0b23b37906
    Ports:         3300/TCP, 6789/TCP
    Host Ports:    0/TCP, 0/TCP
    Command:
      ceph-mon
    Args:
      --fsid=d9bb6004-5817-4d33-b7bf-f869d457973c
      --keyring=/etc/ceph/keyring-store/keyring
      --default-log-to-stderr=true
      --default-err-to-stderr=true
      --default-mon-cluster-log-to-stderr=true
      --default-log-stderr-prefix=debug
      --default-log-to-file=false
      --default-mon-cluster-log-to-file=false
      --mon-host=$(ROOK_CEPH_MON_HOST)
      --mon-initial-members=$(ROOK_CEPH_MON_INITIAL_MEMBERS)
      --id=a
      --setuser=ceph
      --setgroup=ceph
      --foreground
      --public-addr=10.96.11.92
      --setuser-match-path=/var/lib/ceph/mon/ceph-a/store.db
      --public-bind-addr=$(ROOK_POD_IP)
    State:          Running
      Started:      Thu, 17 Apr 2025 16:09:58 +0900
    Ready:          True
    Restart Count:  0
    Liveness:       exec [env -i sh -c
outp="$(ceph --admin-daemon /run/ceph/ceph-mon.a.asok mon_status 2>&1)"
rc=$?
if [ $rc -ne 0 ]; then
  echo "ceph daemon health check failed with the following output:"
  echo "$outp" | sed -e 's/^/> /g'
  exit $rc
fi
] delay=10s timeout=5s period=10s #success=1 #failure=3
    Startup:  exec [env -i sh -c
outp="$(ceph --admin-daemon /run/ceph/ceph-mon.a.asok mon_status 2>&1)"
rc=$?
if [ $rc -ne 0 ]; then
  echo "ceph daemon health check failed with the following output:"
  echo "$outp" | sed -e 's/^/> /g'
  exit $rc
fi
] delay=10s timeout=5s period=10s #success=1 #failure=6
    Environment:
      CONTAINER_IMAGE:                quay.io/ceph/ceph:v18.2.4
      POD_NAME:                       rook-ceph-mon-a-6b84b89d56-jv6hm (v1:metadata.name)
      POD_NAMESPACE:                  rook-ceph (v1:metadata.namespace)
      NODE_NAME:                       (v1:spec.nodeName)
      POD_MEMORY_LIMIT:               node allocatable (limits.memory)
      POD_MEMORY_REQUEST:             0 (requests.memory)
      POD_CPU_LIMIT:                  node allocatable (limits.cpu)
      POD_CPU_REQUEST:                0 (requests.cpu)
      CEPH_USE_RANDOM_NONCE:          true
      ROOK_CEPH_MON_HOST:             <set to the key 'mon_host' in secret 'rook-ceph-config'>             Optional: false
      ROOK_CEPH_MON_INITIAL_MEMBERS:  <set to the key 'mon_initial_members' in secret 'rook-ceph-config'>  Optional: false
      ROOK_POD_IP:                     (v1:status.podIP)
    Mounts:
      /etc/ceph from rook-config-override (ro)
      /etc/ceph/keyring-store/ from rook-ceph-mons-keyring (ro)
      /run/ceph from ceph-daemons-sock-dir (rw)
      /var/lib/ceph/crash from rook-ceph-crash (rw)
      /var/lib/ceph/mon/ceph-a from ceph-daemon-data (rw)
      /var/log/ceph from rook-ceph-log (rw)
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-9cxjj (ro)
Conditions:
  Type                        Status
  PodReadyToStartContainers   True
  Initialized                 True
  Ready                       True
  ContainersReady             True
  PodScheduled                True
Volumes:
  rook-config-override:
    Type:               Projected (a volume that contains injected data from multiple sources)
    ConfigMapName:      rook-config-override
    ConfigMapOptional:  <nil>
  rook-ceph-mons-keyring:
    Type:        Secret (a volume populated by a Secret)
    SecretName:  rook-ceph-mons-keyring
    Optional:    false
  ceph-daemons-sock-dir:
    Type:          HostPath (bare host directory volume)
    Path:          /var/lib/rook/exporter
    HostPathType:  DirectoryOrCreate
  rook-ceph-log:
    Type:          HostPath (bare host directory volume)
    Path:          /var/lib/rook/rook-ceph/log
    HostPathType:
  rook-ceph-crash:
    Type:          HostPath (bare host directory volume)
    Path:          /var/lib/rook/rook-ceph/crash
    HostPathType:
  ceph-daemon-data:
    Type:          HostPath (bare host directory volume)
    Path:          /var/lib/rook/mon-a/data
    HostPathType:
  kube-api-access-9cxjj:
    Type:                    Projected (a volume that contains injected data from multiple sources)
    TokenExpirationSeconds:  3607
    ConfigMapName:           kube-root-ca.crt
    ConfigMapOptional:       <nil>
    DownwardAPI:             true
QoS Class:                   BestEffort
Node-Selectors:              kubernetes.io/hostname=k1
Tolerations:                 node.kubernetes.io/not-ready:NoExecute op=Exists for 300s
                             node.kubernetes.io/unreachable:NoExecute op=Exists for 300s
Events:                      <none>
citec@k1:~/osh$ kubectl -n rook-ceph describe pod rook-ceph-mon-b-66789dfd6-c9pct
Name:             rook-ceph-mon-b-66789dfd6-c9pct
Namespace:        rook-ceph
Priority:         0
Service Account:  rook-ceph-default
Node:             k3/172.16.2.223
Start Time:       Thu, 17 Apr 2025 16:30:08 +0900
Labels:           app=rook-ceph-mon
                  app.kubernetes.io/component=cephclusters.ceph.rook.io
                  app.kubernetes.io/created-by=rook-ceph-operator
                  app.kubernetes.io/instance=b
                  app.kubernetes.io/managed-by=rook-ceph-operator
                  app.kubernetes.io/name=ceph-mon
                  app.kubernetes.io/part-of=rook-ceph
                  ceph_daemon_id=b
                  ceph_daemon_type=mon
                  mon=b
                  mon_cluster=rook-ceph
                  mon_daemon=true
                  pod-template-hash=66789dfd6
                  rook.io/operator-namespace=rook-ceph
                  rook_cluster=rook-ceph
Annotations:      cni.projectcalico.org/containerID: 4307474bbe5581a800372ab5c0b148bfaef1fb13af7d405ea63dd310202d8639
                  cni.projectcalico.org/podIP: 10.244.195.149/32
                  cni.projectcalico.org/podIPs: 10.244.195.149/32
Status:           Running
IP:               10.244.195.149
IPs:
  IP:           10.244.195.149
Controlled By:  ReplicaSet/rook-ceph-mon-b-66789dfd6
Init Containers:
  chown-container-data-dir:
    Container ID:  containerd://7f5b3c26aaee964c9ecf29b949e7ecaf7ce0b82a8d6487ab710ef9c6f5b36388
    Image:         quay.io/ceph/ceph:v18.2.4
    Image ID:      quay.io/ceph/ceph@sha256:6ac7f923aa1d23b43248ce0ddec7e1388855ee3d00813b52c3172b0b23b37906
    Port:          <none>
    Host Port:     <none>
    Command:
      chown
    Args:
      --verbose
      --recursive
      ceph:ceph
      /var/log/ceph
      /var/lib/ceph/crash
      /run/ceph
      /var/lib/ceph/mon/ceph-b
    State:          Terminated
      Reason:       Completed
      Exit Code:    0
      Started:      Thu, 17 Apr 2025 16:30:08 +0900
      Finished:     Thu, 17 Apr 2025 16:30:08 +0900
    Ready:          True
    Restart Count:  0
    Environment:    <none>
    Mounts:
      /etc/ceph from rook-config-override (ro)
      /etc/ceph/keyring-store/ from rook-ceph-mons-keyring (ro)
      /run/ceph from ceph-daemons-sock-dir (rw)
      /var/lib/ceph/crash from rook-ceph-crash (rw)
      /var/lib/ceph/mon/ceph-b from ceph-daemon-data (rw)
      /var/log/ceph from rook-ceph-log (rw)
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-qbxqd (ro)
  init-mon-fs:
    Container ID:  containerd://eb393eb0c02b182887a722d753e6aeecdc7a5307013aa6f5c94b7a2d4be88299
    Image:         quay.io/ceph/ceph:v18.2.4
    Image ID:      quay.io/ceph/ceph@sha256:6ac7f923aa1d23b43248ce0ddec7e1388855ee3d00813b52c3172b0b23b37906
    Port:          <none>
    Host Port:     <none>
    Command:
      ceph-mon
    Args:
      --fsid=d9bb6004-5817-4d33-b7bf-f869d457973c
      --keyring=/etc/ceph/keyring-store/keyring
      --default-log-to-stderr=true
      --default-err-to-stderr=true
      --default-mon-cluster-log-to-stderr=true
      --default-log-stderr-prefix=debug
      --default-log-to-file=false
      --default-mon-cluster-log-to-file=false
      --mon-host=$(ROOK_CEPH_MON_HOST)
      --mon-initial-members=$(ROOK_CEPH_MON_INITIAL_MEMBERS)
      --id=b
      --setuser=ceph
      --setgroup=ceph
      --public-addr=10.96.228.121
      --mkfs
    State:          Terminated
      Reason:       Completed
      Exit Code:    0
      Started:      Thu, 17 Apr 2025 16:30:09 +0900
      Finished:     Thu, 17 Apr 2025 16:30:09 +0900
    Ready:          True
    Restart Count:  0
    Environment:
      CONTAINER_IMAGE:                quay.io/ceph/ceph:v18.2.4
      POD_NAME:                       rook-ceph-mon-b-66789dfd6-c9pct (v1:metadata.name)
      POD_NAMESPACE:                  rook-ceph (v1:metadata.namespace)
      NODE_NAME:                       (v1:spec.nodeName)
      POD_MEMORY_LIMIT:               node allocatable (limits.memory)
      POD_MEMORY_REQUEST:             0 (requests.memory)
      POD_CPU_LIMIT:                  node allocatable (limits.cpu)
      POD_CPU_REQUEST:                0 (requests.cpu)
      CEPH_USE_RANDOM_NONCE:          true
      ROOK_CEPH_MON_HOST:             <set to the key 'mon_host' in secret 'rook-ceph-config'>             Optional: false
      ROOK_CEPH_MON_INITIAL_MEMBERS:  <set to the key 'mon_initial_members' in secret 'rook-ceph-config'>  Optional: false
    Mounts:
      /etc/ceph from rook-config-override (ro)
      /etc/ceph/keyring-store/ from rook-ceph-mons-keyring (ro)
      /run/ceph from ceph-daemons-sock-dir (rw)
      /var/lib/ceph/crash from rook-ceph-crash (rw)
      /var/lib/ceph/mon/ceph-b from ceph-daemon-data (rw)
      /var/log/ceph from rook-ceph-log (rw)
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-qbxqd (ro)
Containers:
  mon:
    Container ID:  containerd://6fbd8796aa138b85dc8de12111174e98cdd02cfd3322bc2b6e315b392f0e13ec
    Image:         quay.io/ceph/ceph:v18.2.4
    Image ID:      quay.io/ceph/ceph@sha256:6ac7f923aa1d23b43248ce0ddec7e1388855ee3d00813b52c3172b0b23b37906
    Ports:         3300/TCP, 6789/TCP
    Host Ports:    0/TCP, 0/TCP
    Command:
      ceph-mon
    Args:
      --fsid=d9bb6004-5817-4d33-b7bf-f869d457973c
      --keyring=/etc/ceph/keyring-store/keyring
      --default-log-to-stderr=true
      --default-err-to-stderr=true
      --default-mon-cluster-log-to-stderr=true
      --default-log-stderr-prefix=debug
      --default-log-to-file=false
      --default-mon-cluster-log-to-file=false
      --mon-host=$(ROOK_CEPH_MON_HOST)
      --mon-initial-members=$(ROOK_CEPH_MON_INITIAL_MEMBERS)
      --id=b
      --setuser=ceph
      --setgroup=ceph
      --foreground
      --public-addr=10.96.228.121
      --setuser-match-path=/var/lib/ceph/mon/ceph-b/store.db
      --public-bind-addr=$(ROOK_POD_IP)
    State:          Running
      Started:      Fri, 18 Apr 2025 06:39:35 +0900
    Last State:     Terminated
      Reason:       OOMKilled
      Exit Code:    137
      Started:      Thu, 17 Apr 2025 16:30:10 +0900
      Finished:     Fri, 18 Apr 2025 06:39:34 +0900
    Ready:          True
    Restart Count:  1
    Liveness:       exec [env -i sh -c
outp="$(ceph --admin-daemon /run/ceph/ceph-mon.b.asok mon_status 2>&1)"
rc=$?
if [ $rc -ne 0 ]; then
  echo "ceph daemon health check failed with the following output:"
  echo "$outp" | sed -e 's/^/> /g'
  exit $rc
fi
] delay=10s timeout=5s period=10s #success=1 #failure=3
    Startup:  exec [env -i sh -c
outp="$(ceph --admin-daemon /run/ceph/ceph-mon.b.asok mon_status 2>&1)"
rc=$?
if [ $rc -ne 0 ]; then
  echo "ceph daemon health check failed with the following output:"
  echo "$outp" | sed -e 's/^/> /g'
  exit $rc
fi
] delay=10s timeout=5s period=10s #success=1 #failure=6
    Environment:
      CONTAINER_IMAGE:                quay.io/ceph/ceph:v18.2.4
      POD_NAME:                       rook-ceph-mon-b-66789dfd6-c9pct (v1:metadata.name)
      POD_NAMESPACE:                  rook-ceph (v1:metadata.namespace)
      NODE_NAME:                       (v1:spec.nodeName)
      POD_MEMORY_LIMIT:               node allocatable (limits.memory)
      POD_MEMORY_REQUEST:             0 (requests.memory)
      POD_CPU_LIMIT:                  node allocatable (limits.cpu)
      POD_CPU_REQUEST:                0 (requests.cpu)
      CEPH_USE_RANDOM_NONCE:          true
      ROOK_CEPH_MON_HOST:             <set to the key 'mon_host' in secret 'rook-ceph-config'>             Optional: false
      ROOK_CEPH_MON_INITIAL_MEMBERS:  <set to the key 'mon_initial_members' in secret 'rook-ceph-config'>  Optional: false
      ROOK_POD_IP:                     (v1:status.podIP)
    Mounts:
      /etc/ceph from rook-config-override (ro)
      /etc/ceph/keyring-store/ from rook-ceph-mons-keyring (ro)
      /run/ceph from ceph-daemons-sock-dir (rw)
      /var/lib/ceph/crash from rook-ceph-crash (rw)
      /var/lib/ceph/mon/ceph-b from ceph-daemon-data (rw)
      /var/log/ceph from rook-ceph-log (rw)
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-qbxqd (ro)
Conditions:
  Type                        Status
  PodReadyToStartContainers   True
  Initialized                 True
  Ready                       True
  ContainersReady             True
  PodScheduled                True
Volumes:
  rook-config-override:
    Type:               Projected (a volume that contains injected data from multiple sources)
    ConfigMapName:      rook-config-override
    ConfigMapOptional:  <nil>
  rook-ceph-mons-keyring:
    Type:        Secret (a volume populated by a Secret)
    SecretName:  rook-ceph-mons-keyring
    Optional:    false
  ceph-daemons-sock-dir:
    Type:          HostPath (bare host directory volume)
    Path:          /var/lib/rook/exporter
    HostPathType:  DirectoryOrCreate
  rook-ceph-log:
    Type:          HostPath (bare host directory volume)
    Path:          /var/lib/rook/rook-ceph/log
    HostPathType:
  rook-ceph-crash:
    Type:          HostPath (bare host directory volume)
    Path:          /var/lib/rook/rook-ceph/crash
    HostPathType:
  ceph-daemon-data:
    Type:          HostPath (bare host directory volume)
    Path:          /var/lib/rook/mon-b/data
    HostPathType:
  kube-api-access-qbxqd:
    Type:                    Projected (a volume that contains injected data from multiple sources)
    TokenExpirationSeconds:  3607
    ConfigMapName:           kube-root-ca.crt
    ConfigMapOptional:       <nil>
    DownwardAPI:             true
QoS Class:                   BestEffort
Node-Selectors:              kubernetes.io/hostname=k3
Tolerations:                 node.kubernetes.io/not-ready:NoExecute op=Exists for 300s
                             node.kubernetes.io/unreachable:NoExecute op=Exists for 300s
Events:                      <none>
citec@k1:~/osh$ kubectl -n rook-ceph describe pod rook-ceph-mon-c-648dbbff5c-b8vth
Name:             rook-ceph-mon-c-648dbbff5c-b8vth
Namespace:        rook-ceph
Priority:         0
Service Account:  rook-ceph-default
Node:             k2/172.16.2.52
Start Time:       Thu, 17 Apr 2025 16:50:51 +0900
Labels:           app=rook-ceph-mon
                  app.kubernetes.io/component=cephclusters.ceph.rook.io
                  app.kubernetes.io/created-by=rook-ceph-operator
                  app.kubernetes.io/instance=c
                  app.kubernetes.io/managed-by=rook-ceph-operator
                  app.kubernetes.io/name=ceph-mon
                  app.kubernetes.io/part-of=rook-ceph
                  ceph_daemon_id=c
                  ceph_daemon_type=mon
                  mon=c
                  mon_cluster=rook-ceph
                  mon_daemon=true
                  pod-template-hash=648dbbff5c
                  rook.io/operator-namespace=rook-ceph
                  rook_cluster=rook-ceph
Annotations:      cni.projectcalico.org/containerID: 93b306b96baece79a0b2379226f091b8d8cf475f52bee41e188485e094e8c5ba
                  cni.projectcalico.org/podIP: 10.244.99.18/32
                  cni.projectcalico.org/podIPs: 10.244.99.18/32
Status:           Running
IP:               10.244.99.18
IPs:
  IP:           10.244.99.18
Controlled By:  ReplicaSet/rook-ceph-mon-c-648dbbff5c
Init Containers:
  chown-container-data-dir:
    Container ID:  containerd://9f403176dd8c55c83054328bef1b9fa9ed1e99bc551c972c7d644748c1579e51
    Image:         quay.io/ceph/ceph:v18.2.4
    Image ID:      quay.io/ceph/ceph@sha256:6ac7f923aa1d23b43248ce0ddec7e1388855ee3d00813b52c3172b0b23b37906
    Port:          <none>
    Host Port:     <none>
    Command:
      chown
    Args:
      --verbose
      --recursive
      ceph:ceph
      /var/log/ceph
      /var/lib/ceph/crash
      /run/ceph
      /var/lib/ceph/mon/ceph-c
    State:          Terminated
      Reason:       Completed
      Exit Code:    0
      Started:      Thu, 17 Apr 2025 16:50:52 +0900
      Finished:     Thu, 17 Apr 2025 16:50:52 +0900
    Ready:          True
    Restart Count:  0
    Environment:    <none>
    Mounts:
      /etc/ceph from rook-config-override (ro)
      /etc/ceph/keyring-store/ from rook-ceph-mons-keyring (ro)
      /run/ceph from ceph-daemons-sock-dir (rw)
      /var/lib/ceph/crash from rook-ceph-crash (rw)
      /var/lib/ceph/mon/ceph-c from ceph-daemon-data (rw)
      /var/log/ceph from rook-ceph-log (rw)
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-w7tck (ro)
  init-mon-fs:
    Container ID:  containerd://efe017a72d426ada30fa4b31ca62857202e3dc6d59b3787350d76efb00bd24e5
    Image:         quay.io/ceph/ceph:v18.2.4
    Image ID:      quay.io/ceph/ceph@sha256:6ac7f923aa1d23b43248ce0ddec7e1388855ee3d00813b52c3172b0b23b37906
    Port:          <none>
    Host Port:     <none>
    Command:
      ceph-mon
    Args:
      --fsid=d9bb6004-5817-4d33-b7bf-f869d457973c
      --keyring=/etc/ceph/keyring-store/keyring
      --default-log-to-stderr=true
      --default-err-to-stderr=true
      --default-mon-cluster-log-to-stderr=true
      --default-log-stderr-prefix=debug
      --default-log-to-file=false
      --default-mon-cluster-log-to-file=false
      --mon-host=$(ROOK_CEPH_MON_HOST)
      --mon-initial-members=$(ROOK_CEPH_MON_INITIAL_MEMBERS)
      --id=c
      --setuser=ceph
      --setgroup=ceph
      --public-addr=10.96.170.97
      --mkfs
    State:          Terminated
      Reason:       Completed
      Exit Code:    0
      Started:      Thu, 17 Apr 2025 16:50:53 +0900
      Finished:     Thu, 17 Apr 2025 16:50:53 +0900
    Ready:          True
    Restart Count:  0
    Environment:
      CONTAINER_IMAGE:                quay.io/ceph/ceph:v18.2.4
      POD_NAME:                       rook-ceph-mon-c-648dbbff5c-b8vth (v1:metadata.name)
      POD_NAMESPACE:                  rook-ceph (v1:metadata.namespace)
      NODE_NAME:                       (v1:spec.nodeName)
      POD_MEMORY_LIMIT:               node allocatable (limits.memory)
      POD_MEMORY_REQUEST:             0 (requests.memory)
      POD_CPU_LIMIT:                  node allocatable (limits.cpu)
      POD_CPU_REQUEST:                0 (requests.cpu)
      CEPH_USE_RANDOM_NONCE:          true
      ROOK_CEPH_MON_HOST:             <set to the key 'mon_host' in secret 'rook-ceph-config'>             Optional: false
      ROOK_CEPH_MON_INITIAL_MEMBERS:  <set to the key 'mon_initial_members' in secret 'rook-ceph-config'>  Optional: false
    Mounts:
      /etc/ceph from rook-config-override (ro)
      /etc/ceph/keyring-store/ from rook-ceph-mons-keyring (ro)
      /run/ceph from ceph-daemons-sock-dir (rw)
      /var/lib/ceph/crash from rook-ceph-crash (rw)
      /var/lib/ceph/mon/ceph-c from ceph-daemon-data (rw)
      /var/log/ceph from rook-ceph-log (rw)
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-w7tck (ro)
Containers:
  mon:
    Container ID:  containerd://11c474086f4c845954378be95949cd3d4f9c405d221814965ac06a0e69108d62
    Image:         quay.io/ceph/ceph:v18.2.4
    Image ID:      quay.io/ceph/ceph@sha256:6ac7f923aa1d23b43248ce0ddec7e1388855ee3d00813b52c3172b0b23b37906
    Ports:         3300/TCP, 6789/TCP
    Host Ports:    0/TCP, 0/TCP
    Command:
      ceph-mon
    Args:
      --fsid=d9bb6004-5817-4d33-b7bf-f869d457973c
      --keyring=/etc/ceph/keyring-store/keyring
      --default-log-to-stderr=true
      --default-err-to-stderr=true
      --default-mon-cluster-log-to-stderr=true
      --default-log-stderr-prefix=debug
      --default-log-to-file=false
      --default-mon-cluster-log-to-file=false
      --mon-host=$(ROOK_CEPH_MON_HOST)
      --mon-initial-members=$(ROOK_CEPH_MON_INITIAL_MEMBERS)
      --id=c
      --setuser=ceph
      --setgroup=ceph
      --foreground
      --public-addr=10.96.170.97
      --setuser-match-path=/var/lib/ceph/mon/ceph-c/store.db
      --public-bind-addr=$(ROOK_POD_IP)
    State:          Running
      Started:      Thu, 17 Apr 2025 16:50:54 +0900
    Ready:          True
    Restart Count:  0
    Liveness:       exec [env -i sh -c
outp="$(ceph --admin-daemon /run/ceph/ceph-mon.c.asok mon_status 2>&1)"
rc=$?
if [ $rc -ne 0 ]; then
  echo "ceph daemon health check failed with the following output:"
  echo "$outp" | sed -e 's/^/> /g'
  exit $rc
fi
] delay=10s timeout=5s period=10s #success=1 #failure=3
    Startup:  exec [env -i sh -c
outp="$(ceph --admin-daemon /run/ceph/ceph-mon.c.asok mon_status 2>&1)"
rc=$?
if [ $rc -ne 0 ]; then
  echo "ceph daemon health check failed with the following output:"
  echo "$outp" | sed -e 's/^/> /g'
  exit $rc
fi
] delay=10s timeout=5s period=10s #success=1 #failure=6
    Environment:
      CONTAINER_IMAGE:                quay.io/ceph/ceph:v18.2.4
      POD_NAME:                       rook-ceph-mon-c-648dbbff5c-b8vth (v1:metadata.name)
      POD_NAMESPACE:                  rook-ceph (v1:metadata.namespace)
      NODE_NAME:                       (v1:spec.nodeName)
      POD_MEMORY_LIMIT:               node allocatable (limits.memory)
      POD_MEMORY_REQUEST:             0 (requests.memory)
      POD_CPU_LIMIT:                  node allocatable (limits.cpu)
      POD_CPU_REQUEST:                0 (requests.cpu)
      CEPH_USE_RANDOM_NONCE:          true
      ROOK_CEPH_MON_HOST:             <set to the key 'mon_host' in secret 'rook-ceph-config'>             Optional: false
      ROOK_CEPH_MON_INITIAL_MEMBERS:  <set to the key 'mon_initial_members' in secret 'rook-ceph-config'>  Optional: false
      ROOK_POD_IP:                     (v1:status.podIP)
    Mounts:
      /etc/ceph from rook-config-override (ro)
      /etc/ceph/keyring-store/ from rook-ceph-mons-keyring (ro)
      /run/ceph from ceph-daemons-sock-dir (rw)
      /var/lib/ceph/crash from rook-ceph-crash (rw)
      /var/lib/ceph/mon/ceph-c from ceph-daemon-data (rw)
      /var/log/ceph from rook-ceph-log (rw)
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-w7tck (ro)
Conditions:
  Type                        Status
  PodReadyToStartContainers   True
  Initialized                 True
  Ready                       True
  ContainersReady             True
  PodScheduled                True
Volumes:
  rook-config-override:
    Type:               Projected (a volume that contains injected data from multiple sources)
    ConfigMapName:      rook-config-override
    ConfigMapOptional:  <nil>
  rook-ceph-mons-keyring:
    Type:        Secret (a volume populated by a Secret)
    SecretName:  rook-ceph-mons-keyring
    Optional:    false
  ceph-daemons-sock-dir:
    Type:          HostPath (bare host directory volume)
    Path:          /var/lib/rook/exporter
    HostPathType:  DirectoryOrCreate
  rook-ceph-log:
    Type:          HostPath (bare host directory volume)
    Path:          /var/lib/rook/rook-ceph/log
    HostPathType:
  rook-ceph-crash:
    Type:          HostPath (bare host directory volume)
    Path:          /var/lib/rook/rook-ceph/crash
    HostPathType:
  ceph-daemon-data:
    Type:          HostPath (bare host directory volume)
    Path:          /var/lib/rook/mon-c/data
    HostPathType:
  kube-api-access-w7tck:
    Type:                    Projected (a volume that contains injected data from multiple sources)
    TokenExpirationSeconds:  3607
    ConfigMapName:           kube-root-ca.crt
    ConfigMapOptional:       <nil>
    DownwardAPI:             true
QoS Class:                   BestEffort
Node-Selectors:              kubernetes.io/hostname=k2
Tolerations:                 node.kubernetes.io/not-ready:NoExecute op=Exists for 300s
                             node.kubernetes.io/unreachable:NoExecute op=Exists for 300s
Events:                      <none>

citec@k1:~/osh$ kubectl -n rook-ceph logs rook-ceph-mon-a-6b84b89d56-jv6hm | tail -n 100
Defaulted container "mon" out of: mon, chown-container-data-dir (init), init-mon-fs (init)
debug 2025-04-18T00:45:16.379+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:45:16.379+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:45:17.475+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12658 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:45:22.475+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12658 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:45:26.375+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:45:26.375+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:45:27.475+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12660 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:45:32.479+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12660 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:45:36.375+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:45:36.375+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:45:37.479+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12662 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:45:42.479+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12662 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:45:46.379+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:45:46.379+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:45:47.483+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12664 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:45:52.483+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12664 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:45:56.383+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:45:56.383+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:45:57.483+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12666 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:46:02.487+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12666 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:46:06.387+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:46:06.391+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:46:07.487+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12668 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:46:12.487+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12668 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:46:16.379+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:46:16.379+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:46:17.487+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12670 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:46:22.491+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12670 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:46:26.375+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:46:26.375+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:46:27.491+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12672 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:46:32.491+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12672 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:46:36.375+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:46:36.375+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:46:37.495+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12674 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:46:42.495+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12674 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:46:46.383+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:46:46.383+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:46:47.495+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12676 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:46:52.499+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12676 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:46:56.379+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:46:56.379+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:46:57.499+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12678 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:47:02.499+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12678 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:47:06.371+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:47:06.375+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:47:07.499+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12680 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:47:12.503+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12680 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:47:16.375+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:47:16.375+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:47:17.503+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12682 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:47:22.503+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12682 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:47:26.379+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:47:26.379+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:47:27.507+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12684 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:47:32.507+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12684 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:47:36.379+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:47:36.379+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:47:37.507+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12686 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:47:42.507+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12686 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:47:46.371+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:47:46.371+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:47:47.511+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12688 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:47:52.511+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12688 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:47:56.375+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:47:56.375+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:47:57.511+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12690 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:48:02.515+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12690 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:48:06.395+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:48:06.395+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:48:07.515+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12692 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:48:12.515+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12692 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:48:16.371+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:48:16.375+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:48:17.519+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12694 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:48:22.519+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12694 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:48:26.379+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:48:26.379+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:48:27.519+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12696 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:48:32.519+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12696 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:48:36.379+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:48:36.383+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:48:37.523+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12698 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:48:42.523+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12698 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:48:46.375+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:48:46.375+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:48:47.523+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12700 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:48:52.527+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12700 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:48:56.375+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:48:56.379+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:48:57.527+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12702 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:49:02.527+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12702 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:49:06.379+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:49:06.379+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:49:07.527+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12704 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:49:12.531+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12704 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:49:16.375+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:49:16.375+0000 7fc66a099640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:49:17.531+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12706 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
debug 2025-04-18T00:49:22.531+0000 7fc6666d5640 -1 mon.a@0(probing) e2 get_health_metrics reporting 12706 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:10:16.386117+0000)
citec@k1:~/osh$ kubectl -n rook-ceph logs rook-ceph-mon-b-66789dfd6-c9pct | tail -n 100
Defaulted container "mon" out of: mon, chown-container-data-dir (init), init-mon-fs (init)
debug 2025-04-18T00:45:58.736+0000 7ff9141df640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:46:03.268+0000 7ff91081b640 -1 mon.b@0(probing) e0 get_health_metrics reporting 2232 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T21:39:48.991759+0000)
debug 2025-04-18T00:46:08.268+0000 7ff91081b640 -1 mon.b@0(probing) e0 get_health_metrics reporting 2232 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T21:39:48.991759+0000)
debug 2025-04-18T00:46:08.724+0000 7ff9141df640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:46:08.724+0000 7ff9141df640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:46:13.268+0000 7ff91081b640 -1 mon.b@0(probing) e0 get_health_metrics reporting 2234 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T21:39:48.991759+0000)
debug 2025-04-18T00:46:18.268+0000 7ff91081b640 -1 mon.b@0(probing) e0 get_health_metrics reporting 2234 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T21:39:48.991759+0000)
debug 2025-04-18T00:46:18.732+0000 7ff9141df640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:46:18.736+0000 7ff9141df640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:46:23.268+0000 7ff91081b640 -1 mon.b@0(probing) e0 get_health_metrics reporting 2236 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T21:39:48.991759+0000)
debug 2025-04-18T00:46:28.268+0000 7ff91081b640 -1 mon.b@0(probing) e0 get_health_metrics reporting 2236 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T21:39:48.991759+0000)
debug 2025-04-18T00:46:28.724+0000 7ff9141df640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:46:28.724+0000 7ff9141df640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:46:33.268+0000 7ff91081b640 -1 mon.b@0(probing) e0 get_health_metrics reporting 2238 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T21:39:48.991759+0000)
debug 2025-04-18T00:46:38.268+0000 7ff91081b640 -1 mon.b@0(probing) e0 get_health_metrics reporting 2238 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T21:39:48.991759+0000)
debug 2025-04-18T00:46:38.720+0000 7ff9141df640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:46:38.720+0000 7ff9141df640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:46:43.272+0000 7ff91081b640 -1 mon.b@0(probing) e0 get_health_metrics reporting 2240 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T21:39:48.991759+0000)
debug 2025-04-18T00:46:48.272+0000 7ff91081b640 -1 mon.b@0(probing) e0 get_health_metrics reporting 2240 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T21:39:48.991759+0000)
debug 2025-04-18T00:46:48.724+0000 7ff9141df640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:46:48.728+0000 7ff9141df640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:46:53.272+0000 7ff91081b640 -1 mon.b@0(probing) e0 get_health_metrics reporting 2242 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T21:39:48.991759+0000)
debug 2025-04-18T00:46:58.272+0000 7ff91081b640 -1 mon.b@0(probing) e0 get_health_metrics reporting 2242 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T21:39:48.991759+0000)
debug 2025-04-18T00:46:58.720+0000 7ff9141df640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:46:58.720+0000 7ff9141df640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:47:03.272+0000 7ff91081b640 -1 mon.b@0(probing) e0 get_health_metrics reporting 2244 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T21:39:48.991759+0000)
debug 2025-04-18T00:47:08.276+0000 7ff91081b640 -1 mon.b@0(probing) e0 get_health_metrics reporting 2244 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T21:39:48.991759+0000)
debug 2025-04-18T00:47:08.724+0000 7ff9141df640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:47:08.724+0000 7ff9141df640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:47:13.272+0000 7ff91081b640 -1 mon.b@0(probing) e0 get_health_metrics reporting 2246 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T21:39:48.991759+0000)
debug 2025-04-18T00:47:18.272+0000 7ff91081b640 -1 mon.b@0(probing) e0 get_health_metrics reporting 2246 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T21:39:48.991759+0000)
debug 2025-04-18T00:47:18.756+0000 7ff9141df640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:47:18.756+0000 7ff9141df640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:47:23.276+0000 7ff91081b640 -1 mon.b@0(probing) e0 get_health_metrics reporting 2248 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T21:39:48.991759+0000)
debug 2025-04-18T00:47:28.272+0000 7ff91081b640 -1 mon.b@0(probing) e0 get_health_metrics reporting 2248 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T21:39:48.991759+0000)
debug 2025-04-18T00:47:28.720+0000 7ff9141df640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:47:28.724+0000 7ff9141df640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:47:33.272+0000 7ff91081b640 -1 mon.b@0(probing) e0 get_health_metrics reporting 2250 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T21:39:48.991759+0000)
debug 2025-04-18T00:47:38.276+0000 7ff91081b640 -1 mon.b@0(probing) e0 get_health_metrics reporting 2250 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T21:39:48.991759+0000)
debug 2025-04-18T00:47:38.720+0000 7ff9141df640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:47:38.720+0000 7ff9141df640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:47:43.276+0000 7ff91081b640 -1 mon.b@0(probing) e0 get_health_metrics reporting 2252 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T21:39:48.991759+0000)
debug 2025-04-18T00:47:48.276+0000 7ff91081b640 -1 mon.b@0(probing) e0 get_health_metrics reporting 2252 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T21:39:48.991759+0000)
debug 2025-04-18T00:47:48.744+0000 7ff9141df640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:47:48.744+0000 7ff9141df640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:47:53.276+0000 7ff91081b640 -1 mon.b@0(probing) e0 get_health_metrics reporting 2254 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T21:39:48.991759+0000)
debug 2025-04-18T00:47:58.276+0000 7ff91081b640 -1 mon.b@0(probing) e0 get_health_metrics reporting 2254 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T21:39:48.991759+0000)
debug 2025-04-18T00:47:58.724+0000 7ff9141df640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:47:58.724+0000 7ff9141df640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:48:03.280+0000 7ff91081b640 -1 mon.b@0(probing) e0 get_health_metrics reporting 2256 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T21:39:48.991759+0000)
debug 2025-04-18T00:48:08.276+0000 7ff91081b640 -1 mon.b@0(probing) e0 get_health_metrics reporting 2256 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T21:39:48.991759+0000)
debug 2025-04-18T00:48:08.724+0000 7ff9141df640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:48:08.724+0000 7ff9141df640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:48:13.276+0000 7ff91081b640 -1 mon.b@0(probing) e0 get_health_metrics reporting 2258 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T21:39:48.991759+0000)
debug 2025-04-18T00:48:18.276+0000 7ff91081b640 -1 mon.b@0(probing) e0 get_health_metrics reporting 2258 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T21:39:48.991759+0000)
debug 2025-04-18T00:48:18.728+0000 7ff9141df640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:48:18.728+0000 7ff9141df640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:48:23.275+0000 7ff91081b640 -1 mon.b@0(probing) e0 get_health_metrics reporting 2260 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T21:39:48.991759+0000)
debug 2025-04-18T00:48:28.275+0000 7ff91081b640 -1 mon.b@0(probing) e0 get_health_metrics reporting 2260 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T21:39:48.991759+0000)
debug 2025-04-18T00:48:28.723+0000 7ff9141df640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:48:28.723+0000 7ff9141df640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:48:33.279+0000 7ff91081b640 -1 mon.b@0(probing) e0 get_health_metrics reporting 2262 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T21:39:48.991759+0000)
debug 2025-04-18T00:48:38.279+0000 7ff91081b640 -1 mon.b@0(probing) e0 get_health_metrics reporting 2262 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T21:39:48.991759+0000)
debug 2025-04-18T00:48:38.727+0000 7ff9141df640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:48:38.727+0000 7ff9141df640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:48:43.279+0000 7ff91081b640 -1 mon.b@0(probing) e0 get_health_metrics reporting 2264 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T21:39:48.991759+0000)
debug 2025-04-18T00:48:48.279+0000 7ff91081b640 -1 mon.b@0(probing) e0 get_health_metrics reporting 2264 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T21:39:48.991759+0000)
debug 2025-04-18T00:48:48.731+0000 7ff9141df640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:48:48.731+0000 7ff9141df640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:48:53.279+0000 7ff91081b640 -1 mon.b@0(probing) e0 get_health_metrics reporting 2266 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T21:39:48.991759+0000)
debug 2025-04-18T00:48:58.279+0000 7ff91081b640 -1 mon.b@0(probing) e0 get_health_metrics reporting 2266 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T21:39:48.991759+0000)
debug 2025-04-18T00:48:58.719+0000 7ff9141df640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:48:58.719+0000 7ff9141df640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:49:03.279+0000 7ff91081b640 -1 mon.b@0(probing) e0 get_health_metrics reporting 2268 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T21:39:48.991759+0000)
debug 2025-04-18T00:49:08.279+0000 7ff91081b640 -1 mon.b@0(probing) e0 get_health_metrics reporting 2268 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T21:39:48.991759+0000)
debug 2025-04-18T00:49:08.719+0000 7ff9141df640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:49:08.723+0000 7ff9141df640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:49:13.279+0000 7ff91081b640 -1 mon.b@0(probing) e0 get_health_metrics reporting 2270 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T21:39:48.991759+0000)
debug 2025-04-18T00:49:18.283+0000 7ff91081b640 -1 mon.b@0(probing) e0 get_health_metrics reporting 2270 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T21:39:48.991759+0000)
debug 2025-04-18T00:49:18.755+0000 7ff9141df640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:49:18.755+0000 7ff9141df640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:49:23.279+0000 7ff91081b640 -1 mon.b@0(probing) e0 get_health_metrics reporting 2272 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T21:39:48.991759+0000)
debug 2025-04-18T00:49:28.279+0000 7ff91081b640 -1 mon.b@0(probing) e0 get_health_metrics reporting 2272 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T21:39:48.991759+0000)
debug 2025-04-18T00:49:28.719+0000 7ff9141df640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:49:28.719+0000 7ff9141df640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:49:33.283+0000 7ff91081b640 -1 mon.b@0(probing) e0 get_health_metrics reporting 2274 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T21:39:48.991759+0000)
debug 2025-04-18T00:49:37.559+0000 7ff90b010640  4 rocksdb: [db/db_impl/db_impl.cc:1109] ------- DUMPING STATS -------
debug 2025-04-18T00:49:37.559+0000 7ff90b010640  4 rocksdb: [db/db_impl/db_impl.cc:1111]
** DB Stats **
Uptime(secs): 11400.1 total, 600.0 interval
Cumulative writes: 0 writes, 0 keys, 0 commit groups, 0.0 writes per commit group, ingest: 0.00 GB, 0.00 MB/s
Cumulative WAL: 0 writes, 0 syncs, 0.00 writes per sync, written: 0.00 GB, 0.00 MB/s
Cumulative stall: 00:00:0.000 H:M:S, 0.0 percent
Interval writes: 0 writes, 0 keys, 0 commit groups, 0.0 writes per commit group, ingest: 0.00 MB, 0.00 MB/s
Interval WAL: 0 writes, 0 syncs, 0.00 writes per sync, written: 0.00 GB, 0.00 MB/s
Interval stall: 00:00:0.000 H:M:S, 0.0 percent

debug 2025-04-18T00:49:38.283+0000 7ff91081b640 -1 mon.b@0(probing) e0 get_health_metrics reporting 2274 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T21:39:48.991759+0000)
debug 2025-04-18T00:49:38.719+0000 7ff9141df640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:49:38.719+0000 7ff9141df640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
citec@k1:~/osh$ kubectl -n rook-ceph logs rook-ceph-mon-c-648dbbff5c-b8vth | tail -n 100
Defaulted container "mon" out of: mon, chown-container-data-dir (init), init-mon-fs (init)
debug 2025-04-18T00:45:42.480+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:45:42.480+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:45:43.080+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12172 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:45:48.080+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12172 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:45:52.472+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:45:52.472+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:45:53.084+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12174 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:45:58.084+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12174 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:46:02.452+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:46:02.452+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:46:03.084+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12176 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:46:08.088+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12176 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:46:12.456+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:46:12.460+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:46:13.088+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12178 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:46:18.088+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12178 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:46:22.448+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:46:22.448+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:46:23.092+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12180 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:46:28.092+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12180 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:46:32.452+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:46:32.452+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:46:33.092+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12182 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:46:38.096+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12182 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:46:42.456+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:46:42.456+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:46:43.096+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12184 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:46:48.096+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12184 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:46:52.440+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:46:52.440+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:46:53.096+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12186 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:46:58.100+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12186 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:47:02.452+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:47:02.452+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:47:03.100+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12188 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:47:08.100+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12188 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:47:12.464+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:47:12.464+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:47:13.104+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12190 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:47:18.104+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12190 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:47:22.456+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:47:22.460+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:47:23.104+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12192 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:47:28.108+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12192 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:47:32.452+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:47:32.452+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:47:33.108+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12194 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:47:38.108+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12194 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:47:42.452+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:47:42.452+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:47:43.108+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12196 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:47:48.112+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12196 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:47:52.452+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:47:52.452+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:47:53.112+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12198 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:47:58.112+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12198 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:48:02.444+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:48:02.444+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:48:03.116+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12200 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:48:08.116+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12200 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:48:12.464+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:48:12.464+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:48:13.116+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12202 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:48:18.120+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12202 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:48:22.464+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:48:22.464+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:48:23.120+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12204 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:48:28.120+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12204 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:48:32.452+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:48:32.452+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:48:33.120+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12206 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:48:38.124+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12206 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:48:42.460+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:48:42.460+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:48:43.124+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12208 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:48:48.124+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12208 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:48:52.488+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:48:52.488+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:48:53.128+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12210 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:48:58.128+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12210 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:49:02.476+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:49:02.476+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:49:03.128+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12212 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:49:08.132+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12212 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:49:12.452+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:49:12.452+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:49:13.132+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12214 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:49:18.132+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12214 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:49:22.444+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:49:22.444+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:49:23.132+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12216 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:49:28.136+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12216 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:49:32.448+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:49:32.452+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:49:33.136+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12218 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:49:38.136+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12218 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:49:42.476+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd='mon_status' args=[]: dispatch
debug 2025-04-18T00:49:42.480+0000 7f6b5f04d640  0 log_channel(audit) log [DBG] : from='admin socket' entity='admin socket' cmd=mon_status args=[]: finished
debug 2025-04-18T00:49:43.140+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12220 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)
debug 2025-04-18T00:49:48.140+0000 7f6b5b689640 -1 mon.c@1(probing) e2 get_health_metrics reporting 12220 slow ops, oldest is log(1 entries from seq 1 at 2025-04-17T07:51:12.458016+0000)

citec@k1:~/osh$ kubectl -n rook-ceph exec -it rook-ceph-mon-a-6b84b89d56-jv6hm -- ceph --admin-daemon /run/ceph/ceph-mon.a.asok mon_status
Defaulted container "mon" out of: mon, chown-container-data-dir (init), init-mon-fs (init)
{
    "name": "a",
    "rank": 0,
    "state": "probing",
    "election_epoch": 0,
    "quorum": [],
    "features": {
        "required_con": "2449958758054445060",
        "required_mon": [
            "kraken",
            "luminous",
            "mimic",
            "osdmap-prune",
            "nautilus",
            "octopus",
            "pacific",
            "elector-pinging",
            "quincy",
            "reef"
        ],
        "quorum_con": "0",
        "quorum_mon": []
    },
    "outside_quorum": [
        "a"
    ],
    "extra_probe_peers": [],
    "sync_provider": [],
    "monmap": {
        "epoch": 2,
        "fsid": "f1ed7497-46ae-4186-b2c6-46aac10df99c",
        "modified": "2025-04-17T05:48:43.602051Z",
        "created": "2025-04-17T05:42:54.074126Z",
        "min_mon_release": 18,
        "min_mon_release_name": "reef",
        "election_strategy": 1,
        "disallowed_leaders: ": "",
        "stretch_mode": false,
        "tiebreaker_mon": "",
        "removed_ranks: ": "",
        "features": {
            "persistent": [
                "kraken",
                "luminous",
                "mimic",
                "osdmap-prune",
                "nautilus",
                "octopus",
                "pacific",
                "elector-pinging",
                "quincy",
                "reef"
            ],
            "optional": []
        },
        "mons": [
            {
                "rank": 0,
                "name": "a",
                "public_addrs": {
                    "addrvec": [
                        {
                            "type": "v2",
                            "addr": "10.96.30.54:3300",
                            "nonce": 0
                        },
                        {
                            "type": "v1",
                            "addr": "10.96.30.54:6789",
                            "nonce": 0
                        }
                    ]
                },
                "addr": "10.96.30.54:6789/0",
                "public_addr": "10.96.30.54:6789/0",
                "priority": 0,
                "weight": 0,
                "crush_location": "{}"
            },
            {
                "rank": 1,
                "name": "c",
                "public_addrs": {
                    "addrvec": [
                        {
                            "type": "v2",
                            "addr": "10.96.91.166:3300",
                            "nonce": 0
                        },
                        {
                            "type": "v1",
                            "addr": "10.96.91.166:6789",
                            "nonce": 0
                        }
                    ]
                },
                "addr": "10.96.91.166:6789/0",
                "public_addr": "10.96.91.166:6789/0",
                "priority": 0,
                "weight": 0,
                "crush_location": "{}"
            }
        ]
    },
    "feature_map": {
        "mon": [
            {
                "features": "0x3f01cfbffffdffff",
                "release": "reef",
                "num": 1
            }
        ]
    },
    "stretch_mode": false
}
citec@k1:~/osh$ kubectl -n rook-ceph exec -it rook-ceph-mon-b-66789dfd6-c9pct -- ceph --admin-daemon /run/ceph/ceph-mon.b.asok mon_status
Defaulted container "mon" out of: mon, chown-container-data-dir (init), init-mon-fs (init)
{
    "name": "b",
    "rank": 0,
    "state": "probing",
    "election_epoch": 0,
    "quorum": [],
    "features": {
        "required_con": "0",
        "required_mon": [],
        "quorum_con": "0",
        "quorum_mon": []
    },
    "outside_quorum": [
        "b"
    ],
    "extra_probe_peers": [
        {
            "addrvec": [
                {
                    "type": "v2",
                    "addr": "10.96.116.238:3300",
                    "nonce": 0
                },
                {
                    "type": "v1",
                    "addr": "10.96.116.238:6789",
                    "nonce": 0
                }
            ]
        }
    ],
    "sync_provider": [],
    "monmap": {
        "epoch": 0,
        "fsid": "f1ddd33d-5812-4dcd-b83e-58a66a2dd8cf",
        "modified": "2025-04-17T05:22:33.254748Z",
        "created": "2025-04-17T05:22:33.254748Z",
        "min_mon_release": 0,
        "min_mon_release_name": "unknown",
        "election_strategy": 1,
        "disallowed_leaders: ": "",
        "stretch_mode": false,
        "tiebreaker_mon": "",
        "removed_ranks: ": "0",
        "features": {
            "persistent": [],
            "optional": []
        },
        "mons": [
            {
                "rank": 0,
                "name": "b",
                "public_addrs": {
                    "addrvec": [
                        {
                            "type": "v2",
                            "addr": "10.96.178.123:3300",
                            "nonce": 0
                        },
                        {
                            "type": "v1",
                            "addr": "10.96.178.123:6789",
                            "nonce": 0
                        }
                    ]
                },
                "addr": "10.96.178.123:6789/0",
                "public_addr": "10.96.178.123:6789/0",
                "priority": 0,
                "weight": 0,
                "crush_location": "{}"
            },
            {
                "rank": 1,
                "name": "a",
                "public_addrs": {
                    "addrvec": [
                        {
                            "type": "v1",
                            "addr": "0.0.0.0:0",
                            "nonce": 1
                        }
                    ]
                },
                "addr": "0.0.0.0:0/1",
                "public_addr": "0.0.0.0:0/1",
                "priority": 0,
                "weight": 0,
                "crush_location": "{}"
            },
            {
                "rank": 2,
                "name": "c",
                "public_addrs": {
                    "addrvec": [
                        {
                            "type": "v1",
                            "addr": "0.0.0.0:0",
                            "nonce": 2
                        }
                    ]
                },
                "addr": "0.0.0.0:0/2",
                "public_addr": "0.0.0.0:0/2",
                "priority": 0,
                "weight": 0,
                "crush_location": "{}"
            }
        ]
    },
    "feature_map": {
        "mon": [
            {
                "features": "0x3f01cfbffffdffff",
                "release": "reef",
                "num": 1
            }
        ]
    },
    "stretch_mode": false
}
citec@k1:~/osh$ kubectl -n rook-ceph exec -it rook-ceph-mon-c-648dbbff5c-b8vth -- ceph --admin-daemon /run/ceph/ceph-mon.c.asok mon_status
Defaulted container "mon" out of: mon, chown-container-data-dir (init), init-mon-fs (init)
{
    "name": "c",
    "rank": 1,
    "state": "probing",
    "election_epoch": 0,
    "quorum": [],
    "features": {
        "required_con": "2449958758054445060",
        "required_mon": [
            "kraken",
            "luminous",
            "mimic",
            "osdmap-prune",
            "nautilus",
            "octopus",
            "pacific",
            "elector-pinging",
            "quincy",
            "reef"
        ],
        "quorum_con": "0",
        "quorum_mon": []
    },
    "outside_quorum": [
        "c"
    ],
    "extra_probe_peers": [],
    "sync_provider": [],
    "monmap": {
        "epoch": 2,
        "fsid": "f1ed7497-46ae-4186-b2c6-46aac10df99c",
        "modified": "2025-04-17T05:48:43.602051Z",
        "created": "2025-04-17T05:42:54.074126Z",
        "min_mon_release": 18,
        "min_mon_release_name": "reef",
        "election_strategy": 1,
        "disallowed_leaders: ": "",
        "stretch_mode": false,
        "tiebreaker_mon": "",
        "removed_ranks: ": "",
        "features": {
            "persistent": [
                "kraken",
                "luminous",
                "mimic",
                "osdmap-prune",
                "nautilus",
                "octopus",
                "pacific",
                "elector-pinging",
                "quincy",
                "reef"
            ],
            "optional": []
        },
        "mons": [
            {
                "rank": 0,
                "name": "a",
                "public_addrs": {
                    "addrvec": [
                        {
                            "type": "v2",
                            "addr": "10.96.30.54:3300",
                            "nonce": 0
                        },
                        {
                            "type": "v1",
                            "addr": "10.96.30.54:6789",
                            "nonce": 0
                        }
                    ]
                },
                "addr": "10.96.30.54:6789/0",
                "public_addr": "10.96.30.54:6789/0",
                "priority": 0,
                "weight": 0,
                "crush_location": "{}"
            },
            {
                "rank": 1,
                "name": "c",
                "public_addrs": {
                    "addrvec": [
                        {
                            "type": "v2",
                            "addr": "10.96.91.166:3300",
                            "nonce": 0
                        },
                        {
                            "type": "v1",
                            "addr": "10.96.91.166:6789",
                            "nonce": 0
                        }
                    ]
                },
                "addr": "10.96.91.166:6789/0",
                "public_addr": "10.96.91.166:6789/0",
                "priority": 0,
                "weight": 0,
                "crush_location": "{}"
            }
        ]
    },
    "feature_map": {
        "mon": [
            {
                "features": "0x3f01cfbffffdffff",
                "release": "reef",
                "num": 1
            }
        ]
    },
    "stretch_mode": false
}

citec@k1:~/osh$ kubectl -n rook-ceph get endpoints
NAME              ENDPOINTS                                 AGE
rook-ceph-mon-a   10.244.105.140:6789,10.244.105.140:3300   17h
rook-ceph-mon-b   10.244.195.149:6789,10.244.195.149:3300   17h
rook-ceph-mon-c   10.244.99.18:6789,10.244.99.18:3300       17h
citec@k1:~/osh$ kubectl -n rook-ceph get networkpolicies
No resources found in rook-ceph namespace.

citec@k1:~/osh$ ssh k1 date
Fri Apr 18 09:34:25 AM KST 2025
citec@k1:~/osh$ ssh k2 date
Fri Apr 18 09:34:29 AM KST 2025
citec@k1:~/osh$ ssh k3 date
Fri Apr 18 09:34:34 AM KST 2025
citec@k1:~/osh$ ssh k4 date
Fri Apr 18 09:34:37 AM KST 2025

citec@k1:~/osh$ sudo ufw status
Status: inactive
citec@k1:~/osh$ sudo iptables -L -v -n
Chain INPUT (policy ACCEPT 22M packets, 6534M bytes)
 pkts bytes target     prot opt in     out     source               destination
  22M 6578M cali-INPUT  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:Cz_u1IQiXIMmKD4c */
  22M 6461M KUBE-IPVS-FILTER  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* kubernetes ipvs access filter */
  22M 6461M KUBE-PROXY-FIREWALL  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* kube-proxy firewall rules */
  22M 6461M KUBE-NODE-PORT  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* kubernetes health check rules */
  22M 6468M KUBE-FIREWALL  all  --  *      *       0.0.0.0/0            0.0.0.0/0

Chain FORWARD (policy ACCEPT 0 packets, 0 bytes)
 pkts bytes target     prot opt in     out     source               destination
 808K  102M cali-FORWARD  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:wUHhoiAYhphO9Mso */
55483 3338K KUBE-PROXY-FIREWALL  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* kube-proxy firewall rules */
55483 3338K KUBE-FORWARD  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* kubernetes forwarding rules */
55483 3338K DOCKER-USER  all  --  *      *       0.0.0.0/0            0.0.0.0/0
55483 3338K DOCKER-FORWARD  all  --  *      *       0.0.0.0/0            0.0.0.0/0
55483 3338K ACCEPT     all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:S93hcgKJrXEqnTfs */ /* Policy explicitly accepted packet. */
    0     0 MARK       all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:mp77cMpurHhyjLrM */ MARK or 0x10000

Chain OUTPUT (policy ACCEPT 21M packets, 6203M bytes)
 pkts bytes target     prot opt in     out     source               destination
  22M 6210M cali-OUTPUT  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:tVnHkvAo15HuiPy0 */
  21M 6173M KUBE-IPVS-OUT-FILTER  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* kubernetes ipvs access filter */
  21M 6180M KUBE-FIREWALL  all  --  *      *       0.0.0.0/0            0.0.0.0/0

Chain DOCKER (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 DROP       all  --  !docker0 docker0  0.0.0.0/0            0.0.0.0/0

Chain DOCKER-BRIDGE (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 DOCKER     all  --  *      docker0  0.0.0.0/0            0.0.0.0/0

Chain DOCKER-CT (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 ACCEPT     all  --  *      docker0  0.0.0.0/0            0.0.0.0/0            ctstate RELATED,ESTABLISHED

Chain DOCKER-FORWARD (1 references)
 pkts bytes target     prot opt in     out     source               destination
55483 3338K DOCKER-CT  all  --  *      *       0.0.0.0/0            0.0.0.0/0
55483 3338K DOCKER-ISOLATION-STAGE-1  all  --  *      *       0.0.0.0/0            0.0.0.0/0
55483 3338K DOCKER-BRIDGE  all  --  *      *       0.0.0.0/0            0.0.0.0/0
    0     0 ACCEPT     all  --  docker0 *       0.0.0.0/0            0.0.0.0/0

Chain DOCKER-ISOLATION-STAGE-1 (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 DOCKER-ISOLATION-STAGE-2  all  --  docker0 !docker0  0.0.0.0/0            0.0.0.0/0

Chain DOCKER-ISOLATION-STAGE-2 (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 DROP       all  --  *      docker0  0.0.0.0/0            0.0.0.0/0

Chain DOCKER-USER (1 references)
 pkts bytes target     prot opt in     out     source               destination
55483 3338K RETURN     all  --  *      *       0.0.0.0/0            0.0.0.0/0

Chain KUBE-FIREWALL (2 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 DROP       all  --  *      *      !127.0.0.0/8          127.0.0.0/8          /* block incoming localnet connections */ ! ctstate RELATED,ESTABLISHED,DNAT

Chain KUBE-FORWARD (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 ACCEPT     all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* kubernetes forwarding rules */
    0     0 ACCEPT     all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* kubernetes forwarding conntrack rule */ ctstate RELATED,ESTABLISHED

Chain KUBE-IPVS-FILTER (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 RETURN     all  --  *      *       0.0.0.0/0            0.0.0.0/0            match-set KUBE-LOAD-BALANCER dst,dst
    0     0 RETURN     all  --  *      *       0.0.0.0/0            0.0.0.0/0            match-set KUBE-CLUSTER-IP dst,dst
    0     0 RETURN     all  --  *      *       0.0.0.0/0            0.0.0.0/0            match-set KUBE-EXTERNAL-IP dst,dst
    0     0 RETURN     all  --  *      *       0.0.0.0/0            0.0.0.0/0            match-set KUBE-EXTERNAL-IP-LOCAL dst,dst
    0     0 RETURN     all  --  *      *       0.0.0.0/0            0.0.0.0/0            match-set KUBE-HEALTH-CHECK-NODE-PORT dst
    0     0 REJECT     all  --  *      *       0.0.0.0/0            0.0.0.0/0            ctstate NEW match-set KUBE-IPVS-IPS dst reject-with icmp-port-unreachable

Chain KUBE-IPVS-OUT-FILTER (1 references)
 pkts bytes target     prot opt in     out     source               destination

Chain KUBE-KUBELET-CANARY (0 references)
 pkts bytes target     prot opt in     out     source               destination

Chain KUBE-NODE-PORT (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 ACCEPT     all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* Kubernetes health check node port */ match-set KUBE-HEALTH-CHECK-NODE-PORT dst

Chain KUBE-PROXY-FIREWALL (2 references)
 pkts bytes target     prot opt in     out     source               destination

Chain KUBE-SOURCE-RANGES-FIREWALL (0 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 DROP       all  --  *      *       0.0.0.0/0            0.0.0.0/0

Chain cali-FORWARD (1 references)
 pkts bytes target     prot opt in     out     source               destination
 808K  102M MARK       all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:vjrMJCRpqwy5oRoX */ MARK and 0xfff1ffff
 808K  102M cali-from-hep-forward  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:A_sPAO0mcxbT9mOV */
 407K   62M cali-from-wl-dispatch  all  --  cali+  *       0.0.0.0/0            0.0.0.0/0            /* cali:8ZoYfO5HKXWbB3pk */
 401K   39M cali-to-wl-dispatch  all  --  *      cali+   0.0.0.0/0            0.0.0.0/0            /* cali:jdEuaPBe14V2hutn */
55483 3338K cali-to-hep-forward  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:12bc6HljsMKsmfr- */
55483 3338K cali-cidr-block  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:NOSxoaGx8OIstr1z */

Chain cali-INPUT (1 references)
 pkts bytes target     prot opt in     out     source               destination
 411K   48M ACCEPT     4    --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:PajejrV4aFdkZojI */ /* Allow IPIP packets from Calico hosts */ match-set cali40all-hosts-net src ADDRTYPE match dst-type LOCAL
    0     0 DROP       4    --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:_wjq-Yrma8Ly1Svo */ /* Drop IPIP packets from non-Calico hosts */
  22M 6530M MARK       all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:ss8lEMQsXi-s6qYT */ MARK and 0xfffff
  22M 6530M cali-forward-check  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:PgIW-V0nEjwPhF_8 */
 7930 1398K RETURN     all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:QMJlDwlS0OjHyfMN */
 219K  107M cali-wl-to-host  all  --  cali+  *       0.0.0.0/0            0.0.0.0/0           [goto]  /* cali:nDRe73txrna-aZjG */
    0     0 ACCEPT     all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:iX2AYvqGXaVqwkro */
  22M 6422M MARK       all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:bhpnxD5IRtBP8KW0 */ MARK and 0xfff0ffff
  22M 6422M cali-from-host-endpoint  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:H5_bccAbHV0sooVy */
    0     0 ACCEPT     all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:inBL01YlfurT0dbI */ /* Host endpoint policy accepted packet. */

Chain cali-OUTPUT (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 ACCEPT     all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:Mq1_rAdXXH3YkrzW */
  126  7560 cali-forward-endpoint-mark  all  --  *      *       0.0.0.0/0            0.0.0.0/0           [goto]  /* cali:5Z67OUUpTOM7Xa1a */
 227K  118M RETURN     all  --  *      cali+   0.0.0.0/0            0.0.0.0/0            /* cali:M2Wf0OehNdig8MHR */
 385K   62M ACCEPT     4    --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:AJBkLho_0Qd8LNr3 */ /* Allow IPIP packets to other Calico hosts */ match-set cali40all-hosts-net dst ADDRTYPE match src-type LOCAL
  21M 6030M MARK       all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:iz2RWXlXJDUfsLpe */ MARK and 0xfff0ffff
  21M 6030M cali-to-host-endpoint  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:xQqLi8S0sxbiyvjR */ ! ctstate DNAT
    0     0 ACCEPT     all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:aSnsxZdmhxm_ilRZ */ /* Host endpoint policy accepted packet. */

Chain cali-cidr-block (1 references)
 pkts bytes target     prot opt in     out     source               destination

Chain cali-forward-check (1 references)
 pkts bytes target     prot opt in     out     source               destination
  22M 6517M RETURN     all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:Pbldlb4FaULvpdD8 */ ctstate RELATED,ESTABLISHED
    0     0 cali-set-endpoint-mark  tcp  --  *      *       0.0.0.0/0            0.0.0.0/0           [goto]  /* cali:ZD-6UxuUtGW-xtzg */ /* To kubernetes NodePort service */ multiport dports 30000:32767 match-set cali40this-host dst
    0     0 cali-set-endpoint-mark  udp  --  *      *       0.0.0.0/0            0.0.0.0/0           [goto]  /* cali:CbPfUajQ2bFVnDq4 */ /* To kubernetes NodePort service */ multiport dports 30000:32767 match-set cali40this-host dst
 7930 1398K cali-set-endpoint-mark  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:jmhU0ODogX-Zfe5g */ /* To kubernetes service */ ! match-set cali40this-host dst

Chain cali-forward-endpoint-mark (1 references)
 pkts bytes target     prot opt in     out     source               destination
  126  7560 cali-from-endpoint-mark  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:O0SmFDrnm7KggWqW */
   40  2400 cali-to-wl-dispatch  all  --  *      cali+   0.0.0.0/0            0.0.0.0/0            /* cali:aFl0WFKRxDqj8oA6 */
  126  7560 cali-to-hep-forward  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:AZKVrO3i_8cLai5f */
  126  7560 MARK       all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:96HaP1sFtb-NYoYA */ MARK and 0xfffff
  126  7560 ACCEPT     all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:VxO6hyNWz62YEtul */ /* Policy explicitly accepted packet. */

Chain cali-from-endpoint-mark (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 cali-fw-calia8d64e13668  all  --  *      *       0.0.0.0/0            0.0.0.0/0           [goto]  /* cali:oLX8wYZ0PWCkhAzr */
    0     0 cali-fw-calic7055d6afa6  all  --  *      *       0.0.0.0/0            0.0.0.0/0           [goto]  /* cali:Zo9wIlkbPY0_opkm */
    0     0 cali-fw-calif1aa1cfa43e  all  --  *      *       0.0.0.0/0            0.0.0.0/0           [goto]  /* cali:DP0GPyDESPoh966E */
    0     0 DROP       all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:zXUNgE9qQNBa1VSp */ /* Unknown interface */

Chain cali-from-hep-forward (1 references)
 pkts bytes target     prot opt in     out     source               destination

Chain cali-from-host-endpoint (1 references)
 pkts bytes target     prot opt in     out     source               destination

Chain cali-from-wl-dispatch (2 references)
 pkts bytes target     prot opt in     out     source               destination
 323K   22M cali-fw-calia8d64e13668  all  --  calia8d64e13668 *       0.0.0.0/0            0.0.0.0/0           [goto]  /* cali:yjl7dxGMpQsk3Q2b */
86748 7218K cali-fw-calic7055d6afa6  all  --  calic7055d6afa6 *       0.0.0.0/0            0.0.0.0/0           [goto]  /* cali:SLl2_6jlBw0oWL1W */
86467 7213K cali-fw-calif1aa1cfa43e  all  --  calif1aa1cfa43e *       0.0.0.0/0            0.0.0.0/0           [goto]  /* cali:gT0QXIXuciG1RjJs */
    0     0 DROP       all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:CyOGqg9H-7WeFHQi */ /* Unknown interface */

Chain cali-fw-calia8d64e13668 (2 references)
 pkts bytes target     prot opt in     out     source               destination
 312K   21M ACCEPT     all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:VN3AwtIlBGBDRnYl */ ctstate RELATED,ESTABLISHED
    0     0 DROP       all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:Q5MoNvwIsbEuL9x9 */ ctstate INVALID
10204  612K MARK       all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:0IiJepMa_EThZOb6 */ MARK and 0xfffeffff
    0     0 DROP       udp  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:Q42egSv_XCkxFLby */ /* Drop VXLAN encapped packets originating in workloads */ multiport dports 4789
    0     0 DROP       4    --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:7n9eWTxuJJzgYghx */ /* Drop IPinIP encapped packets originating in workloads */
10204  612K cali-pro-kns.rook-ceph  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:g4Pj4fsVuMVwYe73 */
10204  612K RETURN     all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:ncjGMueMVZsXD9BZ */ /* Return if profile accepted */
    0     0 cali-pro-_Tn6vS0_Qg9MjrpTirl  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:gFMngPhRL3yNYvDv */
    0     0 RETURN     all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:juZ83QNOsz2DzR9A */ /* Return if profile accepted */
    0     0 DROP       all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:wbEbHCNkS9k5m9MP */ /* Drop if no profiles matched */

Chain cali-fw-calic7055d6afa6 (2 references)
 pkts bytes target     prot opt in     out     source               destination
98498 8200K ACCEPT     all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:rtoPGUx6yrLC3lmU */ ctstate RELATED,ESTABLISHED
    0     0 DROP       all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:_49L-nesoCl5gIyc */ ctstate INVALID
    0     0 MARK       all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:njzCk_cJikREokWo */ MARK and 0xfffeffff
    0     0 DROP       udp  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:xxFx-UU6pfBVNfnF */ /* Drop VXLAN encapped packets originating in workloads */ multiport dports 4789
    0     0 DROP       4    --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:_3P8bVBRWgUmkjzF */ /* Drop IPinIP encapped packets originating in workloads */
    0     0 cali-pro-kns.ceph  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:gi9nM8t4UAE4_SMo */
    0     0 RETURN     all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:6ECQtmnwQO5hkmG0 */ /* Return if profile accepted */
    0     0 cali-pro-_3CoffGHfcoYGrfpgcn  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:lN-nO-mtUJmUdA-g */
    0     0 RETURN     all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:Z0x6ZHbhiswBl9wf */ /* Return if profile accepted */
    0     0 DROP       all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:TUU2efm0u5rTE2Kz */ /* Drop if no profiles matched */

Chain cali-fw-calif1aa1cfa43e (2 references)
 pkts bytes target     prot opt in     out     source               destination
98183 8193K ACCEPT     all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:btWqy_9u9i5thd-z */ ctstate RELATED,ESTABLISHED
    0     0 DROP       all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:Cdt0Jd3SD3Ofr-Ut */ ctstate INVALID
    0     0 MARK       all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:EiyYekN0lC5HcFSS */ MARK and 0xfffeffff
    0     0 DROP       udp  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:e-RM9DZs4RxtYAMN */ /* Drop VXLAN encapped packets originating in workloads */ multiport dports 4789
    0     0 DROP       4    --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:k6ldjREUsDKEZtUh */ /* Drop IPinIP encapped packets originating in workloads */
    0     0 cali-pro-kns.openstack  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:UZjtJrxvgqvVmb5L */
    0     0 RETURN     all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:gbC_5hH7pMQooFiV */ /* Return if profile accepted */
    0     0 cali-pro-_yxO6sDNctlXrebydlU  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:nm7_7v9sfgwKrlGM */
    0     0 RETURN     all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:D3SQ8bn6prVN1fRX */ /* Return if profile accepted */
    0     0 DROP       all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:ySpn9g8D6dym5eKE */ /* Drop if no profiles matched */

Chain cali-pri-_3CoffGHfcoYGrfpgcn (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0            all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:FuUiFtoZDHkQw74y */ /* Profile ksa.ceph.ingress-nginx-ceph ingress */

Chain cali-pri-_Tn6vS0_Qg9MjrpTirl (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0            all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:mBlFmN_-JMFJoPXJ */ /* Profile ksa.rook-ceph.rook-ceph-default ingress */

Chain cali-pri-_yxO6sDNctlXrebydlU (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0            all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:lR8AkpdoWipBnWob */ /* Profile ksa.openstack.ingress-nginx-openstack ingress */

Chain cali-pri-kns.ceph (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 MARK       all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:3qoQ8nO5naQekJMZ */ /* Profile kns.ceph ingress */ MARK or 0x10000
    0     0 RETURN     all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:B4M38_O1qLHTNeoC */

Chain cali-pri-kns.openstack (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 MARK       all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:9afgozaT_wxBeYsU */ /* Profile kns.openstack ingress */ MARK or 0x10000
    0     0 RETURN     all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:OmsBB3iEvCLIitZA */

Chain cali-pri-kns.rook-ceph (1 references)
 pkts bytes target     prot opt in     out     source               destination
44710 2683K MARK       all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:jKu-8jTk1mPb-9jb */ /* Profile kns.rook-ceph ingress */ MARK or 0x10000
44710 2683K RETURN     all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:bTsufM6abD4gGHeh */

Chain cali-pro-_3CoffGHfcoYGrfpgcn (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0            all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:0HGz_yy9AZadvU5S */ /* Profile ksa.ceph.ingress-nginx-ceph egress */

Chain cali-pro-_Tn6vS0_Qg9MjrpTirl (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0            all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:rm7zWAmNKjTJEnQB */ /* Profile ksa.rook-ceph.rook-ceph-default egress */

Chain cali-pro-_yxO6sDNctlXrebydlU (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0            all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:YQ9rafwUKxhtoqut */ /* Profile ksa.openstack.ingress-nginx-openstack egress */

Chain cali-pro-kns.ceph (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 MARK       all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:42ii3EwOqm05djr7 */ /* Profile kns.ceph egress */ MARK or 0x10000
    0     0 RETURN     all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:CMP1wnbCPhNaRcY6 */

Chain cali-pro-kns.openstack (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 MARK       all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:0dzIhyErBUCzkXPh */ /* Profile kns.openstack egress */ MARK or 0x10000
    0     0 RETURN     all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:BIufASQlmkp_h73a */

Chain cali-pro-kns.rook-ceph (1 references)
 pkts bytes target     prot opt in     out     source               destination
10204  612K MARK       all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:FyniI_4RzK76T7QM */ /* Profile kns.rook-ceph egress */ MARK or 0x10000
10204  612K RETURN     all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:nbVX0BlPTLKM4b_r */

Chain cali-set-endpoint-mark (3 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 cali-sm-calia8d64e13668  all  --  calia8d64e13668 *       0.0.0.0/0            0.0.0.0/0           [goto]  /* cali:6WduDm6-iehusq2z */
    0     0 cali-sm-calic7055d6afa6  all  --  calic7055d6afa6 *       0.0.0.0/0            0.0.0.0/0           [goto]  /* cali:q-p9lKfXkqfUlmeO */
    0     0 cali-sm-calif1aa1cfa43e  all  --  calif1aa1cfa43e *       0.0.0.0/0            0.0.0.0/0           [goto]  /* cali:-GcdmBj42GKIH2M0 */
    0     0 DROP       all  --  cali+  *       0.0.0.0/0            0.0.0.0/0            /* cali:9i-KrRyBz0xVQQRP */ /* Unknown endpoint */
 6017 1074K MARK       all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:clPZwcGBh9xM6S7r */ /* Non-Cali endpoint mark */ MARK xset 0x100000/0xfff00000

Chain cali-sm-calia8d64e13668 (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 MARK       all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:jmMdhpbIWf3Lbz4A */ MARK xset 0x3bc00000/0xfff00000

Chain cali-sm-calic7055d6afa6 (1 references)
 pkts bytes target     prot opt in     out     source               destination
    1    60 MARK       all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:nI1bkNIkjIMoAOp1 */ MARK xset 0xc8a00000/0xfff00000

Chain cali-sm-calif1aa1cfa43e (1 references)
 pkts bytes target     prot opt in     out     source               destination
    1    60 MARK       all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:bgCaaU195IMr5LLR */ MARK xset 0x38a00000/0xfff00000

Chain cali-to-hep-forward (2 references)
 pkts bytes target     prot opt in     out     source               destination

Chain cali-to-host-endpoint (1 references)
 pkts bytes target     prot opt in     out     source               destination

Chain cali-to-wl-dispatch (2 references)
 pkts bytes target     prot opt in     out     source               destination
 330K   25M cali-tw-calia8d64e13668  all  --  *      calia8d64e13668  0.0.0.0/0            0.0.0.0/0           [goto]  /* cali:FB4uMmkOJGtj183l */
    0     0 cali-tw-calic7055d6afa6  all  --  *      calic7055d6afa6  0.0.0.0/0            0.0.0.0/0           [goto]  /* cali:xoDxLUEjvYT6yOum */
    0     0 cali-tw-calif1aa1cfa43e  all  --  *      calif1aa1cfa43e  0.0.0.0/0            0.0.0.0/0           [goto]  /* cali:40carLP5uKzWbZev */
    0     0 DROP       all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:sbH_hQhJ6PJnPG6F */ /* Unknown interface */

Chain cali-tw-calia8d64e13668 (1 references)
 pkts bytes target     prot opt in     out     source               destination
 286K   23M ACCEPT     all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:WnH0XS7bhimcx7iL */ ctstate RELATED,ESTABLISHED
    0     0 DROP       all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:yZtzRk1AxmyJ2EXl */ ctstate INVALID
44710 2683K MARK       all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:f0ZXC1eoQzdzr30r */ MARK and 0xfffeffff
44710 2683K cali-pri-kns.rook-ceph  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:M8LXHNutEeiyqrg2 */
44710 2683K RETURN     all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:_pcfcHAI_LBiEY20 */ /* Return if profile accepted */
    0     0 cali-pri-_Tn6vS0_Qg9MjrpTirl  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:MfHXAv51daD7xtVU */
    0     0 RETURN     all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:iV2SE5t6ZE4jyqUy */ /* Return if profile accepted */
    0     0 DROP       all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:-vNX19x1UJZUG-fZ */ /* Drop if no profiles matched */

Chain cali-tw-calic7055d6afa6 (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 ACCEPT     all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:za59hBij2QCtPdH1 */ ctstate RELATED,ESTABLISHED
    0     0 DROP       all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:fKAMP5_fyazQ2ExK */ ctstate INVALID
    0     0 MARK       all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:bOFxSIGtEAvOQoCY */ MARK and 0xfffeffff
    0     0 cali-pri-kns.ceph  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:1PzoB0xWAVID2wyf */
    0     0 RETURN     all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:Auli2fFvsrse9o1e */ /* Return if profile accepted */
    0     0 cali-pri-_3CoffGHfcoYGrfpgcn  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:cpdhoYqQ2GI9RK0Z */
    0     0 RETURN     all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:HFhvTCUvM897E-JA */ /* Return if profile accepted */
    0     0 DROP       all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:r7n5uvrZj1YwLR-I */ /* Drop if no profiles matched */

Chain cali-tw-calif1aa1cfa43e (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 ACCEPT     all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:B-OZCez_58_Vw87S */ ctstate RELATED,ESTABLISHED
    0     0 DROP       all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:auxQ7G-7Iy9_5YpR */ ctstate INVALID
    0     0 MARK       all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:-vvqOPvoJZzRZgZk */ MARK and 0xfffeffff
    0     0 cali-pri-kns.openstack  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:pIvCQaf95QOZaG-H */
    0     0 RETURN     all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:NWmgOQ3UF3wopEFn */ /* Return if profile accepted */
    0     0 cali-pri-_yxO6sDNctlXrebydlU  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:RSfTwU5PR9YPdBGJ */
    0     0 RETURN     all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:l7MZMBM3JaTPkYvJ */ /* Return if profile accepted */
    0     0 DROP       all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:7Xb4xEPB9kF9ksFE */ /* Drop if no profiles matched */

Chain cali-wl-to-host (1 references)
 pkts bytes target     prot opt in     out     source               destination
 219K  107M cali-from-wl-dispatch  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:Ee9Sbo10IpVujdIY */
    0     0 ACCEPT     all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* cali:nSZbcOoG1xPONxb8 */ /* Configured DefaultEndpointToHostAction */
```
