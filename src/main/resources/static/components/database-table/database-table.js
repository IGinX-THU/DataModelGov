class DatabaseTable extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });
        this.data = [];
        this.pageSize = 6;
        this.currentPage = 1;
    }

    async connectedCallback() {
        this.loadTemplate();
        this.seedData();
        this.renderTable();
        this.bindEvents();
        const modalMask = this.shadowRoot.getElementById('modalMask');
        if (modalMask) {
            modalMask.hidden = true;
        }
    }

    loadTemplate() {
        const html = this.getTemplate();
        const style = this.getStyle();
        this.shadowRoot.innerHTML = `<style>${style}</style>${html}`;
    }

    getTemplate() {
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

    getStyle() {
        return `
            ${this.inlineStyles}
        `;
    }

    get inlineStyles() {
        return `
            ${this.constructor.styles}
        `;
    }

    static styles = String.raw`
:host {
    display: none;
    width: 100%;
    height: 100%;
}

:host([show]) {
    display: block;
}

.db-table {
    padding: 16px 24px 24px;
    font-family: "Segoe UI", "PingFang SC", "Microsoft YaHei", sans-serif;
    color: #2b2f36;
}

.db-filter-card {
    background: #fff;
    border-radius: 6px;
    border: 1px solid #edf0f5;
    padding: 16px 20px 12px;
    box-shadow: 0 1px 2px rgba(15, 23, 42, 0.05);
}

.filter-header {
    font-size: 13px;
    color: #6b7280;
    margin-bottom: 10px;
}

.filter-rows {
    display: flex;
    flex-direction: column;
    gap: 10px;
}

.filter-row {
    display: grid;
    grid-template-columns: 1fr 1fr 1fr 32px;
    gap: 16px;
    align-items: center;
}

.filter-field {
    display: flex;
    align-items: center;
    gap: 10px;
}

.filter-label {
    min-width: 42px;
    color: #5f6b7a;
    font-size: 12px;
}

.filter-input {
    flex: 1;
    border: 1px solid #e2e6ef;
    border-radius: 4px;
    padding: 6px 10px;
    font-size: 12px;
    color: #2b2f36;
    background: #fafbff;
}

.filter-remove {
    border: none;
    background: transparent;
    color: #ff6b6b;
    font-size: 18px;
    cursor: pointer;
}

.filter-actions {
    display: flex;
    align-items: center;
    gap: 12px;
    margin-top: 10px;
}

.filter-add {
    border: none;
    background: #f1f4f9;
    color: #37b26c;
    font-size: 18px;
    width: 28px;
    height: 28px;
    border-radius: 50%;
    cursor: pointer;
}

.filter-spacer {
    flex: 1;
}

.filter-btn {
    border-radius: 4px;
    padding: 6px 18px;
    font-size: 12px;
    cursor: pointer;
    border: 1px solid transparent;
}

.filter-btn.outline {
    background: #fff;
    border-color: #4c89ff;
    color: #4c89ff;
}

.filter-btn.solid {
    background: #4c89ff;
    color: #fff;
}

.db-table-card {
    margin-top: 18px;
    background: #fff;
    border-radius: 6px;
    border: 1px solid #edf0f5;
    padding: 16px 18px 12px;
}

.table-toolbar {
    display: flex;
    gap: 8px;
    margin-bottom: 12px;
}

.toolbar-btn {
    border: none;
    border-radius: 4px;
    padding: 6px 16px;
    font-size: 12px;
    color: #fff;
    cursor: pointer;
}

.toolbar-btn.green { background: #37b26c; }
.toolbar-btn.orange { background: #f4a340; }
.toolbar-btn.blue { background: #4c89ff; }

.table-wrapper {
    border: 1px solid #eef1f6;
    border-radius: 4px;
    overflow: hidden;
}

.data-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 12px;
}

.data-table th,
.data-table td {
    padding: 10px 8px;
    border-bottom: 1px solid #eef1f6;
    text-align: left;
}

.data-table th {
    background: #f7f8fb;
    color: #6b7280;
    font-weight: 600;
}

.data-table td {
    color: #4b5563;
}

.data-table td.action {
    color: #ff6b6b;
    cursor: pointer;
}

.pagination {
    display: flex;
    justify-content: flex-end;
    align-items: center;
    gap: 6px;
    padding: 10px 6px 4px;
}

.page-btn {
    border: 1px solid #e2e6ef;
    background: #fff;
    border-radius: 4px;
    width: 28px;
    height: 28px;
    cursor: pointer;
}

.page-list {
    display: flex;
    gap: 6px;
}

.page-item {
    border: 1px solid #e2e6ef;
    border-radius: 4px;
    width: 28px;
    height: 28px;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 12px;
    cursor: pointer;
    color: #6b7280;
}

.page-item.active {
    background: #4c89ff;
    color: #fff;
    border-color: #4c89ff;
}

.modal-mask {
    position: fixed;
    inset: 0;
    background: rgba(15, 23, 42, 0.35);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 2000;
}

.modal-mask[hidden] {
    display: none;
}

.modal {
    width: 420px;
    background: #fff;
    border-radius: 8px;
    box-shadow: 0 12px 32px rgba(15, 23, 42, 0.2);
}

.modal-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 14px 16px;
    border-bottom: 1px solid #eef1f6;
    font-size: 14px;
}

.modal-close {
    border: none;
    background: transparent;
    font-size: 18px;
    cursor: pointer;
}

.modal-body {
    padding: 16px;
    font-size: 13px;
    color: #4b5563;
}

.modal-footer {
    padding: 12px 16px 16px;
    display: flex;
    justify-content: flex-end;
    gap: 8px;
}

.modal-btn {
    padding: 6px 14px;
    border-radius: 4px;
    border: 1px solid #e2e6ef;
    background: #fff;
    cursor: pointer;
    font-size: 12px;
}

.modal-btn.primary {
    background: #4c89ff;
    color: #fff;
    border-color: #4c89ff;
}
`;
    
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

    seedData() {
        this.data = Array.from({ length: 18 }).map((_, index) => ({
            id: index + 1,
            temperature: '3145',
            humidity: '3145',
            name: 'XXXXXXXX',
            device: 'XXXXXXXX',
            type: 'XXXXXXXX',
            status: 'XXXXXXXX',
            createtime: '2022-08-04',
            updatetime: '2022-08-04'
        }));
    }

    renderTable() {
        const body = this.shadowRoot.getElementById('tableBody');
        const start = (this.currentPage - 1) * this.pageSize;
        const pageData = this.data.slice(start, start + this.pageSize);
        body.innerHTML = pageData
            .map((row) => `
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
                    <td class="action">
                        <span class="edit-btn" data-id="${row.id}">编辑</span>
                        <span class="delete-btn" data-id="${row.id}">删除</span>
                    </td>
                </tr>
            `)
            .join('');
        this.renderPagination();
    }

    renderPagination() {
        const pageList = this.shadowRoot.getElementById('pageList');
        const totalPages = Math.ceil(this.data.length / this.pageSize);
        const items = Array.from({ length: totalPages }).map((_, idx) => {
            const page = idx + 1;
            return `<div class="page-item ${page === this.currentPage ? 'active' : ''}" data-page="${page}">${page}</div>`;
        });
        pageList.innerHTML = items.join('');
    }

    bindEvents() {
        const filterRows = this.shadowRoot.getElementById('filterRows');
        const addFilter = this.shadowRoot.getElementById('addFilter');
        const pageList = this.shadowRoot.getElementById('pageList');
        const prev = this.shadowRoot.getElementById('prevPage');
        const next = this.shadowRoot.getElementById('nextPage');
        const reset = this.shadowRoot.getElementById('resetFilters');
        const apply = this.shadowRoot.getElementById('applyFilters');
        const addRowBtn = this.shadowRoot.getElementById('addRowBtn');
        const importBtn = this.shadowRoot.getElementById('importBtn');
        const exportBtn = this.shadowRoot.getElementById('exportBtn');
        const modalMask = this.shadowRoot.getElementById('modalMask');
        const modalClose = this.shadowRoot.getElementById('modalClose');

        addFilter.addEventListener('click', () => {
            filterRows.insertAdjacentHTML('beforeend', this.buildFilterRow('', '', ''));
        });

        filterRows.addEventListener('click', (event) => {
            const target = event.target.closest('.filter-remove');
            if (!target) return;
            const row = target.closest('.filter-row');
            if (row && filterRows.children.length > 1) {
                row.remove();
            }
        });

        pageList.addEventListener('click', (event) => {
            const target = event.target.closest('.page-item');
            if (!target) return;
            this.currentPage = Number(target.dataset.page);
            this.renderTable();
        });

        prev.addEventListener('click', () => {
            if (this.currentPage > 1) {
                this.currentPage -= 1;
                this.renderTable();
            }
        });

        next.addEventListener('click', () => {
            const totalPages = Math.ceil(this.data.length / this.pageSize);
            if (this.currentPage < totalPages) {
                this.currentPage += 1;
                this.renderTable();
            }
        });

        reset.addEventListener('click', () => {
            filterRows.innerHTML = this.buildFilterRow('temperature', '=', '3145') + this.buildFilterRow('humidity', '=', '3145') + this.buildFilterRow('时间戳', '包含', '');
        });

        apply.addEventListener('click', () => {
            this.currentPage = 1;
            this.renderTable();
        });

        addRowBtn.addEventListener('click', () => this.openModal('新增', '这里是新增表单示例', ['取消', '确定']));
        importBtn.addEventListener('click', () => this.openModal('导入', '这里是导入弹窗示例', ['取消', '确定']));
        exportBtn.addEventListener('click', () => this.openModal('导出', '这里是导出弹窗示例', ['取消', '确定']));

        this.shadowRoot.addEventListener('click', (event) => {
            const editBtn = event.target.closest('.edit-btn');
            const deleteBtn = event.target.closest('.delete-btn');
            if (editBtn) {
                this.openModal('编辑', `编辑记录 ID: ${editBtn.dataset.id}`, ['取消', '保存']);
            }
            if (deleteBtn) {
                this.openModal('删除', `确认删除记录 ID: ${deleteBtn.dataset.id}？`, ['取消', '确认删除']);
            }
        });

        modalClose.addEventListener('click', () => this.closeModal());
        modalMask.addEventListener('click', (event) => {
            if (event.target === modalMask) {
                this.closeModal();
            }
        });

        document.addEventListener('keydown', (event) => {
            if (event.key === 'Escape') {
                this.closeModal();
            }
        });
    }

    openModal(title, bodyText, actions) {
        const modalMask = this.shadowRoot.getElementById('modalMask');
        const modalTitle = this.shadowRoot.getElementById('modalTitle');
        const modalBody = this.shadowRoot.getElementById('modalBody');
        const modalFooter = this.shadowRoot.getElementById('modalFooter');
        modalTitle.textContent = title;
        modalBody.textContent = bodyText;
        modalFooter.innerHTML = actions
            .map((label, index) => `<button class="modal-btn ${index === actions.length - 1 ? 'primary' : ''}">${label}</button>`)
            .join('');
        modalMask.hidden = false;
        modalFooter.querySelectorAll('button').forEach((btn) => {
            btn.addEventListener('click', () => this.closeModal(), { once: true });
        });
    }

    closeModal() {
        const modalMask = this.shadowRoot.getElementById('modalMask');
        modalMask.hidden = true;
    }

    show() {
        this.setAttribute('show', '');
    }

    hide() {
        this.removeAttribute('show');
    }
}

customElements.define('database-table', DatabaseTable);
