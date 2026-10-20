#!/usr/bin/env python3
"""Fails if the USDC donation addresses anywhere diverge from DONATE.md, the signed source.

Checks that:
  - DONATE.md holds exactly one EVM address and one Solana address;
  - README.md and docs/index.html show both, and no other address-shaped string;
  - docs/img/qr-*.svg are exactly what scripts/donate_qr.py draws from DONATE.md.

Run from the repo root:  python3 scripts/check-donate-addresses.py
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import donate_qr  # noqa: E402

PAGES = ["README.md", "docs/index.html"]

# Anything that could be read as an address: 0x + 40 hex, or a long base58 run.
EVM_LIKE = re.compile(r"0x[0-9a-fA-F]{38,42}(?![0-9a-zA-Z])")
SOLANA_LIKE = re.compile(r"(?<![0-9A-Za-z])[1-9A-HJ-NP-Za-km-z]{40,46}(?![0-9A-Za-z])")


def main():
    with open(donate_qr.DONATE, encoding="utf-8") as f:
        source = donate_qr.addresses(f.read())
    errors = []
    for path in PAGES:
        with open(path, encoding="utf-8") as f:
            text = f.read()
        for key, address in source.items():
            if address not in text:
                errors.append(f"{path}: missing the {key} address {address}")
        for found in set(EVM_LIKE.findall(text)) | set(SOLANA_LIKE.findall(text)):
            if found not in source.values():
                errors.append(f"{path}: {found} is not an address from {donate_qr.DONATE}")

    _, svgs = donate_qr.expected_svgs()
    for key, path in donate_qr.SVG_PATHS.items():
        try:
            with open(path, encoding="utf-8") as f:
                current = f.read()
        except FileNotFoundError:
            current = None
        if current != svgs[key]:
            errors.append(f"{path}: out of date; run python3 scripts/donate_qr.py")

    if errors:
        print("\n".join(errors))
        sys.exit(1)
    print(f"OK: {source['evm']} and {source['solana']} match in {', '.join([donate_qr.DONATE, *PAGES])} and the QR codes")


if __name__ == "__main__":
    main()
