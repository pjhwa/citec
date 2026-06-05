이 plist-sz 패턴이 그림을 크게 바꿉니다. 한 가지 확인하고 종합하겠습니다 — 09:42 전후 messages에 JVM 사망/킬/코어 흔적이 있는지.messages에 09:42~09:55 사이 **kill·core·CRASH·oom·segfault·watchdog 동작 흔적이 전혀 없습니다.** 09:40 WatchDog.sh는 매분 도는 정기 크론일 뿐입니다. 그리고 사건 직전 plist-sz 12.6~12.7k는 **복구 후 정상 스냅샷(12,630)과 사실상 동일**합니다. 이 두 가지가 결론을 다시 한 번 조정합니다.

---

## plist-sz가 말해주는 것 — 그리고 내 이전 프레임의 수정

**확정된 사실 (확신도: High)**
- 09:42 12.7k → 09:43 **8.02k, 약 4,680개 태스크가 한 인터벌에 소멸.** 이는 **1,061스레드 JVM ≈ 4개분(4×1061=4,244) + 보조 스레드**와 정확히 맞습니다.
- 독립 증거 3개가 같은 사건을 가리킵니다: ⒜ plist-sz 4,680 급감, ⒝ 6개 중 **4개 JVM의 STIME=May29(재기동됨)**, ⒞ 09:55 swap 스파이크(=재기동). → **09:42~43에 무거운 JVM 4개가 죽었고, 09:55에 되살아났다.** 이게 장애 본체입니다.

**여기서 내 이전 가설을 수정합니다 (중요).**
직전 답변에서 저는 "fork storm이 카운트를 천장(10240)까지 밀어올려 터졌다"고 했습니다. **plist-sz 데이터는 이걸 지지하지 않습니다.**
- 사건 직전 카운트는 **천장으로 상승한 게 아니라 정상치(12.7k=평상 스냅샷과 동일)에서 평탄**하다가 **붕괴**했습니다.
- 즉 "수 분에 걸쳐 카운트가 한도까지 차오르는" 그림은 **분 단위 샘플에서 보이지 않습니다.** 제 "ceiling까지 net 상승" 서술은 과했습니다. 철회합니다.

다만 분 단위 샘플은 **초 단위 버스트를 못 잡습니다**(proc/s 4,240/s churn 존재). 그래서 plist-sz는 "수 분짜리 지속 상승"은 반증하지만, "1분 내 순간 버스트로 10,240 터치"는 **반증도 입증도 못 합니다.**

---

## 다시 정리한 RCA

**장애 본체 (확신도: High)**
5/29 09:38경 읽기 중심 부하 스파이크(388MiB/s, 쓰기≈0) + 태스크 churn 급증(proc/s 4,240/s) → 09:41 cswch 정점(221K) 후 → **09:42~43 무거운 JVM 4개 사망(plist-sz 4,680 급감)** → 09:55 재기동. messages에 커널 레벨 사망 흔적 없음 → **OS가 죽인 게 아니라 JVM이 스스로 죽었거나 부모 스크립트가 종료**시킨 패턴.

**근본 배경 (확신도: High)**
spinadm 한 UID에 38개 JVM(6개가 1,061스레드)이 몰려 **평상시에도 9,657/10,240(94%)**. 카운트가 정상이어도 천장과 580스레드밖에 안 떨어져 있는 만성 취약 구조. 이건 plist-sz가 정상이었다는 사실과 모순되지 않습니다 — **정상=이미 94%**이기 때문입니다.

**직접원인(errno 레벨) — 두 가설이 진짜로 갈립니다. 미확정 (확신도: 둘 다 Moderate)**

| | H1: nproc EAGAIN (errno 11) | H2: 메모리압 ENOMEM (errno 12) |
|---|---|---|
| 메커니즘 | 94% 베이스라인 + 09:38 스파이크가 580 여유를 **초 단위 버스트로 소진** → clone EAGAIN | 사건 중 **free 792MB·avail 0·direct reclaim 폭주**(1차 SAR) 상태에서 clone의 **커널스택(order-2, swap불가) 할당 실패** |
| 지지 증거 | 만성 94%, proc/s churn | 1차 SAR의 99.9%·792MB·pgscand 114K, 읽기 388MiB/s가 캐시 잠식 |
| 약점 | 분단위 plist-sz가 천장 근처를 안 보임(버스트 가정 필요) | 회수가능 캐시 460GB+ 존재, page alloc failure 미기록(단 억제 가능) |

**제가 직전에 H2(메모리)를 너무 일찍 죽인 것도 정정합니다.** 그건 복구 후 28% 스냅샷에 근거한 판단이었는데, **사건 당시는 free 792MB**였습니다. 커널스택 ENOMEM은 OOM-killer 없이도 발생하므로, "oom-killer 0건"이 H2를 완전히 배제하지 못합니다.

**배제 유지 (확신도: High):** swap 부족(thread 한도·메모리와 무관, 평탄), NOFILE(max 831), pid_max/threads-max, 그리고 외부 kill/segfault/OOM-killer(messages 무흔적).

---

## 결론적으로 — 데이터로 갈 수 있는 끝

이 sosreport(사건 3일 후 스냅샷) + 요약 SAR로 **확정 가능한 것**: 장애 본체(JVM 4개 09:42~43 사망→09:55 재기동), 만성 nproc 94% 취약 구조, 그리고 swap·물리OOM·NOFILE 배제.

**확정 불가한 것**: "cannot create native thread"의 **errno가 11(nproc)인지 12(메모리)인지.** plist-sz는 이걸 못 가립니다(분 단위 한계 + 정상치 붕괴 패턴은 양쪽 모두와 호환).

**이 하나로 끝나는 단서 (이제 진짜 마지막):**
1. **`hs_err_pid<pid>.log`** (HeapDumpPath=/securepin/log/PLG1 근처/같은 로그 디렉터리) — 그 안의 `OutOfMemoryError: unable to create new native thread` 줄과 **`(errno=11, Resource temporarily unavailable)`**(→H1) vs **`(errno=12, Cannot allocate memory)`**(→H2). 09:42 타임스탬프.
   - 참고: HeapDumpOnOutOfMemoryError가 켜져 있는데 사건 구간 **로컬 쓰기 I/O가 3.58MiB/s뿐** → 5~10GB 힙덤프가 로컬에 안 떨어졌습니다. /securepin이 **NFS면 덤프가 네트워크로 나가 로컬 writeB/s에 안 잡힘**(이 서버 NFS 비중 큼) → 덤프 존재 여부는 NFS 마운트 확인 필요.
