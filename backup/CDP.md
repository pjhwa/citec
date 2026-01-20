CI-TEC의 핵심 기술 자산인 **4,000여 개의 PISA 진단 항목**과 **Lookin/ProbeONE**과 같은 자체 도구는 단순한 운영 도구가 아니라, 엔지니어를 '대체 불가능한 전문가'로 만드는 강력한 무기입니다.

이를 바탕으로 각 분야별 직무 정의와 3단계 성장 로드맵(CDP)을 보다 심층적으로 설계했습니다.

---

## [CI-TEC 분야별 상세 JD 및 CDP 로드맵]

### 1. OS: Kernel & System Performance Specialist

* **직무 정의**: 대규모 서버 인프라의 커널 파라미터 최적화, 저지연(Low-latency) 워크로드 분석 및 하드웨어 가용성 극대화.
* **Elevator Pitch**: "단순한 패치 설치자가 아닙니다. 수만 대의 서버에서 발생하는 커널 패닉의 근본 원인(RCA)을 **ProbeONE**으로 실시간 추적하고, 시스템 성능을 1% 더 쥐어짜는 **'OS 아키텍트'**가 됩니다. CI-TEC에서의 경험은 리눅스 커널의 내부 동작 원리를 현장에서 체득하는 최고의 과정이 될 것입니다."

| 단계 | 명칭 | 핵심 역량 및 역할 | 활용 도구/Stack |
| --- | --- | --- | --- |
| **L1** | **Sys-Admin** | 표준 SOP 기반 OS 빌드 및 취약점 진단, PISA 항목별 기본 점검 수행 | RHEL/Ubuntu, PISA Standard |
| **L2** | **Perf-Tuner** | 시스템 병목 현상 분석, Lookin 데이터를 활용한 커널 튜닝 및 리소스 최적화 | Systemtap, eBPF, Lookin |
| **L3** | **Kernel Architect** | 대규모 장애 근본 원인 분석(RCA), 하드웨어 아키텍처별 맞춤형 OS 최적화 전략 수립 | Kernel Source, NUMA Topology |

---

### 2. DB: Heterogeneous Data Platform Architect

* **직무 정의**: Oracle, HANA, OpenSource DB 등 이기종 DB 환경의 성능 진단, 마이그레이션 아키텍처 설계 및 자동화 진단 로직 개발.
* **Elevator Pitch**: "국내에서 가장 복잡한 데이터 흐름을 다룹니다. DB 성능 병목을 수동으로 잡는 시대는 끝났습니다. **PISA의 진단 알고리즘**을 DB 자동 분석 엔진으로 승화시키는 **'데이터 플랫폼 설계자'**로 거듭나십시오. 3년 뒤 당신은 어떤 DB 환경에서도 최적의 경로를 찾아내는 전문가가 되어 있을 것입니다."

| 단계 | 명칭 | 핵심 역량 및 역할 | 활용 도구/Stack |
| --- | --- | --- | --- |
| **L1** | **DB Admin** | 인스턴스 관리, 백업/복구 수행, PISA 기반 정기 점검 | Oracle, MySQL, PISA DB |
| **L2** | **Migration Expert** | 이기종 간 데이터 전환(Oracle to Hana 등) 및 쿼리 튜닝 전문가 | SQL Profiler, Lookin DB Agent |
| **L3** | **Data Architect** | 전사 데이터 거버넌스 수립, 자가 치유(Self-Healing) DB 진단 로직 설계 | NoSQL, Distributed DB Design |

---

### 3. Middleware: Cloud-Native SRE Specialist

* **직무 정의**: 웹/애플리케이션 서버(WAS)와 컨테이너 환경의 트랜잭션 추적, 가용성 보장 및 대규모 트래픽 분산 제어.
* **Elevator Pitch**: "Tuxedo 같은 레거시부터 Kubernetes 기반의 마이크로서비스까지, 서비스의 중단을 불허하는 **'신뢰성 공학자(SRE)'**의 길입니다. CI-TEC의 **Lookin MW 모듈**을 통해 수천 개의 인스턴스에서 흐르는 트래픽의 결을 읽고, 장애를 사전에 차단하는 지능형 인프라의 핵심 인재가 됩니다."

| 단계 | 명칭 | 핵심 역량 및 역할 | 활용 도구/Stack |
| --- | --- | --- | --- |
| **L1** | **MW Admin** | WAS/Web Server 설정 및 기본 가용성 모니터링 수행 | Tuxedo, JBoss, WebLogic |
| **L2** | **Tuning Expert** | 대규모 트랜잭션 병목 분석, Java/C 애플리케이션 프로파일링 및 최적화 | Thread Dump, Lookin APM |
| **L3** | **SRE Strategist** | Cloud-Native 환경의 무중단 배포 아키텍처 및 자동 복구 시스템 설계 | Kubernetes, Istio, Helm |

---

### 4. Network: SDN & Traffic Intelligence Engineer

