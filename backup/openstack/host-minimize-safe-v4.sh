#!/bin/bash
#
# host-minimize-safe-v4.sh
# Universal Host OS Minimization Script v4.0
# Supports: Ceph nodes, Compute nodes, Control nodes, Generic servers
#
# Features:
#   - Auto node type detection (Ceph / Compute / Control / Generic)
#   - Profile-based whitelist & safe-remove lists
#   - Conditional Ceph health check (only on Ceph nodes)
#   - Full dependency analysis + smart removal ordering
#   - Critical reverse-dependency protection
#   - Exclusion list support
#
# Version: 4.1 (Updated with more packages from additional servers)
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
# PROFILE-BASED WHITELISTS
# =============================================================================

# Common to ALL node types (Core System + Security)
COMMON_WHITELIST=(
    # System Core
    "systemd*" "dbus*" "udev" "initramfs-tools" "grub*" "linux-image*" "linux-headers*"
    "coreutils" "bash" "dash" "util-linux" "mount" "procps" "iproute2" "nftables"
    
    # Security (CSAP Mandatory)
    "apparmor*" "auditd" "aide*" "unattended-upgrades" "apt" "dpkg" "ca-certificates"
    
    # Management
    "openssh-server" "landscape-client" "canonical-livepatch"
    "rsyslog" "journald" "prometheus*" "node-exporter"
)

# Ceph-specific additions
CEPH_WHITELIST=(
    "ceph*" "rados*" "rbd*" "librados*" "librbd*" "libceph*"
    "ceph-common" "ceph-osd" "ceph-mon" "ceph-mgr" "ceph-mds" "ceph-volume"
    "ceph-fuse" "rbd-nbd" "lvm2" "xfsprogs" "btrfs-progs" "ethtool"
)

# Compute node additions (KVM + OpenStack)
COMPUTE_WHITELIST=(
    "qemu*" "libvirt*" "virtlogd" "virtlockd"
    "openvswitch*" "ovs*" "bridge-utils"
    "nova*" "neutron*" "cinder*"           # if baremetal services
    "kvm" "cpu-checker"
)

# Control node additions
CONTROL_WHITELIST=(
    "mysql*" "mariadb*" "postgresql*" "rabbitmq*" "memcached*"
    "keystone*" "glance*" "nova*" "neutron*" "cinder*" "horizon*"
    "haproxy" "keepalived" "pacemaker*" "corosync*"
)

# =============================================================================
# DEFAULT SAFE TO REMOVE (Updated v4.1 - more aggressive)
# =============================================================================
DEFAULT_SAFE_REMOVE=(
    # GUI / Desktop
    "gnome-shell" "gnome-session" "gdm3" "lightdm" "xserver-xorg*"
    "ubuntu-desktop" "xfce4*" "kde*" "lxde*" "mate*"
    
    # Games
    "aisleriot" "atari800" "gnome-games*" "mahjongg" "gnome-mahjongg"
    "gnome-mines" "gnome-sudoku"
    
    # Office / Productivity
    "libreoffice*" "abiword" "gnumeric" "evince" "gedit"
    
    # Media
    "audacity" "rhythmbox" "totem" "vlc" "cheese" "shotwell"
    "pitivi" "openshot*"
    
    # Insecure / Legacy
    "ftp" "telnet" "rsh-client" "rlogin" "tftp" "whois" "finger"
    
    # Error Reporting
    "apport" "apport-symptoms" "whoopsie" "apport-core-dump-handler" "ubuntu-report"
    
    # Bloat + Debug tools (v4.1 추가)
    "byobu" "poppler-utils" "yelp" "gnome-help"
    "strace" "gdb" "crash" "bpftrace" "bpfcc-tools" "trace-cmd"
    "git" "buildah" "podman"
    "bind9-dnsutils" "bind9-host" "bind9-libs"
    "htop" "sysstat"
    "snapd"
)

# =============================================================================
# NODE TYPE DETECTION
# =============================================================================

detect_node_type() {
    if [[ "$PROFILE" != "auto" ]]; then
        NODE_TYPE="$PROFILE"
        return
    fi
    
    # Check for Ceph
    if command -v ceph &> /dev/null && [[ -f /etc/ceph/ceph.conf ]]; then
        NODE_TYPE="ceph"
        return
    fi
    
    # Check for Compute (KVM + libvirt)
    if command -v qemu-system-x86_64 &> /dev/null || systemctl is-active --quiet libvirtd 2>/dev/null; then
        NODE_TYPE="compute"
        return
    fi
    
    # Check for Control (OpenStack services)
    if systemctl is-active --quiet keystone 2>/dev/null || \
       systemctl is-active --quiet glance-api 2>/dev/null || \
       systemctl is-active --quiet nova-api 2>/dev/null; then
        NODE_TYPE="control"
        return
    fi
    
    NODE_TYPE="generic"
}