2. 보조: 1차 SAR의 **kbmemfree 792MB 시각이 09:42와 일치하는지** + 같은 구간 **`sar -u` %iowait**. iowait가 09:41~42에 치솟았으면 H2(메모리압/회수정체) 쪽 가중.

errno 한 줄만 주시면 H1/H2를 닫습니다. 그 전까지는 **장애 본체·구조적 원인은 확정, 직접 트리거의 errno 분기는 미확정**이 정직한 상태입니다.
---
```
Load-runq/plist: plist-sz는 09:42에 12.7k -> 09:43에 8.02k로 급감 
Name	Mean	Max	Min
blocked PDBEAL01SL
0.0214	1	0
plist-sz PDBEAL01SL
12.4 K	12.7 K	7.97 K
runq-sz PDBEAL01SL
8.06	46	2
```

맞습니다. Ansible는 하나의 후보일 뿐인데 제가 거기 매달렸고, 더 근본적으로 **스냅샷이 사건 중인지 후인지조차 검증 안 한 채** 결론을 쌓았습니다. 전체를 다시 보겠습니다 — 특히 1번째 SAR(메모리 99.9%)와 이 파일들(28%)의 모순부터.STIME 컬럼을 잘못 집었습니다(14번). 스냅샷 시점과 6개 과다-스레드 JVM의 기동시각을 정확히 보겠습니다 — 이게 "전체 시간대" 판단의 핵심입니다.전체를 다시 보니 **제가 쌓아온 전제 하나가 틀렸습니다.** 스냅샷은 사건 당시가 아니라 **사건 3~4일 후(약 6/2)** 의 것입니다. 이걸 모르고 "9,657 = 사건 시점 스레드 수"처럼 다뤘는데, 그건 **복구된 평상 상태**였습니다. 이 정정을 반영해 처음부터 다시 정리합니다.

---

## A. 먼저 — 이번에 드러난 두 가지 정정

**정정 1 — 스냅샷 시점 (확신도: High)**
- 프로세스 STIME에 May29, May31, Jun01, Jun02, 그리고 당일 시계(11:08, 11:09)가 섞여 있고, messages 로그는 **Jun 1 03:46에서 끝납니다.** → sosreport 수집은 **6/2 전후**. 사건(5/29)보다 **3~4일 뒤**입니다.
- 따라서 `free`(28%)·`meminfo`(avail 474GB)·스레드 9,657은 전부 **복구 후 정상치**이지 사건 순간 값이 아닙니다. 제가 이걸 사건 값처럼 쓴 건 오류였습니다.

**정정 2 — 1호기 "99.9%" vs 이 파일 "28%" 모순 해소 (확신도: High)**
- 둘 다 같은 호스트 **PDBEAL01SL**입니다. 모순이 아니라 **시점 차이**입니다: 사건 중(5/29 09:3x) memused 99.9%·free 792MB → 복구 후(6/2) 28%·free 31GB. 즉 **1호기 = 이 AP 서버 = PDBEAL01SL** 한 대의 두 시점입니다. 메시지 3의 "29%"는 사건값이 아니라 복구 스냅샷을 읽으신 겁니다.

---

## B. 검증된 사실 (스냅샷·로그 기반, 확신도 High)

| 항목 | 값 |
|---|---|
| 서버 | PDBEAL01SL, 640GB RAM, DB 암호화 AP (KSign SPIN) |
| JVM | `com.ksign.spin.server.SPINServer` **38개 인스턴스**, 각 `-Xmx10240M`, JDK 1.8.0_51 |
| 스레드 분포 | **6개 JVM이 ~1,061 스레드**(전체의 66%), 나머지 32개는 72~167 |
| spinadm UID 스레드 합 | **9,657 / nproc 10,240 = 94%** (복구 후 평상치) |
| 6개 중 4개 | STIME=**May29** → 5/29에 재기동됨(09:55 리스타트와 부합, 부분 재기동) |
| 6개 중 2개 | STIME=Apr19 → 재기동 안 됨 |
| oom-killer / page alloc failure | messages 전체 **0건** |
| 최대 오픈 FD/프로세스 | 831 (NOFILE 10240 무관) |
| pid_max=120000, overcommit 미설정(기본0), swappiness=30 | — |
| 사건 지표(5/29) | 읽기 388MiB/s·쓰기≈0(09:38~50), proc/s max 4,240, cswch 09:41 221K→50K 붕괴, swap 평탄 |

**핵심 관찰:** Apr19 기동분과 May29 기동분이 **똑같이 1,061**에 모여 있습니다. 만약 스레드 누수라면 40일 된 Apr19분이 3일 된 May29분보다 훨씬 많아야 하는데 같습니다 → **1,061은 누수가 아니라 부하/설정에 의한 안정 운영 수준(plateau)** 으로 봐야 합니다. (제 이전 "스레드 leak" 추정 약화)

---

## C. 근본원인 분석 (계층 분리)

**① 근본원인 (Root) — 구조적 nproc 과다구독 (확신도: High)**
한 UID(spinadm) 아래 38개 JVM, 그중 6개가 1,061 스레드씩 → **평상시조차 9,657/10,240(94%)**. 즉 이 서버는 **상시 ~580 스레드 여유밖에 없는 절벽 끝에서 운영**됩니다. 스냅샷이 사건 후 평상치인데도 94%라는 게 결정적입니다 — 사건 때문에 높아진 게 아니라 **원래 그렇게 위태롭게 설계/구성**되어 있습니다. 이게 진짜 원인입니다.

**② 직접원인 (Proximate) — 부하 스파이크가 천장 돌파 (확신도: Moderate)**
5/29 09:38경 **읽기 지배 워크로드 스파이크**(388MiB/s, 쓰기≈0)와 **태스크 생성 폭주**(proc/s 4,240/s)가 겹치며 스레드 수가 평상 베이스라인 위로 밀려 **10,240 돌파 → `clone()` EAGAIN → "unable to create native thread"**. **09:41 cswch 붕괴(221K→50K)** 가 신규 스레드 생성이 막혀 시스템이 스톨한 순간으로 보입니다. (Moderate인 이유: 사건 시점 실제 스레드 수와 errno를 아직 못 봄)

