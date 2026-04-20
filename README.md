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