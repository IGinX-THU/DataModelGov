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
                    <h3 class="upload-title">新建仿真程序</h3>
                    <button class="close-btn" id="closeBtn">&times;</button>
                </div>
                <div class="wizard-steps">
                    <div class="wizard-step active" id="step1Indicator"><span class="step-number">1</span><span class="step-label">选择来源</span></div>
                    <div class="wizard-step-line"></div>
                    <div class="wizard-step" id="step2Indicator"><span class="step-number">2</span><span class="step-label">填写信息</span></div>
                </div>
                <div class="wizard-content" id="step1Content">
                    <div class="source-choice">
                        <label class="source-option"><input type="radio" name="sourceType" value="preset" checked><div class="source-card"><div class="source-icon">📦</div><div class="source-text"><div class="source-title">从已接入程序创建</div><div class="source-desc">选择 resources/programs/ 里的预置程序，自动关联源码包、配置和脚本</div></div></div></label>
                        <label class="source-option"><input type="radio" name="sourceType" value="manual"><div class="source-card"><div class="source-icon">📤</div><div class="source-text"><div class="source-title">手动上传</div><div class="source-desc">上传自己的压缩包，自行填写程序信息</div></div></div></label>
                    </div>
                    <div class="form-actions"><button type="button" class="btn btn-secondary" id="cancelBtn">取消</button><button type="button" class="btn btn-primary" id="step1NextBtn">下一步</button></div>
                </div>
                <div class="wizard-content" id="step2Content" style="display:none;">
                    <form id="uploadForm">
                        <div id="presetForm" style="display:none;">
                            <div class="form-group"><label class="form-label required">选择程序</label><select class="form-control" id="presetProgramSelect"><option value="">请选择...</option></select><div class="error-message" id="presetSelectError">请选择程序</div></div>
                        </div>
                        <div id="manualForm" style="display:none;">
                            <div class="form-group"><label class="form-label required">程序压缩包</label><div class="file-upload-area" id="fileUploadArea"><div class="upload-content"><div class="upload-icon">📁</div><p class="upload-text">点击选择文件或拖拽文件到此处</p><p class="upload-hint">支持 .zip, .rar, .7z, .tar, .tar.gz, .tgz 格式</p><input type="file" class="file-input" id="uploadFile" accept=".zip,.rar,.7z,.tar,.tar.gz,.tgz"></div></div><div class="file-info" id="fileInfo" style="display: none;"><div class="file-details"><span class="file-name" id="fileName"></span><span class="file-size" id="fileSize"></span></div><button type="button" class="remove-file-btn" id="removeFileBtn">&times;</button></div><div class="error-message" id="uploadFileError">请选择程序压缩包</div></div>
                        </div>
                        <div class="form-group"><label class="form-label required">程序名称</label><input type="text" class="form-control" id="uploadName" placeholder="请输入程序名称"><div class="error-message" id="uploadNameError">请输入程序名称</div></div>
                        <div class="form-group"><label class="form-label required">版本号</label><input type="text" class="form-control" id="uploadVersion" placeholder="请输入版本号" value="1.0"><div class="error-message" id="uploadVersionError">请输入版本号</div></div>
                        <div class="form-group"><label class="form-label">描述</label><textarea class="form-control" id="uploadDescription" rows="3" placeholder="请输入描述"></textarea></div>
                        <div class="form-actions"><button type="button" class="btn btn-secondary" id="step2PrevBtn">上一步</button><button type="button" class="btn btn-primary" id="uploadBtn">确认上传</button></div>
                    </form>
                </div>
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
        this.goToStep(1);
        this.loadPresetPrograms();
    }

    /** 加载预置程序列表 */
    async loadPresetPrograms() {
        try {
            const result = await window.AppConfig.get('program', 'preset-programs');
            const programs = (result && (result.success || result.code === 200) && Array.isArray(result.data)) ? result.data : [];
            const select = this.getElement('presetProgramSelect');
            if (select) {
                select.innerHTML = '<option value="">请选择...</option>' +
                    programs.map(p => `<option value="${p.id}">${p.name || p.id}</option>`).join('');
            }
        } catch (e) {
            console.warn('加载预置程序列表失败:', e);
        }
    }

    /** 跳转到指定步骤 */
    goToStep(step) {
        const step1Content = this.getElement('step1Content');
        const step2Content = this.getElement('step2Content');
        const step1Indicator = this.getElement('step1Indicator');
        const step2Indicator = this.getElement('step2Indicator');
        if (step === 1) {
            if (step1Content) step1Content.style.display = '';
            if (step2Content) step2Content.style.display = 'none';
            if (step1Indicator) step1Indicator.classList.add('active');
            if (step2Indicator) step2Indicator.classList.remove('active');
        } else {
            if (step1Content) step1Content.style.display = 'none';
            if (step2Content) step2Content.style.display = '';
            if (step1Indicator) step1Indicator.classList.remove('active');
            if (step2Indicator) step2Indicator.classList.add('active');
            // 根据来源类型显示对应表单
            const sourceType = this.getSelectedSourceType();
            const presetForm = this.getElement('presetForm');
            const manualForm = this.getElement('manualForm');
            if (sourceType === 'preset') {
                if (presetForm) presetForm.style.display = '';
                if (manualForm) manualForm.style.display = 'none';
            } else {
                if (presetForm) presetForm.style.display = 'none';
                if (manualForm) manualForm.style.display = '';
            }
        }
    }

    getSelectedSourceType() {
        const modal = this.getModal();
        let radios;
        if (modal) {
            radios = modal.querySelectorAll('input[name="sourceType"]');
            if (radios && radios.length > 0) {
                for (const r of radios) {
                    if (r.checked) return r.value;
                }
            }
        }
        radios = this.shadowRoot.querySelectorAll('input[name="sourceType"]');
        for (const r of radios) {
            if (r.checked) return r.value;
        }
        return 'preset';
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

            const step1NextBtn = modalElement.querySelector('#step1NextBtn');
            if (step1NextBtn) step1NextBtn.addEventListener('click', () => this.goToStep(2));

            const step2PrevBtn = modalElement.querySelector('#step2PrevBtn');
            if (step2PrevBtn) step2PrevBtn.addEventListener('click', () => this.goToStep(1));

            const uploadBtn = modalElement.querySelector('#uploadBtn');
            if (uploadBtn) uploadBtn.addEventListener('click', () => this.handleUpload());

            // 预置程序选择变化时自动填充程序名
            const presetSelect = modalElement.querySelector('#presetProgramSelect');
            if (presetSelect) presetSelect.addEventListener('change', () => {
                const nameInput = this.getElement('uploadName');
                const descInput = this.getElement('uploadDescription');
                if (nameInput && presetSelect.value) nameInput.value = presetSelect.value;
                if (descInput && presetSelect.value) descInput.value = '预置程序: ' + presetSelect.value;
                this.clearFieldError('presetSelectError');
            });

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
        const sourceType = this.getSelectedSourceType();
        const nameInput = this.getElement('uploadName');
        const versionInput = this.getElement('uploadVersion');
        const descriptionInput = this.getElement('uploadDescription');
        const name = nameInput ? nameInput.value.trim() : '';
        const version = versionInput ? versionInput.value.trim() : '';

        let hasError = false;
        if (!name) {
            this.showFieldError('uploadName', '请输入程序名称');
            hasError = true;
        }
        if (!version) {
            this.showFieldError('uploadVersion', '请输入版本号');
            hasError = true;
        }

        if (sourceType === 'preset') {
            // 预置程序模式：验证选择了程序，调用后端接口
            const presetSelect = this.getElement('presetProgramSelect');
            if (!presetSelect || !presetSelect.value) {
                this.showFieldError('presetSelect', '请选择程序');
                hasError = true;
            }
            if (hasError) return;
            const programId = presetSelect.value;
            const uploadBtn = this.getElement('uploadBtn');
            this._setUploadBusy(uploadBtn, true, '创建中...');
            try {
                if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('正在创建预置程序...', 'info');
                const url = window.AppConfig.getApiUrl('program', 'preset-programs') + '/' + encodeURIComponent(programId) + '/upload?version=' + encodeURIComponent(version) + '&name=' + encodeURIComponent(name);
                const result = await window.AppConfig.request(url, { method: 'POST' });
                if (result && (result.success || result.code === 200)) {
                    if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('预置程序创建成功: ' + programId, 'success');
                    this.dispatchEvent(new CustomEvent('upload-success', { bubbles: true, composed: true }));
                    this.hide();
                    if (window.ProgramLauncher) {
                        try {
                            const username = window.AppConfig.getUsername ? window.AppConfig.getUsername() : localStorage.getItem('username');
                            let currentProject = null;
                            try {
                                const cached = username ? JSON.parse(localStorage.getItem('currentProject_' + username) || 'null') : null;
                                currentProject = cached && cached.name ? cached.name : null;
                            } catch (e) {}
                            await window.ProgramLauncher.open({ name: name, version, projectName: currentProject });
                        } catch (openError) {
                            console.error('打开预置程序失败:', openError);
                            if (window.CommonUtils && window.CommonUtils.showToast) {
                                window.CommonUtils.showToast('程序已创建，但打开失败: ' + openError.message, 'warning');
                            }
                        }
                    }
                } else {
                    throw new Error(result.message || '创建失败');
                }
            } catch (e) {
                console.error('创建预置程序失败:', e);
                if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('创建失败: ' + e.message, 'error');
            } finally {
                this._setUploadBusy(uploadBtn, false, '确认上传');
            }
        } else {
            // 手动上传模式：验证选择了文件，走原有上传逻辑
            const file = this.selectedFile;
            if (!file) {
                this.showFieldError('uploadFile', '请选择程序压缩包');
                hasError = true;
            }
            if (hasError) return;
            const uploadBtn = this.getElement('uploadBtn');
            this._setUploadBusy(uploadBtn, true, '上传中...');
            const formData = new FormData();
            formData.append('file', file);
            formData.append('name', name);
            formData.append('version', version);
            formData.append('description', descriptionInput ? descriptionInput.value.trim() : '');
            try {
                const result = await window.AppConfig.upload('program', 'upload', formData);
                if (result && (result.code === 200 || result.success)) {
                    if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('创建成功', 'success');
                    this.dispatchEvent(new CustomEvent('upload-success', { bubbles: true, composed: true }));
                    this.hide();
                } else {
                    throw new Error(result.message || '创建失败');
                }
            } catch (e) {
                console.error('创建失败:', e);
                if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast('创建失败: ' + e.message, 'error');
            } finally {
                this._setUploadBusy(uploadBtn, false, '确认上传');
            }
        }
    }

    _setUploadBusy(button, busy, label) {
        if (!button) return;
        button.disabled = busy;
        if (label) button.textContent = label;
    }
}

customElements.define('program-upload', ProgramUpload);
