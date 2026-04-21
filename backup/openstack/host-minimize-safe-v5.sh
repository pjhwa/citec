#!/usr/bin/env bash
#
# host-minimize-safe-v5.sh
# Universal Host OS Minimization Script v5.0
# Target: Samsung SDS SCPv2 Sovereign (Ubuntu 22.04/24.04)
# Supports: Ceph / Compute / K8s Worker / K8s Control / Network / Generic
#
# Version: 5.0
#   - v4.2 의 치명적 버그 수정 (set -e + (()) 트랩, grep 매칭 오류, 로케일 의존성)
#   - Risk Report 모드 추가 (--risk-report)
#   - 노드 타입 세분화 (cephadm, k8s-worker, k8s-control, compute-bare, network)
#   - Extended baseline (services / ports / kernel modules / /etc / routes / mounts)
#   - Lock 파일, SSH 안정성 사전 점검, LVM snapshot 유도
#   - podman/docker/containerd 등 런타임 whitelist 보강 (cephadm/Rook/K8s 필수)
#   - ANSI 컬러 제거된 plain-text 병렬 로그
#   - Plan export (--plan-out <file>.yaml)
#
# 사용 시나리오:
#   1. 먼저 dry-run 분석 :  sudo ./host-minimize-safe-v5.sh
#   2. 위험도 리포트       :  sudo ./host-minimize-safe-v5.sh --risk-report
#   3. 프로파일 강제        :  sudo ./host-minimize-safe-v5.sh --profile cephadm
#   4. 실제 제거           :  sudo ./host-minimize-safe-v5.sh --execute
#
set -Euo pipefail

# ============================================================================
# 0. GLOBAL CONSTANTS
# ============================================================================
SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="5.0"
SCRIPT_DATE="2026-04-21"

LOG_DIR="/var/log/host-minimize"
STATE_DIR="/var/lib/host-minimize"
BASELINE_DIR="${STATE_DIR}/baseline"
ROLLBACK_DIR="${STATE_DIR}/rollback"
RISK_DIR="${STATE_DIR}/risk"
LOCK_FILE="${STATE_DIR}/minimize.lock"
CONFIG_FILE="/etc/host-minimize/exclude.conf"
TS="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${LOG_DIR}/minimize-v5-${TS}.log"
PLAIN_LOG_FILE="${LOG_DIR}/minimize-v5-${TS}.plain.log"

# Colors (terminal only — 파일 로그에는 strip)
if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; MAGENTA=''; CYAN=''; NC=''
fi

# Flags
EXECUTE_MODE=false
RISK_REPORT=false
SHOW_FULL_TREE=false
AUTO_YES=false
SKIP_SNAPSHOT_CHECK=false
SKIP_SSH_CHECK=false
PLAN_OUT=""
PROFILE="auto"
EXCLUDE_CLI=()
NODE_TYPE="unknown"

# apt 출력은 항상 C 로케일 강제 (파싱 안정성)
export LC_ALL=C.UTF-8
export LANG=C.UTF-8
export DEBIAN_FRONTEND=noninteractive

# ============================================================================
# 1. LOGGING (컬러 제거된 plain 로그 분리 저장)
# ============================================================================
init_logging() {
    mkdir -p "$LOG_DIR" "$STATE_DIR" "$BASELINE_DIR" "$ROLLBACK_DIR" "$RISK_DIR"
    chmod 0700 "$LOG_DIR" "$STATE_DIR"
    : > "$LOG_FILE"
    : > "$PLAIN_LOG_FILE"
    chmod 0600 "$LOG_FILE" "$PLAIN_LOG_FILE"
}

# strip ANSI
_strip_ansi() { sed -E 's/\x1b\[[0-9;]*[a-zA-Z]//g'; }

log() {
    local level="$1"; shift
    local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
    local msg="[$ts] [$(printf '%-5s' "$level")] $*"
    local colored="$msg"
    case "$level" in
        INFO)  colored="${GREEN}${msg}${NC}" ;;
        WARN)  colored="${YELLOW}${msg}${NC}" ;;
        ERROR) colored="${RED}${msg}${NC}" ;;
        CRIT)  colored="${RED}${msg}${NC}" ;;
        RISK)  colored="${MAGENTA}${msg}${NC}" ;;
        OK)    colored="${GREEN}${msg}${NC}" ;;
    esac
    echo -e "$colored" | tee -a "$LOG_FILE" >/dev/null
    echo "$msg" >> "$PLAIN_LOG_FILE"
    echo -e "$colored"
}

hr() { echo -e "${BLUE}────────────────────────────────────────────────────────────────────────────${NC}"; }

print_header() {
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}           Host OS Minimization Script v${SCRIPT_VERSION}  (${SCRIPT_DATE})              ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}           Profiles: ceph / cephadm / compute / k8s / network / generic      ${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo
}

# ============================================================================
# 2. ERROR TRAPPING
# ============================================================================
on_err() {
    local ec=$?
    log CRIT "Unexpected failure (exit=${ec}) at line ${BASH_LINENO[0]} : ${BASH_COMMAND}"
    release_lock
    exit "$ec"
}
on_exit() { release_lock; }
trap on_err ERR
trap on_exit EXIT

