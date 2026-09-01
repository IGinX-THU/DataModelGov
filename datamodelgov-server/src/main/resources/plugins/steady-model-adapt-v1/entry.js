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

/** 修正系数物理含义映射（对应 MATLAB local_parameter_definition） */
const PARAM_MEANING = {
  'Inlet_K_dP': '进气道总压损失修正',
  'HPC_K_W': '高压压气机流量修正',
  'HPC_K_eta': '高压压气机效率修正',
  'Burner_K_dP': '燃烧室总压损失修正',
  'GT_K_W': '燃气涡轮流量修正',
  'GT_K_eta': '燃气涡轮效率修正',
  'GT_PT_Duct_K_dP': 'GT-PT涵道总压损失修正',
  'PT_K_W': '动力涡轮流量修正',
  'PT_K_eta': '动力涡轮效率修正',
  'PT_Nozzle_Duct_K_dP': 'PT-尾喷管涵道总压损失修正',
  'Nozzle_K_A8': '尾喷管喉部面积修正',
  'Wf_bias': '燃油流量测量偏置'
};

/** 默认参数列表（10个发动机修正系数 + 1个燃油偏置 = 11个） */
const DEFAULT_PARAMS = [
  { name: 'HPC_K_W', form: '调度', unit: '无量纲', action: '曲线' },
  { name: 'HPC_K_eta', form: '调度', unit: '无量纲', action: '曲线' },
  { name: 'Burner_K_dP', form: '调度', unit: '无量纲', action: '曲线' },
  { name: 'GT_K_W', form: '调度', unit: '无量纲', action: '曲线' },
  { name: 'GT_K_eta', form: '调度', unit: '无量纲', action: '曲线' },
  { name: 'GT_PT_Duct_K_dP', form: '调度', unit: '无量纲', action: '曲线' },
  { name: 'PT_K_W', form: '调度', unit: '无量纲', action: '曲线' },
  { name: 'PT_K_eta', form: '调度', unit: '无量纲', action: '曲线' },
  { name: 'PT_Nozzle_Duct_K_dP', form: '调度', unit: '无量纲', action: '曲线' },
  { name: 'Nozzle_K_A8', form: '常值', unit: '无量纲', action: '详情' },
  { name: 'Wf_bias', form: '调度', unit: 'kg/s', action: '曲线' }
];

const OUTPUT_VARS = ['Np', 'Ng', 'Pt3', 'Tt3', 'Tt45', 'Pt45'];

/** 输出变量单位映射 */
const OUTPUT_UNITS = {
  'Np': 'rpm', 'Ng': 'rpm', 'Pt3': 'Pa', 'Tt3': 'K', 'Tt45': 'K', 'Pt45': 'Pa',
  'dNp_dt': 'rpm/s', 'dNg_dt': 'rpm/s', 'Pt2': 'Pa'
};

