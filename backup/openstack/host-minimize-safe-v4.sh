#!/bin/bash
#
# ceph-host-minimize-safe-v4.2.sh
# Universal Host OS Minimization Script v4.2 (완전 안정 버전)
# 모든 노드 타입 지원 + Dry-run 출력 문제 완전 해결
#

set -euo pipefail

# =============================================================================
# 설정
# =============================================================================

LOG_DIR="/var/log/host-minimize"
LOG_FILE="${LOG_DIR}/minimize-v4-$(date +%Y%m%d-%H%M%S).log"
BASELINE_DIR="/var/lib/host-minimize/baseline"
ROLLBACK_DIR="/var/lib/host-minimize/rollback"
CONFIG_FILE="/etc/host-minimize/exclude.conf"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

EXECUTE_MODE=false
SHOW_FULL_TREE=false
PROFILE="auto"
EXCLUDE_LIST=()
NODE_TYPE="unknown"

# =============================================================================
# 로그 & 헤더
# =============================================================================

print_header() {
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}                  Host OS Minimization Safe Script v4.2                  ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}             Universal for Ceph / Compute / Control / Generic             ${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

log() {
    local level="$1"
    shift
    local ts=$(date '+%Y-%m-%d %H:%M:%S')
    case "$level" in
        INFO)  echo -e "${GREEN}[$ts] [INFO ] $*${NC}" | tee -a "$LOG_FILE" ;;
        WARN)  echo -e "${YELLOW}[$ts] [WARN ] $*${NC}" | tee -a "$LOG_FILE" ;;
        ERROR) echo -e "${RED}[$ts] [ERROR] $*${NC}" | tee -a "$LOG_FILE" ;;
        CRIT)  echo -e "${RED}[$ts] [CRIT ] $*${NC}" | tee -a "$LOG_FILE" ;;
    esac
}

# =============================================================================
# 화이트리스트 & 제거 대상
# =============================================================================

COMMON_WHITELIST=(
    "systemd*" "dbus*" "udev" "initramfs-tools" "grub*" "linux-image*" 
    "coreutils" "bash" "util-linux" "iproute2" "apparmor*" "auditd" "aide*"
    "unattended-upgrades" "apt" "dpkg" "ca-certificates" "openssh-server" "rsyslog"
)

CEPH_WHITELIST=("ceph*" "rados*" "rbd*" "librados*" "librbd*" "ceph-common" "ceph-mds" "lvm2" "xfsprogs")
COMPUTE_WHITELIST=("qemu*" "libvirt*" "virtlogd" "openvswitch*" "kvm")
CONTROL_WHITELIST=("mysql*" "rabbitmq*" "keystone*" "glance*" "nova*" "neutron*" "haproxy")

DEFAULT_SAFE_REMOVE=(
    "gnome-shell" "gnome-session" "gdm3" "lightdm" "xserver-xorg*" "ubuntu-desktop"
    "aisleriot" "libreoffice*" "audacity" "rhythmbox" "totem" "vlc"
    "ftp" "telnet" "inetutils-telnet" "whois" "finger"
    "apport" "apport-symptoms" "whoopsie" "apport-core-dump-handler"
    "byobu" "screen" "tmux" "strace" "gdb" "crash" "bpftrace" "htop" "sysstat" "snapd"
    "git" "buildah" "podman" "bind9-dnsutils" "bind9-host"
)

# =============================================================================
# 함수들
# =============================================================================

detect_node_type() {
    if [[ "$PROFILE" != "auto" ]]; then
        NODE_TYPE="$PROFILE"
        return
    fi
    if command -v ceph &> /dev/null && [[ -f /etc/ceph/ceph.conf ]]; then NODE_TYPE="ceph"
    elif command -v qemu-system-x86_64 &> /dev/null || systemctl is-active --quiet libvirtd 2>/dev/null; then NODE_TYPE="compute"
    elif systemctl is-active --quiet keystone 2>/dev/null || systemctl is-active --quiet glance-api 2>/dev/null; then NODE_TYPE="control"
    else NODE_TYPE="generic"
    fi
}

get_whitelist() {
    local wl=("${COMMON_WHITELIST[@]}")
    case "$NODE_TYPE" in
        ceph) wl+=("${CEPH_WHITELIST[@]}") ;;
        compute) wl+=("${COMPUTE_WHITELIST[@]}") ;;
        control) wl+=("${CONTROL_WHITELIST[@]}") ;;
    esac
    printf '%s\n' "${wl[@]}"
}

check_root() { [[ $EUID -eq 0 ]] || { log ERROR "root 권한으로 실행해야 합니다."; exit 1; }; }

check_ceph_health() {
    [[ "$NODE_TYPE" != "ceph" ]] && return 0
    log INFO "Ceph Health Check..."
    local health; health=$(ceph health 2>/dev/null | awk '{print $1}' || echo "UNKNOWN")
    [[ "$health" != "HEALTH_OK" ]] && { log CRIT "Ceph cluster is NOT healthy ($health). 중단합니다."; exit 1; }
    log INFO "Ceph cluster health: HEALTH_OK ✓"
}

check_disk_space() {
    local available; available=$(df / | awk 'NR==2 {print $4}')
    [[ $available -lt 2097152 ]] && { log ERROR "디스크 공간 부족 (< 2GB)"; exit 1; }
    log INFO "Disk space OK ($(($available / 1024)) MB free) ✓"
}

load_exclude_list() {
    [[ -f "$CONFIG_FILE" ]] && mapfile -t EXCLUDE_LIST < <(grep -v '^#' "$CONFIG_FILE" | grep -v '^$')
}

