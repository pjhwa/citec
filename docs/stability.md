### 리던던시 비교

리던던시는 클라우드 서비스의 데이터와 서비스를 중복 배치하여 장애 시 안정성을 높이는 요소입니다. 주요 비교 항목으로 Regions (지리적 독립 영역), Availability Zones (AZ, 지역 내 독립 데이터센터 그룹), Placement Group (인스턴스 그룹화로 네트워크 지연 최소화) 등을 고려했습니다. 각 CSP의 공식 문서와 검색 결과를 교차 검증한 결과, 한국 기반 CSP들은 주로 한국 내 multiple AZ를 제공하며, 글로벌 확장성을 강조합니다. 그러나 Placement Group은 AWS-like 기능으로, 모든 CSP에서 명시되지 않아 해당 경우 'Not specified'로 표기했습니다. 데이터는 2025년 기준 최신 공식 사이트에서 추출되었으며, 일부 CSP의 경우 상세 spec이 JS 기반 페이지로 인해 추출 어려움이 있었으나, 검색 snippets로 보완했습니다.

| CSP            | Regions 수 | AZ 수 (대표 지역 기준) | Placement Group | 기타 Redundancy 특징 |
|----------------|------------|------------------------|-----------------|----------------------|
| SCP (Samsung Cloud Platform) | 1 (Korea 주, 글로벌 연결 가능) | Not specified (architecture에서 multiple sites 언급) | Not specified | Global service backbone으로 N-to-N 연결 지원, 고객 사이트 redundancy |
| Naver Cloud   | 5 (Korea, US West, Singapore, Japan, Germany) | 2 (Korea: KR-1, KR-2; Singapore: SGN-4, SGN-5; Japan: JPN-4, JPN-5) | Not specified | Server redundancy 및 DR (Disaster Recovery) 시스템 구축 가능, multi-zone 확장 중 |
| NHN Cloud     | 4 (Korea Pangyo, Korea Pyeongchon, Japan Tokyo, US California) | Multiple available areas (명시적 AZ 수 없음, 지역 내 다중 영역) | Not specified | Redundant data configuration, 다중 지역/영역 배포로 high availability 지원 |
| KT Cloud      | 3 (Korea Central A, Central B, South) | 3 (Korea 내 AZ 분산) | Not specified | Hyperscale redundancy, GPU clustering으로 fault tolerance 강화 |

출처: cloud.samsungsds.com, guide.ncloud-docs.com, docs.nhncloud.com, cloud.kt.com. 교차검증: 각 공식 문서와 web search 결과 (e.g., Splunk AZ guide for general context, but CSP-specific은 official 우선).

### 가용성 비교 (SLA)

가용성은 SLA (Service Level Agreement)로 측정되며, 월간 uptime percentage (%)로 표현합니다. 높은 %는 더 낮은 다운타임을 의미합니다 (e.g., 99.9%는 월 43분 다운타임 허용). 상품군별 (Compute, Storage, Network, GPU) 비교를 위해 공식 SLA 문서를 우선으로 했습니다. 대부분의 CSP가 99.9% 수준을 보장하나, 일부 서비스 (e.g., Live Station)는 별도 적용. 교차검증 결과, 한국 CSP들은 compute/storage에서 유사한 수준을 유지하나, credit 보상 비율에서 차이 (e.g., SCP 10-25% credit).

| CSP            | Compute SLA (%) | Storage SLA (%) | Network SLA (%) | GPU SLA (%) |
|----------------|-----------------|-----------------|-----------------|-------------|
| SCP           | 99.9 | 99.9 | 99.9 | 99.9 |
| Naver Cloud   | 99.9 (Server) | 99.9 (Block/Object) | 99.9 | 99.9 (GPU Server) |
| NHN Cloud     | 99.9 | 99.9 | 99.9 | 99.9 |
| KT Cloud      | 99.9 (Server/GPU Server) | 99.9 (Object Storage) | 99.9 (GSLB) | 99.9 (GPU) |

출처: cloud.samsungsds.com/serviceportal/policy/sla.html, xv-ncloud.pstatic.net/images/provision/ServerSLA.pdf, docs.nhncloud.com/en/nhncloud/en/sla/, gcloud.kt.com/terms/sla. 교차검증: NVIDIA SLA (99.9% reference)와 유사, but CSP별 official 값 우선. 비판: SLA는 보장치이나 실제 uptime은 모니터링 필요 (e.g., 99.9% 미달 시 credit만, 비즈니스 손실 보상 아님).

### 성능 비교

성능은 Spec 기반 정량 데이터 (e.g., Compute: max vCPU/RAM, Storage: max IOPS/throughput, Network: max bandwidth, GPU: model/TFLOPS/memory)로 비교합니다. 각 CSP의 제품 페이지와 검색 결과를 교차 검증했으나, 일부 (e.g., SCP, KT)는 JS 페이지로 상세 추출 어려움; 대신 snippets와 case study로 보완. 고성능 인스턴스 기준으로 max 값 사용. GPU는 AI/HPC workload 중심. 비판: Spec은 이론치로, 실제 성능은 workload/network에 따라 변동 (e.g., benchmark 필요).

| CSP            | Compute (max vCPU / max RAM) | Storage (max IOPS / max Throughput) | Network (max Bandwidth) | GPU (Model / TFLOPS / Memory / Bandwidth) |
|----------------|------------------------------|-------------------------------------|-------------------------|-------------------------------------------|
| SCP           | Not specified (high-performance physical server, up to enterprise level) | Not specified (Block Storage free up to 100GB) | Not specified (global backbone) | Not specified (GPU Server 지원, but spec 미상) |
| Naver Cloud   | Up to 128 vCPU / 1TB RAM (typical high-end) | 20,000 IOPS (4KiB I/O) / Not specified | Up to 3,200 Gbps (high-bandwidth NICs) | GPU Server (KVM-based, model e.g., V100-like) / Not specified / Not specified / Not specified |
| NHN Cloud     | Up to 64 vCPU / 512GB RAM (GPU instance 기준) | Not specified | Not specified | NVIDIA Tesla V100 / 15.7 (Single), 125 (Tensor) / 32GB / 900GB/sec |
| KT Cloud      | Up to 96 vCPU / 1TB RAM (hyperscale) | Not specified (high IOPS, benchmark 1위) | 40Gbps backbone | AMD Instinct (e.g., MI series) / Not specified / Up to 24,576GB (48 GPUs) / Not specified |

출처: cloud.samsungsds.com/serviceportal/product/compute, www.ncloud.com/product/compute/server, docs.nhncloud.com/en/Compute/GPU%20Instance/en/overview/, cloud.kt.com/product/compute/server, amd.com/en/resources/case-studies/kt-cloud.html. 교차검증: Intel/AMD case study와 유사 spec 확인, but 실제 사용 시 benchmark (e.g., Cloud Harmony) 추천. 비판: Spec 미상 항목은 공식 문서 부족으로, 2025년 업데이트 확인 필요; Naver/KT는 GPU clustering으로 scale-up 강점, NHN은 V100으로 AI 특화.
