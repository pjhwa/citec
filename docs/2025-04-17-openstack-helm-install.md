---
title: "OpenStack Helm 설치 (Ansible 활용)"
date: 2025-04-17
tags: [openstack, helm, kubernetes, ansible]
---

# OpenStack Helm 설치 (Ansible 활용)

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

### 시스템 업데이트 및 필수 패키지 설치 

```
citec@k1:~$ sudo apt update & sudo apt upgrade -y
citec@k1:~$ sudo apt install -y python3-pip git ansible 
```

### 필요 저장소 복제 및 Ansible 환경 설정

```
# 작업 디렉토리 생성 및 이동
citec@k1:~$ mkdir ~/osh 
citec@k1:~$ cd ~/osh 

# 저장소 복제 
citec@k1:~/osh$ git clone https://opendev.org/openstack/openstack-helm.git
Cloning into 'openstack-helm'...
remote: Enumerating objects: 81894, done.
remote: Counting objects: 100% (31212/31212), done.
remote: Compressing objects: 100% (12814/12814), done.
remote: Total 81894 (delta 29497), reused 18398 (delta 18398), pack-reused 50682
Receiving objects: 100% (81894/81894), 13.22 MiB | 1.83 MiB/s, done.
Resolving deltas: 100% (59571/59571), done.

citec@k1:~/osh$ git clone https://opendev.org/openstack/openstack-helm-infra.git
Cloning into 'openstack-helm-infra'...
remote: Enumerating objects: 35634, done.
remote: Counting objects: 100% (20981/20981), done.
remote: Compressing objects: 100% (9331/9331), done.
remote: Total 35634 (delta 19671), reused 11650 (delta 11650), pack-reused 14653
Receiving objects: 100% (35634/35634), 5.62 MiB | 1.78 MiB/s, done.
Resolving deltas: 100% (24811/24811), done.

citec@k1:~/osh$ git clone https://opendev.org/zuul/zuul-jobs.git
Cloning into 'zuul-jobs'...
remote: Enumerating objects: 18937, done.
remote: Counting objects: 100% (9375/9375), done.
remote: Compressing objects: 100% (4057/4057), done.
remote: Total 18937 (delta 8474), reused 5318 (delta 5318), pack-reused 9562
Receiving objects: 100% (18937/18937), 2.83 MiB | 1.73 MiB/s, done.
Resolving deltas: 100% (10789/10789), done.

# ANSIBLE_ROLES_PATH 설정 
citec@k1:~$ echo "export ANSIBLE_ROLES_PATH=~/osh/openstack-helm-infra/roles:~/osh/zuul-jobs/roles" >> ~/.bashrc
citec@k1:~$ . ~/.bashrc 
```

### Ansible 인벤토리 및 플레이북 생성

#### SSH Public Key를 인벤토리 파일에서 설정

```
citec@k1:~/osh$ cat ~/.ssh/id_rsa.pub
ssh-rsa AAAAB...0Z9rQ8Q== citec@k1
```

#### 인벤토리 파일 생성

```
citec@k1:~/osh$ tee inventory.yaml <<EOF
---
all:
  vars:
    ansible_port: 22
    ansible_user: citec
    ansible_ssh_private_key_file: /home/citec/.ssh/id_rsa
    ansible_ssh_extra_args: -o StrictHostKeyChecking=no
    ssh_public_key: "ssh-rsa AAAAB...0Z9rQ8Q== citec@k1"
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
  children:
    primary:
      hosts:
        k1:
          ansible_host: 172.16.2.149
    k8s_cluster:
      hosts:
        k1:
          ansible_host: 172.16.2.149
        k2:
          ansible_host: 172.16.2.52
        k3:
          ansible_host: 172.16.2.223
        k4:
          ansible_host: 172.16.2.161
    k8s_control_plane:
      hosts:
        k1:
          ansible_host: 172.16.2.149
    k8s_nodes:
      hosts:
        k2:
          ansible_host: 172.16.2.52
        k3:
          ansible_host: 172.16.2.223
        k4:
          ansible_host: 172.16.2.161
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

### 수정이 필요한 플레이북 (openstack-helm-infra)

아래 파일들에 대해 해당 내용을 수정 또는 추가, 삭제해야 에러없이 Ansible 수행이 가능하다.

#### ~/osh/openstack-helm-infra/roles/deploy-env/tasks/prerequisites.yaml
```
- name: Remove existing Kubernetes repository files
  file:
    path: /etc/apt/sources.list.d/kubernetes.list
    state: absent

- name: Add Kubernetes apt repository key
  shell: |
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  args:
    creates: /etc/apt/keyrings/kubernetes-apt-keyring.gpg

- name: Add Kubernetes apt repository
  apt_repository:
    repo: "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /"
    state: present
    filename: kubernetes
```

#### ~/osh/openstack-helm-infra/roles/deploy-env/tasks/containerd.yaml
```
- name: Remove existing Docker repository files
  file:
    path: /etc/apt/sources.list.d/docker.list
    state: absent

- name: Remove conflicting Docker key
  file:
    path: /etc/apt/trusted.gpg.d/docker.gpg
    state: absent

- name: Add Docker apt repository key
  apt_key:
    url: https://download.docker.com/linux/ubuntu/gpg
    ...
```

#### ~/osh/openstack-helm-infra/roles/deploy-env/tasks/loopback_devices.yaml 
```
- name: Create loop device image
  shell: |
    mkdir -p {{ loopback_image | dirname }}
    truncate -s {{ loopback_image_size }} {{ loopback_image }}

- name: Check if loop device exists
  stat:
    path: /dev/loop100
  register: loop_device_stat

- name: Create loop device
  command: mknod /dev/loop100 b $(grep loop /proc/devices | cut -c3) 100
  when: not loop_device_stat.stat.exists

    #- name: Create loop device
    #  shell: |
    #    mknod {{ loopback_device }} b $(grep loop /proc/devices | cut -c3) {{ loopback_device | regex_search('[0-9]+') }}
```

#### ~/osh/openstack-helm-infra/roles/deploy-env/tasks/client_cluster_ssh.yaml
```
- name: Setup ssh keys
  become_user: "{{ client_ssh_user }}"
  block:
    - name: Generate ssh key pair
      shell: |
        ssh-keygen -t ed25519 -q -N "" -f {{ client_user_home_directory }}/.ssh/id_ed25519
      args:
        creates: "{{ client_user_home_directory }}/.ssh/id_ed25519.pub"
      when: inventory_hostname in (groups['primary'] | default([]))

    - name: Read ssh public key
      command: cat "{{ client_user_home_directory }}/.ssh/id_ed25519.pub"
      register: ssh_public_key
      when: inventory_hostname in (groups['primary'] | default([]))

- name: Setup passwordless ssh from primary and cluster nodes
  become_user: "{{ cluster_ssh_user }}"
  block:
    - name: Set primary ssh public key
      set_fact:
        client_ssh_public_key: "{{ hostvars[groups['primary'][0]]['ssh_public_key']['stdout'] }}"
      when:
        - groups['primary'] | default([]) | length > 0
        - inventory_hostname in (groups['k8s_cluster'] | default([]))
  ...
    - name: Disable strict host key checking
      template:
        src: "files/ssh_config"
        dest: "{{ client_user_home_directory }}/.ssh/config"
        owner: "{{ client_ssh_user }}"
        mode: 0644
        backup: true
      when: inventory_hostname in (groups['primary'] | default([]))
...
```

#### ~/osh/openstack-helm-infra/roles/deploy-env/tasks/k8s_common.yaml
```
- name: Configure sysctl
  sysctl:
    name: "{{ item }}"
    value: "1"
    state: present
  loop:
    - net.bridge.bridge-nf-call-iptables
    - net.bridge.bridge-nf-call-ip6tables
    - net.ipv4.ip_forward
  ignore_errors: true

- name: Check if IPv6 is enabled
  stat:
    path: /proc/sys/net/ipv6
  register: ipv6_enabled

- name: Configure sysctl for IPv6
  sysctl:
    name: "{{ item }}"
    value: "1"
    state: present
    reload: yes
  when: ipv6_enabled.stat.exists
  loop:
    - net.ipv6.conf.default.disable_ipv6
    - net.ipv6.conf.all.disable_ipv6
    - net.ipv6.conf.lo.disable_ipv6

...
- name: Install Kubernetes binaries
  apt:
    name:
      - kubelet
      - kubeadm
      - kubectl
    state: present

(Disable unbound 섹션은 삭제)
```

#### ~/osh/openstack-helm-infra/roles/deploy-env/tasks/k8s_client.yaml
```
- name: Install Kubectl
  apt:
    name: kubectl
    state: present

...
(Install osh helm plugin 섹션 삭제, 아래 추가)
    - name: Check if OSH Helm plugin is installed
      shell: helm plugin list | grep osh || true
      register: osh_plugin_check
      ignore_errors: true

    - name: Install OSH Helm plugin
      command: helm plugin install https://opendev.org/openstack/openstack-helm-plugin.git
      when: osh_plugin_check.stdout == ""

    # This is to improve build time
    - name: Check if stable Helm repo exists
      command: helm repo list
      register: stable_repo_check
      changed_when: false
      failed_when: false

    - name: Remove stable Helm repo
      command: helm repo remove stable
      when: "'stable' in stable_repo_check.stdout"
```

## Kubernetes 설치 

### 플레이북 실행

수정이 필요한 플레이북들을 모두 수정했다면, 아래의 명령을 실행하여 Kubernetes 설치를 진행한다.

```
citec@k1:~/osh$ ansible-playbook -i ~/osh/inventory.yaml ~/osh/deploy-env.yaml
```

실행 결과는 아래와 유사하다. 실행하는 환경에 따라서, 여러번 수행할 때마다 조금씩 달라지긴 하지만, 모든 노드에 대해서 failed는 0이어야 한다.

```
PLAY [all] *************************************************************************************************************

