---
title: "Apache Syncope Query로 인한 Temp Disk Full"
date: 2025-05-20
tags: [problem, bug, mariadb, apache, syncope, query]
---

## **장애 개요 및 현상**
- **장애 내용**: MFA 서비스 SingleID DB(MariaDB 10.6.14 이중화)에 Temp Disk Full로 인해 DB Hang이 발생했습니다. 이는 MFA 요청 시 사용자 SingleID 앱 API 호출과 k8s 내 MFA 기능에서 DB 조회(사용자, 배치 프로세스 동작 등) 중 발생한 문제입니다.
- **발생 과정**:
  - MariaDB에서 대규모 정렬(Sort)이 필요한 Long-running Query 4건이 실행되었습니다.
  - 이로 인해 Temp Disk(56GB)가 가득 차면서 DB Hang이 발생했습니다.
  - 관련 스레드 정보:
    - Thread ID: 337423063, Runtime: 3046초
    - Thread ID: 337418590, Runtime: 2985초
    - Thread ID: 337425505, Runtime: 2925초
    - Thread ID: 337427163, Runtime: 2986초
- **현상 원인**:
  - 해당 Query의 조회 조건에 해당하는 컬럼에 인덱스가 없어 Full Table Scan이 발생했습니다.
  - MariaDB의 테이블 통계 정보가 자동 업데이트되면서 Query 실행 계획(Query Plan)이 변경되었습니다.

---

### **애플리케이션 담당자의 주장**
애플리케이션 담당자는 장애의 원인을 MariaDB 버그로 보고 있습니다. 주요 주장은 다음과 같습니다:
1. **Query의 출처**:
   - 문제의 Query는 Apache Syncope 오픈소스 솔루션에서 JPA 기반으로 자동 생성된 것입니다.
   - 장애 시점에 실행 계획이 악성 Plan으로 변경되기 전까지는 문제가 없던 Query였습니다.
2. **MariaDB 버그(MDEV-33813)**:
   - Temp Disk Full 시점에 DB Hang이 발생한 것은 MariaDB 10.6.16의 버그로 인해 다른 서비스 세션까지 영향을 받은 결과입니다.
   - SingleID 데이터 테이블은 InnoDB를 사용하지만, Temp Table은 별도 설정이 없으면 Aria Storage Engine을 사용합니다. 이는 버그 리포팅(MDEV-33813)과 일치합니다.
   - Temp Disk Full 후 "no space left on device" 오류로 세션이 복구되지 않은 것도 버그의 특징과 동일합니다.
3. **버그의 영향**:
   - 해당 버그가 없었다면, 이 Query는 단순 관리용 페이지의 Slow Query로 인시던트로 등록되어 개선 절차로 처리되었을 것이라고 주장합니다.
4. **버그 패치와의 연관성**:
   - MDEV-33813 패치(10.6.18 이후)는 Temp Disk Full 시 Wait 대신 Error로 처리하도록 변경되었습니다. 패치가 적용되었다면 DB Hang 없이 Temp Disk Full 상황이 해소되었을 가능성이 있다고 봅니다.

---

### **데이터베이스 지원 전문가의 주장**
데이터베이스 지원 전문가는 장애의 근본 원인을 Query 설계 문제로 보고, MariaDB 버그는 부차적 요인이라고 주장합니다:
1. **근본 원인**:
   - MariaDB 버그가 픽스되면 장애가 발생하지 않을 수 있지만, 근본 원인은 Query가 조회 조건을 주지 않아 Full Table Scan을 유발한 것입니다.
   - Full Table Scan으로 Temp Disk가 가득 차면서 장애가 발생했습니다.
2. **MDEV-33813 버그와의 차이**:
   - 버그 리포팅은 Temp Disk가 100%가 아닌데도 "no space left on device" 오류가 발생한 사례를 다룹니다.
   - 반면, SingleID 시스템은 Temp Disk가 100%로 유지된 상태에서 오류가 발생했으므로, 이는 당연한 현상입니다.
3. **테스트 환경 차이**:
   - 버그는 Aria Storage Engine에서 테스트되었으나, SingleID는 InnoDB를 사용합니다. 따라서 버그와 동일한 상황으로 보지 않습니다.

---

### **애플리케이션 담당자의 반박**
애플리케이션 담당자는 데이터베이스 지원 전문가의 주장에 대해 다음과 같이 반박합니다:
1. **테스트 환경 차이**:
   - 오픈소스 버그 리포팅은 재현 가능성을 위해 제한된 환경(Aria Storage Engine)에서 테스트됩니다.
   - 운영 환경에서는 InnoDB(데이터 저장)와 Aria(Temp Table)를 동시에 사용하므로, 테스트 환경 차이를 이유로 버그와 무관하다고 보기는 어렵습니다.
2. **버그 패치의 의미**:
   - 패치 내용은 Temp Disk Full 시 Wait 대신 Error로 처리하는 것입니다.
   - SingleID에서 Temp Disk가 100%로 유지된 것은 4개 세션이 Wait 상태에 빠진 결과이며, 이는 버그 리포팅 상황과 동일합니다.
   - 패치가 적용되었다면 Error 처리로 세션이 종료되며 Temp Disk Full 상태가 해소되었을 가능성이 있습니다.

