const root = document.getElementById('jobs');
const listEl = document.getElementById('list');

function post(name, data) {
    return fetch(`https://gain_jobs/${name}`, {
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

function render(jobs, current) {
    listEl.innerHTML = '';

    const currentJob = jobs.find((j) => j.current);
    document.getElementById('current').textContent = currentJob ? currentJob.label : '無職';
    document.getElementById('quit').classList.toggle('hidden', !currentJob);

    jobs.forEach((job) => {
        const el = document.createElement('div');
        el.className = 'job' + (job.current ? ' current-job' : '');
        el.innerHTML = `
            <div>
                <div class="name">${escapeHtml(job.label)}</div>
                <div class="sub">初任給 $${Number(job.salary).toLocaleString()} / 勤務地: ${escapeHtml(job.duty)}</div>
            </div>
        `;

        const button = document.createElement('button');
        button.textContent = job.current ? '勤務中' : '応募する';
        button.disabled = job.current;
        button.addEventListener('click', () => post('apply', { name: job.name }));

        el.appendChild(button);
        listEl.appendChild(el);
    });
}

function close() {
    root.classList.add('hidden');
    post('close');
}

document.getElementById('close').addEventListener('click', close);
document.getElementById('quit').addEventListener('click', () => post('apply', { name: 'unemployed' }));

document.addEventListener('keyup', (e) => {
    if (e.key === 'Escape') close();
});

window.addEventListener('message', (event) => {
    const data = event.data;
    if (!data) return;

    if (data.action === 'openJobs') {
        render(data.jobs || [], data.current);
        root.classList.remove('hidden');
    }

    if (data.action === 'closeJobs') root.classList.add('hidden');
});
