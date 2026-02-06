/**
 * 上传模型文件组件
 * 使用 Web Components (Custom Elements + Shadow DOM) 实现
 */
class ModelUpload extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });
        this.selectedFile = null;
    }

    async connectedCallback() {
        await this.loadResources();
        this.render();
        // 等待DOM渲染完成后再绑定事件
        setTimeout(() => {
            this.bindEvents();
        }, 100);
    }

    async loadResources() {
        // 加载CSS
        try {
            const cssLink = document.createElement('link');
            cssLink.rel = 'stylesheet';
            cssLink.href = './components/model-upload/model-upload.css';
            this.shadowRoot.appendChild(cssLink);
        } catch (error) {
            console.error('Failed to load CSS:', error);
        }

        if (window.location.protocol === 'file:') {
            this.htmlTemplate = this.getInlineHTML();
            return;
        }

        // 加载HTML模板
        try {
            const response = await fetch('./components/model-upload/model-upload.html');
            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }
            const htmlContent = await response.text();
            this.htmlTemplate = htmlContent;
        } catch (error) {
            console.error('Failed to load HTML template:', error);
            // 如果外部文件加载失败，使用内联模板
            this.htmlTemplate = this.getInlineHTML();
        }
    }

    getInlineHTML() {
        return `
            <div class="upload-container">
                <div class="upload-header">
                    <h3 class="upload-title">上传模型文件</h3>
                    <button class="close-btn" id="closeBtn">&times;</button>
                </div>
                
                <form id="uploadForm">
                    <div class="form-group">
                        <label class="form-label required">模型文件</label>
                        <div class="file-upload-area" id="fileUploadArea">
                            <div class="upload-content">
                                <div class="upload-icon">📁</div>
                                <p class="upload-text">点击选择文件或拖拽文件到此处</p>
                                <p class="upload-hint">支持 .pkl, .joblib, .h5, .pt, .pth, .onnx, .pb 格式</p>
                                <input type="file" class="file-input" id="modelFile" accept=".pkl,.joblib,.h5,.pt,.pth,.onnx,.pb" required>
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
                        <label class="form-label required">是否关联已有模型</label>
                        <div class="radio-group-horizontal">
                            <div class="radio-item-horizontal">
                                <input type="radio" id="isRelatedModelYes" name="isRelatedModel" value="yes" required>
                                <label for="isRelatedModelYes">是</label>
                            </div>
                            <div class="radio-item-horizontal">
                                <input type="radio" id="isRelatedModelNo" name="isRelatedModel" value="no" checked required>
                                <label for="isRelatedModelNo">否</label>
                            </div>
                        </div>
                    </div>

                    <div class="form-group">
                        <label class="form-label required">名称</label>
                        <div id="modelNameInputContainer">
                            <input type="text" class="form-control" id="modelName" placeholder="请输入模型名称" required>
                        </div>
                        <div id="modelNameSelectContainer" style="display: none;">
                            <select class="form-control form-select" id="modelNameSelect" required>
                                <option value="">请选择模型名称</option>
                            </select>
                        </div>
                    </div>

                    <div class="form-group">
                        <label class="form-label required">版本号</label>
                        <input type="text" class="form-control" id="modelVersion" placeholder="请输入版本号" required>
                    </div>

                    <div class="form-actions">
                        <button type="button" class="btn btn-secondary" id="cancelBtn">
                            取消
                        </button>
                        <button type="button" class="btn btn-primary" id="uploadBtn">
                            确认上传
                        </button>
                    </div>
                </form>
            </div>
        `;
    }

    render() {
        if (this.htmlTemplate) {
            // 保留已加载的CSS，只添加HTML
            const existingCSS = this.shadowRoot.querySelector('link');
            this.shadowRoot.innerHTML = '';
            if (existingCSS) {
                this.shadowRoot.appendChild(existingCSS);
            }
            this.shadowRoot.innerHTML += this.htmlTemplate;
        } else {
            console.error('没有可用的HTML模板');
        }
    }

    bindEvents() {
        // 关闭按钮
        const closeBtn = this.shadowRoot.getElementById('closeBtn');
        if (closeBtn) {
            closeBtn.addEventListener('click', () => {
                if (this._closeDialog) {
                    this._closeDialog();
                } else {
                    this.hide();
                }
            });
        }

        // 取消按钮
        const cancelBtn = this.shadowRoot.getElementById('cancelBtn');
        if (cancelBtn) {
            cancelBtn.addEventListener('click', () => {
                if (this._closeDialog) {
                    this._closeDialog();
                } else {
                    this.hide();
                }
            });
        }

        // 上传按钮
        const uploadBtn = this.shadowRoot.getElementById('uploadBtn');
        if (uploadBtn) {
            uploadBtn.addEventListener('click', (e) => {
                e.preventDefault();
                this.upload();
            });
        }

        // 文件选择
        const fileInput = this.shadowRoot.getElementById('modelFile');
        const fileUploadArea = this.shadowRoot.getElementById('fileUploadArea');
        
        if (fileInput) {
            fileInput.addEventListener('change', (e) => {
                this.handleFileSelect(e.target.files[0]);
            });
        }

        // 拖拽上传
        if (fileUploadArea) {
            fileUploadArea.addEventListener('dragover', (e) => {
                e.preventDefault();
                fileUploadArea.classList.add('dragover');
            });

            fileUploadArea.addEventListener('dragleave', (e) => {
                e.preventDefault();
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

        // 移除文件按钮
        const removeFileBtn = this.shadowRoot.getElementById('removeFileBtn');
        if (removeFileBtn) {
            removeFileBtn.addEventListener('click', () => {
                this.removeFile();
            });
        }

        // 是否关联已有模型变化事件
        const isRelatedModelYes = this.shadowRoot.getElementById('isRelatedModelYes');
        const isRelatedModelNo = this.shadowRoot.getElementById('isRelatedModelNo');
        
        if (isRelatedModelYes) {
            isRelatedModelYes.addEventListener('change', () => {
                this.handleRelatedModelChange();
            });
        }
        
        if (isRelatedModelNo) {
            isRelatedModelNo.addEventListener('change', () => {
                this.handleRelatedModelChange();
            });
        }

        // ESC键关闭
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape' && this.hasAttribute('show')) {
                this.hide();
            }
        });
    }

    handleRelatedModelChange() {
        const isRelatedModelYes = this.shadowRoot.getElementById('isRelatedModelYes');
        const isRelatedModelNo = this.shadowRoot.getElementById('isRelatedModelNo');
        
        if (!isRelatedModelYes || !isRelatedModelNo) {
            console.warn('handleRelatedModelChange: 单选框元素未找到');
            return;
        }
        
        const selectedValue = isRelatedModelYes.checked ? 'yes' : (isRelatedModelNo.checked ? 'no' : '');
        console.log('handleRelatedModelChange: 选择值', selectedValue);
        
        if (selectedValue === 'yes') {
            console.log('选择了关联已有模型，切换到下拉选择框');
            this.showModelSelect();
        } else {
            console.log('选择了不关联已有模型，切换到输入框');
            this.showModelInput();
        }
    }

    showModelSelect() {
        const inputContainer = this.shadowRoot.getElementById('modelNameInputContainer');
        const selectContainer = this.shadowRoot.getElementById('modelNameSelectContainer');
        const modelNameSelect = this.shadowRoot.getElementById('modelNameSelect');
        
        if (inputContainer) inputContainer.style.display = 'none';
        if (selectContainer) {
            selectContainer.style.display = 'block';
            this.loadModelNames();
        }
    }

    showModelInput() {
        const inputContainer = this.shadowRoot.getElementById('modelNameInputContainer');
        const selectContainer = this.shadowRoot.getElementById('modelNameSelectContainer');
        
        if (inputContainer) inputContainer.style.display = 'block';
        if (selectContainer) selectContainer.style.display = 'none';
    }

    loadModelNames() {
        const modelNameSelect = this.shadowRoot.getElementById('modelNameSelect');
        if (!modelNameSelect) return;
        
        // 获取右侧模型资产库的根节点
        const rightSidebarTree = document.querySelector('.right-sidebar .tree');
        if (!rightSidebarTree) {
            console.warn('未找到右侧模型资产库');
            return;
        }
        
        const rootNodes = rightSidebarTree.querySelectorAll('.tree-node');
        const modelNames = [];
        
        rootNodes.forEach(node => {
            const span = node.querySelector('span');
            if (span) {
                modelNames.push(span.textContent.trim());
            }
        });
        
        // 清空现有选项
        modelNameSelect.innerHTML = '<option value="">请选择模型名称</option>';
        
        // 添加模型名称选项
        modelNames.forEach(name => {
            const option = document.createElement('option');
            option.value = name;
            option.textContent = name;
            modelNameSelect.appendChild(option);
        });
    }

    handleFileSelect(file) {
        if (!file) return;

        // 验证文件类型
        const allowedTypes = ['.pkl', '.joblib', '.h5', '.pt', '.pth', '.onnx', '.pb'];
        const fileExtension = '.' + file.name.split('.').pop().toLowerCase();
        
        if (!allowedTypes.includes(fileExtension)) {
            this.showMessage('不支持的文件格式，请选择支持的模型文件格式', 'error');
            return;
        }

        // 验证文件大小（限制为100MB）
        const maxSize = 100 * 1024 * 1024; // 100MB
        if (file.size > maxSize) {
            this.showMessage('文件大小不能超过100MB', 'error');
            return;
        }

        this.selectedFile = file;
        this.displayFileInfo(file);
    }

    displayFileInfo(file) {
        const fileUploadArea = this.shadowRoot.getElementById('fileUploadArea');
        const fileInfo = this.shadowRoot.getElementById('fileInfo');
        const fileName = this.shadowRoot.getElementById('fileName');
        const fileSize = this.shadowRoot.getElementById('fileSize');

        if (fileUploadArea) fileUploadArea.style.display = 'none';
        if (fileInfo) fileInfo.style.display = 'flex';
        if (fileName) fileName.textContent = file.name;
        if (fileSize) fileSize.textContent = this.formatFileSize(file.size);
    }

    removeFile() {
        this.selectedFile = null;
        const fileUploadArea = this.shadowRoot.getElementById('fileUploadArea');
        const fileInfo = this.shadowRoot.getElementById('fileInfo');
        const fileInput = this.shadowRoot.getElementById('modelFile');

        if (fileUploadArea) fileUploadArea.style.display = 'block';
        if (fileInfo) fileInfo.style.display = 'none';
        if (fileInput) fileInput.value = '';
    }

    formatFileSize(bytes) {
        if (bytes === 0) return '0 Bytes';
        const k = 1024;
        const sizes = ['Bytes', 'KB', 'MB', 'GB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
    }

    show() {
        console.log('🔍 model-upload show() 被调用');
        
        // 使用通用弹窗管理器
        const modal = window.modalManager.show(this, {
            maxWidth: '600px'
        });
        
        // 绑定组件内部事件
        this.bindModalEvents(modal);
        
        // 重置表单
        this.resetForm();
        this.clearValidationErrors();
        
        console.log('🔍 show() 方法执行完成');
    }

    hide() {
        console.log('🔍 model-upload hide() 被调用');
        window.modalManager.hide();
        // 隐藏时也清除验证错误
        this.clearValidationErrors();
    }

    bindModalEvents(modal) {
        // 等待DOM更新后绑定事件
        setTimeout(() => {
            const modalElement = modal.modal;
            
            // 绑定关闭按钮
            const closeBtn = modalElement.querySelector('#closeBtn');
            if (closeBtn) {
                closeBtn.addEventListener('click', () => {
                    this.hide();
                });
            }
            
            // 绑定取消按钮
            const cancelBtn = modalElement.querySelector('#cancelBtn');
            if (cancelBtn) {
                cancelBtn.addEventListener('click', () => {
                    this.hide();
                });
            }
            
            // 绑定上传按钮
            const uploadBtn = modalElement.querySelector('#uploadBtn');
            if (uploadBtn) {
                uploadBtn.addEventListener('click', () => {
                    this.handleUpload();
                });
            }
            
            // 绑定文件选择相关事件
            this.bindFileEvents(modalElement);
            
            // 绑定单选按钮事件
            this.bindRadioEvents(modalElement);
            
            console.log('🔍 事件绑定完成');
        }, 100);
    }

    handleUpload() {
        console.log('🔍 handleUpload 被调用');
        // 这里添加文件上传逻辑
        const fileInput = this.shadowRoot.getElementById('modelFile');
        const modelName = this.shadowRoot.getElementById('modelName');
        const modelNameSelect = this.shadowRoot.getElementById('modelNameSelect');
        const modelVersion = this.shadowRoot.getElementById('modelVersion');
        const isRelatedModelYes = this.shadowRoot.getElementById('isRelatedModelYes');
        
        const formData = {
            file: fileInput?.files[0] || null,
            modelName: modelName?.value || '',
            modelNameSelect: modelNameSelect?.value || '',
            modelVersion: modelVersion?.value || '',
            isRelatedModel: isRelatedModelYes?.checked || false
        };

        console.log('🔍 上传数据:', formData);
        
        // 这里可以添加文件上传API调用
        // 上传成功后关闭弹窗
        this.hide();
    }

    handleFileSelect(file) {
        console.log('🔍 handleFileSelect 被调用，文件:', file);
        const fileUploadArea = this.shadowRoot.getElementById('fileUploadArea');
        const fileName = this.shadowRoot.getElementById('fileName');
        const fileSize = this.shadowRoot.getElementById('fileSize');
        
        if (file) {
            fileName.textContent = file.name;
            fileSize.textContent = this.formatFileSize(file.size);
            fileUploadArea.classList.add('has-file');
        } else {
            fileName.textContent = '';
            fileSize.textContent = '';
            fileUploadArea.classList.remove('has-file');
        }
    }

    bindFileEvents(modalElement) {
        const fileUploadArea = modalElement.querySelector('#fileUploadArea');
        const fileInput = modalElement.querySelector('#modelFile');
        
        if (fileUploadArea && fileInput) {
            // 点击上传区域
            fileUploadArea.addEventListener('click', () => {
                fileInput.click();
            });
            
            // 文件选择
            fileInput.addEventListener('change', (e) => {
                this.handleFileSelect(e.target.files[0]);
            });
            
            // 拖拽事件
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
                const file = e.dataTransfer.files[0];
                if (file) {
                    this.handleFileSelect(file);
                }
            });
        }
    }

    bindRadioEvents(modalElement) {
        const yesRadio = modalElement.querySelector('#isRelatedModelYes');
        const noRadio = modalElement.querySelector('#isRelatedModelNo');
        const inputContainer = modalElement.querySelector('#modelNameInputContainer');
        const selectContainer = modalElement.querySelector('#modelNameSelectContainer');
        
        if (yesRadio && noRadio && inputContainer && selectContainer) {
            const handleRadioChange = () => {
                if (yesRadio.checked) {
                    inputContainer.style.display = 'none';
                    selectContainer.style.display = 'block';
                } else {
                    inputContainer.style.display = 'block';
                    selectContainer.style.display = 'none';
                }
            };
            
            yesRadio.addEventListener('change', handleRadioChange);
            noRadio.addEventListener('change', handleRadioChange);
        }
    }

    resetForm() {
        const modelName = this.shadowRoot.getElementById('modelName');
        const modelNameSelect = this.shadowRoot.getElementById('modelNameSelect');
        const modelVersion = this.shadowRoot.getElementById('modelVersion');
        const isRelatedModelYes = this.shadowRoot.getElementById('isRelatedModelYes');
        const isRelatedModelNo = this.shadowRoot.getElementById('isRelatedModelNo');

        // 重置是否关联已有模型单选框（默认选中"否"）
        if (isRelatedModelYes) isRelatedModelYes.checked = false;
        if (isRelatedModelNo) isRelatedModelNo.checked = true;
        
        // 显示输入框，隐藏下拉选择框
        this.showModelInput();
        
        // 重置名称字段
        if (modelName) modelName.value = '';
        if (modelNameSelect) modelNameSelect.value = '';
        
        // 重置版本号
        if (modelVersion) modelVersion.value = '';

        this.removeFile();
    }

    async upload() {
        // 清除之前的错误状态
        this.clearValidationErrors();
        
        const formData = this.getFormData();
        
        let hasError = false;
        
        // 验证是否关联已有模型
        const isRelatedModelYes = this.shadowRoot.getElementById('isRelatedModelYes');
        const isRelatedModelNo = this.shadowRoot.getElementById('isRelatedModelNo');
        
        if (!isRelatedModelYes?.checked && !isRelatedModelNo?.checked) {
            this.showFieldError('isRelatedModel', '请选择是否关联已有模型');
            hasError = true;
        }
        
        // 验证模型名称
        if (!formData.name) {
            if (formData.isRelatedModel === 'yes') {
                this.showFieldError('modelNameSelect', '请选择模型名称');
            } else {
                this.showFieldError('modelName', '请输入模型名称');
            }
            hasError = true;
        }
        
        // 验证版本号
        if (!formData.version) {
            this.showFieldError('modelVersion', '请输入版本号');
            hasError = true;
        }
        
        // 验证模型文件
        if (!this.selectedFile) {
            this.showFieldError('modelFile', '请选择模型文件');
            hasError = true;
        }
        
        if (hasError) {
            this.showMessage('请填写必填字段', 'error');
            return;
        }

        try {
            // 创建FormData对象用于文件上传
            const uploadFormData = new FormData();
            uploadFormData.append('file', this.selectedFile);
            uploadFormData.append('isRelatedModel', formData.isRelatedModel);
            uploadFormData.append('name', formData.name);
            uploadFormData.append('version', formData.version);

            // 模拟上传API调用
            const response = await this.apiCall(window.AppConfig.getApiUrl('model', 'upload'), 'POST', uploadFormData, true);
            
            if (response.code === 200) {
                this.showMessage('模型文件上传成功', 'success');
                
                // 延迟关闭窗口
                setTimeout(() => {
                    if (this._closeDialog) {
                        this._closeDialog();
                    } else {
                        this.hide();
                    }
                    
                    this.dispatchEvent(new CustomEvent('upload-success', {
                        detail: { formData, response },
                        bubbles: true,
                        composed: true
                    }));
                }, 1000);
            } else {
                const errorMessage = response.message || '上传失败';
                this.showMessage(errorMessage, 'error');
            }
        } catch (error) {
            console.error('上传模型文件失败:', error);
            this.showMessage('上传失败，请稍后重试', 'error');
        }
    }

    getFormData() {
        const modelName = this.shadowRoot.getElementById('modelName');
        const modelNameSelect = this.shadowRoot.getElementById('modelNameSelect');
        const modelVersion = this.shadowRoot.getElementById('modelVersion');
        const isRelatedModelYes = this.shadowRoot.getElementById('isRelatedModelYes');
        const isRelatedModelNo = this.shadowRoot.getElementById('isRelatedModelNo');
        
        const isRelatedModel = isRelatedModelYes && isRelatedModelYes.checked ? 'yes' : 
                              (isRelatedModelNo && isRelatedModelNo.checked ? 'no' : '');
        
        let nameValue = '';
        
        // 根据关联模型选择获取名称值
        if (isRelatedModel === 'yes') {
            // 从下拉选择框获取值
            nameValue = modelNameSelect ? modelNameSelect.value : '';
        } else {
            // 从输入框获取值
            nameValue = modelName ? modelName.value : '';
        }
        
        return {
            file: this.selectedFile,
            isRelatedModel: isRelatedModel,
            name: nameValue,
            version: modelVersion ? modelVersion.value : ''
        };
    }

    showFieldError(fieldId, message) {
        const field = this.shadowRoot.getElementById(fieldId);
        const errorElement = this.shadowRoot.getElementById(fieldId + 'Error');
        const formGroup = field?.closest('.form-group');
        
        if (field) {
            field.classList.add('error');
        }
        if (errorElement) {
            errorElement.textContent = message;
            errorElement.classList.add('show');
        }
        if (formGroup) {
            formGroup.classList.add('error');
        }
    }

    clearFieldError(fieldId) {
        const field = this.shadowRoot.getElementById(fieldId);
        const errorElement = this.shadowRoot.getElementById(fieldId + 'Error');
        const formGroup = field?.closest('.form-group');
        
        if (field) {
            field.classList.remove('error');
        }
        if (errorElement) {
            errorElement.classList.remove('show');
        }
        if (formGroup) {
            formGroup.classList.remove('error');
        }
    }

    clearValidationErrors() {
        // 清除所有错误状态
        const errorFields = this.shadowRoot.querySelectorAll('.form-control.error');
        const errorMessages = this.shadowRoot.querySelectorAll('.error-message.show');
        const errorGroups = this.shadowRoot.querySelectorAll('.form-group.error');
        
        errorFields.forEach(field => field.classList.remove('error'));
        errorMessages.forEach(msg => msg.classList.remove('show'));
        errorGroups.forEach(group => group.classList.remove('error'));
    }

    async apiCall(url, method = 'GET', data = null, isFormData = false) {
        const options = {
            method: method,
            headers: window.AppConfig.getAuthHeaders(),
        };

        // 如果是FormData，不要设置Content-Type，让浏览器自动设置
        if (!isFormData && data && method !== 'GET') {
            options.headers['Content-Type'] = 'application/json';
            options.body = JSON.stringify(data);
        } else if (data) {
            options.body = data;
        }

        const response = await fetch(url, options);
        
        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }
        
        const result = await response.json();
        return result;
    }

    showMessage(message, type = 'info') {
        // 移除已存在的消息
        const existingMessage = document.querySelector('.message');
        if (existingMessage) {
            existingMessage.remove();
        }

        const messageEl = document.createElement('div');
        messageEl.className = `message ${type}`;
        messageEl.textContent = message;
        
        // 添加到body，确保是全屏居中的弹窗
        document.body.appendChild(messageEl);
        
        // 根据消息类型设置不同的显示时间
        const duration = type === 'success' ? 5000 : 3000; // 成功消息显示5秒
        
        // 自动消失
        setTimeout(() => {
            if (messageEl.parentNode) {
                messageEl.remove();
            }
        }, duration);
    }
}

customElements.define('model-upload', ModelUpload);
