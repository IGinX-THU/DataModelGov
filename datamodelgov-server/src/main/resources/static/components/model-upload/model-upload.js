/**
 * 上传模型文件组件
 * 使用 Web Components (Custom Elements + Shadow DOM) 实现
 * 版本: 2.0 - 2026-02-24 14:20
 */
console.log('🔍 model-upload.js 开始加载');

class ModelUpload extends HTMLElement {
    constructor() {
        super();
        console.log('🔍 ModelUpload constructor 被调用');
        this.attachShadow({ mode: 'open' });
        this.selectedFile = null;
    }

    // 去掉存储路径前缀（如 models_system.projectName.）
    stripStoragePrefix(path) {
        if (!path) return path;
        const prefixes = ['models_system.', 'algorithms_system.'];
        for (const prefix of prefixes) {
            if (path.startsWith(prefix)) {
                // 去掉前缀后，再去掉项目名部分
                const withoutPrefix = path.substring(prefix.length);
                const parts = withoutPrefix.split('.');
                if (parts.length > 1) {
                    // 返回去掉项目名后的部分（即模型/算法名称）
                    return parts.slice(1).join('.');
                }
                return withoutPrefix;
            }
        }
        return path;
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
                                <p class="upload-hint">支持 .py, .m, .dll, .so, .pyd, .ame, .fmu, .mat, .zip 格式</p>
                                <input type="file" class="file-input" id="modelFile" accept=".py, .m, .dll, .so, .pyd, .ame, .fmu, .mat, .zip" required>
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
        // 关闭按钮由bindModalEvents处理，这里不重复绑定

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
                console.log('🔍 拖拽文件事件触发，文件数量:', files.length);
                if (files.length > 0) {
                    console.log('🔍 第一个文件信息:', files[0]);
                    this.handleFileSelect(files[0]);
                } else {
                    console.log('🔍 没有找到文件');
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

        // 模型名称输入框变化时自动生成版本号
        const modelNameInput = this.shadowRoot.getElementById('modelName');
        if (modelNameInput) {
            modelNameInput.addEventListener('input', () => {
                this.generateSuggestedVersion();
            });
        }

        // 模型名称下拉框变化时自动生成版本号
        const modelNameSelect = this.shadowRoot.getElementById('modelNameSelect');
        if (modelNameSelect) {
            modelNameSelect.addEventListener('change', () => {
                this.generateSuggestedVersion();
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

    async generateSuggestedVersion() {
        try {
            // 获取当前模型名称
            let modelName = '';
            
            // 优先从弹窗中获取元素
            const modal = document.querySelector('.modal-overlay');
            if (modal) {
                const modalContainer = modal.querySelector('.modal-container');
                if (modalContainer) {
                    const isRelatedModelYes = modalContainer.querySelector('#isRelatedModelYes');
                    const modelNameInput = modalContainer.querySelector('#modelName');
                    const modelNameSelect = modalContainer.querySelector('#modelNameSelect');
                    
                    if (isRelatedModelYes && isRelatedModelYes.checked && modelNameSelect) {
                        modelName = modelNameSelect.value;
                    } else if (modelNameInput) {
                        modelName = modelNameInput.value;
                    }
                }
            }
            
            // 如果弹窗中没有找到，尝试从Shadow DOM中获取
            if (!modelName) {
                const isRelatedModelYes = this.shadowRoot.getElementById('isRelatedModelYes');
                const modelNameInput = this.shadowRoot.getElementById('modelName');
                const modelNameSelect = this.shadowRoot.getElementById('modelNameSelect');
                
                if (isRelatedModelYes && isRelatedModelYes.checked && modelNameSelect) {
                    modelName = modelNameSelect.value;
                } else if (modelNameInput) {
                    modelName = modelNameInput.value;
                }
            }
            
            if (!modelName) {
                return; // 没有模型名称，不生成版本号
            }
            
            // 获取当前项目名称
            const username = window.localStorage.getItem('username');
            const cachedProject = username ? JSON.parse(window.localStorage.getItem('currentProject_' + username) || 'null') : null;
            const projectName = cachedProject ? cachedProject.name : null;
            
            // 调用后端API获取版本历史
            const params = { name: modelName };
            if (projectName) {
                params.projectName = projectName;
            }
            
            const result = await window.AppConfig.get('model', 'history', params);
            
            if (result.success && result.data && result.data.length > 0) {
                // 获取最新版本号
                const latestVersion = result.data[0].version;
                if (latestVersion) {
                    // 解析版本号并累加小版本号
                    // 支持两种格式：v1_0_0 或 1.0.0
                    let parts;
                    if (latestVersion.startsWith('v')) {
                        parts = latestVersion.substring(1).split('_');
                    } else {
                        parts = latestVersion.split('.');
                    }
                    
                    if (parts.length >= 3) {
                        try {
                            const major = parseInt(parts[0]);
                            const minor = parseInt(parts[1]);
                            const patch = parseInt(parts[2]);
                            const newVersion = `v${major}_${minor}_${patch + 1}`;
                            
                            // 填充到版本号输入框
                            const modelVersion = modal ? 
                                modal.querySelector('.modal-container #modelVersion') : 
                                this.shadowRoot.getElementById('modelVersion');
                            
                            if (modelVersion) {
                                modelVersion.value = newVersion;
                            }
                        } catch (e) {
                            console.warn('版本号解析失败:', e);
                        }
                    }
                }
            } else {
                // 没有版本历史，使用默认版本v1_0_0
                const modelVersion = modal ? 
                    modal.querySelector('.modal-container #modelVersion') : 
                    this.shadowRoot.getElementById('modelVersion');
                
                if (modelVersion) {
                    modelVersion.value = 'v1_0_0';
                }
            }
        } catch (error) {
            console.error('生成建议版本号失败:', error);
        }
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
        
        if (inputContainer) inputContainer.style.display = 'none';
        if (selectContainer) {
            selectContainer.style.display = 'block';
            // 数据已经在弹窗初始化时预加载，不需要重复加载
            console.log('🔍 显示模型选择下拉框，数据已预加载');
        }
    }

    showModelInput() {
        const inputContainer = this.shadowRoot.getElementById('modelNameInputContainer');
        const selectContainer = this.shadowRoot.getElementById('modelNameSelectContainer');
        
        if (inputContainer) inputContainer.style.display = 'block';
        if (selectContainer) selectContainer.style.display = 'none';
    }

    loadModelNames() {
        // 由于使用了弹窗管理器，需要从弹窗中查找实际显示的元素
        let modelNameSelect = null;
        
        // 首先尝试从弹窗中查找元素（这是实际显示的元素）
        const modalOverlay = document.querySelector('.modal-overlay');
        if (modalOverlay) {
            modelNameSelect = modalOverlay.querySelector('#modelNameSelect');
            console.log('🔍 loadModelNames: 从弹窗中查找modelNameSelect元素', modelNameSelect);
        }
        
        // 如果弹窗中没有找到，尝试从Shadow DOM中查找（备用方案）
        if (!modelNameSelect) {
            modelNameSelect = this.shadowRoot.getElementById('modelNameSelect');
            console.log('🔍 loadModelNames: 从Shadow DOM中查找modelNameSelect元素', modelNameSelect);
        }
        
        if (!modelNameSelect) {
            console.error('❌ 未找到modelNameSelect元素');
            return;
        }

        // 获取右侧模型资产库的根节点
        const modelTree = document.getElementById('modelTree');
        if (!modelTree) {
            console.warn('未找到模型树');
            return;
        }

        // 获取所有节点，包括嵌套的子节点
        const allNodes = modelTree.querySelectorAll('.tree-node');
        const modelNames = new Set(); // 使用Set避免重复
        
        allNodes.forEach(node => {
            // 检查是否是叶子节点（没有子节点的节点，即版本号）
            const childrenContainer = node.querySelector('.tree-children');
            if (!childrenContainer || childrenContainer.children.length === 0) {
                // 这是叶子节点（版本号），获取其完整路径
                const fullPath = node.getAttribute('data-full-path');
                if (fullPath) {
                    console.log('叶子节点完整路径:', fullPath);
                    // 路径格式：models_system.projectName.modelName.version
                    const parts = fullPath.split('.');
                    // 倒数第二级是模型名称
                    if (parts.length >= 3) {
                        const modelName = parts[parts.length - 2];
                        console.log('提取的模型名称:', modelName);
                        modelNames.add(modelName);
                    }
                }
            }
        });
        
        console.log('获取到的模型名称（倒数第二级节点）:', Array.from(modelNames));
        
        // 清空现有选项
        modelNameSelect.innerHTML = '<option value="">请选择模型名称</option>';
        console.log('🔍 已清空下拉选框，当前选项数量:', modelNameSelect.options.length);
        
        // 添加模型名称选项
        Array.from(modelNames).forEach(name => {
            const option = document.createElement('option');
            option.value = name;
            option.textContent = name;
            modelNameSelect.appendChild(option);
        });
        
        console.log('🔍 已添加模型名称选项，最终选项数量:', modelNameSelect.options.length);
        console.log('🔍 下拉选框HTML:', modelNameSelect.outerHTML);
        console.log('🔍 操作的元素来源:', modelNameSelect.closest('.modal-overlay') ? '弹窗中的元素' : 'Shadow DOM中的元素');
    }

    handleFileSelect(file) {
        console.log('🔍 handleFileSelect 被调用，文件:', file);
        console.log('🔍 文件检查 - file存在:', !!file);
        console.log('🔍 文件检查 - file类型:', typeof file);
        
        if (!file) {
            console.log('🔍 文件为空，返回');
            return;
        }

        console.log('🔍 开始验证文件类型');
        // 验证文件类型
        const allowedTypes = ['.py', '.m', '.dll', '.so', '.pyd', '.ame', '.fmu', '.mat', '.zip', '.cpp', '.c', '.h', '.hpp', '.cc', '.cxx', '.java', '.tar', '.gz'];
        const fileExtension = '.' + file.name.split('.').pop().toLowerCase();
        console.log('🔍 文件扩展名:', fileExtension, '允许的扩展名:', allowedTypes);
        
        if (!allowedTypes.includes(fileExtension)) {
            console.log('🔍 文件类型不支持');
            this.showMessage('不支持的文件格式，请选择支持的模型文件格式', 'error');
            return;
        }

        console.log('🔍 文件类型验证通过');
        // 验证文件大小（限制为100MB）
        const maxSize = 1024 * 1024 * 1024; // 100MB
        console.log('🔍 文件大小:', file.size, '最大允许大小:', maxSize);
        if (file.size > maxSize) {
            console.log('🔍 文件过大');
            this.showMessage('文件大小不能超过1GB', 'error');
            return;
        }

        console.log('🔍 文件大小验证通过，设置selectedFile');
        this.selectedFile = file;
        console.log('🔍 准备调用 displayFileInfo，this.displayFileInfo 方法是否存在:', typeof this.displayFileInfo);
        try {
            this.displayFileInfo(file);
            console.log('🔍 displayFileInfo 调用成功');
        } catch (error) {
            console.error('🔍 displayFileInfo 调用失败:', error);
        }
    }

    displayFileInfo(file) {
        console.log('🔍 displayFileInfo 被调用，文件:', file);
        
        // 优先从弹窗中获取元素（用于modal manager）
        let fileUploadArea = null;
        let fileInfo = null;
        let fileName = null;
        let fileSize = null;
        
        const modal = document.querySelector('.modal-overlay');
        console.log('🔍 尝试从弹窗中查找，modal:', !!modal);
        
        if (modal) {
            const modalContainer = modal.querySelector('.modal-container');
            console.log('🔍 modalContainer:', !!modalContainer);
            
            if (modalContainer) {
                fileUploadArea = modalContainer.querySelector('#fileUploadArea');
                fileInfo = modalContainer.querySelector('#fileInfo');
                fileName = modalContainer.querySelector('#fileName');
                fileSize = modalContainer.querySelector('#fileSize');
                
                console.log('🔍 弹窗中查找结果:', {
                    fileUploadArea: !!fileUploadArea,
                    fileInfo: !!fileInfo,
                    fileName: !!fileName,
                    fileSize: !!fileSize
                });
            }
        }
        
        // 如果弹窗中没有找到，尝试从Shadow DOM中获取（用于直接渲染）
        if (!fileUploadArea || !fileInfo || !fileName || !fileSize) {
            console.log('🔍 弹窗中未找到所有元素，尝试从Shadow DOM中查找');
            fileUploadArea = this.shadowRoot.getElementById('fileUploadArea');
            fileInfo = this.shadowRoot.getElementById('fileInfo');
            fileName = this.shadowRoot.getElementById('fileName');
            fileSize = this.shadowRoot.getElementById('fileSize');
            
            console.log('🔍 Shadow DOM 查找结果:', {
                fileUploadArea: !!fileUploadArea,
                fileInfo: !!fileInfo,
                fileName: !!fileName,
                fileSize: !!fileSize
            });
        }

        console.log('🔍 准备显示文件信息');
        
        if (fileUploadArea) {
            fileUploadArea.style.display = 'none';
            console.log('🔍 隐藏上传区域');
        }
        if (fileInfo) {
            fileInfo.style.display = 'flex';
            console.log('🔍 显示文件信息区域');
        }
        if (fileName) {
            fileName.textContent = file.name;
            console.log('🔍 设置文件名:', file.name);
        }
        if (fileSize) {
            fileSize.textContent = this.formatFileSize(file.size);
            console.log('🔍 设置文件大小:', this.formatFileSize(file.size));
        }
    }

    removeFile() {
        console.log('🔍 removeFile() 方法被调用');
        this.selectedFile = null;
        
        // 优先从弹窗中获取元素（用于modal manager）
        let fileUploadArea = null;
        let fileInfo = null;
        let fileInput = null;
        
        const modal = document.querySelector('.modal-overlay');
        console.log('🔍 查找弹窗:', modal);
        if (modal) {
            fileUploadArea = modal.querySelector('#fileUploadArea');
            fileInfo = modal.querySelector('#fileInfo');
            fileInput = modal.querySelector('#modelFile');
            console.log('🔍 弹窗中元素查找结果:', {
                fileUploadArea: !!fileUploadArea,
                fileInfo: !!fileInfo,
                fileInput: !!fileInput
            });
        }
        
        // 如果弹窗中没有找到，尝试从Shadow DOM中获取（用于直接渲染）
        if (!fileUploadArea || !fileInfo || !fileInput) {
            console.log('🔍 弹窗中未找到所有元素，尝试从Shadow DOM中查找');
            fileUploadArea = this.shadowRoot.getElementById('fileUploadArea');
            fileInfo = this.shadowRoot.getElementById('fileInfo');
            fileInput = this.shadowRoot.getElementById('modelFile');
            console.log('🔍 Shadow DOM 元素查找结果:', {
                fileUploadArea: !!fileUploadArea,
                fileInfo: !!fileInfo,
                fileInput: !!fileInput
            });
        }

        if (fileUploadArea) {
            fileUploadArea.style.display = 'block';
            console.log('🔍 显示文件上传区域');
        }
        if (fileInfo) {
            fileInfo.style.display = 'none';
            console.log('🔍 隐藏文件信息区域');
        }
        if (fileInput) {
            fileInput.value = '';
            console.log('🔍 清空文件输入框');
        }
    }

    formatFileSize(bytes) {
        if (bytes === 0) return '0 Bytes';
        const k = 1024;
        const sizes = ['Bytes', 'KB', 'MB', 'GB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
    }

    async show() {
        console.log('🔍 model-upload show() 被调用');

        // 使用通用弹窗管理器
        const modal = await window.modalManager.show(this, {
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
            
            // 绑定模型名称输入框和下拉框事件，用于自动生成版本号
            const modelNameInput = modalElement.querySelector('#modelName');
            if (modelNameInput) {
                modelNameInput.addEventListener('input', () => {
                    this.generateSuggestedVersion();
                });
            }
            
            const modelNameSelect = modalElement.querySelector('#modelNameSelect');
            if (modelNameSelect) {
                modelNameSelect.addEventListener('change', () => {
                    this.generateSuggestedVersion();
                });
            }
            
            // 在DOM完全准备好后预加载模型名称数据
            this.loadModelNames();
            
            console.log('🔍 事件绑定完成');
        }, 100);
    }

    async handleUpload() {
        console.log('🔍 handleUpload 被调用');
        
        // 清除之前的错误状态
        this.clearValidationErrors();
        
        // 优先从弹窗中获取元素（用于modal manager）
        let fileInput = null;
        let modelName = null;
        let modelNameSelect = null;
        let modelVersion = null;
        let isRelatedModelYes = null;
        let isRelatedModelNo = null;
        
        const modal = document.querySelector('.modal-overlay');
        if (modal) {
            const modalContainer = modal.querySelector('.modal-container');
            if (modalContainer) {
                fileInput = modalContainer.querySelector('#modelFile');
                modelName = modalContainer.querySelector('#modelName');
                modelNameSelect = modalContainer.querySelector('#modelNameSelect');
                modelVersion = modalContainer.querySelector('#modelVersion');
                isRelatedModelYes = modalContainer.querySelector('#isRelatedModelYes');
                isRelatedModelNo = modalContainer.querySelector('#isRelatedModelNo');
                
                console.log('🔍 弹窗中元素查找结果:', {
                    fileInput: !!fileInput,
                    modelName: !!modelName,
                    modelNameSelect: !!modelNameSelect,
                    modelVersion: !!modelVersion,
                    isRelatedModelYes: !!isRelatedModelYes,
                    isRelatedModelNo: !!isRelatedModelNo
                });
            }
        }
        
        // 如果弹窗中没有找到，尝试从Shadow DOM中获取（用于直接渲染）
        if (!fileInput || !modelName || !modelNameSelect || !modelVersion || !isRelatedModelYes || !isRelatedModelNo) {
            console.log('🔍 弹窗中未找到所有元素，尝试从Shadow DOM中查找');
            fileInput = this.shadowRoot.getElementById('modelFile');
            modelName = this.shadowRoot.getElementById('modelName');
            modelNameSelect = this.shadowRoot.getElementById('modelNameSelect');
            modelVersion = this.shadowRoot.getElementById('modelVersion');
            isRelatedModelYes = this.shadowRoot.getElementById('isRelatedModelYes');
            isRelatedModelNo = this.shadowRoot.getElementById('isRelatedModelNo');
            
            console.log('🔍 Shadow DOM 元素查找结果:', {
                fileInput: !!fileInput,
                modelName: !!modelName,
                modelNameSelect: !!modelNameSelect,
                modelVersion: !!modelVersion,
                isRelatedModelYes: !!isRelatedModelYes,
                isRelatedModelNo: !!isRelatedModelNo
            });
        }
        
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
        
        console.log('🔍 表单值获取详情:', {
            isRelatedModel,
            modelNameValue: nameValue,
            modelNameElement: modelName ? modelName.value : 'null',
            modelVersionValue: modelVersion ? modelVersion.value : 'null',
            modelVersionElement: modelVersion ? modelVersion.value : 'null'
        });
        
        const formData = {
            file: this.selectedFile || (fileInput ? fileInput.files[0] : null),
            modelName: nameValue,
            modelNameSelect: modelNameSelect ? modelNameSelect.value : '',
            modelVersion: modelVersion ? modelVersion.value : '',
            isRelatedModel: isRelatedModel
        };

        console.log('🔍 上传数据:', formData);
        
        let hasError = false;
        
        // 验证是否关联已有模型
        if (!isRelatedModelYes?.checked && !isRelatedModelNo?.checked) {
            this.showFieldError('isRelatedModel', '请选择是否关联已有模型');
            hasError = true;
        }
        
        // 验证模型名称
        if (!formData.modelName) {
            if (formData.isRelatedModel === 'yes') {
                this.showFieldError('modelNameSelect', '请选择模型名称');
            } else {
                this.showFieldError('modelName', '请输入模型名称');
            }
            hasError = true;
        }
        
        // 验证版本号
        if (!formData.modelVersion) {
            this.showFieldError('modelVersion', '请输入版本号');
            hasError = true;
        }
        
        // 验证模型文件
        if (!formData.file) {
            this.showFieldError('modelFile', '请选择模型文件');
            hasError = true;
        }
        
        if (hasError) {
            this.showMessage('请填写必填字段', 'error');
            return;
        }

        try {
            console.log('🔍 开始API调用');
            // 创建FormData对象用于文件上传
            const uploadFormData = new FormData();
            uploadFormData.append('file', formData.file);
            uploadFormData.append('name', formData.modelName);
            uploadFormData.append('version', formData.modelVersion);

            console.log('🔍 FormData内容:', {
                file: formData.file.name,
                name: formData.modelName,
                version: formData.modelVersion
            });

            // 调用上传API
            console.log('🔍 调用API: /api/model/upload');
            const response = await this.apiCall('/api/model/upload', 'POST', uploadFormData, true);
            console.log('🔍 API响应:', response);
            
            if (response.code === 200) {
                this.showMessage('模型文件上传成功', 'success');
                
                // 重新加载右侧模型资产库
                console.log('🔄 模型上传成功，准备调用 loadDataSourceTree');
                if (window.loadDataSourceTree) {
                    console.log('🔄 调用 window.loadDataSourceTree');
                    window.loadDataSourceTree();
                } else {
                    console.error('❌ window.loadDataSourceTree 不存在');
                }
                
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
            } else if (response.code === 400) {
                this.showMessage(response.message || '请求参数错误', 'error');
            } else if (response.code === 500) {
                this.showMessage(response.message || '服务器内部错误', 'error');
            } else {
                this.showMessage(response.message || '上传失败', 'error');
            }
            
            // 无论成功失败都关闭弹窗
            this.hide();
        } catch (error) {
            console.error('上传模型文件失败:', error);
            this.showMessage('上传失败，请稍后重试', 'error');
            // 异常情况下也要关闭弹窗
            this.hide();
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
                console.log('🔍 bindModalEvents 拖拽文件事件触发，文件:', file);
                if (file) {
                    this.handleFileSelect(file);
                } else {
                    console.log('🔍 bindModalEvents 没有找到文件');
                }
            });
        }
        
        // 绑定移除文件按钮事件
        const removeFileBtn = modalElement.querySelector('#removeFileBtn');
        console.log('🔍 bindFileEvents - 查找移除文件按钮:', removeFileBtn);
        if (removeFileBtn) {
            console.log('🔍 bindFileEvents - 绑定移除文件按钮点击事件');
            removeFileBtn.addEventListener('click', (e) => {
                console.log('🔍 移除文件按钮被点击');
                e.preventDefault();
                e.stopPropagation();
                this.removeFile();
            });
        } else {
            console.error('❌ bindFileEvents - 未找到移除文件按钮');
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
        // 首先尝试从Shadow DOM中获取元素（用于直接渲染）
        let modelName = this.shadowRoot.getElementById('modelName');
        let modelNameSelect = this.shadowRoot.getElementById('modelNameSelect');
        let modelVersion = this.shadowRoot.getElementById('modelVersion');
        let isRelatedModelYes = this.shadowRoot.getElementById('isRelatedModelYes');
        let isRelatedModelNo = this.shadowRoot.getElementById('isRelatedModelNo');
        let modelNameInputContainer = this.shadowRoot.getElementById('modelNameInputContainer');
        let modelNameSelectContainer = this.shadowRoot.getElementById('modelNameSelectContainer');
        
        // 如果Shadow DOM中没有找到，尝试从弹窗中获取（用于modal manager）
        if (!modelName || !modelNameSelect || !modelVersion || !isRelatedModelYes || !isRelatedModelNo) {
            const modal = document.querySelector('.modal-overlay');
            if (modal) {
                modelName = modal.querySelector('#modelName');
                modelNameSelect = modal.querySelector('#modelNameSelect');
                modelVersion = modal.querySelector('#modelVersion');
                isRelatedModelYes = modal.querySelector('#isRelatedModelYes');
                isRelatedModelNo = modal.querySelector('#isRelatedModelNo');
                modelNameInputContainer = modal.querySelector('#modelNameInputContainer');
                modelNameSelectContainer = modal.querySelector('#modelNameSelectContainer');
            }
        }

        // 重置是否关联已有模型单选框（默认选中"否"）
        if (isRelatedModelYes) isRelatedModelYes.checked = false;
        if (isRelatedModelNo) isRelatedModelNo.checked = true;
        
        // 显示输入框，隐藏下拉选择框
        if (modelNameInputContainer) modelNameInputContainer.style.display = 'block';
        if (modelNameSelectContainer) modelNameSelectContainer.style.display = 'none';
        
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
            uploadFormData.append('name', formData.name);
            uploadFormData.append('version', formData.version);

            // 调用上传API
            const response = await this.apiCall('/api/model/upload', 'POST', uploadFormData, true);
            
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
            } else if (response.code === 400) {
                const errorMessage = response.message || '请求参数错误';
                this.showMessage(errorMessage, 'error');
            } else if (response.code === 500) {
                const errorMessage = response.message || '服务器内部错误';
                this.showMessage(errorMessage, 'error');
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
        // 首先尝试从Shadow DOM中获取元素（用于直接渲染）
        let modelName = this.shadowRoot.getElementById('modelName');
        let modelNameSelect = this.shadowRoot.getElementById('modelNameSelect');
        let modelVersion = this.shadowRoot.getElementById('modelVersion');
        let isRelatedModelYes = this.shadowRoot.getElementById('isRelatedModelYes');
        let isRelatedModelNo = this.shadowRoot.getElementById('isRelatedModelNo');
        
        // 如果Shadow DOM中没有找到，尝试从弹窗中获取（用于modal manager）
        if (!modelName || !modelNameSelect || !modelVersion || !isRelatedModelYes || !isRelatedModelNo) {
            const modal = document.querySelector('.modal-overlay');
            if (modal) {
                modelName = modal.querySelector('#modelName');
                modelNameSelect = modal.querySelector('#modelNameSelect');
                modelVersion = modal.querySelector('#modelVersion');
                isRelatedModelYes = modal.querySelector('#isRelatedModelYes');
                isRelatedModelNo = modal.querySelector('#isRelatedModelNo');
            }
        }
        
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
        // 优先从弹窗中获取元素（用于modal manager）
        let field = null;
        let errorElement = null;
        
        const modal = document.querySelector('.modal-overlay');
        if (modal) {
            const modalContainer = modal.querySelector('.modal-container');
            if (modalContainer) {
                field = modalContainer.querySelector('#' + fieldId);
                errorElement = modalContainer.querySelector('#' + fieldId + 'Error');
            }
        }
        
        // 如果弹窗中没有找到，尝试从Shadow DOM中获取（用于直接渲染）
        if (!field || !errorElement) {
            field = this.shadowRoot.getElementById(fieldId);
            errorElement = this.shadowRoot.getElementById(fieldId + 'Error');
        }
        
        const formGroup = field?.closest('.form-group');
        
        console.log(`🔍 showFieldError ${fieldId}:`, {
            field: !!field,
            errorElement: !!errorElement,
            formGroup: !!formGroup,
            message
        });
        
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
        // 优先从弹窗中获取元素（用于modal manager）
        let field = null;
        let errorElement = null;
        
        const modal = document.querySelector('.modal-overlay');
        if (modal) {
            const modalContainer = modal.querySelector('.modal-container');
            if (modalContainer) {
                field = modalContainer.querySelector('#' + fieldId);
                errorElement = modalContainer.querySelector('#' + fieldId + 'Error');
            }
        }
        
        // 如果弹窗中没有找到，尝试从Shadow DOM中获取（用于直接渲染）
        if (!field || !errorElement) {
            field = this.shadowRoot.getElementById(fieldId);
            errorElement = this.shadowRoot.getElementById(fieldId + 'Error');
        }
        
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
        try {
            let result;
            
            if (isFormData) {
                // 文件上传使用AppConfig.upload
                result = await window.AppConfig.upload('model', 'upload', data);
            } else {
                // 普通API调用使用AppConfig
                if (method === 'GET') {
                    // 从URL中提取模块和端点
                    const urlPath = new URL(url, window.AppConfig.api.baseURL).pathname;
                    // 简单的URL解析，假设格式为 /api/module/endpoint
                    const pathParts = urlPath.split('/').filter(p => p);
                    if (pathParts.length >= 3 && pathParts[1] === 'api') {
                        const module = pathParts[2];
                        const endpoint = pathParts.slice(3).join('/');
                        const params = data ? { ...data } : {};
                        result = await window.AppConfig.get(module, endpoint, params);
                    } else {
                        throw new Error('无法解析API URL: ' + url);
                    }
                } else if (method === 'POST') {
                    const urlPath = new URL(url, window.AppConfig.api.baseURL).pathname;
                    const pathParts = urlPath.split('/').filter(p => p);
                    if (pathParts.length >= 3 && pathParts[1] === 'api') {
                        const module = pathParts[2];
                        const endpoint = pathParts.slice(3).join('/');
                        result = await window.AppConfig.post(module, endpoint, data);
                    } else {
                        throw new Error('无法解析API URL: ' + url);
                    }
                } else {
                    throw new Error('不支持的HTTP方法: ' + method);
                }
            }
            
            return result;
        } catch (error) {
            if (error.name === 'TypeError' && error.message.includes('fetch')) {
                throw new Error('网络连接失败，请检查网络连接');
            }
            throw error;
        }
    }

    showMessage(message, type = 'info') {
        if (window.CommonUtils && window.CommonUtils.showToast) {
            window.CommonUtils.showToast(message, type);
        } else {
            console.warn('CommonUtils.showToast not available, message:', message);
        }
    }
}

console.log('🔍 准备注册自定义元素 model-upload');
try {
    customElements.define('model-upload', ModelUpload);
    console.log('✅ model-upload 自定义元素注册成功');
} catch (error) {
    console.error('❌ model-upload 自定义元素注册失败:', error);
}
