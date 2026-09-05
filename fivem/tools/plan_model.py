#!/usr/bin/env python3
"""間取りのデータモデル。

寸法は自由。グリッドの倍数である必要はない。
壁は「芯線の線分」として持ち、交点は計算で解決する。
2m 単位のブロックを並べる方式は、角が納まらないうえに寸法が縛られるので採らない。
"""

from dataclasses import dataclass, field


@dataclass
class Opening:
    """壁に開ける穴。wall は壁の添字、at は始点からの距離（芯）。"""
    wall: int
    at: float
    width: float
    kind: str = 'door'          # door / window / arch
    height: float = 2.0
    sill: float = 0.0
    swing: str = 'left'         # ドアの開き勝手


@dataclass
class Room:
    name: str
    poly: list                  # [(x, y), ...] 反時計回り


@dataclass
class Plan:
    name: str
    walls: list = field(default_factory=list)      # [(x1, y1, x2, y2), ...]
    openings: list = field(default_factory=list)
    rooms: list = field(default_factory=list)
    thickness: float = 0.18
    wall_height: float = 2.5
    slab: float = 0.15

    # ---------------------------------------------------------------- 幾何
    def nodes(self):
        """壁の端点ごとに、そこに集まる壁の添字を返す。"""
        acc = {}
        for i, (x1, y1, x2, y2) in enumerate(self.walls):
            for p in ((round(x1, 4), round(y1, 4)), (round(x2, 4), round(y2, 4))):
                acc.setdefault(p, []).append(i)
        return acc

    def wall_polygon(self, i):
        """壁 i のポシェ（塗り）の四隅。

        端点に他の壁が集まっていれば厚みの半分だけ延長する。
        これをやらないと角に欠けができる。自由端は延長しない。
        """
        x1, y1, x2, y2 = self.walls[i]
        dx, dy = x2 - x1, y2 - y1
        length = (dx * dx + dy * dy) ** 0.5
        if length == 0:
            return []

        ux, uy = dx / length, dy / length     # 進行方向
        nx, ny = -uy, ux                      # 法線
        h = self.thickness / 2

        nd = self.nodes()
        e1 = h if len(nd.get((round(x1, 4), round(y1, 4)), [])) > 1 else 0.0
        e2 = h if len(nd.get((round(x2, 4), round(y2, 4)), [])) > 1 else 0.0

        ax, ay = x1 - ux * e1, y1 - uy * e1
        bx, by = x2 + ux * e2, y2 + uy * e2

        return [(ax + nx * h, ay + ny * h), (bx + nx * h, by + ny * h),
                (bx - nx * h, by - ny * h), (ax - nx * h, ay - ny * h)]

    def wall_length(self, i):
        x1, y1, x2, y2 = self.walls[i]
        return ((x2 - x1) ** 2 + (y2 - y1) ** 2) ** 0.5

    def wall_openings(self, i):
        return sorted((o for o in self.openings if o.wall == i), key=lambda o: o.at)

    def point_on_wall(self, i, dist):
        x1, y1, x2, y2 = self.walls[i]
        length = self.wall_length(i)
        t = dist / length
        return x1 + (x2 - x1) * t, y1 + (y2 - y1) * t

    def wall_dir(self, i):
        x1, y1, x2, y2 = self.walls[i]
        length = self.wall_length(i)
        return (x2 - x1) / length, (y2 - y1) / length

    # ---------------------------------------------------------------- 数量
    def area(self):
        total = 0.0
        for r in self.rooms:
            p = r.poly
            s = sum(p[i][0] * p[(i + 1) % len(p)][1] - p[(i + 1) % len(p)][0] * p[i][1]
                    for i in range(len(p)))
            total += abs(s) / 2
        return total

    def take_off(self):
        """部品を拾う。壁は連なり1本で1部品。2m 区間には割らない。"""
        wall_runs = len(self.walls)
        wall_total = sum(self.wall_length(i) for i in range(wall_runs))
        doors = sum(1 for o in self.openings if o.kind == 'door')
        windows = sum(1 for o in self.openings if o.kind == 'window')
        area = self.area()

        return {
            '壁（連なり）': wall_runs,
            '　うち総長': f'{wall_total:.1f} m',
            'ドア': doors,
            '窓': windows,
            '床': 1,
            '屋根': 1,
            '延床': f'{area:.1f} m²',
            'プロップ合計': wall_runs + 2,
        }


# ---------------------------------------------------------------- 連結の検査
def _inside(poly, x, y):
    """点が多角形の内側か（レイキャスト）。"""
    n, ins = len(poly), False
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        if (y1 > y) != (y2 > y):
            xi = x1 + (y - y1) / (y2 - y1) * (x2 - x1)
            if x < xi:
                ins = not ins
    return ins


def _room_at(plan, x, y):
    for r in plan.rooms:
        if _inside(r.poly, x, y):
            return r.name
    return None


def connectivity(plan, entry_from_outside=None):
    """開口がどの室とどの室を繋いでいるかを求め、玄関から辿れない室を洗い出す。

    「どの部屋も他室を通らずに到達できる」は口で言っても意味がない。計算する。
    """
    edges = []
    outside = []

    for o in plan.openings:
        if o.kind == 'window':
            continue
        i = o.wall
        ux, uy = plan.wall_dir(i)
        nx, ny = -uy, ux
        cx, cy = plan.point_on_wall(i, o.at)
        d = plan.thickness / 2 + 0.35

        a = _room_at(plan, cx + nx * d, cy + ny * d)
        b = _room_at(plan, cx - nx * d, cy - ny * d)

        if a and b:
            edges.append((a, b, o))
        elif a or b:
            outside.append(((a or b), o))     # 外部に出る開口＝玄関など

    # 到達判定
    start = entry_from_outside or (outside[0][0] if outside else None)
    reach, stack = set(), [start] if start else []
    while stack:
        cur = stack.pop()
        if cur in reach:
            continue
        reach.add(cur)
        for a, b, _ in edges:
            if a == cur and b not in reach:
                stack.append(b)
            elif b == cur and a not in reach:
                stack.append(a)

    names = [r.name for r in plan.rooms]
    unreachable = [n for n in names if n not in reach]

    # 通り抜けでしか行けない室を探す。ある室を封鎖したとき到達できなくなる室
    pass_through = {}
    for block in names:
        if block == start:
            continue
        r2, st2 = set(), [start] if start else []
        while st2:
            cur = st2.pop()
            if cur in r2 or cur == block:
                continue
            r2.add(cur)
            for a, b, _ in edges:
                if a == cur and b not in r2 and b != block:
                    st2.append(b)
                elif b == cur and a not in r2 and a != block:
                    st2.append(a)
        lost = [n for n in names if n not in r2 and n != block and n not in unreachable]
        if lost:
            pass_through[block] = lost

    return dict(entry=start, edges=edges, outside=outside,
                unreachable=unreachable, pass_through=pass_through)
