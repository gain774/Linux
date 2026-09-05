#!/usr/bin/env python3
"""標準型住宅。中廊下型・平屋。寸法はグリッドに縛られない。

ゾーニング:
  パブリック  玄関土間 → 廊下 → LDK（土間は廊下に直接面する）
  プライベート 寝室（廊下の突き当り側）
  サービス    浴室・洗面・便所・収納を東側にまとめる（配管を集約）

動線:
  玄関から廊下に出て、そこから全室に入る。どの部屋も他室を通らずに行ける。
  水回りのドアはすべて廊下に開き、居室には開かない。
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from plan_model import Plan, Room, Opening

W, H = 10.8, 7.6          # 外形
COR_S, COR_N = 4.0, 5.2   # 廊下の南北（有効幅 1.2m）
E = 7.2                   # LDK と玄関を分ける通り
NANDO = 8.6               # 納戸と玄関土間を分ける通り

PLAN = Plan(
    name='標準型住宅 中廊下型 平屋',
    thickness=0.18,
    walls=[
        (0, 0, W, 0),            # 0 外周・南（道路側）
        (W, 0, W, H),            # 1 外周・東
        (W, H, 0, H),            # 2 外周・北
        (0, H, 0, 0),            # 3 外周・西
        (0, COR_S, E, COR_S),    # 4 LDK と廊下
        (E, 0, E, COR_S),        # 5 LDK と玄関
        (0, COR_N, W, COR_N),    # 6 廊下の北側（全室がここに開く）
        (4.4, COR_N, 4.4, H),    # 7 寝室 / 浴室
        (6.6, COR_N, 6.6, H),    # 8 浴室 / 洗面
        (8.2, COR_N, 8.2, H),    # 9 洗面 / 便所
        (9.5, COR_N, 9.5, H),    # 10 便所 / 収納
        (E, COR_S, W, COR_S),    # 11 玄関まわりと廊下
        (NANDO, 0, NANDO, COR_S),# 12 納戸 / 玄関土間
    ],
    openings=[
        # 玄関（南）
        Opening(0, 9.7, 0.95, 'door', swing='right'),
        # LDK の窓（南に2、西に1）
        Opening(0, 1.8, 1.8, 'window', height=1.3, sill=0.9),
        Opening(0, 5.0, 1.8, 'window', height=1.3, sill=0.9),
        Opening(3, 5.6, 1.6, 'window', height=1.3, sill=0.9),
        # 寝室の窓（北・西）
        Opening(2, 8.6, 1.6, 'window', height=1.2, sill=1.0),
        Opening(3, 1.2, 1.4, 'window', height=1.2, sill=1.0),
        # 浴室の窓（北・高窓）
        Opening(2, 5.3, 0.8, 'window', height=0.6, sill=1.6),
        # 廊下から各室へ
        Opening(11, 2.5, 0.9, 'door', swing='left'),    # 玄関土間 → 廊下
        Opening(4, 5.4, 0.9, 'door', swing='left'),     # 廊下 → LDK
        Opening(6, 2.2, 0.85, 'door', swing='left'),    # 廊下 → 寝室
        Opening(6, 5.5, 0.8, 'door', swing='right'),    # 廊下 → 浴室
        Opening(6, 7.4, 0.8, 'door', swing='left'),     # 廊下 → 洗面
        Opening(6, 8.85, 0.75, 'door', swing='right'),  # 廊下 → 便所（外開き）
        Opening(6, 10.15, 0.85, 'door', swing='left'),  # 廊下 → 収納
        Opening(12, 2.0, 0.85, 'door', swing='left'),   # 玄関土間 → 納戸
    ],
    rooms=[
        Room('LDK',      [(0, 0), (E, 0), (E, COR_S), (0, COR_S)]),
        Room('納戸',     [(E, 0), (NANDO, 0), (NANDO, COR_S), (E, COR_S)]),
        Room('玄関土間',  [(NANDO, 0), (W, 0), (W, COR_S), (NANDO, COR_S)]),
        Room('廊下',     [(0, COR_S), (W, COR_S), (W, COR_N), (0, COR_N)]),
        Room('寝室',     [(0, COR_N), (4.4, COR_N), (4.4, H), (0, H)]),
        Room('浴室',     [(4.4, COR_N), (6.6, COR_N), (6.6, H), (4.4, H)]),
        Room('洗面',     [(6.6, COR_N), (8.2, COR_N), (8.2, H), (6.6, H)]),
        Room('便所',     [(8.2, COR_N), (9.5, COR_N), (9.5, H), (8.2, H)]),
        Room('収納',     [(9.5, COR_N), (W, COR_N), (W, H), (9.5, H)]),
    ],
)

def check(plan=None):
    """連結の検査。通らなければ設計として成立していない。"""
    from plan_model import connectivity
    plan = plan or PLAN
    c = connectivity(plan)
    ok = True

    if not c['entry']:
        print('  NG  外部から入る開口が無い')
        ok = False
    if c['unreachable']:
        print(f'  NG  到達できない室: {", ".join(c["unreachable"])}')
        ok = False

    # 廊下・ホールは通り抜けで当然。それ以外が通り抜けになっていたら設計の失敗
    for room, lost in c['pass_through'].items():
        if any(k in room for k in ('廊下', 'ホール', '土間')):
            continue
        print(f'  NG  {room} が通り抜け。塞ぐと {", ".join(lost)} に行けない')
        ok = False

    print('  OK  全室に他室を通らず到達できる' if ok else '  設計をやり直すこと')
    return ok


if __name__ == '__main__':
    print(f'{PLAN.name}  外形 {W} x {H} m')
    for k, v in PLAN.take_off().items():
        print(f'  {k:<14} {v}')
    print()
    print('各室:')
    for r in PLAN.rooms:
        p = r.poly
        s = abs(sum(p[i][0]*p[(i+1) % len(p)][1] - p[(i+1) % len(p)][0]*p[i][1]
                    for i in range(len(p)))) / 2
        print(f'  {r.name:<8} {s:6.2f} m²')

    print()
    print('連結の検査:')
    check()

def draw(out):
    from render import render
    return render(PLAN, (W, H), out, notes=[
        'ゾーニング',
        '　パブリック  玄関土間 → 廊下 → LDK',
        '　プライベート 寝室を廊下の西端に置く',
        '　サービス    水回りを東側にまとめ配管を集約',
        '',
        '動線',
        '　玄関から廊下に出て、そこから全室に入る',
        '　どの部屋も他室を通らずに到達できる',
        '　水回りのドアはすべて廊下に開き、居室に開かない',
        '　便所は外開き（中で倒れても開けられる）',
        '',
        '採光',
        '　LDK は南に窓2・西に窓1',
        '　寝室は北と西の2面採光',
        '　浴室は高窓（視線を切りつつ換気）',
    ])


def draw_frame(out, system='木造軸組'):
    import structure
    from render import render_frame
    st = structure.build(PLAN, system)
    rows = structure.bill(PLAN, st)
    process = [
        ('1', '地縄張り・遣り方', '大工', ''),
        ('2', '掘方・砕石・転圧', '土工', ''),
        ('3', '基礎の配筋・型枠', '鉄筋工・型枠工', ''),
        ('4', '基礎コンクリート打設', '土工', '養生 7日'),
        ('5', '土台敷き', '大工', ''),
        ('6', '建方（上棟）', '大工・鳶', '1日で一気に'),
        ('7', '屋根（垂木・野地・葺き）', '大工・屋根工', ''),
        ('8', '外壁下地・サッシ', '大工', ''),
        ('9', '断熱・防水', '大工', ''),
        ('10', '設備配管・配線', '配管工・電工', ''),
        ('11', '内部造作・ボード', '大工・内装', ''),
        ('12', '仕上げ・建具・外構', '塗装・左官', ''),
    ]
    return render_frame(PLAN, st, (W, H), out, rows, process)
