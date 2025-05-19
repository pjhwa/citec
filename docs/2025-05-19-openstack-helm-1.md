---
title: "OpenStack Helm을 활용한 Kubernetes와 Rook-Ceph 설치 가이드 - 1부"
date: 2025-05-19
tags: [openstack, helm, kubernetes, k8s, rook-ceph, ceph, cloud, install]
---

# OpenStack Helm을 활용한 Kubernetes와 Rook-Ceph 설치 가이드 - 1부

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
    ssh_public_key: "{{ lookup('file', '/home/citec/.ssh/id_rsa.pub') }}"
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

## 결론

이 가이드를 통해 HA 마스터 클러스터 기반의 Kubernetes와 Rook-Ceph 설치를 완료했습니다. 다음 2부에서는 이 환경에 OpenStack을 배포하는 방법을 다룰 예정입니다.
