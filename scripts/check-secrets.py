#!/usr/bin/env python3
"""Stops a commit or release that would publish something private.

Checks every file git would include (tracked + new, minus .gitignore) for:
  * private keys, keychains, vaults, sync files and similar files
  * private-key blocks inside text
  * IPv4 addresses outside documentation/example ranges
  * e-mail addresses other than example / no-reply ones
  * anything listed in ~/.macterm-signing/secret-patterns.txt (your own private list: real IPs,
    host names, e-mail; one per line; that file never goes into the repo)

Usage: scripts/check-secrets.py [--staged]     exit 1 when something is found
"""
import ipaddress
import os
import re
import subprocess
import sys

ROOT = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True).stdout.strip() or "."
os.chdir(ROOT)

if "--staged" in sys.argv:
    files = subprocess.run(["git", "diff", "--cached", "--name-only", "--diff-filter=ACMR"], capture_output=True, text=True).stdout.split("\n")
else:
    files = subprocess.run(["git", "ls-files", "-co", "--exclude-standard"], capture_output=True, text=True).stdout.split("\n")
files = [f for f in files if f and os.path.isfile(f)]

SELF = "scripts/check-secrets.py"
BAD_NAMES = re.compile(r"(^|/)(id_(rsa|ed25519|ecdsa|dsa)|.*\.(pem|p12|pfx|key|keychain|keychain-db|vault)|sync\.json|known_hosts(\.json)?|passwords\.vault|\.env(\..*)?|secrets?\.json)$", re.I)
KEY_BLOCK = re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----\s*\n[A-Za-z0-9+/=]{40,}")
IPV4 = re.compile(r"(?<![\d.])((?:\d{1,3}\.){3}\d{1,3})(?![\d.])")
EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@([A-Za-z0-9-]+\.)+[A-Za-z]{2,}")

ALLOWED_NETS = [ipaddress.ip_network(n) for n in [
    "127.0.0.0/8", "0.0.0.0/32", "10.0.0.0/8", "192.0.2.0/24", "198.51.100.0/24", "203.0.113.0/24",
    "255.0.0.0/8", "169.254.0.0/16", "224.0.0.0/4", "192.168.0.0/23",   # 192.168.0.x / 1.x: generic examples
    "1.1.1.1/32", "1.0.0.1/32", "8.8.8.8/32", "8.8.4.4/32"]]
ALLOWED_EMAIL = re.compile(r"(@(.*\.)?example\.(com|net|org)$|@users\.noreply\.github\.com$|^noreply@|^git@github\.com$|@localhost$)", re.I)

private = []
plist = os.path.expanduser("~/.macterm-signing/secret-patterns.txt")
if os.path.exists(plist):
    private = [l.strip() for l in open(plist, encoding="utf-8") if l.strip() and not l.startswith("#")]

problems = []
for f in files:
    if BAD_NAMES.search(f) and not f.endswith(".pub"):
        problems.append(f"{f}: file type must never be published")
        continue
    if f == SELF:
        continue
    try:
        data = open(f, "rb").read()
    except OSError:
        continue
    if b"\0" in data[:4096]:
        continue   # binary (images etc.)
    text = data.decode("utf-8", "replace")
    if KEY_BLOCK.search(text):
        problems.append(f"{f}: contains a private key")
    for n, line in enumerate(text.split("\n"), 1):
        for m in IPV4.finditer(line):
            try:
                ip = ipaddress.ip_address(m.group(1))
            except ValueError:
                continue   # version numbers like 1.2.300.4
            if not any(ip in net for net in ALLOWED_NETS):
                problems.append(f"{f}:{n}: real-looking IP address {ip} (use 192.0.2.x / 198.51.100.x / 203.0.113.x in examples)")
        for m in EMAIL.finditer(line):
            if not ALLOWED_EMAIL.search(m.group(0)):
                problems.append(f"{f}:{n}: e-mail address {m.group(0)} (use name@example.com in examples)")
        low = line.lower()
        for p in private:
            if p.lower() in low:
                problems.append(f"{f}:{n}: matches an entry in your private list")

if problems:
    print("✗ Private data check failed — nothing was published:")
    for p in problems[:60]:
        print("   " + p)
    if len(problems) > 60:
        print(f"   … and {len(problems) - 60} more")
    sys.exit(1)
print(f"✓ Private data check passed ({len(files)} files{', private list used' if private else ''}).")
