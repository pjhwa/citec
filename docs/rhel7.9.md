SCP 공공 풀 CSAP 인증을 위해 RHEL 7 버전의 업그레이드 항목이 문제점으로 검출되었으나, 
ELS 계약으로 인한 PASS처리를 하는 과정에서 모든 OS의 버전을 RHEL7.9로 올려야 하는 것이 확인되었습니다. 
ELS 지원을 받기위해서는 RHEL 7.9로 설치가 되어있어야 하기때문에 마이너 버전의 업데이트 작업을 계획중 입니다. 

특정 3rd-party application 을 사용하는 OS는 크게 문제가 없으나,  DB/HA를 사용하는 OS에 대한 확인 요청이 있었습니다. 

■ RHEL 7.9 Update 필수 패키지 
RHEL7 레포지토리 :
rhel-7-server-rpms - RHEL7 OS (필수)

이에따라 몇몇 DB 서버에서 위의 필수 repository를 구성하고 설치 패키지 Dependancy를 점검 해 보았습니다. 

#yum --assumeno update

상세 설치 될 패키지 list는 OS 별로 첨부 하였으며, 
아래와 같이 DB가 설치되어있는 환경에서 위 패키지 업데이트로 DB서비스에 영향이 있을 지 검토 요청 드립니다. 
테스트를 해 보면 문제는 없을 듯 한데, 라이센스라던가 부서 내 담당자의 구분이 세분화 되어있어 한번에 확인이 어렵기도하여 
CI-TEC분들의 의견을 여쭤보게 되었습니다. 
확인 중 문의사항 있으시면 편하게 연락 부탁드립니다. 

- 주요 패키지 (쿼럼서버 제외하고 전부 동일)
---- DB : postgresql ----
[root@devops-stg-console-db01 ~]# ps -ef | grep postgresql
root     10704  9668  0 10:12 pts/0    00:00:00 grep --color=auto postgresql
postgres 20550     1  0 Apr14 ?        00:24:21 /usr/pgsql-13/bin/postgres -D /data/postgres/data/pg -c config_file=/data/postgres/data/pg/postgresql.conf
[root@devops-stg-console-db01 ~]# rpm -qa | grep postgres
postgresql13-server-13.20-1PGDG.rhel7.x86_64
postgresql13-13.20-1PGDG.rhel7.x86_64
postgresql13-libs-13.20-1PGDG.rhel7.x86_64
postgresql13-contrib-13.20-1PGDG.rhel7.x86_64

---- replication : DRBD ----
[root@devops-stg-console-db01 ~]# drbdadm status
drbd_res01 role:Primary
  disk:UpToDate
  devops-stg-console-db02 role:Secondary
    peer-disk:UpToDate

[root@devops-stg-console-db01 ~]# rpm -qa | grep drbd
kmod-drbd90-9.0.22-3.el7_9.elrepo.x86_64
drbd90-utils-9.0.0-1.el7.elrepo.x86_64

---- HA : pacemaker ----
[root@devops-stg-console-db01 ~]# pcs status
Cluster name: devopsstg
Stack: corosync
Current DC: devops-stg-console-db02 (version 1.1.18-11.el7_5.2-2b07d5c5a9) - partition with quorum
Last updated: Thu May 29 10:13:51 2025
Last change: Mon Apr 14 17:50:41 2025 by root via cibadmin on devops-stg-console-db02

2 nodes configured
7 resources configured

Online: [ devops-stg-console-db01 devops-stg-console-db02 ]

Full list of resources:
 mysbd01        (stonith:fence_sbd):    Started devops-stg-console-db01
 mysbd02        (stonith:fence_sbd):    Started devops-stg-console-db02
 Master/Slave Set: DataSync [drbd_res]
     Masters: [ devops-stg-console-db01 ]
     Slaves: [ devops-stg-console-db02 ]
 Resource Group: HA-GROUP
     Filesystem (ocf::heartbeat:Filesystem):    Started devops-stg-console-db01
     DB (ocf::heartbeat:pgsql): Started devops-stg-console-db01
     VIP        (ocf::heartbeat:IPaddr2):       Started devops-stg-console-db01

Daemon Status:
  corosync: active/disabled
  pacemaker: active/disabled
  pcsd: active/enabled
  sbd: active/enabled

[root@devops-stg-console-db01 ~]# rpm -qa | grep pcs
pcs-0.9.162-5.el7.centos.1.x86_64
[root@devops-stg-console-db01 ~]# rpm -qa | grep pacemaker
pacemaker-cluster-libs-1.1.18-11.el7_5.2.x86_64
pacemaker-cli-1.1.18-11.el7_5.2.x86_64
pacemaker-1.1.18-11.el7_5.2.x86_64
pacemaker-libs-1.1.18-11.el7_5.2.x86_64

