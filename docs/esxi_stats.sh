#!/bin/bash

# 서버 목록
servers=("mca5101" "mca5203" "mca5303")

# 파일명 접두사 정의 (서버별로 다르게 설정)
prefixes=(
    "mca5101:pb1hcn05-vc053-sam.t1pb1.scpcloud.co.kr"
    "mca5203:pb1hcn01-vc053-sam"
    "mca5303:pb1hcn05-vc053-sam.t1pb1.scpcloud.co.kr"
)

# 결과를 저장할 배열
declare -A results

for server in "${servers[@]}"; do
    # 서버에 맞는 접두사 찾기
    prefix=""
    for entry in "${prefixes[@]}"; do
        if [[ $entry == $server:* ]]; then
            prefix="${entry#*:}"
            break
        fi
    done

    if [ -z "$prefix" ]; then
        echo "서버 $server에 대한 접두사를 찾을 수 없습니다."
        continue
    fi

    # 파일명 생성 (두 개의 시간대를 비교한다고 가정)
    file1="${prefix}_[${server}]_stats_0615_225500.txt"
    file2="${prefix}_[${server}]_stats_0616_005500.txt"

    # 파일 존재 여부 확인
    if [ ! -f "$file1" ] || [ ! -f "$file2" ]; then
        echo "파일이 존재하지 않습니다: $file1 또는 $file2"
        continue
    fi

    # 통계값 추출 (숫자만)
    broadcast_rx_ok_1=$(grep "broadcast pkts rx ok:" "$file1" | sed 's/.*broadcast pkts rx ok://' | tr -d ' ' | head -n 1)
    broadcast_rx_ok_2=$(grep "broadcast pkts rx ok:" "$file2" | sed 's/.*broadcast pkts rx ok://' | tr -d ' ' | head -n 1)

    dropped_rx_1=$(grep "droppedRx:" "$file1" | sed 's/.*droppedRx://' | tr -d ' ' | head -n 1)
    dropped_rx_2=$(grep "droppedRx:" "$file2" | sed 's/.*droppedRx://' | tr -d ' ' | head -n 1)

    pkts_rx_broadcast_1=$(grep "pktsRxBroadcast:" "$file1" | sed 's/.*pktsRxBroadcast://' | tr -d ' ' | head -n 1)
    pkts_rx_broadcast_2=$(grep "pktsRxBroadcast:" "$file2" | sed 's/.*pktsRxBroadcast://' | tr -d ' ' | head -n 1)

    # 델타 계산
    if [ -n "$broadcast_rx_ok_1" ] && [ -n "$broadcast_rx_ok_2" ]; then
        delta_broadcast_rx_ok=$((broadcast_rx_ok_2 - broadcast_rx_ok_1))
    else
        delta_broadcast_rx_ok="N/A"
    fi

    if [ -n "$dropped_rx_1" ] && [ -n "$dropped_rx_2" ]; then
        delta_dropped_rx=$((dropped_rx_2 - dropped_rx_1))
    else
        delta_dropped_rx="N/A"
    fi

    if [ -n "$pkts_rx_broadcast_1" ] && [ -n "$pkts_rx_broadcast_2" ]; then
        delta_pkts_rx_broadcast=$((pkts_rx_broadcast_2 - pkts_rx_broadcast_1))
    else
        delta_pkts_rx_broadcast="N/A"
    fi

    # 결과 저장
    results["${server}_broadcast pkts rx ok"]=$delta_broadcast_rx_ok
    results["${server}_droppedRx"]=$delta_dropped_rx
    results["${server}_pktsRxBroadcast"]=$delta_pkts_rx_broadcast
done

# Markdown 표 출력
echo "| 서버     | broadcast pkts rx ok | droppedRx | pktsRxBroadcast |"
echo "|----------|----------------------|-----------|-----------------|"
for server in "${servers[@]}"; do
    printf "| %-8s | %-20s | %-9s | %-15s |\n" "$server" "${results[${server}_broadcast pkts rx ok]}" "${results[${server}_droppedRx]}" "${results[${server}_pktsRxBroadcast]}"
done
