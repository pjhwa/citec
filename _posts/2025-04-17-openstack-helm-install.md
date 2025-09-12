---
title: "OpenStack Helm 설치 - 1부"
date: 2025-04-17
tags: [openstack, helm, kubernetes, ceph, keepalived, haproxy, ansible]
categories: [Howtos, OpenStack]
---

OpenStack Helm을 기반으로 Kubernetes, Rook-Ceph 기반의 OpenStack 환경을 구축하고자 한다. Kubernetes는 HA 마스터 클러스터로 구성한다. 1부에서는 사전 준비와 Kubernetes와 Rook-Ceph 설치 및 구성을 다룬다.

## 환경 
OpenStack Helm을 이용한 설치를 위해 4개의 VM을 준비한다. 
- 참고 자료: https://docs.openstack.org/openstack-helm/latest/install/index.html 

### VM
- Ubuntu 22.04
- 4 CPU, 32GB Memory, 3 HDD, 2 NIC (VM Network)
- Hostname & IP Address
  - k1 - ens160: 172.16.2.149
  - k2 - ens160: 172.16.2.52
  - k3 - ens160: 172.16.2.223
  - k4 - ens160: 172.16.2.161
- kubectl User: citec

## OS 사전 준비 (모든 노드에서 작업 수행)

### 호스트명 설정

```
citec@ubuntu:~$ sudo hostnamectl set-hostname k1
citec@ubuntu:~$ sudo hostnamectl set-hostname k2
citec@ubuntu:~$ sudo hostnamectl set-hostname k3
citec@ubuntu:~$ sudo hostnamectl set-hostname k4

citec@ubuntu:~$ sudo tee -a /etc/hosts <<EOF
172.16.2.149 k1 
172.16.2.52 k2
172.16.2.223 k3
172.16.2.161 k4
EOF
```

### 사용자 설정
citec 사용자를 sudoers에 등록

```
root@k1:~# echo "citec ALL=(ALL) NOPASSWD:ALL" | tee -a /etc/sudoers.d/citec 
```

### 네트워크 설정

```
root@k1:~# vi /etc/netplan/01-network-manager-all.yaml
network:
  ethernets:
    ens160:
      dhcp4: true
      nameservers:
        addresses:
        - 172.16.10.254
        - 8.8.8.8
    ens192:
      dhcp4: false
  version: 2

root@k1:~# tee /etc/resolv.conf <<EOF
nameserver 8.8.8.8
EOF

root@k1:~# tee /etc/systemd/timesyncd.conf <<EOF
[Time]
NTP=172.16.10.254
EOF

root@k1:~# timedatectl
               Local time: Thu 2025-04-17 09:58:36 KST
           Universal time: Thu 2025-04-17 00:58:36 UTC
                 RTC time: Thu 2025-04-17 00:58:36
                Time zone: Asia/Seoul (KST, +0900)
System clock synchronized: yes
              NTP service: active
          RTC in local TZ: no

root@k1:~# vi /etc/default/grub
GRUB_CMDLINE_LINUX_DEFAULT="maybe-ubiquity ipv6.disable=1"

root@k1:~# update-grub
Sourcing file `/etc/default/grub'
Sourcing file `/etc/default/grub.d/init-select.cfg'
Generating grub configuration file ...
Found linux image: /boot/vmlinuz-5.15.0-136-generic
Found initrd image: /boot/initrd.img-5.15.0-136-generic
Found linux image: /boot/vmlinuz-5.15.0-122-generic
Found initrd image: /boot/initrd.img-5.15.0-122-generic
Warning: os-prober will not be executed to detect other bootable partitions.
Systems on them will not be added to the GRUB boot configuration.
Check GRUB_DISABLE_OS_PROBER documentation entry.
done
root@k1:~# reboot
```

### SSH Key 설정 (citec 사용자, 마스터 노드 k1에서만 실행)

```
citec@k1:~$ ssh-keygen -t rsa -b 4096 -N ""
Generating public/private rsa key pair.
Enter file in which to save the key (/home/citec/.ssh/id_rsa):
Your identification has been saved in /home/citec/.ssh/id_rsa
Your public key has been saved in /home/citec/.ssh/id_rsa.pub
The key fingerprint is:
SHA256:8ZdIFE3SaCfLgB9hmQvPs50AUZR+D+8Rtb8OUoptbQU citec@k1
The key's randomart image is:
+---[RSA 4096]----+
|      .===+*.    |
|      +.*.+.+ .  |
|       B.*.+ E . |
|        O+=...o  |
|        S*o=oo o |
|        . =.B . .|
|         . * =  .|
|          . + .. |
|              .. |
+----[SHA256]-----+

citec@k1:~$ for i in 149 52 223 161
> do
> ssh-copy-id citec@172.16.2.${i}
> done
/usr/bin/ssh-copy-id: INFO: Source of key(s) to be installed: "/home/citec/.ssh/id_rsa.pub"
/usr/bin/ssh-copy-id: INFO: attempting to log in with the new key(s), to filter out any that are already installed
/usr/bin/ssh-copy-id: INFO: 1 key(s) remain to be installed -- if you are prompted now it is to install the new keys

Number of key(s) added: 1

Now try logging into the machine, with:   "ssh 'citec@172.16.2.149'"
and check to make sure that only the key(s) you wanted were added.

/usr/bin/ssh-copy-id: INFO: Source of key(s) to be installed: "/home/citec/.ssh/id_rsa.pub"
/usr/bin/ssh-copy-id: INFO: attempting to log in with the new key(s), to filter out any that are already installed
/usr/bin/ssh-copy-id: INFO: 1 key(s) remain to be installed -- if you are prompted now it is to install the new keys

Number of key(s) added: 1

Now try logging into the machine, with:   "ssh 'citec@172.16.2.52'"
and check to make sure that only the key(s) you wanted were added.

/usr/bin/ssh-copy-id: INFO: Source of key(s) to be installed: "/home/citec/.ssh/id_rsa.pub"
/usr/bin/ssh-copy-id: INFO: attempting to log in with the new key(s), to filter out any that are already installed
/usr/bin/ssh-copy-id: INFO: 1 key(s) remain to be installed -- if you are prompted now it is to install the new keys

Number of key(s) added: 1

Now try logging into the machine, with:   "ssh 'citec@172.16.2.223'"
and check to make sure that only the key(s) you wanted were added.

/usr/bin/ssh-copy-id: INFO: Source of key(s) to be installed: "/home/citec/.ssh/id_rsa.pub"
/usr/bin/ssh-copy-id: INFO: attempting to log in with the new key(s), to filter out any that are already installed
/usr/bin/ssh-copy-id: INFO: 1 key(s) remain to be installed -- if you are prompted now it is to install the new keys

Number of key(s) added: 1

Now try logging into the machine, with:   "ssh 'citec@172.16.2.161'"
and check to make sure that only the key(s) you wanted were added.
```

