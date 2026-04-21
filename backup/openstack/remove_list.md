#### **1. k-log01-com301-krw1b** (Ceph MDS + Log 서버)

**삭제 추천 (Low Risk)**:
```bash
apport apport-symptoms whoopsie apport-core-dump-handler
ftp telnet inetutils-telnet
byobu screen tmux
strace gdb crash bpftrace bpfcc-tools
git buildah podman
bind9-dnsutils bind9-host bind9-libs
htop sysstat
snapd
```

**주의**: `ceph-base`, `ceph-common`, `ceph-mds`, `python3-ceph*` 등은 **절대 삭제 금지**

---

#### **2. k-scn01-con301-krw1b** (Control 노드)

**삭제 추천**:
```bash
apport apport-symptoms whoopsie
ftp telnet inetutils-telnet
byobu screen tmux
strace gdb crash bpftrace bpfcc-tools
git buildah podman
bind9-dnsutils bind9-host
htop sysstat
snapd
```

---

#### **3. k-vfwc01-nr303-krw1b** (Desktop/GUI 노드 - 가장 많이 제거 필요)

이 노드는 **데스크톱 환경**이 설치되어 있어 공격 표면이 매우 큽니다.

**강력 삭제 추천**:
```bash
# GUI 전체
gdm3 gnome-shell gnome-session ubuntu-desktop xserver-xorg* xorg
firefox evince seahorse virt-manager cups* bluez alsa* speech-dispatcher
baobab eog tracker* yelp zenity

# 게임/오락
aisleriot mahjongg gnome-mines gnome-sudoku

# 개발/디버그
strace gdb crash git buildah podman bpftrace bpfcc-tools

# 불필요 서비스
apport apport-symptoms whoopsie whoopsie-preferences
ftp telnet inetutils-telnet
byobu screen tmux htop sysstat
snapd
```

**이 노드는 GUI를 완전히 제거하는 것을 강력 추천**합니다.

---

#### **4. k-nn01-con301-krw1b** (Control 노드)

**삭제 추천**:
```bash
apport apport-symptoms whoopsie
ftp telnet inetutils-telnet
byobu screen tmux
strace gdb crash bpftrace bpfcc-tools
git buildah podman
bind9-dnsutils bind9-host
htop sysstat
snapd
```

---

#### **5. k-wproxy01-con301-krw1b** (WProxy 노드)

**삭제 추천**:
```bash
apport apport-symptoms whoopsie
ftp telnet inetutils-telnet
byobu screen tmux
strace gdb crash bpftrace bpfcc-tools
git buildah podman
bind9-dnsutils bind9-host
htop sysstat
snapd
```

---

**✅ Ceph 스토리지 노드 (k-cepho01) 패키지 분석 및 최소화 제안**

### 2. 제거 추천 카테고리 (위험도별)

| 위험도 | 카테고리 | 설명 | 제거 권장도 |
|--------|----------|------|-------------|
| **Low** | GUI / 데스크톱 | `gnome-*`, `xfce4-*`, `xserver-xorg*`, `lightdm` 등 | ★★★★★ (강력 권장) |
| **Low** | 게임 / 오락 | `aisleriot`, `atari800`, `gnome-games*` 등 | ★★★★★ |
| **Low** | 미디어 / 오피스 | `libreoffice*`, `audacity`, `vlc`, `rhythmbox` 등 | ★★★★☆ |
| **Low** | 불필요 클라이언트 | `ftp`, `telnet`, `whois`, `finger` | ★★★★★ |
| **Medium** | 개발 도구 | `gcc`, `make`, `cmake`, `python3-dev`, `build-essential` | ★★★★☆ (Ceph 개발 안 하면 제거) |
| **Medium** | 오류 보고 도구 | `apport`, `whoopsie`, `apport-symptoms` | ★★★★☆ (개인정보 + 공격 표면) |
| **Medium** | 문서 패키지 | `*-doc`, `*-man` 대량 | ★★★☆☆ (용량 절감) |
| **High** | Ceph 관련 | `ceph*`, `rados*`, `rbd*`, `librados*` | **절대 제거 금지** |
| **High** | 시스템 핵심 | `systemd`, `dbus`, `apparmor`, `auditd`, `aide`, `openssh-server` | **절대 제거 금지** |

---

### 3. 주요 제거 추천 패키지 목록 (실제 목록 기반)

**Low Risk (즉시 제거 가능)**

```bash
# GUI / 데스크톱
gnome-shell gnome-session gdm3 lightdm xserver-xorg* ubuntu-desktop

# 게임
aisleriot atari800 gnome-games* mahjongg

# 미디어 / 오피스
libreoffice* audacity rhythmbox totem vlc

# 불필요 클라이언트
ftp telnet whois finger rsh-client

# 오류 보고 (개인정보 수집)
apport apport-symptoms whoopsie
```

**Medium Risk (테스트 후 제거 권장)**

```bash
# 개발 도구 (Ceph 노드에서는 거의 불필요)
gcc g++ make cmake autoconf automake libtool python3-dev build-essential

# 문서 패키지 (용량 절감)
*-doc *-manpages

# 기타 bloat
byobu screen tmux  # (하나만 유지 추천)
snapd  # (필요 없다면)
```

---
