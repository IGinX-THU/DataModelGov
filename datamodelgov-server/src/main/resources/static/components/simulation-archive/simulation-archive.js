class SimulationArchiveList extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });
        this.currentPage = 1;
        this.pageSize = 10;
        this.totalCount = 0;
        this.data = [];
    }

    async connectedCallback() {
        await this.loadResources();
        this.bindEvents();
        // 不在初始化时自动加载数据，只在显示时加载
    }

    async loadResources() {
        const cssResponse = await fetch('/components/simulation-archive/simulation-archive.css');
        const cssContent = await cssResponse.text();
        const style = document.createElement('style');
        style.textContent = cssContent;
        this.shadowRoot.appendChild(style);

        const htmlResponse = await fetch('/components/simulation-archive/simulation-archive.html');
        const htmlContent = await htmlResponse.text();
        const template = document.createElement('template');
        template.innerHTML = htmlContent;
        this.shadowRoot.appendChild(template.content.cloneNode(true));
    }

    bindEvents() {
        this.shadowRoot.getElementById('importSimulationResourceBtn')?.addEventListener('click', () => {
            window.showProjectImportWizard?.('simulation');
        });
        this.shadowRoot.getElementById('exportSimulationResourceBtn')?.addEventListener('click', () => {
            window.showProjectExportWizard?.('simulation');
        });

        const addBtn = this.shadowRoot.getElementById('addBtn');
        if (addBtn) {
            addBtn.addEventListener('click', () => {
                this.showAdd();
            });
        }

        const searchBtn = this.shadowRoot.getElementById('searchBtn');
        if (searchBtn) {
            searchBtn.addEventListener('click', () => {
                this.currentPage = 1;
                this.loadData();
            });
        }

        const resetBtn = this.shadowRoot.getElementById('resetBtn');
        if (resetBtn) {
            resetBtn.addEventListener('click', () => {
                this.resetFilters();
                this.loadData();
            });
        }

        const prevBtn = this.shadowRoot.getElementById('prevBtn');
        if (prevBtn) {
            prevBtn.addEventListener('click', () => {
                if (this.currentPage > 1) {
                    this.currentPage--;
                    this.loadData();
                }
            });
        }

        const nextBtn = this.shadowRoot.getElementById('nextBtn');
        if (nextBtn) {
            nextBtn.addEventListener('click', () => {
                const totalPages = Math.ceil(this.totalCount / this.pageSize);
                if (this.currentPage < totalPages) {
                    this.currentPage++;
                    this.loadData();
                }
            });
        }

        // 表格操作按钮事件委托
        this.shadowRoot.addEventListener('click', (e) => {
            const btn = e.target.closest('.action-btn');
            if (btn) {
                const action = btn.dataset.action;
                const id = btn.dataset.id;
                const item = this.data.find(item => String(item.id) === String(id));

                switch (action) {
                    case 'toggle-status':
                        this.toggleStatus(id, btn.dataset.status);
                        break;
                    case 'copy':
                        this.copyArchive(id);
                        break;
                    case 'detail':
                        if (item) {
                            this.showDetail(item);
                        } else {
                            console.error('未找到对应的档案项，id:', id);
                        }
                        break;
                    case 'edit':
                        if (item) {
                            this.showEdit(item);
                        } else {
                            console.error('未找到对应的档案项，id:', id);
                        }
                        break;
                    case 'delete':
                        this.deleteArchive(id);
                        break;
                }
                return;
            }

            // 处理表格行点击
            const row = e.target.closest('tr');
            if (row && row.dataset.id) {
                const id = row.dataset.id;
                const item = this.data.find(item => String(item.id) === String(id));
                if (item) {
                    this.showDetail(item);
                }
            }
        });
    }

    resetFilters() {
        const nameInput = this.shadowRoot.getElementById('nameInput');
        const projectNameInput = this.shadowRoot.getElementById('projectNameInput');
        const ownerInput = this.shadowRoot.getElementById('ownerInput');
        const statusSelect = this.shadowRoot.getElementById('statusSelect');

        if (nameInput) nameInput.value = '';
        if (projectNameInput) projectNameInput.value = '';
        if (ownerInput) ownerInput.value = '';
        if (statusSelect) statusSelect.value = '';
    }

    async loadData() {
        try {
            if (window.showGlobalLoading) {
                window.showGlobalLoading('正在加载仿真档案...');
            }

            const nameInput = this.shadowRoot.getElementById('nameInput');
            const projectNameInput = this.shadowRoot.getElementById('projectNameInput');
            const ownerInput = this.shadowRoot.getElementById('ownerInput');
            const statusSelect = this.shadowRoot.getElementById('statusSelect');

            const request = {
                name: nameInput ? nameInput.value : '',
                projectName: projectNameInput ? projectNameInput.value : '',
                owner: ownerInput ? ownerInput.value : '',
                status: statusSelect ? statusSelect.value : '',
                pageNum: this.currentPage,
                pageSize: this.pageSize
            };

            const result = await window.AppConfig.post('simulationArchives', 'query', request);

            if (result.code === 200 && result.data) {
                this.data = result.data.map(archive => ({
                    id: archive.createTime,
                    name: archive.name,
                    description: archive.description,
                    projectName: archive.projectName || '-',
                    owner: archive.owner || '-',
                    status: archive.status ? 'active' : 'inactive',
                    updateTime: new Date(archive.updateTime).toLocaleString('zh-CN'),
                    executionCount: archive.executionCount || 0,
                    isRunning: archive.isRunning || false,
                    createTime: archive.createTime,
                    scheduleCron: archive.scheduleCron || ''
                }));
                this.renderTable();
                
                // 获取总数
                const countResult = await window.AppConfig.post('simulationArchives', 'count', request);
                if (countResult.code === 200) {
                    this.totalCount = countResult.data;
                    this.renderPagination();
                }
            } else {
                this.showToast('加载仿真档案失败', 'error');
            }
        } catch (error) {
            console.error('加载仿真档案失败:', error);
            this.showToast('加载仿真档案失败', 'error');
        } finally {
            if (window.hideGlobalLoading) {
                window.hideGlobalLoading();
            }
        }
    }

    renderTable() {
        const tableBody = this.shadowRoot.getElementById('tableBody');
        if (!tableBody) return;

        tableBody.innerHTML = '';

        if (this.data.length === 0) {
            tableBody.innerHTML = '<tr><td colspan="9" style="text-align: center; padding: 20px;">暂无数据</td></tr>';
            return;
        }

        this.data.forEach(item => {
            const row = document.createElement('tr');
            row.style.cursor = 'pointer';
            row.dataset.id = item.id;

            // 处理调度配置显示
            const scheduleCron = item.scheduleCron && item.scheduleCron.trim() !== '' ? item.scheduleCron : '-';

            row.innerHTML = `
                <td>${item.name || '-'}</td>
                <td>${item.description || '-'}</td>
                <td>${item.projectName || '-'}</td>
                <td>${item.owner || '-'}</td>
                <td>${item.updateTime || '-'}</td>
                <td>${item.executionCount || 0}</td>
                <td>${scheduleCron}</td>
                <td>
                    <span class="status-badge ${item.status}">
                        ${item.status === 'active' ? '启用' : '禁用'}
                    </span>
                </td>
                <td>
                    <div class="action-buttons">
                        <button class="action-btn toggle-status" data-action="toggle-status" data-id="${item.createTime}" data-status="${item.status}">
                            ${item.status === 'active' ? '禁用' : '启用'}
                        </button>
                        <button class="action-btn copy" data-action="copy" data-id="${item.createTime}">复制</button>
                        <button class="action-btn detail" data-action="detail" data-id="${item.createTime}">详情</button>
                        <button class="action-btn edit" data-action="edit" data-id="${item.createTime}">编辑</button>
                        <button class="action-btn delete" data-action="delete" data-id="${item.createTime}">删除</button>
                    </div>
                </td>
            `;

            tableBody.appendChild(row);
        });
    }

    renderPagination() {
        const paginationInfo = this.shadowRoot.getElementById('paginationInfo');
        const prevBtn = this.shadowRoot.getElementById('prevBtn');
        const nextBtn = this.shadowRoot.getElementById('nextBtn');

        if (paginationInfo) {
            const totalPages = Math.ceil(this.totalCount / this.pageSize);
            paginationInfo.textContent = `第 ${this.currentPage} / ${totalPages || 1} 页，共 ${this.totalCount} 条`;
        }

        if (prevBtn) {
            prevBtn.disabled = this.currentPage <= 1;
        }

        if (nextBtn) {
            const totalPages = Math.ceil(this.totalCount / this.pageSize);
            nextBtn.disabled = this.currentPage >= totalPages;
        }
    }

    showAdd() {
        this.hide();
        const simulationArchiveDetail = document.getElementById('simulationArchiveDetail');
        if (simulationArchiveDetail && simulationArchiveDetail.showAdd) {
            simulationArchiveDetail.style.display = 'block';
            simulationArchiveDetail.showAdd();
        }
    }

    async showEdit(item) {
        this.hide();
        const simulationArchiveDetail = document.getElementById('simulationArchiveDetail');
        if (simulationArchiveDetail && simulationArchiveDetail.showDetail) {
            simulationArchiveDetail.style.display = 'block';
            await simulationArchiveDetail.showDetail(item.id);
            // 等待数据加载完成后启用编辑模式
            if (simulationArchiveDetail.enableEdit) {
                simulationArchiveDetail.enableEdit();
            }
        }
    }

    async showDetail(item) {
        this.hide();
        const simulationArchiveDetail = document.getElementById('simulationArchiveDetail');
        if (simulationArchiveDetail && simulationArchiveDetail.showDetail) {
            simulationArchiveDetail.style.display = 'block';
            await simulationArchiveDetail.showDetail(item.id);
        }
    }

    async deleteArchive(id) {
        const archive = this.data.find(a => a.id == id);
        if (archive) {
            this.showModal('删除确认', `确定要删除仿真档案"${archive.name}"吗？`, [
                { text: '取消', class: 'modal-btn secondary', action: 'close' },
                { text: '删除', class: 'modal-btn primary', action: 'delete', id }
            ]);
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

        // Store previous state
        const previousState = {
            title: modalTitle.textContent,
            body: modalBody.innerHTML,
            footer: modalFooter.innerHTML
        };

        modalTitle.textContent = title;
        modalBody.innerHTML = content;

        // Build footer buttons
        modalFooter.innerHTML = '';
        buttons.forEach(btn => {
            const button = document.createElement('button');
            button.className = btn.class || 'modal-btn';
            button.textContent = btn.text;
            button.onclick = () => {
                const action = btn.action;
                const id = btn.id;

                if (action === 'close') {
                    // Restore previous state
                    modalTitle.textContent = previousState.title;
                    modalBody.innerHTML = previousState.body;
                    modalFooter.innerHTML = previousState.footer;
                    modalMask.hidden = true;
                    modalMask.style.display = 'none';
                } else if (action === 'delete' && id) {
                    this.deleteArchiveFromAPI(id);
                    // 删除操作后不需要恢复之前的状态，直接关闭弹窗
                } else if (action === 'confirm' && id) {
                    this.saveCopiedArchive(id);
                }
            };
            modalFooter.appendChild(button);
        });

        modalMask.hidden = false;
        modalMask.style.display = 'flex';
    }

    async deleteArchiveFromAPI(id) {
        try {
            const result = await window.AppConfig.delete('simulationArchives', 'delete', { createTime: id });

            if (result.code === 200) {
                this.showToast('仿真档案已删除');
                await this.loadData();
            } else {
                this.showToast(result.message || '删除失败', 'error');
            }
        } catch (error) {
            console.error('删除仿真档案失败:', error);
            this.showToast('网络错误，删除失败', 'error');
        } finally {
            const modalMask = this.shadowRoot.getElementById('modalMask');
            if (modalMask) {
                modalMask.hidden = true;
                modalMask.style.display = 'none';
            }
        }
    }

    async toggleStatus(id, currentStatus) {
        try {
            const newStatus = currentStatus === 'active' ? false : true;
            const result = await window.AppConfig.post('simulationArchives', 'save', {
                createTime: id,
                status: newStatus
            });

            if (result.code === 200) {
                this.showToast(newStatus ? '已启用' : '已禁用');
                await this.loadData();
            } else {
                this.showToast(result.message || '操作失败', 'error');
            }
        } catch (error) {
            console.error('切换状态失败:', error);
            this.showToast('操作失败', 'error');
        }
    }

    async copyArchive(id) {
        const archive = this.data.find(a => String(a.id) === String(id));
        if (!archive) return;

        // 使用modal输入新名称
        this.showModal('复制仿真档案', `
            <div class="form-group">
                <label>新档案名称</label>
                <input type="text" id="copyNameInput" class="modal-input" value="${archive.name} (副本)" placeholder="请输入新档案名称">
            </div>
        `, [
            { text: '取消', class: 'modal-btn secondary', action: 'close' },
            { text: '确定', class: 'modal-btn primary', action: 'confirm', id }
        ]);
    }

    async saveCopiedArchive(id) {
        const archive = this.data.find(a => String(a.id) === String(id));
        if (!archive) return;

        const nameInput = this.shadowRoot.getElementById('copyNameInput');
        const newName = nameInput ? nameInput.value.trim() : '';
        if (!newName) {
            this.showToast('请输入档案名称', 'error');
            return;
        }

        try {
            if (window.showGlobalLoading) {
                window.showGlobalLoading('正在复制...');
            }

            // 构建复制后的档案数据
            const copiedArchive = {
                createTime: new Date().getTime(),
                name: newName,
                description: archive.description || '',
                projectName: archive.projectName || '',
                owner: archive.owner || '',
                graphJson: archive.graphJson || '{}',
                status: false, // 默认禁用
                scheduleCron: archive.scheduleCron || '',
                outputApiConfig: archive.outputApiConfig || ''
            };

            const result = await window.AppConfig.post('simulationArchives', 'save', copiedArchive);

            if (result.code === 200) {
                this.showToast('仿真档案复制成功');
                await this.loadData();
            } else {
                this.showToast(result.message || '复制失败', 'error');
            }
        } catch (error) {
            console.error('复制仿真档案失败:', error);
            this.showToast('网络错误，复制失败', 'error');
        } finally {
            if (window.hideGlobalLoading) {
                window.hideGlobalLoading();
            }
            const modalMask = this.shadowRoot.getElementById('modalMask');
            if (modalMask) {
                modalMask.hidden = true;
                modalMask.style.display = 'none';
            }
        }
    }

    show() {
        this.style.display = 'block';
        if (!this.data || this.data.length === 0) {
            this.loadData();
        }
    }

    hide() {
        this.style.display = 'none';
    }

    showToast(message, type = 'success') {
        if (window.CommonUtils && window.CommonUtils.showToast) {
            window.CommonUtils.showToast(message, type);
        } else {
            console.log(`[${type}] ${message}`);
        }
    }
}

customElements.define('simulation-archive-list', SimulationArchiveList);
