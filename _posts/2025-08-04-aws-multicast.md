---
title: "AWS 환경에서의 Multicast 성능 테스트"
date: 2025-08-04
tags: [aws, network, multicast, tgw, performance, test, iperf]
categories: [Howtos, Benchmark]
---

AWS 환경에서 멀티캐스트(multicast) 성능 테스트를 고려할 때, 먼저 AWS의 기본 지원 한계를 이해해야 합니다. AWS VPC(Virtual Private Cloud) 자체에서는 멀티캐스트가 직접 지원되지 않으며, 이는 IGMP(Internet Group Management Protocol)나 멀티캐스트 라우팅의 부재 때문입니다. 대신, AWS Transit Gateway를 통해 제한적으로 멀티캐스트를 구현할 수 있으며, 이는 VPC 간 또는 외부 네트워크와의 연결에서 유용합니다. 그러나 AWS 문서에 따르면, Transit Gateway의 멀티캐스트는 고대역폭(high bandwidth)이나 극저지연(very low latency) 워크로드를 위한 서비스가 아니며, 약간의 오버헤드가 발생할 수 있습니다. 이는 비판적으로 검증된 사실로, 실제 성능은 네트워크 구성, 인스턴스 유형, 존 간 트래픽 등에 따라 달라질 수 있습니다.

### AWS 멀티캐스트 지원 개요
- **주요 기능**: Transit Gateway를 멀티캐스트 도메인으로 구성하면, 연결된 VPC의 서브넷 간 멀티캐스트 트래픽을 라우팅합니다. IGMPv2를 지원하며, 그룹 멤버십을 동적으로 관리할 수 있습니다.

- **제한 사항**: 최대 MTU(Maximum Transmission Unit)는 8500 bytes로, VPC 간 트래픽에 적용됩니다. 멀티캐스트 도메인당 그룹 수는 제한적이며(예: 1000개 그룹), 스케일링 시 고객 테스트가 필수입니다. AWS는 이 기능을 금융, 미디어, IoT 등에서 추천하지만, 성능 최적화는 사용자 책임입니다.
- **대안**: 컨테이너 환경(예: Amazon ECS)에서 멀티캐스트를 활성화하려면 Transit Gateway와 결합해야 하며, EC2 인스턴스에서 IGMP를 수동 설정합니다.

### 관련 테스트 결과 요약
공개된 테스트 결과는 많지 않으며, 대부분 iPerf 도구를 사용한 기본 벤치마크입니다. 이는 실제 프로덕션 환경과 다를 수 있으니, 비판적으로 검토하세요. 예를 들어, 낮은 대역폭 테스트가 주를 이루며, 고부하 시 손실이 발생할 수 있습니다. 아래 테이블에 주요 결과를 정리했습니다. (데이터는 공개 소스에서 추출; 구체적 숫자가 없는 경우는 '상세 데이터 없음'으로 표시)

