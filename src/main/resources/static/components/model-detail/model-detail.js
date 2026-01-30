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
    }

    show(modelInfo) {
        this.currentModel = modelInfo;
        this.setAttribute('show', '');
        this.updateContent(modelInfo);
    }

    hide() {
        this.removeAttribute('show');
    }

    updateContent(modelInfo) {
        const modelName = this.shadowRoot.getElementById('modelName');
        const modelVersion = this.shadowRoot.getElementById('modelVersion');
        const developer = this.shadowRoot.getElementById('developer');
        const scene = this.shadowRoot.getElementById('scene');
        const createTime = this.shadowRoot.getElementById('createTime');
        const modelDiagramName = this.shadowRoot.getElementById('modelDiagramName');
        
        if (modelName) modelName.textContent = modelInfo.name || '-';
        if (modelVersion) modelVersion.textContent = modelInfo.version || '-';
        if (developer) developer.textContent = '张三'; // 默认开发者
        if (scene) scene.textContent = '工业控制'; // 默认场景
        if (createTime) createTime.textContent = '2024-01-15 10:30:00'; // 默认创建时间
        if (modelDiagramName) modelDiagramName.textContent = modelInfo.name || 'Timer';
        
        // 更新版本历史
        this.updateVersionHistory(modelInfo);
        
        // 更新UML图数据
        this.updateUMLDiagram(modelInfo);
    }
    
    updateVersionHistory(modelInfo) {
        const timeline = this.shadowRoot.querySelector('.horizontal-timeline');
        if (timeline) {
            timeline.innerHTML = `
                <div class="timeline-item">
                    <div class="timeline-dot"></div>
                    <div class="timeline-content">
                        <div class="timeline-version">v0.9.0</div>
                        <div class="timeline-developer">李四</div>
                        <div class="timeline-date">2024-01-10</div>
                    </div>
                </div>
                <div class="timeline-item">
                    <div class="timeline-dot"></div>
                    <div class="timeline-content">
                        <div class="timeline-version">v1.0.0</div>
                        <div class="timeline-developer">张三</div>
                        <div class="timeline-date">2024-01-15</div>
                    </div>
                </div>
                <div class="timeline-item">
                    <div class="timeline-dot"></div>
                    <div class="timeline-content">
                        <div class="timeline-version">${modelInfo.version || 'v1.0.1'}</div>
                        <div class="timeline-developer">张三</div>
                        <div class="timeline-date">2024-01-20</div>
                    </div>
                </div>
            `;
        }
    }
    
    updateUMLDiagram(modelInfo) {
        const modelDiagramName = this.shadowRoot.getElementById('modelDiagramName');
        const modelDiagramVersion = this.shadowRoot.getElementById('modelDiagramVersion');
        
        if (modelDiagramName) modelDiagramName.textContent = modelInfo.name || 'Timer';
        if (modelDiagramVersion) modelDiagramVersion.textContent = modelInfo.version || 'v1.0.1';
        
        // 这里可以根据实际模型类型动态设置Inputs和Outputs的参数列表
        // 目前使用静态数据
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
        
        // 显示编辑对话框
        const modelEdit = document.getElementById('modelEdit');
        if (modelEdit) {
            modelEdit.show(this.currentModel);
        } else {
            console.error('未找到modelEdit组件');
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
            
            // 调用删除API，只删除当前版本
            const response = await fetch('/api/models/delete', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({
                    modelName: this.currentModel.name,
                    version: version // 使用页面中的版本信息
                })
            });
            
            if (response.ok) {
                const result = await response.json();
                console.log('删除响应:', result);
                
                if (result.code === 200) {
                    // 显示成功消息
                    this.showSuccessMessage(`模型版本 "${version}" 删除成功`);
                    
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
        // 创建成功消息
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
    
    showErrorMessage(message) {
        // 创建错误消息
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

customElements.define('model-detail', ModelDetail);
