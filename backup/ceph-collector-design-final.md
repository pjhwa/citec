# Ceph 종합 진단 정보 수집 도구 (ceph-collector) 설계 문서

**대상 Ceph 버전**: 18.2.x (Reef) 이상, cephadm orchestrator 배포 환경 기준
**실행 환경 전제**: **운영(production) 클러스터에서 수집한다. 수집 중 시스템에 어떤 영향(상태 변경·부하·락)도 주어서는 안 된다.** 본 설계의 모든 명령은 이 제약을 1순위로 검증했다(§4).
**목적**: Linux `sosreport` 스타일로 Ceph 클러스터의 상태·구성·성능·장애 원인 분석에 필요한 정보를 read-only로 자동 수집·패키징한다.

> **신뢰도 표기**: 명령어 끝 `[High]`/`[Moderate]`/`[Low]` = 18.2.x 존재 확신도.
> **부하 등급 표기**: `{L0}`=무시 가능 / `{L1}`=경미(N배수·중간) / `{L2}`=대형 클러스터에서 주의(opt-in·가드 대상). 미표기는 `{L0}`.
> 명령어는 공식 문서·man page 기반이며 라이브 일괄 검증본은 아니다. 도구는 실패를 `errors.log`로 흡수한다(§5.2).

---

## 1. 설계 원칙

| 원칙 | 내용 |
|---|---|
| **무영향 최우선** | 운영 클러스터 수집이 전제. 상태 변경 명령은 절대 미포함(§4.1). 부하 유발 가능 명령(§4.2 L2)은 기본 비활성·opt-in·상한·비피크 가드 |
| **Read-only** | 변경/부하 명령(`bench`, S3 `put/del`, `device check-health`, `pg repair/scrub`)은 본 도구 범위에서 제외 |
| **부하 통제** | 기본 **순차 또는 저병렬(≤4)**. 명령 간 throttle 인터벌(옵션). 모든 외부 프로세스를 `nice -n 19` + `ionice -c3`로 래핑. `timeout`은 hang 방지일 뿐 부하 방지가 아님을 전제 |
| **명령 introspection** | 모든 명령을 timeout + try/except로 감싸 종료코드·stderr를 `errors.log`에 기록. 버전 드리프트는 런타임 캡처로 흡수 |
| **cephadm 인지** | `ceph daemon`(admin socket)은 호스트 로컬이라 중앙 수집기에선 `ceph tell` 우선 |
| **레닥션 기본 ON** | `key`/`secret`/token/password 필드 마스킹 후 저장. `--no-redact`로만 해제(경고) |
| **이중 포맷** | `ceph`는 `-f json-pretty` + 텍스트. `radosgw-admin`은 기본 JSON(`--format` 미사용) |
| **멱등성** | 출력 = `ceph-report-<fsid>-<UTCtimestamp>` |

---

## 2. 아키텍처

### 2.1 디렉토리 구조
```
ceph-collector/
├── ceph_collector.py            # CLI 엔트리포인트 (argparse)
├── core/
│   ├── collector.py             # 워크플로우 오케스트레이션
│   ├── command_runner.py        # subprocess + timeout + nice/ionice + throttle + 종료코드 로깅
│   ├── safety_gate.py           # 변경/부하 명령 차단 allowlist (방어선, §4.4)
│   ├── redactor.py              # 민감정보 마스킹 (기본 ON)
│   └── report_packager.py       # tar.gz + manifest.json
├── modules/
│   ├── base_module.py
│   ├── metadata_module.py / cluster_module.py / mon_module.py / mgr_module.py
│   ├── osd_module.py / pg_module.py / crush_module.py / pool_module.py
│   ├── orch_module.py / rgw_module.py / rbd_module.py / cephfs_module.py
│   ├── crash_module.py / host_module.py
├── config/default.yaml
└── requirements.txt
```

