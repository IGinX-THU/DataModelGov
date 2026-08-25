const SECTIONS = [
  { id: 'data', title: '项目与数据', hint: '工作区、试车数据与数据合同' },
  { id: 'identify', title: '参数辨识', hint: 'A/B/C/D 连续辨识流程' },
  { id: 'identifiability', title: '工程可辨识性', hint: '双位置信息质量与补偿关系' },
  { id: 'uq', title: '不确定性评估', hint: '方法 A / B 与 95%置信区间' },
  { id: 'validation', title: '独立测试验证', hint: '测试集输出与误差标准差' },
  { id: 'prediction', title: '任意工况预测', hint: '单工况确定性与后验预测' },
  { id: 'results', title: '结果中心', hint: '追溯、审核、归档与发布' }
];

const TERMINAL = new Set(['SUCCEEDED', 'FAILED', 'CANCELLED', 'SKIPPED']);
const RUNNING = new Set(['QUEUED', 'RUNNING', 'CANCEL_REQUESTED']);
const STATUS_TEXT = {
  READY: '就绪', QUEUED: '排队中', RUNNING: '运行中', CANCEL_REQUESTED: '取消中',
  SUCCEEDED: '已完成', FAILED: '已失败', CANCELLED: '已取消', SKIPPED: '已跳过'
};

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined && text !== null) node.textContent = String(text);
  return node;
}

function button(text, className, handler) {
  const node = el('button', className || 'btn', text);
  node.type = 'button';
  if (handler) node.addEventListener('click', handler);
  return node;
}

function input(type, name, value, placeholder) {
  const node = document.createElement('input');
  node.type = type;
  node.name = name;
  if (value !== undefined && value !== null) node.value = String(value);
  if (placeholder) node.placeholder = placeholder;
  return node;
}

function asArray(value) {
  return Array.isArray(value) ? value : [];
}

function formatTime(value) {
  if (!value) return '—';
  const date = new Date(Number(value));
  return Number.isNaN(date.getTime()) ? String(value) : date.toLocaleString('zh-CN', { hour12: false });
}

function formatSize(value) {
  const size = Number(value);
  if (!Number.isFinite(size)) return '—';
  if (size < 1024) return size + ' B';
  if (size < 1048576) return (size / 1024).toFixed(1) + ' KB';
  return (size / 1048576).toFixed(1) + ' MB';
}

function actionText(action) {
  return [action.key, action.stage, action.label, action.resultType].filter(Boolean).join(' ').toLowerCase();
}

function actionSection(action) {
  const text = actionText(action);
  if (/publish|发布/.test(text) || /review|audit|approve|审核|归档/.test(text)) return 'results';
  if (/predict|工况预测|prediction/.test(text)) return 'prediction';
  if (/validat|testdata|test[_ -]?data|测试验证|独立测试/.test(text)) return 'validation';
  if (/uncertain|\buq\b|posterior|置信|后验|耗时预估|runtime.?estimate/.test(text)) return 'uq';
  if (/identifiab|可辨识/.test(text)) return 'identifiability';
  if (/adapt|estimat|identif|calibrat|参数辨识|模型修正/.test(text)) return 'identify';
  return 'results';
}

function isDatasetInput(name, specs) {
  return specs.some(spec => spec.key === name);
}

class SteadyModelAdaptV1 {
  constructor(ctx) {
    this.ctx = ctx;
    this.root = null;
    this.activeSection = 'data';
    this.workspaces = [];
    this.workspace = null;
    this.uploaded = [];
    this.tasks = new Map();
    this.results = new Map();
    this.artifacts = new Map();
    this.taskLogs = new Map();
    this.timers = new Set();
    this.listeners = [];
    this.charts = [];
    this.destroyed = false;
    this.busy = false;
    this.predictionMode = 'pressure';
    this.identifyModel = 'transient';
    this.uqMethod = 'A';
    this.actions = asArray(ctx.config && ctx.config.workflow && ctx.config.workflow.actions);
    this.datasetSpecs = asArray(ctx.config && ctx.config.workflow && ctx.config.workflow.datasets);
  }

  async init() {
    this.buildShell();
    this.render();
    await this.loadWorkspaces();
  }

  buildShell() {
    this.root = el('div', 'steady-app');
    const header = el('header', 'app-header');
    const identity = el('div', 'identity');
    identity.append(el('div', 'eyebrow', '发动机个性化性能数字模型'), el('h1', '', '稳态试车工况点模型修正 V1'));
    identity.append(el('p', 'subhead', [this.ctx.program.name, this.ctx.program.version, this.ctx.program.projectName].filter(Boolean).join(' · ')));
    this.workspaceBadge = el('div', 'workspace-badge', '未选择工作区');
    header.append(identity, this.workspaceBadge);

    const body = el('div', 'app-body');
    this.nav = el('nav', 'flow-nav');
    this.content = el('main', 'content');
    this.aside = el('aside', 'status-rail');
    body.append(this.nav, this.content, this.aside);
    this.root.append(header, body);
    this.ctx.mount.replaceChildren(this.root);
  }

  render() {
    if (this.destroyed) return;
    this.disposeCharts();
    this.renderNav();
    this.content.replaceChildren();
    const section = SECTIONS.find(item => item.id === this.activeSection) || SECTIONS[0];
    const heading = el('div', 'section-heading');
    heading.append(el('div', 'step-number', String(SECTIONS.indexOf(section) + 1).padStart(2, '0')));
    const copy = el('div');
    copy.append(el('h2', '', section.title), el('p', '', section.hint));
    heading.append(copy);
    this.content.append(heading);
    const renderer = this['render_' + section.id];
    if (renderer) renderer.call(this, this.content);
    this.renderAside();
    this.workspaceBadge.textContent = this.workspace ? '工作区 ' + this.workspace.id : '未选择工作区';
  }