TASK [Gathering Facts] *************************************************************************************************
[WARNING]: Platform linux on host k1 is using the discovered Python interpreter at /usr/bin/python3.10, but future
installation of another Python interpreter could change the meaning of that path. See https://docs.ansible.com/ansible-
core/2.17/reference_appendices/interpreter_discovery.html for more information.
ok: [k1]
[WARNING]: Platform linux on host k2 is using the discovered Python interpreter at /usr/bin/python3.10, but future
installation of another Python interpreter could change the meaning of that path. See https://docs.ansible.com/ansible-
core/2.17/reference_appendices/interpreter_discovery.html for more information.
ok: [k2]
[WARNING]: Platform linux on host k4 is using the discovered Python interpreter at /usr/bin/python3.10, but future
installation of another Python interpreter could change the meaning of that path. See https://docs.ansible.com/ansible-
core/2.17/reference_appendices/interpreter_discovery.html for more information.
ok: [k4]
[WARNING]: Platform linux on host k3 is using the discovered Python interpreter at /usr/bin/python3.10, but future
installation of another Python interpreter could change the meaning of that path. See https://docs.ansible.com/ansible-
core/2.17/reference_appendices/interpreter_discovery.html for more information.
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

TASK [ensure-python : Pull in venv package] ****************************************************************************
skipping: [k1]
skipping: [k2]
skipping: [k3]
skipping: [k4]

TASK [ensure-python : Set default RPM package name] ********************************************************************
skipping: [k1]
skipping: [k2]
skipping: [k3]
skipping: [k4]

TASK [ensure-python : Set RPM package name for CentOS/RHEL 9 and Python 3.9] *******************************************
skipping: [k1]
skipping: [k2]
skipping: [k3]
skipping: [k4]

TASK [ensure-python : Install RPM package] *****************************************************************************
skipping: [k1]
skipping: [k2]
skipping: [k3]
skipping: [k4]

TASK [ensure-python : Install python using pyenv] **********************************************************************
skipping: [k1]
skipping: [k2]
skipping: [k3]
skipping: [k4]

TASK [ensure-python : Activate python using stow] **********************************************************************
skipping: [k1]
skipping: [k2]
skipping: [k3]
skipping: [k4]

TASK [ensure-pip : Check if pip is installed] **************************************************************************
changed: [k4]
changed: [k3]
changed: [k1]
changed: [k2]

TASK [ensure-pip : Install pip from packages] **************************************************************************
skipping: [k1] => (item=/home/citec/osh/zuul-jobs/roles/ensure-pip/tasks/Debian.yaml)
skipping: [k2] => (item=/home/citec/osh/zuul-jobs/roles/ensure-pip/tasks/Debian.yaml)
skipping: [k1]
skipping: [k3] => (item=/home/citec/osh/zuul-jobs/roles/ensure-pip/tasks/Debian.yaml)
skipping: [k2]
skipping: [k3]
skipping: [k4] => (item=/home/citec/osh/zuul-jobs/roles/ensure-pip/tasks/Debian.yaml)
skipping: [k4]

TASK [ensure-pip : Ensure setuptools] **********************************************************************************
skipping: [k1]
skipping: [k2]
skipping: [k3]
skipping: [k4]

TASK [ensure-pip : Check for ensurepip module] *************************************************************************
changed: [k2]
changed: [k1]
changed: [k3]
changed: [k4]

TASK [ensure-pip : Ensure python3-venv] ********************************************************************************
skipping: [k1]
skipping: [k2]
skipping: [k3]
skipping: [k4]

TASK [ensure-pip : Install pip from source] ****************************************************************************
skipping: [k1]
skipping: [k2]
skipping: [k3]
skipping: [k4]

TASK [ensure-pip : Probe for venv python full path] ********************************************************************
changed: [k1]
changed: [k2]
changed: [k4]
changed: [k3]

TASK [ensure-pip : Set host default] ***********************************************************************************
ok: [k1]
ok: [k2]
ok: [k3]
ok: [k4]

TASK [ensure-pip : Set ensure_pip_virtualenv_command] ******************************************************************
ok: [k1]
ok: [k2]
ok: [k3]
ok: [k4]

TASK [clear-firewall : Clear iptables rules] ***************************************************************************
changed: [k1]
changed: [k2]
changed: [k3]
changed: [k4]

TASK [deploy-env : Include prerequisites tasks] ************************************************************************
included: /home/citec/osh/openstack-helm-infra/roles/deploy-env/tasks/prerequisites.yaml for k1, k2, k3, k4

TASK [deploy-env : Remove existing Kubernetes repository files] ********************************************************
changed: [k4]
changed: [k2]
changed: [k1]
changed: [k3]

TASK [deploy-env : Add Kubernetes apt repository key] ******************************************************************
ok: [k2]
ok: [k3]
ok: [k1]
ok: [k4]

TASK [deploy-env : Add Kubernetes apt repository] **********************************************************************
changed: [k3]
changed: [k1]
changed: [k4]
changed: [k2]

TASK [deploy-env : Install necessary packages] *************************************************************************
ok: [k2]
ok: [k1]
ok: [k4]
ok: [k3]

TASK [deploy-env : Configure /etc/hosts] *******************************************************************************
[DEPRECATION WARNING]: Filter "ansible.netcommon.ipaddr" has been deprecated. Use 'ansible.utils.ipaddr' module
instead. This feature will be removed from ansible.netcommon in a release after 2024-01-01. Deprecation warnings can be
 disabled by setting deprecation_warnings=False in ansible.cfg.
ok: [k2]
ok: [k4]
ok: [k1]
ok: [k3]

TASK [deploy-env : Loop devices] ***************************************************************************************
included: /home/citec/osh/openstack-helm-infra/roles/deploy-env/tasks/loopback_devices.yaml for k1, k2, k3, k4

TASK [deploy-env : Create loop device image] ***************************************************************************
changed: [k2]
changed: [k1]
changed: [k3]
changed: [k4]

TASK [deploy-env : Check if loop device exists] ************************************************************************
ok: [k1]
ok: [k2]
ok: [k3]
ok: [k4]

TASK [deploy-env : Create loop device] *********************************************************************************
skipping: [k1]
skipping: [k2]
skipping: [k3]
skipping: [k4]

TASK [deploy-env : Create loop-setup systemd unit] *********************************************************************
ok: [k1]
ok: [k2]
ok: [k4]
ok: [k3]

TASK [deploy-env : Systemd reload] *************************************************************************************
changed: [k2]
changed: [k4]
changed: [k3]
changed: [k1]

TASK [deploy-env : Configure loop-setup systemd unit] ******************************************************************
ok: [k3]
ok: [k1]
ok: [k2]
ok: [k4]

TASK [deploy-env : Check /dev/loop100 is attached] *********************************************************************
changed: [k1]
changed: [k3]
changed: [k2]
changed: [k4]

TASK [deploy-env : Deploy Containerd] **********************************************************************************
included: /home/citec/osh/openstack-helm-infra/roles/deploy-env/tasks/containerd.yaml for k1, k2, k3, k4

TASK [deploy-env : Remove old docker packages] *************************************************************************
ok: [k2]
ok: [k1]
ok: [k3]
ok: [k4]

TASK [deploy-env : Remove existing Docker repository files] ************************************************************
changed: [k1]
changed: [k2]
changed: [k3]
changed: [k4]

TASK [deploy-env : Remove conflicting Docker key] **********************************************************************
changed: [k1]
changed: [k2]
changed: [k3]
changed: [k4]

TASK [deploy-env : Add Docker apt repository key] **********************************************************************
changed: [k3]
changed: [k4]
changed: [k2]
changed: [k1]

TASK [deploy-env : Get dpkg arch] **************************************************************************************
changed: [k1]
changed: [k2]
changed: [k3]
changed: [k4]

TASK [deploy-env : Add Docker apt repository] **************************************************************************
changed: [k2]
changed: [k3]
changed: [k4]
changed: [k1]

TASK [deploy-env : Install docker packages] ****************************************************************************
ok: [k2]
ok: [k1]
ok: [k3]
ok: [k4]

TASK [deploy-env : Add users to docker group] **************************************************************************
changed: [k2] => (item=citec)
changed: [k1] => (item=citec)
changed: [k3] => (item=citec)
changed: [k4] => (item=citec)

TASK [deploy-env : Reset ssh connection to apply user changes.] ********************************************************

TASK [deploy-env : Reset ssh connection to apply user changes.] ********************************************************

TASK [deploy-env : Reset ssh connection to apply user changes.] ********************************************************

TASK [deploy-env : Reset ssh connection to apply user changes.] ********************************************************

TASK [deploy-env : Install Crictl] *************************************************************************************
changed: [k3]
changed: [k4]
changed: [k1]
changed: [k2]

TASK [deploy-env : Set registry_mirror fact] ***************************************************************************
skipping: [k1]
skipping: [k2]
skipping: [k3]
skipping: [k4]

TASK [deploy-env : Set insecure_registries fact for Docker] ************************************************************
skipping: [k1]
skipping: [k2]
skipping: [k3]
skipping: [k4]

TASK [deploy-env : Set registry_namespaces fact] ***********************************************************************
skipping: [k1]
skipping: [k2]
skipping: [k3]
skipping: [k4]

TASK [deploy-env : Init registry_namespaces if not defined] ************************************************************
ok: [k1]
ok: [k2]
ok: [k3]
ok: [k4]

TASK [deploy-env : Buildset registry alias] ****************************************************************************
skipping: [k1]
skipping: [k2]
skipping: [k3]
skipping: [k4]

