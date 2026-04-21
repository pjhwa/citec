#!/bin/bash
#
# ceph-host-minimize-safe-v4.sh
# Universal Host OS Minimization Script v4.1
# Supports: Ceph, Compute, Control, Generic servers
#
# Version: 4.1 (print_header, log 함수 완전 정의 + syntax 검증 완료)
# Date: 2026-04-21
#

set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================

SCRIPT_NAME="$(basename "$0")"
LOG_DIR="/var/log/host-minimize"
LOG_FILE="${LOG_DIR}/minimize-v4-$(date +%Y%m%d-%H%M%S).log"
BASELINE_DIR="/var/lib/host-minimize/baseline"
ROLLBACK_DIR="/var/lib/host-minimize/rollback"
CONFIG_FILE="/etc/host-minimize/exclude.conf"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Execution flags
EXECUTE_MODE=false
SHOW_FULL_TREE=false
PROFILE="auto"
EXCLUDE_LIST=()
NODE_TYPE="unknown"

# =============================================================================
# LOG & HEADER FUNCTIONS
# =============================================================================

print_header() {
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}                  Host OS Minimization Safe Script v4.1                  ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}             Universal for Ceph / Compute / Control / Generic             ${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

log() {
    local level="$1"
    shift
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    case "$level" in
        INFO)  echo -e "${GREEN}[$timestamp] [INFO ] $*${NC}" | tee -a "$LOG_FILE" ;;
        WARN)  echo -e "${YELLOW}[$timestamp] [WARN ] $*${NC}" | tee -a "$LOG_FILE" ;;
        ERROR) echo -e "${RED}[$timestamp] [ERROR] $*${NC}" | tee -a "$LOG_FILE" ;;
        CRIT)  echo -e "${RED}[$timestamp] [CRIT ] $*${NC}" | tee -a "$LOG_FILE" ;;
    esac
}

# =============================================================================
# PROFILE-BASED WHITELISTS (v4.1 업데이트)
# =============================================================================

COMMON_WHITELIST=(
    "systemd*" "dbus*" "udev" "initramfs-tools" "grub*" "linux-image*" "linux-headers*"
    "coreutils" "bash" "dash" "util-linux" "mount" "procps" "iproute2" "nftables"
    "apparmor*" "auditd" "aide*" "unattended-upgrades" "apt" "dpkg" "ca-certificates"
    "openssh-server" "landscape-client" "rsyslog"
)

CEPH_WHITELIST=("ceph*" "rados*" "rbd*" "librados*" "librbd*" "libceph*" "ceph-common" "ceph-mds" "lvm2" "xfsprogs")
COMPUTE_WHITELIST=("qemu*" "libvirt*" "virtlogd" "openvswitch*" "kvm")
CONTROL_WHITELIST=("mysql*" "mariadb*" "rabbitmq*" "keystone*" "glance*" "nova*" "neutron*" "haproxy")

DEFAULT_SAFE_REMOVE=(
    # GUI / Desktop
    "gnome-shell" "gnome-session" "gdm3" "lightdm" "xserver-xorg*" "ubuntu-desktop" "xfce4*"
    # Games / Media / Office
    "aisleriot" "atari800" "gnome-games*" "mahjongg" "libreoffice*" "audacity" "rhythmbox" "totem" "vlc"
    # Insecure / Legacy
    "ftp" "telnet" "inetutils-telnet" "rsh-client" "whois" "finger"
    # Error Reporting
    "apport" "apport-symptoms" "whoopsie" "apport-core-dump-handler" "ubuntu-report"
    # Debug / Bloat (v4.1)
    "byobu" "screen" "tmux" "strace" "gdb" "crash" "bpftrace" "bpfcc-tools" "trace-cmd"
    "git" "buildah" "podman" "bind9-dnsutils" "bind9-host" "htop" "sysstat" "snapd"
)

# =============================================================================
# FUNCTIONS
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
    log INFO "Baseline saved: $baseline"
}

create_rollback_script() {
    local rollback="${ROLLBACK_DIR}/rollback-v4-$(date +%Y%m%d-%H%M%S).sh"
    cat > "$rollback" << 'EOF'
#!/bin/bash
set -euo pipefail
echo "=== ROLLBACK v4.1 ==="
dpkg --set-selections < /var/lib/host-minimize/rollback/pre-removal-selections.txt
apt-get dselect-upgrade -y
echo "Rollback 완료. Reboot 권장."
EOF
    chmod +x "$rollback"
    log INFO "Rollback script created: $rollback"
}

get_direct_dependents() { apt-cache rdepends --installed "$1" 2>/dev/null | grep -v "^$1$" | awk '{print $1}' | sort -u; }

