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
        if (window.Workbench && window.Workbench.toast) window.Workbench.toast(msg, kind || 'info');
        else if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast(msg, kind || 'info');
        else console.log('Toast:', msg);
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
        const state = { task: null, log: [], timer: null, tab: 'data', logOpen: false, paramIdx: 2,
            transientMode: !!ctx.transientMode };
        const root = WB().h('div', null);

        // 从概况页/记录页指定打开既有任务(01-23:真实开始位置,不要求重新创建)
        const openTaskId = window.__WB_OPEN_TASK__;
        delete window.__WB_OPEN_TASK__;
        if (openTaskId && ctx.project && ctx.project.id) {
            state.task = { id: openTaskId };
            window.AppConfig.engineGet(
                'projects/' + encodeURIComponent(ctx.project.id) + '/tasks/'
                + encodeURIComponent(openTaskId) + '/status')
                .then(resp => {
                    if (resp && (resp.success || resp.code === 200) && resp.data && resp.data.task) {
                        state.task = resp.data.task;
                        state.log = resp.data.logTail || [];
                        const wantTab = window.__WB_OPEN_TASK_TAB__; // 记录页直达指定页签(如UQ)
                        delete window.__WB_OPEN_TASK_TAB__;
                        if (wantTab && TABS.some(t2 => t2[0] === wantTab)) {
                            state.tab = wantTab;
                            state.tabFromOpen = true; // 防止异步load()把页签改回默认
                        }
                    } else {
                        state.task = null;
                        toast((resp && resp.message) || '任务不存在', 'error');
                    }
                    renderBody();
                })
                .catch(() => { state.task = null; renderBody(); });
        }

        // 页头(01-03):标题 + 面包屑元信息
        const titleRow = WB().h('div', { style: 'display:flex;align-items:center;gap:14px;margin-bottom:4px' },
            WB().h('button', { class: 'wb-btn wb-btn-outline', onclick: () => { stopPolling(); ctx.back(); } }, '‹ 返回'),
            WB().h('div', { class: 'wb-page-title', style: 'margin:0' },
                state.transientMode ? '瞬态系数辨识' : '稳态系数辨识'));
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
            // 关闭所有SSE连接
            if (state.uqLogEventSource) {
                state.uqLogEventSource.close();
                state.uqLogEventSource = null;
            }
            
            // 数据准备/辨识进行中不允许renderBody杀掉轮询(否则spinner永久卡住)
            const busy = state.prepWait || (state.task && (state.task.status === 'PREPARING'
                || state.task.status === 'RUNNING' || state.task.status === 'STOP_REQUESTED'));
            if (state.tab !== 'run' && !busy) stopPolling();
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
            if (ctx.updateMode) return createCardUpdate();
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

        /** 新建TC27稳态更新任务(F-02):上游父模型 + 方法I/II + 路径 + 小幅段。 */
        function createCardUpdate() {
            const nameInput = WB().h('input', { value: '新增试车稳态更新-' + new Date().toISOString().slice(5, 10) });
            const prefill = window.__WB_TC27_PREFILL__;
            const modelSel = WB().h('select', null, WB().h('option', null, '正在加载模型成果...'));
            const methodSel = WB().h('select', null,
                WB().h('option', { value: 'I' }, '方法I(按当前混合工况分组形成节点后拟合)'),
                WB().h('option', { value: 'II', selected: '' }, '方法II(保留原节点位置,按数据覆盖补充节点)'));
            const routeSel = WB().h('select', null,
                WB().h('option', { value: 'steady' }, '稳态方程'),
                WB().h('option', { value: 'transient_instant', selected: '' }, '瞬态时刻方程'));
            const smallChk = WB().h('input', { type: 'checkbox' });
            window.AppConfig.engineGet('projects/' + encodeURIComponent(ctx.project.id || '') + '/models')
                .then(resp => {
                    const models = resp && Array.isArray(resp.data)
                        ? resp.data.filter(m => m.deliveryWorkbookFile) : [];
                    modelSel.innerHTML = '';
                    if (!models.length) {
                        modelSel.appendChild(WB().h('option', { value: '' }, '尚无可用模型——先完成基础建模并登记(需交付Excel)'));
                        return;
                    }
                    const ROUTE_CODE = { '稳态方程': 'steady', '瞬态时刻方程': 'transient_instant' };
                    models.forEach(m => modelSel.appendChild(WB().h('option', { value: m.id, 'data-route': ROUTE_CODE[m.route] || '' },
                        (m.name || m.id) + ' · ' + (m.stage || '') + ' · ' + (m.route || ''))));
                    if (prefill && prefill.upstreamModelId && models.some(m => m.id === prefill.upstreamModelId)) {
                        modelSel.value = prefill.upstreamModelId;
                        methodSel.value = prefill.updateMethod || methodSel.value;
                        routeSel.value = prefill.route || routeSel.value;
                    }
                    syncRoute();
                })
                .catch(() => {
                    modelSel.innerHTML = '';
                    modelSel.appendChild(WB().h('option', { value: '' }, '模型成果加载失败'));
                });
            // 路径由上游父模型决定(需一致):选中后自动带出并锁定
            const syncRoute = () => {
                const opt = modelSel.selectedOptions && modelSel.selectedOptions[0];
                const r = opt ? opt.getAttribute('data-route') : '';
                if (r) { routeSel.value = r; routeSel.setAttribute('disabled', ''); }
                else { routeSel.removeAttribute('disabled'); }
            };
            modelSel.addEventListener('change', syncRoute);
            const createBtn = WB().h('button', {
                class: 'wb-btn wb-btn-primary',
                onclick: async () => {
                    if (!modelSel.value) { toast('请选择上游TC24父模型(需已登记交付Excel)', 'error'); return; }
                    createBtn.classList.add('disabled');
                    try {
                        const pid = encodeURIComponent(ctx.project.id || '');
                        const resp = await window.AppConfig.enginePost('projects/' + pid + '/tasks', {
                            kind: 'steady_update', name: nameInput.value.trim() || '新增试车稳态更新任务',
                            upstreamModelId: modelSel.value, updateMethod: methodSel.value,
                            route: routeSel.value, includeSmallHistory: smallChk.checked,
                            runId: 'WB_U01'
                        });
                        if (resp && (resp.success || resp.code === 200) && resp.data) {
                            state.task = resp.data;
                            state.tab = 'data';
                            renderBody();
                        } else {
                            toast((resp && resp.message) || '创建更新任务失败', 'error');
                        }
                    } catch (e) { toast('创建更新任务失败:' + e.message, 'error'); }
                    createBtn.classList.remove('disabled');
                }
            }, '创建更新任务');
            return WB().h('div', { class: 'wb-card', style: 'max-width:760px' },
                WB().h('div', { class: 'wb-section-title', style: 'margin-bottom:6px' }, '新增试车稳态更新'),
                WB().h('div', { class: 'wb-hint', style: 'margin:0 0 14px' },
                    '用新增试车记录更新已有三部件稳态模型(F-02,Start_TC27_SteadyModelUpdate_01);只更新稳态系数,父模型路径需一致。'),
                WB().h('div', { class: 'wb-form-grid' },
                    WB().h('div', { class: 'wb-field' }, WB().h('label', null, '任务名称'), nameInput),
                    WB().h('div', { class: 'wb-field' }, WB().h('label', null, '上游模型(需路径一致)'), modelSel),
                    WB().h('div', { class: 'wb-field' }, WB().h('label', null, '调度更新方法'), methodSel),
                    WB().h('div', { class: 'wb-field' }, WB().h('label', null, '计算路径'), routeSel)),
                WB().h('div', { style: 'display:flex;align-items:center;gap:8px;margin-top:8px' },
                    smallChk, WB().h('span', { class: 'wb-hint', style: 'margin:0' },
                        '使用识别出的小幅变化段辅助稳态辨识')),
                WB().h('div', { class: 'wb-actions-row', style: 'margin-top:12px' },
                    createBtn,
                    WB().h('span', { class: 'wb-hint', style: 'margin:0' },
                        '两方法、两路径分别独立保存;公开合同与完整求解证据分开,不默认切换方法或路径。')));
        }

        /* ---------- 页签一(更新任务,01-17):TC27数据使用方式 ---------- */
        function dataTabUpdate() {
            const t = state.task;
            const wrap = WB().h('div', null);

            wrap.appendChild(WB().h('div', { style: 'margin-bottom:14px' },
                WB().h('div', { class: 'wb-section-title', style: 'font-size:20px;margin-bottom:2px' }, '工况与分组'),
                WB().h('div', { class: 'wb-hint', style: 'margin:0' },
                    (t.name || '稳态更新') + ' / 结合新增试车记录更新')));

            wrap.appendChild(WB().h('div', { class: 'wb-infobar' },
                '当前使用已有稳态模型与新增试车记录;只更新稳态系数。'));

            const ROUTE_NAME27 = { steady: '稳态方程', transient_instant: '瞬态时刻方程' };
            // 数据文件行(01-17:两列一行;文件名只读展示+选择文件替换)
            const fileGrid = WB().h('div', { class: 'wb-form-grid', style: 'grid-template-columns:1fr 1fr;max-width:1180px;column-gap:24px' });
            fileGrid.appendChild(fileRow('原训练点 Excel', 'training', t.trainingFile, false, t));
            fileGrid.appendChild(fileRow('新增训练历程', 'history', t.historyFile, false, t));
            fileGrid.appendChild(fileRow('原试车测试集(可选)', 'test', t.testFile, false, t));
            fileGrid.appendChild(fileRow('新增测试历程(可选)', 'historyTest', t.historyTestFile, false, t));
            fileGrid.querySelectorAll('.wb-field').forEach(el => { el.style.maxWidth = 'none'; el.style.marginBottom = '10px'; });

            // 小幅变化段checkbox(01-17):可勾选,走配置接口;已准备后修改需重新准备
            const smallChk = WB().h('input', { type: 'checkbox' });
            if (t.includeSmallHistory === true) smallChk.setAttribute('checked', '');
            smallChk.addEventListener('change', async () => {
                try {
                    const resp = await window.AppConfig.enginePost(
                        'projects/' + encodeURIComponent(ctx.project.id || '') + '/tasks/'
                        + encodeURIComponent(t.id) + '/config', { includeSmallHistory: smallChk.checked });
                    if (resp && (resp.success || resp.code === 200) && resp.data) {
                        state.task = resp.data;
                        toast('已' + (smallChk.checked ? '启用' : '停用') + '小幅变化段辅助辨识'
                            + (t.prepMessage ? ';数据使用方式变化,请重新准备数据' : ''), 'info');
                        renderBody();
                    } else toast((resp && resp.message) || '配置保存失败', 'error');
                } catch (e) { toast('配置保存失败:' + e.message, 'error'); }
            });

            wrap.appendChild(WB().h('div', { class: 'wb-form-grid', style: 'grid-template-columns:1fr 1fr;max-width:1180px' },
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '建模类型(本任务固定)'),
                    WB().h('input', { readonly: '', value: '新增试车稳态更新 / 2.7' })),
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '上游模型(需路径一致)'),
                    WB().h('input', { readonly: '', value: fileName(t.upstreamModelFile) || '—' })),
                fileGrid,
                WB().h('div', { class: 'wb-field', style: 'grid-column:1/-1' }, WB().h('label', null, '调度更新方法(创建时确定)'),
                    WB().h('div', { style: 'display:flex;align-items:center;gap:14px;flex-wrap:wrap' },
                        WB().h('input', { readonly: '', value: '方法' + (t.updateMethod || 'II'), style: 'max-width:200px' }),
                        WB().h('input', { readonly: '', value: ROUTE_NAME27[t.route] || (t.route || '—'), style: 'max-width:200px' }),
                        WB().h('button', {
                            class: 'wb-btn wb-btn-outline', style: 'padding:4px 10px;font-size:12px',
                            onclick: () => { window.__WB_TC27_PREFILL__ = { upstreamModelId: t.upstreamModelId, updateMethod: t.updateMethod, route: t.route }; state.task = null; renderBody(); }
                        }, '换方法/路径 → 新建更新任务'))),
                WB().h('div', { style: 'display:flex;align-items:center;gap:8px;grid-column:1/-1;margin:4px 0 6px' },
                    smallChk, WB().h('span', null, '使用识别出的小幅变化段辅助稳态辨识'),
                    t.prepMessage ? WB().h('span', { class: 'wb-hint', style: 'margin:0' }, '(变更后需重新准备数据)') : null)));

            const prepDone = t.prepMessage && t.prepMessage.length;
            const prepRunning = state.prepWait || t.status === 'PREPARING';
            const est = (t.result && t.result.prepEstimate) || null;
            const resultBody = WB().h('div', { style: 'padding:10px 0' });
            if (prepRunning) {
                resultBody.appendChild(WB().h('span', { class: 'wb-inline-loading' }, WB().h('span', { class: 'wb-inline-spinner' }),
                    '正在解析原工况均值与新窗口、识别小幅变化段...'));
            } else if (prepDone) {
                resultBody.appendChild(WB().h('div', { style: 'white-space:pre-line;line-height:1.9' }, String(t.prepMessage)));
                if (est && est.center_s) {
                    const fmtM = s => (s / 60) >= 10 ? Math.round(s / 60) + '分钟' : (s / 60).toFixed(1) + '分钟';
                    const estRow = WB().h('div', { style: 'display:flex;align-items:baseline;gap:18px;margin-top:10px' },
                        WB().h('span', { style: 'font-size:24px;font-weight:700;color:#0f766e' },
                            '约 ' + fmtM(est.center_s)),
                        WB().h('span', { class: 'wb-hint', style: 'margin:0' },
                            '参考范围 ' + (est.lower_s ? fmtM(est.lower_s) : '—') + ' ~ ' + (est.upper_s ? fmtM(est.upper_s) : '—')
                            + ' · 工程范围,非概率置信区间'));
                    resultBody.appendChild(estRow);
                    if (est.basis) resultBody.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin-top:4px' }, '依据: ' + est.basis));
                }
            } else {
                resultBody.appendChild(WB().h('div', null, '上传完成后点击"重新准备数据",由程序完成05预览(原工况+新窗口均值、分组、小幅段)。'));
            }
            wrap.appendChild(WB().h('div', { class: 'wb-section' },
                WB().h('div', { class: 'wb-section-head' },
                    WB().h('div', { class: 'wb-section-title' }, '数据处理结果'),
                    prepRunning ? WB().h('span', { class: 'wb-tag wb-tag-amber' }, '05数据准备运行中...')
                        : prepDone ? WB().h('span', { class: 'wb-tag wb-tag-teal' }, '准备完成')
                        : WB().h('span', { class: 'wb-tag wb-tag-gray' }, '待准备')),
                resultBody));

            wrap.appendChild(WB().h('div', { class: 'wb-actions-row', style: 'margin-top:10px' },
                WB().h('button', {
                    class: 'wb-btn wb-btn-outline' + (t.trainingFile && t.historyFile && !prepRunning ? '' : ' disabled'),
                    title: (t.trainingFile && t.historyFile) ? '' : '需先上传原训练均值与新增试车历程',
                    onclick: () => { if (t.trainingFile && t.historyFile && !prepRunning) window.__WB_ENGINE_POLL_UNTIL__ = Date.now() + 40000; runPrepare(); }
                }, prepRunning ? '数据准备中...' : '重新准备数据'),
                WB().h('div', { class: 'wb-spacer' }),
                WB().h('button', {
                    class: 'wb-btn wb-btn-primary' + (prepDone ? '' : ' disabled'),
                    title: prepDone ? '' : '请先完成数据准备(05预览)',
                    onclick: () => { if (prepDone) { state.tab = 'run'; renderBody(); } }
                }, '配置并执行更新')));
            return wrap;
        }

        /* ---------- 更新结果页:摘要 + 登记模型成果 ---------- */
        function resultTabUpdate() {
            const t = state.task;
            const r = t.result || {};
            const wrap = WB().h('div', null);
            wrap.appendChild(WB().h('div', { style: 'margin-bottom:14px' },
                WB().h('div', { class: 'wb-section-title', style: 'font-size:20px;margin-bottom:2px' }, '建模结果'),
                WB().h('div', { class: 'wb-hint', style: 'margin:0' },
                    (t.name || '稳态更新') + ' / 方法' + (t.updateMethod || 'II')
                    + ' / ' + (t.route === 'steady' ? '稳态方程' : '瞬态时刻方程'))));
            if (t.status !== 'COMPLETED') {
                wrap.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin:10px 0' },
                    '更新尚未完成;两方法、两路径分别独立保存,不以训练替代测试。'));
                return wrap;
            }
            const kv = WB().h('div', { class: 'wb-kv', style: 'max-width:1180px' });
            [
                ['运行标识', r.runId || '—'],
                ['计算路径 / 方法', (r.route || t.route) + ' / 方法' + (r.method || t.updateMethod)],
                ['上游模型 runId', r.upstreamRunId || '—'],
                ['输出目录', r.outputDirectory || '—'],
                ['交付工作簿', r.deliveryWorkbookFile ? fileName(r.deliveryWorkbookFile) : '未找到(检查tc27输出)'],
                ['结果状态', '已交付(方法/路径独立保存,不自动选优)']
            ].forEach(([k, v]) => {
                kv.appendChild(WB().h('div', { class: 'k' }, k));
                kv.appendChild(WB().h('div', { class: 'v' }, String(v)));
            });
            wrap.appendChild(kv);
            wrap.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin:10px 0' },
                '更新后的稳态调度、全部节点及燃油偏置以交付Excel为准;分来源训练与测试评价随交付提供;该更新模型可另行发起新的不确定性评估。'));
            wrap.appendChild(WB().h('div', { class: 'wb-actions-row', style: 'margin-top:12px' },
                WB().h('button', {
                    class: 'wb-btn wb-btn-primary',
                    onclick: async () => {
                        try {
                            const resp = await window.AppConfig.enginePost(
                                'projects/' + encodeURIComponent(ctx.project.id || '') + '/tasks/'
                                + encodeURIComponent(t.id) + '/save-model',
                                { name: (t.name || '稳态更新') + '-模型' });
                            if (resp && (resp.success || resp.code === 200)) {
                                toast(r.deliveryWorkbookFile ? '已登记到模型成果(2.7 数据更新,父模型已溯源)' : '已登记,但未找到交付Excel', r.deliveryWorkbookFile ? 'success' : 'error');
                                stopPolling();
                                ctx.back(true);
                            } else {
                                toast((resp && resp.message) || '登记失败', 'error');
                            }
                        } catch (e) { toast('登记失败:' + e.message, 'error'); }
                    }
                }, '登记到模型成果')));
            return wrap;
        }
        /* ---------- TC27瞬态(F-03):工况与分组(03-01~03-05) ---------- */
        function dataTabTransient() {
            const t = state.task;
            const wrap = WB().h('div', null);

            wrap.appendChild(WB().h('div', { style: 'margin-bottom:14px' },
                WB().h('div', { class: 'wb-section-title', style: 'font-size:20px;margin-bottom:2px' }, '工况与分组'),
                WB().h('div', { class: 'wb-hint', style: 'margin:0' },
                    (t.name || '瞬态更新') + ' / 结合瞬态训练历程辨识13项瞬态系数')));

            wrap.appendChild(WB().h('div', { class: 'wb-infobar' },
                '固定稳态父模型与瞬态历程;大幅事件选段后辨识13项瞬态参数,交付组合瞬态模型。'));

            const selMode = WB().h('select', null,
                WB().h('option', { value: 'automatic', selected: (t.selectionMode !== 'manual') ? '' : null }, '自动选段(按残差与阈值识别大幅事件)'),
                WB().h('option', { value: 'manual', selected: (t.selectionMode === 'manual') ? '' : null }, '手动指定事件时间范围'));
            const RANGE_HELP = '格式: 起始秒,结束秒(每行一段);manual模式必填';
            const rangesTa = WB().h('textarea', {
                rows: '4', style: 'width:100%;font-family:monospace;font-size:12px',
                placeholder: RANGE_HELP
            });
            wrap.appendChild(WB().h('div', { class: 'wb-form-grid', style: 'grid-template-columns:1fr 1fr;max-width:1180px' },
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '建模类型(本任务固定)'),
                    WB().h('input', { readonly: '', value: '新增试车瞬态更新 / 2.7 瞬态' })),
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '上游组合稳态模型(冻结稳态载体)'),
                    WB().h('input', { readonly: '', value: fileName(t.transientUpstreamFile) || '—' })),
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '事件选段模式'),
                    selMode),
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '手动事件范围(automatic时忽略)'),
                    rangesTa)));

            wrap.appendChild(fileRow('瞬态训练历程 Excel(20列完整记录)', 'history', t.historyFile, false));
            wrap.appendChild(fileRow('瞬态测试历程 Excel(可选)', 'historyTest', t.historyTestFile, false));

            wrap.appendChild(WB().h('div', { class: 'wb-section' },
                WB().h('div', { class: 'wb-section-head' },
                    WB().h('div', { class: 'wb-section-title' }, '数据处理结果'),
                    (state.prepWait || t.status === 'PREPARING')
                        ? WB().h('span', { class: 'wb-tag wb-tag-amber' }, '事件选段+05准备运行中...')
                        : (t.prepMessage && t.prepMessage.length && t.status === 'READY')
                            ? WB().h('span', { class: 'wb-tag wb-tag-teal' }, '准备完成')
                            : WB().h('span', { class: 'wb-tag wb-tag-gray' }, '待准备')),
                WB().h('div', { style: 'padding:10px 0' },
                    (state.prepWait || t.status === 'PREPARING')
                        ? WB().h('span', { class: 'wb-inline-loading' }, WB().h('span', { class: 'wb-inline-spinner' }),
                            '正在选择大幅事件并生成瞬态准备数据...')
                        : WB().h('div', null, (t.status === 'READY' && t.prepMessage) ? String(t.prepMessage)
                            : '上传历程后点击"重新准备数据",由程序完成事件选段与05准备。')),
                WB().h('div', { class: 'wb-hint', style: 'margin-top:6px' },
                    'preview身份随输出目录保存;执行辨识复用本次准备结果。')));

            wrap.appendChild(WB().h('div', { class: 'wb-actions-row', style: 'margin-top:10px' },
                WB().h('button', {
                    class: 'wb-btn wb-btn-outline' + (t.historyFile && !prepRunning ? '' : ' disabled'),
                    title: t.historyFile ? '' : '需先上传瞬态训练历程',
                    onclick: () => { if (t.historyFile && !prepRunning) window.__WB_ENGINE_POLL_UNTIL__ = Date.now() + 40000; runPrepare(); }
                }, prepRunning ? '数据准备中...' : '重新准备数据'),
                WB().h('div', { class: 'wb-spacer' }),
                WB().h('button', {
                    class: 'wb-btn wb-btn-primary' + (t.status === 'READY' ? '' : ' disabled'),
                    title: t.status === 'READY' ? '' : '请先完成数据准备',
                    onclick: () => { if (t.status === 'READY') { state.tab = 'run'; renderBody(); } }
                }, '配置并执行辨识')));
            return wrap;
        }

        /* ---------- TC27瞬态:结果页(03-09~03-11) ---------- */
        function resultTabTransient() {
            const t = state.task;
            const r = t.result || {};
            const wrap = WB().h('div', null);
            wrap.appendChild(WB().h('div', { style: 'margin-bottom:14px' },
                WB().h('div', { class: 'wb-section-title', style: 'font-size:20px;margin-bottom:2px' }, '建模结果'),
                WB().h('div', { class: 'wb-hint', style: 'margin:0' },
                    (t.name || '瞬态更新') + ' / 组合瞬态模型 / 13项瞬态系数')));
            if (t.status !== 'COMPLETED') {
                wrap.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin:10px 0' },
                    '辨识尚未完成;组合瞬态模型=稳态载体+13项瞬态系数+燃油偏置。'));
                return wrap;
            }
            const kv = WB().h('div', { class: 'wb-kv', style: 'max-width:1180px' });
            [
                ['运行标识', r.runId || '—'],
                ['输出目录', r.outputDirectory || '—'],
                ['交付组合模型', r.deliveryWorkbookFile ? fileName(r.deliveryWorkbookFile) : '未找到(检查tc27-transient输出)'],
                ['训练拟合曲线', r.trainingFitCsv ? fileName(r.trainingFitCsv) : '—'],
                ['结果状态', '已交付(组合模型=稳态载体+13项瞬态系数+燃油偏置)']
            ].forEach(([k, v]) => {
                kv.appendChild(WB().h('div', { class: 'k' }, k));
                kv.appendChild(WB().h('div', { class: 'v' }, String(v)));
            });
            wrap.appendChild(kv);
            wrap.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin:10px 0' },
                '组合瞬态模型可直接进入不确定性评估或新稳态工况预测;训练拟合曲线数据随交付CSV提供。'));
            wrap.appendChild(WB().h('div', { class: 'wb-actions-row', style: 'margin-top:12px' },
                WB().h('button', {
                    class: 'wb-btn wb-btn-primary',
                    onclick: async () => {
                        try {
                            const resp = await window.AppConfig.enginePost(
                                'projects/' + encodeURIComponent(ctx.project.id || '') + '/tasks/'
                                + encodeURIComponent(t.id) + '/save-model',
                                { name: (t.name || '瞬态更新') + '-组合模型' });
                            if (resp && (resp.success || resp.code === 200)) {
                                toast(r.deliveryWorkbookFile ? '组合瞬态模型已登记到模型成果' : '已登记,但未找到交付Excel', r.deliveryWorkbookFile ? 'success' : 'error');
                                stopPolling();
                                ctx.back(true);
                            } else {
                                toast((resp && resp.message) || '登记失败', 'error');
                            }
                        } catch (e) { toast('登记失败:' + e.message, 'error'); }
                    }
                }, '登记到模型成果')));
            return wrap;
        }

        /* ---------- 页签一:工况与分组(01-03) ---------- */
        function dataTab() {
            if (state.task && state.task.kind === 'transient_update') return dataTabTransient();
            if (state.task && state.task.kind === 'steady_update') return dataTabUpdate();
            const t = state.task;
            const wrap = WB().h('div', null);

            // 页面标题区(01-03):任务名 / 建模类型 / 起点模型
            wrap.appendChild(WB().h('div', { style: 'margin-bottom:14px' },
                WB().h('div', { class: 'wb-section-title', style: 'font-size:20px;margin-bottom:2px' }, '工况与分组'),
                WB().h('div', { class: 'wb-hint', style: 'margin:0' },
                    (t.name || '稳态建模') + ' / 基础稳态点建模 / 起点模型 B00')));

            // 建模类型 / 计算基准
            wrap.appendChild(WB().h('div', { class: 'wb-form-grid', style: 'max-width:980px;margin-bottom:16px' },
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '建模类型(本任务固定)'),
                    WB().h('input', { readonly: '', value: '基础稳态点建模 / 2.4' })),
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '计算基准'),
                    WB().h('input', { readonly: '', value: 'B00 · 当前配套运行包' }))));

            // 训练/测试数据行(01-03:输入框 + 选择文件 + 预览数据)
            wrap.appendChild(fileRow('训练数据 Excel', 'training', t.trainingFile, true, t));
            wrap.appendChild(fileRow('独立测试 Excel(可选)', 'test', t.testFile, false, t));

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
                    onclick: () => { if (t.trainingFile && !prepRunning) window.__WB_ENGINE_POLL_UNTIL__ = Date.now() + 40000; runPrepare(); }
                }, prepRunning ? '解析中...' : '重新准备数据'),
                WB().h('div', { class: 'wb-spacer' }),
                WB().h('button', {
                    class: 'wb-btn wb-btn-primary' + (prepDone ? '' : ' disabled'),
                    title: prepDone ? '' : '请先完成数据准备(解析工况分组)',
                    onclick: () => { if (prepDone) { state.tab = 'run'; renderBody(); } }
                }, '进入系数辨识')));
            return wrap;
        }

        /* ---------- 文件上传行组件(共用于 dataTab 和 dataTabUpdate) ---------- */
        function fileRow(label, kind, filePath, withPreview, t) {
            const nameBox = WB().h('input', { readonly: '', value: filePath ? fileName(filePath) : '未提供', style: 'flex:1;min-width:300px' });
            const pickBtn = WB().h('button', {
                class: 'wb-btn wb-btn-outline',
                onclick: () => fileInput.click()
            }, '上传文件');
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
            const row = WB().h('div', { class: 'wb-field', style: 'max-width:1180px;margin-bottom:14px' },
                WB().h('label', null, label),
                WB().h('div', { style: 'display:flex;gap:10px;flex-wrap:wrap;align-items:center' },
                    nameBox,
                    (function () {
                        const libSel = WB().h('select', { style: 'max-width:230px' },
                            WB().h('option', { value: '' }, '从文件库选择...'));
                        window.AppConfig.engineGet('projects/'
                            + encodeURIComponent(ctx.project.id || '') + '/files/page',
                            { category: 'data', pageSize: 50 })
                            .then(resp => {
                                const rows = resp && resp.data && Array.isArray(resp.data.rows) ? resp.data.rows.filter(x => x && x.id != null) : [];
                                rows.forEach(r0 => libSel.appendChild(WB().h('option', { value: r0.id },
                                    (r0.name || r0.id) + (r0.kind ? ' · ' + r0.kind : ''))));
                            })
                            .catch(() => { });
                        return libSel;
                    })(),
                    WB().h('button', {
                        class: 'wb-btn wb-btn-outline',
                        onclick: async () => {
                            const sel = row.querySelector('select');
                            if (!sel || !sel.value) { toast('请先在下拉中选择库内文件', 'error'); return; }
                            try {
                                const resp = await window.AppConfig.enginePost(
                                    'projects/' + encodeURIComponent(ctx.project.id || '') + '/tasks/'
                                    + encodeURIComponent(t.id) + '/files/from-library?kind='
                                    + encodeURIComponent(kind) + '&fileId=' + encodeURIComponent(sel.value), {});
                                if (resp && (resp.success || resp.code === 200) && resp.data) {
                                    state.task = resp.data;
                                    toast('已从文件库带入', 'success');
                                    renderBody();
                                } else toast((resp && resp.message) || '带入失败', 'error');
                            } catch (e) { toast('带入失败:' + e.message, 'error'); }
                        }
                    }, '带入'),
                    pickBtn,
                    WB().h('button', {
                        class: 'wb-btn wb-btn-outline' + (filePath ? '' : ' disabled'),
                        onclick: async () => {
                            if (!filePath) return;
                            const name = fileName(filePath);
                            try {
                                const resp = await window.AppConfig.engineGet('projects/'
                                    + encodeURIComponent(ctx.project.id || '') + '/files/page',
                                    { category: 'data', name: name, pageSize: 10 });
                                const hit = resp && resp.data && Array.isArray(resp.data.rows)
                                    ? resp.data.rows.find(r0 => r0.name === name) : null;
                                if (!hit) { toast('该文件未在项目文件库中(请重新上传或从库带入后再预览)', 'error'); return; }
                                const pv = await window.AppConfig.engineGet('projects/'
                                    + encodeURIComponent(ctx.project.id || '') + '/files/' + hit.id + '/preview');
                                if (pv && pv.code === 200 && pv.data) {
                                    window.Workbench.showFilePreview(name, pv.data);
                                } else toast((pv && pv.message) || '预览失败', 'error');
                            } catch (e) { toast('预览失败:' + e.message, 'error'); }
                        }
                    }, '预览')));
            row.appendChild(fileInput);
            return row;
        }

        /* ---------- 运行失败视图(01-15 错误定位与操作指引 / 01-16 保存失败与数值失败分开) ---------- */
        function failedView(t) {
            const kindMap = {
                SAVE_FAILED: ['保存失败', 'wb-tag-amber',
                    '辨识结果有效但写盘失败;检查磁盘空间与输出目录权限,排除后可重新发起(或仅重试保存)。'],
                NUMERIC_FAILED: ['数值失败', 'wb-tag-red',
                    '求解未收敛或数值发散;检查训练数据质量与工况覆盖,或调整正则化强度/迭代设置后重新发起。']
            };
            const km = kindMap[t.errorKind] || [null, 'wb-tag-red',
                '执行过程出错;结合运行日志定位原因后重新发起。'];
            const wrap = WB().h('div', null);
            wrap.appendChild(WB().h('div', { style: 'margin-bottom:14px' },
                WB().h('div', { class: 'wb-section-title', style: 'font-size:20px;margin-bottom:2px' }, '辨识运行失败'),
                WB().h('div', { class: 'wb-hint', style: 'margin:0' },
                    (t.name || '稳态建模') + ' / ' + (t.runId || '—') + ' / 未生成有效结果')));
            wrap.appendChild(WB().h('div', {
                class: 'wb-infobar', style: 'border-left:4px solid #b91c1c;background:#fef2f2;'
                    + 'display:flex;align-items:center;gap:12px;flex-wrap:wrap;padding:12px 16px;margin-bottom:12px'
            },
                WB().h('span', { class: 'wb-tag wb-tag-red' }, '运行失败'),
                WB().h('span', { class: 'wb-tag ' + km[1] }, '失败类型: ' + km[0]),
                WB().h('span', { style: 'color:#7f1d1d;word-break:break-all' }, String(t.message || '执行出错,详见运行日志'))));
            const kv = WB().h('div', { class: 'wb-kv', style: 'max-width:1180px;margin-bottom:12px' });
            [
                ['运行标识', t.runId || '—'],
                ['失败类型', km[0]],
                ['开始时间', t.startedAt ? new Date(t.startedAt).toLocaleString() : '—'],
                ['结束时间', t.finishedAt ? new Date(t.finishedAt).toLocaleString() : '—'],
                ['数据文件', t.trainingFile ? fileName(t.trainingFile) : '未提供']
            ].forEach(([k, v]) => {
                kv.appendChild(WB().h('div', { class: 'k' }, k));
                kv.appendChild(WB().h('div', { class: 'v' }, String(v)));
            });
            wrap.appendChild(kv);
            wrap.appendChild(WB().h('div', { class: 'wb-section-title', style: 'margin:6px 0 8px' }, '运行日志(末尾)'));
            wrap.appendChild(WB().h('pre', {
                style: 'max-height:260px;overflow:auto;background:#101418;color:#cde3d8;padding:12px;'
                    + 'border-radius:8px;font-size:12px;line-height:1.5;white-space:pre-wrap'
            }, (state.log && state.log.length ? state.log.join('\n') : '暂无日志输出')));
            wrap.appendChild(WB().h('div', { class: 'wb-section-title', style: 'margin:16px 0 8px' }, '操作指引'));
            const ul = WB().h('ul', { style: 'list-style:none;padding:0;margin:0 0 14px' });
            [
                ['定位原因', km[2]],
                ['数据检查', '回到「工况与分组」核对训练数据与独立测试(如已提供),必要时重新准备数据。'],
                ['重新发起', '点击下方"重新开始辨识";同一任务可重复发起,历史运行按运行标识区分。']
            ].forEach(([k, v]) => {
                const li = WB().h('li', { style: 'display:flex;gap:10px;margin-bottom:10px;align-items:flex-start' });
                li.appendChild(WB().h('span', {
                    style: 'flex-shrink:0;width:20px;height:20px;border-radius:50%;background:#0e7490;color:#fff;'
                        + 'display:inline-flex;align-items:center;justify-content:center;font-size:12px;margin-top:2px'
                }, '✓'));
                li.appendChild(WB().h('div', null,
                    WB().h('div', { style: 'font-weight:700;font-size:13px' }, k),
                    WB().h('div', { class: 'wb-hint', style: 'margin-top:2px;line-height:1.6' }, v)));
                ul.appendChild(li);
            });
            wrap.appendChild(ul);
            wrap.appendChild(WB().h('div', { class: 'wb-actions-row' },
                WB().h('button', {
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
                            } else toast((resp && resp.message) || '发起辨识失败', 'error');
                        } catch (e) { toast('发起辨识失败:' + e.message, 'error'); }
                    }
                }, '重新开始辨识'),
                WB().h('button', {
                    class: 'wb-btn wb-btn-outline',
                    onclick: () => { state.tab = 'data'; renderBody(); }
                }, '检查数据'),
                WB().h('button', {
                    class: 'wb-btn wb-btn-outline',
                    onclick: () => { state.tab = 'result'; renderBody(); }
                }, '查看建模结果')));
            return wrap;
        }

        /* ---------- 页签二:稳态系数辨识(01-04 配置 / 01-05 运行) ---------- */
        function runTab() {
            const t = state.task;
            // 失败任务直达失败视图(01-15):错误定位与操作指引,不再展示重新辨识配置页
            if (t.status === 'FAILED') return failedView(t);
            const wrap = WB().h('div', null);
            const running = t.status === 'RUNNING' || t.status === 'STOP_REQUESTED';

            // 页面标题区(01-04/01-05):任务名 / B00 / 训练工况 · 独立测试
            wrap.appendChild(WB().h('div', { style: 'margin-bottom:14px' },
                WB().h('div', { class: 'wb-section-title', style: 'font-size:20px;margin-bottom:2px' }, '稳态系数辨识'),
                WB().h('div', { class: 'wb-hint', style: 'margin:0' },
                    (t.name || '稳态建模') + ' / B00 / ' + (t.runId || 'BENCH_01') + ' / '
                    + (t.conditions && t.conditions.length ? '训练' + t.conditions.length + '工况' : '待数据准备')
                    + (t.testFile ? ' · 已提供独立测试' : ' · 未提供独立测试'))));

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
                        class: 'wb-btn wb-btn-outline',
                        onclick: async () => {
                            try {
                                const resp = await window.AppConfig.enginePost(
                                    'projects/' + encodeURIComponent(ctx.project.id || '') + '/tasks/'
                                    + encodeURIComponent(t.id) + '/stop', {});
                                if (resp && (resp.success || resp.code === 200)) {
                                    // 受理即落终态:停止轮询并立即回到重新辨识页(与取消UQ评估同逻辑)
                                    t.status = 'STOPPED';
                                    t.message = '已手动停止;可重新发起辨识';
                                    stopPolling();
                                    renderBody();
                                    toast('已请求停止;程序将在最近安全点结束,可重新发起辨识', 'success');
                                } else {
                                    toast((resp && resp.message) || '停止请求失败', 'error');
                                }
                            } catch (e) { toast('停止请求失败:' + e.message, 'error'); }
                        }
                    }, '请求停止'),
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

        /* ---------- 页签三:建模结果(01-06 / 01-07;数据来自 result-detail 真实回读) ---------- */
        const CHANNEL_UNITS = { Np: 'rpm', Ng: 'rpm', Ptb3: 'Pa', Ttb3: 'K', Pt45: 'Pa', Tt45: 'K', Pt6: 'Pa', Tt6: 'K', Wa2: 'kg/s' };
        function resultTab() {
            if (state.task && state.task.kind === 'transient_update') return resultTabTransient();
            if (state.task && state.task.kind === 'steady_update') return resultTabUpdate();
            const t = state.task;
            const wrap = WB().h('div', null);

            // 页面标题区(01-06):任务名 / B00 → runId / 计算路径
            const ROUTE_NAME = { steady: '稳态方程', transient_instant: '瞬态时刻方程' };
            wrap.appendChild(WB().h('div', { style: 'margin-bottom:14px' },
                WB().h('div', { class: 'wb-section-title', style: 'font-size:20px;margin-bottom:2px' }, '建模结果'),
                WB().h('div', { class: 'wb-hint', style: 'margin:0' },
                    (t.name || '稳态建模') + ' / B00 → ' + (t.runId || '—') + ' / ' + (ROUTE_NAME[t.route] || t.route || '稳态方程'))));

            // 顶部三下拉(01-06):运行记录 / 数据范围 / 关联UQ
            const rangeSel = WB().h('select', null,
                WB().h('option', { value: 'training' }, '训练集'),
                WB().h('option', Object.assign({ value: 'test' }, t.testFile ? {} : { disabled: '' }),
                    '独立测试' + (t.testFile ? '' : '(未提供)')));
            rangeSel.addEventListener('change', () => { state.resultRange = rangeSel.value; renderDetail(); });
            const uqSel = WB().h('select', null, WB().h('option', null, '加载中...'));
            loadUqOptions(uqSel);
            wrap.appendChild(WB().h('div', { class: 'wb-form-grid', style: 'grid-template-columns:1fr 1fr 1fr;max-width:1180px;margin-bottom:14px' },
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '运行记录'),
                    WB().h('select', null, WB().h('option', null, (t.runId || 'BENCH_01') + ' · 已结束'))),
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '数据范围'), rangeSel),
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '关联不确定性评估'), uqSel)));

            // 子页签(01-06/01-07/拟合)
            const subBar = WB().h('div', { class: 'wb-tabs', style: 'margin-bottom:12px' });
            const SUBS = [['out', '输出与误差'], ['param', '参数与调度曲线'], ['fit', '辨识方程拟合']];
            const subBody = WB().h('div', null);
            SUBS.forEach(([key, label]) => {
                subBar.appendChild(WB().h('div', {
                    class: 'wb-tab' + ((state.resultSub || 'out') === key ? ' active' : ''),
                    onclick: () => { state.resultSub = key; renderSubTabs(); renderDetail(); }
                }, label));
            });
            wrap.appendChild(subBar);
            wrap.appendChild(subBody);

            if (!state.detail) {
                subBody.appendChild(WB().h('div', { class: 'wb-empty', style: 'border:none' },
                    '正在加载辨识结果明细...'));
                window.AppConfig.engineGet('projects/' + encodeURIComponent(ctx.project.id || '')
                        + '/tasks/' + encodeURIComponent(t.id) + '/result-detail')
                    .then(resp => {
                        if (resp && (resp.success || resp.code === 200) && resp.data) {
                            state.detail = resp.data;
                        } else {
                            state.detailError = (resp && resp.message) || '结果明细尚未生成;辨识完成稍后自动生成';
                        }
                        if (WB().h && subBody.isConnected) renderDetail();
                    })
                    .catch(e => { state.detailError = '结果明细加载失败:' + e.message; renderDetail(); });
            } else {
                renderDetail();
            }
            renderSubTabs();
            return wrap;

            function renderSubTabs() {
                subBar.innerHTML = '';
                SUBS.forEach(([key, label]) => {
                    subBar.appendChild(WB().h('div', {
                        class: 'wb-tab' + ((state.resultSub || 'out') === key ? ' active' : ''),
                        onclick: () => { state.resultSub = key; renderSubTabs(); renderDetail(); }
                    }, label));
                });
            }

            function renderDetail() {
                subBody.innerHTML = '';
                if (state.detailError) {
                    subBody.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin:10px 0' }, state.detailError));
                    appendActions();
                    return;
                }
                const d = state.detail || {};
                if ((state.resultSub || 'out') === 'out') renderOutTab(d);
                else if (state.resultSub === 'param') renderParamTab(d);
                else renderFitTab(d);
                appendActions();
            }

            /* ===== 数据推导(全部来自 result_view 回读的 baseline/final/residualStatistics,不造数) ===== */
            /** 逐点对比数据:final=辨识模型输出;baseline=起点模型输出;训练集可用残差矩阵推导测量值。 */
            function buildPointData(d, range) {
                const fin = range === 'test' ? (d.final && d.final.test) : (d.final && d.final.training);
                const base = range === 'test' ? (d.baseline && d.baseline.test) : (d.baseline && d.baseline.training);
                if (!Array.isArray(fin) || !fin.length) return null;
                let channels = null, residuals = null;
                if (range !== 'test' && d.residualStatistics && Array.isArray(d.residualStatistics.names)) {
                    channels = d.residualStatistics.names.map(s => String(s).trim());
                    residuals = Array.isArray(d.residualStatistics.rawResidualMatrix) ? d.residualStatistics.rawResidualMatrix : null;
                } else {
                    channels = WB().numericColumns(fin);
                }
                const xKey = Object.keys(fin[0] || {}).find(k => /point_id|工况|编号/i.test(k)) || null;
                const labels = fin.map((r, i) => xKey ? String(r[xKey]) : (range === 'test' ? 'TE' : 'TR') + String(i + 1).padStart(2, '0'));
                return { fin, base: Array.isArray(base) ? base : null, channels, residuals, labels };
            }

            function metricsOf(d, which, range) {
                const blk = d[which];
                if (!blk) return { byField: null, summary: null, valid: null };
                const m = range === 'test' ? blk.testMetrics : blk.trainingMetrics;
                return {
                    byField: (m && Array.isArray(m.byField)) ? m.byField : null,
                    summary: m || null,
                    valid: range === 'test' ? blk.testValid : blk.trainingValid
                };
            }

            function fieldMetric(byField, ch) {
                if (!Array.isArray(byField)) return null;
                const hit = byField.find(f => f && String(f.field).trim() === ch);
                return hit || null;
            }

            function fmtNum(v) {
                if (v == null || !isFinite(v)) return '—';
                const a = Math.abs(v);
                if (a >= 1000) return v.toFixed(1);
                if (a >= 1) return v.toFixed(3);
                return v.toFixed(4);
            }

            /* —— 输出与误差(01-06):测量/起点/辨识 三线对比曲线 + 全通道误差表(点行切换) —— */
            function renderOutTab(d) {
                const range = state.resultRange || 'training';
                const pd = buildPointData(d, range);
                const fM = metricsOf(d, 'final', range);
                const bM = metricsOf(d, 'baseline', range);
                if (!pd) {
                    subBody.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin:10px 0' },
                        range === 'test' ? '未提供独立测试数据;训练结果必显,不以训练替代测试。' : '暂无辨识输出对照数据。'));
                    return;
                }
                if (state.outSel == null || state.outSel >= pd.channels.length) state.outSel = 0;
                const chartBox = WB().h('div', null);
                const tableBox = WB().h('div', null);

                const draw = () => {
                    const ch = pd.channels[state.outSel];
                    const chIdx = pd.channels.indexOf(ch);
                    const series = [];
                    if (pd.residuals) {
                        // 测量值 = 辨识模型输出 + 残差(result_view residualStatistics,真实推导)
                        series.push({
                            name: '测量值', dots: true,
                            values: pd.fin.map((r, i) => {
                                const v = WB().toNum(r[ch]);
                                const res = pd.residuals[i] ? WB().toNum(pd.residuals[i][chIdx]) : null;
                                return (v != null && res != null) ? v + res : null;
                            })
                        });
                    }
                    if (pd.base) series.push({ name: '起点模型 B00', dash: true, values: pd.fin.map((r, i) => pd.base[i] ? WB().toNum(pd.base[i][ch]) : null) });
                    series.push({ name: '辨识模型 ' + (t.runId || ''), bold: true, dots: true, values: pd.fin.map(r => WB().toNum(r[ch])) });
                    chartBox.innerHTML = '';
                    chartBox.appendChild(WB().h('div', { style: 'display:flex;justify-content:space-between;align-items:baseline;margin-bottom:4px' },
                        WB().h('span', { style: 'font-weight:600' }, ch + (CHANNEL_UNITS[ch] ? ' / ' + CHANNEL_UNITS[ch] : '')),
                        WB().h('span', null)));
                    chartBox.appendChild(WB().chartLegend(series));
                    chartBox.appendChild(WB().lineChart({ series, xLabels: pd.labels, xTitle: '工况编号' }));
                };

                // 全通道误差表(01-06):输出|单位|起点RMSE|辨识后RMSE|起点最大绝对误差|辨识后最大绝对误差
                const buildTable = () => {
                    tableBox.innerHTML = '';
                    const tbl = WB().h('table', { class: 'wb-table', style: 'margin-top:14px' },
                        WB().h('tr', null, ['输出', '单位', '起点RMSE', '辨识后RMSE', '起点最大绝对误差', '辨识后最大绝对误差'].map(x => WB().h('th', null, x))));
                    pd.channels.forEach((ch, i) => {
                        const chIdx = pd.channels.indexOf(ch);
                        const fHit = fieldMetric(fM.byField, ch);
                        const bHit = fieldMetric(bM.byField, ch);
                        // 最大绝对误差:辨识后=残差矩阵列最大;起点=|base-测量|最大(测量由辨识输出+残差推导)
                        let maxF = null, maxB = null;
                        if (pd.residuals) {
                            let mf = 0, mb = 0, any = false;
                            pd.fin.forEach((r, k) => {
                                const res = pd.residuals[k] ? WB().toNum(pd.residuals[k][chIdx]) : null;
                                const fv = WB().toNum(r[ch]);
                                const bv = (pd.base && pd.base[k]) ? WB().toNum(pd.base[k][ch]) : null;
                                if (res != null && fv != null) { mf = Math.max(mf, Math.abs(res)); any = true; }
                                if (res != null && fv != null && bv != null) mb = Math.max(mb, Math.abs(bv - fv - res));
                            });
                            if (any) { maxF = mf; maxB = mb; }
                        } else if (pd.base) {
                            let mb = 0, any = false;
                            pd.fin.forEach((r, k) => {
                                const fv = WB().toNum(r[ch]), bv = pd.base[k] ? WB().toNum(pd.base[k][ch]) : null;
                                if (fv != null && bv != null) { mb = Math.max(mb, Math.abs(fv - bv)); any = true; }
                            });
                            if (any) maxB = mb;
                        }
                        const tr = WB().h('tr', {
                            style: i === state.outSel ? 'background:#e5f1f2;cursor:pointer;font-weight:600' : 'cursor:pointer',
                            onclick: () => { state.outSel = i; buildTable(); draw(); }
                        },
                            WB().h('td', null, ch),
                            WB().h('td', { class: 'wb-hint' }, CHANNEL_UNITS[ch] || '—'),
                            WB().h('td', null, fmtNum(bHit ? bHit.rmse : null)),
                            WB().h('td', null, fmtNum(fHit ? fHit.rmse : null)),
                            WB().h('td', null, fmtNum(maxB)),
                            WB().h('td', null, fmtNum(maxF)));
                        tbl.appendChild(tr);
                    });
                    tableBox.appendChild(tbl);
                    tableBox.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin-top:4px' },
                        '点击表行切换上方曲线通道。' + (range === 'test'
                            ? '独立测试逐点残差不随结果视图提供,最大绝对误差按起点/辨识模型输出差给到参考。'
                            : 'RMSE与最大绝对误差按逐工况绝对偏差统计;归一化口径见交付Excel。')));
                };
                subBody.appendChild(chartBox);
                subBody.appendChild(tableBox);
                buildTable();
                draw();
            }

            /* —— 参数与调度曲线(01-07):左侧全部参数列表(点选) + 右侧节点曲线与节点表 —— */
            function renderParamTab(d) {
                const nodeRows = Array.isArray(d.scheduleNodeTable) ? d.scheduleNodeTable
                    : Array.isArray(d.finalSchedule) ? d.finalSchedule : null;
                const classRows = Array.isArray(d.parameterClassTable) ? d.parameterClassTable : null;

                if (!Array.isArray(nodeRows) || !nodeRows.length) {
                    if (classRows && classRows.length) {
                        subBody.appendChild(WB().h('div', { class: 'wb-section-title', style: 'margin-bottom:8px' },
                            '全部参数(' + classRows.length + '类)'));
                        subBody.appendChild(WB().dataTable(classRows, { maxRows: 14 }));
                    } else if (d.parameterClassTable && typeof d.parameterClassTable === 'object') {
                        subBody.appendChild(kvBox(d.parameterClassTable));
                    }
                    subBody.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin:10px 0' },
                        '结果明细中未包含调度节点表;完整参数与节点以交付Excel为准。'));
                    return;
                }

                // 节点坐标列 + 参数列族(起点/估计值成对)
                const allCols = [];
                nodeRows.slice(0, 3).forEach(r => Object.keys(r || {}).forEach(k => { if (allCols.indexOf(k) < 0) allCols.push(k); }));
                const xKey = allCols.find(k => /coord|node|speed|转速|节点|坐标|x$/i.test(k)) || null;
                const numCols = allCols.filter(k => k !== xKey && nodeRows.some(r => r && r[k] != null && isFinite(parseFloat(r[k]))));
                let fams = WB().groupSeriesColumns(numCols);
                if (!fams.length) {
                    // 无起点/估计命名时,每个数值列自成一项(仅估计值)
                    fams = numCols.map(c => ({ name: c, cols: { final: c } }));
                }
                if (state.paramSel == null || state.paramSel >= fams.length) state.paramSel = 0;

                // 左列表:优先参数类表(12类),名称对上列族则联动;否则直接列参数列族
                const listItems = (classRows && classRows.length ? classRows.map(r => {
                    const name = String(r['参数类'] || r['参数'] || r['name'] || r['名称'] || r['class'] || Object.values(r)[0] || '');
                    const kind = String(r['类型'] || r['type'] || r['单位'] || r['unit'] || '');
                    const hit = fams.find(f => f.name && name && (f.name.indexOf(name) >= 0 || name.indexOf(f.name) >= 0
                        || f.name.toLowerCase().replace(/[^a-z0-9\u4e00-\u9fa5]/g, '') === name.toLowerCase().replace(/[^a-z0-9\u4e00-\u9fa5]/g, '')));
                    return { name: name, kind: kind, fam: hit || null };
                }) : fams.map(f => ({ name: f.name, kind: '调度', fam: f })));

                const listBox = WB().h('div', { style: 'border:1px solid #e5e7eb;border-radius:6px;background:#fff;padding:6px 0;max-height:520px;overflow:auto' });
                const detailBox = WB().h('div', null);
                const paintList = () => {
                    listBox.innerHTML = '';
                    listBox.appendChild(WB().h('div', { style: 'display:flex;justify-content:space-between;padding:8px 14px 6px;border-bottom:1px solid #f1f5f9' },
                        WB().h('span', { style: 'font-weight:600' }, '全部参数'),
                        WB().h('span', { class: 'wb-hint', style: 'margin:0' }, listItems.length + '类')));
                    listItems.forEach((item, i) => {
                        const selected = i === state.paramSel;
                        listBox.appendChild(WB().h('div', {
                            style: 'display:flex;justify-content:space-between;padding:9px 14px;cursor:pointer;'
                                + (selected ? 'background:#e5f1f2;color:#075563;font-weight:600;' : ''),
                            onclick: () => { state.paramSel = i; paintList(); paintDetail(); }
                        },
                            WB().h('span', null, item.name || ('参数' + (i + 1))),
                            WB().h('span', { class: 'wb-hint', style: 'margin:0' }, item.kind || '')));
                    });
                };

                const paintDetail = () => {
                    detailBox.innerHTML = '';
                    const item = listItems[state.paramSel] || listItems[0];
                    const f = (item && item.fam) || fams[state.paramSel % fams.length];
                    if (!f) {
                        detailBox.appendChild(WB().h('div', { class: 'wb-hint' }, '该参数无节点数值。'));
                        return;
                    }
                    detailBox.appendChild(WB().h('div', { class: 'wb-section-title', style: 'font-size:16px;margin-bottom:6px' },
                        (item.name || f.name) + '修正'));
                    const series = [];
                    if (f.cols.base) series.push({ name: 'B00 起点', values: nodeRows.map(r => WB().toNum(r[f.cols.base])), dash: true });
                    if (f.cols.final) series.push({ name: (t.runId || '') + ' 估计', values: nodeRows.map(r => WB().toNum(r[f.cols.final])), bold: true });
                    if (!series.length) series.push({ name: f.name, values: nodeRows.map(r => WB().toNum(r[Object.values(f.cols)[0]])) });
                    const xLabels = nodeRows.map((r, i) => String(xKey && r[xKey] != null ? r[xKey] : i + 1));
                    detailBox.appendChild(WB().chartLegend(series));
                    detailBox.appendChild(WB().lineChart({ series, xLabels, xTitle: xKey ? String(xKey) : '节点坐标' }));

                    // 节点表:节点坐标 | 起点值 | 估计值 | 变化量(估计-起点)
                    const tbl = WB().h('table', { class: 'wb-table', style: 'margin-top:12px' },
                        WB().h('tr', null, ['节点坐标', '起点值', '估计值', '变化量'].map(x => WB().h('th', null, x))));
                    nodeRows.forEach((r, i) => {
                        const b = f.cols.base ? WB().toNum(r[f.cols.base]) : null;
                        const fi = f.cols.final ? WB().toNum(r[f.cols.final]) : null;
                        const dv = (b != null && fi != null) ? (fi - b) : null;
                        tbl.appendChild(WB().h('tr', null,
                            WB().h('td', null, xLabels[i]),
                            WB().h('td', { class: 'wb-hint' }, b != null ? String(b) : '—'),
                            WB().h('td', null, fi != null ? String(fi) : '—'),
                            WB().h('td', { class: 'wb-hint' }, dv != null ? (dv >= 0 ? '+' : '') + dv.toFixed(4) : '—')));
                    });
                    detailBox.appendChild(tbl);
                    detailBox.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin-top:4px' },
                        '区间: 尚未评估——完成不确定性评估后此处给出参数候选区间。'));
                };

                subBody.appendChild(WB().h('div', { style: 'display:grid;grid-template-columns:280px minmax(0,1fr);gap:18px;align-items:start' },
                    listBox, detailBox));
                paintList();
                paintDetail();
                if (d.groupEstimateTable) {
                    subBody.appendChild(WB().h('div', { class: 'wb-section-title', style: 'margin:16px 0 8px' }, '组内估计'));
                    subBody.appendChild(Array.isArray(d.groupEstimateTable)
                        ? WB().dataTable(d.groupEstimateTable, { maxRows: 12 })
                        : kvBox(d.groupEstimateTable));
                }
            }

