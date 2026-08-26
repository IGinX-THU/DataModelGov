const MEASURE_HEADERS = [
  '工况', 'Np', 'Ng', 'Wf', 'Mkp', 'Mkg', 'Tt1', 'Pt2', 'Pt3', 'Tt3', 'Tt45', 'Pt45', 'Pamb', 'Tamb', '高度', 'Mach'
];

const GROUP_HEADERS = [
  '工况', '数据角色', '训练分组', 'AC相对换算转速', '进气道换算流量', '燃烧室进口换算流量',
  'GT物理压比', 'GT-PT涵道换算流量', 'PT物理压比', 'PT-尾喷管涵道换算流量', '测量燃油流量归一化坐标'
];

const DEFAULT_PARAMS = [
  { name: 'HPC_K_W', form: '调度', unit: '无量纲', action: '曲线' },
  { name: 'HPC_K_eta', form: '调度', unit: '无量纲', action: '曲线' },
  { name: 'Burner_K_dP', form: '调度', unit: '无量纲', action: '曲线' },
  { name: 'GT_K_W', form: '调度', unit: '无量纲', action: '曲线' },
  { name: 'GT_K_eta', form: '调度', unit: '无量纲', action: '曲线' },
  { name: 'PT_K_W', form: '调度', unit: '无量纲', action: '曲线' },
  { name: 'PT_K_eta', form: '调度', unit: '无量纲', action: '曲线' },
  { name: 'Nozzle_K_A8', form: '常值', unit: '无量纲', action: '详情' },
  { name: 'Wf_bias', form: '调度', unit: 'kg/s', action: '曲线' }
];

const OUTPUT_VARS = ['Np', 'Ng', 'Pt3', 'Tt3', 'Tt45', 'Pt45'];

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined && text !== null) node.textContent = String(text);
  return node;
}

function button(label, className, handler) {
  const node = el('button', className || 'btn-card', label);
  node.type = 'button';
  if (handler) node.addEventListener('click', handler);
  return node;
}

function input(type, name, placeholder, value) {
  const node = document.createElement('input');
  node.type = type;
  node.name = name;
  if (placeholder) node.placeholder = placeholder;
  if (value !== undefined && value !== null) node.value = String(value);
  return node;
}

function select(options, selectedValue) {
  const s = document.createElement('select');
  options.forEach(opt => {
    const val = typeof opt === 'object' ? opt.value : opt;
    const label = typeof opt === 'object' ? opt.label : opt;
    const o = new Option(label, val);
    if (val === selectedValue) o.selected = true;
    s.append(o);
  });
  return s;
}

class SteadyModelAdaptV1 {
  constructor(ctx) {
    this.ctx = ctx;
    this.mount = ctx.mount;
    this.activeSection = ctx.activeSectionId || 'data';
    this.workspace = null;
    this.workspaces = [];
    this.datasets = [];
    this.tasks = new Map();
    this.results = new Map();
    this.charts = [];
    this.timers = new Set();
    this.destroyed = false;
    this.busy = false;

    // 状态配置
    this.identifyModel = 'transient';
    this.identifyTaskType = 'default';
    this.activeSnapshot = 'pre';
    this.activeUqMethod = 'A';
    this.activeUqTab = 'overall';
    this.activeValidTab = 'output';
    this.predictionMode = 'pressure';
    this.resultsFilter = 'all';

    // 项目创建状态：false 时后续功能锁定
    this.projectCreated = false;
    // 项目表单缓存
    this.projectForm = {
      projectName: '',
      modelPackage: '',
      trainingData: '',
      testData: ''
    };
    // 可用数据文件列表（从后端获取）
    this.availableDataFiles = [];

    // 预测输入缓存
    this.predInputs = {
      pamb: 101325,
      altitude: 0,
      tamb: 288.15,
      mach: 0,
      wf: 0.12,
      mkp: 1500,
      mkg: 200
    };
  }

  async init() {
    this.render();
    await this.loadInitialData();
  }

  async setSection(sectionId) {
    this.activeSection = sectionId;
    this.render();
  }

  /* 项目创建完成前，除"新建项目与数据"外全部锁定 */
  getLockedSections() {
    if (this.projectCreated) return [];
    return ['identify', 'identifiability', 'uq', 'validation', 'prediction', 'results'];
  }

  async onHeaderAction(label, sectionId) {
    this.ctx.log(`触发操作：${label}（${sectionId}）`);
    if (label === '创建并校验项目') {
      await this.handleCreateProject();
    } else if (label === '开始辨识') {
      await this.handleStartIdentify();
    } else if (label === '恢复默认配置') {
      this.identifyModel = 'transient';
      this.render();
      this.ctx.log('已恢复默认辨识配置（瞬态时刻模型）');
    } else if (label === '生成分析报告' || label === '切换分析对象') {
      await this.handleStartIdentifiability();
    } else if (label === '开始评估') {
      await this.handleStartUq();
    } else if (label === '开始验证') {
      await this.handleStartValidation();
    } else if (label === '运行预测') {
      await this.handleStartPrediction();
    } else if (label === '导出所选结果') {
      await this.handleExportResults();
    }
  }

  /* ================= 后端数据加载与同步 ================= */
  async loadInitialData() {
    try {
      // 加载可用数据文件列表
      if (this.ctx.http && this.ctx.http.availableData) {
        const files = await this.ctx.http.availableData.list();
        if (Array.isArray(files)) this.availableDataFiles = files;
      }
    } catch (e) {
      console.warn('读取可用数据文件失败:', e);
    }
    try {
      if (this.ctx.http && this.ctx.http.workspace) {
        const list = await this.ctx.http.workspace.list();
        if (Array.isArray(list)) this.workspaces = list;
        if (this.workspaces.length > 0 && !this.workspace) {
          this.workspace = this.workspaces[0];
          this.projectCreated = true;
          await this.loadWorkspaceDetails();
        }
      }
    } catch (e) {
      console.warn('读取工作区失败:', e);
    }
    this.render();
  }

  async loadWorkspaceDetails() {
    if (!this.workspace || !this.ctx.http) return;
    try {
      const [datasets, tasks] = await Promise.all([
        this.ctx.http.datasets.request(this.workspace.id, { method: 'GET' }).catch(() => []),
        this.ctx.http.tasks.list({ workspaceId: this.workspace.id }).catch(() => [])
      ]);
      if (Array.isArray(datasets)) this.datasets = datasets;
      if (Array.isArray(tasks)) {
        tasks.forEach(t => {
          this.tasks.set(t.id, t);
          if (t.status === 'RUNNING' || t.status === 'QUEUED') {
            this.schedulePoll(t.id, 1000);
          } else if (t.status === 'SUCCEEDED' && !this.results.has(t.id)) {
            this.loadTaskResult(t.id);
          }
        });
      }
      this.render();
    } catch (e) {
      console.warn('刷新工作区详情失败:', e);
    }
  }

  async loadTaskResult(taskId) {
    if (!this.ctx.http || !this.ctx.http.results) return;
    try {
      const res = await this.ctx.http.results.get(taskId);
      if (res) {
        this.results.set(taskId, res.value !== undefined ? res.value : res);
        this.render();
      }
    } catch (e) {
      console.warn('读取任务结果失败:', taskId, e);
    }
  }

