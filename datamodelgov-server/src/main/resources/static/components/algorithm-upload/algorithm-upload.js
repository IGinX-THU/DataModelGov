/**
 * 上传算法文件组件
 * 使用 Web Components (Custom Elements + Shadow DOM) 实现
 */
console.log('🔍 algorithm-upload.js 开始加载');

class AlgorithmUpload extends HTMLElement {
    constructor() {
        super();
        console.log('🔍 AlgorithmUpload constructor 被调用');
        this.attachShadow({ mode: 'open' });
        this.selectedFile = null;
    }

    async connectedCallback() {
        await this.loadResources();
        this.render();
        setTimeout(() => {
            this.bindEvents();
        }, 100);
    }

    async loadResources() {
        try {
            const cssLink = document.createElement('link');
            cssLink.rel = 'stylesheet';
            cssLink.href = './components/algorithm-upload/algorithm-upload.css';
            this.shadowRoot.appendChild(cssLink);
        } catch (error) {
            console.error('Failed to load CSS:', error);
        }

        if (window.location.protocol === 'file:') {
            this.htmlTemplate = this.getInlineHTML();
            return;
        }

        try {
            const response = await fetch('./components/algorithm-upload/algorithm-upload.html');
            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }
            const htmlContent = await response.text();
            this.htmlTemplate = htmlContent;
        } catch (error) {
            console.error('Failed to load HTML template:', error);
            this.htmlTemplate = this.getInlineHTML();
        }
    }

    getInlineHTML() {
        return `
            <div class="upload-container">
                <div class="upload-header">
                    <h3 class="upload-title">上传算法文件</h3>
                    <button class="close-btn" id="closeBtn">&times;</button>
                </div>
                
                <form id="uploadForm">
                    <div class="form-group">
                        <label class="form-label required">算法文件</label>
                        <div class="file-upload-area" id="fileUploadArea">
                            <div class="upload-content">
                                <div class="upload-icon">📁</div>
                                <p class="upload-text">点击选择文件或拖拽文件到此处</p>
                                <p class="upload-hint">支持 .py, .java, .sh, .jar 格式</p>
                                <input type="file" class="file-input" id="algorithmFile" accept=".py,.java,.sh,.jar" required>
                            </div>
                        </div>
                        <div class="file-info" id="fileInfo" style="display: none;">
                            <div class="file-details">
                                <span class="file-name" id="fileName"></span>
                                <span class="file-size" id="fileSize"></span>
                            </div>
                            <button type="button" class="remove-file-btn" id="removeFileBtn">&times;</button>
                        </div>
                    </div>

                    <div class="form-group">
                        <label class="form-label required">算法名称</label>
                        <input type="text" class="form-control" id="algorithmName" placeholder="请输入算法名称" required>
                    </div>

                    <div class="form-group">
                        <label class="form-label required">版本号</label>
                        <input type="text" class="form-control" id="algorithmVersion" placeholder="请输入版本号" required>
                    </div>

                    <div class="form-group">
                        <label class="form-label required">算法类型</label>
                        <select class="form-control" id="algorithmType" required>
                            <option value="">请选择算法类型</option>
                            <option value="python">Python脚本</option>
                            <option value="java">Java程序</option>
                            <option value="shell">Shell脚本</option>
                        </select>
                    </div>

                    <div class="form-group">
                        <label class="form-label">开发者</label>
                        <input type="text" class="form-control" id="author" placeholder="请输入开发者名称">
                    </div>

                    <div class="form-group">
                        <label class="form-label">场景描述</label>
                        <textarea class="form-control" id="scene" rows="3" placeholder="请输入算法应用场景描述"></textarea>
                    </div>

                    <div class="form-group">
                        <label class="form-label">运行命令</label>
                        <input type="text" class="form-control" id="cmd" placeholder="例如: python algorithm.py">
                    </div>

                    <div class="form-group">
                        <label class="form-label">输入文件名</label>
                        <input type="text" class="form-control" id="inputFile" placeholder="例如: input.txt">
                    </div>

                    <div class="form-group">
                        <label class="form-label">输出文件名</label>
                        <input type="text" class="form-control" id="outputFile" placeholder="例如: output.txt">
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
        if (this.htmlTemplate) {
            this.shadowRoot.innerHTML += this.htmlTemplate;
        }
    }

    bindEvents() {
        const closeBtn = this.shadowRoot.getElementById('closeBtn');
        const cancelBtn = this.shadowRoot.getElementById('cancelBtn');
        const uploadBtn = this.shadowRoot.getElementById('uploadBtn');
        const fileUploadArea = this.shadowRoot.getElementById('fileUploadArea');
        const removeFileBtn = this.shadowRoot.getElementById('removeFileBtn');
        const fileInput = this.shadowRoot.getElementById('algorithmFile');

        if (closeBtn) {
            closeBtn.addEventListener('click', () => this.hide());
        }

        if (cancelBtn) {
            cancelBtn.addEventListener('click', () => this.hide());
        }

        if (uploadBtn) {
            uploadBtn.addEventListener('click', () => this.handleUpload());
        }

        if (fileUploadArea) {
            fileUploadArea.addEventListener('click', () => fileInput.click());
            
            fileUploadArea.addEventListener('dragover', (e) => {
                e.preventDefault();
                fileUploadArea.classList.add('dragover');
            });

            fileUploadArea.addEventListener('dragleave', () => {
                fileUploadArea.classList.remove('dragover');
            });

            fileUploadArea.addEventListener('drop', (e) => {
                e.preventDefault();
                fileUploadArea.classList.remove('dragover');
                const files = e.dataTransfer.files;
                if (files.length > 0) {
                    this.handleFileSelect(files[0]);
                }
            });
        }

        if (fileInput) {
            fileInput.addEventListener('change', (e) => {
                if (e.target.files.length > 0) {
                    this.handleFileSelect(e.target.files[0]);
                }
            });
        }

        if (removeFileBtn) {
            removeFileBtn.addEventListener('click', () => this.removeFile());
        }
    }

    handleFileSelect(file) {
        this.selectedFile = file;
        const fileName = this.shadowRoot.getElementById('fileName');
        const fileSize = this.shadowRoot.getElementById('fileSize');
        const fileInfo = this.shadowRoot.getElementById('fileInfo');
        const fileUploadArea = this.shadowRoot.getElementById('fileUploadArea');

        if (fileName) fileName.textContent = file.name;
        if (fileSize) fileSize.textContent = this.formatFileSize(file.size);
        if (fileInfo) fileInfo.style.display = 'flex';
        if (fileUploadArea) fileUploadArea.style.display = 'none';

        // 自动填充算法名称
        const nameInput = this.shadowRoot.getElementById('algorithmName');
        if (nameInput && !nameInput.value) {
            nameInput.value = file.name.replace(/\.[^/.]+$/, '');
        }
    }

    removeFile() {
        this.selectedFile = null;
        const fileInput = this.shadowRoot.getElementById('algorithmFile');
        const fileInfo = this.shadowRoot.getElementById('fileInfo');
        const fileUploadArea = this.shadowRoot.getElementById('fileUploadArea');

        if (fileInput) fileInput.value = '';
        if (fileInfo) fileInfo.style.display = 'none';
        if (fileUploadArea) fileUploadArea.style.display = 'block';
    }

    async handleUpload() {
        if (!this.validateForm()) {
            return;
        }

        const formData = new FormData();
        formData.append('file', this.selectedFile);
        formData.append('name', this.shadowRoot.getElementById('algorithmName').value.trim());
        formData.append('version', this.shadowRoot.getElementById('algorithmVersion').value.trim());
        formData.append('algorithmType', this.shadowRoot.getElementById('algorithmType').value);

        try {
            if (window.showGlobalLoading) {
                window.showGlobalLoading('正在上传算法文件...');
            }

            const result = await window.AppConfig.upload('algorithm', 'upload', formData);
            
            if (result.code === 200) {
                this.showToast('算法上传成功', 'success');
                this.hide();
                this.resetForm();
                
                // 触发自定义事件通知父组件刷新
                this.dispatchEvent(new CustomEvent('algorithm-uploaded', { 
                    bubbles: true, 
                    composed: true 
                }));
            } else {
                this.showToast(result.message || '上传失败', 'error');
            }
        } catch (error) {
            console.error('上传算法失败:', error);
            this.showToast('网络错误，上传失败', 'error');
        } finally {
            if (window.hideGlobalLoading) {
                window.hideGlobalLoading();
            }
        }
    }

    validateForm() {
        let isValid = true;

        // 验证文件
        if (!this.selectedFile) {
            this.showError('algorithmFile', '请选择算法文件');
            isValid = false;
        } else {
            this.hideError('algorithmFile');
        }

        // 验证名称
        const name = this.shadowRoot.getElementById('algorithmName').value.trim();
        if (!name) {
            this.showError('algorithmName', '请输入算法名称');
            isValid = false;
        } else {
            this.hideError('algorithmName');
        }

        // 验证版本号
        const version = this.shadowRoot.getElementById('algorithmVersion').value.trim();
        if (!version) {
            this.showError('algorithmVersion', '请输入版本号');
            isValid = false;
        } else {
            this.hideError('algorithmVersion');
        }

        // 验证算法类型
        const algorithmType = this.shadowRoot.getElementById('algorithmType').value;
        if (!algorithmType) {
            this.showError('algorithmType', '请选择算法类型');
            isValid = false;
        } else {
            this.hideError('algorithmType');
        }

        return isValid;
    }

    showError(fieldId, message) {
        const field = this.shadowRoot.getElementById(fieldId);
        if (field) {
            field.classList.add('error');
            const errorDiv = this.shadowRoot.getElementById(fieldId + 'Error');
            if (errorDiv) {
                errorDiv.textContent = message;
                errorDiv.classList.add('show');
            }
        }
    }

    hideError(fieldId) {
        const field = this.shadowRoot.getElementById(fieldId);
        if (field) {
            field.classList.remove('error');
            const errorDiv = this.shadowRoot.getElementById(fieldId + 'Error');
            if (errorDiv) {
                errorDiv.classList.remove('show');
            }
        }
    }

    resetForm() {
        const form = this.shadowRoot.getElementById('uploadForm');
        if (form) form.reset();
        this.removeFile();
    }

    formatFileSize(bytes) {
        if (bytes === 0) return '0 Bytes';
        const k = 1024;
        const sizes = ['Bytes', 'KB', 'MB', 'GB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return Math.round(bytes / Math.pow(k, i) * 100) / 100 + ' ' + sizes[i];
    }

    showToast(message, type = 'success') {
        if (window.CommonUtils && window.CommonUtils.showToast) {
            window.CommonUtils.showToast(message, type);
        } else {
            console.log(`[${type}] ${message}`);
        }
    }

    show() {
        this.style.display = 'block';
        this.setAttribute('show', '');
    }

    hide() {
        this.style.display = 'none';
        this.removeAttribute('show');
        this.resetForm();
    }
}

customElements.define('algorithm-upload', AlgorithmUpload);
