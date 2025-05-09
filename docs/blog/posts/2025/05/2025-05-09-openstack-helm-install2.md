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

### 설치 순서가 중요한 이유

- **의존성**: 예를 들어, Nova는 Keystone, Glance, Neutron이 설치되어 있어야 작동한다.
- **기본 인프라**: MariaDB와 RabbitMQ는 거의 모든 서비스가 사용하는 필수 구성 요소이므로 가장 먼저 설치해야 한다.
- **서비스 등록**: Keystone이 설치되어야 다른 서비스들이 인증 및 등록을 할 수 있다.

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

### Memcached 설치
캐싱 서비스로, Keystone과 같은 서비스의 성능을 향상시킨다.

#### helm dependency build 수행

```
citec@k1:~/osh$ cd openstack-helm
citec@k1:~/osh/openstack-helm$ helm dependency build memcached
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "metallb" chart repository
...Successfully got an update from the "ingress-nginx" chart repository
...Successfully got an update from the "rook-release" chart repository
Update Complete. ⎈Happy Helming!⎈
Saving 1 charts
Deleting outdated charts
```

#### 설치 및 상태 확인

```
citec@k1:~/osh/openstack-helm$ cd ~/osh
citec@k1:~/osh$ helm upgrade --install memcached openstack-helm/memcached \
  --namespace=openstack \
  --timeout=600s
Release "memcached" does not exist. Installing it now.
NAME: memcached
LAST DEPLOYED: Fri May  9 10:57:05 2025
NAMESPACE: openstack
STATUS: deployed
REVISION: 1
TEST SUITE: None

citec@k1:~/osh$ kubectl -n openstack wait --for=condition=Ready pod -l application=memcached --timeout=600s
pod/memcached-memcached-0 condition met

citec@k1:~/osh$ kubectl -n openstack get pods -l application=memcached
NAME                    READY   STATUS    RESTARTS   AGE
memcached-memcached-0   1/1     Running   0          75s
```

### Keystone (Identity Service) 설치
OpenStack의 인증 및 서비스 카탈로그를 관리하는 핵심 서비스이다. 다른 모든 서비스가 Keystone에 등록되어야 하므로 이 단계에서 설치한다.

#### helm dependency build 실행

```
citec@k1:~/osh$ cd openstack-helm
citec@k1:~/osh/openstack-helm$ helm dependency build keystone
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "metallb" chart repository
...Successfully got an update from the "ingress-nginx" chart repository
...Successfully got an update from the "rook-release" chart repository
Update Complete. ⎈Happy Helming!⎈
Saving 1 charts
Deleting outdated charts
```

#### 설치

```
citec@k1:~/osh/openstack-helm$ cd ~/osh
citec@k1:~/osh$ helm upgrade --install keystone openstack-helm/keystone \
  --namespace=openstack \
  --timeout=600s
Release "keystone" does not exist. Installing it now.
NAME: keystone
LAST DEPLOYED: Fri May  9 11:00:31 2025
NAMESPACE: openstack
STATUS: deployed
REVISION: 1
```

#### 파드 상태 확인

```
citec@k1:~/osh$ kubectl -n openstack get pods -l application=keystone
NAME                              READY   STATUS      RESTARTS   AGE
keystone-api-58b788dfcc-7cndw     1/1     Running     0          3m21s
keystone-bootstrap-8hbdl          0/1     Completed   0          41s
keystone-credential-setup-kk7cb   0/1     Completed   0          3m21s
keystone-db-init-d26zc            0/1     Completed   0          2m58s
keystone-db-sync-ft6xg            0/1     Completed   0          2m32s
keystone-domain-manage-m52fn      0/1     Completed   0          56s
keystone-fernet-setup-5p7m5       0/1     Completed   0          2m45s
keystone-rabbit-init-jcn4r        0/1     Completed   0          2m6s
```

#### Keystone 접근 

`openstack` 명령어를 이용해 Keystone에 접근하기 위해서는 Keystone 서비스의 URL과 `admin` 사용자의 비밀번호가 필요하다. 이를 확인하고, 접근하는 방법에 대해 설명한다.

`keystone-values.yaml` 파일을 생성하고, `endpoints.identity.auth.admin.password` 값을 확인한다.
```
citec@k1helm show values openstack-helm/keystone > openstack/keystone-values.yaml

```
endpoints:
  identity:
    namespace: null
    name: keystone
    auth:
      admin:
        region_name: RegionOne
        username: admin
        password: password
        project_name: admin
        user_domain_name: default
        project_domain_name: default
        default_domain_id: default