TASK [deploy-env : Write buildset registry TLS certificate] ************************************************************
skipping: [k1]
skipping: [k2]
skipping: [k3]
skipping: [k4]

TASK [deploy-env : Update CA certs] ************************************************************************************
skipping: [k1]
skipping: [k2]
skipping: [k3]
skipping: [k4]

TASK [deploy-env : Set buildset registry namespace] ********************************************************************
skipping: [k1]
skipping: [k2]
skipping: [k3]
skipping: [k4]

TASK [deploy-env : Append buildset_registry to registry namespaces] ****************************************************
skipping: [k1]
skipping: [k2]
skipping: [k3]
skipping: [k4]

TASK [deploy-env : Configure containerd] *******************************************************************************
ok: [k1]
ok: [k2]
ok: [k3]
ok: [k4]

TASK [deploy-env : Create containerd config directory hierarchy] *******************************************************
ok: [k1]
ok: [k2]
ok: [k3]
ok: [k4]

TASK [deploy-env : Create host namespace directory] ********************************************************************
skipping: [k1]
skipping: [k2]
skipping: [k3]
skipping: [k4]

TASK [deploy-env : Create hosts.toml file] *****************************************************************************
skipping: [k1]
skipping: [k2]
skipping: [k3]
skipping: [k4]

TASK [deploy-env : Restart containerd] *********************************************************************************
changed: [k2]
changed: [k4]
changed: [k1]
changed: [k3]

TASK [deploy-env : Configure Docker daemon] ****************************************************************************
ok: [k1]
ok: [k3]
ok: [k4]
ok: [k2]

TASK [deploy-env : Restart docker] *************************************************************************************
changed: [k2]
changed: [k4]
changed: [k1]
changed: [k3]

TASK [deploy-env : Include K8s common tasks] ***************************************************************************
included: /home/citec/osh/openstack-helm-infra/roles/deploy-env/tasks/k8s_common.yaml for k1, k2, k3, k4

TASK [deploy-env : Load necessary modules] *****************************************************************************
ok: [k1] => (item=overlay)
ok: [k3] => (item=overlay)
ok: [k1] => (item=br_netfilter)
ok: [k3] => (item=br_netfilter)
ok: [k2] => (item=overlay)
ok: [k4] => (item=overlay)
ok: [k2] => (item=br_netfilter)
ok: [k4] => (item=br_netfilter)

TASK [deploy-env : Configure sysctl] ***********************************************************************************
ok: [k2] => (item=net.bridge.bridge-nf-call-iptables)
ok: [k4] => (item=net.bridge.bridge-nf-call-iptables)
ok: [k1] => (item=net.bridge.bridge-nf-call-iptables)
ok: [k3] => (item=net.bridge.bridge-nf-call-iptables)
ok: [k4] => (item=net.bridge.bridge-nf-call-ip6tables)
ok: [k1] => (item=net.bridge.bridge-nf-call-ip6tables)
ok: [k2] => (item=net.bridge.bridge-nf-call-ip6tables)
ok: [k3] => (item=net.bridge.bridge-nf-call-ip6tables)
ok: [k2] => (item=net.ipv4.ip_forward)
ok: [k1] => (item=net.ipv4.ip_forward)
ok: [k4] => (item=net.ipv4.ip_forward)
ok: [k3] => (item=net.ipv4.ip_forward)

TASK [deploy-env : Check if IPv6 is enabled] ***************************************************************************
ok: [k1]
ok: [k2]
ok: [k4]
ok: [k3]

TASK [deploy-env : Configure sysctl for IPv6] **************************************************************************
skipping: [k1] => (item=net.ipv6.conf.default.disable_ipv6)
skipping: [k1] => (item=net.ipv6.conf.all.disable_ipv6)
skipping: [k1] => (item=net.ipv6.conf.lo.disable_ipv6)
skipping: [k2] => (item=net.ipv6.conf.default.disable_ipv6)
skipping: [k2] => (item=net.ipv6.conf.all.disable_ipv6)
skipping: [k2] => (item=net.ipv6.conf.lo.disable_ipv6)
skipping: [k1]
skipping: [k3] => (item=net.ipv6.conf.default.disable_ipv6)
skipping: [k3] => (item=net.ipv6.conf.all.disable_ipv6)
skipping: [k3] => (item=net.ipv6.conf.lo.disable_ipv6)
skipping: [k2]
skipping: [k3]
skipping: [k4] => (item=net.ipv6.conf.default.disable_ipv6)
skipping: [k4] => (item=net.ipv6.conf.all.disable_ipv6)
skipping: [k4] => (item=net.ipv6.conf.lo.disable_ipv6)
skipping: [k4]

TASK [deploy-env : Configure number of inotify instances] **************************************************************
ok: [k1]
ok: [k2]
ok: [k3]
ok: [k4]

TASK [deploy-env : Configure number of inotify instances] **************************************************************
ok: [k2] => (item=net.ipv4.conf.all.rp_filter)
ok: [k3] => (item=net.ipv4.conf.all.rp_filter)
ok: [k1] => (item=net.ipv4.conf.all.rp_filter)
ok: [k2] => (item=net.ipv4.conf.default.rp_filter)
ok: [k3] => (item=net.ipv4.conf.default.rp_filter)
ok: [k1] => (item=net.ipv4.conf.default.rp_filter)
ok: [k4] => (item=net.ipv4.conf.all.rp_filter)
ok: [k4] => (item=net.ipv4.conf.default.rp_filter)

TASK [deploy-env : Remove swapfile from /etc/fstab] ********************************************************************
ok: [k4] => (item=swap)
ok: [k3] => (item=swap)
ok: [k2] => (item=swap)
ok: [k1] => (item=swap)
ok: [k4] => (item=none)
ok: [k2] => (item=none)
ok: [k3] => (item=none)
ok: [k1] => (item=none)

TASK [deploy-env : Disable swap] ***************************************************************************************
skipping: [k1]
skipping: [k2]
skipping: [k3]
skipping: [k4]

TASK [deploy-env : Install Kubernetes binaries] ************************************************************************
ok: [k2]
ok: [k1]
ok: [k3]
ok: [k4]

TASK [deploy-env : Restart kubelet] ************************************************************************************
changed: [k2]
changed: [k4]
changed: [k1]
changed: [k3]

TASK [deploy-env : Configure resolv.conf] ******************************************************************************
ok: [k1]
ok: [k3]
ok: [k2]
ok: [k4]

TASK [deploy-env : Disable systemd-resolved] ***************************************************************************
ok: [k1]
ok: [k3]
ok: [k2]
ok: [k4]

TASK [deploy-env : Include K8s control-plane tasks] ********************************************************************
skipping: [k2]
skipping: [k3]
skipping: [k4]
included: /home/citec/osh/openstack-helm-infra/roles/deploy-env/tasks/k8s_control_plane.yaml for k1

TASK [deploy-env : Mount tmpfs to /var/lib/etcd] ***********************************************************************
ok: [k1]

TASK [deploy-env : Prepare kubeadm config] *****************************************************************************
ok: [k1]

TASK [deploy-env : Initialize the Kubernetes cluster using kubeadm] ****************************************************
changed: [k1]

TASK [deploy-env : Generate join command] ******************************************************************************
changed: [k1]

TASK [deploy-env : Copy kube config to localhost] **********************************************************************
changed: [k1]

TASK [deploy-env : Join workload nodes to cluster] *********************************************************************
skipping: [k1]
changed: [k2]
changed: [k4]
changed: [k3]

TASK [deploy-env : Include K8s client tasks] ***************************************************************************
skipping: [k2]
skipping: [k3]
skipping: [k4]
included: /home/citec/osh/openstack-helm-infra/roles/deploy-env/tasks/k8s_client.yaml for k1

TASK [deploy-env : Install Kubectl] ************************************************************************************
ok: [k1]

TASK [deploy-env : Set user home directory] ****************************************************************************
ok: [k1]

TASK [deploy-env : Set root home directory] ****************************************************************************
skipping: [k1]

TASK [deploy-env : Setup kubeconfig directory for citec user] **********************************************************
changed: [k1]

TASK [deploy-env : Copy kube_config file for citec user] ***************************************************************
changed: [k1]

TASK [deploy-env : Set kubconfig file ownership for citec user] ********************************************************
changed: [k1]

TASK [deploy-env : Install Helm] ***************************************************************************************
changed: [k1]

TASK [deploy-env : Check if OSH Helm plugin is installed] **************************************************************
changed: [k1]

TASK [deploy-env : Install OSH Helm plugin] ****************************************************************************
skipping: [k1]

TASK [deploy-env : Check if stable Helm repo exists] *******************************************************************
ok: [k1]

TASK [deploy-env : Remove stable Helm repo] ****************************************************************************
skipping: [k1]

TASK [deploy-env : Include Calico tasks] *******************************************************************************
included: /home/citec/osh/openstack-helm-infra/roles/deploy-env/tasks/calico.yaml for k1, k2, k3, k4

TASK [deploy-env : Download Calico manifest] ***************************************************************************
changed: [k3]
changed: [k1]
changed: [k4]
changed: [k2]

TASK [deploy-env : Download Calico manifest] ***************************************************************************
skipping: [k2]
skipping: [k3]
skipping: [k4]
changed: [k1]

TASK [deploy-env : Deploy Calico] **************************************************************************************
skipping: [k2]
skipping: [k3]
skipping: [k4]
changed: [k1]

TASK [deploy-env : Sleep before trying to check Calico pods] ***********************************************************
Pausing for 30 seconds
(ctrl+C then 'C' = continue early, ctrl+C then 'A' = abort)
ok: [k1]

