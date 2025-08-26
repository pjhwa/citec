---
title: "OpenStack Helm을 활용한 Kubernetes와 Rook-Ceph 설치 가이드 - 1부"
date: 2025-05-19
tags: [openstack, helm, kubernetes, k8s, rook-ceph, ceph, cloud, install]
categories: [Howtos, OpenStack]
---


이 문서는 OpenStack Helm을 기반으로 Kubernetes와 Rook-Ceph를 설치하여 OpenStack 환경을 구축하는 과정을 안내합니다. Kubernetes는 컨테이너 오케스트레이션 플랫폼으로, 애플리케이션 배포와 관리를 자동화하며, Rook-Ceph는 Kubernetes에서 분산 스토리지 시스템인 Ceph를 쉽게 관리할 수 있도록 돕는 도구입니다. 이 가이드의 1부에서는 사전 준비와 Kubernetes, Rook-Ceph 설치 및 구성을 다룹니다. 단계별 설명과 함께 명령어, 출력 예시, 그리고 시각적 다이어그램을 제공하여 설치 과정이 직관적이고 명확하게 전달되도록 하였습니다.

---

## 환경

OpenStack Helm 설치를 위해 4개의 가상 머신(VM)을 사용합니다. 각 VM은 Ubuntu 22.04를 기반으로 하며, 아래와 같은 사양과 네트워크 구성을 갖추고 있습니다.

- **운영체제**: Ubuntu 22.04
- **사양**: 4 CPU, 32GB 메모리, 3개의 HDD, 2개의 NIC (VM 네트워크)
- **호스트명 및 IP 주소**:
  - k1: ens160 - 172.16.2.149
  - k2: ens160 - 172.16.2.52
  - k3: ens160 - 172.16.2.223
  - k4: ens160 - 172.16.2.161
