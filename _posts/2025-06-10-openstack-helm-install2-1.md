---
title: "OpenStack Helm 설치 - 2부"
date: 2025-05-17
tags: [openstack, helm, kubernetes, ceph, ansible]
categories: [Howtos, OpenStack]
---


OpenStack-Helm은 Helm 차트를 사용하여 OpenStack 서비스를 Kubernetes에 배포한다. 각 서비스는 의존성을 가지므로, 설치 순서를 준수하고 `helm dependency build`를 통해 의존성을 해결해야 한다. 기본 설치 순서는 다음과 같다.

1. **인프라 서비스**: MariaDB, RabbitMQ, Memcached
2. **코어 서비스**: Keystone
3. **추가 서비스**: Glance, Placement, Nova, Neutron, Cinder, Horizon, Heat

### 설치 순서가 중요한 이유

- **의존성**: 예를 들어, Nova는 Keystone, Glance, Neutron이 설치되어 있어야 작동한다.
- **기본 인프라**: MariaDB와 RabbitMQ는 거의 모든 서비스가 사용하는 필수 구성 요소이므로 가장 먼저 설치해야 한다.
- **서비스 등록**: Keystone이 설치되어야 다른 서비스들이 인증 및 등록을 할 수 있다.

## 상세 설치 과정

설치 과정에서 필요한 내용은 대부분 스크립트로 작성했으므로, 이를 단계별로 수행하여 진행한다.

### Rook-Ceph 스토리지 설정
OpenStack 서비스는 데이터를 저장하기 위해 Rook-Ceph를 사용한다.

먼저 Ceph 상태를 확인하자.
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

#### StorageClass 생성 및 풀 생성
`rook-ceph-block` StorageClass를 생성하고, `replicapool` 풀을 생성한 후 이를 초기화한다.

```
citec@k1:~/osh$ ./O01.storageclass.sh
>>> Creating rook-ceph-block StorageClass...
storageclass.storage.k8s.io/rook-ceph-block unchanged
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

### CoreDNS RBAC 권한 설정
CoreDNS가 Kubernetes 클러스터에서 제대로 작동하려면 API 서버에서 특정 리소스(`endpoints, services, pods, namespaces, endpointslices 등)를 조회할 수 있는 권한이 필요하다. 이를 위해 RBAC(Role-Based Access Control)를 설정해야 하며, 아래 단계에 따라 ClusterRole과 ClusterRoleBinding을 생성하고 적용한다.

```
citec@k1:~/osh$ ./O02.coredns-rbac.sh
>>> Defining RBAC for CoreDNS...
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: coredns
rules:
- apiGroups: [""]
  resources: ["endpoints", "services", "pods", "namespaces"]
  verbs: ["list", "watch"]
- apiGroups: ["discovery.k8s.io"]
  resources: ["endpointslices"]
  verbs: ["list", "watch"]
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: coredns
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: coredns
subjects:
- kind: ServiceAccount
  name: coredns
  namespace: kube-system
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
Labels:       <none>
Annotations:  <none>
PolicyRule:
  Resources                        Non-Resource URLs  Resource Names  Verbs
  ---------                        -----------------  --------------  -----
  endpoints                        []                 []              [list watch]
  namespaces                       []                 []              [list watch]
  pods                             []                 []              [list watch]
  services                         []                 []              [list watch]
  endpointslices.discovery.k8s.io  []                 []              [list watch]

citec@k1:~/osh$ kubectl describe clusterrolebinding coredns
Name:         coredns
Labels:       <none>
Annotations:  <none>
Role:
  Kind:  ClusterRole
  Name:  coredns
Subjects:
  Kind            Name     Namespace
  ----            ----     ---------
  ServiceAccount  coredns  kube-system
```

### Rook-Ceph 모니터 이름 변경
Rook은 기본적으로 모니터 노드의 수를 유지하려고 하며, 장애 발생 시 자동으로 새로운 모니터를 생성한다. 이 과정에서 이름이 순차적으로 변경될 수 있다. Rook-Ceph 모니터 이름이 변경될 때마다 이를 참조하는 ConfigMap을 수동으로 업데이트해야 하는데, 이를 자동화하는 스크립트 작성이 필요하다.

#### 업데이트 스크립트 등록
Rook-Ceph 모니터 정보가 `ceph-etc` ConfigMap에 등록되어있다고 가정한다. (본 문서의 설정이다.)

```
citec@k1:~/osh$ ./O03.rook-ceph-mon-update.sh
>>> Registering for automated updates to rook-ceph monitor information...
apiVersion: batch/v1
kind: CronJob
metadata:
  name: update-ceph-config
  namespace: openstack
spec:
  schedule: "0 0 * * *"  # 매일 자정 실행
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: update-ceph-config
            image: bitnami/kubectl:latest  # kubectl이 포함된 이미지
            command: ["/bin/sh", "-c", "/scripts/update-ceph-config.sh"]
            volumeMounts:
            - name: scripts
              mountPath: /scripts
          volumes:
          - name: scripts
            configMap:
              name: update-ceph-config-script
          restartPolicy: OnFailure
configmap/update-ceph-config-script created

Done.
```

### MariaDB 설치
MariaDB는 OpenStack의 데이터베이스 역할을 하며, 가장 먼저 설치해야 한다.

#### 설치

```
citec@k1:~/osh$ ./O04.mariadb.sh
>>> Initializing MariaDB install...
...
>>> Running helm dependency build...
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "metallb" chart repository
...Successfully got an update from the "rook-release" chart repository
...Successfully got an update from the "ingress-nginx" chart repository
Update Complete. ⎈Happy Helming!⎈
Saving 1 charts
Deleting outdated charts
>>> Configuring label of nodes...
node/k1 labeled
node/k2 labeled
node/k3 labeled
>>> Installing MariaDB...
Release "mariadb" does not exist. Installing it now.
NAME: mariadb
LAST DEPLOYED: Fri May 23 11:59:00 2025
NAMESPACE: openstack
STATUS: deployed
REVISION: 1
pod/mariadb-controller-68584bd996-644vm condition met
pod/mariadb-server-0 condition met
NAME                                  READY   STATUS    RESTARTS   AGE
mariadb-controller-68584bd996-644vm   1/1     Running   0          6m23s
mariadb-server-0                      1/1     Running   0          6m23s

Done.
```

설치가 진행되는 동안 다른 창에서 아래의 명령으로 파드의 상태를 확인할 수 있다.

```
citec@k1:~/osh$ watch kubectl -n openstack get pods -l application=mariadb

Every 2.0s: kubectl -n openstack get pods -l application=mariadb                                                        k1: Fri May 23 12:00:40 2025

NAME                                  READY   STATUS     RESTARTS   AGE
mariadb-controller-68584bd996-644vm   0/1     Init:0/1   0          99s
mariadb-server-0                      0/1     Init:0/2   0          99s
```

#### 로그 실시간 확인 (`-f` 옵션)
```
citec@k1:~/osh$ kubectl -n openstack logs mariadb-server-0 -c mariadb -f
2025-05-08 09:05:12,191 - OpenStack-Helm Mariadb - INFO - This instance hostname: mariadb-server-0
2025-05-08 09:05:12,191 - OpenStack-Helm Mariadb - INFO - This instance IP address: 10.244.105.136
2025-05-08 09:05:12,191 - OpenStack-Helm Mariadb - INFO - This instance number: 0
2025-05-08 09:05:12,200 - OpenStack-Helm Mariadb - INFO - Kubernetes API Version: v1.33.0
2025-05-08 09:05:12,200 - OpenStack-Helm Mariadb - INFO - Will use "mariadb-mariadb-state" configmap for cluster state info
2025-05-08 09:05:12,201 - OpenStack-Helm Mariadb - INFO - Getting cluster state
2025-05-08 09:05:12,210 - OpenStack-Helm Mariadb - INFO - The cluster is currently in "live" state.
2025-05-08 09:05:12,210 - OpenStack-Helm Mariadb - INFO - Getting cluster state
2025-05-08 09:05:12,213 - OpenStack-Helm Mariadb - INFO - The cluster is currently in "live" state.
2025-05-08 09:05:12,213 - OpenStack-Helm Mariadb - INFO - Getting cluster state
```