TASK [deploy-env : Wait for Calico pods ready] *************************************************************************
skipping: [k2]
skipping: [k3]
skipping: [k4]
changed: [k1]

TASK [deploy-env : Prepare Calico patch] *******************************************************************************
skipping: [k2]
skipping: [k3]
skipping: [k4]
ok: [k1]

TASK [deploy-env : Patch Calico] ***************************************************************************************
skipping: [k2]
skipping: [k3]
skipping: [k4]
changed: [k1]

TASK [deploy-env : Wait for Calico pods ready (after patch)] ***********************************************************
skipping: [k2]
skipping: [k3]
skipping: [k4]
FAILED - RETRYING: [k1]: Wait for Calico pods ready (after patch) (10 retries left).
changed: [k1]

TASK [deploy-env : Include Cilium tasks] *******************************************************************************
skipping: [k1]
skipping: [k2]
skipping: [k3]
skipping: [k4]

TASK [deploy-env : Include Flannel tasks] ******************************************************************************
skipping: [k1]
skipping: [k2]
skipping: [k3]
skipping: [k4]

TASK [deploy-env : Include coredns resolver tasks] *********************************************************************
included: /home/citec/osh/openstack-helm-infra/roles/deploy-env/tasks/coredns_resolver.yaml for k1, k2, k3, k4

TASK [deploy-env : Enable recursive queries for coredns] ***************************************************************
skipping: [k2]
skipping: [k3]
skipping: [k4]
changed: [k1]

TASK [deploy-env : Use coredns as default DNS resolver] ****************************************************************
changed: [k1]
changed: [k3]
changed: [k4]
changed: [k2]

TASK [deploy-env : Include Openstack provider gateway tasks] ***********************************************************
skipping: [k1]
skipping: [k2]
skipping: [k3]
skipping: [k4]

TASK [deploy-env : Include Metallb tasks] ******************************************************************************
included: /home/citec/osh/openstack-helm-infra/roles/deploy-env/tasks/metallb.yaml for k1, k2, k3, k4

TASK [deploy-env : Add MetalLB chart repo] *****************************************************************************
skipping: [k2]
skipping: [k3]
skipping: [k4]
changed: [k1]

TASK [deploy-env : Install MetalLB] ************************************************************************************
skipping: [k2]
skipping: [k3]
skipping: [k4]
changed: [k1]

TASK [deploy-env : Sleep before trying to check MetalLB pods] **********************************************************
Pausing for 30 seconds
(ctrl+C then 'C' = continue early, ctrl+C then 'A' = abort)
ok: [k1]

TASK [deploy-env : Wait for MetalLB pods ready] ************************************************************************
skipping: [k2]
skipping: [k3]
skipping: [k4]
changed: [k1]

TASK [deploy-env : Create MetalLB address pool] ************************************************************************
skipping: [k2]
skipping: [k3]
skipping: [k4]
changed: [k1]

TASK [deploy-env : Include Openstack Metallb endpoint tasks] ***********************************************************
skipping: [k2]
skipping: [k3]
skipping: [k4]
included: /home/citec/osh/openstack-helm-infra/roles/deploy-env/tasks/openstack_metallb_endpoint.yaml for k1

TASK [deploy-env : Create openstack ingress service] *******************************************************************
changed: [k1]

TASK [deploy-env : Set dnsmasq listen ip] ******************************************************************************
ok: [k1]

TASK [deploy-env : Start dnsmasq] **************************************************************************************
changed: [k1]

TASK [deploy-env : Configure /etc/resolv.conf] *************************************************************************
changed: [k1]

TASK [deploy-env : Include client-to-cluster tunnel tasks] *************************************************************
skipping: [k1]
skipping: [k2]
skipping: [k3]
skipping: [k4]

TASK [deploy-env : Include client-to-cluster ssh key tasks] ************************************************************
included: /home/citec/osh/openstack-helm-infra/roles/deploy-env/tasks/client_cluster_ssh.yaml for k1, k2, k3, k4

TASK [deploy-env : Set client user home directory] *********************************************************************
ok: [k1]
ok: [k2]
ok: [k3]
ok: [k4]

TASK [deploy-env : Set client user home directory] *********************************************************************
skipping: [k1]
skipping: [k2]
skipping: [k3]
skipping: [k4]

TASK [deploy-env : Set cluster user home directory] ********************************************************************
ok: [k1]
ok: [k2]
ok: [k3]
ok: [k4]

TASK [deploy-env : Set cluster user home directory] ********************************************************************
skipping: [k1]
skipping: [k2]
skipping: [k3]
skipping: [k4]

TASK [deploy-env : Generate ssh key pair] ******************************************************************************
skipping: [k2]
skipping: [k3]
skipping: [k4]
ok: [k1]

TASK [deploy-env : Read ssh public key] ********************************************************************************
skipping: [k2]
skipping: [k3]
skipping: [k4]
changed: [k1]

TASK [deploy-env : Set primary ssh public key] *************************************************************************
ok: [k1]
ok: [k2]
ok: [k3]
ok: [k4]

TASK [deploy-env : Put keys to .ssh/authorized_keys] *******************************************************************
ok: [k1]
ok: [k3]
ok: [k2]
ok: [k4]

TASK [deploy-env : Disable strict host key checking] *******************************************************************
skipping: [k2]
skipping: [k3]
skipping: [k4]
ok: [k1]

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

#### 마스터 노드(k1)

```
citec@k1:~/osh$ sudo kubeadm reset
[reset] Reading configuration from the cluster...
[reset] FYI: You can look at this config file with 'kubectl -n kube-system get cm kubeadm-config -o yaml'
W0417 09:37:34.137635 2049572 preflight.go:56] [reset] WARNING: Changes made to this host by 'kubeadm init' or 'kubeadm join' will be reverted.
[reset] Are you sure you want to proceed? [y/N]: y
[preflight] Running pre-flight checks
[reset] Deleted contents of the etcd data directory: /var/lib/etcd
[reset] Stopping the kubelet service
[reset] Unmounting mounted directories in "/var/lib/kubelet"
[reset] Deleting contents of directories: [/etc/kubernetes/manifests /var/lib/kubelet /etc/kubernetes/pki]
[reset] Deleting files: [/etc/kubernetes/admin.conf /etc/kubernetes/super-admin.conf /etc/kubernetes/kubelet.conf /etc/kubernetes/bootstrap-kubelet.conf /etc/kubernetes/controller-manager.conf /etc/kubernetes/scheduler.conf]

The reset process does not clean CNI configuration. To do so, you must remove /etc/cni/net.d

The reset process does not reset or clean up iptables rules or IPVS tables.
If you wish to reset iptables, you must do so manually by using the "iptables" command.

If your cluster was setup to utilize IPVS, run ipvsadm --clear (or similar)
to reset your system's IPVS tables.

The reset process does not clean your kubeconfig files and you must remove them manually.
Please, check the contents of the $HOME/.kube/config file.

citec@k1:~/osh$ cat remove.sh
#!/bin/bash

sudo rm -rf /etc/kubernetes/*
sudo rm -rf /var/lib/kubelet/*
sudo rm -rf /var/lib/cni/*
sudo rm -rf /etc/cni/net.d/*
sudo netstat -tulpn | grep -E '6443|10259|10257|10250|2379|2380' | awk '{print $6}' | awk -F'/' '{print "kill -9 "$1}' | sh
sudo systemctl stop kubelet
sudo systemctl start kubelet

sudo crictl --runtime-endpoint=unix:///run/containerd/containerd.sock ps -a | grep Running | awk '{print "crictl stop "$1}' | sh
sudo crictl --runtime-endpoint=unix:///run/containerd/containerd.sock ps -a | grep -v CONTAINER | awk '{print "crictl rm "$1}' | sh
sleep 5
sudo crictl --runtime-endpoint=unix:///run/containerd/containerd.sock ps -a | grep -v CONTAINER | awk '{print "crictl rm "$1}' | sh

sudo cp resolv.conf /etc/

citec@k1:~/osh$ cat resolv.conf
nameserver 8.8.8.8
citec@k1:~/osh$ ./remove.sh
```

#### 워커 노드(k2, k3, k4)

```
citec@k2:~$ sudo kubeadm reset
W0417 09:42:50.785384 3968002 preflight.go:56] [reset] WARNING: Changes made to this host by 'kubeadm init' or 'kubeadm join' will be reverted.
[reset] Are you sure you want to proceed? [y/N]: y
[preflight] Running pre-flight checks
W0417 09:42:51.879414 3968002 removeetcdmember.go:106] [reset] No kubeadm config, using etcd pod spec to get data directory
[reset] Deleted contents of the etcd data directory: /var/lib/etcd
[reset] Stopping the kubelet service
[reset] Unmounting mounted directories in "/var/lib/kubelet"
W0417 09:43:00.563599 3968002 cleanupnode.go:99] [reset] Failed to remove containers: [failed to stop running pod 65ff16017966500f616448a198aa75925538d0e24ea65bf447fbb41b456ef352: output: E0417 09:42:52.724542 3968222 remote_runtime.go:222] "StopPodSandbox from runtime service failed" err="rpc error: code = Unknown desc = failed to destroy network for sandbox \"65ff16017966500f616448a198aa75925538d0e24ea65bf447fbb41b456ef352\": plugin type=\"calico\" failed (delete): error getting ClusterInformation: Get \"https://10.96.0.1:443/apis/crd.projectcalico.org/v1/clusterinformations/default\": dial tcp 10.96.0.1:443: connect: connection refused" podSandboxID="65ff16017966500f616448a198aa75925538d0e24ea65bf447fbb41b456ef352"
time="2025-04-17T09:42:52+09:00" level=fatal msg="stopping the pod sandbox \"65ff16017966500f616448a198aa75925538d0e24ea65bf447fbb41b456ef352\": rpc error: code = Unknown desc = failed to destroy network for sandbox \"65ff16017966500f616448a198aa75925538d0e24ea65bf447fbb41b456ef352\": plugin type=\"calico\" failed (delete): error getting ClusterInformation: Get \"https://10.96.0.1:443/apis/crd.projectcalico.org/v1/clusterinformations/default\": dial tcp 10.96.0.1:443: connect: connection refused"
: exit status 1]
[reset] Deleting contents of directories: [/etc/kubernetes/manifests /var/lib/kubelet /etc/kubernetes/pki]
[reset] Deleting files: [/etc/kubernetes/admin.conf /etc/kubernetes/super-admin.conf /etc/kubernetes/kubelet.conf /etc/kubernetes/bootstrap-kubelet.conf /etc/kubernetes/controller-manager.conf /etc/kubernetes/scheduler.conf]

The reset process does not clean CNI configuration. To do so, you must remove /etc/cni/net.d

The reset process does not reset or clean up iptables rules or IPVS tables.
If you wish to reset iptables, you must do so manually by using the "iptables" command.

If your cluster was setup to utilize IPVS, run ipvsadm --clear (or similar)
to reset your system's IPVS tables.

The reset process does not clean your kubeconfig files and you must remove them manually.
Please, check the contents of the $HOME/.kube/config file.

citec@k2:~$ ./remove.sh
```

