/**
 * 稳态试车建模任务页(图组1 概念,按实际功能实现):
 *   ① 任务与数据(创建任务、上传训练/测试 Excel)
 *   ② 执行辨识(Start_TC24_00_Offline via /api/engine,进度日志、请求停止)
 *   ③ 结果与保存(输出文件、关键信息、保存为模型成果)
 * 数据源:/api/engine/*(工作台域 API)。
 */
(function () {
    const WB = () => window.Workbench;

    const STATUS_TEXT = {
        PREPARING: '准备中', RUNNING: '运行中', COMPLETED: '已完成', FAILED: '失败',
        STOP_REQUESTED: '已请求停止', STOPPED: '已停止'
    };
    const STATUS_KIND = {
        PREPARING: 'amber', RUNNING: 'teal', COMPLETED: 'teal', FAILED: 'red',
        STOP_REQUESTED: 'amber', STOPPED: 'gray'
    };

    function statusTag(task) {
        return WB().h('span', { class: 'wb-tag wb-tag-' + (STATUS_KIND[task.status] || 'gray') },
            STATUS_TEXT[task.status] || task.status);
    }

    function toast(msg, kind) {
        if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast(msg, kind || 'info');
    }

    /**
     * 渲染稳态试车建模任务视图。
     * ctx: { project, back() }
     */
    function renderSteadyTask(ctx) {
        const state = { task: null, log: [], timer: null, step: 1 };
        const root = WB().h('div', null);

        // 页头
        root.appendChild(WB().h('div', { style: 'display:flex;align-items:center;gap:14px;margin-bottom:4px' },
            WB().h('button', { class: 'wb-btn wb-btn-outline', onclick: () => { stopPolling(); ctx.back(); } }, '‹ 返回'),
            WB().h('div', { class: 'wb-page-title', style: 'margin:0' }, '稳态试车建模')));
        root.appendChild(WB().h('div', { class: 'wb-page-sub' },
            ctx.project.name + ' / 由稳态数据新建模型(TC24),或用新试车记录更新(TC27)'));

        const stepsBar = WB().h('div', { class: 'wb-steps' });
        const body = WB().h('div', null);
        root.appendChild(stepsBar);
        root.appendChild(body);

        function renderSteps() {
            const names = ['任务与数据', '执行辨识', '结果与保存'];
            const maxStep = state.task
                ? (state.task.status === 'COMPLETED' ? 3 : (state.task.trainingFile ? 2 : 1))
                : 1;
            stepsBar.innerHTML = '';
            names.forEach((n, i) => {
                const idx = i + 1;
                const clickable = idx <= maxStep && state.task;
                stepsBar.appendChild(WB().h('div', {
                    class: 'wb-step' + (state.step === idx ? ' active' : '') + (idx < state.step ? ' done' : ''),
                    style: clickable ? '' : 'pointer-events:none;opacity:.55',
                    onclick: () => { if (clickable) { state.step = idx; renderBody(); renderSteps(); } }
                },
                    WB().h('span', { class: 'wb-step-idx' }, String(idx)), n,
                    idx < state.step ? ' ✓' : ''));
            });
        }

        function renderBody() {
            stopPolling();
            body.innerHTML = '';
            if (!state.task) { body.appendChild(createView()); }
            else if (state.step === 1) { body.appendChild(dataView()); }
            else if (state.step === 2) { body.appendChild(runView()); }
            else { body.appendChild(resultView()); }
        }

        /* ---------- ① 创建任务 ---------- */
        function createView() {
            const nameInput = WB().h('input', { value: '稳态建模-' + new Date().toISOString().slice(5, 10) });
            const routeSel = WB().h('select', null,
                WB().h('option', { value: 'steady' }, '稳态方程(由稳态均值数据新建)'),
                WB().h('option', { value: 'transient_instant' }, '瞬态时刻方程(两条独立辨识路径之一)'));
            const createBtn = WB().h('button', {
                class: 'wb-btn wb-btn-primary',
                onclick: async () => {
                    createBtn.classList.add('disabled');
                    try {
                        const resp = await window.AppConfig.enginePost('projects/tasks?projectId=' + encodeURIComponent(ctx.project.id || ''), {
                            kind: 'steady', name: nameInput.value.trim() || '稳态建模任务',
                            route: routeSel.value, runId: 'WB_01'
                        });
                        if (resp && (resp.success || resp.code === 200) && resp.data) {
                            state.task = resp.data;
                            state.step = 1;
                            renderSteps(); renderBody();
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

        /* ---------- ① 任务与数据 ---------- */
        function dataView() {
            const t = state.task;
            const wrap = WB().h('div', null);

            wrap.appendChild(WB().h('div', { class: 'wb-card', style: 'margin-bottom:16px;max-width:900px' },
                WB().h('div', { class: 'wb-kv' },
                    WB().h('div', { class: 'k' }, '任务'), WB().h('div', { class: 'v' }, t.name),
                    WB().h('div', { class: 'k' }, '计算路径'),
                    WB().h('div', { class: 'v' }, t.route === 'steady' ? '稳态方程' : '瞬态时刻方程'),
                    WB().h('div', { class: 'k' }, '状态'), WB().h('div', { class: 'v' }, statusTag(t)))));

            wrap.appendChild(uploadCard('训练数据(必选)', 'training', t.trainingFile,
                '训练均值 Excel(2p4 台架口径);示例数据见交付包 examples/TC24/TestData/three_component/。'));
            wrap.appendChild(uploadCard('测试数据(可选)', 'test', t.testFile,
                '独立测试均值 Excel;不提供时界面明确显示"未提供测试数据"。'));

            const nextBtn = WB().h('button', {
                class: 'wb-btn wb-btn-primary' + (t.trainingFile ? '' : ' disabled'),
                onclick: () => { if (t.trainingFile) { state.step = 2; renderSteps(); renderBody(); } }
            }, '下一步:执行辨识');
            wrap.appendChild(WB().h('div', { class: 'wb-actions-row' }, nextBtn));
            return wrap;

            function uploadCard(title, kind, filePath, hint) {
                const fileInput = WB().h('input', { class: 'wb-upload-input', type: 'file', accept: '.xlsx,.xls' });
                const box = WB().h('div', { class: 'wb-filebox' + (filePath ? ' hasfile' : '') },
                    fileInput,
                    WB().h('div', { style: 'flex:1' },
                        WB().h('div', { style: 'font-weight:600;color:#111827' },
                            filePath ? filePath.split(/[\\/]/).pop() : '点击选择 Excel 文件'),
                        WB().h('div', { class: 'wb-hint', style: 'margin:2px 0 0' }, hint)),
                    filePath ? WB().h('span', { class: 'wb-tag wb-tag-teal' }, '已上传') : null);

                box.addEventListener('click', () => fileInput.click());
                fileInput.addEventListener('change', async () => {
                    const f = fileInput.files && fileInput.files[0];
                    if (!f) return;
                    const fd = new FormData();
                    fd.append('projectId', ctx.project.id || '');
                    fd.append('taskId', t.id);
                    fd.append('kind', kind);
                    fd.append('file', f);
                    box.querySelector('.wb-hint').textContent = '上传中...';
                    try {
                        const resp = await window.AppConfig.engineUpload('projects/files', fd);
                        if (resp && (resp.success || resp.code === 200) && resp.data) {
                            state.task = resp.data;
                            toast((kind === 'training' ? '训练' : '测试') + '数据已上传', 'success');
                            renderBody();
                        } else {
                            toast((resp && resp.message) || '上传失败', 'error');
                        }
                    } catch (e) { toast('上传失败:' + e.message, 'error'); }
                });
                return WB().h('div', { class: 'wb-card', style: 'margin-bottom:16px;max-width:900px' },
                    WB().h('div', { class: 'wb-section-title', style: 'margin-bottom:10px' }, title),
                    box);
            }
        }

        /* ---------- ② 执行辨识 ---------- */
        function runView() {
            const t = state.task;
            const wrap = WB().h('div', null, WB().h('div', { class: 'wb-card', style: 'max-width:900px' }));

            const card = wrap.firstChild;
            const statusRow = WB().h('div', { style: 'display:flex;align-items:center;gap:12px;margin-bottom:12px' });
            const logBox = WB().h('div', { class: 'wb-logbox' }, '等待启动...');
            const actions = WB().h('div', { class: 'wb-actions-row' });

            const runBtn = WB().h('button', {
                class: 'wb-btn wb-btn-primary',
                onclick: async () => {
                    runBtn.classList.add('disabled');
                    try {
                        const resp = await window.AppConfig.enginePost('projects/run?projectId=' +
                            encodeURIComponent(ctx.project.id || '') + '&taskId=' + encodeURIComponent(t.id), {});
                        if (resp && (resp.success || resp.code === 200)) {
                            if (resp.data) state.task = resp.data;
                            startPolling();
                        } else {
                            toast((resp && resp.message) || '发起辨识失败', 'error');
                        }
                    } catch (e) { toast('发起辨识失败:' + e.message, 'error'); }
                    runBtn.classList.remove('disabled');
                }
            }, '开始辨识');
            const stopBtn = WB().h('button', {
                class: 'wb-btn wb-btn-outline',
                onclick: async () => {
                    try {
                        await window.AppConfig.enginePost('projects/stop?projectId=' +
                            encodeURIComponent(ctx.project.id || '') + '&taskId=' + encodeURIComponent(t.id), {});
                        toast('已请求停止;等待程序到达安全点');
                    } catch (e) { toast('停止请求失败:' + e.message, 'error'); }
                }
            }, '请求停止');

            actions.appendChild(runBtn);
            actions.appendChild(stopBtn);
            card.appendChild(statusRow);
            card.appendChild(logBox);
            card.appendChild(actions);

            function paint() {
                const tt = state.task || {};
                statusRow.innerHTML = '';
                statusRow.appendChild(statusTag(tt));
                if (tt.message) statusRow.appendChild(WB().h('span', { class: 'wb-hint', style: 'margin:0' }, tt.message));
                const running = tt.status === 'RUNNING' || tt.status === 'PREPARING' || tt.status === 'STOP_REQUESTED';
                runBtn.classList.toggle('disabled', running);
                logBox.textContent = (state.log && state.log.length ? state.log.join('\n') : '等待启动...');
                logBox.scrollTop = logBox.scrollHeight;
                if (tt.status === 'COMPLETED') {
                    stopPolling();
                    state.step = 3;
                    renderSteps();
                    renderBody();
                }
            }
            paint();

            function poll() {
                window.AppConfig.engineGet('projects/status',
                    { projectId: ctx.project.id || '', taskId: t.id })
                    .then(resp => {
                        if (resp && (resp.success || resp.code === 200) && resp.data) {
                            state.task = resp.data.task;
                            state.log = resp.data.logTail || [];
                        }
                        paint();
                    })
                    .catch(() => { });
            }
            function startPolling() { stopPolling(); state.timer = setInterval(poll, 2500); poll(); }

            // 若任务已在运行(重开页面),自动续接轮询
            if (t.status === 'RUNNING' || t.status === 'PREPARING' || t.status === 'STOP_REQUESTED') startPolling();
            return wrap;
        }

        /* ---------- ③ 结果与保存 ---------- */
        function resultView() {
            const t = state.task;
            const wrap = WB().h('div', null);

            const kv = WB().h('div', { class: 'wb-kv' });
            const r = t.result || {};
            Object.keys(r).forEach(k => {
                const v = r[k];
                if (v == null) return;
                if (typeof v === 'object') {
                    kv.appendChild(WB().h('div', { class: 'k' }, k));
                    kv.appendChild(WB().h('div', { class: 'v' },
                        WB().h('div', null, Object.keys(v).map(kk =>
                            WB().h('div', null, kk + ': ' + (v[kk] == null ? '—' : String(v[kk])))))));
                } else {
                    kv.appendChild(WB().h('div', { class: 'k' }, k));
                    kv.appendChild(WB().h('div', { class: 'v' }, String(v)));
                }
            });

            wrap.appendChild(WB().h('div', { class: 'wb-card', style: 'max-width:900px;margin-bottom:16px' },
                WB().h('div', { class: 'wb-section-title', style: 'margin-bottom:12px' }, '辨识结果'),
                kv));
            if (!Object.keys(r).length) {
                wrap.appendChild(WB().h('div', { class: 'wb-empty' }, '尚无结果信息'));
            }

            const nameInput = WB().h('input', { value: t.name + '-模型' });
            wrap.appendChild(WB().h('div', { class: 'wb-card', style: 'max-width:900px' },
                WB().h('div', { class: 'wb-section-title', style: 'margin-bottom:12px' }, '保存为模型成果'),
                WB().h('div', { class: 'wb-field', style: 'max-width:420px' },
                    WB().h('label', null, '模型名称'), nameInput),
                WB().h('div', { class: 'wb-hint', style: 'margin:10px 0 0' },
                    '保存后可在"模型成果"中查看,并作为后续 UQ、预测与自演化的输入。'),
                WB().h('div', { class: 'wb-actions-row' },
                    WB().h('button', {
                        class: 'wb-btn wb-btn-primary',
                        onclick: async () => {
                            try {
                                const resp = await window.AppConfig.enginePost('projects/save-model?projectId=' +
                                    encodeURIComponent(ctx.project.id || '') + '&taskId=' + encodeURIComponent(t.id),
                                    { name: nameInput.value.trim() || t.name + '-模型' });
                                if (resp && (resp.success || resp.code === 200)) {
                                    toast('已保存为模型成果', 'success');
                                    stopPolling();
                                    ctx.back(true);
                                } else {
                                    toast((resp && resp.message) || '保存失败', 'error');
                                }
                            } catch (e) { toast('保存失败:' + e.message, 'error'); }
                        }
                    }, '保存为模型成果'))));
            return wrap;
        }

        /* ---------- 加载既有任务 ---------- */
        async function load() {
            if (!ctx.project.id) {
                body.innerHTML = '';
                body.appendChild(WB().h('div', { class: 'wb-placeholder' },
                    WB().h('h3', null, '项目尚未保存到服务器'),
                    WB().h('p', null, '当前项目为本地演示项目,无法关联任务。请从项目入口重新进入(选择或创建真实项目)。')));
                renderSteps();
                return;
            }
            try {
                const resp = await window.AppConfig.engineGet('projects/detail', { projectId: ctx.project.id });
                if (resp && (resp.success || resp.code === 200) && resp.data) {
                    const tasks = (resp.data.tasks || []).filter(t => t.kind === 'steady');
                    if (tasks.length) {
                        state.task = tasks[0];
                        state.step = state.task.status === 'COMPLETED' ? 3 : (state.task.trainingFile ? 1 : 1);
                    }
                }
            } catch (e) { console.warn('任务加载失败', e); }
            renderSteps();
            renderBody();
        }

        function stopPolling() { if (state.timer) { clearInterval(state.timer); state.timer = null; } }

        load();
        return root;
    }

    window.Workbench.renderSteadyTask = renderSteadyTask;
})();
