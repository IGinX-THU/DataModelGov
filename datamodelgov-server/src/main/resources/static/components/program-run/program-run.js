class ProgramRun extends HTMLElement {
  constructor() { super(); this.attachShadow({ mode: 'open' }); }
  async connectedCallback() {
    await this.loadResources();
    requestAnimationFrame(() => this.drawCharts());
    window.addEventListener('resize', () => this.drawCharts());
  }
  show() { this.style.display = 'block'; requestAnimationFrame(() => this.drawCharts()); }
  hide() { this.style.display = 'none'; }
  async loadResources() {
    const base = 'components/program-run/';
    const link = document.createElement('link');
    link.rel = 'stylesheet';
    link.href = base + 'program-run.css';
    this.shadowRoot.appendChild(link);
    const res = await fetch(base + 'program-run.html');
    const html = await res.text();
    const wrapper = document.createElement('div');
    wrapper.innerHTML = html;
    this.shadowRoot.appendChild(wrapper);
  }
  drawCharts() {
    this.shadowRoot.querySelectorAll('.chart-canvas').forEach((c, i) => {
      if (CHARTS[i]) drawChart(c, CHARTS[i]);
    });
  }
}
customElements.define('program-run', ProgramRun);

const colors = {
  yellow: '#f59e0b', green: '#22c55e', cyan: '#06b6d4', red: '#ef4444',
  blue: '#3b82f6', orange: '#d97706', purple: '#a855f7', pink: '#ec4899',
  teal: '#14b8a6', lime: '#84cc16', indigo: '#6366f1'
};

const CHARTS = [
  {
    title: '转速响应', yMin: 12000, yMax: 48000,
    series: [
      { name: 'Np指令', color: colors.yellow, dashed: true, fn: x => x < 5 ? 21000 : 25000 },
      { name: 'Np', color: colors.green, fn: x => 12000 + (20812 - 12000) * (1 - Math.exp(-Math.max(0, x - 5) / 3)) },
      { name: 'Ng', color: colors.cyan, fn: x => 12000 + (38046 - 12000) * (1 - Math.exp(-Math.max(0, x - 6) / 4)) }
    ]
  },
  {
    title: '温度与扭矩', yMin: 0, yMax: 2400,
    series: [
      { name: 'T45 (K)', color: colors.red, fn: x => 600 + 582 * (1 - Math.exp(-Math.max(0, x - 6) / 4)) },
      { name: 'Mkp (N·m)', color: colors.blue, fn: x => 1046 * (1 - Math.exp(-Math.max(0, x - 6) / 4)) }
    ]
  },
  {
    title: '燃油系统', yMin: 0, yMax: 0.25,
    series: [
      { name: 'Wf指令', color: colors.yellow, dashed: true, fn: x => x < 2 ? 0 : 0.20 },
      { name: 'Wf实际', color: colors.orange, fn: x => 0.153 * (1 - Math.exp(-Math.max(0, x - 2) / 3)) }
    ]
  },
  {
    title: '滑油热管理', yMin: 0, yMax: 120,
    series: [
      { name: 'ToutA', color: colors.green, fn: x => 30 + 70 * (1 - Math.exp(-Math.max(0, x - 6) / 4)) },
      { name: 'ToutB', color: colors.cyan, fn: x => 30 + 65 * (1 - Math.exp(-Math.max(0, x - 7) / 4)) },
      { name: '空滑出口油温', color: colors.yellow, fn: x => 30 + 80 * (1 - Math.exp(-Math.max(0, x - 5) / 3)) }
    ]
  },
  {
    title: '空气流量 G01-G08', yMin: 0, yMax: 100,
    series: [
      { name: 'G01', color: colors.red, fn: x => 10 + 25 * (1 - Math.exp(-Math.max(0, x - 5) / 3)) },
      { name: 'G02', color: colors.orange, fn: x => 15 + 30 * (1 - Math.exp(-Math.max(0, x - 6) / 3)) },
      { name: 'G03', color: colors.yellow, fn: x => 20 + 35 * (1 - Math.exp(-Math.max(0, x - 5) / 3)) },
      { name: 'G04', color: colors.green, fn: x => 25 + 40 * (1 - Math.exp(-Math.max(0, x - 7) / 3)) },
      { name: 'G05', color: colors.cyan, fn: x => 30 + 45 * (1 - Math.exp(-Math.max(0, x - 5) / 3)) },
      { name: 'G06', color: colors.blue, fn: x => 35 + 50 * (1 - Math.exp(-Math.max(0, x - 6) / 3)) },
      { name: 'G07', color: colors.purple, fn: x => 40 + 45 * (1 - Math.exp(-Math.max(0, x - 5) / 3)) },
      { name: 'G08', color: colors.pink, fn: x => 45 + 40 * (1 - Math.exp(-Math.max(0, x - 7) / 3)) }
    ]
  },
  {
    title: '压力与收敛', yMin: 0, yMax: 4500, y2Min: 0, y2Max: 1e-6,
    series: [
      { name: 'Pt3 (kPa)', color: colors.blue, fn: x => 1000 + 1500 * (1 - Math.exp(-Math.max(0, x - 4) / 2)) },
      { name: 'Pt45 (kPa)', color: colors.cyan, fn: x => 500 + 500 * (1 - Math.exp(-Math.max(0, x - 4) / 3)) },
      { name: 'Error', color: colors.yellow, axis: 'right', fn: x => 2.1e-7 * (1 - Math.exp(-Math.max(0, x - 8) / 3)) }
    ]
  }
];