**③ 트리거 (Trigger) — 미확정 (확신도: Low)**
읽기 388MiB/s·쓰기0은 **대량 읽기/스캔성 작업**에 부합하나, 그게 암호화 요청 폭증인지·배치인지·점검 스캔인지 **단정 불가**. 09:38 Ansible는 동시간 후보 중 하나일 뿐이며 **여기에 매몰되지 않겠습니다**(지적 반영). proc/s·cswch는 전역값이라 폭주 주체가 JVM인지 타 작업인지 못 가립니다.

**④ 동반증상 (Co-symptom), 원인 아님 — 메모리 (확신도: High)**
사건 중 memused 99.9%·free 792MB는 사실이나, ⒜ 464~513GB가 page cache(회수 가능), ⒝ **oom-killer·alloc failure 0건**. 진짜 고갈이면 fork storm 중 OOM-killer가 떴어야 합니다. → 메모리 압박은 같은 스파이크의 **병행 증상**이지 native thread 실패의 직접 원인이 아닙니다. swap은 thread 한도와 무관하고 사건 중 평탄했으므로 **완전 무관**.

---

## D. 배제된 가설 (확신도 High)

- 물리 메모리 고갈로 인한 OOM → ✗ (oom-killer 0)
- swap 부족 → ✗ (swap 평탄, count 한도와 무관)
- 열린 파일(NOFILE) 한도 → ✗ (max 831/10240)
- pid_max / threads-max → ✗ (전역 12,630 « 120,000)
- 사용자의 1·2차 결론("100% 갔다→swap→지연→OOM" / "Memory밖에 없다") → ✗ 둘 다 물리/swap 프레임이 틀림. 실제는 **nproc count 한도**.

---

## E. 닫지 못한 불확실성 (정직하게)

1. **JVM 실제 errno를 아직 못 봤습니다.** EAGAIN(11)이면 위 진단 확정 / ENOMEM(12)이면 max_map_count(기본 65530)·heuristic overcommit(Committed_AS 398GB > CommitLimit 351GB) 재검토 필요. → `hs_err_pid*.log` 또는 stdout.
2. **사건 시점 실제 스레드 수 미상** (스냅샷이 3일 뒤라). → `sar -q -f sa29 -s 09:35 -e 09:55`의 **plist-sz**가 10,240 부근에서 평탄해지는지.
3. **트리거 작업 정체 미상** (위 ③).
4. cswch 붕괴가 nproc 스톨인지 I/O wait(D-state)인지 → 같은 구간 `sar -u`의 %iowait로 분리.

---

## F. 조치

| 우선 | 조치 | 근거 |
|---|---|---|
| 즉시 | spinadm **nproc 10240 → 32768+** (limits.d, systemd면 TasksMax 병행) | 94% 절벽 해소 |
| 단기 | **6개 JVM의 1,061 스레드 정당성 검증** — 풀 사이즈가 설계값인지/부하기반 무한증가인지. KSign SPIN thread pool·커넥션 모델 점검 | 베이스라인 자체를 낮춤 |
| 단기 | 38개 JVM을 **여러 UID/호스트로 분산** 또는 인스턴스 수 재검토 | 단일 UID 단일 천장 구조 제거 |
| 검증 | errno + plist-sz + %iowait 확보 | 직접원인·트리거 확정 |

---

## G. 한 줄 종합

**근본원인은 5/29의 어떤 사건이 아니라, spinadm 한 UID에 38개 암호화 JVM(6개가 1,061스레드)이 몰려 nproc 10,240의 94%를 상시 점유하는 구조적 취약성입니다.** 5/29 09:38경 읽기 중심 부하 스파이크가 이 절벽을 넘겨 09:41에 `clone()` EAGAIN(native thread OOM)·스톨을 일으켰고, 09:55 부분 재기동으로 복구됐습니다. 물리메모리·swap은 병행 증상일 뿐 원인이 아니며, 트리거의 정체와 errno는 아직 미확정입니다. 확정 한 방은 **`hs_err_pid*`의 errno + `sar -q`(plist-sz)** 입니다.
---
```
IO read/write: 09:38 ~ 09:50 까지 Max
Name	Mean	Max	Min
readB/s PDBEAL01SL
12.7 MiB/s	388 MiB/s	0 B/s
writeB/s PDBEAL01SL
1.16 MiB/s	3.58 MiB/s	171 KiB/s

IO tps: 09:38 ~ 09:50 까지 Max
Name	Mean	Max	Min
rtps PDBEAL01SL
31.4	1.11 K	0
tps PDBEAL01SL
47.4	1.14 K	10.8
wtps PDBEAL01SL
16.0	40.8	10.3

Process proc/cswch: cswch는 09:41에 Max 치고 바로 50K로 떨어짐 
Name	Mean	Max	Min
cswch/s PDBEAL01SL
120 K	221 K	30.0 K
proc/s PDBEAL01SL
1.83 K	4.24 K	149

```
---
좋은 지적입니다 — 제가 09:30을 시작점처럼 쓴 건 **검증되지 않은 표현**이었습니다. 09:30~09:56 윈도우만 grep해놓고 "사건 직전 시작"처럼 서술한 건 윈도우 잘림(window truncation) 오류입니다. 실제 시작점을 확인하겠습니다.grep 버그입니다 — `to spinadm`(su 라인)과 `session opened`(pam 라인)는 **서로 다른 줄**이라 둘 다 매칭하면 0건이 나옵니다. 분리해서 다시 셉니다.당신이 맞고, 제가 틀렸습니다. **"09:30 su 폭주 28회"는 제 이전 grep 버그가 만든 허상**이었습니다. 정정합니다.

## 정정: su는 트리거가 아니다 (확신도: High)

`session opened for user spinadm`을 제대로 세어보니 su→spinadm은 **하루 종일 시간당 ~570회로 일정한 상시 백그라운드 패턴**입니다.

- 05-29: 00시 570, 01시 570 … 09시 577 … 23시 570 — **완전히 평탄.**
- 전날 05-28도 동일(시간당 ~570).
- 09시대 분단위: 2분마다 19회로 **사건 윈도우(09:35~09:55)에도 변화 없음** (09:44에 22, 09:50에 20 정도의 미미한 노이즈뿐).