| 소스 | 테스트 환경 | 도구 및 설정 | 주요 결과 | 결론 및 비판 |
|------|-------------|-------------|-----------|-------------|
| Edge Cloud 블로그 (2020) | Transit Gateway 멀티캐스트 도메인, EC2 인스턴스 (1 소스, 2 리시버), Ubuntu Linux, Nitro 기반 인스턴스 | iPerf: 소스에서 UDP 트래픽 전송 (224.1.1.1 그룹, TTL 32, 3초 지속, 1초 간격 보고). 리시버: 서버 모드 (-s -u -B 224.1.1.1 -i 1) | 대역폭: 1.05 Mbits/sec, 전송: 386 KBytes (269 datagrams), 지터: 0.068 ms, 손실: 0% (0/269) | 기본 기능 확인 성공. 그러나 저대역폭 테스트로, 고부하 시 성능 저하 가능. AWS 문서와 일치하며, 실제 사용 시 스케일링 테스트 필요. |
| AWS 블로그 (2022, 컨테이너 환경) | Amazon ECS, Transit Gateway 멀티캐스트 도메인, IGMPv2 지원, Docker 컨테이너 (1 소스, 2 리시버) | iPerf: 소스 (-c 233.252.0.5 -u -b 10k -t 86400), 리시버 (-s -u -B 233.252.0.5 -i 1). CloudWatch 로그 모니터링 | 대역폭: 약 10 Kb/sec, datagram 크기: 1470 bytes, 그룹: 233.252.0.5 (멀티캐스트 그룹 4개 확인) | 컨테이너 간 멀티캐스트 성공, 하지만 매우 낮은 대역폭 테스트. 프로덕션에서 지연 증가 가능성 있음. IGMP 설정이 핵심으로, veth 인터페이스에서 V2 확인 필수. |
| CJC (시장 데이터 POC) | AWS Transit Gateway, Kafka 기반 멀티캐스트, 동일/교차 존 테스트 | PCAP 분석 및 지연 측정 (250 Bytes 패킷, 7000 패킷/100ms, 9.6M 패킷/10분) | 동일 존/교차 존 지연 테스트 섹션 존재, 하지만 구체적 latency 숫자나 벤치마크 없음. Transit Gateway 오버헤드 지연 영향 언급 | 지연 영향 확인, 하지만 데이터 부족으로 신뢰성 낮음. Kafka와 결합 시 시장 데이터 배포에 적합하나, 고객별 벤치마크 권장. |
| Reddit 토론 (2022) | Transit Gateway 멀티캐스트, 장기 테스트 | UDP datagram 전송 (8MB 미만 전송률) | datagram 손실 발생 (약 1000 datagrams 손실), 낮은 전송률에서도 문제 | 오버헤드 인해 안정성 문제 지적. AWS 문서의 '저지연 아님'과 일치하나, 특정 구성에서만 발생할 수 있음. 추가 검증 필요. |
| Doppelio 블로그 (2021, IoT) | Transit Gateway, IGMPv2, 온프레미스-AWS 하이브리드 | 멀티캐스트 라우팅 아키텍처 테스트 | 구체적 숫자 없음, 하지만 IoT 장치 자동화 성공 | IoT 시나리오에서 유용하나, 성능 데이터 부족. 하이브리드 환경에서 지연 최소화 가능. |

이 결과들은 주로 기능 검증 수준으로, 고성능 벤치마크(예: 수십 Gbps)는 부족합니다. AWS re:Post에서 언급된 바와 같이, throughput과 latency는 고객 요구사항에 따라 테스트해야 하며, 느리지 않지만 오버헤드가 존재합니다. X(트위터) 검색에서도 유사한 성능 테스트 결과가 거의 없어, 공개 데이터가 제한적임을 확인했습니다.

### 권장 사항과 비판적 검증
- **테스트 방법**: iPerf를 사용해 소스/리시버 설정으로 시작하세요. 예: 리시버에서 `iperf -s -u -B [multicast-group] -i 1`, 소스에서 `iperf -c [multicast-group] -u -T 32 -t [duration] -i 1`. Transit Gateway 멀티캐스트 도메인을 구성하고, ENI(Elastic Network Interface)를 그룹에 등록하세요.
- **주의점**: 결과는 인스턴스 유형(예: Nitro 기반 추천), 존 간 트래픽, 네트워크 보안 그룹에 따라 변동적입니다. 공개 테스트는 편향될 수 있으므로(예: AWS 블로그는 긍정적 측면 강조), 직접 재현 테스트를 통해 검증하세요. 만약 고성능이 필요하다면, AWS Direct Connect나 외부 멀티캐스트 서비스 통합을 고려하세요.
- **결론**: AWS 멀티캐스트는 안정적이지만, 성능은 중간 수준으로 보입니다. 구체적 결과가 부족하니, 귀하의 환경에서 iPerf나 CloudWatch를 활용한 테스트를 추천합니다. 추가 질문이 있으시면 더 자세히 도와드리겠습니다.

