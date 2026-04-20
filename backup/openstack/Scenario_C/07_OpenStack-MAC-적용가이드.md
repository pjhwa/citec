# OpenStack KVM MAC(sVirt/AppArmor) 적용 가이드 v2.0

> **문서 목적**: CSAP 9.1.4-③ 대응 방향(**백신 미설치 + MAC 통제**)의 **기술 구현 가이드**.
> PoC 측정계획서(`06_PoC_측정계획서.md`)의 3개월 로드맵과 1:1 매핑되는 실행 문서.

> **v2.0 변경 사항**: v1.0은 "AV와 병행 운영"을 전제로 했으나, v2.0은 **MAC을 Primary 통제**로 격상. 검증 절차(E-01~E-12 증적과 연동), 롤백 기준, Dev→운영 단계별 적용 순서 추가.

---

## 0. 결론 요약

| 항목 | 내용 |
| --- | --- |
| 적용 대상 | SCPv2 Sovereign(PG) 상암/춘천 OpenStack Compute 노드 (Ubuntu + KVM Helm) |
| 통제 수단 | **sVirt (libvirt 자동 AppArmor 프로파일 생성) + 커스텀 AppArmor 프로파일 보강** |
| 검증 기간 | **3개월 (Week 1~12)** — Phase 0 준비, Phase 1 Test, Phase 2 Dev, Phase 3 운영 |
| 롤백 조건 | VM 기동 실패율 >1%, 라이브 마이그레이션 실패율 >0.5%, I/O 성능 저하 >5% |
| 필수 증적 | E-01 sVirt 활성화, E-02 프로파일 적용, E-09 DENIED 로그 |

---

## 1. 사전 점검 체크리스트 (Phase 0: Week 1)

### 1-1. 커널·패키지 버전 확인

```bash
# 커널 AppArmor 모듈 로드 확인
cat /sys/module/apparmor/parameters/enabled   # 기대값: Y
aa-status --enabled                            # 정상 종료 코드: 0

# 패키지 버전
dpkg -l | grep -E 'apparmor|libvirt|qemu'
# 기대값: apparmor >= 3.0, libvirt-daemon >= 8.0, qemu-kvm >= 6.2

# libvirt AppArmor 드라이버 빌드 확인
virsh capabilities | grep -i 'security.*apparmor'
# 기대 출력: <secmodel><model>apparmor</model><doi>0</doi></secmodel>
```

### 1-2. 현재 상태 스냅샷 (롤백 기준점)

```bash
# 현 시점 VM 기동 성공률·마이그레이션 지표 기록 → baseline.json
# PoC 측정계획서 §3.2의 "성능 베이스라인" 섹션 참조

# Compute 노드 수
openstack hypervisor list -f value -c "Hypervisor Hostname" | wc -l

# 노드별 실행 중 VM 수
for host in $(openstack hypervisor list -f value -c "Hypervisor Hostname"); do
  echo "=== $host ==="
  openstack server list --all-projects --host "$host" -f value | wc -l
done
```

### 1-3. OpenStack Helm 배포 특성 확인

- SCPv2는 **OpenStack Helm 기반** → nova-compute가 컨테이너 내부에서 동작
- libvirt는 호스트 네임스페이스에서 동작하지만, QEMU 프로세스는 컨테이너 볼륨 마운트 경로 사용
- **주의**: AppArmor 프로파일은 **호스트 기준 경로**로 작성해야 함 (`/var/lib/openstack-helm/libvirt/...` 등 실제 마운트 경로 반영)

---

## 2. sVirt 활성화 (Phase 1: Week 2~4 — Test 환경)

### 2-1. libvirt 설정 변경

```bash
# /etc/libvirt/qemu.conf
# v2.0 적용 후 기대 상태:
security_driver = "apparmor"
security_default_confined = 1
security_require_confined = 1
```

> **중요**: `security_require_confined = 1`은 프로파일 미적용 VM 기동을 **차단**. Test 환경에서 먼저 검증 후 단계적으로 적용.

### 2-2. 서비스 재시작 (무중단 원칙)