  renderNav() {
    this.nav.replaceChildren();
    this.nav.append(el('div', 'nav-title', '业务流程'));
    SECTIONS.forEach((section, index) => {
      const item = button('', 'nav-item' + (section.id === this.activeSection ? ' active' : ''), () => {
        this.activeSection = section.id;
        this.render();
      });
      item.append(el('span', 'nav-index', String(index + 1)), el('span', 'nav-label', section.title));
      this.nav.append(item);
    });
  }

  renderAside() {
    this.aside.replaceChildren();
    const pre = this.card('前置条件');
    const list = el('ul', 'check-list');
    this.checkItem(list, '工作区已创建', Boolean(this.workspace));
    const required = this.datasetSpecs.filter(item => item.required);
    this.checkItem(list, '必需数据已上传', required.every(spec => this.uploaded.some(item => item.datasetKey === spec.key)));
    this.checkItem(list, '工作流动作可用', this.actions.length > 0);
    pre.append(list);

    const status = this.card('任务状态');
    const taskList = el('div', 'mini-task-list');
    const tasks = Array.from(this.tasks.values()).sort((a, b) => Number(b.createdAt || 0) - Number(a.createdAt || 0)).slice(0, 6);
    if (!tasks.length) taskList.append(el('p', 'empty', '当前会话暂无任务'));
    tasks.forEach(task => {
      const row = el('button', 'mini-task');
      row.type = 'button';
      row.addEventListener('click', () => {
        const action = this.findAction(task.actionKey);
        this.activeSection = action ? actionSection(action) : 'results';
        this.render();
      });
      row.append(el('span', '', this.actionLabel(task.actionKey)), this.statusPill(task.status));
      taskList.append(row);
    });
    status.append(taskList);

    const note = this.card('运行约束');
    note.append(el('p', 'rail-note', '训练数据用于辨识，测试数据仅用于独立验证。业务结果只读取结构化返回值，不解析 MATLAB 控制台日志。'));
    this.aside.append(pre, status, note);
  }

  checkItem(list, label, passed) {
    const item = el('li', passed ? 'passed' : 'pending');
    item.append(el('span', 'check-mark', passed ? '通过' : '待办'), el('span', '', label));
    list.append(item);
  }

  card(title, className) {
    const node = el('section', 'card' + (className ? ' ' + className : ''));
    if (title) node.append(el('h3', 'card-title', title));
    return node;
  }

  render_data(container) {
    const workspaceCard = this.card('项目工作区', 'span-2');
    const toolbar = el('div', 'toolbar');
    const select = document.createElement('select');
    select.setAttribute('aria-label', '选择工作区');
    select.append(new Option('请选择已有工作区', ''));
    this.workspaces.forEach(item => select.append(new Option(item.id + ' · ' + formatTime(item.createdAt), item.id)));
    select.value = this.workspace ? this.workspace.id : '';
    select.addEventListener('change', () => this.selectWorkspace(select.value));
    const create = button('新建工作区', 'btn primary', () => this.createWorkspace());
    const refresh = button('刷新', 'btn subtle', () => this.loadWorkspaces());
    toolbar.append(select, create, refresh);
    workspaceCard.append(toolbar);
    if (this.workspace) {
      const facts = el('div', 'facts');
      this.fact(facts, '程序', this.workspace.programName || this.ctx.program.name);
      this.fact(facts, '模型版本', this.workspace.programVersion || this.ctx.program.version);
      this.fact(facts, '项目', this.workspace.projectName || this.ctx.program.projectName || '—');
      this.fact(facts, '创建时间', formatTime(this.workspace.createdAt));
      workspaceCard.append(facts);
    }

    const datasetCard = this.card('训练与测试数据', 'span-2');
    const datasetGrid = el('div', 'dataset-grid');
    if (!this.datasetSpecs.length) datasetGrid.append(el('p', 'empty', '当前程序配置未声明 workflow.datasets。'));
    this.datasetSpecs.forEach(spec => datasetGrid.append(this.renderDataset(spec)));
    datasetCard.append(datasetGrid);

    const contract = this.card('数据合同与质量检查');
    contract.append(el('p', 'muted', '服务端结构化检查结果将在相应动作完成后显示。上传文件不会在浏览器中推断或伪造业务数值。'));
    const fields = ['point_id', 'Np_mean', 'Ng_mean', 'Wf_mean', 'Mkp_mean', 'Mkg_mean', 'Tt1_mean', 'Pt2_mean', 'Pt3_mean', 'Tt3_mean', 'Tt45_mean', 'Pt45_mean', 'Pamb_mean', 'Tamb_mean', 'Altitude_mean', 'Mach_mean'];
    const chips = el('div', 'chips');
    fields.forEach(field => chips.append(el('span', 'chip', field)));
    contract.append(chips);

    const dataActions = this.card('可用数据动作');
    this.renderActionButtons(dataActions, this.actions.filter(action => {
      const text = actionText(action);
      return /data|import|prepare|group|contract|数据|分组|检查/.test(text) && actionSection(action) === 'results';
    }));

    const grid = el('div', 'grid');
    grid.append(workspaceCard, datasetCard, contract, dataActions);
    container.append(grid);
  }

