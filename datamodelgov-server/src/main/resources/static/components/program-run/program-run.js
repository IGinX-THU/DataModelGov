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
    this.exportBtn = root.querySelector('.footer-actions button:nth-child(1)');
    this.saveBtn = root.querySelector('.footer-actions button:nth-child(2)');

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

    const viewDetailBtn = this.shadowRoot.querySelector('.view-detail');
    if (viewDetailBtn) viewDetailBtn.addEventListener('click', () => this.showAlertDetail());
    if (this.exportBtn) this.exportBtn.addEventListener('click', () => this.exportData());
    if (this.saveBtn) this.saveBtn.addEventListener('click', () => this.saveResults());

    window.addEventListener('resize', () => this.charts.forEach(c => c && c.resize()));
  }

  showAlertDetail() {
    const root = this.shadowRoot;
    let modal = root.querySelector('.alert-modal');
    if (modal) modal.remove();
    modal = document.createElement('div');
    modal.className = 'alert-modal';
    modal.style.cssText = 'position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,.6);z-index:9999;display:flex;align-items:center;justify-content:center;';
    const box = document.createElement('div');
    box.style.cssText = 'background:#0f172a;border:1px solid #24344D;border-radius:8px;padding:24px;max-width:500px;max-height:400px;overflow:auto;color:#e5e7eb;font-size:13px;';
    const title = document.createElement('div');
    title.style.cssText = 'font-size:15px;font-weight:600;margin-bottom:16px;color:#f59e0b;';
    title.textContent = '告警详情';
    box.appendChild(title);
    const list = root.querySelector('.alert-list');
    if (list && list.querySelector('.alert-empty')) {
      const empty = document.createElement('div');
      empty.style.cssText = 'color:#6b7280;text-align:center;padding:20px;';
      empty.textContent = '当前无告警记录';
      box.appendChild(empty);
    } else if (list) {
      Array.from(list.querySelectorAll('.alert')).forEach(a => {
        const item = document.createElement('div');
        item.style.cssText = 'padding:8px 0;border-bottom:1px solid #24344D;';
        item.textContent = a.textContent;
        box.appendChild(item);
      });
    }
    const closeBtn = document.createElement('button');
    closeBtn.textContent = '关闭';
    closeBtn.style.cssText = 'margin-top:16px;padding:6px 16px;background:#1e293b;border:1px solid #24344D;border-radius:4px;color:#e5e7eb;cursor:pointer;';
    closeBtn.addEventListener('click', () => modal.remove());
    box.appendChild(closeBtn);
    modal.appendChild(box);
    modal.addEventListener('click', e => { if (e.target === modal) modal.remove(); });
    root.appendChild(modal);
  }

  exportData() {
    if (!this.csvHeaders || !this.csvRows) {
      this.showToast('暂无数据可导出', 'warning');
      return;
    }
    const name = this.getAttribute('data-name');
    const version = this.getAttribute('data-version');
    if (!name || !version) {
      this.showToast('无法获取程序信息', 'error');
      return;
    }

    const existing = this.shadowRoot.querySelector('.export-dropdown');
    if (existing) { existing.remove(); return; }

    const dd = document.createElement('div');
    dd.className = 'export-dropdown';
    dd.innerHTML = `
      <div class="export-item" data-format="csv">📄 导出 CSV</div>
      <div class="export-item" data-format="mat">📊 导出 MAT</div>
    `;
    const btnRect = this.exportBtn.getBoundingClientRect();
    dd.style.cssText = `position:fixed;left:${btnRect.left}px;top:${btnRect.bottom + 4}px;z-index:9999;background:#0f172a;border:1px solid #24344D;border-radius:6px;box-shadow:0 4px 12px rgba(0,0,0,.5);overflow:hidden;min-width:200px;`;
    dd.querySelectorAll('.export-item').forEach(item => {
      item.style.cssText = 'padding:10px 14px;font-size:12px;color:#e5e7eb;cursor:pointer;display:flex;align-items:center;gap:6px;';
      item.addEventListener('mouseenter', () => { item.style.background = '#1e293b'; });
      item.addEventListener('mouseleave', () => { item.style.background = ''; });
    });
    document.body.appendChild(dd);

    const close = () => dd.remove();
    dd.querySelectorAll('.export-item').forEach(item => {
      item.addEventListener('click', async () => {
        close();
        const format = item.getAttribute('data-format');
        await this.downloadSignal(name, version, format);
      });
    });
    setTimeout(() => {
      document.addEventListener('click', close, { once: true });
    }, 0);
  }

  async downloadSignal(name, version, format) {
    const token = localStorage.getItem('jwtToken');
    const pn = this.getProjectName();
    const authHeaders = { 'Authorization': token ? `Bearer ${token}` : '' };
    try {
      this.showToast(`正在导出 ${format.toUpperCase()} 文件...`, 'info');
      const baseUrl = window.AppConfig.getApiUrl('program', 'download-signal');
      const url = `${baseUrl}?name=${encodeURIComponent(name)}&version=${encodeURIComponent(version)}&format=${format}${pn ? '&projectName=' + encodeURIComponent(pn) : ''}`;
      const resp = await fetch(url, { headers: authHeaders });
      if (!resp.ok) {
        if (resp.status === 401) {
          this.showToast('认证失败，请重新登录', 'error');
          return;
        }
        const text = await resp.text();
        this.showToast('导出失败: ' + (text || resp.statusText), 'error');
        return;
      }
      const blob = await resp.blob();
      const disposition = resp.headers.get('Content-Disposition') || '';
      let filename = `signals.${format}`;
      const match = disposition.match(/filename="?(.+?)"?$/);
      if (match) filename = match[1];
      const blobUrl = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = blobUrl;
      a.download = filename;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(blobUrl);
      this.showToast(`${format.toUpperCase()} 导出成功！`, 'success');
    } catch (e) {
      console.error('导出失败:', e);
      this.showToast('导出失败: ' + e.message, 'error');
    }
  }

  async saveResults() {
    const name = this.getAttribute('data-name');
    const version = this.getAttribute('data-version');
    if (!name || !version) {
      this.showToast('无法获取程序信息', 'error');
      return;
    }
    if (!this.csvHeaders || !this.csvRows) {
      this.showToast('暂无仿真数据，无法保存结果', 'warning');
      return;
    }
    const token = localStorage.getItem('jwtToken');
    const authHeaders = { 'Authorization': token ? `Bearer ${token}` : '' };
    const pn = this.getProjectName();
    try {
      this.showToast('正在保存结果...', 'info');

      // 1. 截取综合总览所有图表，合成一张带标题和图例的 overview.png
      if (this.charts.length > 0 && this.currentConfigs) {
        const cols = 2;
        const cfgs = this.currentConfigs;
        const rows = Math.ceil(this.charts.length / cols);
        const chartW = 600;
        const chartH = 260;
        const titleH = 20;
        const legendH = 20;
        const cellH = chartH + titleH + legendH;
        const padding = 10;
        const canvas = document.createElement('canvas');
        canvas.width = cols * chartW + (cols + 1) * padding;
        canvas.height = rows * cellH + (rows + 1) * padding;
        const ctx = canvas.getContext('2d');
        ctx.fillStyle = '#0b1220';
        ctx.fillRect(0, 0, canvas.width, canvas.height);

        for (let i = 0; i < this.charts.length; i++) {
          const chart = this.charts[i];
          if (!chart) continue;
          const cfg = cfgs[i];
          const col = i % cols;
          const row = Math.floor(i / cols);
          const x = padding + col * (chartW + padding);
          const y = padding + row * (cellH + padding);

          // 绘制标题
          ctx.fillStyle = '#e5e7eb';
          ctx.font = 'bold 14px sans-serif';
          ctx.textAlign = 'left';
          ctx.textBaseline = 'middle';
          ctx.fillText(cfg.title, x + 4, y + titleH / 2);

          // 绘制图例
          let legendX = x + 4;
          const legendY = y + titleH + legendH / 2;
          ctx.font = '11px sans-serif';
          ctx.textBaseline = 'middle';
          for (const s of cfg.series) {
            // 色块
            ctx.fillStyle = s.color;
            if (s.dashed) {
              ctx.fillRect(legendX, legendY - 3, 8, 2);
              ctx.fillRect(legendX + 10, legendY - 3, 8, 2);
            } else {
              ctx.fillRect(legendX, legendY - 4, 12, 4);
            }
            legendX += 16;
            // 文字
            ctx.fillStyle = '#9ca3af';
            ctx.fillText(s.name, legendX, legendY);
            legendX += ctx.measureText(s.name).width + 16;
          }

          // 截取图表
          const dataUrl = chart.getDataURL({
            type: 'png', pixelRatio: 1, backgroundColor: '#0b1220'
          });
          const img = new Image();
          img.src = dataUrl;
          await new Promise(resolve => { img.onload = resolve; img.onerror = resolve; });
          ctx.drawImage(img, x, y + titleH + legendH, chartW, chartH);
        }

        const compositeDataUrl = canvas.toDataURL('image/png');
        const base64 = compositeDataUrl.split(',')[1];
        const pngBytes = Uint8Array.from(atob(base64), c => c.charCodeAt(0));
        const uploadUrl = window.AppConfig.getApiUrl('program', 'upload-overview');
        await fetch(`${uploadUrl}?name=${encodeURIComponent(name)}&version=${encodeURIComponent(version)}${pn ? '&projectName=' + encodeURIComponent(pn) : ''}`, {
          method: 'POST',
          headers: { ...authHeaders, 'Content-Type': 'image/png' },
          body: pngBytes
        });
      }

      // 2. 下载结果包
      const baseUrl = window.AppConfig.getApiUrl('program', 'download-result');
      const url = `${baseUrl}?name=${encodeURIComponent(name)}&version=${encodeURIComponent(version)}${pn ? '&projectName=' + encodeURIComponent(pn) : ''}`;
      const resp = await fetch(url, { headers: authHeaders });
      if (!resp.ok) {
        if (resp.status === 401) {
          this.showToast('认证失败，请重新登录', 'error');
          return;
        }
        const text = await resp.text();
        this.showToast('下载结果包失败: ' + (text || resp.statusText), 'error');
        return;
      }
      const blob = await resp.blob();
      const disposition = resp.headers.get('Content-Disposition') || '';
      let filename = 'Result.zip';
      const match = disposition.match(/filename="?(.+?)"?$/);
      if (match) filename = match[1];
      const blobUrl = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = blobUrl;
      a.download = filename;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(blobUrl);

      this.showToast('结果包下载成功！', 'success');
    } catch (e) {
      console.error('保存结果失败:', e);
      this.showToast('保存结果失败: ' + e.message, 'error');
    }
  }

  getProjectName() {
    const username = window.AppConfig.getUsername ? window.AppConfig.getUsername() : localStorage.getItem('username');
    if (username) {
      const cached = JSON.parse(localStorage.getItem('currentProject_' + username) || 'null');
      if (cached) return cached.name;
    }
    return null;
  }

  showToast(message, type = 'success') {
    if (window.CommonUtils && window.CommonUtils.showToast) {
      window.CommonUtils.showToast(message, type);
    } else {
      console[type === 'error' ? 'error' : type === 'warning' ? 'warn' : 'log'](`[${type}] ${message}`);
    }
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
    if (this.csvHeaders && this.csvRows) {
      this.applyCsvToCharts(this.csvHeaders, this.csvRows);
    }
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
      const pn = this.getProjectName();
      if (pn) params.set('projectName', pn);
      const url = window.AppConfig.getApiUrl('program', 'run') + '?' + params.toString();
      const result = await window.AppConfig.request(url, { method: 'POST' });
      if (result && result.code === 200) {
        this.duration = 30;
        this.updateStatusUI('RUNNING');
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
      const pn = this.getProjectName();
      const url = window.AppConfig.getApiUrl('program', 'stop')
        + '?name=' + encodeURIComponent(name) + '&version=' + encodeURIComponent(version)
        + (pn ? '&projectName=' + encodeURIComponent(pn) : '');
      const result = await window.AppConfig.request(url, { method: 'POST' });
      if (result && result.code === 200) {
        this.stopPolling();
        this.stopRunTimer();
        this.updateStatusUI('STOPPED');
      }
    } catch (e) {
      console.error('停止运行失败:', e);
      this.showToast('停止运行失败: ' + e.message, 'error');
    }
  }

  startPolling(name, version) {
    this.stopPolling();
    this._pollTimer = setInterval(async () => {
      try {
        const pn = this.getProjectName();
        const result = await window.AppConfig.get('program', 'results', { name, version, ...(pn ? { projectName: pn } : {}) });
        if (!result || result.code !== 200 || !result.data) return;
        const data = result.data;
        const status = data.status || 'UNKNOWN';
        this.updateStatusUI(status, data.lastError);
        if (data.runLog) {
          this.runLog = data.runLog;
        }
        this.runStatus = status;
        this.runError = data.lastError || null;
        this.runTimestamp = data.lastRunTime || null;
        if (status === 'RUNNING') {
          this.duration += 30;
        }
        if (status === 'SUCCESS') {
          this.stopPolling();
          this.stopRunTimer();
          if (data.headers && data.rows) {
            this.loadCsvData(data.headers, data.rows);
          }
        }
        if (status === 'ERROR' || status === 'STOPPED') {
          this.stopPolling();
          this.stopRunTimer();
        }
      } catch (e) {
        console.error('轮询状态失败:', e);
      }
    }, 30000);
  }

  stopPolling() {
    if (this._pollTimer) {
      clearInterval(this._pollTimer);
      this._pollTimer = null;
    }
  }

  loadCsvData(headers, rows) {
    this.csvHeaders = headers;
    this.csvRows = rows;
    this.applyCsvToCharts(headers, rows);
    const colIdx = {};
    headers.forEach((h, i) => colIdx[h] = i);
    const timeCol = colIdx['time'] != null ? colIdx['time'] : 0;
    const timeData = rows.map(r => parseFloat(r[timeCol]));
    const getLastVal = (colName) => {
      if (!colName || colIdx[colName] == null) return null;
      return parseFloat(rows[rows.length - 1][colIdx[colName]]);
    };
    this.updateKpiCards(colIdx, rows, getLastVal);
    this.updateAlertSummary(colIdx, rows, timeData, getLastVal);
  }

  _makeGetLastVal(headers, rows) {
    const colIdx = {};
    headers.forEach((h, i) => colIdx[h] = i);
    return (colName) => {
      if (!colName || colIdx[colName] == null) return null;
      return parseFloat(rows[rows.length - 1][colIdx[colName]]);
    };
  }

  applyCsvToCharts(headers, rows) {
    const colIdx = {};
    headers.forEach((h, i) => colIdx[h] = i);
    const timeCol = colIdx['time'] != null ? colIdx['time'] : 0;
    const timeData = rows.map(r => parseFloat(r[timeCol]));
    const tMax = timeData.length ? timeData[timeData.length - 1] : 30;
    this.duration = tMax;

    const getSeries = (colName) => {
      if (!colName || colIdx[colName] == null) return null;
      return timeData.map((t, i) => [t, parseFloat(rows[i][colIdx[colName]])]);
    };

    const getLastVal = (colName) => {
      if (!colName || colIdx[colName] == null) return null;
      return parseFloat(rows[rows.length - 1][colIdx[colName]]);
    };

    this.currentDatas = this.currentConfigs.map(cfg => {
      // 信号与告警页签：用告警统计数据填充
      if (cfg.title === '告警统计') {
        const ALERT_LIMITS = [
          { csv: 'HPC_T4_out', danger: 1400, warn: 1200 },
          { csv: 'Pt3', danger: 3500000, warn: 3000000 },
          { csv: 'Pt45', danger: 1000000, warn: 800000 },
        ];
        const dangerCounts = timeData.map((t, i) => {
          let c = 0;
          for (const al of ALERT_LIMITS) {
            if (colIdx[al.csv] == null) continue;
            const v = parseFloat(rows[i][colIdx[al.csv]]);
            if (v >= al.danger) c++;
          }
          return [t, c];
        });
        const warnCounts = timeData.map((t, i) => {
          let c = 0;
          for (const al of ALERT_LIMITS) {
            if (colIdx[al.csv] == null) continue;
            const v = parseFloat(rows[i][colIdx[al.csv]]);
            if (v >= al.warn && v < al.danger) c++;
          }
          return [t, c];
        });
        return {
          yMin: cfg.yMin, yMax: cfg.yMax, y2Min: cfg.y2Min, y2Max: cfg.y2Max,
          seriesData: [
            { name: '一级告警', color: cfg.series[0].color, dashed: false, data: dangerCounts },
            { name: '二级告警', color: cfg.series[1].color, dashed: false, data: warnCounts },
          ]
        };
      }
      return {
        yMin: cfg.yMin, yMax: cfg.yMax, y2Min: cfg.y2Min, y2Max: cfg.y2Max,
        seriesData: cfg.series.map(s => {
          const realData = getSeries(s.csv);
          return {
            name: s.name, color: s.color, dashed: s.dashed, axis: s.axis,
            data: realData || []
          };
        })
      };
    });

    this.charts.forEach((chart, i) => {
      if (this.currentDatas[i]) {
        chart.setOption(buildEChartsOptions(this.currentDatas[i], this.currentTime), true);
      }
    });
    this.updateCursor(0, true);
  }

  updateKpiCards(colIdx, rows, getLastVal) {
    const kpiMap = [
      { name: 'Np', csv: null, unit: 'rpm', fmt: v => v ? v.toLocaleString() : '--' },
      { name: 'Ng', csv: null, unit: 'rpm', fmt: v => v ? v.toLocaleString() : '--' },
      { name: 'T45', csv: 'HPC_T4_out', unit: 'K', fmt: v => v ? v.toFixed(1) : '--' },
      { name: 'Mkp', csv: null, unit: 'N·m', fmt: v => v ? v.toFixed(1) : '--' },
      { name: 'Wf', csv: null, unit: 'kg/s', fmt: v => v ? v.toFixed(4) : '--' },
      { name: 'Error', csv: null, unit: '-', fmt: v => v != null ? v.toExponential(2) : '--' }
    ];
    const kpiGrid = this.shadowRoot.querySelector('.kpi-grid');
    if (!kpiGrid) return;
    kpiGrid.innerHTML = kpiMap.map(k => {
      const val = k.csv ? getLastVal(k.csv) : null;
      return `<div class="kpi-card"><div class="kpi-head"><span class="kpi-name">${k.name}</span><span class="kpi-icon"></span></div><div class="kpi-value">${k.fmt(val)}</div><div class="kpi-unit">${k.unit}</div></div>`;
    }).join('');
  }

  updateAlertSummary(colIdx, rows, timeData, getLastVal) {
    const alerts = [];
    const ALERT_LIMITS = [
      { name: 'T45', csv: 'HPC_T4_out', warn: 1200, danger: 1400, unit: 'K', desc: '燃气涡轮后温度超限' },
      { name: 'Pt3', csv: 'Pt3', warn: 3000000, danger: 3500000, unit: 'Pa', desc: '压气机出口压力超限' },
      { name: 'Pt45', csv: 'Pt45', warn: 800000, danger: 1000000, unit: 'Pa', desc: '涡轮后压力超限' },
    ];
    ALERT_LIMITS.forEach(al => {
      if (!al.csv || colIdx[al.csv] == null) return;
      const colI = colIdx[al.csv];
      for (let i = 0; i < rows.length; i++) {
        const v = parseFloat(rows[i][colI]);
        if (v >= al.danger) {
          alerts.push({ time: timeData[i], level: '一级', desc: `${al.name} ${al.desc} — ${al.name}=${v.toFixed(1)}${al.unit} ≥ ${al.danger}${al.unit}` });
          break;
        } else if (v >= al.warn) {
          alerts.push({ time: timeData[i], level: '二级', desc: `${al.name} ${al.desc} — ${al.name}=${v.toFixed(1)}${al.unit} ≥ ${al.warn}${al.unit}` });
          break;
        }
      }
    });

    const alertPanel = this.shadowRoot.querySelector('.alert-title');
    if (alertPanel) {
      const countSpan = alertPanel.querySelector('.alert-count');
      if (countSpan) countSpan.textContent = alerts.length;
    }
    const alertContainer = this.shadowRoot.querySelector('.alert-list');
    if (alertContainer) {
      if (alerts.length === 0) {
        alertContainer.innerHTML = '<div class="alert-empty">暂无告警</div>';
      } else {
        alertContainer.innerHTML = alerts.map(a =>
          `<div class="alert ${a.level === '一级' ? 'alert-danger' : 'alert-warn'}"><span class="alert-time">${a.time.toFixed(2)} s</span><span class="alert-icon">${a.level === '一级' ? '🔴' : '🟡'}</span>${a.desc} — ${a.level}告警</div>`
        ).join('');
      }
    }

    const statusTbody = this.shadowRoot.querySelector('.status-table tbody');
    if (statusTbody) {
      const modules = [
        { icon: '🖥', name: '控制系统', csvs: [] },
        { icon: '⛽', name: '燃油系统', csvs: [] },
        { icon: '⚙', name: '发动机总体性能', csvs: ['HPC_T4_out', 'HPC_P4_out1', 'HPC_T5_out1'] },
        { icon: '🛢', name: '滑油系统', csvs: ['OilBoundary_1', 'OilBoundary_2', 'OilBoundary_3', 'OilBoundary_4'] },
        { icon: '🌬', name: '空气系统', csvs: ['Pt1', 'Pt3', 'Pt45', 'Pt5', 'Tt1', 'Tt3', 'Tt45', 'AirBoundaryTP16_1'] },
        { icon: '🔔', name: '信号与告警', csvs: ['HPC_T4_out', 'Pt3', 'Pt45'] },
        { icon: '⚖', name: '单位一致性检查', csvs: [] },
      ];
      statusTbody.innerHTML = modules.map(m => {
        if (m.csvs.length === 0) {
          if (m.name === '单位一致性检查') {
            const issues = this.checkUnitConsistency(colIdx, rows);
            const tag = issues.length > 0 ? 'warn' : 'ok';
            const tagText = issues.length > 0 ? `${issues.length}项待确认` : '通过';
            const desc = issues.length > 0 ? issues.join('; ') : '单位一致';
            return `<tr><td class="sys-name">${m.icon} ${m.name}</td><td><span class="status-tag ${tag}">${tagText}</span></td><td class="status-desc">${desc}</td></tr>`;
          }
          const tag = 'warn';
          const tagText = '未接线';
          return `<tr><td class="sys-name">${m.icon} ${m.name}</td><td><span class="status-tag ${tag}">${tagText}</span></td><td class="status-desc">信号未接出</td></tr>`;
        }
        const connectedCount = m.csvs.filter(c => colIdx[c] != null).length;
        const connected = connectedCount > 0;
        const tagText = connected ? '已接' : '未接线';
        return `<tr><td class="sys-name">${m.icon} ${m.name}</td><td><span class="status-tag ${connected ? 'ok' : 'warn'}">${tagText}</span></td><td class="status-desc">${connected ? '数据正常' : '信号未接出'}</td></tr>`;
      }).join('');
    }
  }

  checkUnitConsistency(colIdx, rows) {
    const issues = [];
    const UNIT_EXPECT = {
      'Pt1': { unit: 'Pa', min: 50000, max: 500000 },
      'Pt3': { unit: 'Pa', min: 500000, max: 5000000 },
      'Pt45': { unit: 'Pa', min: 100000, max: 2000000 },
      'Pt5': { unit: 'Pa', min: 50000, max: 500000 },
      'Tt1': { unit: 'K', min: 200, max: 400 },
      'Tt3': { unit: 'K', min: 300, max: 1200 },
      'Tt45': { unit: 'K', min: 500, max: 1500 },
      'HPC_T4_out': { unit: 'K', min: 500, max: 2000 },
      'HPC_P4_out1': { unit: 'Pa', min: 500000, max: 5000000 },
      'HPC_T5_out1': { unit: 'K', min: 300, max: 1200 },
      'OilBoundary_1': { unit: 'K', min: 200, max: 500 },
      'OilBoundary_2': { unit: 'K', min: 200, max: 500 },
      'OilBoundary_3': { unit: 'K', min: 200, max: 500 },
      'OilBoundary_4': { unit: 'Pa', min: 50000, max: 500000 },
    };
    Object.keys(UNIT_EXPECT).forEach(col => {
      if (colIdx[col] == null) return;
      const ci = colIdx[col];
      const expect = UNIT_EXPECT[col];
      const firstVal = parseFloat(rows[0][ci]);
      const lastVal = parseFloat(rows[rows.length - 1][ci]);
      const vals = [firstVal, lastVal];
      for (const v of vals) {
        if (isNaN(v)) {
          issues.push(`${col} 含非数值`);
          break;
        }
        if (v < expect.min || v > expect.max) {
          issues.push(`${col} 值${v.toFixed(1)}超出${expect.unit}预期范围[${expect.min},${expect.max}]`);
          break;
        }
      }
    });
    return issues;
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
    if (this._lastStatus && this._lastStatus !== status) {
      const toastMap = {
        'RUNNING': { msg: '运行已开始', type: 'info' },
        'SUCCESS': { msg: '运行完成', type: 'success' },
        'STOPPED': { msg: '运行已停止', type: 'info' },
        'ERROR': { msg: errorMsg ? '运行失败: ' + errorMsg : '运行失败', type: 'error' }
      };
      const toast = toastMap[status];
      if (toast) this.showToast(toast.msg, toast.type);
    }
    this._lastStatus = status;
  }

  async queryStatus(name, version) {
    try {
      const pn = this.getProjectName();
      const result = await window.AppConfig.get('program', 'results', { name, version, ...(pn ? { projectName: pn } : {}) });
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
      if (status === 'SUCCESS' && data.headers && data.rows) {
        this.loadCsvData(data.headers, data.rows);
      }
    } catch (e) {
      this.updateStatusUI('IDLE');
    }
  }

  async loadProgramFiles(name, version) {
    try {
      const pn = this.getProjectName();
      const result = await window.AppConfig.get('program', 'files', { name, version, ...(pn ? { projectName: pn } : {}) });
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
      }

      this.queryStatus(name, version);
    } catch (e) {
      console.error('加载程序文件列表失败:', e);
    }
  }
}

