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
            this.capturePermModalTemplate();
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

    capturePermModalTemplate() {
        const modalBody = this.shadowRoot.getElementById('modalBody');
        const modalFooter = this.shadowRoot.getElementById('modalFooter');
        if (modalBody && modalFooter) {
            this._defaultPermModalSnapshot = {
                body: modalBody.innerHTML,
                footer: modalFooter.innerHTML
            };
        }
    }

    restorePermModalDom() {
        if (!this._defaultPermModalSnapshot) {
            return;
        }
        const modalBody = this.shadowRoot.getElementById('modalBody');
        const modalFooter = this.shadowRoot.getElementById('modalFooter');
        if (modalBody) {
            modalBody.innerHTML = this._defaultPermModalSnapshot.body;
        }
        if (modalFooter) {
            modalFooter.innerHTML = this._defaultPermModalSnapshot.footer;
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

        this.bindModalDelegationOnce();
    }

    bindModalDelegationOnce() {
        const mask = this.shadowRoot.getElementById('modalMask');
        if (!mask || mask.dataset.delegationBound === '1') {
            return;
        }
        mask.dataset.delegationBound = '1';
        mask.addEventListener('click', (e) => {
            const id = e.target.id;
            if (id === 'modalClose' || id === 'cancelBtn') {
                e.preventDefault();
                this.hideModal();
            } else if (id === 'saveBtn') {
                e.preventDefault();
                this.savePermission();
            }
        });
    }

    filterPayload() {
        const prefix = this.shadowRoot.getElementById('prefixFilter')?.value.trim();
        return {
            tablePrefix: prefix || null
        };
    }

    async loadList() {
        if (window.showGlobalLoading) {
            window.showGlobalLoading('正在查询数据权限...');
        }
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
        } finally {
            if (window.hideGlobalLoading) {
                window.hideGlobalLoading();
            }
        }
    }

    async loadTotalCount() {
        try {
            const requestBody = this.filterPayload();
            const result = await window.AppConfig.post('dataPermission', 'count', requestBody);
            if (result.success && result.data !== undefined && result.data !== null) {
                const raw = result.data;
                this.totalCount = typeof raw === 'object' && raw !== null && 'count' in raw
                    ? Number(raw.count) || 0
                    : Number(raw) || 0;
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

        // 检查当前用户是否是管理员
        const userRole = window.MenuPermission ? window.MenuPermission.getCurrentRole() : null;
        const isAdmin = userRole === 'ADMIN';

        this.rows.forEach((row) => {
            const pk = this.rowPrimaryKey(row);
            const tr = document.createElement('tr');
            let actionButtonsHtml = `
                <div class="action-buttons">
                    <button type="button" class="action-btn edit" data-id="${pk != null ? pk : ''}">编辑</button>
            `;
            if (isAdmin) {
                actionButtonsHtml += `
                    <button type="button" class="action-btn delete" data-table-prefix="${this.escapeHtml(row.tablePrefix || '')}">删除</button>
                `;
            }
            actionButtonsHtml += '</div>';

            tr.innerHTML = `
                <td>${this.escapeHtml(row.tablePrefix || '')}</td>
                <td>${this.escapeHtml(row.owner || '')}</td>
                <td>${row.isPublic ? '是' : '否'}</td>
                <td>${this.escapeHtml(row.visibleUsers || '-')}</td>
                <td>${this.formatTime(row.createTime)}</td>
                <td>${actionButtonsHtml}</td>
            `;
            const editBtn = tr.querySelector('.action-btn.edit');
            if (editBtn && pk != null) {
                editBtn.addEventListener('click', () => this.openEditModal(row));
            }
            const deleteBtn = tr.querySelector('.action-btn.delete');
            if (deleteBtn) {
                deleteBtn.addEventListener('click', () => this.deletePermission(row.tablePrefix));
            }
            tableBody.appendChild(tr);
        });
    }

    async openEditModal(row) {
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

        // 加载所有用户列表
        await this.loadAllUsers();

        // 设置已选中的用户
        if (visibleUsers && row.visibleUsers != null) {
            const selectedUsers = row.visibleUsers.split(',').map(u => u.trim()).filter(u => u);
            const checkboxes = visibleUsers.querySelectorAll('input[type="checkbox"]');
            checkboxes.forEach(checkbox => {
                checkbox.checked = selectedUsers.includes(checkbox.value);
            });
        }

        if (modalMask) {
            modalMask.hidden = false;
            modalMask.style.display = 'flex';
        }
    }

    async loadAllUsers() {
        const visibleUsers = this.shadowRoot.getElementById('visibleUsers');
        if (!visibleUsers) {
            return;
        }

        try {
            const result = await window.AppConfig.get('userManagement', 'all');
            if (result.success && Array.isArray(result.data)) {
                // 清空现有选项
                visibleUsers.innerHTML = '';
                // 设置网格布局
                visibleUsers.style.display = 'grid';
                visibleUsers.style.gridTemplateColumns = 'repeat(auto-fill, minmax(75px, 1fr))';
                visibleUsers.style.gap = '8px';

                // 添加用户复选框
                result.data.forEach(username => {
                    const checkboxDiv = document.createElement('div');
                    checkboxDiv.style.display = 'flex';
                    checkboxDiv.style.alignItems = 'center';

                    const checkbox = document.createElement('input');
                    checkbox.type = 'checkbox';
                    checkbox.value = username;
                    checkbox.id = `user-${username}`;
                    checkbox.style.marginRight = '6px';

                    const label = document.createElement('label');
                    label.htmlFor = `user-${username}`;
                    label.textContent = username;
                    label.style.cursor = 'pointer';

                    checkboxDiv.appendChild(checkbox);
                    checkboxDiv.appendChild(label);
                    visibleUsers.appendChild(checkboxDiv);
                });
            } else {
                this.showToast('加载用户列表失败', 'error');
            }
        } catch (error) {
            console.error('加载用户列表失败:', error);
            this.showToast('加载用户列表失败', 'error');
        }
    }

    hideModal() {
        this.restorePermModalDom();
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

        // 获取选中的用户列表
        let visibleUsers = '';
        if (visibleUsersEl) {
            const checkboxes = visibleUsersEl.querySelectorAll('input[type="checkbox"]:checked');
            visibleUsers = Array.from(checkboxes).map(checkbox => checkbox.value).join(',');
        }

        const body = {
            id: Number(recordId),
            isPublic: isPublicEl ? isPublicEl.value === 'true' : false,
            visibleUsers: visibleUsers
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

    async deletePermission(tablePrefix) {
        if (!tablePrefix) {
            this.showToast('表前缀不能为空', 'error');
            return;
        }
        const confirmed = await window.CommonUtils.confirmDialog(`确定要删除权限 "${tablePrefix}" 吗？`, '删除确认');
        if (!confirmed) {
            return;
        }
        try {
            const url = `${window.AppConfig.api.baseURL}/api/data-permission/delete/${encodeURIComponent(tablePrefix)}`;
            const response = await fetch(url, {
                method: 'DELETE',
                headers: window.AppConfig.getAuthHeaders()
            });
            const result = await response.json();
            if (result.success) {
                this.showToast(result.message || '删除成功');
                await this.loadList();
            } else {
                this.showToast(result.message || '删除失败', 'error');
            }
        } catch (error) {
            console.error('删除权限失败:', error);
            this.showToast('删除权限失败', 'error');
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