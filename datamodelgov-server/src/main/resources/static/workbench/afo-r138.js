/**
 * 多系统联合仿真(R138 版)—— 覆盖注册 Workbench.pages['testbench.afo']。
 * 依据:《多系统联合仿真界面需求规格说明书》UI-R138 V1.2 + 效果图 MS-01~MS-09 逐页对齐。
 *
 * 版式(对照效果图):
 *  - 页面大标题(总控与监视/发动机·全部登记输出/控制与负载·指令和响应/燃油·仅燃油系统代理模型/
 *    滑油·温度 流量 换热 通风/空气·八路质量流量 供气温度 供气压力);
 *  - 共享运行栏:大字状态+仿真 t/T+大百分比+横向进度条+右侧暂停/结束(继续)大按钮,第二行小字
 *    (最新采样/墙钟耗时单独计量/任务编号/发布与保存状态);
 *  - 固定 6 页签:总控/发动机/控制与负载/燃油/滑油/空气(结果与历史经页面与运行栏入口);
 *  - 图卡:标题左上、单位右上、横轴 t/s、图例在图下方、图区扁平;缩放滚轮,视图条"复位";
 *  - 总控:操纵区浅色横条两行 + 四图 2×2(轴速/燃油/负载功率/轴承腔出口油温℃);
 *  - 发动机常用两列六图,控制第六图为"当前输入命令·生效值阶梯",燃油 3×2(F06 状态条),
 *    滑油每图精选两条,空气三行两列同支路同色;各页底注;燃油/空气页签下 teal 提示行;
 *  - 自选工作区(MS-09):左侧通道树+右图+共同游标+"当前选中时刻"样本值表。
 *
 * 能力状态(R138 9/10章):后台 R065 已具备(MS-ALG-01~05);本页实现界面职责(MS-UI-01~03):
 * 增量曲线读 stream 样本块(不轮询最新值连线)、缺口/心跳/发布状态如实显示、111 项显示范围。
 */
