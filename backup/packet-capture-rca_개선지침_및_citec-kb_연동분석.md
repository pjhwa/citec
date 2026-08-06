# packet-capture-rca 개선 지침 및 citec-kb 연동 심화 분석

**목적:** 이 문서는 두 부분으로 구성된다.
- **Part A** — packet-capture-rca 스킬 자체의 개선 항목을, 이 저장소를 편집할 미래의 Claude 세션이
  그대로 실행할 수 있는 수준의 **작업 지시서**로 상세화한다 (대상 파일, 삽입 위치, 삽입 내용 초안,
  완료 판정 기준 포함).
- **Part B** — citec-kb(`~/dev/citec-kb`) 및 그 MCP 서버(wiki-mcp, `mcp-server/server.py`)의 실제
  소스코드를 직접 읽고 확인한 근거를 바탕으로, failure_bucket 연동을 어떻게 개선할 수 있는지 분석한다.

**선행 정정:** 직전 분석(`packet-capture-rca_핵심분석.md`)의 "캡처 확보(acquisition)가 범위 밖"이라는
지적은 **철회한다**. 사용자 확인에 따르면 이 스킬은 애초에 운영부서가 이슈 설명과 함께 이미 확보해
보내온 pcap을 분석하는 데 쓰인다 — 캡처 확보가 범위 밖인 것은 결함이 아니라 **의도된 설계 경계**다.
이 정정에 따라 개선 우선순위를 재배치했다(이전 문서의 §6 순위 1, §7-2 (D)는 폐기).

**추가 실측:** Part B 작성 중 사용자 요청에 따라 wiki-mcp로 citec-kb에 실제 등록된 `failure_bucket`
4건을 `kb_list_failure_buckets`/`kb_get_failure_bucket`으로 직접 조회했다(§B-0-a). 코드 추론이 아닌
운영 데이터로 확인한 결과, Part B의 개선 항목 중 특히 `evidence_ref` 검증(§B-3)의 시급성이
이론적 리스크가 아니라 **지금 등록된 4건 전부에 실재하는 문제**임이 드러났다 — 관련 신뢰도를
상향했다.

---

# Part A. packet-capture-rca 스킬 개선 — 실행용 상세 지침

각 항목은 **목표 → 대상 파일 → 근거 → 신뢰도/반증신호 → 구체적 작업 지시 → 완료 판정 기준**의
동일한 틀로 작성했다. 실행 순서는 §A-0(우선순위)를 따른다.

## A-0. 우선순위와 실행 순서

| 순위 | 항목 | 이유 |
|---|---|---|
| 1 | A-1 mTLS 복호화/우회 레시피 | 서비스 메시 캡처에서 L7 관측 자체가 불가능해지는, 가장 치명적인 공백 |
| 2 | A-2 HTTP/2·gRPC 스파인 질문 확장 | 클라우드 네이티브 백엔드 간 트래픽의 기본값이 되어가는 프로토콜을 다루지 못함 |
| 3 | A-3 클럭 스큐 측정 한계 추가 | 이미 존재하는 다중 캡처 인터리빙 지침(SKILL.md:208)의 정확성을 담보하는 저비용 수정 |
| 4 | A-4 기준선(baseline) 확보 절차 명문화 | 이미 부분적으로 존재하는 지침을 구체화하는 저비용 수정 |
| 5 | A-5 트레이스ID/요청ID 상관 레시피 | 분산 트랜잭션 식별에 유용하나, Part B의 개선(특히 evidence_ref 관례)과 맞물려야 완전한 가치 |
| 6 | A-6 citec-kb 연동 지침에 environment 반영 | **Part B-1의 citec-kb 측 변경이 먼저 배포된 뒤에만 실행** — 순서 뒤바뀌면 존재하지 않는 파라미터를 호출하게 됨 |

A-1~A-4는 서로 독립적이며 병렬로 작업 가능하다. A-6은 반드시 Part B-1이 citec-kb 저장소에
반영된 뒤 진행한다.

---

## A-1. mTLS 복호화/우회 레시피 추가

**목표:** 서비스 메시(Istio/Linkerd류) 환경에서 사이드카 간 mTLS로 인해 L7 페이로드가 보이지 않을 때,
분석을 이어갈 수 있는 표준 절차를 제공한다.

**대상 파일:** `skills/packet-capture-rca/references/tshark-recipes.md` — "## L5 / L6 (TLS)" 섹션
(현재 142–162행, `tls.handshake.type` / QUIC guard 뒤)

**근거:** 해당 섹션 전체를 확인한 결과 `tls.keylog_file`/`SSLKEYLOGFILE` 관련 언급이 전혀 없다
(tshark-recipes.md:142–162). SKILL.md:163–165의 "프록시는 백엔드에 평문으로 말한다"는 관찰은 mTLS
메시에서 성립하지 않는다.

**신뢰도/반증 신호:** High — 반증 신호: 향후 실제 mTLS 캡처 분석 세션에서 이 레시피 없이도 L7
관측에 성공한 사례가 나오면(예: 사이드카가 여전히 로컬호스트 루프백 구간에서는 평문으로 통신하는
구조라면) 이 레시피의 필요성은 좁아진다 — 그 경우 "루프백 캡처 지점" 자체를 대안으로 문서화해야 한다.

**구체적 작업 지시:**

1. `tshark-recipes.md`의 TLS 섹션 끝(QUIC guard 다음, L7 섹션 시작 전)에 아래 서브섹션을 추가한다:

