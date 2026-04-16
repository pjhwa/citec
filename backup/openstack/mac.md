# OpenStack 환경에서 MAC(Mandatory Access Control) 적용 검토

## 1. 현황 분석

| 구분 | 상태 | 비고 |
|------|------|------|
| AppArmor | **부분 활성** | systemctl=disabled, 일부 프로파일 로드됨 |
| sVirt | **미설정** | libvirt security_driver 미지정 |
| 운영 환경 | **Production** | 운영 중인 OpenStack |

---

## 2. 결론: **적용 가능하나, 단계적 접근 필수**

MAC을 운영 중인 환경에 적용하는 것은 **기술적으로 가능**하다. 다만 잘못된 적용 시 VM 부팅 실패, 서비스 중단 등 심각한 장애가 발생할 수 있어 **신중한 단계적 접근**이 필요하다.

---

## 3. 적용 단계 (권장 순서)

### Phase 1: 사전 준비 (1-2주)
```bash
# 1. 현재 AppArmor 상태 정밀 진단
aa-status
cat /sys/kernel/security/apparmor/profiles

# 2. 로드된 프로파일 확인 (어떤 것이 enforce/complain 모드인지)
aa-status --json

# 3. libvirt 관련 AppArmor 프로파일 존재 여부
ls -la /etc/apparmor.d/libvirt/
ls -la /etc/apparmor.d/abstractions/libvirt*
```

### Phase 2: Complain Mode 테스트 (2-4주)
```bash
# 1. AppArmor 서비스 활성화 (재부팅 없이)
systemctl enable apparmor
systemctl start apparmor

# 2. libvirt 프로파일을 complain 모드로 설정 (차단 없이 로깅만)
aa-complain /etc/apparmor.d/usr.sbin.libvirtd
aa-complain /etc/apparmor.d/libvirt/TEMPLATE.qemu

# 3. 로그 모니터링 (위반 사항 수집)
tail -f /var/log/syslog | grep apparmor
# 또는
journalctl -f | grep apparmor
```

### Phase 3: sVirt 설정 (complain 모드 안정화 후)
```bash
# /etc/libvirt/qemu.conf 수정
security_driver = "apparmor"
security_default_confined = 1
security_require_confined = 0  # 초기에는 0으로 시작

# libvirt 재시작 (기존 VM 영향 없음, 신규 VM부터 적용)
systemctl restart libvirtd
```

### Phase 4: Enforce Mode 전환 (충분한 테스트 후)
```bash
# 1. 개별 프로파일 enforce 전환
aa-enforce /etc/apparmor.d/usr.sbin.libvirtd

# 2. 신규 VM으로 테스트
# 3. 문제 없으면 전체 적용
```

---

## 4. 영향도 분석

### 높은 위험 (🔴)
| 영향 항목 | 설명 | 완화 방안 |
|-----------|------|-----------|
| VM 부팅 실패 | AppArmor가 QEMU의 디스크/네트워크 접근 차단 | Complain 모드 선행 |
| Live Migration 실패 | 마이그레이션 시 임시 파일 접근 차단 가능 | 프로파일 사전 커스터마이징 |
| Cinder 볼륨 연결 실패 | iSCSI/NFS 경로 접근 차단 | 스토리지 경로 프로파일 추가 |

### 중간 위험 (🟡)
| 영향 항목 | 설명 |
|-----------|------|
| 성능 저하 | 미미함 (1-3% 이내), 대부분 무시 가능 |
| 운영 복잡도 증가 | 새로운 스토리지/네트워크 추가 시 프로파일 업데이트 필요 |

### 낮은 위험 (🟢)
| 영향 항목 | 설명 |
|-----------|------|
| 기존 VM | libvirt 재시작 시 기존 VM에는 영향 없음 (신규 VM부터 적용) |

---

## 5. 불가능한 시나리오

MAC 적용이 **현실적으로 어려운** 경우:

1. **커스텀 QEMU/libvirt 빌드 사용 시**: 표준 AppArmor 프로파일과 경로 불일치
2. **비표준 스토리지 경로**: `/var/lib/nova/instances` 외 경로 사용 시 프로파일 대폭 수정 필요
3. **GPU Passthrough 사용 환경**: VFIO 관련 복잡한 프로파일 커스터마이징 필요

---

## 6. 권장 Action Items

