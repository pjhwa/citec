---
title: "OpenStack Helm 설치 - 2부"
date: 2025-06-10
tags: [openstack, helm, kubernetes, ceph, ansible]
categories: [Howtos, OpenStack]
---

이 문서는 OpenStack Helm을 활용하여 Kubernetes 환경에 OpenStack 서비스를 배포하는 과정을 안내합니다. Kubernetes와 Rook-Ceph가 이미 구축된 상태에서, 이 가이드는 OpenStack의 주요 서비스들을 설치하는 단계를 초보자도 쉽게 따라 할 수 있도록 상세히 설명합니다. 명령어와 출력 예시를 그대로 유지하며, 기술적 배경과 보완이 필요한 부분을 이해하기 쉽게 풀어냈습니다. 또한, OpenStack 서비스의 네트워크 구성과 클러스터 아키텍처를 텍스트 다이어그램으로 시각화하여 전체 구조를 한눈에 파악할 수 있도록 했습니다.

---

## 설치 개요

OpenStack Helm은 Helm 차트를 사용해 OpenStack 서비스를 Kubernetes 클러스터에 배포하는 도구입니다. Helm은 Kubernetes의 패키지 매니저로, 복잡한 애플리케이션 설치를 단순화합니다. OpenStack 서비스들은 서로 의존성이 있으므로 설치 순서를 지키는 것이 중요합니다.

### 설치 순서

1. **인프라 서비스**: MariaDB(데이터베이스), RabbitMQ(메시지 브로커), Memcached(캐싱)
2. **코어 서비스**: Keystone(인증 및 서비스 관리)
3. **추가 서비스**: Glance(이미지 관리), Placement(리소스 할당), OpenVswitch(네트워크 스위치), Libvirt(가상화), Neutron(네트워킹) 등

**왜 순서가 중요한가요?**
- MariaDB와 RabbitMQ는 다른 서비스들이 데이터를 저장하거나 통신할 때 필요합니다.
- Keystone은 OpenStack의 "신분증" 같은 역할을 하며, 다른 서비스가 Keystone에 등록되어야 동작합니다.
- Neutron은 네트워크를 관리하므로, 이를 위해 OpenVswitch가 먼저 설치되어야 합니다.

---

## 상세 설치 과정

### Rook-Ceph 스토리지 설정

OpenStack은 데이터를 저장하기 위해 Rook-Ceph라는 분산 스토리지 시스템을 사용합니다. Ceph는 여러 노드에 데이터를 나눠 저장해 안정성과 확장성을 제공합니다.

#### Ceph 상태 확인
```
citec@k1:~$ kceph ceph -s
  cluster:
    id:     224dbf5c-cee5-460c-b0d3-d96c76483f14
    health: HEALTH_OK
  services:
    mon: 3 daemons, quorum a,b,c (age 94s)
    mgr: a(active, since 19s)
    osd: 6 osds: 4 up (since 7s), 6 in (since 46s)
  data:
    pools:   0 pools, 0 pgs
    objects: 0 objects, 0 B
    usage:   1.3 GiB used, 71 GiB / 72 GiB avail
    pgs:
```

**확인 포인트**: `health: HEALTH_OK`가 출력되면 Ceph가 정상입니다. `mon`은 모니터링 데몬, `osd`는 스토리지 데몬을 의미합니다.

#### StorageClass 및 풀 생성
```
citec@k1:~/osh$ ./O01.storageclass.sh
>>> Creating rook-ceph-block StorageClass...
storageclass.storage.k8s.io/rook-ceph-block created
>>> Checking StorageClass...
NAME              PROVISIONER                  RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION   AGE
rook-ceph-block   rook-ceph.rbd.csi.ceph.com   Delete          Immediate           true                   141m
>>> Creating replicapool for rook-ceph-block StorageClass...
pool 'replicapool' created
>>> Checking OSD Pool List...
.mgr
replicapool
Done.
```

**기술적 배경**: 
- `StorageClass`는 Kubernetes에서 스토리지를 동적으로 할당하는 방법을 정의합니다. 예를 들어, OpenStack이 데이터를 저장할 때 자동으로 Ceph에 공간을 만듭니다.
- `replicapool`은 Ceph에서 데이터를 저장하는 "저장소"로, 데이터 복제를 통해 안전성을 높입니다.

