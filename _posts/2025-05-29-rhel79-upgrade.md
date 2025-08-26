---
title: "RHEL 7.4에서 7.9로 업그레이드 시 데이터베이스 및 고가용성 시스템에 미치는 영향 검토"
date: 2025-05-29
tags: [rhel, linux, upgrade, ha, database]
categories: [Howtos, Upgrade]
---


## 개요
RHEL 7.4에서 7.9로의 업그레이드가 필요하다는 요구사항이 있으며, Extended Life Cycle Support(ELS)를 유지하기 위한 필수 조치입니다. 이에 따라 데이터베이스(PostgreSQL)와 고가용성 구성(Pacemaker 및 DRBD)이 포함된 시스템에 부정적인 영향을 미치지 않도록 신중한 검토와 준비가 필요합니다. 아래에서는 업그레이드의 영향을 평가하고, 우려 사항에 대한 통찰 및 권장 사항을 제공합니다.

---

## 시스템 세부 정보 및 평가

### 1. PostgreSQL 데이터베이스
- **현재 버전:** PostgreSQL 13.20-1PGDG.rhel7
- **평가:**
  - PostgreSQL 13.20은 RHEL 7의 마이너 버전 업데이트(7.4 → 7.9)와 일반적으로 호환됩니다. RHEL 7.9의 커널 버전(3.10.0-1160.119.1.el7) 및 주요 라이브러리 업데이트는 PostgreSQL의 동작에 직접적인 영향을 미치지 않을 것으로 보입니다.
  - `yum --assumeno update` 출력에서 PostgreSQL 관련 패키지는 업데이트 대상으로 표시되지 않았으며, 이는 기존 설치된 버전이 유지됨을 의미합니다.
- **우려 사항:**
  - 커널 또는 의존성 라이브러리 업데이트로 인해 데이터베이스 연결성이나 성능에 미세한 변화가 발생할 가능성.
  - 복제(DRBD 기반) 설정에서 데이터 무결성 유지.
- **권장 사항:**
  1. **업그레이드 전 백업:** 데이터베이스의 전체 백업을 수행하여 데이터 손실 위험을 최소화합니다.
     ```bash
     pg_dumpall > pg_backup.sql
     ```
  2. **업그레이드 후 점검:** PostgreSQL 서비스 재시작 후 데이터베이스 연결 및 복제 상태를 확인합니다.
     ```bash
     systemctl restart postgresql-13
     psql -U postgres -c "SELECT pg_is_in_recovery();"
     ```
  3. **무결성 확인:** 데이터베이스 무결성을 검증하여 예상치 못한 오류를 사전에 탐지합니다.
     ```bash
     pg_checksums -c
     ```

### 2. 고가용성 구성 (Pacemaker 및 DRBD)
- **Pacemaker:**
  - **현재 버전:** 1.1.18-11.el7_5.2
  - **평가:**
    - RHEL 7.9에서 Pacemaker 1.1.18은 공식적으로 지원되며, 마이너 업데이트로 인한 주요 호환성 문제는 보고되지 않았습니다.
    - `yum --assumeno update` 출력에서 Pacemaker 패키지는 업데이트 대상이 아니므로 현재 버전이 유지됩니다.
  - **우려 사항:**
    - 설정 파일(`cib.xml`) 또는 리소스 정의의 미세한 변경 가능성.
    - 커널 업데이트로 인한 클러스터 동작 이상.
  - **권장 사항:**
    1. **사전 점검:** 업그레이드 전 클러스터 상태를 확인합니다.
       ```bash
       pcs status
       ```
    2. **업그레이드 후 점검:** Pacemaker 서비스 재시작 후 클러스터 및 리소스 상태를 모니터링합니다.
       ```bash
       systemctl restart pacemaker
       pcs status
       ```
    3. **설정 검토:** 설정 파일을 백업하고 업그레이드 후 변경 사항을 확인합니다.
       ```bash
       pcs config backup
       ```

