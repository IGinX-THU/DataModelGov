/**
 * 飞参建模任务页(F-04 稳态飞参 / F-05 过渡态飞参)。
 * 与 workbench-task.js 同族页面结构:创建卡 → 工况与分组(数据意图确认) → 执行 → 结果登记。
 * 入口:window.Workbench.renderFlightTask({ project, flightKind, back, navigate })
 */
(function () {
    const WB = () => window.Workbench;

    const KIND_LABEL = {
        flight_steady: { title: '稳态飞参建模', sub: 'F-04 · Start_FlightModelAdapt_14 · 从实际飞参提取有效稳态窗口', evolution: false },
        flight_transient: { title: '过渡态飞参建模', sub: 'F-05 · Start_FlightModelAdapt_11/12/13 · 选取飞行大幅事件更新瞬态参数', evolution: false },
        evolution: { title: '模型自演化', sub: 'F-06 · Start_Stage4_02_EvolutionTask · 逐架次数据确认与整批建模编排', evolution: true }
    };

    function renderFlightTask(ctx) {
        const isSteady = ctx.flightKind === 'flight_steady';
        const L = KIND_LABEL[ctx.flightKind] || KIND_LABEL.flight_steady;
        const state = { task: null, log: [], timer: null, tab: 'data', prepWait: false };
        const root = WB().h('div', null);

        // 指定打开既有任务(记录页跳转)
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
                    } else {
                        state.task = null;
                        if (window.Workbench && window.Workbench.toast) window.Workbench.toast((resp && resp.message) || '任务不存在', 'error');
                    }
                    renderBody();
                })
                .catch(() => { state.task = null; renderBody(); });
        }

        const titleRow = WB().h('div', { style: 'display:flex;align-items:center;gap:14px;margin-bottom:4px' },
            WB().h('button', { class: 'wb-btn wb-btn-outline', onclick: () => { stopPolling(); ctx.back(); } }, '‹ 返回'),
            WB().h('div', { class: 'wb-page-title', style: 'margin:0' }, L.title));
        const metaRow = WB().h('div', { class: 'wb-page-sub' }, '');
        root.appendChild(titleRow);
        root.appendChild(metaRow);

        const TABS = [['data', '数据与确认'], ['run', '执行建模'], ['result', '建模结果']];
        const tabBar = WB().h('div', { class: 'wb-tabs' });
        root.appendChild(tabBar);
        const body = WB().h('div', null);
        root.appendChild(body);

        function toast(msg, kind) {
            if (window.Workbench && window.Workbench.toast) window.Workbench.toast(msg, kind || 'info');
        }
        function fileName(p) { return p ? String(p).split(/[\\/]/).pop() : ''; }
        function str(v) { return v == null ? '—' : String(v); }

        function paintMeta() {
            const t = state.task;
            metaRow.textContent = t
                ? (ctx.project.name + ' / ' + (t.runId || 'F3_01') + ' / 父模型来源 ' + (t.parentSource || '2p4')
                    + ' / 训练' + (t.identificationFile ? '已上传' : '待上传'))
                : (ctx.project.name + ' / 尚未创建任务');
        }

        function paintTabs() {
            const t = state.task;
            const evo = L.evolution;
            const reach = {
                data: !!t,
                run: !!(t && t.status === 'READY' && (evo || t.confirmationFile)),
                result: !!(t && (t.status === 'COMPLETED' || t.status === 'FAILED' || t.status === 'RUNNING'))
            };
            tabBar.innerHTML = '';
            TABS.forEach(([key, label]) => {
                const enabled = reach[key];
                const labelTxt = evo && key === 'data' ? '输入核验' : label;
                tabBar.appendChild(WB().h('div', {
                    class: 'wb-tab' + (state.tab === key ? ' active' : '') + (enabled ? '' : ' disabled'),
                    onclick: () => {
                        if (!enabled) {
                            if (key === 'run') toast(evo ? '请先完成输入核验' : '请先完成数据意图确认', 'info');
                            else if (key === 'result') toast('建模结果:执行完成后开放', 'info');
                            else toast('请先创建任务并上传测量Excel', 'info');
                            return;
                        }
                        state.tab = key; renderBody();
                    }
                }, labelTxt));
            });
        }

        function renderBody() {
            if (state.tab !== 'run') stopPolling();
            body.innerHTML = '';
            if (!state.task) { body.appendChild(createCard()); paintTabs(); paintMeta(); return; }
            if (state.tab === 'data') body.appendChild(dataTab());
            else if (state.tab === 'run') body.appendChild(runTab());
            else body.appendChild(resultTab());
            paintTabs();
            paintMeta();
        }

        /* ---------- 创建卡(F-04/F-05):任务名 + 父模型来源 + 架次 + 数据方法 ---------- */
        function createCard() {
            const nameInput = WB().h('input', {
                value: (isSteady ? '稳态飞参建模-' : '过渡态飞参建模-') + new Date().toISOString().slice(5, 10)
            });
            const parentSourceSel = WB().h('select', null,
                WB().h('option', { value: '2p4' }, '2.4 三部件模型'),
                WB().h('option', { value: '2p7' }, '2.7 数据更新模型'),
                WB().h('option', { value: 'flight' }, '既有飞参模型'),
                WB().h('option', { value: 'combined' }, '组合模型'));
            const modelSel = WB().h('select', null, WB().h('option', { value: '' }, '不指定(由程序按来源路线自动选择)'));
            const sortieInput = WB().h('input', { value: 'SORTIE-01', placeholder: '架次编号' });
            const engineInput = WB().h('input', { value: '', placeholder: '留空则取项目当前发动机' });
            const dataMethodSel = WB().h('select', null,
                WB().h('option', { value: 'steady_only' }, '仅稳态窗口(steady_only)'),
                WB().h('option', { value: 'steady_plus_small_history' }, '稳态+小幅变化段(steady_plus_small_history)'));

            window.AppConfig.engineGet('projects/' + encodeURIComponent(ctx.project.id || '') + '/models')
                .then(resp => {
                    const models = resp && Array.isArray(resp.data) ? resp.data.filter(m => m.deliveryWorkbookFile) : [];
                    if (models.length) {
                        models.forEach(m => modelSel.appendChild(WB().h('option', { value: m.id },
                            (m.name || m.id) + ' · ' + (m.stage || '') + ' · ' + (m.route || ''))));
                    }
                })
                .catch(() => { /* 模型列表加载失败不阻断创建 */ });

            const createBtn = WB().h('button', {
                class: 'wb-btn wb-btn-primary',
                onclick: async () => {
                    createBtn.classList.add('disabled');
                    try {
                        const pid = encodeURIComponent(ctx.project.id || '');
                        const resp = await window.AppConfig.enginePost('projects/' + pid + '/tasks', {
                            kind: ctx.flightKind,
                            name: nameInput.value.trim() || L.title + '任务',
                            parentSource: parentSourceSel.value,
                            parentModelId: modelSel.value || '',
                            f3SortieId: sortieInput.value.trim() || 'SORTIE-01',
                            f3EngineId: engineInput.value.trim() || '',
                            dataMethod: dataMethodSel.value,
                            runId: L.evolution ? 'EVO_01' : (isSteady ? 'F3_S01' : 'F3_T01')
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

            return WB().h('div', { class: 'wb-card', style: 'max-width:760px' },
                WB().h('div', { class: 'wb-section-title', style: 'margin-bottom:6px' }, '新建' + L.title + '任务'),
                WB().h('div', { class: 'wb-hint', style: 'margin:0 0 14px' }, L.sub + ';'
                    + (L.evolution
                        ? '流程:上传根架次测量Excel → 输入核验(check) → 整批执行(逐架次自动确认数据意图后按父链建模)。'
                        : '两阶段流程:先上传飞参Excel做数据意图确认(A阶段),再以确认凭据执行建模(B阶段)。')),
                WB().h('div', { class: 'wb-form-grid' },
                    WB().h('div', { class: 'wb-field' }, WB().h('label', null, '任务名称'), nameInput),
                    WB().h('div', { class: 'wb-field' }, WB().h('label', null, '父模型来源'), parentSourceSel),
                    WB().h('div', { class: 'wb-field' }, WB().h('label', null, '指定父模型(可选)'), modelSel),
                    WB().h('div', { class: 'wb-field' }, WB().h('label', null, L.evolution ? '根架次编号' : '架次编号'), sortieInput),
                    WB().h('div', { class: 'wb-field' }, WB().h('label', null, '发动机编号'), engineInput),
                    L.evolution ? null : WB().h('div', { class: 'wb-field' }, WB().h('label', null, '数据使用方式'), dataMethodSel)),
                WB().h('div', { class: 'wb-actions-row', style: 'margin-top:12px' },
                    createBtn,
                    WB().h('span', { class: 'wb-hint', style: 'margin:0' },
                        L.evolution
                            ? '创建后进入「输入核验」上传根架次测量Excel并核验输入与父依赖。'
                            : '创建后进入「数据与确认」上传飞参Excel(Data表)并执行数据意图确认。')));
        }

        /* ---------- 页签一:数据与确认(A阶段)/输入核验(evolution) ---------- */
        function dataTab() {
            const t = state.task;
            const evo = L.evolution;
            const wrap = WB().h('div', null);
            wrap.appendChild(WB().h('div', { style: 'margin-bottom:14px' },
                WB().h('div', { class: 'wb-section-title', style: 'font-size:20px;margin-bottom:2px' },
                    evo ? '输入核验' : '数据与意图确认'),
                WB().h('div', { class: 'wb-hint', style: 'margin:0' },
                    evo
                        ? (t.name || L.title) + ' / 根架次测量Excel → check(输入与父依赖核验,不计算)'
                        : (t.name || L.title) + ' / 飞参Excel(Data表) → confirmData 冻结窗口凭据')));

            wrap.appendChild(WB().h('div', { class: 'wb-form-grid', style: 'grid-template-columns:1fr 1fr;max-width:1180px' },
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '建模类型(本任务固定)'),
                    WB().h('input', { readonly: '', value: L.title + ' / ' + (evo ? 'Stage4' : 'F3') })),
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '父模型'),
                    WB().h('input', { readonly: '', value: (t.parentSource || '2p4') + (t.parentWorkbook ? ' · ' + fileName(t.parentWorkbook) : ' · 程序按来源选择') })),
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '架次 / 发动机'),
                    WB().h('input', { readonly: '', value: (t.f3SortieId || 'SORTIE-01') + ' / ' + (t.f3EngineId || '—') })),
                evo ? null : WB().h('div', { class: 'wb-field' }, WB().h('label', null, '数据使用方式'),
                    WB().h('input', { readonly: '', value: t.dataMethod === 'steady_plus_small_history' ? '稳态+小幅变化段' : '仅稳态窗口' }))));

            wrap.appendChild(fileRow(evo ? '根架次测量 Excel(Data表,必选)' : '飞参训练 Excel(Data表,必选)', 'identification', t.identificationFile, t));
            wrap.appendChild(fileRow('验证 Excel(可选)', 'validation', t.validationFile, t));

            const confirmed = evo ? !!(t.prepMessage && t.prepMessage.length)
                : !!(t.confirmationFile && t.confirmationFile.length);
            const prepRunning = state.prepWait || t.status === 'PREPARING';
            wrap.appendChild(WB().h('div', { class: 'wb-section' },
                WB().h('div', { class: 'wb-section-head' },
                    WB().h('div', { class: 'wb-section-title' }, evo ? '输入核验结果(check)' : '数据意图确认(A阶段)'),
                    prepRunning ? WB().h('span', { class: 'wb-tag wb-tag-amber' }, evo ? 'check运行中...' : 'confirmData运行中...')
                        : confirmed ? WB().h('span', { class: 'wb-tag wb-tag-teal' }, evo ? '核验通过' : '确认完成')
                        : WB().h('span', { class: 'wb-tag wb-tag-gray' }, evo ? '待核验' : '待确认')),
                WB().h('div', { style: 'padding:10px 0' },
                    prepRunning
                        ? WB().h('span', { class: 'wb-inline-loading' }, WB().h('span', { class: 'wb-inline-spinner' }),
                            evo ? '正在核验测量Excel、父模型依赖与输出目录...' : '正在解析飞参数据并冻结数据意图窗口...')
                        : WB().h('div', null, confirmed ? (t.message || (evo ? '输入核验完成' : '数据意图确认完成'))
                            : evo ? '上传测量Excel后点击"输入核验",由程序核验全批输入与父链依赖。'
                            : '上传训练Excel后点击"数据意图确认",生成确认凭据(禁父模型)。')),
                WB().h('div', { class: 'wb-hint', style: 'margin-top:6px' },
                    evo ? '核验通过后整批执行;执行时适配器对每个架次自动完成preview+数据意图确认。'
                        : '确认凭据随输出目录保存;B阶段执行建模复用该凭据并附加父模型。')));

            wrap.appendChild(WB().h('div', { class: 'wb-actions-row', style: 'margin-top:10px' },
                WB().h('button', {
                    class: 'wb-btn wb-btn-outline' + (t.identificationFile && !prepRunning ? '' : ' disabled'),
                    title: t.identificationFile ? '' : '需先上传测量Excel',
                    onclick: () => { if (t.identificationFile && !prepRunning) { window.__WB_ENGINE_POLL_UNTIL__ = Date.now() + 40000; runPrepare(); } }
                }, prepRunning ? (evo ? '核验中...' : '确认中...') : (evo ? '输入核验' : '数据意图确认')),
                WB().h('div', { class: 'wb-spacer' }),
                WB().h('button', {
                    class: 'wb-btn wb-btn-primary' + (t.status === 'READY' ? '' : ' disabled'),
                    title: t.status === 'READY' ? '' : (evo ? '请先完成输入核验' : '请先完成数据意图确认'),
                    onclick: () => { if (t.status === 'READY') { state.tab = 'run'; renderBody(); } }
                }, evo ? '执行整批建模' : '配置并执行建模')));
            return wrap;
        }

        /* ---------- 文件上传行(identification/validation) ---------- */
        function fileRow(label, kind, filePath, t) {
            const nameBox = WB().h('input', { readonly: '', value: filePath ? fileName(filePath) : '未提供', style: 'flex:1' });
            const pickBtn = WB().h('button', { class: 'wb-btn wb-btn-outline', onclick: () => fileInput.click() }, '选择文件');
            const fileInput = WB().h('input', { type: 'file', accept: '.xlsx,.xls', style: 'display:none' });
            fileInput.addEventListener('change', async () => {
                const f = fileInput.files && fileInput.files[0];
                if (!f) return;
                const fd = new FormData();
                fd.append('file', f);
                nameBox.value = '上传中:' + f.name + '...';
                try {
                    const pid = encodeURIComponent(ctx.project.id || '');
                    const tid = encodeURIComponent(t.id);
                    const resp = await window.AppConfig.engineUpload(
                        'projects/' + pid + '/tasks/' + tid + '/files?kind=' + encodeURIComponent(kind), fd);
                    if (resp && (resp.success || resp.code === 200) && resp.data) {
                        state.task = resp.data;
                        toast((kind === 'identification' ? '训练' : '验证') + 'Excel已上传', 'success');
                    } else {
                        toast((resp && resp.message) || '上传失败', 'error');
                        nameBox.value = filePath ? fileName(filePath) : '未提供';
                    }
                } catch (e) { toast('上传失败:' + e.message, 'error'); nameBox.value = filePath ? fileName(filePath) : '未提供'; }
                renderBody();
            });
            const row = WB().h('div', { class: 'wb-field', style: 'max-width:980px;margin-bottom:14px' },
                WB().h('label', null, label),
                WB().h('div', { style: 'display:flex;gap:10px' }, nameBox, pickBtn));
            row.appendChild(fileInput);
            return row;
        }

        /* ---------- 页签二:执行建模(B阶段) ---------- */
        function runTab() {
            const t = state.task;
            const wrap = WB().h('div', null);
            const running = t.status === 'RUNNING' || t.status === 'STOP_REQUESTED';

            wrap.appendChild(WB().h('div', { style: 'margin-bottom:14px' },
                WB().h('div', { class: 'wb-section-title', style: 'font-size:20px;margin-bottom:2px' }, '执行建模'),
                WB().h('div', { class: 'wb-hint', style: 'margin:0' },
                    (t.name || L.title) + ' / run(confirmationFile + 父模型) → 交付Excel')));

            wrap.appendChild(WB().h('div', { class: 'wb-form-grid', style: 'grid-template-columns:1fr 1fr;max-width:1180px;margin-bottom:14px' },
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '确认凭据(A阶段)'),
                    WB().h('input', { readonly: '', value: t.confirmationFile ? fileName(t.confirmationFile) : '—' })),
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '任务状态'),
                    WB().h('input', { readonly: '', value: str(t.message) }))));

            // 日志区
            const logBox = WB().h('pre', {
                class: 'wb-log', style: 'max-height:320px;overflow:auto;background:#101418;color:#cde3d8;'
                    + 'padding:12px;border-radius:8px;font-size:12px;line-height:1.5;white-space:pre-wrap'
            }, (state.log && state.log.length ? state.log.join('\n') : '等待MATLAB输出...'));
            wrap.appendChild(WB().h('div', { class: 'wb-section' },
                WB().h('div', { class: 'wb-section-head' },
                    WB().h('div', { class: 'wb-section-title' }, '运行日志'),
                    running ? WB().h('span', { class: 'wb-tag wb-tag-amber' }, 'MATLAB运行中...')
                        : t.status === 'COMPLETED' ? WB().h('span', { class: 'wb-tag wb-tag-teal' }, '已完成')
                        : t.status === 'FAILED' ? WB().h('span', { class: 'wb-tag wb-tag-red' }, '失败')
                        : WB().h('span', { class: 'wb-tag wb-tag-gray' }, '待执行')),
                logBox));

            wrap.appendChild(WB().h('div', { class: 'wb-actions-row', style: 'margin-top:12px' },
                WB().h('button', {
                    class: 'wb-btn wb-btn-primary' + (t.status === 'READY' && !running ? '' : ' disabled'),
                    title: t.status === 'READY' ? '' : '需A阶段确认完成(READY)',
                    onclick: () => { if (t.status === 'READY' && !running) runModel(); }
                }, running ? '建模执行中...' : '执行建模'),
                WB().h('div', { class: 'wb-spacer' }),
                running ? WB().h('button', { class: 'wb-btn wb-btn-outline', onclick: stopModel }, '请求停止') : null));
            return wrap;
        }

        /* ---------- 页签三:结果与登记 ---------- */
        function resultTab() {
            const t = state.task;
            const r = t.result || {};
            const wrap = WB().h('div', null);
            wrap.appendChild(WB().h('div', { style: 'margin-bottom:14px' },
                WB().h('div', { class: 'wb-section-title', style: 'font-size:20px;margin-bottom:2px' }, '建模结果'),
                WB().h('div', { class: 'wb-hint', style: 'margin:0' },
                    (t.name || L.title) + ' / 父模型来源 ' + (t.parentSource || '2p4') + ' / 架次 ' + (t.f3SortieId || '—'))));
            if (t.status !== 'COMPLETED') {
                wrap.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin:10px 0' },
                    t.status === 'FAILED' ? ('执行失败:' + (t.message || '详见运行日志'))
                        : '执行尚未完成;完成后此处显示交付Excel与manifest。'));
                if (t.status === 'RUNNING') startPolling();
                return wrap;
            }
            const kv = WB().h('div', { class: 'wb-kv', style: 'max-width:1180px' });
            [
                ['运行标识', r.runId || t.runId || '—'],
                ['输出目录', r.outputRoot || '—'],
                ['交付Excel', r.deliveryWorkbookFile ? fileName(r.deliveryWorkbookFile) : '未找到(检查f3输出)'],
                ['manifest', r.manifestJson ? fileName(r.manifestJson) : '—'],
                ['结果状态', '已交付(可登记到模型成果)']
            ].forEach(([k, v]) => {
                kv.appendChild(WB().h('div', { class: 'k' }, k));
                kv.appendChild(WB().h('div', { class: 'v' }, String(v)));
            });
            wrap.appendChild(kv);
            wrap.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin:10px 0' },
                '飞参建模交付Excel可登记到模型成果;登记时保留父模型来源与架次信息用于溯源。'));
            wrap.appendChild(WB().h('div', { class: 'wb-actions-row', style: 'margin-top:12px' },
                WB().h('button', {
                    class: 'wb-btn wb-btn-primary',
                    onclick: async () => {
                        try {
                            const resp = await window.AppConfig.enginePost(
                                'projects/' + encodeURIComponent(ctx.project.id || '') + '/tasks/'
                                + encodeURIComponent(t.id) + '/save-model',
                                { name: (t.name || L.title) + '-模型' });
                            if (resp && (resp.success || resp.code === 200)) {
                                toast(r.deliveryWorkbookFile ? '飞参模型已登记到模型成果' : '已登记,但未找到交付Excel', r.deliveryWorkbookFile ? 'success' : 'error');
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

        /* ---------- 动作:确认/执行/停止 ---------- */
        async function runPrepare() {
            state.prepWait = true; renderBody();
            try {
                const resp = await window.AppConfig.enginePost(
                    'projects/' + encodeURIComponent(ctx.project.id || '') + '/tasks/'
                    + encodeURIComponent(state.task.id) + '/prepare', {});
                if (resp && (resp.success || resp.code === 200) && resp.data) state.task = resp.data;
                else toast((resp && resp.message) || '数据意图确认发起失败', 'error');
            } catch (e) { toast('数据意图确认发起失败:' + e.message, 'error'); }
            state.prepWait = false;
            startPolling();
            renderBody();
        }

        async function runModel() {
            try {
                const resp = await window.AppConfig.enginePost(
                    'projects/' + encodeURIComponent(ctx.project.id || '') + '/tasks/'
                    + encodeURIComponent(state.task.id) + '/run', {});
                if (resp && (resp.success || resp.code === 200) && resp.data) state.task = resp.data;
                else toast((resp && resp.message) || '执行发起失败', 'error');
            } catch (e) { toast('执行发起失败:' + e.message, 'error'); }
            startPolling();
            renderBody();
        }

        async function stopModel() {
            try {
                await window.AppConfig.enginePost(
                    'projects/' + encodeURIComponent(ctx.project.id || '') + '/tasks/'
                    + encodeURIComponent(state.task.id) + '/stop', {});
                toast('已请求停止', 'info');
            } catch (e) { toast('请求停止失败:' + e.message, 'error'); }
            startPolling();
        }

        /* ---------- 轮询(心跳门控:仅任务活动期间请求) ---------- */
        function poll() {
            const t = state.task;
            if (!t || !ctx.project.id) return;
            const active = t.status === 'RUNNING' || t.status === 'PREPARING' || t.status === 'STOP_REQUESTED';
            if (!active && (window.__WB_ENGINE_POLL_UNTIL__ || 0) < Date.now()) return;
            window.AppConfig.engineGet(
                'projects/' + encodeURIComponent(ctx.project.id) + '/tasks/'
                + encodeURIComponent(t.id) + '/status')
                .then(resp => {
                    if (resp && (resp.success || resp.code === 200) && resp.data && resp.data.task) {
                        state.task = resp.data.task;
                        if (Array.isArray(resp.data.logTail) && resp.data.logTail.length) state.log = resp.data.logTail;
                    }
                    const cur = state.task;
                    const stillActive = cur && (cur.status === 'RUNNING' || cur.status === 'PREPARING' || cur.status === 'STOP_REQUESTED');
                    if (stillActive) window.__WB_ENGINE_POLL_UNTIL__ = Date.now() + 40000;
                    else if ((window.__WB_ENGINE_POLL_UNTIL__ || 0) < Date.now()) stopPolling();
                    if (state.tab === 'run' || state.tab === 'result' || state.tab === 'data') renderBody();
                })
                .catch(() => { });
        }
        function startPolling() {
            window.__WB_ENGINE_POLL_UNTIL__ = Date.now() + 40000;
            if (state.timer) return;
            poll();
            state.timer = setInterval(poll, 4000);
        }
        function stopPolling() {
            if (state.timer) { clearInterval(state.timer); state.timer = null; }
        }

        renderBody();
        return root;
    }

    window.Workbench.renderFlightTask = renderFlightTask;
})();
