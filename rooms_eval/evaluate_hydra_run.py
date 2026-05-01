#!/usr/bin/env python3
import argparse
import json
import re
import shutil
import subprocess
from pathlib import Path

import pandas as pd

DATASET_DIR = Path.home() / "datasets"
EVO_VENV_ACTIVATE = DATASET_DIR / "evo_venv/bin/activate"
GT_TUM = DATASET_DIR / "tesse_odom.tum"
HYDRA_BACKEND_DIR = Path.home() / ".hydra/uhumans2/backend"


def run_bash(cmd: str, capture_output: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["bash", "-lc", cmd],
        capture_output=capture_output,
        text=True,
        check=True,
    )


def convert_hydra_traj_to_tum(dst: Path) -> int:
    src = HYDRA_BACKEND_DIR / "trajectory.csv"
    if not src.exists():
      raise FileNotFoundError(f"Missing trajectory file: {src}")

    df = pd.read_csv(src)

    ts_col = None
    for cand in ["timestamp [ns]", "timestamp[ns]"]:
        if cand in df.columns:
            ts_col = cand
            break
    if ts_col is None:
        raise KeyError(f"Cannot find timestamp column in {list(df.columns)}")

    out = pd.DataFrame({
        "timestamp": df[ts_col] / 1e9,
        "tx": df["x"],
        "ty": df["y"],
        "tz": df["z"],
        "qx": df["qx"],
        "qy": df["qy"],
        "qz": df["qz"],
        "qw": df["qw"],
    })

    out.to_csv(dst, sep=" ", header=False, index=False, float_format="%.9f")
    return len(out)


def extract_metric(log_text: str, metric_name: str):
    m = re.search(rf"^\s*{metric_name}\s+([0-9.eE+-]+)\s*$", log_text, re.MULTILINE)
    return float(m.group(1)) if m else None


def run_ape(gt_tum: Path, est_tum: Path) -> tuple[str, float | None, float | None]:
    cmd = f"""
    source "{EVO_VENV_ACTIVATE}"
    evo_ape tum "{gt_tum}" "{est_tum}" -a -v
    """.strip()
    proc = run_bash(cmd)
    text = proc.stdout + ("\n" + proc.stderr if proc.stderr else "")
    return text, extract_metric(text, "rmse"), extract_metric(text, "mean")


def run_rpe(gt_tum: Path, est_tum: Path) -> tuple[str, float | None, float | None]:
    cmd = f"""
    source "{EVO_VENV_ACTIVATE}"
    evo_rpe tum "{gt_tum}" "{est_tum}" -a --delta 1 --delta_unit m --pose_relation trans_part -v
    """.strip()
    proc = run_bash(cmd)
    text = proc.stdout + ("\n" + proc.stderr if proc.stderr else "")
    return text, extract_metric(text, "rmse"), extract_metric(text, "mean")


def get_layer_stats() -> dict:
    names = {
        2: "Objects",
        3: "Places",
        4: "Rooms",
        5: "Buildings",
    }

    result = {}
    for layer in [2, 3, 4, 5]:
        path = HYDRA_BACKEND_DIR / f"layer_{layer}_statistics.csv"
        if not path.exists():
            result[f"layer_{layer}_final_nodes_active"] = None
            continue
        df = pd.read_csv(path)
        result[f"layer_{layer}_final_nodes_active"] = int(df["nodes_active"].iloc[-1])

    result["rooms_final"] = result.get("layer_4_final_nodes_active")
    result["layer_names"] = names
    return result


def copy_backend(run_dir: Path) -> None:
    dst = run_dir / "backend_copy"
    dst.mkdir(parents=True, exist_ok=True)
    for item in HYDRA_BACKEND_DIR.iterdir():
        target = dst / item.name
        if item.is_dir():
            shutil.copytree(item, target, dirs_exist_ok=True)
        else:
            shutil.copy2(item, target)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-dir", required=True)
    args = parser.parse_args()

    run_dir = Path(args.run_dir)
    run_dir.mkdir(parents=True, exist_ok=True)

    hydra_est_tum = run_dir / "hydra_est.tum"

    rows = convert_hydra_traj_to_tum(hydra_est_tum)
    ape_text, ape_rmse, ape_mean = run_ape(GT_TUM, hydra_est_tum)
    rpe_text, rpe_rmse, rpe_mean = run_rpe(GT_TUM, hydra_est_tum)
    layer_stats = get_layer_stats()
    copy_backend(run_dir)

    (run_dir / "ape.log").write_text(ape_text)
    (run_dir / "rpe.log").write_text(rpe_text)

    summary = {
        "trajectory_rows": rows,
        "ape_rmse": ape_rmse,
        "ape_mean": ape_mean,
        "rpe_rmse": rpe_rmse,
        "rpe_mean": rpe_mean,
        **layer_stats,
    }

    (run_dir / "run_summary.json").write_text(json.dumps(summary, indent=2))

    print("Evaluation done.")
    print(f"  trajectory_rows: {rows}")
    print(f"  ape_rmse: {ape_rmse}")
    print(f"  rpe_rmse: {rpe_rmse}")
    print(f"  rooms_final: {summary.get('rooms_final')}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())