get_whitelist() {
    local wl=("${COMMON_WHITELIST[@]}")
    
    case "$NODE_TYPE" in
        ceph)
            wl+=("${CEPH_WHITELIST[@]}")
            ;;
        compute)
            wl+=("${COMPUTE_WHITELIST[@]}")
            ;;
        control)
            wl+=("${CONTROL_WHITELIST[@]}")
            ;;
        generic)
            # Only common whitelist
            ;;
    esac
    
    printf '%s\n' "${wl[@]}"
}

# =============================================================================
# SAFETY CHECKS
# =============================================================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log ERROR "This script must be run as root"
        exit 1
    fi
}

check_ceph_health() {
    if [[ "$NODE_TYPE" != "ceph" ]]; then
        return 0
    fi
    
    log INFO "Checking Ceph cluster health (Ceph node detected)..."
    
    if ! command -v ceph &> /dev/null; then
        log WARN "ceph command not found on Ceph node - skipping health check"
        return 0
    fi
    
    local health
    health=$(ceph health 2>/dev/null | awk '{print $1}' || echo "UNKNOWN")
    
    if [[ "$health" != "HEALTH_OK" ]]; then
        log CRIT "Ceph cluster is NOT healthy: $health"
        log CRIT "Aborting to prevent data risk"
        exit 1
    fi
    
    log INFO "Ceph cluster health: HEALTH_OK ✓"
}

check_disk_space() {
    log INFO "Checking available disk space..."
    local available; available=$(df / | awk 'NR==2 {print $4}')
    
    if [[ $available -lt 2097152 ]]; then
        log ERROR "Insufficient disk space (< 2GB free)"
        exit 1
    fi
    log INFO "Disk space OK ($(($available / 1024)) MB free) ✓"
}

load_exclude_list() {
    if [[ -f "$CONFIG_FILE" ]]; then
        log INFO "Loading exclusion list from $CONFIG_FILE"
        mapfile -t EXCLUDE_LIST < <(grep -v '^#' "$CONFIG_FILE" | grep -v '^$')
    fi
}

backup_baseline() {
    log INFO "Creating package baseline backup..."
    mkdir -p "$BASELINE_DIR" "$ROLLBACK_DIR"
    
    local baseline_file="${BASELINE_DIR}/baseline-$(date +%Y%m%d-%H%M%S).txt"
    dpkg --get-selections > "$baseline_file"
    cp "$baseline_file" "${ROLLBACK_DIR}/pre-removal-selections.txt"
    log INFO "Baseline saved: $baseline_file"
}

create_rollback_script() {
    log INFO "Creating rollback script..."
    local rollback_script="${ROLLBACK_DIR}/rollback-v4-$(date +%Y%m%d-%H%M%S).sh"
    
    cat > "$rollback_script" << 'ROLLBACK_EOF'
#!/bin/bash
set -euo pipefail
echo "=== ROLLBACK v4: Restoring previous package state ==="
if [[ -f /var/lib/host-minimize/rollback/pre-removal-selections.txt ]]; then
    dpkg --set-selections < /var/lib/host-minimize/rollback/pre-removal-selections.txt
    apt-get dselect-upgrade -y
    echo "Rollback completed. Reboot recommended."
else
    echo "ERROR: Pre-removal baseline not found!"
    exit 1
fi
ROLLBACK_EOF
    
    chmod +x "$rollback_script"
    log INFO "Rollback script created: $rollback_script"
}

# =============================================================================
# DEPENDENCY ANALYSIS
# =============================================================================

get_direct_dependents() {
    local pkg="$1"
    apt-cache rdepends --installed "$pkg" 2>/dev/null | grep -v "^$pkg$" | grep -v "^Reverse Depends:" | awk '{print $1}' | sort -u
}

check_critical_reverse_deps() {
    local pkg="$1"
    local whitelist=($(get_whitelist))
    
    local dependents
    dependents=$(get_direct_dependents "$pkg")
    
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
            if [[ "$pkg" != "$other" ]]; then
                if apt-cache depends --installed "$other" 2>/dev/null | grep -q " $pkg "; then
                    ((count++))
                fi
            fi
        done
        dep_count["$pkg"]=$count
    done
    
    printf '%s\n' "${packages_ref[@]}" | while IFS= read -r pkg; do
        echo "${dep_count[$pkg]} $pkg"
    done | sort -n | cut -d' ' -f2-
}

# =============================================================================
# DRY-RUN
# =============================================================================

