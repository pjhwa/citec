---
title: "SCP 중장기 로드맵"
date: 2025-05-13
tags: [scp, cloud, samsung, plan]
---

# Samsung Cloud Platform (SCP) 중장기 기술로드맵 초안

## 1. 프로젝트 개요
Samsung Cloud Platform (SCP)의 3~5년 중장기 기술로드맵을 작성하기 위해, 주요 경쟁사(AWS, Azure, GCP, 네이버 클라우드, NHN, KT)와의 서비스 라인업 비교를 통해 SCP의 차별화 포인트를 도출합니다. 본 로드맵은 기술적 깊이를 강조하며, 영업적/숫자적 관점보다 기술적 경쟁력을 중심으로 구성됩니다. 프로젝트는 2주 소규모 프로젝트로, 1주 후 중간보고가 예정되어 있습니다.

## 2. 조사 대상 및 방법
### 조사 대상
- **글로벌 클라우드 제공업체**: AWS, Azure, Google Cloud Platform (GCP)
- **한국 클라우드 제공업체**: 네이버 클라우드, NHN 클라우드, KT 클라우드
- **SCP**: 삼성SDS의 클라우드 플랫폼 ([서비스 목록](https://www.samsungsds.com/en/cloud-product-list/cloud-product-list.html))

### 조사 방법
- 각 제공업체의 서비스 카테고리와 주요 서비스 수를 비교.
- 기능별 세부 비교는 제외하고, 서비스 라인업의 폭과 깊이를 중심으로 분석.
- SCP의 차별화 포인트를 도출하기 위해 산업별 사례, 기술적 강점, 지역적 이점을 조사.

## 3. 클라우드 서비스 카테고리 및 비교
클라우드 서비스는 일반적으로 다음과 같은 주요 카테고리로 분류됩니다:
- Compute, Storage, Database, Container, Networking, Security, Application Service, DevOps Tools, Data Analytics, AI/ML, Management, Hybrid Cloud

### SCP 서비스 라인업
SCP는 12개 주요 카테고리에서 다양한 서비스를 제공합니다. 아래는 주요 카테고리와 서비스 수를 정리한 표입니다:

| **카테고리**          | **서비스 수** | **주요 서비스**                                                                 |
|-----------------------|---------------|--------------------------------------------------------------------------------|
| Compute               | 8             | Bare Metal Server, GPU Server, HPC Cluster, Virtual Server                     |
| Storage               | 6             | Archive Storage, Block Storage, Object Storage, Parallel File Storage          |
| Database              | 9             | CUBRID, EPAS(DBaaS), MySQL(DBaaS), PostgreSQL(DBaaS)                          |
| Container             | 3             | Container Registry, Kubernetes Apps, Kubernetes Engine                         |
| Networking            | 15            | Cloud LAN, DNS, Firewall, Load Balancer, VPC                                   |
| Security              | 11            | Certificate Manager, DDoS Protection, Key Management Service, WAF              |
| Application Service   | 3             | API Gateway, GraviX, Mail/SMS/Push                                            |
| DevOps Tools          | 3             | DevOps Code, DevOps Service, GitHub Enterprise                                |
| Data Analytics        | 11            | Cloud Hadoop, Data Catalog, Quick Query, VMware Greenplum                      |
| AI/ML                 | 8             | AI&MLOps Platform, CloudML Notebook, Text API, Vision API                     |
| Management            | 7             | Cloud Control, Cloud Monitoring, IAM, VM Migration                            |
| Hybrid Cloud          | 2             | Edge Server, Oracle Services                                                  |

### 경쟁사 서비스 라인업 비교
#### 글로벌 제공업체
- **AWS**: 20개 이상의 카테고리에서 200개 이상의 서비스 제공. 예: Storage(S3, EBS, EFS 등 10개 이상), AI/ML(SageMaker, Rekognition 등).
- **Azure**: 약 20개 카테고리, 특히 AI + Machine Learning(27개 서비스), Compute(20개 이상)에서 강세 ([Azure 서비스](https://azure.microsoft.com/en-us/products/)).
- **GCP**: 100개 이상의 서비스, Big Data(BigQuery, Dataflow)와 AI(Cloud Vision API, AutoML)에서 경쟁력 ([GCP 서비스](https://cloud.google.com/docs/get-started/aws-azure-gcp-service-comparison)).

#### 한국 제공업체
- **네이버 클라우드**: 약 19개 카테고리(Compute, Storage, AI Services, Blockchain 등). AI 서비스(CLOVA, Papago)와 웹 서비스에서 강점 ([네이버 클라우드](https://www.ncloud.com/?language=en-US)).
- **NHN 클라우드**: Cloud, Hosting, AI, Data Center 등 4~6개 카테고리 추정. 게임 산업(Hangame)과 AI(GPU 기반)에서 전문성 ([NHN 클라우드](https://company.nhncloud.com/service)).
- **KT 클라우드**: 8개 카테고리(SERVER, DATABASE, STORAGE/CDN 등). 네트워킹과 IoT에서 강점 ([KT 클라우드](https://cloud.kt.com/en/)).

| **제공업체**       | **카테고리 수** | **주요 강점**                              |
|--------------------|-----------------|--------------------------------------------|
| SCP                | 12              | 지역 데이터센터, 보안, AI/ML, 산업 특화     |
| AWS                | 20+             | 서비스 다양성, 글로벌 확장성                |
| Azure              | 20              | AI/ML, 하이브리드 클라우드                 |
| GCP                | 15+             | 빅데이터, AI, 오픈소스 친화                |
| 네이버 클라우드    | 19              | AI 서비스, 웹 서비스, 한국 시장 최적화     |
| NHN 클라우드       | 4~6             | 게임, AI, 오픈스택 기반                    |
| KT 클라우드        | 8               | 네트워킹, IoT, 공공 인증                   |

## 4. SCP의 차별화 포인트
SCP는 경쟁사 대비 다음과 같은 독특한 강점을 보유하고 있습니다:

1. **아시아 지역 데이터센터**: 한국 내 데이터센터를 통해 낮은 지연 시간과 일본, 싱가포르 등 아시아 시장 접근성을 제공. 지역 데이터 주권 및 규제 준수에 유리 ([Samsung SDS Cloud Potential](https://scalardynamic.com/resources/articles/10-samsung-sds-cloud-platform-enterprise-potential)).
2. **강력한 보안 기능**: 고급 암호화, 다중 인증, 지속적 모니터링 등 삼성의 하드웨어/소프트웨어 보안 기술 활용. 한국 내 최장수 클라우드 보안 제공업체로 인정 ([Samsung Cloud Platform](https://www.samsungsds.com/en/enterprise-cloud/enterprise-cloud.html)).
3. **AI 및 ML 서비스**: Brightics AI, AI&MLOps Platform 등 고급 분석 및 머신러닝 서비스 제공, 특히 제조 및 반도체 산업에 최적화.
4. **삼성 생태계 통합**: 삼성 디바이스 및 서비스와의 원활한 통합, 삼성 제품 사용 기업에 매력적.
5. **산업별 전문성**: 제조, 금융, 유통/서비스, 공공 부문 사례를 통해 입증된 전문성. 예: SCM SaaS로 운영 효율성 증대.
6. **경쟁력 있는 가격 정책**: 사용 약정 할인, 전체 볼륨 할인 등 유연한 가격 옵션 제공.
7. **자동화 기능**: 클라우드 리소스 관리 간소화 및 운영 효율성을 높이는 강력한 자동화 도구.

## 5. 중장기 기술로드맵 제안
### 5.1 전략적 방향
- **AI/ML 강화**: Brightics AI 및 CloudML 서비스 확장, 특히 제조 및 금융 산업용 맞춤형 AI 솔루션 개발.
- **보안 고도화**: 한국 및 아시아 지역 규제 준수를 위한 보안 인증 추가 취득, AI 기반 보안 위협 탐지 도입.
- **하이브리드 클라우드 확대**: Edge Server 및 Oracle Services를 활용한 하이브리드 클라우드 솔루션 강화.
- **산업별 맞춤화**: 제조, 금융, 공공 부문에 특화된 클라우드 패키지 개발.
- **가격 경쟁력 유지**: 지역 시장에 맞춘 유연한 가격 정책 지속, 특히 중소기업 타겟 프로모션 확대.

### 5.2 기술 개발 우선순위
| **우선순위** | **기술 영역**            | **세부 계획**                                                                 |
|--------------|--------------------------|------------------------------------------------------------------------------|
| 1            | AI/ML                    | - AI&MLOps Platform 고도화<br>- 반도체 설계용 AI 솔루션 개발                 |
| 2            | 보안                     | - AI 기반 실시간 위협 탐지 시스템 도입<br>- 추가 보안 인증 취득               |
| 3            | 하이브리드 클라우드      | - Edge Server 확장<br>- 멀티 클라우드 관리 도구 개발                         |
| 4            | 산업별 솔루션            | - 제조업용 IoT 통합 클라우드 패키지<br>- 금융 규제 준수 솔루션 강화          |
| 5            | 자동화 및 관리            | - Cloud Control 및 Monitoring 기능 개선<br>- VM Migration 자동화 도구 개발   |

### 5.3 예상 결과
- **경쟁력 강화**: AI/ML 및 보안에서 글로벌 및 지역 경쟁사 대비 우위 확보.
- **시장 확대**: 아시아 지역 및 삼성 생태계 내 기업을 타겟으로 시장 점유율 증가.
- **고객 만족도 향상**: 산업별 맞춤 솔루션과 자동화로 운영 효율성 및 비용 절감.

## 6. 중간보고 계획 (1주 후)
- **완료 예정**: 경쟁사 서비스 라인업 비교 완료, SCP 차별화 포인트 초안 작성.
- **보고 내용**:
  - 주요 카테고리별 서비스 수 비교 표.
  - SCP의 잠재적 강점 및 약점 분석.
  - 초기 로드맵 방향 제안.
- **추가 조사 필요**:
  - NHN 및 KT 클라우드의 세부 서비스 목록.
  - SCP의 최신 가격 정책 및 고객 피드백.

## 7. 결론
SCP는 아시아 지역 데이터센터, 강력한 보안, AI/ML, 삼성 생태계 통합, 산업별 전문성을 바탕으로 경쟁사와 차별화됩니다. 향후 3~5년 동안 AI/ML, 보안, 하이브리드 클라우드, 산업별 솔루션에 집중 투자하여 한국 및 아시아 시장에서 경쟁력을 강화해야 합니다. 본 로드맵은 기술적 깊이를 강조하며, SCP의 지속 가능한 성장을 위한 전략적 방향을 제시합니다.