# ============================================================================
# 3. LOCK
# ============================================================================
acquire_lock() {
    if [[ -e "$LOCK_FILE" ]]; then
        local pid; pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        if [[ -n "$pid" && -d "/proc/$pid" ]]; then
            log CRIT "다른 인스턴스가 실행 중입니다 (PID=$pid). 종료합니다."
            exit 1
        else
            log WARN "Stale lock 제거 ($LOCK_FILE)"
            rm -f "$LOCK_FILE"
        fi
    fi
    echo "$$" > "$LOCK_FILE"
}
release_lock() { [[ -f "$LOCK_FILE" ]] && rm -f "$LOCK_FILE" || true; }

# ============================================================================
# 4. WHITELISTS / SAFE REMOVE
# ============================================================================
# 모든 노드 공통 — 부팅·보안·원격접속 필수
COMMON_WHITELIST=(
    # init / core
    "systemd*" "dbus*" "udev" "libpam*" "login" "util-linux" "mount" "sudo"
    "coreutils" "bash" "dash" "procps" "iproute2" "iptables" "nftables"
    # kernel / boot
    "grub*" "linux-image*" "linux-headers*" "linux-modules*" "linux-firmware"
    "initramfs-tools*" "cryptsetup*" "lvm2"
    # network basic
    "netplan.io" "isc-dhcp-client" "netbase" "ifupdown" "resolvconf"
    # security / compliance (CSAP)
    "apparmor*" "auditd" "audispd-plugins" "aide*" "libselinux1"
    "unattended-upgrades" "apt-listchanges"
    # package mgmt
    "apt" "apt-utils" "dpkg" "gnupg*" "ca-certificates" "debconf"
    # remote access
    "openssh-server" "openssh-client"
    # logging & time
    "rsyslog" "logrotate" "chrony" "systemd-timesyncd"
    # monitoring / agent 유지 (보안 요구)
    "snmpd" "snmp"
    # 필수 텍스트/진단
    "vim-tiny" "nano" "less" "grep" "sed" "gawk" "tar" "gzip" "xz-utils" "file"
)

# Profile별 추가 whitelist
CEPH_WHITELIST=(
    "ceph*" "rados*" "rbd*" "librados*" "librbd*" "libceph*" "ceph-common"
    "xfsprogs" "smartmontools" "nvme-cli" "hdparm"
)
# Cephadm = Ceph + 컨테이너 런타임 필수
CEPHADM_WHITELIST=(
    "${CEPH_WHITELIST[@]}"
    "podman" "containers-common" "runc" "catatonit" "crun" "slirp4netns"
    "uidmap" "fuse-overlayfs" "skopeo" "buildah"   # cephadm orch 사용
)
COMPUTE_WHITELIST=(
    "qemu*" "libvirt*" "virtiofsd" "virtlogd" "openvswitch*" "ovn*"
    "dnsmasq*" "ebtables" "bridge-utils" "ipset" "conntrack" "ipvsadm"
    "numactl" "cpu-checker" "msr-tools" "hwloc*"
)
K8S_WHITELIST=(
    "kubelet" "kubeadm" "kubectl" "kubernetes-cni" "cri-tools"
    "containerd*" "runc" "podman" "cni-plugins"
    "socat" "conntrack" "ipset" "ethtool" "ebtables"
)
K8S_CONTROL_WHITELIST=(
    "${K8S_WHITELIST[@]}"
    "haproxy" "keepalived"
)
NETWORK_WHITELIST=(
    "frr*" "bird*" "keepalived" "haproxy" "nginx*" "strongswan*" "xl2tpd"
    "openvswitch*" "ovn*" "conntrack" "ipvsadm" "ipset" "ebtables"
    "bridge-utils" "dnsmasq*" "radvd"
)

# 제거 후보 (기본) — 프로파일 필터링 후 실제 매칭
DEFAULT_SAFE_REMOVE=(
    # GUI (서버에 불필요)
    "gnome-shell" "gnome-session" "gdm3" "lightdm" "xserver-xorg*" "xwayland"
    "ubuntu-desktop*" "xfce4*" "lxde*" "kde-*" "plasma-*" "gnome-*"
    # 게임/멀티미디어
    "aisleriot" "atari800" "mahjongg" "gnome-games*" "libreoffice*"
    "audacity" "rhythmbox" "totem" "vlc" "celluloid" "cheese" "shotwell"
    # 레거시 평문 프로토콜 (CSAP 통제 대상)
    "ftp" "telnet" "inetutils-telnet" "rsh-client" "rsh-server"
    "nis" "yp-tools" "talk" "talkd" "tftp" "tftpd"
    # 프라이버시/정보노출
    "whois" "finger"
    # 크래시 리포트 (민감정보 유출 위험)
    "apport" "apport-symptoms" "whoopsie" "apport-core-dump-handler" "ubuntu-report"
    "popularity-contest"
    # 멀티플렉서 (운영 중에는 OK지만 공격면)
    "byobu" "screen" "tmux"
    # 디버그/트레이스 (CSAP: 별도 승인 없이 상주 금지)
    "strace" "gdb" "crash" "bpftrace" "bpfcc-tools" "trace-cmd" "ltrace"
    "systemtap*" "sysdig"
    # 빌드/VCS (프로덕션에는 불필요)
    "git" "subversion" "mercurial"
    # 컨테이너 (역할에 따라 whitelist 처리)
    "buildah" "podman" "docker.io" "docker-ce" "docker-ce-cli"
    # DNS 진단 (network 노드만 제외)
    "bind9-dnsutils" "bind9-host" "bind9utils"
    # 퍼포먼스 도구 (필요 시 emergency kit로 재설치)
    "htop" "sysstat" "iotop" "nethogs" "iftop"
    # Snap (서버 공격면 축소)
    "snapd"
)

