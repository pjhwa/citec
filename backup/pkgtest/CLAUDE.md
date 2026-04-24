# CLAUDE.md — host-minimize-safe v5.x 테스트 프로젝트

이 파일은 Claude Code가 세션 시작 시 자동으로 읽는 컨텍스트 파일입니다.
아래 지침을 반드시 준수하세요.

---

## 🎯 프로젝트 요약

- **프로젝트**: Samsung SDS CI-TEC `host-minimize-safe` 스크립트 실증 테스트
- **담당자**: Jerry (CI-TEC)
- **목적**: 여러 테스트 서버를 **릴레이 방식**으로 돌면서 v5.0 스크립트를 검증/개선하여 **프로덕션 투입 가능한 v5.x 최종본** 완성
- **환경**: Ubuntu 24.04 Noble, SCPv2 Sovereign (Samsung Cloud Platform v2)

---

## 📋 필수 참조 문서

**세션 시작 시 가장 먼저 아래 문서를 읽으세요**:

```
./claude-code-handoff.md
```

이 파일에는 테스트 전체 워크플로우, Phase 정의, 이터레이션 루프, 번들 계주 규칙이 상세히 기술되어 있습니다. **모든 실전 지침은 이 문서를 기준으로 삼습니다.**

읽어야 할 순서:
1. `claude-code-handoff.md` §0 ~ §11 (배경 + 전체 구조)
2. `claude-code-handoff.md` **§15 「삭제 테스트 시작」 워크플로우** ← 실전 핵심
3. `claude-code-handoff.md` §16 서버 간 계주 규칙
4. 기타 섹션은 필요 시 참조

---

## 🚀 트리거 명령

사용자가 아래 명령을 입력하면 `claude-code-handoff.md §15` 워크플로우를 실행합니다:

| 트리거 명령 | 동작 |
|-------------|------|
| **`삭제 테스트 시작`** | §15 Phase A부터 순차 실행 |
| `테스트 해봐`, `진행해` 등 유사 표현 | 트리거 명령 확인 후 §15 실행 |
| `상태 확인` | Phase A만 실행 (진단만, 후속 작업 없음) |
| `번들 검증` | §16.3 bundle-verify.sh 만 실행 |

---

## 🔒 행동 원칙 (필수 준수)

### 절대 원칙
1. **파괴적 작업은 반드시 사전 승인 요청**: `apt purge`, `rm -rf`, `dpkg --remove`, reboot 계열은 실행 전 사용자에게 "명령어 + 예상 영향 + 되돌리기 방법" 3줄로 확인.
2. **Dry-run을 먼저, 항상**: 모든 제거 작업은 `--execute` 없이 결과 검토 후 진행.
3. **Reboot 금지**: 본 테스트 환경은 LVM 스냅샷 불가 → 부팅 실패 시 복구 어려움.
4. **프로덕션 노드 절대 건드리지 않음**: 테스트 서버가 프로덕션 네트워크에 있다는 증거 발견 시 즉시 중단.

### 이터레이션 원칙
5. **문제 발견 = 스크립트 개선 기회**: 버그를 단순 기록하지 말고 **Jerry 승인 후 스크립트를 직접 수정**하고 재테스트 (핸드오프 §12).
6. **산출물은 다음 서버로 이동할 것을 전제**: 모든 파일은 번들 디렉토리(`~/minimize-test-bundle/`)에 규칙대로 배치 (핸드오프 §6.3).

### 보고서 원칙
7. **테스트 보고서는 항상 상세하게 작성**: `docs/test-report-<server>.md`는 절대 요약하지 않는다. 기준 형식은 `test-report-test-nn2.md`. Phase별 타임라인, 버그 원인 분석, 사후 검증 표, 산출물 목록을 모두 포함 (핸드오프 §G.2).
8. **번들 패키징 전 인계 문서 전체 반영 필수**: `tar czf` 실행 전에 summary.md·CHANGELOG.md·KNOWN-ISSUES.md·test-matrix.csv·BUNDLE-CHECKSUMS.txt가 현 서버 내용을 모두 반영했는지 확인 (핸드오프 §G.4).

