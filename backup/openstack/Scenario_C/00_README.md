# SCPv2 CSAP 9.1.4-③ 하이퍼바이저 백신 대응 산출물 패키지 v2.0

> **작성 목적**: 2026년 5월 KISA 본심사(5/18~22)에 제출할 CSAP 9.1.4 ③항(하이퍼바이저 악성코드 보호) 대응 증빙 패키지
> **대상 환경**: Samsung Cloud Platform v2 Sovereign(PG) 상암/춘천 — Ubuntu + OpenStack KVM (Helm)
> **작성 책임**: CI-TEC + SCPv2 운영부서 공동
> **버전**: **v2.0** (운영부서 협의 후 "미설치 + MAC" 방향 확정)

---

## 0. v2.0 핵심 변경 사항

| 구분 | v1.0 (2026-04-15) | **v2.0 (2026-04-20)** |
| --- | --- | --- |
| 대응 방식 | 백신 설치 + 실시간 스캔 OFF | **백신 미설치 + MAC 통제** |
| 논리 구조 | 문언 준수 + 운영 최적화 | **"통제 목적 동등 달성" 정공법** |
| 일정 | 즉시 설치 후 운영 | **3개월 내 MAC 검증·전사 적용** |
| 운영 리스크 | I/O·마이그레이션 잔존 | 낮음 |
| 인증 리스크 | 낮음 | 중간 (심사관 설득 필요) |

---

## 1. 산출물 구성

| # | 파일명 | 용도 | 제출 시점 |
| --- | --- | --- | --- |
| — | `하이퍼바이저백신요건대응논리.md` | 전체 대응 논리 마스터 문서 | 내부 전략 기준 |
| 00 | `00_README.md` | 패키지 안내 (본 문서) | — |
| 01 | `01_운영정책서_하이퍼바이저_백신.md` | 백신 **미설치** + MAC 통제 공식 정책서 | 사전점검·본심사 |
| 02 | `02_보완통제_증적수집_가이드.md` | sVirt/AppArmor/FIM 증적 수집 명령 | 사전점검·본심사 |
| 03 | `03_악성코드_대응절차서.md` | 탐지~격리~복구 절차 (9.1.4-③ 두 번째 ∎ 충족) | 사전점검·본심사 |
| 04 | `04_글로벌CSP_비교표.md` | AWS·Azure·GCP + 국내 CSP(NHN/KT/Naver) 비교 | 본심사 보충 |
| 05 | `05_공식문서_인용집.md` | OpenStack·Ubuntu·libvirt·NIST 공식 인용 | 본심사 보충 |
| 06 | `06_PoC_측정계획서.md` | 3개월 MAC 검증·적용 로드맵 + 측정 계획 | 사전점검·본심사 |
| 부록 | `OpenStack-MAC-적용가이드.md` | 기술 상세 가이드 (내부 Engineering 참조용) | 내부 기술 기준 |

---

## 2. 대응 논리 1페이지 요약

### 2-1. 결론

**SCPv2는 하이퍼바이저에 전통적 백신(AV)을 설치하지 않는다. 대신 KVM/libvirt의 강제접근통제(MAC) — sVirt(AppArmor) + 파일 무결성 모니터링(FIM) + 호스트 OS 최소화 + 관리망 분리 — 의 4종 보완통제 패키지로 통제 목적을 달성하며, 3개월 내 전사 검증·적용을 완료한다.**

### 2-2. 4가지 주장 (Line of Defense)

| # | 주장 | 요지 |
| --- | --- | --- |
| 1 | **기술적 부적합성** | AV 설치는 qemu-kvm 안정성을 훼손해 통제 목적과 정반대 결과를 초래 |
| 2 | **보완통제의 동등성** | MAC은 커널 레벨에서 프로세스 단위 격리 → AV보다 구조적으로 강력 |
| 3 | **공식 문서 부합** | OpenStack·Ubuntu·libvirt·NIST 모두 **MAC을 우선 권고, AV는 권고 항목 아님** |
| 4 | **업계 관행** | AWS/Azure/GCP 전 세계 CSP가 전통 AV 미사용 — MAC이 de facto 표준 |

### 2-3. 공식 근거 3종

| 근거 | 핵심 내용 | 출처 |
| --- | --- | --- |
| OpenStack Security Guide | 하이퍼바이저 3대 권고 = ①코드최소화 ②컴파일러하드닝 ③**MAC**. AV 없음 | docs.openstack.org/security-guide |
| Ubuntu Server 공식 문서 | libvirt는 기본적으로 AppArmor 격리로 QEMU 게스트 spawn | ubuntu.com/server/docs |
| NIST SP 800-125 | 가상화 호스트 보안 = attack surface 최소화 + 격리 + 무결성 | csrc.nist.gov |

### 2-4. 글로벌·국내 CSP 사례

- **글로벌**: AWS Nitro / Azure Hyper-V / GCP — 호스트 AV 전원 미운용 (공식 백서 입증)
- **국내**: NHN Cloud(OpenStack 공식), KT Cloud, 네이버클라우드 모두 CSAP 취득. AV 설치 여부는 공개 자료에 미등재 (추정: MAC 기반)
- **삼성SDS**: SCPv1 (VMware)에서 백신 미설치로 CSAP 통과한 선례 보유

---

## 3. 사용 방법

### 3-1. 사전점검(노브레이크, ~4/29) 대응 프로세스