### 패키지 자동 업데이트 중지

```
citec@k1:~$ sudo systemctl stop apt-daily.timer
citec@k1:~$ sudo systemctl disable apt-daily.timer
citec@k1:~$ sudo systemctl stop apt-daily-upgrade.timer
citec@k1:~$ sudo systemctl disable apt-daily-upgrade.timer
citec@k1:~$ sudo systemctl stop unattended-upgrades
citec@k1:~$ sudo systemctl disable unattended-upgrades
Synchronizing state of unattended-upgrades.service with SysV service script with /lib/systemd/systemd-sysv-install.
Executing: /lib/systemd/systemd-sysv-install disable unattended-upgrades
```

### 방화벽 비활성화 

```
citec@k1:~$ sudo systemctl stop ufw
citec@k1:~$ sudo systemctl disable ufw
citec@k1:~$ sudo systemctl status ufw
○ ufw.service - Uncomplicated firewall
     Loaded: loaded (/lib/systemd/system/ufw.service; disabled; vendor preset: enabled)
     Active: inactive (dead)
       Docs: man:ufw(8)
```

## 패키지 설치 

### 시스템 업데이트 및 필수 패키지 설치 (모든 노드에서 수행)

```
citec@k1:~$ sudo apt update & sudo apt upgrade -y
citec@k1:~$ sudo apt install -y python3-pip git ansible openvswitch
```

## Ansible 플레이북 설치 환경 구성 (마스터 노드, k1에서만 실행)

### 필요 저장소 복제 및 Ansible 환경 설정

#### 작업 디렉토리 생성 및 이동
```
citec@k1:~$ mkdir ~/osh 
citec@k1:~$ cd ~/osh 
```

#### 저장소 복제 
기존 openstack-helm 플레이북을 Kubernetes HA 마스터 클러스터 환경으로 구성할 수 있도록 수정한 저장소를 복제한다.

```
citec@k1:~/osh$ git clone https://github.com/pjhwa/openstack-helm.git
Cloning into 'openstack-helm'...
remote: Enumerating objects: 82208, done.
remote: Counting objects: 100% (5416/5416), done.
remote: Compressing objects: 100% (1124/1124), done.
remote: Total 82208 (delta 4894), reused 4292 (delta 4292), pack-reused 76792 (from 5)
Receiving objects: 100% (82208/82208), 19.91 MiB | 1.78 MiB/s, done.
Resolving deltas: 100% (58772/58772), done.
Updating files: 100% (2853/2853), done.
```

Kubernetes HA 마스터 클러스터 환경을 위한 Keepalived, HAProxy 설치, Rook-Ceph 설치를 위한 플레이북을 포함한 저장소도 복제한다.

```
citec@k1:~/osh$ git clone https://github.com/pjhwa/osh-hamaster.git
Cloning into 'osh-hamaster'...
remote: Enumerating objects: 38, done.
remote: Counting objects: 100% (38/38), done.
remote: Compressing objects: 100% (36/36), done.
remote: Total 38 (delta 11), reused 0 (delta 0), pack-reused 0 (from 0)
Receiving objects: 100% (38/38), 14.58 KiB | 2.43 MiB/s, done.
Resolving deltas: 100% (11/11), done.
```

#### ANSIBLE_ROLES_PATH 설정 
```
citec@k1:~$ echo "export ANSIBLE_ROLES_PATH=~/osh/openstack-helm/roles" >> ~/.bashrc
citec@k1:~$ . ~/.bashrc 
```

### Ansible 인벤토리 및 플레이북 생성

#### 인벤토리 파일 생성

```
citec@k1:~/osh$ tee inventory.yaml <<EOF
---
all:
  vars:
    ansible_port: 22
    ansible_user: citec
    ansible_ssh_private_key_file: /home/citec/.ssh/id_rsa
    ansible_ssh_extra_args: -o StrictHostKeyChecking=no -o ConnectTimeout=30 -o ServerAliveInterval=60 -o ServerAliveCountMax=5
    ansible_ssh_public_key_file: /home/citec/.ssh/id_rsa.pub
    ssh_public_key: "lookup('file', '/home/citec/.ssh/id_rsa.pub')"
    kubectl:
      user: citec
      group: citec
    docker_users:
      - citec
    client_ssh_user: citec
    cluster_ssh_user: citec
    metallb_setup: true
    loopback_setup: true
    loopback_device: /dev/loop100
    loopback_image: /var/lib/openstack-helm/ceph-loop.img
    loopback_image_size: 12G
    vip: "172.16.2.148"
    control_plane_endpoint: "{{ vip }}:16443"
    kubeadm:
      service_cidr: "10.96.0.0/16"
      pod_network_cidr: "10.244.0.0/16"
    kube_version: "1.33.0"
    kube_version_repo: "v1.33"
    kube_package_version: "1.33.0-1.1"
    ingress_setup: true
  children:
    primary:
      hosts:
        k1:
          ansible_host: 172.16.2.149
          node_role: master
    k8s_cluster:
      hosts:
        k1:
          ansible_host: 172.16.2.149
          node_role: master
        k2:
          ansible_host: 172.16.2.52
          node_role: master_worker
        k3:
          ansible_host: 172.16.2.223
          node_role: master_worker
        k4:
          ansible_host: 172.16.2.161
          node_role: worker
    k8s_control_plane:
      hosts:
        k1:
          ansible_host: 172.16.2.149
          node_role: master
        k2:
          ansible_host: 172.16.2.52
          node_role: master_worker
        k3:
          ansible_host: 172.16.2.223
          node_role: master_worker
    k8s_nodes:
      hosts:
        k4:
          ansible_host: 172.16.2.161
          node_role: worker
    k8s_worker:
      hosts:
        k2:
          ansible_host: 172.16.2.52
          node_role: master_worker
        k3:
          ansible_host: 172.16.2.223
          node_role: master_worker
        k4:
          ansible_host: 172.16.2.161
          node_role: worker
EOF
```

#### 플레이북 생성

```
citec@k1:~/osh$ tee deploy-env.yaml <<EOF
---
- hosts: all
  become: true
  gather_facts: true
  roles:
    - ensure-python
    - ensure-pip
    - clear-firewall
    - deploy-env
EOF
```

## Kubernetes 설치 

### Keepalived, HAProxy 설치

osh-hamaster 저장소에 있는 파일들을 `~/osh` 디렉토리로 이동한 후 설치를 진행한다.

```
citec@k1:~/osh$ cd osh-hamaster/
citec@k1:~/osh/osh-hamaster$ mv * ~/osh/
```

이들 설치를 위한 플레이북 실행한다.

```
citec@k1:~/osh$ ansible-playbook -i inventory.yaml install-keepalived.yaml
citec@k1:~/osh$ ansible-playbook -i inventory.yaml install-haproxy.yaml
```

