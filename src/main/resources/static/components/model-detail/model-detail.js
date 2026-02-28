class ModelDetail extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });
        this.currentModel = null;
    }

    async connectedCallback() {
        await this.loadResources();
        this.render();
        this.bindEvents();
    }

    async loadResources() {
        // 加载CSS
        try {
            const cssLink = document.createElement('link');
            cssLink.rel = 'stylesheet';
            cssLink.href = './components/model-detail/model-detail.css';
            this.shadowRoot.appendChild(cssLink);
        } catch (error) {
            console.error('Failed to load CSS:', error);
        }

        // 加载HTML模板
        try {
            const response = await fetch('./components/model-detail/model-detail.html');
            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }
            const html = await response.text();
            this.shadowRoot.innerHTML += html;
            console.log('Model detail HTML template loaded successfully');
        } catch (error) {
            console.error('Failed to load HTML template:', error);
            this.shadowRoot.innerHTML += this.getFallbackHTML();
        }
    }

    getFallbackHTML() {
        return `
            <div class="model-detail">
                <div class="model-info-card">
                    <div class="info-header">基本信息及历史版本变更记录</div>
                    <div class="info-content">
                        <div class="basic-info">
                            <div class="info-title">基本信息</div>
                            <div class="info-table">
                                <div class="info-row">
                                    <div class="info-key">模型名称</div>
                                    <div class="info-value" id="modelName">-</div>
                                </div>
                            </div>
                        </div>
                        <div class="version-history">
                            <div class="info-title">历史版本变更记录</div>
                            <div class="version-timeline">
                                <div class="timeline-item">
                                    <div class="timeline-dot"></div>
                                    <div class="timeline-content">
                                        <div class="timeline-version">v1.0.0</div>
                                        <div class="timeline-date">2024-01-15</div>
                                        <div class="timeline-desc">初始版本</div>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        `;
    }

    render() {
        // HTML已通过loadResources加载
    }

    bindEvents() {
        // 绑定事件
        const downloadBtn = this.shadowRoot.getElementById('downloadBtn');
        const editBtn = this.shadowRoot.getElementById('editBtn');
        const deleteBtn = this.shadowRoot.getElementById('deleteBtn');
        const editButton = this.shadowRoot.querySelector('.edit-button');
        const deleteButton = this.shadowRoot.querySelector('.delete-button');
        
        if (downloadBtn) {
            downloadBtn.addEventListener('click', () => this.download());
        }
        
        if (editBtn) {
            editBtn.addEventListener('click', () => this.edit());
        }
        
        if (deleteBtn) {
            deleteBtn.addEventListener('click', () => this.deleteModel());
        }
        
        if (editButton) {
            editButton.addEventListener('click', () => this.edit());
        }
        
        if (deleteButton) {
            deleteButton.addEventListener('click', () => this.deleteModel());
        }
        
        // 监听模型更新事件
        document.addEventListener('model-updated', (e) => {
            if (this.currentModel && 
                e.detail.modelName === this.currentModel.name && 
                e.detail.version === this.currentModel.version) {
                // 刷新当前模型详情数据
                console.log('模型详情页面收到更新事件，刷新数据');
                this.loadModelData(this.currentModel);
            }
        });
    }

    show(modelInfo) {
        this.currentModel = modelInfo;
        this.setAttribute('show', '');
        // 调用接口获取模型元数据
        this.loadModelData(modelInfo);
    }

    async loadModelData(modelInfo) {
        try {
            // 调用接口获取元数据
            const response = await fetch(`/api/model/metas?name=${encodeURIComponent(modelInfo.name)}&version=${encodeURIComponent(modelInfo.version)}`);
            
            if (response.ok) {
                const result = await response.json();
                if (result.code === 200 && result.data) {
                    const meta = result.data;
                    console.log('获取模型元数据成功:', meta);
                    // 保存完整的接口数据
                    this.currentModelMeta = meta;
                    this.updateContent(meta);
                } else {
                    console.error('获取元数据失败:', result.message);
                    this.showErrorMessage('获取模型信息失败');
                }
            } else {
                throw new Error(`HTTP error! status: ${response.status}`);
            }
        } catch (error) {
            console.error('加载模型数据失败:', error);
            // 如果接口失败，使用默认值
            this.updateContent(modelInfo);
        }
    }

    hide() {
        this.removeAttribute('show');
    }

    updateContent(modelInfo) {
        // 渲染基本信息到basic-info-section，完全使用接口数据
        const modelName = this.shadowRoot.getElementById('modelName');
        const modelVersion = this.shadowRoot.getElementById('modelVersion');
        const developer = this.shadowRoot.getElementById('developer');
        const scene = this.shadowRoot.getElementById('scene');
        const createTime = this.shadowRoot.getElementById('createTime');
        
        if (modelName) modelName.textContent = modelInfo.name || '-';
        if (modelVersion) modelVersion.textContent = modelInfo.version || '-';
        if (developer) developer.textContent = modelInfo.author || '-';
        if (scene) scene.textContent = modelInfo.scene || '-';
        if (createTime) {
            if (modelInfo.timestamp) {
                // 将时间戳转换为日期格式
                const date = new Date(modelInfo.timestamp);
                createTime.textContent = date.toLocaleString('zh-CN', {
                    year: 'numeric',
                    month: '2-digit',
                    day: '2-digit',
                    hour: '2-digit',
                    minute: '2-digit',
                    second: '2-digit'
                });
            } else {
                createTime.textContent = '-';
            }
        }
        
        // 更新版本历史
        this.updateVersionHistory(modelInfo);
        
        // 更新UML图数据
        this.updateUMLDiagram(modelInfo);
    }
    
    updateVersionHistory(modelInfo) {
        // 调用接口获取版本历史数据
        this.loadVersionHistory(modelInfo);
    }

    async loadVersionHistory(modelInfo) {
        try {
            // 调用接口获取版本历史
            const response = await fetch(`/api/model/history?name=${encodeURIComponent(modelInfo.name)}`);
            
            if (response.ok) {
                const result = await response.json();
                if (result.code === 200 && result.data) {
                    const historyData = result.data;
                    console.log('获取版本历史成功:', historyData);
                    this.renderVersionHistory(historyData);
                } else {
                    console.error('获取版本历史失败:', result.message);
                    this.renderVersionHistory([]);
                }
            } else {
                throw new Error(`HTTP error! status: ${response.status}`);
            }
        } catch (error) {
            console.error('加载版本历史失败:', error);
            // 如果接口失败，显示空的历史
            this.renderVersionHistory([]);
        }
    }

    renderVersionHistory(historyData) {
        const timeline = this.shadowRoot.querySelector('.horizontal-timeline');
        if (!timeline) return;
        
        // 如果没有历史数据，显示空提示
        if (!historyData || historyData.length === 0) {
            timeline.innerHTML = `
                <div class="timeline-item empty-history">
                    <div class="timeline-content">
                        <div class="empty-message">暂无版本历史</div>
                    </div>
                </div>
            `;
            return;
        }
        
        // 渲染版本历史
        timeline.innerHTML = historyData.map(item => `
            <div class="timeline-item">
                <div class="timeline-dot"></div>
                <div class="timeline-content">
                    <div class="timeline-version">${item.version || '-'}</div>
                    <div class="timeline-developer">${item.author || '-'}</div>
                    <div class="timeline-date">${this.formatDate(item.timestamp)}</div>
                </div>
            </div>
        `).join('');
    }

    formatDate(timestamp) {
        if (!timestamp) return '-';
        try {
            const date = new Date(timestamp);
            return date.toLocaleString('zh-CN', {
                year: 'numeric',
                month: '2-digit',
                day: '2-digit',
                hour: '2-digit',
                minute: '2-digit',
                second: '2-digit'
            });
        } catch (error) {
            console.error('日期格式化失败:', error);
            return '-';
        }
    }
    
    updateUMLDiagram(modelInfo) {
        const modelDiagramName = this.shadowRoot.getElementById('modelDiagramName');
        const modelDiagramVersion = this.shadowRoot.getElementById('modelDiagramVersion');
        
        if (modelDiagramName) modelDiagramName.textContent = modelInfo.name || 'Timer';
        if (modelDiagramVersion) modelDiagramVersion.textContent = modelInfo.version || 'v1.0.1';
        
        // 动态渲染inputs参数表格
        this.renderParamsTable('inputs', modelInfo.inputs);
        
        // 动态渲染outputs参数表格
        this.renderParamsTable('outputs', modelInfo.outputs);
    }

    renderParamsTable(type, paramsData) {
        // 找到对应的params-table
        const container = this.shadowRoot.querySelector(`.${type}-container`);
        if (!container) return;
        
        const paramsBody = container.querySelector('.params-body');
        if (!paramsBody) return;
        
        // 清空现有内容
        paramsBody.innerHTML = '';
        
        // 解析参数数据
        let params = [];
        if (paramsData) {
            try {
                params = typeof paramsData === 'string' ? JSON.parse(paramsData) : paramsData;
            } catch (error) {
                console.error(`解析${type}参数数据失败:`, error);
                return;
            }
        }
        
        // 如果没有参数，显示空提示
        if (!params || params.length === 0) {
            paramsBody.innerHTML = `
                <div class="param-row empty-row">
                    <div class="param-col param-name" colspan="4">暂无${type === 'inputs' ? '输入' : '输出'}参数</div>
                </div>
            `;
            return;
        }
        
        // 渲染参数行
        params.forEach(param => {
            const row = document.createElement('div');
            row.className = 'param-row';
            row.innerHTML = `
                <div class="param-col param-name">${param.name || '-'}</div>
                <div class="param-col param-type">${param.type || '-'}</div>
                <div class="param-col param-unit">${param.unit || '-'}</div>
                <div class="param-col param-desc">${param.desc || '-'}</div>
            `;
            paramsBody.appendChild(row);
        });
    }

    download() {
        console.log('下载模型:', this.currentModel);
        // 调用下载功能
    }

    edit() {
        if (!this.currentModel) {
            console.warn('没有选中的模型');
            return;
        }
        
        // 显示编辑对话框，传递当前模型数据和完整的接口数据
        const modelEdit = document.getElementById('modelEdit');
        if (modelEdit && modelEdit.showWithModelData) {
            modelEdit.showWithModelData(this.currentModel, this.currentModelMeta || this.currentModel);
        } else {
            console.error('未找到modelEdit组件或showWithModelData方法');
        }
    }

    deleteModel() {
        if (!this.currentModel) {
            console.warn('没有选中的模型');
            return;
        }
        
        // 显示确认对话框
        this.showDeleteConfirmDialog();
    }
    
    showDeleteConfirmDialog() {
        const modelName = this.currentModel.name || '未知模型';
        
        // 从页面内容获取版本信息
        const versionElement = this.shadowRoot.getElementById('modelVersion');
        const version = versionElement ? versionElement.textContent.trim() : '未知版本';
        
        // 创建确认对话框
        const dialogHtml = `
            <div class="delete-confirm-dialog-overlay" style="
                position: fixed;
                top: 0;
                left: 0;
                width: 100%;
                height: 100%;
                background: rgba(0, 0, 0, 0.5);
                display: flex;
                justify-content: center;
                align-items: center;
                z-index: 10000;
            ">
                <div class="delete-confirm-dialog" style="
                    background: white;
                    border-radius: 8px;
                    padding: 24px;
                    max-width: 400px;
                    width: 90%;
                    box-shadow: 0 10px 25px rgba(0, 0, 0, 0.2);
                ">
                    <div class="dialog-header" style="
                        margin-bottom: 16px;
                        font-size: 18px;
                        font-weight: 600;
                        color: #1f2937;
                    ">
                        确认删除
                    </div>
                    <div class="dialog-content" style="
                        margin-bottom: 24px;
                        color: #6b7280;
                        line-height: 1.5;
                    ">
                        确定要删除模型 <strong>${modelName}</strong> 的版本 <strong>${version}</strong> 吗？<br>
                        删除后无法恢复，请谨慎操作。
                    </div>
                    <div class="dialog-buttons" style="
                        display: flex;
                        gap: 12px;
                        justify-content: flex-end;
                    ">
                        <button class="cancel-btn" style="
                            padding: 8px 16px;
                            border: 1px solid #d1d5db;
                            background: white;
                            color: #6b7280;
                            border-radius: 4px;
                            cursor: pointer;
                        ">取消</button>
                        <button class="confirm-btn" style="
                            padding: 8px 16px;
                            border: none;
                            background: #dc2626;
                            color: white;
                            border-radius: 4px;
                            cursor: pointer;
                        ">确认删除</button>
                    </div>
                </div>
            </div>
        `;
        
        // 添加到页面
        document.body.insertAdjacentHTML('beforeend', dialogHtml);
        
        const overlay = document.querySelector('.delete-confirm-dialog-overlay');
        const cancelBtn = overlay.querySelector('.cancel-btn');
        const confirmBtn = overlay.querySelector('.confirm-btn');
        
        // 绑定事件
        const closeDialog = () => {
            overlay.remove();
        };
        
        cancelBtn.addEventListener('click', closeDialog);
        confirmBtn.addEventListener('click', () => {
            this.performDelete();
            closeDialog();
        });
        
        overlay.addEventListener('click', (e) => {
            if (e.target === overlay) {
                closeDialog();
            }
        });
        
        // ESC键关闭
        const handleEsc = (e) => {
            if (e.key === 'Escape') {
                closeDialog();
                document.removeEventListener('keydown', handleEsc);
            }
        };
        document.addEventListener('keydown', handleEsc);
    }
    
    async performDelete() {
        try {
            console.log('删除模型版本:', this.currentModel);
            
            // 从页面内容获取版本信息
            const versionElement = this.shadowRoot.getElementById('modelVersion');
            const version = versionElement ? versionElement.textContent.trim() : null;
            
            if (!version) {
                this.showErrorMessage('无法获取模型版本信息');
                return;
            }
            
            // 构建查询参数
            const params = new URLSearchParams({
                name: this.currentModel.name,
                version: version
            });
            
            // 调用删除API - 使用DELETE方法和正确的参数格式
            const response = await fetch(`/api/model/delete?${params.toString()}`, {
                method: 'DELETE',
                headers: {
                    'Content-Type': 'application/json'
                }
            });
            
            if (response.ok) {
                const result = await response.json();
                console.log('删除响应:', result);
                
                if (result.code === 200) {
                    // 显示成功消息
                    this.showSuccessMessage(`模型版本 "${version}" 删除成功`);
                    
                    // 重新加载右侧模型资产库
                    console.log('🔄 模型删除成功，准备调用 loadDataSourceTree');
                    if (window.loadDataSourceTree) {
                        console.log('🔄 调用 window.loadDataSourceTree');
                        window.loadDataSourceTree();
                    } else {
                        console.error('❌ window.loadDataSourceTree 不存在');
                    }
                    
                    // 从右侧树中移除该版本节点
                    this.removeVersionFromTree({ ...this.currentModel, version });
                    
                    // 隐藏模型详情
                    this.hide();
                } else {
                    this.showErrorMessage(result.message || '删除失败');
                }
            } else {
                throw new Error(`HTTP error! status: ${response.status}`);
            }
        } catch (error) {
            console.error('删除模型版本失败:', error);
            this.showErrorMessage('删除失败，请稍后重试');
        }
    }
    
    removeVersionFromTree(selectedModel) {
        const rightSidebarTree = document.querySelector('.right-sidebar .tree');
        if (!rightSidebarTree) return;
        
        const allNodes = rightSidebarTree.querySelectorAll('.tree-node');
        
        allNodes.forEach(node => {
            const span = node.querySelector('span');
            if (span && span.textContent.trim() === selectedModel.version) {
                node.remove();
            }
        });
    }
    
    showSuccessMessage(message) {
        if (window.CommonUtils && window.CommonUtils.showToast) {
            window.CommonUtils.showToast(message, 'success');
        } else {
            // 回退到原有的实现
            const messageHtml = `
                <div class="workspace-message success" style="
                    position: fixed;
                    top: 20px;
                    right: 20px;
                    background: #10b981;
                    color: white;
                    padding: 12px 20px;
                    border-radius: 4px;
                    box-shadow: 0 4px 12px rgba(16, 185, 129, 0.3);
                    z-index: 10001;
                    animation: slideIn 0.3s ease-out;
                ">
                    ${message}
                </div>
            `;
            
            document.body.insertAdjacentHTML('beforeend', messageHtml);
            
            const messageEl = document.querySelector('.workspace-message.success');
            setTimeout(() => {
                if (messageEl) messageEl.remove();
            }, 3000);
        }
    }
    
    showErrorMessage(message) {
        if (window.CommonUtils && window.CommonUtils.showToast) {
            window.CommonUtils.showToast(message, 'error');
        } else {
            // 回退到原有的实现
            const messageHtml = `
                <div class="workspace-message error" style="
                    position: fixed;
                    top: 20px;
                    right: 20px;
                    background: #ef4444;
                    color: white;
                    padding: 12px 20px;
                    border-radius: 4px;
                    box-shadow: 0 4px 12px rgba(239, 68, 68, 0.3);
                    z-index: 10001;
                    animation: slideIn 0.3s ease-out;
                ">
                    ${message}
                </div>
            `;
            
            document.body.insertAdjacentHTML('beforeend', messageHtml);
            
            const messageEl = document.querySelector('.workspace-message.error');
            setTimeout(() => {
                if (messageEl) messageEl.remove();
            }, 3000);
        }
    }
}

customElements.define('model-detail', ModelDetail);
