#!/usr/bin/env python3
"""間取りから構造を起こす。柱を立て、梁を渡し、スパンを検定して断面を決める。

「壁を線で引いて部屋名を付けた」だけでは建たない。柱がどこに立ち、
梁がどこまで飛ぶかで取れる空間が決まり、それが材料と工程と職種を決める。
"""
import math
from dataclasses import dataclass, field

# 木造の流通断面（梁せい・mm）。これ以外は特注になるので使わない
BEAM_DEPTHS = [150, 180, 210, 240, 270, 300, 330, 360, 390, 450]


@dataclass
class Column:
    x: float
    y: float
    size: float          # 見付（m）
    kind: str            # 管柱 / 通し柱 / RC柱


@dataclass
class Beam:
    x1: float
    y1: float
    x2: float
    y2: float
    span: float
    depth: float         # せい（m）
    width: float
    over: bool = False   # スパン超過


@dataclass
class Structure:
    system: str
    columns: list = field(default_factory=list)
    beams: list = field(default_factory=list)
    notes: list = field(default_factory=list)
    spec: dict = field(default_factory=dict)


SYSTEMS = {
    '木造軸組': dict(col=0.105, col_pitch=1.82, col_max=2.73, beam_ratio=11,
                     beam_w=0.105, found='布基礎', unit='木材'),
    '木造枠組壁': dict(col=0.089, col_pitch=0.455, col_max=3.64, beam_ratio=12,
                       beam_w=0.089, found='ベタ基礎', unit='木材'),
    'RCラーメン': dict(col=0.60, col_pitch=6.0, col_max=8.0, beam_ratio=11,
                       beam_w=0.30, found='独立基礎', unit='RC'),
    'RC壁式': dict(col=0.0, col_pitch=0.0, col_max=5.0, beam_ratio=14,
                   beam_w=0.20, found='ベタ基礎', unit='RC'),
    '鉄骨造': dict(col=0.40, col_pitch=6.0, col_max=12.0, beam_ratio=15,
                   beam_w=0.20, found='独立基礎', unit='鋼材'),
}


def _key(x, y):
    return (round(x, 3), round(y, 3))


def build(plan, system='木造軸組'):
    """間取りから構造を起こす。"""
    if system not in SYSTEMS:
        raise ValueError(f'未知の構造形式: {system}')
    sp = SYSTEMS[system]
    st = Structure(system=system, spec=sp)

    # 構造形式で柱の立て方が根本的に違う。
    #   木造軸組    間仕切りにも柱が乗る。壁の線が構造の線
    #   RC / S 造  構造グリッドを別に持ち、間仕切りは非構造
    if sp['unit'] in ('RC', '鋼材') and sp['col_pitch'] > 0:
        return _framed(plan, st, sp)
    if st.system == 'RC壁式':
        return _wall_bearing(plan, st, sp)

    # ---- 柱。壁の端点（交点）に必ず立て、長い壁は標準ピッチで割る
    seen = {}
    for i, (x1, y1, x2, y2) in enumerate(plan.walls):
        L = plan.wall_length(i)
        ux, uy = plan.wall_dir(i)

        # 端点
        for px, py in ((x1, y1), (x2, y2)):
            seen.setdefault(_key(px, py), (px, py))

        if sp['col_pitch'] <= 0:      # 壁式は柱を立てない
            continue

        n = max(1, math.ceil(L / sp['col_pitch']))
        if n > 1:
            step = L / n
            for k in range(1, n):
                px, py = x1 + ux * step * k, y1 + uy * step * k
                seen.setdefault(_key(px, py), (px, py))

    node_deg = plan.nodes()
    for k, (px, py) in seen.items():
        deg = len(node_deg.get((round(px, 4), round(py, 4)), []))
        kind = '通し柱' if deg >= 2 and system.startswith('木造') else (
            'RC柱' if system.startswith('RC') else '管柱')
        st.columns.append(Column(px, py, sp['col'], kind))

    # ---- 梁。壁の芯線に沿って、隣り合う柱の間に渡す
    for i in range(len(plan.walls)):
        L = plan.wall_length(i)
        ux, uy = plan.wall_dir(i)
        x1, y1, _, _ = plan.walls[i]

        # この壁の上に乗る柱を距離順に
        on = []
        for c in st.columns:
            t = (c.x - x1) * ux + (c.y - y1) * uy
            perp = abs((c.x - x1) * (-uy) + (c.y - y1) * ux)
            if -1e-6 <= t <= L + 1e-6 and perp < 1e-6:
                on.append(t)
        on = sorted(set(round(t, 4) for t in on))
        if not on or on[0] > 1e-6:
            on.insert(0, 0.0)
        if abs(on[-1] - L) > 1e-6:
            on.append(L)

        for a, b in zip(on, on[1:]):
            span = b - a
            if span < 1e-6:
                continue
            depth = _beam_depth(span, sp)
            over = span > sp['col_max'] + 1e-6
            st.beams.append(Beam(x1 + ux * a, y1 + uy * a, x1 + ux * b, y1 + uy * b,
                                 span, depth, sp['beam_w'], over))

    # ---- 検定
    worst = max((b.span for b in st.beams), default=0)
    st.notes.append(f'最大スパン {worst*1000:.0f} mm（限界 {sp["col_max"]*1000:.0f}）')
    if any(b.over for b in st.beams):
        n = sum(1 for b in st.beams if b.over)
        st.notes.append(f'スパン超過 {n} 箇所。柱を追加するか断面を上げること')
    else:
        st.notes.append('全スパンが標準内。柱の追加は不要')
    st.notes.append(f'基礎形式 {sp["found"]}')

    return st


