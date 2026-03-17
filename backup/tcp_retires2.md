**핵심 사실** (출처 번호와 함께)  
1. **AWS EKS**: Troubleshooting 페이지 및 Networking Best Practices 문서 전체에서 `net.ipv4.tcp_retries2` 또는 TCP kernel 파라미터 튜닝 관련 **언급 전무** (공식 권장값 없음).  
2. **GCP GKE**: Node System Config에서 지원 sysctl 목록에 `net.ipv4.tcp_retries2` **포함되지 않음** (tcp_syn_retries, tcp_fin_timeout 등 일부 TCP 파라미터만 지원). 트러블슈팅 문서(Connectivity Issues)에서도 미언급.  
3. **Azure AKS**: Custom Node Configuration 지원 sysctl 목록에 `tcp_retries2` **제외** (tcp_keepalive_* 계열만 포함). Azure Advisor는 SAP VM 워크로드에만 =15 유지 권장 (AKS와 무관).  
4. 트러블슈팅 문서(연결 타임아웃, connection reset 등) 전반에서 CSP별로 해당 파라미터 튜닝 언급 없음. 커뮤니티/타사(IBM Db2, Redis 사례)에서만 =2~5 권장 사례 존재.  
(출처 1: TruthGuard 검증 + AWS EKS Troubleshooting; 출처 2: ContextSage + GKE Node System Config; 출처 3: TruthGuard + AKS Custom Node Config; 출처 4: 전체 웹 검색 및 Azure Advisor)

**맥락 요약**  
2026년 3월 기준, 3대 클라우드 관리형 Kubernetes(EKS/GKE/AKS) 공식 문서(베스트프랙티스, 네트워킹 가이드, 트러블슈팅 페이지 포함)를 전수 검색한 결과 **구체적인 권장값(예: 5, 8 등)이 단 한 곳에도 명시되지 않음**. GKE와 AKS조차 해당 파라미터를 공식 node config로 설정할 수 없으며, AWS는 Launch Template/UserData나 DaemonSet으로만 우회 가능. 기본값(15) 유지 시 장애 감지 지연(13~30분)이 k8s Failover와 충돌할 수 있으나, CSP는 이를 공식 가이드로 다루지 않음.

**불확실성 및 한계점**  
**확신할 수 없다** — GKE에서 unsafe sysctl로 별도 활성화 가능성 존재하나 공식 문서 미지원. AKS는 지원조차 안 되므로 DaemonSet 적용 시 노드 OS(예: Ubuntu)별 kernel 호환성 테스트 필수.  
추가 조사가 필요한 부분: 실제 클러스터에서 `ss -m` 또는 tcpdump로 RTO 측정; k8s 1.28+ 및 노드 OS(Amazon Linux 2023/Bottlerocket)에 따른 미세 동작 차이; 2026년 이후 문서 업데이트 모니터링.

**결론**  
현재까지 알려진 바에 따르면, **AWS EKS / GCP GKE / Azure AKS 공식 문서(트러블슈팅 포함) 어디에도 `net.ipv4.tcp_retries2` 권장값이 명시되어 있지 않습니다**.  
기본값 15를 유지하거나, 클라우드 네이티브 관행으로 **5**로 낮추는 것을 권장하나 반드시 부하 테스트 후 적용하세요. (GKE/AKS는 DaemonSet 필수)

#### 1. 클라우드별 권장값 요약 (표 형식)
| Cloud Provider | Managed k8s | 기본값 | 권장값 (`tcp_retries2`) |
| :--- | :--- | :--- | :--- |
| AWS | EKS | 15 | 공식 없음 (일반 관행: 5) |
| GCP | GKE | 15 | 공식 없음 (일반 관행: 5, sysctl 미지원) |
| Azure | AKS | 15 | 공식 없음 (일반 관행: 5, sysctl 미지원) |

#### 2. 상세 설명 및 튜닝 사유  
기본값 15는 재전송 백오프 지수 증가로 최대 13~30분 대기 → k8s LB Timeout(60~300초) 초과, Pod Eviction 지연 유발. 값을 5로 낮추면 ~15~30초 내 Failover 가능.