```bash
# Helm 환경에서 libvirt Pod 롤링 재시작
kubectl rollout restart daemonset/libvirt -n openstack
kubectl rollout status daemonset/libvirt -n openstack --timeout=10m

# 기존 VM은 기동 중인 프로파일을 유지함 → 즉시 재기동 불필요
# 새로 기동되는 VM부터 신규 설정 적용
```

### 2-3. 적용 확인

```bash
# 각 VM별 AppArmor 프로파일 확인 (증적 E-02)
for pid in $(pgrep -f qemu-system); do
  echo "PID $pid:"
  cat /proc/$pid/attr/current
done
# 기대 출력: libvirt-<UUID> (enforce)

# sVirt 활성 상태 (증적 E-01)
virsh capabilities | grep -A2 secmodel
```

---

## 3. AppArmor 커스텀 프로파일 보강 (Phase 2: Week 5~8)

### 3-1. libvirt 기본 프로파일 위치

- `/etc/apparmor.d/abstractions/libvirt-qemu` — 공통 허용 규칙
- `/etc/apparmor.d/libvirt/TEMPLATE.qemu` — VM별 프로파일 템플릿
- `/etc/apparmor.d/libvirt/libvirt-<UUID>` — VM 기동 시 동적 생성

### 3-2. CSAP 관점 보강 지점

다음 항목은 **기본 프로파일이 허용하지만 CSAP 관점에서 추가 제한이 필요한** 영역:

| 항목 | 기본 | v2.0 보강 | 근거 |
| --- | --- | --- | --- |
| `/proc/sys/kernel/*` 쓰기 | 일부 허용 | **deny 추가** | VM 탈출 방지 |
| `/sys/firmware/**` | 읽기 | **deny** | 펌웨어 정보 누출 방지 |
| `ptrace (peer=unconfined)` | 허용 | **deny** | 하이퍼바이저 프로세스 공격 차단 |
| `capability sys_module` | 허용 | **deny** | VM에서 커널 모듈 로드 차단 |
| `mount` | 조건부 | **deny (명시)** | 호스트 FS 마운트 차단 |

### 3-3. 커스텀 보강 규칙 예시

`/etc/apparmor.d/local/abstractions/libvirt-qemu` (local 디렉터리는 패키지 업데이트 시에도 유지됨):

```
# v2.0 CSAP 보강 규칙
# 파일: /etc/apparmor.d/local/abstractions/libvirt-qemu

# 커널 내부 상태 변경 차단
deny /proc/sys/kernel/** w,
deny /proc/*/clear_refs w,
deny /proc/kcore r,

# 펌웨어·부트 정보 접근 차단
deny /sys/firmware/** rwklx,
deny /boot/** rwklx,

# 하이퍼바이저 프로세스 공격 차단
deny ptrace peer=unconfined,
deny ptrace peer=/usr/sbin/libvirtd,

# 커널 모듈 조작 차단
deny capability sys_module,
deny /lib/modules/** w,

# 호스트 네트워크 스택 직접 조작 차단
deny capability net_admin,  # virtio-net은 이미 허용됨, 추가 capability 차단
```

> **주의**: `deny capability net_admin`은 일부 네트워크 구성에서 문제가 될 수 있음. **Test 환경에서 반드시 검증** 후 Dev·운영으로 이관.

### 3-4. 프로파일 로드·활성화

```bash
# 구문 검사
apparmor_parser -Q /etc/apparmor.d/local/abstractions/libvirt-qemu

# 적용 (enforce 모드)
apparmor_parser -r /etc/apparmor.d/abstractions/libvirt-qemu

# 신규 VM부터 적용됨. 기존 VM은 재기동 시 신규 프로파일 적용.

# 상태 확인
aa-status | grep libvirt
```

---

## 4. 검증 시나리오 (각 Phase 종료 시점)

### 4-1. 기본 동작 검증 (Week 4·8·12 공통)

