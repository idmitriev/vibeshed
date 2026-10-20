#!/usr/bin/env python3
"""Draws the QR codes for the USDC donation addresses as static SVGs:
  docs/img/qr-evm.svg     the address for Base, Polygon, Arbitrum and Ethereum
  docs/img/qr-solana.svg  the Solana address

The addresses are read from DONATE.md, the signed source of truth. The encoder is a
small QR Code Model 2 implementation (byte mode, error correction M, versions 1-6),
so building the site needs nothing beyond Python.

Run from the repo root:  python3 scripts/donate_qr.py
"""

import re

DONATE = "DONATE.md"
SVG_PATHS = {"evm": "docs/img/qr-evm.svg", "solana": "docs/img/qr-solana.svg"}

EVM_RE = re.compile(r"\b0x[0-9a-fA-F]{40}\b")
SOLANA_RE = re.compile(r"\b[1-9A-HJ-NP-Za-km-z]{32,44}\b")


def addresses(text):
    """The EVM and Solana addresses in DONATE.md's text, each exactly once."""
    evm = set(EVM_RE.findall(text))
    solana = {s for s in SOLANA_RE.findall(text) if not s.startswith("0x") and any(ch.isdigit() for ch in s)}
    if len(evm) != 1 or len(solana) != 1:
        raise SystemExit(f"{DONATE}: expected one EVM and one Solana address, found {sorted(evm)} {sorted(solana)}")
    return {"evm": evm.pop(), "solana": solana.pop()}


# --- Reed-Solomon over GF(256) ------------------------------------------------------------

EXP = [0] * 512
LOG = [0] * 256
_x = 1
for _i in range(255):
    EXP[_i] = _x
    LOG[_x] = _i
    _x <<= 1
    if _x & 0x100:
        _x ^= 0x11D
for _i in range(255, 512):
    EXP[_i] = EXP[_i - 255]


def gf_mul(a, b):
    return 0 if a == 0 or b == 0 else EXP[LOG[a] + LOG[b]]


def rs_remainder(data, degree):
    gen = [1]
    for i in range(degree):
        gen = [a ^ gf_mul(b, EXP[i]) for a, b in zip(gen + [0], [0] + gen)]
    rem = [0] * degree
    for byte in data:
        factor = byte ^ rem[0]
        rem = rem[1:] + [0]
        for i in range(degree):
            rem[i] ^= gf_mul(gen[i + 1], factor)
    return rem


# --- Encoding ----------------------------------------------------------------------------

# Error correction M: version -> (blocks, data codewords per block, EC codewords per block)
BLOCKS_M = {1: (1, 16, 10), 2: (1, 28, 16), 3: (1, 44, 26), 4: (2, 32, 18), 5: (2, 43, 24), 6: (4, 27, 16)}
ALIGN = {1: [], 2: [6, 18], 3: [6, 22], 4: [6, 26], 5: [6, 30], 6: [6, 34]}
EC_M_BITS = 0b00


