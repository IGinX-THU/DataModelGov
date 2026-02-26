class DatabaseTable extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });
        this.data = [];
        this.pageSize = 10;
        this.currentPage = 1;
        this.tableName = null;
        this.totalCount = 0;
        
        // 数据缓存
        this.dataCache = new Map(); // 格式: Map<tableName, {data: [], totalCount: number, header: []}>
        
        // 表格最大宽度限制
        this.maxTableWidth = 1000; // 可以根据需要调整这个值
        
        // 筛选条件
        this.filters = []; // 存储筛选条件
        this.availableFields = []; // 存储可用字段列表
    }

    async connectedCallback() {
        await this.loadResources();
        
        // 只有在没有tableName时才使用seedData
        if (!this.tableName) {
            this.seedData();
            this.totalCount = this.data.length;
            this.renderTable();
        }
        
        // 初始化分页组件
        this.initPagination();
        
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
        // 加载通用工具
        if (!window.CommonUtils) {
            const script = document.createElement('script');
            script.src = './js/common-utils.js';
            document.head.appendChild(script);
            // 等待脚本加载
            await new Promise(resolve => {
                script.onload = resolve;
            });
        }

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
            <!-- 初始为空，只通过加号添加 -->
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

    buildFilterRow(fieldValue = '', operatorValue = '=', valueValue = '') {
        return `
            <div class="filter-row">
                <div class="filter-field">
                    <span class="filter-label">字段</span>
                    <select class="filter-input">
                        <option value="">请选择字段</option>
                        ${this.availableFields.map(field => 
                            `<option value="${field}" ${field === fieldValue ? 'selected' : ''}>${field}</option>`
                        ).join('')}
                    </select>
                </div>
                <div class="filter-operator">
                    <span class="filter-label">运算符</span>
                    <select class="filter-input">
                        <option value="=" ${operatorValue === '=' ? 'selected' : ''}>=</option>
                        <option value="!=" ${operatorValue === '!=' ? 'selected' : ''}>!=</option>
                        <option value=">" ${operatorValue === '>' ? 'selected' : ''}>></option>
                        <option value="<" ${operatorValue === '<' ? 'selected' : ''}><</option>
                        <option value=">=" ${operatorValue === '>=' ? 'selected' : ''}>>=</option>
                        <option value="<=" ${operatorValue === '<=' ? 'selected' : ''}>=</option>
                        <option value="IN" ${operatorValue === 'IN' ? 'selected' : ''}>IN</option>
                        <option value="NOT IN" ${operatorValue === 'NOT IN' ? 'selected' : ''}>NOT IN</option>
                        <option value="LIKE" ${operatorValue === 'LIKE' ? 'selected' : ''}>LIKE</option>
                        <option value="包含" ${operatorValue === '包含' ? 'selected' : ''}>包含</option>
                    </select>
                </div>
                <div class="filter-value">
                    <span class="filter-label">值</span>
                    <input class="filter-input" type="text" value="${valueValue}" placeholder="筛选值" />
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

        if (!this.data || this.data.length === 0) {
            this.showEmptyState();
            return;
        }

        tbody.innerHTML = this.data.map((row, index) => {
            // 生成行数据
            const rowCells = Object.values(row).map(value => 
                `<td>${value !== null && value !== undefined ? value : ''}</td>`
            ).join('');
            
            // 添加操作列
            const actionCell = `
                <td>
                    <div class="action-buttons">
                        <button class="action-btn edit" data-index="${index}">编辑</button>
                        <button class="action-btn delete" data-index="${index}">删除</button>
                    </div>
                </td>
            `;
            
            return `<tr>${rowCells}${actionCell}</tr>`;
        }).join('');

        this.updatePagination();
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
                this.resetFilters();
            });
        }

        if (applyFilters) {
            applyFilters.addEventListener('click', () => {
                this.applyFilters();
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
                // 使用统一的 toast 消息系统
                if (window.CommonUtils && window.CommonUtils.showToast) {
                    window.CommonUtils.showToast(`已导出 ${this.data.length} 条记录`, 'success');
                } else {
                    this.showModal('导出成功', `已导出 ${this.data.length} 条记录`);
                }
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

        // 表格行操作
        const tbody = this.shadowRoot.getElementById('tableBody');
        if (tbody) {
            tbody.addEventListener('click', (event) => {
                if (event.target.classList.contains('action-btn')) {
                    const id = event.target.dataset.id;
                    if (event.target.classList.contains('delete')) {
                        this.showModal('删除确认', `确定要删除 ID 为 ${id} 的记录吗？`, [
                            { text: '取消', class: 'modal-btn secondary', action: 'close' },
                            { text: '删除', class: 'modal-btn primary', action: 'delete', id }
                        ]);
                    } else if (event.target.classList.contains('edit')) {
                        const id = event.target.dataset.id;
                        const row = this.data.find(r => r.id == id);
                        if (row) {
                            this.showModal('编辑记录', this.getFormModalBody(row), [
                                { text: '取消', class: 'modal-btn secondary', action: 'close' },
                                { text: '保存', class: 'modal-btn primary', action: 'edit', id }
                            ]);
                        }
                    }
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
                    this.hideModal();
                    // 使用统一的 toast 消息系统
                    if (window.CommonUtils && window.CommonUtils.showToast) {
                        window.CommonUtils.showToast('记录已添加', 'success');
                    } else {
                        this.showModal('成功', '记录已添加');
                    }
                } else if (action === 'import') {
                    this.hideModal();
                    // 使用统一的 toast 消息系统
                    if (window.CommonUtils && window.CommonUtils.showToast) {
                        window.CommonUtils.showToast('数据导入完成', 'success');
                    } else {
                        this.showModal('成功', '数据导入完成');
                    }
                } else if (action === 'edit' && id) {
                    const name = modalBody.querySelector('.modal-input:nth-child(2)').value.trim();
                    const device = modalBody.querySelector('.modal-input:nth-child(4)').value.trim();
                    const temperature = modalBody.querySelector('.modal-input:nth-child(6)').value.trim();
                    const humidity = modalBody.querySelector('.modal-input:nth-child(8)').value.trim();
                    
                    if (!name || !device || !temperature || !humidity) {
                        this.showModal('错误', '请填写完整的字段信息');
                        return;
                    }
                    
                    const row = this.data.find(r => r.id == id);
                    if (row) {
                        row.name = name;
                        row.device = device;
                        row.temperature = temperature;
                        row.humidity = humidity;
                        row.updatetime = new Date().toISOString().split('T')[0];
                        this.renderTable();
                        this.hideModal();
                        // 使用统一的 toast 消息系统
                        if (window.CommonUtils && window.CommonUtils.showToast) {
                            window.CommonUtils.showToast('记录已更新', 'success');
                        } else {
                            this.showModal('成功', '记录已更新');
                        }
                    }
                } else if (action === 'delete' && id) {
                    this.data = this.data.filter(row => row.id != id);
                    this.renderTable();
                    this.hideModal();
                    // 使用统一的 toast 消息系统
                    if (window.CommonUtils && window.CommonUtils.showToast) {
                        window.CommonUtils.showToast('删除成功', 'success');
                    } else {
                        console.log('记录已删除');
                    }
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

    show(tableName = null) {
        // 如果提供了tableName，加载关系数据
        if (tableName) {
            console.log('显示数据库表格:', tableName);
            this.tableName = tableName;
            // 重置到第一页并使用缓存
            this.currentPage = 1;
            this.filters = []; // 重置筛选条件
            this.loadRelationalData(true);
            // 加载可用字段列表
            this.loadAvailableFields();
        }
        this.setAttribute('show', '');
    }

    initPagination() {
        const pagination = this.shadowRoot.getElementById('pagination');
        if (pagination) {
            // 初始化分页设置
            pagination.setPagination(this.currentPage, this.pageSize, this.totalCount);
            
            // 监听分页变化事件
            pagination.addEventListener('pagination-change', (event) => {
                const { currentPage, pageSize } = event.detail;
                this.currentPage = currentPage;
                this.pageSize = pageSize;
                
                console.log('分页变化:', { currentPage, pageSize });
                
                // 如果有tableName，重新加载数据（不使用缓存，因为需要查询不同页）
                if (this.tableName) {
                    this.loadRelationalData(false);
                } else {
                    // 否则使用本地数据分页
                    this.renderTable();
                }
            });
        }
    }

    updatePagination() {
        const pagination = this.shadowRoot.getElementById('pagination');
        if (pagination) {
            // 使用totalCount设置分页
            console.log('更新分页: currentPage=', this.currentPage, ', pageSize=', this.pageSize, ', totalCount=', this.totalCount);
            pagination.setPagination(this.currentPage, this.pageSize, this.totalCount);
        }
    }

    async loadRelationalData(useCache = true) {
        try {
            console.log('开始加载关系数据:', this.tableName);
            
            // 检查缓存（仅在允许使用缓存且是第一页且无筛选条件时）
            if (useCache && this.currentPage === 1 && this.dataCache.has(this.tableName) && this.filters.length === 0) {
                console.log('使用缓存数据:', this.tableName);
                const cachedData = this.dataCache.get(this.tableName);
                this.data = cachedData.data;
                this.totalCount = cachedData.totalCount;
                this.updateTableHeader(cachedData.header);
                this.renderTable();
                this.updatePagination();
                return;
            }
            
            // 显示全局loading
            if (window.showGlobalLoading) {
                window.showGlobalLoading('正在查询数据...');
            }
            
            // 首先获取数据总量（仅在第一页或没有缓存时）
            if (this.currentPage === 1 || !this.dataCache.has(this.tableName) || this.filters.length > 0) {
                await this.loadTotalCount();
            }
            
            // 构建请求体
            const requestBody = {
                tableName: this.tableName,
                pageNum: this.currentPage,
                pageSize: this.pageSize,
                filters: this.filters.length > 0 ? this.filters : null
            };
            
            console.log('查询参数:', requestBody);
            
            // 调用关系数据查询接口
            const response = await fetch(window.AppConfig.getApiUrl('data', 'relational/query'), {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify(requestBody)
            });
            
            const result = await response.json();
            
            console.log('API响应结果:', result);
            
            if (result.code === 200 && result.data) {
                console.log('关系数据查询成功:', result.data);
                
                // 处理查询结果
                this.processTableData(result.data);
                
                // 只缓存第一页的无筛选条件的数据和表头
                if (this.currentPage === 1 && this.filters.length === 0) {
                    const header = result.data.header || result.data.paths;
                    this.dataCache.set(this.tableName, {
                        data: result.data.records,
                        totalCount: this.totalCount,
                        header: header
                    });
                    console.log('数据已缓存:', this.tableName);
                }
                
            } else if (result.code === 200 && (!result.data || !result.data.records || result.data.records.length === 0)) {
                // 接口成功但没有数据
                console.log('查询成功但没有数据');
                this.showEmptyState();
            } else {
                // 接口返回错误
                console.error('关系数据查询失败:', result.message);
                this.showError('数据查询失败: ' + (result.message || '未知错误'));
            }
            
        } catch (error) {
            console.error('加载关系数据失败:', error);
            this.showError('网络错误，无法查询数据');
        } finally {
            // 无论成功还是失败，都隐藏全局loading
            if (window.hideGlobalLoading) {
                window.hideGlobalLoading();
            }
        }
    }

    async loadTotalCount() {
        try {
            const requestBody = {
                tableName: this.tableName,
                filters: this.filters.length > 0 ? this.filters : null
            };
            
            console.log('查询总量参数:', requestBody);
            
            const response = await fetch(window.AppConfig.getApiUrl('data', 'relational/count'), {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify(requestBody)
            });
            
            const result = await response.json();
            console.log('总量查询结果:', result);
            
            if (result.code === 200 && result.data !== undefined) {
                this.totalCount = result.data;
                console.log('数据总量:', this.totalCount);
            } else {
                console.warn('获取数据总量失败，使用当前数据量');
                this.totalCount = this.data.length;
            }
        } catch (error) {
            console.error('获取数据总量失败:', error);
            this.totalCount = this.data.length;
        }
    }

    // 处理表格数据（参考data-visualization的processTableData）
    processTableData(tableData) {
        console.log('处理表格数据:', tableData);
        
        // 检查数据格式，支持header或paths
        if (!tableData || (!tableData.header && !tableData.paths) || !tableData.records) {
            console.error('无效的表格数据格式');
            this.showEmptyState();
            return;
        }
        
        // 使用header或paths作为表头
        const header = tableData.header || tableData.paths;
        
        // 更新可用字段列表（只取叶子节点）
        this.availableFields = header.map(path => {
            const parts = path.split('.');
            return parts[parts.length - 1];
        });
        console.log('更新字段列表:', this.availableFields);
        this.updateFilterFields();
        
        // 设置表头
        this.updateTableHeader(header);
        
        // 保存数据
        this.data = tableData.records;
        // totalCount已经在loadTotalCount中设置了
        
        console.log('处理后的数据:', this.data.length, '条记录');
        console.log('表头:', header);
        console.log('数据总量:', this.totalCount);
        
        // 更新表格
        this.renderTable();
        
        // 更新分页
        this.updatePagination();
    }

    // 更新表头（参考data-visualization的updateTableHeader）
    updateTableHeader(header) {
        const table = this.shadowRoot.querySelector('.data-table');
        const tableHead = table ? table.querySelector('thead tr') : null;
        if (tableHead) {
            // 清空现有表头
            tableHead.innerHTML = '';
            
            // 添加所有列头
            header.forEach(columnName => {
                const th = document.createElement('th');
                th.textContent = columnName;
                th.style.minWidth = '120px'; // 设置合理的最小宽度
                th.style.whiteSpace = 'nowrap';
                th.style.padding = '8px 12px';
                tableHead.appendChild(th);
            });
            
            // 添加操作列
            const actionTh = document.createElement('th');
            actionTh.textContent = '操作';
            actionTh.style.minWidth = '120px';
            actionTh.style.whiteSpace = 'nowrap';
            actionTh.style.padding = '8px 12px';
            tableHead.appendChild(actionTh);
            
            // 让表格自然撑开，由workspace-content处理滚动
            setTimeout(() => {
                this.enableTableNaturalWidth();
            }, 100);
        }
    }

    // 让表格自然撑开
    enableTableNaturalWidth() {
        const table = this.shadowRoot.querySelector('.data-table');
        if (table) {
            // 计算表格所需宽度
            const headers = table.querySelectorAll('th');
            let totalWidth = 0;
            headers.forEach(th => {
                totalWidth += th.offsetWidth;
            });
            
            // 设置表格宽度，让它自然撑开
            table.style.width = totalWidth + 'px';
            table.style.minWidth = totalWidth + 'px';
            
            console.log('表格自然宽度:', totalWidth + 'px');
        }
    }

    // 检查布局平衡
    checkLayoutBalance() {
        // 获取布局相关的关键元素
        const topNav = document.querySelector('.top-nav');
        const leftSidebar = document.querySelector('.left-sidebar');
        const rightSidebar = document.querySelector('.right-sidebar');
        const workspace = document.querySelector('.workspace');
        
        // 打印布局宽度信息
        console.log('=== 网页布局宽度调试信息 ===');
        console.log('top-nav宽度:', topNav ? topNav.offsetWidth + 'px' : '未找到');
        console.log('left-sidebar宽度:', leftSidebar ? leftSidebar.offsetWidth + 'px' : '未找到');
        console.log('right-sidebar宽度:', rightSidebar ? rightSidebar.offsetWidth + 'px' : '未找到');
        console.log('workspace宽度:', workspace ? workspace.offsetWidth + 'px' : '未找到');
        
        if (topNav && leftSidebar && rightSidebar) {
            const sidebarPlusWorkspace = leftSidebar.offsetWidth + workspace.offsetWidth + rightSidebar.offsetWidth;
            console.log('left-sidebar + workspace + right-sidebar =', sidebarPlusWorkspace + 'px');
            
            // 计算理想workspace宽度
            const idealWorkspaceWidth = topNav.offsetWidth - leftSidebar.offsetWidth - rightSidebar.offsetWidth;
            console.log('计算的理想workspace宽度:', idealWorkspaceWidth + 'px');
            console.log('计算公式: top-nav - left-sidebar - right-sidebar =', 
                topNav.offsetWidth + ' - ' + leftSidebar.offsetWidth + ' - ' + rightSidebar.offsetWidth + ' = ' + idealWorkspaceWidth);
            
            if (topNav) {
                const diff = sidebarPlusWorkspace - topNav.offsetWidth;
                console.log('与top-nav宽度差异:', diff + 'px');
                if (Math.abs(diff) > 5) {
                    console.warn('⚠️ 布局不平衡！差异超过5px');
                } else {
                    console.log('✅ 布局平衡');
                }
            }
            
            // 动态设置组件宽度
            this.setComponentWidth(workspace.offsetWidth);
        }
        console.log('========================');
    }

    // 动态设置组件宽度
    setComponentWidth(currentWorkspaceWidth) {
        const host = this.shadowRoot.host;
        const dbTable = this.shadowRoot.querySelector('.db-table');
        
        // 计算workspace的理想宽度
        const topNav = document.querySelector('.top-nav');
        const leftSidebar = document.querySelector('.left-sidebar');
        const rightSidebar = document.querySelector('.right-sidebar');
        
        if (topNav && leftSidebar && rightSidebar) {
            const idealWorkspaceWidth = topNav.offsetWidth - leftSidebar.offsetWidth - rightSidebar.offsetWidth;
            console.log('当前workspace宽度:', currentWorkspaceWidth + 'px');
            console.log('理想workspace宽度:', idealWorkspaceWidth + 'px');
            
            if (host && dbTable) {
                // 设置database-table组件宽度等于理想workspace宽度
                host.style.maxWidth = idealWorkspaceWidth + 'px';
                dbTable.style.maxWidth = idealWorkspaceWidth + 'px';
                console.log('设置database-table组件宽度为:', idealWorkspaceWidth + 'px');
            }
            
            // 同时设置data-visualization组件的宽度
            const dataViz = document.querySelector('data-visualization');
            if (dataViz) {
                dataViz.style.maxWidth = idealWorkspaceWidth + 'px';
                console.log('设置data-visualization组件宽度为:', idealWorkspaceWidth + 'px');
            }
            
            // 强制限制workspace的宽度
            const workspace = document.querySelector('.workspace');
            if (workspace) {
                workspace.style.maxWidth = idealWorkspaceWidth + 'px';
                console.log('强制限制workspace宽度为:', idealWorkspaceWidth + 'px');
            }
        }
    }

    // 设置表格宽度
    setTableWidth() {
        const table = this.shadowRoot.querySelector('.data-table');
        
        // 获取布局相关的关键元素
        const topNav = document.querySelector('.top-nav');
        const leftSidebar = document.querySelector('.left-sidebar');
        const rightSidebar = document.querySelector('.right-sidebar');
        const workspace = document.querySelector('.workspace');
        const mainContainer = document.querySelector('.main-container');
        
        if (table) {
            // 计算表格所需宽度
            const headers = table.querySelectorAll('th');
            let totalWidth = 0;
            headers.forEach(th => {
                totalWidth += th.offsetWidth;
            });
            
            // 设置表格宽度，让它能够撑开workspace-content
            table.style.width = totalWidth + 'px';
            table.style.minWidth = totalWidth + 'px';
            
            // 打印布局宽度信息
            console.log('=== 网页布局宽度调试信息 ===');
            console.log('top-nav宽度:', topNav ? topNav.offsetWidth + 'px' : '未找到');
            console.log('left-sidebar宽度:', leftSidebar ? leftSidebar.offsetWidth + 'px' : '未找到');
            console.log('workspace宽度:', workspace ? workspace.offsetWidth + 'px' : '未找到');
            console.log('right-sidebar宽度:', rightSidebar ? rightSidebar.offsetWidth + 'px' : '未找到');
            
            if (leftSidebar && workspace && rightSidebar) {
                const sidebarPlusWorkspace = leftSidebar.offsetWidth + workspace.offsetWidth + rightSidebar.offsetWidth;
                console.log('left-sidebar + workspace + right-sidebar =', sidebarPlusWorkspace + 'px');
                
                if (topNav) {
                    const diff = sidebarPlusWorkspace - topNav.offsetWidth;
                    console.log('与top-nav宽度差异:', diff + 'px');
                    if (Math.abs(diff) > 5) {
                        console.warn('⚠️ 布局不平衡！差异超过5px');
                    } else {
                        console.log('✅ 布局平衡');
                    }
                }
            }
            
            console.log('表格计算宽度:', totalWidth + 'px');
            console.log('========================');
        }
    }

    // 强制设置表格宽度
    forceTableWidth() {
        const table = this.shadowRoot.querySelector('.data-table');
        const tableCard = this.shadowRoot.querySelector('.db-table-card');
        
        if (table && tableCard) {
            // 使用配置的最大宽度
            const reasonableWidth = this.maxTableWidth;
            
            // 计算表格所需的最小宽度
            const headers = table.querySelectorAll('th');
            let totalWidth = 0;
            headers.forEach(th => {
                totalWidth += th.offsetWidth;
            });
            
            // 如果表格宽度超过合理宽度，使用合理宽度；否则使用计算出的宽度
            const finalWidth = Math.min(totalWidth + 40, reasonableWidth);
            
            // 设置表格宽度
            table.style.width = finalWidth + 'px';
            table.style.minWidth = finalWidth + 'px';
            
            console.log('表格宽度计算 - 需要宽度:', totalWidth + 40 + 'px, 最大宽度:', reasonableWidth + 'px, 最终宽度:', finalWidth + 'px');
        }
    }

    showEmptyState() {
        const tbody = this.shadowRoot.getElementById('tableBody');
        if (tbody) {
            tbody.innerHTML = '<tr><td colspan="100%" style="text-align: center; padding: 20px; color: #666;">暂无数据</td></tr>';
        }
    }

    showError(message) {
        const tbody = this.shadowRoot.getElementById('tableBody');
        if (tbody) {
            tbody.innerHTML = `<tr><td colspan="100%" style="text-align: center; padding: 20px; color: #f44336;">${message}</td></tr>`;
        }
    }

    hide() {
        this.removeAttribute('show');
    }

    // 清除缓存
    clearCache(tableName = null) {
        if (tableName) {
            this.dataCache.delete(tableName);
            console.log('已清除缓存:', tableName);
        } else {
            this.dataCache.clear();
            console.log('已清除所有缓存');
        }
    }

    // 获取可用字段列表
    async loadAvailableFields() {
        try {
            // 从当前表格的表头获取字段列表
            if (this.dataCache.has(this.tableName)) {
                const cachedData = this.dataCache.get(this.tableName);
                const fullPaths = cachedData.header || [];
                // 只取叶子节点的值（最后一个点之后的部分）
                this.availableFields = fullPaths.map(path => {
                    const parts = path.split('.');
                    return parts[parts.length - 1];
                });
                console.log('从缓存获取字段列表:', this.availableFields);
                this.updateFilterFields();
                return;
            }
            
            // 如果没有缓存，先查询一页数据获取表头
            const requestBody = {
                tableName: this.tableName,
                pageNum: 1,
                pageSize: 1
            };
            
            const response = await fetch(window.AppConfig.getApiUrl('data', 'relational/query'), {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify(requestBody)
            });
            
            const result = await response.json();
            
            if (result.code === 200 && result.data) {
                const fullPaths = result.data.header || result.data.paths || [];
                // 只取叶子节点的值（最后一个点之后的部分）
                this.availableFields = fullPaths.map(path => {
                    const parts = path.split('.');
                    return parts[parts.length - 1];
                });
                console.log('获取字段列表:', this.availableFields);
                this.updateFilterFields();
            }
        } catch (error) {
            console.error('获取字段列表失败:', error);
            this.availableFields = [];
        }
    }

    // 更新筛选字段下拉框
    updateFilterFields() {
        const filterRows = this.shadowRoot.querySelectorAll('.filter-row');
        filterRows.forEach(row => {
            const fieldSelect = row.querySelector('.filter-field select');
            if (fieldSelect) {
                const currentValue = fieldSelect.value;
                fieldSelect.innerHTML = '<option value="">请选择字段</option>';
                
                this.availableFields.forEach(field => {
                    const option = document.createElement('option');
                    option.value = field;
                    option.textContent = field;
                    if (field === currentValue) {
                        option.selected = true;
                    }
                    fieldSelect.appendChild(option);
                });
            }
        });
    }

    // 应用筛选条件
    applyFilters() {
        try {
            // 收集筛选条件
            const filterRows = this.shadowRoot.querySelectorAll('.filter-row');
            this.filters = [];
            
            filterRows.forEach(row => {
                const fieldSelect = row.querySelector('.filter-field select');
                const operatorSelect = row.querySelector('.filter-operator select');
                const valueInput = row.querySelector('.filter-value input');
                
                if (fieldSelect && operatorSelect && valueInput) {
                    const field = fieldSelect.value.trim();
                    const operator = operatorSelect.value;
                    const value = valueInput.value.trim();
                    
                    if (field && operator && value) {
                        this.filters.push({
                            field: field,
                            operator: operator,
                            value: value
                        });
                    }
                }
            });
            
            console.log('筛选条件:', this.filters);
            
            // 重置到第一页并重新加载数据
            this.currentPage = 1;
            this.loadRelationalData(false); // 不使用缓存
            
            // 显示筛选结果
            if (window.CommonUtils && window.CommonUtils.showToast) {
                window.CommonUtils.showToast('正在应用筛选条件...', 'info');
            }
            
        } catch (error) {
            console.error('应用筛选条件失败:', error);
            if (window.CommonUtils && window.CommonUtils.showToast) {
                window.CommonUtils.showToast('筛选失败', 'error');
            }
        }
    }

    // 重置筛选条件
    resetFilters() {
        try {
            // 清空筛选条件
            this.filters = [];
            
            // 重置筛选表单（清空所有筛选行）
            const filterRows = this.shadowRoot.getElementById('filterRows');
            if (filterRows) {
                filterRows.innerHTML = ''; // 清空所有筛选行
            }
            
            // 重置到第一页并重新加载数据
            this.currentPage = 1;
            this.loadRelationalData(true); // 使用缓存
            
            if (window.CommonUtils && window.CommonUtils.showToast) {
                window.CommonUtils.showToast('筛选条件已重置', 'success');
            }
            
        } catch (error) {
            console.error('重置筛选条件失败:', error);
        }
    }
}

customElements.define('database-table', DatabaseTable);
