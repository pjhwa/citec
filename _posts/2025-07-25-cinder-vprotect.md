---
title: "OpenStack 환경에서 vProtect 백업 솔루션의 Snapshot 볼륨 Attach 불가 에러"
date: 2025-07-25
tags: [openstack, cinder, vprotect, volume, snapshot, backup, netapp]
categories: [Issues, OpenStack]
---

## 질의

백업 솔루션(vProtect)으로 snapshot 볼륨 Attach 불가로 백업 에러 발생
- Timeout waiting for device [d96acb68-5312-4dc8-8f13-660de3317285] attachment

| 시간 | Openstack Pod | Task |
|----|----|----|
| 02:31:45 | cinder-volume-a | Snapshot으로부터 볼륨(d96acb68) 생성 실패 |
| 02:32:12 | cinder-volume-b | Snapshot으로부터 볼륨(d96acb68) 생성 실패 |
| 02:32:22 | cinder-volume-c | Snapshot으로부터 볼륨(d96acb68) 생성 성공 |
| 02:32:51 | cinder-volume-a | 볼륨 생성 실패로 Reverting 실행하면서 cinder-volume-c 가 생성했던 볼륨(d96acb68)을 Storage가 삭제(NetApp Block Storage Log에서 확인) (Running -> Failure -> Reverting -> Reverted) |
| 02:32:56 | cinder-volume-b | 볼륨 생성 실패로 Reverting 실행하면서 볼륨을 삭제하려고 했으나, 볼륨이 없으므로 에러 |
| 02:35:02 | nova-compute | 백업 VM에서 볼륨(d96acb68)을 Attach 하려고 했으나, 볼륨이 삭제되고 없으므로 attach 실패 |
| 02:45:33 | vProtect (백업 솔루션) | Timeout waiting for device [d96acb68-5312-4dc8-8f13-660de3317285] attachment |

## 문제 원인 분석

OpenStack 환경에서 vProtect 백업 솔루션이 snapshot 기반 백업을 수행할 때, Cinder 서비스의 볼륨 생성 및 attach 과정에서 발생하는 이 에러("Timeout waiting for device [d96acb68-5312-4dc8-8f13-660de3317285] attachment")는 전형적인 race condition(경쟁 조건)으로 보입니다. 이를 자세히 분석해 보겠습니다. 분석은 OpenStack 공식 문서와 관련 버그 리포트, 커뮤니티 논의를 기반으로 하며, 사실 확인을 위해 여러 소스를 검증했습니다.

### 1. 백업 프로세스 개요 (이해를 돕기 위해)
- vProtect는 OpenStack의 Cinder snapshot을 활용해 VM 백업을 수행합니다. 구체적으로:
  - 원본 볼륨의 snapshot 생성.
  - snapshot으로부터 temporary volume(임시 볼륨, 여기서는 ID d96acb68)을 생성.
  - 이 temporary volume을 백업 VM(또는 proxy VM)에 attach하여 데이터 추출.
  - attach 실패 시 timeout 에러 발생.
- 이 과정에서 Cinder의 cinder-volume 서비스가 핵심 역할을 합니다. cinder-volume은 Kubernetes 기반 OpenStack(예: OpenStack Helm 또는 Kolla)에서 여러 파드(a, b, c)로 배포되어 HA(High Availability)를 지원합니다.

### 2. 타임라인 기반 문제 재현
제공된 타임라인을 바탕으로 사건 순서를 분석하면:
- **02:31:45 ~ 02:32:22**: 여러 cinder-volume 파드(a, b, c)가 동시에 snapshot으로부터 볼륨(d96acb68) 생성을 시도. 이는 Cinder scheduler가 작업을 분산 배포하거나, API 호출이 여러 서비스에 도달한 결과입니다.
  - a와 b 파드: 생성 실패 (가능한 이유: NetApp backend의 일시적 지연, 네트워크 문제, 또는 리소스 경쟁).
  - c 파드: 생성 성공 (NetApp Block Storage에서 볼륨 실제 생성).
- **02:32:51**: a 파드가 실패를 감지하고 reverting(되돌리기) 프로세스 실행. 이 과정에서 Cinder DB(데이터베이스)에 저장된 볼륨 상태를 확인하고, "실패"로 간주해 볼륨을 삭제. 하지만 c 파드가 이미 생성한 볼륨을 삭제하게 되어 전체 작업이 망가짐.
- **02:32:56**: b 파드도 reverting 시도하지만, 이미 삭제된 볼륨이 없어 에러.
- **02:35:02 ~ 02:45:33**: nova-compute가 attach 시도하지만 볼륨이 삭제되어 실패. vProtect가 이를 기다리다 timeout.

이 현상의 핵심은 **cinder-volume 파드들 간의 상태 공유 및 동기화(sync) 부족**입니다. OpenStack Cinder는 기본적으로 MySQL 같은 공유 DB와 RabbitMQ 메시지 큐를 통해 상태를 공유하지만, 고부하 또는 active-active HA 구성에서 timing issue(타이밍 문제)가 발생하면 race condition이 생깁니다. 예를 들어:
- 한 파드가 볼륨을 생성 중일 때 다른 파드가 실패로 간주하고 삭제.
- 이는 분산 환경에서 lock(잠금) 메커니즘이 제대로 작동하지 않을 때 흔합니다.