- **사용자**: citec (kubectl 및 sudo 권한 보유)
- **참고 자료**: [OpenStack Helm 공식 문서](https://docs.openstack.org/openstack-helm/latest/install/index.html)

### 네트워크 구성 다이어그램

4개의 VM과 그들의 IP 주소를 시각적으로 표현한 다이어그램입니다.

```
[Internet]
     |
  [Router]
     |
  [Switch]
     |
  +---+---+
  |       |
[k1]    [k2]    [k3]    [k4]
  |       |       |       |
172.16.2.149  172.16.2.52  172.16.2.223  172.16.2.161
```

---

## OS 사전 준비 (모든 노드에서 수행)

설치에 앞서 모든 노드에서 운영체제 환경을 설정합니다. 이 과정은 네트워크, 사용자 권한, SSH 연결 등을 준비하여 이후 단계가 원활히 진행되도록 합니다.

### 호스트명 설정

각 노드의 호스트명을 설정하고, IP와 호스트명을 매핑합니다.

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

`citec` 사용자를 `sudoers`에 등록하여 관리 권한을 부여합니다.

```
root@k1:~# echo "citec ALL=(ALL) NOPASSWD:ALL" | tee -a /etc/sudoers.d/citec 
```

### 네트워크 설정

네트워크 인터페이스와 DNS, 시간 동기화를 설정합니다. IPv6을 비활성화하고, 안정적인 네트워크 환경을 구축합니다.

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

### SSH 키 설정 (마스터 노드 k1에서만 실행)

SSH 키를 생성하고, 모든 노드에 배포하여 비밀번호 없이 접속할 수 있도록 설정합니다.

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

설치 중 패키지 업데이트로 인한 간섭을 방지하기 위해 자동 업데이트를 비활성화합니다.

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

클러스터 내부 통신을 원활히 하기 위해 방화벽을 비활성화합니다.

```
citec@k1:~$ sudo systemctl stop ufw
citec@k1:~$ sudo systemctl disable ufw
citec@k1:~$ sudo systemctl status ufw
○ ufw.service - Uncomplicated firewall
     Loaded: loaded (/lib/systemd/system/ufw.service; disabled; vendor preset: enabled)
     Active: inactive (dead)
       Docs: man:ufw(8)
```

---

## 패키지 설치

### 시스템 업데이트 및 필수 패키지 설치 (모든 노드에서 수행)

시스템을 최신 상태로 유지하고, 필요한 도구를 설치합니다.

```
citec@k1:~$ sudo apt update & sudo apt upgrade -y
citec@k1:~$ sudo apt install -y python3-pip git ansible openvswitch
```

---

## Ansible 플레이북 설치 환경 구성 (마스터 노드 k1에서만 실행)

Ansible은 서버 설정을 자동화하는 도구로, 이 섹션에서는 Kubernetes와 Rook-Ceph 설치를 위한 환경을 준비합니다.

### 필요 저장소 복제 및 Ansible 환경 설정

#### 작업 디렉토리 생성 및 이동

```
citec@k1:~$ mkdir ~/osh 
citec@k1:~$ cd ~/osh 
```

#### 저장소 복제

Kubernetes HA 마스터 클러스터와 Rook-Ceph 설치를 지원하도록 수정된 저장소를 복제합니다.

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

Ansible 역할 경로를 환경 변수에 추가합니다.

```
citec@k1:~$ echo "export ANSIBLE_ROLES_PATH=~/osh/openstack-helm/roles" >> ~/.bashrc
citec@k1:~$ . ~/.bashrc 
```

### Ansible 인벤토리 및 플레이북 생성

#### 인벤토리 파일 생성

클러스터 노드의 정보를 정의한 인벤토리 파일을 생성합니다.

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

설치 작업을 정의한 플레이북을 생성합니다.

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

---

## Kubernetes 설치

Kubernetes를 HA(High Availability) 마스터 클러스터로 구성합니다. HA는 여러 마스터 노드를 통해 단일 장애 지점을 제거하고 가용성을 높이는 구조입니다.

### 클러스터 아키텍처 다이어그램

Kubernetes HA 마스터 클러스터와 Rook-Ceph의 구성을 보여주는 다이어그램입니다.

```
[VIP: 172.16.2.148:16443]
         |
  +------+------+
  |             |
[Master: k1]  [Master: k2]  [Master: k3]
  |             |             |
[Worker: k2]  [Worker: k3]  [Worker: k4]
         |
  [Rook-Ceph Cluster]
```

### Keepalived, HAProxy 설치

Keepalived는 VIP(가상 IP)를 관리하여 장애 조치를 지원하고, HAProxy는 마스터 노드 간 부하를 분산합니다.

```
citec@k1:~/osh$ cd osh-hamaster/
citec@k1:~/osh/osh-hamaster$ mv * ~/osh/

citec@k1:~/osh$ ansible-playbook -i inventory.yaml install-keepalived.yaml
citec@k1:~/osh$ ansible-playbook -i inventory.yaml install-haproxy.yaml
```

설치 후 상태를 확인합니다.

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

citec@k1:~/osh$ netstat -tunlp | grep 16443
(Not all processes could be identified, non-owned process info
 will not be shown, you would have to be root to see it all.)
tcp        0      0 172.16.2.148:16443      0.0.0.0:*               LISTEN      -
```

### Kubernetes 플레이북 실행

Kubernetes 설치를 진행합니다.

```
citec@k1:~/osh$ ansible-playbook -i ~/osh/inventory.yaml ~/osh/deploy-env.yaml
```

설치 결과는 다음과 같습니다. `failed=0`이면 성공입니다.

```
PLAY RECAP *************************************************************************************************************
k1                         : ok=93   changed=43   unreachable=0    failed=0    skipped=36   rescued=0    ignored=0
k2                         : ok=58   changed=22   unreachable=0    failed=0    skipped=49   rescued=0    ignored=0
k3                         : ok=58   changed=22   unreachable=0    failed=0    skipped=49   rescued=0    ignored=0
k4                         : ok=58   changed=22   unreachable=0    failed=0    skipped=49   rescued=0    ignored=0
```

### 시스템 초기화 방법

설치 실패 시 초기화 스크립트를 실행합니다.

```
citec@k1:~/osh$ ./reset_script.sh 
citec@k2:~/osh$ ./reset_script.sh 
citec@k3:~/osh$ ./reset_script.sh 
citec@k4:~/osh$ ./reset_script.sh 
```

### Kubernetes 설치 확인

#### 노드 상태 확인

```
citec@k1:~/osh$ kubectl get nodes
NAME   STATUS   ROLES                  AGE   VERSION
k1     Ready    control-plane          23h   v1.33.0
k2     Ready    control-plane,worker   23h   v1.33.0
k3     Ready    control-plane,worker   23h   v1.33.0
k4     Ready    worker                 23h   v1.33.0
```

#### 파드 상태 확인

```
citec@k1:~/osh$ kubectl get pods -A -o wide
NAMESPACE        NAME                                           READY   STATUS      RESTARTS   AGE   IP               NODE   NOMINATED NODE   READINESS GATES
ceph             ingress-nginx-ceph-controller-8wlgb            1/1     Running     0          23h   10.244.105.132   k1     <none>           <none>
kube-system      calico-node-gj295                              1/1     Running     0          23h   172.16.2.223     k3     <none>           <none>
...
```

#### 네임스페이스 확인

```
citec@k1:~/osh$ kubectl get namespaces
NAME              STATUS   AGE
default           Active   119m
kube-system       Active   119m
...
```

#### 컨테이너 상태 확인

```
citec@k1:~/osh$ sudo crictl ps -a
CONTAINER           IMAGE               CREATED             STATE               NAME                       ATTEMPT             POD ID              POD
9c65b0c0288a8       5aa0bf4798fa2       23 hours ago        Running             controller                 0                   742513a8bedd4       ingress-nginx-ceph-controller-8wlgb
...
```

#### Alias 설정

편리한 작업을 위해 alias를 등록합니다.

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
citec@k1:~/osh$ . ~/.bashrc
```

```
citec@k1:~/osh$ ka
NAME                              SHORTNAMES   APIVERSION                        NAMESPACED   KIND
bindings                                       v1                                true         Binding
...
```

---

## Rook-Ceph 설치

Rook-Ceph는 Kubernetes에서 Ceph 스토리지를 관리하는 오퍼레이터로, 각 노드의 HDD를 활용해 분산 스토리지를 구성합니다.

### 플레이북 실행

```
citec@k1:~/osh$ ansible-playbook -i inventory.yaml install-rook-ceph.yaml 
```

### Rook-Ceph 초기화 방법

실패 시 초기화합니다.

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

```
citec@k1:~/osh$ kubectl -n rook-ceph get pods -o wide
NAME                                           READY   STATUS      RESTARTS   AGE   IP               NODE   NOMINATED NODE   READINESS GATES
csi-cephfsplugin-5w7x4                         2/2     Running     0          19h   172.16.2.52      k2     <none>           <none>
...
```

### Rook 오퍼레이터 로그 확인

```
citec@k1:~/osh$ kubectl -n rook-ceph logs -f rook-ceph-operator-6d97579698-b7bx5
...
2025-04-17 05:43:14.979736 I | op-mon: Monitors in quorum: [a]
...
```

### Ceph 상태 확인

Rook 툴박스를 사용해 Ceph 상태를 확인합니다.

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
...
```

### Ceph Alias 등록

```
citec@k1:~$ tee -a ~/.bashrc <<EOF
> alias kceph='kubectl -n rook-ceph exec -it rook-ceph-tools --'
> EOF
citec@k1:~$ . ~/.bashrc
citec@k1:~/osh$ kceph ceph -s
  cluster:
    id:     603c8790-369b-40e8-b42e-751a1e771267
    health: HEALTH_OK
...
```

---

## 상태 확인 

Kubernetes와 Rook-Ceph 설치가 완료되었습니다. 주요 기능들이 제대로 동작하는지 확인하겠습니다.

### 서비스 상태 확인

서비스는 파드에 대한 네트워크 접근을 제공합니다.

```
citec@k1:~/osh$ kubectl get services -A
NAMESPACE        NAME                      TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)                                  AGE
default          kubernetes                ClusterIP      10.96.0.1       <none>           443/TCP                                  12d
kube-system      kube-dns                  ClusterIP      10.96.0.10      <none>           53/UDP,53/TCP,9153/TCP                   12d
metallb-system   metallb-webhook-service   ClusterIP      10.96.48.22     <none>           443/TCP                                  12d
rook-ceph        rook-ceph-exporter        ClusterIP      10.96.162.174   <none>           9926/TCP                                 12d
rook-ceph        rook-ceph-mgr             ClusterIP      10.96.150.232   <none>           9283/TCP                                 12d
rook-ceph        rook-ceph-mgr-dashboard   ClusterIP      10.96.116.126   <none>           7000/TCP                                 12d
rook-ceph        rook-ceph-mon-b           ClusterIP      10.96.105.121   <none>           6789/TCP,3300/TCP                        12d
rook-ceph        rook-ceph-mon-c           ClusterIP      10.96.99.237    <none>           6789/TCP,3300/TCP                        12d
rook-ceph        rook-ceph-mon-d           ClusterIP      10.96.116.1     <none>           6789/TCP,3300/TCP                        6d8h
```

### 컨트롤러 상태 확인

Deployment, StatefulSet, DaemonSet 등의 컨트롤러는 파드의 배포와 관리를 담당합니다.

```
citec@k1:~/osh$ kubectl get deployments -A
NAMESPACE        NAME                           READY   UP-TO-DATE   AVAILABLE   AGE
kube-system      calico-kube-controllers        1/1     1            1           12d
kube-system      coredns                        2/2     2            2           12d
metallb-system   metallb-controller             1/1     1            1           12d
rook-ceph        csi-cephfsplugin-provisioner   2/2     2            2           12d
rook-ceph        csi-rbdplugin-provisioner      2/2     2            2           12d
rook-ceph        rook-ceph-crashcollector-k1    1/1     1            1           12d
rook-ceph        rook-ceph-crashcollector-k2    1/1     1            1           12d
rook-ceph        rook-ceph-crashcollector-k3    1/1     1            1           12d
rook-ceph        rook-ceph-crashcollector-k4    1/1     1            1           12d
rook-ceph        rook-ceph-exporter-k1          1/1     1            1           12d
rook-ceph        rook-ceph-exporter-k2          1/1     1            1           12d
rook-ceph        rook-ceph-exporter-k3          1/1     1            1           12d
rook-ceph        rook-ceph-exporter-k4          1/1     1            1           12d
rook-ceph        rook-ceph-mgr-a                1/1     1            1           12d
rook-ceph        rook-ceph-mon-b                1/1     1            1           12d
rook-ceph        rook-ceph-mon-c                1/1     1            1           12d
rook-ceph        rook-ceph-mon-d                1/1     1            1           6d8h
rook-ceph        rook-ceph-operator             1/1     1            1           12d
rook-ceph        rook-ceph-osd-0                1/1     1            1           12d
rook-ceph        rook-ceph-osd-1                1/1     1            1           12d
rook-ceph        rook-ceph-osd-2                1/1     1            1           12d
rook-ceph        rook-ceph-osd-3                1/1     1            1           12d
rook-ceph        rook-ceph-osd-4                1/1     1            1           12d
rook-ceph        rook-ceph-osd-5                1/1     1            1           12d
rook-ceph        rook-ceph-osd-6                1/1     1            1           12d
rook-ceph        rook-ceph-osd-7                1/1     1            1           12d

