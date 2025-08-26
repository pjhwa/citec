---
title: "Private DNS 내에 테스트용 DNS 레코드를 설정하고 이를 주기적으로 쿼리하는 방식"
date: 2025-04-25
tags: [dns, test, query, cloud, linux, windows]
categories: [Howtos, DNS]
---

클라우드 플랫폼에서 OS와 DNS 간의 연결 상태를 모니터링하기 위해, "**Private DNS 내에 테스트용 DNS 레코드를 설정하고 이를 주기적으로 쿼리하는 방식**"에 대해 자세히 설명드리겠습니다.

--- 

## 1. 테스트용 DNS 레코드의 개념
이 방법의 핵심은 Private DNS에 **테스트용 DNS 레코드**를 만드는 것입니다. 예를 들어, `test.internal.xxx`라는 도메인 이름을 만들고 이를 특정 IP 주소(예: `192.168.1.100`)로 해석하도록 설정합니다. OS에서 이 레코드를 주기적으로 쿼리하면:

- **정상 응답** (예: `192.168.1.100` 반환): OS와 DNS 간 연결이 정상이고, DNS 서비스도 제대로 작동 중임을 확인.
- **비정상 응답** (쿼리 실패 또는 잘못된 IP 반환): 네트워크 연결 문제나 DNS 서비스 오류를 감지.

이 방식은 단순히 포트가 열려 있는지 확인하는 것보다 실제 DNS 해석 과정을 점검하므로 더 정확합니다.

---

## 3. 설정 및 구현 방법
이제 이 방법을 클라우드 플랫폼 환경에 적용하는 구체적인 단계를 설명하겠습니다.

### 3.1. Private DNS에 테스트용 레코드 생성
먼저, Private DNS에 테스트용 A 레코드를 추가합니다. 클라우드 플랫폼에서 DNS 관리를 웹 콘솔이나 CLI로 제공한다고 가정하겠습니다.

#### **클라우드 플랫폼 웹 콘솔 사용**
1. 클라우드 플랫폼 관리 콘솔에 로그인합니다.
2. DNS 관리 섹션으로 이동하여 Private DNS 존(예: `internal.xxx`)을 선택합니다.
3. 새 레코드를 추가합니다:
   - **이름**: `test`
   - **유형**: `A`
   - **값**: `192.168.1.100` (테스트용 IP, 실제 환경에 맞게 설정)
4. 변경 사항을 저장합니다.

---

### 3.2. OS에서 주기적 쿼리 설정
테스트 레코드가 생성되었으면, OS에서 이를 주기적으로 쿼리하도록 설정합니다. 이를 위해 `dig`(Linux) 또는 `nslookup`(Windows) 같은 도구를 사용합니다.

#### **Linux 환경**
1. **수동 쿼리 테스트**
   DNS 서버 IP가 `10.0.0.1`이라고 가정하고, 다음 명령어로 확인:
   
```
dig @10.0.0.1 test.internal.xxx A
```
   
   - 출력 예시:
     
```
;; ANSWER SECTION:
test.internal.xxx. 3600 IN A 192.168.1.100
```
     
   - `192.168.1.100`이 반환되면 정상.

2. **자동화 스크립트 작성**
   `/usr/local/bin/dns_check.sh` 파일을 만들어 아래 내용을 입력:
   
```
#!/bin/bash
DNS_SERVER="10.0.0.1"  # Private DNS 서버 IP
TEST_DOMAIN="test.internal.xxx"
EXPECTED_IP="192.168.1.100"
   
RESPONSE=$(dig @$DNS_SERVER $TEST_DOMAIN A +short)
  
if [ "$RESPONSE" == "$EXPECTED_IP" ]; then
    echo "$(date): DNS 정상 작동"
else
    echo "$(date): DNS 오류 감지: $RESPONSE"
    # 여기에 알림 추가 (예: 이메일, 모니터링 시스템 호출)
fi
```

3. **실행 권한 부여**
   
```
chmod +x /usr/local/bin/dns_check.sh
```

4. **Cron으로 주기적 실행**
   5분마다 실행하도록 설정:
   
```
crontab -e
```
   
   다음 줄 추가:
   
```
*/5 * * * * /usr/local/bin/dns_check.sh >> /var/log/dns_check.log 2>&1
```

#### **Windows 환경**
1. **수동 쿼리 테스트**

```
nslookup test.internal.xxx 10.0.0.1
```

   - 출력 예시:
     
```
Server:  10.0.0.1
Address:  10.0.0.1#53
Name:    test.internal.xxx
Address:  192.168.1.100
```

2. **자동화 스크립트 작성**
   `dns_check.bat` 파일을 만들어 아래 내용을 입력:
   
```
@echo off
set DNS_SERVER=10.0.0.1
set TEST_DOMAIN=test.internal.xxx
set EXPECTED_IP=192.168.1.100
   
for /f "tokens=*" %%a in ('nslookup %TEST_DOMAIN% %DNS_SERVER% ^| findstr /c:"Address:"') do set RESPONSE=%%a
set RESPONSE=%RESPONSE:Address: =%
   
if "%RESPONSE%"=="%EXPECTED_IP%" (
    echo %date% %time%: DNS 정상 작동 >> C:\dns_check.log
) else (
    echo %date% %time%: DNS 오류 감지: %RESPONSE% >> C:\dns_check.log
    :: 여기에 알림 추가
)
```

4. **작업 스케줄러로 주기적 실행**
   - Windows "작업 스케줄러"를 열고 새 작업을 생성.
   - **트리거**: 5분마다 실행.
   - **작업**: `C:\dns_check.bat` 실행.

---

## 4. 모니터링 시스템과의 통합
- **로그 확인**: 주기적 쿼리 결과를 로그 파일에 기록하여 모니터링 시스템(예: Prometheus, ELK)이 이를 수집하도록 설정.
- **알림 추가**: 쿼리 실패 시 이메일 또는 슬랙 알림을 트리거하도록 스크립트에 추가.
  - 예: Linux에서 `mail` 명령어로 이메일 전송:
```
echo "DNS 오류 감지" | mail -s "DNS 모니터링 경고" admin@example.com
```

---

## 5. 보안 및 성능 고려사항
- **보안**: 테스트 레코드는 Private DNS 내에 있으므로 외부 노출 위험이 없습니다. 다만, Private DNS 서버가 안전하게 설정되어 있어야 합니다.
- **성능**: 주기적 쿼리는 단순한 DNS 조회로, 서버나 네트워크에 큰 부담을 주지 않습니다. 5분 간격은 적절한 균형을 제공합니다.

---

## 6. 설정 및 테스트 단계별 가이드
### **단계 1: 테스트 레코드 생성**
- SCP 콘솔 또는 CLI로 `test.internal.xxx`를 `192.168.1.100`으로 설정.

### **단계 2: 수동 테스트**
- Linux: `dig @10.0.0.1 test.internal.xxx A`
- Windows: `nslookup test.internal.xxx 10.0.0.1`
- 예상 IP(`192.168.1.100`) 확인.

### **단계 3: 스크립트 작성 및 실행**
- 위 예시 스크립트를 작성하고 실행 권한 부여 후 테스트:
  - Linux: `/usr/local/bin/dns_check.sh`
  - Windows: `dns_check.bat`

### **단계 4: 주기적 실행 설정**
- Cron 또는 작업 스케줄러로 5분마다 실행 설정.

### **단계 5: 모니터링 검증**
- 스크립트를 실행하며 로그 확인.
- 테스트로 DNS 레코드 IP를 변경(예: `192.168.1.101`)하고 오류 감지 여부 확인.
