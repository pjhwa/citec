● 두 번째 서버에 복사할 것은 딱 하나입니다.

  # 현재 서버에서 다음 서버로
  scp ~/minimize-bundle-after-test-nn-20260423.tar.gz  <다음서버>:~/

  그리고 다음 서버에서:

  cd ~
  tar xzf minimize-bundle-after-test-nn-20260423.tar.gz
  # → ~/minimize-test-bundle/ 로 풀림

  추가로 필요한 것:

  # 다음 노드의 apt_list.txt 를 번들 내에 교체
  cp <다음노드>_apt_list.txt ~/minimize-test-bundle/apt-lists/

  그러면 ~/minimize-test-bundle/ 안에 CLAUDE.md·핸드오프 문서를 제외한 모든 산출물이 들어 있습니다.

  ---
  CLAUDE.md / claude-code-handoff.md 는 별도로 복사해야 합니다. 이 두 파일은 번들에 포함되지 않습니다.

  scp ~/CLAUDE.md ~/claude-code-handoff.md  <다음서버>:~/

  ---
  두 번째 서버에서 세션 시작 전 체크리스트:

  [ ] minimize-bundle-after-test-nn-*.tar.gz 복사 및 압축 해제 완료
  [ ] ~/minimize-test-bundle/ 존재 확인
  [ ] 다음 노드의 apt_list.txt → ~/minimize-test-bundle/apt-lists/ 에 배치
  [ ] CLAUDE.md 복사
  [ ] claude-code-handoff.md 복사
  [ ] Claude Code 세션 시작 → "삭제 테스트 시작" 입력

  작업 디렉토리를 ~/minimize-test-bundle/ 로 이동한 상태에서 시작하면 Phase A의 번들 자동 감지가 바로 됩니다.
