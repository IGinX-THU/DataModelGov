class ProgramUpload extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });
        this.selectedFile = null;
    }

    async connectedCallback() {
        await this.loadResources();
        this.render();
    }

    async loadResources() {
        try {
            const cssLink = document.createElement('link');
            cssLink.rel = 'stylesheet';
            cssLink.href = './components/program-upload/program-upload.css';
            this.shadowRoot.appendChild(cssLink);
        } catch (error) {
            console.error('Failed to load CSS:', error);
        }

        try {
            const response = await fetch('./components/program-upload/program-upload.html');
            if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
            this.htmlTemplate = await response.text();
        } catch (error) {
            console.error('Failed to load HTML template:', error);
            this.htmlTemplate = this.getInlineHTML();
        }
    }

    getInlineHTML() {
        return `
            <div class="upload-container">
                <div class="upload-header">
                    <h3 class="upload-title">上传仿真程序</h3>
                    <button class="close-btn" id="closeBtn">&times;</button>
                </div>
                <form id="uploadForm">
                    <div class="form-group">
                        <label class="form-label required">程序压缩包</label>
                        <div class="file-upload-area" id="fileUploadArea">
                            <div class="upload-content">
                                <div class="upload-icon">📁</div>
                                <p class="upload-text">点击选择文件或拖拽文件到此处</p>
                                <p class="upload-hint">支持 .zip, .rar, .7z, .tar, .tar.gz, .tgz 格式</p>
                                <input type="file" class="file-input" id="uploadFile" accept=".zip,.rar,.7z,.tar,.tar.gz,.tgz">
                            </div>
                        </div>
                        <div class="file-info" id="fileInfo" style="display: none;">
                            <div class="file-details">
                                <span class="file-name" id="fileName"></span>
                                <span class="file-size" id="fileSize"></span>
                            </div>
                            <button type="button" class="remove-file-btn" id="removeFileBtn">&times;</button>
                        </div>
                        <div class="error-message" id="uploadFileError">请选择程序压缩包</div>
                    </div>
                    <div class="form-group">
                        <label class="form-label required">程序名称</label>
                        <input type="text" class="form-control" id="uploadName" placeholder="请输入程序名称">
                        <div class="error-message" id="uploadNameError">请输入程序名称</div>
                    </div>
                    <div class="form-group">
                        <label class="form-label required">版本号</label>
                        <input type="text" class="form-control" id="uploadVersion" placeholder="请输入版本号">
                        <div class="error-message" id="uploadVersionError">请输入版本号</div>
                    </div>
                    <div class="form-group">
                        <label class="form-label">描述</label>
                        <textarea class="form-control" id="uploadDescription" rows="3" placeholder="请输入描述"></textarea>
                    </div>
                    <div class="form-actions">
                        <button type="button" class="btn btn-secondary" id="cancelBtn">取消</button>
                        <button type="button" class="btn btn-primary" id="uploadBtn">确认上传</button>
                    </div>
                </form>
            </div>
        `;
    }

    render() {
        const existingCSS = this.shadowRoot.querySelector('link');
        this.shadowRoot.innerHTML = '';
        if (existingCSS) this.shadowRoot.appendChild(existingCSS);
        if (this.htmlTemplate) {
            this.shadowRoot.innerHTML += this.htmlTemplate;
        } else {
            console.error('没有可用的HTML模板');
        }
    }

    getModal() {
        return document.querySelector('.modal-overlay');
    }

    getElement(id) {
        const modal = this.getModal();
        if (modal) {
            const el = modal.querySelector('#' + id);
            if (el) return el;
        }
        return this.shadowRoot.getElementById(id);
    }

    async show() {
        if (!this.shadowRoot.innerHTML) this.render();
        const modal = await window.modalManager.show(this, { maxWidth: '600px' });
        this.bindModalEvents(modal);
        this.resetForm();
        this.clearValidationErrors();
    }

    hide() {
        if (window.modalManager) window.modalManager.hide();
        this.clearValidationErrors();
    }

    bindModalEvents(modal) {
        setTimeout(() => {
            const modalElement = modal.modal;

            const closeBtn = modalElement.querySelector('#closeBtn');
            if (closeBtn) closeBtn.addEventListener('click', () => this.hide());

            const cancelBtn = modalElement.querySelector('#cancelBtn');
            if (cancelBtn) cancelBtn.addEventListener('click', () => this.hide());

            const uploadBtn = modalElement.querySelector('#uploadBtn');
            if (uploadBtn) uploadBtn.addEventListener('click', () => this.handleUpload());

            this.bindFileEvents(modalElement);

            ['uploadName', 'uploadVersion'].forEach(id => {
                const el = modalElement.querySelector('#' + id);
                if (el) el.addEventListener('input', () => this.clearFieldError(id));
            });

            const uploadFile = modalElement.querySelector('#uploadFile');
            if (uploadFile) uploadFile.addEventListener('change', () => this.clearFieldError('uploadFile'));
        }, 100);
    }

    bindFileEvents(modalElement) {
        const fileUploadArea = modalElement.querySelector('#fileUploadArea');
        const fileInput = modalElement.querySelector('#uploadFile');

        if (fileInput) {
            fileInput.addEventListener('change', (e) => {
                const file = e.target.files[0];
                if (file) this.handleFileSelect(file);
            });
        }

        if (fileUploadArea) {
            fileUploadArea.addEventListener('click', () => {
                if (fileInput) fileInput.click();
            });

            fileUploadArea.addEventListener('dragover', (e) => {
                e.preventDefault();
                e.stopPropagation();
                fileUploadArea.classList.add('dragover');
            });

            fileUploadArea.addEventListener('dragleave', () => {
                fileUploadArea.classList.remove('dragover');
            });

            fileUploadArea.addEventListener('drop', (e) => {
                e.preventDefault();
                e.stopPropagation();
                fileUploadArea.classList.remove('dragover');
                if (e.dataTransfer.files.length > 0) {
                    this.handleFileSelect(e.dataTransfer.files[0]);
                }
            });
        }

        const removeFileBtn = modalElement.querySelector('#removeFileBtn');
        if (removeFileBtn) {
            removeFileBtn.addEventListener('click', (e) => {
                e.preventDefault();
                e.stopPropagation();
                this.removeFile();
            });
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
        this.displayFileInfo(file);
        this.clearFieldError('uploadFile');
    }

    displayFileInfo(file) {
        // 优先从弹窗中获取元素（用于 modal manager）
        let fileUploadArea = null;
        let fileInfo = null;
        let fileName = null;
        let fileSize = null;

        const modal = document.querySelector('.modal-overlay');
        if (modal) {
            const modalContainer = modal.querySelector('.modal-container');
            if (modalContainer) {
                fileUploadArea = modalContainer.querySelector('#fileUploadArea');
                fileInfo = modalContainer.querySelector('#fileInfo');
                fileName = modalContainer.querySelector('#fileName');
                fileSize = modalContainer.querySelector('#fileSize');
            }
        }

        // 如果弹窗中没有找到，再尝试 Shadow DOM
        if (!fileUploadArea || !fileInfo || !fileName || !fileSize) {
            fileUploadArea = this.shadowRoot.getElementById('fileUploadArea');
            fileInfo = this.shadowRoot.getElementById('fileInfo');
            fileName = this.shadowRoot.getElementById('fileName');
            fileSize = this.shadowRoot.getElementById('fileSize');
        }

        if (fileUploadArea) fileUploadArea.style.display = 'none';
        if (fileInfo) fileInfo.style.display = 'flex';
        if (fileName) fileName.textContent = file.name;
        if (fileSize) fileSize.textContent = this.formatFileSize(file.size);
    }

    removeFile() {
        this.selectedFile = null;

        let fileUploadArea = null;
        let fileInfo = null;
        let fileInput = null;

        const modal = document.querySelector('.modal-overlay');
        if (modal) {
            const modalContainer = modal.querySelector('.modal-container');
            if (modalContainer) {
                fileUploadArea = modalContainer.querySelector('#fileUploadArea');
                fileInfo = modalContainer.querySelector('#fileInfo');
                fileInput = modalContainer.querySelector('#uploadFile');
            }
        }

        if (!fileUploadArea || !fileInfo || !fileInput) {
            fileUploadArea = this.shadowRoot.getElementById('fileUploadArea');
            fileInfo = this.shadowRoot.getElementById('fileInfo');
            fileInput = this.shadowRoot.getElementById('uploadFile');
        }

        if (fileUploadArea) fileUploadArea.style.display = 'block';
        if (fileInfo) fileInfo.style.display = 'none';
        if (fileInput) fileInput.value = '';
    }

    resetForm() {
        const nameInput = this.getElement('uploadName');
        const versionInput = this.getElement('uploadVersion');
        const descriptionInput = this.getElement('uploadDescription');
        if (nameInput) nameInput.value = '';
        if (versionInput) versionInput.value = '';
        if (descriptionInput) descriptionInput.value = '';
        this.removeFile();
    }

    clearValidationErrors() {
        ['uploadFile', 'uploadName', 'uploadVersion'].forEach(id => this.clearFieldError(id));
    }

    clearFieldError(fieldId) {
        const input = this.getElement(fieldId);
        const errorEl = this.getElement(fieldId + 'Error');
        if (input) input.classList.remove('error');
        if (errorEl) errorEl.classList.remove('show');
    }

    showFieldError(fieldId, message) {
        const input = this.getElement(fieldId);
        const errorEl = this.getElement(fieldId + 'Error');
        if (input) input.classList.add('error');
        if (errorEl) {
            errorEl.classList.add('show');
            if (message) errorEl.textContent = message;
        }
    }

    formatFileSize(bytes) {
        if (bytes === 0) return '0 Bytes';
        const k = 1024;
        const sizes = ['Bytes', 'KB', 'MB', 'GB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
    }

    async handleUpload() {
        this.clearValidationErrors();
        const nameInput = this.getElement('uploadName');
        const versionInput = this.getElement('uploadVersion');
        const descriptionInput = this.getElement('uploadDescription');
        const file = this.selectedFile;
        const name = nameInput ? nameInput.value.trim() : '';
        const version = versionInput ? versionInput.value.trim() : '';

        let hasError = false;
        if (!file) {
            this.showFieldError('uploadFile', '请选择程序压缩包');
            hasError = true;
        }
        if (!name) {
            this.showFieldError('uploadName', '请输入程序名称');
            hasError = true;
        }
        if (!version) {
            this.showFieldError('uploadVersion', '请输入版本号');
            hasError = true;
        }
        if (hasError) return;

        const formData = new FormData();
        formData.append('file', file);
        formData.append('name', name);
        formData.append('version', version);
        formData.append('description', descriptionInput ? descriptionInput.value.trim() : '');
        try {
            const result = await window.AppConfig.upload('program', 'upload', formData);
            if (result && (result.code === 200 || result.success)) {
                if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('上传成功', 'success');
                this.dispatchEvent(new CustomEvent('upload-success', { bubbles: true, composed: true }));
                this.hide();
            } else {
                throw new Error(result.message || '上传失败');
            }
        } catch (e) {
            console.error('上传失败:', e);
            if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('上传失败: ' + e.message, 'error');
        }
    }
}

customElements.define('program-upload', ProgramUpload);
