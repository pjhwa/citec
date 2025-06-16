#!/bin/bash

# Declare associative array to store statistics
declare -A stats

# Initialize variables to track current state
current_time=""
current_vm=""
current_section=""
current_subsection=""
in_rx_queue=false

# Function to store ethtool totals for a VM at a specific time
store_ethtool_totals() {
    if [ "$current_section" == "ethtool" ] && [ -n "$current_vm" ] && [ -n "$current_time" ]; then
        stats["${current_vm}_${current_time}_drv dropped rx total"]=$drv_dropped_rx_total
        stats["${current_vm}_${current_time}_rx buf alloc fail"]=$rx_buf_alloc_fail
        stats["${current_vm}_${current_time}_pkts rx err"]=$pkts_rx_err
        stats["${current_vm}_${current_time}_bcast pkts rx"]=$bcast_pkts_rx
    fi
}

# Parse the input file
while read -r line; do
    # Detect timestamp
    if [[ $line =~ ^Mon\ Jun\ 16\ (07|09):55:01\ KST\ 2025$ ]]; then
        store_ethtool_totals
        current_time="${BASH_REMATCH[1]}:55:01"
        current_vm=""
        current_section=""
        current_subsection=""
        in_rx_queue=false

    # Detect VM and section (netstat or ethtool)
    elif [[ $line =~ ^(mca[0-9]+)_(netstat|ethtool)$ ]]; then
        store_ethtool_totals
        current_vm="${BASH_REMATCH[1]}"
        current_section="${BASH_REMATCH[2]}"
        if [ "$current_section" == "ethtool" ]; then
            # Initialize ethtool totals
            drv_dropped_rx_total=0
            rx_buf_alloc_fail=0
            pkts_rx_err=0
            bcast_pkts_rx=0
        fi
        current_subsection=""
        in_rx_queue=false

    # Process netstat section
    elif [ "$current_section" == "netstat" ]; then
        # Detect subsections
        if [[ $line == "Ip:" ]]; then
            current_subsection="Ip"
        elif [[ $line == "Udp:" ]]; then
            current_subsection="Udp"
        elif [[ $line == "IpExt:" ]]; then
            current_subsection="IpExt"
        fi

        # Extract statistics
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

    # Process ethtool section
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

# Store totals for the last ethtool section
store_ethtool_totals

# Define VM list and statistics order
vms=("mca5102" "mca5204" "mca5304" "mca7106" "mca7208" "mca7308")
stats_order=(
    "Udp packets received"
    "Udp packet receive errors"
    "IpExt InBcastPkts"
    "UdpRcvbufErrors"
    "Ip InDiscards"
    "Udp InErrors"
    "drv dropped rx total"
    "rx buf alloc fail"
    "pkts rx err"
    "bcast pkts rx"
)

# Output markdown table header
echo "| VM | Udp packets received | Udp packet receive errors | IpExt InBcastPkts | UdpRcvbufErrors | Ip InDiscards | Udp InErrors | drv dropped rx total | rx buf alloc fail | pkts rx err | bcast pkts rx |"
echo "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |"

# Calculate and output delta values for each VM
for vm in "${vms[@]}"; do
    echo -n "| $vm "
    for stat in "${stats_order[@]}"; do
        val1=${stats["${vm}_07:55:01_${stat}"]}
        val2=${stats["${vm}_09:55:01_${stat}"]}
        if [ -n "$val1" ] && [ -n "$val2" ]; then
            delta=$((val2 - val1))
            echo -n "| $delta "
        else
            echo -n "| N/A "
        fi
    done
    echo "|"
done
