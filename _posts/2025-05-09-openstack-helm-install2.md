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

### CoreDNS RBAC 권한 설정
CoreDNS가 Kubernetes 클러스터에서 제대로 작동하려면 API 서버에서 특정 리소스(`endpoints, services, pods, namespaces, endpointslices 등)를 조회할 수 있는 권한이 필요하다. 이를 위해 RBAC(Role-Based Access Control)를 설정해야 하며, 아래 단계에 따라 ClusterRole과 ClusterRoleBinding을 생성하고 적용한다.

#### ClusterRole 설정 
ClusterRole은 CoreDNS가 접근할 수 있는 리소스와 허용된 작업(verbs)을 정의한다. CoreDNS는 리소스를 실시간으로 동기화하기 위해 `list`와 `watch` 권한이 필요하다.

```
citec@k1:~/osh$ cat coredns-clusterrole.yaml <<EOF
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
EOF
```

ClusterRoleBinding은 위에서 정의한 ClusterRole을 CoreDNS의 ServiceAccount에 연결한다. CoreDNS는 일반적으로 `kube-system` 네임스페이스에서 실행되며, 기본 ServiceAccount 이름은 `coredns`이다.

```
citec@k1:~/osh$ cat coredns-clusterrolebinding.yaml <<EOF
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
EOF
```

위의 두 YAML을 파일로 저장한 후 `kubectl`로 적용한다.

```
citec@k1:~/osh$ kubectl apply -f coredns-clusterrole.yaml
clusterrole.rbac.authorization.k8s.io/coredns created
citec@k1:~/osh$ kubectl apply -f coredns-clusterrolebinding.yaml
clusterrolebinding.rbac.authorization.k8s.io/coredns created
```

RBAC 설정이 적용된 후 CoreDNS가 새로운 권한을 즉시 반영하도록 하려면 CoreDNS Deployment를 재시작한다.

```
citec@k1:~/osh$ kubectl -n kube-system rollout restart deployment coredns
deployment.apps/coredns restarted
```

### Rook-Ceph 모니터 이름 변경
Rook은 기본적으로 모니터 노드의 수를 유지하려고 하며, 장애 발생 시 자동으로 새로운 모니터를 생성한다. 이 과정에서 이름이 순차적으로 변경될 수 있다. Rook-Ceph 모니터 이름이 변경될 때마다 이를 참조하는 ConfigMap을 수동으로 업데이트해야 하는데, 이를 자동화하는 스크립트 작성이 필요하다.

#### 업데이트 스크립트 작성
Rook-Ceph 모니터 정보가 `ceph-etc` ConfigMap에 등록되어있다고 가정한다. (본 문서의 설정이다.)

```
citec@k1:~/osh$ cat update-ceph-config.sh <<EOF
#!/bin/bash

# Rook-Ceph 모니터 서비스 이름 가져오기
MONITORS=$(kubectl -n rook-ceph get svc -l app=rook-ceph-mon -o jsonpath='{.items[*].metadata.name}')

# mon_host 문자열 생성 (형식: "mon1:6789,mon2:6789,mon3:6789")
MON_HOST=""
for MON in $MONITORS; do
  IP=$(kubectl -n rook-ceph get svc $MON -o jsonpath='{.spec.clusterIP}')
  MON_HOST="${MON_HOST}${MON}.rook-ceph.svc.cluster.local:6789,"
done
MON_HOST=${MON_HOST%,}  # 마지막 쉼표 제거

# ceph.conf 내용 생성
CEPH_CONF="[global]\nmon_host = $MON_HOST"

# ceph-etc ConfigMap 업데이트
kubectl -n openstack patch configmap ceph-etc --type merge -p "{\"data\":{\"ceph.conf\":\"$CEPH_CONF\"}}"

echo "ceph-etc ConfigMap updated with mon_host: $MON_HOST"
EOF

citec@k1:~/osh$ chmod +x update-ceph-config.sh 
```

#### CronJob으로 자동화
Kubernetes CronJob을 설정하여 스크립트를 주기적으로 실행하도록 한다.
```
citec@k1:~/osh$ cat update-ceph-config-cronjob.yaml <<EOF
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
EOF
```

#### 스크립트를 ConfigMap으로 등록 및 적용
CronJob에서 사용할 스크립트를 ConfigMap으로 생성한다. CronJob YAML을 적용한다.

```
citec@k1:~/osh$ kubectl -n openstack create configmap update-ceph-config-script --from-file=update-ceph-config.sh
configmap/update-ceph-config-script created

citec@k1:~/osh$ kubectl apply -f update-ceph-config-cronjob.yaml
cronjob.batch/update-ceph-config created
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

Glance가 Ceph에 연결할 수 있도록 `images-rbd-keyring` Secret에 올바른 키가 설치되어있는지 확인하고 제대로 안되어있다면 설정한다.
```
citec@k1:~/osh$ kubectl -n openstack get secret images-rbd-keyring -o jsonpath='{.data.key}' | base64 -d
citec@k1:~/osh$

citec@k1:~/osh$ echo -n "AQATgB1oOU5fLBAAcgufVzK/P1GolPoBlZ/4ZA==" | base64
QVFBVGdCMW9PVTVmTEJBQWNndWZWeksvUDFHb2xQb0JsWi80WkE9PQ==
citec@k1:~/osh$ kubectl -n openstack patch secret images-rbd-keyring --type='json' -p='[{"op": "replace", "path": "/data/key", "value": "QVFBVGdCMW9PVTVmTEJBQWNndWZWeksvUDFHb2xQb0JsWi80WkE9PQ=="}]'
secret/images-rbd-keyring patched
citec@k1:~/osh$ kubectl -n openstack get secret images-rbd-keyring -o jsonpath='{.data.key}' | base64 -d
AQATgB1oOU5fLBAAcgufVzK/P1GolPoBlZ/4ZA==
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

Ceph 클러스터에 연결하려면 관리자 키링이 필요하다. 생성된 ConfigMap을 수정 모드로 들어가 관리자 키링(`ceph.client.admin.keyring`)을 추가한다.
```
citec@k1:~/osh$ kubectl -n openstack edit configmap ceph-etc
# Please edit the object below. Lines beginning with a '#' will be ignored,
# and an empty file will abort the edit. If an error occurs while saving this file will be
# reopened with the relevant failures.
#
apiVersion: v1
data:
  ceph.conf: |
    [global]
    fsid = 603c8790-369b-40e8-b42e-751a1e771267
    #    mon_host = 10.96.11.1:6789,10.96.105.121:6789,10.96.99.237:6789
    mon_host = rook-ceph-mon-b.rook-ceph.svc.cluster.local:6789,rook-ceph-mon-c.rook-ceph.svc.cluster.local:6789,rook-ceph-mon-d.rook-ceph.svc.cluster.local:6789
  ceph.client.admin.keyring: |
    [client.admin]
		key = AQCVSBxorL2XEhAAn575xTxB7dFlbYU6zn4fjQ==
kind: ConfigMap
metadata:
  creationTimestamp: "2025-05-09T07:47:47Z"
  name: ceph-etc
  namespace: openstack
  resourceVersion: "2655948"
  uid: ed2d50e7-2596-49df-8a3b-91c2dddd0c70

configmap/ceph-etc edited
```

수정 후 확인 방법은 아래와 같다.
```
citec@k1:~/osh$ kubectl -n openstack get configmap ceph-etc -o yaml
apiVersion: v1
data:
  ceph.client.admin.keyring: |
    [client.admin]
		key = AQCVSBxorL2XEhAAn575xTxB7dFlbYU6zn4fjQ==
  ceph.conf: |
    [global]
    fsid = 603c8790-369b-40e8-b42e-751a1e771267
    #    mon_host = 10.96.11.1:6789,10.96.105.121:6789,10.96.99.237:6789
    mon_host = rook-ceph-mon-b.rook-ceph.svc.cluster.local:6789,rook-ceph-mon-c.rook-ceph.svc.cluster.local:6789,rook-ceph-mon-d.rook-ceph.svc.cluster.local:6789
kind: ConfigMap
metadata:
  creationTimestamp: "2025-05-09T07:47:47Z"
  name: ceph-etc
  namespace: openstack
  resourceVersion: "2657555"
  uid: ed2d50e7-2596-49df-8a3b-91c2dddd0c70
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
citec@k1:~/osh$ helm upgrade --install glance openstack-helm/glance \
  --namespace=openstack \
  --set storage=rbd \
  --set job.storage_init.backoffLimit=50 \
  --timeout=600s
Release "glance" does not exist. Installing it now.
NAME: glance
LAST DEPLOYED: Tue May 13 11:10:51 2025
NAMESPACE: openstack
STATUS: deployed
REVISION: 1
```

#### 상태 확인 
```
citec@k1:~$ kubectl -n openstack get pods -l application=glance
NAME                          READY   STATUS      RESTARTS   AGE
glance-api-6db69c6b47-hzgdh   1/1     Running     0          2m58s
glance-bootstrap-8xptd        0/1     Completed   0          62s
glance-db-init-htbnx          0/1     Completed   0          2m53s
glance-db-sync-d724f          0/1     Completed   0          2m43s
glance-ks-endpoints-qss44     0/3     Completed   0          2m13s
glance-ks-service-2n46c       0/1     Completed   0          2m25s
glance-ks-user-w6m54          0/1     Completed   0          111s
glance-metadefs-load-vhkft    0/1     Completed   0          87s
glance-rabbit-init-q442f      0/1     Completed   0          2m32s
glance-storage-init-frt67     0/1     Completed   0          76s
```
`glance`에 등록된 이미지를 확인해 서비스가 제대로 작동하는지 점검한다.
```
citec@k1:~/osh$ openstack image list
+--------------------------------------+---------------------+--------+
| ID                                   | Name                | Status |
+--------------------------------------+---------------------+--------+
| 31e410c9-7e2b-4627-8280-b30817f8576c | Cirros 0.6.2 64-bit | active |
+--------------------------------------+---------------------+--------+
```

### Placement 

리소스 추적 및 할당을 관리하며, Nova가 인스턴스를 배치할 때 사용된다.

#### helm dependency build 실행
```
citec@k1:~/osh$ cd openstack-helm
citec@k1:~/osh/openstack-helm$ helm dependency build placement
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
citec@k1:~/osh$ helm upgrade --install placement openstack-helm/placement \
  --namespace=openstack \
  --timeout=600s
Release "placement" does not exist. Installing it now.
NAME: placement
LAST DEPLOYED: Tue May 13 12:06:00 2025
NAMESPACE: openstack
STATUS: deployed
REVISION: 1
TEST SUITE: None
```

#### 상태 확인
```
citec@k1:~/osh$ kubectl -n openstack get pods -l application=placement
NAME                             READY   STATUS      RESTARTS   AGE
placement-api-67b8564b77-7bj2r   1/1     Running     0          6m38s
placement-db-init-stqjs          0/1     Completed   0          6m38s
placement-db-sync-lpr5g          0/1     Completed   0          6m30s
placement-ks-endpoints-bt8v7     0/3     Completed   0          2m7s
placement-ks-service-4fjj2       0/1     Completed   0          3m24s
placement-ks-user-6r44r          0/1     Completed   0          2m38s
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

#### 노드 레이블 적용
`openvswitch=enabled` 레이블을 모든 노드에 적용한다.

```
citec@k1:~/osh$ for node in k1 k2 k3 k4; do
  kubectl label node $node openvswitch=enabled --overwrite
done
node/k1 labeled
node/k2 labeled
node/k3 labeled
node/k4 labeled
```

#### 설치 
```
citec@k1:~/osh$ cd openstack-helm
citec@k1:~/osh/openstack-helm$ helm dependency build openvswitch
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "metallb" chart repository
...Successfully got an update from the "rook-release" chart repository
...Successfully got an update from the "ingress-nginx" chart repository
Update Complete. ⎈Happy Helming!⎈
Saving 1 charts
Deleting outdated charts

citec@k1:~/osh/openstack-helm$ cd ~/osh
citec@k1:~/osh$ helm upgrade --install openvswitch openstack-helm/openvswitch \
  --namespace openstack \
  --timeout=600s
Release "openvswitch" does not exist. Installing it now.
NAME: openvswitch
LAST DEPLOYED: Fri May 16 10:57:48 2025
NAMESPACE: openstack
STATUS: deployed
REVISION: 1
TEST SUITE: None
```

#### 상태 확인 

openvswtich 파드가 모두 `Running` 상태인 것을 확인한다. `READY`에 `2/2`여야 한다.
```
citec@k1:~/osh$ kubectl -n openstack get pods -l application=openvswitch -o wide
NAME                READY   STATUS    RESTARTS   AGE   IP             NODE   NOMINATED NODE   READINESS GATES
openvswitch-crt4k   2/2     Running   0          24m   172.16.2.52    k2     <none>           <none>
openvswitch-gpzc8   2/2     Running   0          24m   172.16.2.149   k1     <none>           <none>
openvswitch-kv85f   2/2     Running   0          24m   172.16.2.161   k4     <none>           <none>
openvswitch-wnjdc   2/2     Running   0          24m   172.16.2.223   k3     <none>           <none>
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
각 노드에 `br-ex` 브리지가 제대로 생성되어있는지 확인한다.
```
citec@k1:~/osh$ for node in k1 k2 k3 k4
> do
> ssh citec@$node "sudo ovs-vsctl show"
> done
6b83d441-aafc-4f24-a271-dc9a47adcd1b
    Bridge br-ex
        Port br-ex
            Interface br-ex
                type: internal
4c750c1d-decd-440d-b0c2-a14ad8108868
    Bridge br-ex
        Port br-ex
            Interface br-ex
                type: internal
b0c1ca6f-6bdb-4e24-bf5f-eb924aa9688d
    Bridge br-ex
        Port br-ex
            Interface br-ex
                type: internal
ba6452d0-4347-4b98-ba0c-d2227880ab40
    Bridge br-ex
        Port br-ex
            Interface br-ex
                type: internal
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

`libvirt`가 Ceph RBD에 접근하기 위해 Ceph 클라이언트 키를 생성하고, 키링 파일을 로컬로 복사한다.
```
citec@k1:~/osh$ kubectl -n rook-ceph exec -it rook-ceph-tools -- ceph auth get-or-create client.openstack mon 'allow r' osd 'allow rwx pool=rbd' -o /tmp/ceph.client.openstack.keyring

citec@k1:~/osh$ kubectl -n rook-ceph cp rook-ceph-tools:/tmp/ceph.client.openstack.keyring ./ceph.client.openstack.keyring
tar: Removing leading `/' from member names
```

키를 Secret으로 등록한다.
```
citec@k1:~/osh$ kubectl -n openstack create secret generic ceph-client-openstack \
  --from-file=ceph.client.openstack.keyring=./ceph.client.openstack.keyring
secret/ceph-client-openstack created
```

#### 설치 
```
citec@k1:~/osh$ cd openstack-helm
citec@k1:~/osh/openstack-helm$ helm dependency build libvirt
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "ingress-nginx" chart repository
...Successfully got an update from the "metallb" chart repository
...Successfully got an update from the "rook-release" chart repository
Update Complete. ⎈Happy Helming!⎈
Saving 1 charts
Deleting outdated charts

citec@k1:~/osh/openstack-helm$ cd ~/osh
citec@k1:~/osh$ helm upgrade --install libvirt openstack-helm/libvirt \
  --namespace openstack \
  --timeout=600s
Release "libvirt" does not exist. Installing it now.
NAME: libvirt
LAST DEPLOYED: Fri May 16 15:07:43 2025
NAMESPACE: openstack
STATUS: deployed
REVISION: 1
TEST SUITE: None
```

#### 상태 확인
```
citec@k1:~/osh$ kubectl -n openstack get pods -l application=libvirt
NAME                            READY   STATUS    RESTARTS   AGE
libvirt-libvirt-default-pnhq9   1/1     Running   0          116s
libvirt-libvirt-default-r6rsh   1/1     Running   0          116s
libvirt-libvirt-default-rg6th   1/1     Running   0          116s
```

파드 로그를 보고 성공적으로 시작되었다는 메시지를 확인한다.
```
citec@k1:~/osh$ kubectl -n openstack logs libvirt-libvirt-default-pnhq9 | tail -n 5
Defaulted container "libvirt" out of: libvirt, init (init), init-dynamic-options (init), ceph-admin-keyring-placement (init), ceph-keyring-placement (init)
+ '[' -n '' ']'
+ rm -f /var/run/libvirtd.pid
+ [[ -c /dev/kvm ]]
+ systemd-run --scope --slice=system libvirtd --listen
Running scope as unit: run-r01e24a9b8fe742d8a1e21b898e78f778.scope
```

`virsh`로 연결 테스트를 수행해 오류가 없으면 성공이다.
```
citec@k1:~/osh$ kubectl -n openstack exec -it libvirt-libvirt-default-pnhq9 -- /bin/bash
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
citec@k1:~/osh$ cd openstack-helm/
citec@k1:~/osh/openstack-helm$ helm dependency build neutron
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "metallb" chart repository
...Successfully got an update from the "ingress-nginx" chart repository
...Successfully got an update from the "rook-release" chart repository
Update Complete. ⎈Happy Helming!⎈
Saving 1 charts
Deleting outdated charts

citec@k1:~/osh$ helm upgrade --install neutron openstack-helm/neutron \
  --namespace openstack \
  --set dependency_service=mariadb \
  --timeout=600s
Release "neutron" does not exist. Installing it now.
NAME: neutron
LAST DEPLOYED: Fri May 16 16:33:10 2025
NAMESPACE: openstack
STATUS: deployed
REVISION: 1
```

#### 상태 확인
```
citec@k1:~/osh$ kubectl -n openstack get pods -l application=neutron
NAME                                       READY   STATUS      RESTARTS   AGE
neutron-db-init-kqlpw                      0/1     Completed   0          5m45s
neutron-db-sync-rl4rc                      0/1     Completed   0          5m33s
neutron-dhcp-agent-default-755kt           1/1     Running     0          5m45s
neutron-dhcp-agent-default-xxnc8           1/1     Running     0          5m45s
neutron-dhcp-agent-default-z922z           1/1     Running     0          5m45s
neutron-ks-endpoints-7c27h                 0/3     Completed   0          3m39s
neutron-ks-service-82qhd                   0/1     Completed   0          3m53s
neutron-ks-user-q5j5s                      0/1     Completed   0          3m14s
neutron-l3-agent-default-cmpw4             1/1     Running     0          5m45s
neutron-l3-agent-default-qlqzs             1/1     Running     0          5m45s
neutron-l3-agent-default-tbmlv             1/1     Running     0          5m45s
neutron-metadata-agent-default-fjvnp       1/1     Running     0          5m46s
neutron-metadata-agent-default-fls9s       1/1     Running     0          5m46s
neutron-metadata-agent-default-gwnc6       1/1     Running     0          5m46s
neutron-netns-cleanup-cron-default-9dztx   1/1     Running     0          5m45s
neutron-netns-cleanup-cron-default-gdng6   1/1     Running     0          5m45s
neutron-netns-cleanup-cron-default-pt422   1/1     Running     0          5m45s
neutron-ovs-agent-default-jsf79            1/1     Running     0          5m45s
neutron-ovs-agent-default-lhfnc            1/1     Running     0          5m46s
neutron-ovs-agent-default-x9jng            1/1     Running     0          5m46s
neutron-ovs-agent-default-zwgmh            1/1     Running     0          5m46s
neutron-rabbit-init-lvfwd                  0/1     Completed   0          4m1s
neutron-rpc-server-54b9b8558f-hj7td        1/1     Running     0          5m46s
neutron-server-58dc66555f-8djht            1/1     Running     0          5m46s

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
  
  
  
  
  
  
  
  
  
  
  
kubectl get nodes --show-labels
kubectl -n openstack get secrets
kubectl -n openstack get services
kubectl -n openstack get pods




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
```

kubectl -n openstack delete pod nova-compute-default-d298h
kubectl -n openstack get pods -l application=nova

kubectl -n openstack logs nova-compute-default-lf7dr -c ceph-keyring-placement -f
