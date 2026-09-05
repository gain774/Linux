// ゲーム内 CAD。壁を芯線で引き、開口を開け、部屋を囲む。
// 出力は plan_model.py と同じ形式（walls / openings / rooms）。

const SNAP = 0.25;          // 部品の刻みと一致させる
const MAXE = 40;            // 作図範囲（m）
const THICK = 0.18;

const cv = document.getElementById('cv');
const ctx = cv.getContext('2d');

let S = {                    // 図面
  id: null, name: '無題', system: '木造軸組',
  walls: [], openings: [], rooms: [],
};
let view = { x: 0, y: 0, k: 34 };     // 表示（k = px/m）
let tool = 'wall';
let draft = null;                     // 作図中
let hover = null;
let history = [];

// ---------------------------------------------------------------- 座標変換
const toS = (x, y) => [cv.width / 2 + (x - view.x) * view.k,
                       cv.height / 2 - (y - view.y) * view.k];
const toW = (px, py) => [view.x + (px - cv.width / 2) / view.k,
                         view.y - (py - cv.height / 2) / view.k];
const snap = v => Math.round(v / SNAP) * SNAP;
const dist = (x1, y1, x2, y2) => Math.hypot(x2 - x1, y2 - y1);

function wallLen(w) { return dist(w[0], w[1], w[2], w[3]); }

// 壁の芯線上で、点に最も近い位置（距離と、始点からの長さ）を返す
function projectOnWall(w, x, y) {
  const dx = w[2] - w[0], dy = w[3] - w[1];
  const L = Math.hypot(dx, dy);
  if (L === 0) return null;
  let t = ((x - w[0]) * dx + (y - w[1]) * dy) / (L * L);
  t = Math.max(0, Math.min(1, t));
  const px = w[0] + dx * t, py = w[1] + dy * t;
  return { d: dist(x, y, px, py), at: t * L, x: px, y: py, len: L };
}

function nearestWall(x, y, maxD = 0.6) {
  let best = null;
  S.walls.forEach((w, i) => {
    const p = projectOnWall(w, x, y);
    if (p && p.d < maxD && (!best || p.d < best.d)) best = { ...p, wall: i + 1 };
  });
  return best;
}

// 端点へのスナップ（既存の壁の端に吸い付く）
function snapPoint(x, y) {
  let best = null;
  for (const w of S.walls) {
    for (const [px, py] of [[w[0], w[1]], [w[2], w[3]]]) {
      const d = dist(x, y, px, py);
      if (d < 0.45 && (!best || d < best.d)) best = { d, x: px, y: py };
    }
  }
  if (best) return [best.x, best.y];
  return [snap(x), snap(y)];
}

// ---------------------------------------------------------------- 描画
function draw() {
  cv.width = cv.clientWidth; cv.height = cv.clientHeight;
  ctx.fillStyle = '#12131a'; ctx.fillRect(0, 0, cv.width, cv.height);

  drawGrid();
  S.rooms.forEach(drawRoom);
  S.walls.forEach((w, i) => drawWall(w, i));
  S.openings.forEach(drawOpening);
  if (draft) drawDraft();
  drawStat();
}

function drawGrid() {
  const step = view.k >= 26 ? 1 : 5;
  const [x0, y1] = toW(0, 0), [x1, y0] = toW(cv.width, cv.height);
  ctx.lineWidth = 1;
  for (let x = Math.floor(x0 / step) * step; x <= x1; x += step) {
    const m = Math.abs(x % 5) < 1e-6;
    ctx.strokeStyle = m ? '#2b2f3d' : '#20232e';
    ctx.beginPath(); const a = toS(x, y0), b = toS(x, y1);
    ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]); ctx.stroke();
  }
  for (let y = Math.floor(y0 / step) * step; y <= y1; y += step) {
    const m = Math.abs(y % 5) < 1e-6;
    ctx.strokeStyle = m ? '#2b2f3d' : '#20232e';
    ctx.beginPath(); const a = toS(x0, y), b = toS(x1, y);
    ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]); ctx.stroke();
  }
  ctx.strokeStyle = '#3a3e4f';
  ctx.beginPath();
  let a = toS(-MAXE, 0), b = toS(MAXE, 0);
  ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]);
  a = toS(0, -MAXE); b = toS(0, MAXE);
  ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]);
  ctx.stroke();
}

