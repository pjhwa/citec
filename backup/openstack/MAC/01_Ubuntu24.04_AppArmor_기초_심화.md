# Ubuntu 24.04 AppArmor 적용 - 소개·개념·기초 (심화)

> 본 문서는 OpenStack Helm 기반 Ubuntu 24.04(Noble Numbat) 하이퍼바이저 환경에 MAC(sVirt + AppArmor)을 적용하기 위한 시리즈 교육 자료의 첫 번째 편입니다. AppArmor의 정의·아키텍처·정책 구조·운영 모드·기본 명령어·디버깅·sVirt 연동 맥락까지, 공식 문서를 1차 레퍼런스로 하여 이해하기 쉽게 정리합니다.
>
> **대상 독자**: 리눅스 시스템·가상화·OpenStack 운영 경험은 있으나 MAC 보안 모듈은 처음 접하는 엔지니어
>
> **참고 1차 출처**
> - Ubuntu Security Documentation: AppArmor (`documentation.ubuntu.com/security/security-features/privilege-restriction/apparmor/`)
> - Ubuntu Server Documentation: AppArmor (`documentation.ubuntu.com/server/how-to/security/apparmor/`)
> - The Linux Kernel Documentation: AppArmor (`docs.kernel.org/admin-guide/LSM/apparmor.html`)
> - Ubuntu Manpages (Noble): `apparmor(7)`, `apparmor.d(5)`, `aa-status(8)`, `aa-genprof(8)`, `apparmor_parser(8)`
> - upstream AppArmor 프로젝트 (`apparmor.net`, `gitlab.com/apparmor/apparmor`)
> - Ubuntu Wiki: `LibvirtApparmor`, `SecurityTeam/Specifications`

---

## 목차

1. AppArmor 소개
2. 핵심 개념: DAC, MAC, LSM, 경로 기반 정책
3. AppArmor 아키텍처
4. 동작 모드 (Enforce / Complain / Disable / Audit)
5. 프로파일 구조와 문법
6. 기초 명령어와 운영 흐름
7. Ubuntu 24.04에서의 주요 변화 (AppArmor 4.0)
8. 디버깅과 트러블슈팅
9. OpenStack 하이퍼바이저 맥락 - libvirt sVirt와의 연결
10. 요약 및 다음 단계

---

## 1. AppArmor 소개

### 1.1 정의

AppArmor(Application Armor)는 리눅스 커널의 LSM(Linux Security Module) 프레임워크 위에서 동작하는 **MAC(Mandatory Access Control, 강제 접근 통제)** 구현체입니다. 각 프로세스에 "프로파일(profile)"이라 부르는 정책 파일을 부착하여, 그 프로세스가 접근할 수 있는 파일 경로·Capability·네트워크·시그널·마운트 등을 화이트리스트 방식으로 제한합니다.

공식 정의를 그대로 옮기면 다음과 같습니다.

> *"AppArmor is a MAC style security extension for the Linux kernel that implements a task centered policy, with task 'profiles' being created and loaded from user space."* — Linux Kernel Documentation, *AppArmor*

핵심을 정리하면, AppArmor는 (1) 커널 모듈로 동작하는 **태스크 중심(task-centered)** 정책 엔진이며, (2) 사람이 읽기 쉬운 **텍스트 기반 프로파일**을 사용자 공간에서 작성·로딩하고, (3) 표준 DAC(소유자/그룹/퍼미션) 위에 추가 제한층을 덧씌우는 도구입니다.

### 1.2 등장 배경과 역사

| 시기 | 사건 |
|---|---|
| 1998 ~ 2005 | Immunix 사가 SubDomain이라는 이름으로 개발 |
| 2005 | Novell이 인수, AppArmor로 이름 변경, 오픈 소스화 |
| 2009 | Canonical(Ubuntu)이 메인테이너 지위 인계 |
| 2010-10 | Linux 커널 2.6.36에 메인라인 머지 |
| 2017 ~ | Debian, openSUSE, Arch 등으로 채택 확산 |
| 2024-04 | AppArmor 4.0이 Ubuntu 24.04 LTS에 기본 탑재 |

Ubuntu 계열에서는 부팅 직후부터 다수의 시스템 데몬(예: `cups`, `tcpdump`, `man`, `lxc`, `libvirtd`, `snap` 등)이 AppArmor 프로파일로 보호됩니다. 즉, **Ubuntu에서 AppArmor는 기본 활성화(opt-out)** 정책입니다.

### 1.3 왜 OpenStack 하이퍼바이저에 중요한가

가상화 호스트는 다음과 같은 특성 때문에 일반 서버보다 강력한 격리가 필요합니다.

- **다중 테넌트(multi-tenant)**: 서로 다른 신뢰 도메인의 게스트가 같은 호스트에서 공존
- **공격면(attack surface) 비대칭**: QEMU/KVM 한 프로세스가 호스트 커널·다른 게스트의 디스크 이미지·NUMA 자원에 접근할 수 있는 잠재적 경로가 많음
- **테넌트 탈출(VM escape)**: QEMU 취약점 한 건이 노출되면 호스트 전체가 위태로워짐

libvirt는 sVirt 프레임워크를 통해 각 게스트 QEMU 프로세스에 **고유한 AppArmor 프로파일**을 동적으로 생성·부착함으로써, 설령 QEMU 자체가 탈취되더라도 그 프로세스가 자신의 디스크 이미지·자신의 vTPM·자신의 vhost 소켓 외에는 호스트 자원에 접근하지 못하도록 막습니다. 즉, AppArmor는 **VM escape 시 영향을 봉쇄(containment)** 하는 최후 방어선 역할을 합니다.

---

## 2. 핵심 개념

### 2.1 DAC와 MAC

리눅스 보안의 기본 모델은 **DAC(Discretionary Access Control, 임의 접근 통제)** 입니다. 파일을 만든 사용자가 `chmod`/`chown`으로 자유롭게 권한을 조정할 수 있으며, 권한의 결정 주체는 "리소스 소유자"입니다. 익숙한 `rwxr-xr-x`, `setuid`, ACL이 모두 DAC의 일부입니다.

DAC만으로는 다음과 같은 문제를 막기 어렵습니다.

- root로 동작하는 프로세스가 탈취되면 사실상 모든 파일·자원에 접근 가능
- 사용자가 실수로 민감 파일에 `chmod 777`을 걸어도 시스템이 막아주지 않음
- 애플리케이션이 의도치 않은 시스템 콜·경로에 접근해도 무방비

