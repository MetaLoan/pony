#!/usr/bin/env python3
import json
import sys
from pathlib import Path


def fix_workflow(path: Path) -> None:
    with path.open("r", encoding="utf-8") as f:
        data = json.load(f)

    changed = False
    nodes = data.get("nodes", [])

    for node in nodes:
        ntype = node.get("type")
        widgets = node.get("widgets_values")
        if not isinstance(widgets, list):
            continue

        if ntype == "CheckpointLoaderSimple" and widgets:
            ckpt = widgets[0]
            if isinstance(ckpt, str) and not ckpt.endswith((".safetensors", ".ckpt")):
                widgets[0] = f"{ckpt}.safetensors"
                changed = True

        if ntype == "IPAdapterFaceID":
            # Expected widget order in newer ComfyUI_IPAdapter_plus:
            # [weight, weight_faceidv2, weight_type, combine_embeds, start_at, end_at, embeds_scaling]
            # Old malformed workflows may contain numeric placeholders and shifted values.
            node["widgets_values"] = [
                0.8,         # weight
                1.0,         # weight_faceidv2
                "linear",    # weight_type
                "concat",    # combine_embeds
                0.0,         # start_at
                1.0,         # end_at
                "V only",    # embeds_scaling
            ]
            changed = True

    if changed:
        with path.open("w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        print(f"patched: {path}")
    else:
        print(f"no changes needed: {path}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: python scripts/fix_workflow_ipadapter.py /path/to/workflow.json")
        sys.exit(1)
    target = Path(sys.argv[1]).expanduser()
    if not target.exists():
        print(f"file not found: {target}")
        sys.exit(1)
    fix_workflow(target)