1. 산출물 01~03, 06을 노브레이크에 **사전 공유**
2. 사전점검 회의에서 본 패키지 §2-2 (4가지 주장) 순서대로 설명
3. PoC Phase 1 완료 증적 제시 (sVirt/AppArmor `aa-status` 캡처, VM별 프로파일 생성 증거)
4. 노브레이크 피드백 → v2.1 보완

### 3-2. 본심사(KISA, 5/18~22) 대응 프로세스

1. 산출물 01~06 일체를 인증 신청 부속문서로 제출
2. 심사관 질의 시 §05 인용집의 한국어 요약 페이지를 직접 제시
3. PoC Phase 2 완료 증적 + Phase 3 Canary 운영 증적 제시
4. 예상 반박에 대한 응답 시나리오는 `하이퍼바이저백신요건대응논리.md` §7-3 참조

### 3-3. 갱신·사후평가(연 1회) 대응

- PoC Phase 3 완료 후 전 운영 환경 enforce 모드 증적 제시
- AppArmor 프로파일 버전 관리 이력 (Git)
- 연간 FIM 위반 탐지 이력 + 대응 결과

---

## 4. 핵심 실행 체크리스트

### 4-1. 사전점검 전까지 (D-10일)

- [ ] PoC **Phase 1 (Test 환경)** 완료
- [ ] Test 환경 aa-status, 기능/성능/보안 검증 증적 확보

### 4-2. 본심사 전까지 (D-30일)

- [ ] Phase 1 완료 보고서 작성
- [ ] 본심사 제출 자료: Phase 1 증적 + Phase 2 ~ 3 계획서

### 4-3. 본심사 당일

- [ ] "Test 환경 검증 완료 + 통과 후 Dev 환경 즉시 적용" 전략 발표
- [ ] 실시간 시연 가능 환경 **준비** (aa-status, QEMU 프로세스 레이블 확인)
- [ ] 예상 질의 응답 시나리오 **숙지**

---

## 5. 후속 과제 및 미해결 사항

| # | 항목 | 담당 | 기한 |
| --- | --- | --- | --- |
| 1 | 사전점검 노브레이크 사전 의견 확보 | SCPv2 운영 | 4/22 |
| 2 | 피어 CSP 비공식 confirm 시도 | CI-TEC | 본심사 전 |
| 3 | PoC Phase 1 증적 패키지 완성 | CI-TEC | 4/25 |
| 4 | PoC Phase 2 개시 (Dev 환경) | CI-TEC + 운영 | 5/1 |
| 5 | Canary 노드 운영 환경 적용 | SCPv2 운영 | 5/10 |
| 6 | 경영진·법무 최종 검토 | 보안팀 | 5/12 |
| 7 | KISA 사전 의견 청취 (가능 시) | SCPv2 운영 | 사전점검 중 |

---

## 6. 리스크 관리

### 6-1. Top 3 Risks

| # | 리스크 | 발생 가능성 | 영향 | 완화 방안 |
| --- | --- | --- | --- | --- |
| 1 | 심사관이 문언 해석으로 결함 판정 | 중 | 높음 | 사전점검 단계 집중 설득, 4가지 주장 동시 제시 |
| 2 | 경쟁 CSP가 AV를 설치하고 있어 대비될 경우 | 낮음~중 | 높음 | 피어 네트워크 비공식 confirm, MAC의 우월성 시연 |
| 3 | PoC 일정 지연으로 증적 부족 | 중 | 중 | 운영부서 자원 사전 배정, Phase 1만이라도 확보 |

### 6-2. Fallback 시나리오

심사관이 수용 불가 통보 시:
1. **Plan B**: 즉시 v1.0 논리(설치 + 실시간 스캔 OFF)로 전환 → 결함 수정 기간(30일) 활용
2. **Plan C**: 조건부 통과(조치 요구사항 포함)로 본심사 통과 후 사후평가 단계에서 MAC 완전 전환

---

## 7. 변경 이력

| 버전 | 일자 | 변경 내역 | 작성자 |
| --- | --- | --- | --- |
| v0.1 | 2026-04-15 | 초안 (시나리오 C: 설치 + 보완통제) | CI-TEC |
| **v2.0** | **2026-04-20** | **시나리오 A+ 전환: 미설치 + MAC + 3개월 로드맵** | **CI-TEC + SCPv2 운영** |

---

## 8. 부록: 본 패키지 작성에 사용된 1차 출처

1. OpenStack Security Guide — <https://docs.openstack.org/security-guide/>
2. Ubuntu Server Documentation: Libvirt — <https://ubuntu.com/server/docs/how-to/virtualisation/libvirt/>
3. libvirt.org QEMU/KVM driver — <https://libvirt.org/drvqemu.html>
4. Mirantis MCP Security Best Practices — <https://docs.mirantis.com/mcp/q4-18/mcp-security-best-practices/openstack/compute-and-hypervisor-security.html>
5. AWS Nitro System Security Whitepaper — <https://docs.aws.amazon.com/whitepapers/latest/security-design-of-aws-nitro-system/>
6. Google Cloud CSAP — <https://cloud.google.com/security/compliance/csap?hl=ko>
7. KISA CSAP 안내 — <https://isms.kisa.or.kr/main/csap/intro/>
8. NIST SP 800-125 — <https://csrc.nist.gov/pubs/sp/800/125/final>
9. Red Hat Enterprise Linux Virtualization Security Guide — <https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/7/html/virtualization_security_guide/>
