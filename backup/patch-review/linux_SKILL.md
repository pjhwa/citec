---
name: 패치 리뷰 보드 (PRB) 운영  
description: AI 에이전트가 Red Hat, Oracle Linux, Ubuntu, Windows Server에 대한 분기별 OS 패치 검토 프로세스를 수행하기 위한 지침입니다.
---

# 패치 리뷰 보드 (PRB) 운영

이 스킬은 AI 에이전트가 검증된 OS 패치 권장 보고서를 생성하는 전체 과정을 안내합니다. 패치 데이터 수집, 비중요 컴포넌트 필터링, 심층 영향 분석(LLM Check), 최종 CSV 보고서 생성 단계를 포함합니다.

## 1. 사전 준비 및 설정

작업 공간(GitHub: `https://github.com/pjhwa/patch-review-dashboard-v2`, `patch-review/os/linux/` 하위)에 다음 스크립트들이 존재해야 합니다.

**Linux OS 수집기 (벤더별, CRON 실행):**  
- `redhat/rhsa_collector.js` — Red Hat Security Advisories (CSAF API)  
- `redhat/rhba_collector.js` — Red Hat Bug Fix Advisories (Hydra API)  
- `oracle/oracle_collector.sh` + `oracle/oracle_parser.py` — Oracle Linux (yum updateinfo.xml)  
- `ubuntu/ubuntu_collector.sh` — Ubuntu (Canonical GitHub clone + jq)

**전처리:**  
- `patch_preprocessing.py` (가지치기 및 집계 — Dashboard 파이프라인에서 트리거)

> [!NOTE]  
> **오케스트레이션:** 모든 Linux 수집기는 `run_collectors_cron.sh`에 의해 호출되며 서버의 Linux CRON으로 스케줄링됩니다. 데이터 수집은 **AI 검토 파이프라인과 독립적으로** 실행되며 Dashboard에서 수동으로 트리거할 수 없습니다.

## 2. 프로세스 워크플로

### Step 1: 데이터 수집 및 수집
데이터 수집은 **Linux CRON**을 통해 완전 자동화됩니다 (매 분기 3번째 일요일 06:00 — 3월/6월/9월/12월). 각 벤더별 전용 수집 스크립트가 정규화된 advisory JSON 파일을 해당 데이터 디렉토리에 기록합니다.

| Vendor       | Collector                                                                 | Output Directory      |
|--------------|---------------------------------------------------------------------------|-----------------------|
| Red Hat      | `redhat/rhsa_collector.js` (CSAF API) + `redhat/rhba_collector.js` (Hydra API) | `redhat/redhat_data/` |
| Oracle Linux | `oracle/oracle_collector.sh` + `oracle/oracle_parser.py` (yum updateinfo.xml) | `oracle/oracle_data/` |
| Ubuntu       | `ubuntu/ubuntu_collector.sh` (Canonical GitHub + jq)                      | `ubuntu/ubuntu_data/` |

**주요 수집 동작:**  
- **Lookback period**: 수집기당 180일 (6개월)  
- **Incremental mode**: 이미 수집된 advisory ID는 자동으로 스킵  
- **Retry logic**: 실패한 요청은 백오프와 함께 재시도 후 스킵  

**수동 수집 트리거 (서버 전용):**  
```bash
cd /home/citec/.openclaw/workspace/skills/patch-review/os/linux
bash run_collectors_cron.sh
```

*목표: 전처리 단계 실행 전에 `redhat/redhat_data/`, `oracle/oracle_data/`, `ubuntu/ubuntu_data/`에 advisory JSON 파일들이 채워져 있어야 합니다.*

> [!IMPORTANT]  
> **수집은 CRON 전용입니다.** `queue.ts`나 Dashboard 파이프라인 내부에서 수집기 스크립트를 호출하지 마십시오. Dashboard 파이프라인(Step 2 이후)은 CRON에 의한 수집이 이미 완료된 것을 전제로 합니다.

