#!/usr/bin/env python3
"""Current GLB triangles -> bounded source-mask CPU probe; no resource import."""
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def matrix_mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]


def node_matrix(node):
    if "matrix" in node:
        m = node["matrix"]
        return [[m[j * 4 + i] for j in range(4)] for i in range(4)]
    x, y, z, w = node.get("rotation", [0, 0, 0, 1])
    scale = node.get("scale", [1, 1, 1])
    t = node.get("translation", [0, 0, 0])
    rotation = [[1 - 2*y*y - 2*z*z, 2*x*y - 2*z*w, 2*x*z + 2*y*w],
                [2*x*y + 2*z*w, 1 - 2*x*x - 2*z*z, 2*y*z - 2*x*w],
                [2*x*z - 2*y*w, 2*y*z + 2*x*w, 1 - 2*x*x - 2*y*y]]
    return [[rotation[i][j] * scale[j] for j in range(3)] + [t[i]] for i in range(3)] + [[0, 0, 0, 1]]


def decode(path):
    raw = path.read_bytes()
    magic, version, length = struct.unpack_from("<III", raw)
    assert magic == 0x46546C67 and version == 2 and length == len(raw)
    cursor = 12
    document = None
    binary = None
    while cursor < len(raw):
        size, kind = struct.unpack_from("<II", raw, cursor)
        value = raw[cursor + 8:cursor + 8 + size]
        if kind == 0x4E4F534A:
            document = json.loads(value)
        elif kind == 0x004E4942:
            binary = value
        cursor += size + 8
    assert document is not None and binary is not None

    def accessor(index):
        item = document["accessors"][index]
        assert "sparse" not in item and not item.get("normalized", False)
        view = document["bufferViews"][item["bufferView"]]
        assert view.get("buffer", 0) == 0
        components = {"SCALAR": 1, "VEC3": 3}[item["type"]]
        fmt = {5121: "B", 5123: "H", 5125: "I", 5126: "f"}[item["componentType"]]
        size = struct.calcsize("<" + fmt * components)
        stride = view.get("byteStride", size)
        offset = view.get("byteOffset", 0) + item.get("byteOffset", 0)
        return [struct.unpack_from("<" + fmt * components, binary, offset + i * stride) for i in range(item["count"])]

    meshes = []

    def visit(index, parent):
        node = document["nodes"][index]
        transform = matrix_mul(parent, node_matrix(node))
        name = node.get("name", str(index))
        if "mesh" in node and not name.startswith("COLLISION_"):
            for primitive in document["meshes"][node["mesh"]]["primitives"]:
                assert primitive.get("mode", 4) == 4
                positions = accessor(primitive["attributes"]["POSITION"])
                indices = [x[0] for x in accessor(primitive["indices"])] if "indices" in primitive else list(range(len(positions)))
                faces = []
                for vertex in indices:
                    point = (*positions[vertex], 1.0)
                    faces.append([sum(transform[i][j] * point[j] for j in range(4)) for i in range(3)])
                if faces:
                    meshes.append({"name": name, "faces": faces})
        for child in node.get("children", []):
            visit(child, transform)

    identity = [[1 if i == j else 0 for j in range(4)] for i in range(4)]
    for node in document["scenes"][document.get("scene", 0)]["nodes"]:
        visit(node, identity)
    return {"sha256": hashlib.sha256(raw).hexdigest(), "meshes": meshes}


def main():
    with tempfile.TemporaryDirectory(prefix="poolcore-mask-probe-", dir="/tmp") as directory:
        tmp = Path(directory)
        path = tmp / "triangles.json"
        path.write_text(json.dumps(decode(ROOT / "assets/models/reference_wing/octagonal_bath.glb")))
        env = {**os.environ, "XDG_DATA_HOME": str(tmp / "data"), "XDG_CACHE_HOME": str(tmp / "cache")}
        command = ["godot", "--headless", "--path", str(ROOT), "--script", "res://tests/reference_wing/water_octagon_mask_probe.gd", "--", "--triangle-json=" + str(path)]
        if "--grid" in sys.argv:
            command.append("--grid")
        result = subprocess.run(command, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60, check=False)
        prefix = "REFERENCE_OCTAGON_MASK_PROBE "
        reports = [json.loads(line[len(prefix):]) for line in result.stdout.splitlines() if line.startswith(prefix)]
        if reports and "--summary" in sys.argv:
            report = reports[-1]
            rows = report.pop("probes")
            report["probe_rays"] = len(rows)
            report["false_occlusion_examples"] = [row for row in rows if row["source_mask_value"] == 0 and row["triangle_oracle_value"] == 255][:8]
            report["both_blocked_rays"] = sum(row["source_mask_value"] == 0 and row["triangle_oracle_value"] == 0 for row in rows)
            report["both_visible_rays"] = sum(row["source_mask_value"] == 255 and row["triangle_oracle_value"] == 255 for row in rows)
            report["false_visible_rays"] = sum(row["source_mask_value"] == 255 and row["triangle_oracle_value"] == 0 for row in rows)
            print(json.dumps(report, indent=2))
        else:
            print(result.stdout, end="")
        return result.returncode if reports and "SCRIPT ERROR" not in result.stdout and "ERROR:" not in result.stdout else 2


if __name__ == "__main__":
    raise SystemExit(main())