**MAC(Mandatory Access Control, 강제 접근 통제)** 는 시스템 관리자(또는 정책 작성자)가 사전에 정의한 규칙을 커널이 강제하며, 그 규칙은 **리소스 소유자가 변경할 수 없습니다**. AppArmor가 거부한 접근은 root 사용자라도 우회할 수 없다는 점이 DAC와의 가장 큰 차이입니다.

요약하면, MAC는 DAC를 **대체(replace)** 하는 것이 아니라 **보강(augment)** 합니다. 두 메커니즘은 동시에 적용되며, 두 곳 모두에서 허용되어야만 접근이 성립합니다.

```
요청 ──▶ DAC 체크 ──▶ MAC(LSM) 체크 ──▶ 허용 / 거부
         (rwx 등)      (AppArmor 등)
```

### 2.2 LSM(Linux Security Module) 프레임워크

LSM은 2002년 리눅스 2.6에 도입된 **커널 내부의 보안 후크(hook) 프레임워크**입니다. 커널 내 주요 동작 지점(파일 열기, 시스템 콜, 네트워크 송수신, 시그널 전송 등)에 후크를 두어, 등록된 보안 모듈이 "허용/거부"를 추가로 판단할 수 있게 합니다.

대표적인 LSM 모듈은 다음과 같습니다.

| 모듈 | 정책 모델 | 주요 배포판 |
|---|---|---|
| **AppArmor** | 경로 기반(path-based) MAC | Ubuntu, SUSE, Debian |
| **SELinux** | 레이블 기반(label-based) MAC | RHEL, Fedora, CentOS |
| **Smack** | 단순 레이블 MAC | Tizen 등 임베디드 |
| **TOMOYO** | 경로 기반 MAC, 학습 중심 | 일부 임베디드 |
| **Yama**, **Lockdown**, **Landlock**, **BPF-LSM** | 보조형 / 메이저 모듈과 동시 활성화 가능 | 모든 배포판 |

Ubuntu 24.04 커널은 기본적으로 AppArmor를 *primary* LSM으로 빌드되며, 부팅 시 자동 활성화됩니다. 커널 부트 파라미터로 `security=apparmor`(기본)를 지정하거나, 비활성화할 때는 `apparmor=0`을 사용합니다.

### 2.3 경로 기반 vs 레이블 기반

AppArmor와 SELinux를 구분 짓는 가장 중요한 차이는 **무엇으로 객체를 식별하는가** 입니다.

**경로 기반(AppArmor)**

```
/usr/sbin/nginx 프로세스가
  /var/log/nginx/access.log 파일을
  쓸 수 있다.
```

규칙은 텍스트 경로 그대로 작성되며, inode가 무엇이든 파일 시스템 경로가 일치하면 적용됩니다. 사람이 읽고 쓰기에 직관적이며, 정책의 인지 부담이 낮습니다. 단, 동일 inode가 다른 경로(하드 링크, 바인드 마운트)로 보이면 정책이 우회될 수 있어, AppArmor는 이를 막기 위한 별도 메커니즘(예: `mount` 규칙, `attach_disconnected` 등)을 가지고 있습니다.

**레이블 기반(SELinux)**

```
nginx 프로세스 컨텍스트 (httpd_t) 가
  파일 컨텍스트 (httpd_log_t) 에 대해
  write 액션을 가진다.
```

모든 객체에 보안 컨텍스트(레이블)를 부여하고, "주체-객체-액션" 삼중항으로 규칙을 작성합니다. 정밀하지만 학습 곡선이 가파르고, 파일 시스템 전체에 레이블 부여(restorecon) 운영 부담이 있습니다.

### 2.4 AppArmor와 SELinux 비교 요약

| 항목 | AppArmor | SELinux |
|---|---|---|
| 정책 식별자 | 파일 경로 | 보안 레이블(컨텍스트) |
| 정책 파일 위치 | `/etc/apparmor.d/` | `/etc/selinux/`, `*.te` |
| 조작 단위 | r/w/a/x/l/k/m/ix/ex 등 | 수십~수백 종 클래스·퍼미션 |
| 학습 곡선 | 낮음(text 한 파일) | 높음(타입·롤·도메인) |
| 기본 채택 배포판 | Ubuntu / SUSE / Debian | RHEL / Fedora / CentOS Stream |
| 정책 생성 보조 도구 | `aa-genprof`, `aa-logprof` | `audit2allow`, `sepolicy` |
| 제한 가능한 영역 | 파일·Capability·네트워크·mount·signal·dbus·ptrace·userns 등 | 거의 모든 커널 객체 |
| 컨테이너/가상화 통합 | libvirt sVirt-AppArmor, Docker, LXC | libvirt sVirt-SELinux, Docker |

두 방식 모두 "MAC"이라는 보안 목표는 동일합니다. AppArmor는 "쓰기 쉽고 운영하기 쉬운 MAC"을, SELinux는 "표현력이 더 높고 더 세밀한 MAC"을 지향합니다.

### 2.5 sVirt - 가상화에 특화된 MAC 활용 패턴

sVirt는 별도의 LSM이 아닙니다. **libvirt가 SELinux 또는 AppArmor를 호출하여, 게스트마다 동적으로 격리 정책을 생성·적용하는 추상 계층의 이름**입니다. Ubuntu에서는 libvirt가 AppArmor를 호출하므로 흔히 *sVirt-AppArmor* 라고 부릅니다. 동작 원리는 9장에서 자세히 다룹니다.

---

## 3. AppArmor 아키텍처

AppArmor는 크게 **커널 공간 컴포넌트**와 **사용자 공간 컴포넌트**로 나뉩니다.

```
┌──────────────────────────────────────────────────────────────┐
│                   사용자 공간(user space)                     │
│                                                              │
│  /etc/apparmor.d/*.profile         apparmor-utils            │
│   ├ tunables/                       ├ aa-status              │
│   ├ abstractions/                   ├ aa-enforce             │
│   └ usr.sbin.libvirtd               ├ aa-complain            │
│                                     ├ aa-genprof / aa-logprof│
│                                     └ aa-disable             │
│                       │                                       │
│                       ▼  apparmor_parser (텍스트→바이너리)     │
│                                                              │
│  systemd 유닛: apparmor.service                              │
└─────────────────────────┬────────────────────────────────────┘
                          │  write() to /sys/kernel/security/apparmor/.load
                          ▼
┌──────────────────────────────────────────────────────────────┐
│                   커널 공간(kernel space)                     │
│                                                              │
│   securityfs ──── /sys/kernel/security/apparmor/             │
│                       ├ profiles    (현재 로드된 프로파일)    │
│                       ├ .load       (프로파일 적재 진입점)    │
│                       ├ .replace                             │
│                       └ .remove                              │
│                                                              │
│   LSM 후크 → AppArmor 정책 매처(policy matcher) → 허용/거부  │
└──────────────────────────────────────────────────────────────┘
```