### 2.2 실행 흐름
1. CLI 파싱 → `collect --output-dir /tmp [--use-cephadm-shell] [--no-redact] [--concurrency N] [--throttle-ms 200] [--full-pg-dump] [--all-osds] [--rbd-du] [--rgw-full]`
2. 모듈 초기화 → **safety_gate가 각 명령을 read-only allowlist와 대조**(§4.4)
3. `command_runner`가 nice/ionice 래핑 + timeout + throttle로 실행
4. 결과 저장 → 레닥션 적용
5. `manifest.json` 생성(성공/실패, health 스냅샷, 명령별 소요·바이트, 적용된 부하 가드)
6. `tar.gz`(또는 zstd) 패키징

### 2.3 실행 환경
- 기본: `client.admin` keyring으로 `ceph`/`radosgw-admin`/`rbd` 동작 가능한 노드(보통 mgr/admin 호스트).
- cephadm: `--use-cephadm-shell` → `cephadm shell -- <cmd>` 래핑. `[High]`
- `radosgw-admin`은 RGW keyring/`ceph.conf` 접근 필요. cephadm에선 `cephadm shell` 내부 실행 권장.

---

## 3. 수집 모듈별 명령어

### 3.1 Metadata
```bash
date -u                               # [High] {L0}
hostname -f                           # [High] {L0}
ceph --version                        # [High] {L0}
ceph fsid                             # [High] {L0}
uname -a                              # [High] {L0}
```

### 3.2 Cluster (기본 상태)
```bash
ceph -s -f json-pretty                            # [High] {L0}
ceph status                                       # [High] {L0}
ceph health detail -f json-pretty                 # [High] {L0}
ceph df detail -f json-pretty                     # [High] {L0}
ceph versions -f json-pretty                      # [High] {L0} 혼합버전 장애 핵심
ceph features -f json-pretty                      # [Moderate] {L0}
ceph node ls -f json-pretty                       # [High] {L0}
ceph log last 2000                                # [High] {L0}
ceph report                                       # [High] {L2} mgr 전체 직렬화 → 대형 클러스터 부하. §4.3 가드, 별도 파일
```

### 3.3 MON / 쿼럼 / 시계
```bash
ceph mon stat -f json-pretty                      # [High] {L0}
ceph mon dump -f json-pretty                      # [High] {L0}
ceph quorum_status -f json-pretty                 # [High] {L0}
chronyc tracking                                  # [High] {L0} (호스트 로컬)
timedatectl                                       # [High] {L0}
```
> clock skew는 MON 쿼럼 장애의 단골 원인이므로 반드시 수집.

### 3.4 MGR
```bash
ceph mgr dump -f json-pretty                      # [High] {L0}
ceph mgr module ls -f json-pretty                 # [High] {L0}
ceph mgr services -f json-pretty                  # [High] {L0}
ceph balancer status -f json-pretty               # [High] {L0} status 조회만, 리밸런스 트리거 안 함
ceph progress -f json-pretty                      # [Moderate] {L0}
```

### 3.5 OSD / 디바이스
```bash
ceph osd tree -f json-pretty                      # [High] {L0}
ceph osd df tree -f json-pretty                   # [High] {L0} 용량/PG분포(plain osd df는 중복이라 제외)
ceph osd stat -f json-pretty                      # [High] {L0}
ceph osd dump -f json-pretty                      # [High] {L0}
ceph osd perf -f json-pretty                      # [High] {L0} commit/apply latency
ceph osd blocked-by -f json-pretty                # [Moderate] {L0}
ceph osd pool autoscale-status                    # [High] {L0}
ceph osd metadata -f json-pretty                  # [High] {L1} 전체 OSD 메타(N배수, mon 읽기)
ceph device ls -f json-pretty                     # [High] {L0}
ceph device get-health-metrics <devid>            # [Moderate] {L1} 저장된 SMART 스냅샷 읽기(디바이스 직접 조회 아님)
```

**OSD 심층 (샘플링: 문제 OSD 또는 상한 N개만 — §6)**
```bash
ceph tell osd.<id> perf dump                      # [High] {L1} (Reef deprecated, 호환 수집)
ceph tell osd.<id> counter dump                   # [Moderate] {L1} perf dump 후속(권장)
ceph tell osd.<id> dump_historic_ops              # [Moderate] {L1} 느린 op 이력
ceph tell osd.<id> dump_ops_in_flight             # [Moderate] {L1}
ceph tell osd.<id> dump_blocked_ops               # [Moderate] {L1}
```
> `ceph tell`은 asok 명령을 중계하며 개별 호출은 가볍다. 위험은 부하가 아니라 OSD 수 N배수 → 샘플링으로 통제.

