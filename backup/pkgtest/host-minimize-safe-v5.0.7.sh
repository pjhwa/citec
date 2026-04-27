#!/usr/bin/env bash
#
# host-minimize-safe-v5.sh
# Universal Host OS Minimization Script v5.0
# Target: Samsung SDS SCPv2 Sovereign (Ubuntu 22.04/24.04)
# Supports: Ceph / Compute / K8s Worker / K8s Control / Network / Generic
#
# 변경 이력 (최신부터):
#
# Version: 5.0.3  (2026-04-23)
#   [BUG-A P0] autoremove 가 whitelist 를 우회하는 설계 결함 수정
#              - protect_whitelist_packages(): autoremove 전 whitelist 패키지 apt-mark manual
#              - do_autoremove(): dry-run 결과 표시 → whitelist 침범 시 중단 → 사용자 확인 후 실행
#              - systemd* 계열 패키지 autoremove 대상 포함 시 CRIT 경고
#   [BUG-B P1] kubelet/서비스 restart storm 탐지 미비 수정
#              - check_k8s_health(): NRestarts > STORM_THRESHOLD(50) 탐지 → --execute 시 확인 요청
#              - check_systemd_storm(): 모든 서비스 대상 restart storm 사전 점검
#   [BUG-C P1] get_removal_order O(N²) 중복 실행 수정
#              - ORDERED_PACKAGES 전역 캐시 → dry_run/real_removal 양쪽에서 재사용
#              - N > ORDER_SKIP_THRESHOLD(20) 시 위상 정렬 스킵 (O(N²) 방지)
#   [BUG-D P1] apt-get/apt-cache 호출 timeout 부재 수정
#              - APT_TIMEOUT=120s, APT_CACHE_TIMEOUT=30s, PKG_REMOVE_TIMEOUT=300s
#              - timeout 초과 시 CRIT 로그 + 진단 명령 출력
#   [BUG-E P1] snapd 제거 전 snap 목록 사전 확인 누락 수정
#              - check_snapd_safety(): snap list 확인 → 설치된 snap 있으면 경고 + 확인
#   [BUG-F P2] autoremove 실제 제거 목록 사용자 미표시 수정 (do_autoremove 에서 해결)
#   [BUG-G P2] 패키지당 제거 timeout 부재 수정
#              - timeout PKG_REMOVE_TIMEOUT apt-get purge
#   [추가] check_apt_lock(): dpkg/apt lock 사전 점검
#
# Version: 5.0.7  (2026-04-27)
#   [신규] --verbose 옵션 — apt 명령 출력을 터미널에 실시간 표시
#   [신규] apt_exec() 헬퍼 — apt 호출을 일관된 방식으로 실행/로깅
#          - if ! cmd; then local ec=$? 패턴의 ec=0 버그 수정 (! 반전 영향)
#          - 실패 시 PLAIN_LOG_FILE 발췌를 터미널에 자동 표시
#          - set -e + pipefail 환경에서 함수 abort 방지 처리
#   [신규 P3] BUG-J / KI-05 — purge 후 systemd failed 유닛 자동 reset-failed
#          - real_removal() 사후 검증 단계에 추가
#          - sysstat-collect.timer 등 잔류 정리
#   [개선] protect_whitelist_packages() — 중복 매칭 카운트 정확화 + 일괄 apt-mark
#   [개선] check_pending_upgrades() timeout 30s → APT_TIMEOUT(120s) 일관화
#   [개선] dpkg --audit 빈출력 매칭 정확도 (grep -qE '.+')
#   [개선] rollback 스크립트 버전 표시 동적화
#
# Version: 5.0.6  (2026-04-23)
#   [BUG-I P2] apt-get purge 개별 실행 시 virtual package Conflicts/Provides 체인으로
#              인해 의도치 않은 패키지가 자동 설치되는 문제 수정 (test-nn3 발견)
#              - 원인: apport-core-dump-handler/systemd-coredump 모두 core-dump-handler
#                virtual pkg를 Provides/Conflicts. 개별 purge 시 apt가 빈 자리를 채움.
#              - 수정1: real_removal() 에서 개별 purge 루프 → 단일 batch purge 호출
#                       `apt-get purge pkg1 pkg2 ... pkgN` — apt가 전체 의존성 해석 시
#                       불필요한 대체 패키지 설치 없음. (시뮬레이션 검증: 0 newly installed)
#              - 수정2: check_pending_upgrades() 추가 — execute 진입 전 pending 업그레이드
#                       존재 시 경고. 프로덕션 환경에서 자동 upgrade는 수행하지 않음.
#              - 수정3: verify_no_new_packages() 추가 — execute 후 사전 baseline 대비
#                       신규 패키지 탐지 및 WARN 로깅
#
# Version: 5.0.5  (2026-04-23)
#   [BUG-H P2] plan 파일 cascade_count 가 actual_cascade 대신 total_cascade(개별 합산)
#              을 기록하던 오류 수정 — BUG-03 수정 시 summary는 actual_cascade로 변경됐으나
#              plan 파일 기록 코드는 누락됨. (test-nn3 발견)
#
# Version: 5.0.4  (2026-04-23)
#   [신규 P1] kubelet restart storm 자동 중단 — 승인 후 mask/stop 수행
#              - check_k8s_health() 에서 storm 탐지 시 자동 중단 제안
#              - 사용자 승인(yes) 후 systemctl stop + mask 실행
#              - 마커 파일 기록 (${STATE_DIR}/kubelet-masked-by-script.txt)
#              - on_exit() 에서 unmask 안내 출력
#              - KUBELET_MASKED_BY_SCRIPT 전역 플래그로 상태 추적
#
# 이전 버전:
#   v5.0.1: rollback 복원 실패(P1), k8s-worker 프로파일 체크 과도(P2),
#           cascade count 중복 합산(P2), NIC Link Down 오탐(P3), rc 패키지 오인식(P2)
#   v5.0.2: (이 파일의 기반)
#
set -Euo pipefail

# ============================================================================
# 0. GLOBAL CONSTANTS
# ============================================================================
SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="5.0.7"
SCRIPT_DATE="2026-04-27"

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

# [BUG-D] apt/dpkg timeout 상수
APT_TIMEOUT=120          # apt-get 단일 호출 최대 대기 (초)
APT_CACHE_TIMEOUT=30     # apt-cache 단일 호출 최대 대기 (초)
PKG_REMOVE_TIMEOUT=300   # 패키지당 purge 최대 대기 (초) — prerm/postrm hang 방지
AUTOREMOVE_TIMEOUT=600   # autoremove 전체 최대 대기 (초)

# [BUG-B] restart storm 탐지 임계치
STORM_THRESHOLD=50       # NRestarts 이 값 초과 시 storm으로 판정

# [BUG-C] get_removal_order O(N²) 스킵 임계치
ORDER_SKIP_THRESHOLD=20  # 후보 수가 이 값 초과 시 위상 정렬 스킵

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
VERBOSE=false
PLAN_OUT=""
PROFILE="auto"
EXCLUDE_CLI=()
NODE_TYPE="unknown"

# [BUG-C] 위상 정렬 결과 캐시 (dry_run + real_removal 에서 공유)
ORDERED_PACKAGES=()