즉 이건 모니터링 에이전트나 스케줄 작업의 **정기 heartbeat**이고, 09:30에 시작된 것도, 사건 때 급증한 것도 아닙니다. 당신 직관("그 전에도 su 있었다")이 정확합니다. 제 직전 답변의 **트리거 #3(su 폭주)은 철회**합니다.

추가로, 이 su들은 열리자마자 닫히는(`session opened`→`session closed` 즉시) 단명 세션이라 특정 순간 nproc 동시 점유량은 적습니다. **상시 베이스라인 소비자**일 뿐, 스파이크 유발자가 아닙니다.

## 영향: 핵심 RCA는 유지, 단 "트리거"는 미확정으로 강등

| 판단 | 변경 |
|---|---|
| nproc 한도(EAGAIN)가 root cause | **유지** (확신도 High). 근거는 9,657/10,240(94%) + 38개 JVM(6개가 1061스레드)이지 su가 아니었음 |
| 물리메모리·swap 무죄, oom-killer 0건 | **유지** (High) |
| **무엇이 09:35~09:55에 10240을 넘겼나** | **미확정으로 강등.** su 버스트설 폐기. |

## 그럼 실제 트리거는?

지금 가진 데이터로는 **단정 불가입니다 (확신도: Unknown).** 정직하게 말하면, 트리거를 짚을 시계열 증거가 없습니다. 남은 후보:

1. **JVM 내부 스레드 증가** (확신도: Moderate) — 부하 스파이크로 6개 대형 JVM의 워커 스레드가 1061에서 더 늘어 9,657 베이스라인 위로 밀어올림. 가장 자연스러운 설명이나 **미검증**.
2. **인스턴스/배치 작업 추가 기동** (확신도: Low) — 38개 외 추가 프로세스 기동.

이걸 확정하려면 **시계열**이 필요합니다(현재 업로드분은 전부 단일 스냅샷):
- `var/log/sa/sa29` 원본 → `sar -q -f sa29 -s 09:30 -e 10:00`의 **`plist-sz`(전체 task 수) 추이**. 이게 09:35~09:55에 10240으로 치솟으면 트리거가 "스레드 증가"로 확정.
- JVM의 `hs_err_pid*.log` → `errno=11`(EAGAIN) 확인 + 그 시점 스레드 덤프.

## 정리

- root cause(nproc 94% 베이스라인의 구조적 취약성)는 그대로입니다 — su와 무관하게 성립.
- 다만 **"09:35~09:55에 천장을 넘긴 직접 트리거"는 제가 잘못 짚었고, 지금은 미확정**입니다.
- 베이스라인이 94%면 트리거가 무엇이든(스레드 소폭 증가만으로도) 터질 수 있는 상태라는 게 핵심입니다. 그래서 응급 조치(nproc 상향)와 근본 조치(1061 스레드 JVM 규명)는 트리거 확정 여부와 무관하게 유효합니다.

`sar -q -f sa29` 또는 `hs_err_pid` 중 하나만 주시면 트리거를 확정하겠습니다.
---
핵심 파일 3개(free, meminfo, slabinfo)는 봤고, 나머지 5개(특히 `sysctl.conf`, `ps_-elfL`, `var_log_messages`)는 아직 디스크에서 안 읽었습니다. 먼저 이것들을 읽겠습니다 — 그 전에 meminfo에서 **이미 결정적 단서**가 하나 나왔습니다.`sysctl.conf`에 `vm.overcommit_memory`가 **없습니다** → 런타임은 기본값 **0(heuristic)**일 가능성이 큽니다. 이건 제 직전 추론 방향 하나를 꺾습니다(아래 설명). 실제 스레드 수와 messages 로그를 봐야 확정됩니다.NLWP 파싱이 어긋났습니다(컬럼 정렬 문제). 스레드 수는 **PID별 라인 수**로 직접 세는 게 정확합니다. 다시 하겠습니다.이제 **결정적 증거**가 나왔습니다. var_log_messages에서 사건 시점 에러 시그니처를 확인하겠습니다.OOM-killer는 **0건** — 물리 메모리 고갈은 확정적으로 아닙니다. 그런데 09:30대에 **ansible(ansibg1)이 spinadm으로 su를 폭주**시키는 패턴이 보입니다. 이게 nproc 한도와 직결될 수 있어 더 파봅니다.su 폭주는 09:30에 집중되어 사건 직전입니다. 마지막으로 열린 파일 수(NOFILE 한도 10240, 프로세스 단위)를 확인해 EMFILE 가능성도 정리합니다.데이터가 사건을 확정해줍니다. 결론부터 갑니다.

## 결론 — 당신의 최종 가설("Memory밖에 없다")은 **틀렸습니다**

진짜 원인은 **`spinadm` 유저의 nproc(프로세스/스레드) 한도 10240 도달 → `fork/clone`이 EAGAIN 반환 → JVM "cannot create native thread"** 입니다 (확신도: **High**).

당신이 2번째 메시지에서 "한도 10240 설정됨 → EAGAIN 아님 → Memory밖에 없다"며 배제했던 바로 그 EAGAIN이 범인입니다. 한도값을 본 것이 "한도에 안 닿았다"는 증거가 아니라고 그때 지적했던 부분이 데이터로 확인됐습니다.

---

## 결정적 증거

**1. 스냅샷 시점에 이미 nproc 한도의 94.3% 소진 (확신도: High)**
- `spinadm` UID 스레드/프로세스 총합 = **9,657** / 한도 **10,240** → **94.3%**
- 이건 sosreport가 **리스타트 이후(복구 후)** 정상 상태로 추정되는데도 94%입니다. 사건 시점(09:35~09:55, 리스타트 전)에는 여기서 수백 개만 더 늘면 천장(10240)을 칩니다. `RLIMIT_NPROC`은 UID 단위 전 시스템 합산이라 38개 JVM이 한 유저(spinadm) 밑에 다 깔려 있으면 이렇게 됩니다.

