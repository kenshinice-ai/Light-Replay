"""Recompute the numeric claims in the docs/blueprint-v1 review (2026-09-10).

Run: python3 verify_review.py   (stdlib only)
"""
import itertools
import math

TRUST = ["solar", "vps", "map", "magnetic"]


def cdiff(a, b):
    """Circular difference in degrees, in [0, 180]."""
    d = abs(a - b) % 360
    return min(d, 360 - d)


def fuse(cands):
    """Inverse-variance weighted circular mean. cands: [(yaw_deg, sigma_deg)]."""
    w = [1 / s**2 for _, s in cands]
    x = sum(wi * math.cos(math.radians(y)) for wi, (y, _) in zip(w, cands))
    y = sum(wi * math.sin(math.radians(y)) for wi, (y, _) in zip(w, cands))
    return round(math.degrees(math.atan2(y, x)) % 360, 2), round(1 / math.sqrt(sum(w)), 2)


def conflicting_pairs(groups):
    """Group pairs whose circular difference exceeds 3*sqrt(si^2 + sj^2)."""
    return [
        (gi, gj)
        for (gi, (yi, si)), (gj, (yj, sj)) in itertools.combinations(groups.items(), 2)
        if cdiff(yi, yj) > 3 * math.sqrt(si**2 + sj**2)
    ]


def resolve_current(groups):
    """docs/05 §3 step 4 as written: any conflict keeps only the most trusted group."""
    if not conflicting_pairs(groups):
        return list(groups), [], fuse(list(groups.values()))
    top = min(groups, key=TRUST.index)
    return [top], [g for g in groups if g != top], fuse([groups[top]])


def resolve_proposed(groups):
    """Draft ADR-0009: largest pairwise-consistent subset; ties by trust order.

    Returns kept groups, rejected groups, whether it blocks (a non-magnetic
    group was rejected), and the fused (yaw, sigma).
    """
    names = list(groups)
    for k in range(len(names), 0, -1):
        ok = [s for s in itertools.combinations(names, k)
              if not conflicting_pairs({g: groups[g] for g in s})]
        if ok:
            kept = min(ok, key=lambda s: sorted(TRUST.index(g) for g in s))
            rejected = [g for g in names if g not in kept]
            blocking = any(g != "magnetic" for g in rejected)
            return list(kept), rejected, blocking, fuse([groups[g] for g in kept])


def main():
    print("== #4 circular wrap: docs/03 example, solar 359±2 vs map 2±4")
    thr = 3 * math.sqrt(2**2 + 4**2)
    print(f"  literal |359-2| = {abs(359 - 2)}   circular = {cdiff(359, 2)}   threshold = {thr:.1f}")

    print("== #1 delta sign: AR reference axis points east (true azimuth beta = 90)")
    beta = 90
    delta_by_prose = (0 - beta) % 360  # CW angle FROM reference axis TO north
    print(f"  delta per prose = {delta_by_prose}; ray along reference axis -> "
          f"az_ar + delta = {(0 + delta_by_prose) % 360}, truth = {beta}")
    for b in (0, 10, 45, 90, 180):
        print(f"  session heading beta = {b:>3} -> heading error if prose is followed = {(2 * b) % 360}")

    print("== #2 asin on the unnormalized ray (image top edge, tan 30deg = 0.577)")
    t = math.tan(math.radians(30))
    for pitch in (0, 30, 60):
        p = math.radians(pitch)
        dy = t * math.cos(p) + math.sin(p)  # z = 1 ray rotated up by pitch
        true_alt = math.degrees(math.asin(dy / math.sqrt(t * t + 1)))
        naive = "NaN" if abs(dy) > 1 else f"{math.degrees(math.asin(dy)):.1f}"
        print(f"  pitch = {pitch:>2}: d_y = {dy:.3f}   asin(d_y) = {naive:>5}   true alt = {true_alt:.1f}")

    print("== #3 atan2(d_x, d_z) in ARKit gravityAndHeading (+X east, +Y up, +Z south)")
    for name, d in {"N": (0, 0, -1), "E": (1, 0, 0), "S": (0, 0, 1), "W": (-1, 0, 0)}.items():
        a = math.degrees(math.atan2(d[0], d[2])) % 360
        b = math.degrees(math.atan2(d[0], -d[2])) % 360
        print(f"  {name}: atan2(dx, dz) = {a:5.1f}   atan2(dx, -dz) = {b:5.1f}")

    cases = {
        "#5 magnetic outlier (review example)": {"solar": (1, 2), "map": (3, 4), "magnetic": (40, 8)},
        "#5 wrong solar vs agreeing map+vps (fictional)": {"solar": (20, 2), "vps": (3, 3), "map": (2, 4)},
        "#7 docs/03 example as written (sigma_mag 8)": {"magnetic": (8, 8), "map": (2, 4), "solar": (359, 2)},
        "#7 docs/03 example, sigma_mag = heading_accuracy 12": {"magnetic": (8, 12), "map": (2, 4), "solar": (359, 2)},
    }
    for label, groups in cases.items():
        print(f"== {label}")
        for gi, gj in itertools.combinations(groups, 2):
            (yi, si), (yj, sj) = groups[gi], groups[gj]
            d, th = cdiff(yi, yj), 3 * math.sqrt(si**2 + sj**2)
            print(f"  {gi}-{gj}: diff = {d:g}   threshold = {th:.1f}   conflict = {d > th}")
        kept, rej, fused = resolve_current(groups)
        print(f"  current rule : kept = {kept}  rejected = {rej}  fused = {fused}")
        kept, rej, blocking, fused = resolve_proposed(groups)
        print(f"  proposed rule: kept = {kept}  rejected = {rej}  blocking = {blocking}  fused = {fused}")

    print("== #7 other fusion subsets of the docs/03 example (doc claims yaw 0.6, sigma 2.4)")
    print("  map + solar only :", fuse([(2, 4), (359, 2)]))


if __name__ == "__main__":
    main()
