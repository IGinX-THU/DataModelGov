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

    /* ---------- 示例数据(静态展示;真实数据随域模型接入替换) ---------- */
    const DEMO = {
        project: { name: 'E-001 台架标定项目', engineId: 'E-001', engineDesc: '三部件模型', matlab: 'MATLAB R2019b' },
        tasks: [
            { name: '台架标定01', type: '稳态试车建模', lastRun: 'BENCH_01', status: '待配置', statusKind: 'amber', model: '尚未生成' }
        ],
        models: [
            { checked: false, name: 'M24-S01', ver: '基础模型 · 稳态方程', stage: '2.4 基础建模', path: '稳态方程', data: 'D01', parent: '基准配置', status: '结果已保存', statusKind: '', uq: '未评估', uqKind: 'gray' },
            { checked: false, name: 'M24-T01', ver: '基础模型 · 瞬态时刻方程', stage: '2.4 基础建模', path: '瞬态时刻方程', data: 'D01', parent: '基准配置', status: '结果已保存', statusKind: '', uq: '3份记录\n2采样/1局部近似', uqKind: 'teal' },
            { checked: false, name: 'M27-S-I01', ver: '新增数据更新 · 方法Ⅰ', stage: '2.7 数据更新', path: '稳态方程', data: 'D01 + D02', parent: 'M24-S01', status: '并列方案示例', statusKind: '', uq: '未评估', uqKind: 'gray' },
            { checked: false, name: 'M27-S-II01', ver: '新增数据更新 · 方法Ⅱ', stage: '2.7 数据更新', path: '稳态方程', data: 'D01 + D02', parent: 'M24-S01', status: '并列方案示例', statusKind: '', uq: '未评估', uqKind: 'gray' },
            { checked: false, name: 'M27-T-I01', ver: '新增数据更新 · 方法Ⅰ', stage: '2.7 数据更新', path: '瞬态时刻方程', data: 'D01 + D02', parent: 'M24-T01', status: '并列方案示例', statusKind: '', uq: '未评估', uqKind: 'gray' },
            { checked: true, name: 'M27-T-II01', ver: '新增数据更新 · 方法Ⅱ', stage: '2.7 数据更新', path: '瞬态时刻方程', data: 'D01 + D02', parent: 'M24-T01', status: '已交付', statusKind: 'teal', uq: 'UQ-27D01 · 非驻点局部近似', uqKind: 'teal' }
        ],
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

    /** 导入模型:选择 Excel 上传到项目目录并登记为模型成果(与导入数据同机制)。 */
    function importModel(ctx) {
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

    /* ===== 个性化建模 · 模型成果(图 02-01)===== */
    pages['modeling.models'] = (ctx) => {
        const wrap = h('div', null, pageHeader('模型成果', ctx.project.engineId + ' / 稳态试车建模 / 模型版本与数据、评估关联'));
        const tableHolder = h('div', null, h('div', { class: 'wb-empty' }, '正在加载模型成果...'));
        wrap.appendChild(tableHolder);
        if (ctx.project.id) loadRealModels(ctx, wrap, tableHolder); else renderDemoModels(ctx, wrap, tableHolder);
        return wrap;
    };

    function loadRealModels(ctx, wrap, holder) {
        window.AppConfig.engineGet('projects/' + encodeURIComponent(ctx.project.id) + '/models')
            .then(resp => {
                const models = resp && resp.data;
                if (!Array.isArray(models)) throw new Error('bad resp');
                holder.innerHTML = '';
                if (!models.length) {
                    holder.appendChild(h('div', { class: 'wb-empty' },
                        '暂无模型成果——完成一次稳态辨识并保存后在此查看。'));
                    return;
                }
                const table = h('table', { class: 'wb-table' },
                    h('tr', null, ['模型名称', '来源阶段', '计算路径', '交付文件', '创建时间'].map(t => h('th', null, t))),
                    models.map(m => h('tr', { class: 'clickable' },
                        h('td', { style: 'font-weight:600;color:#111827' }, m.name),
                        h('td', null, m.stage || '—'),
                        h('td', null, m.route || '—'),
                        h('td', { class: 'wb-hint', style: 'margin:0;word-break:break-all' },
                            m.deliveryWorkbookFile ? m.deliveryWorkbookFile.split(/[\/]/).pop() : '—'),
                        h('td', { class: 'wb-hint', style: 'margin:0' },
                            m.createdAt ? new Date(m.createdAt).toLocaleString() : '—'))));
                holder.appendChild(table);
            })
            .catch(() => renderDemoModels(ctx, wrap, holder));
    }

    function renderDemoModels(ctx, wrap, holder) {
        const rows = DEMO.models.map(m => h('tr', { class: 'clickable' + (m.checked ? ' selected' : '') },
            h('td', null, h('input', { type: 'checkbox', ...(m.checked ? { checked: '' } : {}) })),
            h('td', null, h('div', { style: 'font-weight:600;color:#111827' }, m.name), h('div', { style: 'font-size:11px;color:#9ca3af' }, m.ver)),
            h('td', null, m.stage), h('td', null, m.path), h('td', null, m.data), h('td', null, m.parent),
            h('td', null, statusTag(m.status, m.statusKind)),
            h('td', null, m.uq.split('\n').map((line, i) => h('div', { style: 'font-size:12px;' + (i ? 'color:#9ca3af' : '') }, line)))));
        const sel = DEMO.models.find(m => m.checked) || DEMO.models[0];
        holder.innerHTML = '';
        holder.appendChild(h('div', { class: 'wb-section' },
            h('div', { class: 'wb-filter-bar' },
                ['业务类别:稳态试车建模', '来源阶段:2.4 与 2.7', '计算路径:全部路径', '模型名称:全部模型'].map(txt => {
                    const [label, val] = txt.split(':');
                    return h('div', { class: 'wb-field' }, h('label', null, label), h('select', null, h('option', null, val)));
                }),
                h('button', { class: 'wb-btn wb-btn-outline' }, '导入离线模型成果')),
            h('table', { class: 'wb-table' },
                h('tr', null, ['', '模型名称 / 版本', '来源阶段', '计算路径', '训练数据', '父模型', '结果状态', '不确定性评估'].map(t => h('th', null, t))),
                rows),
            h('div', { class: 'wb-detail-strip' },
                h('div', { class: 'wb-detail-main' }, '已选 ' + sel.name),
                h('div', { class: 'wb-detail-item' }, sel.ver.split('·')[1] + ';稳态系数更新;瞬态系数固定'),
                h('div', { class: 'wb-detail-item' }, '原数据 D01 + 新数据 D02'),
                h('div', { class: 'wb-detail-item' }, '父模型 ', h('b', null, sel.parent)),
                h('div', { class: 'wb-detail-item wb-tag-teal' }, sel.uq)),
            h('div', { class: 'wb-actions-row' },
                h('button', { class: 'wb-btn wb-btn-primary' }, '查看模型详情'),
                h('button', { class: 'wb-btn wb-btn-outline' }, '查看来源关系'),
                h('div', { class: 'wb-spacer' }),
                h('button', { class: 'wb-btn wb-btn-outline disabled' }, '比较已选模型'),
                h('button', { class: 'wb-btn wb-btn-outline' }, '新工况预测'))));
        wrap.appendChild(h('div', { class: 'wb-hint' }, '查看行 / 比较复选 / 下游选择为三种独立操作;列表为示例数据,将随域模型落库切换为真实记录。'));
        return wrap;
    };

    /* ===== 个性化建模 · 输出预测(图 01-11 简化)===== */
    pages['modeling.predictions'] = (ctx) => {
        const wrap = h('div', null, pageHeader('输出预测', '独立稳态工况预测:选择模型,给定环境、燃油及负载,由模型自主输出'));
        const field = (label, val, hint) => h('div', { class: 'wb-field' }, h('label', null, label),
            h('input', { value: val || '', placeholder: '—' }), hint ? h('div', { class: 'wb-hint' }, hint) : null);
        wrap.appendChild(h('div', { class: 'wb-section', style: 'display:grid;grid-template-columns:1fr 1fr;gap:22px' },
            h('div', { class: 'wb-card' },
                h('div', { class: 'wb-section-title', style: 'margin-bottom:14px' }, '预测输入'),
                h('div', { class: 'wb-form-grid' },
                    h('div', { class: 'wb-field', style: 'grid-column:1/-1' }, h('label', null, '预测模型'),
                        h('select', null, h('option', null, 'M24-S01 · 稳态方程 · 结果已保存'))),
                    field('Pt1 总压 / Pa', '101325'), field('Tt1 总温 / K', '288.15'),
                    field('Pamb 环境压力 / Pa', '101325'), field('Wf 物理燃油 / kg·s⁻¹', '1.20', '物理燃油不扣测量偏置'),
                    field('Mkp 负载扭矩 / N·m', '320.0'), field('Mkg 附件负载 / N·m', '0.0', '当前 Mkg=0 为模型限制')),
                h('div', { class: 'wb-actions-row' },
                    h('button', { class: 'wb-btn wb-btn-primary' }, '开始预测'),
                    h('button', { class: 'wb-btn wb-btn-outline' }, '保存为预测记录'))),
            h('div', { class: 'wb-card' },
                h('div', { class: 'wb-section-title', style: 'margin-bottom:14px' }, '预测结果'),
                h('div', { class: 'wb-empty' }, '尚未计算——配置输入后开始预测。空白不代表零误差。'),
                h('div', { class: 'wb-hint', style: 'margin-top:12px' },
                    '预测记录含输入、确定性输出、物理有效状态、模型身份、可选UQ来源及实际区间;没有观测时不显示预测误差。'))));
        return wrap;
    };

    /* ===== 运行记录 / 仿真记录 ===== */
    function recordsPage(ctx, scope) {
        const isSim = scope === 'sim';
        const wrap = h('div', null, pageHeader(isSim ? '仿真记录' : '运行记录',
            isSim ? '全模式仿真与多系统联合仿真的执行记录;历史只读' : '建模任务执行历史;保存失败与计算失败分开显示'));
        wrap.appendChild(h('div', { class: 'wb-section' },
            h('div', { class: 'wb-empty' }, isSim ? '暂无仿真记录' : '暂无运行记录')));
        wrap.appendChild(h('div', { class: 'wb-hint' }, '记录将包含:任务身份、五类状态(执行/收敛/物理有效/统计质量/导出)、耗时分解与产物清单。'));
        return wrap;
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
        ICONS, DEMO, WORKBENCHES, pages, h,
        /** 渲染页面:workbenchKey + navKey → DOM */
        renderPage(workbenchKey, navKey, ctx) {
            const fn = pages[workbenchKey + '.' + navKey];
            return fn ? fn(ctx) : h('div', { class: 'wb-empty' }, '页面未注册');
        }
    };
})();
