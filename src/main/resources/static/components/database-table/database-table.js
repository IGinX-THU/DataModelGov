class DatabaseTable extends HTMLElement {
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
        
        // 确保模态框初始状态是隐藏的，并且移除任何可能的事件监听器
        setTimeout(() => {
            const modalMask = this.shadowRoot.getElementById('modalMask');
            if (modalMask) {
                modalMask.hidden = true;
                // 确保模态框不会因为任何原因自动显示
                modalMask.style.display = 'none';
            }
            this.bindEvents();
        }, 100);
    }

    async loadResources() {
        // 加载CSS
        try {
            const cssLink = document.createElement('link');
            cssLink.rel = 'stylesheet';
            cssLink.href = './components/database-table/database-table.css';
            this.shadowRoot.appendChild(cssLink);
        } catch (error) {
            console.error('Failed to load CSS:', error);
        }

        if (window.location.protocol === 'file:') {
            this.shadowRoot.innerHTML += this.getFallbackHTML();
        } else {
            // 加载HTML模板
            try {
                const response = await fetch('./components/database-table/database-table.html');
                if (!response.ok) {
                    throw new Error(`HTTP error! status: ${response.status}`);
                }
                const html = await response.text();
                this.shadowRoot.innerHTML += html;
                console.log('Database table HTML template loaded successfully');
            } catch (error) {
                console.error('Failed to load HTML template:', error);
                // 如果外部文件加载失败，使用内联模板
                this.shadowRoot.innerHTML += this.getFallbackHTML();
            }
        }
    }

    getFallbackHTML() {
        return `
<div class="db-table">
    <div class="db-filter-card">
        <div class="filter-header">筛选</div>
        <div class="filter-rows" id="filterRows">
            ${this.buildFilterRow('temperature', '=', '3145')}
            ${this.buildFilterRow('humidity', '=', '3145')}
            ${this.buildFilterRow('时间戳', '包含', '')}
        </div>
        <div class="filter-actions">
            <button class="filter-add" type="button" id="addFilter">⊕</button>
            <div class="filter-spacer"></div>
            <button class="filter-btn outline" type="button" id="resetFilters">重置</button>
            <button class="filter-btn solid" type="button" id="applyFilters">查询</button>
        </div>
    </div>

    <div class="db-table-card">
        <div class="table-toolbar">
            <button class="toolbar-btn green" type="button" id="addRowBtn">新增</button>
            <button class="toolbar-btn orange" type="button" id="importBtn">导入</button>
            <button class="toolbar-btn blue" type="button" id="exportBtn">导出</button>
        </div>
        <div class="table-wrapper">
            <table class="data-table">
                <thead>
                    <tr>
                        <th>id</th>
                        <th>temperature</th>
                        <th>humidity</th>
                        <th>name</th>
                        <th>device</th>
                        <th>type</th>
                        <th>status</th>
                        <th>createtime</th>
                        <th>updatetime</th>
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
</div>
        `;
    }

    buildFilterRow(fieldValue = '', operatorValue = '', valueValue = '') {
        return `
            <div class="filter-row">
                <div class="filter-field">
                    <span class="filter-label">字段</span>
                    <input class="filter-input" type="text" value="${fieldValue}" />
                </div>
                <div class="filter-field">
                    <span class="filter-label">运算符</span>
                    <input class="filter-input" type="text" value="${operatorValue}" />
                </div>
                <div class="filter-field">
                    <span class="filter-label">值</span>
                    <input class="filter-input" type="text" value="${valueValue}" placeholder="请输入" />
                </div>
                <button class="filter-remove" type="button">⊖</button>
            </div>
        `;
    }

    getFormModalBody(defaults = {}) {
        const values = {
            name: defaults.name || 'XXXXXXXX',
            device: defaults.device || 'XXXXXXXX',
            temperature: defaults.temperature || '3145',
            humidity: defaults.humidity || '3145'
        };
        return `
            <div class="modal-form">
                <div class="modal-form-row">
                    <span class="modal-label">name :</span>
                    <input class="modal-input" type="text" value="${values.name}" />
                </div>
                <div class="modal-form-row">
                    <span class="modal-label">device :</span>
                    <input class="modal-input" type="text" value="${values.device}" />
                </div>
                <div class="modal-form-row">
                    <span class="modal-label">temperature :</span>
                    <input class="modal-input" type="text" value="${values.temperature}" />
                </div>
                <div class="modal-form-row">
                    <span class="modal-label">humidity :</span>
                    <input class="modal-input" type="text" value="${values.humidity}" />
                </div>
            </div>
        `;
    }

    getImportModalBody() {
        return `
            <div class="modal-import">
                <div class="import-area">
                    <div class="import-icon">📁</div>
                    <p>点击选择文件或拖拽文件到此处</p>
                    <input type="file" id="fileInput" accept=".csv,.xlsx,.xls" style="display: none;">
                </div>
            </div>
        `;
    }

    seedData() {
        this.data = Array.from({ length: 100 }, (_, i) => ({
            id: i + 1,
            temperature: Math.floor(Math.random() * 50) + 2800,
            humidity: Math.floor(Math.random() * 40) + 30,
            name: `设备${i + 1}`,
            device: `DEV-${String(i + 1).padStart(4, '0')}`,
            type: ['传感器', '控制器', '执行器'][Math.floor(Math.random() * 3)],
            status: ['正常', '警告', '故障'][Math.floor(Math.random() * 3)],
            createtime: new Date(Date.now() - Math.random() * 30 * 24 * 60 * 60 * 1000).toISOString().split('T')[0],
            updatetime: new Date(Date.now() - Math.random() * 7 * 24 * 60 * 60 * 1000).toISOString().split('T')[0]
        }));
    }

    renderTable() {
        const tbody = this.shadowRoot.getElementById('tableBody');
        if (!tbody) return;

        const start = (this.currentPage - 1) * this.pageSize;
        const end = start + this.pageSize;
        const pageData = this.data.slice(start, end);

        tbody.innerHTML = pageData.map(row => `
            <tr>
                <td>${row.id}</td>
                <td>${row.temperature}</td>
                <td>${row.humidity}</td>
                <td>${row.name}</td>
                <td>${row.device}</td>
                <td>${row.type}</td>
                <td>${row.status}</td>
                <td>${row.createtime}</td>
                <td>${row.updatetime}</td>
                <td class="action" data-id="${row.id}">删除</td>
            </tr>
        `).join('');

        this.renderPagination();
    }

    renderPagination() {
        const totalPages = Math.ceil(this.data.length / this.pageSize);
        const pageList = this.shadowRoot.getElementById('pageList');
        const prevBtn = this.shadowRoot.getElementById('prevPage');
        const nextBtn = this.shadowRoot.getElementById('nextPage');

        if (!pageList || !prevBtn || !nextBtn) return;

        // 渲染页码
        let pages = [];
        const maxVisible = 5;
        let start = Math.max(1, this.currentPage - Math.floor(maxVisible / 2));
        let end = Math.min(totalPages, start + maxVisible - 1);

        if (end - start + 1 < maxVisible) {
            start = Math.max(1, end - maxVisible + 1);
        }

        for (let i = start; i <= end; i++) {
            pages.push(`<div class="page-item ${i === this.currentPage ? 'active' : ''}" data-page="${i}">${i}</div>`);
        }

        pageList.innerHTML = pages.join('');

        // 更新按钮状态
        prevBtn.disabled = this.currentPage === 1;
        nextBtn.disabled = this.currentPage === totalPages;
    }

    bindEvents() {
        const filterRows = this.shadowRoot.getElementById('filterRows');
        const addFilter = this.shadowRoot.getElementById('addFilter');
        const resetFilters = this.shadowRoot.getElementById('resetFilters');
        const applyFilters = this.shadowRoot.getElementById('applyFilters');
        const addRowBtn = this.shadowRoot.getElementById('addRowBtn');
        const importBtn = this.shadowRoot.getElementById('importBtn');
        const exportBtn = this.shadowRoot.getElementById('exportBtn');
        const modalMask = this.shadowRoot.getElementById('modalMask');
        const modalClose = this.shadowRoot.getElementById('modalClose');

        if (addFilter && filterRows) {
            addFilter.addEventListener('click', () => {
                filterRows.insertAdjacentHTML('beforeend', this.buildFilterRow('', '', ''));
            });
        }

        if (filterRows) {
            filterRows.addEventListener('click', (event) => {
                if (event.target.classList.contains('filter-remove')) {
                    event.target.parentElement.remove();
                }
            });
        }

        if (resetFilters && filterRows) {
            resetFilters.addEventListener('click', () => {
                filterRows.innerHTML = this.buildFilterRow('temperature', '=', '3145') + 
                                     this.buildFilterRow('humidity', '=', '3145') + 
                                     this.buildFilterRow('时间戳', '包含', '');
            });
        }

        if (applyFilters) {
            applyFilters.addEventListener('click', () => {
                this.showModal('查询结果', `找到 ${this.data.length} 条符合条件的记录`);
            });
        }

        if (addRowBtn) {
            addRowBtn.addEventListener('click', () => {
                this.showModal('新增记录', this.getFormModalBody(), [
                    { text: '取消', class: 'modal-btn secondary', action: 'close' },
                    { text: '确认', class: 'modal-btn primary', action: 'submit' }
                ]);
            });
        }

        if (importBtn) {
            importBtn.addEventListener('click', () => {
                this.showModal('导入数据', this.getImportModalBody(), [
                    { text: '取消', class: 'modal-btn secondary', action: 'close' },
                    { text: '导入', class: 'modal-btn primary', action: 'import' }
                ]);
            });
        }

        if (exportBtn) {
            exportBtn.addEventListener('click', () => {
                this.showModal('导出成功', `已导出 ${this.data.length} 条记录`);
            });
        }

        if (modalClose && modalMask) {
            modalClose.addEventListener('click', () => {
                this.hideModal();
            });
        }

        if (modalMask) {
            modalMask.addEventListener('click', (event) => {
                if (event.target === modalMask) {
                    this.hideModal();
                }
            });
        }

        // 分页事件
        const pageList = this.shadowRoot.getElementById('pageList');
        const prevBtn = this.shadowRoot.getElementById('prevPage');
        const nextBtn = this.shadowRoot.getElementById('nextPage');

        if (pageList) {
            pageList.addEventListener('click', (event) => {
                if (event.target.classList.contains('page-item')) {
                    this.currentPage = parseInt(event.target.dataset.page);
                    this.renderTable();
                }
            });
        }

        if (prevBtn) {
            prevBtn.addEventListener('click', () => {
                if (this.currentPage > 1) {
                    this.currentPage--;
                    this.renderTable();
                }
            });
        }

        if (nextBtn) {
            nextBtn.addEventListener('click', () => {
                const totalPages = Math.ceil(this.data.length / this.pageSize);
                if (this.currentPage < totalPages) {
                    this.currentPage++;
                    this.renderTable();
                }
            });
        }

        // 表格行操作
        const tbody = this.shadowRoot.getElementById('tableBody');
        if (tbody) {
            tbody.addEventListener('click', (event) => {
                if (event.target.classList.contains('action')) {
                    const id = event.target.dataset.id;
                    this.showModal('删除确认', `确定要删除 ID 为 ${id} 的记录吗？`, [
                        { text: '取消', class: 'modal-btn secondary', action: 'close' },
                        { text: '删除', class: 'modal-btn primary', action: 'delete', id }
                    ]);
                }
            });
        }
    }

    showModal(title, content, buttons = []) {
        const modalMask = this.shadowRoot.getElementById('modalMask');
        const modalTitle = this.shadowRoot.getElementById('modalTitle');
        const modalBody = this.shadowRoot.getElementById('modalBody');
        const modalFooter = this.shadowRoot.getElementById('modalFooter');

        if (!modalMask || !modalTitle || !modalBody || !modalFooter) {
            console.error('Modal elements not found');
            return;
        }

        modalTitle.textContent = title;
        modalBody.innerHTML = content;

        if (buttons.length > 0) {
            modalFooter.innerHTML = buttons.map(btn => 
                `<button class="${btn.class}" data-action="${btn.action}" ${btn.id ? `data-id="${btn.id}"` : ''}>${btn.text}</button>`
            ).join('');

            // 移除旧的事件监听器并添加新的
            modalFooter.replaceWith(modalFooter.cloneNode(true));
            const newModalFooter = this.shadowRoot.getElementById('modalFooter');
            
            newModalFooter.addEventListener('click', (event) => {
                const action = event.target.dataset.action;
                const id = event.target.dataset.id;

                if (action === 'close') {
                    this.hideModal();
                } else if (action === 'submit') {
                    this.showModal('成功', '记录已添加');
                } else if (action === 'import') {
                    this.showModal('成功', '数据导入完成');
                } else if (action === 'delete' && id) {
                    this.data = this.data.filter(row => row.id != id);
                    this.renderTable();
                    this.showModal('成功', '记录已删除');
                }
            });
        } else {
            modalFooter.innerHTML = '';
        }

        this.showModalMask();
    }

    showModalMask() {
        const modalMask = this.shadowRoot.getElementById('modalMask');
        if (modalMask) {
            modalMask.hidden = false;
            modalMask.style.display = 'flex';
        }
    }

    hideModal() {
        const modalMask = this.shadowRoot.getElementById('modalMask');
        if (modalMask) {
            modalMask.hidden = true;
            modalMask.style.display = 'none';
        }
    }

    show() {
        this.setAttribute('show', '');
    }

    hide() {
        this.removeAttribute('show');
    }
}

customElements.define('database-table', DatabaseTable);