```

이 `admin` 사용자의 비밀번호는 아래와 같이 Secret을 통해서도 확인이 가능하다. `OS_PASSWORD`의 값이며, 이는 `base64 --decode` 명령으로 확인이 가능하다.
```
citec@k1:~/osh$ kubectl -n openstack get secret keystone-keystone-admin -o yaml
apiVersion: v1
data:
  OS_AUTH_URL: aHR0cDovL2tleXN0b25lLWFwaS5vcGVuc3RhY2suc3ZjLmNsdXN0ZXIubG9jYWw6NTAwMC92Mw==
  OS_DEFAULT_DOMAIN: ZGVmYXVsdA==
  OS_INTERFACE: aW50ZXJuYWw=
  OS_PASSWORD: cGFzc3dvcmQ=
  OS_PROJECT_DOMAIN_NAME: ZGVmYXVsdA==
  OS_PROJECT_NAME: YWRtaW4=
  OS_REGION_NAME: UmVnaW9uT25l
  OS_USER_DOMAIN_NAME: ZGVmYXVsdA==
  OS_USERNAME: YWRtaW4=
kind: Secret
metadata:
  annotations:
    meta.helm.sh/release-name: keystone
    meta.helm.sh/release-namespace: openstack
  creationTimestamp: "2025-05-09T02:00:33Z"
  labels:
    app.kubernetes.io/managed-by: Helm
  name: keystone-keystone-admin
  namespace: openstack
  resourceVersion: "258693"
  uid: 72eb9e41-eb7d-4319-a99d-cf557842ad50
type: Opaque

citec@k1:~/osh$ kubectl -n openstack get secret keystone-keystone-admin -o jsonpath='{.data.OS_PASSWORD}' | base64 --decode
passwordcitec@k1:~/osh$
```

`keystone-api` 파드가 어떤 노드에 있더라도 영구적으로 k1 노드에서 접근할 수 있도록 설정하기 위해 Ingress를 사용한다. Ingress를 사용하면 `keystone-api`를 도메인 이름으로 외부에 노출할 수 있으므로, k1 노드에서 접근하려면 Ingress를 통해 안정적인 엔드포인트를 제공받을 수 있다.

`keystone-api`를 도메인 이름으로 외부에 노출하기 위한 Ingress 리소스를 생성한다.
```
citec@k1:~/osh$ tee ingress-keystone.yaml <<EOF
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
EOF

citec@k1:~/osh$ kubectl -n openstack apply -f ingress-keystone.yaml
ingress.networking.k8s.io/keystone-ingress created
```

아래 명령으로 서비스 및 포트를 확인한다.
```
citec@k1:~/osh$ kubectl -n openstack get svc keystone-api
NAME           TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
keystone-api   ClusterIP   10.96.205.144   <none>        5000/TCP   4h19m
```

Ingress Controller Pod가 80번 포트를 수신 대기 중인지 확인한다.
```
citec@k1:~/osh$ kubectl -n openstack get pods -l app.kubernetes.io/name=ingress-nginx -o jsonpath='{.items[0].spec.containers[0].ports}'
[{"containerPort":80,"name":"http","protocol":"TCP"},{"containerPort":443,"name":"https","protocol":"TCP"}]
```

아래와 같이 DaemonSet을 수정하여 Ingress Controller가 노드의 네트워크를 직접 사용하고, 80번 및 443번 포트를 노드에 매핑하도록 설정한다. 수정한 후 파드들이 정상적으로 재시작되었는지 확인하고, 노드에도 80 포트가 LISTEN 하는지 확인한다.
```
citec@k1:~/osh$ kubectl -n openstack edit daemonset ingress-nginx-openstack-controller
spect:
  template:
    spec:
      hostNetwork: true
      containers:
        ports:
        - containerPort: 80
          hostPort: 80
          name: http
          protocol: TCP
        - containerPort: 443
          hostPort: 443
          name: https
          protocol: TCP
daemonset.apps/ingress-nginx-openstack-controller edited