에러 없이 설치가 완료되면, 아래와 같이 정상적으로 설치가 완료되었는지 확인한다. Kubernetes HA 마스터들을 위해 VIP:Port(`172.16.2.148:16443`)를 구성한다.

Keepalived 서비스가 `active (running)` 상태인지 확인하고, ens160 디바이스에 VIP `172.16.2.148`이 IP Aliasing 되어있는지 확인한다.
```
citec@k1:~/osh$ sudo systemctl status keepalived
● keepalived.service - Keepalive Daemon (LVS and VRRP)
     Loaded: loaded (/lib/systemd/system/keepalived.service; enabled; vendor preset: enabled)
     Active: active (running) since Thu 2025-05-08 10:04:08 KST; 23h ago
   Main PID: 331861 (keepalived)
      Tasks: 2 (limit: 38380)
     Memory: 2.1M
        CPU: 11.556s
     CGroup: /system.slice/keepalived.service
             ├─331861 /usr/sbin/keepalived --dont-fork
             └─331862 /usr/sbin/keepalived --dont-fork

May 08 10:04:08 k1 systemd[1]: keepalived.service: Got notification message from PID 331862, but reception only permitted for main PID 331861
May 08 10:04:08 k1 Keepalived_vrrp[331862]: WARNING - default user 'keepalived_script' for script execution does not exist - please create.
May 08 10:04:08 k1 Keepalived[331861]: Startup complete
May 08 10:04:08 k1 systemd[1]: Started Keepalive Daemon (LVS and VRRP).
May 08 10:04:08 k1 Keepalived_vrrp[331862]: WARNING - script `killall` resolved by path search to `/usr/bin/killall`. Please specify full path.
May 08 10:04:08 k1 Keepalived_vrrp[331862]: SECURITY VIOLATION - scripts are being executed but script_security not enabled.
May 08 10:04:08 k1 Keepalived_vrrp[331862]: Warning - script chk_haproxy is not used
May 08 10:04:08 k1 Keepalived_vrrp[331862]: (VI_1) Entering BACKUP STATE (init)
May 08 10:04:12 k1 Keepalived_vrrp[331862]: (VI_1) received lower priority (99) advert from 172.16.2.52 - discarding
May 08 10:04:12 k1 Keepalived_vrrp[331862]: (VI_1) Entering MASTER STATE

citec@k1:~/osh$ ip addr show
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
2: ens160: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    link/ether 00:50:56:bb:57:46 brd ff:ff:ff:ff:ff:ff
    altname enp3s0
    inet 172.16.2.149/24 metric 100 brd 172.16.2.255 scope global dynamic ens160
       valid_lft 599sec preferred_lft 599sec
    inet 172.16.2.148/24 scope global secondary ens160
       valid_lft forever preferred_lft forever
3: ens192: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    link/ether 00:50:56:bb:af:1a brd ff:ff:ff:ff:ff:ff
    altname enp11s0
14: tunl0@NONE: <NOARP,UP,LOWER_UP> mtu 1480 qdisc noqueue state UNKNOWN group default qlen 1000
    link/ipip 0.0.0.0 brd 0.0.0.0
    inet 10.244.105.128/32 scope global tunl0
       valid_lft forever preferred_lft forever
```

HAProxy 서비스가 `active (running)` 상태인지 확인하고, `16443` 포트가 `LISTEN` 상태에 있는지 확인한다.
```
citec@k1:~/osh$ sudo systemctl status haproxy
● haproxy.service - HAProxy Load Balancer
     Loaded: loaded (/lib/systemd/system/haproxy.service; enabled; vendor preset: enabled)
     Active: active (running) since Thu 2025-05-08 10:04:28 KST; 23h ago
       Docs: man:haproxy(1)
             file:/usr/share/doc/haproxy/configuration.txt.gz
   Main PID: 332594 (haproxy)
      Tasks: 5 (limit: 38380)
     Memory: 71.0M
        CPU: 45.561s
     CGroup: /system.slice/haproxy.service
             ├─332594 /usr/sbin/haproxy -Ws -f /etc/haproxy/haproxy.cfg -p /run/haproxy.pid -S /run/haproxy-master.sock
             └─332602 /usr/sbin/haproxy -Ws -f /etc/haproxy/haproxy.cfg -p /run/haproxy.pid -S /run/haproxy-master.sock

May 08 10:04:28 k1 systemd[1]: Started HAProxy Load Balancer.
May 08 10:04:28 k1 haproxy[332602]: [WARNING]  (332602) : Server kubernetes-master/k1 is DOWN, reason: Layer4 connection problem, info: "Connec>
May 08 10:04:29 k1 haproxy[332602]: [WARNING]  (332602) : Server kubernetes-master/k2 is DOWN, reason: Layer4 connection problem, info: "Connec>
May 08 10:04:29 k1 haproxy[332602]: [WARNING]  (332602) : Server kubernetes-master/k3 is DOWN, reason: Layer4 connection problem, info: "Connec>
May 08 10:04:29 k1 haproxy[332602]: [NOTICE]   (332602) : haproxy version is 2.4.24-0ubuntu0.22.04.2
May 08 10:04:29 k1 haproxy[332602]: [NOTICE]   (332602) : path to executable is /usr/sbin/haproxy
May 08 10:04:29 k1 haproxy[332602]: [ALERT]    (332602) : backend 'kubernetes-master' has no server available!
May 08 10:12:24 k1 haproxy[332602]: [WARNING]  (332602) : Server kubernetes-master/k1 is UP, reason: Layer4 check passed, check duration: 0ms. >
May 08 10:12:41 k1 haproxy[332602]: [WARNING]  (332602) : Server kubernetes-master/k2 is UP, reason: Layer4 check passed, check duration: 0ms. >
May 08 10:12:42 k1 haproxy[332602]: [WARNING]  (332602) : Server kubernetes-master/k3 is UP, reason: Layer4 check passed, check duration: 0ms. >

citec@k1:~/osh$ netstat -tunlp | grep 16443
(Not all processes could be identified, non-owned process info
 will not be shown, you would have to be root to see it all.)
tcp        0      0 172.16.2.148:16443      0.0.0.0:*               LISTEN      -
```

### Kubernetes 플레이북 실행

아래의 명령을 실행하여 Kubernetes 설치를 진행한다.

```
citec@k1:~/osh$ ansible-playbook -i ~/osh/inventory.yaml ~/osh/deploy-env.yaml
```

실행 결과는 아래와 유사하다. 실행하는 환경에 따라서, 여러번 수행할 때마다 조금씩 달라지긴 하지만, 모든 노드에 대해서 `failed`는 `0`이어야 한다.