---

### CoreDNS RBAC 권한 설정

CoreDNS는 Kubernetes에서 서비스 이름을 IP로 변환해주는 DNS 서버입니다. 이를 위해 클러스터 내 리소스 정보를 읽을 권한이 필요합니다.

#### 권한 설정
```
citec@k1:~/osh$ ./O02.coredns-rbac.sh
>>> Defining RBAC for CoreDNS...
clusterrole.rbac.authorization.k8s.io/coredns created
clusterrolebinding.rbac.authorization.k8s.io/coredns created
>>> Restarting CoreDNS Deployment...
deployment.apps/coredns restarted
Done.
```

#### 확인
```
citec@k1:~/osh$ kubectl describe clusterrole coredns
Name:         coredns
PolicyRule:
  Resources                        Non-Resource URLs  Resource Names  Verbs
  ---------                        -----------------  --------------  -----
  endpoints                        []                 []              [list watch]
  namespaces                       []                 []              [list watch]
  pods                             []                 []              [list watch]
  services                         []                 []              [list watch]
  endpointslices.discovery.k8s.io  []                 []              [list watch]
```

**기술적 배경**: 
- RBAC는 Kubernetes의 권한 관리 시스템으로, CoreDNS가 필요한 정보를 조회할 수 있도록 `list`와 `watch` 권한을 부여합니다.
- CoreDNS가 재시작되며 새 권한을 적용받습니다.

**확인 포인트**: `PolicyRule`에 `endpoints`, `services` 등이 나열되어 있으면 설정이 잘 된 것입니다.

---

### Rook-Ceph 모니터 이름 변경 자동화

Ceph 모니터는 클러스터 상태를 관리합니다. 노드 장애 시 모니터 이름이 바뀔 수 있어, 이를 자동으로 업데이트하는 작업이 필요합니다.

#### CronJob 설정
```
citec@k1:~/osh$ ./O03.rook-ceph-mon-update.sh
>>> Registering for automated updates to rook-ceph monitor information...
cronjob.batch/update-ceph-config created
configmap/update-ceph-config-script created
NAME                         SCHEDULE       TIMEZONE   SUSPEND   ACTIVE   LAST SCHEDULE   AGE
keystone-credential-rotate   0 0 1 * *      <none>     False     0        <none>          29m
keystone-fernet-rotate       0 */12 * * *   <none>     False     0        <none>          29m
update-ceph-config           0 0 * * *      <none>     False     0        <none>          95s
Done.
```

**기술적 배경**: 
- Kubernetes의 `CronJob`은 주기적으로 작업을 실행합니다. 여기서는 매일 자정에 모니터 정보를 업데이트합니다.
- `ConfigMap`은 설정 데이터를 저장하는 객체로, Ceph 설정을 반영합니다.

---

### MariaDB 설치

MariaDB는 OpenStack의 데이터베이스로, 모든 서비스가 데이터를 저장하는 데 사용합니다.

#### 설치
```
citec@k1:~/osh$ ./O04.mariadb.sh
>>> Initializing MariaDB install...
>>> Running helm dependency build...
>>> Configuring label of nodes...
>>> Installing MariaDB...
pod/mariadb-controller-68584bd996-644vm condition met
pod/mariadb-server-0 condition met
NAME                                  READY   STATUS    RESTARTS   AGE
mariadb-controller-68584bd996-644vm   1/1     Running   0          6m23s
mariadb-server-0                      1/1     Running   0          6m23s
Done.
```

#### 로그 확인
```
citec@k1:~/osh$ kubectl -n openstack logs mariadb-server-0 -c mariadb -f
2025-05-08 09:05:12,191 - OpenStack-Helm Mariadb - INFO - This instance hostname: mariadb-server-0
2025-05-08 09:05:12,191 - OpenStack-Helm Mariadb - INFO - This instance IP address: 10.244.105.136
2025-05-08 09:05:12,200 - OpenStack-Helm Mariadb - INFO - Kubernetes API Version: v1.33.0
2025-05-08 09:05:12,210 - OpenStack-Helm Mariadb - INFO - The cluster is currently in "live" state.
```

