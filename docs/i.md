(SCP V2) Baremetal Active-Active iSCSI 구성 가이드

SCP BM 서버를 위한 Block Storage 는 iSCSI 방식으로 제공하고 있고 기본적으로 iSCSI 의 NIC 구성은 Active-Standby 의 Bonding 으로 구성되어 있습니다. 

I/O 대역폭을 더 크게 사용하기를 원할 경우 iSCSI 용 NIC 을 Active-Active 구성하여 사용할 수 있습니다. 

해당 문서는 SCP V2 환경에서 iSCSI 용 NIC 을 Active-Active 구성하는 상세 방법을 설명합니다. 


