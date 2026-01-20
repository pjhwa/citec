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


## [CI-TEC OS Specialist: Job Description & Vision]

### 1. Elevator Pitch: 당신의 커리어 비전

> **"운영체제의 경계를 넘어 하이퍼스케일 인프라의 심장을 설계합니다."**
> "단순히 리눅스 명령어를 입력하는 'Admin'에 머물지 마십시오. CI-TEC에서는 10년간 축적된 **Technical Repository**라는 거인의 어깨 위에서, 국내 최대 규모 워크로드의 **커널 패닉(Kernel Panic)**을 실시간 추적하고 **NUMA 아키텍처** 최적화를 통해 성능을 극대화하는 **'System Scientist'**로 성장합니다. 이곳에서의 3년은 업계 표준을 만드는 경험이 될 것이며, 당신이 작성한 RCA 리포트는 차세대 인프라의 진단 알고리즘(PISA)이 될 것입니다."

---

### 2. 상세 직무 정의 (Key Responsibilities)

* **지능형 진단 및 자동화 (PISA & Lookin Mastery)**: 4,000여 개의 PISA 항목을 기반으로 인프라의 건강 상태를 정밀 진단하고, **Lookin** 스크립트를 고도화하여 잠재적 장애를 사전에 탐지하는 '예방적 운영' 체계를 구축합니다.
* **심층 성능 최적화 (Kernel & Performance Engineering)**: **eBPF, Systemtap** 등 최첨단 도구를 활용하여 I/O 병목, 메모리 누수, CPU 스케줄링 간섭 등을 분석하고, 워크로드 특성에 최적화된 OS 파라미터를 설계합니다.
* **장애 근본 원인 규명 (Advanced RCA)**: 단순 현상 조치를 넘어, **ProbeONE** 트레이싱 데이터를 분석하여 커널 레벨의 버그나 하드웨어 호환성 이슈를 규명하는 기술적 리더십을 발휘합니다.
* **기술 자산화 및 지식 승계 (Knowledge Capitalization)**: 10년 경과 기술 자산을 최신 트렌드에 맞게 리모델링하고, 시니어의 암묵지를 **Troubleshooting Decision Tree** 형태의 형식지로 전환하여 조직의 지능을 높입니다.

---

### 3. 단계별 성장 경로 (CDP: Career Development Path)

| 단계 | 역할 명칭 | 핵심 미션 및 역량 스택 | 독보적 커리어 가치 |
| --- | --- | --- | --- |
| **Level 1** | **OS Guardian** (Onboarding) | **[역량]** PISA 4,000 표준 진단 숙달, 기초 SOP 수행, Lookin 기본 쿼리 활용<br>
<br>**[미션]** 표준 인프라 가용성 유지 및 정기 점검 자동화 | 국내 최대 규모 인프라의 운영 표준(Standard)을 체득한 주니어 전문가 |
| **Level 2** | **Performance Analyst** (Specialist) | **[역량]** 커널 파라미터 튜닝, eBPF 기반 실시간 프로파일링, RCA 리포트 고도화<br>
<br>**[미션]** 저지연(Low-latency) 및 고집적 워크로드 최적화 설계 | 특정 도메인(OS/Hw)에서 업계 상위 1%의 트러블슈팅 능력을 보유한 스페셜리스트 |
| **Level 3** | **System Architect** (Master) | **[역량]** 차세대 OS 전략 수립, PISA 진단 로직 설계, 지식 그래프(KM) 아키텍처 주도<br>
<br>**[미션]** 기술 부채 해결 및 지속 가능한 지식 전수 체계 완성 | 인프라 전체의 기술 방향성을 결정하고 후배를 양성하는 '기술 HR 전략가' |

---

### 4. OS 담당자만을 위한 'Jumpstart' 가속 요소

신규 입사자나 주니어가 고연차의 노하우를 빠르게 흡수하기 위해 OS 파트에서는 다음의 **'기술 전수 장치'**를 운영합니다.

1. **PISA Reverse Engineering**: 시니어가 만든 진단 항목(PISA)이 '왜' 만들어졌는지 배경(Rationale)을 주니어가 분석하고 시니어에게 검증받는 역방향 학습.
2. **Kernel Panic Simulation**: 테크리포에 기록된 과거 대형 장애 상황을 가상 환경에서 재현하고, **ProbeONE**으로 원인을 찾아가는 실전형 시뮬레이션.
3. **The "Lookin" Library**: 숙련된 OS 전문가들이 사용한 분석 스크립트와 쿼리 묶음을 'Script Repository'로 제공하여 신규자의 분석 생산성을 즉시 시니어 수준으로 확보.