# ============================================================================
# 5. RISK CATALOG (패키지별 제거 위험 설명)
# ============================================================================
declare -A RISK_DESC=(
    [strace]="시스템콜 트레이스 불가 → 장애 진단 시 커널 레벨 분석 어려움"
    [gdb]="코어덤프 분석 불가 → 프로세스 크래시 원인 규명 제한"
    [bpftrace]="eBPF 기반 성능/장애 분석 불가"
    [bpfcc-tools]="biolatency, tcpconnect 등 BCC 툴 상실"
    [tcpdump]="네트워크 패킷 캡처 불가 — 단, 이 목록에 포함시에만 해당"
    [strace]="syscall 레벨 디버깅 불가"
    [screen]="백그라운드 세션 상실 — systemd-run으로 대체 가능"
    [tmux]="백그라운드 세션 상실 — systemd-run으로 대체 가능"
    [byobu]="세션 래퍼 상실"
    [git]="현장 hotfix시 remote pull 불가 — Ansible/SCM 기반 운영 필요"
    [podman]="cephadm/K8s 이미지 수동 검사 불가. cephadm 노드에서는 제거 절대 금지!"
    [buildah]="컨테이너 이미지 로컬 빌드 불가"
    [docker.io]="Docker 상실 — containerd 직접 사용 가능. K8s에 영향 없음."
    [htop]="top 대체 시각화 상실 — coreutils top은 유지"
    [sysstat]="sar 데이터 수집 중단 → 과거 성능 추세 분석 불가 (CSAP 고려 필요)"
    [iotop]="I/O 소비 프로세스 실시간 관찰 불가"
    [bind9-dnsutils]="dig, nslookup 상실 — DNS 장애 진단 어려움"
    [bind9-host]="host 명령 상실"
    [snapd]="snap 설치 앱이 있으면 연쇄 고장. lxd, microk8s 등 체크 필수"
    [apport]="크래시 자동 수집 중단 (민감정보 유출 위험 감소 → CSAP 권장)"
    [whoopsie]="Ubuntu 에러 리포트 상실"
    [ubuntu-report]="시스템 메트릭 외부 송신 중단 (CSAP 권장)"
    [telnet]="평문 원격접속 클라이언트 상실 (CSAP 8.x 계열 필수 제거)"
    [ftp]="평문 FTP 클라이언트 상실 (CSAP 8.x 계열 필수 제거)"
    [rsh-client]="평문 rsh 상실 (CSAP 필수 제거)"
    [whois]="whois 조회 상실"
    [finger]="finger 상실"
    [gdm3]="GUI 로그인 매니저 제거 → 콘솔로만 로그인 가능"
    [gnome-shell]="GNOME GUI 상실"
    [xserver-xorg-core]="X 서버 상실 → GUI 완전 불가"
    [crash]="kdump 분석 상실 → 커널 패닉 사후분석 제한"
    [trace-cmd]="ftrace 프론트엔드 상실"
)

declare -A CSAP_MAP=(
    [telnet]="2.4.1 (평문 프로토콜 금지)"
    [ftp]="2.4.1 (평문 프로토콜 금지)"
    [rsh-client]="2.4.1 (평문 프로토콜 금지)"
    [rsh-server]="2.4.1 (평문 프로토콜 금지)"
    [finger]="2.4.2 (사용자 정보 노출 금지)"
    [whois]="2.4.2"
    [tftp]="2.4.1"
    [talk]="2.4.2"
    [snapd]="9.3 (불필요 서비스 제거)"
    [apport]="8.5 (민감정보 유출 방지)"
    [whoopsie]="8.5"
    [ubuntu-report]="8.5"
    [gnome-shell]="9.3 (불필요 GUI 제거)"
    [gdm3]="9.3"
    [xserver-xorg-core]="9.3"
    [git]="9.3 (개발도구 상주 금지)"
    [buildah]="9.3"
)

# ============================================================================
# 6. PROFILE DETECTION (개선)
# ============================================================================
validate_profile() {
    case "$PROFILE" in
        auto|ceph|cephadm|compute|k8s-worker|k8s-control|network|generic) ;;
        *) log ERROR "알 수 없는 profile: $PROFILE"; usage; exit 2 ;;
    esac
}

