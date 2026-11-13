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

    /* 日志刷新自动贴底：状态流(SSE chg)每次都会 renderBody 重建整个 body，
       日志容器 scrollTop 归零会表现为"刷新后跳回顶部"。重绘前记录是否贴底，
       重绘后贴底的拉到最底；用户主动上翻时保持原位置。稳态飞参、过渡态飞参、
       自演化三个任务页共用这套逻辑。 */
    const LOG_SELECTOR = '.wb-logbox, .wb-log, pre';
    function captureLogScroll(container) {
        return Array.prototype.map.call(container.querySelectorAll(LOG_SELECTOR), el => ({
            stick: el.clientHeight === 0 || el.scrollTop + el.clientHeight >= el.scrollHeight - 30,
            top: el.scrollTop
        }));
    }
    function restoreLogScroll(container, states) {
        const els = container.querySelectorAll(LOG_SELECTOR);
        const sameLayout = states.length === els.length;
        Array.prototype.forEach.call(els, (el, i) => {
            const st = sameLayout ? states[i] : { stick: true, top: 0 };
            el.scrollTop = st.stick ? el.scrollHeight : Math.min(st.top, el.scrollHeight);
        });
    }

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
            const prevScroll = captureLogScroll(body);
            body.innerHTML = '';
            if (state.tab === 'data') body.appendChild(dataTab());
            else if (!state.task) {
                body.appendChild(emptyHint('请先在「' + TABS[0][1] + '」完成任务创建与数据检查。'));
                paintTabs(); paintMeta(); restoreLogScroll(body, prevScroll); return;
            }
            else if (state.tab === 'update') body.appendChild(updateTab());
            else if (state.tab === 'event') body.appendChild(eventTab());
            else if (state.tab === 'run') body.appendChild(runTab());
            else if (state.tab === 'uq') body.appendChild(uqTab());
            else body.appendChild(resultTab());
            paintTabs();
            paintMeta();
            restoreLogScroll(body, prevScroll);
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
                        // 草稿期即可从文件库选择:显示库内全部数据文件(不再按槽位类型筛选,2026-10-30),
                        // 记录fileId,保存草稿(创建架次)后自动带入
                        const libPicked = state.draftLibrary && state.draftLibrary[kind];
                        const libSel = WB().h('select', { style: 'max-width:260px;padding:2px 6px;font-size:12px' });
                        let rows0 = [];
                        const refillLib = () => {
                            const keep = libPicked || libSel.value;
                            libSel.innerHTML = '';
                            libSel.appendChild(WB().h('option', { value: '' }, '从文件库选择...'));
                            // 已选项保留在列表中并回显文件名(不显示内部ID);被删文件用ID占位不丢选择。
                            // 用DOM属性.selected而非HTML属性——h()对null会setAttribute('selected','null'),
                            // 属性存在即生效,导致所有选项带selected、下拉永远钉在最后一个选项上
                            const hit = rows0.filter(r0 => /\.(xlsx|xls)$/i.test(String(r0.name || '')) || String(r0.id) === String(keep));
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

            // 04-03:测量字段与单位映射合同表(静态合同,列名/含义/单位/本任务用途)
            const mapTbl = WB().h('table', { class: 'wb-table', style: 'max-width:1180px;margin-top:10px' },
                WB().h('tr', null, ['测量别名', '物理量', '单位', '本任务用途'].map(x => WB().h('th', null, x))));
            [
                ['sample_id', '样本编号', '—', '行标识'],
                ['time_s', '相对时间', 's', '时间轴与窗口选择'],
                ['Ps0', '入口静压', 'Pa', '入口边界'],
                ['Ts_amb', '环境静温', 'K', '环境边界'],
                ['Altitude / Mach', '高度 / 马赫数', 'm / —', '模式3高度边界(可选)'],
                ['Tt1', '入口总温', 'K', '入口边界'],
                ['Ng / Np', '两轴换算转速', '%', '输入(不列预测误差)'],
                ['Mkp', 'PT负载扭矩', 'N·m', '负载边界'],
                ['Wf', '测量燃油流量', 'kg/s', '燃油偏置仅扣一次'],
                ['Pt3_eq / Tt45', '等效输出量', 'Pa / K', '仅输出比对,不作输入']
            ].forEach(([a, b, c, d]) => mapTbl.appendChild(WB().h('tr', null,
                WB().h('td', null, a), WB().h('td', null, b), WB().h('td', null, c), WB().h('td', { class: 'wb-hint' }, d))));
            wrap.appendChild(mapTbl);
            wrap.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin-top:4px;max-width:1180px' },
                '映射状态以「检查数据与模型」返回为准;缺列/单位未声明将在失败定位表中逐项给出,不静默替换来源(04-20)。'));

            // 04-04/04-21:完整时间轴 + 稳态窗口识别与选择状态(程序自动选定,高亮不等于用户选择)
            wrap.appendChild(WB().timelinePreviewBlock({
                projectId: ctx.project.id, taskId: t.id, file: 'identification',
                segClass: 'steady_window',
                title: '完整时间轴与有效稳态窗口(04-04/04-21)',
                note: '窗口确认以「检查数据与模型」生成的冻结凭据为准;本页为识别结果预览,保存选段草稿在程序确认中完成,不在这里截取5秒窗口。'
            }));

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
                        // 显示库内全部数据文件(不再按槽位类型筛选,2026-10-30);无数据显示空提示
                        const libSel = WB().h('select', { style: 'max-width:260px' },
                            WB().h('option', { value: '' }, '从文件库选择...'));
                        window.AppConfig.engineGet('projects/'
                            + encodeURIComponent(ctx.project.id || '') + '/files/page',
                            { pageSize: 200 })
                            .then(resp => {
                                const rows = resp && resp.data && Array.isArray(resp.data.rows) ? resp.data.rows.filter(x => x && x.id != null) : [];
                                const hit = rows.filter(r0 => /\.(xlsx|xls)$/i.test(String(r0.name || '')));
                                if (!hit.length) {
                                    libSel.appendChild(WB().h('option', { value: '' }, '库内暂无数据文件(可直接上传)'));
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
                // 04-07:预计耗时区块(范围说明与估时依据如实标注,不含UQ与自主预测)
                wrap.appendChild(WB().h('div', { style: 'display:flex;align-items:baseline;gap:16px;margin:14px 0 4px;max-width:1180px' },
                    WB().h('div', { style: 'font-size:26px;font-weight:700;color:#0f766e' }, '约 2 分钟'),
                    WB().h('div', { class: 'wb-hint' }, '参考范围 1~3 分钟')));
                wrap.appendChild(WB().h('div', { class: 'wb-hint', style: 'max-width:1180px;margin-bottom:6px' },
                    '范围说明:准备、稳态求解、最终核查及结果写出;不含不确定性评估和自主预测。'
                    + '估时依据:同环境实测基准 × 当前窗口与参数工作量,首次任务也提供粗估;实际以运行记录为准。'));
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
            // 04-08:确认的计算范围(窗口与用途如实展示;准备记录不计入拟合)
            wrap.appendChild(WB().h('div', { class: 'wb-infobar', style: 'margin-bottom:10px' },
                '确认的计算范围: ' + (t.identificationFile ? fileName(t.identificationFile) : '训练数据未登记')
                + (t.validationFile ? ' + 独立测试 ' + fileName(t.validationFile) : '(无独立测试)')
                + ';窗口与参数以「检查数据与模型」凭据为准,准备记录不计入拟合残差;本次配置快照已固定。'
                + '详细进度以日志和后端返回为准,未返回的差异列不推测;只有后端返回 stopped 才显示「已安全暂停」。'));

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
            // 05-03/05-04:候选事件时间轴高亮 + 事件选择表(识别结果只读预览,确认以「检查数据与模型」凭据为准)
            wrap.appendChild(WB().timelinePreviewBlock({
                projectId: ctx.project.id, taskId: t.id, file: 'identification',
                eventsMode: true,
                title: '完整架次时间轴与候选事件(05-03:高亮=事件核心,不等于已确认选择)',
                note: '单事件详情(实际执行范围/准备前史/拟合记录数)随「检查数据与模型」凭据返回;每个候选独立局部准备,不从整架次起点连续积分(05-04)。'
            }));
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
                // 05-05:13项瞬态参数合同表(编号/参数/作用/初值;固定集,前端如实展示)
                const tp = WB().h('table', { class: 'wb-table', style: 'max-width:1180px' },
                    WB().h('tr', null, ['编号', '参数', '物理作用', '初值'].map(x => WB().h('th', null, x))));
                [
                    ['h58', 'K_Jg', 'GT轴有效惯量修正', '0'],
                    ['h59', 'K_Jp', 'PT轴有效惯量修正', '0'],
                    ['h60', 'K_tau_HPC', 'HPC金属热响应时间尺度修正', '0'],
                    ['h61', 'K_tau_Burner', '燃烧室金属热响应时间尺度修正', '0'],
                    ['h62', 'K_tau_GT', 'GT金属热响应时间尺度修正', '0'],
                    ['h63', 'K_tau_PT', 'PT金属热响应时间尺度修正', '0'],
                    ['h64', 'K_gapW_HPC', 'HPC间隙对流量的性能交换率修正', '0'],
                    ['h65', 'K_gapEta_HPC', 'HPC间隙对效率的性能交换率修正', '0'],
                    ['h66', 'K_gapEta_GT', 'GT间隙对效率的性能交换率修正', '0'],
                    ['h67', 'K_gapEta_PT', 'PT间隙对效率的性能交换率修正', '0'],
                    ['h68', 'K_diskTau_HPC', 'HPC盘热响应时间尺度修正', '0'],
                    ['h69', 'K_diskTau_GT', 'GT盘热响应时间尺度修正', '0'],
                    ['h70', 'K_diskTau_PT', 'PT盘热响应时间尺度修正', '0']
                ].forEach(([a, b, c, d]) => tp.appendChild(WB().h('tr', null,
                    WB().h('td', null, a), WB().h('td', null, b), WB().h('td', null, c), WB().h('td', null, d))));
                wrap.appendChild(tp);
                wrap.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin:6px 0;max-width:1180px' },
                    '全部13项均参与辨识并完整展示(05-09),参数接近0不等于已证明无物理作用;正则使用λ不是λ²;'
                    + '求解设置(λ/迭代/积分步长)随交付程序合同,不在界面伪装可调。'));
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

            // 过渡态飞参:交付程序 sht_f3_transient_task 没有UQ动作(capabilities仅
            // check/preview/confirm/estimate/run/resume/validate),状态表明确标注
            // uqStatus=not_evaluated_for_transient_combination。保留评估记录查看,
            // 但不提供发起入口,避免复用稳态C/D合同后被后端拦成「缺少训练数据」。
            if (!isSteady) {
                wrap.appendChild(WB().h('div', { class: 'wb-infobar', style: 'margin-bottom:12px' },
                    '当前交付程序未开通「过渡态飞参 + 不确定性评估」组合:过渡态任务只实现数据/事件/身份/安全控制与物理执行,'
                    + '稳态飞参的 C/D 评估合同不适用于过渡态组合。如需区间评估,请新建稳态飞参建模任务后在稳态页发起。'));
                return wrap;
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

            /* 执行中(04-14):阶段卡片 + 已用时间/预估/当前进度 + 就地评估日志。
             * 原实现是 window.open 打开SSE端点——浏览器标签页对 text/event-stream 渲染为空白,按钮形同虚设。 */
            if (t.uqStatus === 'EXECUTING' || t.uqStatus === 'PREPARING') {
                wrap.appendChild(WB().h('div', { class: 'wb-infobar', style: 'margin-bottom:12px' },
                    '当前评估已关联 ' + (t.name || t.runId || '本架次模型') + ';确定性模型仍可查看和用于独立预测。'));
                // 阶段卡片(04-14五段):从日志关键字推断当前段,推断不出时整体待执行
                const logText = (state.log || []).join('\n');
                const stageDefs = [
                    ['合同与先验', /合同|先验|prior/i],
                    ['主样本计算', /主样本|主计算|particle|uqrun|方法\s*[CD]/i],
                    ['独立复算', /复算|独立|repeat|independent/i],
                    ['参数汇总', /汇总|summary/i],
                    ['结果写出', /写出|manifest|交付|workbook/i]
                ];
                let cur = -1;
                stageDefs.forEach((sd, i) => { if (sd[1].test(logText)) cur = i; });
                const cards = WB().h('div', { class: 'wb-form-grid', style: 'grid-template-columns:repeat(5,1fr);max-width:1180px;margin-bottom:12px' });
                stageDefs.forEach((sd, i) => {
                    const stTxt = cur < 0 ? '待执行' : i < cur ? '已完成' : i === cur ? (t.uqStatus === 'PREPARING' ? '准备中' : '正在执行') : '待执行';
                    const hi = i === cur && cur >= 0;
                    cards.appendChild(WB().h('div', {
                        style: 'padding:10px 12px;border:1px solid ' + (hi ? '#0f766e' : '#e5e7eb')
                            + ';border-radius:8px;background:' + (hi ? '#f0fdfa' : '#f8fafc')
                    }, WB().h('div', { style: 'font-weight:600;color:' + (hi ? '#0f766e' : '#374151') }, sd[0]),
                        WB().h('div', { class: 'wb-hint', style: 'margin-top:4px' }, stTxt)));
                });
                wrap.appendChild(cards);
                // 已用时间 / 运行前预估 / 当前进度(04-14三栏)
                const elapsed = t.uqStartedAt ? formatDur(Date.now() - t.uqStartedAt) : '—';
                const lastLog = (state.log && state.log.length) ? state.log[state.log.length - 1] : '';
                const kv3 = WB().h('div', { class: 'wb-form-grid', style: 'grid-template-columns:repeat(3,1fr);max-width:1180px;margin-bottom:14px' });
                [['已用有效时间', elapsed], ['运行前预估(保留原值)', '约30分钟 / 20~50分钟'],
                 ['当前进度', (cur >= 0 ? stageDefs[cur][0] + ' / ' : '') + (lastLog ? lastLog.slice(0, 24) : (t.uqMessage || '启动中'))]]
                    .forEach(([k, v]) => kv3.appendChild(WB().h('div', { class: 'wb-field' },
                        WB().h('label', null, k), WB().h('input', { readonly: '', value: String(v).slice(0, 40) }))));
                wrap.appendChild(kv3);
                wrap.appendChild(WB().h('div', { class: 'wb-section-title', style: 'margin:6px 0 8px' }, '运行日志'));
                wrap.appendChild(WB().h('pre', {
                    id: 'uq-log-box',
                    style: 'max-height:260px;overflow:auto;background:#101418;color:#cde3d8;padding:12px;border-radius:8px;font-size:12px;line-height:1.5;white-space:pre-wrap'
                }, (state.log && state.log.length ? state.log.join('\n') : '等待MATLAB输出...')));
                wrap.appendChild(WB().h('div', { class: 'wb-actions-row', style: 'margin-top:12px' },
                    WB().h('button', { class: 'wb-btn wb-btn-outline', onclick: () => {
                        const box = document.querySelector('#uq-log-box');
                        if (box) box.scrollTop = box.scrollHeight;
                    } }, '📄 查看运行日志'),
                    WB().h('button', { class: 'wb-btn wb-btn-outline', onclick: async () => {
                        try {
                            await window.AppConfig.enginePost('projects/' + encodeURIComponent(ctx.project.id)
                                + '/tasks/' + encodeURIComponent(t.id) + '/uq/stop', {});
                            toast('已请求安全暂停(协作取消,结果作废)', 'info');
                        } catch (e) { toast('取消失败:' + e.message, 'error'); }
                        startPolling();
                    } }, '请求安全暂停'),
                    WB().h('div', { class: 'wb-spacer' }),
                    WB().h('button', { class: 'wb-btn wb-btn-primary', onclick: () => { state.tab = 'result'; renderBody(); } }, '返回飞行模型结果')));
                // 渲染路径只补开通道,不重置轮询窗口:renderBody每次都走这里,
                // 无条件startPolling会把轮询截止时间无限顺延(/status永久轮询的根因)
                if (!state.es && !state.timer) startPolling();
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

            /* 04-15 结果视图:完成后先展示区间结果与来源追溯,再评估入口随下方保留 */
            if (t.uqStatus === 'COMPLETED') {
                const uqRes = t.uqResult || {};
                // 04-15:有限样本条件评估提示
                wrap.appendChild(WB().h('div', { class: 'wb-infobar', style: 'border-left:4px solid #d97706;background:#fffbeb;color:#92400e;margin-bottom:12px' },
                    '⚠ 有限样本条件评估:统计限制随结果保存,不标为全局完备后验。'
                    + (uqRes.intervalStatus ? ('区间状态: ' + uqRes.intervalStatus + '。') : '')));
                // 身份与追溯摘要(04-15标题区:建模/模型/UQ标识/参数分布)
                const kv = WB().h('div', { class: 'wb-kv', style: 'max-width:1180px' });
                [
                    ['评估标识', uqRes.runTag ? ('UQ-' + uqRes.runTag) : (t.runId ? 'UQ-' + t.runId : '—')],
                    ['评估方法', uqRes.method === 'C' ? 'C:非线性粒子评估' : uqRes.method === 'D' ? 'D:快速局部初评' : (uqRes.method || '—')],
                    ['预计 / 实际', (t.uqStartedAt && t.uqFinishedAt) ? formatDur(t.uqFinishedAt - t.uqStartedAt) : '—'],
                    ['概率先验来源', uqRes.sourceWorkbook ? fileName(String(uqRes.sourceWorkbook)) : '—'],
                    ['区间交付Excel', uqRes.workbook ? fileName(String(uqRes.workbook)) : '未找到'],
                    ['输出目录', uqRes.outputRoot || '—']
                ].forEach(([k, v]) => { kv.appendChild(WB().h('div', { class: 'k' }, k)); kv.appendChild(WB().h('div', { class: 'v' }, String(v))); });
                wrap.appendChild(kv);
                // 区间参数表(04-15主体:节点坐标/确定性值/评估均值/95%参数区间/本次处理)
                wrap.appendChild(WB().h('div', { class: 'wb-section-title', style: 'margin:14px 0 8px' }, '全部参数区间与来源追溯'));
                const holder = WB().h('div', null, WB().h('div', { class: 'wb-hint' }, '区间表加载中...'));
                wrap.appendChild(holder);
                window.AppConfig.engineGet('projects/' + encodeURIComponent(ctx.project.id)
                    + '/tasks/' + encodeURIComponent(t.id) + '/uq/interval-table')
                    .then(resp => {
                        holder.innerHTML = '';
                        if (!(resp && (resp.success || resp.code === 200) && resp.data)) {
                            holder.appendChild(WB().h('div', { class: 'wb-hint' },
                                '区间表暂不可读: ' + ((resp && resp.message) || '详见评估记录') + ';交付Excel可通过「导出参数表」获取。'));
                            return;
                        }
                        const d = resp.data;
                        // 页签切换(全部参数/燃油偏置/工程补偿与诊断≈按Sheet拆分)
                        const names = Array.isArray(d.sheetNames) ? d.sheetNames : [];
                        let curSheet = d.sheet;
                        const tblHolder = WB().h('div', null);
                        const renderSheet = sn => {
                            const load = sn2 => window.AppConfig.engineGet('projects/' + encodeURIComponent(ctx.project.id)
                                + '/tasks/' + encodeURIComponent(t.id) + '/uq/interval-table?sheet=' + encodeURIComponent(sn2));
                            load(sn).then(r2 => {
                                if ((r2 && (r2.success || r2.code === 200)) && r2.data) {
                                    drawTable(tblHolder, r2.data);
                                } else { drawTable(tblHolder, d); }
                            }).catch(() => drawTable(tblHolder, d));
                        };
                        const drawTable = (box, dd) => {
                            box.innerHTML = '';
                            const headers = dd.headers || [], rows = dd.rows || [];
                            if (!headers.length) {
                                box.appendChild(WB().h('div', { class: 'wb-hint' }, '该Sheet无表头数据。'));
                                return;
                            }
                            const tbl = WB().h('table', { class: 'wb-table', style: 'max-width:1180px' });
                            const tr = WB().h('tr', null);
                            headers.forEach(hd => tr.appendChild(WB().h('th', null, hd || '')));
                            tbl.appendChild(tr);
                            rows.forEach(rw => {
                                const r2 = WB().h('tr', null);
                                headers.forEach((hd, i) => r2.appendChild(WB().h('td', null, String(rw[i] == null ? '' : rw[i]))));
                                tbl.appendChild(r2);
                            });
                            box.appendChild(tbl);
                            drawErrBars(box, dd);
                            if (dd.totalRows > rows.length) {
                                box.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin-top:6px' },
                                    '共 ' + dd.totalRows + ' 行,页内展示前 ' + rows.length + ' 行;完整数据请导出参数表。'));
                            }
                        };
                        /* —— 04-25 逐点/逐节点区间误差棒图:坐标列+均值列±95%区间列,圆点为均值竖线为区间 —— */
                        const drawErrBars = (box, dd) => {
                            try {
                                const hs = (dd.headers || []).map(h => String(h || ''));
                                const xi = hs.findIndex(h => /(坐标|x_|^x$|流量|质量流量)/i.test(h) && !/max|最大/i.test(h));
                                const mi = hs.findIndex(h => /均值|mean/i.test(h));
                                const li = hs.findIndex(h => /下限|lower|2\.5/i.test(h));
                                const ui = hs.findIndex(h => /上限|upper|97\.5/i.test(h));
                                if (xi < 0 || mi < 0) return;
                                const pts = (dd.rows || []).map(r => ({
                                    x: parseFloat(r[xi]), m: parseFloat(r[mi]),
                                    lo: li >= 0 ? parseFloat(r[li]) : null,
                                    up: ui >= 0 ? parseFloat(r[ui]) : null
                                })).filter(p => isFinite(p.x) && isFinite(p.m));
                                if (pts.length < 2) return;
                                const W = 900, H = 240, PADL = 64, PADB = 34, PADT = 14, PADR = 14;
                                const xs = pts.map(p => p.x);
                                const xmin = Math.min.apply(null, xs), xmax = Math.max.apply(null, xs);
                                const vals = [];
                                pts.forEach(p => { vals.push(p.m); if (isFinite(p.lo)) vals.push(p.lo); if (isFinite(p.up)) vals.push(p.up); });
                                const vmin = Math.min.apply(null, vals), vmax = Math.max.apply(null, vals);
                                const vpad = (vmax - vmin) * 0.1 || Math.abs(vmax) * 0.05 || 1;
                                const x2px = v => PADL + (v - xmin) / ((xmax - xmin) || 1) * (W - PADL - PADR);
                                const y2px = v => H - PADB - (v - (vmin - vpad)) / ((vmax + vpad) - (vmin - vpad) || 1) * (H - PADT - PADB);
                                const NS = 'http://www.w3.org/2000/svg';
                                const svg = document.createElementNS(NS, 'svg');
                                svg.setAttribute('viewBox', '0 0 ' + W + ' ' + H);
                                svg.setAttribute('style', 'width:100%;max-width:960px;background:#fff;border:1px solid #e5e7eb;border-radius:8px;margin-top:12px');
                                // y 轴刻度(5档)
                                for (let k = 0; k <= 4; k++) {
                                    const vv = (vmin - vpad) + k * ((vmax + vpad) - (vmin - vpad)) / 4;
                                    const yy = y2px(vv);
                                    const ln = document.createElementNS(NS, 'line');
                                    ln.setAttribute('x1', PADL); ln.setAttribute('x2', W - PADR);
                                    ln.setAttribute('y1', yy); ln.setAttribute('y2', yy);
                                    ln.setAttribute('stroke', '#f1f5f9'); svg.appendChild(ln);
                                    const tx = document.createElementNS(NS, 'text');
                                    tx.setAttribute('x', PADL - 6); tx.setAttribute('y', yy + 4);
                                    tx.setAttribute('text-anchor', 'end'); tx.setAttribute('font-size', '11');
                                    tx.setAttribute('fill', '#64748b');
                                    tx.textContent = Math.abs(vv) >= 1000 ? vv.toFixed(0) : vv.toPrecision(3);
                                    svg.appendChild(tx);
                                }
                                // x 轴刻度(6档)
                                for (let k = 0; k <= 5; k++) {
                                    const vv = xmin + k * (xmax - xmin) / 5;
                                    const tx = document.createElementNS(NS, 'text');
                                    tx.setAttribute('x', x2px(vv)); tx.setAttribute('y', H - PADB + 16);
                                    tx.setAttribute('text-anchor', 'middle'); tx.setAttribute('font-size', '11');
                                    tx.setAttribute('fill', '#64748b');
                                    tx.textContent = Math.abs(vv) >= 1000 ? vv.toFixed(0) : vv.toPrecision(3);
                                    svg.appendChild(tx);
                                }
                                // 误差棒+均值点
                                pts.forEach(p => {
                                    const hasInt = isFinite(p.lo) && isFinite(p.up);
                                    if (hasInt) {
                                        const ln = document.createElementNS(NS, 'line');
                                        ln.setAttribute('x1', x2px(p.x)); ln.setAttribute('x2', x2px(p.x));
                                        ln.setAttribute('y1', y2px(p.up)); ln.setAttribute('y2', y2px(p.lo));
                                        ln.setAttribute('stroke', '#0f766e'); ln.setAttribute('stroke-width', '1.6');
                                        svg.appendChild(ln);
                                    }
                                    const c = document.createElementNS(NS, 'circle');
                                    c.setAttribute('cx', x2px(p.x)); c.setAttribute('cy', y2px(p.m));
                                    c.setAttribute('r', 4);
                                    c.setAttribute('fill', hasInt ? '#0f766e' : '#94a3b8');
                                    svg.appendChild(c);
                                });
                                box.appendChild(svg);
                                box.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin-top:4px' },
                                    '圆点为均值,竖线为本次95%参数区间;灰色表示未独立抽样,不表示区间为等(04-25)。'));
                            } catch (e) { /* 误差棒为增强项,失败不影响表格 */ }
                        };
                        if (names.length > 1) {
                            const bar = WB().h('div', { class: 'wb-actions-row', style: 'margin-bottom:8px' });
                            names.forEach(sn => {
                                bar.appendChild(WB().h('button', {
                                    class: 'wb-btn wb-btn-outline',
                                    onclick: () => { curSheet = sn; renderSheet(sn); }
                                }, sn));
                            });
                            holder.appendChild(bar);
                        }
                        holder.appendChild(tblHolder);
                        drawTable(tblHolder, d);
                    })
                    .catch(e => { holder.innerHTML = ''; holder.appendChild(WB().h('div', { class: 'wb-hint' }, '区间表加载失败:' + e.message)); });
                wrap.appendChild(holder);
                wrap.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin:10px 0;max-width:1180px' },
                    '全部参数及燃油偏置的区间来源逐节点可追溯(04-15);结果另存,不覆盖确定性估计值。'));
                // 04-26:不同区间回答不同工程问题,不使用含义不清的总区间
                const rng = WB().h('table', { class: 'wb-table', style: 'max-width:1180px' },
                    WB().h('tr', null, ['区间范围', '含义'].map(x => WB().h('th', null, x))));
                [
                    ['参数传播区间', '固定输入下传播参数不确定性(后验样本直接传播)'],
                    ['物理输出区间', '在参数传播基础上加入输入误差与模型差异;不含输出量噪声'],
                    ['测量输出区间', '在物理输出基础上再加输出测量误差;与实测对照时使用']
                ].forEach(([a, b]) => rng.appendChild(WB().h('tr', null,
                    WB().h('td', null, a), WB().h('td', { class: 'wb-hint' }, b))));
                wrap.appendChild(rng);
                wrap.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin:6px 0;max-width:1180px' },
                    '有限样本下按成功子集保存权重与未计算范围;灰色节点表示未独立抽样,不表示区间为零(04-25)。'));
                wrap.appendChild(WB().h('div', { class: 'wb-actions-row', style: 'margin-bottom:16px' },
                    uqRes.workbook ? WB().h('a', {
                        class: 'wb-btn wb-btn-outline',
                        href: window.AppConfig.api.baseURL + '/api/engine/projects/' + encodeURIComponent(ctx.project.id)
                            + '/tasks/' + encodeURIComponent(t.id) + '/uq/workbook',
                        download: ''
                    }, '⬇ 导出参数表') : null,
                    WB().h('div', { class: 'wb-spacer' }),
                    WB().h('button', { class: 'wb-btn wb-btn-primary', onclick: () => { state.tab = 'result'; renderBody(); } }, '返回飞行模型结果')));
                wrap.appendChild(WB().h('div', { class: 'wb-section-title', style: 'margin:6px 0 8px' }, '重新发起评估'));
            }

            state.uqMethod = state.uqMethod || 'C';
            const objInp = WB().h('input', { readonly: '', value: (t.name || t.runId || '本架次模型')
                + ' / ' + (t.identificationFile ? fileName(t.identificationFile) : '训练窗口') });
            const idInp = WB().h('input', { readonly: '', value: 'UQ-' + (t.runId || t.id) + '(记录标识由服务端生成)' });
            const methodSel = WB().h('select', { style: 'width:100%' });
            const optC = WB().h('option', { value: 'C' }, 'C:非线性粒子评估');
            const optD = WB().h('option', { value: 'D' }, 'D:快速局部初评');
            optC.selected = state.uqMethod !== 'D'; optD.selected = state.uqMethod === 'D';
            methodSel.appendChild(optC); methodSel.appendChild(optD);
            methodSel.addEventListener('change', () => { state.uqMethod = methodSel.value; });
            const channelInp = WB().h('input', { readonly: '', value: 'F-07-F3 独立UQ(C/D) · 同次冻结结果根' });
            wrap.appendChild(WB().h('div', { class: 'wb-form-grid', style: 'grid-template-columns:1fr 1fr;max-width:1180px;margin-bottom:6px' },
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '评估对象(本任务已保存模型)'), objInp),
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '本次评估编号'), idInp),
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '方法'), methodSel),
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '评估通道'), channelInp)));
            wrap.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin:0 0 10px' },
                '评估走 F3 稳态飞参专用合同:复用本任务建模时冻结的确认凭据与结果根,概率先验由服务端从项目内已接受的 UQ 后验交付中选取;'
                + '不消费试车建模的 512/1024 粒子数设置。D 为快速局部初评,C 为非线性粒子评估。'));

            /* 配置内容表(04-13):由本任务数据如实汇总 */
            wrap.appendChild(WB().h('table', { class: 'wb-table', style: 'max-width:1180px' },
                WB().h('tr', null, ['配置内容', '当前选择'].map(x => WB().h('th', null, x))),
                WB().h('tr', null, WB().h('td', null, '建模证据'),
                    WB().h('td', { class: 'wb-hint' }, (t.identificationFile ? fileName(t.identificationFile) : '—')
                        + ' 完整窗口均值;独立测试' + (t.validationFile ? '已提供(' + fileName(t.validationFile) + ')' : '未提供;不显示测试通过率'))),
                WB().h('tr', null, WB().h('td', null, '先验设置'),
                    WB().h('td', { class: 'wb-hint' }, '确定性结果只作数值起点;概率先验须为 formal_status=ACCEPTED 且含后验样本的 2p4/2p7 UQ 交付,由服务端按方法与节点一致性选取')),
                WB().h('tr', null, WB().h('td', null, '参数与条件项'),
                    WB().h('td', { class: 'wb-hint' }, '全部参数与燃油偏置节点(以交付Excel参数表为准);固定继承项不参与抽样')),
                WB().h('tr', null, WB().h('td', null, '数值起点'),
                    WB().h('td', { class: 'wb-hint' }, '使用本次确定性结果')),
                WB().h('tr', null, WB().h('td', null, '输出范围'),
                    WB().h('td', { class: 'wb-hint' }, '全部参数与燃油节点区间、条件处理说明、诊断及独立评估文件(04-15:区间来源逐节点可追溯)')),
                WB().h('tr', null, WB().h('td', null, '预计耗时'),
                    WB().h('td', { class: 'wb-hint' }, '首次粗估约30分钟(参考20~50分钟);含准备、主计算、复算和写出,不含新工况预测;实际以评估记录为准'))));

            /* 发起:F-07-F3 专用UQ通道。服务端按本任务已交付的建模结果目录、建模时冻结的
             * 确认凭据和项目内可用的UQ后验交付(概率先验)组配置;不消费试车建模的
             * modelAssetId / particleCount,也不需要为了发起评估而临时登记模型成果。 */
            const launch = async () => {
                try {
                    const resp = await window.AppConfig.enginePost(
                        'projects/' + encodeURIComponent(ctx.project.id) + '/tasks/'
                        + encodeURIComponent(t.id) + '/uq?method=' + encodeURIComponent(state.uqMethod),
                        {});
                    if (resp && (resp.success || resp.code === 200)) {
                        toast('F3稳态飞参UQ评估已发起;进度见本页与评估记录', 'success');
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
            appendF3Artifacts(wrap, t, ctx, state);
            wrap.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin:10px 0' },
                '全部参数清单(含燃油偏置与物理横坐标)、逐工况值与平衡/求解诊断随交付Excel与运行记录提供;最小模型交付与完整结果浏览分开。'));
            // 04-12:保存确认视图——模型名称可编辑+来源链表,一键隐式登记改为显式确认
            if (state.saveConfirm) {
                const nameInp = WB().h('input', { value: state.saveName || ((t.name || L.title) + '-模型') });
                nameInp.addEventListener('input', () => { state.saveName = nameInp.value; });
                const chain = WB().h('table', { class: 'wb-table', style: 'max-width:1180px' },
                    WB().h('tr', null, ['关联内容', '保存内容'].map(x => WB().h('th', null, x))));
                [
                    ['模型来源', (t.parentSource || '2p4') + (t.parentWorkbook ? ' · ' + fileName(t.parentWorkbook) : '')],
                    ['本次证据', (t.identificationFile ? fileName(t.identificationFile) : '—')
                        + (t.validationFile ? ' + 独立测试 ' + fileName(t.validationFile) : '')],
                    ['模型方法', '稳态飞参 · ' + (t.dataMethod === 'steady_plus_small_history' ? '稳态+小幅混合' : '稳态曲线')],
                    ['数值诊断', r.stopReason ? ('停止原因: ' + r.stopReason + '(未确认收敛)') : '正常收敛'],
                    ['交付文件', r.deliveryWorkbookFile ? fileName(r.deliveryWorkbookFile) : '—'],
                    ['运行标识', r.runId || t.runId || '—']
                ].forEach(([a, b]) => chain.appendChild(WB().h('tr', null,
                    WB().h('td', null, a), WB().h('td', { class: 'wb-hint' }, String(b)))));
                wrap.appendChild(WB().h('div', { class: 'wb-section-title', style: 'margin:14px 0 8px' }, '保存确认(04-12:保留完整来源链)'));
                wrap.appendChild(WB().h('div', { class: 'wb-form-grid', style: 'grid-template-columns:1fr 1fr;max-width:1180px;margin-bottom:8px' },
                    WB().h('div', { class: 'wb-field' }, WB().h('label', null, '模型编号(自动生成)'), WB().h('input', { readonly: '', value: 'MF-' + (t.runId || t.id) })),
                    WB().h('div', { class: 'wb-field' }, WB().h('label', null, '模型名称'), nameInp)));
                wrap.appendChild(chain);
                wrap.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin:8px 0;max-width:1180px' },
                    '保存后模型进入模型成果,可交给不确定性评估与新工况预测;原始数据与运行记录保留,不因保存而改动。'));
                wrap.appendChild(WB().h('div', { class: 'wb-actions-row', style: 'margin-top:6px' },
                    WB().h('button', { class: 'wb-btn wb-btn-outline', onclick: () => { state.saveConfirm = false; renderBody(); } }, '取消'),
                    WB().h('div', { class: 'wb-spacer' }),
                    WB().h('button', { class: 'wb-btn wb-btn-primary', onclick: () => saveModel(false) }, '✓ 确认登记到模型成果')));
            } else {
                wrap.appendChild(WB().h('div', { class: 'wb-actions-row', style: 'margin-top:12px' },
                    WB().h('button', { class: 'wb-btn wb-btn-primary', onclick: () => { state.saveConfirm = true; renderBody(); } }, '保存模型(登记到模型成果)'),
                    r.deliveryWorkbookFile ? WB().h('button', {
                        class: 'wb-btn wb-btn-outline',
                        onclick: () => window.open(window.AppConfig.api.baseURL + '/api/engine/projects/'
                            + encodeURIComponent(ctx.project.id) + '/tasks/' + encodeURIComponent(t.id)
                            + '/status', '_blank')
                    }, '查看运行记录') : null));
            }
            return wrap;
        }

        async function saveModel(gotoModels) {
            const t = state.task;
            try {
                const resp = await window.AppConfig.enginePost(
                    'projects/' + encodeURIComponent(ctx.project.id || '') + '/tasks/'
                    + encodeURIComponent(t.id) + '/save-model',
                    { name: state.saveName || ((t.name || L.title) + '-模型') });
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

        /** 状态应用(SSE chg负载与 /status 响应同构 {task, logTail}):SSE活跃期间零status轮询XHR */
        function applyData(d) {
            const prev = state.task ? state.task.status : null;
            const prevUq = state.task ? state.task.uqStatus : null;
            if (d && (d.success || d.code === 200) && d.data && d.data.task) {
                state.task = d.data.task;
                if (Array.isArray(d.data.logTail) && d.data.logTail.length) state.log = d.data.logTail;
            }
            // 准备/执行结束一次性提示:运行态→终态跃迁时弹窗,覆盖确认失败(READY+message)
            // 与建模失败(RUNNING→FAILED)两类静默场景;终态后轮询自停,不会重复弹
            const RUN_ST = ['PREPARING', 'RUNNING', 'STOP_REQUESTED'];
            if (prev && RUN_ST.includes(prev) && state.task && !RUN_ST.includes(state.task.status)) {
                const st2 = state.task.status, msg = state.task.message || '';
                if (st2 === 'FAILED') toast('建模执行失败: ' + msg, 'error');
                else if (st2 === 'READY' && msg.indexOf('失败') >= 0) toast(msg, 'error');
                else if (st2 === 'READY' && state.task.prepMessage) toast(state.task.prepMessage, 'success');
                else if (st2 === 'COMPLETED') toast('任务已完成', 'success');
                else if (st2 === 'STOPPED') toast('已安全停止', 'info');
            }
            // UQ执行态→终态跃迁:停轮询回到结果/重发视图(曾因终态不停轮询+渲染路径
            // 反复重置轮询窗口,导致 /status 无限轮询且卡在执行中页面)
            const UQ_RUN = ['EXECUTING', 'PREPARING'];
            if (prevUq && UQ_RUN.includes(prevUq) && state.task && !UQ_RUN.includes(state.task.uqStatus)) {
                const ns = state.task.uqStatus;
                if (ns === 'COMPLETED') toast('UQ评估完成;结果另存,不覆盖确定性估计值', 'success');
                else toast('UQ评估已中断/失败: ' + String(state.task.uqMessage || '详见日志').slice(0, 80), 'error');
                stopPolling();
            }
            const uqRun = state.task && UQ_RUN.includes(state.task.uqStatus);
            if (running(state.task) || uqRun) window.__WB_ENGINE_POLL_UNTIL__ = Date.now() + 40000;
            else if ((window.__WB_ENGINE_POLL_UNTIL__ || 0) < Date.now()) stopPolling();
            renderBody();
        }
        function poll() {
            const t = state.task;
            if (!t || !ctx.project.id) return;
            const uqRun = t.uqStatus === 'EXECUTING' || t.uqStatus === 'PREPARING';
            if (!running(t) && !uqRun && (window.__WB_ENGINE_POLL_UNTIL__ || 0) < Date.now()) return;
            // UQ执行期间保持兜底轮询活性(SSE断链时也不漏终态)
            if (uqRun) window.__WB_ENGINE_POLL_UNTIL__ = Date.now() + 40000;
            window.AppConfig.engineGet(
                'projects/' + encodeURIComponent(ctx.project.id) + '/tasks/'
                + encodeURIComponent(t.id) + '/status')
                .then(resp => applyData(resp))
                .catch(() => { });
        }
        function startPolling() {
            window.__WB_ENGINE_POLL_UNTIL__ = Date.now() + 40000;
            if (state.es) return;
            // SSE与轮询互斥:断链兜底定时器残留时重建SSE,必须先退掉定时器,
            // 否则SSE活跃期间5s /status轮询永久并存
            if (state.timer) { clearInterval(state.timer); state.timer = null; }
            // SSE 通知流为主:chg负载直接渲染(不再回拉status);失败回退5s定时轮询
            try {
                const cfg0 = window.AppConfig;
                const url = cfg0.api.baseURL + '/api/engine/projects/' + encodeURIComponent(ctx.project.id || '')
                    + '/tasks/' + encodeURIComponent(state.task.id) + '/stream?token=' + encodeURIComponent(cfg0.getToken() || '');
                const es = new EventSource(url);
                state.es = es;
                es.addEventListener('chg', ev => {
                    window.__WB_ENGINE_POLL_UNTIL__ = Date.now() + 40000;
                    try {
                        const d = JSON.parse(ev.data);
                        // 服务端task流负载为裸{task,logTail};补成/status同构信封再应用
                        applyData(d && d.task ? { code: 200, data: d } : d);
                    } catch (e) { poll(); }
                });
                es.addEventListener('end', () => { try { es.close(); } catch (e) { } state.es = null; });
                es.onerror = () => {
                    try { es.close(); } catch (e) { }
                    if (state.es === es) state.es = null;
                    if (!state.timer) state.timer = setInterval(poll, 5000);
                };
                poll();
                return;
            } catch (e) { /* 降级 */ }
            poll();
            state.timer = setInterval(poll, 5000);
        }
        function stopPolling() {
            if (state.timer) { clearInterval(state.timer); state.timer = null; }
            if (state.es) { try { state.es.close(); } catch (e) { } state.es = null; }
        }
        // 进入业务页固定显示新建视图;只有运行记录/项目概览指定 __WB_OPEN_TASK__ 时才打开既有任务
        // 页面切换时由 shell 调用,避免旧页轮询残留(跨页串状态通道)
        window.__WB_PAGE_STOP__ = stopPolling;

        renderBody();
        return root;
    }

    /* ================= F3 运行资产共享渲染(04-09/10、04-24、02-08/09、06-x;数据来自 /f3-artifacts 只读端点) ================= */
    function appendF3Artifacts(wrap, t, ctx, state) {
        if (state.f3Art === undefined) {
            state.f3Art = null;
            window.AppConfig.engineGet('projects/' + encodeURIComponent(ctx.project.id || '')
                    + '/tasks/' + encodeURIComponent(t.id) + '/f3-artifacts')
                .then(resp => {
                    state.f3Art = (resp && (resp.success || resp.code === 200) && resp.data)
                        ? resp.data : { error: (resp && resp.message) || '读取失败' };
                    renderBody();
                })
                .catch(e => { state.f3Art = { error: e.message }; renderBody(); });
            return;
        }
        if (state.f3Art === null) return; // 加载中
        if (state.f3Art.error) {
            wrap.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin:8px 0' },
                '运行摘要不可用:' + state.f3Art.error));
            return;
        }
        const art = state.f3Art;
        // 运行摘要与估时(f3_result_manifest.json:收敛/迭代/参数量/估时口径)
        if (art.manifest) {
            const m = art.manifest, est = m.estimate || {};
            const kv = WB().h('div', { class: 'wb-kv', style: 'max-width:1180px' });
            [
                ['收敛状态', m.converged === true ? '已收敛' : m.converged === false ? '未确认收敛' : '—'],
                ['停止原因', m.stopReason || '—'],
                ['迭代数 / 参数量', (m.iterationCount != null ? m.iterationCount : '—') + ' / ' + (m.parameterCount != null ? m.parameterCount : '—')],
                ['目标函数(先验→最终)', (m.priorObjective != null && m.finalObjective != null)
                    ? (Number(m.priorObjective).toExponential(3) + ' → ' + Number(m.finalObjective).toExponential(3)) : '—'],
                ['估时基准', est.baselineVersion || '—'],
                ['估时口径', est.transient && (est.transient.scope || est.transient.meaning)
                    ? String(est.transient.scope || est.transient.meaning) : '—']
            ].forEach(([k, v]) => { kv.appendChild(WB().h('div', { class: 'k' }, k)); kv.appendChild(WB().h('div', { class: 'v' }, String(v))); });
            wrap.appendChild(WB().h('div', { class: 'wb-section-title', style: 'margin:14px 0 8px' }, '运行摘要与估时(06-04/06:估时区间为工程排期范围,不是统计置信区间)'));
            wrap.appendChild(kv);
        }
        // 运行包版本绑定(02-08/09:父工作簿SHA与运行包清单SHA,身份与凭证流量分开)
        const cf = art.confirm || {};
        const ra = cf.runtimeAssociation || (cf.configuration && cf.configuration.parentRuntimeBinding) || null;
        if (ra) {
            const kv2 = WB().h('div', { class: 'wb-kv', style: 'max-width:1180px' });
            [
                ['父工作簿 SHA-256', ra.workbookSha256 || '—'],
                ['运行包清单 SHA-256', ra.runtimeManifestSha256 || ra.sourceManifestSHA256 || '—'],
                ['绑定依据', ra.basis || '—'],
                ['模型模式', cf.runtimeAssociation
                    ? ('modelMode=' + (ra.modelMode != null ? ra.modelMode : '—')
                        + '; 状态数=' + (ra.stateCount != null ? ra.stateCount : '—')
                        + '; 热模式=' + (ra.thermalMode != null ? ra.thermalMode : '—')) : '随父模型']
            ].forEach(([k, v]) => { kv2.appendChild(WB().h('div', { class: 'k' }, k)); kv2.appendChild(WB().h('div', { class: 'v' }, String(v))); });
            wrap.appendChild(WB().h('div', { class: 'wb-section-title', style: 'margin:14px 0 8px' },
                '运行包版本绑定(02-08/09:旧运行包只完整计算,新运行包按合同重新求值,不改写已有结果)'));
            wrap.appendChild(kv2);
        }
        // 全量参数清单(04-10):parameterStatus 全量展示 + CSV 导出
        const ps = Array.isArray(cf.parameterStatus) ? cf.parameterStatus : null;
        if (ps && ps.length) {
            wrap.appendChild(WB().h('div', { class: 'wb-section-title', style: 'margin:14px 0 8px' },
                '全部参数清单(04-10:' + ps.length + ' 项,含固定与本次估计;集合口径=稳态曲线+装机量+燃油偏置)'));
            const headers = Object.keys(ps[0] || {});
            const tbl = WB().h('div', { style: 'max-height:320px;overflow:auto;border:1px solid #e5e7eb;border-radius:6px' });
            const t10 = WB().h('table', { class: 'wb-table', style: 'font-size:12px' });
            t10.appendChild(WB().h('tr', null, headers.map(hd => WB().h('th', null, hd))));
            ps.forEach(r => t10.appendChild(WB().h('tr', null,
                headers.map(hd => WB().h('td', { class: 'wb-hint' }, String(r[hd] == null ? '' : r[hd]))))));
            tbl.appendChild(t10);
            wrap.appendChild(tbl);
            wrap.appendChild(WB().h('div', { class: 'wb-actions-row', style: 'margin:6px 0' },
                WB().h('button', {
                    class: 'wb-btn wb-btn-outline',
                    onclick: () => {
                        const csv = headers.join(',') + '\n' + ps.map(r => headers.map(hd => '"' + String(r[hd] == null ? '' : r[hd]).replace(/"/g, '""') + '"').join(',')).join('\n');
                        const blob = new Blob(['\uFEFF' + csv], { type: 'text/csv;charset=utf-8' });
                        const a = document.createElement('a');
                        a.href = URL.createObjectURL(blob);
                        a.download = '全部参数表_' + (t.runId || t.id) + '.csv';
                        a.click();
                        setTimeout(() => URL.revokeObjectURL(a.href), 3000);
                    }
                }, '导出全部参数表'),
                WB().h('span', { class: 'wb-hint', style: 'margin:0' },
                    '自由度(可估参数数)不等于参数字典数;父节点/更新状态以「节点/状态」列为准(04-10)。')));
        }
        // 资产完整性表(04-24:离线只读查看与重新计算分开)
        {
            const mOk = !!art.manifest, cOk = !!art.confirm, sOk = !!art.summaryMd;
            const wbOk = !!(t.result && (t.result.deliveryWorkbookFile || t.result.excelFile));
            wrap.appendChild(WB().h('div', { class: 'wb-section-title', style: 'margin:14px 0 8px' },
                '资产完整性核查(04-24:只读查看不启动DLL;缺少资产不静默补齐)'));
            const at = WB().h('table', { class: 'wb-table', style: 'max-width:1180px' },
                WB().h('tr', null, ['记录', '当前状态', '可执行动作'].map(x => WB().h('th', null, x))));
            [
                ['确定性模型及训练结果', wbOk ? '已恢复(交付Excel在记录中)' : '未找到交付Excel', wbOk ? '查看/导出已存结果' : '重新计算(缺资产)'],
                ['结果清单(manifest)', mOk ? '可读(收敛/估时随清单)' : '未生成', mOk ? '查看运行摘要' : '重新计算'],
                ['运行包与绑定身份', cOk ? '可读(SHA已记录)' : '未生成', cOk ? '查看绑定视图' : '重新准备'],
                ['执行摘要(分段/误差表)', sOk ? '可读' : '未生成', sOk ? '查看下方摘要' : '重新计算'],
                ['原训练数据', '只读查看(不自动重算)', '打开原始记录预览']
            ].forEach(([a, b, c]) => at.appendChild(WB().h('tr', null,
                WB().h('td', null, a), WB().h('td', { class: 'wb-hint' }, b), WB().h('td', { class: 'wb-hint' }, c))));
            wrap.appendChild(at);
            wrap.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin:4px 0;max-width:1180px' },
                '不从开发目录补同名文件、不通过网络下载、不要求预留MATLAB工作区;计算运行包缺少指定DLL时只有「重新计算」可用(04-24)。'));
        }
        // 执行摘要(md表格:分段统计/四通道观测误差/部件工作范围;离线只读核查口径 04-24)
        if (art.summaryMd) {
            wrap.appendChild(WB().h('div', { class: 'wb-section-title', style: 'margin:14px 0 8px' },
                '执行摘要与误差表(离线只读核查:直接读输出目录文件,与本页数值同源)'));
            renderMarkdownSummary(wrap, art.summaryMd);
        }
    }

    /** 执行摘要 markdown 结构化渲染:标题/表格/要点行(不做原始文本 dump)。 */
    function renderMarkdownSummary(wrap, md) {
        const lines = String(md).split(/\r?\n/);
        let i = 0;
        while (i < lines.length) {
            const ln = lines[i];
            const h = ln.match(/^(#{1,4})\s+(.*)$/);
            if (h) {
                wrap.appendChild(WB().h('div', { class: 'wb-section-title', style: 'font-size:' + (h[1].length <= 2 ? 15 : 13) + 'px;margin:12px 0 6px' }, h[2]));
                i++; continue;
            }
            if (/^\s*\|.*\|\s*$/.test(ln)) {
                const tblLines = [];
                while (i < lines.length && /^\s*\|.*\|\s*$/.test(lines[i])) { tblLines.push(lines[i]); i++; }
                const cells = tblLines.map(l => l.trim().replace(/^\||\|$/g, '').split('|').map(c => c.trim()));
                const header = cells[0] || [];
                const bodyRows = cells.slice(1).filter(r => !r.every(c => /^:?-{2,}:?$/.test(c) || c === ''));
                const tbl = WB().h('table', { class: 'wb-table', style: 'max-width:1180px;font-size:12px' });
                tbl.appendChild(WB().h('tr', null, header.map(c => WB().h('th', null, c))));
                bodyRows.forEach(r => tbl.appendChild(WB().h('tr', null, r.map(c => WB().h('td', { class: 'wb-hint' }, c)))));
                wrap.appendChild(tbl);
                continue;
            }
            const tx = ln.trim();
            if (tx) wrap.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin:2px 0;max-width:1180px' }, tx.replace(/^[-*]\s+/, '· ')));
            i++;
        }
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
                            WB().h('option', { value: '' }, '从文件库选择...'));
                        window.AppConfig.engineGet('projects/'
                            + encodeURIComponent(ctx.project.id || '') + '/files/page',
                            { pageSize: 200 })
                            .then(resp => {
                                const rows = resp && resp.data && Array.isArray(resp.data.rows) ? resp.data.rows.filter(x => x && x.id != null) : [];
                                const hit = rows.filter(r0 => /\.(xlsx|xls)$/i.test(String(r0.name || '')));
                                if (!hit.length) {
                                    libSel.appendChild(WB().h('option', { value: '' }, '库内暂无数据文件(可直接上传)'));
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
            const prevScroll = captureLogScroll(body);
            body.innerHTML = '';
            if (state.tab === 'overview') body.appendChild(overviewTab());
            else if (state.tab === 'sorties') body.appendChild(sortiesTab());
            else if (!state.task) { body.appendChild(WB().h('div', { class: 'wb-placeholder' }, WB().h('p', null, '请先在「架次与执行」登记本批架次。'))); }
            else if (state.tab === 'result') body.appendChild(resultTab());
            else if (state.tab === 'uq') body.appendChild(uqTab());
            else body.appendChild(predictEntrance());
            paintTabs();
            restoreLogScroll(body, prevScroll);
        }

        /* ---- 下一架次预测(06-15~19):两模型方案与输入合同(执行需独立预测任务,不在本页自动执行) ---- */
        function predictEntrance() {
            const t = state.task;
            const wrap = WB().h('div', null);
            wrap.appendChild(WB().h('div', { class: 'wb-infobar', style: 'margin-bottom:12px' },
                '先冻结两份模型:「沿用当前正常模型」与「按正常历史趋势外推模型」;两份使用相同未来输入与物理初态计算输出,'
                + '不自动选胜者,不替换当前模型;之后取得测量再建立独立评价记录(06-15/21)。执行需独立预测任务,本页为方案与输入合同配置。'));
            // 06-15:预测方案表
            wrap.appendChild(WB().h('div', { class: 'wb-section-title', style: 'margin:12px 0 8px' }, '预测方案(06-15:沿用与趋势并列)'));
            const plan = WB().h('table', { class: 'wb-table', style: 'max-width:1180px' },
                WB().h('tr', null, ['方案', '做法', '覆盖不足时', '保存后状态'].map(x => WB().h('th', null, x))));
            [
                ['P16-H01 沿用当前模型', '完整复制父曲线、燃油、装机量和固定13项', '不适用(整体复制)', '冻结保存,与来源模型SHA关联'],
                ['P16-T01 正常趋势外推', '仅六项流量/效率坐标线性外推(其余参数不动)', '覆盖不足或越界→保持并注明原因', '冻结保存,外推坐标与原因逐节点可查']
            ].forEach(([a, b, c, d]) => plan.appendChild(WB().h('tr', null,
                WB().h('td', null, a), WB().h('td', { class: 'wb-hint' }, b),
                WB().h('td', { class: 'wb-hint' }, c), WB().h('td', { class: 'wb-hint' }, d))));
            wrap.appendChild(plan);
            wrap.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin:4px 0;max-width:1180px' },
                '明确选择的正常历史 / 实际未父 分开显示;两模型冻结与保存需独立预测任务支持,本页不伪造执行(06-15)。'));
            // 06-16:输入列说明表
            wrap.appendChild(WB().h('div', { class: 'wb-section-title', style: 'margin:14px 0 8px' },
                '预测输入合同(06-16:用输入历程驱动,不伪造未来Np和Ng)'));
            const inCols = WB().h('table', { class: 'wb-table', style: 'max-width:1180px' },
                WB().h('tr', null, ['输入列', '物理含义与单位', '用途'].map(x => WB().h('th', null, x))));
            [
                ['time_s', '相对时间 / s', '预测时间轴'],
                ['Ps0 / Ts_amb', '入口静压 Pa / 环境静温 K', '入口与环境边界'],
                ['Altitude / Mach', '高度 m / 马赫数', '高度边界(可选)'],
                ['Mkp / Mkg', 'PT负载扭矩 N·m / GT附件扭矩 N·m', '负载边界(Mkg默认0)'],
                ['Wf(测量)', '测量燃油流量 kg/s', '按模型扣偏置一次后进入发动机'],
                ['(不提供) Np / Ng', '两轴转速', '预测输出,不是输入;不伪造未来转速']
            ].forEach(([a, b, c]) => inCols.appendChild(WB().h('tr', null,
                WB().h('td', null, a), WB().h('td', { class: 'wb-hint' }, b), WB().h('td', { class: 'wb-hint' }, c))));
            wrap.appendChild(inCols);
            wrap.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin:4px 0;max-width:1180px' },
                '输入Excel(如 forecast_input.xlsx 的 Data 表)与「设置共同初始状态」在独立预测任务中提供;燃油语义=测量值,按模型扣偏置一次(06-16)。'));
            // 06-17:初值与热状态
            wrap.appendChild(WB().h('div', { class: 'wb-section-title', style: 'margin:14px 0 8px' },
                '共同初始状态(06-17:物理轴速/热状态/传感器明确提供)'));
            const initT = WB().h('table', { class: 'wb-table', style: 'max-width:1180px' },
                WB().h('tr', null, ['状态组', '应提供的值', '来源与要求'].map(x => WB().h('th', null, x))));
            [
                ['两轴转速初值', 'Np初值 / Ng初值(物理rpm)', 'MDL公开初始化;可编辑'],
                ['热状态(14项金属温度)', 'HPC/燃烧室/GT/PT 热组件温度', '必须经正式初始化导入并逐值可查;不从界面补零'],
                ['传感器状态(4项)', '传感器内部状态', '随热状态导入;逐值可查'],
                ['来源声明', '热状态来源 / 传感器状态来源下拉', '如提供需6个有限实数及来源(06-17)']
            ].forEach(([a, b, c]) => initT.appendChild(WB().h('tr', null,
                WB().h('td', null, a), WB().h('td', { class: 'wb-hint' }, b), WB().h('td', { class: 'wb-hint' }, c))));
            wrap.appendChild(initT);
            // 06-18/19:执行确认与停续口径
            wrap.appendChild(WB().h('div', { class: 'wb-section-title', style: 'margin:14px 0 8px' },
                '执行确认与停续口径(06-18/19)'));
            const execT = WB().h('table', { class: 'wb-table', style: 'max-width:1180px' },
                WB().h('tr', null, ['项目', '口径'].map(x => WB().h('th', null, x))));
            [
                ['计算对象', 'P16-H01(沿用)/P16-T01(趋势) 各自模型及SHA已记录;共同输入与初态'],
                ['预计用时', '两法计算及导出合计约3~6分钟(参考);不含冷启动'],
                ['输出', '真实模型输出与传感器期望输出分别查看(06-20);新输出目录不覆盖旧输出'],
                ['暂停恢复', '请求事实与Isafe状态分别显示;单条Owner部分积分不能伪恢复(06-19)'],
                ['评价', '冻结预测与后补测量评价分身份保存(06-21);不把预测误差混入建模指标']
            ].forEach(([a, b]) => execT.appendChild(WB().h('tr', null,
                WB().h('td', null, a), WB().h('td', { class: 'wb-hint' }, b))));
            wrap.appendChild(execT);
            wrap.appendChild(WB().h('div', { class: 'wb-actions-row', style: 'margin-top:12px' },
                WB().h('button', { class: 'wb-btn wb-btn-primary', onclick: () => ctx.navigate('predictions') }, '前往输出预测(独立任务)'),
                WB().h('div', { class: 'wb-hint', style: 'margin:0' },
                    '两模型冻结保存与两次真实输出计算在输出预测域执行;本页配置与口径作为预测任务的输入合同(06-18)。')));
            return wrap;
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
                // 06-02:模型类型兼容性对照表(哪些来源可直接采用/哪些需显式绑定)
                wrap.appendChild(WB().h('div', { class: 'wb-section-title', style: 'margin:16px 0 8px' },
                    '模型类型兼容性对照(06-02:选前核对,不默认兼容)'));
                const cmp = WB().h('table', { class: 'wb-table', style: 'max-width:1180px' },
                    WB().h('tr', null, ['模型类型', '实际支持', '选择说明'].map(x => WB().h('th', null, x))));
                [
                    ['TC24 稳态系数模型', '直接采用', '试车稳态系数与调度,含燃油偏置节点'],
                    ['TC27 稳态结果', '直接采用', '组合模型稳态载体;瞬态部分按固定值处理'],
                    ['F33 组合模型', '直接采用', '含稳态+13项瞬态;13项作为本次先验中心'],
                    ['TC27 组合模型(跨项目)', '显式绑定后支持', '需核对节点网格与运行包一致;不符时列出具体原因']
                ].forEach(([a, b, c]) => cmp.appendChild(WB().h('tr', null,
                    WB().h('td', null, a),
                    WB().h('td', { class: 'wb-hint' }, b),
                    WB().h('td', { class: 'wb-hint' }, c))));
                wrap.appendChild(cmp);
                wrap.appendChild(WB().h('div', { class: 'wb-infobar', style: 'margin-top:8px' },
                    '运行关联声明不等于独立物理验证;缺表、缺载体、单位或运行包不符时,准备阶段将给出具体原因(06-02)。'));
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
            // 06-06:逐架次 数据确认/父模型状态/估时状态(估时为容量估计口径,实际耗时以运行记录为准)
            const dataOk = !!t.identificationFile;
            const prepDone = t.status !== 'READY' || state.prepWait === false;
            const estState = t.status === 'COMPLETED'
                ? '实测耗时已回填运行记录;容量估时见运行摘要'
                : dataOk ? '容量估计;输入核验与父绑定后刷新' : '待上传测量Excel';
            const tbl = WB().h('table', { class: 'wb-table' },
                WB().h('tr', null, ['架次 / 次序', '飞参Excel', '父模型状态', '数据确认', '估时状态'].map(x => WB().h('th', null, x))),
                WB().h('tr', null,
                    WB().h('td', null, (t.f3SortieId || '—') + ' / 1'),
                    WB().h('td', null, t.identificationFile ? fileName(t.identificationFile) : '未上传'),
                    WB().h('td', null, t.parentModelId
                        ? String(t.parentModelId) + ' · 已绑定实际SHA'
                        : (t.parentSource || '2p4') + '(根) · 未产生实际父'),
                    WB().h('td', { class: 'wb-hint' },
                        dataOk ? (prepDone ? '测量Excel已核验' : '测量Excel已登记 · 待核验') : '未确认'),
                    WB().h('td', { class: 'wb-hint' }, estState)));
            wrap.appendChild(tbl);
            wrap.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin:6px 0 12px' },
                '必要测量:时间、环境、燃油、PT负载、两轴转速及测量输出;父需为根或登记中更早架次;正常业务不得继承验证场景模型。'));

            // 06-06 确认内容:执行范围/模型与运行包/预计用时/确认后(如实口径,不虚报停续能力)
            const confirmTbl = WB().h('table', { class: 'wb-table', style: 'max-width:1180px' },
                WB().h('tr', null, ['项目', '当前选择或状态'].map(x => WB().h('th', null, x))));
            [
                ['执行范围', '只执行明确选中的架次;缺失父模型时给出依赖错误,不静默换父'],
                ['模型与运行包', '所选实际父 · 建模模式 · 固定13项瞬态和运行资产一致;运行包版本随任务记录'],
                ['预计用时', t.status === 'COMPLETED'
                    ? ('本批次实测耗时' + (t.result && t.result.execution && t.result.execution.actualActiveSeconds != null
                        ? ' ' + Number(t.result.execution.actualActiveSeconds).toFixed(0) + ' s' : '(见运行记录)') + ';不含冷启动与用户暂停')
                    : '本批次辨识估时按程序内置基准;执行核验后按当前窗口与参数工作量刷新'],
                ['确认后', '先执行本架次;后续架次实际父产生后生成新的绑定,不改动旧蓝图']
            ].forEach(([a, b]) => confirmTbl.appendChild(WB().h('tr', null,
                WB().h('td', null, a), WB().h('td', { class: 'wb-hint' }, b))));
            wrap.appendChild(confirmTbl);
            wrap.appendChild(WB().h('div', { class: 'wb-infobar', style: 'margin-top:10px' },
                '后续父尚未产生不是伪造父文件或默认改用根模型的理由。'));

            // 06-05:本批计算配置(固定瞬态不清零;数据方法与配置状态如实展示)
            wrap.appendChild(WB().h('div', { class: 'wb-section-title', style: 'margin:14px 0 8px' },
                '本批计算配置(06-05:选路线与配置,固定瞬态不清零)'));
            const cfgT = WB().h('table', { class: 'wb-table', style: 'max-width:1180px' },
                WB().h('tr', null, ['配置项', '当前值/状态'].map(x => WB().h('th', null, x))));
            [
                ['辨识路径', '瞬态时刻模型(当前默认;F3飞参路径固定)'],
                ['数据方法', (t.dataMethod || 'steady_only') + '(本批已验证稳态点)'],
                ['发动机稳态参数', '使用父模型曲线为先验中心'],
                ['燃油偏置与装机量', '本架次重新估计,先验中心为0'],
                ['13项瞬态参数', '固定为实际父模型值,可查看(不清零)'],
                ['不确定性评估', '另建独立评估;本批不自动部署UQ'],
                ['正则化强度 / 迭代', '随交付程序配置字典(界面不另设默认)']
            ].forEach(([a, b]) => cfgT.appendChild(WB().h('tr', null,
                WB().h('td', null, a), WB().h('td', { class: 'wb-hint' }, b))));
            wrap.appendChild(cfgT);

            // 06-07:逐架次求解状态/结果可用性/下一动作(单架次批次如实展示)
            wrap.appendChild(WB().h('div', { class: 'wb-section-title', style: 'margin:14px 0 8px' },
                '架次求解状态与下一动作(06-07)'));
            const stRow = t.status === 'COMPLETED'
                ? ['完成', '迭代可能达上限→合法模型已保存', '查看模型或继续父链']
                : t.status === 'RUNNING' ? ['执行中', '尚无最终模型', '查询状态/请求安全暂停']
                : t.status === 'STOP_REQUESTED' ? ['已请求暂停/等待安全点', '已完成部分不删除', '等待真实安全点保存']
                : t.status === 'FAILED' ? ['失败', '以服务端记录为准', '查看日志/重新准备']
                : ['待执行', '尚无结果', '上传测量Excel并核验'];
            const stT = WB().h('table', { class: 'wb-table', style: 'max-width:1180px' },
                WB().h('tr', null, ['架次', '求解状态', '结果可用性', '下一动作'].map(x => WB().h('th', null, x))),
                WB().h('tr', null,
                    WB().h('td', null, t.f3SortieId || '—'),
                    WB().h('td', null, stRow[0]),
                    WB().h('td', { class: 'wb-hint' }, stRow[1]),
                    WB().h('td', { class: 'wb-hint' }, stRow[2])));
            wrap.appendChild(stT);
            wrap.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin:4px 0;max-width:1180px' },
                '已完成成果:请求暂停或后续失败不删除已保存合法模型;状态最近更新以轮询与磁盘核对为准(06-07)。'));

            const prepRunning = state.prepWait || t.status === 'PREPARING';
            const isRun = t.status === 'RUNNING';
            wrap.appendChild(WB().h('div', { class: 'wb-section' },
                WB().h('div', { class: 'wb-section-head' },
                    WB().h('div', { class: 'wb-section-title' }, '执行状态'),
                    prepRunning ? WB().h('span', { class: 'wb-tag wb-tag-amber' }, '输入核验中(check)...')
                        : isRun ? WB().h('span', { class: 'wb-tag wb-tag-amber' }, '整批执行中(run)...')
                        : t.status === 'STOP_REQUESTED' ? WB().h('span', { class: 'wb-tag wb-tag-amber' }, '已请求暂停;等待安全点')
                        : t.status === 'READY' ? WB().h('span', { class: 'wb-tag wb-tag-teal' }, '核验通过;可整批执行')
                        : t.status === 'COMPLETED' ? WB().h('span', { class: 'wb-tag wb-tag-teal' }, '已完成')
                        : t.status === 'FAILED' ? WB().h('span', { class: 'wb-tag wb-tag-red' }, '失败')
                        : WB().h('span', { class: 'wb-tag wb-tag-gray' }, '待核验')),
                WB().h('div', { style: 'padding:10px 0' },
                    (prepRunning || isRun)
                        ? WB().h('span', { class: 'wb-inline-loading' }, WB().h('span', { class: 'wb-inline-spinner' }),
                            prepRunning ? '正在检查测量Excel、父模型依赖与输出目录...' : '逐架次:预览→确认数据意图→绑定实际父→执行;身份变化只阻断相关续算...')
                        : t.status === 'STOP_REQUESTED'
                            ? '已请求安全暂停;到达真实安全点保存检查点后才显示已暂停,不提前宣称暂停完成(06-07)。'
                            : WB().h('div', null, t.message || '—')),
                (t.status === 'RUNNING' || t.status === 'STOP_REQUESTED') ? WB().h('pre', {
                    style: 'max-height:200px;overflow:auto;background:#101418;color:#cde3d8;padding:12px;border-radius:8px;font-size:12px;white-space:pre-wrap'
                }, (state.log && state.log.length ? state.log.join('\n') : '等待MATLAB输出...')) : null));

            wrap.appendChild(WB().h('div', { class: 'wb-actions-row', style: 'margin-top:10px' },
                WB().h('button', {
                    class: 'wb-btn wb-btn-outline' + (t.identificationFile && !prepRunning && !isRun && !['COMPLETED'].includes(t.status) ? '' : ' disabled'),
                    onclick: () => { if (t.identificationFile && !prepRunning && !isRun) { window.__WB_ENGINE_POLL_UNTIL__ = Date.now() + 40000; runPrepare(); } }
                }, prepRunning ? '核验中...' : '预览所选架次数据(输入核验)'),
                // 06-07:执行中提供安全暂停发起入口(状态机已支持STOP_REQUESTED,此前UI无路径)
                (isRun || t.status === 'STOP_REQUESTED') ? WB().h('button', {
                    class: 'wb-btn wb-btn-outline' + (t.status === 'STOP_REQUESTED' ? ' disabled' : ''),
                    onclick: async () => {
                        if (t.status === 'STOP_REQUESTED') return;
                        try {
                            await window.AppConfig.enginePost('projects/' + encodeURIComponent(ctx.project.id || '')
                                + '/tasks/' + encodeURIComponent(state.task.id) + '/stop', {});
                            toast('已请求安全暂停;完成当前架次保存合法模型后停止', 'info');
                        } catch (e) { toast('请求停止失败:' + e.message, 'error'); }
                        startPolling();
                    }
                }, t.status === 'STOP_REQUESTED' ? '等待安全点...' : '请求安全暂停') : null,
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
            appendF3Artifacts(wrap, t, ctx, state);
            wrap.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin:10px 0' },
                '全量参数、实际父和本次先验分开;瞬态参数保持实际父值;完整节点和真实覆盖随交付Excel可追溯。'));
            // 06-22:来源与交付成果清单(成果类型/实际用途/是否独立保存)
            const dl = WB().h('table', { class: 'wb-table', style: 'max-width:1180px' },
                WB().h('tr', null, ['成果类型', '实际用途', '是否独立保存'].map(x => WB().h('th', null, x))));
            [
                ['本架次模型Excel', '交付组合模型(稳态继承+本架次估计)', '是' + (r.deliveryWorkbookFile ? '(' + fileName(r.deliveryWorkbookFile) + ')' : '')],
                ['结果Excel', '训练对照与全部参数随结果交付', '是'],
                ['运行记录', '运行标识/父链/估时/日志', '是(输出目录)'],
                ['配置与检查点', '输入身份与安全暂停快照', '内部(不单独交付)'],
                ['跨架次趋势', '正常历史修正值并列', '另行聚合(06-12)'],
                ['UQ交付', '本架次模型的独立区间', '独立UQ任务另存(06-13/14)'],
                ['下一架次预测', '沿用/趋势两模型+输出', '独立预测任务另存(06-15)'],
                ['图片与报告', '诊断图随运行目录', '是(输出目录)']
            ].forEach(([a, b, c]) => dl.appendChild(WB().h('tr', null,
                WB().h('td', null, a), WB().h('td', { class: 'wb-hint' }, b), WB().h('td', { class: 'wb-hint' }, c))));
            wrap.appendChild(dl);
            wrap.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin:6px 0;max-width:1180px' },
                '独立离线与界面使用同一核心;只读查看已保存Excel不加载DLL;继续计算需要完整依赖与原身份(06-22)。'));
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
                // 渲染路径只补开通道,不重置轮询窗口(与稳态飞参页同一修复口径)
                if (!state.es && !state.timer) startPolling();
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
            // 06-14:固定条件/概率派生/预计耗时状态表 + 完整数据确认复选框
            const condTbl = WB().h('table', { class: 'wb-table', style: 'max-width:1180px;margin-top:10px' },
                WB().h('tr', null, ['项目', '当前口径'].map(x => WB().h('th', null, x))));
            [
                ['实际父模型13项瞬态参数', '固定为实际父模型值,不进入本次采样'],
                ['概率先验', '服务端从项目内 formal_status=ACCEPTED 的演化起点(2p4)方法C交付中选取;不自动把确定性父或上一次先后验充当先验'],
                ['重新绑定确认', '目标模型显式重绑定后发起;未改宽文件、数据或运行身份检查'],
                ['预计耗时', '首次评估约30分钟(参考20~50分钟);D为有限局部非驻点证明,完整C尚未对目标样本计算'],
                ['已有验证', '登记快照不等于概要文件仍可用;其他模型的UQ只在其原模型查看,不贴到当前模型']
            ].forEach(([a, b]) => condTbl.appendChild(WB().h('tr', null,
                WB().h('td', null, a), WB().h('td', { class: 'wb-hint' }, b))));
            wrap.appendChild(condTbl);
            const confirmChk = WB().h('input', { type: 'checkbox' });
            wrap.appendChild(WB().h('div', { class: 'wb-hint', style: 'margin:10px 0;max-width:900px' },
                confirmChk,
                ' 本次完整数据确认:已确认当前目标重绑定与概率来源;未更改宽文件、数据或运行身份检查(06-14)。发起评估前请勾选。'));
            const launchBtn = WB().h('button', {
                class: 'wb-btn wb-btn-primary' + (uqRunning ? ' disabled' : ''),
                onclick: async () => {
                    if (uqRunning) return;
                    if (!confirmChk.checked) { toast('请先勾选「本次完整数据确认」(06-14)', 'error'); return; }
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
        /** 状态应用(SSE chg负载与 /status 响应同构 {task, logTail}):SSE活跃期间零status轮询XHR */
        function applyData(d) {
            const prev = state.task ? state.task.status : null;
            const prevUq = state.task ? state.task.uqStatus : null;
            if (d && (d.success || d.code === 200) && d.data && d.data.task) {
                state.task = d.data.task;
                if (Array.isArray(d.data.logTail) && d.data.logTail.length) state.log = d.data.logTail;
            }
            // 准备/执行结束一次性提示:运行态→终态跃迁时弹窗,覆盖确认失败(READY+message)
            // 与建模失败(RUNNING→FAILED)两类静默场景;终态后轮询自停,不会重复弹
            const RUN_ST = ['PREPARING', 'RUNNING', 'STOP_REQUESTED'];
            if (prev && RUN_ST.includes(prev) && state.task && !RUN_ST.includes(state.task.status)) {
                const st2 = state.task.status, msg = state.task.message || '';
                if (st2 === 'FAILED') toast('建模执行失败: ' + msg, 'error');
                else if (st2 === 'READY' && msg.indexOf('失败') >= 0) toast(msg, 'error');
                else if (st2 === 'READY' && state.task.prepMessage) toast(state.task.prepMessage, 'success');
                else if (st2 === 'COMPLETED') toast('任务已完成', 'success');
                else if (st2 === 'STOPPED') toast('已安全停止', 'info');
            }
            // UQ执行态→终态跃迁:停轮询回到结果/重发视图(与稳态飞参页同一修复口径)
            const UQ_RUN = ['EXECUTING', 'PREPARING'];
            if (prevUq && UQ_RUN.includes(prevUq) && state.task && !UQ_RUN.includes(state.task.uqStatus)) {
                const ns = state.task.uqStatus;
                if (ns === 'COMPLETED') toast('UQ评估完成;结果另存,不覆盖确定性估计值', 'success');
                else toast('UQ评估已中断/失败: ' + String(state.task.uqMessage || '详见日志').slice(0, 80), 'error');
                stopPolling();
            }
            const uqRun = state.task && UQ_RUN.includes(state.task.uqStatus);
            if (running(state.task) || uqRun) window.__WB_ENGINE_POLL_UNTIL__ = Date.now() + 40000;
            else if ((window.__WB_ENGINE_POLL_UNTIL__ || 0) < Date.now()) stopPolling();
            renderBody();
        }
        function poll() {
            const t = state.task;
            if (!t) return;
            const uqRun = t.uqStatus === 'EXECUTING' || t.uqStatus === 'PREPARING';
            if (!running(t) && !uqRun && (window.__WB_ENGINE_POLL_UNTIL__ || 0) < Date.now()) return;
            if (uqRun) window.__WB_ENGINE_POLL_UNTIL__ = Date.now() + 40000;
            window.AppConfig.engineGet('projects/' + encodeURIComponent(ctx.project.id) + '/tasks/'
                + encodeURIComponent(t.id) + '/status')
                .then(resp => applyData(resp)).catch(() => { });
        }
        function startPolling() {
            window.__WB_ENGINE_POLL_UNTIL__ = Date.now() + 40000;
            if (state.es) return;
            // SSE与轮询互斥:断链兜底定时器残留时重建SSE,必须先退掉定时器,
            // 否则SSE活跃期间5s /status轮询永久并存
            if (state.timer) { clearInterval(state.timer); state.timer = null; }
            // SSE 通知流为主:chg负载直接渲染(不再回拉status);失败回退5s定时轮询
            try {
                const cfg0 = window.AppConfig;
                const url = cfg0.api.baseURL + '/api/engine/projects/' + encodeURIComponent(ctx.project.id || '')
                    + '/tasks/' + encodeURIComponent(state.task.id) + '/stream?token=' + encodeURIComponent(cfg0.getToken() || '');
                const es = new EventSource(url);
                state.es = es;
                es.addEventListener('chg', ev => {
                    window.__WB_ENGINE_POLL_UNTIL__ = Date.now() + 40000;
                    try {
                        const d = JSON.parse(ev.data);
                        // 服务端task流负载为裸{task,logTail};补成/status同构信封再应用
                        applyData(d && d.task ? { code: 200, data: d } : d);
                    } catch (e) { poll(); }
                });
                es.addEventListener('end', () => { try { es.close(); } catch (e) { } state.es = null; });
                es.onerror = () => {
                    try { es.close(); } catch (e) { }
                    if (state.es === es) state.es = null;
                    if (!state.timer) state.timer = setInterval(poll, 5000);
                };
                poll();
                return;
            } catch (e) { /* 降级 */ }
            poll();
            state.timer = setInterval(poll, 5000);
        }
        function stopPolling() {
            if (state.timer) { clearInterval(state.timer); state.timer = null; }
            if (state.es) { try { state.es.close(); } catch (e) { } state.es = null; }
        }
        // 进入业务页固定显示新建视图;只有运行记录/项目概览指定 __WB_OPEN_TASK__ 时才打开既有任务
        // 页面切换时由 shell 调用,避免旧页轮询残留(跨页串状态通道)
        window.__WB_PAGE_STOP__ = stopPolling;

        renderBody();
        return root;
    }

    window.Workbench.renderFlightTask = taskPage;
    window.Workbench.renderEvolutionTask = renderEvolutionTask;
})();
