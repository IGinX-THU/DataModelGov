class AlgorithmDetail extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });
        this.currentAlgorithm = null;
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
            cssLink.href = './components/algorithm-detail/algorithm-detail.css';
            this.shadowRoot.appendChild(cssLink);
        } catch (error) {
            console.error('Failed to load CSS:', error);
        }

        // 加载HTML模板
        try {
            const response = await fetch('./components/algorithm-detail/algorithm-detail.html');
            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }
            const html = await response.text();
            this.shadowRoot.innerHTML += html;
            console.log('Algorithm detail HTML template loaded successfully');
        } catch (error) {
            console.error('Failed to load HTML template:', error);
            this.shadowRoot.innerHTML += this.getFallbackHTML();
        }
    }

    getFallbackHTML() {
        return `
            <div class="algorithm-detail">
                <div class="algorithm-info-card">
                    <div class="info-header">基本信息及历史版本变更记录</div>
                    <div class="info-content">
                        <div class="basic-info">
                            <div class="info-title">基本信息</div>
                            <div class="info-table">
                                <div class="info-row">
                                    <div class="info-key">算法名称</div>
                                    <div class="info-value" id="algorithmName">-</div>
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
        const backBtn = this.shadowRoot.getElementById('backBtn');
        const closeBtn = this.shadowRoot.getElementById('closeBtn');
        const downloadBtn = this.shadowRoot.getElementById('downloadBtn');
        const editBtn = this.shadowRoot.getElementById('editBtn');
        const deleteBtn = this.shadowRoot.getElementById('deleteBtn');
        const editButton = this.shadowRoot.querySelector('.edit-button');
        const deleteButton = this.shadowRoot.querySelector('.delete-button');

        if (backBtn) {
            backBtn.addEventListener('click', () => {
                this.hide();
                const algorithmArchiveList = document.getElementById('algorithmArchiveList');
                if (algorithmArchiveList && algorithmArchiveList.show) {
                    algorithmArchiveList.show();
                }
            });
        }

        if (closeBtn) {
            closeBtn.addEventListener('click', () => {
                this.hide();
            });
        }
        
        if (downloadBtn) {
            downloadBtn.addEventListener('click', () => this.download());
        }
        
        if (editBtn) {
            editBtn.addEventListener('click', () => this.edit());
        }
        
        if (deleteBtn) {
            deleteBtn.addEventListener('click', () => this.deleteAlgorithm());
        }
        
        if (editButton) {
            editButton.addEventListener('click', () => this.edit());
        }
        
        if (deleteButton) {
            deleteButton.addEventListener('click', () => this.deleteAlgorithm());
        }

        // 绑定关联规则按钮事件
        const viewAllAssociationsBtn = this.shadowRoot.getElementById('viewAllAssociations');
        if (viewAllAssociationsBtn) {
            viewAllAssociationsBtn.addEventListener('click', () => this.viewAllAssociations());
        }
        
        // 绑定关联规则跳转按钮事件（使用事件委托）
        this.shadowRoot.addEventListener('click', (e) => {
            if (e.target.classList.contains('association-link-btn')) {
                const ruleName = e.target.dataset.ruleName;
                this.navigateToRule(ruleName);
            }
        });
        
        // 监听算法更新事件
        document.addEventListener('algorithm-updated', (e) => {
            if (this.currentAlgorithm && 
                e.detail.algorithmName === this.currentAlgorithm.name && 
                e.detail.version === this.currentAlgorithm.version) {
                // 刷新当前算法详情数据
                console.log('算法详情页面收到更新事件，刷新数据');
                this.loadAlgorithmData(this.currentAlgorithm);
            }
        });
    }

    show(algorithmInfo) {
        this.currentAlgorithm = algorithmInfo;
        this.setAttribute('show', '');
        // 调用接口获取算法元数据
        this.loadAlgorithmData(algorithmInfo);
    }

    async loadAlgorithmData(algorithmInfo) {
        try {
            // 显示全局loading
            if (window.showGlobalLoading) {
                window.showGlobalLoading('正在加载算法信息...');
            }

            // 使用新的API配置
            const result = await window.AppConfig.get('algorithm', 'metas', {
                name: algorithmInfo.name,
                version: algorithmInfo.version
            });

            if (result.success && result.data) {
                const meta = result.data;
                console.log('获取算法元数据成功:', meta);
                // 保存完整的接口数据
                this.currentAlgorithmMeta = meta;
                this.updateContent(meta);
            } else {
                console.error('获取元数据失败:', result.message);
                this.showErrorMessage('获取算法信息失败');
            }
        } catch (error) {
            console.error('加载算法数据失败:', error);
            // 如果接口失败，使用默认值
            this.updateContent(algorithmInfo);
        } finally {
            // 隐藏全局loading
            if (window.hideGlobalLoading) {
                window.hideGlobalLoading();
            }
        }
    }

    hide() {
        this.removeAttribute('show');
    }

    updateContent(algorithmInfo) {
        // 渲染基本信息到basic-info-section，完全使用接口数据
        const algorithmName = this.shadowRoot.getElementById('algorithmName');
        const algorithmVersion = this.shadowRoot.getElementById('algorithmVersion');
        const developer = this.shadowRoot.getElementById('developer');
        const scene = this.shadowRoot.getElementById('scene');
        const createTime = this.shadowRoot.getElementById('createTime');
        
        if (algorithmName) algorithmName.textContent = algorithmInfo.name || '-';
        if (algorithmVersion) algorithmVersion.textContent = algorithmInfo.version || '-';
        if (developer) developer.textContent = algorithmInfo.author || '-';
        if (scene) scene.textContent = algorithmInfo.scene || '-';
        if (createTime) {
            if (algorithmInfo.timestamp) {
                // 将时间戳转换为日期格式
                const date = new Date(algorithmInfo.timestamp);
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

        // 填充档案描述字段
        const projectName = this.shadowRoot.getElementById('projectName');
        const description = this.shadowRoot.getElementById('description');

        if (projectName) projectName.textContent = algorithmInfo.projectName || '-';
        if (description) description.textContent = algorithmInfo.description || '-';
        
        // 渲染输出格式预览
        this.renderOutputFormatPreview(algorithmInfo);

        // 更新版本历史
        this.updateVersionHistory(algorithmInfo);
        
        // 更新UML图数据
        this.updateUMLDiagram(algorithmInfo);
        
        // 加载数据绑定信息
        this.loadBindingData(algorithmInfo);
    }
    
    renderOutputFormatPreview(algorithmInfo) {
        const previewEl = this.shadowRoot.getElementById('outputFormatPreview');
        if (!previewEl) return;

        // 从输出参数的回写目标生成CSV表头
        let outputs = [];
        if (algorithmInfo.outputs) {
            try {
                outputs = typeof algorithmInfo.outputs === 'string' ? JSON.parse(algorithmInfo.outputs) : algorithmInfo.outputs;
            } catch (e) { outputs = []; }
        }

        const headers = outputs.map(o => o.bindTarget || o.name || '').filter(h => h);

        if (headers.length === 0) {
            previewEl.innerHTML = '<pre>暂无输出格式</pre>';
            return;
        }

        // 生成CSV表头
        const csvHeader = headers.join(',');

        // 生成模拟数据行（3行）
        const mockRows = [];
        for (let i = 0; i < 3; i++) {
            const row = headers.map(header => {
                // 根据数据类型生成模拟值
                const output = outputs.find(o => (o.bindTarget || o.name) === header);
                if (!output) return '';

                const type = (output.type || 'string').toLowerCase();
                switch (type) {
                    case 'int':
                    case 'integer':
                        return Math.floor(Math.random() * 100);
                    case 'float':
                    case 'double':
                        return (Math.random() * 100).toFixed(2);
                    case 'bool':
                    case 'boolean':
                        return Math.random() > 0.5 ? 'true' : 'false';
                    default:
                        return `sample_${i + 1}`;
                }
            });
            mockRows.push(row.join(','));
        }

        const csvContent = csvHeader + '\n' + mockRows.join('\n');
        previewEl.innerHTML = `<pre>${csvContent}</pre>`;
    }

    updateVersionHistory(algorithmInfo) {
        // 调用接口获取版本历史数据
        this.loadVersionHistory(algorithmInfo);
    }

    async loadVersionHistory(algorithmInfo) {
        try {
            // 显示全局loading
            if (window.showGlobalLoading) {
                window.showGlobalLoading('正在加载版本历史...');
            }

            // 使用新的API配置
            const result = await window.AppConfig.get('algorithm', 'history', { name: algorithmInfo.name });

            if (result.success && result.data) {
                const historyData = result.data;
                console.log('获取版本历史成功:', historyData);
                this.renderVersionHistory(historyData);
            } else {
                console.error('获取版本历史失败:', result.message);
                this.renderVersionHistory([]);
            }
        } catch (error) {
            console.error('加载版本历史失败:', error);
            // 如果接口失败，显示空的历史
            this.renderVersionHistory([]);
        } finally {
            // 隐藏全局loading
            if (window.hideGlobalLoading) {
                window.hideGlobalLoading();
            }
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
    
    updateUMLDiagram(algorithmInfo) {
        const algorithmDiagramName = this.shadowRoot.getElementById('algorithmDiagramName');
        const algorithmDiagramVersion = this.shadowRoot.getElementById('algorithmDiagramVersion');
        
        if (algorithmDiagramName) algorithmDiagramName.textContent = algorithmInfo.name || 'Timer';
        if (algorithmDiagramVersion) algorithmDiagramVersion.textContent = algorithmInfo.version || 'v1.0.1';
        
        // 动态渲染inputs参数表格
        this.renderParamsTable('inputs', algorithmInfo.inputs);
        
        // 动态渲染outputs参数表格
        this.renderParamsTable('outputs', algorithmInfo.outputs);
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
        console.log('下载算法:', this.currentAlgorithm);
        // 调用下载功能
    }

    edit() {
        if (!this.currentAlgorithm) {
            console.warn('没有选中的算法');
            return;
        }
        
        // 显示编辑对话框，传递当前算法数据和完整的接口数据
        const algorithmEdit = document.getElementById('algorithmEdit');
        if (algorithmEdit && algorithmEdit.showWithAlgorithmData) {
            algorithmEdit.showWithAlgorithmData(this.currentAlgorithm, this.currentAlgorithmMeta || this.currentAlgorithm);
        } else {
            console.error('未找到algorithmEdit组件或showWithAlgorithmData方法');
        }
    }

    deleteAlgorithm() {
        if (!this.currentAlgorithm) {
            console.warn('没有选中的算法');
            return;
        }
        
        // 显示确认对话框
        this.showDeleteConfirmDialog();
    }
    
    showDeleteConfirmDialog() {
        const algorithmName = this.currentAlgorithm.name || '未知算法';
        
        // 从页面内容获取版本信息
        const versionElement = this.shadowRoot.getElementById('algorithmVersion');
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
                        确定要删除算法 <strong>${algorithmName}</strong> 的版本 <strong>${version}</strong> 吗？<br>
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
        
        // 移除点击遮罩关闭功能，避免误操作
        // overlay.addEventListener('click', (e) => {
        //     if (e.target === overlay) {
        //         closeDialog();
        //     }
        // });
        
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
            console.log('删除算法版本:', this.currentAlgorithm);
            
            // 从页面内容获取版本信息
            const versionElement = this.shadowRoot.getElementById('algorithmVersion');
            const version = versionElement ? versionElement.textContent.trim() : null;
            
            if (!version) {
                this.showErrorMessage('无法获取算法版本信息');
                return;
            }
            
            // 构建查询参数
            const params = new URLSearchParams({
                name: this.currentAlgorithm.name,
                version: version
            });
            
            // 使用新的API配置
            const result = await window.AppConfig.delete('algorithm', 'delete', {
                name: this.currentAlgorithm.name,
                version: version
            });
            
            console.log('删除响应:', result);
            
            if (result.success) {
                // 显示成功消息
                this.showSuccessMessage(`算法版本 "${version}" 删除成功`);
                
                // 重新加载右侧算法资产库
                console.log('🔄 算法删除成功，准备调用 loadDataSourceTree');
                if (window.loadDataSourceTree) {
                    console.log('🔄 调用 window.loadDataSourceTree');
                    window.loadDataSourceTree();
                } else {
                    console.error('❌ window.loadDataSourceTree 不存在');
                }
                
                // 从右侧树中移除该版本节点
                this.removeVersionFromTree({ ...this.currentAlgorithm, version });
                
                // 隐藏算法详情
                this.hide();
            } else {
                this.showErrorMessage(result.message || '删除失败');
            }
        } catch (error) {
            console.error('删除算法版本失败:', error);
            this.showErrorMessage('删除失败，请稍后重试');
        }
    }
    
    removeVersionFromTree(selectedAlgorithm) {
        const rightSidebarTree = document.querySelector('.right-sidebar .tree');
        if (!rightSidebarTree) return;
        
        const allNodes = rightSidebarTree.querySelectorAll('.tree-node');
        
        allNodes.forEach(node => {
            const span = node.querySelector('span');
            if (span && span.textContent.trim() === selectedAlgorithm.version) {
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

    async loadBindingData(algorithmInfo) {
        try {
            if (window.showGlobalLoading) {
                window.showGlobalLoading('正在加载数据绑定...');
            }

            // 从算法元数据API加载绑定数据
            const result = await window.AppConfig.get('algorithm', 'metas', {
                name: algorithmInfo.name,
                version: algorithmInfo.version
            });

            if (result.success && result.data) {
                this.renderBindingData(result.data);
            } else {
                this.renderBindingData({});
            }
        } catch (error) {
            console.error('加载数据绑定失败:', error);
            this.renderBindingData({});
        } finally {
            if (window.hideGlobalLoading) {
                window.hideGlobalLoading();
            }
        }
    }

    renderBindingData(algorithmData) {
        // 填充基本绑定信息
        const ids = {
            detailDataSource: algorithmData?.tableName || '-',
            detailCmd: algorithmData?.cmd || '-',
            detailInputCsv: algorithmData?.inputCsvName || '-',
            detailOutputCsv: algorithmData?.outputCsvName || '-',
            detailOutputTable: algorithmData?.outputTable || '-'
        };
        Object.entries(ids).forEach(([id, value]) => {
            const el = this.shadowRoot.getElementById(id);
            if (el) el.textContent = value;
        });

        // 渲染模型绑定列表
        const modelBindEl = this.shadowRoot.getElementById('detailModelBindings');
        if (modelBindEl) {
            const header = modelBindEl.querySelector('.binding-mapping-header');
            modelBindEl.innerHTML = '';
            if (header) modelBindEl.appendChild(header);
            
            let modelBindings = [];
            if (algorithmData?.calledModels) {
                try {
                    modelBindings = typeof algorithmData.calledModels === 'string'
                        ? JSON.parse(algorithmData.calledModels)
                        : algorithmData.calledModels;
                } catch (e) { modelBindings = []; }
            }
            
            if (!modelBindings || modelBindings.length === 0) {
                const empty = document.createElement('div');
                empty.className = 'binding-mapping-row binding-mapping-empty';
                empty.innerHTML = '<span>暂无绑定模型</span>';
                modelBindEl.appendChild(empty);
            } else {
                modelBindings.forEach(binding => {
                    const row = document.createElement('div');
                    row.className = 'binding-mapping-row binding-model-row';
                    row.innerHTML = `<span>${binding.modelName || '-'}</span><span>${binding.version || '-'}</span><span>${binding.storagePath || '-'}</span>`;
                    modelBindEl.appendChild(row);
                });
            }
        }

        // 渲染数据源字段全路径
        const inputFieldPathsEl = this.shadowRoot.getElementById('detailInputFieldPaths');
        if (inputFieldPathsEl) {
            let fieldPaths = [];
            if (algorithmData?.inputData) {
                try {
                    fieldPaths = typeof algorithmData.inputData === 'string'
                        ? JSON.parse(algorithmData.inputData)
                        : algorithmData.inputData;
                } catch (e) { fieldPaths = []; }
            }
            const header = inputFieldPathsEl.querySelector('.binding-mapping-header');
            inputFieldPathsEl.innerHTML = '';
            if (header) inputFieldPathsEl.appendChild(header);
            if (!fieldPaths || fieldPaths.length === 0) {
                const empty = document.createElement('div');
                empty.className = 'binding-mapping-row binding-mapping-empty';
                empty.innerHTML = '<span>暂无数据源字段</span>';
                inputFieldPathsEl.appendChild(empty);
            } else {
                fieldPaths.forEach(path => {
                    const row = document.createElement('div');
                    row.className = 'binding-mapping-row';
                    row.innerHTML = `<span>${path || '-'}</span>`;
                    inputFieldPathsEl.appendChild(row);
                });
            }
        }

        // 渲染输入映射
        const inputMappingsEl = this.shadowRoot.getElementById('detailInputMappings');
        if (inputMappingsEl) {
            let mappings = [];
            if (algorithmData?.inputsBind) {
                try {
                    mappings = typeof algorithmData.inputsBind === 'string'
                        ? JSON.parse(algorithmData.inputsBind)
                        : algorithmData.inputsBind;
                } catch (e) { mappings = []; }
            }
            const header = inputMappingsEl.querySelector('.binding-mapping-header');
            inputMappingsEl.innerHTML = '';
            if (header) inputMappingsEl.appendChild(header);
            if (mappings.length === 0) {
                const empty = document.createElement('div');
                empty.className = 'binding-mapping-row binding-mapping-empty';
                empty.innerHTML = '<span>暂无输入映射</span>';
                inputMappingsEl.appendChild(empty);
            } else {
                mappings.forEach(m => {
                    const row = document.createElement('div');
                    row.className = 'binding-mapping-row';
                    row.innerHTML = `<span>${m.sourceField || '-'}</span><span class="mapping-arrow">→</span><span>${m.targetField || '-'}</span>`;
                    inputMappingsEl.appendChild(row);
                });
            }
        }

        // 渲染输出映射
        const outputMappingsEl = this.shadowRoot.getElementById('detailOutputMappings');
        if (outputMappingsEl) {
            let mappings = [];
            if (algorithmData?.outputsBind) {
                try {
                    mappings = typeof algorithmData.outputsBind === 'string'
                        ? JSON.parse(algorithmData.outputsBind)
                        : algorithmData.outputsBind;
                } catch (e) { mappings = []; }
            }
            const header = outputMappingsEl.querySelector('.binding-mapping-header');
            outputMappingsEl.innerHTML = '';
            if (header) outputMappingsEl.appendChild(header);
            if (mappings.length === 0) {
                const empty = document.createElement('div');
                empty.className = 'binding-mapping-row binding-mapping-empty';
                empty.innerHTML = '<span>暂无输出映射</span>';
                outputMappingsEl.appendChild(empty);
            } else {
                mappings.forEach(m => {
                    const row = document.createElement('div');
                    row.className = 'binding-mapping-row';
                    row.innerHTML = `<span>${m.modelOutput || '-'}</span><span class="mapping-arrow">→</span><span>${m.resultTarget || '-'}</span>`;
                    outputMappingsEl.appendChild(row);
                });
            }
        }
    }

}

customElements.define('algorithm-detail', AlgorithmDetail);
