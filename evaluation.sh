#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<EOF
Usage:
  ./evaluation.sh [options]

Options:
  --hydra-ws-dir PATH            Hydra workspace folder
                                 default: /home/abcd0/hydra_ws

  --hydra-repo-dir PATH          Hydra repo folder
                                 default: auto-detect from:
                                          /home/abcd0/hydra_ws/src/hydra
                                          /home/abcd0/hydra_ws/src/Hydra

  --tum-dir PATH                 tum folder
                                 default: /home/abcd0/tum

  --venv-dir PATH                venv folder
                                 default: /home/abcd0/venvs/evo_eval

  --backend-dir PATH             backend folder
                                 default: /home/abcd0/.hydra/uhumans2/backend

  --gt-bag-dir PATH              ROS2 bag folder for GT
                                 default: /home/abcd0/datasets/uhumans2/office_ros2

  --gt-topic TOPIC               GT topic in rosbag
                                 default: /tesse/odom

  --gt-name FILENAME             GT tum filename
                                 default: tesse_odom.tum

  --est-name FILENAME            estimated tum filename
                                 default: hydra_est.tum

  --official-eval-results-dir P  results dir for official hydra-eval
                                 default: <backend-dir>

  --skip-official-eval           skip running official hydra-eval
  --force-reinstall              pass through to evaluation_setup.sh
  --force-regenerate-gt          pass through to evaluation_setup.sh
  -h, --help                     show this help
EOF
}

abspath() {
    python3 - "$1" <<'PY'
import os, sys
print(os.path.abspath(sys.argv[1]))
PY
}

# ---------------- defaults ----------------
HYDRA_WS_DIR="/home/abcd0/hydra_ws"
HYDRA_REPO_DIR=""
TUM_DIR="/home/abcd0/tum"
VENV_DIR="/home/abcd0/venvs/evo_eval"
BACKEND_DIR="/home/abcd0/.hydra/uhumans2/backend"
GT_BAG_DIR="/home/abcd0/datasets/uhumans2/office_ros2"
GT_TOPIC="/tesse/odom"
GT_NAME="tesse_odom.tum"
EST_NAME="hydra_est.tum"
OFFICIAL_EVAL_RESULTS_DIR=""
RUN_OFFICIAL_EVAL=1

FORCE_REINSTALL=0
FORCE_REGENERATE_GT=0

# ---------------- parse args ----------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --hydra-ws-dir)
            HYDRA_WS_DIR="$2"
            shift 2
            ;;
        --hydra-repo-dir)
            HYDRA_REPO_DIR="$2"
            shift 2
            ;;
        --tum-dir)
            TUM_DIR="$2"
            shift 2
            ;;
        --venv-dir)
            VENV_DIR="$2"
            shift 2
            ;;
        --backend-dir)
            BACKEND_DIR="$2"
            shift 2
            ;;
        --gt-bag-dir)
            GT_BAG_DIR="$2"
            shift 2
            ;;
        --gt-topic)
            GT_TOPIC="$2"
            shift 2
            ;;
        --gt-name)
            GT_NAME="$2"
            shift 2
            ;;
        --est-name)
            EST_NAME="$2"
            shift 2
            ;;
        --official-eval-results-dir)
            OFFICIAL_EVAL_RESULTS_DIR="$2"
            shift 2
            ;;
        --skip-official-eval)
            RUN_OFFICIAL_EVAL=0
            shift
            ;;
        --force-reinstall)
            FORCE_REINSTALL=1
            shift
            ;;
        --force-regenerate-gt)
            FORCE_REGENERATE_GT=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1"
            usage
            exit 1
            ;;
    esac
done

# ---------------- resolve paths ----------------
HYDRA_WS_DIR="$(abspath "$HYDRA_WS_DIR")"
TUM_DIR="$(abspath "$TUM_DIR")"
VENV_DIR="$(abspath "$VENV_DIR")"
BACKEND_DIR="$(abspath "$BACKEND_DIR")"
GT_BAG_DIR="$(abspath "$GT_BAG_DIR")"

