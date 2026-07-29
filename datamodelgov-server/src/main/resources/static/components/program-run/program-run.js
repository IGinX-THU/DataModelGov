class ProgramRun extends HTMLElement {
  constructor() {
    super();
    this.attachShadow({ mode: 'open' });
    this.charts = [];
    this.currentTime = 0;
    this.duration = 30;
    this.speed = 1;
    this.playing = false;
    this.activeTab = '综合总览';
    this.timer = null;
    this.dragging = false;
    this.currentConfigs = [];
    this.currentDatas = [];
    this._runTimer = null;
    this._runStartTime = null;
  }

  async connectedCallback() {
    await this.loadResources();
    const echartsUrl = new URL('lib/echarts/echarts.min.js', document.baseURI).href;
    try {
      await this.loadScript(echartsUrl);
    } catch (e) {
      console.error('加载 ECharts 失败', e);
      return;
    }
    this.init();
  }

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

  loadScript(url) {
    return new Promise((resolve, reject) => {
      if (window.echarts) { resolve(); return; }
      const s = document.createElement('script');
      s.src = url;
      s.onload = resolve;
      s.onerror = reject;
      document.head.appendChild(s);
    });
  }

  init() {
    const root = this.shadowRoot;
    this.echarts = window.echarts;
    this.tabs = Array.from(root.querySelectorAll('.tab'));
    this.chartGrid = root.querySelector('.chart-grid');
    this.flow = root.querySelector('.flow');
    this.timeTrack = root.querySelector('.time-track');
    this.timeCursor = root.querySelector('.time-cursor');
    this.timeProgress = root.querySelector('.time-progress');
    this.timeMark = root.querySelector('.time-mark');
    this.cursorVal = root.querySelector('.cursor-val');
    this.timeBox = root.querySelector('.time-box');
    this.statusBox = root.querySelector('.status-box');
    this.statusDot = root.querySelector('.status-box .dot');
    this.runBtn = root.querySelector('.btn-run');
    this.stopBtn = root.querySelector('.btn-stop');
    this.closeBtn = root.querySelector('#closeBtn');
    const playWrap = root.querySelector('.play');
    this.prevBtn = playWrap.querySelector('button:nth-child(1)');
    this.playBtn = playWrap.querySelector('button:nth-child(2)');
    this.nextBtn = playWrap.querySelector('button:nth-child(3)');
    this.speedBtns = Array.from(playWrap.querySelectorAll('span'));

    this.bindEvents();
    this.renderTab(this.activeTab);
    this.updateCursor(this.currentTime, true);
    this.updateStatusUI('IDLE');
  }

  bindEvents() {
    if (this.closeBtn) this.closeBtn.addEventListener('click', () => this.hide());
    this.tabs.forEach(t => t.addEventListener('click', () => this.renderTab(t.textContent.trim())));
    this.playBtn.addEventListener('click', () => this.togglePlay());
    this.prevBtn.addEventListener('click', () => this.updateCursor(this.currentTime - 1));
    this.nextBtn.addEventListener('click', () => this.updateCursor(this.currentTime + 1));
    this.speedBtns.forEach(s => s.addEventListener('click', () => {
      this.speed = parseFloat(s.textContent);
      this.speedBtns.forEach(b => b.classList.toggle('active', b === s));
      if (this.playing) { this.stopPlay(); this.startPlay(); }
    }));

    if (this.runBtn) this.runBtn.addEventListener('click', () => this.handleRun());
    if (this.stopBtn) this.stopBtn.addEventListener('click', () => this.handleStop());

    this.timeTrack.addEventListener('click', (e) => {
      if (this.timeCursor.contains(e.target)) return;
      const rect = this.timeTrack.getBoundingClientRect();
      const pct = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width));
      this.updateCursor(pct * this.duration);
    });

    this.timeCursor.addEventListener('pointerdown', (e) => {
      this.dragging = true;
      e.stopPropagation();
      this.timeCursor.setPointerCapture(e.pointerId);
    });
    this.timeCursor.addEventListener('pointermove', (e) => {
      if (!this.dragging) return;
      const rect = this.timeTrack.getBoundingClientRect();
      const pct = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width));
      this.updateCursor(pct * this.duration);
    });
    this.timeCursor.addEventListener('pointerup', (e) => {
      this.dragging = false;
      this.timeCursor.releasePointerCapture(e.pointerId);
    });

    window.addEventListener('resize', () => this.charts.forEach(c => c && c.resize()));
  }

  renderTab(tab) {
    this.activeTab = tab;
    this.tabs.forEach(t => t.classList.toggle('active', t.textContent.trim() === tab));
    this.flow.style.display = tab === '综合总览' ? '' : 'none';
    const cfgs = CHARTS_BY_TAB[tab] || CHARTS_BY_TAB['综合总览'];
    this.charts.forEach(c => c.dispose());
    this.charts = [];
    this.currentConfigs = cfgs;
    this.currentDatas = cfgs.map(buildChartData);
    this.chartGrid.innerHTML = '';
    this.chartGrid.classList.toggle('single', cfgs.length === 1);

    cfgs.forEach((cfg, i) => {
      const card = document.createElement('div');
      card.className = 'chart-card';
      const head = document.createElement('div');
      head.className = 'chart-head';
      const title = document.createElement('span');
      title.className = 'chart-title';
      title.textContent = cfg.title;
      head.appendChild(title);
      card.appendChild(head);
      const dom = document.createElement('div');
      dom.className = 'chart-dom';
      card.appendChild(dom);
      this.chartGrid.appendChild(card);
      buildLegend(card, cfg);

      const chart = this.echarts.init(dom, null, { renderer: 'canvas', backgroundColor: 'transparent' });
      chart.setOption(buildEChartsOptions(this.currentDatas[i], this.currentTime), true);
      this.charts.push(chart);
    });
    requestAnimationFrame(() => this.charts.forEach(c => c && c.resize()));
  }

  togglePlay() {
    if (this.playing) this.stopPlay(); else this.startPlay();
  }

  startPlay() {
    this.playing = true;
    this.playBtn.textContent = '⏸';
    const step = 0.05;
    this.timer = setInterval(() => {
      let t = this.currentTime + step * this.speed;
      if (t >= this.duration) t = 0;
      this.updateCursor(t);
    }, 50);
  }

  stopPlay() {
    this.playing = false;
    this.playBtn.textContent = '▶';
    clearInterval(this.timer);
    this.timer = null;
  }

  updateCursor(time, skipCharts) {
    time = Math.max(0, time);
    this.currentTime = time;
    const cappedTime = Math.min(time, this.duration);
    const pct = (cappedTime / this.duration) * 100;
    this.timeProgress.style.width = pct + '%';
    this.timeCursor.style.left = pct + '%';
    this.timeMark.style.left = pct + '%';
    this.timeMark.textContent = time.toFixed(2) + ' s';
    if (this.cursorVal) this.cursorVal.textContent = time.toFixed(2) + ' s';
    if (this.timeBox) this.timeBox.textContent = time.toFixed(2) + ' / ' + this.duration.toFixed(2) + ' s';

    if (!skipCharts && this.charts.length) {
      const mark = {
        silent: true,
        animation: false,
        symbol: 'none',
        lineStyle: { color: '#10b981', type: 'dashed', width: 1 },
        data: [{ xAxis: cappedTime, label: { show: false } }]
      };
      this.charts.forEach((chart, i) => {
        const data = this.currentDatas[i];
        if (!data) return;
        const seriesUpdate = data.seriesData.map(() => ({ markLine: mark }));
        chart.setOption({ series: seriesUpdate });
      });
    }
  }

  show() {
    this.style.display = 'block';
    if (this.charts) this.charts.forEach(c => c && c.resize());
  }

  hide() {
    this.style.display = 'none';
    this.stopPolling();
    this.stopRunTimer();
  }

  startRunTimer(serverStartTime) {
    this.stopRunTimer();
    this._runStartTime = serverStartTime || Date.now();
    this._runTimer = setInterval(() => {
      if (!this._runStartTime) return;
      const elapsed = (Date.now() - this._runStartTime) / 1000;
      this.updateCursor(elapsed);
    }, 100);
  }

  stopRunTimer() {
    if (this._runTimer) {
      clearInterval(this._runTimer);
      this._runTimer = null;
    }
    this._runStartTime = null;
  }

  async handleRun() {
    const name = this.getAttribute('data-name');
    const version = this.getAttribute('data-version');
    if (!name || !version) return;
    try {
      this.updateStatusUI('RUNNING');
      const root = this.shadowRoot;
      const inputs = root.querySelectorAll('.field-row .input-box input');
      const select = root.querySelector('.field-row .input-box select');
      const params = new URLSearchParams();
      params.set('name', name);
      params.set('version', version);
      if (inputs.length >= 1 && inputs[0].value) params.set('stopTime', inputs[0].value);
      if (inputs.length >= 2 && inputs[1].value) params.set('fixedStep', inputs[1].value);
      if (inputs.length >= 3 && inputs[2].value) params.set('npCommand', inputs[2].value);
      if (inputs.length >= 4 && inputs[3].value) params.set('loadPower', inputs[3].value);
      if (select && select.value) {
        params.set('modelFile', select.value);
      }
      const url = window.AppConfig.getApiUrl('program', 'run') + '?' + params.toString();
      const result = await window.AppConfig.request(url, { method: 'POST' });
      if (result && result.code === 200) {
        this.duration = 10;
        this.startPolling(name, version);
        this.startRunTimer(Date.now());
      } else {
        this.updateStatusUI('ERROR', result ? result.msg : '启动失败');
      }
    } catch (e) {
      console.error('启动运行失败:', e);
      this.updateStatusUI('ERROR', e.message);
    }
  }

  async handleStop() {
    const name = this.getAttribute('data-name');
    const version = this.getAttribute('data-version');
    if (!name || !version) return;
    try {
      const url = window.AppConfig.getApiUrl('program', 'stop')
        + '?name=' + encodeURIComponent(name) + '&version=' + encodeURIComponent(version);
      const result = await window.AppConfig.request(url, { method: 'POST' });
      if (result && result.code === 200) {
        this.stopPolling();
        this.stopRunTimer();
        this.updateStatusUI('STOPPED');
      }
    } catch (e) {
      console.error('停止运行失败:', e);
    }
  }

  startPolling(name, version) {
    this.stopPolling();
    this._pollTimer = setInterval(async () => {
      try {
        const result = await window.AppConfig.get('program', 'results', { name, version });
        if (!result || result.code !== 200 || !result.data) return;
        const data = result.data;
        const status = data.status || 'UNKNOWN';
        this.updateStatusUI(status, data.lastError);
        if (data.runLog) {
          console.log('[运行日志]', data.runLog);
        }
        if (status === 'RUNNING') {
          this.duration += 10;
        }
        if (status === 'SUCCESS' || status === 'ERROR' || status === 'STOPPED') {
          this.stopPolling();
          this.stopRunTimer();
        }
      } catch (e) {
        console.error('轮询状态失败:', e);
      }
    }, 10000);
  }

  stopPolling() {
    if (this._pollTimer) {
      clearInterval(this._pollTimer);
      this._pollTimer = null;
    }
  }

  updateStatusUI(status, errorMsg) {
    const statusTexts = {
      'IDLE': '就绪',
      'RUNNING': '仿真运行中',
      'SUCCESS': '运行完成',
      'ERROR': '运行错误',
      'STOPPED': '已停止',
      'UNKNOWN': '未知状态'
    };
    const statusColors = {
      'IDLE': '#9ca3af',
      'RUNNING': '#22c55e',
      'SUCCESS': '#3b82f6',
      'ERROR': '#ef4444',
      'STOPPED': '#9ca3af',
      'UNKNOWN': '#9ca3af'
    };
    if (this.statusBox) {
      const text = statusTexts[status] || status;
      this.statusBox.innerHTML = `<span class="dot" style="background:${statusColors[status] || '#9ca3af'}"></span>${text}`;
    }
    if (this.runBtn && this.stopBtn) {
      const running = status === 'RUNNING';
      this.runBtn.disabled = running;
      this.stopBtn.disabled = !running;
    }
  }

  async queryStatus(name, version) {
    try {
      const result = await window.AppConfig.get('program', 'results', { name, version });
      if (!result || result.code !== 200 || !result.data) {
        this.updateStatusUI('IDLE');
        return;
      }
      const data = result.data;
      const status = data.status || 'IDLE';
      this.updateStatusUI(status, data.lastError);
      if (status === 'RUNNING') {
        this.startPolling(name, version);
        this.startRunTimer(data.lastRunTime);
      }
    } catch (e) {
      this.updateStatusUI('IDLE');
    }
  }

  async loadProgramFiles(name, version) {
    try {
      const result = await window.AppConfig.get('program', 'files', { name, version });
      if (!result || result.code !== 200 || !result.data) {
        console.warn('获取程序文件列表失败', result);
        return;
      }
      const data = result.data;
      if (!data.found) {
        console.warn('程序目录不存在:', data.message);
        return;
      }
      this.programFilesData = data;

      const root = this.shadowRoot;
      const modelFileSelect = root.querySelectorAll('.field-row .input-box select')[0];
      if (modelFileSelect && data.modelFiles) {
        modelFileSelect.innerHTML = data.modelFiles.map(f =>
          `<option value="${f}">${f}</option>`
        ).join('');

        const updateModelTag = () => {
          const tag = root.querySelector('.model-tag');
          if (tag) {
            const mn = this.programFilesData && this.programFilesData.params
              ? this.programFilesData.params.modelName : '';
            tag.textContent = mn || modelFileSelect.value.replace(/\.(slx|mdl)$/i, '');
          }
        };
        modelFileSelect.removeEventListener('change', this._modelSelectHandler);
        this._modelSelectHandler = updateModelTag;
        modelFileSelect.addEventListener('change', updateModelTag);
        updateModelTag();
      }

      if (data.params) {
        const p = data.params;
        if (p.stopTime) {
          this.duration = parseFloat(p.stopTime) || 30;
          this.updateCursor(0, true);
        }
        const inputs = root.querySelectorAll('.field-row .input-box input');
        if (inputs.length >= 1 && p.stopTime) inputs[0].value = p.stopTime;
        if (inputs.length >= 2 && p.fixedStep) inputs[1].value = p.fixedStep;
        if (inputs.length >= 3 && p.npCommand) inputs[2].value = p.npCommand;
        if (inputs.length >= 4 && p.loadPower) inputs[3].value = p.loadPower;

        if (p.kpiParams) {
          const kpiGrid = root.querySelector('.kpi-grid');
          if (kpiGrid) {
            kpiGrid.innerHTML = p.kpiParams.map(k =>
              `<div class="kpi-card"><div class="kpi-head"><span class="kpi-name">${k.name}</span><span class="kpi-icon"></span></div><div class="kpi-value">${k.value}</div><div class="kpi-unit">${k.unit}</div></div>`
            ).join('');
          }
        }

        if (p.systemModules) {
          const tbody = root.querySelector('.status-table tbody');
          if (tbody) {
            tbody.innerHTML = p.systemModules.map(m =>
              `<tr><td class="sys-name">${m.icon} ${m.name}</td><td><span class="status-tag ${m.status}">${m.statusText}</span></td><td class="status-desc">${m.desc}</td></tr>`
            ).join('');
          }
        }
      }

      this.queryStatus(name, version);
    } catch (e) {
      console.error('加载程序文件列表失败:', e);
    }
  }
}