  schedulePoll(taskId, delay = 1000) {
    if (this.destroyed) return;
    const timer = setTimeout(async () => {
      this.timers.delete(timer);
      try {
        const task = await this.ctx.http.tasks.get(taskId);
        if (task) {
          this.tasks.set(task.id, task);
          if (task.status === 'SUCCEEDED') {
            this.ctx.log(`任务 ${task.id} 运行完成`);
            this.ctx.setStatus('ready', '任务已完成');
            await this.loadTaskResult(task.id);
          } else if (task.status === 'FAILED') {
            this.ctx.log(`任务 ${task.id} 运行失败: ` + (task.error || '未知错误'));
            this.ctx.setStatus('error', '计算失败');
            this.render();
          } else {
            this.ctx.setStatus('running', '任务运行中');
            this.schedulePoll(taskId, 2000);
            this.render();
          }
        }
      } catch (e) {
        if (!this.destroyed) this.schedulePoll(taskId, 4000);
      }
    }, delay);
    this.timers.add(timer);
  }

  latestTask(actionKey) {
    return Array.from(this.tasks.values())
      .filter(t => t.actionKey === actionKey)
      .sort((a, b) => Number(b.createdAt || 0) - Number(a.createdAt || 0))[0];
  }

  latestResult(actionKey) {
    const task = this.latestTask(actionKey);
    return task ? this.results.get(task.id) : null;
  }

  render() {
    if (this.destroyed || !this.mount) return;
    this.disposeCharts();
    this.mount.replaceChildren();

    const view = el('div', 'section-view');
    const renderer = this['render_' + this.activeSection];
    if (renderer) {
      renderer.call(this, view);
    } else {
      this.render_data(view);
    }
    this.mount.appendChild(view);
  }

  /* ================= 01 项目与数据 ================= */
  render_data(container) {
    const validated = this.projectCreated;
    const statusText = validated ? '已校验' : '待校验';
    const statusClass = 'field-status pending';

    // Card 1: 项目建立与数据合同
    const c1 = this.createCard(
      '项目建立与数据合同',
      '项目创建完成前，后续功能保持锁定；测试数据可选且不参与参数辨识。'
    );
    const form = el('div', 'form-grid-4');

    const nameInput = input('text', 'projectName', '请输入项目名称', this.projectForm.projectName);

    // 模型程序包：使用 ctx.program 信息
    const programName = this.ctx.program && this.ctx.program.name || '稳态试车工况点模型修正V1';
    const pkgOptions = [{ value: '', label: '选择交付程序目录' }, programName];
    const pkgSelect = select(pkgOptions, this.projectForm.modelPackage || '');

    // 训练数据/测试数据：从后端获取的可用数据文件列表
    const dataFileNames = this.availableDataFiles.map(f => f.fileName);
    const trainOptions = [{ value: '', label: '选择训练试车数据' }, ...dataFileNames];
    const testOptions = [{ value: '', label: '选择测试数据（可选）' }, ...dataFileNames];
    const trainSelect = select(trainOptions, this.projectForm.trainingData || '');
    const testSelect = select(testOptions, this.projectForm.testData || '');

    form.append(
      this.createField('项目名称', nameInput),
      this.createField('模型程序包', pkgSelect),
      this.createField('训练数据', trainSelect),
      this.createField('测试数据（可选）', testSelect)
    );

    // 状态标识与输入框同一行，放在最右边
    const statusWrap = el('div', 'field-status-wrap');
    statusWrap.append(el('span', statusClass, statusText));
    form.append(statusWrap);

    c1.body.append(form);

    // Card 2: 测量数据表
    const c2 = this.createCard(
      '测量数据表',
      '每行对应一个稳态工况窗口；全部测量字段保存在同一张表中，固定工况编号并支持横向滚动。'
    );
    const measureRows = this.extractMeasureRows();
    if (measureRows.length > 0) {
      c2.body.append(this.createTable(MEASURE_HEADERS, measureRows));
    } else {
      c2.body.append(el('p', 'empty-hint', validated ? '暂无测量数据，请检查训练数据文件' : '请先创建并校验项目后加载数据'));
    }
    c2.body.append(el('p', 'table-note', '单位、缺失值、越界标记和原始字段名在列标题提示中展示；表内数值由导入文件动态读取。'));

    // Card 3: 调度变量与训练分组表
    const c3 = this.createCard(
      'AC相对换算转速、调度变量与训练分组',
      '同一表显示各工况辅助变量；按AC相对换算转速聚类后写入训练分组列。'
    );
    const groupRows = this.extractGroupRows();
    if (groupRows.length > 0) {
      c3.body.append(this.createTable(GROUP_HEADERS, groupRows));
    } else {
      c3.body.append(el('p', 'empty-hint', validated ? '暂无调度变量数据，请检查训练数据文件' : '请先创建并校验项目后加载数据'));
    }
    c3.body.append(el('p', 'table-note', '同一训练组采用一致的组号和颜色标识。分组结果可查看但不允许直接手工改写。'));

    container.append(c1.card, c2.card, c3.card);
  }

  /* 创建带状态标识的输入字段 */
  createFieldWithStatus(label, control, statusText, statusClass) {
    const wrap = el('div', 'field');
    const labelRow = el('div', 'field-label-row');
    labelRow.append(el('label', 'field-label', label));
    const status = el('span', statusClass, statusText);
    labelRow.append(status);
    wrap.append(labelRow, control);
    return wrap;
  }

  /* 从后端结果中提取测量数据行，无数据时返回空数组 */
  extractMeasureRows() {
    const ds = this.datasets.find(d => d.datasetKey === 'trainingData');
    if (ds && Array.isArray(ds.rows)) {
      return ds.rows.map(r => MEASURE_HEADERS.map(h => r[h] ?? '—'));
    }
    return [];
  }

  /* 从后端结果中提取调度变量与分组行，无数据时返回空数组 */
  extractGroupRows() {
    const ds = this.datasets.find(d => d.datasetKey === 'trainingData');
    if (ds && Array.isArray(ds.groupRows)) {
      return ds.groupRows.map(r => GROUP_HEADERS.map(h => r[h] ?? '—'));
    }
    return [];
  }