### 3.6 PG
```bash
ceph pg stat -f json-pretty                       # [High] {L0}
ceph pg dump pgs_brief -f json-pretty             # [High] {L1} 경량 버전 (기본)
ceph pg ls -f json-pretty                         # [High] {L1} 전체 PG 나열(대형 클러스터 중간 부하)
ceph pg dump_stuck inactive -f json-pretty        # [High] {L0}
ceph pg dump_stuck unclean  -f json-pretty        # [High] {L0}
ceph pg dump_stuck stale    -f json-pretty        # [High] {L0}
ceph pg dump_stuck undersized -f json-pretty      # [Moderate] {L0}
ceph pg dump_stuck degraded   -f json-pretty      # [Moderate] {L0}
ceph pg <pgid> query -f json-pretty               # [High] {L1} 문제 PG만 타겟(primary OSD 쿼리)
ceph pg dump -f json-pretty                       # [High] {L2} --full-pg-dump 에서만. mgr 부하, §4.3
```

### 3.7 CRUSH
```bash
ceph osd crush dump -f json-pretty                # [High] {L0}
ceph osd crush tree -f json-pretty                # [High] {L0}
ceph osd crush class ls -f json-pretty            # [High] {L0}
ceph osd crush rule ls -f json-pretty             # [High] {L0}
ceph osd crush rule dump -f json-pretty           # [High] {L0}
```
> CRUSH 맵 바이너리(`getcrushmap -o`)는 오프라인 편집용이라 RCA에 불필요 → 제외. JSON `crush dump`로 충분.

### 3.8 Pool / EC
```bash
ceph osd pool ls detail -f json-pretty            # [High] {L0}
ceph osd lspools -f json-pretty                   # [High] {L0}
ceph osd pool stats -f json-pretty                # [High] {L0}
ceph osd erasure-code-profile ls                  # [High] {L0}
ceph osd erasure-code-profile get <profile>       # [High] {L0} (ls 순회)
```
> `ceph osd pool get <pool> all`은 `pool ls detail`과 정보가 대부분 중복되어 RCA 목적상 제외.

### 3.9 Config
```bash
ceph config dump -f json-pretty                   # [High] {L0} *비-기본값만 출력*
ceph config-key dump                              # [High] {L0} 시크릿 포함 가능 → 레닥션
ceph config show <who>                            # [High] {L0} 예: osd.<id>, client.rgw.<id> (effective 값)
```
> 제외: `config ls`(값 없이 옵션명만), `config show-with-defaults`(기본값 전체 노이즈), `config generate-minimal-conf`(접속용·RCA무관). 효과적 설정 확인은 `config dump`+`config show`로 충분.
> `ceph config dump`는 명시적 비-기본값만 출력하므로, vault/keystone 등 기본값/env 주입 파라미터는 `ceph config show`로 effective 값을 확인한다.

### 3.10 Orchestrator / cephadm
```bash
ceph orch ls --format yaml                         # [High] {L0}
ceph orch ps -f json-pretty                        # [High] {L0}
ceph orch host ls -f json-pretty                   # [High] {L0}
ceph orch device ls -f json-pretty                 # [High] {L0}
ceph orch upgrade status                           # [High] {L0}
ceph cephadm config-check ls                       # [Moderate] {L0}
ceph orch host ok-to-stop <hostname>               # [High] {L0} **평가(dry-run)만, 실제 중단 안 함**
cephadm ls                                         # [High] {L0} (호스트 로컬, mgr/orch 불능 시에도 동작)
cephadm check-host                                 # [High] {L0} (인자 없이, 호스트 점검만)
```
> 제외: `orch status`(ls/ps와 중복), `cephadm config-check status`(config-check ls로 충분).

### 3.11 RGW (vault/keystone 연동 + 메타데이터 + multisite)

