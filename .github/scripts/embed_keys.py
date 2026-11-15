"""빌드 직전에 repository secrets를 BuiltInKeys.swift에 섞어 넣는다. 키 값은 로그에 출력하지 않는다."""
import os, secrets, sys

path = sys.argv[1]
salt = secrets.token_bytes(32)

def mix(s: str) -> str:
    b = s.strip().encode()
    return ", ".join(str(c ^ salt[i % len(salt)]) for i, c in enumerate(b))

jev = os.environ.get("JEV_API_KEY", "").strip()
claude = os.environ.get("CLAUDE_API_KEY", "").strip()
hint = "openrouter" if jev.startswith("sk-or-") else ("typesafe" if jev else "")

src = open(path, encoding="utf-8").read()
src = src.replace("static let salt: [UInt8] = []", f"static let salt: [UInt8] = [{', '.join(map(str, salt))}]")
src = src.replace("static let jevBytes: [UInt8] = []", f"static let jevBytes: [UInt8] = [{mix(jev)}]" if jev else "static let jevBytes: [UInt8] = []")
src = src.replace("static let claudeBytes: [UInt8] = []", f"static let claudeBytes: [UInt8] = [{mix(claude)}]" if claude else "static let claudeBytes: [UInt8] = []")
src = src.replace('static let jevProviderHint = ""', f'static let jevProviderHint = "{hint}"')
open(path, "w", encoding="utf-8").write(src)
print(f"Jev key: {'yes' if jev else 'no'} (provider: {hint or '-'}), Claude key: {'yes' if claude else 'no'}")