if [[ -z "$HYDRA_REPO_DIR" ]]; then
    if [[ -d "$HYDRA_WS_DIR/src/hydra" ]]; then
        HYDRA_REPO_DIR="$HYDRA_WS_DIR/src/hydra"
    elif [[ -d "$HYDRA_WS_DIR/src/Hydra" ]]; then
        HYDRA_REPO_DIR="$HYDRA_WS_DIR/src/Hydra"
    else
        HYDRA_REPO_DIR="$HYDRA_WS_DIR/src/hydra"
    fi
fi
HYDRA_REPO_DIR="$(abspath "$HYDRA_REPO_DIR")"

if [[ -z "$OFFICIAL_EVAL_RESULTS_DIR" ]]; then
    OFFICIAL_EVAL_RESULTS_DIR="$BACKEND_DIR"
fi
OFFICIAL_EVAL_RESULTS_DIR="$(abspath "$OFFICIAL_EVAL_RESULTS_DIR")"

GT_TUM_FILE="$TUM_DIR/$GT_NAME"
HYDRA_TUM_FILE="$TUM_DIR/$EST_NAME"
TRAJ_CSV="$BACKEND_DIR/trajectory.csv"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SCRIPT="$SCRIPT_DIR/evaluation_setup.sh"

if [[ ! -f "$SETUP_SCRIPT" && -f "$SCRIPT_DIR/evaluatoin_setup.sh" ]]; then
    SETUP_SCRIPT="$SCRIPT_DIR/evaluatoin_setup.sh"
fi

# ---------------- print config ----------------
echo "=========================================="
echo "evaluation.sh"
echo "hydra_ws_dir           : $HYDRA_WS_DIR"
echo "hydra_repo_dir         : $HYDRA_REPO_DIR"
echo "tum_dir                : $TUM_DIR"
echo "venv_dir               : $VENV_DIR"
echo "backend_dir            : $BACKEND_DIR"
echo "gt_bag_dir             : $GT_BAG_DIR"
echo "gt_topic               : $GT_TOPIC"
echo "gt_tum_file            : $GT_TUM_FILE"
echo "hydra_tum              : $HYDRA_TUM_FILE"
echo "official_eval_results  : $OFFICIAL_EVAL_RESULTS_DIR"
echo "=========================================="

# ---------------- setup args ----------------
SETUP_ARGS=(
    --hydra-ws-dir "$HYDRA_WS_DIR"
    --hydra-repo-dir "$HYDRA_REPO_DIR"
    --tum-dir "$TUM_DIR"
    --venv-dir "$VENV_DIR"
    --backend-dir "$BACKEND_DIR"
    --gt-bag-dir "$GT_BAG_DIR"
    --gt-topic "$GT_TOPIC"
    --gt-name "$GT_NAME"
)

if [[ $RUN_OFFICIAL_EVAL -eq 0 ]]; then
    SETUP_ARGS+=(--skip-official-eval)
fi

if [[ $FORCE_REINSTALL -eq 1 ]]; then
    SETUP_ARGS+=(--force-reinstall)
fi

if [[ $FORCE_REGENERATE_GT -eq 1 ]]; then
    SETUP_ARGS+=(--force-regenerate-gt)
fi

# ---------------- maybe run setup ----------------
if [[ ! -f "$SETUP_SCRIPT" ]]; then
    echo "Error: setup script not found: $SETUP_SCRIPT"
    exit 1
fi

NEED_SETUP=0

if [[ ! -x "$VENV_DIR/bin/evo_ape" || ! -x "$VENV_DIR/bin/evo_rpe" || ! -x "$VENV_DIR/bin/evo_traj" ]]; then
    NEED_SETUP=1
fi

if [[ $RUN_OFFICIAL_EVAL -eq 1 ]]; then
    if [[ ! -d "$HYDRA_REPO_DIR/eval/python/hydra_eval" ]]; then
        NEED_SETUP=1
    fi
fi

if [[ ! -f "$GT_TUM_FILE" ]]; then
    NEED_SETUP=1
fi

if [[ $FORCE_REINSTALL -eq 1 || $FORCE_REGENERATE_GT -eq 1 ]]; then
    NEED_SETUP=1
fi

if [[ $NEED_SETUP -eq 1 ]]; then
    echo "Running evaluation_setup.sh ..."
    bash "$SETUP_SCRIPT" "${SETUP_ARGS[@]}"
else
    echo "Setup already satisfied. Skipping evaluation_setup.sh"
fi

