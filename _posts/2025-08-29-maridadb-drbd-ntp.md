---
title: "NTP 로그 및 구성 검증: chronyc 명령어 출력 분석"
date: 2025-08-29
tags: [ntp, chrony, vmware, network]
categories: [Howtos, NTP]
---

chronyc 명령어 출력 결과를 바탕으로, 각 필드의 의미를 자세히 설명하겠습니다. 설명은 chrony 공식 문서와 관련 자료를 기반으로 하며, 사실 검증을 위해 chrony 프로젝트의 공식 매뉴얼(예: chronyc(1) man page)을 참고했습니다. 각 값을 이해하기 쉽게, 실제 출력 예시를 들어 단계적으로 풀어 설명하겠습니다. chrony는 NTP 클라이언트/서버로, 시스템 클럭을 동기화하는 도구입니다. slew 모드(점진적 시간 조정)에서 동작할 때, 이러한 명령어는 NTP 서버의 상태, 오차, 안정성을 확인하는 데 유용합니다.

이 분석은 NTP 재선택 사건(예: 198.19.1.53으로 전환)이 네트워크 지연과 연관될 수 있음을 검증하는 데 초점을 맞춥니다. 값이 높거나 불안정하면 네트워크 문제(지연, 패킷 손실)를 의심할 수 있습니다.

### 1. chronyc sources 출력 분석
이 명령어는 chronyd가 현재 접근 중인 NTP 소스(서버) 목록과 상태를 보여줍니다. 출력은 각 소스의 품질과 동기화 상태를 한눈에 파악할 수 있게 합니다. chrony는 여러 소스 중 가장 신뢰할 수 있는 하나를 선택해 동기화합니다.

**출력 필드 상세 설명 및 이해 방법**:
- **MS (Mode/State)**: 소스의 모드와 상태를 나타냅니다.
  - '^' (서버 모드), '=' (피어 모드), '#' (로컬 참조 클럭)으로 모드 표시.
  - 상태: '*' (현재 동기화된 소스), '+' (선택된 소스와 결합 가능한 소스), '-' (제외된 소스), '?' (연결 끊김 또는 테스트 미통과), 'x' (falseticker, 다른 소스와 불일치), '~' (변동성 너무 큼).
  - 이해: '*'가 있는 소스가 주요 동기화 대상입니다. 만약 '?'나 'x'가 많으면 네트워크 문제나 잘못된 소스 설정을 의심하세요.
- **Name/IP address**: 소스의 이름 또는 IP 주소.
  - 이해: 목록에 있는 서버가 chrony.conf에 설정된 것입니다. IP가 실제로 접근 가능한지 확인하세요.
- **Stratum**: 소스의 stratum 레벨 (1: 로컬 클럭, 2 이상: 상위 서버로부터의 홉 수).
  - 이해: 낮을수록 (예: 2) 더 신뢰할 수 있습니다. 높은 stratum은 지연이 누적될 수 있음.
- **Poll**: 폴링 간격의 base-2 로그 (예: 10은 2^10=1024초 간격).
  - 이해: chrony가 자동으로 조정합니다. 높은 값은 안정적 소스, 낮은 값은 자주 확인 Needed.
- **Reach**: 도달 가능성 레지스터 (8비트 octal, 최대 377=11111111).
  - 이해: 최근 8번 전송 중 성공한 횟수. 377은 모두 성공, 낮으면 패킷 손실(네트워크 문제) 의심.
- **LastRx**: 마지막 샘플 수신 시간 (초 단위, m/h/d/y 접미사 가능).
  - 이해: 최근이면 소스가 활성, 오래되면 연결 문제.
- **Last sample**: 마지막 측정 오프셋 (브라켓 안: 실제 측정값, +/-: 오차 범위).
  - 이해: 음수(-)는 로컬 클럭이 느림, 양수(+)는 빠름. us/ms 단위로 작을수록 좋음. 큰 변동은 네트워크 지터(jitter)나 클럭 드리프트.

