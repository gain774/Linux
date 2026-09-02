const root = document.getElementById('bank');
const historyEl = document.getElementById('history');

const KIND_LABEL = {
    deposit: '預け入れ',
    withdraw: '引き出し',
    transfer_in: '入金',
    transfer_out: '送金',
    salary: '給料',
};

const INCOMING = new Set(['deposit', 'transfer_in', 'salary']);

let mode = 'bank';

function post(name, data) {
    return fetch(`https://gain_banking/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data || {}),
    });
}

function escapeHtml(value) {
    return String(value).replace(/[&<>"']/g, (c) => ({
        '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
    }[c]));
}

function yen(value) {
    return '$' + Number(value || 0).toLocaleString();
}

function setState(state) {
    document.getElementById('cash').textContent = yen(state.cash);
    document.getElementById('bank-balance').textContent = yen(state.bank);
    document.getElementById('citizenid').textContent = state.citizenid || '-';

    historyEl.innerHTML = '';

    if (!state.history || state.history.length === 0) {
        historyEl.innerHTML = '<div class="entry-empty">取引はまだありません。</div>';
        return;
    }

    state.history.forEach((row) => {
        const incoming = INCOMING.has(row.kind);
        const el = document.createElement('div');
        el.className = 'entry';
        el.innerHTML = `
            <div>
                <div>${escapeHtml(KIND_LABEL[row.kind] || row.kind)}${
                    row.counterparty ? ' / ' + escapeHtml(row.counterparty) : ''
                }</div>
                <div class="when">${escapeHtml(row.created_at || '')}</div>
            </div>
            <div class="${incoming ? 'plus' : 'minus'}">${incoming ? '+' : '-'}${yen(row.amount)}</div>
        `;
        historyEl.appendChild(el);
    });
}

function selectTab(name) {
    document.querySelectorAll('.tab').forEach((el) => {
        el.classList.toggle('active', el.dataset.tab === name);
    });
    document.querySelectorAll('.form').forEach((el) => {
        el.classList.toggle('active', el.dataset.form === name);
    });
}

function open(data) {
    mode = data.mode || 'bank';
    document.getElementById('title').textContent = mode === 'atm' ? 'ATM' : '銀行';

    // 送金は窓口のみ（サーバー側でも同じ判定をしている）
    document.getElementById('tab-transfer').classList.toggle('hidden', mode === 'atm');
    selectTab('deposit');

    root.classList.remove('hidden');
}

function close() {
    root.classList.add('hidden');
    post('close');
}

document.querySelectorAll('.tab').forEach((el) => {
    el.addEventListener('click', () => selectTab(el.dataset.tab));
});

document.querySelectorAll('[data-submit]').forEach((el) => {
    el.addEventListener('click', () => {
        const kind = el.dataset.submit;

        if (kind === 'transfer') {
            post('transfer', {
                target: document.getElementById('transfer-target').value.trim(),
                amount: Number(document.getElementById('transfer-amount').value),
            });
            return;
        }

        post(kind, { amount: Number(document.getElementById(`${kind}-amount`).value) });
    });
});

document.getElementById('close').addEventListener('click', close);

document.addEventListener('keyup', (e) => {
    if (e.key === 'Escape') close();
});

window.addEventListener('message', (event) => {
    const data = event.data;
    if (!data) return;

    if (data.action === 'openBank') open(data);
    if (data.action === 'closeBank') root.classList.add('hidden');
    if (data.action === 'setState') setState(data.state);
});