detect_node_type() {
    if [[ "$PROFILE" != "auto" ]]; then
        NODE_TYPE="$PROFILE"
        return
    fi
    # 우선순위: ceph/cephadm > k8s-control > k8s-worker > compute > network > generic
    # 1) cephadm: /var/lib/ceph 아래 fsid 디렉토리 or `cephadm ls` 가능
    if command -v cephadm &>/dev/null && [[ -d /var/lib/ceph ]]; then
        NODE_TYPE="cephadm"; return
    fi
    # 2) 전통 Ceph: systemd ceph-osd 활성
    if command -v ceph &>/dev/null && [[ -f /etc/ceph/ceph.conf ]]; then
        # ceph-osd/mon/mgr 데몬이 systemd에 올라가 있는지
        if systemctl list-units --type=service --all 2>/dev/null | grep -qE 'ceph-(osd|mon|mgr|mds)@'; then
            NODE_TYPE="ceph"; return
        fi
        # Ceph client 전용 (설정만 있음) → 타입 확정 전에 K8s/compute 체크
    fi
    # 3) K8s: kubelet + etcd/kube-apiserver manifest → control plane
    if systemctl is-active --quiet kubelet 2>/dev/null; then
        if [[ -f /etc/kubernetes/manifests/kube-apiserver.yaml ]] || \
           [[ -f /etc/kubernetes/manifests/etcd.yaml ]]; then
            NODE_TYPE="k8s-control"; return
        fi
        NODE_TYPE="k8s-worker"; return
    fi
    # 4) Compute (OpenStack bare-metal)
    if systemctl is-active --quiet libvirtd 2>/dev/null || command -v qemu-system-x86_64 &>/dev/null; then
        NODE_TYPE="compute"; return
    fi
    # 5) Network: frr, bird, haproxy 활성
    if systemctl is-active --quiet frr 2>/dev/null || \
       systemctl is-active --quiet bird 2>/dev/null || \
       systemctl is-active --quiet keepalived 2>/dev/null; then
        NODE_TYPE="network"; return
    fi
    NODE_TYPE="generic"
}

get_whitelist() {
    local wl=("${COMMON_WHITELIST[@]}")
    case "$NODE_TYPE" in
        ceph)        wl+=("${CEPH_WHITELIST[@]}") ;;
        cephadm)     wl+=("${CEPHADM_WHITELIST[@]}") ;;
        compute)     wl+=("${COMPUTE_WHITELIST[@]}") ;;
        k8s-worker)  wl+=("${K8S_WHITELIST[@]}") ;;
        k8s-control) wl+=("${K8S_CONTROL_WHITELIST[@]}") ;;
        network)     wl+=("${NETWORK_WHITELIST[@]}") ;;
    esac
    printf '%s\n' "${wl[@]}"
}

# ============================================================================
# 7. PRE-FLIGHT CHECKS
# ============================================================================
check_root() {
    [[ $EUID -eq 0 ]] || { log ERROR "root 권한으로 실행해야 합니다."; exit 1; }
}

check_ssh_stability() {
    $SKIP_SSH_CHECK && { log WARN "SSH 안정성 체크 스킵"; return 0; }
    # 최근 1분간 dmesg에 eno/enp/eth 링크 다운 기록이 있는지
    if dmesg -T 2>/dev/null | tail -200 | grep -qE 'Link is Down|link down|NIC Link is Down'; then
        log CRIT "최근 NIC Link Down 로그 발견 → SSH 단절 위험. 확인 후 진행하세요."
        return 1
    fi
    # 현재 SSH 세션 SRC IP 출력
    local src; src=$(who am i 2>/dev/null | awk '{print $NF}' | tr -d '()' || true)
    log INFO "현재 SSH source: ${src:-N/A}"
    log OK "SSH 안정성 체크 통과"
}

check_ceph_health() {
    [[ "$NODE_TYPE" != "ceph" && "$NODE_TYPE" != "cephadm" ]] && return 0
    log INFO "Ceph Health Check (timeout 10s)..."
    local health
    if ! health=$(timeout 10 ceph health 2>/dev/null | awk '{print $1}'); then
        log CRIT "Ceph 상태 조회 실패 또는 timeout"
        return 1
    fi
    if [[ "$health" != "HEALTH_OK" ]]; then
        log CRIT "Ceph cluster 상태: $health — 중단합니다."
        log WARN "  해결: ceph status / ceph health detail 로 확인 후 재시도"
        return 1
    fi
    log OK "Ceph cluster: HEALTH_OK"
    # orch 확인
    if command -v cephadm &>/dev/null; then
        local orch; orch=$(timeout 10 ceph orch status 2>/dev/null | head -5 || echo "")
        [[ -n "$orch" ]] && log INFO "ceph orch status:" && echo "$orch" | sed 's/^/   /'
    fi
}

check_k8s_health() {
    [[ "$NODE_TYPE" != k8s-* ]] && return 0
    if ! systemctl is-active --quiet kubelet; then
        log CRIT "kubelet 비활성 — K8s 노드 상태 비정상. 중단."; return 1
    fi
    log OK "kubelet active"
    # 노드 cordon 권장 메시지
    log WARN "권장: 패키지 제거 전에 'kubectl cordon <node>' 실행"
}

check_disk_space() {
    # apt purge는 디스크 공간 증가시키지만, 백업/로그용 여유 필요
    local avail; avail=$(df -Pk "$STATE_DIR" | awk 'NR==2 {print $4}')
    if [[ $avail -lt 1048576 ]]; then
        log ERROR "백업 공간 부족 (<1GB at $STATE_DIR)"; return 1
    fi
    log OK "백업 공간 여유: $((avail/1024)) MB"
}

