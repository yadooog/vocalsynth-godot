"""Brings sam's Blender export (a .glb) into the game.

Run:  python3 tools/import_models.py path/to/sam_export.glb

It keeps two things from the file, in sam's own units and arrangement:
  - the large rug ("rug large.002", or "rug large" if that's missing)
  - the stage, where sam put it on that rug
and writes:
  project/models/world_props.glb   just those two meshes (no textures, no reference objects)
  project/room/stage_shape.gd      the rug's measurements and the height of the stage's
                                   walkable tops on a grid, so the game knows where you can stand

The game scales all of it (room/world.gd MODEL_SCALE): sam's character reference box is
7 m tall and the character is 3.5 m, so sam's scenes are drawn at twice the game's size.
"""
import base64
import json
import math
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CELL = 0.5          # grid spacing for the stage heights, in sam's units


def read_glb(path):
    data = Path(path).read_bytes()
    jlen, = struct.unpack_from('<I', data, 12)
    j = json.loads(data[20:20 + jlen])
    boff = 20 + jlen
    blen, = struct.unpack_from('<I', data, boff)
    return j, data[boff + 8: boff + 8 + blen]


def accessor(j, bin_, i):
    a = j['accessors'][i]
    bv = j['bufferViews'][a['bufferView']]
    fmt, size = {5126: ('f', 4), 5123: ('H', 2), 5125: ('I', 4), 5121: ('B', 1)}[a['componentType']]
    n = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[a['type']]
    start = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    stride = bv.get('byteStride', size * n)
    out = [struct.unpack_from('<' + fmt * n, bin_, start + k * stride) for k in range(a['count'])]
    return [v[0] for v in out] if n == 1 else out


# --- small matrix helpers (column-major 4x4, as glTF stores them) ---

def quat_mat(q):
    x, y, z, w = q
    return [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
            [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
            [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]


def node_transform(node):
    """(apply_point, apply_normal) for a node with translation/rotation/scale."""
    t = node.get('translation', [0, 0, 0])
    r = quat_mat(node.get('rotation', [0, 0, 0, 1]))
    s = node.get('scale', [1, 1, 1])

    def point(v):
        v = [v[0] * s[0], v[1] * s[1], v[2] * s[2]]
        return tuple(sum(r[i][k] * v[k] for k in range(3)) + t[i] for i in range(3))

    def normal(n):
        n = [n[0] / s[0], n[1] / s[1], n[2] / s[2]]
        n = [sum(r[i][k] * n[k] for k in range(3)) for i in range(3)]
        length = math.sqrt(sum(c * c for c in n)) or 1.0
        return tuple(c / length for c in n)

    return point, normal


def take(j, bin_, name):
    """Positions, normals, UVs and triangles of a named node, in the scene's space."""
    node = next((n for n in j['nodes'] if n.get('name') == name), None)
    if node is None:
        return None
    point, normal = node_transform(node)
    pos, nor, uv, tris = [], [], [], []
    for prim in j['meshes'][node['mesh']]['primitives']:
        base = len(pos)
        attrs = prim['attributes']
        pos += [point(v) for v in accessor(j, bin_, attrs['POSITION'])]
        nor += [normal(v) for v in accessor(j, bin_, attrs['NORMAL'])]
        uv += accessor(j, bin_, attrs['TEXCOORD_0']) if 'TEXCOORD_0' in attrs else [(0.0, 0.0)] * (len(pos) - base)
        idx = accessor(j, bin_, prim['indices'])
        tris += [(base + idx[k], base + idx[k + 1], base + idx[k + 2]) for k in range(0, len(idx), 3)]
    return pos, nor, uv, tris


def write_glb(path, meshes):
    """meshes: [(name, pos, nor, uv, tris)] -> a .glb with one node per mesh, no materials."""
    blob = bytearray()
    views, accessors, gl_meshes, nodes = [], [], [], []

    def add(data, target, count, comp, kind, mn=None, mx=None):
        while len(blob) % 4:
            blob.append(0)
        views.append({'buffer': 0, 'byteOffset': len(blob), 'byteLength': len(data), 'target': target})
        blob.extend(data)
        a = {'bufferView': len(views) - 1, 'componentType': comp, 'count': count, 'type': kind}
        if mn is not None:
            a['min'], a['max'] = mn, mx
        accessors.append(a)
        return len(accessors) - 1

    for name, pos, nor, uv, tris in meshes:
        p = add(b''.join(struct.pack('<3f', *v) for v in pos), 34962, len(pos), 5126, 'VEC3',
                [min(v[i] for v in pos) for i in range(3)], [max(v[i] for v in pos) for i in range(3)])
        n = add(b''.join(struct.pack('<3f', *v) for v in nor), 34962, len(nor), 5126, 'VEC3')
        t = add(b''.join(struct.pack('<2f', *v) for v in uv), 34962, len(uv), 5126, 'VEC2')
        flat = [i for t in tris for i in t]
        i = add(b''.join(struct.pack('<I', k) for k in flat), 34963, len(flat), 5125, 'SCALAR')
        gl_meshes.append({'name': name, 'primitives': [{'attributes': {'POSITION': p, 'NORMAL': n, 'TEXCOORD_0': t}, 'indices': i}]})
        nodes.append({'name': name, 'mesh': len(gl_meshes) - 1})
    while len(blob) % 4:
        blob.append(0)
    j = {'asset': {'version': '2.0', 'generator': 'tools/import_models.py'}, 'scene': 0,
         'scenes': [{'nodes': list(range(len(nodes)))}], 'nodes': nodes, 'meshes': gl_meshes,
         'accessors': accessors, 'bufferViews': views, 'buffers': [{'byteLength': len(blob)}]}
    js = json.dumps(j, separators=(',', ':')).encode()
    js += b' ' * (-len(js) % 4)
    out = struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob))
    out += struct.pack('<II', len(js), 0x4E4F534A) + js + struct.pack('<II', len(blob), 0x004E4942) + bytes(blob)
    Path(path).write_bytes(out)


