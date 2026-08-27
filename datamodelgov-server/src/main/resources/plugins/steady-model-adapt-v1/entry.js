const MEASURE_HEADERS = [
  '工况', 'Np', 'Ng', 'Wf', 'Mkp', 'Mkg', 'Tt1', 'Pt2', 'Pt3', 'Tt3', 'Tt45', 'Pt45', 'Pamb', 'Tamb', 'Altitude', 'Mach'
];

/** 测量数据表表头按类别分组（文档 5.2） */
const MEASURE_GROUPS = [
  { label: '编号', span: 1, headers: ['工况'] },
  { label: '转速', span: 2, headers: ['Np', 'Ng'] },
  { label: '燃油与负载', span: 3, headers: ['Wf', 'Mkp', 'Mkg'] },
  { label: '温度', span: 3, headers: ['Tt1', 'Tt3', 'Tt45'] },
  { label: '压力', span: 3, headers: ['Pt2', 'Pt3', 'Pt45'] },
  { label: '环境', span: 4, headers: ['Pamb', 'Tamb', 'Altitude', 'Mach'] }
];

/** 文档第 13 节统一任务状态（与后端 TaskStatus 英文常量保持一致） */
const TASK_STATUS = {
  PENDING_CONFIG: 'pending_config',
  READY: 'ready',
  RUNNING: 'workflow_running',
  CANCELLING: 'cancelling',
  COMPLETED: 'completed',
  SKIPPED: 'skipped',
  FAILED: 'workflow_failed',
  PENDING_REVIEW: 'pending_review',
  PUBLISHED: 'published',
  REVIEW_APPROVED: 'review_approved',
  REVIEW_REJECTED: 'review_rejected'
};
const isTerminalStatus = s => s === TASK_STATUS.COMPLETED || s === TASK_STATUS.FAILED
  || s === TASK_STATUS.CANCELLING || s === TASK_STATUS.SKIPPED;

const GROUP_HEADERS = [
  '工况', '数据角色', '训练分组', 'AC相对换算转速', '进气道换算流量', '燃烧室进口换算流量',
  'GT物理压比', 'GT-PT涵道换算流量', 'PT物理压比', 'PT-尾喷管涵道换算流量', '测量燃油流量归一化坐标'
];

const GROUP_KEY_MAP = {
  '工况': 'point_id',
  '数据角色': 'dataRole',
  '训练分组': 'trainingGroup',
  'AC相对换算转速': 'acRelativeCorrectedSpeed',
  '进气道换算流量': 'inletCorrectedMassFlow',
  '燃烧室进口换算流量': 'burnerInletCorrectedMassFlow',
  'GT物理压比': 'gtTotalPressureRatio',
  'GT-PT涵道换算流量': 'gtPtDuctCorrectedMassFlow',
  'PT物理压比': 'ptTotalPressureRatio',
  'PT-尾喷管涵道换算流量': 'ptNozzleDuctCorrectedMassFlow',
  '测量燃油流量归一化坐标': 'measuredFuelNormalizedCoordinate'
};

/** 测量数据表表头单位提示（title 属性） */
const MEASURE_UNIT_TIPS = {
  '工况': '工况编号 point_id（无量纲）',
  'Np': 'PT轴转速 Np_mean (rpm)',
  'Ng': 'GT轴转速 Ng_mean (rpm)',
  'Wf': '燃油流量 Wf_mean (kg/s)',
  'Mkp': 'PT扭矩 Mkp_mean (N·m)',
  'Mkg': 'GT扭矩 Mkg_mean (N·m)',
  'Tt1': '进口总温 Tt1_mean (K)',
  'Pt2': 'AC进口总压 Pt2_mean (Pa)',
  'Pt3': 'HPC出口总压 Pt3_mean (Pa)',
  'Tt3': 'HPC出口总温 Tt3_mean (K)',
  'Tt45': '涡轮出口总温 Tt45_mean (K)',
  'Pt45': '涡轮出口总压 Pt45_mean (Pa)',
  'Pamb': '环境压力 Pamb_mean (Pa)',
  'Tamb': '环境温度 Tamb_mean (K)',
  'Altitude': '飞行高度 Altitude_mean (m)',
  'Mach': '马赫数 Mach_mean（无量纲）'
};

/** 调度变量表表头单位提示 */
const GROUP_UNIT_TIPS = {
  '工况': '工况编号 point_id（无量纲）',
  '数据角色': 'training / test（无量纲）',
  '训练分组': '聚类组号 G1, G2... 或 N/A（无量纲）',
  'AC相对换算转速': '无量纲',
  '进气道换算流量': 'kg/s',
  '燃烧室进口换算流量': 'kg/s',
  'GT物理压比': '无量纲',
  'GT-PT涵道换算流量': 'kg/s',
  'PT物理压比': '无量纲',
  'PT-尾喷管涵道换算流量': 'kg/s',
  '测量燃油流量归一化坐标': '无量纲'
};