| 우선순위 | 항목 | 담당 |
|----------|------|------|
| 1 | 테스트 환경에서 Phase 1-4 전체 검증 | CI-TEC |
| 2 | 현재 로드된 AppArmor 프로파일 목록 문서화 | 인프라팀 |
| 3 | Complain 모드 2주 운영 후 위반 로그 분석 | 보안팀 |
| 4 | 롤백 절차 문서화 (`aa-disable`, `security_driver = "none"`) | CI-TEC |

---

## 7. 불확실한 부분 (명시)

- 현재 "일부 모듈 로드됨"의 구체적 프로파일 목록 미상 → `aa-status` 결과 공유 필요
- NetApp 스토리지 연동 시 NFS/iSCSI 경로가 표준인지 확인 필요
- OpenStack 버전(특히 Nova/libvirt 버전)에 따라 기본 프로파일 지원 범위 상이

추가 정보가 있으면 더 정밀한 분석이 가능하다.


---
# OpenStack Helm 환경에서 MAC 적용 추가 검토

## 1. OpenStack Helm 아키텍처 특수성

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Node (Ubuntu)                  │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ AppArmor (Kernel Level)                                 ││
│  └─────────────────────────────────────────────────────────┘│
│                              │                               │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │ libvirt Pod  │  │nova-compute  │  │ neutron-ovs  │       │
│  │ (DaemonSet)  │  │   Pod        │  │    Pod       │       │
│  │ privileged   │  │ privileged   │  │ privileged   │       │
│  └──────┬───────┘  └──────────────┘  └──────────────┘       │
│         │                                                    │
│         ▼                                                    │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ QEMU Process (실제 호스트에서 실행)                      ││
│  │ → AppArmor 프로파일 적용 대상                            ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

**핵심 차이점**: OpenStack Helm에서 libvirt/nova-compute는 **컨테이너**로 실행되지만, QEMU 프로세스는 **호스트 레벨**에서 fork됨.

---

## 2. OpenStack Helm 환경의 추가 복잡성

### 2.1 Privileged Container 문제

```yaml
# 일반적인 OpenStack Helm libvirt DaemonSet 설정
securityContext:
  privileged: true      # AppArmor 우회 가능
  runAsUser: 0
```

| 이슈 | 설명 |
|------|------|
| `privileged: true` | 컨테이너가 호스트의 모든 capabilities 획득, AppArmor 프로파일 무시 가능 |
| `hostPID: true` | 호스트 PID 네임스페이스 공유 |
| `hostNetwork: true` | 호스트 네트워크 네임스페이스 공유 |

### 2.2 Helm Chart 수정 필요 영역

```bash
# OpenStack Helm 관련 리포지토리 확인
# openstack-helm-infra: libvirt chart 포함
# openstack-helm: nova chart 포함
```

---

## 3. 적용 단계 (OpenStack Helm 특화)

### Phase 0: 현재 Helm 배포 상태 확인

```bash
# 1. libvirt DaemonSet 확인
kubectl get daemonset -n openstack libvirt-libvirt-default -o yaml

# 2. 현재 securityContext 확인
kubectl get pod -n openstack -l application=libvirt -o jsonpath='{.items[0].spec.containers[0].securityContext}'

# 3. hostPath 마운트 경로 확인 (AppArmor 프로파일에 반영 필요)
kubectl get pod -n openstack -l application=libvirt -o jsonpath='{.items[0].spec.volumes[*].hostPath.path}'
```

### Phase 1: Kubernetes Node 레벨 AppArmor 설정

```bash
# 각 Compute Node에서 실행

# 1. AppArmor 활성화
systemctl enable apparmor
systemctl start apparmor

# 2. libvirt-qemu 프로파일 설치 확인
apt list --installed | grep apparmor
dpkg -L apparmor-profiles | grep libvirt

# 3. Complain 모드 설정
aa-complain /etc/apparmor.d/usr.sbin.libvirtd
aa-complain /etc/apparmor.d/libvirt/TEMPLATE.qemu
```

### Phase 2: Helm Values 수정

```yaml
# openstack-helm-infra/libvirt/values.yaml 오버라이드

conf:
  qemu:
    security_driver: "apparmor"
    security_default_confined: 1
    security_require_confined: 0  # 초기 설정

pod:
  security_context:
    libvirt:
      container:
        libvirt:
          # privileged는 유지하되, AppArmor 프로파일 명시
          # Kubernetes 1.4+ 지원
          # annotation으로 처리
```