### 3.1 커널 공간 컴포넌트

- **AppArmor LSM 모듈**: `security/apparmor/` (Linux 소스 트리). 파일 시스템 접근, exec, capability, mount, ptrace, signal, network 등 LSM 후크에 콜백을 등록.
- **policy matcher**: 컴파일된 바이너리 정책을 메모리에서 빠르게 매칭. DFA 기반.
- **securityfs 인터페이스**: `/sys/kernel/security/apparmor/` 경로에 마운트되며, 프로파일 적재·교체·제거 진입점과 현재 상태 조회 인터페이스를 제공.
- **audit 서브시스템 연동**: 거부(DENIED) 또는 모드별 로깅 이벤트를 audit/dmesg에 기록.

### 3.2 사용자 공간 컴포넌트

- **`apparmor_parser`**: 텍스트 프로파일을 파싱·검증·최적화하여 커널 바이너리 형태로 변환 후 `securityfs`에 적재하는 핵심 도구.
- **`apparmor.service` (systemd)**: 부팅 시 `/etc/apparmor.d/` 안의 모든 활성 프로파일을 일괄 적재.
- **`apparmor-utils` 패키지**: `aa-status`, `aa-enforce`, `aa-complain`, `aa-disable`, `aa-genprof`, `aa-logprof`, `aa-unconfined`, `aa-mergeprof` 등 운영 보조 도구.
- **프로파일 텍스트 파일**: `/etc/apparmor.d/<name>` 형태로 보관. 디렉터리 트리 안의 `tunables/`, `abstractions/` 등은 재사용 가능한 조각.

### 3.3 정책 적재 흐름

부팅 시 또는 운영 중 정책 적용 흐름은 다음과 같습니다.

1. `apparmor.service`가 `apparmor_parser --add /etc/apparmor.d/...` 형태로 활성 프로파일 일괄 적재
2. `apparmor_parser`가 `tunables/`, `abstractions/` 등 include 파일까지 모두 전개(preprocess)
3. 결과를 정책 DFA로 컴파일 후 `securityfs`(`/sys/kernel/security/apparmor/.load`)에 write
4. 커널이 해당 프로파일을 메모리에 등록
5. 이후 매칭되는 실행 파일이 `execve`될 때, 커널이 자동으로 그 프로세스를 해당 프로파일에 부착(confine)

> **중요**: AppArmor는 정책 없이는 어떤 제한도 가하지 않습니다. *"For AppArmor to enforce any restrictions beyond standard Linux DAC permissions policy must be loaded into the kernel from user space."* (kernel.org)

### 3.4 securityfs 인터페이스 둘러보기

```bash
sudo mount | grep securityfs
# securityfs on /sys/kernel/security type securityfs (rw,nosuid,nodev,noexec,relatime)

sudo ls /sys/kernel/security/apparmor/
# .access  .load  .ns_level  .ns_name  .ns_stacked  .remove  .replace
# features  policy  profiles  raw_data  revision

sudo cat /sys/kernel/security/apparmor/profiles | head
# /usr/bin/man (enforce)
# /usr/bin/evince (enforce)
# libvirtd (enforce)
# ...
```

`profiles` 파일은 현재 커널에 적재된 프로파일의 이름과 모드를 나열합니다. `aa-status`는 이 파일을 읽어 가공해 보여주는 사용자 공간 도구일 뿐입니다.

---

## 4. 동작 모드

각 AppArmor 프로파일은 다음 모드 중 하나로 동작합니다.

### 4.1 Enforce (강제) 모드

- 정책에 명시된 행위만 허용, 그 외는 **거부 + 로깅(DENIED)**.
- 운영 환경 기본 모드.
- 프로파일 헤더에 모드 플래그가 없는 경우의 기본값.

### 4.2 Complain (학습) 모드

- 정책 위반 시 **거부하지 않고 로깅(ALLOWED)** 만 수행.
- 프로파일을 새로 만들거나, 변경 후 영향을 가늠할 때 사용.
- 헤더 플래그: `flags=(complain)` 또는 `aa-complain` 명령으로 전환.

### 4.3 Disabled (비활성)

- 해당 프로파일을 커널에서 언로드하고, 부팅 시 자동 적재 대상에서 제외.
- `aa-disable` 명령은 `/etc/apparmor.d/disable/`에 심볼릭 링크를 만들어 영구 비활성화.

### 4.4 Audit / Kill / Unconfined / Default-allow 등 보조 모드

- **audit**: 허용된 접근까지 모두 로깅. 보안 감사·포렌식 목적.
- **kill**: 위반 시 프로세스에 SIGKILL 전달. 거의 사용되지 않으나 즉시 차단이 필요한 경우.
- **prompt**: 사용자 공간 데몬에 위반을 통지하고 응답을 받아 처리(데스크톱 시나리오).
- **unconfined**: 프로파일이 부착되지 않은 상태. 일반 DAC만 적용.
- **default_allow** (4.0 신규): 명시되지 않은 권한을 허용으로 처리(opt-out 방식). 호환성 목적.

모드 간 전환은 다음과 같습니다.

```bash
sudo aa-complain /etc/apparmor.d/usr.sbin.libvirtd   # complain으로 전환
sudo aa-enforce /etc/apparmor.d/usr.sbin.libvirtd    # enforce로 전환
sudo aa-disable /etc/apparmor.d/usr.sbin.libvirtd    # 비활성화
```

**프로덕션 운영 원칙**: 프로파일을 최초 작성·검증할 때는 complain → 충분 기간 로그 수집 → enforce. 갑작스러운 enforce 전환은 서비스 중단을 유발할 수 있습니다.

---

## 5. 프로파일 구조와 문법

AppArmor 프로파일은 사람이 읽기 쉬운 텍스트 파일입니다. 다음은 *전형적인* 프로파일의 골격입니다.