customElements.define('program-run', ProgramRun);

const TIME = Array.from({ length: 61 }, (_, i) => i * 0.5);

const colors = {
  yellow: '#f59e0b', green: '#22c55e', cyan: '#06b6d4', red: '#ef4444',
  blue: '#3b82f6', orange: '#d97706', purple: '#a855f7', pink: '#ec4899',
  teal: '#14b8a6', lime: '#84cc16', indigo: '#6366f1'
};

function sStep(name, color, low, high, delay) {
  return { name, color, dashed: true, fn: x => x < delay ? low : high };
}
function sRise(name, color, start, target, delay, tau) {
  return { name, color, fn: x => start + (target - start) * (1 - Math.exp(-Math.max(0, x - delay) / tau)) };
}
function sRightRise(name, color, start, target, delay, tau) {
  return { name, color, axis: 'right', fn: x => start + (target - start) * (1 - Math.exp(-Math.max(0, x - delay) / tau)) };
}
function sSine(name, color, base, amp, freq, phase) {
  return { name, color, fn: x => base + amp * Math.sin(freq * x + phase) };
}
function sConst(name, color, val) {
  return { name, color, fn: x => val };
}
function chart(title, yMin, yMax, ...series) {
  return { title, yMin, yMax, series };
}
function chart2(title, yMin, yMax, y2Min, y2Max, ...series) {
  return { title, yMin, yMax, y2Min, y2Max, series };
}

