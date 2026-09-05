#!/usr/bin/env python3
"""間取りデータから建築図面一式を描く。

gain_build の間取りデータ（グリッド上の壁・開口・部屋）を入力に、
平面図・立面図・断面図・数量表を1枚にまとめた図面を SVG で出力する。
将来は間取りエディタの保存データをそのまま食わせる。

グリッドは genkit.py と共通（1マス 2.0m / 壁高 2.5m / 厚み 0.2m）。
"""

import sys, math
from datetime import date

GRID, WALL_H, THICK, SLAB = 2.0, 2.5, 0.2, 0.15
DOOR_W, DOOR_H = 0.9, 2.0
WIN_W, WIN_H, WIN_SILL = 1.0, 1.0, 1.0

INK, SUB, FAINT, LINE, ACC = '#16161c', '#5f5a6b', '#9a94a8', '#c8c3d2', '#7a3b2e'
PAPER, POCHE, ROOMF = '#fbfaf7', '#2a2731', '#f2eff6'

MONO = 'ui-monospace,SFMono-Regular,Consolas,monospace'
SANS = '"Hiragino Sans","Noto Sans JP","Yu Gothic UI",ui-sans-serif,system-ui,sans-serif'

# ---------------------------------------------------------------- 間取りデータ
# 壁は「グリッド線上の 2m 区間」。('h', x, y) は (x,y)-(x+2,y) の水平壁。
# kind: full / door / window
PLAN = {
    'name': '木造平屋 48m2 A型',
    'size': (8.0, 6.0),
    'walls': [
        # 外周・南（y=0）
        ('h', 0, 0, 'window'), ('h', 2, 0, 'window'), ('h', 4, 0, 'window'), ('h', 6, 0, 'window'),
        # 外周・北（y=6）
        ('h', 0, 6, 'door'), ('h', 2, 6, 'full'), ('h', 4, 6, 'full'), ('h', 6, 6, 'full'),
        # 外周・西（x=0）
        ('v', 0, 0, 'window'), ('v', 0, 2, 'full'), ('v', 0, 4, 'full'),
        # 外周・東（x=8）
        ('v', 8, 0, 'window'), ('v', 8, 2, 'window'), ('v', 8, 4, 'full'),
        # 内部・水平（y=4）
        ('h', 0, 4, 'door'), ('h', 2, 4, 'door'), ('h', 4, 4, 'door'), ('h', 6, 4, 'door'),
        # 内部・垂直（x=4, y0-4）
        ('v', 4, 0, 'door'), ('v', 4, 2, 'full'),
        # 内部・垂直（y4-6 の間仕切り）
        ('v', 2, 4, 'full'), ('v', 4, 4, 'full'), ('v', 6, 4, 'full'),
    ],
    'rooms': [
        ('LDK',     0, 0, 4, 4),
        ('寝室',    4, 0, 4, 4),
        ('玄関',    0, 4, 2, 2),
        ('浴室',    2, 4, 2, 2),
        ('便所',    4, 4, 2, 2),
        ('収納',    6, 4, 2, 2),
    ],
}

# ------------------------------------------------------------------- 図形部品
def esc(s):
    return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')

def txt(x, y, s, size=11, fill=INK, anchor='start', font=SANS, weight='400', extra=''):
    return (f'<text x="{x:.1f}" y="{y:.1f}" font-size="{size}" fill="{fill}" '
            f'text-anchor="{anchor}" font-family="{font}" font-weight="{weight}" {extra}>{esc(s)}</text>')

def line(x1, y1, x2, y2, stroke=INK, w=1.0, dash=None):
    d = f' stroke-dasharray="{dash}"' if dash else ''
    return f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" stroke="{stroke}" stroke-width="{w}"{d}/>'

def rect(x, y, w, h, fill='none', stroke='none', sw=1.0, extra=''):
    return (f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" '
            f'fill="{fill}" stroke="{stroke}" stroke-width="{sw}" {extra}/>')

def dimension(x1, y1, x2, y2, label, flip=False):
    """寸法線。端部は建築図の慣習にならって 45 度のティック。"""
    o = [line(x1, y1, x2, y2, SUB, 0.8)]
    for (x, y) in ((x1, y1), (x2, y2)):
        o.append(line(x - 3, y + 3, x + 3, y - 3, SUB, 1.0))
    mx, my = (x1 + x2) / 2, (y1 + y2) / 2
    if abs(y2 - y1) < 0.1:      # 水平
        o.append(txt(mx, my - 5, label, 10, SUB, 'middle', MONO))
    else:                        # 垂直
        o.append(txt(mx - 6, my + 3, label, 10, SUB, 'middle', MONO,
                     extra=f'transform="rotate(-90 {mx-6:.1f} {my+3:.1f})"'))
    return ''.join(o)

