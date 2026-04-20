# 06. PoC 측정계획서 — MAC 검증·전사 적용 3개월 로드맵 v2.0

> **문서 목적**: CSAP 심사관에게 제출할 "3개월 내 MAC 검증·적용 완료" 계획 및 중간 측정 증적
> **대상 환경**: SCPv2 Sovereign(PG) 상암/춘천 — OpenStack Helm + Ubuntu 22.04/24.04 혼재 + GPU/HCN 노드 포함
> **실행 기간**: 2026-04-20 ~ 2026-07-20 (3개월)
> **버전**: v2.0 (방향 전환: AV 성능 측정 → MAC 운영화 검증)

---

## 1. 전체 계획 요약

### 1-1. 3개월 로드맵

| Phase | 기간 | 대상 환경 | 주요 목표 | 심사 대응 |
|-------|------|-----------|----------|----------|
| **Phase 0** | 4/20~4/26 | 전 환경 | 프로파일 템플릿 작성 + baseline 수집 | - |
| **Phase 1** | **4/27~5/17** (3주) | **Test 환경만** | Complain → Enforce 전환 + 3주 안정성 검증 | **사전점검(~4/29)**: Phase 1 진행<br>**본심사(5/18 ~ 22)**: Phase 1 완료 증적 제출 |
| **Phase 2** | 5/23~6/13 (3주) | **Dev 환경** | Complain → Enforce + 성능/보안 검증 | 본심사 **통과 후** 본격 시작 |
| **Phase 3-1** | 6/14~6/28 | 운영 Canary (3~5노드) | Complain → Enforce | - |
| **Phase 3-2** | 6/29~7/12 | 운영 환경 50% | Enforce 확대 | - |
| **Phase 3-3** | 7/13~7/20 | 운영 환경 전 노드 | Enforce 100% 완료 | 3개월 내 목표 달성 |

### 1-2. 심사 대응 타임라인 상 위치

| 심사 이벤트 | 일자 | PoC Phase 진행 상태 | 제출 증적 수준 |
| --- | --- | --- | --- |
| 사전점검 (노브레이크) | ~4/29 | **Phase 1 완료 중** | Test 환경 검증 결과 + 전사 로드맵 |
| 예비심사 (KISA) | ~5/15 | **Phase 2 진행 중** | Dev 환경 운영 증적 + Canary 개시 |
| **본심사 (KISA)** | **5/18~22** | **Phase 2 완료, Phase 3 Canary 운영** | **운영 환경 Canary 증적** |
| 사후평가 (연 1회) | 2027년 | **Phase 3 완료 후 전사 운영** | **전 운영 환경 enforce 증적** |

---

## 2. Phase 0: 사전 준비 (Week 1)

### 2-1. 목표

- 현재 환경의 MAC 운영 상태 baseline 수집
- 3종 AppArmor 프로파일 템플릿 완성 (KVM 일반 / GPU / HCN)
- Ansible Playbook 배포 자동화 준비

### 2-2. Task

| # | Task | 담당 | 산출물 |
| --- | --- | --- | --- |
| 0-1 | 전 컴퓨트 노드 aa-status baseline 수집 | CI-TEC | JSON 파일 |
| 0-2 | VM 워크로드 인벤토리 (일반/GPU/HCN 비중) | SCPv2 운영 | 인벤토리 표 |
| 0-3 | Ubuntu 22.04 vs 24.04 노드 비중 확인 | CI-TEC | 노드 분류표 |
| 0-4 | KVM 프로파일 TEMPLATE.qemu 작성 | CI-TEC | 프로파일 파일 |
| 0-5 | GPU 프로파일 TEMPLATE.qemu.gpu 작성 | CI-TEC | 프로파일 파일 |
| 0-6 | HCN 프로파일 TEMPLATE.qemu.hcn 작성 | CI-TEC | 프로파일 파일 |
| 0-7 | Ansible Playbook 작성·검증 | CI-TEC | `apparmor-deploy.yml` |
| 0-8 | GitLab 저장소 생성 및 접근 권한 설정 | CI-TEC | `scpv2-security/apparmor-profiles` |

### 2-3. 완료 기준

- [ ] 전 컴퓨트 노드 aa-status 수집 완료
- [ ] 3종 프로파일 템플릿 코드 리뷰 완료
- [ ] Ansible Playbook dry-run 성공
- [ ] GitLab 저장소 초기 커밋 완료

---

## 3. Phase 1: Test 환경 검증 (Week 2~4)

### 3-1. 목표

Test 환경(osh1)에서 3종 프로파일의 기능·성능·보안을 검증.