- **DRBD:**
  - **현재 버전:** 9.0.22-3.el7_9.elrepo (kmod-drbd90)
  - **평가:**
    - DRBD는 커널 모듈을 사용하므로, RHEL 7.9의 커널 업데이트(3.10.0-1160.119.1.el7)에 따라 호환성 확인이 필수입니다.
    - DRBD 9.0.22는 RHEL 7.9 커널과 호환되지만, 최신 DRBD 버전으로의 업데이트 여부를 검토하는 것이 좋습니다.
    - `yum --assumeno update`에서 DRBD 패키지는 업데이트 대상이 아니므로 현재 모듈이 유지됩니다.
  - **우려 사항:**
    - 커널 업데이트로 인해 DRBD 모듈 로드 실패 가능성.
    - 복제 상태 동기화 문제.
  - **권장 사항:**
    1. **호환성 확인:** 업그레이드 전 DRBD 모듈과 커널 호환성을 확인합니다.
       ```bash
       modinfo drbd | grep vermagic
       ```
    2. **상태 점검:** 업그레이드 후 DRBD 상태를 확인하고, 필요 시 모듈을 재컴파일하거나 업데이트합니다.
       ```bash
       drbdadm status
       modprobe drbd
       ```
    3. **최신 버전 고려:** DRBD 9.x의 최신 마이너 버전으로 업데이트하여 안정성을 강화합니다.
       ```bash
       yum install kmod-drbd90 --enablerepo=elrepo
       ```

---

## 알려진 문제 및 호환성 정보
- **PostgreSQL:** RHEL 7.9로의 업그레이드에서 PostgreSQL 13.20과 관련된 주요 호환성 문제는 알려지지 않았습니다. 다만, 복제 설정(DRBD)에서 동기화 오류가 발생할 가능성을 배제할 수 없으므로 사전 테스트가 필요합니다.
- **Pacemaker:** RHEL 7.9에서 Pacemaker 1.1.18은 안정적으로 동작하며, 주요 변경 사항은 없습니다. 그러나 리소스 관리 스크립트(예: `ocf:heartbeat:pgsql`)의 동작을 재확인해야 합니다.
- **DRBD:** 커널 업데이트 시 DRBD 모듈의 호환성 문제가 발생할 수 있으나, DRBD 9.0.22는 RHEL 7.9 커널과 호환성이 확인되었습니다. 최신 버전으로의 업데이트는 선택 사항입니다.

---

## 테스트 전략 및 도구
### 테스트 전략
- **가상 머신 활용:** 라이선스 제약 및 부서별 분리로 인해 프로덕션과 동일한 환경 구축이 어려운 점을 고려할 때, 가상 머신(VM)을 사용한 테스트 환경 구축을 추천합니다.
  1. 현재 시스템의 스냅샷을 생성하거나 VM에 RHEL 7.4를 설치합니다.
  2. PostgreSQL, Pacemaker, DRBD를 동일한 버전으로 설정합니다.
  3. RHEL 7.9로 업그레이드를 시뮬레이션하고 주요 기능(데이터베이스 연결, 복제, 페일오버)을 테스트합니다.
- **롤백 계획:** 업그레이드 실패 시 복구를 위해 시스템 백업 및 롤백 절차를 준비합니다.
  ```bash
  tar -cvf /backup/system_backup.tar /etc /var/lib/pgsql /var/lib/pacemaker
  ```

### 도구
- **`yum --assumeno update`:** 업데이트 예정 패키지 및 의존성을 사전에 점검합니다.
- **`systemd-analyze`:** 업그레이드 후 부팅 시간 및 시스템 성능을 분석합니다.
  ```bash
  systemd-analyze blame
  ```
- **`pcs status` 및 `drbdadm status`:** 고가용성 구성과 복제 상태를 모니터링합니다.
- **`pg_stat_activity`:** PostgreSQL의 활성 연결 상태를 확인합니다.
  ```sql
  SELECT * FROM pg_stat_activity;
  ```

---

## 결론 및 권장 조치
RHEL 7.4에서 7.9로의 업그레이드는 PostgreSQL, Pacemaker, DRBD로 구성된 시스템에 큰 영향을 미치지 않을 것으로 예상됩니다. 그러나 다음과 같은 조치를 통해 위험을 최소화할 수 있습니다:
1. **사전 준비:**
   - 데이터베이스와 설정 파일 백업.
   - DRBD와 커널 호환성 확인.
2. **업그레이드 후 검증:**
   - 데이터베이스 연결 및 복제 상태 점검.
   - Pacemaker 클러스터와 리소스 상태 확인.
3. **테스트:** VM 기반 시뮬레이션을 통해 잠재적 문제를 사전에 식별.

위 절차를 준수한다면, 업그레이드로 인한 비호환성 또는 비정상 동작 위험을 효과적으로 관리할 수 있을 것입니다. 추가적인 지원이 필요하면 RHEL 지원팀 또는 DRBD 커뮤니티를 통해 최신 정보를 확인하는 것도 추천합니다.
