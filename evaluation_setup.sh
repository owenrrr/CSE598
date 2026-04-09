#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<EOF
Usage:
  ./evaluation_setup.sh [options]

Options:
  --hydra-ws-dir PATH            Hydra workspace folder
                                 default: /home/abcd0/hydra_ws

  --hydra-repo-dir PATH          Hydra repo folder
                                 default: auto-detect from:
                                          /home/abcd0/hydra_ws/src/hydra
                                          /home/abcd0/hydra_ws/src/Hydra

  --tum-dir PATH                 TUM output folder
                                 default: /home/abcd0/tum

  --venv-dir PATH                evo / hydra-eval virtual environment folder
                                 default: /home/abcd0/venvs/evo_eval

  --backend-dir PATH             backend folder
                                 default: /home/abcd0/.hydra/uhumans2/backend
                                 (kept for interface compatibility)

  --gt-bag-dir PATH              ROS2 bag folder for GT
                                 default: /home/abcd0/datasets/uhumans2/office_ros2

  --gt-topic TOPIC               GT topic in rosbag
                                 default: /tesse/odom

  --gt-name FILENAME             GT TUM filename
                                 default: tesse_odom.tum

  --force-reinstall              recreate venv and reinstall packages
  --force-regenerate-gt          recreate GT TUM even if it already exists
  --skip-official-eval           skip installing official hydra-eval package
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

FORCE_REINSTALL=0
FORCE_REGENERATE_GT=0
INSTALL_OFFICIAL_EVAL=1

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
        --force-reinstall)
            FORCE_REINSTALL=1
            shift
            ;;
        --force-regenerate-gt)
            FORCE_REGENERATE_GT=1
            shift
            ;;
        --skip-official-eval)
            INSTALL_OFFICIAL_EVAL=0
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

# ---------------- normalize paths ----------------
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

GT_TUM_FILE="$TUM_DIR/$GT_NAME"
HYDRA_EVAL_PKG_DIR="$HYDRA_REPO_DIR/eval"

mkdir -p "$TUM_DIR"

echo "=========================================="
echo "Setup for Hydra evaluation"
echo "hydra_ws_dir      : $HYDRA_WS_DIR"
echo "hydra_repo_dir    : $HYDRA_REPO_DIR"
echo "tum_dir           : $TUM_DIR"
echo "venv_dir          : $VENV_DIR"
echo "backend_dir       : $BACKEND_DIR"
echo "gt_bag_dir        : $GT_BAG_DIR"
echo "gt_topic          : $GT_TOPIC"
echo "gt_tum_file       : $GT_TUM_FILE"
echo "official_eval_pkg : $HYDRA_EVAL_PKG_DIR"
echo "=========================================="

# ---------------------------------------------------------
# 1. create or recreate venv
# ---------------------------------------------------------
if [[ $FORCE_REINSTALL -eq 1 && -d "$VENV_DIR" ]]; then
    echo "[1/4] --force-reinstall set, removing existing venv..."
    rm -rf "$VENV_DIR"
fi

if [[ ! -d "$VENV_DIR" ]]; then
    echo "[1/4] Creating venv..."
    python3 -m venv "$VENV_DIR"
else
    echo "[1/4] venv already exists, skipping creation."
fi

# ---------------------------------------------------------
# 2. install/update evo
# ---------------------------------------------------------
if [[ $FORCE_REINSTALL -eq 1 || ! -x "$VENV_DIR/bin/evo_traj" || ! -x "$VENV_DIR/bin/evo_ape" || ! -x "$VENV_DIR/bin/evo_rpe" ]]; then
    echo "[2/4] Installing/updating evo..."
    "$VENV_DIR/bin/python" -m pip install -U pip setuptools wheel
    "$VENV_DIR/bin/python" -m pip install -U evo
else
    echo "[2/4] evo already available, skipping install."
fi

if [[ ! -x "$VENV_DIR/bin/evo_traj" ]]; then
    echo "Error: evo_traj not found under: $VENV_DIR/bin"
    exit 1
fi

# ---------------------------------------------------------
# 3. install official hydra-eval package
# ---------------------------------------------------------
if [[ $INSTALL_OFFICIAL_EVAL -eq 1 ]]; then
    if [[ ! -d "$HYDRA_EVAL_PKG_DIR" ]]; then
        echo "[3/4] Warning: Hydra eval directory not found: $HYDRA_EVAL_PKG_DIR"
        echo "      Skipping official Hydra eval dependency install."
    else
        echo "[3/4] Installing official Hydra eval dependencies..."
        "$VENV_DIR/bin/python" -m pip install -U click tqdm matplotlib pandas seaborn
    fi
else
    echo "[3/4] Official Hydra eval dependency install skipped by user."
fi

# ---------------------------------------------------------
# 4. create GT TUM if needed
# ---------------------------------------------------------
if [[ $FORCE_REGENERATE_GT -eq 1 && -f "$GT_TUM_FILE" ]]; then
    echo "[4/4] --force-regenerate-gt set, removing existing GT TUM..."
    rm -f "$GT_TUM_FILE"
fi

if [[ -f "$GT_TUM_FILE" ]]; then
    echo "[4/4] GT TUM already exists, skipping creation."
    echo "Done."
    exit 0
fi

if [[ ! -d "$GT_BAG_DIR" ]]; then
    echo "Error: GT bag directory not found: $GT_BAG_DIR"
    exit 1
fi

if [[ ! -f "$GT_BAG_DIR/metadata.yaml" ]]; then
    echo "Error: metadata.yaml not found under GT bag directory: $GT_BAG_DIR"
    echo "This path must point to the ROS2 bag folder itself."
    exit 1
fi

echo "[4/4] Creating GT TUM from ROS2 bag..."

TMP_EXPORT_DIR="$(mktemp -d)"
cleanup() {
    rm -rf "$TMP_EXPORT_DIR"
}
trap cleanup EXIT

pushd "$TMP_EXPORT_DIR" >/dev/null
"$VENV_DIR/bin/evo_traj" bag2 "$GT_BAG_DIR" "$GT_TOPIC" --save_as_tum

GENERATED_TUM="$(find . -maxdepth 1 -type f -name "*.tum" | head -n 1 || true)"
if [[ -z "$GENERATED_TUM" ]]; then
    echo "Error: evo_traj did not generate any .tum file."
    exit 1
fi

mv "$GENERATED_TUM" "$GT_TUM_FILE"
popd >/dev/null

echo "Created GT TUM: $GT_TUM_FILE"
echo "Done."