---
사용자의 질문에 따라, AWS 환경에서 Placement Group을 활용해 다른 호스트로 인스턴스를 분산 구성하고, 각 호스트에 3개 VM(총 9대 리시버 VM)과 별도 소스 VM을 설정한 멀티리시버 멀티캐스트 성능 테스트 가능 여부를 분석하겠습니다. 이 분석은 AWS 공식 문서와 공개된 사례를 기반으로 하며, 사실 중심으로 설명하겠습니다. 동시에 비판적 관점에서 AWS의 제한 사항을 검증하며, 실제 환경에서 발생할 수 있는 문제를 강조하겠습니다. 이해하기 쉽게 단계별로 설명하겠습니다.

### 가능 여부 요약
네, 가능합니다. AWS Transit Gateway Multicast 기능을 통해 멀티캐스트 트래픽을 여러 리시버로 전송할 수 있으며, Placement Group(특히 Spread 타입)을 사용해 인스턴스를 다른 물리적 호스트에 분산 배치할 수 있습니다. 그러나 AWS Transit Gateway는 고대역폭이나 극저지연 워크로드를 위한 최적화된 서비스가 아니므로, 성능은 기대치에 미치지 않을 수 있습니다. 실제 테스트에서 Placement Group 내 직접 통신보다 지연이 증가할 수 있으며, 고객별로 직접 벤치마크를 권장합니다.

- **왜 가능할까?** Transit Gateway Multicast Domain을 생성하면, 소스 VM에서 전송된 멀티캐스트 패킷을 여러 리시버 VM으로 복제해 배포합니다. 리시버는 ENI(Elastic Network Interface)를 통해 그룹 멤버로 등록되며, 9대 리시버처럼 여러 인스턴스를 지원합니다. Placement Group은 인스턴스 배치만 제어하므로, 멀티캐스트 기능과 독립적으로 작동합니다.
- **비판적 검증**: AWS 문서에서 Placement Group과 멀티캐스트의 직접적 상호작용은 명시되지 않지만, Spread Placement Group은 인스턴스를 다른 하드웨어에 분산시켜 가용성을 높이지만 네트워크 지연을 증가시킬 수 있습니다. 반대로 Cluster Placement Group은 저지연을 제공하지만, 모든 인스턴스를 가까운 호스트에 모으므로 "다른 호스트로 구성" 요구와 맞지 않을 수 있습니다. 공개 사례에서 고대역폭(예: 12Gbps 세션) 테스트 시 TGW가 유니캐스트 기반 복제로 동작해 성능 저하가 발생한다고 지적됩니다.

### 설정 방법 (단계별 가이드)
테스트를 위해 다음 단계를 따르세요. 이는 AWS Console이나 CLI를 사용할 수 있으며, Nitro 기반 EC2 인스턴스(예: t3 또는 m5 시리즈)를 추천합니다. Nitro가 아닌 인스턴스는 Source/Destination Check를 비활성화해야 합니다.

1. **Placement Group 생성**:
   - Spread Placement Group을 생성해 인스턴스를 다른 호스트에 분산합니다. (AWS Console > EC2 > Placement Groups > Create > Spread 선택)
   - 3개의 호스트 그룹으로 생각하면, 각 Spread PG에 3개 VM을 배치할 수 있습니다. 그러나 Spread PG은 그룹당 최대 7개 인스턴스 제한이 있으므로, 여러 PG를 사용하세요. (비판: 여러 PG 간 분산 보장은 없으므로, 실제 호스트 분리가 안 될 수 있음.)

2. **EC2 인스턴스 생성**:
   - 리시버: 9대 VM (각 3대씩 3 PG에 배치). Ubuntu나 Amazon Linux 사용.
   - 소스: 별도 호스트에 1대 VM (다른 PG나 일반 배치).
   - 모두 동일 VPC 또는 연결된 VPC에 배치. Security Group에서 UDP와 IGMP 트래픽 허용 (예: IGMP from 0.0.0.0/32, UDP 포트 5001).