function drawRoom(r) {
  ctx.beginPath();
  r.poly.forEach((p, i) => { const s = toS(p[0], p[1]); i ? ctx.lineTo(s[0], s[1]) : ctx.moveTo(s[0], s[1]); });
  ctx.closePath();
  ctx.fillStyle = 'rgba(216,161,58,.10)'; ctx.fill();
  ctx.strokeStyle = 'rgba(216,161,58,.35)'; ctx.lineWidth = 1; ctx.stroke();

  const cx = r.poly.reduce((s, p) => s + p[0], 0) / r.poly.length;
  const cy = r.poly.reduce((s, p) => s + p[1], 0) / r.poly.length;
  const c = toS(cx, cy);
  ctx.fillStyle = '#e8eaf0'; ctx.font = '600 13px "Hiragino Sans",sans-serif';
  ctx.textAlign = 'center'; ctx.fillText(r.name, c[0], c[1]);
  ctx.fillStyle = '#9aa0b4'; ctx.font = '11px ui-monospace,monospace';
  ctx.fillText(polyArea(r.poly).toFixed(1) + ' m²', c[0], c[1] + 15);
}

function polyArea(p) {
  let s = 0;
  for (let i = 0; i < p.length; i++) {
    const a = p[i], b = p[(i + 1) % p.length];
    s += a[0] * b[1] - b[0] * a[1];
  }
  return Math.abs(s) / 2;
}

function drawWall(w, i) {
  const t = THICK * view.k;
  const a = toS(w[0], w[1]), b = toS(w[2], w[3]);
  ctx.strokeStyle = (hover && hover.wall === i + 1) ? '#f0be5c' : '#c8ccd8';
  ctx.lineWidth = Math.max(3, t);
  ctx.lineCap = 'butt';
  ctx.beginPath(); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]); ctx.stroke();

  if (view.k > 22) {
    const mx = (a[0] + b[0]) / 2, my = (a[1] + b[1]) / 2;
    ctx.fillStyle = '#5d6377'; ctx.font = '10px ui-monospace,monospace';
    ctx.textAlign = 'center';
    ctx.fillText((wallLen(w) * 1000).toFixed(0), mx, my - t / 2 - 5);
  }
}

function drawOpening(o) {
  const w = S.walls[o.wall - 1]; if (!w) return;
  const L = wallLen(w);
  const ux = (w[2] - w[0]) / L, uy = (w[3] - w[1]) / L;
  const cx = w[0] + ux * o.at, cy = w[1] + uy * o.at;
  const h = o.width / 2;
  const a = toS(cx - ux * h, cy - uy * h), b = toS(cx + ux * h, cy + uy * h);

  ctx.strokeStyle = '#12131a'; ctx.lineWidth = Math.max(4, THICK * view.k + 1);
  ctx.beginPath(); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]); ctx.stroke();

  ctx.strokeStyle = o.kind === 'door' ? '#5cc08a' : '#6fa8d8';
  ctx.lineWidth = 2;
  ctx.beginPath(); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]); ctx.stroke();
}

function drawDraft() {
  if (draft.kind === 'wall') {
    const a = toS(draft.x1, draft.y1), b = toS(draft.x2, draft.y2);
    ctx.strokeStyle = '#f0be5c'; ctx.lineWidth = Math.max(3, THICK * view.k);
    ctx.setLineDash([6, 4]);
    ctx.beginPath(); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]); ctx.stroke();
    ctx.setLineDash([]);
    const L = dist(draft.x1, draft.y1, draft.x2, draft.y2);
    ctx.fillStyle = '#f0be5c'; ctx.font = '600 12px ui-monospace,monospace';
    ctx.textAlign = 'center';
    ctx.fillText((L * 1000).toFixed(0), (a[0] + b[0]) / 2, (a[1] + b[1]) / 2 - 12);
  } else if (draft.kind === 'room') {
    const x1 = Math.min(draft.x1, draft.x2), x2 = Math.max(draft.x1, draft.x2);
    const y1 = Math.min(draft.y1, draft.y2), y2 = Math.max(draft.y1, draft.y2);
    const a = toS(x1, y2), b = toS(x2, y1);
    ctx.strokeStyle = '#f0be5c'; ctx.setLineDash([6, 4]); ctx.lineWidth = 1.5;
    ctx.strokeRect(a[0], a[1], b[0] - a[0], b[1] - a[1]);
    ctx.setLineDash([]);
    ctx.fillStyle = '#f0be5c'; ctx.font = '600 12px ui-monospace,monospace';
    ctx.textAlign = 'center';
    ctx.fillText(((x2 - x1) * (y2 - y1)).toFixed(1) + ' m²',
                 (a[0] + b[0]) / 2, (a[1] + b[1]) / 2);
  }
}