```
PLAY [all] *************************************************************************************************************

TASK [Gathering Facts] *************************************************************************************************
ok: [k1]
ok: [k2]
ok: [k4]
ok: [k3]

TASK [ensure-python : Validate python_version value] *******************************************************************
skipping: [k1]
skipping: [k2]
skipping: [k3]
skipping: [k4]

TASK [ensure-python : Install specified version of python interpreter and development files (DEB)] *********************
skipping: [k1]
skipping: [k2]
skipping: [k3]
skipping: [k4]

...

TASK [deploy-env : Include ingress tasks] ******************************************************************************
skipping: [k1]
skipping: [k2]
skipping: [k3]
skipping: [k4]

PLAY RECAP *************************************************************************************************************
k1                         : ok=93   changed=43   unreachable=0    failed=0    skipped=36   rescued=0    ignored=0
k2                         : ok=58   changed=22   unreachable=0    failed=0    skipped=49   rescued=0    ignored=0
k3                         : ok=58   changed=22   unreachable=0    failed=0    skipped=49   rescued=0    ignored=0
k4                         : ok=58   changed=22   unreachable=0    failed=0    skipped=49   rescued=0    ignored=0
```

### 시스템 초기화 방법

만약, 이전에 Helm을 통해 Kubernetes와 OpenStack 설치를 진행했었다면 아래와 같은 절차로 모든 노드를 초기화한다. ansible-playbook 명령을 여러번 수행해야할 상황이 반드시 올 것이므로... :-)

`reset_script.sh` 스크립트는 Kubernetes 관련 패키지, 설정 파일, 디렉토리 등을 모두 삭제한다. 스크립트를 모든 노드에 복사하고, 수행한다. 참고로, `~/osh/00.sh` 파일은 모든 노드에서 자동으로 수행하도록 만든 간단한 스크립트이다.
```
citec@k1:~/osh$ ./reset_script.sh 
citec@k2:~/osh$ ./reset_script.sh 
citec@k3:~/osh$ ./reset_script.sh 
citec@k4:~/osh$ ./reset_script.sh 
```

### Kubernetes 설치 확인 

#### 노드 상태 확인 
HA 마스터 클러스터 환경이므로, control-plane 역할을 하는 노드가 k1, k2, k3 노드이다. k2, k3, k4 노드는 worker 노드 역할을 한다.

``` 
citec@k1:~/osh$ kubectl get nodes
NAME   STATUS   ROLES                  AGE   VERSION
k1     Ready    control-plane          23h   v1.33.0
k2     Ready    control-plane,worker   23h   v1.33.0
k3     Ready    control-plane,worker   23h   v1.33.0
k4     Ready    worker                 23h   v1.33.0
```

#### kube-system 네임스페이스의 파드 상태 확인
kubectl 명령어를 통해 Kubernetes의 상태를 확인하거나 명령을 수행하는데 필요한 kube-apiserver, Kubernetes 환경에서 네트워크를 담당하게 되는 calico 파드 등을 포함해 모든 파드들이 정상적으로 Running 상태에 있는지 확인한다. 

```
citec@k1:~/osh$ kubectl get pods -A -o wide
NAMESPACE        NAME                                           READY   STATUS      RESTARTS   AGE   IP               NODE   NOMINATED NODE   READINESS GATES
ceph             ingress-nginx-ceph-controller-8wlgb            1/1     Running     0          23h   10.244.105.132   k1     <none>           <none>
ceph             ingress-nginx-ceph-controller-cdpnl            1/1     Running     0          23h   10.244.194.133   k4     <none>           <none>
ceph             ingress-nginx-ceph-controller-kchpf            1/1     Running     0          23h   10.244.195.131   k3     <none>           <none>
ceph             ingress-nginx-ceph-controller-swxdn            1/1     Running     0          23h   10.244.99.2      k2     <none>           <none>
kube-system      calico-kube-controllers-847c966dfc-7k28r       1/1     Running     0          23h   10.244.194.129   k4     <none>           <none>
kube-system      calico-node-gj295                              1/1     Running     0          23h   172.16.2.223     k3     <none>           <none>
kube-system      calico-node-hnm6r                              1/1     Running     0          23h   172.16.2.52      k2     <none>           <none>
kube-system      calico-node-hzl55                              1/1     Running     0          23h   172.16.2.161     k4     <none>           <none>
kube-system      calico-node-z5fvz                              1/1     Running     0          23h   172.16.2.149     k1     <none>           <none>
kube-system      coredns-5d5b7f64b7-nk84m                       1/1     Running     0          23h   10.244.194.130   k4     <none>           <none>
kube-system      coredns-5d5b7f64b7-thtb7                       1/1     Running     0          23h   10.244.195.129   k3     <none>           <none>
kube-system      etcd-k1                                        1/1     Running     47         23h   172.16.2.149     k1     <none>           <none>
kube-system      etcd-k2                                        1/1     Running     0          23h   172.16.2.52      k2     <none>           <none>
kube-system      etcd-k3                                        1/1     Running     0          23h   172.16.2.223     k3     <none>           <none>
kube-system      kube-apiserver-k1                              1/1     Running     23         23h   172.16.2.149     k1     <none>           <none>
kube-system      kube-apiserver-k2                              1/1     Running     26         23h   172.16.2.52      k2     <none>           <none>
kube-system      kube-apiserver-k3                              1/1     Running     27         23h   172.16.2.223     k3     <none>           <none>
kube-system      kube-controller-manager-k1                     1/1     Running     49         23h   172.16.2.149     k1     <none>           <none>
kube-system      kube-controller-manager-k2                     1/1     Running     21         23h   172.16.2.52      k2     <none>           <none>
kube-system      kube-controller-manager-k3                     1/1     Running     33         23h   172.16.2.223     k3     <none>           <none>
kube-system      kube-proxy-6wlxh                               1/1     Running     0          23h   172.16.2.161     k4     <none>           <none>
kube-system      kube-proxy-fsf8h                               1/1     Running     0          23h   172.16.2.149     k1     <none>           <none>
kube-system      kube-proxy-lmkdp                               1/1     Running     0          23h   172.16.2.52      k2     <none>           <none>
kube-system      kube-proxy-vxw9t                               1/1     Running     0          23h   172.16.2.223     k3     <none>           <none>
kube-system      kube-scheduler-k1                              1/1     Running     49         23h   172.16.2.149     k1     <none>           <none>
kube-system      kube-scheduler-k2                              1/1     Running     21         23h   172.16.2.52      k2     <none>           <none>
kube-system      kube-scheduler-k3                              1/1     Running     32         23h   172.16.2.223     k3     <none>           <none>
metallb-system   metallb-controller-77fb8947dc-kktzd            1/1     Running     0          23h   10.244.194.131   k4     <none>           <none>
metallb-system   metallb-speaker-84wpw                          4/4     Running     0          23h   172.16.2.149     k1     <none>           <none>
metallb-system   metallb-speaker-9br2c                          4/4     Running     0          23h   172.16.2.52      k2     <none>           <none>
metallb-system   metallb-speaker-dk2lr                          4/4     Running     0          23h   172.16.2.223     k3     <none>           <none>
metallb-system   metallb-speaker-dkdgc                          4/4     Running     0          23h   172.16.2.161     k4     <none>           <none>
openstack        ingress-nginx-openstack-controller-72l8m       1/1     Running     0          23h   10.244.195.130   k3     <none>           <none>
openstack        ingress-nginx-openstack-controller-ncklx       1/1     Running     0          23h   10.244.99.1      k2     <none>           <none>
openstack        ingress-nginx-openstack-controller-pd6bw       1/1     Running     0          23h   10.244.105.131   k1     <none>           <none>
openstack        ingress-nginx-openstack-controller-ww7ds       1/1     Running     0          23h   10.244.194.132   k4     <none>           <none>
```

