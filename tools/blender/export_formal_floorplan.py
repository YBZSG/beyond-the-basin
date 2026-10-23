#!/usr/bin/env python3
"""Export a measured, roof-free SVG plan from the actual five shipped GLBs."""
import html
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.dont_write_bytecode = True
sys.path.insert(0, str(ROOT/'tests'))
from formal_architectural_junctions import GLB

ROOMS = [('formal_mainhall', -32, -32, 'MAIN HALL', '22 × 20 m · 0.44 m water'),
         ('formal_arcade', 0, -32, 'ARCADE', '24.8 × 6 m · dry gallery'),
         ('formal_sidepool', -32, 0, 'SIDE POOL', '14 × 14 m · 0.84 m water'),
         ('formal_terrace', 0, -64, 'DAYLIGHT TERRACE', '20 × 18 m · 0.22 m water'),
         ('formal_bath', -32, -64, 'CURVED BATH', 'Ø18.32 m · 0.94 m water')]
SCALE = 7.0


def xy(x, z):
    return (56+(x+48)*SCALE, 100+(z+80)*SCALE)


def main():
    svg = ['<svg xmlns="http://www.w3.org/2000/svg" width="620" height="850" viewBox="0 0 620 850">',
           '<rect width="620" height="850" fill="#eef1ed"/>',
           '<g font-family="DejaVu Sans,Arial,sans-serif" fill="#20363b">',
           '<text x="35" y="36" font-size="20" font-weight="bold">FORMAL WING · MEASURED PLAN</text>',
           '<text x="35" y="58" font-size="11">Actual GLB floor/wall geometry. Roofs removed. Not a runtime screenshot.</text>',
           '<text x="35" y="76" font-size="11">32 m room grid · five rooms · continuous four-room walking loop</text></g>']
    for x in [-48, -16, 16]:
        a, b = xy(x, -80), xy(x, 16)
        svg.append(f'<path d="M{a[0]},{a[1]} L{b[0]},{b[1]}" stroke="#a9b8b3" stroke-dasharray="4 6" fill="none"/>')
    for z in [-80, -48, -16, 16]:
        a, b = xy(-48, z), xy(16, z)
        svg.append(f'<path d="M{a[0]},{a[1]} L{b[0]},{b[1]}" stroke="#a9b8b3" stroke-dasharray="4 6" fill="none"/>')
    faces = []
    walls = []
    for asset, ox, oz, _, _ in ROOMS:
        glb = GLB(ROOT/'assets/models/formal'/f'{asset}.glb')
        for name in glb.nodes:
            if name.startswith('COLLISION_'):
                continue
            low, high = glb.bounds(name)
            # Walls are shown at a 1.5 m architectural section, not at the
            # upper drum/header, which would falsely close real doorways.
            is_wall = low[1] < 1.5 < high[1]
            for primitive in glb.primitives(name):
                vertices = glb.accessor(primitive['attributes']['POSITION'])
                normals = glb.accessor(primitive['attributes']['NORMAL'])
                indices = [v[0] for v in glb.accessor(primitive['indices'])]
                role = glb.doc['materials'][primitive['material']]['name']
                for i in range(0, len(indices), 3):
                    ids = indices[i:i+3]
                    # Include the real sloping connector floor faces as well
                    # as horizontal decks. The steepest retained ramp is 19°.
                    if not all(normals[j][1] > (.99 if is_wall else .90) for j in ids):
                        continue
                    height = sum(vertices[j][1] for j in ids)/3
                    if height > .60 and not is_wall:
                        continue
                    color = '#f7f4e9' if role == 'Formal_Coping' else '#dce3de'
                    if '_Basin' in name or '_Stair' in name:
                        color = '#aad4d2' if height < .32 else '#c5dfda'
                    if 'Vestibule' in name:
                        color = '#c4cec7'
                    if role in ('Formal_Drain', 'Formal_Metal'):
                        color = '#6a807f'
                    points = [xy(vertices[j][0]+ox, vertices[j][2]+oz) for j in ids]
                    polygon = '<path d="M'+' L'.join(f'{x:.3f},{y:.3f}' for x, y in points)+' Z" fill="'+('#657c78' if is_wall else color)+'"/>'
                    (walls if is_wall else faces).append((height, polygon))
    svg.extend(p for _, p in sorted(faces))
    svg.extend(p for _, p in sorted(walls))
    # This is the exact dry route also exercised by formal_connected_loop.gd.
    import math
    loop = [(-32, -40), (-32, -56.6)]
    loop += [(-32+math.cos(math.radians(a))*7.4, -64+math.sin(math.radians(a))*7.4) for a in [75, 60, 45, 30, 15, 0]]
    loop += [(-8, -64), (-8, -57), (0, -57), (0, -33), (-9, -32), (-22.8, -32), (-22.8, -40), (-32, -40)]
    svg.append('<path d="M'+' L'.join(f'{xy(x,z)[0]:.2f},{xy(x,z)[1]:.2f}' for x, z in loop)+'" fill="none" stroke="#b36b49" stroke-width="1.8" stroke-dasharray="4 3"/>')
    svg.append('<g font-family="DejaVu Sans,Arial,sans-serif" fill="#20363b" text-anchor="middle">')
    for _, ox, oz, title, detail in ROOMS:
        x, y = xy(ox, oz)
        svg.append(f'<text x="{x}" y="{y-4}" font-size="10" font-weight="bold">{html.escape(title)}</text>')
        svg.append(f'<text x="{x}" y="{y+10}" font-size="7.5">{html.escape(detail)}</text>')
    svg += ['</g>', '<g font-family="DejaVu Sans,Arial,sans-serif" fill="#20363b" font-size="10">',
            '<path d="M35 800 H105" stroke="#20363b" stroke-width="3"/><text x="35" y="818">10 metres</text>',
            '<path d="M215 800 H265" stroke="#b36b49" stroke-width="2" stroke-dasharray="4 3"/><text x="275" y="804">Tested dry walking loop</text>',
            '<text x="35" y="839">Optional authored wing only. The original source world remains the default.</text>', '</g></svg>']
    target = ROOT/'docs/formal-wing-floorplan.svg'
    target.write_text('\n'.join(svg)+'\n')
    print(f'Wrote measured floor plan: {target.relative_to(ROOT)}')


if __name__ == '__main__':
    main()