**구성/토폴로지**
```bash
radosgw-admin realm list                           # [High] {L0}
radosgw-admin zonegroup list                       # [High] {L0}
radosgw-admin zone list                            # [High] {L0}
radosgw-admin period get                           # [High] {L0}
radosgw-admin zonegroup get                          # [High] {L0}
radosgw-admin zone get                              # [High] {L0} sync 키 포함 → 레닥션
radosgw-admin sync status                           # [High] {L0} 멀티사이트 필수(단일도 무해)
```
> 제외: `mdlog status`/`datalog status`(니치, `sync status`가 복제 지연을 대표 신호로 보여줌).

**사용자 / 버킷 / 샤딩 / GC / lifecycle**
```bash
radosgw-admin user list                             # [High] {L1}
radosgw-admin bucket list                           # [High] {L2} 버킷 수천 개면 부하 → §4.6
radosgw-admin bucket stats                          # [High] {L2} 전체는 --rgw-full에서만. 기본은 상위 K개·--bucket=<b> (§4.6)
radosgw-admin bucket limit check                    # [Moderate] {L2} 전체 버킷 순회 → --rgw-full에서만 (§4.6)
radosgw-admin reshard list                          # [High] {L0} 대기열 나열만(reshard 실행 아님)
radosgw-admin gc list                               # [High] {L1} 나열만(GC 실행 아님). 대기열 大면 출력 큼(§4.6)
radosgw-admin lc list                               # [High] {L0} lifecycle 처리 상태(만료 미동작 RCA)
```
> `radosgw-admin`은 기본 JSON 출력이며 `--format` 옵션을 쓰지 않는다.

**Vault / Keystone 연동 확인** (config 키 검사)
```bash
ceph config dump -f json-pretty                     # rgw_* 키 필터
ceph config show client.rgw.<id>                    # [High] {L0} effective 값 (orch ps에서 daemon명 파싱)
ceph config dump | grep -E 'rgw_crypt_vault|rgw_crypt_s3_kms|rgw_keystone|rgw_s3_auth_use_keystone'
```
- **Vault 판정 키**: `rgw_crypt_s3_kms_backend=vault`, `rgw_crypt_vault_addr`, `rgw_crypt_vault_auth`, `rgw_crypt_vault_secret_engine`, `rgw_crypt_vault_prefix`, `rgw_crypt_vault_token_file`
- **Keystone 판정 키**: `rgw_s3_auth_use_keystone=true`, `rgw_keystone_url`, `rgw_keystone_api_version`, `rgw_keystone_admin_*` 또는 `rgw_keystone_admin_token`(레닥션)

### 3.12 RBD (pool ls 결과에서 rbd application 풀 순회)
```bash
rbd ls -p <pool> --long --format json               # [High] {L1}
rbd info <pool>/<image> --format json               # [High] {L1} (features에서 object-map/fast-diff 확인)
rbd status <pool>/<image> --format json             # [High] {L1} watcher(좀비 매핑 진단)
rbd mirror pool status <pool> --verbose             # [Moderate] {L1} 미러링(DR) 사용 시에만
# 부하 주의 — 기본 비활성
rbd du -p <pool> --format json                      # [High] {L2} --rbd-du 에서만, §4.6 (용량분석 옵션, RCA 핵심 아님)
```
> 제외: `rbd trash ls`(휴지통 니치). **`rbd du` 운영 경고**: object-map+fast-diff가 **비활성**인 이미지는 실사용량 계산을 위해 전체 오브젝트를 스캔하여 대용량 이미지에서 수 분 + OSD I/O 부하를 유발한다. 기본 비활성(`--rbd-du` opt-in)이며, 활성 시에도 `rbd info`의 features에 `object-map`,`fast-diff`가 **모두 있는 이미지에만** 실행한다. 없는 이미지는 건너뛰고 `errors.log`에 사유 기록.

### 3.13 CephFS / MDS
```bash
ceph fs ls -f json-pretty                           # [High] {L0}
ceph fs status -f json-pretty                       # [High] {L0}
ceph fs dump -f json-pretty                          # [High] {L0}
ceph mds stat -f json-pretty                         # [High] {L0}
ceph mds metadata -f json-pretty                     # [High] {L0}
ceph tell mds.<rank> session ls                      # [Moderate] {L2} 클라이언트 多면 세션당 1행 → 출력 大(§4.6)
ceph tell mds.<rank> dump_blocked_ops                 # [Moderate] {L1}
```
> 제외: `tell mds perf dump`(deprecated 니치), `fs subvolume(group) ls`(서브볼륨 관리용, RCA 비핵심).