#### 생성된 네임스페이스 확인 

```
citec@k1:~/osh$ kubectl get namespaces
NAME              STATUS   AGE
default           Active   119m
kube-node-lease   Active   119m
kube-public       Active   119m
kube-system       Active   119m
metallb-system    Active   115m
openstack         Active   114m
```

#### crictl 명령어로 컨테이너 상태 확인
ansible-playbook 명령어로 Kubernetes를 설치하면, Kubernetes 파드들이 containerd 서비스에 컨테이너로 동작하게 된다. 이를 crictl 명령어로 확인해보자.

```
citec@k1:~/osh$ sudo crictl ps -a
WARN[0000] runtime connect using default endpoints: [unix:///run/containerd/containerd.sock unix:///run/crio/crio.sock unix:///var/run/cri-dockerd.sock]. As the default settings are now deprecated, you should set the endpoint instead.
WARN[0000] image connect using default endpoints: [unix:///run/containerd/containerd.sock unix:///run/crio/crio.sock unix:///var/run/cri-dockerd.sock]. As the default settings are now deprecated, you should set the endpoint instead.
CONTAINER           IMAGE               CREATED             STATE               NAME                       ATTEMPT             POD ID              POD
9c65b0c0288a8       5aa0bf4798fa2       23 hours ago        Running             controller                 0                   742513a8bedd4       ingress-nginx-ceph-controller-8wlgb
104a30c7e8366       5aa0bf4798fa2       23 hours ago        Running             controller                 0                   a68592700863b       ingress-nginx-openstack-controller-pd6bw
2892bc86e5fae       86e3b780f3799       23 hours ago        Running             frr-metrics                0                   476581eeaac97       metallb-speaker-84wpw
bec8913941b26       86e3b780f3799       23 hours ago        Running             reloader                   0                   476581eeaac97       metallb-speaker-84wpw
a25081ce7f4c4       86e3b780f3799       23 hours ago        Running             frr                        0                   476581eeaac97       metallb-speaker-84wpw
0d2b7b0f20b7b       94c5f9675e593       23 hours ago        Running             speaker                    0                   476581eeaac97       metallb-speaker-84wpw
c8cf6a7db5850       94c5f9675e593       23 hours ago        Exited              cp-metrics                 0                   476581eeaac97       metallb-speaker-84wpw
5b76b72bb4f88       94c5f9675e593       23 hours ago        Exited              cp-reloader                0                   476581eeaac97       metallb-speaker-84wpw
dd552678ee53e       86e3b780f3799       23 hours ago        Exited              cp-frr-files               0                   476581eeaac97       metallb-speaker-84wpw
93ac3642647f2       3dd4390f2a85a       23 hours ago        Running             calico-node                0                   3f4f54c413bd3       calico-node-z5fvz
68a7e3ba50f11       3dd4390f2a85a       23 hours ago        Exited              mount-bpffs                0                   3f4f54c413bd3       calico-node-z5fvz
17c8233ff719a       dc6f84c32585f       23 hours ago        Exited              install-cni                0                   3f4f54c413bd3       calico-node-z5fvz
ea1186e1790d9       dc6f84c32585f       23 hours ago        Exited              upgrade-ipam               0                   3f4f54c413bd3       calico-node-z5fvz
f8e4fa456cb4a       f1184a0bd7fe5       23 hours ago        Running             kube-proxy                 0                   0b05bb31b731d       kube-proxy-fsf8h
b45c32d8ee9a5       8d72586a76469       24 hours ago        Running             kube-scheduler             49                  744d3c02d8741       kube-scheduler-k1
00181ae5c2a07       6ba9545b2183e       24 hours ago        Running             kube-apiserver             23                  210b44a23b6e8       kube-apiserver-k1
18d9f9cabb9a1       499038711c081       24 hours ago        Running             etcd                       47                  2aedf9ce3f1ca       etcd-k1
88db835be5dcc       1d579cb6d6967       24 hours ago        Running             kube-controller-manager    49                  a6ac95c4b6929       kube-controller-manager-k1
```

#### .bashrc에 등록할 alias 설정 
편의를 위해 자주 사용하는 명령어를 alias로 등록한다.

```
citec@k1:~/osh$ tee -a ~/.bashrc <<EOF
> alias k=kubectl
> alias ko='kubectl -n openstack'
> alias kc='kubectl -n ceph'
> alias kr='kubectl -n rook-ceph'
> alias ka='kubectl api-resources'
> alias me='watch "kubectl -n openstack get events --sort-by='{.lastTimestamp}' | tail"'
> alias mp='watch -d "kubectl get pods -A -o wide | grep -v job | grep -e NAME -e ingress"'
> EOF
alias k=kubectl
alias ko='kubectl -n openstack'
alias kc='kubectl -n ceph'
alias kr='kubectl -n rook-ceph'
alias ka='kubectl api-resources'
alias me='watch "kubectl -n openstack get events --sort-by='{.lastTimestamp}' | tail"'
alias mp='watch -d "kubectl get pods -A -o wide | grep -v job | grep -e NAME -e ingress"'
citec@k1:~/osh$ . ~/.bashrc
```

