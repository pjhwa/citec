# Ubuntu 24.04 AppArmor 적용 — 02. 프로파일 작성·운영 실습

> 시리즈 2편. 1편에서 잡은 개념(DAC·MAC·LSM·프로파일 문법·동작 모드)을 **손으로** 익히는 실습편이다. 임의의 사용자 데몬 한 개를 골라 *0에서* 시작해 **complain → logprof → enforce → CI 검증** 사이클을 한 바퀴 돌려본다.
>
> **환경 가정**: `00_환경_컨텍스트.md` 참조. 본 편의 실습은 단일 Ubuntu 24.04 VM 한 대에서 자족적으로 수행 가능하며, 컨테이너·OpenStack을 필요로 하지 않는다. 그러나 본 편에서 익힌 사이클은 4편(libvirt sVirt) 이후 실 환경 적용의 기본기가 되므로 반드시 *직접* 따라 칠 것을 권장한다.
>
> **선수 문서**: `01_Ubuntu24.04_AppArmor_기초_심화.md`
>
> **소요 시간**: 처음 한 사이클 약 2~3시간. 6~8장(CI/통합 테스트)까지 포함하면 반나절.

---

## 목차

1. 학습 목표와 사전 준비
2. 라이브 데모 — 기본 분석 도구 손에 익히기
3. 실습 대상 데몬 만들기 — `myapp`
4. 첫 프로파일 — 빈 골격에서 시작하기
5. 학습 사이클 (complain → logprof → enforce)
6. 정책 리팩토링 패턴 (abstractions, owner, 변수, local)
7. 정책의 단위 테스트 (`apparmor_parser` CI 검증)
8. 시스템 통합 테스트 (양성·거부 자동화)
9. 자주 발생하는 시행착오와 해결
10. 점검 질문 + 다음 편 예고
- 부록 A. 본 편 전체 명령 한 페이지 요약
- 부록 B. `myapp` 완성 프로파일 (참고)

---

## 1. 학습 목표와 사전 준비

### 1.1 학습 목표

본 편을 마치면 다음을 *직접 손으로* 할 수 있어야 한다.

- 임의의 데몬에 대해 빈 프로파일 골격을 만들고 complain 모드로 적재할 수 있다.
- 데몬을 정상 시나리오로 한 번 실행한 뒤, 발생한 로그를 `aa-logprof`로 정책에 반영할 수 있다.
- enforce로 전환하고, 의도된 거부가 발생했을 때 로그를 읽고 정책을 수정할 수 있다.
- 정책에 abstractions·owner·변수·local 분리를 적용해 가독성·유지보수성을 높일 수 있다.
- 정책 변경에 대해 **CI에서 자동 검증**(파서 검증·룰 다운그레이드 경고)을 돌릴 수 있다.
- 양성 시나리오와 거부 시나리오를 자동화 스크립트로 회귀 테스트할 수 있다.

### 1.2 실습 환경

| 항목 | 권장값 |
|---|---|
| 호스트 OS | Ubuntu 24.04 LTS (Noble Numbat) |
| vCPU / RAM / 디스크 | 2 vCPU / 2 GiB / 10 GiB 이상 |
| 네트워크 | 외부 인터넷 (apt 가능) |
| 권한 | sudo 가능한 일반 사용자 |
| 가상화 | Multipass / KVM / VirtualBox / Cloud VM 무엇이든 가능 |

본 편 실습은 호스트 OS에 영향을 주는 변경(프로파일 적재, 시스템 사용자 추가)이 포함된다. **반드시 학습용 일회성 VM**에서 진행한다.

### 1.3 패키지 설치

```bash
# 기본 도구
sudo apt update
sudo apt install -y apparmor apparmor-utils apparmor-profiles-extra \
                    auditd python3 python3-venv jq

# (선택) 정책 단위 테스트용
sudo apt install -y bats

# 설치 확인
dpkg -l | grep -E '^ii  apparmor'
# 결과 예 (4.0.1-0ubuntu0.24.04.x 계열)

aa-status --version
apparmor_parser --version
```

> **노트**: 24.04에서 `apparmor` 자체는 사전 설치되어 있다. 위 명령은 `apparmor-utils`(aa-* CLI)와 `auditd`(audit 로그)를 추가로 들이는 것이 핵심이다.

### 1.4 작업 디렉터리 약속

본 편 전체에서 다음 두 위치를 일관되게 사용한다.

| 경로 | 용도 |
|---|---|
| `/etc/apparmor.d/usr.local.bin.myapp` | 실습 대상 프로파일 |
| `/etc/apparmor.d/local/usr.local.bin.myapp` | 사이트 보강(6장) |
| `~/apparmor-lab/` | 정책 코드 Git 저장소(7장 CI용) |

---

## 2. 라이브 데모 — 기본 분석 도구 손에 익히기

본격적인 작성 전에 *현재 시스템 상태*를 한 번 둘러본다. 1편에서 본 도구들을 실제 출력으로 확인하면서 손에 감을 익힌다.

### 2.1 `aa-status`

```bash
sudo aa-status
```

전형적인 출력:

```
apparmor module is loaded.
86 profiles are loaded.
80 profiles are in enforce mode.
   /usr/bin/man
   /usr/sbin/cups-browsed
   ...
6 profiles are in complain mode.
12 processes have profiles defined.
12 processes are in enforce mode.
   /usr/sbin/cupsd (1024)
   /usr/sbin/libvirtd (1234)
0 processes are in complain mode.
0 processes are unconfined but have a profile defined.
```

**읽는 법** (1편 6.2절 복습):