citec@k1:~/osh$ kubectl -n openstack get pods -l app.kubernetes.io/name=ingress-nginx
NAME                                       READY   STATUS    RESTARTS   AGE
ingress-nginx-openstack-controller-hdtwh   1/1     Running   0          101s
ingress-nginx-openstack-controller-qldzg   1/1     Running   0          53s
ingress-nginx-openstack-controller-rgfrp   1/1     Running   0          28s
ingress-nginx-openstack-controller-w7bxj   1/1     Running   0          77s

citec@k1:~/osh$ ssh k1 "sudo netstat -tunlp | grep :80"
tcp        0      0 0.0.0.0:80              0.0.0.0:*               LISTEN      2031149/nginx: mast
```

k1 노드에서 접근하려면 `/etc/hosts` 파일에 `keystone.citec.com`을 k1 노드의 IP를 지정한다.
```
citec@k1:~/osh$ cat /etc/hosts
127.0.0.1 localhost
172.16.2.149 k1
172.16.2.52 k2
172.16.2.223 k3
172.16.2.161 k4
172.16.2.149 keystone.citec.com
```

정상적으로 접근이 되는지 `curl` 명령으로 확인하자.
```
citec@k1:~/osh$ curl http://keystone.citec.com
{"versions": {"values": [{"id": "v3.14", "status": "stable", "updated": "2020-04-07T00:00:00Z", "links": [{"rel": "self", "href": "http://keystone.citec.com/v3/"}], "media-types": [{"base": "application/json", "type": "application/vnd.openstack.identity-v3+json"}]}]}}
```

`openstack` 명령을 사용하기 위해서 아래 환경변수들을 설정한다.
```
citec@k1:~/osh$ tee -a ~/.profile <<EOF
export OS_AUTH_URL=http://keystone.citec.com/v3
export OS_USERNAME=admin
export OS_PASSWORD=password
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=default
export OS_PROJECT_DOMAIN_NAME=default
EOF

citec@k1:~/osh$ . ~/.profile

citec@k1:~/osh$ env | grep OS_
OS_AUTH_URL=http://keystone.citec.com/v3
OS_PROJECT_DOMAIN_NAME=default
OS_USERNAME=admin
OS_USER_DOMAIN_NAME=default
OS_PROJECT_NAME=admin
OS_PASSWORD=password
```

`openstack` 명령을 실행해보자. 아래와 같이 openstack 명령은 컨테이너 형태로 실행된다.
```
citec@k1:~/osh$ openstack
Unable to find image 'quay.io/airshipit/openstack-client:2024.2' locally
2024.2: Pulling from airshipit/openstack-client
7478e0ac0f23: Pull complete
15f0d6b9775f: Pull complete
1de21cdae6fb: Pull complete
Digest: sha256:e293799048ac51745aa752783c20740dd9b708805423ad8059dec2439b598949
Status: Downloaded newer image for quay.io/airshipit/openstack-client:2024.2
```

앞에서 설정한 환경변수를 컨테이너로 전달하기 위해서는 아래와 같이 수행한다.
```
citec@k1:~/osh$ docker run --network host \
           -e OS_AUTH_URL=$OS_AUTH_URL \
           -e OS_USERNAME=$OS_USERNAME \
           -e OS_PASSWORD=$OS_PASSWORD \
           -e OS_PROJECT_NAME=$OS_PROJECT_NAME \
           -e OS_PROJECT_DOMAIN_NAME=$OS_PROJECT_DOMAIN_NAME \
           -e OS_USER_DOMAIN_NAME=$OS_USER_DOMAIN_NAME \
           quay.io/airshipit/openstack-client:2024.2 \
           openstack service list
+----------------------------------+----------+----------+
| ID                               | Name     | Type     |
+----------------------------------+----------+----------+
| e6f877a654ca4868b5543c2a5e4289f4 | keystone | identity |
+----------------------------------+----------+----------+
```

매번 이런 식으로 `openstack` 명령을 수행하기 불편하므로, alias로 설정하자.
```
citec@k1:~/osh$ tee -a ~/.bashrc <<EOF
> alias openstack='docker run --network host quay.io/airshipit/openstack-client:2024.2 openstack --os-auth-url $OS_AUTH_URL --os-project-domain-name $OS_PROJECT_DOMAIN_NAME --os-user-domain-name $OS_USER_DOMAIN_NAME --os-project-name $OS_PROJECT_NAME --os-username $OS_USERNAME --os-password $OS_PASSWORD'
> EOF
alias openstack='docker run --network host quay.io/airshipit/openstack-client:2024.2 openstack --os-auth-url http://keystone.citec.com/v3 --os-project-domain-name default --os-user-domain-name default --os-project-name admin --os-username admin --os-password password'