### 3.14 Crash (레닥션 후 저장)
```bash
ceph crash ls -f json-pretty                         # [High] {L0} (NEW 컬럼으로 신규 크래시 식별)
ceph crash info <crash_id>                           # [High] {L0} (ls 순회, 최근 N개)
```
> 제외: `crash ls-new`/`crash stat`(`crash ls`의 NEW 표시와 건수로 대체 가능).

### 3.15 인증 (레닥션 필수)
```bash
ceph auth ls -f json-pretty                          # [High] {L0} key 필드 마스킹, caps만 보존
```

### 3.16 Host / OS 컨텍스트 (해당 노드 로컬)
```bash
podman ps -a            # 또는 docker ps -a              # [High] {L0}
systemctl --type=service | grep ceph                    # [High] {L0}
ip -s link                                              # [High] {L0} 패킷 드롭/에러
ss -s                                                   # [High] {L0}
dmesg -T | grep -iE 'ceph|bluestore|nvme|scsi|ext4|xfs' # [High] {L0}
smartctl -a <dev>                                       # [High] {L1} 읽기 전용(-a). **-t(테스트 시작) 금지**
```

---

## 4. 운영 영향 안전성 분석 (핵심)

운영 클러스터 수집의 1순위 제약은 "무영향"이다. 본 절은 전 명령을 (1) 상태 변경, (2) 부하, (3) 간접 영향 세 축으로 검증한다.

### 4.1 상태 변경(mutating) 명령 부재 — 입증
본 설계에 포함된 명령의 동사는 전부 read 계열이다: `ls/list/dump/stat/status/df/tree/perf/query/info/du/show/get/metadata/versions/features/report/last/tracking/check`. 변경 계열 동사(`set/rm/create/add/delete/apply/enable/disable/start/stop/restart/reweight/in/out/repair/scrub/deep-scrub/bench/mark/destroy/purge/bootstrap/pull/process`)는 **한 건도 사용하지 않는다.**

오해 소지가 있는 명령의 실제 동작:

| 명령 | 검증 결과 |
|---|---|
| `ceph orch host ok-to-stop` | 호스트 중단 가능 여부 **평가만**. 데몬을 멈추지 않음 |
| `radosgw-admin gc list` / `reshard list` | 대기열 **나열만**. GC/reshard를 실행하지 않음 |
| `ceph balancer status` | 상태 **조회만**. 리밸런스를 트리거하지 않음 |
| `ceph osd dump` flags 표시 | osdmap의 noout 등 플래그를 **읽어 표시만** 함. 설정하지 않음 |

### 4.2 부하 위험 분류

- **{L0} 무시 가능**: mon/mgr/osd map 스냅샷, health, df, tree, config dump/show, crush dump, pool ls, auth ls, crash ls, orch ls/ps, RGW realm/zone/sync status 등 메타데이터 단발 조회. 운영 영향 사실상 없음.
- **{L1} 경미**: `osd metadata`(전체), `pg ls`(전체), `pg dump pgs_brief`, per-OSD/MDS `tell`, `rbd ls/info/status`, `smartctl -a` 등. 개별은 가벼우나 N배수·중간 출력 → **샘플링·상한**으로 통제(§6).
- **{L2} 주의**: `ceph report`, `ceph pg dump`(full), `rbd du`(object-map 미활성), `radosgw-admin bucket stats/list/limit check`(전체). 대형 클러스터에서 mgr/RGW 부하 → **기본 비활성·opt-in·상한·비피크**(§4.3).

