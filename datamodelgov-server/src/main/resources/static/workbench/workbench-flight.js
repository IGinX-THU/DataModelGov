/**
 * 飞参建模任务页(G4 稳态飞参 / G5 过渡态飞参)与自演化任务页(G6)。
 * 版式依据 R06《完整界面设计说明书》:
 *   稳态飞参四页: 架次数据与工况覆盖 / 稳态参数更新 / 不确定性评估 / 飞行模型结果 (04-01~04-26)
 *   过渡态飞参四页: 架次与模型 / 飞行事件与准备 / 瞬态参数辨识 / 飞行模型结果 (05-01~05-16)
 *   自演化五视图: 演化总览 / 架次与执行 / 架次模型结果 / 不确定性评估 / 下一架次预测 (06-01~06-22)
 * 入口:
 *   window.Workbench.renderFlightTask({ project, flightKind:'flight_steady'|'flight_transient', back, navigate })
 *   window.Workbench.renderEvolutionTask({ project, back, navigate })
 */
(function () {
    const WB = () => window.Workbench;

    const KIND = {
        flight_steady: { title: '稳态飞参建模' },
        flight_transient: { title: '过渡态飞参建模' }
    };

    function taskPage(ctx) {
        const isSteady = ctx.flightKind === 'flight_steady';
        const L = KIND[ctx.flightKind] || KIND.flight_steady;
        const state = { task: null, log: [], timer: null, tab: 'data', prepWait: false, draft: {} };
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
                        // 从运行记录打开:按状态直达对应视图,失败/停止直达运行日志界面(01-15同款)
                        const st = state.task.status;
                        const wantTab = window.__WB_OPEN_TASK_TAB__;
                        delete window.__WB_OPEN_TASK_TAB__;
                        if (wantTab === 'uq') {
                            state.tab = 'uq'; // 模型成果评估记录跳转(04-16):直达UQ页签
                        } else if (['RUNNING', 'PREPARING', 'STOP_REQUESTED', 'FAILED', 'STOPPED'].includes(st)) {
                            state.tab = isSteady ? 'update' : 'run';
                        } else if (st === 'COMPLETED') {
                            state.tab = 'result';
                        }
                        // 从运行记录打开仍在跑的任务时,runProgressView自身不启动轮询,需在此补启,
                        // 否则页面停在首帧状态,只能手动刷新
                        if (['RUNNING', 'PREPARING', 'STOP_REQUESTED'].includes(st)) startPolling();
                    } else {
                        state.task = null;
                        toast((resp && resp.message) || '任务不存在', 'error');
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

        // 页签(说明书5.2四页流程 / 6.2四页)
        const TABS = isSteady
            ? [['data', '架次数据与工况覆盖'], ['update', '稳态参数更新'], ['uq', '不确定性评估'], ['result', '飞行模型结果']]
            : [['data', '架次与模型'], ['event', '飞行事件与准备'], ['run', '瞬态参数辨识'], ['result', '飞行模型结果']];
        const tabBar = WB().h('div', { class: 'wb-tabs' });
        root.appendChild(tabBar);
        const body = WB().h('div', null);
        root.appendChild(body);

        function toast(msg, kind) { if (WB() && WB().toast) WB().toast(msg, kind || 'info'); }
        function fileName(p) { return p ? String(p).split(/[\\/]/).pop() : ''; }
        function str(v) { return v == null ? '—' : String(v); }
        const running = t => t && (t.status === 'RUNNING' || t.status === 'PREPARING' || t.status === 'STOP_REQUESTED');

        function paintMeta() {
            const t = state.task;
            metaRow.textContent = t
                ? ((t.name || L.title) + ' / ' + (t.f3SortieId || '—') + ' / ' + statusText(t))
                : ((state.draft.name || L.title) + ' / ' + (state.draft.sortieId || '—') + ' / 草稿');
        }
        function statusText(t) {
            return { READY: '待执行', PREPARING: '检查中', RUNNING: '正在执行', STOP_REQUESTED: '已请求停止',
                COMPLETED: '已完成', FAILED: '失败' }[t.status] || t.status || '—';
        }

        function paintTabs() {
            const t = state.task;
            const reach = {
                data: true,
                update: !!(t && (t.confirmationFile || t.status === 'READY' || t.status === 'RUNNING' || t.status === 'COMPLETED')),
                event: !!(t && (t.status === 'READY' || t.status === 'RUNNING' || t.status === 'COMPLETED')),
                run: !!(t && (t.status === 'READY' || t.status === 'RUNNING' || t.status === 'COMPLETED')),
                uq: !!(t && t.status === 'COMPLETED'),
                result: !!(t && t.taskIdFlag !== true && (t.status === 'RUNNING' || t.status === 'COMPLETED' || t.status === 'FAILED'))
            };
            tabBar.innerHTML = '';
            TABS.forEach(([key, label]) => {
                const enabled = key === 'data' ? true : !!reach[key];
                tabBar.appendChild(WB().h('div', {
                    class: 'wb-tab' + (state.tab === key ? ' active' : '') + (enabled ? '' : ' disabled'),
                    onclick: () => {
                        if (!enabled) {
                            if (key === 'result') toast('飞行模型结果:执行完成后开放', 'info');
                            else if (key === 'uq') toast('不确定性评估:先完成一次建模后开放', 'info');
                            else toast('请先完成上一页签(数据检查与意图确认)', 'info');
                            return;
                        }
                        state.tab = key; renderBody();
                    }
                }, label));
            });
        }

        function renderBody() {
            // 检查/执行进行中不允许renderBody杀掉轮询
            const busy = state.prepWait || (state.task && ['PREPARING', 'RUNNING', 'STOP_REQUESTED'].includes(state.task.status));
            if (!busy) stopPolling();
            body.innerHTML = '';
            if (state.tab === 'data') body.appendChild(dataTab());
            else if (!state.task) { body.appendChild(emptyHint('请先在「' + TABS[0][1] + '」完成任务创建与数据检查。')); paintTabs(); paintMeta(); return; }
            else if (state.tab === 'update') body.appendChild(updateTab());
            else if (state.tab === 'event') body.appendChild(eventTab());
            else if (state.tab === 'run') body.appendChild(runTab());
            else if (state.tab === 'uq') body.appendChild(uqTab());
            else body.appendChild(resultTab());
            paintTabs();
            paintMeta();
        }

        function emptyHint(msg) {
            return WB().h('div', { class: 'wb-placeholder' }, WB().h('p', null, msg));
        }

        /* ================= 页签一: 架次数据与工况覆盖 (04-01/03/04) ================= */
        function dataTab() {
            const t = state.task;
            const wrap = WB().h('div', null);

            if (!t) {
                /* ---- 草稿(04-01): 架次/名称 + 本架次飞参 + 父模型 ---- */
                /* 本架次飞参表(对齐效果图04-01:数据用途|文件|数据记录|状态) */
                const draftFlightTable = () => {
                    const inputs = {};
                    const mkRow = (kind, usage, recordCn, stateCn) => {
                        const f = state.draft[kind];
                        const fileInput = WB().h('input', { type: 'file', accept: '.xlsx,.xls', style: 'display:none' });
                        fileInput.addEventListener('change', () => {
                            const file = fileInput.files && fileInput.files[0];
                            if (!file) return;
                            state.draft[kind] = file.name;
                            (state.draftFiles = state.draftFiles || {})[kind] = file;
                            toast('已选择文件,保存草稿后自动上传', 'info');
                            renderBody();
                        });
                        inputs[kind] = fileInput;
                        // 草稿期即可从文件库选择:按本任务/槽位类型自动筛选(训练→飞参训练数据,测试→飞参独立测试),
                        // 无需手动选类型;记录fileId,保存草稿(创建架次)后自动带入
                        const libPicked = state.draftLibrary && state.draftLibrary[kind];
                        const slotKw = kind === 'validation' ? ['飞参独立测试', '飞参测试'] : ['飞参训练'];
                        const matchSlot = k => slotKw.some(w => String(k || '').indexOf(w) >= 0);
                        const libSel = WB().h('select', { style: 'max-width:260px;padding:2px 6px;font-size:12px' });
                        let rows0 = [];
                        const refillLib = () => {
                            const keep = libPicked || libSel.value;
                            libSel.innerHTML = '';
                            libSel.appendChild(WB().h('option', { value: '' }, '从文件库选择(本槽位类型)...'));
                            // 已选项保留在列表中并回显文件名(不显示内部ID);被删文件用ID占位不丢选择。
                            // 用DOM属性.selected而非HTML属性——h()对null会setAttribute('selected','null'),
                            // 属性存在即生效,导致所有选项带selected、下拉永远钉在最后一个选项上
                            const hit = rows0.filter(r0 => matchSlot(r0.kind) || String(r0.id) === String(keep));
                            hit.forEach(r0 => {
                                const opt = WB().h('option', { value: r0.id },
                                    (r0.name || r0.id) + (r0.kind ? ' · ' + r0.kind : ''));
                                opt.selected = String(r0.id) === keep;
                                libSel.appendChild(opt);
                            });
                            if (keep && !hit.some(r0 => String(r0.id) === keep)) {
                                const opt = WB().h('option', { value: keep }, '库文件#' + keep);
                                opt.selected = true;
                                libSel.appendChild(opt);
                            }
                        };
                        libSel.addEventListener('change', () => {
                            if (!libSel.value) return;
                            (state.draftLibrary = state.draftLibrary || {})[kind] = libSel.value;
                            if (state.draftFiles) delete state.draftFiles[kind];
                            const opt = libSel.options[libSel.selectedIndex];
                            state.draft[kind] = '【库】' + (opt ? opt.textContent : libSel.value);
                            toast('已选择库内文件,保存草稿(创建架次)后自动带入', 'info');
                            renderBody();
                        });
                        window.AppConfig.engineGet('projects/'
                            + encodeURIComponent(ctx.project.id || '') + '/files/page',
                            { pageSize: 200 })
                            .then(resp => {
                                rows0 = resp && resp.data && Array.isArray(resp.data.rows) ? resp.data.rows.filter(x => x && x.id != null) : [];
                                refillLib();
                            }).catch(() => { });
                        const ops = WB().h('div', { style: 'display:flex;gap:8px;flex-wrap:wrap;margin-top:6px' },
                            WB().h('button', { class: 'wb-btn wb-btn-outline', style: 'padding:2px 10px;font-size:12px', onclick: () => {
                                if (libPicked) { toast('该用途已选择库内文件;改用本地上传请先重新创建草稿或在下拉中清除', 'info'); return; }
                                fileInput.click();
                            } }, '选择文件'),
                            libSel,
                            WB().h('button', { class: 'wb-btn wb-btn-primary', style: 'padding:2px 10px;font-size:12px',
                                title: '将下拉选中的库内文件带入本用途;保存草稿(创建架次)后自动完成',
                                onclick: () => {
                                    if (libPicked) toast('已选择库内文件;保存草稿(创建架次)后自动带入', 'info');
                                    else toast('请先在下拉中选择文件库文件,保存草稿后自动带入', 'info');
                                } }, '带入'),
                            WB().h('button', { class: 'wb-btn wb-btn-outline', style: 'padding:2px 10px;font-size:12px', title: '保存草稿(创建架次)后可预览', onclick: () => toast(f ? '本地文件在保存草稿后自动上传,届时可预览' : '请先选择文件', 'info') }, '预览'));
                        ops.appendChild(fileInput);
                        return WB().h('tr', null,
                            WB().h('td', null, usage),
                            WB().h('td', null, WB().h('div', null, f ? f : '未提供'), ops),
                            WB().h('td', null, recordCn),
                            WB().h('td', null, stateCn));
                    };
                    return WB().h('div', { style: 'max-width:1180px;overflow-x:auto' },
                        WB().h('table', { class: 'wb-table' },
                            WB().h('thead', null, WB().h('tr', null,
                                WB().h('th', null, '数据用途'), WB().h('th', null, '文件'),
                                WB().h('th', null, '数据记录'), WB().h('th', null, '状态'))),
                            WB().h('tbody', null,
                                mkRow('identification', '本次训练', '暂无(文件上传后显示)', '待检查'),
                                mkRow('validation', '独立测试(可选)', '不参与本次任务', '不影响训练'))),
                        WB().h('div', { style: 'display:flex;gap:10px;margin-top:12px' },
                            WB().h('button', { class: 'wb-btn wb-btn-outline', onclick: () => inputs.validation && inputs.validation.click() }, '+ 添加独立测试文件'),
                            WB().h('button', { class: 'wb-btn wb-btn-outline', onclick: () => toast('保存草稿(创建架次)后可查看原始记录与预览', 'info') }, '查看原始记录')));
                };
                const sortieInput = WB().h('input', { value: state.draft.sortieId || 'F-012', placeholder: '架次编号(可中文)' });
                const nameInput = WB().h('input', { value: state.draft.name || (L.title) });
                const engineInput = WB().h('input', { readonly: '', value: ctx.project.engineId || '—' });
                const parentSourceSel = WB().h('select', null,
                    WB().h('option', { value: '2p4' }, '2.4 三部件模型'),
                    WB().h('option', { value: '2p7' }, '2.7 数据更新模型'),
                    WB().h('option', { value: 'flight' }, '既有飞参模型'),
                    WB().h('option', { value: 'combined' }, 'TC27组合模型'));
                const modelSel = WB().h('select', null, WB().h('option', { value: '' }, '由程序按来源路线解析(可不指定)'));
                window.AppConfig.engineGet('projects/' + encodeURIComponent(ctx.project.id || '') + '/models')
                    .then(resp => {
                        const models = resp && Array.isArray(resp.data) ? resp.data.filter(m => m.deliveryWorkbookFile) : [];
                        models.forEach(m => modelSel.appendChild(WB().h('option', { value: m.id },
                            (m.name || m.id) + ' · ' + (m.stage || '') + ' · ' + (m.route || ''))));
                    }).catch(() => { });

                const createBtn = WB().h('button', {
                    class: 'wb-btn wb-btn-outline',
                    onclick: async () => {
                        createBtn.classList.add('disabled');
                        try {
                            const resp = await window.AppConfig.enginePost('projects/' + encodeURIComponent(ctx.project.id || '') + '/tasks', {
                                kind: ctx.flightKind,
                                name: nameInput.value.trim() || L.title,
                                parentSource: parentSourceSel.value,
                                parentModelId: modelSel.value || '',
                                f3SortieId: sortieInput.value.trim() || 'SORTIE-01',
                                f3EngineId: ctx.project.engineId || '',
                                dataMethod: 'steady_only',
                                runId: isSteady ? 'F3_S01' : 'F3_T01'
                            });
                            if (resp && (resp.success || resp.code === 200) && resp.data) {
                                state.task = resp.data;
                                // 草稿期暂存的本地文件保存草稿后自动上传,避免视图切换后"已选文件"丢失
                                const pend = state.draftFiles || {};
                                const kinds = ['identification', 'validation'].filter(k => pend[k] instanceof File);
                                try {
                                    for (const k of kinds) {
                                        const fd = new FormData(); fd.append('file', pend[k]);
                                        const up = await window.AppConfig.engineUpload(
                                            'projects/' + encodeURIComponent(ctx.project.id || '') + '/tasks/'
                                            + encodeURIComponent(state.task.id) + '/files?kind=' + encodeURIComponent(k), fd);
                                        if (up && (up.success || up.code === 200) && up.data) { state.task = up.data; toast('已上传:' + pend[k].name, 'success'); }
                                        else toast((up && up.message) || ('上传' + pend[k].name + '失败,可在当前页重新上传'), 'error');
                                    }
                                    // 草稿期选择的库内文件:任务创建后自动从文件库带入
                                    const pendLib = state.draftLibrary || {};
                                    for (const k of ['identification', 'validation'].filter(k => pendLib[k])) {
                                        try {
                                            const lb = await window.AppConfig.enginePost(
                                                'projects/' + encodeURIComponent(ctx.project.id || '') + '/tasks/'
                                                + encodeURIComponent(state.task.id) + '/files/from-library?kind='
                                                + encodeURIComponent(k) + '&fileId=' + encodeURIComponent(pendLib[k]), {});
                                            if (lb && (lb.success || lb.code === 200) && lb.data) {
                                                state.task = lb.data;
                                                toast('已从文件库带入', 'success');
                                            } else toast((lb && lb.message) || ('库文件带入失败(' + k + '),可在当前页用带入按钮重试'), 'error');
                                        } catch (e) { toast('库文件带入失败(' + k + '):' + e.message, 'error'); }
                                    }
                                } finally { delete state.draftFiles; delete state.draftLibrary; state.draft = {}; }
                                renderBody();
                            } else toast((resp && resp.message) || '保存草稿失败', 'error');
                        } catch (e) { toast('保存草稿失败:' + e.message, 'error'); }
                        createBtn.classList.remove('disabled');
                    }
                }, '保存草稿');

                wrap.appendChild(WB().h('div', { class: 'wb-form-grid', style: 'grid-template-columns:1fr 1fr 1fr;max-width:1280px' },
                    WB().h('div', { class: 'wb-field' }, WB().h('label', null, '所属发动机'), engineInput),
                    WB().h('div', { class: 'wb-field' }, WB().h('label', null, '架次编号'), sortieInput),
                    WB().h('div', { class: 'wb-field' }, WB().h('label', null, '任务名称'), nameInput)));

                wrap.appendChild(WB().h('div', { class: 'wb-section-title', style: 'margin:18px 0 8px' }, '本架次飞参'));
                wrap.appendChild(draftFlightTable());

                wrap.appendChild(WB().h('div', { class: 'wb-section-title', style: 'margin:18px 0 8px' }, '父模型'));
                wrap.appendChild(WB().h('div', { class: 'wb-form-grid', style: 'grid-template-columns:1fr 1fr auto;max-width:1180px;align-items:end' },
                    WB().h('div', { class: 'wb-field' }, WB().h('label', null, '模型来源'), parentSourceSel),
                    WB().h('div', { class: 'wb-field' }, WB().h('label', null, '选择已有模型'), modelSel),
                    WB().h('div', { class: 'wb-field' }, WB().h('button', { class: 'wb-btn wb-btn-outline', onclick: () => ctx.navigate('models') }, '查看模型与数据来源'))));
                wrap.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin:6px 0 14px' },
                    isSteady ? '瞬态参数:标称0;本次仅更新稳态参数与飞参燃油偏置。' : '固定:稳态曲线、飞参燃油偏置、装机参数;本次更新:瞬态修正参数(Visser16 13项)。'));

                wrap.appendChild(WB().h('div', { class: 'wb-actions-row', style: 'margin-top:10px' },
                    createBtn,
                    WB().h('div', { class: 'wb-spacer' }),
                    WB().h('button', { class: 'wb-btn wb-btn-primary', style: 'opacity:.5', onclick: () => toast('先保存草稿(创建架次),任务建立后可检查数据与模型', 'info') }, '检查数据与模型')));
                return wrap;
            }

            /* ---- 已建任务(04-03): 任务/架次 + 检查与意图确认 ---- */
            const SRC_CN = { '2p4': '2.4 三部件模型', '2p7': '2.7 数据更新模型', flight: '既有飞参模型', combined: 'TC27组合模型' };
            const parentBox = WB().h('input', { readonly: '', value: (SRC_CN[t.parentSource] || t.parentSource || '2.4 三部件模型')
                + (t.parentModelId ? ' · 指定模型加载中' : ' · 按来源解析') });
            if (t.parentModelId) {
                // 回显草稿期指定的项目模型名(轻量GET,失败保持占位)
                window.AppConfig.engineGet('projects/' + encodeURIComponent(ctx.project.id || '') + '/models')
                    .then(resp => {
                        const ms = resp && Array.isArray(resp.data) ? resp.data : [];
                        const m = ms.find(x => x.id === t.parentModelId);
                        if (m && document.body.contains(parentBox)) {
                            parentBox.value = (SRC_CN[t.parentSource] || t.parentSource || '2.4 三部件模型') + ' · ' + (m.name || m.id);
                        }
                    }).catch(() => { });
            }
            wrap.appendChild(WB().h('div', { class: 'wb-form-grid', style: 'grid-template-columns:1fr 1fr 1fr;max-width:1280px' },
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '任务 / 架次'),
                    WB().h('input', { readonly: '', value: (t.name || L.title) + ' / ' + (t.f3SortieId || '—') })),
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '所选父模型'), parentBox),
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '飞参数据 / 测试'),
                    WB().h('input', { readonly: '', value: (t.identificationFile ? fileName(t.identificationFile) : '未提供') + ' / ' + (t.validationFile ? fileName(t.validationFile) : '未提供独立测试') }))));

            const confirmed = !!(t.confirmationFile && t.confirmationFile.length);
            const prepRunning = state.prepWait || t.status === 'PREPARING';
            if (confirmed) {
                wrap.appendChild(WB().h('div', { class: 'wb-infobar', style: 'margin:10px 0' },
                    '数据意图已确认(完整窗口冻结凭据已生成);父模型与原始数据保持不变。'));
            } else if (t.prepMessage) {
                const failed = String(t.prepMessage).indexOf('失败') >= 0;
                wrap.appendChild(WB().h('div', { class: failed ? 'wb-tag wb-tag-red' : 'wb-infobar', style: failed ? 'display:inline-block;padding:4px 10px;border-radius:6px;margin:10px 0' : 'margin:10px 0' },
                    String(t.prepMessage)));
            }

            wrap.appendChild(WB().h('div', { class: 'wb-section-title', style: 'margin:14px 0 8px' }, '本架次飞参'));
            wrap.appendChild(uploadRow('训练飞参 Excel(Data表,必选)', 'identification', t));
            wrap.appendChild(uploadRow('独立测试 Excel(可选)', 'validation', t));

            wrap.appendChild(WB().h('div', { class: 'wb-section', style: 'margin-top:14px' },
                WB().h('div', { class: 'wb-section-head' },
                    WB().h('div', { class: 'wb-section-title' }, '数据检查与意图确认'),
                    prepRunning ? WB().h('span', { class: 'wb-tag wb-tag-amber' }, '检查中...')
                        : confirmed ? WB().h('span', { class: 'wb-tag wb-tag-teal' }, '已确认')
                        : WB().h('span', { class: 'wb-tag wb-tag-gray' }, '待检查')),
                WB().h('div', { style: 'padding:10px 0' },
                    prepRunning
                        ? WB().h('span', { class: 'wb-inline-loading' }, WB().h('span', { class: 'wb-inline-spinner' }),
                            '正在检查列映射、时间轴与父模型兼容性,并冻结完整窗口...')
                        : WB().h('div', null, confirmed
                            ? '完整有效稳态窗口按程序选定整段使用,不再裁成固定5秒;测量误差与传感器先验在配置中给定。'
                            : '上传后点击「检查数据与模型」:检查稀疏测量合同与父模型兼容性,生成数据意图凭据。')),
                WB().h('div', { class: 'wb-hint', style: 'margin-top:6px' },
                    'Ps0、Tt1、Pt3_eq、环境量及轴速按本模块字典解释;不把台架Pt2/Tt3/Pt45测量布局直接搬入。')));

            wrap.appendChild(WB().h('div', { class: 'wb-actions-row', style: 'margin-top:10px' },
                WB().h('button', {
                    class: 'wb-btn wb-btn-outline' + (t.identificationFile && !prepRunning ? '' : ' disabled'),
                    onclick: () => { if (t.identificationFile && !prepRunning) { window.__WB_ENGINE_POLL_UNTIL__ = Date.now() + 40000; runPrepare(); } }
                }, prepRunning ? '检查中...' : '检查数据与模型'),
                WB().h('div', { class: 'wb-spacer' }),
                WB().h('button', {
                    class: 'wb-btn wb-btn-primary' + (confirmed ? '' : ' disabled'),
                    onclick: () => { if (confirmed) { state.showEstimate = false; state.tab = isSteady ? 'update' : 'event'; renderBody(); } }
                }, isSteady ? '进入稳态参数更新' : '确认事件与准备计划')));
            return wrap;
        }

        /* ---- 上传行(草稿/任务两用) ---- */
        function uploadRow(label, kind, t) {
            const current = t ? (kind === 'identification' ? t.identificationFile : t.validationFile) : state.draft[kind];
            const nameBox = WB().h('input', { readonly: '', value: current ? fileName(current) : '未提供', style: 'flex:1;min-width:300px' });
            const pickBtn = WB().h('button', { class: 'wb-btn wb-btn-outline', onclick: () => fileInput.click() },
                kind === 'identification' ? '上传训练文件' : '上传独立测试文件');
            const fileInput = WB().h('input', { type: 'file', accept: '.xlsx,.xls', style: 'display:none' });
            fileInput.addEventListener('change', async () => {
                const f = fileInput.files && fileInput.files[0];
                if (!f) return;
                if (!state.task) { state.draft[kind] = f.name; (state.draftFiles = state.draftFiles || {})[kind] = f; nameBox.value = f.name; toast('已选择文件,保存草稿后自动上传', 'info'); return; }
                const fd = new FormData();
                fd.append('file', f);
                nameBox.value = '上传中:' + f.name + '...';
                try {
                    const resp = await window.AppConfig.engineUpload(
                        'projects/' + encodeURIComponent(ctx.project.id || '') + '/tasks/'
                        + encodeURIComponent(state.task.id) + '/files?kind=' + encodeURIComponent(kind), fd);
                    if (resp && (resp.success || resp.code === 200) && resp.data) {
                        state.task = resp.data;
                        toast('已上传:' + f.name, 'success');
                    } else { toast((resp && resp.message) || '上传失败', 'error'); nameBox.value = current ? fileName(current) : '未提供'; }
                } catch (e) { toast('上传失败:' + e.message, 'error'); nameBox.value = current ? fileName(current) : '未提供'; }
                renderBody();
            });
            const row = WB().h('div', { class: 'wb-field', style: 'max-width:1180px;margin-bottom:10px' },
                WB().h('label', null, label),
                WB().h('div', { style: 'display:flex;gap:10px;flex-wrap:wrap;align-items:center' },
                    nameBox,
                    pickBtn,
                    (function () {
                        // 按槽位类型自动筛选:训练→飞参训练数据,测试→飞参独立测试(kind标签或文件名任一命中);
                        // 无匹配显示空提示,不回退显示全部(避免训练/测试混选)
                        const slotKw = kind === 'validation' ? ['飞参独立测试', '飞参测试', '独立测试', '测试', '检验', 'validation', 'test'] : ['飞参训练', '训练', 'train'];
                        const matchSlot = k => slotKw.some(w => String(k || '').indexOf(w) >= 0);
                        const libSel = WB().h('select', { style: 'max-width:260px' },
                            WB().h('option', { value: '' }, '从文件库选择(本槽位类型)...'));
                        window.AppConfig.engineGet('projects/'
                            + encodeURIComponent(ctx.project.id || '') + '/files/page',
                            { pageSize: 200 })
                            .then(resp => {
                                const rows = resp && resp.data && Array.isArray(resp.data.rows) ? resp.data.rows.filter(x => x && x.id != null) : [];
                                const hit = rows.filter(r0 => /\.(xlsx|xls)$/i.test(String(r0.name || '')) && (matchSlot(r0.kind) || matchSlot(r0.name)));
                                if (!hit.length) {
                                    libSel.appendChild(WB().h('option', { value: '' }, '本槽位类型暂无库内文件(可直接上传)'));
                                    return;
                                }
                                hit.forEach(r0 => libSel.appendChild(WB().h('option', { value: r0.id },
                                    (r0.name || r0.id) + (r0.kind ? ' · ' + r0.kind : ''))));
                            })
                            .catch(() => { });
                        return libSel;
                    })(),
                    WB().h('button', {
                        class: 'wb-btn wb-btn-outline',
                        style: state.task ? '' : 'opacity:.5',
                        title: state.task ? '' : '先保存草稿(创建架次),再从文件库带入',
                        onclick: async () => {
                            const sel = row.querySelector('select');
                            if (!state.task) { toast('先保存草稿(创建架次),再从文件库带入', 'error'); return; }
                            if (!sel || !sel.value) { toast('请先在下拉中选择库内文件', 'error'); return; }
                            try {
                                const resp = await window.AppConfig.enginePost(
                                    'projects/' + encodeURIComponent(ctx.project.id || '') + '/tasks/'
                                    + encodeURIComponent(state.task.id) + '/files/from-library?kind='
                                    + encodeURIComponent(kind) + '&fileId=' + encodeURIComponent(sel.value), {});
                                if (resp && (resp.success || resp.code === 200) && resp.data) {
                                    state.task = resp.data;
                                    toast('已从文件库带入', 'success');
                                    renderBody();
                                } else toast((resp && resp.message) || '带入失败', 'error');
                            } catch (e) { toast('带入失败:' + e.message, 'error'); }
                        }
                    }, '带入'),
                    WB().h('button', {
                        class: 'wb-btn wb-btn-outline',
                        style: current ? '' : 'opacity:.5',
                        onclick: async () => {
                            if (!current) { toast('请先上传或从文件库带入文件', 'error'); return; }
                            if (!state.task) { toast('本地文件在保存草稿后自动上传,届时可预览', 'info'); return; }
                            const name = fileName(current);
                            try {
                                // 任务直传/带入文件走任务文件预览接口(文件不必在文件库)
                                const pv = await window.AppConfig.engineGet('projects/'
                                    + encodeURIComponent(ctx.project.id || '') + '/tasks/'
                                    + encodeURIComponent(state.task.id) + '/file-preview?kind=' + encodeURIComponent(kind));
                                if (pv && (pv.success || pv.code === 200) && pv.data) {
                                    window.Workbench.showFilePreview(pv.data.fileName || name, pv.data);
                                } else toast((pv && pv.message) || '预览失败', 'error');
                            } catch (e) { toast('预览失败:' + e.message, 'error'); }
                        }
                    }, '预览')));
            row.appendChild(fileInput);
            return row;
        }

        /* ================= 页签二(稳态): 稳态参数更新 (04-06/07/08) ================= */
        function updateTab() {
            const t = state.task;
            const wrap = WB().h('div', null);
            const isRunPhase = t.status === 'RUNNING' || t.status === 'STOP_REQUESTED';
            const confirmed = !!(t.confirmationFile && t.confirmationFile.length);

            if (confirmed) {
                wrap.appendChild(WB().h('div', { class: 'wb-infobar', style: 'margin-bottom:12px' },
                    '选段已确认:' + (t.f3SortieId || '') + ' 完整窗口均值;本次运行只生成新结果,不覆盖父模型。'));
            }

            if (isRunPhase || t.status === 'COMPLETED' || t.status === 'FAILED' || t.status === 'STOPPED' || state.showEstimate) {
                // FAILED/STOPPED也直达运行日志视图(阶段卡+状态+日志+重新辨识);
                // 「重新辨识→返回配置」会置showEstimate=false回到参数表单
                // READY+showEstimate:「检查配置并估时」后进入估时/运行前检查视图(showEstimate只在此消费,
                // 否则点按钮后页面停留在参数表单看似无反应);「返回配置」会置false回到表单
                wrap.appendChild(runProgressView(t));
                return wrap;
            }

            /* ---- 参数配置(04-06) ---- */
            const routeSel = WB().h('select', null,
                WB().h('option', { value: 'steady' }, '稳态模型(默认 R1)'),
                WB().h('option', { value: 'transient_instant' }, '瞬态时刻模型(默认 R2)'));
            routeSel.value = t.parentRoute === 'transient_instant' ? 'transient_instant' : 'steady';
            const useSel = WB().h('select', null,
                WB().h('option', { value: 'steady_only', selected: t.dataMethod !== 'steady_plus_small_history' ? '' : null }, '稳态窗口均值'),
                WB().h('option', { value: 'steady_plus_small_history', selected: t.dataMethod === 'steady_plus_small_history' ? '' : null }, '稳态均值 + 小幅变化辅助'));
            const lambdaInput = WB().h('input', { value: t.regularizationStrength != null ? t.regularizationStrength : '0.05' });

            wrap.appendChild(WB().h('div', { class: 'wb-form-grid', style: 'grid-template-columns:1fr 1fr;max-width:1180px' },
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '求解路径'), routeSel),
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '本次数据用途'), useSel),
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '正则化强度 λ'), lambdaInput)));

            wrap.appendChild(WB().h('div', { class: 'wb-section-title', style: 'margin:16px 0 8px' }, '本次更新范围'));
            const scopeTbl = WB().h('table', { class: 'wb-table' },
                WB().h('tr', null, ['对象', '初始值 / 正则化参考', '本次处理'].map(x => WB().h('th', null, x))),
                WB().h('tr', null, WB().h('td', null, '稳态修正曲线'), WB().h('td', null, '父模型对应节点值'), WB().h('td', null, '有数据支撑的节点更新,其余沿用')),
                WB().h('tr', null, WB().h('td', null, '装机等效参数 Kdist'), WB().h('td', null, '现行装机参数合同'), WB().h('td', null, '按当前模型合同更新')),
                WB().h('tr', null, WB().h('td', null, '飞参燃油偏置 Wf_bias'), WB().h('td', null, '0 kg/s(本架次建模先验)'), WB().h('td', null, '独立估计;不复制台架测量偏置')),
                WB().h('tr', null, WB().h('td', null, '瞬态修正系数'), WB().h('td', null, '父模型为标称0'), WB().h('td', null, '固定,不参与本次辨识')));
            wrap.appendChild(scopeTbl);
            wrap.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin:8px 0' },
                '节点横坐标沿用父模型;台架或上架次燃油偏置不自动成为本架次已知偏置。'));

            wrap.appendChild(WB().h('div', { class: 'wb-actions-row', style: 'margin-top:10px' },
                WB().h('button', { class: 'wb-btn wb-btn-outline', onclick: () => { state.tab = 'data'; renderBody(); } }, '← 返回覆盖'),
                WB().h('div', { class: 'wb-spacer' }),
                WB().h('button', {
                    class: 'wb-btn wb-btn-primary',
                    onclick: () => applyConfigAndGo(routeSel.value, useSel.value, lambdaInput.value)
                }, '检查配置并估时')));
            return wrap;
        }

        async function applyConfigAndGo(route, dataMethod, lambda) {
            const t = state.task;
            try {
                const resp = await window.AppConfig.enginePost(
                    'projects/' + encodeURIComponent(ctx.project.id || '') + '/tasks/'
                    + encodeURIComponent(t.id) + '/config', {
                    parentRoute: route, dataMethod: dataMethod,
                    regularizationStrength: parseFloat(lambda) || 0.05
                });
                if (resp && (resp.success || resp.code === 200) && resp.data) state.task = resp.data;
                else toast((resp && resp.message) || '配置保存失败', 'error');
            } catch (e) { toast('配置保存失败:' + e.message, 'error'); }
            state.showEstimate = true;
            renderBody();
        }

        /* ---- 估时 + 运行前检查(04-07)与运行过程(04-08) ---- */
        function runProgressView(t) {
            const wrap = WB().h('div', null);
            const isRun = t.status === 'RUNNING' || t.status === 'STOP_REQUESTED';
            // 估算/确认视图仅在明确请求时进入:READY默认展示;FAILED/STOPPED默认直达日志视图(01-15:
            // 失败任务直达错误定位与日志,不先展示重新辨识配置页),点"重新辨识"(showEstimate=true)后进入。
            // STOP_REQUESTED(等待安全点)不进入——04-23:保存进度前不开放重跑
            const showEstimateView = !isRun && (
                (t.status === 'READY' && state.showEstimate !== false)
                || ((t.status === 'FAILED' || t.status === 'STOPPED') && state.showEstimate === true));

            if (!isRun && showEstimateView) {
                if (t.status === 'STOPPED') {
                    wrap.appendChild(WB().h('div', { class: 'wb-infobar', style: 'margin-bottom:12px' },
                        '上一次运行已安全停止(进度与产物保留)。重新辨识将发起新一轮执行,按运行标识区分历史,不覆盖父模型。'));
                }
                wrap.appendChild(WB().h('div', { class: 'wb-infobar', style: 'margin-bottom:12px' },
                    '输入、父模型、选段与运行包检查通过;本次运行只生成新结果,不覆盖父模型。'));
                wrap.appendChild(WB().h('div', { class: 'wb-section-title', style: 'margin:6px 0 8px' }, '本次将执行'));
                const kv = WB().h('div', { class: 'wb-kv', style: 'max-width:1180px' });
                [
                    ['数据', (t.identificationFile ? fileName(t.identificationFile) : '—') + ';完整窗口均值;独立测试' + (t.validationFile ? '已提供' : '无')],
                    ['父模型', (t.parentSource || '2p4') + (t.parentWorkbook ? ' · ' + fileName(t.parentWorkbook) : '')],
                    ['参数', (t.dataMethod === 'steady_plus_small_history' ? '稳态+小幅混合' : '稳态曲线 + Kdist + 燃油偏置')],
                    ['算法', '瞬态时刻 / 独立节点 / Tikhonov λ=' + (t.regularizationStrength != null ? t.regularizationStrength : '0.05')],
                    ['输出', '新运行;训练对照、全部参数、模型Excel与运行记录']
                ].forEach(([k, v]) => { kv.appendChild(WB().h('div', { class: 'k' }, k)); kv.appendChild(WB().h('div', { class: 'v' }, v)); });
                wrap.appendChild(kv);
                wrap.appendChild(WB().h('div', { class: 'wb-actions-row', style: 'margin-top:14px' },
                    WB().h('button', { class: 'wb-btn wb-btn-outline', onclick: () => { state.showEstimate = false; state.tab = 'update'; renderBody(); } }, '← 返回配置'),
                    WB().h('div', { class: 'wb-spacer' }),
                    WB().h('button', { class: 'wb-btn wb-btn-primary', onclick: runModel }, '▶ 开始稳态参数更新')));
                return wrap;
            }

            /* 运行过程(04-08): 阶段卡 + 用时 + 日志(不伪造总体完成百分比) */
            // 04-23:已请求暂停≠已暂停——完成后端安全点并保存进度前,保持过渡提示且不重复受理
            if (t.status === 'STOP_REQUESTED') {
                wrap.appendChild(WB().h('div', { class: 'wb-infobar', style: 'border-left:4px solid #d97706;background:#fffbeb;color:#92400e' },
                    '⚠ 已请求安全暂停。完成当前安全计算单元后保存进度;未保存前不显示"已暂停",发现身份变化只允许另建运行、不修改旧签名续跑。'));
            }
            const stages = [
                ['输入检查', '已完成'], ['准备与覆盖', '已完成'],
                ['参数更新', isRun ? '执行中' : t.status === 'COMPLETED' ? '已完成' : '—'],
                ['最终核查', t.status === 'COMPLETED' ? '已完成' : '待执行'],
                ['结果写出', t.status === 'COMPLETED' ? '已完成' : '待执行']
            ];
            const stageRow = WB().h('div', { style: 'display:grid;grid-template-columns:repeat(5,1fr);gap:12px;margin:12px 0' });
            stages.forEach(([name, st]) => {
                const active = String(st).indexOf('执行中') >= 0;
                stageRow.appendChild(WB().h('div', { class: 'wb-card', style: 'padding:12px 14px;' + (active ? 'border-color:#0f766e' : '') },
                    WB().h('div', { style: 'font-weight:600;margin-bottom:4px' + (active ? ';color:#0f766e' : '') }, name),
                    WB().h('div', { class: 'wb-hint', style: 'margin:0' }, st)));
            });
            wrap.appendChild(stageRow);

            const durTxt = t.startedAt && t.finishedAt ? formatDur(t.finishedAt - t.startedAt)
                : t.startedAt ? formatDur(Date.now() - t.startedAt) + '(累计)' : '—';
            wrap.appendChild(WB().h('div', { class: 'wb-form-grid', style: 'grid-template-columns:1fr 1fr 1fr;max-width:1180px;margin-bottom:12px' },
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '已用计算时间'), WB().h('input', { readonly: '', value: durTxt })),
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '状态'), WB().h('input', { readonly: '', value: statusText(t) + (t.message ? ' · ' + t.message : '') })),
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '完成判定'),
                    WB().h('input', { readonly: '', value: '以程序实际阶段为准;不显示伪造总体百分比' }))));

            wrap.appendChild(WB().h('div', { class: 'wb-section-title', style: 'margin:10px 0 8px' }, '运行日志'));
            wrap.appendChild(WB().h('pre', {
                class: 'wb-log', style: 'max-height:260px;overflow:auto;background:#101418;color:#cde3d8;padding:12px;border-radius:8px;font-size:12px;line-height:1.5;white-space:pre-wrap'
            }, (state.log && state.log.length ? state.log.join('\n') : '等待MATLAB输出...')));

            wrap.appendChild(WB().h('div', { class: 'wb-actions-row', style: 'margin-top:12px' },
                WB().h('button', {
                    class: 'wb-btn wb-btn-outline' + (isRun && t.status !== 'STOP_REQUESTED' ? '' : ' disabled'),
                    title: t.status === 'STOP_REQUESTED' ? '停止请求已受理;等待后端安全点保存进度' : '让本次算法在安全点结束并保存,不强杀',
                    onclick: () => { if (isRun && t.status !== 'STOP_REQUESTED') stopModel(); }
                }, t.status === 'STOP_REQUESTED' ? '已请求安全暂停(等待安全点)' : isRun ? '请求安全暂停' : '请求安全暂停(未在运行)'),
                WB().h('div', { class: 'wb-spacer' }),
                t.status === 'COMPLETED' ? WB().h('button', { class: 'wb-btn wb-btn-primary', onclick: () => { state.tab = 'result'; renderBody(); } }, '查看飞行模型结果') :
                (t.status === 'FAILED' || t.status === 'STOPPED') ? WB().h('button', { class: 'wb-btn wb-btn-primary', onclick: () => { state.showEstimate = true; renderBody(); } }, '重新辨识') : null));
            return wrap;
        }

        function formatDur(ms) {
            const s = Math.max(0, Math.round(ms / 1000));
            return s >= 60 ? (Math.floor(s / 60) + '分' + (s % 60) + '秒') : (s + '秒');
        }

        /* ================= 页签二(瞬态): 飞行事件与准备 (05-03/04) ================= */
        function eventTab() {
            const t = state.task;
            const wrap = WB().h('div', null);
            const confirmed = !!(t.confirmationFile && t.confirmationFile.length) || t.status === 'READY';
            wrap.appendChild(WB().h('div', { class: 'wb-infobar', style: 'margin-bottom:12px' },
                confirmed
                    ? '大幅事件与准备前史已确认;多事件联合辨识同一组瞬态参数,未选择的记录仍保留。'
                    : '本页在A阶段检查(架次与模型)完成后,由程序提取大幅事件与局部准备段;实际采用范围以求解器返回为准。'));
            wrap.appendChild(WB().h('div', { class: 'wb-kv', style: 'max-width:1180px' }));
            const kv = wrap.querySelector('.wb-kv');
            [
                ['事件来源', t.identificationFile ? fileName(t.identificationFile) : '—'],
                ['稳态父模型(冻结)', t.parentWorkbook ? fileName(t.parentWorkbook) : (t.parentSource || '2p4')],
                ['数据意图', t.confirmationFile ? '已确认(完整窗口冻结)' : '待确认'],
                ['程序说明', t.prepMessage || '—']
            ].forEach(([k, v]) => { kv.appendChild(WB().h('div', { class: 'k' }, k)); kv.appendChild(WB().h('div', { class: 'v' }, String(v))); });
            wrap.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin:10px 0' },
                '事件、拟合窗口与实际准备前史分列显示;没有有效事件时程序报告原因,不回退成整段强行辨识。'));
            wrap.appendChild(WB().h('div', { class: 'wb-actions-row', style: 'margin-top:10px' },
                WB().h('div', { class: 'wb-spacer' }),
                WB().h('button', {
                    class: 'wb-btn wb-btn-primary' + (confirmed ? '' : ' disabled'),
                    onclick: () => { if (confirmed) { state.tab = 'run'; renderBody(); } }
                }, '进入瞬态参数辨识')));
            return wrap;
        }

        /* ================= 页签三(瞬态): 瞬态参数辨识 (05-05~07) ================= */
        function runTab() {
            const t = state.task;
            const wrap = WB().h('div', null);
            const isRun = t.status === 'RUNNING' || t.status === 'STOP_REQUESTED';

            if (!isRun && t.status === 'READY') {
                wrap.appendChild(WB().h('div', { class: 'wb-infobar', style: 'margin-bottom:12px' },
                    '运行前核对:13项瞬态参数待辨识;固定稳态/燃油/装机参数沿用父模型;默认 λ=0.05、最多6轮、0.1秒积分(可选0.025秒)。'));
                wrap.appendChild(WB().h('div', { class: 'wb-kv', style: 'max-width:1180px' }));
                const kv = wrap.querySelector('.wb-kv');
                [
                    ['辨识对象', '13项瞬态修正参数(Visser16固定参数集,不清零)'],
                    ['事件', (t.prepMessage ? String(t.prepMessage) : '已确认事件与准备计划')],
                    ['预计范围', '以程序估时为准;执行前显示,不虚报停续能力']
                ].forEach(([k, v]) => { kv.appendChild(WB().h('div', { class: 'k' }, k)); kv.appendChild(WB().h('div', { class: 'v' }, v)); });
                wrap.appendChild(WB().h('div', { class: 'wb-actions-row', style: 'margin-top:14px' },
                    WB().h('button', { class: 'wb-btn wb-btn-outline', onclick: () => { state.tab = 'event'; renderBody(); } }, '← 返回事件'),
                    WB().h('div', { class: 'wb-spacer' }),
                    WB().h('button', { class: 'wb-btn wb-btn-primary', onclick: runModel }, '▶ 开始瞬态参数辨识')));
                return wrap;
            }

            wrap.appendChild(runProgressView(t));
            return wrap;
        }

        /* ================= 不确定性评估 (04-13~04-16) ================= */
        function uqTab() {
            const t = state.task;
            const wrap = WB().h('div', null);

            // 04-16连接(双向):任何状态都可查看此任务的已有评估记录
            const uqPrevBox = WB().h('div', null);
            wrap.appendChild(WB().h('div', { class: 'wb-actions-row', style: 'margin-bottom:10px' },
                WB().h('button', {
                    class: 'wb-btn wb-btn-outline',
                    onclick: () => { uqPrevBox.innerHTML = ''; uqPrevBox.appendChild(uqRecordDrawer()); }
                }, '查看此模型的已有评估')));
            wrap.appendChild(uqPrevBox);

            function uqRecordDrawer() {
                const box = WB().h('div', { class: 'wb-card', style: 'padding:14px;max-width:1180px;margin-bottom:12px' },
                    WB().h('div', { class: 'wb-section-title', style: 'margin-bottom:8px' }, '此任务的评估记录'));
                const holder = WB().h('div', null, WB().h('div', { class: 'wb-hint' }, '正在加载...'));
                box.appendChild(holder);
                window.AppConfig.engineGet('projects/' + encodeURIComponent(ctx.project.id || '') + '/uq-records')
                    .then(resp => {
                        const list = resp && (resp.success || resp.code === 200) && Array.isArray(resp.data) ? resp.data : [];
                        const mine = list.filter(r => r.taskId === t.id);
                        holder.innerHTML = '';
                        if (!mine.length) { holder.appendChild(WB().h('div', { class: 'wb-hint' }, '暂无评估记录。')); return; }
                        holder.appendChild(WB().h('table', { class: 'wb-table' },
                            WB().h('tr', null, ['运行标识', '方法', '状态', '开始时间', '说明'].map(x => WB().h('th', null, x))),
                            mine.map(r => WB().h('tr', null,
                                WB().h('td', null, r.runId || r.id),
                                WB().h('td', null, r.method || '—'),
                                WB().h('td', null, r.status === 'COMPLETED' ? '已完成' : r.status === 'FAILED' ? '失败' : (r.status || '—')),
                                WB().h('td', { class: 'wb-hint' }, r.startedAt ? new Date(r.startedAt).toLocaleString() : '—'),
                                WB().h('td', { class: 'wb-hint' }, r.message || '—')))));
                    })
                    .catch(e => { holder.innerHTML = ''; holder.appendChild(WB().h('div', { class: 'wb-hint' }, '加载失败:' + e.message)); });
                return box;
            }

            if (t.status !== 'COMPLETED') {
                wrap.appendChild(WB().h('div', { class: 'wb-infobar', style: 'margin-bottom:12px' },
                    'UQ独立配置与保存:评估对象、观测、固定参数、概率来源和先验重设依据明确;当前新C/D评估限实际支持的纯稳态均值路线。'));
                wrap.appendChild(WB().h('span', { class: 'wb-hint' }, '完成一次建模并保存模型后开放评估入口。'));
                return wrap;
            }
            // 04-13:确定性模型已保存——本页提供真实评估入口(评估对象/方法/计算设置/先验说明)
            wrap.appendChild(WB().h('div', { class: 'wb-infobar', style: 'margin-bottom:12px' },
                '确定性模型已保存。可以新建评估,也可以跳过评估直接进行新工况预测。'));

            /* 执行中:进度入口(状态由任务轮询刷新;独立复算与主样本分开,不提前标记统计通过) */
            if (t.uqStatus === 'EXECUTING' || t.uqStatus === 'PREPARING') {
                wrap.appendChild(WB().h('div', { class: 'wb-infobar', style: 'margin-bottom:12px' },
                    'UQ评估' + (t.uqStatus === 'PREPARING' ? '准备中' : '执行中')
                    + ';按 合同与先验 → 主样本计算 → 独立复算 → 参数汇总 → 结果写出 顺序执行(04-14)。'));
                wrap.appendChild(WB().h('div', { class: 'wb-actions-row' },
                    WB().h('button', { class: 'wb-btn wb-btn-outline', onclick: () => {
                        const base = window.AppConfig.api.baseURL;
                        window.open(base + '/api/engine/projects/' + encodeURIComponent(ctx.project.id)
                            + '/tasks/' + encodeURIComponent(t.id) + '/uq-log-stream?token='
                            + encodeURIComponent(window.AppConfig.getToken() || ''), '_blank');
                    } }, '📄 打开评估日志'),
                    WB().h('button', { class: 'wb-btn wb-btn-outline', onclick: async () => {
                        try {
                            await window.AppConfig.enginePost('projects/' + encodeURIComponent(ctx.project.id)
                                + '/tasks/' + encodeURIComponent(t.id) + '/uq/stop', {});
                            toast('已请求取消UQ评估(协作取消,结果作废)', 'info');
                        } catch (e) { toast('取消失败:' + e.message, 'error'); }
                        startPolling();
                    } }, '请求协作取消'),
                    WB().h('div', { class: 'wb-spacer' }),
                    WB().h('button', { class: 'wb-btn wb-btn-primary', onclick: () => { state.tab = 'result'; renderBody(); } }, '返回飞行模型结果')));
                startPolling();
                return wrap;
            }

            // 失败留痕视图(与自演化页同款):错误定位+日志,配置保留在下方便于重发
            if (t.uqStatus === 'FAILED') {
                wrap.appendChild(WB().h('div', { class: 'wb-tag wb-tag-red', style: 'display:inline-block;padding:6px 12px;margin-bottom:10px' },
                    'UQ评估失败:' + (t.uqMessage || '详见日志')));
                wrap.appendChild(WB().h('div', { class: 'wb-section-title', style: 'margin:6px 0 8px' }, '评估日志'));
                wrap.appendChild(WB().h('pre', {
                    style: 'max-height:260px;overflow:auto;background:#101418;color:#cde3d8;padding:12px;border-radius:8px;font-size:12px;line-height:1.5;white-space:pre-wrap'
                }, (state.log && state.log.length ? state.log.join('\n') : '(无日志)')));
            }

            state.uqMethod = state.uqMethod || 'C';
            state.uqParticle = state.uqParticle || '512';
            const objInp = WB().h('input', { readonly: '', value: (t.name || t.runId || '本架次模型')
                + ' / ' + (t.identificationFile ? fileName(t.identificationFile) : '训练窗口') });
            const idInp = WB().h('input', { readonly: '', value: 'UQ-' + (t.runId || t.id) + '(记录标识由服务端生成)' });
            const methodSel = WB().h('select', { style: 'width:100%' });
            const optC = WB().h('option', { value: 'C' }, 'C:非线性粒子评估');
            const optD = WB().h('option', { value: 'D' }, 'D:快速局部初评');
            optC.selected = state.uqMethod !== 'D'; optD.selected = state.uqMethod === 'D';
            methodSel.appendChild(optC); methodSel.appendChild(optD);
            methodSel.addEventListener('change', () => { state.uqMethod = methodSel.value; });
            const particleSel = WB().h('select', { style: 'width:100%' });
            const opt5 = WB().h('option', { value: '512' }, '主样本512 · 独立复算512');
            const opt10 = WB().h('option', { value: '1024' }, '主样本1024 · 独立复算1024');
            opt5.selected = state.uqParticle !== '1024'; opt10.selected = state.uqParticle === '1024';
            particleSel.appendChild(opt5); particleSel.appendChild(opt10);
            particleSel.addEventListener('change', () => { state.uqParticle = particleSel.value; });
            wrap.appendChild(WB().h('div', { class: 'wb-form-grid', style: 'grid-template-columns:1fr 1fr;max-width:1180px;margin-bottom:6px' },
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '评估对象(本任务已保存模型)'), objInp),
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '本次评估编号'), idInp),
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '方法'), methodSel),
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '计算设置(粒子合同)'), particleSel)));
            wrap.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin:0 0 10px' },
                '当前仅支持R2稳态均值UQ;D快速局部初评可另选,两种结果分别保存、不互相覆盖。'));

            /* 配置内容表(04-13):由本任务数据如实汇总 */
            wrap.appendChild(WB().h('table', { class: 'wb-table', style: 'max-width:1180px' },
                WB().h('tr', null, ['配置内容', '当前选择'].map(x => WB().h('th', null, x))),
                WB().h('tr', null, WB().h('td', null, '建模证据'),
                    WB().h('td', { class: 'wb-hint' }, (t.identificationFile ? fileName(t.identificationFile) : '—')
                        + ' 完整窗口均值;独立测试' + (t.validationFile ? '已提供(' + fileName(t.validationFile) + ')' : '未提供;不显示测试通过率'))),
                WB().h('tr', null, WB().h('td', null, '先验设置'),
                    WB().h('td', { class: 'wb-hint' }, '确定性结果作为数值起点;不将本次结果或其他模型后验自动作为概率先验')),
                WB().h('tr', null, WB().h('td', null, '参数与条件项'),
                    WB().h('td', { class: 'wb-hint' }, '全部参数与燃油偏置节点(以交付Excel参数表为准);固定继承项不参与抽样')),
                WB().h('tr', null, WB().h('td', null, '数值起点'),
                    WB().h('td', { class: 'wb-hint' }, '使用本次确定性结果')),
                WB().h('tr', null, WB().h('td', null, '输出范围'),
                    WB().h('td', { class: 'wb-hint' }, '全部参数与燃油节点区间、条件处理说明、诊断及独立评估文件(04-15:区间来源逐节点可追溯)')),
                WB().h('tr', null, WB().h('td', null, '预计耗时'),
                    WB().h('td', { class: 'wb-hint' }, '首次粗估约30分钟(参考20~50分钟);含准备、主计算、复算和写出,不含新工况预测;实际以评估记录为准'))));

            /* 发起:确保已登记模型成果(UQ按已登记成果的交付Excel评估),再走与试车建模同一UQ接口 */
            const launch = async () => {
                try {
                    let assetId = null;
                    const fetchModels = () => window.AppConfig.engineGet(
                        'projects/' + encodeURIComponent(ctx.project.id) + '/models');
                    let respM = await fetchModels();
                    let models = respM && (respM.success || respM.code === 200) && Array.isArray(respM.data) ? respM.data : [];
                    let mine = models.filter(m => m.taskId === t.id);
                    if (!mine.length) {
                        const reg = await window.AppConfig.enginePost(
                            'projects/' + encodeURIComponent(ctx.project.id) + '/tasks/'
                            + encodeURIComponent(t.id) + '/save-model', { name: (t.name || '稳态飞参') + '-模型' });
                        if (!(reg && (reg.success || reg.code === 200))) {
                            toast((reg && reg.message) || '登记模型成果失败,无法发起评估', 'error'); return;
                        }
                        respM = await fetchModels();
                        models = respM && (respM.success || respM.code === 200) && Array.isArray(respM.data) ? respM.data : [];
                        mine = models.filter(m => m.taskId === t.id);
                    }
                    if (!mine.length || !mine[mine.length - 1].deliveryWorkbookFile) {
                        toast('模型成果缺少交付Excel,无法评估;请检查辨识输出后重新登记', 'error'); return;
                    }
                    assetId = mine[mine.length - 1].id;
                    const resp = await window.AppConfig.enginePost(
                        'projects/' + encodeURIComponent(ctx.project.id) + '/tasks/'
                        + encodeURIComponent(t.id) + '/uq?method=' + encodeURIComponent(state.uqMethod),
                        { modelAssetId: assetId, particleCount: parseInt(state.uqParticle, 10) });
                    if (resp && (resp.success || resp.code === 200)) {
                        toast('UQ评估已发起;进度见本页与评估记录', 'success');
                        startPolling(); renderBody();
                    } else toast((resp && resp.message) || '发起UQ失败', 'error');
                } catch (e) { toast('发起UQ失败:' + e.message, 'error'); }
            };
            wrap.appendChild(WB().h('div', { class: 'wb-actions-row', style: 'margin-top:14px' },
                WB().h('button', { class: 'wb-btn wb-btn-outline', onclick: () => ctx.navigate('predictions') }, '→ 跳过并进入输出预测'),
                WB().h('div', { class: 'wb-spacer' }),
                WB().h('button', { class: 'wb-btn wb-btn-primary', onclick: launch }, '▶ 检查配置并开始评估')));
            wrap.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin-top:10px;max-width:1180px' },
                '评估按 合同与先验 → 主样本计算 → 独立复算 → 参数汇总 → 结果写出 执行(04-14);'
                + '完成后全部参数及燃油偏置的区间来源逐节点可追溯,有限样本评估的统计限制随结果保存,不标为全局完备后验(04-15)。'));
            return wrap;
        }

        /* ================= 飞行模型结果 (04-09~12) ================= */
        function resultTab() {
            const t = state.task;
            const r = t.result || {};
            const wrap = WB().h('div', null);
            // 04-22:数值停止/物理可用/统计结论分开——未确认收敛时琥珀提示,保存语义如实说明
            if (t.status === 'COMPLETED' && (r.stopReason || /迭代|iteration/i.test(String(t.message || '')))) {
                wrap.appendChild(WB().h('div', { class: 'wb-infobar', style: 'border-left:4px solid #d97706;background:#fffbeb;color:#92400e' },
                    '⚠ ' + (r.stopReason ? ('停止原因: ' + r.stopReason + '。') : '')
                    + '本次结果尚未确认收敛;模型文件和有效结果可以保存及独立验证,不将本次结果标为统计校准。'));
            }
            wrap.appendChild(WB().h('div', { class: 'wb-infobar', style: 'margin-bottom:12px' },
                t.status === 'COMPLETED'
                    ? ((t.runId || 'RUN') + ' 已结束;训练必展,独立测试' + (t.validationFile ? '已提供' : '未提供') + ';UQ' + (t.uqDone ? '已执行' : '未执行') + '。')
                    : t.status === 'FAILED' ? ('执行失败:' + (t.message || '详见运行日志')) : '执行中;完成后此处显示训练输出与全部参数。'));
            if (t.status !== 'COMPLETED') {
                if (t.status === 'RUNNING') startPolling();
                return wrap;
            }
            const kv = WB().h('div', { class: 'wb-kv', style: 'max-width:1180px' });
            [
                ['运行标识', r.runId || t.runId || '—'],
                ['训练集', (t.identificationFile ? fileName(t.identificationFile) : '—') + ';完整窗口均值'],
                ['独立测试', t.validationFile ? fileName(t.validationFile) : '未提供(不影响训练)'],
                ['预计 / 实际', (t.startedAt && t.finishedAt) ? formatDur(t.finishedAt - t.startedAt) : '—'],
                ['交付Excel', r.deliveryWorkbookFile ? fileName(r.deliveryWorkbookFile) : '未找到(检查f3输出)'],
                ['输出目录', r.outputRoot || '—']
            ].forEach(([k, v]) => { kv.appendChild(WB().h('div', { class: 'k' }, k)); kv.appendChild(WB().h('div', { class: 'v' }, String(v))); });
            wrap.appendChild(kv);
            wrap.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin:10px 0' },
                '全部参数清单(含燃油偏置与物理横坐标)、逐工况值与平衡/求解诊断随交付Excel与运行记录提供;最小模型交付与完整结果浏览分开。'));
            wrap.appendChild(WB().h('div', { class: 'wb-actions-row', style: 'margin-top:12px' },
                WB().h('button', { class: 'wb-btn wb-btn-primary', onclick: () => saveModel(false) }, '保存模型(登记到模型成果)'),
                r.deliveryWorkbookFile ? WB().h('button', {
                    class: 'wb-btn wb-btn-outline',
                    onclick: () => window.open(window.AppConfig.api.baseURL + '/api/engine/projects/'
                        + encodeURIComponent(ctx.project.id) + '/tasks/' + encodeURIComponent(t.id)
                        + '/status', '_blank')
                }, '查看运行记录') : null));
            return wrap;
        }

        async function saveModel(gotoModels) {
            const t = state.task;
            try {
                const resp = await window.AppConfig.enginePost(
                    'projects/' + encodeURIComponent(ctx.project.id || '') + '/tasks/'
                    + encodeURIComponent(t.id) + '/save-model',
                    { name: (t.name || L.title) + '-模型' });
                if (resp && (resp.success || resp.code === 200)) {
                    toast('已登记到模型成果', 'success');
                    stopPolling();
                    ctx.back(!!gotoModels);
                } else toast((resp && resp.message) || '登记失败', 'error');
            } catch (e) { toast('登记失败:' + e.message, 'error'); }
        }

        /* ================= 动作 ================= */
        async function runPrepare() {
            state.prepWait = true; renderBody();
            try {
                const resp = await window.AppConfig.enginePost(
                    'projects/' + encodeURIComponent(ctx.project.id || '') + '/tasks/'
                    + encodeURIComponent(state.task.id) + '/prepare', {});
                if (resp && (resp.success || resp.code === 200) && resp.data) state.task = resp.data;
                else toast((resp && resp.message) || '检查发起失败', 'error');
            } catch (e) { toast('检查发起失败:' + e.message, 'error'); }
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
                toast('已请求安全暂停(到达安全点后保存,不强杀)', 'info');
            } catch (e) { toast('请求停止失败:' + e.message, 'error'); }
            startPolling();
        }

        function poll() {
            const t = state.task;
            if (!t || !ctx.project.id) return;
            if (!running(t) && (window.__WB_ENGINE_POLL_UNTIL__ || 0) < Date.now()) return;
            window.AppConfig.engineGet(
                'projects/' + encodeURIComponent(ctx.project.id) + '/tasks/'
                + encodeURIComponent(t.id) + '/status')
                .then(resp => {
                    if (resp && (resp.success || resp.code === 200) && resp.data && resp.data.task) {
                        state.task = resp.data.task;
                        if (Array.isArray(resp.data.logTail) && resp.data.logTail.length) state.log = resp.data.logTail;
                    }
                    if (running(state.task)) window.__WB_ENGINE_POLL_UNTIL__ = Date.now() + 40000;
                    else if ((window.__WB_ENGINE_POLL_UNTIL__ || 0) < Date.now()) stopPolling();
                    renderBody();
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
        // 进入业务页固定显示新建视图;只有运行记录/项目概览指定 __WB_OPEN_TASK__ 时才打开既有任务
        // 页面切换时由 shell 调用,避免旧页轮询残留(跨页串状态通道)
        window.__WB_PAGE_STOP__ = stopPolling;

        renderBody();
        return root;
    }

    /* ================= 自演化(G6): 五视图 ================= */
    function renderEvolutionTask(ctx) {
        const state = { task: null, timer: null, tab: 'overview', prepWait: false };
        const root = WB().h('div', null);

        const openTaskId = window.__WB_OPEN_TASK__;
        delete window.__WB_OPEN_TASK__;
        if (openTaskId && ctx.project && ctx.project.id) {
            window.AppConfig.engineGet('projects/' + encodeURIComponent(ctx.project.id) + '/tasks/'
                + encodeURIComponent(openTaskId) + '/status')
                .then(resp => {
                    if (resp && (resp.success || resp.code === 200) && resp.data && resp.data.task) {
                        state.task = resp.data.task;
                        state.log = resp.data.logTail || [];
                        if (state.task && state.task.status !== 'COMPLETED') state.tab = 'sorties';
                        // 模型成果评估记录跳转(04-16):直达UQ页签
                        const wantTab2 = window.__WB_OPEN_TASK_TAB__;
                        delete window.__WB_OPEN_TASK_TAB__;
                        if (wantTab2 === 'uq') state.tab = 'uq';
                        // 从运行记录打开仍在跑的任务时补启轮询(sortiesTab不自行启动)
                        if (state.task && ['RUNNING', 'PREPARING', 'STOP_REQUESTED'].includes(state.task.status)) startPolling();
                    } else toast((resp && resp.message) || '任务不存在', 'error');
                    renderBody();
                }).catch(() => renderBody());
        }

        const titleRow = WB().h('div', { style: 'display:flex;align-items:center;gap:14px;margin-bottom:4px' },
            WB().h('button', { class: 'wb-btn wb-btn-outline', onclick: () => { stopPolling(); ctx.back(); } }, '‹ 返回'),
            WB().h('div', { class: 'wb-page-title', style: 'margin:0' }, '发动机个性化模型自演化'));
        const metaRow = WB().h('div', { class: 'wb-page-sub' }, '同一台发动机 / 从试车模型开始,按实际架次逐步更新');
        root.appendChild(titleRow);
        root.appendChild(metaRow);

        const TABS = [['overview', '演化总览'], ['sorties', '架次与执行'], ['result', '架次模型结果'], ['uq', '不确定性评估'], ['predict', '下一架次预测']];
        const tabBar = WB().h('div', { class: 'wb-tabs' });
        root.appendChild(tabBar);
        const body = WB().h('div', null);
        root.appendChild(body);

        function toast(msg, kind) { if (WB() && WB().toast) WB().toast(msg, kind || 'info'); }
        function fileName(p) { return p ? String(p).split(/[\\/]/).pop() : ''; }
        const running = t => t && (t.status === 'RUNNING' || t.status === 'PREPARING');

        /* ---- 上传行(自演化架次测量Excel;taskPage里的同名函数作用域不同,不能直接引用) ---- */
        function uploadRow(label, kind, t) {
            const current = t ? (kind === 'identification' ? t.identificationFile : t.validationFile) : null;
            const nameBox = WB().h('input', { readonly: '', value: current ? fileName(current) : '未提供', style: 'flex:1;min-width:300px' });
            const pickBtn = WB().h('button', { class: 'wb-btn wb-btn-outline', onclick: () => fileInput.click() },
                kind === 'identification' ? '上传架次测量文件' : '上传独立测试文件');
            const fileInput = WB().h('input', { type: 'file', accept: '.xlsx,.xls', style: 'display:none' });
            fileInput.addEventListener('change', async () => {
                const f = fileInput.files && fileInput.files[0];
                if (!f) return;
                if (!state.task) { toast('请先登记本批任务,再上传文件', 'error'); return; }
                const fd = new FormData();
                fd.append('file', f);
                nameBox.value = '上传中:' + f.name + '...';
                try {
                    const resp = await window.AppConfig.engineUpload(
                        'projects/' + encodeURIComponent(ctx.project.id || '') + '/tasks/'
                        + encodeURIComponent(state.task.id) + '/files?kind=' + encodeURIComponent(kind), fd);
                    if (resp && (resp.success || resp.code === 200) && resp.data) {
                        state.task = resp.data;
                        toast('已上传:' + f.name, 'success');
                    } else { toast((resp && resp.message) || '上传失败', 'error'); nameBox.value = current ? fileName(current) : '未提供'; }
                } catch (e) { toast('上传失败:' + e.message, 'error'); nameBox.value = current ? fileName(current) : '未提供'; }
                renderBody();
            });
            const row = WB().h('div', { class: 'wb-field', style: 'max-width:1180px;margin-bottom:10px' },
                WB().h('label', null, label),
                WB().h('div', { style: 'display:flex;gap:10px;flex-wrap:wrap;align-items:center' },
                    nameBox,
                    pickBtn,
                    (function () {
                        const libSel = WB().h('select', { style: 'max-width:260px' },
                            WB().h('option', { value: '' }, '从文件库选择(架次测量数据)...'));
                        window.AppConfig.engineGet('projects/'
                            + encodeURIComponent(ctx.project.id || '') + '/files/page',
                            { pageSize: 200 })
                            .then(resp => {
                                const rows = resp && resp.data && Array.isArray(resp.data.rows) ? resp.data.rows.filter(x => x && x.id != null) : [];
                                const hit = rows.filter(r0 => /\.(xlsx|xls)$/i.test(String(r0.name || '')) && ['飞参训练', '测量', 'train'].some(w => String(r0.kind || '').indexOf(w) >= 0 || String(r0.name || '').indexOf(w) >= 0));
                                if (!hit.length) {
                                    libSel.appendChild(WB().h('option', { value: '' }, '暂无架次测量类库内文件(可直接上传)'));
                                    return;
                                }
                                hit.forEach(r0 => libSel.appendChild(WB().h('option', { value: r0.id },
                                    (r0.name || r0.id) + (r0.kind ? ' · ' + r0.kind : ''))));
                            })
                            .catch(() => { });
                        return libSel;
                    })(),
                    WB().h('button', {
                        class: 'wb-btn wb-btn-outline',
                        onclick: async () => {
                            const sel = row.querySelector('select');
                            if (!state.task) { toast('先登记本批任务(创建架次),再从文件库带入', 'error'); return; }
                            if (!sel || !sel.value) { toast('请先在下拉中选择库内文件', 'error'); return; }
                            try {
                                const resp = await window.AppConfig.enginePost(
                                    'projects/' + encodeURIComponent(ctx.project.id || '') + '/tasks/'
                                    + encodeURIComponent(state.task.id) + '/files/from-library?kind='
                                    + encodeURIComponent(kind) + '&fileId=' + encodeURIComponent(sel.value), {});
                                if (resp && (resp.success || resp.code === 200) && resp.data) {
                                    state.task = resp.data;
                                    toast('已从文件库带入', 'success');
                                    renderBody();
                                } else toast((resp && resp.message) || '带入失败', 'error');
                            } catch (e) { toast('带入失败:' + e.message, 'error'); }
                        }
                    }, '带入'),
                    WB().h('button', {
                        class: 'wb-btn wb-btn-outline',
                        style: current ? '' : 'opacity:.5',
                        onclick: async () => {
                            if (!current) { toast('请先上传或从文件库带入文件', 'error'); return; }
                            const name = fileName(current);
                            try {
                                const pv = await window.AppConfig.engineGet('projects/'
                                    + encodeURIComponent(ctx.project.id || '') + '/tasks/'
                                    + encodeURIComponent(state.task.id) + '/file-preview?kind=' + encodeURIComponent(kind));
                                if (pv && (pv.success || pv.code === 200) && pv.data) {
                                    window.Workbench.showFilePreview(pv.data.fileName || name, pv.data);
                                } else toast((pv && pv.message) || '预览失败', 'error');
                            } catch (e) { toast('预览失败:' + e.message, 'error'); }
                        }
                    }, '预览')));
            row.appendChild(fileInput);
            return row;
        }

        function paintTabs() {
            const t = state.task;
            const reach = { overview: true, sorties: true, result: !!(t && (t.status === 'COMPLETED' || t.status === 'FAILED' || t.status === 'RUNNING')), uq: !!(t && t.status === 'COMPLETED'), predict: !!(t && t.status === 'COMPLETED') };
            tabBar.innerHTML = '';
            TABS.forEach(([key, label]) => {
                const enabled = !!reach[key];
                tabBar.appendChild(WB().h('div', {
                    class: 'wb-tab' + (state.tab === key ? ' active' : '') + (enabled ? '' : ' disabled'),
                    onclick: () => {
                        if (!enabled) { toast('完成一次演化建模后开放', 'info'); return; }
                        state.tab = key; renderBody();
                    }
                }, label));
            });
        }

        function renderBody() {
            // 核验/执行/UQ评估进行中不允许renderBody杀掉轮询
            const busy = state.prepWait || (state.task && ['PREPARING', 'RUNNING', 'STOP_REQUESTED'].includes(state.task.status))
                || (state.task && (state.task.uqStatus === 'EXECUTING' || state.task.uqStatus === 'PREPARING'));
            if (!busy) stopPolling();
            body.innerHTML = '';
            if (state.tab === 'overview') body.appendChild(overviewTab());
            else if (state.tab === 'sorties') body.appendChild(sortiesTab());
            else if (!state.task) { body.appendChild(WB().h('div', { class: 'wb-placeholder' }, WB().h('p', null, '请先在「架次与执行」登记本批架次。'))); }
            else if (state.tab === 'result') body.appendChild(resultTab());
            else if (state.tab === 'uq') body.appendChild(uqTab());
            else body.appendChild(entranceTab('下一架次预测', '先冻结两份模型:「沿用当前正常模型」与「按正常历史趋势外推模型」;两份使用相同未来输入与物理初态计算输出,不自动选胜者,不替换当前模型;之后取得测量再建立独立评价记录。'));
            paintTabs();
        }

        /* ---- 演化总览(06-01) ---- */
        function overviewTab() {
            const t = state.task;
            const wrap = WB().h('div', null);
            wrap.appendChild(WB().h('div', { class: 'wb-section-title', style: 'margin-bottom:8px' }, '当前模型链'));
            const kv = WB().h('div', { class: 'wb-kv', style: 'max-width:1180px' });
            [
                ['试车起点', t ? ((t.parentSource || '2p4') + (t.parentWorkbook ? ' · ' + fileName(t.parentWorkbook) : ' · 按来源解析')) : '未选择(在架次与执行中登记)'],
                ['本批登记', t ? (t.f3SortieId || '—') + ';编号和数量由实际任务确定' : '未登记'],
                ['后续目标', '确认数据 → 顺序更新 → 查看趋势 → 预测下一架次'],
                ['批身份', t ? (t.runId || '—') : '—']
            ].forEach(([k, v]) => { kv.appendChild(WB().h('div', { class: 'k' }, k)); kv.appendChild(WB().h('div', { class: 'v' }, v)); });
            wrap.appendChild(kv);
            wrap.appendChild(WB().h('div', { class: 'wb-section-title', style: 'margin:16px 0 8px' }, '待处理任务'));
            const work = WB().h('table', { class: 'wb-table' },
                WB().h('tr', null, ['工作', '当前状态'].map(x => WB().h('th', null, x))),
                WB().h('tr', null, WB().h('td', null, '试车起点'), WB().h('td', null, t ? '已登记;可核模型及来源' : '待登记')),
                WB().h('tr', null, WB().h('td', null, '架次数据确认与执行'), WB().h('td', null, t ? ({ READY: '输入核验通过;可整批执行', PREPARING: '核验中', RUNNING: '执行中', COMPLETED: '已完成', FAILED: '失败' }[t.status] || t.status) : '待核验')),
                WB().h('tr', null, WB().h('td', null, '下一架次预测'), WB().h('td', null, t && t.status === 'COMPLETED' ? '可冻结两种预测模型' : '尚未形成 / 不需未来输出')));
            wrap.appendChild(work);
            wrap.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin:10px 0' },
                '已有模型不会按保存时间自动成为父模型;验证样例与真实业务分开,不内置固定故障场景。'));
            wrap.appendChild(WB().h('div', { class: 'wb-actions-row', style: 'margin-top:10px' },
                WB().h('button', { class: 'wb-btn wb-btn-outline', onclick: () => ctx.back() }, '← 返回项目概况'),
                WB().h('div', { class: 'wb-spacer' }),
                WB().h('button', { class: 'wb-btn wb-btn-primary', onclick: () => { state.tab = 'sorties'; renderBody(); } }, '→ 核对试车起点与架次')));
            return wrap;
        }

        /* ---- 架次与执行(06-03/04/06/07) ---- */
        function sortiesTab() {
            const t = state.task;
            const wrap = WB().h('div', null);
            if (!t) {
                /* 登记本批(草稿) */
                const nameInput = WB().h('input', { value: 'EV-' + new Date().toISOString().slice(2, 10).replace(/-/g, '') });
                const sortieInput = WB().h('input', { value: 'F-014', placeholder: '架次编号(可中文)' });
                const parentSourceSel = WB().h('select', null,
                    WB().h('option', { value: '2p4' }, '2.4 试车模型'),
                    WB().h('option', { value: '2p7' }, '2.7 数据更新模型'),
                    WB().h('option', { value: 'flight' }, '既有飞参模型'),
                    WB().h('option', { value: 'combined' }, 'TC27组合模型'));
                const modelSel = WB().h('select', null, WB().h('option', { value: '' }, '由程序按来源路线解析(可不指定)'));
                window.AppConfig.engineGet('projects/' + encodeURIComponent(ctx.project.id || '') + '/models')
                    .then(resp => {
                        const models = resp && Array.isArray(resp.data) ? resp.data.filter(m => m.deliveryWorkbookFile) : [];
                        models.forEach(m => modelSel.appendChild(WB().h('option', { value: m.id },
                            (m.name || m.id) + ' · ' + (m.stage || '') + ' · ' + (m.route || ''))));
                    }).catch(() => { });
                const createBtn = WB().h('button', {
                    class: 'wb-btn wb-btn-primary',
                    onclick: async () => {
                        createBtn.classList.add('disabled');
                        try {
                            const resp = await window.AppConfig.enginePost('projects/' + encodeURIComponent(ctx.project.id || '') + '/tasks', {
                                kind: 'evolution', name: nameInput.value.trim() || '模型自演化任务',
                                parentSource: parentSourceSel.value, parentModelId: modelSel.value || '',
                                f3SortieId: sortieInput.value.trim() || 'SORTIE-01',
                                f3EngineId: ctx.project.engineId || '', dataMethod: 'steady_only',
                                runId: 'EV01'
                            });
                            if (resp && (resp.success || resp.code === 200) && resp.data) { state.task = resp.data; renderBody(); }
                            else toast((resp && resp.message) || '登记失败', 'error');
                        } catch (e) { toast('登记失败:' + e.message, 'error'); }
                        createBtn.classList.remove('disabled');
                    }
                }, '登记本批任务');
                wrap.appendChild(WB().h('div', { class: 'wb-card', style: 'max-width:760px' },
                    WB().h('div', { class: 'wb-section-title', style: 'margin-bottom:6px' }, '登记本批架次'),
                    WB().h('div', { class: 'wb-hint', style: 'margin:0 0 14px' }, '用户登记架次编号、顺序、测量Excel及输出位置;父模型从显式关系取得,不取最后保存的模型或最近修改文件。'),
                    WB().h('div', { class: 'wb-form-grid' },
                        WB().h('div', { class: 'wb-field' }, WB().h('label', null, '本批任务'), nameInput),
                        WB().h('div', { class: 'wb-field' }, WB().h('label', null, '架次编号'), sortieInput),
                        WB().h('div', { class: 'wb-field' }, WB().h('label', null, '初始父模型来源'), parentSourceSel),
                        WB().h('div', { class: 'wb-field' }, WB().h('label', null, '指定父模型(可选)'), modelSel)),
                    WB().h('div', { class: 'wb-actions-row', style: 'margin-top:12px' }, createBtn)));
                return wrap;
            }

            wrap.appendChild(WB().h('div', { class: 'wb-form-grid', style: 'grid-template-columns:1fr 1fr;max-width:1180px;margin-bottom:12px' },
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '本批任务'),
                    WB().h('input', { readonly: '', value: t.name || t.runId || '—' })),
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '初始父模型'),
                    WB().h('input', { readonly: '', value: (t.parentSource || '2p4') + (t.parentWorkbook ? ' · ' + fileName(t.parentWorkbook) : '') }))));

            wrap.appendChild(WB().h('div', { class: 'wb-section-title', style: 'margin-bottom:8px' }, '架次清单'));
            // 测量Excel上传(合同必填:sorties.measurementFile;无上传入口任务会死锁在run阶段报空文件)
            wrap.appendChild(uploadRow('架次试车测量Excel(Data表,必选)', 'identification', t));
            const tbl = WB().h('table', { class: 'wb-table' },
                WB().h('tr', null, ['架次 / 次序', '飞参Excel', '父模型', '独立测试', '业务角色'].map(x => WB().h('th', null, x))),
                WB().h('tr', null,
                    WB().h('td', null, (t.f3SortieId || '—') + ' / 1'),
                    WB().h('td', null, t.identificationFile ? fileName(t.identificationFile) : '未上传'),
                    WB().h('td', null, t.parentModelId ? String(t.parentModelId) : (t.parentSource || '2p4') + '(根)'),
                    WB().h('td', null, t.validationFile ? fileName(t.validationFile) : '未提供'),
                    WB().h('td', null, '正常')));
            wrap.appendChild(tbl);
            wrap.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin:6px 0 12px' },
                '必要测量:时间、环境、燃油、PT负载、两轴转速及测量输出;父需为根或登记中更早架次;正常业务不得继承验证场景模型。'));

            const prepRunning = state.prepWait || t.status === 'PREPARING';
            const isRun = t.status === 'RUNNING';
            wrap.appendChild(WB().h('div', { class: 'wb-section' },
                WB().h('div', { class: 'wb-section-head' },
                    WB().h('div', { class: 'wb-section-title' }, '执行状态'),
                    prepRunning ? WB().h('span', { class: 'wb-tag wb-tag-amber' }, '输入核验中(check)...')
                        : isRun ? WB().h('span', { class: 'wb-tag wb-tag-amber' }, '整批执行中(run)...')
                        : t.status === 'READY' ? WB().h('span', { class: 'wb-tag wb-tag-teal' }, '核验通过;可整批执行')
                        : t.status === 'COMPLETED' ? WB().h('span', { class: 'wb-tag wb-tag-teal' }, '已完成')
                        : t.status === 'FAILED' ? WB().h('span', { class: 'wb-tag wb-tag-red' }, '失败')
                        : WB().h('span', { class: 'wb-tag wb-tag-gray' }, '待核验')),
                WB().h('div', { style: 'padding:10px 0' },
                    (prepRunning || isRun)
                        ? WB().h('span', { class: 'wb-inline-loading' }, WB().h('span', { class: 'wb-inline-spinner' }),
                            prepRunning ? '正在检查测量Excel、父模型依赖与输出目录...' : '逐架次:预览→确认数据意图→绑定实际父→执行;身份变化只阻断相关续算...')
                        : WB().h('div', null, t.message || '—')),
                (t.status === 'RUNNING' || t.status === 'STOP_REQUESTED') ? WB().h('pre', {
                    style: 'max-height:200px;overflow:auto;background:#101418;color:#cde3d8;padding:12px;border-radius:8px;font-size:12px;white-space:pre-wrap'
                }, (state.log && state.log.length ? state.log.join('\n') : '等待MATLAB输出...')) : null));

            wrap.appendChild(WB().h('div', { class: 'wb-actions-row', style: 'margin-top:10px' },
                WB().h('button', {
                    class: 'wb-btn wb-btn-outline' + (t.identificationFile && !prepRunning && !isRun && !['COMPLETED'].includes(t.status) ? '' : ' disabled'),
                    onclick: () => { if (t.identificationFile && !prepRunning && !isRun) { window.__WB_ENGINE_POLL_UNTIL__ = Date.now() + 40000; runPrepare(); } }
                }, prepRunning ? '核验中...' : '预览所选架次数据(输入核验)'),
                WB().h('div', { class: 'wb-spacer' }),
                WB().h('button', {
                    // 登记后即为READY,执行前必须已有架次测量Excel,否则后端会拒绝
                    class: 'wb-btn wb-btn-primary' + (t.status === 'READY' && t.identificationFile && !isRun ? '' : ' disabled'),
                    onclick: () => {
                        if (t.status !== 'READY' || isRun) return;
                        if (!t.identificationFile) { toast('请先上传/带入架次试车测量Excel(Data表)', 'error'); return; }
                        window.__WB_ENGINE_POLL_UNTIL__ = Date.now() + 40000; runModel();
                    }
                }, isRun ? '执行中...' : '顺序更新(整批执行)')));
            return wrap;
        }

        /* ---- 架次模型结果(06-09/10/13) ---- */
        function resultTab() {
            const t = state.task;
            const r = t.result || {};
            const wrap = WB().h('div', null);
            wrap.appendChild(WB().h('div', { class: 'wb-infobar', style: 'margin-bottom:12px' },
                t.status === 'COMPLETED' ? '本架次模型已交付;训练必展,测试可空;未收敛但合法的模型可继续使用,停止原因随模型传递。'
                    : t.status === 'FAILED' ? ('执行失败:' + (t.message || '')) : '执行中...'));
            if (t.status !== 'COMPLETED') { if (t.status === 'RUNNING') startPolling(); return wrap; }
            const kv = WB().h('div', { class: 'wb-kv', style: 'max-width:1180px' });
            [
                ['运行标识', r.runId || t.runId || '—'],
                ['实际父', (t.parentSource || '2p4') + (t.parentWorkbook ? ' · ' + fileName(t.parentWorkbook) : '')],
                ['本架次模型', r.deliveryWorkbookFile ? fileName(r.deliveryWorkbookFile) : '—'],
                ['输出目录', r.outputRoot || '—']
            ].forEach(([k, v]) => { kv.appendChild(WB().h('div', { class: 'k' }, k)); kv.appendChild(WB().h('div', { class: 'v' }, String(v))); });
            wrap.appendChild(kv);
            wrap.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin:10px 0' },
                '全量参数、实际父和本次先验分开;瞬态参数保持实际父值;完整节点和真实覆盖随交付Excel可追溯。'));
            wrap.appendChild(WB().h('div', { class: 'wb-actions-row', style: 'margin-top:12px' },
                WB().h('button', {
                    class: 'wb-btn wb-btn-primary',
                    onclick: async () => {
                        try {
                            const resp = await window.AppConfig.enginePost(
                                'projects/' + encodeURIComponent(ctx.project.id || '') + '/tasks/'
                                + encodeURIComponent(t.id) + '/save-model', { name: (t.name || '自演化') + '-模型' });
                            if (resp && (resp.success || resp.code === 200)) { toast('已登记到模型成果', 'success'); ctx.back(true); }
                            else toast((resp && resp.message) || '登记失败', 'error');
                        } catch (e) { toast('登记失败:' + e.message, 'error'); }
                    }
                }, '保存模型(登记到模型成果)')));
            return wrap;
        }

        function entranceTab(title, desc) {
            return WB().h('div', null,
                WB().h('div', { class: 'wb-infobar', style: 'margin-bottom:12px' }, title + ' — 独立任务,不在本页自动执行'),
                WB().h('div', { class: 'wb-hint', style: 'margin:8px 0;max-width:900px;line-height:1.8' }, desc),
                WB().h('div', { class: 'wb-actions-row', style: 'margin-top:12px' },
                    WB().h('button', { class: 'wb-btn wb-btn-primary', onclick: () => ctx.back(true) }, '前往模型成果')));
        }

        /* ---- 不确定性评估:与本任务已登记模型成果发起,与稳态飞参建模同一UQ接口 ---- */
        function uqTab() {
            const t = state.task;
            const wrap = WB().h('div', null);

            // 04-16连接(双向):任何状态都可查看此任务的已有评估记录
            const uqPrevBox = WB().h('div', null);
            wrap.appendChild(WB().h('div', { class: 'wb-actions-row', style: 'margin-bottom:10px' },
                WB().h('button', {
                    class: 'wb-btn wb-btn-outline',
                    onclick: () => { uqPrevBox.innerHTML = ''; uqPrevBox.appendChild(uqRecordDrawer()); }
                }, '查看此模型的已有评估')));
            wrap.appendChild(uqPrevBox);

            function uqRecordDrawer() {
                const box = WB().h('div', { class: 'wb-card', style: 'padding:14px;max-width:1180px;margin-bottom:12px' },
                    WB().h('div', { class: 'wb-section-title', style: 'margin-bottom:8px' }, '此任务的评估记录'));
                const holder = WB().h('div', null, WB().h('div', { class: 'wb-hint' }, '正在加载...'));
                box.appendChild(holder);
                window.AppConfig.engineGet('projects/' + encodeURIComponent(ctx.project.id || '') + '/uq-records')
                    .then(resp => {
                        const list = resp && (resp.success || resp.code === 200) && Array.isArray(resp.data) ? resp.data : [];
                        const mine = list.filter(r => r.taskId === t.id);
                        holder.innerHTML = '';
                        if (!mine.length) { holder.appendChild(WB().h('div', { class: 'wb-hint' }, '暂无评估记录。')); return; }
                        holder.appendChild(WB().h('table', { class: 'wb-table' },
                            WB().h('tr', null, ['运行标识', '方法', '状态', '开始时间', '说明'].map(x => WB().h('th', null, x))),
                            mine.map(r => WB().h('tr', null,
                                WB().h('td', null, r.runId || r.id),
                                WB().h('td', null, r.method || '—'),
                                WB().h('td', null, r.status === 'COMPLETED' ? '已完成' : r.status === 'FAILED' ? '失败' : (r.status || '—')),
                                WB().h('td', { class: 'wb-hint' }, r.startedAt ? new Date(r.startedAt).toLocaleString() : '—'),
                                WB().h('td', { class: 'wb-hint' }, r.message || '—')))));
                    })
                    .catch(e => { holder.innerHTML = ''; holder.appendChild(WB().h('div', { class: 'wb-hint' }, '加载失败:' + e.message)); });
                return box;
            }

            if (t.status !== 'COMPLETED') {
                wrap.appendChild(WB().h('div', { class: 'wb-infobar', style: 'margin-bottom:12px' },
                    '完成一次演化建模并登记模型成果后开放评估。'));
                return wrap;
            }
            const uqRunning = t.uqStatus === 'EXECUTING' || t.uqStatus === 'PREPARING';

            /* 执行中:阶段说明 + 就地日志 + 协作取消(与稳态飞参建模同款) */
            if (uqRunning) {
                wrap.appendChild(WB().h('div', { class: 'wb-infobar', style: 'margin-bottom:12px' },
                    'UQ评估' + (t.uqStatus === 'PREPARING' ? '准备中(确认观测并绑定目标模型)' : '执行中')
                    + ';按 评估准备 → 主样本计算 → 独立复算 → 参数汇总 → 结果写出 顺序执行。'));
                wrap.appendChild(WB().h('div', { class: 'wb-section-title', style: 'margin:10px 0 8px' }, '评估日志'));
                wrap.appendChild(WB().h('pre', {
                    style: 'max-height:260px;overflow:auto;background:#101418;color:#cde3d8;padding:12px;border-radius:8px;font-size:12px;line-height:1.5;white-space:pre-wrap'
                }, (state.log && state.log.length ? state.log.join('\n') : '等待MATLAB输出...')));
                wrap.appendChild(WB().h('div', { class: 'wb-actions-row', style: 'margin-top:12px' },
                    WB().h('button', { class: 'wb-btn wb-btn-outline', onclick: async () => {
                        try {
                            await window.AppConfig.enginePost('projects/' + encodeURIComponent(ctx.project.id || '')
                                + '/tasks/' + encodeURIComponent(t.id) + '/uq/stop', {});
                            toast('已请求取消UQ评估(协作取消,结果作废)', 'info');
                        } catch (e) { toast('取消失败:' + e.message, 'error'); }
                        startPolling();
                    } }, '请求协作取消'),
                    WB().h('div', { class: 'wb-spacer' }),
                    WB().h('button', { class: 'wb-btn wb-btn-primary', onclick: () => { state.tab = 'result'; renderBody(); } }, '返回模型结果')));
                startPolling();
                return wrap;
            }

            /* 失败:错误定位 + 日志(与飞行建模运行失败视图同款),配置表随下方保留便于直接重发 */
            if (t.uqStatus === 'FAILED') {
                wrap.appendChild(WB().h('div', { class: 'wb-tag wb-tag-red', style: 'display:inline-block;padding:6px 12px;margin-bottom:10px' },
                    'UQ评估失败:' + (t.uqMessage || '详见日志')));
                wrap.appendChild(WB().h('div', { class: 'wb-section-title', style: 'margin:6px 0 8px' }, '评估日志'));
                wrap.appendChild(WB().h('pre', {
                    style: 'max-height:260px;overflow:auto;background:#101418;color:#cde3d8;padding:12px;border-radius:8px;font-size:12px;line-height:1.5;white-space:pre-wrap'
                }, (state.log && state.log.length ? state.log.join('\n') : '(无日志)')));
            } else if (t.uqStatus === 'COMPLETED') {
                wrap.appendChild(WB().h('div', { class: 'wb-infobar', style: 'margin-bottom:12px' },
                    '上次评估已完成' + (t.uqResult && t.uqResult.workbook ? ';区间Excel: ' + fileName(String(t.uqResult.workbook)) : '')
                    + ';结果另存,不覆盖确定性估计值。可发起新评估(生成新评估批次)。'));
            } else {
                wrap.appendChild(WB().h('div', { class: 'wb-infobar', style: 'margin-bottom:12px' },
                    'UQ调用F3原算法(uqpreview→确认观测→绑定目标模型→uqrun):评估对象为本架次已交付模型,'
                    + '概率先验须为对演化起点2p4模型执行「方法C」评估产出的后验交付(同节点网格且含条件物理参数表);'
                    + '方法限C/D;评估结果另存,不覆盖确定性估计值。'));
            }
            const methodSel = WB().h('select', null,
                WB().h('option', { value: 'D' }, '方法D(默认,快速局部初评)'),
                WB().h('option', { value: 'C' }, '方法C(非线性粒子评估)'));
            wrap.appendChild(WB().h('div', { class: 'wb-form-grid', style: 'grid-template-columns:1fr;max-width:480px' },
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '评估方法'), methodSel)));
            const launchBtn = WB().h('button', {
                class: 'wb-btn wb-btn-primary' + (uqRunning ? ' disabled' : ''),
                onclick: async () => {
                    if (uqRunning) return;
                    launchBtn.classList.add('disabled');
                    try {
                        let mine = [];
                        const respM = await window.AppConfig.engineGet(
                            'projects/' + encodeURIComponent(ctx.project.id || '') + '/models');
                        const models = respM && (respM.success || respM.code === 200) && Array.isArray(respM.data) ? respM.data : [];
                        mine = models.filter(m => m.taskId === t.id);
                        if (!mine.length || !mine[mine.length - 1].deliveryWorkbookFile) {
                            const reg = await window.AppConfig.enginePost(
                                'projects/' + encodeURIComponent(ctx.project.id || '') + '/tasks/'
                                + encodeURIComponent(t.id) + '/save-model', { name: (t.name || '自演化') + '-模型' });
                            if (!(reg && (reg.success || reg.code === 200))) {
                                toast((reg && reg.message) || '登记模型成果失败,无法发起评估', 'error'); return;
                            }
                        }
                        const resp = await window.AppConfig.enginePost(
                            'projects/' + encodeURIComponent(ctx.project.id || '') + '/tasks/'
                            + encodeURIComponent(t.id) + '/uq?method=' + encodeURIComponent(methodSel.value), {});
                        if (resp && (resp.success || resp.code === 200)) {
                            toast('UQ评估已发起;进度见本页与评估记录', 'success');
                            window.__WB_ENGINE_POLL_UNTIL__ = Date.now() + 40000;
                            startPolling(); renderBody();
                        } else toast((resp && resp.message) || '发起UQ失败', 'error');
                    } catch (e) { toast('发起UQ失败:' + e.message, 'error'); }
                }
            }, uqRunning ? '评估执行中...' : '▶ 检查配置并开始评估');
            wrap.appendChild(WB().h('div', { class: 'wb-actions-row', style: 'margin-top:12px' }, launchBtn));
            wrap.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin-top:8px;max-width:900px' },
                '首次评估约30分钟(参考20~50分钟);完成后区间来源逐节点可追溯,有限样本评估的统计限制随结果保存,不标为全局完备后验。'));
            return wrap;
        }

        async function runPrepare() {
            state.prepWait = true; renderBody();
            try {
                const resp = await window.AppConfig.enginePost(
                    'projects/' + encodeURIComponent(ctx.project.id || '') + '/tasks/'
                    + encodeURIComponent(state.task.id) + '/prepare', {});
                if (resp && (resp.success || resp.code === 200) && resp.data) state.task = resp.data;
                else toast((resp && resp.message) || '核验发起失败', 'error');
            } catch (e) { toast('核验发起失败:' + e.message, 'error'); }
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
        function poll() {
            const t = state.task;
            if (!t) return;
            if (!running(t) && (window.__WB_ENGINE_POLL_UNTIL__ || 0) < Date.now()) return;
            window.AppConfig.engineGet('projects/' + encodeURIComponent(ctx.project.id) + '/tasks/'
                + encodeURIComponent(t.id) + '/status')
                .then(resp => {
                    if (resp && (resp.success || resp.code === 200) && resp.data && resp.data.task) {
                        state.task = resp.data.task;
                        if (Array.isArray(resp.data.logTail) && resp.data.logTail.length) state.log = resp.data.logTail;
                    }
                    if (running(state.task)) window.__WB_ENGINE_POLL_UNTIL__ = Date.now() + 40000;
                    else if ((window.__WB_ENGINE_POLL_UNTIL__ || 0) < Date.now()) stopPolling();
                    renderBody();
                }).catch(() => { });
        }
        function startPolling() {
            window.__WB_ENGINE_POLL_UNTIL__ = Date.now() + 40000;
            if (state.timer) return;
            poll();
            state.timer = setInterval(poll, 4000);
        }
        function stopPolling() { if (state.timer) { clearInterval(state.timer); state.timer = null; } }
        // 进入业务页固定显示新建视图;只有运行记录/项目概览指定 __WB_OPEN_TASK__ 时才打开既有任务
        // 页面切换时由 shell 调用,避免旧页轮询残留(跨页串状态通道)
        window.__WB_PAGE_STOP__ = stopPolling;

        renderBody();
        return root;
    }

    window.Workbench.renderFlightTask = taskPage;
    window.Workbench.renderEvolutionTask = renderEvolutionTask;
})();