# ------------------------------------------------------------------- 平面図
def draw_plan(ox, oy, s):
    """s = 1m あたりの px"""
    W, H = PLAN['size']
    t = THICK * s
    o = []

    # 室（塗り + 名前 + 面積）
    for name, rx, ry, rw, rh in PLAN['rooms']:
        px, py = ox + rx * s, oy + (H - ry - rh) * s
        o.append(rect(px, py, rw * s, rh * s, ROOMF))
        cx, cy = px + rw * s / 2, py + rh * s / 2
        o.append(txt(cx, cy, name, 12, INK, 'middle', SANS, '600'))
        o.append(txt(cx, cy + 15, f'{rw*rh:.1f} m²', 10, SUB, 'middle', MONO))

    # 通り芯（一点鎖線）
    for i in range(int(W / GRID) + 1):
        x = ox + i * GRID * s
        o.append(line(x, oy - 34, x, oy + H * s + 34, FAINT, 0.7, '9 3 2 3'))
        o.append(f'<circle cx="{x:.1f}" cy="{oy-44:.1f}" r="10" fill="{PAPER}" stroke="{SUB}" stroke-width="0.8"/>')
        o.append(txt(x, oy - 40, f'X{i+1}', 9, SUB, 'middle', MONO))
    for j in range(int(H / GRID) + 1):
        y = oy + (H - j * GRID) * s
        o.append(line(ox - 34, y, ox + W * s + 34, y, FAINT, 0.7, '9 3 2 3'))
        o.append(f'<circle cx="{ox-44:.1f}" cy="{y:.1f}" r="10" fill="{PAPER}" stroke="{SUB}" stroke-width="0.8"/>')
        o.append(txt(ox - 44, y + 4, f'Y{j+1}', 9, SUB, 'middle', MONO))

    # 壁
    for kind_, gx, gy, opening in PLAN['walls']:
        if kind_ == 'h':
            x0, y0 = ox + gx * s, oy + (H - gy) * s
            length = GRID * s
            hor = True
        else:
            x0, y0 = ox + gx * s, oy + (H - gy - GRID) * s
            length = GRID * s
            hor = False

        if opening == 'full':
            if hor:
                o.append(rect(x0, y0 - t / 2, length, t, POCHE))
            else:
                o.append(rect(x0 - t / 2, y0, t, length, POCHE))
            continue

        ow = (DOOR_W if opening == 'door' else WIN_W) * s
        side = (length - ow) / 2

        if hor:
            o.append(rect(x0, y0 - t / 2, side, t, POCHE))
            o.append(rect(x0 + side + ow, y0 - t / 2, side, t, POCHE))
        else:
            o.append(rect(x0 - t / 2, y0, t, side, POCHE))
            o.append(rect(x0 - t / 2, y0 + side + ow, t, side, POCHE))

        if opening == 'window':
            # 窓は開口内に細線3本
            if hor:
                for k, off in enumerate((-t / 2, 0, t / 2)):
                    o.append(line(x0 + side, y0 + off, x0 + side + ow, y0 + off, INK, 0.8))
            else:
                for off in (-t / 2, 0, t / 2):
                    o.append(line(x0 + off, y0 + side, x0 + off, y0 + side + ow, INK, 0.8))
        else:
            # ドアは開き勝手を円弧で示す
            if hor:
                hx, hy = x0 + side, y0
                o.append(line(hx, hy, hx, hy - ow, INK, 1.1))
                o.append(f'<path d="M {hx:.1f} {hy-ow:.1f} A {ow:.1f} {ow:.1f} 0 0 1 {hx+ow:.1f} {hy:.1f}" '
                         f'fill="none" stroke="{SUB}" stroke-width="0.8"/>')
            else:
                hx, hy = x0, y0 + side
                o.append(line(hx, hy, hx + ow, hy, INK, 1.1))
                o.append(f'<path d="M {hx+ow:.1f} {hy:.1f} A {ow:.1f} {ow:.1f} 0 0 1 {hx:.1f} {hy+ow:.1f}" '
                         f'fill="none" stroke="{SUB}" stroke-width="0.8"/>')

    # 寸法線（全体・通り間）
    yb = oy + H * s + 62
    o.append(dimension(ox, yb, ox + W * s, yb, f'{W*1000:.0f}'))
    yb2 = oy + H * s + 40
    for i in range(int(W / GRID)):
        o.append(dimension(ox + i * GRID * s, yb2, ox + (i + 1) * GRID * s, yb2, f'{GRID*1000:.0f}'))
    xl = ox - 62
    o.append(dimension(xl, oy, xl, oy + H * s, f'{H*1000:.0f}'))

    # 断面の切断線
    ycut = oy + (H - 2.0) * s
    o.append(line(ox - 20, ycut, ox + W * s + 20, ycut, ACC, 1.2, '14 4 3 4'))
    o.append(txt(ox - 26, ycut + 4, 'A', 11, ACC, 'middle', MONO, '700'))
    o.append(txt(ox + W * s + 26, ycut + 4, 'A', 11, ACC, 'middle', MONO, '700'))

    # 方位
    nx, ny = ox + W * s + 58, oy + 16
    o.append(f'<path d="M {nx:.1f} {ny-16:.1f} L {nx-7:.1f} {ny+8:.1f} L {nx:.1f} {ny+2:.1f} '
             f'L {nx+7:.1f} {ny+8:.1f} Z" fill="{INK}"/>')
    o.append(txt(nx, ny + 24, 'N', 11, INK, 'middle', MONO, '700'))
    return ''.join(o)