3. **Transit Gateway 및 Multicast Domain 설정**:
   - Transit Gateway 생성 (Multicast 지원 활성화).
   - VPC Attachment 생성 및 Multicast Domain 생성 (IGMPv2 지원 추천으로 Dynamic 설정).
   - 서브넷을 Domain에 어소시에이션 (리시버와 소스 서브넷 모두).
   - 소스 ENI를 Multicast Source로 등록 (CLI: `aws ec2 register-transit-gateway-multicast-group-sources`).
   - 리시버 ENI를 Multicast Group Member로 등록 (CLI: `aws ec2 register-transit-gateway-multicast-group-members` – 그룹 IP 예: 224.1.1.1).

4. **테스트 실행**:
   - 도구: iPerf 사용 (소스: `iperf -c [multicast-group] -u -T 32`, 리시버: `iperf -s -u -B [multicast-group]`).
   - CloudWatch로 throughput, latency 모니터링.
   - 예: 소스에서 UDP 멀티캐스트 전송 시 9대 리시버가 동시에 수신 확인.

### 성능 고려사항 및 제한
아래 테이블에서 주요 성능 요소와 제한을 정리했습니다. 이는 AWS 문서와 사용자 사례를 기반으로 하며, 고부하 시 손실 가능성을 비판적으로 검증했습니다.

| 항목 | 설명 | 성능 영향 | 비판적 검증 |
|------|------|-----------|-------------|
| **Placement Group 타입** | Spread: 다른 호스트 분산. Cluster: 저지연 집중. | Spread에서 지연 증가 (200μs 이상 가능). Cluster에서 10Gbps 제한 내 고성능. | Spread는 가용성 좋지만, 멀티캐스트 지연으로 인해 테스트 시 손실 발생 가능. Cluster가 더 적합하나 "다른 호스트" 요구와 충돌. |
| **리시버 스케일** | 9대처럼 여러 리시버 지원. 그룹당 멤버 제한 (쿼터 확인). | Throughput: 1-12Gbps 세션 가능하나, TGW 오버헤드로 저하. | 고대역폭(12Gbps x 5 세션) 테스트에서 실패 사례 있음. TGW가 유니캐스트 복제 방식으로 동작해 진짜 멀티캐스트 효율 아님. |
| **지연 및 손실** | TGW는 저지연 아님. MTU 8500. | 지터 0.068ms, 손실 0% (저대역 테스트). 고부하 시 패킷 드롭. | 프래그먼테이션 미지원으로 대형 패킷 손실. IGMP JOIN 손실 시 재시도 필요. |
| **기타 제한** | IGMPv2만 지원. Nitro 인스턴스 필수 (소스). | Bandwidth 소비 증가 (복제 방식). | 하이브리드나 Direct Connect 미지원. 성능은 고객 환경依存 – AWS 보장 없음. |

### 권장 사항 및 결론
- **테스트 팁**: 저대역부터 시작해 스케일업. iPerf로 datagram 손실 측정. CloudWatch Metrics로 모니터링.
- **대안**: 고성능 필요 시 Cluster PG 사용하거나, 외부 멀티캐스트 서비스 통합 고려.
- **비판적 결론**: 이 설정은 기능적으로 가능하지만, AWS의 TGW 멀티캐스트는 "중간 수준" 성능으로 평가되며, 공개 벤치마크가 부족합니다. 실제 프로덕션 전에 귀하의 환경에서 반복 테스트를 통해 지연과 손실을 검증하세요. 추가 질문(예: CLI 예시)이 있으시면 말씀해주세요.