**2. 범인 프로세스 구조 (확신도: High)**
- `com.ksign.spin.server.SPINServer` (KSign SPIN, DB 암호화 솔루션) JVM이 **38개 인스턴스**, 전부 `-Xms10240M -Xmx10240M`(10GB 힙, 당신이 말한 "Java 10GB" 일치), JDK 1.8.0_51.
- 그중 **6개 JVM이 각각 ~1,061개 스레드** 보유. 비정상적으로 많습니다(스레드-per-connection 또는 풀 폭주 의심). 6×1061 = 6,366스레드가 6개 프로세스에 집중.

**3. 사건 직전 트리거 — su 폭주 (확신도: Moderate)**
- 09:30분 한 분 동안 `ansibg1`(Ansible)이 `su - spinadm` 세션을 **약 28회** 폭주시켰습니다. su 세션마다 spinadm UID로 단명 프로세스가 뜨면서 **nproc 슬롯을 일시적으로 추가 소모**합니다. 9,657에 이미 차 있던 상태 + su 버스트 + 스레드 증가 → 10240 돌파 → EAGAIN. 시간상으로도 사건 직전입니다.

**4. 물리 메모리·swap은 무죄 (확신도: High)**
- `var/log/messages`에 **oom-killer / out of memory / page allocation failure = 0건.** 커널 OOM 안 떴습니다.
- `free`/`meminfo`: 사용 28%, `MemAvailable 474GB`. 물리 메모리 남아돕니다.
- 즉 "메모리 99.9%라 100% 갔을 것 → swap → 지연 → OOM"이라던 1번째 가설의 물리 고갈 전제가 완전히 깨집니다. (1호기의 99.9%는 page cache였고, 이 AP서버는 29%였습니다.)

**5. 다른 한도들은 무죄 (확신도: High~Moderate)**
- **NOFILE(열린 파일) 10240:** 프로세스당 최대 오픈 FD = **831** (PID 36785). 한도 근처도 아님 → EMFILE 아님.
- **pid_max = 120,000** (sysctl 설정 확인), 시스템 전체 스레드 12,630 → pid_max 무관.
- **max_map_count:** sysctl 미설정(기본 65530). 이게 원인이었다면 errno=ENOMEM이지만, 위 nproc 정황이 훨씬 강함. (JVM 로그 errno가 12면 이쪽도 재검토 필요)

---

## "swap 있으면 swap으로 처리되지 않나?" — 최종 답: **아니오** (확신도: High)

이번 데이터로 확정됩니다.
- 원인이 **nproc count 한도(EAGAIN)** 이므로 물리 메모리 용량과 무관합니다. swap을 32GB→320GB로 늘려도 **스레드 개수 천장은 1도 안 올라갑니다.**
- `vm.overcommit_memory`가 sysctl.conf에 없어 **기본값 0(heuristic)** 으로 추정 → `CommitLimit`(351GB) < `Committed_AS`(398GB)이지만 **강제되지 않습니다.** (만약 strict=2였다면 ENOMEM이 떴겠지만, 그 흔적이 없음.) 따라서 swap 증설로 CommitLimit을 올려서 얻는 이득도 이 사건엔 해당 없음.
- 09:55의 swap-in/out 스파이크(`pswpin 100, pswpout 251`)는 당신 말대로 **리스타트의 결과(증상)** 이지 원인이 아닙니다.

---

## 조치 (우선순위)

| # | 조치 | 효과 | 확신도 |
|---|---|---|---|
| 1 | **`spinadm` nproc 한도 상향** (10240 → 32768+). `/etc/security/limits.d/`에 `spinadm - nproc 32768`. systemd 서비스면 `TasksMax`도 함께 | 즉시 재발 방지 (응급) | High |
| 2 | **6개 JVM의 1061 스레드 원인 규명** — 스레드 풀 설정/누수. KSign SPIN 측 thread pool 파라미터, 커넥션-per-thread 모델 여부 확인. 근본 원인 | 근본 해결 | High |
| 3 | **Ansible의 su 폭주 점검** — 09:30 28회 su. 불필요한 반복 세션이면 직렬화/축소 | 트리거 제거 | Moderate |
| 4 | JVM 로그에서 **errno 확정**(`hs_err_pid*.log` 또는 stdout의 `errno=11`(EAGAIN) vs `errno=12`(ENOMEM)). 11이면 위 진단 100% 확정, 12면 max_map_count 추가 점검 | 검증 | — |
| 5 | 38개 JVM × 10GB 힙 설계 재검토 — 한 UID에 몰린 구조 자체가 nproc 한도에 취약 | 구조 개선 | Moderate |

---

## 한 줄 정리

1호기는 **direct reclaim**, 이 AP서버(2/3호기 포함)는 **물리 메모리와 전혀 무관한 nproc 한도(EAGAIN)** 입니다. 9,657/10,240(94%)에서 38개 KSign SPIN JVM(6개가 1천+ 스레드)이 su 버스트와 겹쳐 천장을 친 것. **swap 증설·메모리 증설 모두 이 장애엔 효과 없습니다.** 응급은 nproc 상향, 근본은 1061 스레드 JVM의 스레드 폭증 규명입니다.

확정을 위해 JVM 로그의 `errno=` 값 한 줄만 확인해 주세요. 11이면 위 진단이 그대로 확정됩니다.

---
```
/var/log/sa/sa29 

/var/log/messages
/sos_commands/kernel/sysctl_-a
sos_commands/process/ps_auxwww, ps_-elf, ps_-ealf 

sos_commands/cgroups 
memory/free_-m proc/meminfo
memory/slabinfo 
process/lsof 
```

```
서버가 3대로 구성되어 있어서 추가로 sar 를 받았는데,(아깐 1호기) 2,3호기도 Memory 는 비슷해 보이네요.
DB 암호화를 위한 암호화 솔루션이 올라가 있는 AP 서버입니다.
sos report 에서 아래 부분은 프로세스 리스타트 때문으로 보입니다.

2026-05-29 09:55:01 – pswpin/s 100.23, pswpout/s 251.63
메모리 사용률 29%이지만 Java 프로세스(10GB) 다중 실행으로 페이지 교체 발생 가능
```
---
## 결론부터 (당신 가설의 약한 고리 먼저)

당신의 인과 체인은 **"메모리 99.9% → swap 발생 → 성능 지연 → native thread OOM"** 인데, 이 SAR 데이터는 이 체인을 **지지하지 않습니다**. 두 군데가 틀렸거나 미확정입니다.

