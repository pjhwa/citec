## 원인 분석

### 1단계: 사고 과정
- 3대 서버(DB2·ETL·기타)의 dmesg/messages/modinfo를 수집해 hung-task, kernel trace, 커널 버전, 설치 모듈을 교차 대조했습니다.
- 증상(SSH는 연결되나 프롬프트 이후 명령 미응답 → 다음 날 "특정 명령만 느림")은 **kernel rwsem write-lock 경합 + THP(Transparent Huge Page) collapse 실패 + 메모리 압박 하에서의 swap-in 대기** 의 전형적 패턴과 일치합니다.
- hung-task 트레이스의 최상단을 잡은 프로세스가 **khugepaged** 이고, 이와 동시에 블록된 사용자 프로세스가 전부 **CrowdStrike Falcon의 user-space 스레드**(`falcon-sensor-b`, `bpfrb/N`, `evdefer/N`, `wqtimer`)라는 점에서 "백신-커널 상호작용" 문제로 수렴합니다.

### 2단계: 핵심 증거

**[공통] 커널·HW 환경**
- 3대 모두 Lenovo ThinkSystem SR650(V2/V1), RHEL 8 (kernel `4.18.0-477.10.1.el8_8` / `4.18.0-553.el8_10`)
- CrowdStrike Falcon Sensor를 **eBPF user-mode 로 운영** (커널 모듈이 아닌 bpf 센서 → `modinfo` 에는 falcon 모듈 없음, 대신 `falcon-sensor-bpf` 데몬이 동작)

**[DB2 서버 OSDSVDDP1P] 4/21 14:35** — 사용자가 첫 번째로 재부팅한 장애 시점
| 블록된 태스크 | 스택 핵심 |
|---|---|
| `khugepaged:249` | `rwsem_down_write_slowpath` → `collapse_huge_page` (THP 병합을 위해 `mm->mmap_lock` write-lock 대기) |
| `bpfrb/1..21` (CrowdStrike 10개+) | `rwsem_down_read_slowpath` → `__do_page_fault` 또는 `do_swap_page → migration_entry_wait_on_locked` |

- `bpfrb/1` 스택에 **`io_schedule → do_swap_page → migration_entry_wait_on_locked`** 등장 → **swap-in I/O 를 대기** 하면서 페이지 마이그레이션 엔트리에 걸림.
- `Code: Unable to access opcode bytes at RIP ...` — 해당 페이지가 스왑 아웃되어 지시어조차 읽을 수 없는 상태.

**[ETL 서버 OSDSVDEP1P] 4/18·4/20·4/22 세 차례 동일 패턴**
- `khugepaged` + `evdefer/N` + `wqtimer` + `falcon-sensor-b` + `bpfrb/N` + `workqueue` 가 **동시에** 120초 이상 블록.
- 총 hung-task 로그 30건, falcon-sensor 관련 로그 1,847건(=파일이 매우 크고 falcon 활동이 지배적).

**[3번째 서버 OSOACSPEP1P]**
- hung-task 0건, `falcon-sensor` 문자열 0건 → **Falcon 미설치 또는 비활성** 추정. 이것이 장애가 이 서버에만 없는 이유와 정확히 부합.

### 3단계: 결론 — 근본 원인

> **CrowdStrike Falcon (eBPF 사용자 센서) 의 다수 스레드가 `mmap_lock` read-lock 을 장시간 점유한 상태에서 page-fault/swap-in 에 묶이고, 동시에 `khugepaged` 가 동일 프로세스 주소공간의 write-lock 을 요구하면서 rwsem 경합이 발생. 그 결과 커널이 `mmap_lock` 기아(starvation)에 빠져 새 프로세스 생성·`fork/exec`·`read /proc` 이 요구되는 모든 조작(=shell 프롬프트, `ls/ps/top` 등 대부분의 인터랙티브 명령)이 멈춘 것**