  renderDataset(spec) {
    const uploaded = this.uploaded.find(item => item.datasetKey === spec.key);
    const node = el('div', 'dataset-item');
    const top = el('div', 'dataset-top');
    const title = el('div');
    title.append(el('strong', '', spec.label || spec.key), el('small', '', [spec.role, spec.type].filter(Boolean).join(' · ')));
    top.append(title, el('span', uploaded ? 'dataset-state ready' : 'dataset-state', uploaded ? '已上传' : (spec.required ? '必需' : '可选')));
    node.append(top);
    if (uploaded) node.append(el('div', 'file-meta', uploaded.fileName + ' · ' + formatSize(uploaded.size) + ' · ' + formatTime(uploaded.uploadedAt)));
    const file = input('file', 'file-' + spec.key);
    if (String(spec.type).toLowerCase() === 'xlsx') file.accept = '.xlsx,.xls';
    if (String(spec.type).toLowerCase() === 'csv') file.accept = '.csv';
    file.disabled = !this.workspace;
    file.addEventListener('change', () => {
      if (file.files && file.files[0]) this.uploadDataset(spec.key, file.files[0]);
      file.value = '';
    });
    node.append(file);
    return node;
  }

  render_identify(container) {
    const config = this.card('辨识任务配置', 'span-2');
    const modeRow = el('div', 'form-row');
    const modelSelect = this.selectControl('identify-model', [
      ['transient', '瞬态时刻模型（默认）'], ['steady', '稳态模型']
    ], this.identifyModel);
    modelSelect.addEventListener('change', () => {
      this.identifyModel = modelSelect.value;
      this.render();
    });
    modeRow.append(this.field('辨识模型', modelSelect));
    config.append(modeRow);
    const notice = el('p', 'muted', '正则化参数由程序入口内置默认值决定，不可在运行时覆盖。以下为入口默认配置，仅供参考。');
    config.append(notice);
    const stages = el('div', 'stage-config readonly');
    const defaults = this.identifyModel === 'steady'
      ? [['A', 'TSVD', '截断 7 方向'], ['B', 'Tikhonov', 's=0.50'], ['D', 'Tikhonov', 's=1.00']]
      : [['A', 'TSVD', '截断 5 方向'], ['B', 'Tikhonov', 's=0.75'], ['D', 'Tikhonov', 's=1.00']];
    defaults.forEach(values => {
      const stage = el('div', 'stage-box');
      stage.append(el('strong', '', '阶段 ' + values[0]));
      stage.append(el('div', 'stage-default', '方法：' + values[1]));
      stage.append(el('div', 'stage-default', '参数：' + values[2]));
      stages.append(stage);
    });
    config.append(stages);

    const flow = this.card('连续辨识流程', 'span-2');
    const flowline = el('div', 'stage-flow');
    ['A 全工况常值初估', 'B 分组组内估计', 'C 调度节点组装', 'D 全工况联合微调'].forEach((name, index) => {
      const step = el('div', 'flow-step');
      step.append(el('span', 'flow-dot', String(index + 1)), el('span', '', name));
      flowline.append(step);
    });
    flow.append(flowline);
    const identifyActions = this.actionsFor('identify').filter(action => {
      const text = actionText(action);
      return this.identifyModel === 'steady' ? /steady|稳态模型/.test(text) && !/transient|瞬态/.test(text) : /transient|瞬态/.test(text);
    });
    this.renderActionButtons(flow, identifyActions, '一次启动完成 A/B/C/D；配置将写入任务记录。');

    const result = this.card('修正系数与输出误差', 'span-2');
    this.renderSectionResults(result, 'identify');
    const grid = el('div', 'grid');
    grid.append(config, flow, result);
    container.append(grid);
  }

  render_identifiability(container) {
    const overview = this.card('分析位置与工程问题');
    const tabs = el('div', 'segmented');
    tabs.append(button('零修正基准模型', 'segment active'), button('稳态辨识模型', 'segment'));
    tabs.addEventListener('click', event => {
      if (!(event.target instanceof HTMLButtonElement)) return;
      tabs.querySelectorAll('button').forEach(node => node.classList.toggle('active', node === event.target));
    });
    overview.append(tabs, el('p', 'muted', '同时评估自身敏感性、参数补偿依赖及双位置结论一致性。'));
    this.renderActionButtons(overview, this.actionsFor('identifiability'));
    const evidence = this.card('整体信息质量');
    this.placeholderMetrics(evidence, ['标准化条件数', '有效奇异方向', '观测数', '参数数']);
    const result = this.card('逐参数分类与补偿证据', 'span-2');
    this.renderSectionResults(result, 'identifiability');
    const grid = el('div', 'grid');
    grid.append(overview, evidence, result);
    container.append(grid);
  }

  render_uq(container) {
    const methods = this.card('评估方法', 'span-2');
    const choice = el('div', 'method-grid');
    choice.append(this.methodCard('A', '关键修正系数评估', '总体调度参数、常值参数和燃油偏置'), this.methodCard('B', '全修正系数评估', '六部件局部常值修正与物理引气不确定性'));
    methods.append(choice);
    const cfg = el('div', 'form-row');
    const methodSelect = this.selectControl('uq-method', [['A', '方法 A'], ['B', '方法 B']], this.uqMethod);
    methodSelect.addEventListener('change', () => {
      this.uqMethod = methodSelect.value;
      this.render();
    });
    cfg.append(this.field('粒子/样本配置', input('number', 'uq-samples', '', '由程序配置或任务输入决定')), this.field('方法选择', methodSelect));
    methods.append(cfg);
    const uqActions = this.actionsFor('uq').filter(action => this.uqMethod === 'B' ? /methodB|方法B|uqB/i.test(actionText(action)) : !/methodB|方法B|uqB/i.test(actionText(action)));
    this.renderActionButtons(methods, uqActions, '若配置提供耗时预估动作，可先独立执行轻量预估。');

    const progress = this.card('运行状态');
    this.renderTaskProgress(progress, uqActions);
    const result = this.card('95%置信区间结果', 'span-2');
    result.append(el('p', 'muted', '模型输出区间与叠加测量误差后的可观测量区间分别展示，不显示参数真值。'));
    this.renderSectionResults(result, 'uq');
    const grid = el('div', 'grid');
    grid.append(methods, progress, result);
    container.append(grid);
  }