```apparmor
# /etc/apparmor.d/usr.bin.example
abi <abi/4.0>,                          # (1) ABI 선언

include <tunables/global>               # (2) 전역 변수 include

/usr/bin/example flags=(attach_disconnected) {   # (3) 헤더 + 플래그
    include <abstractions/base>         # (4) 공통 abstraction
    include <abstractions/nameservice>

    capability net_bind_service,        # (5) capability 규칙

    /etc/example.conf r,                # (6) 파일 규칙
    /var/log/example.log w,
    /usr/bin/example mr,                # m=mmap, r=read
    owner /home/*/.example/** rw,

    network inet stream,                # (7) 네트워크 규칙
    network inet6 stream,

    signal (receive) peer=unconfined,   # (8) signal 규칙

    deny /etc/shadow rwklx,             # (9) 명시적 거부
}
```

각 항목을 차례대로 설명합니다.

### 5.1 파일 위치 규약

- 활성 프로파일: `/etc/apparmor.d/<name>` (보통 `/usr/bin/foo` → `usr.bin.foo`로 명명)
- 추가 비활성 보관 프로파일 모음: `/etc/apparmor.d/extra-profiles/`
- 사용자 공통 라이브러리: `/etc/apparmor.d/abstractions/`
- 변수 정의: `/etc/apparmor.d/tunables/`
- 일부 프로파일의 supplementary 파일: `/etc/apparmor.d/local/`
- `apparmor-profiles` 패키지가 제공하는 추가 표본 프로파일: `/usr/share/apparmor/extra-profiles/`

### 5.2 ABI 선언

```apparmor
abi <abi/4.0>,
```

AppArmor 4.0부터 도입된 헤더로, 프로파일이 **어느 정책 ABI 버전을 가정하고 작성되었는지** 선언합니다. 새 ABI에서 추가된 키워드(예: `userns`)나 의미 변경이 있더라도, 선언이 명확하므로 파서가 적절히 처리할 수 있습니다.

### 5.3 Includes - tunables, abstractions, program-chunks

AppArmor의 정책 재사용성은 세 가지 include 메커니즘에 기반합니다.

**(a) tunables** - 전역 변수

`/etc/apparmor.d/tunables/global`에는 `@{HOME}`, `@{PROC}` 등의 매크로가 정의됩니다. 모든 프로파일이 자유롭게 참조할 수 있어, 경로의 사이트별 상수를 한곳에서 바꿀 수 있습니다.

**(b) abstractions** - 공통 작업 묶음

`abstractions/base`는 거의 모든 프로파일이 include하는 "최소 기본권"입니다. 공유 라이브러리 mmap, `/dev/null`, `/proc/self/...` 등 *어떤 프로세스라도 동작하려면 필요한* 접근들이 묶여 있습니다.

기타 자주 쓰이는 abstraction:

| Abstraction | 용도 |
|---|---|
| `abstractions/base` | 모든 바이너리의 최소 동작권 (필수) |
| `abstractions/nameservice` | DNS·NSS 조회 (`/etc/resolv.conf` 등) |
| `abstractions/ssl_certs` | TLS 인증서 읽기 |
| `abstractions/user-tmp` | 사용자 임시 파일 |
| `abstractions/X` | X 윈도우 클라이언트 |
| `abstractions/dbus-session` | 사용자 D-Bus 접근 |
| `abstractions/audio` | PulseAudio/ALSA |

**(c) program-chunks** - 프로그램 단위 공통 규칙 모음

특정 패밀리 프로그램들이 공유하는 규칙(예: `program-chunks/postfix-common`).

### 5.4 헤더와 플래그

```apparmor
profile myname /usr/bin/foo flags=(...) {
    ...
}
```

- 첫 토큰이 경로면 그것이 곧 프로파일 이름이 됩니다(예: `/usr/bin/foo {`).
- 경로 앞에 별칭을 두려면 `profile <alias> <path>` 형태.
- `flags=( ... )` 안에 `complain`, `audit`, `attach_disconnected`, `mediate_deleted`, `default_allow` 등을 콤마로 나열.

### 5.5 파일 규칙

가장 자주 사용되는 규칙입니다. **`<경로> <퍼미션문자>,`** 형식.

```apparmor
/etc/foo.conf       r,
/var/log/foo.log    w,
/var/log/foo.log    a,            # append-only
/usr/bin/foo        mrix,         # m: mmap, r: read, ix: inherit-exec
/run/foo/socket     rw,
owner /home/*/.foo/** rw,         # owner: 실효 UID == 파일 소유자일 때만
deny  /etc/shadow   rwklx,        # 명시적 거부 (다른 규칙보다 우선)
```

주요 퍼미션 문자:

| 문자 | 의미 |
|---|---|
| `r` | read |
| `w` | write |
| `a` | append (write에 포함되지만 별도 명시 가능) |
| `m` | mmap PROT_EXEC |
| `k` | file lock |
| `l` | hard link |
| `x` | execute (반드시 전이 모드 동반) |
| `ix` | execute & inherit (현재 프로파일 유지) |
| `Px` | execute & 다른 프로파일로 transition (해당 프로파일 필요) |
| `Cx` | execute & 자식 프로파일(child profile)로 transition |
| `Ux` | execute unconfined (위험, 가급적 회피) |

경로 와일드카드:

- `*` : 슬래시 제외 임의 문자열
- `**` : 슬래시 포함 임의 문자열(서브트리 전체)
- `?` : 한 문자
- `[abc]` : 문자 집합

### 5.6 Capability 규칙

POSIX.1e capability 단위 제어. `capabilities(7)` 매뉴얼 페이지의 `CAP_*` 이름을 소문자로 사용.

```apparmor
capability net_bind_service,    # 1024 미만 포트 bind
capability sys_admin,
capability,                     # 인자 없으면 모든 capability 허용 (지양)
```

DAC상 root 프로세스라도 이 규칙에 명시되지 않은 capability는 사용할 수 없게 됩니다. **권한 분리(privilege separation)** 의 핵심 도구입니다.

### 5.7 네트워크 규칙

```apparmor
network,                                # 모든 네트워크 허용
network inet stream,                    # IPv4 TCP
network inet6 dgram,                    # IPv6 UDP
network unix stream,                    # Unix 도메인 소켓
network netlink raw,                    # netlink

# AppArmor 4.0+ : ip/port 세분화
network inet tcp peer=(ip=127.0.0.1 port=5432),
```

### 5.8 Mount 규칙

마운트 행위 자체를 제어합니다. 컨테이너·sandbox 프로파일에서 중요.