const OVERVIEW_CHARTS = [
  chart('转速响应', 12000, 48000,
    sStep('Np指令', colors.yellow, 21000, 25000, 5),
    sRise('Np', colors.green, 12000, 20812, 5, 3),
    sRise('Ng', colors.cyan, 12000, 38046, 6, 4)
  ),
  chart('温度与扭矩', 0, 2400,
    sRise('T45 (K)', colors.red, 600, 1182, 6, 4),
    sRise('Mkp (N·m)', colors.blue, 0, 1046, 6, 4)
  ),
  chart('燃油系统', 0, 0.25,
    sStep('Wf指令', colors.yellow, 0, 0.20, 2),
    sRise('Wf实际', colors.orange, 0, 0.153, 2, 3)
  ),
  chart('滑油热管理', 0, 120,
    sRise('ToutA', colors.green, 30, 100, 6, 4),
    sRise('ToutB', colors.cyan, 30, 95, 7, 4),
    sRise('空滑出口油温', colors.yellow, 30, 110, 5, 3)
  ),
  chart('空气流量 G01-G08', 0, 100,
    sRise('G01', colors.red, 10, 35, 5, 3),
    sRise('G02', colors.orange, 15, 45, 6, 3),
    sRise('G03', colors.yellow, 20, 55, 5, 3),
    sRise('G04', colors.green, 25, 65, 7, 3),
    sRise('G05', colors.cyan, 30, 75, 5, 3),
    sRise('G06', colors.blue, 35, 85, 6, 3),
    sRise('G07', colors.purple, 40, 85, 5, 3),
    sRise('G08', colors.pink, 45, 85, 7, 3)
  ),
  chart2('压力与收敛', 0, 4500, 0, 1e-6,
    sRise('Pt3 (kPa)', colors.blue, 1000, 2500, 4, 2),
    sRise('Pt45 (kPa)', colors.cyan, 500, 1000, 4, 3),
    sRightRise('Error', colors.yellow, 0, 2.1e-7, 8, 3)
  )
];

