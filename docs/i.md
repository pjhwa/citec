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

5. iSCSI 파라미터 설정 
- iSCSI 세션을 최적화 하기 위한 파라미터 설정 후 iscsid 서비스 재가동
```
# vi /etc/iscsi/iscsid.conf

..중략.. 


# ********
# Timeouts
# ********
#
node.session.timeo.replacement_timeout = 5

# Time interval to wait for on connection before sending a ping.

node.conn[0].timeo.noop_out_interval = 5

# To specify the time to wait for a Nop-out response before failing
# the connection, edit this line. Failing the connection will
# cause IO to be failed back to the SCSI layer. If using dm-multipath
# this will cause the IO to be failed to the multipath layer.
node.conn[0].timeo.noop_out_timeout = 5

################################
# session and device queue depth
################################

# To control how many commands the session will queue set
# node.session.cmds_max to an integer between 2 and 2048 that is also
# a power of 2. The default is 128.
#node.session.cmds_max = 128
node.session.cmds_max = 2048

# To control the device's queue depth set node.session.queue_depth
# to a value between 1 and 1024. The default is 32.
#node.session.queue_depth = 32
node.session.queue_depth = 64

# For multipath configurations, you may want more than one session to be
# created on each iface record.  If node.session.nr_sessions is greater
# than 1, performing a 'login' for that node will ensure that the
# appropriate number of sessions is created.
node.session.nr_sessions = 1
#node.session.nr_sessions = 2
```
                                                      
6. iSCSI A-A 네트워크 설정 
  - SCP BM 서버의 초기 프로비전 시 세팅 되었던 A-S Bonding 구성을 삭제하고 A-A 구성으로 변경

  - VLAN Tagging 을 사용하므로 vlan 타입 및 vlan 디바이스로 설정함 

  - iSCSI NIC의 MTU 는 9000 으로 설정 및 확인

1. 기존 bond-iscsi 관련 디바이스 삭제
```
# nmcli con down "Vlan bond-iscsi.3706"

# nmcli con down "Bond bond-iscsi"

# nmcli con del "Vlan bond-iscsi.3706"
# nmcli con del "Bond bond-iscsi"
```


2. A-A 에 사용할 vlan NIC 설정
```
# nmcli con add type vlan con-name "ens5f0-isc.3706" ifname ens5f0-isc.3706 vlan.parent ens5f0 vlan.id 3706 ipv4.addresses 172.30.4.2/24 ipv4.method manual ipv6.method ignore 
# nmcli con add type vlan con-name "ens6f1-isc.3706" ifname ens6f1-isc.3706 vlan.parent ens6f1 vlan.id 3706 ipv4.addresses 172.30.4.202/24 ipv4.method manual ipv6.method ignore 

# nmcli con mod "ens5f0-isc.3706" mtu 9000
# nmcli con mod "ens6f1-isc.3706" mtu 9000

# ip link set mtu 9000 dev ens5f0
# ip link set mtu 9000 dev ens6f1

# nmcli con show
```


3. 스토리지 통신을 위한 static route 추가 
```
# cp /etc/sysconfig/network-scripts/backup/route-bond-iscsi /etc/sysconfig/network-scripts/backup/route-ens5f0-isc.3706 

# cp /etc/sysconfig/network-scripts/backup/route-bond-iscsi /etc/sysconfig/network-scripts/backup/route-ens6f1-isc.3706 

# systemctl restart NetworkManager



  - 수동으로 추가할 경우 다음 커맨드 수행

# route add -net 172.18.88.0 netmask 255.255.254.0 gw 172.30.4.1 dev ens5f0-isc.3706
# route add -net 172.18.88.0 netmask 255.255.254.0 gw 172.30.4.1 dev ens6f1-isc.3706
```


