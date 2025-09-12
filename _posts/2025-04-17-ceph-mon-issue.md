---
title: "Ceph 클러스터 설치 시 모니터 파드 시작 문제"
date: 2025-04-17
tags: [ceph, rook-ceph, mon]
categories: [Issues, Ceph]
---

초기 설치 시 모니터 파드(mon a, mon b, mon c)가 제때 실행되지 않는 경우가 있습니다. 아래는 그 예이며, 어떤 경우의 수가 있는지를 설명합니다.

### rook-ceph-operator 로그
```
citec@k1:~/osh$ kubectl -n rook-ceph logs -f -l app=rook-ceph-operator
2025-04-17 07:09:29.196366 I | ceph-csi: successfully started CSI Ceph RBD driver
2025-04-17 07:09:29.226152 I | ceph-csi: successfully started CSI CephFS driver
2025-04-17 07:09:29.230366 I | ceph-csi: CSIDriver object updated for driver "rook-ceph.rbd.csi.ceph.com"
2025-04-17 07:09:29.234553 I | ceph-csi: CSIDriver object updated for driver "rook-ceph.cephfs.csi.ceph.com"
2025-04-17 07:09:29.234638 I | op-k8sutil: removing daemonset csi-nfsplugin if it exists
2025-04-17 07:09:29.236535 I | op-k8sutil: removing deployment csi-nfsplugin-provisioner if it exists
2025-04-17 07:09:29.364526 I | ceph-csi: successfully removed CSI NFS driver
2025-04-17 07:09:47.156564 I | op-mon: mons running: [a]
2025-04-17 07:10:07.346786 I | op-mon: mons running: [a]
2025-04-17 07:10:27.547396 I | op-mon: mons running: [a]
2025-04-17 07:10:47.726950 I | op-mon: mons running: [a]
2025-04-17 07:11:07.912642 I | op-mon: mons running: [a]
2025-04-17 07:11:28.095363 I | op-mon: mons running: [a]
2025-04-17 07:11:48.312484 I | op-mon: mons running: [a]
2025-04-17 07:12:08.497523 I | op-mon: mons running: [a]
2025-04-17 07:12:28.686558 I | op-mon: mons running: [a]
2025-04-17 07:12:48.890350 I | op-mon: mons running: [a]
2025-04-17 07:13:09.075067 I | op-mon: mons running: [a]
2025-04-17 07:13:29.260885 I | op-mon: mons running: [a]
2025-04-17 07:13:49.449604 I | op-mon: mons running: [a]
2025-04-17 07:14:09.636765 I | op-mon: mons running: [a]
2025-04-17 07:14:29.824591 I | op-mon: mons running: [a]
2025-04-17 07:14:50.005152 I | op-mon: mons running: [a]
2025-04-17 07:15:10.189715 I | op-mon: mons running: [a]
2025-04-17 07:15:30.372587 I | op-mon: mons running: [a]
2025-04-17 07:15:50.577499 I | op-mon: mons running: [a]
2025-04-17 07:16:10.798885 I | op-mon: mons running: [a]
2025-04-17 07:16:30.992319 I | op-mon: mons running: [a]
2025-04-17 07:16:51.180059 I | op-mon: mons running: [a]
2025-04-17 07:17:11.380592 I | op-mon: mons running: [a]
2025-04-17 07:17:31.569562 I | op-mon: mons running: [a]
2025-04-17 07:17:51.756632 I | op-mon: mons running: [a]
2025-04-17 07:18:11.977445 I | op-mon: mons running: [a]
2025-04-17 07:18:32.167667 I | op-mon: mons running: [a]
2025-04-17 07:18:52.365043 I | op-mon: mons running: [a]
2025-04-17 07:19:12.574271 I | op-mon: mons running: [a]
2025-04-17 07:19:32.749952 I | op-mon: mons running: [a]
2025-04-17 07:19:52.935351 I | op-mon: mons running: [a]
2025-04-17 07:20:13.117475 I | op-mon: mons running: [a]
2025-04-17 07:20:33.302150 I | op-mon: mons running: [a]
2025-04-17 07:20:53.497534 I | op-mon: mons running: [a]
2025-04-17 07:21:13.686427 I | op-mon: mons running: [a]
2025-04-17 07:21:33.870679 I | op-mon: mons running: [a]
2025-04-17 07:21:54.054290 I | op-mon: mons running: [a]
2025-04-17 07:22:14.234956 I | op-mon: mons running: [a]
2025-04-17 07:22:34.419831 I | op-mon: mons running: [a]
2025-04-17 07:22:54.602316 I | op-mon: mons running: [a]
2025-04-17 07:23:14.788073 I | op-mon: mons running: [a]
2025-04-17 07:23:34.997377 I | op-mon: mons running: [a]
2025-04-17 07:23:55.181627 I | op-mon: mons running: [a]
2025-04-17 07:24:15.386446 I | op-mon: mons running: [a]
2025-04-17 07:24:35.569529 I | op-mon: mons running: [a]
2025-04-17 07:24:55.745502 I | op-mon: mons running: [a]
2025-04-17 07:25:15.926831 I | op-mon: mons running: [a]
2025-04-17 07:25:36.120742 I | op-mon: mons running: [a]
2025-04-17 07:25:56.315344 I | op-mon: mons running: [a]
2025-04-17 07:26:16.511818 I | op-mon: mons running: [a]
2025-04-17 07:26:36.697289 I | op-mon: mons running: [a]
2025-04-17 07:26:56.901465 I | op-mon: mons running: [a]
2025-04-17 07:27:17.082753 I | op-mon: mons running: [a]
2025-04-17 07:27:37.265585 I | op-mon: mons running: [a]
2025-04-17 07:27:57.457486 I | op-mon: mons running: [a]
2025-04-17 07:28:17.643402 I | op-mon: mons running: [a]
2025-04-17 07:28:37.835712 I | op-mon: mons running: [a]
2025-04-17 07:28:58.036942 I | op-mon: mons running: [a]
2025-04-17 07:29:18.230476 I | op-mon: mons running: [a]
2025-04-17 07:29:33.454595 E | ceph-cluster-controller: failed to reconcile CephCluster "rook-ceph/rook-ceph". failed to reconcile cluster "rook-ceph": failed to configure local ceph cluster: failed to create cluster: failed to start ceph monitors: failed to start mon pods: failed to check mon quorum a: failed to wait for mon quorum: exceeded max retry count waiting for monitors to reach quorum
2025-04-17 07:29:33.460297 I | ceph-cluster-controller: reconciling ceph cluster in namespace "rook-ceph"
2025-04-17 07:29:33.464495 I | ceph-spec: parsing mon endpoints: a=10.96.11.92:6789
2025-04-17 07:29:33.478500 I | ceph-spec: detecting the ceph image version for image quay.io/ceph/ceph:v18.2.4...
2025-04-17 07:29:35.591803 I | ceph-spec: detected ceph image version: "18.2.4-0 reef"
2025-04-17 07:29:35.591841 I | ceph-cluster-controller: validating ceph version from provided image
2025-04-17 07:29:35.600219 I | ceph-spec: parsing mon endpoints: a=10.96.11.92:6789
2025-04-17 07:29:35.604494 I | cephclient: writing config file /var/lib/rook/rook-ceph/rook-ceph.config
2025-04-17 07:29:35.604943 I | cephclient: generated admin config in /var/lib/rook/rook-ceph
2025-04-17 07:29:50.781600 E | ceph-cluster-controller: failed to get ceph daemons versions, this typically happens during the first cluster initialization. failed to run 'ceph versions'. . timed out: exit status 1
2025-04-17 07:29:50.781636 I | ceph-cluster-controller: cluster "rook-ceph": version "18.2.4-0 reef" detected for image "quay.io/ceph/ceph:v18.2.4"
2025-04-17 07:29:50.805641 I | op-mon: start running mons
2025-04-17 07:29:50.809093 I | ceph-spec: parsing mon endpoints: a=10.96.11.92:6789
2025-04-17 07:29:50.819108 I | op-mon: saved mon endpoints to config map map[csi-cluster-config-json:[{"clusterID":"rook-ceph","monitors":["10.96.11.92:6789"],"cephFS":{"netNamespaceFilePath":"","subvolumeGroup":"","radosNamespace":"","kernelMountOptions":"","fuseMountOptions":""},"rbd":{"netNamespaceFilePath":"","radosNamespace":"","mirrorDaemonCount":0},"nfs":{"netNamespaceFilePath":""},"readAffinity":{"enabled":false,"crushLocationLabels":null},"namespace":""}] data:a=10.96.11.92:6789 externalMons: mapping:{"node":{"a":{"Name":"k1","Hostname":"k1","Address":"172.16.2.149"},"b":{"Name":"k3","Hostname":"k3","Address":"172.16.2.223"},"c":{"Name":"k2","Hostname":"k2","Address":"172.16.2.52"}}} maxMonId:0 outOfQuorum:]
2025-04-17 07:29:50.824569 I | op-mon: created/updated IPv4 endpointslice with addresses: [10.96.11.92]
2025-04-17 07:29:51.000893 I | cephclient: writing config file /var/lib/rook/rook-ceph/rook-ceph.config
2025-04-17 07:29:51.001202 I | cephclient: generated admin config in /var/lib/rook/rook-ceph
2025-04-17 07:29:52.602335 I | op-mon: targeting the mon count 3
2025-04-17 07:29:52.608049 I | op-config: applying ceph settings for "global"
2025-04-17 07:30:07.609489 I | exec: exec timeout waiting for process ceph to return. Sending interrupt signal to the process
2025-04-17 07:30:07.615369 E | op-config: failed to open assimilate output file /var/lib/rook/2410115400.out. open /var/lib/rook/2410115400.out: no such file or directory
2025-04-17 07:30:07.615401 E | op-config: failed to run command ceph [config assimilate-conf -i /var/lib/rook/2410115400 -o /var/lib/rook/2410115400.out]
2025-04-17 07:30:07.615417 E | op-config: failed to apply ceph settings for "global"
2025-04-17 07:30:07.615531 E | op-config: failed to remove file "/var/lib/rook/2410115400.out". remove /var/lib/rook/2410115400.out: no such file or directory
2025-04-17 07:30:07.615597 W | op-mon: failed to set Rook and/or user-defined Ceph config options before starting mons; will retry after starting mons. failed to apply default Ceph configurations: failed to set all keys: failed to set ceph config in the centralized mon configuration database; output: Cluster connection aborted: exit status 1
2025-04-17 07:30:07.615615 I | op-mon: creating mon b
2025-04-17 07:30:07.632375 I | op-mon: mon "a" cluster IP is 10.96.11.92
2025-04-17 07:30:07.637515 I | op-mon: mon "b" cluster IP is 10.96.228.121
2025-04-17 07:30:07.650576 I | op-mon: saved mon endpoints to config map map[csi-cluster-config-json:[{"clusterID":"rook-ceph","monitors":["10.96.11.92:6789","10.96.228.121:6789"],"cephFS":{"netNamespaceFilePath":"","subvolumeGroup":"","radosNamespace":"","kernelMountOptions":"","fuseMountOptions":""},"rbd":{"netNamespaceFilePath":"","radosNamespace":"","mirrorDaemonCount":0},"nfs":{"netNamespaceFilePath":""},"readAffinity":{"enabled":false,"crushLocationLabels":null},"namespace":""}] data:a=10.96.11.92:6789,b=10.96.228.121:6789 externalMons: mapping:{"node":{"a":{"Name":"k1","Hostname":"k1","Address":"172.16.2.149"},"b":{"Name":"k3","Hostname":"k3","Address":"172.16.2.223"},"c":{"Name":"k2","Hostname":"k2","Address":"172.16.2.52"}}} maxMonId:0 outOfQuorum:]
2025-04-17 07:30:07.657544 I | op-mon: created/updated IPv4 endpointslice with addresses: [10.96.11.92 10.96.228.121]
2025-04-17 07:30:07.819824 I | cephclient: writing config file /var/lib/rook/rook-ceph/rook-ceph.config
2025-04-17 07:30:07.820229 I | cephclient: generated admin config in /var/lib/rook/rook-ceph
2025-04-17 07:30:08.223597 I | op-mon: 1 of 2 expected mon deployments exist. creating new deployment(s).
2025-04-17 07:30:08.228254 I | op-mon: deployment for mon rook-ceph-mon-a already exists. updating if needed
2025-04-17 07:30:08.234881 I | op-k8sutil: deployment "rook-ceph-mon-a" did not change, nothing to update
2025-04-17 07:30:08.418162 I | op-mon: updating maxMonID from 0 to 1
2025-04-17 07:30:09.219522 I | op-mon: saved mon endpoints to config map map[csi-cluster-config-json:[{"clusterID":"rook-ceph","monitors":["10.96.11.92:6789","10.96.228.121:6789"],"cephFS":{"netNamespaceFilePath":"","subvolumeGroup":"","radosNamespace":"","kernelMountOptions":"","fuseMountOptions":""},"rbd":{"netNamespaceFilePath":"","radosNamespace":"","mirrorDaemonCount":0},"nfs":{"netNamespaceFilePath":""},"readAffinity":{"enabled":false,"crushLocationLabels":null},"namespace":""}] data:b=10.96.228.121:6789,a=10.96.11.92:6789 externalMons: mapping:{"node":{"a":{"Name":"k1","Hostname":"k1","Address":"172.16.2.149"},"b":{"Name":"k3","Hostname":"k3","Address":"172.16.2.223"},"c":{"Name":"k2","Hostname":"k2","Address":"172.16.2.52"}}} maxMonId:1 outOfQuorum:]
2025-04-17 07:30:09.225958 I | op-mon: created/updated IPv4 endpointslice with addresses: [10.96.228.121 10.96.11.92]
2025-04-17 07:30:09.228535 I | op-mon: waiting for mon quorum with [a b]
2025-04-17 07:30:09.622328 I | op-mon: mon b is not yet running
2025-04-17 07:30:09.622360 I | op-mon: mons running: [a]
2025-04-17 07:30:29.817021 I | op-mon: mons running: [a b]
```