  render_validation(container) {
    const testSpecs = this.datasetSpecs.filter(spec => /test|valid|测试/.test([spec.key, spec.role, spec.label].join(' ').toLowerCase()));
    const hasTest = testSpecs.some(spec => this.uploaded.some(item => item.datasetKey === spec.key));
    const intro = this.card('独立测试集');
    intro.append(el('div', hasTest ? 'notice success' : 'notice', hasTest ? '测试集已就绪，仅用于验证且不更新参数。' : '未提供测试集时，程序应安全返回“已跳过”，不作为错误处理。'));
    this.renderActionButtons(intro, this.actionsFor('validation'));
    const chart = this.card('输出对比与误差标准差', 'span-2');
    this.renderSectionResults(chart, 'validation');
    const grid = el('div', 'grid');
    grid.append(intro, chart);
    container.append(grid);
  }

  render_prediction(container) {
    const formCard = this.card('单工况输入', 'span-2');
    const modes = el('div', 'segmented mode-switch');
    const pressure = button('直接环境边界（模式 2）', 'segment' + (this.predictionMode === 'pressure' ? ' active' : ''));
    const altitude = button('高度环境边界（模式 3）', 'segment' + (this.predictionMode === 'altitude' ? ' active' : ''));
    pressure.addEventListener('click', () => { this.predictionMode = 'pressure'; this.render(); });
    altitude.addEventListener('click', () => { this.predictionMode = 'altitude'; this.render(); });
    modes.append(pressure, altitude);
    formCard.append(modes);
    const form = el('div', 'prediction-form');
    const first = this.predictionMode === 'pressure'
      ? ['Pamb', '环境静压', 'Pa'] : ['Altitude', '高度', 'm'];
    [first, ['Tamb', '环境静温', 'K'], ['Mach', '马赫数', '—'], ['Wf_model', '模型燃油流量', 'kg/s'], ['Mkp', 'PT 轴负载', 'N·m'], ['Mkg', 'GT 附件负载', 'N·m']].forEach(item => {
      const control = input('number', 'predict-' + item[0], '', item[2]);
      control.step = 'any';
      form.append(this.field(item[1] + ' (' + item[0] + ')', control));
    });
    const posterior = this.selectControl('posterior-method', [['none', '仅确定性预测'], ['A', '方法 A 后验'], ['B', '方法 B 后验']], 'none');
    form.append(this.field('不确定性传播', posterior));
    formCard.append(form);
    this.renderActionButtons(formCard, this.actionsFor('prediction'));
    const result = this.card('预测输出', 'span-2');
    result.append(el('p', 'muted', '确定性输出、共同工作最大残差和收敛状态优先显示；可用后验同时显示模型输出与可观测量 95%置信区间。'));
    this.renderSectionResults(result, 'prediction');
    const grid = el('div', 'grid');
    grid.append(formCard, result);
    container.append(grid);
  }

  render_results(container) {
    const trace = this.card('任务与结果追溯', 'span-2');
    const tasks = Array.from(this.tasks.values()).sort((a, b) => Number(b.createdAt || 0) - Number(a.createdAt || 0));
    if (!tasks.length) trace.append(el('p', 'empty', '当前会话暂无任务结果。'));
    tasks.forEach(task => trace.append(this.renderTaskRecord(task)));
    const governance = this.card('审核与发布');
    const publishable = tasks.filter(task => task.status === 'SUCCEEDED' && task.resultType === 'estimation');
    if (!publishable.length) governance.append(el('p', 'empty', '暂无可审核的参数辨识结果。'));
    publishable.forEach(task => {
      const record = el('div', 'task-record');
      record.append(el('strong', '', this.actionLabel(task.actionKey)), el('small', '', task.id));
      const controls = el('div', 'toolbar compact');
      controls.append(
        button('审核通过', 'btn subtle', () => this.reviewTask(task.id, 'APPROVED')),
        button('审核驳回', 'btn danger', () => this.reviewTask(task.id, 'REJECTED'))
      );
      if (task.reviewStatus === 'APPROVED') controls.append(button('发布为当前辨识模型', 'btn primary', () => this.publishTask(task.id)));
      record.append(controls);
      if (task.reviewStatus) record.append(el('p', 'muted', '审核状态：' + task.reviewStatus));
      if (task.publicationStatus) record.append(el('p', 'notice success', '发布状态：' + task.publicationStatus));
      governance.append(record);
    });
    const grid = el('div', 'grid');
    grid.append(trace, governance);
    container.append(grid);
  }

  renderTaskRecord(task) {
    const node = el('article', 'task-record');
    const head = el('div', 'task-head');
    const title = el('div');
    title.append(el('strong', '', this.actionLabel(task.actionKey)), el('small', '', task.id));
    head.append(title, this.statusPill(task.status));
    node.append(head);
    const meta = el('div', 'task-meta');
    meta.append(el('span', '', '开始：' + formatTime(task.startedAt || task.createdAt)), el('span', '', '结束：' + formatTime(task.completedAt)));
    node.append(meta);
    if (task.error) node.append(el('div', 'notice error', task.error));
    const controls = el('div', 'toolbar compact');
    if (RUNNING.has(task.status)) controls.append(button('取消任务', 'btn danger', () => this.cancelTask(task.id)));
    if (task.status === 'SUCCEEDED') controls.append(button('查看结构化结果', 'btn subtle', () => this.loadOutcome(task.id)));
    controls.append(button('查看日志', 'btn subtle', () => this.loadTaskLog(task.id)));
    node.append(controls);
    const result = this.results.get(task.id);
    if (result) node.append(this.renderValue(result.value !== undefined ? result.value : result, 0));
    const artifacts = this.artifacts.get(task.id);
    if (artifacts) node.append(this.renderArtifacts(artifacts, task.id));
    const log = this.taskLogs.get(task.id);
    if (log !== undefined) node.append(el('pre', 'task-log', log || '暂无日志'));
    return node;
  }

