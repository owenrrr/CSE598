# CSE 598

- `evaluation/`: evaluation
- `label_space_opt/`: optimization on label space
- `object_cluster_config_opt/`: optimization on object clustering
- `data/`: data for evaluation

## QA

### If no files saved at .hydra/uhumans2/ after execution, what to do?
`src/hydra_ros/hydra_ros/launch/hydra.launch.yaml`:

```bash
# change
- arg: {name: exit_after_clock, default: 'false',...
# to
- arg: {name: exit_after_clock, default: 'true',...
```

## rooms_eval

This directory contains scripts for evaluating the stability of Hydra's room segmentation.

### Overview

The evaluation pipeline repeatedly runs Hydra on the same dataset and analyzes
the variation in detected room segmentation results.

### Scripts

- `repeat_hydra_eval.py`  
  Runs Hydra and ros2 bag playback multiple times and collects results.

- `evaluate_hydra_run.py`  
  Performs evaluation on a single run.

- `analyze_runs.py`  
  Aggregates statistics across multiple runs and analyzes plateau selection behavior. It extracts plateau information (e.g., number of components and lifetimes) from logs and applies a custom scoring function to compare different plateau selection strategies.

- `parse_results.py`  
  Parses log output (e.g., plateau selection) for analysis.

### Notes

- `runs.log` is generated from a locally modified version of `hydra_ros`
  with additional logging for room segmentation.
- These modifications are not included in this repository.

### Purpose

This evaluation is used to analyze the stability and consistency of
Hydra's room segmentation across repeated executions.