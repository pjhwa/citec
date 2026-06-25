# ceph-collector 예시 출력 & 해설집

**대상**: Ceph 18.2.x (Reef), cephadm 배포
**용도**: 수집기 각 명령의 실제 출력 형식과, 그 출력에서 무엇을 진단·확인할 수 있는지 정리.
**짝 문서**: `ceph-collector-design-final.md`(설계). 본 문서의 명령 집합·신뢰도·부하 가드는 설계 문서와 1:1 대응하며, `⚠️ 운영 부하` 표기는 설계 §4.6(반드시 수집하지만 부하가 있는 명령)을 참조한다.

> **읽는 법 / 신뢰 고지**
> - 모든 출력의 **값(수치·이름·UUID)은 합성(synthetic)** 이다. **형식(컬럼·필드명·구조)은 18.2.x 실제 출력 기준**이며, 형식이 확실치 않은 명령은 텍스트 기본 출력으로 제시했다(수집기는 추가로 `-f json-pretty`를 함께 저장).
> - 대형 JSON(`ceph report`, `pg query`, `perf dump`, `zone get` 등)은 **핵심 필드만 발췌**하고 `…`로 생략했다. 생략 부분의 필드명을 추측해 채우지 않았다.
> - 시크릿 필드는 수집기 레닥션을 반영해 `***REDACTED***`로 표기했다.
> - 일부 명령 예시 묶음(예: `pg dump_stuck`은 inactive 1개로 unclean/stale/undersized/degraded 변형 대표, `counter dump`는 `perf dump` 항목에 병합)은 동일 형식이므로 대표 1개로 해설했다.
> - `ceph osd perf`/`balancer status`/`osd df tree`/`features`/`radosgw-admin sync status` 형식은 공식·실사용 출력으로 교차검증했다.

---

# 1. Metadata

### `ceph --version`
```
ceph version 18.2.4 (e7ad5345525c7aa95470c26863873b581076945d) reef (stable)
```
**확인 내용**: 수집 시점의 정확한 패치 버전. 버그/CVE 해당 여부, 데몬 간 버전 일치(§3 `ceph versions`와 대조)의 기준점.

### `ceph fsid`
```
3a5f8b2c-1d4e-4f9a-9c7b-2e6a1f0d8b34
```
**확인 내용**: 클러스터 고유 ID. 수집물 네이밍·다중 클러스터 식별. 호스트의 `/var/lib/ceph/<fsid>` 경로와 일치 여부.

### `uname -a`
```
Linux scp-osd-01 5.15.0-117-generic #127-Ubuntu SMP ... x86_64 GNU/Linux
```
**확인 내용**: 커널 버전(RBD krbd feature 호환, 알려진 커널 버그), 아키텍처.

---

# 2. Cluster (기본 상태)

### `ceph -s`
```
  cluster:
    id:     3a5f8b2c-1d4e-4f9a-9c7b-2e6a1f0d8b34
    health: HEALTH_WARN
            1 osds down
            Degraded data redundancy: 12030/3601342 objects degraded (0.334%), 3 pgs degraded

  services:
    mon: 3 daemons, quorum scp-mon-01,scp-mon-02,scp-mon-03 (age 2w)
    mgr: scp-mon-01.aqwxyz(active, since 2w), standbys: scp-mon-02.bcdefg
    osd: 24 osds: 23 up (since 4m), 24 in (since 3d)
    rgw: 2 daemons active (2 hosts, 1 zones)

  data:
    pools:   7 pools, 193 pgs
    objects: 1.20M objects, 4.5 TiB
    usage:   14 TiB used, 86 TiB / 100 TiB avail
    pgs:     190 active+clean
             3   active+undersized+degraded

  io:
    client:   12 MiB/s rd, 3.4 MiB/s wr, 410 op/s rd, 88 op/s wr
    recovery: 45 MiB/s, 11 objects/s
```
**확인 내용**: 클러스터 한 화면 요약. health 등급, mon 쿼럼 구성·age, mgr active/standby, **osd up/in 불일치(여기선 23 up / 24 in → 1개 down)**, PG 상태 분포(active+clean 외 항목이 장애 신호), 클라이언트 I/O 및 recovery 진행 여부. RCA의 출발점.

### `ceph health detail`
```
HEALTH_WARN 1 osds down; Degraded data redundancy: 12030/3601342 objects degraded (0.334%), 3 pgs degraded
[WRN] OSD_DOWN: 1 osds down
    osd.7 (root=default,host=scp-osd-03) is down
[WRN] PG_DEGRADED: Degraded data redundancy: 12030/3601342 objects degraded (0.334%), 3 pgs degraded
    pg 4.1a is active+undersized+degraded, acting [12,5,2147483647]
    pg 4.2c is active+undersized+degraded, acting [9,18,2147483647]
    pg 7.05 is active+undersized+degraded, acting [3,21,2147483647]
```
**확인 내용**: 각 health 체크의 **구체 대상**. 어떤 OSD가 어느 host에서 down인지, 어떤 PG가 degraded이고 acting set의 결손 위치(`2147483647`=NONE, 복제본 1개 누락). HEALTH_WARN/ERR의 직접 원인 목록.

### `ceph df detail`
```
--- RAW STORAGE ---
CLASS     SIZE    AVAIL     USED  RAW USED  %RAW USED
hdd     90 TiB   78 TiB   12 TiB    12 TiB      13.33
ssd     10 TiB    8 TiB    2 TiB     2 TiB      20.00
TOTAL  100 TiB   86 TiB   14 TiB    14 TiB      14.00

--- POOLS ---
POOL                   ID  PGS   STORED  OBJECTS     USED  %USED  MAX AVAIL  QUOTA OBJECTS  QUOTA BYTES  DIRTY  USED COMPR  UNDER COMPR
.mgr                    1    1  449 KiB        2  1.3 MiB      0     24 TiB              0            0      0          0 B          0 B
.rgw.root               2   32   1.3 KiB        4   48 KiB      0     24 TiB              0            0      0          0 B          0 B
default.rgw.meta        6   32   2.1 KiB       11   96 KiB      0     24 TiB              0            0      0          0 B          0 B
default.rgw.buckets.data 8  128   4.4 TiB    1.19M   13 TiB  15.34     24 TiB              0            0      0          0 B          0 B
cephfs_data            10   32   120 GiB    31.0k  360 GiB   0.49     24 TiB              0            0      0          0 B          0 B
```
**확인 내용**: 클래스별 raw 용량/사용률, **풀별 STORED(논리)/USED(복제 포함 물리)/%USED/MAX AVAIL**. near-full 임박 풀, EC vs 3-replica의 USED:STORED 비율, 쿼터 설정, 압축 효과 확인. 용량 장애·MAX AVAIL 고갈 진단.

### `ceph versions`
```json
{
    "mon": { "ceph version 18.2.4 (...) reef (stable)": 3 },
    "mgr": { "ceph version 18.2.4 (...) reef (stable)": 2 },
    "osd": {
        "ceph version 18.2.4 (...) reef (stable)": 23,
        "ceph version 18.2.2 (...) reef (stable)": 1
    },
    "mds": { "ceph version 18.2.4 (...) reef (stable)": 2 },
    "rgw": { "ceph version 18.2.4 (...) reef (stable)": 2 },
    "overall": {
        "ceph version 18.2.4 (...) reef (stable)": 32,
        "ceph version 18.2.2 (...) reef (stable)": 1
    }
}
```
**확인 내용**: 데몬 종류별 버전 분포. **혼합 버전(여기선 osd 1개가 18.2.2)** 은 미완료 업그레이드·롤백 흔적이며, 호환성/성능 이상의 단서. 업그레이드 중단 장애 진단 핵심.

### `ceph features`
```json
{
    "mon": [ { "features": "0x3f01cfbffffdffff", "release": "luminous", "num": 3 } ],
    "osd": [ { "features": "0x3f01cfbffffdffff", "release": "luminous", "num": 24 } ],
    "client": [
        { "features": "0x2f018fb87aa4aafe", "release": "luminous", "num": 5 },
        { "features": "0x3f01cfbffffdffff", "release": "luminous", "num": 12 }
    ],
    "mgr": [ { "features": "0x3f01cfbffffdffff", "release": "luminous", "num": 2 } ]
}
```
**확인 내용**: 연결 주체별 feature bit/최소 릴리스. `upmap-read` 등 신기능 사용 전제(모든 client가 특정 릴리스 이상)를 충족하는지, 구버전 클라이언트 잔존 여부 확인.

### `ceph node ls`
```json
{
    "mon": { "scp-mon-01": ["scp-mon-01"], "scp-mon-02": ["scp-mon-02"], "scp-mon-03": ["scp-mon-03"] },
    "osd": { "scp-osd-01": [0,1,2,3], "scp-osd-02": [4,5,6,7], "scp-osd-03": [8,9,10,11] },
    "mds": { "scp-mds-01": ["scp-mds-01"] },
    "mgr": { "scp-mon-01": ["scp-mon-01"], "scp-mon-02": ["scp-mon-02"] }
}
```
**확인 내용**: 데몬↔호스트 매핑. 특정 호스트에 OSD/데몬이 몰려 있는지(장애 도메인 위험), 호스트 단위 장애 시 영향 범위 산정.