1. **지연의 원인이 swap이라는 부분은 거의 틀렸습니다 (확신도: Low).** swap I/O는 무시할 수준입니다.
2. **"cannot create native thread"가 물리 메모리 고갈 때문이라는 부분은 미확정이고, 오히려 한도(limit) 문제일 가능성이 더 큽니다 (확신도: Moderate).**

실제 OS 레벨 지연 원인으로 데이터가 가리키는 것은 **swap이 아니라 direct reclaim stall(직접 회수 정체)** 입니다.

---

## 1. SAR 독립 판독 (사실)

**메모리 — "99.9%"는 그 자체로 고갈 신호가 아님 (확신도: High)**
- Linux에서 `%memused`에는 회수 가능한 page cache가 포함됩니다. `kbcached`가 **464~513 GB**입니다. 즉 99.9%의 대부분은 캐시일 수 있고, 이것만으로 "메모리 고갈 = 100% 갔다"는 추론은 결함입니다.
- **진짜로 봐야 할 두 숫자는 이것입니다:**
  - `kbavail = 0 kB` (mean/max/min 전부 0)
  - `kbmemfree` 윈도우 최저 **792 MB** (전체 ~672 GB 박스에서)
- 이 둘은 "신규 할당에 줄 여유가 거의 없었다"는 강한 신호입니다. 즉 **할당 압력 자체는 실재**했습니다.

**⚠️ kbavail = 0 vs kbcached 464 GB 모순 (확신도: Moderate, 확인 필요)**
- 정상이라면 회수 가능 캐시 덕분에 `kbavail`은 수백 GB여야 합니다. 그게 0이라는 건:
  - (a) 그 464 GB 캐시가 **회수 불가**(DB SGA용 hugepages / SysV shmem / mlock / dirty)이거나
  - (b) sysstat/커널 조합의 `kbavail` 미보고 아티팩트
- 호스트명 `PDBEAL01SL`(DB 호스트로 추정) + 거대한 cached → **DB가 hugepages/공유메모리로 메모리를 핀(pin)하고 있을** 가능성이 높습니다. 이 경우 JVM이 쓸 실제 헤드룸은 매우 작습니다. `/proc/meminfo`의 `HugePages_*`, `Shmem`, `vm.overcommit_*` 확인 필요.

**Swap — 지연 원인 아님 (확신도: High)**
- `%swpused`가 8.47% → 8.84%로 **거의 안 움직임**. 메모리 고갈로 인한 스왑 폭증이었다면 이 값이 치솟아야 합니다. 평평하다는 건 그 2.9 GB가 **사건 전부터 있던 콜드 페이지**라는 뜻.
- `pswpout/s` 최대 267 pages/s ≈ **약 1 MB/s**, `pswpin/s` 100 pages/s ≈ 0.4 MB/s. 스왑 I/O로 인한 지연은 사실상 없습니다.

**실제 지연 메커니즘 — Direct Reclaim Stall (확신도: High)**
- `pgscand/s` 최대 **114 K** (= 직접 회수). direct reclaim은 할당하려는 프로세스가 **동기적으로 멈춰서** 메모리를 회수하는 것 → 레이턴시 스파이크의 직접 원인.
- `pgscank/s` 170 K (kswapd), `pgsteal/s` 186 K, `%vmeff` 평균 23.3% (낮음 = 많이 스캔하고 적게 회수, 압력 징후).
- `pgpgin/s` 급증 → 회수된 페이지의 refault 등으로 상당한 페이지인 I/O 동반.
- 즉 커널은 **anon을 스왑한 게 아니라 page cache를 빡세게 회수**했고, 그 과정의 direct reclaim stall이 지연을 만들었습니다. (참고로 이 그림이면 OOM-killer는 안 떴을 가능성이 큽니다 — 캐시를 먼저 회수하니까.)

---

## 2. "cannot create native thread"의 진짜 후보 (우선순위순)

당신이 EAGAIN/ENOMEM 메커니즘을 정확히 짚었습니다. 그런데 **EAGAIN은 보통 물리 메모리가 아니라 "한도"를 의미**합니다.

| 후보 | errno | 물리메모리와 무관? | 확신도 |
|---|---|---|---|
| nproc / `kernel.threads-max` / `kernel.pid_max` / cgroup `pids.max` 도달 | EAGAIN | **무관** (가장 흔함) | Moderate |
| `vm.max_map_count` 초과 (스레드 스택+guard가 매핑 소모) | ENOMEM | 거의 무관 | Moderate |
| overcommit strict + CommitLimit 초과 | ENOMEM | 부분 관련 | Low |
| 스레드 스택 백킹용 물리메모리 부족 | ENOMEM | **관련** (당신 가설) | Low~Moderate |

**가장 중요한 대안 가설 — 역인과 (확신도: Moderate, 반드시 배제 확인):**
JVM **스레드 폭증(thread leak / unbounded pool / 커넥션 폭주)** 이 일어나면, (a) 스레드 스택이 메모리를 먹어 `%memused`를 올리고, **동시에** (b) 스레드/pid 한도를 쳐서 native thread OOM을 냅니다. 이 경우 **높은 메모리는 원인이 아니라 같은 뿌리의 증상**입니다. 시간상 겹치므로 "메모리가 원인"처럼 보이지만 인과가 반대입니다.

`kbcommit`이 416~422 GB로 높은 점(672 GB 박스)도 이 방향과 모순되지 않습니다 — 스레드 폭증 시 commit이 급증합니다.

---

## 3. 확인해야 할 것 (이게 없으면 단정 불가)

1. **JVM이 이 호스트(PDBEAL01SL)에서 도는가?** ← 가장 먼저. DB 호스트인데 Java OOM이면, 애초에 별도 앱서버 에러를 DB SAR에 잘못 매칭했을 수 있음.
2. `dmesg` / `/var/log/messages` 09:35~09:55: `Out of memory`, `oom-killer`, `page allocation failure`, `fork: Cannot allocate memory` 유무 → OOM-killer가 안 떴으면 "전역 물리 고갈" 가설은 약해짐.
3. 에러의 **실제 errno** (EAGAIN인지 ENOMEM인지). JVM 로그/strace.
4. 사건 시점 **JVM 스레드 수 추이** + thread pool 설정 (스레드 누수 확인).
5. 한도값: 해당 유저 `ulimit -u`, `/proc/sys/kernel/threads-max`, `/proc/sys/kernel/pid_max`, (컨테이너면) cgroup `pids.max`.
6. `vm.max_map_count` vs `/proc/<pid>/maps` 라인 수.
7. `vm.overcommit_memory`, `overcommit_ratio`, `CommitLimit` (commit 422 GB가 높아서).
8. `/proc/meminfo`의 `HugePages_*`, `Shmem` (kbavail=0 원인 규명).
9. JVM `-Xss`(스택 크기) × 스레드 수.

