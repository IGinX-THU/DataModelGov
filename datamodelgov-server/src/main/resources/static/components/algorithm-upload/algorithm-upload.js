/**
 * 上传算法文件组件
 * 使用 Web Components (Custom Elements + Shadow DOM) 实现
 * 版本: 2.0 - 2026-02-24 14:20
 */
console.log('🔍 algorithm-upload.js 开始加载');

class AlgorithmUpload extends HTMLElement {
    constructor() {
        super();
        console.log('🔍 AlgorithmUpload constructor 被调用');
        this.attachShadow({ mode: 'open' });
        this.selectedFile = null;
    }

    // 去掉存储路径前缀（如 algorithms_system.projectName.）
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
            cssLink.href = './components/algorithm-upload/algorithm-upload.css';
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
            const response = await fetch('./components/algorithm-upload/algorithm-upload.html');
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
                        <label class="form-label required">是否关联已有算法</label>
                        <div class="radio-group-horizontal">
                            <div class="radio-item-horizontal">
                                <input type="radio" id="isRelatedAlgorithmYes" name="isRelatedAlgorithm" value="yes" required>
                                <label for="isRelatedAlgorithmYes">是</label>
                            </div>
                            <div class="radio-item-horizontal">
                                <input type="radio" id="isRelatedAlgorithmNo" name="isRelatedAlgorithm" value="no" checked required>
                                <label for="isRelatedAlgorithmNo">否</label>
                            </div>
                        </div>
                    </div>

                    <div class="form-group">
                        <label class="form-label required">名称</label>
                        <div id="algorithmNameInputContainer">
                            <input type="text" class="form-control" id="algorithmName" placeholder="请输入算法名称" required>
                        </div>
                        <div id="algorithmNameSelectContainer" style="display: none;">
                            <select class="form-control form-select" id="algorithmNameSelect" required>
                                <option value="">请选择算法名称</option>
                            </select>
                        </div>
                    </div>

                    <div class="form-group">
                        <label class="form-label required">版本号</label>
                        <input type="text" class="form-control" id="algorithmVersion" placeholder="请输入版本号" required>
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
        const fileInput = this.shadowRoot.getElementById('algorithmFile');
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

        // 是否关联已有算法变化事件
        const isRelatedAlgorithmYes = this.shadowRoot.getElementById('isRelatedAlgorithmYes');
        const isRelatedAlgorithmNo = this.shadowRoot.getElementById('isRelatedAlgorithmNo');
        
        if (isRelatedAlgorithmYes) {
            isRelatedAlgorithmYes.addEventListener('change', () => {
                this.handleRelatedAlgorithmChange();
            });
        }
        
        if (isRelatedAlgorithmNo) {
            isRelatedAlgorithmNo.addEventListener('change', () => {
                this.handleRelatedAlgorithmChange();
            });
        }

