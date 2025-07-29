(SCP V2) Baremetal Active-Active iSCSI 구성 가이드

SCP BM 서버를 위한 Block Storage 는 iSCSI 방식으로 제공하고 있고 기본적으로 iSCSI 의 NIC 구성은 Active-Standby 의 Bonding 으로 구성되어 있습니다. 

I/O 대역폭을 더 크게 사용하기를 원할 경우 iSCSI 용 NIC 을 Active-Active 구성하여 사용할 수 있습니다. 

해당 문서는 SCP V2 환경에서 iSCSI 용 NIC 을 Active-Active 구성하는 상세 방법을 설명합니다. 

2. iSCSI 구성 방식 변경 시 사전 준비 사항

항목: iSCSI 연결 용 추가 IP 준비	

설명: iSCSI A-A 구성을 위해 추가 IP 할당 방법 
→ 동일 프로젝트 내의 BM iSCSI 로 할당된 서브넷(C class) 내의 미사용 IP 사용

비고: IP 충돌 방지를 위해
200 이후 IP(xxx.xx.xx.200~ ) 사용
→ SCP 프로젝트 내의 IP 관리 필요
    (Multi-AZ 환경일 경우 AZ 별로 IP 관리됨)

참고: 
SCP BM 의 V1 대비 V2 변경 사항

iSCSI 용 네트워크는 기존 L2 방식에서 L3 방식으로 변경됨 → Static Route 추가 필요 
iSCSI 용 본딩 bond-iscsi 는 기존 물리 NIC 사용에서 VLAN Tagging 으로 변경됨 → VLAN ID 별 VLAN 디바이스로 설정 필요

