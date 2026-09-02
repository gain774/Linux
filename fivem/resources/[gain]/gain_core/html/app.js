const container = document.getElementById('toasts');
const DURATION = 5000;

function notify(message, kind) {
    const el = document.createElement('div');
    el.className = 'toast ' + (kind || 'info');
    el.textContent = message;
    container.appendChild(el);

    setTimeout(() => {
        el.classList.add('leaving');
        setTimeout(() => el.remove(), 300);
    }, DURATION);
}

window.addEventListener('message', (event) => {
    const data = event.data;
    if (!data) return;

    if (data.action === 'notify') {
        notify(data.message, data.kind);
    }
});