  renderActionButtons(parent, actions, help) {
    if (help) parent.append(el('p', 'muted', help));
    const bar = el('div', 'action-bar');
    if (!actions.length) bar.append(el('span', 'empty', '当前 workflow.actions 未提供对应动作。'));
    actions.forEach(action => {
      const task = this.latestTask(action.key);
      const running = task && RUNNING.has(task.status);
      const start = button(action.label || action.key, 'btn primary', () => this.startAction(action));
      start.disabled = !this.workspace || running || this.busy;
      bar.append(start);
      if (running) bar.append(button('取消', 'btn danger', () => this.cancelTask(task.id)));
    });
    parent.append(bar);
  }

  renderTaskProgress(parent, actions) {
    const task = actions.map(action => this.latestTask(action.key)).filter(Boolean).sort((a, b) => Number(b.createdAt || 0) - Number(a.createdAt || 0))[0];
    if (!task) {
      parent.append(el('p', 'empty', '尚未启动不确定性任务。预计耗时以结构化预估动作结果为准。'));
      return;
    }
    parent.append(this.statusPill(task.status));
    const progress = el('div', 'progress');
    const fill = el('span');
    const numeric = Number(task.progress);
    fill.style.width = Number.isFinite(numeric) ? Math.max(0, Math.min(100, numeric)) + '%' : (RUNNING.has(task.status) ? '35%' : task.status === 'SUCCEEDED' ? '100%' : '0%');
    progress.append(fill);
    parent.append(progress);
    const details = el('div', 'facts vertical');
    this.fact(details, '当前子步骤', task.step || task.currentStep || '—');
    this.fact(details, '已运行时间', task.elapsed || this.elapsed(task));
    this.fact(details, '预计剩余时间', task.estimatedRemaining || '待程序返回');
    this.fact(details, '最终运行时间', task.duration || (task.completedAt && task.startedAt ? this.duration(task.completedAt - task.startedAt) : '—'));
    parent.append(details);
  }

  renderSectionResults(parent, sectionId) {
    const relevant = Array.from(this.tasks.values()).filter(task => {
      const action = this.findAction(task.actionKey);
      return action && actionSection(action) === sectionId && task.status === 'SUCCEEDED';
    });
    if (!relevant.length) {
      parent.append(el('p', 'empty', '待任务完成后显示结构化结果与产物。'));
      return;
    }
    relevant.sort((a, b) => Number(b.completedAt || 0) - Number(a.completedAt || 0));
    relevant.slice(0, 2).forEach(task => {
      const block = el('div', 'result-block');
      block.append(el('h4', '', this.actionLabel(task.actionKey)));
      const result = this.results.get(task.id);
      if (result) block.append(this.renderValue(result.value !== undefined ? result.value : result, 0));
      else block.append(button('加载结构化结果', 'btn subtle', () => this.loadOutcome(task.id)));
      const artifacts = this.artifacts.get(task.id);
      if (artifacts) block.append(this.renderArtifacts(artifacts, task.id));
      parent.append(block);
    });
  }

  renderValue(value, depth) {
    if (value === null || value === undefined) return el('span', 'value-empty', '—');
    if (depth > 3) return el('span', 'value-summary', Array.isArray(value) ? value.length + ' 项' : '结构化对象');
    if (typeof value !== 'object') return el('span', 'value-scalar', String(value));
    if (Array.isArray(value)) return this.renderArray(value, depth);
    const dl = el('dl', 'result-object');
    Object.keys(value).forEach(key => {
      const dt = el('dt', '', key);
      const dd = el('dd');
      dd.append(this.renderValue(value[key], depth + 1));
      dl.append(dt, dd);
    });
    return dl;
  }

  renderArray(rows, depth) {
    if (!rows.length) return el('span', 'value-empty', '空列表');
    const objectRows = rows.filter(item => item && typeof item === 'object' && !Array.isArray(item));
    if (objectRows.length === rows.length) {
      const columns = Array.from(new Set(objectRows.flatMap(item => Object.keys(item)))).slice(0, 12);
      const wrap = el('div', 'table-wrap');
      const table = el('table', 'data-table');
      const thead = el('thead');
      const hr = el('tr');
      columns.forEach(column => hr.append(el('th', '', column)));
      thead.append(hr);
      const tbody = el('tbody');
      objectRows.slice(0, 100).forEach(row => {
        const tr = el('tr');
        columns.forEach(column => {
          const cell = row[column];
          tr.append(el('td', '', cell && typeof cell === 'object' ? JSON.stringify(cell) : (cell === undefined || cell === null ? '—' : cell)));
        });
        tbody.append(tr);
      });
      table.append(thead, tbody);
      wrap.append(table);
      if (rows.length > 100) wrap.append(el('p', 'muted', '仅显示前 100 行，共 ' + rows.length + ' 行。'));
      const result = el('div', 'tabular-result');
      const numericColumns = columns.filter(column => objectRows.some(row => row[column] !== '' && Number.isFinite(Number(row[column]))));
      if (this.ctx.echarts && depth < 3 && objectRows.length > 1 && numericColumns.length) {
        const chartHost = el('div', 'result-chart');
        result.append(chartHost);
        this.scheduleChart(chartHost, objectRows.slice(0, 100), columns[0], numericColumns.slice(0, 4));
      }
      result.append(wrap);
      return result;
    }
    const list = el('ul', 'value-list');
    rows.slice(0, 100).forEach(item => {
      const li = el('li');
      li.append(this.renderValue(item, depth + 1));
      list.append(li);
    });
    return list;
  }