(() => {
    const W = window.Workbench;
    const K = window.AfoKernel;
    if (!W || !K) return;
    const h = W.h, toast = W.toast;

    /* ================= 页面图组(对照效果图 MS-02~MS-07) ================= */
    const S_ = (id, o) => Object.assign({}, o, { id });
    const NP_DEM = '__np_dem';
    const CMD_STEP = '__cmd_step';
    // 常用视图(精选布局;name 为效果图图例短标)
    const COMMON_LAYOUT = {
        engine: {
            title: '发动机·全部登记输出',
            charts: [
                { t: '轴速', u: 'rpm', s: [S_('engine_09', { name: 'Np' }), S_('engine_10', { name: 'Ng' })] },
                // 总压/总温按1、3、4、45、5截面气路顺序(M7,规格4.2)
                { t: '截面总压', u: 'kPa', s: [S_('engine_01', { name: 'Pt1' }), S_('engine_03', { name: 'Pt3' }), S_('engine_17', { name: 'Pt4' }), S_('engine_05', { name: 'Pt45' }), S_('engine_07', { name: 'Pt5' })] },
                { t: '截面总温', u: 'K', s: [S_('engine_02', { name: 'Tt1' }), S_('engine_04', { name: 'Tt3' }), S_('engine_18', { name: 'Tt4' }), S_('engine_06', { name: 'Tt45' }), S_('engine_08', { name: 'Tt5' })] },
                { t: '主流量', u: 'kg/s', s: [S_('engine_11', { name: 'W2' })] },
                { t: '轴系力矩', u: 'N·m', s: [S_('engine_12', { name: 'PT驱动' }), S_('engine_19', { name: 'GT/HPC净' })] },
                { t: '工作点与诊断', u: '1', s: [S_('engine_13', { name: 'HPC换算转速' }), S_('engine_14', { name: 'GT压比' }), S_('engine_15', { name: 'PT压比' })] }
            ],
            footnote: '20项均可绘制 · 求解诊断(残差/收敛标志)在“全部分组”展开'
        },
        control: {
            title: '控制与负载·指令和响应',
            charts: [
                { t: 'Np目标与反馈', u: 'rpm', s: [S_(NP_DEM, { name: '目标', dash: true }), S_('engine_09', { name: '实际' })] },
                { t: '燃油响应', u: 'kg/s', s: [S_('fuel_command_01', { name: '控制指令' }), S_('fuel_engine_01', { name: '发动机采用' })] },
                { t: '负载扭矩', u: 'N·m', s: [S_('load_01', { name: 'Mkp' })] },
                { t: '负载功率', u: 'kW', s: [S_('load_05', { name: '实际负载' })] },
                { t: '等效桨距', u: 'deg', s: [S_('load_02', { name: '映射值' })] },
                { t: '当前输入命令', u: '挡位 %', s: [S_(CMD_STEP, { name: '生效值', step: true })] }
            ],
            footnote: '目标与生效值为配置及事件重建，反馈为原通道引用；未记录控制内部量不得填假曲线。'
        },
        fuel: {
            title: '燃油·仅燃油系统代理模型',
            notice: 'R065已采集10条连续量和2项状态。',
            cols: 2,
            charts: [
                { t: '计量流量与最终输出', u: 'kg/s', s: [S_('fuel_proxy_flow_before', { name: '切换前' }), S_('fuel_proxy_flow_after', { name: '切换后' }), S_('fuel_detailed_01', { name: '最终输出' })] },
                { t: '计量阀位跟踪', u: 'm', s: [S_('fuel_proxy_valve_demand', { name: '指令' }), S_('fuel_proxy_valve_actual', { name: '实际' })] },
                { t: '计量驱动电流', u: 'mA', s: [S_('fuel_proxy_current_before', { name: '限幅前' }), S_('fuel_proxy_current_after', { name: '限幅后' })] },
                { t: '计量面积', u: 'm²', s: [S_('fuel_proxy_area', { name: '查表输出' })] },
                { t: '计量压差代理', u: 'MPa', s: [S_('fuel_proxy_dp_before', { name: '输入' }), S_('fuel_proxy_dp_after', { name: '滤波后' })] },
                { t: '内部模式输入', state: [
                    { label: '计量闭锁', id: 'fuel_proxy_meter_lock', color: '#0e7490' },
                    { label: '停车切换', id: 'fuel_proxy_stop_switch', color: '#0369a1' }
                ] }
            ],
            footnote: '压差为模型代理量；内部停车开关不是“结束计算”，不增加操纵按钮。'
        },
        oil: {
            title: '滑油·温度 流量 换热 通风',
            charts: [
                { t: '轴承腔出口油温', u: '℃', s: [S_('oil09_01', { name: '甲腔' }), S_('oil10_01', { name: '乙腔' })] },
                { t: '供回油流量', u: 'm³/s', s: [S_('oil05_01', { name: '供油' }), S_('oil11_01', { name: '回油' })] },
                { t: '腔及换热器压力', u: 'kPa', s: [S_('oil17_01', { name: '入口' }), S_('oil18_01', { name: '出口' })] },
                { t: '换热与生热', u: 'kW', s: [S_('oil15_01', { name: '换热' }), S_('oil13_01', { name: '生热' })] },
                { t: '封严与通风', u: 'kg/s', s: [S_('oil22_01', { name: '甲前' }), S_('oil22_03', { name: '乙前' })] },
                { t: '质量残差', u: 'kg/s', s: [S_('oil26_01', { name: '甲腔' }), S_('oil26_02', { name: '乙腔' })] }
            ],
            footnote: '28个输出端口展开47项 · 输入边界不展示 · 温度原单位逐项核对'
        },
        air: {
            title: '空气·八路质量流量 供气温度 供气压力',
            notice: 'R065已采集24项；回灌关闭仍计算。温压为保护前供气边界状态。',
            footnote: '每图一个支路(温度/压力同源)，支路可单独显隐。界面不展示模板、合并或延迟副本。原空气选择器第10输入未接线等历史限制保留。'
        }
    };
    // 全部分组(展开其余通道;名称取自字典)
    const GROUPS_ALL = {
        engine: [
            { t: '轴速', charts: [[{ id: 'engine_09' }, { id: 'engine_10' }]], note: 'Np与Ng同轴rpm' },
            { t: '总压(全截面)', charts: [[{ id: 'engine_01' }, { id: 'engine_03' }, { id: 'engine_17' }, { id: 'engine_05' }, { id: 'engine_07' }]], note: '按1/3/4/45/5截面气路顺序;Pa可显示kPa' },
            { t: '总温(全截面)', charts: [[{ id: 'engine_02' }, { id: 'engine_04' }, { id: 'engine_18' }, { id: 'engine_06' }, { id: 'engine_08' }]], note: '按1/3/4/45/5截面气路顺序;默认K' },
            { t: '主流量', charts: [[{ id: 'engine_11' }]], note: 'W2,kg/s' },
            { t: '轴系力矩(含负载引用)', charts: [[{ id: 'engine_12' }, { id: 'engine_19' }, { id: 'load_01', dash: true }]], note: 'PT驱动力矩≠负载Mkp;load_01为跨页引用' },
            { t: '工作点', charts: [[{ id: 'engine_13' }], [{ id: 'engine_14' }, { id: 'engine_15' }]], note: 'HPC相对换算转速与GT/PT压比分别标明' },
            { t: '求解诊断', charts: [[{ id: 'engine_16' }], [{ id: 'engine_20', step: true }]], note: '残差保留正负;收敛标志按模型定义解释' }
        ],
        control: [
            { t: '调速响应', charts: [[{ id: NP_DEM, dash: true }, { id: 'engine_09' }, { id: 'engine_10' }]], note: 'Np目标为配置及事件重建' },
            { t: '燃油对照', charts: [[{ id: 'fuel_command_01' }, { id: 'fuel_engine_01' }]], note: '采集分组fuel,显示分组control' },
            { t: '负载扭矩', charts: [[{ id: 'load_01' }]], note: '外部负载边界' },
            { t: '负载功率', charts: [[{ id: 'load_05' }]], note: 'W可显示kW' },
            { t: '等效桨距与桨距系数', charts: [[{ id: 'load_02' }], [{ id: 'load_03' }]], note: '扭矩模式下可合法不适用' },
            { t: '转速比与范围', charts: [[{ id: 'load_04' }], [{ id: 'load_06', step: true }]], note: '范围标志为状态带' },
            { t: '操纵记录', events: true, note: '使用实际生效时刻,非模型输出' }
        ],
        fuel: [
            { t: '计量流量与最终输出', charts: [[{ id: 'fuel_proxy_flow_before' }, { id: 'fuel_proxy_flow_after' }, { id: 'fuel_detailed_01' }]], note: '切换后尚有最终动态,不与最终输出合并' },
            { t: '计量阀位跟踪', charts: [[{ id: 'fuel_proxy_valve_demand' }, { id: 'fuel_proxy_valve_actual' }]], note: '不是发动机导叶角' },
            { t: '计量驱动电流', charts: [[{ id: 'fuel_proxy_current_before' }, { id: 'fuel_proxy_current_after' }]], note: '限幅前/后' },
            { t: '计量面积', charts: [[{ id: 'fuel_proxy_area' }]], note: '查表输出' },
            { t: '计量压差代理', charts: [[{ id: 'fuel_proxy_dp_before' }, { id: 'fuel_proxy_dp_after' }]], note: '常值是合法结果,不得人为加波动' },
            { t: '内部模式输入', state: [
                { label: '计量闭锁', id: 'fuel_proxy_meter_lock', color: '#0e7490' },
                { label: '停车切换', id: 'fuel_proxy_stop_switch', color: '#0369a1' }
            ], note: '0正常变化率/1固定负向变化率;1送零流量,最终输出有动态滞后' }
        ],
        oil: [
            { t: '温度', charts: [[{ id: 'oil09_01' }, { id: 'oil10_01' }], [{ id: 'oil27_01' }, { id: 'oil28_01' }], [{ id: 'oil16_01' }]], note: 'K与℃分图;oil16_01单位未确认单独原值' },
            { t: '供回油流量', charts: [[{ id: 'oil05_01' }, { id: 'oil06_01' }, { id: 'oil11_01' }, { id: 'oil12_01' }]], note: 'm³/s可转换L/min,不当kg/s' },
            { t: '腔与换热器压力', charts: [[{ id: 'oil07_01' }, { id: 'oil08_01' }], [{ id: 'oil17_01' }, { id: 'oil18_01' }, { id: 'oil19_01' }, { id: 'oil20_01' }]], note: 'Pa/kPa' },
            { t: '生热换热', charts: [[{ id: 'oil01_01' }, { id: 'oil02_01' }, { id: 'oil03_01' }, { id: 'oil04_01' }], [{ id: 'oil13_01' }, { id: 'oil14_01' }, { id: 'oil15_01' }], [{ id: 'oil27_02' }, { id: 'oil28_02' }]], note: 'W与kW统一后同图;相近名称不合并' },
            { t: '封严通风', charts: [[{ id: 'oil21_01' }, { id: 'oil21_03' }, { id: 'oil21_05' }, { id: 'oil21_07' }], [{ id: 'oil21_02' }, { id: 'oil21_04' }, { id: 'oil21_06' }, { id: 'oil21_08' }], [{ id: 'oil22_01' }, { id: 'oil22_02' }, { id: 'oil22_03' }, { id: 'oil22_04' }], [{ id: 'oil23_01' }, { id: 'oil23_02' }, { id: 'oil23_03' }], [{ id: 'oil24_01' }, { id: 'oil24_02' }, { id: 'oil24_03' }, { id: 'oil24_04' }], [{ id: 'oil25_01' }, { id: 'oil25_02' }]], note: '压力/温度/封严流量/排气/封严压差/排气压差分图(M4)' },
            { t: '守恒诊断', charts: [[{ id: 'oil26_01' }, { id: 'oil26_02' }]], note: '质量残差保留正负' }
        ]
    };
    // 空气:三行两列(效果图 MS-07)
    const AIR_BRANCH = ['G01', 'G02', 'G03', 'G04', 'G05', 'G06', 'G07', 'G08'];
    const AIR_ROWS = [
        { title: '质量流量', unit: 'kg/s', ids: ['air01_01', 'air02_01', 'air03_01', 'air04_01', 'air05_01', 'air06_01', 'air07_01', 'air08_01'] },
        { title: '供气温度', unit: 'K', ids: ['air_g01_temperature', 'air_g02_temperature', 'air_g03_temperature', 'air09_01', 'air_g05_temperature', 'air_g06_temperature', 'air_g07_temperature', 'air_g08_temperature'] },
        { title: '供气压力', unit: 'kPa', ids: ['air_g01_pressure', 'air_g02_pressure', 'air_g03_pressure', 'air10_01', 'air_g05_pressure', 'air_g06_pressure', 'air_g07_pressure', 'air_g08_pressure'] }
    ];
    const AIR_BRANCH_COLOR = ['#0e7490', '#0369a1', '#d97706', '#7c3aed', '#0f766e', '#1d4ed8', '#b45309', '#6d28d9'];
    const SYS_TITLE = { engine: '发动机', control: '控制与负载', fuel: '燃油代理', oil: '滑油', air: '空气' };

    /* ================= 页面 ================= */
    W.pages['testbench.afo'] = (ctx) => {
        const pid = ctx.project.id || '';
        const api = (p, params) => window.AppConfig.engineGet('projects/' + encodeURIComponent(pid) + '/afo' + p, params);
        const apiPost = (p, body) => window.AppConfig.enginePost('projects/' + encodeURIComponent(pid) + '/afo' + p, body || {});

        const S = window.__WB_AFO__ = window.__WB_AFO__ || {
            phase: 'IDLE', message: '', error: '', live: null, result: null,
            readonlyRunId: null, readonlyLoading: false,
            cfg: {
                engineId: ctx.project.engineId || 'ENGINE-001', runId: '',
                duration: '30', recordStep: '0.1', pace: 'realtime',
                loadMode: 'power', powerKw: '2176.6', mkpNm: '1000', pitchDeg: '12',
                mainPitchDeg: '12', tailPitchDeg: '10', externalAir: false, npRatio: '1',
                tailToMainPowerRatio: '0.10', tailDesignPitchDeg: '10', // 双总距固定映射参数(规格3.1)
                publishLive: true, initialTransitionConfirmed: false
            },
            cfgFrozen: null,
            catalog: null, catalogHash: null, sessionId: null,
            byId: null, dispIds: null, dispPos: null,
            liveBuf: null, liveCols: null, liveErr: '', gapNotice: '', gapRetries: 0,
            tab: 'main', viewMode: 'common', custom: [], customSel: [],
            airHide: {}, airBranch: -1, treeCollapsed: false, // airBranch>=0为单支路三图查看(M5);树折叠态(L6)
            follow: true, followDirty: false, windowPreset: '30s', conv: true, // followDirty:关跟随后有新样本(L2)
            compare: null, compareOverlay: false,
            localResume: false, connLost: false, pauseReqAt: null, // 暂停请求提交时刻(30s延迟提示,L3)
            procLost: false, statusOutputDir: null, // D8:心跳长期停止判定"该实例不能续算";D12:会话输出目录(只读)
            applyBusy: false, lastSubmit: null, // 规格3.3:物理输入在途提交/最近提交回执(仅桥接显示,生效仍以applied为准)
            es: null, streamMode: '', pullTimer: null,
        };
        S.tab = S.tab || 'main';

        /* ---------- 显示配置另存(不改原始数值) ---------- */
        const dispKey = () => 'afo_disp::' + pid + '::' + (S.readonlyRunId || (S.live && S.live.runId) || 'draft');
        let dispTimer = null;
        const saveDisp = () => {
            clearTimeout(dispTimer);
            dispTimer = setTimeout(() => {
                try {
                    localStorage.setItem(dispKey(), JSON.stringify({
                        viewMode: S.viewMode, custom: S.custom, windowPreset: S.windowPreset,
                        follow: S.follow, conv: S.conv, airHide: S.airHide, treeCollapsed: S.treeCollapsed
                    }));
                } catch (e) { /* 忽略 */ }
            }, 400);
        };
        function loadDisp() {
            try {
                const d = JSON.parse(localStorage.getItem(dispKey()) || 'null');
                if (d) {
                    S.viewMode = d.viewMode || 'common';
                    S.custom = Array.isArray(d.custom) ? d.custom : [];
                    S.windowPreset = d.windowPreset || '30s';
                    S.follow = d.follow !== false;
                    S.conv = d.conv !== false;
                    S.airHide = d.airHide || {};
                    S.treeCollapsed = !!d.treeCollapsed;
                }
            } catch (e) { /* 忽略 */ }
        }

        /* ---------- 目录加载 ---------- */
        async function loadCatalog(attempt) {
            attempt = attempt || 1;
            let cat = null, hash = null, sid = null;
            if (!S.readonlyRunId) {
                // 只读回看不用当前活动会话的通道目录,统一走结果自带目录
                try {
                    const resp = await api('/channels');
                    if (resp && (resp.success || resp.code === 200) && resp.data && Array.isArray(resp.data.channels)) {
                        cat = resp.data.channels; hash = resp.data.channelCatalogHash || null; sid = resp.data.sessionId || null;
                        S.catalogErr = '';
                    } else {
                        S.catalogErr = (resp && resp.message) || '通道字典返回为空';
                    }
                } catch (e) {
                    // 准备阶段channels.json可能尚未写出:重试几次再报错,不能静默吞掉(否则运行期全图"未在字典中")
                    S.catalogErr = e.message || String(e);
                }
            }
            if (!cat && S.result) {
                if (Array.isArray(S.result.catalog)) { cat = S.result.catalog; hash = S.result.channelCatalogHash || null; sid = S.result.sessionId || null; }
                else if (Array.isArray(S.result.channels)) cat = specToCatalog(S.result.channels);
            }
            if (!cat) {
                if (attempt < 4 && !S.readonlyRunId && !S._catBusyRetry) {
                    S._catBusyRetry = true;
                    setTimeout(() => { S._catBusyRetry = false; loadCatalog(attempt + 1).then(ok => { if (ok) renderAll(); }); }, 1200);
                } else if (attempt >= 4) {
                    console.warn('通道字典加载失败:', S.catalogErr);
                }
                return false;
            }
            S.catalog = cat; S.catalogHash = hash;
            if (sid && !S.sessionId) S.sessionId = sid;
            const byId = {}, dispIds = [], dispPos = [];
            cat.forEach((c, pos) => {
                byId[c.id] = Object.assign({ _pos: pos }, c);
                if (c.display) { dispIds.push(c.id); dispPos.push(pos); }
            });
            S.byId = byId; S.dispIds = dispIds; S.dispPos = dispPos;
            if (!S.liveBuf) S.liveBuf = K.LiveBuffer();
            if (!S.liveCols) S.liveCols = dispPos.slice();
            return true;
        }
        function specToCatalog(specs) {
            const out = [];
            (specs || []).forEach(spec => (spec.names || []).forEach((nm, j) => {
                const isFlat = /^fuel_proxy_|^air_g/.test(spec.id);
                const id = isFlat ? spec.id : spec.id + '_' + String(j + 1).padStart(2, '0');
                const pnl = panelOf(id);
                out.push({
                    id, group: spec.group, name: nm, unit: (spec.units || [])[j] || '',
                    source: spec.sid + ':' + spec.port, role: spec.role || '',
                    display: !!pnl, displayGroup: pnl ? PANEL_SYS[pnl] : '',
                    panel: pnl, physicalDefinition: nm,
                    availability: /unconfirmed|未确认/.test(String((spec.units || [])[j] || '')) ? 'unit_unconfirmed' : 'recorded'
                });
            }));
            return out;
        }
        const chById = id => (S.byId || {})[id] || null;
        const PANEL_SYS = { E01: 'engine', E02: 'engine', E03: 'engine', E04: 'engine', E05: 'engine', E06: 'engine', E07: 'engine', C01: 'control', C02: 'control', C03: 'control', C04: 'control', C05: 'control', C06: 'control', C07: 'control', F01: 'fuel', F02: 'fuel', F03: 'fuel', F04: 'fuel', F05: 'fuel', F06: 'fuel', O01: 'oil', O02: 'oil', O03: 'oil', O04: 'oil', O05: 'oil', O06: 'oil', A01: 'air', A02: 'air', A03: 'air' };
        function panelOf(id) {
            for (const sys of Object.keys(COMMON_LAYOUT)) {
                for (const c of COMMON_LAYOUT[sys].charts || []) {
                    for (const d of c.s || []) if (d.id === id) return PANEL_SYS[firstPanelOf(sys)];
                    for (const r of c.state || []) if (r.id === id) return PANEL_SYS[firstPanelOf(sys)];
                }
            }
            for (const arr of AIR_ROWS) { const i = arr.ids.indexOf(id); if (i >= 0) return ['A01', 'A02', 'A03'][AIR_ROWS.indexOf(arr)]; }
            for (const sys of Object.keys(GROUPS_ALL)) {
                for (const g of GROUPS_ALL[sys]) {
                    for (const ch of g.charts || []) for (const d of ch) if (d.id === id) return PANEL_SYS[firstPanelOf(sys)];
                    for (const r of g.state || []) if (r.id === id) return PANEL_SYS[firstPanelOf(sys)];
                }
            }
            return '';
        }
        const FIRST_PANEL = { engine: 'E01', control: 'C01', fuel: 'F01', oil: 'O01', air: 'A01' };
        const firstPanelOf = sys => FIRST_PANEL[sys];

        /* ---------- 数值访问 ---------- */
        function resultAccessor(result) {
            let vals = (result && result.values) || [];
            if (vals.length === 1 && Array.isArray(vals[0]) && Array.isArray(vals[0][0])) vals = vals[0];
            const time = (result && result.time) || [];
            const n = time.length;
            // 组×时刻展平(列优先,MATLAB jsonencode 常见):长度 = 组数×时刻数,远大于时刻数
            const colMajor = n > 0 && vals.length > n;
            const idx = {};
            (result.channels || []).forEach((spec, gi) => {
                if (Array.isArray(spec.names) && spec.names.length) {
                    // 分组spec(正常result.json):通道id = spec.id_NNN,fuel_proxy_/air_g_用spec.id本身
                    const isFlat = /^fuel_proxy_|^air_g/.test(spec.id);
                    spec.names.forEach((nm, j) => {
                        const id = isFlat ? spec.id : spec.id + '_' + String(j + 1).padStart(2, '0');
                        idx[id] = { gi, j };
                    });
                } else if (spec.id) {
                    // 平铺spec(失败会话合成结果,每spec单值):id即通道
                    idx[spec.id] = { gi, j: 0 };
                }
            });
            // 单通道组(names只有1项)在result.json里被jsonencode降维成标量(不是数组),
            // 必须按标量取该组唯一值,否则所有单通道量(燃油/滑油/空气/控制燃油等)全读成null
            const pick = (g, j) => {
                if (g == null) return null;
                if (typeof g === 'number') return j === 0 ? g : null;
                if (!Array.isArray(g)) return null;
                const x = g[j];
                return x == null ? null : x;
            };
            return {
                time,
                has: id => !!idx[id],
                series(id) {
                    const m = idx[id];
                    const out = new Array(n).fill(null);
                    if (!m) return out;
                    for (let i = 0; i < n; i++) {
                        if (colMajor) out[i] = pick(vals[i + m.gi * n], m.j);
                        else { const row = vals[i]; out[i] = pick(row ? row[m.gi] : null, m.j); }
                    }
                    return out;
                }
            };
        }
        let resultAcc = null;
        const refreshAcc = () => { resultAcc = S.result ? resultAccessor(S.result) : null; };
        function liveSeries(id) {
            const c = chById(id);
            if (!c || !S.liveBuf) return { time: [], v: [] };
            const col = S.liveBuf.series(c._pos);
            return { time: S.liveBuf.time, v: col.v.map((x, i) => (col.q[i] === 2 ? null : x)) };
        }
        function valueAt(id, t) {
            // 游标时刻样本值(取 ≤t 的最近样本);返回原始值
            const c = chById(id);
            if (!c) return null;
            let time, v;
            if (isResultMode() && resultAcc) {
                if (!resultAcc.has(id)) return undefined; // 未记录
                time = resultAcc.time; v = resultAcc.series(id);
            } else if (S.liveBuf && S.liveBuf.count()) {
                const col = S.liveBuf.series(c._pos);
                time = S.liveBuf.time; v = col.v;
            } else return null;
            if (!time.length) return null;
            let lo = 0, hi = time.length;
            while (lo < hi) { const m = (lo + hi) >> 1; if ((time[m] == null ? -1 : time[m]) <= t) lo = m + 1; else hi = m; }
            const i = lo - 1;
            return i < 0 ? null : v[i];
        }
        /* ---------- 质量状态(L7,规格5.4) ----------
         * quality码:0有效 1非有限(缓冲区为null,经断线/null断带自然可见) 2不适用(liveSeries置null断线)
         * 3单位未确认(图例/纵轴标签追加"(单位未确认)")。单位未确认按通道availability标记判定。 */
        const qualName = id => {
            const c = chById(id);
            if (c && (c.availability === 'unit_unconfirmed' || Number(c.quality) === 3
                || (c.unit && /unconfirmed|未确认/.test(String(c.unit))))) {
                return (c.name || id) + '(单位未确认)';
            }
            return (c && c.name) || id;
        };

        /* ---------- 状态与命令 ---------- */
        function uiState() {
            if (S.readonlyRunId) return S.readonlyFailed ? 'FAILED' : 'READONLY';
            const st = S.live || {};
            const ph = S.phase;
            if (ph === 'PREPARING') return 'PREPARING';
            if (ph === 'READY') return 'READY';
            if (ph === 'ENDED') return st.saveState === 'failed' ? 'SAVE_FAILED' : 'ENDED';
            if (ph === 'FAILED') return 'FAILED';
            if (ph === 'RUNNING' || ph === 'PAUSED') {
                if (st.stopRequested) return 'STOP_REQ';
                if (st.state === 'paused') return S.localResume ? 'RESUME_REQ' : 'PAUSED';
                if (st.state === 'running') return st.pauseRequested ? 'PAUSE_REQ' : 'RUNNING';
                return 'RUNNING';
            }
            return S.message && /失败/.test(S.message) ? 'VALIDATE_FAILED' : 'IDLE';
        }
        const runningLike = () => ['RUNNING', 'PAUSE_REQ', 'PAUSED', 'RESUME_REQ', 'STOP_REQ'].includes(uiState());
        const canCmdPhysics = () => ['RUNNING', 'PAUSED'].includes(uiState());
        /** 暂停/继续族状态:这些迁移只做就地补丁,不重建主面板/图表。 */
        const isPauseUi = u => ['RUNNING', 'PAUSE_REQ', 'PAUSED', 'RESUME_REQ'].includes(u);
        /** 运行中但还没收到任何样本:sim() 正在编译/初始化模型,不是"计算中"。 */
        const isCompiling = () => uiState() === 'RUNNING' && !(
            (S.liveBuf && S.liveBuf.time && S.liveBuf.time.length > 0)
            || (((S.live || {}).currentSimulationTime || 0) > 0));
        const isResultMode = () => !!S.result && ['ENDED', 'READONLY', 'FAILED', 'SAVE_FAILED'].includes(uiState());
        const fmtT = t => (t == null || isNaN(t)) ? '—' : Number(t).toFixed(3) + ' s';
        function loadMode() {
            // D2:负载模式以冻结配置为准(服务端恢复),避免运行中刷新后按错误量纲换算
            return (S.cfgFrozen && S.cfgFrozen.loadMode) || (S.result && S.result.config && S.result.config.loadMode) || S.cfg.loadMode;
        }
        function cmdText(ev) {
            const v = ev.value, lm = loadMode();
            switch (ev.kind) {
                case 'np': return 'Np → ' + Math.round(parseFloat(v) * 100) + '%';
                case 'load':
                    return lm === 'power' ? 'PT功率 → ' + (Number(v) / 1000).toFixed(2) + ' kW'
                        : lm === 'torque' ? '扭矩 → ' + Number(v).toFixed(1) + ' N·m'
                        : lm === 'pitch' ? '总距角 → ' + Number(v).toFixed(2) + '°'
                        : '主/尾桨 → ' + (Array.isArray(v) ? v.map(x => Number(x).toFixed(1) + '°').join(' / ') : v);
                case 'pause': return '暂停';
                case 'resume': return '继续';
                case 'stop': return '结束计算';
                default: return ev.kind + ' ' + JSON.stringify(v);
            }
        }
        function evState(ev) {
            if (ev.status === 'applied') return ['已生效 ' + fmtT(ev.appliedTime), 'teal'];
            if (ev.status === 'accepted') {
                // L4(规格3.3):暂停期间提交的物理输入,发动机未推进,继续后才施加,不显示"待生效"
                if ((ev.kind === 'np' || ev.kind === 'load') && uiState() === 'PAUSED') return ['已接受，继续后施加', 'amber'];
                return ['已接受，待生效', 'amber'];
            }
            if (ev.status === 'not_applied') return ['未施加，运行已结束', 'gray'];
            if (ev.status === 'failed') return ['失败:' + (ev.reason || ''), 'red'];
            if (ev.status === 'rejected') return ['已回退:' + (ev.reason || ''), 'red'];
            return [ev.status || '—', 'gray'];
        }
        // MATLAB jsonencode 会把单元素struct数组编码成对象而非数组;这里统一规范成数组
        const asArr = x => Array.isArray(x) ? x : (x && typeof x === 'object' ? [x] : []);
        const eventsList = () => {
            const re = asArr(S.result && S.result.events);
            return re.length ? re : asArr((S.live || {}).events);
        };
        function eventsTable() {
            const events = eventsList();
            if (!events.length) return h('div', { class: 'wb-hint' }, '本次运行无在线操纵(初始配置见准备记录)。');
            const tbl = h('table', { class: 'wb-table' },
                h('tr', null, ['提交编号', '操纵内容', '接收时刻', '生效时刻', '状态'].map(x => h('th', null, x))));
            events.forEach(ev => {
                const st = evState(ev);
                tbl.appendChild(h('tr', null,
                    h('td', { class: 'wb-hint' }, ev.id || '—'),
                    h('td', null, cmdText(ev)),
                    h('td', { class: 'wb-hint' }, fmtT(ev.acceptedTime)),
                    h('td', { class: 'wb-hint' }, fmtT(ev.appliedTime)),
                    h('td', null, h('span', { class: 'wb-tag wb-tag-' + st[1] }, st[0]))));
            });
            return tbl;
        }
        function appliedMarks() {
            return eventsList().filter(ev => ev.status === 'applied' && ev.appliedTime != null && ['np', 'load'].includes(ev.kind))
                .map(ev => ({ t: ev.appliedTime, label: cmdText(ev) }));
        }

        /* ---------- 失败原因:悬停预览 + 点击查看完整日志 ---------- */
        let failTipEl = null;
        /** 失败原因:Java会话error(完整报告) > 实时流error > 只读结果error > stopReason;
         *  旧版本会话的"原因未记录"占位文案不展示(用户已否决该措辞)。 */
        function failReasonText() {
            const cands = [
                S.error,
                S.live && S.live.error,
                S.result && S.result.error,
                S.result && S.result.state === 'failed' && S.result.stopReason,
                S.live && S.live.state === 'failed' && S.live.stopReason
            ];
            for (const c of cands) {
                const t = String(c == null ? '' : c).trim();
                if (t && !t.startsWith('原因未记录')) return t;
            }
            return '';
        }
        function hideFailTip() {
            if (failTipEl && failTipEl.parentNode) failTipEl.parentNode.removeChild(failTipEl);
            failTipEl = null;
            window.removeEventListener('scroll', hideFailTip, true);
            window.removeEventListener('resize', hideFailTip);
        }
        /** 悬停预览:最多4行/200字,超出以省略提示结尾;完整日志走点击弹窗。 */
        function showFailTip(anchor, text) {
            hideFailTip();
            const src = String(text);
            const lines = src.split(/\r?\n/);
            const MAX_LINES = 4, MAX_CHARS = 200;
            let preview = '', used = 0, cut = false;
            for (let i = 0; i < lines.length && i < MAX_LINES; i++) {
                const room = MAX_CHARS - used;
                let line = lines[i];
                if (line.length > room) { line = line.slice(0, Math.max(0, room)); cut = true; }
                preview += (i ? '\n' : '') + line;
                used += line.length;
                if (cut || used >= MAX_CHARS) { cut = true; break; }
            }
            if (lines.length > MAX_LINES || used >= MAX_CHARS) cut = true;
            const tip = h('div', {
                style: 'position:fixed;z-index:99990;visibility:hidden;pointer-events:none;max-width:min(560px,calc(100vw - 24px));'
                    + 'background:#fff;border:1px solid #e5e7eb;border-radius:8px;padding:9px 12px;'
                    + 'box-shadow:0 8px 28px rgba(15,23,42,.18);font-size:12px;line-height:1.55;color:#334155'
            });
            tip.appendChild(h('div', { style: 'max-height:80px;overflow:hidden;white-space:pre-wrap;overflow-wrap:anywhere;word-break:break-all' }, preview));
            if (cut) tip.appendChild(h('div', { style: 'margin-top:4px;font-size:11px;color:#64748b' }, '…点击查看完整日志'));
            document.body.appendChild(tip);
            // 默认在文本下方;视口下方放不下则翻到上方,左右也夹在可视区内
            const r = anchor.getBoundingClientRect();
            const vw = window.innerWidth || document.documentElement.clientWidth;
            const vh = window.innerHeight || document.documentElement.clientHeight;
            const w = tip.offsetWidth, ht = tip.offsetHeight;
            let left = r.left, top = r.bottom + 6;
            if (top + ht > vh - 8) top = r.top - ht - 6;
            if (top < 8) top = 8;
            if (left + w > vw - 8) left = vw - w - 8;
            if (left < 8) left = 8;
            tip.style.left = left + 'px'; tip.style.top = top + 'px'; tip.style.visibility = 'visible';
            failTipEl = tip;
            // 浮窗跟随文本位置:页面滚动/尺寸变化时直接收起,避免停留在旧位置
            window.addEventListener('scroll', hideFailTip, true);
            window.addEventListener('resize', hideFailTip);
        }
        /** 完整失败日志弹窗:沿用工作台 wb-card/遮罩风格;支持滚动、选中复制、ESC/遮罩关闭。 */
        function openFailLogModal(text) {
            hideFailTip();
            const full = String(text);
            const truncated = /报告过长已截断/.test(full);
            let closed = false;
            const prevOverflow = document.body.style.overflow;
            const onKey = e => {
                if (e.key === 'Escape' || e.key === 'Esc') { e.preventDefault(); e.stopPropagation(); close(); }
            };
            const fallbackCopy = t => {
                try {
                    const ta = document.createElement('textarea');
                    ta.value = t; ta.style.position = 'fixed'; ta.style.left = '-9999px'; ta.style.opacity = '0';
                    document.body.appendChild(ta); ta.select();
                    const ok = document.execCommand && document.execCommand('copy');
                    document.body.removeChild(ta);
                    return !!ok;
                } catch (e) { return false; }
            };
            const copy = () => {
                const done = ok => toast(ok ? '日志已复制' : '复制失败，请手动选中日志复制', ok ? 'success' : 'error');
                if (navigator.clipboard && navigator.clipboard.writeText) {
                    navigator.clipboard.writeText(full).then(() => done(true), () => done(fallbackCopy(full)));
                } else done(fallbackCopy(full));
            };
            const close = () => {
                if (closed) return;
                closed = true;
                document.body.style.overflow = prevOverflow;
                document.removeEventListener('keydown', onKey, true);
                if (mask.parentNode) mask.parentNode.removeChild(mask);
            };
            const mask = h('div', { style: 'position:fixed;inset:0;background:rgba(15,23,42,.45);z-index:99998;display:flex;align-items:center;justify-content:center;padding:24px' });
            mask.addEventListener('mousedown', e => { if (e.target === mask) close(); });
            mask.appendChild(h('div', { class: 'wb-card', style: 'max-width:760px;width:100%;max-height:calc(100vh - 48px);display:flex;flex-direction:column;box-shadow:0 12px 40px rgba(0,0,0,.28)' },
                h('div', { class: 'wb-section-title', style: 'margin-bottom:10px' }, '计算失败日志'),
                h('div', { style: 'max-height:60vh;overflow:auto;overscroll-behavior:contain;background:#f8fafc;border:1px solid #e2e8f0;border-radius:6px;padding:10px 12px;font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:12px;line-height:1.6;color:#334155;white-space:pre-wrap;overflow-wrap:anywhere;word-break:break-all;user-select:text' }, full),
                truncated ? h('div', { style: 'margin-top:6px;font-size:12px;color:#b45309' }, '日志过长已截断，完整内容见服务端 error-report.txt') : null,
                h('div', { class: 'wb-actions-row', style: 'margin-top:14px;justify-content:flex-end' },
                    h('button', { class: 'wb-btn wb-btn-outline', onclick: copy }, '复制日志'),
                    h('button', { class: 'wb-btn wb-btn-primary', onclick: close }, '关闭'))));
            document.body.appendChild(mask);
            document.body.style.overflow = 'hidden'; // 弹窗期间滚轮只滚日志,不滚背景页面
            document.addEventListener('keydown', onKey, true);
        }

        /* ---------- 共享运行栏(效果图:大字状态+仿真t/T+大百分比+进度条+大按钮) ---------- */
        function runBar() {
            const ui = uiState();
            const live = S.live || {};
            const stMap = {
                RUNNING: ['计算中', 'teal'], PAUSE_REQ: ['暂停请求中', 'amber'], PAUSED: ['已暂停', 'amber'],
                RESUME_REQ: ['继续请求中', 'amber'], STOP_REQ: ['结束请求中', 'amber'],
                READY: ['已就绪', 'teal'], PREPARING: ['准备中', 'gray'], ENDED: ['计算结束', 'gray'],
                FAILED: ['计算失败', 'red'], SAVE_FAILED: ['保存失败', 'red'], READONLY: ['历史只读', 'gray']
            };
            // 运行栏状态:sim()编译/初始化期(尚无首帧样本)单独标注,不宣称"计算中"
            const compiling = ui === 'RUNNING' && isCompiling();
            const meta = compiling ? ['模型编译初始化中', 'amber'] : (stMap[ui] || ['空闲', 'gray']);
            const curT = typeof live.currentSimulationTime === 'number' ? live.currentSimulationTime
                : (S.result ? S.result.finalSimulationTime || 0 : 0);
            // D2/D3:进度分母优先用服务端 status.json 的 duration/progress(刷新/重开不回落默认配置)
            const dur = (typeof live.duration === 'number' && isFinite(live.duration) && live.duration > 0) ? Number(live.duration)
                : (S.cfgFrozen && isFinite(Number(S.cfgFrozen.duration)) && Number(S.cfgFrozen.duration) > 0 ? Number(S.cfgFrozen.duration)
                    : (parseFloat(S.cfg.duration) || 0));
            const prog = (typeof live.progress === 'number' && isFinite(live.progress))
                ? Math.min(Math.max(live.progress, 0), 1)
                : (dur > 0 ? Math.min(Math.max(curT / dur, 0), 1) : 0);
            const pct = 100 * prog;
            // D3:准备/编译阶段没有可靠工作总量 → 不定进度+阶段名,不显示 0.0% 当作确定进度
            const indet = compiling || ui === 'PREPARING';
            const stage = compiling ? '模型编译与求解器初始化' : (S.message || '准备中');
            const early = (S.result && S.result.stopReason === 'user_ended_computation') || live.stopReason === 'user_ended_computation';
            const pctTxt = indet ? '' : (ui === 'ENDED' && early) ? Number(pct).toFixed(1) + '%（提前结束）' : Number(pct).toFixed(1) + '%';
            // D3:预计剩余时间;暂停/失联时不给不可靠估计
            let etaTxt = '';
            if (!indet && (ui === 'RUNNING')) {
                if (S.connLost) etaTxt = '预计剩余：暂不可估计（连接待核查）';
                else if (typeof live.wallSeconds === 'number' && prog > 0 && prog < 1) {
                    const rem = live.wallSeconds * (1 - prog) / prog;
                    etaTxt = '预计剩余 ' + (rem >= 90 ? Math.floor(rem / 60) + 'm' + Math.round(rem % 60) + 's' : Math.round(rem) + 's');
                } else etaTxt = '预计剩余：暂不可估计';
            } else if (ui === 'PAUSED' || ui === 'RESUME_REQ' || ui === 'PAUSE_REQ') etaTxt = '预计剩余：暂不可估计（暂停中）';
            const runId = S.readonlyRunId || live.runId || (S.result && S.result.runId) || '';
            const wall = typeof live.wallSeconds === 'number' ? live.wallSeconds : (S.result && S.result.timing ? S.result.timing.runWall : null);
            const btn = (label, kind, fn, disabled) => h('button', {
                class: 'wb-btn' + (kind ? ' ' + kind : ''), disabled: disabled ? '' : null,
                style: 'min-width:110px;height:40px;font-size:15px', onclick: disabled ? null : fn
            }, label);

            const bar = h('div', { style: 'background:#fff;border-bottom:1px solid #e5e7eb;padding:10px 18px 8px' });
            const statusEl = h('span', { class: 'wb-tag wb-tag-' + meta[1], style: 'font-size:14px;padding:3px 12px' }, meta[0]);
            // 失败态:悬停"计算失败"弹简短预览,点击打开完整日志;原因为空时不响应
            if (ui === 'FAILED' && failReasonText()) {
                statusEl.style.cursor = 'pointer';
                statusEl.addEventListener('mouseenter', () => {
                    const reason = failReasonText();
                    if (reason) showFailTip(statusEl, reason);
                });
                statusEl.addEventListener('mouseleave', hideFailTip);
                statusEl.addEventListener('click', () => {
                    const reason = failReasonText();
                    if (reason) openFailLogModal(reason);
                });
            }
            const row1 = h('div', { style: 'display:flex;align-items:center;gap:18px;flex-wrap:wrap' },
                statusEl,
                h('span', { style: 'font-size:16px' }, indet && !curT ? '仿真 —（未开始出数）'
                    : '仿真 ' + Number(curT).toFixed(1) + ' / ' + (dur > 0 ? Number(dur).toFixed(1) : '—') + ' s'),
                indet
                    ? h('span', { style: 'font-size:14px;color:#b45309;min-width:220px' }, '阶段：' + stage + '（无可靠总量，不定进度）')
                    : h('span', { style: 'font-size:22px;font-weight:700;min-width:86px' }, pctTxt));
            if (etaTxt) row1.appendChild(h('span', { style: 'font-size:13px;color:' + (S.connLost || ui === 'PAUSED' ? '#b45309' : '#334155') }, etaTxt));
            const track = h('div', { style: 'flex:1;min-width:220px;height:16px;background:#e2e8f0;border-radius:4px;overflow:hidden;position:relative' });
            if (indet) {
                // 复用 afoIndet 动画(编译遮罩同一节奏);不把 0.0% 当作确定进度
                track.appendChild(h('div', { style: 'position:absolute;top:0;bottom:0;width:32%;background:#d97706;animation:afoIndet 1.4s linear infinite' }));
            } else {
                track.appendChild(h('div', { style: 'position:absolute;left:0;top:0;bottom:0;width:' + pct + '%;background:#0f766e' }));
            }
            row1.appendChild(track);
            const actions = h('div', { style: 'display:flex;gap:10px;margin-left:12px' });
            const go = ui;
            // D8:实例失联后不再向无人消费的队列写暂停/继续/结束命令(按钮置灰+说明)
            const lost = !!S.procLost;
            const lostTitle = '该实例不能续算：仿真进程心跳已停止，命令不会写入无人消费的队列';
            if (go === 'RUNNING') { actions.appendChild(btn('暂停', 'wb-btn-primary', () => sendCmd('pause', 0), lost)); actions.appendChild(btn('结束计算', 'wb-btn-outline', () => sendCmd('stop', 0), lost)); }
            else if (go === 'PAUSE_REQ') { actions.appendChild(btn('暂停请求中…', 'wb-btn-primary', null, true)); actions.appendChild(btn('结束计算', 'wb-btn-outline', () => sendCmd('stop', 0), lost)); }
            else if (go === 'PAUSED') { actions.appendChild(btn('继续', 'wb-btn-primary', () => sendCmd('resume', 0), lost)); actions.appendChild(btn('结束计算', 'wb-btn-outline', () => sendCmd('stop', 0), lost)); }
            else if (go === 'RESUME_REQ') { actions.appendChild(btn('继续请求中…', 'wb-btn-primary', null, true)); actions.appendChild(btn('结束计算', 'wb-btn-outline', () => sendCmd('stop', 0), lost)); }
            else if (go === 'STOP_REQ') { actions.appendChild(btn('结束请求中…', 'wb-btn-outline', null, true)); }
            else if (go === 'READY') { actions.appendChild(btn('开始仿真', 'wb-btn-primary', startRun)); actions.appendChild(btn('放弃并关闭', 'wb-btn-outline', closeSession)); }
            else if (go === 'ENDED' || go === 'SAVE_FAILED' || go === 'FAILED') { actions.appendChild(btn('结果与历史', 'wb-btn-primary', () => { S.tab = '__result'; renderAll(); })); actions.appendChild(btn('新建运行(关闭会话)', 'wb-btn-outline', closeSession)); }
            else if (go === 'READONLY') { actions.appendChild(btn('‹ 返回仿真准备', 'wb-btn-outline', exitReadonly)); actions.appendChild(btn('📂 导出Excel', 'wb-btn-outline', () => window.open(excelUrl(S.readonlyRunId), '_blank'))); }
            if (lost) actions.querySelectorAll('button[disabled]').forEach(b => { b.title = lostTitle; });
            row1.appendChild(actions);
            bar.appendChild(row1);
            // 第二行小字
            const save = live.saveState;
            const bits = [];
            bits.push('任务 ' + (runId || '—'));
            if (compiling) bits.push('正在编译模型与初始化求解器(通常1~2分钟),首帧数据到达后自动进入计算');
            if (S.procLost) bits.push('该实例不能续算：心跳已停止超过60s(进程可能已退出或实例已丢失)，暂停/继续/结束已禁用');
            if (!S.catalog && S.catalogErr) bits.push('通道字典加载失败(重试中): ' + String(S.catalogErr).slice(0, 60));
            if (live.sampleTime != null) bits.push('最新采样 ' + Number(live.sampleTime).toFixed(1) + ' s');
            bits.push('墙钟耗时单独计量' + (wall != null ? ('（' + (wall >= 90 ? Math.floor(wall / 60) + 'm' + Math.round(wall % 60) + 's' : Number(wall).toFixed(1) + 's') + '）') : ''));
            if (live.publishLive === false) bits.push('实时发布已关闭（Excel仍完整保存）');
            if (typeof live.publishedSeq === 'number' && typeof live.sampleSeq === 'number' && live.publishedSeq < live.sampleSeq) bits.push('发布积压 ' + (live.sampleSeq - live.publishedSeq) + ' 行');
            if (live.publishError) bits.push('发布错误: ' + String(live.publishError).slice(0, 40));
            if (live.observerError) bits.push('观察回调错误(数值继续)');
            // 保存状态(规格3.2/D5):只有结果文件保存成功才显示"已保存";未开始不得当成正在保存
            if (save === 'failed') bits.push('保存失败: ' + (live.saveError || ''));
            else if (save === 'saved') bits.push('结果已保存');
            else if (save === 'writing') bits.push('计算结束，正在保存…');
            else if (ui === 'ENDED') bits.push('等待保存（保存阶段尚未开始）');
            bar.appendChild(h('div', { style: 'font-size:12px;color:#64748b;margin-top:5px;display:flex;gap:16px;flex-wrap:wrap' },
                bits.map(t => h('span', null, t))));
            return bar;
        }

        /* ---------- 编译期过渡(图表提前渲染,只叠动画与提示条) ---------- */
        if (!document.getElementById('afo-r138-style')) {
            const st = document.createElement('style');
            st.id = 'afo-r138-style';
            st.textContent = '@keyframes afoIndet{0%{left:-32%}100%{left:100%}}';
            document.head.appendChild(st);
        }

        /* ---------- 页面骨架 ---------- */
        const wrap = h('div', null);
        const barHost = h('div');
        // 页签+图表区包一层:编译期 loading 遮罩盖这里(不盖运行栏,暂停/结束仍可操作)
        const midHost = h('div', { style: 'position:relative' });
        const tabHost = h('div', { class: 'wb-tabs' });
        const body = h('div');
        midHost.appendChild(tabHost);
        midHost.appendChild(body);
        wrap.appendChild(barHost);
        wrap.appendChild(midHost);

        const TABS = [['main', '总控'], ['engine', '发动机'], ['control', '控制与负载'], ['fuel', '燃油'], ['oil', '滑油'], ['air', '空气']];
        function paintTabs() {
            tabHost.innerHTML = '';
            const bar = h('div', { style: 'display:flex;gap:34px;padding:0 18px;border-bottom:2px solid #e5e7eb;background:#fff' });
            TABS.forEach(([k, label]) => {
                const active = S.tab === k;
                bar.appendChild(h('div', {
                    style: 'padding:10px 2px;font-size:15px;cursor:pointer;color:' + (active ? '#0f766e' : '#334155')
                        + ';font-weight:' + (active ? '700' : '400') + ';border-bottom:3px solid ' + (active ? '#0f766e' : 'transparent'),
                    onclick: () => { S.tab = k; if (k !== 'air') S.airBranch = -1; renderAll(); } // 离开空气页复位单支路视图(M5)
                }, label));
            });
            tabHost.appendChild(bar);
        }

        /* ---------- 图表挂载 ---------- */
        let charts = []; // {ctl?, makeCfg, refresh, dom}
        let staticCharts = [];
        function killCharts() {
            charts.forEach(m => { if (m.ctl) m.ctl.dispose(); });
            staticCharts.forEach(c => c.dispose());
            charts = []; staticCharts = [];
        }
        const windowRange = time => {
            if (!time || !time.length || !S.follow || S.windowPreset === 'all') return null;
            const tEnd = time[time.length - 1];
            const span = { '10s': 10, '30s': 30, '60s': 60 }[S.windowPreset] || 30;
            return [Math.max(0, tEnd - span), Math.max(tEnd, span)];
        };
        // 单位策略(R138 4.2/5.2):常用图按图组目标单位转换(def.u,如发动机温度默认K、
        // 滑油/总控油温℃);开关切"原单位"时一律原值;全部分组(无targetU)显示原单位。
        // L5:useConv 为每图有效换算开关(缺省跟随全局 S.conv),支持单图覆盖
        function defsSeries(defs, acc, targetU, useConv) {
            const convOn = useConv === undefined ? S.conv : !!useConv;
            const out = [];
            if (!S._cmpSkipped) S._cmpSkipped = new Set();
            const accB = compareAcc();
            defs.forEach(d => {
                const id = d.id;
                if (id === NP_DEM) {
                    if (!acc) return;
                    const p = npDemandPair(acc);
                    out.push({ name: d.name || '目标', values: p.vs, unit: 'rpm', time: p.ts, dash: true });
                    return;
                }
                if (id === CMD_STEP) {
                    const p = cmdStepPair(acc);
                    out.push({ name: d.name || '生效值', values: p.vs, unit: '%', time: p.ts, step: true });
                    return;
                }
                const c = chById(id);
                if (!c) return;
                let time, values;
                if (isResultMode() && acc) {
                    if (!acc.has(id)) return;
                    time = acc.time; values = acc.series(id);
                } else {
                    const s = liveSeries(id); time = s.time; values = s.v;
                }
                // 单位策略(R138 4.2/5.2):常用图按图组目标单位转换(def.u,如发动机温度默认K、
                // 滑油/总控油温℃);开关切"原单位"时一律原值;全部分组(无targetU)显示原单位
                let conv = values, u = c.unit;
                if (convOn && targetU) {
                    const r2 = K.convertTo(values, c.unit, targetU);
                    conv = r2.values; u = r2.unit;
                } else if (K.isUnconfirmedUnit(c.unit)) {
                    u = '原值(单位未确认)';
                }
                out.push(Object.assign({
                    name: d.name || qualName(id), values: conv, unit: u, time
                }, { dash: d.dash, step: d.step, color: d.color }));
                // 比较叠加(R138 第8章):先核对同物理量单位一致,不一致不叠加并记录
                if (accB && S.compareOverlay) {
                    const cB = compareUnitOf(id);
                    if (cB && cB !== c.unit) { S._cmpSkipped.add(id); return; }
                    if (!accB.has(id)) return;
                    out.push({
                        name: '[对比]' + (d.name || c.name), values: accB.series(id), unit: u,
                        time: accB.time, dash: true, color: '#94a3b8'
                    });
                }
            });
            return out;
        }
        /** 对比运行通道单位(以对比结果文件内字典为准)。 */
        function compareUnitOf(id) {
            const r = S.compare && S.compare.result;
            if (!r) return null;
            if (!S._cmpUnits) {
                S._cmpUnits = {};
                if (Array.isArray(r.catalog)) r.catalog.forEach(c => { S._cmpUnits[c.id] = c.unit; });
                else (r.channels || []).forEach(spec => (spec.names || []).forEach((nm, j) => {
                    const isFlat = /^fuel_proxy_|^air_g/.test(spec.id);
                    const cid = isFlat ? spec.id : spec.id + '_' + String(j + 1).padStart(2, '0');
                    S._cmpUnits[cid] = (spec.units || [])[j] || '';
                }));
            }
            return S._cmpUnits[id];
        }
        /** 命令生效阶梯:初始挡位+已生效 np 命令(挡位百分比)。 */
        /** D2:Np 基线统一取"带 npRatio 的已冻结/恢复配置",运行中刷新后不回落准备页默认挡位。 */
        function configBaseline() {
            const srcs = [S.cfgFrozen, (S.live || {}).initialConfig, (S.result || {}).initialConfig, S.cfg];
            return srcs.find(x => x && x.npRatio != null) || S.cfg;
        }
        /** 设计参考转速来自程序发布的 initialConfig.designNpRpm;sht_afo_prepare 写入。 */
        function designNpRpm() {
            const srcs = [S.cfgFrozen, (S.live || {}).initialConfig, (S.result || {}).initialConfig, S.cfg];
            for (const x of srcs) {
                if (x && x.designNpRpm != null && isFinite(Number(x.designNpRpm))) return Number(x.designNpRpm);
            }
            // 20800 仅为旧结果缺字段时的兜底,不得反向写回配置
            return 20800;
        }
        function cmdStepPair(acc) {
            const cfg0 = configBaseline();
            const events = eventsList();
            const steps = events.filter(e => e.kind === 'np' && e.status === 'applied' && e.appliedTime != null)
                .sort((a, b) => a.appliedTime - b.appliedTime)
                .map(e => ({ t: e.appliedTime, v: parseFloat(e.value) * 100 }));
            const time = acc ? acc.time : (S.liveBuf ? S.liveBuf.time : []);
            const t0 = time[0] || 0, t1 = time[time.length - 1] || 0;
            const n = Math.min(300, Math.max(8, time.length || 30)), ts = [], vs = [];
            for (let k = 0; k <= n; k++) {
                const t = t0 + (t1 - t0) * k / n;
                let v = parseFloat(cfg0.npRatio || 1) * 100;
                steps.forEach(s => { if (t >= s.t) v = s.v; });
                ts.push(t); vs.push(v);
            }
            return { ts, vs };
        }
        function npDemandPair(acc) {
            const cfg0 = configBaseline();
            const designNp = designNpRpm();
            const steps = eventsList().filter(e => e.kind === 'np' && e.status === 'applied' && e.appliedTime != null)
                .sort((a, b) => a.appliedTime - b.appliedTime)
                .map(e => ({ t: e.appliedTime, v: parseFloat(e.value) * designNp }));
            const time = acc ? acc.time : (S.liveBuf ? S.liveBuf.time : []);
            const t0 = time[0] || 0, t1 = time[time.length - 1] || 0;
            const n = Math.min(400, Math.max(8, time.length || 30)), ts = [], vs = [];
            for (let k = 0; k <= n; k++) {
                const t = t0 + (t1 - t0) * k / n;
                let v = parseFloat(cfg0.npRatio || 1) * designNp;
                steps.forEach(s => { if (t >= s.t) v = s.v; });
                ts.push(t); vs.push(v);
            }
            return { ts, vs };
        }

        /** 一图一曲线(用户反馈):多曲线图拆成若干单曲线图,标题带曲线短名便于区分。
         *  【明确例外】这是对 UI_R138 文档版式的明确例外(用户决定,2026-11):保留全局拆分,
         *  不按文档"一图多曲线"回退;文档本身不修改。 */
        function splitOneSeries(defs) {
            const out = [];
            (defs || []).forEach(def => {
                const list = def.s || [];
                if (list.length <= 1) { out.push(def); return; }
                list.forEach(one => out.push(Object.assign({}, def, {
                    t: (def.t ? def.t + '·' : '') + (one.name || one.id),
                    s: [one]
                })));
            });
            return out;
        }

        /** 图卡(效果图:标题左上/单位右上/图区/图例在图内底部;标题行含单位切换与导出当前视图)。 */
        function chartCard(host, def, resultMode) {
            // 单位:常用图按图组目标单位(def.u,如发动机温度K、滑油/总控油温℃);"原单位"开关切回。
            // L5:每图可切单位——仅当图声明目标单位且基准单位有明确换算路径(Pa→kPa/K→℃/W→kW等)
            // 时显示按钮;覆盖状态按图保存于 S.__unitOv(默认跟随全局"单位"开关),切换只重绘本图
            const firstId = (def.s || []).map(d => d.id).find(id => id !== NP_DEM && id !== CMD_STEP && chById(id));
            const rawBase = firstId ? String(chById(firstId).unit || '') : String(def.u || '');
            const ovKey = (def.t || '') + '::' + (def.s || []).map(d => d.id).join(',');
            const canConv = !!firstId && !!def.u && !!K.convertedUnit(rawBase); // 单位元数据:图目标单位+通道基准单位
            const effConv = () => { const ov = (S.__unitOv || {})[ovKey]; return ov ? ov === 'conv' : S.conv; };
            const unitLabelOf = convOn => {
                if (!firstId) return def.u || '';
                const raw = chById(firstId).unit;
                return convOn ? (K.convertTo([], raw, def.u).unit || raw)
                    : (K.isUnconfirmedUnit(raw) ? '原值(单位未确认)' : String(raw || ''));
            };
            const ctlRef = { ctl: null, redraw: null, refresh: null };
            const unitEl = h('span', { style: 'font-size:12px;color:#64748b' }, unitLabelOf(effConv()));
            const card = h('div', { style: 'background:#fff;border-radius:4px;padding:8px 6px 2px' },
                h('div', { style: 'display:flex;align-items:baseline;padding:0 4px' },
                    h('span', { style: 'font-weight:700;font-size:14px;color:#0f172a' }, def.t),
                    h('span', { style: 'flex:1' }),
                    unitEl,
                    h('span', {
                        style: 'font-size:11px;color:#0f766e;cursor:pointer;margin-left:10px',
                        title: '复位本图视图(缩放/平移回到初始窗口)',
                        onclick: () => {
                            if (ctlRef.ctl && ctlRef.ctl.resetView) ctlRef.ctl.resetView();
                            else if (ctlRef.redraw) ctlRef.redraw(); // 结果模式控制器尚未就绪时重挂本图
                        }
                    }, '复位'),
                    canConv ? h('span', {
                        style: 'font-size:11px;color:#0f766e;cursor:pointer;margin-left:10px',
                        title: '本图单位切换（明确换算 ' + rawBase + '→' + K.convertedUnit(rawBase) + '；切换后本图不再跟随全局单位开关）',
                        onclick: () => {
                            S.__unitOv = S.__unitOv || {};
                            S.__unitOv[ovKey] = effConv() ? 'raw' : 'conv'; // 每图覆盖状态
                            unitEl.textContent = unitLabelOf(effConv());
                            if (ctlRef.redraw) ctlRef.redraw();
                            else if (ctlRef.refresh) ctlRef.refresh(); // 只重绘本图
                        }
                    }, '单位') : null,
                    h('span', {
                        style: 'font-size:11px;color:#0f766e;cursor:pointer;margin-left:10px',
                        title: '导出当前视图(窗口内样本)',
                        onclick: () => { if (ctlRef.ctl) ctlRef.ctl.exportCsv(); }
                    }, '⤓')));
            const dom = h('div', { style: 'height:' + (def.h || 185) + 'px' });
            card.appendChild(dom);
            host.appendChild(card);
            // D11:扭矩模式下等效桨距/桨距映射不适用 → 显示"不适用",不画空线或零值
            if ((def.s || []).some(d => d.id === 'load_02') && loadMode() === 'torque') {
                dom.style.height = 'auto';
                dom.appendChild(K.emptyState('不适用', '扭矩模式按扭矩施加负载，不计算等效桨距'));
                return;
            }
            const missing = (def.s || []).filter(d => d.id !== NP_DEM && d.id !== CMD_STEP && !chById(d.id)).map(d => d.id);
            if (missing.length === (def.s || []).length && (def.s || []).length) {
                dom.style.height = 'auto';
                dom.appendChild(isCompiling()
                    ? K.emptyState('等待首帧样本…', '模型编译完成后自动开始绘制')
                    : K.emptyState('通道未在本次字典中', missing.join(', ')));
                return;
            }
            if (missing.length) {
                card.insertBefore(h('div', { style: 'font-size:11px;color:#b45309;padding:0 4px 2px' }, '本结果未记录: ' + missing.join(', ')), dom);
            }
            const zoomHooks = {
                onZoom: () => {
                    // R138 5.2:用户拖动/缩放历史区间后,自动关闭"跟随最新"(仿真继续)
                    if (S.follow) {
                        S.follow = false; saveDisp();
                        if (S._followEl) { S._followEl.textContent = '跟随最新：关'; S._followEl.style.color = '#b45309'; }
                    }
                }
            };
            if (resultMode) {
                const acc = resultAcc;
                if (!acc) { dom.appendChild(K.emptyState('结果尚未加载')); return; }
                // 结果模式:单图重绘入口(L5 单位覆盖切换时只重挂本图,不整页重建)
                ctlRef.redraw = () => {
                    if (ctlRef.ctl) { try { ctlRef.ctl.dispose(); } catch (e) { /* 已释放 */ } ctlRef.ctl = null; }
                    dom.innerHTML = '';
                    const series = defsSeries(def.s, acc, def.u, effConv());
                    if (!series.length) { dom.appendChild(K.emptyState('暂无数据')); return; }
                    K.mount(dom, { time: acc.time, series, window: windowRange(acc.time), marks: appliedMarks() }, zoomHooks)
                        .then(c => { ctlRef.ctl = c; staticCharts.push(c); })
                        .catch(e => { dom.innerHTML = ''; dom.appendChild(K.emptyState('图表库加载失败', e.message)); });
                };
                ctlRef.redraw();
                return;
            }
            const meta = {
                ctl: null, dom, def,
                makeCfg() {
                    const series = defsSeries(def.s, null, def.u, effConv());
                    const t = S.liveBuf ? S.liveBuf.time : [];
                    return { time: t, series, window: windowRange(t), marks: appliedMarks() };
                },
                refresh() { if (this.ctl && !this.ctl.disposed) this.ctl.setCfg(this.makeCfg()); }
            };
            charts.push(meta);
            ctlRef.refresh = () => meta.refresh();
            K.mount(dom, meta.makeCfg(), zoomHooks).then(c => { meta.ctl = c; ctlRef.ctl = c; }).catch(e => {
                dom.innerHTML = ''; dom.appendChild(K.emptyState('图表库加载失败', e.message));
            });
        }
        /** 状态条卡(效果图 F06)。 */
        function stateCard(host, def, resultMode) {
            const card = h('div', { style: 'background:#fff;border-radius:4px;padding:8px 6px 2px' },
                h('div', { style: 'display:flex;align-items:baseline;padding:0 4px' },
                    h('span', { style: 'font-weight:700;font-size:14px;color:#0f172a' }, def.t),
                    h('span', { style: 'flex:1' }),
                    h('span', { style: 'font-size:12px;color:#64748b' }, '状态带')));
            const dom = h('div', { style: 'min-height:120px' });
            card.appendChild(dom);
            host.appendChild(card);
            const render = () => {
                dom.innerHTML = '';
                const rows = [];
                (def.state || []).forEach(r => {
                    const c = chById(r.id);
                    if (!c) return;
                    let time, values;
                    if (isResultMode() && resultAcc && resultAcc.has(r.id)) { time = resultAcc.time; values = resultAcc.series(r.id); }
                    else { const s = liveSeries(r.id); time = s.time; values = s.v; }
                    // S1:保留 null(非有限样本),由 stateBar 断带处理,不得画成0或跨段连线
                    rows.push({ label: r.label, time, values, color: r.color });
                });
                K.stateBar(dom, rows);
            };
            if (resultMode) render();
            else { charts.push({ refresh: render, makeCfg: null }); render(); }
        }
        const refreshRuntimeCharts = () => charts.forEach(m => m.refresh && m.refresh());
        S.__refreshRuntime = refreshRuntimeCharts; // 供测试/外部触发(与内部轮询同一入口)

        /* ---------- 视图条(内联;MS-09) ---------- */
        function viewBar() {
            const seg = (key, label) => h('span', {
                style: 'font-size:14px;font-weight:' + (S.viewMode === key ? '700' : '400') + ';color:' + (S.viewMode === key ? '#0f766e' : '#334155')
                    + ';cursor:pointer;margin-right:22px',
                onclick: () => { S.viewMode = key; saveDisp(); renderAll(); }
            }, label);
            const winBtn = (key, label) => h('span', {
                style: 'font-size:13px;color:' + (S.windowPreset === key ? '#0f766e;font-weight:700' : '#334155') + ';cursor:pointer;margin-left:14px',
                onclick: () => { S.windowPreset = key; saveDisp(); refreshRuntimeCharts(); }
            }, label);
            const followEl = h('span', {
                style: 'font-size:13px;color:' + (S.follow ? '#334155' : '#b45309') + ';cursor:pointer;margin-left:14px',
                onclick: () => { S.follow = !S.follow; if (S.follow) S.followDirty = false; saveDisp(); renderAll(); },
                title: '关闭跟随仅停止视图滚动,仿真继续'
                // L2:关跟随后有新样本到达时,给出可见提示;点跟随恢复后清除
            }, '跟随最新：' + (S.follow ? '开' : ('关' + (S.followDirty ? '（新数据已到达）' : ''))));
            S._followEl = followEl; // 缩放回调更新文本(R138 5.2)
            const bar = h('div', { style: 'background:#f1f5f9;border-radius:4px;padding:8px 14px;margin-bottom:12px;display:flex;align-items:center' },
                seg('common', '常用'), seg('groups', '全部分组'), seg('custom', '自选'),
                h('span', { style: 'flex:1' }),
                h('span', { style: 'font-size:13px;color:#334155' }, '时间窗'),
                winBtn('30s', '30 s'), winBtn('10s', '10 s'), winBtn('60s', '60 s'), winBtn('all', '全历程'),
                followEl,
                h('span', {
                    style: 'font-size:13px;color:#0f766e;cursor:pointer;margin-left:14px',
                    onclick: () => { S.follow = true; S.windowPreset = '30s'; saveDisp(); renderAll(); }
                }, '复位'),
                h('span', {
                    style: 'font-size:13px;color:#334155;cursor:pointer;margin-left:14px',
                    onclick: () => { S.conv = !S.conv; saveDisp(); renderAll(); }
                }, '单位：' + (S.conv ? '显示单位' : '原单位')));
            return bar;
        }
        function pageHead(title) {
            return h('div', { style: 'padding:14px 18px 10px;background:#fff' },
                h('div', { style: 'font-size:21px;font-weight:800;color:#0f172a' }, title));
        }

        /* ---------- 系统页 ---------- */
        const sysOfTab = { engine: 'engine', control: 'control', fuel: 'fuel', oil: 'oil', air: 'air' };
        /** 空气页顶部状态(M6,规格4.6):显示本次运行实际回灌状态,取冻结配置→live/结果initialConfig→准备表单。 */
        function airStatusText() {
            const srcs = [S.cfgFrozen, (S.live || {}).initialConfig, (S.result || {}).initialConfig, S.cfg];
            let on = null;
            for (const x of srcs) { if (x && x.externalAir != null) { on = !!x.externalAir; break; } }
            return '外部回灌：' + (on ? '开启' : '关闭') + '（关闭不停止空气系统计算）';
        }
        function paintSystemTab(sys) {
            const resultMode = isResultMode();
            const L = COMMON_LAYOUT[sys];
            body.appendChild(pageHead(L.title));
            if (L.notice) body.appendChild(h('div', { style: 'padding:2px 18px 8px;background:#fff;font-size:13px;color:#0f766e' },
                sys === 'air' ? airStatusText() : L.notice)); // M6:空气页顶部显示本次运行实际回灌状态
            if (!S.catalog) {
                body.appendChild(h('div', { class: 'wb-empty' }, '通道字典未加载(会话准备完成后从 channels.json 读取;历史运行取自结果 catalog/channels)。'));
                return;
            }
            // 视图切换条在自选视图同样显示,否则进入自选后无法切回常用/全部分组
            body.appendChild(viewBar());
            // L6(规格4.5):图区与常驻通道树横向排列;"全部分组"共用右侧可折叠通道树;
            // "自选"按UI-R138效果图通道树固定在左侧(先树后图)
            const rowc = h('div', { style: 'display:flex;align-items:flex-start' });
            body.appendChild(rowc);
            const host = h('div', { style: 'padding:0 18px 16px;flex:1;min-width:0' });
            if (S.viewMode === 'custom') { rowc.appendChild(channelTreePanel()); rowc.appendChild(host); paintCustomWorkspace(host, resultMode); return; }
            rowc.appendChild(host);
            // M5(规格4.6):空气页单支路三图查看(流量/温度/压力纵排,不新增物理量)
            if (sys === 'air' && S.airBranch >= 0) {
                paintAirSingle(host, resultMode);
                if (S.viewMode === 'groups') rowc.appendChild(channelTreePanel());
                return;
            }
            if (S.viewMode === 'common') {
                const gr = h('div', { class: 'wb-chart', style: 'display:grid;grid-template-columns:1fr 1fr;gap:10px 22px' });
                host.appendChild(gr);
                (L.charts || []).forEach(def => {
                    if (def.state) stateCard(gr, def, resultMode);
                    else splitOneSeries([def]).forEach(d => chartCard(gr, d, resultMode));
                });
                if (sys === 'air') paintAirGrid(gr, resultMode);
            } else {
                // 全部分组:逐组展开(名称取自字典)
                (GROUPS_ALL[sys] || []).forEach(g => {
                    host.appendChild(h('div', { style: 'font-weight:700;margin:12px 0 2px' }, g.t,
                        h('span', { style: 'font-weight:400;font-size:12px;color:#64748b;margin-left:10px' }, g.note || '')));
                    if (g.events) { host.appendChild(eventsTable()); return; }
                    const gr = h('div', { class: 'wb-chart', style: 'display:grid;grid-template-columns:1fr 1fr;gap:10px 22px' });
                    host.appendChild(gr);
                    (g.charts || []).forEach(ch => splitOneSeries([{ t: g.t, u: '', s: ch }])
                        .forEach(d => chartCard(gr, Object.assign({}, d, { t: g.t ? d.t.replace(/^·/, '') : (d.s[0].name || d.s[0].id) }), resultMode)));
                    if (g.state) stateCard(gr, { t: g.t, state: g.state }, resultMode);
                });
                if (sys === 'air') { const gr2 = h('div', { class: 'wb-chart' }); host.appendChild(gr2); paintAirGrid(gr2, resultMode); }
            }
            if (sys === 'air' && S.viewMode === 'groups') rowc.appendChild(channelTreePanel());
            if (L.footnote) host.appendChild(h('div', { style: 'font-size:13px;color:#334155;padding:10px 4px 0' }, L.footnote));
            if (!resultMode) host.appendChild(h('div', { style: 'font-size:12px;color:#94a3b8;padding:4px 4px 0' },
                '运行中曲线读取 stream 增量样本块(R065);关闭“跟随最新”仅冻结视图,仿真继续。'));
        }
        /** 空气三行×八路(用户要求一图一曲线):每张图一个支路,支路显隐联动三行。
         *  【明确例外】空气页保留"支路总览 + 单支路三图查看"现有版式,这是对 UI_R138 文档的
         *  明确例外(用户决定,2026-11);不改成图例点选单支路,也不恢复 6 图×4 支路多曲线布局。
         *  仅修复该支路查看链路的实际功能缺陷,不改版式;文档本身不修改。 */
        function paintAirGrid(host, resultMode) {
            AIR_ROWS.forEach(row => {
                const unit = S.conv && row.title === '供气压力' ? 'kPa' : row.unit;
                AIR_BRANCH.forEach((br, bi) => {
                    if (S.airHide[br]) return;
                    const id = row.ids[bi];
                    const head = h('div', { style: 'display:flex;align-items:baseline;padding:6px 4px 0' },
                        h('span', { style: 'font-weight:700;font-size:14px;color:#0f172a' }, row.title + ' ' + br),
                        h('span', { style: 'flex:1' }),
                        h('span', { style: 'font-size:12px;color:#64748b' }, unit));
                    const dom = h('div', { style: 'height:150px' });
                    host.appendChild(h('div', null, head, dom));
                    const c = chById(id);
                    if (!c) { dom.appendChild(K.emptyState('本结果未记录', id)); return; }
                    const conv = v => (S.conv && row.title === '供气压力') ? K.convertSeries(v, 'Pa').values : v;
                    const sUnit = () => (S.conv && row.title === '供气压力') ? 'kPa' : (c.unit || row.unit);
                    if (resultMode && resultAcc) {
                        if (!resultAcc.has(id)) { dom.appendChild(K.emptyState('本结果未记录(25项为R065新增)', id)); return; }
                        K.mount(dom, {
                            time: resultAcc.time,
                            series: [{ name: br, values: conv(resultAcc.series(id)), unit: sUnit(), time: resultAcc.time, color: AIR_BRANCH_COLOR[bi] }],
                            window: windowRange(resultAcc.time), marks: appliedMarks()
                        }).then(ctl => staticCharts.push(ctl)).catch(() => { });
                    } else {
                        const meta = {
                            ctl: null,
                            makeCfg() {
                                const s = liveSeries(id);
                                return {
                                    time: s.time,
                                    series: [{ name: br, values: conv(s.v), unit: sUnit(), time: s.time, color: AIR_BRANCH_COLOR[bi] }],
                                    window: windowRange(s.time), marks: appliedMarks()
                                };
                            },
                            refresh() { if (this.ctl && !this.ctl.disposed) this.ctl.setCfg(this.makeCfg()); }
                        };
                        charts.push(meta);
                        K.mount(dom, meta.makeCfg()).then(ctl => { meta.ctl = ctl; }).catch(() => { });
                    }
                });
            });
            host.appendChild(h('div', { style: 'font-size:13px;color:#334155;padding:8px 4px 0' },
                '每图一个支路(温度/压力同源)，支路可单独显隐。界面不展示模板、合并或延迟副本。原空气选择器第10输入未接线等历史限制保留。'));
            const chips = h('div', { style: 'display:flex;gap:6px;padding:6px 0 0;flex-wrap:wrap' });
            AIR_BRANCH.forEach((g, i) => {
                chips.appendChild(h('button', {
                    class: 'wb-btn ' + (S.airHide[g] ? 'wb-btn-outline' : 'wb-btn-primary'),
                    style: 'font-size:12px;padding:2px 12px',
                    onclick: () => { S.airHide[g] = !S.airHide[g]; saveDisp(); renderAll(); }
                }, g));
                // M5(规格4.6):单支路查看入口——进入该支路流量/温度/压力三图单独视图
                chips.appendChild(h('button', {
                    class: 'wb-btn wb-btn-outline',
                    style: 'font-size:12px;padding:2px 8px',
                    title: g + ' 单支路三图查看(质量流量/供气温度/供气压力)',
                    onclick: () => { S.airBranch = i; saveDisp(); renderAll(); }
                }, '查看'));
            });
            host.appendChild(chips);
        }
        /** 空气单支路视图(M5,规格4.6):该支路的流量/温度/压力三图纵排,带"返回八路总览";不新增物理量。 */
        function paintAirSingle(host, resultMode) {
            const bi = S.airBranch;
            const g = AIR_BRANCH[bi] || AIR_BRANCH[0];
            host.appendChild(h('div', { style: 'display:flex;align-items:center;gap:14px;padding:4px 4px 10px' },
                h('button', {
                    class: 'wb-btn wb-btn-outline', style: 'font-size:13px;padding:4px 14px',
                    onclick: () => { S.airBranch = -1; saveDisp(); renderAll(); }
                }, '‹ 返回八路总览'),
                h('span', { style: 'font-weight:700;font-size:15px;color:#0f172a' },
                    g + ' 单支路三图（质量流量 / 供气温度 / 供气压力）')));
            const rows = [AIR_ROWS[0], AIR_ROWS[1], AIR_ROWS[2]];
            const gr = h('div', { class: 'wb-chart', style: 'display:grid;grid-template-columns:1fr;gap:10px' });
            host.appendChild(gr);
            rows.forEach(row => {
                const id = row.ids[bi];
                const head = h('div', { style: 'display:flex;align-items:baseline;padding:6px 4px 0' },
                    h('span', { style: 'font-weight:700;font-size:14px;color:#0f172a' }, row.title + ' ' + g),
                    h('span', { style: 'flex:1' }),
                    h('span', { style: 'font-size:12px;color:#64748b' }, S.conv && row.title === '供气压力' ? 'kPa' : row.unit));
                const dom = h('div', { style: 'height:220px' });
                gr.appendChild(h('div', null, head, dom));
                if (!chById(id)) { dom.appendChild(K.emptyState('本结果未记录', id)); return; }
                if (isResultMode() && resultAcc) {
                    if (!resultAcc.has(id)) { dom.appendChild(K.emptyState('本结果未记录')); return; }
                    const c = chById(id);
                    const conv = S.conv && row.title === '供气压力' ? K.convertSeries(resultAcc.series(id), 'Pa').values : resultAcc.series(id);
                    K.mount(dom, {
                        time: resultAcc.time,
                        series: [{ name: g, values: conv, unit: S.conv && row.title === '供气压力' ? 'kPa' : (c.unit || row.unit), time: resultAcc.time, color: AIR_BRANCH_COLOR[bi] }],
                        window: windowRange(resultAcc.time), marks: appliedMarks()
                    }).then(ctl => staticCharts.push(ctl)).catch(() => { });
                } else {
                    const meta = {
                        ctl: null,
                        makeCfg() {
                            const s = liveSeries(id);
                            const conv = S.conv && row.title === '供气压力' ? K.convertSeries(s.v, 'Pa').values : s.v;
                            const c = chById(id);
                            return {
                                time: s.time,
                                series: [{ name: g, values: conv, unit: S.conv && row.title === '供气压力' ? 'kPa' : (c.unit || row.unit), time: s.time, color: AIR_BRANCH_COLOR[bi] }],
                                window: windowRange(s.time), marks: appliedMarks()
                            };
                        },
                        refresh() { if (this.ctl && !this.ctl.disposed) this.ctl.setCfg(this.makeCfg()); }
                    };
                    charts.push(meta);
                    K.mount(dom, meta.makeCfg()).then(ctl => { meta.ctl = ctl; }).catch(() => { });
                }
            });
        }

        /* ---------- 通道树(常驻右侧面板,L6)与样本值表 ---------- */
        /** 常驻通道树(L6,规格4.5):"全部分组"与"自选"共用;点击节点添加/移除自选曲线
         *  (同一曲线不会重复添加);可折叠,折叠态记忆在显示配置。 */
        function channelTreePanel() {
            const open = !S.treeCollapsed;
            const panel = h('div', {
                style: 'width:' + (open ? '280px' : '34px') + ';flex:none;background:#f8fafc;border-left:1px solid #e5e7eb;'
                    + 'padding:' + (open ? '12px 14px' : '12px 6px') + ';max-height:760px;overflow:auto;box-sizing:border-box'
            });
            panel.appendChild(h('div', {
                style: 'display:flex;align-items:center;cursor:pointer;white-space:nowrap;margin-bottom:8px',
                title: open ? '收起通道树' : '展开通道树',
                onclick: () => { S.treeCollapsed = !S.treeCollapsed; saveDisp(); renderAll(); }
            },
                h('span', { style: 'font-size:13px;font-weight:700;color:#0f766e' }, open ? '收起 ›' : '‹'),
                open ? h('span', { style: 'font-size:12px;color:#64748b;margin-left:6px' }, '通道树（点击添加/移除自选）') : null));
            if (!open) return panel;
            const search = h('input', { placeholder: '搜索 名称 / ID（如 油温 / oil09）', style: 'width:100%;margin-bottom:10px' });
            panel.appendChild(search);
            const listBox = h('div');
            panel.appendChild(listBox);
            function paintList() {
                const kw = search.value.trim().toLowerCase();
                listBox.innerHTML = '';
                if (!S.catalog) { listBox.appendChild(h('div', { class: 'wb-hint' }, '字典未加载')); return; }
                const byGrp = {};
                S.dispIds.forEach(id => {
                    const c = chById(id);
                    const hit = !kw || id.toLowerCase().includes(kw) || String(c.name).toLowerCase().includes(kw);
                    if (hit) (byGrp[c.displayGroup] = byGrp[c.displayGroup] || []).push(c);
                });
                Object.keys(byGrp).forEach(gr => {
                    listBox.appendChild(h('div', { style: 'font-weight:700;font-size:13px;margin:8px 0 2px;color:#0f172a' },
                        (SYS_TITLE[gr] || gr) + ' ' + byGrp[gr].length + '项'));
                    byGrp[gr].forEach(c => {
                        const checked = S.custom.includes(c.id);
                        listBox.appendChild(h('div', {
                            style: 'font-size:13px;padding:2px 0 2px 14px;color:' + (checked ? '#0f766e;font-weight:600' : '#334155') + ';cursor:pointer',
                            onclick: () => {
                                if (checked) S.custom = S.custom.filter(x => x !== c.id);
                                else if (!S.custom.includes(c.id)) S.custom.push(c.id);
                                saveDisp(); renderAll();
                            }
                        }, c.name));
                    });
                });
            }
            search.addEventListener('input', paintList);
            paintList();
            return panel;
        }
        /** “当前选中时刻”样本值表(MS-09)。 */
        function sampleTable(ids) {
            const t = K.cursorBus.value;
            const box = h('div', { style: 'margin-top:8px' });
            box.appendChild(h('div', { style: 'font-weight:700;font-size:14px;border-bottom:1px solid #e5e7eb;padding-bottom:4px' },
                '当前选中时刻：' + (t != null ? '使用实际样本时间（游标 ' + Number(t).toFixed(3) + ' s）' : '点击图面设置共同游标')));
            ids.forEach(id => {
                const c = chById(id);
                if (!c) return;
                const raw = t != null ? valueAt(id, t) : null;
                const conv = S.conv ? K.convertSeries(raw == null ? [] : [raw], c.unit).values[0] : raw;
                const uLabel = S.conv ? K.unitLabel(c.unit) : (K.isUnconfirmedUnit(c.unit) ? '原值(单位未确认)' : (c.unit || ''));
                box.appendChild(h('div', { style: 'display:flex;gap:24px;padding:6px 0;border-bottom:1px solid #f8fafc;font-size:13px' },
                    h('span', { style: 'width:170px;color:#334155' }, id),
                    h('span', { style: 'flex:1' }, c.name),
                    h('span', { style: 'width:120px;color:#0f172a;font-weight:600' }, raw === undefined ? '本结果未记录' : K.fmtV(conv == null ? null : conv)),
                    h('span', { style: 'width:110px;color:#64748b' }, uLabel)));
            });
            box.appendChild(h('div', { style: 'font-size:12px;color:#94a3b8;padding-top:6px' }, '样本值由后台读取；图例不刊出项目物理数值。'));
            return box;
        }
        /** 自选工作区(MS-09):右侧图+样本值表;通道树由 paintSystemTab 统一提供(L6 常驻右侧)。 */
        function paintCustomWorkspace(host, resultMode) {
            refreshAcc();
            const ids = S.custom.slice();
            if (!ids.length) {
                host.appendChild(h('div', { class: 'wb-empty' }, '在左侧通道树点击通道加入自选（同一曲线不会重复添加）；样本值表跟随共同游标显示实际样本。'));
                return;
            }
            const buckets = [];
            ids.forEach(id => {
                const c = chById(id);
                if (!c) return;
                const key = K.isUnconfirmedUnit(c.unit) ? '__unc__' : c.unit;
                let b = buckets.find(x => x.key === key && x.items.length < 4);
                if (!b) { b = { key, items: [] }; buckets.push(b); }
                b.items.push(id);
            });
            const gr = h('div', { class: 'wb-chart', style: 'display:grid;grid-template-columns:1fr 1fr;gap:10px 22px' });
            host.appendChild(gr);
            buckets.forEach(bk => {
                const defs = bk.items.map(id => {
                    const c = chById(id);
                    const converted = S.conv && !K.isUnconfirmedUnit(c.unit) && K.convertedUnit(c.unit);
                    return S_(id, { name: qualName(id), unit: converted || c.unit, rawUnit: converted ? c.unit : undefined });
                });
                // 一图一曲线(用户反馈):自选工作区同样按通道拆分
                splitOneSeries([{ t: bk.key === '__unc__' ? '未确认单位（原值）' : bk.key, u: bk.key === '__unc__' ? '' : bk.key, s: defs }])
                    .forEach(d => chartCard(gr, d, resultMode));
            });
            host.appendChild(sampleTable(ids.slice()));
            const rm = h('div', { style: 'margin-top:10px;display:flex;gap:6px;flex-wrap:wrap' });
            ids.forEach(id => rm.appendChild(h('button', {
                class: 'wb-btn wb-btn-outline', style: 'font-size:12px;padding:2px 10px',
                onclick: () => { S.custom = S.custom.filter(x => x !== id); saveDisp(); renderAll(); }
            }, '− ' + ((chById(id) || {}).name || id))));
            host.appendChild(rm);
        }

        /** 待生效命令:Java把status.json的pending统一规范成数组(单元素对象→[obj],空→[]),
         *  不能直接当对象读;空数组在JS恒为真,会误判为"永远有待生效项"(规格3.3占位)。 */
        function pendingOf(live) {
            const p = (live || {}).pending;
            if (Array.isArray(p)) return p.length ? p[0] : null;
            return p || null;
        }
        /** 本端已提交、回执未到的事件(按提交编号匹配)。 */
        function submittedEvent() {
            const l = S.lastSubmit;
            if (!l || !l.id) return null;
            return eventsList().filter(e => e && String(e.id) === String(l.id)).slice(-1)[0] || null;
        }
        /** 物理输入占位(规格3.3):后台待生效项 + 本端等待回执的提交(8s兜底防永久锁死)。
         *  只约束np/load的"施加";暂停、继续、结束计算不受此占位限制。 */
        function physicsLocked() {
            if (S.applyBusy) return true;
            if (pendingOf(S.live)) return true;
            const l = S.lastSubmit;
            return !!(l && !submittedEvent() && (Date.now() - l.at) < 8000);
        }
        /** 待生效提示:请求值与提交编号取自后台pending,状态与事件表同源。 */
        function pendingHintText(live) {
            const p = pendingOf(live);
            if (!p) return '待施加命令：最多1项';
            return '待施加命令：最多1项（' + cmdText(p) + (p.id ? '，提交编号 ' + p.id : '')
                + '；' + (uiState() === 'PAUSED' ? '已接受，继续后施加' : '已接受，待生效') + '）';
        }
        /** 两个物理"施加"按钮的统一置灰/恢复(就地补丁,不重建页面)。
         *  文案始终保留"施加",禁用时用置灰+title解释,避免入口看起来消失。 */
        function paintApplyButtons() {
            const locked = physicsLocked();
            ['apply-np', 'apply-load'].forEach(k => {
                const b = body.querySelector('[data-afo="' + k + '"]');
                if (b) {
                    b.disabled = locked;
                    b.title = locked ? '已有待生效的物理输入命令，暂不能施加' : '';
                }
            });
        }
        /** 最近一次物理输入提交:提交编号、请求值、状态(接受≠生效,生效值只认applied回执)。 */
        function lastSubmitText() {
            const l = S.lastSubmit;
            if (!l) return '';
            const ev = submittedEvent();
            const p = pendingOf(S.live);
            let st;
            if (ev) st = evState(ev)[0];
            else if (p && l.id && String(p.id || '') === String(l.id)) {
                st = uiState() === 'PAUSED' ? '已接受，继续后施加' : '已接受，待生效';
            } else st = '已提交，等待后台回执';
            return '最近提交：提交编号 ' + (l.id || '—') + ' · ' + cmdText(l) + ' · 状态：' + st;
        }
        /** 填充状态提示条(暂停/暂停请求/结束请求/断连/增量异常)。 */
        function fillStateNotices(host, live) {
            host.innerHTML = '';
            const ui = uiState();
            if (ui === 'PAUSED') host.appendChild(h('div', { class: 'wb-infobar', style: 'border-left:4px solid #0f766e;margin-bottom:10px' },
                '已暂停：原实例保留，可检查历史，仿真时间不再推进。任一运行阶段都可请求结束计算；这不是发动机物理停车。'));
            // L3(规格6.2):暂停请求横幅持久显示,含最后活动信息;等待超30s追加延迟提示
            if (ui === 'PAUSE_REQ') {
                const waitS = S.pauseReqAt ? Math.round((Date.now() - S.pauseReqAt) / 1000) : 0;
                host.appendChild(h('div', { class: 'wb-infobar', style: 'border-left:4px solid #b45309;margin-bottom:10px' },
                    '暂停请求已提交，等待安全响应点；最后活动：样本 '
                    + (live.sampleTime != null ? 't=' + Number(live.sampleTime).toFixed(3) + ' s' : '—')
                    + '（心跳 ' + (live.lastHeartbeat || '—') + '）'
                    + (waitS > 30 ? '。响应延迟较长，请耐心等待或查看日志' : '')));
            }
            // L3:结束请求横幅同样补最后活动信息
            if (ui === 'STOP_REQ') host.appendChild(h('div', { class: 'wb-infobar', style: 'margin-bottom:10px' },
                '已请求结束计算；服务点确认前仿真仍可能推进（不强杀进程）。最后活动：样本 '
                + (live.sampleTime != null ? 't=' + Number(live.sampleTime).toFixed(3) + ' s' : '—')
                + '（心跳 ' + (live.lastHeartbeat || '—') + '）。'));
            if (S.procLost) host.appendChild(h('div', { class: 'wb-infobar', style: 'border-left:4px solid #b91c1c;margin-bottom:10px' },
                '该实例不能续算：最后心跳 ' + ((S.live || {}).lastHeartbeat || '—')
                + '，已超过60 s 无更新（进程可能已退出或实例已丢失）。暂停/继续/结束请求不会再写入无人消费的命令队列；'
                + '曲线保持已到达的样本，不宣称后台仍在运行。'));
            else if (S.connLost) host.appendChild(h('div', { class: 'wb-infobar', style: 'border-left:4px solid #b91c1c;margin-bottom:10px' },
                '连接待核查：最后心跳 ' + ((S.live || {}).lastHeartbeat || '—') + '。曲线已冻结，不宣称后台已停止；恢复后自动补读。'));
            if (S.gapNotice) host.appendChild(h('div', { class: 'wb-infobar', style: 'border-left:4px solid #b45309;margin-bottom:10px' }, S.gapNotice));
            if (S.liveErr && runningLike()) host.appendChild(h('div', { class: 'wb-infobar', style: 'border-left:4px solid #b45309;margin-bottom:10px' }, '增量读取异常: ' + S.liveErr + '（保留已有曲线，持续重试）'));
        }
        /** 合并"命令回执刷新 + SSE状态推送"产生的重复补丁,同一轮只渲染一次运行栏。 */
        let patchTimer = null;
        function schedulePatchRunningUi() {
            if (patchTimer) return;
            patchTimer = setTimeout(() => { patchTimer = null; patchRunningUi(); }, 60);
        }
        /** 暂停/继续族状态迁移:就地补丁运行栏、操作条、提示条;不重建主面板、不动 ECharts 实例。 */
        function patchRunningUi() {
            paintBar();
            const live = S.live || {};
            const strip = body.querySelector('[data-afo="op-strip"]');
            // 极端场景:主面板渲染时不可操作(无操作条),之后再进入可操作态,补一次主面板渲染
            if (!strip && S.tab === 'main' && canCmdPhysics()) { paintBody(); return; }
            if (strip) strip.style.display = canCmdPhysics() ? '' : 'none';
            const appliedEl = body.querySelector('[data-afo="applied-text"]');
            if (appliedEl) appliedEl.textContent = '当前采用值与编辑值分开（当前采用: ' + appliedText() + '）';
            const hintEl = body.querySelector('[data-afo="pending-hint"]');
            if (hintEl) hintEl.textContent = pendingHintText(live);
            // 规格3.3:同一时刻只允许一项未生效物理输入,有待生效项时两个"施加"一起禁用
            paintApplyButtons();
            const subEl = body.querySelector('[data-afo="last-submit"]');
            if (subEl) subEl.textContent = lastSubmitText();
            const notice = body.querySelector('.afo-state-notice');
            if (notice) fillStateNotices(notice, live);
            // 命令记录小表就地重建,避免为一条事件重建整个主面板与图表
            const evHost = body.querySelector('[data-afo="events"]');
            if (evHost) { evHost.innerHTML = ''; evHost.appendChild(eventsTable()); }
        }

        /* ---------- 总控页(MS-02) ---------- */
        function paintMain() {
            const ui = uiState();
            // 过渡态优先:准备中只显示阶段横幅,表单不可见不可操作(R138 6.1"准备中:查看阶段与日志")
            if (ui === 'PREPARING') {
                body.appendChild(pageHead('多系统联合仿真·仿真准备'));
                body.appendChild(h('div', { style: 'padding:8px 18px' }, h('div', { class: 'wb-infobar', style: 'display:flex;gap:12px;align-items:center' },
                    h('span', { class: 'wb-inline-loading' }, h('span', { class: 'wb-inline-spinner' })),
                    S.message || '正在准备…(无可靠工作总量,不伪造百分比)')));
                body.appendChild(h('div', { style: 'font-size:12px;color:#94a3b8;padding:4px 18px' },
                    '准备期间不可修改配置;完成后本页显示初态核对与开始入口。'));
                return;
            }
            const idle = ui === 'IDLE' || ui === 'VALIDATE_FAILED';
            body.appendChild(pageHead(idle ? '多系统联合仿真·仿真准备' : '多系统联合仿真·总控与监视'));
            if (idle) { paintPrepare(); return; }
            if (ui === 'READY') { paintPrepare(); return; }
            const host = h('div', { style: 'padding:0 18px 16px' });
            body.appendChild(host);
            // 操纵区(浅色横条两行)
            const live = S.live || {};
            if (canCmdPhysics()) {
                // 规格3.3:有待生效命令或本端提交等待回执时,只禁用物理"施加";编辑框与草稿仍可改
                const locked = physicsLocked();
                S.npDraft = S.npDraft || S.cfg.npRatio || '1';
                const lm = loadMode();
                const strip = h('div', { 'data-afo': 'op-strip', style: 'background:#f0fdf9;border-radius:6px;padding:10px 16px;margin-bottom:14px' });
                const row1 = h('div', { style: 'display:flex;align-items:center;gap:10px;flex-wrap:wrap' },
                    h('span', { style: 'font-weight:600;font-size:14px' }, 'Np挡位'));
                [['0.8', '80%'], ['0.9', '90%'], ['0.95', '95%'], ['1', '100%'], ['1.05', '105%']].forEach(([val, label]) => {
                    row1.appendChild(h('button', {
                        class: 'wb-btn ' + (S.npDraft === val ? 'wb-btn-primary' : 'wb-btn-outline'),
                        // 规格3.3:填写阶段只改草稿,点击前不影响模型;有待生效项时仍可改下一组数值
                        'data-afo': 'np-opt', 'data-np': val,
                        style: 'min-width:0;padding:4px 14px',
                        onclick: () => selectNpDraft(val)
                    }, label));
                });
                row1.appendChild(h('button', {
                    'data-afo': 'apply-np', class: 'wb-btn wb-btn-outline', style: 'padding:4px 16px',
                    disabled: locked ? '' : null,
                    title: locked ? '已有待生效的物理输入命令，暂不能施加' : null,
                    onclick: applyNp
                }, '施加'));
                row1.appendChild(h('span', { style: 'flex:1' }));
                row1.appendChild(h('span', { 'data-afo': 'applied-text', style: 'font-size:13px;color:#0f766e' }, '当前采用值与编辑值分开（当前采用: ' + appliedText() + '）'));
                strip.appendChild(row1);
                const row2 = h('div', { style: 'display:flex;align-items:center;gap:10px;flex-wrap:wrap;margin-top:8px' },
                    h('span', { style: 'font-size:13px' }, '负载：按选定模式填常值 → 施加 → 等待实际生效'));
                const addLoad = (label, mkId, hint) => {
                    // M3:输入框在有待生效命令时保持可编辑(下一组数值),提交由"施加"按钮统一限制
                    const inp = h('input', { value: loadDefault(lm, mkId), id: mkId, style: 'width:150px' });
                    row2.appendChild(h('span', { style: 'display:inline-flex;align-items:center;gap:4px' },
                        h('span', { style: 'font-size:12px;color:#475569' }, label), inp,
                        hint ? h('span', { style: 'font-size:11px;color:#94a3b8' }, hint) : null));
                };
                if (lm === 'power') addLoad('功率', 'afo-load-0', 'kW');
                else if (lm === 'torque') addLoad('扭矩', 'afo-load-0', 'N·m');
                else if (lm === 'pitch') addLoad('总距角', 'afo-load-0', '6~14 deg');
                else { addLoad('主桨', 'afo-load-0', '6~14'); addLoad('尾桨', 'afo-load-1', '−8~18'); }
                row2.appendChild(h('button', {
                    // 规格3.3:输入框在有待生效命令时保持可编辑(下一组数值),提交由"施加"按钮统一限制
                    'data-afo': 'apply-load', class: 'wb-btn wb-btn-outline', style: 'padding:4px 16px',
                    disabled: locked ? '' : null,
                    title: locked ? '已有待生效的物理输入命令，暂不能施加' : null,
                    onclick: () => applyLoad(lm)
                }, '施加'));
                row2.appendChild(h('span', { style: 'flex:1' }));
                row2.appendChild(h('span', { 'data-afo': 'pending-hint', style: 'font-size:13px;color:#334155' }, pendingHintText(live)));
                strip.appendChild(row2);
                // 规格3.3:施加后显示提交编号、请求值和状态;接受≠生效,生效值只认applied回执
                strip.appendChild(h('div', { 'data-afo': 'last-submit', style: 'font-size:12px;color:#475569;margin-top:6px' }, lastSubmitText()));
                host.appendChild(strip);
            }
            // 状态提示条独立宿主:暂停/继续迁移时就地更新,不必重建整个主面板
            const noticeHost = h('div', { class: 'afo-state-notice' });
            fillStateNotices(noticeHost, live);
            host.appendChild(noticeHost);
            // 四图 2×2(效果图 MS-02:轴速/燃油/负载功率/轴承腔出口油温)
            const gr = h('div', { class: 'wb-chart', style: 'display:grid;grid-template-columns:1fr 1fr;gap:8px 22px' });
            host.appendChild(gr);
            [
                { t: '轴速', u: 'rpm', s: [S_('engine_09', { name: 'Np' }), S_('engine_10', { name: 'Ng' })] },
                { t: '燃油', u: 'kg/s', s: [S_('fuel_command_01', { name: '指令' }), S_('fuel_engine_01', { name: '发动机采用' })] },
                { t: '负载功率', u: 'kW', s: [S_('load_05', { name: '实际负载' })] },
                { t: '轴承腔出口油温', u: '℃', s: [S_('oil09_01', { name: '甲腔' }), S_('oil10_01', { name: '乙腔' })] }
            ].forEach(def => splitOneSeries([def]).forEach(d => chartCard(gr, d, isResultMode())));
            host.appendChild(h('div', { style: 'font-size:13px;color:#334155;padding:8px 4px 0' },
                '事件：请求已接受不等于已经施加；按实际生效仿真时间在曲线标记。'));
            // 入口行
            host.appendChild(h('div', { class: 'wb-actions-row', style: 'margin-top:10px' },
                h('button', { class: 'wb-btn wb-btn-outline', onclick: () => { S.tab = '__result'; renderAll(); } }, '结果与历史'),
                h('button', { class: 'wb-btn wb-btn-outline', onclick: () => window.open(excelUrl((S.live && S.live.runId) || S.readonlyRunId || ''), '_blank') }, '📂 导出Excel')));
            // 命令记录
            host.appendChild(h('div', { style: 'font-weight:700;font-size:14px;margin:16px 0 6px' }, '命令记录'));
            const evHost = h('div', { 'data-afo': 'events' });
            evHost.appendChild(eventsTable());
            host.appendChild(evHost);
        }

        /* ---------- 准备页(MS-01:编号分区+通栏表单) ---------- */
        function loadMode() {
            // D2:负载模式以冻结配置为准(服务端恢复),避免运行中刷新后按错误量纲换算
            return (S.cfgFrozen && S.cfgFrozen.loadMode) || (S.result && S.result.config && S.result.config.loadMode) || S.cfg.loadMode;
        }
        function loadDefault(lm, which) {
            const c = S.cfg;
            if (lm === 'power') return c.powerKw;
            if (lm === 'torque') return c.mkpNm;
            if (lm === 'pitch') return c.pitchDeg;
            return which === 'afo-load-1' ? c.tailPitchDeg : c.mainPitchDeg;
        }
        function appliedText() {
            const a = (S.live || {}).applied || [];
            const lm = loadMode();
            if (a[0] == null) return '—';
            let load = '—';
            if (a[1] != null) load = lm === 'power' ? Number(a[1] / 1000).toFixed(2) + ' kW' : lm === 'torque' ? Number(a[1]).toFixed(1) + ' N·m' : Number(a[1]).toFixed(2) + '°';
            return Math.round(a[0]) + ' rpm / ' + load;
        }
        /** 双总距固定映射参数(规格3.1:准备期配置并保存,运行中不热修改):
         *  取冻结配置→live/结果initialConfig→准备表单,缺省兜底与准备页默认一致。 */
        function dualMapping() {
            const srcs = [S.cfgFrozen, (S.live || {}).initialConfig, (S.result || {}).initialConfig, S.cfg];
            let ratio = null, design = null;
            srcs.forEach(x => {
                if (!x) return;
                if (ratio == null && x.tailToMainPowerRatio != null) ratio = parseFloat(x.tailToMainPowerRatio);
                if (design == null && x.tailDesignPitchDeg != null) design = parseFloat(x.tailDesignPitchDeg);
            });
            return { ratio: isFinite(ratio) && ratio >= 0 ? ratio : 0.10, design: isFinite(design) && design > 0 ? design : 10 };
        }
        /** 主尾桨合成等效桨距(与后端 sht_afo_session.m local_equivalent_pitch 公式一致,规格3.1)。 */
        function equivalentPitch(main, tail, ratio, design) {
            const f = 1 / (1 + ratio);
            const gm = 0.15 + 0.85 * Math.pow(main / 12, 1.5);
            const gt = 0.15 + 0.85 * Math.pow(Math.abs(tail / design), 1.5);
            return 12 * Math.pow((f * gm + (1 - f) * gt - 0.15) / 0.85, 2 / 3);
        }
        /** Np草稿选择:只改编辑值不提交(规格3.3"点击之前不影响模型"),就地换高亮避免整页重建。 */
        function selectNpDraft(val) {
            S.npDraft = val;
            body.querySelectorAll('[data-afo="np-opt"]').forEach(b => {
                const on = b.getAttribute('data-np') === String(val);
                b.className = 'wb-btn ' + (on ? 'wb-btn-primary' : 'wb-btn-outline');
            });
        }
        /** Np施加:先检查挡位枚举、再提交;后台接受只入队,生效看applied回执(规格3.3)。 */
        function applyNp() {
            const v = String(S.npDraft);
            if (!['0.8', '0.9', '0.95', '1', '1.05'].includes(v)) { toast('请选择有效的Np挡位（80%/90%/95%/100%/105%）', 'error'); return; }
            sendCmd('np', parseFloat(v));
        }
        async function applyLoad(lm) {
            const e0 = document.getElementById('afo-load-0');
            if (!e0) return;
            const v0 = parseFloat(e0.value);
            if (!isFinite(v0)) { toast('请输入负载数值', 'error'); return; }
            let value;
            if (lm === 'power') {
                if (v0 <= 0) { toast('PT功率须为正数', 'error'); return; }
                value = v0 * 1000; // 界面kW → 程序W
            } else if (lm === 'torque') {
                if (v0 < 0) { toast('扭矩须为非负数', 'error'); return; }
                value = v0;
            } else if (lm === 'pitch') {
                // D6:与后台/程序一致的 6~14 范围,提交前拦截,避免先 accepted 再被拒
                if (!(v0 >= 6 && v0 <= 14)) { toast('总距角须在6~14 deg', 'error'); return; }
                value = v0;
            } else {
                const e1 = document.getElementById('afo-load-1');
                const v1 = e1 ? parseFloat(e1.value) : NaN;
                if (!(v0 >= 6 && v0 <= 14)) { toast('主桨总距角须在6~14 deg', 'error'); return; }
                if (!(v1 >= -8 && v1 <= 18)) { toast('尾桨总距角须在−8~18 deg', 'error'); return; }
                // M2:运行中用冻结配置的映射参数做等效桨距校验(运行中不热修改映射参数),不通过拒绝提交
                const mp = dualMapping();
                const th = equivalentPitch(v0, v1, mp.ratio, mp.design);
                if (!(th >= 6 && th <= 14)) { toast('主尾桨合成等效角' + th.toFixed(2) + '超出现有负载模型6至14度范围', 'error'); return; }
                value = [v0, v1]; // 双桨一次成对提交
            }
            sendCmd('load', value);
        }
        function sectionHead(no, text) {
            return h('div', { style: 'display:flex;align-items:center;gap:12px;margin:18px 0 10px;border-bottom:1px solid #e5e7eb;padding-bottom:6px' },
                h('span', { style: 'font-size:20px;font-weight:800;color:#0f766e' }, no),
                h('span', { style: 'font-size:17px;font-weight:700;color:#0f172a' }, text));
        }
        function formRow(label, ctrl, hint) {
            const row = h('div', { style: 'display:flex;align-items:center;gap:14px;margin-bottom:10px' },
                h('div', { style: 'width:150px;text-align:right;font-size:14px;color:#334155;flex:none' }, label),
                h('div', { style: 'flex:1;max-width:820px' }, ctrl));
            if (hint) row.appendChild(h('div', { style: 'font-size:12px;color:#94a3b8;width:180px;flex:none' }, hint));
            return row;
        }
        function paintPrepare() {
            // READY=配置已随准备冻结(R138 3.2:分母来自通过校验后冻结的配置;Java会话配置同为prepare值)
            // → 就绪态表单只读,防止"界面改了、实际没生效";修改须放弃并关闭后重新准备
            const ro = uiState() === 'READY';
            const host = h('div', { style: 'padding:0 24px 20px;max-width:1080px' });
            body.appendChild(host);
            if (ro) {
                host.appendChild(h('div', { class: 'wb-infobar', style: 'border-left:4px solid #0f766e;margin-bottom:6px' },
                    '已就绪：以下配置已随准备校验冻结（进度分母与会话配置同源）。如需修改，请“放弃并关闭”后重新准备。'));
            }
            host.appendChild(sectionHead('1', '选择配套模型'));
            host.appendChild(h('div', { style: 'font-size:16px;font-weight:600' }, 'AFO_V_2　Dll_Control_AFO_V8_5_R2019b.slx'));
            host.appendChild(h('div', { style: 'font-size:13px;color:#0f766e;margin-top:4px' },
                '配套DLL与模型身份已核对 · 使用独立工作副本 · 发动机 ' + (S.cfg.engineId || ctx.project.engineId || 'ENGINE-001')));
            host.appendChild(sectionHead('2', '配置本次运行'));
            const c = S.cfg;
            const f = {};
            const inp = (key) => {
                f[key] = h('input', {
                    value: c[key], readOnly: ro ? '' : null,
                    style: 'width:100%;box-sizing:border-box;background:' + (ro ? '#eef2f7' : '#f8fafc')
                        + ';border:1px solid #e2e8f0;border-radius:4px;padding:7px 10px'
                });
                f[key].addEventListener('input', e => { c[key] = e.target.value; }); // 回写状态:整页重绘(Np切换)不丢输入
                return f[key];
            };
            const sel = (options, value, onch) => {
                const s = h('select', { style: 'width:100%;background:' + (ro ? '#eef2f7' : '#f8fafc')
                    + ';border:1px solid #e2e8f0;border-radius:4px;padding:7px 10px', disabled: ro ? '' : null },
                    options.map(([v, l]) => h('option', { value: v, selected: value === v ? '' : null }, l)));
                if (onch) s.addEventListener('change', e => onch(e.target.value));
                return s;
            };
            host.appendChild(formRow('终止时间', inp('duration'), '秒;正数,运行中固定'));
            host.appendChild(formRow('记录周期', inp('recordStep'), '0.025 s 整数倍,默认 0.1'));
            host.appendChild(formRow('运行速度', sel([['realtime', '实时节奏'], ['fast', '尽快计算']], c.pace, v => { c.pace = v; })));
            host.appendChild(formRow('Np挡位', (() => {
                const g = h('div', { style: 'display:flex;gap:8px' });
                [['0.8', '80%'], ['0.9', '90%'], ['0.95', '95%'], ['1', '100%'], ['1.05', '105%']].forEach(([v, l]) => {
                    g.appendChild(h('button', {
                        class: 'wb-btn ' + (c.npRatio === v ? 'wb-btn-primary' : 'wb-btn-outline'), style: 'padding:5px 16px',
                        disabled: ro ? '' : null,
                        onclick: () => { if (ro) return; c.npRatio = v; renderAll(); }
                    }, l));
                });
                return g;
            })(), '相对设计参考转速'));
            const loadSel = sel([['power', '功率'], ['torque', '扭矩'], ['pitch', '单总距'], ['dual_pitch', '主尾桨双总距']], c.loadMode, v => { c.loadMode = v; });
            host.appendChild(formRow('负载模式', loadSel, '准备后固定,只允许改数值'));
            const loadBox = h('div', { style: 'display:flex;gap:12px;margin:-4px 0 10px 164px;flex-wrap:wrap' });
            const paintLoad = () => {
                loadBox.innerHTML = '';
                const mk = (label, key, hint) => {
                    f[key] = h('input', { value: c[key], readOnly: ro ? '' : null, style: 'width:180px;background:'
                        + (ro ? '#eef2f7' : '#f8fafc') + ';border:1px solid #e2e8f0;border-radius:4px;padding:6px 10px' });
                    f[key].addEventListener('input', e => { c[key] = e.target.value; });
                    loadBox.appendChild(h('span', { style: 'display:inline-flex;align-items:center;gap:6px' },
                        h('span', { style: 'font-size:13px;color:#475569' }, label), f[key],
                        hint ? h('span', { style: 'font-size:11px;color:#94a3b8' }, hint) : null));
                };
                const lm = loadSel.value;
                if (lm === 'power') mk('PT功率', 'powerKw', 'kW,发送前转W');
                else if (lm === 'torque') mk('扭矩', 'mkpNm', 'N·m');
                else if (lm === 'pitch') mk('总距角', 'pitchDeg', '6~14 deg');
                else {
                    mk('主桨总距角', 'mainPitchDeg', '6~14 deg');
                    mk('尾桨总距角', 'tailPitchDeg', '−8~18 deg,成对提交');
                    // M2(规格3.1):双总距固定映射参数,准备期配置保存,运行中不热修改
                    mk('尾/主桨功率比', 'tailToMainPowerRatio', '默认0.10');
                    mk('尾桨设计总距', 'tailDesignPitchDeg', 'deg,默认10');
                    loadBox.appendChild(h('div', { style: 'flexBasis:100%;font-size:12px;color:#94a3b8;margin-top:2px' },
                        '主尾桨按工程映射合成等效负载：主桨6~14 deg、尾桨−8~18 deg，合成等效桨距须在6~14 deg内；映射参数准备后固定，运行中不可修改。'));
                }
            };
            paintLoad();
            loadSel.addEventListener('change', paintLoad);
            host.appendChild(loadBox);
            host.appendChild(formRow('外部空气回灌', sel([['internal', '关闭 · 空气系统仍计算输出'], ['external', '外部8路回灌（经一步延迟生效）']], c.externalAir ? 'external' : 'internal', v => { c.externalAir = v === 'external'; })));
            host.appendChild(formRow('实时发布', sel([['on', '开启 · 运行时增量曲线'], ['off', '关闭 · 仍完整计算并导出Excel']], c.publishLive ? 'on' : 'off', v => { c.publishLive = v === 'on'; })));
            // 任务编号输入框已按 UI_R138 移除:MS-01 准备页无此字段,规格定位 runId 为
            // 系统生成的运行标识(运行栏展示;历史复用"新建运行"时生成新编号),不由用户手填。
            // 曾因此输入框被旧 runId 预填,导致第二次准备撞"结果目录已存在"失败。
            // D12:输出目录只读展示(会话结果/status/inbox 落盘位置;来自 /status.outputDir 或结果 config)
            const outDir = S.statusOutputDir || (S.result && S.result.config && S.result.config.outputDir)
                || (S.cfgFrozen && S.cfgFrozen.outputDir) || '';
            host.appendChild(formRow('输出目录',
                h('div', { style: 'width:100%;box-sizing:border-box;background:#eef2f7;border:1px solid #e2e8f0;border-radius:4px;padding:7px 10px;font-size:13px;color:#475569;overflow-wrap:anywhere' },
                    outDir || '准备完成后生成（会话输出目录）'),
                '只读;结果/状态/命令通道'));
            host.appendChild(sectionHead('3', '核对初态与目标'));
            host.appendChild(h('div', { style: 'font-size:14px;line-height:1.9' },
                '初始Np、Ng及子系统初态：从配套模型读取，不在准备页虚构数值。',
                h('br'), '目标不同于初态时，会发生过渡；勾选确认后再开始。'));
            host.appendChild(h('div', { style: 'font-size:14px;color:#b45309;margin-top:6px' },
                '此入口不提供任意工况自动配平、冷起动或断进程续算。'));
            if (uiState() === 'READY' || uiState() === 'PREPARING') {
                // 初态事实(R065):准备时由配套模型读取并校验(initialState/initialOutput),
                // 但 status.json 首次写入在第一个记录点——READY 时刻外部拿不到初值,
                // 此处只显示配置目标(真实)与来源说明,不虚构初值(R138 3.1)。
                const live = S.live || {};
                const v0 = live.values || [];
                const eng = v0[0] || [];
                const hasInit = eng.length > 0;
                const lm = c.loadMode;
                const goal = lm === 'power' ? Number(c.powerKw).toFixed(1) + ' kW'
                    : lm === 'torque' ? Number(c.mkpNm).toFixed(1) + ' N·m'
                    : lm === 'pitch' ? Number(c.pitchDeg).toFixed(1) + '°'
                    : Number(c.mainPitchDeg).toFixed(1) + '° / ' + Number(c.tailPitchDeg).toFixed(1) + '°（主/尾）';
                host.appendChild(h('div', { style: 'margin-top:10px' }, h('table', { class: 'wb-table' },
                    h('tr', null, ['目标Np挡位', '目标负载', '初态来源', '实际初值'].map(x => h('th', null, x))),
                    h('tr', null,
                        h('td', null, Math.round(parseFloat(c.npRatio) * 100) + '%'),
                        h('td', null, goal),
                        h('td', { class: 'wb-hint' }, '配套模型读取并校验（initialState）'),
                        h('td', { class: 'wb-hint' }, hasInit
                            ? (eng[8] != null ? Math.round(eng[8]) + ' rpm' : '—')
                            : '开始计算后首个记录点出现（约0.1 s）')))));
            }
            const transRow = h('div', { style: 'display:flex;align-items:center;gap:8px;margin-top:12px' },
                h('input', { type: 'checkbox', id: 'afo-trans', disabled: ro ? '' : null, checked: c.initialTransitionConfirmed ? '' : null }),
                h('span', { style: 'font-size:13px' }, '我已知晓：目标不同于初态将出现过渡过程；允许过渡 ≠ 已求得目标状态配平值'));
            host.appendChild(transRow);
            const btnRow = h('div', { style: 'display:flex;justify-content:flex-end;gap:10px;margin-top:16px' },
                h('button', { class: 'wb-btn wb-btn-outline', onclick: () => { S.tab = '__result'; renderAll(); } }, '查看历史仿真记录'));
            if (!ro) {
                // 提交流程:先同步校验(失败留在表单),随后立即进入"准备中"过渡态锁界面,失败再回退
                btnRow.appendChild(h('button', {
                    class: 'wb-btn wb-btn-primary', style: 'min-width:200px;height:42px;font-size:16px',
                    onclick: async (ev) => {
                        const btn = ev.currentTarget;
                        if (S._prepBusy || uiState() === 'PREPARING') return; // 防重入
                        S._prepBusy = true;
                        btn.classList.add('disabled');
                        try {
                            const np0 = c.npRatio;
                            const step = parseFloat(f.recordStep.value);
                            const dur = parseFloat(f.duration.value);
                            const trans = document.getElementById('afo-trans').checked;
                            if (!isFinite(dur) || dur <= 0) throw new Error('终止时间须为正数');
                            // M1:终止时间对齐固定步长网格,与服务端 SimTimeUtil.alignToStep 约定一致
                            if (Math.abs(dur / 0.025 - Math.round(dur / 0.025)) >= 1e-9) throw new Error('终止时间需为0.025 s计算网格的整数倍');
                            if (!isFinite(step) || step <= 0) throw new Error('记录周期须为正数');
                            if (Math.abs(step / 0.025 - Math.round(step / 0.025)) > 1e-6) throw new Error('记录周期须为0.025 s整数倍(当前 ' + step + ')');
                            if (np0 !== '1' && !trans) throw new Error('Np初值挡位≠100%(与配套初态不同),请先勾选初态确认');
                            const req = {
                                engineId: c.engineId || ctx.project.engineId || 'ENGINE-001',
                                duration: dur, recordStep: step, pace: c.pace, loadMode: loadSel.value,
                                npRatio: parseFloat(np0), externalAir: c.externalAir,
                                publishLive: c.publishLive, plots: false, initialTransitionConfirmed: trans
                            };
                            const lm = loadSel.value;
                            if (lm === 'power') {
                                const kw = parseFloat(f.powerKw.value);
                                if (!isFinite(kw) || kw <= 0) throw new Error('PT功率须为正数');
                                req.powerW = kw * 1000;
                            } else if (lm === 'torque') {
                                const v = parseFloat(f.mkpNm.value);
                                if (!isFinite(v) || v <= 0) throw new Error('扭矩须为正数');
                                req.mkpNm = v;
                            } else if (lm === 'pitch') {
                                const v = parseFloat(f.pitchDeg.value);
                                // D6:单总距与后台/程序一致的 6~14 范围,提交前拦截
                                if (!isFinite(v)) throw new Error('总距角须为数值');
                                if (!(v >= 6 && v <= 14)) throw new Error('总距角须在6~14 deg');
                                req.pitchDeg = v;
                            } else {
                                const m = parseFloat(f.mainPitchDeg.value), t2 = parseFloat(f.tailPitchDeg.value);
                                if (!(m >= 6 && m <= 14)) throw new Error('主桨总距角须在6~14 deg');
                                if (!(t2 >= -8 && t2 <= 18)) throw new Error('尾桨总距角须在−8~18 deg');
                                // M2(规格3.1):双总距固定映射参数随准备提交;合成等效桨距校验与后端一致
                                const tr = parseFloat(f.tailToMainPowerRatio ? f.tailToMainPowerRatio.value : c.tailToMainPowerRatio);
                                const td = parseFloat(f.tailDesignPitchDeg ? f.tailDesignPitchDeg.value : c.tailDesignPitchDeg);
                                if (!isFinite(tr) || tr < 0) throw new Error('尾/主桨功率比须为非负数');
                                if (!isFinite(td) || td <= 0) throw new Error('尾桨设计总距须为正数(deg)');
                                const th = equivalentPitch(m, t2, tr, td);
                                if (!(th >= 6 && th <= 14)) throw new Error('主尾桨合成等效角' + th.toFixed(2) + '超出现有负载模型6至14度范围');
                                req.tailToMainPowerRatio = tr; req.tailDesignPitchDeg = td;
                                req.mainPitchDeg = m; req.tailPitchDeg = t2;
                            }
                            // 不传 runId:由服务端自动生成新编号(UI_R138,runId非用户输入)
                            // 回写仅读当前模式实际渲染的输入;未渲染模式回退到既有状态值
                            const fv = k => (f[k] && f[k].value != null) ? f[k].value : (c[k] != null ? String(c[k]) : '');
                            S.cfg = Object.assign({}, S.cfg, {
                                engineId: req.engineId, duration: dur, recordStep: step, pace: req.pace,
                                loadMode: lm, powerKw: fv('powerKw'), mkpNm: fv('mkpNm'), pitchDeg: fv('pitchDeg'),
                                mainPitchDeg: fv('mainPitchDeg'), tailPitchDeg: fv('tailPitchDeg'),
                                // M2:双总距固定映射参数写入本地配置(随 prepare 请求原样透传给程序)
                                tailToMainPowerRatio: fv('tailToMainPowerRatio'), tailDesignPitchDeg: fv('tailDesignPitchDeg'),
                                externalAir: req.externalAir, npRatio: np0, runId: '',
                                publishLive: req.publishLive, initialTransitionConfirmed: trans
                            });
                            // 乐观过渡态:点击即锁界面,失败回退(R138 6.1"准备中"不可操作)
                            S.phase = 'PREPARING';
                            S.message = '准备运行副本(校验配套身份与初态)';
                            // 新会话数据通道复位:上次运行可能残留 pull 模式/未关连接,
                            // 不清会导致 refresh 的 startLiveChannel 被 streamMode!=='pull' 永久拦截,
                            // 运行期 S.live 零更新(状态SSE无chg)→进度条不动直到结束
                            stopLiveChannel(); S.streamMode = '';
                            S.liveBuf = null; S.sessionId = null; S.catalog = null; S.byId = null;
                            S.dispIds = null; S.dispPos = null; S.liveCols = null; S.gapNotice = ''; S.liveErr = '';
                            renderAll();
                            const resp = await apiPost('/prepare', req);
                            if (!(resp && (resp.success || resp.code === 200))) throw new Error((resp && resp.message) || '准备发起失败');
                            if (resp.data && resp.data.phase) S.phase = resp.data.phase;
                            S.message = '准备运行副本(校验配套身份与初态)';
                            toast('准备已发起;运行副本与模型初始化需要一些时间', 'info');
                        } catch (e) {
                            S.phase = 'IDLE'; S.message = ''; // 失败回退,表单恢复可编辑
                            toast('准备失败:' + e.message, 'error');
                        }
                        S._prepBusy = false;
                        btn.classList.remove('disabled');
                        renderAll();
                        startLoops();
                    }
                }, '检查并准备运行'));
            }
            host.appendChild(btnRow);
        }

        /* ---------- 结果与历史(MS-08入口) ---------- */
        function paintResultTab() {
            refreshAcc();
            body.appendChild(pageHead('结果与历史'));
            const host = h('div', { style: 'padding:0 18px 16px' });
            body.appendChild(host);
            if (S.result && ((resultAcc && resultAcc.time.length) || S.result.phase === 'FAILED' || S.result.readonlyFailed)) {
                const r = S.result, t = r.timing || {};
                const runId = S.readonlyRunId || (S.live && S.live.runId);
                const failed = r.phase === 'FAILED' || r.readonlyFailed === true || String(r.state || '').toLowerCase() === 'failed';
                host.appendChild(h('div', { style: 'font-weight:700;font-size:15px;margin-bottom:6px' }, '结果摘要'));
                const early = r.stopReason === 'user_ended_computation';
                // D5:按 live.saveState 区分等待保存/正在保存/已保存/保存失败;只读历史以结果文件为准
                const ss = (S.live || {}).saveState;
                const saveTxt = S.readonlyRunId ? '已保存（历史结果）'
                    : ss === 'failed' ? h('span', { style: 'color:#b91c1c' }, '保存失败:' + ((S.live || {}).saveError || '') + '(可重试,不重新仿真)')
                    : ss === 'saved' ? '已保存'
                    : ss === 'writing' ? '正在保存…'
                    : '等待保存（计算结束后执行）';
                // 结束原因:失败给"异常首行+末尾原因"摘要并提供完整报告入口;正常结束把机器码翻成中文
                let reasonNode;
                if (failed) {
                    reasonNode = h('div', { style: 'white-space:pre-wrap;overflow-wrap:anywhere' }, r.stopReason || r.error || '—');
                    if (r.error) reasonNode.appendChild(h('div', { style: 'margin-top:4px' },
                        h('button', { class: 'wb-btn wb-btn-outline', style: 'font-size:12px;padding:1px 8px;line-height:1.4', onclick: () => openFailLogModal(String(r.error)) }, '查看完整失败日志')));
                } else {
                    const reasonTxt = early ? '提前结束(用户结束计算;不强制100%)'
                        : r.stopReason === 'time_limit' ? '达到目标终止时间'
                        : (r.stopReason || '达到目标终止时间');
                    reasonNode = h('div', { style: 'white-space:pre-wrap;overflow-wrap:anywhere' }, reasonTxt);
                }
                host.appendChild(h('table', { class: 'wb-table' },
                    h('tr', null, ['最终仿真时间', '目标终止时间', '结束原因', '样本数', '保存状态'].map(x => h('th', null, x))),
                    h('tr', null,
                        h('td', null, Number(r.finalSimulationTime != null ? r.finalSimulationTime : ((r.time && r.time.length) ? r.time[r.time.length - 1] : 0)).toFixed(3) + ' s'),
                        h('td', null, Number((r.config && r.config.duration) || 0).toFixed(2) + ' s'),
                        h('td', { style: 'max-width:420px' }, reasonNode),
                        h('td', null, String((r.time || []).length)),
                        h('td', null, saveTxt))));
                host.appendChild(h('div', { style: 'font-weight:700;font-size:15px;margin:12px 0 6px' }, '耗时口径（计算结束后的管理等待不计入运行墙钟）'));
                host.appendChild(h('table', { class: 'wb-table' },
                    h('tr', null, ['准备', '运行墙钟', '人工暂停', '实时节奏等待', '计算及服务'].map(x => h('th', null, x))),
                    h('tr', null, [t.prepare, t.runWall, t.humanPause, t.paceWait, t.computeAndService]
                        .map(v => h('td', null, v == null ? '—' : Number(v).toFixed(1) + ' s')))));
                const acts = h('div', { class: 'wb-actions-row', style: 'margin-top:10px' });
                if (runId) acts.appendChild(h('button', { class: 'wb-btn wb-btn-outline', onclick: () => window.open(excelUrl(runId), '_blank') }, '📂 导出Excel(272原始+4派生)'));
                if ((S.live && S.live.saveState) === 'failed') acts.appendChild(h('button', { class: 'wb-btn wb-btn-outline', onclick: retrySave }, '重试保存(原进程,不重新仿真)'));
                if (S.readonlyRunId) {
                    acts.appendChild(h('button', { class: 'wb-btn wb-btn-primary', onclick: () => reuseFrom('initial') }, '用此配置新建运行(初始配置)'));
                    acts.appendChild(h('button', { class: 'wb-btn wb-btn-outline', onclick: () => reuseFrom('final') }, '用此配置新建运行(最终配置)'));
                }
                host.appendChild(acts);
                host.appendChild(h('div', { class: 'wb-hint', style: 'margin:6px 0 12px' },
                    '历史读取不启动MATLAB/DLL;R06旧结果缺新增25项显示“本结果未记录”,不填零。'));
                host.appendChild(h('div', { class: 'wb-hint', style: 'margin:0 0 12px' },
                    '回退标志说明（G04温度/压力、混温A/B，共4项）在导出Excel的Data列中，用于标识某段计算使用了回退逻辑；属数据解释状态，不等同超限告警。'));
                host.appendChild(h('div', { style: 'font-weight:700;font-size:15px;margin-bottom:6px' }, '命令记录'));
                host.appendChild(eventsTable());
            } else {
                host.appendChild(h('div', { class: 'wb-infobar' }, '当前会话尚无结果;运行结束保存后此处显示结果摘要。'));
            }
            // 历史列表(只保留条数选择,取最新 N 条;查询复用仿真记录的 SQL 记录查询接口 kind=afo)
            let histSize = S.histSize || 10;
            const listHost = h('div');
            const headBox = h('div', { class: 'wb-section-head', style: 'margin:16px 0 6px' },
                h('div', { style: 'font-weight:700;font-size:15px' }, '历史会话(只读)'),
                h('div', { style: 'display:flex;align-items:center;gap:6px' },
                    h('span', { class: 'wb-hint', style: 'margin:0' }, '最新'),
                    h('select', {
                        title: '最新显示条数',
                        onchange: (e) => { histSize = parseInt(e.target.value, 10) || 10; S.histSize = histSize; fetchHistory(); }
                    }, [10, 20, 50].map(n => h('option', Object.assign({ value: String(n) }, n === histSize ? { selected: '' } : {}), n + ' 条')))));
            host.appendChild(headBox);
            host.appendChild(listHost);
            function fetchHistory() {
                listHost.innerHTML = '';
                listHost.appendChild(h('div', { class: 'wb-hint' }, '历史会话加载中...'));
                api('/sessions/list', { kind: 'afo', pageNum: 1, pageSize: histSize }).then(resp => {
                    listHost.innerHTML = '';
                    const list = (resp && (resp.success || resp.code === 200) && Array.isArray(resp.data)) ? resp.data : [];
                    if (!list.length) { listHost.appendChild(h('div', { class: 'wb-hint' }, '暂无历史会话')); return; }
                    const tbl = h('table', { class: 'wb-table' },
                        h('tr', null, ['运行编号', '状态', '创建时间', '结果', 'Excel', '操作'].map(x => h('th', null, x))));
                    list.forEach(ses => {
                        const rid = ses.runId;
                        tbl.appendChild(h('tr', null,
                            h('td', null, rid),
                            h('td', null, h('span', { class: 'wb-tag wb-tag-' + (ses.phase === 'ENDED' ? 'teal' : ses.phase === 'FAILED' ? 'red' : 'gray') }, ses.phase || '—')),
                            h('td', { class: 'wb-hint' }, ses.createdAt ? new Date(ses.createdAt).toLocaleString() : '—'),
                            h('td', null, ses.hasResult ? '√' : '—'),
                            h('td', null, ses.hasExcel ? '√' : '—'),
                            h('td', null, h('div', { style: 'display:flex;gap:6px' },
                                h('button', {
                                    class: 'wb-btn wb-btn-outline', style: 'font-size:12px;padding:2px 10px',
                                    disabled: ses.hasResult ? null : '',
                                    onclick: () => ses.hasResult && loadReadonly(rid)
                                }, '打开(只读)'),
                                (S.result && S.readonlyRunId && rid !== S.readonlyRunId && ses.hasResult) ? h('button', {
                                    class: 'wb-btn wb-btn-outline', style: 'font-size:12px;padding:2px 10px',
                                    onclick: () => loadCompare(rid)
                                }, '作为对比') : null))));
                    });
                    listHost.appendChild(tbl);
                }).catch(e => {
                    listHost.innerHTML = '';
                    listHost.appendChild(h('div', { class: 'wb-hint' }, '历史列表读取失败:' + e.message));
                });
            }
            fetchHistory();
            if (S.compare) paintCompareBar(host);
        }
        /** D7:模型/资产身份摘要(name@sha前8位),用于比较页披露。 */
        function identitySummary(r) {
            const ids = (r && r.identity) || [];
            if (!ids.length) return '—';
            return ids.map(it => {
                const nm = String((it && it.name) || '');
                const sha = String((it && it.sha256) || '').slice(0, 8);
                return nm + (sha ? '@' + sha : '');
            }).join('；');
        }
        /** D7:因单位不一致未叠加的曲线清单(以两份结果文件内字典为准,并合并渲染时记录的 _cmpSkipped)。 */
        function cmpUnitMismatchList() {
            const names = new Set();
            const ca = S.result && S.result.catalog;
            if (Array.isArray(ca) && S.compare) {
                ca.forEach(c => {
                    if (!c || c.unit == null) return;
                    const ub = compareUnitOf(c.id);
                    if (ub && ub !== c.unit) names.add((chById(c.id) && chById(c.id).name) || c.id);
                });
            }
            (S._cmpSkipped || new Set()).forEach(id => names.add((chById(id) && chById(id).name) || id));
            return Array.from(names);
        }
        function paintCompareBar(host) {
            const b = S.compare;
            const box = h('div', { style: 'margin-top:10px;background:#f8fafc;border:1px solid #e5e7eb;border-radius:6px;padding:10px 12px' });
            box.appendChild(h('div', { style: 'font-weight:700;margin-bottom:6px;display:flex;gap:10px;align-items:center' },
                '运行比较: ' + S.readonlyRunId + ' ↔ ' + b.runId,
                h('button', {
                    class: 'wb-btn ' + (S.compareOverlay ? 'wb-btn-primary' : 'wb-btn-outline'),
                    style: 'font-size:12px;padding:2px 10px',
                    onclick: () => { S.compareOverlay = !S.compareOverlay; renderAll(); }
                }, S.compareOverlay ? '✓ 各系统页叠加对比曲线' : '叠加对比曲线'),
                h('button', { class: 'wb-btn wb-btn-outline', style: 'font-size:12px;padding:2px 10px', onclick: () => { S.compare = null; S.compareOverlay = false; renderAll(); } }, '移除比较')));
            const ca = S.result.config || {}, cb = b.result.config || {};
            const tbl = h('table', { class: 'wb-table', style: 'font-size:12px' }, h('tr', null, ['配置项', '本运行', '对比运行'].map(x => h('th', null, x))));
            [['负载模式', ca.loadMode, cb.loadMode], ['空气回灌', ca.externalAir ? '外部' : '内部', cb.externalAir ? '外部' : '内部'],
             ['终止时间', ca.duration, cb.duration], ['记录周期', ca.recordStep, cb.recordStep]].forEach(([k, va, vb]) => {
                tbl.appendChild(h('tr', null, h('td', null, k), h('td', null, String(va)),
                    h('td', { style: String(va) !== String(vb) ? 'color:#b45309;font-weight:600' : '' }, String(vb))));
            });
            // D7:披露模型/资产身份(identity: name@sha256前8位),避免把不同资产当成同源比较
            tbl.appendChild(h('tr', null, h('td', null, '模型/资产身份'),
                h('td', { style: 'max-width:520px;overflow-wrap:anywhere' }, identitySummary(S.result)),
                h('td', { style: 'max-width:520px;overflow-wrap:anywhere;color:' + (identitySummary(S.result) !== identitySummary(b.result) ? '#b45309' : '') }, identitySummary(b.result))));
            box.appendChild(tbl);
            box.appendChild(h('div', { class: 'wb-hint', style: 'margin-top:4px' }, '采样网格不同则各自按原曲线叠加,不插值不外插。'));
            // D7:显性展示"因单位不一致未叠加"的曲线清单(原 _cmpSkipped 从未渲染)
            const skipped = cmpUnitMismatchList();
            box.appendChild(h('div', { class: 'wb-hint', style: 'margin-top:4px;color:' + (skipped.length ? '#b45309' : '#64748b') },
                skipped.length ? ('因单位不一致未叠加（' + skipped.length + '项）：' + skipped.join('、'))
                    : '单位核对：未发现因单位不一致而未叠加的曲线。'));
            host.appendChild(box);
        }
        async function loadCompare(runId) {
            try {
                const resp = await api('/sessions/' + encodeURIComponent(runId) + '/result');
                if (!(resp && (resp.success || resp.code === 200) && resp.data)) throw new Error((resp && resp.message) || '结果尚未生成');
                S.compare = { runId, result: resp.data };
                S._cmpUnits = null; S._cmpSkipped = new Set();
                toast('对比运行已加载:' + runId, 'success');
                renderAll();
            } catch (e) { toast('加载对比失败:' + e.message, 'error'); }
        }
        function compareAcc() {
            return (S.compare && S.compare.result && S.compareOverlay) ? resultAccessor(S.compare.result) : null;
        }

        /* ---------- 渲染 ---------- */
        /** 编译期 loading 遮罩:盖住页签+图表区,图表照常提前渲染,首帧样本到达后摘除消失。 */
        function compileOverlay() {
            const ov = h('div', {
                class: 'afo-compile-overlay',
                style: 'position:absolute;left:0;right:0;top:0;bottom:0;z-index:20;'
                    + 'background:rgba(248,250,252,.85);display:flex;align-items:flex-start;justify-content:center'
            });
            const card = h('div', {
                style: 'margin-top:96px;padding:22px 34px;border:1px solid #e2e8f0;border-radius:10px;background:#fff;'
                    + 'box-shadow:0 4px 18px rgba(15,23,42,.08);text-align:center;min-width:300px'
            });
            card.appendChild(h('div', { style: 'font-size:15px;font-weight:700;color:#0f766e' }, '模型编译初始化中'));
            const track = h('div', {
                style: 'margin:14px auto 0;width:240px;height:6px;background:#e2e8f0;border-radius:3px;position:relative;overflow:hidden'
            });
            track.appendChild(h('div', {
                style: 'position:absolute;top:0;bottom:0;width:32%;border-radius:3px;'
                    + 'background:linear-gradient(90deg,#0e7490,#22d3ee);animation:afoIndet 1.4s ease-in-out infinite'
            }));
            card.appendChild(track);
            card.appendChild(h('div', { style: 'margin-top:12px;font-size:12px;color:#64748b' },
                '正在编译模型与加载求解器（通常 1~2 分钟），首帧样本到达后自动进入计算'));
            ov.appendChild(card);
            return ov;
        }
        function paintBody() {
            killCharts();
            if (S.readonlyLoading) {
                body.innerHTML = '';
                body.appendChild(h('div', { class: 'wb-empty' }, '正在加载历史结果(不启动MATLAB/DLL)…'));
                return;
            }
            // 编译期:图表照常提前渲染(空态),上面盖一个 loading 遮罩;同一页签已渲染则保持,避免轮询重启动画
            const chartTab = (S.tab === 'main' || sysOfTab[S.tab]);
            const compiling = chartTab && isCompiling() && !S.readonlyRunId;
            if (compiling && body.dataset.compile === '1' && body.dataset.compileTab === S.tab) return;
            delete body.dataset.compile;
            delete body.dataset.compileTab;
            body.innerHTML = '';
            refreshAcc();
            if (S.tab === 'main') paintMain();
            else if (S.tab === '__result') paintResultTab();
            else {
                const sys = sysOfTab[S.tab];
                if (sys) paintSystemTab(sys);
            }
            if (compiling) {
                body.dataset.compile = '1';
                body.dataset.compileTab = S.tab;
                midHost.appendChild(compileOverlay());
            }
        }
        /** 编译期结束(首帧样本到达):只摘 loading 遮罩并刷新运行栏/曲线,图表实例保持,不整页重建。 */
        function exitCompileOverlay() {
            delete body.dataset.compile;
            delete body.dataset.compileTab;
            const ov = midHost.querySelector('.afo-compile-overlay');
            if (ov) ov.remove();
            paintBar();
        }
        function paintBar() {
            hideFailTip(); // 运行栏重建时收起悬停浮窗,避免残留
            barHost.innerHTML = '';
            if (uiState() !== 'IDLE' && uiState() !== 'VALIDATE_FAILED') barHost.appendChild(runBar());
        }
        function renderAll() {
            if (patchTimer) { clearTimeout(patchTimer); patchTimer = null; } // 全量渲染后丢弃挂起的局部补丁
            paintBar();
            paintTabs();
            paintBody();
        }
        function lightUpdate() {
            paintBar();
            const ae = document.activeElement;
            const editing = ae && (ae.tagName === 'INPUT' || ae.tagName === 'SELECT') && body.contains(ae);
            if (editing) return;
            if ((S.tab === 'main' || sysOfTab[S.tab]) && (runningLike() || uiState() === 'ENDED')) {
                paintBody();
                refreshRuntimeCharts();
            }
        }

        /* ---------- 动作 ---------- */
        async function sendCmd(kind, value) {
            const physical = kind === 'np' || kind === 'load';
            // D8:实例失联时禁止把暂停/继续/结束写进无人消费的 inbox 队列
            if (S.procLost && ['pause', 'resume', 'stop'].includes(kind)) {
                toast('该实例不能续算：进程心跳已停止，命令不会写入无人消费的队列', 'error'); return;
            }
            // 规格3.3:同一时刻只允许一项未生效物理输入;暂停/继续/结束计算不受此占位限制
            if (physical && physicsLocked()) { toast('已有待生效的物理输入命令，暂不能施加', 'info'); return; }
            if (physical) { S.applyBusy = true; paintApplyButtons(); schedulePatchRunningUi(); } // 提交在途期间同步锁住两个"施加"
            try {
                // R138 6.2禁重复提交:暂停/继续请求已在途时忽略同Kind命令(防连点造成多重请求)
                if (kind === 'pause' && uiState() === 'PAUSE_REQ') { toast('暂停请求已在处理中,请等待安全响应点', 'info'); return; }
                if (kind === 'resume' && uiState() === 'RESUME_REQ') { toast('继续请求已在处理中', 'info'); return; }
                if (kind === 'stop' && uiState() === 'STOP_REQ') { toast('结束请求已在处理中', 'info'); return; }
                const resp = await apiPost('/command', { kind, value });
                // D13:后端在写 inbox 前校验 Np/负载范围;拒收时不再提示"已提交",直接显示原因
                if (resp && (resp.success === false || (resp.code != null && Number(resp.code) !== 200))) {
                    toast('命令被拒绝:' + (resp.message || '参数不合法'), 'error'); return;
                }
                const rd = (resp && (resp.data || resp)) || {};
                if (physical) {
                    // 规格3.3:记录提交编号/请求值;状态由后台pending/events回执驱动,不本地伪造生效
                    S.lastSubmit = { id: rd.id ? String(rd.id) : '', kind, value, at: Date.now() };
                }
                if (kind === 'resume') { S.localResume = true; S.pauseReqAt = null; }
                if (kind === 'pause') { S.localResume = false; S.pauseReqAt = Date.now(); } // L3:30s延迟提示计时起点
                if (kind === 'stop') S.pauseReqAt = null;
                toast(kind === 'pause' ? '暂停请求已提交,等待安全响应点' : kind === 'resume' ? '继续请求已提交' :
                    kind === 'stop' ? '结束请求已提交;不强杀进程'
                        : '命令已提交' + (S.lastSubmit && S.lastSubmit.id ? '（' + S.lastSubmit.id + '）' : '') + ';实际生效以回执为准', 'info');
                refresh(); if (S.streamMode !== 'sse') quickPoll();
            } catch (e) { toast('命令失败:' + e.message, 'error'); }
            finally {
                if (physical) { S.applyBusy = false; paintApplyButtons(); schedulePatchRunningUi(); }
            }
        }
        async function startRun() {
            try {
                S.applyBusy = false; S.lastSubmit = null; S.npDraft = null; // 新会话:清上一次的提交回执与草稿
                await apiPost('/run', {});
                toast('仿真已启动', 'success');
                startLoops();
                refresh(); if (S.streamMode !== 'sse') quickPoll();
            } catch (e) { toast('启动失败:' + e.message, 'error'); }
        }
        async function closeSession() {
            if (S.readonlyRunId) {
                // 只读回看(含失败页面):后端没有需要关闭的活动会话,直接退出只读回到准备页,
                // 避免把别人正在跑的会话误关掉
                exitReadonly();
                toast('已退出回看,可新建运行', 'success');
                return;
            }
            const live = S.live || {};
            const msg = live.saveState === 'saved'
                ? '保存已完成,确认关闭会话并释放实例?'
                : '结果尚未确认保存。关闭将按放弃未保存结果处理(不可恢复)。确认关闭?';
            const okc = await W.confirmDialog(msg, { danger: live.saveState !== 'saved', okText: '确认关闭' });
            if (!okc) return;
            try {
                await apiPost('/close', {});
                S.phase = 'IDLE'; S.live = null; S.result = null; S.message = ''; S.error = '';
                S.cfgFrozen = null; S.tab = 'main';
                S.compare = null; S.compareOverlay = false;
                S.liveBuf = null; S.sessionId = null; S.catalog = null; S.byId = null;
                S.dispIds = null; S.dispPos = null; S.liveCols = null;
                S.gapNotice = ''; S.liveErr = ''; S.connLost = false; S.pauseReqAt = null;
                S.procLost = false; S.statusOutputDir = null;
                S.applyBusy = false; S.lastSubmit = null;
                stopLoops();
                toast('会话已关闭;可新建运行', 'success');
                renderAll();
            } catch (e) { toast('关闭失败:' + e.message, 'error'); }
        }
        function exitReadonly() {
            S.readonlyRunId = null; S.readonlyFailed = false; S.result = null; resultAcc = null; S.tab = 'main'; S.phase = 'IDLE';
            S.live = null; S.message = ''; S.error = ''; S.compare = null; S.compareOverlay = false;
            S.applyBusy = false; S.lastSubmit = null;
            renderAll();
            refresh();
        }
        const excelUrl = runId => {
            const cfg0 = window.AppConfig;
            return cfg0.api.baseURL + '/api/engine/projects/' + encodeURIComponent(pid)
                + '/afo/sessions/' + encodeURIComponent(runId) + '/excel?token=' + encodeURIComponent(cfg0.getToken() || '');
        };
        async function retrySave() {
            try {
                await apiPost('/save', {});
                toast('已发起保存重试(不重新仿真)', 'info');
                refresh();
            } catch (e) { toast('保存重试失败:' + e.message, 'error'); }
        }
        function reuseFrom(which) {
            const r = S.result || {};
            const src = which === 'initial' ? (r.initialConfig || r.config) : (r.config || r.initialConfig);
            const c = src || {};
            S.cfg = Object.assign({}, S.cfg, {
                engineId: c.engineId || S.cfg.engineId,
                duration: c.duration != null ? c.duration : S.cfg.duration,
                recordStep: c.recordStep != null ? c.recordStep : S.cfg.recordStep,
                pace: c.pace || S.cfg.pace, loadMode: c.loadMode || S.cfg.loadMode,
                powerKw: c.powerW != null ? String(c.powerW / 1000) : S.cfg.powerKw,
                mkpNm: c.mkpNm != null ? c.mkpNm : S.cfg.mkpNm,
                pitchDeg: c.pitchDeg != null ? c.pitchDeg : S.cfg.pitchDeg,
                mainPitchDeg: c.mainPitchDeg != null ? c.mainPitchDeg : S.cfg.mainPitchDeg,
                tailPitchDeg: c.tailPitchDeg != null ? c.tailPitchDeg : S.cfg.tailPitchDeg,
                // M2:双总距固定映射参数随复用配置带入
                tailToMainPowerRatio: c.tailToMainPowerRatio != null ? c.tailToMainPowerRatio : S.cfg.tailToMainPowerRatio,
                tailDesignPitchDeg: c.tailDesignPitchDeg != null ? c.tailDesignPitchDeg : S.cfg.tailDesignPitchDeg,
                externalAir: !!c.externalAir, npRatio: String(c.npRatio || '1'), runId: ''
            });
            exitReadonly();
        }

        /* ---------- 轮询与增量通道 ---------- */
        /* SSE 主通道:样本+状态+事件+阶段一并推送,活跃时零轮询。
         * 兜底:SSE 不可用/断链时启动状态 5s + 增量 200ms 轮询;SSE 恢复后自动停。
         * 引导:页面打开时启动引导轮询(5s)探测阶段→READY 后 loadCatalog→startLiveChannel。 */
        let pollTimer = null, pullTimer = null, pulling = false, statusBusy = false;
        let lastBarPaint = 0; // 运行栏轻量刷新节流(避免高频重建DOM影响按钮点击)
        function startLoops() {
            stopLoops();
            startStatusStream(); // 状态通知SSE:页面打开即订阅(含准备期),chg→refresh一次;连接期间停5s状态轮询
            startLiveChannel();
        }
        function stopLoops() {
            if (pollTimer) { clearInterval(pollTimer); pollTimer = null; }
            stopLiveChannel();
            S.streamMode = ''; // 通道模式一并复位:残留'pull'会让下个会话的SSE启动被永久拦截
            if (S.sseRetry) { clearInterval(S.sseRetry); S.sseRetry = null; }
            if (S.stsRetry) { clearInterval(S.stsRetry); S.stsRetry = null; }
            if (S.stsEs) { try { S.stsEs.close(); } catch (e) { /* 已关 */ } S.stsEs = null; }
        }
        /** 状态通知通道(全生命周期):准备期阶段迁移(IDLE/PREPARING/READY)由此推送,5s轮询降为断链兜底。 */
        function startStatusStream() {
            if (S.stsEs || S.readonlyRunId || typeof EventSource === 'undefined') return;
            try {
                const cfg0 = window.AppConfig;
                const url = cfg0.api.baseURL + '/api/engine/projects/' + encodeURIComponent(pid) + '/afo/stream?token='
                    + encodeURIComponent(cfg0.getToken() || '');
                const es = new EventSource(url);
                S.stsEs = es;
                es.onopen = () => {
                    // 状态SSE就绪:退掉5s兜底轮询与本通道的重试(chg驱动阶段迁移,live帧驱动数据)
                    stopBootstrapPoll();
                    if (S.stsRetry) { clearInterval(S.stsRetry); S.stsRetry = null; }
                };
                es.addEventListener('chg', () => {
                    refresh();
                    // 状态通道已覆盖阶段迁移:停5s引导轮询(数据通道就绪后由live帧接管S.live明细)
                    stopBootstrapPoll();
                });
                es.onerror = () => {
                    try { es.close(); } catch (e) { /* 已关 */ }
                    if (S.stsEs === es) S.stsEs = null;
                    startBootstrapPoll(); // 断链兜底
                    // EventSource已被close,不会有自动重连:必须自愈重订阅,
                    // 否则一次断链后永久停在5s /status轮询,与live推送形成双通道
                    if (!S.stsRetry) S.stsRetry = setInterval(() => {
                        if (S.stsEs || S.readonlyRunId) { clearInterval(S.stsRetry); S.stsRetry = null; return; }
                        startStatusStream(); // 失败再次进入onerror,重试间隔仍在,不叠加
                    }, 5000);
                };
            } catch (e) { /* 保持轮询兜底 */ }
        }
        function startBootstrapPoll() {
            if (pollTimer) return;
            // 状态SSE在线时阶段迁移由chg推送覆盖,绝不叠加5s /status轮询。
            // live流的end/断链处理曾无条件启动本轮询,若chg恰好先到(stopBootstrapPoll扑空),
            // 之后不再有chg,轮询就与活跃SSE永久并存——故统一在此守卫。
            if (S.stsEs || S.readonlyRunId) return;
            pollTimer = setInterval(() => {
                if (!S.readonlyRunId && ['PREPARING', 'READY', 'RUNNING', 'PAUSED', 'ENDED', 'FAILED'].includes(S.phase)) refresh();
            }, 5000);
        }
        function stopBootstrapPoll() {
            if (pollTimer) { clearInterval(pollTimer); pollTimer = null; }
        }
        /** 增量通道:SSE 为主(program-run live-stream 同构),失败降级 200ms 拉取。 */
        function startLiveChannel() {
            if (S.es || S.readonlyRunId) return;
            if (!S.catalog || !S.liveBuf || !S.liveCols) return; // 目录就绪后由 refresh 再触发
            const live = S.live || {};
            if (live.publishLive === false) return; // 发布关闭:运行栏已有提示
            if (S.liveBuf.isFinal) return;
            if (typeof EventSource === 'undefined') { fallbackPull(); return; }
            try {
                const cfg0 = window.AppConfig;
                const url = cfg0.api.baseURL + '/api/engine/projects/' + encodeURIComponent(pid) + '/afo/live-stream?token='
                    + encodeURIComponent(cfg0.getToken() || '')
                    + '&afterSeq=' + (S.liveBuf.nextSeq || 0)
                    + (S.liveBuf.sessionId ? '&sessionId=' + encodeURIComponent(S.liveBuf.sessionId) : '')
                    + '&columns=' + S.liveCols.join(',');
                const es = new EventSource(url);
                S.es = es; S.streamMode = 'sse';
                S._liveFrames = 0;
                // watchdog:连接活着但6s收不到任何live帧(典型:nginx等代理缓冲SSE)→强制降级轮询,
                // 否则"状态流通(chg停轮询)+数据流被缓冲"的组合会让运行期全程盲跑
                S._liveWatch = setTimeout(() => {
                    if (S.es === es && S.streamMode === 'sse' && !S._liveFrames && !S.liveBuf.isFinal) {
                        console.warn('AFO实时流6s无数据帧(疑似代理缓冲),降级为轮询拉取');
                        stopLiveChannel();
                        fallbackPull();
                    }
                }, 6000);
                es.addEventListener('live', ev => {
                    try {
                        S._liveFrames++;
                        ingestLive(JSON.parse(ev.data));
                        // SSE 活跃:停引导轮询与兜底(状态/事件/阶段已由通道覆盖,零轮询)
                        stopBootstrapPoll();
                        if (S.pullTimer) { clearInterval(S.pullTimer); S.pullTimer = null; }
                    } catch (e) { /* 坏帧忽略 */ }
                });
                es.addEventListener('end', () => {
                    if (S.liveBuf) S.liveBuf.isFinal = true;
                    stopLiveChannel();
                    // 数据通道在isFinal即关闭,但Java phase=ENDED要等save/result/close完成后才设置——
                    // 必须恢复状态监视(状态流+兜底轮询),否则保存完成后的ENDED迁移无人送达,界面卡在"计算中"
                    startStatusStream();
                    startBootstrapPoll();
                });
                es.addEventListener('err', () => { stopLiveChannel(); fallbackPull(); });
                es.onerror = () => { stopLiveChannel(); startBootstrapPoll(); fallbackPull(); };
            } catch (e) { fallbackPull(); }
        }
        function fallbackPull() {
            S.streamMode = 'pull';
            if (!S.pullTimer) S.pullTimer = setInterval(pullLive, 200);
            startBootstrapPoll();
            startSseRetry();
        }
        /** 兜底拉取期间的SSE重试(10s一次):恢复推送后自动退掉轮询,避免永久停留在200ms拉取。 */
        function startSseRetry() {
            if (S.sseRetry) return;
            S.sseRetry = setInterval(() => {
                if (S.streamMode !== 'pull' || !S.catalog || !S.liveBuf || S.liveBuf.isFinal || S.readonlyRunId) {
                    clearInterval(S.sseRetry); S.sseRetry = null; return;
                }
                stopLiveChannel();
                S.streamMode = '';
                startLiveChannel(); // 失败会再次 onerror→fallbackPull(计时器仍在,不叠加)
            }, 10000);
        }
        function stopLiveChannel() {
            if (S.es) { try { S.es.close(); } catch (e) { /* 已关 */ } S.es = null; }
            if (S.pullTimer) { clearInterval(S.pullTimer); S.pullTimer = null; }
            if (S._liveWatch) { clearTimeout(S._liveWatch); S._liveWatch = null; }
        }
        /** 命令提交后的快速状态跟踪(取回执/状态迁移,不受 5s 节拍限制)。 */
        function quickPoll() {
            (async () => {
                for (let i = 0; i < 5; i++) {
                    await new Promise(r => setTimeout(r, 900));
                    await refresh();
                }
            })();
        }
        /** D2:用服务端会话配置(prepare 请求原样)恢复界面配置与冻结配置。
         *  运行中刷新/重开页面时,S.cfg 不能回落准备页默认值;功率在服务端是 W,界面是 kW。 */
        function restoreServerCfg(c) {
            if (!c || typeof c !== 'object') return;
            const pw = c.powerW != null && isFinite(Number(c.powerW)) ? String(Number(c.powerW) / 1000) : null;
            const s = k => (c[k] != null ? String(c[k]) : S.cfg[k]);
            Object.assign(S.cfg, {
                engineId: s('engineId'),
                duration: s('duration'), recordStep: s('recordStep'), pace: s('pace'),
                loadMode: s('loadMode'),
                powerKw: pw != null ? pw : s('powerKw'),
                mkpNm: s('mkpNm'), pitchDeg: s('pitchDeg'),
                mainPitchDeg: s('mainPitchDeg'), tailPitchDeg: s('tailPitchDeg'),
                tailToMainPowerRatio: s('tailToMainPowerRatio'), tailDesignPitchDeg: s('tailDesignPitchDeg'),
                npRatio: s('npRatio'),
                // 任务编号不回填:服务端 config 里的 runId 是上一次运行的身份,
                // 带回表单会导致第二次准备沿用旧编号,MATLAB 合同断言"结果目录已存在,不覆盖"直接失败
                // (与 reuseFrom/__WB_AFO_REUSE__ 的 runId:'' 约定一致)
                runId: '',
                externalAir: !!c.externalAir,
                publishLive: c.publishLive !== false
            });
            S.cfgFrozen = {
                duration: parseFloat(c.duration), externalAir: !!c.externalAir,
                loadMode: c.loadMode || S.cfg.loadMode, npRatio: c.npRatio != null ? String(c.npRatio) : S.cfg.npRatio,
                designNpRpm: c.designNpRpm,
                tailToMainPowerRatio: c.tailToMainPowerRatio, tailDesignPitchDeg: c.tailDesignPitchDeg,
                outputDir: c.outputDir || (S.cfgFrozen && S.cfgFrozen.outputDir) || null
            };
        }
        /** D8:进程消失判定。运行态(非暂停)心跳停止超过 60s → 视为实例失联,不能续算。
         *  暂停时 status.json 不再随记录步重写,心跳必然变旧,故不把暂停族计入该判定。 */
        function heartbeatAge() {
            const hb = S.live && S.live.lastHeartbeat;
            if (!hb) return null;
            const t = new Date(String(hb).replace(' ', 'T')).getTime();
            return isFinite(t) ? Date.now() - t : null;
        }
        async function refresh() {
            if (statusBusy || S.readonlyRunId) return;
            statusBusy = true;
            try {
                const resp = await api('/status');
                const d = resp && (resp.success || resp.code === 200) && resp.data ? resp.data : {};
                const prev = uiState();
                S.phase = d.phase || 'IDLE';
                S.message = d.message || '';
                S.live = d.live || null;
                // 失败原因采集:Java会话error为完整报告(status.json本身不含error)
                S.error = S.phase === 'FAILED' && d.error != null ? String(d.error) : '';
                // D2:有活动会话时一律用服务端配置恢复(不只 READY);运行中刷新/重开不回落默认
                if (d.config) restoreServerCfg(d.config);
                if (d.outputDir) S.statusOutputDir = String(d.outputDir);
                if (S.live && S.live.state === 'running') S.localResume = false;
                // 以 uiState 判连接/失联:Java 会话 phase 在暂停期间仍是 RUNNING,
                // 暂停时 status.json 不再随记录步重写,不能据此误报失联(D3/D8)
                const uiNow = uiState();
                const pausedFamily = uiNow === 'PAUSED' || uiNow === 'RESUME_REQ' || uiNow === 'PAUSE_REQ';
                const hbAge = heartbeatAge();
                S.connLost = hbAge != null ? (hbAge > 12000 && !pausedFamily && uiNow === 'RUNNING') : runningLike();
                // D8:运行态(未暂停)长时间无心跳 → 实例失联且不能续算
                S.procLost = hbAge != null && hbAge > 60000 && uiNow === 'RUNNING';
                // 字典缺失时任何阶段都重试(准备中channels.json可能还没写出);不然运行期全图"未在字典中"
                if (!S.catalog && !S._catBusy && !S.readonlyRunId) {
                    S._catBusy = true;
                    loadCatalog().then(ok => { S._catBusy = false; if (ok) renderAll(); })
                        .catch(() => { S._catBusy = false; });
                }
                if (S.catalog && !S.es && S.streamMode !== 'pull') startLiveChannel();
                if ((S.phase === 'ENDED' || S.phase === 'FAILED') && !S.result) ensureSessionResult();
                const now = uiState();
                if (now !== prev) {
                    // 暂停/继续族迁移:只做就地补丁,避免"命令回执 + 状态轮询"各重建一次造成双闪
                    if (isPauseUi(prev) && isPauseUi(now)) schedulePatchRunningUi();
                    else renderAll();
                } else if (isPauseUi(now)) {
                    // 同状态轮询:就地补丁(含命令记录小表),不重建主面板/图表
                    schedulePatchRunningUi();
                } else lightUpdate();
            } catch (e) { /* 轮询容错 */ }
            statusBusy = false;
        }
        /** 增量数据统一入口(SSE 消息与 REST 兜底同构):样本+状态+事件+阶段一次到位。 */
        function ingestLive(d) {
            if (!S.liveBuf) return;
            const prevUi = uiState(); // 状态摘要更新可能引发按钮态迁移(RUNNING→PAUSED等),先记快照
            const wasCompiling = isCompiling(); // 编译期→首帧样本到达需要重绘运行栏(编译中→计算中)
            const added = S.liveBuf.append(d, S.liveCols);
            let eventsChanged = false;
            // 阶段迁移(Java 生命周期真源):变更即整页重绘
            let phaseChanged = false;
            if (d.phase && d.phase !== S.phase) {
                const prev = uiState();
                S.phase = d.phase;
                S.message = d.message || S.message;
                phaseChanged = prev !== uiState();
            } else if (d.message && !S.message) {
                S.message = d.message;
            }
            // 状态摘要/命令回执/操纵占位随通道同步(轮询降为兜底后这里是主路径)
            S.live = S.live || {};
            ['state', 'currentSimulationTime', 'sampleTime', 'sampleSeq', 'publishedSeq',
             'lastHeartbeat', 'saveState', 'saveError', 'publishError', 'applied', 'pending',
             'pauseRequested', 'stopRequested', 'error',
             'progress', 'duration', 'wallSeconds'].forEach(k => {
                if (d[k] !== undefined) S.live[k] = d[k];
            });
            if (d.events && d.eventsLen !== undefined) {
                const evs = asArr(d.events);
                const prevLen = (S.live.events || []).length;
                if (d.eventsLen !== prevLen || evs.length !== d.eventsLen) {
                    S.live.events = evs;
                    eventsChanged = true;
                }
            }
            if ((S.phase === 'ENDED' || S.phase === 'FAILED') && !S.result) ensureSessionResult();
            if (S.liveBuf.gap && S.gapRetries >= 5) {
                S.gapNotice = '样本序号缺口 ' + S.liveBuf.gap.from + '~' + S.liveBuf.gap.to
                    + ':多次补读未获，图中保留缺口不线性连接。后续数据继续追加。';
                S.liveBuf.nextSeq = Math.max(S.liveBuf.nextSeq, S.liveBuf.gap.to + 1);
                S.liveBuf.gap = null; S.gapRetries = 0;
            } else if (!S.liveBuf.gap) { S.gapNotice = ''; S.gapRetries = 0; }
            // L2:关跟随后新样本到达→图表工具条给出可见提示(点击"跟随最新"恢复后清除)
            if (added > 0 && !S.follow) {
                S.followDirty = true;
                if (S._followEl) { S._followEl.textContent = '跟随最新：关（新数据已到达）'; S._followEl.style.color = '#b45309'; }
            }
            if (added > 0 || d.hasMore || eventsChanged) refreshRuntimeCharts();
            // 命令回执新增/状态变化:只就地刷新运行栏与命令记录,不整页重绘
            if (eventsChanged && isPauseUi(uiState())) schedulePatchRunningUi();
            if (d.isFinal) S.liveBuf.isFinal = true; // 通道保持开启:保存状态仍会变化
            if (phaseChanged || uiState() !== prevUi) {
                const next = uiState();
                // 暂停/继续迁移就地补丁:不 disposeCharts、不重建主面板,避免曲线闪断/滚动回顶
                if (isPauseUi(prevUi) && isPauseUi(next)) schedulePatchRunningUi();
                else renderAll(); // 按钮态迁移(准备完成/结束等)
            }
            else if (wasCompiling && added > 0 && !isCompiling()) exitCompileOverlay(); // 编译期结束:只摘遮罩+刷新,不整页重建
            else if (runningLike()) {
                // SSE稳态运行:进度/仿真时间随数据轻量刷新(图表由refreshRuntimeCharts负责),400ms节流
                const now = Date.now();
                if (now - lastBarPaint > 400) { lastBarPaint = now; paintBar(); }
            }
            else if ((S.tab === 'main' || sysOfTab[S.tab]) && uiState() === 'ENDED') lightUpdate();
        }
        async function pullLive() {
            if (pulling || !S.catalog || S.readonlyRunId || !S.liveBuf || S.liveBuf.isFinal) return;
            const live = S.live || {};
            if (live.publishLive === false) return;
            if (!['RUNNING', 'PAUSED', 'ENDED', 'PAUSE_REQ', 'RESUME_REQ', 'STOP_REQ'].includes(S.phase) && S.phase !== 'READY') return;
            pulling = true;
            try {
                let cursor = S.liveBuf.nextSeq;
                if (S.liveBuf.gap && S.gapRetries < 5) { cursor = S.liveBuf.gap.from - 1; S.gapRetries++; }
                const qs = '?afterSeq=' + cursor + '&maxRows=2048'
                    + (S.liveBuf.sessionId ? '&sessionId=' + encodeURIComponent(S.liveBuf.sessionId) : '')
                    + '&columns=' + S.liveCols.join(',');
                const resp = await api('/live' + qs);
                if (!(resp && (resp.success || resp.code === 200) && resp.data)) { S.liveErr = (resp && resp.message) || '读取失败'; pulling = false; return; }
                S.liveErr = '';
                ingestLive(resp.data);
            } catch (e) { S.liveErr = e.message || String(e); }
            pulling = false;
        }
        function ensureSessionResult() {
            if (S.result || S._resultLoading || S.readonlyRunId) return;
            const runId = S.live && S.live.runId;
            if (!runId || (S.phase !== 'ENDED' && S.phase !== 'FAILED')) return;
            S._resultLoading = true;
            api('/sessions/' + encodeURIComponent(runId) + '/result')
                .then(resp => { if (resp && (resp.success || resp.code === 200) && resp.data) S.result = resp.data; })
                .catch(() => { })
                .finally(() => { S._resultLoading = false; loadCatalog().then(renderAll); });
        }

        /* ---------- 历史只读钩子(与仿真记录页兼容) ---------- */
        async function loadReadonly(runId) {
            S.readonlyRunId = runId;
            S.readonlyFailed = false;
            S.readonlyLoading = true;
            S.result = null; resultAcc = null;
            S.error = '';
            S.tab = 'main';
            S.compare = null; S.compareOverlay = false;
            stopLoops();
            loadDisp();
            renderAll();
            try {
                const resp = await api('/sessions/' + encodeURIComponent(runId) + '/result');
                if (resp && (resp.success || resp.code === 200) && resp.data) {
                    S.result = resp.data;
                    if (resp.data.readonlyFailed || resp.data.phase === 'FAILED') {
                        // 失败会话只读:保留失败状态,并采集error供运行栏悬停浮窗使用
                        S.readonlyFailed = true;
                        S.error = resp.data.error == null ? '' : String(resp.data.error);
                        await loadCatalog();
                        refreshAcc();
                    } else {
                        await loadCatalog();
                        refreshAcc(); // 主区图表经resultAcc取数,结果赋值后立即重建访问器
                        // 冻结配置:历史结果回看时取结果的最终配置(含回灌与双总距映射参数)
                        S.cfgFrozen = {
                            duration: parseFloat((S.result.config && S.result.config.duration) || 0),
                            externalAir: !!(S.result.config && S.result.config.externalAir),
                            tailToMainPowerRatio: S.result.config && S.result.config.tailToMainPowerRatio,
                            tailDesignPitchDeg: S.result.config && S.result.config.tailDesignPitchDeg
                        };
                    }
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
            const c = (rec && rec.config) || {};
            S.cfg = Object.assign({}, S.cfg, {
                engineId: c.engineId || S.cfg.engineId,
                duration: c.duration != null ? c.duration : S.cfg.duration,
                recordStep: c.recordStep != null ? c.recordStep : S.cfg.recordStep,
                pace: c.pace || S.cfg.pace, loadMode: c.loadMode || S.cfg.loadMode,
                powerKw: c.powerW != null ? String(c.powerW / 1000) : S.cfg.powerKw,
                mkpNm: c.mkpNm != null ? c.mkpNm : S.cfg.mkpNm,
                pitchDeg: c.pitchDeg != null ? c.pitchDeg : S.cfg.pitchDeg,
                mainPitchDeg: c.mainPitchDeg != null ? c.mainPitchDeg : S.cfg.mainPitchDeg,
                tailPitchDeg: c.tailPitchDeg != null ? c.tailPitchDeg : S.cfg.tailPitchDeg,
                // M2:双总距固定映射参数随复用配置带入
                tailToMainPowerRatio: c.tailToMainPowerRatio != null ? c.tailToMainPowerRatio : S.cfg.tailToMainPowerRatio,
                tailDesignPitchDeg: c.tailDesignPitchDeg != null ? c.tailDesignPitchDeg : S.cfg.tailDesignPitchDeg,
                externalAir: !!c.externalAir, npRatio: String(c.npRatio || '1'), runId: ''
            });
            exitReadonly();
        };

        /* ---------- 启动 ---------- */
        loadDisp();
        renderAll();
        refresh();
        loadCatalog().then(() => { if (S.tab !== 'main') renderAll(); });
        startLoops();
        return wrap;
    };
    /* 旧实现(workbench-common.js 同键页面)保留回退:本文件在其后加载即覆盖注册。 */
})();
