---
title: "OpenStack Helm 설치 - 2부"
date: 2025-05-17
tags: [openstack, helm, kubernetes, ceph, ansible]
---

# OpenStack-Helm 설치 - 2부

OpenStack-Helm은 Helm 차트를 사용하여 OpenStack 서비스를 Kubernetes에 배포한다. 각 서비스는 의존성을 가지므로, 설치 순서를 준수하고 `helm dependency build`를 통해 의존성을 해결해야 한다. 기본 설치 순서는 다음과 같다.

1. **인프라 서비스**: MariaDB, RabbitMQ, Memcached
2. **코어 서비스**: Keystone
3. **추가 서비스**: Glance, Placement, Nova, Neutron, Cinder, Horizon, Heat

## 상세 설치 과정

### Rook-Ceph 스토리지 설정
OpenStack 서비스는 데이터를 저장하기 위해 Rook-Ceph를 사용한다.

#### StorageClass 확인
`rook-ceph-block` StorageClass를 확인한다. 

```
citec@k1:~/osh$ kubectl get storageclass
No resources found
```

없을 경우, 아래 명령어로 생성한다.

```
citec@k1:~/osh$ kubectl -n rook-ceph apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: rook-ceph-block
provisioner: rook-ceph.rbd.csi.ceph.com
parameters:
  clusterID: rook-ceph
  pool: replicapool
  imageFormat: "2"
  imageFeatures: layering
  csi.storage.k8s.io/provisioner-secret-name: rook-csi-rbd-provisioner
  csi.storage.k8s.io/provisioner-secret-namespace: rook-ceph
  csi.storage.k8s.io/controller-expand-secret-name: rook-csi-rbd-provisioner
  csi.storage.k8s.io/controller-expand-secret-namespace: rook-ceph
  csi.storage.k8s.io/node-stage-secret-name: rook-csi-rbd-node
  csi.storage.k8s.io/node-stage-secret-namespace: rook-ceph
  csi.storage.k8s.io/fstype: ext4
reclaimPolicy: Delete
allowVolumeExpansion: true
EOF
storageclass.storage.k8s.io/rook-ceph-block created

citec@k1:~/osh$ kubectl get storageclass
NAME              PROVISIONER                  RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION   AGE
rook-ceph-block   rook-ceph.rbd.csi.ceph.com   Delete          Immediate           true                   104m
```

#### Ceph 클러스터에 `replicapool` 풀 생성
`rook-ceph-block` StorageClass가 참조하는 `replicapool` 풀을 생성하고 이를 초기화한다.

```
citec@k1:~/osh$ kubectl -n rook-ceph exec -it rook-ceph-tools -- ceph osd pool create replicapool 32 32
pool 'replicapool' created
citec@k1:~/osh$ kubectl -n rook-ceph exec -it rook-ceph-tools -- rbd pool init replicapool
citec@k1:~/osh$ kubectl -n rook-ceph exec -it rook-ceph-tools -- ceph osd pool ls
.mgr
replicapool
```

### MariaDB 설치
MariaDB는 OpenStack의 데이터베이스 역할을 하며, 가장 먼저 설치해야 한다.

#### 설치 전 초기화 방법
이전에 설치했거나 설치에 실패한 경우, 이를 초기화하는 방법이다.

```
citec@k1:~/osh$ kubectl -n openstack delete pvc mysql-data-mariadb-server-0
persistentvolumeclaim "mysql-data-mariadb-server-0" deleted
citec@k1:~/osh$ helm uninstall mariadb -n openstack
release "mariadb" uninstalled
```

#### helm dependency build 수행
`helm dependency build`는 Helm 차트의 의존성을 해결하는 필수 단계이다. OpenStack-Helm의 각 차트는 `requirements.yaml`에 명시된 의존성을 가지며, 이 명령어를 실행하면 의존성을 다운로드하고 빌드한다. 모든 서비스 설치 전에 해당 차트 디렉토리에서 실행해야 한다.

```
citec@k1:~/osh$ cd openstack-helm
citec@k1:~/osh/openstack-helm$ helm dependency build mariadb
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "metallb" chart repository
...Successfully got an update from the "ingress-nginx" chart repository
...Successfully got an update from the "rook-release" chart repository
Update Complete. ⎈Happy Helming!⎈
Saving 1 charts
Deleting outdated charts
```

#### StorageClass 지정 
`mariadb-values.yaml` 파일을 생성하고, StorageClass를 `rook-ceph-block`으로 설정한다.

```
citec@k1:~/osh/openstack-helm$ cd ~/osh
citec@k1:~/osh$ helm show values openstack-helm/mariadb > openstack/mariadb-values.yaml
```

`mariadb-values.yaml` 파일에서 `volume:` 섹션의 `class_name: general` 부분을 수정한다.

