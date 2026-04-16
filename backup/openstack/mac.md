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