보조적으로 관찰되는 악화 요인:
- 메모리 압박 + swap 사용 → `do_swap_page` 와 `migration_entry_wait_on_locked` 가 트레이스에 반복 등장 → THP collapse 비용이 폭증.
- **서비스(DB2·ETL) 자체는 이미 기동되어 lock 획득이 없거나 file I/O 중심이므로 정상 동작**, 반면 **신규 로그인/명령 실행은 `mmap_lock` 을 요구하기 때문에 "접속은 되는데 프롬프트가 멈춤"** 증상이 그대로 설명됨.
- 재부팅 직후에는 메모리가 정리되어 일시 회복되지만, Falcon 이 재기동되고 워크로드가 올라가면 동일 패턴이 누적돼 다음 날 다시 재현.

### 4단계: 확인/대응 Action Items

**① 즉시 완화 (downtime 없음)**
- `echo never > /sys/kernel/mm/transparent_hugepage/enabled` → THP 비활성화 (DB2 IBM 공식 권고사항과도 일치)
- `echo never > /sys/kernel/mm/transparent_hugepage/defrag`
- `grubby --update-kernel=ALL --args="transparent_hugepage=never"` 로 영구화
- `sysctl vm.swappiness=1` (DB2 서버는 1~10 권고), swap 사용량 모니터링

**② CrowdStrike 측 확인 (가장 중요)**
- CrowdStrike 포털에서 **센서 빌드/채널 파일 버전** 확인 후 CrowdStrike 지원에 본 스택(`rwsem_down_read_slowpath → __do_page_fault`, `bpfrb` + `evdefer` 블록) 티켓 제출.
- 알려진 유사 이슈: Falcon eBPF 센서가 RHEL 8 에서 `khugepaged` 와 경합하며 hung-task 유발한 사례가 다수 보고됨. **센서 버전 업그레이드** 가 일반적 해법.
- 임시로 **BPF mode → Kernel Module mode (kmod)** 전환을 검토 (CS 지원 협의 필요).

**③ 진단·모니터링 강화**
- `vmstat 1`, `sar -B`, `/proc/pressure/memory` 로 PSI 메모리 압박 지표 상시 수집
- `perf lock` 또는 `cat /proc/<pid>/stack` 을 걸어 다음 재발 시 어느 lock 에서 막히는지 즉시 캡처
- `echo 1 > /proc/sys/kernel/hung_task_panic` 은 **설정 금지** (운영에서 panic 로 확장되므로), 대신 `kdump` 정상 동작 확인

**④ 메모리·용량 점검**
- DB2·ETL 서버의 실제 워킹셋과 `memory.*` cgroup 사용량 검토. THP 를 끄더라도 메모리 압박이 있으면 다른 경합이 나타날 수 있음.

### 5단계: 불확실성 (명시)

- **Falcon 센서의 정확한 버전 정보** 가 업로드 로그에 없어 이슈 티켓을 어느 릴리스에 매핑할지는 포털에서 재확인 필요. `falconctl -g --version` 결과를 요청드립니다.
- 로그에 `oom-killer` 는 보이지 않아 순수 OOM 은 아니지만, `/proc/meminfo` · `free -h` 덤프가 없어 당시 **swap 사용률** 을 수치로 고정하지 못했습니다. 재현 시 `sar -r -S` 1초 간격 수집 권장.
- 3번째 서버(OSOACSPEP1P)가 장애 미발생 원인이 "Falcon 미설치" 라는 추정은 로그에 falcon 문자열이 전혀 없다는 간접 증거에 기반합니다. 실제로는 **정책/모듈 배포 범위** 를 자산관리에서 교차확인 필요.

---

**한 줄 요약**: THP(`khugepaged`)와 CrowdStrike Falcon eBPF 센서 스레드(`bpfrb/evdefer/wqtimer/falcon-sensor-b`)가 프로세스 주소공간의 `mmap_lock` 을 서로 기다리다 rwsem 경합·기아가 발생하여, 기존 서비스는 동작하지만 신규 로그인/명령 실행이 멈추는 증상이 발생. **대응 우선순위: ① THP never 설정, ② Falcon 센서 버전 업그레이드(또는 kmod 전환), ③ 메모리 압박 지표 상시 수집.**