# ------------------------------------------------------------- 立面図・断面図
def draw_elevation(ox, oy, s):
    W = PLAN['size'][0]
    o = [line(ox - 10, oy, ox + W * s + 10, oy, INK, 1.6)]  # GL
    o.append(rect(ox, oy - WALL_H * s, W * s, WALL_H * s, PAPER, INK, 1.2))
    o.append(rect(ox - 0.2 * s, oy - (WALL_H + SLAB) * s, (W + 0.4) * s, SLAB * s, POCHE))

    # 南面の開口（y=0 の壁）
    for kind_, gx, gy, opening in PLAN['walls']:
        if kind_ != 'h' or gy != 0 or opening == 'full':
            continue
        ow = (DOOR_W if opening == 'door' else WIN_W) * s
        cx = ox + (gx + GRID / 2) * s
        if opening == 'window':
            o.append(rect(cx - ow / 2, oy - (WIN_SILL + WIN_H) * s, ow, WIN_H * s, '#dfe6ee', INK, 1.0))
            o.append(line(cx, oy - (WIN_SILL + WIN_H) * s, cx, oy - WIN_SILL * s, INK, 0.7))
        else:
            o.append(rect(cx - ow / 2, oy - DOOR_H * s, ow, DOOR_H * s, ROOMF, INK, 1.0))

    o.append(dimension(ox - 34, oy - WALL_H * s, ox - 34, oy, f'{WALL_H*1000:.0f}'))
    o.append(txt(ox, oy + 26, '立面図（南）', 12, INK, 'start', SANS, '600'))
    o.append(txt(ox, oy + 42, 'GL ±0 / 軒高 2,500', 10, SUB, 'start', MONO))
    return ''.join(o)

def draw_section(ox, oy, s):
    W = PLAN['size'][0]
    o = [line(ox - 10, oy, ox + W * s + 10, oy, INK, 1.6)]
    o.append(rect(ox, oy - SLAB * s, W * s, SLAB * s, POCHE))                    # 床スラブ
    o.append(rect(ox, oy - (WALL_H + SLAB) * s, THICK * s, WALL_H * s, POCHE))   # 左壁
    o.append(rect(ox + W * s - THICK * s, oy - (WALL_H + SLAB) * s, THICK * s, WALL_H * s, POCHE))
    o.append(rect(ox + 4.0 * s - THICK * s / 2, oy - (WALL_H + SLAB) * s, THICK * s, WALL_H * s, POCHE))  # 間仕切り
    o.append(rect(ox, oy - (WALL_H + SLAB * 2) * s, W * s, SLAB * s, POCHE))     # 屋根

    o.append(dimension(ox + W * s + 30, oy - (WALL_H + SLAB) * s, ox + W * s + 30, oy - SLAB * s, f'{WALL_H*1000:.0f}'))
    o.append(txt(ox, oy + 26, 'A-A 断面図', 12, INK, 'start', SANS, '600'))
    o.append(txt(ox, oy + 42, f'床 t{SLAB*1000:.0f} / 壁 t{THICK*1000:.0f} / 屋根 t{SLAB*1000:.0f}', 10, SUB, 'start', MONO))
    return ''.join(o)

# --------------------------------------------------------------------- 数量表
def take_off():
    counts = {'full': 0, 'door': 0, 'window': 0}
    for _, _, _, opening in PLAN['walls']:
        counts[opening] += 1

    W, H = PLAN['size']
    cells = int(W / GRID) * int(H / GRID)

    # 柱は壁が2方向以上で交わる格子点に立てる
    nodes = {}
    for kind_, gx, gy, _ in PLAN['walls']:
        ends = [(gx, gy), (gx + GRID, gy)] if kind_ == 'h' else [(gx, gy), (gx, gy + GRID)]
        for e in ends:
            nodes.setdefault(e, set()).add(kind_)
    posts = sum(1 for dirs in nodes.values() if len(dirs) > 1)

    tris = {'gain_wall_full': 12, 'gain_wall_door': 36, 'gain_wall_window': 48,
            'gain_floor_2x2': 12, 'gain_roof_2x2': 12, 'gain_corner_post': 12}
    rows = [
        ('gain_wall_full',   '壁（開口なし）', counts['full']),
        ('gain_wall_door',   '壁（ドア開口）', counts['door']),
        ('gain_wall_window', '壁（窓開口）',   counts['window']),
        ('gain_floor_2x2',   '床',             cells),
        ('gain_roof_2x2',    '屋根',           cells),
        ('gain_corner_post', '柱',             posts),
    ]
    return rows, tris

