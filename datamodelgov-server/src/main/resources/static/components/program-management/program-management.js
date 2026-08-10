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
                    if (btn.classList.contains('delete-btn')) this.deleteProgram(name, version);
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
        const addSystemBtn = this.shadowRoot.getElementById('addSystemBtn');
        const addOutputBtn = this.shadowRoot.getElementById('addOutputBtn');

        if (configCloseBtn) configCloseBtn.addEventListener('click', () => this.closeConfig());
        if (configCancelBtn) configCancelBtn.addEventListener('click', () => this.closeConfig());
        if (configSaveBtn) configSaveBtn.addEventListener('click', () => this.saveConfig());
        if (addSystemBtn) addSystemBtn.addEventListener('click', () => this.addSystemRow());
        if (addOutputBtn) addOutputBtn.addEventListener('click', () => this.addOutputRow());
    }

    show() { this.style.display = 'block'; this.loadPrograms(); }
    hide() { this.style.display = 'none'; }

    normalizeConfig(config, program) {
        return {
            programName: (config && config.programName) || (program && program.name) || '',
            runtime: (config && config.runtime) || {},
            systems: (config && config.systems) || [],
            outputs: (config && config.outputs) || []
        };
    }

    openConfig(name, version) {
        this.configProgramName = name;
        this.configProgramVersion = version;
        const program = this.programs.find(p => p.name === name && p.version === version);
        const nameEl = this.shadowRoot.getElementById('configProgramName');
        if (nameEl) nameEl.textContent = program ? (program.name || '-') : '-';
        let config = {};
        try {
            config = program && program.configJson ? JSON.parse(program.configJson) : {};
        } catch (e) { config = {}; }
        this.editingConfig = this.normalizeConfig(config, program);
        this.renderConfigForm(this.editingConfig);
        const modal = this.shadowRoot.getElementById('configModal');
        if (modal) modal.classList.remove('hidden');
    }

    closeConfig() {
        const modal = this.shadowRoot.getElementById('configModal');
        if (modal) modal.classList.add('hidden');
        this.configProgramName = null;
        this.configProgramVersion = null;
        this.editingConfig = null;
    }

    renderConfigForm(config) {
        const runtime = config.runtime || {};
        const sim = this.shadowRoot.getElementById('cfgSimulinkModel');
        const pre = this.shadowRoot.getElementById('cfgPreRunScript');
        const stop = this.shadowRoot.getElementById('cfgStopTime');
        if (sim) sim.value = runtime.simulinkModel || '';
        if (pre) pre.value = runtime.preRunScript || '';
        if (stop) stop.value = runtime.stopTime != null ? runtime.stopTime : '';
        this.renderSystemRows(config.systems || []);
        this.renderOutputRows(config.outputs || []);
        const raw = this.shadowRoot.getElementById('cfgRawJson');
        if (raw) raw.value = JSON.stringify(config, null, 2);
    }

    renderSystemRows(systems) {
        const container = this.shadowRoot.getElementById('systemConfigList');
        if (!container) return;
        container.innerHTML = '';
        const iconOptions = ['⚙', '🔥', '💧', '⚡', '📊', '🛠', '🧭', '🔋', '✈', '🌡'];
        const colorOptions = [
            { value: 'purple', label: '紫色' },
            { value: 'orange', label: '橙色' },
            { value: 'green', label: '绿色' },
            { value: 'blue', label: '蓝色' },
            { value: 'cyan', label: '青色' }
        ];
        const esc = (v) => String(v == null ? '' : v).replace(/"/g, '&quot;').replace(/</g, '&lt;');
        systems.forEach((s, idx) => {
            const row = document.createElement('div');
            row.className = 'config-row';
            const currentIcon = s.icon || '';
            const currentColor = s.color || '';
            let iconSelect = `<option value="">-</option>` + iconOptions.map(icon => {
                const selected = icon === currentIcon ? 'selected' : '';
                return `<option value="${esc(icon)}" ${selected}>${esc(icon)}</option>`;
            }).join('');
            if (currentIcon && !iconOptions.includes(currentIcon)) {
                iconSelect = `<option value="${esc(currentIcon)}" selected>${esc(currentIcon)}</option>` + iconSelect.replace('<option value="">-</option>', '');
            }
            let colorSelect = `<option value="">-</option>` + colorOptions.map(c => {
                const selected = c.value === currentColor ? 'selected' : '';
                return `<option value="${esc(c.value)}" ${selected}>${esc(c.label)}</option>`;
            }).join('');
            if (currentColor && !colorOptions.some(c => c.value === currentColor)) {
                colorSelect = `<option value="${esc(currentColor)}" selected>${esc(currentColor)}</option>` + colorSelect;
            }
            row.innerHTML = `
                <input type="text" class="cfg-sys-id" placeholder="ID" value="${esc(s.id)}">
                <input type="text" class="cfg-sys-name" placeholder="名称" value="${esc(s.name)}">
                <select class="cfg-sys-icon">${iconSelect}</select>
                <select class="cfg-sys-color">${colorSelect}</select>
                <input type="text" class="cfg-sys-keywords" placeholder="关键字,逗号分隔" value="${(Array.isArray(s.keywords) ? s.keywords.join(',') : (s.keywords || '')).replace(/"/g, '&quot;')}">
                <button class="btn btn-icon delete-row" data-idx="${idx}" type="button">✕</button>
            `;
            row.querySelector('.delete-row').addEventListener('click', () => {
                this.editingConfig.systems.splice(idx, 1);
                this.renderConfigForm(this.editingConfig);
            });
            container.appendChild(row);
        });
    }

    renderOutputRows(outputs) {
        const container = this.shadowRoot.getElementById('outputConfigList');
        if (!container) return;
        container.innerHTML = '';
        const systems = (this.editingConfig && this.editingConfig.systems) || [];
        outputs.forEach((o, idx) => {
            const opts = systems.map(s => `<option value="${(s.id || '').replace(/"/g, '&quot;')}" ${(o.system || '') === s.id ? 'selected' : ''}>${(s.name || s.id || '').replace(/</g, '&lt;')}</option>`).join('');
            const row = document.createElement('div');
            row.className = 'config-row';
            row.innerHTML = `
                <input type="text" class="cfg-out-name" placeholder="信号名" value="${(o.name || '').replace(/"/g, '&quot;')}">
                <select class="cfg-out-system"><option value="">-</option>${opts}</select>
                <input type="text" class="cfg-out-unit" placeholder="单位" value="${(o.unit || '').replace(/"/g, '&quot;')}">
                <button class="btn btn-icon delete-row" data-idx="${idx}" type="button">✕</button>
            `;
            row.querySelector('.delete-row').addEventListener('click', () => {
                this.editingConfig.outputs.splice(idx, 1);
                this.renderConfigForm(this.editingConfig);
            });
            container.appendChild(row);
        });
    }

    addSystemRow() {
        this.editingConfig = this.collectConfig(false);
        this.editingConfig.systems.push({ id: '', name: '', icon: '', color: '', keywords: [] });
        this.renderConfigForm(this.editingConfig);
    }

    addOutputRow() {
        this.editingConfig = this.collectConfig(false);
        this.editingConfig.outputs.push({ name: '', system: '', unit: '' });
        this.renderConfigForm(this.editingConfig);
    }

    collectConfig(parseRaw = false) {
        const raw = this.shadowRoot.getElementById('cfgRawJson') && this.shadowRoot.getElementById('cfgRawJson').value;
        if (parseRaw && raw) {
            try { return JSON.parse(raw); } catch (e) {}
        }
        const runtime = {
            simulinkModel: this.shadowRoot.getElementById('cfgSimulinkModel')?.value || '',
            preRunScript: this.shadowRoot.getElementById('cfgPreRunScript')?.value || '',
            stopTime: parseFloat(this.shadowRoot.getElementById('cfgStopTime')?.value) || 30
        };
        const systems = [];
        this.shadowRoot.querySelectorAll('#systemConfigList .config-row').forEach(row => {
            const keywords = (row.querySelector('.cfg-sys-keywords')?.value || '').split(',').map(k => k.trim()).filter(k => k);
            systems.push({
                id: row.querySelector('.cfg-sys-id')?.value.trim() || '',
                name: row.querySelector('.cfg-sys-name')?.value.trim() || '',
                icon: row.querySelector('.cfg-sys-icon')?.value.trim() || '',
                color: row.querySelector('.cfg-sys-color')?.value.trim() || '',
                keywords
            });
        });
        const outputs = [];
        this.shadowRoot.querySelectorAll('#outputConfigList .config-row').forEach(row => {
            outputs.push({
                name: row.querySelector('.cfg-out-name')?.value.trim() || '',
                system: row.querySelector('.cfg-out-system')?.value || '',
                unit: row.querySelector('.cfg-out-unit')?.value.trim() || ''
            });
        });
        return { ...this.editingConfig, runtime, systems, outputs };
    }

    async saveConfig() {
        const config = this.collectConfig(false);
        try {
            const pn = this.getProjectName();
            const url = window.AppConfig.getApiUrl('program', 'update-config') + '?name=' + encodeURIComponent(this.configProgramName) + '&version=' + encodeURIComponent(this.configProgramVersion) + (pn ? '&projectName=' + encodeURIComponent(pn) : '');
            const result = await window.AppConfig.request(url, {
                method: 'POST',
                body: JSON.stringify(config)
            });
            if (result && (result.success || result.code === 200)) {
                if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('配置已保存', 'success');
                this.closeConfig();
                this.loadPrograms();
            } else {
                throw new Error(result.message || '保存失败');
            }
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
