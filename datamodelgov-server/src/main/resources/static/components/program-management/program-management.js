class ProgramManagement extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });
        this.programs = [];
        this.pageNum = 1;
        this.pageSize = 10;
        this.total = 0;
        this.filterName = '';
        this.filterProject = '';
    }

    async connectedCallback() {
        await this.loadResources();
        this.bindEvents();
    }

    async loadResources() {
        const cssLink = document.createElement('link');
        cssLink.rel = 'stylesheet';
        cssLink.href = './components/program-management/program-management.css';
        this.shadowRoot.appendChild(cssLink);

        try {
            const response = await fetch('./components/program-management/program-management.html');
            if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
            this.shadowRoot.innerHTML += await response.text();
        } catch (error) {
            console.error('Failed to load HTML template:', error);
        }
    }

    bindEvents() {
        const tbody = this.shadowRoot.getElementById('tableBody');
        const showUploadBtn = this.shadowRoot.getElementById('showUploadBtn');
        const searchBtn = this.shadowRoot.getElementById('searchBtn');
        const resetFilterBtn = this.shadowRoot.getElementById('resetFilterBtn');
        const filterNameInput = this.shadowRoot.getElementById('filterName');
        const filterProjectInput = this.shadowRoot.getElementById('filterProject');
        const prevPageBtn = this.shadowRoot.getElementById('prevPageBtn');
        const nextPageBtn = this.shadowRoot.getElementById('nextPageBtn');

        if (showUploadBtn) showUploadBtn.addEventListener('click', () => {
            if (window.showComponent) window.showComponent('programUpload');
        });
        if (searchBtn) searchBtn.addEventListener('click', () => {
            this.filterName = filterNameInput ? filterNameInput.value.trim() : '';
            this.filterProject = filterProjectInput ? filterProjectInput.value.trim() : '';
            this.pageNum = 1;
            this.loadPrograms();
        });
        if (resetFilterBtn) resetFilterBtn.addEventListener('click', () => {
            this.filterName = '';
            this.filterProject = '';
            if (filterNameInput) filterNameInput.value = '';
            if (filterProjectInput) filterProjectInput.value = '';
            this.pageNum = 1;
            this.loadPrograms();
        });
        if (prevPageBtn) prevPageBtn.addEventListener('click', () => {
            if (this.pageNum > 1) { this.pageNum--; this.loadPrograms(); }
        });
        if (nextPageBtn) nextPageBtn.addEventListener('click', () => {
            const maxPage = Math.ceil(this.total / this.pageSize);
            if (this.pageNum < maxPage) { this.pageNum++; this.loadPrograms(); }
        });

        if (tbody) {
            tbody.addEventListener('click', (e) => {
                const btn = e.target.closest('button');
                const row = e.target.closest('tr');
                if (btn) {
                    const name = btn.dataset.name;
                    const version = btn.dataset.version;
                    const projectName = btn.dataset.project;
                    if (!name || !version) return;
                    if (btn.classList.contains('run-btn')) this.openProgramRun(name, version, projectName);
                    if (btn.classList.contains('config-btn')) this.openConfig(name, version, projectName);
                    if (btn.classList.contains('delete-btn')) this.deleteProgram(name, version);
                    if (btn.classList.contains('download-btn')) this.downloadProgram(name, version, projectName);
                    return;
                }
                if (row) {
                    const name = row.dataset.name;
                    const version = row.dataset.version;
                    const projectName = row.dataset.project;
                    if (name && version) this.openProgramRun(name, version, projectName);
                }
            });
        }

        const configCloseBtn = this.shadowRoot.getElementById('configCloseBtn');
        const configCancelBtn = this.shadowRoot.getElementById('configCancelBtn');
        const configSaveBtn = this.shadowRoot.getElementById('configSaveBtn');
        const addParamBtn = this.shadowRoot.getElementById('addParamBtn');
        const addSignalBtn = this.shadowRoot.getElementById('addSignalBtn');
        const addSectionBtn = this.shadowRoot.getElementById('addSectionBtn');
        const cfgUploadJsonBtn = this.shadowRoot.getElementById('cfgUploadJsonBtn');
        const cfgUploadJsonInput = this.shadowRoot.getElementById('cfgUploadJsonInput');
        const cfgApplyTemplateBtn = this.shadowRoot.getElementById('cfgApplyTemplateBtn');
        const cfgApplyPresetBtn = this.shadowRoot.getElementById('cfgApplyPresetBtn');
        const cfgUploadScriptBtn = this.shadowRoot.getElementById('cfgUploadScriptBtn');
        const cfgUploadScriptInput = this.shadowRoot.getElementById('cfgUploadScriptInput');

        if (configCloseBtn) configCloseBtn.addEventListener('click', () => this.closeConfig());
        if (configCancelBtn) configCancelBtn.addEventListener('click', () => this.closeConfig());
        if (configSaveBtn) configSaveBtn.addEventListener('click', () => this.saveConfig());
        if (addParamBtn) addParamBtn.addEventListener('click', () => this.addParamRow());
        if (addSignalBtn) addSignalBtn.addEventListener('click', () => this.addSignalRow());
        if (addSectionBtn) addSectionBtn.addEventListener('click', () => this.addSectionRow());
        if (cfgApplyPresetBtn) cfgApplyPresetBtn.addEventListener('click', () => this.applyPreset());
        if (cfgApplyTemplateBtn) cfgApplyTemplateBtn.addEventListener('click', () => this.applyTemplate());
        if (cfgUploadJsonBtn) cfgUploadJsonBtn.addEventListener('click', () => cfgUploadJsonInput && cfgUploadJsonInput.click());
        if (cfgUploadJsonInput) cfgUploadJsonInput.addEventListener('change', (e) => this.handleConfigUpload(e));
        if (cfgUploadScriptBtn) cfgUploadScriptBtn.addEventListener('click', () => cfgUploadScriptInput && cfgUploadScriptInput.click());
        if (cfgUploadScriptInput) cfgUploadScriptInput.addEventListener('change', (e) => this.handleScriptUpload(e));
        // 双向自动同步：表单 ↔ rawJson
        const configForm = this.shadowRoot.getElementById('configForm');
        if (configForm) {
            configForm.addEventListener('input', () => this.syncFormToRawJson());
            configForm.addEventListener('change', () => this.syncFormToRawJson());
        }
        const rawEl = this.shadowRoot.getElementById('cfgRawJson');
        if (rawEl) {
            // rawJson 变化时（debounce 300ms）自动同步到表单
            let rawTimer = null;
            rawEl.addEventListener('input', () => {
                if (rawTimer) clearTimeout(rawTimer);
                rawTimer = setTimeout(() => this.syncRawJsonToForm(), 300);
            });
        }
    }

    /** 表单 → rawJson：把表单值合并到 rawJson（保留 rawJson 里表单不支持的字段） */
    syncFormToRawJson() {
        if (!this.editingConfig) return;
        const rawEl = this.shadowRoot.getElementById('cfgRawJson');
        if (!rawEl) return;
        // 防止循环同步：标记正在从表单同步
        if (this._syncingForm) return;
        this._syncingForm = true;
        try {
            const formConfig = this.collectConfig(false);
            let rawConfig = this.editingConfig;
            if (rawEl.value && rawEl.value.trim()) {
                try { rawConfig = JSON.parse(rawEl.value); } catch (e) { /* 用 editingConfig */ }
            }
            const merged = this.mergeFormAndRaw(formConfig, rawConfig);
            rawEl.value = JSON.stringify(merged, null, 2);
        } catch (e) {
            // 忽略同步错误
        } finally {
            this._syncingForm = false;
        }
    }

    /** rawJson → 表单：解析 rawJson 并回填表单字段 */
    syncRawJsonToForm() {
        const rawEl = this.shadowRoot.getElementById('cfgRawJson');
        if (!rawEl || !rawEl.value || !rawEl.value.trim()) return;
        // 防止循环同步
        if (this._syncingRaw) return;
        this._syncingRaw = true;
        try {
            const parsed = JSON.parse(rawEl.value);
            this.editingConfig = this.normalizeConfig(parsed, { name: this.configProgramName });
            this.renderConfigForm(this.editingConfig);
        } catch (e) {
            // JSON 格式错误时不回填，让用户继续编辑
        } finally {
            this._syncingRaw = false;
        }
    }

    show() { this.style.display = 'block'; this.loadPrograms(); }
    hide() { this.style.display = 'none'; }

    normalizeConfig(config, program) {
        const c = config || {};
        const result = {
            programName: c.programName || (program && program.name) || '',
            runtime: c.runtime || { preRunScript: '', simulinkModel: '', stopTime: 30, fixedStep: '' },
            parameters: c.parameters || [],
            derivedVars: c.derivedVars || [],
            signals: c.signals || [],
            ui: c.ui || { title: '', layout: 'tabs', sections: [], extension: { enabled: false, mode: 'slot', entry: '', slot: '' } }
        };
        if (c.template) result.template = c.template;
        return result;
    }

    async openConfig(name, version, projectName) {
        this.configProgramName = name;
        this.configProgramVersion = version;
        this.configProjectName = projectName || this.getProjectName();
        const nameEl = this.shadowRoot.getElementById('configProgramName');
        if (nameEl) nameEl.textContent = name;
        // 加载可用插件列表、预置配置列表、页面模板列表
        await this.loadPluginOptions();
        await this.loadPresetOptions();
        await this.loadTemplateOptions();
        let config = {};
        try {
            const pn = this.configProjectName;
            const result = await window.AppConfig.get('program', 'config', { name, version, ...(pn ? { projectName: pn } : {}) });
            if (result && (result.success || result.code === 200) && result.data) {
                config = typeof result.data === 'string' ? JSON.parse(result.data) : result.data;
            }
        } catch (e) { config = {}; }
        this.editingConfig = this.normalizeConfig(config, { name });
        // 如果有 template 引用且没有内联 ui，加载 template 的 ui 填充到表单
        if (this.editingConfig.template && (!this.editingConfig.ui || !this.editingConfig.ui.title)) {
            try {
                const tplUrl = window.AppConfig.getApiUrl('program', 'templates') + '/' + encodeURIComponent(this.editingConfig.template);
                const tplResult = await window.AppConfig.request(tplUrl, { method: 'GET' });
                if (tplResult && (tplResult.success || tplResult.code === 200) && tplResult.data) {
                    const tpl = typeof tplResult.data === 'string' ? JSON.parse(tplResult.data) : tplResult.data;
                    if (!this.editingConfig.ui || !this.editingConfig.ui.title) {
                        this.editingConfig.ui = tpl.ui || tpl;
                    }
                }
            } catch (te) { console.warn('加载页面模板失败:', te); }
        }
        this.renderConfigForm(this.editingConfig);
        // 回显 template 下拉
        const tplSelect = this.shadowRoot.getElementById('cfgTemplateSelect');
        if (tplSelect && this.editingConfig.template) tplSelect.value = this.editingConfig.template;
        // 加载 setupScript（独立字段）
        await this.loadSetupScript(name, version);
        const modal = this.shadowRoot.getElementById('configModal');
        if (modal) modal.classList.remove('hidden');
    }

    /** 加载预置配置列表，填充下拉框 */
    async loadPresetOptions() {
        const select = this.shadowRoot.getElementById('cfgPresetSelect');
        if (!select) return;
        try {
            const result = await window.AppConfig.get('program', 'config-templates');
            const presets = (result && (result.success || result.code === 200) && Array.isArray(result.data)) ? result.data : [];
            select.innerHTML = '<option value="">选择预置配置...</option>' +
                presets.map(t => `<option value="${this.esc(t.id)}">${this.esc(t.name || t.id)}</option>`).join('');
            if (this.configProgramName) select.value = this.configProgramName;
        } catch (e) {
            console.warn('加载预置配置列表失败:', e);
        }
    }

    /** 加载 setupScript（独立字段） */
    async loadSetupScript(name, version) {
        try {
            const pn = this.configProjectName;
            const result = await window.AppConfig.get('program', 'setup-script', { name, version, ...(pn ? { projectName: pn } : {}) });
            if (result && (result.success || result.code === 200) && result.data) {
                const el = this.shadowRoot.getElementById('cfgSetupScript');
                if (el) el.value = result.data;
            }
        } catch (e) {
            console.warn('加载脚本失败:', e);
        }
    }

    /** 加载选中的预置配置（含脚本） */
    async applyPreset() {
        const select = this.shadowRoot.getElementById('cfgPresetSelect');
        if (!select || !select.value) {
            if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('请先选择预置配置', 'warning');
            return;
        }
        const id = select.value;
        try {
            // 加载配置 JSON
            const url = window.AppConfig.getApiUrl('program', 'config-templates') + '/' + encodeURIComponent(id);
            const result = await window.AppConfig.request(url, { method: 'GET' });
            if (result && (result.success || result.code === 200) && result.data) {
                const config = typeof result.data === 'string' ? JSON.parse(result.data) : result.data;
                this.editingConfig = this.normalizeConfig(config, { name: this.configProgramName });
                // 如果有 template 引用且 ui 为空，加载 template 的 ui 填充到表单
                const uiEmpty = !this.editingConfig.ui || (!this.editingConfig.ui.title && (!this.editingConfig.ui.sections || this.editingConfig.ui.sections.length === 0));
                if (this.editingConfig.template && uiEmpty) {
                    try {
                        const tplUrl = window.AppConfig.getApiUrl('program', 'templates') + '/' + encodeURIComponent(this.editingConfig.template);
                        const tplResult = await window.AppConfig.request(tplUrl, { method: 'GET' });
                        if (tplResult && (tplResult.success || tplResult.code === 200) && tplResult.data) {
                            const tpl = typeof tplResult.data === 'string' ? JSON.parse(tplResult.data) : tplResult.data;
                            this.editingConfig.ui = tpl.ui || tpl;
                        }
                    } catch (te) { console.warn('加载页面模板失败:', te); }
                }
                this.renderConfigForm(this.editingConfig);
                // 回显 template 下拉
                const tplSel = this.shadowRoot.getElementById('cfgTemplateSelect');
                if (tplSel && this.editingConfig.template) tplSel.value = this.editingConfig.template;
                // 加载对应的脚本
                const scriptUrl = window.AppConfig.getApiUrl('program', 'config-templates') + '/' + encodeURIComponent(id) + '/setup-script';
                const scriptResult = await window.AppConfig.request(scriptUrl, { method: 'GET' });
                if (scriptResult && (scriptResult.success || scriptResult.code === 200) && scriptResult.data) {
                    const el = this.shadowRoot.getElementById('cfgSetupScript');
                    if (el) el.value = scriptResult.data;
                }
                if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('预置配置已加载', 'success');
            } else {
                throw new Error(result.message || '加载失败');
            }
        } catch (e) {
            if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('加载预置配置失败: ' + e.message, 'error');
        }
    }

    /** 上传 .m 文件，解析到脚本文本框 */
    handleScriptUpload(e) {
        const file = e.target.files[0];
        if (!file) return;
        const reader = new FileReader();
        reader.onload = () => {
            const el = this.shadowRoot.getElementById('cfgSetupScript');
            if (el) el.value = reader.result;
            if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('脚本已加载: ' + file.name, 'success');
        };
        reader.readAsText(file);
        e.target.value = '';
    }

    /** 下载脚本为 .m 文件 */
    /** 加载插件列表，填充 cfgExtEntry 下拉框 */
    async loadPluginOptions() {
        const select = this.shadowRoot.getElementById('cfgExtEntry');
        if (!select) return;
        try {
            const result = await window.AppConfig.get('program', 'plugin');
            const plugins = (result && (result.success || result.code === 200) && Array.isArray(result.data)) ? result.data : [];
            const current = select.value;
            select.innerHTML = '<option value="">不使用插件</option>' +
                plugins.map(p => `<option value="${this.esc(p.id)}">${this.esc(p.name || p.id)}${p.program ? ' (' + this.esc(p.program) + ')' : ''}</option>`).join('');
            select.value = current;
        } catch (e) {
            console.warn('加载插件列表失败:', e);
        }
    }

    /** 加载页面模板列表，填充下拉框 */
    async loadTemplateOptions() {
        const select = this.shadowRoot.getElementById('cfgTemplateSelect');
        if (!select) return;
        try {
            const result = await window.AppConfig.get('program', 'templates');
            const templates = (result && (result.success || result.code === 200) && Array.isArray(result.data)) ? result.data : [];
            select.innerHTML = '<option value="">无（内联UI）</option>' +
                templates.map(t => `<option value="${this.esc(t.id)}">${this.esc(t.name || t.id)}</option>`).join('');
            // 回显当前 template
            if (this.editingConfig && this.editingConfig.template) select.value = this.editingConfig.template;
        } catch (e) {
            console.warn('加载页面模板列表失败:', e);
        }
    }

    /** 应用选中的页面模板（设置 template 字段） */
    async applyTemplate() {
        const select = this.shadowRoot.getElementById('cfgTemplateSelect');
        if (!select) {
            if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('请先选择模板', 'warning');
            return;
        }
        const id = select.value;
        if (!id) {
            // 清除 template
            if (this.editingConfig) delete this.editingConfig.template;
            if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('已清除模板引用', 'info');
            return;
        }
        // 设置 template 字段
        if (this.editingConfig) this.editingConfig.template = id;
        if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('已引用模板: ' + id, 'success');
    }

    closeConfig() {
        const modal = this.shadowRoot.getElementById('configModal');
        if (modal) modal.classList.add('hidden');
        this.configProgramName = null;
        this.configProgramVersion = null;
        this.editingConfig = null;
    }

    renderConfigForm(config) {
        const rt = config.runtime || {};
        const set = (id, v) => { const el = this.shadowRoot.getElementById(id); if (el) el.value = v != null ? v : ''; };
        set('cfgPreRunScript', rt.preRunScript);
        set('cfgSimulinkModel', rt.simulinkModel);
        set('cfgStopTime', rt.stopTime);
        set('cfgFixedStep', rt.fixedStep);
        // setupScript 是独立字段，由 loadSetupScript 单独加载
        const ui = config.ui || {};
        set('cfgUiTitle', ui.title);
        const layoutEl = this.shadowRoot.getElementById('cfgUiLayout');
        if (layoutEl) layoutEl.value = ui.layout || 'tabs';
        const ext = ui.extension || {};
        const extEn = this.shadowRoot.getElementById('cfgExtEnabled');
        if (extEn) extEn.checked = !!ext.enabled;
        set('cfgExtMode', ext.mode || 'slot');
        set('cfgExtEntry', ext.entry);
        set('cfgExtSlot', ext.slot);
        this.renderParamRows(config.parameters || []);
        this.renderSignalRows(config.signals || []);
        this.renderSectionRows(config.ui && config.ui.sections || []);
        const raw = this.shadowRoot.getElementById('cfgRawJson');
        if (raw) raw.value = JSON.stringify(config, null, 2);
    }

    esc(v) { return String(v == null ? '' : v).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;'); }

    renderParamRows(params) {
        const container = this.shadowRoot.getElementById('paramConfigList');
        if (!container) return;
        container.innerHTML = '';
        params.forEach((p, idx) => {
            const row = document.createElement('div');
            row.className = 'config-row';
            row.innerHTML = `
                <input type="text" class="cfg-p-key" placeholder="key" value="${this.esc(p.key)}">
                <input type="text" class="cfg-p-label" placeholder="标签" value="${this.esc(p.label)}">
                <input type="text" class="cfg-p-matlabVar" placeholder="MATLAB 变量" value="${this.esc(p.matlabVar)}">
                <input type="text" class="cfg-p-default" placeholder="默认值" value="${this.esc(p.defaultValue)}">
                <input type="text" class="cfg-p-unit" placeholder="单位" value="${this.esc(p.unit)}">
                <button class="btn btn-icon delete-row" data-idx="${idx}" type="button">✕</button>
            `;
            row.querySelector('.delete-row').addEventListener('click', () => {
                this.editingConfig = this.collectConfig(false);
                this.editingConfig.parameters.splice(idx, 1);
                this.renderConfigForm(this.editingConfig);
            });
            container.appendChild(row);
        });
    }

    renderSignalRows(signals) {
        const container = this.shadowRoot.getElementById('signalConfigList');
        if (!container) return;
        container.innerHTML = '';
        const typeOpts = ['block', 'goto', 'subsystemOut', 'subsystemAllOuts', 'sfuncExtra', 'auto'];
        signals.forEach((s, idx) => {
            const row = document.createElement('div');
            row.className = 'config-row';
            const typeSelect = typeOpts.map(t => `<option value="${t}" ${s.type === t ? 'selected' : ''}>${t}</option>`).join('');
            row.innerHTML = `
                <input type="text" class="cfg-s-name" placeholder="信号名" value="${this.esc(s.name)}">
                <select class="cfg-s-type">${typeSelect}</select>
                <input type="text" class="cfg-s-path" placeholder="块路径/Goto 标签/子系统路径" value="${this.esc(s.path || s.blockPath || s.gotoTag || s.subsystemPath)}">
                <input type="text" class="cfg-s-label" placeholder="显示名" value="${this.esc(s.label)}">
                <input type="text" class="cfg-s-unit" placeholder="单位" value="${this.esc(s.unit)}">
                <button class="btn btn-icon delete-row" data-idx="${idx}" type="button">✕</button>
            `;
            row.querySelector('.delete-row').addEventListener('click', () => {
                this.editingConfig = this.collectConfig(false);
                this.editingConfig.signals.splice(idx, 1);
                this.renderConfigForm(this.editingConfig);
            });
            container.appendChild(row);
        });
    }

    renderSectionRows(sections) {
        const container = this.shadowRoot.getElementById('sectionConfigList');
        if (!container) return;
        container.innerHTML = '';
        const typeOpts = ['control', 'charts', 'readout', 'gauge', 'table', 'custom'];
        sections.forEach((sec, idx) => {
            const row = document.createElement('div');
            row.className = 'config-row';
            const typeSelect = typeOpts.map(t => `<option value="${t}" ${sec.type === t ? 'selected' : ''}>${t}</option>`).join('');
            const fieldsStr = Array.isArray(sec.rows) ? sec.rows.map(r => (r.fields || []).join(',')).join(';') : '';
            const signalsStr = sec.type === 'charts' && sec.groups ? sec.groups.map(g => (g.signals || []).join(',')).join(';') : '';
            row.innerHTML = `
                <input type="text" class="cfg-sec-id" placeholder="ID" value="${this.esc(sec.id)}">
                <input type="text" class="cfg-sec-title" placeholder="标题" value="${this.esc(sec.title)}">
                <select class="cfg-sec-type">${typeSelect}</select>
                <input type="text" class="cfg-sec-fields" placeholder="字段(逗号;分组)" value="${this.esc(fieldsStr || signalsStr)}">
                <button class="btn btn-icon delete-row" data-idx="${idx}" type="button">✕</button>
            `;
            row.querySelector('.delete-row').addEventListener('click', () => {
                this.editingConfig = this.collectConfig(false);
                this.editingConfig.ui.sections.splice(idx, 1);
                this.renderConfigForm(this.editingConfig);
            });
            container.appendChild(row);
        });
    }

    addParamRow() {
        this.editingConfig = this.collectConfig(false);
        if (!this.editingConfig.parameters) this.editingConfig.parameters = [];
        this.editingConfig.parameters.push({ key: '', label: '', matlabVar: '', defaultValue: '', unit: '' });
        this.renderConfigForm(this.editingConfig);
    }

    addSignalRow() {
        this.editingConfig = this.collectConfig(false);
        if (!this.editingConfig.signals) this.editingConfig.signals = [];
        this.editingConfig.signals.push({ name: '', type: 'block', path: '', label: '', unit: '' });
        this.renderConfigForm(this.editingConfig);
    }

    addSectionRow() {
        this.editingConfig = this.collectConfig(false);
        if (!this.editingConfig.ui) this.editingConfig.ui = { title: '', layout: 'tabs', sections: [] };
        if (!this.editingConfig.ui.sections) this.editingConfig.ui.sections = [];
        this.editingConfig.ui.sections.push({ id: '', title: '', type: 'control' });
        this.renderConfigForm(this.editingConfig);
    }

    collectConfig(parseRaw = false) {
        const raw = this.shadowRoot.getElementById('cfgRawJson') && this.shadowRoot.getElementById('cfgRawJson').value;
        if (parseRaw && raw) {
            try { return JSON.parse(raw); } catch (e) {}
        }
        const val = (id) => this.shadowRoot.getElementById(id)?.value || '';
        const num = (id, dflt) => { const v = parseFloat(val(id)); return isNaN(v) ? dflt : v; };
        const runtime = {
            preRunScript: val('cfgPreRunScript'),
            simulinkModel: val('cfgSimulinkModel'),
            stopTime: num('cfgStopTime', 30),
            fixedStep: val('cfgFixedStep')
        };
        const parameters = [];
        this.shadowRoot.querySelectorAll('#paramConfigList .config-row').forEach(row => {
            parameters.push({
                key: row.querySelector('.cfg-p-key')?.value.trim() || '',
                label: row.querySelector('.cfg-p-label')?.value.trim() || '',
                matlabVar: row.querySelector('.cfg-p-matlabVar')?.value.trim() || '',
                defaultValue: row.querySelector('.cfg-p-default')?.value.trim() || '',
                unit: row.querySelector('.cfg-p-unit')?.value.trim() || ''
            });
        });
        const signals = [];
        this.shadowRoot.querySelectorAll('#signalConfigList .config-row').forEach(row => {
            const type = row.querySelector('.cfg-s-type')?.value || 'block';
            const path = row.querySelector('.cfg-s-path')?.value.trim() || '';
            const sig = {
                name: row.querySelector('.cfg-s-name')?.value.trim() || '',
                type,
                label: row.querySelector('.cfg-s-label')?.value.trim() || '',
                unit: row.querySelector('.cfg-s-unit')?.value.trim() || ''
            };
            if (type === 'goto') sig.gotoTag = path; else if (type === 'block') sig.blockPath = path;
            else if (type === 'subsystemOut' || type === 'subsystemAllOuts') sig.subsystemPath = path;
            else sig.path = path;
            signals.push(sig);
        });
        const sections = [];
        this.shadowRoot.querySelectorAll('#sectionConfigList .config-row').forEach(row => {
            const type = row.querySelector('.cfg-sec-type')?.value || 'control';
            const fieldsStr = row.querySelector('.cfg-sec-fields')?.value.trim() || '';
            const sec = {
                id: row.querySelector('.cfg-sec-id')?.value.trim() || '',
                title: row.querySelector('.cfg-sec-title')?.value.trim() || '',
                type
            };
            if (type === 'control') {
                sec.rows = fieldsStr ? fieldsStr.split(';').map(g => ({ fields: g.split(',').map(f => f.trim()).filter(Boolean) })) : [];
            } else if (type === 'charts') {
                sec.groups = fieldsStr ? fieldsStr.split(';').map(g => ({ title: '', signals: g.split(',').map(s => s.trim()).filter(Boolean) })) : [];
            }
            sections.push(sec);
        });
        const ext = {
            enabled: !!this.shadowRoot.getElementById('cfgExtEnabled')?.checked,
            mode: val('cfgExtMode') || 'slot',
            entry: val('cfgExtEntry'),
            slot: val('cfgExtSlot')
        };
        const ui = { title: val('cfgUiTitle'), layout: val('cfgUiLayout') || 'tabs', sections, extension: ext };
        return { ...this.editingConfig, runtime, parameters, signals, ui };
    }

    /**
     * 合并表单收集的配置和 rawJson 配置：
     * - 表单支持的字段（runtime、parameters、signals、ui.title、ui.sections 基本结构、ui.extension）用表单值
     * - 表单不支持的字段（section.groups 的 yMin/yMax/series、readout items、flow、leftPanels 等）用 rawJson 值
     */
    mergeFormAndRaw(formConfig, rawConfig) {
        const merged = JSON.parse(JSON.stringify(rawConfig)); // 以 raw 为底
        // 表单字段覆盖
        merged.runtime = formConfig.runtime;
        merged.setupScript = formConfig.setupScript;
        merged.parameters = formConfig.parameters;
        merged.signals = formConfig.signals;
        if (formConfig.ui) {
            if (!merged.ui) merged.ui = {};
            merged.ui.title = formConfig.ui.title;
            merged.ui.layout = formConfig.ui.layout;
            merged.ui.extension = formConfig.ui.extension;
            // sections：表单收集的是基本结构，raw 可能有更多字段（groups 详细配置、readout items）
            // 按 id 合并：表单值覆盖基本字段，raw 补充表单不支持的字段
            if (formConfig.ui.sections && rawConfig.ui && rawConfig.ui.sections) {
                merged.ui.sections = formConfig.ui.sections.map(fs => {
                    const rs = rawConfig.ui.sections.find(r => r.id === fs.id);
                    if (!rs) return fs;
                    const mergedSec = JSON.parse(JSON.stringify(rs)); // raw 为底
                    mergedSec.id = fs.id;
                    mergedSec.title = fs.title;
                    mergedSec.type = fs.type;
                    // charts 类型：表单可能只收集了 signals，raw 有完整 groups（含 yMin/yMax/series）
                    if (fs.type === 'charts' && rs.groups) {
                        mergedSec.groups = rs.groups; // 保留 raw 的完整 groups
                    }
                    return mergedSec;
                });
            } else {
                merged.ui.sections = formConfig.ui.sections;
            }
        }
        return merged;
    }

    handleConfigUpload(e) {
        const file = e.target.files && e.target.files[0];
        if (!file) return;
        const inputEl = e.target;
        const reader = new FileReader();
        reader.onload = (ev) => {
            try {
                const parsed = JSON.parse(ev.target.result);
                this.editingConfig = this.normalizeConfig(parsed, { name: this.configProgramName });
                this.renderConfigForm(this.editingConfig);
                if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('配置已加载', 'success');
            } catch (err) {
                if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('JSON 解析失败: ' + err.message, 'error');
            }
            if (inputEl) inputEl.value = '';
        };
        reader.readAsText(file);
    }

    async saveConfig() {
        // 从可视化表单收集配置（包含插件扩展字段）
        let config = this.collectConfig(false);
        // 合并 rawJson 里表单不支持的字段（如 chart groups 的 yMin/yMax、readout items 等）
        const rawEl = this.shadowRoot.getElementById('cfgRawJson');
        if (rawEl && rawEl.value && rawEl.value.trim()) {
            try {
                const rawConfig = JSON.parse(rawEl.value);
                // 用 rawConfig 的深层字段补全表单不支持的配置
                config = this.mergeFormAndRaw(config, rawConfig);
            } catch (e) {
                if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('原始 JSON 格式错误: ' + e.message, 'error');
                return;
            }
        }
        // 保留 template 字段
        const tplSelect = this.shadowRoot.getElementById('cfgTemplateSelect');
        if (tplSelect && tplSelect.value) config.template = tplSelect.value;
        else delete config.template;
        try {
            const pn = this.configProjectName || this.getProjectName();
            // 1. 保存配置 JSON
            const url = window.AppConfig.getApiUrl('program', 'config') + '?name=' + encodeURIComponent(this.configProgramName) + '&version=' + encodeURIComponent(this.configProgramVersion) + (pn ? '&projectName=' + encodeURIComponent(pn) : '');
            const result = await window.AppConfig.request(url, {
                method: 'PUT',
                body: JSON.stringify(config)
            });
            if (!(result && (result.success || result.code === 200))) {
                throw new Error(result.message || '保存失败');
            }
            // 2. 保存 setupScript（独立字段）
            const scriptEl = this.shadowRoot.getElementById('cfgSetupScript');
            if (scriptEl) {
                const scriptUrl = window.AppConfig.getApiUrl('program', 'setup-script') + '?name=' + encodeURIComponent(this.configProgramName) + '&version=' + encodeURIComponent(this.configProgramVersion) + (pn ? '&projectName=' + encodeURIComponent(pn) : '');
                await window.AppConfig.request(scriptUrl, {
                    method: 'PUT',
                    headers: { 'Content-Type': 'text/plain' },
                    body: scriptEl.value
                });
            }
            if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('配置已保存', 'success');
            this.closeConfig();
            this.loadPrograms();
        } catch (e) {
            console.error('保存配置失败:', e);
            if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('保存配置失败: ' + e.message, 'error');
        }
    }

    async loadPrograms() {
        try {
            const params = { pageNum: this.pageNum, pageSize: this.pageSize };
            if (this.filterName) params.name = this.filterName;
            if (this.filterProject) params.projectName = this.filterProject;
            const result = await window.AppConfig.get('program', 'list', params);
            this.programs = (result && result.data) || [];
            const countResult = await window.AppConfig.get('program', 'count', {
                ...(this.filterName ? { name: this.filterName } : {}),
                ...(this.filterProject ? { projectName: this.filterProject } : {})
            });
            this.total = (countResult && countResult.data) || 0;
            this.renderTable();
            this.renderPagination();
        } catch (e) {
            console.error('加载程序列表失败:', e);
            if (window.CommonUtils && window.CommonUtils.showToast) {
                window.CommonUtils.showToast('加载程序列表失败', 'error');
            }
        }
    }

    renderTable() {
        const tbody = this.shadowRoot.getElementById('tableBody');
        const emptyHint = this.shadowRoot.getElementById('emptyHint');
        if (!this.programs.length) {
            tbody.innerHTML = '';
            emptyHint.hidden = false;
            return;
        }
        emptyHint.hidden = true;
        tbody.innerHTML = this.programs.map(p => {
            const time = p.timestamp ? new Date(p.timestamp).toLocaleString() : '-';
            const statusClass = p.status === 'RUNNING' ? 'running' : p.status === 'ERROR' ? 'error' : 'ready';
            return `
                <tr data-name="${p.name || ''}" data-version="${p.version || ''}" data-project="${p.projectName || ''}">
                    <td>${p.name || '-'}</td>
                    <td>${p.version || '-'}</td>
                    <td>${p.projectName || '-'}</td>
                    <td>${p.description || '-'}</td>
                    <td>${time}</td>
                    <td><span class="status ${statusClass}">${p.status || 'READY'}</span></td>
                    <td class="actions">
                        <button class="run-btn filter-btn outline" data-name="${p.name || ''}" data-version="${p.version || ''}" data-project="${p.projectName || ''}">运行</button>
                        <button class="config-btn filter-btn outline" data-name="${p.name || ''}" data-version="${p.version || ''}" data-project="${p.projectName || ''}">配置</button>
                        <button class="download-btn filter-btn outline" data-name="${p.name || ''}" data-version="${p.version || ''}" data-project="${p.projectName || ''}">下载</button>
                        <button class="delete-btn filter-btn outline" data-name="${p.name || ''}" data-version="${p.version || ''}" data-project="${p.projectName || ''}">删除</button>
                    </td>
                </tr>
            `;
        }).join('');
    }

    renderPagination() {
        const pageInfo = this.shadowRoot.getElementById('pageInfo');
        const pageNumbers = this.shadowRoot.getElementById('pageNumbers');
        const prevPageBtn = this.shadowRoot.getElementById('prevPageBtn');
        const nextPageBtn = this.shadowRoot.getElementById('nextPageBtn');
        const maxPage = Math.max(1, Math.ceil(this.total / this.pageSize));
        if (pageInfo) pageInfo.textContent = `共 ${this.total} 条，第 ${this.pageNum}/${maxPage} 页`;
        if (prevPageBtn) prevPageBtn.disabled = this.pageNum <= 1;
        if (nextPageBtn) nextPageBtn.disabled = this.pageNum >= maxPage;
        if (pageNumbers) {
            let html = '';
            const start = Math.max(1, this.pageNum - 2);
            const end = Math.min(maxPage, this.pageNum + 2);
            for (let i = start; i <= end; i++) {
                const cls = i === this.pageNum ? 'filter-btn active' : 'filter-btn';
                html += `<button class="${cls}" data-page="${i}">${i}</button>`;
            }
            pageNumbers.innerHTML = html;
            pageNumbers.querySelectorAll('button[data-page]').forEach(btn => {
                btn.addEventListener('click', () => {
                    this.pageNum = parseInt(btn.dataset.page);
                    this.loadPrograms();
                });
            });
        }
    }

    async handleUpload() {
        this.clearUploadErrors();
        const nameInput = this.shadowRoot.getElementById('uploadName');
        const versionInput = this.shadowRoot.getElementById('uploadVersion');
        const descriptionInput = this.shadowRoot.getElementById('uploadDescription');
        const file = this.selectedFile;
        const name = nameInput ? nameInput.value.trim() : '';
        const version = versionInput ? versionInput.value.trim() : '';

        let valid = true;
        if (!file) {
            this.setFieldError('uploadFile', '请选择程序压缩包');
            valid = false;
        }
        if (!name) {
            this.setFieldError('uploadName', '请输入程序名称');
            valid = false;
        }
        if (!version) {
            this.setFieldError('uploadVersion', '请输入版本号');
            valid = false;
        }
        if (!valid) return;

        const formData = new FormData();
        formData.append('file', file);
        formData.append('name', name);
        formData.append('version', version);
        formData.append('description', descriptionInput ? descriptionInput.value.trim() : '');
        try {
            const result = await window.AppConfig.upload('program', 'upload', formData);
            if (result && (result.success || result.code === 200)) {
                if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('上传成功', 'success');
                this.resetUploadForm();
                this.loadPrograms();
            } else {
                throw new Error(result.message || '上传失败');
            }
        } catch (e) {
            console.error('上传失败:', e);
            if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('上传失败: ' + e.message, 'error');
        }
    }

    handleFileSelect(file) {
        if (!file) return;
        const allowedExtensions = ['.zip', '.rar', '.7z', '.tar', '.tar.gz', '.tgz'];
        const lower = file.name.toLowerCase();
        let ext = lower.substring(lower.lastIndexOf('.'));
        if (lower.endsWith('.tar.gz')) ext = '.tar.gz';
        if (lower.endsWith('.tgz')) ext = '.tgz';
        if (!allowedExtensions.includes(ext)) {
            if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('不支持的文件格式', 'error');
            return;
        }
        if (file.size > 1024 * 1024 * 1024) {
            if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('文件大小不能超过1GB', 'error');
            return;
        }
        this.selectedFile = file;
        const fileUploadArea = this.shadowRoot.getElementById('fileUploadArea');
        const fileInfo = this.shadowRoot.getElementById('fileInfo');
        const fileName = this.shadowRoot.getElementById('fileName');
        const fileSize = this.shadowRoot.getElementById('fileSize');
        if (fileUploadArea) fileUploadArea.style.display = 'none';
        if (fileInfo) fileInfo.style.display = 'flex';
        if (fileName) fileName.textContent = file.name;
        if (fileSize) fileSize.textContent = this.formatFileSize(file.size);
        this.clearFieldError('uploadFile');
    }

    removeFile() {
        this.selectedFile = null;
        const fileUploadArea = this.shadowRoot.getElementById('fileUploadArea');
        const fileInfo = this.shadowRoot.getElementById('fileInfo');
        const fileInput = this.shadowRoot.getElementById('uploadFile');
        if (fileUploadArea) fileUploadArea.style.display = 'block';
        if (fileInfo) fileInfo.style.display = 'none';
        if (fileInput) fileInput.value = '';
    }

    resetUploadForm() {
        const nameInput = this.shadowRoot.getElementById('uploadName');
        const versionInput = this.shadowRoot.getElementById('uploadVersion');
        const descriptionInput = this.shadowRoot.getElementById('uploadDescription');
        if (nameInput) nameInput.value = '';
        if (versionInput) versionInput.value = '';
        if (descriptionInput) descriptionInput.value = '';
        this.removeFile();
        this.clearUploadErrors();
    }

    formatFileSize(bytes) {
        if (bytes === 0) return '0 Bytes';
        const k = 1024;
        const sizes = ['Bytes', 'KB', 'MB', 'GB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
    }

    setFieldError(fieldId, message) {
        const input = this.shadowRoot.getElementById(fieldId);
        const errorEl = this.shadowRoot.getElementById(fieldId + 'Error');
        if (input) input.classList.add('error');
        if (errorEl) errorEl.classList.add('show');
    }

    clearFieldError(fieldId) {
        const input = this.shadowRoot.getElementById(fieldId);
        const errorEl = this.shadowRoot.getElementById(fieldId + 'Error');
        if (input) input.classList.remove('error');
        if (errorEl) errorEl.classList.remove('show');
    }

    clearUploadErrors() {
        ['uploadFile', 'uploadName', 'uploadVersion'].forEach(id => this.clearFieldError(id));
    }

    async runProgram(name, version) {
        try {
            const pn = this.getProjectName();
            const url = window.AppConfig.getApiUrl('program', 'run') + '?name=' + encodeURIComponent(name) + '&version=' + encodeURIComponent(version) + (pn ? '&projectName=' + encodeURIComponent(pn) : '');
            const result = await window.AppConfig.request(url, { method: 'POST' });
            if (result && (result.success || result.code === 200)) {
                if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('运行已开始', 'success');
                this.loadPrograms();
            } else {
                throw new Error(result.message || '运行失败');
            }
        } catch (e) {
            console.error('运行失败:', e);
            if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('运行失败: ' + e.message, 'error');
        }
    }

    openProgramRun(name, version, programProjectName) {
        const currentProject = this.getProjectName();
        if (programProjectName && programProjectName !== currentProject) {
            const doSwitch = () => {
                this.switchProject(programProjectName);
                this._doShowProgramRun(name, version);
            };
            if (window.showConfirmDialog) {
                window.showConfirmDialog(
                    '切换项目确认',
                    `程序 "${name}" 属于项目 ${programProjectName}，当前项目为 ${currentProject || '未选择'}，是否先切换项目？`,
                    doSwitch
                );
            } else if (confirm(`程序 "${name}" 属于项目 ${programProjectName}，当前项目为 ${currentProject || '未选择'}，是否切换项目？`)) {
                doSwitch();
            }
        } else {
            this._doShowProgramRun(name, version);
        }
    }

    _doShowProgramRun(name, version) {
        const programRun = document.getElementById('programRun');
        if (!programRun) {
            console.error('未找到 program-run 组件');
            return;
        }
        programRun.setAttribute('data-name', name);
        programRun.setAttribute('data-version', version);
        if (window.showComponent) window.showComponent('programRun');
        if (programRun.loadProgramFiles) programRun.loadProgramFiles(name, version);
    }

    switchProject(projectName) {
        const username = window.AppConfig.getUsername ? window.AppConfig.getUsername() : localStorage.getItem('username');
        if (username && projectName) {
            localStorage.setItem('currentProject_' + username, JSON.stringify({ name: projectName }));
        }
        if (window.loadProjectTree) window.loadProjectTree();
    }

    async loadResults(name, version) {
        const resultPanel = this.shadowRoot.getElementById('resultPanel');
        const statusText = this.shadowRoot.getElementById('statusText');
        const csvPreview = this.shadowRoot.getElementById('csvPreview');
        resultPanel.classList.remove('hidden');
        statusText.textContent = '加载中...';
        csvPreview.innerHTML = '';
        try {
            const pn = this.getProjectName();
            const result = await window.AppConfig.get('program', 'results', { name, version, ...(pn ? { projectName: pn } : {}) });
            if (result && result.code === 200 && result.data) {
                statusText.textContent = `状态: ${result.data.status || 'UNKNOWN'}`;
                if (result.data.rows && result.data.headers) {
                    csvPreview.innerHTML = this.renderCsv(result.data.headers, result.data.rows);
                } else {
                    csvPreview.innerHTML = '<p>暂无结果数据</p>';
                }
            } else {
                throw new Error(result.message || '无结果');
            }
        } catch (e) {
            statusText.textContent = '加载结果失败: ' + e.message;
        }
    }

    renderCsv(headers, rows) {
        const th = headers.map(h => `<th>${h}</th>`).join('');
        const tr = rows.slice(0, 100).map(r => `<tr>${r.map(c => `<td>${c != null ? c : ''}</td>`).join('')}</tr>`).join('');
        return `<table><thead><tr>${th}</tr></thead><tbody>${tr}</tbody></table>`;
    }

    async deleteProgram(name, version) {
        if (window.showConfirmDialog) {
            window.showConfirmDialog('确认删除', `确定要删除程序 ${name}@${version} 吗？删除后无法恢复。`, () => this._doDeleteProgram(name, version));
        } else {
            this._doDeleteProgram(name, version);
        }
    }

    async _doDeleteProgram(name, version) {
        try {
            const pn = this.getProjectName();
            const result = await window.AppConfig.delete('program', 'delete', { name, version, ...(pn ? { projectName: pn } : {}) });
            if (result && (result.success || result.code === 200)) {
                if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('删除成功', 'success');
                this.loadPrograms();
            } else {
                throw new Error(result.message || '删除失败');
            }
        } catch (e) {
            console.error('删除失败:', e);
            if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('删除失败: ' + e.message, 'error');
        }
    }

    async downloadProgram(name, version, projectName) {
        try {
            // 1. 下载源码包
            const downloadData = {
                name: name,
                version: version,
                ...(projectName ? { projectName: projectName } : {})
            };
            await window.AppConfig.download('program', 'download', downloadData, null, true);
            // 2. 下载配置 JSON
            const pn = projectName || this.getProjectName();
            const cfgResult = await window.AppConfig.get('program', 'config', { name, version, ...(pn ? { projectName: pn } : {}) });
            if (cfgResult && (cfgResult.success || cfgResult.code === 200) && cfgResult.data) {
                const cfgData = typeof cfgResult.data === 'string' ? cfgResult.data : JSON.stringify(cfgResult.data, null, 2);
                const cfgBlob = new Blob([cfgData], { type: 'application/json' });
                const cfgA = document.createElement('a');
                cfgA.href = URL.createObjectURL(cfgBlob);
                cfgA.download = 'config.json';
                cfgA.click();
                URL.revokeObjectURL(cfgA.href);
            }
            // 3. 下载脚本
            const scriptResult = await window.AppConfig.get('program', 'setup-script', { name, version, ...(pn ? { projectName: pn } : {}) });
            if (scriptResult && (scriptResult.success || scriptResult.code === 200) && scriptResult.data) {
                const scriptBlob = new Blob([scriptResult.data], { type: 'text/plain' });
                const scriptA = document.createElement('a');
                scriptA.href = URL.createObjectURL(scriptBlob);
                scriptA.download = 'dmg_setup.m';
                scriptA.click();
                URL.revokeObjectURL(scriptA.href);
            }
            if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('下载成功', 'success');
        } catch (e) {
            console.error('下载失败:', e);
            if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('下载失败: ' + e.message, 'error');
        }
    }

    getProjectName() {
        const username = window.AppConfig.getUsername ? window.AppConfig.getUsername() : localStorage.getItem('username');
        if (username) {
            const cached = JSON.parse(localStorage.getItem('currentProject_' + username) || 'null');
            if (cached) return cached.name;
        }
        return null;
    }
}

customElements.define('program-management', ProgramManagement);
