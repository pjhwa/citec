# OpenStack KVM 하이퍼바이저 백신/EPP 도입: 사실 기반 정리

## 0. 분석 접근

- **목적**: 첨부문서의 프레임(CSAP 가정, 튜닝 전략)을 참고하되, 공식 문서·벤더 레퍼런스·커뮤니티 사례에서 확인 가능한 **사실**만으로 재구성.
- **1차 소스 우선순위**: OpenStack Nova/libvirt 공식 문서 → Red Hat/Ubuntu 벤더 문서 → KVM/Proxmox 커뮤니티 운영 사례 → 버그 트래커.
- **불확실 영역 분리**: 국내 EPP(V3 Net, TachyonEnterprise 등) 벤더의 KVM 환경 정량 벤치마크는 **공개 자료 부재** → 별도 섹션에 명시.

---

## 1. 핵심 결론 (3줄 요약)

1. **하이퍼바이저(호스트 OS) 레벨 EPP 설치는 OpenStack 공식 가이드에 존재하지 않으며**, 대형 퍼블릭 클라우드·KVM 커뮤니티의 주류 권고는 "게스트 내부에서 보호 + 호스트는 네트워크 분리·sVirt/SELinux·최소 권한으로 보호"이다.
2. 그럼에도 국내 CSAP·금융망 요구로 **호스트에 EPP 설치가 불가피한 경우**, 핵심 리스크는 ① qcow2/raw 이미지 실시간 스캔으로 인한 I/O 지연, ② libvirt/qemu 프로세스 오탐 또는 kill, ③ 라이브 마이그레이션 중 파일·포트 접근 차단이다.
3. 운영상 검증된 대응은 **경로·프로세스 예외 등록 + CPU/cgroup 격리 + 실시간 스캔 대신 예약 스캔 우선 + PoC 기반 튜닝**이며, 도입 전 반드시 스테이징 환경 부하·마이그레이션 테스트를 거쳐야 한다.

---

## 2. 설치 사례 (Industry Practice)

### 2-1. 주류 권고: "호스트 EPP 미설치"
- **Proxmox 커뮤니티 공식 포럼**: 호스트에 AV를 까는 대신, 관리망/VM망을 물리·VLAN 분리하고 호스트에는 외부에서 접근 불가한 관리망만 노출하는 아키텍처를 권고. VM 내부에 각 게스트 OS용 AV를 두는 방식.
- **KVM/libvirt 보안 모델**: libvirt는 기본적으로 **sVirt(SELinux 기반 MAC)** 로 qemu 프로세스별 고유 레이블을 부여해 VM 간·VM↔호스트 격리를 제공. 별도 AV 없이도 하이퍼바이저 수준의 컨테인먼트가 존재.
- **퍼블릭 클라우드(AWS/Azure/GCP)**: 하이퍼바이저 호스트 OS에 상용 EPP를 올리지 않음(custom kernel + 텔레메트리 기반 자체 탐지).

### 2-2. 호스트 EPP 설치가 강제되는 사례 (국내·규제 환경)
- **CSAP(공공), 금융보안원 FSI, 국방 사이버 요구사항**: 인프라 호스트 OS도 "서버"로 간주되어 악성코드 대응 통제(AC/MM 영역) 적용 대상.
- 국내 현장에서 관찰되는 조합:
  - AhnLab V3 Net for Linux Server
  - 하우리 ViRobot Server
  - TrendMicro Deep Security (Agent 모드) / Server Protect for Linux
  - Trellix(구 McAfee) ENS for Linux
- ⚠️ **주의**: 위 솔루션들의 "OpenStack KVM 하이퍼바이저 인증/검증" 공식 레퍼런스는 공개 자료상 확인 불가. 대부분 "일반 Linux 서버" 지원으로만 명시됨.

---

## 3. Known Issues (문서·트래커 기반)

