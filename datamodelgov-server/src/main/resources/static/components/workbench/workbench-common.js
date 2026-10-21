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
            { id: 'transient', name: '过渡态试车建模', desc: '固定稳态父模型,选定大幅变化事件辨识13项瞬态系数(TC27 瞬态)', enabled: false },
            { id: 'flightSteady', name: '稳态飞参建模', desc: '从实际飞参提取有效稳态窗口,更新稳态及相关参数(F3 Start14)', enabled: false },
            { id: 'flightTransient', name: '过渡态飞参建模', desc: '选取飞行大幅事件,更新瞬态参数(F3 Start11/12/13)', enabled: false },
            { id: 'evolution', name: '发动机个性化模型自演化', desc: '从试车模型起步,逐架次更新并比较趋势与预测(Stage4)', enabled: false }
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
                { key: 'fullmode', label: '全模式仿真', icon: 'engine', badge: '建设中' },
                { key: 'afo', label: '多系统联合仿真', icon: 'joint', badge: '接入中' },
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
                    h('button', {
                        class: 'wb-btn wb-btn-outline disabled', title: 'TC27 试车数据更新(2.7)为F-02链路,程序入口Start_TC27_SteadyModelUpdate_01尚未接入'
                    }, '新增试车更新'))),
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
        const wrap = h('div', null, pageHeader('项目概况', ctx.project.name + ' / 系统联合仿真'));
        wrap.appendChild(h('div', { class: 'wb-section', style: 'display:grid;grid-template-columns:1fr 1fr;gap:20px' },
            h('div', { class: 'wb-card' },
                h('div', { class: 'wb-section-title' }, '多系统联合仿真'),
                h('div', { class: 'wb-hint', style: 'margin:8px 0 14px' }, 'AFO_V_2 · Dll_Control_AFO_V8_5_R2019b · 39 组 247 通道 + 4 回退标志'),
                h('span', { class: 'wb-tag wb-tag-amber' }, '接入中(V8_5 会话合同)'),
                h('div', { style: 'margin-top:14px' }, h('button', { class: 'wb-btn wb-btn-outline disabled' }, '进入'))),
            h('div', { class: 'wb-card' },
                h('div', { class: 'wb-section-title' }, '全模式仿真'),
                h('div', { class: 'wb-hint', style: 'margin:8px 0 14px' }, '三位置油门 · 五挡Np · 负载互斥 · 命令状态机 · 快照恢复(F-11)'),
                h('span', { class: 'wb-tag wb-tag-gray' }, '建设中'),
                h('div', { style: 'margin-top:14px' }, h('button', { class: 'wb-btn wb-btn-outline disabled' }, '进入')))));
        wrap.appendChild(h('div', { class: 'wb-section' },
            h('div', { class: 'wb-section-title', style: 'margin-bottom:12px' }, '仿真记录'),
            h('div', { class: 'wb-empty' }, '暂无仿真记录')));
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
    pages['testbench.fullmode'] = (ctx) => placeholderPage('全模式仿真', '准备初态与试车条件', '页面建设中',
        '将按 F-11 合同实现:仿真准备(模型/初态:停止·慢车·巡航·设计转速;负载方式:轴功率·Mkp扭矩·总距角互斥)→ 操纵与监视(三位置油门、五挡Np 80/90/95/100/105%、命令状态机:草稿→已提交→已接收→已施加/已拒绝)→ 本次结果(输出/全通道/热状态/命令/配置文件;Excel+快照MAT+manifest)。依据 R06《程序调用与独立使用手册》第13章。');
    pages['testbench.afo'] = (ctx) => placeholderPage('多系统联合仿真', 'AFO_V_2 · 总控 + 发动机/控制/燃油/滑油/空气', 'AFO_V_2(V8_5)接入中',
        '将按 F-12 合同实现:总控页(初始状态、常值输入、运行进度、关键输出)+ 五系统输出页;准备→运行→施加常值→暂停/继续→停止→保存→历史只读→配置比较。251 项通道(247 原始 + 4 回退标志)按系统分组显示,常用输出置顶、全量可检索。依据 R06《程序调用与独立使用手册》第14章 sht_afo_session 合同。');
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