def heights(pos, nor, _uv, tris):
    """The height of the highest upward-facing surface over each grid cell (0 where there's none)."""
    xs = [v[0] for v in pos]
    zs = [v[2] for v in pos]
    x0 = math.floor(min(xs) / CELL) * CELL
    z0 = math.floor(min(zs) / CELL) * CELL
    nx = int(math.ceil((max(xs) - x0) / CELL)) + 1
    nz = int(math.ceil((max(zs) - z0) / CELL)) + 1
    grid = [0.0] * (nx * nz)
    for a, b, c in tris:
        A, B, C = pos[a], pos[b], pos[c]
        if (nor[a][1] + nor[b][1] + nor[c][1]) / 3.0 < 0.3:
            continue # walls and the underside
        det = (B[0] - A[0]) * (C[2] - A[2]) - (C[0] - A[0]) * (B[2] - A[2])
        if abs(det) < 1e-12:
            continue
        i0 = max(0, int((min(A[0], B[0], C[0]) - x0) / CELL))
        i1 = min(nx - 1, int((max(A[0], B[0], C[0]) - x0) / CELL) + 1)
        k0 = max(0, int((min(A[2], B[2], C[2]) - z0) / CELL))
        k1 = min(nz - 1, int((max(A[2], B[2], C[2]) - z0) / CELL) + 1)
        for k in range(k0, k1 + 1):
            for i in range(i0, i1 + 1):
                x, z = x0 + i * CELL, z0 + k * CELL
                l1 = ((x - A[0]) * (C[2] - A[2]) - (C[0] - A[0]) * (z - A[2])) / det
                l2 = ((B[0] - A[0]) * (z - A[2]) - (x - A[0]) * (B[2] - A[2])) / det
                if l1 < -1e-6 or l2 < -1e-6 or l1 + l2 > 1 + 1e-6:
                    continue
                y = A[1] + l1 * (B[1] - A[1]) + l2 * (C[1] - A[1])
                grid[k * nx + i] = max(grid[k * nx + i], y)
    return x0, z0, nx, nz, grid


def main():
    j, bin_ = read_glb(sys.argv[1])
    rug = take(j, bin_, 'rug large.002') or take(j, bin_, 'rug large')
    stage = take(j, bin_, 'stage')
    if rug is None or stage is None:
        sys.exit('need a "rug large" and a "stage" in the file')
    # The rug's shape: outer radius and side height, top radius and height.
    prof = [(math.hypot(v[0], v[2]), v[1]) for v in rug[0]]
    rug_r = max(r for r, _ in prof)
    rug_h = max(y for _, y in prof)
    top_r = min(r for r, y in prof if abs(y - rug_h) < 1e-3)
    side_h = max((y for r, y in prof if abs(r - rug_r) < 0.01 and y < rug_h - 1e-3), default=0.0)
    write_glb(ROOT / 'project/models/world_props.glb', [('rug', *rug), ('stage', *stage)])
    x0, z0, nx, nz, grid = heights(*stage)
    # The deck: the most common height on top of the stage.
    tops = {}
    for y in grid:
        if y > rug_h:
            tops[round(y, 2)] = tops.get(round(y, 2), 0) + 1
    deck = max(tops, key=tops.get)
    data = base64.b64encode(b''.join(struct.pack('<H', int(round(y * 1000))) for y in grid)).decode()
    lines = [
        'class_name StageShape',
        '## Made by tools/import_models.py from sam\'s Blender export: don\'t edit by hand.',
        '## Everything is in sam\'s units (World.MODEL_SCALE turns them into the game\'s), measured',
        '## from the centre of the stage\'s rug, at the floor.',
        '',
        'const RUG_R := %.3f        # the rug\'s outer radius' % rug_r,
        'const RUG_TOP_R := %.3f    # where its top starts to bevel down' % top_r,
        'const RUG_H := %.3f        # its height' % rug_h,
        'const RUG_SIDE_H := %.3f   # the height of its straight outer side' % side_h,
        'const DECK_Y := %.3f       # the height of the stage\'s floor' % deck,
        '# The highest walkable surface of the stage over a grid: CELL apart, starting at X0, Z0,',
        '# NX across by NZ deep, as 16-bit millimetres in base64 (0 where there\'s no stage).',
        'const CELL := %.3f' % CELL,
        'const X0 := %.3f' % x0,
        'const Z0 := %.3f' % z0,
        'const NX := %d' % nx,
        'const NZ := %d' % nz,
        'const DATA := "%s"' % data,
        '',
    ]
    (ROOT / 'project/room/stage_shape.gd').write_text('\n'.join(lines))
    print('rug r %.3f (top %.3f) h %.3f side %.3f; stage deck %.3f; grid %d x %d' % (rug_r, top_r, rug_h, side_h, deck, nx, nz))


if __name__ == '__main__':
    main()