---

## [CI-TEC DB Specialist: Job Description & Vision]

### 1. Elevator Pitch: 당신의 커리어 비전

> **"국내 최대 규모의 복합 DB 생태계를 진단하고, 데이터의 흐름을 설계하는 아키텍트로 거듭납니다."**
> "단순히 쿼리를 튜닝하고 인덱스를 생성하는 기술자에 머물지 마십시오. CI-TEC에서는 Oracle에서 HANA, 오픈소스(PostgreSQL/MySQL)로 이어지는 **이기종 DB 전환의 핵심 아키텍처**를 경험하게 됩니다. 10년의 노하우가 집약된 **PISA 진단 알고리즘**을 통해 일반 DBA는 평생 한 번 보기 힘든 대규모 트랜잭션 장애를 해결하고, **Lookin DB** 모듈로 수만 개의 인스턴스를 자동화된 체계로 관리하는 **'데이터 사이언티스트급 엔지니어'**로 성장할 것입니다."

---

### 2. 상세 직무 정의 (Key Responsibilities)

* **지능형 데이터 진단 (Intelligent DB Diagnosis)**: 4,000여 개의 PISA 항목 중 DB 특화 진단 로직을 활용하여 성능 저하 요인을 사전에 탐지하고, **Lookin DB Agent**를 통해 실시간 상태 정보를 자산화합니다.
* **이기종 DB 최적화 및 마이그레이션 (Heterogeneous DB Optimization)**: 레거시(Oracle)에서 차세대(HANA/OpenSource)로의 데이터 전환 시 발생하는 아키텍처 불일치를 해결하고, 복합 DB 환경에서의 통합 가용성 모델을 설계합니다.
* **심층 성능 분석 및 RCA (Advanced SQL & Instance RCA)**: **ProbeONE**의 트랜잭션 추적 데이터를 분석하여 락(Lock), 대기 이벤트(Wait Events), 실행 계획(Execution Plan)의 왜곡을 바로잡는 최고 수준의 트러블슈팅을 수행합니다.
* **데이터 거버넌스 및 KM 리더십 (Data Governance & KM)**: 시니어의 튜닝 노하우를 **'Troubleshooting Decision Tree'**로 격상시켜 테크리포에 등재하고, 후배들이 즉시 활용 가능한 **SQL 쿼리 라이브러리**를 구축합니다.

---

### 3. 단계별 성장 경로 (CDP: Career Development Path)

| 단계 | 역할 명칭 | 핵심 역량 및 역할 스택 | 독보적 커리어 가치 |
| --- | --- | --- | --- |
| **Level 1** | **DB Guardian** (Onboarding) | **[역량]** PISA DB 진단 항목 숙달, 백업/복구 SOP 수행, Lookin 기반 가용량 관리<br>

<br>**[미션]** 표준 DB 인스턴스의 안정성 확보 및 정기 점검 자동화 | 대규모 엔터프라이즈 DB의 운영 표준과 가동 원리를 완벽히 이해한 신뢰받는 엔지니어 |
| **Level 2** | **Performance Optimizer** (Specialist) | **[역량]** 복합 쿼리 튜닝, 이기종 DB 마이그레이션 기술, Lookin 기반 성능 프로파일링<br>

<br>**[미션]** 대규모 트랜잭션 병목 해결 및 DB 성능 최적화 가이드 수립 | 특정 벤더에 종속되지 않고 어떤 DB 환경에서도 최적의 성능을 끌어내는 전문 튜너 |
| **Level 3** | **Data Platform Architect** (Master) | **[역량]** 차세대 데이터 아키텍처 설계, 자가 치유(Self-Healing) DB 로직 개발, 지식 승계 전략 주도<br>

<br>**[미션]** 전사 데이터 거버넌스 수립 및 AI 기반 지능형 진단 체계 완성 | 인프라 전반의 데이터 전략을 결정하고 지식 자산을 경영하는 기술 HR 전략가 |

---

### 4. DB 담당자만을 위한 'Jumpstart' 가속 요소