```
citec@k1:~/osh$ vi openstack/mariadb-values.yaml
volume:
  enabled: true
  class_name: rook-ceph-block
  size: 5Gi
  backup:
    enabled: true
    class_name: rook-ceph-block
    size: 5Gi
```

#### Node Selector 조건에 따라 레이블 설정 
mariadb 파드의 노드 선택 조건(`Node-Selectors: openstack-control-plane=enabled`)을 위해 마스터 노드들에 레이블을 추가한다. 

```
citec@k1:~/osh$ kubectl label nodes k1 openstack-control-plane=enabled
node/k1 labeled
citec@k1:~/osh$ kubectl label nodes k2 openstack-control-plane=enabled
node/k2 labeled
citec@k1:~/osh$ kubectl label nodes k3 openstack-control-plane=enabled
node/k3 labeled
```

#### 설치 
```
citec@k1:~/osh$ helm upgrade --install mariadb openstack-helm/mariadb \
  --namespace=openstack \
  --set pod.replicas.server=1 \
  --set volume.storage_class=rook-ceph-block \
  --values openstack/mariadb-values.yaml \
  --timeout=600s
Release "mariadb" does not exist. Installing it now.
NAME: mariadb
LAST DEPLOYED: Thu May  8 15:28:29 2025
NAMESPACE: openstack
STATUS: deployed
REVISION: 1
```

#### 상태 확인
```
citec@k1:~/osh$ kubectl -n openstack wait --for=condition=Ready pod -l application=mariadb --timeout=600s
pod/mariadb-controller-68584bd996-zbdjn condition met
pod/mariadb-server-0 condition met
```

#### 파드 상태 및 노드 위치 확인
```
citec@k1:~/osh$ kubectl -n openstack get pods -l application=mariadb -o wide
NAME                                  READY   STATUS    RESTARTS   AGE     IP               NODE   NOMINATED NODE   READINESS GATES
mariadb-controller-68584bd996-zbdjn   1/1     Running   0          2m16s   10.244.105.138   k1     <none>           <none>
mariadb-server-0                      1/1     Running   0          2m15s   10.244.105.136   k1     <none>           <none>
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

### RabbitMQ 설치
RabbitMQ는 서비스 간 메시지 브로커로 사용된다.

#### 설치 전 초기화 방법
이전에 설치했거나 설치에 실패한 경우, 이를 초기화하는 방법이다.

```
citec@k1:~/osh$ helm uninstall rabbitmq -n openstack
release "rabbitmq" uninstalled
citec@k1:~/osh$ kubectl -n openstack delete pvc rabbitmq-data-rabbitmq-rabbitmq-0
persistentvolumeclaim "rabbitmq-data-rabbitmq-rabbitmq-0" deleted
citec@k1:~/osh$ kubectl -n openstack delete pod -l application=rabbitmq --force --grace-period=0
Warning: Immediate deletion does not wait for confirmation that the running resource has been terminated. The resource may continue to run on the cluster indefinitely.
pod "rabbitmq-cluster-wait-t62lq" force deleted
```

#### StorageClass 지정 
`mariadb-values.yaml` 파일을 생성하고, StorageClass를 `rook-ceph-block`으로 설정한다.

```
citec@k1:~/osh$ helm show values openstack-helm/rabbitmq > openstack/rabbitmq-values.yaml
```

`rabbitmq-values.yaml` 파일에서 `volume:` 섹션의 `class_name: general` 부분을 수정한다. 추가로 서버 단에서 ipv6를 비활성화했으므로, ipv4 만 사용하도록 설정한다. 

```
citec@k1:~/osh$ vi openstack/rabbitmq-values.yaml
volume:
  use_local_path:
    enabled: false
    host_path: /var/lib/rabbitmq
  chown_on_start: true
  enabled: true
  class_name: rook-ceph-block
  size: 768Mi
conf:
    bind_address: "0.0.0.0"
    rabbit_additonal_conf:
      management.listener.ip: "0.0.0.0"
      management.listener.port: 15672
```

#### helm dependency build 수행
```
citec@k1:~/osh$ cd openstack-helm
citec@k1:~/osh/openstack-helm$ helm dependency build rabbitmq
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "ingress-nginx" chart repository
...Successfully got an update from the "metallb" chart repository
...Successfully got an update from the "rook-release" chart repository
Update Complete. ⎈Happy Helming!⎈
Saving 1 charts
Deleting outdated charts
```

#### 설치 
```
citec@k1:~/osh$ helm upgrade --install rabbitmq openstack-helm/rabbitmq \
  --namespace=openstack \
  --set pod.replicas.server=1 \
  --set volume.storage_class=rook-ceph-block \
  --values openstack/rabbitmq-values.yaml \
  --timeout=600s