### Step 2: 가지치기 및 집계 (자동화)
전처리 스크립트는 Dashboard 파이프라인(`POST /api/pipeline/run` → BullMQ → `queue.ts`)에 의해 자동으로 트리거됩니다. 모든 벤더 데이터 디렉토리를 읽고 핵심 컴포넌트 화이트리스트 필터를 적용한 후, 데이터베이스와 LLM 검토용 JSON 파일에 결과를 기록합니다.

```bash
# queue.ts (Dashboard 파이프라인)에 의해 트리거 — 기본 90일 창:
python3 patch_preprocessing.py --days 90

# 수동 실행 (서버 전용):
cd /home/citec/.openclaw/workspace/skills/patch-review/os/linux
python3 patch_preprocessing.py --days 90
# 또는: python3 patch_preprocessing.py --quarter 2026-Q1
```

**이 단계에서 수행하는 작업:**  
1. `redhat/redhat_data/`, `oracle/oracle_data/`, `ubuntu/ubuntu_data/`에서 JSON 파일 읽기  
2. 90일 날짜 필터 적용 (파이프라인 창; 수집기는 180일 창 사용)  
3. **SYSTEM_CORE_COMPONENTS 화이트리스트**에 따른 필터링 (kernel, filesystem, cluster, systemd, libvirt 등)  
4. 동일 컴포넌트에 대한 다중 업데이트를 통합 이력으로 집계  
5. `PreprocessedPatch` DB 테이블에 결과 기록 (Prisma upsert)  
6. LLM 검토용 `patches_for_llm_review.json` 생성 (Step 3)  
7. `[PREPROCESS_DONE] count=N` 로그 발생 → Dashboard 실시간 카운터 업데이트  

*목표: `patches_for_llm_review.json` 생성 및 `PreprocessedPatch` DB 테이블 채우기. 이 파일은 대상 기간 내 필터링·정리된 후보 목록을 포함합니다.*

### Step 3: 영향 분석 (실제 에이전트 검토)
**필수 작업:** `patches_for_llm_review.json` 파일을 읽으십시오. 에이전트는 각 후보의 `full_text`와 `history`를 **수동으로 분석**하여 **치명적 시스템 영향(Critical System Impact)** 기준을 충족하는지 판단해야 합니다. **이 단계에서 단순 스크립트에 의존하지 마십시오.**

**누적 권장 로직 (매우 중요):**  
동일 컴포넌트가 분기 내에 여러 업데이트를 가진 경우 (예: kernel-5, kernel-4, kernel-3, kernel-2, kernel-1):  
1. **치명 버전 식별**: 이력 중 *Critical* 수정이 포함된 버전을 판단 (예: kernel-3과 kernel-1이 Critical, 나머지는 Non-Critical)  
2. **최신 치명 버전 권장**: **Critical 수정이 포함된 가장 최신 버전**을 선택 (예: **kernel-3**). 단순히 절대 최신 버전(kernel-5)을 추천해서는 안 됩니다.  
3. **치명 설명 집계**: **Description**에는 선택된 버전(kernel-3)과 이전 치명 버전(kernel-1)의 치명 수정 내용만 병합합니다. Non-Critical 버전의 불필요한 내용은 제외합니다.

**포함 기준:**  
- **시스템 멈춤/크래시**: Kernel panic, deadlock, boot failures  
- **데이터 손실/손상**: Filesystem 오류, RAID 실패, data integrity 문제  
- **치명적 성능 저하**: 서비스 능력에 영향을 미치는 심각한 성능 저하  
- **보안 (Critical)**: RCE (Remote Code Execution), Privilege Escalation (Root), Auth Bypass  
- **Failover 실패**: High Availability (Pacemaker, Corosync)에 영향을 미치는 문제  