* **직무 정의**: 복잡한 엔터프라이즈 망의 트래픽 흐름 가시성 확보, 소프트웨어 정의 네트워킹(SDN) 아키텍처 설계 및 보안 정책 최적화.
* **Elevator Pitch**: "장비 연결을 넘어 '데이터의 흐름'을 지휘합니다. CI-TEC에서는 수 페타바이트급 트래픽을 **ProbeONE NW**로 실시간 분석하여 보이지 않는 위협과 병목을 찾아냅니다. 네트워크를 코드로 제어하는 **'SDN 전문가'**로서의 커리어는 오직 이곳에서만 완성될 수 있습니다."

| 단계 | 명칭 | 핵심 역량 및 역할 | 활용 도구/Stack |
| --- | --- | --- | --- |
| **L1** | **NW Admin** | L2/L3 스위칭 운영, 방화벽 정책 설정 및 물리적 구성 관리 | Cisco/Arista, PISA NW |
| **L2** | **Traffic Engineer** | 패킷 분석 기반 장애 원인 규명, SDN 제어 로직 설계 및 보안 위협 분석 | Wireshark, ProbeONE NW |
| **L3** | **Network Strategist** | 하이브리드 클라우드 연동망 설계 및 지능형 트래픽 라우팅 자동화 구현 | SD-WAN, Spine-Leaf Arch |

---

### 5. Storage: Data Integrity & Next-Gen Storage Architect

* **직무 정의**: 대규모 데이터 저장소의 고가용성 설계, 소프트웨어 정의 스토리지(SDS) 전환 및 데이터 생명주기 관리(ILM).
* **Elevator Pitch**: "회사의 가장 소중한 자산인 '데이터'의 최후 보루입니다. Legacy SAN에서 Ceph와 같은 분산 스토리지로의 대전환을 주도하십시오. CI-TEC의 **PISA 스토리지 진단 항목**을 통해 수만 개의 디스크 상태를 예측하고 관리하는 **'데이터 스토리지 아키텍트'**는 업계 최고의 대우를 받는 커리어입니다."

| 단계 | 명칭 | 핵심 역량 및 역할 | 활용 도구/Stack |
| --- | --- | --- | --- |
| **L1** | **Storage Ops** | 볼륨 할당, 백업/소거 관리, 스토리지 가용량 리포팅 수행 | NetApp, EMC, PISA STG |
| **L2** | **SDS Engineer** | OpenStack 기반 Ceph/Swift 구축 및 운영, I/O 성능 최적화 전문가 | Ceph, NVMe, Lookin STG |
| **L3** | **Storage Architect** | 전사 데이터 보호 전략 수립, AI 워크로드용 고성능 스토리지 팜 설계 | Distributed File System |

---

### 6. Cloud: OpenStack & Hybrid Cloud Orchestrator

* **직무 정의**: OpenStack 기반 자체 클라우드(SCP) 고도화, 하이브리드 클라우드 운영 거버넌스 수립 및 IaC 기반 인프라 자동화.
* **Elevator Pitch**: "단순히 클라우드를 사용하는 사용자가 아니라, **'클라우드를 만드는 빌더(Builder)'**가 됩니다. OpenStack과 Kubernetes가 결합된 복합 아키텍처를 진단하고 운영하는 경험은 국내 어디에서도 얻을 수 없는 독보적 가치입니다. CI-TEC는 당신을 **'클라우드 오케스트레이터'**로 완성시킬 것입니다."

| 단계 | 명칭 | 핵심 역량 및 역할 | 활용 도구/Stack |
| --- | --- | --- | --- |
| **L1** | **Cloud Ops** | 가상 자원 프로비저닝, 클라우드 기본 모니터링 및 사용자 지원 | OpenStack(Horizon), SCP |
| **L2** | **Infra Coder** | Terraform/Ansible 기반 인프라 자동화(IaC) 구현 및 기술지원 | Terraform, Ansible, Git |
| **L3** | **Cloud Architect** | 하이브리드 클라우드 통합 관리 체계 수립 및 차세대 플랫폼 아키텍처 설계 | Multi-Cloud Governance |

---

## [지속 가능한 선순환을 위한 실행 가이드]

1. **Skill Inventory 시각화**: 각 엔지니어가 현재 어느 단계(L1~L3)에 있는지, 어떤 PISA 항목 전문가인지 대시보드화하여 관리합니다.
2. **Badge 시스템 도입**: 특정 단계의 역량을 증명(예: Lookin 활용 RCA 성공 5건 이상)하면 'CI-TEC Certified Specialist' 배지를 부여하여 자긍심을 고취합니다.
3. **퇴직자 Knowledge Mentor 위촉**: 고연차 퇴직 예정자를 1년 전부터 '마스터' 직책으로 전환하여, 자신의 직무 비전과 노하우를 주니어의 CDP에 이식하는 역할에만 집중하게 합니다.

---

**[Next Step]**
이제 이 상세 JD를 바탕으로, 실제 **'신규 입사자용 12개월 Jumpstart 상세 커리큘럼'**을 작성해 볼까요? 혹은 특정 분야(예: 가장 시급한 OS나 DB)를 선택하여 **'성과 지표(KPI)와 매칭된 로드맵'**을 구체화할 수도 있습니다. 어떤 것을 먼저 진행할까요?
