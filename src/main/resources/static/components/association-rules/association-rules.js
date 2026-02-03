class AssociationRules extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });
        this.data = [];
        this.pageSize = 6;
        this.currentPage = 1;
    }

    async connectedCallback() {
        await this.loadResources();
        this.seedData();
        this.renderTable();
        
        setTimeout(() => {
            const modalMask = this.shadowRoot.getElementById('modalMask');
            if (modalMask) {
                modalMask.hidden = true;
                modalMask.style.display = 'none';
            }
            this.bindEvents();
        }, 100);
    }

    async loadResources() {
        try {
            const cssLink = document.createElement('link');
            cssLink.rel = 'stylesheet';
            cssLink.href = './components/association-rules/association-rules.css';
            this.shadowRoot.appendChild(cssLink);
        } catch (error) {
            console.error('Failed to load CSS:', error);
        }

        if (window.location.protocol === 'file:') {
            this.shadowRoot.innerHTML += this.getFallbackHTML();
        } else {
            try {
                const response = await fetch('./components/association-rules/association-rules.html');
                if (!response.ok) {
                    throw new Error(`HTTP error! status: ${response.status}`);
                }
                const html = await response.text();
                this.shadowRoot.innerHTML += html;
                console.log('Association rules HTML template loaded successfully');
            } catch (error) {
                console.error('Failed to load HTML template:', error);
                this.shadowRoot.innerHTML += this.getFallbackHTML();
            }
        }
    }

    getFallbackHTML() {
        return `
<div class="parsing-rules">
    <div class="parsing-filter-card">
        <div class="filter-header">筛选</div>
        <div class="filter-rows" id="filterRows">
            ${this.buildFilterRow('', '')}
        </div>
        <div class="filter-actions">
            <button class="filter-add" type="button" id="addFilter">⊕</button>
            <div class="filter-spacer"></div>
            <button class="filter-btn outline" type="button" id="resetFilters">重置</button>
            <button class="filter-btn solid" type="button" id="applyFilters">查询</button>
        </div>
    </div>

    <div class="parsing-table-card">
        <div class="table-toolbar">
            <button class="toolbar-btn green" type="button" id="addRuleBtn">新增</button>
            <button class="toolbar-btn orange" type="button" id="importBtn">导入</button>
            <button class="toolbar-btn blue" type="button" id="exportBtn">导出</button>
        </div>
        <div class="table-wrapper">
            <table class="data-table">
                <thead>
                    <tr>
                        <th>id</th>
                        <th>名称</th>
                        <th>正则表达式</th>
                        <th>创建时间</th>
                        <th>更新时间</th>
                        <th>操作</th>
                    </tr>
                </thead>
                <tbody id="tableBody"></tbody>
            </table>
        </div>
        <div class="pagination">
            <button class="page-btn" id="prevPage">&lt;</button>
            <div class="page-list" id="pageList"></div>
            <button class="page-btn" id="nextPage">&gt;</button>
        </div>
    </div>
</div>

<div class="modal-mask" id="modalMask" hidden>
    <div class="modal">
        <div class="modal-header">
            <span id="modalTitle">提示</span>
            <button class="modal-close" id="modalClose">×</button>
        </div>
        <div class="modal-body" id="modalBody"></div>
        <div class="modal-footer" id="modalFooter"></div>
    </div>
</div>`;
    }

    buildFilterRow(name = '', regex = '') {
        return `
            <div class="filter-row">
                <div class="filter-field">
                    <span class="filter-label">名称</span>
                    <input class="filter-input" type="text" placeholder="请输入规则名称" value="${name}" />
                </div>
                <div class="filter-field">
                    <span class="filter-label">正则</span>
                    <input class="filter-input" type="text" placeholder="请输入正则表达式" value="${regex}" />
                </div>
                <button class="filter-remove" type="button" onclick="this.parentElement.remove()">×</button>
            </div>
        `;
    }

    seedData() {
        this.data = [
            {
                id: 1,
                ruleName: '温度数据关联规则',
                targetModel: '环境监测模型',
                version: 'v1.0.0',
                status: 'active',
                updateTime: '2024-01-20 14:25:00'
            },
            {
                id: 2,
                ruleName: '设备状态关联规则',
                targetModel: '设备监控模型',
                version: 'v1.2.0',
                status: 'active',
                updateTime: '2024-01-18 16:40:00'
            },
            {
                id: 3,
                ruleName: '压力数据关联规则',
                targetModel: '管道监测模型',
                version: 'v1.1.0',
                status: 'inactive',
                updateTime: '2024-01-16 13:55:00'
            },
            {
                id: 4,
                ruleName: '能耗数据关联规则',
                targetModel: '能耗分析模型',
                version: 'v2.0.0',
                status: 'active',
                updateTime: '2024-01-12 10:30:00'
            },
            {
                id: 5,
                ruleName: '振动数据关联规则',
                targetModel: '设备健康模型',
                version: 'v1.0.0',
                status: 'inactive',
                updateTime: '2024-01-10 17:20:00'
            }
        ];
    }

    bindEvents() {
        // 筛选相关事件
        this.shadowRoot.getElementById('addFilter')?.addEventListener('click', () => this.addFilterRow());
        this.shadowRoot.getElementById('resetFilters')?.addEventListener('click', () => this.resetFilters());
        this.shadowRoot.getElementById('applyFilters')?.addEventListener('click', () => this.applyFilters());

        // 工具栏事件
        this.shadowRoot.getElementById('addRuleBtn')?.addEventListener('click', () => this.showAddModal());
        this.shadowRoot.getElementById('importBtn')?.addEventListener('click', () => this.importRules());
        this.shadowRoot.getElementById('exportBtn')?.addEventListener('click', () => this.exportRules());

        // 分页事件
        this.shadowRoot.getElementById('prevPage')?.addEventListener('click', () => this.changePage(-1));
        this.shadowRoot.getElementById('nextPage')?.addEventListener('click', () => this.changePage(1));

        // 模态框事件
        this.shadowRoot.getElementById('modalClose')?.addEventListener('click', () => this.closeModal());
        this.shadowRoot.getElementById('modalMask')?.addEventListener('click', (e) => {
            if (e.target.id === 'modalMask') this.closeModal();
        });

        // 处理操作按钮点击事件
        this.shadowRoot.addEventListener('click', (e) => {
            if (e.target.classList.contains('action-btn')) {
                const action = e.target.dataset.action;
                const id = parseInt(e.target.dataset.id);
                const item = this.data.find(item => item.id === id);
                
                switch (action) {
                    case 'run':
                        this.runRule(id);
                        break;
                    case 'copy':
                        this.copyRule(id);
                        break;
                    case 'toggle':
                        this.toggleRuleStatus(id);
                        e.target.textContent = item.status === 'active' ? '启用' : '禁用';
                        break;
                    case 'edit':
                        this.editRule(id);
                        break;
                    case 'delete':
                        this.deleteRule(id);
                        break;
                }
            }
            
            // 处理模态框按钮点击事件
            if (e.target.classList.contains('modal-btn')) {
                const action = e.target.dataset.action;
                const id = e.target.dataset.id ? parseInt(e.target.dataset.id) : null;
                
                switch (action) {
                    case 'cancel':
                        this.closeModal();
                        break;
                    case 'save':
                        this.saveRule();
                        break;
                    case 'update':
                        this.updateRule(id);
                        break;
                }
            }
        });
    }

    addFilterRow() {
        const filterRows = this.shadowRoot.getElementById('filterRows');
        const newRow = document.createElement('div');
        newRow.innerHTML = this.buildFilterRow();
        filterRows.appendChild(newRow);
    }

    resetFilters() {
        const filterRows = this.shadowRoot.getElementById('filterRows');
        filterRows.innerHTML = this.buildFilterRow();
        this.renderTable();
    }

    applyFilters() {
        const filterInputs = this.shadowRoot.querySelectorAll('.filter-input');
        const filters = Array.from(filterInputs).map(input => input.value.trim());
        
        const [nameFilter, regexFilter] = filters;
        
        let filteredData = this.data.filter(item => {
            if (nameFilter && !item.name.includes(nameFilter)) return false;
            if (regexFilter && !item.regex.includes(regexFilter)) return false;
            return true;
        });

        this.renderFilteredTable(filteredData);
    }

    renderFilteredTable(filteredData) {
        const tbody = this.shadowRoot.getElementById('tableBody');
        if (!tbody) return;

        const start = (this.currentPage - 1) * this.pageSize;
        const end = start + this.pageSize;
        const pageData = filteredData.slice(start, end);

        tbody.innerHTML = pageData.map(item => `
            <tr>
                <td>${item.ruleName}</td>
                <td>${item.targetModel}</td>
                <td>${item.version}</td>
                <td>
                    <span class="status-badge ${item.status}">
                        ${item.status === 'active' ? '启用' : '禁用'}
                    </span>
                </td>
                <td>${item.updateTime}</td>
                <td>
                    <div class="action-buttons">
                        <button class="action-btn run" data-action="run" data-id="${item.id}">运行</button>
                        <button class="action-btn copy" data-action="copy" data-id="${item.id}">复制</button>
                        <button class="action-btn toggle" data-action="toggle" data-id="${item.id}" data-status="${item.status}">${item.status === 'active' ? '禁用' : '启用'}</button>
                        <button class="action-btn edit" data-action="edit" data-id="${item.id}">编辑</button>
                        <button class="action-btn delete" data-action="delete" data-id="${item.id}">删除</button>
                    </div>
                </td>
            </tr>
        `).join('');

        this.renderFilteredPagination(filteredData);
    }

    renderFilteredPagination(filteredData) {
        const totalPages = Math.ceil(filteredData.length / this.pageSize);
        const pageList = this.shadowRoot.getElementById('pageList');
        const prevBtn = this.shadowRoot.getElementById('prevPage');
        const nextBtn = this.shadowRoot.getElementById('nextPage');

        if (!pageList) return;

        pageList.innerHTML = '';
        for (let i = 1; i <= totalPages; i++) {
            const pageBtn = document.createElement('button');
            pageBtn.className = `page-number ${i === this.currentPage ? 'active' : ''}`;
            pageBtn.textContent = i;
            pageBtn.onclick = () => this.goToPage(i);
            pageList.appendChild(pageBtn);
        }

        prevBtn.disabled = this.currentPage === 1;
        nextBtn.disabled = this.currentPage === totalPages;
    }

    renderTable() {
        const tbody = this.shadowRoot.getElementById('tableBody');
        if (!tbody) return;

        const start = (this.currentPage - 1) * this.pageSize;
        const end = start + this.pageSize;
        const pageData = this.data.slice(start, end);

        tbody.innerHTML = pageData.map(item => `
            <tr>
                <td>${item.ruleName}</td>
                <td>${item.targetModel}</td>
                <td>${item.version}</td>
                <td>
                    <span class="status-badge ${item.status}">
                        ${item.status === 'active' ? '启用' : '禁用'}
                    </span>
                </td>
                <td>${item.updateTime}</td>
                <td>
                    <div class="action-buttons">
                        <button class="action-btn run" data-action="run" data-id="${item.id}">运行</button>
                        <button class="action-btn copy" data-action="copy" data-id="${item.id}">复制</button>
                        <button class="action-btn toggle" data-action="toggle" data-id="${item.id}" data-status="${item.status}">${item.status === 'active' ? '禁用' : '启用'}</button>
                        <button class="action-btn edit" data-action="edit" data-id="${item.id}">编辑</button>
                        <button class="action-btn delete" data-action="delete" data-id="${item.id}">删除</button>
                    </div>
                </td>
            </tr>
        `).join('');

        this.renderPagination();
    }

    renderPagination() {
        const totalPages = Math.ceil(this.data.length / this.pageSize);
        const pageList = this.shadowRoot.getElementById('pageList');
        const prevBtn = this.shadowRoot.getElementById('prevPage');
        const nextBtn = this.shadowRoot.getElementById('nextPage');

        if (!pageList) return;

        pageList.innerHTML = '';
        for (let i = 1; i <= totalPages; i++) {
            const pageBtn = document.createElement('button');
            pageBtn.className = `page-number ${i === this.currentPage ? 'active' : ''}`;
            pageBtn.textContent = i;
            pageBtn.onclick = () => this.goToPage(i);
            pageList.appendChild(pageBtn);
        }

        prevBtn.disabled = this.currentPage === 1;
        nextBtn.disabled = this.currentPage === totalPages;
    }

    changePage(direction) {
        const totalPages = Math.ceil(this.data.length / this.pageSize);
        const newPage = this.currentPage + direction;
        
        if (newPage >= 1 && newPage <= totalPages) {
            this.currentPage = newPage;
            this.renderTable();
        }
    }

    goToPage(page) {
        this.currentPage = page;
        this.renderTable();
    }

    showAddModal() {
        const modalBody = this.shadowRoot.getElementById('modalBody');
        const modalFooter = this.shadowRoot.getElementById('modalFooter');
        const modalTitle = this.shadowRoot.getElementById('modalTitle');

        modalTitle.textContent = '新增解析规则';
        modalBody.innerHTML = this.getRuleModalBody();
        modalFooter.innerHTML = `
            <button class="modal-btn" data-action="cancel">取消</button>
            <button class="modal-btn primary" data-action="save">保存</button>
        `;

        this.shadowRoot.getElementById('modalMask').hidden = false;
    }

    getRuleModalBody() {
        return `
            <div class="form-group">
                <label class="form-label">规则名称</label>
                <input class="form-input" id="ruleName" type="text" placeholder="请输入规则名称" />
            </div>
            <div class="form-group">
                <label class="form-label">正则表达式</label>
                <input class="form-input" id="ruleRegex" type="text" placeholder="请输入正则表达式" />
            </div>
        `;
    }

    saveRule() {
        const newRule = {
            id: this.data.length + 1,
            name: this.shadowRoot.getElementById('ruleName')?.value.trim(),
            regex: this.shadowRoot.getElementById('ruleRegex')?.value.trim(),
            createTime: new Date().toLocaleString('zh-CN'),
            updateTime: new Date().toLocaleString('zh-CN')
        };

        this.data.push(newRule);
        this.renderTable();
        this.closeModal();
    }

    editRule(id) {
        const rule = this.data.find(item => item.id === id);
        if (!rule) return;

        const modalBody = this.shadowRoot.getElementById('modalBody');
        const modalFooter = this.shadowRoot.getElementById('modalFooter');
        const modalTitle = this.shadowRoot.getElementById('modalTitle');

        modalTitle.textContent = '编辑解析规则';
        modalBody.innerHTML = this.getRuleModalBody();
        modalFooter.innerHTML = `
            <button class="modal-btn" data-action="cancel">取消</button>
            <button class="modal-btn primary" data-action="update" data-id="${id}">更新</button>
        `;

        // 填充表单数据
        setTimeout(() => {
            this.shadowRoot.getElementById('ruleName').value = rule.name;
            this.shadowRoot.getElementById('ruleRegex').value = rule.regex;
        }, 0);

        this.shadowRoot.getElementById('modalMask').hidden = false;
    }

    updateRule(id) {
        const rule = this.data.find(item => item.id === id);
        if (!rule) return;

        rule.name = this.shadowRoot.getElementById('ruleName')?.value.trim();
        rule.regex = this.shadowRoot.getElementById('ruleRegex')?.value.trim();
        rule.updateTime = new Date().toLocaleString('zh-CN');

        this.renderTable();
        this.closeModal();
    }

    deleteRule(id) {
        if (confirm('确定要删除这条规则吗？')) {
            this.data = this.data.filter(item => item.id !== id);
            this.renderTable();
        }
    }

    importRules() {
        alert('导入功能待实现');
    }

    exportRules() {
        alert('导出功能待实现');
    }

    closeModal() {
        this.shadowRoot.getElementById('modalMask').hidden = true;
    }
    
    show() {
        console.log('AssociationRules.show() called');
        this.setAttribute('show', '');
        console.log('AssociationRules: show attribute set');
        
        // 直接设置样式作为备用方案
        this.style.display = 'block';
        console.log('AssociationRules: style.display set to:', this.style.display);
    }
    
    hide() {
        console.log('AssociationRules.hide() called');
        this.removeAttribute('show');
        this.style.display = 'none';
    }
}

customElements.define('association-rules', AssociationRules);