#### 설치 과정에서의 오류 

아래 `mariadb-server-0` 파드의 이벤트에 보이는 것처럼 초기 PVC 바인딩 지연과 Readiness Probe 실패가 있을 수 있으나 데이터베이스 초기화 과정에서 종종 발생할 수 있는 문제이므로, 시간을 두고 기다려보거나 재설치를 시도해본다.

```
citec@k1:~/osh$ kubectl -n openstack describe pod mariadb-server-0
...
Events:
  Type     Reason                  Age                From                     Message
  ----     ------                  ----               ----                     -------
  Warning  FailedScheduling        15m (x5 over 15m)  default-scheduler        0/4 nodes are available: pod has unbound immediate PersistentVolumeClaims. preemption: 0/4 nodes are available: 4 Preemption is not helpful for scheduling.
...
  Warning  Unhealthy               13m (x2 over 14m)  kubelet                  Readiness probe failed: Select from mysql failed
  Warning  Unhealthy               13m                kubelet                  Readiness probe failed: WSREP says the node can not receive queries
```

### RabbitMQ 설치
RabbitMQ는 서비스 간 메시지 브로커로 사용된다.

#### 설치

```
citec@k1:~/osh$ ./O05.rabbitmq.sh
>>> Initializing RabbitMQ install...
...
>>> Running helm dependency build...
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "metallb" chart repository
...Successfully got an update from the "ingress-nginx" chart repository
...Successfully got an update from the "rook-release" chart repository
Update Complete. ⎈Happy Helming!⎈
Saving 1 charts
Deleting outdated charts
>>> Installing RabbitMQ...
Release "rabbitmq" does not exist. Installing it now.
NAME: rabbitmq
LAST DEPLOYED: Tue Jun 10 12:42:40 2025
NAMESPACE: openstack
STATUS: deployed
REVISION: 1
./O05.rabbitmq.sh: line 19: --set: command not found
pod/rabbitmq-rabbitmq-0 condition met
pod/rabbitmq-rabbitmq-1 condition met
NAME                          READY   STATUS      RESTARTS   AGE
rabbitmq-cluster-wait-lmwbq   0/1     Completed   0          2m59s
rabbitmq-rabbitmq-0           1/1     Running     0          2m59s
rabbitmq-rabbitmq-1           1/1     Running     0          2m59s
Defaulted container "rabbitmq" out of: rabbitmq, init (init), rabbitmq-password (init), rabbitmq-cookie (init), rabbitmq-perms (init)
RabbitMQ version: 3.13.0
RabbitMQ release series support status: supported
Node name: rabbit@rabbitmq-rabbitmq-0.rabbitmq.openstack.svc.cluster.local
Node data directory: /var/lib/rabbitmq/mnesia/rabbit@rabbitmq-rabbitmq-0.rabbitmq.openstack.svc.cluster.local

Done.
```

### Memcached 설치
캐싱 서비스로, Keystone과 같은 서비스의 성능을 향상시킨다.

#### 설치

```
citec@k1:~/osh$ ./O06.memcached.sh
>>> Initializing Memcached install...
...
>>> Running helm dependency build...
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "ingress-nginx" chart repository
...Successfully got an update from the "metallb" chart repository
...Successfully got an update from the "rook-release" chart repository
Update Complete. ⎈Happy Helming!⎈
Saving 1 charts
Deleting outdated charts
>>> Installing Memcached...
Release "memcached" does not exist. Installing it now.
NAME: memcached
LAST DEPLOYED: Fri May 23 12:26:41 2025
NAMESPACE: openstack
STATUS: deployed
REVISION: 1
TEST SUITE: None
pod/memcached-memcached-0 condition met
NAME                    READY   STATUS     RESTARTS   AGE
memcached-memcached-0   0/1     Init:0/1   0          0s

Done.
```

### Keystone (Identity Service) 설치
OpenStack의 인증 및 서비스 카탈로그를 관리하는 핵심 서비스이다. 다른 모든 서비스가 Keystone에 등록되어야 하므로 이 단계에서 설치한다.

#### 설치

스크립트를 수행하면, Keystone의 도메인명을 입력해야 한다. 이 문서에서는 `keystone.citec.com`으로 입력한다.

```
citec@k1:~/osh$ ./O07.keystone.sh
>>> Initializing Keystone install...
...
>>> Running helm dependency build...
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "metallb" chart repository
...Successfully got an update from the "ingress-nginx" chart repository
...Successfully got an update from the "rook-release" chart repository
Update Complete. ⎈Happy Helming!⎈
Saving 1 charts
Deleting outdated charts
>>> Installing Keystone...
Release "keystone" does not exist. Installing it now.
NAME: keystone
LAST DEPLOYED: Mon May 26 15:40:47 2025
NAMESPACE: openstack
STATUS: deployed
REVISION: 1
pod/keystone-api-58b788dfcc-mcc9s condition met
NAME                              READY   STATUS      RESTARTS   AGE
keystone-api-58b788dfcc-mcc9s     1/1     Running     0          2m21s
keystone-bootstrap-z5qtl          0/1     Completed   0          13s
keystone-credential-setup-mn9x7   0/1     Completed   0          2m20s
keystone-db-init-qpcm8            0/1     Completed   0          2m10s
keystone-db-sync-v6wv6            0/1     Completed   0          111s
keystone-domain-manage-79d2t      0/1     Completed   0          90s
keystone-fernet-setup-hl7xs       0/1     Completed   0          2m2s
keystone-rabbit-init-jcf47        0/1     Completed   0          95s
>>> Enter the domain name for Keystone (e.g., keystone.citec.com): keystone.citec.com (도메인 입력)
>>> Creating Ingress Resource for keystone-api...
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: keystone-ingress
  namespace: openstack
spec:
  ingressClassName: nginx
  rules:
  - host: keystone.citec.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: keystone-api
            port:
              number: 5000
ingress.networking.k8s.io/keystone-ingress unchanged
NAME           TYPE        CLUSTER-IP    EXTERNAL-IP   PORT(S)    AGE
keystone-api   ClusterIP   10.96.72.10   <none>        5000/TCP   2m46s
>>> Editing DaemonSet to use hostNetwork and hostPort...
daemonset.apps/ingress-nginx-openstack-controller patched (no change)
>>> Waiting for pods to restart...
daemon set "ingress-nginx-openstack-controller" successfully rolled out
>>> Checking if port 80 is listening on node k1...
tcp        0      0 0.0.0.0:80              0.0.0.0:*               LISTEN      961850/nginx: maste
tcp        0      0 0.0.0.0:80              0.0.0.0:*               LISTEN      961850/nginx: maste
tcp        0      0 0.0.0.0:80              0.0.0.0:*               LISTEN      961850/nginx: maste
tcp        0      0 0.0.0.0:80              0.0.0.0:*               LISTEN      961850/nginx: maste
>>> Adding keystone.citec.com to /etc/hosts with IP 172.16.2.149...
172.16.2.149 keystone.citec.com
>>> Checking access to http://keystone.citec.com...
{"versions": {"values": [{"id": "v3.14", "status": "stable", "updated": "2020-04-07T00:00:00Z", "links": [{"rel": "self", "href": "http://keystone.citec.com/v3/"}], "media-types": [{"base": "application/json", "type": "application/vnd.openstack.identity-v3+json"}]}]}}>>> Creating .openstackrc file...
export OS_AUTH_URL=http://keystone.citec.com/v3
export OS_USERNAME=admin
export OS_PASSWORD=password
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=default
export OS_PROJECT_DOMAIN_NAME=default
>>> Setting alias for openstack command...
alias openstack='source ~/.openstackrc && docker run --network host   -e OS_AUTH_URL="$OS_AUTH_URL"   -e OS_USERNAME="$OS_USERNAME"   -e OS_PASSWORD="$OS_PASSWORD"   -e OS_PROJECT_NAME="$OS_PROJECT_NAME"   -e OS_USER_DOMAIN_NAME="$OS_USER_DOMAIN_NAME"   -e OS_PROJECT_DOMAIN_NAME="$OS_PROJECT_DOMAIN_NAME"   quay.io/airshipit/openstack-client:2024.2 openstack'

Done.
```