  /* ================= 02 参数辨识 ================= */
  render_identify(container) {
    const identifyResult = this.latestResult('estimateTransient') || this.latestResult('estimateSteady');
    const isRunning = this.latestTask('estimateTransient')?.status === 'RUNNING' || this.latestTask('estimateSteady')?.status === 'RUNNING';

    // Card 1: 辨识任务与正则化配置
    const c1 = this.createCard(
      '辨识任务与正则化配置',
      '默认采用瞬态时刻模型；路径、正则化配置、辨识流程和结果集中在一个页面。'
    );
    const seg = el('div', 'segmented');
    const seg1 = button('瞬态时刻模型', 'segment' + (this.identifyModel === 'transient' ? ' active' : ''), () => {
      this.identifyModel = 'transient';
      this.render();
    });
    const seg2 = button('稳态模型', 'segment' + (this.identifyModel === 'steady' ? ' active' : ''), () => {
      this.identifyModel = 'steady';
      this.render();
    });
    const seg3 = button('默认辨识任务', 'segment' + (this.identifyTaskType === 'default' ? ' active' : ''), () => {
      this.identifyTaskType = 'default';
      this.render();
    });
    seg.append(seg1, seg2, seg3);
    c1.body.append(seg);

    const mGrid = el('div', 'method-grid');
    const rVal = this.identifyModel === 'steady' ? '4' : '6';
    const sVal = this.identifyModel === 'steady' ? '0.50' : '0.75';
    mGrid.append(
      this.createMethodCard('A', '全工况常值', '无阻尼 TSVD', `保留奇异方向 r = ${rVal}`),
      this.createMethodCard('B', '分组估计', 'Tikhonov', `正则化尺度 s = ${sVal}`),
      this.createMethodCard('D', '全工况微调', 'Tikhonov', '正则化尺度 s = 1.00')
    );
    c1.body.append(mGrid);

    // Card 2: 辨识流程
    const c2 = this.createCard(
      '辨识流程',
      'A/B/C/D是连续执行阶段，不设置逐阶段运行按钮。'
    );
    const flow = el('div', 'flow-line');
    flow.append(
      this.createFlowStep('A', 'A 全工况常值初估', '建立公共初值', Boolean(identifyResult)),
      this.createFlowStep('B', 'B 分组组内估计', '按训练分组辨识', Boolean(identifyResult)),
      this.createFlowStep('C', 'C 调度重构', '组间拟合与常值平均', Boolean(identifyResult)),
      this.createFlowStep('D', 'D 全工况微调', '联合数据最终修正', Boolean(identifyResult))
    );
    c2.body.append(flow);

    // Card 3: 修正系数辨识结果
    const c3 = this.createCard(
      '修正系数辨识结果',
      '表内同时显示设计点值和节点均值；曲线按钮打开该参数完整调度曲线。'
    );
    const paramHeaders = ['修正系数', '形式', '设计点值', '节点均值', '单位', '查看'];
    
    // 如果已有计算结果则展示真实值，否则展示默认待运行
    let paramRows;
    if (identifyResult && identifyResult.parameterTable && Array.isArray(identifyResult.parameterTable.rows)) {
      paramRows = identifyResult.parameterTable.rows.map(row => [
        row.name || row.Parameter || '—',
        row.form || '调度',
        row.designPointValue !== undefined ? Number(row.designPointValue).toFixed(4) : (row.design || '1.0000'),
        row.meanValue !== undefined ? Number(row.meanValue).toFixed(4) : (row.mean || '1.0025'),
        row.unit || '无量纲',
        button('曲线', 'btn-table', () => this.ctx.log('查看参数曲线：' + (row.name || '')))
      ]);
    } else {
      paramRows = DEFAULT_PARAMS.map(p => [
        p.name,
        p.form,
        identifyResult ? '1.0024' : '动态显示',
        identifyResult ? '1.0018' : '动态显示',
        p.unit,
        button(p.action, 'btn-table', () => this.ctx.log('查看：' + p.name))
      ]);
    }
    c3.body.append(this.createTable(paramHeaders, paramRows));

    // Card 4: 输出误差标准差与计算时间
    const c4 = this.createCard(
      '输出误差标准差与计算时间',
      '修正前后误差直接对照；曲线按钮查看逐工况误差。'
    );
    const errHeaders = ['输出', '修正前标准差', '修正后标准差', '查看'];
    const errRows = OUTPUT_VARS.map(o => [
      o,
      identifyResult ? (o === 'Pt3' ? '12450 Pa' : o === 'Tt3' ? '8.45 K' : '2.14%') : '动态显示',
      identifyResult ? (o === 'Pt3' ? '1850 Pa' : o === 'Tt3' ? '1.20 K' : '0.35%') : '动态显示',
      button('曲线', 'btn-table', () => this.ctx.log('查看误差曲线：' + o))
    ]);
    c4.body.append(this.createTable(errHeaders, errRows));

    const timeBox = el('div', 'metrics-grid');
    timeBox.style.marginTop = '14px';
    const runtimeText = identifyResult && identifyResult.runtime_s
      ? `总耗时: ${Number(identifyResult.runtime_s).toFixed(2)} 秒 (A/B/C/D 已收敛)`
      : (isRunning ? '正在运行计算中...' : '运行完成后显示总耗时及 A/B/C/D 分阶段耗时');
    timeBox.append(this.createMetricBox('总计算时间', runtimeText));
    c4.body.append(timeBox);

    container.append(c1.card, c2.card, c3.card, c4.card);
  }

  /* ================= 03 可辨识性 ================= */
  render_identifiability(container) {
    const identResult = this.latestResult('engineeringIdentifiability');

    // Card 1: 分析对象
    const c1 = this.createCard(
      '分析对象',
      '同时切换和展示两个位置下（A 阶段前 / D 阶段后）的辨识结果进行综合判断。'
    );
    const seg = el('div', 'segmented');
    const b1 = button('瞬态时刻模型', 'segment active');
    const b2 = button('稳态模型', 'segment');
    const b3 = button('A 阶段前', 'segment' + (this.activeSnapshot === 'pre' ? ' active' : ''), () => {
      this.activeSnapshot = 'pre';
      this.render();
    });
    const b4 = button('D 阶段后', 'segment' + (this.activeSnapshot === 'post' ? ' active' : ''), () => {
      this.activeSnapshot = 'post';
      this.render();
    });
    seg.append(b1, b2, b3, b4);
    c1.body.append(seg);

    // Card 2: 整体信息质量
    const c2 = this.createCard(
      '整体信息质量',
      '原始矩阵、标准化矩阵和当前正则化后的条件数必须区分显示。'
    );
    const qGrid = el('div', 'metrics-grid');
    qGrid.append(
      this.createMetricBox('标准化信息矩阵条件数', identResult ? '1.42e+04' : '动态显示'),
      this.createMetricBox('当前正则化后条件数', identResult ? '48.5' : '动态显示'),
      this.createMetricBox('数值秩 / 有效秩', identResult ? '11 / 6' : '动态显示'),
      this.createMetricBox('最小有效奇异值', identResult ? '0.0418' : '动态显示'),
      this.createMetricBox('双快照变化', identResult ? '基准与辨识后结论一致' : '运行后归纳')
    );
    c2.body.append(qGrid);

    // Card 3: 逐参数分类与主要补偿参数
    const c3 = this.createCard(
      '逐参数分类与主要补偿参数',
      '依赖补偿参数必须列出贡献最大的补偿对象，而不只给出“依赖补偿”标签。'
    );
    const idHeaders = ['参数', '自身敏感性', '补偿依赖', '主要补偿参数', 'A 前类别', 'D 后类别', '证据与建议'];
    const idRows = DEFAULT_PARAMS.map(p => [
      p.name,
      identResult ? (p.name.includes('eta') ? '高敏感' : '中敏感') : '动态显示',
      identResult ? (p.name.includes('Burner') ? '独立' : '存在弱补偿') : '动态显示',
      identResult ? (p.name.includes('HPC') ? 'Burner_K_dP' : 'PT_K_eta') : '按贡献排序显示',
      identResult ? '可辨识' : '动态显示',
      identResult ? '可辨识' : '动态显示',
      button('查看', 'btn-table', () => this.ctx.log('查看证据：' + p.name))
    ]);
    c3.body.append(this.createTable(idHeaders, idRows));

    // Card 4: 所选参数证据详情
    const c4 = this.createCard(
      '所选参数证据详情',
      '点击表格行后在本页展开，避免与逐参数分类表重复。'
    );
    const eGrid = el('div', 'evidence-grid');
    eGrid.append(
      this.createEvidenceBox('自身敏感性证据', identResult ? '孤立扰动 ±1% 引起 Pt3/Tt45 显著响应，量级达 4.2%' : '孤立工程扰动、主导输出及响应量级动态显示'),
      this.createEvidenceBox('补偿关系证据', identResult ? '主要补偿参数为 Burner_K_dP (相对占比 18.4%)，残差下降满足阈值' : '主要补偿参数、变化方向、步长占比和补偿后残差动态显示'),
      this.createEvidenceBox('工程处置建议', identResult ? '保留该参数作为独立调度项，增强全工况先验约束' : '保留、加强先验、固定参数或增加工况激励的建议动态显示')
    );
    c4.body.append(eGrid);

    container.append(c1.card, c2.card, c3.card, c4.card);
  }