```markdown
## mTLS(서비스 메시) 복호화 — 가능한 경우

사이드카 mTLS(Istio/Linkerd류)로 파드 간 트래픽이 전 구간 암호화된 경우, L7 스파인 질문(바디
완전성, 4xx/5xx 본문)에 답할 페이로드 자체가 캡처에 없을 수 있다. 아래 순서로 우회를 시도한다.

1. **키로그 파일이 존재하는지 먼저 확인한다.** 애플리케이션/사이드카가 `SSLKEYLOGFILE` 환경변수를
   지원하도록 이미 설정돼 있었는지 운영팀에 확인한다 — 사후에 캡처만으로는 복구 불가능하므로, 이
   질문은 "Ask before you analyze"(SKILL.md 99–112행) 단계에서 반드시 물어야 한다.
2. 키로그 파일이 있으면:
   ```
   & $ts -r "<file>" -o "tls.keylog_file:<keylog경로>" -Y "tls" -T fields -e frame.number -e http2.streamid
   ```
   Wireshark GUI에서는 Edit → Preferences → Protocols → TLS → (Pre)-Master-Secret log filename에
   지정 후 동일하게 복호화된 상태로 필터링한다.
3. 키로그가 없으면 복호화는 불가능하다 — 이 경우 **측정 한계로 명시**하고(부록 B), 대안으로
   사이드카 **직전/직후의 루프백(localhost) 구간**에서 별도로 캡처된 파일이 있는지 확인한다. Istio류
   사이드카는 앱 컨테이너와 Envoy 사이를 평문으로 통신하는 경우가 많다 — 이 구간의 캡처가 있다면
   L7 진실 레버(SKILL.md:163–165)를 그 지점으로 옮겨 적용할 수 있다.
4. 어느 쪽도 안 되면, TCP 레벨 신호(RST/FIN 타이밍, zero-window, 재전송)만으로 판정 가능한
   버킷으로 스코프를 좁히고, L7 근거가 필요한 주장은 하지 않는다 — analysis-methodology.md의
   "관측 vs 추론" 규율을 그대로 적용해 "페이로드 내용은 확인 불가(mTLS, 키로그 없음)"를 부록 B에
   명시한다.
```

2. `analysis-methodology.md`의 "측정 한계" 목록(현재 109–119행)에 항목 추가:
   `- **mTLS 암호화 + 키로그 없음** → L7 페이로드 판독 불가, TCP 레벨 신호로만 판정. 이 경우
   바디 완전성 등 L7 의존 버킷 배정은 보류하거나 "확인 불가"로 명시한다.`

**완료 판정 기준:** `tshark-recipes.md`에 위 서브섹션이 존재하고, `analysis-methodology.md` 측정
한계 목록에 mTLS 항목이 추가되어 있으며, "Ask before you analyze" 절(SKILL.md)에 키로그 파일 존재
여부를 묻는 항목이 반영되어 있다.

---

## A-2. HTTP/2·gRPC 멀티플렉싱 — 스파인 질문/버킷 확장

**목표:** "하나의 tcp.stream = 하나의 트랜잭션"이라는 HTTP/1.1 전제가 깨지는 HTTP/2·gRPC 트래픽에도
스파인 질문과 버킷 어휘를 적용 가능하게 한다.

**대상 파일:**
- `skills/packet-capture-rca/references/analysis-methodology.md` — 스파인 질문 섹션(현재 6–19행,
  QUIC substitution 바로 아래)
- `skills/packet-capture-rca/references/tshark-recipes.md` — L7 섹션(현재 164–193행)

**근거:** QUIC은 명시적 예외 처리를 받았으나(analysis-methodology.md:16–19) HTTP/2는 받지 못했다.
`tshark-recipes.md`의 L7 섹션 어디에도 `http2.streamid`가 등장하지 않는다(164–193행 확인).

**신뢰도/반증 신호:** Medium — 반증 신호: 실제 gRPC 장애 캡처에 `http2.streamid` 필터만으로 기존
버킷 어휘가 그대로 적용됨이 확인되면, 이 항목은 "새 어휘 신설"이 아니라 "레시피 한 줄 추가"로
축소된다. 아래 작업 지시는 이 가능성을 감안해 최소 변경으로 설계했다.

**구체적 작업 지시:**

1. `analysis-methodology.md`의 "QUIC/HTTP3 substitution" 문단 바로 아래에 병렬 문단을 추가한다:

```markdown
**HTTP/2·gRPC substitution:** 캡처의 `-z io,phs`에 `http2`가 나타나면(phase 3), 하나의 `tcp.stream`
안에 여러 논리적 요청이 `http2.streamid`로 멀티플렉싱되어 있을 수 있다. 이 경우 스파인 질문의
단위를 `tcp.stream`이 아니라 **`(tcp.stream, http2.streamid)` 쌍**으로 낮춰 적용한다 — "이 스트림이
실패했다"가 아니라 "이 tcp.stream의 이 http2.streamid 요청이 실패했다"로 명시한다. RST/FIN은 TCP
연결 전체에 영향을 주지만, gRPC 상태 코드(`grpc-status` 트레일러) 또는 HTTP/2 `RST_STREAM` 프레임은
개별 스트림 단위로 발생한다 — 어느 쪽이 관측됐는지에 따라 "커넥션 레벨 장애"(TCP RST/FIN)와
"스트림 레벨 장애"(HTTP/2 RST_STREAM)를 구분한다.
```

2. `tshark-recipes.md`의 L7 섹션 상단(HTTP 응답 읽기 레시피 앞)에 추가:

```markdown
# HTTP/2 논리 스트림 분리 — 하나의 tcp.stream 안 여러 요청을 구분
& $ts -r "<file>" -Y "http2 and tcp.stream==<S>" -T fields -e frame.number -e frame.time_relative `
  -e http2.streamid -e http2.type -e http2.flags -e http2.rst_stream.error_code

# gRPC 상태 코드(트레일러) — 앱 레벨 실패 여부
& $ts -r "<file>" -Y "http2.streamid==<ID> and http2.header.name==\"grpc-status\"" -T fields `
  -e frame.number -e http2.header.value
```

3. `analysis-methodology.md`의 버킷 목록(현재 21–37행) 끝에 각주 형태로 추가:

```markdown
**HTTP/2·gRPC 버킷 매핑:** 위 4개 버킷은 `http2.streamid` 단위로도 그대로 적용 가능하다 —
"body incomplete"는 `Content-Length`/gRPC 메시지 길이 프리픽스 대비 실제 전달 바이트로,
"teardown"은 TCP RST/FIN 대신 `RST_STREAM`/`grpc-status`(0이 아닌 값)로 대체해서 읽는다. 다만
**같은 tcp.stream 안에서 어떤 http2.streamid는 성공하고 다른 streamid는 실패하는 경우**, 교차검증
(§ Cross-validation)의 "3–4개 독립 실패 스트림" 요건은 tcp.stream이 아니라 **독립된 http2.streamid**
기준으로 채운다 — 같은 tcp.stream 안의 여러 streamid를 각각 하나로 세지 않는다(같은 커넥션 상태에
영향받을 수 있어 완전히 독립적이지 않기 때문— 이 점을 보고서에 명시한다).
```

