class ProjectList extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });
        this.data = [];
        this.currentPage = 1;
        this.pageSize = 10;
        this.totalCount = 0;
    }

    async loadProjectsFromAPI() {
        try {
            if (window.showGlobalLoading) {
                window.showGlobalLoading('正在查询项目...');
            }

            const keyword = this.shadowRoot.getElementById('keywordFilter')?.value.trim();
            const searchType = this.shadowRoot.getElementById('searchType')?.value || 'all';

            // Try to load from local cache first
            let result = null;
            if (window.localDB) {
                try {
                    const isStale = await window.localDB.isCacheStale('project_list', 5 * 60 * 1000);
                    if (!isStale && !keyword) {
                        const cachedData = await window.localDB.getCacheMetadata('project_list');
                        if (cachedData) {
                            console.log('Loading projects from local cache');
                            result = cachedData;
                        }
                    }
                } catch (cacheError) {
                    console.error('Cache read failed:', cacheError);
                }
            }

            // Fetch from server if no cache or cache is stale
            if (!result) {
                result = await window.AppConfig.get('project', 'search', {
                    keyword: keyword || null,
                    searchType: searchType
                });
                
                // Cache the result if successful
                if (result.code === 200 && window.localDB && !keyword) {
                    try {
                        await window.localDB.setCacheMetadata('project_list', result);
                        
                        // Also cache individual projects
                        if (result.data) {
                            for (const project of result.data) {
                                await window.localDB.put('projects', project);
                            }
                        }
                    } catch (cacheError) {
                        console.error('Cache write failed:', cacheError);
                    }
                }
            }
            
            if (result.code === 200 && result.data) {
                this.data = result.data.map(project => ({
                    id: project.id,
                    name: project.name,
                    description: project.description,
                    type: project.type,
                    updateTime: new Date(project.updateTime).toLocaleString('zh-CN'),
                    createTime: new Date(project.createTime).toLocaleString('zh-CN'),
                    owner: project.owner,
                    status: project.status ? 'active' : 'inactive',
                    algorithms: project.algorithms ? JSON.parse(project.algorithms) : [],
                    models: project.models ? JSON.parse(project.models) : [],
                    dataSources: project.dataSources ? JSON.parse(project.dataSources) : [],
                    simulationArchives: project.simulationArchives ? JSON.parse(project.simulationArchives) : []
                }));
                
                this.totalCount = this.data.length;
                this.renderTable();
            } else {
                this.showToast(result.message || '加载项目失败', 'error');
            }
        } catch (error) {
            console.error('加载项目失败:', error);
            
            // Fallback to local cache if network fails
            if (window.localDB) {
                try {
                    const cachedProjects = await window.localDB.getAll('projects');
                    if (cachedProjects && cachedProjects.length > 0) {
                        console.log('Using offline cache as fallback');
                        this.data = cachedProjects.map(project => ({
                            id: project.id,
                            name: project.name,
                            description: project.description,
                            type: project.type,
                            updateTime: new Date(project.updateTime).toLocaleString('zh-CN'),
                            createTime: new Date(project.createTime).toLocaleString('zh-CN'),
                            owner: project.owner,
                            status: project.status ? 'active' : 'inactive',
                            algorithms: project.algorithms ? JSON.parse(project.algorithms) : [],
                            models: project.models ? JSON.parse(project.models) : [],
                            dataSources: project.dataSources ? JSON.parse(project.dataSources) : [],
                            simulationArchives: project.simulationArchives ? JSON.parse(project.simulationArchives) : []
                        }));
                        this.totalCount = this.data.length;
                        this.renderTable();
                        this.showToast('离线模式：使用本地缓存数据', 'warning');
                        return;
                    }
                } catch (cacheError) {
                    console.error('Fallback cache read failed:', cacheError);
                }
            }
            
            this.showToast('网络错误，无法加载项目', 'error');
        } finally {
            if (window.hideGlobalLoading) {
                window.hideGlobalLoading();
            }
        }
    }

    async deleteProjectFromAPI(projectId) {
        try {
            const result = await window.AppConfig.delete('project', 'delete', { projectId });
            
            if (result.code === 200) {
                await this.loadProjectsFromAPI();
                this.showToast('项目已删除');
            } else {
                this.showToast(result.message || '删除失败', 'error');
            }
        } catch (error) {
            console.error('删除项目失败:', error);
            this.showToast('网络错误，删除失败', 'error');
        }
        
        this.hideModal();
    }

    async exportProjectFromAPI(projectId) {
        try {
            const result = await window.AppConfig.get('project', 'export', { projectId });
            
            if (result.code === 200 && result.data) {
                // Create a blob and download
                const blob = new Blob([result.data], { type: 'application/json' });
                const url = URL.createObjectURL(blob);
                const a = document.createElement('a');
                a.href = url;
                a.download = `project_${projectId}.json`;
                document.body.appendChild(a);
                a.click();
                document.body.removeChild(a);
                URL.revokeObjectURL(url);
                this.showToast('项目导出成功');
            } else {
                this.showToast(result.message || '导出失败', 'error');
            }
        } catch (error) {
            console.error('导出项目失败:', error);
            this.showToast('网络错误，导出失败', 'error');
        }
    }

    async connectedCallback() {
        await this.loadResources();
        
        setTimeout(() => {
            const modalMask = this.shadowRoot.getElementById('modalMask');
            if (modalMask) {
                modalMask.hidden = true;
                modalMask.style.display = 'none';
            }
            this.bindEvents();
        }, 100);
    }

    async show() {
        console.log('ProjectList show() 被调用');
        this.style.display = 'block';

        this.currentPage = 1;
        const keywordFilter = this.shadowRoot.getElementById('keywordFilter');
        if (keywordFilter) {
            keywordFilter.value = '';
        }
        const searchType = this.shadowRoot.getElementById('searchType');
        if (searchType) {
            searchType.value = 'all';
        }

        setTimeout(() => {
            this.loadProjectsFromAPI().then(() => {
                this.renderTable();
            });
        }, 100);
    }

    hide() {
        this.style.display = 'none';
    }

    async loadResources() {
        try {
            const cssLink = document.createElement('link');
            cssLink.rel = 'stylesheet';
            cssLink.href = './components/project-list/project-list.css';
            this.shadowRoot.appendChild(cssLink);
        } catch (error) {
            console.error('Failed to load CSS:', error);
        }

        if (window.location.protocol === 'file:') {
            this.shadowRoot.innerHTML += this.getFallbackHTML();
        } else {
            try {
                const response = await fetch('./components/project-list/project-list.html');
                if (!response.ok) {
                    throw new Error(`HTTP error! status: ${response.status}`);
                }
                const html = await response.text();
                this.shadowRoot.innerHTML += html;
                console.log('Project list HTML template loaded successfully');
            } catch (error) {
                console.error('Failed to load HTML template:', error);
                this.shadowRoot.innerHTML += this.getFallbackHTML();
            }
        }
    }

    getFallbackHTML() {
        return `
<div class="project-list">
    <div class="project-filter-card">
        <div class="filter-header">筛选</div>
        <div class="filter-rows" id="filterRows">
            <div class="filter-row">
                <div class="filter-field">
                    <span class="filter-label">搜索关键词</span>
                    <input class="filter-input" type="text" placeholder="请输入搜索关键词" id="keywordFilter" />
                </div>
                <div class="filter-field">
                    <span class="filter-label">搜索类型</span>
                    <select class="filter-input" id="searchType">
                        <option value="all">全部</option>
                        <option value="name">按名称</option>
                        <option value="algorithm">按算法</option>
                        <option value="model">按模型</option>
                        <option value="data">按数据</option>
                    </select>
                </div>
            </div>
        </div>
        <div class="filter-actions">
            <div class="filter-spacer"></div>
            <button class="filter-btn outline" type="button" id="resetFilters">重置</button>
            <button class="filter-btn solid" type="button" id="applyFilters">查询</button>
        </div>
    </div>

    <div class="project-table-card">
        <div class="table-toolbar">
            <button class="toolbar-btn green" type="button" id="addProjectBtn">新建项目</button>
            <button class="toolbar-btn blue" type="button" id="importProjectBtn">导入项目</button>
        </div>
        <div class="table-wrapper">
            <table class="data-table">
                <thead>
                    <tr>
                        <th>项目名称</th>
                        <th>描述</th>
                        <th>类型</th>
                        <th>创建人</th>
                        <th>创建时间</th>
                        <th>状态</th>
                        <th>操作</th>
                    </tr>
                </thead>
                <tbody id="tableBody"></tbody>
            </table>
        </div>
        <div class="pagination">
            <div class="pagination-left">
                <button class="page-btn" id="prevPage">&lt;</button>
                <div class="page-list" id="pageList"></div>
                <button class="page-btn" id="nextPage">&gt;</button>
            </div>
            <div class="pagination-right">
                <span class="total-count">共 <span id="totalCount">0</span> 条</span>
                <select class="page-size-select" id="pageSizeSelect">
                    <option value="5">5条/页</option>
                    <option value="10" selected>10条/页</option>
                    <option value="20">20条/页</option>
                    <option value="50">50条/页</option>
                </select>
            </div>
        </div>
    </div>
</div>

<div class="modal-mask" id="modalMask" hidden>
    <div class="modal">
        <div class="modal-header">
            <span id="modalTitle">确认删除</span>
            <button class="modal-close" id="modalClose">×</button>
        </div>
        <div class="modal-body" id="modalBody">
            <p>确定要删除该项目吗？此操作不可恢复。</p>
        </div>
        <div class="modal-footer" id="modalFooter">
            <button type="button" class="modal-btn secondary" id="cancelBtn">取消</button>
            <button type="button" class="modal-btn danger" id="confirmBtn">确定</button>
        </div>
    </div>
</div>

<input type="file" id="importFileInput" accept=".json" style="display: none;" />`;
    }

    bindEvents() {
        if (this._eventsBound) {
            return;
        }
        this._eventsBound = true;

        this.shadowRoot.getElementById('resetFilters')?.addEventListener('click', () => this.resetFilters());
        this.shadowRoot.getElementById('applyFilters')?.addEventListener('click', () => this.applyFilters());

        this.shadowRoot.addEventListener('click', (e) => {
            const btn = e.target.closest('.toolbar-btn');
            if (!btn) return;

            switch (btn.id) {
                case 'addProjectBtn':
                    this.showCreateProject();
                    break;
                case 'importProjectBtn':
                    this.shadowRoot.getElementById('importFileInput').click();
                    break;
            }
        });

        this.shadowRoot.getElementById('importFileInput')?.addEventListener('change', (e) => this.handleImportFile(e));

        this.shadowRoot.getElementById('modalClose')?.addEventListener('click', () => this.hideModal());
        this.shadowRoot.getElementById('cancelBtn')?.addEventListener('click', () => this.hideModal());
        this.shadowRoot.getElementById('confirmBtn')?.addEventListener('click', () => this.confirmDelete());

        this.shadowRoot.getElementById('prevPage')?.addEventListener('click', () => this.changePage(-1));
        this.shadowRoot.getElementById('nextPage')?.addEventListener('click', () => this.changePage(1));
        this.shadowRoot.getElementById('pageSizeSelect')?.addEventListener('change', (e) => {
            this.pageSize = parseInt(e.target.value);
            this.currentPage = 1;
            this.renderTable();
        });
    }

    resetFilters() {
        const keywordFilter = this.shadowRoot.getElementById('keywordFilter');
        const searchType = this.shadowRoot.getElementById('searchType');
        if (keywordFilter) keywordFilter.value = '';
        if (searchType) searchType.value = 'all';
        this.loadProjectsFromAPI();
    }

    applyFilters() {
        this.currentPage = 1;
        this.loadProjectsFromAPI();
    }

    renderTable() {
        const tbody = this.shadowRoot.getElementById('tableBody');
        if (!tbody) return;

        const start = (this.currentPage - 1) * this.pageSize;
        const end = start + this.pageSize;
        const pageData = this.data.slice(start, end);

        tbody.innerHTML = pageData.map(project => `
            <tr data-project-id="${project.id}">
                <td>${this.escapeHtml(project.name)}</td>
                <td>${this.escapeHtml(project.description || '-')}</td>
                <td>${this.escapeHtml(project.type || '-')}</td>
                <td>${this.escapeHtml(project.owner || '-')}</td>
                <td>${project.createTime}</td>
                <td>
                    <span class="status-badge ${project.status}">${project.status === 'active' ? '启用' : '禁用'}</span>
                </td>
                <td>
                    <div class="action-buttons">
                        <button class="action-btn edit" data-action="view" data-project-id="${project.id}">查看</button>
                        <button class="action-btn copy" data-action="export" data-project-id="${project.id}">导出</button>
                        <button class="action-btn delete" data-action="delete" data-project-id="${project.id}">删除</button>
                    </div>
                </td>
            </tr>
        `).join('');

        tbody.addEventListener('click', (e) => {
            const btn = e.target.closest('.action-btn');
            if (!btn) return;

            const action = btn.dataset.action;
            const projectId = btn.dataset.projectId;

            switch (action) {
                case 'view':
                    this.viewProject(projectId);
                    break;
                case 'export':
                    this.exportProjectFromAPI(projectId);
                    break;
                case 'delete':
                    this.showDeleteModal(projectId);
                    break;
            }
        });

        this.updatePagination();
    }

    updatePagination() {
        const totalPages = Math.ceil(this.data.length / this.pageSize);
        const pageList = this.shadowRoot.getElementById('pageList');
        if (!pageList) return;

        let html = '';
        for (let i = 1; i <= totalPages; i++) {
            html += `<button class="page-num ${i === this.currentPage ? 'active' : ''}" data-page="${i}">${i}</button>`;
        }
        pageList.innerHTML = html;

        pageList.querySelectorAll('.page-num').forEach(btn => {
            btn.addEventListener('click', () => {
                this.currentPage = parseInt(btn.dataset.page);
                this.renderTable();
            });
        });

        this.shadowRoot.getElementById('totalCount').textContent = this.totalCount;
        this.shadowRoot.getElementById('prevPage').disabled = this.currentPage === 1;
        this.shadowRoot.getElementById('nextPage').disabled = this.currentPage === totalPages;
    }

    changePage(delta) {
        const totalPages = Math.ceil(this.data.length / this.pageSize);
        const newPage = this.currentPage + delta;
        if (newPage >= 1 && newPage <= totalPages) {
            this.currentPage = newPage;
            this.renderTable();
        }
    }

    showDeleteModal(projectId) {
        this._deleteProjectId = projectId;
        const modal = this.shadowRoot.getElementById('modalMask');
        if (modal) {
            modal.hidden = false;
            modal.style.display = 'flex';
        }
    }

    hideModal() {
        const modal = this.shadowRoot.getElementById('modalMask');
        if (modal) {
            modal.hidden = true;
            modal.style.display = 'none';
        }
        this._deleteProjectId = null;
    }

    confirmDelete() {
        if (this._deleteProjectId) {
            this.deleteProjectFromAPI(this._deleteProjectId);
        }
    }

    viewProject(projectId) {
        // Show project detail component
        const projectDetail = document.querySelector('project-detail');
        if (projectDetail) {
            window.hideAllComponents();
            projectDetail.show(projectId);
        }
    }

    showCreateProject() {
        // Show project create component
        const projectCreate = document.querySelector('project-create');
        if (projectCreate) {
            projectCreate.show();
        }
    }

    async handleImportFile(e) {
        const file = e.target.files[0];
        if (!file) return;

        try {
            const text = await file.text();
            const projectJson = JSON.parse(text);

            if (window.showGlobalLoading) {
                window.showGlobalLoading('正在导入项目...');
            }

            const result = await window.AppConfig.post('project', 'import', projectJson);

            if (result.code === 200) {
                this.showToast('项目导入成功');
                this.loadProjectsFromAPI();
            } else {
                this.showToast(result.message || '导入失败', 'error');
            }
        } catch (error) {
            console.error('导入项目失败:', error);
            this.showToast('文件格式错误或网络错误', 'error');
        } finally {
            if (window.hideGlobalLoading) {
                window.hideGlobalLoading();
            }
            e.target.value = '';
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

customElements.define('project-list', ProjectList);