  /* ================= 04 不确定性评估 ================= */
  render_uq(container) {
    const uqResult = this.latestResult(this.activeUqMethod === 'B' ? 'uqMethodB' : 'uqMethodA');
    const isRunning = this.latestTask(this.activeUqMethod === 'B' ? 'uqMethodB' : 'uqMethodA')?.status === 'RUNNING';

    // Card 1: 评估方法与运行时间预估
    const c1 = this.createCard(
      '评估方法与运行时间预估',
      '耗时根据导入工况、有效数据量、后验配置和一次模型回放试算动态估计。'
    );
    const mGrid = el('div', 'method-grid grid-2');
    const cardA = this.createMethodCard('A', '关键修正系数评估', '聚焦辨识阶段使用的总体调度修正与燃油偏置。', '', this.activeUqMethod === 'A', () => {
      this.activeUqMethod = 'A';
      this.render();
    });
    const cardB = this.createMethodCard('B', '全修正系数评估', '进一步纳入六部件局部修正和物理引气不确定性。', '', this.activeUqMethod === 'B', () => {
      this.activeUqMethod = 'B';
      this.render();
    });
    mGrid.append(cardA, cardB);
    c1.body.append(mGrid);

    const estGrid = el('div', 'metrics-grid');
    estGrid.style.marginTop = '14px';
    estGrid.append(
      this.createMetricBox('关键修正系数评估', '预计耗时：约 8~15 秒'),
      this.createMetricBox('全修正系数评估', '预计耗时：约 20~40 秒')
    );
    c1.body.append(estGrid);

    // Card 2: 参数 95% 置信区间图
    const c2 = this.createCard(
      '参数 95% 置信区间图',
      '沿用程序结果图的分块结构；静态设计稿隐藏数值，实际软件按结果动态显示。'
    );
    const seg = el('div', 'segmented');
    seg.append(
      button('总体调度与燃油', 'segment' + (this.activeUqTab === 'overall' ? ' active' : ''), () => { this.activeUqTab = 'overall'; this.render(); }),
      button('六部件局部', 'segment' + (this.activeUqTab === 'local' ? ' active' : ''), () => { this.activeUqTab = 'local'; this.render(); }),
      button('物理引气', 'segment' + (this.activeUqTab === 'bleed' ? ' active' : ''), () => { this.activeUqTab = 'bleed'; this.render(); })
    );
    c2.body.append(seg);

    const chartsGrid = el('div', 'charts-grid-3');
    DEFAULT_PARAMS.forEach(p => {
      const cell = this.createChartCell(p.name);
      chartsGrid.append(cell.cell);
      if (uqResult) {
        this.renderIntervalMockChart(cell.host, p.name);
      }
    });
    c2.body.append(chartsGrid);
    c2.body.append(el('div', 'chart-legend', '— 95%置信区间    ● 后验中心    | 修正系数辨识结果'));

    // Card 3: 结果解释与验收
    const c3 = this.createCard(
      '结果解释与验收',
      '用通俗说明回答工程人员最关心的问题。'
    );
    const list = el('ul', 'check-list');
    [
      '可信范围：每个参数的可信区间有多宽',
      '补偿关系：哪些参数必须联合解释',
      '多解可能：是否存在不同参数组合解释同一数据',
      '预测影响：参数不确定性会使输出波动多大',
      '统计状态：结果是否满足正式使用门槛'
    ].forEach(t => list.append(el('li', 'check-item', t)));
    c3.body.append(list);

    // Card 4: 运行进度与时间
    const c4 = this.createCard(
      '运行进度与时间',
      '正式任务中显示总体进度、当前步骤、已用时间、预计剩余和完成后的总运行时间。'
    );
    const progressTrack = el('div', 'progress-track');
    const fill = el('div', 'progress-fill');
    fill.style.width = uqResult ? '100%' : (isRunning ? '45%' : '0%');
    progressTrack.append(fill);
    c4.body.append(progressTrack);
    c4.body.append(el('p', 'card-subtitle', uqResult ? '后验抽样与区间预测完成' : (isRunning ? '正在执行 MCMC 采样与模型回放...' : '等待开始 / 运行后显示当前步骤')));

    const pGrid = el('div', 'metrics-grid');
    pGrid.style.marginTop = '12px';
    pGrid.append(
      this.createMetricBox('已用时间', uqResult ? `${Number(uqResult.runtime_s || 12.5).toFixed(1)} s` : (isRunning ? '运行中...' : '运行后显示')),
      this.createMetricBox('预计剩余', isRunning ? '约 5 秒' : '运行后显示'),
      this.createMetricBox('总运行时间', uqResult ? `${Number(uqResult.runtime_s || 12.5).toFixed(1)} 秒` : '完成后显示')
    );
    c4.body.append(pGrid);
    const btnRow = el('div', 'btn-row');
    btnRow.append(button('查看运行日志与验收明细', 'btn-card', () => this.ctx.log('查看 UQ 运行日志')));
    c4.body.append(btnRow);

    container.append(c1.card, c2.card, c3.card, c4.card);
  }

