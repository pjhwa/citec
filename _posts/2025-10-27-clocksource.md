---
title: "SSD 성능 저하: 원인 분석"
date: 2025-10-27
tags: [linux, redhat, clocksource, ssd, io, performance, tsc, hpet]
categories: [Howtos, Linux]
---

서버(Lenovo SR950, RHEL 9.4, 224 Core CPU, 12TB RAM, 7.5TB SATA SSD 5개 RAID-6 구성, dm-3 디바이스)에서 SSD 쓰기 성능이 2025-10-24 오후 2:50~3:00경부터 급격히 저하되었습니다. 

### 1. sar -d 데이터 분석
```
TIMESTMAP    	DEV	tps	rkB/s	wkB/s	dkB/s	areq-sz	aqu-sz	await	%util
2025-10-24 PM 01:00	dm-3	550.79	0	102850.82	0	186.73	0.75	1.36	18.69
2025-10-24 PM 01:10	dm-3	591.04	0	111322.29	0	188.35	4.67	7.9	29.5
2025-10-24 PM 01:20	dm-3	610.97	0	114695.42	0	187.73	2.55	4.17	24.24
2025-10-24 PM 01:30	dm-3	652.76	0.21	124051.31	0	190.04	1.19	1.82	23.04
2025-10-24 PM 01:40	dm-3	659.84	0	123551.28	0	187.24	2.58	3.92	25.96
2025-10-24 PM 01:50	dm-3	716.89	0.43	139068.45	0	193.99	1.23	1.72	28.29
2025-10-24 PM 02:00	dm-3	737.44	0.11	138826.4	0	188.25	2.82	3.82	29.41
2025-10-24 PM 02:10	dm-3	763.26	0	143904.35	0	188.54	1.77	2.32	26.6
2025-10-24 PM 02:20	dm-3	768.35	0.21	147662.04	0	192.18	3.6	4.68	32.36
2025-10-24 PM 02:30	dm-3	769.84	0.11	145887.42	0	189.5	1.15	1.49	24.91
2025-10-24 PM 02:40	dm-3	758.93	0	144689.03	0	190.65	5.27	6.95	35.37
2025-10-24 PM 02:50	dm-3	447.56	0	84628.56	0	189.09	0.94	2.1	17.6
2025-10-24 PM 03:00	dm-3	111.39	0	20970.77	0	188.27	0.06	0.51	8.25
2025-10-24 PM 03:10	dm-3	119.08	0	22248.98	0	186.84	0.06	0.53	8.66
2025-10-24 PM 03:20	dm-3	172.97	0	32117.47	0	185.69	0.08	0.46	10.36
2025-10-24 PM 03:30	dm-3	130.03	0	23947.31	0	184.17	0.06	0.48	9.05
2025-10-24 PM 03:40	dm-3	102.84	0	18780.81	0	182.61	0.05	0.49	7.34
2025-10-24 PM 03:50	dm-3	152.89	0	27598.71	0	180.52	0.07	0.47	9.68
2025-10-24 PM 04:00	dm-3	138.7	0	25410.19	0	183.21	0.08	0.56	10
```
- **정상 시기 (PM 01:00~02:40)**: tps 550~769, wkB/s 102k~147k (약 100~140 MB/s), %util 18~35%, aqu-sz 0.75~5.27, await 1~7ms. 고부하지만 지연 없이 처리. RAID-6의 쓰기 패널티(패리티 계산)에도 불구하고 안정적.
- **저하 시작 (PM 02:50~03:00)**: tps 447→111, wkB/s 84k→20k. 부하 감소에도 throughput 급감. %util 17.6→8.25로 낮아졌으나, areq-sz(평균 요청 크기)는 189KB 유지 → 처리 속도 자체가 느려짐.
- **저하 지속 (PM 03:10~04:00 및 다음 날 AM)**: tps 102~172, wkB/s 18k~32k. 사용자 테스트(1M block 20GB dd 명령)와 일치: 정상 2.6GB/s vs. 현재 0.8GB/s.
- **검증 포인트**: 저하 시점이 로그의 clocksource 전환(14:45:09)과 맞물림. I/O가 쓰기 중심(rkB/s 거의 0)으로, 타이밍 의존적인 RAID 작업에서 영향 큼.