### `ceph log last 2000`
```
2026-06-25T05:18:42.114+0900 mon.scp-mon-01 (mon.0) 882003 : cluster [WRN] Health check failed: 1 osds down (OSD_DOWN)
2026-06-25T05:18:42.660+0900 osd.7 (osd.7) 12 : cluster [WRN] Monitor daemon marked osd.7 down, but it is still running
2026-06-25T05:18:55.901+0900 mon.scp-mon-01 (mon.0) 882010 : cluster [INF] osd.7 failed (root=default,host=scp-osd-03) ...
```
**확인 내용**: 최근 클러스터 이벤트 타임라인. 장애 발생 순간(누가 언제 down/up, flag set, health 전이)을 시계열로 재구성. RCA의 1차 사료.

### `ceph report` (발췌)
```json
{
    "cluster_fingerprint": "…",
    "version": "18.2.4",
    "commit": "…",
    "timestamp": "2026-06-25T05:20:00.123456",
    "health": { "status": "HEALTH_WARN", "checks": { "OSD_DOWN": { … } } },
    "monmap": { … }, "osdmap": { … }, "pgmap": { … }, "fsmap": { … },
    "crashes": { … }
    …
}
```
**확인 내용**: monmap/osdmap/pgmap/fsmap/health/crash를 **단일 JSON으로 통합**한 오프라인 분석용 스냅샷. 클러스터 미접속 상태에서 전체 상태를 한 파일로 재구성.
**⚠️ 운영 부하(§4.6) {L2}**: active mgr가 전체 맵을 한 번에 직렬화 → 대형 클러스터에서 mgr CPU/메모리 순간 점유, 수십 MB. 1회·별도 파일·`HEALTH_ERR`나 대규모 recovery 중이면 자동 skip.

---

# 3. MON / 쿼럼 / 시계

### `ceph mon stat`
```
e3: 3 mons at {scp-mon-01=[v2:10.0.0.11:3300/0,v1:10.0.0.11:6789/0],scp-mon-02=[v2:10.0.0.12:3300/0,v1:10.0.0.12:6789/0],scp-mon-03=[v2:10.0.0.13:3300/0,v1:10.0.0.13:6789/0]}, election epoch 48, leader 0 scp-mon-01, quorum 0,1,2 scp-mon-01,scp-mon-02,scp-mon-03
```
**확인 내용**: monmap epoch, mon 주소(v2/v1 포트), election epoch, **현재 리더와 쿼럼 멤버**. 쿼럼 결손(예: 3개 중 2개만 quorum) 즉시 식별.

### `ceph mon dump`
```
epoch 3
fsid 3a5f8b2c-1d4e-4f9a-9c7b-2e6a1f0d8b34
last_changed 2026-06-01T09:12:33.481122+0900
created 2025-11-02T01:00:10.002001+0900
min_mon_release 18 (reef)
0: [v2:10.0.0.11:3300/0,v1:10.0.0.11:6789/0] mon.scp-mon-01
1: [v2:10.0.0.12:3300/0,v1:10.0.0.12:6789/0] mon.scp-mon-02
2: [v2:10.0.0.13:3300/0,v1:10.0.0.13:6789/0] mon.scp-mon-03
```
**확인 내용**: monmap 상세. `min_mon_release`(업그레이드 완료 수준), mon 추가/제거 이력(`last_changed`), 각 mon의 rank·주소.

### `ceph quorum_status`
```json
{
    "election_epoch": 48,
    "quorum": [0, 1, 2],
    "quorum_names": ["scp-mon-01", "scp-mon-02", "scp-mon-03"],
    "quorum_leader_name": "scp-mon-01",
    "monmap": { "epoch": 3, "min_mon_release_name": "reef", "mons": [ … ] }
}
```
**확인 내용**: 쿼럼 멤버·리더의 기계 판독본. mon down 시 `quorum` 배열이 줄어듦 → 쿼럼 손실 위험(과반 미달 시 클러스터 정지) 판정.

### `chronyc tracking`
```
Reference ID    : 0A000001 (ntp.internal)
Stratum         : 3
System time     : 0.000031 seconds slow of NTP time
Last offset     : -0.000012 seconds
RMS offset      : 0.000045 seconds
```
**확인 내용**: 호스트 시계 동기 상태. **System time/offset이 수십~수백 ms로 벌어지면 `MON_CLOCK_SKEW` 유발** → mon 쿼럼 불안정. 시계 원인 장애 판별.

### `timedatectl`
```
               Local time: Thu 2026-06-25 05:20:01 KST
           Universal time: Wed 2026-06-24 20:20:01 UTC
                 NTP service: active
System clock synchronized: yes
```
**확인 내용**: NTP 동기 활성/동기화 여부, 타임존. `synchronized: no`면 skew 위험 선제 식별.

---

# 4. MGR

### `ceph mgr dump` (발췌)
```json
{
    "epoch": 102,
    "active_gid": 814052,
    "active_name": "scp-mon-01.aqwxyz",
    "active_addrs": { "addrvec": [ { "type": "v2", "addr": "10.0.0.11:6800/123", … } ] },
    "available": true,
    "standbys": [ { "gid": 814060, "name": "scp-mon-02.bcdefg", … } ],
    "modules": ["balancer", "cephadm", "dashboard", "iostat", "rgw"],
    "services": { "dashboard": "https://10.0.0.11:8443/", "prometheus": "http://10.0.0.11:9283/" }
    …
}
```
**확인 내용**: active mgr와 standby 목록, **`available: true`(mgr 정상)**, 활성 모듈, 노출 서비스 URL. mgr 페일오버·모듈 로드 이상 진단.

### `ceph mgr module ls` (요약)
```
MODULE              
balancer    on (always on)
cephadm     on
dashboard   on
rgw         on
iostat      on
...
nfs         -
```
**확인 내용**: 어떤 mgr 모듈이 활성인지. cephadm/dashboard/rgw 등 운영 핵심 모듈 활성 여부, 장애 시 비활성 모듈 확인.

### `ceph mgr services`
```json
{ "dashboard": "https://10.0.0.11:8443/", "prometheus": "http://10.0.0.11:9283/" }
```
**확인 내용**: mgr가 노출하는 엔드포인트 실제 주소. 모니터링(Prometheus) 연동·대시보드 접근 경로 확인.

### `ceph balancer status`
```json
{
    "active": true,
    "last_optimize_duration": "0:00:00.001174",
    "last_optimize_started": "Wed Jun 25 05:10:18 2026",
    "mode": "upmap",
    "no_optimization_needed": true,
    "optimize_result": "Unable to find further optimization, or pool(s) pg_num is decreasing, or distribution is already perfect",
    "plans": []
}
```
**확인 내용**: 밸런서 on/off, 모드(upmap 등), 마지막 최적화 결과. **`Too many objects ... are misplaced`** 류 메시지는 진행 중 리밸런스를, "distribution is already perfect"는 균형 상태를 의미. PG 편중 원인 진단.

### `ceph progress`
```
Global Recovery Event (33s)
    [=========================...................] (remaining: 18s)
```
(이벤트 없을 때)
```
No events in progress
```
**확인 내용**: recovery/backfill/업그레이드 등 진행 중 작업과 진척률·예상 잔여시간. 부하·지연의 원인이 진행 중 작업인지 식별.

---

# 5. OSD / 디바이스

### `ceph osd tree`
```
ID   CLASS  WEIGHT    TYPE NAME            STATUS  REWEIGHT  PRI-AFF
 -1         100.0000  root default
 -3          33.3333      host scp-osd-01
  0    hdd    8.3333          osd.0            up   1.00000  1.00000
  1    hdd    8.3333          osd.1            up   1.00000  1.00000
 -5          33.3333      host scp-osd-03
  7    hdd    8.3333          osd.7          down   1.00000  1.00000
```
**확인 내용**: CRUSH 계층(root→host→osd), 각 OSD의 **STATUS(up/down)**, REWEIGHT, weight. down OSD의 위치, host 단위 결손, weight 이상 즉시 파악.

### `ceph osd df tree`
```
ID  CLASS  WEIGHT   REWEIGHT  SIZE     RAW USE  DATA     OMAP    META    AVAIL    %USE   VAR   PGS  STATUS  TYPE NAME
-1         100.000         -  100 TiB   14 TiB   14 TiB  120 MiB  60 GiB   86 TiB  14.00  1.00    -          root default
 0    hdd   8.3333   1.00000  8.3 TiB  1.4 TiB  1.4 TiB   12 MiB  6.0 GiB  6.9 TiB  16.80  1.20   45      up      osd.0
 7    hdd   8.3333   1.00000  8.3 TiB  0.9 TiB  0.9 TiB    8 MiB  4.0 GiB  7.4 TiB  10.80  0.77   38    down      osd.7
```
**확인 내용**: OSD별 사용률(%USE)·편차(VAR)·PG 수. **near-full 임박 OSD, 분포 불균형(VAR 1.0에서 크게 벗어남), OMAP/META 비대(RGW 인덱스 폭증 신호)** 진단.