function propEstimate() {
  const sizes = [4, 2, 1, .5, .25];
  let n = 2;
  for (const w of S.walls) {
    let L = wallLen(w);
    for (const s of sizes) while (L >= s - 1e-3) { L -= s; n++; }
  }
  return n;
}

function drawStat() {
  const area = S.rooms.reduce((s, r) => s + polyArea(r.poly), 0);
  const p = propEstimate();
  const over = p > 240;
  document.getElementById('stat').innerHTML =
    `壁 <b>${S.walls.length}</b>　開口 <b>${S.openings.length}</b>　室 <b>${S.rooms.length}</b><br>` +
    `延床 <b>${area.toFixed(1)}</b> m²<br>` +
    `部品 <span class="${over ? 'warn' : ''}"><b>${p}</b> / 240</span>`;
}

// ---------------------------------------------------------------- 操作
const HINTS = {
  wall: 'ドラッグで壁を引く。端点に吸い付く。Shift で角度を固定',
  door: '壁をクリックするとドアが入る（幅 900）',
  window: '壁をクリックすると窓が入る（幅 1600）',
  room: 'ドラッグで部屋を囲む。離すと名前を聞く',
  erase: 'クリックした壁・開口・部屋を消す',
};

function setTool(t) {
  tool = t;
  document.querySelectorAll('[data-tool]').forEach(b =>
    b.classList.toggle('on', b.dataset.tool === t));
  document.getElementById('hint').textContent = HINTS[t];
  draft = null; draw();
}

function push() { history.push(JSON.stringify({ w: S.walls, o: S.openings, r: S.rooms })); if (history.length > 60) history.shift(); }
function undo() {
  const h = history.pop(); if (!h) return;
  const s = JSON.parse(h); S.walls = s.w; S.openings = s.o; S.rooms = s.r; draw();
}

cv.addEventListener('mousedown', e => {
  if (e.button === 1 || e.button === 2) return;
  const [wx, wy] = toW(e.offsetX, e.offsetY);

  if (tool === 'wall' || tool === 'room') {
    const [sx, sy] = tool === 'wall' ? snapPoint(wx, wy) : [snap(wx), snap(wy)];
    draft = { kind: tool, x1: sx, y1: sy, x2: sx, y2: sy };
  } else if (tool === 'door' || tool === 'window') {
    const n = nearestWall(wx, wy);
    if (!n) return;
    const width = tool === 'door' ? 0.9 : 1.6;
    const at = Math.max(width / 2, Math.min(n.len - width / 2, snap(n.at)));
    if (n.len < width + 0.2) return;
    push();
    S.openings.push({ wall: n.wall, at, width, kind: tool });
    draw();
  } else if (tool === 'erase') {
    push();
    const n = nearestWall(wx, wy, 0.4);
    const oi = S.openings.findIndex(o => {
      const w = S.walls[o.wall - 1]; if (!w) return false;
      const L = wallLen(w), ux = (w[2] - w[0]) / L, uy = (w[3] - w[1]) / L;
      return dist(wx, wy, w[0] + ux * o.at, w[1] + uy * o.at) < 0.5;
    });
    if (oi >= 0) S.openings.splice(oi, 1);
    else if (n) {
      S.walls.splice(n.wall - 1, 1);
      S.openings = S.openings.filter(o => o.wall !== n.wall)
        .map(o => ({ ...o, wall: o.wall > n.wall ? o.wall - 1 : o.wall }));
    } else {
      const ri = S.rooms.findIndex(r => pointInPoly(r.poly, wx, wy));
      if (ri >= 0) S.rooms.splice(ri, 1);
    }
    draw();
  }
});

cv.addEventListener('mousemove', e => {
  const [wx, wy] = toW(e.offsetX, e.offsetY);
  if (draft) {
    if (draft.kind === 'wall') {
      let [x, y] = snapPoint(wx, wy);
      if (e.shiftKey || Math.abs(x - draft.x1) < 0.3 || Math.abs(y - draft.y1) < 0.3) {
        if (Math.abs(x - draft.x1) > Math.abs(y - draft.y1)) y = draft.y1; else x = draft.x1;
      }
      draft.x2 = x; draft.y2 = y;
    } else { draft.x2 = snap(wx); draft.y2 = snap(wy); }
    draw();
  } else {
    const h = nearestWall(wx, wy, 0.5);
    if ((h && h.wall) !== (hover && hover.wall)) { hover = h; draw(); }
  }
});