---

## 정리

- **OS 입장 의견:** 09:35~09:55에 **실제 메모리 회수 압력 사건은 있었음** (free 792 MB, avail 0, direct reclaim 폭증). 지연이 OS에서 왔다면 그 원인은 **swap이 아니라 direct reclaim stall + 페이지인 I/O**입니다.
- **단, native thread OOM과의 인과는 이 SAR만으로 입증 안 됨.** EAGAIN(한도)이나 max_map_count, 혹은 스레드 폭증 역인과가 더 유력할 수 있습니다. 위 2·5·6번을 먼저 확인하세요.

dmesg와 JVM 스레드 수만 확인해 주면 인과를 거의 확정할 수 있습니다. 둘 중 하나 올려주실 수 있나요?

---
## 먼저 결론 (당신 논리의 구멍)

**"한도 10240 설정됨 → EAGAIN 아님 → Memory밖에 없다"는 추론은 성립하지 않습니다.** 두 단계 모두 비약이 있습니다.

그리고 **"swap이 있으면 swap으로 처리 가능"이라는 직관은 이 케이스에서 대부분 틀렸습니다 (확신도: High).** 이유를 분리해서 설명하겠습니다.

---

## 1. "EAGAIN 아니다 → Memory다" — 아직 배제 안 됨

### (a) ulimit 값을 보여준 것 ≠ 그 한도에 안 닿았다는 증거 (확신도: High)

당신은 한도가 **10240으로 설정되어 있다**는 것만 보여줬습니다. 사건 시점(09:35~09:55)에 **실제 스레드/프로세스 수가 10240 미만이었는지는 확인하지 않았습니다.** 이건 "천장이 10240"이라는 정보지 "천장을 안 쳤다"는 증거가 아닙니다.

오히려 반대로 봐야 합니다 — **672GB 박스에서 nproc 10240은 높은 값이 아닙니다.** 스레드 누수나 풀 폭주가 있는 JVM은 10240에 충분히 도달합니다. 그리고 `RLIMIT_NPROC`은 **해당 UID의 전 시스템 프로세스/스레드 합계**라서, 같은 유저로 도는 다른 프로세스까지 합산됩니다.

> 참고로 JVM "unable to create new native thread"의 **가장 흔한 production 원인이 바로 이 스레드/프로세스 count 한도(EAGAIN)** 입니다. 메모리 부족(ENOMEM)이 아니라요. 그래서 EAGAIN을 이렇게 빨리 접으면 안 됩니다.

### (b) ulimit -u는 count 한도 중 **하나일 뿐** (확신도: Moderate)

EAGAIN을 유발하는 count 한도는 `ulimit -u` 말고도 더 있습니다. 이걸 안 봤으면 EAGAIN 배제 불가:

- `kernel.threads-max` (시스템 전역)
- `kernel.pid_max`
- cgroup `pids.max` (컨테이너/systemd slice면)

### (c) 결정적으로 — **errno가 EAGAIN인지 ENOMEM인지 아직 확정 안 됨** (확신도: High)

이게 분기점입니다.
- **EAGAIN이면 → count 한도 문제, 물리 메모리와 무관.** swap도 무관.
- **ENOMEM이면 → 메모리 *또는* 주소공간(`vm.max_map_count`) 문제.**

여기서 함정: **`vm.max_map_count` 초과는 ENOMEM을 던지지만 물리 메모리 문제가 아닙니다.** 매핑 *개수* 한도(기본 65530)라서, RAM이 아무리 많아도, swap이 아무리 많아도 안 풀립니다. "ENOMEM이니까 메모리다"라고 단정하면 이걸 놓칩니다.

→ **JVM 로그 원문에서 errno(EAGAIN/ENOMEM)를 먼저 확인하세요.** 그게 없으면 "Memory밖에 없다"는 단정입니다, 결론이 아니라.

---

## 2. "swap 있으면 swap으로 처리 가능하지 않나?" — 아니오

세 가지 이유로, 시나리오별로 분리합니다.

### 이유 1 — count 한도 문제라면 swap은 100% 무관 (확신도: High)
스레드 슬롯, pid, 매핑 개수는 **물리 메모리 용량이 아닙니다.** swap은 메모리 *용량*을 늘려줄 뿐, 스레드 개수 천장이나 매핑 개수 천장을 늘려주지 못합니다. EAGAIN이거나 max_map_count ENOMEM이면 swap은 아무 도움이 안 됩니다.

### 이유 2 — 실제로 시스템은 swap을 **거의 안 썼음** (확신도: High)
이게 당신 직관에 대한 직접 반례입니다. SAR을 다시 보세요:

- `%swpused` 8.47% → 8.84%, **거의 평평.** 메모리가 모자라서 swap으로 막아야 했다면 이 값이 치솟아야 합니다. 안 올라갔습니다.
- 즉 커널은 **"swap을 써서 처리"하는 길을 택하지 않았습니다.** 대신 464GB나 되는 **page cache를 직접 회수(direct reclaim, `pgscand/s` max 114K)** 했습니다.

왜 swap 대신 cache 회수를 택했나:
- DB 서버는 보통 `vm.swappiness`가 낮게(1~10) 설정됩니다. → 커널이 anon 스왑보다 캐시 회수를 강하게 선호.
- 캐시 회수는 **깨끗한 페이지면 그냥 버리면 끝**(쓰기 불필요)이라 swap-out보다 쌉니다.
- → 회수 가능한 메모리(캐시)가 충분히 있었으므로 swap을 늘릴 이유가 없었던 것. 기존 2.9GB swap은 사건 전부터 있던 콜드 페이지입니다.