citec@k1:~/osh$ kubectl get statefulsets -A
NAMESPACE   NAME                  READY   AGE

citec@k1:~/osh$ kubectl get daemonsets -A
NAMESPACE        NAME                                 DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR                     AGE
ceph             ingress-nginx-ceph-controller        4         4         4       4            4           kubernetes.io/os=linux            12d
kube-system      calico-node                          4         4         4       4            4           kubernetes.io/os=linux            12d
kube-system      kube-proxy                           4         4         4       4            4           kubernetes.io/os=linux            12d
metallb-system   metallb-speaker                      4         4         4       4            4           kubernetes.io/os=linux            12d
rook-ceph        csi-cephfsplugin                     4         4         4       4            4           <none>                            12d
rook-ceph        csi-rbdplugin                        4         4         4       4            4           <none>                            12d
```

확인 사항:
`READY` 열이 원하는 수량과 일치하는지 확인합니다 (예: `1/1`, `3/3`).
`UP-TO-DATE`와 `AVAILABLE` 필드도 정상인지 확인합니다.

#### 이벤트 확인

클러스터에서 발생한 이벤트를 확인하여 오류나 경고를 감지합니다. (참고로, 아래 예는 OpenStack 서비스 설치 시 발생한 이벤트이다.)

```
citec@k1:~/osh$ kubectl get events -A --sort-by='.metadata.creationTimestamp'
NAMESPACE   LAST SEEN   TYPE      REASON              OBJECT                                         MESSAGE
openstack   3s          Normal    SuccessfulCreate    job/nova-service-cleaner-29128740              Created pod: nova-service-cleaner-29128740-9h4r4
openstack   3s          Normal    Scheduled           pod/nova-service-cleaner-29128740-9h4r4        Successfully assigned openstack/nova-service-cleaner-29128740-9h4r4 to k1
openstack   3s          Normal    SuccessfulCreate    cronjob/nova-cell-setup                        Created job nova-cell-setup-29128740
openstack   3s          Normal    SuccessfulCreate    cronjob/nova-service-cleaner                   Created job nova-service-cleaner-29128740
openstack   3s          Normal    Scheduled           pod/nova-cell-setup-29128740-5tgmv             Successfully assigned openstack/nova-cell-setup-29128740-5tgmv to k2
openstack   3s          Normal    SuccessfulCreate    job/nova-cell-setup-29128740                   Created pod: nova-cell-setup-29128740-5tgmv
openstack   2s          Normal    Pulled              pod/nova-service-cleaner-29128740-9h4r4        Container image "quay.io/airshipit/kubernetes-entrypoint:latest-ubuntu_focal" already present on machine
openstack   2s          Normal    Created             pod/nova-service-cleaner-29128740-9h4r4        Created container: init
openstack   2s          Normal    Started             pod/nova-service-cleaner-29128740-9h4r4        Started container init
openstack   2s          Normal    Pulled              pod/nova-cell-setup-29128740-5tgmv             Container image "quay.io/airshipit/kubernetes-entrypoint:latest-ubuntu_focal" already present on machine
openstack   2s          Normal    Created             pod/nova-cell-setup-29128740-5tgmv             Created container: init
openstack   2s          Normal    Started             pod/nova-cell-setup-29128740-5tgmv             Started container init
```

#### 리소스 사용량 확인

노드와 파드의 CPU 및 메모리 사용량을 점검합니다. 이를 위해서 Metrics Server를 설치합니다.

```
citec@k1:~/osh$ kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
serviceaccount/metrics-server created
clusterrole.rbac.authorization.k8s.io/system:aggregated-metrics-reader created
clusterrole.rbac.authorization.k8s.io/system:metrics-server created
rolebinding.rbac.authorization.k8s.io/metrics-server-auth-reader created
clusterrolebinding.rbac.authorization.k8s.io/metrics-server:system:auth-delegator created
clusterrolebinding.rbac.authorization.k8s.io/system:metrics-server created
service/metrics-server created
deployment.apps/metrics-server created
apiservice.apiregistration.k8s.io/v1beta1.metrics.k8s.io created

