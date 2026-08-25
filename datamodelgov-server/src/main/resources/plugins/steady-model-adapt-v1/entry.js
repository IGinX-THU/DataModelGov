const MEASURE_HEADERS = [
  '工况', 'Np', 'Ng', 'Wf', 'Mkp', 'Mkg', 'Tt1', 'Pt2', 'Pt3', 'Tt3', 'Tt45', 'Pt45', 'Pamb', 'Tamb', '高度', 'Mach'
];

const GROUP_HEADERS = [
  '工况', '数据角色', '训练分组', 'AC相对换算转速', '进气道换算流量', '燃烧室进口换算流量',
  'GT物理压比', 'GT-PT涵道换算流量', 'PT物理压比', 'PT-尾喷管涵道换算流量', '测量燃油流量归一化坐标'
];

const IDENTIFY_PARAMS = [
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
    this.tasks = new Map();
    this.identifyModel = 'transient';
    this.identifyTaskType = 'default';
    this.activeSnapshot = 'pre';
    this.activeUqMethod = 'A';
    this.activeUqTab = 'overall';
    this.activeValidTab = 'output';
    this.predictionMode = 'pressure';
    this.resultsFilter = 'all';
    this.charts = [];
    this.timers = new Set();
    this.destroyed = false;
  }

  async init() {
    this.render();
    await this.loadInitialData();
  }

  async setSection(sectionId) {
    this.activeSection = sectionId;
    this.render();
  }

  onHeaderAction(label, sectionId) {
    this.ctx.log(`触发操作：${label}（${sectionId}）`);
    if (label === '创建并校验项目') {
      this.handleCreateProject();
    } else if (label === '开始辨识') {
      this.handleStartIdentify();
    } else if (label === '开始评估') {
      this.handleStartUq();
    } else if (label === '开始验证') {
      this.handleStartValidation();
    } else if (label === '运行预测') {
      this.handleStartPrediction();
    } else if (label === '导出所选结果') {
      this.handleExportResults();
    }
  }

  async loadInitialData() {
    try {
      if (this.ctx.http && this.ctx.http.workspace) {
        const list = await this.ctx.http.workspace.list();
        if (Array.isArray(list)) this.workspaces = list;
        if (this.workspaces.length > 0 && !this.workspace) {
          this.workspace = this.workspaces[0];
        }
      }
    } catch (e) {
      console.warn('读取工作区失败:', e);
    }
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
    // Card 1: 项目建立与数据合同
    const c1 = this.createCard(
      '项目建立与数据合同',
      '项目创建完成前，后续功能保持锁定；测试数据可选且不参与参数辨识。'
    );
    const form = el('div', 'form-grid-4');
    form.append(
      this.createField('项目名称', input('text', 'projectName', '请输入项目名称', (this.workspace && this.workspace.projectName) || '示例项目_2026')),
      this.createField('模型程序包', select(['稳态试车工况点模型修正V1', '选择交付程序目录'])),
      this.createField('训练数据', select(['steady_bench_2p4_train_means.xlsx', '选择训练试车数据'])),
      this.createField('测试数据', select(['steady_bench_2p4_test_means.xlsx', '选择测试数据（可选）']))
    );
    c1.body.append(form);
    c1.body.append(el('p', 'card-foot-note', '训练数据用于辨识，测试数据仅用于独立验证。'));

    // Card 2: 测量数据表
    const c2 = this.createCard(
      '测量数据表',
      '每行对应一个稳态工况窗口；全部测量字段保存在同一张表中，固定工况编号并支持横向滚动。'
    );
    const mRows = [
      ['工况A', '动态显示', '动态显示', '动态显示', '动态显示', '动态显示', '动态显示', '动态显示', '动态显示', '动态显示', '动态显示', '动态显示', '动态显示', '动态显示', '动态显示', '动态显示'],
      ['工况B', '动态显示', '动态显示', '动态显示', '动态显示', '动态显示', '动态显示', '动态显示', '动态显示', '动态显示', '动态显示', '动态显示', '动态显示', '动态显示', '动态显示', '动态显示'],
      ['工况C', '动态显示', '动态显示', '动态显示', '动态显示', '动态显示', '动态显示', '动态显示', '动态显示', '动态显示', '动态显示', '动态显示', '动态显示', '动态显示', '动态显示', '动态显示']
    ];
    c2.body.append(this.createTable(MEASURE_HEADERS, mRows));
    c2.body.append(el('p', 'table-note', '单位、缺失值、越界标记和原始字段名在列标题提示中展示；表内数值由导入文件动态读取。'));

    // Card 3: AC相对换算转速、调度变量与训练分组
    const c3 = this.createCard(
      'AC相对换算转速、调度变量与训练分组',
      '同一表显示各工况辅助变量；按AC相对换算转速聚类后写入训练分组列。'
    );
    const gRows = [
      ['工况A', '训练', '组甲', '动态显示', '动态显示', '动态显示', '动态显示', '动态显示', '动态显示', '动态显示', '动态显示'],
      ['工况B', '训练', '组甲', '动态显示', '动态显示', '动态显示', '动态显示', '动态显示', '动态显示', '动态显示', '动态显示'],
      ['工况C', '训练', '组乙', '动态显示', '动态显示', '动态显示', '动态显示', '动态显示', '动态显示', '动态显示', '动态显示']
    ];
    c3.body.append(this.createTable(GROUP_HEADERS, gRows));
    c3.body.append(el('p', 'table-note', '同一训练组采用一致的组号和颜色标识。分组结果可查看但不允许直接手工改写。'));

    container.append(c1.card, c2.card, c3.card);
  }

  /* ================= 02 参数辨识 ================= */
  render_identify(container) {
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
      this.createFlowStep('A', 'A 全工况常值初估', '建立公共初值'),
      this.createFlowStep('B', 'B 分组组内估计', '按训练分组辨识'),
      this.createFlowStep('C', 'C 调度重构', '组间拟合与常值平均'),
      this.createFlowStep('D', 'D 全工况微调', '联合数据最终修正')
    );
    c2.body.append(flow);

    // Card 3: 修正系数辨识结果
    const c3 = this.createCard(
      '修正系数辨识结果',
      '表内同时显示设计点值和节点均值；曲线按钮打开该参数完整调度曲线。'
    );
    const paramHeaders = ['修正系数', '形式', '设计点值', '节点均值', '单位', '查看'];
    const paramRows = IDENTIFY_PARAMS.map(p => [
      p.name,
      p.form,
      '动态显示',
      '动态显示',
      p.unit,
      button(p.action, 'btn-table', () => this.ctx.log('查看：' + p.name))
    ]);
    c3.body.append(this.createTable(paramHeaders, paramRows));

    // Card 4: 输出误差标准差与计算时间
    const c4 = this.createCard(
      '输出误差标准差与计算时间',
      '修正前后误差直接对照；曲线按钮查看逐工况误差。'
    );
    const errHeaders = ['输出', '修正前标准差', '修正后标准差', '查看'];
    const errRows = OUTPUT_VARS.map(o => [
      o,
      '动态显示',
      '动态显示',
      button('曲线', 'btn-table', () => this.ctx.log('查看误差曲线：' + o))
    ]);
    c4.body.append(this.createTable(errHeaders, errRows));
    const timeBox = el('div', 'metrics-grid');
    timeBox.style.marginTop = '14px';
    timeBox.append(this.createMetricBox('总计算时间', '运行完成后显示总耗时及 A/B/C/D 分阶段耗时'));
    c4.body.append(timeBox);

    container.append(c1.card, c2.card, c3.card, c4.card);
  }

  /* ================= 03 可辨识性 ================= */
  render_identifiability(container) {
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
      this.createMetricBox('标准化信息矩阵条件数', '动态显示'),
      this.createMetricBox('当前正则化后条件数', '动态显示'),
      this.createMetricBox('数值秩 / 有效秩', '动态显示'),
      this.createMetricBox('最小有效奇异值', '动态显示'),
      this.createMetricBox('双快照变化', '运行后归纳')
    );
    c2.body.append(qGrid);

    // Card 3: 逐参数分类与主要补偿参数
    const c3 = this.createCard(
      '逐参数分类与主要补偿参数',
      '依赖补偿参数必须列出贡献最大的补偿对象，而不只给出“依赖补偿”标签。'
    );
    const idHeaders = ['参数', '自身敏感性', '补偿依赖', '主要补偿参数', 'A 前类别', 'D 后类别', '证据与建议'];
    const idRows = IDENTIFY_PARAMS.map(p => [
      p.name,
      '动态显示',
      '动态显示',
      '按贡献排序显示',
      '动态显示',
      '动态显示',
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
      this.createEvidenceBox('自身敏感性证据', '孤立工程扰动、主导输出及响应量级动态显示'),
      this.createEvidenceBox('补偿关系证据', '主要补偿参数、变化方向、步长占比和补偿后残差动态显示'),
      this.createEvidenceBox('工程处置建议', '保留、加强先验、固定参数或增加工况激励的建议动态显示')
    );
    c4.body.append(eGrid);

    container.append(c1.card, c2.card, c3.card, c4.card);
  }

  /* ================= 04 不确定性评估 ================= */
  render_uq(container) {
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
      this.createMetricBox('关键修正系数评估', '预计耗时：待估算'),
      this.createMetricBox('全修正系数评估', '预计耗时：待估算')
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
    IDENTIFY_PARAMS.forEach(p => {
      chartsGrid.append(this.createChartCell(p.name));
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
    progressTrack.append(el('div', 'progress-fill'));
    c4.body.append(progressTrack);
    c4.body.append(el('p', 'card-subtitle', '等待开始 / 运行后显示当前步骤'));

    const pGrid = el('div', 'metrics-grid');
    pGrid.style.marginTop = '12px';
    pGrid.append(
      this.createMetricBox('已用时间', '运行后显示'),
      this.createMetricBox('预计剩余', '运行后显示'),
      this.createMetricBox('总运行时间', '完成后显示')
    );
    c4.body.append(pGrid);
    const btnRow = el('div', 'btn-row');
    btnRow.append(button('查看运行日志与验收明细', 'btn-card', () => this.ctx.log('查看运行日志')));
    c4.body.append(btnRow);

    container.append(c1.card, c2.card, c3.card, c4.card);
  }

  /* ================= 05 测试验证 ================= */
  render_validation(container) {
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
      OUTPUT_VARS.forEach(o => chartsGrid.append(this.createChartCell(o)));
      c2.body.append(chartsGrid);
      c2.body.append(el('div', 'chart-legend', '— 零修正模型    — 稳态辨识模型    — 测量值'));
    } else {
      const vHeaders = ['输出', '零修正模型 RMSE', '稳态辨识模型 RMSE', '改善幅度'];
      const vRows = OUTPUT_VARS.map(o => [o, '动态显示', '动态显示', '动态显示']);
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
      form.append(
        this.createField('环境压力 (Pamb)', input('number', 'pamb', '请输入或由高度计算')),
        this.createField('环境静温 (Tamb)', input('number', 'tamb', '请输入')),
        this.createField('马赫数 (Mach)', input('number', 'mach', '请输入')),
        this.createField('模型燃油流量 (Wf_model)', input('number', 'wf', '请输入')),
        this.createField('PT 轴负载 (Mkp)', input('number', 'mkp', '请输入')),
        this.createField('GT 附件负载 (Mkg)', input('number', 'mkg', '请输入'))
      );
    } else {
      form.append(
        this.createField('高度 (Altitude)', input('number', 'altitude', '请输入')),
        this.createField('环境静温 (Tamb)', input('number', 'tamb', '请输入')),
        this.createField('马赫数 (Mach)', input('number', 'mach', '请输入')),
        this.createField('模型燃油流量 (Wf_model)', input('number', 'wf', '请输入')),
        this.createField('PT 轴负载 (Mkp)', input('number', 'mkp', '请输入')),
        this.createField('GT 附件负载 (Mkg)', input('number', 'mkg', '请输入'))
      );
    }
    c2.body.append(form);

    // Card 3: 预测输出与 95% 置信区间
    const c3 = this.createCard(
      '预测输出与 95% 置信区间',
      '确定性结果、后验中心、模型输出区间和可观测量区间均在运行后读取。'
    );
    const pHeaders = ['输出', '稳态辨识模型', '区间下界', '区间上界', '状态'];
    const pRows = OUTPUT_VARS.map(o => [o, '动态显示', '动态显示', '动态显示', '待运行']);
    c3.body.append(this.createTable(pHeaders, pRows));

    // Card 4: 区间图与运行验收
    const c4 = this.createCard(
      '区间图与运行验收',
      '单工况正式后验可选择关键修正系数评估或全修正系数评估后验。'
    );
    const chartsGrid = el('div', 'charts-grid-3');
    OUTPUT_VARS.forEach(o => chartsGrid.append(this.createChartCell(o)));
    c4.body.append(chartsGrid);
    c4.body.append(el('div', 'chart-legend', '— 95%置信区间    ● 后验中心    | 稳态辨识模型'));

    container.append(c1.card, c2.card, c3.card, c4.card);
  }

  /* ================= 07 结果中心 ================= */
  render_results(container) {
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
      ['参数辨识', '用户运行后记录', '待运行', '参数、调度曲线、误差', button('打开', 'btn-table', () => this.ctx.setSection('identify'))],
      ['可辨识性', '用户运行后记录', '待运行', '分类、补偿方向、报告', button('打开', 'btn-table', () => this.ctx.setSection('identifiability'))],
      ['关键修正系数评估', '用户运行后记录', '待运行', '后验、可信区间、预测', button('打开', 'btn-table', () => this.ctx.setSection('uq'))],
      ['全修正系数评估', '用户运行后记录', '待运行', '分块后验、可信区间、预测', button('打开', 'btn-table', () => this.ctx.setSection('uq'))],
      ['测试验证', '稳态模型', '待运行', '输出对比、误差标准差', button('打开', 'btn-table', () => this.ctx.setSection('validation'))],
      ['工况预测', '单工况', '待运行', '预测中心、可信区间', button('打开', 'btn-table', () => this.ctx.setSection('prediction'))]
    ];
    c2.body.append(this.createTable(rHeaders, rRows));
    c2.body.append(el('p', 'table-note', '尚无运行记录时，引导用户返回相应页面开始任务。'));

    // Card 3: 所选结果详情
    const c3 = this.createCard(
      '所选结果详情',
      '仅展示当前选择，不修改原始结果文件。'
    );
    const dGrid = el('div', 'metrics-grid');
    dGrid.append(
      this.createMetricBox('输入数据与模型指纹', '尚未选择结果'),
      this.createMetricBox('运行配置与停止原因', '尚未选择结果'),
      this.createMetricBox('验收状态与复核意见', '尚未选择结果'),
      this.createMetricBox('结果文件与图形', '尚未选择结果'),
      this.createMetricBox('MATLAB 调用方式', '尚未选择结果'),
      this.createMetricBox('稳态辨识模型状态', '尚未选择结果')
    );
    c3.body.append(dGrid);
    const btnRow = el('div', 'btn-row');
    btnRow.append(
      button('复制调用方式', 'btn-card', () => this.ctx.log('已复制调用方式')),
      button('设为稳态辨识模型', 'btn-card primary', () => this.ctx.log('已设为稳态辨识模型'))
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
      tRow.append(button(t, 'btn-card', () => this.ctx.log('追溯：' + t)));
    });
    c4.body.append(tRow);

    container.append(c1.card, c2.card, c3.card, c4.card);
  }

  /* ================= 通用辅助渲染 ================= */
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
          td.textContent = String(val == null ? '' : val);
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

  createFlowStep(badge, label, sublabel) {
    const step = el('div', 'flow-step');
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
    return cell;
  }

  /* ================= 业务动作处理 ================= */
  async handleCreateProject() {
    this.ctx.log('正在创建并校验项目...');
    try {
      if (this.ctx.http && this.ctx.http.workspace) {
        const ws = await this.ctx.http.workspace.create({});
        this.workspace = ws;
        this.ctx.log(`项目 ${ws.id} 创建成功并已校验`);
        this.render();
      }
    } catch (e) {
      this.ctx.log('创建项目失败: ' + (e.message || e));
    }
  }

  async handleStartIdentify() {
    this.ctx.log('正在启动参数辨识 A/B/C/D 流程...');
    try {
      if (!this.workspace) {
        this.ctx.log('请先创建项目');
        return;
      }
      const actionKey = this.identifyModel === 'steady' ? 'estimateSteady' : 'estimateTransient';
      const task = await this.ctx.http.tasks.create({
        workspaceId: this.workspace.id,
        actionKey: actionKey,
        inputs: {}
      });
      this.ctx.log(`辨识任务 ${task.id} 已提交`);
    } catch (e) {
      this.ctx.log('启动辨识失败: ' + (e.message || e));
    }
  }

  async handleStartUq() {
    this.ctx.log(`正在启动不确定性评估（方法 ${this.activeUqMethod}）...`);
  }

  async handleStartValidation() {
    this.ctx.log('正在启动测试集稳态验证...');
  }

  async handleStartPrediction() {
    this.ctx.log('正在执行单工况预测...');
  }

  async handleExportResults() {
    this.ctx.log('正在导出所选结果...');
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