check_snapshot_recommendation() {
    $SKIP_SNAPSHOT_CHECK && return 0
    $EXECUTE_MODE || return 0
    # LVM snapshot 존재 여부 힌트
    if command -v lvs &>/dev/null; then
        local snap; snap=$(lvs --noheadings -o lv_name,lv_attr 2>/dev/null | awk '$2 ~ /^s/ {print $1}' || true)
        if [[ -z "$snap" ]]; then
            log WARN "LVM 스냅샷 없음. 실제 제거 전에 스냅샷 생성을 강력 권장:"
            log WARN "   예: lvcreate -L 5G -s -n root_premin /dev/ubuntu-vg/root"
            if ! $AUTO_YES; then
                read -rp "스냅샷 없이 계속하시겠습니까? (yes 입력): " ok
                [[ "$ok" != "yes" ]] && { log INFO "사용자 중단"; exit 0; }
            fi
        else
            log OK "LVM 스냅샷 발견: $snap"
        fi
    else
        log WARN "LVM 미사용 (lvs 없음) — 파일시스템 스냅샷 도구로 직접 백업 권장"
    fi
}

# ============================================================================
# 8. BASELINE & ROLLBACK (확장)
# ============================================================================
backup_baseline() {
    local base="${BASELINE_DIR}/${TS}"
    mkdir -p "$base"

    dpkg --get-selections > "${base}/dpkg-selections.txt"
    dpkg -l > "${base}/dpkg-l.txt" 2>/dev/null || true
    apt-mark showmanual > "${base}/apt-manual.txt" 2>/dev/null || true
    apt-mark showauto > "${base}/apt-auto.txt" 2>/dev/null || true

    systemctl list-unit-files --type=service --state=enabled > "${base}/services-enabled.txt" 2>/dev/null || true
    systemctl list-units --type=service --state=running > "${base}/services-running.txt" 2>/dev/null || true

    ss -tlnpu > "${base}/ports.txt" 2>/dev/null || true
    lsmod > "${base}/lsmod.txt" 2>/dev/null || true
    ip -br addr > "${base}/ip-addr.txt" 2>/dev/null || true
    ip route > "${base}/ip-route.txt" 2>/dev/null || true
    mount > "${base}/mount.txt" 2>/dev/null || true

    # /etc 전체 tarball (config 보존)
    tar --exclude='/etc/shadow*' --exclude='/etc/gshadow*' \
        -czf "${base}/etc-snapshot.tar.gz" /etc 2>/dev/null || true

    # rollback용 고정 경로
    cp "${base}/dpkg-selections.txt" "${ROLLBACK_DIR}/pre-removal-selections.txt"
    cp "${base}/apt-manual.txt" "${ROLLBACK_DIR}/pre-removal-manual.txt" 2>/dev/null || true

    log OK "Baseline 저장: $base"
    log INFO "  - dpkg-selections, dpkg -l, apt-mark, services, ports, lsmod, /etc snapshot"
}

create_rollback_script() {
    local rb="${ROLLBACK_DIR}/rollback-v5-${TS}.sh"
    cat > "$rb" << EOF
#!/usr/bin/env bash
# Auto-generated rollback script (v5.0) - ${TS}
set -Euo pipefail
export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C.UTF-8

echo "=== ROLLBACK v5.0 (${TS}) ==="
echo "이 스크립트는 패키지 선택(selections)만 복원합니다."
echo "설정 파일은 /var/lib/host-minimize/baseline/${TS}/etc-snapshot.tar.gz 에서 수동 복원하세요."
read -rp "진행하시겠습니까? (yes 입력): " ok
[[ "\$ok" == "yes" ]] || { echo "취소"; exit 0; }

apt-get update || true
dpkg --set-selections < /var/lib/host-minimize/rollback/pre-removal-selections.txt
apt-get -y dselect-upgrade

# manual marking 복원
if [[ -f /var/lib/host-minimize/rollback/pre-removal-manual.txt ]]; then
    xargs -a /var/lib/host-minimize/rollback/pre-removal-manual.txt -r apt-mark manual || true
fi

echo "=== 복원 완료. reboot 권장. ==="
echo "※ /etc 설정 복원이 필요하면:"
echo "   tar -tzf /var/lib/host-minimize/baseline/${TS}/etc-snapshot.tar.gz | less"
echo "   (선택적으로 파일 단위 복원 후 서비스 재시작)"
EOF
    chmod +x "$rb"
    log OK "Rollback 스크립트 생성: $rb"
}

# ============================================================================
# 9. DEPENDENCY ANALYSIS (정확도 개선)
# ============================================================================

# 설치된 패키지 중 해당 패키지에 의존하는 것만 반환
get_direct_dependents() {
    local pkg="$1"
    # apt-cache rdepends는 모든 역의존 반환 → dpkg -l 로 설치 필터
    apt-cache rdepends --no-suggests --no-conflicts --no-breaks \
        --no-replaces --no-enhances --installed "$pkg" 2>/dev/null \
        | tail -n +3 | sed 's/^[[:space:]]*//' | grep -v '^$' \
        | grep -vFx "$pkg" | sort -u
}