- *"86 profiles are loaded"*: 커널에 적재된 정책 개수.
- *"12 processes have profiles defined"*: 현재 실행 중이며 프로파일이 부착된 프로세스.
- *"unconfined but have a profile defined"*: 프로파일이 있는데도 부착되지 않음 — **잠재 문제**. 보통 `execve` 매칭 실패(경로 mismatch)나 부팅 순서 문제.

### 2.2 securityfs 직접 보기

```bash
sudo cat /sys/kernel/security/apparmor/profiles | head
sudo wc -l /sys/kernel/security/apparmor/profiles
sudo cat /sys/kernel/security/apparmor/features/policy/versions
```

`profiles` 파일은 한 줄당 `<프로파일이름> (<모드>)` 형식이다. `aa-status`는 이 파일을 가공해 보여주는 사용자 공간 도구일 뿐이라는 것을 직접 확인한다.

### 2.3 `aa-unconfined`로 보호되지 않은 프로세스 식별

```bash
sudo aa-unconfined --paranoid
```

TCP/UDP 포트를 열고 있으면서 프로파일이 부착되지 않은 프로세스를 알려준다. 운영 환경 점검용으로 매우 유용하다.

### 2.4 사용자 네임스페이스 제한 상태

24.04 핵심 변화(1편 7.3절). 직접 확인:

```bash
sysctl kernel.apparmor_restrict_unprivileged_userns
# kernel.apparmor_restrict_unprivileged_userns = 1

ls /proc/sys/kernel/apparmor_restrict_unprivileged_userns_force
```

본 편 실습은 user namespace를 만들지 않으므로 이 값을 변경하지 않는다.

---

## 3. 실습 대상 데몬 만들기 — `myapp`

학습용으로 작은 데몬을 직접 만든다. 실 데몬을 가져와도 되지만, *어떤 자원이 필요한지 우리가 정확히 아는* 데몬이 학습에 가장 좋다.

### 3.1 요구사항

`myapp`는 다음 동작을 한다.

- 설정 파일 `/etc/myapp/config.json`을 읽는다.
- 정적 디렉터리 `/srv/myapp/files/` 안의 파일을 HTTP로 서빙한다.
- 모든 요청을 `/var/log/myapp/access.log`에 append.
- PID 파일은 `/run/myapp.pid`.
- TCP 8080에서 리슨.
- `SIGTERM`을 받으면 PID 파일을 정리하고 종료.

### 3.2 데몬 코드

```bash
sudo install -d -m 0755 /etc/myapp /srv/myapp/files /var/log/myapp
sudo install -d -m 0755 /usr/local/lib/myapp

sudo tee /etc/myapp/config.json >/dev/null <<'JSON'
{
  "listen_port": 8080,
  "doc_root": "/srv/myapp/files",
  "log_path": "/var/log/myapp/access.log"
}
JSON

# 시연용 정적 파일
echo "hello from myapp" | sudo tee /srv/myapp/files/index.txt

sudo tee /usr/local/bin/myapp >/dev/null <<'PY'
#!/usr/bin/env python3
"""Tiny educational HTTP daemon for AppArmor practice."""
import json, os, signal, sys, http.server, socketserver, datetime

CONF = "/etc/myapp/config.json"
PIDF = "/run/myapp.pid"

with open(CONF) as f:
    cfg = json.load(f)

os.chdir(cfg["doc_root"])
log = open(cfg["log_path"], "a", buffering=1)

with open(PIDF, "w") as f:
    f.write(str(os.getpid()))

def cleanup(*_):
    try: os.unlink(PIDF)
    except FileNotFoundError: pass
    log.close()
    sys.exit(0)

signal.signal(signal.SIGTERM, cleanup)
signal.signal(signal.SIGINT, cleanup)

class H(http.server.SimpleHTTPRequestHandler):
    def log_message(self, fmt, *args):
        log.write(f"{datetime.datetime.now().isoformat()} {self.address_string()} {fmt%args}\n")

with socketserver.TCPServer(("", cfg["listen_port"]), H) as srv:
    srv.serve_forever()
PY

sudo chmod 0755 /usr/local/bin/myapp
```

### 3.3 systemd 유닛

```bash
sudo tee /etc/systemd/system/myapp.service >/dev/null <<'UNIT'
[Unit]
Description=Tiny educational HTTP daemon (AppArmor lab)
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/myapp
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable --now myapp.service
sleep 1
sudo systemctl --no-pager status myapp.service
```

### 3.4 정상 동작 확인

```bash
curl -sS http://127.0.0.1:8080/index.txt
# hello from myapp

cat /run/myapp.pid
sudo tail /var/log/myapp/access.log
```

여기까지가 *프로파일 없는 상태*. `aa-status` 출력에 `myapp`은 없다. 다음 4장에서 프로파일을 부착한다.

---

## 4. 첫 프로파일 — 빈 골격에서 시작하기

### 4.1 두 가지 출발 방식

| 방식 | 장점 | 단점 |
|---|---|---|
| 손으로 빈 파일 작성 | 구조가 명확히 보인다 | 매번 abstractions·헤더를 외워야 함 |
| `aa-genprof` / `aa-autodep` 자동 생성 | 표준 골격이 빠르게 만들어짐 | 어떤 abstraction이 들어왔는지 *읽고* 이해할 책임 |

본 편에서는 두 가지를 모두 한 번씩 경험한다. 먼저 손으로.

### 4.2 손으로 빈 골격 만들기

