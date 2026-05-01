#!/usr/bin/env python3
import re
import json
from pathlib import Path


def parse_runs(log_text: str):
    runs = {}

    current_run = None
    in_plateau = False

    for line in log_text.splitlines():
        line = line.strip()

        # ===== detect run start =====
        m = re.match(r"=+\s+(run_\d+)\s+=+", line)
        if m:
            current_run = m.group(1)
            runs[current_run] = {
                "plateaus": [],
                "threshold": None,
                "max_lifetime": None,
                "selected_baseline": None,
            }
            continue

        if current_run is None:
            continue

        # ===== detect plateau block =====
        if "[PLATEAU] Summary:" in line:
            in_plateau = True
            continue

        if not in_plateau:
            continue

        # ===== selected_components =====
        m = re.search(r"selected_components:\s*(\d+)", line)
        if m:
            runs[current_run]["selected_baseline"] = int(m.group(1))
            continue

        # ===== threshold =====
        m = re.search(r"threshold:\s*([0-9.eE+-]+)", line)
        if m:
            runs[current_run]["threshold"] = float(m.group(1))
            continue

        # ===== max_lifetime =====
        m = re.search(r"max_lifetime:\s*([0-9.eE+-]+)", line)
        if m:
            runs[current_run]["max_lifetime"] = float(m.group(1))
            continue

        # ===== plateau entries =====
        m = re.search(r"comp=(\d+),\s*lifetime=([0-9.eE+-]+)", line)
        if m:
            runs[current_run]["plateaus"].append({
                "components": int(m.group(1)),
                "lifetime": float(m.group(2)),
            })
            continue

        # ===== end of plateau block =====
        if line.startswith("[INFO] Cleaning backend"):
            in_plateau = False
            continue

    return runs

def format_runs(runs):
    lines = ["{"]

    for run_name, run in runs.items():
        lines.append(f'  "{run_name}": {{')

        # plateaus
        lines.append('    "plateaus": [')
        for p in run["plateaus"]:
            lines.append(
                f'      {{ "components": {p["components"]}, "lifetime": {p["lifetime"]} }},'
            )
        if run["plateaus"]:
            lines[-1] = lines[-1].rstrip(",")  # remove last comma
        lines.append("    ],")

        # other fields
        lines.append(f'    "threshold": {run["threshold"]},')
        lines.append(f'    "max_lifetime": {run["max_lifetime"]},')
        lines.append(f'    "selected_baseline": {run["selected_baseline"]}')

        lines.append("  },")

    if len(lines) > 1:
        lines[-1] = lines[-1].rstrip(",")  # remove last comma

    lines.append("}")
    return "\n".join(lines)

if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("logfile", help="path to your full log file")
    parser.add_argument("--out", default="runs.json")
    args = parser.parse_args()

    text = Path(args.logfile).read_text()
    runs = parse_runs(text)

    print(format_runs(runs))
    Path(args.out).write_text(format_runs(runs))