backup_baseline() {
    mkdir -p "$BASELINE_DIR" "$ROLLBACK_DIR"
    local baseline="${BASELINE_DIR}/baseline-$(date +%Y%m%d-%H%M%S).txt"
    dpkg --get-selections > "$baseline"
    cp "$baseline" "${ROLLBACK_DIR}/pre-removal-selections.txt"
    log INFO "Baseline saved"
}

create_rollback_script() {
    local rollback="${ROLLBACK_DIR}/rollback-v4-$(date +%Y%m%d-%H%M%S).sh"
    cat > "$rollback" << 'EOF'
#!/bin/bash
set -euo pipefail
echo "=== ROLLBACK v4.2 ==="
dpkg --set-selections < /var/lib/host-minimize/rollback/pre-removal-selections.txt
apt-get dselect-upgrade -y
echo "Rollback 완료. Reboot 권장."
EOF
    chmod +x "$rollback"
    log INFO "Rollback script created"
}

get_removal_order() {
    local -n packages_ref=$1
    local -A dep_count=()
    for pkg in "${packages_ref[@]}"; do
        local count=0
        for other in "${packages_ref[@]}"; do
            [[ "$pkg" != "$other" ]] && apt-cache depends --installed "$other" 2>/dev/null | grep -q " $pkg " && ((count++))
        done
        dep_count["$pkg"]=$count
    done
    printf '%s\n' "${packages_ref[@]}" | while IFS= read -r pkg; do
        echo "${dep_count[$pkg]} $pkg"
    done | sort -n | cut -d' ' -f2-
}

dry_run_full_analysis() {
    local packages=("$@")
    local total_direct=0 total_auto=0

    print_header
    log INFO "=== DRY-RUN v4.2 시작 (Node Type: $NODE_TYPE) ==="

    # 제거 대상 분석
    log INFO "Phase 2: 제거 대상 분석"
    echo ""
    local ordered; ordered=$(get_removal_order packages)

    for pkg in $ordered; do
        dpkg -l | grep -q "^ii  $pkg" || continue
        local auto
        auto=$(apt -s purge "$pkg" 2>/dev/null | grep -E "^Remv |^Purg " | wc -l)
        auto=$((auto - 1))

        echo -e "  ${CYAN}▶${NC} $pkg   (추가 제거 예상: $auto 개)"
        ((total_direct++))
        total_auto=$((total_auto + auto))
    done

    local grand_total=$((total_direct + total_auto))

    echo ""
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║${NC}  DRY-RUN SUMMARY (Node: $NODE_TYPE)                                        ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╠══════════════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${MAGENTA}║${NC}  직접 제거 대상     : ${GREEN}$total_direct${NC} 개                                          ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}║${NC}  총 영향 패키지     : ${RED}$grand_total${NC} 개                                          ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"

    echo ""
    log INFO "Dry-run이 완료되었습니다."
    log INFO "실제 삭제를 원하시면 아래 명령어를 실행하세요:"
    echo -e "   ${YELLOW}sudo $0 --execute${NC}"
    echo ""
    log INFO "스크립트가 정상적으로 종료되었습니다."
}

real_removal_smart() {
    local packages=("$@")
    print_header
    log WARN "=== REAL REMOVAL MODE ==="
    read -p "정말 삭제를 진행하시겠습니까? (YES 입력): " confirm
    [[ "$confirm" != "YES" ]] && { log INFO "작업이 취소되었습니다."; exit 0; }

    local ordered; ordered=$(get_removal_order packages)
    for pkg in $ordered; do
        dpkg -l | grep -q "^ii  $pkg" || continue
        log INFO "Removing: $pkg"
        apt purge -y "$pkg" >> "$LOG_FILE" 2>&1 || true
    done

    log INFO "자동 정리 중..."
    apt autoremove -y >> "$LOG_FILE" 2>&1 || true
    apt autoclean >> "$LOG_FILE" 2>&1 || true

    log INFO "=== 실제 삭제 작업이 완료되었습니다 ==="
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    mkdir -p "$LOG_DIR"
    touch "$LOG_FILE"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --profile) PROFILE="$2"; shift 2 ;;
            --execute) EXECUTE_MODE=true; shift ;;
            --full-tree) SHOW_FULL_TREE=true; shift ;;
            --exclude) IFS=',' read -ra EXCLUDE_LIST <<< "$2"; shift 2 ;;
            -h|--help) echo "Usage: $0 [--profile TYPE] [--execute] [--full-tree] [--exclude PKG1,PKG2]"; exit 0 ;;
            *) log ERROR "알 수 없는 옵션: $1"; exit 1 ;;
        esac
    done

    detect_node_type
    log INFO "Detected node type: $NODE_TYPE"

    load_exclude_list
    check_root
    check_ceph_health
    check_disk_space
    backup_baseline
    create_rollback_script

    local to_remove=()
    local whitelist=($(get_whitelist))
    for pkg in "${DEFAULT_SAFE_REMOVE[@]}"; do
        dpkg -l | grep -q "^ii  $pkg" || continue
        local is_safe=true
        for white in "${whitelist[@]}"; do [[ "$pkg" == $white ]] && is_safe=false && break; done
        for ex in "${EXCLUDE_LIST[@]}"; do [[ "$pkg" == "$ex" ]] && is_safe=false && break; done
        $is_safe && to_remove+=("$pkg")
    done

    if [[ ${#to_remove[@]} -eq 0 ]]; then
        log INFO "제거할 불필요 패키지가 없습니다."
        exit 0
    fi

    if [[ "$EXECUTE_MODE" == "true" ]]; then
        real_removal_smart "${to_remove[@]}"
    else
        dry_run_full_analysis "${to_remove[@]}"
    fi
}

main "$@"