```bash
sudo tee /etc/apparmor.d/usr.local.bin.myapp >/dev/null <<'AA'
abi <abi/4.0>,

include <tunables/global>

/usr/local/bin/myapp flags=(complain) {
    include <abstractions/base>

    # ── 본문은 5장에서 학습 사이클로 채운다 ──
}
AA
```

지금 이 프로파일에는 `abstractions/base` 외에는 아무 규칙이 없다. 즉 `myapp`이 정상 동작에 필요한 거의 모든 자원이 거부될 것이다. 우리는 일부러 *최소 골격으로 시작* 한 뒤 로그를 보고 한 줄씩 채울 것이다.

### 4.3 적재와 부착 확인

```bash
# 정책 적재
sudo apparmor_parser -r /etc/apparmor.d/usr.local.bin.myapp

# 적재 상태 확인
sudo aa-status | grep myapp
#   /usr/local/bin/myapp    (complain)

# 데몬 재시작 → execve 시점에 프로파일이 부착됨
sudo systemctl restart myapp.service
sleep 1

# 프로세스에 부착되었는지 확인
PID=$(cat /run/myapp.pid)
cat /proc/$PID/attr/current
# /usr/local/bin/myapp (complain)
```

`/proc/<PID>/attr/current`는 그 프로세스에 *현재 부착된* 프로파일과 모드를 보여주는 가장 신뢰할 수 있는 확인 수단이다.

> **함정**: 프로파일을 적재했는데 `current`가 `unconfined`로 보이는 경우가 있다. 거의 대부분 (a) 데몬을 재시작하지 않았거나, (b) 프로파일 헤더의 경로가 실제 실행 경로와 일치하지 않거나, (c) 실행 파일이 심볼릭 링크인데 대상 경로가 다르다.

### 4.4 `aa-autodep` / `aa-genprof` 비교 체험

같은 데몬을 자동 생성기로도 한 번 만들어보고, 손으로 만든 것과 비교한다.

```bash
# 골격만 생성 (적재 안 함). 기존 프로파일을 백업해두고 시도하자.
sudo cp /etc/apparmor.d/usr.local.bin.myapp{,.handwritten}
sudo aa-autodep /usr/local/bin/myapp
sudo cat /etc/apparmor.d/usr.local.bin.myapp
```

전형적으로 `aa-autodep`은 `abstractions/base` + 실행 파일 자체에 대한 `mr` + 일반적인 헤더를 끼운 골격을 만들어준다. *우리가 손으로 만든 것과 본질적으로 같다*.

학습이 끝났으면 손으로 만든 버전으로 복원하고 진행한다.

```bash
sudo mv /etc/apparmor.d/usr.local.bin.myapp.handwritten \
        /etc/apparmor.d/usr.local.bin.myapp
sudo apparmor_parser -r /etc/apparmor.d/usr.local.bin.myapp
sudo systemctl restart myapp.service
```

---

## 5. 학습 사이클 (complain → logprof → enforce)

여기가 본 편의 핵심이다. 한 사이클을 *천천히* 돌려본다.

```
[1] 시나리오 정의      ← "정상 사용"이 무엇인지 합의
        ↓
[2] complain 모드 실행 ← 일부러 로그를 쌓는다
        ↓
[3] aa-logprof 반영    ← 사람이 한 줄씩 결정
        ↓
[4] 다시 시나리오 실행 ← 추가 위반이 없는지 확인
        ↓
[5] enforce 전환       ← 운영 모드로
        ↓
[6] 회귀 테스트        ← 거부도 정상 동작도 둘 다 검증 (8장)
```

### 5.1 시나리오 정의

`myapp`의 "정상 사용"은 다음 4가지로 한다.

1. systemd가 `myapp`을 시작한다.
2. `curl http://127.0.0.1:8080/index.txt` 가 200으로 응답한다.
3. `curl http://127.0.0.1:8080/notfound` 가 404로 응답한다(파일 시스템 stat까지 발생).
4. systemd가 `myapp`을 SIGTERM으로 정지한다 (PID 파일 정리 포함).

### 5.2 complain 모드에서 시나리오 실행

complain 모드에서는 *위반이 발생해도 막지 않고 로그만* 남는다. 모든 위반을 한 번에 모으려면 시나리오를 깨끗하게 한 번 실행해야 한다.

```bash
# 데몬 재시작 (정책은 이미 complain 모드로 적재됨)
sudo systemctl restart myapp.service

# 시나리오 1·2·3 수행
sleep 1
curl -sS http://127.0.0.1:8080/index.txt
curl -sS -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8080/notfound

# 시나리오 4 — 정지
sudo systemctl stop myapp.service

# 위반 로그 확인
sudo dmesg -T | grep 'apparmor=' | grep myapp | tail -n 30
```

전형적으로 다음과 같은 라인이 보인다 (요약):

```
apparmor="ALLOWED" operation="open"  profile="/usr/local/bin/myapp" name="/etc/myapp/config.json" requested_mask="r" ...
apparmor="ALLOWED" operation="open"  profile="/usr/local/bin/myapp" name="/srv/myapp/files/" requested_mask="r" ...
apparmor="ALLOWED" operation="mknod" profile="/usr/local/bin/myapp" name="/run/myapp.pid"     ...
apparmor="ALLOWED" operation="open"  profile="/usr/local/bin/myapp" name="/var/log/myapp/access.log" requested_mask="wa" ...
apparmor="ALLOWED" operation="bind"  profile="/usr/local/bin/myapp" ...
```

complain에서는 `apparmor="ALLOWED"` 로 찍히지만 그 의미는 *"enforce였으면 막혔을 동작"* 이다.

### 5.3 `aa-logprof`로 한 줄씩 정책에 반영