**완료 판정 기준:** 위 세 군데 삽입이 모두 반영되어 있고, 실제 HTTP/2 캡처(테스트 파일)에 대해
`http2.streamid` 필터가 동작함을 `tshark -G fields | grep http2.streamid`로 확인했다(QUIC 가드가
tshark-recipes.md:161에서 쓰는 것과 동일한 버전 확인 패턴).

---

## A-3. 클럭 스큐 — 측정 한계 목록에 추가

**목표:** 다중 캡처 지점(클라이언트/LB프론트/LB백엔드/백엔드)을 타임스탬프로 인터리빙할 때
(SKILL.md:208), 각 지점의 시계가 어긋나 있을 수 있다는 위험을 명시적으로 점검하게 한다.

**대상 파일:** `skills/packet-capture-rca/references/analysis-methodology.md` — "측정 한계" 섹션
(현재 109–119행)

**근거:** 해당 섹션에 SYN 부재, snaplen 절단, 캡처 중간 시작, keep-alive 인과 혼선 4가지는
있으나 클럭 스큐는 없다. SKILL.md:208은 "두 프록시 절반을 타임스탬프로 인터리빙하라"고 지시하는데,
이는 정확히 클럭 스큐가 위험해지는 지점이다.

**신뢰도/반증 신호:** Medium — 반증 신호: 이 스킬이 실제로 다루는 캡처가 대부분 "같은 호스트/같은
NIC에서 딴 단일 캡처 파일 안의 양방향 트래픽"(예: LB 한 대에서 front/back 두 커넥션을 동시에
캡처)이라면, 클럭 스큐는 애초에 발생하지 않는다 — 이 경우 이 항목은 "다중 호스트 캡처를 병합하는
경우에 한해"로 조건부화해야 한다.

**구체적 작업 지시:**

1. `analysis-methodology.md`의 측정 한계 목록 끝에 항목 추가:

```markdown
- **다중 호스트에서 딴 캡처를 인터리빙하는 경우** → 클라이언트/LB/백엔드가 서로 다른 캡처 파일에서
  왔다면(같은 파일 안의 두 tcp.stream이 아니라, 물리적으로 다른 시스템에서 각각 캡처한 경우), 각
  시스템의 시계가 NTP 오차만큼 어긋나 있을 수 있다. 판정하려는 시간차(예: teardown과 응답의 순서)가
  이 오차보다 훨씬 커야 "먼저/나중"을 주장할 수 있다 — 오차 추정치를 모르면 밀리초 단위의 순서
  주장은 보류하고, "같은 파일 안에서 관측된 두 tcp.stream 간의 순서"만 확정적으로 다룬다. 단일
  캡처 파일(하나의 캡처 지점이 양방향을 모두 봄)인 경우 이 문제는 발생하지 않는다 — 캡처 구성을
  먼저 확인한다.
```

2. SKILL.md phase 3(오리엔테이션) 절(현재 151–176행)의 "map the capture endpoints onto the topology"
   문단에 한 문장 추가: `캡처가 여러 파일/여러 호스트에서 온 것이라면, 각 캡처의 시계 출처(NTP 동기화
   여부)를 이 시점에 확인해 둔다 — phase 5의 인터리빙 정확도에 영향을 준다.`

**완료 판정 기준:** 두 삽입 모두 반영, 그리고 다중 파일 캡처 사례가 생겼을 때 "캡처가 단일 파일인지
다중 호스트인지"를 phase 3 산출물에 기록하는 습관이 실제 세션 로그에서 확인됨(사후 검증 항목).

---

## A-4. 정상 기준선(known-good baseline) 확보 절차 명문화

**목표:** 재전송률 등 임계값이 "출발점일 뿐, 보편적 컷오프가 아니다"(tshark-recipes.md:129–133)라고
이미 명시되어 있는데, "그럼 무엇과 비교해야 하는가"의 절차가 없다. 이를 구체화한다.

**대상 파일:** `skills/packet-capture-rca/references/tshark-recipes.md` — "Performance metrics" 섹션
끝(현재 111–140행)

**근거:** analysis-methodology.md:67–69이 "같은 경로의 known-good 스트림과 비교하라"고 언급하지만,
"같은 경로"를 어떻게 확인하는지, 기준선 스트림을 어떻게 고르는지의 절차는 없다.

**신뢰도/반증 신호:** Low — 반증 신호: 이미 부분적으로 다뤄지고 있어(analysis-methodology.md:67–69)
격차가 좁다. 실제 분석 세션에서 기준선 선정이 매번 문제없이 이루어진다면 이 항목의 우선순위는
더 낮출 수 있다.

**구체적 작업 지시:**

`tshark-recipes.md` Performance metrics 섹션 끝에 추가:

```markdown
**기준선(baseline) 스트림 선정 기준.** "비정상"이라는 판정은 항상 상대적이다 — 아래 조건을 최대한
만족하는 스트림을 기준선으로 고른다(모두 만족하지 않아도 되나, 어긋난 조건은 보고서에 명시한다):
1. 같은 두 엔드포인트(같은 client↔backend 구간, 부록 C의 role→IP 매핑과 동일 쌍)
2. 같은 방향(업로드면 업로드끼리, 다운로드면 다운로드끼리)
3. 비슷한 페이로드 크기(±30% 이내를 권장 — 크기 차이가 크면 재전송률·RTT 자체가 다르게 나온다)
4. 가능하면 같은 시간대(네트워크 혼잡도의 일-중 변동을 배제)
기준선 스트림의 재전송률/RTT/zero-window를 실패 스트림과 나란히 표로 제시하고("성공 vs 실패
diff", SKILL.md:229–230과 동일한 원칙), 조건 중 어긋난 것이 있으면(예: 크기가 2배 차이) 그 사실을
비교 옆에 명시해 신뢰도를 낮춰 서술한다.
```