### Kubernetes 설치 확인 

#### 노드 상태 확인 
```
citec@k1:~/osh$ kubectl get nodes -o wide
NAME   STATUS   ROLES           AGE     VERSION    INTERNAL-IP    EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION       CONTAINER-RUNTIME
k1     Ready    control-plane   10m     v1.29.15   172.16.2.149   <none>        Ubuntu 22.04.5 LTS   5.15.0-136-generic   containerd://1.7.27
k2     Ready    <none>          8m52s   v1.29.15   172.16.2.52    <none>        Ubuntu 22.04.5 LTS   5.15.0-136-generic   containerd://1.7.27
k3     Ready    <none>          7m23s   v1.29.15   172.16.2.223   <none>        Ubuntu 22.04.5 LTS   5.15.0-136-generic   containerd://1.7.27
k4     Ready    <none>          8m53s   v1.29.15   172.16.2.161   <none>        Ubuntu 22.04.5 LTS   5.15.0-136-generic   containerd://1.7.27
```

#### kube-system 네임스페이스의 파드 상태 확인
kubectl 명령어를 통해 Kubernetes의 상태를 확인하거나 명령을 수행하는데 필요한 kube-apiserver, Kubernetes 환경에서 네트워크를 담당하게 되는 calico 파드 등을 포함해 모든 파드들이 정상적으로 Running 상태에 있는지 확인한다. 

```
citec@k1:~/osh$ kubectl get pods -n kube-system -o wide
NAME                                       READY   STATUS    RESTARTS   AGE     IP               NODE   NOMINATED NODE   READINESS GATES
calico-kube-controllers-6b78c44475-7gm9j   1/1     Running   0          7m23s   10.244.194.130   k4     <none>           <none>
calico-node-9knwk                          1/1     Running   0          6m20s   172.16.2.223     k3     <none>           <none>
calico-node-ltwdm                          1/1     Running   0          6m30s   172.16.2.161     k4     <none>           <none>
calico-node-qfqtq                          1/1     Running   0          6m51s   172.16.2.149     k1     <none>           <none>
calico-node-z4tkv                          1/1     Running   0          6m41s   172.16.2.52      k2     <none>           <none>
coredns-b87576b6c-55dr8                    1/1     Running   0          6m29s   10.244.195.129   k3     <none>           <none>
coredns-b87576b6c-x2s4f                    1/1     Running   0          6m29s   10.244.99.1      k2     <none>           <none>
etcd-k1                                    1/1     Running   84         10m     172.16.2.149     k1     <none>           <none>
kube-apiserver-k1                          1/1     Running   8          10m     172.16.2.149     k1     <none>           <none>
kube-controller-manager-k1                 1/1     Running   8          10m     172.16.2.149     k1     <none>           <none>
kube-proxy-8sw4c                           1/1     Running   0          9m15s   172.16.2.161     k4     <none>           <none>
kube-proxy-lmffv                           1/1     Running   0          9m14s   172.16.2.52      k2     <none>           <none>
kube-proxy-qr85k                           1/1     Running   0          9m18s   172.16.2.149     k1     <none>           <none>
kube-proxy-wvcx2                           1/1     Running   0          7m45s   172.16.2.223     k3     <none>           <none>
kube-scheduler-k1                          1/1     Running   79         10m     172.16.2.149     k1     <none>           <none>
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
CONTAINER           IMAGE               CREATED             STATE               NAME                      ATTEMPT             POD ID              POD
11e683bf5381f       86e3b780f3799       6 minutes ago       Running             frr-metrics               0                   1cbc3d82bcc71       metallb-speaker-vm7pz
547c372942c76       86e3b780f3799       6 minutes ago       Running             reloader                  0                   1cbc3d82bcc71       metallb-speaker-vm7pz
eeb757cf2e490       86e3b780f3799       6 minutes ago       Running             frr                       0                   1cbc3d82bcc71       metallb-speaker-vm7pz
343d3e72bc23b       94c5f9675e593       6 minutes ago       Running             speaker                   0                   1cbc3d82bcc71       metallb-speaker-vm7pz
972a3432badf1       94c5f9675e593       6 minutes ago       Exited              cp-metrics                0                   1cbc3d82bcc71       metallb-speaker-vm7pz
622e4c7de893d       94c5f9675e593       6 minutes ago       Exited              cp-reloader               0                   1cbc3d82bcc71       metallb-speaker-vm7pz
3ce656802dde1       86e3b780f3799       6 minutes ago       Exited              cp-frr-files              0                   1cbc3d82bcc71       metallb-speaker-vm7pz
7053618be050a       3dd4390f2a85a       7 minutes ago       Running             calico-node               0                   4bf3ee176d85c       calico-node-qfqtq
a72f05efeb29f       3dd4390f2a85a       7 minutes ago       Exited              mount-bpffs               0                   4bf3ee176d85c       calico-node-qfqtq
1adf109638bca       dc6f84c32585f       7 minutes ago       Exited              install-cni               0                   4bf3ee176d85c       calico-node-qfqtq
4edd58248d9ab       dc6f84c32585f       7 minutes ago       Exited              upgrade-ipam              0                   4bf3ee176d85c       calico-node-qfqtq
5d4b24d88b095       f71614796eb76       10 minutes ago      Running             kube-proxy                0                   2f1ac55bd5160       kube-proxy-qr85k
ab2be62891376       9ea0bd82ed4f6       11 minutes ago      Running             kube-scheduler            79                  effecf6af3cde       kube-scheduler-k1
708f0911f7957       b0cdcf76ac8e9       11 minutes ago      Running             kube-controller-manager   8                   3857b630837c5       kube-controller-manager-k1
3f6c063d79aca       a9e7e6b294baf       11 minutes ago      Running             etcd                      84                  6b5e6c07f7dea       etcd-k1
1f3d29acccdd7       f44c6888a2d24       11 minutes ago      Running             kube-apiserver            8                   3511d4eb46fea       kube-apiserver-k1
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

### Ingress 설치 
Kubernetes 클러스터 내의 서비스에 대한 외부 HTTP/HTTPS 트래픽을 관리하고 라우팅하는 역할을 하는 Ingress를 설치한다. 

#### OpenStack 구성을 위한 환경 설정

```
citec@k1:~/osh$ cd openstack-helm
citec@k1:~/osh/openstack-helm$ ./tools/deployment/common/setup-client.sh
+ sudo -H mkdir -p /etc/openstack
++ id -un
+ sudo -H chown -R citec: /etc/openstack
+ [[ '' =~ (^|[[:space:]])tls($|[[:space:]]) ]]
+ tee /etc/openstack/clouds.yaml
  clouds:
    openstack_helm:
      region_name: RegionOne
      identity_api_version: 3
      auth:
        username: 'admin'
        password: 'password'
        project_name: 'admin'
        project_domain_name: 'default'
        user_domain_name: 'default'
        auth_url: 'http://keystone.openstack.svc.cluster.local/v3'
+ sudo tee /usr/local/bin/openstack
#!/bin/bash
args=("$@")

sudo docker run \
    --rm \
    --network host \
    -w / \
    -v /etc/openstack/clouds.yaml:/etc/openstack/clouds.yaml \
    -v /etc/openstack-helm:/etc/openstack-helm \
    -e OS_CLOUD=${OS_CLOUD} \
    ${OPENSTACK_CLIENT_CONTAINER_EXTRA_ARGS} \
    quay.io/airshipit/openstack-client:${OPENSTACK_RELEASE:-2024.2} openstack "${args[@]}"
+ sudo chmod +x /usr/local/bin/openstack
```

#### Ingress 설치 스크립트 수정
Ingress 설치 과정에서 ceph 네임스페이스를 생성하는 부분이 누락되어있으니 이를 포함하도록 수정한다.

```
citec@k1:~/osh/openstack-helm$ vi tools/deployment/common/ingress.sh
...
helm upgrade --install ingress-nginx-ceph ingress-nginx/ingress-nginx \
  --version ${HELM_INGRESS_NGINX_VERSION} \
  --namespace=ceph \
  --create-namespace \
  --set controller.kind=DaemonSet \
  --set controller.admissionWebhooks.enabled="false" \
  --set controller.scope.enabled="true" \
  --set controller.service.enabled="false" \
  --set controller.ingressClassResource.name=nginx-ceph \
  --set controller.ingressClassResource.controllerValue="k8s.io/ingress-nginx-ceph" \
  --set controller.ingressClass=nginx-ceph \
  --set controller.labels.app=ingress-api
