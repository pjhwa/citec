# FIM (File Integrity Monitoring) 적용 계획서 v1.0

**문서 ID**: SCPv2-FIM-PLAN-001  
**버전**: 1.0  
**작성일**: 2026-04-21  
**대상 환경**: SCPv2 Sovereign(PG) 상암/춘천 — Ubuntu 22.04/24.04 + OpenStack Helm KVM

---

## 1. 문서 개요

### 1-1. 목적

본 계획서는 CSAP 9.1.4-③ 「하이퍼바이저 악성코드 보호」 요건을 충족하기 위한 **FIM(File Integrity Monitoring)**의 상세 적용 계획을 수립한다.

FIM은 MAC(sVirt/AppArmor)과 함께 **보완통제**의 핵심 요소로서, 호스트 OS의 중요 파일 변경을 실시간/주기적으로 탐지하여 악성코드 침투, 설정 변조, 권한 상승 공격 등을 조기에 발견하는 역할을 수행한다.

### 1-2. 적용 범위

- **대상 시스템**: SCPv2 컴퓨트 노드 전체 (상암/춘천)
- **대상 OS**: Ubuntu 22.04 LTS / 24.04 LTS
- **FIM 도구**: **AIDE (Advanced Intrusion Detection Environment)**
- **제외 대상**: VM 디스크 이미지 (`/var/lib/nova/instances/*`) — 동적 변경이 발생하므로 제외

### 1-3. 관련 문서

- `01_운영정책서_하이퍼바이저_백신.md` (호스트 OS 최소화 + FIM 정의)
- `02_보완통제_증적수집_가이드.md` (E-06~E-07 AIDE 증적 수집)
- `03_악성코드_대응절차서.md` (FIM을 탐지 채널로 활용)
- `06_PoC_측정계획서.md` (Phase별 FIM 검증 계획)
- `07_OpenStack-MAC-적용가이드.md`

---

## 2. FIM 도구 선정 및 아키텍처

### 2-1. AIDE 선정 이유

| 평가 항목 | AIDE | OSSEC | Samhain | 비고 |
|-----------|------|-------|---------|------|
| Ubuntu 공식 지원 | ★★★★★ | ★★★★☆ | ★★★☆☆ | Canonical 패키지 제공 |
| 성능 오버헤드 | ★★★★★ (매우 낮음) | ★★★☆☆ | ★★★★☆ | AIDE가 가장 가벼움 |
| 설정 유연성 | ★★★★★ | ★★★★☆ | ★★★★☆ | 정규식 기반 규칙 강력 |
| SIEM 연동 용이성 | ★★★★★ | ★★★★★ | ★★★★☆ | 텍스트 로그 + JSON 지원 |
| CSAP 증적 적합성 | ★★★★★ | ★★★★☆ | ★★★★☆ | 일일 보고서 + 변경 이력 명확 |

**결론**: Ubuntu 환경 + OpenStack Helm + CSAP 증적 요구사항에 가장 적합한 도구는 **AIDE**이다.

### 2-2. 전체 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│                    Compute Node (Ubuntu)                     │
├─────────────────────────────────────────────────────────────┤
│  [AIDE]                                                      │
│   ├── /etc/aide/aide.conf          (감시 규칙)               │
│   ├── /var/lib/aide/aide.db        (베이스라인 DB)           │
│   └── /var/log/aide/               (검사 결과 로그)          │
│                                                              │
│  [Cron]  03:00 매일                                            │
│   └── /usr/local/bin/aide-daily-check.sh                     │
│                                                              │
│  [OpenSearch] (SIEM)                                          │
│   ├── index: scpv2-fim-*                                      │
│   └── Alert Rule: 파일 변경 시 Slack + PagerDuty             │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. 상세 설정 가이드

### 3-1. AIDE 설치

```bash
# Ubuntu 22.04 / 24.04
sudo apt update
sudo apt install aide aide-common -y

# 버전 확인
aide --version
```

### 3-2. aide.conf 상세 설정 (권장)

**파일 위치**: `/etc/aide/aide.conf`