```bash
# 4-1-1. VM 기동 성공률
for i in {1..20}; do
  openstack server create --image cirros --flavor m1.tiny \
    --network private --wait test-vm-$i
done
openstack server list --name test-vm- -f value -c Status | sort | uniq -c
# 기대: ACTIVE 20

# 4-1-2. 라이브 마이그레이션 성공
for vm in $(openstack server list --name test-vm- -f value -c ID); do
  openstack server migrate --live-migration --wait $vm
done

# 4-1-3. AppArmor DENIED 로그 확인 (증적 E-09)
grep 'apparmor="DENIED"' /var/log/syslog | grep qemu | tail -50
# 이 로그는 MAC이 실제로 동작 중이라는 증거가 됨
```

### 4-2. 침투 검증 (Phase 2 이후 선택적)

**sVirt VM 격리 테스트** (VM 내부에서 실행):

```bash
# VM 내부에서 호스트 프로세스 접근 시도 → 실패해야 정상
cat /proc/1/maps 2>&1 | head   # VM 내부의 init(1)만 보여야 함
ls /sys/firmware/efi/           # 또는 deny 로그 생성되어야 함
```

**호스트에서 sVirt 경계 테스트**:

```bash
# 다른 VM의 디스크에 접근 시도 (별도 VM 프로파일이므로 차단되어야 함)
# VM A의 qemu 프로세스가 VM B의 /var/lib/nova/instances/<B-UUID>/disk 를 open할 수 없음
```

---

## 5. 롤백 기준·절차

### 5-1. 롤백 트리거 (하나라도 해당 시 즉시 중단)

| # | 조건 | 측정 방법 |
| --- | --- | --- |
| R-01 | VM 기동 실패율 > 1% | `nova-api.log` ERROR 집계 |
| R-02 | 라이브 마이그레이션 실패율 > 0.5% | `nova-compute.log` 집계 |
| R-03 | 디스크 I/O p95 > 기준선 +5% | `fio` 벤치마크 |
| R-04 | 이유 불명 DENIED 로그 급증 (정상 업무 차단) | `syslog` 모니터링 |

### 5-2. 단계별 롤백 방법

**1단계 — 프로파일만 roll back** (사용자 업무 영향 없음):

```bash
# 보강 프로파일 비활성화
mv /etc/apparmor.d/local/abstractions/libvirt-qemu{,.disabled}
apparmor_parser -r /etc/apparmor.d/abstractions/libvirt-qemu
```

**2단계 — sVirt complain 모드 전환** (강제 차단 해제, 로그만 수집):

```bash
# /etc/libvirt/qemu.conf
security_default_confined = 1
security_require_confined = 0   # 0으로 변경
# libvirt 재시작 (2-2 참고)
```

**3단계 — sVirt 완전 비활성화** (최후 수단, KISA 심사 후):

```bash
# /etc/libvirt/qemu.conf
security_driver = "none"
# 단, 이 경우 KISA 재심사 필요 → 실질적으로 선택 불가
```

---

## 6. 증적 수집 자동화 (가이드 02와 연동)

### 6-1. 일일 증적 스크립트 확장

`02_보완통제_증적수집_가이드.md`의 `csap-evidence-collect.sh`에 MAC 전용 섹션 추가:

```bash
# MAC 전용 증적 블록 (가이드 02 스크립트에 병합)

echo "=== E-01: sVirt 활성 상태 ==="
virsh capabilities | grep -A2 secmodel | tee -a $LOG

echo "=== E-02: VM별 AppArmor 프로파일 적용 ==="
for pid in $(pgrep -f qemu-system); do
  uuid=$(cat /proc/$pid/cmdline | tr '\0' ' ' | grep -oP 'guest=\K[^,]+')
  prof=$(cat /proc/$pid/attr/current)
  echo "VM=$uuid PID=$pid profile=$prof" | tee -a $LOG
done

echo "=== E-09: 최근 24h DENIED 이벤트 ==="
journalctl --since="24 hours ago" | grep 'apparmor="DENIED"' | \
  awk '{print $0}' | tee -a $LOG
```

### 6-2. KISA 심사장 시연 3분 시나리오