const CHARTS_BY_TAB = {
  '综合总览': OVERVIEW_CHARTS,
  '总体性能': [
    chart('发动机总体性能', 0, 45000, sRise('Np (rpm)', colors.green, 0, 20812, 5, 3), sRise('Ng (rpm)', colors.cyan, 0, 38046, 6, 4))
  ],
  '控制': [
    chart('控制系统响应', 0, 25000, sStep('Np指令', colors.yellow, 21000, 25000, 5), sRise('Np实际', colors.green, 0, 20812, 5, 3))
  ],
  '燃油': [
    chart('燃油系统', 0, 0.25, sStep('Wf指令', colors.yellow, 0, 0.20, 2), sRise('Wf实际', colors.orange, 0, 0.153, 2, 3))
  ],
  '滑油': [
    chart('滑油系统', 0, 120, sRise('ToutA (°C)', colors.green, 30, 100, 6, 4), sRise('ToutB (°C)', colors.cyan, 30, 95, 7, 4))
  ],
  '空气': [
    chart2('空气系统', 0, 3000, 0, 1600, sRise('Pc2 (kPa)', colors.blue, 200, 2500, 5, 3), sRightRise('T41 (K)', colors.orange, 600, 1300, 5, 4))
  ],
  '信号与告警': [
    chart('告警统计', 0, 5, sStep('一级告警', colors.red, 0, 1, 12), sStep('二级告警', colors.orange, 0, 2, 12))
  ]
};

