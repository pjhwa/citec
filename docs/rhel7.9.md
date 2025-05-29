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

-------------------------
상세 설치 될 패키지 list:

[root@devops-stg-dbqr yum.repos.d]# cat /etc/*-release
NAME="Red Hat Enterprise Linux Server"
VERSION="7.4 (Maipo)"
ID="rhel"
ID_LIKE="fedora"
VARIANT="Server"
VARIANT_ID="server"
VERSION_ID="7.4"
PRETTY_NAME="Red Hat Enterprise Linux Server 7.4 (Maipo)"
ANSI_COLOR="0;31"
CPE_NAME="cpe:/o:redhat:enterprise_linux:7.4:GA:server"
HOME_URL="https://www.redhat.com/"
BUG_REPORT_URL="https://bugzilla.redhat.com/"

REDHAT_BUGZILLA_PRODUCT="Red Hat Enterprise Linux 7"
REDHAT_BUGZILLA_PRODUCT_VERSION=7.4
REDHAT_SUPPORT_PRODUCT="Red Hat Enterprise Linux"
REDHAT_SUPPORT_PRODUCT_VERSION="7.4"
Red Hat Enterprise Linux Server release 7.4 (Maipo)
Red Hat Enterprise Linux Server release 7.4 (Maipo)
[root@devops-stg-dbqr yum.repos.d]# cat /etc/yum.repos.d/branch.repo
[LocalRepo_BaseOS]
baseurl = http://182.197.136.246/7/base/
enabled = 1
gpgcheck = 0
metadata_expire = -1
name = LocalRepo_BaseOS

[root@devops-stg-dbqr yum.repos.d]#
[root@devops-stg-dbqr yum.repos.d]#
[root@devops-stg-dbqr yum.repos.d]# yum --assumeno update

-------------------------------------
Dependencies Resolved


============================================================================================================================================================================================
 Package                                                    Arch                       Version                                                   Repository                            Size
============================================================================================================================================================================================
Installing:
 grub2                                                      x86_64                     1:2.02-0.87.el7_9.14                                      LocalRepo_BaseOS                      35 k
     replacing  grub2.x86_64 1:2.02-0.64.el7
 grub2-tools                                                x86_64                     1:2.02-0.87.el7_9.14                                      LocalRepo_BaseOS                     1.8 M
     replacing  grub2-tools.x86_64 1:2.02-0.64.el7
 grub2-tools-extra                                          x86_64                     1:2.02-0.87.el7_9.14                                      LocalRepo_BaseOS                     1.0 M
     replacing  grub2-tools.x86_64 1:2.02-0.64.el7
 grub2-tools-minimal                                        x86_64                     1:2.02-0.87.el7_9.14                                      LocalRepo_BaseOS                     178 k
     replacing  grub2-tools.x86_64 1:2.02-0.64.el7
 iwl7260-firmware                                           noarch                     25.30.13.0-83.el7_9                                       LocalRepo_BaseOS                      14 M
     replacing  iwl7265-firmware.noarch 22.0.7.0-56.el7
 subscription-manager-rhsm                                  x86_64                     1.24.54-1.el7_9                                           LocalRepo_BaseOS                     336 k
     replacing  python-rhsm.x86_64 1.19.9-1.el7
 subscription-manager-rhsm-certificates                     x86_64                     1.24.54-1.el7_9                                           LocalRepo_BaseOS                     244 k
     replacing  python-rhsm-certificates.x86_64 1.19.9-1.el7