window.addEventListener('mouseup', () => {
  if (!draft) return;
  if (draft.kind === 'wall') {
    const L = dist(draft.x1, draft.y1, draft.x2, draft.y2);
    if (L >= SNAP) { push(); S.walls.push([draft.x1, draft.y1, draft.x2, draft.y2]); }
  } else if (draft.kind === 'room') {
    const x1 = Math.min(draft.x1, draft.x2), x2 = Math.max(draft.x1, draft.x2);
    const y1 = Math.min(draft.y1, draft.y2), y2 = Math.max(draft.y1, draft.y2);
    if ((x2 - x1) >= 0.5 && (y2 - y1) >= 0.5) {
      const name = prompt('部屋の名前', '室') || '室';
      push();
      S.rooms.push({ name, poly: [[x1, y1], [x2, y1], [x2, y2], [x1, y2]] });
    }
  }
  draft = null; draw();
});

cv.addEventListener('wheel', e => {
  e.preventDefault();
  const [bx, by] = toW(e.offsetX, e.offsetY);
  view.k = Math.max(8, Math.min(90, view.k * (e.deltaY < 0 ? 1.12 : 0.89)));
  const [ax, ay] = toW(e.offsetX, e.offsetY);
  view.x += bx - ax; view.y += by - ay;
  draw();
}, { passive: false });

// 中ボタン/右ドラッグで移動
let pan = null;
cv.addEventListener('mousedown', e => { if (e.button === 1 || e.button === 2) pan = { x: e.clientX, y: e.clientY }; });
window.addEventListener('mousemove', e => {
  if (!pan) return;
  view.x -= (e.clientX - pan.x) / view.k; view.y += (e.clientY - pan.y) / view.k;
  pan = { x: e.clientX, y: e.clientY }; draw();
});
window.addEventListener('mouseup', () => pan = null);
cv.addEventListener('contextmenu', e => e.preventDefault());

function pointInPoly(poly, x, y) {
  let ins = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const [xi, yi] = poly[i], [xj, yj] = poly[j];
    if ((yi > y) !== (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) ins = !ins;
  }
  return ins;
}

// ---------------------------------------------------------------- 連結の検査
function connectivity() {
  const roomAt = (x, y) => { for (const r of S.rooms) if (pointInPoly(r.poly, x, y)) return r.name; return null; };
  const edges = [], outs = [];
  for (const o of S.openings) {
    if (o.kind === 'window') continue;
    const w = S.walls[o.wall - 1]; if (!w) continue;
    const L = wallLen(w), ux = (w[2] - w[0]) / L, uy = (w[3] - w[1]) / L;
    const nx = -uy, ny = ux, d = THICK / 2 + 0.35;
    const cx = w[0] + ux * o.at, cy = w[1] + uy * o.at;
    const a = roomAt(cx + nx * d, cy + ny * d), b = roomAt(cx - nx * d, cy - ny * d);
    if (a && b) edges.push([a, b]); else if (a || b) outs.push(a || b);
  }
  const names = S.rooms.map(r => r.name);
  const start = outs[0] || null;
  const reach = (block) => {
    const seen = new Set(), st = start ? [start] : [];
    while (st.length) {
      const c = st.pop();
      if (seen.has(c) || c === block) continue;
      seen.add(c);
      for (const [a, b] of edges) {
        if (a === c && !seen.has(b) && b !== block) st.push(b);
        if (b === c && !seen.has(a) && a !== block) st.push(a);
      }
    }
    return seen;
  };
  const base = reach(null);
  const unreachable = names.filter(n => !base.has(n));
  const through = {};
  for (const b of names) {
    if (b === start) continue;
    const r = reach(b);
    const lost = names.filter(n => n !== b && !r.has(n) && !unreachable.includes(n));
    if (lost.length) through[b] = lost;
  }
  return { start, unreachable, through };
}