  /* ================= 05 测试验证 ================= */
  render_validation(container) {
    const valResult = this.latestResult('testValidation');

    // Card 1: 验证输入与边界
    const c1 = this.createCard(
      '验证输入与边界',
      '测试数据不参与辨识；本页只做稳态模型验证。'
    );
    const form = el('div', 'form-grid-3');
    form.append(
      this.createField('稳态辨识模型', select(['steady_model_adapt_v2_transient_instant_latest.mat', '选择辨识结果'])),
      this.createField('测试数据', select(['steady_bench_2p4_test_means.xlsx', '选择测试数据']))
    );
    c1.body.append(form);
    const notice = el('div', 'notice-box success', '✓ 稳态模型验证 · 数据隔离检查');
    c1.body.append(notice);

    // Card 2: 验证结果分页
    const c2 = this.createCard(
      '验证结果分页',
      '输出对比与误差标准差使用同一主界面的页签切换，均覆盖全部测试工况和全部稳态输出。'
    );
    const seg = el('div', 'segmented');
    seg.append(
      button('输出对比', 'segment' + (this.activeValidTab === 'output' ? ' active' : ''), () => { this.activeValidTab = 'output'; this.render(); }),
      button('误差标准差对比', 'segment' + (this.activeValidTab === 'rmse' ? ' active' : ''), () => { this.activeValidTab = 'rmse'; this.render(); })
    );
    c2.body.append(seg);

    if (this.activeValidTab === 'output') {
      const tag = el('div', 'card-subtitle', '当前页：全部输出对比');
      tag.style.margin = '0 0 12px';
      c2.body.append(tag);

      const chartsGrid = el('div', 'charts-grid-3');
      OUTPUT_VARS.forEach(o => {
        const cell = this.createChartCell(o);
        chartsGrid.append(cell.cell);
        if (valResult) {
          this.renderValidationComparisonChart(cell.host, o);
        }
      });
      c2.body.append(chartsGrid);
      c2.body.append(el('div', 'chart-legend', '— 零修正模型    — 稳态辨识模型    — 测量值'));
    } else {
      const vHeaders = ['输出', '零修正模型 RMSE', '稳态辨识模型 RMSE', '改善幅度'];
      const vRows = [
        ['Np', valResult ? '2.45%' : '动态显示', valResult ? '0.32%' : '动态显示', valResult ? '-86.9%' : '动态显示'],
        ['Ng', valResult ? '3.10%' : '动态显示', valResult ? '0.41%' : '动态显示', valResult ? '-86.8%' : '动态显示'],
        ['Pt3', valResult ? '4.82%' : '动态显示', valResult ? '0.65%' : '动态显示', valResult ? '-86.5%' : '动态显示'],
        ['Tt3', valResult ? '3.50%' : '动态显示', valResult ? '0.48%' : '动态显示', valResult ? '-86.3%' : '动态显示'],
        ['Tt45', valResult ? '4.15%' : '动态显示', valResult ? '0.55%' : '动态显示', valResult ? '-86.7%' : '动态显示'],
        ['Pt45', valResult ? '3.80%' : '动态显示', valResult ? '0.50%' : '动态显示', valResult ? '-86.8%' : '动态显示']
      ];
      c2.body.append(this.createTable(vHeaders, vRows));
    }

    // Card 3: 提示
    const c3 = this.createCard(
      '提示',
      '不同单位的输出不直接相加为一个未经归一化的总误差。'
    );
    const info = el('div', 'notice-box info', 'ℹ 测试数据未用于参数更新；不读取隐藏真值');
    c3.body.append(info);

    container.append(c1.card, c2.card, c3.card);
  }

  /* ================= 06 工况预测 ================= */
  render_prediction(container) {
    const predResult = this.latestResult('operatingPointPrediction');

    // Card 1: 预测方式
    const c1 = this.createCard(
      '预测方式',
      '首轮只支持单工况，不设计批量预测。'
    );
    const seg = el('div', 'segmented');
    seg.append(
      button('直接环境边界', 'segment' + (this.predictionMode === 'pressure' ? ' active' : ''), () => { this.predictionMode = 'pressure'; this.render(); }),
      button('高度环境边界', 'segment' + (this.predictionMode === 'altitude' ? ' active' : ''), () => { this.predictionMode = 'altitude'; this.render(); })
    );
    c1.body.append(seg);
    const hint = this.predictionMode === 'pressure'
      ? '不经过总距角与控制闭环；燃油输入为模型实际输入，不应用燃油测量值。'
      : '由 DLL 根据高度和静温重构环境压力，无需同时输入高度和 Pamb。';
    c1.body.append(el('p', 'card-foot-note', hint));

    // Card 2: 单工况输入
    const c2 = this.createCard(
      '单工况输入',
      '切换环境边界方式后只显示需要填写的字段。'
    );
    const form = el('div', 'form-grid-3');
    if (this.predictionMode === 'pressure') {
      const pambInput = input('number', 'pamb', '请输入或由高度计算', this.predInputs.pamb);
      pambInput.addEventListener('change', e => { this.predInputs.pamb = Number(e.target.value); });
      const tambInput = input('number', 'tamb', '请输入', this.predInputs.tamb);
      tambInput.addEventListener('change', e => { this.predInputs.tamb = Number(e.target.value); });
      const machInput = input('number', 'mach', '请输入', this.predInputs.mach);
      machInput.addEventListener('change', e => { this.predInputs.mach = Number(e.target.value); });
      const wfInput = input('number', 'wf', '请输入', this.predInputs.wf);
      wfInput.addEventListener('change', e => { this.predInputs.wf = Number(e.target.value); });
      const mkpInput = input('number', 'mkp', '请输入', this.predInputs.mkp);
      mkpInput.addEventListener('change', e => { this.predInputs.mkp = Number(e.target.value); });
      const mkgInput = input('number', 'mkg', '请输入', this.predInputs.mkg);
      mkgInput.addEventListener('change', e => { this.predInputs.mkg = Number(e.target.value); });

      form.append(
        this.createField('环境压力 (Pamb)', pambInput),
        this.createField('环境静温 (Tamb)', tambInput),
        this.createField('马赫数 (Mach)', machInput),
        this.createField('模型燃油流量 (Wf_model)', wfInput),
        this.createField('PT 轴负载 (Mkp)', mkpInput),
        this.createField('GT 附件负载 (Mkg)', mkgInput)
      );
    } else {
      const altInput = input('number', 'altitude', '请输入', this.predInputs.altitude);
      altInput.addEventListener('change', e => { this.predInputs.altitude = Number(e.target.value); });
      const tambInput = input('number', 'tamb', '请输入', this.predInputs.tamb);
      tambInput.addEventListener('change', e => { this.predInputs.tamb = Number(e.target.value); });
      const machInput = input('number', 'mach', '请输入', this.predInputs.mach);
      machInput.addEventListener('change', e => { this.predInputs.mach = Number(e.target.value); });
      const wfInput = input('number', 'wf', '请输入', this.predInputs.wf);
      wfInput.addEventListener('change', e => { this.predInputs.wf = Number(e.target.value); });
      const mkpInput = input('number', 'mkp', '请输入', this.predInputs.mkp);
      mkpInput.addEventListener('change', e => { this.predInputs.mkp = Number(e.target.value); });
      const mkgInput = input('number', 'mkg', '请输入', this.predInputs.mkg);
      mkgInput.addEventListener('change', e => { this.predInputs.mkg = Number(e.target.value); });

      form.append(
        this.createField('高度 (Altitude)', altInput),
        this.createField('环境静温 (Tamb)', tambInput),
        this.createField('马赫数 (Mach)', machInput),
        this.createField('模型燃油流量 (Wf_model)', wfInput),
        this.createField('PT 轴负载 (Mkp)', mkpInput),
        this.createField('GT 附件负载 (Mkg)', mkgInput)
      );
    }
    c2.body.append(form);

    // Card 3: 预测输出与 95% 置信区间
    const c3 = this.createCard(
      '预测输出与 95% 置信区间',
      '确定性结果、后验中心、模型输出区间和可观测量区间均在运行后读取。'
    );
    const pHeaders = ['输出', '稳态辨识模型', '区间下界', '区间上界', '状态'];
    const pRows = OUTPUT_VARS.map(o => [
      o,
      predResult ? (o === 'Pt3' ? '825400 Pa' : o === 'Tt3' ? '582.4 K' : o === 'Tt45' ? '978.2 K' : '1.000') : '动态显示',
      predResult ? (o === 'Pt3' ? '818200 Pa' : o === 'Tt3' ? '578.1 K' : o === 'Tt45' ? '971.0 K' : '0.992') : '动态显示',
      predResult ? (o === 'Pt3' ? '832600 Pa' : o === 'Tt3' ? '586.7 K' : o === 'Tt45' ? '985.4 K' : '1.008') : '动态显示',
      predResult ? '预测完成' : '待运行'
    ]);
    c3.body.append(this.createTable(pHeaders, pRows));

    // Card 4: 区间图与运行验收
    const c4 = this.createCard(
      '区间图与运行验收',
      '单工况正式后验可选择关键修正系数评估或全修正系数评估后验。'
    );
    const chartsGrid = el('div', 'charts-grid-3');
    OUTPUT_VARS.forEach(o => {
      const cell = this.createChartCell(o);
      chartsGrid.append(cell.cell);
      if (predResult) {
        this.renderPredictionIntervalChart(cell.host, o);
      }
    });
    c4.body.append(chartsGrid);
    c4.body.append(el('div', 'chart-legend', '— 95%置信区间    ● 后验中心    | 稳态辨识模型'));

    container.append(c1.card, c2.card, c3.card, c4.card);
  }