dry_run_full_analysis() {
    local packages=("$@")
    local total_direct=0
    local total_auto=0
    local critical_count=0
    local whitelist=($(get_whitelist))
    
    log INFO "=== DRY-RUN v4.1: Full Analysis (Profile: $NODE_TYPE) ==="
    echo ""
    
    # Critical check
    log INFO "Phase 1: Critical Reverse Dependency Check"
    local critical_packages=()
    
    for pkg in "${packages[@]}"; do
        if dpkg -l | grep -q "^ii  $pkg"; then
            if ! check_critical_reverse_deps "$pkg" 2>/dev/null; then
                critical_packages+=("$pkg")
                ((critical_count++))
            fi
        fi
    done
    
    if [[ $critical_count -gt 0 ]]; then
        log CRIT "$critical_count packages have critical reverse dependencies!"
        for pkg in "${critical_packages[@]}"; do
            log CRIT "  → $pkg"
        done
        echo ""
        log ERROR "Cannot safely proceed. Review the list above."
        return 1
    else
        log INFO "No critical reverse dependencies found ✓"
    fi
    
    echo ""
    log INFO "Phase 2: Per-Package Analysis + Smart Ordering"
    echo ""
    
    local ordered_packages
    ordered_packages=$(get_removal_order packages)
    
    for pkg in $ordered_packages; do
        if dpkg -l | grep -q "^ii  $pkg"; then
            local direct=0
            local auto=0
            
            direct=$(get_direct_dependents "$pkg" | wc -l)
            auto=$(apt -s purge "$pkg" 2>/dev/null | grep -E "^Remv |^Purg " | wc -l)
            auto=$((auto - 1))
            
            echo -e "  ${CYAN}▶${NC} $pkg"
            echo "     • 직접 의존자: $direct | 추가 제거 예상: $auto"
            
            if [[ "$SHOW_FULL_TREE" == "true" ]]; then
                echo "     • Dependency Tree:"
                apt-cache depends --installed "$pkg" 2>/dev/null | grep -E "^  [ |]" | head -6 | sed 's/^/       /'
            fi
            echo ""
            
            ((total_direct++))
            total_auto=$((total_auto + auto))
        fi
    done
    
    local grand_total=$((total_direct + total_auto))
    
    echo ""
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║${NC}  DRY-RUN v4.1 SUMMARY (Node Type: $NODE_TYPE)                                 ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╠══════════════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${MAGENTA}║${NC}  직접 제거 대상     : ${GREEN}$total_direct${NC} 개                                          ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}║${NC}  의존성 추가 제거   : ${YELLOW}$total_auto${NC} 개                                          ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}║${NC}  총 영향 패키지     : ${RED}$grand_total${NC} 개                                          ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}║${NC}  스마트 순서        : Leaf-first (의존성 적은 것부터)                              ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
}

# =============================================================================
# REAL REMOVAL
# =============================================================================

real_removal_smart() {
    local packages=("$@")
    
    log WARN "REAL REMOVAL MODE (Smart Order)"
    read -p "Type 'YES' to proceed: " confirm
    [[ "$confirm" != "YES" ]] && { log INFO "Cancelled"; exit 0; }
    
    local ordered
    ordered=$(get_removal_order packages)
    
    local removed=0
    local failed=0
    
    for pkg in $ordered; do
        if dpkg -l | grep -q "^ii  $pkg"; then
            log INFO "Removing: $pkg"
            if apt purge -y "$pkg" >> "$LOG_FILE" 2>&1; then
                ((removed++))
            else
                ((failed++))
            fi
        fi
    done
    
    log INFO "Completed: $removed removed, $failed failed"
}

# =============================================================================
# MAIN
# =============================================================================

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --profile [ceph|compute|control|generic|auto]   Node profile (default: auto)"
    echo "  --execute                                      Perform actual removal"
    echo "  --full-tree                                    Show full dependency tree"
    echo "  --exclude PKG1,PKG2                            Exclude packages"
    echo "  -h, --help                                     Show help"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Auto-detect + Dry-run"
    echo "  $0 --profile compute --execute        # Force compute profile + execute"
    echo "  $0 --exclude ftp,byobu --full-tree    # Exclude + show tree"
}

main() {
    print_header
    check_root
    mkdir -p "$LOG_DIR"
    touch "$LOG_FILE"
    
    # Parse args
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
    log INFO "Detected node type: $NODE_TYPE (Profile: $PROFILE)"
    
    load_exclude_list
    check_ceph_health
    check_disk_space
    backup_baseline
    create_rollback_script
    
    # Build removal list
    local to_remove=()
    local whitelist=($(get_whitelist))
    
    for pkg in "${DEFAULT_SAFE_REMOVE[@]}"; do
        if dpkg -l | grep -q "^ii  $pkg"; then
            local is_safe=true
            
            for white in "${whitelist[@]}"; do
                if [[ "$pkg" == $white ]]; then is_safe=false; break; fi
            done
            for ex in "${EXCLUDE_LIST[@]}"; do
                if [[ "$pkg" == "$ex" ]]; then is_safe=false; break; fi
            done
            
            $is_safe && to_remove+=("$pkg")
        fi
    done
    
    if [[ ${#to_remove[@]} -eq 0 ]]; then
        log INFO "No packages to remove after filtering"
        exit 0
    fi
    
    if [[ "$EXECUTE_MODE" == "true" ]]; then
        real_removal_smart "${to_remove[@]}"
        apt autoremove -y >> "$LOG_FILE" 2>&1 || true
        apt autoclean >> "$LOG_FILE" 2>&1 || true
        log INFO "=== EXECUTION COMPLETED ==="
    else
        dry_run_full_analysis "${to_remove[@]}"
        echo ""
        log INFO "DRY-RUN completed. Use --execute for real removal."
    fi
}

main "$@"