DB 분야는 특히 시니어의 '감'과 '경험'이 중요하므로, 이를 시스템적으로 전수하기 위한 장치를 가동합니다.

1. **SQL Tuning Dojo (모의 훈련)**: 테크리포에 기록된 과거 성능 장애 사례를 바탕으로, 주니어가 직접 튜닝을 시도하고 시니어가 최적의 실행 계획(Plan)을 가이드하는 **'리버스 멘토링'** 세션.
2. **PISA Logic Deep-Dive**: "왜 이 수치를 임계치로 설정했는가?"에 대한 시니어의 판단 근거(Rationale)를 인터뷰하여 PISA 항목 옆에 **'전문가 팁(Context-base Tip)'**으로 명문화.
3. **Lookin DB Query Library**: 숙련된 전문가들이 장애 분석 시 사용한 실제 SQL 쿼리와 파이프라인 스크립트를 도서관 형태로 구축하여, 주니어가 복잡한 분석 도구를 배우지 않아도 시니어와 동일한 수준의 데이터 추출이 가능하게 지원.

---

## [CI-TEC Middleware Specialist: Job Description & Vision]

### 1. Elevator Pitch: 당신의 커리어 비전

> **"복잡한 트랜잭션의 실맥을 짚고, 멈추지 않는 서비스 아키텍처를 설계합니다."**
> "단순히 WAS 설정 파일을 수정하는 엔지니어에 머물지 마십시오. CI-TEC에서는 레거시 시스템의 상징인 Tuxedo부터 최신 Microservices Architecture(MSA)의 핵심인 Kubernetes까지, 인프라의 전 계층을 관통하는 **'트랜잭션 오케스트레이터'**로 성장합니다. 10년의 정수가 담긴 **PISA 진단 체계**와 **Lookin MW**를 통해 수천 개의 인스턴스 사이에서 발생하는 병목을 1초 안에 찾아내고, 서비스 가용성을 99.999%로 끌어올리는 **'SRE 전략가'**로서의 독보적 가치를 증명하십시오."

---

### 2. 상세 직무 정의 (Key Responsibilities)

* **지능형 가용성 진단 (Middleware Health Monitoring)**: 4,000여 개의 PISA 항목 중 미들웨어 특화 로직을 활용하여 JVM(Java Virtual Machine) Heap 메모리, Thread 풀, 커넥션 풀의 상태를 정밀 진단하고 장애 징후를 선제적으로 차단합니다.
* **복합 미들웨어 아키텍처 최적화 (Legacy to Cloud-Native)**: Tuxedo, JBoss 등 전통적 미들웨어 환경과 컨테이너 기반 클라우드 환경이 공존하는 하이브리드 인프라에서 최적의 서비스 성능 배분과 연동 구조를 설계합니다.
* **심층 트랜잭션 분석 및 RCA (End-to-End Tracing & RCA)**: **ProbeONE**의 분산 트랜잭션 추적 기능을 활용하여 어플리케이션 지연의 근본 원인이 소스 코드인지, 미들웨어 설정인지, 혹은 하부 인프라인지를 명확히 규명하는 기술적 심판관 역할을 수행합니다.
* **운영 자동화 및 지식 자산화 (Automation & Knowledge Engineering)**: 반복적인 배포 및 설정 작업을 **Ansible/Terraform**으로 자동화하고, 시니어의 트러블슈팅 직관을 **'Middleware Decision Tree'**로 변환하여 테크리포의 지능형 검색 엔진에 이식합니다.

---

### 3. 단계별 성장 경로 (CDP: Career Development Path)

| 단계 | 역할 명칭 | 핵심 역량 및 역할 스택 | 독보적 커리어 가치 |
| --- | --- | --- | --- |
| **Level 1** | **MW Guardian** (Onboarding) | **[역량]** PISA MW 진단 수행, 표준 WAS/Web 설정, Lookin 기반 로그 분석<br>

<br>**[미션]** 표준 미들웨어 환경의 안정성 유지 및 보안 취약점 점검 자동화 | 대규모 트래픽을 처리하는 엔터프라이즈 미들웨어의 기본 구조를 완벽히 마스터한 인재 |
| **Level 2** | **SRE Engineer** (Specialist) | **[역량]** Java/C 프로파일링, Thread/Heap Dump 분석, 컨테이너 오케스트레이션(K8s)<br>