Release "rabbitmq" does not exist. Installing it now.
NAME: rabbitmq
LAST DEPLOYED: Fri May  9 09:03:39 2025
NAMESPACE: openstack
STATUS: deployed
REVISION: 1
```

아래와 같이 설치 과정에서 PVC 바인딩 지연, 초기화 컨테이너와 이미지 풀링에 시간이 소요되어 타임아웃이 발생될 수 있으나 15분 정도 후 설치가 완료될 수 있으므로 모니터링 한다. (혹은 초기화 후 재설치한다.)
```
Error: failed post-install: 1 error occurred:
        * timed out waiting for the condition
```

#### 파드 상태 및 노드 위치 확인
```
citec@k1:~/osh$ kubectl -n openstack get pods -l application=rabbitmq -o wide
NAME                          READY   STATUS      RESTARTS   AGE   IP               NODE   NOMINATED NODE   READINESS GATES
rabbitmq-cluster-wait-t62lq   0/1     Completed   0          30m   10.244.195.173   k3     <none>           <none>
rabbitmq-rabbitmq-0           1/1     Running     0          30m   10.244.99.47     k2     <none>           <none>
```

#### RabbitMQ 상태 확인 
```
citec@k1:~/oshkubectl -n openstack exec -it rabbitmq-rabbitmq-0 -- rabbitmqctl status
Defaulted container "rabbitmq" out of: rabbitmq, init (init), rabbitmq-password (init), rabbitmq-cookie (init), rabbitmq-perms (init)
Status of node rabbit@rabbitmq-rabbitmq-0.rabbitmq.openstack.svc.cluster.local ...
Runtime

OS PID: 13
OS: Linux
Uptime (seconds): 785
Is under maintenance?: false
RabbitMQ version: 3.13.0
RabbitMQ release series support status: supported
Node name: rabbit@rabbitmq-rabbitmq-0.rabbitmq.openstack.svc.cluster.local
Erlang configuration: Erlang/OTP 26 [erts-14.2.2] [source] [64-bit] [smp:1:1] [ds:1:1:10] [async-threads:1] [jit:ns]
Crypto library: OpenSSL 3.1.5 30 Jan 2024
Erlang processes: 375 used, 1048576 limit
Scheduler run queue: 1
Cluster heartbeat timeout (net_ticktime): 60
```

#### 파드 이벤트 확인 
설치 과정에서 문제가 발생할 경우 원인을 파악하기 위해 파드의 이벤트를 확인할 필요가 있다. 아래 명령 수행 후 `Events:` 섹션에 어떤 내용이 있는지 확인하여 원인을 파악할 수 있다.

```
citec@k1:~/osh$ kubectl -n openstack describe pod rabbitmq-rabbitmq-0
...
Events:
  Type     Reason                  Age                From                     Message
  ----     ------                  ----               ----                     -------
  Warning  FailedScheduling        69s (x4 over 69s)  default-scheduler        0/4 nodes are available: pod has unbound immediate PersistentVolumeClaims. preemption: 0/4 nodes are available: 4 Preemption is not helpful for scheduling.
  Normal   Scheduled               69s                default-scheduler        Successfully assigned openstack/rabbitmq-rabbitmq-0 to k2
  Normal   SuccessfulAttachVolume  69s                attachdetach-controller  AttachVolume.Attach succeeded for volume "pvc-ad0337fc-8c51-4c05-aaa7-aba599770f8f"
  Normal   Pulled                  62s                kubelet                  Container image "quay.io/airshipit/kubernetes-entrypoint:latest-ubuntu_focal" already present on machine
  Normal   Created                 62s                kubelet                  Created container: init
  Normal   Started                 61s                kubelet                  Started container init
  Normal   Pulled                  61s                kubelet                  Container image "docker.io/openstackhelm/heat:2023.2-ubuntu_jammy" already present on machine
  Normal   Created                 61s                kubelet                  Created container: rabbitmq-password
  Normal   Started                 61s                kubelet                  Started container rabbitmq-password
  Normal   Pulled                  60s                kubelet                  Container image "docker.io/library/rabbitmq:3.13.0" already present on machine
  Normal   Created                 60s                kubelet                  Created container: rabbitmq-cookie
  Normal   Started                 60s                kubelet                  Started container rabbitmq-cookie
  Normal   Pulled                  59s                kubelet                  Container image "docker.io/library/rabbitmq:3.13.0" already present on machine
  Normal   Created                 59s                kubelet                  Created container: rabbitmq-perms
  Normal   Started                 59s                kubelet                  Started container rabbitmq-perms
  Normal   Pulled                  58s                kubelet                  Container image "docker.io/library/rabbitmq:3.13.0" already present on machine
  Normal   Created                 58s                kubelet                  Created container: rabbitmq
  Normal   Started                 58s                kubelet                  Started container rabbitmq
```