이제, Kubernetes API 리소스들을 확인하려면, ka 명령어를 아래와 같이 수행하면 된다. 
```
citec@k1:~/osh$ ka
NAME                              SHORTNAMES   APIVERSION                        NAMESPACED   KIND
bindings                                       v1                                true         Binding
componentstatuses                 cs           v1                                false        ComponentStatus
configmaps                        cm           v1                                true         ConfigMap
endpoints                         ep           v1                                true         Endpoints
events                            ev           v1                                true         Event
limitranges                       limits       v1                                true         LimitRange
namespaces                        ns           v1                                false        Namespace
nodes                             no           v1                                false        Node
persistentvolumeclaims            pvc          v1                                true         PersistentVolumeClaim
persistentvolumes                 pv           v1                                false        PersistentVolume
pods                              po           v1                                true         Pod
podtemplates                                   v1                                true         PodTemplate
replicationcontrollers            rc           v1                                true         ReplicationController
resourcequotas                    quota        v1                                true         ResourceQuota
secrets                                        v1                                true         Secret
serviceaccounts                   sa           v1                                true         ServiceAccount
services                          svc          v1                                true         Service
mutatingwebhookconfigurations                  admissionregistration.k8s.io/v1   false        MutatingWebhookConfiguration
validatingwebhookconfigurations                admissionregistration.k8s.io/v1   false        ValidatingWebhookConfiguration
customresourcedefinitions         crd,crds     apiextensions.k8s.io/v1           false        CustomResourceDefinition
apiservices                                    apiregistration.k8s.io/v1         false        APIService
controllerrevisions                            apps/v1                           true         ControllerRevision
daemonsets                        ds           apps/v1                           true         DaemonSet
deployments                       deploy       apps/v1                           true         Deployment
replicasets                       rs           apps/v1                           true         ReplicaSet
statefulsets                      sts          apps/v1                           true         StatefulSet
selfsubjectreviews                             authentication.k8s.io/v1          false        SelfSubjectReview
tokenreviews                                   authentication.k8s.io/v1          false        TokenReview
localsubjectaccessreviews                      authorization.k8s.io/v1           true         LocalSubjectAccessReview
selfsubjectaccessreviews                       authorization.k8s.io/v1           false        SelfSubjectAccessReview
selfsubjectrulesreviews                        authorization.k8s.io/v1           false        SelfSubjectRulesReview
subjectaccessreviews                           authorization.k8s.io/v1           false        SubjectAccessReview
horizontalpodautoscalers          hpa          autoscaling/v2                    true         HorizontalPodAutoscaler
cronjobs                          cj           batch/v1                          true         CronJob
jobs                                           batch/v1                          true         Job
certificatesigningrequests        csr          certificates.k8s.io/v1            false        CertificateSigningRequest
leases                                         coordination.k8s.io/v1            true         Lease
bgpconfigurations                              crd.projectcalico.org/v1          false        BGPConfiguration
bgpfilters                                     crd.projectcalico.org/v1          false        BGPFilter
bgppeers                                       crd.projectcalico.org/v1          false        BGPPeer
blockaffinities                                crd.projectcalico.org/v1          false        BlockAffinity
caliconodestatuses                             crd.projectcalico.org/v1          false        CalicoNodeStatus
clusterinformations                            crd.projectcalico.org/v1          false        ClusterInformation
felixconfigurations                            crd.projectcalico.org/v1          false        FelixConfiguration
globalnetworkpolicies                          crd.projectcalico.org/v1          false        GlobalNetworkPolicy
globalnetworksets                              crd.projectcalico.org/v1          false        GlobalNetworkSet
hostendpoints                                  crd.projectcalico.org/v1          false        HostEndpoint
ipamblocks                                     crd.projectcalico.org/v1          false        IPAMBlock
ipamconfigs                                    crd.projectcalico.org/v1          false        IPAMConfig
ipamhandles                                    crd.projectcalico.org/v1          false        IPAMHandle
ippools                                        crd.projectcalico.org/v1          false        IPPool
ipreservations                                 crd.projectcalico.org/v1          false        IPReservation
kubecontrollersconfigurations                  crd.projectcalico.org/v1          false        KubeControllersConfiguration
networkpolicies                                crd.projectcalico.org/v1          true         NetworkPolicy
networksets                                    crd.projectcalico.org/v1          true         NetworkSet
endpointslices                                 discovery.k8s.io/v1               true         EndpointSlice
events                            ev           events.k8s.io/v1                  true         Event
flowschemas                                    flowcontrol.apiserver.k8s.io/v1   false        FlowSchema
prioritylevelconfigurations                    flowcontrol.apiserver.k8s.io/v1   false        PriorityLevelConfiguration
addresspools                                   metallb.io/v1beta1                true         AddressPool
bfdprofiles                                    metallb.io/v1beta1                true         BFDProfile
bgpadvertisements                              metallb.io/v1beta1                true         BGPAdvertisement
bgppeers                                       metallb.io/v1beta2                true         BGPPeer
communities                                    metallb.io/v1beta1                true         Community
ipaddresspools                                 metallb.io/v1beta1                true         IPAddressPool
l2advertisements                               metallb.io/v1beta1                true         L2Advertisement
ingressclasses                                 networking.k8s.io/v1              false        IngressClass
ingresses                         ing          networking.k8s.io/v1              true         Ingress
networkpolicies                   netpol       networking.k8s.io/v1              true         NetworkPolicy
runtimeclasses                                 node.k8s.io/v1                    false        RuntimeClass
poddisruptionbudgets              pdb          policy/v1                         true         PodDisruptionBudget
clusterrolebindings                            rbac.authorization.k8s.io/v1      false        ClusterRoleBinding
clusterroles                                   rbac.authorization.k8s.io/v1      false        ClusterRole
rolebindings                                   rbac.authorization.k8s.io/v1      true         RoleBinding
roles                                          rbac.authorization.k8s.io/v1      true         Role
priorityclasses                   pc           scheduling.k8s.io/v1              false        PriorityClass
csidrivers                                     storage.k8s.io/v1                 false        CSIDriver
csinodes                                       storage.k8s.io/v1                 false        CSINode
csistoragecapacities                           storage.k8s.io/v1                 true         CSIStorageCapacity
storageclasses                    sc           storage.k8s.io/v1                 false        StorageClass
volumeattachments                              storage.k8s.io/v1                 false        VolumeAttachment
```

## Rook Ceph 설치 

Ceph를 Kubernetes에 배포하기 위해 Rook Ceph를 사용한다. Rook는 Ceph 클러스터를 쉽게 관리할 수 있도록 도와주는 오퍼레이터이다. 

각 노드에는 2개의 HDD(`sdb`, `sdc`)가 장착되어있고, 이 둘 모두를 OSD로 사용할 예정이다. 만약 디스크 구성이 다르다면, `install-rook-ceph.yaml` 파일의 "Wipe disks for OSD" 부분을 수정해야 하니 이를 먼저 확인한다.

### 플레이북 실행

```
citec@k1:~/osh$ ansible-playbook -i inventory.yaml install-rook-ceph.yaml 
```

만약 플레이북 실행 시 오류가 발생한다면, 오류의 내용을 더 자세히 확인하기 위해서 `-vvv` 옵션을 추가해 초기화 후 재실행하면 된다.

### Rook-Ceph 초기화 방법

설치에 실패할 경우에는 아래와 같이 `reset_ceph.sh` 스크립트를 실행하여 Rook-Ceph와 관련한 ConfigMap, Secret, CephCluster와 네임스페이스 등을 삭제하고, 디스크를 초기화한다.

```
citec@k1:~/osh$ ./reset_ceph.sh
```

### CephCluster 상태 확인 
```
citec@k1:~/osh$ kubectl -n rook-ceph get cephcluster
NAME        DATADIRHOSTPATH   MONCOUNT   AGE   PHASE   MESSAGE                        HEALTH      EXTERNAL   FSID
rook-ceph   /var/lib/rook     3          19h   Ready   Cluster created successfully   HEALTH_OK              603c8790-369b-40e8-b42e-751a1e771267
```

