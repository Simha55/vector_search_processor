"""Independent integer cosine model and packed INT8 conversion helpers.

No simulator is launched when this module is imported.
"""
import math

SCALE = 1 << 30


def normalize(dot, nq, nd):
    if not nq or not nd:
        return 0, 1
    magnitude = min(SCALE, (abs(dot) << 62) // math.isqrt((nq * nd) << 64))
    return (-magnitude if dot < 0 else magnitude), 0


def reference(q, d):
    dot = sum(a*b for a, b in zip(q, d))
    nq = sum(a*a for a in q)
    nd = sum(b*b for b in d)
    if not nq or not nd:
        return 0, 2
    # Bit-accurate independent integer model, with no Verilog-style iteration.
    denominator = math.isqrt((nq*nd) << 64)
    magnitude = min(SCALE, (abs(dot) << 62)//denominator)
    score = -magnitude if dot < 0 else magnitude
    # Also check the mathematical cosine, not just the implementation formula.
    mathematical = dot/math.sqrt(nq*nd)
    assert abs(score/SCALE - mathematical) <= 2/SCALE
    return score, 0


def chunks(values, lanes):
    for offset in range(0, len(values), lanes):
        # Poison padding so an incorrect final-lane mask changes the answer.
        part = values[offset:offset + lanes]
        part += [127] * (lanes - len(part))
        yield sum((value & 255) << (8 * lane) for lane, value in enumerate(part))


def bits32(value):
    return value & 0xFFFFFFFF