```conf
# =============================================
# SCPv2 FIM 정책 - Compute Node 전용 (v1.0)
# =============================================

# 기본 설정
database=file:/var/lib/aide/aide.db
database_out=file:/var/lib/aide/aide.db.new
gzip_dbout=yes
report_url=stdout
report_url=file:/var/log/aide/aide-check-$(date +%Y%m%d).log
report_format=plain

# =============================================
# 감시 규칙 (정규식 지원)
# =============================================

# 1. 핵심 시스템 디렉터리 (최고 수준 감시)
=/boot                    NORMAL
=/bin                     NORMAL
=/sbin                    NORMAL
=/usr/bin                 NORMAL
=/usr/sbin                NORMAL
=/usr/local/bin           NORMAL
=/usr/local/sbin          NORMAL
=/lib                     NORMAL
=/lib64                   NORMAL
=/lib/x86_64-linux-gnu    NORMAL

# 2. 설정 파일 (변경 탐지 최우선)
=/etc                     NORMAL
=/etc/apparmor.d          NORMAL
=/etc/libvirt             NORMAL
=/etc/nova                NORMAL          # Helm 환경에서는 /etc/nova가 호스트에 있을 수 있음
=/etc/openvswitch         NORMAL

# 3. 보안 도구 관련
=/etc/aide                NORMAL
=/etc/audit               NORMAL
=/etc/rsyslog.d           NORMAL

# 4. 커널 및 부팅 관련
=/boot/vmlinuz*           NORMAL
=/boot/initrd*            NORMAL
=/boot/System.map*        NORMAL

# =============================================
# 제외 규칙 (중요!)
# =============================================

# VM 디스크 이미지 (동적 변경 발생 → 반드시 제외)
!/var/lib/nova/instances

# libvirt/QEMU 동적 파일
!/var/lib/libvirt/qemu
!/var/lib/libvirt/images

# 로그 디렉터리 (너무 많은 변경 발생)
!/var/log
!/var/log/aide

# 임시/런타임 파일
!/tmp
!/var/tmp
!/var/run
!/run
!/proc
!/sys
!/dev

# 패키지 관리자 캐시
!/var/cache/apt
!/var/lib/apt

# =============================================
# 사용자 정의 그룹 (선택)
# =============================================

# HIGH = 매우 중요한 파일 (변경 시 즉시 Alert)
HIGH = p+i+n+u+g+s+b+acl+xattrs+sha512

# NORMAL = 일반 중요 파일
NORMAL = p+i+n+u+g+s+b+acl+xattrs+sha512

# =============================================
# 끝
# =============================================
```

### 3-3. 베이스라인 생성

```bash
# 초기 베이스라인 생성 (최초 1회)
sudo aideinit

# 생성된 DB 이동
sudo mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db

# 백업 (중요!)
sudo cp /var/lib/aide/aide.db /var/lib/aide/aide.db.$(date +%Y%m%d).bak
```

---

## 4. 운영 절차

### 4-1. 일일 검사 스크립트 (자동화)

**파일 위치**: `/usr/local/bin/aide-daily-check.sh`

```bash
#!/bin/bash
# SCPv2 FIM 일일 검사 스크립트 v1.0

LOG_DIR="/var/log/aide"
REPORT_FILE="${LOG_DIR}/aide-check-$(date +%Y%m%d).log"
DB_FILE="/var/lib/aide/aide.db"
DB_NEW="/var/lib/aide/aide.db.new"

mkdir -p "$LOG_DIR"

echo "=== AIDE Daily Check Started: $(date) ===" | tee "$REPORT_FILE"

# AIDE 검사 실행
/usr/bin/aide --check > "$REPORT_FILE" 2>&1
RESULT=$?

echo "=== AIDE Check Finished: $(date) ===" | tee -a "$REPORT_FILE"

# 결과 처리
if [ $RESULT -ne 0 ]; then
    # 변경 탐지됨
    echo "[ALERT] File integrity changes detected!" | tee -a "$REPORT_FILE"
    
    # OpenSearch로 전송 (예시)
    curl -X POST "https://opensearch.internal:9200/scpv2-fim-$(date +%Y.%m.%d)/_doc" \
        -H "Content-Type: application/json" \
        -d @- <<EOF
{
    "@timestamp": "$(date -Iseconds)",
    "host": "$(hostname)",
    "event": "fim_change_detected",
    "severity": "high",
    "report_file": "$REPORT_FILE",
    "summary": "$(tail -20 $REPORT_FILE | grep -E 'changed|added|removed' | head -5)"
}
EOF

    # Alert (Slack / PagerDuty)
    # /usr/local/bin/send-fim-alert.sh "$REPORT_FILE"
    
    # 로그 보관
    cp "$REPORT_FILE" "/mnt/audit-archive/aide/"
else
    echo "[INFO] No changes detected." | tee -a "$REPORT_FILE"
fi

# 오래된 로그 정리 (90일)
find "$LOG_DIR" -name "aide-check-*.log" -mtime +90 -delete
```