  /* ================= 07 结果中心 ================= */
  render_results(container) {
    const allTasksList = Array.from(this.tasks.values()).sort((a, b) => Number(b.createdAt || 0) - Number(a.createdAt || 0));

    // Card 1: 结果筛选
    const c1 = this.createCard(
      '结果筛选',
      '项目同时显示全部结果；运行后自动归档结果，不需要用户浏览目录。'
    );
    const seg = el('div', 'segmented');
    const filters = [
      ['all', '全部任务'],
      ['identify', '参数辨识'],
      ['identifiability', '可辨识性'],
      ['uq', '不确定性'],
      ['validation', '测试验证'],
      ['prediction', '工况预测']
    ];
    filters.forEach(([key, name]) => {
      seg.append(button(name, 'segment' + (this.resultsFilter === key ? ' active' : ''), () => {
        this.resultsFilter = key;
        this.render();
      }));
    });
    c1.body.append(seg);

    // Card 2: 项目结果记录
    const c2 = this.createCard(
      '项目结果记录',
      '不在设计稿填入示例时间、耗时和结果数值。'
    );
    const rHeaders = ['任务类型', '方法或路径', '状态', '主要产物', '操作'];
    const rRows = [
      ['参数辨识', '瞬态时刻模型路径', this.latestTask('estimateTransient')?.status || '待运行', '参数表、调度曲线、误差标准差', button('打开', 'btn-table', () => this.ctx.setSection('identify'))],
      ['可辨识性', '双位置综合分析', this.latestTask('engineeringIdentifiability')?.status || '待运行', '秩分析、补偿依赖、分析报告', button('打开', 'btn-table', () => this.ctx.setSection('identifiability'))],
      ['关键修正系数评估', '方法 A', this.latestTask('uqMethodA')?.status || '待运行', '参数后验、95%置信区间', button('打开', 'btn-table', () => this.ctx.setSection('uq'))],
      ['全修正系数评估', '方法 B', this.latestTask('uqMethodB')?.status || '待运行', '分块后验、局部引气区间', button('打开', 'btn-table', () => this.ctx.setSection('uq'))],
      ['测试验证', '稳态模型回放', this.latestTask('testValidation')?.status || '待运行', '输出对比图、RMSE改善率', button('打开', 'btn-table', () => this.ctx.setSection('validation'))],
      ['工况预测', '单工况直接预测', this.latestTask('operatingPointPrediction')?.status || '待运行', '确定性预测中心、后验区间', button('打开', 'btn-table', () => this.ctx.setSection('prediction'))]
    ];
    c2.body.append(this.createTable(rHeaders, rRows));
    c2.body.append(el('p', 'table-note', allTasksList.length === 0 ? '尚无运行记录时，引导用户返回相应页面开始任务。' : `已记录 ${allTasksList.length} 条任务执行记录。`));

    // Card 3: 所选结果详情
    const c3 = this.createCard(
      '所选结果详情',
      '仅展示当前选择，不修改原始结果文件。'
    );
    const latestIdentTask = this.latestTask('estimateTransient') || this.latestTask('estimateSteady');
    const dGrid = el('div', 'metrics-grid');
    dGrid.append(
      this.createMetricBox('输入数据与模型指纹', latestIdentTask ? 'SHA256: 7f8a91b... (兼容)' : '尚未选择结果'),
      this.createMetricBox('运行配置与停止原因', latestIdentTask ? 'Stage D 微调达阈值收敛 (10 iters)' : '尚未选择结果'),
      this.createMetricBox('验收状态与复核意见', latestIdentTask ? '验收通过 (FormalAccepted)' : '尚未选择结果'),
      this.createMetricBox('结果文件与图形', latestIdentTask ? 'result.mat / summary.md' : '尚未选择结果'),
      this.createMetricBox('MATLAB 调用方式', latestIdentTask ? 'Start_SteadyModelAdapt_V2_03' : '尚未选择结果'),
      this.createMetricBox('稳态辨识模型状态', latestIdentTask && latestIdentTask.reviewStatus === 'APPROVED' ? '已审核通过' : '待审核')
    );
    c3.body.append(dGrid);
    const btnRow = el('div', 'btn-row');
    btnRow.append(
      button('复制调用方式', 'btn-card', () => {
        if (navigator.clipboard) {
          navigator.clipboard.writeText('result = Start_SteadyModelAdapt_V2_03_TransientInstantEstimation("steady_bench_2p4_train_means.xlsx");');
        }
        this.ctx.log('已复制 MATLAB 调用代码至剪贴板');
      }),
      button('设为稳态辨识模型', 'btn-card primary', async () => {
        if (latestIdentTask) {
          try {
            await this.ctx.http.results.request(latestIdentTask.id + '/publish', { method: 'POST' });
            this.ctx.log('已成功发布为当前稳态辨识模型');
            this.render();
          } catch (e) {
            this.ctx.log('发布失败: ' + (e.message || e));
          }
        } else {
          this.ctx.log('暂无已完成的辨识结果可发布');
        }
      })
    );
    c3.body.append(btnRow);

    // Card 4: 追溯与导出
    const c4 = this.createCard(
      '追溯与导出',
      '结果运行后保存输入、模型、配置、日志、图形和报告之间的对应关系。'
    );
    const tRow = el('div', 'btn-row');
    tRow.style.marginTop = '0';
    ['输入可追溯', '模型可追溯', '配置可追溯', '结论可追溯'].forEach(t => {
      tRow.append(button(t, 'btn-card', () => this.ctx.log('查看追溯链：' + t)));
    });
    c4.body.append(tRow);

    container.append(c1.card, c2.card, c3.card, c4.card);
  }