주어진 로그는 OpenStack-Helm 환경에서 Rook-Ceph 클러스터를 설정하는 과정에서 `rook-ceph-operator`의 동작을 기록한 것입니다. 이 로그는 Ceph 스토리지 클러스터의 초기화, 모니터(Monitor, 이하 mon) 설정, 그리고 관련된 CSI(Container Storage Interface) 드라이버 설정 과정을 보여줍니다. 로그를 통해 Ceph 클러스터가 초기화되고 mon 프로세스가 시작되며, 일부 오류가 발생한 상황을 확인할 수 있습니다. 아래에서 로그의 주요 부분을 단계별로 분석하고, 왜 `mon a`만 오랫동안 실행되었는지, 그리고 그 원인을 상세히 설명하겠습니다.

---

### **로그 분석: 주요 단계와 의미**

로그는 시간순으로 진행되며, Ceph 클러스터의 초기화 및 모니터 설정 과정을 보여줍니다. 각 단계와 오류를 자세히 살펴보겠습니다.

#### **1. 초기화 및 CSI 드라이버 설정 (07:09:29)**

```
2025-04-17 07:09:29.196366 I | ceph-csi: successfully started CSI Ceph RBD driver
2025-04-17 07:09:29.226152 I | ceph-csi: successfully started CSI CephFS driver
2025-04-17 07:09:29.230366 I | ceph-csi: CSIDriver object updated for driver "rook-ceph.rbd.csi.ceph.com"
2025-04-17 07:09:29.234553 I | ceph-csi: CSIDriver object updated for driver "rook-ceph.cephfs.csi.ceph.com"
2025-04-17 07:09:29.234638 I | op-k8sutil: removing daemonset csi-nfsplugin if it exists
2025-04-17 07:09:29.236535 I | op-k8sutil: removing deployment csi-nfsplugin-provisioner if it exists
2025-04-17 07:09:29.364526 I | ceph-csi: successfully removed CSI NFS driver
```