### `ceph osd perf`
```
osd  commit_latency(ms)  apply_latency(ms)
  0                   2                   2
  1                   3                   3
  7                 178                 178
 12                 151                 151
```
**확인 내용**: OSD별 commit/apply 레이턴시(ms). **수십~수백 ms로 튀는 OSD = 느린/노후 디스크 후보**(여기선 osd.7, osd.12). 단일 느린 디스크가 클러스터 전체를 끌어내리는 slow-ops 원인 특정.

### `ceph osd stat`
```
24 osds: 23 up (since 4m), 24 in (since 3d); epoch: e88421
```
**확인 내용**: up/in 카운트와 osdmap epoch. up≠in이면 down OSD 존재. epoch 급증은 잦은 up/down(flapping) 의심.

### `ceph osd dump` (발췌)
```
epoch 88421
fsid 3a5f8b2c-...
flags sortbitwise,recovery_deletes,purged_snapdirs,pglog_hardlimit
pool 8 'default.rgw.buckets.data' replicated size 3 min_size 2 crush_rule 0 object_hash rjenkins pg_num 128 pgp_num 128 autoscale_mode on last_change 84102 application rgw
max_osd 24
osd.7 down in weight 1 up_from 88100 up_thru 88400 down_at 88419 ... 
```
**확인 내용**: osdmap 상세. **클러스터 flags(noout/norecover 등 운영 플래그 잔존 여부)**, 풀별 size/min_size/pg_num/autoscale/application, OSD별 up/down 상태와 epoch 이력. 설정 오류·잔존 플래그 진단.

### `ceph osd blocked-by`
```
osd  num_blocked
  7            3
```
(차단 없을 때는 빈 출력)
**확인 내용**: peering을 막고 있는 OSD와 그 영향 PG 수. PG가 inactive/peering에 갇힌 직접 원인 OSD 특정.

### `ceph osd pool autoscale-status`
```
POOL                      SIZE  TARGET SIZE  RATE  RAW CAPACITY  RATIO  TARGET RATIO  EFFECTIVE RATIO  BIAS  PG_NUM  NEW PG_NUM  AUTOSCALE  BULK
default.rgw.buckets.data  4.4T               3.0   100.0T        0.132                                 1.0   128                 on         False
cephfs_data               120G               3.0   100.0T        0.003                                 1.0    32                 on         False
```
**확인 내용**: 풀별 자동 PG 스케일러 판단. **NEW PG_NUM이 채워져 있으면 PG 수 조정 예정**(향후 리밸런스 부하 예고), autoscale on/off, target ratio 설정 확인.

### `ceph osd metadata` (osd.0 발췌)
```json
{
    "id": 0,
    "hostname": "scp-osd-01",
    "osd_objectstore": "bluestore",
    "bluestore_bdev_type": "ssd",
    "devices": "nvme0n1",
    "device_ids": "nvme0n1=SAMSUNG_MZQL21T9_S64...",
    "default_device_class": "ssd",
    "ceph_version": "ceph version 18.2.4 (...) reef (stable)"
}
```
**확인 내용**: OSD별 백엔드(bluestore), 물리 디바이스명·모델·시리얼, device class, 데몬 버전. **느린 OSD(앞 perf)와 디스크 모델 대조**, WAL/DB 분리 여부 추적.

### `ceph device ls`
```
DEVICE                     HOST:DEV         DAEMONS  WEAR  LIFE EXPECTANCY
SAMSUNG_MZQL2_S64A...       scp-osd-01:nvme0n1  osd.0   1%
SEAGATE_ST8000_ZA1...       scp-osd-03:sda      osd.7   -    2026-08-10
```
**확인 내용**: 디바이스↔데몬 매핑, WEAR(SSD 마모도), **LIFE EXPECTANCY(예측 수명, 날짜가 가까우면 교체 경고)**. 디스크 노후로 인한 잠재 장애 선제 식별.

### `ceph device get-health-metrics <devid>` (발췌)
```json
{
    "20260625-051000": {
        "dev": "/dev/sda",
        "scsi_grown_defect_list": 0,
        "scsi_error_counter_log": { "read": { "total_uncorrected_errors": 0 }, "write": { "total_uncorrected_errors": 0 } },
        "temperature": { "current": 38 }
        …
    }
}
```
**확인 내용**: 저장된 SMART 스냅샷(시간별). uncorrected error 증가, defect list 증가, 온도 이상 → 디스크 물리 열화 추적. (디바이스를 직접 두드리지 않고 저장값 읽기)

### `ceph tell osd.7 perf dump` (발췌)
```json
{
    "osd": {
        "op_latency": { "avgcount": 1820345, "sum": 4521.3, "avgtime": 0.00248 },
        "op_w_latency": { "avgcount": 502311, "sum": 3110.8, "avgtime": 0.00619 },
        "numpg": 38
    },
    "bluestore": {
        "kv_sync_lat": { "avgcount": 990221, "sum": 88.4, "avgtime": 0.0000893 },
        "state_kv_commiting_lat": { "avgcount": 990221, "sum": 60.1, "avgtime": 0.0000607 }
    }
    …
}
```
**확인 내용**: 해당 OSD 내부 성능 카운터(op 레이턴시, BlueStore KV/커밋 지연 등). 느린 OSD의 **병목 계층(네트워크 vs RocksDB vs 디바이스)** 분해. Reef에서 `perf dump`는 deprecated이므로 후속 명령 `ceph tell osd.7 counter dump`(라벨 기반 카운터)를 함께 수집한다.
**⚠️ 운영 부하(§4.6) {L1}**: 개별 호출은 가볍지만 OSD 수 N배. down/near-full/high-latency OSD 우선 **샘플링**(상한 N=20). 전체는 `--all-osds`. (dump_historic_ops/ops_in_flight/blocked_ops도 동일 샘플링)

### `ceph tell osd.7 dump_historic_ops` (발췌)
```json
{
    "size": 20,
    "duration": 600,
    "ops": [
        {
            "description": "osd_op(client.4471.0:99 8.1a ...)",
            "initiated_at": "2026-06-25T05:17:01.221+0900",
            "age": 179.4,
            "duration": 5.213,
            "type_data": { "flag_point": "waiting for sub ops", … }
        }
    ]
}
```
**확인 내용**: 최근 느린 op 표본과 각 op의 **체류 단계(flag_point)**. "waiting for sub ops"=복제본 OSD 대기, "waiting for rw locks" 등으로 지연 지점 특정.

### `ceph tell osd.7 dump_ops_in_flight`
```json
{ "ops": [], "num_ops": 0 }
```
**확인 내용**: 현재 처리 중 op. num_ops가 높고 오래 머무는 op이 있으면 해당 OSD 정체. (dump_blocked_ops도 동일 형식, 차단된 op만)

---

# 6. PG

### `ceph pg stat`
```
193 pgs: 190 active+clean, 3 active+undersized+degraded; 4.5 TiB data, 14 TiB used, 86 TiB / 100 TiB avail; 12030/3601342 objects degraded (0.334%)
```
**확인 내용**: 전체 PG 수와 상태 분포 1줄 요약. active+clean 외 상태 비중으로 건강도 즉시 판정.

### `ceph pg dump pgs_brief` (발췌)
```
PG_STAT  STATE                          UP        UP_PRIMARY  ACTING       ACTING_PRIMARY
4.1a     active+undersized+degraded     [12,5]    12          [12,5]       12
4.2c     active+undersized+degraded     [9,18]    9           [9,18]       9
8.05     active+clean                   [3,21,11] 3           [3,21,11]    3
```
**확인 내용**: PG별 상태와 UP/ACTING set. **acting set 멤버 수가 size보다 적으면 undersized**(복제본 부족), UP≠ACTING이면 데이터 이동 중. 데이터 redundancy 위험 PG 목록화.

### `ceph pg dump` (full, 발췌)  ⚠️ {L2}
```
PG_STAT  OBJECTS  ...  STATE         ...  LAST_SCRUB           SCRUB_STAMP                  LAST_DEEP_SCRUB      DEEP_SCRUB_STAMP
8.05        9210  ...  active+clean  ...  84021'120            2026-06-18T02:11:09.4+0900   84001'118            2026-06-12T01:50:33.1+0900
...
OSD_STAT  USED     AVAIL    USED_RAW  TOTAL
0         1.4 TiB  6.9 TiB  1.4 TiB   8.3 TiB
```
**확인 내용**: 전 PG의 **scrub/deep-scrub 타임스탬프**(scrub 지연·PG_NOT_SCRUBBED RCA), OSD별 PG 분포 정밀표. `pgs_brief`엔 없는 데이터.
**⚠️ 운영 부하(§4.6)**: mgr가 전 PG 레코드를 직렬화 → PG 수 비례 부하. 기본 비활성, `--full-pg-dump`로만, 비피크 권장.

### `ceph pg ls` (발췌)
```
PG    OBJECTS  DEGRADED  MISPLACED  BYTES        OMAP_BYTES*  LOG   STATE                       SINCE  ...
8.05    9210         0          0  38654705664           0  3021  active+clean                  2w
4.1a    1003      4010          0   4203741184           0  1880  active+undersized+degraded    5m
```
**확인 내용**: PG별 객체 수·degraded/misplaced 객체 수·바이트·로그 길이·상태와 지속시간. 큰 PG, log 비대(복구 지연 신호), 오래된 비정상 상태(SINCE) 식별.

