vLLM (GPT-oss 20B) 모델 8개 GPU에 각각 띄운 후 병렬 inference

Pytorch lightning DDP 사용해서 8B 모델 full fine-tuning SFT 학습

verl 로 8B 모델 RL 학습 (이 부분에서 학습 시작할 때 서버 오류 발생, 원래 GPU 2번에서도 잘 돌아갔었던 학습 코드였음.)

내부적으로 FSDP, vLLM 사용

Jan  4 04:29:21 usr002-gpumngc-01 systemd[1]: docker-d1b496c8d966d65fb8784fa50c1122aec635287df466b38f0445425f9145006a.scope: Deactivated successfully.
Jan  4 04:29:21 usr002-gpumngc-01 systemd[1]: docker-d1b496c8d966d65fb8784fa50c1122aec635287df466b38f0445425f9145006a.scope: Consumed 2h 27min 41.592s CPU time.
Jan  4 04:29:21 usr002-gpumngc-01 dockerd[3468]: time="2026-01-04T04:29:21.333484443+09:00" level=info msg="ignoring event" container=d1b496c8d966d65fb8784fa50c1122aec635287df466b38f0445425f9145006a module=libcontainerd namespace=moby topic=/tasks/delete type="*events.TaskDelete"
Jan  4 04:29:21 usr002-gpumngc-01 containerd[2767]: time="2026-01-04T04:29:21.333993942+09:00" level=info msg="shim disconnected" id=d1b496c8d966d65fb8784fa50c1122aec635287df466b38f0445425f9145006a namespace=moby
Jan  4 04:29:21 usr002-gpumngc-01 containerd[2767]: time="2026-01-04T04:29:21.334034018+09:00" level=warning msg="cleaning up after shim disconnected" id=d1b496c8d966d65fb8784fa50c1122aec635287df466b38f0445425f9145006a namespace=moby
Jan  4 04:29:21 usr002-gpumngc-01 containerd[2767]: time="2026-01-04T04:29:21.334041049+09:00" level=info msg="cleaning up dead shim" namespace=moby
Jan  4 04:29:21 usr002-gpumngc-01 systemd-networkd[2117]: vethe65d677: Lost carrier
Jan  4 04:29:21 usr002-gpumngc-01 kernel: [306330.269085] docker0: port 1(vethe65d677) entered disabled state
Jan  4 04:29:21 usr002-gpumngc-01 kernel: [306330.269133] veth1cb3172: renamed from eth0
Jan  4 04:29:21 usr002-gpumngc-01 networkd-dispatcher[2139]: WARNING:Unknown index 48 seen, reloading interface list
Jan  4 04:29:21 usr002-gpumngc-01 systemd-udevd[1708831]: Using default interface naming scheme 'v249'.
Jan  4 04:29:21 usr002-gpumngc-01 systemd-networkd[2117]: vethe65d677: Link DOWN
Jan  4 04:29:21 usr002-gpumngc-01 kernel: [306330.316025] docker0: port 1(vethe65d677) entered disabled state
Jan  4 04:29:21 usr002-gpumngc-01 kernel: [306330.316561] device vethe65d677 left promiscuous mode
Jan  4 04:29:21 usr002-gpumngc-01 kernel: [306330.316564] docker0: port 1(vethe65d677) entered disabled state
Jan  4 04:29:21 usr002-gpumngc-01 networkd-dispatcher[2139]: ERROR:Unknown interface index 48 seen even after reload
Jan  4 04:29:21 usr002-gpumngc-01 networkctl[1708844]: Interface "vethe65d677" not found.
Jan  4 04:29:21 usr002-gpumngc-01 systemd[1]: networkd-dispatcher.service: Got notification message from PID 1708844, but reception only permitted for main PID 2139
Jan  4 04:29:21 usr002-gpumngc-01 networkd-dispatcher[2139]: ERROR:Failed to get interface "vethe65d677" status: Command '['/usr/bin/networkctl', 'status', '--no-pager', '--no-legend', '--', 'vethe65d677']' returned non-zero exit status 1.
Jan  4 04:29:21 usr002-gpumngc-01 networkd-dispatcher[2139]: WARNING:Unknown index 48 seen, reloading interface list
Jan  4 04:29:21 usr002-gpumngc-01 networkd-dispatcher[2139]: ERROR:Unknown interface index 48 seen even after reload
Jan  4 04:29:21 usr002-gpumngc-01 systemd[1]: run-docker-netns-19afdb2bd059.mount: Deactivated successfully.
Jan  4 04:29:21 usr002-gpumngc-01 systemd[1]: var-lib-docker-overlay2-a79b5a5868b692436a4bef445601ec6e9f5bc15e8f42515f842eb50789bb18a7-merged.mount: Deactivated successfully.