### 4.3 L2 명령 가드 (필수)
1. **기본 비활성**. 명시 플래그에서만 실행: `--full-pg-dump`, `--rbd-du`, `--rgw-full`. `ceph report`는 별도 파일·1회.
2. **`rbd du`**: `rbd info` features에 `object-map`+`fast-diff` 둘 다 있는 이미지에만. 없으면 skip + 사유 기록.
3. **RGW 전체 순회**: 기본은 `bucket list` + 상위 K개(기본 50) `bucket stats`만. 전체는 `--rgw-full`.
4. **비피크 권장**: L2 활성 수집은 운영 피크 시간대를 피하도록 README·실행 시 경고 출력.
5. **사전 health 확인**: 수집 시작 시 `HEALTH_ERR` 또는 진행 중 대규모 recovery/backfill 감지되면 L2 명령을 자동 skip(부하 가중 방지).

### 4.4 수집기 자체의 부하 통제
- **동시성 기본 순차** 또는 저병렬(`--concurrency`, 기본 1~4). mon/mgr는 단일 처리 지점이므로 명령 폭주는 클라이언트 I/O에 간접 영향을 줄 수 있음.
- **throttle**: 명령 간 인터벌(`--throttle-ms`, 기본 0~200ms)로 mon 연결 버스트 완화.
- **nice/ionice**: 모든 외부 프로세스를 `nice -n 19 ionice -c3`로 래핑(특히 `rbd du`, `smartctl`, `dmesg`).
- **`timeout`은 부하 방지가 아님**: hang 방지용일 뿐, timeout 만료 전까지 부하는 발생한다. 따라서 부하 통제는 timeout이 아니라 위 가드로 수행한다.
- **safety_gate 방어선**: 실행 직전 각 명령을 read-only allowlist와 대조하여, 향후 모듈 확장 시 변경/부하 명령이 실수로 유입되는 것을 코드 레벨에서 차단.

### 4.5 파일시스템 영향
- 모든 출력 파일·패키지는 **수집 디렉토리 외부에 쓰지 않는다**. 시스템 경로 오염 없음.
- 읽기 전용 디렉토리 마운트 가정 환경에서도 동작(작업 경로만 쓰기).

### 4.6 "반드시 수집하지만 부하가 있는" 명령 — 메커니즘·필요성·완화

아래 명령들은 **RCA에 꼭 필요해서 제외할 수 없지만**, 운영 클러스터에서 부하를 유발할 수 있다. 부하의 원인과 그럼에도 필요한 이유, 완화책을 명시한다. (단순 부하만 있고 RCA 가치가 낮은 명령은 §3에서 이미 제외했다.)