def codewords(text):
    payload = text.encode("utf-8")
    for version, (blocks, per_block, ec) in BLOCKS_M.items():
        capacity = blocks * per_block
        if 4 + 8 + 8 * len(payload) <= capacity * 8:
            break
    else:
        raise ValueError("too long for versions 1-6")
    bits = "0100" + format(len(payload), "08b") + "".join(format(b, "08b") for b in payload)
    bits += "0" * min(4, capacity * 8 - len(bits))
    bits += "0" * (-len(bits) % 8)
    data = [int(bits[i : i + 8], 2) for i in range(0, len(bits), 8)]
    pad = [0xEC, 0x11]
    while len(data) < capacity:
        data.append(pad[(len(data) - len(bits) // 8) % 2])
    chunks = [data[i * per_block : (i + 1) * per_block] for i in range(blocks)]
    ecc = [rs_remainder(c, ec) for c in chunks]
    out = [c[i] for i in range(per_block) for c in chunks]
    out += [e[i] for i in range(ec) for e in ecc]
    return version, out


def format_bits(mask):
    value = (EC_M_BITS << 3) | mask
    rem = value
    for _ in range(10):
        rem = (rem << 1) ^ ((rem >> 9) * 0x537)
    return ((value << 10) | rem) ^ 0x5412


MASKS = [
    lambda r, c: (r + c) % 2 == 0,
    lambda r, c: r % 2 == 0,
    lambda r, c: c % 3 == 0,
    lambda r, c: (r + c) % 3 == 0,
    lambda r, c: (r // 2 + c // 3) % 2 == 0,
    lambda r, c: (r * c) % 2 + (r * c) % 3 == 0,
    lambda r, c: ((r * c) % 2 + (r * c) % 3) % 2 == 0,
    lambda r, c: ((r + c) % 2 + (r * c) % 3) % 2 == 0,
]


def base_matrix(version):
    size = 17 + 4 * version
    grid = [[None] * size for _ in range(size)]

    def finder(r0, c0):
        for r in range(-1, 8):
            for c in range(-1, 8):
                rr, cc = r0 + r, c0 + c
                if 0 <= rr < size and 0 <= cc < size:
                    ring = max(abs(r - 3), abs(c - 3))
                    grid[rr][cc] = ring != 2 and ring != 4

    finder(0, 0)
    finder(0, size - 7)
    finder(size - 7, 0)
    for i in range(8, size - 8):
        grid[6][i] = grid[i][6] = i % 2 == 0
    centers = ALIGN[version]
    for r in centers:
        for c in centers:
            if grid[r][c] is not None:
                continue
            for dr in range(-2, 3):
                for dc in range(-2, 3):
                    grid[r + dr][c + dc] = max(abs(dr), abs(dc)) != 1
    grid[size - 8][8] = True  # dark module
    # Reserve the format areas so data skips them.
    for i in range(9):
        if grid[8][i] is None:
            grid[8][i] = False
        if grid[i][8] is None:
            grid[i][8] = False
    for i in range(8):
        if grid[8][size - 1 - i] is None:
            grid[8][size - 1 - i] = False
        if grid[size - 1 - i][8] is None:
            grid[size - 1 - i][8] = False
    return grid


def place_format(grid, mask):
    size = len(grid)
    bits = format_bits(mask)
    bit = lambda i: (bits >> i) & 1 == 1  # noqa: E731
    # First copy, around the top-left finder (grid[row][column]).
    for i in range(6):
        grid[i][8] = bit(i)
    grid[7][8] = bit(6)
    grid[8][8] = bit(7)
    grid[8][7] = bit(8)
    for i in range(9, 15):
        grid[8][14 - i] = bit(i)
    # Second copy, split between the top-right and bottom-left finders.
    for i in range(8):
        grid[8][size - 1 - i] = bit(i)
    for i in range(8, 15):
        grid[size - 15 + i][8] = bit(i)
    grid[size - 8][8] = True


def place_data(grid, data, mask):
    size = len(grid)
    reserved = [[cell is not None for cell in row] for row in grid]
    bits = [(byte >> (7 - i)) & 1 for byte in data for i in range(8)]
    k = 0
    col = size - 1
    upward = True
    while col > 0:
        if col == 6:
            col -= 1
        rows = range(size - 1, -1, -1) if upward else range(size)
        for r in rows:
            for c in (col, col - 1):
                if reserved[r][c]:
                    continue
                dark = k < len(bits) and bits[k] == 1
                k += 1
                grid[r][c] = dark != MASKS[mask](r, c)
        upward = not upward
        col -= 2


def penalty(grid):
    size = len(grid)
    score = 0
    lines = grid + [list(col) for col in zip(*grid)]
    for line in lines:
        run = 1
        for i in range(1, size + 1):
            if i < size and line[i] == line[i - 1]:
                run += 1
            else:
                if run >= 5:
                    score += run - 2
                run = 1
        for i in range(size - 10):
            seg = line[i : i + 11]
            if seg in (
                [True, False, True, True, True, False, True, False, False, False, False],
                [False, False, False, False, True, False, True, True, True, False, True],
            ):
                score += 40
    for r in range(size - 1):
        for c in range(size - 1):
            if grid[r][c] == grid[r][c + 1] == grid[r + 1][c] == grid[r + 1][c + 1]:
                score += 3
    dark = sum(map(sum, grid))
    score += abs(dark * 20 - size * size * 10) // (size * size) * 10
    return score


def qr_matrix(text, mask=None):
    version, data = codewords(text)
    best = None
    for m in range(8) if mask is None else [mask]:
        grid = base_matrix(version)
        place_data(grid, data, m)
        place_format(grid, m)
        score = penalty(grid)
        if best is None or score < best[0]:
            best = (score, grid)
    return best[1]


def svg(text, label):
    grid = qr_matrix(text)
    quiet = 4
    size = len(grid) + 2 * quiet
    path = "".join(
        f"M{c + quiet} {r + quiet}h1v1h-1z" for r, row in enumerate(grid) for c, dark in enumerate(row) if dark
    )
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {size} {size}" role="img" '
        f'aria-label="QR code: {label}" shape-rendering="crispEdges">'
        f'<title>{label}: {text}</title>'
        f'<rect width="{size}" height="{size}" fill="#fff"/>'
        f'<path fill="#000" d="{path}"/></svg>\n'
    )


LABELS = {"evm": "USDC on Base, Polygon, Arbitrum or Ethereum", "solana": "USDC on Solana"}


def expected_svgs():
    with open(DONATE, encoding="utf-8") as f:
        found = addresses(f.read())
    return found, {key: svg(found[key], LABELS[key]) for key in SVG_PATHS}


def main():
    _, svgs = expected_svgs()
    for key, path in SVG_PATHS.items():
        with open(path, "w", encoding="utf-8") as f:
            f.write(svgs[key])
        print(f"wrote {path}")


if __name__ == "__main__":
    main()