```apparmor
mount fstype=tmpfs -> /tmp/sandbox/,
remount options=(ro, bind) /var/lib/data/,
umount /mnt/cdrom,
```

### 5.9 Signal 규칙

```apparmor
signal (send) set=(term, kill) peer=/usr/bin/myhelper,
signal (receive) peer=unconfined,
```

송신 측 프로파일과 수신 측 프로파일 양쪽 모두에 일치하는 권한이 있어야 시그널 전달이 성립합니다.

### 5.10 D-Bus 규칙

```apparmor
dbus (send) bus=system path=/org/freedesktop/login1 interface=org.freedesktop.login1.Manager,
```

### 5.11 Userns 규칙 (Ubuntu 24.04 핵심)

```apparmor
userns,
```

unprivileged user namespace 생성 권한을 명시적으로 부여합니다. Ubuntu 24.04는 기본적으로 unconfined 프로세스의 unprivileged user namespace 생성을 제한하므로(7.3절), Docker rootless·Firefox sandbox·일부 빌드 도구는 프로파일에 이 규칙을 추가해야 합니다.

### 5.12 ptrace, mqueue, io_uring 등

표현력의 일부 예시:

```apparmor
ptrace (read, trace) peer=/usr/bin/strace,
mqueue (open, write) type=posix label=/usr/sbin/foo,
io_uring (sqpoll, override_creds),
unix (connect) type=stream peer=(addr="@/tmp/sock"),
```

---

## 6. 기초 명령어와 운영 흐름

### 6.1 패키지와 서비스 확인

```bash
# 패키지 설치 상태
dpkg -l | grep -E '^ii  apparmor'
# apparmor                     4.0.1-0ubuntu0.24.04.x  공통 라이브러리·서비스
# apparmor-profiles            4.0.1-0ubuntu0.24.04.x  추가 표본 프로파일(extra)
# apparmor-utils               4.0.1-0ubuntu0.24.04.x  CLI 도구 모음

# 서비스 상태 (24.04에서는 커널 드라이버 자체는 항상 활성, 유닛은 적재기 역할)
systemctl status apparmor.service
```

> **24.04 변화**: AppArmor 모듈은 커널에 빌트인되어 있으며 `apparmor.service`는 부팅 시 프로파일을 일괄 적재하는 oneshot에 가깝습니다. 서비스를 stop해도 이미 적재된 프로파일은 그대로 적용됩니다.

### 6.2 `aa-status` - 한눈에 보는 현황

```bash
sudo aa-status
# apparmor module is loaded.
# 86 profiles are loaded.
# 80 profiles are in enforce mode.
# 6  profiles are in complain mode.
# 12 processes have profiles defined.
# 12 processes are in enforce mode.
#    /usr/sbin/libvirtd (1234)
#    /usr/sbin/cupsd (4567)
#    ...
```

- "loaded": 커널에 적재된 정책 개수
- "enforce/complain": 모드별 분포
- "processes ... defined": 현재 실행 중이며 프로파일이 부착된 프로세스 수
- "processes ... unconfined but ... profiles defined": 프로파일은 있으나 부착되지 않음(잠재적 문제)

### 6.3 모드 전환 명령

```bash
# 프로파일 한 개를 complain 모드로 (학습)
sudo aa-complain /etc/apparmor.d/usr.sbin.libvirtd

# enforce로 복귀
sudo aa-enforce /etc/apparmor.d/usr.sbin.libvirtd

# 비활성화 (영구)
sudo aa-disable /etc/apparmor.d/usr.sbin.libvirtd
# 결과: /etc/apparmor.d/disable/usr.sbin.libvirtd 심링크 생성

# 디렉터리 단위 일괄 적용도 가능
sudo aa-complain /etc/apparmor.d/
```

### 6.4 새 프로파일 생성 - `aa-genprof` / `aa-autodep` / `aa-logprof`

```bash
# 1) 신규 프로파일 골격 자동 생성 + complain 모드로 적재
sudo aa-genprof /usr/local/bin/myapp

# 2) (다른 터미널에서) 애플리케이션 정상 시나리오 한번 돌리기
/usr/local/bin/myapp ...

# 3) aa-genprof가 logprof를 호출 → 로그 기반으로 규칙을 한 줄씩 묻고 답하며 추가
#    Allow / Deny / Glob / Inherit / Profile / Child / Name / etc.

# 이미 작성된 프로파일에 대해 추가 학습만 하려면
sudo aa-logprof
```

`aa-autodep`는 의존성을 분석해 비어있는 골격을 만들어 주고, `aa-genprof`는 그것을 complain 모드로 적재한 뒤 인터랙티브 갱신을 돕는 도구입니다.

### 6.5 보조 명령

```bash
# 프로파일이 있어야 마땅한데 unconfined로 도는 프로세스 찾기
sudo aa-unconfined --paranoid

# 두 프로파일 합치기
sudo aa-mergeprof <profile1> <profile2>

# 프로파일을 직접 적재/교체/언로드 (아래 6.6 참조)
sudo apparmor_parser -r /etc/apparmor.d/usr.sbin.libvirtd
```

### 6.6 `apparmor_parser` 직접 사용

`aa-*` 도구들은 결국 내부적으로 이 파서를 호출합니다. 디버깅·자동화 시 직접 다룰 일이 많습니다.

```bash
# 현재 정책 일괄 새로 적재 (서비스 재시작 없이)
sudo apparmor_parser -r /etc/apparmor.d/                       # replace

# 특정 프로파일 추가
sudo apparmor_parser -a /etc/apparmor.d/usr.local.bin.myapp    # add

# 제거(언로드)
sudo apparmor_parser -R /etc/apparmor.d/usr.local.bin.myapp    # remove

# 컴파일 결과를 커널에 올리지 않고 검증만 (CI에 유용)
sudo apparmor_parser -QT /etc/apparmor.d/usr.local.bin.myapp

# 어떤 규칙이 현재 커널에서 enforce되지 않거나 다운그레이드되는지 경고
sudo apparmor_parser --warn=rules-not-enforced --warn=rule-downgraded /etc/apparmor.d/...

# 디버그 (커널 적재 없이 컴파일 과정만 출력)
sudo apparmor_parser --skip-kernel-load --debug /etc/apparmor.d/...

# 전처리 결과(includes 펼친 텍스트)만 보기
sudo apparmor_parser --preprocess /etc/apparmor.d/...
```

---

