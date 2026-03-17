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