citec@k1:~/osh$ . ~/.bashrc
citec@k1:~/osh$ openstack service list
+----------------------------------+----------+----------+
| ID                               | Name     | Type     |
+----------------------------------+----------+----------+
| e6f877a654ca4868b5543c2a5e4289f4 | keystone | identity |
+----------------------------------+----------+----------+
```

### Glance (Image Service)
가상 머신 이미지를 관리하는 서비스로, Nova가 VM을 생성할 때 필요한 이미지를 제공한다.

#### 초기화 방법
Glance 설치와 관련한 모든 파드와 설정들을 삭제한다. 참고로, 재설치하는 경우에는 `images-rbd-keyring` Secret도 삭제되므로 새로 생성해야 할 수 있다.
```
citec@k1:~/osh$ helm uninstall glance -n openstack
release "glance" uninstalled

citec@k1:~/osh$ kubectl -n openstack delete pvc -l app.kubernetes.io/name=glance
No resources found

citec@k1:~/osh$ kubectl -n openstack delete pod -l app.kubernetes.io/name=glance --force --grace-period=0
Warning: Immediate deletion does not wait for confirmation that the running resource has been terminated. The resource may continue to run on the cluster indefinitely.
pod "glance-db-init-w4brb" force deleted
pod "glance-db-sync-pz89f" force deleted
pod "glance-ks-endpoints-bvqns" force deleted
pod "glance-ks-service-fpjf6" force deleted
pod "glance-ks-user-5dw7x" force deleted
pod "glance-metadefs-load-c29pg" force deleted
pod "glance-rabbit-init-9lznf" force deleted
pod "glance-storage-init-r444n" force deleted

citec@k1:~/osh$ kubectl -n openstack delete job -l app.kubernetes.io/name=glance
job.batch "glance-db-init" deleted
job.batch "glance-db-sync" deleted
job.batch "glance-ks-endpoints" deleted
job.batch "glance-ks-service" deleted
job.batch "glance-ks-user" deleted
job.batch "glance-metadefs-load" deleted
job.batch "glance-rabbit-init" deleted
job.batch "glance-storage-init" deleted
```

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

#### StorageClass 지정

`glance-values.yaml` 파일을 생성하고, `storage:`를 `swift`에서 `rbd`로 수정하고, `volume:`의 `class_name:`은 `general`에서 `rook-ceph-block`로 수정한다. `endpoints:`의 `object_store:` 아래는 코멘트 처리하고, `pod:`의 `glance_storage_init:` 부분은 추가한다. 마지막에 `job:` 부분도 추가한다.

```
citec@k1:~/osh$ helm show values openstack-helm/glance > openstack/glance-values.yaml
storage: rbd
ceph_client:
  configmap: ceph-etc
  user_secret_name: images-rbd-keyring
conf:
  glance:
    glance_store:
      rbd_store_pool: glance.images
volume:
  class_name: rook-ceph-block
  size: 2Gi
  accessModes:
    - ReadWriteOnce
secrets:
  rbd: images-rbd-keyring
endpoints:
  object_store:
  #  name: swift
  #  namespace: ceph
  glance:
    username: glance
    password: password
    project_name: service
    user_domain_name: default
    project_domain_name: default
pod:
  mounts:
    glance_storage_init:
      glance_storage_init:
        volumeMounts:
          - name: ceph-admin-keyring
            mountPath: /etc/ceph/ceph.client.admin.keyring
            subPath: ceph.client.admin.keyring
        volumes:
          - name: ceph-admin-keyring
            secret:
              secretName: ceph-admin-keyring
job:
  storage_init:
    backoffLimit: 10
```

#### Glance 이미지를 위한 풀 생성 및 초기화 

`glance-values.yaml` 파일에서 Glance 이미지 저장을 위한 `glance:`의 `rbd_store_pool`이 `glance.images`로 설정되어 있는 것을 확인하고, 이 풀을 미리 생성하고 초기화한다.

```
citec@k1:~/osh$ kceph ceph osd pool create glance.images
pool 'glance.images' created
citec@k1:~/osh$ kceph rbd pool init glance.images
citec@k1:~/osh$ kceph ceph osd pool ls
.mgr
replicapool
glance.images
```

```
#### `glance.images` RBD 풀 통계 확인

