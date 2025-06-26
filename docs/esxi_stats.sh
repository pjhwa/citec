#!/bin/bash

# 인자 확인: 오늘 날짜 (MMDD 형식, 예: 0617)
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <MMDD>"
    exit 1
fi

today=$1  # 오늘 날짜 (예: 0617)

# 전날 날짜 계산 (예: 0616)
yesterday=$(date -d "2025-$today -1 day" +%m%d 2>/dev/null || date -v-1d -j -f "%m%d" "2025$today" +%m%d)

# 디렉토리 경로
DIR="/mnt/c/Users/jooksan.park/src/esxi"

# 서버 목록
servers=("mca5103" "mca5201" "mca5301")

# 파일명 접두사 정의
prefixes=(
    "mca5103:pb1hcn09-vc053-sam"
    "mca5201:pb1hcn01-vc052-sam"
    "mca5301:pb1hcn09-vc053-sam"
)

# 최대 대역폭 설정 (10Gbps = 10000 Mbps)
MAX_BANDWIDTH=10000  # Mbps

# 시간 간격 설정 (7200초 = 2시간)
TIME_INTERVAL=7200  # seconds

# 결과를 저장할 연관 배열
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

    # 파일명 생성 (전날과 오늘 파일)
    file_yesterday="${DIR}/${prefix}_[${server}]_stats_${yesterday}_225500.txt"
    file_today="${DIR}/${prefix}_[${server}]_stats_${today}_005500.txt"

    # 디버깅: 확인하려는 파일명 출력
    echo "서버 $server의 파일 확인: $file_yesterday 및 $file_today"

    # 파일 존재 여부 확인
    if [ ! -f "$file_yesterday" ]; then
        echo "파일이 존재하지 않습니다: $file_yesterday"
        results["${server}_broadcast pkts rx ok"]="N/A"
        results["${server}_droppedRx"]="N/A"
        results["${server}_pktsRxBroadcast"]="N/A"
        results["${server}_vmnic5_rx_usage"]="N/A"
        results["${server}_vmnic5_tx_usage"]="N/A"
        continue
    fi

    if [ ! -f "$file_today" ]; then
        echo "파일이 존재하지 않습니다: $file_today"
        results["${server}_broadcast pkts rx ok"]="N/A"
        results["${server}_droppedRx"]="N/A"
        results["${server}_pktsRxBroadcast"]="N/A"
        results["${server}_vmnic5_rx_usage"]="N/A"
        results["${server}_vmnic5_tx_usage"]="N/A"
        continue
    fi

    # 통계값 추출 (broadcast pkts rx ok)
    broadcast_rx_ok_1=$(grep "broadcast pkts rx ok:" "$file_yesterday" | sed 's/.*broadcast pkts rx ok://' | tr -d ' ' | head -n 1)
    broadcast_rx_ok_2=$(grep "broadcast pkts rx ok:" "$file_today" | sed 's/.*broadcast pkts rx ok://' | tr -d ' ' | head -n 1)

    # 통계값 추출 (droppedRx)
    dropped_rx_1=$(grep "droppedRx:" "$file_yesterday" | sed 's/.*droppedRx://' | tr -d ' ' | head -n 1)
    dropped_rx_2=$(grep "droppedRx:" "$file_today" | sed 's/.*droppedRx://' | tr -d ' ' | head -n 1)

    # 통계값 추출 (pktsRxBroadcast)
    pkts_rx_broadcast_1=$(grep "pktsRxBroadcast:" "$file_yesterday" | sed 's/.*pktsRxBroadcast://' | tr -d ' ' | head -n 1)
    pkts_rx_broadcast_2=$(grep "pktsRxBroadcast:" "$file_today" | sed 's/.*pktsRxBroadcast://' | tr -d ' ' | head -n 1)

    # 델타 계산 (broadcast pkts rx ok)
    if [[ "$broadcast_rx_ok_1" =~ ^[0-9]+$ ]] && [[ "$broadcast_rx_ok_2" =~ ^[0-9]+$ ]]; then
        delta_broadcast_rx_ok=$((broadcast_rx_ok_2 - broadcast_rx_ok_1))
    else
        delta_broadcast_rx_ok="N/A"
    fi

    # 델타 계산 (droppedRx)
    if [[ "$dropped_rx_1" =~ ^[0-9]+$ ]] && [[ "$dropped_rx_2" =~ ^[0-9]+$ ]]; then
        delta_dropped_rx=$((dropped_rx_2 - dropped_rx_1))
    else
        delta_dropped_rx="N/A"
    fi

    # 델타 계산 (pktsRxBroadcast)
    if [[ "$pkts_rx_broadcast_1" =~ ^[0-9]+$ ]] && [[ "$pkts_rx_broadcast_2" =~ ^[0-9]+$ ]]; then
        delta_pkts_rx_broadcast=$((pkts_rx_broadcast_2 - pkts_rx_broadcast_1))
    else
        delta_pkts_rx_broadcast="N/A"
    fi

    # vmnic5 통계 추출
    bytes_rx_1=$(awk '/NIC statistics for vmnic5/{flag=1} flag && /Bytes received:/{print $3; flag=0}' "$file_yesterday")
    bytes_rx_2=$(awk '/NIC statistics for vmnic5/{flag=1} flag && /Bytes received:/{print $3; flag=0}' "$file_today")
    bytes_tx_1=$(awk '/NIC statistics for vmnic5/{flag=1} flag && /Bytes sent:/{print $3; flag=0}' "$file_yesterday")
    bytes_tx_2=$(awk '/NIC statistics for vmnic5/{flag=1} flag && /Bytes sent:/{print $3; flag=0}' "$file_today")

    # 사용률 계산
    if [[ "$bytes_rx_1" =~ ^[0-9]+$ ]] && [[ "$bytes_rx_2" =~ ^[0-9]+$ ]] && [[ "$bytes_tx_1" =~ ^[0-9]+$ ]] && [[ "$bytes_tx_2" =~ ^[0-9]+$ ]]; then
        rx_diff=$((bytes_rx_2 - bytes_rx_1))
        tx_diff=$((bytes_tx_2 - bytes_tx_1))
        
        # 초당 바이트 수
        rx_bytes_per_sec=$((rx_diff / TIME_INTERVAL))
        tx_bytes_per_sec=$((tx_diff / TIME_INTERVAL))
        
        # Mbps로 변환
        rx_mbps=$((rx_bytes_per_sec * 8 / 1000000))
        tx_mbps=$((tx_bytes_per_sec * 8 / 1000000))
        
        # 사용률 계산
        rx_usage=$(echo "scale=2; ($rx_mbps / $MAX_BANDWIDTH) * 100" | bc)
        tx_usage=$(echo "scale=2; ($tx_mbps / $MAX_BANDWIDTH) * 100" | bc)
    else
        rx_usage="N/A"
        tx_usage="N/A"
    fi

    # 결과 저장
    results["${server}_broadcast pkts rx ok"]=$delta_broadcast_rx_ok
    results["${server}_droppedRx"]=$delta_dropped_rx
    results["${server}_pktsRxBroadcast"]=$delta_pkts_rx_broadcast
    results["${server}_vmnic5_rx_usage"]=$rx_usage
    results["${server}_vmnic5_tx_usage"]=$tx_usage
done

# Markdown 표 출력
echo "| 서버     | broadcast pkts rx ok | droppedRx | pktsRxBroadcast | vmnic5 Rx 사용률 (%) | vmnic5 Tx 사용률 (%) |"
echo "|----------|----------------------|-----------|-----------------|----------------------|----------------------|"
for server in "${servers[@]}"; do
    printf "| %-8s | %-20s | %-9s | %-15s | %-20s | %-20s |\n" "$server" "${results[${server}_broadcast pkts rx ok]}" "${results[${server}_droppedRx]}" "${results[${server}_pktsRxBroadcast]}" "${results[${server}_vmnic5_rx_usage]}" "${results[${server}_vmnic5_tx_usage]}"
done