### 3-2. Task 상세

#### Week 2: Complain 모드 배포

```bash
# Step 1: Test 환경 모든 노드에 AppArmor 활성화
ansible osh1 -i inventory/osh1 -m systemd -a "name=apparmor state=started enabled=yes" --become

# Step 2: 프로파일 배포
ansible-playbook -i inventory/osh1 playbooks/apparmor-deploy.yml --extra-vars "mode=complain"

# Step 3: libvirt Helm values 업데이트
helm upgrade libvirt openstack-helm-infra/libvirt \
  -n openstack \
  -f values/libvirt-values-mac.yaml

# Step 4: libvirt Pod 재시작
kubectl delete pod -n openstack -l application=libvirt --wait=false

# Step 5: 검증 VM 스폰
for i in $(seq 1 10); do
  openstack server create --image ubuntu-22.04 --flavor m1.small \
    --network private --key-name test-key test-vm-$i
done
```

#### Week 3: 로그 수집 및 프로파일 튜닝

- 2주간 `apparmor="DENIED"` 로그 전수 수집
- `aa-logprof` 인터랙티브 프로파일 개선
- 주요 시나리오(VM 부팅/마이그레이션/볼륨 attach) 각 10회 실행

#### Week 4: Enforce 모드 전환

```bash
ansible-playbook -i inventory/osh1 playbooks/apparmor-deploy.yml --extra-vars "mode=enforce"

# 검증
ansible osh1 -i inventory/osh1 -m shell -a "aa-status --json" --become > phase1-enforce-verify.json
```

### 3-3. 합격 기준 (3종)

| 범주 | 측정 항목 | 합격 기준 |
| --- | --- | --- |
| **기능** | VM 부팅 성공률 | 100% (10/10) |
| 기능 | VM 재부팅 성공률 | 100% |
| 기능 | 볼륨 attach/detach | 100% |
| 기능 | 라이브 마이그레이션 | 100% |
| 기능 | 콘솔 접속 | 100% |
| **성능** | VM 부팅 시간 | baseline +5% 이내 |
| 성능 | 디스크 IOPS (fio, 4K random read) | baseline -3% 이내 |
| 성능 | 네트워크 처리량 (iperf3) | baseline -3% 이내 |
| 성능 | CPU 오버헤드 (idle 시) | baseline +1% 이내 |
| **보안** | VM 간 격리 검증 | 타 VM 이미지 접근 시 DENIED |
| 보안 | 호스트 파일 보호 검증 | /root 접근 시도 시 DENIED |
| 보안 | sVirt 활성 | `virsh capabilities` apparmor 표시 |
| 보안 | VM별 프로파일 | 실행 VM 수 == libvirt-<uuid> 프로파일 수 |

### 3-4. Phase 1 증적 (사전점검 제출)

| 증적 # | 내용 | 형식 |
| --- | --- | --- |
| P1-E1 | Before/After aa-status 비교 | JSON 파일 2개 |
| P1-E2 | 기능 검증 체크리스트 (100% 합격) | Excel 표 |
| P1-E3 | 성능 벤치마크 보고서 | PDF |
| P1-E4 | 보안 검증 시나리오 실행 결과 | 스크린샷 + 로그 |
| P1-E5 | AppArmor DENIED 로그 2주 집계 | 집계 보고서 |

---

## 4. Phase 2: Dev 환경 적용 (Week 5~8)

### 4-1. 목표

Dev 환경 전체에 Complain 배포 후 Enforce 전환. Ubuntu 22.04/24.04 혼재 및 GPU/HCN 특수 환경 검증.

### 4-2. Task 상세

#### Week 5: Dev 일반 compute 노드 Complain

```bash
ansible dev_compute -m systemd -a "name=apparmor state=started enabled=yes" --become
ansible-playbook playbooks/apparmor-deploy.yml -e "mode=complain" -l dev_compute
```

#### Week 6: Dev GPU/HCN 노드 Complain + 프로파일 조정

- VFIO 디바이스 접근 필요 경로 프로파일 반영
- NVIDIA UVM, NVIDIA-CTL 접근 경로 허용

#### Week 7: 2주 관찰 후 Enforce 전환 (일반 → GPU/HCN 순)

#### Week 8: 최종 검증 + 운영 문서화

### 4-3. 특수 환경 검증 포인트

