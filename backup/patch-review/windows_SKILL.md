---
name: OS 패치 검토 헬퍼 (Windows Server)  
description: 정의된 임계값(threshold)에 따라 Windows Server 누적 업데이트(Cumulative Update)를 운영 시스템에 적용할지 여부를 결정하기 위한 가이드라인 세트입니다.
---

# Windows Server 패치 검토 가이드라인

본 문서는 Windows Server 누적 업데이트(MSUs)를 검토하는 OpenClaw 에이전트를 위한 엄격한 평가 기준을 제공합니다.

## 1. 목적 (Objective)
우리 시스템은 매월 Windows Server 업데이트를 자동으로 수집합니다. 이러한 업데이트는 누적 방식이므로, 수백 개의 CVE가 포함된 업데이트 전체를 평가하는 것은 매우 복잡할 수 있습니다. `windows_preprocessing.py` 스크립트는 업데이트 내용을 가장 중요한 10개의 CVE, 상위 5개의 버그 수정 및 알려진 문제(Known Issues)로 요약합니다. 귀하의 역할은 이 누적 업데이트가 즉각적인 배포가 필요한 **긴급/높음(Critical/High) 우선순위**인지, 아니면 표준 월간 주기에 따라 배포할 수 있는지를 결정하는 것입니다.

## 검토 범위 (Review Window)
전처리 스크립트는 **6개월 전부터 3개월 전 사이**에 출시된 패치를 대상으로 합니다 (예: 1분기인 3월 검토 시, 전년도 9월부터 12월까지의 패치 검토). 이 분기별 회고 기간을 통해 아직 출시되지 않았거나 너무 최신인 패치 대신, 검증된 최신 안정 버전을 평가할 수 있습니다.

## 선택 규칙 (버전당 하나)
각 Windows Server 버전(2016, 2019, 2022, 2025)에 대해 AI는 검토 범위 내의 모든 월간 누적 업데이트를 수신합니다. AI는 Critical/High 기준을 충족하는 **가장 최신의 단일** 누적 업데이트를 선택해야 합니다. 출력 결과에는 **OS 버전당 정확히 하나의 항목**만 포함되어야 합니다.

## 2. 검토 기준 (Review Criteria)

업데이트가 다음 제약 사항 중 하나라도 해결하는 경우, 정기 배포 외(out-of-band) 배포를 수행하고 우선순위를 상향 조정해야 합니다.

### 포함 기준 (긴급도: Critical)
누적 업데이트가 다음과 같은 치명적인 문제를 해결하는 경우, 반드시 강조되어야 합니다:

1.  **시스템 중단/충돌 (System Hang/Crash)**: 커널 패닉, 데드락, 부팅 실패(예: BSOD), 복구 불가능한 OS 중단.
2.  **데이터 손실/손상 (Data Loss/Corruption)**: NTFS/ReFS 파일 시스템 손상, RAID/Storage Spaces 오류, 데이터 무결성 손실.
3.  **치명적 성능 저하 (Critical Performance)**: 기업 서비스 역량에 영향을 미치는 심각한 CPU/메모리 누수 및 성능 저하.
4.  **보안 (Critical)**: CVSS 8.5 이상의 원격 코드 실행(RCE), 현재 악용 중인 권한 상승(SYSTEM/Admin 권한), 또는 심각한 인증 우회(예: Active Directory/Kerberos 결함).
5.  **장애 조치 실패 (Failover Failure)**: Windows Server 장애 조치 클러스터링(WSFC), Hyper-V 고가용성(HA) 또는 Active-Active 스토리지 가용성에 영향을 미치는 문제.

### 제외 / 등급 하향 기준
- 누적 업데이트에 **치명적인 알려진 문제(Critical Known Issue)**가 포함된 경우(예: "이 업데이트를 설치한 후 도메인 컨트롤러가 예기치 않게 재시작될 수 있음"), 이를 명시적으로 기록하고 위험을 평가해야 합니다.
- 단순한 기능 업데이트 또는 낮은 심각도(CVSS 7.0 미만)의 CVE는 긴급 패치 대상으로 간주하지 않습니다.

## 3. 입력 데이터 형식 (Input Data Format)
귀하는 전처리된 누적 업데이트가 포함된 JSON 배치를 수신하게 됩니다. `Description` 필드는 "상위 10개 주요 CVE", "알려진 문제", "상위 5개 버그 수정"을 포함하는 합성된 텍스트 블록입니다. 원본 파일을 직접 읽으려고 시도하지 마십시오.

