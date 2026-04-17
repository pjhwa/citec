## libvirt pod
```
kwholee@SDS-7XDD-60881:~$ kq2 get pods -n openstack | grep libvirt
libvirt-libvirt-default-b0-2x7cq                                  1/1     Running             2 (16d ago)        23d
libvirt-libvirt-default-b0-4sldn                                  1/1     Running             2 (15d ago)        23d
libvirt-libvirt-default-b0-bmwpk                                  1/1     Running             2 (16d ago)        23d
libvirt-libvirt-default-b0-ms6xr                                  1/1     Running             2 (15d ago)        23d
libvirt-libvirt-default-b0-qxd8z                                  1/1     Running             2 (16d ago)        23d
libvirt-libvirt-default-b0-xgsx7                                  1/1     Running             3 (15d ago)        23d
libvirt-libvirt-default-b1-22b2h                                  1/1     Running             3 (15d ago)        23d
libvirt-libvirt-default-b1-2m2cr                                  1/1     Running             2 (14d ago)        23d
libvirt-libvirt-default-b1-6bsdg                                  1/1     Running             2 (15d ago)        23d
libvirt-libvirt-default-b1-7g2pz                                  1/1     Running             2 (15d ago)        23d
libvirt-libvirt-default-b1-cj9zc                                  1/1     Running             0                  3d12h
libvirt-libvirt-default-b1-ftkc8                                  1/1     Running             2 (16d ago)        23d
libvirt-libvirt-default-b1-gpu-b300-3-5s594                       1/1     Running             0                  7d2h
libvirt-libvirt-default-b1-gpu-b300-3-95tlh                       1/1     Running             0                  27h
libvirt-libvirt-default-b1-gpu-b300-3-lfhwk                       1/1     Running             2 (15d ago)        23d
libvirt-libvirt-default-b1-gpu-b300-3-rmfxp                       1/1     Running             0                  153m
libvirt-libvirt-default-b1-gpu-h100-2-c2x4x                       1/1     Running             2 (15d ago)        23d
libvirt-libvirt-default-b1-gpu-h100-2-rnt4r                       1/1     Running             2 (14d ago)        23d
libvirt-libvirt-default-b1-hcn2-fs6gs                             1/1     Running             3 (13d ago)        23d
libvirt-libvirt-default-b1-hcn2-fvd2d                             1/1     Running             0                  7d2h
libvirt-libvirt-default-b1-hcn2-hlk76                             1/1     Running             0                  7d2h
libvirt-libvirt-default-b1-hcn2-n7n9s                             1/1     Running             0                  7d2h
libvirt-libvirt-default-b1-hjr8j                                  1/1     Running             2 (14d ago)        23d
libvirt-libvirt-default-b1-knw7m                                  1/1     Running             2 (14d ago)        23d
libvirt-libvirt-default-b1-l4pjm                                  1/1     Running             2 (14d ago)        23d
libvirt-libvirt-default-b1-nz6ds                                  1/1     Running             2 (14d ago)        23d
libvirt-libvirt-default-b1-rlb86                                  1/1     Running             2 (16d ago)        23d
...
```

