#!/bin/bash

# 연관 배열 선언
declare -A stats

# 현재 상태 변수 초기화
current_time=""
current_vm=""
current_section=""
current_subsection=""
in_rx_queue=false

# ethtool 통계값 합계를 저장하는 함수
store_ethtool_totals() {
    if [ "$current_section" == "ethtool" ] && [ -n "$current_vm" ] && [ -n "$current_time" ]; then
        stats["${current_vm}_${current_time}_drv dropped rx total"]=$drv_dropped_rx_total
        stats["${current_vm}_${current_time}_rx buf alloc fail"]=$rx_buf_alloc_fail
        stats["${current_vm}_${current_time}_pkts rx err"]=$pkts_rx_err
        stats["${current_vm}_${current_time}_bcast pkts rx"]=$bcast_pkts_rx
    fi
}

# 입력 파일 파싱
while read -r line; do
    # 타임스탬프 감지
    if [[ $line =~ ^Mon\ Jun\ 16\ (07|09):55:01\ KST\ 2025$ ]]; then
        store_ethtool_totals
        current_time="${BASH_REMATCH[1]}:55:01"
        current_vm=""
        current_section=""
        current_subsection=""
        in_rx_queue=false

    # VM 및 섹션(netstat 또는 ethtool) 감지
    elif [[ $line =~ ^(mca[0-9]+)_(netstat|ethtool)$ ]]; then
        store_ethtool_totals
        current_vm="${BASH_REMATCH[1]}"
        current_section="${BASH_REMATCH[2]}"
        if [ "$current_section" == "ethtool" ]; then
            # ethtool 합계 초기화
            drv_dropped_rx_total=0
            rx_buf_alloc_fail=0
            pkts_rx_err=0
            bcast_pkts_rx=0
        fi
        current_subsection=""
        in_rx_queue=false

    # netstat 섹션 처리
    elif [ "$current_section" == "netstat" ]; then
        # 하위 섹션 감지
        if [[ $line == "Ip:" ]]; then
            current_subsection="Ip"
        elif [[ $line == "Udp:" ]]; then
            current_subsection="Udp"
        elif [[ $line == "IpExt:" ]]; then
            current_subsection="IpExt"
        fi

        # 통계값 추출
        if [ "$current_subsection" == "Ip" ]; then
            if [[ $line =~ ([0-9]+)\ incoming\ packets\ discarded ]]; then
                stats["${current_vm}_${current_time}_Ip InDiscards"]=${BASH_REMATCH[1]}
            fi
        elif [ "$current_subsection" == "Udp" ]; then
            if [[ $line =~ ([0-9]+)\ packets\ received ]]; then
                stats["${current_vm}_${current_time}_Udp packets received"]=${BASH_REMATCH[1]}
            elif [[ $line =~ ([0-9]+)\ packet\ receive\ errors ]]; then
                stats["${current_vm}_${current_time}_Udp packet receive errors"]=${BASH_REMATCH[1]}
                stats["${current_vm}_${current_time}_Udp InErrors"]=${BASH_REMATCH[1]}
            elif [[ $line =~ ([0-9]+)\ receive\ buffer\ errors ]]; then
                stats["${current_vm}_${current_time}_UdpRcvbufErrors"]=${BASH_REMATCH[1]}
            fi
        elif [ "$current_subsection" == "IpExt" ]; then
            if [[ $line =~ InBcastPkts:\ ([0-9]+) ]]; then
                stats["${current_vm}_${current_time}_IpExt InBcastPkts"]=${BASH_REMATCH[1]}
            fi
        fi

    # ethtool 섹션 처리
    elif [ "$current_section" == "ethtool" ]; then
        if [[ $line =~ Rx\ Queue#:\ [0-9]+ ]]; then
            in_rx_queue=true
        elif $in_rx_queue; then
            if [[ $line =~ drv\ dropped\ rx\ total:\ ([0-9]+) ]]; then
                ((drv_dropped_rx_total += ${BASH_REMATCH[1]}))
            elif [[ $line =~ rx\ buf\ alloc\ fail:\ ([0-9]+) ]]; then
                ((rx_buf_alloc_fail += ${BASH_REMATCH[1]}))
            elif [[ $line =~ pkts\ rx\ err:\ ([0-9]+) ]]; then
                ((pkts_rx_err += ${BASH_REMATCH[1]}))
            elif [[ $line =~ bcast\ pkts\ rx:\ ([0-9]+) ]]; then
                ((bcast_pkts_rx += ${BASH_REMATCH[1]}))
            fi
        fi
    fi
done < "data.txt"

# 마지막 ethtool 섹션의 합계 저장
store_ethtool_totals

# VM 및 통계값 목록 정의
vms=("mca5102" "mca5204" "mca5304" "mca7106" "mca7208" "mca7308")
stats_list=(
    "IpExt InBcastPkts"
    "UdpRcvbufErrors"
    "Ip InDiscards"
    "Udp InErrors"
    "Udp packets received"
    "Udp packet receive errors"
    "drv dropped rx total"
    "rx buf alloc fail"
    "pkts rx err"
    "bcast pkts rx"
)

# 표 헤더 출력
printf "%-10s" "VM"
for stat in "${stats_list[@]}"; do
    printf " | %-20s" "$stat"
done
printf "\n"

# 구분선 출력
printf "%-10s" "----------"
for _ in "${stats_list[@]}"; do
    printf " | --------------------"
done
printf "\n"

# 각 VM의 델타값 계산 및 출력
for vm in "${vms[@]}"; do
    printf "%-10s" "$vm"
    for stat in "${stats_list[@]}"; do
        val1=${stats["${vm}_07:55:01_${stat}"]}
        val2=${stats["${vm}_09:55:01_${stat}"]}
        if [ -n "$val1" ] && [ -n "$val2" ]; then
            delta=$((val2 - val1))
            printf " | %-20d" "$delta"
        else
            printf " | %-20s" "N/A"
        fi
    done
    printf "\n"
done
