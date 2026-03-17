**핵심 사실 (출처 번호와 함께)**  
1. 이 로그(`vsansystem: info vsansystem[1234] [vSAN@6876 sub=VsanMgmtServer] Panic at fork: DISABLED`)는 **vSAN Management Daemon(vsanmgmtd)**의 **VsanMgmtServer** 서브시스템에서 출력되는 **info 레벨** 메시지이며, 실제 호스트 크래시(panic)가 아닙니다.  
2. vSAN을 사용하지 않는 컴퓨트 노드에서도 이 로그가 반복 출력되는 이유는 **ESXi에 vSAN 컴포넌트(vSAN VIB와 vsanmgmtd)가 기본 탑재**되어 있기 때문입니다(6.5 이후 모든 ESXi 호스트 표준). 클러스터에서 vSAN을 활성화하지 않아도 management plane은 항상 실행됩니다.  
3. “Panic at fork: DISABLED”는 daemon 내부에서 **fork() 호출 시 panic(크래시) 기능을 의도적으로 비활성화**한 상태를 알리는 debug/info 로그로, 멀티스레드 환경에서의 안정성/보안을 위한 코드입니다(실제 오류 아님).  
4. 유사 사례: Broadcom KB 418551(비-vSAN 호스트에서 vsanmgmtd 관련 이벤트 발생 시 “한 번 발생하면 무시 가능”) 및 커뮤니티 스레드(VSANMGMTSVC/vsansystem.log 반복 로그, [vSAN@6876] 태그 동일).  

**맥락 요약**  
vSphere/ESXi 설계상 vSAN 기능은 “언제든 쉽게 켜기” 위해 호스트에 항상 포함되어 있습니다. 따라서 vSAN 미사용 환경에서도 vsanmgmtd 데몬이 백그라운드에서 동작하며, vsansystem.log에 info 레벨 메시지를 남깁니다. 이는 로그 스팸(monitoring 노이즈)으로 느껴질 수 있지만, 호스트 성능·기능·안정성에는 전혀 영향을 주지 않습니다. 커뮤니티와 KB 모두 “vSAN 안 쓰면 무시해도 된다”는 공통 의견입니다.

**불확실성 및 한계점**  
- 정확한 “Panic at fork: DISABLED” 문자열의 내부 의미는 **공개 KB나 공식 문서에 전혀 등장하지 않습니다** (내부 디버그 로그로 추정). **확신할 수 없다** — 70~80% 확률로 완전 무해한 설정 알림이지만, 특정 버전/ESXi 빌드에서 과도한 logging 버그일 가능성은 배제 불가.  
- 지속 출력 시 vsanmgmtd가 비정상적으로 동작할 수 있음(드물지만 core dump 발생 가능).  
- 추가 조사가 필요한 부분: 정확한 ESXi 버전(7.x? 8.x?), 로그 전체 컨텍스트(/var/run/log/vsansystem.log), /var/core에 vsanmgmtd core 파일 존재 여부.

**결론**  
현재까지 알려진 바에 따르면, 이 메시지는 **vSAN 미사용 환경에서 정상적인 info 로그**이며 무시해도 안전합니다.  
- **즉시 조치 추천**:  
  1. 로그 레벨 낮추기 → 호스트 Advanced Setting에서 `Syslog.loggers.vsansystem.level`을 `warning` 또는 `error`로 변경 (로그 스팸 방지).  
  2. 데몬 재시작 테스트 → SSH로 `/etc/init.d/vsanmgmtd restart` 실행 후 로그 재확인.  
  3. 여전히 반복되면 Broadcom 지원 티켓 제출 (KB 418551 참조).  
vSAN을 계획적으로 사용하지 않는다면 이 로그를 신경 쓰지 않아도 됩니다. 추가 로그 샘플이나 ESXi 버전 알려주시면 더 정확히 확인해 드릴 수 있습니다!