customElements.define('program-run', ProgramRun);

const colors = {
  yellow: '#f59e0b', green: '#22c55e', cyan: '#06b6d4', red: '#ef4444',
  blue: '#3b82f6', orange: '#d97706', purple: '#a855f7', pink: '#ec4899',
  teal: '#14b8a6', lime: '#84cc16', indigo: '#6366f1'
};

function sig(name, color, opts = {}) {
  return { name, color, dashed: !!opts.dashed, axis: opts.axis || null, csv: opts.csv || null };
}
function chart(title, yMin, yMax, ...series) {
  return { title, yMin, yMax, series };
}
function chart2(title, yMin, yMax, y2Min, y2Max, ...series) {
  return { title, yMin, yMax, y2Min, y2Max, series };
}

const OVERVIEW_CHARTS = [
  chart('转速响应', 12000, 48000,
    sig('Np指令', colors.yellow, { dashed: true }),
    sig('Np', colors.green),
    sig('Ng', colors.cyan)
  ),
  chart('温度与扭矩', 0, 2400,
    sig('T45 (K)', colors.red, { csv: 'HPC_T4_out' }),
    sig('Mkp (N·m)', colors.blue)
  ),
  chart('燃油系统', 0, 0.25,
    sig('Wf指令', colors.yellow, { dashed: true }),
    sig('Wf实际', colors.orange)
  ),
  chart('滑油热管理', 0, 1200,
    sig('ToutA', colors.green, { csv: 'OilBoundary_1' }),
    sig('ToutB', colors.cyan, { csv: 'OilBoundary_2' }),
    sig('空滑出口油温', colors.yellow, { csv: 'OilBoundary_3' })
  ),
  chart('空气流量 G01-G08', 0, 1500,
    sig('G01', colors.red, { csv: 'AirBoundaryTP16_1' }),
    sig('G02', colors.orange, { csv: 'AirBoundaryTP16_3' }),
    sig('G03', colors.yellow, { csv: 'AirBoundaryTP16_5' }),
    sig('G04', colors.green, { csv: 'AirBoundaryTP16_7' }),
    sig('G05', colors.cyan, { csv: 'AirBoundaryTP16_9' }),
    sig('G06', colors.blue, { csv: 'AirBoundaryTP16_11' }),
    sig('G07', colors.purple, { csv: 'AirBoundaryTP16_13' }),
    sig('G08', colors.pink, { csv: 'AirBoundaryTP16_15' })
  ),
  chart2('压力与收敛', 0, 2000000, 0, 1e-6,
    sig('Pt3 (kPa)', colors.blue, { csv: 'Pt3' }),
    sig('Pt45 (kPa)', colors.cyan, { csv: 'Pt45' }),
    sig('Error', colors.yellow, { axis: 'right' })
  )
];

