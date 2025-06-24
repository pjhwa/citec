Nuri SKE K8s 클러스터에서 OS상의 firewalld 데몬이 enable 되었을 때, calico plugin 관련 통신이슈가 확인되어

K8s VM에 대해 firewalld 를 disable 로 예외적용 가능한지 검토 요청드립니다.



현상확인(qa2에서 테스트)

1. firewalld disable 상태

2. 내부 pod -> 외부 198.18.1.136(internal web proxy) 통신 정상 

3. firewalld enable

4. 내부 pod -> 외부 198.18.1.136(internal web proxy) 통신 timeout

5. calico pod 재구동

6. 내부 pod -> 외부 198.18.1.136(internal web proxy) 통신 정상

7. firewalld restart

8. 내부 pod -> 외부 198.18.1.136(internal web proxy) 통신 timeout

9. calico pod 재구동

10. 내부 pod -> 외부 198.18.1.136(internal web proxy) 통신 정상

■ 조건

- K8S 사용 Node (VM) 중 calico pod으로 통신이 되는 장비

- OS Reboot 이 발생 되거나 firewalld가 enable(restart) 되는 상황에서 통신 불가 상황 발생

- 전체 OS의 보안 기본은 firewalld를 enable 하도록 함 (SSI 보안 기준)


아래는 calico 공식 문서 및 oracle cloud calico 설치 관련 문서에 적힌 firewalld disable 관련 requirement 입니다.

https://docs.tigera.io/calico/latest/getting-started/kubernetes/requirements

If your Linux distribution comes with installed Firewalld or another iptables manager it should be disabled. These may interfere with rules added by Calico and result in unexpected behavior.

https://docs.oracle.com/en/operating-systems/olcne/1.9/calico/install.html

Disable the firewalld service on each Kubernetes node:

■ workaround 

- firewalld enable 로 통신 안될 경우 calico pod 재구동 

 

 

위 이슈를 조치하기 위해 firewalld를 disable 한다면 OS단에서 접근제어하는 방법이 없기때문에 보안상 문제가 되는 부분이 있습니다. 

물론 앞단의 FW 장비나 SG에서 제어 하기도하지만 OS 자체에서의 제어 방법이 없게 되는 것입니다. 

그래서 어떠한 조건이나 설정을 통해 firewalld를 restart 하여도 K8S 간의 통신이 되도록 할 수 있지 않을까 아이디어를 문의 드립니다. 

저도 계속 찾아보고 있으나 CI-TEC분들께서 더 나은 방법이 있으실지 고견을 여쭤봅니다.