# [5.0.4] kubelet mask 상태 추적 — on_exit()에서 unmask 안내에 사용
KUBELET_MASKED_BY_SCRIPT=false

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

_strip_ansi() { sed -E 's/\x1b\[[0-9;]*[a-zA-Z]//g'; }

log() {
    local level="$1"; shift
    # DEBUG 레벨은 --verbose 시에만 출력
    [[ "$level" == "DEBUG" ]] && ! $VERBOSE && return 0
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
        DEBUG) colored="${CYAN}${msg}${NC}" ;;
    esac
    echo -e "$colored" | tee -a "$LOG_FILE" >/dev/null
    echo "$msg" >> "$PLAIN_LOG_FILE"
    echo -e "$colored"
}

# apt-get 출력을 로그에 기록하고, --verbose 시 터미널에도 표시
# $? 캡처용 헬퍼: apt_exec <ec_varname> <timeout> <...cmd...>
# - set -e + pipefail 환경에서 파이프 실패 시 ERR trap 우회를 위해 || true 사용
# - 실패 시 PLAIN_LOG_FILE에서 발췌(터미널에 표시), LOG_FILE에는 누적 기록 안 함
apt_exec() {
    local _ec_var="$1"; shift
    local _timeout="$1"; shift
    # 실행 전 plain 로그 파일 라인 수 마킹 (실패 시 해당 구간만 추출)
    local _mark; _mark=$(wc -l < "$PLAIN_LOG_FILE" 2>/dev/null || echo 0)
    local _ec=0
    if $VERBOSE; then
        # tee로 양쪽 로그에 기록 + 화면 표시 (ANSI/CR 정리하여 가독성 개선)
        # set -o pipefail 환경 보호: || true로 함수 abort 방지
        { timeout "$_timeout" "$@" 2>&1; printf '\n__APT_EXEC_EC__=%d\n' "$?"; } \
            | tee -a "$LOG_FILE" "$PLAIN_LOG_FILE" \
            | sed 's/\r/\n/g; s/\x1b\[[0-9;]*[mK]//g' \
            | while IFS= read -r _line; do
                [[ "$_line" =~ ^__APT_EXEC_EC__= ]] && continue
                [[ -n "$_line" ]] && printf '    %s\n' "$_line"
              done || true
        # 마커 라인에서 실제 종료 코드 추출 (PIPESTATUS는 tee/sed/while 영향)
        _ec=$(grep -oP '^__APT_EXEC_EC__=\K[0-9]+' "$PLAIN_LOG_FILE" | tail -1)
        _ec=${_ec:-1}
        # 마커 라인 정리 (양쪽 로그)
        sed -i '/^__APT_EXEC_EC__=/d' "$LOG_FILE" "$PLAIN_LOG_FILE" 2>/dev/null || true
    else
        timeout "$_timeout" "$@" >> "$PLAIN_LOG_FILE" 2>&1 || _ec=$?
        # 색상 없는 plain 출력을 LOG_FILE에도 사본 누적 (단방향 — 자기 누적 없음)
        if (( _mark >= 0 )); then
            tail -n +"$((_mark + 1))" "$PLAIN_LOG_FILE" >> "$LOG_FILE" 2>/dev/null || true
        fi
    fi
    printf -v "$_ec_var" '%d' "$_ec"
    # 실패 시 + non-verbose: 발췌를 터미널에만 출력 (LOG_FILE에 다시 누적 안 함)
    if (( _ec != 0 )) && ! $VERBOSE; then
        local _new_lines; _new_lines=$(wc -l < "$PLAIN_LOG_FILE" 2>/dev/null || echo 0)
        if (( _new_lines > _mark )); then
            log ERROR "  apt 출력 발췌 (전체: $PLAIN_LOG_FILE):"
            sed -n "$((_mark + 1)),${_new_lines}p" "$PLAIN_LOG_FILE" \
                | grep -v '^[[:space:]]*$' \
                | tail -20 \
                | while IFS= read -r _line; do
                    printf '    %s\n' "$_line"
                  done
        fi
    fi
    return "$_ec"
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
    # [5.0.4] 오류 종료 시에도 unmask 안내 출력
    if $KUBELET_MASKED_BY_SCRIPT; then
        echo -e "\n⚠  이 스크립트가 kubelet을 mask했습니다. 복원 명령:"
        echo    "     sudo systemctl unmask kubelet"
        echo    "     sudo systemctl start kubelet   # 필요시"
    fi
    exit "$ec"
}
on_exit() {
    release_lock
    # [5.0.4] 정상 종료 시 unmask 안내 출력
    if $KUBELET_MASKED_BY_SCRIPT; then
        echo ""
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${YELLOW}⚠  kubelet이 이 스크립트에 의해 mask되어 있습니다.${NC}"
        echo    "   테스트 완료 후 반드시 복원하세요:"
        echo    "     sudo systemctl unmask kubelet"
        echo    "     sudo systemctl start kubelet   # K8s 워크로드 재개 시"
        echo -e "   마커 파일: ${STATE_DIR}/kubelet-masked-by-script.txt"
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    fi
}
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
    # monitoring / agent
    "snmpd" "snmp"
    # 필수 텍스트/진단
    "vim-tiny" "nano" "less" "grep" "sed" "gawk" "tar" "gzip" "xz-utils" "file"
)

CEPH_WHITELIST=(
    "ceph*" "rados*" "rbd*" "librados*" "librbd*" "libceph*" "ceph-common"
    "xfsprogs" "smartmontools" "nvme-cli" "hdparm"
)
CEPHADM_WHITELIST=(
    "${CEPH_WHITELIST[@]}"
    "podman" "containers-common" "runc" "catatonit" "crun" "slirp4netns"
    "uidmap" "fuse-overlayfs" "skopeo" "buildah"
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
    # 크래시 리포트
    "apport" "apport-symptoms" "whoopsie" "apport-core-dump-handler" "ubuntu-report"
    "popularity-contest"
    # 멀티플렉서
    "byobu" "screen" "tmux"
    # 디버그/트레이스 (CSAP: 별도 승인 없이 상주 금지)
    "strace" "gdb" "crash" "bpftrace" "bpfcc-tools" "trace-cmd" "ltrace"
    "systemtap*" "sysdig"
    # 빌드/VCS
    "git" "subversion" "mercurial"
    # 컨테이너 (역할에 따라 whitelist 처리)
    "buildah" "podman" "docker.io" "docker-ce" "docker-ce-cli"
    # DNS 진단
    "bind9-dnsutils" "bind9-host" "bind9utils"
    # 퍼포먼스 도구
    "htop" "sysstat" "iotop" "nethogs" "iftop"
    # Snap
    "snapd"
)

