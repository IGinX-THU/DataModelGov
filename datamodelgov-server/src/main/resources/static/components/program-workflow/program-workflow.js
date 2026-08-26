class ProgramWorkflow extends HTMLElement {
  constructor() {
    super();
    this.attachShadow({ mode: 'open' });
    this.programConfig = null;
    this.program = null;
    this.pluginInstance = null;
    this.pluginContainer = null;
    this.sections = [];
    this.activeSection = null;
    this._initialized = false;
    this._destroyed = false;
    this._isFullscreen = false;
    this._loadSequence = 0;
    this._resourcesReady = null;
  }

  connectedCallback() {
    if (!this._resourcesReady) this._resourcesReady = this.loadResources();
    this._resourcesReady.catch(error => console.error('加载程序工作流资源失败:', error));
  }

  disconnectedCallback() { this.destroy(); }

  async loadResources() {
    const base = 'components/program-workflow/';
    const link = document.createElement('link');
    link.rel = 'stylesheet';
    link.href = base + 'program-workflow.css';
    this.shadowRoot.appendChild(link);

    const response = await fetch(base + 'program-workflow.html');
    if (!response.ok) throw new Error(`HTTP ${response.status}: ${response.statusText}`);
    const template = document.createElement('template');
    template.innerHTML = await response.text();
    this.shadowRoot.appendChild(template.content.cloneNode(true));

    this.currentFunctionName = this.shadowRoot.getElementById('currentFunctionName');
    this.workflowNav = this.shadowRoot.getElementById('workflowNav');
    this.envDot = this.shadowRoot.getElementById('envDot');
    this.envStatusText = this.shadowRoot.getElementById('envStatusText');
    this.envStatusNote = this.shadowRoot.getElementById('envStatusNote');
    this.topbarTitle = this.shadowRoot.getElementById('topbarTitle');
    this.topbarFunction = this.shadowRoot.getElementById('topbarFunction');
    this.topbarProject = this.shadowRoot.getElementById('topbarProject');
    this.pageTitle = this.shadowRoot.getElementById('pageTitle');
    this.pageDesc = this.shadowRoot.getElementById('pageDesc');
    this.pageActions = this.shadowRoot.getElementById('pageActions');
    this.pluginHost = this.shadowRoot.getElementById('pluginHost');
    this.shellMessage = this.shadowRoot.getElementById('shellMessage');

    this.bindEvents();
    this._initialized = true;
    this._destroyed = false;
  }

  bindEvents() {
    this._closeHandler = () => {
      this.hide();
      this.dispatchEvent(new CustomEvent('workflow-close', { bubbles: true, composed: true }));
    };
    this._fullscreenHandler = () => this.toggleFullscreen();
    this._keyHandler = event => { if (event.key === 'Escape' && this._isFullscreen) this.toggleFullscreen(false); };
    this._resizeHandler = () => this.notifyPluginResize();

    const exitBtn = this.shadowRoot.getElementById('exitBtn');
    const helpBtn = this.shadowRoot.getElementById('helpBtn');
    const fullscreenBtn = this.shadowRoot.getElementById('fullscreenBtn');
    if (exitBtn) exitBtn.addEventListener('click', this._closeHandler);
    if (fullscreenBtn) fullscreenBtn.addEventListener('click', this._fullscreenHandler);
    if (helpBtn) helpBtn.addEventListener('click', () => {
      if (this.pluginInstance && typeof this.pluginInstance.onHelp === 'function') {
        this.pluginInstance.onHelp();
      } else {
        this.setLog('帮助功能已调用');
      }
    });
    document.addEventListener('keydown', this._keyHandler);
    window.addEventListener('resize', this._resizeHandler);
  }

  async show(details = {}) {
    this.hidden = false;
    this.style.display = 'block';
    await this.ensureReady();
    const name = details.name || this.getAttribute('data-name');
    const version = details.version || this.getAttribute('data-version');
    const projectName = details.projectName || this.getAttribute('data-project');
    const config = details.config || this.programConfig;
    if (name && version) return this.loadProgram(name, version, projectName, config);
    this.setEnvStatus('idle', '待加载');
    this.renderMessage('请选择程序以加载工作流');
    return null;
  }

  hide() {
    this.hidden = true;
    this.style.display = 'none';
    this.destroyExtension();
    if (this._isFullscreen) this.toggleFullscreen(false);
  }

  destroy() {
    this._loadSequence += 1;
    this.destroyExtension();
    if (this._keyHandler) document.removeEventListener('keydown', this._keyHandler);
    if (this._resizeHandler) window.removeEventListener('resize', this._resizeHandler);
    const exitBtn = this.shadowRoot.getElementById('exitBtn');
    if (exitBtn && this._closeHandler) exitBtn.removeEventListener('click', this._closeHandler);
    this.programConfig = null;
    this.program = null;
    this._destroyed = true;
  }

  async ensureReady() {
    if (!this._resourcesReady) this._resourcesReady = this.loadResources();
    await this._resourcesReady;
    if (this._destroyed && this._initialized) { this.bindEvents(); this._destroyed = false; }
  }

  async loadProgram(name, version, projectName, preloadedConfig) {
    if (name && typeof name === 'object') {
      const d = name;
      name = d.name;
      version = d.version;
      projectName = d.projectName;
      preloadedConfig = d.config;
    }
    if (!name || !version) throw new Error('程序名称和版本不能为空');

    await this.ensureReady();
    this.hidden = false;
    this.style.display = 'block';
    this.setAttribute('data-name', name);
    this.setAttribute('data-version', version);
    if (projectName) this.setAttribute('data-project', projectName);

    const sequence = ++this._loadSequence;
    const currentProject = projectName || this.getAttribute('data-project') || this.getProjectName();
    this.program = { name, version, projectName: currentProject || null };
    this.programConfig = null;
    this.destroyExtension();
    this.setEnvStatus('loading', '计算环境加载中');
    this.setLog('正在加载程序配置');
    this.renderMessage('正在加载工作流插件...');

    try {
      let config = preloadedConfig || this.programConfig;
      if (!config) {
        const params = { name, version, ...(currentProject ? { projectName: currentProject } : {}) };
        const result = await window.AppConfig.get('program', 'config', params);
        if (sequence !== this._loadSequence) return null;
        if (!result || (!(result.success || result.code === 200)) || !result.data) {
          throw new Error((result && (result.message || result.msg)) || '程序配置不存在');
        }
        config = typeof result.data === 'string' ? JSON.parse(result.data) : result.data;
      }
      if (sequence !== this._loadSequence) return null;

      this.programConfig = config;

      await this.loadECharts();
      if (sequence !== this._loadSequence) return null;
      await this.loadExtension(config, sequence);
      if (sequence !== this._loadSequence) return null;
      this.setEnvStatus('ready', '计算环境就绪');
      this.setLog('工作流已加载');
      return this.programConfig;
    } catch (error) {
      if (sequence !== this._loadSequence) return null;
      console.error('加载程序工作流失败:', error);
      this.destroyExtension();
      this.setEnvStatus('error', '计算环境异常');
      this.setLog('工作流加载失败: ' + (error.message || error));
      this.renderMessage('无法加载程序工作流：' + (error.message || error), true);
      return null;
    }
  }

  async loadECharts() {
    if (window.echarts) { this.echarts = window.echarts; return; }
    if (!ProgramWorkflow.echartsPromise) {
      ProgramWorkflow.echartsPromise = new Promise((resolve, reject) => {
        const script = document.createElement('script');
        script.src = new URL('lib/echarts/echarts.min.js', document.baseURI).href;
        script.onload = resolve;
        script.onerror = () => reject(new Error('ECharts 加载失败'));
        document.head.appendChild(script);
      });
    }
    await ProgramWorkflow.echartsPromise;
    this.echarts = window.echarts;
  }

  getSections() {
    const defaultActions = {
      data: [{ label: '字段说明' }, { label: '创建并校验项目', primary: true }],
      identify: [{ label: '恢复默认配置' }, { label: '开始辨识', primary: true }],
      identifiability: [{ label: '切换分析对象' }, { label: '生成分析报告', primary: true }],
      uq: [{ label: '评估配置' }, { label: '开始评估', primary: true }],
      validation: [{ label: '选择辨识结果' }, { label: '开始验证', primary: true }],
      prediction: [{ label: '选择模型' }, { label: '运行预测', primary: true }],
      results: [{ label: '打开结果目录' }, { label: '导出所选结果', primary: true }]
    };

    const ui = this.programConfig && this.programConfig.ui;
    if (ui && Array.isArray(ui.sections) && ui.sections.length) {
      return ui.sections.map((s, i) => ({
        id: s.id || ('s' + i),
        title: s.title || s.id,
        hint: s.hint || '',
        actions: (Array.isArray(s.actions) && s.actions.length) ? s.actions : (defaultActions[s.id] || [])
      }));
    }

    return [
      {
        id: 'data',
        title: '新建项目与数据',
        hint: '在一个页面内完成项目建立、测量数据检查、辅助变量计算和训练工况分组。',
        actions: defaultActions.data
      },
      {
        id: 'identify',
        title: '参数辨识',
        hint: '默认采用瞬态时刻模型；路径、正则化配置、辨识流程和结果集中在一个页面。',
        actions: defaultActions.identify
      },
      {
        id: 'identifiability',
        title: '可辨识性',
        hint: '同时展示整体信息质量、逐参数分类和主要补偿参数，帮助判断辨识结果能否独立解释。',
        actions: defaultActions.identifiability
      },
      {
        id: 'uq',
        title: '不确定性评估',
        hint: '分别评估关键修正系数和全部修正系数，并给出参数95%置信区间及预测影响。',
        actions: defaultActions.uq
      },
      {
        id: 'validation',
        title: '测试验证',
        hint: '仅使用稳态模型，在独立测试工况上比较零修正模型、稳态辨识模型和测量数据。',
        actions: defaultActions.validation
      },
      {
        id: 'prediction',
        title: '工况预测',
        hint: '输入单个新工况，在无测量输出条件下给出稳态辨识模型预测和后验95%置信区间。',
        actions: defaultActions.prediction
      },
      {
        id: 'results',
        title: '结果中心',
        hint: '按项目和任务组织辨识、可辨识性、不确定、验证与预测结果。',
        actions: defaultActions.results
      }
    ];
  }

  renderShell() {
    const ui = (this.programConfig && this.programConfig.ui) || {};
    if (this.topbarTitle) this.topbarTitle.textContent = '发动机个性化性能数字模型平台';
    if (this.topbarFunction) this.topbarFunction.textContent = '功能: ' + (ui.title || (this.program && this.program.name) || '稳态试车工况点模型修正V1');
    if (this.topbarProject) {
      const pluginProjectCreated = this.pluginInstance && this.pluginInstance.projectCreated;
      const p = pluginProjectCreated ? (this.pluginInstance.projectForm && this.pluginInstance.projectForm.projectName) : null;
      this.topbarProject.textContent = '当前项目：' + (p ? p : '未创建');
      this.topbarProject.classList.toggle('project-uncreated', !pluginProjectCreated);
    }
    if (this.currentFunctionName) {
      this.currentFunctionName.innerHTML = '稳态试车工况点模型<br>自适应修正';
    }

    this.sections = this.getSections();
    if (!this.activeSection) this.activeSection = this.sections[0];

    this.workflowNav.replaceChildren();
    this.sections.forEach((section, index) => {
      const item = document.createElement('button');
      item.className = 'nav-item' + (section.id === this.activeSection.id ? ' active' : '');
      item.type = 'button';
      item.append(el('span', 'nav-index', String(index + 1)));
      item.append(el('span', 'nav-label', section.title));
      item.addEventListener('click', () => this.setActiveSection(section.id));
      this.workflowNav.appendChild(item);
    });
    this.updatePageHeader();
  }

  updatePageHeader() {
    const section = this.activeSection || this.sections[0] || {};
    this.pageTitle.textContent = section.title || '—';
    this.pageDesc.textContent = section.hint || '';
    this.pageActions.replaceChildren();
    (section.actions || []).forEach(a => {
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = a.primary ? 'btn primary' : 'btn';
      btn.textContent = a.label;
      btn.addEventListener('click', () => {
        if (this.pluginInstance && typeof this.pluginInstance.onHeaderAction === 'function') {
          Promise.resolve(this.pluginInstance.onHeaderAction(a.label, section.id))
            .catch(e => this.setLog('操作失败: ' + (e && e.message || e)));
        } else {
          this.setLog('操作：' + a.label);
        }
      });
      this.pageActions.appendChild(btn);
    });
  }

  async setActiveSection(id) {
    const target = this.sections.find(s => s.id === id);
    if (!target) return;
    const locked = this.getLockedSections();
    if (locked.has(target.id)) {
      this.setLog(`功能"${target.title}"尚未解锁，请先完成前置步骤`);
      return;
    }
    this.activeSection = target;
    this.workflowNav.querySelectorAll('.nav-item').forEach((item, index) => {
      item.classList.toggle('active', this.sections[index].id === this.activeSection.id);
    });
    this.updatePageHeader();
    if (this.pluginInstance && typeof this.pluginInstance.setSection === 'function') {
      try { await this.pluginInstance.setSection(this.activeSection.id); } catch (e) { console.warn('setSection 失败:', e); }
    }
    this.updateNavLockState();
  }

  getLockedSections() {
    if (this.pluginInstance && typeof this.pluginInstance.getLockedSections === 'function') {
      try { return new Set(this.pluginInstance.getLockedSections()); } catch (e) { return new Set(); }
    }
    return new Set();
  }

  updateNavLockState() {
    const locked = this.getLockedSections();
    this.workflowNav.querySelectorAll('.nav-item').forEach((item, index) => {
      const section = this.sections[index];
      if (section) item.classList.toggle('locked', locked.has(section.id));
    });
  }

  async loadExtension(config, sequence) {
    this.destroyExtension();
    const extension = config.ui && config.ui.extension;
    if (!extension || extension.enabled === false || !extension.entry) throw new Error('程序配置必须提供已启用的 ui.extension.entry');

    const baseUrl = window.AppConfig.getApiUrl('program', 'plugin');
    const token = window.AppConfig.getToken ? window.AppConfig.getToken() : localStorage.getItem('jwtToken');
    const query = token ? `?token=${encodeURIComponent(token)}` : '';
    const pluginId = extension.entry;
    const moduleUrl = `${baseUrl}/${encodeURIComponent(pluginId)}/entry.js${query}`;
    const module = await import(/* @vite-ignore */ moduleUrl);
    if (sequence !== this._loadSequence) return;

    const Plugin = module.default || module;
    if (typeof Plugin !== 'function') throw new Error('插件必须导出 default 类或工厂函数');

    const container = document.createElement('div');
    container.className = 'plugin-container';
    const pluginShadow = container.attachShadow({ mode: 'open' });
    if (extension.css) {
      const link = document.createElement('link');
      link.rel = 'stylesheet';
      link.href = `${baseUrl}/${encodeURIComponent(pluginId)}/style.css${query}`;
      pluginShadow.appendChild(link);
    }
    const mount = document.createElement('div');
    mount.className = 'plugin-mount';
    mount.style.cssText = 'display:flex;width:100%;min-width:0;min-height:0;flex-direction:column;';
    pluginShadow.appendChild(mount);
    this.pluginHost.replaceChildren(container);
    this.pluginContainer = container;
    this.pluginShadow = pluginShadow;

    this.renderShell();

    try {
      this.activeSection = this.sections[0];
      const context = this.buildPluginContext(pluginShadow, mount);
      let instance;
      try { instance = new Plugin(context); } catch (error) { if (!/not a constructor/i.test(error && error.message)) throw error; instance = Plugin(context); }
      if (instance && typeof instance.then === 'function') instance = await instance;
      this.pluginInstance = instance || null;
      if (instance && typeof instance.init === 'function') await instance.init(context);
      if (sequence !== this._loadSequence) { this.destroyExtension(); return; }
      this.updateNavLockState();
    } catch (error) {
      this.destroyExtension();
      throw new Error(`插件 ${pluginId} 初始化失败: ${error.message || error}`);
    }
  }

  buildPluginContext(shadow, mount) {
    const section = this.activeSection || this.sections[0] || {};
    return Object.freeze({
      mount, shadow,
      activeSectionId: section.id,
      sections: this.sections,
      setSection: id => this.setActiveSection(id),
      refreshNav: () => { this.updateNavLockState(); this.renderShell(); },
      program: Object.freeze({ ...this.program }),
      metadata: Object.freeze({ ...this.program }),
      config: this.programConfig,
      echarts: this.echarts || window.echarts,
      http: Object.freeze({
        workspace: this.createHttpNamespace('workspace'),
        datasets: this.createHttpNamespace('datasets'),
        tasks: this.createHttpNamespace('tasks'),
        results: this.createHttpNamespace('results'),
        artifacts: this.createHttpNamespace('artifacts'),
        availableData: this.createHttpNamespace('available-data'),
        previewData: this.createHttpNamespace('preview-data')
      }),
      log: message => this.setLog(message),
      setStatus: (state, text) => this.setEnvStatus(state, text)
    });
  }

  createHttpNamespace(namespace) {
    const unwrap = result => {
      if (result && typeof result === 'object' && 'success' in result && 'data' in result) return result.data;
      return result;
    };
    const request = async (path = '', options = {}) => {
      const cleanPath = String(path || '').replace(/^\/+/, '');
      const baseUrl = (window.AppConfig.api && window.AppConfig.api.baseURL) || '';
      let url = `${baseUrl}/api/program/workflow/${namespace}`;
      if (cleanPath) url += '/' + cleanPath.split('/').map(encodeURIComponent).join('/');
      const query = {
        name: this.program.name,
        version: this.program.version,
        ...(this.program.projectName ? { projectName: this.program.projectName } : {}),
        ...(options.query || {})
      };
      const queryString = new URLSearchParams(Object.entries(query).filter(([, value]) => value !== undefined && value !== null)).toString();
      if (queryString) url += '?' + queryString;
      const requestOptions = { ...options };
      delete requestOptions.query;
      if (requestOptions.body instanceof FormData) {
        const headers = window.AppConfig.getAuthHeaders();
        delete headers['Content-Type'];
        const response = await fetch(url, { ...requestOptions, headers });
        if (!response.ok) throw new Error(`请求失败: HTTP ${response.status}`);
        const json = await response.json();
        return unwrap(json);
      }
      if (requestOptions.body !== undefined && this.isPlainObject(requestOptions.body)) requestOptions.body = JSON.stringify(requestOptions.body);
      const result = await window.AppConfig.request(url, requestOptions);
      return unwrap(result);
    };
    const download = async (path, fileName, query = {}) => {
      const cleanPath = String(path || '').replace(/^\/+/, '');
      const baseUrl = (window.AppConfig.api && window.AppConfig.api.baseURL) || '';
      const params = new URLSearchParams({
        name: this.program.name,
        version: this.program.version,
        ...(this.program.projectName ? { projectName: this.program.projectName } : {}),
        ...query
      });
      const url = `${baseUrl}/api/program/workflow/${namespace}/${cleanPath.split('/').map(encodeURIComponent).join('/')}?${params}`;
      const response = await fetch(url, { headers: window.AppConfig.getAuthHeaders() });
      if (!response.ok) throw new Error(`下载失败: HTTP ${response.status}`);
      const blob = await response.blob();
      const objectUrl = URL.createObjectURL(blob);
      const anchor = document.createElement('a');
      anchor.href = objectUrl;
      anchor.download = fileName || 'artifact';
      anchor.click();
      setTimeout(() => URL.revokeObjectURL(objectUrl), 1000);
    };
    return Object.freeze({ request, list: query => request('', { method: 'GET', query }), get: (id, query) => request(id, { method: 'GET', query }), create: (data, query) => request('', { method: 'POST', body: data, query }), update: (id, data, query) => request(id, { method: 'PUT', body: data, query }), remove: (id, query) => request(id, { method: 'DELETE', query }), download });
  }

  isPlainObject(value) { return value !== null && typeof value === 'object' && Object.getPrototypeOf(value) === Object.prototype; }

  getProjectName() {
    const username = window.AppConfig.getUsername ? window.AppConfig.getUsername() : localStorage.getItem('username');
    if (!username) return null;
    try { const project = JSON.parse(localStorage.getItem('currentProject_' + username) || 'null'); return project && project.name ? project.name : null; }
    catch (error) { console.warn('读取当前项目失败:', error); return null; }
  }

  destroyExtension() {
    const instance = this.pluginInstance;
    this.pluginInstance = null;
    this.activeSection = null;
    if (instance && typeof instance.destroy === 'function') {
      try {
        const result = instance.destroy();
        if (result && typeof result.catch === 'function') result.catch(error => console.warn('工作流插件销毁失败:', error));
      } catch (error) { console.warn('工作流插件销毁失败:', error); }
    }
    if (this.pluginContainer && this.pluginContainer.parentNode) this.pluginContainer.remove();
    this.pluginContainer = null;
    this.pluginShadow = null;
  }

  toggleFullscreen(force) {
    this._isFullscreen = typeof force === 'boolean' ? force : !this._isFullscreen;
    this.classList.toggle('component-fullscreen', this._isFullscreen);
    requestAnimationFrame(() => this.notifyPluginResize());
  }

  notifyPluginResize() {
    if (this.pluginInstance && typeof this.pluginInstance.resize === 'function') {
      try { this.pluginInstance.resize(); } catch (error) { console.warn('工作流插件 resize 失败:', error); }
    }
  }

  setEnvStatus(type, text, note) {
    if (this.envDot) this.envDot.className = 'status-dot' + (type ? ' ' + type : '');
    if (this.envStatusText) this.envStatusText.textContent = text || '计算环境就绪';
    if (note && this.envStatusNote) this.envStatusNote.textContent = note;
  }

  setLog(message) { if (this.envStatusNote) this.envStatusNote.textContent = String(message == null ? '模型与数据状态随项目更新' : message); }

  renderMessage(message, isError = false) {
    if (!this.pluginHost) return;
    const element = document.createElement('div');
    element.className = 'shell-message' + (isError ? ' error' : '');
    element.textContent = message;
    this.pluginHost.replaceChildren(element);
  }
}

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined && text !== null) node.textContent = String(text);
  return node;
}

customElements.define('program-workflow', ProgramWorkflow);