  renderArtifacts(items, taskId) {
    const wrap = el('div', 'artifact-list');
    wrap.append(el('h5', '', '结果产物'));
    if (!items.length) wrap.append(el('p', 'empty', '未发现新增产物。'));
    items.forEach(item => {
      const row = el('div', 'artifact-row');
      const copy = el('div');
      const name = item.name || item.fileName || item.id;
      copy.append(el('strong', '', name), el('small', '', [item.type, formatSize(item.size)].filter(Boolean).join(' · ')));
      const download = button('下载', 'btn subtle', () => {
        this.ctx.http.artifacts.download(taskId + '/' + item.id, name)
          .catch(error => this.ctx.log('产物下载失败：' + (error.message || error)));
      });
      row.append(copy, download);
      wrap.append(row);
    });
    return wrap;
  }

  methodCard(code, title, description) {
    const node = el('div', 'method-card');
    node.append(el('span', 'method-code', code), el('strong', '', title), el('p', '', description));
    return node;
  }

  placeholderMetrics(parent, names) {
    const grid = el('div', 'metric-grid');
    names.forEach(name => {
      const metric = el('div', 'metric');
      metric.append(el('span', '', name), el('strong', '', '待计算'));
      grid.append(metric);
    });
    parent.append(grid);
  }

  field(label, control) {
    const wrapper = el('label', 'field');
    wrapper.append(el('span', 'field-label', label), control);
    return wrapper;
  }

  selectControl(name, options, selected) {
    const select = document.createElement('select');
    select.name = name;
    options.forEach(option => select.append(new Option(option[1], option[0], false, option[0] === selected)));
    return select;
  }

  fact(parent, label, value) {
    const node = el('div', 'fact');
    node.append(el('span', '', label), el('strong', '', value === undefined || value === null || value === '' ? '—' : value));
    parent.append(node);
  }

  statusPill(status) {
    const value = status || 'READY';
    return el('span', 'status-pill status-' + value.toLowerCase(), STATUS_TEXT[value] || value);
  }

  actionsFor(section) {
    return this.actions.filter(action => actionSection(action) === section);
  }

  findAction(key) {
    return this.actions.find(action => action.key === key);
  }

  actionLabel(key) {
    const action = this.findAction(key);
    return action ? (action.label || action.key) : key;
  }

  latestTask(actionKey) {
    return Array.from(this.tasks.values()).filter(task => task.actionKey === actionKey).sort((a, b) => Number(b.createdAt || 0) - Number(a.createdAt || 0))[0];
  }

  hasSuccessfulAction(pattern) {
    return Array.from(this.tasks.values()).some(task => {
      const action = this.findAction(task.actionKey);
      return task.status === 'SUCCEEDED' && action && pattern.test(actionText(action));
    });
  }

  async request(call, activity) {
    try {
      this.ctx.setStatus('loading', activity);
      this.ctx.log(activity);
      const response = await call();
      if (!response || (response.success === false) || (response.code !== undefined && Number(response.code) !== 200 && response.success !== true)) {
        throw new Error(response && (response.message || response.msg) || activity + '失败');
      }
      return response.data !== undefined ? response.data : response;
    } catch (error) {
      if (!this.destroyed) {
        this.ctx.setStatus('error', '操作失败');
        this.ctx.log(activity + '失败：' + (error.message || error));
      }
      throw error;
    }
  }

  async loadWorkspaces() {
    try {
      const list = await this.request(() => this.ctx.http.workspace.list(), '读取工作区');
      if (this.destroyed) return;
      this.workspaces = asArray(list);
      if (this.workspace) {
        const current = this.workspaces.find(item => item.id === this.workspace.id);
        if (!current) this.workspace = null;
      }
      this.ctx.setStatus('ready', '就绪');
      this.ctx.log('工作区已刷新');
      this.render();
    } catch (error) {
      this.render();
    }
  }

  async createWorkspace() {
    if (this.busy) return;
    this.busy = true;
    try {
      const workspace = await this.request(() => this.ctx.http.workspace.create({}), '创建工作区');
      if (this.destroyed) return;
      this.workspace = workspace;
      this.workspaces.unshift(workspace);
      this.uploaded = [];
      this.tasks.clear();
      this.ctx.setStatus('ready', '工作区已创建');
      this.ctx.log('工作区 ' + workspace.id + ' 已创建');
      this.render();
    } catch (error) {
      this.render();
    } finally {
      this.busy = false;
    }
  }

  async selectWorkspace(id) {
    if (!id) {
      this.workspace = null;
      this.uploaded = [];
      this.tasks.clear();
      this.results.clear();
      this.artifacts.clear();
      this.render();
      return;
    }
    try {
      const workspace = await this.request(() => this.ctx.http.workspace.get(id), '打开工作区');
      if (this.destroyed) return;
      this.workspace = workspace;
      await Promise.all([this.loadDatasets(), this.loadTasks()]);
      this.ctx.setStatus('ready', '工作区已打开');
      this.ctx.log('已选择工作区 ' + id);
      this.render();
    } catch (error) {
      this.render();
    }
  }

  async loadDatasets() {
    if (!this.workspace) return;
    const datasets = await this.request(
      () => this.ctx.http.datasets.request(this.workspace.id, { method: 'GET' }),
      '读取数据集'
    );
    if (!this.destroyed) this.uploaded = asArray(datasets);
  }

  async loadTasks() {
    if (!this.workspace) return;
    const tasks = await this.request(
      () => this.ctx.http.tasks.list({ workspaceId: this.workspace.id }),
      '读取任务列表'
    );
    if (this.destroyed) return;
    this.tasks.clear();
    asArray(tasks).forEach(task => {
      this.tasks.set(task.id, task);
      if (RUNNING.has(task.status)) this.schedulePoll(task.id, 500);
    });
  }