citec@k1:~/osh$ kubectl get pods -n kube-system | grep metrics-server
metrics-server-6f7dd4c4c4-fbtmb            0/1     Running   0                13s
```

Metrics Server에 `--kubelet-insecure-tls` 플래그를 추가해 인증서 검증을 건너뛰도록 설정합니다.

```
citec@k1:~/osh$ kubectl edit deployment -n kube-system metrics-server
spec:
  template:
    spec:
      containers:
      - args:
        - --cert-dir=/tmp
        - --secure-port=10250
        - --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname
        - --kubelet-use-node-status-port
        - --metric-resolution=15s
        - --kubelet-insecure-tls  # 추가
...
deployment.apps/metrics-server edited
```

노드의 자원 사용률과 각 파드의 자원 사용률을 확인할 수 있습니다.

```
citec@k1:~/osh$ kubectl top nodes
NAME   CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
k1     562m         14%      11763Mi         36%
k2     1009m        25%      9848Mi          30%
k3     439m         10%      8377Mi          26%
k4     208m         5%       4724Mi          14%

citec@k1:~/osh$ kubectl top pods -A
NAMESPACE        NAME                                           CPU(cores)   MEMORY(bytes)
ceph             ingress-nginx-ceph-controller-8wlgb            2m           91Mi
ceph             ingress-nginx-ceph-controller-cdpnl            1m           86Mi
ceph             ingress-nginx-ceph-controller-kchpf            1m           86Mi
ceph             ingress-nginx-ceph-controller-swxdn            2m           87Mi
kube-system      calico-kube-controllers-847c966dfc-7k28r       3m           28Mi
kube-system      calico-node-gj295                              29m          136Mi
kube-system      calico-node-hnm6r                              33m          134Mi
kube-system      calico-node-hzl55                              23m          134Mi
kube-system      calico-node-z5fvz                              40m          133Mi
kube-system      coredns-8d98f4ccd-4pj4v                        2m           15Mi
kube-system      coredns-8d98f4ccd-pz2xf                        2m           16Mi
kube-system      etcd-k1                                        47m          532Mi
kube-system      etcd-k2                                        58m          529Mi
kube-system      etcd-k3                                        40m          530Mi
kube-system      kube-apiserver-k1                              45m          363Mi
kube-system      kube-apiserver-k2                              46m          364Mi
kube-system      kube-apiserver-k3                              51m          473Mi
kube-system      kube-controller-manager-k1                     2m           28Mi
kube-system      kube-controller-manager-k2                     3m           18Mi
kube-system      kube-controller-manager-k3                     15m          79Mi
kube-system      kube-proxy-6wlxh                               1m           17Mi
kube-system      kube-proxy-fsf8h                               1m           26Mi
kube-system      kube-proxy-lmkdp                               1m           16Mi
kube-system      kube-proxy-vxw9t                               1m           17Mi
kube-system      kube-scheduler-k1                              10m          44Mi
kube-system      kube-scheduler-k2                              9m           33Mi
kube-system      kube-scheduler-k3                              8m           36Mi
kube-system      metrics-server-8467fcc7b7-kkn8m                3m           21Mi
metallb-system   metallb-controller-77fb8947dc-kktzd            2m           20Mi
metallb-system   metallb-speaker-84wpw                          18m          71Mi
metallb-system   metallb-speaker-9br2c                          14m          66Mi
metallb-system   metallb-speaker-dk2lr                          11m          67Mi
metallb-system   metallb-speaker-dkdgc                          11m          68Mi
rook-ceph        csi-cephfsplugin-5w7x4                         0m           20Mi
rook-ceph        csi-cephfsplugin-gx89z                         1m           20Mi
rook-ceph        csi-cephfsplugin-kn7wz                         1m           20Mi
rook-ceph        csi-cephfsplugin-provisioner-9dfb4f865-d4f4w   2m           52Mi
rook-ceph        csi-cephfsplugin-provisioner-9dfb4f865-hh8wp   3m           53Mi
rook-ceph        csi-cephfsplugin-ww58g                         1m           20Mi
rook-ceph        csi-rbdplugin-54h25                            1m           27Mi
rook-ceph        csi-rbdplugin-b7w5l                            1m           31Mi
rook-ceph        csi-rbdplugin-l297q                            0m           20Mi
rook-ceph        csi-rbdplugin-provisioner-84864fbf9b-7nwv7     3m           62Mi
rook-ceph        csi-rbdplugin-provisioner-84864fbf9b-krq8v     2m           52Mi
rook-ceph        csi-rbdplugin-tmr2b                            1m           30Mi
rook-ceph        rook-ceph-crashcollector-k1-554f49567c-9sdsx   0m           6Mi
rook-ceph        rook-ceph-crashcollector-k2-7cd5c69c64-2n7l7   0m           6Mi
rook-ceph        rook-ceph-crashcollector-k3-59fd6c96b7-4tpm7   0m           6Mi
rook-ceph        rook-ceph-crashcollector-k4-58fd7f8f4-kmltz    0m           6Mi
rook-ceph        rook-ceph-exporter-k1-5b8b446944-j7qq8         6m           17Mi
rook-ceph        rook-ceph-exporter-k2-544cdf9bf-bgw8t          5m           18Mi
rook-ceph        rook-ceph-exporter-k3-d7df9fb58-xsghl          5m           18Mi
rook-ceph        rook-ceph-exporter-k4-557cfccc7f-nx9lz         3m           18Mi
rook-ceph        rook-ceph-mgr-a-7579b8bf97-nk6zb               20m          593Mi
rook-ceph        rook-ceph-mon-b-79d8d4df4c-fn4jk               49m          437Mi
rook-ceph        rook-ceph-mon-c-5cb5674b66-srj74               23m          427Mi
rook-ceph        rook-ceph-mon-d-c8f9fb97b-xck2c                19m          411Mi
rook-ceph        rook-ceph-operator-67cff58f8-qhgwd             4m           39Mi
rook-ceph        rook-ceph-osd-0-7578c848f4-mdxwm               20m          323Mi
rook-ceph        rook-ceph-osd-1-fcdf76b96-l7v2q                40m          400Mi
rook-ceph        rook-ceph-osd-2-6f468dd66b-znczr               30m          685Mi
rook-ceph        rook-ceph-osd-3-784f68847f-29f4z               27m          721Mi
rook-ceph        rook-ceph-osd-4-7969ddb47f-4cwl9               24m          671Mi
rook-ceph        rook-ceph-osd-5-6f48d55cb7-wq6gn               26m          773Mi
rook-ceph        rook-ceph-osd-6-bdfcd474d-7dgrq                31m          839Mi
rook-ceph        rook-ceph-osd-7-b8b9b7bc4-wl9sg                24m          699Mi
rook-ceph        rook-ceph-tools                                0m           8Mi
```

#### API 서버 상태 확인

Kubernetes API 서버가 정상적으로 응답하는지 확인합니다.

```
citec@k1:~/osh$ kubectl cluster-info
Kubernetes control plane is running at https://172.16.2.148:16443
CoreDNS is running at https://172.16.2.148:16443/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy

