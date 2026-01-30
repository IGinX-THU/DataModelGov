class ModelDownload extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });
        this.selectedModel = null;
        // 确保组件初始状态是隐藏的
        this.style.display = 'none';
    }

    async connectedCallback() {
        await this.loadResources();
        // 等待CSS加载完成后再渲染HTML
        setTimeout(() => {
            this.render();
            // 等待DOM渲染完成后再绑定事件
            setTimeout(() => {
                this.bindEvents();
            }, 100);
        }, 100);
    }

    async loadResources() {
        console.log('开始加载下载组件资源...');
        
        // 直接内联CSS，确保样式正确加载，并限制作用域
        const cssText = `
            .download-host {
                position: fixed !important;
                top: 0 !important;
                left: 0 !important;
                width: 100% !important;
                height: 100% !important;
                background: rgba(0, 0, 0, 0.5) !important;
                display: none !important;
                z-index: 1000 !important;
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif !important;
            }

            .download-host.show {
                display: block !important;
            }

            .download-container {
                background: white !important;
                border-radius: 8px !important;
                box-shadow: 0 4px 20px rgba(0, 0, 0, 0.15) !important;
                width: 500px !important;
                max-width: 90vw !important;
                max-height: 70vh !important;
                overflow-y: auto !important;
                position: absolute !important;
                top: 140px !important;
                left: 50% !important;
                transform: translateX(-50%) !important;
                padding: 24px !important;
                box-sizing: border-box !important;
            }

            .download-header {
                display: flex !important;
                justify-content: space-between !important;
                align-items: center !important;
                margin-bottom: 24px !important;
            }

            .download-title {
                margin: 0 !important;
                font-size: 18px !important;
                font-weight: 600 !important;
                color: #1f2329 !important;
            }

            .close-btn {
                background: none !important;
                border: none !important;
                font-size: 24px !important;
                cursor: pointer !important;
                color: #646a73 !important;
                padding: 0 !important;
                width: 24px !important;
                height: 24px !important;
                display: flex !important;
                align-items: center !important;
                justify-content: center !important;
            }

            .close-btn:hover {
                color: #1f2329 !important;
            }

            .form-group {
                margin-bottom: 20px !important;
            }

            .form-label {
                display: block !important;
                margin-bottom: 8px !important;
                font-size: 14px !important;
                font-weight: 500 !important;
                color: #1f2329 !important;
            }

            .form-label.required::before {
                content: '*' !important;
                color: #f5222d !important;
                margin-right: 4px !important;
            }

            .form-control {
                width: 100% !important;
                padding: 8px 12px !important;
                border: 1px solid #c9cdd4 !important;
                border-radius: 4px !important;
                font-size: 14px !important;
                transition: border-color 0.2s !important;
                box-sizing: border-box !important;
                background: white !important;
            }

            .form-control:focus {
                outline: none !important;
                border-color: #3370ff !important;
                box-shadow: 0 0 0 2px rgba(51, 112, 255, 0.1) !important;
            }

            .form-control.error {
                border-color: #f5222d !important;
            }

            .form-select {
                background-color: white !important;
                cursor: pointer !important;
            }

            .error-message {
                color: #f5222d !important;
                font-size: 12px !important;
                margin-top: 4px !important;
                display: none !important;
            }

            .error-message.show {
                display: block !important;
            }

            .form-actions {
                display: flex !important;
                gap: 12px !important;
                justify-content: flex-end !important;
                margin-top: 24px !important;
            }

            .btn {
                padding: 8px 16px !important;
                border: 1px solid #c9cdd4 !important;
                border-radius: 4px !important;
                font-size: 14px !important;
                cursor: pointer !important;
                transition: all 0.2s !important;
                background: white !important;
                box-sizing: border-box !important;
                display: inline-block !important;
                text-align: center !important;
                font-family: inherit !important;
            }

            .btn-primary {
                background: #3370ff !important;
                color: white !important;
                border-color: #3370ff !important;
            }

            .btn-primary:hover {
                background: #1e5eff !important;
                border-color: #1e5eff !important;
            }

            .btn-secondary {
                background: #f2f3f5 !important;
                color: #1f2329 !important;
                border-color: #c9cdd4 !important;
            }

            .btn-secondary:hover {
                background: #e5e6eb !important;
            }
        `;
        
        const style = document.createElement('style');
        style.textContent = cssText;
        this.shadowRoot.appendChild(style);
        console.log('CSS样式已添加到Shadow DOM，样式数量:', this.shadowRoot.querySelectorAll('style').length);
        console.log('Shadow DOM内容:', this.shadowRoot.innerHTML.substring(0, 200) + '...');
    }

    render() {
        this.shadowRoot.innerHTML = this.getInlineHTML();
    }

    getInlineHTML() {
        return `
            <div class="download-host" style="position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0, 0, 0, 0.5); display: none; z-index: 1000; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;">
                <div class="download-container" style="background: white; border-radius: 8px; box-shadow: 0 4px 20px rgba(0, 0, 0, 0.15); width: 500px; max-width: 90vw; max-height: 70vh; overflow-y: auto; position: absolute; top: 140px; left: 50%; transform: translateX(-50%); padding: 24px; box-sizing: border-box;">
                    <div class="download-header" style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 24px;">
                        <h3 class="download-title" style="margin: 0; font-size: 18px; font-weight: 600; color: #1f2329;">下载模型文件</h3>
                        <button class="close-btn" id="closeBtn" style="background: none; border: none; font-size: 24px; cursor: pointer; color: #646a73; padding: 0; width: 24px; height: 24px; display: flex; align-items: center; justify-content: center;">&times;</button>
                    </div>
                    <form id="downloadForm">
                        <div class="form-group" style="margin-bottom: 20px;">
                            <label class="form-label required" style="display: block; margin-bottom: 8px; font-size: 14px; font-weight: 500; color: #1f2329;"><span style="color: #f5222d; margin-right: 4px;">*</span>模型名称</label>
                            <select class="form-control form-select" id="modelName" required style="width: 100%; padding: 8px 12px; border: 1px solid #c9cdd4; border-radius: 4px; font-size: 14px; box-sizing: border-box; background: white; cursor: pointer;">
                                <option value="">请选择模型名称</option>
                            </select>
                            <div class="error-message" id="modelNameError" style="color: #f5222d; font-size: 12px; margin-top: 4px; display: none;">请选择模型名称</div>
                        </div>

                        <div class="form-group" style="margin-bottom: 20px;">
                            <label class="form-label required" style="display: block; margin-bottom: 8px; font-size: 14px; font-weight: 500; color: #1f2329;"><span style="color: #f5222d; margin-right: 4px;">*</span>版本号</label>
                            <select class="form-control form-select" id="modelVersion" required style="width: 100%; padding: 8px 12px; border: 1px solid #c9cdd4; border-radius: 4px; font-size: 14px; box-sizing: border-box; background: white; cursor: pointer;">
                                <option value="">请选择版本号</option>
                            </select>
                            <div class="error-message" id="modelVersionError" style="color: #f5222d; font-size: 12px; margin-top: 4px; display: none;">请选择版本号</div>
                        </div>

                        <div class="form-actions" style="display: flex; gap: 12px; justify-content: flex-end; margin-top: 24px;">
                            <button type="button" class="btn btn-secondary" id="cancelBtn" style="padding: 8px 16px; border: 1px solid #c9cdd4; border-radius: 4px; font-size: 14px; cursor: pointer; background: #f2f3f5; color: #1f2329; box-sizing: border-box; display: inline-block; text-align: center;">取消</button>
                            <button type="button" class="btn btn-primary" id="downloadBtn" style="padding: 8px 16px; border: 1px solid #3370ff; border-radius: 4px; font-size: 14px; cursor: pointer; background: #3370ff; color: white; box-sizing: border-box; display: inline-block; text-align: center;">确认下载</button>
                        </div>
                    </form>
                </div>
            </div>
        `;
    }

    bindEvents() {
        // 关闭按钮
        const closeBtn = this.shadowRoot.getElementById('closeBtn');
        if (closeBtn) {
            closeBtn.addEventListener('click', () => {
                this.hide();
            });
        }

        // 取消按钮
        const cancelBtn = this.shadowRoot.getElementById('cancelBtn');
        if (cancelBtn) {
            cancelBtn.addEventListener('click', () => {
                this.hide();
            });
        }

        // 下载按钮
        const downloadBtn = this.shadowRoot.getElementById('downloadBtn');
        if (downloadBtn) {
            downloadBtn.addEventListener('click', () => {
                this.download();
            });
        }

        // 模型名称变化事件
        const modelName = this.shadowRoot.getElementById('modelName');
        if (modelName) {
            modelName.addEventListener('change', () => {
                this.clearFieldError('modelName');
                this.loadVersions();
            });
        }

        // 版本号变化事件
        const modelVersion = this.shadowRoot.getElementById('modelVersion');
        if (modelVersion) {
            modelVersion.addEventListener('change', () => {
                this.clearFieldError('modelVersion');
            });
        }

        // ESC键关闭
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape' && this.style.display === 'block') {
                this.hide();
            }
        });
    }

    show(selectedModel = null) {
        console.log('ModelDownload show() 被调用');
        this.selectedModel = selectedModel;
        
        // 直接设置显示状态
        this.style.display = 'block';
        
        // 等待DOM更新后再显示弹窗
        setTimeout(() => {
            const downloadHost = this.shadowRoot.querySelector('.download-host');
            if (downloadHost) {
                downloadHost.style.display = 'block';
                console.log('弹窗已显示');
            } else {
                console.error('未找到download-host元素');
            }
        }, 50);
        
        this.resetForm();
        this.clearValidationErrors();
        this.loadModelNames();
        
        // 如果有选中的模型，自动设置
        if (selectedModel) {
            this.setSelectedModel(selectedModel);
        }
    }

    hide() {
        console.log('ModelDownload hide() 被调用');
        const downloadHost = this.shadowRoot.querySelector('.download-host');
        if (downloadHost) {
            downloadHost.style.display = 'none';
        }
        this.style.display = 'none';
        this.clearValidationErrors();
    }

    resetForm() {
        const modelName = this.shadowRoot.getElementById('modelName');
        const modelVersion = this.shadowRoot.getElementById('modelVersion');

        // 重置下拉选择框
        if (modelName) modelName.value = '';
        if (modelVersion) modelVersion.value = '';
    }

    loadModelNames() {
        const modelName = this.shadowRoot.getElementById('modelName');
        if (!modelName) return;
        
        // 获取右侧模型资产库的根节点
        const rightSidebarTree = document.querySelector('.right-sidebar .tree');
        if (!rightSidebarTree) {
            console.warn('未找到右侧模型资产库');
            return;
        }
        
        // 只获取直接子节点（根节点），不包含嵌套的子节点
        const rootNodes = Array.from(rightSidebarTree.children).filter(child => 
            child.classList.contains('tree-node')
        );
        
        const modelNames = [];
        
        rootNodes.forEach(node => {
            const span = node.querySelector('span');
            if (span) {
                const nodeName = span.textContent.trim();
                // 只添加不是版本号的节点（版本号格式为 v1.0.0）
                if (!nodeName.match(/^v\d+\.\d+\.\d+$/)) {
                    modelNames.push(nodeName);
                }
            }
        });
        
        console.log('获取到的模型名称:', modelNames);
        
        // 清空现有选项
        modelName.innerHTML = '<option value="">请选择模型名称</option>';
        
        // 添加模型名称选项
        modelNames.forEach(name => {
            const option = document.createElement('option');
            option.value = name;
            option.textContent = name;
            modelName.appendChild(option);
        });
    }

    loadVersions() {
        const modelName = this.shadowRoot.getElementById('modelName');
        const modelVersion = this.shadowRoot.getElementById('modelVersion');
        
        if (!modelName || !modelVersion) return;
        
        const selectedModelName = modelName.value;
        if (!selectedModelName) {
            modelVersion.innerHTML = '<option value="">请选择版本号</option>';
            return;
        }
        
        // 获取选中模型的版本号
        const rightSidebarTree = document.querySelector('.right-sidebar .tree');
        if (!rightSidebarTree) return;
        
        const rootNodes = rightSidebarTree.querySelectorAll('.tree-node');
        let versions = [];
        
        rootNodes.forEach(node => {
            const span = node.querySelector('span');
            if (span && span.textContent.trim() === selectedModelName) {
                // 查找子节点中的版本号
                const childrenContainer = node.querySelector('.tree-children');
                if (childrenContainer) {
                    const versionNodes = childrenContainer.querySelectorAll('.tree-node span');
                    versionNodes.forEach(versionSpan => {
                        const versionText = versionSpan.textContent.trim();
                        if (versionText.match(/^v\d+\.\d+\.\d+$/)) {
                            versions.push(versionText);
                        }
                    });
                }
            }
        });
        
        // 清空现有选项
        modelVersion.innerHTML = '<option value="">请选择版本号</option>';
        
        // 添加版本号选项
        versions.forEach(version => {
            const option = document.createElement('option');
            option.value = version;
            option.textContent = version;
            modelVersion.appendChild(option);
        });
    }

    setSelectedModel(selectedModel) {
        console.log('setSelectedModel 被调用，传入数据:', selectedModel);
        const modelName = this.shadowRoot.getElementById('modelName');
        const modelVersion = this.shadowRoot.getElementById('modelVersion');
        
        if (!modelName || !modelVersion || !selectedModel) {
            console.log('setSelectedModel: 缺少必要元素或数据');
            return;
        }
        
        // 设置模型名称
        modelName.value = selectedModel.name;
        console.log('设置模型名称:', selectedModel.name);
        
        // 触发版本号加载
        this.loadVersions();
        
        // 设置版本号
        if (selectedModel.version) {
            // 等待版本号加载完成后再设置
            setTimeout(() => {
                modelVersion.value = selectedModel.version;
                console.log('设置版本号:', selectedModel.version);
            }, 100);
        }
    }

    async download() {
        // 清除之前的错误状态
        this.clearValidationErrors();
        
        const formData = this.getFormData();
        
        let hasError = false;
        
        // 验证模型名称
        if (!formData.modelName) {
            this.showFieldError('modelName', '请选择模型名称');
            hasError = true;
        }
        
        // 验证版本号
        if (!formData.modelVersion) {
            this.showFieldError('modelVersion', '请选择版本号');
            hasError = true;
        }
        
        if (hasError) return;
        
        try {
            // 调用下载API
            const result = await this.apiCall('/api/models/download', {
                modelName: formData.modelName,
                version: formData.modelVersion
            });
            
            if (result.code === 200) {
                this.showMessage('下载成功', 'success');
                this.hide();
                
                // 触发下载成功事件
                this.dispatchEvent(new CustomEvent('download-success', {
                    detail: {
                        modelName: formData.modelName,
                        version: formData.modelVersion,
                        downloadUrl: result.data.downloadUrl
                    }
                }));
            } else {
                this.showMessage(result.message || '下载失败', 'error');
            }
        } catch (error) {
            console.error('下载模型文件失败:', error);
            this.showMessage('下载失败，请稍后重试', 'error');
        }
    }

    getFormData() {
        const modelName = this.shadowRoot.getElementById('modelName');
        const modelVersion = this.shadowRoot.getElementById('modelVersion');
        
        return {
            modelName: modelName ? modelName.value : '',
            modelVersion: modelVersion ? modelVersion.value : ''
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
    }

    clearFieldError(fieldId) {
        const field = this.shadowRoot.getElementById(fieldId);
        const errorElement = this.shadowRoot.getElementById(fieldId + 'Error');
        
        if (field) {
            field.classList.remove('error');
        }
        
        if (errorElement) {
            errorElement.classList.remove('show');
        }
    }

    clearValidationErrors() {
        this.clearFieldError('modelName');
        this.clearFieldError('modelVersion');
    }

    async apiCall(url, data) {
        const response = await fetch(url, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(data)
        });

        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }

        return await response.json();
    }

    showMessage(message, type = 'info') {
        const messageDiv = document.createElement('div');
        messageDiv.className = `message ${type}`;
        messageDiv.textContent = message;
        document.body.appendChild(messageDiv);

        setTimeout(() => {
            if (messageDiv.parentNode) {
                messageDiv.parentNode.removeChild(messageDiv);
            }
        }, 3000);
    }
}

customElements.define('model-download', ModelDownload);