**Cron 등록**:
```bash
# /etc/cron.d/aide-daily
0 3 * * * root /usr/local/bin/aide-daily-check.sh
```

### 4-2. 베이스라인 갱신 절차 (승인 필요)

베이스라인 갱신은 **보안팀 승인 후**에만 수행:

1. 변경 사유 문서 작성 (커널 패치, 보안 업데이트 등)
2. CISO 또는 보안팀장 승인
3. `aide --update` 실행
4. 새 DB로 교체 + 백업
5. Git에 변경 이력 기록

---

## 5. OpenSearch (SIEM) 연동

### 5-1. 인덱스 매핑 예시

```json
{
  "index_patterns": ["scpv2-fim-*"],
  "template": {
    "mappings": {
      "properties": {
        "@timestamp": { "type": "date" },
        "host": { "type": "keyword" },
        "event": { "type": "keyword" },
        "severity": { "type": "keyword" },
        "changed_files": { "type": "text" },
        "report_path": { "type": "keyword" }
      }
    }
  }
}
```

### 5-2. Alert 규칙 (권장)

| 조건 | 심각도 | 액션 |
|------|--------|------|
| 1시간 내 5개 이상 파일 변경 | High | Slack + PagerDuty 즉시 호출 |
| `/etc/apparmor.d` 또는 `/etc/libvirt` 변경 | Critical | SOC + CISO 즉시 에스컬레이션 |
| `/boot` 또는 `/etc` 하위 10개 이상 변경 | Critical | 전체 노드 격리 검토 |

---

## 6. 검증 및 테스트 계획

### 6-1. Phase별 테스트

| Phase | 기간 | 테스트 내용 | 합격 기준 |
|-------|------|-------------|----------|
| **Phase 1 (Test 환경)** | Week 2~3 | baseline 생성, 일일 검사, 변경 탐지 테스트 | 100% 변경 탐지, 오탐 0건 |
| **Phase 2 (Dev 환경)** | Week 5~6 | 2주 연속 운영, 성능 영향 측정 | CPU < 1%, I/O 영향 없음 |
| **Phase 3 (운영 Canary)** | Week 9~10 | 3개 노드 2주 운영 | 변경 탐지 + Alert 정상 동작 |

### 6-2. 성능 영향 측정

- **CPU**: AIDE 검사 시점에만 5~15% (1~3분)
- **I/O**: SSD 환경에서 영향 미미
- **메모리**: 50~150MB (검사 중)

---

## 7. 장애 대응 및 롤백

### 7-1. AIDE DB 손상 시

```bash
# 최신 백업에서 복구
sudo cp /var/lib/aide/aide.db.20260420.bak /var/lib/aide/aide.db
```

### 7-2. 대량 변경 발생 시 (False Positive)

1. 변경 원인 분석 (커널 업데이트? 패치?)
2. 보안팀 확인 후 베이스라인 갱신
3. `aide --update` 실행

---

## 8. 일정 (PoC 연계)

| 기간 | 작업 | 산출물 |
|------|------|--------|
| 4/27 ~ 5/3 | Test 환경 AIDE 설치 + 설정 | aide.conf, baseline DB |
| 5/4 ~ 5/10 | 1주 운영 + 변경 테스트 | 검사 보고서 7건 |
| 5/11 ~ 5/17 | Dev 환경 전파 + 2주 운영 | Phase 2 완료 보고서 |
| 5/25 ~ | 운영 Canary 적용 (본심사 통과 후) | - |

---

## 9. 부록

### A. 참고 자료

- AIDE 공식 문서: https://aide.github.io/
- CIS Ubuntu Benchmark (Level 1 Server)
- NIST SP 800-53 SI-7 (Software, Firmware, and Information Integrity)

