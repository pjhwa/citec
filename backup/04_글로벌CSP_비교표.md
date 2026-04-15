# 글로벌 클라우드 사업자 하이퍼바이저 보안 접근법 비교

| 항목 | 내용 |
|------|------|
| 문서번호 | SCPv2-SEC-CMP-2026-004 |
| 버전 | v0.1 |
| 작성일 | 2026-04-15 |
| 용도 | CSAP 9.1.4-③ 대응 시 글로벌 CSP의 동일 통제항목 처리 사례 비교 근거 |

---

## 0. 본 비교표의 사용 목적

CSAP 본심사 시 심사관이 "왜 SCPv2는 호스트에 실시간 백신을 운영하지 않느냐"고 질의하는 경우, **글로벌 CSP들도 동일한 사유로 호스트 백신을 운영하지 않으며, 그럼에도 동등 또는 더 엄격한 인증을 통과하고 있다**는 사실을 입증하는 비교 자료.

---

## 1. 종합 비교표

| 항목 | AWS (Nitro) | Microsoft Azure | Google Cloud (GCP) | Samsung Cloud Platform v1 (구) | **SCPv2 (본 대응)** |
|------|:---:|:---:|:---:|:---:|:---:|
| **하이퍼바이저 기반** | KVM 기반 자체 경량화 (Nitro Hypervisor) | Hyper-V | KVM 기반 자체 (gVisor 등 보조) | VMware ESXi (Appliance OS) | **Ubuntu + OpenStack KVM** |
| **호스트 OS 형태** | shell·파일시스템·네트워크 스택 없는 firmware-like | Hyper-V Server (최소화) | Borg/proprietary minimal Linux | ESXi Appliance (벤더 폐쇄형) | Ubuntu LTS (범용 Linux) |
| **호스트 백신 설치 가능성** | **물리적으로 불가능** (shell 없음) | 미운영 (정책) | 미운영 (정책) | 벤더 미지원 (브로드컴 공식 회신) | **가능** (Linux 패키지 설치 가능) |
| **하이퍼바이저 보호 주 메커니즘** | Nitro Security Chip + 최소 hypervisor + 격리 | Hyper-V isolation, VBS | sVirt 유사 + custom isolation | ESXi 폐쇄형 보안 | **AppArmor sVirt + FIM + 백신(예약스캔)** |
| **CSAP 인증 현황** | (미인증, 신청 검토 보도) | **CSAP 하 등급 인증 (2024.12)** | **CSAP 하 등급(그룹 다) 인증** | CSAP 인증 보유 | **본심사 진행 중 (2026.05)** |
| **CSAP 9.1.4-③ 대응 방식** | (해당사항 없음 — 호스트 OS 자체가 없음) | 보완통제 (Hyper-V 격리, MAC 등) | 보완통제 (sandbox, 격리) | 벤더 미지원 사유서 제출 | **백신 설치 + 운영방식 최적화 + 보완통제** |

---

## 2. AWS Nitro System 상세

### 2.1 핵심 사실
> "Within the Nitro Hypervisor, there is, by design, **no networking stack, no general-purpose file system implementations, and no peripheral device driver support**. The Nitro Hypervisor has been designed to include only those services and features which are strictly necessary for its task; **it is not a general-purpose system and includes neither a shell** nor any type of i[nteractive access]."
>
> — AWS Whitepaper "The Security Design of the AWS Nitro System"
> 출처: https://docs.aws.amazon.com/whitepapers/latest/security-design-of-aws-nitro-system/the-components-of-the-nitro-system.html

> "no shells, filesystems, common user space utilities, or access to resources that could facilitate lateral [movement]"
>
> — 동일 출처

### 2.2 의미
- **AWS는 호스트에 백신을 설치할 수 없는 구조를 의도적으로 설계함.** Shell, 파일시스템, 일반 OS 유틸리티 자체가 없으므로 V3·Trellix 같은 백신은 동작 불가.
- 즉, AWS의 보안 모델은 **"AV로 사후 탐지" → "구조적으로 불필요"** 로 이동한 것.
- Nitro는 **KVM 기반**(Linux KVM의 minimized fork)으로 SCPv2 KVM과 같은 가상화 코어 기술 위에 보안 모델만 다르게 구현.

### 2.3 SCPv2 적용 가능성
SCPv2는 범용 Ubuntu를 호스트로 사용하므로 AWS와 같은 "구조적 보안" 접근은 단기간 불가능. 그러나 **동일한 철학(MAC 우선, 백신은 보완수단)** 은 적용 가능.

---

## 3. Microsoft Azure 상세

### 3.1 핵심 사실
- Azure는 Hyper-V 기반 하이퍼바이저로 운영
- 2024년 12월 글로벌 CSP 최초로 한국 CSAP "하" 등급 인증 취득
  > 출처: https://iting.co.kr/insight-tech-csap-20250117/

### 3.2 인증 통과 의미
- Azure가 호스트 Hyper-V에 실시간 백신을 운영하지 않음에도 CSAP 9.1.4-③을 통과했다는 사실은, **본 통제항목이 보완통제로 충족 가능**함을 KISA가 인정한 선례.
- 다만 Hyper-V는 Microsoft 자체 OS로 외부 백신 설치가 정책적으로 제한됨 → "벤더 미지원" 논리가 적용된 것으로 추정 (SCPv1과 유사한 패턴).