- **의미**:
  - Rook-Ceph 오퍼레이터가 Ceph 클러스터와 Kubernetes 간의 스토리지 통합을 위해 CSI 드라이버를 초기화하고 있습니다.
  - `RBD`(Rados Block Device)와 `CephFS`(Ceph File System) 드라이버가 성공적으로 시작되었습니다. 이는 Kubernetes에서 Ceph의 블록 스토리지와 파일 스토리지를 사용할 수 있도록 준비된 것입니다.
  - `CSIDriver` 객체가 업데이트되어 Kubernetes가 이 드라이버를 인식하도록 설정되었습니다.
  - NFS 관련 CSI 드라이버(`csi-nfsplugin`, `csi-nfsplugin-provisioner`)는 필요하지 않으므로 제거되었습니다.
- **상태**:
  - 이 단계는 정상적으로 완료되었습니다. Ceph 클러스터와 Kubernetes 간의 스토리지 인터페이스가 준비된 상태입니다.

#### **2. 모니터 상태 확인 (07:09:47 ~ 07:29:18)**

```
2025-04-17 07:09:47.156564 I | op-mon: mons running: [a]
2025-04-17 07:10:07.346786 I | op-mon: mons running: [a]
...
2025-04-17 07:29:18.230476 I | op-mon: mons running: [a]
```