def draw_takeoff(ox, oy):
    rows, tris = take_off()
    o = [txt(ox, oy, '数量表（部品拾い）', 12, INK, 'start', SANS, '600')]
    y = oy + 22
    o.append(line(ox, y - 13, ox + 430, y - 13, INK, 1.0))
    for h, x, a in (('部品', 0, 'start'), ('内容', 150, 'start'), ('数量', 300, 'end'), ('三角形', 400, 'end')):
        o.append(txt(ox + x, y, h, 10, SUB, a, MONO, '600'))
    y += 8
    o.append(line(ox, y, ox + 430, y, LINE, 0.8))

    total_n, total_t = 0, 0
    for name, label, n in rows:
        y += 19
        t = n * tris[name]
        total_n += n
        total_t += t
        o.append(txt(ox, y, name, 10, INK, 'start', MONO))
        o.append(txt(ox + 150, y, label, 10, SUB, 'start', SANS))
        o.append(txt(ox + 300, y, str(n), 10, INK, 'end', MONO))
        o.append(txt(ox + 400, y, f'{t:,}', 10, SUB, 'end', MONO))

    y += 10
    o.append(line(ox, y, ox + 430, y, INK, 1.0))
    y += 19
    o.append(txt(ox, y, '合計', 11, INK, 'start', SANS, '700'))
    o.append(txt(ox + 300, y, f'{total_n} 個', 11, INK, 'end', MONO, '700'))
    o.append(txt(ox + 400, y, f'{total_t:,}', 11, INK, 'end', MONO, '700'))
    y += 20
    o.append(txt(ox, y, f'1棟あたり {total_n} プロップ。描画負荷の見積りはこの数字で行う',
                 10, ACC, 'start', SANS))
    return ''.join(o), total_n

def title_block(x, y, w, h, props):
    o = [rect(x, y, w, h, PAPER, INK, 1.4)]
    o.append(line(x, y + 30, x + w, y + 30, INK, 1.0))
    o.append(txt(x + 12, y + 20, PLAN['name'], 13, INK, 'start', SANS, '700'))
    rows = [
        ('図面', '平面図・立面図・断面図・数量表'),
        ('縮尺', 'NTS（グリッド 2,000 基準）'),
        ('構法', f'モジュール組立 / 壁高 {WALL_H*1000:.0f} / 壁厚 {THICK*1000:.0f}'),
        ('延床', f'{PLAN["size"][0]*PLAN["size"][1]:.1f} m²'),
        ('部品数', f'{props} 個'),
        ('日付', date.today().isoformat()),
    ]
    yy = y + 50
    for k, v in rows:
        o.append(txt(x + 12, yy, k, 9, SUB, 'start', MONO))
        o.append(txt(x + 66, yy, v, 10, INK, 'start', SANS))
        yy += 19
    return ''.join(o)

# ----------------------------------------------------------------------- 出力
def main():
    out = sys.argv[1] if len(sys.argv) > 1 else 'plan.svg'
    W, H = 1400, 1010
    s = 46

    p = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
         rect(0, 0, W, H, PAPER),
         rect(18, 18, W - 36, H - 36, 'none', INK, 1.6),
         rect(26, 26, W - 52, H - 52, 'none', FAINT, 0.6)]

    p.append(txt(52, 62, 'gain_build 建築図面', 20, INK, 'start', SANS, '700'))
    p.append(txt(52, 82, '間取りデータから自動生成。この図面がそのまま施工の指示書と積算根拠になる',
                 11, SUB, 'start', SANS))
    p.append(line(52, 96, W - 52, 96, INK, 1.2))

    p.append(draw_plan(150, 150, s))
    p.append(txt(150, 148 + 6 * s + 96, '平面図', 12, INK, 'start', SANS, '600'))

    p.append(draw_elevation(880, 300, s * 0.55))
    p.append(draw_section(880, 470, s * 0.55))

    take, props = draw_takeoff(880, 560)
    p.append(take)
    p.append(title_block(880, 780, 440, 170, props))
    p.append('</svg>')

    open(out, 'w', encoding='utf-8').write(''.join(p))
    print(f'書き出し: {out}')
    rows, tris = take_off()
    for name, label, n in rows:
        print(f'  {name:<20} {label:<16} {n:>3} 個')
    print(f'  {"合計":<20} {"":<16} {props:>3} プロップ')

if __name__ == '__main__':
    main()