아래 명령으로 `glance.images` 풀의 통계를 확인할 수 있다.

```
citec@k1:~/osh$ kceph rbd pool stats --pool glance.images
Total Images: 0
Total Snapshots: 0
Provisioned Size: 0 B
```

#### Ceph 사용자 생성 및 권한 부여 

Glance가 `glance.images` 풀에 접근할 수 있도록 `client.glance` 사용자를 생성하고 권한을 설정한다.

`/tmp` 디렉토리에 `client.glance.keyring` 파일을 생성하고, 파드 내부의 `/tmp/client.glance.keyring` 파일을 로컬 환경으로 복사한다. 아래 명령은 `client.glance` 사용자에게 읽기(`r`) 및 쓰기(`rwx`) 권한을 부여한다.
```
citec@k1:~/osh$ kubectl -n rook-ceph exec -it rook-ceph-tools -- ceph auth get-or-create client.glance mon 'allow r' osd 'allow class-read object_prefix rbd_children, allow rwx pool=glance.images' -o /tmp/client.glance.keyring

citec@k1:~/osh$ kubectl -n rook-ceph cp rook-ceph-tools:/tmp/client.glance.keyring ./client.glance.keyring
tar: Removing leading `/' from member names
citec@k1:~/osh$ ls -l client.glance.keyring
-rw-rw-r-- 1 citec citec 64 May  9 13:11 client.glance.keyring
```

복사한 키링 파일을 사용해 Kubernetes Secret을 생성하고, 정상적으로 Secret이 생성되었는지 확인한다.
```
citec@k1:~/osh$ kubectl -n openstack create secret generic images-rbd-keyring --from-file=client.glance.keyring
secret/images-rbd-keyring created

citec@k1:~/osh$ kubectl -n openstack get secret images-rbd-keyring
NAME                 TYPE     DATA   AGE
images-rbd-keyring   Opaque   1      21s
```

사용자와 키링이 생성되었는지 확인한다.
```
citec@k1:~/osh$ kubectl -n rook-ceph exec -it rook-ceph-tools -- ceph auth get client.glance
[client.glance]
        key = AQATgB1oOU5fLBAAcgufVzK/P1GolPoBlZ/4ZA==
        caps mon = "allow r"
        caps osd = "allow class-read object_prefix rbd_children, allow rwx pool=glance.images"
```

Glance의 스토리지 초기화 스크립트는 관리자 권한(`client.admin`)을 필요로 하기에 Ceph 관리자 키링도 Ceph 클러스터에서 가져와 Kubernetes Secret으로 등록한다.
```
citec@k1:~/osh$ kubectl -n rook-ceph exec -it rook-ceph-tools -- ceph auth get client.admin -o /tmp/ceph.client.admin.keyring

citec@k1:~/osh$ kubectl -n rook-ceph cp rook-ceph-tools:/tmp/ceph.client.admin.keyring ./ceph.client.admin.keyring
tar: Removing leading `/' from member names

citec@k1:~/osh$ ls -l ceph.client.admin.keyring
-rw-rw-r-- 1 citec citec 151 May  9 17:36 ceph.client.admin.keyring

citec@k1:~/osh$ kubectl -n openstack create secret generic ceph-admin-keyring --from-file=./ceph.client.admin.keyring
secret/ceph-admin-keyring created
```

ConfigMap을 생성하기 위해 로컬에 `ceph.conf` 파일을 작성해야 한다. 먼저 Ceph 모니터의 엔드포인트 정보와 FSID 정보를 확인한다.
```
citec@k1:~/osh$ kubectl -n rook-ceph get configmap rook-ceph-mon-endpoints -o jsonpath='{.data.data}'
a=10.96.11.1:6789,b=10.96.105.121:6789,c=10.96.99.237:6789

citec@k1:~/osh$ kubectl -n rook-ceph get cephcluster rook-ceph -o jsonpath='{.status.ceph.fsid}'
603c8790-369b-40e8-b42e-751a1e771267
```