function drawChart(canvas, cfg) {
  const ctx = canvas.getContext('2d');
  canvas.width = canvas.clientWidth;
  canvas.height = canvas.clientHeight;
  const w = canvas.width, h = canvas.height, pad = 32;
  const cw = w - 2 * pad, ch = h - 2 * pad;
  ctx.clearRect(0, 0, w, h);

  ctx.strokeStyle = '#24344D';
  ctx.lineWidth = 1;
  for (let i = 1; i < 5; i++) { ctx.beginPath(); ctx.moveTo(pad, pad + i * ch / 4); ctx.lineTo(w - pad, pad + i * ch / 4); ctx.stroke(); }
  for (let i = 0; i < 7; i++) { ctx.beginPath(); ctx.moveTo(pad + i * cw / 6, pad); ctx.lineTo(pad + i * cw / 6, h - pad); ctx.stroke(); }

  ctx.fillStyle = '#9ca3af';
  ctx.font = '10px sans-serif';
  ctx.textAlign = 'center';
  for (let i = 0; i < 7; i++) { const x = pad + i * cw / 6; ctx.fillText(String(i * 5), x, h - pad + 13); }

  ctx.textAlign = 'right';
  for (let i = 0; i <= 4; i++) { const y = pad + ch - i * ch / 4; const v = cfg.yMin + i * (cfg.yMax - cfg.yMin) / 4; ctx.fillText(String(Math.round(v)), pad - 4, y + 3); }

  if (cfg.y2Min != null) {
    ctx.textAlign = 'left';
    for (let i = 0; i <= 4; i++) { const y = pad + ch - i * ch / 4; const v = cfg.y2Min + i * (cfg.y2Max - cfg.y2Min) / 4; const t = v < 1e-4 ? v.toExponential(1) : String(Math.round(v)); ctx.fillText(t, w - pad + 2, y + 3); }
  }

  cfg.series.forEach(s => {
    ctx.strokeStyle = s.color;
    ctx.lineWidth = 2;
    ctx.setLineDash(s.dashed ? [5, 3] : []);
    ctx.beginPath();
    let started = false;
    for (let xi = 0; xi <= 60; xi++) {
      const xv = xi * 0.5;
      const yv = s.fn(xv);
      const yr = (s.axis === 'right' && cfg.y2Max != null) ? (cfg.y2Max - cfg.y2Min) : (cfg.yMax - cfg.yMin);
      const ymin = (s.axis === 'right' && cfg.y2Max != null) ? cfg.y2Min : cfg.yMin;
      const x = pad + (xv / 30) * cw;
      const y = pad + ch - (yv - ymin) / yr * ch;
      if (!started) { ctx.moveTo(x, y); started = true; } else ctx.lineTo(x, y);
    }
    ctx.stroke();
    ctx.setLineDash([]);
  });

  buildLegend(canvas.parentNode, cfg);
}

function buildLegend(card, cfg) {
  const head = card.querySelector('.chart-head');
  if (!head) return;
  let leg = head.querySelector('.chart-legend');
  if (!leg) {
    leg = document.createElement('div');
    leg.className = 'chart-legend';
    head.appendChild(leg);
  }
  leg.innerHTML = cfg.series.map(s => {
    const style = s.dashed
      ? `background:repeating-linear-gradient(90deg,${s.color},${s.color} 2px,transparent 2px,transparent 4px)`
      : `background:${s.color}`;
    return `<span class="legend-item"><span class="legend-color" style="${style}"></span>${s.name}</span>`;
  }).join('');
}
