# 대구 PPP 행정망 NAS NTP 동기화 방안 — 운영담당자 선택 가이드

> 실증 테스트 결과 기반의 4가지 방안 상세 분석 · 테스트 절차 · 적용 절차 포함

| 항목 | 내용 |
|------|------|
| **대상** | NetApp ONTAP NAS (대구 PPP 행정망) |
| **이슈** | 22분(1,320초) 시간 지연 |
| **영향 범위** | 11개 과제, 약 230대 서버 |
| **문서 버전** | Final v7.0 |

---

## 목차

1. [개요 및 방안 비교](#1-개요-및-방안-비교)
2. [기술 배경 및 실증 테스트 결과](#2-기술-배경-및-실증-테스트-결과)
3. [방안 A — local stratum + maxslewrate 400 + maxpoll 8](#3-방안-a--local-stratum--maxslewrate-400--maxpoll-8)
4. [방안 B — local stratum + maxslewrate 400 + tinker step 0](#4-방안-b--local-stratum--maxslewrate-400--tinker-step-0)
5. [방안 C — local stratum + maxslewrate 100 (ONTAP 설정 없음)](#5-방안-c--local-stratum--maxslewrate-100-ontap-설정-변경-없음)
6. [방안 D — 분할 step (60초 × 22회)](#6-방안-d--분할-step-60초--22회)
7. [의사결정 가이드](#7-의사결정-가이드)
8. [참고 문서](#8-참고-문서)

---

## 1. 개요 및 방안 비교

> **핵심 원리 — 왜 이 방안들이 작동하는가**
>
> 3차례 실증 테스트를 통해 확인된 핵심 사실은 두 가지입니다.
>
> **① local stratum**으로 외부 NTP 참조를 제거하면, 클라이언트(NAS)가 chrony 서버를 falseticker로 분류하지 않고 정상적으로 동기화합니다.
>
> **② maxslewrate**로 서버의 클럭 변화 속도를 제한하면, 클라이언트는 polling마다 128ms 이내의 작은 offset만 감지하여 step 없이 slew로 자연스럽게 따라옵니다.
>
> 4가지 방안은 이 두 원리의 조합과 ONTAP 설정 변경 필요 여부에 따라 구분됩니다.

### 1.1 방안 요약 비교

| 방안 | 점진성 | 예상 소요 | step 발생 | ONTAP 설정 변경 | NetApp 승인 | 권장 상황 |
|------|--------|-----------|-----------|-----------------|-------------|-----------|
| **A** — local stratum + maxslewrate 400 + maxpoll 8 | ✓ 진정한 slew | **38일** | 0회 | systemshell maxpoll 설정 | ⚠️ 필요 | 점진성 최우선, 승인 가능 시 |
| **B** — local stratum + maxslewrate 400 + tinker step 0 | ✓ 진정한 slew | **38일** | 0회 | systemshell tinker 설정 | ⚠️ 필요 | 점진성 최우선, maxpoll 설정보다 근본적 해결 |
| **C** — local stratum + maxslewrate 100 (ONTAP 무수정) | ✓ 진정한 slew | **153일** | 0회 | **없음** | ✅ 불필요 | ONTAP 변경 불가, 장기 운영 수용 시 |
| **D** — 분할 step (60초 × 22회) | ✗ 작은 step 22회 반복 | **11시간** | 22회 (각 60초) | **없음** | ✅ 불필요 | 빠른 해결, 고객 협의 완료 시 |

### 1.2 핵심 임계값 참조

| 값 | 설명 |
|----|------|
| **128ms** | ntpd step threshold — 이 이하만 slew |
| **1,000초** | ntpd panic threshold — NAS 현재 초과 중 |
| **300초** | CIFS Kerberos 허용 skew — 60초 step은 안전 |
| **1,024초** | ONTAP ntpd 기본 maxpoll — 방안 A/B의 변경 대상 |
| **83,333 PPM** | Linux chrony 기본 maxslewrate — 제한 필요 |
| **500 PPM** | Unix 커널 최대 slew rate — 절대 한계 |

---

## 2. 기술 배경 및 실증 테스트 결과

### 2.1 문제 구조

대구 PPP 행정망 NetApp ONTAP NAS의 시간이 현재 시간보다 22분(1,320초) 늦습니다. 이 차이는 ntpd의 panic threshold(1,000초)를 초과하므로 NAS 자체적으로 NTP 동기화를 거부하는 상태입니다. 문제의 원인은 시간이 갑자기 점프한 적이 없다는 점에서 장기간의 누적 drift로 추정됩니다.

### 2.2 실증 테스트 요약

| 차수 | 설정 | 서버 결과 | 클라이언트 결과 | 실패 원인 |
|------|------|-----------|-----------------|-----------|
| 1차 | `smoothtime 400 0.001` | 65,351 PPM으로 빠르게 보정 | 38분에 149초 추종 | smoothtime 자동 활성화 안 됨. 기본 보정 속도(83,333 PPM) 작동 |
| 2차 | `smoothtime + maxslewrate 400` (외부 NTP 참조) | 389 PPM으로 천천히 보정 | 시간 제자리, 오히려 뒤로 밀림 | **외부 NTP 참조 → root dispersion 비정상 → falseticker 분류** |
| 3차 | `local stratum 5`, `smoothtime 400 0.001`, `makestep 1 3`, `chronyc smoothtime activate` | — | `^~` → `^*` 전환 후 급격 추종 | `chronyc smoothing Active: No`. local stratum은 root dispersion 문제를 해결했으나 maxslewrate 없어 급격 보정 → 클라이언트 step 발동 |

> **3차 테스트의 결정적 단서**
>
> 3차 테스트에서 클라이언트가 `^~ → ^*`로 전환된 것은 **local stratum이 root dispersion 문제를 실제로 해결했음**을 증명합니다. 문제는 서버가 maxslewrate 없이 기본 속도(83,333 PPM)로 너무 빠르게 변화하여 클라이언트가 step을 발동한 것입니다. 따라서 `local stratum + maxslewrate` 조합이 핵심 해법입니다.

### 2.3 polling 간격이 중요한 이유 (방안 A/B 관련)

NTP.org 공식 문서에 따르면 ntpd의 polling 간격은 "jiggle 알고리즘"으로 자동 조정됩니다. 서버가 400 PPM으로 변화할 때, polling 간격이 길어질수록 클라이언트가 감지하는 offset이 커집니다.

```
클라이언트 감지 offset = maxslewrate(PPM) × polling 간격(초) × 10⁻⁶ × 1000 ms

400 PPM × 256초(maxpoll 8) = 102.4ms < 128ms → slew ✓
400 PPM × 512초(maxpoll 9) = 204.8ms > 128ms → STEP ✗
400 PPM × 1024초(기본 maxpoll) = 409.6ms > 128ms → STEP ✗
```

ONTAP ntpd의 기본 maxpoll은 1024초이므로, maxslewrate 400 PPM 적용 시 polling이 1024초까지 늘어나면 409.6ms의 offset이 발생하여 step이 발동됩니다. 이를 방지하는 방법이 방안 A(maxpoll 제한)와 방안 B(step 비활성화)입니다.

| polling 간격 | maxpoll 설정 | 변화량 (400 PPM) | step 여부 |
|-------------|-------------|-----------------|-----------|
| 64초 | minpoll 6 | ✅ 25.6ms | slew |
| 128초 | maxpoll 7 | ✅ 51.2ms | slew |
| 256초 | maxpoll 8 | ✅ 102.4ms | slew (방안 A 목표) |
| 512초 | maxpoll 9 | ❌ 204.8ms | STEP |
| 1024초 | maxpoll 10 (기본) | ❌ 409.6ms | STEP |

---

## 3. 방안 A — local stratum + maxslewrate 400 + maxpoll 8

> **local stratum 5 + maxslewrate 400 PPM + ONTAP maxpoll 8 설정**
> 소요: 약 38일 | step: 0회 | NetApp Support 승인 필요

### 방안 A 개요

chrony 서버에 `local stratum 5`와 `maxslewrate 400`을 설정하여 서버 클럭 변화 속도를 400 PPM으로 제한하고, ONTAP의 ntpd에 `maxpoll 8`(256초)을 설정하여 polling 간격이 길어져 step이 발동되는 것을 방지합니다.

| 지표 | 값 |
|------|----|
| 22분 보정 예상 소요 | **38일** |
| polling 256초 × 400 PPM | **102.4ms** (128ms 이내 ✓) |
| step 발생 횟수 | **0회** |
| ONTAP 설정 변경 방법 | **systemshell** |

### A-1. VM 사전 검증 절차

#### 환경 구성

- VM1: 임시 chrony NTP 서버 (외부 NTP 참조 없음)
- VM2: NAS 시뮬레이션 (ntpd, maxpoll 8 설정)

#### VM1 (chrony 서버) 설정

```bash
# /etc/chrony.conf 작성
# 외부 NTP 참조 없음 (server/pool 라인 없음)

local stratum 5       # root dispersion 정상화 핵심
manual                # chronyc settime 명령 허용
maxslewrate 400       # 서버 클럭 변화 속도 400 PPM으로 제한
makestep 0 0          # 서버 자체 step 완전 비활성화
driftfile /var/lib/chrony/drift
allow 0.0.0.0/0
logdir /var/log/chrony
log tracking measurements

# VM1 시간을 -22분으로 설정
date -s "$(date -d '22 minutes ago')"
systemctl restart chronyd

# 확인: root dispersion이 마이크로초 수준인지 확인
chronyc tracking
# → Root dispersion 항목이 0.000xxx seconds 수준이어야 함

# manual 모드 활성화
chronyc manual on
```

#### VM2 (NAS 시뮬레이션, ntpd) 설정

```bash
# /etc/ntp.conf 작성
server <VM1_IP> iburst minpoll 6 maxpoll 8   # maxpoll 8 = 256초 제한
driftfile /var/lib/ntp/drift

# VM2 시간을 -22분으로 설정
date -s "$(date -d '22 minutes ago')"
systemctl restart ntpd

# 5분 대기 후 확인
ntpq -pn
# 정상 출력 예시:
# *<VM1_IP>   .LOCL.   5 u   28   64  377   0.1   +25.6   0.05
#  ↑ 신뢰(*)            ↑st5        ↑ offset ~25ms (400 PPM × 64초)
```

#### 점진적 가속 스크립트 실행 (VM1에서)

```bash
#!/bin/bash
# /usr/local/bin/gradual_advance.sh
TOTAL_MS=1320000    # 22분 = 1,320,000ms
ADVANCE_MS=120      # 5분 × 400 PPM = 120ms
INTERVAL=300        # 5분 간격
DONE=0
LOG=/var/log/gradual_advance.log

echo "[$(date -Is)] 시작. 목표: ${TOTAL_MS}ms" >> $LOG
while [ $DONE -lt $TOTAL_MS ]; do
    NEW=$(date -d "+${ADVANCE_MS} milliseconds" "+%Y-%m-%d %H:%M:%S")
    chronyc "settime $NEW"
    DONE=$((DONE + ADVANCE_MS))
    echo "[$(date -Is)] +${ADVANCE_MS}ms | 누적: ${DONE}ms / ${TOTAL_MS}ms" >> $LOG
    sleep $INTERVAL
done
echo "[$(date -Is)] 완료" >> $LOG
```

#### 검증 모니터링 (VM2에서)

```bash
# step 발생 여부 실시간 감시 (절대 step 없어야 함)
journalctl -f -u ntpd | grep -i "step\|panic\|offset"

# 30분마다 누적 변화 기록
watch -n 1800 'date; ntpq -pn'

# 24시간 후 예상 보정량
# 400 PPM × 86400초 = 34.6초 — 이만큼 시간이 앞당겨졌으면 성공
```

#### 검증 성공 기준

| 항목 | 성공 기준 | 실패 시 대응 |
|------|-----------|-------------|
| `ntpq -pn` 첫 글자 | `*` 유지 (신뢰 상태) | VM1 allow 설정 및 방화벽 확인 |
| offset 절대값 | 항상 128ms 미만 | maxpoll을 7로 낮춤 |
| step 로그 | 발생 없음 | maxslewrate를 300으로 낮춤 |
| 24시간 후 보정량 | 약 34.6초 앞당겨짐 | cron 스크립트 및 drift 파일 확인 |

### A-2. ONTAP 실제 적용 절차

> ⛔ **사전 필수 조건**
>
> 아래 절차의 ONTAP systemshell 접근은 **NetApp Support 공식 승인 후 진행**해야 합니다. 승인 요청 시 다음 사항을 명시하십시오: "maxpoll을 8(256초)로 제한하여 점진적 시간 동기화를 진행하려 하며, systemshell에서 /etc/ntp.conf minpoll/maxpoll 옵션 추가를 요청합니다."

1. **11개 과제 고객 사전 통지** (작업 48시간 전)
   - "38일에 걸쳐 매 64~256초마다 최대 102ms의 미세한 시간 조정이 발생합니다. CIFS 인증 및 NFS I/O에는 영향이 없습니다."

2. **임시 chrony 서버 구축 및 방화벽 설정**
   - NAS IP 대역에서만 접근 가능하도록 제한. 다른 시스템이 이 서버를 NTP 소스로 참조하지 않도록 격리.

3. **chrony 서버 시간을 NAS 현재 시간(-22분)으로 설정**
   ```bash
   date -s "$(date -d '22 minutes ago')"
   systemctl restart chronyd
   chronyc manual on
   ```

4. **ONTAP에 임시 chrony 서버 등록**
   ```
   ::> cluster time-service ntp server create -server <chrony_IP> -version 4
   ::> cluster time-service ntp server show
   ```

5. **systemshell에서 maxpoll 설정 (NetApp 승인 후)**
   ```bash
   ::*> systemshell -node <node_name>
   # ntp.conf 편집
   sed -i 's|server <chrony_IP>.*|server <chrony_IP> iburst minpoll 6 maxpoll 8|' /etc/ntp.conf
   # 확인
   cat /etc/ntp.conf
   # ntpd 재시작
   service ntpd restart
   # 동기화 확인
   ntpq -pn
   # poll 컬럼이 64~256 범위인지 확인
   ```
   클러스터의 모든 노드에 동일하게 적용합니다.

6. **점진적 가속 스크립트 실행 (chrony 서버에서)**
   ```bash
   nohup /usr/local/bin/gradual_advance.sh &
   # 또는 cron에 등록
   # */5 * * * * /usr/local/bin/gradual_advance.sh --single-run
   ```
   nohup 또는 systemd service로 백그라운드 실행. 38일간 중단 없이 실행.

7. **모니터링**
   ```
   ::*> cluster time-service ntp status show
   ::*> systemshell -node <node> -command "ntpq -pn"
   # offset이 0으로 수렴하는 추세 확인
   ```

8. **완료 후 정상화**
   - 38일 후 chrony 서버 해제. ONTAP의 NTP 서버를 원래 운영 NTP 서버로 복원. ntp.conf의 maxpoll 설정 원복.

---

## 4. 방안 B — local stratum + maxslewrate 400 + tinker step 0

> **local stratum 5 + maxslewrate 400 PPM + ONTAP tinker step 0**
> 소요: 약 38일 | step: 0회 | NetApp Support 승인 필요 | 방안 A보다 근본적 해결

### 방안 B 개요

방안 A와 chrony 서버 설정은 동일합니다. 차이점은 ONTAP에서 maxpoll을 제한하는 대신, ntpd의 `tinker step 0`으로 **step 발동 자체를 비활성화**한다는 것입니다. polling 간격이 아무리 길어져도 클라이언트가 step을 발동하지 않으므로, maxpoll 설정이 불필요합니다.

> **방안 A vs 방안 B의 핵심 차이**
>
> **방안 A:** "polling 간격을 짧게 제한하여 offset이 128ms를 넘지 않게 함 → step 조건을 만족하지 못하게"
>
> **방안 B:** "step 발동 임계값을 비활성화 → polling 간격에 관계없이 항상 slew만 수행"
>
> 방안 B가 더 근본적인 해결책이며, 추가로 `tinker panic 0`을 적용하면 ntpd가 큰 offset에서도 종료되지 않습니다.

| 지표 | 값 |
|------|----|
| 22분 보정 예상 소요 | **38일** |
| polling 간격 | **무관** — step 비활성화로 안전 |
| step 발생 횟수 | **0회** |
| ONTAP 설정 변경 항목 | **tinker** |

### B-1. VM 사전 검증 절차

#### VM1 (chrony 서버) 설정 — 방안 A와 동일

```bash
# /etc/chrony.conf (방안 A와 동일)
local stratum 5
manual
maxslewrate 400
makestep 0 0
driftfile /var/lib/chrony/drift
allow 0.0.0.0/0
```

#### VM2 (NAS 시뮬레이션, ntpd) 설정 — 방안 A와 차이점

```bash
# /etc/ntp.conf (방안 A와 차이: maxpoll 없음, tinker step 0 추가)
server <VM1_IP> iburst    # minpoll/maxpoll 지정 없음 — 기본값 사용
tinker step 0             # step 완전 비활성화 (핵심)
tinker panic 0            # panic 비활성화 (22분 > 1000초 초과 대응)
tinker stepout 0          # stepout threshold 비활성화
driftfile /var/lib/ntp/drift

# VM2 시간을 -22분으로 설정
date -s "$(date -d '22 minutes ago')"
systemctl restart ntpd

# 확인 — polling이 기본값(1024초)으로 길어져도 step이 발생하지 않아야 함
ntpq -pn
# poll 컬럼이 1024여도 step 없으면 성공

# step 발생 여부 확인 (아무것도 출력되면 안 됨)
journalctl -u ntpd | grep -i step
```

#### 방안 B 전용 검증: polling 1024초 상황 시뮬레이션

```bash
# polling을 1024초로 강제 설정하여 방안 B의 핵심 특성 확인
# /etc/ntp.conf에서 maxpoll 10 추가 (방안 A와 반대 방향 테스트)
server <VM1_IP> iburst maxpoll 10  # 1024초 polling 강제
tinker step 0
tinker panic 0
driftfile /var/lib/ntp/drift

# 재시작 후 5~10분 대기
systemctl restart ntpd
sleep 600

# ntpq -pn에서 poll이 1024에 도달해도 step 미발생 확인
ntpq -pn
# 예상 출력:
# *VM1_IP   .LOCL.   5 u  900 1024  377   0.1  +409.6  0.05
#                              ↑          ↑ 409ms offset이지만 step 없음!
```

### B-2. ONTAP 실제 적용 절차

> ⛔ **사전 필수 조건**
>
> ONTAP systemshell 접근은 **NetApp Support 공식 승인 후** 진행합니다. 승인 요청 시: "ntpd tinker step 0 및 tinker panic 0을 /etc/ntp.conf에 추가하여 step 없는 점진적 시간 동기화를 진행하려 합니다."

1. **임시 chrony 서버 구축** (방안 A의 1~3단계와 동일)

2. **ONTAP에 임시 chrony 서버 등록**
   ```
   ::> cluster time-service ntp server create -server <chrony_IP> -version 4
   ```

3. **systemshell에서 tinker 설정 (NetApp 승인 후)**
   ```bash
   ::*> systemshell -node <node_name>

   # tinker 옵션 추가
   cat >> /etc/ntp.conf << 'EOF'
   tinker step 0
   tinker panic 0
   tinker stepout 0
   EOF

   # 확인
   grep tinker /etc/ntp.conf

   # ntpd 재시작
   service ntpd restart

   # 상태 확인 — poll 값에 관계없이 * 상태 유지 확인
   ntpq -pn
   ```
   클러스터의 모든 노드에 동일하게 적용합니다.

4. **점진적 가속 스크립트 실행** (방안 A의 6단계와 동일)

5. **완료 후 정상화**
   - 38일 후 NTP 서버 원복. systemshell에서 /etc/ntp.conf의 tinker 라인 제거 후 ntpd 재시작.
   ```bash
   ::*> systemshell -node <node_name>
   sed -i '/tinker/d' /etc/ntp.conf
   service ntpd restart
   ```

---

## 5. 방안 C — local stratum + maxslewrate 100 (ONTAP 설정 변경 없음)

> **local stratum 5 + maxslewrate 100 PPM — ONTAP 무설정 변경**
> 소요: 약 153일 | step: 0회 | NetApp 승인 불필요

### 방안 C 개요

ONTAP의 기본 maxpoll(1024초)에서도 안전하도록 maxslewrate를 **100 PPM**으로 낮춘 방안입니다. 이 값으로는 polling 1024초 기준 변화량이 102.4ms로 step threshold(128ms) 이내를 유지합니다. ONTAP에 대한 어떠한 설정 변경도 없이 적용 가능합니다.

```
안전 조건 검증: 100 PPM × 1024초 × 10⁻⁶ × 1000 = 102.4ms < 128ms ✓
보정 소요 시간: 1,320초 ÷ (100 × 10⁻⁶ 초/초) = 13,200,000초 = 약 153일
```

> **cron 가속과 maxslewrate의 관계**
>
> cron으로 chronyc settime을 호출하면 chrony 서버 시스템 시간에 offset이 발생하고, chrony는 이를 maxslewrate 한계 내에서 보정합니다. 따라서 **실질 보정 속도 = min(cron 목표 속도, maxslewrate)**입니다. cron을 아무리 빠르게 실행해도 실질 보정 속도는 maxslewrate를 초과하지 않습니다.
>
> 방안 C에서 cron은 5분마다 30ms를 가속합니다. 이는 100 PPM 속도와 정확히 대응합니다.

| 지표 | 값 |
|------|----|
| 22분 보정 예상 소요 | **153일** |
| polling 1024초 × 100 PPM | **102.4ms** (안전 ✓) |
| ONTAP 설정 변경 | **없음** |
| NetApp Support 승인 | **불필요** |

### C-1. VM 사전 검증 절차

#### VM1 (chrony 서버) 설정

```bash
# /etc/chrony.conf
local stratum 5
manual
maxslewrate 100       # 핵심: 1024초 polling에서도 102.4ms < 128ms 안전
makestep 0 0
driftfile /var/lib/chrony/drift
allow 0.0.0.0/0

date -s "$(date -d '22 minutes ago')"
systemctl restart chronyd
chronyc manual on
```

#### VM2 (NAS 시뮬레이션) 설정 — ONTAP 기본값 재현

```bash
# /etc/ntp.conf — maxpoll 설정 없음 (ONTAP 기본값 재현)
server <VM1_IP> iburst
driftfile /var/lib/ntp/drift
# tinker 설정 없음 — ONTAP 기본 동작 그대로

date -s "$(date -d '22 minutes ago')"
systemctl restart ntpd
```

#### 방안 C 전용 검증: maxpoll 1024초에서 step 없음 확인

```bash
# polling이 1024초까지 늘어나도 step이 발생하지 않는지 확인
# VM2 /etc/ntp.conf에 maxpoll 10(1024초) 추가하여 시뮬레이션
echo "server <VM1_IP> iburst maxpoll 10" > /etc/ntp.conf
systemctl restart ntpd

# 15분 대기 후 (polling이 1024초까지 확장될 시간)
sleep 900

# poll 컬럼 확인 — 1024에 도달해도 step 미발생 확인
ntpq -pn
# 예시: *VM1_IP   .LOCL.   5 u  800 1024  377   0.1  +102.4  0.05
#                                                  ↑ 102.4ms < 128ms → slew 유지!

# step 미발생 확인
journalctl -u ntpd | grep -i "step"
# → 아무 출력 없어야 성공
```

#### cron 가속 스크립트 (방안 C 전용)

```bash
#!/bin/bash
# /usr/local/bin/gradual_advance_C.sh
# 방안 C: 5분마다 30ms 가속 (100 PPM 대응)
TOTAL_MS=1320000
ADVANCE_MS=30       # 300초 × 100 PPM = 30ms
INTERVAL=300
DONE=0
LOG=/var/log/gradual_advance_C.log

echo "[$(date -Is)] 방안 C 시작 (100 PPM, 약 153일)" >> $LOG
while [ $DONE -lt $TOTAL_MS ]; do
    NEW=$(date -d "+${ADVANCE_MS} milliseconds" "+%Y-%m-%d %H:%M:%S")
    chronyc "settime $NEW"
    DONE=$((DONE + ADVANCE_MS))
    REMAIN_DAYS=$(echo "scale=1; ($TOTAL_MS - $DONE) / $ADVANCE_MS * $INTERVAL / 86400" | bc)
    echo "[$(date -Is)] +${ADVANCE_MS}ms | 누적: ${DONE}ms | 잔여: ~${REMAIN_DAYS}일" >> $LOG
    sleep $INTERVAL
done
```

### C-2. ONTAP 실제 적용 절차

1. **임시 chrony 서버 구축**
   ```bash
   # /etc/chrony.conf
   local stratum 5
   manual
   maxslewrate 100
   makestep 0 0
   driftfile /var/lib/chrony/drift
   allow <NAS_IP_대역>

   date -s "$(date -d '22 minutes ago')"
   systemctl restart chronyd
   chronyc manual on
   ```

2. **ONTAP NTP 서버 전환**
   ```
   ::> cluster time-service ntp server delete -server <기존_NTP_IP>
   ::> cluster time-service ntp server create -server <chrony_IP> -version 4
   ::> cluster time-service ntp server show

   # 5분 후 동기화 확인
   ::*> cluster time-service ntp status show
   ::*> systemshell -node local -command "ntpq -pn"
   # → * 상태이면 동기화 성립
   ```

3. **점진적 가속 스크립트 백그라운드 실행**
   ```bash
   nohup /usr/local/bin/gradual_advance_C.sh &
   # 또는 systemd service로 등록하여 안정적으로 운영
   ```

4. **모니터링 (주 1회 권장)**
   ```bash
   # NAS 현재 offset 확인
   ::*> systemshell -node local -command "ntpq -pn"

   # 로그 확인
   tail -20 /var/log/gradual_advance_C.log

   # 예상 주간 보정량: 400 PPM × 86400 × 7 = 약 242초/주
   ```

5. **완료 후 정상화 (153일 후)**
   ```
   ::> cluster time-service ntp server delete -server <chrony_IP>
   ::> cluster time-service ntp server create -server <운영_NTP_IP> -version 4
   ```

> ⚠️ **153일 운영 기간 중 고려사항**
>
> - 백업 timestamp는 153일에 걸쳐 점진적으로 정상화됨 (고객 사전 통지 필요)
> - SnapLock Compliance Clock 영향도 NetApp에 별도 확인
> - cron 스크립트가 153일간 안정적으로 실행되어야 함 (systemd service 등록 권장)
> - 정기 모니터링으로 step 미발생 확인 필수

---

## 6. 방안 D — 분할 step (60초 × 22회)

> **단계별 분할 step — 60초씩 22회, 11시간 내 완료**
> 소요: 약 11시간 | step: 22회 (각 60초) | ONTAP 설정 변경 없음 | NetApp 승인 불필요

### 방안 D 개요

NetApp 공식 명령 `cluster date modify`를 활용하여 22분(1,320초)을 60초 단위로 22회 분할하여 보정합니다. 각 step은 CIFS Kerberos 허용치(300초)의 1/5 수준으로, 인증 영향이 수학적으로 보장됩니다.

> ✅ **Kerberos 인증 안전성 수학적 보장**
>
> - CIFS Kerberos 기본 clock skew 허용치: **300초**
> - 1회 step 크기: **60초**
> - 60초 ÷ 300초 = 20% → Kerberos 허용치의 1/5 수준 → **인증 영향 없음이 수학적으로 보장**

| 지표 | 값 |
|------|----|
| 총 소요 시간 | **11시간** (30분 간격 × 22회) |
| step 발생 | **22회** (각 60초) |
| ONTAP 설정 변경 | **없음** |
| NetApp Support 승인 | **불필요** |

### D-1. 사전 준비

1. **11개 과제 고객 사전 통지** (작업 48시간 전)
   - "11시간에 걸쳐 30분마다 1분(60초)의 시간 조정이 22회 발생합니다. CIFS 인증에는 영향이 없으며, 백업 timestamp가 1분 단위로 점진적으로 정상화됩니다."

2. **작업 윈도우 선정**: 백업 작업이 없는 시간대 (예: 토요일 00:00~12:00)

3. **NetApp Support 핫라인 대기 합의**

4. **사전 상태 스냅샷**
   ```
   ::> cluster date show
   ::*> cluster time-service ntp status show
   ::*> systemshell -node local -command "ntpq -pn"
   # 결과를 파일로 저장
   ```

### D-2. 자동화 스크립트 (관리 서버에서 실행)

```bash
#!/bin/bash
# ontap_step_sync.sh
# ONTAP cluster date modify를 활용한 분할 step 자동화
# 실행 전: ONTAP CLI 접근 가능한 관리 서버에서 실행

ONTAP_IP="<ONTAP_MGMT_IP>"
ONTAP_USER="admin"
TOTAL_STEPS=22
STEP_SEC=60         # 1회 step 크기 (초)
INTERVAL_MIN=30     # step 간격 (분)
LOG=./step_sync.log

echo "[$(date -Is)] 분할 step 시작. ${TOTAL_STEPS}회 × ${STEP_SEC}초" | tee -a $LOG

for i in $(seq 1 $TOTAL_STEPS); do
    echo "" | tee -a $LOG
    echo "[Step $i/$TOTAL_STEPS] $(date)" | tee -a $LOG

    # 현재 ONTAP 시간 조회
    CURRENT=$(ssh ${ONTAP_USER}@${ONTAP_IP} "cluster date show" 2>/dev/null | grep -oP '\d{2}:\d{2}:\d{2}')
    echo "  현재 ONTAP 시간: $CURRENT" | tee -a $LOG

    # 60초 앞당긴 목표 시간 계산
    TARGET=$(date -d "$CURRENT +${STEP_SEC} seconds" "+%m/%d/%Y %H:%M:%S" 2>/dev/null)
    echo "  목표 시간 적용: $TARGET" | tee -a $LOG

    # cluster date modify 실행
    ssh ${ONTAP_USER}@${ONTAP_IP} "cluster date modify -date \"$TARGET\"" 2>&1 | tee -a $LOG

    # 적용 후 상태 확인
    echo "  적용 후 확인:" | tee -a $LOG
    ssh ${ONTAP_USER}@${ONTAP_IP} "cluster date show" 2>/dev/null | tee -a $LOG

    # EMS 로그에서 CIFS 인증 오류 확인
    ssh ${ONTAP_USER}@${ONTAP_IP} \
        "event log show -severity ERROR -time-range 1m -fields event -messagename secd*" \
        2>/dev/null | tee -a $LOG

    if [ $i -lt $TOTAL_STEPS ]; then
        echo "  ${INTERVAL_MIN}분 대기 중..." | tee -a $LOG
        sleep $((INTERVAL_MIN * 60))
    fi
done

echo "" | tee -a $LOG
echo "[$(date -Is)] 완료. 총 ${TOTAL_STEPS}회 × ${STEP_SEC}초 = $((TOTAL_STEPS * STEP_SEC))초 보정" | tee -a $LOG
```

### D-3. 수동 실행 (스크립트 미사용 시)

```
# 1. 현재 상태 확인
::> cluster date show
::*> cluster time-service ntp status show

# 2. NTP 서버 임시 제거 (step 시 NTP가 되돌리지 않도록)
::> cluster time-service ntp server delete -server <NTP_IP>

# 3. 60초씩 앞당기기 (22회 반복 — 30분 간격)
::> cluster date modify -date "MM/DD/YYYY HH:MM:SS"
#  └─ 현재 시간보다 60초 앞선 시각 입력

# 4. 각 step 후 즉시 확인
::> cluster date show
::> event log show -severity ERROR -time-range 2m
#  └─ secd.cifsAuth.problem 이벤트가 없어야 함

# 5. 22회 완료 후 NTP 서버 재등록
::> cluster time-service ntp server create -server <NTP_IP> -version 4
::*> cluster time-service ntp status show
#  └─ reach=377, offset이 0에 수렴하면 완료
```

### D-4. 각 step 후 체크리스트

| 확인 항목 | 명령 | 정상 기준 | 이상 시 대응 |
|----------|------|-----------|-------------|
| 시간 적용 확인 | `cluster date show` | 목표 시간과 일치 | 다시 modify 실행 |
| CIFS 인증 오류 | `event log show -messagename secd.cifsAuth*` | 이벤트 없음 | 즉시 중단, 고객 확인 |
| NFS lock 상태 | `vserver nfs locks show` | lock 정상 유지 | lock 재확인 후 계속 |
| Snapshot 정책 | `volume snapshot policy show` | 정책 변경 없음 | NetApp Support 문의 |
| SnapMirror 상태 | `snapmirror show -fields lag-time` | lag 정상 범위 | 관계 재동기화 |

### D-5. 이상 발생 시 롤백 방법

> ⛔ **step 도중 이상 발생 시 즉시 중단 기준**
>
> - CIFS 세션 대량 단절 (event log에 secd.cifsAuth.problem 다수 발생)
> - SnapMirror lag이 비정상적으로 증가
> - 고객 어플리케이션에서 시간 불일치 오류 보고

```bash
# 롤백: 현재까지 적용된 step만큼 되돌리기
# 예: 5회 step 후 중단 → 5분(300초)만큼 되돌리기

# 1. 현재 시간 확인
::> cluster date show

# 2. 300초 이전 시각으로 복원
::> cluster date modify -date "MM/DD/YYYY HH:MM:SS"
#  └─ 현재 시간보다 300초 뒤인 시각 입력

# 3. NTP 재등록하여 자동 안정화
::> cluster time-service ntp server create -server <NTP_IP> -version 4
```

---

## 7. 의사결정 가이드

### 7.1 상황별 권고 방안

| 상황 | 권고 | 이유 |
|------|------|------|
| 고객 중 단 1개라도 시간 점프(step) 절대 불가, NetApp 승인 가능 | **방안 A 또는 B** ⭐ 추천 | 진정한 slew, 38일 내 해결. B가 더 근본적 |
| 고객 중 단 1개라도 시간 점프(step) 절대 불가, NetApp 승인 불가 | **방안 C** | ONTAP 무변경, 153일 소요 — 장기 운영 수용 필수 |
| 모든 고객이 60초 단위 step 수용 가능, 빠른 해결 필요 | **방안 D** ⚡ 즉시 가능 | 11시간 내 완료, NetApp 공식 명령만 사용 |
| NetApp 승인 대기 중, 임시 조치 필요 | **방안 C 우선 적용** → 승인 후 방안 A/B로 전환 | C는 즉시 가능, A/B는 승인 후 전환 |

### 7.2 체크리스트 비교

| 확인 항목 | 방안 A | 방안 B | 방안 C | 방안 D |
|----------|--------|--------|--------|--------|
| 진정한 slew (step 없음) | ✅ | ✅ | ✅ | ❌ |
| ONTAP 설정 변경 없음 | ❌ | ❌ | ✅ | ✅ |
| NetApp 승인 불필요 | ❌ | ❌ | ✅ | ✅ |
| 30일 이내 완료 | ✅ (38일) | ✅ (38일) | ❌ (153일) | ✅ (11시간) |
| CIFS 인증 영향 없음 | ✅ | ✅ | ✅ | ✅ (60초 << 300초) |
| VM 사전 검증 가능 | ✅ | ✅ | ✅ | ✅ |
| NetApp 공식 명령만 사용 | ❌ | ❌ | ❌ (chrony 서버) | ✅ |

### 7.3 모든 방안 공통 적용 후 조치

1. **NTP 정상화 확인**
   - `::*> cluster time-service ntp status show` — 모든 노드 reach=377, offset 0에 근접

2. **근본 원인 조사**
   - hypervisor 시계 drift, NTP 서버 falseticker 이력, ntp.drift 파일 상태 점검

3. **재발 방지 SOP 추가**
   - 5분 이상 NTP skew 발생 시 알람. 주 1회 `ntpq -pn` 점검 자동화

---

## 8. 참고 문서

### NetApp 공식

1. [Can NTP time skew affect an ONTAP 9 system?](https://kb.netapp.com/on-prem/ontap/Ontap_OS/OS-KBs/Can_NTP_time_skew_affect_an_ONTAP_9_system)
2. [Is there any way to fix the NTP sync mode of ONTAP 9 to step or slew?](https://kb.netapp.com/onprem/ontap/os/Is_there_any_way_to_fix_the_NTP_sync_mode_of_ONTAP_9_to_step_or_slew)
3. [How to configure and troubleshoot NTP in ONTAP 9 using CLI](https://kb.netapp.com/on-prem/ontap/Ontap_OS/OS-KBs/How_to_configure_and_troubleshoot_NTP_in_ONTAP_9_using_CLI)
4. [Manage ONTAP cluster time](https://docs.netapp.com/us-en/ontap/system-admin/manage-cluster-time-concept.html)
5. [cluster date modify CLI reference](https://docs.netapp.com/us-en/ontap-cli/cluster-date-modify.html)
6. [cluster time-service ntp server modify CLI reference](https://docs.netapp.com/us-en/ontap-cli/cluster-time-service-ntp-server-modify.html)
7. [Resolving Skew Between Compliance Clock and System Clock](https://kb.netapp.com/on-prem/ontap/DP/SnapLock/SnapLock-KBs/Resolving_Skew_Between_Compliance_Clock_and_System_Clock)

### NTP / Chrony 공식

8. [chrony.conf(5) — maxslewrate, local, makestep, smoothtime](https://chrony-project.org/doc/4.3/chrony.conf.html)
9. [chronyc(1) — settime, smoothing, manual](https://chrony-project.org/doc/3.4/chronyc.html)
10. [NTP.org — Poll Process (jiggle 알고리즘)](https://www.ntp.org/documentation/4.2.8-series/poll/)
11. [NTP.org — How does it work?](https://www.ntp.org/ntpfaq/NTP-s-algo/)
12. [ntpd Miscellaneous Options — tinker step, panic](https://www.eecis.udel.edu/~mills/ntp/html/miscopt.html)
13. [RFC 5905 — NTPv4 Specification](https://www.ietf.org/rfc/rfc5905.txt)

### 운영 참고

14. [RHEL 10 — chrony isolated network configuration](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html/configuring_time_synchronization/using-chrony)
15. [How to change the NTP polling interval? (Red Hat)](https://access.redhat.com/solutions/39194)
16. [Avoiding clock drift on VMs (Red Hat)](https://www.redhat.com/en/blog/avoiding-clock-drift-vms)

---

*본 보고서는 3차례 실증 테스트 결과(2026-05-14, 2026-05-15)와 NetApp, chrony, NTP 공식 문서를 종합하여 작성되었습니다.*

*운영 환경 적용 전 VM 사전 검증을 반드시 수행하고, systemshell 접근이 필요한 방안(A/B)은 NetApp Support 공식 승인을 받으시기 바랍니다.*