#### `openstack` 명령어 확인 

`openstack` 명령어가 제대로 수행되는지 확인한다.

```
citec@k1:~/osh$ openstack service list
Unable to find image 'quay.io/airshipit/openstack-client:2024.2' locally
2024.2: Pulling from airshipit/openstack-client
7478e0ac0f23: Pull complete
15f0d6b9775f: Pull complete
1de21cdae6fb: Pull complete
Digest: sha256:e293799048ac51745aa752783c20740dd9b708805423ad8059dec2439b598949
Status: Downloaded newer image for quay.io/airshipit/openstack-client:2024.2
+----------------------------------+----------+----------+
| ID                               | Name     | Type     |
+----------------------------------+----------+----------+
| 3c55cedc9125431e8c21512e0a65474c | keystone | identity |
+----------------------------------+----------+----------+
```

### Glance (Image Service)
가상 머신 이미지를 관리하는 서비스로, Nova가 VM을 생성할 때 필요한 이미지를 제공한다.

#### Ceph 상태 확인
Glance는 Ceph 스토리지를 사용하므로, 설치 전에 상태를 확인한다.

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
Error from server (NotFound): secrets "images-rbd-keyring" not found
Error from server (NotFound): secrets "ceph-admin-keyring" not found
Error from server (NotFound): configmaps "ceph-etc" not found
No resources found in openstack namespace.
No resources found in openstack namespace.
No resources found in openstack namespace.
No resources found in openstack namespace.
No resources found in openstack namespace.
Warning: Immediate deletion does not wait for confirmation that the running resource has been terminated. The resource may continue to run on the cluster indefinitely.
No resources found
No resources found
No resources found
No resources found
No resources found
No resources found
pool 'glance.images' does not exist
>>> Creating glance.images pool for Glance...
pool 'glance.images' created
.mgr
replicapool
glance.images
>>> Checking glance.images pool...
Total Images: 0
Total Snapshots: 0
Provisioned Size: 0 B
>>> Creating Ceph user: client.glance...
tar: Removing leading `/' from member names
>>> Getting information for client.admin...
>>> Registering images-rbd-keyring Secret...
secret/images-rbd-keyring created
NAME                 TYPE     DATA   AGE
images-rbd-keyring   Opaque   1      0s
>>> Updating images-rbd-keyring Secret...
Keys do not match. Updating Secret...
secret/images-rbd-keyring patched
Secret updated successfully.
>>> Registering ceph-admin-keyring Secret...
secret/ceph-admin-keyring created
NAME                 TYPE     DATA   AGE
ceph-admin-keyring   Opaque   1      0s
>>> Checking user and keyring...
[client.glance]
        key = AQC6HDVo1Q4RARAA1N1mimT6deiX2Q+NYi6yLw==
        caps mon = "allow r"
        caps osd = "allow class-read object_prefix rbd_children, allow rwx pool=glance.images"
[client.admin]
        key = AQDeEDVonhWiCRAAJkcSQcpvCID7hD8xw8F0lw==
        caps mds = "allow *"
        caps mgr = "allow *"
        caps mon = "allow *"
        caps osd = "allow *"
>>> Creating ceph.conf and registering ceph-etc ConfigMap...
[global]
fsid = 603c8790-369b-40e8-b42e-751a1e771267
mon_host = rook-ceph-mon-b.rook-ceph.svc.cluster.local:6789,rook-ceph-mon-c.rook-ceph.svc.cluster.local:6789,rook-ceph-mon-d.rook-ceph.svc.cluster.local:6789
ceph.conf 파일이 생성되었습니다.

[global]
fsid = 603c8790-369b-40e8-b42e-751a1e771267
mon_host = rook-ceph-mon-a.rook-ceph.svc.cluster.local:6789,rook-ceph-mon-b.rook-ceph.svc.cluster.local:6789,rook-ceph-mon-c.rook-ceph.svc.cluster.local:6789
configmap/ceph-etc created
configmap/ceph-etc patched
apiVersion: v1
data:
  ceph.client.admin.keyring: key = AQDeEDVonhWiCRAAJkcSQcpvCID7hD8xw8F0lw==
  ceph.conf: |
    [global]
    fsid = 603c8790-369b-40e8-b42e-751a1e771267
    mon_host = rook-ceph-mon-a.rook-ceph.svc.cluster.local:6789,rook-ceph-mon-b.rook-ceph.svc.cluster.local:6789,rook-ceph-mon-c.rook-ceph.svc.cluster.local:6789
kind: ConfigMap
metadata:
  creationTimestamp: "2025-05-27T02:00:33Z"
  name: ceph-etc
  namespace: openstack
  resourceVersion: "16964"
  uid: 90730525-bf65-4aa9-b454-dc1e68b7ed97

Done.
```

#### 설치 2단계

스크립트 실행은 반드시 `source` 명령을 이용해서 수행한다. 그리고, 처음 실행하는 것이라면 초반에 초기화 관련하여 오류가 발생할 수 있으나 무시할 수 있다.

