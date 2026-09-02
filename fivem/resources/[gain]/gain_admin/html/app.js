const RANK = { user: 0, mod: 1, admin: 2, owner: 3 };

const root = document.getElementById('admin');
const listEl = document.getElementById('players');
const searchEl = document.getElementById('search');
const targetEl = document.getElementById('target');
const emptyEl = document.getElementById('empty');

let players = [];
let meta = { self: 0, actions: {}, durations: [] };
let selected = null;

function post(name, data) {
    return fetch(`https://gain_admin/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data || {}),
    });
}

function myRank() {
    const me = players.find((p) => p.id === meta.self);
    return RANK[me ? me.permission : 'user'] ?? 0;
}

/** 自分の権限で使えない操作のブロックを隠す */
function applyPermissions() {
    const rank = myRank();

    document.querySelectorAll('[data-action-group]').forEach((el) => {
        const required = meta.actions[el.dataset.actionGroup];
        el.classList.toggle('hidden', (RANK[required] ?? 0) > rank);
    });

    document.querySelectorAll('[data-perm-group] [data-action]').forEach((el) => {
        const required = meta.actions[el.dataset.action];
        el.classList.toggle('hidden', (RANK[required] ?? 0) > rank);
    });
}

function renderList() {
    const query = searchEl.value.trim().toLowerCase();
    listEl.innerHTML = '';

    players
        .filter((p) => !query || p.name.toLowerCase().includes(query) || String(p.id).includes(query))
        .forEach((p) => {
            const el = document.createElement('div');
            el.className = 'player' + (selected === p.id ? ' selected' : '');
            el.innerHTML = `
                <div class="name">[${p.id}] ${escapeHtml(p.name)}</div>
                <div class="sub">${escapeHtml(p.permission)} / ${escapeHtml(p.job)} / ${p.ping}ms</div>
            `;
            el.addEventListener('click', () => select(p.id));
            listEl.appendChild(el);
        });
}

function escapeHtml(value) {
    return String(value).replace(/[&<>"']/g, (c) => ({
        '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
    }[c]));
}

function select(id) {
    selected = id;
    const p = players.find((x) => x.id === id);

    if (!p) {
        targetEl.classList.add('hidden');
        emptyEl.classList.remove('hidden');
        return;
    }

    emptyEl.classList.add('hidden');
    targetEl.classList.remove('hidden');
    document.getElementById('target-name').textContent = `[${p.id}] ${p.name}`;
    document.getElementById('target-meta').innerHTML = `
        ID: ${escapeHtml(p.citizenid)}<br>
        権限: ${escapeHtml(p.permission)} / 職業: ${escapeHtml(p.job)}<br>
        現金: $${p.cash.toLocaleString()} / 銀行: $${p.bank.toLocaleString()}
    `;
    document.getElementById('perm-level').value = p.permission;

    renderList();
}

function payloadFor(action) {
    switch (action) {
        case 'givemoney':
            return {
                account: document.getElementById('money-account').value,
                amount: Number(document.getElementById('money-amount').value),
            };
        case 'kick':
            return { reason: document.getElementById('kick-reason').value };
        case 'ban':
            return {
                minutes: Number(document.getElementById('ban-duration').value),
                reason: document.getElementById('ban-reason').value,
            };
        case 'setperm':
            return { level: document.getElementById('perm-level').value };
        default:
            return {};
    }
}

function open(data) {
    players = data.players || [];
    meta = data.meta || meta;

    const durationEl = document.getElementById('ban-duration');
    durationEl.innerHTML = '';
    (meta.durations || []).forEach((d) => {
        const opt = document.createElement('option');
        opt.value = d.minutes;
        opt.textContent = d.label;
        durationEl.appendChild(opt);
    });

    root.classList.remove('hidden');
    applyPermissions();
    renderList();

    if (selected !== null) select(selected);
}

function close() {
    root.classList.add('hidden');
    post('close');
}

document.querySelectorAll('[data-action]').forEach((el) => {
    el.addEventListener('click', () => {
        if (selected === null) return;
        const action = el.dataset.action;
        post('action', { name: action, target: selected, payload: payloadFor(action) });
    });
});

document.getElementById('spawn-vehicle').addEventListener('click', () => {
    const model = document.getElementById('vehicle-model').value.trim();
    if (model) post('spawnVehicle', { model });
});

document.getElementById('refresh').addEventListener('click', () => post('refresh'));
document.getElementById('close').addEventListener('click', close);
searchEl.addEventListener('input', renderList);

document.addEventListener('keyup', (e) => {
    if (e.key === 'Escape') close();
});

window.addEventListener('message', (event) => {
    const data = event.data;
    if (!data) return;

    if (data.action === 'openAdmin') open(data);
    if (data.action === 'closeAdmin') root.classList.add('hidden');
});