  async uploadDataset(datasetKey, file) {
    if (!this.workspace || !file) return;
    const body = new FormData();
    body.append('file', file);
    body.append('datasetKey', datasetKey);
    try {
      await this.request(() => this.ctx.http.datasets.request(this.workspace.id, { method: 'POST', body }), '上传数据集');
      await this.loadDatasets();
      if (this.destroyed) return;
      this.ctx.setStatus('ready', '数据已上传');
      this.ctx.log('数据集 ' + datasetKey + ' 已上传');
      this.render();
    } catch (error) {
      this.render();
    }
  }

  collectActionInputs(action) {
    const inputs = {};
    asArray(action.inputs).forEach(name => {
      if (isDatasetInput(name, this.datasetSpecs)) return;
      if (/modelInput/i.test(name)) {
        const modelInput = {
          point_id: 'CUSTOM_POINT',
          inletBoundaryMode: this.predictionMode === 'pressure' ? 2 : 3
        };
        const keys = this.predictionMode === 'pressure' ? ['Pamb', 'Tamb', 'Mach', 'Wf_model', 'Mkp', 'Mkg'] : ['Altitude', 'Tamb', 'Mach', 'Wf_model', 'Mkp', 'Mkg'];
        keys.forEach(key => {
          const node = this.root.querySelector('[name="predict-' + key + '"]');
          if (!node || node.value === '') throw new Error('请填写预测输入：' + key);
          modelInput[key] = Number(node.value);
        });
        inputs[name] = modelInput;
      } else if (/estimationResultFile/i.test(name)) {
        inputs[name] = '';
      } else if (/posteriorOptions/i.test(name)) {
        const method = this.root.querySelector('[name="posterior-method"]');
        inputs[name] = method && method.value !== 'none' ? { method: method.value, runId: 'latest' } : {};
      } else if (/userCfg|config|options/i.test(name)) {
        inputs[name] = this.buildConfigInput(action);
      } else {
        const control = this.root.querySelector('[name="action-input-' + name + '"]');
        if (!control || control.value === '') throw new Error('动作需要配置输入：' + name);
        inputs[name] = control.type === 'number' ? Number(control.value) : control.value;
      }
    });
    return inputs;
  }

  buildConfigInput(action) {
    if (actionSection(action) === 'uq') {
      const samples = this.root.querySelector('[name="uq-samples"]');
      const value = { figureVisible: 'off' };
      if (samples && samples.value !== '') {
        value.formalSampleCount = Number(samples.value);
        value.posteriorPredictiveSampleCount = Number(samples.value);
      }
      if (/methodB|uqB/i.test(action.key || '')) value.runAdditionalSteadyPrediction = true;
      return value;
    }
    return {};
  }

  ensureGenericInputs(action) {
    const missing = asArray(action.inputs).filter(name => !isDatasetInput(name, this.datasetSpecs) && !/modelInput|estimationResultFile|posteriorOptions|userCfg|config|options/i.test(name));
    if (!missing.length) return true;
    const existing = this.root.querySelector('.generic-inputs[data-action="' + action.key + '"]');
    if (existing) return true;
    const target = this.content.querySelector('.action-bar');
    if (!target) return false;
    const form = el('div', 'generic-inputs');
    form.dataset.action = action.key;
    form.append(el('p', 'muted', '该动作声明了额外结构化输入，请填写后再次启动。'));
    missing.forEach(name => form.append(this.field(name, input('text', 'action-input-' + name, '', name))));
    target.before(form);
    return false;
  }

  async startAction(action) {
    if (!this.workspace || this.busy) return;
    const section = actionSection(action);
    if (section === 'identifiability' && (!this.hasSuccessfulAction(/estimateSteady|稳态模型参数/) || !this.hasSuccessfulAction(/estimateTransient|瞬态时刻/))) {
      this.ctx.log('工程可辨识性分析前必须先完成稳态和瞬态时刻两条辨识路径。');
      return;
    }
    if (['uq', 'validation', 'prediction'].includes(section) && !this.hasSuccessfulAction(/estimateTransient|瞬态时刻/)) {
      this.ctx.log('该任务前必须先完成瞬态时刻模型参数辨识。');
      return;
    }
    if (!this.ensureGenericInputs(action)) return;
    this.busy = true;
    try {
      const inputs = this.collectActionInputs(action);
      const task = await this.request(() => this.ctx.http.tasks.create({ workspaceId: this.workspace.id, actionKey: action.key, inputs }), '提交任务：' + (action.label || action.key));
      if (this.destroyed) return;
      this.tasks.set(task.id, task);
      this.ctx.setStatus('running', '任务运行中');
      this.ctx.log('任务 ' + task.id + ' 已提交');
      this.render();
      this.schedulePoll(task.id, 500);
    } catch (error) {
      this.render();
    } finally {
      this.busy = false;
    }
  }

  schedulePoll(taskId, delay) {
    if (this.destroyed) return;
    const timer = setTimeout(() => {
      this.timers.delete(timer);
      this.pollTask(taskId);
    }, delay);
    this.timers.add(timer);
  }

  async pollTask(taskId) {
    if (this.destroyed) return;
    try {
      const task = await this.request(() => this.ctx.http.tasks.get(taskId), '刷新任务状态');
      if (this.destroyed) return;
      this.tasks.set(task.id, task);
      if (TERMINAL.has(task.status)) {
        this.ctx.setStatus(task.status === 'SUCCEEDED' ? 'ready' : 'error', STATUS_TEXT[task.status] || task.status);
        this.ctx.log('任务 ' + task.id + '：' + (STATUS_TEXT[task.status] || task.status));
        if (task.status === 'SUCCEEDED') await this.loadOutcome(task.id, false);
        else await this.loadArtifacts(task.id, false);
      } else {
        this.ctx.setStatus('running', STATUS_TEXT[task.status] || task.status);
        this.schedulePoll(taskId, 2000);
      }
      this.render();
    } catch (error) {
      if (!this.destroyed) this.schedulePoll(taskId, 5000);
    }
  }

