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
dracut-network                                             x86_64                     033-572.el7                                               LocalRepo_BaseOS                     103 k
 e2fsprogs                                                  x86_64                     1.42.9-19.el7                                             LocalRepo_BaseOS                     701 k
 e2fsprogs-libs                                             x86_64                     1.42.9-19.el7                                             LocalRepo_BaseOS                     168 k
 ebtables                                                   x86_64                     2.0.10-16.el7                                             LocalRepo_BaseOS                     123 k
 elfutils-default-yama-scope                                noarch                     0.176-5.el7                                               LocalRepo_BaseOS                      33 k
 elfutils-libelf                                            x86_64                     0.176-5.el7                                               LocalRepo_BaseOS                     195 k
 elfutils-libs                                              x86_64                     0.176-5.el7                                               LocalRepo_BaseOS                     291 k
 emacs-filesystem                                           noarch                     1:24.3-23.el7_9.1                                         LocalRepo_BaseOS                      58 k
 ethtool                                                    x86_64                     2:4.8-10.el7                                              LocalRepo_BaseOS                     127 k
 expat                                                      x86_64                     2.1.0-15.el7_9                                            LocalRepo_BaseOS                      83 k
 file                                                       x86_64                     5.11-37.el7                                               LocalRepo_BaseOS                      57 k
 file-libs                                                  x86_64                     5.11-37.el7                                               LocalRepo_BaseOS                     340 k
 filesystem                                                 x86_64                     3.2-25.el7                                                LocalRepo_BaseOS                     1.0 M
 findutils                                                  x86_64                     1:4.5.11-6.el7                                            LocalRepo_BaseOS                     559 k
 firewalld                                                  noarch                     0.6.3-13.el7_9                                            LocalRepo_BaseOS                     449 k
 firewalld-filesystem                                       noarch                     0.6.3-13.el7_9                                            LocalRepo_BaseOS                      51 k
 freetype                                                   x86_64                     2.8-14.el7_9.1                                            LocalRepo_BaseOS                     380 k
 fuse                                                       x86_64                     2.9.2-11.el7                                              LocalRepo_BaseOS                      86 k
 fuse-libs                                                  x86_64                     2.9.2-11.el7                                              LocalRepo_BaseOS                      93 k
 gettext                                                    x86_64                     0.19.8.1-3.el7_9                                          LocalRepo_BaseOS                     1.0 M
 gettext-libs                                               x86_64                     0.19.8.1-3.el7_9                                          LocalRepo_BaseOS                     502 k
 glib2                                                      x86_64                     2.56.1-9.el7_9                                            LocalRepo_BaseOS                     2.5 M
 gnupg2                                                     x86_64                     2.0.22-5.el7_5                                            LocalRepo_BaseOS                     1.5 M
 gnutls                                                     x86_64                     3.3.29-9.el7_6                                            LocalRepo_BaseOS                     681 k
 gobject-introspection                                      x86_64                     1.56.1-1.el7                                              LocalRepo_BaseOS                     241 k
 grub2-common                                               noarch                     1:2.02-0.87.el7_9.14                                      LocalRepo_BaseOS                     733 k
 grub2-pc                                                   x86_64                     1:2.02-0.87.el7_9.14                                      LocalRepo_BaseOS                      35 k
 grub2-pc-modules                                           noarch                     1:2.02-0.87.el7_9.14                                      LocalRepo_BaseOS                     861 k
 grubby                                                     x86_64                     8.28-26.el7                                               LocalRepo_BaseOS                      71 k
 gssproxy                                                   x86_64                     0.7.0-30.el7_9                                            LocalRepo_BaseOS                     111 k
 gzip                                                       x86_64                     1.5-11.el7_9                                              LocalRepo_BaseOS                     130 k
 hostname                                                   x86_64                     3.13-3.el7_7.1                                            LocalRepo_BaseOS                      17 k
 hwdata                                                     x86_64                     0.252-9.7.el7                                             LocalRepo_BaseOS                     2.5 M
 info                                                       x86_64                     5.1-5.el7                                                 LocalRepo_BaseOS                     233 k
 initscripts                                                x86_64                     9.49.53-1.el7_9.1                                         LocalRepo_BaseOS                     440 k
 iproute                                                    x86_64                     4.11.0-30.el7                                             LocalRepo_BaseOS                     805 k
 iprutils                                                   x86_64                     2.4.17.1-3.el7_7                                          LocalRepo_BaseOS                     243 k
 ipset                                                      x86_64                     7.1-1.el7                                                 LocalRepo_BaseOS                      39 k
 ipset-libs                                                 x86_64                     7.1-1.el7                                                 LocalRepo_BaseOS                      64 k
 iptables                                                   x86_64                     1.4.21-35.el7                                             LocalRepo_BaseOS                     432 k
 irqbalance                                                 x86_64                     3:1.0.7-12.el7                                            LocalRepo_BaseOS                      45 k
 iwl100-firmware                                            noarch                     39.31.5.1-83.el7_9                                        LocalRepo_BaseOS                     156 k
 iwl1000-firmware                                           noarch                     1:39.31.5.1-83.el7_9                                      LocalRepo_BaseOS                     215 k
 iwl105-firmware                                            noarch                     18.168.6.1-83.el7_9                                       LocalRepo_BaseOS                     235 k
 iwl135-firmware                                            noarch                     18.168.6.1-83.el7_9                                       LocalRepo_BaseOS                     243 k
 iwl2000-firmware                                           noarch                     18.168.6.1-83.el7_9                                       LocalRepo_BaseOS                     237 k
 iwl2030-firmware                                           noarch                     18.168.6.1-83.el7_9                                       LocalRepo_BaseOS                     246 k
 iwl3160-firmware                                           noarch                     25.30.13.0-83.el7_9                                       LocalRepo_BaseOS                     1.5 M
 iwl3945-firmware                                           noarch                     15.32.2.9-83.el7_9                                        LocalRepo_BaseOS                      97 k
 iwl4965-firmware                                           noarch                     228.61.2.24-83.el7_9                                      LocalRepo_BaseOS                     110 k
 iwl5000-firmware                                           noarch                     8.83.5.1_1-83.el7_9                                       LocalRepo_BaseOS                     290 k
 iwl5150-firmware                                           noarch                     8.24.2.2-83.el7_9                                         LocalRepo_BaseOS                     153 k
 iwl6000-firmware                                           noarch                     9.221.4.1-83.el7_9                                        LocalRepo_BaseOS                     172 k
 iwl6000g2a-firmware                                        noarch                     18.168.6.1-83.el7_9                                       LocalRepo_BaseOS                     305 k
 iwl6000g2b-firmware                                        noarch                     18.168.6.1-83.el7_9                                       LocalRepo_BaseOS                     305 k
 iwl6050-firmware                                           noarch                     41.28.5.1-83.el7_9                                        LocalRepo_BaseOS                     242 k
 kbd                                                        x86_64                     1.15.5-16.el7_9                                           LocalRepo_BaseOS                     348 k
 kbd-legacy                                                 noarch                     1.15.5-16.el7_9                                           LocalRepo_BaseOS                     466 k
 kbd-misc                                                   noarch                     1.15.5-16.el7_9                                           LocalRepo_BaseOS                     1.4 M
 kmod                                                       x86_64                     20-28.el7                                                 LocalRepo_BaseOS                     123 k
 kmod-libs                                                  x86_64                     20-28.el7                                                 LocalRepo_BaseOS                      51 k
 kpartx                                                     x86_64                     0.4.9-136.el7_9                                           LocalRepo_BaseOS                      81 k
 krb5-libs                                                  x86_64                     1.15.1-55.el7_9                                           LocalRepo_BaseOS                     810 k
 less                                                       x86_64                     458-10.el7_9                                              LocalRepo_BaseOS                     120 k
 libacl                                                     x86_64                     2.2.51-15.el7                                             LocalRepo_BaseOS                      27 k
 libattr                                                    x86_64                     2.4.46-13.el7                                             LocalRepo_BaseOS                      18 k
 libbasicobjects                                            x86_64                     0.1.1-32.el7                                              LocalRepo_BaseOS                      26 k
 libblkid                                                   x86_64                     2.23.2-65.el7_9.1                                         LocalRepo_BaseOS                     183 k
 libcap                                                     x86_64                     2.22-11.el7                                               LocalRepo_BaseOS                      47 k
 libcgroup                                                  x86_64                     0.41-21.el7                                               LocalRepo_BaseOS                      66 k
 libcollection                                              x86_64                     0.7.0-32.el7                                              LocalRepo_BaseOS                      42 k
 libcom_err                                                 x86_64                     1.42.9-19.el7                                             LocalRepo_BaseOS                      42 k
 libcroco                                                   x86_64                     0.6.12-6.el7_9                                            LocalRepo_BaseOS                     105 k
 libcurl                                                    x86_64                     7.29.0-59.el7_9.2                                         LocalRepo_BaseOS                     223 k
 libdb                                                      x86_64                     5.3.21-25.el7                                             LocalRepo_BaseOS                     719 k
 libdb-utils                                                x86_64                     5.3.21-25.el7                                             LocalRepo_BaseOS                     133 k
 libdrm                                                     x86_64                     2.4.97-2.el7                                              LocalRepo_BaseOS                     151 k
 libfastjson                                                x86_64                     0.99.4-3.el7                                              LocalRepo_BaseOS                      27 k
 libffi                                                     x86_64                     3.0.13-19.el7                                             LocalRepo_BaseOS                      30 k
 libgcc                                                     x86_64                     4.8.5-44.el7                                              LocalRepo_BaseOS                     103 k
 libgomp                                                    x86_64                     4.8.5-44.el7                                              LocalRepo_BaseOS                     159 k
 libibverbs                                                 x86_64                     22.4-6.el7_9                                              LocalRepo_BaseOS                     269 k
 libicu                                                     x86_64                     50.2-4.el7_7                                              LocalRepo_BaseOS                     6.9 M
 libini_config                                              x86_64                     1.3.1-32.el7                                              LocalRepo_BaseOS                      64 k
 libldb                                                     x86_64                     1.5.4-2.el7_9                                             LocalRepo_BaseOS                     149 k
 libmount                                                   x86_64                     2.23.2-65.el7_9.1                                         LocalRepo_BaseOS                     185 k
 libmspack                                                  x86_64                     0.5-0.8.alpha.el7                                         LocalRepo_BaseOS                      64 k
 libndp                                                     x86_64                     1.2-9.el7                                                 LocalRepo_BaseOS                      32 k
 libpath_utils                                              x86_64                     0.2.1-32.el7                                              LocalRepo_BaseOS                      28 k
 libpciaccess                                               x86_64                     0.14-1.el7                                                LocalRepo_BaseOS                      26 k
 libpwquality                                               x86_64                     1.2.3-5.el7                                               LocalRepo_BaseOS                      85 k
 libqb                                                      x86_64                     1.0.1-9.el7                                               LocalRepo_BaseOS                      96 k
 librdmacm                                                  x86_64                     22.4-6.el7_9                                              LocalRepo_BaseOS                      64 k
 libref_array                                               x86_64                     0.1.5-32.el7                                              LocalRepo_BaseOS                      27 k
 libss                                                      x86_64                     1.42.9-19.el7                                             LocalRepo_BaseOS                      47 k
 libstdc++                                                  x86_64                     4.8.5-44.el7                                              LocalRepo_BaseOS                     306 k
 libtalloc                                                  x86_64                     2.1.16-1.el7                                              LocalRepo_BaseOS                      33 k
 libtdb                                                     x86_64                     1.3.18-1.el7                                              LocalRepo_BaseOS                      49 k
 libteam                                                    x86_64                     1.29-3.el7                                                LocalRepo_BaseOS                      50 k
 libtevent                                                  x86_64                     0.9.39-1.el7                                              LocalRepo_BaseOS                      41 k
 libtirpc                                                   x86_64                     0.2.4-0.16.el7                                            LocalRepo_BaseOS                      89 k
 libuser                                                    x86_64                     0.60-9.el7                                                LocalRepo_BaseOS                     400 k
 libuuid                                                    x86_64                     2.23.2-65.el7_9.1                                         LocalRepo_BaseOS                      84 k
 libwbclient                                                x86_64                     4.10.16-25.el7_9                                          LocalRepo_BaseOS                     117 k
 libxml2                                                    x86_64                     2.9.1-6.el7_9.6                                           LocalRepo_BaseOS                     668 k
 libxml2-python                                             x86_64                     2.9.1-6.el7_9.6                                           LocalRepo_BaseOS                     247 k
 libxslt                                                    x86_64                     1.1.28-6.el7                                              LocalRepo_BaseOS                     242 k