### 소통 원칙
9. **한국어 Markdown, 간결체, bullet 선호** (Jerry의 user preference).
10. **불확실성 명시**: 확실하지 않으면 `⚠ [확인 필요]` 로 표기.
11. **모호하면 멈추고 물어라**: 지침과 현실 충돌 시 진행 중단 후 보고.
12. **체크리스트 기반 보고**: ✅/❌/⏭ 기호 사용.

---

## 🛑 즉시 중단 조건

다음 중 하나라도 발생 시 **즉시 중단하고 Jerry에게 보고**:

1. `podman`이 cephadm 프로파일 제거 대상에 포함됨
2. `containerd` 또는 `kubelet`이 k8s 프로파일 제거 대상에 포함됨
3. `openssh-server`가 어떤 프로파일에서든 제거 대상에 포함됨
4. 스크립트 crash/세그폴트
5. 테스트 서버 SSH 접근 불가
6. 연쇄 제거 수가 plan 예상치의 **2배 이상** 초과
7. `dpkg --audit` 또는 `apt-get check` 에러 발생
8. 테스트 서버가 프로덕션 네트워크에 있다는 증거
9. 이전 서버 번들 손상/불완전 (§16.3 검증 실패)

---

## 📁 작업 디렉토리 규칙

- **기본 위치**: `/home/citec/` (또는 Jerry가 지정한 디렉토리)
- **번들 위치**: `~/minimize-test-bundle/` (Phase G에서 구축)
- **외부 백업**: `~/minimize-test-backup/<server>/<TS>/` (Phase D에서 생성)
- **스크립트 로그**: `/var/log/host-minimize/` (스크립트 자체가 생성)

---

## 🔁 세션 시작 시 자동 수행

사용자가 아무 명령도 입력하지 않고 세션만 시작했을 때, 다음과 같이 응답하세요:

```
✅ CLAUDE.md 확인 완료. host-minimize-safe v5.x 릴레이 테스트 프로젝트입니다.

📖 참조 문서: ./claude-code-handoff.md (§15 워크플로우 기반)

현재 작업 디렉토리 상태를 간단히 확인하겠습니다...
[find 명령으로 번들 파일 탐색]

판정: <첫 번째 서버 모드 / 계주 서버 모드>
- 현재 서버: <hostname>
- 발견된 번들 파일: <개수>
- 번들 모드 세부: <요약>

다음 명령을 입력하시면 진행합니다:
- `삭제 테스트 시작` → §15 Phase A부터 전체 워크플로우
- `상태 확인` → 진단만 (Phase A 단독)
- `번들 검증` → bundle-verify.sh 실행
```

---

## 🎯 최종 목표 (Definition of Done)

- [ ] 6개 용도 서버(nn/scn/wproxy/log/cepho/vfwc) 모두에서 Phase A~F 통과
- [ ] 마지막 2개 서버에서 **새 버그 0건** (수렴)
- [ ] 스크립트 v5.0 → v5.1 프로모션
- [ ] `PRODUCTION-RUNBOOK.md` 작성 완료
- [ ] 번들 13종 산출물 완비

상세 기준: `claude-code-handoff.md §4.4`

---

## 📞 참고: Jerry 맥락

- Samsung SDS CI-TEC 26명 인프라/보안팀 리드
- 이 스크립트는 CSAP 9.3 통제(불필요 서비스 제거) 기술 증빙으로 사용됨
- 2026년 5월 말 KISA CSAP 형식 감사 예정
- 과거 관련 작업: CSAP 9.1.4-③(MAC/AppArmor), OpenStack Helm on K8s
- 스타일: 기술 깊이 선호, 불확실성 솔직 표기, 과장 금지

---

## ⚠ 문서가 서로 충돌하면?

우선순위:
1. **사용자의 직접 지시** (최우선)
2. **CLAUDE.md (이 파일)**
3. **claude-code-handoff.md**
4. 기타 프로젝트 내 문서

충돌 발견 시 진행하지 말고 사용자에게 보고.

---

**이제 `claude-code-handoff.md` 를 읽고 대기하세요.**