이 정보를 바탕으로 `ceph.conf` 파일을 작성한다.
```
citec@k1:~/osh$ tee ceph.conf <<EOF
> [global]
> fsid = 603c8790-369b-40e8-b42e-751a1e771267
> mon_host = 10.96.11.1:6789,10.96.105.121:6789,10.96.99.237:6789
> EOF
[global]
fsid = 603c8790-369b-40e8-b42e-751a1e771267
mon_host = 10.96.11.1:6789,10.96.105.121:6789,10.96.99.237:6789
```

작성한 `ceph.conf` 파일을 `ceph-etc` ConfigMap 생성하여 `openstack` 네임스페이스에 등록한다.
```
citec@k1:~/osh$ kubectl -n openstack create configmap ceph-etc --from-file=ceph.conf
configmap/ceph-etc created
```

#### Keystone 사용자 및 서비스 등록

Glance는 Keystone을 통해 인증되므로, Keystone에 Glance 사용자와 서비스를 등록해야 한다. 

Keystone 사용자를 생성하고 확인한다.
```
citec@k1:~/osh$ openstack user create --domain default --password password glance
+---------------------+----------------------------------+
| Field               | Value                            |
+---------------------+----------------------------------+
| default_project_id  | None                             |
| domain_id           | default                          |
| email               | None                             |
| enabled             | True                             |
| id                  | c808586c42c742d795310712f7cf8636 |
| name                | glance                           |
| description         | None                             |
| password_expires_at | None                             |
+---------------------+----------------------------------+

citec@k1:~/osh$ openstack user list
+----------------------------------+--------+
| ID                               | Name   |
+----------------------------------+--------+
| fce1b2e42e464ed6b15e2ae68f2e0534 | admin  |
| c808586c42c742d795310712f7cf8636 | glance |
+----------------------------------+--------+
```

Glance 사용자에게 Keystone `admin` 역할을 부여한다.
```
citec@k1:~/osh$ openstack role add --project service --user glance admin
No project with a name or ID of 'service' exists.
```
위와 같이 `service` 프로젝트가 없다는 에러가 발생하면, 서비스 사용자들이 속할 수 있는 `service` 프로젝트를 생성하고, `glance` 사용자에게 `admin` 역할을 부여한다.

```
citec@k1:~/osh$ openstack project create --domain default --description "Service Project" service
+-------------+----------------------------------+
| Field       | Value                            |
+-------------+----------------------------------+
| description | Service Project                  |
| domain_id   | default                          |
| enabled     | True                             |
| id          | 7719d5bfa52447ada439feafeb430e1f |
| is_domain   | False                            |
| name        | service                          |
| options     | {}                               |
| parent_id   | default                          |
| tags        | []                               |
+-------------+----------------------------------+
citec@k1:~/osh$ openstack project list
+----------------------------------+---------+
| ID                               | Name    |
+----------------------------------+---------+
| 7719d5bfa52447ada439feafeb430e1f | service |
| d2235125de7d49a193b5951027f780f3 | admin   |
+----------------------------------+---------+
citec@k1:~/osh$ openstack role add --project service --user glance admin
citec@k1:~/osh$ openstack role assignment list --user glance
+----------------------------------+----------------------------------+-------+----------------------------------+--------+--------+-----------+
| Role                             | User                             | Group | Project                          | Domain | System | Inherited |
+----------------------------------+----------------------------------+-------+----------------------------------+--------+--------+-----------+
| c7f325344e944f29ab663392dcac2a59 | c808586c42c742d795310712f7cf8636 |       | 7719d5bfa52447ada439feafeb430e1f |        |        | False     |
+----------------------------------+----------------------------------+-------+----------------------------------+--------+--------+-----------+
```

Glance 서비스를 Keystone에 등록한다.
```
citec@k1:~/osh$ openstack service create --name glance --description "OpenStack Image Service" image
+-------------+----------------------------------+
| Field       | Value                            |
+-------------+----------------------------------+
| id          | 267d629600984bf9800993a444ea3a3d |
| name        | glance                           |
| type        | image                            |
| enabled     | True                             |
| description | OpenStack Image Service          |
+-------------+----------------------------------+
citec@k1:~/osh$ openstack service list
+----------------------------------+----------+----------+
| ID                               | Name     | Type     |
+----------------------------------+----------+----------+
| 267d629600984bf9800993a444ea3a3d | glance   | image    |
| e6f877a654ca4868b5543c2a5e4289f4 | keystone | identity |
+----------------------------------+----------+----------+
```