check_critical_reverse_deps() {
    local pkg="$1"
    local whitelist=($(get_whitelist))
    local dependents; dependents=$(get_direct_dependents "$pkg")
    for dep in $dependents; do
        for white in "${whitelist[@]}"; do
            if [[ "$dep" == $white ]]; then
                echo -e "${RED}  ⚠ CRITICAL${NC}: $pkg is required by $dep"
                return 1
            fi
        done
    done
    return 0
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
    local total_direct=0 total_auto=0 critical_count=0
    local whitelist=($(get_whitelist))
    
    print_header
    log INFO "=== DRY-RUN v4.1: Full Analysis (Node: $NODE_TYPE) ==="
    
    # Critical check
    log INFO "Phase 1: Critical Reverse Dependency Check"
    for pkg in "${packages[@]}"; do
        dpkg -l | grep -q "^ii  $pkg" || continue
        if ! check_critical_reverse_deps "$pkg" 2>/dev/null; then
            ((critical_count++))
        fi
    done
    [[ $critical_count -gt 0 ]] && { log CRIT "Critical reverse dependencies detected!"; return 1; }
    log INFO "No critical reverse dependencies ✓"
    
    # Analysis
    log INFO "Phase 2: Per-Package Analysis"
    local ordered; ordered=$(get_removal_order packages)
    for pkg in $ordered; do
        dpkg -l | grep -q "^ii  $pkg" || continue
        local direct auto
        direct=$(get_direct_dependents "$pkg" | wc -l)
        auto=$(apt -s purge "$pkg" 2>/dev/null | grep -E "^Remv |^Purg " | wc -l)
        auto=$((auto - 1))
        echo -e "  ${CYAN}▶${NC} $pkg   (직접: $direct | 추가: $auto)"
        ((total_direct++))
        total_auto=$((total_auto + auto))
    done
    
    local grand_total=$((total_direct + total_auto))
    echo -e "\n${MAGENTA}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║${NC}  DRY-RUN SUMMARY (Node: $NODE_TYPE)                                         ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╠══════════════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${MAGENTA}║${NC}  직접 제거 대상     : ${GREEN}$total_direct${NC} 개                                          ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}║${NC}  의존성 추가 제거   : ${YELLOW}$total_auto${NC} 개                                          ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}║${NC}  총 영향 패키지     : ${RED}$grand_total${NC} 개                                          ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
}

real_removal_smart() {
    local packages=("$@")
    log WARN "REAL REMOVAL MODE 시작"
    read -p "Type 'YES' to proceed: " confirm
    [[ "$confirm" != "YES" ]] && { log INFO "Cancelled."; exit 0; }
    
    local ordered; ordered=$(get_removal_order packages)
    for pkg in $ordered; do
        dpkg -l | grep -q "^ii  $pkg" || continue
        log INFO "Removing: $pkg"
        apt purge -y "$pkg" >> "$LOG_FILE" 2>&1 || true
    done
    apt autoremove -y >> "$LOG_FILE" 2>&1 || true
    apt autoclean >> "$LOG_FILE" 2>&1 || true
    log INFO "=== EXECUTION COMPLETED ==="
}

# =============================================================================
# MAIN
# =============================================================================

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "  --profile [ceph|compute|control|generic|auto]   (default: auto)"
    echo "  --execute                                        실제 삭제 실행"
    echo "  --full-tree                                      의존성 트리 전체 출력"
    echo "  --exclude PKG1,PKG2                              제외 패키지"
}

main() {
    mkdir -p "$LOG_DIR"
    touch "$LOG_FILE"
    print_header
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --profile) PROFILE="$2"; shift 2 ;;
            --execute) EXECUTE_MODE=true; shift ;;
            --full-tree) SHOW_FULL_TREE=true; shift ;;
            --exclude) IFS=',' read -ra EXCLUDE_LIST <<< "$2"; shift 2 ;;
            -h|--help) usage; exit 0 ;;
            *) log ERROR "Unknown option: $1"; usage; exit 1 ;;
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
    
    # Build removal list
    local to_remove=()
    local whitelist=($(get_whitelist))
    for pkg in "${DEFAULT_SAFE_REMOVE[@]}"; do
        dpkg -l | grep -q "^ii  $pkg" || continue
        local is_safe=true
        for white in "${whitelist[@]}"; do [[ "$pkg" == $white ]] && is_safe=false && break; done
        for ex in "${EXCLUDE_LIST[@]}"; do [[ "$pkg" == "$ex" ]] && is_safe=false && break; done
        $is_safe && to_remove+=("$pkg")
    done
    
    [[ ${#to_remove[@]} -eq 0 ]] && { log INFO "No packages to remove."; exit 0; }
    
    if [[ "$EXECUTE_MODE" == "true" ]]; then
        real_removal_smart "${to_remove[@]}"
    else
        dry_run_full_analysis "${to_remove[@]}"
        log INFO "DRY-RUN 완료. --execute 옵션으로 실제 실행 가능."
    fi
}

main "$@"
