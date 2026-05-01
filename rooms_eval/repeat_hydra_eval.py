#!/usr/bin/env python3
import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path
import threading
import shutil
import re


RUNS = 5

ROS_SETUP = Path("/opt/ros/jazzy/setup.bash")
HYDRA_WS_SETUP = Path.home() / "hydra_ws/install/setup.bash"

BAG_PATH = Path.home() / "datasets/uhumans2/office_scene/office_ros2_00h_v2"
QOS_OVERRIDES = Path.home() / ".tf_overrides.yaml"
EVO_VENV_ACTIVATE = Path.home() / "datasets/evo_venv/bin/activate"

HYDRA_LAUNCH_PKG = "hydra_ros"
HYDRA_LAUNCH_FILE = "uhumans2.launch.yaml"

RESULT_ROOT = Path.home() / "hydra_repeat_results"
EVAL_SCRIPT = Path(__file__).resolve().parent / "evaluate_hydra_run.py"

POST_BAG_WAIT_SEC = 5
HYDRA_START_WAIT_SEC = 8




def run_bash_background(cmd: str, stdout_path: Path, stderr_path: Path) -> subprocess.Popen:
    stdout_f = open(stdout_path, "w")
    stderr_f = open(stderr_path, "w")
    proc = subprocess.Popen(
        ["bash", "-lc", cmd],
        stdout=stdout_f,
        stderr=stderr_f,
        preexec_fn=os.setsid,
    )
    proc._stdout_file = stdout_f  # type: ignore[attr-defined]
    proc._stderr_file = stderr_f  # type: ignore[attr-defined]
    return proc


def close_proc_files(proc: subprocess.Popen) -> None:
    for attr in ("_stdout_file", "_stderr_file"):
        f = getattr(proc, attr, None)
        if f:
            f.close()


def stop_process_group(proc: subprocess.Popen, name: str) -> None:
    if proc.poll() is not None:
        close_proc_files(proc)
        return

    try:
        os.killpg(os.getpgid(proc.pid), signal.SIGINT)
        proc.wait(timeout=20)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
            proc.wait(timeout=5)

    close_proc_files(proc)


def print_run_summary(summary_path: Path) -> None:
    if not summary_path.exists():
        print(f"[WARN] Missing summary file: {summary_path}")
        return

    with open(summary_path, "r") as f:
        summary = json.load(f)

    print("Run summary:")
    for k, v in summary.items():
        print(f"  {k}: {v}")


def parse_last_plateau_block(log_path: Path) -> dict | None:
    if not log_path.exists():
        return None

    lines = log_path.read_text().splitlines()

    # 找最後一個 Sequences
    start_idx = None
    for i in range(len(lines) - 1, -1, -1):
        if "[getBestPlateau] Sequences:" in lines[i]:
            start_idx = i
            break

    if start_idx is None:
        return None

    # 找結尾（Best threshold）
    end_idx = None
    for i in range(start_idx, len(lines)):
        if "[RoomFinder] Best threshold" in lines[i]:
            end_idx = i
            break

    if end_idx is None:
        return None

    block = lines[start_idx:end_idx + 1]

    plateaus = []
    threshold = None
    max_lifetime = None
    selected_components = None

    for line in block:
        # plateau line
        m = re.search(r"- \d+: (\d+) -> .* lifetime=([0-9.eE+-]+)", line)
        if m:
            plateaus.append({
                "components": int(m.group(1)),
                "lifetime": float(m.group(2)),
            })

        # threshold line
        m = re.search(r"Max lifetime: ([0-9.eE+-]+).*Threshold: ([0-9.eE+-]+)", line)
        if m:
            max_lifetime = float(m.group(1))
            threshold = float(m.group(2))

        # final selection
        m = re.search(r"Best threshold: .* \((\d+) components\)", line)
        if m:
            selected_components = int(m.group(1))

    return {
        "plateaus": plateaus,
        "threshold": threshold,
        "max_lifetime": max_lifetime,
        "selected_components": selected_components,
    }