---
네, AWS 환경에서 서브넷을 분리하여 소스 VM과 리시버 VM들을 각각 다른 서브넷에 배치하고 멀티캐스트 성능 테스트를 진행하는 것은 가능합니다. 이는 Transit Gateway Multicast 기능의 핵심 설계 덕분으로, 여러 서브넷(심지어 다른 VPC) 간 트래픽을 라우팅할 수 있도록 지원되기 때문입니다. 그러나 실제 구현 시 네트워크 지연 증가나 설정 복잡성 같은 제한 사항이 있을 수 있으므로, 사실 기반으로 자세히 설명하겠습니다. 이해하기 쉽게 단계별로 안내하고, 비판적 관점에서 잠재적 문제를 검증하겠습니다. 이 정보는 AWS 공식 문서와 사용자 사례를 기반으로 하며, 2025년 현재 기준으로 업데이트된 내용을 반영합니다.

### 왜 가능할까? (기본 원리)
- Transit Gateway는 멀티캐스트 도메인(Multicast Domain)을 통해 소스에서 전송된 패킷을 여러 리시버로 복제하고 라우팅합니다. 이 도메인은 VPC attachments의 서브넷을 어소시에이션(association)할 수 있어, 소스와 리시버가 동일 서브넷에 있지 않아도 동작합니다. 예를 들어, 소스 VM을 서브넷 A에, 리시버 VM들을 서브넷 B, C 등에 배치할 수 있습니다.
- 심지어 소스와 리시버가 다른 VPC에 있어도 Transit Gateway를 통해 연결 가능합니다. 이는 미디어 스트리밍이나 금융 데이터 배포 같은 워크로드에서 유용하게 설계된 기능입니다.
- 비판적 검증: 이 기능은 편리하지만, Transit Gateway의 오버헤드(패킷 복제 방식)로 인해 지연이 증가할 수 있습니다. AWS 문서에서 "고대역폭이나 저지연 워크로드에 최적화되지 않음"이라고 명시되어 있듯이, 서브넷 분리 시 네트워크 홉(hop)이 늘어나 throughput 저하나 패킷 손실 위험이 커질 수 있습니다. 실제 사용자 사례(예: re:Post)에서 고부하 테스트 시 이러한 문제가 보고된 바 있으므로, 직접 벤치마크를 통해 검증하세요.

### 설정 방법 (단계별 가이드)
테스트를 위해 AWS Console이나 CLI를 사용하세요. Nitro 기반 EC2 인스턴스(예: m5 또는 t3 시리즈)를 추천하며, Security Group에서 UDP와 IGMP 트래픽을 허용해야 합니다. 아래는 소스(1대)와 리시버(9대)를 각각 다른 서브넷에 배치하는 예시입니다.

1. **VPC와 서브넷 준비**:
   - 동일 VPC 내에서 서브넷을 여러 개 생성(예: 서브넷 A: 소스용, 서브넷 B/C/D: 리시버용). 또는 다른 VPC를 사용해 더 분리할 수 있습니다.
   - 각 서브넷의 Route Table에서 Transit Gateway를 향한 경로를 추가(예: 0.0.0.0/0 -> Transit Gateway ID).

2. **Transit Gateway 생성 및 Multicast Domain 설정**:
   - Transit Gateway 생성 시 Multicast 지원을 활성화합니다.
   - Multicast Domain 생성: Dynamic(IGMPv2 지원) 또는 Static 중 선택. Dynamic을 추천합니다.
   - VPC Attachment 생성: 각 VPC를 Transit Gateway에 attach합니다.
   - 서브넷 어소시에이션: Multicast Domain에 소스 서브넷(A)과 리시버 서브넷(B/C/D)을 추가합니다. CLI 예시: `aws ec2 create-transit-gateway-multicast-domain-association --transit-gateway-multicast-domain-id [domain-id] --transit-gateway-attachment-id [attachment-id] --subnet-id [subnet-id]`. 하나의 서브넷은 하나의 도메인에만 어소시에이션할 수 있습니다.

