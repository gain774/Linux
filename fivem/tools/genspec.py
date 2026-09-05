#!/usr/bin/env python3
"""モジュール部品の仕様図を SVG で描く。genkit.py と同じ寸法定義を使う。"""
import sys, os

GRID, WALL_H, THICK = 2.0, 2.5, 0.2
DOOR_W, DOOR_H = 0.9, 2.0
WIN_W, WIN_H, WIN_SILL = 1.0, 1.0, 1.0
S = 58  # 1m あたりの px

INK, SUB, LINE, FILL, ACC, BG = '#1b1b21', '#6b6675', '#c9c4d2', '#e8e5ef', '#5b4b8a', '#faf9fc'

def esc(s): return s.replace('&','&amp;').replace('<','&lt;')

def dim(x1, y1, x2, y2, label, off=0):
    """寸法線。"""
    return (f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{SUB}" stroke-width="1"/>'
            f'<text x="{(x1+x2)/2}" y="{(y1+y2)/2+off}" fill="{SUB}" font-size="11" '
            f'text-anchor="middle" font-family="ui-monospace,monospace">{label}</text>')

def elevation(x, y, name, jp, panels):
    """立面図。panels は (x0,z0,x1,z1) の矩形リスト（メートル）。"""
    o = [f'<g transform="translate({x},{y})">']
    w, h = GRID*S, WALL_H*S
    o.append(f'<rect x="0" y="0" width="{w}" height="{h}" fill="none" stroke="{LINE}" '
             f'stroke-width="1" stroke-dasharray="3 3"/>')
    for x0, z0, x1, z1 in panels:
        px, pw = (x0+GRID/2)*S, (x1-x0)*S
        pz, ph = (WALL_H-z1)*S, (z1-z0)*S
        o.append(f'<rect x="{px:.1f}" y="{pz:.1f}" width="{pw:.1f}" height="{ph:.1f}" '
                 f'fill="{FILL}" stroke="{INK}" stroke-width="1.4"/>')
    o.append(f'<text x="0" y="{h+20}" fill="{INK}" font-size="12" font-weight="600" '
             f'font-family="ui-monospace,monospace">{esc(name)}</text>')
    o.append(f'<text x="0" y="{h+36}" fill="{SUB}" font-size="11">{esc(jp)}</text>')
    o.append('</g>')
    return ''.join(o)

def plan(x, y, cells):
    """平面図。cells は (col,row,kind) で kind は wall/door/window/floor。"""
    o = [f'<g transform="translate({x},{y})">']
    cs = GRID * S * 0.5
    cols = max(c for c, _, _ in cells) + 1
    rows = max(r for _, r, _ in cells) + 1
    for c in range(cols+1):
        o.append(f'<line x1="{c*cs}" y1="0" x2="{c*cs}" y2="{rows*cs}" stroke="{LINE}" stroke-width="0.7"/>')
    for r in range(rows+1):
        o.append(f'<line x1="0" y1="{r*cs}" x2="{cols*cs}" y2="{r*cs}" stroke="{LINE}" stroke-width="0.7"/>')
    col = {'wall': INK, 'door': ACC, 'window': '#8f86b8', 'floor': '#efedf5'}
    for c, r, kind in cells:
        px, py = c*cs, r*cs
        if kind == 'floor':
            o.append(f'<rect x="{px}" y="{py}" width="{cs}" height="{cs}" fill="{col[kind]}"/>')
        else:
            o.append(f'<rect x="{px+2}" y="{py+2}" width="{cs-4}" height="{cs-4}" '
                     f'fill="{col[kind]}" opacity="0.9" rx="2"/>')
    o.append('</g>')
    return ''.join(o)

def main():
    out = sys.argv[1] if len(sys.argv) > 1 else 'kit-spec.svg'
    W, H = 980, 660
    p = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
         f'<rect width="{W}" height="{H}" fill="{BG}"/>',
         f'<text x="40" y="46" fill="{INK}" font-size="22" font-weight="700" '
         f'font-family="ui-sans-serif,system-ui">gain_build モジュール部品 仕様図</text>',
         f'<text x="40" y="68" fill="{SUB}" font-size="13">グリッド {GRID}m ／ 壁高 {WALL_H}m ／ 厚み {THICK}m'
         f'　原点は部品中心・床面 Z=0</text>',
         f'<line x1="40" y1="84" x2="{W-40}" y2="84" stroke="{INK}" stroke-width="1.5"/>']

    hw, hd, hwin = GRID/2, DOOR_W/2, WIN_W/2
    parts = [
        ('gain_wall_full', '壁（開口なし）', [(-hw, 0, hw, WALL_H)]),
        ('gain_wall_door', '壁（ドア開口 0.9×2.0）',
         [(-hw, 0, -hd, WALL_H), (hd, 0, hw, WALL_H), (-hd, DOOR_H, hd, WALL_H)]),
        ('gain_wall_window', '壁（窓開口 1.0×1.0）',
         [(-hw, 0, -hwin, WALL_H), (hwin, 0, hw, WALL_H),
          (-hwin, 0, hwin, WIN_SILL), (-hwin, WIN_SILL+WIN_H, hwin, WALL_H)]),
    ]
    for i, (name, jp, panels) in enumerate(parts):
        p.append(elevation(40 + i*260, 120, name, jp, panels))

    p.append(f'<text x="40" y="330" fill="{INK}" font-size="14" font-weight="600">立面図（上の3点）'
             f'　開口はブーリアンで抜かず、袖・まぐさ・腰壁で囲って作る</text>')
    p.append(f'<text x="40" y="350" fill="{SUB}" font-size="12">'
             f'三角化が素直になり、コリジョンも安定する。ゲーム用アセットとしてはこちらが正道</text>')

    p.append(f'<line x1="40" y1="374" x2="{W-40}" y2="374" stroke="{LINE}" stroke-width="1"/>')
    p.append(f'<text x="40" y="404" fill="{INK}" font-size="14" font-weight="600">'
             f'平面図の例　4×3 マスの部屋</text>')

    cells = []
    for c in range(4):
        for r in range(3):
            cells.append((c, r, 'floor'))
    for c in range(4):
        cells.append((c, 0, 'window' if c in (1, 2) else 'wall'))
        cells.append((c, 2, 'door' if c == 1 else 'wall'))
    for r in range(1, 2):
        cells.append((0, r, 'wall')); cells.append((3, r, 'wall'))
    p.append(plan(40, 424, cells))

    lx = 40 + 4*GRID*S*0.5 + 50
    for i, (k, label) in enumerate([('wall', '壁'), ('door', 'ドア'), ('window', '窓'), ('floor', '床')]):
        col = {'wall': INK, 'door': ACC, 'window': '#8f86b8', 'floor': '#efedf5'}[k]
        p.append(f'<rect x="{lx}" y="{430+i*26}" width="16" height="16" fill="{col}" '
                 f'stroke="{LINE}" rx="2"/>')
        p.append(f'<text x="{lx+24}" y="{443+i*26}" fill="{INK}" font-size="12">{label}</text>')

    p.append(f'<text x="{lx}" y="{430+4*26+18}" fill="{SUB}" font-size="12">'
             f'1マス {GRID}m。部品は原点合わせで置くだけで噛み合う</text>')
    p.append('</svg>')

    open(out, 'w', encoding='utf-8').write(''.join(p))
    print(f'書き出し: {out} ({os.path.getsize(out)} bytes)')

if __name__ == '__main__':
    main()
