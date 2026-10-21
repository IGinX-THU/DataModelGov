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
            node.appendChild(typeof c === 'string' ? document.createTextNode(c) : c);
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

    function toast(msg, kind) {
        if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast(msg, kind || 'info');
        else console.log('[workbench]', msg);
    }

    /** 模型交付文件下载地址(带 token;import() 场景同插件认证约定)。 */
    function modelDownloadUrl(pid, mid) {
        const cfg = window.AppConfig;
        return cfg.api.baseURL + '/api/engine/projects/' + encodeURIComponent(pid)
            + '/models/' + encodeURIComponent(mid) + '/file?token=' + encodeURIComponent(cfg.getToken() || '');
    }

    /* ===== 个性化建模 · 项目概况(图 01-02;任务/模型为真实接口数据)===== */
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
                        class: 'wb-btn wb-btn-outline disabled', title: 'TC27 试车数据更新(2.7)后行接入',
                        onclick: () => window.CommonUtils && window.CommonUtils.showToast &&
                            window.CommonUtils.showToast('TC27 试车数据更新(2.7)后行接入', 'info')
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
                            onclick: () => ctx.enterTask({ id: 'steady', name: '基础稳态点建模' })
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

    /** 导入模型:选择 Excel 上传到项目目录并登记为模型成果(与导入数据同机制);完成后回调刷新。 */
    function importModel(ctx, done) {
        if (!ctx.project || !ctx.project.id) {
            window.CommonUtils && window.CommonUtils.showToast &&
                window.CommonUtils.showToast('本地演示项目不支持导入;请进入真实项目', 'error');
            return;
        }
        const input = document.createElement('input');
        input.type = 'file';
        input.accept = '.xlsx,.xls';
        input.addEventListener('change', async () => {
            const f = input.files && input.files[0];
            if (!f) return;
            const fd = new FormData();
            fd.append('file', f);
            window.CommonUtils && window.CommonUtils.showToast &&
                window.CommonUtils.showToast('正在导入:' + f.name, 'info');
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

    /* ===== 个性化建模 · 模型成果(真实登记记录;下载/用于预测)===== */
    pages['modeling.models'] = (ctx) => {
        const wrap = h('div', null, pageHeader('模型成果', ctx.project.engineId + ' / 稳态试车建模 / 模型版本与数据、评估关联'));
        const tableHolder = h('div', null, h('div', { class: 'wb-empty' }, '正在加载模型成果...'));
        wrap.appendChild(h('div', { class: 'wb-section' },
            h('div', { class: 'wb-section-head' },
                h('div', { class: 'wb-section-title' }, '已登记模型'),
                h('div', { style: 'display:flex;gap:10px' },
                    h('button', { class: 'wb-btn wb-btn-outline', onclick: () => ctx.navigate('models') }, '刷新'),
                    h('button', { class: 'wb-btn wb-btn-primary', onclick: () => importModel(ctx, () => ctx.navigate('models')) }, '导入模型'))),
            tableHolder));
        loadRealModels(ctx, tableHolder);
        return wrap;
    };

    async function loadRealModels(ctx, holder) {
        holder.innerHTML = '';
        try {
            const resp = await window.AppConfig.engineGet('projects/' + encodeURIComponent(ctx.project.id) + '/models');
            const models = resp && (resp.success || resp.code === 200) && Array.isArray(resp.data) ? resp.data : null;
            if (!models) throw new Error((resp && resp.message) || '接口返回异常');
            if (!models.length) {
                holder.appendChild(h('div', { class: 'wb-empty' },
                    '暂无模型成果——完成一次稳态辨识并"登记到模型成果"后在此查看;也可直接"导入模型"。'));
                return;
            }
            const rows = models.map(m => h('tr', null,
                h('td', { style: 'font-weight:600;color:#111827' }, m.name || m.id),
                h('td', null, m.stage || '—'),
                h('td', null, m.route || '—'),
                h('td', { class: 'wb-hint', style: 'word-break:break-all' },
                    m.deliveryWorkbookFile ? m.deliveryWorkbookFile.split(/[\\/]/).pop() : '—'),
                h('td', { class: 'wb-hint' }, m.createdAt ? new Date(m.createdAt).toLocaleString() : '—'),
                h('td', { style: 'white-space:nowrap' },
                    m.deliveryWorkbookFile
                        ? h('a', { class: 'wb-btn wb-btn-outline', href: modelDownloadUrl(ctx.project.id, m.id) }, '下载')
                        : h('span', { class: 'wb-hint' }, '无交付文件'),
                    ' ',
                    h('button', {
                        class: 'wb-btn wb-btn-primary',
                        onclick: () => {
                            window.__WB_PREDICT_MODEL__ = m;
                            ctx.navigate('predictions');
                        }
                    }, '用于预测'))));
            holder.appendChild(h('table', { class: 'wb-table' },
                h('tr', null, ['模型名称', '来源阶段', '计算路径', '交付文件', '登记时间', '操作'].map(t => h('th', null, t))),
                rows));
        } catch (e) {
            holder.appendChild(h('div', { class: 'wb-empty' }, '模型成果加载失败:' + e.message));
        }
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
        const wrap = h('div', null, pageHeader('输出预测',
            '独立稳态工况预测:选择已登记模型,给定环境、燃油及负载,由模型自主输出(不使用目标测量,不经控制闭环)'));

        // 左:预测输入;右:预测结果
        const modelSel = h('select', { style: 'width:100%' });
        const modeSel = h('select', { style: 'width:100%' }, Object.keys(PREDICT_FIELDS).map(k =>
            h('option', { value: k }, PREDICT_FIELDS[k].label)));
        const inputGrid = h('div', { class: 'wb-form-grid', style: 'margin-top:12px' });
        const runBtn = h('button', { class: 'wb-btn wb-btn-primary disabled' }, '开始预测');
        const resultHolder = h('div', null, h('div', { class: 'wb-empty' }, '尚未计算——配置输入后开始预测。空白不代表零误差。'));
        const historyHolder = h('div', null);
        const pre = window.__WB_PREDICT_MODEL__;
        delete window.__WB_PREDICT_MODEL__;

        function rebuildInputs() {
            const mode = modeSel.value;
            inputGrid.innerHTML = '';
            PREDICT_FIELDS[mode].fields.forEach(name => {
                const unit = PREDICT_UNITS[name] && PREDICT_UNITS[name] !== '—' ? ' / ' + PREDICT_UNITS[name] : '';
                inputGrid.appendChild(h('div', { class: 'wb-field' },
                    h('label', null, name + unit),
                    h('input', { 'data-pred': name, value: PREDICT_DEFAULTS[name] || '' })));
            });
        }
        modeSel.addEventListener('change', rebuildInputs);
        rebuildInputs();

        async function loadModels() {
            modelSel.innerHTML = '';
            try {
                const resp = await window.AppConfig.engineGet('projects/' + encodeURIComponent(ctx.project.id) + '/models');
                const models = resp && (resp.success || resp.code === 200) && Array.isArray(resp.data) ? resp.data : [];
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
            } catch (e) {
                modelSel.appendChild(h('option', { value: '' }, '模型列表加载失败'));
                runBtn.classList.add('disabled');
            }
        }

        runBtn.addEventListener('click', async () => {
            const modelId = modelSel.value;
            if (!modelId) { toast('请先选择模型', 'error'); return; }
            const inputs = {};
            let bad = null;
            inputGrid.querySelectorAll('input[data-pred]').forEach(inp => {
                const v = parseFloat(inp.value);
                if (isNaN(v)) bad = inp.getAttribute('data-pred');
                inputs[inp.getAttribute('data-pred')] = v;
            });
            if (bad) { toast('输入项 ' + bad + ' 必须为数值', 'error'); return; }
            inputs.inletBoundaryMode = parseInt(modeSel.value, 10);
            runBtn.classList.add('disabled');
            runBtn.textContent = '预测执行中...';
            try {
                const resp = await window.AppConfig.enginePost(
                    'projects/' + encodeURIComponent(ctx.project.id) + '/predict?modelAssetId=' + encodeURIComponent(modelId), inputs);
                if (resp && (resp.success || resp.code === 200) && resp.data) {
                    toast('预测已发起,程序计算中...', 'info');
                    pollPrediction(resp.data.id, () => {
                        runBtn.classList.remove('disabled');
                        runBtn.textContent = '开始预测';
                    });
                } else {
                    throw new Error((resp && resp.message) || '发起失败');
                }
            } catch (e) {
                toast('发起输出预测失败:' + e.message, 'error');
                runBtn.classList.remove('disabled');
                runBtn.textContent = '开始预测';
            }
        });

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
                resultHolder.appendChild(h('div', { class: 'wb-hint', style: 'margin-bottom:8px' }, '运行标识 ' + rec.runId));
            }
            const r = rec.result || {};
            const box = renderValue(r, false);
            resultHolder.appendChild(box);
            if (Array.isArray(r.outputFiles) && r.outputFiles.length) {
                resultHolder.appendChild(h('div', { class: 'wb-hint', style: 'margin-top:8px' },
                    '输出文件: ' + r.outputFiles.join(' , ')));
            }
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
                    h('tr', null, ['时间', '模型', '输入摘要', '运行标识', '状态'].map(t => h('th', null, t))),
                    list.slice(0, 20).map(r => h('tr', { class: 'clickable', onclick: () => renderLatest(r) },
                        h('td', { class: 'wb-hint' }, r.createdAt ? new Date(r.createdAt).toLocaleString() : '—'),
                        h('td', null, r.modelName || '—'),
                        h('td', { class: 'wb-hint', style: 'word-break:break-all' }, inputSummary(r.inputs)),
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

        wrap.appendChild(h('div', { class: 'wb-section', style: 'display:grid;grid-template-columns:1fr 1fr;gap:22px' },
            h('div', { class: 'wb-card' },
                h('div', { class: 'wb-section-title', style: 'margin-bottom:14px' }, '预测输入'),
                h('div', { class: 'wb-field' }, h('label', null, '预测模型(已登记)'), modelSel),
                h('div', { class: 'wb-field', style: 'margin-top:10px' }, h('label', null, '环境边界输入方式'), modeSel),
                inputGrid,
                h('div', { class: 'wb-actions-row', style: 'margin-top:14px' }, runBtn)),
            h('div', { class: 'wb-card' },
                h('div', { class: 'wb-section-title', style: 'margin-bottom:14px' }, '预测结果'),
                resultHolder)));
        wrap.appendChild(h('div', { class: 'wb-section' },
            h('div', { class: 'wb-section-title', style: 'margin-bottom:12px' }, '预测记录(点击行查看结果)'),
            historyHolder));
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
            const resp = await window.AppConfig.engineGet('projects/detail', { projectId: ctx.project.id });
            const tasks = resp && (resp.success || resp.code === 200) && resp.data && Array.isArray(resp.data.tasks)
                ? resp.data.tasks : null;
            if (!tasks) throw new Error((resp && resp.message) || '接口返回异常');
            if (!tasks.length) {
                holder.appendChild(h('div', { class: 'wb-empty' }, '暂无运行记录——发起数据准备或辨识后在此查看。'));
                return;
            }
            holder.appendChild(h('table', { class: 'wb-table' },
                h('tr', null, ['任务', '运行标识', '状态', '开始时间', '结束时间', '耗时', '消息'].map(t => h('th', null, t))),
                tasks.map(t => {
                    const st = RUN_STATUS[t.status] || [t.status || '—', 'gray'];
                    const dur = t.startedAt && t.finishedAt ? fmtSpan(t.finishedAt - t.startedAt) : '—';
                    return h('tr', null,
                        h('td', { style: 'font-weight:600;color:#111827' }, t.name || t.id),
                        h('td', { class: 'wb-hint' }, t.runId || '—'),
                        h('td', null, statusTag(st[0], st[1])),
                        h('td', { class: 'wb-hint' }, t.startedAt ? new Date(t.startedAt).toLocaleString() : '—'),
                        h('td', { class: 'wb-hint' }, t.finishedAt ? new Date(t.finishedAt).toLocaleString() : '—'),
                        h('td', { class: 'wb-hint' }, dur),
                        h('td', { class: 'wb-hint', style: 'word-break:break-all;max-width:360px' }, t.message || '—'));
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
        /** 渲染页面:workbenchKey + navKey → DOM */
        renderPage(workbenchKey, navKey, ctx) {
            const fn = pages[workbenchKey + '.' + navKey];
            return fn ? fn(ctx) : h('div', { class: 'wb-empty' }, '页面未注册');
        }
    };
})();