# ---------------- checks ----------------
if [[ ! -d "$BACKEND_DIR" ]]; then
    echo "Error: backend directory not found: $BACKEND_DIR"
    exit 1
fi

if [[ ! -f "$TRAJ_CSV" ]]; then
    echo "Error: trajectory.csv not found: $TRAJ_CSV"
    exit 1
fi

if [[ ! -f "$GT_TUM_FILE" ]]; then
    echo "Error: GT TUM file not found: $GT_TUM_FILE"
    exit 1
fi

if [[ ! -x "$VENV_DIR/bin/evo_ape" || ! -x "$VENV_DIR/bin/evo_rpe" ]]; then
    echo "Error: evo commands not found under: $VENV_DIR/bin"
    exit 1
fi

mkdir -p "$TUM_DIR"

# ---------------- print final active node counts ----------------
"$VENV_DIR/bin/python" - <<PY
import os
import pandas as pd

backend_dir = r"${BACKEND_DIR}"

names = {
    2: "Objects (possibly includes agent)",
    3: "Places",
    4: "Rooms",
    5: "Buildings",
}

print("\n=== Final Active Nodes ===")
for layer in [2, 3, 4, 5]:
    csv_path = os.path.join(backend_dir, f"layer_{layer}_statistics.csv")
    if not os.path.exists(csv_path):
        print(f"Layer {layer} - {names[layer]}: file not found ({csv_path})")
        continue

    df = pd.read_csv(csv_path)

    if "nodes_active" not in df.columns or len(df) == 0:
        print(f"Layer {layer} - {names[layer]}: invalid or empty csv")
        continue

    final_active = int(df["nodes_active"].iloc[-1])
    print(f"Layer {layer} - {names[layer]}: {final_active}")
PY

# ---------------- convert hydra trajectory to TUM ----------------
"$VENV_DIR/bin/python" - <<PY
import pandas as pd

traj_csv = r"${TRAJ_CSV}"
out_path = r"${HYDRA_TUM_FILE}"

df = pd.read_csv(traj_csv)

required_cols = ["timestamp[ns]", "x", "y", "z", "qx", "qy", "qz", "qw"]
missing = [c for c in required_cols if c not in df.columns]
if missing:
    raise ValueError(f"trajectory.csv missing required columns: {missing}")

out = pd.DataFrame({
    "timestamp": df["timestamp[ns]"] / 1e9,
    "tx": df["x"],
    "ty": df["y"],
    "tz": df["z"],
    "qx": df["qx"],
    "qy": df["qy"],
    "qz": df["qz"],
    "qw": df["qw"],
})

out.to_csv(out_path, sep=" ", header=False, index=False, float_format="%.9f")
print(f"\nsaved {out_path}")
PY

# ---------------- run evo ----------------
echo
echo "=== Running APE ==="
"$VENV_DIR/bin/evo_ape" tum "$GT_TUM_FILE" "$HYDRA_TUM_FILE" -a -v

echo
echo "=== Running RPE ==="
"$VENV_DIR/bin/evo_rpe" tum "$GT_TUM_FILE" "$HYDRA_TUM_FILE" -a --delta 1 --delta_unit m --pose_relation trans_part -v

# ---------------- run official Hydra eval ----------------
if [[ $RUN_OFFICIAL_EVAL -eq 1 ]]; then
    echo
    echo "=== Running official Hydra timing eval ==="

    HYDRA_EVAL_SRC_DIR="$HYDRA_REPO_DIR/eval/python"

    if [[ ! -d "$HYDRA_EVAL_SRC_DIR/hydra_eval" ]]; then
        echo "Warning: Hydra eval source dir not found: $HYDRA_EVAL_SRC_DIR/hydra_eval"
        echo "Skipping official eval."
    elif [[ ! -d "$OFFICIAL_EVAL_RESULTS_DIR" ]]; then
        echo "Warning: official eval results dir not found: $OFFICIAL_EVAL_RESULTS_DIR"
        echo "Skipping official eval."
    else
        PYTHONPATH="$HYDRA_EVAL_SRC_DIR${PYTHONPATH:+:$PYTHONPATH}" \
            "$VENV_DIR/bin/python" -m hydra_eval timing show "$OFFICIAL_EVAL_RESULTS_DIR" || true
    fi
fi

echo
echo "Evaluation finished."