...
```

#### Ingress 설치

```
citec@k1:~/osh/openstack-helm$ ./tools/deployment/common/ingress.sh
+ : 4.8.3
+ helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
"ingress-nginx" already exists with the same configuration, skipping
+ [[ '' =~ (^|[[:space:]])metallb($|[[:space:]]) ]]
+ helm upgrade --install ingress-nginx-cluster ingress-nginx/ingress-nginx --version 4.8.3 --namespace=kube-system --set controller.admissionWebhooks.enabled=false --set controller.kind=DaemonSet --set controller.service.type=ClusterIP --set controller.scope.enabled=false --set controller.hostNetwork=true --set controller.ingressClassResource.name=nginx-cluster --set controller.ingressClassResource.controllerValue=k8s.io/ingress-nginx-cluster --set controller.ingressClassResource.default=true --set controller.ingressClass=nginx-cluster --set controller.labels.app=ingress-api
Release "ingress-nginx-cluster" does not exist. Installing it now.
NAME: ingress-nginx-cluster
LAST DEPLOYED: Thu Apr 17 13:45:58 2025
NAMESPACE: kube-system
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
The ingress-nginx controller has been installed.
Get the application URL by running these commands:
  export POD_NAME=$(kubectl --namespace kube-system get pods -o jsonpath="{.items[0].metadata.name}" -l "app=ingress-nginx,component=controller,release=ingress-nginx-cluster")
  kubectl --namespace kube-system port-forward $POD_NAME 8080:80
  echo "Visit http://127.0.0.1:8080 to access your application."

An example Ingress that makes use of the controller:
  apiVersion: networking.k8s.io/v1
  kind: Ingress
  metadata:
    name: example
    namespace: foo
  spec:
    ingressClassName: nginx-cluster
    rules:
      - host: www.example.com
        http:
          paths:
            - pathType: Prefix
              backend:
                service:
                  name: exampleService
                  port:
                    number: 80
              path: /
    # This section is only required if TLS is to be enabled for the Ingress
    tls:
      - hosts:
        - www.example.com
        secretName: example-tls

If TLS is enabled for the Ingress, a Secret containing the certificate and key must also be provided:

  apiVersion: v1
  kind: Secret
  metadata:
    name: example-tls
    namespace: foo
  data:
    tls.crt: <base64 encoded cert>
    tls.key: <base64 encoded key>
  type: kubernetes.io/tls
+ helm osh wait-for-pods kube-system
+ helm upgrade --install ingress-nginx-openstack ingress-nginx/ingress-nginx --version 4.8.3 --namespace=openstack --set controller.kind=DaemonSet --set controller.admissionWebhooks.enabled=false --set controller.scope.enabled=true --set controller.service.enabled=false --set controller.ingressClassResource.name=nginx --set controller.ingressClassResource.controllerValue=k8s.io/ingress-nginx-openstack --set controller.ingressClass=nginx --set controller.labels.app=ingress-api
Release "ingress-nginx-openstack" does not exist. Installing it now.
NAME: ingress-nginx-openstack
LAST DEPLOYED: Thu Apr 17 13:46:10 2025
NAMESPACE: openstack
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
The ingress-nginx controller has been installed.
It may take a few minutes for the LoadBalancer IP to be available.
You can watch the status by running 'kubectl --namespace openstack get services -o wide -w ingress-nginx-openstack-controller'

An example Ingress that makes use of the controller:
  apiVersion: networking.k8s.io/v1
  kind: Ingress
  metadata:
    name: example
    namespace: foo
  spec:
    ingressClassName: nginx
    rules:
      - host: www.example.com
        http:
          paths:
            - pathType: Prefix
              backend:
                service:
                  name: exampleService
                  port:
                    number: 80
              path: /
    # This section is only required if TLS is to be enabled for the Ingress
    tls:
      - hosts:
        - www.example.com
        secretName: example-tls

If TLS is enabled for the Ingress, a Secret containing the certificate and key must also be provided:

  apiVersion: v1
  kind: Secret
  metadata:
    name: example-tls
    namespace: foo
  data:
    tls.crt: <base64 encoded cert>
    tls.key: <base64 encoded key>
  type: kubernetes.io/tls
+ helm osh wait-for-pods openstack
+ helm upgrade --install ingress-nginx-ceph ingress-nginx/ingress-nginx --version 4.8.3 --namespace=ceph --create-namespace --set controller.kind=DaemonSet --set controller.admissionWebhooks.enabled=false --set controller.scope.enabled=true --set controller.service.enabled=false --set controller.ingressClassResource.name=nginx-ceph --set controller.ingressClassResource.controllerValue=k8s.io/ingress-nginx-ceph --set controller.ingressClass=nginx-ceph --set controller.labels.app=ingress-api
Release "ingress-nginx-ceph" does not exist. Installing it now.
NAME: ingress-nginx-ceph
LAST DEPLOYED: Thu Apr 17 13:46:22 2025
NAMESPACE: ceph
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
The ingress-nginx controller has been installed.
It may take a few minutes for the LoadBalancer IP to be available.
You can watch the status by running 'kubectl --namespace ceph get services -o wide -w ingress-nginx-ceph-controller'

An example Ingress that makes use of the controller:
  apiVersion: networking.k8s.io/v1
  kind: Ingress
  metadata:
    name: example
    namespace: foo
  spec:
    ingressClassName: nginx-ceph
    rules:
      - host: www.example.com
        http:
          paths:
            - pathType: Prefix
              backend:
                service:
                  name: exampleService
                  port:
                    number: 80
              path: /
    # This section is only required if TLS is to be enabled for the Ingress
    tls:
      - hosts:
        - www.example.com
        secretName: example-tls

If TLS is enabled for the Ingress, a Secret containing the certificate and key must also be provided:

  apiVersion: v1
  kind: Secret
  metadata:
    name: example-tls
    namespace: foo
  data:
    tls.crt: <base64 encoded cert>
    tls.key: <base64 encoded key>
  type: kubernetes.io/tls
+ helm osh wait-for-pods ceph
```

#### Ingress 파드 상태 확인 
kube-system, openstack, ceph 네임스페이스에 각각 확인 

```
citec@k1:~/osh/openstack-helm$ kubectl -n kube-system get pods | grep ingress
ingress-nginx-cluster-controller-4f7k9     1/1     Running   0          4m45s
ingress-nginx-cluster-controller-9bplr     1/1     Running   0          4m45s
ingress-nginx-cluster-controller-cxlzh     1/1     Running   0          4m45s
ingress-nginx-cluster-controller-gqb7r     1/1     Running   0          4m45s

citec@k1:~/osh/openstack-helm$ kubectl -n openstack  get pods | grep ingress
ingress-nginx-openstack-controller-7v45t   1/1     Running   0          4m44s
ingress-nginx-openstack-controller-cts8w   1/1     Running   0          4m44s
ingress-nginx-openstack-controller-vj2kd   1/1     Running   0          4m44s
ingress-nginx-openstack-controller-zdw66   1/1     Running   0          4m44s

citec@k1:~/osh/openstack-helm$ kubectl -n ceph get pods | grep ingress
ingress-nginx-ceph-controller-7ssh8   1/1     Running   0          4m37s
ingress-nginx-ceph-controller-pnh5c   1/1     Running   0          4m37s
ingress-nginx-ceph-controller-txszj   1/1     Running   0          4m37s
ingress-nginx-ceph-controller-vfzwd   1/1     Running   0          4m37s
```

### Rook Ceph Helm 차트 설치 
Ceph를 Kubernetes에 배포하기 위해 Rook Ceph를 사용한다. Rook는 Ceph 클러스터를 쉽게 관리할 수 있도록 도와주는 오퍼레이터이다. 

#### Helm 저장소 추가

```
citec@k1:~/osh$ helm repo add rook-release https://charts.rook.io/release
"rook-release" has been added to your repositories

citec@k1:~/osh$ helm repo update
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "metallb" chart repository
...Successfully got an update from the "ingress-nginx" chart repository
...Successfully got an update from the "rook-release" chart repository
Update Complete. ⎈Happy Helming!⎈
```

#### Rook Ceph 오퍼레이터 설치
설치 후 Rook 오퍼레이터가 Ceph 클러스터를 관리할 수 있도록 준비한다.

```
citec@k1:~/osh$ helm install --create-namespace --namespace rook-ceph rook-ceph rook-release/rook-ceph
NAME: rook-ceph
LAST DEPLOYED: Thu Apr 17 13:59:37 2025
NAMESPACE: rook-ceph
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
The Rook Operator has been installed. Check its status by running:
  kubectl --namespace rook-ceph get pods -l "app=rook-ceph-operator"

Visit https://rook.io/docs/rook/latest for instructions on how to create and configure Rook clusters

Important Notes:
- You must customize the 'CephCluster' resource in the sample manifests for your cluster.
- Each CephCluster must be deployed to its own namespace, the samples use `rook-ceph` for the namespace.
- The sample manifests assume you also installed the rook-ceph operator in the `rook-ceph` namespace.
- The helm chart includes all the RBAC required to create a CephCluster CRD in the same namespace.
- Any disk devices you add to the cluster in the 'CephCluster' must be empty (no filesystem and no partitions).
```

#### Ceph 클러스터 생성
Ceph 클러스터를 생성하기 위해 CephCluster 리소스를 정의하는 YAML 파일을 작성한다.

```
citec@k1:~/osh$ tee ceph-cluster.yaml <<EOF
apiVersion: ceph.rook.io/v1
kind: CephCluster
metadata:
  name: rook-ceph
  namespace: rook-ceph