<br>**[미션]** 복합 장애 RCA 주도 및 성능 튜닝 가이드 수립, CI/CD 파이프라인 최적화 | 레거시와 클라우드를 자유자재로 다루며 서비스 가용성을 책임지는 고숙련 엔지니어 |
| **Level 3** | **Service Architect** (Master) | **[역량]** MSA 전환 전략 수립, 지능형 자가 치유(Self-Healing) 로직 설계, 지식 승계 체계 총괄<br>

<br>**[미션]** 전사 서비스 신뢰성 가이드라인 수립 및 미래형 플랫폼 아키텍처 설계 | 기술적 한계를 넘어서는 솔루션을 제시하고 조직의 지식 자산을 경영하는 테크니컬 리더 |

---

### 4. Middleware 담당자만을 위한 'Jumpstart' 가속 요소

미들웨어는 보이지 않는 흐름을 가시화하는 능력이 핵심이므로, 시니어의 '통찰'을 이식하기 위한 특화 프로그램을 운영합니다.

1. **Dump Analysis Masterclass**: 시니어가 해결했던 역대급 메모리 누수(Memory Leak)나 스레드 데드락(Deadlock) 사례의 덤프 파일을 주니어가 직접 분석하고, 시니어의 분석 경로와 비교하는 **'섀도잉 분석 훈련'**.
2. **PISA Logic Documentation**: 특정 미들웨어 에러 코드에 대응하는 PISA 진단 로직의 비하인드 스토리(Case Study)를 인터뷰 형식으로 기록하여, 단순 '조치'가 아닌 '원리' 중심의 지식 전수.
3. **The "Lookin" Automation Library**: 숙련자들이 장애 대응 시 즉각적으로 활용하는 JVM 모니터링 스크립트와 트래픽 제어 명령어를 **'Standard Playbook'**으로 구성하여, 신입 사원도 투입 즉시 시니어 수준의 초동 조치 가능.

---

## [CI-TEC Network Specialist: Job Description & Vision]

### 1. Elevator Pitch: 당신의 커리어 비전

> **"단순한 연결을 넘어, 데이터의 흐름을 지휘하는 네트워크 아키텍트로 도약합니다."**
> "단순히 스위치 명령어를 입력하는 'Config 관리자'에 머물지 마십시오. CI-TEC에서는 국내 최대 규모의 복합 망에서 발생하는 페타바이트급 트래픽을 **ProbeONE NW**로 실시간 해부하고, **Spine-Leaf** 및 **SDN** 기반의 차세대 아키텍처를 설계하는 경험을 쌓게 됩니다. 4,000여 개의 **PISA 진단 로직**을 통해 네트워크 병목의 근본 원인을 단숨에 규명하고, 코드로 네트워크를 제어하는 **'인프라 프로그래머'**로서의 독보적인 커리어를 완성하십시오."

---

### 2. 상세 직무 정의 (Key Responsibilities)

* **지능형 트래픽 진단 (Network Health Engineering):** 4,000여 개의 PISA 항목 중 네트워크 특화 알고리즘을 활용하여 패킷 손실, 지연(Latency), 지터(Jitter) 등의 이상 징후를 선제적으로 탐지하고 최적의 경로를 설계합니다.
* **소프트웨어 정의 인프라 구축 (SDN & Automation):** 인프라를 코드로 관리하는(IaC) 환경에서 **Ansible, Terraform**을 활용하여 대규모 네트워크 설정을 자동화하고, SDN 제어 로직을 통해 트래픽 부하 분산을 최적화합니다.
* **심층 패킷 분석 및 RCA (Deep Packet Inspection & RCA):** **ProbeONE NW**를 활용하여 L2부터 L7까지의 패킷을 전수 분석함으로써, 간헐적인 통신 단절이나 보안 위협의 근본 원인을 데이터 기반으로 규명합니다.
* **지식 자산화 및 망 거버넌스 (NW Knowledge Management):** 시니어의 망 설계 직관을 **'Traffic Flow Decision Tree'**로 격상시켜 테크리포에 등재하고, 후배들이 즉시 활용 가능한 **표준 구성 및 장애 대응 플레이북**을 구축합니다.

---

### 3. 단계별 성장 경로 (CDP: Career Development Path)