linux-firmware                                             noarch                     20200421-83.git78c0348.el7_9                              LocalRepo_BaseOS                      80 M
 lm_sensors-libs                                            x86_64                     3.4.0-8.20160601gitf9185e5.el7_9.1                        LocalRepo_BaseOS                      42 k
 logrotate                                                  x86_64                     3.8.6-19.el7                                              LocalRepo_BaseOS                      70 k
 lsof                                                       x86_64                     4.87-6.el7                                                LocalRepo_BaseOS                     331 k
 lvm2                                                       x86_64                     7:2.02.187-6.el7_9.5                                      LocalRepo_BaseOS                     1.3 M
 lvm2-libs                                                  x86_64                     7:2.02.187-6.el7_9.5                                      LocalRepo_BaseOS                     1.1 M
 make                                                       x86_64                     1:3.82-24.el7                                             LocalRepo_BaseOS                     421 k
 man-db                                                     x86_64                     2.6.3-11.el7                                              LocalRepo_BaseOS                     832 k
 mariadb-libs                                               x86_64                     1:5.5.68-1.el7                                            LocalRepo_BaseOS                     760 k
 microcode_ctl                                              x86_64                     2:2.1-73.20.el7_9                                         LocalRepo_BaseOS                     6.8 M
 mozjs17                                                    x86_64                     17.0.0-20.el7                                             LocalRepo_BaseOS                     1.4 M
 ncurses                                                    x86_64                     5.9-14.20130511.el7_4                                     LocalRepo_BaseOS                     304 k
 ncurses-base                                               noarch                     5.9-14.20130511.el7_4                                     LocalRepo_BaseOS                      68 k
 ncurses-libs                                               x86_64                     5.9-14.20130511.el7_4                                     LocalRepo_BaseOS                     316 k
 net-snmp-libs                                              x86_64                     1:5.7.2-49.el7_9.4                                        LocalRepo_BaseOS                     752 k
 net-tools                                                  x86_64                     2.0-0.25.20131004git.el7                                  LocalRepo_BaseOS                     306 k
 nettle                                                     x86_64                     2.7.1-9.el7_9                                             LocalRepo_BaseOS                     328 k
 nfs-utils                                                  x86_64                     1:1.3.0-0.68.el7.2                                        LocalRepo_BaseOS                     414 k
 nspr                                                       x86_64                     4.35.0-1.el7_9                                            LocalRepo_BaseOS                     128 k
 nss                                                        x86_64                     3.90.0-2.el7_9                                            LocalRepo_BaseOS                     905 k
 nss-pem                                                    x86_64                     1.0.3-7.el7_9.1                                           LocalRepo_BaseOS                      75 k
 nss-softokn                                                x86_64                     3.90.0-6.el7_9                                            LocalRepo_BaseOS                     384 k
 nss-softokn-freebl                                         x86_64                     3.90.0-6.el7_9                                            LocalRepo_BaseOS                     321 k
 nss-sysinit                                                x86_64                     3.90.0-2.el7_9                                            LocalRepo_BaseOS                      67 k
 nss-tools                                                  x86_64                     3.90.0-2.el7_9                                            LocalRepo_BaseOS                     557 k
 nss-util                                                   x86_64                     3.90.0-1.el7_9                                            LocalRepo_BaseOS                      80 k
 numactl-libs                                               x86_64                     2.0.12-5.el7                                              LocalRepo_BaseOS                      30 k
 openldap                                                   x86_64                     2.4.44-25.el7_9                                           LocalRepo_BaseOS                     356 k
 pam                                                        x86_64                     1.1.8-23.el7                                              LocalRepo_BaseOS                     721 k
 parted                                                     x86_64                     3.1-32.el7                                                LocalRepo_BaseOS                     609 k
 passwd                                                     x86_64                     0.79-6.el7                                                LocalRepo_BaseOS                     106 k
 pciutils                                                   x86_64                     3.5.1-3.el7                                               LocalRepo_BaseOS                      93 k
 pciutils-libs                                              x86_64                     3.5.1-3.el7                                               LocalRepo_BaseOS                      46 k
 perl                                                       x86_64                     4:5.16.3-299.el7_9                                        LocalRepo_BaseOS                     8.0 M
 perl-Getopt-Long                                           noarch                     2.40-3.el7                                                LocalRepo_BaseOS                      56 k
 perl-Pod-Escapes                                           noarch                     1:1.04-299.el7_9                                          LocalRepo_BaseOS                      52 k
 perl-Socket                                                x86_64                     2.010-5.el7                                               LocalRepo_BaseOS                      49 k
 perl-libs                                                  x86_64                     4:5.16.3-299.el7_9                                        LocalRepo_BaseOS                     690 k
 perl-macros                                                x86_64                     4:5.16.3-299.el7_9                                        LocalRepo_BaseOS                      44 k
 plymouth                                                   x86_64                     0.8.9-0.34.20140113.el7                                   LocalRepo_BaseOS                     116 k
 plymouth-core-libs                                         x86_64                     0.8.9-0.34.20140113.el7                                   LocalRepo_BaseOS                     108 k
 plymouth-scripts                                           x86_64                     0.8.9-0.34.20140113.el7                                   LocalRepo_BaseOS                      39 k
 postfix                                                    x86_64                     2:2.10.1-9.el7                                            LocalRepo_BaseOS                     2.4 M
 procps-ng                                                  x86_64                     3.3.10-28.el7                                             LocalRepo_BaseOS                     291 k
 psmisc                                                     x86_64                     22.20-17.el7                                              LocalRepo_BaseOS                     141 k
 pyOpenSSL                                                  x86_64                     0.13.1-4.el7                                              LocalRepo_BaseOS                     135 k
 python                                                     x86_64                     2.7.5-94.el7_9                                            LocalRepo_BaseOS                      97 k
 python-dmidecode                                           x86_64                     3.12.2-4.el7                                              LocalRepo_BaseOS                      83 k
 python-ethtool                                             x86_64                     0.8-8.el7                                                 LocalRepo_BaseOS                      34 k
 python-firewall                                            noarch                     0.6.3-13.el7_9                                            LocalRepo_BaseOS                     355 k
 python-gobject-base                                        x86_64                     3.22.0-1.el7_4.1                                          LocalRepo_BaseOS                     294 k
 python-libs                                                x86_64                     2.7.5-94.el7_9                                            LocalRepo_BaseOS                     5.6 M