## helm values (테스트 환경)
```
(openstack-client) ubuntu@osh1:~$ helm ls -A
NAME                    NAMESPACE       REVISION        UPDATED                                 STATUS          CHART                           APP VERSION
ceph-adapter-rook       openstack       1               2026-02-24 10:13:14.124451075 +0900 KST deployed        ceph-adapter-rook-2025.2.0      v1.0.0
cinder                  openstack       1               2026-02-24 11:22:54.306253297 +0900 KST deployed        cinder-2025.2.0                 v1.0.0
glance                  openstack       1               2026-02-24 11:19:54.640978793 +0900 KST deployed        glance-2025.2.0                 v1.0.0
heat                    openstack       1               2026-02-24 10:50:34.63589835 +0900 KST  deployed        heat-2025.2.0                   v1.0.0
horizon                 openstack       1               2026-02-24 15:30:40.330886717 +0900 KST deployed        horizon-2025.2.0                v1.0.0
ingress-nginx           openstack       1               2026-02-24 10:02:25.244960542 +0900 KST deployed        ingress-nginx-4.8.3             1.9.4
keystone                openstack       1               2026-02-24 10:20:55.861283912 +0900 KST deployed        keystone-2025.2.0               v1.0.0
libvirt                 openstack       2               2026-02-26 13:11:31.060822304 +0900 KST deployed        libvirt-2025.2.0                v1.0.0
mariadb                 openstack       1               2026-02-24 10:18:31.782870629 +0900 KST deployed        mariadb-2025.2.0                v10.6.7
memcached               openstack       1               2026-02-24 10:20:10.687626568 +0900 KST deployed        memcached-2025.2.0              v1.5.5
neutron                 openstack       1               2026-02-24 12:26:01.311617503 +0900 KST deployed        neutron-2025.2.0                v1.0.0
nova                    openstack       1               2026-02-24 12:01:57.469012295 +0900 KST deployed        nova-2025.2.0                   v1.0.0
openvswitch             openstack       1               2026-02-24 11:28:46.624779268 +0900 KST deployed        openvswitch-2025.2.0            v1.0.0
placement               openstack       1               2026-02-24 11:32:48.505292368 +0900 KST deployed        placement-2025.2.0              v1.0.0
rabbitmq                openstack       1               2026-02-24 10:14:03.396943023 +0900 KST deployed        rabbitmq-2025.2.0               v3.12.0
rook-ceph               rook-ceph       1               2026-02-24 10:06:15.458338831 +0900 KST deployed        rook-ceph-v1.17.7               v1.17.7
rook-ceph-cluster       ceph            1               2026-02-24 10:06:26.116462166 +0900 KST deployed        rook-ceph-cluster-v1.17.7       v1.17.7

(openstack-client) ubuntu@osh1:~$ helm get values libvirt -nopenstack
USER-SUPPLIED VALUES:
conf:
  ceph:
    enabled: true
images:
  tags:
    libvirt: docker.io/openstackhelm/libvirt:2025.1-ubuntu_noble
```

## hsotPath (개발계:dev2 조회)

### nova-compute
```
root@SDS-7XDD-60399:~# kd get po nova-compute-default-a1-448zz -oyaml|grep -i hostpath -A1
  - hostPath:
      path: /var/lib/openstack-helm/compute/nova
  - hostPath:
      path: /dev/pts
  - hostPath:
      path: /lib/modules
  - hostPath:
      path: /var/lib/nova
  - hostPath:
      path: /var/lib/libvirt
  - hostPath:
      path: /run
  - hostPath:
      path: /sys/fs/cgroup
  - hostPath:
      path: /etc/machine-id
  - hostPath:
      path: /
  - hostPath:
      path: /run/lock
  - hostPath:
      path: /etc/iscsi
  - hostPath:
      path: /dev
  - hostPath:
      path: /etc/multipath
  - hostPath:
      path: /sys/block
  - hostPath:
      path: /var/run/ceph/guests
  - hostPath:
      path: /var/log/qemu
```

### libvirt
```
  - hostPath:
      path: /etc/multipath
  - hostPath:
      path: /etc/lvm
  - hostPath:
      path: /var/lib/openstack-helm/compute/libvirt
  - hostPath:
      path: /lib/modules
  - hostPath:
      path: /var/lib/libvirt
  - hostPath:
      path: /var/lib/nova
  - hostPath:
      path: /run
  - hostPath:
      path: /dev
  - hostPath:
      path: /var/log/libvirt
  - hostPath:
      path: /sys/fs/cgroup
  - hostPath:
      path: /etc/machine-id
  - hostPath:
      path: /etc/libvirt/qemu
  - hostPath:
      path: /var/run/ceph/guests
  - hostPath:
      path: /var/log/qemu
```	  
	  