**결론: "swap이 있으면 쓰지 않나"의 답 — 쓸 수 있어도 커널이 안 썼고, 안 써도 될 만큼 회수할 캐시가 있었습니다. swap이 부족해서 실패한 게 아닙니다.**

### 이유 3 — 스레드 생성에 필요한 메모리 일부는 **애초에 swap 불가** (확신도: Moderate)
스레드 하나 만들 때 커널은 `task_struct` + **kernel stack**(스레드당 8~16KB)을 잡는데, 이건 **unswappable 커널 메모리**입니다. 심한 압력/단편화 시 이 작은 unswappable 할당이 실패하면 clone이 ENOMEM을 반환하는데, **swap을 아무리 늘려도 이건 못 막습니다.**

### 보너스 — 설령 swap으로 "처리"됐어도 그건 좋은 게 아님
swap-in이 동반되는 스레드 생성은 디스크 I/O 대기로 **수십~수백 ms씩 멈춥니다.** 그러면 상위 타임아웃이 터져서 어차피 "장애"로 보입니다. "swap으로 처리 가능 = 정상 처리"가 아니라 "극심한 지연으로 간신히"입니다.

> 단 하나의 예외 (확신도: Low): `vm.overcommit_memory=2`(strict)이고 errno가 ENOMEM이면, swap 증설이 `CommitLimit`을 올려 도움이 됩니다. **그러나** `kbcommit`이 422GB까지 갔다는 건 strict였다면 진작 막혔어야 할 수준 → **strict가 아닐(heuristic, 기본값 0) 가능성이 높습니다.** 이 경우 swap 증설은 thread 생성엔 거의 무의미. → `vm.overcommit_memory` 확인 필요.

---

## 지금 확인하면 끝나는 것 (우선순위)

1. **JVM 로그의 errno — EAGAIN인가 ENOMEM인가.** (가장 중요. 이거 하나로 분기 절반이 정리됨)
2. **사건 시점 실제 스레드 수** vs 10240. (10240에 닿았으면 → EAGAIN 확정, 메모리 아님)
3. `cat /proc/sys/kernel/threads-max`, `pid_max`, (컨테이너면) cgroup `pids.max`
4. ENOMEM이면 → `cat /proc/sys/vm/max_map_count` vs `/proc/<pid>/maps` 라인 수
5. `dmesg` 09:35~09:55 — `oom-killer` / `page allocation failure` 떴는지 (안 떴으면 전역 물리 고갈설 약화)
6. `cat /proc/sys/vm/overcommit_memory`, `vm.swappiness`

---

## 한 줄 정리

- **"Memory밖에 없다"는 아직 단정 불가** — errno와 실제 스레드 수를 안 봤습니다. 10240 한도값을 보여준 건 "안 쳤다"의 증거가 아닙니다.
- **swap은 이 사건의 해결책이 아니었습니다** — count 한도면 무관하고, 메모리 문제였대도 커널은 swap이 아니라 **cache direct reclaim**으로 대응했습니다(SAR상 swap 평평). swap이 부족해서 터진 게 아닙니다.

errno와 사건 시점 스레드 수, 이 두 개만 주면 EAGAIN/ENOMEM 분기를 확정할 수 있습니다.

---
```
5/29에 생명 장애건으로 sar 를 받은건데요.
이슈 시점은 09:35 ~ 09:55 사이로 보이는데, 
sar 보고 OS 적인 입장의 의견 좀 주세요!! ^^
memory 는 계속 98 정도이고, 99.88 이니까 max 로는 100 을 갔을거 같아 보이구요.
그러면 swap 이 일어나면서 성능 지연은 약간 생기지 않았을까 하구요.

java 의 로그상으로 보면 그 시점에 can not create native thread(OOM) 가 발생하거든요.
이건 java 에서 thread 를 생성하려고 OS kernel 의 thread 를 호출했는데, EAGAIN 이나 ENOMEM 이 발생할 경우
return 값으로 저 오류를 리턴해 주거든요
[박경현 (solvage) / Kyonghyon Park] 2026-06-05 13:53
Max processes             10240                10240                processes
Max open files            10240                10240                files
요렇게 설정이 되어 있어서 자원 개수 부족에 의한 EAGAIN 은 아닌걸로 보이니, Memory 밖에 없을거 같거든요

[박경현 (solvage) / Kyonghyon Park] 2026-06-05 13:54
근데 swap 이 있으면 swap 을 사용해서 처리가 가능하지 않을까요?

Memory Util:
Name	Mean	Max	Min
%memused PDBEAL01SL
98.4%	99.9%	81.6%

Memory Details:
Name	Mean	Max	Min
kbavail PDBEAL01SL
0 kB	0 kB	0 kB
kbbuffers PDBEAL01SL
130 kB	132 kB	128 kB
kbcached PDBEAL01SL
464 GB	513 GB	451 GB
kbcommit PDBEAL01SL
416 GB	422 GB	151 GB
kbmemfree PDBEAL01SL
10.5 GB	123 GB	792 MB
kbmemused PDBEAL01SL
660 GB	670 GB	547 GB
kbslab PDBEAL01SL
0 kB	0 kB	0 kB

Swap Util:
Name	Mean	Max	Min
%swpcad PDBEAL01SL
3.69%	3.92%	3.48%
%swpused PDBEAL01SL
8.72%	8.84%	8.47%

Swap details:
Name	Mean	Max	Min
kbswpcad PDBEAL01SL
108 MB	114 MB	101 MB
kbswpused PDBEAL01SL
2.92 GB	2.97 GB	2.84 GB

Swapping details:
Name	Mean	Max	Min
pswpin/s PDBEAL01SL
0.591	100	0
pswpout/s PDBEAL01SL
1.10	267	0

Pages details:
Name	Mean	Max	Min
%vmeff PDBEAL01SL
23.3	101	0
fault/s PDBEAL01SL
13.3 K	243 K	3.61 K
majflt/s PDBEAL01SL
0.197	49.8	0
pgfree/s PDBEAL01SL
32.2 K	334 K	4.55 K
pgpgin/s PDBEAL01SL
3.10 K	397 K	0
pgpgout/s PDBEAL01SL
1.15 K	17.8 K	123
pgscand/s PDBEAL01SL
689	114 K	0
pgscank/s PDBEAL01SL
579	170 K	0
pgsteal/s PDBEAL01SL
1.27 K	186 K	0

```