spec:
  cephVersion:
    image: quay.io/ceph/ceph:v18.2.4
  dataDirHostPath: /var/lib/rook
  mon:
    count: 3
    allowMultiplePerNode: false
  dashboard:
    enabled: true
  storage:
    useAllNodes: true
    useAllDevices: true
EOF
```
- mon.count: 3 : Ceph 모니터를 3개로 설정하여 고가용성 확보 
- useAllNodes 및 useAllDevices : 모든 노드와 디바이스를 스토리지로 사용

##### /etc/resolv.conf 파일 확인 
Ceph 이미지 quay.io/ceph/ceph:v18.2.4를 가져오기 위해서 /etc/resolv.conf 파일을 다시 확인하고, 만약 내부 네임서버만 지정되어있다면(Kubernetes 설치 과정에서 변경될 수 있음), 8.8.8.8 과 같은 네임서버를 추가한다. 모든 노드에서 확인하고 같은 작업을 수행한다. 

```
citec@k1:~/osh$ cat /etc/resolv.conf
nameserver 172.16.2.149

citec@k1:~/osh$ sudo tee -a /etc/resolv.conf <<EOF
> nameserver 8.8.8.8
> EOF
nameserver 8.8.8.8

citec@k1:~/osh$ cat /etc/resolv.conf
nameserver 172.16.2.149
nameserver 8.8.8.8
```

##### YAML 적용
생성한 YAML 파일을 적용한다.
```
citec@k1:~/osh$ kubectl apply -f ceph-cluster.yaml
cephcluster.ceph.rook.io/rook-ceph created
```

##### CephCluster 상태 확인 
```
citec@k1:~/osh$ kubectl -n rook-ceph get cephcluster
NAME        DATADIRHOSTPATH   MONCOUNT   AGE   PHASE         MESSAGE                 HEALTH   EXTERNAL   FSID
rook-ceph   /var/lib/rook     3          12s   Progressing   Configuring Ceph Mons
```

##### 파드 상태 확인
rook-ceph 네임스페이스의 파드 확인 
```
ccitec@k1:~/osh$ kubectl -n rook-ceph get pods
NAME                                            READY   STATUS     RESTARTS   AGE
csi-cephfsplugin-c2ctx                          2/2     Running    0          2m3s
csi-cephfsplugin-j7sms                          2/2     Running    0          2m3s
csi-cephfsplugin-provisioner-5fd86644fb-cp7p6   5/5     Running    0          2m3s
csi-cephfsplugin-provisioner-5fd86644fb-dmdbs   5/5     Running    0          2m3s
csi-cephfsplugin-q4rnr                          2/2     Running    0          2m3s
csi-cephfsplugin-vgtgp                          2/2     Running    0          2m3s
csi-rbdplugin-c9668                             2/2     Running    0          2m3s
csi-rbdplugin-cfrmq                             2/2     Running    0          2m3s
csi-rbdplugin-g2ttm                             2/2     Running    0          2m3s
csi-rbdplugin-provisioner-5cdcfc4cbd-xr25b      5/5     Running    0          2m3s
csi-rbdplugin-provisioner-5cdcfc4cbd-zcwwq      5/5     Running    0          2m3s
csi-rbdplugin-w5m22                             2/2     Running    0          2m3s
rook-ceph-mon-a-6f9fb68d-rktwj                  0/1     Init:0/2   0          115s
rook-ceph-operator-6d97579698-b7bx5             1/1     Running    0          2m43s
```

##### 파드 이벤트 확인
만약 파드의 상태가 장시간 변화가 없다면, 파드의 이벤트와 로그를 확인할 수 있다. rook-ceph-mon-a 파드 이벤트를 확인하려면 다음의 명령을 실행한다.
```
citec@k1:~/osh$ kubectl -n rook-ceph describe pod rook-ceph-mon-a-6f9fb68d-rktwj
Name:             rook-ceph-mon-a-6f9fb68d-rktwj
Namespace:        rook-ceph
Priority:         0
Service Account:  rook-ceph-default
Node:             k1/172.16.2.149
Start Time:       Thu, 17 Apr 2025 14:38:53 +0900
Labels:           app=rook-ceph-mon
                  app.kubernetes.io/component=cephclusters.ceph.rook.io
                  app.kubernetes.io/created-by=rook-ceph-operator
                  app.kubernetes.io/instance=a
                  app.kubernetes.io/managed-by=rook-ceph-operator
                  app.kubernetes.io/name=ceph-mon
                  app.kubernetes.io/part-of=rook-ceph
                  ceph_daemon_id=a
                  ceph_daemon_type=mon
                  mon=a
                  mon_cluster=rook-ceph
                  mon_daemon=true
                  pod-template-hash=6f9fb68d
                  rook.io/operator-namespace=rook-ceph
                  rook_cluster=rook-ceph
Annotations:      cni.projectcalico.org/containerID: bee5fbfe73e532bb89528ded1751b1c7919f1d75ea4f926c936f6456d641aa35
                  cni.projectcalico.org/podIP: 10.244.105.133/32
                  cni.projectcalico.org/podIPs: 10.244.105.133/32
Status:           Running
IP:               10.244.105.133
IPs:
  IP:           10.244.105.133
Controlled By:  ReplicaSet/rook-ceph-mon-a-6f9fb68d
Init Containers:
  chown-container-data-dir:
    Container ID:  containerd://5a80c2fb18ab839cf0dc519b9704d336f5c96e13d4ca6d92b27b6636df617053
    Image:         quay.io/ceph/ceph:v18.2.4
    Image ID:      quay.io/ceph/ceph@sha256:6ac7f923aa1d23b43248ce0ddec7e1388855ee3d00813b52c3172b0b23b37906
    Port:          <none>
    Host Port:     <none>
    Command:
      chown
    Args:
      --verbose
      --recursive
      ceph:ceph
      /var/log/ceph
      /var/lib/ceph/crash
      /run/ceph
      /var/lib/ceph/mon/ceph-a
    State:          Terminated
      Reason:       Completed
      Exit Code:    0
      Started:      Thu, 17 Apr 2025 14:42:40 +0900
      Finished:     Thu, 17 Apr 2025 14:42:40 +0900
    Ready:          True
    Restart Count:  0
    Environment:    <none>
    Mounts:
      /etc/ceph from rook-config-override (ro)
      /etc/ceph/keyring-store/ from rook-ceph-mons-keyring (ro)
      /run/ceph from ceph-daemons-sock-dir (rw)
      /var/lib/ceph/crash from rook-ceph-crash (rw)
      /var/lib/ceph/mon/ceph-a from ceph-daemon-data (rw)
      /var/log/ceph from rook-ceph-log (rw)
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-4xd2q (ro)
  init-mon-fs:
    Container ID:  containerd://70fc750eaa8414d2099fb123bc17b9febced7cbbb8336efb98191dfa350bac4c
    Image:         quay.io/ceph/ceph:v18.2.4
    Image ID:      quay.io/ceph/ceph@sha256:6ac7f923aa1d23b43248ce0ddec7e1388855ee3d00813b52c3172b0b23b37906
    Port:          <none>
    Host Port:     <none>
    Command:
      ceph-mon
    Args:
      --fsid=f1ed7497-46ae-4186-b2c6-46aac10df99c
      --keyring=/etc/ceph/keyring-store/keyring
      --default-log-to-stderr=true
      --default-err-to-stderr=true
      --default-mon-cluster-log-to-stderr=true
      --default-log-stderr-prefix=debug
      --default-log-to-file=false
      --default-mon-cluster-log-to-file=false
      --mon-host=$(ROOK_CEPH_MON_HOST)
      --mon-initial-members=$(ROOK_CEPH_MON_INITIAL_MEMBERS)
      --id=a
      --setuser=ceph
      --setgroup=ceph
      --public-addr=10.96.30.54
      --mkfs
    State:          Terminated
      Reason:       Completed
      Exit Code:    0
      Started:      Thu, 17 Apr 2025 14:42:54 +0900
      Finished:     Thu, 17 Apr 2025 14:42:54 +0900
    Ready:          True
    Restart Count:  0
    Environment:
      CONTAINER_IMAGE:                quay.io/ceph/ceph:v18.2.4
      POD_NAME:                       rook-ceph-mon-a-6f9fb68d-rktwj (v1:metadata.name)
      POD_NAMESPACE:                  rook-ceph (v1:metadata.namespace)
      NODE_NAME:                       (v1:spec.nodeName)
      POD_MEMORY_LIMIT:               node allocatable (limits.memory)
      POD_MEMORY_REQUEST:             0 (requests.memory)
      POD_CPU_LIMIT:                  node allocatable (limits.cpu)
      POD_CPU_REQUEST:                0 (requests.cpu)
      CEPH_USE_RANDOM_NONCE:          true
      ROOK_CEPH_MON_HOST:             <set to the key 'mon_host' in secret 'rook-ceph-config'>             Optional: false
      ROOK_CEPH_MON_INITIAL_MEMBERS:  <set to the key 'mon_initial_members' in secret 'rook-ceph-config'>  Optional: false
    Mounts:
      /etc/ceph from rook-config-override (ro)
      /etc/ceph/keyring-store/ from rook-ceph-mons-keyring (ro)
      /run/ceph from ceph-daemons-sock-dir (rw)
      /var/lib/ceph/crash from rook-ceph-crash (rw)
      /var/lib/ceph/mon/ceph-a from ceph-daemon-data (rw)
      /var/log/ceph from rook-ceph-log (rw)
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-4xd2q (ro)
Containers:
  mon:
    Container ID:  containerd://76d510c2b4408855661d03a8687a90c191bdebcfdd856a8a52f3f1233bc527c4
    Image:         quay.io/ceph/ceph:v18.2.4
    Image ID:      quay.io/ceph/ceph@sha256:6ac7f923aa1d23b43248ce0ddec7e1388855ee3d00813b52c3172b0b23b37906
    Ports:         3300/TCP, 6789/TCP
    Host Ports:    0/TCP, 0/TCP
    Command:
      ceph-mon
    Args:
      --fsid=f1ed7497-46ae-4186-b2c6-46aac10df99c
      --keyring=/etc/ceph/keyring-store/keyring
      --default-log-to-stderr=true
      --default-err-to-stderr=true
      --default-mon-cluster-log-to-stderr=true
      --default-log-stderr-prefix=debug
      --default-log-to-file=false
      --default-mon-cluster-log-to-file=false
      --mon-host=$(ROOK_CEPH_MON_HOST)
      --mon-initial-members=$(ROOK_CEPH_MON_INITIAL_MEMBERS)
      --id=a
      --setuser=ceph
      --setgroup=ceph
      --foreground
      --public-addr=10.96.30.54
      --setuser-match-path=/var/lib/ceph/mon/ceph-a/store.db
      --public-bind-addr=$(ROOK_POD_IP)
    State:          Running
      Started:      Thu, 17 Apr 2025 14:42:55 +0900
    Ready:          True
    Restart Count:  0
    Liveness:       exec [env -i sh -c
outp="$(ceph --admin-daemon /run/ceph/ceph-mon.a.asok mon_status 2>&1)"
rc=$?
if [ $rc -ne 0 ]; then
  echo "ceph daemon health check failed with the following output:"
  echo "$outp" | sed -e 's/^/> /g'
  exit $rc
fi
] delay=10s timeout=5s period=10s #success=1 #failure=3
    Startup:  exec [env -i sh -c
outp="$(ceph --admin-daemon /run/ceph/ceph-mon.a.asok mon_status 2>&1)"
rc=$?
if [ $rc -ne 0 ]; then
  echo "ceph daemon health check failed with the following output:"
  echo "$outp" | sed -e 's/^/> /g'
  exit $rc
fi
] delay=10s timeout=5s period=10s #success=1 #failure=6
    Environment:
      CONTAINER_IMAGE:                quay.io/ceph/ceph:v18.2.4
      POD_NAME:                       rook-ceph-mon-a-6f9fb68d-rktwj (v1:metadata.name)
      POD_NAMESPACE:                  rook-ceph (v1:metadata.namespace)
      NODE_NAME:                       (v1:spec.nodeName)
      POD_MEMORY_LIMIT:               node allocatable (limits.memory)
      POD_MEMORY_REQUEST:             0 (requests.memory)
      POD_CPU_LIMIT:                  node allocatable (limits.cpu)
      POD_CPU_REQUEST:                0 (requests.cpu)
      CEPH_USE_RANDOM_NONCE:          true
      ROOK_CEPH_MON_HOST:             <set to the key 'mon_host' in secret 'rook-ceph-config'>             Optional: false
      ROOK_CEPH_MON_INITIAL_MEMBERS:  <set to the key 'mon_initial_members' in secret 'rook-ceph-config'>  Optional: false
      ROOK_POD_IP:                     (v1:status.podIP)
    Mounts:
      /etc/ceph from rook-config-override (ro)
      /etc/ceph/keyring-store/ from rook-ceph-mons-keyring (ro)
      /run/ceph from ceph-daemons-sock-dir (rw)
      /var/lib/ceph/crash from rook-ceph-crash (rw)
      /var/lib/ceph/mon/ceph-a from ceph-daemon-data (rw)
      /var/log/ceph from rook-ceph-log (rw)
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-4xd2q (ro)
Conditions:
  Type                        Status
  PodReadyToStartContainers   True
  Initialized                 True
  Ready                       True
  ContainersReady             True
  PodScheduled                True