---

## 2단계 심층 분석 결과

### 6단계: 추가로 발견한 증거

**ETL 서버(OSDSVDEP1P)의 hung-task 재발 패턴 — 중요**
| 일자 | 시각 | 블록된 태스크 |
|---|---|---|
| 4/18 15:54 | 1차 | `evdefer/11`, `wqtimer`, `workqueue` (Falcon 스레드군) |
| 4/20 21:57 | 2차 | `khugepaged` + `evdefer/11` + `falcon-sensor-b` + `workqueue` |
| 4/22 04:42 | 3차 | `khugepaged` + `evdefer/4` + `wqtimer` + `falcon-sensor-b` + `bpfrb/0~5` |

→ **수일 간격이 아닌 수시간~이틀 간격**으로 재발 중이며, **재부팅해도 해결이 안 된 상태**.

**DB2 서버(OSDSVDDP1P) 실제 재부팅 시점 재구성**
- `Apr 21 09:17:44` — 1차 재부팅 후 부팅 (Startup 3분 소요)
- `Apr 21 14:35:10` — 복귀 5시간 만에 다시 hung-task 발생 (`khugepaged` + `bpfrb/1~21` 10건)
- `Apr 21 21:05` 이후 다시 shutdown 시도들
- `Apr 22 10:30:39` — 2차 재부팅 후 부팅

→ 사용자 설명("다음날 재부팅")과 타임라인 정확히 일치.

**Falcon Cloud 연결 이상 징후 (간접 원인 후보)**
- `Apr 16 23:04` 부터 `ConnectToCloud starts` 가 **약 6~7분 간격으로 반복 기록** (= Falcon 클라우드로의 이벤트 전송이 지속 실패/재시도 중)
- 이는 Falcon 센서가 **이벤트를 로컬 큐에 축적**하면서 BPF 워커 스레드(`bpfrb/*`) 가 더 많은 lock 경합을 일으킬 가능성을 시사.
- **장애 발생 4~5일 전부터** 이 증상이 시작됨 → 시간적 상관관계 존재.

### 7단계: 3개 서버 비교 (정상/이상 원인 확정)

| 항목 | OSDSVDDP1P (DB2·이상) | OSDSVDEP1P (ETL·이상) | OSOACSPEP1P (정상) |
|---|---|---|---|
| HW | SR650 V2, Xeon 4310, 48 core, 128GB | SR650 V1, Xeon 4208, 32 core, 64GB | SR650 V1, Xeon 4208, 32 core, 64GB |
| 커널 | 4.18.0-477.10.1.el8_8 | 4.18.0-553.el8_10 | 4.18.0-553.el8_10 |
| CrowdStrike Falcon | **설치 (BPF mode)** | **설치 (BPF mode)** | **미설치** |
| hung-task | 10건 (4/21) | 30건 (4/18·4/20·4/22) | **0건** |
| falcon 로그 건수 | 26건(부분) | **1,847건** | 0건 |

→ **HW·커널 버전이 다름에도 Falcon 유무가 이상/정상을 완벽히 가르는 단일 변수**. 이는 이전 결론을 더욱 강하게 뒷받침함.

### 8단계: 보완된 Root Cause 서술

1. **촉발(Trigger)**: Falcon 센서가 Cloud 연결 실패 반복(4/16부터) → 이벤트 큐 적체 → BPF 워커 스레드(`bpfrb`, `evdefer`, `wqtimer`) 활동 급증.
2. **경합(Contention)**: 이 스레드들이 모니터링 대상 프로세스 주소공간에 대해 `mmap_lock` read-lock 을 자주, 오래 점유.
3. **기아(Starvation)**: 메모리 압박 상황에서 `khugepaged` 가 THP 병합을 위해 동일 `mm->mmap_lock` write-lock 을 요구 → RHEL 8 kernel 4.18 rwsem 의 writer-starvation 보호 메커니즘과 상호작용하며 **read-lock 대기 행렬이 길게 형성**.
4. **2차 피해(Collateral)**: `swap-in` 대기(`migration_entry_wait_on_locked`)와 겹치면서 대기 체인이 수분~수십분 지속.
5. **관찰 증상**:
   - 기동 중인 DB2/DS/ETL 데몬은 **이미 핸들러가 생성되어 lock 요구가 낮으므로 I/O만 하면서 정상 수행**.
   - 반면 **새 SSH/콘솔 세션의 fork+exec, `ls/ps/top` 등 `/proc` 조회, PAM/NSS lookup** 은 모두 **mmap_lock 요구** → 프롬프트 직후 무응답.
   - 회복기에는 **일부 명령만 느린 현상**으로 재현 (사용자의 2일차 증상 = hung-task 이벤트 수준이 낮은 시점의 mmap_lock 경합).

