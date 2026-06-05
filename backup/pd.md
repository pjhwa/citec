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