### `ceph pg dump_stuck inactive` (예: 정상 시)
```
ok
```
(갇힌 PG 존재 시)
```
PG_STAT  STATE     UP    UP_PRIMARY  ACTING  ACTING_PRIMARY
4.7f     peering   [3,9] 3           [3,9]   3
```
**확인 내용**: inactive/unclean/stale 상태로 **갇힌 PG**(클라이언트 I/O 차단 원인). peering/down/stale의 대상 PG와 관련 OSD를 좁혀 RCA.

### `ceph pg 4.1a query` (발췌)
```json
{
    "snap_trimq": "[]",
    "state": "active+undersized+degraded",
    "up": [12, 5],
    "acting": [12, 5],
    "info": { "stats": { "stat_sum": { "num_objects_degraded": 4010, … } } },
    "recovery_state": [
        { "name": "Started/Primary/Active", "enter_time": "2026-06-25T05:17:00.123+0900",
          "might_have_unfound": [ { "osd": "7", "status": "osd is down" } ] }
    ]
}
```
**확인 내용**: 특정 PG의 상세 진단. recovery_state로 **복구 진행 단계**, `might_have_unfound`로 데이터가 어느 down OSD에 있는지(unfound object 원인) 추적. 가장 깊은 PG 단위 RCA.

---

# 7. CRUSH

### `ceph osd crush tree`
```
ID   CLASS  WEIGHT    TYPE NAME
 -1         100.0000  root default
 -3          33.3333      host scp-osd-01
  0    ssd    8.3333          osd.0
 -7          33.3333      rack rack-a
 -5          33.3333          host scp-osd-03
  7    hdd    8.3333              osd.7
```
**확인 내용**: CRUSH 계층 구조와 device class 배치. 장애 도메인(host/rack) 구성, class 혼재, weight 합계 검증.

### `ceph osd crush class ls`
```json
["hdd", "ssd"]
```
**확인 내용**: 정의된 device class. 풀의 crush rule이 의도한 class로 매핑되는지 대조.

### `ceph osd crush rule ls`
```json
["replicated_rule", "rgw-ec-rule", "ssd-rule"]
```
**확인 내용**: CRUSH 룰 목록. 풀이 참조하는 룰 존재 여부.

### `ceph osd crush rule dump rgw-ec-rule` (발췌)
```json
{
    "rule_id": 1,
    "rule_name": "rgw-ec-rule",
    "type": 3,
    "steps": [
        { "op": "take", "item": -1, "item_name": "default~hdd" },
        { "op": "chooseleaf_indep", "num": 0, "type": "host" },
        { "op": "emit" }
    ]
}
```
**확인 내용**: 룰의 배치 알고리즘(take 대상 class, choose 도메인 type). **장애 도메인이 host인지 osd인지**(host면 호스트 단위 내고장성), EC/replica용 chooseleaf 모드 검증. 데이터 안전성 설계 확인.

### `ceph osd crush dump` (발췌)
```json
{
    "devices": [ { "id": 0, "name": "osd.0", "class": "ssd" }, … ],
    "types": [ { "type_id": 1, "name": "host" }, { "type_id": 3, "name": "rack" }, … ],
    "buckets": [ … ], "rules": [ … ],
    "tunables": { "profile": "jewel", "chooseleaf_vary_r": 1, "straw_calc_version": 1 }
}
```
**확인 내용**: 전체 CRUSH 맵(JSON). tunables 프로파일(구버전 tunable 잔존 시 데이터 이동·호환 이슈), 버킷/룰 전수.

---

# 8. Pool / EC

### `ceph osd pool ls detail` (발췌)
```
pool 8 'default.rgw.buckets.data' replicated size 3 min_size 2 crush_rule 0 object_hash rjenkins pg_num 128 pgp_num 128 autoscale_mode on last_change 84102 lfor 0/0/0 flags hashpspool,selfmanaged_snaps stripe_width 0 application rgw
pool 12 'cephfs_ec' erasure profile standard_8_2 size 10 min_size 9 crush_rule 1 pg_num 64 pgp_num 64 autoscale_mode on flags hashpspool,ec_overwrites stripe_width 32768 application cephfs
```
**확인 내용**: 풀별 핵심 설정. **size/min_size(min_size=1이면 데이터 안전 위험), replicated vs erasure, EC 프로파일, ec_overwrites/selfmanaged_snaps flags, application 태그**. 설정 오류·내고장성 정책 검증.

### `ceph osd lspools`
```
1 .mgr
2 .rgw.root
8 default.rgw.buckets.data
10 cephfs_data
12 cephfs_ec
```
**확인 내용**: 풀 ID↔이름 매핑. 다른 출력의 풀 ID 해석 기준.

### `ceph osd pool stats`
```
pool .mgr id 1
  nothing is going on

pool default.rgw.buckets.data id 8
  client io 12 MiB/s rd, 3.4 MiB/s wr, 410 op/s rd, 88 op/s wr

pool cephfs_data id 10
  client io 2.1 MiB/s wr, 14 op/s wr
  recovery io 45 MiB/s, 11 objects/s
```
**확인 내용**: **풀별 클라이언트 I/O·복구 I/O 분해**. 어느 풀이 핫스팟인지(`ceph -s`의 전체 I/O를 풀 단위로 쪼갬), 특정 풀에서만 진행 중인 recovery 식별.

### `ceph osd erasure-code-profile get standard_8_2`
```
crush-device-class=hdd
crush-failure-domain=host
k=8
m=2
plugin=jerasure
technique=reed_sol_van
```
**확인 내용**: EC 프로파일의 k/m(8+2=오버헤드 1.25x, 2개 결손 허용), **failure-domain(host면 호스트 2개까지 손실 견딤)**, 플러그인(jerasure/isa 등). EC 내고장성·효율 검증. (`erasure-code-profile ls`로 프로파일 목록 먼저 확인)

---

# 9. Config

### `ceph config dump` (발췌)
```
WHO              MASK  LEVEL     OPTION                              VALUE                        RO
global                 advanced  osd_pool_default_size               3
global                 basic     container_image                     quay.io/ceph/ceph:v18.2.4    *
client.rgw             advanced  rgw_keystone_url                    https://keystone.local:5000
client.rgw             advanced  rgw_s3_auth_use_keystone            true
client.rgw             advanced  rgw_crypt_s3_kms_backend            vault
client.rgw             advanced  rgw_crypt_vault_addr                https://vault.local:8200
mgr                    advanced  mgr/balancer/active                 true
```
**확인 내용**: **명시적으로 설정된 비-기본값만** 표시. RGW의 keystone/vault 연동 키, 기본 풀 size, container_image(배포 버전) 등 운영 커스터마이즈 전수. (기본값 파라미터는 안 보이므로 §`config show` 병행)

### `ceph config-key dump` (레닥션 후)
```json
{
    "config/global/osd_pool_default_size": "3",
    "mgr/cephadm/inventory": "…",
    "rgw/keystone/admin_password": "***REDACTED***"
}
```
**확인 내용**: mgr 모듈·cephadm이 사용하는 KV 저장소. 시크릿은 마스킹. cephadm 인벤토리/스펙 저장값 확인.

### `ceph config show client.rgw.scp-rgw-01` (발췌)
```
NAME                          VALUE                       SOURCE
rgw_crypt_s3_kms_backend      vault                       mon
rgw_crypt_vault_addr          https://vault.local:8200    mon
rgw_crypt_vault_auth          token                       mon
rgw_s3_auth_use_keystone      true                        mon
rgw_keystone_url              https://keystone.local:5000 mon
```
**확인 내용**: 해당 RGW 데몬의 **effective 값**(기본값 포함). `config dump`에 안 잡히는 vault/keystone 파라미터까지 실제 적용값으로 확인 → 연동 여부 확정.

---

# 10. Orchestrator / cephadm

### `ceph orch ls`
```
NAME                       PORTS        RUNNING  REFRESHED  AGE  PLACEMENT
mgr                                          2/2  5m ago     7M   count:2
mon                                          3/3  5m ago     7M   count:3
osd                                         23/24 5m ago     7M
rgw.default                ?:80             2/2  5m ago     6M   count:2
mds.cephfs                                   2/2  5m ago     5M   count:2
```
**확인 내용**: 서비스별 **목표 대비 실행 수(RUNNING 23/24 → OSD 1개 미기동)**, 포트, 배치 정책, 마지막 갱신. 데몬 배포 정합성·미기동 서비스 식별.

### `ceph orch ps` (발췌)
```
NAME                   HOST         PORTS   STATUS         REFRESHED  AGE  MEM USE  VERSION  IMAGE ID
osd.7                  scp-osd-03           error          5m ago     3d   -        18.2.2   <unknown>
rgw.default.scp-rgw-01 scp-rgw-01   *:80    running (6M)   5m ago     6M   210M     18.2.4   2bc0b0f4d3a1
mon.scp-mon-01         scp-mon-01           running (2w)   5m ago     7M   512M     18.2.4   2bc0b0f4d3a1
```
**확인 내용**: 데몬 단위 상태/호스트/버전/메모리/이미지. **error/stopped 데몬, 버전 불일치(osd.7=18.2.2), 이미지 ID 불일치**를 데몬 레벨로 특정.

