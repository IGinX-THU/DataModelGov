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

            const nameFilter = this.shadowRoot.getElementById('nameFilter')?.value.trim();
            const algorithmFilter = this.shadowRoot.getElementById('algorithmFilter')?.value.trim();
            const modelFilter = this.shadowRoot.getElementById('modelFilter')?.value.trim();
            const dataFilter = this.shadowRoot.getElementById('dataFilter')?.value.trim();

            // Build query request matching backend ProjectsQueryRequest
            const queryRequest = {
                pageNum: this.currentPage,
                pageSize: this.pageSize,
                name: nameFilter || null,
                algorithm: algorithmFilter || null,
                model: modelFilter || null,
                data: dataFilter || null
            };

            // 先调用count接口获取总数
            const countResult = await window.AppConfig.post('project', 'count', queryRequest);
            if (countResult.code === 200) {
                this.totalCount = parseInt(countResult.data) || 0;
            }

            // 再调用query接口获取分页数据
            const result = await window.AppConfig.post('project', 'query', queryRequest);

            if (result.code === 200 && result.data) {
                this.data = result.data.map(project => ({
                    id: project.createTime,
                    name: project.name,
                    desc: project.desc,
                    createTime: new Date(project.createTime).toLocaleString('zh-CN'),
                    owner: project.owner,
                    algorithms: project.algorithms || '',
                    models: project.models || '',
                    datas: project.datas || ''
                }));

                this.renderTable();
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

    async viewProjectDetail(createTime) {
        try {
            if (window.showGlobalLoading) {
                window.showGlobalLoading('正在加载项目详情...');
            }

            const result = await window.AppConfig.get('project', 'detail', { createTime });

            if (result.code === 200 && result.data) {
                this.showDetailModal(result.data);
            } else {
                this.showToast(result.message || '加载项目详情失败', 'error');
            }
        } catch (error) {
            console.error('加载项目详情失败:', error);
            this.showToast('网络错误，无法加载项目详情', 'error');
        } finally {
            if (window.hideGlobalLoading) {
                window.hideGlobalLoading();
            }
        }
    }

    showDetailModal(project) {
        this.shadowRoot.getElementById('detailName').textContent = project.name || '-';
        this.shadowRoot.getElementById('detailDesc').textContent = project.desc || '-';
        this.shadowRoot.getElementById('detailOwner').textContent = project.owner || '-';
        this.shadowRoot.getElementById('detailCreateTime').textContent = new Date(project.createTime).toLocaleString('zh-CN');

        this.shadowRoot.getElementById('detailAlgorithms').textContent = project.algorithms || '-';
        this.shadowRoot.getElementById('detailModels').textContent = project.models || '-';
        this.shadowRoot.getElementById('detailDatas').textContent = project.datas || '-';

        const modal = this.shadowRoot.getElementById('detailModalMask');
        if (modal) {
            modal.hidden = false;
            modal.style.display = 'flex';
        }
    }

    hideDetailModal() {
        const modal = this.shadowRoot.getElementById('detailModalMask');
        if (modal) {
            modal.hidden = true;
            modal.style.display = 'none';
        }
    }

    async connectedCallback() {
        await this.loadResources();

        setTimeout(() => {
            this.bindEvents();
        }, 100);
    }

    async show() {
        console.log('ProjectList show() 被调用');
        this.style.display = 'block';

        this.currentPage = 1;
        const nameFilter = this.shadowRoot.getElementById('nameFilter');
        if (nameFilter) {
            nameFilter.value = '';
        }
        const algorithmFilter = this.shadowRoot.getElementById('algorithmFilter');
        if (algorithmFilter) {
            algorithmFilter.value = '';
        }
        const modelFilter = this.shadowRoot.getElementById('modelFilter');
        if (modelFilter) {
            modelFilter.value = '';
        }
        const dataFilter = this.shadowRoot.getElementById('dataFilter');
        if (dataFilter) {
            dataFilter.value = '';
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
                    <span class="filter-label">项目名称</span>
                    <input class="filter-input" type="text" placeholder="请输入项目名称" id="nameFilter" />
                </div>
                <div class="filter-field">
                    <span class="filter-label">算法</span>
                    <input class="filter-input" type="text" placeholder="请输入算法" id="algorithmFilter" />
                </div>
                <div class="filter-field">
                    <span class="filter-label">模型</span>
                    <input class="filter-input" type="text" placeholder="请输入模型" id="modelFilter" />
                </div>
                <div class="filter-field">
                    <span class="filter-label">数据</span>
                    <input class="filter-input" type="text" placeholder="请输入数据" id="dataFilter" />
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
        </div>
        <div class="table-wrapper">
            <table class="data-table">
                <thead>
                    <tr>
                        <th>项目名称</th>
                        <th>描述</th>
                        <th>创建人</th>
                        <th>创建时间</th>
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

<div class="modal-mask" id="detailModalMask" hidden>
    <div class="modal">
        <div class="modal-header">
            <span id="detailModalTitle">项目详情</span>
            <button class="modal-close" id="detailModalClose">×</button>
        </div>
        <div class="modal-body" id="detailModalBody">
            <div class="detail-content">
                <div class="detail-row">
                    <span class="detail-label">项目名称：</span>
                    <span class="detail-value" id="detailName"></span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">描述：</span>
                    <span class="detail-value" id="detailDesc"></span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">创建人：</span>
                    <span class="detail-value" id="detailOwner"></span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">创建时间：</span>
                    <span class="detail-value" id="detailCreateTime"></span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">算法：</span>
                    <span class="detail-value" id="detailAlgorithms"></span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">模型：</span>
                    <span class="detail-value" id="detailModels"></span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">数据：</span>
                    <span class="detail-value" id="detailDatas"></span>
                </div>
            </div>
        </div>
        <div class="modal-footer">
            <button type="button" class="modal-btn secondary" id="detailModalCloseBtn">关闭</button>
        </div>
    </div>
</div>`;
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
                    window.showComponent?.('projectImport');
                    break;
                case 'exportProjectBtn':
                    window.showComponent?.('projectExport');
                    break;
            }
        });

        this.shadowRoot.getElementById('detailModalClose')?.addEventListener('click', () => this.hideDetailModal());
        this.shadowRoot.getElementById('detailModalCloseBtn')?.addEventListener('click', () => this.hideDetailModal());

        this.shadowRoot.getElementById('prevPage')?.addEventListener('click', () => this.changePage(-1));
        this.shadowRoot.getElementById('nextPage')?.addEventListener('click', () => this.changePage(1));
        this.shadowRoot.getElementById('pageSizeSelect')?.addEventListener('change', (e) => {
            this.pageSize = parseInt(e.target.value);
            this.currentPage = 1;
            this.renderTable();
        });
    }

    resetFilters() {
        const nameFilter = this.shadowRoot.getElementById('nameFilter');
        const algorithmFilter = this.shadowRoot.getElementById('algorithmFilter');
        const modelFilter = this.shadowRoot.getElementById('modelFilter');
        const dataFilter = this.shadowRoot.getElementById('dataFilter');
        if (nameFilter) nameFilter.value = '';
        if (algorithmFilter) algorithmFilter.value = '';
        if (modelFilter) modelFilter.value = '';
        if (dataFilter) dataFilter.value = '';
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
                <td>${this.escapeHtml(project.desc || '-')}</td>
                <td>${this.escapeHtml(project.owner || '-')}</td>
                <td>${project.createTime}</td>
                <td>
                    <div class="action-buttons">
                        <button class="action-btn edit" data-action="open" data-create-time="${project.id}">打开</button>
                        <button class="action-btn copy" data-action="view" data-create-time="${project.id}">查看</button>
                    </div>
                </td>
            </tr>
        `).join('');

        // 移除旧的事件监听器（如果有）
        if (this._tbodyClickHandler) {
            tbody.removeEventListener('click', this._tbodyClickHandler);
        }

        // 创建并保存新的事件监听器
        this._tbodyClickHandler = (e) => {
            const btn = e.target.closest('.action-btn');
            if (!btn) return;

            const action = btn.dataset.action;
            const createTime = btn.dataset.createTime;

            switch (action) {
                case 'open':
                    this.openProject(createTime);
                    break;
                case 'view':
                    this.viewProjectDetail(createTime);
                    break;
            }
        };
        tbody.addEventListener('click', this._tbodyClickHandler);

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

    showCreateProject() {
        const projectCreate = document.querySelector('project-create');
        if (projectCreate) {
            projectCreate.show();
        }
    }

    async openProject(createTime) {
        try {
            if (window.showGlobalLoading) {
                window.showGlobalLoading('正在打开项目...');
            }

            const result = await window.AppConfig.get('project', 'detail', { createTime });

            if (result.code === 200 && result.data) {
                const project = result.data;

                // Cache current project (按用户隔离)
                if (window.localStorage) {
                    const username = window.AppConfig.getUsername();
                    if (username) {
                        window.localStorage.setItem('currentProject_' + username, JSON.stringify({
                            name: project.name,
                            createTime: project.createTime
                        }));
                    }
                }

                // Call global function to display tree in left sidebar
                if (window.displayProjectTree) {
                    window.displayProjectTree(project.name);
                } else {
                    this.showToast('树形展示功能暂不可用', 'error');
                }
            } else {
                this.showToast(result.message || '打开项目失败', 'error');
            }
        } catch (error) {
            console.error('打开项目失败:', error);
            this.showToast('网络错误，无法打开项目', 'error');
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

customElements.define('project-list', ProjectList);