**기술적 배경**: 
- MariaDB는 `StatefulSet`으로 배포되어 순서가 있는 안정적인 실행을 보장합니다.
- `helm dependency build`는 Helm 차트의 의존성을 다운로드합니다.

**확인 포인트**: 로그에서 `"live" state`가 보이면 MariaDB가 정상 작동 중입니다.

**보완 포인트**: 설치 중 파드가 `Pending` 상태라면 노드 리소스(CPU, 메모리)를 확인하거나 PVC 바인딩 문제를 점검하세요.

---

### RabbitMQ 설치

RabbitMQ는 서비스 간 메시지 전달을 담당합니다.

#### 설치
```
citec@k1:~/osh$ ./O05.rabbitmq.sh
>>> Initializing RabbitMQ install...
>>> Running helm dependency build...
>>> Installing RabbitMQ...
pod/rabbitmq-rabbitmq-0 condition met
pod/rabbitmq-rabbitmq-1 condition met
NAME                          READY   STATUS      RESTARTS   AGE
rabbitmq-rabbitmq-0           1/1     Running     0          2m59s
rabbitmq-rabbitmq-1           1/1     Running     0          2m59s
Done.
```

**기술적 배경**: RabbitMQ는 클러스터로 배포되어 장애 시에도 메시지 처리가 가능합니다.

**확인 포인트**: 두 파드가 `Running` 상태면 정상입니다.

---

### Memcached 설치

Memcached는 데이터를 빠르게 읽기 위한 캐싱 서비스입니다.

#### 설치
```
citec@k1:~/osh$ ./O06.memcached.sh
>>> Initializing Memcached install...
>>> Running helm dependency build...
>>> Installing Memcached...
pod/memcached-memcached-0 condition met
NAME                    READY   STATUS     RESTARTS   AGE
memcached-memcached-0   1/1     Running   0          6m23s
Done.
```

**기술적 배경**: Keystone 같은 서비스가 자주 사용하는 데이터를 캐싱해 성능을 높입니다.

**확인 포인트**: `1/1 Running`이면 성공입니다.

---

### Keystone 설치

Keystone은 OpenStack의 인증 서비스로, 모든 서비스의 "관리자" 역할을 합니다.

#### 설치
```
citec@k1:~/osh$ ./O07.keystone.sh
>>> Initializing Keystone install...
>>> Running helm dependency build...
>>> Installing Keystone...
pod/keystone-api-58b788dfcc-mcc9s condition met
NAME                              READY   STATUS      RESTARTS   AGE
keystone-api-58b788dfcc-mcc9s     1/1     Running     0          2m21s
keystone-bootstrap-z5qtl          0/1     Completed   0          13s
>>> Enter the domain name for Keystone (e.g., keystone.citec.com): keystone.citec.com
>>> Creating Ingress Resource for keystone-api...
ingress.networking.k8s.io/keystone-ingress unchanged
>>> Checking access to http://keystone.citec.com...
{"versions": {"values": [{"id": "v3.14", "status": "stable", "updated": "2020-04-07T00:00:00Z", "links": [{"rel": "self", "href": "http://keystone.citec.com/v3/"}], "media-types": [{"base": "application/json", "type": "application/vnd.openstack.identity-v3+json"}]}]}}
>>> Creating .openstackrc file...
>>> Setting alias for openstack command...
Done.
```

#### 명령어 확인
```
citec@k1:~/osh$ openstack service list
+----------------------------------+----------+----------+
| ID                               | Name     | Type     |
+----------------------------------+----------+----------+
| 3c55cedc9125431e8c21512e0a65474c | keystone | identity |
+----------------------------------+----------+----------+
```

**기술적 배경**: 
- `Ingress`는 외부에서 Keystone에 접근할 수 있게 합니다.
- `.openstackrc` 파일은 OpenStack CLI 명령어를 쉽게 실행하도록 환경 변수를 설정합니다.

**확인 포인트**: `keystone`이 서비스 목록에 보이면 정상입니다.

**보완 포인트**: 도메인 접근이 안 되면 `/etc/hosts`에 IP와 도메인 매핑을 확인하세요.

---

### Glance 설치

Glance는 가상 머신 이미지를 관리합니다.