# $pkg가 whitelist 중 하나에 glob 매칭되는가
matches_whitelist() {
    local pkg="$1"; shift
    local w
    for w in "$@"; do
        # glob pattern match
        case "$pkg" in
            $w) return 0 ;;
        esac
    done
    return 1
}

# 제거했을 때 whitelist의 critical 패키지가 영향받는지
check_critical_reverse_deps() {
    local pkg="$1"
    local wl_arr=()
    mapfile -t wl_arr < <(get_whitelist)
    local deps dep
    deps=$(get_direct_dependents "$pkg")
    for dep in $deps; do
        if matches_whitelist "$dep" "${wl_arr[@]}"; then
            printf "  %b[CRITICAL]%b %s → depends on it: %s\n" "$RED" "$NC" "$dep" "$pkg"
            return 1
        fi
    done
    return 0
}

# 패키지 삭제 시 자동 연쇄 제거될 패키지 수 (apt-get -s 파싱)
count_cascade_removals() {
    local pkg="$1"
    apt-get -s -y --auto-remove purge "$pkg" 2>/dev/null \
      | awk '/^(Remv|Purg) / {c++} END {print c+0}'
}

# 위상 정렬 — 의존 관계가 많은 것을 나중에 제거
get_removal_order() {
    local -n arr_ref=$1
    local pkg other
    local tmp; tmp=$(mktemp)
    for pkg in "${arr_ref[@]}"; do
        local deps_count=0
        # 다른 제거 대상들이 이 pkg에 의존하는가?
        for other in "${arr_ref[@]}"; do
            [[ "$pkg" == "$other" ]] && continue
            if apt-cache depends --installed "$other" 2>/dev/null \
                | awk '/^[[:space:]]*(Depends|PreDepends):/ {print $2}' \
                | grep -Fxq "$pkg"; then
                deps_count=$((deps_count + 1))
            fi
        done
        printf '%d\t%s\n' "$deps_count" "$pkg" >> "$tmp"
    done
    sort -n "$tmp" | cut -f2-
    rm -f "$tmp"
}

