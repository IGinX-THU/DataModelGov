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

    this.customVarMode = false;

    this.selectedVars = new Set();

    this.kpiParams = null;

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

    this.renderVarTree();

    this.bindVarEvents();

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

    this.renderVarTree();

    if (tab === '信号与告警') {
      this.selectedVars = new Set();
      this.renderAlertChart();
      return;
    }

    this.selectAllVarsForTab(tab);

    this.renderCustomCharts();

  }

  renderAlertChart() {
    const cfgs = CHARTS_BY_TAB['信号与告警'] || [];
    this.charts.forEach(c => c.dispose());
    this.charts = [];
    this.currentConfigs = cfgs;
    this.currentDatas = cfgs.map(buildChartData);
    if (this.csvHeaders && this.csvRows) {
      this.applyCsvToCharts(this.csvHeaders, this.csvRows);
    }
    this.chartGrid.innerHTML = '';
    this.chartGrid.classList.toggle('single', cfgs.length === 1);
    this.chartGrid.classList.remove('chart-scroll');
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

  selectAllVarsForTab(tab) {
    this.selectedVars = new Set();
    VARIABLE_CATALOG.forEach((grp, gi) => {
      if (grp.tab !== tab) return;
      grp.vars.forEach((v, vi) => {
        this.selectedVars.add(`${gi}_${vi}`);
      });
    });
    const root = this.shadowRoot;
    if (root) {
      root.querySelectorAll('.var-tree input[type="checkbox"]').forEach(cb => { cb.checked = true; });
    }
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



  renderVarTree() {
    const container = this.shadowRoot.getElementById('varTree');
    if (!container) return;
    const activeTab = this.activeTab || '综合总览';
    let html = '';
    VARIABLE_CATALOG.forEach((grp, gi) => {
      if (grp.tab !== activeTab) return;
      const hasIO = grp.vars.some(v => v.io);
      const allChecked = grp.vars.every((v, vi) => this.selectedVars && this.selectedVars.has(`${gi}_${vi}`));
      html += `<div class="var-group" data-group="${gi}">`;
      html += `<div class="var-group-header" data-gi="${gi}"><input type="checkbox" class="var-group-check" data-gi="${gi}" ${allChecked ? 'checked' : ''}>${grp.group}</div>`;
      const renderVarItem = (v, vi) => {
        const id = `var_${gi}_${vi}`;
        const checked = this.selectedVars && this.selectedVars.has(`${gi}_${vi}`) ? 'checked' : '';
        const cn = v.cnName ? `<span class="var-cn">${v.cnName}</span>` : '';
        return `<li class="var-item" data-gi="${gi}" data-vi="${vi}">
          <input type="checkbox" id="${id}" data-gi="${gi}" data-vi="${vi}" ${checked}>
          <span class="var-name">${v.name}</span>
          ${cn}
          <span class="var-unit">${v.unit || ''}</span>
        </li>`;
      };
      if (hasIO) {
        const plainVars = grp.vars.map((v, vi) => ({ v, vi })).filter(x => !x.v.io);
        const inputVars = grp.vars.map((v, vi) => ({ v, vi })).filter(x => x.v.io === 'input');
        const outputVars = grp.vars.map((v, vi) => ({ v, vi })).filter(x => x.v.io === 'output');
        html += '<div class="var-group-body">';
        if (plainVars.length > 0) {
          html += '<ul class="var-group-items">';
          plainVars.forEach(({ v, vi }) => { html += renderVarItem(v, vi); });
          html += '</ul>';
        }
        const renderSubGroup = (label, vars) => {
          if (vars.length === 0) return;
          const subAllChecked = vars.every(({ vi }) => this.selectedVars && this.selectedVars.has(`${gi}_${vi}`));
          html += `<div class="var-io-group"><div class="var-io-header"><input type="checkbox" class="var-io-check" data-gi="${gi}" data-io="${label === '输入' ? 'input' : 'output'}" ${subAllChecked ? 'checked' : ''}>${label}</div><ul class="var-group-items">`;
          vars.forEach(({ v, vi }) => { html += renderVarItem(v, vi); });
          html += '</ul></div>';
        };
        renderSubGroup('输入', inputVars);
        renderSubGroup('输出', outputVars);
        html += '</div>';
      } else {
        html += '<ul class="var-group-items">';
        grp.vars.forEach((v, vi) => { html += renderVarItem(v, vi); });
        html += '</ul>';
      }
      html += '</div>';
    });
    container.innerHTML = html;
  }

  bindVarEvents() {
    const root = this.shadowRoot;
    const tree = root.getElementById('varTree');
    if (!tree) return;
    tree.addEventListener('change', (e) => {
      const cb = e.target;
      if (cb.classList.contains('var-group-check')) {
        const gi = parseInt(cb.dataset.gi);
        const grp = VARIABLE_CATALOG[gi];
        grp.vars.forEach((v, vi) => {
          if (cb.checked) this.selectedVars.add(`${gi}_${vi}`);
          else this.selectedVars.delete(`${gi}_${vi}`);
        });
        this.renderVarTree();
        this.renderCustomCharts();
      } else if (cb.classList.contains('var-io-check')) {
        const gi = parseInt(cb.dataset.gi);
        const ioType = cb.dataset.io;
        const grp = VARIABLE_CATALOG[gi];
        grp.vars.forEach((v, vi) => {
          if (v.io === ioType) {
            if (cb.checked) this.selectedVars.add(`${gi}_${vi}`);
            else this.selectedVars.delete(`${gi}_${vi}`);
          }
        });
        this.renderVarTree();
        this.renderCustomCharts();
      } else if (cb.dataset.gi !== undefined && cb.dataset.vi !== undefined) {
        const gi = parseInt(cb.dataset.gi);
        const vi = parseInt(cb.dataset.vi);
        if (cb.checked) this.selectedVars.add(`${gi}_${vi}`);
        else this.selectedVars.delete(`${gi}_${vi}`);
        this.renderVarTree();
        this.renderCustomCharts();
      }
    });
  }

  renderCustomCharts() {
    const cfgs = [];
    let colorIdx = 0;
    this.selectedVars.forEach(key => {
      const [gi, vi] = key.split('_').map(Number);
      const grp = VARIABLE_CATALOG[gi];
      if (!grp || !grp.vars[vi]) return;
      const v = grp.vars[vi];
      const series = v.csvs.map((csv, si) => {
        const subName = v.csvs.length > 1 ? csv : v.name;
        const color = VAR_COLORS[colorIdx % VAR_COLORS.length];
        colorIdx++;
        return sig(subName, color, { csv });
      });
      cfgs.push(chartUnit(v.cnName || v.name, v.unit, ...series));
    });
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

        this.duration = parseFloat(inputs[0].value) || 30;

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

        this.handleResultData(result.data, name, version);

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

    // keep duration from stop time input; do not override with CSV tMax



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

        const ALERT_ITEMS = [
          { csv: 'T45', limitCsv: 'T45Max' },
          { csv: 'Mkp', limitCsv: 'MkpMax' },
          { csv: 'Ng', limitCsv: 'NgMax' },
        ];

        const limits = ALERT_ITEMS.map(al => {
          if (colIdx[al.csv] == null || colIdx[al.limitCsv] == null) return null;
          const limitVal = parseFloat(rows[rows.length - 1][colIdx[al.limitCsv]]);
          if (!limitVal || !isFinite(limitVal)) return null;
          return { csv: al.csv, limit: limitVal };
        }).filter(Boolean);

        const dangerCounts = timeData.map((t, i) => {

          let c = 0;

          for (const al of limits) {

            const v = parseFloat(rows[i][colIdx[al.csv]]);

            if (v >= al.limit) c++;

          }

          return [t, c];

        });

        const warnCounts = timeData.map((t, i) => {

          let c = 0;

          for (const al of limits) {

            const v = parseFloat(rows[i][colIdx[al.csv]]);

            if (v >= al.limit * 0.9 && v < al.limit) c++;

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

        yMin: cfg.yMin, yMax: cfg.yMax, y2Min: cfg.y2Min, y2Max: cfg.y2Max, unit: cfg.unit || null,

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



  renderKpiFromParams() {

    if (!this.kpiParams) return;

    const kpiGrid = this.shadowRoot.querySelector('.kpi-grid');

    if (!kpiGrid) return;

    const fmtMap = {
      'Np': v => v ? Number(v).toLocaleString() : '--',
      'Ng': v => v ? Number(v).toLocaleString() : '--',
      'T45': v => v ? Number(v).toFixed(1) : '--',
      'Mkp': v => v ? Number(v).toFixed(1) : '--',
      'Wf': v => v ? Number(v).toFixed(4) : '--',
      'Error': v => v != null && v !== '' ? Number(v).toString() : '--'
    };

    kpiGrid.innerHTML = this.kpiParams.map(k => {

      const fmt = fmtMap[k.name] || (v => v != null ? v : '--');

      return `<div class="kpi-card"><div class="kpi-head"><span class="kpi-name">${k.name}</span><span class="kpi-icon"></span></div><div class="kpi-value">${fmt(k.value)}</div><div class="kpi-unit">${k.unit}</div></div>`;

    }).join('');

  }



  updateAlertSummary(colIdx, rows, timeData, getLastVal) {

    const alerts = [];

    const ALERT_LIMITS = [

      { name: 'T45', csv: 'T45', limitCsv: 'T45Max', unit: 'K', desc: '燃气涡轮后温度超限' },

      { name: 'Mkp', csv: 'Mkp', limitCsv: 'MkpMax', unit: 'N·m', desc: '动力涡轮扭矩超限' },

      { name: 'Ng', csv: 'Ng', limitCsv: 'NgMax', unit: 'rpm', desc: '燃气涡轮转速超限' },

    ];

    ALERT_LIMITS.forEach(al => {

      if (!al.csv || colIdx[al.csv] == null) return;

      if (!al.limitCsv || colIdx[al.limitCsv] == null) return;

      const colI = colIdx[al.csv];

      const limitVal = parseFloat(rows[rows.length - 1][colIdx[al.limitCsv]]);

      if (!limitVal || !isFinite(limitVal)) return;

      for (let i = 0; i < rows.length; i++) {

        const v = parseFloat(rows[i][colI]);

        if (v >= limitVal) {

          alerts.push({ time: timeData[i], level: '一级', desc: `${al.name} ${al.desc} — ${al.name}=${v.toFixed(1)}${al.unit} ≥ ${limitVal}${al.unit}` });

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

        { icon: '🖥', name: '控制系统', csvs: ['CLP', 'Np', 'Ng', 'T45', 'Mkp', 'Ngc', 'Wf_cmd', 'NpDem'] },

        { icon: '⛽', name: '燃油系统', csvs: ['WfProxyCmd', 'Wf_kgps', 'Wf', 'Wf_cmd'] },

        { icon: '⚙', name: '发动机总体性能', csvs: ['Pt1', 'Tt1', 'Pt3', 'Tt3', 'Pt45', 'Tt45', 'Pt5', 'Tt5', 'HPC_T4_out', 'HPC_P4_out1', 'HPC_T5_out1', 'Np', 'Ng', 'Mkp'] },

        { icon: '🛢', name: '滑油系统', csvs: ['Q_BearingA', 'Q_BearingB', 'Q_AirOil', 'Q_Accessory', 'QA', 'QB', 'PA', 'PB', 'ToutA', 'ToutB', 'QretA', 'QretB', 'QgenA', 'QgenB', 'FuelOilCooler_Q', 'FuelOilCooler_FuelTout', 'AirOilCooler_Pin_Pa', 'AirOilCooler_Pout_Pa', 'FuelOilCooler_Pin_Pa', 'FuelOilCooler_Pout_Pa', 'CavityState8_PaK_1', 'SealLeak4_kgps_1', 'VentFlow3_kgps_1', 'SealDeltaP4_Pa_1', 'VentDeltaP2_Pa_1', 'MassResidual2_kgps_1', 'FuelOil2_ToutC_QkW_1', 'AirOil2_ToutC_QkW_1'] },

        { icon: '🌬', name: '空气系统', csvs: ['Pt1', 'Tt1', 'Pt3', 'Tt3', 'Pt45', 'Tt45', 'Pt5', 'Tt5', 'G01_GT1_IN_W_kgps', 'G02_GT1_OUT_W_kgps', 'G03_GT2_IN_W_kgps', 'G04_GT2_OUT_W_kgps', 'G05_PT1_IN_ROOT_W_kgps', 'G06_PT1_OUT_ROOT_W_kgps', 'G07_PT2_IN_TIP_W_kgps', 'G08_PT2_OUT_TIP_W_kgps'] },

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

          return `<tr><td class="sys-name">${m.icon} ${m.name}</td><td><span class="status-tag warn">未接线</span></td><td class="status-desc">信号未接出</td></tr>`;

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

    const statusMap = {
      'running': 'RUNNING',
      'success': 'SUCCESS',
      'failed': 'ERROR',
      'stopped': 'STOPPED',
      'pending': 'IDLE'
    };
    status = statusMap[status] || status;

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

      if (status === 'SUCCESS') {
        if (window.loadDataSourceTree) window.loadDataSourceTree();
        const dataIcon = document.querySelector('.bottom-sidebar-icon.left-sidebar-icon[data-panel="data"]');
        if (dataIcon && !dataIcon.classList.contains('active')) dataIcon.click();
      }

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

      this.handleResultData(result.data, name, version);

    } catch (e) {

      this.updateStatusUI('IDLE');

    }

  }



  handleResultData(data, name, version) {

    const statusMap = {
      'running': 'RUNNING',
      'success': 'SUCCESS',
      'failed': 'ERROR',
      'stopped': 'STOPPED',
      'pending': 'IDLE'
    };
    const status = statusMap[data.status] || data.status || 'UNKNOWN';

    this.updateStatusUI(status, data.lastError);

    if (data.runLog) {

      this.runLog = data.runLog;

    }

    this.runStatus = status;

    this.runError = data.lastError || null;

    this.runTimestamp = data.lastRunTime || null;

    if (this.kpiParams) {

      this.kpiParams.forEach(k => {

        if (k.name === 'Np' && data.npCommand) k.value = data.npCommand;

        if (k.name === 'Mkp' && data.loadPower) k.value = data.loadPower;

      });

      this.renderKpiFromParams();

    }

    if (data.headers && data.rows) {

      this.loadCsvData(data.headers, data.rows);

    }

    if (status === 'RUNNING' && name && version) {

      this.startPolling(name, version);

      this.startRunTimer(data.lastRunTime);

    }

    if (status === 'SUCCESS' || status === 'ERROR' || status === 'STOPPED') {

      this.stopPolling();

      this.stopRunTimer();

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



        const lastModelFile = data.params && data.params.modelFile

          ? data.params.modelFile : null;

        if (lastModelFile && data.modelFiles.includes(lastModelFile)) {

          modelFileSelect.value = lastModelFile;

        } else if (data.modelFiles.length > 0) {

          modelFileSelect.value = data.modelFiles[0];

        }



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
          this.kpiParams = p.kpiParams;
          this.renderKpiFromParams();
        }

      }



      this.queryStatus(name, version);

    } catch (e) {

      console.error('加载程序文件列表失败:', e);

    }

  }

}



customElements.define('program-run', ProgramRun);



// ── 变量目录（按文档章节分类，区分输入/输出） ──
const VARIABLE_CATALOG = [
  {
    group: '综合总览', tab: '综合总览',
    vars: [
      { name: 'NpDem+Np_fbk', cnName: '动力涡轮转速指令+反馈', csvs: ['NpDem', 'Np_fbk'], unit: 'rpm' },
      { name: 'Ng_fbk', cnName: '燃气涡轮转速反馈', csvs: ['Ng_fbk'], unit: 'rpm' },
      { name: 'T45_fbk', cnName: '燃气涡轮后温度反馈', csvs: ['T45_fbk'], unit: 'K' },
      { name: 'Mkp_fbk', cnName: '动力涡轮扭矩反馈', csvs: ['Mkp_fbk'], unit: 'N·m' },
      { name: 'Wfcmd', cnName: '燃油流量指令', csvs: ['Wf_cmd', 'Wf'], unit: 'kg/s' },
    ]
  },
  {
    group: '控制系统', tab: '控制',
    vars: [
      { name: 'CLP', cnName: '综合控制逻辑', csvs: ['CLP'], unit: '-' },
      { name: 'NpDem+Np_fbk', cnName: '动力涡轮转速指令+反馈', csvs: ['NpDem', 'Np_fbk'], unit: 'rpm' },
      { name: 'NgMax+Ng_fbk', cnName: '燃气涡轮转速限制+反馈', csvs: ['NgMax', 'Ng_fbk'], unit: 'rpm' },
      { name: 'T45Max+T45_fbk', cnName: '燃气涡轮后温度限制+反馈', csvs: ['T45Max', 'T45_fbk'], unit: 'K' },
      { name: 'MkpMax+Mkp_fbk', cnName: '动力涡轮扭矩限制+反馈', csvs: ['MkpMax', 'Mkp_fbk'], unit: 'N·m' },
      { name: 'Ngc', cnName: '燃气涡轮换算转速', csvs: ['Ngc'], unit: '-' },
      { name: 'Wfcmd', cnName: '燃油流量指令', csvs: ['Wf_cmd', 'Wf'], unit: 'kg/s' },
    ]
  },
  {
    group: '发动机总体性能', tab: '总体性能',
    vars: [
      { name: 'Wf', cnName: '实际燃油流量', csvs: ['Wf', 'Wf_kgps'], unit: 'kg/s' },
      { name: 'Power', cnName: '负载/输出功率指令', csvs: ['Power_cmd'], unit: 'W' },
      { name: 'HP_PowerExtract', cnName: '高压轴功率提取保留槽', csvs: ['HP_PowerExtract'], unit: 'W' },
      { name: 'Pt1/P1', cnName: '发动机进口总压', csvs: ['Pt1', 'P1'], unit: 'Pa' },
      { name: 'Tt1/T1', cnName: '发动机进口总温', csvs: ['Tt1', 'T1'], unit: 'K' },
      { name: 'Pt3', cnName: '压气机出口总压', csvs: ['Pt3', 'Pt3_fbk'], unit: 'Pa' },
      { name: 'Tt3', cnName: '压气机出口总温', csvs: ['Tt3', 'Tt3_fbk'], unit: 'K' },
      { name: 'Pt45/P45', cnName: '燃气涡轮后总压', csvs: ['Pt45', 'P45'], unit: 'Pa' },
      { name: 'Tt45/T45', cnName: '燃气涡轮后总温', csvs: ['Tt45', 'T45', 'HPC_T4_out'], unit: 'K' },
      { name: 'Pt5/P5', cnName: '动力涡轮出口总压', csvs: ['Pt5', 'P5'], unit: 'Pa' },
      { name: 'Tt5/T5', cnName: '动力涡轮出口总温', csvs: ['Tt5', 'T5'], unit: 'K' },
      { name: 'Np', cnName: '动力涡轮机械转速', csvs: ['Np'], unit: 'rpm' },
      { name: 'Ng', cnName: '燃气涡轮机械转速', csvs: ['Ng'], unit: 'rpm' },
      { name: 'SM_HPC', cnName: '高压压气机裕度类监测量', csvs: ['SM_HPC'], unit: '-' },
      { name: 'Mkp', cnName: '动力涡轮扭矩', csvs: ['Mkp'], unit: 'N·m' },
      { name: 'HPC_u6', cnName: 'HPC附加监测量', csvs: ['HPC_u6'], unit: '-' },
      { name: 'HPT_y16', cnName: 'HPT附加监测量', csvs: ['HPT_y16'], unit: '-' },
      { name: 'LPT_y16', cnName: 'LPT附加监测量', csvs: ['LPT_y16'], unit: '-' },
      { name: 'Error', cnName: '总体收敛误差最大值', csvs: ['errmax'], unit: '-' },
      { name: 'Pt4/P4', cnName: '燃烧室出口总压', csvs: ['HPC_P4_out1', 'P4'], unit: 'Pa' },
      { name: 'Tt4/T4', cnName: '燃烧室出口总温', csvs: ['HPC_T4_out', 'T4'], unit: 'K' },
    ]
  },
  {
    group: '燃油模块', tab: '燃油',
    vars: [
      { name: 'WfProxyCmd+Wf_kgps', cnName: '计量燃油指令', csvs: ['WfProxyCmd', 'Wf_kgps'], unit: 'kg/s' },
      { name: 'Δp_fuel', cnName: '油压/计量压差', csvs: ['dp_fuel'], unit: 'MPa', io: 'input' },
      { name: 'lock_meter', cnName: '计量活门闭锁信号', csvs: ['lock_meter'], unit: '0/1', io: 'input' },
      { name: 'xm_ref_sb', cnName: '计量位移台架激励', csvs: ['xm_ref_sb'], unit: 'm', io: 'input' },
      { name: 'xm_cmd_m', cnName: '计量位移联仿指令', csvs: ['xm_cmd_m'], unit: 'm', io: 'input' },
      { name: 'lock_igv', cnName: '导叶活门闭锁信号', csvs: ['lock_igv'], unit: '0/1', io: 'input' },
      { name: 'xd_cmd', cnName: '导叶位移指令', csvs: ['xd_cmd'], unit: 'm', io: 'input' },
      { name: 'shutdown', cnName: '停车信号', csvs: ['shutdown'], unit: '0/1', io: 'input' },
      { name: 'xm', cnName: '计量活门位移输出', csvs: ['xm'], unit: 'm', io: 'output' },
      { name: 'Wf', cnName: '计量燃油质量流量', csvs: ['Wf', 'Wf_kgps'], unit: 'kg/s', io: 'output' },
      { name: 'xd', cnName: '导叶活门位移输出', csvs: ['xd'], unit: 'm', io: 'output' },
    ]
  },
  {
    group: '滑油模块', tab: '滑油',
    vars: [
      { name: 'Ng_fbk', cnName: '燃气涡轮转速', csvs: ['Ng_fbk'], unit: 'rpm', io: 'input' },
      { name: 'Np_fbk', cnName: '动力涡轮转速', csvs: ['Np_fbk'], unit: 'rpm', io: 'input' },
      { name: 'AirOil_Teff_C', cnName: '空滑有效空气温度', csvs: ['Oil_AirTemp_C'], unit: '℃', io: 'input' },
      { name: 'OilPump_Displacement_cc_rev', cnName: '滑油泵排量', csvs: ['OilPump_Displacement_cc_rev'], unit: 'cc/rev', io: 'input' },
      { name: 'Wf_kgps', cnName: '计量燃油量', csvs: ['Wf_kgps'], unit: 'kg/s', io: 'input' },
      { name: 'VentBoundary10', cnName: '通风边界向量', csvs: ['VentBoundary10_1','VentBoundary10_2','VentBoundary10_3','VentBoundary10_4','VentBoundary10_5','VentBoundary10_6','VentBoundary10_7','VentBoundary10_8','VentBoundary10_9','VentBoundary10_10'], unit: 'Pa/K', io: 'input' },
      { name: 'OilInlet2_C', cnName: '燃滑/空滑入口油温向量', csvs: ['OilInlet2_C_1','OilInlet2_C_2'], unit: '℃', io: 'input' },
      { name: 'Q_BearingA', cnName: '甲轴承腔换热量', csvs: ['Q_BearingA'], unit: 'W', io: 'output' },
      { name: 'Q_BearingB', cnName: '乙轴承腔换热量', csvs: ['Q_BearingB'], unit: 'W', io: 'output' },
      { name: 'Q_AirOil', cnName: '空滑换热量', csvs: ['Q_AirOil'], unit: 'W', io: 'output' },
      { name: 'Q_Accessory', cnName: '机匣附件换热量', csvs: ['Q_Accessory'], unit: 'W', io: 'output' },
      { name: 'QA', cnName: '甲轴承腔供油流量', csvs: ['QA'], unit: 'm³/s', io: 'output' },
      { name: 'QB', cnName: '乙轴承腔供油流量', csvs: ['QB'], unit: 'm³/s', io: 'output' },
      { name: 'PA', cnName: '甲轴承腔油路压力', csvs: ['PA'], unit: 'Pa', io: 'output' },
      { name: 'PB', cnName: '乙轴承腔油路压力', csvs: ['PB'], unit: 'Pa', io: 'output' },
      { name: 'ToutA', cnName: '甲轴承腔出口油温', csvs: ['ToutA'], unit: 'K', io: 'output' },
      { name: 'ToutB', cnName: '乙轴承腔出口油温', csvs: ['ToutB'], unit: 'K', io: 'output' },
      { name: 'QretA', cnName: 'A腔回油流量', csvs: ['QretA'], unit: 'm³/s', io: 'output' },
      { name: 'QretB', cnName: 'B腔回油流量', csvs: ['QretB'], unit: 'm³/s', io: 'output' },
      { name: 'QgenA', cnName: '甲轴承腔生热量', csvs: ['QgenA'], unit: 'W', io: 'output' },
      { name: 'QgenB', cnName: '乙轴承腔生热量', csvs: ['QgenB'], unit: 'W', io: 'output' },
      { name: 'FuelOilCooler_Q', cnName: '燃滑换热量', csvs: ['FuelOilCooler_Q'], unit: 'W', io: 'output' },
      { name: 'FuelOilCooler_FuelTout', cnName: '燃滑燃油出口温度', csvs: ['FuelOilCooler_FuelTout'], unit: 'K', io: 'output' },
      { name: 'AirOilCooler_Pin', cnName: '空滑入口压力', csvs: ['AirOilCooler_Pin_Pa'], unit: 'Pa', io: 'output' },
      { name: 'AirOilCooler_Pout', cnName: '空滑出口压力', csvs: ['AirOilCooler_Pout_Pa'], unit: 'Pa', io: 'output' },
      { name: 'FuelOilCooler_Pin', cnName: '燃滑入口压力', csvs: ['FuelOilCooler_Pin_Pa'], unit: 'Pa', io: 'output' },
      { name: 'FuelOilCooler_Pout', cnName: '燃滑出口压力', csvs: ['FuelOilCooler_Pout_Pa'], unit: 'Pa', io: 'output' },
      { name: 'CavityState8', cnName: 'A/B腔前后压力温度状态', csvs: ['CavityState8_PaK_1','CavityState8_PaK_2','CavityState8_PaK_3','CavityState8_PaK_4','CavityState8_PaK_5','CavityState8_PaK_6','CavityState8_PaK_7','CavityState8_PaK_8'], unit: 'Pa/K', io: 'output' },
      { name: 'SealLeak4', cnName: 'A前/A后/B前/B后封严泄漏', csvs: ['SealLeak4_kgps_1','SealLeak4_kgps_2','SealLeak4_kgps_3','SealLeak4_kgps_4'], unit: 'kg/s', io: 'output' },
      { name: 'VentFlow3', cnName: 'A腔/B腔/总通风流量', csvs: ['VentFlow3_kgps_1','VentFlow3_kgps_2','VentFlow3_kgps_3'], unit: 'kg/s', io: 'output' },
      { name: 'SealDeltaP4', cnName: '四路封严压差', csvs: ['SealDeltaP4_Pa_1','SealDeltaP4_Pa_2','SealDeltaP4_Pa_3','SealDeltaP4_Pa_4'], unit: 'Pa', io: 'output' },
      { name: 'VentDeltaP2', cnName: 'A/B腔通风压损', csvs: ['VentDeltaP2_Pa_1','VentDeltaP2_Pa_2'], unit: 'Pa', io: 'output' },
      { name: 'MassResidual2', cnName: 'A/B腔质量残差', csvs: ['MassResidual2_kgps_1','MassResidual2_kgps_2'], unit: 'kg/s', io: 'output' },
      { name: 'FuelOil2_ToutC_QkW', cnName: '燃滑出口油温/散热量', csvs: ['FuelOil2_ToutC_QkW_1','FuelOil2_ToutC_QkW_2'], unit: '℃/kW', io: 'output' },
      { name: 'AirOil2_ToutC_QkW', cnName: '空滑出口油温/散热量', csvs: ['AirOil2_ToutC_QkW_1','AirOil2_ToutC_QkW_2'], unit: '℃/kW', io: 'output' },
    ]
  },
  {
    group: '空气模块', tab: '空气',
    vars: [
      { name: 'AirBoundaryTP16', cnName: 'G01-G08总温总压边界', csvs: ['AirBoundaryTP16_1','AirBoundaryTP16_3','AirBoundaryTP16_5','AirBoundaryTP16_7','AirBoundaryTP16_9','AirBoundaryTP16_11','AirBoundaryTP16_13','AirBoundaryTP16_15'], unit: 'K/Pa' },
      { name: 'Ng_fbk', cnName: '燃气涡轮转速', csvs: ['Ng_fbk'], unit: 'rpm' },
      { name: 'Np_fbk', cnName: '动力涡轮转速', csvs: ['Np_fbk'], unit: 'rpm' },
      { name: 'G01', cnName: 'GT1进气流量', csvs: ['G01_GT1_IN_W_kgps'], unit: 'kg/s' },
      { name: 'G02', cnName: 'GT1出气流量', csvs: ['G02_GT1_OUT_W_kgps'], unit: 'kg/s' },
      { name: 'G03', cnName: 'GT2进气流量', csvs: ['G03_GT2_IN_W_kgps'], unit: 'kg/s' },
      { name: 'G04', cnName: 'GT2出气流量', csvs: ['G04_GT2_OUT_W_kgps'], unit: 'kg/s' },
      { name: 'G05', cnName: 'PT1根部进气流量', csvs: ['G05_PT1_IN_ROOT_W_kgps'], unit: 'kg/s' },
      { name: 'G06', cnName: 'PT1根部出气流量', csvs: ['G06_PT1_OUT_ROOT_W_kgps'], unit: 'kg/s' },
      { name: 'G07', cnName: 'PT2叶尖进气流量', csvs: ['G07_PT2_IN_TIP_W_kgps'], unit: 'kg/s' },
      { name: 'G08', cnName: 'PT2叶尖出气流量', csvs: ['G08_PT2_OUT_TIP_W_kgps'], unit: 'kg/s' },
    ]
  },
];

const VAR_COLORS = [
  '#f59e0b', '#22c55e', '#06b6d4', '#ef4444', '#3b82f6',
  '#d97706', '#a855f7', '#ec4899', '#14b8a6', '#84cc16',
  '#6366f1', '#f97316', '#10b981', '#8b5cf6', '#0ea5e9'
];



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

function chartUnit(title, unit, ...series) {

  return { title, yMin: null, yMax: null, series, unit };

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

    unit: cfg.unit || null,

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

        { type: 'value', min: data.yMin ?? null, max: data.yMax ?? null, name: data.unit || '', nameTextStyle: { color: '#9ca3af', fontSize: 10 }, axisLabel: { color: '#9ca3af', fontSize: 10 }, splitLine: { lineStyle: { color: '#24344D' } }, axisLine: { lineStyle: { color: '#24344D' } } },

        { type: 'value', min: data.y2Min, max: data.y2Max, position: 'right', name: data.unit2 || '', nameTextStyle: { color: '#9ca3af', fontSize: 10 }, axisLabel: { color: '#9ca3af', fontSize: 10, formatter: v => v !== 0 && Math.abs(v) < 1e-4 ? v.toExponential(1) : v.toFixed(0) }, splitLine: { show: false }, axisLine: { lineStyle: { color: '#24344D' } } }

      ]

    : { type: 'value', min: data.yMin ?? null, max: data.yMax ?? null, name: data.unit || '', nameTextStyle: { color: '#9ca3af', fontSize: 10 }, axisLabel: { color: '#9ca3af', fontSize: 10 }, splitLine: { lineStyle: { color: '#24344D' } }, axisLine: { lineStyle: { color: '#24344D' } } };



  const opts = {

    backgroundColor: 'transparent',

    tooltip: { trigger: 'axis', backgroundColor: 'rgba(15,23,42,.9)', borderColor: '#24344D', textStyle: { color: '#e5e7eb' } },

    grid: { left: 55, right: data.y2Min != null ? 65 : 45, top: 32, bottom: 25 },

    toolbox: { right: 8, top: 4, iconStyle: { borderColor: '#9ca3af' }, emphasis: { iconStyle: { borderColor: '#fff' } }, feature: { restore: { title: '还原' } } },

    dataZoom: [{ type: 'inside', xAxisIndex: [0], filterMode: 'filter', start: 0, end: 100 }],

    xAxis: { type: 'value', min: 0, splitNumber: 6, name: '时间 (s)', nameTextStyle: { color: '#9ca3af', fontSize: 10 }, axisLabel: { color: '#9ca3af', fontSize: 10 }, splitLine: { lineStyle: { color: '#24344D' } }, axisLine: { lineStyle: { color: '#24344D' } } },

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