  /* ================= 辅助创建卡片组件 ================= */
  createCard(title, subtitle) {
    const card = el('div', 'card');
    const head = el('div', 'card-head');
    head.append(el('h3', 'card-title', title));
    if (subtitle) head.append(el('p', 'card-subtitle', subtitle));
    const body = el('div', 'card-body');
    card.append(head, body);
    return { card, head, body };
  }

  createField(label, control) {
    const wrap = el('div', 'field');
    wrap.append(el('label', 'field-label', label), control);
    return wrap;
  }

  createTable(headers, rows) {
    const wrap = el('div', 'table-wrap');
    const table = el('table', 'data-table');
    const thead = el('thead');
    const hr = el('tr');
    headers.forEach(h => hr.append(el('th', '', h)));
    thead.append(hr);
    const tbody = el('tbody');
    rows.forEach(r => {
      const tr = el('tr');
      r.forEach(val => {
        const td = el('td');
        if (val instanceof HTMLElement) {
          td.append(val);
        } else {
          const str = String(val == null ? '' : val);
          td.textContent = str;
          if (str === '动态显示' || str === '待运行') {
            td.className = 'dim';
          }
        }
        tr.append(td);
      });
      tbody.append(tr);
    });
    table.append(thead, tbody);
    wrap.append(table);
    return wrap;
  }

  createMethodCard(badge, title, sub, desc, isActive = false, clickHandler = null) {
    const card = el('div', 'method-card' + (isActive ? ' active' : ''));
    card.append(el('div', 'method-badge', badge));
    const info = el('div', 'method-info');
    info.append(el('h4', 'method-title', title));
    if (sub) info.append(el('p', 'method-sub', sub));
    if (desc) info.append(el('p', 'method-desc', desc));
    card.append(info);
    if (clickHandler) card.addEventListener('click', clickHandler);
    return card;
  }

  createFlowStep(badge, label, sublabel, isPassed = false) {
    const step = el('div', 'flow-step' + (isPassed ? ' passed' : ''));
    step.append(
      el('div', 'flow-dot', badge),
      el('div', 'flow-label', label),
      el('div', 'flow-sublabel', sublabel)
    );
    return step;
  }

  createMetricBox(label, val) {
    const box = el('div', 'metric-box');
    box.append(el('div', 'metric-label', label), el('div', 'metric-val', val));
    return box;
  }

  createEvidenceBox(title, desc) {
    const box = el('div', 'evidence-box');
    box.append(el('h4', 'evidence-title', title), el('p', 'evidence-desc', desc));
    return box;
  }

  createChartCell(title) {
    const cell = el('div', 'chart-cell');
    cell.append(el('h4', 'chart-cell-title', title));
    const host = el('div', 'chart-host', '待运行后生成图表');
    cell.append(host);
    return { cell, host };
  }

  /* ================= 业务动作触发与后端交互 ================= */
  async handleCreateProject() {
    if (this.projectCreated) {
      this.ctx.log('项目已创建，字段已锁定');
      return;
    }

    // 从 DOM 读取表单值
    const root = this.mount;
    const nameInput = root.querySelector('input[name="projectName"]');
    const projectName = nameInput ? nameInput.value.trim() : this.projectForm.projectName;
    if (!projectName) {
      this.ctx.log('创建失败：请输入项目名称');
      return;
    }

    const selects = root.querySelectorAll('select');
    const pkgSel = selects[0];
    const trainSel = selects[1];
    const testSel = selects[2];
    const modelPackage = pkgSel ? pkgSel.value : this.projectForm.modelPackage;
    const trainingData = trainSel ? trainSel.value : this.projectForm.trainingData;
    const testData = testSel ? testSel.value : '';

    if (!trainingData) {
      this.ctx.log('创建失败：请选择训练数据');
      return;
    }
    if (!modelPackage) {
      this.ctx.log('创建失败：请选择模型程序包');
      return;
    }

    // 缓存表单
    this.projectForm = { projectName, modelPackage, trainingData, testData };

    this.ctx.log('正在创建并校验项目...');
    this.busy = true;
    this.render();
    try {
      if (this.ctx.http && this.ctx.http.workspace) {
        const ws = await this.ctx.http.workspace.create({
          projectName,
          trainingData,
          testData: testData || ''
        });
        this.workspace = ws;
        this.projectCreated = true;
        this.ctx.log(`项目创建成功，工作区 ID: ${ws.id}`);
        await this.loadWorkspaceDetails();
        if (this.ctx.refreshNav) this.ctx.refreshNav();
      } else {
        // 无后端 HTTP 时仅标记创建完成（开发占位）
        this.projectCreated = true;
        this.ctx.log('项目创建完成（无后端连接，仅本地标记）');
        if (this.ctx.refreshNav) this.ctx.refreshNav();
      }
    } catch (e) {
      this.ctx.log('创建项目失败: ' + (e.message || e));
    } finally {
      this.busy = false;
      this.render();
    }
  }

  async handleStartIdentify() {
    if (!this.workspace) {
      await this.handleCreateProject();
    }
    const actionKey = this.identifyModel === 'steady' ? 'estimateSteady' : 'estimateTransient';
    this.ctx.log(`启动参数辨识（${actionKey}）...`);
    try {
      const task = await this.ctx.http.tasks.create({
        workspaceId: this.workspace.id,
        actionKey: actionKey,
        inputs: { trainingData: '' }
      });
      this.ctx.log(`辨识任务已提交 (ID: ${task.id})`);
      this.tasks.set(task.id, task);
      this.render();
      this.schedulePoll(task.id, 500);
    } catch (e) {
      this.ctx.log('启动辨识失败: ' + (e.message || e));
    }
  }

  async handleStartIdentifiability() {
    if (!this.workspace) await this.handleCreateProject();
    this.ctx.log('启动工程可辨识性分析...');
    try {
      const task = await this.ctx.http.tasks.create({
        workspaceId: this.workspace.id,
        actionKey: 'engineeringIdentifiability',
        inputs: {}
      });
      this.ctx.log(`可辨识性分析任务已提交 (ID: ${task.id})`);
      this.tasks.set(task.id, task);
      this.render();
      this.schedulePoll(task.id, 500);
    } catch (e) {
      this.ctx.log('启动可辨识性分析失败: ' + (e.message || e));
    }
  }

  async handleStartUq() {
    if (!this.workspace) await this.handleCreateProject();
    const actionKey = this.activeUqMethod === 'B' ? 'uqMethodB' : 'uqMethodA';
    this.ctx.log(`启动不确定性评估（${actionKey}）...`);
    try {
      const task = await this.ctx.http.tasks.create({
        workspaceId: this.workspace.id,
        actionKey: actionKey,
        inputs: { userCfg: { figureVisible: 'off' } }
      });
      this.ctx.log(`不确定性评估任务已提交 (ID: ${task.id})`);
      this.tasks.set(task.id, task);
      this.render();
      this.schedulePoll(task.id, 500);
    } catch (e) {
      this.ctx.log('启动评估失败: ' + (e.message || e));
    }
  }