**제외 기준:**  
- 사소한 버그 수정 (typos, logging noise)  
- 안정성에 영향을 주지 않는 에지 케이스  
- "Moderate" 보안 문제 (local DoS, info leak) — 광범위한 영향이 없는 경우  
- **지원 기간 제외 (Ubuntu)**:  
    - **비LTS 버전만** 영향을 미치는 패치는 **포함하지 않습니다** (예: Ubuntu 25.10, 24.10).  
    - **LTS 버전(24.04, 22.04, 20.04)** 을 최우선으로 합니다.  
    - *예시:* "USN-7906-1이 Ubuntu 25.10에만 영향을 줌 → **제외**."  
- **특정 버전 조회**:  
    - **중요:** `patches_for_llm_review.json` 입력 데이터에 명시된 `specific_version` (또는 `patch_name_suggestion`) 값을 반드시 사용하세요!  
    - `specific_version`에 유효한 문자열이 있으면 "Unknown"을 출력하지 마십시오.

### Step 4: 최종 보고서 생성
모든 후보에 대한 최종 검토 결정을 **반드시** `patch_review_ai_report.json`이라는 JSON 데이터 파일로 출력하세요.  
마크다운 코드 블록으로 감싸지 말고, 순수 JSON 배열로만 출력하십시오.

**형식:**
```json
[
  {
    "id": "USN-7851-2",
    "vendor": "Ubuntu",
    "OsVersion": "22.04 LTS, 24.04 LTS",
    "distVersion": "22.04 LTS",
    "component": "runc",
    "version": "1.3.3-0ubuntu1~24.04.3",
    "date": "2026-02-14",
    "criticality": "Critical",
    "description": "Resolves container escape vulnerabilities.",
    "koreanDescription": "컨테이너 탈취 취약점 해결.",
    "decision": "Approve",
    "reason": "High risk of host compromise.",
    "reference": "https://ubuntu.com/security/notices/USN-7851-2"
  }
]
```

**내용 가이드라인 (매우 중요):**  
- **OsVersion**: JSON의 `os_version` 필드에 있는 특정 OS 버전으로 **반드시** 채워야 합니다. 여러 배포판을 커버하는 경우 소스 필드에 결합된 형태를 그대로 유지 (예: `"22.04 LTS, 24.04 LTS"` 또는 `"RHEL 8, RHEL 9"`). **단일 패치에 대해 여러 행을 생성하지 마십시오.**  
- **Dist Version**: JSON의 `dist_version` 필드에 있는 기본 OS 버전으로 **반드시** 채워야 합니다.  
- **Ubuntu Variant-Specific USNs**: 일부 USN은 특정 커널 변형(FIPS, GCP, NVIDIA, Tegra)만 커버합니다. `full_text`의 Releases 섹션을 확인하세요.  
- **Reference**: 소스 JSON의 `ref_url` (또는 `url`) 필드로 **반드시** 채워야 합니다.  
- **Version**: **중요 지침** — 소스 JSON의 `specific_version` 필드(또는 `patch_name_suggestion`)에 제공된 **정확한 값**을 반드시 사용하세요! `full_text`나 `diff_content`에서 임의 추출하거나 “Unknown”, placeholder 문자열을 사용하지 마십시오.  
- **한글 설명 (Korean Description)**:  
    - “Security update for kernel” 같은 일반적 표현이나 CVE 목록만 나열하지 마십시오.  
    - boilerplate 텍스트, URL, 업데이트 지침, raw .patch/.rpm 목록, changelog 스니펫을 포함하지 마십시오.  
    - **반드시** 1~2문장으로 압축된 요약이어야 하며, 실제로 어떤 기능이 깨졌고 시스템에 어떤 영향을 미치는지 설명하세요.  
    - 키워드: “System Hang”, “Memory Leak”, “Race Condition”, “Use-After-Free”, “Data Corruption”, “Panic”.  
    - *나쁜 예시 1:* “커널 보안 업데이트. 다음 문제를 해결함: See the following advisory...”  
    - *나쁜 예시 2:* “[9.1.0-29] - kvm-target-i386...patch”  
    - *좋은 예시:* “메모리 부족 상황에서 데이터 손실을 유발할 수 있는 zswap 경쟁 상태 해결 및 `nilfs_mdt_destroy`의 일반 보호 오류(GPF)로 인한 시스템 크래시 방지.”  