Updating:
 GeoIP                                                      x86_64                     1.5.0-14.el7                                              LocalRepo_BaseOS                     1.5 M
 NetworkManager                                             x86_64                     1:1.18.8-2.el7_9                                          LocalRepo_BaseOS                     1.9 M
 NetworkManager-config-server                               noarch                     1:1.18.8-2.el7_9                                          LocalRepo_BaseOS                     151 k
 NetworkManager-libnm                                       x86_64                     1:1.18.8-2.el7_9                                          LocalRepo_BaseOS                     1.7 M
 NetworkManager-team                                        x86_64                     1:1.18.8-2.el7_9                                          LocalRepo_BaseOS                     165 k
 NetworkManager-tui                                         x86_64                     1:1.18.8-2.el7_9                                          LocalRepo_BaseOS                     329 k
 acl                                                        x86_64                     2.2.51-15.el7                                             LocalRepo_BaseOS                      82 k
 alsa-lib                                                   x86_64                     1.1.8-1.el7                                               LocalRepo_BaseOS                     425 k
 audit                                                      x86_64                     2.8.5-4.el7                                               LocalRepo_BaseOS                     255 k
 audit-libs                                                 x86_64                     2.8.5-4.el7                                               LocalRepo_BaseOS                     102 k
 avahi-libs                                                 x86_64                     0.6.31-20.el7                                             LocalRepo_BaseOS                      62 k
 bash                                                       x86_64                     4.2.46-35.el7_9                                           LocalRepo_BaseOS                     1.0 M
 bind-libs-lite                                             x86_64                     32:9.11.4-26.P2.el7_9.16                                  LocalRepo_BaseOS                     1.1 M
 bind-license                                               noarch                     32:9.11.4-26.P2.el7_9.16                                  LocalRepo_BaseOS                      92 k
 binutils                                                   x86_64                     2.27-44.base.el7_9.1                                      LocalRepo_BaseOS                     5.9 M
 biosdevname                                                x86_64                     0.7.3-2.el7                                               LocalRepo_BaseOS                      38 k
 ca-certificates                                            noarch                     2023.2.60_v7.0.306-72.el7_9                               LocalRepo_BaseOS                     923 k
 chkconfig                                                  x86_64                     1.7.6-1.el7                                               LocalRepo_BaseOS                     182 k
 coreutils                                                  x86_64                     8.22-24.el7_9.2                                           LocalRepo_BaseOS                     3.3 M
 cpio                                                       x86_64                     2.11-28.el7                                               LocalRepo_BaseOS                     211 k
 cronie                                                     x86_64                     1.4.11-25.el7_9                                           LocalRepo_BaseOS                      92 k
 cronie-anacron                                             x86_64                     1.4.11-25.el7_9                                           LocalRepo_BaseOS                      36 k
 cups-libs                                                  x86_64                     1:1.6.3-52.el7_9                                          LocalRepo_BaseOS                     359 k
 curl                                                       x86_64                     7.29.0-59.el7_9.2                                         LocalRepo_BaseOS                     271 k
 cyrus-sasl-lib                                             x86_64                     2.1.26-24.el7_9                                           LocalRepo_BaseOS                     156 k
 dbus                                                       x86_64                     1:1.10.24-15.el7                                          LocalRepo_BaseOS                     245 k
 dbus-libs                                                  x86_64                     1:1.10.24-15.el7                                          LocalRepo_BaseOS                     169 k
 desktop-file-utils                                         x86_64                     0.23-2.el7                                                LocalRepo_BaseOS                      67 k
 device-mapper                                              x86_64                     7:1.02.170-6.el7_9.5                                      LocalRepo_BaseOS                     297 k
 device-mapper-event                                        x86_64                     7:1.02.170-6.el7_9.5                                      LocalRepo_BaseOS                     192 k
 device-mapper-event-libs                                   x86_64                     7:1.02.170-6.el7_9.5                                      LocalRepo_BaseOS                     192 k
 device-mapper-libs                                         x86_64                     7:1.02.170-6.el7_9.5                                      LocalRepo_BaseOS                     325 k
 device-mapper-persistent-data                              x86_64                     0.8.5-3.el7_9.2                                           LocalRepo_BaseOS                     423 k
 dhclient                                                   x86_64                     12:4.2.5-83.el7_9.2                                       LocalRepo_BaseOS                     286 k
 dhcp-common                                                x86_64                     12:4.2.5-83.el7_9.2                                       LocalRepo_BaseOS                     177 k
 dhcp-libs                                                  x86_64                     12:4.2.5-83.el7_9.2                                       LocalRepo_BaseOS                     133 k
 diffutils                                                  x86_64                     3.3-6.el7_9                                               LocalRepo_BaseOS                     322 k
 dmidecode                                                  x86_64                     1:3.2-5.el7_9.1                                           LocalRepo_BaseOS                      82 k
 dracut                                                     x86_64                     033-572.el7                                               LocalRepo_BaseOS                     329 k
 dracut-config-rescue                                       x86_64                     033-572.el7                                               LocalRepo_BaseOS                      61 k
 
