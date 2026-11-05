/**
 * AFO 曲线内核(UI-R138 第5章统一规则):ECharts 动态加载、时间轴曲线、按像素抽稀
 * (保留桶内首/末/极值)、二值状态阶梯、跨图共同时间游标、明确单位换算(Pa→kPa/K→℃/
 * W→kW/m³/s→L/min;单位未确认不换算)、命令生效竖线、当前视图导出,以及运行时增量
 * 缓存 LiveBuffer(R138 7.3:游标补读/身份绑定/缺口保留/逐样本质量码)。
 * 由 afo-r138.js 消费。
 */
window.AfoKernel = (() => {

    /* ---------- ECharts 按需加载(与 program-run 同一库文件) ---------- */
    let ecPromise = null;
    function loadEcharts() {
        if (window.echarts) return Promise.resolve(window.echarts);
        if (!ecPromise) {
            ecPromise = new Promise((resolve, reject) => {
                const s = document.createElement('script');
                s.src = new URL('lib/echarts/echarts.min.js', document.baseURI).href;
                s.onload = () => window.echarts ? resolve(window.echarts) : reject(new Error('echarts 加载失败'));
                s.onerror = () => { ecPromise = null; reject(new Error('echarts 脚本加载失败')); };
                document.head.appendChild(s);
            });
        }
        return ecPromise;
    }

    /* ---------- 单位换算:仅明确换算;无先验字段不转换(R138 5.2) ---------- */
    const CONVERSIONS = {
        'Pa': { to: 'kPa', fn: v => v / 1e3 },
        'K': { to: '℃', fn: v => v - 273.15 },
        'W': { to: 'kW', fn: v => v / 1e3 },
        'm³/s': { to: 'L/min', fn: v => v * 6e4 },
        'm3/s': { to: 'L/min', fn: v => v * 6e4 }
    };
    const isUnconfirmedUnit = u => !u || /unconfirmed|enthalpy|未确认/.test(String(u).trim());
    const convertedUnit = u => (isUnconfirmedUnit(u) || !CONVERSIONS[String(u).trim()]) ? null : CONVERSIONS[String(u).trim()].to;
    function convertSeries(values, unit, forceRaw) {
        const u = String(unit || '').trim();
        if (forceRaw || isUnconfirmedUnit(u)) return { values, unit: u || '—' };
        const c = CONVERSIONS[u];
        if (!c) return { values, unit: u };
        return { values: values.map(v => (v == null || !isFinite(v)) ? v : c.fn(v)), unit: c.to };
    }

    /* ---------- 抽稀:每桶保留首/末/极大/极小,尖峰不被平均掉(R138 5.3) ---------- */
    function downsample(ts, vs, maxPts) {
        const n = ts.length;
        if (n <= maxPts) return { ts, vs };
        const bucket = Math.ceil(n / maxPts);
        const ots = [], ovs = [];
        for (let i = 0; i < n; i += bucket) {
            const end = Math.min(n, i + bucket);
            let iMin = -1, iMax = -1, vMin = Infinity, vMax = -Infinity;
            for (let j = i; j < end; j++) {
                const v = vs[j];
                if (v == null || !isFinite(v)) continue;
                if (v < vMin) { vMin = v; iMin = j; }
                if (v > vMax) { vMax = v; iMax = j; }
            }
            const keep = Array.from(new Set([i, end - 1, iMin, iMax])).filter(x => x >= i && x < end).sort((a, b) => a - b);
            keep.forEach(j => { ots.push(ts[j]); ovs.push(vs[j]); });
        }
        return { ts: ots, vs: ovs };
    }

    /* ---------- 共同时间游标总线(跨图、跨页同步;游标值=仿真时间s) ---------- */
    const cursorBus = {
        value: null,
        subs: new Set(),
        set(t) {
            this.value = (t == null || !isFinite(t)) ? null : Number(t);
            this.subs.forEach(f => { try { f(this.value); } catch (e) { /* 单图失败不影响其他 */ } });
        },
        sub(f) { this.subs.add(f); f(this.value); },
        unsub(f) { this.subs.delete(f); }
    };

    /* ---------- 数值格式 ---------- */
    function fmtV(v) {
        if (v == null || !isFinite(v)) return v == null ? '—' : (isNaN(v) ? 'NaN' : (v > 0 ? '+∞' : '-∞'));
        const a = Math.abs(v);
        if (a !== 0 && (a >= 1e6 || a < 1e-3)) return v.toExponential(3);
        if (a >= 1000) return v.toFixed(1);
        if (a >= 10) return v.toFixed(2);
        return v.toFixed(4);
    }

    /** 轴刻度短格式:避免大数/极小值产生超长标签被裁切。 */
    function axisNum(v) {
        if (!isFinite(v)) return '';
        const a = Math.abs(v);
        if (a === 0) return '0';
        if (a >= 1e6) return (v / 1e6).toFixed(2) + 'M';
        if (a >= 1e4) return (v / 1e3).toFixed(1) + 'k';
        if (a >= 100) return String(Math.round(v));
        if (a >= 1) return String(Math.round(v * 100) / 100);
        if (a >= 1e-3) return v.toFixed(4);
        return v.toExponential(1);
    }

    /* ---------- LiveBuffer:运行时增量缓存(R138 7.3) ----------
     * 服务端 /afo/live 返回 sampleSeqList/sampleTimeList/values[n×W]/quality[n×W],
     * values 列与请求时的 columns(目录0基下标)一一对应。按游标追加;缺口不拼接,
     * 由调用方决定重试或保留缺口;身份变更拒绝。 */
    function LiveBuffer() {
        return {
            seq: [], time: [],
            cols: {},            // catalogIndex -> {v:[], q:[]}
            colIdx: [],          // 本缓冲请求的目录下标(与批次行内位置对应)
            sessionId: null, hash: null, nextSeq: 0,
            isFinal: false, lastHeartbeat: null, gap: null, gapRetries: 0,
            count() { return this.seq.length; },
            /** 批次落库;重复/乱序行安全跳过;身份不符抛错。返回本批新增行数。 */
            append(batch, colIdx) {
                const sid = batch.sessionId;
                if (this.sessionId && sid && this.sessionId !== sid) {
                    throw new Error('会话身份变更(' + this.sessionId + ' → ' + sid + ');不跨会话拼接');
                }
                if (sid) this.sessionId = sid;
                if (batch.channelCatalogHash) this.hash = batch.channelCatalogHash;
                this.isFinal = !!batch.isFinal;
                if (batch.lastHeartbeat) this.lastHeartbeat = batch.lastHeartbeat;
                this.gap = batch.gap || null;
                const seqs = batch.sampleSeqList || [];
                const times = batch.sampleTimeList || [];
                const values = batch.values || [];
                const quality = batch.quality || [];
                let added = 0;
                for (let r = 0; r < seqs.length; r++) {
                    const sq = Number(seqs[r]);
                    if (this.seq.length && sq <= this.seq[this.seq.length - 1]) continue; // 已有,跳过
                    this.seq.push(sq);
                    this.time.push(times[r] == null ? null : Number(times[r]));
                    for (let c = 0; c < colIdx.length; c++) {
                        let col = this.cols[colIdx[c]];
                        if (!col) { col = this.cols[colIdx[c]] = { v: [], q: [] }; }
                        const row = values[r];
                        const qrow = quality[r];
                        col.v.push(row && row[c] != null && isFinite(row[c]) ? Number(row[c]) : null);
                        col.q.push(qrow && qrow[c] != null ? Number(qrow[c]) : (row && row[c] == null ? 1 : 0));
                    }
                    // 补齐本次未请求的历史列(长度对齐)
                    for (const k of Object.keys(this.cols)) {
                        const col = this.cols[k];
                        while (col.v.length < this.seq.length) { col.v.push(null); col.q.push(0); }
                    }
                    added++;
                }
                this.colIdx = colIdx.slice();
                if (seqs.length) this.nextSeq = Number(batch.nextSeq || seqs[seqs.length - 1]);
                return added;
            },
            /** 目录下标序列(自动纳入缓冲);值/质量(未请求列为null)。 */
            series(catIdx) {
                let col = this.cols[catIdx];
                if (!col) { col = this.cols[catIdx] = { v: new Array(this.seq.length).fill(null), q: new Array(this.seq.length).fill(0) }; }
                while (col.v.length < this.seq.length) { col.v.push(null); col.q.push(0); }
                return col;
            },
            /** 时间窗口 [t0,t1] 的行下标范围(二分)。 */
            range(t0, t1) {
                const t = this.time;
                let lo = 0, hi = t.length;
                while (lo < hi) { const m = (lo + hi) >> 1; if ((t[m] == null ? -1 : t[m]) < t0) lo = m + 1; else hi = m; }
                const i0 = lo;
                hi = t.length;
                let hi2 = hi;
                lo = i0;
                while (lo < hi2) { const m = (lo + hi2) >> 1; if ((t[m] == null ? Infinity : t[m]) <= t1) lo = m + 1; else hi2 = m; }
                return [i0, hi2];
            }
        };
    }

    /* ---------- option 构建 ----------
     * cfg: { time:[...], series:[{name, values, time?, unit, color, dash, step, axis, rawUnit}],
     *        window:[t0,t1]|null, marks:[{t,label}], zoom } */
    const PALETTE = ['#0e7490', '#b91c1c', '#65a30d', '#7c3aed', '#d97706', '#0f766e', '#be185d', '#475569',
        '#0284c7', '#c2410c', '#4d7c0f', '#9333ea'];

    function buildOption(cfg) {
        const hasY2 = (cfg.series || []).some(s => s.axis === 'right');
        const leftSeries = (cfg.series || []).filter(s => s.axis !== 'right');
        const maxPts = cfg.maxPoints || 1400;
        const lineSeries = (cfg.series || []).map((s, i) => {
            // 每序列可带独立时间轴(比较叠加时不同采样网格各自成对,不互插值)
            const tArr = s.time || cfg.time || [];
            const conv = convertSeries(s.values, s.unit, s.rawUnit);
            const ds = downsample(tArr, conv.values, maxPts);
            const data = [];
            for (let k = 0; k < ds.ts.length; k++) data.push([ds.ts[k], ds.vs[k] == null ? null : ds.vs[k]]);
            const color = s.color || PALETTE[i % PALETTE.length];
            return {
                name: s.name, type: 'line', showSymbol: false, animation: false, sampling: false,
                step: s.step ? 'end' : false,
                connectNulls: false,
                lineStyle: { width: 1.4, type: s.dash ? 'dashed' : 'solid', color },
                itemStyle: { color },
                yAxisIndex: s.axis === 'right' ? 1 : 0,
                data,
                _unit: conv.unit
            };
        });
        const unitMap = {};
        lineSeries.forEach(s => { unitMap[s.name] = s._unit || ''; });
        // 近常量序列(如稳态Np):ECharts默认把y轴缩到1e-6量级,刻度变成超长小数并被标签区裁掉;
        // 跨度不足量级0.5%时主动撑开,保证刻度可读
        const leftVals = [];
        lineSeries.forEach(s => { if (s.yAxisIndex === 0) s.data.forEach(p => { if (p[1] != null && isFinite(p[1])) leftVals.push(p[1]); }); });
        let yMin = null, yMax = null;
        if (leftVals.length) {
            let mn = leftVals[0], mx = leftVals[0];
            for (const v of leftVals) { if (v < mn) mn = v; if (v > mx) mx = v; }
            const mag = Math.max(Math.abs(mn), Math.abs(mx));
            if (mx - mn < mag * 0.005) {
                const pad = Math.max(mag * 0.0025, 1e-9);
                yMin = mn - pad; yMax = mx + pad;
            }
        }
        const yName = s => s && s.length ? (s[0].unit || '') : '';
        return {
            animation: false,
            // 效果图版式:图区扁平、横轴 t/s、图例在图下方(legend bottom);缩放用 inside(滚轮),
            // "复位"由视图条统一提供
            grid: { left: 58, right: hasY2 ? 58 : 16, top: 12, bottom: cfg.legend === false ? 18 : 34 },
            legend: cfg.legend === false ? undefined : {
                data: (cfg.series || []).map(s => s.name), type: 'scroll', bottom: 0,
                textStyle: { fontSize: 12, color: '#334155' }, icon: 'rect',
                itemWidth: 16, itemHeight: 3, itemGap: 22
            },
            tooltip: {
                trigger: 'axis', axisPointer: { type: 'line' }, textStyle: { fontSize: 11 },
                formatter: params => {
                    if (!params || !params.length) return '';
                    const rows = ['<b>t = ' + Number(params[0].axisValue).toFixed(3) + ' s</b>'];
                    params.forEach(p => {
                        const u = unitMap[p.seriesName] || '';
                        rows.push(p.marker + ' ' + p.seriesName + ': ' + fmtV(p.value ? p.value[1] : p.value) + (u ? ' ' + u : ''));
                    });
                    return rows.join('<br/>');
                }
            },
            xAxis: {
                type: 'value', name: 't / s', nameLocation: 'end', nameGap: 3,
                min: cfg.window ? cfg.window[0] : null, max: cfg.window ? cfg.window[1] : null,
                scale: !cfg.window,
                axisLabel: { fontSize: 10, formatter: v => Number(v).toFixed(cfg.timeDecimals != null ? cfg.timeDecimals : 1) },
                splitLine: { lineStyle: { color: '#f1f5f9' } }
            },
            yAxis: [{
                type: 'value', scale: true, name: yName(leftSeries),
                min: yMin == null ? null : yMin, max: yMax == null ? null : yMax,
                nameTextStyle: { fontSize: 11, align: 'left' },
                axisLabel: { fontSize: 10, formatter: axisNum },
                splitLine: { lineStyle: { color: '#f1f5f9' } }
            }].concat(hasY2 ? [{
                type: 'value', scale: true, name: cfg.y2Title || yName((cfg.series || []).filter(s => s.axis === 'right')),
                nameTextStyle: { fontSize: 11, align: 'right' },
                axisLabel: { fontSize: 10, formatter: axisNum },
                splitLine: { show: false }
            }] : []),
            dataZoom: cfg.zoom === false ? [] : [{ type: 'inside', filterMode: 'none' }],
            series: lineSeries.concat([{
                id: '__marks', name: '__marks', type: 'line', data: [], silent: true,
                markLine: { symbol: 'none', animation: false, data: [] }
            }])
        };
    }

    /** 生效竖线+游标合并进 __marks 系列(按 id 部分合并,不整图重建)。 */
    function marksData(applied, cursorT) {
        const data = (applied || []).map(m => ({
            xAxis: m.t,
            lineStyle: { color: '#b45309', type: 'dashed', width: 1.2 },
            label: { formatter: m.label || '生效', position: 'insideEndTop', fontSize: 10, color: '#b45309' }
        }));
        if (cursorT != null && isFinite(cursorT)) {
            data.push({
                xAxis: cursorT,
                lineStyle: { color: '#0e7490', type: 'dashed', width: 1 },
                label: { formatter: '游标 ' + Number(cursorT).toFixed(3) + ' s', position: 'insideEndBottom', fontSize: 10, color: '#0e7490' }
            });
        }
        return data;
    }

    /* ---------- 图表挂载 ----------
     * mount(dom, cfg, hooks) → Promise<controller>;
     * controller: setCfg(全量重建) / setAppliedMarks / setCursor / exportCsv / dispose
     * hooks: { onZoom() } 用户滚轮缩放回调(用于自动关闭"跟随最新",R138 5.2)
     * 点击图面 → 设共同游标;图例显隐/缩放/复位由 ECharts 内建。 */
    function mount(dom, cfg, hooks) {
        return loadEcharts().then(ec => {
            const chart = ec.init(dom, null, { renderer: 'canvas', backgroundColor: 'transparent' });
            const ctl = { chart, cfg, applied: [], cursorT: null, disposed: false };

            function paintMarks() {
                if (ctl.disposed) return;
                try {
                    chart.setOption({ series: [{ id: '__marks', markLine: { symbol: 'none', animation: false, data: marksData(ctl.applied, ctl.cursorT) } }] });
                } catch (e) { /* 图已释放 */ }
            }
            function rebuild() {
                if (ctl.disposed) return;
                chart.setOption(buildOption(cfg), true);
                paintMarks();
            }
            ctl.setAppliedMarks = ms => { ctl.applied = ms || []; paintMarks(); };
            ctl.setCursor = t => { ctl.cursorT = (t == null || !isFinite(t)) ? null : Number(t); paintMarks(); };
            ctl.setCfg = c => { cfg = c; rebuild(); };
            // D9:每图独立复位视图(缩放/平移回到初始窗口);不触发 onZoom,不影响"跟随最新"全局开关
            ctl.resetView = () => {
                try { chart.dispatchAction({ type: 'dataZoom', start: 0, end: 100 }); } catch (e) { /* 图已释放 */ }
            };
            ctl.exportCsv = () => {
                // 导出当前视图:存在窗口时按窗口切片(R138 5.2"导出当前视图")
                const win = cfg.window;
                const tAll = cfg.time || [];
                let idx = null;
                if (win) {
                    idx = [];
                    for (let i = 0; i < tAll.length; i++) {
                        if (tAll[i] != null && tAll[i] >= win[0] && tAll[i] <= win[1]) idx.push(i);
                    }
                }
                const pick = (arr, i) => arr == null ? '' : (arr[i] == null ? '' : Number(arr[i]).toString());
                const rows = ['time_s,' + cfg.series.map(s => '"' + s.name + (s.unit ? '(' + s.unit + ')' : '') + '"').join(',')];
                const list = idx || tAll.map((_, i) => i);
                list.forEach(i => {
                    rows.push(Number(tAll[i]).toFixed(4) + ',' + cfg.series.map(s => pick(s.values, i)).join(','));
                });
                const blob = new Blob(['\ufeff' + rows.join('\n')], { type: 'text/csv;charset=utf-8' });
                const a = document.createElement('a');
                a.href = URL.createObjectURL(blob);
                a.download = 'afo_curves_' + Date.now() + '.csv';
                a.click();
                setTimeout(() => URL.revokeObjectURL(a.href), 3000);
            };
            chart.getZr().on('click', e => {
                try {
                    const pt = chart.convertFromPixel('grid', [e.offsetX, e.offsetY]);
                    if (pt && isFinite(pt[0])) cursorBus.set(pt[0]);
                } catch (err) { /* 布局未完成 */ }
            });
            // 用户缩放回调(R138 5.2:拖动/缩放后自动关闭跟随最新)
            chart.on('datazoom', () => {
                try { if (hooks && typeof hooks.onZoom === 'function') hooks.onZoom(); } catch (e) { /* 回调异常不影响视图 */ }
            });
            cursorBus.sub(t => ctl.setCursor(t));
            ctl.dispose = () => { ctl.disposed = true; cursorBus.unsub(t => ctl.setCursor(t)); try { chart.dispose(); } catch (e) { /* 已释放 */ } };
            rebuild();
            return ctl;
        });
    }

    /** 空图占位(R138 4.1:真实运行缺数据留空并写明原因,不填零/不用别支路代替)。 */
    function emptyState(reason, hint) {
        const d = document.createElement('div');
        d.style.cssText = 'height:200px;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:6px;'
            + 'background:#fff;border:1px dashed #cbd5e1;border-radius:6px;color:#64748b;font-size:13px';
        d.innerHTML = '<div style="font-size:24px">⌛</div><div>' + reason + '</div>'
            + (hint ? '<div style="font-size:12px;color:#94a3b8;max-width:80%;text-align:center">' + hint + '</div>' : '');
        return d;
    }

    /** 按目标单位转换(仅明确物理路径;无路径则原值原单位返回)。 */
    const TO_RULES = {
        'kPa': { from: 'Pa', fn: v => v / 1e3 },
        '℃': { from: 'K', fn: v => v - 273.15 },
        'kW': { from: 'W', fn: v => v / 1e3 },
        'L/min': { from: 'm³/s', fn: v => v * 6e4 }
    };
    function convertTo(values, from, to) {
        const f = String(from || '').trim(), t = String(to || '').trim();
        if (!t || t === f) return { values, unit: f };
        const rule = TO_RULES[t];
        if (!rule || rule.from !== f) return { values, unit: f };
        return { values: values.map(v => (v == null || !isFinite(v)) ? v : rule.fn(v)), unit: t };
    }

    /** 单位转换标注(如 "K → ℃";无换算返回原单位)。 */
    function unitLabel(unit, forceRaw) {
        const c = convertSeries([], unit, forceRaw);
        if (!forceRaw && unit && c.unit !== String(unit).trim()) return String(unit).trim() + ' → ' + c.unit;
        return isUnconfirmedUnit(unit) ? '原值(单位未确认)' : String(unit || '—').trim();
    }

    /** 水平状态条(效果图 F06"内部模式输入"):把 0/1 状态序列渲染为时间条带。
     *  rows: [{label, time:[], values:[]}] value=1 段填色;窗口取各 time 的公共范围。 */
    function stateBar(host, rows, opts) {
        opts = opts || {};
        const wrap = document.createElement('div');
        wrap.style.cssText = 'padding:6px 2px 0';
        let t0 = Infinity, t1 = -Infinity;
        rows.forEach(r => (r.time || []).forEach(t => { if (t != null && isFinite(t)) { t0 = Math.min(t0, t); t1 = Math.max(t1, t); } }));
        if (!isFinite(t0)) { wrap.innerHTML = '<div style="color:#94a3b8;font-size:12px;padding:18px;text-align:center">暂无状态样本</div>'; host.appendChild(wrap); return wrap; }
        if (t1 === t0) t1 = t0 + 0.1;
        rows.forEach(r => {
            const line = document.createElement('div');
            line.style.cssText = 'display:flex;align-items:center;gap:10px;margin-bottom:10px';
            const lab = document.createElement('div');
            lab.style.cssText = 'width:76px;font-size:12px;color:#334155;text-align:right;flex:none';
            lab.appendChild(document.createTextNode(r.label));
            const track = document.createElement('div');
            track.style.cssText = 'position:relative;flex:1;height:16px;background:#e2e8f0;border-radius:3px;overflow:hidden';
            const segs = [];
            let cur = null;
            for (let i = 0; i < (r.time || []).length; i++) {
                const v = r.values[i];
                const t = r.time[i];
                // S1:null=非有限样本,结束当前连续段且不开新段(不画成0,不跨段连线);
                // 下个非null样本另起新段
                if (cur && (v == null || v !== cur.v)) { segs.push({ a: cur.t, b: t, v: cur.v }); cur = null; }
                if (!cur && v != null) cur = { t, v };
            }
            if (cur) segs.push({ a: cur.t, b: t1, v: cur.v });
            segs.forEach(s => {
                const seg = document.createElement('div');
                const on = (s.v === 1 || s.v === true);
                // 状态为0(正常工况)也画一条浅色基线,否则全程0会看起来像"没有数据"
                seg.style.cssText = 'position:absolute;'
                    + (on ? 'top:0;bottom:0;background:' + (r.color || '#0e7490')
                           : 'top:50%;height:2px;background:' + (r.color || '#0e7490') + '55')
                    + ';left:' + (100 * (s.a - t0) / (t1 - t0)) + '%;width:' + Math.max(0.4, 100 * (s.b - s.a) / (t1 - t0)) + '%';
                track.appendChild(seg);
            });
            const last = (r.values || []).length ? r.values[r.values.length - 1] : null;
            const scale = document.createElement('div');
            scale.style.cssText = 'width:64px;font-size:11px;color:#64748b;flex:none';
            const txt = last == null ? '—' : (last === 1 || last === true) ? '1 触发' : '0 正常';
            scale.appendChild(document.createTextNode(txt));
            line.appendChild(lab); line.appendChild(track); line.appendChild(scale);
            wrap.appendChild(line);
        });
        const axis = document.createElement('div');
        axis.style.cssText = 'display:flex;justify-content:space-between;font-size:10px;color:#94a3b8;padding:0 0 0 86px';
        const s0 = document.createElement('span'); s0.appendChild(document.createTextNode(t0.toFixed(1) + ' s'));
        const s1 = document.createElement('span'); s1.appendChild(document.createTextNode(t1.toFixed(1) + ' s'));
        axis.appendChild(s0); axis.appendChild(s1);
        wrap.appendChild(axis);
        host.appendChild(wrap);
        return wrap;
    }

    return {
        loadEcharts, convertSeries, convertTo, convertedUnit, isUnconfirmedUnit, unitLabel,
        downsample, cursorBus, buildOption, mount, emptyState, fmtV,
        LiveBuffer, PALETTE, stateBar
    };
})();