- **Patch Description (English)**: Korean Description을 바탕으로 1~2문장 영어 요약. raw diff_summary나 changelog 복사 금지. 누적 업데이트인 경우 “(누적 패치 포함: 3건)” 등을 반영하세요.

## 3. 실행 예시

**사용자 요청:** "Run the PRB for Q1 2026."

**에이전트 동작:**  
1. CRON이 `run_collectors_cron.sh`를 실행했는지 확인 (`ls -lh redhat/redhat_data/` 등). 필요 시 수동 실행.  
2. Dashboard 파이프라인 또는 수동으로 `python3 patch_preprocessing.py --quarter 2026-Q1` 실행.  
3. `patches_for_llm_review.json` 읽기.  
4. 생각 과정: “Candidate: kernel-uek... Impacts: Data Loss. → **포함**.” / “Candidate: python-libs... Minor fix. → **제외**.”  
5. `patch_review_ai_report.json` 생성.  
6. 사용자에게 “Report generated at [path].” 알림.

## 4. 엄격한 LLM 평가 규칙

### 4.1 포함 기준
패치가 다음 중 하나 이상을 충족할 때만 포함:  
- System Hang/Crash, Data Loss/Corruption, Critical Performance, Security (Critical), Failover Failure, Hardware Compatibility 등.

### 4.2 제외 기준
- 사소한 버그 수정, Moderate 보안 문제, Ubuntu non-LTS 전용, 이미 최신 Critical 패치로 대체된 경우 등.

### 4.3 출력 형식 (JSON Schema)
순수 JSON 배열로만 반환. 각 객체는 다음 필드를 정확히 포함:  
```json
{
  "IssueID": "...",
  "Component": "...",
  "Version": "specific_version 필드 정확 값",
  "Vendor": "Red Hat | Oracle | Ubuntu",
  "Date": "YYYY-MM-DD",
  "Criticality": "Critical | High | Moderate | Low",
  "Description": "1-2문장 영어 요약",
  "KoreanDescription": "1-2문장 한국어 요약",
  "Decision": "Approve | Exclude",
  "Reason": "간단한 근거"
}
```

### 4.4 일반 규칙
- 입력 배치와 정확히 같은 수의 객체 반환  
- Version은 반드시 `specific_version` 값 사용  
- OsVersion은 소스 `os_version` 그대로  
- raw .patch, CVE 목록, changelog 복사 금지

### 4.5 Hallucination 방지 규칙
- 존재하지 않는 CVE 발명 금지  
- 버전 추측 금지  
- “See the following advisory” 같은 표현 금지  
- generic 설명(“Security update for kernel”) 금지

## 5. 출력 검증 규칙
제출 전 반드시 확인: 배열 길이 일치, 모든 필드 존재, Version이 “Unknown”이 아님, Vendor 정확 표기, 설명이 1~2문장 등.

## 6. 벤더별 규칙

### 6.1 Red Hat (RHSA-*/RHBA-*)
- 데이터 위치: `redhat/redhat_data/`  
- Vendor 값: `"Red Hat"`  
- Version 예시: `"kernel-5.14.0-503.26.2.el9_5"`  
- RHBA는 cosmetic 변경만 제외

### 6.2 Oracle Linux (ELSA-*)
- 데이터 위치: `oracle/oracle_data/`  
- Vendor 값: `"Oracle"`  
- UEK와 RHCK 모두 유효

### 6.3 Ubuntu (USN-*)
- 데이터 위치: `ubuntu/ubuntu_data/`  
- Vendor 값: `"Ubuntu"`  
- **LTS ONLY** (24.04, 22.04, 20.04)  
- Variant USN(FIPS, GCP 등)은 서버 환경 관련 시 포함  
- Version: `specific_version` 또는 `packages` 배열의 LTS 버전 사용