Glance의 `public`, `internal`, `admin` 엔드포인트를 등록한다.
```
citec@k1:~/osh$ openstack endpoint create --region RegionOne image public http://glance-api.openstack.svc.cluster.local:9292
+--------------+----------------------------------------------------+
| Field        | Value                                              |
+--------------+----------------------------------------------------+
| enabled      | True                                               |
| id           | eb4495b5a7784065bf6792fff80db946                   |
| interface    | public                                             |
| region       | RegionOne                                          |
| region_id    | RegionOne                                          |
| service_id   | 267d629600984bf9800993a444ea3a3d                   |
| service_name | glance                                             |
| service_type | image                                              |
| url          | http://glance-api.openstack.svc.cluster.local:9292 |
+--------------+----------------------------------------------------+
citec@k1:~/osh$ openstack endpoint create --region RegionOne image internal http://glance-api.openstack.svc.cluster.local:9292
+--------------+----------------------------------------------------+
| Field        | Value                                              |
+--------------+----------------------------------------------------+
| enabled      | True                                               |
| id           | e7127effe92445f3815d957cd69b933b                   |
| interface    | internal                                           |
| region       | RegionOne                                          |
| region_id    | RegionOne                                          |
| service_id   | 267d629600984bf9800993a444ea3a3d                   |
| service_name | glance                                             |
| service_type | image                                              |
| url          | http://glance-api.openstack.svc.cluster.local:9292 |
+--------------+----------------------------------------------------+
citec@k1:~/osh$ openstack endpoint create --region RegionOne image admin http://glance-api.openstack.svc.cluster.local:9292
+--------------+----------------------------------------------------+
| Field        | Value                                              |
+--------------+----------------------------------------------------+
| enabled      | True                                               |
| id           | 0f8a63518f6341d485b697f2d064bd3c                   |
| interface    | admin                                              |
| region       | RegionOne                                          |
| region_id    | RegionOne                                          |
| service_id   | 267d629600984bf9800993a444ea3a3d                   |
| service_name | glance                                             |
| service_type | image                                              |
| url          | http://glance-api.openstack.svc.cluster.local:9292 |
+--------------+----------------------------------------------------+
citec@k1:~/osh$ openstack endpoint list
+----------------------------------+-----------+--------------+--------------+---------+-----------+---------------------------------------------------------+
| ID                               | Region    | Service Name | Service Type | Enabled | Interface | URL                                                     |
+----------------------------------+-----------+--------------+--------------+---------+-----------+---------------------------------------------------------+
| 0af30ecd7435438091b3fc40b20b26fc | RegionOne | keystone     | identity     | True    | internal  | http://keystone-api.openstack.svc.cluster.local:5000/v3 |
| 0f8a63518f6341d485b697f2d064bd3c | RegionOne | glance       | image        | True    | admin     | http://glance-api.openstack.svc.cluster.local:9292      |
| 2ae2b66334fd45779c5e341af26e756e | RegionOne | keystone     | identity     | True    | public    | http://keystone.openstack.svc.cluster.local/v3          |
| 52970dfb557e48b085a171feace4fcb4 | RegionOne | keystone     | identity     | True    | admin     | http://keystone.openstack.svc.cluster.local/v3          |
| e7127effe92445f3815d957cd69b933b | RegionOne | glance       | image        | True    | internal  | http://glance-api.openstack.svc.cluster.local:9292      |
| eb4495b5a7784065bf6792fff80db946 | RegionOne | glance       | image        | True    | public    | http://glance-api.openstack.svc.cluster.local:9292      |
+----------------------------------+-----------+--------------+--------------+---------+-----------+---------------------------------------------------------+
```

#### helm dependency build 실행
```
citec@k1:~/osh$ cd openstack-helm
citec@k1:~/osh/openstack-helm$ helm dependency build glance
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "metallb" chart repository
...Successfully got an update from the "ingress-nginx" chart repository
...Successfully got an update from the "rook-release" chart repository
Update Complete. ⎈Happy Helming!⎈
Saving 1 charts
Deleting outdated charts
```

#### 설치
```
helm upgrade --install glance openstack-helm/glance \
  --namespace=openstack \
  --values openstack/glance-values.yaml \
  --set storage=rbd \
  --set job.storage_init.backoffLimit=50 \
  --timeout=600s