`aa-logprof`는 위 로그를 읽어 사람에게 한 항목씩 보여주고, 어떻게 정책에 반영할지 묻는 인터랙티브 도구다.

```bash
sudo aa-logprof
```

화면 예시 (개념도):

```
Profile:  /usr/local/bin/myapp
Path:     /etc/myapp/config.json
Mode:     r
Severity: unknown

 [1 - include <abstractions/base>]
  2 - /etc/myapp/config.json r,
  3 - /etc/myapp/* r,
  4 - /etc/** r,

(A)llow / (D)eny / (I)gnore / (G)lob / glob with (E)xtension /
(N)ew / Audi(T) / Abo(R)t / (F)inish / (M)ore
```

**선택 가이드** (학습용):

| 상황 | 권장 선택 |
|---|---|
| 단일 파일 한 번 접근 | `Allow` (옵션 1·2 그대로) |
| 같은 디렉터리에 비슷한 파일 여럿 (예: `/srv/myapp/files/index.txt`, `/srv/myapp/files/about.html`) | `Glob` → `/srv/myapp/files/*` |
| 디렉터리 전체 서브트리 (예: `/srv/myapp/files/sub/...`) | `Glob with Extension` 두 번 → `/srv/myapp/files/**` |
| 실수로 잡힌 무관한 경로 | `Deny` 또는 `Ignore` |
| abstractions로 묶을 만한 묶음 | `Allow` 후 6장에서 abstraction으로 리팩토링 |

본 데몬에 대해 우리가 합의할 결과:

- `/etc/myapp/config.json r,`
- `/srv/myapp/files/ r,`
- `/srv/myapp/files/** r,`
- `/var/log/myapp/access.log w,`
- `/run/myapp.pid w,`
- `network inet stream,` (TCP listen)
- 실행 파일 자체는 이미 부착 시 자동 처리되지만 명시: `/usr/local/bin/myapp mr,`

`aa-logprof`가 끝나면 변경 사항을 저장(`S`)하고 빠져나온다. 프로파일은 자동으로 다시 적재된다.

### 5.4 적재된 프로파일 확인

```bash
sudo cat /etc/apparmor.d/usr.local.bin.myapp
```

전형적으로 다음과 같은 형태가 되어 있다(주석은 학습용).

```apparmor
abi <abi/4.0>,

include <tunables/global>

/usr/local/bin/myapp flags=(complain) {
  include <abstractions/base>

  /usr/local/bin/myapp mr,

  /etc/myapp/config.json r,
  /srv/myapp/files/ r,
  /srv/myapp/files/** r,
  /var/log/myapp/access.log w,
  /run/myapp.pid w,

  network inet stream,
}
```

> 만약 위 형태와 다르거나 항목이 누락됐다면, 시나리오 실행을 한 번 더 하고 `aa-logprof`를 다시 돌려서 마저 채운다.

### 5.5 두 번째 시나리오 — "추가 위반 없음"을 확인

```bash
sudo systemctl restart myapp.service
curl -sS http://127.0.0.1:8080/index.txt
curl -sS -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8080/notfound
sudo systemctl stop myapp.service

# 새로운 ALLOWED 라인이 더 이상 안 나와야 한다
sudo dmesg -T | grep 'apparmor=' | grep myapp | tail
```

새 위반이 없으면 프로파일은 *현재 시나리오 기준으로* 완전하다.

### 5.6 enforce로 전환

```bash
sudo aa-enforce /etc/apparmor.d/usr.local.bin.myapp

# 헤더 플래그가 변경되었는지 확인
sudo head -3 /etc/apparmor.d/usr.local.bin.myapp
# /usr/local/bin/myapp {        ← flags=(complain) 가 사라짐

sudo systemctl restart myapp.service
PID=$(cat /run/myapp.pid)
cat /proc/$PID/attr/current
# /usr/local/bin/myapp (enforce)
```

### 5.7 enforce 검증 — 정책이 *실제로* 막는지 시험

학습 사이클의 마무리는 *정책이 정말 강제되는지* 직접 시험하는 것이다.

```bash
# 시나리오에 없던 파일 접근을 의도적으로 시도
# (myapp이 임의 파일을 열도록 만들 권한이 우리에겐 없으므로,
#  대신 myapp이 의존하는 자원을 일부러 빼고 다시 시작해본다)

# 1) 설정 파일을 일시적으로 권한 없는 위치로 옮기기
sudo mv /etc/myapp/config.json /etc/myapp/config.json.bak
sudo systemctl restart myapp.service
sleep 1
sudo systemctl --no-pager status myapp.service | head -n 5
# Active: failed
sudo journalctl -u myapp.service -n 5 --no-pager
# FileNotFoundError: '/etc/myapp/config.json'   ← DAC 단계에서 이미 실패

sudo mv /etc/myapp/config.json.bak /etc/myapp/config.json

# 2) 이번엔 AppArmor에 막힐 만한 상황을 만든다.
#    /srv/myapp/files/ 밖을 향한 심링크
sudo ln -sf /etc/passwd /srv/myapp/files/passwd
sudo systemctl restart myapp.service
sleep 1
curl -sS -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8080/passwd
# 403 또는 500이 나오고
sudo dmesg -T | grep 'apparmor=' | grep myapp | tail -3
# apparmor="DENIED" operation="open" name="/etc/passwd" requested_mask="r" ...

sudo rm /srv/myapp/files/passwd
```

- 첫 번째는 DAC가 처리한 케이스고(파일이 없음).
- 두 번째가 진짜 AppArmor 거부다 — 데몬이 심링크를 따라 `/etc/passwd`를 읽으려 했고, `/srv/myapp/files/**`만 허용된 정책이 막았다.

