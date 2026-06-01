class ProjectImport extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });
        this._selectedFile = null;
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
                <span class="import-label">目标项目名称</span>
                <input type="text" class="import-input" id="targetProjectName" placeholder="留空则使用导出时的项目名" />
            </div>
            <div class="import-field">
                <span class="import-label">选择导出文件</span>
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

    show() {
        this.style.display = 'block';
        this.resetForm();
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
        const projectName = root.getElementById('targetProjectName');
        if (projectName) projectName.value = '';
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
        const projectName = root.getElementById('targetProjectName')?.value?.trim() || '';

        const formData = new FormData();
        formData.append('file', this._selectedFile);
        if (projectName) {
            formData.append('projectName', projectName);
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

            const response = await fetch('/api/project/import', {
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
                const summary = [
                    data.targetProjectName ? '项目: ' + data.targetProjectName : '',
                    data.algorithmCount ? '算法: ' + data.algorithmCount + ' 个' : '',
                    data.modelCount ? '模型: ' + data.modelCount + ' 个' : '',
                    data.dataCount ? '数据: ' + data.dataCount + ' 个' : '',
                    data.simulationCount ? '仿真: ' + data.simulationCount + ' 个' : ''
                ].filter(s => s).join('，');
                this.showToast('导入成功！' + (summary ? ' ' + summary : ''));
                setTimeout(() => this.hide(), 1500);
            } else {
                if (progress) progress.style.display = 'none';
                this.showToast(result.message || '导入失败', 'error');
                if (importBtn) importBtn.disabled = false;
            }
        } catch (error) {
            console.error('导入项目失败:', error);
            if (progress) progress.style.display = 'none';
            this.showToast('网络错误，导入失败', 'error');
            if (importBtn) importBtn.disabled = false;
        }
    }

    showToast(message, type = 'success') {
        const toast = document.createElement('div');
        toast.className = `toast toast-${type}`;
        toast.textContent = message;
        toast.style.cssText = `
            position: fixed;
            top: 20px;
            right: 20px;
            padding: 12px 24px;
            background: ${type === 'success' ? '#67c23a' : '#f56c6c'};
            color: white;
            border-radius: 4px;
            z-index: 10000;
            animation: slideIn 0.3s ease;
        `;
        document.body.appendChild(toast);
        setTimeout(() => toast.remove(), 3000);
    }
}

customElements.define('project-import', ProjectImport);