def _beam_depth(span, sp):
    """せい = スパン ÷ 比。流通断面に丸める。"""
    if sp['unit'] == '木材':
        need = span * 1000 / sp['beam_ratio']
        for d in BEAM_DEPTHS:
            if d >= need:
                return d / 1000
        return BEAM_DEPTHS[-1] / 1000
    need = span * 1000 / sp['beam_ratio']
    return max(0.3, math.ceil(need / 50) * 50 / 1000)


def bill(plan, st):
    """積算。構造形式で出てくる材料の種類が変わる。"""
    sp = st.spec
    h = plan.wall_height
    wall_len = sum(plan.wall_length(i) for i in range(len(plan.walls)))
    area = plan.area()
    rows = []

    if sp['unit'] == '木材':
        s = sp['col']
        col_v = sum(s * s * h for _ in st.columns)
        beam_v = sum(b.width * b.depth * b.span for b in st.beams)
        sill_v = 0.105 * 0.105 * wall_len
        # 小屋組は屋根面積から概算（垂木 45x60@455 + 母屋）
        roof_v = area * 0.018
        floor_v = area * 0.020          # 大引・根太
        rows += [
            ('土台 105角', f'{wall_len:.1f} m', f'{sill_v:.2f} m³'),
            (f'柱 {s*1000:.0f}角 × {len(st.columns)}本', f'{h:.1f} m', f'{col_v:.2f} m³'),
            (f'梁・桁 × {len(st.beams)}本', f'{sum(b.span for b in st.beams):.1f} m', f'{beam_v:.2f} m³'),
            ('床組（大引・根太）', f'{area:.1f} m²', f'{floor_v:.2f} m³'),
            ('小屋組（母屋・垂木）', f'{area:.1f} m²', f'{roof_v:.2f} m³'),
        ]
        total = col_v + beam_v + sill_v + roof_v + floor_v
        rows.append(('木材 合計', '', f'{total:.2f} m³'))
        # 基礎（布基礎）
        conc = wall_len * 0.15 * 0.45 + wall_len * 0.45 * 0.15
        rows.append(('基礎コンクリート', f'{wall_len:.1f} m', f'{conc:.2f} m³'))
        rows.append(('基礎配筋', '', f'{conc * 90:.0f} kg'))
    elif sp['unit'] == '鋼材':
        # H 形鋼の単位重量から拾う。柱 H-300x300（94 kg/m）、梁 H-400x200（66 kg/m）
        col_len = sum(h for _ in st.columns)
        beam_len = sum(b.span for b in st.beams)
        col_t = col_len * 94 / 1000
        beam_t = beam_len * 66 / 1000
        slab_t = 0.15
        slab_v = area * slab_t
        rows += [
            (f'柱 H-300x300 × {len(st.columns)}本', f'{col_len:.1f} m', f'{col_t:.2f} t'),
            (f'梁 H-400x200 × {len(st.beams)}本', f'{beam_len:.1f} m', f'{beam_t:.2f} t'),
            ('鋼材 合計', '', f'{col_t + beam_t:.2f} t'),
            ('高力ボルト', f'{len(st.beams) * 2} 継手', f'{len(st.beams) * 12} 本'),
            ('デッキプレート', f'{area:.1f} m²', f'{area:.0f} m²'),
            (f'床コンクリート t{slab_t*1000:.0f}', f'{area:.1f} m²', f'{slab_v:.2f} m³'),
            ('耐火被覆', f'{(col_len + beam_len):.0f} m', '吹付ロックウール'),
        ]
        return rows
    else:
        col_v = sum(sp['col'] ** 2 * h for _ in st.columns)
        beam_v = sum(b.width * b.depth * b.span for b in st.beams)
        slab_t = max(0.15, min(0.20, math.sqrt(area) / 35))
        slab_v = area * slab_t
        wall_v = wall_len * 0.20 * h if st.system == 'RC壁式' else 0.0
        conc = col_v + beam_v + slab_v + wall_v
        rows += [
            (f'柱 × {len(st.columns)}本', f'{sp["col"]*1000:.0f}角', f'{col_v:.2f} m³'),
            (f'梁 × {len(st.beams)}本', f'{sum(b.span for b in st.beams):.1f} m', f'{beam_v:.2f} m³'),
            (f'スラブ t{slab_t*1000:.0f}', f'{area:.1f} m²', f'{slab_v:.2f} m³'),
        ]
        if wall_v:
            rows.append(('耐力壁 t200', f'{wall_len:.1f} m', f'{wall_v:.2f} m³'))
        rows += [
            ('生コン 合計', '', f'{conc:.2f} m³'),
            ('鉄筋', '', f'{conc * 110:.0f} kg'),
            ('型枠', '', f'{(wall_len * h * 2 + area):.0f} m²'),
        ]
    return rows