이 한 사이클을 완주했다면 본 편의 핵심 학습 목표는 달성된 것이다. 이후 6~9장은 정책의 *품질*과 *운영성*을 끌어올리는 단계다.

---

## 6. 정책 리팩토링 패턴

5장에서 만들어진 프로파일은 동작은 하지만 다음과 같은 결함이 있다.

- 모든 규칙이 한 파일에 평면적으로 나열됨.
- 다른 데몬에도 공통될 만한 규칙(예: 로그 디렉터리 패턴)이 추상화 안 됨.
- 사이트별 패치가 본 프로파일을 직접 수정하게 되어 패키지 업그레이드 시 충돌 위험.

이를 단계적으로 정리한다.

### 6.1 abstractions로 공통 묶기

여러 프로파일이 공유할 수 있는 규칙은 `/etc/apparmor.d/abstractions/` 안에 별도 파일로 두고 include 한다.

```bash
sudo tee /etc/apparmor.d/abstractions/myapp-runtime >/dev/null <<'AA'
# Common runtime needs for myapp-family services
/etc/myapp/*.json r,
/var/log/myapp/*.log w,
/run/myapp*.pid w,
AA
```

본 프로파일에서 활용:

```apparmor
/usr/local/bin/myapp {
  include <abstractions/base>
  include <abstractions/myapp-runtime>

  /usr/local/bin/myapp mr,
  /srv/myapp/files/ r,
  /srv/myapp/files/** r,
  network inet stream,
}
```

### 6.2 owner 한정자

본 데몬은 단일 사용자(systemd가 띄운 root)로 동작하지만, 사용자별 데이터를 다루는 데몬에서는 다음 패턴이 거의 필수다.

```apparmor
owner /home/*/.myapp/** rw,    # 실효 UID == 파일 소유자 인 경우에만 허용
```

`owner`가 없으면 root로 도는 데몬이 *다른 사용자의 홈* 까지 접근하는 것이 허용될 수 있다.

### 6.3 변수(`@{HOME}` 등)와 tunables

`/etc/apparmor.d/tunables/global`에 정의된 매크로:

```apparmor
@{HOME}=/home/*/ /root/
@{PROC}=/proc/
@{multiarch}={x86_64,aarch64}-linux-gnu
```

활용:

```apparmor
@{HOME}/.myapp/** rw,
@{PROC}/sys/kernel/random/uuid r,
```

사이트별로 매크로를 추가 정의하고 싶다면 `/etc/apparmor.d/tunables/myapp` 같은 파일을 만들고 `tunables/global`을 수정하지 않는다 (패키지 업그레이드 충돌 회피).

### 6.4 `local/` 분리 — 사이트 패치 보존 패턴

본 시리즈 전반에서 채택할 컨벤션이다. 본 프로파일 끝에 `include if exists` 한 줄을 넣어두고, 사이트별 추가 규칙은 `local/` 아래 같은 이름으로 둔다.

```apparmor
/usr/local/bin/myapp {
  include <abstractions/base>
  include <abstractions/myapp-runtime>

  /usr/local/bin/myapp mr,
  /srv/myapp/files/ r,
  /srv/myapp/files/** r,
  network inet stream,

  include if exists <local/usr.local.bin.myapp>
}
```

사이트 패치 예시 (예: 사이트가 `/data/extra` 도 서빙):

```bash
sudo tee /etc/apparmor.d/local/usr.local.bin.myapp >/dev/null <<'AA'
/data/extra/ r,
/data/extra/** r,
AA

sudo apparmor_parser -r /etc/apparmor.d/usr.local.bin.myapp
```

이 컨벤션을 지키면 향후 패키지(또는 OpenStack-Helm chart)가 본 프로파일을 갱신해도 `local/` 패치는 보존된다.

### 6.5 deny와 audit

명시적 거부와 보조 감사 플래그도 자주 쓰인다.

```apparmor
deny /etc/shadow rwklx,            # 명시적 거부 — 다른 어떤 규칙보다 우선
audit /var/log/myapp/access.log w, # 허용하되 모든 쓰기를 audit 로그에 기록
```

### 6.6 리팩토링 후 검증

리팩토링이 행위를 바꾸지 않았는지 5장 시나리오를 한 번 더 돌리고 새 DENIED가 없는지 확인한다.

```bash
sudo apparmor_parser -r /etc/apparmor.d/usr.local.bin.myapp
sudo systemctl restart myapp.service
curl -sS http://127.0.0.1:8080/index.txt >/dev/null
sudo dmesg -T | grep 'apparmor="DENIED"' | tail
```

---

## 7. 정책의 단위 테스트 (CI 검증)

정책을 코드로 본다는 것은 곧 *정책이 PR로 들어오면 자동으로 검증된다* 는 뜻이다. 여기서는 사람의 손이 닿지 않는 자동 검증 두 단계를 만든다.

### 7.1 정책 코드 저장소 구조

```bash
mkdir -p ~/apparmor-lab/policies/{base,abstractions,local}
cp /etc/apparmor.d/usr.local.bin.myapp                ~/apparmor-lab/policies/base/
cp /etc/apparmor.d/abstractions/myapp-runtime         ~/apparmor-lab/policies/abstractions/
[ -f /etc/apparmor.d/local/usr.local.bin.myapp ] && \
  cp /etc/apparmor.d/local/usr.local.bin.myapp        ~/apparmor-lab/policies/local/

cd ~/apparmor-lab
git init -q && git add . && git commit -q -m "initial myapp policy"
```