### Phase 3: Pod Annotation으로 AppArmor 적용

```yaml
# Helm values override 또는 직접 patch

metadata:
  annotations:
    # Kubernetes AppArmor annotation
    container.apparmor.security.beta.kubernetes.io/libvirt: localhost/libvirt-container
```

**주의**: `privileged: true` 컨테이너에서는 이 annotation이 **무시될 수 있음**.

### Phase 4: libvirt ConfigMap 업데이트

```bash
# Helm upgrade로 qemu.conf 반영
helm upgrade libvirt openstack-helm-infra/libvirt \
  -n openstack \
  -f custom-values.yaml
```

---

## 4. OpenStack Helm 특화 영향도

### 🔴 높은 위험

| 항목 | OpenStack Helm 특수 이슈 | 완화 방안 |
|------|--------------------------|-----------|
| **Rolling Update 시 VM 영향** | libvirt Pod 재시작 시 기존 VM과의 연결 일시 단절 | `updateStrategy: OnDelete` 사용, 수동 제어 |
| **hostPath 경로 불일치** | Chart 버전별 경로 상이 (`/var/lib/libvirt` vs `/var/lib/openstack-helm/libvirt`) | 프로파일에 실제 경로 반영 |
| **Ceph RBD 경로** | `/dev/rbd*` 접근 권한 필요 | AppArmor 프로파일에 Ceph 경로 추가 |

### 🟡 중간 위험

| 항목 | 설명 |
|------|------|
| **Helm Upgrade 충돌** | custom values가 upstream chart 업그레이드 시 충돌 가능 |
| **Multi-compute 일관성** | 모든 compute node에 동일한 AppArmor 프로파일 배포 필요 |

---

## 5. OpenStack Helm에서 권장하지 않는 접근

| 접근법 | 문제점 |
|--------|--------|
| Pod 내부에서 `aa-enforce` 실행 | 컨테이너 재시작 시 초기화됨 |
| ConfigMap으로 AppArmor 프로파일 배포 | AppArmor는 호스트 커널 기능, ConfigMap으로 로드 불가 |
| `privileged: false`로 변경 | libvirt/nova-compute 정상 동작 불가 |

---

## 6. 권장 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│                     Ansible/Puppet                          │
│         (Node Bootstrap 시 AppArmor 프로파일 배포)           │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Node                          │
│  • AppArmor 프로파일: /etc/apparmor.d/libvirt/*             │
│  • systemd: apparmor.service enabled                        │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              Helm Chart (values override)                   │
│  • conf.qemu.security_driver = "apparmor"                   │
│  • Pod annotations (optional)                               │
└─────────────────────────────────────────────────────────────┘
```

---

## 7. 실행 가능한 Action Items (OpenStack Helm)

| 우선순위 | 항목 | 세부 내용 |
|----------|------|-----------|
| 1 | **현재 Helm values 추출** | `helm get values libvirt -n openstack -o yaml > current-libvirt-values.yaml` |
| 2 | **hostPath 경로 목록화** | libvirt, nova-compute Pod의 실제 마운트 경로 문서화 |
| 3 | **Node Bootstrap 스크립트 준비** | Ansible playbook으로 AppArmor 프로파일 + 설정 배포 |
| 4 | **Staging 환경 테스트** | 단일 compute node에서 complain 모드 테스트 |
| 5 | **Helm upgrade 테스트** | `--dry-run` 으로 충돌 여부 사전 확인 |

---

## 8. 결론 (OpenStack Helm 특화)

| 구분 | 평가 |
|------|------|
| **기술적 가능 여부** | ✅ 가능 |
| **복잡도** | 🔴 높음 (일반 OpenStack 대비) |
| **주요 허들** | Node-level 설정과 Helm 관리의 분리 |
| **권장 접근** | Ansible + Helm 하이브리드 (Node 설정은 Ansible, 서비스 설정은 Helm) |

---

## 9. 불확실한 부분

- OpenStack Helm 버전 및 사용 중인 chart 버전 미상 → `helm list -n openstack` 결과 필요
- Ceph/NetApp 등 스토리지 백엔드 구성 상세 → AppArmor 프로파일 경로 결정에 필수
- Node Bootstrap 방식 (MaaS, Airship, 수동 등) → AppArmor 배포 방식 결정에 영향