function showCheck() {
  const c = connectivity();
  const ok = s => `<span class="ok">${s}</span>`, ng = s => `<span class="ng">${s}</span>`;
  let h = '<div class="msg">';
  h += '<span class="h">連結</span>';
  if (!c.start) h += ng('外部に出る扉がありません。玄関を付けてください') + '<br>';
  else h += ok('外部から ' + c.start + ' に入れます') + '<br>';
  if (c.unreachable.length) h += ng('到達できない室: ' + c.unreachable.join(', ')) + '<br>';
  else if (c.start) h += ok('全室に到達できます') + '<br>';

  h += '<span class="h">通り抜け</span>';
  const bad = Object.entries(c.through).filter(([k]) => !/廊下|ホール|土間/.test(k));
  if (!Object.keys(c.through).length) h += ok('なし') + '<br>';
  Object.entries(c.through).forEach(([k, v]) => {
    const isHall = /廊下|ホール|土間/.test(k);
    h += (isHall ? ok(k + '（廊下なので正常）') : ng(k + ' を塞ぐと ' + v.join(', ') + ' に行けない')) + '<br>';
  });
  if (!bad.length && Object.keys(c.through).length) h += ok('居室の通り抜けはありません') + '<br>';

  h += '<span class="h">部品</span>';
  const p = propEstimate();
  h += (p > 240 ? ng(`${p} 個。上限 240 を超えています`) : ok(`${p} 個 / 240`)) + '<br>';
  h += '</div>';
  openPanel('検査', h);
}

// ---------------------------------------------------------------- パネル
function openPanel(title, html) {
  document.getElementById('ptitle').textContent = title;
  document.getElementById('pbody').innerHTML = html;
  document.getElementById('panel').classList.remove('hidden');
}
document.getElementById('pclose').onclick = () =>
  document.getElementById('panel').classList.add('hidden');

// ---------------------------------------------------------------- NUI 連携
const post = (name, data) => fetch(`https://gain_build/${name}`, {
  method: 'POST', headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify(data || {}),
});

document.querySelectorAll('[data-tool]').forEach(b => b.onclick = () => setTool(b.dataset.tool));
document.getElementById('undo').onclick = undo;
document.getElementById('check').onclick = showCheck;
document.getElementById('close').onclick = () => post('close');
document.getElementById('system').onchange = e => S.system = e.target.value;
document.getElementById('name').oninput = e => S.name = e.target.value;
document.getElementById('list').onclick = () => post('list');
document.getElementById('save').onclick = () => {
  if (!S.walls.length) { openPanel('保存', '<div class="msg"><span class="ng">壁がありません</span></div>'); return; }
  post('save', { id: S.id, name: S.name, system: S.system,
                 plan: { walls: S.walls, openings: S.openings, rooms: S.rooms } });
};

window.addEventListener('keydown', e => {
  if (document.activeElement === document.getElementById('name')) return;
  const k = e.key.toLowerCase();
  if (k === 'w') setTool('wall'); else if (k === 'd') setTool('door');
  else if (k === 'n') setTool('window'); else if (k === 'r') setTool('room');
  else if (k === 'e') setTool('erase');
  else if (k === 'z' && (e.ctrlKey || e.metaKey)) undo();
  else if (k === 'escape') post('close');
});

window.addEventListener('message', ev => {
  const d = ev.data;
  if (d.action === 'open') {
    document.getElementById('app').classList.remove('hidden');
    setTool('wall'); draw();
  } else if (d.action === 'close') {
    document.getElementById('app').classList.add('hidden');
  } else if (d.action === 'blueprints') {
    const rows = d.rows || [];
    let h = rows.length ? '' : '<div class="msg">保存された図面はありません</div>';
    rows.forEach(r => {
      h += `<div class="row" data-id="${r.id}"><span class="del" data-del="${r.id}">削除</span>
        <div class="t">${r.name}</div>
        <div class="m">${r.system}　${Number(r.area).toFixed(1)} m²　部品 ${r.props}</div></div>`;
    });
    openPanel('図面一覧', h);
    document.querySelectorAll('[data-id]').forEach(el => el.onclick = ev2 => {
      if (ev2.target.dataset.del) { post('delete', { id: +ev2.target.dataset.del }); return; }
      post('load', { id: +el.dataset.id });
    });
  } else if (d.action === 'loaded') {
    const p = typeof d.data === 'string' ? JSON.parse(d.data) : d.data;
    S.id = d.id; S.name = d.name; S.system = d.system;
    S.walls = p.walls || []; S.openings = p.openings || []; S.rooms = p.rooms || [];
    document.getElementById('name').value = S.name;
    document.getElementById('system').value = S.system;
    document.getElementById('panel').classList.add('hidden');
    draw();
  } else if (d.action === 'saved') {
    S.id = d.id;
  }
});

window.addEventListener('resize', draw);
setTool('wall');