python-linux-procfs                                        noarch                     0.4.11-4.el7                                              LocalRepo_BaseOS                      33 k
 python-magic                                               noarch                     5.11-37.el7                                               LocalRepo_BaseOS                      34 k
 python-perf                                                x86_64                     3.10.0-1160.119.1.el7                                     LocalRepo_BaseOS                     8.2 M
 python-slip                                                noarch                     0.4.0-4.el7                                               LocalRepo_BaseOS                      31 k
 python-slip-dbus                                           noarch                     0.4.0-4.el7                                               LocalRepo_BaseOS                      32 k
 python-urlgrabber                                          noarch                     3.10-10.el7                                               LocalRepo_BaseOS                     109 k
 quota                                                      x86_64                     1:4.01-19.el7                                             LocalRepo_BaseOS                     179 k
 quota-nls                                                  noarch                     1:4.01-19.el7                                             LocalRepo_BaseOS                      90 k
 rdma-core                                                  x86_64                     22.4-6.el7_9                                              LocalRepo_BaseOS                      52 k
 readline                                                   x86_64                     6.2-11.el7                                                LocalRepo_BaseOS                     193 k
 redhat-logos                                               noarch                     70.7.0-1.el7                                              LocalRepo_BaseOS                      13 M
 redhat-release-server                                      x86_64                     7.9-12.el7_9                                              LocalRepo_BaseOS                      32 k
 redhat-support-lib-python                                  noarch                     0.14.0-1.el7_9                                            LocalRepo_BaseOS                     277 k
 redhat-support-tool                                        noarch                     0.14.0-1.el7_9                                            LocalRepo_BaseOS                     254 k
 rhn-check                                                  x86_64                     2.0.2-24.el7                                              LocalRepo_BaseOS                      56 k
 rhn-client-tools                                           x86_64                     2.0.2-24.el7                                              LocalRepo_BaseOS                     411 k
 rhn-setup                                                  x86_64                     2.0.2-24.el7                                              LocalRepo_BaseOS                      90 k
 rhnlib                                                     noarch                     2.5.65-8.el7                                              LocalRepo_BaseOS                      66 k
 rhnsd                                                      x86_64                     5.0.13-10.el7                                             LocalRepo_BaseOS                      49 k
 rpcbind                                                    x86_64                     0.2.0-49.el7                                              LocalRepo_BaseOS                      60 k
 rpm                                                        x86_64                     4.11.3-48.el7_9                                           LocalRepo_BaseOS                     1.2 M
 rpm-build-libs                                             x86_64                     4.11.3-48.el7_9                                           LocalRepo_BaseOS                     108 k
 rpm-libs                                                   x86_64                     4.11.3-48.el7_9                                           LocalRepo_BaseOS                     279 k
 rpm-python                                                 x86_64                     4.11.3-48.el7_9                                           LocalRepo_BaseOS                      84 k
 rsyslog                                                    x86_64                     8.24.0-57.el7_9.3                                         LocalRepo_BaseOS                     622 k
 ruby                                                       x86_64                     2.0.0.648-39.el7_9                                        LocalRepo_BaseOS                      73 k
 ruby-irb                                                   noarch                     2.0.0.648-39.el7_9                                        LocalRepo_BaseOS                      94 k
 ruby-libs                                                  x86_64                     2.0.0.648-39.el7_9                                        LocalRepo_BaseOS                     2.8 M
 rubygem-bigdecimal                                         x86_64                     1.2.0-39.el7_9                                            LocalRepo_BaseOS                      85 k
 rubygem-io-console                                         x86_64                     0.4.2-39.el7_9                                            LocalRepo_BaseOS                      56 k
 rubygem-json                                               x86_64                     1.7.7-39.el7_9                                            LocalRepo_BaseOS                      82 k
 rubygem-psych                                              x86_64                     2.0.0-39.el7_9                                            LocalRepo_BaseOS                      85 k
 rubygem-rdoc                                               noarch                     4.0.0-39.el7_9                                            LocalRepo_BaseOS                     324 k
 rubygems                                                   noarch                     2.0.14.1-39.el7_9                                         LocalRepo_BaseOS                     216 k
 samba-client-libs                                          x86_64                     4.10.16-25.el7_9                                          LocalRepo_BaseOS                     5.0 M
 samba-common                                               noarch                     4.10.16-25.el7_9                                          LocalRepo_BaseOS                     219 k
 samba-common-libs                                          x86_64                     4.10.16-25.el7_9                                          LocalRepo_BaseOS                     183 k
 sed                                                        x86_64                     4.2.2-7.el7                                               LocalRepo_BaseOS                     231 k
 selinux-policy                                             noarch                     3.13.1-268.el7_9.2                                        LocalRepo_BaseOS                     498 k
 selinux-policy-targeted                                    noarch                     3.13.1-268.el7_9.2                                        LocalRepo_BaseOS                     7.0 M