| 환경 | 추가 검증 | 주의 |
| --- | --- | --- |
| Ubuntu 22.04 | AppArmor 3.0 기본 동작 | — |
| Ubuntu 24.04 | **AppArmor 4.0 신규 제약** — Unprivileged User NS | 별도 프로파일 필요 |
| GPU 노드 | VFIO passthrough + CUDA 실행 | 별도 프로파일 |
| HCN 노드 | 다중 NUMA, 대용량 메모리 핫플러그 | 별도 프로파일 |

### 4-4. Phase 2 증적 (예비심사 제출)

| 증적 # | 내용 |
| --- | --- |
| P2-E1 | 4종 환경별 프로파일 최종본 (Git commit hash) |
| P2-E2 | Dev 환경 전 노드 enforce 모드 `aa-status` 수집 |
| P2-E3 | GPU VM 정상 동작 증빙 (`nvidia-smi` 출력) |
| P2-E4 | 8주간 AppArmor DENIED 통계 (주별 추이) |
| P2-E5 | 라이브 마이그레이션 성공률 (100회 실행 기준) |

### 4-5. 합격 기준

- [ ] 4종 환경(Ubuntu 22.04, 24.04, GPU, HCN) 모두 enforce 모드 동작
- [ ] 운영 시나리오 성공률 100%
- [ ] DENIED 로그 주간 평균 < 10건 (정상 운영 중 프로파일 fit)
- [ ] 성능 저하 < 3%

---

## 5. Phase 3: 운영 환경 적용 (Week 9~12)

### 5-1. 목표

운영 환경에 **Canary → 전 노드 Complain → Enforce** 3단계 점진 적용.

### 5-2. Task 상세

#### Week 9: Canary 1개 노드 Complain

- 최소 영향 노드 1개 선정 (신규 VM 우선 배치 가능한 노드)
- 2주 집중 모니터링 (시간당 DENIED 알림)

#### Week 10: Canary 성공 시 전 운영 노드 Complain

```bash
# 운영 전 노드에 Complain 배포 (Ansible 배치 제어)
ansible-playbook playbooks/apparmor-deploy.yml -e "mode=complain" -l prod_compute \
  --forks 5 --serial 10  # 한 번에 10개씩 배포
```

#### Week 11~12: Complain 운영 + DENIED 0 달성 후 Enforce 전환

- 2주 Complain 운영하여 DENIED 로그 0건 달성
- 하루 1개 노드씩 Enforce 전환 (문제 발생 즉시 회귀)

### 5-3. 운영 Canary 기준

| 지표 | Canary 합격 기준 |
| --- | --- |
| VM 부팅 실패율 | 0% |
| 라이브 마이그레이션 실패 | 0건 |
| 고객 티켓 접수 | 0건 |
| AppArmor DENIED | 일평균 < 5건 (정상 프로파일 fit) |
| 성능 모니터링 | SLA 100% 준수 |

### 5-4. 롤백 기준 및 절차

| 조건 | 조치 |
| --- | --- |
| VM 부팅 실패율 > 1% | 즉시 complain 모드 회귀 |
| 라이브 마이그레이션 실패 발생 | 즉시 complain 회귀 + 프로파일 수정 |
| 성능 저하 > 5% | 원인 조사, 필요 시 complain 회귀 |
| 고객 장애 신고 | **전체 롤백** + 원인 분석 |

**롤백 명령**:
```bash
# 긴급 전체 롤백 (Ansible)
ansible prod_compute -m shell -a "aa-complain /etc/apparmor.d/libvirt/TEMPLATE.qemu" --become
```

### 5-5. Phase 3 증적 (본심사 제출)

| 증적 # | 내용 |
| --- | --- |
| P3-E1 | Canary 노드 2주 운영 증적 (시계열 그래프) |
| P3-E2 | 전 운영 노드 aa-status 수집 결과 |
| P3-E3 | 운영 환경 VM별 프로파일 자동 생성 증적 |
| P3-E4 | SLA 준수 증적 (가용성 99.99% 유지) |
| P3-E5 | 침해 시도 차단 사례 (있을 경우) |

---

## 6. 측정 상세: 성능 벤치마크 방법론

### 6-1. 벤치마크 대상 워크로드

| 워크로드 | 도구 | 파라미터 |
| --- | --- | --- |
| Disk IOPS (Random Read) | fio | `--rw=randread --bs=4K --iodepth=32 --numjobs=4 --runtime=120` |
| Disk Throughput (Seq Write) | fio | `--rw=write --bs=1M --iodepth=16 --numjobs=1` |
| Network Throughput | iperf3 | `-P 4 -t 60` |
| Network Latency | ping | `-c 100 -i 0.1` |
| VM 부팅 시간 | time | `openstack server create --wait` |
| CPU Stress | stress-ng | `--cpu 4 --cpu-method matrixprod --timeout 60s` |

