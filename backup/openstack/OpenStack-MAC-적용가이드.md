# OpenStack Helm 환경 MAC(Mandatory Access Control) 적용 가이드

> **문서 목적**: OpenStack Helm 환경에서 MAC(AppArmor + sVirt) 적용을 위한 종합 가이드
> **작성일**: 2026-04-17
> **대상 환경**: OpenStack 2025.1 (Epoxy) + Ubuntu 22.04/24.04 + Kubernetes

---

## 목차

1. [MAC 기본 개념](#1-mac-기본-개념)
2. [현재 환경 현황](#2-현재-환경-현황)
3. [환경별 고려사항](#3-환경별-고려사항)
4. [사전 테스트 방법](#4-사전-테스트-방법)
5. [단계별 적용 방안](#5-단계별-적용-방안)
6. [검증 방법](#6-검증-방법)
7. [영향도 분석](#7-영향도-분석)
8. [롤백 절차](#8-롤백-절차)
9. [불확실한 부분 및 추가 확인 필요 사항](#9-불확실한-부분-및-추가-확인-필요-사항)

---

## 1. MAC 기본 개념

### 1.1 MAC이란?

**Mandatory Access Control (강제 접근 제어)** 은 시스템 관리자가 정의한 정책에 따라 프로세스의 리소스 접근을 **강제적으로** 제한하는 보안 메커니즘이다.

| 구분 | DAC (Discretionary) | MAC (Mandatory) |
|------|---------------------|------------------|
| 제어 주체 | 파일/리소스 소유자 | 시스템 관리자 (정책) |
| 우회 가능 여부 | 소유자가 변경 가능 | root도 정책 우회 불가 |
| 대표 예시 | chmod, chown | AppArmor, SELinux |
| 격리 수준 | 사용자 단위 | 프로세스 단위 |

### 1.2 Linux 주요 MAC 구현

| 구현체 | 배포판 | 특징 |
|--------|--------|------|
| **AppArmor** | Ubuntu, SUSE | 경로 기반, 학습 곡선 낮음 |
| **SELinux** | RHEL, CentOS | 레이블 기반, 세밀한 제어 |
| **Smack** | Tizen 등 | 간단한 레이블 기반 |

Ubuntu 환경이므로 **AppArmor**가 기본 선택지.

### 1.3 OpenStack에서의 MAC: sVirt

**sVirt (Secure Virtualization)** 는 OpenStack/libvirt가 MAC을 활용하여 VM 간 격리를 강화하는 메커니즘이다.

```
┌─────────────────────────────────────────────────────┐
│                  Hypervisor Host                     │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │
│  │    VM-A     │  │    VM-B     │  │    VM-C     │  │
│  │ (QEMU proc) │  │ (QEMU proc) │  │ (QEMU proc) │  │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  │
│         │                │                │          │
│    AppArmor Profile (per VM, dynamically generated)  │
│         │                │                │          │
│  ┌──────▼────────────────▼────────────────▼───────┐  │
│  │    Kernel (AppArmor enforces isolation)       │  │
│  └───────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

**sVirt 동작 방식**:
- libvirt가 각 VM 프로세스마다 **동적으로 고유한 AppArmor 프로파일** 생성
- 한 VM이 탈출(escape)하더라도 다른 VM의 디스크/메모리 접근 차단
- 하이퍼바이저 호스트 시스템 파일 접근 차단

### 1.4 AppArmor 모드

| 모드 | 동작 | 용도 |
|------|------|------|
| **Disabled** | 프로파일 무시 | 초기 상태 |
| **Complain** | 위반 시 로그만 기록, 차단 X | 프로파일 개발/테스트 |
| **Enforce** | 위반 시 차단 + 로그 | 운영 환경 |

---

## 2. 현재 환경 현황

### 2.1 인프라 구성

| 구분 | 상세 |
|------|------|
| **OS** | Ubuntu 22.04 (운영), 24.04 (개발/테스트 순차 업그레이드 중) |
| **OpenStack** | 2025.1 (Epoxy) |
| **배포 방식** | OpenStack Helm (openstack-helm-infra 2025.2.0) |
| **Kubernetes** | libvirt/nova-compute DaemonSet 기반 |
| **스토리지** | Rook-Ceph (RBD) |
| **컨테이너 이미지** | `docker.io/openstackhelm/libvirt:2025.1-ubuntu_noble` |

### 2.2 현재 MAC 상태

| 항목 | 상태 | 비고 |
|------|------|------|
| AppArmor 서비스 | `disabled` | systemctl 기준 |
| AppArmor 프로파일 | **부분 로드** | `aa-status`에서 일부 모듈 확인 |
| sVirt | **미설정** | `/etc/libvirt/qemu.conf`에 `security_driver` 없음 |

### 2.3 Node Pool 구성

```
┌────────────────────────────────────────────────────────────┐
│                  Compute Node Pools                         │
├────────────────────────────────────────────────────────────┤
│  [b0-*]          일반 compute (6 pods)                      │
│  [b1-*]          일반 compute (12+ pods)                    │
│  [b1-gpu-b300-*] NVIDIA B300 GPU (4 pods)    ← VFIO 필요    │
│  [b1-gpu-h100-*] NVIDIA H100 GPU (2 pods)    ← VFIO 필요    │
│  [b1-hcn2-*]     High-Compute Node (4 pods)                 │
└────────────────────────────────────────────────────────────┘
```

### 2.4 libvirt Helm Values (현재)

```yaml
conf:
  ceph:
    enabled: true
images:
  tags:
    libvirt: docker.io/openstackhelm/libvirt:2025.1-ubuntu_noble
```

**특이사항**: 컨테이너 이미지는 `noble` (Ubuntu 24.04) 기반이나, 호스트는 22.04 혼재.

### 2.5 hostPath 마운트 현황

#### nova-compute
- `/`, `/dev`, `/dev/pts`, `/lib/modules`, `/run`, `/run/lock`
- `/var/lib/nova`, `/var/lib/libvirt`, `/var/lib/openstack-helm/compute/nova`
- `/sys/fs/cgroup`, `/sys/block`
- `/etc/iscsi`, `/etc/multipath`, `/etc/machine-id`
- `/var/run/ceph/guests`, `/var/log/qemu`

#### libvirt
- `/dev`, `/lib/modules`, `/run`
- `/var/lib/libvirt`, `/var/lib/nova`, `/var/lib/openstack-helm/compute/libvirt`
- `/sys/fs/cgroup`, `/etc/machine-id`
- `/etc/multipath`, `/etc/lvm`, `/etc/libvirt/qemu`
- `/var/log/libvirt`, `/var/log/qemu`, `/var/run/ceph/guests`

---

## 3. 환경별 고려사항

### 3.1 OpenStack Helm 특수성

```
┌──────────────────────────────────────────────────────────┐
│              Kubernetes Node (Ubuntu 22.04/24.04)        │
│  ┌────────────────────────────────────────────────────┐  │
│  │ AppArmor (Kernel Level)                            │  │
│  └────────────────────────────────────────────────────┘  │
│                           │                               │
│  ┌──────────────┐  ┌──────────────┐                      │
│  │ libvirt Pod  │  │ nova-compute │                      │
│  │  privileged  │  │  privileged  │                      │
│  └──────┬───────┘  └──────────────┘                      │
│         │ spawn                                          │
│         ▼                                                 │
│  ┌────────────────────────────────────────────────────┐  │
│  │ QEMU Process (호스트 레벨 실행)                      │  │
│  │ → AppArmor 프로파일 적용 대상                        │  │
│  └────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────┘
```

**핵심**: libvirt/nova-compute 컨테이너는 `privileged: true`로 실행되지만, **실제 QEMU 프로세스는 호스트에서 fork** 되므로 호스트 커널의 AppArmor가 QEMU를 직접 제어 가능.

### 3.2 Ubuntu 22.04 vs 24.04 차이점

| 항목 | 22.04 (Jammy) | 24.04 (Noble) |
|------|---------------|----------------|
| AppArmor 버전 | 3.0.x | 4.0.x |
| libvirt 기본 프로파일 | 존재 | 존재 (개선) |
| 신규 기능 | - | 네트워크 룰 세분화, 더 나은 unconfined 검출 |
| Unprivileged User NS | 기본 허용 | **기본 제한** (AppArmor로 제어) |

**영향**: 
- 24.04에서는 AppArmor 프로파일이 더 엄격하게 동작
- 22.04용 프로파일이 24.04에서 예상치 못하게 동작할 수 있음
- **22.04와 24.04 노드 모두에서 별도 검증 필요**

### 3.3 OpenStack 2025.1 (Epoxy) 특이사항

| 항목 | 영향 |
|------|------|
| libvirt 기본 driver | `qemu` |
| Nova compute driver | `libvirt.LibvirtDriver` |
| sVirt 지원 | 정식 지원 (apparmor/selinux) |
| Secure Boot 관련 | UEFI Secure Boot 사용 시 추가 프로파일 필요 |

### 3.4 Rook-Ceph 통합 이슈

현재 `conf.ceph.enabled: true` 설정. AppArmor 프로파일에 Ceph 관련 경로 필수:

```
/var/run/ceph/guests/** rw,
/etc/ceph/** r,
/dev/rbd* rw,
```

### 3.5 GPU Node 특수성 (⚠️ 가장 복잡)

H100, B300 GPU 노드는 **VFIO Passthrough** 방식으로 GPU를 VM에 할당. AppArmor 프로파일에 추가 룰 필요:

```
/dev/vfio/* rw,
/dev/vfio/vfio rw,
/sys/bus/pci/devices/*/config rw,
/sys/bus/pci/drivers/vfio-pci/** rw,
/sys/kernel/iommu_groups/** r,
/dev/nvidia* rw,
/dev/nvidiactl rw,
/dev/nvidia-uvm rw,
```

### 3.6 Privileged Container와 AppArmor

| 구분 | 설명 |
|------|------|
| Pod annotation | `container.apparmor.security.beta.kubernetes.io/<container>` 방식 존재 |
| privileged 컨테이너 | 위 annotation이 **부분 무시**될 수 있음 |
| **실제 보호 대상** | Pod 자체가 아닌, Pod가 생성하는 **QEMU 프로세스** |

**결론**: 컨테이너 자체에 AppArmor를 적용하는 것이 아니라, **호스트 레벨에서 QEMU 프로세스**에 적용.

---

## 4. 사전 테스트 방법

### 4.1 현황 정밀 조사 (Test 환경)

```bash
# 1. AppArmor 상태 전체 조회
sudo aa-status
sudo aa-status --json > apparmor-baseline-$(hostname)-$(date +%Y%m%d).json

# 2. 커널 AppArmor 지원 확인
cat /sys/kernel/security/apparmor/profiles | head -20

# 3. libvirt 관련 프로파일 존재 여부
ls -la /etc/apparmor.d/libvirt/ 2>/dev/null
ls -la /etc/apparmor.d/abstractions/libvirt* 2>/dev/null
ls -la /etc/apparmor.d/usr.sbin.libvirtd 2>/dev/null

# 4. 현재 QEMU 프로세스의 AppArmor 상태 확인
ps -eZ | grep qemu
cat /proc/$(pgrep -f qemu-system | head -1)/attr/current

# 5. Ubuntu 버전 확인
lsb_release -a
uname -r
```

### 4.2 샘플 워크로드 준비

테스트용 VM 시나리오를 미리 정의:

| 시나리오 | 목적 | 커맨드 예시 |
|----------|------|-------------|
| 기본 VM 생성 | 기본 동작 확인 | `openstack server create --image ubuntu --flavor m1.small` |
| Ceph 볼륨 attach | 스토리지 접근 확인 | `openstack volume attach` |
| Live Migration | 마이그레이션 확인 | `openstack server migrate --live` |
| GPU VM (해당 노드) | GPU Passthrough 확인 | GPU flavor 사용 |
| Console 접속 | VNC 동작 확인 | `openstack console url show` |

### 4.3 Complain 모드 Dry-Run

```bash
# 1. AppArmor 활성화 (재부팅 없이)
sudo systemctl enable apparmor
sudo systemctl start apparmor

# 2. 기본 프로파일 설치 확인
dpkg -l | grep apparmor-profiles
sudo apt install apparmor-profiles apparmor-utils -y

# 3. libvirt 프로파일 complain 모드
sudo aa-complain /etc/apparmor.d/usr.sbin.libvirtd
sudo aa-complain /etc/apparmor.d/libvirt/TEMPLATE.qemu 2>/dev/null || echo "템플릿 없음"

# 4. 로그 수집 (2주 권장)
sudo journalctl -f | grep -i apparmor | tee /var/log/apparmor-test-$(date +%Y%m%d).log
```

### 4.4 위반 로그 분석

```bash
# Denied 로그 추출
sudo grep "apparmor=\"DENIED\"" /var/log/syslog | awk -F'name=' '{print $2}' | awk '{print $1}' | sort | uniq -c | sort -rn

# aa-logprof로 프로파일 자동 개선 (주의: 인터랙티브)
sudo aa-logprof
```

---

## 5. 단계별 적용 방안

### 5.1 전체 로드맵

| Phase | 기간 | 대상 | 모드 | 비고 |
|-------|------|------|------|------|
| **Phase 0** | 1주 | 전체 환경 | - | 현황 조사, 프로파일 작성 |
| **Phase 1** | 2주 | Test (osh1) | Complain | 프로파일 검증 |
| **Phase 2** | 1주 | Test (osh1) | Enforce | 엄격 모드 검증 |
| **Phase 3** | 2주 | Dev 일반 compute | Complain → Enforce | Ubuntu 24.04 포함 |
| **Phase 4** | 2주 | Dev GPU/HCN | Complain → Enforce | VFIO 프로파일 검증 |
| **Phase 5** | 2-3주 | 운영 일반 compute | Complain | Ubuntu 22.04, 장기 모니터링 |
| **Phase 6** | 2-3주 | 운영 일반 compute | Enforce | 점진 전환 |
| **Phase 7** | 3-4주 | 운영 GPU/HCN | Complain → Enforce | 최종 단계 |

**총 소요 기간**: 약 15-18주 (4-5개월)

### 5.2 Phase 0: 사전 준비

#### 5.2.1 프로파일 템플릿 작성

```bash
# /etc/apparmor.d/libvirt/TEMPLATE.qemu (커스터마이징)

#include <tunables/global>

profile LIBVIRT_TEMPLATE flags=(attach_disconnected) {
  #include <abstractions/libvirt-qemu>

  # === OpenStack Helm 특화 경로 ===
  /var/lib/openstack-helm/compute/** rwk,
  /var/lib/nova/** rwk,
  /var/lib/libvirt/** rwk,
  
  # === Ceph RBD ===
  /var/run/ceph/guests/** rw,
  /etc/ceph/** r,
  /dev/rbd* rw,
  
  # === Logging ===
  /var/log/libvirt/** rw,
  /var/log/qemu/** rw,
  
  # === Storage Multipath ===
  /etc/iscsi/** r,
  /etc/multipath/** r,
  /etc/lvm/** r,
  /dev/mapper/* rw,
  
  # === 시스템 기본 ===
  /etc/machine-id r,
  /sys/fs/cgroup/** rw,
}
```

#### 5.2.2 GPU 전용 프로파일 (별도)

```bash
# /etc/apparmor.d/libvirt/TEMPLATE.qemu.gpu
# 위 기본 프로파일에 추가

  # === VFIO (GPU Passthrough) ===
  /dev/vfio/* rw,
  /dev/vfio/vfio rw,
  
  # === PCI Device Access ===
  /sys/bus/pci/devices/*/config rw,
  /sys/bus/pci/devices/*/resource* rw,
  /sys/bus/pci/drivers/vfio-pci/** rw,
  /sys/kernel/iommu_groups/** r,
  
  # === NVIDIA ===
  /dev/nvidia* rw,
  /dev/nvidiactl rw,
  /dev/nvidia-uvm rw,
  /dev/nvidia-uvm-tools rw,
```

#### 5.2.3 Helm Values Override 준비

```yaml
# libvirt-values-mac.yaml
conf:
  ceph:
    enabled: true
  qemu:
    security_driver: "apparmor"
    security_default_confined: 1
    security_require_confined: 0  # 초기: 0 (soft-fail)

pod:
  lifecycle:
    upgrades:
      daemonsets:
        libvirt:
          pod_replacement_strategy: OnDelete  # 수동 제어
```

### 5.3 Phase 1-2: 테스트 환경 검증

```bash
# Step 1: Node에서 AppArmor 활성화
sudo systemctl enable apparmor && sudo systemctl start apparmor

# Step 2: 프로파일 배포
sudo cp TEMPLATE.qemu /etc/apparmor.d/libvirt/
sudo apparmor_parser -r /etc/apparmor.d/libvirt/TEMPLATE.qemu
sudo aa-complain /etc/apparmor.d/libvirt/TEMPLATE.qemu

# Step 3: Helm upgrade (테스트 환경만)
helm upgrade libvirt openstack-helm-infra/libvirt \
  -n openstack \
  -f libvirt-values-mac.yaml \
  --dry-run  # 먼저 dry-run

helm upgrade libvirt openstack-helm-infra/libvirt \
  -n openstack \
  -f libvirt-values-mac.yaml

# Step 4: libvirt Pod 수동 재시작
kubectl delete pod -n openstack -l application=libvirt --wait=false
```

### 5.4 Phase 3-4: 개발 환경 적용

Ansible Playbook으로 일괄 배포 권장.

```yaml
# apparmor-deploy.yml
---
- name: Deploy AppArmor for OpenStack Helm
  hosts: compute_standard  # inventory에서 GPU/HCN 분리
  become: yes
  vars:
    ubuntu_version: "{{ ansible_distribution_version }}"
  
  tasks:
    - name: Install AppArmor packages
      apt:
        name:
          - apparmor
          - apparmor-utils
          - apparmor-profiles
        state: present

    - name: Deploy custom QEMU profile (based on Ubuntu version)
      template:
        src: "templates/TEMPLATE.qemu.{{ ubuntu_version }}.j2"
        dest: /etc/apparmor.d/libvirt/TEMPLATE.qemu
        mode: '0644'
      notify: reload apparmor

    - name: Enable and start AppArmor
      systemd:
        name: apparmor
        enabled: yes
        state: started

    - name: Set profile to complain mode (initial)
      command: aa-complain /etc/apparmor.d/libvirt/TEMPLATE.qemu

  handlers:
    - name: reload apparmor
      command: apparmor_parser -r /etc/apparmor.d/libvirt/TEMPLATE.qemu
```

### 5.5 Phase 5-7: 운영 환경 점진 적용

**Canary 방식 권장**:

1. 1개 노드만 적용 (Complain) → 1주 모니터링
2. 5개 노드로 확장 (Complain) → 1주 모니터링
3. 전체 일반 compute (Complain) → 2주 모니터링
4. 위반 로그 0건 달성 후 Enforce 전환 (1개 노드씩)
5. GPU/HCN 노드 별도 동일 절차

**중요**: 운영 환경은 Ubuntu 22.04와 24.04 혼재 예상 → 버전별 프로파일 분리 배포.

---

## 6. 검증 방법

### 6.1 기능 검증 체크리스트

| 항목 | 명령어 | 기준 |
|------|--------|------|
| VM 생성 | `openstack server create ...` | 정상 부팅 |
| VM 재부팅 | `openstack server reboot` | 정상 재시작 |
| 볼륨 attach | `openstack volume attach` | 마운트 성공 |
| 볼륨 detach | `openstack volume detach` | 언마운트 성공 |
| 스냅샷 생성 | `openstack server image create` | 스냅샷 완료 |
| Live Migration | `openstack server migrate --live` | 무중단 이동 |
| Cold Migration | `openstack server migrate` | 재배치 성공 |
| Console 접속 | `openstack console url show` | VNC 동작 |
| GPU 인식 (GPU 노드) | VM 내부 `nvidia-smi` | GPU 표시 |
| CUDA 실행 (GPU 노드) | CUDA 샘플 실행 | 정상 완료 |

### 6.2 로그 기반 검증

```bash
# 1. AppArmor DENIED 로그 (없어야 정상)
sudo grep 'apparmor="DENIED"' /var/log/syslog | tail -100

# 2. libvirt 에러 로그
sudo journalctl -u libvirtd --since "1 hour ago" | grep -i error

# 3. QEMU 프로세스 프로파일 확인
ps -eZ | grep qemu-system
# 예상: libvirt-<uuid> (complain/enforce)

# 4. Kubernetes Pod 상태
kubectl get pods -n openstack -l application=libvirt
kubectl describe pod -n openstack <libvirt-pod>
```

### 6.3 성능 검증

| 지표 | 측정 방법 | 허용 기준 |
|------|-----------|-----------|
| VM 부팅 시간 | 적용 전/후 비교 | +5% 이내 |
| 디스크 IOPS | `fio` 벤치마크 | -3% 이내 |
| 네트워크 처리량 | `iperf3` | -3% 이내 |
| CPU 오버헤드 | `top` 모니터링 | +1% 이내 |

### 6.4 보안 검증 (MAC 효과 확인)

```bash
# 1. 의도적 위반 테스트 (complain 모드에서)
# QEMU 프로세스가 /root 접근 시도 시 차단되는지 확인

# 2. VM 간 격리 확인
# VM-A의 QEMU가 VM-B의 디스크 이미지에 접근 불가한지 검증

# 3. sVirt 활성화 확인
virsh capabilities | grep -A5 secmodel
# 예상 출력: <model>apparmor</model>
```

---

## 7. 영향도 분석

### 7.1 위험 수준별 영향

#### 🔴 High Risk

| 항목 | 영향 | 완화 방안 |
|------|------|-----------|
| VM 부팅 실패 | QEMU가 필요 경로 접근 차단 | Complain 모드 충분한 기간 선행 |
| Live Migration 실패 | 임시 파일 경로 차단 | 프로파일에 migration 경로 포함 |
| Ceph 볼륨 attach 실패 | `/var/run/ceph/guests` 차단 | Ceph 경로 명시 |
| GPU VM 부팅 실패 | VFIO 디바이스 차단 | GPU 전용 프로파일 분리 |
| Ubuntu 22.04/24.04 혼재 | 버전별 동작 차이 | 버전별 프로파일 배포 |

#### 🟡 Medium Risk

| 항목 | 영향 |
|------|------|
| Helm upgrade 시 values 충돌 | Custom values override 관리 |
| 운영 복잡도 증가 | 신규 스토리지/네트워크 추가 시 프로파일 업데이트 필요 |
| DaemonSet rolling update | libvirt Pod 재시작 시 VM 일시적 연결 단절 |

#### 🟢 Low Risk

| 항목 | 영향 |
|------|------|
| 기존 VM | libvirt 재시작 시 영향 없음 (신규 VM부터 적용) |
| 성능 저하 | 1-3% 이내, 실제로는 거의 없음 |
| Compute 노드 부하 | AppArmor 자체 오버헤드 미미 |

### 7.2 적용 효과 (Benefit)

| 효과 | 설명 |
|------|------|
| **VM 간 격리 강화** | 한 VM 탈출 시 다른 VM 자산 보호 |
| **호스트 시스템 보호** | 악성 VM의 호스트 파일 시스템 접근 차단 |
| **규정 준수** | 보안 표준(ISMS-P, CSAP 등) 요구사항 충족 |
| **침해사고 범위 축소** | 공격 시 피해 격리 |
| **감사 로그** | AppArmor 위반 시 로그 자동 수집 |

### 7.3 비적용 시 위험 (Risk of Not Applying)

| 위험 | 가능성 | 영향도 |
|------|--------|--------|
| VM Escape 공격 시 피해 확산 | 낮음 | 매우 높음 |
| 컴플라이언스 미충족 | 높음 | 중간 |
| 인증 감사 지적 | 높음 | 중간 |

---

## 8. 롤백 절차

### 8.1 긴급 전체 롤백

```bash
# Step 1: AppArmor 즉시 비활성화 (Node에서)
sudo systemctl stop apparmor
sudo systemctl disable apparmor

# Step 2: libvirt Helm values 원복
helm upgrade libvirt openstack-helm-infra/libvirt \
  -n openstack \
  --reuse-values \
  --set conf.qemu.security_driver=""

# Step 3: libvirt Pod 재시작
kubectl rollout restart daemonset/libvirt-libvirt-default -n openstack

# Step 4: 검증
kubectl get pods -n openstack -l application=libvirt
openstack server list  # 기존 VM 정상 여부 확인
```

### 8.2 부분 롤백 (특정 Node)

```bash
# 특정 노드에서만 AppArmor 프로파일 비활성화
sudo aa-disable /etc/apparmor.d/libvirt/TEMPLATE.qemu

# 해당 노드의 libvirt Pod 재시작
kubectl delete pod libvirt-libvirt-default-<node-suffix> -n openstack
```

### 8.3 Complain → Enforce 롤백

```bash
# Enforce 모드에서 문제 발생 시 Complain으로 되돌리기
sudo aa-complain /etc/apparmor.d/libvirt/TEMPLATE.qemu
```

### 8.4 롤백 결정 기준

| 상황 | 조치 |
|------|------|
| VM 부팅 실패율 > 1% | 즉시 Complain 모드 전환 |
| Live Migration 실패 발생 | 프로파일 수정, 재배포 |
| 성능 저하 > 5% | 원인 조사 후 프로파일 튜닝 |
| 고객 장애 신고 | 즉시 전체 롤백 후 원인 분석 |

---

## 9. 불확실한 부분 및 추가 확인 필요 사항

### 9.1 확인 필요 정보

| 항목 | 확인 방법 | 우선순위 |
|------|-----------|----------|
| 현재 로드된 AppArmor 프로파일 목록 | `aa-status --json` 전체 노드 수집 | 🔴 높음 |
| DaemonSet updateStrategy | `kubectl get ds -n openstack -o yaml` | 🔴 높음 |
| GPU VM Live Migration 정책 | 운영팀 문의 | 🟡 중간 |
| Ubuntu 24.04 노드 비중 | `ansible all -m setup` 수집 | 🟡 중간 |
| Secure Boot 활성화 여부 | `mokutil --sb-state` | 🟢 낮음 |

### 9.2 추가 조사 필요 사항

- **OpenStack Helm 2025.2.0 Chart의 AppArmor 네이티브 지원 여부**  
  → Helm values에 `pod.securityContext` 레벨 지원이 있는지 확인 필요
- **Ubuntu 24.04 AppArmor 4.0 신규 제약사항**  
  → Unprivileged User Namespace 제한이 OpenStack에 미치는 영향 검증
- **Rook-Ceph CSI 드라이버와의 호환성**  
  → CSI 드라이버가 생성하는 경로가 AppArmor 프로파일에 포함되는지
- **Nova 2025.1 (Epoxy) sVirt 변경사항**  
  → 릴리즈 노트 확인 후 프로파일 업데이트 필요 여부

### 9.3 테스트 환경과 운영 환경 차이

| 항목 | 테스트 (osh1) | 운영 |
|------|---------------|------|
| OS 버전 | 24.04 (예상) | 22.04 + 24.04 혼재 |
| 노드 수 | 소수 | 30+ |
| GPU 노드 | 없음 (추정) | 다수 (H100, B300) |
| 트래픽 | 낮음 | 운영 부하 |

**⚠️ 테스트 환경 검증만으로는 운영 환경 안전 보장 불가.** 운영 환경 Canary 방식 필수.

---

## 부록 A: 주요 명령어 Cheatsheet

```bash
# AppArmor 상태
sudo aa-status
sudo aa-status --json

# 프로파일 모드 변경
sudo aa-complain <profile>   # Complain 모드
sudo aa-enforce <profile>    # Enforce 모드
sudo aa-disable <profile>    # 비활성화

# 프로파일 리로드
sudo apparmor_parser -r /etc/apparmor.d/<profile>

# 위반 로그 분석
sudo aa-logprof              # 인터랙티브 프로파일 개선
sudo grep DENIED /var/log/syslog

# libvirt sVirt 확인
virsh capabilities | grep -A5 secmodel
ps -eZ | grep qemu
```

## 부록 B: 참고 자료

- Ubuntu AppArmor Documentation: https://ubuntu.com/server/docs/security-apparmor
- OpenStack Security Guide (sVirt): https://docs.openstack.org/security-guide/
- OpenStack Helm: https://docs.openstack.org/openstack-helm/
- libvirt Security: https://libvirt.org/drvqemu.html#security

---

## 결론

- **적용 가능성**: ✅ 가능
- **권장 여부**: ✅ 보안 강화를 위해 권장
- **복잡도**: 🔴 높음 (Ubuntu 혼재 + GPU + Helm 조합)
- **소요 기간**: 15-18주 (약 4-5개월)
- **핵심 성공 요인**:
  1. 충분한 Complain 모드 기간 확보
  2. 환경별(OS, 노드 유형) 프로파일 분리 관리
  3. 명확한 롤백 절차 사전 준비
  4. 운영팀-보안팀-CI-TEC 간 긴밀한 협업