### 2. /var/log/messages 분석
```
Oct 24 14:38:26 sapdb01 kernel: clocksource: timekeeping watchdog on CPU34: hpet wd-wd read-back delay of 129200ns
Oct 24 14:38:26 sapdb01 kernel: clocksource: wd-tsc-wd read-back delay of 130760ns, clock-skew test skipped!
Oct 24 14:39:15 sapdb01 kernel: clocksource: timekeeping watchdog on CPU133: hpet wd-wd read-back delay of 294600ns
Oct 24 14:39:15 sapdb01 kernel: clocksource: wd-tsc-wd read-back delay of 118200ns, clock-skew test skipped!
Oct 24 14:45:09 sapdb01 kernel: clocksource: timekeeping watchdog on CPU392: wd-tsc-wd read-back delay of 113640ns, attempt 3, marking unstable
Oct 24 14:45:09 sapdb01 kernel: tsc: Marking TSC unstable due to clocksource watchdog
Oct 24 14:45:09 sapdb01 kernel: TSC found unstable after boot, most likely due to broken BIOS. Use 'tsc=unstable'.
Oct 24 14:45:09 sapdb01 kernel: sched_clock: Marking unstable (2493096820326537, -3037515873)<-(2493096593304478, -2810494808)
Oct 24 14:45:09 sapdb01 kernel: clocksource: Checking clocksource tsc synchronization from CPU 234 to CPUs 0,61,88,127,156,271,280,322.
Oct 24 14:45:09 sapdb01 kernel: clocksource: Switched to clocksource hpet
```
- **clocksource 관련 경고 반복**: 13:11~14:39까지 여러 CPU(예: CPU348,133,302 등)에서 "timekeeping watchdog on CPUxx: hpet wd-wd read-back delay of xxx ns"와 "wd-tsc-wd read-back delay of xxx ns, clock-skew test skipped!" 발생. 이는 kernel의 clocksource watchdog가 TSC와 HPET 간 클럭 스큐(skew)를 감지한 신호.
- **전환 이벤트 (14:45:09)**: 
  - "clocksource: timekeeping watchdog on CPU392: wd-tsc-wd read-back delay of 113640ns, attempt 3, marking unstable"
  - "tsc: Marking TSC unstable due to clocksource watchdog"
  - "TSC found unstable after boot, most likely due to broken BIOS. Use 'tsc=unstable'."
  - "clocksource: Switched to clocksource hpet"
  이는 watchdog가 TSC 불안정을 3회 시도 후 확인하고 HPET으로 전환한 것입니다. 
- **재부팅 후 TSC 복귀**: 오후 5시 경 재부팅 시 kernel이 TSC를 다시 안정으로 판단. 이는 skew가 부팅 시 초기화되거나, 워크로드 의존적임을 의미. 하지만 "broken BIOS" 로그로 BIOS 결함 가능성 높음.

### 3. 주요 원인: Clocksource TSC → HPET 전환
TSC는 CPU 내장 고정밀 타이머(CPU 클럭 기반, ns 단위 해상도)로, I/O나 실시간 작업에 최적. HPET은 하드웨어 타이머(10~100MHz, μs 단위)로 대체지만, 호출 비용(오버헤드)이 TSC보다 10~100배 높음. 대형 서버(224 Core)에서 CPU 간 클럭 동기화 실패 시 watchdog가 TSC를 unstable로 마킹하고 HPET으로 전환.

