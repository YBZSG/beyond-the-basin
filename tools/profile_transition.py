#!/usr/bin/env python3
"""Summarize native transition JSON; never starts Godot or fabricates measurements."""
from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path
from statistics import mean


def summary(values: list[float]) -> dict:
    ordered = sorted(values)
    if not ordered:
        return {"count": 0}
    return {
        "count": len(ordered),
        "mean_ms": mean(ordered),
        "p95_ms": ordered[max(0, math.ceil(len(ordered) * 0.95) - 1)],
        "p99_ms": ordered[max(0, math.ceil(len(ordered) * 0.99) - 1)],
        "max_ms": ordered[-1],
    }


def timing_line(name: str, stats: dict) -> str:
    if not stats.get("count"):
        return f"- {name}: no samples"
    return (f"- {name}: n={stats['count']}, mean {stats['mean_ms']:.2f} ms, "
            f"p95 {stats['p95_ms']:.2f} ms, p99 {stats['p99_ms']:.2f} ms, "
            f"max {stats['max_ms']:.2f} ms")


def load(path: Path) -> dict:
    result = json.loads(path.read_text())
    if not isinstance(result.get("samples"), list):
        raise ValueError(f"{path}: not a transition-profile report")
    return result


def compare(first: dict, second: dict, label: str) -> list[str]:
    lines = [f"## {label}"]
    a, b = first["metadata"], second["metadata"]
    comparable = all(a.get(k) == b.get(k) for k in (
        "route", "requested_viewport", "fixed_fps", "device", "renderer",
        "water_quality", "physics_ticks_per_second", "render_scale", "msaa_3d",
        "taa", "gi", "shadow_atlas_size"))
    lines.append("Same recorded rendering/route settings: " + str(comparable))
    if not comparable:
        lines.append("Do not attribute timing differences to one optimization: settings/device differ.")
    if a.get("loaded_scene_resources") and a.get("loaded_scene_resources") == b.get("loaded_scene_resources"):
        lines.append("The actually loaded imported room-scene hashes match. A staged raw GLB change is not proof "
                     "that the new geometry was loaded; see loaded_resource_provenance in the JSON.")
    if a.get("scene_input_sha256") != b.get("scene_input_sha256"):
        lines.append("Scene/material/lighting hashes differ. Aggregate wall-frame changes include visual changes; "
                     "terrain CPU-stage timings and cache counters are separate evidence, not an isolated GPU speedup.")
    for name in ("cold_outbound", "first_return", "warm_outbound", "warm_return"):
        aa, bb = first.get("timing", {}).get(name, {}), second.get("timing", {}).get(name, {})
        if aa.get("count") and bb.get("count"):
            lines.append(f"- {name}: mean {aa['mean_ms']:.2f} → {bb['mean_ms']:.2f} ms; "
                         f"max {aa['max_ms']:.2f} → {bb['max_ms']:.2f} ms")
    return lines


def render(data: dict, path: Path) -> str:
    meta = data["metadata"]
    samples = data["samples"]
    clean = [s for s in samples if not s.get("instrumentation_overhead")]
    lines = ["# Continuous room-transition profile", "", f"Input: `{path}`", "",
             f"Outcome: {'PASS' if data['pass'] else 'FAIL / INCOMPLETE'}", "",
             f"Device: {meta.get('device')}; renderer: {meta.get('renderer')}; "
             f"viewport: {meta.get('actual_viewport')}; High water: {meta.get('water_quality')}.",
             f"Clock: fixed-fps={meta.get('fixed_fps')} (0 means realtime); "
             f"physics={meta.get('physics_ticks_per_second')} Hz. "
             "Wall intervals are cloud-machine measurements, not target-PC FPS.", "",
             "## Wall-frame intervals"]
    lines += [timing_line(name, stats) for name, stats in data["timing"].items()]
    lines += ["", "The high percentiles of short legs may equal the maximum. "
              "These are descriptive samples, not a statistically stable benchmark.", "",
              "## Exact crossings"]
    for event in data["transitions"]:
        lines.append(f"- {event['phase']}: room={event['room']}, "
                     f"position={event['position']}, physics frame={event['physics_frame']}, "
                     f"render sample={event['sample_index']}, "
                     f"elapsed={event['wall_from_start_ms']:.2f} ms")
        if "five_frame_window_timing" in event:
            lines.append(timing_line("  crossing ±2 samples", event["five_frame_window_timing"]))
    route = data["continuous_route"]
    lines += ["", "## Continuous movement evidence",
              f"- Initial pose assignments: {route['initial_pose_assignments']}; "
              f"transition teleports: {route['transition_teleports']}.",
              f"- Horizontal distance {route['walked_horizontal_m']:.3f} m; "
              f"largest per-physics horizontal displacement {route['max_horizontal_physics_step_m']:.5f} m; "
              f"minimum root y={route['min_y']:.5f}.",
              f"- Raw controller/position evidence: {len(data['physics_positions'])} physics samples."]
    screenshot = data.get("screenshot", {})
    if screenshot:
        lines.append(f"- Screenshot `{screenshot['path']}`: crossing {screenshot['transition_id']}, "
                     f"render sample {screenshot['sample_index']}, position {screenshot['position']}.")
    lines += ["", "## Supported resource monitors"]
    for key in ("static_memory_bytes", "objects", "resources", "nodes", "resident_rooms",
                "render_texture_bytes", "render_buffer_bytes", "render_draw_calls"):
        values = [s["resources"][key] for s in clean if key in s["resources"]]
        if values:
            lines.append(f"- {key}: start {values[0]:g}, peak {max(values):g}, end {values[-1]:g}, "
                         f"net {values[-1]-values[0]:+g}." +
                         (f" Post-startup net {data['final_state']['resources'][key]-data['boot_state']['resources'][key]:+g}."
                          if key in data['boot_state'].get('resources', {}) else ""))
    lines.append("Texture/buffer monitors report bytes, not allocation counts; zero can mean unsupported. "
                 "Initial→final growth includes startup allocation; post-startup growth also includes the profiler's "
                 "own recorded arrays. A short-run net delta alone is not proof of a leak.")
    lines += ["", "## Final original-water counters", "", "```json",
              json.dumps(data["final_state"]["water"], indent=2), "```", "", "## Caveats"]
    lines += [f"- {note}" for note in meta.get("notes", [])]
    lines += [f"- Failure: {failure}" for failure in data.get("failures", [])]
    return "\n".join(lines) + "\n"


def export_csv(data: dict, path: Path) -> None:
    keys = ["index", "wall_interval_ms", "phase", "leg", "draw_frame", "physics_frame",
            "position", "room", "transition_ids", "instrumentation_overhead"]
    resource_keys = sorted({k for s in data["samples"] for k in s["resources"]})
    with path.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=keys + resource_keys)
        writer.writeheader()
        for sample in data["samples"]:
            row = {k: sample.get(k) for k in keys}
            row.update(sample["resources"])
            writer.writerow(row)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--csv", type=Path)
    parser.add_argument("--require-pass", action="store_true")
    args = parser.parse_args()
    data = load(args.report)
    text = render(data, args.report)
    if args.baseline:
        text += "\n" + "\n".join(compare(load(args.baseline), data, "Baseline → current")) + "\n"
    if args.out:
        args.out.write_text(text)
    else:
        print(text, end="")
    if args.csv:
        export_csv(data, args.csv)
    return 1 if args.require_pass and not data["pass"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
