class PluginManagement extends HTMLElement {
  constructor() {
    super();
    this.attachShadow({ mode: 'open' });
    this.plugins = [];
  }

  async connectedCallback() {
    const base = 'components/plugin-management/';
    const link = document.createElement('link');
    link.rel = 'stylesheet';
    link.href = base + 'plugin-management.css';
    this.shadowRoot.appendChild(link);
    const res = await fetch(base + 'plugin-management.html');
    const html = await res.text();
    const tpl = document.createElement('template');
    tpl.innerHTML = html;
    this.shadowRoot.appendChild(tpl.content.cloneNode(true));
    this.bindEvents();
    this.loadPlugins();
  }

  show() {
    this.style.display = 'block';
    this.loadPlugins();
  }

  hide() {
    this.style.display = 'none';
  }

  bindEvents() {
    const root = this.shadowRoot;
    const uploadBtn = root.getElementById('uploadBtn');
    const cancelBtn = root.getElementById('cancelUploadBtn');
    const submitBtn = root.getElementById('submitUploadBtn');
    if (uploadBtn) uploadBtn.addEventListener('click', () => this.showUploadForm());
    if (cancelBtn) cancelBtn.addEventListener('click', () => this.hideUploadForm());
    if (submitBtn) submitBtn.addEventListener('click', () => this.submitUpload());
  }

  async loadPlugins() {
    try {
      const result = await window.AppConfig.get('program', 'plugin');
      if (result && (result.success || result.code === 200) && Array.isArray(result.data)) {
        this.plugins = result.data;
      } else {
        this.plugins = [];
      }
      this.renderList();
    } catch (e) {
      console.error('加载插件列表失败:', e);
      this.plugins = [];
      this.renderList();
    }
  }

  renderList() {
    const container = this.shadowRoot.getElementById('pluginList');
    if (!container) return;
    if (!this.plugins.length) {
      container.innerHTML = '<div class="empty-state">暂无插件，点击"上传插件"添加</div>';
      return;
    }
    container.innerHTML = this.plugins.map(p => `
      <div class="plugin-card">
        <div class="plugin-info">
          <div class="plugin-name">${this.esc(p.name || p.id)}</div>
          <div class="plugin-meta">
            <span>ID: ${this.esc(p.id)}</span>
            ${p.version ? `<span>版本: ${this.esc(p.version)}</span>` : ''}
            ${p.author ? `<span>作者: ${this.esc(p.author)}</span>` : ''}
            <span class="ref-badge ${p.referenceCount === 0 ? 'zero' : ''}">引用 ${p.referenceCount || 0}</span>
          </div>
          ${p.description ? `<div class="plugin-desc">${this.esc(p.description)}</div>` : ''}
        </div>
        <div class="plugin-actions">
          <button class="btn btn-secondary" data-action="edit" data-id="${this.esc(p.id)}">编辑</button>
          <button class="btn btn-secondary" data-action="delete" data-id="${this.esc(p.id)}">删除</button>
        </div>
      </div>
    `).join('');
    container.querySelectorAll('button[data-action]').forEach(btn => {
      btn.addEventListener('click', () => {
        const action = btn.dataset.action;
        const id = btn.dataset.id;
        if (action === 'edit') this.showUploadForm(id);
        if (action === 'delete') this.deletePlugin(id);
      });
    });
  }

  showUploadForm(id) {
    const form = this.shadowRoot.getElementById('uploadForm');
    if (!form) return;
    form.classList.remove('hidden');
    const title = this.shadowRoot.getElementById('uploadFormTitle');
    if (id) {
      const p = this.plugins.find(x => x.id === id);
      if (title) title.textContent = '编辑插件 - ' + (p ? p.name : id);
      this.fillForm(p);
    } else {
      if (title) title.textContent = '上传新插件';
      this.fillForm(null);
    }
  }

  hideUploadForm() {
    const form = this.shadowRoot.getElementById('uploadForm');
    if (form) form.classList.add('hidden');
  }

  fillForm(p) {
    const set = (id, v) => { const el = this.shadowRoot.getElementById(id); if (el) el.value = v || ''; };
    set('pluginId', p ? p.id : '');
    set('pluginName', p ? p.name : '');
    set('pluginVersion', p ? p.version : '');
    set('pluginAuthor', p ? p.author : '');
    set('pluginDesc', p ? p.description : '');
    const entryInput = this.shadowRoot.getElementById('pluginEntryJs');
    const cssInput = this.shadowRoot.getElementById('pluginCss');
    if (entryInput) entryInput.value = '';
    if (cssInput) cssInput.value = '';
  }

  async submitUpload() {
    const get = (id) => this.shadowRoot.getElementById(id)?.value || '';
    const entryInput = this.shadowRoot.getElementById('pluginEntryJs');
    const cssInput = this.shadowRoot.getElementById('pluginCss');
    if (!entryInput || !entryInput.files.length) {
      if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('请选择入口 JS 文件', 'error');
      return;
    }
    const formData = new FormData();
    const id = get('pluginId');
    if (id) formData.append('id', id);
    formData.append('name', get('pluginName'));
    formData.append('version', get('pluginVersion'));
    formData.append('author', get('pluginAuthor'));
    formData.append('description', get('pluginDesc'));
    formData.append('entryJs', entryInput.files[0]);
    if (cssInput && cssInput.files.length) formData.append('css', cssInput.files[0]);
    try {
      const url = window.AppConfig.getApiUrl('program', 'plugin');
      const result = await window.AppConfig.upload('program', 'plugin', formData);
      if (result && (result.success || result.code === 200)) {
        if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('插件已保存', 'success');
        this.hideUploadForm();
        this.loadPlugins();
      } else {
        throw new Error(result.message || '保存失败');
      }
    } catch (e) {
      if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('保存失败: ' + e.message, 'error');
    }
  }

  async deletePlugin(id) {
    if (!confirm('确定删除该插件？')) return;
    try {
      const url = window.AppConfig.getApiUrl('program', 'plugin') + '/' + encodeURIComponent(id);
      const result = await window.AppConfig.request(url, { method: 'DELETE' });
      if (result && (result.success || result.code === 200)) {
        if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('插件已删除', 'success');
        this.loadPlugins();
      } else {
        throw new Error(result.message || '删除失败');
      }
    } catch (e) {
      if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('删除失败: ' + e.message, 'error');
    }
  }

  esc(s) { return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }
}

customElements.define('plugin-management', PluginManagement);
