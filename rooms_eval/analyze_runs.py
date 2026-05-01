#!/usr/bin/env python3
import json
import subprocess
import numpy as np


# ===== Step 1: call parse_result.py =====
def load_runs(logfile):
    proc = subprocess.run(
        ["python3", "parse_results.py", logfile],
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(proc.stdout)


# ===== Step 2: collapse duplicates =====
def collapse_plateaus(plateaus):
    best = {}
    for p in plateaus:
        c = p["components"]
        if c not in best or p["lifetime"] > best[c]:
            best[c] = p["lifetime"]

    return [{"components": c, "lifetime": l} for c, l in best.items()]

def collapse_plateaus_grouped(plateaus):
    """
    Try to combine the lifetime of different plateaus with same num_components
    Insight:
    """
    grouped = {}

    for p in plateaus:
        c = p["components"]
        if c not in grouped:
            grouped[c] = p["lifetime"]
        else:
            grouped[c] += p["lifetime"]

    return [{"components": c, "lifetime": l} for c, l in grouped.items()]


# ===== Step 3: stats =====
def compute_stats(plateaus):
    comps = np.array([p["components"] for p in plateaus])
    lifes = np.array([p["lifetime"] for p in plateaus])

    stats = {
        "components_mean": comps.mean(),
        "components_std": comps.std(),
        "lifetime_mean": lifes.mean(),
        "lifetime_std": lifes.std(),
    }

    # correlation
    if len(comps) > 1:
        stats["corr_comp_lifetime"] = np.corrcoef(comps, lifes)[0, 1]
    else:
        stats["corr_comp_lifetime"] = None

    return stats

def select_new_weighted(run, component_weight=2.0, lifetime_weight=1.0, alpha=1):

    plateaus = collapse_plateaus(run["plateaus"])
    # plateaus = collapse_plateaus_grouped(run["plateaus"])

    max_lifetime = max(p["lifetime"] for p in plateaus)

    max_c = max(x["components"] for x in plateaus)

    def score(p):
        norm_l = p["lifetime"] / max_lifetime if max_lifetime > 0 else 0
        norm_c = p["components"] / max_c

        base_score = component_weight*norm_c + lifetime_weight*norm_l
        print(f"[score] norm_l={norm_l}")


        # penalty for deviation from the mean component count
        # deviation_penalty = 0.8 * abs(p["components"] - mean_c)
        deviation_penalty = 0

        final_score = base_score - deviation_penalty

        print(f"[score] comp={p['components']}, base={base_score:.3f}, penalty={deviation_penalty:.3f}, final={final_score:.3f}")

        return final_score

    best = max(plateaus, key=score)

    return best["components"], score(best)


if __name__ == "__main__":
    runs = load_runs("runs.log")

    ori_results = []
    new_results = []
    for name, run in runs.items():
        # print(run)
        plateaus = collapse_plateaus(run["plateaus"])
        stats = compute_stats(plateaus)

        print(f"\n================ {name} ================")
        print(f"plateaus:")
        # for plt in run["plateaus"]:
        for plt in plateaus:
            print(plt)
        
        # stats of lifetime and components
        print("lifetime   :", end="")
        print(f"  mean={stats['lifetime_mean']:.6f}", end="")
        print(f"  std ={stats['lifetime_std']:.6f}")

        print("components :", end="")
        print(f"  mean={stats['components_mean']:.6f}", end="")
        print(f"  std ={stats['components_std']:.6f}")

        print(f"corr(comp, lifetime): {stats['corr_comp_lifetime']:.3f}")


        # original calculation
        print("## original :", end="")
        print(f"   threshold: {run['threshold']:.6f}", end="")
        print(f"   component: {run['selected_baseline']}")
        ori_results.append(run['selected_baseline'])


        # new calculation
        new_comp, new_score = select_new_weighted(run)
        print("##    new   :", end="")
        if new_comp is not None:
            print(f"   component: {new_comp}", end="")
            print(f"   score: {new_score:.4f}")
        else:
            print("   no valid plateau")
        new_results.append(new_comp)

    print("---- stats ----")
    print("ori_results: ", ori_results)
    print("new_results: ", new_results)