const CHARTS_BY_TAB = {
  '综合总览': OVERVIEW_CHARTS,
  '总体性能': [
    chart('转速响应', 12000, 48000,
      sig('Np', colors.green),
      sig('Ng', colors.cyan)
    ),
    chart('温度与扭矩', 0, 2400,
      sig('T45 (K)', colors.red, { csv: 'HPC_T4_out' }),
      sig('Mkp (N·m)', colors.blue)
    ),
    chart('温度参数', 0, 1500,
      sig('Tt1 (K)', colors.red, { csv: 'Tt1' }),
      sig('Tt3 (K)', colors.orange, { csv: 'Tt3' }),
      sig('Tt45 (K)', colors.yellow, { csv: 'Tt45' }),
      sig('T45 (K)', colors.pink, { csv: 'HPC_T4_out' })
    ),
    chart('压力参数', 0, 3500000,
      sig('Pt1 (Pa)', colors.blue, { csv: 'Pt1' }),
      sig('Pt3 (Pa)', colors.cyan, { csv: 'Pt3' }),
      sig('Pt45 (Pa)', colors.green, { csv: 'Pt45' }),
      sig('Pt5 (Pa)', colors.purple, { csv: 'Pt5' })
    )
  ],
  '控制': [
    chart('转速响应', 12000, 48000,
      sig('Np指令', colors.yellow, { dashed: true }),
      sig('Np', colors.green),
      sig('Ng', colors.cyan)
    )
  ],
  '燃油': [
    chart('燃油系统', 0, 0.25,
      sig('Wf指令', colors.yellow, { dashed: true }),
      sig('Wf实际', colors.orange)
    )
  ],
  '滑油': [
    chart('滑油热管理', 0, 1200,
      sig('ToutA', colors.green, { csv: 'OilBoundary_1' }),
      sig('ToutB', colors.cyan, { csv: 'OilBoundary_2' }),
      sig('空滑出口油温', colors.yellow, { csv: 'OilBoundary_3' }),
      sig('OilBoundary_4', colors.red, { csv: 'OilBoundary_4' })
    )
  ],
  '空气': [
    chart('空气流量 G01-G08', 0, 1500,
      sig('G01', colors.red, { csv: 'AirBoundaryTP16_1' }),
      sig('G02', colors.orange, { csv: 'AirBoundaryTP16_3' }),
      sig('G03', colors.yellow, { csv: 'AirBoundaryTP16_5' }),
      sig('G04', colors.green, { csv: 'AirBoundaryTP16_7' }),
      sig('G05', colors.cyan, { csv: 'AirBoundaryTP16_9' }),
      sig('G06', colors.blue, { csv: 'AirBoundaryTP16_11' }),
      sig('G07', colors.purple, { csv: 'AirBoundaryTP16_13' }),
      sig('G08', colors.pink, { csv: 'AirBoundaryTP16_15' })
    ),
    chart2('压力与收敛', 0, 3500000, 0, 1e-6,
      sig('Pt1 (Pa)', colors.blue, { csv: 'Pt1' }),
      sig('Pt3 (Pa)', colors.cyan, { csv: 'Pt3' }),
      sig('Pt45 (Pa)', colors.green, { csv: 'Pt45' }),
      sig('Pt5 (Pa)', colors.purple, { csv: 'Pt5' }),
      sig('Error', colors.yellow, { axis: 'right' })
    )
  ],
  '信号与告警': [
    chart('告警统计', 0, 5,
      sig('一级告警', colors.red),
      sig('二级告警', colors.orange)
    )
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
      data: []
    }))
  };
}