### `ceph orch host ls`
```
HOST         ADDR        LABELS           STATUS
scp-mon-01   10.0.0.11   _admin mon mgr
scp-osd-03   10.0.0.23   osd              Offline
```
**확인 내용**: 호스트 인벤토리와 라벨(_admin/mon/osd), **STATUS(Offline이면 cephadm이 해당 호스트 접근 불가)**. 호스트 단위 관리 연결성 진단.

### `ceph orch device ls` (발췌)
```
HOST        PATH      TYPE  DEVICE ID            SIZE  AVAILABLE  REJECT REASONS
scp-osd-03  /dev/sdb  hdd   SEAGATE_ST8000_...   8.0T  No         Insufficient space / locked
scp-osd-04  /dev/sdc  hdd   SEAGATE_ST8000_...   8.0T  Yes
```
**확인 내용**: 물리 디바이스 인벤토리와 OSD 배치 가능 여부(AVAILABLE), 거부 사유. 신규 OSD 배치 실패·미사용 디스크 원인 파악.

### `ceph orch upgrade status`
```json
{ "target_image": null, "in_progress": false, "services_complete": [], "message": "" }
```
(진행 중)
```json
{ "target_image": "quay.io/ceph/ceph:v18.2.4", "in_progress": true, "services_complete": ["mgr","mon"], "message": "Currently upgrading osd daemons" }
```
**확인 내용**: 업그레이드 진행 여부와 단계. **혼합 버전(§ceph versions)의 원인이 미완료 업그레이드인지** 확정.

### `ceph cephadm config-check ls` (발췌)
```
NAME              HEALTHCHECK                   STATUS   DESCRIPTION
kernel_security   CEPHADM_CHECK_KERNEL_LSM      enabled  check SELinux/AppArmor consistency
public_network    CEPHADM_CHECK_PUBLIC_MEMBERSHIP enabled check host public network membership
os_subscription   CEPHADM_CHECK_SUBSCRIPTION    enabled  check subscription state
```
**확인 내용**: cephadm 자동 점검 항목과 활성 여부. 호스트 간 커널/네트워크/시간 정합성 점검이 켜져 있는지 확인.

### `ceph orch host ok-to-stop scp-osd-03`
```
It is NOT safe to stop host scp-osd-03: 3 PGs would become unavailable
```
(안전 시)
```
It is presently safe to stop host: scp-osd-03
```
**확인 내용**: 해당 호스트 중단 시 데이터 가용성 영향 **평가만**(실제 중단 없음). 유지보수 가능 시점 판단. (수집 시 정보로만 활용)

### `cephadm check-host` (호스트 로컬)
```
podman (/usr/bin/podman) version 4.6.1 is present
systemctl is present
lvcreate is present
chrony is active
Hostname "scp-osd-03" matches what is expected.
Host looks OK
```
**확인 내용**: 노드의 cephadm 전제(컨테이너 런타임, lvm, 시간동기, hostname) 충족 여부. 호스트가 Offline/배포 실패인 근본 원인(런타임 누락 등) 식별.

### `cephadm ls` (호스트 로컬, 발췌)
```json
[
  { "style": "cephadm:v1", "name": "osd.7", "fsid": "3a5f8b2c-...",
    "systemd_unit": "ceph-3a5f8b2c@osd.7", "enabled": true, "state": "error",
    "container_id": null, "version": "18.2.2", "started": null },
  { "style": "cephadm:v1", "name": "mon.scp-mon-01", "state": "running",
    "version": "18.2.4", "started": "2026-06-11T01:02:03Z" }
]
```
**확인 내용**: 해당 호스트의 Ceph 데몬을 **mgr/orchestrator 없이 직접** 열거. `ceph orch ps`가 mgr 장애로 안 될 때의 대체 수단. 데몬별 systemd 유닛·state·버전·기동시각으로 로컬 장애 진단.

---

# 11. RGW

### `radosgw-admin realm list`
```json
{ "default_info": "16c78bd1-1920-4e23-8c7b-ebf15d982458", "realms": ["scp-realm"] }
```
**확인 내용**: realm 목록과 기본 realm. multisite 구성의 최상위 엔터티 존재 확인.

### `radosgw-admin zonegroup list` / `zone list`
```json
{ "default_info": "2761ad42-...", "zonegroups": ["scp-zg"] }
{ "default_info": "66df8c0a-...", "zones": ["scp-zone1"] }
```
**확인 내용**: zonegroup/zone 구성. 단일/멀티사이트 여부와 기본 zone 식별.

### `radosgw-admin zonegroup get` (발췌)
```json
{
    "id": "2761ad42-...",
    "name": "scp-zg",
    "is_master": "true",
    "endpoints": ["http://scp-rgw-01:80"],
    "hostnames": ["s3.scp.local"],
    "master_zone": "66df8c0a-...",
    "zones": [ { "name": "scp-zone1", "endpoints": ["http://scp-rgw-01:80"] } ]
}
```
**확인 내용**: zonegroup의 **엔드포인트·접속 hostname·마스터 zone·소속 zone 목록**. S3 가상호스트 도메인(hostnames) 설정 오류, 마스터 zone 지정 확인. multisite 토폴로지 RCA.

### `radosgw-admin period get` (발췌)
```json
{
    "id": "a1b2c3d4-...",
    "epoch": 3,
    "realm_id": "16c78bd1-...",
    "realm_name": "scp-realm",
    "master_zonegroup": "2761ad42-...",
    "master_zone": "66df8c0a-..."
}
```
**확인 내용**: 커밋된 period(멀티사이트 설정 버전)와 epoch, 마스터 zonegroup/zone. **period가 사이트 간 어긋나면(epoch 불일치) 설정 전파 실패** → sync 중단 RCA의 단서.

### `radosgw-admin sync status` (멀티사이트)
```
          realm beeea955-8341-41cc-a046-46de2d5ddeb9 (scp-realm)
      zonegroup 2761ad42-fd71-4170-87c6-74c20dd1e334 (scp-zg)
           zone 66df8c0a-c67d-4bd7-9975-bc02a549f13e (scp-zone1)
  metadata sync no sync (zone is master)
      data sync source: 7b9273a9-eb59-413d-a465-3029664c73d7 (scp-zone2)
                        syncing
                        full sync: 0/128 shards
                        incremental sync: 128/128 shards
                        data is caught up with source
```
**확인 내용**: 멀티사이트 복제 상태. 마스터/세컨더리 역할, **metadata/data sync 진행률(shards), "caught up" 여부 또는 지연(behind shards)**. 사이트 간 복제 지연·중단 진단. (단일 사이트면 "no sync" 표시)

### `radosgw-admin user list`
```json
["dashboard", "tester", "sync-user"]
```
**확인 내용**: RGW 사용자 목록. 기능 테스트용 `tester`, multisite sync 시스템 유저 존재 확인.

### `radosgw-admin bucket list`
```json
["tester-bucket", "app-logs", "backup-2026"]
```
**확인 내용**: 버킷 목록. 예상 버킷 존재 여부, 비정상 버킷 식별.
**⚠️ 운영 부하(§4.6) {L2}**: 전체 버킷 enumerate → 버킷 수천 개면 메타데이터 풀 부하. `--rgw-full` 가드.

### `radosgw-admin bucket stats --bucket=app-logs` (발췌)
```json
{
    "bucket": "app-logs",
    "num_shards": 11,
    "zonegroup": "2761ad42-...",
    "placement_rule": "default-placement",
    "usage": {
        "rgw.main": { "size": 4521987654, "size_actual": 4530000000, "num_objects": 120345 }
    },
    "bucket_quota": { "enabled": false, "max_objects": -1, "max_size": -1 }
}
```
**확인 내용**: 버킷별 샤드 수·객체 수·사용량·쿼터·placement. **num_objects 대비 num_shards 부족 = 인덱스 핫스팟/성능 저하 신호**, placement_rule로 저장 위치 확인.
**⚠️ 운영 부하(§4.6) {L2}**: 버킷 전체 stats는 버킷 수만큼 omap 조회. 기본은 지목 버킷·상위 K개만, 전체는 `--rgw-full`.

### `radosgw-admin bucket limit check` (발췌)
```json
[
    { "bucket": "app-logs", "num_objects": 120345, "num_shards": 11,
      "objects_per_shard": 10940, "fill_status": "OK" },
    { "bucket": "backup-2026", "num_objects": 2200000, "num_shards": 11,
      "objects_per_shard": 200000, "fill_status": "OVER" }
]
```
**확인 내용**: 버킷별 샤드 채움률. **fill_status가 OVER/WARN이면 reshard 필요**(샤드당 객체 과다 → 인덱스 OSD OMAP 비대·지연). RGW 성능 장애 예방 핵심.
**⚠️ 운영 부하(§4.6) {L2}**: 모든 버킷 인덱스 순회. `--rgw-full`·비피크.

### `radosgw-admin reshard list`
```json
[]
```
**확인 내용**: 대기 중 reshard 작업(나열만, 실행 아님). 비어 있으면 진행 중 reshard 없음. 항목이 있으면 인덱스 재배치 진행 예정.