To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.
```

#### DNS 서비스 확인

클러스터 내부 DNS가 정상적으로 작동하는지 확인합니다.

```
citec@k1:~/osh$ kubectl get pods -n kube-system -l k8s-app=kube-dns
NAME                      READY   STATUS    RESTARTS   AGE
coredns-8d98f4ccd-4pj4v   1/1     Running   0          30h
coredns-8d98f4ccd-pz2xf   1/1     Running   0          30h
```

DNS 파드가 `Running` 상태인지 확인합니다.

DNS 쿼리 테스트 방법: kubectl exec -it <pod-name> -n <namespace> -- nslookup kubernetes.default.svc.cluster.local

```
citec@k1:~/osh$ kubectl get pods -A
NAMESPACE        NAME                                           READY   STATUS                  RESTARTS         AGE
ceph             ingress-nginx-ceph-controller-8wlgb            1/1     Running                 4 (3d10h ago)    12d
ceph             ingress-nginx-ceph-controller-cdpnl            1/1     Running                 7                12d
ceph             ingress-nginx-ceph-controller-kchpf            1/1     Running                 4 (8d ago)       12d
ceph             ingress-nginx-ceph-controller-swxdn            1/1     Running                 0                12d
kube-system      calico-kube-controllers-847c966dfc-7k28r       1/1     Running                 69 (33h ago)     12d
kube-system      calico-node-gj295                              1/1     Running                 0                12d
...