1. **(30초)** `virsh capabilities | grep secmodel` → sVirt 활성 증명
2. **(60초)** 실행 중 VM 10개 선택 → 각각 `/proc/$pid/attr/current`로 고유 프로파일 확인
3. **(60초)** 의도적 `deny` 규칙 위반 시도 → `/var/log/syslog`에 DENIED 이벤트 실시간 출력
4. **(30초)** `aa-status` 로 enforce 모드 전체 요약

---

## 7. Dev → 운영 이관 체크리스트 (Phase 3: Week 9~12)

### 7-1. 이관 전 필수 조건

- [ ] Test·Dev 환경에서 **4주 이상** 무장애 운영
- [ ] 4-1 검증 시나리오 **100% 통과**
- [ ] 롤백 절차 실제 모의훈련 1회 이상 완료
- [ ] CISO·인프라 운영팀·보안팀 3자 서명 승인
- [ ] 증적 자동수집 cron 정상 동작 확인 (2주 연속)

### 7-2. 이관 순서

1. **Week 9**: 운영 환경 1개 Compute 노드 선정 (비핵심 워크로드)
2. **Week 10**: 해당 노드에 sVirt + 커스텀 프로파일 적용, 1주 모니터링
3. **Week 11**: 문제 없으면 전체 노드의 25% 적용
4. **Week 12**: 75% → 100% 확대, 최종 증적 패키징

### 7-3. 핵심 운영 Do / Don't

| Do | Don't |
| --- | --- |
| ✅ 프로파일 변경은 반드시 git 이력 관리 | ❌ `aa-complain` 일괄 전환 금지 |
| ✅ DENIED 로그 주간 리뷰 | ❌ 문제 발생 시 프로파일 즉시 삭제 금지 |
| ✅ 커널·libvirt 업데이트 전 Test 선검증 | ❌ 운영 노드에서 프로파일 직접 편집 금지 |
| ✅ 롤백 기준 정량 지표 기반 판단 | ❌ 심사관 압박으로 설정 즉시 완화 금지 |

---

## 8. 자주 발생하는 문제·해결

| 증상 | 원인 | 해결 |
| --- | --- | --- |
| VM 기동 실패, `Permission denied` | 커스텀 프로파일이 필요 경로 차단 | `/var/log/syslog`에서 DENIED 경로 확인 후 프로파일 예외 추가 |
| 라이브 마이그레이션 중 중단 | 소스·타겟 노드 프로파일 불일치 | 양쪽 노드 프로파일 버전 동기화 |
| AppArmor 프로파일 로드 실패 | 구문 오류 | `apparmor_parser -Q`로 사전 검증 |
| `aa-status`에 libvirt 프로파일 미표시 | libvirt 서비스 미재시작 | `systemctl restart libvirtd` (또는 Helm Pod 재시작) |
| Ceph RBD 볼륨 마운트 실패 | 프로파일이 RBD device 경로 미허용 | `/dev/rbd*`, `/sys/bus/rbd/**` 허용 규칙 추가 |

---

## 9. 문서 간 매핑

| 이 문서 섹션 | 연관 문서 |
| --- | --- |
| §1 사전 점검 | `06_PoC_측정계획서.md` Phase 0 |
| §2 sVirt 활성화 | `01_운영정책서.md` MAC(Primary) 조항 |
| §3 커스텀 프로파일 | `하이퍼바이저백신요건대응논리.md` §3 주장2 |
| §4 검증 시나리오 | `02_보완통제_증적수집_가이드.md` E-01, E-02, E-09 |
| §5 롤백 기준 | `03_악성코드_대응절차서.md` Stage 3 복구 |
| §6 증적 자동화 | `02_보완통제_증적수집_가이드.md` 통합 스크립트 |

---

## 10. 변경 이력

| 버전 | 일자 | 변경 사항 |
| --- | --- | --- |
| v1.0 | 이전 | AV + MAC 병행 전제, Helm 고려 미흡 |
| v2.0 | 2026-04 | **MAC Primary 격상, 3개월 로드맵 연동, 롤백 기준·절차 명시, Helm 기반 경로 반영, 커스텀 보강 규칙 예시 추가** |

---

**작성**: CI-TEC 하이퍼바이저 백신 대응 TF
**승인 요청**: CISO · 인프라운영팀장 · 정보보호팀장
