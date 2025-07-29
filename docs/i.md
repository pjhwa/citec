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

3. BM 서버의 초기 iSCSI NIC 구성 확인 
  - SCP BM 서버는 기본적으로 iSCSI 연결을 위한 NIC 구성은 Active-Standby Bonding 구성으로 제공

  - Bond iSCSI(bond-iscsi) 의 NIC 정보 확인 : 아래의 경우 ens5f0, ens6f1 로 구성되어 있고 VLAN ID  확인함 

  - iSCSI 스토리지 연결 용 IP 확인 : 아래의 경우 172.30.4.2/24
```
# ip a

..중략 ..
16: bond-srv.3706@bond-srv: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 9000 qdisc noqueue state UP group default qlen 1000
    link/ether ec:e7:a7:0d:ab:34 brd ff:ff:ff:ff:ff:ff
    inet 172.31.4.2/24 brd 172.31.4.255 scope global noprefixroute bond-srv.3706
       valid_lft forever preferred_lft forever
17: bond-iscsi: <BROADCAST,MULTICAST,MASTER,UP,LOWER_UP> mtu 9000 qdisc noqueue state UP group default qlen 1000
    link/ether ec:e7:a7:0d:ac:f0 brd ff:ff:ff:ff:ff:ff
    inet6 fe80::eee7:a7ff:fe0d:acf0/64 scope link 
       valid_lft forever preferred_lft forever
18: bond-iscsi.3706@bond-iscsi: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 9000 qdisc noqueue state UP group default qlen 1000
    link/ether ec:e7:a7:0d:ac:f0 brd ff:ff:ff:ff:ff:ff
    inet 172.30.4.2/24 brd 172.30.4.255 scope global noprefixroute bond-iscsi.3706
       valid_lft forever preferred_lft forever



# cat /proc/net/bonding/bond-iscsi

Ethernet Channel Bonding Driver: v3.7.1 (April 27, 2011)

Bonding Mode: fault-tolerance (active-backup)
Primary Slave: None
Currently Active Slave: ens5f0
MII Status: up
MII Polling Interval (ms): 100
Up Delay (ms): 0
Down Delay (ms): 0
Peer Notification Delay (ms): 0

Slave Interface: ens5f0
MII Status: up
Speed: 25000 Mbps
Duplex: full
Link Failure Count: 0
Permanent HW addr: ec:e7:a7:0d:ac:f0
Slave queue ID: 0

Slave Interface: ens6f1
MII Status: up
Speed: 25000 Mbps
Duplex: full
Link Failure Count: 0
Permanent HW addr: ec:e7:a7:0d:a2:b1
Slave queue ID: 0
```

4. 구성 전 사전 작업 
  - /etc/sysconfig/network-scripts/ifcfg-bond-iscsi*, /etc/sysconfig/network-scripts/route-bond-iscsi*  파일 등을 /etc/sysconfig/network-scripts/backup  디렉토리에 백업 

  - 서버에 Block Storage 가 추가되어 있다면 마운트 상태 확인 및 iSCSI 로그아웃 

  - cron 에 작업 시간 동안 수행되는 JOB 이 있을 경우 주석 처리

- crontab 확인 <-------------------------- 자주 실행되는 스토리지 작업이 있을 경우 작업 시간 동안 주석처리 
```
# crontab -l 

- umount 
# umount <FS  NAME>

- iSCSI logout 

# iscsiadm -m session   <-------------------------- 연결된 iSCSI Node 정보 확인

tcp: [1] 172.19.88.15:3260,1035 iqn.1992-08.com.netapp:sn.7fefe00e7bf111efa3f0d039eab8d501:vs.4 (non-flash)
tcp: [12] 172.19.88.16:3260,1041 iqn.1992-08.com.netapp:sn.7fefe00e7bf111efa3f0d039eab8d501:vs.4 (non-flash)

# iscsiadm -m node -p <iSCSI Node IP1> -u            <----------------  위의 경우 iSCSI Node IP1 : 172.19.88.15
# iscsiadm -m node -p <iSCSI Node IP2> -u            <----------------  위의 경우 iSCSI Node IP2 : 172.19.88.16

# iscsiadm -m session
```