```
citec@k1:~/osh$ source O09.glance2.sh
>>> Creating Keystone user and service...
+---------------------+----------------------------------+
| Field               | Value                            |
+---------------------+----------------------------------+
| default_project_id  | None                             |
| domain_id           | default                          |
| email               | None                             |
| enabled             | True                             |
| id                  | d90289e8ce914013b406ca024a62d441 |
| name                | glance                           |
| description         | None                             |
| password_expires_at | None                             |
+---------------------+----------------------------------+
+----------------------------------+--------+
| ID                               | Name   |
+----------------------------------+--------+
| e3bdd1f693014a079dd9e4f1e6aee63c | admin  |
| d90289e8ce914013b406ca024a62d441 | glance |
+----------------------------------+--------+
+-------------+----------------------------------+
| Field       | Value                            |
+-------------+----------------------------------+
| description | Service Project                  |
| domain_id   | default                          |
| enabled     | True                             |
| id          | 0529c7d2b2bc443cad5b3dbd0e488593 |
| is_domain   | False                            |
| name        | service                          |
| options     | {}                               |
| parent_id   | default                          |
| tags        | []                               |
+-------------+----------------------------------+
+----------------------------------+---------+
| ID                               | Name    |
+----------------------------------+---------+
| 0529c7d2b2bc443cad5b3dbd0e488593 | service |
| fd6295ada7714d9ba5bf2d72b632033c | admin   |
+----------------------------------+---------+
+----------------------------------+----------------------------------+-------+----------------------------------+--------+--------+-----------+
| Role                             | User                             | Group | Project                          | Domain | System | Inherited |
+----------------------------------+----------------------------------+-------+----------------------------------+--------+--------+-----------+
| 8dfcc25dd238439da4e2a29b7d03daa1 | d90289e8ce914013b406ca024a62d441 |       | 0529c7d2b2bc443cad5b3dbd0e488593 |        |        | False     |
+----------------------------------+----------------------------------+-------+----------------------------------+--------+--------+-----------+
>>> Creating 'OpenStack Image Service'...
+-------------+----------------------------------+
| Field       | Value                            |
+-------------+----------------------------------+
| id          | 0ff10ecc1f3848548883fdad7a9572be |
| name        | glance                           |
| type        | image                            |
| enabled     | True                             |
| description | OpenStack Image Service          |
+-------------+----------------------------------+
+----------------------------------+----------+----------+
| ID                               | Name     | Type     |
+----------------------------------+----------+----------+
| 0ff10ecc1f3848548883fdad7a9572be | glance   | image    |
| c2a184c1dd5e4080b568cd088a8fe48d | keystone | identity |
+----------------------------------+----------+----------+
>>> Registering Endpoints...
+--------------+----------------------------------------------------+
| Field        | Value                                              |
+--------------+----------------------------------------------------+
| enabled      | True                                               |
| id           | 30218ad951e14b73a2fc7af391cd773f                   |
| interface    | public                                             |
| region       | RegionOne                                          |
| region_id    | RegionOne                                          |
| service_id   | 0ff10ecc1f3848548883fdad7a9572be                   |
| service_name | glance                                             |
| service_type | image                                              |
| url          | http://glance-api.openstack.svc.cluster.local:9292 |
+--------------+----------------------------------------------------+
+--------------+----------------------------------------------------+
| Field        | Value                                              |
+--------------+----------------------------------------------------+
| enabled      | True                                               |
| id           | 06dd841a8bc84d1eba739618bd259a75                   |
| interface    | internal                                           |
| region       | RegionOne                                          |
| region_id    | RegionOne                                          |
| service_id   | 0ff10ecc1f3848548883fdad7a9572be                   |
| service_name | glance                                             |
| service_type | image                                              |
| url          | http://glance-api.openstack.svc.cluster.local:9292 |
+--------------+----------------------------------------------------+
+--------------+----------------------------------------------------+
| Field        | Value                                              |
+--------------+----------------------------------------------------+
| enabled      | True                                               |
| id           | 4f5301f4f6f84a0b800218590546b142                   |
| interface    | admin                                              |
| region       | RegionOne                                          |
| region_id    | RegionOne                                          |
| service_id   | 0ff10ecc1f3848548883fdad7a9572be                   |
| service_name | glance                                             |
| service_type | image                                              |
| url          | http://glance-api.openstack.svc.cluster.local:9292 |
+--------------+----------------------------------------------------+
+----------------------------------+-----------+--------------+--------------+---------+-----------+---------------------------------------------------------+
| ID                               | Region    | Service Name | Service Type | Enabled | Interface | URL                                                     |
+----------------------------------+-----------+--------------+--------------+---------+-----------+---------------------------------------------------------+
| 06dd841a8bc84d1eba739618bd259a75 | RegionOne | glance       | image        | True    | internal  | http://glance-api.openstack.svc.cluster.local:9292      |
| 1d6d2e25c75a40b59a2079a9b021e3be | RegionOne | keystone     | identity     | True    | admin     | http://keystone.openstack.svc.cluster.local/v3          |
| 30218ad951e14b73a2fc7af391cd773f | RegionOne | glance       | image        | True    | public    | http://glance-api.openstack.svc.cluster.local:9292      |
| 3038da8b37554afdbdbfeefab5f275dc | RegionOne | keystone     | identity     | True    | public    | http://keystone.openstack.svc.cluster.local/v3          |
| 438de312b3d24bc2a02ed4e9cf7ac4d2 | RegionOne | keystone     | identity     | True    | internal  | http://keystone-api.openstack.svc.cluster.local:5000/v3 |
| 4f5301f4f6f84a0b800218590546b142 | RegionOne | glance       | image        | True    | admin     | http://glance-api.openstack.svc.cluster.local:9292      |
+----------------------------------+-----------+--------------+--------------+---------+-----------+---------------------------------------------------------+
>>> Adding DNS Access Allow Policy...
networkpolicy.networking.k8s.io/allow-dns unchanged
networkpolicy.networking.k8s.io/allow-api-server unchanged
networkpolicy.networking.k8s.io/allow-all-egress created
>>> Running helm dependency build...
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "ingress-nginx" chart repository
...Successfully got an update from the "metallb" chart repository
...Successfully got an update from the "rook-release" chart repository
Update Complete. ⎈Happy Helming!⎈
Saving 1 charts
Deleting outdated charts
>>> Installing Glance...
Release "glance" does not exist. Installing it now.
NAME: glance
LAST DEPLOYED: Thu Jun  5 17:55:52 2025
NAMESPACE: openstack
STATUS: deployed
REVISION: 1
pod/glance-api-b685c446f-bhhqk condition met
NAME                         READY   STATUS      RESTARTS   AGE
glance-api-b685c446f-bhhqk   1/1     Running     0          2m20s
glance-bootstrap-62gt4       0/1     Completed   0          25s
glance-db-init-4bvpg         0/1     Completed   0          2m20s
glance-db-sync-gcnpm         0/1     Completed   0          2m13s
glance-ks-endpoints-d9grh    0/3     Completed   0          102s
glance-ks-service-wrhn2      0/1     Completed   0          114s
glance-ks-user-vzp7j         0/1     Completed   0          74s
glance-metadefs-load-b654g   0/1     Completed   0          49s
glance-rabbit-init-l9b8h     0/1     Completed   0          2m1s
glance-storage-init-mvg8b    0/1     Completed   0          39s
+--------------------------------------+---------------------+--------+
| ID                                   | Name                | Status |
+--------------------------------------+---------------------+--------+
| 1479d51b-22c3-4999-b9d4-94a8f10268c9 | Cirros 0.6.2 64-bit | active |
+--------------------------------------+---------------------+--------+

Done.
```


### Placement 

리소스 추적 및 할당을 관리하며, Nova가 인스턴스를 배치할 때 사용된다.

#### 설치
```
citec@k1:~/osh$ ./O10.placement.sh
>>> Initializing Placement install...
No resources found
No resources found
Error: uninstall: Release not loaded: placement: release: not found
>>> Running helm dependency build...
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "metallb" chart repository
...Successfully got an update from the "ingress-nginx" chart repository
...Successfully got an update from the "rook-release" chart repository
Update Complete. ⎈Happy Helming!⎈
Saving 1 charts
Deleting outdated charts
>>> Installing Placement...
Release "placement" does not exist. Installing it now.
NAME: placement
LAST DEPLOYED: Thu Jun  5 18:02:12 2025
NAMESPACE: openstack
STATUS: deployed
REVISION: 1
TEST SUITE: None
pod/placement-api-7db87dd987-9xr9x condition met
NAME                             READY   STATUS      RESTARTS   AGE
placement-api-7db87dd987-9xr9x   1/1     Running     0          3m59s
placement-db-init-gcj5d          0/1     Completed   0          3m59s
placement-db-sync-wblm6          0/1     Completed   0          3m51s
placement-ks-endpoints-smfmt     0/3     Completed   0          85s
placement-ks-service-7vh89       0/1     Completed   0          2m19s
placement-ks-user-g9tmc          0/1     Completed   0          115s

Done.
```

`placement` 서비스가 Openstack의 Keystone에 제대로 등록되어있는지, Placement API 엔드포인트가 올바르게 설정되었는지, Placement API가 정상적으로 응답하는지 확인한다.
```
citec@k1:~/osh$ openstack service list
+----------------------------------+-----------+-----------+
| ID                               | Name      | Type      |
+----------------------------------+-----------+-----------+
| 267d629600984bf9800993a444ea3a3d | glance    | image     |
| e6f877a654ca4868b5543c2a5e4289f4 | keystone  | identity  |
| f84da38c433a46e4bbcfcba66c7bb78f | placement | placement |
+----------------------------------+-----------+-----------+

citec@k1:~/osh$ openstack catalog show placement
+-----------+--------------------------------------------------------------------+
| Field     | Value                                                              |
+-----------+--------------------------------------------------------------------+
| endpoints | RegionOne                                                          |
|           |   public: http://placement.openstack.svc.cluster.local/            |
|           | RegionOne                                                          |
|           |   admin: http://placement-api.openstack.svc.cluster.local:8778/    |
|           | RegionOne                                                          |
|           |   internal: http://placement-api.openstack.svc.cluster.local:8778/ |
|           |                                                                    |
| id        | f84da38c433a46e4bbcfcba66c7bb78f                                   |
| name      | placement                                                          |
| type      | placement                                                          |
+-----------+--------------------------------------------------------------------+

citec@k1:~/osh$ export PLACEMENT_ENDPOINT="http://placement.openstack.svc.cluster.local/"
citec@k1:~/osh$ curl -i -H "X-Auth-Token: $OS_AUTH_TOKEN" $PLACEMENT_ENDPOINT
HTTP/1.1 200 OK
Date: Tue, 13 May 2025 03:56:53 GMT
Content-Type: application/json
Content-Length: 136
Connection: keep-alive
openstack-api-version: placement 1.0
vary: openstack-api-version
x-openstack-request-id: req-858258dd-59aa-44ec-ac32-86da8b6ad689

{"versions": [{"id": "v1.0", "max_version": "1.39", "min_version": "1.0", "status": "CURRENT", "links": [{"rel": "self", "href": ""}]}]}
```

