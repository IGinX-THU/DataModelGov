/**
 * 权限管理：分页查询、编辑是否公开与可见用户（对接 /api/data-permission/query|count|update）
 */
class PermissionManagement extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });
        this.rows = [];
        this.pageSize = 10;
        this.currentPage = 1;
        this.totalCount = 0;
    }

    async connectedCallback() {
        await this.loadResources();
        setTimeout(() => {
            const modalMask = this.shadowRoot.getElementById('modalMask');
            if (modalMask) {
                modalMask.hidden = true;
                modalMask.style.display = 'none';
            }
            this.initPagination();
            this.bindEvents();
        }, 100);
    }

    async show() {
        this.style.display = 'block';
        this.currentPage = 1;
        await this.loadList();
    }

    hide() {
        this.hideModal();
        this.removeAttribute('show');
        this.style.display = 'none';
    }

    rowPrimaryKey(row) {
        if (row.id != null && row.id !== '') {
            return Number(row.id);
        }
        if (row.createTime != null && row.createTime !== '') {
            return Number(row.createTime);
        }
        return null;
    }

    async loadResources() {
        try {
            const cssLink = document.createElement('link');
            cssLink.rel = 'stylesheet';
            cssLink.href = './components/permission-management/permission-management.css';
            this.shadowRoot.appendChild(cssLink);
        } catch (error) {
            console.error('Failed to load permission-management CSS:', error);
        }

        try {
            const response = await fetch('./components/permission-management/permission-management.html');
            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }
            const html = await response.text();
            this.shadowRoot.innerHTML += html;
        } catch (error) {
            console.error('Failed to load permission-management HTML:', error);
        }
    }

    bindEvents() {
        this.shadowRoot.getElementById('applyFilters')?.addEventListener('click', () => {
            this.currentPage = 1;
            this.loadList();
        });
        this.shadowRoot.getElementById('resetFilters')?.addEventListener('click', () => {
            this.shadowRoot.getElementById('prefixFilter').value = '';
            this.currentPage = 1;
            this.loadList();
        });
        this.shadowRoot.getElementById('refreshBtn')?.addEventListener('click', () => {
            this.currentPage = 1;
            this.loadList();
        });

        this.shadowRoot.getElementById('closeModal')?.addEventListener('click', () => this.hideModal());
        this.shadowRoot.getElementById('cancelBtn')?.addEventListener('click', () => this.hideModal());
        this.shadowRoot.getElementById('saveBtn')?.addEventListener('click', () => this.savePermission());
    }

    filterPayload() {
        const prefix = this.shadowRoot.getElementById('prefixFilter')?.value.trim();
        return {
            tablePrefix: prefix || null
        };
    }

    async loadList() {
        try {
            const requestBody = {
                page: this.currentPage || 1,
                pageSize: this.pageSize || 10,
                ...this.filterPayload()
            };
            const result = await window.AppConfig.post('dataPermission', 'query', requestBody);
            if (result.success && Array.isArray(result.data)) {
                this.rows = result.data;
                this.renderTable();
                await this.loadTotalCount();
            } else {
                this.showToast('加载权限列表失败: ' + (result.message || '未知错误'), 'error');
            }
        } catch (error) {
            console.error('加载权限列表失败:', error);
            this.showToast('加载权限列表失败', 'error');
        }
    }

    async loadTotalCount() {
        try {
            const requestBody = this.filterPayload();
            const result = await window.AppConfig.post('dataPermission', 'count', requestBody);
            if (result.success && result.data) {
                this.totalCount = Number(result.data.count) || 0;
                this.updatePagination();
            }
        } catch (error) {
            console.error('加载权限总数失败:', error);
        }
    }

    renderTable() {
        const tableBody = this.shadowRoot.getElementById('tableBody');
        const emptyHint = this.shadowRoot.getElementById('emptyHint');
        if (!tableBody) {
            return;
        }

        tableBody.innerHTML = '';

        if (this.rows.length === 0) {
            if (emptyHint) {
                emptyHint.hidden = false;
            }
            return;
        }
        if (emptyHint) {
            emptyHint.hidden = true;
        }

        this.rows.forEach((row) => {
            const pk = this.rowPrimaryKey(row);
            const tr = document.createElement('tr');
            tr.innerHTML = `
                <td>${this.escapeHtml(row.tablePrefix || '')}</td>
                <td>${this.escapeHtml(row.owner || '')}</td>
                <td>${row.isPublic ? '是' : '否'}</td>
                <td>${this.escapeHtml(row.visibleUsers || '-')}</td>
                <td>${this.escapeHtml(this.truncate(row.timestampSet, 48))}</td>
                <td>${this.formatTime(row.createTime)}</td>
                <td>
                    <button class="table-btn edit" type="button" data-id="${pk != null ? pk : ''}">编辑</button>
                </td>
            `;
            const editBtn = tr.querySelector('.table-btn.edit');
            if (editBtn && pk != null) {
                editBtn.addEventListener('click', () => this.openEditModal(row));
            }
            tableBody.appendChild(tr);
        });
    }

    openEditModal(row) {
        const pk = this.rowPrimaryKey(row);
        if (pk == null) {
            this.showToast('无法识别记录主键', 'error');
            return;
        }
        const modalTitle = this.shadowRoot.getElementById('modalTitle');
        const recordId = this.shadowRoot.getElementById('recordId');
        const displayTablePrefix = this.shadowRoot.getElementById('displayTablePrefix');
        const isPublic = this.shadowRoot.getElementById('isPublic');
        const visibleUsers = this.shadowRoot.getElementById('visibleUsers');
        const modalMask = this.shadowRoot.getElementById('modalMask');

        if (modalTitle) {
            modalTitle.textContent = '编辑权限';
        }
        if (recordId) {
            recordId.value = String(pk);
        }
        if (displayTablePrefix) {
            displayTablePrefix.value = row.tablePrefix || '';
        }
        if (isPublic) {
            isPublic.value = row.isPublic ? 'true' : 'false';
        }
        if (visibleUsers) {
            visibleUsers.value = row.visibleUsers != null ? row.visibleUsers : '';
        }
        if (modalMask) {
            modalMask.hidden = false;
            modalMask.style.display = 'flex';
        }
    }

    hideModal() {
        const modalMask = this.shadowRoot.getElementById('modalMask');
        const form = this.shadowRoot.getElementById('permForm');
        if (modalMask) {
            modalMask.hidden = true;
            modalMask.style.display = 'none';
        }
        if (form) {
            form.reset();
        }
    }

    async savePermission() {
        const recordId = this.shadowRoot.getElementById('recordId')?.value;
        const isPublicEl = this.shadowRoot.getElementById('isPublic');
        const visibleUsersEl = this.shadowRoot.getElementById('visibleUsers');
        if (!recordId) {
            this.showToast('记录主键缺失', 'error');
            return;
        }
        const body = {
            id: Number(recordId),
            isPublic: isPublicEl ? isPublicEl.value === 'true' : false,
            visibleUsers: visibleUsersEl ? visibleUsersEl.value.trim() : ''
        };
        try {
            const result = await window.AppConfig.post('dataPermission', 'update', body);
            if (result.success) {
                this.showToast(result.message || '保存成功');
                this.hideModal();
                await this.loadList();
            } else {
                this.showToast(result.message || '保存失败', 'error');
            }
        } catch (error) {
            console.error('保存权限失败:', error);
            this.showToast('保存权限失败', 'error');
        }
    }

    updatePagination() {
        const pagination = this.shadowRoot.getElementById('pagination');
        if (pagination && pagination.setPagination) {
            pagination.setPagination(this.currentPage, this.pageSize, this.totalCount);
        }
    }

    initPagination() {
        const pagination = this.shadowRoot.getElementById('pagination');
        if (pagination) {
            pagination.addEventListener('pagination-change', (event) => {
                const { currentPage, pageSize } = event.detail;
                this.currentPage = currentPage;
                this.pageSize = pageSize;
                this.loadList();
            });
            this.updatePagination();
        }
    }

    truncate(s, max) {
        if (!s || s.length <= max) {
            return s || '-';
        }
        return s.slice(0, max) + '…';
    }

    escapeHtml(str) {
        if (str == null) {
            return '';
        }
        return String(str)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    formatTime(ts) {
        if (ts == null) {
            return '-';
        }
        const n = typeof ts === 'string' ? Number(ts) : ts;
        if (Number.isNaN(n)) {
            return '-';
        }
        return new Date(n).toLocaleString('zh-CN');
    }

    showToast(message, type = 'success') {
        if (window.CommonUtils && window.CommonUtils.showToast) {
            window.CommonUtils.showToast(message, type);
        } else {
            console[type === 'error' ? 'error' : 'log'](message);
        }
    }
}

customElements.define('permission-management', PermissionManagement);