        // ESC键关闭
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape' && this.hasAttribute('show')) {
                this.hide();
            }
        });
    }

    handleRelatedAlgorithmChange() {
        const isRelatedAlgorithmYes = this.shadowRoot.getElementById('isRelatedAlgorithmYes');
        const isRelatedAlgorithmNo = this.shadowRoot.getElementById('isRelatedAlgorithmNo');
        
        if (!isRelatedAlgorithmYes || !isRelatedAlgorithmNo) {
            console.warn('handleRelatedAlgorithmChange: 单选框元素未找到');
            return;
        }
        
        const selectedValue = isRelatedAlgorithmYes.checked ? 'yes' : (isRelatedAlgorithmNo.checked ? 'no' : '');
        console.log('handleRelatedAlgorithmChange: 选择值', selectedValue);
        
        if (selectedValue === 'yes') {
            console.log('选择了关联已有算法，切换到下拉选择框');
            this.showAlgorithmSelect();
        } else {
            console.log('选择了不关联已有算法，切换到输入框');
            this.showAlgorithmInput();
        }
    }

    showAlgorithmSelect() {
        const inputContainer = this.shadowRoot.getElementById('algorithmNameInputContainer');
        const selectContainer = this.shadowRoot.getElementById('algorithmNameSelectContainer');
        
        if (inputContainer) inputContainer.style.display = 'none';
        if (selectContainer) {
            selectContainer.style.display = 'block';
            // 数据已经在弹窗初始化时预加载，不需要重复加载
            console.log('🔍 显示算法选择下拉框，数据已预加载');
        }
    }

    showAlgorithmInput() {
        const inputContainer = this.shadowRoot.getElementById('algorithmNameInputContainer');
        const selectContainer = this.shadowRoot.getElementById('algorithmNameSelectContainer');
        
        if (inputContainer) inputContainer.style.display = 'block';
        if (selectContainer) selectContainer.style.display = 'none';
    }

    loadAlgorithmNames() {
        // 由于使用了弹窗管理器，需要从弹窗中查找实际显示的元素
        let algorithmNameSelect = null;
        
        // 首先尝试从弹窗中查找元素（这是实际显示的元素）
        const modalOverlay = document.querySelector('.modal-overlay');
        if (modalOverlay) {
            algorithmNameSelect = modalOverlay.querySelector('#algorithmNameSelect');
            console.log('🔍 loadAlgorithmNames: 从弹窗中查找algorithmNameSelect元素', algorithmNameSelect);
        }
        
        // 如果弹窗中没有找到，尝试从Shadow DOM中查找（备用方案）
        if (!algorithmNameSelect) {
            algorithmNameSelect = this.shadowRoot.getElementById('algorithmNameSelect');
            console.log('🔍 loadAlgorithmNames: 从Shadow DOM中查找algorithmNameSelect元素', algorithmNameSelect);
        }
        
        if (!algorithmNameSelect) {
            console.error('❌ 未找到algorithmNameSelect元素');
            return;
        }

        // 获取右侧算法资产库的根节点
        const algorithmTree = document.getElementById('algorithmTree');
        if (!algorithmTree) {
            console.warn('未找到算法树');
            return;
        }

        // 获取所有节点，包括嵌套的子节点
        const allNodes = algorithmTree.querySelectorAll('.tree-node');
        const algorithmNames = new Set(); // 使用Set避免重复
        
        allNodes.forEach(node => {
            const span = node.querySelector('span');
            if (span) {
                const nodeName = span.textContent.trim();
                
                // 排除明显的路径节点
                if (nodeName === 'algorithms_system') {
                    return;
                }

                // 去掉存储路径前缀
                const strippedName = this.stripStoragePrefix(nodeName);

                // 检查是否是父节点（有子节点的节点）
                const childrenContainer = node.querySelector('.tree-children');
                if (childrenContainer && childrenContainer.children.length > 0) {
                    // 检查子节点是否为叶子节点（没有子节点的节点）
                    const childNodes = childrenContainer.querySelectorAll('.tree-node');
                    let hasLeafChild = false;

                    childNodes.forEach(childNode => {
                        const childChildrenContainer = childNode.querySelector('.tree-children');
                        // 如果子节点没有子节点，则是叶子节点
                        if (!childChildrenContainer || childChildrenContainer.children.length === 0) {
                            hasLeafChild = true;
                        }
                    });

                    // 只有当子节点包含叶子节点时，才将父节点作为算法名称
                    if (hasLeafChild) {
                        algorithmNames.add(strippedName);
                    }
                }
            }
        });
        
        console.log('获取到的算法名称（最后一级叶子节点的父节点）:', Array.from(algorithmNames));
        
        // 清空现有选项
        algorithmNameSelect.innerHTML = '<option value="">请选择算法名称</option>';
        console.log('🔍 已清空下拉选框，当前选项数量:', algorithmNameSelect.options.length);
        
        // 添加算法名称选项
        Array.from(algorithmNames).forEach(name => {
            const option = document.createElement('option');
            option.value = name;
            option.textContent = name;
            algorithmNameSelect.appendChild(option);
        });
        
        console.log('🔍 已添加算法名称选项，最终选项数量:', algorithmNameSelect.options.length);
        console.log('🔍 下拉选框HTML:', algorithmNameSelect.outerHTML);
        console.log('🔍 操作的元素来源:', algorithmNameSelect.closest('.modal-overlay') ? '弹窗中的元素' : 'Shadow DOM中的元素');
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
        const allowedTypes = ['.py', '.c', '.cpp', '.h', '.m', '.zip'];
        const fileExtension = '.' + file.name.split('.').pop().toLowerCase();
        console.log('🔍 文件扩展名:', fileExtension, '允许的扩展名:', allowedTypes);
        
        if (!allowedTypes.includes(fileExtension)) {
            console.log('🔍 文件类型不支持');
            this.showMessage('不支持的文件格式，请选择支持的算法文件格式', 'error');
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
            fileInput = modal.querySelector('#algorithmFile');
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
            fileInput = this.shadowRoot.getElementById('algorithmFile');
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

    show() {
        console.log('🔍 algorithm-upload show() 被调用');
        
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
        console.log('🔍 algorithm-upload hide() 被调用');
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
            
            // 在DOM完全准备好后预加载算法名称数据
            this.loadAlgorithmNames();
            
            console.log('🔍 事件绑定完成');
        }, 100);
    }

    async handleUpload() {
        console.log('🔍 handleUpload 被调用');
        
        // 清除之前的错误状态
        this.clearValidationErrors();
        
        // 优先从弹窗中获取元素（用于modal manager）
        let fileInput = null;
        let algorithmName = null;
        let algorithmNameSelect = null;
        let algorithmVersion = null;
        let isRelatedAlgorithmYes = null;
        let isRelatedAlgorithmNo = null;
        
        const modal = document.querySelector('.modal-overlay');
        if (modal) {
            const modalContainer = modal.querySelector('.modal-container');
            if (modalContainer) {
                fileInput = modalContainer.querySelector('#algorithmFile');
                algorithmName = modalContainer.querySelector('#algorithmName');
                algorithmNameSelect = modalContainer.querySelector('#algorithmNameSelect');
                algorithmVersion = modalContainer.querySelector('#algorithmVersion');
                isRelatedAlgorithmYes = modalContainer.querySelector('#isRelatedAlgorithmYes');
                isRelatedAlgorithmNo = modalContainer.querySelector('#isRelatedAlgorithmNo');
                
                console.log('🔍 弹窗中元素查找结果:', {
                    fileInput: !!fileInput,
                    algorithmName: !!algorithmName,
                    algorithmNameSelect: !!algorithmNameSelect,
                    algorithmVersion: !!algorithmVersion,
                    isRelatedAlgorithmYes: !!isRelatedAlgorithmYes,
                    isRelatedAlgorithmNo: !!isRelatedAlgorithmNo
                });
            }
        }
        
        // 如果弹窗中没有找到，尝试从Shadow DOM中获取（用于直接渲染）
        if (!fileInput || !algorithmName || !algorithmNameSelect || !algorithmVersion || !isRelatedAlgorithmYes || !isRelatedAlgorithmNo) {
            console.log('🔍 弹窗中未找到所有元素，尝试从Shadow DOM中查找');
            fileInput = this.shadowRoot.getElementById('algorithmFile');
            algorithmName = this.shadowRoot.getElementById('algorithmName');
            algorithmNameSelect = this.shadowRoot.getElementById('algorithmNameSelect');
            algorithmVersion = this.shadowRoot.getElementById('algorithmVersion');
            isRelatedAlgorithmYes = this.shadowRoot.getElementById('isRelatedAlgorithmYes');
            isRelatedAlgorithmNo = this.shadowRoot.getElementById('isRelatedAlgorithmNo');
            
            console.log('🔍 Shadow DOM 元素查找结果:', {
                fileInput: !!fileInput,
                algorithmName: !!algorithmName,
                algorithmNameSelect: !!algorithmNameSelect,
                algorithmVersion: !!algorithmVersion,
                isRelatedAlgorithmYes: !!isRelatedAlgorithmYes,
                isRelatedAlgorithmNo: !!isRelatedAlgorithmNo
            });
        }
        
        const isRelatedAlgorithm = isRelatedAlgorithmYes && isRelatedAlgorithmYes.checked ? 'yes' : 
                                   (isRelatedAlgorithmNo && isRelatedAlgorithmNo.checked ? 'no' : '');
        
        let nameValue = '';
        
        // 根据关联算法选择获取名称值
        if (isRelatedAlgorithm === 'yes') {
            // 从下拉选择框获取值
            nameValue = algorithmNameSelect ? algorithmNameSelect.value : '';
        } else {
            // 从输入框获取值
            nameValue = algorithmName ? algorithmName.value : '';
        }
        
        console.log('🔍 表单值获取详情:', {
            isRelatedAlgorithm,
            algorithmNameValue: nameValue,
            algorithmNameElement: algorithmName ? algorithmName.value : 'null',
            algorithmVersionValue: algorithmVersion ? algorithmVersion.value : 'null',
            algorithmVersionElement: algorithmVersion ? algorithmVersion.value : 'null'
        });
        
        const formData = {
            file: this.selectedFile || (fileInput ? fileInput.files[0] : null),
            algorithmName: nameValue,
            algorithmNameSelect: algorithmNameSelect ? algorithmNameSelect.value : '',
            algorithmVersion: algorithmVersion ? algorithmVersion.value : '',
            isRelatedAlgorithm: isRelatedAlgorithm
        };

        console.log('🔍 上传数据:', formData);
        
        let hasError = false;
        
        // 验证是否关联已有算法
        if (!isRelatedAlgorithmYes?.checked && !isRelatedAlgorithmNo?.checked) {
            this.showFieldError('isRelatedAlgorithm', '请选择是否关联已有算法');
            hasError = true;
        }
        
        // 验证算法名称
        if (!formData.algorithmName) {
            if (formData.isRelatedAlgorithm === 'yes') {
                this.showFieldError('algorithmNameSelect', '请选择算法名称');
            } else {
                this.showFieldError('algorithmName', '请输入算法名称');
            }
            hasError = true;
        }
        
        // 验证版本号
        if (!formData.algorithmVersion) {
            this.showFieldError('algorithmVersion', '请输入版本号');
            hasError = true;
        }
        
        // 验证算法文件
        if (!formData.file) {
            this.showFieldError('algorithmFile', '请选择算法文件');
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
            uploadFormData.append('name', formData.algorithmName);
            uploadFormData.append('version', formData.algorithmVersion);

            console.log('🔍 FormData内容:', {
                file: formData.file.name,
                name: formData.algorithmName,
                version: formData.algorithmVersion
            });

            // 调用上传API
            console.log('🔍 调用API: /api/algorithm/upload');
            const response = await this.apiCall('/api/algorithm/upload', 'POST', uploadFormData, true);
            console.log('🔍 API响应:', response);
            
            if (response.code === 200) {
                this.showMessage('算法文件上传成功', 'success');
                
                // 重新加载右侧算法资产库
                console.log('🔄 算法上传成功，准备调用 loadDataSourceTree');
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
            console.error('上传算法文件失败:', error);
            this.showMessage('上传失败，请稍后重试', 'error');
            // 异常情况下也要关闭弹窗
            this.hide();
        }
    }

    
    bindFileEvents(modalElement) {
        const fileUploadArea = modalElement.querySelector('#fileUploadArea');
        const fileInput = modalElement.querySelector('#algorithmFile');
        
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
        const yesRadio = modalElement.querySelector('#isRelatedAlgorithmYes');
        const noRadio = modalElement.querySelector('#isRelatedAlgorithmNo');
        const inputContainer = modalElement.querySelector('#algorithmNameInputContainer');
        const selectContainer = modalElement.querySelector('#algorithmNameSelectContainer');
        
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
        let algorithmName = this.shadowRoot.getElementById('algorithmName');
        let algorithmNameSelect = this.shadowRoot.getElementById('algorithmNameSelect');
        let algorithmVersion = this.shadowRoot.getElementById('algorithmVersion');
        let isRelatedAlgorithmYes = this.shadowRoot.getElementById('isRelatedAlgorithmYes');
        let isRelatedAlgorithmNo = this.shadowRoot.getElementById('isRelatedAlgorithmNo');
        let algorithmNameInputContainer = this.shadowRoot.getElementById('algorithmNameInputContainer');
        let algorithmNameSelectContainer = this.shadowRoot.getElementById('algorithmNameSelectContainer');
        
        // 如果Shadow DOM中没有找到，尝试从弹窗中获取（用于modal manager）
        if (!algorithmName || !algorithmNameSelect || !algorithmVersion || !isRelatedAlgorithmYes || !isRelatedAlgorithmNo) {
            const modal = document.querySelector('.modal-overlay');
            if (modal) {
                algorithmName = modal.querySelector('#algorithmName');
                algorithmNameSelect = modal.querySelector('#algorithmNameSelect');
                algorithmVersion = modal.querySelector('#algorithmVersion');
                isRelatedAlgorithmYes = modal.querySelector('#isRelatedAlgorithmYes');
                isRelatedAlgorithmNo = modal.querySelector('#isRelatedAlgorithmNo');
                algorithmNameInputContainer = modal.querySelector('#algorithmNameInputContainer');
                algorithmNameSelectContainer = modal.querySelector('#algorithmNameSelectContainer');
            }
        }

        // 重置是否关联已有算法单选框（默认选中"否"）
        if (isRelatedAlgorithmYes) isRelatedAlgorithmYes.checked = false;
        if (isRelatedAlgorithmNo) isRelatedAlgorithmNo.checked = true;
        
        // 显示输入框，隐藏下拉选择框
        if (algorithmNameInputContainer) algorithmNameInputContainer.style.display = 'block';
        if (algorithmNameSelectContainer) algorithmNameSelectContainer.style.display = 'none';
        
        // 重置名称字段
        if (algorithmName) algorithmName.value = '';
        if (algorithmNameSelect) algorithmNameSelect.value = '';
        
        // 重置版本号
        if (algorithmVersion) algorithmVersion.value = '';

        this.removeFile();
    }

    async upload() {
        // 清除之前的错误状态
        this.clearValidationErrors();
        
        const formData = this.getFormData();
        
        let hasError = false;
        
        // 验证是否关联已有算法
        const isRelatedAlgorithmYes = this.shadowRoot.getElementById('isRelatedAlgorithmYes');
        const isRelatedAlgorithmNo = this.shadowRoot.getElementById('isRelatedAlgorithmNo');
        
        if (!isRelatedAlgorithmYes?.checked && !isRelatedAlgorithmNo?.checked) {
            this.showFieldError('isRelatedAlgorithm', '请选择是否关联已有算法');
            hasError = true;
        }
        
        // 验证算法名称
        if (!formData.name) {
            if (formData.isRelatedAlgorithm === 'yes') {
                this.showFieldError('algorithmNameSelect', '请选择算法名称');
            } else {
                this.showFieldError('algorithmName', '请输入算法名称');
            }
            hasError = true;
        }
        
        // 验证版本号
        if (!formData.version) {
            this.showFieldError('algorithmVersion', '请输入版本号');
            hasError = true;
        }
        
        // 验证算法文件
        if (!this.selectedFile) {
            this.showFieldError('algorithmFile', '请选择算法文件');
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
            const response = await this.apiCall('/api/algorithm/upload', 'POST', uploadFormData, true);
            
            if (response.code === 200) {
                this.showMessage('算法文件上传成功', 'success');
                
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
            console.error('上传算法文件失败:', error);
            this.showMessage('上传失败，请稍后重试', 'error');
        }
    }

    getFormData() {
        // 首先尝试从Shadow DOM中获取元素（用于直接渲染）
        let algorithmName = this.shadowRoot.getElementById('algorithmName');
        let algorithmNameSelect = this.shadowRoot.getElementById('algorithmNameSelect');
        let algorithmVersion = this.shadowRoot.getElementById('algorithmVersion');
        let isRelatedAlgorithmYes = this.shadowRoot.getElementById('isRelatedAlgorithmYes');
        let isRelatedAlgorithmNo = this.shadowRoot.getElementById('isRelatedAlgorithmNo');
        
        // 如果Shadow DOM中没有找到，尝试从弹窗中获取（用于modal manager）
        if (!algorithmName || !algorithmNameSelect || !algorithmVersion || !isRelatedAlgorithmYes || !isRelatedAlgorithmNo) {
            const modal = document.querySelector('.modal-overlay');
            if (modal) {
                algorithmName = modal.querySelector('#algorithmName');
                algorithmNameSelect = modal.querySelector('#algorithmNameSelect');
                algorithmVersion = modal.querySelector('#algorithmVersion');
                isRelatedAlgorithmYes = modal.querySelector('#isRelatedAlgorithmYes');
                isRelatedAlgorithmNo = modal.querySelector('#isRelatedAlgorithmNo');
            }
        }
        
        const isRelatedAlgorithm = isRelatedAlgorithmYes && isRelatedAlgorithmYes.checked ? 'yes' : 
                                   (isRelatedAlgorithmNo && isRelatedAlgorithmNo.checked ? 'no' : '');
        
        let nameValue = '';
        
        // 根据关联算法选择获取名称值
        if (isRelatedAlgorithm === 'yes') {
            // 从下拉选择框获取值
            nameValue = algorithmNameSelect ? algorithmNameSelect.value : '';
        } else {
            // 从输入框获取值
            nameValue = algorithmName ? algorithmName.value : '';
        }
        
        return {
            file: this.selectedFile,
            isRelatedAlgorithm: isRelatedAlgorithm,
            name: nameValue,
            version: algorithmVersion ? algorithmVersion.value : ''
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
                result = await window.AppConfig.upload('algorithm', 'upload', data);
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

console.log('🔍 准备注册自定义元素 algorithm-upload');
try {
    customElements.define('algorithm-upload', AlgorithmUpload);
    console.log('✅ algorithm-upload 自定义元素注册成功');
} catch (error) {
    console.error('❌ algorithm-upload 自定义元素注册失败:', error);
}