**제공된 출력 예시 해석**:
```
MS Name/IP address         Stratum Poll Reach LastRx Last sample
===============================================================================
^- prod-ntp-5.ntp4.ps5.cano>     2  10   377   397  -3878us[-3930us] +/-  126ms
...
^* time.ravnus.com               2  10   377   350   -705us[ -756us] +/- 5828us
...
```
- '*'가 time.ravnus.com에 있으므로 이 소스가 현재 동기화 대상 (재선택된 서버일 수 있음).
- 모든 Reach가 377: 최근 8회 모두 성공, 패킷 손실 없음. 하지만 과거 지연 사건 시 이 값이 떨어질 수 있음.
- Last sample: 대부분 us 단위로 작음 (예: -705us), 안정적. 그러나 any.time.nl의 +13ms는 큰 오프셋으로, 네트워크 지연 의심.
- 이해 팁: 만약 NTP 재선택(198.19.1.53)이 발생했다면, 이 출력에서 새 서버가 나타나고 오프셋이 초기화될 수 있습니다. 지연 원인으로, +/- 값이 ms 단위로 크면 네트워크 불안정.

**추가 확인 명령어**:
- `chronyc sources -v`: verbose 모드로 컬럼 설명 추가 출력 (초보자 추천).
- `chronyc ntpdata [소스 이름]`: 특정 소스의 상세 NTP 데이터 (예: remote addr, local addr, leap status, scores 등). 예: `chronyc ntpdata time.ravnus.com`으로 지연 원인(예: root delay) 확인.
- `chronyc activity`: 온라인/오프라인 소스 수 요약 (빠른 상태 체크).

### 2. chronyc sourcestats 출력 분석
이 명령어는 각 소스의 드리프트율(drift rate)과 오프셋 추정 프로세스 정보를 보여줍니다. chrony가 선형 회귀(linear regression)를 통해 클럭 오차를 예측하는 데 사용됩니다.

**출력 필드 상세 설명 및 이해 방법**:
- **Name/IP Address**: 소스 이름 (sources와 동일).
- **NP (Number of Points)**: 유지된 샘플 포인트 수 (선형 회귀에 사용).
  - 이해: 많을수록 (예: 64) 안정적 추정. 적으면 초기 단계 또는 샘플 삭제됨.
- **NR (Number of Runs)**: 마지막 회귀 후 동일 부호 잔차(residuals) 연속 수.
  - 이해: NP에 비해 낮으면 선형 적합 좋음. 높으면 드리프트 불안정, chrony가 오래된 샘플 버림.
- **Span**: 가장 오래된/새로운 샘플 간 간격 (초 단위, m/h/d/y 접미사).
  - 이해: 길수록 (예: 18h) 장기 추정 정확. 짧으면 최근 데이터만.
- **Frequency**: 추정된 잔여 주파수 (ppm, parts per million). 로컬 클럭이 소스 대비 느림/빠름.
  - 이해: 0에 가까울수록 좋음. 양수: 로컬 빠름, 음수: 느림.
- **Freq Skew**: 주파수 추정 오차 범위 (ppm).
  - 이해: 작을수록 (예: 0.044) 정확. 크면 불안정.
- **Offset**: 추정 오프셋 (us/ms 등).
  - 이해: 소스 대비 로컬 클럭 차이. 작을수록 동기화 좋음.
- **Std Dev (Standard Deviation)**: 샘플 표준편차.
  - 이해: 작을수록 (예: 1810us) 일관성 있음. 크면 지터나 노이즈.

**제공된 출력 예시 해석**:
```
Name/IP Address            NP  NR  Span  Frequency  Freq Skew  Offset  Std Dev
==============================================================================
prod-ntp-5.ntp4.ps5.cano>  64  38   18h     +0.025      0.045  -3021us  1989us
...
time.ravnus.com            33  17  552m     -0.001      0.070   -237ns   979us
...
```
- NP가 64인 소스들: 장기 데이터 축적, 안정적. time.ravnus.com은 33으로 최근 선택된 듯 (NTP 재선택 증거?).
- Frequency 대부분 +0.02x ppm: 로컬 클럭 약간 빠름, slew 모드로 조정 중.
- Std Dev us 단위: 대부분 안정, 하지만 any.time.nl의 +16ms Offset은 큰 편차로 네트워크 지연 가능성.
- 이해 팁: NTP 재설정이 왜 일어났는지? Freq Skew나 Std Dev가 높은 소스가 기존 서버라면, chrony가 더 나은 소스(낮은 skew)로 전환. 예: time.ravnus.com의 -0.001 ppm은 우수.