---

## 4. Google Cloud Platform 상세

### 4.1 핵심 사실
> "Google Cloud는 IaaS 및 PaaS 제품에 대해 CSAP '하 등급'(그룹 '다')을 획득했습니다. 이 인증의 범위에는 대한민국 Seoul Region에 위치한 Google Cloud 리소스가 포함됩니다."
>
> 출처: https://cloud.google.com/security/compliance/csap?hl=ko

### 4.2 인증 통과 의미
- Google Cloud의 호스트 인프라는 자체 개발한 Borg 기반 minimal Linux + KVM
- 외부 백신을 운영하지 않음에도 CSAP 인증 통과
- Azure와 동일하게 보완통제 + 자체 보안 통제로 충족한 사례

---

## 5. Samsung Cloud Platform v1 (구) 사례

### 5.1 v1의 처리 방식
- v1은 VMware ESXi 기반 (Appliance OS)
- 브로드컴(VMware 인수)으로부터 다음 공식 입장 확보:
  1. 호스트 백신 설치 미지원
  2. 설치 시 성능 저하 발생
  3. 유지보수/기술지원 제약
- 위 공식 회신을 CSAP 인증 시 증빙으로 제출하여 통제항목 면제

### 5.2 v2와의 차이
- **v1**: 벤더 정책상 불가능 → "외부 변수에 의한 면제"
- **v2**: Ubuntu 범용 OS → 기술적으로 설치 가능 → **"외부 변수 면제 논리는 성립 불가"**
- v2는 "설치는 하되 운영방식 최적화 + 보완통제"로 정공법 대응 필요

---

## 6. 통제항목별 매트릭스

CSAP 9.1.4-③의 두 가지 요건에 대한 각 CSP의 충족 방식:

### 6.1 첫 번째 ∎ — "백신 프로그램을 설치하여야 하며, 최신 버전 유지"

| CSP | 설치 여부 | 충족 논리 |
|-----|:--------:|----------|
| AWS Nitro | 미설치 | 호스트 OS 자체가 없어 적용 불가능. Nitro Security Chip이 동등 또는 우수한 통제 제공 |
| Azure | 미설치(추정) | 벤더 정책 / 보완통제 |
| GCP | 미설치 | 자체 보안 모델 / 보완통제 |
| SCPv1 | 미설치 | VMware 벤더 미지원 (공식 회신 증빙) |
| **SCPv2** | **설치** | **Linux 백신 설치 + 패턴 일자동 업데이트로 문언 직접 충족** |

### 6.2 두 번째 ∎ — "감염 시 대응방안(격리 등) 수립"

| CSP | 대응 방식 |
|-----|----------|
| AWS Nitro | 침해 시 인스턴스 격리, Nitro 라이브 업데이트로 무중단 패치 |
| Azure | Hyper-V 격리, 자동 마이그레이션 |
| GCP | Live Migration, sandbox 격리 |
| SCPv1 | VMware vMotion + 절차서 |
| **SCPv2** | **OpenStack live migration + 격리 절차서 (03_악성코드_대응절차서.md) 보유** |

---

## 7. 핵심 결론 (심사관 설명용)

### 7.1 한 줄 요약
> "SCPv2는 글로벌 CSP들이 공통으로 채택하는 **'백신은 보완수단, MAC이 본질적 통제'** 라는 보안 철학을 따르되, CSAP 통제항목 문언 충족을 위해 백신을 추가 설치하여 **이중 방어(defense-in-depth)** 를 구성한다."

### 7.2 차별점
| 비교 | 글로벌 CSP | SCPv2 (본 대응) |
|------|----------|----------------|
| MAC 보호 | ○ | ○ |
| 호스트 백신 | × | **○ (예약 스캔 위주)** |
| 격리 절차서 | ○ | ○ |

→ SCPv2는 글로벌 CSP보다 **한 가지 통제(백신)를 추가** 한 셈. CSAP 문언 충족도 + 보안 깊이 모두 우위.

---

## 8. 출처 일괄 정리

| 사항 | 출처 |
|------|------|
| AWS Nitro Hypervisor 구조 (shell 없음) | https://docs.aws.amazon.com/whitepapers/latest/security-design-of-aws-nitro-system/the-components-of-the-nitro-system.html |
| AWS Nitro 보안 백서 전문 | https://docs.aws.amazon.com/whitepapers/latest/security-design-of-aws-nitro-system/security-design-of-aws-nitro-system.html |
| AWS Nitro KVM 기반 사실 | https://docs.aws.amazon.com/whitepapers/latest/security-design-of-aws-nitro-system/the-nitro-system-journey.html |
| Azure CSAP 하 등급 취득 (2024.12) | https://iting.co.kr/insight-tech-csap-20250117/ |
| Google Cloud CSAP 하 등급(그룹 다) | https://cloud.google.com/security/compliance/csap?hl=ko |
| KISA CSAP 제도 안내 | https://isms.kisa.or.kr/main/csap/intro/ |

---

## 9. 변경 이력

| 버전 | 일자 | 변경 내역 | 작성자 |
|------|------|----------|--------|
| v0.1 | 2026-04-15 | 최초 작성 | CI-TEC |