### OpenVswitch 
OpenStack의 네트워킹 서비스(Neutron)에서 가상 네트워크 스위치를 제공하는 핵심 인프라 구성 요소이다.

#### citec@k1:~/osh$ ./O11.openvswitch.sh
>>> Initializing OpenVswitch install...
Warning: Immediate deletion does not wait for confirmation that the running resource has been terminated. The resource may continue to run on the cluster indefinitely.
pod "openvswitch-4q82r" force deleted
pod "openvswitch-bbf2j" force deleted
pod "openvswitch-nxwz6" force deleted
pod "openvswitch-zt7hf" force deleted
release "openvswitch" uninstalled
ovs-vsctl: unix:/var/run/openvswitch/db.sock: database connection failed (No such file or directory)
ovs-vsctl: unix:/var/run/openvswitch/db.sock: database connection failed (No such file or directory)
ovs-vsctl: unix:/var/run/openvswitch/db.sock: database connection failed (No such file or directory)
ovs-vsctl: unix:/var/run/openvswitch/db.sock: database connection failed (No such file or directory)
>>> Configuring label of nodes...
node/k1 not labeled
node/k2 not labeled
node/k3 not labeled
node/k4 not labeled
>>> Running helm dependency build...
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "metallb" chart repository
...Successfully got an update from the "ingress-nginx" chart repository
...Successfully got an update from the "rook-release" chart repository
Update Complete. ⎈Happy Helming!⎈
Saving 1 charts
Deleting outdated charts
>>> Installing OpenVswitch...
Release "openvswitch" does not exist. Installing it now.
NAME: openvswitch
LAST DEPLOYED: Mon Jun  9 12:57:34 2025
NAMESPACE: openstack
STATUS: deployed
REVISION: 1
TEST SUITE: None
pod/openvswitch-cwdct condition met
pod/openvswitch-kx8sv condition met
pod/openvswitch-lv7hz condition met
pod/openvswitch-zdcnk condition met
NAME                READY   STATUS    RESTARTS   AGE
openvswitch-cwdct   2/2     Running   0          5m33s
openvswitch-kx8sv   2/2     Running   0          5m33s
openvswitch-lv7hz   2/2     Running   0          5m33s
openvswitch-zdcnk   2/2     Running   0          5m33s
>>> Checking br-ex bridge of each node...
057d4241-4d6b-46b3-8797-e7f280f1f802
    Bridge br-ex
        Port br-ex
            Interface br-ex
                type: internal
b2d44a74-7767-4913-a7a9-c9cc2a1b6b55
    Bridge br-ex
        Port br-ex
            Interface br-ex
                type: internal
1edc5c9b-c469-45b0-889f-f098866dc808
    Bridge br-ex
        Port br-ex
            Interface br-ex
                type: internal
fd707d9d-95d7-4922-93db-f6a8b74b797e
    Bridge br-ex
        Port br-ex
            Interface br-ex
                type: internal

