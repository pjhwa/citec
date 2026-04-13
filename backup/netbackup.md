NetBackup 매뉴얼에서 Linux 환경(모든 플랫폼 포함)의 변경 데이터 추적(CBT 역할) 및 증분 백업 지원을 뒷받침하는 원문과 한국어 번역, 그리고 페이지 번호는 다음과 같습니다.

**1. 모든 플랫폼에서의 증분 백업 지원 명시**
Linux를 포함해 NetBackup이 지원하는 모든 플랫폼과 파일 시스템에서 증분 백업이 가능하다는 것을 명시한 문구입니다.

*   **원문:** 
    *   "Supports the full backups and incremental backups."
    *   "Supports all platforms, file systems, and logical volumes that NetBackup supports."
*   **한국어 번역:** 
    *   "전체 백업 및 증분 백업을 지원합니다."
    *   "NetBackup이 지원하는 모든 플랫폼, 파일 시스템 및 논리 볼륨을 지원합니다." (Linux 포함)
*   **페이지 번호:** 748 페이지 (Accelerator notes and requirements)

**2. 변경 블록 추적(CBT) 작동 원리 (트랙 로그 활용)**
Windows의 체인지 저널을 사용할 수 없는 Linux 등의 환경에서, 자체적인 '트랙 로그(Track log)'를 파일 시스템과 비교하여 변경된 데이터(CBT 역할)를 식별하고 증분 백업을 수행하는 원리를 설명한 문구입니다.

*   **원문:** 
    *   "At the next backup, NetBackup identifies data that has changed since the previous backup. To do so, it compares information from the track log against information from the file system for each file."
*   **한국어 번역:** 
    *   "다음 백업 시 NetBackup은 이전 백업 이후 변경된 데이터를 식별합니다. 이를 위해 각 파일에 대해 트랙 로그의 정보와 파일 시스템의 정보를 비교합니다."
*   **페이지 번호:** 744 페이지 (How the NetBackup Accelerator works)