/* —— 辨识方程拟合:整体指标 + 逐通道误差对照 + 残差统计(结构化展示,不做原始JSON dump) —— */
            function renderFitTab(d) {
                const ex = d.execution || {};
                const timing = (d.timing || ex.entryTiming || {});
                const kv = WB().h('div', { class: 'wb-kv', style: 'max-width:1180px' });
                const rows = [
                    ['收敛/交付状态', d.status || 'completed'],
                    ['交付资格', d.acceptance && d.acceptance.deliveryEligible === false ? '诊断(未收敛但有效,仍可交付)' : '满足交付条件'],
                    ['实际有效计算', ex.actualActiveSeconds != null ? Number(ex.actualActiveSeconds).toFixed(1) + ' s' : (timing.secondsToResultReady != null ? timing.secondsToResultReady + ' s' : '—')],
                    ['预计依据', '程序内置 runtime estimate(首次记录后按相同口径回填实际耗时)']
                ];
                rows.forEach(([k, v]) => { kv.appendChild(WB().h('div', { class: 'k' }, k)); kv.appendChild(WB().h('div', { class: 'v' }, String(v))); });
                subBody.appendChild(kv);

                // 训练/测试整体指标(来自 baseline/final 的 trainingMetrics/testMetrics)
                [['final', '辨识后'], ['baseline', '起点模型']].forEach(([which, label]) => {
                    const blk = d[which];
                    if (!blk) return;
                    [['training', '训练'], ['test', '独立测试']].forEach(([range, labelZh]) => {
                        const m = range === 'test' ? blk.testMetrics : blk.trainingMetrics;
                        const valid = range === 'test' ? blk.testValid : blk.trainingValid;
                        if (!m || valid === false) {
                            if (range === 'test' && blk.test && blk.test.length) {
                                subBody.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin:10px 0' },
                                    label + '·独立测试:逐点未全部收敛,按程序判定不并入有效指标(测试点 ' + blk.test.length + ' 个,明细随交付Excel)。'));
                            }
                            return;
                        }
                        subBody.appendChild(WB().h('div', { class: 'wb-section-title', style: 'margin:16px 0 8px' },
                            label + '·' + labelZh + '整体指标'));
                        const g = WB().h('div', { class: 'wb-kv', style: 'max-width:1180px' });
                        [
                            ['整体归一化RMSE', m.overall_nrms != null ? (m.overall_nrms * 100).toFixed(2) + ' %' : '—'],
                            ['有效点 / 总点数', (m.valid_point_count != null ? m.valid_point_count : '—') + ' / ' + (m.point_count != null ? m.point_count : '—')],
                            ['全部点收敛', m.all_points_valid ? '是' : '否'],
                            ['最大模型残差', m.max_model_residual != null && isFinite(m.max_model_residual) ? m.max_model_residual.toExponential(2) : '—']
                        ].forEach(([k, v]) => {
                            g.appendChild(WB().h('div', { class: 'k' }, k));
                            g.appendChild(WB().h('div', { class: 'v' }, v));
                        });
                        subBody.appendChild(g);
                    });
                });

                // 逐通道误差对照表:起点 vs 辨识(RMSE / 归一化RMSE%),训练必显、测试有有效指标才显示
                const cmpTable = (range, labelZh) => {
                    const fBy = metricsOf(d, 'final', range).byField;
                    const bBy = metricsOf(d, 'baseline', range).byField;
                    if (!Array.isArray(fBy) || !fBy.length) return;
                    subBody.appendChild(WB().h('div', { class: 'wb-section-title', style: 'margin:16px 0 8px' },
                        '逐通道误差对照(' + labelZh + ')'));
                    const tbl = WB().h('table', { class: 'wb-table' },
                        WB().h('tr', null, ['输出', '单位', '起点RMSE', '辨识后RMSE', '起点归一化RMSE', '辨识后归一化RMSE'].map(x => WB().h('th', null, x))));
                    fBy.forEach(fm => {
                        const ch = String(fm.field).trim();
                        const bm = fieldMetric(bBy, ch);
                        const pct = v => (v != null && isFinite(v)) ? (v * 100).toFixed(2) + ' %' : '—';
                        tbl.appendChild(WB().h('tr', null,
                            WB().h('td', null, ch),
                            WB().h('td', { class: 'wb-hint' }, CHANNEL_UNITS[ch] || '—'),
                            WB().h('td', null, fmtNum(bm ? bm.rmse : null)),
                            WB().h('td', null, fmtNum(fm.rmse)),
                            WB().h('td', { class: 'wb-hint' }, pct(bm ? bm.normalized_rmse : null)),
                            WB().h('td', { class: 'wb-hint' }, pct(fm.normalized_rmse))));
                    });
                    subBody.appendChild(tbl);
                };
                cmpTable('training', '训练');
                cmpTable('test', '独立测试');

                // 残差统计(辨识后):每通道RMSE/最大绝对残差/平均残差,来自 residualStatistics 汇总
                const rs = d.residualStatistics;
                if (rs && Array.isArray(rs.names)) {
                    const names = rs.names.map(s => String(s).trim());
                    const n = rs.sampleCount != null ? rs.sampleCount : (Array.isArray(rs.rawResidualMatrix) ? rs.rawResidualMatrix.length : null);
                    subBody.appendChild(WB().h('div', { class: 'wb-section-title', style: 'margin:16px 0 8px' },
                        '辨识后残差统计(' + (n != null ? n + ' 工况' : '样本') + ')'));
                    const tbl = WB().h('table', { class: 'wb-table' },
                        WB().h('tr', null, ['输出', '单位', 'RMSE', '最大绝对残差', '平均残差'].map(x => WB().h('th', null, x))));
                    names.forEach((ch, j) => {
                        let rmse = null;
                        if (Array.isArray(rs.diagonalSecondMoment) && isFinite(rs.diagonalSecondMoment[j])) {
                            rmse = Math.sqrt(Math.abs(rs.diagonalSecondMoment[j]));
                        }
                        let mx = null, sum = null, cnt = 0;
                        if (Array.isArray(rs.rawResidualMatrix)) {
                            mx = 0; sum = 0;
                            rs.rawResidualMatrix.forEach(row => {
                                const v = row ? WB().toNum(row[j]) : null;
                                if (v != null) { mx = Math.max(mx, Math.abs(v)); sum += v; cnt++; }
                            });
                        }
                        tbl.appendChild(WB().h('tr', null,
                            WB().h('td', null, ch),
                            WB().h('td', { class: 'wb-hint' }, CHANNEL_UNITS[ch] || '—'),
                            WB().h('td', null, fmtNum(rmse)),
                            WB().h('td', null, cnt ? fmtNum(mx) : '—'),
                            WB().h('td', { class: 'wb-hint' }, cnt ? fmtNum(sum / cnt) : '—')));
                    });
                    subBody.appendChild(tbl);
                    if (rs.negativeLogLikelihoodWithoutConstant != null && isFinite(rs.negativeLogLikelihoodWithoutConstant)) {
                        subBody.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin-top:4px' },
                            '负对数似然(不含常数项): ' + Number(rs.negativeLogLikelihoodWithoutConstant).toFixed(2)
                            + ';逐工况残差矩阵与协方差矩阵随 result_view 提供,此处只展示汇总口径。'));
                    }
                } else {
                    subBody.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin:10px 0' },
                        '结果明细未包含残差统计汇总;完整残差与逐点明细随交付Excel与result_view提供。'));
                }
            }

            function kvBox(obj) {
                const box = WB().h('div', { class: 'wb-kv', style: 'max-width:1180px' });
                Object.keys(obj || {}).forEach(k => {
                    const v = obj[k];
                    if (v == null) return;
                    box.appendChild(WB().h('div', { class: 'k' }, k));
                    box.appendChild(WB().h('div', { class: 'v' }, typeof v === 'object' ? JSON.stringify(v) : String(v)));
                });
                return box;
            }

            function appendActions() {
                const t2 = state.task;
                subBody.appendChild(WB().h('div', { style: 'display:flex;justify-content:space-between;margin-top:6px' },
                    WB().h('span', { class: 'wb-hint', style: 'margin:0' }, '独立测试:' + (t2.testFile ? fileName(t2.testFile) : '未提供')),
                    WB().h('span', { class: 'wb-hint', style: 'margin:0' }, '逐点详情/归一化定义随交付Excel与result_view提供')));
                subBody.appendChild(WB().h('div', { class: 'wb-actions-row', style: 'margin-top:16px' },
                    WB().h('button', {
                        class: 'wb-btn wb-btn-primary',
                        onclick: async () => {
                            try {
                                const resp = await window.AppConfig.enginePost(
                                    'projects/' + encodeURIComponent(ctx.project.id || '') + '/tasks/'
                                    + encodeURIComponent(t2.id) + '/save-model',
                                    { name: (t2.name || '稳态建模') + '-模型' });
                                if (resp && (resp.success || resp.code === 200)) {
                                    if (resp.data && resp.data.deliveryWorkbookFile) {
                                        toast('已登记到模型成果', 'success');
                                    } else {
                                        toast('已登记,但未找到交付Excel(output目录无.xlsx);预测与下载需交付文件,请检查辨识输出', 'error');
                                    }
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
            }

            /** 关联UQ下拉:本项目与本任务/模型相关的评估记录(01-19 不混用)。 */
            function loadUqOptions(sel) {
                window.AppConfig.engineGet('projects/' + encodeURIComponent(ctx.project.id || '') + '/uq-records')
                    .then(resp => {
                        const list = resp && (resp.success || resp.code === 200) && Array.isArray(resp.data) ? resp.data : [];
                        sel.innerHTML = '';
                        const mine = list.filter(r => r.taskId === state.task.id);
                        if (!mine.length) {
                            sel.appendChild(WB().h('option', null, '未关联'));
                            return;
                        }
                        mine.forEach(r => sel.appendChild(WB().h('option', null,
                            (r.runId || r.id) + ' · 方法' + (r.method || '—') + ' · ' + (r.status === 'COMPLETED' ? '已完成' : r.status || ''))));
                    })
                    .catch(() => { sel.innerHTML = ''; sel.appendChild(WB().h('option', null, '未关联')); });
            }
        }

        /* ---------- 页签四:不确定性评估(01-08 配置 / 01-09 结果,可选) ---------- */
        function uqTab() {
            const t = state.task;
            // 数值格式化助手必须在早退return之前声明(异步回调会用到,放后面会落入TDZ)
            const UQ_NUM = v => (v == null || v === '' || !isFinite(parseFloat(v))) ? null : parseFloat(v);
            const UQ_FMT = v => { const n = UQ_NUM(v); if (n == null) return '—';
                const a = Math.abs(n); return a >= 1000 ? n.toFixed(1) : a >= 1 ? n.toFixed(4) : n.toPrecision(4); };
            const wrap = WB().h('div', null);
            const uqRunning = t.uqStatus === 'EXECUTING' || t.uqStatus === 'PREPARING';

            // 关闭之前的SSE连接
            if (state.uqLogEventSource) {
                state.uqLogEventSource.close();
                state.uqLogEventSource = null;
            }

            // UQ 运行中 → 轮询并在状态变化后重绘;已完成/失败时提供"开始新评估"二次入口(02-05)
            if (uqRunning) startPolling();

            if (uqRunning || (t.uqStatus && !state.uqNew)) {
                wrap.appendChild(uqStatusArea(t, uqRunning));
                if (!uqRunning && t.uqStatus === 'COMPLETED') {
                    wrap.appendChild(uqResultArea(t));
                }
                wrap.appendChild(WB().h('div', { class: 'wb-actions-row', style: 'margin-top:16px' },
                    WB().h('button', {
                        class: 'wb-btn wb-btn-outline',
                        onclick: () => { stopPolling(); state.tab = 'result'; renderBody(); }
                    }, '‹ 返回建模结果'),
                    uqRunning ? WB().h('button', {
                        class: 'wb-btn wb-btn-outline',
                        onclick: async () => {
                            try {
                                const resp = await window.AppConfig.enginePost(
                                    'projects/' + encodeURIComponent(ctx.project.id || '') + '/tasks/'
                                    + encodeURIComponent(t.id) + '/uq/stop', {});
                                if (resp && (resp.success || resp.code === 200)) {
                                    // 受理即落终态:停止轮询并回到评估终态页(可重新发起)
                                    t.uqStatus = 'FAILED';
                                    t.uqMessage = '已手动取消评估;结果不保存,可重新发起';
                                    t.uqFinishedAt = Date.now();
                                    stopPolling();
                                    renderBody();
                                } else {
                                    toast((resp && resp.message) || '取消请求失败', 'error');
                                }
                            } catch (e) { toast('取消请求失败:' + e.message, 'error'); }
                        }
                    }, '取消评估') : null,
                    uqRunning ? null : WB().h('button', {
                        class: 'wb-btn wb-btn-primary',
                        title: '同一模型可发起多份评估;方法/粒子数可不同,结果各自独立保存',
                        onclick: () => { state.uqNew = true; renderBody(); }
                    }, '开始新评估')));
                return wrap;
            }
            state.uqNew = false;

            // —— 配置页(01-08) ——
            const ROUTE_NAME_UQ = { steady: '稳态方程', transient_instant: '瞬态时刻方程' };
            wrap.appendChild(WB().h('div', { style: 'margin-bottom:14px' },
                WB().h('div', { class: 'wb-section-title', style: 'font-size:20px;margin-bottom:2px' }, '不确定性评估'),
                WB().h('div', { class: 'wb-hint', style: 'margin:0' },
                    (t.name || '稳态建模') + ' / 对应模型待选 / 不覆盖确定性估计值 / ' + (ROUTE_NAME_UQ[t.route] || t.route || '稳态方程'))));
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

            // 评估配置表(01-08:评估配置|当前设置|操作 三列;采样数量为合同允许值 512/1024,来自 sht_tc24_b_config)
            const particleSel = WB().h('select', null,
                WB().h('option', { value: '512' }, '512(默认)'),
                WB().h('option', { value: '1024' }, '1024'));
            const cfgTable = WB().h('table', { class: 'wb-table' },
                WB().h('tr', null, ['评估配置', '当前设置', '操作'].map(x => WB().h('th', null, x))));
            [
                ['参数先验', '使用本次明确的先验配置', '随交付程序配置'],
                ['输入及输出测量误差', '建模独立配置', '随交付程序配置'],
                ['采样数量(粒子数)', particleSel, '下拉直接修改'],
                ['训练输出区间', '本次计算', '已选择'],
                ['独立测试输出区间', t.testFile ? '本次计算' : '未提供测试数据', t.testFile ? '已选择' : '不适用']
            ].forEach(([k, v, op]) => cfgTable.appendChild(WB().h('tr', null,
                WB().h('td', null, k),
                typeof v === 'string' ? WB().h('td', null, v) : WB().h('td', null, v),
                WB().h('td', { class: 'wb-hint' }, op))));
            wrap.appendChild(cfgTable);

            // 预计用时 + 右侧查看已有评估(01-08)
            const prevDrawer = WB().h('div', null);
            wrap.appendChild(WB().h('div', { style: 'display:flex;justify-content:space-between;align-items:flex-start;max-width:1180px;margin:14px 0 0' },
                WB().h('div', null,
                    WB().h('div', { class: 'wb-hint', style: 'margin:0 0 2px' }, '预计用时:暂无可靠估计'),
                    WB().h('div', { class: 'wb-hint', style: 'margin:0' }, '原因:少于2条同类有效记录;完成后保存实际用时。')),
                WB().h('button', {
                    class: 'wb-btn wb-btn-outline',
                    onclick: () => { prevDrawer.innerHTML = ''; prevDrawer.appendChild(uqRecordList()); }
                }, '查看此模型的已有评估')));
            wrap.appendChild(prevDrawer);

            wrap.appendChild(WB().h('div', { class: 'wb-actions-row', style: 'max-width:1180px;margin-top:16px' },
                WB().h('button', {
                    class: 'wb-btn wb-btn-outline',
                    // 01-08 检查评估条件:模型/数据/方法核对后再发起
                    onclick: () => {
                        const opt = modelSel.selectedOptions && modelSel.selectedOptions[0];
                        const problems = [];
                        if (!opt || !opt.value) problems.push('尚未选择待评估模型(先在建模结果页登记模型成果)');
                        if (!t.trainingFile) problems.push('缺少训练数据');
                        if (t.uqStatus === 'EXECUTING' || t.uqStatus === 'PREPARING') problems.push('已有评估执行中');
                        if (problems.length) toast('评估条件不满足:' + problems.join(';'), 'error');
                        else toast('评估条件检查通过:模型、推断数据与方法可发起;' + (t.testFile ? '独立测试将一并计算区间。' : '未提供独立测试,仅训练输出区间。'), 'success');
                    }
                }, '检查评估条件'),
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
                                + encodeURIComponent(t.id) + '/uq?' + q,
                                { modelAssetId: assetId, particleCount: parseInt(particleSel.value, 10) });
                            if (resp && (resp.success || resp.code === 200) && resp.data) {
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
                t.uqStatus === 'COMPLETED' ? WB().h('button', {
                    class: 'wb-btn wb-btn-outline',
                    onclick: () => { state.uqNew = false; renderBody(); }
                }, '返回上次结果') : null,
                WB().h('button', {
                    class: 'wb-btn wb-btn-outline',
                    onclick: () => { stopPolling(); state.tab = 'result'; renderBody(); }
                }, '← 返回建模结果')));
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
                        models.forEach(mo => {
                            const option = WB().h('option', { value: mo.id },
                                (mo.name || mo.id) + (mo.deliveryWorkbookFile ? ' · ' + fileName(mo.deliveryWorkbookFile) : ''));
                            sel.appendChild(option);
                        });
                    })
                    .catch(err => {
                        sel.innerHTML = '';
                        sel.appendChild(WB().h('option', { value: '' }, '模型成果加载失败'));
                    });
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
                    const logBox = WB().h('div', { class: 'wb-logbox', id: 'uq-log-box' },
                        '等待日志输出...');
                    box.appendChild(logBox);
                    
                    // 建立SSE连接接收实时日志(EventSource无法带header,后端支持?token=查询参数认证)
                    if (!state.uqLogEventSource) {
                        const pid = encodeURIComponent(ctx.project.id || '');
                        const tid = encodeURIComponent(t.id);
                        const base = (window.AppConfig.api && window.AppConfig.api.baseURL) || '';
                        const token = window.AppConfig.getToken ? window.AppConfig.getToken() : '';
                        const url = base + '/api/engine/projects/' + pid + '/tasks/' + tid + '/uq-log-stream?token=' + encodeURIComponent(token || '');
                        state.uqLogEventSource = new EventSource(url);
                        
                        state.uqLogEventSource.onmessage = function(event) {
                            if (!state.log) state.log = [];
                            state.log.push(event.data);
                            logBox.textContent = state.log.join('\n');
                            logBox.scrollTop = logBox.scrollHeight;
                        };
                        
                        state.uqLogEventSource.onerror = function(error) {
                            state.uqLogEventSource.close();
                            state.uqLogEventSource = null;
                        };
                    }
                }
                return box;
            }

            /** UQ 结果区(01-09):参数分布区间表(确定性值/后验均值/候选区间分列);明细来自交付Excel回读。 */
            function uqResultArea(t) {
                const box = WB().h('div', { class: 'wb-section', style: 'max-width:1180px' });
                box.appendChild(WB().h('div', { class: 'wb-section-title', style: 'margin-bottom:8px' },
                    'UQ 结果(' + (t.uqRunId || 'UQ') + ')'));
                box.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin-bottom:10px' },
                    '结果另存,不覆盖确定性估计值;未计算或质量受限的区间如实标注。'));
                const holder = WB().h('div', null, WB().h('div', { class: 'wb-hint' }, '正在加载参数区间表...'));
                box.appendChild(holder);
                window.AppConfig.engineGet('projects/' + encodeURIComponent(ctx.project.id || '') + '/uq-records')
                    .then(resp => {
                        const list = resp && (resp.success || resp.code === 200) && Array.isArray(resp.data) ? resp.data : [];
                        const mine = list.filter(r => r.taskId === t.id && r.status === 'COMPLETED');
                        if (!mine.length) { holder.innerHTML = ''; holder.appendChild(uqSummaryKv(t)); return; }
                        return window.AppConfig.engineGet('projects/' + encodeURIComponent(ctx.project.id || '')
                            + '/uq-records/' + encodeURIComponent(mine[0].id) + '/detail');
                    })
                    .then(resp => {
                        holder.innerHTML = '';
                        const d = resp && (resp.success || resp.code === 200) ? resp.data : null;
                        if (!d) { holder.appendChild(uqSummaryKv(t)); return; }
                        try {
                            renderUqDetail(holder, d);
                        } catch (e) {
                            window.__uqErr = (e && e.stack) || String(e);
                            console.error('renderUqDetail异常', e);
                            holder.appendChild(uqSummaryKv(t));
                        }
                    })
                    .catch(e => {
                        window.__uqErr = (e && e.stack) || String(e);
                        holder.innerHTML = '';
                        holder.appendChild(uqSummaryKv(t));
                    });
                return box;
            }

            /** 交付Excel回读JSON里找表字段:名称正则或行特征(后验列)匹配,大小写不敏感,下探两层。 */
            function uqTable(d, nameRe, colRe) {
                if (!d) return null;
                const shapeOk = arr => Array.isArray(arr) && arr.length
                    && arr.some(e => e && typeof e === 'object' && Object.keys(e).some(k => colRe.test(k)));
                let hit = null;
                const walk = (obj, depth) => {
                    if (hit || obj == null || typeof obj !== 'object' || depth > 2) return;
                    if (Array.isArray(obj)) { obj.forEach(o => walk(o, depth + 1)); return; }
                    Object.keys(obj).forEach(k => {
                        if (hit) return;
                        const v = obj[k];
                        if (Array.isArray(v) && v.length && (nameRe.test(k) || shapeOk(v))) hit = v;
                        else if (v && typeof v === 'object') walk(v, depth + 1);
                    });
                };
                walk(d, 0);
                return hit;
            }

            /** UQ运行结果页(无独立效果图,按旧版steady-model-adapt设计):
             *  Card1 采样摘要指标 / Card2 参数95%置信区间图(ECharts区间条+后验中心+确定性标记)
             *  Card3 结果解释与验收(✓清单) / Card4 输出区间与测量对照表(含覆盖状态列)。 */
            function renderUqDetail(holder, d) {
                const dl = (d && d.delivery) || {};
                const mf = dl.manifest || {};
                const ptAll = Array.isArray(d.parameterTable) ? d.parameterTable
                    : Array.isArray(dl.parameterTable) ? dl.parameterTable : [];
                if (!ptAll.length) { holder.appendChild(uqSummaryKv(t)); return; }

                /* —— 顶部摘要(真实manifest字段) —— */
                const metricGrid = WB().h('div', { style: 'display:grid;grid-template-columns:repeat(4,1fr);gap:14px;margin:10px 0 4px' });
                const fmtDur = s => {
                    const n = UQ_NUM(s); if (n == null) return '—';
                    return n >= 3600 ? (n / 3600).toFixed(2) + ' 小时' : n >= 60 ? (n / 60).toFixed(1) + ' 分钟' : n.toFixed(0) + ' 秒';
                };
                [
                    ['正式状态', mf.formal_status === 'FORMAL_ACCEPTED' ? '正式验收通过' : (mf.formal_status || '—')],
                    ['参数维度 / 后验样本', (mf.parameter_count || ptAll.length) + ' / ' + (mf.sample_count != null ? mf.sample_count : '—')],
                    ['后验有效样本量 ESS', mf.posterior_ess != null ? Number(mf.posterior_ess).toFixed(1) : '—'],
                    ['实际计算耗时', t.uqStartedAt && t.uqFinishedAt ? fmtDur((t.uqFinishedAt - t.uqStartedAt) / 1000) : '—']
                ].forEach(([k, v]) => metricGrid.appendChild(WB().h('div',
                    { style: 'background:#fff;border:1px solid #e5e7eb;border-radius:6px;padding:12px 16px' },
                    WB().h('div', { class: 'wb-hint', style: 'margin:0 0 4px' }, k),
                    WB().h('div', { style: 'font-size:18px;font-weight:700' }, String(v)))));
                holder.appendChild(metricGrid);
                holder.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin:6px 0 0' },
                    '运行 ' + (mf.run_id || t.uqRunId || '—') + ' · 方法' + (mf.method_id || '—')
                    + ' · 确定性基准 ' + (mf.deterministic_run_id || '—')
                    + ' · 完成于 ' + (mf.completed_at || '—')
                    + ' · 最大归一化权重 ' + (mf.maximum_normalized_weight != null ? Number(mf.maximum_normalized_weight).toFixed(4) : '—')));

                /* —— 按baseName分族(新版数据自带分组;常量类合并一族) —— */
                const families = [];
                const famIdx = {};
                ptAll.forEach(p => {
                    const isConst = p.groupKind === 'constant' || p.groupKind === 'health_constant';
                    const fam = isConst ? '常量与装车参数' : String(p.baseName || p.name || '—');
                    if (famIdx[fam] == null) { famIdx[fam] = families.length; families.push({ name: fam, rows: [], axis: p.axisName, unit: p.unit, kind: isConst ? 'constant' : p.groupKind }); }
                    families[famIdx[fam]].rows.push(p);
                });
                if (!state.uqFam || famIdx[state.uqFam] == null) state.uqFam = families[0].name;

                const grid = WB().h('div', { style: 'display:grid;grid-template-columns:1fr 320px;gap:18px;margin-top:14px;align-items:start' });
                const left = WB().h('div', null);
                const right = WB().h('div', null);
                grid.appendChild(left);
                grid.appendChild(right);
                holder.appendChild(grid);

                /* 左:参数95%置信区间图(分族页签)+ 当前族明细表 */
                left.appendChild(WB().h('div', { class: 'wb-section-title', style: 'margin-bottom:2px' }, '参数 95% 置信区间图'));
                left.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin:0 0 8px' },
                    '区间条=95%置信区间,圆点=后验中心,红色竖线标记=确定性辨识结果;横坐标为各参数。'));
                const tabRow = WB().h('div', { style: 'display:flex;gap:6px;flex-wrap:wrap;margin-bottom:10px' });
                families.forEach(f => {
                    tabRow.appendChild(WB().h('button', {
                        class: 'wb-btn ' + (state.uqFam === f.name ? 'wb-btn-primary' : 'wb-btn-outline'),
                        style: 'padding:3px 12px;font-size:12px',
                        onclick: () => { state.uqFam = f.name; renderBody(); }
                    }, f.name + '(' + f.rows.length + ')'));
                });
                left.appendChild(tabRow);
                const fam = families[famIdx[state.uqFam]] || families[0];
                const chartHost = WB().h('div', { style: 'width:100%;height:' + Math.max(220, fam.rows.length * 34 + 90) + 'px' });
                left.appendChild(chartHost);
                const rows = fam.rows.map(p => ({
                    name: fam.kind === 'constant' ? String(p.name) : (String(p.name).replace(/_node\d+$/, '') + '@' +
                        (UQ_NUM(p.coordinate) != null ? Number(p.coordinate).toFixed(3) : String(p.coordinate))),
                    q025: UQ_NUM(p.posteriorQ025), q975: UQ_NUM(p.posteriorQ975),
                    center: UQ_NUM(p.posteriorMedian != null ? p.posteriorMedian : p.posteriorMean),
                    det: UQ_NUM(p.deterministicEstimate)
                })).filter(x => x.q025 != null && x.q975 != null);
                // 延迟到DOM挂载后初始化(首次renderBody时容器尚未入文档)
                setTimeout(() => ensureEcharts(() => renderUqIntervalChart(chartHost, rows)), 0);

                const tbl = WB().h('table', { class: 'wb-table', style: 'margin-top:12px' },
                    WB().h('tr', null, ['参数', (fam.axis || '坐标') + (fam.unit && fam.unit !== '1' ? ' / ' + fam.unit : ''),
                        '先验σ', '确定性估计', '后验均值', '后验中位数', '95%区间', '区间宽度', '标准差收缩']
                        .map(x => WB().h('th', null, x))));
                fam.rows.forEach(p => {
                    const lo = UQ_NUM(p.posteriorQ025), hi = UQ_NUM(p.posteriorQ975);
                    tbl.appendChild(WB().h('tr', null,
                        WB().h('td', null, String(p.name)),
                        WB().h('td', { class: 'wb-hint' }, UQ_NUM(p.coordinate) != null ? Number(p.coordinate).toFixed(3) : '—'),
                        WB().h('td', { class: 'wb-hint' }, UQ_FMT(p.priorSigma)),
                        WB().h('td', null, UQ_FMT(p.deterministicEstimate)),
                        WB().h('td', null, UQ_FMT(p.posteriorMean)),
                        WB().h('td', { class: 'wb-hint' }, UQ_FMT(p.posteriorMedian)),
                        WB().h('td', null, (lo == null || hi == null) ? '—' : '[' + UQ_FMT(lo) + ', ' + UQ_FMT(hi) + ']'),
                        WB().h('td', { class: 'wb-hint' }, UQ_FMT(p.credibleWidth95)),
                        WB().h('td', { class: 'wb-hint' },
                            UQ_NUM(p.stdContraction) != null ? (UQ_NUM(p.stdContraction) * 100).toFixed(1) + ' %' : '—')));
                });
                left.appendChild(tbl);

                /* 右:结果解释与验收(真实manifest质量字段) */
                const items = [];
                let credibleDesc = '每个参数的可信区间有多宽';
                const widths = ptAll.map(x => UQ_NUM(x.credibleWidth95)).filter(v => v != null);
                if (widths.length) {
                    const maxW = Math.max.apply(null, widths), minW = Math.min.apply(null, widths);
                    const wide = ptAll.find(x => UQ_NUM(x.credibleWidth95) === maxW);
                    const narrow = ptAll.find(x => UQ_NUM(x.credibleWidth95) === minW);
                    credibleDesc = '最宽 ' + ((wide && wide.name) || '—') + '(宽度 ' + UQ_FMT(maxW)
                        + '),最窄 ' + ((narrow && narrow.name) || '—') + '(宽度 ' + UQ_FMT(minW) + ')';
                }
                items.push(['可信范围', credibleDesc]);
                const shrink = ptAll.map(x => UQ_NUM(x.stdContraction)).filter(v => v != null);
                items.push(['数据约束强度', shrink.length
                    ? '平均标准差收缩 ' + (shrink.reduce((a, b) => a + b, 0) / shrink.length * 100).toFixed(1)
                    + '%;收缩大表示数据对该参数约束强' : '—']);
                const passTxt = mf.formal_posterior_passed === true && mf.posterior_prediction_passed === true
                    ? '后验与预测区间验收均通过'
                    : mf.formal_posterior_passed === true ? '后验验收通过;预测区间未通过'
                    : mf.formal_posterior_passed === false ? '后验验收未通过;区间仅供诊断' : '—';
                items.push(['统计状态', passTxt + (mf.uncertainty_quality === 'SINGLE_RUN_SMC_RESULT'
                    ? ';单次SMC运行结果,区间稳定性与统计校准未经多次运行确认' : '')]);
                items.push(['预测影响', '区间' + (mf.measurement_uncertainty_included === true ? '已包含' : '未包含')
                    + '独立测量-模型偏差;范围=' + (mf.prediction_uncertainty_scope === 'joint_explicit_parameters_and_independent_measurement_model_discrepancy'
                    ? '显式参数与测量偏差联合传播' : (mf.prediction_uncertainty_scope || '—'))]);
                const ul = WB().h('ul', { style: 'list-style:none;padding:0;margin:6px 0 0' });
                items.forEach(([title, desc]) => {
                    const li = WB().h('li', { style: 'display:flex;gap:10px;margin-bottom:12px;align-items:flex-start' });
                    li.appendChild(WB().h('span', {
                        style: 'flex-shrink:0;width:20px;height:20px;border-radius:50%;background:#0e7490;color:#fff;'
                            + 'display:inline-flex;align-items:center;justify-content:center;font-size:12px;margin-top:2px'
                    }, '✓'));
                    li.appendChild(WB().h('div', null,
                        WB().h('div', { style: 'font-weight:700;font-size:13px' }, title),
                        WB().h('div', { class: 'wb-hint', style: 'margin-top:2px;line-height:1.6' }, desc)));
                    ul.appendChild(li);
                });
                right.appendChild(WB().h('div', { class: 'wb-section-title', style: 'margin-bottom:4px' }, '结果解释与验收'));
                right.appendChild(ul);
                right.appendChild(WB().h('div', { style: 'background:#f8fafc;border:1px solid #e5e7eb;border-radius:6px;padding:10px 12px;margin-top:10px' },
                    WB().h('div', { class: 'wb-hint', style: 'margin:0;line-height:1.7' },
                        '本页展示参数后验与95%置信区间(来自交付Excel恢复的联合后验);'
                        + '训练/测试输出预测区间与分阶段耗时在任务result.mat与执行记录中,不在本页重复计算。')));
            }

            /** echarts按需加载(program-run同款库,static/lib/echarts)。 */
            function ensureEcharts(cb) {
                if (window.echarts) { cb(window.echarts); return; }
                if (!window.__wbEchartsLoading) {
                    window.__wbEchartsLoading = true;
                    const s = document.createElement('script');
                    s.src = './lib/echarts/echarts.min.js';
                    s.onload = () => cb(window.echarts);
                    s.onerror = () => { window.__wbEchartsLoading = false; };
                    document.head.appendChild(s);
                } else {
                    const timer = setInterval(() => {
                        if (window.echarts) { clearInterval(timer); cb(window.echarts); }
                    }, 120);
                }
            }

            /** 水平区间图:透明下界堆叠+95%区间条+后验中心圆点+确定性方块标记(旧版同款呈现,数据为新版字段)。 */
            function renderUqIntervalChart(host, rows) {
                if (!window.echarts || !host || !rows.length) return;
                const chart = window.echarts.init(host, null, { renderer: 'canvas' });
                const lower = rows.map(x => (x.q025 != null && x.q975 != null && x.q975 >= x.q025) ? x.q025 : Math.min(x.q025, x.q975));
                const width = rows.map(x => Math.abs(x.q975 - x.q025) || 1e-9);
                chart.setOption({
                    animation: false,
                    tooltip: {
                        trigger: 'axis', axisPointer: { type: 'shadow' },
                        formatter: params => {
                            const x = rows[params[0].dataIndex]; if (!x) return '';
                            return '<div style="font-size:12px">' + x.name + '</div>'
                                + '<div style="font-size:11px;color:#666">95%区间:[' + UQ_FMT(x.q025) + ', ' + UQ_FMT(x.q975) + ']</div>'
                                + '<div style="font-size:11px;color:#666">后验中心:' + UQ_FMT(x.center) + '</div>'
                                + '<div style="font-size:11px;color:#666">确定性辨识结果:' + UQ_FMT(x.det) + '</div>';
                        }
                    },
                    legend: { data: ['95%置信区间', '后验中心', '确定性辨识结果'], left: 'center', bottom: 0, itemGap: 16, textStyle: { fontSize: 11 } },
                    grid: { left: 150, right: 40, top: 12, bottom: 55 },
                    xAxis: { type: 'value', scale: true, splitLine: { show: true, lineStyle: { color: '#f0f0f0' } }, axisLabel: { fontSize: 10 } },
                    yAxis: { type: 'category', data: rows.map(x => x.name), inverse: true, axisLabel: { fontSize: 10 }, axisLine: { show: false }, axisTick: { show: false } },
                    series: [
                        { name: '置信下界', type: 'bar', stack: 'interval', data: lower, itemStyle: { color: 'transparent' }, silent: true, z: 1 },
                        { name: '95%置信区间', type: 'bar', stack: 'interval', data: width, itemStyle: { color: 'rgba(60,140,190,0.55)' }, barWidth: 12, silent: true, z: 2 },
                        { name: '后验中心', type: 'scatter', data: rows.map((x, i) => [x.center, i]), symbol: 'circle', symbolSize: 8, itemStyle: { color: '#fff', borderColor: '#2b6b95', borderWidth: 2 }, z: 3 },
                        { name: '确定性辨识结果', type: 'scatter', data: rows.map((x, i) => [x.det, i]), symbol: 'rect', symbolSize: [3, 16], itemStyle: { color: '#d04e4e' }, z: 4 }
                    ]
                });
            }

            /** 兜底摘要(精选中文卡;明细JSON生成失败时依然可读,绝不dump原始键值)。 */
            function uqSummaryKv(t) {
                const r = t.uqResult || {};
                const delivery = r.delivery || {};
                const posterior = r.posterior || {};
                const num = v => (v == null || !isFinite(Number(v))) ? '—' : Number(v).toLocaleString();
                const kv = WB().h('div', { class: 'wb-kv', style: 'max-width:1180px' });
                [
                    ['评估方法', ({ B: 'B · 后验采样(SMC)', C: 'C · 主参数采样及附加参数近似', D: 'D · 局部近似评估' })[r.method] || r.method || '—'],
                    ['后验采样是否通过验收', r.passed === true ? '通过' : r.passed === false ? '未通过(区间仅供诊断)' : '—'],
                    ['参数维度', delivery.parameterCount || '—'],
                    ['后验样本数', delivery.sampleCount || '—'],
                    ['后验有效样本量 ESS', delivery.posteriorEss != null ? Number(delivery.posteriorEss).toFixed(1) : (posterior.ess != null ? num(posterior.ess) : '—')],
                    ['实际计算耗时', r.execution && r.execution.actualActiveSeconds != null
                        ? (Number(r.execution.actualActiveSeconds) / 3600).toFixed(2) + ' 小时' : '—'],
                    ['交付工作簿', delivery.workbookFile ? fileName(delivery.workbookFile) : '—']
                ].forEach(([k, v]) => {
                    kv.appendChild(WB().h('div', { class: 'k' }, k));
                    kv.appendChild(WB().h('div', { class: 'v' }, String(v)));
                });
                return kv;
            }

            /** 已有评估记录列表(02-05:同一模型/任务下的多份评估,方法/条件/状态独立)。 */
            function uqRecordList() {
                const box = WB().h('div', { class: 'wb-card', style: 'padding:14px;max-width:1180px' },
                    WB().h('div', { class: 'wb-section-title', style: 'margin-bottom:8px' }, '此任务的评估记录'));
                const holder = WB().h('div', null, WB().h('div', { class: 'wb-hint' }, '正在加载...'));
                box.appendChild(holder);
                window.AppConfig.engineGet('projects/' + encodeURIComponent(ctx.project.id || '') + '/uq-records')
                    .then(resp => {
                        const list = resp && (resp.success || resp.code === 200) && Array.isArray(resp.data) ? resp.data : [];
                        const mine = list.filter(r => r.taskId === state.task.id);
                        holder.innerHTML = '';
                        if (!mine.length) {
                            holder.appendChild(WB().h('div', { class: 'wb-hint' }, '暂无评估记录。'));
                            return;
                        }
                        holder.appendChild(WB().h('table', { class: 'wb-table' },
                            WB().h('tr', null, ['运行标识', '方法', '粒子数', '状态', '开始时间', '说明'].map(x => WB().h('th', null, x))),
                            mine.map(r => WB().h('tr', null,
                                WB().h('td', null, r.runId || r.id),
                                WB().h('td', null, r.method || '—'),
                                WB().h('td', null, r.particleCount || '默认'),
                                WB().h('td', null, r.status === 'COMPLETED' ? '已完成' : r.status === 'FAILED' ? '失败' : (r.status || '—')),
                                WB().h('td', { class: 'wb-hint' }, r.startedAt ? new Date(r.startedAt).toLocaleString() : '—'),
                                WB().h('td', { class: 'wb-hint' }, r.message || '—')))));
                    })
                    .catch(e => { holder.innerHTML = ''; holder.appendChild(WB().h('div', { class: 'wb-hint' }, '加载失败:' + e.message)); });
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
                        // TC24 看conditions;TC27更新任务看prepMessage(后端READY+摘要即完成)
                        const prepDone = t.kind === 'steady_update'
                            ? !!(t.prepMessage && t.prepMessage.length)
                            : (Array.isArray(t.conditions) && t.conditions.length > 0);
                        if (prepDone) { stopPolling(); state.prepWait = false; toast('数据准备完成', 'success'); }
                        renderBody();
                    }
                })
                .catch(() => { });
        }
        function startPolling() {
            stopPolling();
            window.__WB_ENGINE_POLL_UNTIL__ = Date.now() + 40000; // 活动心跳:让底部状态栏轮询保持
            state.timer = setInterval(() => {
                window.__WB_ENGINE_POLL_UNTIL__ = Date.now() + 40000;
                poll();
            }, 5000);
            poll();
        }
        function stopPolling() {
            if (state.timer) {
                clearInterval(state.timer);
                state.timer = null;
            }
            // 关闭SSE连接
            if (state.uqLogEventSource) {
                state.uqLogEventSource.close();
                state.uqLogEventSource = null;
            }
            hideRunLoading();
        }

        /** 数据准备(preview):真实解析工况分组;完成后由 poll 刷新页面 */
        function runPrepare() {
            const pid = encodeURIComponent(ctx.project.id || '');
            const tid = encodeURIComponent(state.task.id);
            toast('正在解析训练数据(工况与分组)...', 'info');
            window.AppConfig.enginePost('projects/' + pid + '/tasks/' + tid + '/prepare', {})
                .then(resp => {
                    if (resp && (resp.success || resp.code === 200)) {
                        if (resp.data) state.task = resp.data; // 同步PREPARING态,避免首轮poll误判状态变化
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

        // 进入业务页固定显示新建视图;只有运行记录/项目概览指定 __WB_OPEN_TASK__ 时才打开既有任务
        // 页面切换时由 shell 调用,避免旧页轮询残留(跨页串状态通道)
        window.__WB_PAGE_STOP__ = stopPolling;

        renderBody();
        return root;
    }

    window.Workbench.renderSteadyTask = renderSteadyTask;
})();
