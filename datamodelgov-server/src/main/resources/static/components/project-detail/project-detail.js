class ProjectDetail extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });
        this.project = null;
        this.currentTab = 'overview';
    }

    async loadProjectFromAPI(projectId) {
        try {
            if (window.showGlobalLoading) {
                window.showGlobalLoading('正在加载项目详情...');
            }

            const result = await window.AppConfig.get('project', 'get', { projectId });
            
            if (result.code === 200 && result.data) {
                this.project = result.data;
                this.render();
            } else {
                this.showToast(result.message || '加载项目失败', 'error');
            }
        } catch (error) {
            console.error('加载项目失败:', error);
            this.showToast('网络错误，无法加载项目', 'error');
        } finally {
            if (window.hideGlobalLoading) {
                window.hideGlobalLoading();
            }
        }
    }

    async connectedCallback() {
        await this.loadResources();
        
        setTimeout(() => {
            this.bindEvents();
        }, 100);
    }

    async show(projectId) {
        console.log('ProjectDetail show() 被调用', projectId);
        this.style.display = 'block';
        await this.loadProjectFromAPI(projectId);
    }

    hide() {
        this.style.display = 'none';
    }

    async loadResources() {
        try {
            const cssLink = document.createElement('link');
            cssLink.rel = 'stylesheet';
            cssLink.href = './components/project-detail/project-detail.css';
            this.shadowRoot.appendChild(cssLink);
        } catch (error) {
            console.error('Failed to load CSS:', error);
        }

        if (window.location.protocol === 'file:') {
            this.shadowRoot.innerHTML += this.getFallbackHTML();
        } else {
            try {
                const response = await fetch('./components/project-detail/project-detail.html');
                if (!response.ok) {
                    throw new Error(`HTTP error! status: ${response.status}`);
                }
                const html = await response.text();
                this.shadowRoot.innerHTML += html;
                console.log('Project detail HTML template loaded successfully');
            } catch (error) {
                console.error('Failed to load HTML template:', error);
                this.shadowRoot.innerHTML += this.getFallbackHTML();
            }
        }
    }

    getFallbackHTML() {
        return `
<div class="project-detail">
    <div class="detail-header">
        <div class="header-left">
            <button class="back-btn" id="backBtn">← 返回项目列表</button>
            <h1 class="project-title" id="projectTitle">项目详情</h1>
        </div>
        <div class="header-right">
            <button class="action-btn edit" id="editBtn">编辑项目</button>
            <button class="action-btn delete" id="deleteBtn">删除项目</button>
        </div>
    </div>

    <div class="detail-tabs">
        <button class="tab-btn active" data-tab="overview">概览</button>
        <button class="tab-btn" data-tab="algorithms">算法档案</button>
        <button class="tab-btn" data-tab="models">模型档案</button>
        <button class="tab-btn" data-tab="data">数据档案</button>
        <button class="tab-btn" data-tab="archives">仿真档案</button>
    </div>

    <div class="detail-content">
        <div class="tab-content active" id="overviewTab">
            <div class="info-card">
                <h3>基本信息</h3>
                <div class="info-row">
                    <span class="info-label">项目名称:</span>
                    <span class="info-value" id="infoName">-</span>
                </div>
                <div class="info-row">
                    <span class="info-label">项目描述:</span>
                    <span class="info-value" id="infoDescription">-</span>
                </div>
                <div class="info-row">
                    <span class="info-label">项目类型:</span>
                    <span class="info-value" id="infoType">-</span>
                </div>
                <div class="info-row">
                    <span class="info-label">创建人:</span>
                    <span class="info-value" id="infoOwner">-</span>
                </div>
                <div class="info-row">
                    <span class="info-label">创建时间:</span>
                    <span class="info-value" id="infoCreateTime">-</span>
                </div>
                <div class="info-row">
                    <span class="info-label">更新时间:</span>
                    <span class="info-value" id="infoUpdateTime">-</span>
                </div>
                <div class="info-row">
                    <span class="info-label">状态:</span>
                    <span class="info-value" id="infoStatus">-</span>
                </div>
            </div>

            <div class="info-card">
                <h3>资源统计</h3>
                <div class="info-row">
                    <span class="info-label">算法数量:</span>
                    <span class="info-value" id="infoAlgorithmCount">0</span>
                </div>
                <div class="info-row">
                    <span class="info-label">模型数量:</span>
                    <span class="info-value" id="infoModelCount">0</span>
                </div>
                <div class="info-row">
                    <span class="info-label">数据源数量:</span>
                    <span class="info-value" id="infoDataSourceCount">0</span>
                </div>
                <div class="info-row">
                    <span class="info-label">仿真档案数量:</span>
                    <span class="info-value" id="infoArchiveCount">0</span>
                </div>
            </div>
        </div>

        <div class="tab-content" id="algorithmsTab">
            <div class="archive-list" id="algorithmList"></div>
        </div>

        <div class="tab-content" id="modelsTab">
            <div class="archive-list" id="modelList"></div>
        </div>

        <div class="tab-content" id="dataTab">
            <div class="archive-list" id="dataSourceList"></div>
        </div>

        <div class="tab-content" id="archivesTab">
            <div class="archive-list" id="simulationArchiveList"></div>
        </div>
    </div>
</div>`;
    }

    bindEvents() {
        if (this._eventsBound) {
            return;
        }
        this._eventsBound = true;

        this.shadowRoot.getElementById('backBtn')?.addEventListener('click', () => this.goBack());
        this.shadowRoot.getElementById('editBtn')?.addEventListener('click', () => this.editProject());
        this.shadowRoot.getElementById('deleteBtn')?.addEventListener('click', () => this.deleteProject());

        this.shadowRoot.querySelectorAll('.tab-btn').forEach(btn => {
            btn.addEventListener('click', () => {
                this.switchTab(btn.dataset.tab);
            });
        });
    }

    render() {
        if (!this.project) return;

        // Update overview tab
        this.shadowRoot.getElementById('infoName').textContent = this.project.name || '-';
        this.shadowRoot.getElementById('infoDescription').textContent = this.project.description || '-';
        this.shadowRoot.getElementById('infoType').textContent = this.project.type || '-';
        this.shadowRoot.getElementById('infoOwner').textContent = this.project.owner || '-';
        this.shadowRoot.getElementById('infoCreateTime').textContent = new Date(this.project.createTime).toLocaleString('zh-CN');
        this.shadowRoot.getElementById('infoUpdateTime').textContent = new Date(this.project.updateTime).toLocaleString('zh-CN');
        this.shadowRoot.getElementById('infoStatus').textContent = this.project.status ? '启用' : '禁用';

        // Parse JSON arrays
        const algorithms = this.project.algorithms ? JSON.parse(this.project.algorithms) : [];
        const models = this.project.models ? JSON.parse(this.project.models) : [];
        const dataSources = this.project.dataSources ? JSON.parse(this.project.dataSources) : [];
        const simulationArchives = this.project.simulationArchives ? JSON.parse(this.project.simulationArchives) : [];

        // Update counts
        this.shadowRoot.getElementById('infoAlgorithmCount').textContent = algorithms.length;
        this.shadowRoot.getElementById('infoModelCount').textContent = models.length;
        this.shadowRoot.getElementById('infoDataSourceCount').textContent = dataSources.length;
        this.shadowRoot.getElementById('infoArchiveCount').textContent = simulationArchives.length;

        // Render algorithm list
        this.renderAlgorithmList(algorithms);

        // Render model list
        this.renderModelList(models);

        // Render data source list
        this.renderDataSourceList(dataSources);

        // Render simulation archive list
        this.renderSimulationArchiveList(simulationArchives);
    }

    renderAlgorithmList(algorithms) {
        const container = this.shadowRoot.getElementById('algorithmList');
        if (!container) return;

        if (algorithms.length === 0) {
            container.innerHTML = '<div class="empty-state">暂无算法档案</div>';
            return;
        }

        container.innerHTML = algorithms.map(algo => `
            <div class="archive-item">
                <div class="archive-header">
                    <h4>${this.escapeHtml(algo.name || '-')}</h4>
                    <span class="archive-version">${this.escapeHtml(algo.version || '-')}</span>
                </div>
                <div class="archive-body">
                    <p><strong>算法类型:</strong> ${this.escapeHtml(algo.algorithmType || '-')}</p>
                    <p><strong>开发者:</strong> ${this.escapeHtml(algo.author || '-')}</p>
                    <p><strong>场景描述:</strong> ${this.escapeHtml(algo.scene || '-')}</p>
                    ${algo.inputs ? `<p><strong>输入参数:</strong> ${this.escapeHtml(algo.inputs)}</p>` : ''}
                    ${algo.outputs ? `<p><strong>输出参数:</strong> ${this.escapeHtml(algo.outputs)}</p>` : ''}
                </div>
            </div>
        `).join('');
    }

    renderModelList(models) {
        const container = this.shadowRoot.getElementById('modelList');
        if (!container) return;

        if (models.length === 0) {
            container.innerHTML = '<div class="empty-state">暂无模型档案</div>';
            return;
        }

        container.innerHTML = models.map(model => `
            <div class="archive-item">
                <div class="archive-header">
                    <h4>${this.escapeHtml(model.name || '-')}</h4>
                    <span class="archive-version">${this.escapeHtml(model.version || '-')}</span>
                </div>
                <div class="archive-body">
                    <p><strong>开发者:</strong> ${this.escapeHtml(model.author || '-')}</p>
                    <p><strong>场景:</strong> ${this.escapeHtml(model.scene || '-')}</p>
                    ${model.inputs ? `<p><strong>输入参数:</strong> ${this.escapeHtml(model.inputs)}</p>` : ''}
                    ${model.outputs ? `<p><strong>输出参数:</strong> ${this.escapeHtml(model.outputs)}</p>` : ''}
                    ${model.cmd ? `<p><strong>运行命令:</strong> ${this.escapeHtml(model.cmd)}</p>` : ''}
                </div>
            </div>
        `).join('');
    }

    renderDataSourceList(dataSources) {
        const container = this.shadowRoot.getElementById('dataSourceList');
        if (!container) return;

        if (dataSources.length === 0) {
            container.innerHTML = '<div class="empty-state">暂无数据档案</div>';
            return;
        }

        container.innerHTML = dataSources.map(ds => `
            <div class="archive-item">
                <div class="archive-header">
                    <h4>${this.escapeHtml(ds.dataSourcePath || '-')}</h4>
                </div>
                <div class="archive-body">
                    <p><strong>数据源路径:</strong> ${this.escapeHtml(ds.dataSourcePath || '-')}</p>
                </div>
            </div>
        `).join('');
    }

    renderSimulationArchiveList(archives) {
        const container = this.shadowRoot.getElementById('simulationArchiveList');
        if (!container) return;

        if (archives.length === 0) {
            container.innerHTML = '<div class="empty-state">暂无仿真档案</div>';
            return;
        }

        container.innerHTML = archives.map(archive => `
            <div class="archive-item">
                <div class="archive-header">
                    <h4>${this.escapeHtml(archive.archiveName || '-')}</h4>
                </div>
                <div class="archive-body">
                    <p><strong>档案名称:</strong> ${this.escapeHtml(archive.archiveName || '-')}</p>
                </div>
            </div>
        `).join('');
    }

    switchTab(tabName) {
        this.currentTab = tabName;

        // Update tab buttons
        this.shadowRoot.querySelectorAll('.tab-btn').forEach(btn => {
            btn.classList.toggle('active', btn.dataset.tab === tabName);
        });

        // Update tab content
        this.shadowRoot.querySelectorAll('.tab-content').forEach(content => {
            content.classList.remove('active');
        });
        this.shadowRoot.getElementById(tabName + 'Tab')?.classList.add('active');
    }

    goBack() {
        const projectList = document.querySelector('project-list');
        if (projectList) {
            window.hideAllComponents();
            projectList.show();
        }
    }

    editProject() {
        const projectCreate = document.querySelector('project-create');
        if (projectCreate) {
            window.hideAllComponents();
            projectCreate.show(this.project.id);
        }
    }

    async deleteProject() {
        if (window.showConfirmDialog) {
            window.showConfirmDialog('确定要删除该项目吗？此操作不可恢复。', () => {
                this.executeDeleteProject();
            });
        } else {
            // 降级处理
            if (!confirm('确定要删除该项目吗？此操作不可恢复。')) {
                return;
            }
            this.executeDeleteProject();
        }
    }

    async executeDeleteProject() {

        try {
            if (window.showGlobalLoading) {
                window.showGlobalLoading('正在删除项目...');
            }

            const result = await window.AppConfig.delete('project', 'delete', { projectId: this.project.id });

            if (result.code === 200) {
                this.showToast('项目删除成功');
                this.goBack();
            } else {
                this.showToast(result.message || '删除失败', 'error');
            }
        } catch (error) {
            console.error('删除项目失败:', error);
            this.showToast('网络错误，删除失败', 'error');
        } finally {
            if (window.hideGlobalLoading) {
                window.hideGlobalLoading();
            }
        }
    }

    showToast(message, type = 'success') {
        const toast = document.createElement('div');
        toast.className = `toast toast-${type}`;
        toast.textContent = message;
        toast.style.cssText = `
            position: fixed;
            top: 20px;
            right: 20px;
            padding: 12px 24px;
            background: ${type === 'success' ? '#67c23a' : '#f56c6c'};
            color: white;
            border-radius: 4px;
            z-index: 10000;
            animation: slideIn 0.3s ease;
        `;
        document.body.appendChild(toast);
        setTimeout(() => toast.remove(), 3000);
    }

    escapeHtml(text) {
        if (!text) return '';
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }
}

customElements.define('project-detail', ProjectDetail);