### `radosgw-admin gc list`
```json
[]
```
**확인 내용**: 삭제 대기(garbage collection) 객체 목록(나열만). 대량 누적 시 삭제 처리 지연 → 공간 미회수 진단.
**⚠️ 운영 부하(§4.6) {L1}**: 큐가 크게 쌓이면 출력이 매우 길어짐. 필요 시 head로 상한.

### `radosgw-admin lc list`
```json
[
    { "bucket": ":app-logs:66df8c0a...", "started": "Thu, 25 Jun 2026 00:10:00 GMT", "status": "COMPLETE" },
    { "bucket": ":backup-2026:66df8c0a...", "started": "Thu, 25 Jun 2026 00:10:00 GMT", "status": "PROCESSING" }
]
```
**확인 내용**: 버킷별 lifecycle(만료/이행) 처리 상태. **status가 계속 PROCESSING이거나 오래된 started면 LC 미동작** → "객체가 만료 정책대로 삭제되지 않음" RCA.

### `radosgw-admin zone get` (레닥션 후, 발췌)
```json
{
    "id": "66df8c0a-...",
    "name": "scp-zone1",
    "system_key": { "access_key": "***REDACTED***", "secret_key": "***REDACTED***" },
    "placement_pools": [
        { "key": "default-placement",
          "val": { "index_pool": "default.rgw.buckets.index",
                   "data_pool": "default.rgw.buckets.data",
                   "data_extra_pool": "default.rgw.buckets.non-ec" } }
    ]
}
```
**확인 내용**: zone의 풀 매핑(index/data/non-ec 풀)과 sync 키(마스킹). **버킷 데이터가 실제 어느 RADOS 풀에 저장되는지** 확정, placement 오설정 진단.

---

# 12. RBD

### `rbd ls -p rbd --long`
```
NAME          SIZE     PARENT  FMT  PROT  LOCK
vm-disk-101   200 GiB            2
vm-disk-102   500 GiB            2         excl
```
**확인 내용**: 풀 내 이미지 목록·크기·포맷·락. 예상 이미지 존재, exclusive-lock 보유 이미지 확인.

### `rbd info rbd/vm-disk-101`
```
rbd image 'vm-disk-101':
        size 200 GiB in 51200 objects
        order 22 (4 MiB objects)
        snapshot_count: 1
        id: 5e9a3b1c2d4f
        block_name_prefix: rbd_data.5e9a3b1c2d4f
        format: 2
        features: layering, exclusive-lock, object-map, fast-diff, deep-flatten
        op_features:
        flags:
```
**확인 내용**: 이미지 메타와 **features**. `object-map`+`fast-diff` 보유 → `rbd du`를 안전하게 실행 가능(없으면 du가 전체 스캔). 스냅샷 수, 4MiB object order 확인.

### `rbd status rbd/vm-disk-102`
```
Watchers:
        watcher=10.0.0.51:0/2998447 client.44127 cookie=140423...
```
(워처 없을 때)
```
Watchers: none
```
**확인 내용**: 이미지를 현재 매핑/사용 중인 클라이언트(watcher). **워처가 남았는데 VM은 죽은 경우 = 좀비 매핑**(이미지 삭제/이동 차단 원인) 진단.

### `rbd mirror pool status rbd --verbose` (미러링/DR 사용 시)
```
health: OK
daemon health: OK
image health: OK
images: 2 total
    2 replaying

vm-disk-101:
  global_id:   3a1f...
  state:       up+replaying
  description: replaying, {"bytes_per_second":1048576.0,"entries_behind_primary":0}
```
**확인 내용**: RBD 미러링(원격 DR 복제) 상태. **state가 up+replaying이 아니거나 entries_behind_primary가 계속 증가하면 복제 지연/중단** → DR RTO 위반 RCA. (미러링 미사용 풀에선 수집 안 함)

### `rbd du -p rbd` (object-map 보유 이미지에서만)
```
NAME         PROVISIONED  USED
vm-disk-101      200 GiB  84 GiB
vm-disk-102      500 GiB  121 GiB
<TOTAL>          700 GiB  205 GiB
```
**확인 내용**: 이미지별 프로비저닝 대비 실사용량(씬 프로비저닝 효율). 풀 용량 산정·과대 프로비저닝 식별.
**⚠️ 운영 부하(§4.6) {L2}**: object-map+fast-diff 미보유 이미지는 전 오브젝트 스캔 → OSD I/O 부하. 기본 비활성(`--rbd-du`), 보유 이미지만 실행하고 나머지는 skip. (용량 분석 옵션이며 장애 RCA 핵심은 아님)

---

# 13. CephFS / MDS

### `ceph fs ls`
```
name: cephfs, metadata pool: cephfs_metadata, data pools: [cephfs_data cephfs_ec ]
```
**확인 내용**: 파일시스템과 메타/데이터 풀 매핑. EC 데이터 풀 사용 여부 확인.

### `ceph fs dump` (발췌)
```
e42
enable_multiple, ever_enabled_multiple: 1,1
default compat: compat={},rocompat={},incompat={1=base v0.20,2=client writeable ranges,...,10=snaprealm v2}
legacy client fscid: 1

Filesystem 'cephfs' (1)
fs_name cephfs
epoch   41
flags   12 joinable allow_snaps allow_multimds_snaps
max_mds 1
in      0
up      {0=44128}
failed
damaged
stopped
data_pools      [10,12]
metadata_pool   9
```
**확인 내용**: FSMap 전체(권위 소스). **max_mds vs in/up(다중 active rank 구성), failed/damaged/stopped rank(메타데이터 손상·MDS 장애), flags(snapshot 허용 등), compat 비트**. `fs status`보다 깊은 MDS 클러스터 상태 RCA.

### `ceph fs status`
```
cephfs - 12 clients
======
RANK  STATE        MDS            ACTIVITY     DNS    INOS   DIRS   CAPS
 0    active   cephfs.scp-mds-01  Reqs:  12 /s  85.2k  84.1k  9210   45.0k
      POOL          TYPE     USED  AVAIL
cephfs_metadata  metadata  2400M   24T
  cephfs_data       data    120G   24T
STANDBY MDS
cephfs.scp-mds-02
```
**확인 내용**: MDS rank별 상태(active/standby), **요청률·캐시(DNS/INOS/CAPS)**, 풀 사용량, standby 존재 여부. MDS 과부하(CAPS·Reqs 급증), standby 부재(페일오버 불가) 진단.

### `ceph mds stat`
```
cephfs:1 {0=cephfs.scp-mds-01=up:active} 1 up:standby
```
**확인 내용**: 한 줄 MDS 요약. active rank 수와 standby 수. degraded/failed rank 즉시 식별.

### `ceph mds metadata` (발췌)
```json
[ { "name": "cephfs.scp-mds-01", "hostname": "scp-mds-01",
    "ceph_version": "ceph version 18.2.4 (...) reef (stable)",
    "mem_total_kb": "16400000", "mem_swap_kb": "0" } ]
```
**확인 내용**: MDS 데몬의 호스트·버전·메모리. MDS OOM/버전 불일치 추적.

### `ceph tell mds.0 session ls` (발췌)
```json
[ { "id": 44127, "client_metadata": { "hostname": "app-node-1", "root": "/" },
    "num_leases": 0, "num_caps": 12044, "state": "open" } ]
```
**확인 내용**: MDS에 붙은 클라이언트 세션과 **보유 caps 수**. 특정 클라이언트의 caps 폭증(MDS 메모리 압박·MDS_CLIENT_RECALL 경고 원인) 식별.
**⚠️ 운영 부하(§4.6) {L2}**: 클라이언트 세션당 1행 → 수천 클라이언트면 출력 大 + MDS 일시 부하. CephFS·MDS 경고 존재 시에만.

### `ceph tell mds.0 dump_blocked_ops`
```json
{ "ops": [], "num_ops": 0 }
```
**확인 내용**: MDS에서 막혀 있는 메타데이터 op. num_ops가 높으면 MDS가 특정 op(예: 잠금 대기)에 정체 → CephFS 응답 지연 RCA. (op 없으면 빈 목록)

---

# 14. Crash

### `ceph crash ls`
```
ID                                                                ENTITY     NEW
2026-06-20T11:02:33.123456Z_a1b2c3d4-...                          osd.12      *
2026-05-30T03:44:10.987654Z_f9e8d7c6-...                          mgr.scp-mon-01
```
**확인 내용**: 최근 크래시 목록과 발생 데몬, **NEW 표시(아직 확인 안 한 신규 크래시)**. 반복 크래시 데몬·시점 파악.

### `ceph crash info <id>` (발췌)
```json
{
    "crash_id": "2026-06-20T11:02:33.123456Z_a1b2c3d4-...",
    "entity_name": "osd.12",
    "ceph_version": "18.2.4",
    "utsname_hostname": "scp-osd-04",
    "process_name": "ceph-osd",
    "stack_sig": "…",
    "backtrace": [ "(ceph::__ceph_assert_fail()+0x...)", "…" ]
}
```
**확인 내용**: 크래시의 데몬·호스트·버전·**백트레이스/assert 시그니처**. 동일 stack_sig 반복 여부로 알려진 버그 매칭, 크래시 RCA.