**완료 판정 기준:** 위 문단이 삽입되어 있고, "성공 vs 실패 diff" 관련 SKILL.md phase 6 절이 이
기준선 선정 절차를 참조하도록 상호 링크(문구 언급) 되어 있다.

---

## A-5. 트레이스ID/요청ID 상관 레시피

**목표:** 분산 트랜잭션에서 특정 TCP 스트림이 어느 논리적 요청에 해당하는지, 앱 레벨 신원(요청 ID,
trace ID)으로 보강할 수 있는 표준 절차를 제공한다. HTTP/2 멀티플렉싱(A-2)이나 로그 상관이 필요한
경우의 보완책이다.

**대상 파일:** `skills/packet-capture-rca/references/tshark-recipes.md` — L7 섹션에 신규 서브섹션 추가

**근거:** 현재 L7 섹션(164–193행)에 `X-Request-Id`, `traceparent` 등 상관 헤더를 다루는 레시피가 없다.
`endpoint-identification.md`는 `X-Forwarded-For`를 스트림 연결 증거로 쓰지만(49행), 요청 단위 상관은
다루지 않는다.

**신뢰도/반증 신호:** Medium — 반증 신호: 로그와 패킷의 타임스탬프 상관이 A-3의 클럭 스큐 문제를
그대로 물려받아 실효성이 낮다면, A-3 해결이 이 항목의 선결 조건이 된다 — 실행 순서(§A-0)에서 A-3을
먼저 배치한 이유다.

**구체적 작업 지시:**

`tshark-recipes.md` L7 섹션에 추가:

```markdown
## 요청ID/트레이스ID 상관 — 분산 트랜잭션 식별 보강

패킷만으로 "이 스트림이 어느 논리적 요청인가"가 모호할 때(HTTP/2 멀티플렉싱, 여러 트랜잭션이 섞인
keep-alive 스트림 등), 앱이 심어놓은 상관 헤더를 읽어 로그/트레이스와 연결한다.

```
# 흔한 상관 헤더 추출 (있는 만큼만 골라 사용)
& $ts -r "<file>" -Y "http.request or http2.type==1" -T fields -e frame.number -e tcp.stream `
  -e http.request.line -e http.x_request_id -e http.traceparent

# 헤더 이름이 표준 필드로 안 잡히면 원시 헤더 라인에서 grep
& $ts -r "<file>" -Y "frame.number==<N>" -O http -x | grep -iE "x-request-id|traceparent|x-b3-traceid"
```