Done.
```

openvswitch가 정상적으로 동작하는 것을 확인하기 위해서 아래와 같이 로그를 확인한다. 각 노드마다 openvswitch 파드가 동작 중이니, 모든 노드의 파드 로그를 확인하는 것이 확실하다.

먼저, `openvswitch-db` 컨테이너의 동작 상태를 확인한다. 로그의 내용 중 "Connection reset by peer" 오류는 Kubernetes 프로브가 주기적으로 연결을 열고 닫는 과정에서 발생하는 정상적인 현상이다. "ovsdb_server|INFO|ovsdb-server (Open vSwitch) 2.13.8" 메시지 출력 이후 다른 오류가 없다면 정상 동작 중으로 판단한다.
```
citec@k1:~/osh$ kubectl -n openstack logs openvswitch-crt4k -c openvswitch-db
2025-05-16T05:13:04Z|00001|ovsdb_server|INFO|ovsdb-server (Open vSwitch) 2.13.8
2025-05-16T05:13:14Z|00002|memory|INFO|10992 kB peak resident set size after 10.0 seconds
2025-05-16T05:13:14Z|00003|memory|INFO|cells:122 monitors:4 sessions:2
2025-05-16T05:13:35Z|00004|jsonrpc|WARN|unix#6: receive error: Connection reset by peer
2025-05-16T05:13:35Z|00005|reconnect|WARN|unix#6: connection dropped (Connection reset by peer)
2025-05-16T05:14:05Z|00006|jsonrpc|WARN|unix#7: send error: Broken pipe
2025-05-16T05:14:05Z|00007|reconnect|WARN|unix#7: connection dropped (Broken pipe)
2025-05-16T05:14:35Z|00008|jsonrpc|WARN|unix#8: receive error: Connection reset by peer
2025-05-16T05:14:35Z|00009|reconnect|WARN|unix#8: connection dropped (Connection reset by peer)
2025-05-16T05:17:05Z|00010|jsonrpc|WARN|unix#17: receive error: Connection reset by peer
2025-05-16T05:17:05Z|00011|reconnect|WARN|unix#17: connection dropped (Connection reset by peer)
```
다음은 `openvswitch-vswitchd` 컨테이너의 로그를 확인한다.
```
citec@k1:~/osh$ kubectl -n openstack logs openvswitch-crt4k -c openvswitch-vswitchd
2025-05-16T05:13:04Z|00001|ovs_numa|INFO|Discovered 4 CPU cores on NUMA node 0
2025-05-16T05:13:04Z|00002|ovs_numa|INFO|Discovered 1 NUMA nodes and 4 CPU cores
2025-05-16T05:13:04Z|00003|reconnect|INFO|unix:/run/openvswitch/db.sock: connecting...
2025-05-16T05:13:04Z|00004|reconnect|INFO|unix:/run/openvswitch/db.sock: connected
2025-05-16T05:13:04Z|00005|netdev_linux|INFO|tunl0 device has unknown hardware address family 768
2025-05-16T05:13:04Z|00006|ofproto_dpif|INFO|system@ovs-system: Datapath supports recirculation
2025-05-16T05:13:04Z|00007|ofproto_dpif|INFO|system@ovs-system: VLAN header stack length probed as 2
2025-05-16T05:13:04Z|00008|ofproto_dpif|INFO|system@ovs-system: MPLS label stack length probed as 3
2025-05-16T05:13:04Z|00009|ofproto_dpif|INFO|system@ovs-system: Datapath supports truncate action
2025-05-16T05:13:04Z|00010|ofproto_dpif|INFO|system@ovs-system: Datapath supports unique flow ids
2025-05-16T05:13:04Z|00011|ofproto_dpif|INFO|system@ovs-system: Datapath supports clone action
2025-05-16T05:13:04Z|00012|ofproto_dpif|INFO|system@ovs-system: Max sample nesting level probed as 10
2025-05-16T05:13:04Z|00013|ofproto_dpif|INFO|system@ovs-system: Datapath supports eventmask in conntrack action
2025-05-16T05:13:04Z|00014|ofproto_dpif|INFO|system@ovs-system: Datapath supports ct_clear action
2025-05-16T05:13:04Z|00015|ofproto_dpif|INFO|system@ovs-system: Max dp_hash algorithm probed to be 0
2025-05-16T05:13:04Z|00016|ofproto_dpif|INFO|system@ovs-system: Datapath supports check_pkt_len action
2025-05-16T05:13:04Z|00017|ofproto_dpif|INFO|system@ovs-system: Datapath supports timeout policy in conntrack action
2025-05-16T05:13:04Z|00018|ofproto_dpif|INFO|system@ovs-system: Datapath supports ct_zero_snat
2025-05-16T05:13:04Z|00019|ofproto_dpif|INFO|system@ovs-system: Datapath supports ct_state
2025-05-16T05:13:04Z|00020|ofproto_dpif|INFO|system@ovs-system: Datapath supports ct_zone
2025-05-16T05:13:04Z|00021|ofproto_dpif|INFO|system@ovs-system: Datapath supports ct_mark
2025-05-16T05:13:04Z|00022|ofproto_dpif|INFO|system@ovs-system: Datapath supports ct_label
2025-05-16T05:13:04Z|00023|ofproto_dpif|INFO|system@ovs-system: Datapath supports ct_state_nat
2025-05-16T05:13:04Z|00024|ofproto_dpif|INFO|system@ovs-system: Datapath supports ct_orig_tuple
2025-05-16T05:13:04Z|00025|ofproto_dpif|INFO|system@ovs-system: Datapath supports ct_orig_tuple6
2025-05-16T05:13:04Z|00026|ofproto_dpif|INFO|system@ovs-system: Datapath does not support IPv6 ND Extensions
2025-05-16T05:13:04Z|00027|bridge|INFO|bridge br-ex: added interface br-ex on port 65534
2025-05-16T05:13:04Z|00028|bridge|INFO|bridge br-ex: using datapath ID 00003a93b566154b
2025-05-16T05:13:04Z|00029|connmgr|INFO|br-ex: added service controller "punix:/var/run/openvswitch/br-ex.mgmt"
2025-05-16T05:13:04Z|00030|netdev_linux|INFO|tunl0 device has unknown hardware address family 768
2025-05-16T05:13:04Z|00031|bridge|INFO|ovs-vswitchd (Open vSwitch) 2.13.8
2025-05-16T05:13:04Z|00032|netdev_linux|INFO|tunl0 device has unknown hardware address family 768
2025-05-16T05:13:14Z|00033|memory|INFO|54692 kB peak resident set size after 10.1 seconds
2025-05-16T05:13:14Z|00034|memory|INFO|handlers:2 ports:1 revalidators:2 rules:5
```

### Libvirt
Nova 컴퓨팅 서비스에서 가상 머신을 관리하기 위해 사용되는 가상화 라이브러리이다.

#### Rook-Ceph 관련 설정 
`libvirt`는 가상 머신의 디스크를 Ceph RBD에 저장하기 때문에 Ceph 클러스터가 정상인지 확인하고, Ceph 클라이언트 키와 구성이 필요하다.

Rook-Ceph 상태 확인
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

#### 설치 
```
citec@k1:~/osh$ ./O12.libvirt.sh
>>> Initializing Libvirt install...
Warning: Immediate deletion does not wait for confirmation that the running resource has been terminated. The resource may continue to run on the cluster indefinitely.
No resources found
release "libvirt" uninstalled
secret "ceph-client-openstack" deleted
node/k2 unlabeled
node/k3 unlabeled
node/k4 unlabeled
>>> Checking Ceph status...
NAME        DATADIRHOSTPATH   MONCOUNT   AGE    PHASE   MESSAGE                        HEALTH      EXTERNAL   FSID
rook-ceph   /var/lib/rook     3          4d7h   Ready   Cluster created successfully   HEALTH_OK              91658687-b60d-4797-9d84-c61b152702b9
>>> Creating Ceph client key for client.openstack...
secret/ceph-client-openstack created
NAME                    TYPE     DATA   AGE
ceph-client-openstack   Opaque   1      0s
>>> Labeling nodes...
node/k2 labeled
node/k3 labeled
node/k4 labeled
>>> Running helm dependency build...
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "metallb" chart repository
...Successfully got an update from the "ingress-nginx" chart repository
...Successfully got an update from the "rook-release" chart repository
Update Complete. ⎈Happy Helming!⎈
Saving 1 charts
Deleting outdated charts
>>> Installing Libvirt...
Release "libvirt" does not exist. Installing it now.
NAME: libvirt
LAST DEPLOYED: Mon Jun  9 16:40:45 2025
NAMESPACE: openstack
STATUS: deployed
REVISION: 1
TEST SUITE: None
pod/libvirt-libvirt-default-8rglp condition met
pod/libvirt-libvirt-default-xglgx condition met
pod/libvirt-libvirt-default-xt9fc condition met
NAME                            READY   STATUS    RESTARTS   AGE
libvirt-libvirt-default-8rglp   1/1     Running   0          72s
libvirt-libvirt-default-xglgx   1/1     Running   0          72s
libvirt-libvirt-default-xt9fc   1/1     Running   0          72s

Done.
```

파드 로그를 보고 성공적으로 시작되었다는 메시지를 확인한다.
```
citec@k1:~/osh$ kubectl -n openstack logs libvirt-libvirt-default-8rglp | tail -n 5
Defaulted container "libvirt" out of: libvirt, init (init), init-dynamic-options (init), ceph-admin-keyring-placement (init), ceph-keyring-placement (init)
+ '[' -n '' ']'
+ rm -f /var/run/libvirtd.pid
+ [[ -c /dev/kvm ]]
+ systemd-run --scope --slice=system libvirtd --listen
Running scope as unit: run-r01e24a9b8fe742d8a1e21b898e78f778.scope
```

`virsh`로 연결 테스트를 수행해 오류가 없으면 성공이다.
```
citec@k1:~/osh$ kubectl -n openstack exec -it libvirt-libvirt-default-8rglp -- /bin/bash
Defaulted container "libvirt" out of: libvirt, init (init), init-dynamic-options (init), ceph-admin-keyring-placement (init), ceph-keyring-placement (init)
root@k2:/# virsh connect

root@k2:/# virsh list
 Id   Name   State
--------------------