| 단계 | 역할 명칭 | 핵심 역량 및 역할 스택 | 독보적 커리어 가치 |
| --- | --- | --- | --- |
| **Level 1** | **NW Guardian** (Onboarding) | **[역량]** PISA NW 진단 항목 숙달, L2/L3 스위칭 운영, Lookin 기반 트래픽 리포팅<br>

<br>**[미션]** 표준 네트워크 장비의 안정성 유지 및 정기 보안 설정 점검 자동화 | 대규모 엔터프라이즈 망의 물리적/논리적 구조를 완벽히 이해한 신뢰받는 엔지니어 |
| **Level 2** | **Traffic Engineer** (Specialist) | **[역량]** 패킷 덤프 심층 분석, SDN 제어 기술, BGP/OSPF 경로 최적화<br>

<br>**[미션]** 복합 네트워크 장애 RCA 주도 및 고성능 백본 아키텍처 가이드 수립 | 트래픽의 흐름을 분석하여 비즈니스 가용성을 극대화하는 고숙련 네트워크 전문가 |
| **Level 3** | **Network Strategist** (Master) | **[역량]** 하이브리드 클라우드 연동망 설계, 지능형 자가 치유 망(Self-Healing NW) 설계, 지식 승계 전략 주도<br>

<br>**[미션]** 전사 네트워크 보안 및 거버넌스 수립, 차세대 SDN 플랫폼 아키텍처 설계 | 네트워크 기술의 미래 방향성을 제시하고 조직의 지식 자산을 경영하는 테크니컬 리더 |

---

### 4. Network 담당자만을 위한 'Jumpstart' 가속 요소

네트워크는 가시성(Visibility) 확보가 성패를 결정하므로, 시니어의 분석 기법을 이식하기 위한 특화 프로그램을 운영합니다.

1. **Packet Analysis Dojo (실전 패킷 도장):** 테크리포에 기록된 과거 대형 장애(예: 브로드캐스트 스톰, 라우팅 루프) 시의 실제 패킷 데이터를 주니어가 **ProbeONE**으로 다시 분석하며 해결 경로를 찾는 **'디지털 모의 훈련'**.
2. **PISA Rationale Wiki:** 특정 네트워크 임계치(Threshold) 설정의 이유와 당시 고려되었던 토폴로지 특성을 시니어의 목소리로 기록하여, 단순 '수치'가 아닌 '설계 의도'를 전수.
3. **The "Lookin" NW Script Library:** 숙련된 전문가들이 복잡한 망 상태를 한눈에 파악하기 위해 만든 커스텀 스크립트와 자동화 쿼리를 공유하여, 주니어가 투입 즉시 시니어 수준의 **'망 가시성'**을 확보하게 지원.

---

## [CI-TEC Storage Specialist: Job Description & Vision]

### 1. Elevator Pitch: 당신의 커리어 비전

> **"레거시 스토리지의 한계를 넘어, 데이터의 생명주기를 설계하는 저장소 아키텍트가 됩니다."**
> "단순히 스토리지 볼륨을 할당하고 하드웨어 장애를 처리하는 '인프라 관리자'에 머물지 마십시오. CI-TEC에서는 국내 최대 규모의 데이터 보존 환경에서 **PISA 진단 항목**을 통해 수만 개의 디스크 상태를 예측하고, Ceph와 같은 **소프트웨어 정의 스토리지(SDS)**로의 대전환을 주도하게 됩니다. **Lookin STG**를 통해 병목의 근원을 파헤치고, AI 워크로드를 뒷받침하는 초고성능 스토리지 팜을 설계하는 **'데이터 인프라 아키텍트'**로서 업계 독보적인 권위를 확보하십시오."

---

### 2. 상세 직무 정의 (Key Responsibilities)

* **지능형 스토리지 진단 (Storage Health Engineering):** 4,000여 개의 PISA 항목 중 스토리지 특화 로직을 활용하여 컨트롤러 부하, 캐시 적중률, 디스크 수명 등을 정밀 진단하고 데이터 손실 가능성을 사전에 차단합니다.
* **차세대 저장소 전환 (SDS & Cloud Storage Transition):** 전통적인 SAN/NAS 환경에서 오픈소스 기반의 **Ceph, Swift** 등 분산 스토리지 체계로의 기술 전환을 설계하고 운영 거버넌스를 수립합니다.
* **I/O 성능 최적화 및 RCA (Performance Tuning & RCA):** **Lookin STG** 모듈을 활용하여 어플리케이션 레이턴시의 원인이 스토리지 I/O 병목인지, 네트워크 구간의 문제인지를 규명하고 최적의 I/O 경로를 재설계합니다.
* **데이터 보호 전략 및 지식 자산화 (Data Protection & KM):** 시니어의 백업 및 복구 직관을 **'Data Recovery Decision Tree'**로 격상시켜 테크리포에 등재하고, 후배들이 즉시 활용 가능한 **I/O 프로파일링 플레이북**을 구축합니다.