### 3. 근본 원인 검증
- **분산 lock 미사용**: Cinder는 Tooz 라이브러리를 통해 distributed locking(분산 잠금)을 지원합니다. 기본 설정(backend_url = file://$state_path)은 local file lock을 사용해 파드 간 공유되지 않습니다. 이는 single-node 환경에 적합하지만, multi-pod HA에서 race를 유발합니다.

- **HA active-active 구성 문제**: 여러 cinder-volume 서비스가 동시에 작동할 때, coordination(조정) backend가 없으면 볼륨 생성/삭제 작업이 충돌합니다. NetApp backend 같은 공유 스토리지에서 더 두드러지며, 고부하 시(예: concurrent backups) 자주 발생.

- **vProtect 측면**: vProtect 자체는 OpenStack API를 호출하므로, Cinder의 에러가 직접 전달됩니다. 검색 결과, 유사 에러는 Cinder attach 실패에서 비롯되며, vProtect 설정(예: timeout 증가)만으로는 근본 해결 안 됨.

- 비판적 검증: 일부 소스(예: 버그 리포트)에서 비슷한 race가 Kolla나 Ceph backend에서도 보고되지만, NetApp 특화는 아니며 일반 Cinder 문제. 업그레이드 없이 설정 변경으로 해결 가능하나, production 환경에서 테스트 필수(다운타임 유발 가능).

## 해결 방법

OpenStack 버전 업그레이드 없이 설정 변경으로 문제를 해결할 수 있습니다. 핵심은 Cinder의 coordination backend를 distributed(분산)로 전환해 파드 간 sync를 강화하는 것입니다. 이는 Tooz를 활용하며, etcd, Redis, ZooKeeper 같은 backend를 사용합니다. 아래는 단계별 가이드로, OpenStack 공식 docs를 기반으로 설명합니다. 모든 변경 후 cinder-volume 파드 재시작 필요.

### 1. 사전 준비
- **Coordination backend 설치**: 분산 lock을 위해 별도 서비스 필요.
  - 추천: etcd (간단하고 OpenStack에서 널리 사용). Kubernetes 클러스터에 etcd 이미 배포되어 있으면 재사용.
  - 설치 예: `etcd` 서버를 별도 노드에 배포 (포트 2379 열기).
- **위험 검증**: 변경 시 서비스 중단 가능성 있음. staging 환경에서 먼저 테스트. 백업 데이터 무결성 확인.

### 2. cinder.conf 수정
모든 cinder-volume 파드의 `/etc/cinder/cinder.conf` 파일을 수정합니다. (Kubernetes라면 ConfigMap 업데이트.)

- **[coordination] 섹션 추가/수정**:
```
[coordination]
backend_url = etcd3://<etcd-host-ip>:2379
```
  - `backend_url`: 분산 backend 지정. 예:
    - etcd: `etcd3://etcd-host:2379` (etcd v3 프로토콜).
    - Redis: `redis://redis-host:6379` (Redis 클러스터 추천 for HA).
    - ZooKeeper: `kazoo://zk-host:2181`.
  - 기본(file://)에서 변경하면 local lock이 distributed로 전환되어 파드 간 lock 공유.

- **관련 옵션 튜닝 (선택적, race 완화)**:
```
[DEFAULT]
periodic_interval = 30  # 주기적 작업 간격 줄여 상태 sync 빈도 증가 (기본 60초).
backend_stats_polling_interval = 30  # backend 상태 폴링 간격 줄임 (NetApp 지연 완화).
init_host_max_objects_retrieval = 100  # 초기화 시 DB 배치 크기 제한 (메모리 과부하 방지).
  
[oslo_concurrency]
lock_path = /var/lib/cinder/lock  # lock 디렉토리 명시 (분산 backend와 병행).
```
  - 이는 lock과 polling을 강화해 reverting 시 상태 확인을 더 자주 함.

- **클러스터 모드 활성화 (HA 강화)**:
```
[DEFAULT]
cluster = my-cinder-cluster  # 모든 cinder-volume 파드에 동일 이름 지정. active-active HA 지원.
```
  - 여러 서비스를 클러스터로 그룹화해 작업 분산.

### 3. 적용 및 테스트
- **재시작**: `systemctl restart openstack-cinder-volume` 또는 파드 rolling restart.
- **로그 확인**: cinder-volume 로그에서 "Using coordination backend: etcd3" 같은 메시지 확인. race 관련 에러 감소 여부 모니터링.
- **vProtect 테스트**: 백업 작업 재시도. attach timeout이 사라지면 성공.
- **대안 만약 실패 시**: 
  - vProtect에서 attach timeout 증가 (vProtect config: `attach_timeout_seconds` 조정, 기본 600초).
  - Cinder scheduler filter 튜닝 (cinder-scheduler.conf: `volume_number_per_host` 제한으로 작업 분산 제어).
- 비판적 검증: 이 설정은 Rocky 버전 이후 안정적이나, 오래된 버전(예: Queens)에서는 Tooz 버그 가능. OpenStack releasenotes 확인.