3. **EC2 인스턴스 배치 및 등록**:
   - 소스 VM: 서브넷 A에 배치.
   - 리시버 VM: 서브넷 B/C/D에 각각 3대씩 배치 (Placement Group과 결합 가능).
   - 소스 등록: 소스 ENI를 Multicast Group Source로 등록. CLI: `aws ec2 register-transit-gateway-multicast-group-sources --transit-gateway-multicast-domain-id [domain-id] --group-ip-address 224.1.1.1 --network-interface-ids [eni-id]`.
   - 리시버 등록: 각 리시버 ENI를 Multicast Group Member로 등록. CLI: `aws ec2 register-transit-gateway-multicast-group-members --transit-gateway-multicast-domain-id [domain-id] --group-ip-address 224.1.1.1 --network-interface-ids [eni-id]`.
   
4. **테스트 실행**:
   - iPerf 도구 사용: 소스에서 `iperf -c 224.1.1.1 -u -T 32 -t 60` (멀티캐스트 그룹으로 UDP 전송).
   - 리시버에서 `iperf -s -u -B 224.1.1.1 -i 1` (수신 모드).
   - CloudWatch로 모니터링: throughput, latency, packet loss 측정.

### 성능 고려사항 및 제한 (비판적 검증 포함)
아래 테이블에서 주요 요소를 정리했습니다. 이는 AWS 문서와 사용자 경험을 기반으로 하며, 서브넷 분리 시 발생할 수 있는 문제를 강조합니다.

| 항목 | 설명 | 성능 영향 | 비판적 검증 |
|------|------|-----------|-------------|
| **서브넷 분리 지원** | 여러 서브넷을 도메인에 어소시에이션 가능. | 지연 최소화 가능하나, TGW 홉 추가로 1-2ms 증가 가능. | 기능적으로 안정적이지만, 서브넷 간 트래픽이 TGW를 경유하므로 오버헤드 발생. 고대역폭(예: 10Gbps 이상) 시 패킷 드롭 보고됨 – AWS가 "저지연 아님"을 명시하듯, 프로덕션 전에 테스트 필수. |
| **스케일링 제한** | 도메인당 서브넷 수 제한(쿼터 확인 필요), 그룹당 멤버 수 제한. | 리시버 9대처럼 소규모는 문제없음, 하지만 수백대 시 성능 저하. | 하나의 서브넷=하나의 도메인 제한으로 인해 복잡한 아키텍처에서 불편. 사용자 사례에서 스케일링 시 IGMP JOIN 지연 발생 가능. |
| **IGMP 및 프로토콜** | IGMPv2 지원으로 동적 멤버십 관리. | 손실률 낮음 (저대역 테스트 기준 0%). | IGMP 쿼리 손실 시 재등록 필요 – 서브넷 분리 시 네트워크 불안정성으로 인해 더 취약. Static 모드는 간단하나 동적 변화에 약함. |
| **기타 제한** | MTU 8500, Direct Connect 미지원. | Bandwidth 소비 증가 (복제 방식). | VPC 간 분리 시 비용 증가 (TGW 데이터 처리 요금). 미디어 워크로드 외 고성능 요구 시 대안(예: 온프레미스 라우터) 고려 필요. |

### 권장 사항 및 결론
- **테스트 팁**: 저대역부터 시작해 지연과 손실을 측정하세요. 서브넷 분리로 인해 발생하는 추가 지연을 CloudWatch Metrics로 확인하고, 필요 시 Cluster Placement Group과 결합해 최적화하세요.
- **대안**: 만약 지연이 문제라면, 모든 인스턴스를 동일 서브넷에 배치하거나 외부 멀티캐스트 솔루션(예: 소프트웨어 라우터)을 고려하세요.
- **비판적 결론**: 이 설정은 기능적으로 가능하고 유연하지만, AWS의 Transit Gateway Multicast는 서브넷 분리 시 성능 오버헤드가 불가피합니다. 공개 사례에서 성공적인 구현이 많지만, 환경에 따라 변동이 크니 귀하의 AWS 계정에서 직접 재현 테스트를 통해 사실을 검증하세요. 추가 질문(예: CLI 스크립트 상세)이 있으시면 말씀해주세요.