### 파드 상태 확인
rook-ceph 네임스페이스의 파드 확인 
```
citec@k1:~/osh$ kubectl -n rook-ceph get pods -o wide
NAME                                           READY   STATUS      RESTARTS   AGE   IP               NODE   NOMINATED NODE   READINESS GATES
csi-cephfsplugin-5w7x4                         2/2     Running     0          19h   172.16.2.52      k2     <none>           <none>
csi-cephfsplugin-gx89z                         2/2     Running     0          19h   172.16.2.161     k4     <none>           <none>
csi-cephfsplugin-kn7wz                         2/2     Running     0          19h   172.16.2.149     k1     <none>           <none>
csi-cephfsplugin-provisioner-9dfb4f865-d4f4w   5/5     Running     0          19h   10.244.105.171   k1     <none>           <none>
csi-cephfsplugin-provisioner-9dfb4f865-hh8wp   5/5     Running     0          19h   10.244.195.161   k3     <none>           <none>
csi-cephfsplugin-ww58g                         2/2     Running     0          19h   172.16.2.223     k3     <none>           <none>
csi-rbdplugin-54h25                            2/2     Running     0          19h   172.16.2.223     k3     <none>           <none>
csi-rbdplugin-b7w5l                            2/2     Running     0          19h   172.16.2.149     k1     <none>           <none>
csi-rbdplugin-l297q                            2/2     Running     0          19h   172.16.2.161     k4     <none>           <none>
csi-rbdplugin-provisioner-84864fbf9b-4k4z6     5/5     Running     0          19h   10.244.99.38     k2     <none>           <none>
csi-rbdplugin-provisioner-84864fbf9b-7nwv7     5/5     Running     0          19h   10.244.194.134   k4     <none>           <none>
csi-rbdplugin-tmr2b                            2/2     Running     0          19h   172.16.2.52      k2     <none>           <none>
rook-ceph-crashcollector-k1-554f49567c-9sdsx   1/1     Running     0          19h   10.244.105.175   k1     <none>           <none>
rook-ceph-crashcollector-k2-7cd5c69c64-62c2v   1/1     Running     0          19h   10.244.99.41     k2     <none>           <none>
rook-ceph-crashcollector-k3-59fd6c96b7-4tpm7   1/1     Running     0          19h   10.244.195.165   k3     <none>           <none>
rook-ceph-crashcollector-k4-58fd7f8f4-kmltz    1/1     Running     0          19h   10.244.194.157   k4     <none>           <none>
rook-ceph-exporter-k1-5b8b446944-j7qq8         1/1     Running     0          19h   10.244.105.174   k1     <none>           <none>
rook-ceph-exporter-k2-544cdf9bf-j6wvm          1/1     Running     0          19h   10.244.99.42     k2     <none>           <none>
rook-ceph-exporter-k3-d7df9fb58-xsghl          1/1     Running     0          19h   10.244.195.166   k3     <none>           <none>
rook-ceph-exporter-k4-557cfccc7f-nx9lz         1/1     Running     0          19h   10.244.194.158   k4     <none>           <none>
rook-ceph-mgr-a-7579b8bf97-8c459               1/1     Running     0          19h   10.244.194.155   k4     <none>           <none>
rook-ceph-mon-a-6d68cf7fdc-jpshz               1/1     Running     0          19h   10.244.194.156   k4     <none>           <none>
rook-ceph-mon-b-79d8d4df4c-55lj6               1/1     Running     0          19h   10.244.99.40     k2     <none>           <none>
rook-ceph-mon-c-5cb5674b66-srj74               1/1     Running     0          19h   10.244.105.173   k1     <none>           <none>
rook-ceph-operator-67cff58f8-tdm5h             1/1     Running     0          19h   10.244.194.147   k4     <none>           <none>
rook-ceph-osd-0-7578c848f4-mdxwm               1/1     Running     0          19h   10.244.194.154   k4     <none>           <none>
rook-ceph-osd-1-fcdf76b96-l7v2q                1/1     Running     0          19h   10.244.105.178   k1     <none>           <none>
rook-ceph-osd-2-6f468dd66b-k5kn2               1/1     Running     0          19h   10.244.99.45     k2     <none>           <none>
rook-ceph-osd-3-784f68847f-29f4z               1/1     Running     0          19h   10.244.195.163   k3     <none>           <none>
rook-ceph-osd-4-7969ddb47f-4cwl9               1/1     Running     0          19h   10.244.194.164   k4     <none>           <none>
rook-ceph-osd-5-6f48d55cb7-wq6gn               1/1     Running     0          19h   10.244.105.177   k1     <none>           <none>
rook-ceph-osd-6-bdfcd474d-vw25p                1/1     Running     0          19h   10.244.99.44     k2     <none>           <none>
rook-ceph-osd-7-b8b9b7bc4-wl9sg                1/1     Running     0          19h   10.244.195.164   k3     <none>           <none>
rook-ceph-osd-prepare-k1-7lkhs                 0/1     Completed   0          19h   10.244.105.176   k1     <none>           <none>
rook-ceph-osd-prepare-k2-lrws4                 0/1     Completed   0          19h   10.244.99.43     k2     <none>           <none>
rook-ceph-osd-prepare-k3-8pz8f                 0/1     Completed   0          19h   10.244.195.162   k3     <none>           <none>
rook-ceph-osd-prepare-k4-gw87k                 0/1     Completed   0          19h   10.244.194.159   k4     <none>           <none>
rook-ceph-tools                                1/1     Running     0          19h   10.244.194.165   k4     <none>           <none>
```