| 명령 | 부하 메커니즘 | 왜 반드시 필요한가(어떤 RCA) | 완화책 |
|---|---|---|---|
| `ceph report` | active mgr가 mon/osd/pg/fs 맵 전체를 한 번에 직렬화 → 대형 클러스터에서 mgr CPU·메모리 순간 점유, 수십 MB 출력 | 클러스터 **미접속 상태의 오프라인 전수 분석**(단일 스냅샷). 사후 RCA의 1차 사료 | 1회만·별도 파일·`HEALTH_ERR`나 대규모 recovery 중이면 자동 skip·timeout 180s |
| `ceph pg dump`(full) | mgr가 **전 PG 레코드**(scrub 타임스탬프·OSD별 매핑 포함)를 직렬화 → PG 수 비례 부하 | scrub/deep-scrub 지연, PG별 last_scrub_stamp, OSD↔PG 정밀 분포 RCA(이건 `pgs_brief`에 없음) | 기본 `pgs_brief`만. full은 `--full-pg-dump` opt-in + 비피크 |
| `radosgw-admin bucket limit check` | **모든 버킷**의 인덱스 샤드 채움률을 순회 계산 | 인덱스 핫스팟·reshard 필요 판정(RGW 성능 장애의 최빈 원인) | `--rgw-full`에서만·비피크. 평시엔 상위 버킷만 |
| `radosgw-admin bucket stats`(전체) | 버킷별 인덱스 메타데이터를 순회 → 버킷 수만큼 RADOS omap 조회 | 버킷별 객체 수·사용량·샤드 수 RCA | 기본은 상위 K개(기본 50)+지목 버킷. 전체는 `--rgw-full` |
| `radosgw-admin bucket list` | 전체 버킷 enumerate(메타데이터 풀 스캔) | 버킷 존재·이름·소유 확인의 기준 | {L2} 가드. 대규모 시 페이지네이션 |
| `radosgw-admin gc list` | 삭제 대기 큐 전체를 출력 → 누적 대량 시 큰 출력 | "삭제했는데 공간 미회수" RCA | 출력 상한(head)·필요 시에만 |
| per-OSD `ceph tell osd.* {perf/counter dump, dump_historic_ops, ...}` | 개별 호출은 가볍지만 **OSD 수 N배** | 느린 OSD의 병목 계층(net/RocksDB/disk)·slow-ops 단계 RCA | **샘플링**: down/near-full/high-latency 우선, 상한 N(기본 20). 전체는 `--all-osds` |
| `ceph tell mds.* session ls` | 클라이언트 **세션당 1행** → 수천 클라이언트면 큰 출력 + MDS 일시 부하 | caps 폭증 클라이언트 식별(MDS_CLIENT_RECALL·MDS 메모리 압박 RCA) | CephFS 사용·MDS 경고 존재 시에만. 출력 상한 |
| `rbd du` | object-map/fast-diff 미보유 이미지는 **전 오브젝트 스캔**(RADOS stat 다발) → OSD I/O 부하 | 씬 프로비저닝 실사용량·용량 고갈 분석(용량 이슈) | 기본 비활성·`--rbd-du`·object-map+fast-diff 보유 이미지만 |
| `smartctl -a` | SMART 읽기. 일부 RAID/HBA 컨트롤러에서 짧은 stall·슬립 디스크 깨움. 디바이스 N배 | OSD down/slow의 **물리적 근본 원인**(섹터 불량·마모) 확정 | `nice/ionice` 래핑·`-a`(읽기)만, `-t`(테스트) 금지·디바이스 순차 |
| `dmesg -T` | 큰 링버퍼 전체를 포매팅(CPU·메모리 경미) | 커널 레벨 I/O error·NVMe timeout 확인(OSD 장애의 물리 원인) | grep로 필터·`nice` 래핑 |

**공통 원칙**: 위 명령은 *기능*상 read-only라 클러스터 상태를 바꾸지 않지만 *부하*가 있으므로, ① 기본 비활성(opt-in)·② 샘플링/상한·③ 비피크·④ 수집 시작 시 health/recovery 감지 자동 skip 중 최소 하나 이상을 항상 적용한다.

---

## 5. 민감정보 레닥션 & 실행 안정성

### 5.1 레닥션 (기본 ON)
시크릿 평문 출처와 마스킹 대상:
- `ceph auth ls` → `key`
- `radosgw-admin zone get` → `system_key.access_key/secret_key`, sync 키
- `ceph config-key dump` → 전체 값
- `ceph config dump/show` → `*password*`/`*token*`/`*secret*`
- `radosgw-admin user info` → `keys[].secret_key`

규칙(예): `("key"|"secret_key"|"access_key"|password|token)\s*[:=]\s*\S+` → `***REDACTED***`. `--no-redact` 시 manifest·stdout 경고.

### 5.2 안정성·실패 흡수
- 모든 명령 timeout(기본 60s). `ceph report`/`pg dump`는 별도 상한(예 180s).
- 실패 시 중단 없이 `errors.log`에 `{cmd, returncode, stderr, duration}` 기록.
- `[Moderate]`/`[Low]` 명령은 실행 전 `--help` 존재 확인(선택) 후 실행.

---

## 6. 수집 범위 / 성능 정책

| 명령 | 위험 | 정책 |
|---|---|---|
| `ceph report` | {L2} mgr 부하 | 별도 파일, 1회, health 정상 시에만 |
| `ceph pg dump`(full) | {L2} mgr 부하 | `--full-pg-dump`에서만, 기본은 `pgs_brief` |
| per-OSD `perf/counter dump` | {L1} N배수 | 샘플링: down/near-full/high-latency 우선, 상한 N(기본 20), `--all-osds`로 해제 |
| `rbd du` | {L2} 전체 스캔 | `--rbd-du` + object-map/fast-diff 보유 이미지만 |
| per-image `rbd info/status` | {L1} 이미지 수 | pool당 상한 M(기본 200), 초과 시 `rbd ls`만 |
| `radosgw-admin bucket stats/list/limit check`(전체) | {L2} RGW 부하 | 기본 상위 K개(기본 50), 전체는 `--rgw-full` |