| # | 이슈 | 근거 / 메커니즘 |
|---|------|----------------|
| 1 | **qcow2/raw 이미지 실시간 스캔 시 VM I/O 지연** | qcow2는 copy-on-write 방식으로 지속 쓰기 발생, 기본 backing store이며 force_raw_images 설정에 따라 raw로 변환됨. 대용량 sparse 파일이라 실시간 스캔 시 메타데이터 접근마다 오버헤드. |
| 2 | **qemu/libvirt 프로세스 오탐 가능성** | qemu-kvm은 Proxmox/KVM 환경에서 root 권한으로 실행되며 block·PCI device 접근을 위해 광범위한 syscall을 수행. 행위기반 탐지에서 의심 패턴으로 분류될 수 있음. |
| 3 | **라이브 마이그레이션 실패** | 마이그레이션은 libvirtd 간 TCP 포트 통신(기본 49152–49215), hostname 해석, /var/lib/libvirt/qemu 하위 도메인 디렉터리 접근이 필요. 방화벽형 EPP나 FIM이 이를 차단·지연시키면 실패 사례 다수 보고됨(Red Hat Customer Portal 사례 참조). |
| 4 | **CPU steal time / IO wait 증가** | EPP 커널 모듈(fanotify, LSM hook)이 VFS 계층에 삽입되면 qemu 블록 에뮬레이션 경로에 추가 지연. 정확한 %는 벤더·워크로드별 상이(공개된 표준 수치 없음). |
| 5 | **SELinux/sVirt 충돌** | libvirt는 qemu 프로세스에 `svirt_t` + 고유 카테고리 레이블을 동적으로 부여. EPP 커널 모듈이 별도 LSM hook을 쓰면 정책 충돌로 VM 기동 실패 가능. |
| 6 | **CPU 모델/features 충돌** | host-passthrough 모드에서는 QEMU/libvirt가 호스트 CPU 특성 그대로 노출, 이 상태에서 EPP 모듈이 커널 기능을 바꾸면 마이그레이션 시 ABI 불일치 위험. |

---

## 4. 잠재적 리스크

### 4-1. 기술적 리스크
- **I/O 병목**: `/var/lib/nova/instances/*`(Nova ephemeral 저장소), `/var/lib/libvirt/qemu/*`, `/var/lib/libvirt/images/*` 에 대한 실시간 스캔이 가장 큰 병목원. Ceph/RBD 백엔드라면 호스트 파일시스템 레벨 스캔 대상이 줄어듦.
- **메모리 풋프린트**: EPP 커널 모듈·에이전트가 호스트 메모리를 소비 → overcommit 환경에서 VM OOM·swap 증가 위험(Proxmox 커뮤니티 사례: swap 사용이 KVM 프로세스 기준으로 누적되는 현상 보고됨).
- **커널 모듈 호환성**: RHEL/CentOS/Ubuntu 커널 마이너 업데이트마다 EPP 커널 모듈 재빌드·서명 필요. OpenStack 보안 패치 주기와 충돌 가능.
- **라이브 마이그레이션**: CPU mode가 `host-passthrough`면 원래도 마이그레이션이 엄격함(QEMU 공식 문서 명시). EPP가 그 위에 추가 변수 투입.

### 4-2. 운영/조직 리스크
- **책임 경계 모호화**: 장애 발생 시 "EPP 문제냐 / OpenStack 문제냐 / 커널 문제냐" 3자 책임소재 공방. 벤더 지원이 하이퍼바이저 환경에서 제한적일 수 있음.
- **컴플라이언스 vs 가용성 상충**: 실시간 감시 완화(성능 우선)가 감사 지적사항이 될 수 있음. 통제 근거 문서화 필수.
- **Zero-day 대응 제약**: 호스트 커널·qemu 취약점은 EPP 시그니처보다 패치·마이그레이션·eBPF 기반 탐지가 더 효과적인 경우가 많음.

---

## 5. 운영 방안 (Actionable)

### 5-1. 도입 전 체크리스트
1. **대체 수단 선 검토** — 감사관/보안팀과 협의해 다음으로 통제 대체 가능성 확인:
   - sVirt(SELinux MAC) + AppArmor
   - 호스트 OS 최소 설치 + 패키지 화이트리스트
   - eBPF 기반 런타임 탐지(Falco, Tracee 등)
   - FIM(AIDE, OSSEC) + 게스트 내부 EPP
2. **솔루션 선정 기준**
   - KVM/OpenStack 환경 레퍼런스 보유 여부 (서면 확인)
   - 커널 모듈 없는 Agent-only 모드 지원 여부
   - 제외 규칙(디렉터리·프로세스·해시) 세분화 수준
   - 실시간 스캔 on/off 정책 분리 가능성

### 5-2. 설치 시 필수 예외(Exclusion) 목록

**경로(Path) 예외**
- `/var/lib/nova/instances/` — Nova ephemeral VM 디스크
- `/var/lib/libvirt/qemu/` — libvirt per-domain 상태
- `/var/lib/libvirt/images/` — libvirt 이미지 풀
- `/var/lib/libvirt/qemu/domain-*/` — 도메인별 마스터 키·XDG 데이터
- `/var/log/libvirt/qemu/` — qemu 로그
- `/var/log/nova/` — Nova 로그
- `/var/lib/nova/` 전체 (Kolla 배포라면 `/var/lib/kolla/var/lib/nova/instances/`)
- Ceph/RBD 사용 시: `/var/lib/ceph/`, OSD 저널 경로
- `/dev/kvm`, `/dev/vhost-net`, `/dev/vfio/`

