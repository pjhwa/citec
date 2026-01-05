vLLM (GPT-oss 20B) 모델 8개 GPU에 각각 띄운 후 병렬 inference

Pytorch lightning DDP 사용해서 8B 모델 full fine-tuning SFT 학습

verl 로 8B 모델 RL 학습 (이 부분에서 학습 시작할 때 서버 오류 발생, 원래 GPU 2번에서도 잘 돌아갔었던 학습 코드였음.)

내부적으로 FSDP, vLLM 사용

 NVIDIA-SMI 535.183.06
 Driver Version: 535.183.06
 CUDA Version: 12.2

Jan  5 12:00:42 usr002-gpumngc-01 kernel: [    0.000000] Linux version 5.15.0-105-generic (buildd@lcy02-amd64-007) (gcc (Ubuntu 11.4.0-1ubuntu1~22.04) 11.4.0, GNU ld (GNU Binutils for Ubuntu) 2.38) #115-Ubuntu SMP Mon Apr 15 09:52:04 UTC 2024 (Ubuntu 5.15.0-105.115-generic 5.15.148)

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

Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.088504] general protection fault, probably for non-canonical address 0xdcb81a1fb09dad0c: 0000 [#1] SMP NOPTI
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.088529] CPU: 27 PID: 1750957 Comm: python Tainted: P           OE     5.15.0-105-generic #115-Ubuntu
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.088542] Hardware name: Dell Inc. PowerEdge XE9680/0KK0RG, BIOS 1.3.6 09/20/2023
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.088552] RIP: 0010:__kmalloc+0x111/0x330
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.088562] Code: 8b 50 08 49 8b 00 49 83 78 10 00 48 89 45 c8 0f 84 c5 01 00 00 48 85 c0 0f 84 bc 01 00 00 41 8b 4c 24 28 49 8b 3c 24 48 01 c1 <48> 8b 19 48 89 ce 49 33 9c 24 b8 00 00 00 48 8d 4a 01 48 0f ce 48
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.088582] RSP: 0018:ff6d51a74a44f8c0 EFLAGS: 00010286
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.088590] RAX: dcb81a1fb09dacec RBX: 0000000000006cc0 RCX: dcb81a1fb09dad0c
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.088599] RDX: 0000000000483ae6 RSI: 0000000000006cc0 RDI: 00000000000360a0
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.088608] RBP: ff6d51a74a44f900 R08: ff4364f07faf60a0 R09: ff4364b265721a48
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.088616] R10: 0000000000000246 R11: 00000000ffffffff R12: ff43643100034640
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.088624] R13: ffffffffc1ac3ade R14: 0000000000006cc0 R15: 0000000000000000
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.088632] FS:  00007f58acc5f740(0000) GS:ff4364f07fac0000(0000) knlGS:0000000000000000
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.088642] CS:  0010 DS: 0000 ES: 0000 CR0: 0000000080050033
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.088649] CR2: 00007f57e31a18f0 CR3: 000000c2a2392004 CR4: 0000000000771ee0
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.088657] DR0: 0000000000000000 DR1: 0000000000000000 DR2: 0000000000000000
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.088665] DR3: 0000000000000000 DR6: 00000000fffe07f0 DR7: 0000000000000400
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.088673] PKRU: 55555554
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.088678] Call Trace:
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.088682]  <TASK>
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.088687]  ? show_trace_log_lvl+0x1d6/0x2ea
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.088696]  ? show_trace_log_lvl+0x1d6/0x2ea
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.088704]  ? os_alloc_mem+0xce/0xe0 [nvidia]
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.089045]  ? show_regs.part.0+0x23/0x29
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.089052]  ? __die_body.cold+0x8/0xd
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.089058]  ? die_addr+0x3e/0x60
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.089065]  ? exc_general_protection+0x1c5/0x410
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.089076]  ? asm_exc_general_protection+0x27/0x30
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.089084]  ? os_alloc_mem+0xce/0xe0 [nvidia]
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.089295]  ? __kmalloc+0x111/0x330
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.089302]  os_alloc_mem+0xce/0xe0 [nvidia]
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.089451]  _nv012733rm+0x34/0x50 [nvidia]
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.089751] WARNING: kernel stack frame pointer at 0000000052ac1db3 in python:1750957 has bad value 000000007ff1a134
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.089753] unwind stack type:0 next_sp:0000000000000000 mask:0x2 graph_idx:0
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.089754] 00000000ad918525: ff6d51a74a44f920 (0xff6d51a74a44f920)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.089756] 000000006702d15d: ffffffffc1ac3ade (os_alloc_mem+0xce/0xe0 [nvidia])
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.089921] 00000000ad8cf32a: 0000000000000028 (0x28)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.089922] 000000000bfb5002: ff4364b265721a48 (0xff4364b265721a48)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.089923] 0000000052ac1db3: ff4364b0b0f1d960 (0xff4364b0b0f1d960)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.089924] 000000004731675f: ffffffffc23971f4 (_nv012733rm+0x34/0x50 [nvidia])
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.090217] 000000006c9576e4: ff6d51a74a44f950 (0xff6d51a74a44f950)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.090218] 00000000cd2d3f0d: ffffffffc2396bd7 (_nv042350rm+0x27/0xc0 [nvidia])
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.090518] 00000000bcd023f5: 0000000000000000 ...
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.090518] 00000000d65bcc2e: ffffffffc2114ee8 (_nv011696rm+0x48/0xf0 [nvidia])
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.090926] 00000000b54bf8c4: ff4364b0b0f1d960 (0xff4364b0b0f1d960)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.090927] 00000000972c053b: 0000000000000000 ...
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.090928] 00000000e23170fd: ff4364b265721488 (0xff4364b265721488)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.090928] 00000000c2203504: ff43657083aaf268 (0xff43657083aaf268)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.090929] 0000000090bf69bd: 0000000000000028 (0x28)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.090930] 00000000e9aa0a33: ffffffffc2114f3e (_nv011696rm+0x9e/0xf0 [nvidia])
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.091336] 00000000abc031e0: ff4364b0b0f1d960 (0xff4364b0b0f1d960)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.091337] 000000004a873ac6: 0000000000000000 ...
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.091337] 0000000008dc90f3: ff4364b265721cc8 (0xff4364b265721cc8)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.091338] 000000007d11ae51: ff43657083aaf250 (0xff43657083aaf250)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.091339] 00000000571b5a6a: 0000000000000028 (0x28)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.091339] 00000000b78be13c: ffffffffc2114f3e (_nv011696rm+0x9e/0xf0 [nvidia])
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.091746] 000000005a2de64a: ff4364b0b0f1d960 (0xff4364b0b0f1d960)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.091747] 00000000d5b47d78: 0000000000000000 ...
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.091747] 00000000c5a34fea: ff4364b099558380 (0xff4364b099558380)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.091748] 000000001e614027: ff43657083aaf238 (0xff43657083aaf238)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.091748] 00000000236bc3e1: 0000000000000028 (0x28)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.091749] 000000004432afce: ffffffffc2114f3e (_nv011696rm+0x9e/0xf0 [nvidia])
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.092155] 0000000085200344: ff4364b0b0f1d960 (0xff4364b0b0f1d960)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.092156] 000000003bd89786: ffffffffc4b85120 (_nv030098rm+0xdae0/0xfffffffffdadc9c0 [nvidia])
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.092373] 00000000875f0262: ff4364ceb4477a10 (0xff4364ceb4477a10)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.092374] 0000000087d5db1c: ff43657083aaf238 (0xff43657083aaf238)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.092375] 00000000d1af4b30: ff4364b099558380 (0xff4364b099558380)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.092375] 000000002b4c1e6f: ffffffffc2115043 (_nv037213rm+0x93/0x190 [nvidia])
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.092783] 00000000793c6f54: ff4364b0fe183808 (0xff4364b0fe183808)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.092784] 00000000710f000e: ff43657092c08008 (0xff43657092c08008)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.092784] 000000003d26e18e: 0000000000000001 (0x1)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.092785] 00000000548a4d97: ff43657083aaf208 (0xff43657083aaf208)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.092786] 00000000040bb101: 0000000000000001 (0x1)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.092786] 0000000071e2b5ac: ffffffffc1b13f2a (_nv028470rm+0x41a/0x1090 [nvidia])
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.093002] 00000000f4a31b63: ff4364b0b0f1daf0 (0xff4364b0b0f1daf0)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.093002] 000000004117367a: 0000000000000002 (0x2)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.093003] 00000000ee87bbe6: 0000000000000000 ...
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.093003] 00000000bd0246fe: 00000000000090f1 (0x90f1)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.093004] 000000004a63bde2: 0000000000000000 ...
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.093005] 0000000059d1ac9a: ffffffffc1b21984 (_nv048780rm+0x154/0x225 [nvidia])
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.093220] 000000000532a638: 0000000000000000 ...
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.093221] 0000000016d33a90: 00000000e4010000 (0xe4010000)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.093222] 00000000b9999d00: 00000000e4010000 (0xe4010000)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.093222] 000000006c68aee5: ff4364b0b0f1dc10 (0xff4364b0b0f1dc10)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.093223] 00000000c2d67559: ff4364b0b0f1de48 (0xff4364b0b0f1de48)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.093224] 00000000b0c7aeea: ff4364b0c9cb3008 (0xff4364b0c9cb3008)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.093224] 000000007a85569d: ff43657092c08008 (0xff43657092c08008)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.093225] 0000000014a81ebb: ffffffffc1b1795f (_nv048124rm+0x50f/0xc00 [nvidia])
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.093440] 0000000057acf3fe: 0000000000000000 ...
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.093440] 00000000f9c25051: 00000000e4010000 (0xe4010000)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.093441] 0000000056f877e2: ff4364b0b0f1daf0 (0xff4364b0b0f1daf0)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.093441] 0000000086435813: ffffffffc1b17a69 (_nv048124rm+0x619/0xc00 [nvidia])
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.093656] 00000000e0573344: 0000000000000001 (0x1)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.093657] 00000000199d5134: ff4364b0b0f1db88 (0xff4364b0b0f1db88)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.093657] 0000000082ac984a: ff4364b0b0f1dc10 (0xff4364b0b0f1dc10)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.093658] 00000000a71fa9ab: ff4364b0b0f1de48 (0xff4364b0b0f1de48)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.093659] 00000000300f46fd: ff4364b0c9cb3010 (0xff4364b0c9cb3010)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.093659] 000000006c36668b: ffffffffc23a5c85 (_nv004099rm+0xc5/0x160 [nvidia])
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.093954] 000000002e6685c1: ffffffffc4db8378 (_nv043605rm+0x1008/0xfffffffffd89cc90 [nvidia])
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.094160] 00000000bb3afa34: ff4364b0b0f1de48 (0xff4364b0b0f1de48)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.094161] 0000000004579727: ff4364b0b0f1dbc0 (0xff4364b0b0f1dbc0)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.094162] 00000000e64fa9b3: ff4364b0b0f1dc10 (0xff4364b0b0f1dc10)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.094162] 00000000a68a745f: ff4364b0b0f1de48 (0xff4364b0b0f1de48)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.094163] 000000002d66190b: ffffffffc23a1d6b (_nv003464rm+0x4b/0x80 [nvidia])
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.094458] 00000000e6b97998: ff4364b0b0f1dc10 (0xff4364b0b0f1dc10)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.094459] 000000004b23d862: ffffffffc1b53afe (_nv043338rm+0x8e/0x160 [nvidia])
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.094680] 000000003bce6fcf: ff4364b0b0f1dbc8 (0xff4364b0b0f1dbc8)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.094681] 000000006be2d3fc: ff4364b0fe180430 (0xff4364b0fe180430)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.094681] 00000000c9bbe2bc: ff4364b0b0f1dc10 (0xff4364b0b0f1dc10)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.094682] 000000003033a60f: ff4364b164725810 (0xff4364b164725810)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.094683] 00000000106e83e3: ff4364b0b0f1de48 (0xff4364b0b0f1de48)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.094683] 000000000f86c417: ffffffffc239df6b (_nv010118rm+0x27b/0x5f0 [nvidia])
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.094983] 0000000069e295c7: ffffffffc4e58900 (_nv000453rm+0xad4/0xfffffffffd7fc1d4 [nvidia])
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.095183] 0000000032e2d8fb: ff4364b265721348 (0xff4364b265721348)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.095184] 00000000cdb1b0bd: ff4364b0b0f1dcbc (0xff4364b0b0f1dcbc)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.095185] 00000000a9964e27: ff4364b0b0f1de48 (0xff4364b0b0f1de48)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.095185] 000000009d1f6e59: ffffffffc4db8378 (_nv043605rm+0x1008/0xfffffffffd89cc90 [nvidia])
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.095390] 00000000491ede40: ffffffffc1b52db0 (_nv045274rm+0x2b0/0x9e0 [nvidia])
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.095611] 00000000ffad774b: ff4364b265721348 (0xff4364b265721348)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.095612] 00000000beff7023: ff4364b0b0f1de48 (0xff4364b0b0f1de48)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.095612] 00000000b8fe7fd8: ff4364b0b0f1de88 (0xff4364b0b0f1de88)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.095613] 000000001551b9dd: 0000000000000000 ...
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.095614] 000000004f474e7e: ffffffffc4e58900 (_nv000453rm+0xad4/0xfffffffffd7fc1d4 [nvidia])
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.095814] 000000008a6d1ed3: ffffffffc2399279 (_nv045272rm+0x219/0x390 [nvidia])
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.096112] 00000000699cda95: ff4364b265721648 (0xff4364b265721648)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.096113] 0000000012345800: ffffffffc4e58380 (_nv000453rm+0x554/0xfffffffffd7fc1d4 [nvidia])
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.096313] 000000005375742f: ff4364b265721348 (0xff4364b265721348)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.096314] 000000001e6e6939: 0000000000000051 (0x51)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.096314] 00000000678a4c38: ff4364b0b0f1df70 (0xff4364b0b0f1df70)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.096315] 0000000060429bbe: ffffffffc1b53894 (_nv043451rm+0x164/0x2c0 [nvidia])
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.096537] 00000000eb588d20: 00000000000090f1 (0x90f1)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.096538] 000000003ac873b7: ffffffffc4e58380 (_nv000453rm+0x554/0xfffffffffd7fc1d4 [nvidia])
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.096738] 000000003885d990: 00000000c1d260e7 (0xc1d260e7)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.096739] 000000009ce8ee19: 000000005c000009 (0x5c000009)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.096740] 00000000609bb7a8: ff4364b265721648 (0xff4364b265721648)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.096740] 00000000a80b750a: ffffffffc1b53c2c (_nv043452rm+0x5c/0x90 [nvidia])
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.096961] 00000000a7b395be: 0000000000000000 ...
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.096961] 00000000cfb78ec1: ff4364b0b0f1df70 (0xff4364b0b0f1df70)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.096962] 00000000a07f7cc7: ff4364b265721640 (0xff4364b265721640)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.096963] 0000000038ae904b: 0000000000000000 ...
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.096963] 0000000081e1ce54: ff4364b265721640 (0xff4364b265721640)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.096964] 00000000d8424663: ffffffffc4e536e0 (nv_kthread_q+0x40/0xfffffffffd800960 [nvidia])
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.097165] 00000000024cb7bf: 0000000000000030 (0x30)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.097166] 0000000085f7435a: ffffffffc1b627eb (_nv000573rm+0x6b/0x80 [nvidia])
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.097390] 0000000076e0edbe: 0000000000000000 ...
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.097390] 0000000023573ae8: ff4364b0b0f1df70 (0xff4364b0b0f1df70)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.097391] 000000008cdac898: ff4364b164723c00 (0xff4364b164723c00)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.097391] 0000000007fb7777: ffffffffc25400c0 (_nv000716rm+0xa40/0xe70 [nvidia])
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.097636] 0000000014cd9b5a: 0000000000000000 ...
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.097636] 00000000cb5427ef: ff4364b164723c00 (0xff4364b164723c00)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.097637] 00000000678deeff: 0000000000000000 ...
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.097637] 000000008a752d6f: ff4364b0b0f1b000 (0xff4364b0b0f1b000)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.097638] 000000006d791584: ffffffffc4e536e0 (nv_kthread_q+0x40/0xfffffffffd800960 [nvidia])
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.097839] 00000000281ad33b: ff6d51a74a44fe48 (0xff6d51a74a44fe48)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.097840] 000000000ec5a08a: ff4364b164723c00 (0xff4364b164723c00)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.097841] 0000000084209a8f: 000000000000002b (0x2b)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.097842] 00000000f4552b19: ffffffffc2546c68 (rm_ioctl+0x58/0xb0 [nvidia])
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098079] 0000000059a0c74d: 000000300981f1a3 (0x300981f1a3)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098080] 00000000536708dc: ff4364b265721640 (0xff4364b265721640)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098080] 00000000dbcc11c4: 00000000001ab7ad (0x1ab7ad)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098081] 00000000e51287b5: 000000010981f1a5 (0x10981f1a5)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098082] 000000007d5db9a5: 003e210a603c1300 (0x3e210a603c1300)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098083] 00000000756025a2: 003e210b4ea73b00 (0x3e210b4ea73b00)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098083] 000000000c485684: 003e210b4ea73b00 (0x3e210b4ea73b00)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098084] 00000000e8e197a9: 003e210ad771a700 (0x3e210ad771a700)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098085] 000000004632e00b: 0000000000000000 ...
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098085] 00000000cf8ffc6e: 000001200000001b (0x1200000001b)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098086] 00000000ab77f581: 00000000001ab7ad (0x1ab7ad)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098087] 0000000079d237b4: ff6d51a74b0dbdc8 (0xff6d51a74b0dbdc8)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098087] 00000000e8600bf4: 0000000000000000 ...
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098088] 00000000a94282f7: fffffff000000000 (0xfffffff000000000)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098089] 00000000c1e9d983: ffffffffc4e8c330 (_nv042342rm+0x90/0xfffffffffd7c7d60 [nvidia])
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098289] 0000000021259fe3: 0000000000000010 (0x10)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098290] 0000000052d924fa: 0000000000000000 ...
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098290] 000000009f546a1c: 0000000000000030 (0x30)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098291] 00000000bc85886f: ff4364b265721640 (0xff4364b265721640)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098292] 0000000082212652: ff4364b164723c00 (0xff4364b164723c00)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098292] 00000000c9ed8728: ffffffffc4e536e0 (nv_kthread_q+0x40/0xfffffffffd800960 [nvidia])
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098493] 00000000305e6cfe: ffffffffc1ab6cad (nvidia_ioctl+0x61d/0x840 [nvidia])
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098693] 00000000528b3158: ff4364b0b0f1b000 (0xff4364b0b0f1b000)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098694] 00000000c72025d5: 00007ffd380a8e30 (0x7ffd380a8e30)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098695] 00000000e110c02e: 00007ffd0000002b (0x7ffd0000002b)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098696] 00000000b30e7ba8: 00000000c030462b (0xc030462b)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098696] 00000000f138b748: 00007ffd380a8e30 (0x7ffd380a8e30)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098697] 000000008589d711: 55be6b7d715f9300 (0x55be6b7d715f9300)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098698] 000000002cf69c2f: 00000000000000ff (0xff)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098698] 00000000dae74326: ff4364b0b2a3d100 (0xff4364b0b2a3d100)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098699] 0000000022b76572: 00000000c030462b (0xc030462b)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098700] 0000000082e08701: ff4364b087d52710 (0xff4364b087d52710)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098701] 0000000052f4edae: ff4364b0b2a3d100 (0xff4364b0b2a3d100)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098701] 00000000343bb265: ff6d51a74a44fe80 (0xff6d51a74a44fe80)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098702] 0000000000c21cf1: ffffffffc1ac9695 (nvidia_frontend_unlocked_ioctl+0x55/0x90 [nvidia])
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098907] 00000000439b7df8: ff4364b0b2a3d101 (0xff4364b0b2a3d101)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098909] 00000000f390f3b4: ff4364b0b2a3d101 (0xff4364b0b2a3d101)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098909] 00000000c7f8095f: 0000000000000022 (0x22)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098910] 00000000f245b510: 00000000c030462b (0xc030462b)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098911] 0000000094dfbc48: 00007ffd380a8e30 (0x7ffd380a8e30)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098911] 00000000d6a00e67: ff6d51a74a44feb8 (0xff6d51a74a44feb8)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098912] 00000000a7c29ad3: ffffffff8a1b12d2 (__x64_sys_ioctl+0x92/0xd0)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098915] 00000000d1380a6c: 0000000000000000 ...
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098915] 000000004bddf882: ff6d51a74a44ff58 (0xff6d51a74a44ff58)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098916] 00000000e9ceaf1f: 0000000000000000 ...
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098916] 00000000efa36a4e: ff6d51a74a44ff48 (0xff6d51a74a44ff48)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098917] 000000002878b7a0: ffffffff8abbbb59 (do_syscall_64+0x59/0xc0)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098919] 00000000c722a477: ffffffff89f6ee77 (exit_to_user_mode_prepare+0x37/0xb0)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098922] 000000003d0d13e9: ff6d51a74a44ff58 (0xff6d51a74a44ff58)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098923] 000000002c7565d3: ff6d51a74a44fef0 (0xff6d51a74a44fef0)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098924] 000000002906bbb0: ffffffff8abc0005 (syscall_exit_to_user_mode+0x35/0x50)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098925] 0000000080279811: 0000000000000000 ...
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098925] 000000001ea77bac: ff6d51a74a44ff48 (0xff6d51a74a44ff48)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098926] 000000002f46ca31: ffffffff8abbbb69 (do_syscall_64+0x69/0xc0)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098927] 000000008a12cb7b: ffffffff89f6ee77 (exit_to_user_mode_prepare+0x37/0xb0)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098929] 000000007787b46d: ff6d51a74a44ff58 (0xff6d51a74a44ff58)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098930] 0000000026c91579: ff6d51a74a44ff28 (0xff6d51a74a44ff28)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098931] 00000000dfaa241f: ffffffff8abc0005 (syscall_exit_to_user_mode+0x35/0x50)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098932] 00000000880a9ff8: 0000000000000000 ...
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098932] 000000008d4c2f61: ff6d51a74a44ff48 (0xff6d51a74a44ff48)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098933] 000000002801f576: ffffffff8abbbb69 (do_syscall_64+0x69/0xc0)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098934] 0000000008e1d9fb: 0000000000000000 ...
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098935] 00000000269e1636: ffffffff8ac000da (entry_SYSCALL_64_after_hwframe+0x62/0xcc)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098936] 00000000ab34a657: 0000000000000022 (0x22)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098937] 00000000f00c1bd6: 00000000c030462b (0xc030462b)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098938] 000000009eed11eb: 0000000000000030 (0x30)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098938] 00000000142b6c50: 00007ffd380a8e30 (0x7ffd380a8e30)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098939] 0000000019fb8b8a: 00007ffd380a8d60 (0x7ffd380a8d60)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098940] 0000000053b5a645: 0000000000000022 (0x22)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098940] 00000000fc4ed72c: 0000000000000246 (0x246)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098941] 00000000280ffee0: 00007ffd380a8430 (0x7ffd380a8430)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098942] 00000000cc3c1ca9: 00007ffd380a8e58 (0x7ffd380a8e58)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098942] 000000005ff1e49b: 00007ffd380a8e30 (0x7ffd380a8e30)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098943] 000000002888afc7: ffffffffffffffda (0xffffffffffffffda)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098944] 0000000098ba181c: 00007f58acd7c9bf (0x7f58acd7c9bf)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098945] 0000000004c1615a: 00007ffd380a8e30 (0x7ffd380a8e30)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098945] 00000000f20de12a: 00000000c030462b (0xc030462b)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098946] 0000000007cd9428: 0000000000000022 (0x22)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098947] 00000000ce0cc84b: 0000000000000010 (0x10)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098947] 00000000c7ff9b02: 00007f58acd7c9bf (0x7f58acd7c9bf)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098948] 00000000b1ed311c: 0000000000000033 (0x33)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098949] 000000005ca2c0d7: 0000000000000246 (0x246)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098949] 0000000044dab3d7: 00007ffd380a8cb0 (0x7ffd380a8cb0)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098950] 000000009321e9cb: 000000000000002b (0x2b)
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.098951]  ? _nv042350rm+0x27/0xc0 [nvidia]
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.143595]  ? _nv011696rm+0x48/0xf0 [nvidia]
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.144265]  ? _nv011696rm+0x9e/0xf0 [nvidia]
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.144906]  ? _nv011696rm+0x9e/0xf0 [nvidia]
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.145512]  ? _nv011696rm+0x9e/0xf0 [nvidia]
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.146105]  ? _nv037213rm+0x93/0x190 [nvidia]
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.146700]  ? _nv028470rm+0x41a/0x1090 [nvidia]
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.147101]  ? _nv048780rm+0x154/0x225 [nvidia]
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.147501]  ? _nv048124rm+0x50f/0xc00 [nvidia]
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.147898]  ? _nv048124rm+0x619/0xc00 [nvidia]
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.148288]  ? _nv004099rm+0xc5/0x160 [nvidia]
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.148766]  ? _nv003464rm+0x4b/0x80 [nvidia]
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.149242]  ? _nv043338rm+0x8e/0x160 [nvidia]
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.149635]  ? _nv010118rm+0x27b/0x5f0 [nvidia]
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.150112]  ? _nv045274rm+0x2b0/0x9e0 [nvidia]
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.150500]  ? _nv045272rm+0x219/0x390 [nvidia]
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.150976]  ? _nv043451rm+0x164/0x2c0 [nvidia]
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.151357]  ? _nv043452rm+0x5c/0x90 [nvidia]
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.151737]  ? _nv000573rm+0x6b/0x80 [nvidia]
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.152114]  ? _nv000716rm+0xa40/0xe70 [nvidia]
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.152514]  ? rm_ioctl+0x58/0xb0 [nvidia]
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.152910]  ? nvidia_ioctl+0x61d/0x840 [nvidia]
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.153260]  ? nvidia_frontend_unlocked_ioctl+0x55/0x90 [nvidia]
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.153614]  ? __x64_sys_ioctl+0x92/0xd0
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.153762]  ? do_syscall_64+0x59/0xc0
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.153907]  ? exit_to_user_mode_prepare+0x37/0xb0
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.154050]  ? syscall_exit_to_user_mode+0x35/0x50
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.154190]  ? do_syscall_64+0x69/0xc0
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.154329]  ? exit_to_user_mode_prepare+0x37/0xb0
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.154470]  ? syscall_exit_to_user_mode+0x35/0x50
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.154611]  ? do_syscall_64+0x69/0xc0
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.154753]  ? entry_SYSCALL_64_after_hwframe+0x62/0xcc
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.154899]  </TASK>
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.155043] Modules linked in: nf_conntrack_netlink xt_nat xt_tcpudp veth xt_conntrack xt_MASQUERADE bridge xt_set ip_set nft_counter nft_chain_nat nf_nat nf_conntrack nf_defrag_ipv6 nf_defrag_ipv4 xt_addrtype nft_compat nf_tables nfnetlink xfrm_user xfrm_algo nfsv3 nfs_acl nfs lockd grace fscache netfs scsi_transport_iscsi nvme_fabrics 8021q garp mrp stp llc uio_pci_generic uio cuse overlay rdma_ucm(OE) rdma_cm(OE) iw_cm(OE) ib_ipoib(OE) ib_cm(OE) ib_umad(OE) bonding sunrpc binfmt_misc nls_iso8859_1 ipmi_ssif intel_rapl_msr dell_wmi ledtrig_audio sparse_keymap video intel_rapl_common i10nm_edac nfit x86_pkg_temp_thermal intel_powerclamp coretemp mlx5_ib(OE) dell_smbios dcdbas idxd isst_if_mbox_pci pmt_telemetry pmt_crashlog isst_if_mmio rapl mei_me wmi_bmof dell_wmi_descriptor switchtec isst_if_common pmt_class idxd_bus joydev input_leds ib_uverbs(OE) mei acpi_ipmi ipmi_si ipmi_devintf ipmi_msghandler acpi_power_meter mac_hid nvidia_uvm(POE) sch_fq_codel dm_multipath scsi_dh_rdac
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.155089]  scsi_dh_emc scsi_dh_alua nvidia_peermem(POE) ib_core(OE) knem(OE) efi_pstore ip_tables x_tables autofs4 btrfs blake2b_generic zstd_compress raid10 raid456 async_raid6_recov async_memcpy async_pq async_xor async_tx xor raid6_pq libcrc32c raid1 raid0 multipath linear nvidia_drm(POE) nvidia_modeset(POE) ses enclosure hid_generic usbhid hid mlx5_core(OE) mlxdevm(OE) nvidia(POE) mlxfw(OE) psample mgag200 i2c_algo_bit drm_kms_helper syscopyarea sysfillrect sysimgblt fb_sys_fops crct10dif_pclmul cec crc32_pclmul rc_core ghash_clmulni_intel sha256_ssse3 sha1_ssse3 aesni_intel crypto_simd tls mpt3sas cryptd ahci nvme intel_pmt raid_class mlx_compat(OE) i2c_i801 xhci_pci bnxt_en drm scsi_transport_sas pci_hyperv_intf tg3 i2c_smbus libahci i2c_ismt nvme_core xhci_pci_renesas wmi pinctrl_emmitsburg
Jan  4 05:00:50 usr002-gpumngc-01 kernel: [308219.158392] ---[ end trace 318a847c90a96792 ]---