# ============================================================================
# 5. RISK CATALOG
# ============================================================================
declare -A RISK_DESC=(
    [strace]="시스템콜 트레이스 불가 → 장애 진단 시 커널 레벨 분석 어려움"
    [gdb]="코어덤프 분석 불가 → 프로세스 크래시 원인 규명 제한"
    [bpftrace]="eBPF 기반 성능/장애 분석 불가"
    [bpfcc-tools]="biolatency, tcpconnect 등 BCC 툴 상실"
    [tcpdump]="네트워크 패킷 캡처 불가"
    [screen]="백그라운드 세션 상실 — systemd-run으로 대체 가능"
    [tmux]="백그라운드 세션 상실 — systemd-run으로 대체 가능"
    [byobu]="세션 래퍼 상실"
    [git]="현장 hotfix시 remote pull 불가"
    [podman]="cephadm/K8s 이미지 수동 검사 불가. cephadm 노드에서는 제거 절대 금지!"
    [buildah]="컨테이너 이미지 로컬 빌드 불가"
    [docker.io]="Docker 상실 — containerd 직접 사용 가능."
    [htop]="top 대체 시각화 상실"
    [sysstat]="sar 데이터 수집 중단"
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
# 6. PROFILE DETECTION
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
    if command -v cephadm &>/dev/null && [[ -d /var/lib/ceph ]]; then
        NODE_TYPE="cephadm"; return
    fi
    if command -v ceph &>/dev/null && [[ -f /etc/ceph/ceph.conf ]]; then
        if systemctl list-units --type=service --all 2>/dev/null | grep -qE 'ceph-(osd|mon|mgr|mds)@'; then
            NODE_TYPE="ceph"; return
        fi
    fi
    if systemctl is-active --quiet kubelet 2>/dev/null; then
        if [[ -f /etc/kubernetes/manifests/kube-apiserver.yaml ]] || \
           [[ -f /etc/kubernetes/manifests/etcd.yaml ]]; then
            NODE_TYPE="k8s-control"; return
        fi
        NODE_TYPE="k8s-worker"; return
    fi
    if systemctl is-active --quiet libvirtd 2>/dev/null || command -v qemu-system-x86_64 &>/dev/null; then
        NODE_TYPE="compute"; return
    fi
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

# [BUG-D 추가] apt/dpkg lock 사전 점검
check_apt_lock() {
    local lock_files=(
        "/var/lib/dpkg/lock-frontend"
        "/var/lib/dpkg/lock"
        "/var/lib/apt/lists/lock"
    )
    local locked=false
    local f
    for f in "${lock_files[@]}"; do
        if [[ -e "$f" ]] && fuser "$f" >/dev/null 2>&1; then
            log CRIT "apt/dpkg lock 점유 중: $f"
            fuser -v "$f" 2>&1 | head -5 || true
            locked=true
        fi
    done
    if $locked; then
        log CRIT "다른 apt/dpkg 프로세스가 실행 중입니다."
        log CRIT "  해결: sudo kill <PID> 또는 대기 후 재시도"
        exit 1
    fi
    log OK "apt/dpkg lock 사용 가능"
}

check_ssh_stability() {
    $SKIP_SSH_CHECK && { log WARN "SSH 안정성 체크 스킵"; return 0; }
    local since_ts; since_ts=$(date -d '30 minutes ago' '+%s' 2>/dev/null || echo "0")
    local linkdown_recent=false
    while IFS= read -r line; do
        local ts; ts=$(echo "$line" | grep -oP '\[\K[^\]]+' | head -1)
        local line_ts; line_ts=$(date -d "$ts" '+%s' 2>/dev/null || echo "0")
        if (( line_ts >= since_ts )); then
            linkdown_recent=true
            break
        fi
    done < <(dmesg -T 2>/dev/null | grep -E 'Link is Down|link down|NIC Link is Down' \
             | grep -vE 'SATA|ata[0-9]+:' || true)

    if $linkdown_recent; then
        log CRIT "최근 30분 내 NIC Link Down 로그 발견 → SSH 단절 위험. 확인 후 진행하세요."
        return 1
    fi
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
    if command -v cephadm &>/dev/null; then
        local orch; orch=$(timeout 10 ceph orch status 2>/dev/null | head -5 || echo "")
        [[ -n "$orch" ]] && log INFO "ceph orch status:" && echo "$orch" | sed 's/^/   /'
    fi
}

# [BUG-B + 5.0.4] kubelet health check — restart storm 탐지 + 자동 중단 승인/실행
check_k8s_health() {
    [[ "$NODE_TYPE" != k8s-* ]] && return 0

    # kubelet 서비스 유닛 존재 여부 확인
    if ! systemctl list-unit-files kubelet.service --no-legend 2>/dev/null | grep -q kubelet; then
        log INFO "kubelet.service 유닛 없음 — K8s health check 스킵"
        return 0
    fi

    # 현재 활성 상태 확인
    if systemctl is-active --quiet kubelet 2>/dev/null; then
        log OK "kubelet active"
        log WARN "권장: 패키지 제거 전에 'kubectl cordon <node>' 실행"
    else
        if [[ "$PROFILE" == "auto" ]]; then
            log CRIT "kubelet 비활성 — K8s 노드 상태 비정상. 중단."
            return 1
        else
            log WARN "kubelet 비활성 — 테스트/준비 환경으로 간주하고 계속 진행합니다."
            log WARN "  프로덕션 노드에서는 kubelet active 상태에서만 실행하세요."
        fi
    fi

    # ── restart storm 탐지 ────────────────────────────────────────────────────
    local restarts
    restarts=$(systemctl show kubelet --property=NRestarts 2>/dev/null \
               | cut -d= -f2 || echo 0)
    restarts=${restarts:-0}

    if (( restarts <= STORM_THRESHOLD )); then
        log OK "kubelet restart 횟수 정상 (NRestarts=${restarts})"
        return 0
    fi

    log WARN "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log WARN "⚠ kubelet RESTART STORM 탐지 (NRestarts=${restarts}, 임계치=${STORM_THRESHOLD})"
    log WARN "  이 상태에서 패키지 제거 시 위험:"
    log WARN "    1) 각 패키지 purge가 daemon-reload 트리거 → 과부하된 systemd에 추가 부하"
    log WARN "    2) autoremove가 systemd 관련 패키지 제거 시 deadlock 가능"
    log WARN "    3) 시스템 hang/패닉 위험 (test-nn2에서 NRestarts=572 상태로 실제 발생)"
    log WARN "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # 이미 masked 상태이면 storm 위험 없음
    local load_state
    load_state=$(systemctl show kubelet --property=LoadState 2>/dev/null \
                 | cut -d= -f2 || echo "unknown")
    if [[ "$load_state" == "masked" ]]; then
        log OK "kubelet 이미 mask 상태 — restart storm 위험 없음"
        return 0
    fi

    # ── [5.0.4] 자동 중단 승인 요청 ─────────────────────────────────────────
    log INFO "kubelet restart loop를 안전하게 중단하기 위한 작업:"
    log INFO "  실행 예정:"
    log INFO "    sudo systemctl stop kubelet    — 현재 인스턴스 즉시 중단"
    log INFO "    sudo systemctl mask kubelet    — 재부팅 전까지 자동 시작 차단"
    log INFO "  복원 방법 (테스트 완료 후):"
    log INFO "    sudo systemctl unmask kubelet"
    log INFO "    sudo systemctl start kubelet   # 필요시"

    local do_mask=false
    if $AUTO_YES; then
        log WARN "--yes 모드: kubelet mask/stop을 자동 승인합니다."
        do_mask=true
    else
        echo ""
        read -rp "kubelet을 지금 stop하고 mask하시겠습니까? (yes/no): " ok
        echo ""
        if [[ "$ok" == "yes" ]]; then
            do_mask=true
        else
            log WARN "kubelet mask/stop 거부됨."
            # storm 상태에서 --execute 를 계속할 것인지 추가 확인
            if $EXECUTE_MODE; then
                read -rp "kubelet storm 상태에서 --execute를 그대로 계속하시겠습니까? (yes/no): " ok2
                echo ""
                if [[ "$ok2" != "yes" ]]; then
                    log INFO "사용자 중단 — kubelet 상태 안정화 후 재시도하세요."
                    log INFO "  수동 중단 명령:"
                    log INFO "    sudo systemctl stop kubelet && sudo systemctl mask kubelet"
                    exit 0
                fi
                log WARN "사용자 확인 후 진행합니다 (hang 위험을 인지하고 계속)."
            fi
            return 0
        fi
    fi

    # ── 승인됨 — stop + mask 실행 ───────────────────────────────────────────
    log INFO "kubelet stop 중..."
    if systemctl stop kubelet 2>/dev/null; then
        log OK "kubelet stop 완료"
    else
        log WARN "kubelet stop 실패 또는 이미 중단 상태 (계속 진행)"
    fi

    log INFO "kubelet mask 중..."
    if systemctl mask kubelet 2>/dev/null; then
        log OK "kubelet mask 완료"
        KUBELET_MASKED_BY_SCRIPT=true
        # 마커 파일 기록 — 테스트 종료 후 unmask 상기용
        {
            echo "masked_at=$(date -Is)"
            echo "NRestarts_at_mask=${restarts}"
            echo "masked_by=${SCRIPT_NAME} v${SCRIPT_VERSION}"
            echo "unmask_cmd=systemctl unmask kubelet"
            echo "start_cmd=systemctl start kubelet"
        } > "${STATE_DIR}/kubelet-masked-by-script.txt"
    else
        log ERROR "kubelet mask 실패 — 수동으로 'systemctl mask kubelet' 실행하세요."
        return 0
    fi

    # ── 결과 검증 ────────────────────────────────────────────────────────────
    local new_load_state new_active_state
    new_load_state=$(systemctl show kubelet --property=LoadState 2>/dev/null \
                     | cut -d= -f2 || echo "unknown")
    new_active_state=$(systemctl show kubelet --property=ActiveState 2>/dev/null \
                       | cut -d= -f2 || echo "unknown")

    if [[ "$new_load_state" == "masked" ]]; then
        log OK "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log OK "검증 완료: kubelet LoadState=masked, ActiveState=${new_active_state}"
        log OK "restart storm 차단됨 — 안전하게 패키지 제거를 진행할 수 있습니다."
        log OK "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    else
        log WARN "kubelet LoadState=${new_load_state} (예상: masked) — 수동 확인 필요"
        log WARN "  현재 상태: $(systemctl status kubelet --no-pager -l 2>&1 | head -5)"
    fi
}

# [BUG-B] 전체 서비스 restart storm 점검
check_systemd_storm() {
    log INFO "systemd 서비스 restart storm 점검..."
    local storm_svcs=()
    local svc restarts
    # failed + activating 서비스 목록 수집
    while IFS= read -r svc; do
        [[ -z "$svc" ]] && continue
        restarts=$(systemctl show "$svc" --property=NRestarts 2>/dev/null \
                   | cut -d= -f2 || echo 0)
        restarts=${restarts:-0}
        if (( restarts > STORM_THRESHOLD )); then
            storm_svcs+=("${svc}(NRestarts=${restarts})")
        fi
    done < <(systemctl list-units --state=failed,activating --type=service \
             --no-pager --no-legend 2>/dev/null | awk '{print $1}')

    if (( ${#storm_svcs[@]} > 0 )); then
        log WARN "restart storm 서비스 탐지: ${storm_svcs[*]}"
        log WARN "이 서비스들이 패키지 제거 중 daemon-reload와 충돌할 수 있습니다."
        if $EXECUTE_MODE && ! $AUTO_YES; then
            log WARN "계속 진행하려면 해당 서비스를 mask 하는 것을 권장합니다:"
            for svc in "${storm_svcs[@]}"; do
                echo "   sudo systemctl mask ${svc%%(*}"
            done
        fi
    else
        log OK "systemd restart storm 없음"
    fi
}

check_disk_space() {
    local avail; avail=$(df -Pk "$STATE_DIR" | awk 'NR==2 {print $4}')
    if [[ $avail -lt 1048576 ]]; then
        log ERROR "백업 공간 부족 (<1GB at $STATE_DIR)"; return 1
    fi
    log OK "백업 공간 여유: $((avail/1024)) MB"
}

check_snapshot_recommendation() {
    $SKIP_SNAPSHOT_CHECK && return 0
    $EXECUTE_MODE || return 0
    if command -v lvs &>/dev/null; then
        local snap; snap=$(lvs --noheadings -o lv_name,lv_attr 2>/dev/null | awk '$2 ~ /^s/ {print $1}' || true)
        if [[ -z "$snap" ]]; then
            log WARN "LVM 스냅샷 없음. 실제 제거 전에 스냅샷 생성을 강력 권장:"
            log WARN "   예: lvcreate -L 5G -s -n root_premin /dev/ubuntu-vg/root"
            if ! $AUTO_YES; then
                read -rp "스냅샷 없이 계속하시겠습니까? (yes 입력): " ok
                if [[ "$ok" != "yes" ]]; then log INFO "사용자 중단"; exit 0; fi
            fi
        else
            log OK "LVM 스냅샷 발견: $snap"
        fi
    else
        log WARN "LVM 미사용 (lvs 없음) — 파일시스템 스냅샷 도구로 직접 백업 권장"
    fi
}

# [BUG-I] execute 전 pending 업그레이드 사전 감지 — 경고만, 자동 upgrade 없음
# 프로덕션 환경에서 apt-get upgrade는 변경관리 절차를 통해 별도 수행해야 함
check_pending_upgrades() {
    log INFO "pending apt 업그레이드 확인 중..."
    local pending_list
    pending_list=$(timeout "$APT_TIMEOUT" apt-get -s upgrade 2>/dev/null \
        | awk '/^Inst / {print $2}' | sort -u || true)
    local count
    count=$(printf '%s\n' "$pending_list" | grep -c . || true)

    if (( count == 0 )); then
        log OK "pending 업그레이드 없음 — apt 상태 최신"
        return 0
    fi

    log WARN "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log WARN "⚠ apt pending 업그레이드 ${count}개 탐지"
    log WARN "  이 상태에서 패키지 purge 시 apt가 업그레이드를 함께 처리하거나"
    log WARN "  신규 split 패키지를 자동 설치할 수 있습니다."
    log WARN "  (예: systemd 업그레이드 시 systemd-coredump 자동 설치 — test-nn3 사례)"
    log WARN ""
    log WARN "  pending 업그레이드 상위 10개:"
    printf '%s\n' "$pending_list" | head -10 | while read -r p; do
        log WARN "    - $p"
    done
    (( count > 10 )) && log WARN "    ... 외 $((count - 10))개"
    log WARN ""
    log WARN "  [프로덕션 권장 조치]"
    log WARN "    변경관리 절차에 따라 업그레이드를 먼저 완료한 후 스크립트를 실행하세요."
    log WARN "    현재 v5.0.6 이상에서는 batch purge 방식으로 자동 설치를 최소화하지만,"
    log WARN "    pending 업그레이드가 있으면 예상치 못한 동작이 발생할 수 있습니다."
    log WARN "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    # 경고 후 계속 진행 (block하지 않음 — 변경관리는 운영 절차 영역)
    return 0
}

# [BUG-I] execute 후 신규 패키지 탐지 — baseline 대비 추가된 패키지 WARN 로깅
verify_no_new_packages() {
    local baseline_dpkg="$1"  # 사전 백업된 dpkg --get-selections 파일 경로
    [[ -f "$baseline_dpkg" ]] || return 0

    local new_pkgs
    new_pkgs=$(comm -13 \
        <(awk '{print $1}' "$baseline_dpkg" | awk -F: '{print $1}' | sort -u) \
        <(dpkg -l 2>/dev/null | awk '/^ii/ {print $2}' | awk -F: '{print $1}' | sort -u) \
        || true)

    if [[ -z "$new_pkgs" ]]; then
        log OK "신규 패키지 없음 — execute 전후 패키지 집합 동일"
        return 0
    fi

    local cnt
    cnt=$(printf '%s\n' "$new_pkgs" | grep -c . || true)
    log WARN "execute 중 신규 패키지 ${cnt}개 설치됨 (의도하지 않은 자동 설치 가능성):"
    printf '%s\n' "$new_pkgs" | while read -r p; do
        log WARN "  + $p"
    done
    log WARN "  검토 후 불필요하면 수동 제거: sudo apt-get purge <패키지명>"
}

# [BUG-E] snapd 제거 전 snap 목록 확인
check_snapd_safety() {
    local candidates=("$@")
    local snapd_in_list=false
    local pkg
    for pkg in "${candidates[@]}"; do
        [[ "$pkg" == "snapd" ]] && snapd_in_list=true && break
    done
    $snapd_in_list || return 0
    command -v snap >/dev/null 2>&1 || return 0

    local snap_list
    snap_list=$(snap list 2>/dev/null | awk 'NR>1 && $1!="snapd" {print $1}' || true)
    if [[ -z "$snap_list" ]]; then
        log OK "snapd: 설치된 snap 없음 → 안전하게 제거 가능"
        return 0
    fi

    local count; count=$(echo "$snap_list" | wc -l)
    log WARN "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log WARN "⚠ snapd 제거 대상이지만 설치된 snap ${count}개가 있습니다:"
    echo "$snap_list" | sed 's/^/   /'
    log WARN "snap 앱이 있는 상태에서 snapd를 제거하면:"
    log WARN "  1) snapd prerm hook이 각 snap을 강제 제거 시도"
    log WARN "  2) snap 마운트(/snap/...) 해제 실패 시 → dpkg hang → 서버 hang 위험"
    log WARN "권장: 먼저 snap을 수동 제거 후 재실행:"
    echo "$snap_list" | while IFS= read -r s; do
        echo "   sudo snap remove --purge $s"
    done
    log WARN "또는 --exclude snapd 옵션으로 snapd 제거를 건너뛰세요."
    log WARN "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if $AUTO_YES; then
        log WARN "--yes 모드: snap이 있는 상태로 snapd 제거를 진행합니다. hang 위험을 인지하고 진행합니다."
        return 0
    fi

    if $EXECUTE_MODE; then
        read -rp "snap이 있는 상태로 snapd를 강제 제거하시겠습니까? (yes/no): " ok
        if [[ "$ok" != "yes" ]]; then
            log INFO "snapd 제거를 건너뜁니다. --exclude snapd 옵션 사용을 권장합니다."
            return 1  # caller가 snapd를 candidates에서 제외해야 함
        fi
        log WARN "사용자 확인: snap 존재 상태로 snapd 제거 진행"
    fi
    return 0
}

# ============================================================================
# 8. BASELINE & ROLLBACK
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

    tar --exclude='/etc/shadow*' --exclude='/etc/gshadow*' \
        -czf "${base}/etc-snapshot.tar.gz" /etc 2>/dev/null || true

    cp "${base}/dpkg-selections.txt" "${ROLLBACK_DIR}/pre-removal-selections.txt"
    cp "${base}/apt-manual.txt" "${ROLLBACK_DIR}/pre-removal-manual.txt" 2>/dev/null || true

    log OK "Baseline 저장: $base"
    log INFO "  - dpkg-selections, dpkg -l, apt-mark, services, ports, lsmod, /etc snapshot"
}

create_rollback_script() {
    local rb="${ROLLBACK_DIR}/rollback-v5-${TS}.sh"
    cat > "$rb" << EOF
#!/usr/bin/env bash
# Auto-generated rollback script (v${SCRIPT_VERSION}) - ${TS}
set -Euo pipefail
export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C.UTF-8

echo "=== ROLLBACK v${SCRIPT_VERSION} (${TS}) ==="
echo "이 스크립트는 제거 전 설치 패키지를 apt-get install로 복원합니다."
echo "설정 파일은 /var/lib/host-minimize/baseline/${TS}/etc-snapshot.tar.gz 에서 수동 복원하세요."
read -rp "진행하시겠습니까? (yes 입력): " ok
[[ "\$ok" == "yes" ]] || { echo "취소"; exit 0; }

apt-get update || true

SELECTIONS="/var/lib/host-minimize/rollback/pre-removal-selections.txt"
PKGS_TO_RESTORE=()
while IFS= read -r line; do
    pkg=\$(echo "\$line" | awk '{print \$1}')
    state=\$(echo "\$line" | awk '{print \$2}')
    [[ "\$state" != "install" ]] && continue
    base=\$(echo "\$pkg" | cut -d: -f1)
    current=\$(dpkg -l "\$base" 2>/dev/null | awk '/^[a-z]/ {print \$1}' | tail -1)
    [[ "\$current" != "ii" ]] && PKGS_TO_RESTORE+=("\$base")
done < "\$SELECTIONS"

if (( \${#PKGS_TO_RESTORE[@]} == 0 )); then
    echo "복원할 패키지 없음 (이미 설치됨)."
else
    echo "복원 대상: \${#PKGS_TO_RESTORE[@]} 개"
    apt-get install -y --no-install-recommends "\${PKGS_TO_RESTORE[@]}" || {
        echo "일부 패키지 설치 실패. 개별 재시도하거나 apt-get -f install 실행하세요."
    }
fi

if [[ -f /var/lib/host-minimize/rollback/pre-removal-manual.txt ]]; then
    while IFS= read -r pkg; do
        dpkg -l "\$pkg" 2>/dev/null | grep -q '^ii' && apt-mark manual "\$pkg" 2>/dev/null || true
    done < /var/lib/host-minimize/rollback/pre-removal-manual.txt
fi

echo "=== 복원 완료. reboot 권장. ==="
echo "※ /etc 설정 복원이 필요하면:"
echo "   tar -tzf /var/lib/host-minimize/baseline/${TS}/etc-snapshot.tar.gz | less"
EOF
    chmod +x "$rb"
    log OK "Rollback 스크립트 생성: $rb"
}

# ============================================================================
# 9. DEPENDENCY ANALYSIS
# ============================================================================
get_direct_dependents() {
    local pkg="$1"
    # [BUG-D] timeout 적용
    timeout "$APT_CACHE_TIMEOUT" apt-cache rdepends --no-suggests --no-conflicts \
        --no-breaks --no-replaces --no-enhances --installed "$pkg" 2>/dev/null \
        | tail -n +3 | sed 's/^[[:space:]]*//' | grep -v '^$' \
        | grep -vFx "$pkg" | sort -u
}

matches_whitelist() {
    local pkg="$1"; shift
    local w
    for w in "$@"; do
        case "$pkg" in
            $w) return 0 ;;
        esac
    done
    return 1
}

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

count_cascade_removals() {
    local pkg="$1"
    # [BUG-D] timeout 적용
    timeout "$APT_TIMEOUT" apt-get -s -y --auto-remove purge "$pkg" 2>/dev/null \
      | awk '/^(Remv|Purg) / {c++} END {print c+0}'
}

# [BUG-C] 위상 정렬 — 결과를 ORDERED_PACKAGES 전역 캐시에 저장
get_removal_order() {
    local -n arr_ref=$1

    # 이미 계산된 경우 캐시 반환
    if (( ${#ORDERED_PACKAGES[@]} > 0 )); then
        printf '%s\n' "${ORDERED_PACKAGES[@]}"
        return
    fi

    # [BUG-C] N > ORDER_SKIP_THRESHOLD 시 O(N²) 정렬 스킵
    if (( ${#arr_ref[@]} > ORDER_SKIP_THRESHOLD )); then
        log WARN "제거 후보 ${#arr_ref[@]}개 > ${ORDER_SKIP_THRESHOLD} → 위상 정렬 스킵 (O(N²) 방지)"
        ORDERED_PACKAGES=("${arr_ref[@]}")
        printf '%s\n' "${ORDERED_PACKAGES[@]}"
        return
    fi

    local pkg other
    local tmp; tmp=$(mktemp)
    for pkg in "${arr_ref[@]}"; do
        local deps_count=0
        for other in "${arr_ref[@]}"; do
            [[ "$pkg" == "$other" ]] && continue
            # [BUG-D] timeout 적용
            if timeout "$APT_CACHE_TIMEOUT" apt-cache depends --installed "$other" 2>/dev/null \
                | awk '/^[[:space:]]*(Depends|PreDepends):/ {print $2}' \
                | grep -Fxq "$pkg"; then
                deps_count=$((deps_count + 1))
            fi
        done
        printf '%d\t%s\n' "$deps_count" "$pkg" >> "$tmp"
    done
    mapfile -t ORDERED_PACKAGES < <(sort -n "$tmp" | cut -f2-)
    rm -f "$tmp"
    printf '%s\n' "${ORDERED_PACKAGES[@]}"
}

# ============================================================================
# 10. BUILD REMOVAL CANDIDATES
# ============================================================================
build_candidates() {
    local whitelist
    mapfile -t whitelist < <(get_whitelist)

    local exclude_merge=("${EXCLUDE_CLI[@]}")
    if [[ -f "$CONFIG_FILE" ]]; then
        local line
        while IFS= read -r line; do
            line="${line%%#*}"
            line="${line// /}"
            [[ -n "$line" ]] && exclude_merge+=("$line")
        done < "$CONFIG_FILE"
    fi

    local installed
    installed=$(dpkg -l 2>/dev/null | awk '/^ii/ {print $2}' | awk -F: '{print $1}' | sort -u)

    local cand=()
    local pat
    for pat in "${DEFAULT_SAFE_REMOVE[@]}"; do
        local match
        while IFS= read -r match; do
            [[ -z "$match" ]] && continue
            if matches_whitelist "$match" "${whitelist[@]}"; then continue; fi
            local ex found=false
            for ex in "${exclude_merge[@]}"; do
                [[ "$match" == "$ex" ]] && found=true && break
            done
            $found && continue
            cand+=("$match")
        done < <(printf '%s\n' "$installed" | awk -v p="$pat" '
                BEGIN {
                    gsub(/\./, "\\.", p)
                    gsub(/\*/, ".*", p)
                    gsub(/\?/, ".", p)
                    p = "^" p "$"
                }
                $0 ~ p { print }')
    done
    printf '%s\n' "${cand[@]}" | awk '!seen[$0]++'
}

# ============================================================================
# 11. DRY-RUN ANALYSIS
# ============================================================================
dry_run_full_analysis() {
    local -a packages=("$@")

    print_header
    log INFO "노드 타입: $NODE_TYPE"
    log INFO "제거 후보 개수: ${#packages[@]}"
    hr

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

    log INFO "Phase 2 — 연쇄 제거 및 위상 정렬"
    # [BUG-C] get_removal_order 결과가 ORDERED_PACKAGES에 캐시됨
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
            timeout "$APT_CACHE_TIMEOUT" apt-cache depends --installed "$pkg" 2>/dev/null \
                | awk '/^[[:space:]]+(Depends|PreDepends):/ {print "        ↳ " $2}' \
                | head -8
        fi
        total_direct=$((total_direct + 1))
        total_cascade=$((total_cascade + cascade))
    done

    echo
    hr
    local actual_cascade=0
    if (( total_direct > 0 )); then
        local all_purge_out
        # [BUG-D] timeout 적용
        all_purge_out=$(timeout "$APT_TIMEOUT" apt-get -s purge --auto-remove \
            "${packages[@]}" 2>/dev/null | grep -c '^Purg' || true)
        actual_cascade=$(( all_purge_out > total_direct ? all_purge_out - total_direct : 0 ))
    fi
    local total=$((total_direct + actual_cascade))
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║${NC} DRY-RUN v5.0 SUMMARY  (node: ${NODE_TYPE})"
    echo -e "${MAGENTA}╠══════════════════════════════════════════════════════════════════════════════╣${NC}"
    printf  "${MAGENTA}║${NC}   직접 제거 대상     : %4d 개\n" "$total_direct"
    printf  "${MAGENTA}║${NC}   연쇄 제거 예상     : %4d 개\n" "$actual_cascade"
    printf  "${MAGENTA}║${NC}   총 영향 패키지     : %4d 개\n" "$total"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo

    if [[ -n "$PLAN_OUT" ]]; then
        {
            echo "# host-minimize-safe-v5 plan"
            echo "generated_at: $(date -Is)"
            echo "node_type: $NODE_TYPE"
            echo "direct_count: $total_direct"
            echo "cascade_count: $actual_cascade"
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
# 12. RISK REPORT
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

    cat <<EOT

${YELLOW}※ Emergency Toolkit 제안${NC}
  장애 진단 도구를 제거하면 운영 시 복구 속도가 느려질 수 있습니다.
    A) 각 노드에 별도 debug-pkgs.deb 번들 준비 후 필요시만 dpkg -i
    B) 사내 APT 미러에서 strace/gdb/bpftrace를 즉시 설치 가능하도록 보장
    C) nsenter/kubectl debug(k8s) 사용 시에는 debug 사이드카 이미지 활용

${YELLOW}※ CSAP 대응${NC}
  본 스크립트는 CSAP 불필요 서비스/패키지 항목(2.4, 8.5, 9.3 계열)을 타겟으로 합니다.
  사내 보안 정책 및 감사 체크리스트와 매핑 후 승인받으세요.
EOT
}

# ============================================================================
# 13. REAL REMOVAL — 핵심 개선 (BUG-A, B, D, E, F, G)
# ============================================================================

# [BUG-A] autoremove 전 whitelist 패키지를 apt-mark manual로 보호
protect_whitelist_packages() {
    log INFO "autoremove 전 whitelist 패키지 apt-mark manual 설정 중..."
    local wl_arr
    mapfile -t wl_arr < <(get_whitelist)
    local installed
    installed=$(dpkg -l 2>/dev/null | awk '/^ii/ {print $2}' | awk -F: '{print $1}')

    # 중복 매칭 방지를 위해 매칭된 패키지 집합을 먼저 수집 후 일괄 처리
    declare -A _matched=()
    local pat match
    for pat in "${wl_arr[@]}"; do
        while IFS= read -r match; do
            [[ -z "$match" ]] && continue
            _matched["$match"]=1
        done < <(printf '%s\n' "$installed" | awk -v p="$pat" '
            BEGIN { gsub(/\./, "\\.", p); gsub(/\*/, ".*", p); gsub(/\?/, ".", p); p="^"p"$" }
            $0 ~ p { print }')
    done

    local marked=0
    if (( ${#_matched[@]} > 0 )); then
        # 한번의 apt-mark 호출로 일괄 처리 (성능 + 정확한 카운트)
        if apt-mark manual "${!_matched[@]}" >/dev/null 2>&1; then
            marked=${#_matched[@]}
        else
            # 일괄 실패 시 개별 fallback
            local pkg
            for pkg in "${!_matched[@]}"; do
                apt-mark manual "$pkg" >/dev/null 2>&1 && marked=$((marked + 1)) || true
            done
        fi
    fi
    log OK "whitelist 패키지 ${marked}개 apt-mark manual 완료 — autoremove 보호 활성"
}

# [BUG-A, F] autoremove: dry-run 사전 확인 → whitelist 침범 검사 → 사용자 확인 → 실행
do_autoremove() {
    log INFO "자동 의존성 정리 — dry-run 사전 확인 중..."

    local autoremove_pkgs
    autoremove_pkgs=$(timeout "$APT_TIMEOUT" apt-get -s autoremove --purge 2>/dev/null \
        | awk '/^Remv / {gsub(/\[.*\]/, "", $2); print $2}' | sort -u || true)

    if [[ -z "$autoremove_pkgs" ]]; then
        log OK "autoremove 대상 없음 (whitelist 보호 완료)"
        timeout "$APT_TIMEOUT" apt-get -y autoclean >>"$LOG_FILE" 2>&1 || true
        return 0
    fi

    local count; count=$(echo "$autoremove_pkgs" | wc -l)
    log INFO "autoremove 예정 패키지 (${count}개):"
    echo "$autoremove_pkgs" | head -40 | sed 's/^/   /'
    (( count > 40 )) && log WARN "   ... 외 $((count - 40))개 (전체 목록: $LOG_FILE)"
    echo "$autoremove_pkgs" >> "$LOG_FILE"

    # [BUG-A] whitelist 침범 검사
    local wl_arr
    mapfile -t wl_arr < <(get_whitelist)
    local dangerous=()
    while IFS= read -r pkg; do
        if matches_whitelist "$pkg" "${wl_arr[@]}"; then
            dangerous+=("$pkg")
        fi
    done <<< "$autoremove_pkgs"

    if (( ${#dangerous[@]} > 0 )); then
        log CRIT "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log CRIT "⚠ autoremove 대상에 whitelist 패키지 포함됨 — autoremove를 중단합니다!"
        log CRIT "  침범 패키지: ${dangerous[*]}"
        log CRIT "  원인: apt의 auto-install 마킹과 whitelist 간 불일치"
        log CRIT "  조치: 수동으로 확인 후 필요시 apt-mark manual <패키지> 설정"
        log CRIT "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        timeout "$APT_TIMEOUT" apt-get -y autoclean >>"$LOG_FILE" 2>&1 || true
        return 0
    fi

    # [BUG-A] systemd 계열 포함 시 별도 경고
    local systemd_pkgs
    systemd_pkgs=$(echo "$autoremove_pkgs" | grep -E '^systemd|^libc-|^libsystemd' || true)
    if [[ -n "$systemd_pkgs" ]]; then
        log WARN "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log WARN "⚠ autoremove 대상에 systemd 계열 패키지 포함:"
        echo "$systemd_pkgs" | sed 's/^/   ⚠ /'
        log WARN "  systemd 관련 패키지 제거는 시스템 안정성에 영향을 줄 수 있습니다."
        log WARN "  이 패키지들을 제거하면 daemon-reload 동작이 변경되거나"
        log WARN "  비정상 서비스 restart storm 상태에서 시스템 hang을 유발할 수 있습니다."
        log WARN "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        if ! $AUTO_YES; then
            read -rp "systemd 계열 패키지를 포함하여 autoremove를 진행하시겠습니까? (yes/no): " ok
            if [[ "$ok" != "yes" ]]; then
                log INFO "autoremove 스킵 (systemd 계열 포함으로 사용자 거부)"
                timeout "$APT_TIMEOUT" apt-get -y autoclean >>"$LOG_FILE" 2>&1 || true
                return 0
            fi
        fi
    fi

    # 최종 사용자 확인 (--yes 없는 경우)
    if ! $AUTO_YES; then
        read -rp "위 ${count}개 패키지를 autoremove로 제거하시겠습니까? (yes/no): " ok
        if [[ "$ok" != "yes" ]]; then
            log INFO "autoremove 스킵 (사용자 거부)"
            timeout "$APT_TIMEOUT" apt-get -y autoclean >>"$LOG_FILE" 2>&1 || true
            return 0
        fi
    fi

    log INFO "autoremove 실행 중 (timeout=${AUTOREMOVE_TIMEOUT}s)..."
    local ar_ec=0
    apt_exec ar_ec "$AUTOREMOVE_TIMEOUT" apt-get -y autoremove --purge || true
    if (( ar_ec == 124 )); then
        log CRIT "autoremove TIMEOUT (${AUTOREMOVE_TIMEOUT}s) — dpkg/apt 상태 확인 필요!"
        log CRIT "  진단: sudo dpkg --audit ; sudo apt-get check"
    elif (( ar_ec != 0 )); then
        log WARN "autoremove 일부 실패 (exit=${ar_ec})"
    else
        log OK "autoremove 완료"
    fi
    timeout "$APT_TIMEOUT" apt-get -y autoclean >>"$LOG_FILE" 2>&1 || true
}

real_removal() {
    local -a packages=("$@")
    print_header
    log WARN "=== REAL REMOVAL MODE ==="
    log WARN "제거 대상: ${#packages[@]} 개"

    if ! $AUTO_YES; then
        read -rp "정말로 삭제를 진행하시겠습니까? (YES 대문자 입력): " confirm
        [[ "$confirm" == "YES" ]] || { log INFO "취소됨"; exit 0; }
    fi

    # [BUG-I] 사전 baseline 패키지 목록 스냅샷 (신규 패키지 탐지용)
    local pre_baseline
    pre_baseline=$(mktemp)
    dpkg --get-selections > "$pre_baseline" 2>/dev/null || true

    # [BUG-I] 실제 설치된 패키지만 필터링 (rc 제외)
    local -a to_purge=()
    local pkg
    for pkg in "${packages[@]}"; do
        dpkg -l 2>/dev/null | awk -v p="$pkg" '$1=="ii" && $2==p{found=1} END{exit !found}' \
            && to_purge+=("$pkg") || true
    done

    if (( ${#to_purge[@]} == 0 )); then
        log INFO "제거할 패키지 없음 (모두 미설치 또는 rc 상태)"
        rm -f "$pre_baseline"
        return 0
    fi

    log INFO "실제 제거 대상 (ii 상태): ${#to_purge[@]} 개"
    for pkg in "${to_purge[@]}"; do
        log INFO "  - $pkg"
    done

    # [BUG-I] 핵심 수정: 개별 purge 루프 → 단일 batch purge
    # 개별 purge 시 apt가 virtual package Conflicts/Provides 체인으로 의도치 않은
    # 패키지를 자동 설치하는 문제 방지. batch purge는 전체 의존성을 한번에 해석하므로
    # 불필요한 대체 패키지 설치가 발생하지 않음. (검증: 0 newly installed)
    log INFO "batch purge 실행 중 (timeout=${AUTOREMOVE_TIMEOUT}s)..."
    $VERBOSE && log DEBUG "대상 패키지: ${to_purge[*]}"
    local batch_failed=false
    local batch_start; batch_start=$(date +%s)
    local batch_ec=0
    apt_exec batch_ec "$AUTOREMOVE_TIMEOUT" apt-get -y purge "${to_purge[@]}" || true
    local batch_elapsed=$(( $(date +%s) - batch_start ))
    if (( batch_ec == 124 )); then
        log CRIT "TIMEOUT: batch purge가 ${AUTOREMOVE_TIMEOUT}초(${batch_elapsed}s 경과) 초과!"
        log CRIT "  진단: sudo ps aux | grep -E 'dpkg|apt' ; sudo journalctl -f"
    elif (( batch_ec != 0 )); then
        log ERROR "batch purge 실패 (exit=${batch_ec}, 경과=${batch_elapsed}s) — 개별 재시도 시작"
        # batch 실패 시 개별 fallback (원인 격리)
        local retry_ok=0 retry_fail=0
        for pkg in "${to_purge[@]}"; do
            dpkg -l 2>/dev/null | awk -v p="$pkg" '$1=="ii" && $2==p{f=1} END{exit !f}' || continue
            log INFO "  재시도: $pkg"
            local retry_ec=0
            apt_exec retry_ec "$PKG_REMOVE_TIMEOUT" apt-get -y purge "$pkg" || true
            if (( retry_ec != 0 )); then
                log ERROR "  실패: $pkg (exit=${retry_ec})"
                batch_failed=true
                retry_fail=$(( retry_fail + 1 ))
            else
                log OK "  성공: $pkg"
                retry_ok=$(( retry_ok + 1 ))
            fi
        done
        log INFO "  재시도 결과 — 성공: ${retry_ok}개 / 실패: ${retry_fail}개"
    else
        log OK "batch purge 완료 (경과=${batch_elapsed}s)"
    fi

    # [BUG-A, F] autoremove: whitelist 보호 → dry-run 표시 → 확인 → 실행
    protect_whitelist_packages
    do_autoremove

    # 사후 검증
    hr
    log INFO "=== 사후 검증 ==="
    local remaining=0
    for pkg in "${packages[@]}"; do
        dpkg -l 2>/dev/null | awk -v p="$pkg" '$1=="ii" && $2==p{found=1} END{exit !found}' \
            && remaining=$((remaining + 1)) || true
    done
    log INFO "아직 설치된 대상: $remaining 개"

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
    if ss -tlnp 2>/dev/null | grep -q ':22 '; then
        log OK "sshd 포트 22 listen 유지"
    else
        log CRIT "sshd 포트 22 listen 하지 않음 — 즉시 재시작!"
    fi

    # dpkg 상태 검사
    if dpkg --audit 2>&1 | grep -qE '.+'; then
        log WARN "dpkg --audit 에서 이상 감지됨 — 확인 필요"
        dpkg --audit 2>&1 | head -10
    else
        log OK "dpkg --audit 이상 없음"
    fi

    # [BUG-J / KI-05] purge 후 systemd timer/서비스 failed 상태 잔류 정리
    # 예: sysstat 제거 후 sysstat-collect.timer 등이 not-found/failed로 잔류
    local failed_units
    failed_units=$(systemctl list-units --failed --no-legend --no-pager 2>/dev/null \
        | awk '{print $1}' | grep -v '^$' || true)
    if [[ -n "$failed_units" ]]; then
        local fcount; fcount=$(printf '%s\n' "$failed_units" | wc -l)
        log INFO "purge 후 failed 유닛 ${fcount}개 탐지 — reset-failed 정리 중:"
        printf '%s\n' "$failed_units" | sed 's/^/   /'
        systemctl reset-failed 2>/dev/null || true
        log OK "systemctl reset-failed 완료"
    fi

    # [BUG-I] 신규 패키지 탐지 — execute 전 baseline 대비 추가 설치 여부 확인
    verify_no_new_packages "$pre_baseline"
    rm -f "$pre_baseline"

    $batch_failed && log WARN "일부 패키지 제거 실패 — 위 로그 확인 필요" || true
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
  --verbose                apt 명령 출력을 터미널에 실시간 표시 (DEBUG 로그 포함)
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
            --verbose) VERBOSE=true; shift ;;
            -h|--help) usage; exit 0 ;;
            *) log ERROR "알 수 없는 옵션: $1"; usage; exit 2 ;;
        esac
    done
}

main() {
    parse_args "$@"
    init_logging
    validate_profile

    check_root
    acquire_lock

    print_header
    log INFO "Version $SCRIPT_VERSION / $(date -Is)"
    detect_node_type
    log INFO "Detected/Selected node type: $NODE_TYPE"

    # 사전 점검
    check_disk_space        || exit 1
    check_apt_lock          || exit 1   # [BUG-D 추가]
    check_ssh_stability     || exit 1
    check_ceph_health       || exit 1
    check_k8s_health        || exit 1   # [BUG-B] restart storm 탐지 포함
    check_systemd_storm                 # [BUG-B 추가] 전체 서비스 storm 점검
    check_pending_upgrades              # [BUG-I] pending 업그레이드 경고 (non-blocking)

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
        # [BUG-E] snapd 사전 안전성 확인 (--execute 진입 직후)
        if ! check_snapd_safety "${to_remove[@]}"; then
            # snapd를 candidates에서 제외
            local filtered=()
            local p
            for p in "${to_remove[@]}"; do
                [[ "$p" == "snapd" ]] || filtered+=("$p")
            done
            to_remove=("${filtered[@]}")
            log INFO "snapd를 제거 목록에서 제외했습니다. 나머지 ${#to_remove[@]}개 진행."
        fi

        check_snapshot_recommendation
        # 제거 전 최종 dry-run 결과 요약
        dry_run_full_analysis "${to_remove[@]}" || exit 2
        real_removal "${to_remove[@]}"
    else
        dry_run_full_analysis "${to_remove[@]}"
    fi
}

main "$@"