### 6-2. 측정 시나리오

각 항목에 대해:
1. **Baseline (AppArmor 비활성)**: 10회 측정, 중앙값 사용
2. **Complain 모드**: 10회 측정
3. **Enforce 모드**: 10회 측정

비교: `(Enforce 중앙값 - Baseline 중앙값) / Baseline 중앙값 × 100 (%)`

### 6-3. 측정 환경

| 구분 | 상세 |
| --- | --- |
| Compute 노드 | Ubuntu 22.04 / 24.04 각 3대 |
| VM 사양 | m1.large (vCPU 4, RAM 8GB, Disk 40GB) |
| Ceph 볼륨 | RBD SSD Pool |
| 네트워크 | OVS (VXLAN 오버레이) |

---

## 7. 모니터링 및 알림

### 7-1. 대시보드 구성

| 대시보드 | 지표 | 도구 |
| --- | --- | --- |
| MAC 상태 대시보드 | aa-status 결과, DENIED 건수 | Grafana + Prometheus |
| 성능 대시보드 | IOPS, 처리량, latency | Grafana |
| 사고 대시보드 | AppArmor 탐지·조치 이력 | Splunk |

### 7-2. Alert 룰

| Alert | 임계치 | 조치 |
| --- | --- | --- |
| DENIED 급증 | 단일 호스트 1시간 내 100건 | SOC Alert |
| aa-status 변경 | 프로파일 수 감소 | SCPv2 운영 Alert |
| 성능 저하 | IOPS 10% 하락 | CI-TEC 조사 |
| VM 부팅 실패 | 24시간 내 5회 | SCPv2 운영 조사 |

---

## 8. 리소스 및 예산

### 8-1. 인력 배정

| 역할 | FTE | 기간 |
| --- | --- | --- |
| CI-TEC 기술 리드 | 0.5 | 3개월 |
| SCPv2 운영 대리 | 0.3 | 3개월 |
| 정보보호팀 검토 | 0.1 | 3개월 |
| 외부 보안 컨설팅 (선택) | — | 필요 시 |

### 8-2. 일정 리스크

| 리스크 | 완화 |
| --- | --- |
| Phase 1 지연 (프로파일 튜닝 난이도) | Week 2-4 내 완료 목표, 1주 버퍼 확보 |
| GPU/HCN 프로파일 미해결 | Phase 2 Week 6-7에 집중 |
| 운영 변경 freeze 기간 | 운영 일정과 사전 동기화 필수 |

---

## 9. 외부 검증 (선택)

### 9-1. 외부 모의해킹 (연말 계획)

- Phase 3 완료 후 외부 보안 전문업체 침투 테스트
- 시나리오: VM Escape 시도, 호스트 권한 상승 시도
- 결과: 연례 CSAP 사후평가 증적으로 활용

### 9-2. 벤더 의견서 (선택)

- Canonical(Ubuntu) 또는 Red Hat 파트너 채널 통해 "OpenStack Helm + AppArmor 베스트 프랙티스" 서면 회신 확보 시도

---

## 10. 심사별 제출 패키지

### 10-1. 사전점검 (~4/29)
- Phase 0 + Phase 1 진행 상황 + Test 환경 중간 결과

### 10-2. 본심사 (5/18 ~ 22)
- Phase 1 **완료 증적** (Test 환경 3주 enforce 운영 결과)
- Phase 2~3 **상세 계획서** (본심사 통과 후 Dev부터 적용 계획)
- "Test 환경에서 이미 검증 완료, 본심사 통과 시 즉시 Dev 환경 적용 착수" 강조

### 10-3. 본심사 이후 제출 (사후평가 연계)
- Phase 2 완료 증적
- Phase 3 Canary~ 전사 적용 결과

---

## 11. 변경 이력

| 버전 | 일자 | 변경 내역 |
| --- | --- | --- |
| v1.0 | 2026-04-15 | 초안 (AV 실시간 스캔 ON/OFF 성능 측정) |
| **v2.0** | **2026-04-20** | **방향 전환: AV 성능 측정 제거, MAC 3개월 로드맵 전면 재작성** |

---

## 12. 부속 자료

- `OpenStack-MAC-적용가이드.md` — 기술 상세 가이드 (Phase별 상세 명령 포함)
- GitLab: `scpv2-security/apparmor-profiles` — 프로파일 템플릿 저장소
- Ansible: `playbooks/apparmor-deploy.yml` — 자동 배포 Playbook