function buildChartData(cfg) {
  return {
    yMin: cfg.yMin,
    yMax: cfg.yMax,
    y2Min: cfg.y2Min,
    y2Max: cfg.y2Max,
    seriesData: cfg.series.map(s => ({
      name: s.name,
      color: s.color,
      dashed: s.dashed,
      axis: s.axis,
      data: TIME.map(t => [t, s.fn(t)])
    }))
  };
}

function buildEChartsOptions(data, time) {
  const yAxis = data.y2Min != null
    ? [
        { type: 'value', min: data.yMin, max: data.yMax, axisLabel: { color: '#9ca3af', fontSize: 10 }, splitLine: { lineStyle: { color: '#24344D' } }, axisLine: { lineStyle: { color: '#24344D' } } },
        { type: 'value', min: data.y2Min, max: data.y2Max, position: 'right', axisLabel: { color: '#9ca3af', fontSize: 10, formatter: v => v !== 0 && Math.abs(v) < 1e-4 ? v.toExponential(1) : v.toFixed(0) }, splitLine: { show: false }, axisLine: { lineStyle: { color: '#24344D' } } }
      ]
    : { type: 'value', min: data.yMin, max: data.yMax, axisLabel: { color: '#9ca3af', fontSize: 10 }, splitLine: { lineStyle: { color: '#24344D' } }, axisLine: { lineStyle: { color: '#24344D' } } };

  return {
    backgroundColor: 'transparent',
    tooltip: { trigger: 'axis', backgroundColor: 'rgba(15,23,42,.9)', borderColor: '#24344D', textStyle: { color: '#e5e7eb' } },
    grid: { left: 40, right: data.y2Min != null ? 55 : 40, top: 8, bottom: 18 },
    xAxis: { type: 'value', min: 0, max: 30, interval: 5, axisLabel: { color: '#9ca3af', fontSize: 10 }, splitLine: { lineStyle: { color: '#24344D' } }, axisLine: { lineStyle: { color: '#24344D' } } },
    yAxis,
    series: data.seriesData.map(s => ({
      name: s.name,
      type: 'line',
      smooth: true,
      symbol: 'none',
      yAxisIndex: s.axis === 'right' ? 1 : 0,
      lineStyle: { color: s.color, width: 2, type: s.dashed ? 'dashed' : 'solid' },
      data: s.data,
      markLine: {
        silent: true,
        animation: false,
        symbol: 'none',
        lineStyle: { color: '#10b981', type: 'dashed', width: 1 },
        data: [{ xAxis: time, label: { show: false } }]
      }
    }))
  };
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
      ? 'background:repeating-linear-gradient(90deg,' + s.color + ',' + s.color + ' 2px,transparent 2px,transparent 4px)'
      : 'background:' + s.color;
    return '<span class=\'legend-item\'><span class=\'legend-color\' style=\'' + style + '\'></span>' + s.name + '</span>';
  }).join('');
}