---

# 15. 인증 (레닥션)

### `ceph auth ls` (레닥션 후, 발췌)
```
osd.0
        key: ***REDACTED***
        caps: [mgr] allow profile osd
        caps: [mon] allow profile osd
        caps: [osd] allow *
client.admin
        key: ***REDACTED***
        caps: [mon] allow *
        caps: [osd] allow *
client.rgw.scp-rgw-01
        key: ***REDACTED***
        caps: [mon] allow rw
        caps: [osd] allow rwx ...
```
**확인 내용**: 엔터티별 권한(caps). key는 마스킹. **과도하거나 부족한 권한**(예: client가 `allow *`), RGW/MDS 클라이언트 caps 적정성 검증. 권한 부족으로 인한 접근 장애 진단.

---

# 16. Host / OS 컨텍스트

### `podman ps -a` (발췌)
```
CONTAINER ID  IMAGE                          COMMAND      STATUS                   NAMES
2bc0b0f4d3a1  quay.io/ceph/ceph:v18.2.4     -n osd.7 ...  Exited (1) 4 minutes ago  ceph-3a5f8b2c-osd-7
9f1e2d3c4b5a  quay.io/ceph/ceph:v18.2.4     -n mon ...    Up 2 weeks                ceph-3a5f8b2c-mon-scp-mon-01
```
**확인 내용**: 노드의 Ceph 컨테이너 상태. **Exited 컨테이너(osd.7)와 종료코드·시각**으로 데몬 다운이 컨테이너 크래시/재시작 루프인지 확인.

### `systemctl --type=service | grep ceph`
```
ceph-3a5f8b2c@mon.scp-mon-01.service   loaded active   running
ceph-3a5f8b2c@osd.7.service            loaded failed   failed
```
**확인 내용**: systemd 레벨 데몬 상태. **failed 유닛**(osd.7)과 재시작 정책. 컨테이너↔systemd 일관성 확인.

### `ip -s link` (발췌)
```
2: ens1f0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 9000 ...
    RX:  bytes      packets  errors  dropped
      4821374651234  ...      0       1203
    TX:  bytes      packets  errors  dropped
      3910847120023  ...      0       0
```
**확인 내용**: 클러스터/퍼블릭 NIC의 **MTU(9000 점보프레임 일치 여부), errors/dropped 카운트**. 패킷 드롭=네트워크 원인 slow-ops/OSD flapping 단서.

### `ss -s`
```
Total: 1843
TCP:   1620 (estab 1402, closed 180, orphaned 2, timewait 178)
```
**확인 내용**: 소켓/연결 총량. estab 과다·timewait 급증으로 연결 누수·포트 고갈 징후 확인.

### `dmesg -T | grep -iE 'ceph|bluestore|nvme|scsi'` (발췌)
```
[Wed Jun 25 05:16:40 2026] nvme nvme0: I/O 384 QID 4 timeout, aborting
[Wed Jun 25 05:16:42 2026] blk_update_request: I/O error, dev sda, sector 19283746
```
**확인 내용**: 커널 레벨 디스크/드라이버 오류. **NVMe timeout·I/O error·SCSI reset**이 느린 OSD(§perf)·OSD down의 물리적 근본 원인임을 입증.

### `smartctl -a /dev/sda` (발췌)
```
Model Family:     Seagate Exos
SMART overall-health self-assessment test result: PASSED
  5 Reallocated_Sector_Ct   0x0033   100   100   010    -    0
197 Current_Pending_Sector  0x0012   100   100   000    -    8
Temperature_Celsius                                       -    42
```
**확인 내용**: 디스크 SMART 속성. **Reallocated/Pending Sector 증가, 온도 이상**으로 디스크 물리 열화 확정.
**⚠️ 운영 부하(§4.6) {L1}**: 기능상 읽기(`-a`)지만 일부 RAID/HBA 컨트롤러에서 짧은 stall·슬립 디스크 깨움 가능 + 디바이스 N배. `nice/ionice` 래핑·순차 실행. **`-t`(self-test 시작) 절대 금지.**

---

## 부록. 정상 vs 이상 판독 신호집 (공식 문서 기반)

> 임계값은 **Ceph Reef 공식 health-checks/troubleshooting 문서 기준 기본값**이며 `ceph config set`으로 조정 가능하다(따라서 값 자체보다 "어떤 조건에서 무엇이 막히는가"의 인과가 더 중요). 출처: docs.ceph.com/en/reef (Health checks, Troubleshooting OSDs, Monitoring a Cluster, RGW Dynamic Resharding).

### A. 용량/Full — 쓰기 차단으로 직결 (가장 위험)
Ceph는 용량 임계를 **nearfull < backfillfull < full < failsafe_full** 오름차순으로 강제하며, 역전 시 `OSD_OUT_OF_ORDER_FULL`로 경고한다.

| health check | 임계(기본) | 정상 | 이상 시 발생하는 장애 |
|---|---|---|---|
| `OSD_NEARFULL` | `mon_osd_nearfull_ratio` 0.85 | 최대 OSD < 85% | 조기 경고. 1개 OSD라도 초과하면 그 OSD를 쓰는 풀 전체가 위험 |
| `OSD_BACKFILLFULL` | `mon_osd_backfillfull_ratio` 0.90 | < 90% | **복구/리밸런스(backfill)가 멈춤** → PG가 `backfill_toofull`로 정체, 복구 지연 |
| `OSD_FULL` | `mon_osd_full_ratio` 0.95 | < 95% | **클러스터가 쓰기를 거부**(읽기만). 단 하나의 OSD가 full이면 그 OSD를 포함한 풀의 쓰기가 모두 차단 |
| `POOL_FULL`/`POOL_NEAR_FULL` | 풀 쿼터(`max_bytes/max_objects`) 또는 위 ratio | 쿼터 여유 | 풀이 쿼터 도달 시 **해당 풀 쓰기 차단** |

판독 포인트: `ceph df detail`에서 **개별 OSD %USE의 최댓값**(평균이 아님)과 풀 `MAX AVAIL`을 본다. 평균 50%여도 편중으로 한 OSD가 95%면 full이 발동한다(`ceph osd df tree`의 VAR로 편중 확인).

### B. OSD 상태·플래그·네트워크
| 신호 | 정상 | 이상 | 의미 |
|---|---|---|---|
| `ceph -s` osd up/in | up == in | up < in | in이지만 up 아님 = **down OSD 존재**(아직 out 안 됨, `mon_osd_down_out_interval` 기본 600s 후 out) |
| `OSDMAP_FLAGS` (`ceph osd dump` flags) | 운영 플래그 없음 | `noout/noup/nodown/noin/norecover/nobackfill/norebalance/noscrub/nodeep-scrub/pause*` | 유지보수용 플래그 **잔존**이 장애 원인일 수 있음(예: `noout` 잔존 → down OSD가 out 안 돼 복구 지연; `pausewr` → 쓰기 정지) |
| OSD flapping | up/down 안정 | osdmap epoch 급증, 로그에 반복 up/down | "wrongly marked down" — 보통 **네트워크/스위치** 문제 |
| Slow OSD heartbeats | 핑 지연 낮음 | `ceph health detail`에 `Slow OSD heartbeats on back/front (longest >1000ms)` | 단일=바쁜 OSD일 수 있으나, **여러 OSD 쌍에서 동시 지연 = 스위치/NIC/L1 장애**(공식 문서 명시) |
| `SLOW_OPS` | 없음 | `N slow ops, oldest is ...` | op이 `osd_op_complaint_time`(기본 30s) 초과 체류. 느린 디스크·peering 정체·네트워크 |
| `osd perf` latency | SSD/NVMe 0~5ms, HDD 20~50ms도 정상 | **특정 OSD만** 100ms+ 지속(또는 200ms+) | 디바이스별 baseline이 다르므로 절대값보다 **이상치 OSD 1~2개**가 핵심. 그 OSD가 느린 디스크 → 전체 클러스터 slow ops 유발(가장 느린 디스크가 속도 결정) |
| `ip -s link` | dropped/errors 0, MTU 일치 | dropped/errors 증가, MTU 불일치 | 패킷 드롭→재전송→slow heartbeat/slow ops. 점보프레임 한쪽만 9000이면 단편화 장애 |

### C. PG 상태 — I/O 차단 여부 구분
| PG 상태 | I/O | 의미 |
|---|---|---|
| `active+clean` | 정상 | 모든 복제본 정상 |
| `degraded` | 가능 | 복제본 수 부족(중복도 저하). 데이터 안전성↓이나 접근은 됨 |
| `undersized` | 가능 | acting set이 size보다 작음(둘 자리 OSD 부족) |
| `remapped`/`backfilling`/`recovering` | 가능 | 데이터 이동 중. 그 자체는 정상 과정 |
| `backfill_toofull` | 복구 정지 | 대상 OSD가 backfillfull → 복구 진행 불가(B 참조) |
| `inactive`/`peering`/`down`/`stale`/`incomplete` | **차단** | 해당 PG의 클라이언트 I/O **불가**. `down`은 필요한 OSD가 죽어 데이터 접근 불가, `stale`은 primary 보고 끊김 |
| `inconsistent` | 가능하나 위험 | scrub이 **복제본 불일치(손상)** 발견 → E 참조 |
| `recovery_unfound`/`OBJECT_UNFOUND` | **차단(해당 객체)** | 최신 복제본을 찾을 수 없음. 데이터 유실 위험 |