**추가 확인 명령어**:
- `chronyc sourcestats -v`: verbose로 컬럼 설명 추가.
- `chronyc selectdata`: 소스 선택 기준 상세 (예: combined offset, root distance). 재선택 이유(낮은 score 소스 제외) 확인.
- `chronyc serverstats`: chronyd 서버 통계 (NTP 패킷 수, 드롭 등). 클라이언트 요청 과부하나 지연 검출.

### 3. chronyc tracking 출력 분석
이 명령어는 시스템 클럭의 전체 성능 파라미터를 보여줍니다. chrony가 NTP 소스를 기반으로 로컬 클럭을 어떻게 추적하는지 요약합니다.

**출력 필드 상세 설명 및 이해 방법**:
- **Reference ID**: 현재 동기화된 소스의 ID와 이름/IP.
  - 이해: 동기화 대상 확인. 변경되면 재선택 발생.
- **Stratum**: 시스템의 stratum (참조 소스 +1).
  - 이해: 낮을수록 상위 계층.
- **Ref time (UTC)**: 마지막 참조 시간 (UTC).
  - 이해: 최신 동기화 시점.
- **System time**: NTP 시간 대비 로컬 시간 차이 (초).
  - 이해: 0에 가까울수록 좋음. slow/fast 표시.
- **Last offset**: 최근 오프셋 조정 (초).
  - 이해: slew 적용된 값. 작을수록 안정.
- **RMS offset**: 루트 평균 제곱 오프셋 (초).
  - 이해: 평균 오차. 낮을수록 정확.
- **Frequency**: 클럭 주파수 (ppm, slow/fast).
  - 이해: 로컬 클럭 드리프트율.
- **Residual freq**: 잔여 주파수 오차 (ppm).
  - 이해: 0에 가까울수록 좋음.
- **Skew**: 주파수 skew (ppm).
  - 이해: 주파수 추정 불확실성.
- **Root delay**: 루트 지연 (초, 왕복 시간).
  - 이해: 작을수록 (네트워크 지연 적음).
- **Root dispersion**: 루트 분산 (초, 오차 누적).
  - 이해: 낮을수록 신뢰성 높음.
- **Update interval**: 업데이트 간격 (초).
  - 이해: 자주 업데이트되면 불안정.
- **Leap status**: 리프 초 상태 (Normal: 정상).

**제공된 출력 예시 해석**:
```
Reference ID    : DD97764E (mail.pyeongga.com)
Stratum         : 3
Ref time (UTC)  : Fri Aug 29 00:01:41 2025
System time     : 0.000106650 seconds slow of NTP time
Last offset     : -0.000051298 seconds
RMS offset      : 0.000148047 seconds
Frequency       : 29.683 ppm slow
Residual freq   : -0.001 ppm
Skew            : 0.072 ppm
Root delay      : 0.006277970 seconds
Root dispersion : 0.000998642 seconds
Update interval : 1036.1 seconds
Leap status     : Normal
```
- Reference ID: mail.pyeongga.com (동기화 대상, 재선택된 서버?).
- System time: 0.000106650 초 slow – 매우 미세, slew 모드로 잘 조정 중.
- Frequency: 29.683 ppm slow – 로컬 클럭 느림, chrony가 보정.
- Root delay: 0.006초 (6ms) – 네트워크 지연 작음, 정상.
- 이해 팁: NTP 재설정 원인으로, Root delay나 dispersion이 과거 로그에서 높았을 수 있음. Skew 0.072 ppm은 낮아 안정적.

**추가 확인 명령어**:
- `chronyc makestep`: 강제 동기화 (테스트용, slew 무시).
- `chronyc offset`: 현재 오프셋만 확인 (빠른 체크).
- 로그 파일 확인: `/var/log/chrony/measurements.log` (상세 측정 로그, tail -f로 실시간 모니터링).

