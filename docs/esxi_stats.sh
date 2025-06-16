#!/bin/bash

# 서버 목록
servers=("mca5101" "mca5203" "mca5303")

# 파일명 형식
file1="_stats_0615_225500.txt"
file2="_stats_0616_005500.txt"

# 결과를 저장할 배열
declare -A results

for server in "${servers[@]}"; do
    # 파일명 생성
    file_0755="pb1hcn05-vc053-sam_[${server}]${file1}"
    file_0955="pb1hcn05-vc053-sam_[${server}]${file2}"

    # 파일이 존재하는지 확인
    if [ ! -f "$file_0755" ] || [ ! -f "$file_0955" ]; then
        echo "파일이 존재하지 않습니다: $file_0755 또는 $file_0955"
        continue
    fi

    # broadcast pkts rx ok 추출 (숫자만 추출)
    broadcast_rx_ok_0755=$(grep "broadcast pkts rx ok:" "$file_0755" | sed 's/.*broadcast pkts rx ok://' | tr -d ' ' | head -n 1)
    broadcast_rx_ok_0955=$(grep "broadcast pkts rx ok:" "$file_0955" | sed 's/.*broadcast pkts rx ok://' | tr -d ' ' | head -n 1)

    # droppedRx 추출
    dropped_rx_0755=$(grep "droppedRx:" "$file_0755" | sed 's/.*droppedRx://' | tr -d ' ' | head -n 1)
    dropped_rx_0955=$(grep "droppedRx:" "$file_0955" | sed 's/.*droppedRx://' | tr -d ' ' | head -n 1)

    # pktsRxBroadcast 추출
    pkts_rx_broadcast_0755=$(grep "pktsRxBroadcast:" "$file_0755" | sed 's/.*pktsRxBroadcast://' | tr -d ' ' | head -n 1)
    pkts_rx_broadcast_0955=$(grep "pktsRxBroadcast:" "$file_0955" | sed 's/.*pktsRxBroadcast://' | tr -d ' ' | head -n 1)

    # 델타 계산
    if [ -n "$broadcast_rx_ok_0755" ] && [ -n "$broadcast_rx_ok_0955" ]; then
        delta_broadcast_rx_ok=$((broadcast_rx_ok_0955 - broadcast_rx_ok_0755))
    else
        delta_broadcast_rx_ok="N/A"
    fi

    if [ -n "$dropped_rx_0755" ] && [ -n "$dropped_rx_0955" ]; then
        delta_dropped_rx=$((dropped_rx_0955 - dropped_rx_0755))
    else
        delta_dropped_rx="N/A"
    fi

    if [ -n "$pkts_rx_broadcast_0755" ] && [ -n "$pkts_rx_broadcast_0955" ]; then
        delta_pkts_rx_broadcast=$((pkts_rx_broadcast_0955 - pkts_rx_broadcast_0755))
    else
        delta_pkts_rx_broadcast="N/A"
    fi

    # 결과 저장
    results["${server}_broadcast pkts rx ok"]=$delta_broadcast_rx_ok
    results["${server}_droppedRx"]=$delta_dropped_rx
    results["${server}_pktsRxBroadcast"]=$delta_pkts_rx_broadcast
done

# 결과 출력
echo "서버     | broadcast pkts rx ok | droppedRx | pktsRxBroadcast"
echo "---------|----------------------|-----------|----------------"
for server in "${servers[@]}"; do
    printf "%-8s | %-20s | %-9s | %-15s\n" "$server" "${results[${server}_broadcast pkts rx ok]}" "${results[${server}_droppedRx]}" "${results[${server}_pktsRxBroadcast]}"
done