이상적인 디렉터리 구조 (시리즈 전반에서 채택):

```
apparmor-lab/
├── policies/
│   ├── base/                  # 본 프로파일들
│   ├── abstractions/          # 사이트 abstractions
│   └── local/                 # 사이트 보강
├── tests/
│   ├── parse/                 # 7장
│   └── e2e/                   # 8장
└── ci/
    └── parse.sh
```

### 7.2 `apparmor_parser`로 문법 검증 (`-QT`)

`-Q`(`--skip-cache`) + `-T`(`--skip-kernel-load`)는 *컴파일만 해보고 멈추는* 옵션이다. CI에서 실 커널을 건드리지 않고 검증할 수 있다.

```bash
sudo apparmor_parser -QT \
  --include /etc/apparmor.d \
  ~/apparmor-lab/policies/base/usr.local.bin.myapp
echo "exit=$?"
```

종료 코드 0이면 문법·include 해소 모두 OK. 종료 코드가 0이 아니면 그 메시지를 그대로 PR에 알려준다.

### 7.3 룰 다운그레이드·미적용 경고

1편 8.4절에서 언급한 *조용한 무시* 를 잡는 옵션이다. 사이트가 더 새로운 ABI 정책을 작성했는데 일부 노드 커널이 그 키워드를 모를 때를 검출한다.

```bash
sudo apparmor_parser -QT \
  --warn=rules-not-enforced \
  --warn=rule-downgraded \
  --include /etc/apparmor.d \
  ~/apparmor-lab/policies/base/usr.local.bin.myapp 2>&1 | tee /tmp/parse.log

# 경고가 단 한 줄이라도 있으면 fail
if grep -q '^Warning' /tmp/parse.log; then
  echo "FAIL: warnings present" >&2
  exit 1
fi
```

### 7.4 CI 워크플로 샘플

GitLab CI 예시 (사이트가 GitHub Actions라면 동등하게 변환 가능):

```yaml
# .gitlab-ci.yml
stages: [validate]

apparmor-parse:
  stage: validate
  image: ubuntu:24.04
  before_script:
    - apt-get update -qq
    - apt-get install -y -qq apparmor apparmor-utils
  script:
    - |
      set -e
      for f in policies/base/*; do
        echo "== $f =="
        apparmor_parser -QT \
          --warn=rules-not-enforced --warn=rule-downgraded \
          --include policies \
          "$f"
      done
```

> **운영 팁**: `--include policies`로 *프로파일 저장소 내부의 abstractions*만 보도록 한정하면, 호스트의 `/etc/apparmor.d/abstractions/`에 우연히 있던 파일 때문에 CI가 통과되는 *가짜 그린* 을 막을 수 있다. 단, `<abstractions/base>` 같은 표준 abstraction은 시스템의 것을 빌릴지 사이트가 사본을 둘지 정책으로 결정해야 한다.

### 7.5 (선택) `bats`로 파서 결과 단위 테스트

```bash
cat > ~/apparmor-lab/tests/parse/myapp.bats <<'BATS'
#!/usr/bin/env bats

setup() {
  POLICY="${BATS_TEST_DIRNAME}/../../policies/base/usr.local.bin.myapp"
  INCLUDE="${BATS_TEST_DIRNAME}/../../policies"
}

@test "myapp profile parses without errors" {
  run sudo apparmor_parser -QT --include "$INCLUDE" "$POLICY"
  [ "$status" -eq 0 ]
}

@test "myapp profile has no downgraded rules" {
  run sudo apparmor_parser -QT \
        --warn=rule-downgraded --include "$INCLUDE" "$POLICY"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Warning"* ]]
}
BATS

cd ~/apparmor-lab && bats tests/parse/
```

---

## 8. 시스템 통합 테스트

파서 검증만으로는 *런타임에 정말 동작하는가* 를 보장하지 못한다. 두 종류의 시나리오를 자동화한다.

### 8.1 양성 시나리오 (정상 동작이 깨지지 않는지)

```bash
mkdir -p ~/apparmor-lab/tests/e2e
cat > ~/apparmor-lab/tests/e2e/myapp_positive.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail

sudo systemctl restart myapp.service
sleep 1

# 1. 정상 GET
test "$(curl -sS http://127.0.0.1:8080/index.txt)" = "hello from myapp"

# 2. 404
code=$(curl -sS -o /dev/null -w "%{http_code}" http://127.0.0.1:8080/notfound)
test "$code" = "404"

# 3. PID 파일
test -f /run/myapp.pid

# 4. 로그가 갱신됨
size_before=$(stat -c%s /var/log/myapp/access.log)
curl -sS http://127.0.0.1:8080/index.txt >/dev/null
size_after=$(stat -c%s /var/log/myapp/access.log)
test "$size_after" -gt "$size_before"

echo "POSITIVE: PASS"
SH
chmod +x ~/apparmor-lab/tests/e2e/myapp_positive.sh
~/apparmor-lab/tests/e2e/myapp_positive.sh
```

### 8.2 거부 시나리오 (의도한 위반이 *정말* 막히는지)