citec@k1:~/osh$ kubectl exec -it ingress-nginx-ceph-controller-8wlgb -n ceph -- /bin/sh
/etc/nginx $ nslookup kubernetes.default.svc.cluster.local
Server:         10.96.0.10
Address:        10.96.0.10:53

Name:   kubernetes.default.svc.cluster.local
Address: 10.96.0.1
```

#### PersistentVolume 및 PersistentVolumeClaim 확인

스토리지가 정상적으로 할당되고 사용 중인지 확인합니다. 아래 예시는 OpenStack 서비스를 설치한 후에 생성된 PV, PVC를 확인하는 것입니다. PVC가 PV에 바인딩되어 있는지 (`STATUS`가 `Bound`) 확인합니다.

```
citec@k1:~/osh$ kubectl get pv -A
NAME                                       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                                         STORAGECLASS      VOLUMEATTRIBUTESCLASS   REASON   AGE
pvc-24a399d2-2906-4a04-9ebf-bf9475d77b89   5Gi        RWO            Delete           Bound    openstack/mysql-data-mariadb-server-0         rook-ceph-block   <unset>                          11d
pvc-ad0337fc-8c51-4c05-aaa7-aba599770f8f   768Mi      RWO            Delete           Bound    openstack/rabbitmq-data-rabbitmq-rabbitmq-0   rook-ceph-block   <unset>                          11d

citec@k1:~/osh$ kubectl get pvc -A
NAMESPACE   NAME                                STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS      VOLUMEATTRIBUTESCLASS   AGE
openstack   mysql-data-mariadb-server-0         Bound    pvc-24a399d2-2906-4a04-9ebf-bf9475d77b89   5Gi        RWO            rook-ceph-block   <unset>                 11d
openstack   rabbitmq-data-rabbitmq-rabbitmq-0   Bound    pvc-ad0337fc-8c51-4c05-aaa7-aba599770f8f   768Mi      RWO            rook-ceph-block   <unset>                 11d
```

---
## 결론

이 가이드를 통해 HA 마스터 클러스터 기반의 Kubernetes와 Rook-Ceph 설치를 완료했습니다. 다음 2부에서는 이 환경에 OpenStack을 배포하는 방법을 다룰 예정입니다.
