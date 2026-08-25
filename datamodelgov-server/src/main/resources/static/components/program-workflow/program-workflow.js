class ProgramWorkflow extends HTMLElement {
  constructor() {
    super();
    this.attachShadow({ mode: 'open' });
    this.programConfig = null;
    this.program = null;
    this.pluginInstance = null;
    this.pluginContainer = null;
    this._initialized = false;
    this._destroyed = false;
    this._isFullscreen = false;
    this._loadSequence = 0;
    this._resourcesReady = null;
  }

  connectedCallback() {
    if (!this._resourcesReady) this._resourcesReady = this.loadResources();
    this._resourcesReady.catch(error => {
      console.error('加载程序工作流资源失败:', error);
    });
  }

  disconnectedCallback() {
    this.destroy();
  }

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

    this.titleEl = this.shadowRoot.getElementById('programTitle');
    this.metaEl = this.shadowRoot.getElementById('programMeta');
    this.statusEl = this.shadowRoot.getElementById('workflowStatus');
    this.statusTextEl = this.shadowRoot.getElementById('statusText');
    this.pluginHost = this.shadowRoot.getElementById('pluginHost');
    this.footerLog = this.shadowRoot.getElementById('footerLog');
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
    this._keyHandler = event => {
      if (event.key === 'Escape' && this._isFullscreen) this.toggleFullscreen(false);
    };
    this._resizeHandler = () => this.notifyPluginResize();

    this.shadowRoot.getElementById('closeBtn').addEventListener('click', this._closeHandler);
    this.shadowRoot.getElementById('fullscreenBtn').addEventListener('click', this._fullscreenHandler);
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
    if (name && version) {
      return this.loadProgram(name, version, projectName, config);
    }
    this.setStatus('idle', '待加载');
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
    const closeButton = this.shadowRoot.getElementById('closeBtn');
    const fullscreenButton = this.shadowRoot.getElementById('fullscreenBtn');
    if (closeButton && this._closeHandler) closeButton.removeEventListener('click', this._closeHandler);
    if (fullscreenButton && this._fullscreenHandler) fullscreenButton.removeEventListener('click', this._fullscreenHandler);
    this.programConfig = null;
    this.program = null;
    this._destroyed = true;
  }

  async ensureReady() {
    if (!this._resourcesReady) this._resourcesReady = this.loadResources();
    await this._resourcesReady;
    if (this._destroyed && this._initialized) {
      this.bindEvents();
      this._destroyed = false;
    }
  }

  async loadProgram(name, version, projectName, preloadedConfig) {
    if (name && typeof name === 'object') {
      const details = name;
      name = details.name;
      version = details.version;
      projectName = details.projectName;
      preloadedConfig = details.config;
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
    this.updateHeader();
    this.setStatus('loading', '加载中');
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
      const extension = config.ui && config.ui.extension;
      if (!extension || extension.enabled === false || !extension.entry) {
        throw new Error('程序配置必须提供已启用的 ui.extension.entry');
      }

      await this.loadECharts();
      if (sequence !== this._loadSequence) return null;
      await this.loadExtension(extension, sequence);
      if (sequence !== this._loadSequence) return null;
      this.setStatus('ready', '就绪');
      this.setLog(`工作流插件 ${extension.entry} 已加载`);
      return this.programConfig;
    } catch (error) {
      if (sequence !== this._loadSequence) return null;
      console.error('加载程序工作流失败:', error);
      this.destroyExtension();
      this.setStatus('error', '加载失败');
      this.setLog('工作流加载失败: ' + (error.message || error));
      this.renderMessage('无法加载程序工作流：' + (error.message || error), true);
      return null;
    }
  }

  async loadECharts() {
    if (window.echarts) {
      this.echarts = window.echarts;
      return;
    }
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

  async loadExtension(extension, sequence) {
    this.destroyExtension();
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
    mount.style.cssText = 'display:flex;flex:1;min-width:0;min-height:0;';
    pluginShadow.appendChild(mount);
    this.pluginHost.replaceChildren(container);
    this.pluginContainer = container;
    this.pluginShadow = pluginShadow;

    try {
      const context = this.buildPluginContext(pluginShadow, mount);
      let instance;
      try {
        instance = new Plugin(context);
      } catch (error) {
        if (!/not a constructor/i.test(error && error.message)) throw error;
        instance = Plugin(context);
      }
      if (instance && typeof instance.then === 'function') instance = await instance;
      this.pluginInstance = instance || null;
      if (instance && typeof instance.init === 'function') await instance.init(context);
      if (sequence !== this._loadSequence) {
        this.destroyExtension();
        return;
      }
    } catch (error) {
      this.destroyExtension();
      throw new Error(`插件 ${pluginId} 初始化失败: ${error.message || error}`);
    }
  }

  buildPluginContext(shadow, mount) {
    return Object.freeze({
      mount,
      shadow,
      program: Object.freeze({ ...this.program }),
      metadata: Object.freeze({ ...this.program }),
      config: this.programConfig,
      echarts: this.echarts || window.echarts,
      http: Object.freeze({
        workspace: this.createHttpNamespace('workspace'),
        datasets: this.createHttpNamespace('datasets'),
        tasks: this.createHttpNamespace('tasks'),
        results: this.createHttpNamespace('results'),
        artifacts: this.createHttpNamespace('artifacts')
      }),
      log: message => this.setLog(message),
      setStatus: (state, text) => this.setStatus(state, text)
    });
  }

  createHttpNamespace(namespace) {
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
        return response.json();
      }
      if (requestOptions.body !== undefined && this.isPlainObject(requestOptions.body)) {
        requestOptions.body = JSON.stringify(requestOptions.body);
      }
      return window.AppConfig.request(url, requestOptions);
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

    return Object.freeze({
      request,
      list: query => request('', { method: 'GET', query }),
      get: (id, query) => request(id, { method: 'GET', query }),
      create: (data, query) => request('', { method: 'POST', body: data, query }),
      update: (id, data, query) => request(id, { method: 'PUT', body: data, query }),
      remove: (id, query) => request(id, { method: 'DELETE', query }),
      download
    });
  }

  isPlainObject(value) {
    return value !== null && typeof value === 'object' && Object.getPrototypeOf(value) === Object.prototype;
  }

  getProjectName() {
    const username = window.AppConfig.getUsername ? window.AppConfig.getUsername() : localStorage.getItem('username');
    if (!username) return null;
    try {
      const project = JSON.parse(localStorage.getItem('currentProject_' + username) || 'null');
      return project && project.name ? project.name : null;
    } catch (error) {
      console.warn('读取当前项目失败:', error);
      return null;
    }
  }

  destroyExtension() {
    const instance = this.pluginInstance;
    this.pluginInstance = null;
    if (instance && typeof instance.destroy === 'function') {
      try {
        const result = instance.destroy();
        if (result && typeof result.catch === 'function') {
          result.catch(error => console.warn('工作流插件销毁失败:', error));
        }
      } catch (error) {
        console.warn('工作流插件销毁失败:', error);
      }
    }
    if (this.pluginContainer && this.pluginContainer.parentNode) this.pluginContainer.remove();
    this.pluginContainer = null;
    this.pluginShadow = null;
  }

  toggleFullscreen(force) {
    this._isFullscreen = typeof force === 'boolean' ? force : !this._isFullscreen;
    this.classList.toggle('component-fullscreen', this._isFullscreen);
    const button = this.shadowRoot.getElementById('fullscreenBtn');
    if (button) {
      const label = this._isFullscreen ? '退出全屏' : '全屏显示';
      button.title = label;
      button.setAttribute('aria-label', label);
    }
    requestAnimationFrame(() => this.notifyPluginResize());
  }

  notifyPluginResize() {
    if (this.pluginInstance && typeof this.pluginInstance.resize === 'function') {
      try {
        this.pluginInstance.resize();
      } catch (error) {
        console.warn('工作流插件 resize 失败:', error);
      }
    }
  }

  updateHeader() {
    if (!this.program) return;
    if (this.titleEl) this.titleEl.textContent = this.program.name || 'MATLAB 程序工作流';
    if (this.metaEl) {
      this.metaEl.textContent = [this.program.version, this.program.projectName].filter(Boolean).join(' · ');
    }
  }

  setStatus(state, text) {
    if (this.statusEl) this.statusEl.dataset.state = state || 'idle';
    if (this.statusTextEl) this.statusTextEl.textContent = text || state || '待加载';
  }

  setLog(message) {
    if (this.footerLog) this.footerLog.textContent = String(message == null ? '' : message);
  }

  renderMessage(message, isError = false) {
    if (!this.pluginHost) return;
    const element = document.createElement('div');
    element.className = 'shell-message' + (isError ? ' error' : '');
    element.textContent = message;
    this.pluginHost.replaceChildren(element);
  }
}

customElements.define('program-workflow', ProgramWorkflow);