# ============================================================================
# 10. BUILD REMOVAL CANDIDATES
# ============================================================================
build_candidates() {
    local whitelist
    mapfile -t whitelist < <(get_whitelist)

    # CLI exclude + config file exclude 합침
    local exclude_merge=("${EXCLUDE_CLI[@]}")
    if [[ -f "$CONFIG_FILE" ]]; then
        local line
        while IFS= read -r line; do
            line="${line%%#*}"
            line="${line// /}"
            [[ -n "$line" ]] && exclude_merge+=("$line")
        done < "$CONFIG_FILE"
    fi

    # 설치된 패키지 전체
    local installed
    installed=$(dpkg-query -W -f='${binary:Package}\n' 2>/dev/null | awk -F: '{print $1}' | sort -u)

    local cand=()
    local pat
    for pat in "${DEFAULT_SAFE_REMOVE[@]}"; do
        local match
        # glob → 실제 패키지명 목록으로 확장
        while IFS= read -r match; do
            [[ -z "$match" ]] && continue
            # whitelist 매칭 제외
            if matches_whitelist "$match" "${whitelist[@]}"; then continue; fi
            # exclude 매칭 제외
            local ex found=false
            for ex in "${exclude_merge[@]}"; do
                [[ "$match" == "$ex" ]] && found=true && break
            done
            $found && continue
            cand+=("$match")
        done < <(printf '%s\n' "$installed" | awk -v p="$pat" '
                BEGIN {
                    # glob → regex 변환
                    gsub(/\./, "\\.", p)
                    gsub(/\*/, ".*", p)
                    gsub(/\?/, ".", p)
                    p = "^" p "$"
                }
                $0 ~ p { print }')
    done
    # 중복 제거
    printf '%s\n' "${cand[@]}" | awk '!seen[$0]++'
}

# ============================================================================
# 11. DRY-RUN ANALYSIS (정보량 확대)
# ============================================================================
dry_run_full_analysis() {
    local -a packages=("$@")

    print_header
    log INFO "노드 타입: $NODE_TYPE"
    log INFO "제거 후보 개수: ${#packages[@]}"
    hr

    # Phase 1: Critical reverse dep 체크
    log INFO "Phase 1 — Whitelist 대상 역의존 검사"
    local critical_count=0 pkg
    for pkg in "${packages[@]}"; do
        dpkg -l 2>/dev/null | awk -v p="$pkg" '$1=="ii" && $2==p{found=1} END{exit !found}' || continue
        if ! check_critical_reverse_deps "$pkg"; then
            critical_count=$((critical_count + 1))
        fi
    done
    if [[ $critical_count -gt 0 ]]; then
        log CRIT "$critical_count 건의 critical 역의존 발견 — 해당 패키지를 whitelist에 추가하거나 --exclude 하세요."
        return 2
    fi
    log OK "Critical 역의존 없음"
    hr

    # Phase 2: 연쇄 제거 분석 + 순서
    log INFO "Phase 2 — 연쇄 제거 및 위상 정렬"
    local ordered
    mapfile -t ordered < <(get_removal_order packages)

    local total_direct=0 total_cascade=0
    printf "\n  %-35s %8s %10s %-20s\n" "PACKAGE" "DIRECT" "CASCADE" "CSAP"
    printf "  %-35s %8s %10s %-20s\n" "-------" "------" "-------" "----"
    for pkg in "${ordered[@]}"; do
        dpkg -l 2>/dev/null | awk -v p="$pkg" '$1=="ii" && $2==p{found=1} END{exit !found}' || continue
        local direct cascade csap
        direct=$(get_direct_dependents "$pkg" | wc -l)
        cascade=$(count_cascade_removals "$pkg")
        csap="${CSAP_MAP[$pkg]:-—}"
        printf "  %-35s %8d %10d %-20s\n" "$pkg" "$direct" "$cascade" "$csap"
        if $SHOW_FULL_TREE; then
            apt-cache depends --installed "$pkg" 2>/dev/null \
                | awk '/^[[:space:]]+(Depends|PreDepends):/ {print "        ↳ " $2}' \
                | head -8
        fi
        total_direct=$((total_direct + 1))
        total_cascade=$((total_cascade + cascade))
    done

    echo
    hr
    local total=$((total_direct + total_cascade))
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║${NC} DRY-RUN v5.0 SUMMARY  (node: ${NODE_TYPE})"
    echo -e "${MAGENTA}╠══════════════════════════════════════════════════════════════════════════════╣${NC}"
    printf  "${MAGENTA}║${NC}   직접 제거 대상     : %4d 개\n" "$total_direct"
    printf  "${MAGENTA}║${NC}   연쇄 제거 예상     : %4d 개\n" "$total_cascade"
    printf  "${MAGENTA}║${NC}   총 영향 패키지     : %4d 개\n" "$total"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo

    # Plan 파일 출력
    if [[ -n "$PLAN_OUT" ]]; then
        {
            echo "# host-minimize-safe-v5 plan"
            echo "generated_at: $(date -Is)"
            echo "node_type: $NODE_TYPE"
            echo "direct_count: $total_direct"
            echo "cascade_count: $total_cascade"
            echo "packages:"
            local p
            for p in "${ordered[@]}"; do
                dpkg -l 2>/dev/null | awk -v q="$p" '$1=="ii" && $2==q{f=1} END{exit !f}' || continue
                echo "  - $p"
            done
        } > "$PLAN_OUT"
        log OK "Plan 파일 저장: $PLAN_OUT"
    fi

    log INFO "실제 제거 명령  :  sudo $0 --execute --profile $NODE_TYPE"
    log INFO "위험도 상세     :  sudo $0 --risk-report --profile $NODE_TYPE"
}

# ============================================================================
# 12. RISK REPORT (새 모드)
# ============================================================================
risk_report() {
    local -a packages=("$@")
    print_header
    log INFO "RISK REPORT — 노드: $NODE_TYPE"
    hr
    local pkg
    for pkg in "${packages[@]}"; do
        dpkg -l 2>/dev/null | awk -v p="$pkg" '$1=="ii" && $2==p{found=1} END{exit !found}' || continue
        local desc="${RISK_DESC[$pkg]:-—}"
        local csap="${CSAP_MAP[$pkg]:-—}"
        local cascade; cascade=$(count_cascade_removals "$pkg")
        printf "  %b▶%b %s\n" "$CYAN" "$NC" "$pkg"
        printf "     CSAP mapping    : %s\n" "$csap"
        printf "     잃는 기능        : %s\n" "$desc"
        printf "     연쇄 제거 개수   : %d\n" "$cascade"
        if (( cascade > 20 )); then
            printf "     %b⚠ 대규모 연쇄 — 수동 리뷰 권장%b\n" "$YELLOW" "$NC"
        fi
        echo
    done

    # Emergency toolkit 가이드
    cat <<EOT

${YELLOW}※ Emergency Toolkit 제안${NC}
  장애 진단 도구를 제거하면 운영 시 복구 속도가 느려질 수 있습니다.
  아래 방식 중 하나를 준비해 두세요:
    A) 각 노드에 별도 debug-pkgs.deb 번들 준비 후 필요시만 dpkg -i
    B) 사내 APT 미러에서 strace/gdb/bpftrace를 즉시 설치 가능하도록 보장
    C) nsenter/kubectl debug(k8s) 사용 시에는 debug 사이드카 이미지 활용

${YELLOW}※ CSAP 대응${NC}
  본 스크립트는 CSAP 불필요 서비스/패키지 항목(2.4, 8.5, 9.3 계열)을 타겟으로 합니다.
  사내 보안 정책 및 감사 체크리스트와 매핑 후 승인받으세요.
EOT
}