---

### **장애등급판정위원의 의견**
- 시스템 운영 중 데이터 증가로 통계 정보가 변화하면 DB Optimizer의 Query 실행 계획도 변합니다.
- 최초 설계 시 데이터 증가를 고려했으나, 운영 중 장시간 수행으로 부하를 유발하는 Query에 대한 지속적인 관리와 개선이 필요합니다.

---

### **MariaDB 버전 간 동작 차이**
- **10.6.17 이전 (현재 버전 10.6.14)**:
  - Temp Disk Full 시 60초 간격으로 공간이 생길 때까지 Wait합니다.
  - 모든 세션이 대기 상태에 빠지며 DB Hang이 발생합니다(이번 장애와 동일).
- **10.6.18 이후**:
  - Temp Disk Full 시 해당 SQL에 Error를 발생시키고 Temp File을 삭제해 공간을 확보합니다.
  - 해당 세션만 영향을 받고 다른 세션은 정상 동작합니다.
  - 패치: MDEV-33813 (10.6.18에서 적용).

---

## **판단: 데이터베이스 지원 전문가의 입장이 옳다**
### **판단의 이유 및 근거**
아래에서 상세히 분석합니다.

#### **1. 근본 원인은 Query의 설계 문제**
- **Full Table Scan의 영향**:
  - Query에 조회 조건에 해당하는 컬럼의 인덱스가 없어 Full Table Scan이 발생했습니다.
  - 대규모 데이터 정렬이 필요해 Temp Disk(56GB)가 가득 찼고, 이는 DB Hang의 직접적인 원인이 되었습니다.
  - Temp Disk Full이 발생하지 않았다면 DB Hang도 발생하지 않았을 것입니다.
- **Query 최적화의 필요성**:
  - 장애등급판정위원의 의견처럼, 데이터 증가에 따라 실행 계획이 변할 수 있으므로 Query 성능 관리가 필수입니다.
  - 인덱스 추가나 조회 조건 최적화로 Full Table Scan을 방지할 수 있었다면 장애를 예방할 수 있었습니다.

#### **2. MariaDB 버그의 역할**
- **버그의 영향**:
  - MariaDB 10.6.14에서 Temp Disk Full 시 모든 세션이 60초 간격으로 Wait하며 DB Hang이 발생했습니다.
  - MDEV-33813 패치(10.6.18) 이후에는 Error 처리로 다른 세션에 영향을 주지 않습니다.
  - 즉, 버그는 장애를 악화시켰으나, Temp Disk Full을 유발한 근본 원인은 아닙니다.
- **버그와 장애의 관계**:
  - 데이터베이스 지원 전문가가 지적했듯, Temp Disk가 100%로 유지된 상태에서 "no space left on device" 오류가 발생한 것은 자연스러운 현상입니다.
  - 버그 리포팅(MDEV-33813)은 Temp Disk가 100%가 아닌데 오류가 발생한 경우를 다루며, SingleID 상황과는 다릅니다.
- **패치의 한계**:
  - 패치가 적용되더라도 Query가 Temp Disk를 과도하게 사용하면 유사한 문제가 재발할 수 있습니다.

#### **3. 애플리케이션 담당자의 주장에 대한 반박**
- **Query 자동 생성의 책임**:
  - Query가 Apache Syncope에서 자동 생성되었다고 하지만, 운영 환경에서는 성능을 모니터링하고 최적화할 책임이 있습니다.
  - 오픈소스 솔루션 사용은 성능 관리 의무를 면제하지 않습니다.
- **버그와의 연관성**:
  - Temp Disk Full이 버그로 인해 악화되었다고 주장하나, Full 상태를 초래한 것은 Query의 Full Table Scan입니다.
  - 패치로 DB Hang은 방지할 수 있어도, 근본적인 Temp Disk 사용 문제는 해결되지 않습니다.

#### **4. 종합적 판단**
- **Query 최적화의 중요성**:
  - Query가 Full Table Scan을 유발하지 않도록 설계되었다면 Temp Disk Full과 DB Hang이 발생하지 않았을 것입니다.
- **MariaDB 버그는 부차적 요인**:
  - 버그는 장애의 심각성을 키웠으나, 근본 원인은 Query 설계에 있습니다.
- **지속적인 관리 필요**:
  - 장애등급판정위원의 의견을 반영하면, Query 성능 개선과 지속적인 관리가 장애 예방의 핵심입니다.

---

## **결론**
데이터베이스 지원 전문가의 입장이 옳습니다. 장애의 근본 원인은 Query가 조회 조건을 주지 않아 Full Table Scan을 유발한 것이며, 이로 인해 Temp Disk Full이 발생해 장애가 시작되었습니다. MariaDB 버그(MDEV-33813)는 DB Hang을 악화시킨 요인이지만, Temp Disk Full을 방지하지 못한 Query 설계가 핵심 문제입니다. 따라서 Query에 인덱스를 추가하거나 최적화하는 등의 조치가 필요하며, 버그 패치만으로는 근본적인 해결이 어렵습니다.