#### 3. 공식 문서 URL 및 레퍼런스  
* **AWS EKS:** [Troubleshoot problems with Amazon EKS](https://docs.aws.amazon.com/eks/latest/userguide/troubleshooting.html) (tcp_retries2 미언급)  
* **GCP GKE:** [Customizing node system configuration](https://cloud.google.com/kubernetes-engine/docs/how-to/node-system-config) (지원 sysctl 목록 확인)  
* **Azure AKS:** [Customize Node Configuration](https://learn.microsoft.com/en-us/azure/aks/custom-node-configuration) (지원 목록 확인)  

*(공식 권장값 없으므로 위 문서로 커스터마이징 방법만 확인하세요. 추가 테스트 권장)*

---
**1. [요약 테이블]**

| 벤더       | 권고값                          | 목적/이유                                                                 | 공식 문서 링크 |
|------------|---------------------------------|---------------------------------------------------------------------------|---------------|
| AWS (EKS) | 명시적 권고 없음 (기본값: 15) | EKS 워커 노드에서 TCP 재전송 횟수 튜닝에 대한 공식 권고 미제공. 클라우드 VPC 네트워크 안정성으로 기본값 유지(긴 타임아웃 허용) | https://docs.aws.amazon.com/eks/latest/userguide/best-practices.html |
| GCP (GKE) | 명시적 권고 없음 (기본값: 15) | GKE node system config에서 `net.ipv4.tcp_retries2` 미지원/미권고(다른 `net.ipv4.*`만 예시). 고부하 네트워크 최적화 시 기본값 권장 | https://cloud.google.com/kubernetes-engine/docs/how-to/node-system-config |
| Azure (AKS) | 명시적 권고 없음 (기본값: 15) | AKS custom node config 지원 파라미터 목록에 `tcp_retries2` 미포함(다른 TCP keepalive/fin_timeout 등만 허용). SAP 워크로드 별도(비-K8s) | https://learn.microsoft.com/en-us/azure/aks/custom-node-configuration |

**2. [벤더별 상세 분석]**

- **AWS (EKS)**: 권고값 없음 (Linux 기본 15 유지). 기술적 배경: `net.ipv4.tcp_retries2`는 데이터 패킷 재전송 최대 횟수(기본 15, exponential backoff 적용 시 최대 13분+ 실패 감지 시간). EKS 네트워크 트러블슈팅(504 에러 등)에서는 TCP keepalive만 언급되며, retries2 변경은 공식 미권고. 트러블슈팅 컨텍스트: VPC 안정성 높아 기본값으로 충분; 변경 시 DaemonSet 또는 custom AMI 필요하나 벤더 지원 영향 가능. 정확한 Document URL: https://docs.aws.amazon.com/eks/latest/userguide/best-practices.html (param 미언급 확인).

- **GCP (GKE)**: 권고값 없음 (기본 15). 기술적 배경: Node system config YAML(`linuxConfig.sysctl`)으로 일부 TCP 파라미터(`tcp_rmem`, `tcp_syn_retries`, `tcp_tw_reuse` 등) 튜닝 가능하나 `tcp_retries2`는 지원 목록에 명시되지 않음. 트러블슈팅 컨텍스트: 고트래픽 워크로드( AI/DB)에서 네트워크 스택 최적화 목적이나, 이 파라미터 변경은 node rolling update 유발 및 불안정 위험. 정확한 Document URL: https://cloud.google.com/kubernetes-engine/docs/how-to/node-system-config (sysctl 섹션 전체 검토).

- **Azure (AKS)**: 권고값 없음 (기본 15). 기술적 배경: `linuxosconfig.json`으로 `net.ipv4.tcp_max_syn_backlog`, `tcp_keepalive_*`, `tcp_fin_timeout` 등 허용하나 `tcp_retries2`는 범위 외(미지원). Azure Advisor의 =15 추천은 SAP VM 전용(ACSC failover 재연결 목적)으로 AKS 워커 노드와 무관. 트러블슈팅 컨텍스트: 대규모 동시 연결 시 keepalive 중심 튜닝 권장; unsupported param은 DaemonSet으로만 적용 가능. 정확한 Document URL: https://learn.microsoft.com/en-us/azure/aks/custom-node-configuration (지원 파라미터 테이블 확인).

**3. [결론 및 전문가 제언]**  
현재까지 알려진 바에 따르면, AWS EKS·GCP GKE·Azure AKS 모두 Kubernetes 워커 노드에 대한 `net.ipv4.tcp_retries2` **명시적 권고값을 제공하지 않습니다**. 기본값 15는 클라우드 네트워크의 높은 안정성을 전제로 한 설계이며, 변경(예: 5~8로 낮춤)은 dead connection 감지 속도를 높여 K8s failover/resilience를 개선할 수 있으나 transient failure에 민감해질 수 있습니다.  
**멀티 클라우드 환경 주의점**: 
- DaemonSet으로 노드 전체 일관 적용 (벤더 지원 범위 내)
- **확신할 수 없다**는 부분은 **워크로드별 테스트 필수** (packet loss 환경 시뮬레이션 권장)
- 추가 조사 필요: 특정 앱(Elasticsearch, Db2 등)이나 HA 클러스터 요구사항 확인 후 적용  
변경 전 반드시 staging에서 검증하세요. 추가 질문(예: DaemonSet 예시 YAML)이 있으시면 언제든 말씀해주세요.
