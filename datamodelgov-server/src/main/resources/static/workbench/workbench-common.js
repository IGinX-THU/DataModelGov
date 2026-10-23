/**
 * 工作台公共定义:导航配置、页面注册、示例数据。
 * 界面结构依据《完整界面设计说明书》UI-R131(9 图组 / 190 效果图);
 * 图中数值为展示样例,程序绑定以 R06 交付包 F-xx 合同为准。
 */
window.Workbench = (() => {

    /* ---------- 小工具 ---------- */
    function h(tag, attrs, ...children) {
        const node = document.createElement(tag);
        if (attrs) {
            Object.entries(attrs).forEach(([k, v]) => {
                if (k === 'class') node.className = v;
                else if (k === 'html') node.innerHTML = v;
                else if (k.startsWith('on')) node.addEventListener(k.slice(2), v);
                else node.setAttribute(k, v);
            });
        }
        children.flat().forEach(c => {
            if (c == null) return;
            if (typeof c === 'string' || typeof c === 'number' || typeof c === 'boolean') {
                node.appendChild(document.createTextNode(String(c)));
            } else {
                node.appendChild(c);
            }
        });
        return node;
    }

    const ICONS = {
        logo: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M2 13h4l3-8 4 16 3-8h6"/></svg>',
        gauge: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><path d="M17.5 14v7M14 17.5h7"/></svg>',
        tasks: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M9 6h12M9 12h12M9 18h12"/><path d="M3 6l1.5 1.5L7 5M3 12l1.5 1.5L7 11M3 18l1.5 1.5L7 17"/></svg>',
        layers: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><path d="M12 2l10 5-10 5L2 7l10-5z"/><path d="M2 12l10 5 10-5M2 17l10 5 10-5"/></svg>',
        chart: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M3 3v18h18"/><path d="M7 14l4-6 3 4 5-8"/></svg>',
        clock: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 3"/></svg>',
        engine: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 3"/></svg>',
        tools: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><path d="M14.7 6.3a4.5 4.5 0 0 0-6 6L3 18l3 3 5.7-5.7a4.5 4.5 0 0 0 6-6L14 13l-3-3 3.7-3.7z"/></svg>',
        joint: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="5" cy="6" r="2.5"/><circle cx="19" cy="6" r="2.5"/><circle cx="12" cy="18" r="2.5"/><path d="M7 7.5l3.5 8M17 7.5l-3.5 8M7.5 6h9"/></svg>',
        ph: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="3" y="4" width="18" height="14" rx="2"/><path d="M8 21h8M12 18v3"/></svg>'
    };

    /* ---------- 业务目录(建模任务页的静态菜单;数据一律来自真实接口) ---------- */
    const DEMO = {
        businesses: [
            { id: 'steady', name: '稳态试车建模', desc: '由稳态均值数据新建模型(TC24),或用新试车记录更新稳态系数(TC27)', enabled: true },
            { id: 'transient', name: '过渡态试车建模', desc: '固定稳态父模型,选定大幅变化事件辨识13项瞬态系数(TC27 瞬态)', enabled: true },
            { id: 'flightSteady', name: '稳态飞参建模', desc: '从实际飞参提取有效稳态窗口,更新稳态及相关参数(F3 Start14)', enabled: true },
            { id: 'flightTransient', name: '过渡态飞参建模', desc: '选取飞行大幅事件,更新瞬态参数(F3 Start11/12/13)', enabled: true },
            { id: 'evolution', name: '发动机个性化模型自演化', desc: '从试车模型起步,逐架次更新并比较趋势与预测(F-06 Stage4)', enabled: true }
        ]
    };

    /* ---------- 导航配置 ---------- */
    const WORKBENCHES = {
        modeling: {
            key: 'modeling',
            appName: '发动机个性化建模',
            groupLabel: '个性化自适应建模',
            icon: 'logo',
            desc: '发动机个性化自适应建模项目:稳态 / 过渡态试车建模、飞参建模、模型自演化',
            nav: [
                { key: 'overview', label: '项目概况', icon: 'gauge' },
                { key: 'tasks', label: '建模任务', icon: 'tasks' },
                { key: 'models', label: '模型成果', icon: 'layers' },
                { key: 'predictions', label: '输出预测', icon: 'chart' },
                { key: 'records', label: '运行记录', icon: 'clock' }
            ]
        },
        testbench: {
            key: 'testbench',
            appName: '发动机数字试车台',
            groupLabel: '系统联合仿真',
            icon: 'logo',
            desc: '发动机系统联合仿真项目:设计点配置、起动停车建模、全模式仿真、多系统联合仿真',
            nav: [
                { key: 'overview', label: '项目概况', icon: 'gauge' },
                { key: 'startstop', label: '起动停车建模', icon: 'tasks' },
                { key: 'models', label: '模型成果', icon: 'layers' },
                { key: 'fullmode', label: '全模式仿真', icon: 'engine' },
                { key: 'afo', label: '多系统联合仿真', icon: 'joint' },
                { key: 'records', label: '仿真记录', icon: 'clock' }
            ]
        }
    };

    /* ---------- 页面注册 ---------- */
    const pages = {};

    function pageHeader(title, sub) {
        return h('div', null,
            h('div', { class: 'wb-page-title' }, title),
            h('div', { class: 'wb-page-sub' }, sub));
    }

    function statusTag(text, kind) {
        return h('span', { class: 'wb-tag wb-tag-' + (kind || 'gray') }, text);
    }

    /** 自包含toast:workbench.html不加载common-utils.js,提示条就地注入body,不依赖外部组件。 */
    let toastHost = null;
    function toast(msg, kind) {
        if (window.CommonUtils && window.CommonUtils.showToast) { window.CommonUtils.showToast(msg, kind || 'info'); return; }
        if (!toastHost || !toastHost.isConnected) {
            toastHost = h('div', { style: 'position:fixed;top:18px;left:50%;transform:translateX(-50%);z-index:99999;display:flex;flex-direction:column;gap:8px;align-items:center;pointer-events:none' });
            document.body.appendChild(toastHost);
        }
        const bg = kind === 'error' ? '#b91c1c' : kind === 'success' ? '#0f766e' : '#334155';
        const item = h('div', {
            style: 'background:' + bg + ';color:#fff;padding:9px 18px;border-radius:6px;font-size:13px;max-width:70vw;'
                + 'box-shadow:0 4px 14px rgba(0,0,0,.18);opacity:0;transition:opacity .2s',
            title: msg
        }, String(msg));
        toastHost.appendChild(item);
        requestAnimationFrame(() => { item.style.opacity = '1'; });
        setTimeout(() => {
            item.style.opacity = '0';
            setTimeout(() => { if (item.parentNode) item.parentNode.removeChild(item); }, 250);
        }, kind === 'error' ? 5200 : 3200);
    }

    /** 模型交付文件下载地址(带 token;import() 场景同插件认证约定)。 */
    function modelDownloadUrl(pid, mid) {
        const cfg = window.AppConfig;
        return cfg.api.baseURL + '/api/engine/projects/' + encodeURIComponent(pid)
            + '/models/' + encodeURIComponent(mid) + '/file?token=' + encodeURIComponent(cfg.getToken() || '');
    }

    /* ===== 共享渲染工具:SVG折线图 / 通用数据表 / 列分组 ===== */

    /** SVG折线图:series=[{name, values:[num], dash?}], xLabels=[str];空值断开。 */
    function lineChart(opt) {
        const W = opt.width || 960, H = opt.height || 300;
        const padL = 58, padR = 16, padT = 14, padB = 34;
        const colors = ['#0e7490', '#94a3b8', '#b91c1c', '#65a30d', '#7c3aed'];
        const all = [];
        (opt.series || []).forEach(s => (s.values || []).forEach(v => { if (v != null && isFinite(v)) all.push(v); }));
        const svgNS = 'http://www.w3.org/2000/svg';
        const svg = document.createElementNS(svgNS, 'svg');
        svg.setAttribute('viewBox', '0 0 ' + W + ' ' + H);
        svg.setAttribute('style', 'width:100%;max-width:' + W + 'px;background:#fff;border:1px solid #e5e7eb;border-radius:6px');
        if (!all.length) {
            const t = document.createElementNS(svgNS, 'text');
            t.setAttribute('x', W / 2); t.setAttribute('y', H / 2); t.setAttribute('text-anchor', 'middle');
            t.setAttribute('fill', '#9ca3af'); t.textContent = '暂无可用数值';
            svg.appendChild(t);
            return svg;
        }
        let min = Math.min.apply(null, all), max = Math.max.apply(null, all);
        if (min === max) { min -= 1; max += 1; }
        const pad = (max - min) * 0.08; min -= pad; max += pad;
        const n = Math.max.apply(null, (opt.series || []).map(s => (s.values || []).length).concat([1]));
        const X = i => padL + (n <= 1 ? 0 : (W - padL - padR) * i / (n - 1));
        const Y = v => padT + (H - padT - padB) * (1 - (v - min) / (max - min));
        // 网格与Y刻度
        for (let g = 0; g <= 4; g++) {
            const gv = min + (max - min) * g / 4, gy = Y(gv);
            const line = document.createElementNS(svgNS, 'line');
            line.setAttribute('x1', padL); line.setAttribute('x2', W - padR);
            line.setAttribute('y1', gy); line.setAttribute('y2', gy);
            line.setAttribute('stroke', '#f1f5f9');
            svg.appendChild(line);
            const lab = document.createElementNS(svgNS, 'text');
            lab.setAttribute('x', padL - 6); lab.setAttribute('y', gy + 4);
            lab.setAttribute('text-anchor', 'end'); lab.setAttribute('font-size', '10'); lab.setAttribute('fill', '#64748b');
            lab.textContent = formatTick(gv);
            svg.appendChild(lab);
        }
        (opt.series || []).forEach((s, si) => {
            const pts = [];
            (s.values || []).forEach((v, i) => { if (v != null && isFinite(v)) pts.push([X(i), Y(v)]); });
            if (!pts.length) return;
            const pl = document.createElementNS(svgNS, 'polyline');
            pl.setAttribute('points', pts.map(p => p.join(',')).join(' '));
            pl.setAttribute('fill', 'none');
            pl.setAttribute('stroke', s.color || colors[si % colors.length]);
            pl.setAttribute('stroke-width', s.bold ? '2' : '1.4');
            if (s.dash) pl.setAttribute('stroke-dasharray', '5 4');
            svg.appendChild(pl);
            if (s.dots) {
                pts.forEach(p => {
                    const c = document.createElementNS(svgNS, 'circle');
                    c.setAttribute('cx', p[0]); c.setAttribute('cy', p[1]);
                    c.setAttribute('r', s.bold ? '3.2' : '2.6');
                    c.setAttribute('fill', s.color || colors[si % colors.length]);
                    svg.appendChild(c);
                });
            }
        });
        // X标签(最多8个)
        const xl = opt.xLabels || [];
        const step = Math.max(1, Math.ceil(xl.length / 8));
        xl.forEach((lab, i) => {
            if (i % step) return;
            const t = document.createElementNS(svgNS, 'text');
            t.setAttribute('x', X(i)); t.setAttribute('y', H - padB + 16);
            t.setAttribute('text-anchor', 'middle'); t.setAttribute('font-size', '10'); t.setAttribute('fill', '#64748b');
            t.textContent = lab;
            svg.appendChild(t);
        });
        if (opt.xTitle) {
            const t = document.createElementNS(svgNS, 'text');
            t.setAttribute('x', (padL + W - padR) / 2); t.setAttribute('y', H - 4);
            t.setAttribute('text-anchor', 'middle'); t.setAttribute('font-size', '11'); t.setAttribute('fill', '#475569');
            t.textContent = opt.xTitle;
            svg.appendChild(t);
        }
        return svg;
    }

    function formatTick(v) {
        const a = Math.abs(v);
        if (a >= 100000) return (v / 1000).toFixed(0) + 'k';
        if (a >= 1000) return v.toFixed(0);
        if (a >= 10) return v.toFixed(1);
        return v.toFixed(3);
    }

    /** 图例(与lineChart配色一致)。 */
    function chartLegend(series) {
        const colors = ['#0e7490', '#94a3b8', '#b91c1c', '#65a30d', '#7c3aed'];
        const spans = (series || []).map((s, i) => {
            const el = h('span', { style: s.dash ? '' : 'font-weight:600' }, (s.dash ? '– ' : '— ') + s.name);
            el.style.color = colors[i % colors.length];
            return el;
        });
        return h('div', { class: 'wb-legend', style: 'margin-bottom:8px' }, spans);
    }

    /** 通用数据表:rows=[{...}] 任意列;maxRows 截断并提示。 */
    function dataTable(rows, opt) {
        opt = opt || {};
        const box = h('div', null);
        if (!Array.isArray(rows) || !rows.length) {
            box.appendChild(h('div', { class: 'wb-hint' }, opt.emptyText || '暂无数据'));
            return box;
        }
        const keys = [];
        rows.slice(0, 5).forEach(r => Object.keys(r || {}).forEach(k => { if (keys.indexOf(k) < 0) keys.push(k); }));
        const tbl = h('table', { class: 'wb-table' },
            h('tr', null, keys.map(k => h('th', null, k))));
        rows.slice(0, opt.maxRows || 20).forEach(r => tbl.appendChild(h('tr', null,
            keys.map(k => {
                const v = r ? r[k] : null;
                return h('td', { class: 'wb-hint' }, v == null ? '—' : (typeof v === 'object' ? JSON.stringify(v) : String(v)));
            }))));
        box.appendChild(tbl);
        if (rows.length > (opt.maxRows || 20)) {
            box.appendChild(h('div', { class: 'wb-hint', style: 'margin-top:4px' },
                '显示前 ' + (opt.maxRows || 20) + ' / ' + rows.length + ' 行;完整数据随交付Excel提供。'));
        }
        return box;
    }

    /** 列名族分组:识别 测量/起点/辨识 三件套(_meas/_base/_final 等后缀);返回 [{name, cols:{meas,base,final}}]。 */
    function groupSeriesColumns(keys) {
        const SUF = [
            [/(^|[_\- ])(meas|measured|measure|测量)($|[_\- ])/i, 'meas'],
            [/(^|[_\- ])(base|baseline|start|起点|参考)($|[_\- ])/i, 'base'],
            [/(^|[_\- ])(final|model|est|estimate|identified|辨识|估计|模型)($|[_\- ])/i, 'final']
        ];
        const fam = {};
        (keys || []).forEach(k => {
            let kind = null, base = k;
            for (const [re, tag] of SUF) {
                if (re.test(k)) { kind = tag; base = k.replace(re, ' '); break; }
            }
            if (!kind) return;
            base = base.trim().toLowerCase();
            if (!fam[base]) fam[base] = { name: base, cols: {} };
            fam[base].cols[kind] = fam[base].cols[kind] || k;
        });
        return Object.keys(fam).filter(b => Object.keys(fam[b].cols).length >= 2).map(b => fam[b]);
    }

    /** 从行对象中提取数值列(跳过明显的元数据列)。 */
    function numericColumns(rows) {
        const keys = [];
        (rows || []).slice(0, 3).forEach(r => Object.keys(r || {}).forEach(k => { if (keys.indexOf(k) < 0) keys.push(k); }));
        const META = /id|group|分组|编号|样本|sample|count|point|工况|note|name|unit|remark|status/i;
        return keys.filter(k => {
            if (META.test(k)) return false;
            return rows.some(r => r && r[k] != null && (typeof r[k] === 'number' || (String(r[k]).trim() !== '' && isFinite(parseFloat(r[k])))));
        });
    }

    function toNum(v) { const n = parseFloat(v); return isFinite(n) ? n : null; }


    pages['modeling.overview'] = (ctx) => {
        const p = ctx.project;
        const wrap = h('div', null, pageHeader('项目概况', p.name + ' / 个性化自适应建模'));

        // 建模任务(真实任务列表,无演示数据)
        const tableHolder = h('div', null, h('div', { class: 'wb-empty' }, '正在加载任务...'));
        wrap.appendChild(h('div', { class: 'wb-section' },
            h('div', { class: 'wb-section-head' },
                h('div', { class: 'wb-section-title' }, '建模任务'),
                h('div', { style: 'display:flex;gap:10px' },
                    h('button', { class: 'wb-btn wb-btn-primary',
                        onclick: () => ctx.enterTask({ id: 'steady', name: '基础稳态点建模' }) }, '+ 基础稳态点建模'),
                    h('button', { class: 'wb-btn wb-btn-outline',
                        onclick: () => ctx.enterTask({ id: 'steady_update', name: '新增试车稳态更新', forceCreate: true }) }, '新增试车更新'))),
            tableHolder,
            h('div', { class: 'wb-actions-row' },
                h('button', { class: 'wb-btn wb-btn-outline', onclick: () => ctx.enterTask({ id: 'steady', name: '基础稳态点建模' }) }, '打开任务'),
                h('button', { class: 'wb-btn wb-btn-outline', onclick: () => importModel(ctx) }, '导入模型'))));

        // 计算基准
        const rows = [
            ['来源', '当前选定运行包;初值由算法配置返回'],
            ['导入已有成果', '进入模型成果;不自动作为本任务初值'],
            ['不确定性评估', '完成辨识并登记模型成果后开放'],
            ['当前任务', '从上方任务表选择或新建']
        ];
        wrap.appendChild(h('div', { class: 'wb-section' },
            h('div', { class: 'wb-section-title', style: 'margin-bottom:12px' }, '本任务的计算基准'),
            h('div', { class: 'wb-card' },
                h('div', { class: 'wb-form-grid' },
                    h('div', { class: 'wb-field' }, h('label', null, '运行包 / 初始参数配置'),
                        h('input', { readonly: '', value: 'B00 · 当前配套三部件基准' })),
                    h('div', { class: 'wb-field' }, h('label', null, '发动机 / 模型模式'),
                        h('input', { readonly: '', value: (p.engineId || '—') + ' / 三部件' }))),
                h('table', { class: 'wb-table', style: 'margin-top:14px' },
                    rows.map(r => h('tr', null, h('td', { style: 'width:180px;color:#6b7280' }, r[0]), h('td', null, r[1]))))),
            h('div', { class: 'wb-actions-row' },
                h('button', { class: 'wb-btn wb-btn-outline', onclick: () => ctx.navigate('predictions') }, '选择预测模型'),
                h('button', { class: 'wb-btn wb-btn-outline', onclick: () => ctx.navigate('records') }, '运行记录'))));

        loadOverviewTasks(ctx, tableHolder);
        return wrap;
    };

function loadOverviewTasks(ctx, holder) {
        if (!ctx.project || !ctx.project.id) {
            console.warn('项目信息不完整:', ctx.project);
            holder.innerHTML = '';
            holder.appendChild(h('div', { class: 'wb-empty' }, '本地演示项目无任务;请从项目入口进入真实项目。'));
            return;
        }
        
        // 先检查基本API是否可用
        window.AppConfig.engineGet('projects')
            .then(resp => {
                console.log('项目列表API响应:', resp);
                
                // 修复：只使用查询参数，不在路径中传参
                const apiUrl = 'projects/detail';
                console.log('请求项目详情API:', apiUrl, '参数:', { projectId: ctx.project.id });
                
                return window.AppConfig.engineGet(apiUrl, { projectId: ctx.project.id });
            })
            .then(resp => {
                console.log('项目详情响应:', resp);
                
                const tasks = resp && resp.data && Array.isArray(resp.data.tasks)
                    ? resp.data.tasks.filter(t => t.kind === 'steady') : [];
                const models = resp && resp.data && Array.isArray(resp.data.models) ? resp.data.models : [];
                
                console.log('过滤后的任务:', tasks);
                console.log('模型:', models);
                
                holder.innerHTML = '';
                if (!tasks.length) {
                    holder.appendChild(h('div', { class: 'wb-empty' },
                        '暂无建模任务;点击右上角"+ 基础稳态点建模"新建。'));
                    return;
                }
                holder.appendChild(h('table', { class: 'wb-table' },
                    h('tr', null, ['任务名称', '任务类型', '最近运行', '状态', '模型成果'].map(t => h('th', null, t))),
                    tasks.map(t => {
                        const model = models.find(mo => mo.taskId === t.id);
                        return h('tr', {
                            class: 'clickable',
                            onclick: () => {
                                // 01-23:打开既有任务,不是再建一个
                                window.__WB_OPEN_TASK__ = t.id;
                                ctx.enterTask({ id: 'steady', name: t.name || '稳态建模任务' });
                            }
                        },
                            h('td', { class: 'wb-link' }, t.name || t.id),
                            h('td', null, '稳态试车建模'),
                            h('td', null, t.runId || '—'),
                            h('td', null, statusTag(t.status, t.status === 'COMPLETED' ? 'teal' : (t.status === 'FAILED' ? 'red' : 'amber'))),
                            h('td', null, model ? model.name : '尚未生成'));
                    })));
            })
            .catch(error => {
                console.error('项目详情API调用失败:', error);
                holder.innerHTML = '';
                
                // 显示更详细的错误信息
                const errorMsg = error.message || '未知错误';
                const errorDetail = h('div', { style: 'font-size:12px;color:#666;margin-top:8px' }, 
                    '错误详情: ' + errorMsg + (error.stack ? '\n' + error.stack.substring(0, 200) + '...' : ''));
                
                holder.appendChild(h('div', { class: 'wb-empty' }, 
                    '任务列表加载失败;请确认服务可用。', errorDetail));
            });
    }

    /** 导入离线模型成果:Excel交付工作簿 + 可选identity.json(与导入数据同机制);完成后回调刷新。 */
    function importModel(ctx, done) {
        if (!ctx.project || !ctx.project.id) {
            window.CommonUtils && window.CommonUtils.showToast &&
                window.CommonUtils.showToast('本地演示项目不支持导入;请进入真实项目', 'error');
            return;
        }
        const input = document.createElement('input');
        input.type = 'file';
        input.multiple = true;
        input.accept = '.xlsx,.xls,.json';
        input.addEventListener('change', async () => {
            const files = Array.from(input.files || []);
            const excel = files.find(f => /\.(xlsx|xls)$/i.test(f.name));
            if (!excel) {
                window.CommonUtils && window.CommonUtils.showToast && window.CommonUtils.showToast('请选择交付Excel(.xlsx/.xls),可同时选入identity.json', 'error');
                return;
            }
            const identity = files.find(f => /\.json$/i.test(f.name));
            const fd = new FormData();
            fd.append('file', excel);
            if (identity) fd.append('identityFile', identity);
            window.CommonUtils && window.CommonUtils.showToast &&
                window.CommonUtils.showToast('正在导入:' + excel.name + (identity ? ' + ' + identity.name : ''), 'info');
            try {
                const resp = await window.AppConfig.engineUpload(
                    'projects/' + encodeURIComponent(ctx.project.id) + '/models/import', fd);
                if (resp && (resp.success || resp.code === 200) && resp.data) {
                    window.CommonUtils && window.CommonUtils.showToast &&
                        window.CommonUtils.showToast('模型已导入并登记:' + resp.data.name, 'success');
                    if (done) done(resp.data);
                } else {
                    window.CommonUtils && window.CommonUtils.showToast &&
                        window.CommonUtils.showToast((resp && resp.message) || '导入失败', 'error');
                }
            } catch (e) {
                window.CommonUtils && window.CommonUtils.showToast &&
                    window.CommonUtils.showToast('导入失败:' + e.message, 'error');
            }
        });
        input.click();
    }

    /* ===== 个性化建模 · 建模任务 ===== */
    pages['modeling.tasks'] = (ctx) => {
        const wrap = h('div', null, pageHeader('建模任务', '按业务目的组织;阶段编号保留在详情中'));
        const cards = DEMO.businesses.map(b => h('div', { class: 'wb-card', style: 'display:flex;align-items:center;gap:18px;margin-bottom:12px;' + (b.enabled ? '' : 'opacity:.62') },
            h('div', { style: 'flex:1' },
                h('div', { style: 'font-weight:700;color:#111827;margin-bottom:5px' }, b.name),
                h('div', { style: 'font-size:12px;color:#6b7280;line-height:1.6' }, b.desc)),
            h('div', null,
                b.enabled
                    ? h('button', { class: 'wb-btn wb-btn-primary', onclick: () => ctx.enterTask(b) }, '进入')
                    : h('span', { class: 'wb-tag wb-tag-gray' }, '页面建设中'))));
        wrap.appendChild(h('div', { class: 'wb-section' }, cards));
        return wrap;
    };

    /* ===== 个性化建模 · 模型成果(02-01~02-09:清单/筛选/来源关系/详情/比较)===== */
    const MODEL_VIEW = { tab: 'list', detailId: null, checked: {} };

    pages['modeling.models'] = (ctx) => {
        const wrap = h('div', null, pageHeader('模型成果',
            (ctx.project.engineId || '—') + ' / 稳态试车建模 / 模型版本与数据、评估关联'));
        const body = h('div', null);
        wrap.appendChild(body);
        renderModelsBody(ctx, body);
        return wrap;
    };

    function renderModelsBody(ctx, body) {
        body.innerHTML = '';
        if (MODEL_VIEW.tab === 'detail' && MODEL_VIEW.detailId) {
            renderModelDetail(ctx, body, MODEL_VIEW.detailId);
            return;
        }
        // 筛选行(02-01)
        const fBusiness = h('select', { style: 'width:100%' }, h('option', { value: '' }, '全部业务'),
            h('option', null, '稳态试车建模'), h('option', null, '导入模型'));
        const fStage = h('select', { style: 'width:100%' }, h('option', { value: '' }, '全部阶段'),
            h('option', null, '2.4 基础建模'), h('option', null, '2.7 数据更新'), h('option', null, '导入'));
        const fRoute = h('select', { style: 'width:100%' }, h('option', { value: '' }, '全部路径'),
            h('option', null, '稳态方程'), h('option', null, '瞬态时刻方程'));
        const fName = h('input', { placeholder: '模型名称/编号' });
        const filterBar = h('div', { class: 'wb-form-grid', style: 'grid-template-columns:repeat(4,1fr) 200px 190px;align-items:end;margin-bottom:14px' },
            h('div', { class: 'wb-field' }, h('label', null, '业务类别'), fBusiness),
            h('div', { class: 'wb-field' }, h('label', null, '来源阶段'), fStage),
            h('div', { class: 'wb-field' }, h('label', null, '计算路径'), fRoute),
            h('div', { class: 'wb-field' }, h('label', null, '模型名称 / 编号'), fName),
            h('div', null, h('button', {
                class: 'wb-btn wb-btn-outline', style: 'width:100%',
                onclick: () => loadModels(ctx)
            }, '刷新')),
            h('div', null, h('button', { class: 'wb-btn wb-btn-primary', style: 'width:100%', onclick: () => importModel(ctx, () => renderModelsBody(ctx, body)) }, '导入离线模型成果')));

        // 子页签:模型清单 | 来源关系(02-01/02-03)
        const tabBar = h('div', { class: 'wb-tabs', style: 'margin-bottom:12px' });
        const listHolder = h('div', null, h('div', { class: 'wb-empty' }, '正在加载模型成果...'));
        const summaryHolder = h('div', null);
        const actionsBar = h('div', { class: 'wb-actions-row', style: 'margin-top:14px' });
        [['list', '模型清单'], ['relation', '来源关系']].forEach(([key, label]) => {
            tabBar.appendChild(h('div', {
                class: 'wb-tab' + (MODEL_VIEW.tab === key ? ' active' : ''),
                onclick: () => { MODEL_VIEW.tab = key; renderModelsBody(ctx, body); }
            }, label));
        });
        body.appendChild(filterBar);
        body.appendChild(tabBar);
        body.appendChild(listHolder);
        body.appendChild(summaryHolder);
        body.appendChild(actionsBar);

        [fBusiness, fStage, fRoute, fName].forEach(el => el.addEventListener('change', () => loadModels(ctx)));
        fName.addEventListener('keydown', e => { if (e.key === 'Enter') loadModels(ctx); });

        let models = [];
        let uqRecords = [];

        function match(m) {
            if (fBusiness.value && (m.sourceBusiness || '') !== fBusiness.value) return false;
            if (fStage.value && (m.stage || '') !== fStage.value) return false;
            if (fRoute.value && (m.route || '') !== fRoute.value) return false;
            const kw = fName.value.trim().toLowerCase();
            if (kw && !((m.name || '') + ' ' + (m.id || '')).toLowerCase().includes(kw)) return false;
            return true;
        }

        function uqCount(mid) {
            return uqRecords.filter(r => r.modelAssetId === mid && r.status === 'COMPLETED').length;
        }

        /** UQ列副行(02-01):按方法汇总"2采样 / 1局部近似"。 */
        function uqSubLine(mid) {
            const mine = uqRecords.filter(r => r.modelAssetId === mid && r.status === 'COMPLETED');
            if (!mine.length) return '可新建匹配评估';
            const sampling = mine.filter(r => r.method === 'B' || r.method === 'C').length;
            const local = mine.filter(r => r.method === 'D').length;
            const parts = [];
            if (sampling) parts.push(sampling + '采样');
            if (local) parts.push(local + '局部近似');
            return parts.join(' / ');
        }

        function renderList() {
            listHolder.innerHTML = '';
            summaryHolder.innerHTML = '';
            const shown = models.filter(match);
            if (MODEL_VIEW.tab === 'relation') {
                renderRelation(shown);
                actionsBar.innerHTML = '';
                return;
            }
            if (!shown.length) {
                listHolder.appendChild(h('div', { class: 'wb-empty' },
                    models.length ? '没有符合筛选条件的模型。' :
                        '暂无模型成果——完成一次稳态辨识并"登记到模型成果"后在此查看;也可直接"导入离线模型成果"。'));
                actionsBar.innerHTML = '';
                return;
            }
            const total = h('span', { class: 'wb-hint', style: 'margin:0' },
                shown.length + '份模型 · ' + new Set(models.map(m => m.parentModelId || 'root')).size + '条来源路径');
            listHolder.appendChild(h('div', { style: 'display:flex;justify-content:flex-end;margin-bottom:6px' }, total));
            const tbl = h('table', { class: 'wb-table' },
                h('tr', null, ['', '模型名称 / 版本', '来源阶段', '计算路径', '训练数据', '父模型', '结果状态', '不确定性评估'].map((x, i) =>
                    h('th', i === 0 ? { style: 'width:34px' } : null, x))));
            shown.forEach(m => {
                const parent = models.find(p => p.id === m.parentModelId);
                const cb = h('input', { type: 'checkbox' });
                if (MODEL_VIEW.checked[m.id]) cb.checked = true;
                cb.addEventListener('change', () => {
                    if (cb.checked) MODEL_VIEW.checked[m.id] = true; else delete MODEL_VIEW.checked[m.id];
                    renderActions();
                });
                const diag = m.resultStatus === '诊断(未收敛但有效)';
                const uqN = uqCount(m.id);
                tbl.appendChild(h('tr', { class: 'clickable', onclick: () => { MODEL_VIEW.tab = 'detail'; MODEL_VIEW.detailId = m.id; renderModelsBody(ctx, body); } },
                    h('td', { onclick: ev => ev.stopPropagation() }, cb),
                    h('td', null,
                        h('div', { style: 'font-weight:600;color:#111827' }, m.name || m.id),
                        h('div', { class: 'wb-hint', style: 'margin:0' },
                            (m.sourceBusiness === '导入模型' ? '导入模型' : '基础/更新模型') + ' · ' + (m.route || '—'))),
                    h('td', null, m.stage || '—'),
                    h('td', null, m.route || '—'),
                    h('td', { class: 'wb-hint' }, m.trainingFile ? String(m.trainingFile).split(/[\\/]/).pop() : '—'),
                    h('td', { class: 'wb-hint' }, parent ? parent.name : (m.parentModelId ? m.parentModelId : '基准配置')),
                    h('td', null,
                        h('div', { style: diag ? 'color:#b45309;font-weight:600' : 'color:#0f766e;font-weight:600' },
                            diag ? '已交付' : (m.resultStatus || '已保存')),
                        diag ? h('div', { class: 'wb-hint', style: 'margin:0' }, '未收敛但有效,可进下游') : null),
                    h('td', null,
                        h('div', { style: 'font-weight:' + (uqN ? '600' : '400') + ';color:' + (uqN ? '#0f766e' : '#6b7280') },
                            uqN ? uqN + '份记录' : '未评估'),
                        h('div', { class: 'wb-hint', style: 'margin:0' }, uqSubLine(m.id)))));
            });
            listHolder.appendChild(tbl);
            renderActions();
        }

        /** 来源关系(02-02):按父模型分组的树形视图——左父模型卡,右同父子方案卡,右缘关联评估;不继承旧模型UQ。 */
        function renderRelation(shown) {
            if (!shown.length) {
                listHolder.appendChild(h('div', { class: 'wb-empty' }, '暂无模型;来源关系随模型登记生成。'));
                return;
            }
            listHolder.appendChild(h('div', { class: 'wb-hint', style: 'margin-bottom:10px' },
                '按父模型链回溯;同父并列方案各自独立,不继承父模型的UQ区间。'));

            // 分组:根模型(无父模型)与其子模型同块
            const byParent = {};
            shown.forEach(m => {
                const key = m.parentModelId || '';
                (byParent[key] = byParent[key] || { roots: [], children: [] });
                if (m.parentModelId) byParent[key].children.push(m);
                else byParent[key].roots.push(m);
            });
            const painted = new Set();
            const modelCard = (m, selected) => h('div', {
                style: 'border:1px solid ' + (selected ? '#0f766e' : '#e5e7eb') + ';background:' + (selected ? '#e5f1f2' : '#fff')
                    + ';border-radius:6px;padding:10px 14px;cursor:pointer;min-width:230px',
                onclick: () => {
                    MODEL_VIEW.checked = {};
                    MODEL_VIEW.checked[m.id] = true;
                    renderList();
                }
            },
                h('div', { style: 'font-weight:600;color:#111827' }, m.name || m.id),
                h('div', { class: 'wb-hint', style: 'margin:0' }, m.route || '—'),
                h('div', { class: 'wb-hint', style: 'margin:0' },
                    '训练: ' + (m.trainingFile ? String(m.trainingFile).split(/[\\/]/).pop() : '—')));

            const drawBlock = (rootArr, children) => {
                const root = rootArr[0];
                rootArr.forEach(r => painted.add(r.id));
                children.forEach(c => painted.add(c.id));
                const uqOnRoot = uqCount(root.id);
                const block = h('div', { style: 'display:grid;grid-template-columns:minmax(200px,280px) 24px minmax(240px,1fr) 150px;gap:0 8px;align-items:center;padding:18px 0;border-bottom:1px solid #f1f5f9' },
                    // 左:父模型卡 + 其UQ记录提示
                    h('div', null,
                        modelCard(root, !!MODEL_VIEW.checked[root.id]),
                        uqOnRoot ? h('div', { style: 'margin-top:8px;background:#f0f9ff;border:1px solid #bae6fd;border-radius:6px;padding:7px 12px;font-size:12px;color:#0369a1' },
                            '⇊ ' + root.name + ': ' + uqOnRoot + '份UQ记录') : null),
                    // 中:连线
                    children.length ? h('div', { style: 'height:100%;display:flex;align-items:center;justify-content:center;color:#94a3b8' }, '—') : h('div', null),
                    // 右:子方案卡列表
                    children.length
                        ? h('div', { style: 'display:flex;flex-direction:column;gap:10px' },
                            children.map(c => modelCard(c, !!MODEL_VIEW.checked[c.id])))
                        : h('div', { class: 'wb-hint' }, '无更新派生模型'),
                    // 右缘:关联评估
                    h('div', { style: 'display:flex;flex-direction:column;gap:10px' },
                        (children.length ? children : [root]).map(t => {
                            const n = uqCount(t.id);
                            return h('div', { style: 'font-size:12px;' + (n ? 'color:#0f766e;font-weight:600' : 'color:#6b7280') },
                                n ? (uqRecords.filter(r => r.modelAssetId === t.id && r.status === 'COMPLETED')[0] || {}).runId || n + '份记录' : '未评估');
                        })));
                listHolder.appendChild(block);
            };

            // 有子模型的根优先成块;剩余独立模型单独成块
            Object.keys(byParent).forEach(pid => {
                const grp = byParent[pid];
                if (!pid && grp.roots.length) {
                    grp.roots.forEach(root => {
                        const kids = shown.filter(m => m.parentModelId === root.id);
                        drawBlock([root], kids);
                    });
                }
            });
            shown.filter(m => !painted.has(m.id)).forEach(m => drawBlock([m], []));

            // 底部说明 + 动作(02-02)
            actionsBar.innerHTML = '';
            const checkedIds = Object.keys(MODEL_VIEW.checked).filter(id => models.some(m => m.id === id));
            actionsBar.appendChild(h('button', {
                class: 'wb-btn wb-btn-primary' + (checkedIds.length === 1 ? '' : ' disabled'),
                onclick: () => {
                    if (checkedIds.length !== 1) return;
                    MODEL_VIEW.tab = 'detail'; MODEL_VIEW.detailId = checkedIds[0]; renderModelsBody(ctx, body);
                }
            }, '打开已选模型详情'));
            const firstChecked = checkedIds.length ? models.find(m => m.id === checkedIds[0]) : null;
            actionsBar.appendChild(h('button', {
                class: 'wb-btn wb-btn-outline' + (firstChecked && uqCount(firstChecked.id) ? '' : ' disabled'),
                onclick: () => {
                    if (!firstChecked) return;
                    window.__WB_OPEN_MODEL_UQ__ = firstChecked.id;
                    MODEL_VIEW.tab = 'detail'; MODEL_VIEW.detailId = firstChecked.id; renderModelsBody(ctx, body);
                }
            }, firstChecked ? ('查看 ' + (firstChecked.name || '') + ' 的评估记录') : '查看评估记录'));
        }

        /** 底部动作(02-01):已选摘要 + 查看详情/来源关系/比较已选/新工况预测。 */
        function renderActions() {
            actionsBar.innerHTML = '';
            summaryHolder.innerHTML = '';
            if (MODEL_VIEW.tab === 'relation') return;
            const checkedIds = Object.keys(MODEL_VIEW.checked).filter(id => models.some(m => m.id === id));
            const checkedRows = checkedIds.map(id => models.find(m => m.id === id));
            // 已选摘要区(02-01):勾选后显示所选模型的方法/数据/父模型/UQ概览
            if (checkedRows.length === 1) {
                const m = checkedRows[0];
                const parent = models.find(p => p.id === m.parentModelId);
                const uqRec = uqRecords.find(r => r.modelAssetId === m.id && r.status === 'COMPLETED');
                summaryHolder.appendChild(h('div', { style: 'border-top:1px solid #f1f5f9;margin-top:14px;padding-top:12px' },
                    h('div', { style: 'display:flex;gap:18px;align-items:baseline;flex-wrap:wrap' },
                        h('span', { style: 'font-weight:600;font-size:15px' }, '已选 ' + (m.name || m.id)),
                        h('span', { class: 'wb-hint', style: 'margin:0' },
                            (m.stage || '—') + ' · ' + (m.route || '—'))),
                    h('div', { class: 'wb-hint', style: 'margin:6px 0 0;display:flex;gap:26px;flex-wrap:wrap' },
                        h('span', null, '训练数据 ' + (m.trainingFile ? String(m.trainingFile).split(/[\\/]/).pop() : '—')),
                        h('span', null, '父模型 ' + (parent ? parent.name : '基准配置')),
                        h('span', null, uqRec ? ((uqRec.runId || 'UQ') + ' · 方法' + (uqRec.method || '—')) : '未评估'))));
            }
            actionsBar.appendChild(h('button', {
                class: 'wb-btn wb-btn-primary' + (checkedRows.length ? '' : ' disabled'),
                onclick: () => {
                    if (!checkedRows.length) return;
                    const m = checkedRows[checkedRows.length - 1];
                    MODEL_VIEW.tab = 'detail'; MODEL_VIEW.detailId = m.id; renderModelsBody(ctx, body);
                }
            }, '查看模型详情'));
            actionsBar.appendChild(h('button', {
                class: 'wb-btn wb-btn-outline',
                onclick: () => { MODEL_VIEW.tab = 'relation'; renderModelsBody(ctx, body); }
            }, '查看来源关系'));
            actionsBar.appendChild(h('button', {
                class: 'wb-btn wb-btn-outline' + (checkedIds.length >= 2 ? '' : ' disabled'),
                title: checkedIds.length >= 2 ? '' : '勾选两份及以上模型后可比较',
                onclick: () => { if (checkedIds.length >= 2) compareModels(ctx, body, checkedIds); }
            }, '比较已选模型(' + checkedIds.length + ')'));
            actionsBar.appendChild(h('div', { class: 'wb-spacer' }));
            actionsBar.appendChild(h('button', {
                class: 'wb-btn wb-btn-primary' + (checkedIds.length === 1 ? '' : ' disabled'),
                title: checkedIds.length === 1 ? '' : '勾选一份模型用于新工况预测',
                onclick: () => {
                    if (checkedIds.length !== 1) return;
                    const m = models.find(x => x.id === checkedIds[0]);
                    window.__WB_PREDICT_MODEL__ = m;
                    ctx.navigate('predictions');
                }
            }, '新工况预测'));
        }

        function loadModels() {
            listHolder.innerHTML = '';
            listHolder.appendChild(h('div', { class: 'wb-empty' }, '正在加载模型成果...'));
            Promise.all([
                window.AppConfig.engineGet('projects/' + encodeURIComponent(ctx.project.id) + '/models'),
                window.AppConfig.engineGet('projects/' + encodeURIComponent(ctx.project.id) + '/uq-records').catch(() => null)
            ]).then(([resp, uqResp]) => {
                models = resp && (resp.success || resp.code === 200) && Array.isArray(resp.data) ? resp.data : [];
                uqRecords = uqResp && uqResp.success && Array.isArray(uqResp.data) ? uqResp.data : [];
                Object.keys(MODEL_VIEW.checked).forEach(id => {
                    if (!models.some(m => m.id === id)) delete MODEL_VIEW.checked[id];
                });
                renderList();
            }).catch(e => {
                listHolder.innerHTML = '';
                listHolder.appendChild(h('div', { class: 'wb-empty' }, '模型成果加载失败:' + e.message));
            });
        }
        loadModels();
    }

    /** 比较已选模型(02-06 前置):关键字段并排对照。 */
    function compareModels(ctx, body, ids) {
        window.AppConfig.engineGet('projects/' + encodeURIComponent(ctx.project.id) + '/models')
            .then(resp => {
                const models = resp && Array.isArray(resp.data) ? resp.data : [];
                const picked = ids.map(id => models.find(m => m.id === id)).filter(Boolean);
                const fields = [['模型', m => m.name || m.id], ['来源阶段', m => m.stage || '—'],
                    ['计算路径', m => m.route || '—'], ['训练数据', m => m.trainingFile ? String(m.trainingFile).split(/[\\/]/).pop() : '—'],
                    ['独立测试', m => m.testFile ? String(m.testFile).split(/[\\/]/).pop() : '未提供'],
                    ['父模型', m => { const p = models.find(x => x.id === m.parentModelId); return p ? p.name : '基准配置'; }],
                    ['结果状态', m => m.resultStatus || '—'], ['交付文件', m => m.deliveryWorkbookFile ? String(m.deliveryWorkbookFile).split(/[\\/]/).pop() : '—']];
                const tbl = h('table', { class: 'wb-table' },
                    h('tr', null, ['属性'].concat(picked.map(p => h('th', null, p.name || p.id)))));
                fields.forEach(([label, get]) => tbl.appendChild(h('tr', null,
                    h('td', { style: 'color:#6b7280' }, label),
                    picked.map(p => h('td', null, String(get(p)))))));
                const box = h('div', { class: 'wb-card', style: 'padding:14px;margin-top:14px' },
                    h('div', { class: 'wb-section-title', style: 'margin-bottom:8px' }, '比较已选模型'),
                    tbl,
                    h('div', { class: 'wb-actions-row', style: 'margin-top:10px' },
                        h('button', { class: 'wb-btn wb-btn-outline', onclick: () => renderModelsBody(ctx, body) }, '‹ 返回清单')));
                body.innerHTML = '';
                body.appendChild(box);
            });
    }

    /** 模型详情(02-03):来源与数据 / 参数与输出 / 不确定性评估。 */
    function renderModelDetail(ctx, body, modelId) {
        body.innerHTML = '';
        body.appendChild(h('div', { class: 'wb-empty' }, '正在加载模型详情...'));
        Promise.all([
            window.AppConfig.engineGet('projects/' + encodeURIComponent(ctx.project.id) + '/models'),
            window.AppConfig.engineGet('projects/' + encodeURIComponent(ctx.project.id) + '/uq-records').catch(() => null)
        ]).then(([resp, uqResp]) => {
            const models = resp && Array.isArray(resp.data) ? resp.data : [];
            const m = models.find(x => x.id === modelId);
            const uqRecords = uqResp && uqResp.success && Array.isArray(uqResp.data) ? uqResp.data : [];
            body.innerHTML = '';
            if (!m) {
                body.appendChild(h('div', { class: 'wb-empty' }, '模型不存在或已被删除。'));
                return;
            }
            const parent = models.find(p => p.id === m.parentModelId);
            // 顶部按钮行(02-03):返回模型清单 | 打开建模任务 | 新工况预测
            body.appendChild(h('div', { style: 'display:flex;align-items:center;gap:14px;margin-bottom:4px' },
                h('button', { class: 'wb-btn wb-btn-outline', onclick: () => { MODEL_VIEW.tab = 'list'; MODEL_VIEW.detailId = null; renderModelsBody(ctx, body); } }, '‹ 返回模型清单'),
                h('div', { class: 'wb-page-title', style: 'margin:0' }, '模型成果 / ' + (m.name || m.id)),
                h('div', { class: 'wb-spacer' }),
                m.taskId ? h('button', {
                    class: 'wb-btn wb-btn-outline',
                    onclick: () => {
                        if (ctx.openTask) ctx.openTask();
                        else toast('请从"建模任务"进入该模型来源任务(' + (m.taskId || '') + ')', 'info');
                    }
                }, '打开建模任务') : null,
                h('button', {
                    class: 'wb-btn wb-btn-primary',
                    onclick: () => { window.__WB_PREDICT_MODEL__ = m; ctx.navigate('predictions'); }
                }, '新工况预测')));
            body.appendChild(h('div', { class: 'wb-page-sub' },
                (m.sourceBusiness || '—') + ' · ' + (m.stage || '—') + ' / ' + (m.route || '—') + ' / ' + (m.engineId || '—') + ' · 三部件'));

            const tabBar = h('div', { class: 'wb-tabs', style: 'margin-bottom:12px' });
            const holder = h('div', null);
            const SUBS = [['src', '来源与数据'], ['param', '参数与输出'], ['uq', '不确定性评估']];
            let sub = 'src';
            SUBS.forEach(([key, label]) => tabBar.appendChild(h('div', {
                class: 'wb-tab', 'data-sub': key,
                onclick: () => { sub = key; paintTabs(); paint(); }
            }, label)));
            body.appendChild(tabBar);
            body.appendChild(holder);

            function paintTabs() {
                tabBar.querySelectorAll('.wb-tab').forEach(el =>
                    el.classList.toggle('active', el.getAttribute('data-sub') === sub));
            }
            function paint() {
                holder.innerHTML = '';
                if (sub === 'src') {
                    const myUq = uqRecords.filter(r => r.modelAssetId === m.id && r.status === 'COMPLETED');
                    if (m.resultStatus === '诊断(未收敛但有效)') {
                        holder.appendChild(h('div', { class: 'wb-infobar', style: 'border-left:4px solid #d97706;background:#fffbeb' },
                            '⚠ 模型已交付;小目标改进停止,一阶段驻点检查未通过;可进入支持的下游。'));
                    }
                    // 溯源行(02-03):父模型 | 当前建模方式 | 本次参数范围 | 关联UQ
                    holder.appendChild(h('table', { class: 'wb-table', style: 'max-width:1180px' },
                        h('tr', null, ['父模型', '当前建模方式', '本次参数范围', '关联UQ'].map(x => h('th', null, x))),
                        h('tr', null,
                            h('td', null, parent ? parent.name : '基准配置'),
                            h('td', null, (m.stage || '—') + ' / ' + (m.route || '—')),
                            h('td', null, '稳态系数、燃油偏置'),
                            h('td', null, myUq.length
                                ? myUq.map(r => r.runId || r.id).join('、')
                                : h('span', { class: 'wb-hint' }, '未评估')))));
                    // 输入数据与实际用途(02-03):真实训练/测试文件及其角色
                    holder.appendChild(h('div', { style: 'display:flex;justify-content:space-between;align-items:baseline;margin:16px 0 8px' },
                        h('div', { class: 'wb-section-title', style: 'margin:0' }, '输入数据与实际用途')));
                    const usageRows = [];
                    if (m.trainingFile) usageRows.push(['训练数据', String(m.trainingFile).split(/[\\/]/).pop(), '稳态训练点', '参与辨识与训练误差']);
                    if (m.testFile) usageRows.push(['独立测试', String(m.testFile).split(/[\\/]/).pop(), '独立测试', '测试误差单独报告,不并入训练']);
                    holder.appendChild(usageRows.length
                        ? h('table', { class: 'wb-table', style: 'max-width:1180px' },
                            h('tr', null, ['数据批次', '原始文件', '本次角色', '实际使用范围'].map(x => h('th', null, x))),
                            usageRows.map(r => h('tr', null, r.map((c, i) => h('td', i > 0 ? { class: 'wb-hint' } : null, c)))))
                        : h('div', { class: 'wb-hint' }, '导入模型未携带数据批次信息;数据血缘见交付 identity.json。'));
                    // 本次模型交付(02-03):工作簿 + 身份文件 + 输出位置
                    holder.appendChild(h('div', { class: 'wb-section-title', style: 'margin:16px 0 8px' }, '本次模型交付'));
                    holder.appendChild(h('table', { class: 'wb-table', style: 'max-width:1180px' },
                        h('tr', null, ['文件', '说明', ''].map(x => h('th', null, x))),
                        h('tr', null,
                            h('td', null, m.deliveryWorkbookFile ? String(m.deliveryWorkbookFile).split(/[\\/]/).pop() : '—'),
                            h('td', { class: 'wb-hint' }, '正式交付工作簿(恢复下游模型;不含训练明细)'),
                            h('td', null, m.deliveryWorkbookFile
                                ? h('a', { class: 'wb-btn wb-btn-outline', href: modelDownloadUrl(ctx.project.id, m.id) }, '下载')
                                : h('span', { class: 'wb-hint' }, '无'))),
                        m.identityFile ? h('tr', null,
                            h('td', null, String(m.identityFile).split(/[\\/]/).pop()),
                            h('td', { class: 'wb-hint' }, '模型身份文件(导入携带)'),
                            h('td', null, '')) : null));
                    if (m.deliveryWorkbookFile) {
                        holder.appendChild(h('div', { class: 'wb-hint', style: 'margin-top:4px' },
                            '输出位置: ' + String(m.deliveryWorkbookFile).replace(/[\\/][^\\/]+$/, '')));
                    }
                    holder.appendChild(h('div', { class: 'wb-actions-row', style: 'margin-top:10px' },
                        h('button', { class: 'wb-btn wb-btn-outline', onclick: () => { MODEL_VIEW.tab = 'relation'; renderModelsBody(ctx, body); } }, '查看数据关联模型'),
                        h('button', { class: 'wb-btn wb-btn-primary', onclick: () => { window.__WB_PREDICT_MODEL__ = m; ctx.navigate('predictions'); } }, '新工况预测')));
                } else if (sub === 'param') {
                    const ph = h('div', null, h('div', { class: 'wb-hint' }, '正在加载参数与节点表...'));
                    holder.appendChild(ph);
                    if (!m.taskId) {
                        ph.innerHTML = '';
                        ph.appendChild(h('div', { class: 'wb-hint' }, '导入模型未携带任务结果;完整参数与节点见交付工作簿。'));
                        return;
                    }
                    window.AppConfig.engineGet('projects/' + encodeURIComponent(ctx.project.id)
                            + '/tasks/' + encodeURIComponent(m.taskId) + '/result-detail')
                        .then(resp => {
                            ph.innerHTML = '';
                            const d = resp && (resp.success || resp.code === 200) ? resp.data : null;
                            if (!d) { ph.appendChild(h('div', { class: 'wb-hint' }, (resp && resp.message) || '结果明细未生成。')); return; }
                            const classRows = d.parameterClassTable;
                            if (Array.isArray(classRows) && classRows.length) {
                                ph.appendChild(h('div', { class: 'wb-section-title', style: 'margin-bottom:8px' }, '全部参数'));
                                ph.appendChild(WB().dataTable(classRows, { maxRows: 14 }));
                            }
                            const nodes = Array.isArray(d.scheduleNodeTable) ? d.scheduleNodeTable
                                : Array.isArray(d.finalSchedule) ? d.finalSchedule : null;
                            if (Array.isArray(nodes) && nodes.length) {
                                ph.appendChild(h('div', { class: 'wb-section-title', style: 'margin:14px 0 8px' }, '调度节点'));
                                ph.appendChild(WB().dataTable(nodes, { maxRows: 20 }));
                            }
                            if (!classRows && !nodes) ph.appendChild(h('div', { class: 'wb-hint' }, '明细中未包含参数/节点表;以交付Excel为准。'));
                        })
                        .catch(e => { ph.innerHTML = ''; ph.appendChild(h('div', { class: 'wb-hint' }, '加载失败:' + e.message)); });
                } else {
                    const mine = uqRecords.filter(r => r.modelAssetId === m.id);
                    if (!mine.length) {
                        holder.appendChild(h('div', { class: 'wb-hint' },
                            '此模型暂无不确定性评估;同父并列方案不继承旧模型UQ,需新建匹配评估。'));
                        return;
                    }
                    holder.appendChild(h('table', { class: 'wb-table', style: 'max-width:1180px' },
                        h('tr', null, ['运行标识', '方法', '粒子数', '状态', '开始时间', ''].map(x => h('th', null, x))),
                        mine.map(r => h('tr', null,
                            h('td', null, r.runId || r.id),
                            h('td', null, r.method || '—'),
                            h('td', null, r.particleCount || '默认'),
                            h('td', null, r.status === 'COMPLETED' ? '已完成' : r.status === 'FAILED' ? '失败' : (r.status || '—')),
                            h('td', { class: 'wb-hint' }, r.startedAt ? new Date(r.startedAt).toLocaleString() : '—'),
                            h('td', null, r.status === 'COMPLETED'
                                ? h('button', {
                                    class: 'wb-btn wb-btn-outline',
                                    onclick: () => {
                                        window.AppConfig.engineGet('projects/' + encodeURIComponent(ctx.project.id)
                                                + '/uq-records/' + encodeURIComponent(r.id) + '/detail')
                                            .then(resp => {
                                                const d = resp && (resp.success || resp.code === 200) ? resp.data : null;
                                                const tbl = d && (d.parameterTable || (d.delivery && d.delivery.parameterTable));
                                                detailHolder.innerHTML = '';
                                                detailHolder.appendChild(Array.isArray(tbl) && tbl.length
                                                    ? WB().dataTable(tbl, { maxRows: 20 })
                                                    : h('div', { class: 'wb-hint' }, '明细中未包含参数区间表。'));
                                            })
                                            .catch(e => toast('加载UQ明细失败:' + e.message, 'error'));
                                    }
                                }, '查看区间表')
                                : h('span', null, ''))))));
                    const detailHolder = h('div', { style: 'margin-top:10px' });
                    holder.appendChild(detailHolder);
                }
            }
            paintTabs();
            paint();
        }).catch(e => {
            body.innerHTML = '';
            body.appendChild(h('div', { class: 'wb-empty' }, '模型详情加载失败:' + e.message));
        });
    }

    /* ===== 个性化建模 · 输出预测(F-08 独立稳态预测,单工况确定性)===== */
    const PREDICT_FIELDS = {
        1: { label: '模式1 · 可测边界(Pt1/Tt1/Pamb)', fields: ['Pt1', 'Tt1', 'Pamb', 'Tamb', 'Mach', 'Wf_model', 'Mkp', 'Mkg'] },
        2: { label: '模式2 · 环境边界(Pamb/Tamb/Mach)', fields: ['Pamb', 'Tamb', 'Mach', 'Wf_model', 'Mkp', 'Mkg'] },
        3: { label: '模式3 · 高度边界(Altitude/Tamb/Mach)', fields: ['Altitude', 'Tamb', 'Mach', 'Wf_model', 'Mkp', 'Mkg'] }
    };
    const PREDICT_DEFAULTS = {
        Pt1: '101325', Tt1: '288.15', Pamb: '101325', Tamb: '288.15', Mach: '0',
        Wf_model: '1.20', Mkp: '320.0', Mkg: '0.0', Altitude: '0'
    };
    const PREDICT_UNITS = {
        Pt1: 'Pa', Tt1: 'K', Pamb: 'Pa', Tamb: 'K', Mach: '—',
        Wf_model: 'kg/s', Mkp: 'N·m', Mkg: 'N·m', Altitude: 'm'
    };

    pages['modeling.predictions'] = (ctx) => {
        const pre0 = window.__WB_PREDICT_MODEL__;
        const wrap = h('div', null,
            h('div', { style: 'margin-bottom:14px' },
                h('div', { class: 'wb-page-title', style: 'font-size:20px;margin-bottom:2px' }, '独立稳态输出预测'),
                h('div', { class: 'wb-page-sub' },
                    (ctx.project.engineId || '—') + ' / ' + (pre0 ? (pre0.name || pre0.id) : '模型待选')
                    + ' / 新工况输入，不需要目标测量输出')));
        const body = h('div', null);
        wrap.appendChild(body);

        const modelSel = h('select', { style: 'width:100%' });
        const uqSel = h('select', { style: 'width:100%' }, h('option', { value: '' }, '不使用(确定性预测)'));
        const modeSel = h('select', { style: 'width:100%' }, Object.keys(PREDICT_FIELDS).map(k =>
            h('option', { value: k }, PREDICT_FIELDS[k].label)));
        const condsHolder = h('div', null);
        const runBtn = h('button', { class: 'wb-btn wb-btn-primary disabled' }, '计算预测');
        const saveBtn = h('button', { class: 'wb-btn wb-btn-outline disabled' }, '保存预测记录');
        const resultHolder = h('div', null, h('div', { class: 'wb-empty' }, '尚未计算——配置输入后开始预测。空白不代表零误差。'));
        const historyHolder = h('div', null);
        const pre = window.__WB_PREDICT_MODEL__;
        delete window.__WB_PREDICT_MODEL__;
        const conds = []; // [{id, grid}]
        let models = [];
        let uqRecords = [];

        function buildCondInputs(mode) {
            const grid = h('div', { class: 'wb-form-grid', style: 'margin-top:8px;grid-template-columns:repeat(4,1fr)' });
            PREDICT_FIELDS[mode].fields.forEach(name => {
                const unit = PREDICT_UNITS[name] && PREDICT_UNITS[name] !== '—' ? ' / ' + PREDICT_UNITS[name] : '';
                grid.appendChild(h('div', { class: 'wb-field' },
                    h('label', null, name + unit),
                    h('input', { 'data-pred': name, value: PREDICT_DEFAULTS[name] || '' })));
            });
            return grid;
        }

        function addCondition(id, preset) {
            const cid = id || 'P' + String(conds.length + 1).padStart(2, '0');
            const grid = buildCondInputs(modeSel.value);
            if (preset) {
                Object.keys(preset).forEach(k => {
                    const inp = grid.querySelector('input[data-pred="' + k + '"]');
                    if (inp && preset[k] != null) inp.value = String(preset[k]);
                });
            }
            const delBtn = h('button', { class: 'wb-btn wb-btn-outline', title: '删除该工况' }, '删除');
            const card = h('div', { class: 'wb-card', style: 'padding:12px;margin-bottom:10px' },
                h('div', { style: 'display:flex;align-items:center;gap:10px;margin-bottom:4px' },
                    h('div', { style: 'font-weight:700;color:#111827' }, cid), h('div', { class: 'wb-spacer' }), delBtn),
                grid);
            delBtn.addEventListener('click', () => {
                const idx = conds.findIndex(c => c.id === cid);
                if (idx >= 0 && conds.length > 1) { conds.splice(idx, 1); card.remove(); renumber(); }
                else toast('至少保留一个工况', 'info');
            });
            conds.push({ id: cid, grid });
            condsHolder.appendChild(card);
        }

        function renumber() {
            // 删除后重排编号(保持顺序)
            conds.forEach((c, i) => {
                const nid = 'P' + String(i + 1).padStart(2, '0');
                const title = c.grid.parentNode && c.grid.parentNode.querySelector('div div');
                if (title && title.textContent.indexOf('P') === 0) title.textContent = nid;
                c.id = nid;
            });
        }

        modeSel.addEventListener('change', () => {
            conds.forEach(c => {
                const fresh = buildCondInputs(modeSel.value);
                c.grid.replaceWith(fresh);
                c.grid = fresh;
            });
        });

        function condInputs(c) {
            const inputs = {};
            let bad = null;
            c.grid.querySelectorAll('input[data-pred]').forEach(inp => {
                const v = parseFloat(inp.value);
                if (isNaN(v)) bad = inp.getAttribute('data-pred');
                inputs[inp.getAttribute('data-pred')] = v;
            });
            return { inputs, bad };
        }

        async function loadModels() {
            modelSel.innerHTML = '';
            try {
                const resp = await window.AppConfig.engineGet('projects/' + encodeURIComponent(ctx.project.id) + '/models');
                models = resp && (resp.success || resp.code === 200) && Array.isArray(resp.data) ? resp.data : [];
                const usable = models.filter(m => m.deliveryWorkbookFile);
                if (!usable.length) {
                    modelSel.appendChild(h('option', { value: '' }, '尚无可用模型——请先在建模结果页登记或导入模型'));
                    runBtn.classList.add('disabled');
                    return;
                }
                usable.forEach(m => modelSel.appendChild(h('option', { value: m.id },
                    (m.name || m.id) + (m.stage ? ' · ' + m.stage : ''))));
                if (pre && usable.some(m => m.id === pre.id)) modelSel.value = pre.id;
                runBtn.classList.remove('disabled');
                loadUqOptions();
            } catch (e) {
                modelSel.appendChild(h('option', { value: '' }, '模型列表加载失败'));
                runBtn.classList.add('disabled');
            }
        }

        /** UQ下拉(图01-11/01-24):显式选择某份已完成评估,区间在新输入下重新传播;不移植父模型区间。 */
        function loadUqOptions() {
            uqSel.innerHTML = '';
            uqSel.appendChild(h('option', { value: '' }, '不使用(确定性预测)'));
            window.AppConfig.engineGet('projects/' + encodeURIComponent(ctx.project.id) + '/uq-records')
                .then(resp => {
                    uqRecords = resp && (resp.success || resp.code === 200) && Array.isArray(resp.data) ? resp.data : [];
                    const mid = modelSel.value;
                    uqRecords.filter(r => r.status === 'COMPLETED' && (!mid || r.modelAssetId === mid))
                        .forEach(r => uqSel.appendChild(h('option', { value: r.id },
                            (r.runId || r.id) + ' · 方法' + (r.method || '—'))));
                })
                .catch(() => { });
        }
        modelSel.addEventListener('change', loadUqOptions);

        runBtn.addEventListener('click', async () => {
            const modelId = modelSel.value;
            if (!modelId) { toast('请先选择模型', 'error'); return; }
            const payload = [];
            for (const c of conds) {
                const { inputs, bad } = condInputs(c);
                if (bad) { toast('工况 ' + c.id + ' 输入项 ' + bad + ' 必须为数值', 'error'); return; }
                inputs.inletBoundaryMode = parseInt(modeSel.value, 10);
                payload.push({ id: c.id, inputs });
            }
            runBtn.classList.add('disabled');
            runBtn.textContent = '预测执行中...';
            try {
                const resp = await window.AppConfig.enginePost(
                    'projects/' + encodeURIComponent(ctx.project.id) + '/predict?modelAssetId=' + encodeURIComponent(modelId),
                    { conditions: payload, uqRecordId: uqSel.value || null });
                if (resp && (resp.success || resp.code === 200) && resp.data) {
                    toast('预测已发起,程序计算中...', 'info');
                    pollPrediction(resp.data.id, () => {
                        runBtn.classList.remove('disabled');
                        runBtn.textContent = '计算预测';
                    });
                } else {
                    throw new Error((resp && resp.message) || '发起失败');
                }
            } catch (e) {
                toast('发起输出预测失败:' + e.message, 'error');
                runBtn.classList.remove('disabled');
                runBtn.textContent = '计算预测';
            }
        });

        saveBtn.addEventListener('click', () => {
            toast('预测记录在完成时已自动保存;可在下方"预测记录"中查看', 'info');
        });

        function predExportUrl(recId, condId) {
            const cfg = window.AppConfig;
            const qs = (condId ? 'cond=' + encodeURIComponent(condId) + '&' : '')
                + 'token=' + encodeURIComponent(cfg.getToken() || '');
            return cfg.api.baseURL + '/api/engine/projects/' + encodeURIComponent(ctx.project.id)
                + '/predictions/' + encodeURIComponent(recId) + '/export?' + qs;
        }

        function pollPrediction(recId, done) {
            const started = Date.now();
            const timer = setInterval(async () => {
                window.__WB_ENGINE_POLL_UNTIL__ = Date.now() + 40000; // 活动心跳
                try {
                    const resp = await window.AppConfig.engineGet('projects/' + encodeURIComponent(ctx.project.id) + '/predictions');
                    const list = resp && (resp.success || resp.code === 200) && Array.isArray(resp.data) ? resp.data : [];
                    const rec = list.find(r => r.id === recId);
                    if (rec && rec.status !== 'EXECUTING') {
                        clearInterval(timer);
                        renderLatest(rec);
                        loadHistory();
                        toast(rec.status === 'COMPLETED' ? '预测完成' : '预测失败:' + (rec.message || ''),
                            rec.status === 'COMPLETED' ? 'success' : 'error');
                        if (done) done();
                    } else if (Date.now() - started > 10 * 60 * 1000) {
                        clearInterval(timer);
                        toast('预测超时未返回', 'error');
                        if (done) done();
                    } else {
                        renderLatest(rec || { status: 'EXECUTING', message: '程序计算中...' });
                    }
                } catch (e) { /* 轮询容错 */ }
            }, 5000);
        }

        function renderValue(v, indent) {
            const box = h('div', indent ? { style: 'padding-left:18px' } : null);
            if (v && typeof v === 'object' && !Array.isArray(v)) {
                Object.keys(v).forEach(k => {
                    const val = v[k];
                    if (val && typeof val === 'object') {
                        box.appendChild(h('div', { style: 'margin:4px 0;font-weight:600;color:#374151' }, k));
                        box.appendChild(renderValue(val, true));
                    } else {
                        box.appendChild(h('div', { class: 'wb-kv', style: 'grid-template-columns:260px 1fr' },
                            h('div', { class: 'k' }, k),
                            h('div', { class: 'v' }, val == null ? '—' : String(val))));
                    }
                });
            }
            return box;
        }

        /** 结果区(01-11/01-12):多工况逐条状态 + 关键输出列 + 单工况查看 + 失败诊断展开 + 导出Excel。 */
        function renderLatest(rec) {
            resultHolder.innerHTML = '';
            if (!rec) {
                resultHolder.appendChild(h('div', { class: 'wb-empty' }, '尚未计算——配置输入后开始预测。'));
                return;
            }
            const running = rec.status === 'EXECUTING';
            resultHolder.appendChild(h('div', { class: 'wb-infobar' },
                running ? (rec.message || '程序计算中...') : rec.message || rec.status));
            if (running) {
                resultHolder.appendChild(h('div', { style: 'text-align:center;padding:14px 0' },
                    h('span', { class: 'wb-inline-loading' }, h('span', { class: 'wb-inline-spinner' }), '预测算法运行中...')));
                return;
            }
            if (rec.runId) {
                resultHolder.appendChild(h('div', { class: 'wb-hint', style: 'margin-bottom:8px' },
                    '运行标识 ' + rec.runId + (rec.uqRecordId ? ' · 区间来源:所选UQ记录' : ' · 确定性计算(区间状态:未计算)')));
            }
            const condList = Array.isArray(rec.conditions) && rec.conditions.length ? rec.conditions
                : [{ id: 'P01', status: rec.status, message: rec.message, result: rec.result }];
            // 已有输出的工况才渲染行;全部无输出时给出明确空态而不是空表
            const withResult = condList.filter(c => c.result && Object.keys(c.result).length);
            if (!withResult.length && !condList.some(c => c.status === 'FAILED')) {
                resultHolder.appendChild(h('div', { class: 'wb-hint', style: 'margin:8px 0' },
                    '本次运行未产生可展示的单工况输出对象;输出Excel与完整结果以导出文件为准。'));
                return;
            }
            // 关键输出提取(01-12汇总表):递归任意嵌套(≤3层)按通道名取值,兼容顶层/outputs/output等结构
            const pickOut = (c, name) => {
                let found = null;
                const walk = (obj, depth) => {
                    if (found != null || obj == null || typeof obj !== 'object' || depth > 3) return;
                    if (Array.isArray(obj)) { obj.forEach(o => walk(o, depth + 1)); return; }
                    Object.keys(obj).forEach(k => {
                        if (found != null) return;
                        const v = obj[k];
                        if (typeof v !== 'object' && k.toLowerCase() === name.toLowerCase()
                            && v != null && isFinite(parseFloat(v))) { found = parseFloat(v); return; }
                        if (v && typeof v === 'object') walk(v, depth + 1);
                    });
                };
                walk(c.result || {}, 0);
                return found;
            };
            // 诊断展开过滤输入回显等元数据,只留输出与执行信息(不再整包dump)
            const META_KEY = /^(input|modelInput|inputContract|schemaVersion|createdAt|inputSummary)$/i;
            const stripMeta = v => {
                if (v && typeof v === 'object' && !Array.isArray(v)) {
                    const out = {};
                    Object.keys(v).forEach(k => { if (!META_KEY.test(k)) out[k] = stripMeta(v[k]); });
                    return Object.keys(out).length ? out : undefined;
                }
                return v;
            };
            const fmtOut = v => v == null ? '—' : (Math.abs(v) >= 1000 ? v.toFixed(0) : Math.abs(v) >= 1 ? v.toFixed(3) : v.toFixed(4));
            // 01-11/01-24 单工况通道表:输出|单位|确定性计算值|95%候选参数输出区间(区间来自程序intervalTable)
            const OUTPUT_UNITS = { Np: 'rpm', Ng: 'rpm', Ptb3: 'Pa', Ttb3: 'K', Pt45: 'Pa', Tt45: 'K', Pt6: 'Pa', Tt6: 'K', Wa2: 'kg/s' };
            const findIntervalTable = c => {
                let hit = null;
                const walk = (obj, depth) => {
                    if (hit || obj == null || typeof obj !== 'object' || depth > 3) return;
                    if (Array.isArray(obj)) { obj.forEach(o => walk(o, depth + 1)); return; }
                    Object.keys(obj).forEach(k => {
                        if (hit) return;
                        const v = obj[k];
                        if (/interval/i.test(k) && Array.isArray(v) && v.length
                            && v.some(e => e && e.model_lower != null)) hit = v;
                        else if (v && typeof v === 'object') walk(v, depth + 1);
                    });
                };
                walk(c.result || {}, 0);
                return hit;
            };
            const condChannelTable = c => {
                const it = findIntervalTable(c);
                const rows = ['Np', 'Ng', 'Ptb3', 'Ttb3', 'Pt45', 'Tt45', 'Pt6', 'Tt6', 'Wa2'];
                const rowOf = n => it ? it.find(e => e && String(e.output_name || '').trim() === n) : null;
                const vals = rows.map(n => {
                    const r0 = rowOf(n);
                    return (r0 && r0.deterministic_frozen_model != null && isFinite(r0.deterministic_frozen_model))
                        ? parseFloat(r0.deterministic_frozen_model) : pickOut(c, n);
                });
                if (vals.every(v => v == null)) return null;
                const hasIv = !!it;
                const fmtIv = e => (e && e.model_lower != null && isFinite(e.model_lower) && isFinite(e.model_upper))
                    ? '[' + Number(e.model_lower).toFixed(1) + ', ' + Number(e.model_upper).toFixed(1) + ']'
                    : '未计算';
                return h('table', { class: 'wb-table', style: 'margin-top:8px' },
                    h('tr', null, ['输出', '单位', '确定性计算值', hasIv ? '95%候选参数输出区间' : '区间状态'].map(x => h('th', null, x))),
                    rows.map((n, i) => h('tr', null,
                        h('td', null, n),
                        h('td', { class: 'wb-hint' }, (rowOf(n) && rowOf(n).unit) || OUTPUT_UNITS[n]),
                        h('td', null, fmtOut(vals[i])),
                        h('td', { class: 'wb-hint' }, hasIv ? fmtIv(rowOf(n)) : '未计算'))));
            };
            const actionsRow = () => h('div', { class: 'wb-actions-row', style: 'margin-top:12px' },
                saveBtn,
                h('a', { class: 'wb-btn wb-btn-outline' + (condList.some(c => c.excelFile) ? '' : ' disabled'),
                    href: condList.some(c => c.excelFile) ? predExportUrl(rec.id) : '#' }, '导出预测Excel'),
                h('div', { class: 'wb-spacer' }),
                h('button', { class: 'wb-btn wb-btn-outline', onclick: () => ctx.navigate('models') }, '返回模型成果'),
                h('button', { class: 'wb-btn wb-btn-outline', onclick: () => addCondition() }, '添加工况'));

            // 单工况完成(01-11):直接平铺"P01 预测结果"+通道表,不套工况汇总表
            if (condList.length === 1 && condList[0].status === 'COMPLETED') {
                const c = condList[0];
                const doneText = rec.uqRecordId ? '确定性及候选区间已计算' : '确定性计算已完成';
                resultHolder.appendChild(h('div', { style: 'display:flex;justify-content:space-between;align-items:baseline;margin:4px 0 8px' },
                    h('div', { class: 'wb-section-title', style: 'margin:0' }, c.id + ' 预测结果'),
                    h('span', { style: 'color:#0f766e;font-weight:600;font-size:13px' }, doneText)));
                const ct = condChannelTable(c);
                if (ct) resultHolder.appendChild(ct);
                else {
                    resultHolder.appendChild(h('div', { class: 'wb-hint', style: 'margin:6px 0' },
                        '程序返回中未包含可展示的输出通道数值;完整输出以导出Excel为准。'));
                    resultHolder.appendChild(renderValue(stripMeta(c.result) || {}, false));
                }
                resultHolder.appendChild(h('div', { class: 'wb-hint', style: 'margin-top:6px' },
                    (rec.runId || '') + ' · ' + (rec.uqRecordId
                        ? '条件参数输出区间,不含新测量误差' : '确定性计算 · 全部输出可展开') + ';无测量值,不计算误差。'));
                if (c.message && c.message.indexOf('诊断') >= 0) {
                    resultHolder.appendChild(h('div', { class: 'wb-infobar', style: 'border-left:4px solid #d97706;background:#fffbeb;margin-top:8px' },
                        '⚠ ' + c.message));
                }
                resultHolder.appendChild(actionsRow());
                return;
            }

            // 多工况/失败(01-12):汇总表 + 单工况查看展开
            const tbl = h('table', { class: 'wb-table' },
                h('tr', null, ['工况', '状态', 'Np / rpm', 'Ng / rpm', 'Tt45 / K', '说明', ''].map(t => h('th', null, t))));
            condList.forEach(c => {
                const channelTbl = condChannelTable(c);
                const diag = h('div', { style: 'display:none;margin-top:6px;padding:8px;background:#f8fafc;border-radius:6px' },
                    h('div', { class: 'wb-hint', style: 'margin:0 0 4px' }, '单工况输出(全部输出可展开;无测量值,不计算误差):'),
                    channelTbl ? channelTbl : renderValue(stripMeta(c.result) || {}, false));
                const viewBtn = h('button', { class: 'wb-btn wb-btn-outline' }, '查看');
                viewBtn.addEventListener('click', () => {
                    diag.style.display = diag.style.display === 'none' ? '' : 'none';
                });
                const diagBtn = c.status === 'FAILED'
                    ? h('button', { class: 'wb-btn wb-btn-outline' }, '查看失败详情')
                    : (c.excelFile ? h('a', {
                        class: 'wb-btn wb-btn-outline', href: predExportUrl(rec.id, c.id)
                    }, '导出Excel') : h('span', null, ''));
                if (c.status === 'FAILED') {
                    diagBtn.addEventListener('click', () => {
                        diag.style.display = diag.style.display === 'none' ? '' : 'none';
                    });
                }
                tbl.appendChild(h('tr', null,
                    h('td', { style: 'font-weight:600' }, c.id || '—'),
                    h('td', null, statusTag(c.status === 'COMPLETED' ? '已完成' : c.status === 'FAILED' ? '失败' : '执行中',
                        c.status === 'COMPLETED' ? 'teal' : c.status === 'FAILED' ? 'red' : 'amber')),
                    h('td', null, fmtOut(pickOut(c, 'Np'))),
                    h('td', null, fmtOut(pickOut(c, 'Ng'))),
                    h('td', null, fmtOut(pickOut(c, 'Tt45'))),
                    h('td', { class: 'wb-hint', style: 'word-break:break-all' },
                        (c.message || '—') + (c.status === 'FAILED' ? ' · 未形成有效结果,不并入成功子集' : '')),
                    h('td', null, viewBtn, diagBtn, diag)));
            });
            resultHolder.appendChild(tbl);
            resultHolder.appendChild(actionsRow());
        }

        async function loadHistory() {
            historyHolder.innerHTML = '';
            try {
                const resp = await window.AppConfig.engineGet('projects/' + encodeURIComponent(ctx.project.id) + '/predictions');
                const list = resp && (resp.success || resp.code === 200) && Array.isArray(resp.data) ? resp.data : [];
                if (!list.length) {
                    historyHolder.appendChild(h('div', { class: 'wb-empty' }, '暂无预测记录'));
                    return;
                }
                historyHolder.appendChild(h('table', { class: 'wb-table' },
                    h('tr', null, ['时间', '模型', '工况', '运行标识', '状态'].map(t => h('th', null, t))),
                    list.slice(0, 20).map(r => h('tr', { class: 'clickable', onclick: () => renderLatest(r) },
                        h('td', { class: 'wb-hint' }, r.createdAt ? new Date(r.createdAt).toLocaleString() : '—'),
                        h('td', null, r.modelName || '—'),
                        h('td', { class: 'wb-hint' },
                            (Array.isArray(r.conditions) && r.conditions.length
                                ? r.conditions.map(c => c.id + (c.status === 'FAILED' ? '(失败)' : '')).join(' ')
                                : inputSummary(r.inputs))),
                        h('td', { class: 'wb-hint' }, r.runId || '—'),
                        h('td', null, statusTag(
                            r.status === 'COMPLETED' ? '已完成' : r.status === 'FAILED' ? '失败' : '执行中',
                            r.status === 'COMPLETED' ? 'teal' : r.status === 'FAILED' ? 'red' : 'amber'))))));
            } catch (e) {
                historyHolder.appendChild(h('div', { class: 'wb-empty' }, '预测记录加载失败:' + e.message));
            }
        }

        function inputSummary(inputs) {
            if (!inputs) return '—';
            return Object.keys(inputs).filter(k => k !== 'inletBoundaryMode')
                .map(k => k + '=' + inputs[k]).join(' ');
        }

        // 01-11 布局:顶部三下拉一行三列 → 工况输入(4列网格) → 计算按钮 → 结果 → 记录
        body.appendChild(h('div', { class: 'wb-form-grid', style: 'grid-template-columns:1fr 1fr 1fr;margin-bottom:6px' },
            h('div', { class: 'wb-field' }, h('label', null, '模型'), modelSel),
            h('div', { class: 'wb-field' }, h('label', null, '不确定性评估'), uqSel),
            h('div', { class: 'wb-field' }, h('label', null, '边界输入方式'), modeSel)));
        body.appendChild(h('div', { style: 'display:flex;justify-content:space-between;align-items:center;margin:2px 0 8px' },
            h('div', { class: 'wb-hint', style: 'margin:0;font-weight:600' }, '预测工况'),
            h('button', { class: 'wb-btn wb-btn-outline' , onclick: () => addCondition() }, '＋ 添加工况')));
        body.appendChild(condsHolder);
        body.appendChild(h('div', { style: 'display:flex;justify-content:space-between;align-items:center;margin:6px 0 14px' },
            h('div', { class: 'wb-hint', style: 'margin:0' }, '物理燃油输入；不重复扣除燃油测量偏置。'),
            runBtn));
        body.appendChild(h('div', { class: 'wb-section' },
            h('div', { class: 'wb-section-title', style: 'margin-bottom:12px' }, '预测结果'),
            resultHolder));
        body.appendChild(h('div', { class: 'wb-section' },
            h('div', { class: 'wb-section-title', style: 'margin-bottom:12px' }, '预测记录(点击行查看结果)'),
            historyHolder));
        addCondition();
        loadModels();
        loadHistory();
        return wrap;
    };

    /* ===== 运行记录 / 仿真记录 ===== */
    const RUN_STATUS = {
        READY: ['空闲', 'gray'], PREPARING: ['准备中', 'amber'], RUNNING: ['运行中', 'teal'],
        COMPLETED: ['已完成', 'teal'], FAILED: ['失败', 'red'],
        STOP_REQUESTED: ['停止中', 'amber'], STOPPED: ['已停止', 'gray']
    };

    function recordsPage(ctx, scope) {
        const isSim = scope === 'sim';
        if (isSim) return afoRecordsPage(ctx);
        const wrap = h('div', null, pageHeader(isSim ? '仿真记录' : '运行记录',
            isSim ? '全模式仿真与多系统联合仿真的执行记录;历史只读'
                : '建模任务执行历史(含数据准备/辨识);只读'));
        const holder = h('div', null, h('div', { class: 'wb-empty' }, '正在加载记录...'));
        wrap.appendChild(h('div', { class: 'wb-section' },
            h('div', { class: 'wb-section-head' },
                h('div', { class: 'wb-section-title' }, isSim ? '仿真执行历史' : '任务执行历史'),
                h('button', { class: 'wb-btn wb-btn-outline', onclick: () => ctx.navigate('records') }, '刷新')),
            holder));
        if (!isSim && ctx.project && ctx.project.id) loadRunRecords(ctx, holder);
        else holder.innerHTML = '';
        if (isSim || !ctx.project || !ctx.project.id) {
            holder.appendChild(h('div', { class: 'wb-empty' }, isSim ? '暂无仿真记录' : '本地演示项目无记录'));
        }
        return wrap;
    }

    /** 多系统联合仿真记录页(09-07/09-08):列表 + 只读查看 + 配置比较与通道叠加。 */
    function afoRecordsPage(ctx) {
        const pid = ctx.project.id || '';
        const api = () => window.AppConfig.engineGet('projects/' + encodeURIComponent(pid) + '/afo/sessions');
        const wrap = h('div', null, pageHeader('仿真记录',
            (ctx.project.engineId || '—') + ' 仿真执行历史;历史只读,原运行包与配置保持不变,不自动采用当前最新DLL重新解释历史结果'));
        const listHolder = h('div', null, h('div', { class: 'wb-empty' }, '正在加载仿真记录...'));
        const selHolder = h('div', null);
        const cmpHolder = h('div', null);
        const checked = {};
        wrap.appendChild(h('div', { class: 'wb-section' },
            h('div', { class: 'wb-section-head' },
                h('div', { class: 'wb-section-title' }, (ctx.project.engineId || 'E') + ' 仿真记录'),
                h('button', { class: 'wb-btn wb-btn-outline', onclick: () => ctx.navigate('records') }, '刷新')),
            listHolder));
        wrap.appendChild(selHolder);
        wrap.appendChild(cmpHolder);

        function renderList(rows) {
            listHolder.innerHTML = '';
            if (!rows.length) {
                listHolder.appendChild(h('div', { class: 'wb-empty' },
                    '暂无仿真记录——在"多系统联合仿真"发起准备并运行后,每次执行在此留档(以运行编号为身份)。'));
                return;
            }
            const tbl = h('table', { class: 'wb-table' },
                h('tr', null, ['', '运行', '输入与空气配置', '仿真时长', '记录状态', '操作'].map((x, i) =>
                    h('th', i === 0 ? { style: 'width:34px' } : null, x))));
            rows.forEach(r => {
                const cfg = r.config || {};
                const cb = h('input', { type: 'checkbox' });
                if (checked[r.runId]) cb.checked = true;
                cb.addEventListener('change', () => {
                    if (cb.checked) checked[r.runId] = true; else delete checked[r.runId];
                    renderActions(rows);
                });
                const stateTxt = r.phase === 'ENDED' ? '完整' : r.phase === 'FAILED' ? '人工结束/失败' : r.phase;
                tbl.appendChild(h('tr', null,
                    h('td', { onclick: ev => ev.stopPropagation() }, cb),
                    h('td', { style: 'font-weight:600' }, r.runId || '—'),
                    h('td', { class: 'wb-hint' },
                        (cfg.loadMode === 'external' ? '外部回灌' : (cfg.externalAir ? '外部回灌' : '人工指令 / 内部引气'))
                        + ' · ' + (cfg.pace === 'fast' ? '尽快计算' : '实时节奏')),
                    h('td', null, cfg.duration != null ? Number(cfg.duration).toFixed(3) + ' s' : '—'),
                    h('td', null, stateTxt + (r.hasExcel ? ' · Excel可导出' : r.hasResult ? ' · 结果已保存' : '')),
                    h('td', null,
                        h('button', {
                            class: 'wb-btn wb-btn-outline',
                            onclick: () => {
                                ctx.navigate('afo');
                                setTimeout(() => { if (window.__WB_AFO_OPEN__) window.__WB_AFO_OPEN__(r.runId); }, 60);
                            }
                        }, '查看(只读)'))));
            });
            listHolder.appendChild(tbl);
        }

        function renderActions(rows) {
            selHolder.innerHTML = '';
            const ids = Object.keys(checked).filter(id => rows.some(r => r.runId === id));
            if (!ids.length) { cmpHolder.innerHTML = ''; return; }
            const first = rows.find(r => r.runId === ids[0]);
            selHolder.appendChild(h('div', { class: 'wb-actions-row', style: 'margin-top:14px' },
                h('button', {
                    class: 'wb-btn wb-btn-primary',
                    onclick: () => {
                        ctx.navigate('afo');
                        setTimeout(() => { if (window.__WB_AFO_OPEN__) window.__WB_AFO_OPEN__(ids[0]); }, 60);
                    }
                }, '打开只读记录 ' + ids[0]),
                h('button', {
                    class: 'wb-btn wb-btn-outline' + (ids.length === 2 ? '' : ' disabled'),
                    title: ids.length === 2 ? '' : '勾选两份记录进行比较',
                    onclick: () => { if (ids.length === 2) compareSessions(ids[0], ids[1]); }
                }, '比较所选记录'),
                h('button', {
                    class: 'wb-btn wb-btn-outline',
                    onclick: () => {
                        ctx.navigate('afo');
                        setTimeout(() => { if (window.__WB_AFO_REUSE__) window.__WB_AFO_REUSE__(first); }, 60);
                    }
                }, '用该配置新建')));
        }

        /** 配置比较(09-08):配置项并排 + 可比性提示 + 同轴通道叠加(按实际仿真时间对齐,缺失留空不补零)。 */
        async function compareSessions(idA, idB) {
            cmpHolder.innerHTML = '';
            cmpHolder.appendChild(h('div', { class: 'wb-empty' }, '正在加载两份记录(result.json)...'));
            const load = async id => {
                const resp = await window.AppConfig.engineGet('projects/' + encodeURIComponent(pid)
                    + '/afo/sessions/' + encodeURIComponent(id) + '/result');
                return resp && (resp.success || resp.code === 200) ? resp.data : null;
            };
            try {
                const [ra, rb] = await Promise.all([load(idA), load(idB)]);
                cmpHolder.innerHTML = '';
                if (!ra || !rb) {
                    cmpHolder.appendChild(h('div', { class: 'wb-hint' }, '比较需要两份已保存的完整结果(result.json);未保存的运行先在原会话结束保存。'));
                    return;
                }
                const ca = ra.config || {}, cb2 = rb.config || {};
                const cmpRows = [
                    ['发动机编号', ca.engineId, cb2.engineId],
                    ['空气回灌', ca.externalAir ? '外部8路回灌' : '内部引气', cb2.externalAir ? '外部8路回灌' : '内部引气'],
                    ['负载方式', (AFO_LOAD.find(l => l[0] === ca.loadMode) || [])[1] || ca.loadMode, (AFO_LOAD.find(l => l[0] === cb2.loadMode) || [])[1] || cb2.loadMode],
                    ['Np挡位', ca.npRatio, cb2.npRatio],
                    ['时长 / 记录步长', ca.duration + ' s / ' + ca.recordStep + ' s', cb2.duration + ' s / ' + cb2.recordStep + ' s'],
                    ['运行节奏', ca.pace, cb2.pace]
                ];
                const tbl = h('table', { class: 'wb-table' },
                    h('tr', null, ['配置项', '记录A · ' + idA, '记录B · ' + idB].map(x => h('th', null, x))),
                    cmpRows.map(r => h('tr', null,
                        h('td', { style: 'color:#6b7280' }, r[0]),
                        h('td', null, String(r[1])),
                        h('td', null, String(r[2])))));
                cmpHolder.appendChild(h('div', { class: 'wb-section-title', style: 'margin:16px 0 8px' }, '比较两次仿真'));
                cmpHolder.appendChild(tbl);
                const sameInputs = String(ca.externalAir) === String(cb2.externalAir)
                    && String(ca.npRatio) === String(cb2.npRatio) && String(ca.loadMode) === String(cb2.loadMode);
                cmpHolder.appendChild(h('div', { class: sameInputs ? 'wb-infobar' : 'wb-infobar', style: 'border-left:4px solid ' + (sameInputs ? '#b88c23' : '#b91c1c') + ';background:#fff9e9;margin-top:10px' },
                    sameInputs
                        ? '⚠ 可比较相同输入下的配置影响。没有实测数据,不能仅凭两次仿真判定哪个模型更准确。'
                        : '⚠ 两次运行的输入或空气配置不同——先核对配置差异再下结论;不能把不同输入的输出差当成模型差异。'));

                // 通道叠加:共同通道按时间对齐;不同单位不共用纵轴(每组一张图)
                cmpHolder.appendChild(h('div', { class: 'wb-section-title', style: 'margin:16px 0 8px' }, '选择同量纲通道对比'));
                cmpHolder.appendChild(h('div', { class: 'wb-hint', style: 'margin-bottom:8px' },
                    'Np / Ng / 温度 / 流量 / 负载可分别叠加;不同单位不共用纵轴。按实际仿真时间对齐,不压缩成相同长度;缺失时间段留空,不补零。'));
                const CH = [
                    ['Np / rpm', AFO_GROUP.engine, AFO_E.Np], ['Ng / rpm', AFO_GROUP.engine, AFO_E.Ng],
                    ['Tt45 / K', AFO_GROUP.engine, AFO_E.Tt45], ['入口流量W2 / kg/s', AFO_GROUP.engine, AFO_E.W2],
                    ['PT负载功率 / kW', AFO_GROUP.load, 4], ['发动机燃油 / kg/s', AFO_GROUP.fuel_engine, 0]
                ];
                const sel = h('select', null, CH.map((c, i) => h('option', { value: String(i) }, c[0])));
                const chartBox = h('div', { style: 'margin-top:8px' });
                const draw = () => {
                    const [label, g, j] = CH[parseInt(sel.value, 10) || 0];
                    const mk = (r, name) => ({
                        name: name,
                        values: (r.values || []).map(row => { const cell = row && row[g]; return cell ? (cell[j] != null ? cell[j] : null) : null; })
                    });
                    const sa = mk(ra, idA), sb = mk(rb, idB);
                    const n = Math.max(sa.values.length, sb.values.length);
                    const labels = [];
                    const step = Math.max(1, Math.ceil(n / 8));
                    const tRef = (ra.time && rb.time && ra.time.length >= rb.time.length) ? ra.time : (rb.time || []);
                    for (let i = 0; i < n; i++) if (i % step === 0) labels.push(tRef && tRef[i] != null ? Number(tRef[i]).toFixed(1) : String(i));
                    chartBox.innerHTML = '';
                    chartBox.appendChild(chartLegend([{ ...sa, color: '#0e7490' }, { ...sb, color: '#b91c1c' }]));
                    chartBox.appendChild(lineChart({ series: [sa, sb], xLabels: labels, xTitle: '时间 / s' }));
                };
                sel.addEventListener('change', draw);
                cmpHolder.appendChild(h('div', { class: 'wb-field', style: 'max-width:360px' }, h('label', null, '对比通道'), sel));
                cmpHolder.appendChild(chartBox);
                draw();
                cmpHolder.appendChild(h('div', { class: 'wb-actions-row', style: 'margin-top:10px' },
                    h('button', {
                        class: 'wb-btn wb-btn-outline',
                        onclick: () => {
                            const blob = new Blob(['\ufeff' + JSON.stringify({ recordA: idA, configA: ca, recordB: idB, configB: cb2 }, null, 1)],
                                { type: 'application/json' });
                            const a = document.createElement('a');
                            a.href = URL.createObjectURL(blob);
                            a.download = 'afo_compare_' + idA + '_' + idB + '.json';
                            a.click();
                            URL.revokeObjectURL(a.href);
                        }
                    }, '导出对比配置')));
            } catch (e) {
                cmpHolder.innerHTML = '';
                cmpHolder.appendChild(h('div', { class: 'wb-hint' }, '比较失败:' + e.message));
            }
        }

        (async () => {
            try {
                const resp = await api();
                renderList(resp && (resp.success || resp.code === 200) && Array.isArray(resp.data) ? resp.data : []);
            } catch (e) {
                listHolder.innerHTML = '';
                listHolder.appendChild(h('div', { class: 'wb-empty' }, '仿真记录加载失败:' + e.message));
            }
        })();
        return wrap;
    }

    async function loadRunRecords(ctx, holder) {
        holder.innerHTML = '';
        try {
            // 运行维度统计:每次执行(稳态辨识/数据准备/UQ评估/输出预测)各一条,以运行标识runId为身份
            const [taskResp, uqResp, predResp] = await Promise.all([
                window.AppConfig.engineGet('projects/detail', { projectId: ctx.project.id }),
                window.AppConfig.engineGet('projects/' + encodeURIComponent(ctx.project.id) + '/uq-records').catch(() => null),
                window.AppConfig.engineGet('projects/' + encodeURIComponent(ctx.project.id) + '/predictions').catch(() => null)
            ]);
            const tasks = taskResp && (taskResp.success || taskResp.code === 200) && taskResp.data && Array.isArray(taskResp.data.tasks)
                ? taskResp.data.tasks : null;
            if (!tasks) throw new Error((taskResp && taskResp.message) || '接口返回异常');
            const uqList = uqResp && uqResp.success && Array.isArray(uqResp.data) ? uqResp.data : [];
            const predList = predResp && predResp.success && Array.isArray(predResp.data) ? predResp.data : [];
            if (!tasks.length && !uqList.length && !predList.length) {
                holder.appendChild(h('div', { class: 'wb-empty' }, '暂无运行记录——发起数据准备、辨识、评估或预测后在此查看。'));
                return;
            }
            const rows = [];
            tasks.forEach(t => rows.push({
                kind: '稳态辨识', runId: t.runId || '—', ref: t.name || t.id,
                status: t.status === 'FAILED' && t.errorKind === 'SAVE_FAILED' ? '保存失败'
                    : t.status === 'FAILED' && t.errorKind === 'NUMERIC_FAILED' ? '数值失败' : t.status,
                kindTag: t.status === 'FAILED' ? (t.errorKind === 'SAVE_FAILED' ? ['保存失败', 'amber'] : t.errorKind === 'NUMERIC_FAILED' ? ['数值失败', 'red'] : null) : null,
                startedAt: t.startedAt, finishedAt: t.finishedAt,
                note: (t.prepMessage ? '准备:' + t.prepMessage + (t.message ? '；' : '') : '') + (t.message || '—')
            }));
            uqList.forEach(r => rows.push({
                kind: 'UQ评估', runId: r.runId || r.id, ref: '方法' + (r.method || '—') + (r.particleCount ? ' · ' + r.particleCount + '粒子' : ''),
                status: r.status || '—', kindTag: null,
                startedAt: r.startedAt, finishedAt: r.finishedAt,
                note: r.message || '—'
            }));
            predList.forEach(r => rows.push({
                kind: '输出预测', runId: r.runId || r.id, ref: r.modelName || '—',
                status: r.status || '—', kindTag: null,
                startedAt: r.createdAt, finishedAt: r.finishedAt,
                note: (r.message || '—') + (Array.isArray(r.conditions)
                    ? ' · 工况 ' + r.conditions.map(c => c.id + (c.status === 'FAILED' ? '(失败)' : '')).join(' ') : '')
            }));
            rows.sort((a, b) => (b.startedAt || 0) - (a.startedAt || 0));
            holder.appendChild(h('div', { class: 'wb-hint', style: 'margin-bottom:8px' },
                '以运行(runId)为维度:每次辨识、评估、预测执行各一条;同一任务多次重跑按运行标识区分,历史只读。'));
            holder.appendChild(h('table', { class: 'wb-table' },
                h('tr', null, ['类型', '运行标识', '关联对象', '状态', '开始时间', '结束时间', '耗时', '说明'].map(t => h('th', null, t))),
                rows.map(rw => {
                    const st = RUN_STATUS[rw.status] || [rw.status || '—', 'gray'];
                    const dur = rw.startedAt && rw.finishedAt ? fmtSpan(rw.finishedAt - rw.startedAt) : '—';
                    return h('tr', null,
                        h('td', { style: 'font-weight:600;color:#111827' }, rw.kind),
                        h('td', { class: 'wb-hint' }, rw.runId),
                        h('td', null, rw.ref),
                        h('td', null, rw.kindTag
                            ? [h('span', { style: 'display:inline-flex;margin-right:6px' }, statusTag(rw.kindTag[0], rw.kindTag[1])), statusTag(st[0], st[1])]
                            : statusTag(st[0], st[1])),
                        h('td', { class: 'wb-hint' }, rw.startedAt ? new Date(rw.startedAt).toLocaleString() : '—'),
                        h('td', { class: 'wb-hint' }, rw.finishedAt ? new Date(rw.finishedAt).toLocaleString() : '—'),
                        h('td', { class: 'wb-hint' }, dur),
                        h('td', { class: 'wb-hint', style: 'word-break:break-all;max-width:360px' }, rw.note));
                })));
        } catch (e) {
            holder.appendChild(h('div', { class: 'wb-empty' }, '运行记录加载失败:' + e.message));
        }
    }

    function fmtSpan(ms) {
        const s = Math.max(0, Math.round(ms / 1000));
        const m = Math.floor(s / 60);
        return (m ? m + '分' : '') + (s % 60) + '秒';
    }
    pages['modeling.records'] = (ctx) => recordsPage(ctx, 'run');

    /* ===== 数字试车台 ===== */
    pages['testbench.overview'] = (ctx) => {
        const pid = encodeURIComponent(ctx.project.id || '');
        const sessionsHolder = h('div', null, h('div', { class: 'wb-empty' }, '正在加载仿真记录...'));
        const wrap = h('div', null, pageHeader('项目概况', ctx.project.name + ' / 系统联合仿真'));
        wrap.appendChild(h('div', { class: 'wb-section', style: 'display:grid;grid-template-columns:1fr 1fr;gap:20px' },
            h('div', { class: 'wb-card' },
                h('div', { class: 'wb-section-title' }, '全模式人工操纵仿真'),
                h('div', { class: 'wb-hint', style: 'margin:8px 0 14px' }, '三位置油门 · 五挡Np · 负载互斥 · 命令状态机 · 快照恢复(F-11)'),
                h('span', { class: 'wb-tag wb-tag-teal' }, '已接入(sht_fullmode_session会话合同)'),
                h('div', { style: 'margin-top:14px' }, h('button', {
                    class: 'wb-btn wb-btn-primary',
                    onclick: () => ctx.navigate('fullmode')
                }, '进入'))),
            h('div', { class: 'wb-card' },
                h('div', { class: 'wb-section-title' }, '起动停车建模(含设计点配置)'),
                h('div', { class: 'wb-hint', style: 'margin:8px 0 14px' }, '模型准备→设计点(F-09 solve/commit)→特性图→物理热参数→校核链→模型成果(F-10 七页签)'),
                h('span', { class: 'wb-tag wb-tag-teal' }, '已接入(design_point + startstop 任务合同)'),
                h('div', { style: 'margin-top:14px' }, h('button', {
                    class: 'wb-btn wb-btn-primary',
                    onclick: () => ctx.navigate('startstop')
                }, '进入'))),
            h('div', { class: 'wb-card' },
                h('div', { class: 'wb-section-title' }, '多系统联合仿真'),
                h('div', { class: 'wb-hint', style: 'margin:8px 0 14px' }, 'AFO_V_2 · Dll_Control_AFO_V8_5_R2019b · 39 组 247 通道 + 4 回退标志(F-12)'),
                h('span', { class: 'wb-tag wb-tag-teal' }, '已接入(sht_afo_session会话合同)'),
                h('div', { style: 'margin-top:14px' }, h('button', {
                    class: 'wb-btn wb-btn-primary',
                    onclick: () => ctx.navigate('afo')
                }, '进入')))));
        wrap.appendChild(h('div', { class: 'wb-section' },
            h('div', { class: 'wb-section-head' },
                h('div', { class: 'wb-section-title' }, '最近仿真记录'),
                h('button', { class: 'wb-btn wb-btn-outline', onclick: () => ctx.navigate('records') }, '全部记录')),
            sessionsHolder));
        window.AppConfig.engineGet('projects/' + pid + '/afo/sessions')
            .then(resp => {
                const rows = resp && (resp.success || resp.code === 200) && Array.isArray(resp.data) ? resp.data : [];
                sessionsHolder.innerHTML = '';
                if (!rows.length) {
                    sessionsHolder.appendChild(h('div', { class: 'wb-empty' },
                        '暂无仿真记录——进入"多系统联合仿真"发起准备并运行后在此留档。'));
                    return;
                }
                sessionsHolder.appendChild(h('table', { class: 'wb-table' },
                    h('tr', null, ['运行', '配置', '状态', '创建时间'].map(x => h('th', null, x))),
                    rows.slice(0, 5).map(r => {
                        const c = r.config || {};
                        return h('tr', { class: 'clickable', onclick: () => ctx.navigate('afo') },
                            h('td', { style: 'font-weight:600' }, r.runId || '—'),
                            h('td', { class: 'wb-hint' },
                                (c.externalAir ? '外部回灌' : '内部引气') + ' · ' + (c.loadMode || '—')
                                + ' · ' + (c.duration != null ? c.duration + ' s' : '—')),
                            h('td', null, r.phase === 'ENDED' ? '完整' : r.phase === 'FAILED' ? '失败' : (r.phase || '—')),
                            h('td', { class: 'wb-hint' }, r.createdAt ? new Date(r.createdAt).toLocaleString() : '—'));
                    })));
            })
            .catch(() => {
                sessionsHolder.innerHTML = '';
                sessionsHolder.appendChild(h('div', { class: 'wb-empty' }, '仿真记录加载失败'));
            });
        return wrap;
    };

    function placeholderPage(title, subtitle, heading, lines) {
        const wrap = h('div', null, pageHeader(title, subtitle));
        wrap.appendChild(h('div', { class: 'wb-placeholder' },
            h('div', { class: 'wb-ph-icon', html: ICONS.ph }),
            h('h3', null, heading),
            h('p', null, lines)));
        return wrap;
    }
    /* ===== 全模式仿真(G8,UI-R101): 三页签 仿真准备/操纵与监视/本次结果 ===== */
    pages['testbench.fullmode'] = (ctx) => {
        const pid = encodeURIComponent(ctx.project.id || '');
        const api = p => window.AppConfig.engineGet('projects/' + pid + '/testbench/fullmode' + p);
        const apiPost = (p, body) => window.AppConfig.enginePost('projects/' + pid + '/testbench/fullmode' + p, body || {});
        const S = window.__WB_FM__ = window.__WB_FM__ || {
            phase: 'IDLE', live: null, message: '', tab: 'prep',
            cfg: { modelMode: 0, initialKind: 'stopped', loadMode: 'dual_collective',
                thermalEnabled: true, density: '1.225', powerW: 0, mkpNm: 0,
                mainPitchDeg: 6, tailPitchDeg: 5, npGear: '0.9', throttle: 'idle',
                loadDraft: '0' }
        };
        const wrap = h('div', null,
            h('div', { style: 'margin-bottom:4px;display:flex;justify-content:space-between;align-items:baseline' },
                h('div', null,
                    h('div', { class: 'wb-page-title', style: 'font-size:20px;margin-bottom:2px' }, '全模式仿真'),
                    h('div', { class: 'wb-page-sub' }, '人工操纵与连续观测 · 0.025s二阶欧拉完整步 · 记录10Hz')),
                h('div', { class: 'wb-hint', style: 'margin:0' }, 'F-11 · sht_fullmode_session · 界面非硬实时试验控制系统')));
        const tabBar = h('div', { class: 'wb-tabs', style: 'margin-bottom:12px' });
        const body = h('div', null);
        wrap.appendChild(tabBar);
        wrap.appendChild(body);
        const TABS = [['prep', '仿真准备'], ['ops', '操纵与监视'], ['result', '本次结果']];

        function toast(msg, kind) { if (window.Workbench && window.Workbench.toast) window.Workbench.toast(msg, kind || 'info'); }
        const canOps = () => ['READY', 'RUNNING', 'PAUSED'].includes(S.phase);

        function paintTabs() {
            tabBar.innerHTML = '';
            TABS.forEach(([k, label]) => tabBar.appendChild(h('div', {
                class: 'wb-tab' + (S.tab === k ? ' active' : '') + (k !== 'prep' && !canOps() && S.phase !== 'ENDED' && S.phase !== 'FAILED' ? ' disabled' : ''),
                onclick: () => {
                    if (k !== 'prep' && !canOps() && S.phase !== 'ENDED' && S.phase !== 'FAILED') { toast('请先完成仿真准备', 'info'); return; }
                    S.tab = k; renderBody();
                }
            }, label)));
        }

        function cmd(kind, value, note) {
            apiPost('/command', { kind, value })
                .then(r => { if (r && r.code === 200) toast(note || ('命令已下发:' + kind), 'success'); else toast((r && r.message) || '命令失败', 'error'); })
                .catch(e => toast('命令失败:' + e.message, 'error'));
        }

        /* ---------- 页签一: 仿真准备(08-01/02/29) ---------- */
        function prepTab() {
            const mmSel = h('select', null,
                h('option', { value: '0', selected: S.cfg.modelMode === 0 ? '' : null }, '三部件模型(model0)'),
                h('option', { value: '1', selected: S.cfg.modelMode === 1 ? '' : null }, '六部件模型(model1)'));
            const ikSel = h('select', null, ['stopped', 'idle', 'cruise', 'maximum'].map(v =>
                h('option', { value: v, selected: S.cfg.initialKind === v ? '' : null },
                    { stopped: '停止(冷态)', idle: '慢车', cruise: '巡航', maximum: '最大(非已验证最大功率)' }[v])));
            const lmSel = h('select', null, ['power', 'mkp', 'dual_collective'].map(v =>
                h('option', { value: v, selected: S.cfg.loadMode === v ? '' : null },
                    { power: '直接轴功率', mkp: '直接Mkp扭矩', dual_collective: '主桨/尾桨总距角' }[v])));
            const densityInput = h('input', { value: S.cfg.density });
            const thermalChk = h('input', { type: 'checkbox', checked: S.cfg.thermalEnabled ? '' : null });
            const preparing = S.phase === 'PREPARING';
            const card = h('div', { class: 'wb-card', style: 'max-width:860px' },
                h('div', { class: 'wb-section-title', style: 'margin-bottom:6px' }, '选择模型和初态'),
                h('div', { class: 'wb-hint', style: 'margin:0 0 14px' },
                    '初态可为停止、慢车、巡航或受支持的指定状态;设计点、最大连续功率与限时状态是不同概念。正恒功率/正恒扭矩从静止直接起动已取消,保留非零初态操作;双总距模式支持静止起停。'),
                h('div', { class: 'wb-form-grid', style: 'grid-template-columns:1fr 1fr' },
                    h('div', { class: 'wb-field' }, h('label', null, '源模型'), mmSel),
                    h('div', { class: 'wb-field' }, h('label', null, '初态'), ikSel),
                    h('div', { class: 'wb-field' }, h('label', null, '负载模式(三类互斥,运行中不切换)'), lmSel),
                    h('div', { class: 'wb-field' }, h('label', null, '环境密度 / kg·m-3'), densityInput),
                    h('div', { class: 'wb-field', style: 'grid-column:1/-1' },
                        h('div', { style: 'display:flex;align-items:center;gap:8px' }, thermalChk,
                            h('span', null, '启用热模型(Visser16热链;热关闭与未计算分开展示)')))),
                h('div', { class: 'wb-actions-row', style: 'margin-top:12px' },
                    h('button', {
                        class: 'wb-btn wb-btn-primary' + (preparing ? ' disabled' : ''),
                        onclick: () => {
                            if (preparing) return;
                            S.cfg.modelMode = parseInt(mmSel.value, 10);
                            S.cfg.initialKind = ikSel.value;
                            S.cfg.loadMode = lmSel.value;
                            S.cfg.thermalEnabled = thermalChk.checked;
                            S.cfg.density = densityInput.value;
                            doPrepare();
                        }
                    }, preparing ? '准备中(校验身份/初始化模型)...' : '发起仿真准备')));
            if (S.phase === 'READY' || S.phase === 'RUNNING' || S.phase === 'PAUSED') {
                const live = S.live || {};
                card.appendChild(h('div', { class: 'wb-section-title', style: 'margin:16px 0 8px' }, '核对已准备初态'));
                const kv = h('div', { class: 'wb-kv', style: 'max-width:1180px' });
                [['会话', live.runId || '—'], ['mode', live.mode != null ? String(live.mode) : String(S.cfg.modelMode)],
                 ['初态', S.cfg.initialKind], ['负载模式', S.cfg.loadMode],
                 ['热模型', S.cfg.thermalEnabled ? '启用' : '关闭'], ['lifecycle', live.lifecycle || 'prepared']]
                    .forEach(([k, v]) => { kv.appendChild(h('div', { class: 'k' }, k)); kv.appendChild(h('div', { class: 'v' }, v)); });
                card.appendChild(kv);
                card.appendChild(h('div', { class: 'wb-actions-row', style: 'margin-top:12px' },
                    h('button', { class: 'wb-btn wb-btn-primary', onclick: () => { S.tab = 'ops'; renderBody(); } }, '→ 操纵与监视')));
            }
            return card;
        }

        function doPrepare() {
            const user = {
                modelMode: S.cfg.modelMode,
                fullmode: {
                    loadMode: S.cfg.loadMode,
                    initialKind: S.cfg.initialKind,
                    thermalEnabled: !!S.cfg.thermalEnabled,
                    densityKgPerM3: parseFloat(S.cfg.density) || 1.225,
                    load: { powerW: Number(S.cfg.powerW) || 0, mkpNm: Number(S.cfg.mkpNm) || 0,
                        mainPitchDeg: Number(S.cfg.mainPitchDeg) || 6, tailPitchDeg: Number(S.cfg.tailPitchDeg) || 5 },
                    outputDirectory: ''
                }
            };
            S.phase = 'PREPARING';
            renderBody();
            apiPost('/prepare', user)
                .then(r => { if (!(r && r.code === 200)) { toast((r && r.message) || '准备发起失败', 'error'); S.phase = 'IDLE'; renderBody(); } })
                .catch(e => { toast('准备发起失败:' + e.message, 'error'); S.phase = 'IDLE'; renderBody(); });
        }

        /* ---------- 页签二: 操纵与监视(08-03~08-20) ---------- */
        function opsTab() {
            const live = S.live || {};
            const t = typeof live.time === 'number' ? live.time : 0;
            const isRun = S.phase === 'RUNNING';
            const wrap = h('div', null);

            const phaseLabel = isRun ? ['▶ 计算运行中', 'teal'] : S.phase === 'PAUSED' ? ['已暂停(保持状态)', 'amber']
                : S.phase === 'READY' ? ['已就绪 · 未推进', 'teal'] : S.phase === 'ENDED' ? ['已结束', 'gray'] : ['失败', 'red'];
            const bar = h('div', { class: 'wb-infobar', style: 'display:flex;align-items:center;gap:16px;padding:10px 16px;margin-bottom:12px' },
                h('span', { class: 'wb-tag wb-tag-' + phaseLabel[1] }, phaseLabel[0]),
                h('span', { style: 'font-weight:700;font-size:16px' }, Number(t).toFixed(3) + ' s'),
                h('span', { class: 'wb-hint', style: 'margin:0' }, '仿真时间'),
                h('span', { class: 'wb-hint', style: 'margin:0' }, '物理阶段: ' + (lifecycleCn(live.lifecycle) || '—')),
                h('span', { class: 'wb-hint', style: 'margin:0' }, live.throttle ? ('油门: ' + live.throttle) : ''),
                h('div', { class: 'wb-spacer' }));
            if (isRun || S.phase === 'PAUSED') {
                bar.appendChild(h('button', { class: 'wb-btn wb-btn-outline', onclick: () => cmd(isRun ? 'pause' : 'resume') }, isRun ? '暂停' : '继续'));
                bar.appendChild(h('button', { class: 'wb-btn wb-btn-outline', onclick: () => { if (confirm('结束本次计算?将执行normal_stop并保存结果。')) cmd('stop'); } }, '结束计算'));
                bar.appendChild(h('button', { class: 'wb-btn', style: 'background:#c0392b;color:#fff;border-color:#c0392b',
                    onclick: () => { if (confirm('紧急断油(emergency_cutoff)?断油保持锁存,不能被一般操作覆盖。')) cmd('emergency_cutoff'); } }, '紧急断油'));
            }
            wrap.appendChild(bar);

            wrap.appendChild(bigGrid(live));

            wrap.appendChild(h('div', { class: 'wb-infobar', style: 'margin:10px 0' },
                S.phase === 'READY' ? '会话已就绪;油门位置与起动命令分开:置慢车不自动起动,置运行不绕过暖机;Ng稳定暖机60秒后转入Np控制。'
                    : S.phase === 'PAUSED' ? '暂停中:发动机处于运行快照;暂停时发出的命令在恢复前未必已改变物理状态,以回执为准。'
                    : S.phase === 'ENDED' ? '已结束;前往「本次结果」查看输出、全通道、热状态、命令与配置五类内容。'
                    : '运行中:命令状态机为 编辑草稿→已提交→已接收→已施加/已拒绝;挡位命令被接收不代表转速已稳定。'));

            if (S.phase === 'ENDED' || S.phase === 'FAILED') {
                wrap.appendChild(h('div', { class: 'wb-actions-row' },
                    h('button', { class: 'wb-btn wb-btn-primary', onclick: () => { S.tab = 'result'; renderBody(); } }, '查看本次结果')));
                return wrap;
            }

            const grid = h('div', { style: 'display:grid;grid-template-columns:360px 1fr;gap:20px' });
            const opsCol = h('div', { class: 'wb-card' });
            opsCol.appendChild(h('div', { class: 'wb-section-title', style: 'margin-bottom:8px' }, '试车操纵'));
            opsCol.appendChild(h('div', { class: 'wb-hint', style: 'margin-bottom:6px' },
                '油门杆 (生效: ' + (live.throttle || '未施加') + ')'));
            const throttleRow = h('div', { style: 'display:grid;grid-template-columns:repeat(3,1fr);gap:8px;margin-bottom:8px' });
            [['cut', '切断'], ['idle', '慢车'], ['run', '运行']].forEach(([v, label]) =>
                throttleRow.appendChild(h('button', { class: 'wb-btn wb-btn-outline', onclick: () => cmd('select_throttle', v, '油门→' + label) }, label)));
            opsCol.appendChild(throttleRow);
            const cmdGrid = h('div', { style: 'display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-bottom:12px' });
            cmdGrid.appendChild(h('button', { class: 'wb-btn wb-btn-primary', onclick: () => cmd('start', null, '起动命令已提交') }, '▶ 起动'));
            cmdGrid.appendChild(h('button', { class: 'wb-btn wb-btn-outline', onclick: () => cmd('cold_blow') }, '冷吹'));
            cmdGrid.appendChild(h('button', { class: 'wb-btn wb-btn-outline', onclick: () => cmd('exit_cold_blow') }, '结束吹转'));
            cmdGrid.appendChild(h('button', { class: 'wb-btn wb-btn-outline', onclick: () => cmd('abort_start') }, '中止起动'));
            cmdGrid.appendChild(h('button', { class: 'wb-btn wb-btn-outline', onclick: () => { if (confirm('正常停车:先执行规定冷却阶段及Np条件,再断油。继续?')) cmd('normal_stop'); } }, '正常停车'));
            cmdGrid.appendChild(h('button', { class: 'wb-btn wb-btn-outline', onclick: () => cmd('acknowledge_cutoff') }, '确认断油锁存'));
            opsCol.appendChild(cmdGrid);
            opsCol.appendChild(h('div', { class: 'wb-hint', style: 'margin-bottom:6px' },
                'Np运行挡位 (设计点转速的80/90/95/100/105%;被接收≠已稳定)'));
            const npRow = h('div', { style: 'display:grid;grid-template-columns:repeat(5,1fr);gap:6px;margin-bottom:6px' });
            ['0.8', '0.9', '0.95', '1', '1.05'].forEach(v =>
                npRow.appendChild(h('button', { class: 'wb-btn wb-btn-outline', onclick: () => { S.cfg.npGear = v; cmd('set_np_gear', parseFloat(v), 'Np挡位→' + Math.round(parseFloat(v) * 100) + '%'); renderBody(); } },
                    Math.round(parseFloat(v) * 100) + '%')));
            opsCol.appendChild(npRow);
            opsCol.appendChild(h('div', { class: 'wb-hint', style: 'margin:0 0 10px' },
                '预选: ' + Math.round(parseFloat(S.cfg.npGear || '0.9') * 100) + '% (待施加)'));
            opsCol.appendChild(h('button', { class: 'wb-btn wb-btn-outline', style: 'width:100%;margin-bottom:14px',
                onclick: () => cmd('set_np_gear', parseFloat(S.cfg.npGear || '0.9'), '已施加Np挡位') }, '✓ 施加转速挡位'));
            opsCol.appendChild(h('div', { class: 'wb-hint', style: 'margin-bottom:6px' }, '负载草稿 (' + ({ power: 'PT功率/W', mkp: 'Mkp扭矩/N·m', dual_collective: '主桨总距角/deg' }[S.cfg.loadMode] || '—') + ')'));
            const loadInput = h('input', { value: S.cfg.loadDraft });
            loadInput.addEventListener('change', () => { S.cfg.loadDraft = loadInput.value; });
            opsCol.appendChild(h('div', { style: 'display:flex;gap:8px' },
                loadInput,
                h('button', { class: 'wb-btn wb-btn-outline', onclick: () => {
                    const v = parseFloat(S.cfg.loadDraft);
                    if (isNaN(v)) { toast('负载草稿须为数值', 'error'); return; }
                    cmd('apply_load', v, '负载命令已提交');
                } }, '✓ 施加负载')));
            grid.appendChild(opsCol);

            const monCol = h('div', null);
            monCol.appendChild(h('div', { class: 'wb-section-title', style: 'margin-bottom:8px' }, '实时监视'));
            monCol.appendChild(h('div', { class: 'wb-hint', style: 'margin-bottom:10px' },
                '运行预选 ' + Math.round(parseFloat(S.cfg.npGear || '0.9') * 100) + '% · 主监视: Np、Ng、燃油、负载、实际输出功率与Tt45;气路有效标志与当前步是否真正计算温度分开展示。'));
            const kv = h('div', { class: 'wb-kv', style: 'max-width:1180px' });
            const known = ['runId', 'mode', 'lifecycle', 'time', 'throttle', 'npGear', 'stopReason', 'wallSeconds'];
            let shown = 0;
            Object.keys(live).forEach(k => {
                if (known.includes(k)) return;
                const v = live[k];
                if (v == null || typeof v === 'object') return;
                kv.appendChild(h('div', { class: 'k' }, k));
                kv.appendChild(h('div', { class: 'v' }, String(v)));
                shown++;
            });
            if (!shown) kv.appendChild(h('div', { class: 'v', style: 'grid-column:1/-1' },
                '等待推进块间状态刷新(每块约2s仿真时间更新一次;实时通道字段随程序status提供)。'));
            monCol.appendChild(kv);

            const receipts = live.receipts || live.events || [];
            monCol.appendChild(h('div', { class: 'wb-section-title', style: 'margin:16px 0 8px' }, '操纵记录'));
            if (Array.isArray(receipts) && receipts.length) {
                const tbl = h('table', { class: 'wb-table' },
                    h('tr', null, ['时刻/s', '操作', '回执', '当前结果'].map(x => h('th', null, x))));
                receipts.slice(-12).forEach(rc => tbl.appendChild(h('tr', null,
                    h('td', null, str(rc.time != null ? rc.time : rc.simTime)),
                    h('td', null, str(rc.action || rc.kind)),
                    h('td', null, str(rc.status || rc.receipt)),
                    h('td', { class: 'wb-hint' }, str(rc.note || rc.result || '')))));
                monCol.appendChild(tbl);
            } else {
                monCol.appendChild(h('div', { class: 'wb-hint' }, '尚无操纵记录;每次命令保存编号、值、单位、提交与生效时刻及拒绝原因。'));
            }
            grid.appendChild(monCol);
            wrap.appendChild(grid);
            return wrap;
        }

        function lifecycleCn(lc) {
            return { prepared: '已准备(停转)', running: '运行', paused: '暂停', terminated: '已终止' }[lc] || lc || '';
        }
        function str(v) { return v == null ? '—' : String(v); }

        function bigGrid(live) {
            const v = live.values || {};
            const pick = k => (v[k] != null ? v[k] : '--');
            const cells = [
                ['Np', pick('Np'), '%设计点 · 模拟测量'], ['Ng', pick('Ng'), 'rpm · 模拟测量'],
                ['Tt45', pick('Tt45'), 'K · 未求值时--'], ['Mkp', pick('Mkp'), 'N·m · 模拟测量'],
                ['PT负载功率', pick('PTpower'), 'kW · 模型计算'], ['计量燃油', pick('Wf'), 'kg/s · 执行器输出']
            ];
            const g = h('div', { style: 'display:grid;grid-template-columns:repeat(6,1fr);gap:14px;margin-bottom:6px' });
            cells.forEach(([k, val, unit]) => g.appendChild(h('div', null,
                h('div', { class: 'wb-hint', style: 'margin:0 0 2px' }, k),
                h('div', { style: 'font-size:22px;font-weight:700' }, String(val)),
                h('div', { class: 'wb-hint', style: 'margin:0;font-size:11px' }, unit))));
            return g;
        }

        /* ---------- 页签三: 本次结果(08-21~25) ---------- */
        function resultTab() {
            const wrap = h('div', null);
            const runId = S.live && S.live.runId;
            wrap.appendChild(h('div', { class: 'wb-infobar', style: 'margin-bottom:12px' },
                S.phase === 'ENDED' ? '计算已结束;三种保存物用途不同:结果Excel用于数据查看,快照MAT与匹配身份用于恢复,manifest记录清单。'
                    : '结束并保存后开放五类内容;现行ResultView读取MAT,Excel单文件不能恢复会话。'));
            const acts = h('div', { class: 'wb-actions-row', style: 'margin-bottom:14px' });
            if (S.phase === 'ENDED' && runId) {
                acts.appendChild(h('button', {
                    class: 'wb-btn wb-btn-primary',
                    onclick: () => {
                        const cfg0 = window.AppConfig;
                        window.open(cfg0.api.baseURL + '/api/engine/projects/' + pid
                            + '/testbench/fullmode/sessions/' + encodeURIComponent(runId)
                            + '/excel?token=' + encodeURIComponent(cfg0.getToken() || ''), '_blank');
                    }
                }, '导出结果Excel'));
            }
            if (['ENDED', 'FAILED'].includes(S.phase)) {
                acts.appendChild(h('button', {
                    class: 'wb-btn wb-btn-outline',
                    onclick: () => apiPost('/close').then(() => { S.phase = 'IDLE'; S.live = null; S.tab = 'prep'; renderBody(); })
                }, '新建运行(关闭本会话)'));
            }
            wrap.appendChild(acts);
            const kv = h('div', { class: 'wb-kv', style: 'max-width:1180px' });
            const live = S.live || {};
            [['会话', runId || '—'], ['相位', S.phase], ['结束说明', S.message || '—'],
             ['实际时间', live.time != null ? Number(live.time).toFixed(3) + ' s' : '—'],
             ['停止原因', live.stopReason || '—']]
                .forEach(([k, v]) => { kv.appendChild(h('div', { class: 'k' }, k)); kv.appendChild(h('div', { class: 'v' }, String(v))); });
            wrap.appendChild(kv);
            wrap.appendChild(h('div', { class: 'wb-section-title', style: 'margin:16px 0 8px' }, '五类内容'));
            wrap.appendChild(h('table', { class: 'wb-table' },
                h('tr', null, ['内容', '说明'].map(x => h('th', null, x))),
                h('tr', null, h('td', null, '输出历程与有效范围'), h('td', { class: 'wb-hint' }, '主通道曲线与有效区间随结果Excel提供')),
                h('tr', null, h('td', null, '所有记录通道及未提供量'), h('td', { class: 'wb-hint' }, '全通道列表;未提供量如实标注')),
                h('tr', null, h('td', null, '热状态'), h('td', { class: 'wb-hint' }, '按实际构型查看;热关闭与未计算分开')),
                h('tr', null, h('td', null, '操纵与告警'), h('td', { class: 'wb-hint' }, '命令回执、告警、限油与自动停车可追溯')),
                h('tr', null, h('td', null, '配置与文件'), h('td', { class: 'wb-hint' }, '实际配置、时间与三种保存物清单(manifest)'))));
            return wrap;
        }

        function renderBody() {
            paintTabs();
            body.innerHTML = '';
            if (S.tab === 'prep') body.appendChild(prepTab());
            else if (S.tab === 'ops') body.appendChild(opsTab());
            else body.appendChild(resultTab());
        }

        if (window.__WB_FM_TIMER__) clearInterval(window.__WB_FM_TIMER__);
        window.__WB_FM_TIMER__ = setInterval(() => {
            if (document.hidden) return;
            if (['PREPARING', 'READY', 'RUNNING', 'PAUSED'].includes(S.phase)) {
                window.__WB_ENGINE_POLL_UNTIL__ = Date.now() + 40000;
                api('/status').then(r => {
                    if (r && r.code === 200 && r.data) {
                        S.phase = r.data.phase || S.phase;
                        S.live = r.data.live || S.live;
                        S.message = r.data.message || '';
                        renderBody();
                    }
                }).catch(() => { });
            }
        }, 2000);
        renderBody();
        api('/status').then(r => {
            if (r && r.code === 200 && r.data && r.data.phase && r.data.phase !== 'IDLE') {
                S.phase = r.data.phase; S.live = r.data.live; S.message = r.data.message;
                if (canOps() || ['ENDED', 'FAILED'].includes(S.phase)) S.tab = 'ops';
                renderBody();
            }
        }).catch(() => { });
        return wrap;
    };

    /* ===== 起动停车建模(G7,UI-R111): 七页签 =====
     * 模型准备 / 设计点配置 / 特性图 / 物理与热参数 / 校核执行 / 校核结果 / 模型成果
     * 后端: design_point(sht_design_point_task solve/commit) + startstop(sht_startstop_modeling_task 阶段链) */
    pages['testbench.startstop'] = (ctx) => {
        const pid = encodeURIComponent(ctx.project.id || '');
        const api = p => window.AppConfig.engineGet('projects/' + pid + '/testbench' + p);
        const apiPost = (p, body) => window.AppConfig.enginePost('projects/' + pid + '/testbench' + p, body || {});
        const S = window.__WB_SS__ = window.__WB_SS__ || {
            tab: 'prepare', dpTaskId: null, ssTaskId: null, modelMode: 0,
            design: { NpRpm: '20900', NgRpm: '38000', loadPowerW: '2176600', targetTt4K: '1620', nozzleAreaM2: '0.10573' }
        };
        const wrap = h('div', null,
            h('div', { style: 'margin-bottom:4px' },
                h('div', { class: 'wb-page-title', style: 'font-size:20px;margin-bottom:2px' }, '起动停车建模'),
                h('div', { class: 'wb-page-sub' }, (ctx.project.engineId || '—') + ' / 设计点配置后可单独完成;源模型拓扑/地图/MDL/DLL/设计点与热资产身份来自所选模型')),
            h('div', { class: 'wb-tabs', style: 'margin-bottom:12px' }));

        const TABS = [['prepare', '模型准备'], ['design', '设计点配置'], ['maps', '特性图'], ['physics', '物理与热参数'], ['exec', '校核执行'], ['verif', '校核结果'], ['assets', '模型成果']];
        const tabBar = wrap.querySelector('.wb-tabs');
        const body = h('div', null);
        wrap.appendChild(body);

        function paintTabs() {
            tabBar.innerHTML = '';
            TABS.forEach(([k, label]) => tabBar.appendChild(h('div', {
                class: 'wb-tab' + (S.tab === k ? ' active' : ''),
                onclick: () => { S.tab = k; renderBody(); }
            }, label)));
        }

        /* ---- 模型准备(07-01): 从明确的源模型开始 + 本次目的 + 来源检查 ---- */
        function prepareTab() {
            const mmSel = h('select', null,
                h('option', { value: '0', selected: S.modelMode === 0 ? '' : null }, 'B-001 / 三部件'),
                h('option', { value: '1', selected: S.modelMode === 1 ? '' : null }, 'B-001 / 六部件'));
            const purpose = [
                ['只做设计点配置', '求解、备份写入、模式2简单测试', '保存设计点成果'],
                ['设计点配置与起停建模', '先完成设计点,再扩图与起停校核', '保存起停模型包'],
                ['已有设计点配置,继续起停建模', '读取匹配设计记录并进行复现检查', '不无依据重复求解']
            ];
            return h('div', null,
                h('div', { class: 'wb-section-title', style: 'margin:4px 0 8px' }, '从明确的源模型开始'),
                h('div', { class: 'wb-form-grid', style: 'grid-template-columns:1fr 1fr;max-width:1180px;margin-bottom:14px' },
                    h('div', { class: 'wb-field' }, h('label', null, '建模任务'),
                        h('input', { readonly: '', value: (ctx.project.engineId || 'E-001') + ' / 设计点与低速模型完善' })),
                    h('div', { class: 'wb-field' }, h('label', null, '源模型'), mmSel)),
                h('table', { class: 'wb-table' },
                    h('tr', null, ['本次目的', '包含的工作', '完成后'].map(x => h('th', null, x))),
                    purpose.map((r0, i) => h('tr', i === 1 ? { style: 'background:#eef7f5' } : null,
                        h('td', null, r0[0]), h('td', { class: 'wb-hint' }, r0[1]), h('td', null, r0[2])))),
                h('div', { class: 'wb-section-title', style: 'margin:16px 0 8px' }, '来源检查'),
                h('table', { class: 'wb-table' },
                    h('tr', null, ['来源检查', '实际文件', '状态'].map(x => h('th', null, x))),
                    h('tr', null,
                        h('td', null, 'MDL与MAP'),
                        h('td', { class: 'wb-hint' }, '按所选版本读取,不按最新文件查找(Turboshaft-TS*.mdl + HPC02/HPT02/LPT02.MAP)'),
                        h('td', null, '待检查')),
                    h('tr', null,
                        h('td', null, 'DLL与加载助手'),
                        h('td', { class: 'wb-hint' }, 'GTESS.dll/头文件随程序目录;同一版本原算法'),
                        h('td', null, '待检查')),
                    h('tr', null,
                        h('td', null, '设计状态 / 热资产(可选)'),
                        h('td', { class: 'wb-hint' }, 'V1/V2各自设计解与三类热MAT;不提供时保持原默认'),
                        h('td', null, '待检查'))),
                h('div', { class: 'wb-hint', style: 'margin:10px 0 0' },
                    '设计点复现、低速矩阵、连续起停分别记录;原V1/V2入口保留;新入口写MDL前必须备份;两个独立模型工程不互为运行前置。'),
                h('div', { class: 'wb-actions-row', style: 'margin-top:12px' },
                    h('button', { class: 'wb-btn wb-btn-outline', onclick: () => ctx.navigate('overview') }, '← 返回项目'),
                    h('div', { class: 'wb-spacer' }),
                    h('button', {
                        class: 'wb-btn wb-btn-primary',
                        onclick: () => { S.modelMode = parseInt(mmSel.value, 10); S.tab = 'design'; renderBody(); }
                    }, '→ 检查源模型并继续')));
        }

        /* ---- 设计点配置(07-02~08): 已知目标 + 求解 + 比较 + commit ---- */
        function designTab() {
            const isV2 = S.modelMode === 1;
            const fields = [
                ['NpRpm', 'Np设计转速', 'rpm'], ['NgRpm', 'Ng设计转速', 'rpm'],
                ['loadPowerW', 'PT负载功率', 'W'], ['targetTt4K', '燃烧室出口总温Tt4', 'K'],
                ['nozzleAreaM2', '喷口面积', 'm²']
            ];
            if (isV2) fields.push(['targetPt25Pa', '25截面目标压力', 'Pa'], ['targetTt25K', '25截面目标温度', 'K']);
            const inputs = fields.map(([k, label, unit]) => {
                const inp = h('input', { value: S.design[k] != null ? S.design[k] : '' });
                inp.dataset.k = k;
                return { k, label, unit, inp };
            });
            const runBtn = h('button', {
                class: 'wb-btn wb-btn-primary',
                onclick: () => {
                    inputs.forEach(({ k, inp }) => { const v = parseFloat(inp.value); if (!isNaN(v)) S.design[k] = v; });
                    const design = {};
                    Object.keys(S.design).forEach(k => { const v = parseFloat(S.design[k]); if (!isNaN(v)) design[k] = v; });
                    runBtn.classList.add('disabled');
                    apiPost('/tasks/design_point/run', { modelMode: S.modelMode, design })
                        .then(r => {
                            if (r && r.code === 200 && r.data) { S.dpTaskId = r.data.taskId; pollDp(); }
                            else toast((r && r.message) || '求解发起失败', 'error');
                            runBtn.classList.remove('disabled');
                            renderBody();
                        })
                        .catch(e => { toast('求解发起失败:' + e.message, 'error'); runBtn.classList.remove('disabled'); });
                }
            }, '▶ 求解设计点');

            const box = h('div', null);
            box.appendChild(h('div', { class: 'wb-section-title', style: 'margin-bottom:8px' },
                isV2 ? '六部件:已知设计目标(2/25/3截面目标、级做功分配按求解结果展示)' : '三部件:已知设计目标'));
            const tbl = h('table', { class: 'wb-table' },
                h('tr', null, ['输入', '数值', '单位', '来源'].map(x => h('th', null, x))));
            inputs.forEach(({ k, label, unit, inp }) => {
                tbl.appendChild(h('tr', null,
                    h('td', null, label),
                    h('td', null, inp),
                    h('td', null, unit),
                    h('td', { class: 'wb-hint' }, '本次设计目标')));
            });
            tbl.appendChild(h('tr', null,
                h('td', null, 'HPC / GT / PT原始特性图'),
                h('td', { class: 'wb-hint' }, 'HPC02 / HPT02 / LPT02'),
                h('td', null, 'MAP'),
                h('td', { class: 'wb-hint' }, '所选MDL,只读名称')));
            box.appendChild(tbl);
            box.appendChild(h('div', { class: 'wb-hint', style: 'margin:8px 0' },
                '求解量与初值:' + (isV2 ? '进口流量、HPC Rline、GT/PT压比、级做功分配、Np、Ng、燃油流量' : '进口流量、HPC Rline、GT/PT压比、Np、Ng、燃油流量') + ';已知边界、目标量、求解初值与待求配置参数分开。'));
            box.appendChild(h('div', { class: 'wb-actions-row', style: 'margin-top:8px' }, runBtn));

            // 任务状态与比较(07-04/07)
            if (S.dpTaskId) {
                const holder = h('div', { style: 'margin-top:16px' }, h('div', { class: 'wb-empty' }, '正在加载求解状态...'));
                box.appendChild(holder);
                api('/tasks/' + encodeURIComponent(S.dpTaskId) + '/status').then(r => {
                    holder.innerHTML = '';
                    const d = r && r.code === 200 ? r.data : null;
                    if (!d) { holder.appendChild(h('div', { class: 'wb-empty' }, '状态读取失败')); return; }
                    const res = d.result || {};
                    holder.appendChild(h('div', { class: 'wb-infobar', style: 'margin-bottom:10px' },
                        d.phase === 'ENDED' ? '求解完成;求解完成不等于正式模型已改变,写入MDL需显式commit。'
                            : d.phase === 'FAILED' ? ('求解失败:' + (d.error || d.message || '')) : '求解运行中...'));
                    const kv = h('div', { class: 'wb-kv', style: 'max-width:1180px' });
                    [['任务', d.taskId], ['程序状态', res.status || '—'],
                     ['是否通过复现', res.accepted === true ? '通过' : res.accepted === false ? '有发现(不掩盖)' : '—'],
                     ['耗时(秒)', res.elapsedSeconds != null ? Number(res.elapsedSeconds).toFixed(1) : '—'],
                     ['候选目录', res.candidateDirectory || '—'],
                     ['已提交MDL', res.commit && res.commit.written ? '已写入(时间备份)' : '未写入']]
                        .forEach(([k, v]) => { kv.appendChild(h('div', { class: 'k' }, k)); kv.appendChild(h('div', { class: 'v' }, String(v == null ? '—' : v))); });
                    holder.appendChild(kv);
                    // 参数比较表(候选设计值 vs MDL当前值)
                    const cmp = res.parameterComparison || res.parameterStates;
                    if (Array.isArray(cmp) && cmp.length) {
                        holder.appendChild(h('div', { class: 'wb-section-title', style: 'margin:12px 0 8px' }, '候选设计值与MDL当前值比较'));
                        const ct = h('table', { class: 'wb-table' },
                            h('tr', null, ['参数', 'MDL当前值', '候选设计值'].map(x => h('th', null, x))));
                        cmp.slice(0, 30).forEach(p => ct.appendChild(h('tr', null,
                            h('td', null, String(p.name || p.parameter || '—')),
                            h('td', null, str(p.current != null ? p.current : p.mdlValue)),
                            h('td', null, str(p.candidate != null ? p.candidate : p.designValue)))));
                        holder.appendChild(ct);
                    }
                    const acts = h('div', { class: 'wb-actions-row', style: 'margin-top:12px' });
                    if (d.phase === 'ENDED' && res.accepted === true && !(res.commit && res.commit.written)) {
                        acts.appendChild(h('button', {
                            class: 'wb-btn wb-btn-primary',
                            onclick: () => {
                                if (!confirm('commit将产生带时间戳且不覆盖的备份后写入所选MDL,并运行offDesignMode=2复现检查,继续?')) return;
                                apiPost('/tasks/' + encodeURIComponent(S.dpTaskId) + '/commit').then(() => pollDp());
                            }
                        }, '提交设计(备份后写入MDL)'));
                    }
                    if (['ENDED', 'FAILED', 'COMMITTED'].includes(d.phase)) {
                        acts.appendChild(h('button', { class: 'wb-btn wb-btn-outline', onclick: () => { S.dpTaskId = null; renderBody(); } }, '新建求解'));
                    }
                    if (acts.children.length) holder.appendChild(acts);
                }).catch(() => { holder.innerHTML = ''; holder.appendChild(h('div', { class: 'wb-empty' }, '状态读取失败')); });
            }
            return box;
        }
        function str(v) { return v == null ? '—' : String(v); }
        function toast(msg, kind) { if (window.Workbench && window.Workbench.toast) window.Workbench.toast(msg, kind || 'info'); }
        function pollDp() {
            if (!S.dpTaskId) return;
            api('/tasks/' + encodeURIComponent(S.dpTaskId) + '/status').then(r => {
                const d = r && r.code === 200 ? r.data : null;
                if (d && !['ENDED', 'FAILED', 'COMMITTED'].includes(d.phase)) {
                    window.__WB_ENGINE_POLL_UNTIL__ = Date.now() + 40000;
                    if (S.tab === 'design') renderBody(); else setTimeout(pollDp, 4000);
                }
            }).catch(() => { });
        }

        /* ---- 特性图(07-15/16)与物理热参数(07-17/18): 配置说明+随阶段链执行 ---- */
        function mapsTab() {
            return h('div', { class: 'wb-card', style: 'max-width:860px' },
                h('div', { class: 'wb-section-title', style: 'margin-bottom:6px' }, '低速特性图设置与对比'),
                h('div', { class: 'wb-hint', style: 'margin:0 0 10px' },
                    '扩展前后图线、实际使用范围和约束在校核执行(maps阶段)后生成;构造低速模型不是获得真实低速试验标定,建模假设与实测证据分列。'),
                h('table', { class: 'wb-table' },
                    h('tr', null, ['内容', '说明'].map(x => h('th', null, x))),
                    h('tr', null, h('td', null, 'mapIO/extension'), h('td', { class: 'wb-hint' }, 'maps阶段按当前合同扩展低速特性并生成候选图;原图与候选图(含效率)随校核结果提供')),
                    h('tr', null, h('td', null, '入口'), h('td', { class: 'wb-hint' }, '原V1/V2入口保留原用途;Auto入口写正式MDL前必须备份'))),
                h('div', { class: 'wb-actions-row', style: 'margin-top:12px' },
                    h('button', { class: 'wb-btn wb-btn-primary', onclick: () => { S.tab = 'exec'; renderBody(); } }, '→ 校核执行(含maps阶段)')));
        }
        function physicsTab() {
            return h('div', { class: 'wb-card', style: 'max-width:860px' },
                h('div', { class: 'wb-section-title', style: 'margin-bottom:6px' }, '物理与热参数'),
                h('div', { class: 'wb-hint', style: 'margin:0 0 10px' },
                    '物理/热参数及其来源在配置中显式给定;engineOverrides只覆盖现有起停配置的物理/数值参数,不能覆盖隔离路径。'),
                h('table', { class: 'wb-table' },
                    h('tr', null, ['参数组', '来源与说明'].map(x => h('th', null, x))),
                    h('tr', null, h('td', null, 'startStop/stage5'), h('td', { class: 'wb-hint' }, '起停物理与低速求解参数;随当前模型合同')),
                    h('tr', null, h('td', null, 'stage6积分'), h('td', { class: 'wb-hint' }, '正式合同0.025秒二阶欧拉;不允许通过覆盖配置绕开')),
                    h('tr', null, h('td', null, 'stage7热参数'), h('td', { class: 'wb-hint' }, 'source.thermalFile显式提供;五参考点不称为十二点完整统计热包')),
                    h('tr', null, h('td', null, '轴系配平'), h('td', { class: 'wb-hint' }, '不等于所有金属节点已热平衡;六部件正常起停能力不推定新设计热生成功能全部支持'))),
                h('div', { class: 'wb-actions-row', style: 'margin-top:12px' },
                    h('button', { class: 'wb-btn wb-btn-primary', onclick: () => { S.tab = 'exec'; renderBody(); } }, '→ 校核执行')));
        }

        /* ---- 校核执行(07-19/20)与校核结果(07-21~24) ---- */
        function execTab() {
            const STAGES = [['maps', '特性图扩展'], ['design', '设计解'], ['matrix', '逐点矩阵'], ['physics', '物理校核'], ['continuous', '连续起停'], ['thermal', '热效应与热浸']];
            const checks = STAGES.map(([s]) => {
                const c = h('input', { type: 'checkbox', checked: s !== 'thermal' ? '' : null });
                c.dataset.stage = s;
                return c;
            });
            const runBtn = h('button', {
                class: 'wb-btn wb-btn-primary',
                onclick: () => {
                    const stages = checks.filter(c => c.checked).map(c => c.dataset.stage);
                    if (!stages.length) { toast('请至少选择一个校核阶段', 'error'); return; }
                    runBtn.classList.add('disabled');
                    apiPost('/tasks/startstop/run', { modelMode: S.modelMode, requestedStages: stages })
                        .then(r => {
                            if (r && r.code === 200 && r.data) { S.ssTaskId = r.data.taskId; renderBody(); }
                            else toast((r && r.message) || '发起失败', 'error');
                            runBtn.classList.remove('disabled');
                        })
                        .catch(e => { toast('发起失败:' + e.message, 'error'); runBtn.classList.remove('disabled'); });
                }
            }, '▶ 执行校核(按选择阶段链)');

            const box = h('div', null);
            box.appendChild(h('div', { class: 'wb-section-title', style: 'margin-bottom:8px' }, '选择校核范围'));
            box.appendChild(h('div', { style: 'display:flex;gap:16px;flex-wrap:wrap;margin-bottom:8px' },
                STAGES.map(([s, label], i) => h('label', { style: 'display:flex;align-items:center;gap:6px' }, checks[i], label + ' (' + s + ')'))));
            box.appendChild(h('div', { class: 'wb-hint', style: 'margin:6px 0 12px' },
                '估时依据当前合同(R009/R011本地R2019b有限任务,非精确预测);paused/failed/blocked即停;进度与安全停止以程序实际阶段为准。'));
            box.appendChild(h('div', { class: 'wb-actions-row' }, runBtn));

            if (S.ssTaskId) {
                const holder = h('div', { style: 'margin-top:16px' }, h('div', { class: 'wb-empty' }, '正在加载校核状态...'));
                box.appendChild(holder);
                api('/tasks/' + encodeURIComponent(S.ssTaskId) + '/status').then(r => {
                    holder.innerHTML = '';
                    const d = r && r.code === 200 ? r.data : null;
                    if (!d) { holder.appendChild(h('div', { class: 'wb-empty' }, '状态读取失败')); return; }
                    const res = d.result || {};
                    holder.appendChild(h('div', { class: 'wb-infobar', style: 'margin-bottom:10px' },
                        d.phase === 'ENDED' ? ('校核完成;程序状态=' + (res.status || '—') + '。顶层完成不代表每项物理检查均通过。')
                            : d.phase === 'FAILED' ? ('校核失败:' + (d.error || d.message || '')) : '校核运行中(逐阶段执行;paused/failed/blocked即停)...'));
                    const kv = h('div', { class: 'wb-kv', style: 'max-width:1180px' });
                    [['任务', d.taskId], ['阶段链', ((d.config || {}).requestedStages || []).join(' → ') || '—'],
                     ['程序状态', res.status || '—'], ['任务目录', res.taskDirectory || d.message || '—']]
                        .forEach(([k, v]) => { kv.appendChild(h('div', { class: 'k' }, k)); kv.appendChild(h('div', { class: 'v' }, String(v == null ? '—' : v))); });
                    holder.appendChild(kv);
                    if (d.phase === 'FAILED' && d.error) {
                        holder.appendChild(h('div', { class: 'wb-tag wb-tag-red', style: 'display:inline-block;padding:6px 12px;border-radius:6px;margin-top:8px' }, String(d.error)));
                    }
                    const acts = h('div', { class: 'wb-actions-row', style: 'margin-top:12px' });
                    if (['ENDED', 'FAILED'].includes(d.phase)) {
                        acts.appendChild(h('button', { class: 'wb-btn wb-btn-primary', onclick: () => { S.tab = 'verif'; renderBody(); } }, '查看校核结果'));
                        acts.appendChild(h('button', { class: 'wb-btn wb-btn-outline', onclick: () => { S.ssTaskId = null; renderBody(); } }, '新建校核'));
                    }
                    holder.appendChild(acts);
                }).catch(() => { holder.innerHTML = ''; holder.appendChild(h('div', { class: 'wb-empty' }, '状态读取失败')); });
            }
            return box;
        }

        function verifTab() {
            return h('div', { class: 'wb-card', style: 'max-width:860px' },
                h('div', { class: 'wb-section-title', style: 'margin-bottom:6px' }, '校核结果'),
                h('div', { class: 'wb-hint', style: 'margin:0 0 10px' },
                    '简单测试分别呈现设计点复现、低速点矩阵、连续起停与热检查的实际执行情况;测试结果保留失败点、限制和日志,不为全绿删除难点。'),
                h('table', { class: 'wb-table' },
                    h('tr', null, ['结果物', '查看方式'].map(x => h('th', null, x))),
                    h('tr', null, h('td', null, '候选特性图与原图(含效率)'), h('td', { class: 'wb-hint' }, '任务目录 TestData/MiddleData 随校核任务生成')),
                    h('tr', null, h('td', null, '逐点矩阵与失败诊断'), h('td', { class: 'wb-hint' }, 'matrix阶段证据文件')),
                    h('tr', null, h('td', null, '连续起停结果与阶段事件'), h('td', { class: 'wb-hint' }, 'continuous阶段记录')),
                    h('tr', null, h('td', null, '热效应与热浸校核'), h('td', { class: 'wb-hint' }, 'thermal阶段记录')),
                    h('tr', null, h('td', null, '全部调图参数与证据'), h('td', { class: 'wb-hint' }, '任务目录 result/日志'))),
                h('div', { class: 'wb-actions-row', style: 'margin-top:12px' },
                    h('button', { class: 'wb-btn wb-btn-primary', onclick: () => { S.tab = 'assets'; renderBody(); } }, '→ 模型成果与保存')));
        }

        function assetsTab() {
            return h('div', { class: 'wb-card', style: 'max-width:860px' },
                h('div', { class: 'wb-section-title', style: 'margin-bottom:6px' }, '保存模型及交付文件'),
                h('div', { class: 'wb-hint', style: 'margin:0 0 10px' },
                    '公开起停模型包包括实际地图、MDL、DLL/头文件、设计种子和热配置,不以一个Excel替代;保存前展示文件清单与来源,保存后提供只读查看与「用于全模式仿真」入口。'),
                h('div', { class: 'wb-actions-row' },
                    h('button', { class: 'wb-btn wb-btn-primary', onclick: () => ctx.navigate('models') }, '前往模型成果'),
                    h('button', { class: 'wb-btn wb-btn-outline', onclick: () => ctx.navigate('fullmode') }, '用于全模式仿真')));
        }

        function renderBody() { paintTabs(); body.innerHTML = ''; 
            if (S.tab === 'prepare') body.appendChild(prepareTab());
            else if (S.tab === 'design') body.appendChild(designTab());
            else if (S.tab === 'maps') body.appendChild(mapsTab());
            else if (S.tab === 'physics') body.appendChild(physicsTab());
            else if (S.tab === 'exec') body.appendChild(execTab());
            else if (S.tab === 'verif') body.appendChild(verifTab());
            else body.appendChild(assetsTab());
        }
        renderBody();
        return wrap;
    };
    /* 试车台模型成果(与建模工作台同一renderModelsBody) */
    pages['testbench.models'] = (ctx) => {
        const wrap2 = h('div', null, pageHeader('模型成果',
            (ctx.project.engineId || '—') + ' / 系统联合仿真 / 模型版本与数据、评估关联'));
        const body2 = h('div', null);
        wrap2.appendChild(body2);
        renderModelsBody(ctx, body2);
        return wrap2;
    };

    /* ===== 多系统联合仿真(F-12,AFO_V_2;sht_afo_session合同)===== */
    // 通道组索引按 sht_afo_channels 顺序固定(status.values/result.values 的组下标)
    const AFO_GROUP = { engine: 0, load: 1, fuel_command: 2, fuel_engine: 3, fuel_detailed: 4, air01: 5, air02: 6, air03: 7, air04: 8, air05: 9, air06: 10, air07: 11, air08: 12 };
    const AFO_E = { Pt1: 0, Tt1: 1, Pt3: 2, Tt3: 3, Pt45: 4, Tt45: 5, Pt5: 6, Tt5: 7, Np: 8, Ng: 9, W2: 10, PT_drive_torque: 11, HPC_corrected: 12, GT_pr: 13, PT_pr: 14 };
    const AFO_NP_STEPS = [['0.8', '80%'], ['0.9', '90%'], ['0.95', '95%'], ['1', '100%'], ['1.05', '105%']];
    const AFO_PACE = [['realtime', '实时节奏(物理时间同步)'], ['fast', '尽快计算(不与墙钟同步)']];
    const AFO_LOAD = [['power', '恒实际PT功率 / kW'], ['torque', '恒扭矩 / N·m'], ['pitch', '恒总距角 / deg'], ['dual_pitch', '主/尾桨双总距角 / deg']];

    pages['testbench.afo'] = (ctx) => {
        const pid = ctx.project.id || '';
        const api = p => window.AppConfig.engineGet('projects/' + encodeURIComponent(pid) + '/afo' + p);
        const apiPost = (p, body) => window.AppConfig.enginePost('projects/' + encodeURIComponent(pid) + '/afo' + p, body || {});
        const S = window.__WB_AFO__ = window.__WB_AFO__ || {
            phase: 'IDLE', message: '', live: null, samples: [], lastSampleT: -1,
            result: null, readonlyRunId: null, readonlyLoading: false, tab: 'main',
            cfg: { engineId: ctx.project.engineId || 'ENGINE-001', duration: '30', recordStep: '0.1', pace: 'realtime', loadMode: 'power', powerW: '2176600', mkpNm: '1000', pitchDeg: '12', mainPitchDeg: '12', tailPitchDeg: '10', externalAir: false, npRatio: '1' }
        };
        S.tab = S.tab || 'main';
        const running = () => S.phase === 'RUNNING' || S.phase === 'PAUSED';
        const canCmd = () => running();

        const wrap = h('div', null,
            h('div', { style: 'margin-bottom:12px;display:flex;justify-content:space-between;align-items:baseline' },
                h('div', null,
                    h('div', { class: 'wb-page-title', style: 'font-size:20px;margin-bottom:2px' }, '多系统联合仿真'),
                    h('div', { class: 'wb-page-sub' },
                        (ctx.project.engineId || '—') + ' / ' + (S.readonlyRunId ? ('记录只读 ' + S.readonlyRunId)
                            : (S.live && S.live.runId ? S.live.runId : '燃油 · 滑油 · 空气'))),
                h('div', { class: 'wb-hint', style: 'margin:0' }, '基准 Dll_Control_AFO_V8_5_R2019b · 同实例暂停 · 燃油/滑油/空气耦合'))));
        const statusBar = h('div', { style: 'margin-bottom:12px' });
        const tabBar = h('div', { class: 'wb-tabs', style: 'margin-bottom:12px' });
        const body = h('div', null, h('div', { class: 'wb-empty' }, '正在加载会话状态...'));
        const foot = h('div', null);
        wrap.appendChild(statusBar);
        wrap.appendChild(tabBar);
        wrap.appendChild(body);
        wrap.appendChild(foot);

        const TABS = [['main', '总控'], ['engine', '发动机'], ['control', '控制'], ['fuel', '燃油'], ['oil', '滑油'], ['air', '空气']];
        function paintTabs() {
            tabBar.innerHTML = '';
            TABS.forEach(([k, label]) => tabBar.appendChild(h('div', {
                class: 'wb-tab' + (S.tab === k ? ' active' : ''),
                onclick: () => { S.tab = k; renderAll(); }
            }, label)));
        }

        /* —— 状态条(09-13):相位 | 仿真时间 | 主控按钮 —— */
        function paintStatus() {
            statusBar.innerHTML = '';
            const t = S.live && typeof S.live.time === 'number' ? S.live.time : (S.result ? S.result.finalSimulationTime : 0);
            const phaseLabel = S.readonlyRunId ? ['历史记录 · 只读', 'gray']
                : S.phase === 'RUNNING' ? ['正在运行', 'teal']
                : S.phase === 'PAUSED' ? ['已暂停(保持状态)', 'amber']
                : S.phase === 'PREPARING' ? ['准备中(运行副本/身份校验/模型初始化)', 'amber']
                : S.phase === 'READY' ? ['已就绪 · 未运行', 'teal']
                : S.phase === 'ENDED' ? ['已结束 · 记录已保存', 'gray']
                : S.phase === 'FAILED' ? ['失败', 'red'] : ['空闲 · 新建运行', 'gray'];
            const bar = h('div', { class: 'wb-infobar', style: 'display:flex;align-items:center;gap:18px;padding:10px 16px' },
                h('span', { class: 'wb-tag wb-tag-' + phaseLabel[1] }, phaseLabel[0]),
                h('span', { style: 'font-weight:600' }, '仿真时间 ' + Number(t || 0).toFixed(3) + ' s'),
                h('span', { class: 'wb-hint', style: 'margin:0' }, S.message || (S.readonlyRunId ? '完整记录已保存' : '内部引气 / 外部系统同步计算')),
                h('div', { class: 'wb-spacer' }));
            statusBar.appendChild(bar);
            const actions = h('div', { class: 'wb-actions-row', style: 'margin:8px 0 0' });
            if (S.readonlyRunId) {
                actions.appendChild(h('button', { class: 'wb-btn wb-btn-outline', onclick: () => exitReadonly() }, '‹ 返回仿真准备'));
                actions.appendChild(h('div', { class: 'wb-spacer' }));
                actions.appendChild(h('button', { class: 'wb-btn wb-btn-outline', onclick: () => window.open(excelUrl(S.readonlyRunId), '_blank') }, '导出Excel'));
                actions.appendChild(h('button', { class: 'wb-btn wb-btn-primary', onclick: () => reuseConfig() }, '用此配置新建'));
            } else if (S.phase === 'RUNNING' || S.phase === 'PAUSED') {
                actions.appendChild(h('button', {
                    class: 'wb-btn wb-btn-primary',
                    onclick: () => sendCmd(S.phase === 'RUNNING' ? 'pause' : 'resume', 0)
                }, S.phase === 'RUNNING' ? '暂停' : '继续'));
                actions.appendChild(h('button', {
                    class: 'wb-btn wb-btn-outline',
                    onclick: () => { if (confirm('结束计算?当前有效记录将保存,暂停不卸载、不自动断油。')) sendCmd('stop', 0); }
                }, '结束计算'));
            } else if (S.phase === 'READY') {
                actions.appendChild(h('button', { class: 'wb-btn wb-btn-primary', onclick: () => startRun() }, '开始运行'));
                actions.appendChild(h('button', { class: 'wb-btn wb-btn-outline', onclick: () => closeSession() }, '放弃并关闭(改配置重新准备)'));
            } else if (S.phase === 'ENDED' || S.phase === 'FAILED') {
                actions.appendChild(h('button', { class: 'wb-btn wb-btn-outline', onclick: () => window.open(excelUrl(S.live && S.live.runId ? S.live.runId : ''), '_blank') }, '导出Excel'));
                actions.appendChild(h('button', { class: 'wb-btn wb-btn-primary', onclick: () => closeSession() }, '新建运行(关闭本会话)'));
            }
            bar.appendChild(actions);
        }

        const excelUrl = runId => {
            const cfg0 = window.AppConfig;
            return cfg0.api.baseURL + '/api/engine/projects/' + encodeURIComponent(pid)
                + '/afo/sessions/' + encodeURIComponent(runId) + '/excel?token=' + encodeURIComponent(cfg0.getToken() || '');
        };

        /* —— 数据抽取:运行中 samples(实时) / 历史 result —— */
        function pushSample(live) {
            const t = live.time;
            if (typeof t !== 'number' || t <= S.lastSampleT) return;
            S.lastSampleT = t;
            const v = live.values || [];
            const eng = v[AFO_GROUP.engine] || [];
            const load = v[AFO_GROUP.load] || [];
            S.samples.push({
                t: t, Np: eng[AFO_E.Np], Ng: eng[AFO_E.Ng], Tt3: eng[AFO_E.Tt3], Tt45: eng[AFO_E.Tt45],
                W2: eng[AFO_E.W2], Mkp: load[0], Pload: load[4],
                Wf_cmd: (v[AFO_GROUP.fuel_command] || [])[0], Wf: (v[AFO_GROUP.fuel_engine] || [])[0]
            });
            if (S.samples.length > 4000) S.samples.splice(0, S.samples.length - 4000);
        }

        function seriesFromSamples(keys) {
            return keys.map(k => ({ name: k, values: S.samples.map(s => s[k]) }));
        }
        function resultCell(g, i, j) {
            const vals = S.result.values || [];
            const n = (S.result.time || []).length;
            if (!vals.length || !n) return null;
            const w0 = Array.isArray(vals[0]) ? vals[0].length : -1;
            const colMajor = vals.length > n && Array.isArray(vals[1]) && vals[1].length === w0;
            const cell = colMajor ? vals[i + g * n] : (vals[i] ? vals[i][g] : null);
            return (cell && cell[j] != null) ? cell[j] : null;
        }
        function seriesFromResult(g, js) {
            const n = (S.result.time || []).length;
            return js.map(j => ({
                name: '通道' + (j + 1),
                values: Array.from({ length: n }, (_, i) => resultCell(g, i, j))
            }));
        }
        function lineByTime(values, labels0) {
            const xLabels = [];
            const n = values.length;
            const step = Math.max(1, Math.ceil(n / 8));
            for (let i = 0; i < n; i++) if (i % step === 0) xLabels.push(labels0 && labels0.length ? Number(labels0[i]).toFixed(1) : String(i));
            return xLabels;
        }

        /* —— 页签渲染 —— */
        function paintBody() {
            body.innerHTML = '';
            if (S.readonlyLoading) {
                body.appendChild(h('div', { class: 'wb-empty' }, '正在加载历史记录(result.json)...'));
                return;
            }
            const src = S.readonlyRunId || S.result ? 'result'
                : (running() || S.phase === 'ENDED' || S.phase === 'FAILED') ? 'live' : 'idle';
            if (S.tab === 'main') paintMain(src);
            else paintSystemTab(src);
        }

        /* —— 总控(09-13) —— */
        function paintMain(src) {
            if (src === 'idle') { paintConfigForm(); return; }
            const live = S.live || {};
            // Np挡位 + 负载施加(运行中;09-13)
            if (canCmd()) {
                body.appendChild(h('div', { class: 'wb-infobar' },
                    '负载方式:' + (AFO_LOAD.find(l => l[0] === loadMode())[1] || '—') + '。空气耦合与负载类型已锁定;当前无待生效命令。'));
                const npRow = h('div', { style: 'display:flex;gap:10px;align-items:center;margin:12px 0' });
                const curRatio = live.applied && live.applied[0] != null ? live.applied[0] / designNp() : 1;
                AFO_NP_STEPS.forEach(([val, label]) => {
                    npRow.appendChild(h('button', {
                        class: 'wb-btn ' + (Math.abs(parseFloat(val) - curRatio) < 1e-9 ? 'wb-btn-primary' : 'wb-btn-outline'),
                        onclick: () => sendCmd('np', parseFloat(val))
                    }, label));
                });
                body.appendChild(h('div', { class: 'wb-section-title', style: 'margin-bottom:8px' }, 'Np运行挡位'));
                body.appendChild(npRow);
                body.appendChild(h('div', { class: 'wb-hint', style: 'margin-bottom:12px' },
                    '当前生效目标: ' + npText() + ';状态: ' + (live.pending ? '有待生效命令(' + live.pending.kind + ')' : '无')));
                // 负载草稿(09-13:按当前负载方式显示对应输入)
                const lm = loadMode();
                const unitTxt = lm === 'power' ? 'PT功率草稿 / kW' : lm === 'torque' ? '扭矩草稿 / N·m' : lm === 'pitch' ? '总距角草稿 / deg' : '主桨总距角草稿 / deg';
                const draft = h('input', { value: loadDraftDefault(lm), id: 'afo-load-draft' });
                body.appendChild(h('div', { class: 'wb-form-grid', style: 'grid-template-columns:320px 200px;max-width:620px;align-items:end' },
                    h('div', { class: 'wb-field' }, h('label', null, unitTxt), draft),
                    h('div', null, h('button', { class: 'wb-btn wb-btn-outline', style: 'width:100%', onclick: () => applyLoadDraft() }, '✓ 施加负载'))));
            } else if (S.phase === 'ENDED' || S.phase === 'FAILED') {
                body.appendChild(h('div', { class: 'wb-infobar' },
                    S.phase === 'FAILED' ? ('运行失败:' + (S.message || '') + ';有效部分不丢弃,历史与Excel仍可读。') : '运行结束;全通道Excel与result已保存,可进入各系统页签查看曲线。'));
            }
            // 关键输出大数字(09-13/09-01)
            body.appendChild(kvBig(src === 'result' ? bigFromResult() : bigFromLive()));
            // 命令回执表(events)
            const events = (src === 'result' ? (S.result.events || []) : (live.events || []));
            body.appendChild(h('div', { class: 'wb-section-title', style: 'margin:16px 0 8px' }, '本次操纵记录'));
            if (events.length) {
                const tbl = h('table', { class: 'wb-table' },
                    h('tr', null, ['命令', '接收', '生效', '当前状态'].map(x => h('th', null, x))));
                events.slice(-12).forEach(ev => {
                    tbl.appendChild(h('tr', null,
                        h('td', null, cmdText(ev)),
                        h('td', { class: 'wb-hint' }, fmtT(ev.acceptedTime)),
                        h('td', { class: 'wb-hint' }, fmtT(ev.appliedTime)),
                        h('td', null, ev.status === 'applied' ? '已生效,按实际轴速观察响应'
                            : ev.status === 'accepted' ? '已接收,等待主步生效'
                            : ev.status === 'rejected' ? ('已回退:' + (ev.reason || '')) : (ev.status || '—'))));
                });
                body.appendChild(tbl);
            } else {
                body.appendChild(h('div', { class: 'wb-hint' }, '本次运行无在线操纵(初始配置见准备记录)。'));
            }
            body.appendChild(h('div', { class: 'wb-hint', style: 'margin-top:12px' },
                '修改模型、空气配置或负载类型需新建运行;暂停不卸载,不自动断油。'));
        }

        const loadMode = () => (S.result && S.result.config) ? S.result.config.loadMode : S.cfg.loadMode;
        const designNp = () => (S.result && S.result.config && S.result.config.designNpRpm) || 20800;
        const npText = () => {
            const live = S.live || {};
            const a = live.applied || [];
            return a[0] != null ? ('' + Math.round(a[0]) + ' rpm / 负载 ' + (a[1] != null ? Number(a[1]).toFixed(1) : '—')) : '—';
        };
        const loadDraftDefault = lm => lm === 'torque' ? String(S.cfg.mkpNm) : lm === 'pitch' ? String(S.cfg.pitchDeg) : lm === 'dual_pitch' ? String(S.cfg.mainPitchDeg) : String(S.cfg.powerW);
        const fmtT = t => (t == null || isNaN(t)) ? '—' : Number(t).toFixed(3) + ' s';
        const cmdText = ev => {
            const v = ev.value;
            switch (ev.kind) {
                case 'np': return 'Np → ' + Math.round(parseFloat(v) * 100) + '%';
                case 'load':
                    const lm = loadMode();
                    return lm === 'power' ? 'PT功率 → ' + Number(v).toFixed(2) + ' kW'
                        : lm === 'torque' ? '扭矩 → ' + Number(v).toFixed(1) + ' N·m'
                        : lm === 'pitch' ? '总距角 → ' + Number(v).toFixed(2) + '°'
                        : '主/尾桨 → ' + (Array.isArray(v) ? v.map(x => Number(x).toFixed(1) + '°').join(' / ') : v);
                case 'pause': return '暂停';
                case 'resume': return '继续';
                case 'stop': return '结束计算';
                default: return ev.kind + ' ' + JSON.stringify(v);
            }
        };

        function bigFromLive() {
            const live = S.live || {};
            const v = live.values || [];
            const eng = v[AFO_GROUP.engine] || [];
            return [
                ['Np实际', eng[AFO_E.Np], 'rpm'], ['Ng实际', eng[AFO_E.Ng], 'rpm'],
                ['发动机燃油', (v[AFO_GROUP.fuel_engine] || [])[0], 'kg/s'],
                ['Tt45', eng[AFO_E.Tt45], 'K']
            ];
        }
        function bigFromResult() {
            const g = AFO_GROUP.engine;
            const last = (j) => {
                const n = (S.result.time || []).length;
                const vals = S.result.values || [];
                for (let i = n - 1; i >= 0; i--) {
                    const v = resultCell(g, i, j);
                    if (v != null) return v;
                }
                return null;
            };
            return [
                ['Np实际轴速', last(AFO_E.Np), 'rpm'], ['Ng实际轴速', last(AFO_E.Ng), 'rpm'],
                ['Tt45', last(AFO_E.Tt45), 'K'], ['入口流量W2', last(AFO_E.W2), 'kg/s']
            ];
        }
        function kvBig(items) {
            const grid = h('div', { style: 'display:grid;grid-template-columns:repeat(4,1fr);gap:16px;margin:14px 0' });
            items.forEach(([label, v, unit]) => grid.appendChild(h('div', { style: 'background:#fff;border:1px solid #e5e7eb;border-radius:6px;padding:12px 16px' },
                h('div', { class: 'wb-hint', style: 'margin:0 0 4px' }, label),
                h('div', { style: 'font-size:24px;font-weight:700;color:#111827' }, v == null || !isFinite(Number(v)) ? '—' : Number(v).toFixed(3)),
                h('div', { class: 'wb-hint', style: 'margin:0' }, unit || ''))));
            return grid;
        }

        /* —— 准备配置表单(09-11准备:检查成套包并展示真实初态) —— */
        function paintConfigForm() {
            body.appendChild(h('div', { class: 'wb-infobar' },
                '准备会创建独立运行副本(原SLX/DLL/MDL不写入),校验成套身份后初始化模型;准备完成才能开始运行。'));
            const c = S.cfg;
            const f = {};
            const mk = (label, key, unit) => {
                f[key] = h('input', { value: c[key] });
                return h('div', { class: 'wb-field' }, h('label', null, label + (unit ? ' / ' + unit : '')), f[key]);
            };
            const paceSel = h('select', null, AFO_PACE.map(([v, l]) => h('option', { value: v, selected: c.pace === v ? '' : null }, l)));
            const loadSel = h('select', null, AFO_LOAD.map(([v, l]) => h('option', { value: v, selected: c.loadMode === v ? '' : null }, l)));
            const airSel = h('select', null, h('option', { value: 'internal', selected: !c.externalAir ? '' : null }, '内部引气(外部空气系统仍计算,8路不回灌)'),
                h('option', { value: 'external', selected: c.externalAir ? '' : null }, '外部8路回灌(经一步延迟生效)'));
            const loadBox = h('div', { class: 'wb-form-grid', style: 'grid-template-columns:1fr 1fr' });
            const paintLoadFields = () => {
                const lm = loadSel.value;
                loadBox.innerHTML = '';
                if (lm === 'power') loadBox.appendChild(mk('PT功率', 'powerW', 'kW'));
                else if (lm === 'torque') loadBox.appendChild(mk('扭矩', 'mkpNm', 'N·m'));
                else if (lm === 'pitch') loadBox.appendChild(mk('总距角', 'pitchDeg', 'deg'));
                else { loadBox.appendChild(mk('主桨总距角', 'mainPitchDeg', 'deg')); loadBox.appendChild(mk('尾桨总距角', 'tailPitchDeg', 'deg')); }
            };
            loadSel.addEventListener('change', paintLoadFields);
            body.appendChild(h('div', { class: 'wb-form-grid', style: 'grid-template-columns:repeat(3,1fr);max-width:1080px' },
                mk('发动机编号', 'engineId'),
                mk('仿真时长', 'duration', 's'),
                mk('记录步长', 'recordStep', 's(积分步0.025整数倍)'),
                h('div', { class: 'wb-field' }, h('label', null, '运行节奏'), paceSel),
                h('div', { class: 'wb-field' }, h('label', null, '负载方式(运行中锁定)'), loadSel),
                h('div', { class: 'wb-field' }, h('label', null, '空气回灌'), airSel)));
            body.appendChild(loadBox);
            const btn = h('button', {
                class: 'wb-btn wb-btn-primary',
                onclick: async () => {
                    btn.classList.add('disabled');
                    try {
                        const cfgReq = {
                            engineId: f.engineId.value.trim() || 'ENGINE-001',
                            duration: parseFloat(f.duration.value),
                            recordStep: parseFloat(f.recordStep.value),
                            pace: paceSel.value,
                            loadMode: loadSel.value,
                            powerW: parseFloat(f.powerW ? f.powerW.value : c.powerW),
                            mkpNm: parseFloat(f.mkpNm ? f.mkpNm.value : c.mkpNm),
                            pitchDeg: parseFloat(f.pitchDeg ? f.pitchDeg.value : c.pitchDeg),
                            mainPitchDeg: parseFloat(f.mainPitchDeg ? f.mainPitchDeg.value : c.mainPitchDeg),
                            tailPitchDeg: parseFloat(f.tailPitchDeg ? f.tailPitchDeg.value : c.tailPitchDeg),
                            externalAir: airSel.value === 'external',
                            npRatio: parseFloat(c.npRatio)
                        };
                        if (!isFinite(cfgReq.duration) || cfgReq.duration <= 0) throw new Error('仿真时长须为正数');
                        if (!isFinite(cfgReq.recordStep) || cfgReq.recordStep <= 0) throw new Error('记录步长须为正数');
                        S.cfg = Object.assign({}, S.cfg, cfgReq);
                        await apiPost('/prepare', cfgReq);
                        toast('准备已发起;运行副本与模型初始化需要一些时间', 'info');
                        startPoll();
                    } catch (e) { toast('准备失败:' + e.message, 'error'); }
                    btn.classList.remove('disabled');
                }
            }, '准备并校验(创建运行副本)');
            body.appendChild(h('div', { class: 'wb-actions-row', style: 'margin-top:14px' },
                btn,
                h('button', { class: 'wb-btn wb-btn-outline', onclick: () => { ctx.navigate('records'); } }, '查看历史仿真记录')));
            body.appendChild(h('div', { class: 'wb-hint', style: 'margin-top:10px' },
                'Np初值挡位为100%(设计转速点);运行中可施加80/90/95/100/105%与负载在线指令。'));
        }

        /* —— 系统页签(09-01/02/05):曲线 + 通道核对 —— */
        function paintSystemTab(src) {
            const tab = S.tab;
            if (tab === 'engine') {
                body.appendChild(h('div', { class: 'wb-infobar' },
                    '发动机内部轴扭矩与外部PT负载扭矩分开展示;不将计算量冒充传感器测量。'));
                body.appendChild(kvBig(src === 'result' ? bigFromResult() : bigFromLive()));
                const grids = h('div', { style: 'display:grid;grid-template-columns:1fr 1fr;gap:18px' });
                grids.appendChild(chartCard('两轴转速 / rpm', chartFor(['Np', 'Ng'], src)));
                grids.appendChild(chartCard('燃气温度 / K', chartFor(['Tt3', 'Tt45'], src)));
                body.appendChild(grids);
                body.appendChild(h('div', { class: 'wb-hint', style: 'margin-top:10px' },
                    '其他通道:各截面温压、流量、实际压比、换算转速、共同工作残差——全通道见交付Excel(通道筛选在底部)。'));
            } else if (tab === 'control') {
                body.appendChild(h('div', { class: 'wb-infobar' },
                    '修改指令请返回总控。这里查看控制响应、实际负载和操纵记录,不设置第二套指令。'));
                const grids = h('div', { style: 'display:grid;grid-template-columns:1fr 1fr;gap:18px' });
                grids.appendChild(chartCard('Np响应 / rpm', chartFor(['Np'], src)));
                grids.appendChild(chartCard('PT实际负载 / kW', chartFor(['Pload'], src)));
                body.appendChild(grids);
                body.appendChild(h('div', { class: 'wb-section-title', style: 'margin:16px 0 8px' }, '本次操纵记录'));
                body.appendChild(eventsTable(src));
            } else if (tab === 'fuel') {
                body.appendChild(h('div', { class: 'wb-infobar' },
                    '燃油三路分开:控制器指令 / 发动机实际采用 / 通往滑油散热器的详细流量;不把详细流量冒充主供油。'));
                body.appendChild(chartCard('燃油流量 / kg/s', chartFor(['Wf_cmd', 'Wf'], src), true));
            } else if (tab === 'oil') {
                body.appendChild(h('div', { class: 'wb-infobar' },
                    '滑油系统按轴承腔/散热器/通风分组展示;原始轴承出口温度保持K,仅混温支路换算摄氏度。'));
                if (src === 'result') {
                    body.appendChild(chartCard('滑油关键通道(通道筛选可选)', oilChart(), true));
                } else {
                    body.appendChild(h('div', { class: 'wb-hint', style: 'margin:8px 0' },
                        '运行中滑油全量通道以交付Excel为准;结束保存后本页提供曲线浏览。'));
                }
            } else if (tab === 'air') {
                body.appendChild(h('div', { class: 'wb-infobar' },
                    (S.result && S.result.config && S.result.config.externalAir) || (S.cfg && S.cfg.externalAir)
                        ? '外部回灌模式:8路流量经一步延迟回灌发动机;G04仍提供滑油边界。'
                        : '内部引气模式:外部空气系统仍计算,但8路流量不回灌发动机;G04仍提供滑油边界。'));
                if (src === 'result') {
                    const grids = h('div', { style: 'display:grid;grid-template-columns:1fr 1fr;gap:18px' });
                    grids.appendChild(chartCard('外部空气1~4路 / kg/s', airChart(0, 4), true));
                    grids.appendChild(chartCard('外部空气5~8路 / kg/s', airChart(4, 8), true));
                    body.appendChild(grids);
                } else {
                    body.appendChild(h('div', { class: 'wb-hint', style: 'margin:8px 0' },
                        '运行中空气8路流量在总控实时值可见;结束保存后本页提供分路曲线。'));
                }
                body.appendChild(h('div', { class: 'wb-section-title', style: 'margin:16px 0 8px' }, '发动机边界核对'));
                body.appendChild(h('table', { class: 'wb-table' },
                    h('tr', null, ['位置', '流量来源', '温度 / 压力 / 焓 / 油气比'].map(x => h('th', null, x))),
                    h('tr', null, h('td', null, '第1~8组'), h('td', null, '外部回灌启用时由8路结果替换'), h('td', null, '保留发动机模板')),
                    h('tr', null, h('td', null, '第9~10组'), h('td', null, '始终保留发动机模板'), h('td', null, '保留发动机模板')),
                    h('tr', null, h('td', null, '采用边界'), h('td', null, '回灌经原有一步延迟生效'), h('td', null, '同时保存模板、合并值、延迟值'))));
            }
        }

        function chartCard(title, chart, wide) {
            return h('div', { style: 'background:#fff;border:1px solid #e5e7eb;border-radius:6px;padding:12px;' + (wide ? '' : '') },
                h('div', { style: 'font-weight:600;margin-bottom:6px' }, title),
                chart || h('div', { class: 'wb-hint' }, '暂无曲线数据'));
        }

        /** 曲线:运行中→samples;历史→result.values。keys含'Pload/Wf_cmd'等映射到组索引。 */
        function chartFor(keys, src) {
            if (src === 'result') {
                if (!S.result || !S.result.values || !S.result.values.length) return null;
                const time = S.result.time || [];
                const KEYMAP = {
                    Np: [AFO_GROUP.engine, AFO_E.Np, 'Np'], Ng: [AFO_GROUP.engine, AFO_E.Ng, 'Ng'],
                    Tt3: [AFO_GROUP.engine, AFO_E.Tt3, 'Tt3'], Tt45: [AFO_GROUP.engine, AFO_E.Tt45, 'Tt45'],
                    W2: [AFO_GROUP.engine, AFO_E.W2, 'W2'],
                    Pload: [AFO_GROUP.load, 4, 'Pload'], Mkp: [AFO_GROUP.load, 0, 'Mkp'],
                    Wf_cmd: [AFO_GROUP.fuel_command, 0, 'Wf_command'], Wf: [AFO_GROUP.fuel_engine, 0, 'Wf_engine']
                };
                const series = keys.map(k => {
                    const m = KEYMAP[k];
                    if (!m) return null;
                    return { name: m[2], values: seriesFromResult(m[0], [m[1]])[0].values };
                }).filter(Boolean);
                if (!series.length) return null;
                const box = h('div', null);
                box.appendChild(chartLegend(series));
                box.appendChild(lineChart({ series, xLabels: lineByTime(series[0].values, time), xTitle: '时间 / s' }));
                return box;
            }
            // 实时/运行结束未保存:samples
            if (S.samples.length < 2) return h('div', { class: 'wb-hint' }, '采样积累中(记录步长见配置)...');
            const series = keys.map(k => ({ name: k, values: S.samples.map(s => s[k]) }));
            const box = h('div', null);
            box.appendChild(chartLegend(series));
            box.appendChild(lineChart({
                series, xLabels: lineByTime(S.samples.map(s => s.t)), xTitle: '时间 / s'
            }));
            return box;
        }

        function oilChart() {
            const chs = (S.result.channels || []);
            const g = chs.findIndex(c => c.id === 'oil_air_temperature');
            if (g < 0) return null;
            const series = seriesFromResult(g, [0]);
            series[0].name = '滑油-空气温度';
            const box = h('div', null);
            box.appendChild(chartLegend(series));
            box.appendChild(lineChart({ series, xLabels: lineByTime(series[0].values, S.result.time), xTitle: '时间 / s' }));
            return box;
        }
        function airChart(from, to) {
            const series = [];
            for (let k = from; k < to; k++) {
                const g = AFO_GROUP['air0' + (k + 1)];
                if (g == null) continue;
                const s = seriesFromResult(g, [0])[0];
                s.name = '第' + (k + 1) + '路';
                series.push(s);
            }
            if (!series.length) return null;
            const box = h('div', null);
            box.appendChild(chartLegend(series));
            box.appendChild(lineChart({ series, xLabels: lineByTime(series[0].values, S.result.time), xTitle: '时间 / s' }));
            return box;
        }
        function eventsTable(src) {
            const events = src === 'result' ? (S.result.events || []) : ((S.live || {}).events || []);
            if (!events.length) return h('div', { class: 'wb-hint' }, '无操纵记录。');
            const tbl = h('table', { class: 'wb-table' },
                h('tr', null, ['接收时刻', '操纵内容', '生效时刻', '状态'].map(x => h('th', null, x))));
            events.forEach(ev => tbl.appendChild(h('tr', null,
                h('td', { class: 'wb-hint' }, fmtT(ev.acceptedTime)),
                h('td', null, cmdText(ev)),
                h('td', { class: 'wb-hint' }, fmtT(ev.appliedTime)),
                h('td', null, ev.status === 'applied' ? '已生效' : ev.status === 'accepted' ? '已接收' : (ev.reason ? '已回退:' + ev.reason : ev.status)))));
            return tbl;
        }

        /* —— 底部共同游标(09-01) —— */
        function paintFoot() {
            foot.innerHTML = '';
            const span = S.result && S.result.time ? S.result.time : S.samples.map(s => s.t);
            const last = span.length ? span[span.length - 1] : 0;
            foot.appendChild(h('div', { class: 'wb-infobar', style: 'display:flex;gap:26px' },
                h('span', null, '⏱ 共同游标 ' + Number(last).toFixed(3) + ' s'),
                h('span', { class: 'wb-hint', style: 'margin:0' }, '范围 0.000 ~ ' + Number(last).toFixed(3) + ' s'),
                h('div', { class: 'wb-spacer' }),
                S.live && S.live.runId || S.readonlyRunId
                    ? h('a', { style: 'color:#096b77;text-decoration:underline;font-size:13px', href: excelUrl(S.readonlyRunId || S.live.runId), target: '_blank' }, '导出可见数据(全通道Excel)')
                    : h('span', { class: 'wb-hint', style: 'margin:0' }, '导出可见数据(运行保存后可用)')));
        }

        /** 运行结束(未在历史只读模式)时自动拉取本会话result.json,供各系统页渲染全量曲线。 */
        function ensureSessionResult() {
            if (S.result || S.resultLoading || S.readonlyRunId) return;
            const runId = S.live && S.live.runId;
            if (!runId || S.phase !== 'ENDED') return;
            S.resultLoading = true;
            window.AppConfig.engineGet('projects/' + encodeURIComponent(ctx.project.id)
                    + '/afo/sessions/' + encodeURIComponent(runId) + '/result')
                .then(resp => {
                    if (resp && (resp.success || resp.code === 200) && resp.data) {
                        S.result = resp.data;
                        renderAll();
                    }
                })
                .catch(() => { });
        }

        function renderAll() {
            paintStatus();
            paintTabs();
            paintBody();
            paintFoot();
        }
        /** 轮询轻更新:phase不变时只刷新状态条数字与总控,不重建输入框。 */
        function lightUpdate() {
            paintStatus();
            if (S.tab === 'main' && canCmd()) { paintBody(); }
            paintFoot();
        }

        /* —— 动作 —— */
        async function sendCmd(kind, value) {
            try {
                await apiPost('/command', { kind: kind, value: value });
                toast(kind === 'pause' ? '已请求暂停' : kind === 'resume' ? '已请求继续' : kind === 'stop' ? '已请求结束计算' : '命令已提交,等待主步生效', 'info');
                refresh();
            } catch (e) { toast('命令失败:' + e.message, 'error'); }
        }
        async function applyLoadDraft() {
            const inp = document.getElementById('afo-load-draft');
            const v = inp ? parseFloat(inp.value) : NaN;
            if (!isFinite(v)) { toast('请输入负载数值', 'error'); return; }
            const lm = S.cfg.loadMode;
            sendCmd('load', lm === 'dual_pitch' ? [v, parseFloat(S.cfg.tailPitchDeg)] : v);
        }
        async function startRun() {
            try {
                await apiPost('/run', {});
                toast('仿真已启动', 'success');
                startPoll();
            } catch (e) { toast('启动失败:' + e.message, 'error'); }
        }
        async function closeSession() {
            try {
                await apiPost('/close', {});
                toast('会话已关闭;可新建运行', 'success');
                S.phase = 'IDLE'; S.live = null; S.samples = []; S.lastSampleT = -1; S.message = '';
                renderAll();
            } catch (e) { toast('关闭失败:' + e.message, 'error'); }
        }
        function reuseConfig() {
            const r = S.result;
            if (r && r.config) {
                S.cfg = Object.assign({}, S.cfg, {
                    engineId: r.config.engineId, duration: r.config.duration, recordStep: r.config.recordStep,
                    pace: r.config.pace, loadMode: r.config.loadMode, powerW: r.config.powerW, mkpNm: r.config.mkpNm,
                    pitchDeg: r.config.pitchDeg, mainPitchDeg: r.config.mainPitchDeg, tailPitchDeg: r.config.tailPitchDeg,
                    externalAir: !!r.config.externalAir
                });
            }
            exitReadonly();
        }
        function exitReadonly() {
            S.readonlyRunId = null; S.result = null; S.tab = 'main'; S.phase = 'IDLE';
            S.live = null; S.samples = []; S.lastSampleT = -1; S.message = '';
            renderAll(); refresh();
        }

        /* —— 历史(记录只读):拉result.json —— */
        async function loadReadonly(runId) {
            S.readonlyRunId = runId;
            S.readonlyLoading = true;
            S.result = null;
            S.tab = 'main';
            renderAll();
            try {
                const resp = await api('/sessions/' + encodeURIComponent(runId) + '/result');
                if (resp && (resp.success || resp.code === 200) && resp.data) {
                    S.result = resp.data;
                } else {
                    toast((resp && resp.message) || '结果尚未生成', 'error');
                    S.readonlyRunId = null;
                }
            } catch (e) {
                toast('历史结果加载失败:' + e.message, 'error');
                S.readonlyRunId = null;
            }
            S.readonlyLoading = false;
            renderAll();
        }
        window.__WB_AFO_OPEN__ = runId => { S.tab = 'main'; loadReadonly(runId); };
        window.__WB_AFO_REUSE__ = rec => {
            const r = rec && rec.config ? rec : (S.result || {});
            const c = r.config || {};
            S.cfg = Object.assign({}, S.cfg, {
                engineId: c.engineId || S.cfg.engineId, duration: c.duration != null ? c.duration : S.cfg.duration,
                recordStep: c.recordStep != null ? c.recordStep : S.cfg.recordStep, pace: c.pace || S.cfg.pace,
                loadMode: c.loadMode || S.cfg.loadMode, powerW: c.powerW != null ? c.powerW : S.cfg.powerW,
                mkpNm: c.mkpNm != null ? c.mkpNm : S.cfg.mkpNm, pitchDeg: c.pitchDeg != null ? c.pitchDeg : S.cfg.pitchDeg,
                mainPitchDeg: c.mainPitchDeg != null ? c.mainPitchDeg : S.cfg.mainPitchDeg,
                tailPitchDeg: c.tailPitchDeg != null ? c.tailPitchDeg : S.cfg.tailPitchDeg,
                externalAir: !!c.externalAir
            });
            exitReadonly();
        };

        /* —— 轮询 —— */
        let polling = false;
        async function refresh() {
            if (polling) return;
            polling = true;
            try {
                const resp = await api('/status');
                const d = resp && (resp.success || resp.code === 200) && resp.data ? resp.data : {};
                const prev = S.phase;
                if (!S.readonlyRunId) {
                    S.phase = d.phase || 'IDLE';
                    S.message = d.message || '';
                    S.live = d.live || null;
                    if (S.live && typeof S.live.time === 'number') pushSample(S.live);
                }
                if (S.phase === 'ENDED' && !S.result) ensureSessionResult();
                if (S.phase !== prev) renderAll();
                else lightUpdate();
            } catch (e) { /* 轮询容错 */ }
            polling = false;
        }
        function startPoll() {
            if (window.__WB_AFO_TIMER__) clearInterval(window.__WB_AFO_TIMER__);
            window.__WB_AFO_TIMER__ = setInterval(() => {
                if (!S.readonlyRunId && ['PREPARING', 'READY', 'RUNNING', 'PAUSED', 'ENDED'].includes(S.phase)) {
                    window.__WB_ENGINE_POLL_UNTIL__ = Date.now() + 40000; // 活动心跳
                    refresh();
                }
            }, 2000);
        }

        if (window.__WB_AFO_TIMER__) clearInterval(window.__WB_AFO_TIMER__);
        window.__WB_AFO_TIMER__ = setInterval(() => {
            if (!S.readonlyRunId && ['PREPARING', 'READY', 'RUNNING', 'PAUSED', 'ENDED'].includes(S.phase)) refresh();
        }, 2000);
        renderAll();
        refresh();
        if (S.phase === 'ENDED') ensureSessionResult();
        return wrap;
    };
    pages['testbench.records'] = (ctx) => recordsPage(ctx, 'sim');

    /* ---------- API ---------- */
    return {
        ICONS, DEMO, WORKBENCHES, pages, h, toast,
        lineChart, chartLegend, dataTable, groupSeriesColumns, numericColumns, toNum,
        /** 渲染页面:workbenchKey + navKey → DOM */
        renderPage(workbenchKey, navKey, ctx) {
            const fn = pages[workbenchKey + '.' + navKey];
            return fn ? fn(ctx) : h('div', { class: 'wb-empty' }, '页面未注册');
        }
    };
})();
