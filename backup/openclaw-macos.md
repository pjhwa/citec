# OpenClaw 설치 및 설정 가이드

> **작성일:** 2026-02-04  
> **OpenClaw 버전:** 2026.2.1  
> **대상 시스템:** Jerry's iMac (Intel i7-7700K, 48GB RAM, macOS Ventura 13.7.8)

---

## 목차

1. [시스템 요구사항](#1-시스템-요구사항)
2. [설치 과정](#2-설치-과정)
3. [기본 설정 (Onboarding)](#3-기본-설정-onboarding)
4. [Slack 채널 연동](#4-slack-채널-연동)
5. [현재 설정 상세](#5-현재-설정-상세)
6. [알려진 제한사항](#6-알려진-제한사항)
7. [자주 쓰는 명령어](#7-자주-쓰는-명령어)
8. [문제 해결](#8-문제-해결)

---

## 1. 시스템 요구사항

### 내 iMac 사양

| 항목      | 값                            |
| ------- | ---------------------------- |
| CPU     | Intel Core i7-7700K @ 4.2GHz |
| RAM     | 48GB                         |
| macOS   | Ventura 13.7.8               |
| Node.js | v24.6.0 ✅ (v22 이상 필요)        |

### 필수 소프트웨어

```bash
# Node.js 버전 확인
node -v   # v22 이상이어야 함

# npm 버전 확인
npm -v
```

> [!NOTE]
> Node.js가 없다면 [https://nodejs.org](https://nodejs.org)에서 LTS 버전을 설치하세요.

---

## 2. 설치 과정

### OpenClaw 전역 설치

```bash
npm install -g openclaw
```

### 설치 확인

```bash
openclaw --version
# 출력: 2026.2.1
```

---

## 3. 기본 설정 (Onboarding)

### 온보딩 마법사 실행

```bash
openclaw onboard
```

### 선택한 설정값

| 질문                          | 선택한 값                                  | 설명            |
| --------------------------- | -------------------------------------- | ------------- |
| Onboarding mode             | Manual                                 | 수동 설정         |
| What do you want to set up? | Local gateway                          | 이 맥에서 직접 실행   |
| Workspace directory         | `/Users/jaehwa/.openclaw/workspace`    | 기본값           |
| Model/auth provider         | Google                                 | Gemini 사용     |
| Google auth method          | **Google Antigravity OAuth**           | 브라우저 로그인 방식   |
| Default model               | `google-antigravity/gemini-3-pro-high` | 고성능 Gemini 모델 |
| Gateway port                | `18789`                                | 기본값           |
| Gateway bind                | Loopback (127.0.0.1)                   | 로컬 전용         |
| Gateway auth                | Token                                  | 토큰 인증         |
| Tailscale exposure          | Off                                    | 외부 노출 안 함     |

### 활성화된 Hooks (자동화 기능)

| Hook             | 기능                |
| ---------------- | ----------------- |
| `session-memory` | 대화 내용을 장기 기억으로 저장 |
| `boot-md`        | 시작 시 환영 메시지 표시    |
| `command-logger` | 명령어 기록 저장         |

### 설치된 Skills

| Skill             | 상태    | 기능                      |
| ----------------- | ----- | ----------------------- |
| `nano-pdf`        | ✅ 설치됨 | PDF 문서 읽기               |
| `nano-banana-pro` | ✅ 설정됨 | Gemini 연동 (API Key 등록됨) |

---

## 4. Slack 채널 연동

### 4.1 Slack 앱 생성 (api.slack.com)

1. [https://api.slack.com/apps](https://api.slack.com/apps) 접속
2. **Create New App** → **From an app manifest** 선택
3. 워크스페이스 선택 후 **Next**
4. **JSON** 탭 선택 후 아래 내용 붙여넣기:

```json
{
    "display_information": {
        "name": "OpenClaw",
        "description": "OpenClaw AI Assistant",
        "background_color": "#0f0f0f"
    },
    "features": {
        "bot_user": {
            "display_name": "OpenClaw",
            "always_online": true
        },
        "app_home": {
            "messages_tab_enabled": true,
            "messages_tab_read_only_enabled": false
        }
    },
    "oauth_config": {
        "scopes": {
            "bot": [
                "app_mentions:read",
                "channels:history",
                "chat:write",
                "files:read",
                "files:write",
                "im:history",
                "users:read"
            ]
        }
    },
    "settings": {
        "event_subscriptions": {
            "bot_events": [
                "app_mention",
                "message.im"
            ]
        },
        "interactivity": {
            "is_enabled": true
        },
        "org_deploy_enabled": false,
        "socket_mode_enabled": true
    }
}
```

5. **Next** → **Create** → **Install to Workspace**

### 4.2 토큰 발급

#### App-Level Token (xapp-...)

1. **Basic Information** → **App-Level Tokens** → **Generate Token**
2. Token Name: `openclaw`
3. Scope: `connections:write` 추가
4. **Generate** 클릭 후 `xapp-...` 토큰 복사

#### Bot User OAuth Token (xoxb-...)

1. **OAuth & Permissions** 이동
2. 상단의 `xoxb-...` 토큰 복사

### 4.3 현재 Slack 설정

| 항목        | 값                                                                                                    |
| --------- | ---------------------------------------------------------------------------------------------------- |
| 활성화       | ✅ Yes                                                                                                |
| Bot Token | `xoxb-...`                                        |
| App Token | `xapp-...` |
| 허용된 채널    | `#tomandjerry`                                                                                       |
| 그룹 정책     | `open` (모든 그룹 허용)                                                                                |

### 4.4 사용자 페어링 승인

Slack에서 처음 대화할 때 페어링 코드가 나오면:

```bash
openclaw pairing approve slack <페어링코드>
```

예시:

```bash
openclaw pairing approve slack GFQY9VGB
```

---

## 5. 현재 설정 상세

### 설정 파일 위치

```
~/.openclaw/openclaw.json
```

### 주요 설정값 요약

```json
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "google-antigravity/gemini-3-pro-high"
      },
      "workspace": "/Users/jaehwa/.openclaw/workspace",
      "maxConcurrent": 4
    }
  },
  "gateway": {
    "port": 18789,
    "mode": "local",
    "bind": "loopback",
    "auth": {
      "mode": "token",
      "token": "09f8..."
    }
  }
}
```

### 웹 UI 접속 (활성화 시)

```
http://127.0.0.1:18789/?token=09f8...
```

---

## 6. 알려진 제한사항

> [!WARNING]
> 현재 시스템(macOS Ventura + Intel CPU)의 한계로 일부 기능이 제한됩니다.

### 설치 불가능한 Skills

| Skill             | 실패 이유                     | 대안                |
| ----------------- | ------------------------- | ----------------- |
| `apple-notes`     | Command Line Tools 버전 불일치 | Xcode CLT 업데이트 필요 |
| `apple-reminders` | macOS Sonoma 이상 필요        | OS 업그레이드 또는 사용 불가 |
| `imsg` (iMessage) | macOS Sonoma 이상 필요        | OS 업그레이드 또는 사용 불가 |
| `summarize`       | Apple Silicon (ARM) 필요    | Intel Mac에서 사용 불가 |
| `gemini-cli`      | CLT 버전 불일치                | Xcode CLT 업데이트 필요 |
| `github` (gh)     | CLT 버전 불일치                | Xcode CLT 업데이트 필요 |

### Command Line Tools 업데이트 방법

```bash
# 기존 CLT 삭제
sudo rm -rf /Library/Developer/CommandLineTools

# 새로 설치
sudo xcode-select --install
```

또는 [Apple Developer](https://developer.apple.com/download/all/)에서 **Xcode 15.2용 Command Line Tools** 다운로드.

---

## 7. 자주 쓰는 명령어

### 기본 명령어

```bash
# AI와 터미널에서 대화
openclaw chat

# 온보딩 마법사 다시 실행
openclaw onboard

# 설정 변경
openclaw configure

# 도움말
openclaw help
```

### Gateway 관리

```bash
# Gateway 시작
openclaw gateway start

# Gateway 재시작
openclaw gateway restart

# Gateway 상태 확인
openclaw gateway status

# Gateway 중지
openclaw gateway stop
```

### 페어링 관리

```bash
# 페어링 승인
openclaw pairing approve slack <코드>

# 페어링 목록 보기
openclaw pairing list
```

### 진단 및 보안

```bash
# 시스템 진단
openclaw doctor

# 보안 감사
openclaw security audit --deep

# 보안 문제 자동 수정
openclaw security audit --fix
```

### Hooks 관리

```bash
# Hook 목록 보기
openclaw hooks list

# Hook 활성화
openclaw hooks enable <name>

# Hook 비활성화
openclaw hooks disable <name>
```

---

## 8. 문제 해결

### 문제: "Connection Refused" 에러

**원인:** Gateway가 실행되지 않음

**해결:**

```bash
openclaw gateway start
# 또는
openclaw chat  # 자동으로 시작됨
```

### 문제: Slack에서 "access not configured" 메시지

**원인:** 사용자 페어링이 안 됨

**해결:**

```bash
openclaw pairing approve slack <페어링코드>
```

### 문제: 웹 UI가 안 열림

**원인:** UI 에셋 누락

**해결:** 터미널 모드(`openclaw chat`)로 사용하거나, 나중에 UI 빌드:

```bash
pnpm ui:build
```

### 문제: Skill 설치 실패

**원인:** macOS 버전 또는 아키텍처 불일치

**해결:**

1. Command Line Tools 업데이트 시도
2. 해당 Skill 없이 사용 (대부분 핵심 기능은 작동함)

---

## 부록: 설정 파일 전체 백업

설정을 백업하려면:

```bash
cp ~/.openclaw/openclaw.json ~/openclaw-backup-$(date +%Y%m%d).json
```

설정 복원:

```bash
cp ~/openclaw-backup-YYYYMMDD.json ~/.openclaw/openclaw.json
openclaw gateway restart
```

---

> [!TIP]
> 문제가 생기면 `openclaw doctor` 명령어로 진단을 시작하세요!