---

### 3. 단계별 성장 경로 (CDP: Career Development Path)

| 단계 | 역할 명칭 | 핵심 역량 및 역할 스택 | 독보적 커리어 가치 |
| --- | --- | --- | --- |
| **Level 1** | **Storage Guardian** (Onboarding) | **[역량]** PISA STG 진단 항목 숙달, 볼륨 할당/해제 SOP, Lookin 기반 가용량 리포팅<br>

<br>**[미션]** 표준 스토리지 장비의 안정성 유지 및 정기 데이터 보호 점검 자동화 | 엔터프라이즈 스토리지의 하드웨어 구조와 데이터 보존 원리를 완벽히 마스터한 인재 |
| **Level 2** | **SDS Engineer** (Specialist) | **[역량]** Ceph/Swift 구축 및 운영, NVMe/All-Flash 최적화, 스토리지 성능 프로파일링<br>

<br>**[미션]** 스토리지 장애 RCA 주도 및 분산 스토리지 성능 최적화 가이드 수립 | 레거시와 오픈소스를 아우르며 데이터 저장 기술의 정점을 경험한 고숙련 엔지니어 |
| **Level 3** | **Storage Architect** (Master) | **[역량]** 전사 데이터 보호 거버넌스 수립, 초고성능 AI 스토리지 팜 설계, 지식 승계 전략 주도<br>

<br>**[미션]** 데이터 생명주기 관리(ILM) 전략 수립 및 지능형 데이터 저장 플랫폼 설계 | 데이터 인프라의 미래 방향성을 제시하고 조직의 지식 자산을 경영하는 테크니컬 리더 |

---

### 4. Storage 담당자만을 위한 'Jumpstart' 가속 요소

스토리지는 데이터의 안전성이 최우선이므로, 시니어의 '리스크 관리 직관'을 이식하기 위한 특화 프로그램을 운영합니다.

1. **I/O Simulation Dojo (I/O 시뮬레이션 도장):** 테크리포에 기록된 과거 성능 저하 사례(예: RAID 리빌딩 시 성능 저하)를 가상 환경에서 재현하고, **Lookin STG**로 병목 구간을 찾아 조치하는 **'실전형 트러블슈팅 훈련'**.
2. **PISA Rationale Wiki (임계치 설계 의도):** "왜 이 디스크 응답 속도를 20ms로 제한했는가?"와 같은 시니어의 설계 Rationale을 데이터 기반으로 기록하여, 주니어가 수치 너머의 **'설계 철학'**을 이해하도록 지원.
3. **The "Lookin" STG Script Library:** 숙련된 전문가들이 수만 개의 LUN 상태를 한눈에 파악하기 위해 만든 자동화 스크립트와 데이터 시각화 쿼리를 공유하여, 주니어가 투입 즉시 시니어 수준의 **'데이터 가시성'**을 확보하게 지원.

---


## [CI-TEC Cloud Technical Support Specialist: Job Description & Vision]

### 1. Elevator Pitch: 당신의 커리어 비전

> **"보이지 않는 가상화 계층의 문제를 해결하는 클라우드 최후의 보루가 됩니다."**
> "단순히 자원을 할당하는 운영자에 머물지 마십시오. CI-TEC에서는 VMware와 OpenStack이라는 이기종 클라우드 환경에서 발생하는 수만 가지 인프라 장애를 해결하는 **'클라우드 트러블슈팅 전문가'**로 성장합니다. 4,000여 개의 **PISA 진단 항목**과 **Lookin/ProbeONE**을 무기 삼아 하이퍼바이저, 가상 네트워크, 공유 스토리지 사이의 복잡한 상관관계를 파헤치십시오. 이곳에서의 3년은 일반적인 클라우드 운영 환경에서는 결코 경험할 수 없는 **'인프라 심층 장애 해결 역량'**을 당신에게 선사할 것입니다."