root@k2:/# exit
exit
```

### Neutron
OpenStack의 네트워킹 서비스로, 가상 네트워크, 서브넷, 라우터, 방화벽 등을 관리한다.

#### 설치 
```
citec@k1:~/osh$ ./O13.neutron.sh
>>> Initializing Neutron install...
Warning: Immediate deletion does not wait for confirmation that the running resource has been terminated. The resource may continue to run on the cluster indefinitely.
...
>>> Running helm dependency build...
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "metallb" chart repository
...Successfully got an update from the "ingress-nginx" chart repository
...Successfully got an update from the "rook-release" chart repository
Update Complete. ⎈Happy Helming!⎈
Saving 1 charts
Deleting outdated charts
>>> Installing Neutron...
Release "neutron" does not exist. Installing it now.
NAME: neutron
LAST DEPLOYED: Mon Jun  9 16:43:15 2025
NAMESPACE: openstack
STATUS: deployed
REVISION: 1
pod/neutron-dhcp-agent-default-5wdqs condition met
pod/neutron-dhcp-agent-default-8n6sw condition met
pod/neutron-dhcp-agent-default-k7jvn condition met
pod/neutron-l3-agent-default-crx6j condition met
pod/neutron-l3-agent-default-dq749 condition met
pod/neutron-l3-agent-default-v6cbc condition met
pod/neutron-metadata-agent-default-ckmx9 condition met
pod/neutron-metadata-agent-default-msq4q condition met
pod/neutron-metadata-agent-default-qc6b8 condition met
pod/neutron-netns-cleanup-cron-default-8d4dk condition met
pod/neutron-netns-cleanup-cron-default-8h9xp condition met
pod/neutron-netns-cleanup-cron-default-njsgh condition met
pod/neutron-ovs-agent-default-2wcb9 condition met
pod/neutron-ovs-agent-default-dc4zf condition met
pod/neutron-ovs-agent-default-gl5n6 condition met
pod/neutron-ovs-agent-default-zgtl7 condition met
pod/neutron-rpc-server-7569cb4667-hnz24 condition met
pod/neutron-server-9d6c4fd97-87ptw condition met
NAME                                       READY   STATUS      RESTARTS   AGE
neutron-db-init-xrx2w                      0/1     Completed   0          3m58s
neutron-db-sync-8mxkp                      0/1     Completed   0          3m49s
neutron-dhcp-agent-default-5wdqs           1/1     Running     0          3m58s
neutron-dhcp-agent-default-8n6sw           1/1     Running     0          3m58s
neutron-dhcp-agent-default-k7jvn           1/1     Running     0          3m58s
neutron-ks-endpoints-fb5f8                 0/3     Completed   0          3m15s
neutron-ks-service-rjr8f                   0/1     Completed   0          3m27s
neutron-ks-user-cqhzs                      0/1     Completed   0          2m49s
neutron-l3-agent-default-crx6j             1/1     Running     0          3m58s
neutron-l3-agent-default-dq749             1/1     Running     0          3m58s
neutron-l3-agent-default-v6cbc             1/1     Running     0          3m58s
neutron-metadata-agent-default-ckmx9       1/1     Running     0          3m59s
neutron-metadata-agent-default-msq4q       1/1     Running     0          3m59s
neutron-metadata-agent-default-qc6b8       1/1     Running     0          3m59s
neutron-netns-cleanup-cron-default-8d4dk   1/1     Running     0          3m58s
neutron-netns-cleanup-cron-default-8h9xp   1/1     Running     0          3m59s
neutron-netns-cleanup-cron-default-njsgh   1/1     Running     0          3m59s
neutron-ovs-agent-default-2wcb9            1/1     Running     0          3m58s
neutron-ovs-agent-default-dc4zf            1/1     Running     0          3m58s
neutron-ovs-agent-default-gl5n6            1/1     Running     0          3m58s
neutron-ovs-agent-default-zgtl7            1/1     Running     0          3m58s
neutron-rabbit-init-p6vvj                  0/1     Completed   0          3m36s
neutron-rpc-server-7569cb4667-hnz24        1/1     Running     0          3m59s
neutron-server-9d6c4fd97-87ptw             1/1     Running     0          3m58s

Done.
```

Neutron 서비스가 인증 서비스인 Keystone에 등록되었는지 확인한다. 출력 결과에 `neutron` 서비스가 나타나는지 확인하자.
```
citec@k1:~/osh$ openstack service list
+----------------------------------+-----------+-----------+
| ID                               | Name      | Type      |
+----------------------------------+-----------+-----------+
| 267d629600984bf9800993a444ea3a3d | glance    | image     |
| 8aec3dbf57b94701bca34f3f2892d146 | neutron   | network   |
| e6f877a654ca4868b5543c2a5e4289f4 | keystone  | identity  |
| f84da38c433a46e4bbcfcba66c7bb78f | placement | placement |
| ff3c5caa164c4baf8c7b831b809a9e57 | nova      | compute   |
+----------------------------------+-----------+-----------+
```

`openstack` 명령어로 네트워크 Agent 목록을 보고 모든 에이전트가 `UP` 상태인지 확인한다. 참고로, `openstack network list` 명령어로 네트워크 목록도 확인할 수 있지만, 설치 단계에서는 생성된 네트워크가 없어 출력이 없다.
```
citec@k1:~/osh$ openstack network agent list
+--------------------------------------+--------------------+------+-------------------+-------+-------+---------------------------+
| ID                                   | Agent Type         | Host | Availability Zone | Alive | State | Binary                    |
+--------------------------------------+--------------------+------+-------------------+-------+-------+---------------------------+
| 0547905c-ab16-47cc-8d23-658da32ea493 | Metadata agent     | k1   | None              | :-)   | UP    | neutron-metadata-agent    |
| 0d4c92bb-97f7-462d-8138-71dd7528c498 | DHCP agent         | k2   | nova              | :-)   | UP    | neutron-dhcp-agent        |
| 161949a0-03cc-4420-85bc-12d8e13efc33 | Open vSwitch agent | k2   | None              | :-)   | UP    | neutron-openvswitch-agent |
| 46570f3a-3b68-4042-939e-c2cf1f2f30e7 | Open vSwitch agent | k4   | None              | :-)   | UP    | neutron-openvswitch-agent |
| 57f6c4e5-d5b5-4773-8ba1-92bbfdd40687 | L3 agent           | k3   | nova              | :-)   | UP    | neutron-l3-agent          |
| 62ee4679-e3ca-4e58-ab52-f3c1b7cef53e | Metadata agent     | k2   | None              | :-)   | UP    | neutron-metadata-agent    |
| 81d8f804-7693-4f8b-8987-cea868808963 | L3 agent           | k1   | nova              | :-)   | UP    | neutron-l3-agent          |
| 9d9372b2-36d5-476d-bf41-05025dea04e5 | DHCP agent         | k3   | nova              | :-)   | UP    | neutron-dhcp-agent        |
| d05a2389-6c73-4ce5-b5d6-10d7e8f7a23c | L3 agent           | k2   | nova              | :-)   | UP    | neutron-l3-agent          |
| d0cfccc2-1c8a-4dad-83d3-303f111d07c3 | Open vSwitch agent | k1   | None              | :-)   | UP    | neutron-openvswitch-agent |
| d48fb947-a99b-432a-9694-47a1d05adf89 | Open vSwitch agent | k3   | None              | :-)   | UP    | neutron-openvswitch-agent |
| ee8661bb-3e2b-42bc-8c12-66eb5d701493 | Metadata agent     | k3   | None              | :-)   | UP    | neutron-metadata-agent    |
| f0ee7368-9329-423a-861d-fdbae521913d | DHCP agent         | k1   | nova              | :-)   | UP    | neutron-dhcp-agent        |
+--------------------------------------+--------------------+------+-------------------+-------+-------+---------------------------+
```

Neutron API가 정상적으로 응답하는지 `curl` 명령어로 확인한다.
```
citec@k1:~/osh$ curl -H "X-Auth-Token: $(openstack token issue -c id -f value)" -H "Host: neutron.openstack.svc.cluster.local" http://172.16.2.149/v2.0/networks
{"networks":[]}
```

#### 실제 네트워크 기능 테스트 

Neutron 서비스가 실제로 네트워킹 기능을 제공하는지 확인하려면 네트워크와 VM을 생성해 테스트해야 한다. 

네트워크와 서브넷을 생성해보자.
```
citec@k1:~/osh$ openstack network create test-net
+---------------------------+--------------------------------------+
| Field                     | Value                                |
+---------------------------+--------------------------------------+
| admin_state_up            | UP                                   |
| availability_zone_hints   | nova                                 |
| availability_zones        |                                      |
| created_at                | 2025-05-20T00:40:14Z                 |
| description               |                                      |
| dns_domain                | None                                 |
| id                        | 9a19830f-0fcd-4364-9b85-f6dbcf0be958 |
| ipv4_address_scope        | None                                 |
| ipv6_address_scope        | None                                 |
| is_default                | False                                |
| is_vlan_transparent       | None                                 |
| mtu                       | 1450                                 |
| name                      | test-net                             |
| port_security_enabled     | True                                 |
| project_id                | d2235125de7d49a193b5951027f780f3     |
| provider:network_type     | vxlan                                |
| provider:physical_network | None                                 |
| provider:segmentation_id  | 476                                  |
| qos_policy_id             | None                                 |
| revision_number           | 1                                    |
| router:external           | Internal                             |
| segments                  | None                                 |
| shared                    | False                                |
| status                    | ACTIVE                               |
| subnets                   |                                      |
| tags                      |                                      |
| updated_at                | 2025-05-20T00:40:14Z                 |
+---------------------------+--------------------------------------+
citec@k1:~/osh$ openstack subnet create --network test-net --subnet-range 192.168.1.0/24 test-subnet
+----------------------+--------------------------------------+
| Field                | Value                                |
+----------------------+--------------------------------------+
| allocation_pools     | 192.168.1.2-192.168.1.254            |
| cidr                 | 192.168.1.0/24                       |
| created_at           | 2025-05-20T00:40:28Z                 |
| description          |                                      |
| dns_nameservers      |                                      |
| dns_publish_fixed_ip | None                                 |
| enable_dhcp          | True                                 |
| gateway_ip           | 192.168.1.1                          |
| host_routes          |                                      |
| id                   | a26df815-09cf-4fee-ae25-e96d6bb80954 |
| ip_version           | 4                                    |
| ipv6_address_mode    | None                                 |
| ipv6_ra_mode         | None                                 |
| name                 | test-subnet                          |
| network_id           | 9a19830f-0fcd-4364-9b85-f6dbcf0be958 |
| project_id           | d2235125de7d49a193b5951027f780f3     |
| revision_number      | 0                                    |
| segment_id           | None                                 |
| service_types        |                                      |
| subnetpool_id        | None                                 |
| tags                 |                                      |
| updated_at           | 2025-05-20T00:40:28Z                 |
+----------------------+--------------------------------------+
```
제대로 생성된 것인지 확인해본다.
```
citec@k1:~/osh$ openstack network list
+--------------------------------------+----------+--------------------------------------+
| ID                                   | Name     | Subnets                              |
+--------------------------------------+----------+--------------------------------------+
| 9a19830f-0fcd-4364-9b85-f6dbcf0be958 | test-net | a26df815-09cf-4fee-ae25-e96d6bb80954 |
+--------------------------------------+----------+--------------------------------------+
citec@k1:~/osh$ openstack subnet list
+--------------------------------------+-------------+--------------------------------------+----------------+
| ID                                   | Name        | Network                              | Subnet         |
+--------------------------------------+-------------+--------------------------------------+----------------+
| a26df815-09cf-4fee-ae25-e96d6bb80954 | test-subnet | 9a19830f-0fcd-4364-9b85-f6dbcf0be958 | 192.168.1.0/24 |
+--------------------------------------+-------------+--------------------------------------+----------------+
```

VM을 생성하고 네트워크 연결을 테스트한다.
  
  
### Nova (Compute Service)

가상 머신의 생성, 관리, 삭제를 담당한다.

#### 컴퓨트 노드 레이블 설정 
컴퓨트 노드로 사용할 노드에 레이블을 추가한다. k2, k3, k4 노드를 컴퓨트 노드로 사용하기로 하자.

```
citec@k1:~/osh$ kubectl label nodes k2 openstack-compute-node=enabled
node/k2 labeled
citec@k1:~/osh$ kubectl label nodes k3 openstack-compute-node=enabled
node/k3 labeled
citec@k1:~/osh$ kubectl label nodes k4 openstack-compute-node=enabled
node/k4 labeled
```

#### helm dependency build 실행
```
citec@k1:~/osh$ cd openstack-helm
citec@k1:~/osh/openstack-helm$ helm dependency build nova
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "metallb" chart repository
...Successfully got an update from the "rook-release" chart repository
...Successfully got an update from the "ingress-nginx" chart repository  
Update Complete. ⎈Happy Helming!⎈
Saving 1 charts
Deleting outdated charts
```

Ceph 클러스터에서 Nova용 클라이언트 키링을 생성한다.
```
citec@k1:~/osh$ kubectl -n rook-ceph exec -it rook-ceph-tools -- ceph auth get-or-create client.nova mon 'allow r' osd 'allow class-read object_prefix rbd_children, allow rwx pool=nova-vms' -o /tmp/ceph.client.nova.keyring
citec@k1:~/osh$ kubectl -n rook-ceph cp rook-ceph-tools:/tmp/ceph.client.nova.keyring ./ceph.client.nova.keyring
tar: Removing leading `/' from member names
```