4. 라우팅 및 Network 설정 상태 확인
```
# ip a

..중략.. 

11: ens7f1: <BROADCAST,MULTICAST,SLAVE,UP,LOWER_UP> mtu 9000 qdisc mq master bond-srv state UP group default qlen 1000
    link/ether ec:e7:a7:0d:ab:34 brd ff:ff:ff:ff:ff:ff permaddr ec:e7:a7:0d:ac:f1
    altname enp201s0f1
12: ens5f0-isc.3706@ens5f0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 9000 qdisc noqueue state UP group default qlen 1000
    link/ether ec:e7:a7:0d:ac:f0 brd ff:ff:ff:ff:ff:ff
    inet 172.30.4.2/24 brd 172.30.4.255 scope global noprefixroute ens5f0-isc.3706
       valid_lft forever preferred_lft forever
    inet6 fe80::eee7:a7ff:fe0d:acf0/64 scope link 
       valid_lft forever preferred_lft forever
13: ens6f1-isc.3706@ens6f1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 9000 qdisc noqueue state UP group default qlen 1000
    link/ether ec:e7:a7:0d:a2:b1 brd ff:ff:ff:ff:ff:ff
    inet 172.30.4.202/24 brd 172.30.4.255 scope global noprefixroute ens6f1-isc.3706
       valid_lft forever preferred_lft forever
    inet6 fe80::eee7:a7ff:fe0d:a2b1/64 scope link 
       valid_lft forever preferred_lft forever



# route

Kernel IP routing table
Destination     Gateway         Genmask         Flags Metric Ref    Use Iface
default         _gateway        0.0.0.0         UG    403    0        0 bond-srv.641
..중략.. 
172.19.88.0     172.30.4.1      255.255.254.0   UG    400    0        0 ens5f0-isc.3706
172.19.88.0     172.30.4.1      255.255.254.0   UG    401    0        0 ens6f1-isc.3706
172.30.4.0      0.0.0.0         255.255.255.0   U     400    0        0 ens5f0-isc.3706
172.30.4.0      0.0.0.0         255.255.255.0   U     401    0        0 ens6f1-isc.3706


.. 생략.. 
```

7. 커널 파라미터 설정 
- iSCSI 트래픽이 2개의 NIC 별로 통신이 되도록 커널 파라미터 설정

- iSCSI 서비스를 위한 NIC 에 해당하는 커널 파라미터만 설정함 (VLAN NIC 에 커널 파라미터 설정해야 하고 VLAN ID는 "/" 구분 함)
```
# vi /etc/sysctl.d/iscsi-aa.conf 

net.ipv4.conf.ens5f0.rp_filter=2  
net.ipv4.conf.ens5f0.arp_ignore=1
net.ipv4.conf.ens5f0.arp_announce=2

net.ipv4.conf.ens6f1.rp_filter=2
net.ipv4.conf.ens6f1.arp_ignore=1
net.ipv4.conf.ens6f1.arp_announce=2


net.ipv4.conf.ens5f0-isc/3706.rp_filter=2 
net.ipv4.conf.ens5f0-isc/3706.arp_ignore=1
net.ipv4.conf.ens5f0-isc/3706.arp_announce=2

net.ipv4.conf.ens6f1-isc/3706.rp_filter=2
net.ipv4.conf.ens6f1-isc/3706.arp_ignore=1
net.ipv4.conf.ens6f1-isc/3706.arp_announce=2

# sysctl -p /etc/sysctl.d/iscsi-aa.conf
```
8. iSCSI 용 NIC 별 네트워크 확인
  - VLAN NIC 별로 스토리지의 iSCSI Node 로 Ping 이 되는지 확인 
```
# NIC 별로 스토리지 IP 로 ping 정상 여부 확인 

# ping -I ens5f0-isc.3706 <iSCSI Node IP1>

# ping -I ens6f1-isc.3706 <iSCSI Node IP1>



# ping -I ens5f0-isc.3706 <iSCSI Node IP2>

# ping -I ens6f1-isc.3706 <iSCSI Node IP2>
```
9. iSCSI Interface 설정 
  - iSCSI 세션이 NIC 별로 연결되도록 2개의 iSCSI Interface 를 설정함

  - iSCSI 용 2 개 VLAN NIC 확인 후 iface.net_ifacename 으로 설정 함 
     (SCP V1 에서는 iface.hwaddress  로 설정했으나 물리 NIC 과 VLAN NIC 의 MAC Address 가 동일하므로 NIC 이름으로 설정함)
```
# iscsiadm -m iface -I iscsi-ens5f0-isc.3706-o new

# iscsiadm -m iface -I iscsi-ens6f1-isc.3706-o new



# iscsiadm -m iface -I iscsi-ens5f0-isc.3706 -o update -n iface.net_ifacename -v ens5f0-isc.3706 -n iface.ipaddress -v 172.30.4.2/24 -n iface.vlan_id -v 3706   
# iscsiadm -m iface -I iscsi-ens6f1-isc.3706 -o update -n iface.net_ifacename -v ens6f1-isc.3706 -n iface.ipaddress -v 172.30.4.202/24 -n iface.vlan_id -v 3706

  (*참고:  iface.net_ifacename 만 설정해도 문제 없고 iface.ipaddress, iface.vlan_id 값은 부가적인 정보임)


# iscsiadm -m iface
```