## 7. Ubuntu 24.04(Noble Numbat)에서의 주요 변화

### 7.1 AppArmor 4.0 탑재

Ubuntu 24.04는 AppArmor 4.0을 기본 채택합니다(릴리스 시점 기준 `4.0.1-0ubuntu0.24.04.x`). 4.0의 주요 변화:

- **ABI 4.0**: 새 키워드(`userns`, 더 정밀한 `mqueue`/`io_uring`/`unix` 등) 도입을 위해 ABI 버전 업.
- **새 정책 매처(matcher)**: 로딩 속도·메모리 사용량 개선.
- **`unconfined`/`default_allow` 플래그 확장**: 기본 허용 정책에서도 특정 권한만 추가 부여 가능.
- **세분화된 네트워크 규칙**: `ip`, `port`, `peer` 조건자 정식 지원.

### 7.2 커널 통합

24.04부터 AppArmor 사용자 공간 도구가 *커널에 내장된* 정책 인터페이스에 맞춰 출시됩니다. 설명상으로는 *"AppArmor services are baked into the Ubuntu Kernel"* 이라 표현되며, 실무적으로는 다음을 의미합니다.

- 커널 모듈 분리 패키지(`linux-modules-...`)가 따로 없으며 `apparmor` LSM은 항상 빌트인.
- 기능 셋(features)은 `/sys/kernel/security/apparmor/features/`에서 조회.
- 사용자 공간 도구는 그 features 트리를 보고 자신이 만들 수 있는 정책 ABI를 결정.

### 7.3 비특권 사용자 네임스페이스 제한 - `apparmor_restrict_unprivileged_userns`

가장 임팩트가 큰 변화입니다. 23.10에서 도입되어 24.04 LTS에서 **기본 활성화**되었습니다.

배경: unprivileged user namespace는 컨테이너·sandbox의 핵심이지만, 동시에 커널 취약점의 주요 진입로였습니다. 그래서 24.04는 다음 정책을 기본 활성화합니다.

> Unprivileged 프로세스가 user namespace를 만들려면 (a) `CAP_SYS_ADMIN`을 가지고 있거나, (b) `userns,` 규칙이 명시된 AppArmor 프로파일에 confine되어 있어야 한다.

확인:

```bash
sysctl kernel.apparmor_restrict_unprivileged_userns
# kernel.apparmor_restrict_unprivileged_userns = 1
```

영향을 받는 대표 사례: Docker rootless, Firefox/Chromium content sandbox, bubblewrap, 일부 빌드 도구. 호환성 처리 방식은 다음 셋 중 하나입니다.

1. **(권장) 해당 앱의 프로파일에 `userns,` 추가** - 가장 안전.
2. 프로파일을 `unconfined flags=(default_allow) { userns, }` 형태로 임시 작성 - 호환성 응급조치.
3. **제한 자체 끄기** - `echo 0 > /proc/sys/kernel/apparmor_restrict_unprivileged_userns`. 보안상 권장되지 않음.

### 7.4 사이트 정책 패턴 - `/etc/apparmor.d/local/`

사이트별 커스터마이징을 본 프로파일 옆에 두지 않고 `local/` 안에 격리하는 관례가 정착되었습니다. 패키지 업그레이드 시 본 프로파일이 덮어써져도 사이트 규칙은 보존됩니다. 본 프로파일 안에 다음과 같이 include만 두고 실제 규칙은 local에 두는 방식이 전형적입니다.

```apparmor
/usr/sbin/libvirtd {
    ...
    include if exists <local/usr.sbin.libvirtd>
}
```

---

## 8. 디버깅과 트러블슈팅

AppArmor 운영의 8할은 **로그 읽기**입니다.

### 8.1 거부 메시지 형식

```
audit: type=1400 audit(1714287612.345:42):
  apparmor="DENIED" operation="open" profile="/usr/sbin/libvirtd"
  name="/var/lib/foo/bar" pid=1234 comm="libvirtd"
  requested_mask="r" denied_mask="r" fsuid=0 ouid=0
```

각 필드의 의미:

| 필드 | 설명 |
|---|---|
| `apparmor` | DENIED / ALLOWED / AUDIT / STATUS |
| `operation` | open, exec, mknod, ptrace, signal, mount … |
| `profile` | 위반을 일으킨 프로세스가 부착된 프로파일 이름 |
| `name` | 접근하려 한 객체(파일 경로, 시그널 이름, 소켓 등) |
| `requested_mask` / `denied_mask` | 요청된 퍼미션 / 거부된 퍼미션 |
| `comm`, `pid` | 프로세스 정보 |
| `fsuid`, `ouid` | 실효 UID / 객체 소유자 UID |

### 8.2 로그 위치

- `dmesg` (커널 링 버퍼): `sudo dmesg | grep apparmor`
- `journalctl`: `sudo journalctl -k | grep apparmor`
- syslog: `/var/log/syslog`, `/var/log/kern.log`
- auditd 설치 시: `/var/log/audit/audit.log`, `sudo ausearch -m AVC,USER_AVC -ts recent`

### 8.3 일반적 디버깅 절차

1. 증상이 발생한 시점 직후 `dmesg -T | grep -i apparmor=DENIED | tail` 로 거부 메시지 확보
2. `profile=`, `operation=`, `name=`, `requested_mask=` 필드를 식별
3. 해당 프로파일을 `aa-complain`으로 학습 모드 전환
4. 시나리오 재현, `aa-logprof`로 로그를 정책에 반영
5. 충분 기간 검증 후 `aa-enforce`로 복귀

### 8.4 흔한 함정

- **경로가 다른 것처럼 보이는 경우**: 바인드 마운트/심링크/오버레이 파일시스템에서 AppArmor가 보는 경로는 namespace의 *최상위 경로*입니다. `attach_disconnected` 플래그가 필요한 사례가 많습니다.
- **chroot/컨테이너 안 프로세스**: 프로파일 매칭은 호스트 관점의 `execve` 시점에 결정됩니다. 컨테이너 런타임이 자체 프로파일을 부여(`docker-default`)하므로 호스트 프로파일과 충돌하지 않게 설계 필요.
- **silently ignored rules**: 커널이 해당 규칙을 모르는 경우 기본적으로 *조용히 무시*됩니다. CI에서 `--warn=rules-not-enforced --warn=rule-downgraded`로 잡아내야 합니다.
- **`abstractions/base` 누락**: 거의 모든 프로세스가 필요로 하므로 잊지 말 것. 누락 시 동적 라이브러리 mmap 거부로 시작도 못 하는 증상이 흔함.
- **잠재적 회피**: 경로 기반이므로 하드 링크·바인드 마운트로 동일 inode를 다른 경로로 노출하면 정책이 적용되지 않습니다. 따라서 `mount` 규칙으로 마운트 자체를 통제하는 설계가 중요합니다.

