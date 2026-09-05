#!/usr/bin/env python3
"""Plan を図面（SVG）に起こす。壁は芯線から描き、交点は延長で埋める。"""
import sys, os, math
from datetime import date
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

INK, SUB, FAINT, LINE, ACC = '#16161c', '#5f5a6b', '#9a94a8', '#c8c3d2', '#8a3f2c'
PAPER, POCHE = '#fbfaf7', '#232028'
ROOMC = {'LDK': '#eef1ec', '廊下': '#f4f0e6', '玄関土間': '#efe9df',
         '寝室': '#eceef4', '浴室': '#e6eef1', '洗面': '#e9eff1',
         '便所': '#eef0f2', '収納': '#f1eef2', '納戸': '#f1eef2'}
MONO = 'ui-monospace,SFMono-Regular,Consolas,monospace'
SANS = '"Hiragino Sans","Noto Sans JP","Yu Gothic UI",ui-sans-serif,sans-serif'


class Sheet:
    def __init__(self, w, h):
        self.w, self.h, self.o = w, h, []

    def add(self, s): self.o.append(s)

    def text(self, x, y, s, size=11, fill=INK, anchor='start', font=SANS, weight='400'):
        s = str(s).replace('&', '&amp;').replace('<', '&lt;')
        self.add(f'<text x="{x:.1f}" y="{y:.1f}" font-size="{size}" fill="{fill}" '
                 f'text-anchor="{anchor}" font-family="{font}" font-weight="{weight}">{s}</text>')

    def line(self, x1, y1, x2, y2, stroke=INK, w=1.0, dash=None):
        d = f' stroke-dasharray="{dash}"' if dash else ''
        self.add(f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" '
                 f'stroke="{stroke}" stroke-width="{w}"{d}/>')

    def poly(self, pts, fill='none', stroke='none', w=1.0):
        d = ' '.join(f'{x:.2f},{y:.2f}' for x, y in pts)
        self.add(f'<polygon points="{d}" fill="{fill}" stroke="{stroke}" stroke-width="{w}"/>')

    def rect(self, x, y, w, h, fill='none', stroke='none', sw=1.0):
        self.add(f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" '
                 f'fill="{fill}" stroke="{stroke}" stroke-width="{sw}"/>')

    def save(self, path):
        head = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.w}" height="{self.h}" '
                f'viewBox="0 0 {self.w} {self.h}">')
        open(path, 'w', encoding='utf-8').write(head + ''.join(self.o) + '</svg>')