핵심 구분(공식 문서): **`misplaced`(OBJECT_MISPLACED)는 위험하지 않다** — 데이터 일관성은 보장되며 단지 CRUSH가 선호하는 위치가 아닐 뿐. 반면 **`degraded`는 중복도 저하**, **`inconsistent`는 손상**으로 의미가 전혀 다르다. 세 가지를 혼동하면 오진한다.

### D. 데이터 안전·이중화
| 신호 | 정상 | 이상 | 의미 |
|---|---|---|---|
| `min_size` (pool ls detail) | 가용 복제본 ≥ min_size | 가용 복제본 < min_size | **PG가 inactive로 전환 → I/O 차단.** 예: replicated size=3,min_size=2에서 2개 동시 손실 시 차단(데이터 보호 목적) |
| `POOL_NO_REDUNDANCY` | size ≥ 2 (EC k+m, m≥1) | replicated size=1 | 이중화 없음 → OSD 1개 손실로 데이터 유실 |
| `size`:`STORED`/`USED` 비율 (`ceph df`) | 설계값(3x 또는 EC 비율) | 예상과 다름 | 풀 size/EC 설정 오류 가능 |

> 주의: `min_size=1` 설정은 다운 시 쓰기를 계속 받게 하지만, **추가 장애 시 데이터 유실** 위험이 크므로 권장되지 않는다(복제 풀 기본 min_size=2 유지 권장).

### E. Scrub / 일관성
| health check | 임계(기본) | 의미 |
|---|---|---|
| `PG_NOT_DEEP_SCRUBBED` | `osd_deep_scrub_interval` 1주(604800s) 초과 | 정기 deep-scrub 누락 → **비트로트(silent corruption) 미검출** 위험 누적 |
| `PG_NOT_SCRUBBED` | `osd_scrub_max_interval` 초과 | 일반 scrub 누락 |
| `OSD_SCRUB_ERRORS`/`PG_DAMAGED` | inconsistent/snaptrim_error/repair 플래그 | deep-scrub이 **복제본 불일치(손상)** 발견. 대상 PG에 `ceph pg repair` 필요(공식). 디스크 불량의 신호일 수 있음 |
| `OSD_TOO_MANY_REPAIRS` | `mon_osd_warn_num_repaired` 10 | 읽기 오류를 복제본에서 복구한 횟수 과다 → **특정 디스크 열화** 강한 신호 |

### F. MON / 시계
| 신호 | 임계(기본) | 의미 |
|---|---|---|
| `MON_CLOCK_SKEW` | skew > `mon_clock_drift_allowed` 0.05s(50ms) | mon 간 시계 차 → **쿼럼 불안정**. (skew는 반드시 `mon_lease`보다 충분히 작아야 함) |
| `MON_DOWN` | — | mon 1개 down=WARN. 단 **과반(⌊N/2⌋+1) 미달 시 클러스터 정지**. 예: 3개 중 2개 down=정지, 5개 중 2개 down=동작(WARN) |
| `MON_DISK_LOW`/`MON_DISK_CRIT` | `mon_data_avail_warn` 30% / `_crit` 5% | mon 저장소 디스크 부족 → mon 다운 위험. 대형 osdmap 누적 시 mon store(rocksdb) 비대 |

### G. PG 수 (배치 효율)
| health check | 임계(기본) | 의미 |
|---|---|---|
| `TOO_MANY_PGS` | OSD당 PG > `mon_max_pg_per_osd` 250 | PG 과다 → mon/osd 메모리·peering 부하, OSD 기동 지연 |
| `TOO_FEW_PGS` | 권고치 미달 | PG 부족 → 데이터 분포 불균형, 편중 |
| `POOL_PG_NUM_NOT_POWER_OF_TWO` | 2의 거듭제곱 아님 | 분포 비효율(경고성) |

### H. RGW (오브젝트 스토리지)
| 신호 | 임계(기본) | 의미 |
|---|---|---|
| `LARGE_OMAP_OBJECTS` | `osd_deep_scrub_large_omap_object_key_threshold` 20만 keys 또는 value 합 1GiB | **버킷 인덱스 미샤딩**(권장 `rgw_max_objs_per_shard` 10만/샤드의 약 2배 초과 시 경고), 한 유저가 버킷 과다 보유(.rgw.meta), CephFS 대형 디렉터리, RGW usage log 누적. RocksDB 압박→OSD 느려짐. deep-scrub 시 `cluster [WRN] Large omap object found`로 로그 |
| `bucket limit check` fill_status | OK/WARN/OVER | OVER=샤드당 객체 과다 → **reshard 필요** |
| `sync status` | data caught up | `behind`/`recovering shards`가 진척 없이 지속 = **멀티사이트 복제 정체**(bilog 미트림→large omap 동반 가능) |
| `reshard list` | 비어 있음 | 항목 잔존+진척 없음 = 리샤딩 정체 |

### I. BlueStore (OSD 백엔드)
| health check | 의미 |
|---|---|
| `BLUEFS_SPILLOVER`/`BLUESTORE_SPILLOVER` | block.db(빠른 장치)가 가득 차 메타데이터가 **느린 데이터 장치로 spill** → OSD 성능 급락. `osd metadata`로 db 분리 여부·`ceph health detail`로 spill 용량 확인 |
| `BLUESTORE_FRAGMENTATION` | 단편화 점수 0~1, **1.0=심각**. BlueFS가 공간 확보 곤란 → 성능 저하 |
| `BLUESTORE_NO_PER_POOL_OMAP`/`NO_PER_PG_OMAP` | Nautilus/Pacific 이전 생성 볼륨 → omap 사용량 **근사치만 보고**(정확 통계 불가). repair로 갱신 가능 |
| `BLUESTORE_LEGACY_STATFS` 등 | 구버전 포맷 잔존 → 통계 부정확 |

### J. CephFS / MDS
| health check | 의미 |
|---|---|
| `MDS_CLIENT_RECALL` | 특정 클라이언트가 caps를 반납하지 않음 → MDS 메모리 압박(`tell mds session ls`의 num_caps로 범인 특정) |
| `MDS_CACHE_OVERSIZED` | MDS 캐시가 `mds_cache_memory_limit` 초과 → OOM 위험 |
| `MDS_SLOW_REQUEST`/`MDS_SLOW_METADATA_IO` | 메타데이터 op 정체(메타데이터 풀 OSD 느림 또는 잠금 경합) |
| `MDS_INSUFFICIENT_STANDBY` | standby MDS 부족 → **페일오버 불가**(active rank 죽으면 FS 마비) |
| `FS_DEGRADED`/`MDS_ALL_DOWN`/`FS_WITH_FAILED_MDS` | rank failed/down → **CephFS 접근 차단** |
| `MDS_DAMAGE` | 메타데이터 손상 감지 → 복구 작업 필요 |

### K. 디바이스·버전·크래시
| 신호 | 정상 | 이상 |
|---|---|---|
| SMART (`smartctl -a`, `device get-health-metrics`) | PASSED, Reallocated/Pending=0 | Pending/Reallocated/Uncorrected 증가, 온도 이상 → **물리 열화**(OSD slow/down의 근본 원인) |
| `DEVICE_HEALTH`/`DEVICE_HEALTH_TOOMANY` | 예측 없음 | 디바이스 **고장 예측**(`ceph device ls`의 LIFE EXPECTANCY) → 사전 교체 |
| `dmesg` | 디스크/드라이버 오류 없음 | `nvme timeout`, `blk_update_request: I/O error`, SCSI reset → OSD 장애의 커널 레벨 물증 |
| `DAEMON_OLD_VERSION` | 단일 버전 | 데몬 간 혼합 버전 지속(미완료 업그레이드)→호환·성능 이상 |
| `RECENT_CRASH` | 없음 | 신규 크래시(`crash ls`의 NEW)→ 반복 시 데몬 안정성 문제 |
| `AUTH_INSECURE_GLOBAL_ID_RECLAIM` | 비활성 | 안전하지 않은 global_id 재요청 허용(구 클라이언트 잔존)→보안 경고 |

**검증·한계 고지**: 위 임계값은 Reef 공식 문서 기준 기본값이며 마이너 버전·운영자 튜닝으로 달라질 수 있다. health check 코드명·임계값(nearfull 0.85 / backfillfull 0.90 / full 0.95, clock skew 50ms, slow heartbeat 1000ms, large omap 20만 keys/1GiB, rgw 10만/샤드, deep-scrub 1주)은 공식 문서·트래커로 교차검증했다. 실제 대응 전에는 `ceph health detail`로 해당 클러스터의 실제 임계·대상을 반드시 확인하라.

**한계 명시**: 위 출력의 값은 합성이며 형식은 18.2.x 기준이다. 마이너 버전·빌드·플러그인(jerasure/isa-l, 텔레메트리 등)에 따라 일부 필드가 가감될 수 있으므로, 실제 클러스터 1회 시범 수집으로 형식을 대조한 뒤 파서를 확정할 것을 권한다.
