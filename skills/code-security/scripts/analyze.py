import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys


def main() -> int:
    parser = argparse.ArgumentParser(description="Call the authorized OctoBus code security capability")
    parser.add_argument("--filename", required=True)
    parser.add_argument("--language", required=True)
    code_group = parser.add_mutually_exclusive_group(required=True)
    code_group.add_argument("--code")
    code_group.add_argument("--code-base64")
    args = parser.parse_args()

    if args.code_base64:
        try:
            code = base64.b64decode(args.code_base64, validate=True).decode("utf-8")
        except (ValueError, UnicodeDecodeError) as error:
            print(json.dumps({"error": "invalid UTF-8 code base64", "detail": str(error)}))
            return 2
    else:
        code = args.code

    target = os.environ.get("CAP_GRPC_TARGET", "").strip()
    token = os.environ.get("CAP_TOKEN", "").strip()
    if not target or not token:
        print(json.dumps({"error": "capability environment is unavailable"}))
        return 2

    payload = json.dumps(
        {"filename": args.filename, "language": args.language, "code": code},
        ensure_ascii=False,
    )
    # Bump this prefix whenever the capability response schema changes so an old
    # same-input cache cannot silently omit newly required provenance fields.
    cache_key = hashlib.sha256(("evidence-v2\0" + payload).encode("utf-8")).hexdigest()
    cache_path = Path("/tmp") / f"code-security-{cache_key}.json"
    if cache_path.exists():
        sys.stdout.write(cache_path.read_text(encoding="utf-8"))
        return 0

    command = [
        "grpcurl",
        "-plaintext",
        "-H",
        f"x-capability-sandbox-token: {token}",
        "-H",
        "x-octobus-capset: local/security-review",
        "-H",
        "x-octobus-instance: code-security-main",
        "-d",
        payload,
        target,
        "codesecurity.v1.CodeSecurityService/AnalyzeSnippet",
    ]
    completed = subprocess.run(command, capture_output=True, text=True, timeout=30, check=False)
    if completed.returncode != 0:
        print(json.dumps({"error": "capability call failed", "detail": completed.stderr.strip()}))
        return completed.returncode
    cache_path.write_text(completed.stdout, encoding="utf-8")
    sys.stdout.write(completed.stdout)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