- **의미**:
  - Rook-Ceph 오퍼레이터가 Ceph 클러스터의 모니터(monitor, mon) 상태를 주기적으로 확인하고 있습니다.
  - Ceph 클러스터는 데이터를 관리하고 클러스터 상태를 유지하기 위해 여러 모니터를 실행합니다. 모니터는 클러스터의 메타데이터를 관리하고, 다른 Ceph 데몬(Mgr, OSD 등)과 통신합니다.
  - 이 로그에서 `mon a`만 실행 중인 것으로 나타나며, 다른 모니터(`mon b`, `mon c` 등)는 아직 시작되지 않았습니다.
  - 약 20분 동안(07:09:47 ~ 07:29:18) `mon a`만 실행 중이었으며, 이는 클러스터가 정상적으로 초기화되지 않았음을 시사합니다.

- **문제점**:
  - Ceph 클러스터는 고가용성을 보장하기 위해 일반적으로 최소 3개의 모니터를 실행하며, 모니터들이 **쿼럼(quorum)**을 형성해야 클러스터가 정상적으로 동작합니다.
  - 쿼럼은 다수의 모니터가 서로 통신하여 클러스터 상태에 동의하는 상태를 의미합니다. 현재 `mon a`만 실행 중이므로 쿼럼이 형성되지 않았습니다.