def main() -> int:
    stop_flag = False
    def handle_sigint(signum, frame):
        nonlocal stop_flag
        print("\n[INFO] Ctrl+C received, stopping after current step...")
        stop_flag = True

    signal.signal(signal.SIGINT, handle_sigint)


    RESULT_ROOT.mkdir(parents=True, exist_ok=True)
    all_runs = []

    backend_dir = Path.home() / ".hydra/uhumans2/backend"
    for i in range(1, RUNS + 1):
        if backend_dir.exists():
            print("[INFO] Cleaning backend directory...")
            shutil.rmtree(backend_dir)
        hydra_proc = None
        bag_proc = None
        try:
            if stop_flag:
                print("[INFO] Stopping remaining runs.")
                break
            run_name = f"run_{i:02d}"
            run_dir = RESULT_ROOT / run_name
            run_dir.mkdir(parents=True, exist_ok=True)

            print(f"\n========== {run_name} ==========")

            hydra_cmd = f"""
            source "{ROS_SETUP}"
            source "{HYDRA_WS_SETUP}"
            /usr/bin/time -v ros2 launch {HYDRA_LAUNCH_PKG} {HYDRA_LAUNCH_FILE}
            """.strip()

            bag_cmd = f"""
            source "{ROS_SETUP}"
            source "{HYDRA_WS_SETUP}"
            /usr/bin/time -v ros2 bag play "{BAG_PATH}" --clock --qos-profile-overrides-path "{QOS_OVERRIDES}"
            """.strip()

            hydra_proc = run_bash_background(
                hydra_cmd,
                run_dir / "hydra_stdout.log",
                run_dir / "hydra_stderr.log",
            )
            print(f"[INFO] Started Hydra pid={hydra_proc.pid}")
            time.sleep(HYDRA_START_WAIT_SEC)

            bag_proc = run_bash_background(
                bag_cmd,
                run_dir / "bag_stdout.log",
                run_dir / "bag_stderr.log",
            )
            print(f"[INFO] Started bag play pid={bag_proc.pid}")

            try:
                bag_rc = bag_proc.wait()
            except KeyboardInterrupt:
                print("[INFO] Interrupted during bag play")
                stop_process_group(bag_proc, "bag")
                stop_process_group(hydra_proc, "hydra")
                return 1

            close_proc_files(bag_proc)
            print(f"[INFO] Bag play finished rc={bag_rc}")

            time.sleep(POST_BAG_WAIT_SEC)
            print("[INFO] Stopping Hydra...")
            stop_process_group(hydra_proc, "hydra")


            ######## running evaluation ########
            print("[INFO] Running evaluation...")
            eval_cmd = [
                str(Path.home() / "datasets/evo_venv/bin/python"),
                str(EVAL_SCRIPT),
                "--run-dir", str(run_dir),
            ]

            eval_proc = subprocess.run(
                eval_cmd,
                capture_output=True,
                text=True,
            )
            try:
                eval_proc = subprocess.run(eval_cmd, capture_output=True, text=True)
            except KeyboardInterrupt:
                print("[INFO] Interrupted during evaluation")
                return 1

            (run_dir / "evaluation_stdout.log").write_text(eval_proc.stdout)
            (run_dir / "evaluation_stderr.log").write_text(eval_proc.stderr)

            if eval_proc.returncode != 0:
                print("[ERROR] Evaluation failed")
                print(eval_proc.stderr)
                continue

            print(eval_proc.stdout.strip())

            summary_path = run_dir / "run_summary.json"
            print_run_summary(summary_path)

            if summary_path.exists():
                with open(summary_path, "r") as f:
                    s = json.load(f)
                s["run"] = run_name
                all_runs.append(s)

            plateau_data = parse_last_plateau_block(run_dir / "hydra_stdout.log")
            if plateau_data:
                print("[PLATEAU] Summary:")
                print(f"  selected_components: {plateau_data['selected_components']}")
                print(f"  threshold: {plateau_data['threshold']:.6f}")
                print(f"  max_lifetime: {plateau_data['max_lifetime']:.6f}")

                # optional: show top candidates
                sorted_plateaus = sorted(
                    plateau_data["plateaus"],
                    key=lambda x: x["lifetime"],
                    reverse=True
                )

                print("  ranked lifetimes:")
                for p in sorted_plateaus:
                    print(f"    comp={p['components']}, lifetime={p['lifetime']:.6f}")

        finally:
            if bag_proc:
                stop_process_group(bag_proc, "bag")

            if hydra_proc:
                stop_process_group(hydra_proc, "hydra")

    if all_runs:
        print("\n========== All runs ==========")
        for row in all_runs:
            print(
                f"{row['run']}: "
                f"rooms={row.get('rooms_final')}, "
                f"ape_rmse={row.get('ape_rmse')}, "
                f"rpe_rmse={row.get('rpe_rmse')}"
            )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())