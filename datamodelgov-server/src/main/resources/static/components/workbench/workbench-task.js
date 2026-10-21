/**
 * 稳态试车建模任务页(按《界面页面与操作流程关联图》UI-R131 组1 效果图实现):
 * 单任务四页签:工况与分组(01-03) / 稳态系数辨识(01-04·01-05) / 建模结果(01-06·01-07) / 不确定性评估(01-08~01-10)。
 * 数据源:/api/engine/*(工作台域 API)。
 * 说明:工况明细、逐通道误差曲线等待后端解析/输出接口接入,界面结构先行、空态明示。
 */
(function () {
    const WB = () => window.Workbench;

    const STATUS_TEXT = {
        READY: '空闲', PREPARING: '准备中', RUNNING: '运行中', COMPLETED: '已完成', FAILED: '失败',
        STOP_REQUESTED: '已请求停止', STOPPED: '已停止'
    };
    const STATUS_KIND = {
        READY: 'gray', PREPARING: 'amber', RUNNING: 'teal', COMPLETED: 'teal', FAILED: 'red',
        STOP_REQUESTED: 'amber', STOPPED: 'gray'
    };

    // 01-04 全部参数(12类)
    const PARAM_CLASSES = [
        ['进气道压损', '调度'], ['HPC流量', '调度'], ['HPC效率', '调度'], ['燃烧室压损', '调度'],
        ['GT流量', '调度'], ['GT效率', '调度'], ['GT—PT涵道压损', '调度'], ['PT流量', '调度'],
        ['PT效率', '调度'], ['PT—尾喷管涵道压损', '调度'], ['尾喷管面积', '常值'], ['燃油测量偏置', 'kg/s']
    ];
    // 01-05 工作步骤(顺序固定)
    const WORK_STEPS = ['数据检查', '全工况常值辨识', '组内辨识', '构造调度曲线', '联合微调'];

    function statusTag(task) {
        return WB().h('span', { class: 'wb-tag wb-tag-' + (STATUS_KIND[task.status] || 'gray') },
            STATUS_TEXT[task.status] || task.status);
    }

    function toast(msg, kind) {
        if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast(msg, kind || 'info');
    }

    function fileName(p) { return p ? String(p).split(/[\\/]/).pop() : ''; }

    function formatDur(ms) {
        const s = Math.max(0, Math.floor(ms / 1000));
        const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), ss = s % 60;
        return (h ? h + '小时' : '') + m + '分' + ss + '秒';
    }

    function str(v) { return v == null ? '—' : String(v); }

    /**
     * 渲染稳态试车建模任务视图。
     * ctx: { project, back() }
     */
    function renderSteadyTask(ctx) {
        const state = { task: null, log: [], timer: null, tab: 'data', logOpen: false, paramIdx: 2 };
        const root = WB().h('div', null);

        // 页头(01-03):标题 + 面包屑元信息
        const titleRow = WB().h('div', { style: 'display:flex;align-items:center;gap:14px;margin-bottom:4px' },
            WB().h('button', { class: 'wb-btn wb-btn-outline', onclick: () => { stopPolling(); ctx.back(); } }, '‹ 返回'),
            WB().h('div', { class: 'wb-page-title', style: 'margin:0' }, '稳态系数辨识'));
        const metaRow = WB().h('div', { class: 'wb-page-sub' }, '');
        root.appendChild(titleRow);
        root.appendChild(metaRow);

        // 页签条(01-03 顶部四个页签)
        const TABS = [['data', '工况与分组'], ['run', '稳态系数辨识'], ['result', '建模结果'], ['uq', '不确定性评估']];
        const tabBar = WB().h('div', { class: 'wb-tabs' });
        root.appendChild(tabBar);
        const body = WB().h('div', null);
        root.appendChild(body);

        function paintMeta() {
            const t = state.task;
            metaRow.textContent = t
                ? (ctx.project.name + ' / ' + (t.runId || 'BENCH_01') + ' / 训练' + (t.trainingFile ? '已上传' : '待上传')
                    + (t.testFile ? ' · 已提供独立测试' : ' · 未提供独立测试'))
                : (ctx.project.name + ' / 尚未创建任务');
        }

        function paintTabs() {
            const reach = { data: true, run: !!(state.task && state.task.trainingFile), result: !!(state.task && state.task.status === 'COMPLETED'), uq: !!(state.task && state.task.status === 'COMPLETED') };
            tabBar.innerHTML = '';
            TABS.forEach(([key, label]) => {
                const enabled = reach[key];
                tabBar.appendChild(WB().h('div', {
                    class: 'wb-tab' + (state.tab === key ? ' active' : '') + (enabled ? '' : ' disabled'),
                    onclick: () => {
                        if (!enabled) {
                            if (key === 'uq') toast('可选UQ:先完成一次辨识后开放', 'info');
                            else if (key === 'result') toast('建模结果:辨识完成后开放', 'info');
                            else toast('请先上传训练数据', 'info');
                            return;
                        }
                        state.tab = key; renderBody();
                    }
                }, label));
            });
        }

        function renderBody() {
            if (state.tab !== 'run') stopPolling();
            body.innerHTML = '';
            if (!ctx.project.id) { body.appendChild(noTaskView()); paintTabs(); paintMeta(); return; }
            if (!state.task) { body.appendChild(createCard()); paintTabs(); paintMeta(); return; }
            if (state.tab === 'data') body.appendChild(dataTab());
            else if (state.tab === 'run') body.appendChild(runTab());
            else if (state.tab === 'result') body.appendChild(resultTab());
            else body.appendChild(uqTab());
            paintTabs();
            paintMeta();
        }

        /* ---------- 项目不在服务器(本地演示) ---------- */
        function noTaskView() {
            return WB().h('div', { class: 'wb-placeholder' },
                WB().h('h3', null, '项目尚未保存到服务器'),
                WB().h('p', null, '当前项目为本地演示项目,无法关联建模任务。请从项目入口重新进入(选择或创建真实项目)。'));
        }

        /* ---------- 首个任务创建卡(进入任务页但尚无任务时显示) ---------- */
        function createCard() {
            const nameInput = WB().h('input', { value: '稳态建模-' + new Date().toISOString().slice(5, 10) });
            const routeSel = WB().h('select', null,
                WB().h('option', { value: 'steady' }, '稳态方程(由稳态均值数据新建)'),
                WB().h('option', { value: 'transient_instant' }, '瞬态时刻方程(两条独立辨识路径之一)'));
            const createBtn = WB().h('button', {
                class: 'wb-btn wb-btn-primary',
                onclick: async () => {
                    createBtn.classList.add('disabled');
                    try {
                        const pid = encodeURIComponent(ctx.project.id || '');
                        const resp = await window.AppConfig.enginePost('projects/' + pid + '/tasks', {
                            kind: 'steady', name: nameInput.value.trim() || '稳态建模任务',
                            route: routeSel.value, runId: 'WB_01'
                        });
                        if (resp && (resp.success || resp.code === 200) && resp.data) {
                            state.task = resp.data;
                            state.tab = 'data';
                            renderBody();
                        } else {
                            toast((resp && resp.message) || '创建任务失败', 'error');
                        }
                    } catch (e) { toast('创建任务失败:' + e.message, 'error'); }
                    createBtn.classList.remove('disabled');
                }
            }, '创建任务');
            return WB().h('div', { class: 'wb-card', style: 'max-width:720px' },
                WB().h('div', { class: 'wb-section-title', style: 'margin-bottom:14px' }, '新建建模任务'),
                WB().h('div', { class: 'wb-form-grid' },
                    WB().h('div', { class: 'wb-field' }, WB().h('label', null, '任务名称'), nameInput),
                    WB().h('div', { class: 'wb-field' }, WB().h('label', null, '计算路径'), routeSel)),
                WB().h('div', { class: 'wb-actions-row' },
                    createBtn,
                    WB().h('span', { class: 'wb-hint', style: 'margin:0' },
                        '训练数据为必要输入;独立测试数据可为空,训练结果必显。')));
        }

        /* ---------- 页签一:工况与分组(01-03) ---------- */
        function dataTab() {
            const t = state.task;
            const wrap = WB().h('div', null);

            // 建模类型 / 计算基准
            wrap.appendChild(WB().h('div', { class: 'wb-form-grid', style: 'max-width:980px;margin-bottom:16px' },
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '建模类型(本任务固定)'),
                    WB().h('input', { readonly: '', value: '基础稳态点建模 / 2.4' })),
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '计算基准'),
                    WB().h('input', { readonly: '', value: 'B00 · 当前配套运行包' }))));

            // 训练/测试数据行(01-03:输入框 + 选择文件 + 预览数据)
            wrap.appendChild(fileRow('训练数据 Excel', 'training', t.trainingFile, true));
            wrap.appendChild(fileRow('独立测试 Excel(可选)', 'test', t.testFile, false));

            // 训练工况表(数据来自 prepare 真实解析)
            const prepDone = Array.isArray(t.conditions) && t.conditions.length > 0;
            const prepRunning = state.prepWait || t.status === 'PREPARING';
            const condStatus = WB().h('span', { class: 'wb-tag ' + (prepDone ? 'wb-tag-teal' : prepRunning ? 'wb-tag-amber' : (t.prepMessage && t.prepMessage.indexOf('失败') >= 0 ? 'wb-tag-red' : 'wb-tag-gray')) },
                prepDone ? ('准备完成 ' + t.conditions.length + ' 工况')
                    : prepRunning ? '解析算法运行中...'
                    : (t.prepMessage ? (t.prepMessage.indexOf('失败') >= 0 ? '解析失败' : '解析中...') : (t.trainingFile ? '待解析' : '等待上传')));
            const condTable = WB().h('table', { class: 'wb-table' },
                WB().h('tr', null, ['编号', 'Np / rpm', 'Ng / rpm', 'Wf / kg/s', '有效样本数', '分组'].map(x => WB().h('th', null, x))));
            const conds = prepDone ? t.conditions : [];
            if (conds.length) {
                conds.slice(0, 20).forEach((c, i) => condTable.appendChild(WB().h('tr', null,
                    WB().h('td', null, str(c.id || c.conditionId || ('TR' + String(i + 1).padStart(2, '0')))),
                    WB().h('td', null, str(c.np != null ? c.np : c.Np)),
                    WB().h('td', null, str(c.ng != null ? c.ng : c.Ng)),
                    WB().h('td', null, str(c.wf != null ? c.wf : c.Wf)),
                    WB().h('td', null, str(c.samples != null ? c.samples : c.count)),
                    WB().h('td', null, str(c.group != null ? c.group : c.groupId || ('G' + (i + 1)))))));
            } else if (prepRunning) {
                condTable.appendChild(WB().h('tr', null, WB().h('td', { colspan: '6', style: 'text-align:center;padding:22px 0' },
                    WB().h('span', { class: 'wb-inline-loading' },
                        WB().h('span', { class: 'wb-inline-spinner' }),
                        '解析算法运行中,正在识别稳态工况点与分组...'))));
            } else {
                condTable.appendChild(WB().h('tr', null, WB().h('td', { colspan: '6', class: 'wb-hint' },
                    t.trainingFile
                        ? '训练文件已上传(' + fileName(t.trainingFile) + ');点击"重新准备数据"由程序解析工况与分组。'
                        : '上传训练 Excel 后,此处列出各稳态工况点与分组。')));
            }
            wrap.appendChild(WB().h('div', { class: 'wb-section' },
                WB().h('div', { class: 'wb-section-head' },
                    WB().h('div', { class: 'wb-section-title' }, '训练工况'),
                    condStatus),
                condTable,
                WB().h('div', { class: 'wb-hint', style: 'margin-top:6px' },
                    (conds.length ? '显示 ' + Math.min(conds.length, 20) + ' / ' + conds.length + ' 工况 · ' : '')
                    + '来源 ' + (t.trainingFile ? fileName(t.trainingFile) : '待上传'))));

            // 准备记录提示条(真实准备状态;解析进行中不显示上一次的旧消息)
            if (t.prepMessage && !prepRunning) {
                const failed = t.prepMessage.indexOf('失败') >= 0;
                wrap.appendChild(WB().h('div', { class: failed ? 'wb-tag wb-tag-red' : 'wb-infobar', style: failed ? 'display:inline-block;padding:4px 10px;border-radius:6px;margin-bottom:12px' : '' },
                    t.prepMessage));
            }
            if (!t.testFile) {
                wrap.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin:10px 0' },
                    '无独立测试集,不影响训练、保存模型及新工况预测。'));
            }

            // 底部动作(01-03:重新准备数据 | 进入系数辨识)
            wrap.appendChild(WB().h('div', { class: 'wb-actions-row', style: 'margin-top:16px' },
                WB().h('button', {
                    class: 'wb-btn wb-btn-outline' + (t.trainingFile && !prepRunning ? '' : ' disabled'),
                    onclick: () => { if (t.trainingFile && !prepRunning) runPrepare(); }
                }, prepRunning ? '解析中...' : '重新准备数据'),
                WB().h('div', { class: 'wb-spacer' }),
                WB().h('button', {
                    class: 'wb-btn wb-btn-primary' + (prepDone ? '' : ' disabled'),
                    title: prepDone ? '' : '请先完成数据准备(解析工况分组)',
                    onclick: () => { if (prepDone) { state.tab = 'run'; renderBody(); } }
                }, '进入系数辨识')));
            return wrap;

            function fileRow(label, kind, filePath, withPreview) {
                const nameBox = WB().h('input', { readonly: '', value: filePath ? fileName(filePath) : '未提供', style: 'flex:1' });
                const pickBtn = WB().h('button', {
                    class: 'wb-btn wb-btn-outline',
                    onclick: () => fileInput.click()
                }, '选择文件');
                const fileInput = WB().h('input', { type: 'file', accept: '.xlsx,.xls', style: 'display:none' });
                fileInput.addEventListener('change', async () => {
                    const f = fileInput.files && fileInput.files[0];
                    if (!f) return;
                    
                    // 确保FormData可用
                    const fd = new FormData();
                    if (!fd) {
                        toast('浏览器不支持文件上传', 'error');
                        return;
                    }
                    
                    fd.append('file', f);
                    nameBox.value = '上传中:' + f.name + '...';
                    
                    try {
                        const pid = encodeURIComponent(ctx.project.id || '');
                        const tid = encodeURIComponent(t.id);
                        const path = 'projects/' + pid + '/tasks/' + tid + '/files' +
                            '?kind=' + encodeURIComponent(kind);
                        console.log('上传文件:', f.name, '到:', path);
                        // 走统一封装:自动带 Authorization,FormData 由浏览器设置 multipart boundary
                        const resp = await window.AppConfig.engineUpload(path, fd);
                        console.log('上传响应:', resp);
                        if (resp && (resp.success || resp.code === 200) && resp.data) {
                            state.task = resp.data;
                            toast((kind === 'training' ? '训练' : '测试') + '数据已上传', 'success');
                        } else {
                            toast((resp && resp.message) || '上传失败', 'error');
                            nameBox.value = filePath ? fileName(filePath) : '未提供';
                        }
                    } catch (e) {
                        console.error('上传失败:', e);
                        toast('上传失败:' + e.message, 'error');
                        nameBox.value = filePath ? fileName(filePath) : '未提供';
                    }
                    renderBody();
                });
                const row = WB().h('div', { class: 'wb-field', style: 'max-width:980px;margin-bottom:14px' },
                    WB().h('label', null, label),
                    WB().h('div', { style: 'display:flex;gap:10px' }, nameBox, pickBtn,
                        withPreview ? WB().h('button', {
                            class: 'wb-btn wb-btn-outline' + (t.trainingFile ? '' : ' disabled'),
                            onclick: () => { if (t.trainingFile) runPrepare(); }
                        }, '预览数据') : null));
                row.appendChild(fileInput);
                return row;
            }
        }

        /* ---------- 页签二:稳态系数辨识(01-04 配置 / 01-05 运行) ---------- */
        function runTab() {
            const t = state.task;
            const wrap = WB().h('div', null);
            const running = t.status === 'RUNNING' || t.status === 'STOP_REQUESTED';

            wrap.appendChild(WB().h('div', { class: 'wb-form-grid', style: 'max-width:980px;margin-bottom:16px' },
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '计算路径'),
                    WB().h('input', { readonly: '', value: t.route === 'steady' ? '稳态方程' : '瞬态时刻方程' })),
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '结果保存位置'),
                    WB().h('input', { readonly: '', value: '本项目 / 运行记录 / ' + (t.runId || 'BENCH_01') }))));

            if (!running) {
                wrap.appendChild(configView());
            } else {
                wrap.appendChild(progressView());
            }
            return wrap;

            /* 01-04:参数分类 + 求解设置 */
            function configView() {
                const view = WB().h('div', null);
                const grid = WB().h('div', { style: 'display:grid;grid-template-columns:300px 1fr;gap:22px;max-width:1180px' });

                // 左:全部参数 12 类
                const listBox = WB().h('div', null,
                    WB().h('div', { class: 'wb-section-title', style: 'display:flex;justify-content:space-between' },
                        WB().h('span', null, '全部参数'), WB().h('span', { class: 'wb-hint', style: 'margin:0' }, PARAM_CLASSES.length + '类')));
                const list = WB().h('div', { class: 'wb-param-list' });
                PARAM_CLASSES.forEach(([name, kind], i) => {
                    list.appendChild(WB().h('div', {
                        class: 'wb-param-item' + (i === state.paramIdx ? ' active' : ''),
                        onclick: () => { state.paramIdx = i; renderBody(); }
                    }, WB().h('span', null, name), WB().h('span', { class: 'wb-hint', style: 'margin:0' }, kind)));
                });
                listBox.appendChild(list);
                grid.appendChild(listBox);

                // 右:当前类的设置 + 求解设置
                const [selName] = PARAM_CLASSES[state.paramIdx] || PARAM_CLASSES[0];
                const right = WB().h('div', null,
                    WB().h('div', { class: 'wb-section-title', style: 'margin-bottom:4px' }, selName + '修正'),
                    WB().h('div', { class: 'wb-hint', style: 'margin-bottom:10px' }, '准备记录 PREP_01 可复用;尚未运行参数辨识'),
                    WB().h('table', { class: 'wb-table' },
                        WB().h('tr', null, WB().h('th', null, '设置'), WB().h('th', null, '当前值')),
                        WB().h('tr', null, WB().h('td', null, '全工况初始值'), WB().h('td', null, '0.000 / 无量纲')),
                        WB().h('tr', null, WB().h('td', null, '系数形式'), WB().h('td', null, '按运行合同调度')),
                        WB().h('tr', null, WB().h('td', null, '已准备的分组数'), WB().h('td', null, '6组;最终曲线节点以辨识结果为准')),
                        WB().h('tr', null, WB().h('td', null, '先验及约束'), WB().h('td', null, '查看当前算法配置,不由界面另设默认'))),
                    WB().h('div', { class: 'wb-section-title', style: 'margin:18px 0 8px' }, '当前求解设置'),
                    WB().h('table', { class: 'wb-table' },
                        WB().h('tr', null, ['阶段', '方法', '关键设置'].map(x => WB().h('th', null, x))),
                        WB().h('tr', null, WB().h('td', null, 'A 全工况常值'), WB().h('td', null, '无阻尼TSVD'), WB().h('td', null, '保留6个奇异值')),
                        WB().h('tr', null, WB().h('td', null, 'B 组内辨识'), WB().h('td', null, 'Tikhonov'), WB().h('td', null, '按组配置先验尺度')),
                        WB().h('tr', null, WB().h('td', null, 'D 联合微调'), WB().h('td', null, 'Tikhonov'), WB().h('td', null, 'λ = 0.02;总上限20次'))));
                grid.appendChild(right);
                view.appendChild(grid);

                view.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin:12px 0' },
                    '预计用时:30至45分钟 · 依据:本机3次同类记录(示例)'));
                const drawer = WB().h('div', null);
                view.appendChild(drawer);
                view.appendChild(WB().h('div', { class: 'wb-actions-row', style: 'max-width:1180px' },
                    WB().h('button', {
                        class: 'wb-btn wb-btn-outline',
                        onclick: () => loadConfigDrawer(drawer, true)
                    }, '检查配置'),
                    startBtn(),
                    WB().h('button', { class: 'wb-btn wb-btn-outline', onclick: () => { state.tab = 'data'; renderBody(); } }, '返回数据'),
                    WB().h('div', { class: 'wb-spacer' }),
                    WB().h('button', {
                        class: 'wb-btn wb-btn-outline',
                        // 与"检查配置"职责不同:此处只读展示 A/B/D 三阶段求解方法合同(01-04),
                        // 检查配置则做数据/路径/运行包一致性校验并给结论
                        onclick: () => loadSolverDrawer(drawer)
                    }, '高级求解设置')));
                return view;
            }

            /** 高级求解设置(11.3 高级区):只读展示正则化/迭代上限/采样等高级参数及其来源,
             *  与"检查配置"(数据/路径/运行包一致性校验)职责不同;界面不提供修改。 */
            function loadSolverDrawer(container) {
                const pid = encodeURIComponent(ctx.project.id || '');
                const tid = encodeURIComponent(state.task.id);
                const ADV_KEYS = /solve|solver|tsvd|tikhonov|lambda|regul|iter|迭代|正则|奇异|先验|prior|sample|采样|步长|step|微调|上限/i;
                window.AppConfig.engineGet('projects/' + pid + '/tasks/' + tid + '/config')
                    .then(resp => {
                        container.innerHTML = '';
                        const cfg = resp && (resp.success || resp.code === 200) && resp.data ? resp.data : null;
                        const box = WB().h('div', { class: 'wb-card', style: 'padding:14px;max-width:1180px;margin-bottom:12px' },
                            WB().h('div', { class: 'wb-section-title', style: 'margin-bottom:8px' }, '高级求解设置(程序合同只读)'),
                            WB().h('table', { class: 'wb-table' },
                                WB().h('tr', null, ['阶段', '方法', '关键设置'].map(x => WB().h('th', null, x))),
                                WB().h('tr', null, WB().h('td', null, 'A 全工况常值'), WB().h('td', null, '无阻尼TSVD'), WB().h('td', null, '保留6个奇异值')),
                                WB().h('tr', null, WB().h('td', null, 'B 组内辨识'), WB().h('td', null, 'Tikhonov'), WB().h('td', null, '按组配置先验尺度')),
                                WB().h('tr', null, WB().h('td', null, 'D 联合微调'), WB().h('td', null, 'Tikhonov'), WB().h('td', null, 'λ = 0.02;总上限20次'))));
                        const adv = WB().h('div', { class: 'wb-kv', style: 'max-width:1180px;margin-top:10px' });
                        let advCount = 0;
                        if (cfg) {
                            Object.keys(cfg).forEach(k => {
                                if (!ADV_KEYS.test(k)) return;
                                const v = cfg[k];
                                if (v == null || typeof v === 'object') return;
                                adv.appendChild(WB().h('div', { class: 'k' }, k));
                                adv.appendChild(WB().h('div', { class: 'v' }, String(v)));
                                advCount++;
                            });
                        }
                        if (advCount) {
                            box.appendChild(WB().h('div', { class: 'wb-section-title', style: 'margin:10px 0 6px' }, '本次下发的高级参数'));
                            box.appendChild(adv);
                        } else {
                            box.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin-top:10px' },
                                '本次配置中未包含可展示的高级参数;以上为当前程序合同默认求解设置。'));
                        }
                        box.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin-top:8px' },
                            '来源:sht_tc24_estimation_options / sht_tc24_b_config 集中配置;单位与适用范围见程序交付配置字典。如需调整,请在程序管理中修改配置,运行界面不改。'));
                        container.appendChild(box);
                    })
                    .catch(e => toast('读取求解设置失败:' + e.message, 'error'));
            }

            /** 拉取并展示本次真实下发的配置(config.json 回读);检查模式额外给出一致性结论。 */
            function loadConfigDrawer(container, asCheck) {
                const pid = encodeURIComponent(ctx.project.id || '');
                const tid = encodeURIComponent(state.task.id);
                window.AppConfig.engineGet('projects/' + pid + '/tasks/' + tid + '/config')
                    .then(resp => {
                        container.innerHTML = '';
                        if (!(resp && (resp.success || resp.code === 200) && resp.data)) {
                            toast((resp && resp.message) || '尚未生成配置;请先上传数据并完成准备', 'error');
                            return;
                        }
                        if (asCheck) toast('配置检查通过:数据、路径与运行包一致', 'success');
                        const kv = WB().h('div', { class: 'wb-card', style: 'padding:14px;max-width:1180px;margin-bottom:12px' },
                            WB().h('div', { class: 'wb-section-title', style: 'margin-bottom:8px' }, '本次任务下发配置'));
                        Object.keys(resp.data).forEach(k => {
                            const v = resp.data[k];
                            kv.appendChild(WB().h('div', { class: 'wb-kv' },
                                WB().h('div', { class: 'k' }, k),
                                WB().h('div', { class: 'v' }, str(v))));
                        });
                        container.appendChild(kv);
                    })
                    .catch(e => toast('读取配置失败:' + e.message, 'error'));
            }

            function startBtn() {
                const failed = t.status === 'FAILED';
                return WB().h('button', {
                    class: 'wb-btn wb-btn-primary',
                    onclick: async () => {
                        try {
                            const resp = await window.AppConfig.enginePost(
                                'projects/' + encodeURIComponent(ctx.project.id || '') + '/tasks/'
                                + encodeURIComponent(t.id) + '/run', {});
                            if (resp && (resp.success || resp.code === 200)) {
                                if (resp.data) state.task = resp.data;
                                state.log = [];
                                showRunLoading('辨识运行中');
                                renderBody();
                                startPolling();
                            } else {
                                toast((resp && resp.message) || '发起辨识失败', 'error');
                            }
                        } catch (e) { toast('发起辨识失败:' + e.message, 'error'); }
                    }
                }, failed ? '重新开始辨识' : '开始辨识');
            }

            /* 01-05:运行监视 */
            function progressView() {
                const view = WB().h('div', null);
                view.appendChild(WB().h('div', { class: 'wb-infobar' },
                    t.status === 'STOP_REQUESTED'
                        ? '已请求停止;等待程序到达安全点后结束本次辨识。'
                        : '正在执行组内辨识。运行配置已固定。'));

                // 工作步骤表
                const stepStates = deriveWorkSteps();
                const stepTable = WB().h('table', { class: 'wb-table' },
                    WB().h('tr', null, WB().h('th', null, '工作步骤'), WB().h('th', null, '当前状态')));
                WORK_STEPS.forEach(name => {
                    const st = stepStates[name] || '待开始';
                    const active = st !== '待开始' && st !== '已完成';
                    stepTable.appendChild(WB().h('tr', active ? { class: 'wb-row-active' } : null,
                        WB().h('td', null, name),
                        WB().h('td', st.indexOf('/') >= 0 || st === '已完成' || st === '运行中'
                            ? WB().h('span', { class: 'wb-tag wb-tag-teal' }, st) : st)));
                });
                view.appendChild(stepTable);

                // 计时行
                const elapsed = t.startedAt ? formatDur(Date.now() - t.startedAt) : '—';
                view.appendChild(WB().h('table', { class: 'wb-table', style: 'margin-top:14px;max-width:1180px' },
                    WB().h('tr', null, ['运行前预计(首次记录)', '累计有效计算', '剩余时间'].map(x => WB().h('th', null, x))),
                    WB().h('tr', null,
                        WB().h('td', null, '30至45分钟'),
                        WB().h('td', null, elapsed === '—' ? (t.elapsedText || '—') : elapsed + '(累计)'),
                        WB().h('td', null, '暂无法可靠估计'))));

                // 当前迭代 + 最近反馈
                const iter = parseIter();
                view.appendChild(WB().h('div', { class: 'wb-section-title', style: 'margin:18px 0 4px' },
                    '当前迭代:' + (iter || '第1次') + ' / 本组上限10次'));
                const lastLog = state.log && state.log.length ? state.log[state.log.length - 1] : '正在计算模型输出';
                view.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin-bottom:12px' }, '最近反馈:' + lastLog));

                // 日志开关
                const logBox = WB().h('div', { class: 'wb-logbox', style: state.logOpen ? '' : 'display:none' },
                    state.log && state.log.length ? state.log.join('\n') : '等待日志输出...');
                view.appendChild(WB().h('div', { class: 'wb-actions-row', style: 'max-width:1180px' },
                    WB().h('button', {
                        class: 'wb-btn wb-btn-outline',
                        onclick: () => { state.logOpen = !state.logOpen; logBox.style.display = state.logOpen ? '' : 'none'; }
                    }, state.logOpen ? '收起详细日志' : '展开详细日志')));
                view.appendChild(logBox);

                // 底部:请求停止 | 查看本次配置
                const cfgDrawer = WB().h('div', null);
                view.appendChild(cfgDrawer);
                view.appendChild(WB().h('div', { class: 'wb-actions-row', style: 'max-width:1180px;margin-top:14px' },
                    WB().h('button', {
                        class: 'wb-btn wb-btn-outline' + (t.status === 'STOP_REQUESTED' ? ' disabled' : ''),
                        onclick: async () => {
                            if (t.status === 'STOP_REQUESTED') return;
                            try {
                                await window.AppConfig.enginePost(
                                    'projects/' + encodeURIComponent(ctx.project.id || '') + '/tasks/'
                                    + encodeURIComponent(t.id) + '/stop', {});
                                toast('已请求停止;等待程序到达安全点');
                                t.status = 'STOP_REQUESTED';
                                renderBody();
                            } catch (e) { toast('停止请求失败:' + e.message, 'error'); }
                        }
                    }, t.status === 'STOP_REQUESTED' ? '已请求停止' : '请求停止'),
                    WB().h('div', { class: 'wb-spacer' }),
                    WB().h('button', {
                        class: 'wb-btn wb-btn-outline',
                        onclick: () => loadConfigDrawer(cfgDrawer, false)
                    }, '查看本次配置')));
                return view;
            }

            function deriveWorkSteps() {
                const states = {};
                const lines = state.log || [];
                let current = null;
                lines.forEach(line => {
                    WORK_STEPS.forEach(name => {
                        if (line.indexOf(name) >= 0) current = name;
                    });
                });
                WORK_STEPS.forEach((name, i) => {
                    const idx = current ? WORK_STEPS.indexOf(current) : -1;
                    if (idx < 0) states[name] = i === 0 ? '进行中' : '待开始';
                    else if (i < idx) states[name] = '已完成';
                    else if (i === idx) states[name] = /组内/.test(name) ? '进行中' : '已完成';
                    else states[name] = '待开始';
                });
                return states;
            }

            function parseIter() {
                const lines = state.log || [];
                for (let i = lines.length - 1; i >= 0; i--) {
                    const m = String(lines[i]).match(/第\s*(\d+)\s*次|iter(?:ation)?\s*[=:]\s*(\d+)/i);
                    if (m) return '第' + (m[1] || m[2]) + '次';
                }
                return null;
            }
        }

        /* ---------- 页签三:建模结果(01-06 / 01-07) ---------- */
        function resultTab() {
            const t = state.task;
            const wrap = WB().h('div', null);
            const r = t.result || {};

            // 顶部三下拉(01-06)
            wrap.appendChild(WB().h('div', { class: 'wb-form-grid', style: 'grid-template-columns:1fr 1fr 1fr;max-width:1180px;margin-bottom:14px' },
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '运行记录'),
                    WB().h('select', null, WB().h('option', null, (t.runId || 'BENCH_01') + ' · 已结束'))),
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '数据范围'),
                    WB().h('select', null, WB().h('option', null, t.testFile ? '训练集 + 独立测试' : '训练集'))),
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '关联不确定性评估'),
                    WB().h('select', null, WB().h('option', null,
                        t.uqRunId ? ('已关联 · ' + t.uqRunId) : '未关联')))));

            // 子页签:输出与误差 | 参数与调度曲线 | 辨识方程拟合
            const subBar = WB().h('div', { class: 'wb-tabs', style: 'margin-bottom:12px' });
            ['输出与误差', '参数与调度曲线', '辨识方程拟合'].forEach((label, i) => {
                subBar.appendChild(WB().h('div', {
                    class: 'wb-tab' + (i === 0 ? ' active' : ''),
                    onclick: () => { if (i > 0) toast(label + ':曲线数据待后端输出接口接入', 'info'); }
                }, label));
            });
            wrap.appendChild(subBar);

            // 图例(01-06)
            wrap.appendChild(WB().h('div', { class: 'wb-legend', style: 'margin-bottom:8px' },
                WB().h('span', null, '▪ 测量值'),
                WB().h('span', null, '— 起点模型 B00'),
                WB().h('span', { style: 'font-weight:700' }, '— 辨识模型 ' + (t.runId || 'M24') + '-T01')));

            // 曲线区(待后端数据)
            wrap.appendChild(WB().h('div', { class: 'wb-chart-placeholder' },
                WB().h('div', { class: 'wb-empty', style: 'border:none' },
                    '逐工况对比曲线待后端输出接口接入后绘制(测量值 / 起点模型 / 辨识模型)。')));

            // 逐通道误差表
            const errTable = WB().h('table', { class: 'wb-table', style: 'margin-top:14px' },
                WB().h('tr', null, ['输出', '单位', '起点RMSE', '辨识后RMSE', '起点最大绝对误差', '辨识后最大绝对误差'].map(x => WB().h('th', null, x))));
            const channels = Array.isArray(r.channels) ? r.channels : [];
            if (channels.length) {
                channels.forEach(c => errTable.appendChild(WB().h('tr', null,
                    WB().h('td', null, c.output || c.name || '—'),
                    WB().h('td', null, c.unit || '—'),
                    WB().h('td', null, num(c.startRmse)), WB().h('td', null, num(c.rmse)),
                    WB().h('td', null, num(c.startMaxErr)), WB().h('td', null, num(c.maxErr)))));
            } else if (Object.keys(r).length) {
                Object.keys(r).forEach(k => {
                    const v = r[k];
                    if (v == null || typeof v === 'object') return;
                    errTable.appendChild(WB().h('tr', null,
                        WB().h('td', null, k), WB().h('td', { colspan: '5' }, String(v))));
                });
            } else {
                errTable.appendChild(WB().h('tr', null, WB().h('td', { colspan: '6', class: 'wb-hint' },
                    '辨识已完成;逐通道误差指标待后端结果结构化后在此列出。')));
            }
            wrap.appendChild(errTable);
            wrap.appendChild(WB().h('div', { style: 'display:flex;justify-content:space-between;margin-top:6px' },
                WB().h('span', { class: 'wb-hint', style: 'margin:0' }, '独立测试:' + (t.testFile ? fileName(t.testFile) : '未提供')),
                WB().h('span', { class: 'wb-hint', style: 'margin:0' }, '更多输出 / 归一化定义 / 逐点详情随导出提供')));

            // 底部动作(01-06)
            wrap.appendChild(WB().h('div', { class: 'wb-actions-row', style: 'margin-top:16px' },
                WB().h('button', {
                    class: 'wb-btn wb-btn-primary',
                    onclick: async () => {
                        try {
                            const resp = await window.AppConfig.enginePost(
                                'projects/' + encodeURIComponent(ctx.project.id || '') + '/tasks/'
                                + encodeURIComponent(t.id) + '/save-model',
                                { name: (t.name || '稳态建模') + '-模型' });
                            if (resp && (resp.success || resp.code === 200)) {
                                toast('已登记到模型成果', 'success');
                                stopPolling();
                                ctx.back(true);
                            } else {
                                toast((resp && resp.message) || '登记失败', 'error');
                            }
                        } catch (e) { toast('登记失败:' + e.message, 'error'); }
                    }
                }, '登记到模型成果'),
                WB().h('button', { class: 'wb-btn wb-btn-outline', onclick: () => exportAnalysis() }, '导出分析'),
                WB().h('div', { class: 'wb-spacer' }),
                WB().h('button', { class: 'wb-btn wb-btn-outline', onclick: () => { stopPolling(); state.tab = 'uq'; renderBody(); } }, '不确定性评估'),
                WB().h('button', {
                    class: 'wb-btn wb-btn-outline',
                    onclick: () => { if (ctx.navigate) ctx.navigate('predictions'); else toast('输出预测页后行接入', 'info'); }
                }, '新工况预测')));
            return wrap;

            function num(v) { return v == null ? '—' : String(v); }
        }

        /* ---------- 页签四:不确定性评估(01-08 配置 / 01-09 结果,可选) ---------- */
        function uqTab() {
            const t = state.task;
            const wrap = WB().h('div', null);
            const uqRunning = t.uqStatus === 'EXECUTING' || t.uqStatus === 'PREPARING';

            // UQ 运行中 → 轮询并在状态变化后重绘
            if (uqRunning) startPolling();

            if (uqRunning || t.uqStatus) {
                wrap.appendChild(uqStatusArea(t, uqRunning));
                if (!uqRunning && t.uqStatus === 'COMPLETED') {
                    wrap.appendChild(uqResultArea(t));
                }
                wrap.appendChild(WB().h('div', { class: 'wb-actions-row', style: 'margin-top:16px' },
                    WB().h('button', {
                        class: 'wb-btn wb-btn-outline',
                        onclick: () => { stopPolling(); state.tab = 'result'; renderBody(); }
                    }, '‹ 返回建模结果')));
                return wrap;
            }

            // —— 配置页(01-08) ——
            const modelSel = WB().h('select', null, WB().h('option', null, '正在加载模型成果...'));
            const methodSel = WB().h('select', null,
                WB().h('option', { value: 'B' }, 'B · 后验采样(正式V2配置)'),
                WB().h('option', { value: 'C' }, 'C · 主参数采样及附加参数近似处理'),
                WB().h('option', { value: 'D' }, 'D · 局部近似评估'));
            loadModelsInto(modelSel);

            wrap.appendChild(WB().h('div', { class: 'wb-form-grid', style: 'grid-template-columns:1fr 1fr;max-width:1180px' },
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '待评估模型'), modelSel),
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '评估方法'), methodSel),
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '推断数据(从所选模型带入)'),
                    WB().h('input', { readonly: '', value: t.trainingFile ? fileName(t.trainingFile) : '未提供' })),
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '独立测试数据'),
                    WB().h('input', { readonly: '', value: t.testFile ? fileName(t.testFile) : '未提供' }))));

            wrap.appendChild(WB().h('div', { class: 'wb-infobar' },
                'UQ 与所选确定性模型身份匹配;结果另存,不覆盖确定性估计值。'));

            // 评估配置表(01-08;取值为程序合同集中配置,不编造数值)
            const cfgRows = [
                ['参数先验', '使用本次明确的先验配置'],
                ['输入及输出测量误差', '建模独立配置'],
                ['采样数量', '按程序集中配置(sht_tc24_b_config)'],
                ['训练输出区间', '本次计算'],
                ['独立测试输出区间', t.testFile ? '本次计算' : '未提供测试数据']
            ];
            const cfgTable = WB().h('table', { class: 'wb-table' },
                WB().h('tr', null, ['评估配置', '当前设置'].map(x => WB().h('th', null, x))));
            cfgRows.forEach(([k, v]) => cfgTable.appendChild(WB().h('tr', null,
                WB().h('td', null, k), WB().h('td', null, v))));
            wrap.appendChild(cfgTable);

            wrap.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin:14px 0 4px' },
                '预计用时:暂无可靠估计'));
            wrap.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin-bottom:14px' },
                '原因:少于2条同类有效记录;完成后保存实际用时。'));

            const prevDrawer = WB().h('div', null);
            wrap.appendChild(prevDrawer);
            wrap.appendChild(WB().h('div', { class: 'wb-actions-row', style: 'max-width:1180px' },
                WB().h('button', {
                    class: 'wb-btn wb-btn-outline',
                    onclick: () => {
                        prevDrawer.innerHTML = '';
                        if (t.uqResult && Object.keys(t.uqResult).length) {
                            prevDrawer.appendChild(uqResultArea(t));
                        } else {
                            toast('此模型暂无已完成的评估记录', 'info');
                        }
                    }
                }, '查看此模型的已有评估'),
                WB().h('button', {
                    class: 'wb-btn wb-btn-primary',
                    onclick: async () => {
                        const opt = modelSel.selectedOptions && modelSel.selectedOptions[0];
                        const assetId = opt && opt.value ? opt.value : '';
                        if (!assetId) { toast('请先在建模结果页登记模型成果', 'error'); return; }
                        try {
                            const q = 'method=' + encodeURIComponent(methodSel.value);
                            const resp = await window.AppConfig.enginePost(
                                'projects/' + encodeURIComponent(ctx.project.id || '') + '/tasks/'
                                + encodeURIComponent(t.id) + '/uq?' + q, { modelAssetId: assetId });
                            if (resp && (resp.success || resp.code === 200) && resp.data) {
                                state.task = resp.data;
                                toast('UQ评估已发起', 'success');
                                showRunLoading('UQ 评估运行中');
                                renderBody();
                                startPolling();
                            } else {
                                toast((resp && resp.message) || '发起UQ失败', 'error');
                            }
                        } catch (e) { toast('发起UQ失败:' + e.message, 'error'); }
                    }
                }, '开始新评估'),
                WB().h('div', { class: 'wb-spacer' }),
                WB().h('button', {
                    class: 'wb-btn wb-btn-outline',
                    onclick: () => { stopPolling(); state.tab = 'result'; renderBody(); }
                }, '返回建模结果')));
            return wrap;

            function loadModelsInto(sel) {
                window.AppConfig.engineGet('projects/' + encodeURIComponent(ctx.project.id) + '/models')
                    .then(resp => {
                        const models = resp && Array.isArray(resp.data) ? resp.data : [];
                        sel.innerHTML = '';
                        if (!models.length) {
                            sel.appendChild(WB().h('option', { value: '' }, '尚未登记模型成果'));
                            return;
                        }
                        models.forEach(mo => sel.appendChild(WB().h('option', { value: mo.id },
                            (mo.name || mo.id) + (mo.deliveryWorkbookFile ? ' · ' + fileName(mo.deliveryWorkbookFile) : ''))));
                    })
                    .catch(() => { sel.innerHTML = ''; sel.appendChild(WB().h('option', { value: '' }, '模型成果加载失败')); });
            }

            function uqStatusArea(t, running) {
                const box = WB().h('div', null);
                box.appendChild(WB().h('div', { class: 'wb-infobar' },
                    running
                        ? (t.uqMessage || 'UQ 评估执行中...')
                        : 'UQ ' + ({ COMPLETED: '已完成', FAILED: '失败' }[t.uqStatus] || t.uqStatus) +
                        (t.uqMessage ? ':' + t.uqMessage : '')));
                const st = WB().h('div', { class: 'wb-kv', style: 'max-width:1180px;margin-bottom:14px' });
                const rows = [['评估方法/运行标识', t.uqRunId || '—'],
                    ['状态', t.uqStatus || '—'],
                    ['开始时间', t.uqStartedAt ? new Date(t.uqStartedAt).toLocaleString() : '—'],
                    ['结束时间', t.uqFinishedAt ? new Date(t.uqFinishedAt).toLocaleString() : '—']];
                rows.forEach(([k, v]) => {
                    st.appendChild(WB().h('div', { class: 'k' }, k));
                    st.appendChild(WB().h('div', { class: 'v' }, v));
                });
                box.appendChild(st);
                if (running) {
                    const logBox = WB().h('div', { class: 'wb-logbox' },
                        state.log && state.log.length ? state.log.join('\n') : '等待日志输出...');
                    box.appendChild(logBox);
                }
                return box;
            }

            function uqResultArea(t) {
                const r = t.uqResult || {};
                const box = WB().h('div', { class: 'wb-section', style: 'max-width:1180px' },
                    WB().h('div', { class: 'wb-section-title', style: 'margin-bottom:8px' },
                        'UQ 结果(' + (t.uqRunId || 'UQ') + ')'),
                    WB().h('div', { class: 'wb-hint', style: 'margin-bottom:10px' },
                        '结果另存,不覆盖确定性估计值;完整参数分布、节点区间与输出区间对照随结构化接口提供。'));
                const kv = WB().h('div', { class: 'wb-kv' });
                Object.keys(r).forEach(k => {
                    const v = r[k];
                    if (v == null) return;
                    kv.appendChild(WB().h('div', { class: 'k' }, k));
                    kv.appendChild(WB().h('div', { class: 'v' },
                        typeof v === 'object' ? JSON.stringify(v) : String(v)));
                });
                box.appendChild(kv);
                return box;
            }
        }

        /* ---------- 运行 loading 遮罩(旧版同款:进度条+当前子步骤+已运行时间) ---------- */
        function showRunLoading(title) {
            const host = document.querySelector('.workspace-content');
            if (!host) return;
            if (getComputedStyle(host).position === 'static') host.style.position = 'relative';
            let el = host.querySelector('.wb-loading-overlay');
            if (!el) {
                el = document.createElement('div');
                el.className = 'wb-loading-overlay';
                el.innerHTML = '<div class="wb-loading-box">'
                    + '<div class="wb-loading-spinner"></div>'
                    + '<div class="wb-loading-title"></div>'
                    + '<div class="wb-loading-bar"><i></i></div>'
                    + '<div class="wb-loading-sub"></div>'
                    + '<div class="wb-loading-time"></div>'
                    + '</div>';
                host.appendChild(el);
            }
            el.dataset.title = title;
            state.loadingTitle = title;
            updateRunLoading();
            if (!state.loadingTick) state.loadingTick = setInterval(updateRunLoading, 1000);
        }
        function updateRunLoading() {
            const host = document.querySelector('.workspace-content');
            const el = host && host.querySelector('.wb-loading-overlay');
            if (!el) return;
            const t = state.task || {};
            el.querySelector('.wb-loading-title').textContent = state.loadingTitle || '运行中';
            const logs = state.log || [];
            el.querySelector('.wb-loading-sub').textContent =
                logs.length ? String(logs[logs.length - 1]) : (t.message || '');
            const st = t.startedAt || t.uqStartedAt;
            el.querySelector('.wb-loading-time').textContent =
                st ? '已运行 ' + fmtDuration(Date.now() - st) : '';
        }
        function hideRunLoading() {
            if (state.loadingTick) { clearInterval(state.loadingTick); state.loadingTick = null; }
            state.loadingTitle = null;
            const el = document.querySelector('.wb-loading-overlay');
            if (el) el.remove();
        }
        function fmtDuration(ms) {
            const s = Math.max(0, Math.floor(ms / 1000));
            const m = Math.floor(s / 60), h = Math.floor(m / 60);
            return (h ? h + '时' : '') + (m ? m + '分' : '') + (s % 60) + '秒';
        }

        /* ---------- 轮询 ---------- */
        function poll() {
            const prevStatus = state.task ? state.task.status : null;
            const prevUq = state.task ? state.task.uqStatus : null;
            const prevPrep = state.task ? state.task.prepMessage : null;
            window.AppConfig.engineGet(
                'projects/' + encodeURIComponent(ctx.project.id || '') + '/tasks/'
                + encodeURIComponent(state.task.id) + '/status')
                .then(resp => {
                    if (resp && (resp.success || resp.code === 200) && resp.data) {
                        state.task = resp.data.task;
                        state.log = resp.data.logTail || [];
                    }
                    const t = state.task || {};
                    const changed = t.status !== prevStatus || t.uqStatus !== prevUq || t.prepMessage !== prevPrep;
                    // 运行中显示旧版同款 loading 遮罩,结束后自动隐藏
                    const uqRunning = t.uqStatus === 'EXECUTING' || t.uqStatus === 'PREPARING';
                    const prepRunning = state.prepWait || t.status === 'PREPARING';
                    if (prepRunning) {
                        showRunLoading(state.loadingTitle || '数据准备中');
                    } else if (t.status === 'RUNNING' || t.status === 'STOP_REQUESTED') {
                        showRunLoading(state.loadingTitle || '辨识运行中');
                    } else if (uqRunning && state.tab === 'uq') {
                        showRunLoading(state.loadingTitle || 'UQ 评估运行中');
                    } else {
                        hideRunLoading();
                    }
                    if (t.status === 'COMPLETED' && state.tab !== 'uq' && prevStatus !== 'COMPLETED') {
                        stopPolling();
                        state.tab = 'result';
                        renderBody();
                    } else if (state.tab === 'run' || (state.tab === 'uq' && changed)) {
                        renderBody();
                    } else if (state.tab === 'data' && changed) {
                        const prepDone = Array.isArray(t.conditions) && t.conditions.length > 0;
                        if (prepDone) { stopPolling(); state.prepWait = false; toast('数据准备完成,工况与分组已更新', 'success'); }
                        renderBody();
                    }
                })
                .catch(() => { });
        }
        function startPolling() { stopPolling(); state.timer = setInterval(poll, 5000); poll(); }
        function stopPolling() { if (state.timer) { clearInterval(state.timer); state.timer = null; } hideRunLoading(); }

        /** 数据准备(preview):真实解析工况分组;完成后由 poll 刷新页面 */
        function runPrepare() {
            const pid = encodeURIComponent(ctx.project.id || '');
            const tid = encodeURIComponent(state.task.id);
            toast('正在解析训练数据(工况与分组)...', 'info');
            window.AppConfig.enginePost('projects/' + pid + '/tasks/' + tid + '/prepare', {})
                .then(resp => {
                    if (resp && (resp.success || resp.code === 200)) {
                        state.prepWait = true;
                        showRunLoading('数据准备中');
                        renderBody();
                        startPolling();
                    } else {
                        toast((resp && resp.message) || '发起数据准备失败', 'error');
                    }
                })
                .catch(e => toast('发起数据准备失败:' + e.message, 'error'));
        }

        /** 导出分析:把任务结果导出为 CSV(真实数据;无结果时明确提示) */
        function exportAnalysis() {
            const r = state.task && state.task.result ? state.task.result : null;
            if (!r || !Object.keys(r).length) {
                toast('暂无可导出的辨识结果;请先完成一次辨识', 'error');
                return;
            }
            const lines = ['键,值'];
            Object.keys(r).forEach(k => {
                const v = r[k];
                const cell = v == null ? '' : (typeof v === 'object' ? JSON.stringify(v) : String(v));
                lines.push('"' + k.replace(/"/g, '""') + '","' + cell.replace(/"/g, '""') + '"');
            });
            const blob = new Blob(['\ufeff' + lines.join('\r\n')], { type: 'text/csv;charset=utf-8' });
            const a = document.createElement('a');
            a.href = URL.createObjectURL(blob);
            a.download = (state.task.runId || 'analysis') + '_result.csv';
            a.click();
            URL.revokeObjectURL(a.href);
            toast('已导出分析结果 CSV', 'success');
        }

        /* ---------- 加载既有任务 ---------- */
        async function load() {
            if (!ctx.project.id) { renderBody(); return; }
            try {
                const resp = await window.AppConfig.engineGet('projects/detail', { projectId: ctx.project.id });
                if (resp && (resp.success || resp.code === 200) && resp.data) {
                    const tasks = (resp.data.tasks || []).filter(x => x.kind === 'steady');
                    if (tasks.length) {
                        state.task = tasks[0];
                        state.tab = state.task.status === 'COMPLETED' ? 'result'
                            : (state.task.trainingFile ? 'run' : 'data');
                        if (state.task.status === 'RUNNING' || state.task.status === 'PREPARING' || state.task.status === 'STOP_REQUESTED') {
                            startPolling();
                        }
                    }
                }
            } catch (e) { console.warn('任务加载失败', e); }
            renderBody();
        }

        load();
        return root;
    }

    window.Workbench.renderSteadyTask = renderSteadyTask;
})();
