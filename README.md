# CSE598
- run `evaluation_setup.sh` to create venv and `tesse_odom.tum` ground-truth file
- run `evaluation.sh`
- **If your project structure is different(supposed to be different), then you should provide 5 options parameters:**
    - `--hydra-ws-dir`
    - `--tum-dir`
    - `--venv-dir`
    - `--backend-dir`
    - `--gt-bag-dir`
- Currently, the default structure looks like this:

```bash
-/home/abcd0 
    - datasets
        - uhumans2
            - office_ros2
                - office_ros2.db3
    - hydra_ws 
        - tum 
            - tesse_odm.tum 
            - hydra_est.tum 
        - venv 
            - evo_eval 
    - evaluation.sh 
    - evaluatoin_setup.sh 
    - .hydra 
        - uhumans2 
            - backend 
                - trajectory.csv 
                - layer_2_statistics.csv 
                - layer_3_statistics.csv 
                - layer_4_statistics.csv 
                - layer_5_statistics.csv
```

- Accepted options:

```bash
Usage:
  ./evaluation.sh [options]

Options:
  --hydra-ws-dir PATH   Hydra workspace folder
                        default: /home/abcd0/hydra_ws

  --tum-dir PATH        tum folder
                        default: <hydra_ws_dir>/tum

  --venv-dir PATH       venv folder OR evo_venv folder
                        default: <hydra_ws_dir>/venv

  --backend-dir PATH    backend folder
                        default: /home/abcd0/.hydra/uhumans2/backend

  --gt-bag-dir PATH     ROS2 bag folder for GT
                        default: <hydra_ws_dir>/src/hydra_ros/datasets/uhumans2/office_ros2

  --gt-topic TOPIC      GT topic in rosbag
                        default: /tesse/odom

  --gt-name FILENAME    GT tum filename
                        default: tesse_odom.tum

  --est-name FILENAME   estimated tum filename
                        default: hydra_est.tum

  --force-reinstall     pass through to evaluation_setup.sh
  --force-regenerate-gt pass through to evaluation_setup.sh
```