class PlanView:
    """図面座標系。平面図は Y 上向き、SVG は Y 下向きなので反転する。"""

    def __init__(self, sheet, plan, ox, oy, scale, extent):
        self.s, self.p, self.ox, self.oy, self.k = sheet, plan, ox, oy, scale
        self.ex, self.ey = extent

    def P(self, x, y):
        return self.ox + x * self.k, self.oy + (self.ey - y) * self.k

    # ---------------------------------------------------------------- 室
    def rooms(self):
        for r in self.p.rooms:
            pts = [self.P(x, y) for x, y in r.poly]
            self.s.poly(pts, ROOMC.get(r.name, '#f0eef4'))
            cx = sum(p[0] for p in pts) / len(pts)
            cy = sum(p[1] for p in pts) / len(pts)
            a = abs(sum(r.poly[i][0] * r.poly[(i + 1) % len(r.poly)][1]
                        - r.poly[(i + 1) % len(r.poly)][0] * r.poly[i][1]
                        for i in range(len(r.poly)))) / 2
            small = a < 5.0
            self.s.text(cx, cy - (0 if small else 4), r.name,
                        10 if small else 12, INK, 'middle', SANS, '600')
            self.s.text(cx, cy + (12 if small else 12), f'{a:.1f}m²',
                        8.5 if small else 9.5, SUB, 'middle', MONO)

    # ---------------------------------------------------------------- 壁
    def walls(self):
        p = self.p
        nd = p.nodes()
        h = p.thickness / 2

        for i in range(len(p.walls)):
            L = p.wall_length(i)
            ux, uy = p.wall_dir(i)
            nx, ny = -uy, ux
            x1, y1, x2, y2 = p.walls[i]
            deg1 = len(nd.get((round(x1, 4), round(y1, 4)), [])) > 1
            deg2 = len(nd.get((round(x2, 4), round(y2, 4)), [])) > 1

            # 開口で分断された実体部分
            cuts, pos = [], 0.0
            for o in p.wall_openings(i):
                a, b = o.at - o.width / 2, o.at + o.width / 2
                if a > pos:
                    cuts.append((pos, a))
                pos = b
            if pos < L:
                cuts.append((pos, L))

            for a, b in cuts:
                aa = a - (h if a == 0.0 and deg1 else 0.0)
                bb = b + (h if abs(b - L) < 1e-9 and deg2 else 0.0)
                ax, ay = p.point_on_wall(i, 0)
                sx, sy = ax + ux * aa, ay + uy * aa
                ex, ey = ax + ux * bb, ay + uy * bb
                pts = [self.P(sx + nx * h, sy + ny * h), self.P(ex + nx * h, ey + ny * h),
                       self.P(ex - nx * h, ey - ny * h), self.P(sx - nx * h, sy - ny * h)]
                self.s.poly(pts, POCHE)

    # ---------------------------------------------------------------- 開口
    def openings(self):
        p = self.p
        h = p.thickness / 2

        for o in p.openings:
            i = o.wall
            ux, uy = p.wall_dir(i)
            nx, ny = -uy, ux
            cx, cy = p.point_on_wall(i, o.at)
            w = o.width

            if o.kind == 'window':
                for off in (-h, 0.0, h):
                    a = self.P(cx - ux * w / 2 + nx * off, cy - uy * w / 2 + ny * off)
                    b = self.P(cx + ux * w / 2 + nx * off, cy + uy * w / 2 + ny * off)
                    self.s.line(*a, *b, INK, 0.9)
                continue

            # ドア。丁番側から扉を直角に開き、円弧で軌跡を示す
            sign = 1 if o.swing == 'left' else -1
            hx = cx - ux * w / 2 * sign
            hy = cy - uy * w / 2 * sign
            jx = cx + ux * w / 2 * sign
            jy = cy + uy * w / 2 * sign
            lx, ly = hx + nx * w, hy + ny * w

            self.s.line(*self.P(hx, hy), *self.P(lx, ly), INK, 1.3)
            a = self.P(lx, ly)
            b = self.P(jx, jy)
            r = w * self.k
            sweep = 1 if sign > 0 else 0
            self.s.add(f'<path d="M {a[0]:.1f} {a[1]:.1f} A {r:.1f} {r:.1f} 0 0 {sweep} '
                       f'{b[0]:.1f} {b[1]:.1f}" fill="none" stroke="{SUB}" stroke-width="0.9"/>')

    # ---------------------------------------------------------------- 寸法
    def dim(self, x1, y1, x2, y2, label, horizontal=True):
        a, b = self.P(x1, y1), self.P(x2, y2)
        self.s.line(*a, *b, SUB, 0.8)
        for pt in (a, b):
            self.s.line(pt[0] - 3, pt[1] + 3, pt[0] + 3, pt[1] - 3, SUB, 1.0)
        mx, my = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
        if horizontal:
            self.s.text(mx, my - 5, label, 9.5, SUB, 'middle', MONO)
        else:
            self.s.add(f'<g transform="rotate(-90 {mx - 5:.1f} {my + 3:.1f})">')
            self.s.text(mx - 5, my + 3, label, 9.5, SUB, 'middle', MONO)
            self.s.add('</g>')

    def dims(self, offsets):
        p = self.p
        ex, ey = self.ex, self.ey
        d = offsets
        self.dim(0, -d, ex, -d, f'{ex * 1000:.0f}')
        self.dim(-d, 0, -d, ey, f'{ey * 1000:.0f}', False)


def render(plan, extent, out, notes=None):
    SW, SH, k = 1440, 1000, 62
    s = Sheet(SW, SH)
    s.rect(0, 0, SW, SH, PAPER)
    s.rect(18, 18, SW - 36, SH - 36, 'none', INK, 1.6)
    s.rect(26, 26, SW - 52, SH - 52, 'none', FAINT, 0.6)

    s.text(54, 62, plan.name, 20, INK, 'start', SANS, '700')
    s.text(54, 84, '寸法はグリッドに縛られない。壁は芯線で持ち、交点は厚みの半分だけ延長して納める',
           11, SUB)
    s.line(54, 98, SW - 54, 98, INK, 1.2)

    v = PlanView(s, plan, 150, 150, k, extent)
    v.rooms()
    v.walls()
    v.openings()
    v.dims(0.62)

    # 方位
    nx, ny = 150 + extent[0] * k + 52, 172
    s.add(f'<path d="M {nx} {ny - 17} L {nx - 7} {ny + 8} L {nx} {ny + 2} '
          f'L {nx + 7} {ny + 8} Z" fill="{INK}"/>')
    s.text(nx, ny + 24, 'N', 11, INK, 'middle', MONO, '700')

    s.text(150, 150 + extent[1] * k + 72, '平面図', 13, INK, 'start', SANS, '600')

    # 凡例と要点
    bx = 150 + extent[0] * k + 110
    s.text(bx, 168, '設計の要点', 13, INK, 'start', SANS, '700')
    y = 192
    for t in (notes or []):
        s.text(bx, y, t, 11, SUB if t.startswith('　') else INK)
        y += 20

    # 数量
    y += 16
    s.text(bx, y, '数量', 13, INK, 'start', SANS, '700')
    y += 10
    s.line(bx, y, bx + 300, y, INK, 1.0)
    for kk, vv in plan.take_off().items():
        y += 20
        s.text(bx, y, kk, 10.5, SUB if kk.startswith('　') else INK)
        s.text(bx + 300, y, vv, 10.5, INK, 'end', MONO,
               '700' if kk == 'プロップ合計' else '400')

    y += 18
    s.line(bx, y, bx + 300, y, LINE, 0.8)
    y += 20
    s.text(bx, y, f'{date.today().isoformat()}　壁 t{plan.thickness*1000:.0f} / '
                  f'階高 {plan.wall_height*1000:.0f}', 10, SUB, 'start', MONO)

    s.save(out)
    return out