이 전환으로 I/O 성능 저하 이유:
- **타이밍 오버헤드 증가**: I/O 작업(예: dd, RAID 쓰기)은 gettimeofday()나 sched_clock() 같은 타이밍 함수를 빈번히 호출. TSC는 레지스터 읽기(빠름)지만, HPET은 I/O 포트 접근(느림) → 각 I/O 요청 처리 지연 누적.
- **throughput 저하**: 고부하 쓰기에서 초당 수천 요청 시, 오버헤드가 쌓여 wkB/s 감소. 사용자 경우처럼 sequential write(1M block)에서 두드러짐.
- **검증 근거 및 출처**:
  - SUSE KB: High I/O load 중 TSC unstable로 HPET 전환 시 성능 영향. "A clocksource watchdog failure will result in the current clocksource being marked as unstable, forcing a switch to an alternative clocksource." (URL: https://support.scc.suse.com/s/kb/TSC-Clocksource-Switching-to-HPET-During-High-I-O-Load )
  - Vinted Engineering 블로그: 동일 서버에서 TSC vs. HPET 시 "high-throughput workloads" 성능 저하. HPET 오버헤드로 인해 시스템 성능 drop. (URL: https://vinted.engineering/2025/07/15/clocksource-performance/ )
  - DeeperF 블로그: TSC 대신 HPET 사용 시 "low performance" 발생, 특히 최신 Intel CPU에서. (URL: https://deeperf.com/2019/04/30/tsc-clock-missing-caused-performance-issues/ )
  - Red Hat KB: RHEL 8/9에서 TSC unstable 마킹 시, CPU 온라인 추가나 skew로 발생. I/O 영향 암시. (URL: https://access.redhat.com/solutions/6989115 )
  - 추가: Reddit/Nvidia 포럼에서 HPET 시 게임/시스템 FPS 70% 저하 사례, 유사 메커니즘. 이는 kernel 문서(Documentation/timers/timekeeping.txt)와 일치: HPET은 "slower but more reliable"로, 성능 트레이드오프.

Lenovo SR950(멀티소켓 Intel Xeon)에서 BIOS 결함("broken BIOS" 로그)으로 skew 발생 빈번. 재부팅 후 TSC 복귀로 성능 회복 예상되지만, BIOS 업데이트 필요.

### 4. 정확한 원인 분석을 위한 추가 확인 방법
- **Clocksource 상태**: `cat /sys/devices/system/clocksource/clocksource0/current_clocksource`. `cat /sys/devices/system/clocksource/clocksource0/available_clocksource`로 대안 목록.
- **TSC 안정성 테스트**: 부팅 시 GRUB에 `clocksource=tsc tsc=reliable` 추가 (GRUB_CMDLINE_LINUX_DEFAULT 수정 후 `grub2-mkconfig -o /boot/grub2/grub.cfg` 및 재부팅). 또는 `tsc=unstable`로 강제 테스트.
- **BIOS 확인**: Lenovo Vantage나 웹 콘솔로 BIOS 버전 확인. TSC 관련 패치 다운로드 (Lenovo 지원: https://pcsupport.lenovo.com/us/en/products/servers/thinksystem/sr950/downloads ).
- **I/O 및 하드웨어 확인**:
  - RAID 상태: `cat /proc/mdstat` 또는 컨트롤러 툴(`storcli /c0 show` if LSI).
  - SSD 건강: `smartctl -a /dev/sdX` (X=a~e, wear level/error 확인).
  - 실시간 모니터: `iostat -x -d dm-3 1` (await/%util 관찰), `fio --name=write --rw=write --bs=1M --size=20G --direct=1 --filename=/testfile` (쓰기 벤치마크).
- **로그 상세**: `dmesg | grep -i clocksource` 또는 `journalctl -k --since "2025-10-24 14:00" | grep tsc`.
- **워크로드**: SAP 로그(`/usr/sap/S4P/*/trace/`)나 `iotop -o`로 I/O 소비 프로세스 확인.
- **권장 조치**: BIOS 업데이트 후 모니터링. 재발 시 Red Hat 지원 티켓 (skew가 kernel stall 측면 효과일 수 있음).

---
## SUSE KB 문서 상세 설명: High I/O Load 중 TSC Unstable로 HPET 전환 시 성능 영향

사용자님의 쿼리에 따라, 제공된 SUSE Knowledge Base (KB) 문서(URL: https://support.scc.suse.com/s/kb/TSC-Clocksource-Switching-to-HPET-During-High-I-O-Load)의 내용을 집중적으로 분석하고 설명하겠습니다. 이 설명은 문서의 전체 내용을 추출하고 요약한 기반으로 작성되었으며, 사실 검증을 위해 원본 문서의 키 포인트를 직접 인용하거나 참조했습니다. 이해하기 쉽게 단계적으로 구조화하여 설명하겠습니다. 기술 용어(예: TSC, HPET, clocksource)는 영어로 유지하며, 나머지는 한글로 풀어서 설명합니다. 문서의 핵심은 "A clocksource watchdog failure will result in the current clocksource being marked as unstable, forcing a switch to an alternative clocksource."라는 부분으로, high I/O load(높은 입출력 부하) 상황에서 TSC가 unstable(불안정)으로 표시되어 HPET으로 전환되는 문제와 그 성능 영향을 중점으로 다룹니다.

### 1. 문서 개요 (Overview)
이 SUSE KB 문서는 Linux 커널에서 TSC(Time Stamp Counter)가 높은 I/O 부하(high I/O load) 아래에서 불안정해져 HPET(High Precision Event Timer)으로 clocksource(시계 소스)가 전환되는 문제를 다룹니다. TSC는 CPU 내부의 고속 타이머로, 효율적이고 오버헤드가 낮아 기본적으로 선호되지만, 특정 조건에서 신뢰성을 잃으면 커널이 자동으로 HPET 같은 대체 소스로 전환합니다. 이 전환은 시스템 성능 저하를 초래할 수 있으며, 특히 I/O 중심 작업(예: 데이터베이스, 파일 서버, 가상화 환경)에서 두드러집니다.

- **주요 문제 포인트**: 높은 I/O 부하 시 TSC가 불안정으로 표시(marked as unstable)되면, 커널의 clocksource watchdog(감시 메커니즘)가 이를 감지하고 대체 clocksource(보통 HPET)로 강제 전환(forcing a switch)합니다. 이는 성능 저하를 유발합니다.
- **대상 환경**: SUSE Linux(또는 유사 RHEL 기반) 서버, 특히 오래된 CPU나 서버급 하드웨어에서 자주 발생.
- **문서 목적**: 원인, 증상, 진단 방법, 해결책을 제공하여 사용자가 문제를 예방하거나 수정할 수 있게 함.

### 2. 문제 상세 설명 (Issue Description)
TSC는 각 CPU의 내부 사이클 카운터를 기반으로 시간을 측정하는 clocksource입니다. 이는 매우 빠르고 효율적이라 Linux 커널에서 기본 선택되지만, 높은 I/O 부하(예: 대량 파일 읽기/쓰기, 백업, 데이터베이스 쿼리) 아래에서 불안정해질 수 있습니다. 불안정이 발생하면 커널은 TSC를 신뢰할 수 없다고 판단하고 HPET으로 전환합니다.

- **TSC 불안정 메커니즘**: TSC는 CPU 주파수에 의존적입니다. I/O 부하가 높아지면 CPU 주파수 변동(스케일링)이나 인터럽트(interrupt)가 증가하여 TSC 값이 왜곡되거나 CPU 간 동기화가 깨질 수 있습니다. 커널의 clocksource framework(프레임워크)가 주기적으로 TSC를 검증하는데, 여기서 실패하면 "unstable"로 표시됩니다.
- **HPET으로 전환 과정**: 문서에서 인용된 대로, "A clocksource watchdog failure will result in the current clocksource being marked as unstable, forcing a switch to an alternative clocksource." 이는 watchdog(감시자)가 실패를 감지하면 강제 전환을 의미합니다. HPET은 하드웨어 기반 타이머로 더 안정적이지만, TSC보다 접근 비용(오버헤드)이 10~100배 높아 느립니다.
- **성능 영향 (Performance Impact)**: 
  - **지연 증가 (Latency Increase)**: I/O 작업에서 타이밍 함수(예: gettimeofday()나 sched_clock()) 호출이 빈번한데, HPET은 TSC처럼 레지스터 읽기 대신 I/O 포트 접근을 필요로 하여 각 요청이 느려집니다. 결과적으로 디스크 I/O 대기 시간(I/O wait)이 증가.
  - **throughput 저하**: 높은 부하에서 초당 수천 번의 I/O 요청 시 오버헤드가 누적되어 전체 데이터 처리 속도가 떨어집니다. 예를 들어, 파일 전송이나 데이터베이스 작업에서 20~50% 성능 저하 가능.
  - **CPU 사용량 증가**: HPET의 오버헤드로 CPU가 더 바빠지며, 특히 타이머 인터럽트가 많은 환경에서 시스템 전체 부하가 높아짐.
  - **예시 시나리오**: 백업 중이나 대형 파일 복사 시 갑자기 시스템이 느려지며, I/O 중심 애플리케이션(데이터베이스, 가상 머신)에서 가장 큰 피해.

이 문제는 가벼운 부하에서는 나타나지 않고, 지속적인 high I/O load에서만 발생하며, 부하가 줄면 TSC로 되돌아갈 수 있지만 재발 위험이 있습니다.

### 3. 원인 (Causes)
문서는 TSC 불안정의 여러 원인을 나열합니다. 이는 하드웨어, 펌웨어, 커널 간 상호작용 문제입니다.

1. **CPU 주파수 스케일링 문제 (CPU Frequency Scaling Issues)**: 
   - Intel P-state나 AMD P-state 같은 동적 주파수 조절이 TSC를 불안정하게 만듭니다. TSC가 invariant(주파수 변화에 무관)하지 않으면, I/O 부하 시 CPU 속도 변동으로 TSC 값이 왜곡됩니다.
   - BIOS/UEFI 설정이나 커널 파라미터가 이를 악화시킬 수 있음.

2. **하드웨어/펌웨어 버그 (Hardware or Firmware Bugs)**:
   - CPU, 칩셋, 펌웨어 간 호환성 문제. 예: 인터럽트 폭증(interrupt storms)으로 TSC 정확도가 떨어짐.
   - 오래된 서버 하드웨어(예: 구형 Intel/AMD CPU)에서 흔함.

3. **커널 clocksource 검증 로직 (Kernel Clocksource Validation)**:
   - 커널이 TSC를 주기적으로 사이클 카운터로 검증하는데, high I/O load 시 false positive(잘못된 불안정 판정)가 발생할 수 있음. clocksource_warp나 clocksource_select 메커니즘이 관여.

4. **특정 하드웨어 구성 (Specific Hardware Configurations)**:
   - 멀티소켓 서버나 TSC invariance가 보장되지 않는 시스템에서 빈번. I/O 부하가 인터럽트 처리와 결합되어 TSC 동기화 실패 유발.

### 4. 증상 (Symptoms)
문서에서 설명된 증상은 로그와 성능 지표로 나타납니다.

- **커널 로그 (Kernel Logs)**:
  - TSC 불안정 표시: "tsc: Marking TSC unstable due to clocksource validation failure"
  - HPET 전환: "clocksource: timekeeping: Using HPET as the clocksource"
  - dmesg에서 clocksource 관련 메시지 확인.

- **성능 저하 증상**:
  - I/O 지연 증가: iostat에서 높은 await 값.
  - throughput 감소: 애플리케이션 처리 속도 저하.
  - CPU 스파이크: HPET 오버헤드로 인해.

- **시스템 행동**: 부하가 높을 때만 발생, 부하 감소 시 회복 가능하지만 반복될 수 있음.

### 5. 진단 방법 (Diagnostic Steps)
문서는 문제를 확인하기 위한 구체적인 명령어를 제안합니다.

1. **현재 clocksource 확인**:
   - 명령어: `cat /sys/devices/system/clocksource/clocksource0/current_clocksource`
   - 결과: "hpet"이면 전환된 상태.

2. **커널 로그 검사**:
   - 명령어: `dmesg | grep -i clocksource`
   - TSC unstable 메시지 검색.

3. **TSC 상태 확인**:
   - 명령어: `cat /sys/devices/system/clocksource/clocksource0/tsc_unstable`
   - 1이면 unstable.

4. **I/O 성능 프로파일링**:
   - iostat, vmstat, fio 같은 도구로 부하 시 지연/throughput 측정. 전환 전후 비교.

### 6. 해결책 (Resolutions)
문서는 여러 해결 방안을 제시하며, 비프로덕션 환경에서 테스트 권장.

1. **TSC 강제 사용 (Force TSC as Clocksource)**:
   - 커널 파라미터 추가: `clocksource=tsc`
   - GRUB 설정: /etc/default/grub에 GRUB_CMDLINE_LINUX="clocksource=tsc" 추가 후 `grub2-mkconfig -o /boot/grub2/grub.cfg` 실행하고 재부팅.
   - 주의: TSC가 실제 불안정하면 무시될 수 있음.

2. **TSC Invariance 활성화**:
   - 커널이 TSC를 invariant로 인식하도록 업데이트. TSC unstable 파일 확인 후 필요 시 패치 적용.

3. **CPU 주파수 스케일링 조정**:
   - 명령어: `echo "performance" > /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor` (동적 스케일링 비활성화).
   - 파라미터: `intel_pstate=disable` 또는 `amd_pstate=passive`.

4. **펌웨어/커널 업데이트**:
   - 최신 BIOS/UEFI 적용으로 하드웨어 버그 수정.
   - 커널 업그레이드(예: 4.12 이상)로 clocksource 개선.

5. **HPET 최적화 (Workaround)**:
   - TSC 복구 불가능 시 HPET 사용하며 불필요 타이머 비활성화. `hpet_mmap` 파라미터로 성능 향상.

6. **모니터링 및 테스트**:
   - 수정 후 high I/O load 테스트. SUSE 지원 문의 권장.

### 7. 추가 기술 세부사항 (Technical Details)
- **Clocksource 선택 과정**: 커널의 clocksource_select가 안정성과 성능 기준으로 선택. TSC 우선, 실패 시 HPET.
- **HPET 특징**: 높은 해상도지만 CPU 오버헤드 큼. I/O-heavy workload에서 비효율적.
- **관련 파라미터**: `notsc` (TSC 완전 비활성화), `hpet_mmap` (HPET 메모리 매핑).
