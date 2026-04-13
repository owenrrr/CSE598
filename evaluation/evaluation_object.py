import json
import yaml
from collections import Counter
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
DSG_JSON = BASE_DIR.parent / "data" / "dsg.json"
LABEL_SPACE_YAML = BASE_DIR.parent / "data" / "uhumans2_office_label_space.yaml"

# 想只看 active objects 就改成 True
ONLY_ACTIVE = False


def load_label_map(yaml_path: Path):
    with open(yaml_path, "r") as f:
        data = yaml.safe_load(f)

    label_map = {}
    for item in data.get("label_names", []):
        label_map[int(item["label"])] = item["name"]
    return label_map


def get_object_nodes(dsg):
    """
    Hydra DSG export:
    - all nodes are in dsg["nodes"]
    - object nodes have attributes.type == "ObjectNodeAttributes"
    """
    nodes = dsg.get("nodes", [])
    object_nodes = []

    for node in nodes:
        if not isinstance(node, dict):
            continue

        attrs = node.get("attributes")
        if not isinstance(attrs, dict):
            continue

        if attrs.get("type") == "ObjectNodeAttributes":
            object_nodes.append(node)

    return object_nodes


def main():
    if not DSG_JSON.exists():
        raise FileNotFoundError(f"DSG JSON not found: {DSG_JSON}")

    if not LABEL_SPACE_YAML.exists():
        raise FileNotFoundError(f"Label-space YAML not found: {LABEL_SPACE_YAML}")

    label_map = load_label_map(LABEL_SPACE_YAML)

    with open(DSG_JSON, "r") as f:
        dsg = json.load(f)

    object_nodes = get_object_nodes(dsg)

    counts = Counter()
    unknown_ids = Counter()

    total_all_object_nodes = len(object_nodes)
    total_active_object_nodes = 0

    for node in object_nodes:
        attrs = node["attributes"]

        is_active = bool(attrs.get("is_active", False))
        if is_active:
            total_active_object_nodes += 1

        if ONLY_ACTIVE and not is_active:
            continue

        label_id = int(attrs["semantic_label"])

        if label_id in label_map:
            counts[label_map[label_id]] += 1
        else:
            unknown_ids[label_id] += 1

    mode_name = "ACTIVE object nodes only" if ONLY_ACTIVE else "ALL object nodes"

    print(f"Counting mode: {mode_name}")
    print(f"DSG file: {DSG_JSON}")
    print(f"Label YAML: {LABEL_SPACE_YAML}")
    print()
    print(f"Total object nodes in DSG: {total_all_object_nodes}")
    print(f"Total active object nodes in DSG: {total_active_object_nodes}")
    print()

    print("Final object counts by class:")
    for name, cnt in sorted(counts.items(), key=lambda x: (-x[1], x[0])):
        print(f"{name}: {cnt}")

    if unknown_ids:
        print("\nUnknown label ids found:")
        for lid, cnt in sorted(unknown_ids.items()):
            print(f"{lid}: {cnt}")

    print(f"\nTotal counted objects: {sum(counts.values()) + sum(unknown_ids.values())}")


if __name__ == "__main__":
    main()