# ============================================================================
# 13. REAL REMOVAL
# ============================================================================
real_removal() {
    local -a packages=("$@")
    print_header
    log WARN "=== REAL REMOVAL MODE ==="
    log WARN "제거 대상: ${#packages[@]} 개"

    if ! $AUTO_YES; then
        read -rp "정말로 삭제를 진행하시겠습니까? (YES 대문자 입력): " confirm
        [[ "$confirm" == "YES" ]] || { log INFO "취소됨"; exit 0; }
    fi

    local ordered
    mapfile -t ordered < <(get_removal_order packages)
    local failed=()
    local pkg
    for pkg in "${ordered[@]}"; do
        dpkg -l 2>/dev/null | awk -v p="$pkg" '$1=="ii" && $2==p{found=1} END{exit !found}' || continue
        log INFO "Removing: $pkg"
        if ! apt-get -y purge "$pkg" >>"$LOG_FILE" 2>&1; then
            log ERROR "실패: $pkg"
            failed+=("$pkg")
        fi
    done

    log INFO "자동 의존성 정리..."
    apt-get -y autoremove --purge >>"$LOG_FILE" 2>&1 || log WARN "autoremove 일부 실패"
    apt-get -y autoclean >>"$LOG_FILE" 2>&1 || true

    # 사후 검증
    hr
    log INFO "=== 사후 검증 ==="
    # 남은 패키지 수
    local remaining=0
    for pkg in "${packages[@]}"; do
        dpkg -l 2>/dev/null | awk -v p="$pkg" '$1=="ii" && $2==p{found=1} END{exit !found}' \
            && remaining=$((remaining + 1)) || true
    done
    log INFO "아직 설치된 대상: $remaining 개"
    # 필수 서비스 상태
    local svc
    for svc in ssh sshd systemd-journald rsyslog chrony auditd apparmor; do
        if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}\.service"; then
            if systemctl is-active --quiet "$svc" 2>/dev/null; then
                log OK "service $svc : active"
            else
                log CRIT "service $svc : NOT active — 즉시 확인!"
            fi
        fi
    done
    # OpenSSH 연결성 확인 (포트만)
    if ss -tlnp 2>/dev/null | grep -q ':22 '; then
        log OK "sshd 포트 22 listen 유지"
    else
        log CRIT "sshd 포트 22 listen 하지 않음 — 즉시 재시작!"
    fi

    if (( ${#failed[@]} > 0 )); then
        log WARN "실패한 패키지: ${failed[*]}"
    fi
    log OK "=== 제거 작업 완료 ==="
    log INFO "Rollback : ${ROLLBACK_DIR}/rollback-v5-${TS}.sh"
    log INFO "Log       : $LOG_FILE (plain: $PLAIN_LOG_FILE)"
    log WARN "권장: reboot 후 업무 영향 확인"
}

# ============================================================================
# 14. MAIN
# ============================================================================
usage() {
    cat <<EOF
$SCRIPT_NAME v$SCRIPT_VERSION

Usage: sudo $0 [OPTIONS]

Options:
  --profile PROFILE        auto(기본) | ceph | cephadm | compute |
                           k8s-worker | k8s-control | network | generic
  --execute                실제 제거 실행 (기본은 dry-run)
  --risk-report            패키지별 위험도 리포트 출력
  --full-tree              각 패키지 의존성 트리 일부 노출
  --plan-out FILE          dry-run 결과를 YAML-like 파일로 저장
  --exclude PKG[,PKG...]   제거에서 제외할 패키지 (쉼표 구분)
  --yes                    확인 프롬프트 자동 승인 (자동화용)
  --skip-snapshot-check    LVM 스냅샷 권고 건너뜀
  --skip-ssh-check         SSH 안정성 사전 점검 건너뜀
  -h, --help               도움말

Exit codes:
  0  성공
  1  root 권한 / 일반 실패
  2  Profile 입력 오류 / critical 역의존 발견
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --profile) PROFILE="$2"; shift 2 ;;
            --execute) EXECUTE_MODE=true; shift ;;
            --risk-report) RISK_REPORT=true; shift ;;
            --full-tree) SHOW_FULL_TREE=true; shift ;;
            --plan-out) PLAN_OUT="$2"; shift 2 ;;
            --exclude) IFS=',' read -r -a EXCLUDE_CLI <<<"$2"; shift 2 ;;
            --yes) AUTO_YES=true; shift ;;
            --skip-snapshot-check) SKIP_SNAPSHOT_CHECK=true; shift ;;
            --skip-ssh-check) SKIP_SSH_CHECK=true; shift ;;
            -h|--help) usage; exit 0 ;;
            *) log ERROR "알 수 없는 옵션: $1"; usage; exit 2 ;;
        esac
    done
}

main() {
    parse_args "$@"
    init_logging
    validate_profile

    # 도움말이 아닌 경우 root
    check_root
    acquire_lock

    print_header
    log INFO "Version $SCRIPT_VERSION / $(date -Is)"
    detect_node_type
    log INFO "Detected/Selected node type: $NODE_TYPE"

    # 사전 점검
    check_disk_space        || exit 1
    check_ssh_stability     || exit 1
    check_ceph_health       || exit 1
    check_k8s_health        || exit 1

    # Baseline & Rollback
    backup_baseline
    create_rollback_script

    # 후보 수집
    local -a to_remove
    mapfile -t to_remove < <(build_candidates)

    if (( ${#to_remove[@]} == 0 )); then
        log OK "제거할 불필요 패키지가 없습니다."
        exit 0
    fi

    log INFO "제거 후보: ${#to_remove[@]} 개"

    if $RISK_REPORT; then
        risk_report "${to_remove[@]}"
        exit 0
    fi

    if $EXECUTE_MODE; then
        check_snapshot_recommendation
        # 제거 전 최종 dry-run 결과 요약
        dry_run_full_analysis "${to_remove[@]}" || exit 2
        real_removal "${to_remove[@]}"
    else
        dry_run_full_analysis "${to_remove[@]}"
    fi
}

main "$@"
