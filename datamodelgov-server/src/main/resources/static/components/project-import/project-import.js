class ProjectImport extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });
        this._selectedFile = null;
        this.resourceType = null;
    }

    async connectedCallback() {
        await this.loadResources();
        setTimeout(() => this.bindEvents(), 100);
    }

    async loadResources() {
        const cssLink = document.createElement('link');
        cssLink.rel = 'stylesheet';
        cssLink.href = './components/project-import/project-import.css';
        this.shadowRoot.appendChild(cssLink);

        try {
            const response = await fetch('./components/project-import/project-import.html');
            if (response.ok) {
                const html = await response.text();
                this.shadowRoot.innerHTML += html;
            } else {
                this.shadowRoot.innerHTML += this.getFallbackHTML();
            }
        } catch (error) {
            console.error('Failed to load HTML template:', error);
            this.shadowRoot.innerHTML += this.getFallbackHTML();
        }
    }

    getFallbackHTML() {
        return `
<div class="project-import">
    <div class="import-card">
        <div class="import-header">导入项目</div>
        <div class="import-body">
            <div class="import-field">
                <span class="import-label">选择项目资源包</span>
                <div class="import-file-area" id="fileDropArea">
                    <input type="file" id="importFile" accept=".zip" style="display: none;" />
                    <div class="import-file-hint" id="fileHint">
                        <span>点击或拖拽ZIP文件到此处</span>
                    </div>
                    <div class="import-file-name" id="fileName" style="display: none;">
                        <span id="fileNameText"></span>
                        <button class="import-file-remove" id="removeFileBtn">&times;</button>
                    </div>
                </div>
            </div>
            <div class="import-progress" id="importProgress" style="display: none;">
                <div class="import-progress-bar">
                    <div class="import-progress-fill" id="progressFill"></div>
                </div>
                <div class="import-progress-text" id="progressText">正在导入...</div>
            </div>
        </div>
        <div class="import-actions">
            <button class="import-btn outline" type="button" id="cancelBtn">取消</button>
            <button class="import-btn solid" type="button" id="importBtn" disabled>导入</button>
        </div>
    </div>
</div>`;
    }

    show(options = {}) {
        this.resourceType = options.resourceType || null;
        this.style.display = 'block';
        this.applyMode();
        this.resetForm();
        if (this.resourceType) {
            this.loadProjectList();
        }
    }

    hide() {
        this.style.display = 'none';
    }

    resetForm() {
        const root = this.shadowRoot;
        this._selectedFile = null;
        const input = root.getElementById('importFile');
        if (input) input.value = '';
        const hint = root.getElementById('fileHint');
        const nameEl = root.getElementById('fileName');
        if (hint) hint.style.display = '';
        if (nameEl) nameEl.style.display = 'none';
        const importBtn = root.getElementById('importBtn');
        if (importBtn) importBtn.disabled = true;
        const progress = root.getElementById('importProgress');
        if (progress) progress.style.display = 'none';
        const targetProjectSelect = root.getElementById('targetProjectSelect');
        if (targetProjectSelect) targetProjectSelect.value = '';
    }

    applyMode() {
        const header = this.shadowRoot.getElementById('importHeader');
        const select = this.shadowRoot.getElementById('targetProjectSelect');
        const field = this.shadowRoot.getElementById('targetProjectField');
        const typeName = this.getResourceTypeName(this.resourceType);
        if (header) header.textContent = typeName ? `导入${typeName}` : '导入项目';
        if (field) field.style.display = this.resourceType ? '' : 'none';
        if (select) select.options[0].textContent = this.resourceType ? '请选择目标项目' : '使用资源包内项目名';
    }

    getResourceTypeName(type) {
        return {
            algorithm: '算法',
            model: '模型',
            data: '数据',
            simulation: '仿真'
        }[type] || '';
    }

    async loadProjectList() {
        try {
            const result = await window.AppConfig.post('project', 'query', {
                pageNum: 1,
                pageSize: 100
            });
            const select = this.shadowRoot.getElementById('targetProjectSelect');
            if (!select) return;
            while (select.options.length > 1) {
                select.remove(1);
            }
            if (result.code === 200 && result.data) {
                result.data.forEach(project => {
                    const option = document.createElement('option');
                    option.value = project.name;
                    option.textContent = project.name + (project.desc ? ' - ' + project.desc : '');
                    select.appendChild(option);
                });
                const username = window.AppConfig?.getUsername?.();
                const cached = window.localStorage?.getItem('currentProject_' + username);
                if (cached) {
                    try {
                        const current = JSON.parse(cached);
                        select.value = current.name;
                    } catch (e) {}
                }
            }
        } catch (error) {
            console.error('加载项目列表失败:', error);
        }
    }

    bindEvents() {
        if (this._eventsBound) return;
        this._eventsBound = true;

        const root = this.shadowRoot;
        const fileInput = root.getElementById('importFile');
        const dropArea = root.getElementById('fileDropArea');

        // Click to select file
        dropArea?.addEventListener('click', (e) => {
            if (e.target.id !== 'removeFileBtn') {
                fileInput?.click();
            }
        });

        // File selected
        fileInput?.addEventListener('change', (e) => {
            if (e.target.files && e.target.files[0]) {
                this.setSelectedFile(e.target.files[0]);
            }
        });

        // Drag and drop
        dropArea?.addEventListener('dragover', (e) => {
            e.preventDefault();
            dropArea.classList.add('dragover');
        });

        dropArea?.addEventListener('dragleave', () => {
            dropArea.classList.remove('dragover');
        });

        dropArea?.addEventListener('drop', (e) => {
            e.preventDefault();
            dropArea.classList.remove('dragover');
            if (e.dataTransfer.files && e.dataTransfer.files[0]) {
                const file = e.dataTransfer.files[0];
                if (file.name.endsWith('.zip')) {
                    this.setSelectedFile(file);
                } else {
                    this.showToast('请选择ZIP文件', 'error');
                }
            }
        });

        // Remove file
        root.getElementById('removeFileBtn')?.addEventListener('click', (e) => {
            e.stopPropagation();
            this.resetFileSelection();
        });

        // Cancel
        root.getElementById('cancelBtn')?.addEventListener('click', () => this.hide());

        // Import
        root.getElementById('importBtn')?.addEventListener('click', () => this.handleImport());
    }

    setSelectedFile(file) {
        this._selectedFile = file;
        const root = this.shadowRoot;
        const hint = root.getElementById('fileHint');
        const nameEl = root.getElementById('fileName');
        const nameText = root.getElementById('fileNameText');
        const importBtn = root.getElementById('importBtn');

        if (hint) hint.style.display = 'none';
        if (nameEl) nameEl.style.display = 'flex';
        if (nameText) nameText.textContent = file.name + ' (' + this.formatFileSize(file.size) + ')';
        if (importBtn) importBtn.disabled = false;
    }

    resetFileSelection() {
        this._selectedFile = null;
        const root = this.shadowRoot;
        const input = root.getElementById('importFile');
        if (input) input.value = '';
        const hint = root.getElementById('fileHint');
        const nameEl = root.getElementById('fileName');
        const importBtn = root.getElementById('importBtn');
        if (hint) hint.style.display = '';
        if (nameEl) nameEl.style.display = 'none';
        if (importBtn) importBtn.disabled = true;
    }

    formatFileSize(bytes) {
        if (bytes < 1024) return bytes + ' B';
        if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
        return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
    }

    async handleImport() {
        if (!this._selectedFile) {
            this.showToast('请选择ZIP文件', 'error');
            return;
        }

        const root = this.shadowRoot;
        const targetProjectName = root.getElementById('targetProjectSelect')?.value || '';
        if (this.resourceType && !targetProjectName) {
            this.showToast('请选择目标项目', 'error');
            return;
        }

        const formData = new FormData();
        formData.append('file', this._selectedFile);
        if (targetProjectName) {
            formData.append('projectName', targetProjectName);
        }

        const progress = root.getElementById('importProgress');
        const progressFill = root.getElementById('progressFill');
        const progressText = root.getElementById('progressText');
        const importBtn = root.getElementById('importBtn');

        try {
            if (progress) progress.style.display = 'block';
            if (progressFill) progressFill.style.width = '30%';
            if (progressText) progressText.textContent = '正在上传文件...';
            if (importBtn) importBtn.disabled = true;

            const authHeaders = window.AppConfig?.getAuthHeaders?.() || {};
            const headers = {};
            if (authHeaders['Authorization']) {
                headers['Authorization'] = authHeaders['Authorization'];
            }

            const importUrl = this.resourceType ? `/api/project/import/${this.resourceType}` : '/api/project/import';
            const response = await fetch(importUrl, {
                method: 'POST',
                headers: headers,
                body: formData
            });

            if (progressFill) progressFill.style.width = '80%';
            if (progressText) progressText.textContent = '正在处理导入...';

            const result = await response.json();

            if (progressFill) progressFill.style.width = '100%';

            if (result.code === 200) {
                if (progressText) progressText.textContent = '导入成功！';
                const data = result.data || {};
                const targetProjectName = data.targetProjectName;
                const summary = [
                    data.targetProjectName ? '项目: ' + data.targetProjectName : '',
                    data.algorithmCount ? '算法: ' + data.algorithmCount + ' 个' : '',
                    data.modelCount ? '模型: ' + data.modelCount + ' 个' : '',
                    data.dataCount ? '数据: ' + data.dataCount + ' 个' : '',
                    data.simulationCount ? '仿真: ' + data.simulationCount + ' 个' : ''
                ].filter(s => s).join('，');
                if (window.CommonUtils && window.CommonUtils.showToast) {
                    window.CommonUtils.showToast('导入成功' + (summary ? '，' + summary : ''));
                } else {
                    this.showToast('导入成功' + (summary ? '，' + summary : ''));
                }
                setTimeout(async () => {
                    this.hide();
                    // 打开导入的项目
                    if (targetProjectName) {
                        try {
                            // 先查询项目获取createTime
                            const queryResult = await window.AppConfig.post('project', 'query', { name: targetProjectName, pageNum: 1, pageSize: 1 });
                            if (queryResult.code === 200 && queryResult.data && queryResult.data.length > 0) {
                                const project = queryResult.data[0];
                                const createTime = project.createTime;
                                // 再获取项目详情
                                const detailResult = await window.AppConfig.get('project', 'detail', { createTime });
                                if (detailResult.code === 200 && detailResult.data) {
                                    const projectDetail = detailResult.data;
                                    // 缓存项目信息（按用户隔离）
                                    if (window.localStorage) {
                                        const username = window.AppConfig.getUsername();
                                        if (username) {
                                            window.localStorage.setItem('currentProject_' + username, JSON.stringify({
                                                name: projectDetail.name,
                                                createTime: projectDetail.createTime
                                            }));
                                        }
                                    }
                                    // 调用displayProjectTree显示项目树
                                    if (window.displayProjectTree) {
                                        window.displayProjectTree(projectDetail.name);
                                    }
                                }
                            }
                        } catch (error) {
                            console.error('打开项目失败:', error);
                        }
                    }
                    // Refresh project list if visible
                    const projectList = document.querySelector('project-list');
                    if (projectList && projectList.style.display !== 'none') {
                        projectList.loadProjectsFromAPI();
                    }
                }, 1500);
            } else {
                if (progress) progress.style.display = 'none';
                if (window.CommonUtils && window.CommonUtils.showToast) {
                    window.CommonUtils.showToast(result.message || '导入失败', 'error');
                } else {
                    this.showToast(result.message || '导入失败', 'error');
                }
                if (importBtn) importBtn.disabled = false;
            }
        } catch (error) {
            console.error('导入项目失败:', error);
            if (progress) progress.style.display = 'none';
            if (window.CommonUtils && window.CommonUtils.showToast) {
                window.CommonUtils.showToast('网络错误，导入失败', 'error');
            } else {
                this.showToast('网络错误，导入失败', 'error');
            }
            if (importBtn) importBtn.disabled = false;
        }
    }

    showToast(message, type = 'success') {
        if (window.CommonUtils && window.CommonUtils.showToast) {
            window.CommonUtils.showToast(message, type);
        } else {
            // 降级处理
            console.log(`[${type.toUpperCase()}] ${message}`);
        }
    }
}

customElements.define('project-import', ProjectImport);