```bash
cat > ~/apparmor-lab/tests/e2e/myapp_negative.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail

# 직전 dmesg 마커 위치
before=$(sudo dmesg | wc -l)

# /srv/myapp/files/ 안에서 /etc/passwd로 향한 심링크
sudo ln -sf /etc/passwd /srv/myapp/files/passwd
trap 'sudo rm -f /srv/myapp/files/passwd' EXIT

sudo systemctl restart myapp.service
sleep 1
curl -sS -o /dev/null http://127.0.0.1:8080/passwd || true

# DENIED 발생을 기대
denied=$(sudo dmesg | tail -n +$((before+1)) | \
         grep -c 'apparmor="DENIED".*name="/etc/passwd".*profile="/usr/local/bin/myapp"' || true)
test "$denied" -ge 1 || { echo "FAIL: expected DENIED for /etc/passwd"; exit 1; }

echo "NEGATIVE: PASS (denied=$denied)"
SH
chmod +x ~/apparmor-lab/tests/e2e/myapp_negative.sh
~/apparmor-lab/tests/e2e/myapp_negative.sh
```

### 8.3 ausearch 자동화

`auditd`가 켜져 있으면 audit 로그가 정형화되어 있어 파싱하기 쉽다.

```bash
sudo ausearch -m AVC,USER_AVC -ts recent | \
  awk '/apparmor=.DENIED./ && /myapp/ { print }'
```

CI 안에서 노드별로 거부 카운트를 모아 임계값 알람으로 쓰는 패턴은 9편에서 이어 다룬다.

### 8.4 회귀 셋 통합

```bash
cat > ~/apparmor-lab/tests/e2e/run_all.sh <<'SH'
#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
./myapp_positive.sh
./myapp_negative.sh
SH
chmod +x ~/apparmor-lab/tests/e2e/run_all.sh
```

이 셋이 "변경이 들어올 때마다 도는 회귀 스위트"다. 7장 CI 파이프라인의 또 다른 잡으로 추가하면, 정책 변경 PR마다 자동으로 양성·거부가 모두 검증된다.

---

## 9. 자주 발생하는 시행착오와 해결

실제 작성 중 만나기 쉬운 함정을 카탈로그로 정리한다.

### 9.1 "프로파일이 부착되지 않는다"

**증상**: `aa-status`에는 보이는데 `cat /proc/<PID>/attr/current` 가 `unconfined`.

**원인 후보**:

1. 데몬을 재시작하지 않음 (가장 흔함). 부착은 *execve 시점*에만 일어난다.
2. 헤더의 경로가 실제 실행 경로와 불일치.
3. systemd가 `ExecStart=` 의 경로를 따라가는데 그 경로가 심볼릭 링크여서 실제 경로가 다름. `readlink -f` 로 확인.
4. 컨테이너 안 데몬인데 호스트 정책이 컨테이너 경로를 모름 (5편 이후 주제).

### 9.2 mmap 거부 — `abstractions/base` 누락

**증상**: 데몬이 시작 즉시 죽는다. 로그:

```
apparmor="DENIED" operation="file_mmap" name="/lib/x86_64-linux-gnu/libc.so.6" requested_mask="m"
```

**해결**: `include <abstractions/base>` 를 본문 첫 줄에 추가. 거의 모든 동적 링크 바이너리에 필수.

### 9.3 경로 와일드카드가 빗나간다

**증상**: 정책에 `/srv/myapp/files/**` 를 두었는데 거부됨.

**원인**:

- 실제 접근 경로가 `/srv/myapp/files/sub/x` 인데 우리는 `*` 한 개만 썼다 → `**` 로 변경.
- 객체가 *다른 경로*로도 노출됨 — 바인드 마운트, 심링크. AppArmor는 namespace의 *최상위 경로* 를 본다. 컨테이너·chroot 환경에선 `flags=(attach_disconnected)` 가 필요하기도 하다.

### 9.4 Px 전이 실패

**증상**:

```
apparmor="DENIED" operation="exec" target="/usr/bin/foo" ...
```

**원인**: 자식 프로세스를 다른 프로파일로 transition 하도록 작성했는데(`/usr/bin/foo Px,`) 그 프로파일이 적재되어 있지 않음.

**해결**: 자식 프로파일을 먼저 적재하거나, 전이가 필요 없으면 `ix` (현재 프로파일 유지) 또는 `Cx -> child_name` (인라인 자식) 사용.

### 9.5 silently ignored rules

**증상**: `apparmor_parser -r` 가 성공했는데 정책이 *동작하지 않는다*.

**원인**: 작성한 키워드를 현재 커널이 모름 (예: 더 새로운 ABI의 `mqueue`, `io_uring`).

**해결**:

```bash
sudo apparmor_parser -QT \
  --warn=rules-not-enforced \
  --warn=rule-downgraded /etc/apparmor.d/...
```

CI에 7.3절 수준으로 묶어둔다.

### 9.6 `unprivileged user namespace` 관련 이상

**증상**: 24.04에서 *잘 돌던* 데몬 일부가 user namespace를 만들지 못해 실패.

**원인**: `kernel.apparmor_restrict_unprivileged_userns = 1` 기본값.

**해결** (1편 7.3절 그대로):

1. 권장 — 해당 데몬 프로파일에 `userns,` 추가.
2. 임시 — `echo 0 | sudo tee /proc/sys/kernel/apparmor_restrict_unprivileged_userns`.

### 9.7 "logprof가 같은 줄을 또 묻는다"

**증상**: `aa-logprof` 를 돌렸는데 다음 사이클에서 동일 항목이 또 등장.

**원인**: complain 모드에서 누적된 *오래된* 로그가 남아 있음. 매 사이클 시작 전에 로그 마커를 잡으면 깨끗하다.

```bash
sudo dmesg -c >/dev/null              # 링 버퍼 비우기 (학습 환경에서만!)
# 시나리오 실행
sudo aa-logprof
```

운영 환경에선 `dmesg -c`를 함부로 쓰지 않는다. `journalctl --since now` 식으로 시간 윈도를 잡는다.

---

## 10. 점검 질문 + 다음 편 예고