#### Ceph 상태 확인
```
citec@k1:~/osh$ kceph ceph -s
  cluster:
    id:     603c8790-369b-40e8-b42e-751a1e771267
    health: HEALTH_OK
  services:
    mon: 3 daemons, quorum a,b,c (age 19h)
    mgr: a(active, since 19h)
    osd: 8 osds: 8 up (since 19h), 8 in (since 19h)
  data:
    pools:   2 pools, 33 pgs
    objects: 49 objects, 63 MiB
    usage:   1.0 GiB used, 143 GiB / 144 GiB avail
    pgs:     33 active+clean
```

#### 설치 1단계
```
citec@k1:~/osh$ ./O08.glance1.sh
>>> Initializing Glance install...
>>> Creating glance.images pool for Glance...
pool 'glance.images' created
>>> Registering images-rbd-keyring Secret...
secret/images-rbd-keyring created
>>> Creating ceph.conf and registering ceph-etc ConfigMap...
configmap/ceph-etc created
Done.
```

#### 설치 2단계
```
citec@k1:~/osh$ source O09.glance2.sh
>>> Creating Keystone user and service...
>>> Creating 'OpenStack Image Service'...
>>> Registering Endpoints...
>>> Running helm dependency build...
>>> Installing Glance...
pod/glance-api-b685c446f-bhhqk condition met
NAME                         READY   STATUS      RESTARTS   AGE
glance-api-b685c446f-bhhqk   1/1     Running     0          2m20s
glance-bootstrap-62gt4       0/1     Completed   0          25s
Done.
```

**기술적 배경**: Glance는 Ceph에 이미지를 저장하며, Keystone에 등록되어야 다른 서비스가 접근할 수 있습니다.

**확인 포인트**: `glance` 파드가 `Running` 상태면 성공입니다.

---

### Placement 설치

Placement는 리소스 할당을 관리합니다.

#### 설치
```
citec@k1:~/osh$ ./O10.placement.sh
>>> Initializing Placement install...
>>> Running helm dependency build...
>>> Installing Placement...
pod/placement-api-7db87dd987-9xr9x condition met
NAME                             READY   STATUS      RESTARTS   AGE
placement-api-7db87dd987-9xr9x   1/1     Running     0          3m59s
Done.
```

#### 확인
```
citec@k1:~/osh$ openstack service list
+----------------------------------+-----------+-----------+
| ID                               | Name      | Type      |
+----------------------------------+-----------+-----------+
| 267d629600984bf9800993a444ea3a3d | glance    | image     |
| e6f877a654ca4868b5543c2a5e4289f4 | keystone  | identity  |
| f84da38c433a46e4bbcfcba66c7bb78f | placement | placement |
+----------------------------------+-----------+-----------+
```

**확인 포인트**: `placement`가 목록에 보이면 성공입니다.

---

### OpenVswitch 설치

OpenVswitch는 가상 네트워크 스위치를 제공합니다.

#### 설치
```
citec@k1:~/osh$ ./O11.openvswitch.sh
>>> Initializing OpenVswitch install...
>>> Configuring label of nodes...
>>> Running helm dependency build...
>>> Installing OpenVswitch...
pod/openvswitch-cwdct condition met
NAME                READY   STATUS    RESTARTS   AGE
openvswitch-cwdct   2/2     Running   0          5m33s
Done.
```

#### 로그 확인
```
citec@k1:~/osh$ kubectl -n openstack logs openvswitch-cwdct -c openvswitch-db
2025-05-16T05:13:04Z|00001|ovsdb_server|INFO|ovsdb-server (Open vSwitch) 2.13.8
```

**확인 포인트**: `ovsdb-server` 메시지가 보이면 정상입니다.

---

### Libvirt 설치

Libvirt는 가상 머신을 실행하는 데 필요합니다.

#### 설치
```
citec@k1:~/osh$ ./O12.libvirt.sh
>>> Initializing Libvirt install...
>>> Checking Ceph status...
>>> Creating Ceph client key for client.openstack...
secret/ceph-client-openstack created
>>> Labeling nodes...
>>> Running helm dependency build...
>>> Installing Libvirt...
pod/libvirt-libvirt-default-8rglp condition met
NAME                            READY   STATUS    RESTARTS   AGE
libvirt-libvirt-default-8rglp   1/1     Running   0          72s
Done.
```