def render_frame(plan, st, extent, out, bill_rows, process_rows):
    """構造伏図。柱・梁・スパンを描き、積算と工程を並べる。"""
    SW, SH, k = 1440, 1010, 62
    s = Sheet(SW, SH)
    s.rect(0, 0, SW, SH, PAPER)
    s.rect(18, 18, SW - 36, SH - 36, 'none', INK, 1.6)
    s.rect(26, 26, SW - 52, SH - 52, 'none', FAINT, 0.6)

    s.text(54, 62, f'{plan.name}　構造伏図', 20, INK, 'start', SANS, '700')
    s.text(54, 84, f'{st.system}　柱がどこに立ち梁がどこまで飛ぶかで、取れる空間と材料が決まる',
           11, SUB)
    s.line(54, 98, SW - 54, 98, INK, 1.2)

    v = PlanView(s, plan, 150, 150, k, extent)

    # 間仕切りを下敷きに薄く
    for i in range(len(plan.walls)):
        x1, y1, x2, y2 = plan.walls[i]
        s.line(*v.P(x1, y1), *v.P(x2, y2), LINE, 1.0)

    # 梁。スパン超過は色を変える
    for b in st.beams:
        col = ACC if b.over else INK
        w = 3.2 if b.depth >= 0.3 else 2.2
        s.line(*v.P(b.x1, b.y1), *v.P(b.x2, b.y2), col, w)

    # 柱
    for c in st.columns:
        px, py = v.P(c.x, c.y)
        sz = max(5.0, c.size * k)
        s.rect(px - sz / 2, py - sz / 2, sz, sz, POCHE, PAPER, 1.0)

    # 代表スパンの寸法
    longest = sorted(st.beams, key=lambda b: -b.span)[:3]
    for b in longest:
        mx, my = v.P((b.x1 + b.x2) / 2, (b.y1 + b.y2) / 2)
        s.add(f'<rect x="{mx-24:.1f}" y="{my-9:.1f}" width="48" height="15" '
              f'fill="{PAPER}" opacity="0.9" rx="2"/>')
        s.text(mx, my + 2, f'{b.span*1000:.0f}', 9, ACC if b.over else SUB, 'middle', MONO, '600')

    s.text(150, 150 + extent[1] * k + 46, '伏図', 13, INK, 'start', SANS, '600')
    ly = 150 + extent[1] * k + 70
    for t in st.notes:
        s.text(150, ly, '・' + t, 10.5, SUB)
        ly += 18

    # 積算
    bx = 150 + extent[0] * k + 110
    s.text(bx, 168, '積算', 13, INK, 'start', SANS, '700')
    y = 180
    s.line(bx, y, bx + 470, y, INK, 1.0)
    for a, b, c in bill_rows:
        y += 20
        bold = '700' if '合計' in a else '400'
        s.text(bx, y, a, 10.5, INK, 'start', SANS, bold)
        s.text(bx + 330, y, b, 10, SUB, 'end', MONO)
        s.text(bx + 470, y, c, 10.5, INK, 'end', MONO, bold)

    # 工程
    y += 34
    s.text(bx, y, '工程と職種', 13, INK, 'start', SANS, '700')
    y += 12
    s.line(bx, y, bx + 470, y, INK, 1.0)
    for no, name, trade, wait in process_rows:
        y += 19
        s.text(bx, y, f'{no}', 9.5, FAINT, 'start', MONO)
        s.text(bx + 22, y, name, 10.5, INK)
        s.text(bx + 330, y, trade, 10, SUB, 'end', SANS)
        if wait:
            s.text(bx + 470, y, wait, 10, ACC, 'end', MONO)

    s.save(out)
    return out