setup                                                      noarch                     2.8.71-11.el7                                             LocalRepo_BaseOS                     166 k
 sg3_utils                                                  x86_64                     1:1.37-19.el7                                             LocalRepo_BaseOS                     646 k
 sg3_utils-libs                                             x86_64                     1:1.37-19.el7                                             LocalRepo_BaseOS                      65 k
 shadow-utils                                               x86_64                     2:4.6-5.el7                                               LocalRepo_BaseOS                     1.2 M
 shared-mime-info                                           x86_64                     1.8-5.el7                                                 LocalRepo_BaseOS                     312 k
 sqlite                                                     x86_64                     3.7.17-8.el7_7.1                                          LocalRepo_BaseOS                     394 k
 subscription-manager                                       x86_64                     1.24.54-1.el7_9                                           LocalRepo_BaseOS                     1.1 M
 sysstat                                                    x86_64                     10.1.5-20.el7_9                                           LocalRepo_BaseOS                     316 k
 tar                                                        x86_64                     2:1.26-35.el7                                             LocalRepo_BaseOS                     846 k
 teamd                                                      x86_64                     1.29-3.el7                                                LocalRepo_BaseOS                     116 k
 tuned                                                      noarch                     2.11.0-12.el7_9                                           LocalRepo_BaseOS                     270 k
 tzdata                                                     noarch                     2024a-1.el7                                               LocalRepo_BaseOS                     497 k
 usermode                                                   x86_64                     1.111-6.el7                                               LocalRepo_BaseOS                     193 k
 util-linux                                                 x86_64                     2.23.2-65.el7_9.1                                         LocalRepo_BaseOS                     2.0 M
 vim-minimal                                                x86_64                     2:7.4.629-8.el7_9                                         LocalRepo_BaseOS                     443 k
 virt-what                                                  x86_64                     1.18-4.el7_9.1                                            LocalRepo_BaseOS                      30 k
 wpa_supplicant                                             x86_64                     1:2.6-12.el7_9.2                                          LocalRepo_BaseOS                     1.2 M
 xfsprogs                                                   x86_64                     4.5.0-22.el7                                              LocalRepo_BaseOS                     897 k
 xmlsec1                                                    x86_64                     1.2.20-8.el7_9                                            LocalRepo_BaseOS                     177 k
 xmlsec1-openssl                                            x86_64                     1.2.20-8.el7_9                                            LocalRepo_BaseOS                      76 k
 xz                                                         x86_64                     5.2.2-2.el7_9                                             LocalRepo_BaseOS                     229 k
 xz-libs                                                    x86_64                     5.2.2-2.el7_9                                             LocalRepo_BaseOS                     103 k
 yum                                                        noarch                     3.4.3-168.el7                                             LocalRepo_BaseOS                     1.2 M
 yum-rhn-plugin                                             noarch                     2.0.1-10.el7                                              LocalRepo_BaseOS                      81 k
 zlib                                                       x86_64                     1.2.7-21.el7_9                                            LocalRepo_BaseOS                      90 k