function buildEChartsOptions(data, time) {
  const hasData = data.seriesData.some(s => s.data.length > 0);
  const xMax = hasData
    ? data.seriesData.find(s => s.data.length > 0).data[data.seriesData.find(s => s.data.length > 0).data.length - 1][0]
    : 30;
  const yAxis = data.y2Min != null
    ? [
        { type: 'value', min: data.yMin, max: data.yMax, axisLabel: { color: '#9ca3af', fontSize: 10 }, splitLine: { lineStyle: { color: '#24344D' } }, axisLine: { lineStyle: { color: '#24344D' } } },
        { type: 'value', min: data.y2Min, max: data.y2Max, position: 'right', axisLabel: { color: '#9ca3af', fontSize: 10, formatter: v => v !== 0 && Math.abs(v) < 1e-4 ? v.toExponential(1) : v.toFixed(0) }, splitLine: { show: false }, axisLine: { lineStyle: { color: '#24344D' } } }
      ]
    : { type: 'value', min: data.yMin, max: data.yMax, axisLabel: { color: '#9ca3af', fontSize: 10 }, splitLine: { lineStyle: { color: '#24344D' } }, axisLine: { lineStyle: { color: '#24344D' } } };

  const opts = {
    backgroundColor: 'transparent',
    tooltip: { trigger: 'axis', backgroundColor: 'rgba(15,23,42,.9)', borderColor: '#24344D', textStyle: { color: '#e5e7eb' } },
    grid: { left: 40, right: data.y2Min != null ? 55 : 40, top: 32, bottom: 18 },
    toolbox: { right: 8, top: 4, iconStyle: { borderColor: '#9ca3af' }, emphasis: { iconStyle: { borderColor: '#fff' } }, feature: { restore: { title: '还原' } } },
    dataZoom: [{ type: 'inside', xAxisIndex: [0], filterMode: 'filter', start: 0, end: 100 }],
    xAxis: { type: 'value', min: 0, splitNumber: 6, axisLabel: { color: '#9ca3af', fontSize: 10 }, splitLine: { lineStyle: { color: '#24344D' } }, axisLine: { lineStyle: { color: '#24344D' } } },
    yAxis,
    series: data.seriesData.map(s => ({
      name: s.name,
      type: 'line',
      smooth: true,
      symbol: 'none',
      yAxisIndex: s.axis === 'right' ? 1 : 0,
      lineStyle: { color: s.color, width: 2, type: s.dashed ? 'dashed' : 'solid' },
      data: s.data,
      markLine: s.data.length > 0 ? {
        silent: true,
        animation: false,
        symbol: 'none',
        lineStyle: { color: '#10b981', type: 'dashed', width: 1 },
        data: [{ xAxis: time, label: { show: false } }]
      } : undefined
    }))
  };

  if (!hasData) {
    opts.graphic = {
      type: 'text',
      left: 'center',
      top: 'middle',
      style: { text: '暂无数据', fill: '#6b7280', fontSize: 14 }
    };
  }

  return opts;
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