생성된 키링을 Kubernetes Secret으로 등록한다.
```
citec@k1:~/osh$ kubectl -n openstack create secret generic pvc-ceph-client-key --from-file=ceph.client.nova.keyring
secret/pvc-ceph-client-key created
```

Ceph 클러스터와의 통신을 위해 설정 파일(`ceph.conf`)과 관리자 키링(`client.admin.keyring`)을 포함하는 Secret을 생성하여 등록한다.
```
citec@k1:~/osh$ cat ceph.conf
[global]
fsid = 603c8790-369b-40e8-b42e-751a1e771267
mon_host = rook-ceph-mon-b.rook-ceph.svc.cluster.local:6789,rook-ceph-mon-c.rook-ceph.svc.cluster.local:6789,rook-ceph-mon-d.rook-ceph.svc.cluster.local:6789

citec@k1:~/osh$ cat client.admin.keyring
[client.admin]
key = AQCVSBxorL2XEhAAn575xTxB7dFlbYU6zn4fjQ==

citec@k1:~/osh$ kubectl -n openstack create secret generic ceph-etc-secret \
  --from-file=ceph.conf=./ceph.conf \
  --from-file=client.admin.keyring=./client.admin.keyring
secret/ceph-etc-secret created
```

생성된 Secret을 확인한다.
```
citec@k1:~/osh$ kubectl -n openstack get secret ceph-etc-secret -o yaml
apiVersion: v1
data:
  ceph.conf: W2dsb2JhbF0KZnNpZCA9IDYwM2M4NzkwLTM2OWItNDBlOC1iNDJlLTc1MWExZTc3MTI2Nwptb25faG9zdCA9IHJvb2stY2VwaC1tb24tYi5yb29rLWNlcGguc3ZjLmNsdXN0ZXIubG9jYWw6Njc4OSxyb29rLWNlcGgtbW9uLWMucm9vay1jZXBoLnN2Yy5jbHVzdGVyLmxvY2FsOjY3ODkscm9vay1jZXBoLW1vbi1kLnJvb2stY2VwaC5zdmMuY2x1c3Rlci5sb2NhbDo2Nzg5Cg==
  client.admin.keyring: W2NsaWVudC5hZG1pbl0Ka2V5ID0gQVFDVlNCeG9yTDJYRWhBQW41NzV4VHhCN2RGbGJZVTZ6bjRmalE9PQo=
kind: Secret
metadata:
  creationTimestamp: "2025-05-20T04:04:26Z"
  name: ceph-etc-secret
  namespace: openstack
  resourceVersion: "2903945"
  uid: 24df07a3-062e-41b7-8a44-bc57d3247376
type: Opaque
```

`client.cinder` 사용자를 생성하고, 키링을 Secret으로 등록한다.
```
citec@k1:~/osh$ kceph ceph auth get-or-create client.cinder mon 'profile rbd' osd 'profile rbd' -o /tmp/ceph.client.cinder.keyring
citec@k1:~/osh$ kubectl -n rook-ceph cp rook-ceph-tools:/tmp/ceph.client.cinder.keyring ./client.cinder.keyring
tar: Removing leading `/' from member names

citec@k1:~/osh$ kubectl -n openstack create secret generic ceph-client-cinder --from-file=key=./client.cinder.keyring
secret/ceph-client-cinder created
```


#### 설치
```
citec@k1:~/osh$ helm upgrade --install nova openstack-helm/nova \
  --namespace=openstack \
  --timeout=600s
Release "nova" does not exist. Installing it now.
NAME: nova
LAST DEPLOYED: Tue May 13 14:01:39 2025
NAMESPACE: openstack
STATUS: deployed
REVISION: 1
```

#### 상태 확인
```
citec@k1:~/osh$ kubectl -n openstack get pods -l application=nova,component=compute
NAME                         READY   STATUS     RESTARTS   AGE
nova-compute-default-8svhv   0/1     Init:0/6   0          19s
nova-compute-default-9tzlg   0/1     Init:0/6   0          22s
nova-compute-default-jblz6   0/1     Init:0/6   0          26s


kubectl -n openstack delete pod nova-compute-default-d298h
kubectl -n openstack get pods -l application=nova

kubectl -n openstack logs nova-compute-default-lf7dr -c ceph-keyring-placement -f