Installing for dependencies:
 bind-export-libs                                           x86_64                     32:9.11.4-26.P2.el7_9.16                                  LocalRepo_BaseOS                     1.1 M
 geoipupdate                                                x86_64                     2.5.0-2.el7                                               LocalRepo_BaseOS                      35 k
 libpcap                                                    x86_64                     14:1.5.3-13.el7_9                                         LocalRepo_BaseOS                     139 k
 libpng                                                     x86_64                     2:1.5.13-8.el7                                            LocalRepo_BaseOS                     213 k
 libsmartcols                                               x86_64                     2.23.2-65.el7_9.1                                         LocalRepo_BaseOS                     143 k
 nmap-ncat                                                  x86_64                     2:6.40-19.el7                                             LocalRepo_BaseOS                     207 k
 pexpect                                                    noarch                     2.3-11.el7                                                LocalRepo_BaseOS                     142 k
 python-cffi                                                x86_64                     1.6.0-5.el7                                               LocalRepo_BaseOS                     218 k
 python-enum34                                              noarch                     1.0.4-1.el7                                               LocalRepo_BaseOS                      52 k
 python-idna                                                noarch                     2.4-1.el7                                                 LocalRepo_BaseOS                      94 k
 python-inotify                                             noarch                     0.9.4-4.el7                                               LocalRepo_BaseOS                      49 k
 python-ipaddr                                              noarch                     2.1.11-2.el7                                              LocalRepo_BaseOS                      36 k
 python-jwcrypto                                            noarch                     0.4.2-1.el7                                               LocalRepo_BaseOS                      57 k
 python-ply                                                 noarch                     3.4-11.el7                                                LocalRepo_BaseOS                     123 k
 python-pycparser                                           noarch                     2.14-1.el7                                                LocalRepo_BaseOS                     105 k
 python-requests                                            noarch                     2.6.0-10.el7                                              LocalRepo_BaseOS                      95 k
 python-six                                                 noarch                     1.9.0-2.el7                                               LocalRepo_BaseOS                      29 k
 python-syspurpose                                          x86_64                     1.24.54-1.el7_9                                           LocalRepo_BaseOS                     277 k
 python-urllib3                                             noarch                     1.10.2-7.el7                                              LocalRepo_BaseOS                     103 k
 python2-cryptography                                       x86_64                     1.7.2-2.el7                                               LocalRepo_BaseOS                     503 k
 python2-futures                                            noarch                     3.1.1-5.el7                                               LocalRepo_BaseOS                      29 k
 python2-pyasn1                                             noarch                     0.1.9-7.el7                                               LocalRepo_BaseOS                     100 k

Transaction Summary
============================================================================================================================================================================================
Install    7 Packages (+22 Dependent packages)
Upgrade  264 Packages

Total download size: 257 M