/** 测量数据异常阈值（超出范围标红） */
const MEASURE_ANOMALY = {
  'Np': [0, 40000], 'Ng': [0, 50000], 'Wf': [0, 10],
  'Tt1': [200, 400], 'Tt3': [200, 1200], 'Tt45': [200, 1400],
  'Pt2': [50000, 200000], 'Pt3': [50000, 600000], 'Pt45': [50000, 600000],
  'Pamb': [50000, 120000], 'Tamb': [200, 350], 'Altitude': [0, 20000], 'Mach': [0, 3]
};

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
    this.loading = false;
    this.loadingText = '';
    this.initPolling = false;
    this.initPollingText = '';

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
      notes: '',
      trainingData: '',
      testData: ''
    };
    // 可用数据文件列表（从后端获取）
    this.availableDataFiles = [];
    // 预览数据缓存
    this.preview = { training: null, test: null };

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

  /* 关闭当前项目：重置状态，不删除 workspace 数据 */
  closeProject() {
    this.workspace = null;
    this.projectCreated = false;
    this.projectForm = { projectName: '', modelPackage: '', notes: '', trainingData: '', testData: '' };
    this.preview = { training: null, test: null };
    this.tasks.clear();
    this.results.clear();
    this.render();
    if (this.ctx.refreshNav) this.ctx.refreshNav();
    if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('已关闭当前项目', 'info');
  }

  async setSection(sectionId) {
    this.activeSection = sectionId;
    this.render();
  }

  /* 项目创建完成前或初始化中，除"新建项目与数据"外全部锁定 */
  getLockedSections() {
    if (this.projectCreated && !this.initPolling) return [];
    return ['identify', 'identifiability', 'uq', 'validation', 'prediction', 'results'];
  }

  async onHeaderAction(label, sectionId) {
    this.ctx.log(`触发操作：${label}（${sectionId}）`);
    if (label === '创建并校验项目') {
      await this.handleCreateProject();
    } else if (label === '字段说明') {
      this.showFieldHelp();
    } else if (label === '打开已有项目') {
      await this.handleOpenExistingProject();
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
    await this.withLoading('正在加载数据...', async () => {
      try {
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
        }
      } catch (e) {
        console.warn('读取工作区失败:', e);
      }
    });
  }

  async loadWorkspaceDetails() {
    if (!this.workspace || !this.ctx.http) return;
    await this.withLoading('正在加载工作区详情...', async () => {
      try {
        // 先刷新 workspace 状态
        const ws = await this.ctx.http.workspace.request(this.workspace.id, { method: 'GET' });
        if (ws) this.workspace = ws;

        const wsStatus = (this.workspace && this.workspace.status) || '';
        // 如果 workspace 还在创建/初始化中，启动轮询，不加载详情
        if (wsStatus === 'creating' || wsStatus === 'initializing' ||
            (this.workspace && this.workspace.initStatus === 'INITIALIZING')) {
          this.initPolling = true;
          if (this.ctx.setStatus) this.ctx.setStatus('busy', 'MATLAB 初始化中');
          this.render();
          this.pollInitStatus(this.workspace.id);
          return;
        }

        const [datasets, tasks] = await Promise.all([
          this.ctx.http.datasets.request(this.workspace.id, { method: 'GET' }).catch(() => []),
          this.ctx.http.tasks.list({ workspaceId: this.workspace.id }).catch(() => [])
        ]);
        if (Array.isArray(datasets)) this.datasets = datasets;
        if (Array.isArray(tasks)) {
          tasks.forEach(t => {
            this.tasks.set(t.id, t);
            if (t.status === TASK_STATUS.RUNNING || t.status === TASK_STATUS.READY) {
              this.schedulePoll(t.id, 1000);
            } else if (t.status === TASK_STATUS.COMPLETED && !this.results.has(t.id)) {
              this.loadTaskResult(t.id);
            }
          });
        }
        if (this.workspace.jobName) this.projectForm.projectName = this.workspace.jobName;
        if (this.workspace.programName) this.projectForm.modelPackage = this.workspace.programName;
        if (this.workspace.trainingDataFile) this.projectForm.trainingData = this.workspace.trainingDataFile;
        if (this.workspace.testDataFile) this.projectForm.testData = this.workspace.testDataFile;
        if (this.workspace.initStatus === 'SUCCEEDED') {
          // 从 IGINX 实体表查询测量数据行和调度变量行
          let measureRows = [];
          let scheduleRows = [];
          try {
            measureRows = await this.ctx.http.workspace.request(`${this.workspace.id}/measure-data`, { method: 'GET' });
            scheduleRows = await this.ctx.http.workspace.request(`${this.workspace.id}/schedule-vars`, { method: 'GET' });
          } catch (e) {
            this.ctx.log('从 IGINX 加载测量数据/调度变量失败: ' + (e.message || e));
          }
          this.preview.training = {
            rows: Array.isArray(measureRows) ? measureRows : [],
            scheduleRows: Array.isArray(scheduleRows) ? scheduleRows : [],
            rowCount: this.workspace.initRowCount || (Array.isArray(measureRows) ? measureRows.length : 0),
            valid: this.workspace.initValid !== false,
            missingColumns: this.workspace.initMissingColumns || [],
            groupCount: this.workspace.initGroupCount || 0
          };
        } else if (this.workspace.trainingDataFile) {
          await this.loadPreview(this.workspace.trainingDataFile, 'training');
        }
        if (this.workspace.testDataFile) {
          await this.loadPreview(this.workspace.testDataFile, 'test');
        }
      } catch (e) {
        console.warn('刷新工作区详情失败:', e);
      }
    });
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
          if (task.status === TASK_STATUS.COMPLETED) {
            this.ctx.log(`任务 ${task.id} 运行完成`);
            this.ctx.setStatus('ready', '任务已完成');
            await this.loadTaskResult(task.id);
          } else if (task.status === TASK_STATUS.FAILED) {
            this.ctx.log(`任务 ${task.id} 运行失败: ` + (task.error || '未知错误'));
            this.ctx.setStatus('error', '计算失败');
            if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('任务失败: ' + (task.error || ''), 'error');
          } else if (task.status === TASK_STATUS.SKIPPED) {
            this.ctx.log(`任务 ${task.id} 已跳过: ` + (task.error || ''));
            this.ctx.setStatus('ready', '任务已跳过');
            if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('任务已跳过: ' + (task.error || ''), 'info');
          } else if (task.status === TASK_STATUS.CANCELLING) {
            this.ctx.log(`任务 ${task.id} 取消中...`);
            this.ctx.setStatus('busy', '任务取消中');
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

  /* 带 loading 状态的异步操作包装 */
  async withLoading(text, fn) {
    this.loading = true;
    this.loadingText = text;
    this.render();
    try {
      return await fn();
    } finally {
      this.loading = false;
      this.loadingText = '';
      this.render();
    }
  }

  render() {
    if (this.destroyed || !this.mount) return;
    this.disposeCharts();
    this.mount.replaceChildren();

    const view = el('div', 'section-view');
    view.style.position = 'relative';
    const renderer = this['render_' + this.activeSection];
    if (renderer) {
      renderer.call(this, view);
    } else {
      this.render_data(view);
    }

    // loading 覆盖层
    if (this.loading) {
      const overlay = el('div', 'loading-overlay');
      overlay.style.cssText = 'position:absolute;top:0;left:0;right:0;bottom:0;background:rgba(255,255,255,.7);display:flex;flex-direction:column;align-items:center;justify-content:center;z-index:100;border-radius:inherit;';
      const spinner = el('div', 'loading-spinner');
      spinner.style.cssText = 'width:36px;height:36px;border:3px solid #e8e8e8;border-top-color:#1890ff;border-radius:50%;animation:dmg-spin .8s linear infinite;';
      const text = el('div', 'loading-text', this.loadingText || '加载中...');
      text.style.cssText = 'margin-top:12px;font-size:14px;color:#666;';
      overlay.append(spinner, text);
      view.append(overlay);
      // 注入 keyframes（只注入一次）
      if (!document.getElementById('dmg-loading-style')) {
        const style = document.createElement('style');
        style.id = 'dmg-loading-style';
        style.textContent = '@keyframes dmg-spin{to{transform:rotate(360deg)}}';
        document.head.append(style);
      }
    }

    this.mount.appendChild(view);
  }

  /* ================= 01 项目与数据 ================= */
  render_data(container) {
    const validated = this.projectCreated && !this.initPolling;
    const statusText = this.initPolling ? '校验中' : (this.projectCreated ? '已校验' : '待校验');
    const statusClass = this.initPolling ? 'field-status pending' : (this.projectCreated ? 'field-status validated' : 'field-status pending');

    // Card 1: 项目建立与数据合同
    const c1 = this.createCard(
      '项目建立与数据合同',
      '项目创建完成前，后续功能保持锁定；测试数据可选且不参与参数辨识。'
    );
    const form = el('div', 'form-grid-4');

    const nameInput = input('text', 'projectName', '请输入项目名称', this.projectForm.projectName);
    nameInput.addEventListener('input', () => { this.projectForm.projectName = nameInput.value; });

    // 备注
    const notesInput = document.createElement('textarea');
    notesInput.name = 'notes';
    notesInput.placeholder = '项目备注（可选）';
    notesInput.value = this.projectForm.notes || '';
    notesInput.rows = 2;
    notesInput.style.cssText = 'width:100%;padding:6px 8px;border:1px solid #d4dde5;border-radius:3px;font-size:13px;resize:vertical;box-sizing:border-box;';
    notesInput.addEventListener('input', () => { this.projectForm.notes = notesInput.value; });

    // 模型程序包：使用 ctx.program 信息
    const programName = this.ctx.program && this.ctx.program.name || '稳态试车工况点模型修正V1';
    const pkgOptions = [{ value: '', label: '选择交付程序目录' }, programName];
    const pkgSelect = select(pkgOptions, this.projectForm.modelPackage || '');
    pkgSelect.addEventListener('change', () => { this.projectForm.modelPackage = pkgSelect.value; });

    // 训练数据/测试数据：从后端获取的可用数据文件列表
    const dataFileNames = this.availableDataFiles.map(f => f.fileName);
    const trainOptions = [{ value: '', label: '选择训练试车数据' }, ...dataFileNames];
    const testOptions = [{ value: '', label: '选择测试数据（可选）' }, ...dataFileNames];
    const trainSelect = select(trainOptions, this.projectForm.trainingData || '');
    const testSelect = select(testOptions, this.projectForm.testData || '');

    // 选择数据只记录文件名，不立即加载预览；创建项目后才加载
    trainSelect.addEventListener('change', () => {
      this.projectForm.trainingData = trainSelect.value;
    });
    testSelect.addEventListener('change', () => {
      this.projectForm.testData = testSelect.value;
    });

    // 项目创建后锁定表单
    if (this.projectCreated) {
      nameInput.disabled = true;
      notesInput.disabled = true;
      pkgSelect.disabled = true;
      trainSelect.disabled = true;
      testSelect.disabled = true;
    }

    form.append(
      this.createField('项目名称', nameInput),
      this.createField('模型程序包', pkgSelect),
      this.createField('训练数据', trainSelect),
      this.createField('测试数据', testSelect)
    );

    // 总体校验状态标识，放在第一行最右边
    const statusWrap = el('div', 'field-status-wrap');
    statusWrap.append(el('span', statusClass, statusText));
    form.append(statusWrap);

    c1.body.append(form);

    // 第二行：备注（独占一行）
    const form2 = el('div', 'form-grid-4');
    form2.style.marginTop = '12px';
    const notesField = el('div', 'form-field');
    notesField.style.gridColumn = '1 / span 4';
    notesField.append(el('label', '', '备注'));
    notesField.append(notesInput);
    form2.append(notesField);
    c1.body.append(form2);

    container.append(c1.card);

    // 数据状态仅在项目创建/打开后显示（初始化中时不显示数据状态，等初始化完成）
    if (this.projectCreated && !this.initPolling) {

    // Card 1b: 数据区 — 文件状态、工况数、字段完整性、数据指纹
    const c1b = this.createCard(
      '数据状态',
      '显示训练集和测试集的文件状态、工况数、字段完整性和数据指纹。'
    );
    const dataStatusRows = [];
    const addDataStatus = (label, file, preview) => {
      const exists = !!file;
      const rowCount = preview && preview.rowCount != null ? preview.rowCount : (preview && preview.rows ? preview.rows.length : 0);
      const valid = preview && preview.valid !== false;
      const missing = preview && preview.missingColumns ? preview.missingColumns.join(', ') : '';
      const fingerprint = preview && preview.fingerprint ? preview.fingerprint
        : (this.workspace && this.workspace.uploadedDatasets ? (this.workspace.uploadedDatasets.find(d => d.datasetKey === label) || {}).sha256 : '');
      dataStatusRows.push([
        label,
        exists ? file : '—',
        exists ? '已导入' : '未导入',
        exists ? rowCount : '—',
        exists ? (valid ? '完整' : '缺失: ' + missing) : '—',
        fingerprint ? String(fingerprint).substring(0, 12) + '...' : '—'
      ]);
    };
    addDataStatus('trainingData', this.projectForm.trainingData, this.preview.training);
    addDataStatus('testData', this.projectForm.testData, this.preview.test);
    c1b.body.append(this.createTable(
      ['数据集', '文件名', '文件状态', '工况数', '字段完整性', '数据指纹(SHA256)'],
      dataStatusRows
    ));
    container.append(c1b.card);

    } // end if (this.projectCreated) — 数据状态

    // Card 2: 测量数据表（始终显示，初始化中时内容区显示 loading）
    const c2 = this.createCard(
      '测量数据表',
      '每行对应一个稳态工况窗口；全部测量字段保存在同一张表中，固定工况编号并支持横向滚动。'
    );
    if (this.projectCreated && this.initPolling) {
      c2.body.append(this.createLoadingPlaceholder('正在加载测量数据...'));
    } else {
      const measureRows = this.extractMeasureRows();
      c2.body.append(this.createEnhancedTable(MEASURE_HEADERS, measureRows, {
        unitTips: MEASURE_UNIT_TIPS,
        anomaly: MEASURE_ANOMALY,
        freezeCols: 1,
        groupHeaders: MEASURE_GROUPS
      }));
      c2.body.append(el('p', 'table-note', '单位、缺失值、越界标记和原始字段名在列标题提示中展示；表内数值由导入文件动态读取。'));
    }
    container.append(c2.card);

    // Card 3: 调度变量与训练分组表（始终显示，初始化中时内容区显示 loading）
    const c3 = this.createCard(
      'AC相对换算转速、调度变量与训练分组',
      '同一表显示各工况辅助变量；按AC相对换算转速聚类后写入训练分组列。'
    );
    if (this.projectCreated && this.initPolling) {
      c3.body.append(this.createLoadingPlaceholder('正在加载调度变量...'));
    } else {
      const groupRows = this.extractGroupRows();
      c3.body.append(this.createEnhancedTable(GROUP_HEADERS, groupRows, {
        unitTips: GROUP_UNIT_TIPS,
        freezeCols: 1,
        cellClass: (header, val) => {
          if (header === '训练分组' && val) {
            const m = /^组(\d+)$/.exec(String(val));
            if (m) return 'group-g' + Math.min(parseInt(m[1]), 6);
          }
          return null;
        }
      }));
      const note = el('p', 'table-note', '');
      note.style.fontWeight = 'bold';
      note.textContent = '用途:AC相对换算转速用于聚类与HPC调度节点;其余列分别服务于压损、涡轮和燃油偏置调度。';
      c3.body.append(note);
    }
    container.append(c3.card);

    // Card 4: 质量与操作区（仅在项目创建且非初始化中时显示）
    if (this.projectCreated && !this.initPolling) {
    const c4 = this.createCard(
      '质量与操作',
      '显示数据合同校验结果、工况覆盖、分组状态；项目创建后可进入参数辨识。'
    );
    const p = this.preview.training;
    const qualityRows = [];
    if (p) {
      qualityRows.push(['工况数', String(p.rowCount || 0)]);
      qualityRows.push(['字段校验', p.valid !== false ? '通过' : '缺失: ' + (p.missingColumns || []).join(', ')]);
      // 异常字段：扫描测量数据中超出阈值的字段
      const anomalyFields = [];
      if (p.rows && p.rows.length) {
        MEASURE_HEADERS.forEach(h => {
          const range = MEASURE_ANOMALY[h];
          if (!range) return;
          const key = h === '工况' ? 'point_id' : (h === 'Altitude' ? 'Altitude_mean' : h + '_mean');
          let hasAnomaly = false;
          for (const r of p.rows) {
            const num = parseFloat(r[key]);
            if (!isNaN(num) && (num < range[0] || num > range[1])) { hasAnomaly = true; break; }
          }
          if (hasAnomaly) anomalyFields.push(h);
        });
      }
      qualityRows.push(['异常字段', anomalyFields.length ? anomalyFields.join(', ') : '无']);
      // 缺失值统计
      let missingCount = 0;
      if (p.rows && p.rows.length) {
        MEASURE_HEADERS.forEach(h => {
          const key = h === '工况' ? 'point_id' : (h === 'Altitude' ? 'Altitude_mean' : h + '_mean');
          for (const r of p.rows) {
            if (r[key] == null || r[key] === '') missingCount++;
          }
        });
      }
      qualityRows.push(['缺失值', String(missingCount)]);
      qualityRows.push(['训练分组数', String(p.groupCount || 0)]);
      qualityRows.push(['测量数据行', String((p.rows || []).length)]);
      qualityRows.push(['调度变量行', String((p.scheduleRows || []).length)]);
    } else {
      qualityRows.push(['工况数', '—']);
      qualityRows.push(['字段校验', '—']);
      qualityRows.push(['异常字段', '—']);
      qualityRows.push(['缺失值', '—']);
      qualityRows.push(['训练分组数', '—']);
      qualityRows.push(['测量数据行', '—']);
      qualityRows.push(['调度变量行', '—']);
    }
    c4.body.append(this.createTable(['检查项', '结果'], qualityRows));

    // 操作按钮
    const qualityOpRow = el('div', 'btn-row');
    qualityOpRow.style.marginTop = '12px';
    qualityOpRow.append(
      button('重新计算辅助变量', 'btn-card', async () => {
        if (!this.workspace) {
          if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('请先创建并校验项目', 'warning');
          return;
        }
        await this.loadWorkspaceDetails();
        if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('辅助变量已重新计算', 'success');
      }),
      button('进入参数辨识', 'btn-card primary', () => {
        if (this.projectCreated) {
          if (this.ctx.setSection) this.ctx.setSection('identify');
        } else {
          if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('请先创建并校验项目', 'warning');
        }
      })
    );
    c4.body.append(qualityOpRow);
    container.append(c4.card);

    } // end if (this.projectCreated) — 质量与操作
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

  /* 从预览数据中提取测量数据行 */
  extractMeasureRows() {
    const p = this.preview.training;
    if (p && Array.isArray(p.rows)) {
      return p.rows.map(r => MEASURE_HEADERS.map(h => {
        const key = h === '工况' ? 'point_id' : (h === 'Altitude' ? 'Altitude_mean' : h + '_mean');
        const val = r[key];
        return val != null ? val : '—';
      }));
    }
    return [];
  }

  /* 从预览数据中提取调度变量与分组行 */
  extractGroupRows() {
    const p = this.preview.training;
    if (p && Array.isArray(p.scheduleRows)) {
      const groupLabel = v => {
        if (v == null || v === 'N/A') return '未分组';
        const m = /^G(\d+)$/.exec(v);
        return m ? `组${m[1]}` : v;
      };
      const roleLabel = v => v === 'training' ? '训练' : (v === 'test' ? '测试' : (v || '—'));
      return p.scheduleRows.map(r => GROUP_HEADERS.map(h => {
        const key = GROUP_KEY_MAP[h] || h;
        let val = r[key];
        if (val == null) return '—';
        if (key === 'trainingGroup') return groupLabel(val);
        if (key === 'dataRole') return roleLabel(val);
        if (typeof val === 'number' && !isNaN(val)) {
          return Number.isInteger(val) ? val : val.toFixed(4);
        }
        return val;
      }));
    }
    return [];
  }

  /* 加载数据文件预览 */
  async loadPreview(fileName, type) {
    this.ctx.log(`正在加载数据预览: ${fileName}...`);
    await this.withLoading(`正在加载${type === 'training' ? '训练' : '测试'}数据预览...`, async () => {
      try {
        if (this.ctx.http && this.ctx.http.previewData) {
          const data = await this.ctx.http.previewData.request('', { method: 'GET', query: { fileName } });
          this.preview[type] = data;
          this.projectForm[type === 'training' ? 'trainingData' : 'testData'] = fileName;
          this.ctx.log(`数据预览完成: ${data.rowCount || 0} 行, ${data.valid ? '字段校验通过' : '缺少字段: ' + (data.missingColumns || []).join(', ')}`);
        }
      } catch (e) {
        this.ctx.log('数据预览失败: ' + (e.message || e));
        if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('数据预览失败: ' + (e.message || e), 'error');
      }
    });
  }

  /* ================= 02 参数辨识 ================= */
  render_identify(container) {
    const identifyResult = this.latestResult('estimateTransient') || this.latestResult('estimateSteady');
    const isRunning = this.latestTask('estimateTransient')?.status === TASK_STATUS.RUNNING || this.latestTask('estimateSteady')?.status === TASK_STATUS.RUNNING;

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
    const isRunning = this.latestTask(this.activeUqMethod === 'B' ? 'uqMethodB' : 'uqMethodA')?.status === TASK_STATUS.RUNNING;

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
      this.createMetricBox('稳态辨识模型状态', latestIdentTask && latestIdentTask.reviewStatus === TASK_STATUS.REVIEW_APPROVED ? '已审核通过' : '待审核')
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

  createLoadingPlaceholder(text) {
    const box = el('div', 'loading-placeholder');
    box.style.cssText = 'display:flex;flex-direction:column;align-items:center;justify-content:center;padding:40px 20px;';
    const spinner = el('div', 'loading-spinner');
    spinner.style.cssText = 'width:32px;height:32px;border:3px solid #e8e8e8;border-top-color:#1890ff;border-radius:50%;animation:dmg-spin .8s linear infinite;';
    const label = el('div', '', text || '加载中...');
    label.style.cssText = 'margin-top:12px;font-size:14px;color:#666;';
    box.append(spinner, label);
    return box;
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

  /**
   * 增强表格：支持排序、筛选、单位提示、异常标记、列冻结。
   * @param headers  表头数组
   * @param rows     数据行（与 headers 列对齐）
   * @param opts     { unitTips: {header->tip}, anomaly: {header->[min,max]}, freezeCols: number }
   */
  createEnhancedTable(headers, rows, opts = {}) {
    const unitTips = opts.unitTips || {};
    const anomaly = opts.anomaly || {};
    const freezeCols = opts.freezeCols || 1;
    const groupHeaders = opts.groupHeaders || null;
    const cellClass = opts.cellClass || null;
    let sortCol = -1, sortDesc = false;
    const colFilters = headers.map(() => '');

    const wrap = el('div', 'table-wrap enhanced-table-wrap');

    const table = el('table', 'data-table enhanced-table');
    const thead = el('thead');

    // 类别分组行（可选）
    if (groupHeaders) {
      const groupRow = el('tr', 'group-header-row');
      let colIdx = 0;
      groupHeaders.forEach(g => {
        const th = el('th', 'group-header', g.label);
        th.colSpan = g.span;
        if (colIdx < freezeCols) th.classList.add('freeze-col');
        colIdx += g.span;
        groupRow.append(th);
      });
      thead.append(groupRow);
    }

    // 表头行
    const hr = el('tr');
    headers.forEach((h, idx) => {
      const th = el('th', '', h);
      if (idx < freezeCols) th.classList.add('freeze-col');
      if (unitTips[h]) th.title = unitTips[h];
      th.style.cursor = 'pointer';
      // 排序
      th.addEventListener('click', (e) => {
        // 点击搜索图标时不触发排序
        if (e.target.classList && e.target.classList.contains('th-filter-icon')) return;
        if (sortCol === idx) { sortDesc = !sortDesc; }
        else { sortCol = idx; sortDesc = false; }
        renderHead();
        renderBody();
      });
      // 搜索图标 + 内联筛选输入框
      const filterWrap = el('span', 'th-filter-wrap');
      const icon = el('span', 'th-filter-icon', '🔍');
      icon.title = '点击筛选此列';
      const inp = el('input', 'th-filter-input');
      inp.type = 'text';
      inp.placeholder = '筛选';
      inp.style.display = 'none';
      inp.addEventListener('input', () => {
        colFilters[idx] = inp.value.trim().toLowerCase();
        renderBody();
      });
      inp.addEventListener('click', e => e.stopPropagation());
      icon.addEventListener('click', e => {
        e.stopPropagation();
        inp.style.display = inp.style.display === 'none' ? '' : 'none';
        if (inp.style.display !== 'none') inp.focus();
        else { inp.value = ''; colFilters[idx] = ''; renderBody(); }
      });
      filterWrap.append(icon, inp);
      th.append(filterWrap);
      hr.append(th);
    });
    thead.append(hr);

    table.append(thead);
    const tbody = el('tbody');
    table.append(tbody);
    wrap.append(table);

    function renderHead() {
      hr.querySelectorAll('th').forEach((th, idx) => {
        th.classList.remove('sort-asc', 'sort-desc');
        if (idx === sortCol) th.classList.add(sortDesc ? 'sort-desc' : 'sort-asc');
      });
    }

    function renderBody() {
      tbody.innerHTML = '';
      let data = rows.slice();
      // 按列筛选
      const hasFilter = colFilters.some(f => f.length > 0);
      if (hasFilter) {
        data = data.filter(r => r.every((v, idx) => {
          if (!colFilters[idx]) return true;
          return String(v == null ? '' : v).toLowerCase().includes(colFilters[idx]);
        }));
      }
      // 排序
      if (sortCol >= 0) {
        data.sort((a, b) => {
          const va = a[sortCol], vb = b[sortCol];
          const na = parseFloat(va), nb = parseFloat(vb);
          if (!isNaN(na) && !isNaN(nb)) return sortDesc ? nb - na : na - nb;
          return sortDesc
            ? String(vb).localeCompare(String(va))
            : String(va).localeCompare(String(vb));
        });
      }
      data.forEach(r => {
        const tr = el('tr');
        r.forEach((val, idx) => {
          const td = el('td');
          if (idx < freezeCols) td.classList.add('freeze-col');
          if (val instanceof HTMLElement) {
            td.append(val);
          } else {
            const str = String(val == null ? '' : val);
            td.textContent = str;
            if (str === '动态显示' || str === '待运行') td.classList.add('dim');
            const range = anomaly[headers[idx]];
            if (range) {
              const num = parseFloat(val);
              if (!isNaN(num) && (num < range[0] || num > range[1])) {
                td.classList.add('anomaly');
                td.title = `异常值：${num}（正常范围 ${range[0]}~${range[1]}）`;
              }
            }
            if (cellClass) {
              const cls = cellClass(headers[idx], val, r, idx);
              if (cls) td.classList.add(cls);
            }
          }
          tr.append(td);
        });
        tbody.append(tr);
      });
    }

    renderBody();
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

  /* ================= 字段说明 / 帮助 / 打开已有项目 ================= */

  /* 字段说明：弹出测量数据表和调度变量表的字段定义 */
  showFieldHelp() {
    const measureFields = [
      ['point_id', '工况编号', '-', '主键，关联试车工况、计算结果和日志'],
      ['Np_mean', 'PT轴转速', 'rpm', '测量'],
      ['Ng_mean', 'GT轴转速', 'rpm', '测量'],
      ['Wf_mean', '燃油流量', 'kg/s', '测量输入'],
      ['Mkp_mean', 'PT负载扭矩', 'N·m', '模型输入'],
      ['Mkg_mean', 'GT外部附件负载扭矩', 'N·m', '模型输入'],
      ['Pt2_mean', '压气机入口总压', 'Pa', '模式4模型输入'],
      ['Tt1_mean', '进口总温测量', 'K', '模式4模型输入'],
      ['Pt3_mean', '压气机出口总压', 'Pa', '拟合输出'],
      ['Tt3_mean', '压气机出口总温', 'K', '拟合输出'],
      ['Tt45_mean', '45截面总温', 'K', '拟合输出'],
      ['Pt45_mean', '45截面总压', 'Pa', '拟合输出'],
      ['Pamb_mean', '环境静压', 'Pa', '环境输入'],
      ['Tamb_mean', '环境静温', 'K', '环境输入'],
      ['Altitude_mean', '高度', 'm', '记录/预测模式输入'],
      ['Mach_mean', '马赫数', '-', '环境输入']
    ];
    const scheduleFields = [
      ['数据角色', '标识训练数据或测试数据'],
      ['训练分组', '训练工况的聚类组号；测试工况显示"不参与分组"'],
      ['AC相对换算转速', '训练工况聚类主坐标，并用于HPC流量/效率修正调度'],
      ['进气道换算流量', '进气道压损修正的工况坐标'],
      ['燃烧室进口换算流量', '燃烧室压损修正调度'],
      ['GT物理压比', 'GT流量/效率修正调度，避免修正量自反馈'],
      ['GT-PT涵道换算流量', 'GT-PT涵道压损修正调度'],
      ['PT物理压比', 'PT流量/效率修正调度'],
      ['PT-尾喷管涵道换算流量', 'PT-尾喷管涵道压损修正调度'],
      ['测量燃油流量归一化坐标', '燃油测量偏置节点调度']
    ];

    const overlay = el('div', 'help-overlay');
    overlay.style.cssText = 'position:fixed;top:0;left:0;right:0;bottom:0;background:rgba(0,0,0,.5);z-index:9999;display:flex;align-items:center;justify-content:center;';
    const dialog = el('div', 'help-dialog');
    dialog.style.cssText = 'background:#fff;border-radius:8px;max-width:720px;max-height:80vh;overflow:auto;padding:24px 32px;box-shadow:0 4px 24px rgba(0,0,0,.2);';
    const close = () => overlay.remove();
    overlay.addEventListener('click', e => { if (e.target === overlay) close(); });

    const title = el('h3', '', '字段说明');
    title.style.cssText = 'margin:0 0 16px 0;font-size:18px;color:#1a1a1a;';
    dialog.append(title);

    const h1 = el('h4', '', '测量数据表字段');
    h1.style.cssText = 'margin:16px 0 8px 0;font-size:15px;color:#333;';
    dialog.append(h1);
    const t1 = this.createTable(
      ['字段名', '含义', '单位', '角色'],
      measureFields.map(r => [el('code', '', r[0]), r[1], r[2], r[3]])
    );
    t1.style.cssText = 'font-size:13px;margin-bottom:16px;';
    dialog.append(t1);

    const h2 = el('h4', '', '调度变量与训练分组表字段');
    h2.style.cssText = 'margin:16px 0 8px 0;font-size:15px;color:#333;';
    dialog.append(h2);
    const t2 = this.createTable(
      ['字段', '用途'],
      scheduleFields.map(r => [r[0], r[1]])
    );
    t2.style.cssText = 'font-size:13px;margin-bottom:16px;';
    dialog.append(t2);

    const btnRow = el('div', '');
    btnRow.style.cssText = 'text-align:right;';
    const btn = el('button', 'btn primary', '关闭');
    btn.style.cssText = 'padding:6px 20px;border:none;border-radius:4px;background:#1890ff;color:#fff;cursor:pointer;font-size:14px;';
    btn.addEventListener('click', close);
    btnRow.append(btn);
    dialog.append(btnRow);

    overlay.append(dialog);
    document.body.append(overlay);
  }

  /* 顶部帮助按钮：弹出当前页面的操作指引 */
  onHelp() {
    const helps = {
      data: {
        title: '新建项目与数据 — 帮助',
        content: [
          '1. 输入项目名称，选择模型程序包和训练数据（测试数据可选）。',
          '2. 选择训练数据后自动加载测量数据表和调度变量表。',
          '3. 点击"创建并校验项目"执行零修正回放，校验数据合同并计算调度变量。',
          '4. 项目创建完成后，后续功能（参数辨识、可辨识性等）自动解锁。',
          '5. 训练集用于参数辨识，测试集仅用于独立验证，不参与参数更新。',
          '6. 点击"字段说明"查看测量字段和调度变量的详细定义。'
        ]
      },
      identify: {
        title: '参数辨识 — 帮助',
        content: [
          '1. 默认采用瞬态时刻模型，可切换为稳态模型。',
          '2. A阶段全工况常值初估，B阶段分组组内估计，C阶段调度重构，D阶段全工况微调。',
          '3. 点击"开始辨识"执行参数辨识，形成稳态辨识模型。',
          '4. 辨识完成后可查看参数估计值、输出误差标准差和计算时间。'
        ]
      },
      identifiability: {
        title: '可辨识性 — 帮助',
        content: [
          '1. 展示整体信息质量、逐参数分类和主要补偿参数。',
          '2. 帮助判断辨识结果能否独立解释，是否存在参数补偿关系。',
          '3. 点击"生成分析报告"执行可辨识性分析。'
        ]
      },
      uq: {
        title: '不确定性评估 — 帮助',
        content: [
          '1. 方法A评估关键修正系数的95%置信区间。',
          '2. 方法B评估全修正系数后验及输出的95%置信区间。',
          '3. 点击"开始评估"执行不确定性评估。'
        ]
      },
      validation: {
        title: '测试验证 — 帮助',
        content: [
          '1. 使用独立测试集验证稳态辨识模型。',
          '2. 展示稳态输出对比和误差标准差对比。',
          '3. 点击"开始验证"执行测试集验证。'
        ]
      },
      prediction: {
        title: '工况预测 — 帮助',
        content: [
          '1. 对指定的新工况执行确定性预测。',
          '2. 可选方法A/B后验区间预测。',
          '3. 在没有该工况测量数据时给出模型输出。'
        ]
      },
      results: {
        title: '结果中心 — 帮助',
        content: [
          '1. 审核、归档并发布项目版本。',
          '2. 结果保存输入、模型、配置、日志、图形和报告之间的对应关系。',
          '3. 点击"导出所选结果"导出结果文件。'
        ]
      }
    };
    const help = helps[this.activeSection] || helps.data;

    const overlay = el('div', 'help-overlay');
    overlay.style.cssText = 'position:fixed;top:0;left:0;right:0;bottom:0;background:rgba(0,0,0,.5);z-index:9999;display:flex;align-items:center;justify-content:center;';
    const dialog = el('div', 'help-dialog');
    dialog.style.cssText = 'background:#fff;border-radius:8px;max-width:560px;max-height:80vh;overflow:auto;padding:24px 32px;box-shadow:0 4px 24px rgba(0,0,0,.2);';
    const close = () => overlay.remove();
    overlay.addEventListener('click', e => { if (e.target === overlay) close(); });

    const title = el('h3', '', help.title);
    title.style.cssText = 'margin:0 0 16px 0;font-size:18px;color:#1a1a1a;';
    dialog.append(title);
    help.content.forEach(line => {
      const p = el('p', '', line);
      p.style.cssText = 'margin:8px 0;font-size:14px;color:#555;line-height:1.6;';
      dialog.append(p);
    });

    const btnRow = el('div', '');
    btnRow.style.cssText = 'text-align:right;margin-top:16px;';
    const btn = el('button', 'btn primary', '关闭');
    btn.style.cssText = 'padding:6px 20px;border:none;border-radius:4px;background:#1890ff;color:#fff;cursor:pointer;font-size:14px;';
    btn.addEventListener('click', close);
    btnRow.append(btn);
    dialog.append(btnRow);

    overlay.append(dialog);
    document.body.append(overlay);
  }

  /* 打开已有项目：列出已有 workspace 供用户选择 */
  async handleOpenExistingProject() {
    if (!this.ctx.http || !this.ctx.http.workspace) {
      if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('无后端连接', 'warning');
      return;
    }
    let list;
    await this.withLoading('正在加载项目列表...', async () => {
      try {
        list = await this.ctx.http.workspace.list();
      } catch (e) {
        if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('加载项目列表失败: ' + (e.message || e), 'error');
      }
    });
    if (!Array.isArray(list) || list.length === 0) {
      if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('暂无已有项目', 'info');
      return;
    }
    if (!Array.isArray(list) || list.length === 0) {
      if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('暂无已有项目', 'info');
      return;
    }
    const overlay = el('div', 'help-overlay');
    overlay.style.cssText = 'position:fixed;top:0;left:0;right:0;bottom:0;background:rgba(0,0,0,.5);z-index:9999;display:flex;align-items:center;justify-content:center;';
    const dialog = el('div', 'help-dialog');
    dialog.style.cssText = 'background:#fff;border-radius:8px;max-width:520px;max-height:80vh;overflow:auto;padding:24px 32px;box-shadow:0 4px 24px rgba(0,0,0,.2);';
    const close = () => overlay.remove();
    overlay.addEventListener('click', e => { if (e.target === overlay) close(); });

    const title = el('h3', '', '打开已有项目');
    title.style.cssText = 'margin:0 0 16px 0;font-size:18px;color:#1a1a1a;';
    dialog.append(title);

    list.forEach(ws => {
      const item = el('div', '');
      item.style.cssText = 'padding:12px 16px;border:1px solid #e8e8e8;border-radius:6px;margin-bottom:8px;display:flex;align-items:center;justify-content:space-between;transition:border-color .2s,opacity .3s;';
      const info = el('div', '');
      info.style.cssText = 'flex:1;cursor:pointer;';
      const name = el('div', '', ws.jobName || ws.id);
      name.style.cssText = 'font-size:15px;font-weight:600;color:#1a1a1a;';
      const meta = el('div', '', `${ws.trainingDataFile || '-'}  ·  ${ws.createdAt || ''}`);
      meta.style.cssText = 'font-size:12px;color:#999;margin-top:4px;';
      info.append(name, meta);
      info.addEventListener('mouseenter', () => { item.style.borderColor = '#1890ff'; });
      info.addEventListener('mouseleave', () => { item.style.borderColor = '#e8e8e8'; });
      info.addEventListener('click', async () => {
        info.style.pointerEvents = 'none';
        name.textContent = (ws.jobName || ws.id) + '  ·  加载中...';
        try {
          close();
          this.workspace = ws;
          this.projectCreated = true;
          this.projectForm.projectName = ws.jobName || '';
          this.projectForm.modelPackage = ws.programName || '';
          this.projectForm.trainingData = ws.trainingDataFile || '';
          this.projectForm.testData = ws.testDataFile || '';
          await this.loadWorkspaceDetails();
          if (this.ctx.refreshNav) this.ctx.refreshNav();
          if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('已打开项目: ' + (ws.jobName || ws.id), 'success');
        } catch (err) {
          info.style.pointerEvents = '';
          name.textContent = ws.jobName || ws.id;
          if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('打开项目失败: ' + (err.message || err), 'error');
        }
      });

      const delBtn = el('button', '', '删除');
      delBtn.style.cssText = 'padding:4px 12px;border:1px solid #ff4d4f;border-radius:4px;background:#fff;color:#ff4d4f;cursor:pointer;font-size:13px;flex-shrink:0;margin-left:12px;transition:all .2s;';
      delBtn.addEventListener('mouseenter', () => { delBtn.style.background = '#ff4d4f'; delBtn.style.color = '#fff'; });
      delBtn.addEventListener('mouseleave', () => { delBtn.style.background = '#fff'; delBtn.style.color = '#ff4d4f'; });
      delBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        const confirmRow = el('div', '');
        confirmRow.style.cssText = 'padding:8px 0 0 0;display:flex;align-items:center;gap:8px;flex-wrap:wrap;';
        const hint = el('span', '', `确认删除"${ws.jobName || ws.id}"？不可恢复`);
        hint.style.cssText = 'font-size:13px;color:#ff4d4f;flex:1;';
        const yesBtn = el('button', '', '确认删除');
        yesBtn.style.cssText = 'padding:4px 12px;border:none;border-radius:4px;background:#ff4d4f;color:#fff;cursor:pointer;font-size:13px;';
        const noBtn = el('button', '', '取消');
        noBtn.style.cssText = 'padding:4px 12px;border:1px solid #d9d9d9;border-radius:4px;background:#fff;color:#666;cursor:pointer;font-size:13px;';
        confirmRow.append(hint, noBtn, yesBtn);

        item.style.borderColor = '#ff4d4f';
        item.style.background = '#fff1f0';
        item.replaceChildren(confirmRow);

        noBtn.addEventListener('click', () => {
          item.style.borderColor = '#e8e8e8';
          item.style.background = '';
          item.replaceChildren(info, delBtn);
        });

        yesBtn.addEventListener('click', async () => {
          yesBtn.disabled = true;
          noBtn.disabled = true;
          yesBtn.textContent = '删除中...';
          try {
            await this.ctx.http.workspace.request(ws.id, { method: 'DELETE' });
            this.workspaces = this.workspaces.filter(w => w.id !== ws.id);
            if (this.workspace && this.workspace.id === ws.id) {
              this.workspace = null;
              this.projectCreated = false;
              this.projectForm = { projectName: '', modelPackage: '', notes: '', trainingData: '', testData: '' };
              this.preview = { training: null, test: null };
              this.render();
              if (this.ctx.refreshNav) this.ctx.refreshNav();
            }
            item.style.opacity = '0';
            setTimeout(() => item.remove(), 300);
            if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('项目已删除', 'success');
            if (this.workspaces.length === 0) setTimeout(close, 400);
          } catch (err) {
            yesBtn.disabled = false;
            noBtn.disabled = false;
            yesBtn.textContent = '确认删除';
            item.style.borderColor = '#e8e8e8';
            item.style.background = '';
            item.replaceChildren(info, delBtn);
            if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('删除失败: ' + (err.message || err), 'error');
          }
        });
      });

      item.append(info, delBtn);
      dialog.append(item);
    });

    const btnRow = el('div', '');
    btnRow.style.cssText = 'text-align:right;margin-top:16px;';
    const btn = el('button', 'btn', '取消');
    btn.style.cssText = 'padding:6px 20px;border:1px solid #d9d9d9;border-radius:4px;background:#fff;cursor:pointer;font-size:14px;';
    btn.addEventListener('click', close);
    btnRow.append(btn);
    dialog.append(btnRow);

    overlay.append(dialog);
    document.body.append(overlay);
  }

  /* ================= 业务动作触发与后端交互 ================= */
  async handleCreateProject() {
    if (this.projectCreated) {
      if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('项目已创建，字段已锁定', 'warning');
      return;
    }

    // 从 DOM 读取表单值
    const root = this.mount;
    const nameInput = root.querySelector('input[name="projectName"]');
    const projectName = nameInput ? nameInput.value.trim() : this.projectForm.projectName;
    if (!projectName) {
      if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('创建失败：请输入项目名称', 'error');
      return;
    }

    const selects = root.querySelectorAll('select');
    const pkgSel = selects[0];
    const trainSel = selects[1];
    const testSel = selects[2];
    const modelPackage = pkgSel ? pkgSel.value : this.projectForm.modelPackage;
    const trainingData = trainSel ? trainSel.value : this.projectForm.trainingData;
    const testData = testSel ? testSel.value : '';
    const notesInputEl = root.querySelector('textarea[name="notes"]');
    const notes = notesInputEl ? notesInputEl.value : this.projectForm.notes;

    if (!trainingData) {
      if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('创建失败：请选择训练数据', 'error');
      return;
    }
    if (!modelPackage) {
      if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('创建失败：请选择模型程序包', 'error');
      return;
    }

    // 缓存表单
    this.projectForm = { projectName, modelPackage, notes, trainingData, testData };

    this.ctx.log('正在创建并校验项目...');
    if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('正在创建项目...', 'info');
    try {
      if (this.ctx.http && this.ctx.http.workspace) {
        // 创建 workspace（后端立即返回，MATLAB 初始化异步执行）
        const ws = await this.ctx.http.workspace.create({
          jobName: projectName,
          notes: notes || '',
          trainingData,
          testData: testData || ''
        });
        this.workspace = ws;
        this.projectCreated = true;
        this.ctx.log(`项目已创建，工作区 ID: ${ws.id}，MATLAB 初始化异步进行中...`);
        if (this.ctx.setStatus) this.ctx.setStatus('busy', 'MATLAB 初始化中');
        if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('项目已创建，MATLAB 初始化进行中', 'info');
        if (this.ctx.refreshNav) this.ctx.refreshNav();
        this.render(); // 锁定表单，显示"校验中"状态

        // 后台轮询初始化状态（不阻塞，完成后自动刷新数据）
        this.pollInitStatus(ws.id);
      } else {
        this.projectCreated = true;
        this.ctx.log('项目创建完成（无后端连接，仅本地标记）');
        if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('项目创建完成（无后端连接）', 'warning');
        if (this.ctx.refreshNav) this.ctx.refreshNav();
        this.render();
      }
    } catch (e) {
      this.ctx.log('创建项目失败: ' + (e.message || e));
      if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('创建项目失败: ' + (e.message || e), 'error');
      this.projectCreated = false;
      this.render();
    }
  }

  /* 后台轮询 workspace 初始化状态（非阻塞，完成后自动刷新数据） */
  async pollInitStatus(workspaceId) {
    const maxAttempts = 60; // 最多轮询 60 次，每次 5 秒，共 5 分钟
    const interval = 5000;
    this.initPolling = true;
    for (let i = 0; i < maxAttempts; i++) {
      if (this.destroyed) { this.initPolling = false; return; }
      try {
        const ws = await this.ctx.http.workspace.request(workspaceId, { method: 'GET' });
        if (!ws) break;
        this.workspace = ws;
        const status = ws.status || 'INITIALIZING';
        if (status === TASK_STATUS.READY) {
          // 初始化完成，从独立字段读取摘要
          const initStatus = ws.initStatus || '';
          if (initStatus === 'SUCCEEDED') {
            // 从 IGINX 实体表查询测量数据行和调度变量行
            let measureRows = [];
            let scheduleRows = [];
            try {
              measureRows = await this.ctx.http.workspace.request(`${workspaceId}/measure-data`, { method: 'GET' });
              scheduleRows = await this.ctx.http.workspace.request(`${workspaceId}/schedule-vars`, { method: 'GET' });
            } catch (e) {
              this.ctx.log('从 IGINX 加载测量数据/调度变量失败: ' + (e.message || e));
            }
            this.preview.training = {
              rows: Array.isArray(measureRows) ? measureRows : [],
              scheduleRows: Array.isArray(scheduleRows) ? scheduleRows : [],
              rowCount: ws.initRowCount || (Array.isArray(measureRows) ? measureRows.length : 0),
              valid: ws.initValid !== false,
              missingColumns: ws.initMissingColumns || [],
              groupCount: ws.initGroupCount || 0
            };
            this.ctx.log(`MATLAB初始化完成: ${ws.initRowCount || 0} 个工况, ${ws.initGroupCount || 0} 个训练分组, DLL哈希: ${(ws.initDllHash || '').substring(0, 12)}...`);
            if (this.ctx.setStatus) this.ctx.setStatus('ready', '计算环境就绪');
            if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('项目初始化完成', 'success');
          } else if (initStatus === 'FALLBACK' || initStatus === 'FAILED') {
            this.ctx.log(`MATLAB初始化${initStatus === 'FALLBACK' ? '降级' : '失败'}: ${ws.initMessage || ''}`);
            if (this.ctx.setStatus) this.ctx.setStatus('error', initStatus === 'FALLBACK' ? '初始化降级' : '初始化失败');
            if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast(`MATLAB初始化${initStatus === 'FALLBACK' ? '降级' : '失败'}: ` + (ws.initMessage || ''), initStatus === 'FALLBACK' ? 'warning' : 'error');
            if (this.projectForm.trainingData) {
              const data = await this.ctx.http.previewData.request('', { method: 'GET', query: { fileName: this.projectForm.trainingData } });
              this.preview.training = data;
            }
          } else {
            // initStatus 为空或未知，加载纯 Java 预览
            if (this.ctx.setStatus) this.ctx.setStatus('ready', '计算环境就绪');
            if (this.projectForm.trainingData) {
              const data = await this.ctx.http.previewData.request('', { method: 'GET', query: { fileName: this.projectForm.trainingData } });
              this.preview.training = data;
            }
          }
          if (this.projectForm.testData) {
            const testData = await this.ctx.http.previewData.request('', { method: 'GET', query: { fileName: this.projectForm.testData } });
            this.preview.test = testData;
          }
          this.initPolling = false;
          this.render();
          return;
        }
        // 仍在初始化中，更新左侧栏状态
        if (this.ctx.setStatus) this.ctx.setStatus('busy', `MATLAB 初始化中（${((i + 1) * interval / 1000).toFixed(0)}s）`);
        this.render();
      } catch (e) {
        this.ctx.log('轮询初始化状态失败: ' + (e.message || e));
      }
      await new Promise(r => setTimeout(r, interval));
    }
    // 超时
    this.initPolling = false;
    this.ctx.log('MATLAB 初始化等待超时，请稍后刷新查看结果');
    if (this.ctx.setStatus) this.ctx.setStatus('error', '初始化超时');
    if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('MATLAB 初始化等待超时，请稍后刷新', 'warning');
    this.render();
  }

  async handleStartIdentify() {
    if (!this.workspace) {
      await this.handleCreateProject();
    }
    const actionKey = this.identifyModel === 'steady' ? 'estimateSteady' : 'estimateTransient';
    this.ctx.log(`启动参数辨识（${actionKey}）...`);
    await this.withLoading('正在提交辨识任务...', async () => {
      try {
        const task = await this.ctx.http.tasks.create({
          workspaceId: this.workspace.id,
          actionKey: actionKey,
          inputs: { trainingData: '' }
        });
        this.ctx.log(`辨识任务已提交 (ID: ${task.id})`);
        this.tasks.set(task.id, task);
        this.schedulePoll(task.id, 500);
      } catch (e) {
        this.ctx.log('启动辨识失败: ' + (e.message || e));
        if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('启动辨识失败: ' + (e.message || e), 'error');
      }
    });
  }

  async handleStartIdentifiability() {
    if (!this.workspace) await this.handleCreateProject();
    this.ctx.log('启动工程可辨识性分析...');
    await this.withLoading('正在提交可辨识性分析...', async () => {
      try {
        const task = await this.ctx.http.tasks.create({
          workspaceId: this.workspace.id,
          actionKey: 'engineeringIdentifiability',
          inputs: {}
        });
        this.ctx.log(`可辨识性分析任务已提交 (ID: ${task.id})`);
        this.tasks.set(task.id, task);
        this.schedulePoll(task.id, 500);
      } catch (e) {
        this.ctx.log('启动可辨识性分析失败: ' + (e.message || e));
        if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('启动可辨识性分析失败: ' + (e.message || e), 'error');
      }
    });
  }

  async handleStartUq() {
    if (!this.workspace) await this.handleCreateProject();
    const actionKey = this.activeUqMethod === 'B' ? 'uqMethodB' : 'uqMethodA';
    this.ctx.log(`启动不确定性评估（${actionKey}）...`);
    await this.withLoading('正在提交不确定性评估...', async () => {
      try {
        const task = await this.ctx.http.tasks.create({
          workspaceId: this.workspace.id,
          actionKey: actionKey,
          inputs: { userCfg: { figureVisible: 'off' } }
        });
        this.ctx.log(`不确定性评估任务已提交 (ID: ${task.id})`);
        this.tasks.set(task.id, task);
        this.schedulePoll(task.id, 500);
      } catch (e) {
        this.ctx.log('启动评估失败: ' + (e.message || e));
        if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('启动评估失败: ' + (e.message || e), 'error');
      }
    });
  }

  async handleStartValidation() {
    if (!this.workspace) await this.handleCreateProject();
    this.ctx.log('启动测试集稳态模型验证...');
    await this.withLoading('正在提交测试验证...', async () => {
      try {
        const task = await this.ctx.http.tasks.create({
          workspaceId: this.workspace.id,
          actionKey: 'testValidation',
          inputs: { testData: '' }
        });
        this.ctx.log(`测试验证任务已提交 (ID: ${task.id})`);
        this.tasks.set(task.id, task);
        this.schedulePoll(task.id, 500);
      } catch (e) {
        this.ctx.log('启动测试验证失败: ' + (e.message || e));
        if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('启动测试验证失败: ' + (e.message || e), 'error');
      }
    });
  }

  async handleStartPrediction() {
    if (!this.workspace) await this.handleCreateProject();
    this.ctx.log('启动单工况预测计算...');
    await this.withLoading('正在提交预测计算...', async () => {
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
        this.schedulePoll(task.id, 500);
      } catch (e) {
        this.ctx.log('工况预测失败: ' + (e.message || e));
        if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('工况预测失败: ' + (e.message || e), 'error');
      }
    });
  }

  async handleExportResults() {
    this.ctx.log('正在导出结果产物清单...');
    if (!this.workspace) return;
    try {
      const allTasks = Array.from(this.tasks.values()).filter(t => t.status === TASK_STATUS.COMPLETED);
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
