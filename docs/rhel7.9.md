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