Volumes:
  rook-config-override:
    Type:               Projected (a volume that contains injected data from multiple sources)
    ConfigMapName:      rook-config-override
    ConfigMapOptional:  <nil>
  rook-ceph-mons-keyring:
    Type:        Secret (a volume populated by a Secret)
    SecretName:  rook-ceph-mons-keyring
    Optional:    false
  ceph-daemons-sock-dir:
    Type:          HostPath (bare host directory volume)
    Path:          /var/lib/rook/exporter
    HostPathType:  DirectoryOrCreate
  rook-ceph-log:
    Type:          HostPath (bare host directory volume)
    Path:          /var/lib/rook/rook-ceph/log
    HostPathType:
  rook-ceph-crash:
    Type:          HostPath (bare host directory volume)
    Path:          /var/lib/rook/rook-ceph/crash
    HostPathType:
  ceph-daemon-data:
    Type:          HostPath (bare host directory volume)
    Path:          /var/lib/rook/mon-a/data
    HostPathType:
  kube-api-access-4xd2q:
    Type:                    Projected (a volume that contains injected data from multiple sources)
    TokenExpirationSeconds:  3607
    ConfigMapName:           kube-root-ca.crt
    ConfigMapOptional:       <nil>
    DownwardAPI:             true
QoS Class:                   BestEffort
Node-Selectors:              kubernetes.io/hostname=k1
Tolerations:                 node.kubernetes.io/not-ready:NoExecute op=Exists for 300s
                             node.kubernetes.io/unreachable:NoExecute op=Exists for 300s
Events:
  Type     Reason            Age                 From               Message
  ----     ------            ----                ----               -------
  Warning  FailedScheduling  4m30s (x2 over 5m)  default-scheduler  0/4 nodes are available: 1 node(s) didn't satisfy existing pods anti-affinity rules, 3 node(s) didn't match Pod's node affinity/selector. preemption: 0/4 nodes are available: 1 No preemption victims found for incoming pod, 3 Preemption is not helpful for scheduling.
  Normal   Scheduled         4m28s               default-scheduler  Successfully assigned rook-ceph/rook-ceph-mon-a-6f9fb68d-rktwj to k1
  Normal   Pulling           4m27s               kubelet            Pulling image "quay.io/ceph/ceph:v18.2.4"
  Normal   Pulled            41s                 kubelet            Successfully pulled image "quay.io/ceph/ceph:v18.2.4" in 3m46.316s (3m46.316s including waiting)
  Normal   Created           41s                 kubelet            Created container: chown-container-data-dir
  Normal   Started           41s                 kubelet            Started container chown-container-data-dir
  Normal   Pulled            28s                 kubelet            Container image "quay.io/ceph/ceph:v18.2.4" already present on machine
  Normal   Created           28s                 kubelet            Created container: init-mon-fs
  Normal   Started           27s                 kubelet            Started container init-mon-fs
  Normal   Pulled            27s                 kubelet            Container image "quay.io/ceph/ceph:v18.2.4" already present on machine
  Normal   Created           27s                 kubelet            Created container: mon
  Normal   Started           26s                 kubelet            Started container mon
```

##### Rook 오퍼레이터 로그 확인
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

#### Ceph 상태 확인 방법
Rook 환경에서는 모니터 파드에서 직접 ceph -s를 실행하는 대신, Rook 툴박스(Toolbox)를 사용하는 것이 표준이다. 

##### 툴박스를 배포하여 상태 확인
툴박스 배포 
```
citec@k1:~$ kubectl -n rook-ceph apply -f https://raw.githubusercontent.com/rook/rook/master/deploy/examples/toolbox.yaml
deployment.apps/rook-ceph-tools created
```

툴박스 파드 확인
```
citec@k1:~$ kubectl -n rook-ceph get pods -l app=rook-ceph-tools
NAME                               READY   STATUS    RESTARTS   AGE
rook-ceph-tools-56fbc74755-gr9p9   1/1     Running   0          8s
```

툴박스에서 상태 확인
```
citec@k1:~$ kubectl -n rook-ceph exec -it $(kubectl -n rook-ceph get pod -l "app=rook-ceph-tools" -o jsonpath='{.items[0].metadata.name}') -- ceph -s
  cluster:
    id:     f1ed7497-46ae-4186-b2c6-46aac10df99c
    health: HEALTH_WARN
            mon a is low on available space
            OSD count 0 < osd_pool_default_size 3

  services:
    mon: 2 daemons, quorum a,c (age 16m)
    mgr: a(active, since 10m)
    osd: 0 osds: 0 up, 0 in

  data:
    pools:   0 pools, 0 pgs
    objects: 0 objects, 0 B
    usage:   0 B used, 0 B / 0 B avail
    pgs:
```

Ceph 명령어 수행의 편의를 위해 alias 등록 
```
citec@k1:~$ tee -a ~/.bashrc <<EOF
> alias kceph='kubectl -n rook-ceph exec -it $(kubectl -n rook-ceph get pod -l "app=rook-ceph-tools" -o jsonpath='{.items[0].metadata.name}') --'
> EOF
alias kceph='kubectl -n rook-ceph exec -it rook-ceph-tools-56fbc74755-gr9p9 --'
citec@k1:~$ . ~/.bashrc
citec@k1:~$ kceph ceph -s
  cluster:
    id:     f1ed7497-46ae-4186-b2c6-46aac10df99c
    health: HEALTH_WARN
            mon a is low on available space
            OSD count 0 < osd_pool_default_size 3

  services:
    mon: 2 daemons, quorum a,c (age 19m)
    mgr: a(active, since 13m)
    osd: 0 osds: 0 up, 0 in

  data:
    pools:   0 pools, 0 pgs
    objects: 0 objects, 0 B
    usage:   0 B used, 0 B / 0 B avail
    pgs:
```