#### **3. 오류 발생: 쿼럼 형성 실패 (07:29:33)**

```
2025-04-17 07:29:33.454595 E | ceph-cluster-controller: failed to reconcile CephCluster "rook-ceph/rook-ceph". failed to reconcile cluster "rook-ceph": failed to configure local ceph cluster: failed to create cluster: failed to start ceph monitors: failed to start mon pods: failed to check mon quorum a: failed to wait for mon quorum: exceeded max retry count waiting for monitors to reach quorum
```

- **의미**:
  - Ceph 클러스터의 초기화(`reconcile`) 과정에서 오류가 발생했습니다.
  - 오류의 핵심은 **모니터 쿼럼을 형성하지 못했다**는 것입니다. Rook-Ceph 오퍼레이터는 모니터들이 쿼럼을 형성할 때까지 반복적으로 시도했지만, 최대 재시도 횟수를 초과하여 실패했습니다.
  - `failed to start mon pods`는 추가 모니터 파드(`mon b`, `mon c` 등)가 시작되지 않았음을 나타냅니다.
  - `failed to check mon quorum a`는 `mon a`가 실행 중이지만, 다른 모니터와 통신하여 쿼럼을 형성하지 못했음을 의미합니다.

- **원인 가능성**:
  - **네트워크 문제**: `mon a`가 다른 노드의 모니터와 통신하지 못했을 가능성이 있습니다. Ceph 모니터는 지정된 포트(기본: 6789)로 통신하며, 네트워크 정책이나 방화벽이 이를 차단했을 수 있습니다.
  - **리소스 부족**: 모니터 파드를 실행할 노드에 충분한 CPU, 메모리, 디스크 리소스가 부족했을 수 있습니다.
  - **스케줄링 문제**: Kubernetes 스케줄러가 모니터 파드를 적절한 노드에 배치하지 못했을 가능성이 있습니다(예: 노드 셀렉터, 테인트/톨러레이션 문제).
  - **설정 오류**: Rook-Ceph의 `CephCluster` 리소스 정의에서 모니터 수, 네트워크 설정, 또는 스토리지 설정이 잘못되었을 수 있습니다.

#### **4. 클러스터 재조정 및 설정 적용 시도 (07:29:33 ~ 07:30:07)**

```
2025-04-17 07:29:33.460297 I | ceph-cluster-controller: reconciling ceph cluster in namespace "rook-ceph"
2025-04-17 07:29:33.464495 I | ceph-spec: parsing mon endpoints: a=10.96.11.92:6789
2025-04-17 07:29:33.478500 I | ceph-spec: detecting the ceph image version for image quay.io/ceph/ceph:v18.2.4...
2025-04-17 07:29:35.591803 I | ceph-spec: detected ceph image version: "18.2.4-0 reef"
...
2025-04-17 07:29:50.781600 E | ceph-cluster-controller: failed to get ceph daemons versions, this typically happens during the first cluster initialization. failed to run 'ceph versions'. . timed out: exit status 1
2025-04-17 07:29:50.781636 I | ceph-cluster-controller: cluster "rook-ceph": version "18.2.4-0 reef" detected for image "quay.io/ceph/ceph:v18.2.4"
```

- **의미**:
  - Rook-Ceph 오퍼레이터가 클러스터를 다시 조정(`reconcile`)하려고 시도합니다.
  - `mon a`의 엔드포인트(`10.96.11.92:6789`)를 확인하고, Ceph 이미지 버전(`18.2.4-0 reef`)을 감지했습니다.
  - 그러나 `ceph versions` 명령이 타임아웃으로 실패했습니다. 이는 클러스터가 아직 완전히 초기화되지 않아 Ceph 데몬 상태를 확인할 수 없음을 나타냅니다. 로그에서 "this typically happens during the first cluster initialization"라고 언급하듯, 초기 설정 중에는 자주 발생하는 상황입니다.

- **상태**:
  - 이 단계에서는 클러스터가 아직 완전히 동작하지 않지만, 오퍼레이터가 계속 설정을 시도하고 있습니다.

#### **5. 모니터 추가 시도 및 설정 오류 (07:30:07)**

```
2025-04-17 07:30:07.609489 I | exec: exec timeout waiting for process ceph to return. Sending interrupt signal to the process
2025-04-17 07:30:07.615369 E | op-config: failed to open assimilate output file /var/lib/rook/2410115400.out. open /var/lib/rook/2410115400.out: no such file or directory
2025-04-17 07:30:07.615401 E | op-config: failed to run command ceph [config assimilate-conf -i /var/lib/rook/2410115400 -o /var/lib/rook/2410115400.out]
2025-04-17 07:30:07.615417 E | op-config: failed to apply ceph settings for "global"
2025-04-17 07:30:07.615531 E | op-config: failed to remove file "/var/lib/rook/2410115400.out". remove /var/lib/rook/2410115400.out: no such file or directory
2025-04-17 07:30:07.615597 W | op-mon: failed to set Rook and/or user-defined Ceph config options before starting mons; will retry after starting mons. failed to apply default Ceph configurations: failed to set all keys: failed to set ceph config in the centralized mon configuration database; output: Cluster connection aborted: exit status 1
```