---

## 9. OpenStack 하이퍼바이저 맥락 - libvirt sVirt와의 연결

여기서부터는 본 시리즈의 최종 목적인 **하이퍼바이저 격리**의 그림을 미리 잡습니다. 상세 설계와 적용 절차는 후속 편에서 다룹니다.

### 9.1 sVirt-AppArmor 개요

> *"The libvirt AppArmor driver uses the sVirt framework within libvirt, which is used to confine QEMU (and KVM) virtual machines and as of libvirt 1.2.3, libvirt-lxc containers."* — Ubuntu Wiki, *LibvirtApparmor*

Ubuntu에서 libvirtd는 다음 두 종류의 프로파일을 활용합니다.

1. **정적 프로파일 - `/usr/sbin/libvirtd`**
   - 패키지가 설치한 고정 프로파일.
   - libvirtd 데몬 자체의 권한을 정의(QEMU 실행, AppArmor 정책 조작 권한 등을 *조심스럽게* 허용).
2. **동적 프로파일 - `libvirt-<UUID>`**
   - libvirtd가 게스트를 시작할 때 게스트 UUID를 이름으로 한 프로파일을 **그때그때 생성**하여 QEMU 프로세스에 부착.
   - 디스크 이미지·UEFI 펌웨어·vTPM 소켓·hugepage 파일 등 *해당 게스트가 실제로 쓰는 자원만* 허용.
   - 게스트가 종료되면 해당 프로파일은 언로드.

### 9.2 `virt-aa-helper` - 동적 프로파일 생성기

이 동적 프로파일을 만드는 주체가 `virt-aa-helper`입니다. 동작 시퀀스는 다음과 같습니다.

```
[게스트 정의 도착]
    │
    ▼
libvirtd ──► virt-aa-helper 실행
                │
                ├ /etc/apparmor.d/libvirt/TEMPLATE 로드
                ├ 게스트 XML에서 디스크/네트워크/PCI 자원 추출
                ├ /etc/apparmor.d/libvirt/libvirt-<UUID> 작성
                ├ apparmor_parser -r 로 적재
                ▼
QEMU 프로세스 fork ─► execve 시점에 프로파일 부착(confine)
```

`virt-aa-helper` 자신도 자체 AppArmor 프로파일(`/usr/lib/libvirt/virt-aa-helper`)에 의해 *제한된 권한* 으로 동작합니다. 즉, 정책 작성·로드 권한이 libvirtd 본체나 호스트 셸에 그대로 노출되지 않습니다.

### 9.3 핵심 보안 효과

- **호스트 보호**: QEMU가 탈취되어도 `/etc/`, `/var/`, 다른 게스트의 디스크에 접근할 수 없음.
- **게스트 간 격리**: 게스트 A의 QEMU 프로파일은 게스트 B의 디스크 이미지 경로를 알지 못하므로 접근 자체가 차단.
- **Capability 최소화**: QEMU는 사실 대부분의 capability가 필요 없음. 프로파일에서 `capability` 규칙을 최소로 두면 권한 상승 경로가 봉쇄됨.
- **mount/userns 봉쇄**: QEMU는 일반적으로 마운트·새 user namespace 생성 권한이 필요 없음. 이를 명시 거부하면 커널 익스플로잇 표면이 줄어듦.

### 9.4 OpenStack(Nova/Helm) 환경에서의 고려사항

- **컨테이너화된 nova-compute**: OpenStack-Helm은 nova-compute / libvirt를 컨테이너로 띄웁니다. 이때 **호스트 커널의 AppArmor가 컨테이너 안 libvirtd 프로파일도 적재** 해야 합니다. 컨테이너 이미지에 들어 있는 `/etc/apparmor.d/`는 컨테이너 격리만으로 끝나지 않으며, 호스트의 AppArmor 정책 적재 메커니즘과 명시적으로 통합되어야 합니다.
- **`apparmor_parser` 권한**: 컨테이너가 정책을 로드하려면 호스트의 securityfs에 쓸 수 있어야 하므로, libvirtd 컨테이너의 보안 프로파일 설계가 중요합니다(보통 `--privileged` + 호스트 mount 또는 명시적 capability/mount 부여).
- **이미지 프로비저닝 경로**: Nova가 게스트 디스크를 `/var/lib/nova/instances/<uuid>/disk`에 두는 경로 패턴은 `virt-aa-helper`의 TEMPLATE이 알고 있어야 동적 프로파일이 정확히 작성됩니다.
- **vhost-user, SR-IOV, vTPM 등 추가 자원**: 각각 추가 경로·소켓이 필요하므로 TEMPLATE 또는 `local/` 보강이 필요할 수 있습니다.

이 통합 설계는 후속 편에서 절차·진단·검증 시나리오와 함께 다룹니다.

---

## 10. 요약

- **AppArmor**는 리눅스 LSM 위에 구현된 **경로 기반 MAC**으로, 텍스트 프로파일을 사용자 공간에서 작성하여 커널에 적재한다.
- DAC와 함께 동작하며 둘 모두를 통과해야만 접근이 성립한다. AppArmor가 막은 것은 root도 우회할 수 없다.
- 프로파일은 `/etc/apparmor.d/`에 저장되며 `tunables`, `abstractions`, `program-chunks`로 재사용·계층화된다.
- 운영 모드는 **enforce / complain / disabled**가 핵심이며 audit, kill, default_allow 등이 보조한다.
- 신규 프로파일은 `aa-genprof` → 시나리오 재현 → `aa-logprof`로 학습한 뒤 `aa-enforce`로 전환하는 것이 표준 흐름이다.
- Ubuntu 24.04는 **AppArmor 4.0** 채택, **커널 통합**, **unprivileged user namespace 제한 기본 활성화** 의 세 변화가 가장 크다. `userns,` 규칙을 기억할 것.
- `dmesg`/`journalctl`의 `apparmor="DENIED"` 메시지를 읽을 줄 알아야 한다. `operation`, `profile`, `name`, `requested_mask`가 핵심 필드.
- libvirt **sVirt-AppArmor**는 게스트마다 동적 프로파일을 생성·부착해 VM escape 시 영향을 봉쇄한다. OpenStack-Helm 환경에서는 컨테이너화된 libvirtd와 호스트 AppArmor 통합 설계가 핵심 과제다.