이렇게 얻은 요청ID/트레이스ID를 애플리케이션 로그·APM(있다면)의 동일 값과 매칭하면, "이 캡처 스트림 =
이 로그 라인의 요청"이라는 독립적인 증거가 하나 더 생긴다 — 부록 A(재현용 명령)에 이 상관관계를
함께 남긴다. **주의:** 로그 타임스탬프와 패킷 타임스탬프를 순서 판정에 함께 쓸 경우 A-3(클럭 스큐)의
한계가 그대로 적용된다 — 로그 시스템의 시계가 캡처 시스템과 동기화되어 있는지 먼저 확인한다.
```

**완료 판정 기준:** 위 서브섹션 삽입, 그리고 이 레시피가 A-2(HTTP/2)의 "스트림 레벨 장애" 판정과
함께 실제로 쓰였을 때 요청ID로 성공/실패 스트림을 독립적으로 재확인할 수 있었는지 사후 기록.

---

## A-6. citec-kb 연동 지침에 `environment` 반영 — **Part B-1 선행 필수**

**목표:** citec-kb의 failure_bucket에 `environment`(csp/msp/onprem/hybrid) 파라미터가 추가되면
(Part B-1), packet-capture-rca도 이를 채워 "이 패턴은 온프레미스 전용/클라우드 메시 전용"을
구조적으로 기록하게 한다.

**대상 파일:** `skills/packet-capture-rca/references/citec-kb-integration.md`

**근거:** 현재 이 파일은 `environment`를 전혀 언급하지 않는다(전체 109행 확인). Part B-1에서 다루듯,
citec-kb의 `kb_similar_incident`에는 이미 `environment` 파라미터가 있지만(`mcp-server/server.py:716`)
failure_bucket 계열 5개 도구에는 없다 — 즉 지금 이 지침을 먼저 고쳐도 실제로 쓸 파라미터가 없다.
**반드시 Part B-1이 citec-kb 저장소에 배포된 뒤에** 아래를 진행한다.

**구체적 작업 지시(Part B-1 배포 확인 후 실행):**

1. `kb_tools_help()`를 호출해 `kb_register_failure_bucket`/`kb_match_failure_bucket`에 `environment`
   파라미터가 실제로 추가됐는지 먼저 확인한다(citec-kb-integration.md 7–10행이 이미 이 확인 습관을
   요구하고 있다 — 동일 패턴 재사용).
2. `citec-kb-integration.md`의 "phase 1" 및 "phase 7" 절(현재 43–48행, 60–71행)에 각각 추가:
   - phase 1: `환경 힌트가 issue 문서에 있으면(예: "쿠버네티스", "서비스 메시", "어플라이언스 LB",
     "온프레미스") kb_match_failure_bucket 호출에 environment=<csp|msp|onprem|hybrid>도 함께 채운다.`
   - phase 7: `kb_register_failure_bucket 호출 시 environment를 함께 채운다 — 이 패턴이 특정
     환경(예: mTLS 서비스 메시)에서만 성립하는지, 환경 무관인지를 구조적으로 남긴다. 확신이 없으면
     비워둔다(추측으로 채우지 않는다 — "근거 없는 등록 금지" 원칙과 동일).`
3. "좋은 discriminating_signals 작성 기준" 절(79–92행)에 추가: `environment별로 달라지는 판별
   신호는(예: "mTLS 메시에서는 관측되지 않음") counter_signals에 명시해 다른 환경으로의 오적용을
   막는다.`

**완료 판정 기준:** Part B-1이 citec-kb에 배포되고 `kb_tools_help()`로 확인된 뒤, 위 세 삽입이
반영되어 있다.

---

# Part B. citec-kb(wiki-mcp) 연동 개선 분석 — 소스코드 근거 기반

`~/dev/citec-kb`의 실제 소스(`apps/api/app/failure_buckets/*.py`, `apps/api/app/db/models.py`,
`apps/api/app/taxonomy.py`, `mcp-server/server.py`)와 설계 문서(`docs/superpowers/specs/2026-08-06-
failure-bucket-multi-plugin-design.md`, `docs/FAILURE_BUCKET_PLUGIN_GUIDE.md`,
`docs/PACKET_ANALYSIS_MCP_GUIDE.md`, `references/failure-bucket-domains.md`)를 직접 읽고 확인한
근거만 사용한다. 이전 분석(§7-2 (A))에서 "버킷이 구조화 데이터가 아닐 것"이라 추론했던 부분은
**이미 상당 부분 구현되어 있음을 확인했다** — 아래 §B-0에서 정정한다.

## B-0-a. wiki-mcp 실사용 데이터 확인 (2026-08-06, `kb_list_failure_buckets`/`kb_get_failure_bucket` 실측)

사용자 요청에 따라 citec-kb에 실제로 등록된 `failure_bucket`을 wiki-mcp로 직접 조회했다. 코드 추론이
아니라 **운영 중인 실 데이터**이므로 아래 항목들은 관측 등급으로 다룬다.

**현황:** `fb_domain="network"`에 4건이 등록되어 있다.

| bucket_name | protocol | confidence | support/counter | evidence_ref | created_by |
|---|---|---|---|---|---|
| 경로상 ECN 오처리 장비로 인한 양방향 실유실+RTT 팽창 | TCP | 0.5 | 0/0 | `legacy:pre-migration` | anonymous |
| WAN 구간 흐름-선택적 손실(레이트 폴리서/tail-drop) | TCP | 0.5 | 0/0 | `legacy:pre-migration` | anonymous |
| 클라이언트 VM 동시 프로세스 경합으로 인한 요청 페이싱 저하 | TCP | 0.5 | 0/0 | `legacy:pre-migration` | anonymous |
| LB 프론트 수신버퍼 포화 → chunked 업로드 본문 미완결 조기 종료 | **TCP/HTTP** | 0.667 | 1/0 | `legacy:pre-migration` | anonymous |

이 실측이 뒷받침하는 관측 사실 4가지:

1. **`evidence_ref`가 4건 전부 `"legacy:pre-migration"`이다** — 즉 지금 이 순간, citec-kb에 등록된
   네트워크 실패 버킷 중 단 한 건도 "사람이 열어 독립적으로 확인할 수 있는 구체적 포인터"
   (`capture:<file>#frame=<n>` 등, `FAILURE_BUCKET_PLUGIN_GUIDE.md:138–153`가 요구하는 형식)를 갖고
   있지 않다. 이는 multi-plugin 설계문서 §10이 예견한 마이그레이션 백필 값이 그대로 남아있는
   상태다 — §B-3(evidence_ref 형식 검증)의 신뢰도를 **Medium → High로 상향**한다. 반증 신호였던
   "팀의 의도적 정책 선택일 수 있다"는 이제 근거가 약하다 — 4건 전부가 검증 불가능한 placeholder로
   남아있다는 것은 정책의 결과가 아니라 **마이그레이션 이후 아무도 `evidence_ref`를 채우지
   않았다는 신호**에 가깝다.
2. **`created_by`가 4건 전부 `"anonymous"`다** — 어느 세션/플러그인이 등록했는지 추적 불가능하다.
   multi-plugin 설계문서 §7이 지적한 "`created_by`를 어떤 MCP 도구도 채우지 않는다"는 결함이 실제
   데이터에도 그대로 나타난다.
3. **`support=0, counter=0`(confidence=0.5 고정)인 버킷이 4건 중 3건이다** — 등록된 이후 단 한 번도
   `kb_refine_failure_bucket`으로 확인/반박된 적이 없다는 뜻이다. citec-kb 문서들이 반복 강조하는
   "재조회·재확인" 루프(`FAILURE_BUCKET_PLUGIN_GUIDE.md:35–39` 등)가 실제로는 아직 거의 돌지 않고
   있음을 보여준다 — 자가개선 루프가 이론상으로는 완비돼 있으나(§B-0), 실사용 빈도가 낮아 아직
   그 가치를 증명하지 못한 초기 단계다.
4. **4건 전부 온프레미스/레거시 인프라 사례다** — A10(하드웨어 L7 LB), WAN 회선, ESXi 하이퍼바이저,
   오브젝트 스토리지 VM 등이 언급되며, mTLS 서비스 메시·쿠버네티스·gRPC·HTTP/2를 다루는 사례는
   **0건**이다. 이는 §5(레거시/온프레미스 가치 평가)의 결론을 실제 등록 데이터로 뒷받침하는 동시에,
   Part A의 A-1(mTLS)·A-2(HTTP/2)가 다루는 영역이 지금 이 지식베이스에 **완전한 공백**임을
   확인시켜준다 — 가상의 우려가 아니라 실제로 커버리지가 0인 영역이다.

**부수 관측 (B-4 관련):** 4번째 버킷의 `protocol` 값이 `"TCP/HTTP"`로, 슬래시로 두 프로토콜을 이어
붙인 자유 텍스트다. §B-4에서 "단일 문자열 컬럼이라 다중값을 못 담는다"고 코드로만 추론했던 것이,
실제로 그 제약을 회피하려는 사용 패턴("TCP/HTTP"라는 합성값)으로 이미 나타나고 있다는 실증이다.

**긍정적 확인 (Part A의 전제 검증):** 4건의 `root_cause`/`discriminating_signals`를 읽어보면
observed/inferred 분리, 신뢰도, kill signal이 이미 매우 정교하게 적용되어 있다(예: 4번째 버킷의
"LB 내부 abort 트리거는... 추론 영역이다(확신 Medium; kill signal: SYN 포함 캡처에서...)"). 이는
Part A가 개선하려는 스파인 질문·버킷팅 규율이 **실제로 고품질 산출물을 내고 있다**는 긍정적 증거이며,
§7-1(강점 재확인, 이전 문서)의 판단을 실 데이터로 뒷받침한다.

## B-0. 이전 추론의 정정

이전 문서(§7-2 (A))는 "실패 버킷을 `{bucket_id, discriminating_signals[], counter_signals[],
protocol_family, environment_tag}` 구조화 스키마로 승격"을 제안하며 신뢰도 Medium을 부여했다.
실제 코드 확인 결과:

- `discriminating_signals[]`, `counter_signals[]`는 **이미 구조화되어 있다** — `FailureBucket` 테이블의
  `ARRAY(String)` 컬럼(`db/models.py:373–378`), `evidence_ref`/`fb_domain`/`protocol`도 모두 독립
  컬럼(`db/models.py:369–371`).
- `confidence`는 Laplace 스무딩으로 자동 재계산되고(`draft.py:10–14`,
  `support_count`/`counter_count` 누적), 신호 매칭에는 이미 K=4 상한 캡이 적용되어 있다
  (`match.py:13, 48` — multi-plugin 설계문서 §3이 제안한 수정이 이미 반영된 상태).
- **다만 `environment_tag`는 실제로 없다** — 이 부분만 이전 추론이 맞았다. 아래 §B-1에서 이를
  코드 근거로 구체화한다.

**결론:** "버킷을 구조화 데이터로 승격하라"는 제안은 이미 완료된 항목이므로 폐기하고, 남은 격차인
`environment` 축 부재에 분석을 집중한다.

## B-1. `environment` 파셋이 failure_bucket에 배선되지 않음 — 가장 큰 개선 기회

**관측 (코드 근거):**

| 사실 | 근거 |
|---|---|
| `Document.environment`(csp/msp/onprem/hybrid) 컬럼이 이미 존재한다 | `db/models.py:93` |
| `infer_environment()`가 title/body 정규식으로 environment를 자동 추론한다 | `taxonomy.py:9–13, 45–50` |
| `enrich_draft_fields()`는 **모든 source_type에 대해 예외 없이** `infer_environment()`를 호출한다 (failure_bucket 포함) | `taxonomy.py:83–102` |
| `kb_similar_incident` MCP 도구에는 `environment` 파라미터가 **명시적으로 존재**한다 | `mcp-server/server.py:714–721` |
| 반면 `kb_register_failure_bucket`/`kb_match_failure_bucket`/`kb_list_failure_buckets`/`kb_get_failure_bucket`/`kb_refine_failure_bucket` — failure_bucket 계열 5개 도구 **전체**에 `environment` 파라미터가 없다 | `mcp-server/server.py:1020–1221` 전수 확인 |
| `_ENV_RULES`(정규식 기반 자동 추론) 3개 규칙 중 어느 것도 mTLS/서비스 메시/사이드카/쿠버네티스/gRPC 키워드를 다루지 않는다 | `taxonomy.py:9–13` |
| `_ENV_RULES`에는 "hybrid" 값을 만들어내는 규칙이 아예 없다 (컬럼 코멘트는 csp\|msp\|onprem\|hybrid 4값을 명시하는데) | `taxonomy.py:9–13` vs `db/models.py:93` |

**왜 중요한가:** 이 세션 전체의 핵심 질문 — "이 실패 패턴이 클라우드에도 적용되는가, 온프레미스
전용인가" — 에 대한 답을 구조적으로 남길 자리가 지금 `failure_bucket`에 없다. 현재로선 이 정보가
`bucket_body_md()`가 만드는 자유 텍스트(`draft.py:17–46`) 안에 `_ENV_RULES`가 우연히 매치되면
간접적으로만 잡힌다 — 그리고 그 정규식조차 "서비스 메시"류 키워드를 다루지 않으므로, packet-capture-
rca가 mTLS 메시 사례를 등록해도 `environment`가 거의 항상 `None`으로 남을 것이다.

**신뢰도:** High — **반증 신호:** `environment` 파라미터가 API 레벨의 다른 경로(예: metadata
passthrough, `created_by` 필드 오버로딩)로 이미 전달 가능함이 발견되면 이 "부재" 판정은 무효화된다.
그러나 `mcp-server/server.py:1020–1221`(failure_bucket 5개 도구 정의 전체)을 직접 읽어 확인했고
그런 경로는 없었다 — 이 반증 가능성은 낮다.

**제안 변경 (citec-kb 저장소, multi-plugin 설계문서와 동일한 패턴을 따름):**

1. **스키마:** `failure_buckets.environment` 컬럼 추가 — `String(16)`, nullable, 인덱스 추가
   (`fb_domain`/`protocol`과 같은 패턴, `db/models.py:357–362`의 `__table_args__` 참고). Alembic
   마이그레이션 1개, 기존 행은 NULL 백필(강제 추론하지 않는다 — "근거 없는 값 채우기 금지" 원칙과
   일치, `FAILURE_BUCKET_PLUGIN_GUIDE.md:40–42`의 §4 원칙을 그대로 적용).

2. **서비스 레이어:** `create_bucket()`(`service.py:101–159`)과 `match_buckets()`
   (`service.py:232–249`)에 `environment: Optional[str] = None` 파라미터 추가, `match_buckets()`의
   SQL where절에 `fb_domain`/`protocol`과 동일하게 `FailureBucket.environment == environment` 필터
   추가(§9의 "SQL 필터를 Python 랭킹보다 먼저" 원칙 재사용).

3. **매칭 스코어러:** `environment`는 하드 필터(SQL where)로만 쓰고 스코어 계산(`match.py`)에는
   개입시키지 않는다 — 사용자가 `environment`를 지정하면 다른 환경의 버킷은 애초에 후보에 오르지
   않게 하는 편이, 스코어 가중치로 넣어 애매하게 섞는 것보다 "관측 vs 추론"의 정신에 맞다(엉뚱한
   환경의 패턴을 낮은 점수로라도 추천하지 않는다).

4. **`_ENV_RULES` 확장(보조 경로로 유지):** 아래 규칙을 추가해 자유 텍스트 추론의 재현율을 높인다 —
   단, 이는 구조화 파라미터(위 1–2)의 **보조 수단**이지 주 경로가 아니어야 한다:
   ```python
   (re.compile(r"서비스\s*메시|service\s*mesh|Istio|Linkerd|사이드카|sidecar|mTLS", re.I), "hybrid"),
   (re.compile(r"쿠버네티스|Kubernetes|\bk8s\b|파드|pod\s+IP|ClusterIP", re.I), "hybrid"),
   ```
   `hybrid`로 매핑하는 이유: 서비스 메시/k8s는 csp에서도 onprem(OpenShift 등)에서도 쓰이므로 그
   자체로 csp/onprem을 단정할 근거가 아니다 — 대신 "네트워크 토폴로지가 복잡하다"는 신호로서
   `hybrid`에 가장 가깝다. (이 매핑 자체가 하나의 설계 판단이므로, citec-kb 팀과 협의가 필요하다 —
   `references/failure-bucket-domains.md`의 "새 도메인 추가 절차"와 유사하게 리뷰를 거친다.)

5. **MCP 도구 시그니처 5개 갱신:**
   - `kb_register_failure_bucket(..., environment: str = "")` → body에 `environment.strip() or None`
   - `kb_match_failure_bucket(..., environment: str = "")` → body에 조건부 포함(`fb_domain`/`protocol`과
     동일 패턴, `server.py:1134–1137` 참고)
   - `kb_list_failure_buckets(..., environment: str = "")` → params에 조건부 포함
   - `kb_get_failure_bucket`/`kb_refine_failure_bucket`은 `bucket_id`로 동작하므로 변경 불필요
     (multi-plugin 설계문서 §8의 동일 결론을 재사용)

6. **문서 갱신:** `docs/PACKET_ANALYSIS_MCP_GUIDE.md` §1(도구 표)과 §4(등록 예시)에 `environment`
   추가, `references/failure-bucket-domains.md`에 "environment는 fb_domain과 직교하는 별도 축"이라는
   설명 한 문단 추가(현재 이 파일은 fb_domain만 다룬다).

**완료 판정 기준:** `kb_tools_help()` 응답에 5개 도구 모두 `environment` 파라미터가 나타나고,
`kb_match_failure_bucket(environment="onprem")` 호출이 실제로 다른 환경의 버킷을 후보에서 제외함을
1건의 등록(onprem 1건, cloud 1건)으로 스모크 테스트한다(`mcp-server/test_smoke.py` 갱신, multi-plugin
설계문서 §10의 관례 재사용).

## B-2. 매칭 알고리즘이 순수 어휘 중첩 — 의미 기반 보강 없음

**관측 (코드 근거):** `_signal_hit()`(`match.py:20–27`)는 정규식 토큰화(`_TOKEN_RE`, 2자 이상
영숫자/한글) 후 관찰된 토큰 집합과의 교집합 비율만 계산한다. `confidence` 산식(`match.py:47–49`)도
`signal_ratio*0.6 + bucket.confidence*0.4`로, 임베딩/의미 유사도는 전혀 쓰이지 않는다. 반면
플랫폼에는 이미 `Embedding` 테이블(HNSW 인덱스, `db/models.py:168–196`)과 `multilingual-e5-base`
임베딩 모델이 있고, `_index_bucket()`(`service.py:60–95`)은 버킷을 등록/정제할 때마다 이미 이
파이프라인을 태워 임베딩까지 만들어 둔다(`bucket_draft()` → `upsert_document_from_draft()` →
`embed_pending_chunks()`).

**왜 중요한가:** "RST 직전 idle ≥ 60초"와 "60초 이상 유휴 후 강제 종료"는 의미상 동일하지만 토큰
교집합은 부분적으로만 걸린다(공통 토큰: "60", "idle"/"유휴"는 다른 언어라 아예 안 걸림). 플러그인이
늘어나고(`pacemaker-tools`, `windows-tools`) 작성자가 늘어날수록 신호 문구의 자연어 변주가
커진다 — multi-plugin 설계문서 §3이 지적한 "형평성 문제"(신호를 몇 개 쓰는 습관이냐에 따라 순위가
좌우됨)와 같은 계열의, 아직 다뤄지지 않은 리스크다.

**신뢰도:** Medium — **반증 신호:** 이 스킬이 다루는 신호가 대부분 정형화된 tshark 필드명·수치
조합(`tcp.analysis.zero_window`, "idle ≥ 60초" 같은 임계값 표현)이라 자연어 변주가 실제로는 드물다면,
이 개선의 실사용 가치는 낮다 — multi-plugin 설계문서 §11이 "실사용 데이터가 쌓여 문제가 되면
재검토"라는 태도를 이미 채택한 것과 같은 방식으로, **먼저 실측(matched_signals 대비 contradicted
없이도 사람이 봤을 때 명백히 같은 패턴인데 놓친 사례)을 수집한 뒤 착수하는 편이 안전**하다.

**제안 변경:** `match_bucket()`에 임베딩 코사인 유사도를 **토큰 매칭이 실패했을 때만 보는 폴백**으로
추가한다 — 기존 인프라(버킷은 이미 임베딩되어 있음)를 재사용하므로 신규 구축 비용이 낮다:

```python
# match.py 개념 스케치 — 실제 구현 시 임베딩 조회 경로(app.embed)를 확인해 배선
def _signal_hit(observed_tokens, observed_embeds, signal, signal_embed, *, sem_threshold=0.82):
    if _lexical_hit(observed_tokens, signal):   # 기존 로직
        return True
    if signal_embed is not None:
        return max(cosine(e, signal_embed) for e in observed_embeds) >= sem_threshold
    return False
```

이 변경은 **의미 매칭으로 새로 걸린 신호는 응답에 별도 표시**(`matched_signals_semantic` 같은 필드)해,
호출자가 "정확히 문구가 일치했다"와 "의미적으로 유사하다고 판단됐다"를 구분할 수 있게 한다 — 이는
packet-capture-rca 자신의 observed/inferred 분리 원칙과 정확히 같은 이유다: 어느 근거로 매칭됐는지
숨기지 않는다.

**우선순위:** Part B 안에서는 B-1보다 낮다 — B-1은 이 세션이 요청한 "클라우드 vs 온프레미스" 질문에
직접 답하는 반면, B-2는 일반적인 매칭 품질 개선으로 착수 전 실측이 필요하다.

## B-3. `evidence_ref` 형식이 소프트 컨벤션 — API가 형식 자체는 검증하지 않음

**관측 (코드 근거):** multi-plugin 설계문서 §11이 "DB-level enum/정규식 제약은 범위 밖"이라 명시적으로
선언했고, 실제로 `routers/failure_buckets.py:57–58`은 `evidence_ref.strip()`이 비어 있지 않은지만
검사한다. `kb_register_failure_bucket`(`mcp-server/server.py:1048–1049`)도 동일하게 비어있음만 검사—
`capture:<file>#frame=<n>` 형식 자체를 검증하는 코드는 없다.

**왜 중요한가:** 이 형식 규칙은 문서(`FAILURE_BUCKET_PLUGIN_GUIDE.md:138–153`,
`PACKET_ANALYSIS_MCP_GUIDE.md:121, 128–129`) 여러 곳에 반복해서 강조되어 있는데도 기계적으로
강제되지 않는다 — "확정된 내용" 방침의 유일한 게이트라고 문서 스스로 말하면서도(§0.24) 실제로는
사람/에이전트의 준수 의지에 의존한다.

**신뢰도:** High(§B-0-a 실측으로 상향) — **반증 신호:** 원래는 "팀의 의도적 정책 선택일 수 있다"였으나,
§B-0-a에서 실제 등록된 4건 전부가 `evidence_ref="legacy:pre-migration"`(마이그레이션 placeholder)로
남아있음을 확인했다 — 정책적으로 자유 서술을 허용한 결과가 아니라, 백필 이후 아무도 채워 넣지 않은
상태로 방치된 결과에 가깝다. 유효한 반증 신호는 이제 좁다: citec-kb 개발팀이 "이 4건은 의도적으로
레거시 표시를 유지하기로 결정했다"고 명시적으로 확인하는 경우뿐이다.

**제안 변경(경량, §5의 `fb_domain_warning`과 동일한 패턴 — 차단이 아닌 경고):**

```python
# create_bucket() 내부, service.py:122 앞에 추가할 수 있는 형태
_EVIDENCE_REF_PREFIXES = ("capture:", "confluence:", "CITECTS-", "evtx:", "log:", "swim:")
if not evidence_ref.strip().startswith(_EVIDENCE_REF_PREFIXES):
    # 차단하지 않고 result에 경고만 추가 — fb_domain_warning과 동일한 관용 패턴
    result["evidence_ref_warning"] = (
        f"evidence_ref='{evidence_ref}'가 알려진 포인터 형식({', '.join(_EVIDENCE_REF_PREFIXES)})과 "
        "다릅니다. 자유 서술이 아닌지 확인해 주세요."
    )
```

**완료 판정 기준(만약 citec-kb 팀이 채택한다면):** 형식에 맞지 않는 `evidence_ref`로 등록 시
`evidence_ref_warning`이 응답에 포함되는 것을 스모크 테스트로 확인.

## B-4. `protocol` 단일 문자열 — HTTP/2·gRPC·QUIC 값 확장은 코드 변경 불필요

**관측 (코드 근거):** `protocol: Mapped[Optional[str]] = mapped_column(String(32))`
(`db/models.py:370`) — 자유 문자열이며 DB-level 제약이 없다. 즉 `"HTTP2"`, `"GRPC"`, `"QUIC"`,
`"MTLS"` 같은 새 값을 넣는 데 **citec-kb 쪽 코드 변경은 전혀 필요 없다** — packet-capture-rca가
그 값들을 실제로 채우기만 하면 된다.

**결론:** 이 항목은 citec-kb 개선이 아니라 packet-capture-rca 쪽 관례 문제다 — Part A-2(HTTP/2 확장
작업) 안에 이미 흡수되어 있으므로 별도 작업으로 분리하지 않는다. (반증 신호를 걸 필요가 없을 만큼
근거가 직접적이다 — 신뢰도 High.)

## B-5. Part B 실행 순서 권고

1. **B-1(environment 배선)을 먼저 진행한다** — 이번 세션이 요청한 질문에 가장 직접적으로 답하고,
   Part A-6이 이 작업의 완료를 전제로 하기 때문이다.
2. **B-3(evidence_ref 경고)을 B-1과 동일한 우선순위로 즉시 병행한다** — §B-0-a 실측 이후 이 항목은
   더 이상 이론적 리스크가 아니라 **지금 운영 중인 4건 전부가 검증 불가능한 상태**라는 실재하는
   문제다. 경고 배선과 별도로, 기존 4건에 대해 실제 근거 프레임을 소급 확인해 `evidence_ref`를
   갱신하는 정리 작업(원 분석 세션 로그나 원본 캡처가 남아있다면)도 함께 고려할 가치가 있다 — 단
   이는 citec-kb 데이터 정비 작업이라 이 문서의 범위(코드/문서 개선)를 넘어서므로 제안만 남긴다.
3. B-2(의미 매칭)는 **먼저 실측 데이터를 모은 뒤** 착수한다 — multi-plugin 설계문서 §11의 태도를
   그대로 따른 것으로, 이 문서가 새로 발명한 원칙이 아니다.
4. B-4는 별도 작업이 아니다(A-2에 흡수).

---

## 부록. 이 문서 자체의 측정 한계

- Part B의 모든 코드 인용은 `~/dev/citec-kb`의 현재 워킹트리 상태를 직접 읽어 확인한 것이며, 이
  저장소가 실제 운영 배포와 동일한 리비전인지는 확인하지 않았다 — multi-plugin 설계문서 자체도
  "file:line 앵커는 실제로 열어 재확인하라"고 스스로 경고한다(해당 문서 10–12행); 이 문서의 인용도
  동일한 재확인이 필요하다.
- B-2(의미 매칭)의 필요성은 실제 매칭 실패 사례 데이터 없이 코드 구조만으로 추론했다 — §B-2의
  반증 신호에 명시한 대로, 착수 전 실측이 선행되어야 한다.
- Part A의 각 작업 지시에 포함된 tshark 명령·필드명(`http2.streamid`, `grpc-status` 등)은 필드
  존재 여부를 실제 캡처로 검증하지 않았다 — tshark-recipes.md 기존 관례(QUIC 가드, 161행)대로
  `tshark -G fields | grep <필드>`로 사전 확인 후 반영해야 한다.