- **의미**:
  - Rook-Ceph 오퍼레이터가 Ceph 설정(`global` 섹션)을 적용하려고 했으나 실패했습니다.
  - `ceph config assimilate-conf` 명령이 실행되지 않아 설정 파일을 처리할 수 없었습니다. 이는 모니터 쿼럼이 없거나 클러스터가 초기화되지 않아 Ceph 명령이 실행되지 않은 결과입니다.
  - 오류 메시지에서 "Cluster connection aborted"가 나타나며, 이는 Ceph 클러스터와의 연결이 끊어졌음을 의미합니다. 이는 모니터가 정상적으로 동작하지 않거나 네트워크 문제가 있음을 시사합니다.
  - 오퍼레이터는 이 오류를 무시하고 모니터 시작을 계속 시도하며, 나중에 설정을 재시도하겠다고 로그에 기록합니다.

- **문제점**:
  - 이 오류는 모니터 쿼럼이 형성되지 않아 Ceph 클러스터가 정상적으로 동작하지 않는 상황에서 발생했습니다.
  - 설정 파일(`/var/lib/rook/2410115400.out`) 관련 오류는 Ceph 명령이 실패하면서 출력 파일이 생성되지 않은 결과입니다.

#### **6. 모니터 추가 및 성공 (07:30:07 ~ 07:30:29)**

```
2025-04-17 07:30:07.615615 I | op-mon: creating mon b
2025-04-17 07:30:07.632375 I | op-mon: mon "a" cluster IP is 10.96.11.92
2025-04-17 07:30:07.637515 I | op-mon: mon "b" cluster IP is 10.96.228.121
...
2025-04-17 07:30:09.228535 I | op-mon: waiting for mon quorum with [a b]
2025-04-17 07:30:09.622328 I | op-mon: mon b is not yet running
2025-04-17 07:30:09.622360 I | op-mon: mons running: [a]
2025-04-17 07:30:29.817021 I | op-mon: mons running: [a b]
```

- **의미**:
  - 오퍼레이터가 `mon b`를 생성하려고 시도했습니다. `mon b`의 클러스터 IP는 `10.96.228.121:6789`로 설정되었습니다.
  - 모니터 엔드포인트가 ConfigMap에 저장되고, IPv4 EndpointSlice가 업데이트되었습니다.
  - 처음에는 `mon b`가 실행 중이 아니었지만, 약 20초 후(07:30:29)에 `mon b`가 실행되며 `[a b]`가 모두 실행 중인 것으로 확인되었습니다.
  - 이는 `mon b` 파드가 성공적으로 시작되었고, `mon a`와 통신을 시작했음을 의미합니다.

- **상태**:
  - `mon b`가 추가되면서 클러스터가 쿼럼 형성에 한 발짝 다가갔습니다. 하지만 로그가 여기서 끝나므로, 쿼럼이 실제로 형성되었는지, 또는 `mon c`가 추가되었는지는 확인할 수 없습니다.

---

### **왜 `mon a`만 오랫동안 실행되었을까?**

로그를 분석한 결과, `mon a`만 약 20분 동안 실행된 이유는 Ceph 클러스터의 초기화 과정에서 **모니터 쿼럼 형성에 실패**했기 때문입니다. 아래에서 주요 원인과 그 배경을 자세히 설명합니다.

#### **1. 모니터 쿼럼의 중요성**
- Ceph 클러스터는 최소 3개의 모니터를 실행하여 쿼럼을 형성하는 것이 일반적입니다. 쿼럼이 형성되지 않으면 클러스터는 정상적으로 동작하지 않으며, 다른 데몬(OSD, Mgr 등)도 시작되지 않습니다.
- 로그에서 `mon a`만 실행 중이었고, `mon b`와 `mon c`는 오랫동안 시작되지 않았습니다. 이는 쿼럼 형성에 필요한 최소 모니터 수(2개 이상)가 충족되지 않아 클러스터 초기화가 지연된 것입니다.

#### **2. `mon b`와 `mon c` 시작 지연의 원인**
`mon a`만 실행되고 다른 모니터가 시작되지 않은 이유는 여러 가지일 수 있습니다. 로그와 일반적인 Rook-Ceph 문제 상황을 바탕으로 가장 가능성 높은 원인을 추측해 봅니다:

- **네트워크 문제**:
  - Ceph 모니터는 서로 통신하여 쿼럼을 형성합니다. `mon a`가 실행 중인 노드(`k1`, IP: `172.16.2.149`)와 다른 노드(`k3`, `k2`) 간의 네트워크 연결에 문제가 있었을 가능성이 있습니다.
  - 로그에서 `mon a`의 엔드포인트는 `10.96.11.92:6789`로 나타나며, 이는 Kubernetes 클러스터 내부 IP입니다. 그러나 `mon b`와 `mon c`가 실행될 노드(`k3`, `k2`)에서 이 IP로 통신하지 못했을 수 있습니다.
  - **해결 방안**:
    - Kubernetes 네트워크 정책(NetworkPolicy)을 확인하여 모니터 포트(6789, 3300 등)가 차단되지 않았는지 확인하세요.
    - 노드 간 방화벽 설정을 점검하고, Ceph 모니터가 사용하는 포트가 열려 있는지 확인하세요.
    - `kubectl -n rook-ceph exec -it <mon-a-pod> -- ceph -s` 명령으로 클러스터 상태를 확인하여 네트워크 연결 문제를 진단하세요.

- **리소스 부족**:
  - `mon b`와 `mon c`를 실행할 노드(`k3`, `k2`)에 CPU, 메모리, 또는 디스크 리소스가 부족했을 수 있습니다. 모니터 파드는 비교적 가벼운 리소스를 사용하지만, 노드가 이미 다른 워크로드로 포화 상태였다면 파드 시작이 지연되었을 수 있습니다.
  - **해결 방안**:
    - `kubectl describe node k3` 및 `kubectl describe node k2` 명령으로 노드의 리소스 상태를 확인하세요.
    - `kubectl -n rook-ceph describe pod` 명령으로 모니터 파드의 이벤트 로그를 확인하여 리소스 부족 관련 오류(`Insufficient CPU`, `Insufficient memory`)가 있는지 확인하세요.

- **파드 스케줄링 문제**:
  - Kubernetes 스케줄러가 `mon b`와 `mon c` 파드를 적절한 노드에 배치하지 못했을 가능성이 있습니다. 이는 노드 셀렉터, 테인트/톨러레이션, 또는 스토리지 설정 문제로 발생할 수 있습니다.
  - 로그에서 `mapping` 정보를 보면, `mon b`는 `k3` 노드, `mon c`는 `k2` 노드에 배치되도록 설정되었습니다. 하지만 이 노드들이 준비되지 않았거나, 파드 배치 조건을 충족하지 못했을 수 있습니다.
  - **해결 방안**:
    - `kubectl -n rook-ceph get pods -o wide` 명령으로 모니터 파드의 상태와 배치된 노드를 확인하세요.
    - `kubectl -n rook-ceph describe pod <mon-b-pod>` 명령으로 파드 시작 실패 원인을 확인하세요(예: `FailedScheduling` 이벤트).
    - `CephCluster` 리소스의 `placement` 또는 `nodeAffinity` 설정을 점검하여 올바른 노드에 파드가 배치되도록 수정하세요.

- **스토리지 설정 문제**:
  - Ceph 모니터는 데이터를 저장하기 위해 Persistent Volume(PV)을 사용합니다. `mon b`와 `mon c`의 PV가 프로비저닝되지 않았거나, 스토리지 클래스가 올바르게 설정되지 않았을 수 있습니다.
  - **해결 방안**:
    - `kubectl -n rook-ceph get pvc` 명령으로 모니터 파드의 Persistent Volume Claim 상태를 확인하세요.
    - Rook-Ceph의 `CephCluster` 리소스에서 `mon` 섹션의 스토리지 설정을 확인하고, 올바른 스토리지 클래스가 지정되었는지 확인하세요.

- **Ceph 초기화 지연**:
  - Ceph 클러스터의 초기화는 특히 첫 설정 시 시간이 걸릴 수 있습니다. 로그에서 "this typically happens during the first cluster initialization"라고 언급된 것처럼, 초기 설정 중 모니터가 순차적으로 시작되면서 지연이 발생했을 수 있습니다.
  - 그러나 20분은 일반적인 초기화 시간보다 훨씬 길므로, 위의 네트워크, 리소스, 또는 스케줄링 문제가 주요 원인일 가능성이 높습니다.

#### **3. `mon a`만 실행된 이유**
- `mon a`는 `k1` 노드에 성공적으로 배치되고 실행되었지만, 다른 모니터(`mon b`, `mon c`)는 위의 문제들로 인해 시작되지 않았습니다.
- Rook-Ceph 오퍼레이터는 모니터 쿼럼이 형성될 때까지 대기하며, 쿼럼이 없으면 추가 모니터를 시작하려고 시도합니다. 하지만 `mon b`와 `mon c`의 파드가 시작되지 않아 `mon a`만 계속 실행된 상태로 로그에 기록된 것입니다.
- 결국 07:30:07에 `mon b`를 생성하려는 시도가 성공하고, 07:30:29에 `mon b`가 실행되면서 `[a b]` 상태로 전환되었습니다.