#### 확인
```
citec@k1:~/osh$ kubectl -n openstack exec -it libvirt-libvirt-default-8rglp -- /bin/bash
root@k2:/# virsh connect
root@k2:/# virsh list
 Id   Name   State
--------------------

root@k2:/# exit
```

**확인 포인트**: `virsh list`가 오류 없이 실행되면 성공입니다.

---

### Neutron 설치

Neutron은 가상 네트워크를 관리합니다.

#### 설치
```
citec@k1:~/osh$ ./O13.neutron.sh
>>> Initializing Neutron install...
>>> Running helm dependency build...
>>> Installing Neutron...
pod/neutron-server-9d6c4fd97-87ptw condition met
NAME                                       READY   STATUS      RESTARTS   AGE
neutron-server-9d6c4fd97-87ptw             1/1     Running     0          3m58s
Done.
```

#### 확인
```
citec@k1:~/osh$ openstack network agent list
+--------------------------------------+--------------------+------+-------------------+-------+-------+---------------------------+
| ID                                   | Agent Type         | Host | Availability Zone | Alive | State | Binary                    |
+--------------------------------------+--------------------+------+-------------------+-------+-------+---------------------------+
| 0547905c-ab16-47cc-8d23-658da32ea493 | Metadata agent     | k1   | None              | :-)   | UP    | neutron-metadata-agent    |
| 0d4c92bb-97f7-462d-8138-71dd7528c498 | DHCP agent         | k2   | nova              | :-)   | UP    | neutron-dhcp-agent        |
| 161949a0-03cc-4420-85bc-12d8e13efc33 | Open vSwitch agent | k2   | None              | :-)   | UP    | neutron-openvswitch-agent |
| ...                                  | ...                | ...  | ...               | ...   | ...   | ...                       |
+--------------------------------------+--------------------+------+-------------------+-------+-------+---------------------------+
```

**확인 포인트**: 모든 에이전트가 `UP` 상태면 성공입니다.

---

## 다이어그램

### OpenStack 서비스 네트워크 구성
```
[외부 네트워크]
     |
     | (Ingress: keystone.citec.com)
     v
+-------------+
|  Keystone   | <--- 인증 및 서비스 카탈로그
+-------------+
     |
     | (내부 통신)
     v
+-------------+    +-------------+    +-------------+
|  MariaDB    |    |  RabbitMQ   |    |  Memcached  |
+-------------+    +-------------+    +-------------+
     | 데이터         | 메시지          | 캐싱
     v              v                v
+-------------+    +-------------+    +-------------+
|  Glance     |    |  Placement  |    |  Neutron    |
+-------------+    +-------------+    +-------------+
     | 이미지         | 리소스          | 네트워크
     v              v                v
+-------------+    +-------------+    +-------------+
|  Nova       |    |  Cinder     |    |  Horizon    |
+-------------+    +-------------+    +-------------+
   VM 관리         볼륨 관리         대시보드
```

**설명**: Keystone은 외부와 내부를 연결하며, 인프라 서비스(MariaDB 등)는 모든 서비스의 기반입니다.

### 클러스터 아키텍처
```
+------------------------------------+
| Kubernetes 클러스터               |
|                                    |
|  +------------+   +------------+   |
|  | Master 노드|   | 워커 노드  |   |
|  | (k1,k2,k3) |   | (k2,k3,k4) |   |
|  +------------+   +------------+   |
|       |                 |          |
|       v                 v          |
|  +------------+   +------------+   |
|  | Rook-Ceph  |   | OpenStack  |   |
|  | 스토리지   |   | 서비스들   |   |
|  +------------+   +------------+   |
+------------------------------------+
```

**설명**: 마스터 노드는 클러스터를 관리하고, 워커 노드는 OpenStack 서비스와 Rook-Ceph를 실행합니다.

---

## 결론

이 가이드를 통해 OpenStack Helm으로 주요 서비스를 성공적으로 설치했습니다. 각 단계의 명령어와 출력은 그대로 유지했으며, 초보자도 이해할 수 있도록 기술적 배경을 쉽게 설명했습니다. 다음 단계에서는 Nova, Cinder, Horizon 등을 추가해 완전한 OpenStack 환경을 구축할 수 있습니다.