**프로세스 예외**
- `qemu-kvm`, `qemu-system-x86_64`
- `libvirtd`, `virtqemud`, `virtlogd`
- `nova-compute`
- `ovs-vswitchd`, `ovsdb-server`, `ovn-controller`
- `neutron-openvswitch-agent`

**포트/방화벽 예외 (마이그레이션)**
- libvirtd: 16509/tcp, 16514/tcp(TLS)
- QEMU 마이그레이션 동적 포트: 49152–49215/tcp
- SSH 터널 마이그레이션: 22/tcp

### 5-3. 스캔 정책 권고
1. **실시간 스캔**: `/etc`, `/root`, `/home`, 사용자 업로드 경로, 패키지 설치 경로(`/usr`, `/opt`) 등 **관리 영역 한정**.
2. **예약 스캔**: 전체 검사는 야간 저부하 시간대, 한 번에 1개 컴퓨트 노드만(라이브 마이그레이션으로 VM 소개 후 실행 고려).
3. **압축 파일·qcow2 내부 스캔 비활성화** — 성능 영향 가장 큼.
4. **자동 격리/삭제 금지** — 오탐 시 qemu 프로세스 kill 방지. "탐지 후 알림"만.

### 5-4. 리소스 격리
- EPP 데몬을 `systemd` slice 또는 cgroups v2로 CPU·메모리 한도 설정 예시:
  ```
  [Service]
  CPUQuota=50%
  MemoryMax=2G
  CPUAffinity=0-1   # 관리용 코어에 고정
  ```
- Nova에서 `vcpu_pin_set` / `cpu_dedicated_set`로 VM 전용 코어와 분리(OpenStack 공식 CPU pinning 기능 활용).
- NUMA 격리: EPP를 관리 NUMA 노드에, qemu-kvm은 워크로드 NUMA 노드에.

### 5-5. 운영 절차
1. **PoC 단계** (2–4주): 스테이징 클러스터에서 VM 생성·부팅·라이브 마이그레이션·스냅샷·볼륨 attach 시나리오 각각 EPP on/off 비교. `fio`·`iperf3`·`virsh migrate --live` 측정.
2. **Rolling 적용**: 1개 노드 → 1개 AZ → 전체. 롤백 절차(패키지 제거 스크립트) 사전 준비.
3. **모니터링 추가 지표**: `iowait`, `steal`, qemu 스레드 latency, live migration 성공률, EPP 스캔 queue depth.
4. **벤더 에스컬레이션 채널**: EPP 벤더 + OpenStack 배포 벤더(Red Hat/Canonical/Mirantis 등) 동시 티켓 경로 확보.
5. **정기 재튜닝**: 커널 패치·OpenStack 버전 업그레이드 시 예외 경로 변경 여부 재확인(예: Kolla → 비Kolla 전환 시 경로 상이).

---

## 6. 불확실한 영역 (솔직한 한계)

- ⚠️ 국내 주요 EPP 솔루션의 **OpenStack Yoga/Antelope + Ubuntu 22.04/RHEL 9.x KVM 환경 정량 벤치마크**는 공개 자료상 확인되지 않음. 벤더 직접 문의 필요.
- ⚠️ **CSAP 기술 심사 기준의 "하이퍼바이저 호스트 EPP 설치 명시 의무화"** 조항을 공개 문서에서 직접 확인하지 못함. 심사원별·연차별 해석 차이 존재 가능 → 보안 컨설팅사 또는 KISA 문의로 확정 필요.
- ⚠️ 첨부문서의 "I/O Wait 20–50% 증가" 같은 정량 수치는 **커뮤니티 일화적(anecdotal) 수준**이며 재현 가능한 표준 벤치마크 아님. 자사 워크로드 기준 PoC 필수.
- ⚠️ 라이브 마이그레이션 실패 사례는 일반 libvirt/qemu 이슈로 공개 트래커에 다수 존재하나, "EPP가 직접 원인"으로 단정된 상용 사고 리포트는 공개되지 않음.

---

## 7. 다음 행동 제안 (To-Do)

1. CI-TEC Linux/Cloud 파트 협업 → PoC 클러스터 1세트 분리(컴퓨트 2대 + 컨트롤러 1대 최소).
2. 보안팀·감사 대응팀과 "호스트 EPP 요건" 문언 재확인 및 대체 통제(sVirt, FIM, eBPF) 수용성 타진.
3. 후보 EPP 3개 벤더에 RFI 발송: KVM 레퍼런스, 커널 모듈 의존성, Agent-only 모드, 예외 규칙 범위, SLA.
4. PoC 측정 지표·합격 기준 사전 정의(예: 라이브 마이그레이션 성공률 ≥99%, VM 부팅 시간 Δ ≤10%, fio 4K randwrite Δ ≤15%).
5. 결과를 IR Q&A 팩에 "Cloud Service 보안 강화 현황" 항목으로 반영 가능하도록 정리.