### Rook 오퍼레이터 로그 확인
Ceph 클러스터의 상태와 로그를 확인하기 위해 rook-ceph-operator 파드의 로그를 확인한다. -f 옵션을 주면 실시간으로 확인할 수 있다.
```
citec@k1:~/osh$ kubectl -n rook-ceph logs -f rook-ceph-operator-6d97579698-b7bx5
...
2025-04-17 05:38:22.046597 I | op-mon: created/updated IPv4 endpointslice with addresses: [10.96.30.54]
2025-04-17 05:38:22.048556 I | op-mon: waiting for mon quorum with [a]
2025-04-17 05:38:22.240341 I | op-mon: mons running: [a]
2025-04-17 05:38:22.637338 I | ceph-spec: parsing mon endpoints: a=10.96.30.54:6789
2025-04-17 05:38:22.637436 I | op-bucket-prov: ceph bucket provisioner launched watching for provisioner "rook-ceph.ceph.rook.io/bucket"
2025-04-17 05:38:22.637953 I | op-bucket-prov: successfully reconciled bucket provisioner
I0417 05:38:22.638033       1 manager.go:135] "msg"="starting provisioner" "logger"="objectbucket.io/provisioner-manager" "name"="rook-ceph.ceph.rook.io/bucket"
2025-04-17 05:38:24.036844 I | ceph-spec: parsing mon endpoints: a=10.96.30.54:6789
2025-04-17 05:38:24.486174 I | ceph-csi: successfully started CSI Ceph RBD driver
2025-04-17 05:38:24.522296 I | ceph-csi: successfully started CSI CephFS driver
2025-04-17 05:38:24.526137 I | ceph-csi: CSIDriver object updated for driver "rook-ceph.rbd.csi.ceph.com"
2025-04-17 05:38:24.530150 I | ceph-csi: CSIDriver object updated for driver "rook-ceph.cephfs.csi.ceph.com"
2025-04-17 05:38:24.530173 I | op-k8sutil: removing daemonset csi-nfsplugin if it exists
2025-04-17 05:38:24.531960 I | op-k8sutil: removing deployment csi-nfsplugin-provisioner if it exists
2025-04-17 05:38:24.650870 I | ceph-csi: successfully removed CSI NFS driver
2025-04-17 05:38:42.408331 I | op-mon: mons running: [a]
2025-04-17 05:39:02.569810 I | op-mon: mon a is not yet running
2025-04-17 05:39:02.569843 I | op-mon: mons running: []
2025-04-17 05:39:22.737558 I | op-mon: mon a is not yet running
2025-04-17 05:42:04.154773 I | op-mon: mons running: []
2025-04-17 05:42:24.317332 I | op-mon: mon a is not yet running
2025-04-17 05:42:24.317623 I | op-mon: mons running: []
2025-04-17 05:42:44.482419 I | op-mon: mon a is not yet running
2025-04-17 05:42:44.482457 I | op-mon: mons running: []
2025-04-17 05:43:04.658007 I | op-mon: mons running: [a]
2025-04-17 05:43:14.979707 I | op-mon: Monitors in quorum: [a]
2025-04-17 05:43:14.979736 I | op-mon: mons created: 1
```

### Ceph 상태 확인 방법
Rook 환경에서는 모니터 파드에서 직접 ceph -s를 실행하는 대신, Rook 툴박스(Toolbox)를 사용하는 것이 표준이다. 

툴박스에서 Ceph 상태를 확인하려면 아래와 같이 명령을 수행한다.

```
citec@k1:~/osh$ kubectl -n rook-ceph exec -it rook-ceph-tools -- ceph -s
  cluster:
    id:     603c8790-369b-40e8-b42e-751a1e771267
    health: HEALTH_OK

  services:
    mon: 3 daemons, quorum a,b,c (age 19h)
    mgr: a(active, since 19h)
    osd: 8 osds: 8 up (since 19h), 8 in (since 19h)

  data:
    pools:   2 pools, 33 pgs
    objects: 46 objects, 51 MiB
    usage:   839 MiB used, 143 GiB / 144 GiB avail
    pgs:     33 active+clean

citec@k1:~/osh$ kubectl -n rook-ceph exec -it rook-ceph-tools -- ceph osd df
ID  CLASS  WEIGHT   REWEIGHT  SIZE     RAW USE  DATA     OMAP    META     AVAIL    %USE  VAR   PGS  STATUS
 1    hdd  0.01559   1.00000   16 GiB   79 MiB  5.2 MiB   1 KiB   73 MiB   16 GiB  0.48  0.85    8      up
 5    hdd  0.01949   1.00000   20 GiB  111 MiB   10 MiB   1 KiB  101 MiB   20 GiB  0.54  0.95   16      up
 2    hdd  0.01949   1.00000   20 GiB  108 MiB   11 MiB   1 KiB   97 MiB   20 GiB  0.53  0.93   13      up
 6    hdd  0.01559   1.00000   16 GiB   82 MiB  8.2 MiB   1 KiB   73 MiB   16 GiB  0.50  0.88   10      up
 3    hdd  0.01559   1.00000   16 GiB  110 MiB  9.6 MiB   1 KiB  101 MiB   16 GiB  0.67  1.19   12      up
 7    hdd  0.01949   1.00000   20 GiB  114 MiB   13 MiB   1 KiB  101 MiB   20 GiB  0.56  0.98   16      up
 0    hdd  0.01559   1.00000   16 GiB   80 MiB  6.6 MiB   1 KiB   73 MiB   16 GiB  0.49  0.86    7      up
 4    hdd  0.01949   1.00000   20 GiB  154 MiB   14 MiB   1 KiB  140 MiB   20 GiB  0.75  1.33   17      up
                       TOTAL  144 GiB  839 MiB   79 MiB  13 KiB  760 MiB  143 GiB  0.57
MIN/MAX VAR: 0.85/1.33  STDDEV: 0.09
```

### Ceph Alias 등록
Ceph 명령어 수행의 편의를 위해 alias 등록 

```
citec@k1:~$ tee -a ~/.bashrc <<EOF
> alias kceph='kubectl -n rook-ceph exec -it rook-ceph-tools --'
> EOF
alias kceph='kubectl -n rook-ceph exec -it rook-ceph-tools --'
citec@k1:~$ . ~/.bashrc
citec@k1:~/osh$ kceph ceph -s
  cluster:
    id:     603c8790-369b-40e8-b42e-751a1e771267
    health: HEALTH_OK

  services:
    mon: 3 daemons, quorum a,b,c (age 19h)
    mgr: a(active, since 19h)
    osd: 8 osds: 8 up (since 19h), 8 in (since 19h)

  data:
    pools:   2 pools, 33 pgs
    objects: 46 objects, 51 MiB
    usage:   839 MiB used, 143 GiB / 144 GiB avail
    pgs:     33 active+clean

citec@k1:~/osh$ kceph ceph osd tree
ID  CLASS  WEIGHT   TYPE NAME      STATUS  REWEIGHT  PRI-AFF
-1         0.14032  root default
-9         0.03508      host k1
 1    hdd  0.01559          osd.1      up   1.00000  1.00000
 5    hdd  0.01949          osd.5      up   1.00000  1.00000
-5         0.03508      host k2
 2    hdd  0.01949          osd.2      up   1.00000  1.00000
 6    hdd  0.01559          osd.6      up   1.00000  1.00000
-7         0.03508      host k3
 3    hdd  0.01559          osd.3      up   1.00000  1.00000
 7    hdd  0.01949          osd.7      up   1.00000  1.00000
-3         0.03508      host k4
 0    hdd  0.01559          osd.0      up   1.00000  1.00000
 4    hdd  0.01949          osd.4      up   1.00000  1.00000
```

## Kubernetes & Rook-Ceph 설치 완료

여기까지 HA 마스터 클러스터 환경의 Kubernetes와 Rook-Ceph 설치 및 구성을 완료했다. 다음 글에서는 구성된 인프라 환경에서 OpenStack을 설치해보자.
