#!/usr/bin/env python3
"""モジュール式の建築部品を手続き的に生成する。

GTA V の標準プロップにはグリッドで組める壁・床が乏しく、Base Building 系の
スクリプトが軒並み独自プロップを同梱しているのはそのため。ここでは
gain_build のグリッド（1マス 2.0m / 壁高 2.5m）にぴったり合う部品を
外部ツールなしで作る。

出力は .obj（テキスト）。Blender で読み込み、Sollumz で .ydr に変換して
FiveM にストリームする想定。

開口部はブーリアンで抜かず、周囲を板で囲って作る。三角化が素直になり、
コリジョンも安定する。ゲーム用アセットとしてはこちらが正道。

使い方: python3 genkit.py [出力先ディレクトリ]
"""

import sys
import os

GRID = 2.0          # 1マスの一辺
WALL_H = 2.5        # 壁の高さ
THICK = 0.2         # 壁の厚み
SLAB = 0.15         # 床・屋根の厚み

DOOR_W, DOOR_H = 0.9, 2.0
WIN_W, WIN_H = 1.0, 1.0
WIN_SILL = 1.0      # 窓の下端の高さ


class Mesh:
    """三角形メッシュ。UV は 1m = 1 タイルの平面投影。"""

    def __init__(self):
        self.v = []
        self.vt = []
        self.vn = []
        self.f = []

    def box(self, x0, y0, z0, x1, y1, z1):
        """軸に沿った直方体を足す。面ごとに法線と UV を持たせる。"""
        c = [
            (x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
            (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1),
        ]
        base = len(self.v)
        self.v.extend(c)

        # (頂点4つ, 法線, UV に使う2軸)
        faces = [
            ((0, 1, 2, 3), (0, 0, -1), (0, 1)),   # 下
            ((7, 6, 5, 4), (0, 0, 1), (0, 1)),    # 上
            ((0, 4, 5, 1), (0, -1, 0), (0, 2)),   # 手前
            ((2, 6, 7, 3), (0, 1, 0), (0, 2)),    # 奥
            ((0, 3, 7, 4), (-1, 0, 0), (1, 2)),   # 左
            ((1, 5, 6, 2), (1, 0, 0), (1, 2)),    # 右
        ]

        for quad, normal, (ua, ub) in faces:
            self.vn.append(normal)
            ni = len(self.vn)

            idx = []
            for k in quad:
                p = c[k]
                self.vt.append((p[ua], p[ub]))
                idx.append((base + k + 1, len(self.vt), ni))

            # 四角形を三角形2枚に
            self.f.append((idx[0], idx[1], idx[2]))
            self.f.append((idx[0], idx[2], idx[3]))

    def write(self, path, name):
        with open(path, 'w', encoding='utf-8') as fp:
            fp.write(f'# {name} — gain_build modular kit\n')
            fp.write(f'# grid {GRID}m / wall {WALL_H}m / thickness {THICK}m\n')
            fp.write('# 原点は部品の中心（床面 Z=0）。そのままグリッド座標に置ける\n')
            fp.write(f'o {name}\n')
            for x, y, z in self.v:
                fp.write(f'v {x:.4f} {y:.4f} {z:.4f}\n')
            for u, w in self.vt:
                fp.write(f'vt {u:.4f} {w:.4f}\n')
            for x, y, z in self.vn:
                fp.write(f'vn {x:.1f} {y:.1f} {z:.1f}\n')
            for tri in self.f:
                fp.write('f ' + ' '.join(f'{a}/{b}/{c}' for a, b, c in tri) + '\n')
        return len(self.f)


def floor_slab():
    m = Mesh()
    h = GRID / 2
    m.box(-h, -h, -SLAB, h, h, 0.0)
    return m


def roof_slab():
    m = Mesh()
    h = GRID / 2
    m.box(-h, -h, 0.0, h, h, SLAB)
    return m


def wall_full():
    m = Mesh()
    h, t = GRID / 2, THICK / 2
    m.box(-h, -t, 0.0, h, t, WALL_H)
    return m


def wall_with_opening(ow, oh, sill):
    """開口部つきの壁。左右の袖と、上（と必要なら下）の板で囲う。"""
    m = Mesh()
    h, t = GRID / 2, THICK / 2
    ohw = ow / 2

    m.box(-h, -t, 0.0, -ohw, t, WALL_H)          # 左の袖
    m.box(ohw, -t, 0.0, h, t, WALL_H)            # 右の袖
    m.box(-ohw, -t, sill + oh, ohw, t, WALL_H)   # まぐさ（開口の上）
    if sill > 0:
        m.box(-ohw, -t, 0.0, ohw, t, sill)       # 腰壁（窓の下）
    return m


def corner_post():
    m = Mesh()
    t = THICK / 2
    m.box(-t, -t, 0.0, t, t, WALL_H)
    return m


PARTS = {
    'gain_floor_2x2':   (floor_slab,  '床 2x2m'),
    'gain_roof_2x2':    (roof_slab,   '屋根 2x2m'),
    'gain_wall_full':   (wall_full,   '壁（開口なし）'),
    'gain_wall_door':   (lambda: wall_with_opening(DOOR_W, DOOR_H, 0.0),      '壁（ドア開口）'),
    'gain_wall_window': (lambda: wall_with_opening(WIN_W, WIN_H, WIN_SILL),   '壁（窓開口）'),
    'gain_corner_post': (corner_post, '柱（角）'),
}


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else '.'
    os.makedirs(out, exist_ok=True)

    total = 0
    print(f'{"部品":<20} {"三角形":>6}  内容')
    print('-' * 52)
    for name, (fn, label) in PARTS.items():
        tris = fn().write(os.path.join(out, name + '.obj'), name)
        total += tris
        print(f'{name:<20} {tris:>6}  {label}')
    print('-' * 52)
    print(f'{"合計":<20} {total:>6}  1棟ぶんの部品一式')


if __name__ == '__main__':
    main()