/** 正则化默认配置（对应 MATLAB Start_SteadyModelAdapt_V2_03/02） */
const REG_DEFAULTS = {
  transient: {
    A: { method: 'tsvd', tsvdRetained: 6, tikhonovScale: 1.00 },
    B: { method: 'tikhonov', tsvdRetained: 5, tikhonovScale: 0.75 },
    D: { method: 'tikhonov', tsvdRetained: 6, tikhonovScale: 1.00 }
  },
  steady: {
    A: { method: 'tsvd', tsvdRetained: 4, tikhonovScale: 1.00 },
    B: { method: 'tikhonov', tsvdRetained: 5, tikhonovScale: 0.50 },
    D: { method: 'tikhonov', tsvdRetained: 6, tikhonovScale: 1.00 }
  }
};

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
    this.loadingResults = new Set();
    this.resultPromises = new Map();
    this.artifacts = new Map();
    this.charts = [];
    this.timers = new Set();
    this.destroyed = false;
    this.busy = false;
    this.loading = false;
    this.loadingText = '';
    this.workspaceLoading = false;
    this.initPolling = false;
    this.initPollingText = '';
    this._scheduledPolls = new Set();

    // 状态配置
    this.identifyModel = 'transient';
    this.identifyTaskType = 'default';
    this.regConfig = JSON.parse(JSON.stringify(REG_DEFAULTS.transient));
    this.identifyErrorTab = 'training';
    this.activeSnapshot = 'pre';
    this.activeUqMethod = 'A';
    this.activeUqTab = 'training';
    this.activeUqParamTab = 'overall';
    this.uqConfig = { pilotSampleCount: 64, pilotReplicateCount: 3, formalSampleCount: 256, posteriorPredictiveSampleCount: 256, figureVisible: 'off' };
    this.activeValidTab = 'output';
    this.predictionMode = 'pressure';
    this.activePredictionModel = 'corrected';
    this._predictionPosterior = 'none';
    this.resultsFilter = 'all';
    this._activeIdentParam = null;

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
      pointId: 'PRED_PT_1',
      pamb: 101325,
      altitude: 0,
      tamb: 288.15,
      mach: 0,
      wf: 0.12,
      mkp: 1500,
      mkg: 200,
      npInitial: ''
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
      this.regConfig = JSON.parse(JSON.stringify(REG_DEFAULTS.transient));
      this._unlockIdentify = true;
      this.render();
      this.ctx.log('已恢复默认辨识配置（瞬态时刻模型），可重新配置并辨识');
    } else if (label === '生成分析报告') {
      await this.handleStartIdentifiability();
    } else if (label === '切换分析对象') {
      // 纯前端切换：在 A阶段前 / D阶段后 之间切换
      this.activeSnapshot = this.activeSnapshot === 'pre' ? 'post' : 'pre';
      this._activeIdentParam = null;
      this.render();
      const label2 = this.activeSnapshot === 'pre' ? 'A 阶段前（零修正基准）' : 'D 阶段后（最终辨识）';
      this.ctx.log(`已切换分析对象：${label2}`);
      if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast(`已切换至 ${label2}`, 'info');
    } else if (label === '评估配置') {
      this._showUqConfigModal();
    } else if (label === '开始评估') {
      await this.handleStartUq();
    } else if (label === '选择辨识结果') {
      this._autoSelectValidationInputs();
    } else if (label === '开始验证') {
      await this.handleStartValidation();
    } else if (label === '选择模型') {
      this._showPredictionModelModal();
    } else if (label === '运行预测') {
      await this.handleStartPrediction();
    } else if (label === '打开结果目录') {
      this._openResultsDirectory();
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
    if (!this.workspace || !this.ctx.http || this.workspaceLoading) return;
    this._unlockIdentify = false;
    this.workspaceLoading = true;
    try {
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
            const id = String(t.id);
            this.tasks.set(id, t);
            const phase = (t.phase || '').toLowerCase();
            const isTerminalByPhase = phase === 'completed' || phase === 'failed';
            if ((t.status === TASK_STATUS.RUNNING || t.status === TASK_STATUS.READY) && !isTerminalByPhase) {
              this.schedulePoll(id, 5000);
            } else if (t.status === TASK_STATUS.FAILED || phase === 'failed') {
              // 失败状态由 render() / _updateEnvStatus() 按当前页面输出
            }
          });
          // 根据最新辨识任务恢复模型路径选择
          const latestIdent = this.latestIdentifyTask();
          if (latestIdent) {
            if (latestIdent.actionKey === 'estimateSteady') {
              this.identifyModel = 'steady';
              this.regConfig = JSON.parse(JSON.stringify(REG_DEFAULTS.steady));
            } else if (latestIdent.actionKey === 'estimateTransient') {
              this.identifyModel = 'transient';
              this.regConfig = JSON.parse(JSON.stringify(REG_DEFAULTS.transient));
            }
          }
          // 根据最新 UQ 任务恢复评估方法选择
          const uqB = this.latestTask('uqMethodB');
          const uqA = this.latestTask('uqMethodA');
          if (uqB && (!uqA || Number(uqB.createdAt || 0) >= Number(uqA.createdAt || 0))) {
            this.activeUqMethod = 'B';
          } else if (uqA) {
            this.activeUqMethod = 'A';
          }
        }
        if (this.workspace.jobName) this.projectForm.projectName = this.workspace.jobName;
        if (this.workspace.programName) this.projectForm.modelPackage = this.workspace.programName;
        if (this.workspace.trainingDataFile) this.projectForm.trainingData = this.workspace.trainingDataFile;
        if (this.workspace.testDataFile) this.projectForm.testData = this.workspace.testDataFile;
        this.projectForm.notes = this.workspace.notes || '';
        if (this.workspace.initStatus === 'SUCCEEDED') {
          // 从 IGINX 实体表查询测量数据行和调度变量行（初始化时已存储，无需再读 Excel）
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
          // 测试数据仅记录文件名，不重新解析 Excel（打开项目时无需重复预览）
          this.preview.test = null;
        } else if (this.workspace.trainingDataFile) {
          await this.loadPreview(this.workspace.trainingDataFile, 'training');
        }
      } catch (e) {
        console.warn('刷新工作区详情失败:', e);
      }
    });
    } finally {
      this.workspaceLoading = false;
    }
  }

  async loadTaskResult(taskId) {
    if (!this.ctx.http || !this.ctx.http.results) return null;
    const key = String(taskId);
    if (this.results.has(key)) return this.results.get(key);
    if (this.resultPromises.has(key)) return this.resultPromises.get(key);
    const promise = (async () => {
      this.loadingResults.add(key);
      try {
        const [res, artifacts] = await Promise.all([
          this.ctx.http.results.get(key),
          this.ctx.http.artifacts.request(key, { method: 'GET' }).catch(() => null)
        ]);
        if (res) {
          this.results.set(key, res.value !== undefined ? res.value : res);
          if (Array.isArray(artifacts)) this.artifacts.set(key, artifacts);
          this.render();
          return this.results.get(key);
        }
        return null;
      } catch (e) {
        console.warn('读取任务结果失败:', key, e);
        return null;
      } finally {
        this.loadingResults.delete(key);
        this.resultPromises.delete(key);
        // 如果是 _ensureResult 触发的 loading，所有结果加载完后清除
        if (this.loading && this.loadingResults.size === 0 && this.loadingText === '正在加载结果...') {
          this.loading = false;
          this.loadingText = '';
          this.render();
        }
      }
    })();
    this.resultPromises.set(key, promise);
    return promise;
  }

  schedulePoll(taskId, delay = 5000) {
    const key = String(taskId);
    if (this.destroyed || this._scheduledPolls.has(key)) return;
    this._scheduledPolls.add(key);
    const timer = setTimeout(async () => {
      this.timers.delete(timer);
      try {
        const task = await this.ctx.http.tasks.get(key);
        if (task) {
          this.tasks.set(String(task.id), task);
          const phase = (task.phase || '').toLowerCase();
          // 判断当前任务是否属于当前页面，只在对应页面才 render
          const taskSection = this._sectionForActionKey(task.actionKey);
          const shouldRender = taskSection === this.activeSection || this.activeSection === 'results';
          if (task.status === TASK_STATUS.COMPLETED || phase === 'completed') {
            this._scheduledPolls.delete(key);
            if (this._uqLogCallback && task.logLine) this._uqLogCallback(task.logLine, task);
            await this.loadTaskResult(key);
            if (shouldRender) this.render();
          } else if (task.status === TASK_STATUS.FAILED || phase === 'failed') {
            this._scheduledPolls.delete(key);
            if (this._uqLogCallback && task.logLine) this._uqLogCallback(task.logLine, task);
            if (shouldRender) this.render();
            if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('任务失败: ' + (task.error || ''), 'error');
          } else if (task.status === TASK_STATUS.SKIPPED) {
            this._scheduledPolls.delete(key);
            if (shouldRender) this.render();
            if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('任务已跳过: ' + (task.error || ''), 'info');
          } else if (task.status === TASK_STATUS.CANCELLING) {
            this._scheduledPolls.delete(key);
            if (shouldRender) this.render();
          } else {
            this._scheduledPolls.delete(key);
            this.schedulePoll(key, 5000);
            // 通知打开的日志弹窗追加新日志
            if (this._uqLogCallback && (task.logLine || task.progressMessage)) {
              this._uqLogCallback(task.logLine || task.progressMessage, task);
            }
            if (shouldRender) this.render();
          }
        }
      } catch (e) {
        this._scheduledPolls.delete(key);
        if (!this.destroyed) this.schedulePoll(key, 10000);
      }
    }, delay);
    this.timers.add(timer);
  }

  latestTask(actionKey) {
    return Array.from(this.tasks.values())
      .filter(t => t.actionKey === actionKey)
      .sort((a, b) => Number(b.createdAt || 0) - Number(a.createdAt || 0))[0];
  }

  /** 取 estimateTransient / estimateSteady 中 createdAt 最大的任务 */
  latestIdentifyTask() {
    const t = this.latestTask('estimateTransient');
    const s = this.latestTask('estimateSteady');
    if (!t) return s || null;
    if (!s) return t;
    return Number(t.createdAt || 0) >= Number(s.createdAt || 0) ? t : s;
  }

  latestResult(actionKey) {
    const task = this.latestTask(actionKey);
    return task ? this.results.get(String(task.id)) : null;
  }

  /** 取最新辨识任务对应的结果 */
  latestIdentifyResult() {
    const task = this.latestIdentifyTask();
    return task ? this.results.get(String(task.id)) : null;
  }

  /* 按需加载指定 actionKey 的最新任务结果 */
  _ensureResult(actionKey) {
    const task = this.latestTask(actionKey);
    if (!task) return;
    const id = String(task.id);
    if (this.results.has(id) || this.resultPromises.has(id)) return;
    // 任务未完成时不请求结果，避免后端 WARN 刷屏
    const phase = (task.phase || '').toLowerCase();
    if (task.status !== TASK_STATUS.COMPLETED && phase !== 'completed') return;
    // 标记 loading 状态，让 render() 显示加载覆盖层
    if (!this.loading && !this.loadingResults.size) {
      this.loading = true;
      this.loadingText = '正在加载结果...';
    }
    this.loadTaskResult(id);
  }

  /* 根据 actionKey 反查所属 section */
  _sectionForActionKey(actionKey) {
    const map = {
      estimateTransient: 'identify',
      estimateSteady: 'identify',
      engineeringIdentifiability: 'identifiability',
      uqMethodA: 'uq',
      uqMethodB: 'uq',
      uqRuntimeEstimateA: 'uq',
      uqRuntimeEstimateB: 'uq',
      testValidation: 'validation',
      operatingPointPrediction: 'prediction'
    };
    return map[actionKey] || null;
  }

  /* 根据当前 section 按需加载所需结果 */
  _ensureResultsForSection(section) {
    const map = {
      identify: ['estimateTransient', 'estimateSteady'],
      identifiability: ['engineeringIdentifiability'],
      uq: ['uqMethodA', 'uqMethodB'],
      validation: ['testValidation'],
      prediction: ['operatingPointPrediction'],
      results: ['estimateTransient', 'estimateSteady', 'engineeringIdentifiability',
                'uqMethodA', 'uqMethodB', 'testValidation', 'operatingPointPrediction']
    };
    (map[section] || []).forEach(action => this._ensureResult(action));
  }

  /* 按当前 section 取对应任务 */
  _taskForSection(section) {
    if (section === 'data') return null;
    if (section === 'identify') return this.latestIdentifyTask();
    if (section === 'identifiability') return this.latestTask('engineeringIdentifiability');
    if (section === 'uq') return this.activeUqMethod === 'B' ? this.latestTask('uqMethodB') : this.latestTask('uqMethodA');
    if (section === 'validation') return this.latestTask('testValidation');
    if (section === 'prediction') return this.latestTask('operatingPointPrediction');
    if (section === 'results') {
      const all = ['estimateTransient', 'estimateSteady', 'engineeringIdentifiability',
                   'uqMethodA', 'uqMethodB', 'testValidation', 'operatingPointPrediction'];
      return all.map(k => this.latestTask(k))
        .filter(Boolean)
        .sort((a, b) => Number(b.createdAt || 0) - Number(a.createdAt || 0))[0];
    }
    return null;
  }

  /* 根据当前 section 刷新左下角状态 / 日志 */
  _updateEnvStatus(section) {
    if (!this.ctx.setStatus) return;
    if (section === 'data' && this.initPolling) {
      this.ctx.setStatus('busy', 'MATLAB 初始化中');
      this.ctx.log('MATLAB 初始化进行中');
      return;
    }
    const task = this._taskForSection(section);
    if (!task) {
      this.ctx.setStatus('ready', '计算环境就绪');
      this.ctx.log('项目数据已加载');
      return;
    }
    const status = task.status;
    const phase = (task.phase || '').toLowerCase();
    const logLine = task.logLine;
    if (status === TASK_STATUS.COMPLETED || phase === 'completed') {
      this.ctx.setStatus('ready', '任务已完成');
      this.ctx.log(logLine || `任务 ${task.id} 已完成`);
    } else if (status === TASK_STATUS.FAILED || phase === 'failed') {
      this.ctx.setStatus('error', '计算失败');
      this.ctx.log(logLine || `任务 ${task.id} 失败: ${task.error || '未知错误'}`);
    } else if (status === TASK_STATUS.CANCELLING) {
      this.ctx.setStatus('busy', '任务取消中');
      this.ctx.log(logLine || `任务 ${task.id} 取消中...`);
    } else if (status === TASK_STATUS.SKIPPED) {
      this.ctx.setStatus('ready', '任务已跳过');
      this.ctx.log(logLine || `任务 ${task.id} 已跳过`);
    } else if (status === TASK_STATUS.READY) {
      this.ctx.setStatus('busy', '排队等待中');
      this.ctx.log('任务已提交，等待前序任务完成后自动开始');
    } else if (status === TASK_STATUS.RUNNING) {
      this.ctx.setStatus('running', '任务运行中');
      this.ctx.log(logLine || task.progressMessage || '任务运行中');
    } else {
      this.ctx.setStatus('ready', '计算环境就绪');
      this.ctx.log('项目数据已加载');
    }
  }

  /* 把秒数格式化为易读的中文时长 */
  _formatDuration(totalSeconds) {
    if (totalSeconds == null || isNaN(totalSeconds)) return '—';
    const s = Number(totalSeconds);
    if (s < 60) return `${s.toFixed(1)} 秒`;
    if (s < 3600) {
      const m = Math.floor(s / 60);
      const rem = s % 60;
      return rem >= 1 ? `${m}分 ${rem.toFixed(1)}秒` : `${m}分`;
    }
    if (s < 86400) {
      const h = Math.floor(s / 3600);
      const m = Math.floor((s % 3600) / 60);
      return m > 0 ? `${h}小时 ${m}分` : `${h}小时`;
    }
    const d = Math.floor(s / 86400);
    const h = Math.floor((s % 86400) / 3600);
    return h > 0 ? `${d}天 ${h}小时` : `${d}天`;
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
    this._ensureResultsForSection(this.activeSection);
    this._updateEnvStatus(this.activeSection);
    this.disposeCharts();
    this.mount.replaceChildren();

    const view = el('div', 'section-view');
    view.style.position = 'relative';
    this.mount.append(view);
    const renderer = this['render_' + this.activeSection];
    if (renderer) {
      renderer.call(this, view);
    } else {
      this.render_data(view);
    }
    // 图表渲染后统一 resize，确保尺寸正确
    this.charts.forEach(c => { try { c.resize(); } catch (e) {} });

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
  }

  /* ================= 01 项目与数据 ================= */
  render_data(container) {
    const initStatus = (this.workspace && this.workspace.initStatus) || '';
    const failed = initStatus === 'FAILED' || initStatus === 'FALLBACK';
    const validated = this.projectCreated && !this.initPolling && initStatus === 'SUCCEEDED';
    const statusText = this.initPolling ? '校验中' : (failed ? '校验失败' : (validated ? '已校验' : '待校验'));
    const statusClass = this.initPolling ? 'field-status pending' : (failed ? 'field-status failed' : (validated ? 'field-status validated' : 'field-status pending'));

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

    // 第二行：备注 + 保存目录（同一行，各占两列）
    const form2 = el('div', 'form-grid-4');
    form2.style.marginTop = '12px';
    const notesField = el('div', 'form-field');
    notesField.style.gridColumn = '1 / span 2';
    notesField.append(el('label', '', '备注'));
    notesField.append(notesInput);
    form2.append(notesField);

    // 项目创建后，在备注右侧显示保存目录
    if (this.projectCreated && this.workspace && this.workspace.workspaceDir) {
      const dirField = el('div', 'form-field');
      dirField.style.gridColumn = '3 / span 2';
      const dirLabel = el('label', '', '保存目录');
      const dirValue = el('div', '');
      dirValue.style.cssText = 'padding:6px 8px;background:#f5f7fa;border:1px solid #e8eaed;border-radius:3px;font-size:11px;color:#5a6a7a;word-break:break-all;font-family:Consolas,monospace;line-height:1.5;';
      dirValue.textContent = this.workspace.workspaceDir;
      dirField.append(dirLabel, dirValue);
      form2.append(dirField);
    }

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
      c2.body.append(this.createLoadingPlaceholder('正在校验测量数据...'));
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
      c3.body.append(this.createLoadingPlaceholder('正在计算调度分组...'));
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

  /* 当前是否存在非失败的辨识任务（即配置已锁定） */
  _isIdentifyLocked() {
    const identifyTask = this.latestIdentifyTask();
    return identifyTask != null && identifyTask.status !== TASK_STATUS.FAILED;
  }

  /* ================= 02 参数辨识 ================= */
  render_identify(container) {
    const identifyTask = this.latestIdentifyTask();
    const identifyResult = this.latestIdentifyResult();
    const isRunning = identifyTask?.status === TASK_STATUS.RUNNING || identifyTask?.status === TASK_STATUS.READY;
    const isFailed = identifyTask?.status === TASK_STATUS.FAILED;
    const isLocked = (identifyTask != null && !isFailed) && !this._unlockIdentify;
    const taskStatus = identifyTask?.status;

    // 从 resultSummary 中提取 MATLAB 返回结构
    const summary = identifyResult?.resultSummary || identifyResult || {};
    const acceptance = summary.acceptance || {};
    const timing = summary.timing || {};
    const outputInfo = summary.output || {};
    const paramTable = summary.parameterTable;
    const baselineMetrics = summary.baseline?.trainingMetrics;
    const finalMetrics = summary.final?.trainingMetrics;
    const baselineTestMetrics = summary.baseline?.testMetrics;
    const finalTestMetrics = summary.final?.testMetrics;

    // ---- Card 1: 辨识任务与正则化配置 ----
    const c1 = this.createCard(
      '辨识任务与正则化配置',
      '路径切换后自动载入该路径的默认 TSVD/Tikhonov 配置，A/B/D 阶段均可独立修改。'
    );
    // 模型路径
    const pathRow = el('div', 'reg-path-row');
    pathRow.append(el('span', 'reg-label', '模型路径'));
    const pathSeg = el('div', 'segmented');
    const seg1 = button('瞬态时刻模型', 'segment' + (this.identifyModel === 'transient' ? ' active' : ''), () => {
      this.identifyModel = 'transient';
      this.regConfig = JSON.parse(JSON.stringify(REG_DEFAULTS.transient));
      this.render();
    });
    const seg2 = button('稳态模型', 'segment' + (this.identifyModel === 'steady' ? ' active' : ''), () => {
      this.identifyModel = 'steady';
      this.regConfig = JSON.parse(JSON.stringify(REG_DEFAULTS.steady));
      this.render();
    });
    pathSeg.append(seg1, seg2);
    pathRow.append(pathSeg);
    const defaultTag = el('span', 'field-status optional', '默认辨识任务');
    defaultTag.style.marginLeft = 'auto';
    pathRow.append(defaultTag);
    seg1.disabled = isLocked; seg2.disabled = isLocked;
    if (isLocked) { seg1.classList.add('disabled'); seg2.classList.add('disabled'); }
    c1.body.append(pathRow);

    // A/B/D 正则化配置卡片
    const mGrid = el('div', 'method-grid');
    const STAGE_LABELS = { A: '全工况常值', B: '分组估计', D: '全工况微调' };
    ['A', 'B', 'D'].forEach(stage => {
      const cfg = this.regConfig[stage];
      const stageLabel = stage + ' ' + STAGE_LABELS[stage];
      const card = el('div', 'method-card reg-card');
      card.append(el('div', 'method-badge', stage));
      const info = el('div', 'method-info');
      info.append(el('h4', 'method-title', stageLabel));

      // 方法选择
      const methodRow = el('div', 'reg-method-row');
      const tsvdBtn = button('无阻尼TSVD', 'segment' + (cfg.method === 'tsvd' ? ' active' : ''), () => {
        cfg.method = 'tsvd';
        this.render();
      });
      const tikhBtn = button('Tikhonov', 'segment' + (cfg.method === 'tikhonov' ? ' active' : ''), () => {
        cfg.method = 'tikhonov';
        this.render();
      });
      tsvdBtn.disabled = isLocked; tikhBtn.disabled = isLocked;
      if (isLocked) { tsvdBtn.classList.add('disabled'); tikhBtn.classList.add('disabled'); }
      methodRow.append(el('span', 'reg-label', '方法'), tsvdBtn, tikhBtn);
      info.append(methodRow);

      // 参数输入
      const paramRow = el('div', 'reg-param-row');
      if (cfg.method === 'tsvd') {
        paramRow.append(el('span', 'reg-label', '保留奇异方向 r ='));
        const input = el('input', 'reg-input');
        input.type = 'number';
        input.min = '1';
        input.max = '20';
        input.value = cfg.tsvdRetained;
        input.disabled = isLocked;
        input.addEventListener('change', () => {
          const v = parseInt(input.value, 10);
          if (v >= 1) { cfg.tsvdRetained = v; }
        });
        paramRow.append(input);
      } else {
        paramRow.append(el('span', 'reg-label', '正则化尺度 s ='));
        const input = el('input', 'reg-input');
        input.type = 'number';
        input.min = '0.01';
        input.step = '0.05';
        input.value = cfg.tikhonovScale;
        input.disabled = isLocked;
        input.addEventListener('change', () => {
          const v = parseFloat(input.value);
          if (v > 0) { cfg.tikhonovScale = v; }
        });
        paramRow.append(input);
      }
      info.append(paramRow);

      // 底部提示
      const footText = isLocked ? '已锁定，运行结果按此配置生成。' : '可在评估前修改，运行后锁定并写入结果记录。';
      info.append(el('p', 'method-foot', footText));
      card.append(info);
      mGrid.append(card);
    });
    c1.body.append(mGrid);

    // ---- Card 2: 辨识流程 ----
    const c2 = this.createCard(
      '辨识流程',
      'A/B/C/D 是连续执行阶段，只需启动一次辨识任务。流程条显示各阶段状态。'
    );
    const flow = el('div', 'flow-line');
    const phase = identifyTask?.phase;
    // 解锁重新配置时，不显示旧任务的阶段状态
    const showStageProgress = !this._unlockIdentify;
    const stageStates = showStageProgress
      ? this._getStageStates(acceptance, isRunning, isFailed, taskStatus, phase)
      : { A: { state: 'pending', label: '待执行' }, B: { state: 'pending', label: '待执行' },
          C: { state: 'pending', label: '待执行' }, D: { state: 'pending', label: '待执行' } };
    flow.append(
      this.createFlowStep('A', 'A 全工况常值', stageStates.A.label, stageStates.A.state, () => this._showStageLog('A')),
      this.createFlowStep('B', 'B 分组估计', stageStates.B.label, stageStates.B.state, () => this._showStageLog('B')),
      this.createFlowStep('C', 'C 调度重构', stageStates.C.label, stageStates.C.state, () => this._showStageLog('C')),
      this.createFlowStep('D', 'D 全工况微调', stageStates.D.label, stageStates.D.state, () => this._showStageLog('D'))
    );
    c2.body.append(flow);

    // ---- Card 3: 修正系数辨识结果 ----
    const c3 = this.createCard(
      '修正系数辨识结果',
      '表内同时显示设计点值和节点均值；曲线按钮打开该参数完整调度曲线。'
    );
    c3.body.append(this._renderParamTable(paramTable, identifyResult));

    // ---- Card 4: 输出误差标准差与计算时间 ----
    const c4 = this.createCard(
      '输出误差标准差与计算时间',
      '修正前后误差直接对照；曲线按钮查看逐工况误差。运行完成后显示总耗时。'
    );
    c4.body.append(this._renderErrorTable(baselineMetrics, finalMetrics, baselineTestMetrics, finalTestMetrics, identifyResult));

    // 运行状态与结果信息合并到 Card 4
    const statusGrid = el('div', 'metrics-grid');
    statusGrid.style.marginTop = '12px';
    const totalSeconds = timing.estimationSeconds || identifyResult?.runtime_s;
    const runtimeText = totalSeconds != null
      ? this._formatDuration(totalSeconds)
      : (isRunning ? '正在运行...' : '待运行');
    statusGrid.append(this.createMetricBox('总计算时间', runtimeText));

    const convergeText = acceptance.allStagesConverged === true
      ? 'A/B/D 全部收敛'
      : acceptance.allStagesConverged === false
        ? `A:${acceptance.stageAConverged ? '✓' : '✗'} B:${acceptance.stageBAllConverged ? '✓' : '✗'} D:${acceptance.stageDConverged ? '✓' : '✗'}`
        : '待运行';
    statusGrid.append(this.createMetricBox('收敛状态', convergeText));

    const maxResidual = finalMetrics?.max_model_residual;
    statusGrid.append(this.createMetricBox('最大共同工作残差', maxResidual != null ? Number(maxResidual).toExponential(3) : '待运行'));

    const formalText = acceptance.formalAccepted === true ? '正式验收通过' : acceptance.formalAccepted === false ? '未通过' : '待运行';
    statusGrid.append(this.createMetricBox('正式验收状态', formalText));

    c4.body.append(statusGrid);

    // 结果文件位置（放在左侧卡片 c3 中，路径较长需要更宽的显示区域）
    const figs = Array.isArray(outputInfo.figureFiles) ? outputInfo.figureFiles : (outputInfo.figureFiles ? [outputInfo.figureFiles] : []);
    if (outputInfo.latestMatFile || outputInfo.excelFile || outputInfo.summaryFile || figs.length) {
      const fileList = el('div', 'file-list');
      fileList.style.marginTop = '12px';
      fileList.append(el('div', 'metric-label', '结果文件位置'));
      if (outputInfo.latestMatFile) fileList.append(el('div', 'file-item', `MAT: ${outputInfo.latestMatFile}`));
      if (outputInfo.excelFile) fileList.append(el('div', 'file-item', `Excel: ${outputInfo.excelFile}`));
      if (outputInfo.summaryFile) fileList.append(el('div', 'file-item', `摘要: ${outputInfo.summaryFile}`));
      if (figs.length) {
        figs.forEach(f => {
          const item = el('div', 'file-item');
          item.textContent = `PNG: ${f}`;
          item.style.color = 'var(--blue, #1890ff)';
          item.style.cursor = 'pointer';
          item.onclick = () => this._viewArtifact(String(f).split(/[\\/]/).pop(), '图片预览');
          fileList.append(item);
        });
      }
      c3.body.append(fileList);
    }

    const resultRow = el('div', 'two-col-row');
    resultRow.append(c3.card, c4.card);
    container.append(c1.card, c2.card, resultRow);
  }

  /** 获取 A/B/C/D 各阶段状态 */
  _getStageStates(acceptance, isRunning, isFailed, taskStatus, phase) {
    if (isFailed) {
      return {
        A: { state: 'failed', label: '失败' },
        B: { state: 'pending', label: '待执行' },
        C: { state: 'pending', label: '待执行' },
        D: { state: 'pending', label: '待执行' }
      };
    }
    if (isRunning) {
      const p = String(phase || '').toUpperCase();
      const stages = ['A', 'B', 'C', 'D'];
      if (stages.includes(p)) {
        const result = {};
        const idx = stages.indexOf(p);
        stages.forEach((s, i) => {
          if (i < idx) result[s] = { state: 'completed', label: '完成' };
          else if (i === idx) result[s] = { state: 'running', label: '运行中' };
          else result[s] = { state: 'pending', label: '待执行' };
        });
        return result;
      }
      // 无阶段进度时按串行语义显示 A 运行中
      return {
        A: { state: 'running', label: '运行中' },
        B: { state: 'pending', label: '待执行' },
        C: { state: 'pending', label: '待执行' },
        D: { state: 'pending', label: '待执行' }
      };
    }
    if (acceptance && acceptance.allStagesConverged !== undefined) {
      return {
        A: { state: acceptance.stageAConverged ? 'completed' : 'warning', label: acceptance.stageAConverged ? '完成' : '警告' },
        B: { state: acceptance.stageBAllConverged ? 'completed' : 'warning', label: acceptance.stageBAllConverged ? '完成' : '警告' },
        C: { state: acceptance.stageAConverged && acceptance.stageBAllConverged ? 'completed' : 'warning', label: acceptance.stageAConverged && acceptance.stageBAllConverged ? '完成' : '警告' },
        D: { state: acceptance.stageDConverged ? 'completed' : 'warning', label: acceptance.stageDConverged ? '完成' : '警告' }
      };
    }
    return {
      A: { state: 'pending', label: '待执行' },
      B: { state: 'pending', label: '待执行' },
      C: { state: 'pending', label: '待执行' },
      D: { state: 'pending', label: '待执行' }
    };
  }

  /** 渲染修正系数结果表 */
  _renderParamTable(paramTable, identifyResult) {
    const paramHeaders = ['修正系数', '物理含义', '形式', '设计点值', '节点均值', '单位', '查看'];
    let paramRows;

    if (paramTable && Array.isArray(paramTable.rows) && paramTable.rows.length > 0) {
      paramRows = paramTable.rows.map(row => {
        const name = row.name || '—';
        const isScheduled = row.scheduled === true || row.scheduled === 1;
        const designVal = row.final_design_value != null ? Number(row.final_design_value).toFixed(4) : '—';
        const meanVal = row.group_mean != null ? Number(row.group_mean).toFixed(4) : '—';
        const unit = (name === 'Wf_bias') ? 'kg/s' : '无量纲';
        return [
          name,
          PARAM_MEANING[name] || '—',
          isScheduled ? '调度' : '常值',
          designVal,
          meanVal,
          unit,
          button(isScheduled ? '曲线' : '详情', 'btn-table', () => this._viewParamCurve(name))
        ];
      });
    } else {
      paramRows = DEFAULT_PARAMS.map(p => [
        p.name,
        PARAM_MEANING[p.name] || '—',
        p.form,
        '待运行',
        '待运行',
        p.unit,
        button(p.action, 'btn-table', () => this._viewParamCurve(p.name))
      ]);
    }
    return this.createTable(paramHeaders, paramRows);
  }

  /** 渲染输出误差表（训练集） */
  _renderErrorTable(baselineMetrics, finalMetrics, baselineTestMetrics, finalTestMetrics, identifyResult) {
    const wrap = el('div');

    const baseMetrics = baselineMetrics;
    const finMetrics = finalMetrics;

    const errHeaders = ['输出', '修正前标准差', '修正后标准差', '查看'];
    const baselineByField = this._metricsByFieldMap(baseMetrics);
    const finalByField = this._metricsByFieldMap(finMetrics);

    // 从实际数据中动态提取输出变量列表（瞬态时刻模型用 dNp_dt/dNg_dt，稳态模型用 Np/Ng）
    const allFields = Object.keys(baselineByField).length > 0
      ? Object.keys(baselineByField)
      : Object.keys(finalByField);
    // 优先按 OUTPUT_VARS 顺序排列，再追加未列出的
    const orderedFields = [
      ...OUTPUT_VARS.filter(o => allFields.includes(o)),
      ...allFields.filter(o => !OUTPUT_VARS.includes(o))
    ];

    const errRows = orderedFields.map(o => {
      const base = baselineByField[o] || {};
      const fin = finalByField[o] || {};
      return [
        o,
        base.rmse != null ? Number(base.rmse).toFixed(3) : '—',
        fin.rmse != null ? Number(fin.rmse).toFixed(3) : '—',
        button('曲线', 'btn-table', () => this._viewErrorCurve(o))
      ];
    });

    // 无数据时显示待运行占位
    if (errRows.length === 0) {
      OUTPUT_VARS.forEach(o => {
        errRows.push([o, '待运行', '待运行', button('曲线', 'btn-table', () => this._viewErrorCurve(o))]);
      });
    }

    wrap.append(this.createTable(errHeaders, errRows));

    return wrap;
  }

  /** 将 metrics.byField 转为 { fieldName: row } 映射 */
  _metricsByFieldMap(metrics) {
    const map = {};
    if (!metrics || !metrics.byField) return map;
    const byField = metrics.byField;
    if (Array.isArray(byField.rows)) {
      byField.rows.forEach(row => {
        const name = row.field || row.Field;
        if (name) map[name] = row;
      });
    }
    return map;
  }

  /* ================= 03 可辨识性 ================= */
  render_identifiability(container) {
    const identTask = this.latestTask('engineeringIdentifiability');
    const identResult = this.latestResult('engineeringIdentifiability');
    const isRunning = identTask?.status === TASK_STATUS.RUNNING || identTask?.status === TASK_STATUS.READY;
    const summary = identResult?.resultSummary || identResult || {};
    const ph = isRunning ? '运行中...' : '运行后显示';
    const routeName = this.identifyModel === 'steady' ? 'steady' : 'transient_instant';
    const snapshotName = this.activeSnapshot === 'pre' ? 'baseline_before_A' : 'final_after_D';

    // 从 conditionSummary 中找到当前 route+snapshot 的行
    const condRows = (summary.conditionSummary?.rows || []).filter(r => r.route === routeName && r.snapshot === snapshotName);
    const cond = condRows[0] || null;

    // 从 combinedParameterSummary 中取当前 route 的参数分类
    const combinedRows = (summary.combinedParameterSummary?.rows || []).filter(r => r.route === routeName);

    // 从 directionDetail 中取当前 route+snapshot 的方向分析
    const dirRows = (summary.directionDetail?.rows || []).filter(r => r.route === routeName && r.snapshot === snapshotName);

    // 从 svdSpectrum 中取当前 route+snapshot 的 SVD 谱
    const svdRows = (summary.svdSpectrum?.rows || []).filter(r => r.route === routeName && r.snapshot === snapshotName);

    // 从 weakDirectionTable 中取当前 route+snapshot 的弱方向
    const weakRows = (summary.weakDirectionTable?.rows || []).filter(r => r.route === routeName && r.snapshot === snapshotName);

    // Card 1: 分析对象
    const c1 = this.createCard(
      '分析对象',
      '同时切换和展示两个位置下（A 阶段前 / D 阶段后）的辨识结果进行综合判断。'
    );
    const seg1 = el('div', 'segmented');
    const b1 = button('瞬态时刻模型', 'segment' + (this.identifyModel === 'transient' ? ' active' : ''), () => {
      this.identifyModel = 'transient';
      this.render();
    });
    const b2 = button('稳态模型', 'segment' + (this.identifyModel === 'steady' ? ' active' : ''), () => {
      this.identifyModel = 'steady';
      this.render();
    });
    seg1.append(b1, b2);

    const seg2 = el('div', 'segmented');
    const b3 = button('A 阶段前', 'segment' + (this.activeSnapshot === 'pre' ? ' active' : ''), () => {
      this.activeSnapshot = 'pre';
      this.render();
    });
    const b4 = button('D 阶段后', 'segment' + (this.activeSnapshot === 'post' ? ' active' : ''), () => {
      this.activeSnapshot = 'post';
      this.render();
    });
    seg2.append(b3, b4);

    const tag = el('span', 'field-status optional', '局部线性分析，不等于全局唯一性');
    const segRow = el('div', 'reg-method-row');
    segRow.append(seg1, seg2, tag);
    c1.body.append(segRow);

    // Card 2: 整体信息质量（文档 7.2：条件数、有效奇异方向数、正则化后条件状态、观测数、待分析参数数）
    const c2 = this.createCard(
      '整体信息质量',
      '显示标准化信息矩阵条件数、有效奇异方向数、TSVD/Tikhonov 作用后的有效条件状态、观测数和待分析参数数。'
    );
    const fmtCond = v => {
      if (v == null) return '—';
      const n = Number(v);
      if (!isFinite(n)) return '—';
      if (n >= 1e6) return n.toLocaleString('zh-CN', { maximumFractionDigits: 1 });
      if (n >= 100) return n.toFixed(1);
      return n.toFixed(3);
    };
    const fmtRegularized = (c) => {
      if (!c) return ph;
      const condStr = fmtCond(c.active_regularized_information_condition);
      const method = c.active_regularization_method || '—';
      return `${condStr} (${method})`;
    };
    const qGrid = el('div', 'metrics-grid');
    qGrid.append(
      this.createMetricBox('标准化信息矩阵条件数', cond ? fmtCond(cond.information_condition) : ph),
      this.createMetricBox('有效奇异方向数', cond ? String(cond.effective_rank) : ph),
      this.createMetricBox('TSVD/Tikhonov 作用后条件数', cond ? fmtRegularized(cond) : ph),
      this.createMetricBox('观测数', cond ? String(cond.data_residual_count) : ph),
      this.createMetricBox('待分析参数数', cond ? String(cond.parameter_count) : ph)
    );
    if (isRunning) {
      const loading = el('div', 'chart-loading');
      loading.style.cssText = 'height:160px;display:flex;align-items:center;justify-content:center;';
      const spinner = el('div', 'chart-spinner');
      const text = el('span', '', '可辨识性分析中...');
      loading.append(spinner, text);
      c2.body.append(loading);
    } else {
      c2.body.append(qGrid);
      // 数值证据：奇异谱和正则化作用曲线不作为页面主结论，以详情链接提供
      if (cond) {
        const note = el('p', 'card-foot-note');
        note.textContent = '奇异谱和正则化作用曲线不作为页面主结论，详见 ';
        const numLink = el('a', '', '数值证据详情');
        numLink.href = '#';
        numLink.style.cssText = 'font-size:12px;color:var(--blue);text-decoration:underline;cursor:pointer;';
        numLink.addEventListener('click', (e) => {
          e.preventDefault();
          this._showNumericalEvidenceModal(cond, svdRows, weakRows);
        });
        note.append(numLink);
        c2.body.append(note);
      }
    }

    // Card 3: 逐参数结果（文档 7.3：参数、自身敏感性、补偿依赖、主要补偿参数、基准位置分类、辨识结果位置分类、综合判断与建议）
    const c3 = this.createCard(
      '逐参数结果',
      '每个参数在同一张表中只出现一次。选中依赖补偿参数后点击"查看"显示补偿详情。'
    );
    const idHeaders = ['参数', '自身敏感性', '补偿依赖', '主要补偿参数', '基准位置分类', '辨识结果位置分类', '综合判断与建议', ''];
    const idRows = combinedRows.map(r => {
      const param = r.parameter;
      const domComp = this._findDominantCompanion(dirRows, param);
      const baseClass = r.baseline_class || '—';
      const finalClass = r.final_class || '—';
      // 自身敏感性：从孤立 RMS 量级判断
      const isoRms = r.baseline_isolated_rms;
      const sensitivity = isoRms != null
        ? (isoRms > 1.0 ? '高敏感' : isoRms > 0.1 ? '中敏感' : '低敏感')
        : '—';
      // 补偿依赖程度
      const compDep = (baseClass === '依赖其他参数补偿' || finalClass === '依赖其他参数补偿') ? '依赖补偿' : '独立';
      // 主要补偿参数
      const mainComp = (domComp && domComp.dominant_companion && domComp.dominant_companion !== 'none')
        ? domComp.dominant_companion : '—';
      // 综合判断与建议
      let advice = '保留为独立调度项';
      const cls = finalClass !== '—' ? finalClass : baseClass;
      if (cls === '参数自身低敏感') advice = '可考虑固定或增加工况激励';
      else if (cls === '依赖其他参数补偿') advice = '增强先验约束或增加激励';
      else if (cls === '参数边界受限') advice = '放宽边界或增加工况覆盖';
      return [
        param,
        sensitivity,
        compDep,
        mainComp,
        baseClass,
        finalClass,
        advice,
        button('查看', 'btn-table', () => {
          this._activeIdentParam = param;
          this.render();
          setTimeout(() => {
            const host = this.ctx.shadow || this.mount;
            const target = host.querySelector('#ident-evidence-detail');
            if (target) target.scrollIntoView({ behavior: 'smooth', block: 'start' });
          }, 0);
        })
      ];
    });
    if (idRows.length === 0) {
      DEFAULT_PARAMS.forEach(p => {
        idRows.push([p.name, '—', '—', '—', '运行后显示', '运行后显示', '—', button('查看', 'btn-table', () => {})]);
      });
    }
    c3.body.append(this.createTable(idHeaders, idRows));

    // Card 4: 所选参数证据详情（三个证据卡片网格布局）
    const c4 = this.createCard(
      '所选参数证据详情',
      '点击表格行后在本页展开，避免与逐参数分类表重复。'
    );
    const eGrid = el('div', 'evidence-grid');
    // 根据是否有结果生成证据描述
    const hasResult = !!identResult;
    const selParam = this._activeIdentParam;
    const selCombined = selParam ? combinedRows.find(r => r.parameter === selParam) : null;
    const selDomComp = selParam ? this._findDominantCompanion(dirRows, selParam) : null;
    const selDirs = selParam ? dirRows.filter(d => d.target_parameter === selParam) : [];

    // 自身敏感性证据
    let sensDesc;
    if (hasResult && selParam && selDirs.length > 0) {
      const isoRms = selCombined?.baseline_isolated_rms;
      const domField = selDirs[0]?.isolated_dominant_field || '—';
      sensDesc = `孤立扰动 ±1% 主导输出 ${domField}，RMS 量级 ${isoRms != null ? Number(isoRms).toFixed(4) : '—'}`;
    } else if (hasResult) {
      sensDesc = '请在上方表格中点击"查看"选择参数后显示自身敏感性证据';
    } else {
      sensDesc = '孤立工程扰动、主导输出及响应量级动态显示';
    }
    eGrid.append(this.createEvidenceBox('自身敏感性证据', sensDesc, 'blue'));

    // 补偿关系证据：以表格形式展示文档 7.3 要求的 5 个详情字段
    let compEvidence;
    const snapshotLabel = this.activeSnapshot === 'pre' ? 'A 阶段前（零修正基准）' : 'D 阶段后（稳态辨识模型）';
    if (hasResult && selParam && selDomComp && selDomComp.dominant_companion && selDomComp.dominant_companion !== 'none') {
      const compDir = Number(selDomComp.dominant_companion_delta) >= 0 ? '同向' : '反向';
      const frac = Number(selDomComp.dominant_companion_step_fraction).toFixed(2);
      const compRows = [
        ['主要补偿参数', selDomComp.dominant_companion],
        ['补偿方向', `${compDir}（Δ=${Number(selDomComp.dominant_companion_delta).toFixed(4)}）`],
        ['相对补偿幅度', `${frac} 个工程步长`],
        ['受影响输出', selDomComp.compensated_dominant_field || '—'],
        ['结论适用局部范围', snapshotLabel]
      ];
      compEvidence = this.createTable(['字段', '值'], compRows);
    } else if (hasResult && selParam) {
      compEvidence = el('p', 'evidence-desc', `${selParam}：无补偿需求或为独立参数（${snapshotLabel}）`);
    } else {
      compEvidence = el('p', 'evidence-desc', '主要补偿参数、变化方向、步长占比和补偿后残差动态显示');
    }
    eGrid.append(this.createEvidenceBox('补偿关系证据', compEvidence, 'orange'));

    // 工程处置建议
    let adviceDesc;
    if (hasResult && selParam && selCombined) {
      const cls = selCombined.final_class || selCombined.baseline_class || '—';
      if (cls === '参数自身低敏感') adviceDesc = '可考虑固定或增加工况激励';
      else if (cls === '依赖其他参数补偿') adviceDesc = '增强先验约束或增加激励';
      else if (cls === '参数边界受限') adviceDesc = '放宽边界或增加工况覆盖';
      else adviceDesc = '保留该参数作为独立调度项';
    } else {
      adviceDesc = '保留、加强先验、固定参数或增加工况激励的建议动态显示';
    }
    eGrid.append(this.createEvidenceBox('工程处置建议', adviceDesc, 'green'));

    c4.card.id = 'ident-evidence-detail';
    c4.body.append(eGrid);

    container.append(c1.card, c2.card, c3.card, c4.card);
  }

  /** 从 directionDetail 中找到某参数的主要补偿参数 */
  _findDominantCompanion(dirRows, paramName) {
    const dirs = dirRows.filter(d => d.target_parameter === paramName);
    if (dirs.length === 0) return null;
    let best = dirs[0];
    for (const d of dirs) {
      if (d.dominant_companion && d.dominant_companion !== 'none' &&
          Number(d.dominant_companion_step_fraction) > Number(best.dominant_companion_step_fraction || 0)) {
        best = d;
      }
    }
    return best;
  }

  /** 数值证据弹窗：奇异谱 + 弱方向（文档 7.2：奇异谱和正则化作用曲线放在数值证据详情中） */
  _showNumericalEvidenceModal(cond, svdRows, weakRows) {
    const overlay = el('div', 'image-modal-overlay');
    const dialog = el('div', 'image-modal');
    dialog.style.maxWidth = '760px';
    const header = el('div', 'image-modal-header');
    const heading = el('h3', '', '数值证据');
    const close = el('button', 'image-modal-close', '✕');
    close.type = 'button';
    close.onclick = () => overlay.remove();
    header.append(heading, close);

    const body = el('div', 'image-modal-body modal-content');
    body.style.padding = '20px 24px';
    body.style.maxHeight = '70vh';
    body.style.overflow = 'auto';

    // 条件数对比
    const sec1 = el('div', '');
    sec1.style.cssText = 'margin-bottom:16px;';
    sec1.append(el('h4', '', '条件数对比'));
    const fmtC = v => {
      const n = Number(v);
      if (n >= 1e6) return n.toLocaleString('zh-CN', { maximumFractionDigits: 1 });
      if (n >= 100) return n.toFixed(1);
      return n.toFixed(6);
    };
    const cHeaders = ['指标', '数值'];
    const cRows = [
      ['标准化信息矩阵条件数', fmtC(cond.information_condition)],
      ['TSVD 保留后条件数', fmtC(cond.tsvd_retained_information_condition)],
      ['Tikhonov 增广后条件数', fmtC(cond.tikhonov_information_condition)],
      ['当前正则化后条件数', fmtC(cond.active_regularized_information_condition)],
      ['正则化改善倍数', fmtC(cond.active_regularization_improvement_factor)],
      ['数值秩 / 有效秩', `${cond.numerical_rank} / ${cond.effective_rank}`],
      ['最小有效奇异值', Number(cond.sigma_min).toFixed(6)],
      ['TSVD 保留/截断数', `${cond.tsvd_retained_count} / ${cond.tsvd_truncated_count}`]
    ];
    sec1.append(this.createTable(cHeaders, cRows));
    body.append(sec1);

    // SVD 奇异值谱
    if (svdRows.length > 0) {
      const sec2 = el('div', '');
      sec2.style.cssText = 'margin-bottom:16px;';
      sec2.append(el('h4', '', '奇异值谱'));
      const chartHost = el('div', '');
      chartHost.style.cssText = 'width:100%;height:260px;';
      sec2.append(chartHost);
      body.append(sec2);
      setTimeout(() => {
        try {
          const chart = this.ctx.echarts.init(chartHost);
          const xData = svdRows.map(r => `σ${r.singular_index}`);
          const yData = svdRows.map(r => Number(r.singular_value));
          const relData = svdRows.map(r => Number(r.relative_singular_value));
          const option = {
            tooltip: { trigger: 'axis' },
            legend: { data: ['奇异值', '相对值'], top: 5 },
            grid: { left: 60, right: 60, top: 40, bottom: 40 },
            xAxis: { type: 'category', data: xData, name: '序号' },
            yAxis: [
              { type: 'log', name: '奇异值', scale: true },
              { type: 'log', name: '相对值', scale: true }
            ],
            series: [
              { name: '奇异值', type: 'bar', data: yData, itemStyle: { color: '#1890ff' } },
              { name: '相对值', type: 'line', yAxisIndex: 1, data: relData, smooth: true, itemStyle: { color: '#ff7d00' } }
            ]
          };
          chart.setOption(option);
          // 滚动时重新 resize，避免 canvas 被清空后不恢复
          body.addEventListener('scroll', () => {
            chart.resize();
            chart.setOption(option, true);
          });
          // 弹窗关闭时销毁图表
          const origClose = close.onclick;
          close.onclick = () => { chart.dispose(); origClose(); };
          overlay.onclick = (e) => { if (e.target === overlay) { chart.dispose(); overlay.remove(); } };
        } catch (e) { /* ignore */ }
      }, 50);
    }

    // 弱方向表
    if (weakRows.length > 0) {
      const sec3 = el('div', '');
      sec3.append(el('h4', '', '弱方向参数载荷'));
      const wHeaders = ['排序', '奇异值', '参数', '载荷(缩放)', '载荷(绝对)'];
      const wRows = weakRows.map(r => [
        String(r.direction_rank_from_weakest),
        Number(r.singular_value).toExponential(3),
        r.parameter,
        Number(r.scaled_loading).toFixed(4),
        Number(r.absolute_loading).toFixed(4)
      ]);
      sec3.append(this.createTable(wHeaders, wRows));
      body.append(sec3);
    }

    dialog.append(header, body);
    overlay.append(dialog);
    (this.ctx.shadow || this.mount).appendChild(overlay);
  }

  /* ================= 04 不确定性评估 ================= */
  render_uq(container) {
    const actionKey = this.activeUqMethod === 'B' ? 'uqMethodB' : 'uqMethodA';
    const uqResult = this.latestResult(actionKey);
    const uqTask = this.latestTask(actionKey);
    const isRunning = uqTask?.status === TASK_STATUS.RUNNING;

    // 从结果中提取真实数据
    const summary = uqResult?.resultSummary || uqResult || {};
    const postDiag = summary.posteriorDiagnostic || {};
    const validation = summary.validation || {};
    const acceptance = summary.acceptance || postDiag.acceptance || validation.acceptance || {};
    const summaryTable = postDiag.summaryTable;
    const trainingTable = validation.trainingTable;
    const testTable = validation.testTable;
    const trainingSummary = validation.trainingSummary;
    const testSummary = validation.testSummary;

    // Card 1: 评估方法与运行时间预估（文档 8.1/8.2）
    const c1 = this.createCard(
      '评估方法与运行时间预估',
      '两种方法独立运行。界面根据当前数据规模、粒子配置和少量 DLL 试算，在执行前显示预计耗时及估算依据。'
    );
    const mGrid = el('div', 'method-grid grid-2');
    const estText = uqResult
      ? `已完成，总运行时间 ${this._formatDuration(summary.runtime_s)}`
      : (isRunning ? '正在运行...' : '运行前预估');
    const cardA = this.createMethodCard('A', '关键修正系数评估', '聚焦辨识阶段使用的总体调度修正与燃油偏置。', estText, this.activeUqMethod === 'A', () => {
      this.activeUqMethod = 'A';
      this.render();
    });
    const cardB = this.createMethodCard('B', '全修正系数评估', '进一步纳入六部件局部修正和物理引气不确定性。', estText, this.activeUqMethod === 'B', () => {
      this.activeUqMethod = 'B';
      this.render();
    });
    mGrid.append(cardA, cardB);
    c1.body.append(mGrid);

    // 运行状态指标
    const sGrid = el('div', 'metrics-grid');
    sGrid.style.marginTop = '12px';
    const passedText = summary.passed === true ? '通过' : summary.passed === false ? '未通过' : '—';
    const ess = postDiag.acceptance?.effectiveSampleSize;
    const minEss = postDiag.acceptance?.minimumEffectiveSampleSize;
    sGrid.append(
      this.createMetricBox('验收状态', passedText),
      this.createMetricBox('总运行时间', summary.runtime_s != null ? this._formatDuration(summary.runtime_s) : (isRunning ? '运行中...' : '运行后显示')),
      this.createMetricBox('有效样本数', ess != null ? String(ess) : '—'),
      this.createMetricBox('最低有效样本数门槛', minEss != null ? String(minEss) : '—')
    );
    c1.body.append(sGrid);

    // Card 2: 参数 95% 置信区间图（文档 8.3：从 summaryTable 读取下限、中心和上限）
    const c2 = this.createCard(
      '参数 95% 置信区间图',
      '统一使用"95%置信区间"名称。图中包含95%置信区间、后验中心和修正系数辨识结果。'
    );
    if (summaryTable && summaryTable.rows && summaryTable.rows.length > 0) {
      const rows = summaryTable.rows;
      // 按参数类别分三组：总体调度与燃油、六部件局部、物理引气
      const groupMap = {
        overall: /_K_W_|Wf_bias|Nozzle_K_A8/,
        local: /_K_eta_|Burner_K_dP_/,
        bleed: /_Duct_K_dP_/
      };
      const filtered = rows.filter(r => groupMap[this.activeUqParamTab || 'overall'].test(r.name));
      if (filtered.length === 0) {
        c2.body.append(el('p', 'card-subtitle', '当前分类下无参数。'));
      } else {
        const tabRow = el('div', 'reg-method-row');
        tabRow.style.marginBottom = '12px';
        const tabLabels = [
          { key: 'overall', label: '总体调度与燃油' },
          { key: 'local', label: '六部件局部' },
          { key: 'bleed', label: '物理引气' }
        ];
        tabLabels.forEach(({ key, label }) => {
          const btn = document.createElement('button');
          btn.textContent = label;
          btn.className = 'segment' + (this.activeUqParamTab === key ? ' active' : '');
          btn.onclick = () => { this.activeUqParamTab = key; this.render(); };
          tabRow.append(btn);
        });
        c2.body.append(tabRow);

        const chartHost = el('div', '');
        chartHost.style.cssText = 'width:100%;height:' + Math.max(260, filtered.length * 28 + 80) + 'px;';
        c2.body.append(chartHost);
        setTimeout(() => this.renderUqParameterChart(chartHost, filtered), 0);
      }
    } else {
      c2.body.append(el('p', 'card-subtitle', isRunning ? '正在执行后验采样...' : '运行后显示参数95%置信区间。'));
    }

    // Card 3: 结果解释与验收
    const c3 = this.createCard(
      '结果解释与验收',
      '用通俗说明回答工程人员最关心的问题。'
    );
    const list = el('ul', 'check-list');
    list.style.cssText = 'list-style:none;padding:0;margin:0;';
    // 每项：加粗标题 + 换行解释
    const items = [];
    // 可信范围
    let credibleDesc = '每个参数的可信区间有多宽';
    if (summaryTable && summaryTable.rows && summaryTable.rows.length > 0) {
      const widths = summaryTable.rows.map(r => Number(r.credible_width || 0));
      const maxW = Math.max(...widths);
      const minW = Math.min(...widths);
      const wideParam = summaryTable.rows.find(r => Number(r.credible_width) === maxW);
      credibleDesc = `最宽区间为 ${wideParam?.parameter || '—'}（宽度 ${maxW.toFixed(4)}），最窄为 ${minW.toFixed(4)}`;
    }
    items.push(['可信范围', credibleDesc]);
    // 补偿关系
    let compDesc = '哪些参数必须联合解释';
    if (postDiag.engineeringCompensationTable && postDiag.engineeringCompensationTable.rows) {
      const compCount = postDiag.engineeringCompensationTable.rows.length;
      if (compCount > 0) compDesc = `检测到 ${compCount} 组补偿关系，需联合解释`;
    }
    items.push(['补偿关系', compDesc]);
    // 多解可能
    let multiDesc = '是否存在不同参数组合解释同一数据';
    const sampling = postDiag.samplingDiagnostic;
    const idTable = postDiag.identifiabilityTable;
    if (sampling && Number(sampling.modeCount) > 1) {
      const masses = sampling.modeMass || [];
      const total = masses.reduce((a, b) => a + Number(b), 0) || 1;
      const parts = masses.map((m, i) => `模态${i + 1}（${(Number(m) / total * 100).toFixed(1)}%）`).join('、');
      multiDesc = `后验存在 ${sampling.modeCount} 个显著模态（${parts}），不同参数组合可能解释同一数据`;
    } else if (idTable && idTable.rows) {
      const lowSens = idTable.rows.filter(r => r.classification === '参数自身低敏感');
      if (lowSens.length > 0) {
        const names = lowSens.slice(0, 5).map(r => r.name || r.parameter || '—').join('、');
        multiDesc = `${names}${lowSens.length > 5 ? ' 等' : ''} 自身敏感性低，可能存在多解`;
      }
    }
    items.push(['多解可能', multiDesc]);
    // 预测影响
    let predDesc = '参数不确定性会使输出波动多大';
    if (validation.trainingSummary && validation.trainingSummary.rows) {
      predDesc = '参数不确定性已传播到输出区间，详见运行日志中的通道覆盖率';
    }
    items.push(['预测影响', predDesc]);
    // 统计状态
    let statDesc = '结果是否满足正式使用门槛';
    if (summary.passed === true) {
      statDesc = '结果满足正式使用门槛';
    } else if (summary.passed === false) {
      statDesc = '结果未满足正式使用门槛，请检查验收明细';
    }
    items.push(['统计状态', statDesc]);

    items.forEach(([title, desc]) => {
      const li = el('li', '');
      li.style.cssText = 'display:flex;gap:10px;margin-bottom:14px;align-items:flex-start;';
      // 大圆点带对号
      const dot = el('span', '');
      dot.style.cssText = 'flex-shrink:0;width:20px;height:20px;border-radius:50%;background:var(--blue,#1890ff);color:#fff;display:inline-flex;align-items:center;justify-content:center;font-size:12px;line-height:1;margin-top:2px;';
      dot.textContent = '✓';
      li.append(dot);
      const textWrap = el('div', '');
      textWrap.style.flex = '1';
      const titleEl = el('div', '');
      titleEl.style.cssText = 'font-weight:700;font-size:13px;color:var(--text);';
      titleEl.textContent = title;
      const descEl = el('div', '');
      descEl.style.cssText = 'font-size:12px;color:var(--muted);margin-top:2px;';
      descEl.textContent = desc;
      textWrap.append(titleEl, descEl);
      li.append(textWrap);
      list.append(li);
    });
    c3.body.append(list);

    // 底部提示
    const tip = el('p', 'card-subtitle', '不显示 SMC 温度推进与有效样本量曲线');
    tip.style.cssText = 'margin-top:12px;font-size:11px;color:var(--muted);border-top:1px solid var(--line);padding-top:10px;';
    c3.body.append(tip);

    // Card 2 和 Card 3 并排显示
    const c2c3Row = el('div', '');
    c2c3Row.style.cssText = 'display:flex;gap:16px;align-items:stretch;';
    c2.card.style.flex = '3';
    c3.card.style.flex = '2';
    c2c3Row.append(c2.card, c3.card);

    // Card 4: 运行进度与验收（文档 8.2）
    const c4 = this.createCard(
      '运行进度与验收',
      '正式任务中显示总体进度、当前步骤、已用时间、预计剩余和完成后的总运行时间。'
    );
    const progressTrack = el('div', 'progress-track');
    const fill = el('div', 'progress-fill');
    // 根据 progressMessage 中的 beta 值 + UQ 步骤号估算进度
    // UQ 10 步：步骤1-5=0-25%, 步骤6先导SMC=25-55%(3组replicate), 步骤7正式SMC=55-80%, 步骤8诊断=80-90%, 步骤9-10预测=90-100%
    const phasePct = { a: 25, b: 70, c: 90, d: 100, completed: 100 };
    const phase = ((uqTask?.phase || '').toLowerCase()).trim();
    const totalReplicates = this.uqConfig?.pilotReplicateCount || 3;
    let pct = 0;
    if (uqResult) {
      pct = 100;
    } else if (isRunning) {
      const msg = uqTask?.progressMessage || '';
      // 先检测 UQ 步骤号 [2.4UQ.N]
      const stepMatch = msg.match(/\[2\.4UQ\.(\d+)\]/);
      if (stepMatch) {
        this._uqStep = parseInt(stepMatch[1], 10);
      }
      const uqStep = this._uqStep || 0;
      const betaMatch = msg.match(/beta=([0-9.]+)/);
      if (betaMatch) {
        const beta = parseFloat(betaMatch[1]);
        const stageMatch = msg.match(/stage=\s*(\d+)/);
        const stage = stageMatch ? parseInt(stageMatch[1], 10) : 1;
        if (uqStep <= 6) {
          // 步骤6：先导 SMC，3组 replicate，区间 25%→55%
          if (this._lastBeta && beta < this._lastBeta * 0.5 && stage === 1) {
            this._smcReplicate = (this._smcReplicate || 0) + 1;
          }
          this._lastBeta = beta;
          const currentReplicate = Math.min(this._smcReplicate || 0, totalReplicates - 1);
          const smcRange = 30; // 25%→55%
          const perReplicate = smcRange / totalReplicates;
          pct = 25 + perReplicate * currentReplicate + perReplicate * Math.min(beta, 1);
        } else if (uqStep === 7) {
          // 步骤7：正式 SMC，区间 55%→80%
          this._lastBeta = beta;
          pct = 55 + 25 * Math.min(beta, 1);
        } else if (uqStep === 8) {
          // 步骤8：诊断，区间 80%→90%
          pct = 80 + 10 * Math.min(beta, 1);
        } else {
          // 步骤9-10：预测，区间 90%→100%
          pct = 90 + 10 * Math.min(beta, 1);
        }
      } else if (uqStep > 0) {
        // 有步骤号但没有 beta（非 SMC 阶段）
        const stepPct = { 1: 3, 2: 8, 3: 12, 4: 18, 5: 22, 6: 25, 7: 55, 8: 80, 9: 90, 10: 95 };
        pct = stepPct[uqStep] || 5;
      } else if (phasePct[phase] != null) {
        pct = phasePct[phase];
      } else {
        pct = 5;
      }
    }
    fill.style.width = pct + '%';
    progressTrack.append(fill);

    // 已用时间：从 task.startedAt 计算
    let elapsedText = '—';
    if (uqResult && summary.runtime_s != null) {
      elapsedText = this._formatDuration(summary.runtime_s);
    } else if (isRunning && uqTask?.startedAt) {
      const elapsed = (Date.now() - Number(uqTask.startedAt)) / 1000;
      elapsedText = this._formatDuration(elapsed);
    }

    // 预计剩余：根据进度百分比估算
    let remainingText = '—';
    if (uqResult) {
      remainingText = this._formatDuration(0);
    } else if (isRunning) {
      if (uqTask?.startedAt && pct > 5) {
        const elapsed = (Date.now() - Number(uqTask.startedAt)) / 1000;
        const total = elapsed / (pct / 100);
        remainingText = this._formatDuration(Math.max(0, total - elapsed));
      } else {
        remainingText = '估算中...';
      }
    }

    // 第一行：进度条 + 时间指标
    const row1 = el('div', '');
    row1.style.cssText = 'display:flex;align-items:center;gap:16px;';
    progressTrack.style.flex = '1';
    row1.append(progressTrack);
    const pGrid = el('div', 'metrics-grid');
    pGrid.style.marginTop = '0';
    pGrid.style.display = 'flex';
    pGrid.style.gridTemplateColumns = 'none';
    pGrid.style.flexShrink = '0';
    pGrid.append(
      this.createMetricBox('已用时间', elapsedText),
      this.createMetricBox('预计剩余', remainingText),
      this.createMetricBox('总运行时间', summary.runtime_s != null ? this._formatDuration(summary.runtime_s) : '完成后显示')
    );
    row1.append(pGrid);
    c4.body.append(row1);

    // 第二行：当前步骤 + 查看运行日志按钮
    const currentStep = uqTask?.progressMessage || uqTask?.logLine || '';
    let stepText;
    if (uqResult) {
      stepText = '后验抽样与区间预测完成';
    } else if (isRunning) {
      // 解析 SMC stage/beta 显示更友好的进度
      const stageMatch = currentStep.match(/SMC stage=(\d+)/);
      const betaMatch = currentStep.match(/beta=([0-9.]+)/);
      const essMatch = currentStep.match(/ESS=([0-9.]+)/);
      if (stageMatch && betaMatch) {
        const uqStep = this._uqStep || 6;
        if (uqStep <= 6) {
          const repNum = (this._smcReplicate || 0) + 1;
          stepText = `先导SMC（第 ${repNum}/${totalReplicates} 次）：stage=${stageMatch[1]}, β=${betaMatch[1]}, ESS=${essMatch ? essMatch[1] : '—'}`;
        } else if (uqStep === 7) {
          stepText = `正式SMC：stage=${stageMatch[1]}, β=${betaMatch[1]}, ESS=${essMatch ? essMatch[1] : '—'}`;
        } else {
          stepText = `SMC stage=${stageMatch[1]}, β=${betaMatch[1]}, ESS=${essMatch ? essMatch[1] : '—'}`;
        }
      } else if (currentStep) {
        stepText = currentStep;
      } else {
        stepText = '任务运行中...';
      }
    } else {
      stepText = '等待开始 / 运行后显示当前步骤';
    }
    const stepP = el('p', 'card-subtitle', stepText);
    if (isRunning && currentStep) {
      stepP.style.cssText = 'word-break:break-all;font-size:11px;color:var(--muted);max-height:60px;overflow:hidden;';
    }
    const row2 = el('div', '');
    row2.style.cssText = 'display:flex;align-items:center;justify-content:space-between;gap:12px;margin-top:8px;';
    stepP.style.flex = '1';
    row2.append(stepP);
    const logBtn = button('查看运行日志与验收明细', 'btn-card', () => this._showUqLogModal(uqTask));
    logBtn.style.whiteSpace = 'nowrap';
    logBtn.style.flexShrink = '0';
    row2.append(logBtn);
    c4.body.append(row2);

    // 验收子项
    const accItems = [];
    if (postDiag.acceptance) {
      if (postDiag.acceptance.endpointMcsePassed != null) accItems.push(['端点 MCSE 检验', postDiag.acceptance.endpointMcsePassed ? '通过' : '未通过']);
      if (postDiag.acceptance.effectiveSampleSizePassed != null) accItems.push(['有效样本数检验', postDiag.acceptance.effectiveSampleSizePassed ? '通过' : '未通过']);
      if (postDiag.acceptance.likelihoodCalibrationPassed != null) accItems.push(['似然标定检验', postDiag.acceptance.likelihoodCalibrationPassed ? '通过' : '未通过']);
    }
    if (validation.acceptance) {
      if (validation.acceptance.testReplayValidityPassed != null) accItems.push(['测试回放有效性', validation.acceptance.testReplayValidityPassed ? '通过' : '未通过']);
      if (validation.acceptance.predictionIntervalsOrdered != null) accItems.push(['预测区间有序性', validation.acceptance.predictionIntervalsOrdered ? '通过' : '未通过']);
    }
    if (accItems.length > 0) {
      const accGrid = el('div', 'metrics-grid');
      accGrid.style.marginTop = '12px';
      accItems.forEach(([label, val]) => accGrid.append(this.createMetricBox(label, val)));
      c4.body.append(accGrid);
    }

    container.append(c1.card, c2c3Row, c4.card);

    // 自动触发运行时间预估（仅在未运行、无结果、无预估结果时触发一次）
    if (!uqResult && !isRunning) {
      const estKey = this.activeUqMethod === 'B' ? 'uqRuntimeEstimateB' : 'uqRuntimeEstimateA';
      const estTask = this.latestTask(estKey);
      const estResult = this.latestResult(estKey);
      if (!estResult && !estTask && !this._uqEstimateTriggered) {
        this._uqEstimateTriggered = true;
        this._startEstimate(estKey);
      }
    }
  }

  /** 提交运行时间预估任务 */
  async _startEstimate(actionKey) {
    try {
      const task = await this.ctx.http.tasks.request('', {
        method: 'POST',
        body: {
          actionKey,
          inputs: { userCfg: { ...this.uqConfig } }
        }
      });
      if (task && task.id) {
        this.tasks.set(String(task.id), task);
        this.schedulePoll(String(task.id), 5000);
        this.render();
      }
    } catch (e) {
      this._uqEstimateTriggered = false;
    }
  }
  async _showUqLogModal(uqTask) {
    const overlay = el('div', 'image-modal-overlay');
    const dialog = el('div', 'image-modal');
    dialog.style.maxWidth = '820px';
    const header = el('div', 'image-modal-header');
    const heading = el('h3', '', '运行日志与验收明细');
    const close = el('button', 'image-modal-close', '✕');
    close.type = 'button';
    const statusTag = el('span', '');
    statusTag.style.cssText = 'font-size:11px;color:var(--muted);margin-left:8px;';
    const titleWrap = el('div', '');
    titleWrap.style.cssText = 'display:flex;align-items:center;gap:8px;';
    titleWrap.append(heading, statusTag);
    header.append(titleWrap, close);

    const body = el('div', 'image-modal-body modal-content');
    body.style.padding = '16px 20px';
    body.style.maxHeight = '75vh';
    body.style.overflow = 'auto';

    body.append(el('p', '', '正在加载日志...'));
    dialog.append(header, body);
    overlay.append(dialog);
    (this.ctx.shadow || this.mount).appendChild(overlay);

    const taskId = uqTask?.id;
    if (!taskId) {
      body.textContent = '';
      body.append(el('p', '', '暂无任务。'));
      close.onclick = () => overlay.remove();
      return;
    }
    const name = this.program?.name || '';
    const version = this.program?.version || '';
    const projectName = this.workspace?.projectName || this.projectForm?.projectName || '';

    // 初始加载一次完整日志
    let pre = null;
    let autoScroll = true;
    try {
      const log = await this.ctx.http.tasks.request(`${taskId}/log`, {
        method: 'GET',
        query: { name, version, projectName }
      });
      const text = typeof log === 'string' ? log : (log?.data?.content || log?.content || log?.text || JSON.stringify(log, null, 2));
      body.textContent = '';
      pre = el('pre', 'log-text', text);
      pre.style.cssText = 'width:100%;margin:0;padding:12px 14px;background:#f8fafb;border:1px solid var(--line);border-radius:3px;font-size:11px;line-height:1.6;white-space:pre-wrap;word-break:break-all;font-family:Consolas,"Courier New",monospace;color:var(--text);max-height:65vh;overflow:auto;';
      pre.addEventListener('scroll', () => {
        autoScroll = pre.scrollTop + pre.clientHeight >= pre.scrollHeight - 5;
      });
      body.append(pre);
    } catch (e) {
      body.textContent = '';
      body.append(el('p', '', '加载日志失败: ' + (e.message || e)));
    }

    // 设置初始状态
    const initPhase = (uqTask?.phase || '').toLowerCase();
    if (uqTask?.status === TASK_STATUS.COMPLETED || initPhase === 'completed') {
      statusTag.textContent = '已完成';
      statusTag.style.color = 'var(--green, #1a7f37)';
    } else if (uqTask?.status === TASK_STATUS.FAILED || initPhase === 'failed') {
      statusTag.textContent = '已失败';
      statusTag.style.color = '#d1242f';
    } else {
      statusTag.textContent = '运行中';
      statusTag.style.color = 'var(--blue, #1890ff)';
    }

    // 注册回调：schedulePoll 轮询到新日志时追加到弹窗
    this._uqLogCallback = (logLine, task) => {
      if (!pre) return;
      // 追加新行
      const wasAtBottom = autoScroll;
      pre.textContent += (pre.textContent.endsWith('\n') || !pre.textContent ? '' : '\n') + logLine;
      if (wasAtBottom) pre.scrollTop = pre.scrollHeight;
      // 更新状态标签
      const phase = (task?.phase || '').toLowerCase();
      if (task?.status === TASK_STATUS.COMPLETED || phase === 'completed') {
        statusTag.textContent = '已完成';
        statusTag.style.color = 'var(--green, #1a7f37)';
      } else if (task?.status === TASK_STATUS.FAILED || phase === 'failed') {
        statusTag.textContent = '已失败';
        statusTag.style.color = '#d1242f';
      } else {
        statusTag.textContent = '运行中';
        statusTag.style.color = 'var(--blue, #1890ff)';
      }
    };

    const cleanup = () => {
      this._uqLogCallback = null;
      overlay.remove();
    };
    close.onclick = cleanup;
    overlay.onclick = (e) => { if (e.target === overlay) cleanup(); };
  }

  /* ================= 05 测试验证 ================= */
  render_validation(container) {
    const valResult = this.latestResult('testValidation');
    const valTask = this.latestTask('testValidation');

    // 文档第 9 节：测试数据不存在时显示"未提供测试集，本步骤已跳过"，不报程序错误
    const hasTestData = !!(this.workspace?.testDataFile);
    const valSkipped = valTask?.status === TASK_STATUS.SKIPPED;

    // Card 1: 验证输入与边界
    const c1 = this.createCard(
      '验证输入与边界',
      '测试数据不参与辨识；本页只做稳态模型验证。'
    );
    const identTask = this.latestIdentifyTask();
    const identResult = identTask ? this.results.get(String(identTask.id)) : null;
    const modelName = identResult?.resultSummary?.steadyModelName || '稳态辨识模型（最新）';
    const testDataName = this.workspace?.testDataFile || '';

    if (!hasTestData || valSkipped) {
      // 测试数据不存在或任务已跳过
      const skipNotice = el('div', 'notice-box', '未提供测试集，本步骤已跳过');
      skipNotice.style.cssText = 'background:#f5f5f5;border-color:#d9d9d9;color:#666;';
      c1.body.append(skipNotice);
      container.append(c1.card);
      return;
    }

    // 自动回显：打开项目时自动选择辨识结果和测试数据
    if (!this._validationModel) this._validationModel = modelName;
    if (!this._validationTestData) this._validationTestData = testDataName;

    const form = el('div', 'form-grid-3');
    form.append(
      this.createField('稳态辨识模型', select([
        { value: '', label: '选择辨识结果' },
        { value: modelName, label: modelName }
      ], this._validationModel || '')),
      this.createField('测试数据', select([
        { value: '', label: '选择测试数据' },
        { value: testDataName, label: testDataName }
      ], this._validationTestData || ''))
    );
    c1.body.append(form);
    const notice = el('div', 'notice-box success', '✓ 稳态模型验证 · 数据隔离检查');
    c1.body.append(notice);
    if (valTask?.status === TASK_STATUS.READY) {
      const queueTip = el('div', 'notice-box', '⏳ 任务已提交，正在排队等待前序任务完成...');
      queueTip.style.cssText = 'background:#fff8e1;border-color:#ffe082;color:#8d6e63;';
      c1.body.append(queueTip);
    }

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

      const valTask = this.latestTask('testValidation');
      const valRunning = valTask?.status === TASK_STATUS.RUNNING;
      const valQueued = valTask?.status === TASK_STATUS.READY;
      const chartsGrid = el('div', 'charts-grid-3');
      OUTPUT_VARS.forEach(o => {
        const cell = this.createChartCell(o, valRunning);
        chartsGrid.append(cell.cell);
        if (valResult) {
          this.renderValidationComparisonChart(cell.host, o, valResult);
        }
      });
      c2.body.append(chartsGrid);
    } else {
      // 误差标准差对比图表：柱状图对比零修正 vs 稳态辨识模型 RMSE
      const summary = valResult?.resultSummary || valResult || {};
      const baselineByField = this._metricsByFieldMap(summary.baseline?.metrics);
      const correctedByField = this._metricsByFieldMap(summary.corrected?.metrics);
      const rmseHost = el('div', 'chart-host');
      rmseHost.style.height = '240px';
      c2.body.append(rmseHost);
      if (this.ctx.echarts && valResult) {
        const chart = this.ctx.echarts.init(rmseHost, null, { renderer: 'canvas' });
        const baseData = OUTPUT_VARS.map(o => {
          const v = baselineByField[o]?.rmse;
          return v != null ? Number(v) : 0;
        });
        const corrData = OUTPUT_VARS.map(o => {
          const v = correctedByField[o]?.rmse;
          return v != null ? Number(v) : 0;
        });
        chart.setOption({
          animation: false,
          grid: { left: 50, right: 20, top: 30, bottom: 30 },
          legend: { data: ['零修正模型', '稳态辨识模型'], top: 0, textStyle: { fontSize: 11 } },
          xAxis: { type: 'category', data: OUTPUT_VARS, axisLabel: { fontSize: 10 } },
          yAxis: { type: 'value', scale: true, axisLabel: { fontSize: 10 } },
          series: [
            { name: '零修正模型', type: 'bar', data: baseData, itemStyle: { color: '#8c9ea9' } },
            { name: '稳态辨识模型', type: 'bar', data: corrData, itemStyle: { color: '#2b6b95' } }
          ]
        });
        this.charts.push(chart);
      }
    }

    // 在验证结果分页卡片内部下方添加提示
    const hint = el('div', 'notice-box', '"误差标准差对比"页按输出变量显示零修正模型和稳态辨识模型的误差标准差及改善幅度。');
    hint.style.cssText = 'background:#f5f7fa;border-color:#e8eaed;color:#5a6a7a;margin-top:12px;font-size:12px;';
    c2.body.append(hint);
    const tagRow = el('div', 'reg-method-row');
    tagRow.style.marginTop = '8px';
    const tag1 = el('span', 'field-status', '测试数据未用于参数更新');
    tag1.style.cssText = 'background:#e6f7e6;color:#237a54;border:1px solid #52c41a;padding:2px 10px;border-radius:3px;font-size:12px;';
    const tag2 = el('span', 'field-status', '不读取隐藏真值');
    tag2.style.cssText = 'background:#e6f7e6;color:#237a54;border:1px solid #52c41a;padding:2px 10px;border-radius:3px;font-size:12px;';
    tagRow.append(tag1, tag2);
    c2.body.append(tagRow);

    container.append(c1.card, c2.card);
  }

  /* ================= 06 工况预测 ================= */
  render_prediction(container) {
    const predResult = this.latestResult('operatingPointPrediction');

    // Card 1: 预测方式
    const c1 = this.createCard(
      '预测方式',
      '首轮只支持单工况，不设计批量预测。'
    );
    const segRow = el('div', 'reg-method-row');
    const seg = el('div', 'segmented');
    seg.append(
      button('直接环境边界', 'segment' + (this.predictionMode === 'pressure' ? ' active' : ''), () => { this.predictionMode = 'pressure'; this.render(); }),
      button('高度环境边界', 'segment' + (this.predictionMode === 'altitude' ? ' active' : ''), () => { this.predictionMode = 'altitude'; this.render(); })
    );
    segRow.append(seg, el('span', 'field-status optional', '单工况 · 稳态模型'));
    c1.body.append(segRow);
    const modelLabel = this.activePredictionModel === 'baseline' ? '零修正基准模型（A阶段前）' : '稳态辨识模型（D阶段后）';
    const postLabel = !this._predictionPosterior || this._predictionPosterior === 'none'
      ? '仅确定性预测' : `方法${this._predictionPosterior}后验区间`;
    const modelTag = el('div', 'reg-method-row');
    modelTag.append(
      el('span', 'field-status', '当前模型：'),
      el('span', 'field-status ok', modelLabel),
      el('span', 'field-status optional', postLabel)
    );
    modelTag.style.margin = '8px 0';
    c1.body.append(modelTag);
    const hint = this.predictionMode === 'pressure'
      ? '不经过总距角与控制闭环；燃油输入为模型实际输入，不应用燃油测量值。'
      : '由 DLL 根据高度和静温重构环境压力，无需同时输入高度和 Pamb。';
    c1.body.append(el('p', 'card-foot-note', hint));

    // Card 2: 单工况输入
    const c2 = this.createCard(
      '单工况输入',
      '切换环境边界方式后只显示需要填写的字段。'
    );
    const form = el('div', '');
    form.style.cssText = 'display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:16px;';
    if (this.predictionMode === 'pressure') {
      const pointInput = input('text', 'pointId', '请输入工况名称', this.predInputs.pointId);
      pointInput.addEventListener('change', e => { this.predInputs.pointId = e.target.value; });
      const pointField = this.createField('工况名称', pointInput);
      const pambInput = input('number', 'pamb', '请输入或由高度计算', this.predInputs.pamb);
      pambInput.addEventListener('change', e => { this.predInputs.pamb = Number(e.target.value); });
      const tambInput = input('number', 'tamb', '请输入环境温度', this.predInputs.tamb);
      tambInput.addEventListener('change', e => { this.predInputs.tamb = Number(e.target.value); });
      const machInput = input('number', 'mach', '请输入马赫数', this.predInputs.mach);
      machInput.addEventListener('change', e => { this.predInputs.mach = Number(e.target.value); });
      const wfInput = input('number', 'wf', '请输入燃油流量', this.predInputs.wf);
      wfInput.addEventListener('change', e => { this.predInputs.wf = Number(e.target.value); });
      const mkpInput = input('number', 'mkp', '请输入Mkp', this.predInputs.mkp);
      mkpInput.addEventListener('change', e => { this.predInputs.mkp = Number(e.target.value); });
      const mkgInput = input('number', 'mkg', '请输入Mkg', this.predInputs.mkg);
      mkgInput.addEventListener('change', e => { this.predInputs.mkg = Number(e.target.value); });
      const npInput = input('number', 'npInitial', '可选；留空时自动生成', this.predInputs.npInitial);
      npInput.addEventListener('change', e => { this.predInputs.npInitial = e.target.value === '' ? '' : Number(e.target.value); });

      form.append(
        pointField,
        this.createField('环境压力', pambInput),
        this.createField('环境温度', tambInput),
        this.createField('马赫数', machInput),
        this.createField('模型燃油流量', wfInput),
        this.createField('PT轴负载扭矩', mkpInput),
        this.createField('GT轴附件负载扭矩', mkgInput),
        this.createField('转速初值', npInput)
      );
    } else {
      const pointInput = input('text', 'pointId', '请输入工况名称', this.predInputs.pointId);
      pointInput.addEventListener('change', e => { this.predInputs.pointId = e.target.value; });
      const pointField = this.createField('工况名称', pointInput);
      const altInput = input('number', 'altitude', '请输入', this.predInputs.altitude);
      altInput.addEventListener('change', e => { this.predInputs.altitude = Number(e.target.value); });
      const tambInput = input('number', 'tamb', '请输入环境温度', this.predInputs.tamb);
      tambInput.addEventListener('change', e => { this.predInputs.tamb = Number(e.target.value); });
      const machInput = input('number', 'mach', '请输入马赫数', this.predInputs.mach);
      machInput.addEventListener('change', e => { this.predInputs.mach = Number(e.target.value); });
      const wfInput = input('number', 'wf', '请输入燃油流量', this.predInputs.wf);
      wfInput.addEventListener('change', e => { this.predInputs.wf = Number(e.target.value); });
      const mkpInput = input('number', 'mkp', '请输入Mkp', this.predInputs.mkp);
      mkpInput.addEventListener('change', e => { this.predInputs.mkp = Number(e.target.value); });
      const mkgInput = input('number', 'mkg', '请输入Mkg', this.predInputs.mkg);
      mkgInput.addEventListener('change', e => { this.predInputs.mkg = Number(e.target.value); });
      const npInput = input('number', 'npInitial', '可选；留空时自动生成', this.predInputs.npInitial);
      npInput.addEventListener('change', e => { this.predInputs.npInitial = e.target.value === '' ? '' : Number(e.target.value); });

      form.append(
        pointField,
        this.createField('高度', altInput),
        this.createField('环境温度', tambInput),
        this.createField('马赫数', machInput),
        this.createField('模型燃油流量', wfInput),
        this.createField('PT轴负载扭矩', mkpInput),
        this.createField('GT轴附件负载扭矩', mkgInput),
        this.createField('转速初值', npInput)
      );
    }
    c2.body.append(form);

    // Card 3: 预测输出与 95% 置信区间（与 Card 2 并排显示）
    const c3 = this.createCard(
      '预测输出与 95% 置信区间',
      '确定性结果、后验中心、模型输出区间和可观测量区间均在运行后读取。'
    );
    const predSummary = predResult?.resultSummary || predResult || {};
    const predTable = predSummary.predictionTable;
    // predTable.rows 可能是数组（多行）或单个对象（rowCount=1 时 MATLAB struct 不是数组）
    let predRow0 = null;
    if (predTable) {
      if (Array.isArray(predTable.rows) && predTable.rows.length > 0) {
        predRow0 = predTable.rows[0];
      } else if (predTable.rows && typeof predTable.rows === 'object' && !Array.isArray(predTable.rows)) {
        predRow0 = predTable.rows;
      }
    }
    const hasPosterior = predSummary.posteriorPredictionPerformed || (predSummary.posteriorPrediction && predSummary.posteriorPrediction.intervalTable);
    const intervalTable = hasPosterior ? (predSummary.posteriorPrediction?.intervalTable) : null;
    let intervalRows = [];
    if (intervalTable) {
      if (Array.isArray(intervalTable.rows)) {
        intervalRows = intervalTable.rows;
      } else if (intervalTable.rows && typeof intervalTable.rows === 'object') {
        intervalRows = [intervalTable.rows];
      }
    }

    // 预测输出表：与效果图对齐，5 列：输出 / 稳态辨识模型 / 区间下界 / 区间上界 / 状态
    const detHeaders = ['输出', '稳态辨识模型', '区间下界', '区间上界', '状态'];
    const detRows = OUTPUT_VARS.map(o => {
      const colMap = { 'Np': 'corrected_Np_rpm', 'Ng': 'corrected_Ng_rpm', 'Pt3': 'corrected_Pt3_Pa', 'Tt3': 'corrected_Tt3_K', 'Tt45': 'corrected_Tt45_K', 'Pt45': 'corrected_Pt45_Pa' };
      const col = colMap[o];
      const val = predRow0 ? predRow0[col] : null;
      const valStr = val != null ? Number(val).toFixed(2) : '运行后显示';
      let lower = '运行后显示';
      let upper = '运行后显示';
      let status = '待运行';
      if (predRow0) {
        if (hasPosterior) {
          const iRow = intervalRows.find(r => r.output_name === o);
          if (iRow) {
            const lo = Number(iRow.model_lower);
            const up = Number(iRow.model_upper);
            if (isFinite(lo)) lower = lo.toFixed(2);
            if (isFinite(up)) upper = up.toFixed(2);
            if (isFinite(lo) && isFinite(up) && val != null) {
              const detVal = Number(val);
              status = (detVal >= lo && detVal <= up) ? '区间覆盖' : '区间未覆盖';
            } else {
              status = '—';
            }
          } else {
            status = '—';
          }
        } else {
          status = '完成';
        }
      }
      return [o, valStr, lower, upper, status];
    });
    c3.body.append(this.createTable(detHeaders, detRows));

    // 共同工作最大残差和收敛状态（文档第 10 节：页面首先显示确定性输出、最大残差和收敛状态）
    const maxResidual = predRow0 ? predRow0.max_model_residual : null;
    const valid = predRow0 ? predRow0.valid : null;
    const fmtResidual = (v) => {
      const n = Number(v);
      if (!isFinite(n)) return '—';
      if (n === 0) return '0';
      if (Math.abs(n) < 1e-6) return n.toExponential(3);
      return n.toFixed(6);
    };
    const statusGrid = el('div', 'metrics-grid');
    statusGrid.style.marginTop = '12px';
    statusGrid.append(
      this.createMetricBox('共同工作最大残差', maxResidual != null ? fmtResidual(maxResidual) : '待运行'),
      this.createMetricBox('收敛状态', valid != null ? (valid ? '收敛' : '未收敛') : '待运行')
    );
    c3.body.append(statusGrid);

    // Card 4: 区间图与运行验收
    const c4 = this.createCard(
      '区间图与运行验收',
      hasPosterior ? '95% 置信区间、后验中心和稳态辨识模型确定性输出。' : '选择方法 A 或 B 后验后，运行预测可显示 95% 置信区间。'
    );
    const predTask = this.latestTask('operatingPointPrediction');
    const predRunning = predTask?.status === TASK_STATUS.RUNNING;
    const chartsGrid = el('div', 'charts-grid-3');
    OUTPUT_VARS.forEach(o => {
      const cell = this.createChartCell(o, predRunning);
      chartsGrid.append(cell.cell);
      if (predResult) {
        const fieldMap = { 'Np': ['corrected_Np_rpm','corrected_Np','Np','dNp_dt'], 'Ng': ['corrected_Ng_rpm','corrected_Ng','Ng','dNg_dt'],
          'Pt3': ['corrected_Pt3_Pa','corrected_Pt3','Pt3'], 'Tt3': ['corrected_Tt3_K','corrected_Tt3','Tt3'],
          'Tt45': ['corrected_Tt45_K','corrected_Tt45','Tt45'], 'Pt45': ['corrected_Pt45_Pa','corrected_Pt45','Pt45'] };
        const candidates = fieldMap[o] || [o];
        let detVal = null;
        if (predRow0) {
          for (const c of candidates) {
            if (predRow0[c] != null) { detVal = predRow0[c]; break; }
          }
          if (detVal == null && predTable && Array.isArray(predTable.rows)) {
            const row = predTable.rows.find(r => candidates.includes(r.field));
            if (row) detVal = row.corrected_model;
          }
        }
        if (hasPosterior) {
          const row = intervalRows.find(r => r.output_name === o);
          if (row) {
            this.renderPredictionIntervalChart(cell.host, o, row);
          } else if (detVal != null) {
            this.renderPredictionDeterministicChart(cell.host, o, detVal);
          }
        } else if (detVal != null) {
          this.renderPredictionDeterministicChart(cell.host, o, detVal);
        }
      }
    });
    c4.body.append(chartsGrid);
    if (hasPosterior) {
      const postInfo = predSummary.posteriorPrediction || {};
      const acceptWrap = el('div', 'reg-method-row');
      acceptWrap.style.justifyContent = 'space-between';
      acceptWrap.style.alignItems = 'center';
      acceptWrap.style.marginTop = '12px';
      const acceptInfo = el('div', 'reg-method-row');
      acceptInfo.append(
        el('span', 'field-status optional', `后验方法：${postInfo.method || '—'}`),
        el('span', 'field-status optional', `有效后验质量：${postInfo.validPosteriorMass != null ? Number(postInfo.validPosteriorMass).toFixed(3) : '—'}`),
        el('span', postInfo.passed ? 'field-status ok' : 'field-status', `区间验收：${postInfo.passed ? '通过' : '未通过'}`)
      );
      const acceptBtn = el('span', '', '收敛与有效后验质量验收');
      acceptBtn.style.cssText = postInfo.passed
        ? 'display:inline-block;background:#237a54;color:#fff;border:1px solid #237a54;padding:6px 16px;border-radius:4px;font-size:12px;line-height:1;'
        : 'display:inline-block;background:#2b6b95;color:#fff;border:1px solid #2b6b95;padding:6px 16px;border-radius:4px;font-size:12px;line-height:1;';
      acceptWrap.append(acceptInfo, acceptBtn);
      c4.body.append(acceptWrap);
    }

    // Card 2 和 Card 3 并排显示
    const c2c3Row = el('div', '');
    c2c3Row.style.cssText = 'display:flex;gap:16px;align-items:stretch;';
    c2.card.style.flex = '1';
    c2.card.style.display = 'flex';
    c2.card.style.flexDirection = 'column';
    c2.body.style.flex = '1 1 auto';
    c3.card.style.flex = '1';
    c3.card.style.display = 'flex';
    c3.card.style.flexDirection = 'column';
    c3.body.style.flex = '1 1 auto';
    c2c3Row.append(c2.card, c3.card);

    container.append(c1.card, c2c3Row, c4.card);
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
    // actionKey → 中文标签、所属筛选分类和主要产物
    const actionKeyMeta = {
      estimateTransient: { label: '参数辨识', method: '瞬态时刻模型路径', filter: 'identify', artifact: '参数、调度曲线、误差' },
      estimateSteady: { label: '参数辨识', method: '稳态模型路径', filter: 'identify', artifact: '参数、调度曲线、误差' },
      engineeringIdentifiability: { label: '可辨识性', method: '双位置综合分析', filter: 'identifiability', artifact: '分类、补偿方向、报告' },
      uqMethodA: { label: '关键修正系数评估', method: '方法 A', filter: 'uq', artifact: '后验、可信区间、预测' },
      uqMethodB: { label: '全修正系数评估', method: '方法 B', filter: 'uq', artifact: '分块后验、可信区间、预测' },
      testValidation: { label: '测试验证', method: '稳态模型回放', filter: 'validation', artifact: '输出对比、误差标准差' },
      operatingPointPrediction: { label: '工况预测', method: '单工况直接预测', filter: 'prediction', artifact: '预测中心、可信区间' }
    };
    let filteredTasks = allTasksList;
    if (this.resultsFilter !== 'all') {
      filteredTasks = allTasksList.filter(t => {
        const meta = actionKeyMeta[t.actionKey];
        return meta && meta.filter === this.resultsFilter;
      });
    }
    // 如果没有选中任务，或选中的任务不在当前筛选范围内，自动选中筛选范围内的最新任务
    if (!this._selectedResultTaskId || !filteredTasks.find(t => String(t.id) === this._selectedResultTaskId)) {
      const latestFiltered = filteredTasks[0];
      this._selectedResultTaskId = latestFiltered ? String(latestFiltered.id) : null;
    }
    const rRows = filteredTasks.map(t => {
      const meta = actionKeyMeta[t.actionKey] || { label: t.actionKey || '—', method: '—', filter: null, artifact: '—' };
      const res = (t.result && t.result.value !== undefined) ? t.result.value : (t.result || this.results.get(String(t.id)));
      const sum = res?.resultSummary || res || {};
      const entry = t.entryPoint || sum.program || meta.method;
      const route = sum.routeLabel || sum.route || '';
      const methodPath = route ? `${entry} · ${route}` : entry;
      const isSelected = this._selectedResultTaskId === String(t.id);
      const openBtn = button(isSelected ? '已打开' : '打开', 'btn-table' + (isSelected ? ' primary' : ''), () => {
        this._selectedResultTaskId = String(t.id);
        this.render();
      });
      return [meta.label, methodPath, this._statusLabel(t.status) || '待运行', meta.artifact, openBtn];
    });
    c2.body.append(this.createTable(rHeaders, rRows));
    c2.body.append(el('p', 'table-note', allTasksList.length === 0 ? '尚无运行记录时，引导用户返回相应页面开始任务。' : `已记录 ${allTasksList.length} 条任务执行记录。`));

    // 当前选中的任务（Card 3 和 Card 4 都跟随这个）
    const selectedTask = this._selectedResultTaskId ? this.tasks.get(this._selectedResultTaskId) : null;

    // Card 3: 所选结果详情（与 Card 2 并排显示）
    const c3 = this.createCard(
      '所选结果详情',
      '仅展示当前选择，不修改原始结果文件。'
    );
    const latestIdentTask = selectedTask;
    const isIdentTask = latestIdentTask && (latestIdentTask.actionKey === 'estimateTransient' || latestIdentTask.actionKey === 'estimateSteady');
    const isCompleted = latestIdentTask && latestIdentTask.status === TASK_STATUS.COMPLETED;
    const reviewApproved = isIdentTask && latestIdentTask.reviewStatus === TASK_STATUS.REVIEW_APPROVED;
    const reviewRejected = isIdentTask && latestIdentTask.reviewStatus === TASK_STATUS.REVIEW_REJECTED;
    const dList = el('ul', 'check-list');
    dList.style.cssText = 'list-style:none;padding:0;margin:0;';
    [
      '输入数据与模型指纹',
      '运行配置与停止原因',
      '验收状态与复核意见',
      '结果文件与图形',
      'MATLAB 调用方式',
      '稳态辨识模型状态'
    ].forEach((label, i) => {
      const vals = latestIdentTask
        ? this._buildResultDetailValues(latestIdentTask)
        : ['尚未选择结果', '尚未选择结果', '尚未选择结果', '尚未选择结果', '尚未选择结果', '尚未选择结果'];
      const li = el('li', 'check-item');
      li.style.cssText = 'display:flex;align-items:flex-start;gap:10px;margin-bottom:12px;';
      const dot = el('span', '');
      dot.style.cssText = 'flex-shrink:0;width:10px;height:10px;border-radius:50%;background:var(--blue,#1890ff);margin-top:5px;';
      li.append(dot);
      const textWrap = el('div', '');
      textWrap.style.flex = '1';
      textWrap.append(el('div', '', label + '：' + vals[i]));
      if (label === '验收状态与复核意见' && isIdentTask && isCompleted) {
        const reviewLine = el('div', '');
        reviewLine.style.cssText = 'margin-top:4px;display:flex;align-items:center;gap:12px;';
        const doReview = async (decision) => {
          try {
            await this.ctx.http.results.request(latestIdentTask.id + '/review', {
              method: 'POST',
              body: JSON.stringify({ decision, notes: '' }),
              headers: { 'Content-Type': 'application/json' }
            });
            latestIdentTask.reviewStatus = decision === 'APPROVED' ? TASK_STATUS.REVIEW_APPROVED : TASK_STATUS.REVIEW_REJECTED;
            this.ctx.log(`结果已${decision === 'APPROVED' ? '审核通过' : '驳回'}`);
            if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast(decision === 'APPROVED' ? '结果已审核通过' : '结果已驳回', decision === 'APPROVED' ? 'success' : 'warning');
            this.render();
          } catch (e) {
            this.ctx.log((decision === 'APPROVED' ? '审核' : '驳回') + '失败: ' + (e.message || e));
            if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast((decision === 'APPROVED' ? '审核' : '驳回') + '失败: ' + (e.message || e), 'error');
          }
        };
        const reviewVal = reviewApproved ? 'APPROVED' : reviewRejected ? 'REJECTED' : '';
        const makeRadio = (value, text, checked) => {
          const lbl = el('label', '');
          lbl.style.cssText = 'display:inline-flex;align-items:center;gap:4px;cursor:pointer;font-size:12px;';
          const inp = el('input', '');
          inp.type = 'radio';
          inp.name = 'review-' + latestIdentTask.id;
          inp.value = value;
          if (checked) inp.checked = true;
          inp.onchange = async () => { if (inp.checked) await doReview(value); };
          lbl.append(inp, el('span', '', text));
          return lbl;
        };
        reviewLine.append(
          el('span', '', '审核：'),
          makeRadio('APPROVED', '通过', reviewVal === 'APPROVED'),
          makeRadio('REJECTED', '驳回', reviewVal === 'REJECTED')
        );
        textWrap.append(reviewLine);
      }
      li.append(textWrap);
      dList.append(li);
    });
    c3.body.append(dList);
    const btnRow = el('div', 'btn-row');
    btnRow.append(
      button('复制调用方式', 'btn-card', () => {
        if (!latestIdentTask) {
          if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('请先选择一条结果记录', 'warning');
          return;
        }
        const entryPoint = latestIdentTask.entryPoint || '—';
        const code = `result = ${entryPoint}(...);`;
        if (navigator.clipboard) navigator.clipboard.writeText(code);
        this.ctx.log(`已复制调用方式：${code}`);
        if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('已复制 MATLAB 调用代码至剪贴板', 'success');
      })
    );
    if (isIdentTask && isCompleted) {
      btnRow.append(

        button('设为稳态辨识模型', 'btn-card primary', async () => {
          if (!latestIdentTask || latestIdentTask.status !== TASK_STATUS.COMPLETED) {
            if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('需要已完成的辨识任务才能发布', 'warning');
            this.ctx.log('暂无已完成的辨识结果可发布');
            return;
          }
          if (!isIdentTask) {
            if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('只有参数辨识结果才能发布为稳态辨识模型', 'warning');
            return;
          }
          // 文档第 11 节：只有指纹兼容、结果通过验收且未读取参数真值时才允许发布
          const identResult = this.results.get(String(latestIdentTask.id));
          const identSummary = identResult?.resultSummary || identResult || {};
          const identAcceptance = identSummary.acceptance || {};
          const checks = [];
          if (!identAcceptance.formalAccepted) checks.push('结果未通过正式验收');
          if (identSummary.truthWasRead === true) checks.push('结果读取了参数真值');
          if (latestIdentTask.reviewStatus !== TASK_STATUS.REVIEW_APPROVED && latestIdentTask.reviewStatus !== 'review_approved' && latestIdentTask.reviewStatus !== 'approved') {
            checks.push('结果未审核通过');
          }
          if (checks.length > 0) {
            const msg = '发布条件不满足：' + checks.join('；');
            this.ctx.log(msg);
            if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast(msg, 'warning');
            return;
          }
          try {
            await this.ctx.http.results.request(latestIdentTask.id + '/publish', { method: 'POST' });
            latestIdentTask.publicationStatus = TASK_STATUS.PUBLISHED;
            this.ctx.log('已成功发布为当前稳态辨识模型');
            if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('已发布为当前稳态辨识模型', 'success');
            this.render();
          } catch (e) {
            this.ctx.log('发布失败: ' + (e.message || e));
            if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('发布失败: ' + (e.message || e), 'error');
          }
        })
      );
    } else if (isCompleted) {
      btnRow.append(button('设为稳态辨识模型', 'btn-card primary disabled', () => {
        if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('只有参数辨识结果可以发布', 'warning');
      }));
    }
    c3.body.append(btnRow);

    // Card 2 和 Card 3 并排显示
    const c2c3Row = el('div', '');
    c2c3Row.style.cssText = 'display:flex;gap:16px;align-items:flex-start;';
    c2.card.style.flex = '3';
    c3.card.style.flex = '2';
    c2c3Row.append(c2.card, c3.card);

    // Card 4: 追溯与导出
    const c4 = this.createCard(
      '追溯与导出',
      '结果运行后保存输入、模型、配置、日志、图形和报告之间的对应关系。'
    );
    // 根据选中任务的真实数据判断追溯状态和具体内容，优先使用任务实体自带结果
    const traceTask = latestIdentTask;
    const taskTraceResult = traceTask && traceTask.result && traceTask.result.value !== undefined ? traceTask.result.value : traceTask?.result;
    const traceResult = taskTraceResult || (traceTask ? this.results.get(String(traceTask.id)) : null);
    const traceSummary = traceResult?.resultSummary || traceResult || {};
    const traceArtifacts = traceTask ? (this.artifacts.get(String(traceTask.id)) || []) : [];
    const traceAcceptance = traceSummary.acceptance || {};
    const traceInput = traceSummary.input || {};
    const traceTiming = traceSummary.timing || {};

    // 构建四类追溯的具体内容
    const inputDetail = [
      `训练数据：${traceInput.trainingFile || '—'}`,
      `训练工况数：${traceInput.trainingPointCount || '—'}`,
      `测试数据：${traceInput.testFile || '无'}`,
      `测试工况数：${traceInput.testPointCount || '—'}`,
      `进口边界模式：${traceInput.inletBoundaryMode || '—'}`
    ];
    const modelDetail = [
      `正式入口：${traceTask?.entryPoint || traceSummary.program || '—'}`,
      `路由：${traceSummary.route || traceSummary.routeLabel || '—'}`,
      `产物文件：${traceArtifacts.map(a => a.name || a.fileName || a).join('、') || '无'}`
    ];
    const configDetail = [
      `正则化配置：${traceSummary.options ? JSON.stringify(traceSummary.options) : '—'}`,
      `阶段A耗时：${(traceTiming.stageASeconds||0).toFixed(1)} s`,
      `阶段B耗时：${(traceTiming.stageBSeconds||0).toFixed(1)} s`,
      `阶段C耗时：${(traceTiming.stageCSeconds||0).toFixed(1)} s`,
      `阶段D耗时：${(traceTiming.stageDSeconds||0).toFixed(1)} s`
    ];
    const warningText = traceSummary.warnings
      ? (Array.isArray(traceSummary.warnings) ? traceSummary.warnings.join('；') : String(traceSummary.warnings))
      : (traceAcceptance.allStagesConverged ? '无' : '存在未收敛阶段');
    const conclusionDetail = [
      `全部阶段收敛：${traceAcceptance.allStagesConverged ? '是' : '否'}`,
      `正式验收通过：${traceAcceptance.formalAccepted ? '是' : '否'}`,
      `训练回放有效：${traceAcceptance.trainingReplayValid ? '是' : '否'}`,
      `测试回放有效：${traceAcceptance.testReplayValid ? '是' : '否'}`,
      `警告：${warningText}`,
      `任务状态：${this._statusLabel(traceTask?.status)}`,
      `发布状态：${traceTask?.publicationStatus === 'published' ? '已发布' : '未发布'}`
    ];

    const traceItems = [
      { label: '输入可追溯', ok: !!(traceInput.trainingFile || traceInput.testFile), detail: inputDetail },
      { label: '模型可追溯', ok: !!(traceSummary.program || traceTask?.entryPoint), detail: modelDetail },
      { label: '配置可追溯', ok: !!(traceSummary.options || traceSummary.route), detail: configDetail },
      { label: '结论可追溯', ok: !!(traceAcceptance.formalAccepted !== undefined || traceTask?.status === TASK_STATUS.COMPLETED), detail: conclusionDetail }
    ];

    const tRow = el('div', 'reg-method-row');
    tRow.style.marginTop = '0';
    tRow.style.flexWrap = 'wrap';
    traceItems.forEach((t) => {
      const cls = t.ok ? 'field-status ok' : 'field-status optional';
      const text = (t.ok ? '✓ ' : '') + t.label;
      const tag = el('span', cls, text);
      tRow.append(tag);
    });
    c4.body.append(tRow);

    // HTML 追溯报告导出入口放在追溯卡片内
    const c4btns = el('div', 'btn-row');
    c4btns.style.marginTop = '12px';
    c4btns.append(button('结果追溯报告', 'btn-card', () => {
      if (!traceTask) {
        if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('请先选择一条结果记录', 'warning');
        return;
      }
      this._exportHtmlReport(traceTask);
    }));
    c4.body.append(c4btns);

    container.append(c1.card, c2c3Row, c4.card);
  }

  /** 状态标签映射 */
  _statusLabel(status) {
    const map = {
      pending_config: '待配置',
      ready: '就绪',
      workflow_running: '运行中',
      running: '运行中',
      cancelling: '取消中',
      completed: '已完成',
      success: '已完成',
      skipped: '已跳过',
      workflow_failed: '已失败',
      failed: '已失败',
      pending_review: '等待审核'
    };
    return map[status] || status || '待运行';
  }

  /** 从辨识任务构建详情值列表（从真实 result/artifacts 读取） */
  _buildResultDetailValues(task) {
    // 优先从任务实体自带的结果 JSON 读取（后端任务表已记录），未加载再查 this.results
    const taskResult = task.result && task.result.value !== undefined ? task.result.value : task.result;
    const result = taskResult || this.results.get(String(task.id));
    const summary = result?.resultSummary || result || {};
    const artifacts = this.artifacts.get(String(task.id)) || [];
    const acceptance = summary.acceptance || {};
    const timing = summary.timing || {};
    const input = summary.input || {};

    // 输入数据与模型指纹
    const trainFile = input.trainingFile || '—';
    const testFile = input.testFile || '无';
    const trainPoints = input.trainingPointCount || '—';
    const artifactFp = artifacts.length > 0 ? artifacts[0].sha256?.substring(0, 12) + '...' : '—';
    const dllName = input.dllFile || this.workspace?.programName || '—';
    const algoFp = summary.schemaVersion || '—';
    const item1 = `训练: ${trainFile}（${trainPoints}点）, 测试: ${testFile}, DLL: ${dllName}, 算法指纹: ${algoFp}, 产物指纹: ${artifactFp}`;

    // 运行配置与停止原因（文档 11.4：开始时间、结束时间和总运行时间）
    const totalSeconds = (timing.estimationSeconds || 0) + (timing.stageASeconds || 0) + (timing.stageBSeconds || 0)
      + (timing.stageCSeconds || 0) + (timing.stageDSeconds || 0);
    const startStr = task.createdAt ? new Date(Number(task.createdAt)).toLocaleString('zh-CN') : '—';
    const endStr = task.finishedAt ? new Date(Number(task.finishedAt)).toLocaleString('zh-CN') : '—';
    const stopReason = acceptance.allStagesConverged ? '全部阶段达阈值收敛' : '运行后显示';
    const item2 = `开始: ${startStr}, 结束: ${endStr}, ${stopReason}, 总耗时 ${totalSeconds.toFixed(1)} s（A=${(timing.stageASeconds||0).toFixed(1)}, B=${(timing.stageBSeconds||0).toFixed(1)}, C=${(timing.stageCSeconds||0).toFixed(1)}, D=${(timing.stageDSeconds||0).toFixed(1)}）`;

    // 验收状态与复核意见（复核 UI 在 render_results 中单独渲染）
    const formalAccepted = acceptance.formalAccepted ? '验收通过' : '待验收';
    const item3 = `${formalAccepted}（${this._statusLabel(task.status)}）`;

    // 结果文件与图形
    const artifactNames = artifacts.map(a => a.name || a.fileName || String(a)).join(', ') || '运行后生成';
    const item4 = artifactNames;

    // MATLAB 调用方式
    const entryPoint = task.entryPoint || summary.program || '—';
    const item5 = entryPoint;

    // 稳态辨识模型状态
    const published = task.publicationStatus === 'published';
    const item6 = published ? '已发布为当前稳态辨识模型' : (task.status === TASK_STATUS.COMPLETED ? '已完成，待发布' : '运行后显示');

    return [item1, item2, item3, item4, item5, item6];
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

  createFlowStep(badge, label, sublabel, state, clickHandler = null) {
    // state 可以是: 'pending', 'running', 'completed', 'warning', 'failed'
    // 兼容旧的 boolean 参数
    const stateClass = typeof state === 'boolean'
      ? (state ? 'completed' : 'pending')
      : (state || 'pending');
    const step = el('div', 'flow-step ' + stateClass);
    step.append(
      el('div', 'flow-dot', badge),
      el('div', 'flow-label', label),
      el('div', 'flow-sublabel', sublabel)
    );
    step.title = '点击查看阶段日志';
    if (clickHandler) {
      step.style.cursor = 'pointer';
      step.addEventListener('click', clickHandler);
    }
    return step;
  }

  createMetricBox(label, val) {
    const box = el('div', 'metric-box');
    box.append(el('div', 'metric-label', label), el('div', 'metric-val', val));
    return box;
  }

  createEvidenceBox(title, desc, color) {
    const cls = 'evidence-box' + (color ? ` ev-${color}` : '');
    const box = el('div', cls);
    box.append(el('h4', 'evidence-title', title));
    if (desc && typeof desc === 'object' && desc.nodeType) {
      box.append(desc);
    } else {
      box.append(el('p', 'evidence-desc', desc));
    }
    return box;
  }

  createChartCell(title, isRunning) {
    const cell = el('div', 'chart-cell');
    cell.append(el('h4', 'chart-cell-title', title));
    const host = el('div', 'chart-host');
    if (isRunning) {
      host.className = 'chart-host chart-loading';
      const spinner = el('div', 'chart-spinner');
      host.append(spinner);
      host.append(el('span', '', '运行中...'));
    }
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
          this.projectForm.notes = ws.notes || '';
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
    this._unlockIdentify = false;
    this.ctx.log(`启动参数辨识（${actionKey}）...`);
    await this.withLoading('正在提交辨识任务...', async () => {
      try {
        const task = await this.ctx.http.tasks.create({
          workspaceId: this.workspace.id,
          actionKey: actionKey,
          inputs: {
            trainingData: '',
            regularization: this.regConfig
          }
        });
        this.ctx.log(`辨识任务已提交 (ID: ${task.id})`);
        this.tasks.set(task.id, task);
        this.schedulePoll(task.id, 5000);
      } catch (e) {
        this.ctx.log('启动辨识失败: ' + (e.message || e));
        if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('启动辨识失败: ' + (e.message || e), 'error');
      }
    });
  }

  async handleStartIdentifiability() {
    if (!this.workspace) await this.handleCreateProject();
    // 前置校验：需要已完成参数辨识
    if (!this._checkIdentCompleted('可辨识性分析')) return;
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
        this.schedulePoll(task.id, 5000);
      } catch (e) {
        this.ctx.log('启动可辨识性分析失败: ' + (e.message || e));
        if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('启动可辨识性分析失败: ' + (e.message || e), 'error');
      }
    });
  }

  _showUqConfigModal() {
    const overlay = el('div', 'image-modal-overlay');
    const dialog = el('div', 'image-modal');
    dialog.style.maxWidth = '520px';
    const header = el('div', 'image-modal-header');
    const heading = el('h3', '', '评估配置');
    const close = el('button', 'image-modal-close', '✕');
    close.type = 'button';
    close.onclick = () => overlay.remove();
    header.append(heading, close);

    const body = el('div', 'image-modal-body modal-content');
    body.style.padding = '20px 24px';
    body.style.maxHeight = '70vh';
    body.style.overflow = 'auto';

    const cfg = this.uqConfig;
    const fields = [
      { key: 'pilotSampleCount', label: '先导粒子数', hint: '每组精确 SMC 先导粒子数，默认 64' },
      { key: 'pilotReplicateCount', label: '先导随机种子数', hint: '独立先导随机种子数，默认 3' },
      { key: 'formalSampleCount', label: '正式粒子数', hint: '正式精确 SMC 粒子数，默认 256' },
      { key: 'posteriorPredictiveSampleCount', label: '后验预测样本数', hint: '后验预测样本数，默认 256' }
    ];
    fields.forEach(f => {
      const row = el('div', '');
      row.style.cssText = 'margin-bottom:14px;';
      const label = el('label', '');
      label.style.cssText = 'display:block;font-size:12px;font-weight:600;color:var(--text-navy);margin-bottom:4px;';
      label.textContent = f.label;
      row.append(label);
      const input = document.createElement('input');
      input.type = 'number';
      input.value = cfg[f.key];
      input.min = '1';
      input.style.cssText = 'width:100%;padding:6px 8px;border:1px solid var(--line);border-radius:3px;font-size:12px;';
      input.dataset.key = f.key;
      row.append(input);
      const hint = el('p', '');
      hint.style.cssText = 'margin:4px 0 0;font-size:11px;color:var(--muted);';
      hint.textContent = f.hint;
      row.append(hint);
      body.append(row);
    });

    // figureVisible 选择
    const figRow = el('div', '');
    figRow.style.cssText = 'margin-bottom:14px;';
    const figLabel = el('label', '');
    figLabel.style.cssText = 'display:block;font-size:12px;font-weight:600;color:var(--text-navy);margin-bottom:4px;';
    figLabel.textContent = '图形显示';
    figRow.append(figLabel);
    const figSel = document.createElement('select');
    figSel.style.cssText = 'width:100%;padding:6px 8px;border:1px solid var(--line);border-radius:3px;font-size:12px;';
    [['off', '关闭（推荐）'], ['on', '开启']].forEach(([v, t]) => {
      const opt = document.createElement('option');
      opt.value = v;
      opt.textContent = t;
      if (cfg.figureVisible === v) opt.selected = true;
      figSel.append(opt);
    });
    figRow.append(figSel);
    body.append(figRow);

    // 确认按钮
    const btnRow = el('div', 'btn-row');
    btnRow.style.cssText = 'margin-top:16px;text-align:right;';
    const confirmBtn = button('确认', 'btn-card', () => {
      body.querySelectorAll('input[type=number]').forEach(inp => {
        const k = inp.dataset.key;
        const v = parseInt(inp.value, 10);
        if (!isNaN(v) && v > 0) cfg[k] = v;
      });
      cfg.figureVisible = figSel.value;
      overlay.remove();
      this.ctx.log(`评估配置已更新：粒子数=${cfg.formalSampleCount}, 先导=${cfg.pilotSampleCount}×${cfg.pilotReplicateCount}, 预测=${cfg.posteriorPredictiveSampleCount}, 图形=${cfg.figureVisible}`);
      if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('评估配置已保存', 'success');
    });
    confirmBtn.classList.add('primary');
    btnRow.append(confirmBtn);
    body.append(btnRow);

    dialog.append(header, body);
    overlay.append(dialog);
    overlay.onclick = (e) => { if (e.target === overlay) overlay.remove(); };
    (this.ctx.shadow || this.mount).appendChild(overlay);
  }

  async handleStartUq() {
    if (!this.workspace) await this.handleCreateProject();
    // 前置校验：需要已完成参数辨识
    if (!this._checkIdentCompleted('不确定性评估')) return;
    const actionKey = this.activeUqMethod === 'B' ? 'uqMethodB' : 'uqMethodA';
    this.ctx.log(`启动不确定性评估（${actionKey}）...`);
    this._smcReplicate = 0;
    this._lastBeta = 0;
    this._uqStep = 0;
    await this.withLoading('正在提交不确定性评估...', async () => {
      try {
        const task = await this.ctx.http.tasks.create({
          workspaceId: this.workspace.id,
          actionKey: actionKey,
          inputs: { userCfg: { ...this.uqConfig } }
        });
        this.ctx.log(`不确定性评估任务已提交 (ID: ${task.id})`);
        this.tasks.set(task.id, task);
        this.schedulePoll(task.id, 5000);
      } catch (e) {
        this.ctx.log('启动评估失败: ' + (e.message || e));
        if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('启动评估失败: ' + (e.message || e), 'error');
      }
    });
  }

  _showPredictionModelModal() {
    const identTask = this.latestIdentifyTask();
    const identDone = identTask?.status === TASK_STATUS.COMPLETED;
    const uqTaskA = this.latestTask('uqMethodA');
    const uqTaskB = this.latestTask('uqMethodB');
    const uqADone = uqTaskA?.status === TASK_STATUS.COMPLETED;
    const uqBDone = uqTaskB?.status === TASK_STATUS.COMPLETED;

    const overlay = el('div', 'image-modal-overlay');
    const dialog = el('div', 'image-modal');
    dialog.style.maxWidth = '480px';
    const header = el('div', 'image-modal-header');
    const heading = el('h3', '', '选择预测模型');
    const close = el('button', 'image-modal-close', '✕');
    close.type = 'button';
    header.append(heading, close);
    dialog.append(header);

    const body = el('div', '');
    body.style.cssText = 'padding:16px;';

    // 第一组：选择模型
    const modelTitle = el('div', '');
    modelTitle.style.cssText = 'font-weight:600;font-size:13px;margin-bottom:8px;';
    modelTitle.textContent = '预测模型';
    body.append(modelTitle);

    const modelOpts = [
      { value: 'corrected', label: '稳态辨识模型（D阶段后）', desc: '修正后的最终模型', enabled: identDone },
      { value: 'baseline', label: '零修正基准模型（A阶段前）', desc: '修正前的原始模型', enabled: true }
    ];
    modelOpts.forEach(opt => {
      const row = el('label', '');
      row.style.cssText = `display:flex;align-items:flex-start;gap:10px;padding:10px;border:1px solid var(--line);border-radius:4px;margin-bottom:8px;${opt.enabled ? 'cursor:pointer;' : 'opacity:0.5;cursor:not-allowed;'}`;
      const radio = el('input', '');
      radio.type = 'radio';
      radio.name = 'pred-model';
      radio.value = opt.value;
      if (!opt.enabled) radio.disabled = true;
      if (this.activePredictionModel === opt.value || (!this.activePredictionModel && opt.value === 'corrected')) radio.checked = true;
      radio.style.marginTop = '3px';
      const textWrap = el('div', '');
      textWrap.style.flex = '1';
      textWrap.append(el('div', '', opt.label));
      const d = el('div', '');
      d.style.cssText = 'font-size:11px;color:var(--muted);margin-top:2px;';
      d.textContent = opt.enabled ? opt.desc : (opt.value === 'corrected' ? '请先完成参数辨识' : opt.desc);
      textWrap.append(d);
      row.append(radio, textWrap);
      body.append(row);
    });

    // 第二组：后验来源（仅稳态辨识模型可选）
    const posteriorTitle = el('div', '');
    posteriorTitle.style.cssText = 'font-weight:600;font-size:13px;margin:12px 0 8px;';
    posteriorTitle.textContent = '后验区间来源（可选）';
    body.append(posteriorTitle);

    const postDesc = el('p', 'card-subtitle', '选择后验来源后，预测同时输出95%置信区间。不选则只输出确定性预测。');
    postDesc.style.cssText = 'margin:0 0 8px;font-size:11px;color:var(--muted);';
    body.append(postDesc);

    const postOpts = [
      { value: 'none', label: '不使用后验（仅确定性预测）', enabled: true },
      { value: 'A', label: '方法 A — 关键修正系数后验', enabled: uqADone },
      { value: 'B', label: '方法 B — 全修正系数后验', enabled: uqBDone }
    ];
    postOpts.forEach(opt => {
      const row = el('label', '');
      row.style.cssText = `display:flex;align-items:center;gap:10px;padding:8px;border:1px solid var(--line);border-radius:4px;margin-bottom:6px;${opt.enabled ? 'cursor:pointer;' : 'opacity:0.5;cursor:not-allowed;'}`;
      const radio = el('input', '');
      radio.type = 'radio';
      radio.name = 'pred-posterior';
      radio.value = opt.value;
      if (!opt.enabled) radio.disabled = true;
      if ((this._predictionPosterior || 'none') === opt.value) radio.checked = true;
      radio.style.marginTop = '2px';
      const textWrap = el('div', '');
      textWrap.style.flex = '1';
      textWrap.append(el('div', '', opt.label));
      if (opt.value !== 'none' && !opt.enabled) {
        const d = el('div', '');
        d.style.cssText = 'font-size:11px;color:var(--muted);margin-top:2px;';
        d.textContent = '请先完成对应不确定性评估';
        textWrap.append(d);
      }
      row.append(radio, textWrap);
      body.append(row);
    });

    const btnRow = el('div', '');
    btnRow.style.cssText = 'display:flex;justify-content:flex-end;gap:8px;margin-top:12px;';
    const cancelBtn = button('取消', 'btn-card', () => overlay.remove());
    const confirmBtn = button('确认选择', 'btn-card primary', () => {
      const modelSelected = body.querySelector('input[name="pred-model"]:checked');
      const postSelected = body.querySelector('input[name="pred-posterior"]:checked');
      if (modelSelected) this.activePredictionModel = modelSelected.value;
      if (postSelected) this._predictionPosterior = postSelected.value;
      const modelLabel = this.activePredictionModel === 'baseline' ? '零修正基准模型' : '稳态辨识模型';
      const postLabel = this._predictionPosterior === 'none' ? '仅确定性预测' : `方法${this._predictionPosterior}后验区间`;
      this.ctx.log(`已选择预测模型：${modelLabel}，${postLabel}`);
      if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast(`已选择：${modelLabel} · ${postLabel}`, 'success');
      overlay.remove();
      this.render();
    });
    btnRow.append(cancelBtn, confirmBtn);
    body.append(btnRow);
    dialog.append(body);
    overlay.append(dialog);
    overlay.onclick = (e) => { if (e.target === overlay) overlay.remove(); };
    close.onclick = () => overlay.remove();
    (this.ctx.shadow || this.mount).appendChild(overlay);
  }

  /** 前置校验：检查参数辨识是否已完成 */
  _checkIdentCompleted(actionName) {
    const identTask = this.latestIdentifyTask();
    if (!identTask || identTask.status !== TASK_STATUS.COMPLETED) {
      const msg = `请先完成参数辨识后再执行${actionName}`;
      this.ctx.log(msg);
      if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast(msg, 'warning');
      return false;
    }
    return true;
  }

  _autoSelectValidationInputs() {
    const identTask = this.latestIdentifyTask();
    if (!identTask || identTask.status !== TASK_STATUS.COMPLETED) {
      if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('请先完成参数辨识', 'warning');
      this.ctx.log('请先完成参数辨识后再选择辨识结果');
      return;
    }
    const identResult = this.results.get(String(identTask.id));
    const modelName = identResult?.resultSummary?.steadyModelName || '稳态辨识模型（最新）';
    const testDataName = this.workspace?.testDataFile || '';
    this._validationModel = modelName;
    this._validationTestData = testDataName;
    this.ctx.log(`已选择辨识结果：${modelName}，测试数据：${testDataName}`);
    if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('已自动选择稳态辨识模型和测试数据', 'success');
    this.render();
  }

  async handleStartValidation() {
    if (!this.workspace) await this.handleCreateProject();
    // 前置校验：需要已完成参数辨识
    if (!this._checkIdentCompleted('测试验证')) return;
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
        this.schedulePoll(task.id, 5000);
      } catch (e) {
        this.ctx.log('启动测试验证失败: ' + (e.message || e));
        if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('启动测试验证失败: ' + (e.message || e), 'error');
      }
    });
  }

  async handleStartPrediction() {
    if (!this.workspace) await this.handleCreateProject();
    // 前置校验：需要已完成参数辨识
    if (!this._checkIdentCompleted('工况预测')) return;
    // 如果选了后验，还需要对应的 UQ 已完成
    if (this._predictionPosterior && this._predictionPosterior !== 'none') {
      const uqActionKey = this._predictionPosterior === 'B' ? 'uqMethodB' : 'uqMethodA';
      const uqTask = this.latestTask(uqActionKey);
      if (!uqTask || uqTask.status !== TASK_STATUS.COMPLETED) {
        const uqLabel = this._predictionPosterior === 'B' ? '全修正系数评估（方法B）' : '关键修正系数评估（方法A）';
        const msg = `选择后验区间需要先完成${uqLabel}`;
        this.ctx.log(msg);
        if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast(msg, 'warning');
        return;
      }
    }
    this.ctx.log('启动单工况预测计算...');
    await this.withLoading('正在提交预测计算...', async () => {
      try {
        const npInit = this.predInputs.npInitial;
        const hasNpInit = npInit !== '' && npInit != null && isFinite(Number(npInit)) && Number(npInit) > 0;
        const modelInput = {
          point_id: this.predInputs.pointId || 'PRED_PT_1',
          inletBoundaryMode: this.predictionMode === 'pressure' ? 2 : 3,
          Pamb: this.predInputs.pamb,
          Altitude: this.predInputs.altitude,
          Tamb: this.predInputs.tamb,
          Mach: this.predInputs.mach,
          Wf_model: this.predInputs.wf,
          Mkp: this.predInputs.mkp,
          Mkg: this.predInputs.mkg
        };
        if (hasNpInit) modelInput.Np_initial = Number(npInit);
        const task = await this.ctx.http.tasks.create({
          workspaceId: this.workspace.id,
          actionKey: 'operatingPointPrediction',
          inputs: {
            modelInput,
            estimationResultFile: '',
            posteriorOptions: this._predictionPosterior && this._predictionPosterior !== 'none'
              ? { method: this._predictionPosterior, runId: 'latest' }
              : null
          }
        });
        this.ctx.log(`工况预测任务已提交 (ID: ${task.id})`);
        this.tasks.set(task.id, task);
        this.schedulePoll(task.id, 5000);
      } catch (e) {
        this.ctx.log('工况预测失败: ' + (e.message || e));
        if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('工况预测失败: ' + (e.message || e), 'error');
      }
    });
  }

  _openResultsDirectory() {
    if (!this.workspace) {
      if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('请先创建项目', 'warning');
      return;
    }
    // 确定要打开的任务：优先选中的，否则最新完成的
    let taskId = this._selectedResultTaskId;
    if (!taskId) {
      const identTask = this.latestIdentifyTask();
      if (identTask) taskId = String(identTask.id);
    }
    if (!taskId) {
      this.ctx.log('暂无任务结果目录可打开');
      if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('暂无任务结果目录', 'info');
      return;
    }
    // 列出产物文件
    const artifacts = this.artifacts.get(taskId) || [];
    if (artifacts.length === 0) {
      this.ctx.log(`任务 ${taskId} 暂无产物文件`);
      if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('该任务暂无产物文件', 'info');
      return;
    }
    // 弹窗展示产物列表，支持下载
    this._showArtifactsModal(taskId, artifacts);
  }

  _showArtifactsModal(taskId, artifacts) {
    const overlay = el('div', 'image-modal-overlay');
    const dialog = el('div', 'image-modal');
    dialog.style.maxWidth = '560px';
    const header = el('div', 'image-modal-header');
    const heading = el('h3', '', '结果产物目录');
    const close = el('button', 'image-modal-close', '✕');
    close.type = 'button';
    header.append(heading, close);
    dialog.append(header);

    const body = el('div', '');
    body.style.cssText = 'padding:16px;max-height:400px;overflow-y:auto;';
    const desc = el('p', 'card-subtitle', `任务 ${taskId} 的产物文件：`);
    desc.style.margin = '0 0 12px';
    body.append(desc);

    artifacts.forEach(a => {
      const name = a.name || a.fileName || String(a);
      const size = a.size ? `（${this._formatFileSize(a.size)}）` : '';
      const row = el('div', '');
      row.style.cssText = 'display:flex;align-items:center;justify-content:space-between;padding:8px 0;border-bottom:1px solid var(--line);';
      const nameEl = el('span', '');
      nameEl.style.cssText = 'font-size:12px;color:var(--text);';
      nameEl.textContent = name + size;
      const dlBtn = button('下载', 'btn-table', () => this._downloadArtifact(taskId, a));
      row.append(nameEl, dlBtn);
      body.append(row);
    });

    dialog.append(body);
    overlay.append(dialog);
    overlay.onclick = (e) => { if (e.target === overlay) overlay.remove(); };
    close.onclick = () => overlay.remove();
    (this.ctx.shadow || this.mount).appendChild(overlay);
  }

  _formatFileSize(bytes) {
    if (bytes < 1024) return bytes + ' B';
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
    return (bytes / 1024 / 1024).toFixed(1) + ' MB';
  }

  async _downloadArtifact(taskId, artifact) {
    const artifactId = artifact.id || artifact.name || artifact.fileName || String(artifact);
    const fileName = artifact.name || artifact.fileName || artifactId;
    this.ctx.log(`正在下载产物: ${artifactId}`);
    try {
      if (this.ctx.http && this.ctx.http.artifacts && this.ctx.http.artifacts.download) {
        await this.ctx.http.artifacts.download(`${taskId}/${artifactId}`, fileName);
        this.ctx.log(`已下载: ${fileName}`);
      }
    } catch (e) {
      this.ctx.log('下载失败: ' + (e.message || e));
      if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('下载失败: ' + (e.message || e), 'error');
    }
  }

  async handleExportResults() {
    if (!this.workspace) {
      if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('请先创建项目', 'warning');
      return;
    }
    // 确定要导出的任务：优先选中的，否则最新完成的辨识任务
    let task;
    if (this._selectedResultTaskId) {
      task = this.tasks.get(this._selectedResultTaskId);
    }
    if (!task) {
      task = this.latestIdentifyTask();
    }
    if (!task) {
      this.ctx.log('暂无任务可导出');
      if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('暂无任务可导出', 'info');
      return;
    }

    this.ctx.log(`正在导出任务 ${task.id} 的 ZIP 产物包...`);

    // 1. 调后端打包接口下载 ZIP（含 result.json、run.log、artifacts.json 及全部产物文件）
    try {
      if (this.ctx.http && this.ctx.http.artifacts && this.ctx.http.artifacts.download) {
        await this.ctx.http.artifacts.download(`${task.id}/package`, `workflow_task_${task.id}.zip`);
        this.ctx.log(`已下载 ZIP 包：workflow_task_${task.id}.zip`);
      }
    } catch (e) {
      this.ctx.log('下载 ZIP 包失败: ' + (e.message || e));
    }

    this.ctx.log(`导出完成：ZIP 产物包`);
    if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('已导出 ZIP 产物包', 'success');
  }

  /** 导出 HTML 追溯报告 */
  _exportHtmlReport(task) {
    const result = this.results.get(String(task.id));
    const summary = result?.resultSummary || result || {};
    const acceptance = summary.acceptance || {};
    const timing = summary.timing || {};
    const input = summary.input || {};
    let artifacts = this.artifacts.get(String(task.id)) || [];

    const PDFGen = window.CommonUtils && window.CommonUtils.LocalPDFGenerator;
    if (PDFGen) {
      const pdf = new PDFGen();
      pdf.addTitle('结果追溯报告');
      pdf.addText(`项目：${this.workspace?.jobName || this.workspace?.id || '—'}`, 12);
      pdf.addText(`保存目录（虚拟盘映射源）：${this.workspace?.workspaceDir || '—'}`, 12);
      pdf.addText(`生成时间：${new Date().toLocaleString('zh-CN')}`, 12);
      pdf.addSeparator();

      pdf.addSubtitle('1. 任务类型、正式入口和模型路径');
      pdf.addText(`任务类型：${task.actionKey}`, 12);
      pdf.addText(`正式入口：${task.entryPoint || summary.program || '—'}`, 12);
      pdf.addText(`模型路径：${summary.route || summary.routeLabel || '—'}`, 12);
      pdf.addSeparator();

      pdf.addSubtitle('2. 训练/测试数据、DLL、配置和算法指纹');
      pdf.addText(`训练数据：${input.trainingFile || '—'}（${input.trainingPointCount || '—'} 工况）`, 12);
      pdf.addText(`测试数据：${input.testFile || '无'}（${input.testPointCount || '—'} 工况）`, 12);
      pdf.addText(`进口边界模式：${input.inletBoundaryMode || '—'}`, 12);
      pdf.addText(`产物文件数：${artifacts.length}`, 12);
      if (artifacts.length > 0) {
        pdf.addTable(
          ['文件名', '大小', 'SHA256'],
          artifacts.map(a => [
            a.name || a.fileName || String(a),
            a.size ? this._formatFileSize(a.size) : '—',
            a.sha256 || '—'
          ])
        );
      }
      pdf.addSeparator();

      pdf.addSubtitle('3. 正则化及后验运行配置');
      pdf.addText('配置：', 11);
      pdf.addCodeBlock(summary.options ? JSON.stringify(summary.options, null, 2) : '—');
      pdf.addText(`阶段A耗时：${(timing.stageASeconds||0).toFixed(1)} s`, 12);
      pdf.addText(`阶段B耗时：${(timing.stageBSeconds||0).toFixed(1)} s`, 12);
      pdf.addText(`阶段C耗时：${(timing.stageCSeconds||0).toFixed(1)} s`, 12);
      pdf.addText(`阶段D耗时：${(timing.stageDSeconds||0).toFixed(1)} s`, 12);
      const totalEst = (timing.estimationSeconds||0)+(timing.stageASeconds||0)+(timing.stageBSeconds||0)+(timing.stageCSeconds||0)+(timing.stageDSeconds||0);
      pdf.addText(`总耗时：${totalEst.toFixed(1)} s`, 12);
      pdf.addSeparator();

      pdf.addSubtitle('4. 开始时间、结束时间和总运行时间');
      pdf.addText(`开始时间：${task.createdAt ? new Date(Number(task.createdAt)).toLocaleString('zh-CN') : '—'}`, 12);
      const endTime = task.finishedAt || result?.completedAt;
      pdf.addText(`结束时间：${endTime ? new Date(Number(endTime)).toLocaleString('zh-CN') : '—'}`, 12);
      const totalRun = (task.createdAt && endTime) ? Math.round((Number(endTime) - Number(task.createdAt)) / 1000) : 0;
      pdf.addText(`总运行时间：${totalRun} 秒`, 12);
      pdf.addSeparator();

      pdf.addSubtitle('5. MAT、Excel、摘要、日志和图形文件');
      if (artifacts.length === 0) {
        pdf.addText('无产物文件', 12);
      } else {
        pdf.addTable(
          ['文件名', '大小', '修改时间'],
          artifacts.map(a => [
            a.name || a.fileName || String(a),
            a.size ? this._formatFileSize(a.size) : '—',
            a.modifiedAt ? new Date(a.modifiedAt).toLocaleString('zh-CN', { hour12: false }) : '—'
          ])
        );
      }
      pdf.addSeparator();

      pdf.addSubtitle('6. 收敛、验收、警告和审核状态');
      const warnings = summary.warnings
        ? (Array.isArray(summary.warnings) ? summary.warnings.join('；') : String(summary.warnings))
        : (acceptance.allStagesConverged ? '无' : '存在未收敛阶段');
      pdf.addTable(
        ['检查项', '状态'],
        [
          ['全部阶段收敛', acceptance.allStagesConverged ? '是' : '否'],
          ['阶段A收敛', acceptance.stageAConverged ? '是' : '否'],
          ['阶段B收敛', acceptance.stageBAllConverged ? '是' : '否'],
          ['阶段D收敛', acceptance.stageDConverged ? '是' : '否'],
          ['正式验收通过', acceptance.formalAccepted ? '是' : '否'],
          ['训练回放有效', acceptance.trainingReplayValid ? '是' : '否'],
          ['测试回放有效', acceptance.testReplayValid ? '是' : '否'],
          ['警告', warnings],
          ['任务状态', this._statusLabel(task.status)],
          ['审核状态', task.reviewStatus || '待审核'],
          ['发布状态', task.publicationStatus === 'published' ? '已发布' : '未发布']
        ]
      );

      pdf.addWatermark();
      const htmlContent = pdf.generateHTML();
      this._openPrintPreview(htmlContent, `结果追溯报告_${task.actionKey}_${task.id}.html`);
    } else {
      const html = this._buildSimpleHtmlReport(task, summary, artifacts, acceptance, timing, input, result);
      this._openPrintPreview(html, `结果追溯报告_${task.actionKey}_${task.id}.html`);
    }

    this.ctx.log('正在打开结果追溯报告打印预览...');
    if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('正在打开结果追溯报告打印预览，请在弹窗中选择保存为PDF', 'success');
  }

  /** 打印预览；若弹窗被阻止则降级为 HTML 下载 */
  _openPrintPreview(html, fileName) {
    const printWindow = window.open('', '_blank');
    if (printWindow && printWindow.document) {
      printWindow.document.write(html);
      printWindow.document.close();
      printWindow.onload = () => {
        printWindow.print();
        printWindow.onafterprint = () => { printWindow.close(); };
        setTimeout(() => { if (!printWindow.closed) printWindow.close(); }, 30000);
      };
    } else {
      const blob = new Blob([html], { type: 'text/html;charset=utf-8' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = fileName;
      a.click();
      URL.revokeObjectURL(url);
    }
  }

  /** 降级用的简单 HTML 报告 */
  _buildSimpleHtmlReport(task, summary, artifacts, acceptance, timing, input, result) {
    const esc = s => String(s || '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
    const warningText = summary.warnings
        ? (Array.isArray(summary.warnings) ? summary.warnings.join('；') : String(summary.warnings))
        : (acceptance.allStagesConverged ? '无' : '存在未收敛阶段');
    const rows = artifacts.map(a => `<tr><td>${esc(a.name||a.fileName)}</td><td>${a.size?this._formatFileSize(a.size):'—'}</td><td>${esc(a.sha256||'—')}</td></tr>`).join('');
    return `<!DOCTYPE html><html><head><meta charset="UTF-8"><title>结果追溯报告</title>
<style>body{font-family:SimSun,Microsoft YaHei,Arial,sans-serif;font-size:12pt;margin:40px;line-height:1.5}
table{width:100%;border-collapse:collapse;margin:10px 0;table-layout:fixed}th,td{border:1px solid #ddd;padding:8px;word-break:break-all}th{background:#f2f2f2}
h1{text-align:center}h2{font-size:14pt;border-bottom:1px solid #999;padding-bottom:5px}</style></head><body>
<h1>结果追溯报告</h1>
<p>项目：${esc(this.workspace?.jobName || this.workspace?.id)}　保存目录（虚拟盘映射源）：${esc(this.workspace?.workspaceDir || '—')}　生成时间：${new Date().toLocaleString('zh-CN')}</p>
<h2>1. 任务类型、正式入口和模型路径</h2>
<p>任务类型：${esc(task.actionKey)}<br>正式入口：${esc(task.entryPoint || summary.program)}<br>模型路径：${esc(summary.route || summary.routeLabel)}</p>
<h2>2. 训练/测试数据、DLL、配置和算法指纹</h2>
<p>训练数据：${esc(input.trainingFile)}（${input.trainingPointCount||'—'} 工况）<br>测试数据：${esc(input.testFile||'无')}（${input.testPointCount||'—'} 工况）<br>进口边界模式：${input.inletBoundaryMode||'—'}</p>
<table><tr><th>文件名</th><th>大小</th><th>SHA256</th></tr>${rows}</table>
<h2>3. 正则化及后验运行配置</h2>
<p>配置：${esc(summary.options?JSON.stringify(summary.options):'—')}</p>
<p>阶段A：${(timing.stageASeconds||0).toFixed(1)}s　阶段B：${(timing.stageBSeconds||0).toFixed(1)}s　阶段C：${(timing.stageCSeconds||0).toFixed(1)}s　阶段D：${(timing.stageDSeconds||0).toFixed(1)}s</p>
<h2>4. 开始时间、结束时间和总运行时间</h2>
<p>开始：${task.createdAt?new Date(Number(task.createdAt)).toLocaleString('zh-CN'):'—'}　结束：${(task.finishedAt||result?.completedAt)?new Date(Number(task.finishedAt||result.completedAt)).toLocaleString('zh-CN'):'—'}</p>
<h2>5. MAT、Excel、摘要、日志和图形文件</h2>
<table><tr><th>文件名</th><th>大小</th><th>SHA256</th></tr>${rows}</table>
<h2>6. 收敛、验收、警告和审核状态</h2>
<table><tr><th>检查项</th><th>状态</th></tr>
<tr><td>全部阶段收敛</td><td>${acceptance.allStagesConverged?'是':'否'}</td></tr>
<tr><td>阶段A收敛</td><td>${acceptance.stageAConverged?'是':'否'}</td></tr>
<tr><td>阶段B收敛</td><td>${acceptance.stageBAllConverged?'是':'否'}</td></tr>
<tr><td>阶段D收敛</td><td>${acceptance.stageDConverged?'是':'否'}</td></tr>
<tr><td>正式验收通过</td><td>${acceptance.formalAccepted?'是':'否'}</td></tr>
<tr><td>训练回放有效</td><td>${acceptance.trainingReplayValid?'是':'否'}</td></tr>
<tr><td>测试回放有效</td><td>${acceptance.testReplayValid?'是':'否'}</td></tr>
<tr><td>警告</td><td>${esc(warningText)}</td></tr>
<tr><td>任务状态</td><td>${esc(this._statusLabel(task.status))}</td></tr>
<tr><td>审核状态</td><td>${esc(task.reviewStatus||'待审核')}</td></tr>
<tr><td>发布状态</td><td>${task.publicationStatus==='published'?'已发布':'未发布'}</td></tr>
</table></body></html>`;
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

  renderValidationComparisonChart(host, outputName, valResult) {
    if (!this.ctx.echarts || !host) return;
    const chart = this.ctx.echarts.init(host, null, { renderer: 'canvas' });

    // 从 valResult.predictionTable 读取真实数据
    // MATLAB table 经 local_summarize 后为 { kind:'table', columns:[...], rowCount:N, rows:[...] }
    // predictionTable 每行: { point_id, field, measured, baseline_model, corrected_model, ... }
    // 瞬态路线 field 用 dNp_dt/dNg_dt，稳态路线用 Np/Ng
    const summary = valResult?.resultSummary || valResult || {};
    const predTable = summary.predictionTable;
    // rows 可能是数组（多行）或单个对象（rowCount=1 时）
    let allRows = [];
    if (predTable) {
      if (Array.isArray(predTable.rows)) allRows = predTable.rows;
      else if (predTable.rows && typeof predTable.rows === 'object') allRows = [predTable.rows];
    }
    // 输出名 → predictionTable field 名映射
    const fieldMap = { 'Np': ['Np', 'dNp_dt', 'Np_rpm'], 'Ng': ['Ng', 'dNg_dt', 'Ng_rpm'],
      'Pt3': ['Pt3', 'Pt3_Pa'], 'Tt3': ['Tt3', 'Tt3_K'], 'Tt45': ['Tt45', 'Tt45_K'], 'Pt45': ['Pt45', 'Pt45_Pa'] };
    const fieldNames = fieldMap[outputName] || [outputName];
    const rows = allRows.filter(r => fieldNames.includes(r.field));

    const pts = rows.map(r => r.point_id || '');
    const measured = rows.map(r => Number(r.measured));
    const zeroModel = rows.map(r => Number(r.baseline_model));
    const adaptModel = rows.map(r => Number(r.corrected_model));

    chart.setOption({
      animation: false,
      legend: { data: ['零修正模型', '稳态辨识模型', '测量值'], left: 'center', bottom: 0, textStyle: { fontSize: 9 } },
      grid: { left: 40, right: 15, top: 15, bottom: 45 },
      xAxis: { type: 'category', data: pts, axisLabel: { fontSize: 10 } },
      yAxis: { type: 'value', scale: true, axisLabel: { fontSize: 10 } },
      series: [
        { name: '零修正模型', type: 'line', data: zeroModel, lineStyle: { color: '#c05050', width: 1.5 }, symbol: 'none' },
        { name: '稳态辨识模型', type: 'line', data: adaptModel, lineStyle: { color: '#2b6b95', width: 2 }, symbol: 'circle', symbolSize: 4 },
        { name: '测量值', type: 'line', data: measured, lineStyle: { color: '#000000', width: 1.5 }, symbol: 'diamond', symbolSize: 5 }
      ]
    });
    this.charts.push(chart);
  }

  renderPredictionDeterministicChart(host, outputName, detVal) {
    if (!this.ctx.echarts || !host) return;
    const chart = this.ctx.echarts.init(host, null, { renderer: 'canvas' });
    chart.setOption({
      animation: false,
      legend: { data: ['稳态辨识模型'], left: 'center', bottom: 0, textStyle: { fontSize: 9 } },
      grid: { left: 15, right: 15, top: 5, bottom: 60 },
      xAxis: { type: 'value', scale: true, splitLine: { show: false }, axisLabel: { fontSize: 9 } },
      yAxis: { type: 'category', data: ['新工况'], axisLabel: { show: false }, axisTick: { show: false }, axisLine: { show: false } },
      series: [
        { name: '稳态辨识模型', type: 'scatter', data: [[Number(detVal), 0]], itemStyle: { color: '#d04e4e' }, symbol: 'rect', symbolSize: [2, 18] }
      ]
    });
    this.charts.push(chart);
  }

  renderPredictionIntervalChart(host, outputName, row) {
    if (!this.ctx.echarts || !host) return;
    const chart = this.ctx.echarts.init(host, null, { renderer: 'canvas' });
    const label = row.point_id || '新工况';
    const unit = row.unit || '';
    const lower = Number(row.model_lower);
    const upper = Number(row.model_upper);
    const center = Number(row.model_median);
    const det = Number(row.deterministic_frozen_model);
    const yData = [label];
    const hasInterval = isFinite(lower) && isFinite(upper) && isFinite(center) && upper >= lower;
    const tooltip = hasInterval
      ? `${outputName}${unit ? ` (${unit})` : ''}<br/>95%置信区间：[${lower.toFixed(2)}, ${upper.toFixed(2)}]<br/>后验中心：${center.toFixed(2)}<br/>稳态辨识模型：${isFinite(det) ? det.toFixed(2) : '—'}`
      : `${outputName}${unit ? ` (${unit})` : ''}<br/>稳态辨识模型：${isFinite(det) ? det.toFixed(2) : '—'}`;

    const series = [];
    if (hasInterval) {
      series.push(
        { name: '95%置信区间', type: 'bar', stack: 'interval', data: [lower], itemStyle: { color: 'transparent' }, silent: true, emphasis: { disabled: true }, z: 1 },
        { name: '95%置信区间', type: 'bar', stack: 'interval', data: [upper - lower], itemStyle: { color: 'rgba(60, 140, 190, 0.55)' }, barWidth: 12, emphasis: { disabled: true }, z: 2 },
        { name: '后验中心', type: 'scatter', data: [[center, 0]], symbol: 'circle', symbolSize: 9, itemStyle: { color: '#fff', borderColor: '#2b6b95', borderWidth: 2 }, z: 3 }
      );
    }
    if (isFinite(det)) {
      series.push({ name: '稳态辨识模型', type: 'scatter', data: [[det, 0]], symbol: 'rect', symbolSize: [2, 18], itemStyle: { color: '#d04e4e' }, z: 4 });
    }

    chart.setOption({
      animation: false,
      tooltip: { trigger: 'axis', formatter: () => tooltip },
      legend: { data: hasInterval ? ['95%置信区间', '后验中心', '稳态辨识模型'] : ['稳态辨识模型'], left: 'center', bottom: 0, textStyle: { fontSize: 9 } },
      grid: { left: 15, right: 15, top: 5, bottom: 60 },
      xAxis: { type: 'value', scale: true, splitLine: { show: false }, axisLabel: { fontSize: 9 } },
      yAxis: { type: 'category', data: yData, axisLabel: { show: false }, axisTick: { show: false }, axisLine: { show: false } },
      series
    });
    this.charts.push(chart);
  }

  /* 参数 95% 置信区间图：水平误差条 */
  renderUqParameterChart(host, rows) {
    if (!this.ctx.echarts || !host) return;
    const chart = this.ctx.echarts.init(host, null, { renderer: 'canvas' });
    const yData = rows.map(r => r.name || r.parameter || '');
    const lower = rows.map(r => Number(r.q025 || 0));
    const width = rows.map(r => Number(r.q975 || r.q025 || 0) - Number(r.q025 || 0));
    const center = rows.map((r, i) => [Number(r.posterior_median != null ? r.posterior_median : (r.posterior_mean || 0)), i]);
    const ident = rows.map((r, i) => [Number(r.deterministic_estimate || 0), i]);

    chart.setOption({
      animation: false,
      tooltip: {
        trigger: 'axis',
        axisPointer: { type: 'shadow' },
        formatter: (params) => {
          const i = params[0].dataIndex;
          const r = rows[i];
          if (!r) return '';
          return `<div style="font-size:12px">${r.name}</div>` +
            `<div style="font-size:11px;color:#666">95%区间：[${Number(r.q025).toFixed(4)}, ${Number(r.q975).toFixed(4)}]</div>` +
            `<div style="font-size:11px;color:#666">后验中心：${Number(r.posterior_median != null ? r.posterior_median : r.posterior_mean).toFixed(4)}</div>` +
            `<div style="font-size:11px;color:#666">辨识结果：${Number(r.deterministic_estimate).toFixed(4)}</div>`;
        }
      },
      legend: { data: ['95%置信区间', '后验中心', '修正系数辨识结果'], left: 'center', bottom: 0, itemGap: 16, textStyle: { fontSize: 11 } },
      grid: { left: 110, right: 30, top: 10, bottom: 55 },
      xAxis: { type: 'value', scale: true, splitLine: { show: true, lineStyle: { color: '#f0f0f0' } }, axisLabel: { fontSize: 10 } },
      yAxis: { type: 'category', data: yData, inverse: true, axisLabel: { fontSize: 10 }, axisLine: { show: false }, axisTick: { show: false } },
      series: [
        { name: '置信下界', type: 'bar', stack: 'interval', data: lower, itemStyle: { color: 'transparent' }, silent: true, emphasis: { disabled: true }, z: 1 },
        { name: '95%置信区间', type: 'bar', stack: 'interval', data: width, itemStyle: { color: 'rgba(60, 140, 190, 0.55)' }, barWidth: 10, emphasis: { disabled: true }, z: 2 },
        { name: '后验中心', type: 'scatter', data: center, symbol: 'circle', symbolSize: 8, itemStyle: { color: '#fff', borderColor: '#2b6b95', borderWidth: 2 }, z: 3 },
        { name: '修正系数辨识结果', type: 'scatter', data: ident, symbol: 'rect', symbolSize: [2, 14], itemStyle: { color: '#d04e4e' }, z: 4 }
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

  /* ================= 图表查看 ================= */
  _viewParamCurve(paramName) {
    const pattern = paramName === 'Wf_bias' ? '_wf_bias_schedule.png' : '_health_schedules.png';
    const title = paramName === 'Wf_bias' ? '燃油测量偏置调度曲线' : `${paramName} 健康调度曲线`;
    this._viewArtifact(pattern, title);
  }

  _viewErrorCurve(outputName) {
    this._viewArtifact('_prediction_error.png', `输出误差对比（${outputName}）`);
  }

  async _viewArtifact(pattern, title) {
    const task = this.latestIdentifyTask();
    if (!task) { this._toast('暂无任务结果', 'warning'); return; }
    const taskId = String(task.id);
    let artifacts = this.artifacts.get(taskId);
    if (!artifacts || artifacts.length === 0) {
      try {
        artifacts = await this.ctx.http.artifacts.request(taskId, { method: 'GET' });
        if (Array.isArray(artifacts)) this.artifacts.set(taskId, artifacts);
      } catch (e) { artifacts = []; }
    }
    // 直接从 artifacts 列表按文件名 pattern 匹配（优先 .png）
    let artifact = (artifacts || []).find(a => a.name && a.name.endsWith('.png') && a.name.includes(pattern));
    if (!artifact) artifact = (artifacts || []).find(a => a.name && a.name.includes(pattern));
    if (!artifact) { this._toast('图表文件未生成或未收集', 'warning'); return; }
    await this._showImageModal(taskId, artifact.id, artifact.name, title);
  }

  _toast(message, type = 'info') {
    if (window.CommonUtils && window.CommonUtils.showToast) {
      window.CommonUtils.showToast(message, type);
    } else {
      this.ctx.log(message);
    }
  }

  async _showImageModal(taskId, artifactId, fileName, title) {
    const overlay = el('div', 'image-modal-overlay');
    const dialog = el('div', 'image-modal');
    const header = el('div', 'image-modal-header');
    const heading = el('h3', '', title);
    const close = el('button', 'image-modal-close', '✕');
    close.type = 'button';
    const img = el('img', 'image-modal-img');
    img.alt = fileName;
    close.onclick = () => { this._revokeImage(img); overlay.remove(); };
    header.append(heading, close);
    const body = el('div', 'image-modal-body');
    body.append(img);
    const footer = el('div', 'image-modal-footer');
    const download = el('a', 'image-modal-download', '下载原图');
    download.href = '#';
    download.onclick = (e) => { e.preventDefault(); this._downloadArtifact(taskId, artifactId, fileName); };
    footer.append(download);
    dialog.append(header, body, footer);
    overlay.append(dialog);
    overlay.onclick = (e) => { if (e.target === overlay) { this._revokeImage(img); overlay.remove(); } };
    (this.ctx.shadow || this.mount).appendChild(overlay);

    const baseUrl = (window.AppConfig.api && window.AppConfig.api.baseURL) || '';
    const params = new URLSearchParams({
      name: this.ctx.program.name,
      version: this.ctx.program.version,
      ...(this.ctx.program.projectName ? { projectName: this.ctx.program.projectName } : {})
    });
    const token = (window.AppConfig.getToken ? window.AppConfig.getToken() : null) || localStorage.getItem('jwtToken') || '';
    if (token) params.set('token', token);
    const url = `${baseUrl}/api/program/workflow/artifacts/${encodeURIComponent(taskId)}/${encodeURIComponent(artifactId)}?${params}`;
    try {
      const headers = window.AppConfig.getAuthHeaders ? window.AppConfig.getAuthHeaders() : {};
      const response = await fetch(url, { headers });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const buf = await response.arrayBuffer();
      const blob = new Blob([buf], { type: 'image/png' });
      img._objUrl = URL.createObjectURL(blob);
      img.src = img._objUrl;
    } catch (e) {
      this._toast('加载图片失败: ' + (e.message || e), 'error');
      img.replaceWith(el('p', '', '加载图片失败：' + (e.message || e)));
    }
  }

  _revokeImage(img) {
    if (img && img._objUrl) { URL.revokeObjectURL(img._objUrl); img._objUrl = null; }
  }

  _downloadArtifact(taskId, artifactId, fileName) {
    this.ctx.http.artifacts.download(`${taskId}/${artifactId}`, fileName)
      .catch(e => this._toast('下载失败: ' + (e.message || e), 'error'));
  }

  _showStageLog(stage) {
    const identifyResult = this.latestIdentifyResult() || {};
    const summary = identifyResult?.resultSummary || identifyResult || {};
    const lines = [];
    if (stage === 'A') {
      const s = summary.stageA || {};
      lines.push('阶段：A 全工况常值');
      lines.push(`停止原因：${s.stopReason || '—'}`);
      lines.push(`迭代次数：${s.iterationCount != null ? s.iterationCount : '—'}`);
      lines.push(`正则化方法：${s.regularizationMethod || '—'}`);
      const costFrom = s.costInitial != null ? Number(s.costInitial).toExponential(4) : '—';
      const costTo = s.costFinal != null ? Number(s.costFinal).toExponential(4) : '—';
      lines.push(`Cost：${costFrom} → ${costTo}`);
      lines.push(`保留/截断奇异值：${s.retainedSingularValueCount != null ? s.retainedSingularValueCount : '—'} / ${s.truncatedSingularValueCount != null ? s.truncatedSingularValueCount : '—'}`);
      lines.push(`待估计参数：${s.parameterCount != null ? s.parameterCount : '—'}`);
    } else if (stage === 'B') {
      const groups = summary.groupResults || [];
      const converged = groups.filter(g => g.solve?.converged === true).length;
      lines.push('阶段：B 分组估计');
      lines.push(`训练分组数：${groups.length || '—'}`);
      lines.push(`已收敛组：${converged} / ${groups.length || '—'}`);
      if (groups.length) {
        const reasons = groups.map((g, i) => `组${g.group_id != null ? g.group_id : i + 1}：${g.solve?.stopReason || '—'}`).join('\n');
        lines.push(`各组停止原因：\n${reasons}`);
      }
    } else if (stage === 'C') {
      lines.push('阶段：C 调度重构');
      lines.push('说明：调度节点组装与非调度参数合并');
      lines.push(`调度稳定性有效：${summary.scheduleBeforeRefineTrainingValid === true ? '是' : summary.scheduleBeforeRefineTrainingValid === false ? '否' : '—'}`);
    } else if (stage === 'D') {
      const s = summary.stageRefine || {};
      lines.push('阶段：D 全工况微调');
      lines.push(`停止原因：${s.stopReason || '—'}`);
      lines.push(`迭代次数：${s.iterationCount != null ? s.iterationCount : '—'}`);
      lines.push(`正则化方法：${s.regularizationMethod || '—'}`);
      const costFrom = s.costInitial != null ? Number(s.costInitial).toExponential(4) : '—';
      const costTo = s.costFinal != null ? Number(s.costFinal).toExponential(4) : '—';
      lines.push(`Cost：${costFrom} → ${costTo}`);
    }
    const title = `${stage} 阶段日志`;
    const text = lines.length ? lines.join('\n') : '暂无阶段日志。';
    this._showLogModal(title, text);
  }

  _showLogModal(title, text) {
    const overlay = el('div', 'image-modal-overlay');
    const dialog = el('div', 'image-modal');
    dialog.style.width = '560px';
    dialog.style.maxWidth = '90vw';
    const header = el('div', 'image-modal-header');
    const heading = el('h3', '', title);
    const close = el('button', 'image-modal-close', '✕');
    close.type = 'button';
    close.onclick = () => overlay.remove();
    header.append(heading, close);
    const body = el('div', 'image-modal-body');
    body.style.display = 'block';
    const pre = el('pre', 'log-text', text);
    pre.style.cssText = 'width:100%;margin:0;padding:12px 14px;background:#f8fafb;border:1px solid var(--line);border-radius:3px;font-size:12px;line-height:1.7;white-space:pre-wrap;font-family:Consolas,"Courier New",monospace;color:var(--text);';
    body.append(pre);
    const footer = el('div', 'image-modal-footer');
    const copy = el('a', 'image-modal-download', '复制日志');
    copy.href = '#';
    copy.onclick = (e) => {
      e.preventDefault();
      navigator.clipboard.writeText(text).then(() => this._toast('已复制到剪贴板', 'info')).catch(() => this._toast('复制失败', 'error'));
    };
    footer.append(copy);
    dialog.append(header, body, footer);
    overlay.append(dialog);
    overlay.onclick = (e) => { if (e.target === overlay) overlay.remove(); };
    (this.ctx.shadow || this.mount).appendChild(overlay);
  }
}

export default SteadyModelAdaptV1;