---

## 7. 출력 패키징

```
ceph-report-<fsid>-<UTCtimestamp>/
├── reports/
│   ├── 00-metadata/ 01-cluster/ 02-mon/ 03-mgr/
│   ├── 04-osd/ 05-pg/ 06-crush/ 07-pools/
│   ├── 08-config/(redacted) 09-orch/
│   ├── 10-rgw/ 11-rbd/ 12-cephfs/
│   ├── 13-crash/ 14-auth/(redacted) 15-host/
├── manifest.json   # tool/ceph 버전, health 스냅샷, 모듈별 성공/실패, 적용된 부하 가드, 명령별 소요·바이트
├── errors.log
├── collection.log
└── README.txt
```

### manifest.json (예)
```json
{
  "tool_version": "1.0",
  "ceph_version": "18.2.x",
  "fsid": "....",
  "collection_time_utc": "2026-06-25T05:20:00Z",
  "redacted": true,
  "load_guards": {"l2_enabled": false, "concurrency": 1, "throttle_ms": 0, "nice_ionice": true},
  "health_snapshot": "HEALTH_WARN",
  "modules": {"osd": {"commands": 12, "success": 11, "failed": 1}}
}
```

---

## 8. 기능 테스트(S3 list/put/get/del) 범위 정의

S3 list/put/get/del 동작 검증은 `tester` 계정을 통한 **별도 절차**로 분리하며 본 collector에 포함하지 않는다. collector는 운영 무영향을 위해 RGW read-only 메타데이터(§3.11)만 수집한다. 외부 기능 테스트는 전용 버킷 allowlist·작업 후 자가 정리·운영 버킷 PUT/DEL 코드 차단을 전제로 별도 실행한다.

---

## 9. 구현 로드맵

| Phase | 범위 |
|---|---|
| **1 (Core)** | command_runner(nice/ionice/throttle) + safety_gate + redactor + packager / metadata·cluster·mon·mgr·osd·pg·pool·crush |
| **2 (Orch+RGW)** | orch / rgw + vault·keystone(`config dump`+`config show`) + multisite sync status |
| **3 (Advanced)** | crash·cephfs·rbd(du 가드)·host / 분석 헬퍼(health 요약, vault/keystone 판정) |
| **4 (고도화)** | YAML 커스텀 명령 / HTML 리포트 / 샘플링·가드 튜닝 |

---

## 10. 클러스터 검증 권장 항목

마이너 버전 간 변동 이력이 있어 대상 18.2.x에서 `--help` 1회 확인 권장(실패는 `errors.log`로 흡수):
`ceph progress` / `ceph cephadm config-check ls` / `ceph device get-health-metrics` / `radosgw-admin bucket limit check` / `ceph features` / `ceph osd blocked-by` / per-daemon `counter dump`.

---

## 11. 결론

본 설계는 **운영 클러스터 무영향**을 1순위 제약으로 검증되었다. (1) 상태 변경 명령은 전 모듈에 0건이며(§4.1), (2) read-only이지만 부하를 줄 수 있는 명령 4개군(`ceph report`, `pg dump` full, `rbd du`, RGW 전체 버킷 순회)은 기본 비활성·opt-in·상한·비피크·health 사전확인으로 가드했고(§4.3), (3) 수집기 자체 부하는 저병렬·throttle·nice/ionice·safety_gate로 통제한다(§4.4). 특히 `rbd du`는 object-map/fast-diff 보유 이미지에만 제한해 전체 오브젝트 스캔을 차단한다. 민감정보 레닥션은 기본 동작이다.

**한계 명시**: 명령어는 공식 문서·man page 기반이며 라이브 18.2.x 일괄 검증본은 아니다. 부하 등급({L1}/{L2})은 클러스터 규모·구성(버킷 수, 이미지 object-map 여부, PG 수)에 따라 달라지므로, 첫 도입 시 **비운영 또는 저부하 시간대에 1회 시범 수집**하여 `manifest.json`의 명령별 소요·바이트를 확인한 뒤 운영 적용을 권한다.
