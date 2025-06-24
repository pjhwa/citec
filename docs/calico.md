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