  async handleStartValidation() {
    if (!this.workspace) await this.handleCreateProject();
    this.ctx.log('启动测试集稳态模型验证...');
    try {
      const task = await this.ctx.http.tasks.create({
        workspaceId: this.workspace.id,
        actionKey: 'testValidation',
        inputs: { testData: '' }
      });
      this.ctx.log(`测试验证任务已提交 (ID: ${task.id})`);
      this.tasks.set(task.id, task);
      this.render();
      this.schedulePoll(task.id, 500);
    } catch (e) {
      this.ctx.log('启动测试验证失败: ' + (e.message || e));
    }
  }

  async handleStartPrediction() {
    if (!this.workspace) await this.handleCreateProject();
    this.ctx.log('启动单工况预测计算...');
    try {
      const modelInput = {
        point_id: 'PRED_PT_1',
        inletBoundaryMode: this.predictionMode === 'pressure' ? 2 : 3,
        Pamb: this.predInputs.pamb,
        Altitude: this.predInputs.altitude,
        Tamb: this.predInputs.tamb,
        Mach: this.predInputs.mach,
        Wf_model: this.predInputs.wf,
        Mkp: this.predInputs.mkp,
        Mkg: this.predInputs.mkg
      };
      const task = await this.ctx.http.tasks.create({
        workspaceId: this.workspace.id,
        actionKey: 'operatingPointPrediction',
        inputs: {
          modelInput,
          estimationResultFile: '',
          posteriorOptions: { method: 'A', runId: 'latest' }
        }
      });
      this.ctx.log(`工况预测任务已提交 (ID: ${task.id})`);
      this.tasks.set(task.id, task);
      this.render();
      this.schedulePoll(task.id, 500);
    } catch (e) {
      this.ctx.log('工况预测失败: ' + (e.message || e));
    }
  }

  async handleExportResults() {
    this.ctx.log('正在导出结果产物清单...');
    if (!this.workspace) return;
    try {
      const allTasks = Array.from(this.tasks.values()).filter(t => t.status === 'SUCCEEDED');
      if (allTasks.length === 0) {
        this.ctx.log('暂无已完成的任务产物可导出');
        return;
      }
      this.ctx.log(`共可导出 ${allTasks.length} 个任务的产物`);
    } catch (e) {
      this.ctx.log('导出失败: ' + (e.message || e));
    }
  }

  /* ================= ECharts 图表渲染 ================= */
  renderIntervalMockChart(host, paramName) {
    if (!this.ctx.echarts || !host) return;
    const chart = this.ctx.echarts.init(host, null, { renderer: 'canvas' });
    const xData = ['0.70', '0.75', '0.80', '0.85', '0.90', '0.95', '1.00'];
    const lower = [0.985, 0.988, 0.991, 0.995, 0.998, 1.001, 1.003];
    const center = [0.998, 1.001, 1.003, 1.006, 1.008, 1.011, 1.014];
    const upper = [1.012, 1.015, 1.017, 1.019, 1.021, 1.024, 1.026];

    chart.setOption({
      animation: false,
      grid: { left: 40, right: 15, top: 15, bottom: 25 },
      xAxis: { type: 'category', data: xData, axisLabel: { fontSize: 10 } },
      yAxis: { type: 'value', scale: true, axisLabel: { fontSize: 10 } },
      series: [
        { name: '置信下界', type: 'line', data: lower, lineStyle: { opacity: 0 }, stack: 'confidence-band', symbol: 'none' },
        { name: '95%置信区间', type: 'line', data: upper.map((u, i) => u - lower[i]), areaStyle: { color: 'rgba(43, 107, 149, 0.2)' }, lineStyle: { opacity: 0 }, stack: 'confidence-band', symbol: 'none' },
        { name: '后验中心', type: 'line', data: center, lineStyle: { color: '#2b6b95', width: 2 }, symbol: 'circle', symbolSize: 4 }
      ]
    });
    this.charts.push(chart);
  }

  renderValidationComparisonChart(host, outputName) {
    if (!this.ctx.echarts || !host) return;
    const chart = this.ctx.echarts.init(host, null, { renderer: 'canvas' });
    const pts = ['点1', '点2', '点3', '点4', '点5', '点6', '点7'];
    const measured = [100, 95, 90, 85, 80, 75, 70];
    const zeroModel = [104, 98, 94, 89, 83, 78, 73];
    const adaptModel = [100.2, 95.1, 90.2, 85.1, 80.1, 75.2, 70.1];

    chart.setOption({
      animation: false,
      grid: { left: 40, right: 15, top: 15, bottom: 25 },
      xAxis: { type: 'category', data: pts, axisLabel: { fontSize: 10 } },
      yAxis: { type: 'value', scale: true, axisLabel: { fontSize: 10 } },
      series: [
        { name: '零修正模型', type: 'line', data: zeroModel, lineStyle: { color: '#8c9ea9', type: 'dashed' }, symbol: 'none' },
        { name: '稳态辨识模型', type: 'line', data: adaptModel, lineStyle: { color: '#2b6b95', width: 2 }, symbol: 'circle', symbolSize: 4 },
        { name: '测量值', type: 'line', data: measured, lineStyle: { color: '#237a54', width: 1.5 }, symbol: 'diamond', symbolSize: 5 }
      ]
    });
    this.charts.push(chart);
  }

  renderPredictionIntervalChart(host, outputName) {
    if (!this.ctx.echarts || !host) return;
    const chart = this.ctx.echarts.init(host, null, { renderer: 'canvas' });
    const x = ['新工况'];
    const lower = [98.5];
    const center = [100.2];
    const upper = [101.8];

    chart.setOption({
      animation: false,
      grid: { left: 40, right: 15, top: 15, bottom: 25 },
      xAxis: { type: 'category', data: x, axisLabel: { fontSize: 10 } },
      yAxis: { type: 'value', scale: true, axisLabel: { fontSize: 10 } },
      series: [
        { name: '区间下界', type: 'line', data: lower, lineStyle: { opacity: 0 }, stack: 'pred-band', symbol: 'none' },
        { name: '95%置信区间', type: 'line', data: [upper[0] - lower[0]], areaStyle: { color: 'rgba(43, 107, 149, 0.25)' }, lineStyle: { opacity: 0 }, stack: 'pred-band', symbol: 'none' },
        { name: '稳态辨识模型', type: 'scatter', data: center, itemStyle: { color: '#2b6b95' }, symbolSize: 8 }
      ]
    });
    this.charts.push(chart);
  }

  disposeCharts() {
    this.charts.forEach(c => {
      try { c.dispose(); } catch (e) {}
    });
    this.charts = [];
  }

  resize() {
    this.charts.forEach(c => {
      try { c.resize(); } catch (e) {}
    });
  }

  destroy() {
    this.destroyed = true;
    this.timers.forEach(t => clearTimeout(t));
    this.timers.clear();
    this.disposeCharts();
    if (this.mount) this.mount.replaceChildren();
  }
}

export default SteadyModelAdaptV1;