def _bbox(plan):
    xs, ys = [], []
    for x1, y1, x2, y2 in plan.walls:
        xs += [x1, x2]
        ys += [y1, y2]
    return min(xs), min(ys), max(xs), max(ys)


def _grid_lines(lo, hi, pitch):
    """lo〜hi を pitch 以下で等分する線の位置。端は必ず含む。"""
    length = hi - lo
    n = max(1, math.ceil(length / pitch))
    return [lo + length / n * k for k in range(n + 1)]


def _framed(plan, st, sp):
    """RC ラーメン・S 造。構造グリッドで柱を立て、間仕切りとは切り離す。"""
    x0, y0, x1, y1 = _bbox(plan)
    xs = _grid_lines(x0, x1, sp['col_pitch'])
    ys = _grid_lines(y0, y1, sp['col_pitch'])

    kind = 'RC柱' if sp['unit'] == 'RC' else '鉄骨柱'
    for x in xs:
        for y in ys:
            st.columns.append(Column(x, y, sp['col'], kind))

    # 大梁は柱を X 方向・Y 方向に結ぶ
    for y in ys:
        for a, b in zip(xs, xs[1:]):
            span = b - a
            st.beams.append(Beam(a, y, b, y, span, _beam_depth(span, sp),
                                 sp['beam_w'], span > sp['col_max'] + 1e-6))
    for x in xs:
        for a, b in zip(ys, ys[1:]):
            span = b - a
            st.beams.append(Beam(x, a, x, b, span, _beam_depth(span, sp),
                                 sp['beam_w'], span > sp['col_max'] + 1e-6))

    worst = max((b.span for b in st.beams), default=0)
    st.notes.append(f'構造グリッド {len(xs)-1} x {len(ys)-1} スパン')
    st.notes.append(f'最大スパン {worst*1000:.0f} mm（限界 {sp["col_max"]*1000:.0f}）')
    st.notes.append('間仕切りは非構造。後から動かせる')
    st.notes.append(f'基礎形式 {sp["found"]}')
    return st


def _wall_bearing(plan, st, sp):
    """RC 壁式。柱を立てず、壁そのものが構造。開口に制限がかかる。"""
    for i in range(len(plan.walls)):
        L = plan.wall_length(i)
        x1, y1, x2, y2 = plan.walls[i]
        st.beams.append(Beam(x1, y1, x2, y2, L, 0.0, 0.20, L > sp['col_max'] + 1e-6))

    over = [b for b in st.beams if b.over]
    st.notes.append('柱を立てない。壁が構造そのもの')
    st.notes.append(f'壁の囲み限界 {sp["col_max"]*1000:.0f} mm')
    if over:
        st.notes.append(f'{len(over)} 箇所が限界超過。壁を追加して囲みを小さくする')
    else:
        st.notes.append('全ての囲みが限界内')
    st.notes.append('耐力壁は後から抜けない。間取り変更は不可')
    st.notes.append(f'基礎形式 {sp["found"]}')
    return st
