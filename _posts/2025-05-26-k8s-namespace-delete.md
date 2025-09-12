---
title: "Kubernetes 네임스페이스 강제 삭제 방법"
date: 2025-05-26
tags: [kubernetes, ceph, force, delete]
categories: [Howtos, Kubernetes]
---

# `rook-ceph` 네임스페이스를 강제로 삭제하는 방법

`rook-ceph` 네임스페이스가 `Terminating` 상태에 머물러 있으며 삭제가 완료되지 않고 있습니다. 이는 네임스페이스 내에 남아 있는 리소스(`secrets`)와 파이널라이저(`ceph.rook.io/disaster-protection`) 때문에 발생하는 문제입니다. 아래에서 `rook-ceph` 네임스페이스를 강제로 삭제하는 방법을 단계별로 설명드리겠습니다.

---

## **로그**

```
citec@k1:~/osh$ kubectl get namespaces
NAME              STATUS        AGE
ceph              Active        17d
default           Active        17d
kube-node-lease   Active        17d
kube-public       Active        17d
kube-system       Active        17d
metallb-system    Active        17d
openstack         Active        17d
rook-ceph         Terminating   2d22h
citec@k1:~/osh$ kubectl describe namespace rook-ceph
Name:         rook-ceph
Labels:       kubernetes.io/metadata.name=rook-ceph
Annotations:  <none>
Status:       Terminating
Conditions:
  Type                                         Status  LastTransitionTime               Reason                Message
  ----                                         ------  ------------------               ------                -------
  NamespaceDeletionDiscoveryFailure            False   Mon, 26 May 2025 09:10:05 +0900  ResourcesDiscovered   All resources successfully discovered
  NamespaceDeletionGroupVersionParsingFailure  False   Mon, 26 May 2025 09:10:05 +0900  ParsedGroupVersions   All legacy kube types successfully parsed
  NamespaceDeletionContentFailure              False   Mon, 26 May 2025 09:10:05 +0900  ContentDeleted        All content successfully deleted, may be waiting on finalization
  NamespaceContentRemaining                    True    Mon, 26 May 2025 09:10:44 +0900  SomeResourcesRemain   Some resources are remaining: secrets. has 1 resource instances
  NamespaceFinalizersRemaining                 True    Mon, 26 May 2025 09:10:44 +0900  SomeFinalizersRemain  Some content in the namespace has finalizers remaining: ceph.rook.io/disaster-protection in 1 resource instances

No resource quota.

No LimitRange resource.
```

## **문제 상황**
`kubectl describe namespace rook-ceph` 명령어의 출력에서 확인된 주요 정보는 다음과 같습니다:
- **상태**: `Terminating`
- **조건**:
  - `NamespaceContentRemaining`: `True` - `secrets` 리소스가 1개 남아 있음
  - `NamespaceFinalizersRemaining`: `True` - `ceph.rook.io/disaster-protection` 파이널라이저가 남아 있음
- **오류 메시지**:
  - `Some resources are remaining: secrets. has 1 resource instances`
  - `Some content in the namespace has finalizers remaining: ceph.rook.io/disaster-protection in 1 resource instances`

이 상황은 네임스페이스 내 리소스가 삭제되지 않았거나, 파이널라이저로 인해 삭제가 지연되고 있음을 의미합니다. 이를 해결하려면 남아 있는 리소스를 삭제하고 파이널라이저를 제거해야 합니다.

---

## **해결 방법**

### **1. 남아 있는 리소스 확인 및 삭제**
네임스페이스 내에 남아 있는 리소스, 특히 `secrets`를 확인하고 삭제합니다.

- 모든 리소스 확인:
  ```bash
  kubectl get all --namespace=rook-ceph
  kubectl get secrets --namespace=rook-ceph
  ```
  출력에서 `secrets` 리소스의 이름을 확인하세요 (예: `rook-ceph-secret`).

- `secrets` 삭제:
  ```bash
  kubectl delete secrets <secret-name> --namespace=rook-ceph
  ```
  `<secret-name>`은 위 명령어 출력에서 확인한 실제 이름으로 대체하세요.

### **2. 파이널라이저 제거**
Rook-Ceph 관련 리소스(예: `CephCluster`, `CephBlockPool`)에 설정된 파이널라이저(`ceph.rook.io/disaster-protection`)를 제거해야 합니다.

- 파이널라이저가 있는 리소스 확인:
  ```bash
  kubectl get cephcluster --namespace=rook-ceph -o json | jq '.items[].metadata.finalizers'
  kubectl get cephblockpool --namespace=rook-ceph -o json | jq '.items[].metadata.finalizers'
  ```
  출력에서 파이널라이저가 있는 리소스(예: `cephcluster/my-cluster`)를 찾습니다.

- 파이널라이저 제거:
  ```bash
  kubectl patch cephcluster <cluster-name> --namespace=rook-ceph --type merge -p '{"metadata":{"finalizers":[]}}'
  ```
  `<cluster-name>`은 확인한 리소스 이름으로 대체하세요. 다른 리소스(예: `cephblockpool`)에도 동일하게 적용합니다.

### **3. 네임스페이스 파이널라이저 제거**
네임스페이스 자체에 파이널라이저가 남아 있을 수 있으므로, 이를 제거합니다.

- 네임스페이스 정보를 JSON 파일로 추출:
  ```bash
  kubectl get namespace rook-ceph -o json > ns.json
  ```

- `ns.json` 파일을 편집하여 `spec.finalizers`를 빈 배열(`[]`)로 설정:
  ```json
  {
    "apiVersion": "v1",
    "kind": "Namespace",
    "metadata": {
      "name": "rook-ceph"
    },
    "spec": {
      "finalizers": []
    },
    "status": {
      "phase": "Terminating"
    }
  }
  ```

- 수정된 JSON을 적용:
  ```bash
  kubectl replace --raw /api/v1/namespaces/rook-ceph/finalize -f ns.json
  ```

### **4. 네임스페이스 강제 삭제**
위 단계를 완료한 후, 네임스페이스를 강제로 삭제합니다:
```bash
kubectl delete namespace rook-ceph --force --grace-period=0
```

- 삭제 여부 확인:
  ```bash
  kubectl get namespaces
  ```
  `rook-ceph`가 목록에서 사라졌는지 확인하세요.