---

### 2. 상세 직무 정의 (Key Responsibilities)

* **클라우드 인프라 기술지원 (Cloud Infrastructure Technical Support):** 클라우드 상에서 구동되는 가상 머신(VM) 및 인스턴스의 성능 저하, 연결 오류 등 각종 인프라 관련 사용자 이슈를 접수하고 기술적으로 지원합니다.
* **가상화 계층 장애 대응 (Virtualization Layer Incident Response):** VMware ESXi 또는 OpenStack Compute(Nova) 노드에서 발생하는 시스템 패닉, 자원 경합, 행(Hang) 현상 등에 대해 **PISA 진단 로직**을 활용하여 신속하게 초동 조치 및 복구를 수행합니다.
* **복합 이슈 근본 원인 분석 (Cloud-Specific RCA):** 가상 네트워크(NSX/Neutron)의 통신 단절이나 가상 스토리지(vSAN/Ceph)의 I/O 지연 등 가상화 계층 전반에 걸친 장애의 근본 원인을 **ProbeONE** 데이터를 기반으로 규명합니다.
* **장애 대응 지식 자산화 (Incident Knowledge Management):** 해결된 장애 사례를 분석하여 유사 이슈 재발 방지를 위한 **'Troubleshooting Playbook'**을 작성하고, 시니어의 대응 노하우를 테크리포의 지식 그래프로 전환합니다.

---

### 3. 단계별 성장 경로 (CDP: Career Development Path)

| 단계 | 역할 명칭 | 핵심 역량 및 역할 스택 | 독보적 커리어 가치 |
| --- | --- | --- | --- |
| **Level 1** | **Cloud Responder** (Onboarding) | **[역량]** PISA Cloud 진단 항목 숙달, 표준 장애 대응 SOP 이행, Lookin 기반 자원 모니터링<br>

<br>**[미션]** 반복적인 클라우드 기술지원 요청 처리 및 장애 상황 전파/초동 조치 | 가상화 환경의 기초 구조와 장애 유형을 완벽히 습득한 신뢰받는 지원 엔지니어 |
| **Level 2** | **Incident Analyst** (Specialist) | **[역량]** 하이퍼바이저 로그 분석, 가상 네트워크/스토리지 심층 분석, 복합 장애 RCA 수행<br>

<br>**[미션]** 난이도 높은 클라우드 인프라 이슈 해결 주도 및 분야별 장애 대응 가이드 수립 | VMware와 OpenStack을 아우르며 어떤 클라우드 이슈도 해결 가능한 기술 스페셜리스트 |
| **Level 3** | **Diagnostic Master** (Master) | **[역량]** 차세대 클라우드 진단 체계 설계, 고난도 장애 의사결정(Decision Making), 지식 승계 전략 주도<br>

<br>**[미션]** 전사 클라우드 기술지원 거버넌스 수립 및 시니어 퇴직 대비 지식 보존 체계 완성 | 클라우드 장애 대응의 표준을 만들고 조직의 기술 자산을 경영하는 테크니컬 리더 |

---

### 4. Cloud 담당자만을 위한 'Jumpstart' 가속 요소

인프라 자동화 구현보다는 **'장애 진단 및 해결'**에 특화된 육성 체계를 운영합니다.

1. **Cloud Incident Replay (장애 복기 세션):** 테크리포에 기록된 과거 대형 클라우드 장애 사례(예: OpenStack 메시지 큐 지연, VMware 스토리지 APD 현상 등)를 시니어와 함께 복기하며 **'진단 경로'**를 학습합니다.
2. **PISA Diagnostic Training:** 4,000여 개의 진단 항목 중 클라우드 기술지원에 빈번히 사용되는 핵심 항목의 설정 배경(Rationale)을 시니어가 설명하고, 주니어가 실제 Lookin 데이터와 매칭해보는 실습을 진행합니다.
3. **The "Lookin" Query Library for Support:** 숙련된 기술지원 전문가들이 장애 발생 시 특정 VM의 상태를 즉시 파악하기 위해 사용하는 **'고속 진단 쿼리 셋'**을 공유하여, 주니어가 투입 즉시 시니어 수준의 분석 생산성을 확보하도록 돕습니다.

---
