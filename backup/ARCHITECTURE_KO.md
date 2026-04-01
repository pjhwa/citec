# Claw Code 아키텍처 심층 분석 문서

> Claude Code 하네스 구조의 Python/Rust 재현 프로젝트 — 상세 한글 해설서

---

## 목차

1. [프로젝트 개요 및 탄생 배경](#1-프로젝트-개요-및-탄생-배경)
2. [전체 구조 한눈에 보기](#2-전체-구조-한눈에-보기)
3. [원본 TypeScript 아키텍처 분석](#3-원본-typescript-아키텍처-분석)
4. [Python 레이어 상세 분석](#4-python-레이어-상세-분석)
5. [Rust 레이어 상세 분석](#5-rust-레이어-상세-분석)
6. [부트스트랩 시퀀스 (시작 흐름)](#6-부트스트랩-시퀀스-시작-흐름)
7. [명령어·도구 시스템](#7-명령어도구-시스템)
8. [권한 모델 (Permission Model)](#8-권한-모델-permission-model)
9. [세션 및 대화 관리](#9-세션-및-대화-관리)
10. [시스템 프롬프트 구조](#10-시스템-프롬프트-구조)
11. [토큰 사용량 추적](#11-토큰-사용량-추적)
12. [세션 압축 (Compaction)](#12-세션-압축-compaction)
13. [원격 실행 모드](#13-원격-실행-모드)
14. [스킬 시스템](#14-스킬-시스템)
15. [다른 AI 모델에 적용하는 방법](#15-다른-ai-모델에-적용하는-방법)
16. [핵심 패턴 요약](#16-핵심-패턴-요약)

---

## 1. 프로젝트 개요 및 탄생 배경

### 무엇인가?

**claw-code**는 Anthropic의 Claude Code 에이전트 하네스(agent harness)의 아키텍처를 연구하고, 이를 Python과 Rust로 재현(clean-room rewrite)한 오픈소스 프로젝트입니다. "하네스(harness)"란 AI 모델이 도구를 사용하고, 사용자와 대화하고, 파일 시스템을 탐색하고, 코드를 작성하는 전체적인 실행 인프라를 의미합니다.

### 왜 만들어졌나?

2026년 3월 31일 새벽 4시, Claude Code의 TypeScript 소스코드가 외부에 노출되는 사건이 발생했습니다. 프로젝트 창시자인 Sigrid Jin(@instructkr)은 법적·윤리적 문제를 피하면서도 그 아키텍처적 패턴을 연구하기 위해, 원본을 복사하지 않고 구조만 참고하여 새벽에 Python으로 처음부터 재현했습니다.

핵심 목적은 두 가지입니다:
1. **하네스 엔지니어링 연구** — AI 에이전트가 내부적으로 어떻게 구성되는지 이해
2. **더 나은 도구 개발** — 단순 아카이브 저장이 아니라, 더 좋은 하네스 도구를 만들기 위한 기반

---

## 2. 전체 구조 한눈에 보기

```
claw-code/
├── src/                        ← Python 포팅 워크스페이스
│   ├── main.py                 ← CLI 진입점 (모든 서브커맨드 정의)
│   ├── runtime.py              ← 최상위 런타임 (PortRuntime)
│   ├── query_engine.py         ← 턴 루프 오케스트레이션
│   ├── commands.py             ← 명령어 레지스트리 (JSON에서 로드)
│   ├── tools.py                ← 도구 레지스트리 (JSON에서 로드)
│   ├── permissions.py          ← 권한 컨텍스트 (허용/차단)
│   ├── session_store.py        ← 세션 영속화 (JSON 파일)
│   ├── transcript.py           ← 대화 로그 (TranscriptStore)
│   ├── history.py              ← 이벤트 히스토리
│   ├── models.py               ← 공유 데이터 클래스
│   ├── context.py              ← 워크스페이스 컨텍스트
│   ├── setup.py                ← 시작 설정 및 사전 로드
│   ├── deferred_init.py        ← 신뢰 게이트 후 지연 초기화
│   ├── prefetch.py             ← 사전 캐시 (MDM, 키체인, 프로젝트 스캔)
│   ├── parity_audit.py         ← Python vs TypeScript 커버리지 측정
│   ├── port_manifest.py        ← 워크스페이스 매니페스트 생성
│   ├── bootstrap_graph.py      ← 부트스트랩 단계 정의
│   ├── command_graph.py        ← 명령어 세그멘테이션
│   ├── tool_pool.py            ← 도구 풀 어셈블리
│   ├── execution_registry.py   ← 명령어/도구 실행 레지스트리
│   ├── cost_tracker.py         ← 비용 추적
│   ├── costHook.py             ← 비용 훅 적용
│   ├── remote_runtime.py       ← 원격/SSH/Teleport 모드
│   ├── direct_modes.py         ← 직접 연결/딥링크 모드
│   ├── system_init.py          ← 시스템 초기화 메시지 빌더
│   ├── QueryEngine.py          ← QueryEngineRuntime (라우팅 통합)
│   ├── query.py                ← QueryRequest/QueryResponse 데이터 클래스
│   ├── tasks.py / task.py      ← 포팅 태스크 관리
│   ├── Tool.py                 ← ToolDefinition 기본 모델
│   └── reference_data/         ← 원본 TypeScript 구조 스냅샷 (JSON)
│       ├── archive_surface_snapshot.json
│       ├── commands_snapshot.json   ← 207개 명령어
│       ├── tools_snapshot.json      ← 184개 도구
│       └── subsystems/             ← 30개 서브시스템 메타데이터
│
├── rust/                       ← Rust 포팅 (실제 동작 가능한 런타임)
│   └── crates/
│       ├── rusty-claude-cli/   ← CLI 바이너리
│       ├── runtime/            ← 핵심 런타임 크레이트
│       ├── api/                ← Claude API 클라이언트 (SSE 스트리밍)
│       ├── commands/           ← 명령어 레지스트리
│       ├── tools/              ← 도구 레지스트리
│       └── compat-harness/     ← TypeScript 소스 호환 레이어
│
└── tests/                      ← Python 검증 테스트
```

---

## 3. 원본 TypeScript 아키텍처 분석

`src/reference_data/archive_surface_snapshot.json`이 기록한 원본 Claude Code의 규모:

| 항목 | 수치 |
|------|------|
| 전체 TypeScript 파일 수 | **1,902개** |
| 명령어 항목 수 | **207개** |
| 도구 항목 수 | **184개** |
| 최상위 서브시스템 수 | **30개** |

### 30개 서브시스템 개요

| 서브시스템 | 파일 수 | 역할 |
|-----------|---------|------|
| `utils` | **564개** | 공통 유틸리티 — 가장 방대한 영역 |
| `components` | **389개** | React/Ink UI 컴포넌트 |
| `services` | **130개** | API 클라이언트, 분석, 세션 메모리 등 |
| `hooks` | **104개** | React 훅 (알림, 권한, MCP 상태 등) |
| `bridge` | **31개** | 원격 브릿지 (웹소켓, JWT, replBridge 등) |
| `keybindings` | **14개** | 키보드 단축키 시스템 |
| `migrations` | **11개** | 설정 마이그레이션 (모델명 변경 등) |
| `types` | **11개** | 공유 타입 정의 |
| `entrypoints` | **8개** | CLI/MCP/SDK 진입점 |
| `memdir` | **8개** | 메모리 디렉토리 시스템 (AI 기억) |
| `cli` | **19개** | CLI 핸들러, 전송 레이어 |
| `skills` | **20개** | 번들 스킬 (loop, debug, TDD 등) |
| `state` | **6개** | 앱 상태 관리 |
| `vim` | **5개** | Vim 모드 지원 |
| `buddy` | **6개** | 컴패니언 스프라이트 (UI 캐릭터) |
| `remote` | **4개** | 원격 세션 관리 |
| `native-ts` | **4개** | 네이티브 바인딩 (color-diff, file-index 등) |
| `plugins` | **2개** | 번들 플러그인 |
| `coordinator` | **1개** | 코디네이터 모드 |
| `assistant` | **1개** | 세션 히스토리 |
| `bootstrap` | **1개** | 부트스트랩 상태 |
| `moreright` | **1개** | UI 확장 훅 |
| `outputStyles` | **1개** | 출력 스타일 로더 |
| `voice` | **1개** | 음성 모드 활성화 |
| `screens` | **3개** | 주요 화면 (Doctor, REPL, ResumeConversation) |
| `server` | **3개** | 직접 연결 서버 |
| `schemas` | **1개** | 훅 스키마 |
| `upstreamproxy` | **2개** | 업스트림 프록시 릴레이 |
| `constants` | **21개** | 상수 정의 (API 한계, 메시지, 프롬프트 등) |
| `context` | 복수 | 컨텍스트 레이어 |

---

## 4. Python 레이어 상세 분석

Python 레이어는 TypeScript 원본의 **구조적 거울(structural mirror)**입니다. 실제 실행 로직보다는 명령어/도구 메타데이터와 런타임 워크플로우를 기록하는 역할을 합니다.

### 4.1 데이터 모델 (`models.py`)

```python
@dataclass(frozen=True)
class Subsystem:
    name: str         # 서브시스템 이름 (예: "utils")
    path: str         # 경로 (예: "src/utils")
    file_count: int   # 파일 수
    notes: str        # 설명

@dataclass(frozen=True)
class PortingModule:
    name: str             # 모듈명 (예: "BashTool")
    responsibility: str   # 역할 설명
    source_hint: str      # 원본 TypeScript 경로
    status: str           # 'planned' | 'mirrored' | 'ported'

@dataclass(frozen=True)
class PermissionDenial:
    tool_name: str    # 차단된 도구 이름
    reason: str       # 차단 이유

@dataclass(frozen=True)
class UsageSummary:
    input_tokens: int    # 입력 토큰 수
    output_tokens: int   # 출력 토큰 수
```

**핵심 설계 원칙**: 모든 모델이 `frozen=True`로 불변(immutable)입니다. 이는 함수형 데이터 흐름을 강제하고 부작용을 최소화합니다.

### 4.2 명령어 레지스트리 (`commands.py`)

207개의 명령어는 `reference_data/commands_snapshot.json`에 저장되어 있으며, 시작 시 한 번만 로드됩니다 (`@lru_cache(maxsize=1)` 사용).

```python
@lru_cache(maxsize=1)
def load_command_snapshot() -> tuple[PortingModule, ...]:
    raw_entries = json.loads(SNAPSHOT_PATH.read_text())
    return tuple(PortingModule(...) for entry in raw_entries)
```

명령어는 세 가지 출처로 분류됩니다:
- **built-in**: 핵심 명령어 (예: `review`, `branch`, `agents`)
- **plugin**: 플러그인에서 로드된 명령어
- **skill**: 스킬 파일에서 로드된 명령어

주요 명령어 예시:
- `add-dir` — 디렉토리 추가
- `advisor` — 조언자 모드
- `agents` — 에이전트 관리
- `ant-trace` — Anthropic 트레이스
- `autofix-pr` — PR 자동 수정
- `branch` — 브랜치 관리
- `bridge` — 원격 브릿지 연결
- `brief` — 요약 브리핑

### 4.3 도구 레지스트리 (`tools.py`)

184개의 도구가 유사한 방식으로 JSON에서 로드됩니다.

**도구 필터링 옵션**:
```python
def get_tools(
    simple_mode: bool = False,      # True면 BashTool, FileReadTool, FileEditTool만
    include_mcp: bool = True,       # False면 MCP 도구 제외
    permission_context: ToolPermissionContext | None = None,  # 차단 목록 적용
) -> tuple[PortingModule, ...]:
```

주요 도구 예시 (AgentTool 서브시스템):
- `AgentTool` — 에이전트 실행 도구
- `agentMemory` — 에이전트 메모리 관리
- `claudeCodeGuideAgent` — Claude Code 가이드 에이전트
- `exploreAgent` — 코드베이스 탐색 에이전트
- `generalPurposeAgent` — 범용 에이전트
- `planAgent` — 계획 수립 에이전트
- `verificationAgent` — 검증 에이전트
- `forkSubagent` — 서브에이전트 포크

### 4.4 권한 컨텍스트 (`permissions.py`)

```python
@dataclass(frozen=True)
class ToolPermissionContext:
    deny_names: frozenset[str]     # 차단할 도구 이름 집합
    deny_prefixes: tuple[str, ...] # 차단할 접두사 목록

    def blocks(self, tool_name: str) -> bool:
        lowered = tool_name.lower()
        return (lowered in self.deny_names or
                any(lowered.startswith(prefix) for prefix in self.deny_prefixes))
```

예를 들어 `deny_prefixes=["mcp"]`로 설정하면 이름이 "mcp"로 시작하는 모든 도구가 차단됩니다.

### 4.5 QueryEngine — 턴 루프 (`query_engine.py`)

`QueryEnginePort`는 대화의 심장부입니다.

```python
@dataclass
class QueryEngineConfig:
    max_turns: int = 8              # 최대 대화 턴 수
    max_budget_tokens: int = 2000   # 최대 토큰 예산
    compact_after_turns: int = 12   # 이 턴 수를 초과하면 압축
    structured_output: bool = False  # JSON 구조화 출력 여부
    structured_retry_limit: int = 2  # 구조화 출력 재시도 횟수
```

**`submit_message()` 동작 흐름**:
1. `max_turns` 초과 여부 확인 → 초과 시 `stop_reason='max_turns_reached'` 반환
2. 요약 라인 생성 (프롬프트, 매칭된 명령어/도구, 권한 거부 건수)
3. 예상 토큰 계산 → `max_budget_tokens` 초과 시 `stop_reason='max_budget_reached'`
4. 메시지를 히스토리에 추가
5. `compact_messages_if_needed()` 호출 (오래된 메시지 압축)
6. `TurnResult` 반환

**스트리밍 이벤트 타입**:
```python
{'type': 'message_start',     'session_id': ..., 'prompt': ...}
{'type': 'command_match',     'commands': [...]}
{'type': 'tool_match',        'tools': [...]}
{'type': 'permission_denial', 'denials': [...]}
{'type': 'message_delta',     'text': ...}
{'type': 'message_stop',      'usage': {...}, 'stop_reason': ...}
```

### 4.6 런타임 라우팅 (`runtime.py`)

`PortRuntime`은 프롬프트를 명령어/도구로 라우팅하는 역할을 합니다.

**라우팅 알고리즘**:
1. 프롬프트를 공백·슬래시·하이픈으로 토큰화
2. 각 명령어/도구에 대해 점수 계산:
   - 토큰이 이름, source_hint, responsibility에 포함되면 +1점
3. 상위 K개 선택 (명령어 1개 + 도구 1개 보장, 나머지는 점수 내림차순)

```python
@staticmethod
def _score(tokens: set[str], module: PortingModule) -> int:
    haystacks = [module.name.lower(), module.source_hint.lower(),
                 module.responsibility.lower()]
    return sum(1 for token in tokens
               if any(token in haystack for haystack in haystacks))
```

**특별 권한 처리**: `bash`가 이름에 포함된 도구는 자동으로 `PermissionDenial`에 추가됩니다 — "destructive shell execution remains gated".

---

## 5. Rust 레이어 상세 분석

Rust 레이어는 Python과 달리 **실제로 동작하는** 에이전트 런타임입니다.

### 5.1 크레이트 구조

```
rust/crates/
├── rusty-claude-cli/   ← 사용자 대면 CLI 바이너리
├── runtime/            ← 핵심 런타임 (회화, 권한, 세션, 압축 등)
├── api/                ← HTTP/SSE Claude API 클라이언트
├── commands/           ← 명령어 레지스트리
├── tools/              ← 도구 레지스트리
└── compat-harness/     ← TypeScript 소스 호환 분석
```

### 5.2 ConversationRuntime — 대화 엔진 (`runtime/conversation.rs`)

가장 핵심적인 구조체입니다.

```rust
pub struct ConversationRuntime<C, T> {
    session: Session,               // 현재 대화 상태
    api_client: C,                  // API 클라이언트 (트레이트)
    tool_executor: T,               // 도구 실행기 (트레이트)
    permission_policy: PermissionPolicy,  // 권한 정책
    system_prompt: Vec<String>,     // 시스템 프롬프트 섹션들
    max_iterations: usize,          // 최대 반복 횟수 (기본값: 16)
    usage_tracker: UsageTracker,    // 토큰 사용량 추적
}
```

**`run_turn()` 동작 흐름** (에이전트의 핵심 루프):

```
사용자 입력 추가
    ↓
루프 시작 (최대 max_iterations번)
    ↓
API에 요청 (system_prompt + messages)
    ↓
스트리밍 이벤트 수신
    - TextDelta → 텍스트 누적
    - ToolUse → 도구 사용 요청 수집
    - Usage → 토큰 사용량 기록
    - MessageStop → 루프 종료 신호
    ↓
도구 사용 요청이 없으면? → 루프 종료
    ↓
도구 사용 요청이 있으면?
    - 각 도구에 대해 permission_policy.authorize() 호출
    - Allow → tool_executor.execute() 실행
    - Deny → 거부 이유를 tool_result로 반환
    ↓
도구 결과를 session에 추가
    ↓
다음 반복으로
```

**제네릭 설계의 의미**: `ApiClient`와 `ToolExecutor`가 트레이트로 추상화되어 있어, 실제 API 클라이언트나 도구 실행기를 테스트 더블(mock)로 쉽게 교체할 수 있습니다.

### 5.3 시스템 프롬프트 빌더 (`runtime/prompt.rs`)

```rust
pub struct SystemPromptBuilder {
    output_style_name: Option<String>,    // 출력 스타일 이름
    output_style_prompt: Option<String>,  // 출력 스타일 지시
    os_name: Option<String>,             // 운영체제 이름
    os_version: Option<String>,          // 운영체제 버전
    append_sections: Vec<String>,         // 추가 섹션
    project_context: Option<ProjectContext>,  // 프로젝트 컨텍스트
    config: Option<RuntimeConfig>,        // 런타임 설정
}
```

`build()` 호출 시 생성되는 시스템 프롬프트 섹션 순서:
1. 소개 섹션 (에이전트 역할 정의)
2. 출력 스타일 섹션 (옵션)
3. `# System` — 도구 사용 규칙
4. `# Doing tasks` — 작업 수행 원칙
5. `# Executing actions with care` — 행동 안전성 원칙
6. `__SYSTEM_PROMPT_DYNAMIC_BOUNDARY__` — 정적/동적 경계 마커
7. `# Environment context` — 모델, CWD, 날짜, 플랫폼
8. `# Project context` — 날짜, Git 상태
9. `# Claude instructions` — CLAUDE.md 파일 내용
10. `# Runtime config` — settings.json 내용
11. 추가 섹션 (append_sections)

**`SYSTEM_PROMPT_DYNAMIC_BOUNDARY` 마커의 의미**: 이 경계선 위의 내용은 정적(모든 세션 공통)이고, 아래 내용은 동적(세션마다 다름)입니다. 이 구분은 프롬프트 캐싱(prompt caching) 최적화에 활용됩니다 — 정적 부분은 캐시되고, 동적 부분은 매 요청마다 새로 전송됩니다.

**지시 파일 탐색 (`discover_instruction_files`)**:
현재 디렉토리부터 루트까지 올라가며 다음 파일을 찾습니다:
- `CLAUDE.md`
- `CLAUDE.local.md`
- `.claude/CLAUDE.md`

루트에서 가장 가까운 파일부터 순서대로 적용됩니다. 즉, 더 구체적인(깊은) 디렉토리의 규칙이 나중에 적용됩니다.

### 5.4 권한 시스템 (`runtime/permissions.rs`)

```rust
pub enum PermissionMode {
    Allow,   // 자동 허가
    Deny,    // 자동 거부
    Prompt,  // 사용자에게 묻기
}

pub struct PermissionPolicy {
    default_mode: PermissionMode,               // 기본 모드
    tool_modes: BTreeMap<String, PermissionMode>,  // 도구별 오버라이드
}
```

`authorize()` 동작:
- `Allow` → 즉시 허가
- `Deny` → 즉시 거부 + 이유 반환
- `Prompt` + prompter 있음 → 사용자에게 물어봄
- `Prompt` + prompter 없음 → 자동 거부 (비대화형 환경에서 안전)

### 5.5 세션 데이터 모델 (`runtime/session.rs`)

```rust
pub enum ContentBlock {
    Text { text: String },
    ToolUse { id: String, name: String, input: String },
    ToolResult { tool_use_id: String, tool_name: String,
                 output: String, is_error: bool },
}

pub struct ConversationMessage {
    pub role: MessageRole,       // System | User | Assistant | Tool
    pub blocks: Vec<ContentBlock>,
    pub usage: Option<TokenUsage>,
}

pub struct Session {
    pub version: u32,
    pub messages: Vec<ConversationMessage>,
}
```

세션은 JSON으로 직렬화/역직렬화됩니다 (`save_to_path` / `load_from_path`).

---

## 6. 부트스트랩 시퀀스 (시작 흐름)

Claude Code가 시작될 때 7단계를 거칩니다 (`bootstrap_graph.py`):

```
단계 1: top-level prefetch side effects
  └── MDM 읽기, 키체인 사전 로드, 프로젝트 스캔 (비동기, 블로킹 없음)

단계 2: warning handler and environment guards
  └── 런타임 환경 검증, 경고 핸들러 등록

단계 3: CLI parser and pre-action trust gate
  └── CLI 인수 파싱
  └── 신뢰 여부 결정 (trusted=True/False)
  └── 신뢰 여부에 따라 다음 단계 분기

단계 4: setup() + commands/agents parallel load
  └── 플랫폼 정보 수집 (Python 버전, OS 등)
  └── 명령어 스냅샷 로드 (207개)
  └── 도구 스냅샷 로드 (184개)

단계 5: deferred init after trust
  └── (trusted=True인 경우에만 실행)
  └── 플러그인 초기화
  └── 스킬 초기화
  └── MCP 서버 사전 연결
  └── 세션 훅 등록

단계 6: mode routing
  └── local REPL 모드 (기본)
  └── remote 모드 (원격 제어)
  └── SSH 모드
  └── Teleport 모드
  └── direct-connect 모드
  └── deep-link 모드

단계 7: query engine submit loop
  └── 사용자 입력 대기
  └── 프롬프트 라우팅
  └── 도구 실행
  └── 응답 스트리밍
  └── 반복
```

**신뢰 게이트(Trust Gate)의 중요성**: 신뢰되지 않은 환경(예: 처음 실행, 권한 없는 디렉토리)에서는 플러그인과 MCP 서버가 초기화되지 않습니다. 이는 악성 플러그인이나 MCP 서버가 자동으로 실행되는 것을 방지합니다.

---

## 7. 명령어·도구 시스템

### 7.1 명령어 그래프 (`command_graph.py`)

명령어는 세 그룹으로 분류됩니다:

| 그룹 | 기준 | 예시 |
|------|------|------|
| **Built-in** | source_hint에 'plugin'도 'skills'도 없음 | `review`, `branch`, `agents` |
| **Plugin-like** | source_hint에 'plugin' 포함 | 플러그인 제공 명령어 |
| **Skill-like** | source_hint에 'skills' 포함 | 스킬 파일 명령어 |

### 7.2 도구 풀 어셈블리 (`tool_pool.py`)

```python
def assemble_tool_pool(
    simple_mode: bool = False,          # True: 핵심 3개만
    include_mcp: bool = True,           # False: MCP 도구 제외
    permission_context: ToolPermissionContext | None = None,
) -> ToolPool:
```

**Simple Mode**: 복잡한 작업에서 모델이 도구를 오남용하지 않도록, 세 가지 핵심 도구만 노출합니다:
1. `BashTool` — 셸 명령어 실행
2. `FileReadTool` — 파일 읽기
3. `FileEditTool` — 파일 편집

### 7.3 실행 레지스트리 (`execution_registry.py`)

```python
@dataclass(frozen=True)
class MirroredCommand:
    name: str
    source_hint: str

    def execute(self, prompt: str) -> str:
        return execute_command(self.name, prompt).message

@dataclass(frozen=True)
class MirroredTool:
    name: str
    source_hint: str

    def execute(self, payload: str) -> str:
        return execute_tool(self.name, payload).message
```

현재 Python 포트에서는 실제 실행 로직이 없고, "이 명령어/도구가 존재하며 여기서 왔다"는 메타데이터 실행을 반환합니다.

---

## 8. 권한 모델 (Permission Model)

Claude Code의 권한 모델은 **세 가지 레이어**로 구성됩니다:

### 레이어 1: 전역 권한 모드

`settings.json`의 `permissionMode` 필드:
- `allow` — 모든 도구 자동 허가
- `prompt` — 모든 도구 실행 전 사용자 확인
- `deny` — 모든 도구 차단

### 레이어 2: 도구별 오버라이드

Rust의 `PermissionPolicy.with_tool_mode()`:
```rust
let policy = PermissionPolicy::new(PermissionMode::Prompt)
    .with_tool_mode("bash", PermissionMode::Allow)      // bash는 항상 허가
    .with_tool_mode("delete", PermissionMode::Deny);    // delete는 항상 거부
```

### 레이어 3: 이름/접두사 차단 (Python)

`ToolPermissionContext`:
```python
context = ToolPermissionContext.from_iterables(
    deny_names=["DangerousTool"],
    deny_prefixes=["mcp", "experimental"],
)
```

### 권한 결정 흐름

```
도구 실행 요청
    ↓
도구별 오버라이드 있음? → 해당 모드 적용
    ↓ 없음
전역 permissionMode 적용
    ↓
Allow → 즉시 실행
Deny  → 거부 메시지 반환 (에이전트에게 전달)
Prompt → 사용자에게 물어봄
    ├── 사용자 허가 → 실행
    └── 사용자 거부 → 거부 이유 반환
```

**중요**: 거부(Deny)된 도구의 결과는 에이전트에게 tool_result로 반환됩니다. 에이전트는 거부 이유를 알고 다른 방법을 찾거나 사용자에게 상황을 설명할 수 있습니다.

---

## 9. 세션 및 대화 관리

### 9.1 세션 스토어 (`session_store.py`)

세션은 `.port_sessions/` 디렉토리에 `{session_id}.json` 파일로 저장됩니다.

```python
@dataclass(frozen=True)
class StoredSession:
    session_id: str           # UUID hex
    messages: tuple[str, ...]  # 사용자 메시지 목록
    input_tokens: int         # 누적 입력 토큰
    output_tokens: int        # 누적 출력 토큰
```

### 9.2 TranscriptStore (`transcript.py`)

세션 내에서 실시간으로 대화를 추적합니다:

```python
@dataclass
class TranscriptStore:
    entries: list[str]   # 메시지 목록
    flushed: bool        # 영속화 여부

    def compact(self, keep_last: int = 10) -> None:
        # 최근 N개만 유지
        if len(self.entries) > keep_last:
            self.entries[:] = self.entries[-keep_last:]
```

### 9.3 Rust 세션 (`runtime/session.rs`)

Rust 세션은 훨씬 풍부한 구조를 가집니다:
- 각 메시지에 `role` (User/Assistant/Tool)
- `ContentBlock` 배열 (텍스트, 도구 사용, 도구 결과)
- `TokenUsage` (각 Assistant 메시지의 토큰 사용량)

이를 통해:
- 세션 복원 시 정확한 토큰 사용량 재계산 가능
- 특정 도구 호출의 결과를 정확히 추적 가능
- 전체 대화 흐름을 JSON으로 완전히 직렬화/복원 가능

---

## 10. 시스템 프롬프트 구조

Rust `SystemPromptBuilder`가 생성하는 시스템 프롬프트의 전체 구조:

### 섹션 1: 소개 (항상 포함)
```
You are an interactive agent that helps users with software engineering tasks.
Use the instructions below and the tools available to you to assist the user.

IMPORTANT: You must NEVER generate or guess URLs...
```

### 섹션 2: 출력 스타일 (선택)
```
# Output Style: {이름}
{스타일 지시사항}
```
예: `# Output Style: Concise` + `Prefer short answers.`

### 섹션 3: System (항상 포함)
```
# System
 - All text you output outside of tool use is displayed to the user.
 - Tools are executed in a user-selected permission mode...
 - Tool results may include data from external sources...
 - ...
```

### 섹션 4: Doing Tasks (항상 포함)
```
# Doing tasks
 - Read relevant code before changing it...
 - Do not add speculative abstractions...
 - Report outcomes faithfully...
```

### 섹션 5: Actions with Care (항상 포함)
```
# Executing actions with care
Carefully consider reversibility and blast radius...
```

### 경계 마커 (캐싱 분리선)
```
__SYSTEM_PROMPT_DYNAMIC_BOUNDARY__
```

### 섹션 6: Environment Context (동적, 항상 포함)
```
# Environment context
 - Model family: Claude Opus 4.6
 - Working directory: /Users/user/project
 - Date: 2026-04-01
 - Platform: macOS 15.4
```

### 섹션 7: Project Context (동적, Git 있으면 포함)
```
# Project context
 - Today's date is 2026-04-01.

Git status snapshot:
## main...origin/main
M src/main.py
?? new_file.py
```

### 섹션 8: Claude Instructions (동적, CLAUDE.md 있으면 포함)
```
# Claude instructions

## /Users/user/project/CLAUDE.md
{CLAUDE.md 내용}

## /Users/user/project/.claude/CLAUDE.md
{.claude/CLAUDE.md 내용}
```

### 섹션 9: Runtime Config (동적, settings.json 있으면 포함)
```
# Runtime config
 - Loaded ProjectLocal: /Users/user/project/.claude/settings.json

{"permissionMode": "acceptEdits", ...}
```

---

## 11. 토큰 사용량 추적

### Python 레이어

```python
@dataclass(frozen=True)
class UsageSummary:
    input_tokens: int = 0
    output_tokens: int = 0

    def add_turn(self, prompt: str, output: str) -> 'UsageSummary':
        # 간단한 단어 수 기반 근사 계산
        return UsageSummary(
            input_tokens=self.input_tokens + len(prompt.split()),
            output_tokens=self.output_tokens + len(output.split()),
        )
```

### Rust 레이어 (정확한 추적)

```rust
pub struct TokenUsage {
    pub input_tokens: u32,
    pub output_tokens: u32,
    pub cache_creation_input_tokens: u32,  // 프롬프트 캐시 생성 토큰
    pub cache_read_input_tokens: u32,      // 프롬프트 캐시 읽기 토큰
}

pub struct UsageTracker {
    turns: Vec<TokenUsage>,
}
```

Rust 레이어는 캐시 토큰까지 추적합니다. `cache_creation_input_tokens`는 처음 캐시를 만들 때 비용이 들고, 이후 `cache_read_input_tokens`는 훨씬 저렴합니다. 이를 통해 실제 비용을 정확히 계산할 수 있습니다.

---

## 12. 세션 압축 (Compaction)

대화가 길어지면 컨텍스트 윈도우를 넘게 됩니다. Claude Code는 자동 압축으로 이를 해결합니다.

### 압축 기준 (`compact.rs`)

```rust
pub struct CompactionConfig {
    pub preserve_recent_messages: usize,   // 최근 N개 메시지 보존 (기본값: 4)
    pub max_estimated_tokens: usize,        // 이 이상이면 압축 (기본값: 10,000)
}

pub fn should_compact(session: &Session, config: CompactionConfig) -> bool {
    session.messages.len() > config.preserve_recent_messages
        && estimate_session_tokens(session) >= config.max_estimated_tokens
}
```

토큰 추정은 글자 수 ÷ 4 + 1로 계산합니다 (근사값).

### 압축 과정

```
1. 보존할 최근 N개 메시지 분리
2. 오래된 메시지들을 요약 텍스트로 변환:
   - 각 메시지를 "role: content" 형식으로 요약
   - 160자를 넘으면 잘라서 '…' 추가
3. 요약을 System 역할의 메시지로 삽입
4. 최근 메시지들을 그 뒤에 추가
5. 압축된 세션 반환
```

### 압축 이후 계속하기 메시지

```
This session is being continued from a previous conversation that ran out of context.
The summary below covers the earlier portion of the conversation.

Summary:
{요약 내용}

Recent messages are preserved verbatim.
Continue the conversation from where it left off without asking the user any further questions.
Resume directly — do not acknowledge the summary, do not recap what was happening,
and do not preface with continuation text.
```

**이 메시지의 핵심**: 모델에게 "요약을 인식했다고 말하지 말고 그냥 계속하라"고 지시합니다. 사용자 경험을 자연스럽게 유지하기 위해서입니다.

---

## 13. 원격 실행 모드

Claude Code는 6가지 실행 모드를 지원합니다:

| 모드 | 설명 | 사용 케이스 |
|------|------|-------------|
| **local** | 기본 REPL 모드 | 일반 로컬 사용 |
| **remote** | 원격 제어 모드 | 다른 Claude Code 인스턴스 제어 |
| **ssh** | SSH 프록시 모드 | 원격 서버에서 실행 |
| **teleport** | Teleport 세션 재개/생성 | 기업 환경 원격 접근 |
| **direct-connect** | 직접 연결 서버 | IDE 통합, 로컬 API 서버 |
| **deep-link** | 딥링크 모드 | 외부 앱에서 Claude Code 호출 |

Python 포트에서는 이 모드들이 placeholder로 구현되어 있습니다 — 실제 연결 로직 없이 모드 이름과 연결 상태만 반환합니다. 원본 TypeScript에서는 완전한 WebSocket/SSH 연결 로직이 구현되어 있었습니다.

---

## 14. 스킬 시스템

스킬은 사용자 정의 프롬프트 템플릿으로, 에이전트의 행동을 확장합니다.

### 번들 스킬 목록 (`reference_data/subsystems/skills.json`)

```
skills/bundled/
├── batch.ts          ← 배치 작업 처리
├── claudeApi.ts      ← Claude API 직접 사용
├── claudeApiContent.ts
├── claudeInChrome.ts ← 브라우저 내 Claude
├── debug.ts          ← 체계적 디버깅
├── index.ts
├── keybindings.ts    ← 키바인딩 설정
├── loop.ts           ← 반복 실행 루프
├── loremIpsum.ts     ← Lorem ipsum 생성
├── remember.ts       ← 기억 저장
├── scheduleRemoteAgents.ts ← 원격 에이전트 스케줄링
├── simplify.ts       ← 코드 단순화
├── skillify.ts       ← 스킬 작성 도우미
├── stuck.ts          ← 막혔을 때 도우미
├── updateConfig.ts   ← 설정 업데이트
├── verify.ts         ← 검증 워크플로우
└── verifyContent.ts  ← 컨텐츠 검증
```

### 스킬 로딩 메커니즘

스킬은 두 가지 방식으로 로드됩니다:
1. **번들 스킬**: 하네스에 내장 (`skills/bundledSkills.ts`)
2. **디렉토리 스킬**: 사용자 디렉토리에서 동적 로드 (`skills/loadSkillsDir.ts`)
3. **MCP 스킬 빌더**: MCP 서버가 제공하는 스킬 (`skills/mcpSkillBuilders.ts`)

스킬은 명령어의 특수한 형태로, `command_graph`에서 `skill-like` 카테고리로 분류됩니다.

---

## 15. 다른 AI 모델에 적용하는 방법

이 리포지토리에서 추출한 패턴을 다른 AI 모델(GPT-4, Gemini 등)에 적용하려면:

### 15.1 시스템 프롬프트 적용

`SYSTEM_PROMPT.md` 파일의 내용을 기반으로 시스템 프롬프트를 작성하세요. 핵심 섹션:

1. **역할 정의** — 에이전트가 무엇을 하는지 명확히 정의
2. **System 섹션** — 도구 사용 규칙, 권한 모드, 태그 처리
3. **Doing Tasks 섹션** — 작업 수행 원칙 (읽기 전에 변경하지 않기, 불필요한 파일 생성하지 않기 등)
4. **Actions with Care 섹션** — 되돌리기 어려운 작업에 대한 주의
5. **환경 컨텍스트** — CWD, 날짜, 플랫폼 정보 동적 삽입
6. **프로젝트 지시** — CLAUDE.md 파일 내용 삽입

### 15.2 대화 루프 구현

```python
# 최소한의 에이전트 대화 루프 의사코드
def run_agent_loop(user_input, max_iterations=16):
    messages = [{"role": "user", "content": user_input}]

    for _ in range(max_iterations):
        response = api_call(system_prompt, messages)

        # 텍스트만 있으면 완료
        if response.stop_reason == "end_turn":
            return response.text

        # 도구 사용 요청이 있으면
        for tool_use in response.tool_uses:
            # 권한 확인
            if not permission_policy.allow(tool_use.name):
                tool_result = f"Denied: {reason}"
            else:
                tool_result = execute_tool(tool_use.name, tool_use.input)

            messages.append({"role": "tool", "tool_use_id": tool_use.id,
                            "content": tool_result})

        messages.append(response.as_message())
```

### 15.3 핵심 도구 세트

최소 에이전트에 필요한 도구들:
- **파일 읽기** — 파일 내용 읽기 (줄 번호, 범위 지원)
- **파일 편집** — 정확한 문자열 치환으로 파일 수정
- **파일 쓰기** — 새 파일 생성
- **셸 실행** — Bash/sh 명령어 실행
- **파일 검색** — glob 패턴 매칭
- **내용 검색** — grep/ripgrep 검색

### 15.4 세션 영속화

세션을 영속화하려면:
```json
{
  "session_id": "abc123",
  "messages": ["user message 1", "user message 2"],
  "input_tokens": 1500,
  "output_tokens": 800
}
```

### 15.5 컨텍스트 압축

긴 대화를 처리하려면 압축 메커니즘이 필요합니다:
1. 예상 토큰 수가 임계값 초과 시 압축 시작
2. 최근 N개 메시지 보존
3. 나머지를 요약 텍스트로 변환
4. 요약을 System 메시지로 대화 앞에 삽입
5. 모델에게 "요약을 언급하지 말고 계속하라" 지시

---

## 16. 핵심 패턴 요약

이 리포지토리에서 배울 수 있는 Claude Code 하네스의 핵심 패턴들:

### 패턴 1: 신뢰 게이트 초기화
```
시작 → 환경 검사 → 신뢰 결정 → 조건부 초기화
```
신뢰되지 않은 환경에서 플러그인/MCP 서버를 초기화하지 않음으로써 보안을 강화합니다.

### 패턴 2: 불변 데이터 모델
모든 핵심 데이터 구조가 불변(frozen/immutable)입니다. 상태 변경은 새 객체 생성으로만 가능합니다.

### 패턴 3: 레지스트리 기반 도구 관리
도구와 명령어를 코드에 하드코딩하지 않고 JSON 레지스트리에 저장합니다. 런타임에 필터링(MCP 제외, 권한 차단 등)이 가능합니다.

### 패턴 4: 스트리밍 이벤트 타입
API 응답을 스트리밍으로 처리하며, 각 이벤트 타입을 구분합니다:
- `message_start` → `command_match` → `tool_match` → `message_delta` → `message_stop`

### 패턴 5: 계층적 권한
전역 모드 → 도구별 오버라이드 → 이름/접두사 차단의 3계층 권한 시스템

### 패턴 6: 동적 경계 마커
`__SYSTEM_PROMPT_DYNAMIC_BOUNDARY__`로 정적/동적 프롬프트를 분리하여 캐싱을 최적화합니다.

### 패턴 7: 자동 세션 압축
토큰 예산 초과 시 오래된 메시지를 요약으로 대체하되, 최근 메시지는 원문 보존합니다.

### 패턴 8: 지시 파일 계층
`CLAUDE.md` → `CLAUDE.local.md` → `.claude/CLAUDE.md`의 계층적 지시 파일로 프로젝트별, 환경별, 로컬별 규칙을 분리합니다.

### 패턴 9: 점수 기반 프롬프트 라우팅
프롬프트 토큰과 명령어/도구 메타데이터 간의 겹침으로 관련 도구를 선택합니다. 완벽한 NLP 없이도 합리적인 라우팅이 가능합니다.

### 패턴 10: 서브에이전트 지원
독립적인 작업을 별도 서브에이전트에 위임하여 병렬 처리가 가능합니다. 서브에이전트는 격리된 git worktree에서 실행될 수 있습니다.

---

## 부록: 프로젝트를 통해 확인된 원본 Claude Code의 규모

이 리포지토리가 기록한 원본 Claude Code (2026년 3월 기준) 수치:

| 항목 | 수치 | 비고 |
|------|------|------|
| TypeScript 파일 | 1,902개 | src/ 기준 |
| 명령어 (commands) | 207개 | 슬래시 커맨드 포함 |
| 도구 (tools) | 184개 | MCP 도구 포함 |
| 서브시스템 | 30개 | 최상위 디렉토리 기준 |
| utils 모듈 수 | 564개 | 가장 방대한 영역 |
| components 수 | 389개 | UI 컴포넌트 |
| services 수 | 130개 | 백엔드 서비스 |
| hooks 수 | 104개 | React 훅 |

이 수치는 Claude Code가 단순한 chatbot 래퍼가 아니라, 수천 개의 모듈로 이루어진 정교한 소프트웨어 엔지니어링 플랫폼임을 보여줍니다.

---

*이 문서는 claw-code 리포지토리의 Python 및 Rust 소스코드를 심층 분석하여 작성되었습니다.*
*작성일: 2026년 4월 1일*
