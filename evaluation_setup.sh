#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# evaluation_setup.sh
#
# Responsibilities:
#   1. create evo virtual environment if needed
#   2. install/update evo if needed
#   3. create GT TUM file from ROS2 bag if missing
#
# Usage:
#   ./evaluation_setup.sh [GT_TUM_FILE] [GT_BAG_DIR]
#
# Example:
#   ./evaluation_setup.sh \
#     /home/abcd0/.hydra/uhumans2/tesse_odom.tum \
#     /home/abcd0/hydra_ws/src/hydra_ros/datasets/uhumans2/office_ros2
# =========================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GT_TUM_FILE_INPUT="${1:-/home/abcd0/.hydra/uhumans2/tesse_odom.tum}"
GT_BAG_DIR_INPUT="${2:-$SCRIPT_DIR/../datasets/uhumans2/office_ros2}"
GT_TOPIC="${GT_TOPIC:-/tesse/odom}"

VENV_DIR="${SCRIPT_DIR}/evo_venv"

GT_TUM_FILE="$(python3 - <<PY
import os
print(os.path.abspath(r'''$GT_TUM_FILE_INPUT'''))
PY
)"

GT_BAG_DIR="$(python3 - <<PY
import os
print(os.path.abspath(r'''$GT_BAG_DIR_INPUT'''))
PY
)"

mkdir -p "$(dirname "$GT_TUM_FILE")"

echo "=========================================="
echo "Setup for Hydra evaluation"
echo "GT TUM file : $GT_TUM_FILE"
echo "GT bag dir  : $GT_BAG_DIR"
echo "GT topic    : $GT_TOPIC"
echo "Venv dir    : $VENV_DIR"
echo "=========================================="

# ---------------------------------------------------------
# 1. create venv if missing
# ---------------------------------------------------------
if [[ ! -d "$VENV_DIR" ]]; then
    echo "[1/3] Creating venv..."
    python3 -m venv "$VENV_DIR"
else
    echo "[1/3] venv already exists, skipping."
fi

# ---------------------------------------------------------
# 2. install/update evo
# ---------------------------------------------------------
echo "[2/3] Installing/updating evo..."
"$VENV_DIR/bin/python" -m pip install -U pip setuptools wheel
"$VENV_DIR/bin/python" -m pip install -U evo

if [[ ! -x "$VENV_DIR/bin/evo_traj" ]]; then
    echo "Error: evo_traj not found after installation."
    exit 1
fi

# ---------------------------------------------------------
# 3. create GT TUM if missing
# ---------------------------------------------------------
if [[ -f "$GT_TUM_FILE" ]]; then
    echo "[3/3] GT TUM already exists, skipping creation."
    echo "Done."
    exit 0
fi

if [[ ! -d "$GT_BAG_DIR" ]]; then
    echo "Error: GT bag directory not found: $GT_BAG_DIR"
    exit 1
fi

echo "[3/3] Creating GT TUM from ROS2 bag..."

TMP_EXPORT_DIR="$(mktemp -d)"
cleanup() {
    rm -rf "$TMP_EXPORT_DIR"
}
trap cleanup EXIT

pushd "$TMP_EXPORT_DIR" >/dev/null

# evo_traj bag2 <bag_dir> <topic> --save_as_tum
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