### 점검 질문

1. complain 모드와 enforce 모드의 *로그 표현* 은 어떻게 다른가? (ALLOWED vs DENIED)
2. `apparmor_parser -QT` 를 쓰는 이유는? `-r`과의 차이는?
3. 본 편의 양성/거부 회귀 스크립트가 정책 PR마다 *반드시* 돌아야 하는 이유를 두 문장으로 설명하라.
4. `/etc/apparmor.d/local/<name>` 컨벤션이 패키지(또는 chart) 업그레이드 시 왜 안전한가?
5. enforce 전환 후 데몬이 계속 멀쩡히 도는 것을 어떻게 *증명* 할 것인가? 절차를 작성하라.
6. `silently ignored rules` 가 가장 위험한 이유는?
7. systemd가 띄운 데몬에서 `cat /proc/<PID>/attr/current` 가 `unconfined` 로 나올 때 점검 순서를 5단계로 작성하라.

### 다음 편 예고 — 3편

본 편에서 *정책 작성 사이클* 을 손에 익혔다면, 3편에서는 **"왜 가상화 호스트에 MAC가 필요한가"** 를 위협 모델 관점에서 다룬다. KVM/QEMU 아키텍처와 STRIDE 분류, 실제 사례(Venom 등) 분석을 거쳐 sVirt가 왜 *동적* 프로파일이라는 발상을 채택했는지 이해한다. 본 편의 학습 사이클이 4편(libvirt sVirt 단일 호스트)과 7편(OpenStack-Helm + ArgoCD 통합)에서 *그대로* 다시 등장하므로 본 편이 시리즈 전체의 운영 기본기다.

---

## 부록 A. 본 편 전체 명령 한 페이지 요약

```bash
# === 환경 준비 ===
sudo apt install -y apparmor apparmor-utils apparmor-profiles-extra auditd

# === 데몬 설치 (3장) ===
sudo install -d -m 0755 /etc/myapp /srv/myapp/files /var/log/myapp
# /etc/myapp/config.json, /usr/local/bin/myapp, /etc/systemd/system/myapp.service 작성
sudo systemctl daemon-reload
sudo systemctl enable --now myapp.service

# === 프로파일 골격 적재 (4장) ===
sudo tee /etc/apparmor.d/usr.local.bin.myapp >/dev/null <<'AA'
abi <abi/4.0>,
include <tunables/global>
/usr/local/bin/myapp flags=(complain) {
    include <abstractions/base>
}
AA
sudo apparmor_parser -r /etc/apparmor.d/usr.local.bin.myapp
sudo systemctl restart myapp.service

# === 학습 사이클 (5장) ===
sudo systemctl restart myapp.service
curl -sS http://127.0.0.1:8080/index.txt
curl -sS -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8080/notfound
sudo systemctl stop myapp.service
sudo dmesg -T | grep 'apparmor=' | grep myapp | tail
sudo aa-logprof
sudo aa-enforce /etc/apparmor.d/usr.local.bin.myapp

# === 부착 확인 ===
sudo systemctl restart myapp.service
PID=$(cat /run/myapp.pid); cat /proc/$PID/attr/current

# === 리팩토링 (6장) ===
# - abstractions/myapp-runtime 추출
# - owner / @{HOME} / tunables 적용
# - include if exists <local/usr.local.bin.myapp>

# === CI 검증 (7장) ===
sudo apparmor_parser -QT \
    --warn=rules-not-enforced --warn=rule-downgraded \
    --include /etc/apparmor.d /etc/apparmor.d/usr.local.bin.myapp

# === 회귀 테스트 (8장) ===
~/apparmor-lab/tests/e2e/run_all.sh
```

## 부록 B. `myapp` 완성 프로파일 (참고)

```apparmor
# /etc/apparmor.d/usr.local.bin.myapp
abi <abi/4.0>,

include <tunables/global>

/usr/local/bin/myapp {
    include <abstractions/base>
    include <abstractions/myapp-runtime>     # 6.1절에서 추출

    /usr/local/bin/myapp mr,

    # 정적 자원 — 도큐먼트 루트
    /srv/myapp/files/   r,
    /srv/myapp/files/** r,

    # 명시적 거부 (방어적)
    deny /etc/shadow rwklx,
    deny /root/**    rwklx,

    # 네트워크
    network inet  stream,
    network inet6 stream,

    # 사이트 보강
    include if exists <local/usr.local.bin.myapp>
}
```

```apparmor
# /etc/apparmor.d/abstractions/myapp-runtime
/etc/myapp/*.json     r,
/var/log/myapp/*.log  w,
/run/myapp*.pid       w,
```

```apparmor
# /etc/apparmor.d/local/usr.local.bin.myapp  (사이트별 — 비어있어도 OK)
# 예: /data/extra/** r,
```

---

## 참고

- 1편: `01_Ubuntu24.04_AppArmor_기초_심화.md`
- 환경 컨텍스트: `00_환경_컨텍스트.md`
- 시리즈 로드맵: `00_시리즈_로드맵.md`
- 공식 매뉴얼: [`apparmor.d(5)`](https://manpages.ubuntu.com/manpages/noble/man5/apparmor.d.5.html), [`aa-logprof(8)`](https://manpages.ubuntu.com/manpages/noble/man8/aa-logprof.8.html), [`apparmor_parser(8)`](https://manpages.ubuntu.com/manpages/noble/man8/apparmor_parser.8.html)
- AppArmor upstream: [apparmor.net](https://apparmor.net/), [GitLab apparmor/apparmor](https://gitlab.com/apparmor/apparmor)
