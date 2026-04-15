# SCPv2 CSAP 9.1.4-③ 하이퍼바이저 백신 대응 산출물 패키지

> **작성 목적**: 2026년 5월 KISA 본심사(5/18~22)에 제출할 CSAP 9.1.4 ③항(하이퍼바이저 악성코드 보호) 대응 증빙 패키지
> **대상 환경**: Samsung Cloud Platform v2 Sovereign(PG) 상암/춘천 — Ubuntu + OpenStack KVM
> **작성 책임**: CI-TEC + SCPv2 운영부서 공동
> **버전**: v0.1 (초안)

---

## 1. 산출물 구성

| # | 파일명 | 용도 | 제출 시점 |
|---|--------|------|----------|
| 00 | `00_README.md` | 패키지 안내 (본 문서) | — |
| 01 | `01_운영정책서_하이퍼바이저_백신.md` | 백신 설치·운영 공식 정책서 | 사전점검·본심사 |
| 02 | `02_보완통제_증적수집_가이드.md` | sVirt/AppArmor/FIM 증적 수집 명령어 및 캡처 방법 | 사전점검·본심사 |
| 03 | `03_악성코드_대응절차서.md` | 감염 탐지~격리~복구 절차 (CSAP 9.1.4-③ 두 번째 ∎ 충족) | 사전점검·본심사 |
| 04 | `04_글로벌CSP_비교표.md` | AWS·Azure·GCP의 동일 통제항목 처리 방식 비교 | 본심사 보충 |
| 05 | `05_공식문서_인용집.md` | OpenStack·Ubuntu·libvirt·NIST 공식 문서 인용 (한국어 요약) | 본심사 보충 |
| 06 | `06_PoC_측정계획서.md` | 실시간 스캔 ON/OFF 성능 영향 PoC 계획 및 합격기준 | 사전점검 직전 |

---

## 2. 핵심 대응 논리 요약 (1페이지 버전)

### 2-1. 우리는 무엇을 했는가
1. CSAP 9.1.4-③ 문언("백신 프로그램을 설치하여야 한다")을 충족하기 위해 **컴퓨트 노드 전체에 Linux 백신을 설치**함.
2. 단, 가상화 워크로드 안정성을 위해 **실시간 감시는 비활성화하고 예약 스캔(주1회 야간) 위주로 운영**하며, 악성코드 격리 시 자동 삭제가 아닌 알림 후 수동 격리 절차를 적용함.
3. 본질적인 하이퍼바이저 보호는 **Linux 커널의 강제접근통제(MAC) 기능인 sVirt(AppArmor) + 파일 무결성 모니터링(FIM) + 호스트 OS 최소화 + 네트워크 분리**의 보완통제 패키지로 구현함.

### 2-2. 왜 이 방식이 정당한가 (공식 근거 3종)

| 근거 | 출처 | 핵심 내용 |
|------|------|----------|
| OpenStack 공식 보안 가이드 | docs.openstack.org/security-guide | 하이퍼바이저 강화의 3대 권고사항은 ①코드베이스 최소화 ②컴파일러 하드닝 ③**MAC(sVirt/SELinux/AppArmor)**. 백신 설치는 권고 항목에 없음 |
| Ubuntu Server 공식 문서 | ubuntu.com/server/docs | "libvirt는 기본적으로 AppArmor 격리 환경에서 QEMU 게스트를 spawn한다" — SCPv2 컴퓨트 노드는 추가 솔루션 없이도 sVirt 보호 작동 중 |
| NIST SP 800-125 | NIST 공식 발행 | 가상화 호스트 보안의 핵심은 attack surface 최소화·격리·무결성. AV 추가는 surface 확대 방향 |

### 2-3. 하이퍼스케일러도 같은 방식인가
- **AWS Nitro**: 호스트 OS 자체에 "shells, filesystems, common user space utilities" 자체가 없어 AV 설치 불가능 구조 (AWS 공식 백서)
- **Microsoft Azure**: 2024년 12월 글로벌 CSP 최초 CSAP "하" 등급 인증 취득 — Hyper-V 호스트에 외부 AV 미운영
- **Google Cloud**: CSAP "하" 등급(그룹 다) 인증 (cloud.google.com/security/compliance/csap)

→ 본 통제항목은 글로벌 CSP들도 **"운영방식 + 보완통제"** 로 충족해온 항목이다.

---

## 3. 사용 방법

### 3-1. 사전점검(노브레이크, ~4/29) 대응
1. 산출물 01~03, 06을 노브레이크에 사전 공유
2. 사전점검 회의에서 본 패키지 §2-1, §2-2 논리 설명
3. 노브레이크 피드백 → v0.2 보완

### 3-2. 본심사(KISA, 5/18~22) 대응
1. 산출물 01~05 일체를 인증 신청 부속문서로 제출
2. 06번(PoC) 결과 수치를 §1-2 운영정책서에 반영(v1.0 확정)
3. 심사관 질의 시 §05 인용집의 한국어 요약 페이지를 직접 제시

### 3-3. 갱신(연 1회 사후평가) 대응
- 본 패키지를 매년 재검토 후 사후평가 시 함께 제출
- 백신 패치 이력, 예약 스캔 로그, 장애 발생 이력은 §03 절차서에 따라 별도 운영기록 유지

---

## 4. 미해결 / 후속 과제

| # | 항목 | 담당 | 기한 |
|---|------|------|------|
| 1 | 백신 솔루션 최종 결정 (V3 Net / TrendMicro DSAS / ViRobot 후보) | 보안팀 + 구매 | 4/19 |
| 2 | 노브레이크 사전점검 일정 확정 및 본 패키지 공유 | SCPv2 운영 | 4/16 |
| 3 | PoC 환경 구축 (컴퓨트 2 + 컨트롤러 1) | CI-TEC | 4/22 |
| 4 | Canonical/벤더 공식 의견서 요청 (선택사항) | CI-TEC | 본심사 전 |
| 5 | 심사관 사전 의견 청취 (가능 시) | SCPv2 운영 | 사전점검 중 |

---

## 5. 변경 이력

| 버전 | 일자 | 변경 내역 | 작성자 |
|------|------|----------|--------|
| v0.1 | 2026-04-15 | 초안 작성 | CI-TEC |

---

## 6. 부록: 본 패키지 작성에 사용된 1차 출처

1. OpenStack Security Guide — https://docs.openstack.org/security-guide/
2. Ubuntu Server Documentation: Libvirt — https://ubuntu.com/server/docs/how-to/virtualisation/libvirt/
3. libvirt.org QEMU/KVM driver — https://libvirt.org/drvqemu.html
4. Mirantis MCP Security Best Practices — https://docs.mirantis.com/mcp/q4-18/mcp-security-best-practices/openstack/compute-and-hypervisor-security.html
5. AWS Nitro System Security Whitepaper — https://docs.aws.amazon.com/whitepapers/latest/security-design-of-aws-nitro-system/
6. Google Cloud CSAP — https://cloud.google.com/security/compliance/csap?hl=ko
7. KISA CSAP 안내 — https://isms.kisa.or.kr/main/csap/intro/
8. Red Hat Enterprise Linux 7 Virtualization Security Guide — https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/7/html/virtualization_security_guide/