  async cancelTask(taskId) {
    try {
      const task = await this.request(() => this.ctx.http.tasks.request(taskId + '/cancel', { method: 'POST' }), '请求取消任务');
      if (this.destroyed) return;
      this.tasks.set(task.id, task);
      this.ctx.setStatus('running', '取消中');
      this.ctx.log('任务已请求取消；原始程序包不支持中途取消，将等待当前 MATLAB 调用结束后生效');
      this.render();
      this.schedulePoll(taskId, 1000);
    } catch (error) {
      this.render();
    }
  }

  async loadTaskLog(taskId) {
    try {
      const log = await this.request(() => this.ctx.http.tasks.request(taskId + '/log', { method: 'GET' }), '读取任务日志');
      if (!this.destroyed) this.taskLogs.set(taskId, log && log.content ? log.content : '');
      this.render();
    } catch (error) {
      this.render();
    }
  }

  async reviewTask(taskId, decision) {
    try {
      const task = await this.request(
        () => this.ctx.http.results.request(taskId + '/review', { method: 'POST', body: { decision, notes: '' } }),
        decision === 'APPROVED' ? '审核通过' : '审核驳回'
      );
      if (!this.destroyed) this.tasks.set(task.id, task);
      this.render();
    } catch (error) {
      this.render();
    }
  }

  async publishTask(taskId) {
    try {
      await this.request(
        () => this.ctx.http.results.request(taskId + '/publish', { method: 'POST', body: {} }),
        '发布辨识模型'
      );
      const task = await this.request(() => this.ctx.http.tasks.get(taskId), '刷新发布状态');
      if (!this.destroyed) this.tasks.set(task.id, task);
      this.render();
    } catch (error) {
      this.render();
    }
  }

  async loadOutcome(taskId, rerender = true) {
    try {
      const result = await this.request(() => this.ctx.http.results.get(taskId), '读取结构化结果');
      if (this.destroyed) return;
      this.results.set(taskId, result);
      await this.loadArtifacts(taskId, false);
      this.ctx.setStatus('ready', '结果已加载');
      this.ctx.log('结构化结果与产物已加载');
      if (rerender) this.render();
    } catch (error) {
      if (rerender) this.render();
    }
  }

  async loadArtifacts(taskId, rerender = true) {
    try {
      const artifacts = await this.request(() => this.ctx.http.artifacts.request(taskId, { method: 'GET' }), '读取结果产物');
      if (!this.destroyed) this.artifacts.set(taskId, asArray(artifacts));
      if (rerender) this.render();
    } catch (error) {
      if (rerender) this.render();
    }
  }

  elapsed(task) {
    if (!task.startedAt) return '—';
    return this.duration((task.completedAt || Date.now()) - task.startedAt);
  }

  duration(milliseconds) {
    const seconds = Math.max(0, Math.floor(Number(milliseconds) / 1000));
    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    const rest = seconds % 60;
    return [hours ? hours + '小时' : '', minutes ? minutes + '分' : '', rest + '秒'].filter(Boolean).join(' ');
  }

  scheduleChart(host, rows, categoryColumn, numericColumns) {
    const timer = setTimeout(() => {
      this.timers.delete(timer);
      if (this.destroyed || !host.isConnected) return;
      try {
        const chart = this.ctx.echarts.init(host, null, { renderer: 'canvas' });
        chart.setOption({
          animation: false,
          color: ['#17698d', '#4f8f72', '#b4792b', '#8b5b8f'],
          tooltip: { trigger: 'axis' },
          legend: { type: 'scroll', top: 2, textStyle: { fontSize: 10 } },
          grid: { left: 48, right: 18, top: 38, bottom: 42, containLabel: true },
          xAxis: {
            type: 'category',
            name: categoryColumn,
            data: rows.map((row, index) => row[categoryColumn] === undefined ? String(index + 1) : String(row[categoryColumn])),
            axisLabel: { fontSize: 10, hideOverlap: true }
          },
          yAxis: { type: 'value', axisLabel: { fontSize: 10 }, scale: true },
          series: numericColumns.map(column => ({
            name: column,
            type: 'line',
            symbolSize: 5,
            connectNulls: false,
            data: rows.map(row => Number.isFinite(Number(row[column])) ? Number(row[column]) : null)
          }))
        });
        this.charts.push(chart);
      } catch (error) {
        host.replaceChildren(el('p', 'empty', '图表初始化失败，表格数据仍可查看。'));
      }
    }, 0);
    this.timers.add(timer);
  }

  resize() {
    this.charts.forEach(chart => {
      try { chart.resize(); } catch (error) { /* chart may already be detached */ }
    });
  }

  disposeCharts() {
    this.charts.forEach(chart => {
      try { chart.dispose(); } catch (error) { /* chart may already be disposed */ }
    });
    this.charts = [];
  }

  destroy() {
    this.destroyed = true;
    this.timers.forEach(timer => clearTimeout(timer));
    this.timers.clear();
    this.listeners.forEach(item => item.target.removeEventListener(item.type, item.handler, item.options));
    this.listeners = [];
    this.disposeCharts();
    this.tasks.clear();
    this.results.clear();
    this.artifacts.clear();
    this.taskLogs.clear();
    if (this.ctx.mount) this.ctx.mount.replaceChildren();
    this.root = null;
  }
}

export default SteadyModelAdaptV1;