### 다음 학습 단계

본 시리즈의 후속 편에서 다음 주제를 이어 갑니다.

1. **실습편**: Ubuntu 24.04 단일 호스트에서 임의의 데몬에 직접 프로파일을 작성·테스트(complain → enforce 전환 사이클 체득).
2. **libvirt sVirt 적용편**: 베어메탈 KVM 호스트에서 sVirt-AppArmor를 활성화하고 동작 검증.
3. **OpenStack-Helm 통합편**: 컨테이너화된 nova-compute/libvirtd에서의 호스트 AppArmor 연동, 정책 배포·검증 파이프라인.
4. **검증·감사편**: `aa-status`, audit 로그, `apparmor_parser --warn`, `aa-unconfined` 등을 활용한 운영 점검 자동화.

---

## 부록 A. 자주 쓰는 한 줄 명령 모음

```bash
# 현황
sudo aa-status
sudo cat /sys/kernel/security/apparmor/profiles
sudo aa-unconfined --paranoid

# 모드 전환
sudo aa-complain /etc/apparmor.d/<profile>
sudo aa-enforce  /etc/apparmor.d/<profile>
sudo aa-disable  /etc/apparmor.d/<profile>

# 정책 적재/교체/제거 (서비스 재시작 불필요)
sudo apparmor_parser -a /etc/apparmor.d/<profile>     # add
sudo apparmor_parser -r /etc/apparmor.d/<profile>     # replace
sudo apparmor_parser -R /etc/apparmor.d/<profile>     # remove

# 검증/디버그
sudo apparmor_parser -QT /etc/apparmor.d/<profile>
sudo apparmor_parser --warn=rules-not-enforced --warn=rule-downgraded /etc/apparmor.d/<profile>
sudo apparmor_parser --skip-kernel-load --debug /etc/apparmor.d/<profile>
sudo apparmor_parser --preprocess /etc/apparmor.d/<profile>

# 로그
sudo dmesg | grep -i 'apparmor='
sudo journalctl -k -g apparmor
sudo ausearch -m AVC,USER_AVC -ts recent      # auditd 설치 시

# 신규 프로파일 생성
sudo aa-genprof /usr/local/bin/myapp
sudo aa-logprof

# Ubuntu 24.04 userns 제한 임시 해제 (보안상 권장 안 함)
echo 0 | sudo tee /proc/sys/kernel/apparmor_restrict_unprivileged_userns
```

## 부록 B. 자주 쓰는 파일 시스템 경로

```
/etc/apparmor.d/                    활성 프로파일 (부팅 시 자동 적재)
/etc/apparmor.d/abstractions/       재사용 가능한 공통 규칙 묶음
/etc/apparmor.d/tunables/           전역 변수(@{HOME} 등)
/etc/apparmor.d/local/              사이트별 커스터마이즈(업그레이드 보존)
/etc/apparmor.d/disable/            비활성 프로파일 심볼릭 링크
/etc/apparmor.d/libvirt/            libvirt 동적 프로파일 + TEMPLATE
/usr/share/apparmor/extra-profiles/ apparmor-profiles 패키지 표본
/sys/kernel/security/apparmor/      커널 인터페이스(securityfs)
   ├ profiles, .load, .replace, .remove
   └ features/                      현재 커널이 지원하는 정책 ABI
/var/log/syslog, /var/log/kern.log  로그
/var/log/audit/audit.log            auditd 설치 시
```

## 부록 C. 학습 점검 질문

1. DAC와 MAC를 한 문장으로 구분해 설명하라.
2. AppArmor와 SELinux가 객체를 식별하는 방식을 비교하라.
3. complain 모드와 enforce 모드의 차이는 무엇이며, 운영상 어떤 순서로 사용하는가?
4. `aa-genprof`와 `aa-logprof`의 역할 차이를 설명하라.
5. `apparmor="DENIED"` 메시지에서 즉시 확인해야 할 4개 필드는?
6. Ubuntu 24.04에서 unprivileged user namespace가 제한되는 이유와, 이를 정상화하는 권장 방법은?
7. libvirt가 게스트별로 동적 AppArmor 프로파일을 만드는 이유와 그 흐름을 설명하라.
8. 경로 기반 정책의 한계와 그것을 보완하기 위한 AppArmor의 메커니즘은?

---

## 참고 출처

- [AppArmor — Ubuntu Security Documentation](https://documentation.ubuntu.com/security/security-features/privilege-restriction/apparmor/)
- [AppArmor — Ubuntu Server Documentation](https://documentation.ubuntu.com/server/how-to/security/apparmor/)
- [AppArmor — The Linux Kernel Documentation](https://docs.kernel.org/admin-guide/LSM/apparmor.html)
- [Linux Security Module Usage — Kernel Documentation](https://docs.kernel.org/admin-guide/LSM/index.html)
- [Ubuntu Manpage: `apparmor.d(5)`](https://manpages.ubuntu.com/manpages/noble/man5/apparmor.d.5.html)
- [Ubuntu Manpage: `aa-genprof(8)`](https://manpages.ubuntu.com/manpages/noble/man8/aa-genprof.8.html)
- [Ubuntu Manpage: `apparmor_parser(8)`](https://manpages.ubuntu.com/manpages/noble/man8/apparmor_parser.8.html)
- [Ubuntu Wiki: AppArmor](https://wiki.ubuntu.com/AppArmor)
- [Ubuntu Wiki: LibvirtApparmor](https://wiki.ubuntu.com/LibvirtApparmor)
- [AppArmor 4.0.2 release notes](https://apparmor.net/news/release-4.0.2/)
- [AppArmor (upstream wiki) — Libvirt](https://gitlab.com/apparmor/apparmor/-/wikis/Libvirt)
- [Understanding AppArmor User Namespace Restriction — Ubuntu Discourse](https://discourse.ubuntu.com/t/understanding-apparmor-user-namespace-restriction/58007)
- [Restricted unprivileged user namespaces are coming to Ubuntu — Ubuntu Blog](https://ubuntu.com/blog/ubuntu-23-10-restricted-unprivileged-user-namespaces)
- [Ubuntu 24.04 LTS release notes](https://documentation.ubuntu.com/release-notes/24.04/)
