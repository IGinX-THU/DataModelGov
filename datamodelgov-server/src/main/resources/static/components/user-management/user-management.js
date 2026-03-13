class UserManagement extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });
        this.users = [];
        this.pageSize = 10;
        this.currentPage = 1;
        this.totalCount = 0;
        this.currentEditUser = null;
    }

    async connectedCallback() {
        await this.loadResources();
        
        // 初始化分页组件
        this.initPagination();
        
        setTimeout(() => {
            const modalMask = this.shadowRoot.getElementById('modalMask');
            if (modalMask) {
                modalMask.hidden = true;
                modalMask.style.display = 'none';
            }
            this.bindEvents();
        }, 100);
    }

    // 添加show方法供main.js调用 - 参考数据源管理的实现
    async show(...args) {
        console.log('UserManagement show() 被调用', args);
        this.style.display = 'block';
        // 每次显示时刷新数据
        await this.loadUsers();
        this.renderTable();
    }

    async loadResources() {
        try {
            const cssLink = document.createElement('link');
            cssLink.rel = 'stylesheet';
            cssLink.href = './components/user-management/user-management.css';
            this.shadowRoot.appendChild(cssLink);
        } catch (error) {
            console.error('Failed to load CSS:', error);
        }

        if (window.location.protocol === 'file:') {
            this.shadowRoot.innerHTML += this.getFallbackHTML();
        } else {
            try {
                const response = await fetch('./components/user-management/user-management.html');
                if (!response.ok) {
                    throw new Error(`HTTP error! status: ${response.status}`);
                }
                const html = await response.text();
                this.shadowRoot.innerHTML += html;
                console.log('User management HTML template loaded successfully');
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
            <div class="filter-row">
                <div class="filter-field">
                    <span class="filter-label">用户名</span>
                    <input class="filter-input" type="text" placeholder="请输入用户名" id="usernameFilter" />
                </div>
                <div class="filter-field">
                    <span class="filter-label">角色</span>
                    <select class="filter-input" id="roleFilter">
                        <option value="">全部</option>
                        <option value="ADMIN">管理员</option>
                        <option value="DATA_ENGINEER">数据工程师</option>
                        <option value="MODEL_ENGINEER">模型工程师</option>
                        <option value="SIMULATION_ENGINEER">仿真工程师</option>
                    </select>
                </div>
            </div>
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
            <button class="toolbar-btn green" type="button" id="addUserBtn">新增</button>
        </div>
        <div class="table-wrapper">
            <table class="data-table">
                <thead>
                    <tr>
                        <th>用户名</th>
                        <th>角色</th>
                        <th>状态</th>
                        <th>创建时间</th>
                        <th>操作</th>
                    </tr>
                </thead>
                <tbody id="tableBody"></tbody>
            </table>
        </div>
        <common-pagination id="pagination"></common-pagination>
    </div>

    <!-- 用户编辑模态框 -->
    <div class="modal-mask" id="modalMask" hidden>
        <div class="modal-container">
            <div class="modal-header">
                <h3 class="modal-title" id="modalTitle">新增用户</h3>
                <button class="close-btn" id="closeModal">&times;</button>
            </div>
            <div class="modal-body">
                <form id="userForm">
                    <input type="hidden" id="userId" />
                    <div class="form-group">
                        <label class="form-label required">用户名</label>
                        <input type="text" class="form-control" id="username" placeholder="请输入用户名" required />
                    </div>
                    <div class="form-group">
                        <label class="form-label required" id="passwordLabel">密码</label>
                        <input type="password" class="form-control" id="password" placeholder="请输入密码" />
                    </div>
                    <div class="form-group">
                        <label class="form-label required">角色</label>
                        <select class="form-control form-select" id="role" required>
                            <option value="">请选择角色</option>
                            <option value="ADMIN">管理员</option>
                            <option value="DATA_ENGINEER">数据工程师</option>
                            <option value="MODEL_ENGINEER">模型工程师</option>
                            <option value="SIMULATION_ENGINEER">仿真工程师</option>
                        </select>
                    </div>
                    <div class="form-group">
                        <label class="form-label">状态</label>
                        <select class="form-control form-select" id="enabled">
                            <option value="true">启用</option>
                            <option value="false">禁用</option>
                        </select>
                    </div>
                </form>
            </div>
            <div class="modal-footer">
                <button class="btn secondary" type="button" id="cancelBtn">取消</button>
                <button class="btn primary" type="button" id="saveBtn">保存</button>
            </div>
        </div>
    </div>
</div>
        `;
    }

    bindEvents() {
        // 查询按钮
        this.shadowRoot.getElementById('applyFilters')?.addEventListener('click', () => {
            this.currentPage = 1;
            this.loadUsers();
        });

        // 重置按钮
        this.shadowRoot.getElementById('resetFilters')?.addEventListener('click', () => {
            this.shadowRoot.getElementById('usernameFilter').value = '';
            this.shadowRoot.getElementById('roleFilter').value = '';
            this.shadowRoot.getElementById('statusFilter').value = '';
            this.currentPage = 1;
            this.loadUsers();
        });

        // 新增用户按钮
        this.shadowRoot.getElementById('addUserBtn')?.addEventListener('click', () => {
            this.showAddUserModal();
        });

        // 模态框事件
        this.shadowRoot.getElementById('closeModal')?.addEventListener('click', () => this.hideModal());
        this.shadowRoot.getElementById('cancelBtn')?.addEventListener('click', () => this.hideModal());
        this.shadowRoot.getElementById('saveBtn')?.addEventListener('click', () => this.saveUser());
        
        // 移除点击遮罩关闭功能，避免误操作
        // this.shadowRoot.getElementById('modalMask')?.addEventListener('click', (e) => {
        //     if (e.target === this.shadowRoot.getElementById('modalMask')) {
        //         this.hideModal();
        //     }
        // });
    }

    async loadUsers() {
        try {
            // 获取筛选条件 - 完全参考AssociationRules
            const usernameFilter = this.shadowRoot.getElementById('usernameFilter')?.value.trim();
            const roleFilter = this.shadowRoot.getElementById('roleFilter')?.value;
            const statusFilter = this.shadowRoot.getElementById('statusFilter')?.value;

            // 构建请求对象 - 完全参考AssociationRules
            const requestBody = {
                page: this.currentPage || 1,
                pageSize: this.pageSize || 10,
                username: usernameFilter || null,
                role: roleFilter || null,
                enabled: statusFilter || null
            };
            
            console.log('查询参数:', requestBody);
            
            // 调用查询接口 - 完全参考AssociationRules
            const result = await window.AppConfig.post('userManagement', 'query', requestBody);
            console.log('查询结果:', result);

            if (result.success && result.data) {
                // 后端直接返回List<UserEntity>，转换为前端所需格式
                this.users = result.data.map(user => {
                    console.log('用户数据:', user); // 调试日志
                    return {
                        username: user.username,
                        role: user.role,
                        enabled: user.enabled, // 保持布尔值
                        timestamp: user.timestamp
                    };
                });
                this.renderTable();
                this.loadTotalCount();
            } else {
                this.showToast('加载用户列表失败: ' + (result.message || '未知错误'), 'error');
            }
        } catch (error) {
            console.error('加载用户列表失败:', error);
            this.showToast('加载用户列表失败', 'error');
        }
    }

    async loadTotalCount() {
        try {
            // 获取筛选条件 - 完全参考AssociationRules
            const usernameFilter = this.shadowRoot.getElementById('usernameFilter')?.value.trim();
            const roleFilter = this.shadowRoot.getElementById('roleFilter')?.value;
            const statusFilter = this.shadowRoot.getElementById('statusFilter')?.value;

            // 构建请求对象 - 完全参考AssociationRules
            const requestBody = {
                username: usernameFilter || null,
                role: roleFilter || null,
                enabled: statusFilter || null
            };
            
            console.log('计数查询参数:', requestBody);
            
            // 调用计数接口 - 完全参考AssociationRules
            const result = await window.AppConfig.post('userManagement', 'count', requestBody);
            console.log('计数查询结果:', result);

            if (result.success && result.data) {
                this.totalCount = result.data.count || 0;
                this.updatePagination();
            }
        } catch (error) {
            console.error('加载用户总数失败:', error);
        }
    }

    renderTable() {
        const tableBody = this.shadowRoot.getElementById('tableBody');
        if (!tableBody) return;
        
        tableBody.innerHTML = '';

        this.users.forEach(user => {
            const row = document.createElement('tr');
            row.innerHTML = `
                <td>${user.username}</td>
                <td>${this.getRoleDisplayName(user.role)}</td>
                <td>${user.enabled ? '启用' : '禁用'}</td>
                <td>${this.formatTimestamp(user.timestamp)}</td>
                <td>
                    <button class="table-btn edit" data-username="${user.username}">编辑</button>
                    <button class="table-btn delete" data-username="${user.username}">删除</button>
                </td>
            `;
            
            // 绑定事件
            const editBtn = row.querySelector('.table-btn.edit');
            const deleteBtn = row.querySelector('.table-btn.delete');
            
            if (editBtn) {
                editBtn.addEventListener('click', () => {
                    this.editUser(user.username);
                });
            }
            
            if (deleteBtn) {
                deleteBtn.addEventListener('click', () => {
                    this.deleteUser(user.username);
                });
            }
            
            tableBody.appendChild(row);
        });
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
            // 监听分页变化事件（如果有自定义分页组件）
            pagination.addEventListener('pagination-change', (event) => {
                const { currentPage, pageSize } = event.detail;
                this.currentPage = currentPage;
                this.pageSize = pageSize;
                this.loadUsers();
            });
            
            // 初始化分页
            this.updatePagination();
        }
    }

    showAddUserModal() {
        this.currentEditUser = null;
        const modalTitle = this.shadowRoot.getElementById('modalTitle');
        const userId = this.shadowRoot.getElementById('userId');
        const username = this.shadowRoot.getElementById('username');
        const password = this.shadowRoot.getElementById('password');
        const passwordLabel = this.shadowRoot.getElementById('passwordLabel');
        const role = this.shadowRoot.getElementById('role');
        const enabled = this.shadowRoot.getElementById('enabled');
        const modalMask = this.shadowRoot.getElementById('modalMask');
        
        if (modalTitle) modalTitle.textContent = '新增用户';
        if (userId) userId.value = '';
        if (username) username.value = '';
        if (password) password.value = '';
        if (passwordLabel) passwordLabel.textContent = '密码';
        if (password) password.required = true;
        if (role) role.value = '';
        if (enabled) enabled.value = 'true';
        if (modalMask) {
            modalMask.hidden = false;
            modalMask.style.display = 'flex';
        }
    }

    async editUser(username) {
        try {
            // 调用查询接口 - 完全参考AssociationRules
            const result = await window.AppConfig.get('userManagement', 'detail', { username: encodeURIComponent(username) });
            console.log('查询用户结果:', result);
            
            if (result.success) {
                this.currentEditUser = result.data;
                
                const modalTitle = this.shadowRoot.getElementById('modalTitle');
                const userId = this.shadowRoot.getElementById('userId');
                const usernameInput = this.shadowRoot.getElementById('username');
                const password = this.shadowRoot.getElementById('password');
                const passwordLabel = this.shadowRoot.getElementById('passwordLabel');
                const role = this.shadowRoot.getElementById('role');
                const enabled = this.shadowRoot.getElementById('enabled');
                const modalMask = this.shadowRoot.getElementById('modalMask');
                
                if (modalTitle) modalTitle.textContent = '编辑用户';
                if (userId) userId.value = this.currentEditUser.username;
                if (usernameInput) {
                    usernameInput.value = this.currentEditUser.username;
                    usernameInput.disabled = true;
                }
                if (passwordLabel) passwordLabel.textContent = '新密码（留空则不修改）';
                if (password) {
                    password.value = '';
                    password.required = false;
                }
                if (role) role.value = this.currentEditUser.role;
                if (enabled) enabled.value = this.currentEditUser.enabled.toString();
                if (modalMask) {
                    modalMask.hidden = false;
                    modalMask.style.display = 'flex';
                }
            } else {
                this.showToast('获取用户信息失败: ' + result.message, 'error');
            }
        } catch (error) {
            console.error('获取用户信息失败:', error);
            this.showToast('获取用户信息失败', 'error');
        }
    }

    async saveUser() {
        const form = this.shadowRoot.getElementById('userForm');
        if (form && !form.checkValidity()) {
            form.reportValidity();
            return;
        }

        const username = this.shadowRoot.getElementById('username')?.value;
        const password = this.shadowRoot.getElementById('password')?.value;
        const role = this.shadowRoot.getElementById('role')?.value;
        const enabled = this.shadowRoot.getElementById('enabled')?.value === 'true';

        const userData = {
            username: username,
            role: role,
            enabled: enabled,
            timestamp: this.currentEditUser ? this.currentEditUser.timestamp : Date.now()
        };
        
        // 如果是新增用户或有密码输入，则包含密码字段
        if (!this.currentEditUser || (password && password.trim() !== '')) {
            userData.password = password;
        }

        try {
            const url = this.currentEditUser ? 'update' : 'save';
            
            // 调用保存接口 - 完全参考AssociationRules
            const result = await window.AppConfig.post('userManagement', url, userData);
            console.log('保存用户结果:', result);

            if (result.success) {
                this.showToast(`用户已${this.currentEditUser ? '更新' : '添加'}成功`);
                this.hideModal();
                this.loadUsers();
            } else {
                this.showToast('保存失败: ' + (result.message || '未知错误'), 'error');
            }
        } catch (error) {
            console.error('保存用户失败:', error);
            this.showToast('保存用户失败', 'error');
        }
    }

    async deleteUser(username) {
        // 使用 showModal 显示删除确认 - 完全参考AssociationRules
        this.showModal('删除确认', `确定要删除用户 "${username}" 吗？`, [
            { text: '取消', class: 'modal-btn secondary', action: 'close' },
            { text: '删除', class: 'modal-btn primary', action: 'delete', id: username }
        ]);
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

        // Store the current state
        const previousState = {
            title: modalTitle.textContent,
            body: modalBody.innerHTML,
            footer: modalFooter.innerHTML
        };

        // Update modal content
        modalTitle.textContent = title;
        modalBody.innerHTML = content;

        // Handle buttons
        if (buttons.length === 0) {
            // Default close button
            modalFooter.innerHTML = `<button type="button" class="modal-btn secondary" id="modalClose">关闭</button>`;
        } else {
            modalFooter.innerHTML = buttons.map(btn => 
                `<button type="button" class="modal-btn ${btn.class}" data-action="${btn.action}" data-id="${btn.id || ''}">${btn.text}</button>`
            ).join('');
        }

        // Show modal
        modalMask.hidden = false;
        modalMask.style.display = 'flex';

        // Handle button clicks
        const handleModalClick = (e) => {
            const action = e.target.dataset.action;
            const id = e.target.dataset.id;
            
            if (action === 'close') {
                this.hideModal();
                // Restore previous state
                modalTitle.textContent = previousState.title;
                modalBody.innerHTML = previousState.body;
                modalFooter.innerHTML = previousState.footer;
            } else if (action === 'delete' && id) {
                this.deleteUserFromAPI(id);
                // 删除操作后不需要恢复之前的状态，直接关闭弹窗
            }
            
            // Remove event listener
            modalFooter.removeEventListener('click', handleModalClick);
        };

        modalFooter.addEventListener('click', handleModalClick);
    }

    async deleteUserFromAPI(username) {
        try {
            // 调用删除接口 - 完全参考AssociationRules
            const result = await window.AppConfig.delete('userManagement', 'delete', { username: encodeURIComponent(username) });
            console.log('删除用户结果:', result);

            if (result.success) {
                this.showToast('用户已删除');
                this.loadUsers();
                this.hideModal();
            } else {
                this.showToast(result.message || '删除失败', 'error');
            }
        } catch (error) {
            console.error('删除用户失败:', error);
            this.showToast('网络错误，删除失败', 'error');
        }
    }

    showToast(message, type = 'success') {
        if (window.CommonUtils && window.CommonUtils.showToast) {
            window.CommonUtils.showToast(message, type);
        } else {
            console.warn('CommonUtils.showToast not available, falling back to console.log');
            console[type === 'error' ? 'error' : type === 'warning' ? 'warn' : 'log'](`[${type}] ${message}`);
        }
    }

    hideModal() {
        const modalMask = this.shadowRoot.getElementById('modalMask');
        const username = this.shadowRoot.getElementById('username');
        const form = this.shadowRoot.getElementById('userForm');
        
        if (modalMask) {
            modalMask.hidden = true;
            modalMask.style.display = 'none';
        }
        if (username) username.disabled = false;
        if (form) form.reset();
    }

    hide() {
        console.log('UserManagement.hide() called');
        this.removeAttribute('show');
        this.style.display = 'none';
    }

    getRoleDisplayName(role) {
        const roleMap = {
            'ADMIN': '管理员',
            'DATA_ENGINEER': '数据工程师',
            'MODEL_ENGINEER': '模型工程师',
            'SIMULATION_ENGINEER': '仿真工程师'
        };
        return roleMap[role] || role;
    }

    formatTimestamp(timestamp) {
        if (!timestamp) return '-';
        const date = new Date(timestamp);
        return date.toLocaleString('zh-CN');
    }

    showMessage(message, type = 'info') {
        console.log(`[${type}] ${message}`);
        alert(message);
    }
}

// 注册自定义元素
customElements.define('user-management', UserManagement);