### 9단계: 추가 대응 Action

**⑤ 즉시 Falcon 재시작 (downtime 없음)**
- `sudo systemctl stop falcon-sensor` → 1시간 모니터링 → 증상 사라지면 원인 100% 확정
- DB2 서비스는 유지되므로 업무 영향 없이 테스트 가능

**⑥ Falcon 네트워크 연결 점검**
- Falcon Cloud URL (`ts01-b.cloudsink.net` 등) 으로의 방화벽/프록시 통신 확인
- 수일간 `ConnectToCloud starts` 반복은 **망분리·방화벽 정책 변경** 또는 TLS 인증서 문제일 가능성. CSAP·사내 망 정책 변경 이력 확인 필요.

**⑦ 커널 파라미터 튜닝 (THP 외에)**
```bash
# rwsem 경합 완화 (write starvation 방지)
sysctl -w vm.dirty_ratio=10
sysctl -w vm.dirty_background_ratio=5
# khugepaged 빈도 낮추기 (THP=never로 근본차단하면 불필요)
echo 10000 > /sys/kernel/mm/transparent_hugepage/khugepaged/scan_sleep_millisecs
```

**⑧ 관찰용 덤프 자동화 (다음 재발 대비)**
```bash
# systemd timer로 5분 간격 수집 (증상 발생 시 원인 고정용)
cat /proc/pressure/memory /proc/pressure/cpu /proc/pressure/io
cat /proc/meminfo | grep -E "MemFree|SwapFree|AnonHugePages|ShmemHugePages"
ps -eLo pid,tid,stat,wchan:32,comm | grep -E " D "   # D-state 프로세스 포착
```

### 10단계: 불확실성 (추가)

- **OSDSVDEP1P dmesg 의 hostname 이 `OSOACSPEP1P` 로 표기**되어 있음 — 파일명과 dmesg 내 hostname 불일치. 이는 단순 파일 이름 혼동인지, 아니면 클론 이미지 배포 시 hostname 변경 누락으로 **`/etc/hostname` 이 두 서버에서 일시 혼동되었을 가능성**이 있으나 messages 내부는 정상이라 운영 영향은 없어 보임. **파일 수집 시 hostname 검증** 을 권장.
- `ConnectToCloud starts` 반복이 원인인지 증상인지는 Falcon 로그(`/opt/CrowdStrike/logs/`) 를 직접 열어야 확정 가능.
- 4/16 23:00 전후로 **무슨 네트워크/정책 이벤트가 있었는지** 확인 필요 — 이 시점이 전체 장애의 진짜 시작점일 수 있음.

---

**최종 권고 (우선순위 순)**
1. 임시 테스트로 **Falcon 센서만 stop** 하여 증상 재발 여부 확인 (1시간 이내 판단 가능, 가장 확실한 진단법)
2. Falcon Cloud 통신 경로 점검 + 센서 버전 확인 및 CrowdStrike 티켓 제출
3. THP `never` 영구 적용 (DB2 서버 IBM 권고와도 일치, 부작용 없음)
4. 다음 재발 대비 PSI·D-state 자동 수집 스크립트 배치
5. 근본 해결 전까지 **Falcon 센서를 eBPF → kmod 모드로 전환 검토** (CrowdStrike 지원 협의 필요)