## 4. 출력 제약 사항 (Output Constraints)
최종 응답은 반드시 **객체들로 구성된 엄격한 JSON 배열**이어야 합니다. 마크다운 기호(예: \`\`\`json)를 사용하지 마십시오. 각 객체는 다음의 ZOD 스키마와 정확히 일치해야 합니다:

```json
[
  {
    "IssueID": "String (입력값의 GROUP patch_id를 사용하십시오. 예: WINDOWS-GROUP-Windows_Server_2025)",
    "Component": "String (예: cumulative-update)",
    "Version": "String (선택된 월간 패치의 KB 번호. 예: KB5078740)",
    "Vendor": "Windows Server",
    "Date": "YYYY-MM-DD (선택된 월간 패치의 출시일)",
    "Criticality": "Critical | High | Medium | Low",
    "Description": "선택된 패치에 의해 방지된 가장 심각한 RCE, 충돌 또는 데이터 손실에만 집중하여 매우 간결하게 요약하십시오. 모든 CVE를 나열하지 마십시오. 최악의 위협이 무엇인지 설명하십시오.",
    "KoreanDescription": "기업용 전문 한국어로 번역된 설명(Description)입니다.",
    "Decision": "Done | Exclude (알려진 문제에 기반하여 환경에 심각하게 부적절하거나 시스템을 손상시키는 경우에만 Exclude를 사용하십시오)",
    "Reason": "위의 기준에 근거하여 이러한 결정을 내린 이유를 작성하십시오."
  }
]
```

### 응답 예시:
```json
[
  {
    "IssueID": "WINDOWS-GROUP-Windows_Server_2025",
    "Component": "cumulative-update",
    "Version": "KB5078740",
    "Vendor": "Windows Server",
    "Date": "2025-12-10",
    "Criticality": "Critical",
    "Description": "Addresses critical RCE in Print Spooler and Active Directory privilege escalation. No blocking known issues.",
    "KoreanDescription": "Print Spooler의 원격 코드 실행 및 Active Directory 권한 상승 취약점을 해결합니다. 현재 확인된 심각한 알려진 문제는 없습니다.",
    "Decision": "Done",
    "Reason": "Includes fixes for highly critical RCE and AD privilege escalation."
  }
]
```

**설명(Description) 작성을 위한 핵심 규칙:** `Description` 및 `KoreanDescription` 필드는 업데이트에 대한 간결한 요약 보고서여야 합니다. 원본 설명을 그대로 복사하여 붙여넣거나 긴 CVE 번호 목록을 포함하지 마십시오. 업데이트를 통해 방지되는 최악의 영향이 무엇인지, 그리고 왜 이 패치를 적용해야 하는지를 설명하십시오.

## 5. 엄격한 LLM 평가 규칙 (Strict LLM Evaluation Rules)

### 5.1 범위 제약 (Scope Constraint)
- 프롬프트에 제공된 `[BATCH DATA]` 내용만을 근거로 평가하십시오.
- 데이터를 보완하기 위해 RAG 검색, 워크스페이스 파일 또는 외부 지식을 사용하지 마십시오.
- 워크스페이스 디렉토리의 JSON 파일을 읽거나 참조하지 마십시오.

### 5.2 버전 그룹별 선택 로직
각 Windows Server 버전 그룹에 대해 `patches` 배열 내의 모든 월간 패치를 스캔하십시오:
1. 어떤 패치라도 Critical 심각도 CVE(CVSS ≥ 8.5)를 포함하는 경우 → **Decision: Done**, 가장 최신 패치 선택
2. 어떤 패치라도 RCE 또는 SYSTEM 권한 상승을 해결하는 경우 → **Decision: Done**
3. 어떤 패치라도 현재 악용 중인 것으로 알려진 취약점을 포함하는 경우 → **Decision: Done**
4. 모든 패치가 CVSS 7.0 미만의 Low/Moderate 등급이며 HA/데이터 손실 위험이 없는 경우 → **Decision: Exclude**

### 5.3 알려진 문제 처리 (Known Issues Handling)
- 선택된 패치에 **치명적인 알려진 문제**(예: 도메인 컨트롤러 재시작, 부팅 실패 등)가 있는 경우, 이를 `Reason`에 명시적으로 기록하십시오.
- 알려진 문제가 있다고 해서 자동으로 `Exclude` 하지는 마십시오. 보안 위험과 안정성 위험의 가중치를 비교하십시오.
- 알려진 문제가 제외할 만큼 심각하다면, `Reason`에 해당 내용을 명확히 기술하십시오.

### 5.4 출력 유효성 검사 (Output Validation)
| 필드 | 유효한 값 |
|-------|-------------|
| `Decision` | `Done` 또는 `Exclude`만 허용 |
| `Criticality` | `Critical`, `High`, `Medium`, `Low`만 허용 |
| `Vendor` | 반드시 `Windows Server`여야 함 |
| `IssueID` | 해당 그룹의 `patch_id`와 일치해야 함 (예: `WINDOWS-GROUP-Windows_Server_2025`) |
| `Version` | 선택된 월간 패치의 KB 번호 (예: `KB5046617`) |