#### **4. 쿼럼 형성 지연의 결과**
- 쿼럼이 형성되지 않으면 Ceph 클러스터는 다른 데몬(OSD, Mgr 등)을 시작하지 않습니다. 이는 로그에서 `ceph versions` 명령이 실패하고, 설정 적용(`ceph config assimilate-conf`)이 실패한 이유를 설명합니다.
- 쿼럼이 형성되기 전까지 `mon a`는 단독으로 실행되며, 클러스터 상태를 유지하려고 하지만 실제 작업은 진행되지 않습니다.

---

### **문제 해결 방법**

로그에서 확인된 오류와 `mon a`만 오랫동안 실행된 상황을 해결하기 위해 다음 단계를 수행하세요:

1. **모니터 파드 상태 확인**:
```
kubectl -n rook-ceph get pods -l app=rook-ceph-mon
kubectl -n rook-ceph describe pod <mon-b-pod> <mon-c-pod>
```
   - 파드 상태가 `Pending`, `CrashLoopBackOff`, 또는 `Error`인지 확인하고, 이벤트 로그에서 실패 원인을 찾으세요.

2. **노드 상태 점검**:
```
kubectl describe node k1 k2 k3
```
   - 노드의 리소스 상태, 테인트, 또는 스케줄링 문제를 확인하세요.

3. **네트워크 연결 테스트**:
   - `mon a` 파드에서 다른 모니터 엔드포인트로 연결을 테스트하세요:
```
kubectl -n rook-ceph exec -it <mon-a-pod> -- ping 10.96.228.121
kubectl -n rook-ceph exec -it <mon-a-pod> -- ceph -s
```
   - 네트워크 정책 또는 방화벽 설정을 확인하여 포트 6789와 3300이 열려 있는지 확인하세요.

4. **CephCluster 리소스 검토**:
```
kubectl -n rook-ceph get cephcluster rook-ceph -o yaml
```
   - `mon` 섹션에서 모니터 수(`count`), 스토리지 설정, 노드 배치 설정(`placement`, `nodeAffinity`)을 확인하세요.
   - 예시 `CephCluster` 설정:
```yaml
spec:
  mon:
    count: 3
    allowMultiplePerNode: false
  placement:
    mon:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
          - matchExpressions:
            - key: kubernetes.io/hostname
              operator: In
              values:
              - k1
              - k2
              - k3
```

5. **스토리지 클래스 및 PVC 확인**:
```
kubectl -n rook-ceph get pvc
kubectl -n rook-ceph get storageclass
```
   - 모니터 파드의 PVC가 `Bound` 상태인지 확인하고, 스토리지 클래스가 올바르게 설정되었는지 확인하세요.

6. **로그 추가 확인**:
   - `mon b`와 `mon c` 파드의 로그를 확인하여 추가 오류를 찾으세요:
```
kubectl -n rook-ceph logs <mon-b-pod>
kubectl -n rook-ceph logs <mon-c-pod>
```

7. **Rook-Ceph 재설정(선택 사항)**:
   - 문제가 해결되지 않으면, Rook-Ceph 클러스터를 삭제하고 재설치할 수 있습니다:
```
kubectl -n rook-ceph delete cephcluster rook-ceph
helm uninstall rook-ceph -n rook-ceph
```
   - 삭제 후, 노드의 리소스와 네트워크 설정을 점검한 뒤 재배포하세요.

---

### **결론**

로그에서 `mon a`만 약 20분 동안 실행된 이유는 Ceph 클러스터의 모니터 쿼럼 형성에 실패했기 때문입니다. 이는 `mon b`와 `mon c` 파드가 시작되지 않은 문제로, 네트워크 문제, 리소스 부족, 파드 스케줄링 문제, 또는 스토리지 설정 오류가 원인일 가능성이 높습니다. 특히, 로그에서 나타난 "failed to wait for mon quorum" 오류와 설정 적용 실패는 쿼럼이 없어 클러스터가 초기화되지 않은 결과입니다. 

문제를 해결하려면 모니터 파드와 노드 상태를 확인하고, 네트워크 연결, 리소스, 스토리지 설정을 점검해야 합니다. 위의 단계별 해결 방법을 따라 문제를 진단하고 수정하면 클러스터가 정상적으로 초기화될 가능성이 높습니다. 추가로 로그나 오류 메시지가 있다면 공유해 주시면 더 구체적인 해결 방안을 제안할 수 있습니다!
