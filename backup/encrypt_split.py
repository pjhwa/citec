#!/usr/bin/env python3
"""
encrypt_split.py
────────────────
파이프라인: 원본 → LZMA-9e 압축 → AES-256-GCM 암호화 → Base64 → N개 청크 파일

의존성: pip install cryptography
사용법: python encrypt_split.py <input_file> <output_dir> [--chunk 2000]
"""

import os, sys, json, base64, lzma, hashlib, secrets, getpass, argparse, time
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from cryptography.hazmat.primitives import hashes

PBKDF2_ITERATIONS = 600_000   # NIST 2023 권장
DEFAULT_CHUNK     = 2000      # chars per chunk file (조정 가능)


def derive_key(password: str, salt: bytes) -> bytes:
    kdf = PBKDF2HMAC(
        algorithm=hashes.SHA256(),
        length=32,
        salt=salt,
        iterations=PBKDF2_ITERATIONS,
    )
    return kdf.derive(password.encode("utf-8"))


def process(input_path: str, output_dir: str, password: str, chunk_size: int):
    os.makedirs(output_dir, exist_ok=True)
    t0 = time.time()

    # ── 1. 원본 읽기 ──────────────────────────────────────────────
    with open(input_path, "rb") as f:
        data = f.read()
    orig_sha256 = hashlib.sha256(data).hexdigest()
    print(f"[1] 원본        : {len(data):>12,} bytes")

    # ── 2. LZMA 압축 (preset 9 | EXTREME) ────────────────────────
    compressed = lzma.compress(data, preset=9 | lzma.PRESET_EXTREME)
    comp_sha256 = hashlib.sha256(compressed).hexdigest()
    ratio = 100 * len(compressed) / len(data)
    print(f"[2] 압축 후     : {len(compressed):>12,} bytes  ({ratio:.1f}% / 절감 {100-ratio:.1f}%)")

    # ── 3. AES-256-GCM 암호화 ─────────────────────────────────────
    salt  = secrets.token_bytes(32)   # 256-bit salt (공개 가능, 비밀 아님)
    nonce = secrets.token_bytes(12)   # 96-bit nonce (GCM 표준)
    key   = derive_key(password, salt)
    aesgcm = AESGCM(key)
    ciphertext = aesgcm.encrypt(nonce, compressed, None)
    # GCM output = ciphertext + 16-byte auth tag (자동 포함)
    print(f"[3] 암호화 후   : {len(ciphertext):>12,} bytes  (AES-256-GCM + auth tag)")

    # ── 4. Base64 인코딩 ──────────────────────────────────────────
    b64_data = base64.b64encode(ciphertext).decode("ascii")
    print(f"[4] Base64 후   : {len(b64_data):>12,} chars")

    # ── 5. 청크 분할 ──────────────────────────────────────────────
    chunks = [b64_data[i : i + chunk_size] for i in range(0, len(b64_data), chunk_size)]
    total  = len(chunks)
    print(f"[5] 청크 수     : {total:>12,} 개  (chunk_size={chunk_size})")

    for idx, chunk in enumerate(chunks):
        fname = os.path.join(output_dir, f"chunk_{idx:05d}.b64")
        with open(fname, "w", encoding="ascii") as f:
            f.write(chunk)

    # ── 6. manifest.json 저장 ─────────────────────────────────────
    manifest = {
        "version"          : 1,
        "filename"         : os.path.basename(input_path),
        "orig_size"        : len(data),
        "comp_size"        : len(compressed),
        "total_chunks"     : total,
        "chunk_size"       : chunk_size,
        "pbkdf2_iters"     : PBKDF2_ITERATIONS,
        "salt_hex"         : salt.hex(),
        "nonce_hex"        : nonce.hex(),
        "sha256_original"  : orig_sha256,
        "sha256_compressed": comp_sha256,
    }
    manifest_path = os.path.join(output_dir, "manifest.json")
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)

    elapsed = time.time() - t0
    print(f"\n✓ 완료 ({elapsed:.1f}s) → {output_dir}/")
    print(f"  manifest.json + chunk_00000.b64 ~ chunk_{total-1:05d}.b64")
    print(f"  총 {total + 1}개 파일, 총 크기 ~{len(b64_data)//1024:.0f} KB")
    print(f"\n⚠  주의: manifest.json 에 원본 파일명이 평문 포함됨.")
    print(f"         민감하면 filename 필드를 수동으로 치환하세요.")


def main():
    ap = argparse.ArgumentParser(description="compress → encrypt → split")
    ap.add_argument("input",  help="입력 파일 경로")
    ap.add_argument("output", help="청크 저장 디렉토리")
    ap.add_argument("--chunk", type=int, default=DEFAULT_CHUNK,
                    help=f"청크 크기 chars (기본 {DEFAULT_CHUNK})")
    args = ap.parse_args()

    pw = getpass.getpass("암호화 비밀번호: ")
    pw2 = getpass.getpass("비밀번호 확인 : ")
    if pw != pw2:
        print("✗ 비밀번호 불일치"), sys.exit(1)
    if len(pw) < 12:
        print("⚠  경고: 비밀번호가 12자 미만입니다. 강력한 비밀번호를 권장합니다.")

    process(args.input, args.output, pw, args.chunk)


if __name__ == "__main__":
    main()
