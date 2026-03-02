class AssociationRules extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });
        this.data = [];
        this.pageSize = 10;
        this.currentPage = 1;
    }

    async loadRulesFromAPI() {
        try {
            // 获取筛选条件
            const nameFilter = this.shadowRoot.querySelector('.filter-input[type="text"]')?.value.trim();
            const statusFilter = this.shadowRoot.querySelector('.filter-input[type="text"] + select')?.value;
            
            // 构建请求对象
            const requestBody = {
                pageNum: this.currentPage || 1,
                pageSize: this.pageSize || 6,
                name: nameFilter || null,
                status: statusFilter || null
            };
            
            console.log('查询参数:', requestBody);
            
            // 调用查询接口
            const response = await fetch(window.AppConfig.api.baseURL + window.AppConfig.endpoints.data['association/rules/query'], {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify(requestBody)
            });
            
            const result = await response.json();
            console.log('查询结果:', result);
            
            if (result.code === 200 && result.data) {
                // 后端直接返回List<AssociationRulesEntity>，转换为前端所需格式
                this.data = result.data.map(rule => ({
                    id: rule.createTime, // 使用createTime作为唯一标识
                    ruleName: rule.name,
                    ruleDesc: rule.description,
                    dataSource: rule.tableName,
                    targetModel: rule.modelName,
                    version: rule.modelVersion,
                    status: rule.status ? 'active' : 'inactive',
                    mappings: rule.inputsBind ? JSON.parse(rule.inputsBind) : [],
                    resultMappings: rule.outputsBind ? JSON.parse(rule.outputsBind) : [],
                    updateTime: new Date(rule.updateTime).toLocaleString('zh-CN'),
                    createTime: rule.createTime
                }));
                
                // 同时获取总数用于分页
                await this.loadRulesCount(nameFilter, statusFilter);
                
                console.log('加载的规则数据:', this.data);
            } else {
                console.error('加载规则失败:', result.message);
                this.showToast('加载规则失败', 'error');
            }
        } catch (error) {
            console.error('加载规则失败:', error);
            this.showToast('网络错误，无法加载规则', 'error');
        }
    }

    async loadRulesCount(name, status) {
        try {
            // 构建请求对象
            const requestBody = {
                name: name || null,
                status: status || null
            };
            
            console.log('查询总量参数:', requestBody);
            
            const response = await fetch(window.AppConfig.api.baseURL + window.AppConfig.endpoints.data['association/rules/count'], {
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
                this.updatePagination();
            } else {
                console.warn('获取数据总量失败，使用当前数据量');
                this.totalCount = this.data.length;
            }
        } catch (error) {
            console.error('获取数据总量失败:', error);
            this.totalCount = this.data.length;
        }
    }

    
    async deleteRuleFromAPI(createTime) {
        try {
            const response = await fetch(window.AppConfig.api.baseURL + window.AppConfig.endpoints.data['association/rules/delete'] + `?createTime=${createTime}`, {
                method: 'DELETE'
            });
            
            const result = await response.json();
            
            if (result.code === 200) {
                await this.loadRulesFromAPI();
                this.renderTable();
                this.hideModal(); // 直接关闭弹窗，不恢复新增弹窗
                this.showToast('规则已删除');
            } else {
                this.showToast(result.message || '删除失败', 'error');
            }
        } catch (error) {
            console.error('删除规则失败:', error);
            this.showToast('网络错误，删除失败', 'error');
        }
    }

    getRuleNameByCreateTime(createTime) {
        const rule = this.data.find(r => r.createTime === createTime);
        return rule ? rule.ruleName : '';
    }

    async connectedCallback() {
        await this.loadResources();
        
        // 初始化分页组件
        this.initPagination();
        
        // Store references to external trees
        this.selectedDataSource = null;
        this.selectedModel = null;
        
        setTimeout(() => {
            const modalMask = this.shadowRoot.getElementById('modalMask');
            if (modalMask) {
                modalMask.hidden = true;
                modalMask.style.display = 'none';
            }
            this.bindEvents();
            this.setupTreeInteraction();
        }, 100);
    }

    // 添加show方法供main.js调用 - 参考数据源管理的实现
    async show(...args) {
        console.log('AssociationRules show() 被调用', args);
        this.style.display = 'block';
        // 每次显示时刷新数据
        await this.loadRulesFromAPI();
        this.renderTable();
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

    buildFilterRow(name = '', status = '') {
        return `
            <div class="filter-row">
                <div class="filter-field">
                    <span class="filter-label">规则名</span>
                    <input class="filter-input" type="text" placeholder="请输入规则名称" value="${name}" />
                </div>
                <div class="filter-field">
                    <span class="filter-label">状态</span>
                    <select class="filter-input">
                        <option value="">全部</option>
                        <option value="active" ${status === 'active' ? 'selected' : ''}>启用</option>
                        <option value="inactive" ${status === 'inactive' ? 'selected' : ''}>禁用</option>
                    </select>
                </div>
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

        // 模态框事件
        this.shadowRoot.getElementById('modalClose')?.addEventListener('click', () => this.hideModal());
        this.shadowRoot.getElementById('cancelBtn')?.addEventListener('click', () => this.hideModal());
        this.shadowRoot.getElementById('saveBtn')?.addEventListener('click', () => this.saveRule());
        
        // 添加映射按钮
        this.shadowRoot.getElementById('addMapping')?.addEventListener('click', () => this.addMapping());
        this.shadowRoot.getElementById('addResultMapping')?.addEventListener('click', () => this.addResultMapping());
        
        // 数据源和目标模型变化事件
        this.shadowRoot.getElementById('dataSource')?.addEventListener('change', () => this.updateMappingFieldOptions());
        this.shadowRoot.getElementById('targetModel')?.addEventListener('change', () => {
            this.updateMappingFieldOptions();
            this.updateResultMappingFieldOptions();
        });
        
        // Close modal when clicking on the mask
        this.shadowRoot.getElementById('modalMask')?.addEventListener('click', (e) => {
            if (e.target === this.shadowRoot.getElementById('modalMask')) {
                this.hideModal();
            }
        });
        
        // Handle form submission
        this.shadowRoot.getElementById('ruleForm')?.addEventListener('submit', (e) => {
            e.preventDefault();
            this.saveRule();
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

    async applyFilters() {
        console.log('点击查询按钮');
        this.currentPage = 1; // 重置到第一页
        await this.loadRulesFromAPI();
        this.renderTable();
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

        this.updatePagination();
    }

    showAddModal() {
        const modal = this.shadowRoot.getElementById('modalMask');
        const title = this.shadowRoot.getElementById('modalTitle');
        const form = this.shadowRoot.getElementById('ruleForm');
        
        if (modal && title && form) {
            // Restore form content if it was replaced by showModal
            this.restoreFormContent();
            
            title.textContent = '新增关联规则';
            form.reset();
            modal.hidden = false;
            modal.style.display = 'flex';
            // 移除静态版本值，等待模型选择后加载
            this.shadowRoot.getElementById('version').innerHTML = '<option value="">请选择版本</option>';
            this.shadowRoot.querySelector('input[name="status"][value="active"]').checked = true;
            this.currentAction = 'add';
            
            // Restore form footer buttons
            this.restoreFormFooter();
            
            // Highlight external trees
            document.body.classList.add('association-rules-modal-open');
            
            // 初始化动态数据源和目标模型
            this.loadDataSourceOptions();
            this.loadTargetModelOptions();
            
            // Initialize empty mappings list
            this.initializeMappings();
            this.initializeResultMappings();
        }
    }

        showEditModal(rule) {
        const modal = this.shadowRoot.getElementById('modalMask');
        const title = this.shadowRoot.getElementById('modalTitle');
        const form = this.shadowRoot.getElementById('ruleForm');
        
        if (modal && title && form && rule) {
            // Restore form content if it was replaced by showModal
            this.restoreFormContent();
            
            title.textContent = '编辑关联规则';
            form.reset();
            
            // 完全参考model-edit.js的showWithModelData方法，将所有字段带过去
            // Fill the form with rule data - 参考模型元数据的字段映射
            this.shadowRoot.getElementById('ruleName').value = rule.ruleName || rule.name || '';
            this.shadowRoot.getElementById('ruleDesc').value = rule.ruleDesc || rule.description || '';
            this.shadowRoot.getElementById('dataSource').value = rule.dataSource || rule.tableName || '';
            this.shadowRoot.getElementById('targetModel').value = rule.targetModel || rule.modelName || '';
            this.shadowRoot.getElementById('version').value = rule.version || rule.modelVersion || 'v1.0.0';
            
            // Set status radio button - 参考模型元数据的status处理
            const statusValue = rule.status === 'active' || rule.status === true ? 'active' : 'inactive';
            this.shadowRoot.querySelector(`input[name="status"][value="${statusValue}"]`).checked = true;
            
            // Store the rule createTime for update - 参考模型元数据的timestamp
            form.dataset.ruleId = rule.createTime;
            this.currentAction = 'edit';
            
            // Restore form footer buttons
            this.restoreFormFooter();
            
            // Highlight external trees
            document.body.classList.add('association-rules-modal-open');
            
            // 完全参考model-edit.js的loadInterfaceParamsFromData方法
            // Initialize mappings with existing data if available - 参考inputs/outputs处理
            if (rule.mappings && rule.mappings.length > 0) {
                this.initializeMappings();
                // Clear existing mappings and add existing ones
                const mappingsList = this.shadowRoot.getElementById('mappingsList');
                mappingsList.innerHTML = '';
                rule.mappings.forEach(mapping => {
                    this.addMapping(mapping);
                });
            } else {
                this.initializeMappings();
            }
            
            // Initialize result mappings with existing data if available
            if (rule.resultMappings && rule.resultMappings.length > 0) {
                this.initializeResultMappings();
                // Clear existing result mappings and add existing ones
                const resultMappingsList = this.shadowRoot.getElementById('resultMappingsList');
                resultMappingsList.innerHTML = '';
                rule.resultMappings.forEach(mapping => {
                    this.addResultMapping(mapping);
                });
            } else {
                this.initializeResultMappings();
            }
            
            modal.hidden = false;
            modal.style.display = 'flex';
        }
    }

    hideModal() {
        const modal = this.shadowRoot.getElementById('modalMask');
        if (modal) {
            modal.hidden = true;
            modal.style.display = 'none';
            
            // Remove highlight from external trees
            document.body.classList.remove('association-rules-modal-open');
            
            // Clear selections
            document.querySelectorAll('.left-sidebar .tree-node.selected, .right-sidebar .tree-node.selected').forEach(node => {
                node.classList.remove('selected');
            });
            
            this.selectedDataSource = null;
            this.selectedModel = null;
        }
    }

    async saveRule() {
        try {
            const formData = this.collectFormData();
            
            // 验证必填字段 - 参考model-edit.js的验证逻辑
            if (!formData.name) {
                this.showToast('请输入规则名称', 'error');
                return;
            }
            
            if (!formData.tableName) {
                this.showToast('请选择数据源', 'error');
                return;
            }
            
            if (!formData.modelName) {
                this.showToast('请选择目标模型', 'error');
                return;
            }

            console.log('保存关联规则数据:', formData);

            // 调用保存API - 参考model-edit.js的保存逻辑
            const response = await fetch(window.AppConfig.api.baseURL + window.AppConfig.endpoints.data['association/rules/save'], {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify(formData)
            });

            if (response.ok) {
                const result = await response.json();
                console.log('保存响应:', result);
                
                if (result.code === 200) {
                    this.showToast(`规则已${this.currentAction === 'edit' ? '更新' : '添加'}成功`);
                    this.hideModal();
                    
                    // 重新加载规则列表 - 参考model-edit.js的刷新逻辑
                    await this.loadRulesFromAPI();
                    this.renderTable();
                    
                    // 通知其他组件刷新 - 参考model-edit.js的事件通知
                    this.dispatchEvent(new CustomEvent('rule-updated', {
                        detail: { 
                            ruleName: formData.name,
                            createTime: formData.createTime,
                            formData: formData
                        },
                        bubbles: true,
                        composed: true
                    }));
                } else {
                    this.showToast(result.message || '保存失败', 'error');
                }
            } else {
                throw new Error(`HTTP error! status: ${response.status}`);
            }
        } catch (error) {
            console.error('保存规则失败:', error);
            this.showToast('保存失败，请稍后重试', 'error');
        }
    }

    collectFormData() {
        // 完全参考model-edit.js的collectFormData方法，收集所有字段
        // 收集基本信息
        const ruleName = this.shadowRoot.getElementById('ruleName').value.trim();
        const ruleDesc = this.shadowRoot.getElementById('ruleDesc').value.trim();
        const dataSource = this.shadowRoot.getElementById('dataSource').value;
        const targetModel = this.shadowRoot.getElementById('targetModel').value;
        const version = this.shadowRoot.getElementById('version').value.trim();
        const status = this.shadowRoot.querySelector('input[name="status"]:checked')?.value || 'active';
        
        // 收集映射关系 - 参考model-edit.js的inputs/outputs收集逻辑
        const mappings = this.getMappings();
        const resultMappings = this.getResultMappings();
        
        // 构建完整的表单数据对象，包含AssociationRulesEntity需要的所有字段
        // 参考model-edit.js的formData构建方式
        const formData = {
            name: ruleName,
            description: ruleDesc,
            tableName: dataSource,  // 前端dataSource映射到后端tableName
            modelName: targetModel, // 前端targetModel映射到后端modelName
            modelVersion: version,   // 前端version映射到后端modelVersion
            status: status === 'active', // 转换为boolean类型
            createTime: this.currentAction === 'edit' && this.shadowRoot.getElementById('ruleForm').dataset.ruleId 
                ? parseInt(this.shadowRoot.getElementById('ruleForm').dataset.ruleId) 
                : null,
            inputsBind: JSON.stringify(mappings),    // 输入映射关系转为JSON - 参考inputs字段
            outputsBind: JSON.stringify(resultMappings) // 输出映射关系转为JSON - 参考outputs字段
        };

        return formData;
    }

    formatJson() {
        const textarea = this.shadowRoot.getElementById('ruleConfig');
        if (!textarea) return;

        try {
            const parsed = JSON.parse(textarea.value);
            textarea.value = JSON.stringify(parsed, null, 2);
        } catch (e) {
            alert('无效的JSON格式');
        }
    }

    editRule(id) {
        const rule = this.data.find(item => item.id === id);
        if (!rule) return;
        
        this.showEditModal(rule);
    }

    updateRule(id) {
        const modalBody = this.shadowRoot.getElementById('modalBody');
        const rule = this.data.find(item => item.id === id);
        if (!rule) return;

        rule.name = modalBody.querySelector('#ruleName')?.value.trim();
        rule.regex = modalBody.querySelector('#ruleRegex')?.value.trim();
        rule.updateTime = new Date().toLocaleString('zh-CN');

        this.renderTable();
        this.showModal('成功', '规则已更新');
    }

    deleteRule(id) {
        this.showModal('删除确认', `确定要删除这条规则吗？`, [
            { text: '取消', class: 'modal-btn secondary', action: 'close' },
            { text: '删除', class: 'modal-btn primary', action: 'delete', id }
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
        if (buttons.length > 0) {
            modalFooter.innerHTML = buttons.map(btn => 
                `<button class="${btn.class}" data-action="${btn.action}" ${btn.id ? `data-id="${btn.id}"` : ''}>${btn.text}</button>`
            ).join('');

            // Add new event listener
            const handleFooterClick = (event) => {
                const action = event.target.dataset.action;
                const id = event.target.dataset.id;

                if (action === 'close') {
                    this.hideModal();
                    // Restore previous state
                    modalTitle.textContent = previousState.title;
                    modalBody.innerHTML = previousState.body;
                    modalFooter.innerHTML = previousState.footer;
                } else if (action === 'delete' && id) {
                    this.deleteRuleFromAPI(id);
                    // Restore previous state
                    modalTitle.textContent = previousState.title;
                    modalBody.innerHTML = previousState.body;
                    modalFooter.innerHTML = previousState.footer;
                } else if (action === 'save') {
                    this.saveRule();
                } else if (action === 'update' && id) {
                    this.updateRule(id);
                }
            };

            // Remove any existing event listeners
            const newFooter = modalFooter.cloneNode(true);
            modalFooter.parentNode.replaceChild(newFooter, modalFooter);
            newFooter.addEventListener('click', handleFooterClick);
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

    /**
     * Initialize mappings list with one empty row
     */
    initializeMappings() {
        const mappingsList = this.shadowRoot.getElementById('mappingsList');
        if (mappingsList) {
            mappingsList.innerHTML = '';
            this.addMapping();
        }
    }

    /**
     * Initialize result mappings list with one empty row
     */
    initializeResultMappings() {
        const resultMappingsList = this.shadowRoot.getElementById('resultMappingsList');
        if (resultMappingsList) {
            resultMappingsList.innerHTML = '';
            this.addResultMapping();
        }
    }

    /**
     * Add a mapping row to the mappings list
     */
    addMapping(mappingData = null) {
        const mappingsList = this.shadowRoot.getElementById('mappingsList');
        if (!mappingsList) return;

        const row = document.createElement('div');
        row.className = 'mapping-row';

        // Data source field
        const sourceField = document.createElement('div');
        sourceField.className = 'mapping-field';
        sourceField.innerHTML = `
            <label>数据源字段</label>
            <select class="data-field-select">
                <option value="">请选择字段</option>
            </select>
        `;

        // Arrow
        const arrow = document.createElement('div');
        arrow.className = 'mapping-arrow';
        arrow.textContent = '→';

        // Target model field
        const targetField = document.createElement('div');
        targetField.className = 'mapping-field';
        targetField.innerHTML = `
            <label>模型参数</label>
            <select class="mapping-target-field">
                <option value="">请选择参数</option>
            </select>
        `;

 // Conversion section (middle)
        const conversion = document.createElement('div');
        conversion.className = 'mapping-conversion';
        conversion.innerHTML = `
            <div class="mapping-field conversion-type">
                <label>转换类型</label>
                <select class="conversion-select">
                    <option value="none">无转换</option>
                    <option value="formula">公式转换</option>
                    <option value="unit">单位转换</option>
                </select>
            </div>
            <div class="mapping-field conversion-formula">
                <label>转换公式</label>
                <input type="text" class="formula-input" placeholder="如: value * 1000 / 3600">
            </div>
        `;

        // Remove button
        const removeBtn = document.createElement('button');
        removeBtn.type = 'button';
        removeBtn.className = 'remove-mapping';
        removeBtn.textContent = '×';
        removeBtn.addEventListener('click', () => {
            row.remove();
        });

        // Assemble the row with conversion in the middle
        row.appendChild(sourceField);
        row.appendChild(conversion);
        row.appendChild(arrow);
        row.appendChild(targetField);
        row.appendChild(removeBtn);

        // Add to the list
        mappingsList.appendChild(row);

        // Update field options based on current selections
        this.updateMappingFieldOptionsForNewRow(sourceField, targetField);

        // If mapping data is provided, populate the fields
        if (mappingData) {
            const sourceSelect = sourceField.querySelector('.data-field-select');
            const targetSelect = targetField.querySelector('.model-field-select');
            const conversionSelect = conversion.querySelector('.conversion-select');
            const formulaInput = conversion.querySelector('.formula-input');
            
            if (mappingData.sourceField) sourceSelect.value = mappingData.sourceField;
            if (mappingData.targetField) targetSelect.value = mappingData.targetField;
            if (mappingData.conversionType) conversionSelect.value = mappingData.conversionType;
            if (mappingData.formula) formulaInput.value = mappingData.formula;
        }

        // Add event listener for conversion type change
        const conversionSelect = conversion.querySelector('.conversion-select');
        const formulaInput = conversion.querySelector('.formula-input');
        conversionSelect.addEventListener('change', () => {
            if (conversionSelect.value === 'none') {
                formulaInput.value = '';
                formulaInput.disabled = true;
            } else {
                formulaInput.disabled = false;
                if (conversionSelect.value === 'unit') {
                    // Pre-fill common unit conversion formulas
                    const dataSource = this.shadowRoot.getElementById('dataSource')?.value;
                    if (dataSource === 'car') {
                        formulaInput.placeholder = '如: value * 1000 / 3600 (km/h → m/s)';
                    }
                }
            }
        });
    }

    /**
     * Add a result mapping row to the result mappings list
     */
    addResultMapping(mappingData = null) {
        const resultMappingsList = this.shadowRoot.getElementById('resultMappingsList');
        if (!resultMappingsList) return;

        const row = document.createElement('div');
        row.className = 'mapping-row';

        // Model output field
        const modelField = document.createElement('div');
        modelField.className = 'mapping-field';
        modelField.innerHTML = `
            <label>模型输出</label>
            <select class="result-mapping-source-field">
                <option value="">请选择输出</option>
            </select>
        `;

        // Arrow
        const arrow = document.createElement('div');
        arrow.className = 'mapping-arrow';
        arrow.textContent = '→';

        // Result target field
        const resultField = document.createElement('div');
        resultField.className = 'mapping-field';
        resultField.innerHTML = `
            <label>回写目标</label>
            <input type="text" class="result-target-input" placeholder="请输入回写目标字段名">
        `;

        // Remove button
        const removeBtn = document.createElement('button');
        removeBtn.type = 'button';
        removeBtn.className = 'remove-mapping';
        removeBtn.textContent = '×';
        removeBtn.addEventListener('click', () => {
            row.remove();
        });

        // Assemble the row without conversion
        row.appendChild(modelField);
        row.appendChild(arrow);
        row.appendChild(resultField);
        row.appendChild(removeBtn);

        // Add to the list
        resultMappingsList.appendChild(row);

        // Update field options based on current selections
        this.updateResultMappingFieldOptionsForNewRow(modelField);

        // If mapping data is provided, populate the fields
        if (mappingData) {
            const modelSelect = modelField.querySelector('.result-mapping-source-field');
            const resultInput = resultField.querySelector('.result-target-input');
            
            if (mappingData.modelOutput) modelSelect.value = mappingData.modelOutput;
            if (mappingData.resultTarget) resultInput.value = mappingData.resultTarget;
        }
    }

    /**
     * Get all mappings from the mappings list
     */
    getMappings() {
        const mappings = [];
        const mappingRows = this.shadowRoot.querySelectorAll('#mappingsList .mapping-row');
        
        mappingRows.forEach(row => {
            const sourceField = row.querySelector('.data-field-select')?.value;
            const targetField = row.querySelector('.model-field-select')?.value;
            const conversionType = row.querySelector('.conversion-select')?.value;
            const formula = row.querySelector('.formula-input')?.value;
            
            if (sourceField && targetField) {
                mappings.push({ 
                    sourceField, 
                    targetField, 
                    conversionType: conversionType || 'none',
                    formula: formula || ''
                });
            }
        });
        
        return mappings;
    }

    /**
     * Get all result mappings from the result mappings list
     */
    getResultMappings() {
        const resultMappings = [];
        const resultMappingRows = this.shadowRoot.querySelectorAll('#resultMappingsList .mapping-row');
        
        resultMappingRows.forEach(row => {
            const modelOutput = row.querySelector('.result-mapping-source-field')?.value;
            const resultTarget = row.querySelector('.result-target-input')?.value;
            
            if (modelOutput && resultTarget) {
                resultMappings.push({ 
                    modelOutput, 
                    resultTarget
                });
            }
        });
        
        return resultMappings;
    }

    /**
     * Update mapping field options based on selected data source and target model
     */
    updateMappingFieldOptions() {
        const dataSource = this.shadowRoot.getElementById('dataSource')?.value;
        const targetModel = this.shadowRoot.getElementById('targetModel')?.value;
        
        const dataFields = this.getDataSourceFields(dataSource);
        const modelFields = this.getTargetModelFields(targetModel);
        
        // Update all mapping rows
        const mappingRows = this.shadowRoot.querySelectorAll('.mapping-row');
        mappingRows.forEach(row => {
            const sourceSelect = row.querySelector('.data-field-select');
            const targetSelect = row.querySelector('.model-field-select');
            
            // Update source field options
            if (sourceSelect) {
                const currentValue = sourceSelect.value;
                sourceSelect.innerHTML = '<option value="">请选择字段</option>';
                dataFields.forEach(field => {
                    const option = document.createElement('option');
                    option.value = field.id;
                    option.textContent = field.name;
                    if (field.id === currentValue) {
                        option.selected = true;
                    }
                    sourceSelect.appendChild(option);
                });
            }
            
            // Update target field options
            if (targetSelect) {
                const currentValue = targetSelect.value;
                targetSelect.innerHTML = '<option value="">请选择参数</option>';
                modelFields.forEach(field => {
                    const option = document.createElement('option');
                    option.value = field.id;
                    option.textContent = field.name;
                    if (field.id === currentValue) {
                        option.selected = true;
                    }
                    targetSelect.appendChild(option);
                });
            }
        });
    }

    /**
     * Update result mapping field options based on selected target model
     */
    updateResultMappingFieldOptions() {
        const targetModel = this.shadowRoot.getElementById('targetModel')?.value;
        
        const modelOutputs = this.getModelOutputs(targetModel);
        const resultTargets = this.getResultTargets();
        
        // Update all result mapping rows
        const resultMappingRows = this.shadowRoot.querySelectorAll('#resultMappingsList .mapping-row');
        resultMappingRows.forEach(row => {
            const modelSelect = row.querySelector('.result-mapping-source-field');
            
            // Update model output options
            if (modelSelect) {
                const currentValue = modelSelect.value;
                modelSelect.innerHTML = '<option value="">请选择输出</option>';
                modelOutputs.forEach(output => {
                    const option = document.createElement('option');
                    option.value = output.id;
                    option.textContent = output.name;
                    if (output.id === currentValue) {
                        option.selected = true;
                    }
                    modelSelect.appendChild(option);
                });
            }
            
            // Note: 回写目标是输入框，不需要更新选项
        });
    }

    /**
     * Get data source fields
     */
    getDataSourceFields(dataSource) {
        const mockData = {
            'car': [
                { id: 'root.car.s1', name: 'root.car.s1 (速度 km/h)' },
                { id: 'root.car.s2', name: 'root.car.s2 (转速 rpm)' },
                { id: 'root.car.temp', name: 'root.car.temp (温度 °C)' }
            ],
            'environment': [
                { id: 'env.temp', name: 'env.temp (环境温度 °C)' },
                { id: 'env.humidity', name: 'env.humidity (湿度 %)' },
                { id: 'env.pressure', name: 'env.pressure (气压 Pa)' }
            ],
            'device': [
                { id: 'device.status', name: 'device.status (设备状态)' },
                { id: 'device.power', name: 'device.power (功率 kW)' },
                { id: 'device.voltage', name: 'device.voltage (电压 V)' }
            ]
        };
        
        return mockData[dataSource] || [];
    }

    /**
     * Get target model fields
     */
    getTargetModelFields(targetModel) {
        const mockData = {
            'speedModel': [
                { id: 'Model.speed', name: 'Model.speed (速度 m/s)' },
                { id: 'Model.acceleration', name: 'Model.acceleration (加速度 m/s²)' }
            ],
            'tempModel': [
                { id: 'Model.temperature', name: 'Model.temperature (温度 K)' },
                { id: 'Model.heatIndex', name: 'Model.heatIndex (热指数)' }
            ],
            'pressureModel': [
                { id: 'Model.pressure', name: 'Model.pressure (压力 bar)' },
                { id: 'Model.flowRate', name: 'Model.flowRate (流量 L/min)' }
            ]
        };
        
        return mockData[targetModel] || [];
    }

    /**
     * Get model outputs for result mapping
     */
    getModelOutputs(targetModel) {
        const mockData = {
            'speedModel': [
                { id: 'Model.speed', name: 'Model.speed (计算速度 m/s)' },
                { id: 'Model.power', name: 'Model.power (计算功率 W)' }
            ],
            'tempModel': [
                { id: 'Model.temperature', name: 'Model.temperature (计算温度 K)' },
                { id: 'Model.heatIndex', name: 'Model.heatIndex (热指数)' }
            ],
            'pressureModel': [
                { id: 'Model.pressure', name: 'Model.pressure (计算压力 bar)' },
                { id: 'Model.flowRate', name: 'Model.flowRate (计算流量 L/min)' }
            ]
        };
        
        return mockData[targetModel] || [];
    }

    /**
     * Get result targets for writing back
     */
    getResultTargets() {
        const mockData = [
            { id: 'root.result.job01.power', name: 'root.result.job01.power' },
            { id: 'root.result.job01.speed', name: 'root.result.job01.speed' },
            { id: 'root.result.job01.temperature', name: 'root.result.job01.temperature' },
            { id: 'root.result.job02.power', name: 'root.result.job02.power' },
            { id: 'root.result.job02.status', name: 'root.result.job02.status' }
        ];
        
        return mockData;
    }

    /**
     * Setup interaction with external trees
     */
    setupTreeInteraction() {
        // Get reference to external trees
        const leftSidebar = document.querySelector('.left-sidebar');
        const rightSidebar = document.querySelector('.right-sidebar');
        
        if (leftSidebar) {
            // Add click listeners to data source tree nodes
            const dataTreeNodes = leftSidebar.querySelectorAll('.tree-node');
            dataTreeNodes.forEach(node => {
                node.addEventListener('click', (e) => {
                    e.stopPropagation();
                    this.handleDataSourceSelection(node);
                });
            });
        }
        
        if (rightSidebar) {
            // Add click listeners to model tree nodes
            const modelTreeNodes = rightSidebar.querySelectorAll('.tree-node');
            modelTreeNodes.forEach(node => {
                node.addEventListener('click', (e) => {
                    e.stopPropagation();
                    this.handleModelSelection(node);
                });
            });
        }
    }

    /**
     * Handle data source tree node selection
     */
    handleDataSourceSelection(node) {
        // Remove previous selection
        document.querySelectorAll('.left-sidebar .tree-node').forEach(n => {
            n.classList.remove('selected');
        });
        
        // Add selection to current node
        node.classList.add('selected');
        
        // Get the full path of the selected node
        const path = this.getTreePath(node);
        this.selectedDataSource = path;
        
        // Update modal if it's open
        this.updateModalDataSource(path);
    }

    /**
     * Handle model tree node selection
     */
    handleModelSelection(node) {
        // Remove previous selection
        document.querySelectorAll('.right-sidebar .tree-node').forEach(n => {
            n.classList.remove('selected');
        });
        
        // Add selection to current node
        node.classList.add('selected');
        
        // Get the full path of the selected node
        const path = this.getTreePath(node);
        this.selectedModel = path;
        
        // Update modal if it's open
        this.updateModalModel(path);
    }

    /**
     * Get the full path of a tree node
     */
    getTreePath(node) {
        const path = [];
        let current = node;
        
        while (current && current.classList.contains('tree-node')) {
            const text = current.querySelector('span')?.textContent || current.textContent;
            path.unshift(text);
            current = current.parentElement.closest('.tree-node');
        }
        
        return path.join('.');
    }

    /**
     * Update modal with selected data source
     */
    updateModalDataSource(path) {
        const dataSourceSelect = this.shadowRoot.getElementById('dataSource');
        if (dataSourceSelect && this.isModalOpen()) {
            // Try to match with existing options or add custom option
            let option = Array.from(dataSourceSelect.options).find(opt => 
                opt.textContent.includes(path) || opt.value === path
            );
            
            if (!option) {
                option = document.createElement('option');
                option.value = path;
                option.textContent = path;
                dataSourceSelect.appendChild(option);
            }
            
            dataSourceSelect.value = path;
            this.updateMappingFieldOptions();
        }
    }

    /**
     * Update modal with selected model
     */
    updateModalModel(path) {
        const targetModelSelect = this.shadowRoot.getElementById('targetModel');
        if (targetModelSelect && this.isModalOpen()) {
            // Try to match with existing options or add custom option
            let option = Array.from(targetModelSelect.options).find(opt => 
                opt.textContent.includes(path) || opt.value === path
            );
            
            if (!option) {
                option = document.createElement('option');
                option.value = path;
                option.textContent = path;
                targetModelSelect.appendChild(option);
            }
            
            targetModelSelect.value = path;
            this.updateMappingFieldOptions();
            this.updateResultMappingFieldOptions();
        }
    }

    /**
     * Check if modal is open
     */
    isModalOpen() {
        const modal = this.shadowRoot.getElementById('modalMask');
        return modal && !modal.hidden && modal.style.display !== 'none';
    }

    importRules() {
        alert('导入功能待实现');
    }

    exportRules() {
        alert('导出功能待实现');
    }
    
    copyRule(id) {
        const rule = this.data.find(item => item.id === id);
        if (!rule) return;
        
        // Show add modal with copied data
        this.showCopyModal(rule);
    }
    
    showCopyModal(rule) {
        const modal = this.shadowRoot.getElementById('modalMask');
        const title = this.shadowRoot.getElementById('modalTitle');
        const form = this.shadowRoot.getElementById('ruleForm');
        
        if (modal && title && form && rule) {
            // Restore form content if it was replaced by showModal
            this.restoreFormContent();
            
            title.textContent = '新增关联规则';
            form.reset();
            
            // Fill the form with copied rule data
            this.shadowRoot.getElementById('ruleName').value = rule.ruleName + ' - 副本';
            this.shadowRoot.getElementById('ruleDesc').value = rule.ruleDesc || '';
            this.shadowRoot.getElementById('dataSource').value = rule.dataSource || '';
            this.shadowRoot.getElementById('targetModel').value = rule.targetModel || '';
            this.shadowRoot.getElementById('version').value = rule.version || 'v1.0.0';
            
            // Set status radio button to active by default for new copy
            this.shadowRoot.querySelector('input[name="status"][value="active"]').checked = true;
            
            // Clear any rule ID to ensure this creates a new rule
            delete form.dataset.ruleId;
            this.currentAction = 'add';
            
            // Restore form footer buttons
            this.restoreFormFooter();
            
            // Highlight external trees
            document.body.classList.add('association-rules-modal-open');
            
            // Initialize mappings with copied data if available
            if (rule.mappings && rule.mappings.length > 0) {
                this.initializeMappings();
                // Clear existing mappings and add copied ones
                const mappingsList = this.shadowRoot.getElementById('mappingsList');
                mappingsList.innerHTML = '';
                rule.mappings.forEach(mapping => {
                    this.addMapping(mapping);
                });
            } else {
                this.initializeMappings();
            }
            
            // Initialize result mappings with copied data if available
            if (rule.resultMappings && rule.resultMappings.length > 0) {
                this.initializeResultMappings();
                // Clear existing result mappings and add copied ones
                const resultMappingsList = this.shadowRoot.getElementById('resultMappingsList');
                resultMappingsList.innerHTML = '';
                rule.resultMappings.forEach(mapping => {
                    this.addResultMapping(mapping);
                });
            } else {
                this.initializeResultMappings();
            }
            
            modal.hidden = false;
            modal.style.display = 'flex';
        }
    }
    
    restoreFormContent() {
        const modalBody = this.shadowRoot.getElementById('modalBody');
        if (!modalBody) return;
        
        // Check if form content exists, if not, restore it
        const existingForm = modalBody.querySelector('#ruleForm');
        if (!existingForm) {
            // Restore the original form content
            modalBody.innerHTML = `
                <form id="ruleForm" class="rule-form">
                    <div class="form-row">
                        <div class="form-group">
                            <label for="ruleName">规则名称</label>
                            <input type="text" id="ruleName" name="ruleName" required placeholder="请输入规则名称">
                        </div>
                        <div class="form-group">
                            <label for="ruleDesc">规则描述</label>
                            <input type="text" id="ruleDesc" name="ruleDesc" placeholder="请输入规则描述">
                        </div>
                    </div>
                    
                    <div class="form-section">
                        <div class="section-title">数据映射配置</div>
                        <div class="mapping-config">
                            <div class="mapping-header">
                                <div class="mapping-source">
                                    <label>数据源</label>
                                    <select id="dataSource" class="data-source-select">
                                        <option value="">请选择数据源</option>
                                        <option value="car">车辆数据</option>
                                        <option value="environment">环境数据</option>
                                        <option value="device">设备数据</option>
                                    </select>
                                </div>
                                <div class="mapping-target">
                                    <label>目标模型</label>
                                    <select id="targetModel" class="target-model-select">
                                        <option value="">请选择目标模型</option>
                                        <option value="speedModel">速度模型</option>
                                        <option value="tempModel">温度模型</option>
                                        <option value="pressureModel">压力模型</option>
                                    </select>
                                </div>
                                <div class="mapping-version">
                                    <label for="version">版本</label>
                                    <select id="version" name="version" class="version-select">
                                        <option value="v1.0.0">v1.0.0</option>
                                        <option value="v1.1.0">v1.1.0</option>
                                        <option value="v2.0.0">v2.0.0</option>
                                    </select>
                                </div>
                            </div>
                            
                            <div class="mapping-section">
                                <div class="mapping-title">输入映射关系（数据源 → 模型）</div>
                                <div class="mappings-list" id="mappingsList">
                                    <!-- 动态添加映射行 -->
                                </div>
                                <button type="button" class="add-mapping-btn" id="addMapping">+ 添加映射</button>
                            </div>
                            
                            <div class="mapping-section">
                                <div class="mapping-title">结果回写映射（模型 → 数据源）</div>
                                <div class="mappings-list" id="resultMappingsList">
                                    <!-- 动态添加结果映射行 -->
                                </div>
                                <button type="button" class="add-mapping-btn" id="addResultMapping">+ 添加回写映射</button>
                            </div>
                        </div>
                    </div>
                    
                    <div class="form-row">
                        <div class="form-group">
                            <label>状态</label>
                            <div class="radio-group">
                                <label class="radio-label">
                                    <input type="radio" name="status" value="active" checked>
                                    <span class="radio-custom"></span>
                                    <span>启用</span>
                                </label>
                                <label class="radio-label">
                                    <input type="radio" name="status" value="inactive">
                                    <span class="radio-custom"></span>
                                    <span>禁用</span>
                                </label>
                            </div>
                        </div>
                    </div>
                </form>
            `;
            
            // Re-bind form events after restoring content
            this.bindFormEvents();
        }
    }
    
    restoreFormFooter() {
        const modalFooter = this.shadowRoot.getElementById('modalFooter');
        if (modalFooter) {
            modalFooter.innerHTML = `
                <button type="button" class="btn btn-cancel" id="cancelBtn">取消</button>
                <button type="button" class="btn btn-confirm" id="saveBtn">确定</button>
            `;
            
            // Re-bind footer events
            this.bindFooterEvents();
        }
    }
    
    bindFormEvents() {
        // Re-bind form-specific events
        this.shadowRoot.getElementById('addMapping')?.addEventListener('click', () => this.addMapping());
        this.shadowRoot.getElementById('addResultMapping')?.addEventListener('click', () => this.addResultMapping());
        
        // Data source and target model change events
        this.shadowRoot.getElementById('dataSource')?.addEventListener('change', () => this.updateMappingFieldOptions());
        this.shadowRoot.getElementById('targetModel')?.addEventListener('change', () => {
            this.updateMappingFieldOptions();
            this.updateResultMappingFieldOptions();
        });
        
        // Form submission
        this.shadowRoot.getElementById('ruleForm')?.addEventListener('submit', (e) => {
            e.preventDefault();
            this.saveRule();
        });
    }
    
    bindFooterEvents() {
        // Re-bind footer button events
        this.shadowRoot.getElementById('cancelBtn')?.addEventListener('click', () => this.hideModal());
        this.shadowRoot.getElementById('saveBtn')?.addEventListener('click', () => this.saveRule());
    }
    
    runRule(id) {
        const rule = this.data.find(item => item.id === id);
        if (!rule) return;
        
        this.showRunModal(rule);
    }
    
    showRunModal(rule) {
        const modal = this.shadowRoot.getElementById('modalMask');
        const title = this.shadowRoot.getElementById('modalTitle');
        const modalBody = this.shadowRoot.getElementById('modalBody');
        const modalFooter = this.shadowRoot.getElementById('modalFooter');
        
        if (modal && title && modalBody && modalFooter) {
            title.textContent = '运行关联规则';
            
            // Create run form HTML
            modalBody.innerHTML = `
                <form id="runForm" class="run-form">
                    <div class="form-row">
                        <div class="form-group">
                            <label for="runName">名称</label>
                            <input type="text" id="runName" name="runName" required placeholder="请输入运行名称" value="${rule.ruleName || ''}">
                        </div>
                    </div>
                    
                    <div class="form-row">
                        <div class="form-group">
                            <label for="startTime">开始时间</label>
                            <input type="date" id="startTime" name="startTime" required value="${new Date().toISOString().split('T')[0]}">
                        </div>
                        <div class="form-group">
                            <label for="endTime">结束时间</label>
                            <input type="date" id="endTime" name="endTime" required value="${new Date().toISOString().split('T')[0]}">
                        </div>
                    </div>
                </form>
            `;
            
            // Set footer buttons for run modal
            modalFooter.innerHTML = `
                <button type="button" class="btn btn-cancel" id="runCancelBtn">取消</button>
                <button type="button" class="btn btn-confirm" id="runExecuteBtn">立即运行</button>
            `;
            
            // Store the rule ID for execution
            this.currentRunRuleId = rule.id;
            
            // Re-bind events for run modal
            this.bindRunModalEvents();
            
            modal.hidden = false;
            modal.style.display = 'flex';
        }
    }
    
    bindRunModalEvents() {
        // Cancel button
        this.shadowRoot.getElementById('runCancelBtn')?.addEventListener('click', () => {
            this.hideModal();
        });
        
        // Execute button
        this.shadowRoot.getElementById('runExecuteBtn')?.addEventListener('click', () => {
            this.executeRule();
        });
        
        // Form submission
        this.shadowRoot.getElementById('runForm')?.addEventListener('submit', (e) => {
            e.preventDefault();
            this.executeRule();
        });
    }
    
    executeRule() {
        const runName = this.shadowRoot.getElementById('runName')?.value.trim();
        const startTime = this.shadowRoot.getElementById('startTime')?.value;
        const endTime = this.shadowRoot.getElementById('endTime')?.value;
        
        if (!runName) {
            this.showToast('请输入运行名称', 'error');
            return;
        }
        
        if (!startTime || !endTime) {
            this.showToast('请选择开始时间和结束时间', 'error');
            return;
        }
        
        if (new Date(startTime) > new Date(endTime)) {
            this.showToast('开始时间不能晚于结束时间', 'error');
            return;
        }
        
        const rule = this.data.find(item => item.id === this.currentRunRuleId);
        if (rule) {
            this.showToast(`正在运行规则: ${runName}\n规则: ${rule.ruleName}\n时间范围: ${startTime} 至 ${endTime}`);
            // TODO: Implement actual rule execution logic
        }
        
        this.hideModal();
    }
    
    toggleRuleStatus(id) {
        const rule = this.data.find(item => item.id === id);
        if (!rule) return;
        
        rule.status = rule.status === 'active' ? 'inactive' : 'active';
        rule.updateTime = new Date().toLocaleString('zh-CN');
        
        this.renderTable();
        this.showToast(`规则 "${rule.ruleName}" 已${rule.status === 'active' ? '启用' : '禁用'}`);
    }
    
    // 动态加载数据源选项 - 参考database-table.js的表名获取
    loadDataSourceOptions() {
        const dataSourceSelect = this.shadowRoot.getElementById('dataSource');
        if (!dataSourceSelect) return;
        
        // 获取左侧关系查询的表名 - 参考 database-table.js 的表名获取方式
        const leftSidebarTree = document.querySelector('.left-sidebar .tree');
        if (!leftSidebarTree) {
            console.warn('未找到左侧关系查询树');
            return;
        }
        
        const allNodes = leftSidebarTree.querySelectorAll('.tree-node');
        const tableNames = new Set();
        
        allNodes.forEach(node => {
            const span = node.querySelector('span');
            if (span) {
                const nodeName = span.textContent.trim();
                
                // 排除根节点
                if (nodeName === 'relational_system') {
                    return;
                }
                
                // 判断是否为字段（最后一级叶子节点）
                const isField = !node.querySelector('.tree-children');
                if (isField) {
                    // 字段节点，获取其父节点（表名）
                    const parentNode = node.parentElement?.parentElement;
                    if (parentNode && parentNode.classList.contains('tree-node')) {
                        const tablePath = this.getFullTablePath(parentNode);
                        tableNames.add(tablePath);
                    }
                }
            }
        });
        
        console.log('获取到的数据源表名:', Array.from(tableNames));
        
        // 清空现有选项
        dataSourceSelect.innerHTML = '<option value="">请选择数据源</option>';
        
        // 添加表名选项
        Array.from(tableNames).forEach(tableName => {
            const option = document.createElement('option');
            option.value = tableName;
            option.textContent = tableName;
            dataSourceSelect.appendChild(option);
        });
        
        // 监听数据源变化，加载字段
        dataSourceSelect.addEventListener('change', () => {
            this.loadDataSourceFields(dataSourceSelect.value);
        });
    }

    // 获取表的完整路径
    getFullTablePath(node) {
        const parts = [];
        let current = node;
        let foundRoot = false;
        
        while (current && current.classList.contains('tree-node')) {
            const span = current.querySelector('span');
            if (span) {
                const nodeName = span.textContent.trim();
                // 包含relational_system根路径
                if (nodeName === 'relational_system') {
                    foundRoot = true;
                }
                parts.unshift(nodeName);
            }
            current = current.parentElement?.parentElement;
        }
        
        // 确保包含根路径
        if (!foundRoot && parts.length > 0) {
            parts.unshift('relational_system');
        }
        
        return parts.join('.');
    }
    
    // 动态加载数据源字段
    loadDataSourceFields(tableName) {
        if (!tableName) return;
        
        console.log('加载表字段:', tableName);
        
        // 从左侧树中获取该表的字段（最后一级叶子节点）
        const leftSidebarTree = document.querySelector('.left-sidebar .tree');
        if (!leftSidebarTree) return;
        
        const allNodes = leftSidebarTree.querySelectorAll('.tree-node');
        const fields = new Set();
        
        allNodes.forEach(node => {
            const span = node.querySelector('span');
            if (span) {
                const nodeName = span.textContent.trim();
                
                // 判断是否为字段（最后一级叶子节点）
                const isField = !node.querySelector('.tree-children');
                if (isField) {
                    // 获取父节点的完整路径
                    const parentNode = node.parentElement?.parentElement;
                    if (parentNode && parentNode.classList.contains('tree-node')) {
                        const parentPath = this.getFullTablePath(parentNode);
                        if (parentPath === tableName) {
                            fields.add(nodeName);
                        }
                    }
                }
            }
        });
        
        console.log('获取到的字段:', Array.from(fields));
        
        // 更新所有映射行中的数据源字段选项
        const mappingRows = this.shadowRoot.querySelectorAll('.mapping-row');
        mappingRows.forEach(row => {
            const sourceSelect = row.querySelector('.data-field-select');
            if (sourceSelect) {
                const currentValue = sourceSelect.value;
                sourceSelect.innerHTML = '<option value="">请选择字段</option>';
                
                // 添加字段选项
                Array.from(fields).forEach(field => {
                    const option = document.createElement('option');
                    option.value = field;
                    option.textContent = field;
                    sourceSelect.appendChild(option);
                });
                
                // 恢复之前选择的值
                if (currentValue) {
                    sourceSelect.value = currentValue;
                }
            }
        });
    }
    
    // 动态加载目标模型选项 - 参考model-download.js的模型获取
    loadTargetModelOptions() {
        const targetModelSelect = this.shadowRoot.getElementById('targetModel');
        if (!targetModelSelect) return;
        
        // 获取右侧模型资产库的根节点 - 参考 model-download.js 的模型获取方式
        const rightSidebarTree = document.querySelector('.right-sidebar .tree');
        if (!rightSidebarTree) {
            console.warn('未找到右侧模型资产库树');
            return;
        }
        
        const allNodes = rightSidebarTree.querySelectorAll('.tree-node');
        const modelNames = new Set(); // 使用Set避免重复
        
        allNodes.forEach(node => {
            const span = node.querySelector('span');
            if (span) {
                const nodeName = span.textContent.trim();
                
                // 排除明显的路径节点
                if (nodeName === 'models_system') {
                    return;
                }
                
                // 检查是否为父节点（有子节点）
                const hasChildren = node.querySelector('.tree-children');
                if (hasChildren) {
                    // 检查子节点中是否有叶子节点
                    const childNodes = node.querySelectorAll('.tree-node .tree-node');
                    const hasLeafChild = Array.from(childNodes).some(child => !child.querySelector('.tree-children'));
                    
                    // 只有当子节点包含叶子节点时，才将父节点作为模型名称
                    if (hasLeafChild) {
                        modelNames.add(nodeName);
                    }
                }
            }
        });
        
        console.log('获取到的目标模型名称:', Array.from(modelNames));
        
        // 清空现有选项
        targetModelSelect.innerHTML = '<option value="">请选择目标模型</option>';
        
        // 添加模型名称选项
        Array.from(modelNames).forEach(name => {
            const option = document.createElement('option');
            option.value = name;
            option.textContent = name;
            targetModelSelect.appendChild(option);
        });
        
        // 监听目标模型变化，加载版本
        targetModelSelect.addEventListener('change', () => {
            console.log('目标模型变化，加载版本');
            this.loadModelVersions(targetModelSelect.value);
            // 不在这里加载字段，等版本选择后再加载
        });
        
        // 监听版本变化，加载模型字段 - 使用更可靠的方式
        const versionSelect = this.shadowRoot.getElementById('version');
        if (versionSelect) {
            // 使用事件委托方式监听
            const handleVersionChange = (event) => {
                console.log('版本change事件触发:', event);
                console.log('版本select当前值:', versionSelect.value);
                
                // 重新获取目标模型select元素
                const currentTargetModelSelect = this.shadowRoot.getElementById('targetModel');
                console.log('目标模型select元素:', currentTargetModelSelect);
                console.log('目标模型当前值:', currentTargetModelSelect.value);
                
                const selectedModel = currentTargetModelSelect.value;
                if (selectedModel && versionSelect.value) {
                    console.log('版本变化，加载模型字段:', selectedModel, versionSelect.value);
                    this.loadModelFields(selectedModel);
                } else {
                    console.log('条件不满足 - selectedModel:', selectedModel, 'version:', versionSelect.value);
                }
            };
            
            // 移除所有可能的监听器
            versionSelect.removeEventListener('change', handleVersionChange);
            versionSelect.removeEventListener('blur', handleVersionChange);
            
            // 添加新的监听器
            versionSelect.addEventListener('change', handleVersionChange);
            versionSelect.addEventListener('blur', handleVersionChange);
        }
    }
    
    // 动态加载模型版本 - 参考model-download.js的版本获取
    loadModelVersions(modelName) {
        const versionSelect = this.shadowRoot.getElementById('version');
        if (!versionSelect) return;
        
        console.log('加载模型版本:', modelName);
        
        // 如果没有选择模型，清空版本下拉
        if (!modelName) {
            versionSelect.innerHTML = '<option value="">请选择版本</option>';
            return;
        }
        
        // 获取右侧模型资产库的版本信息
        const rightSidebarTree = document.querySelector('.right-sidebar .tree');
        if (!rightSidebarTree) return;
        
        const allNodes = rightSidebarTree.querySelectorAll('.tree-node');
        const versions = [];
        
        allNodes.forEach(node => {
            const span = node.querySelector('span');
            if (span) {
                const nodeName = span.textContent.trim();
                
                // 排除明显的路径节点
                if (nodeName === 'models_system') {
                    return;
                }
                
                // 检查是否为叶子节点（版本）
                const isLeaf = !node.querySelector('.tree-children');
                if (isLeaf) {
                    const parentNode = node.closest('.tree-children')?.parentElement;
                    if (parentNode) {
                        const parentSpan = parentNode.querySelector('span');
                        if (parentSpan && parentSpan.textContent.trim() === modelName) {
                            versions.push(nodeName);
                        }
                    }
                }
            }
        });
        
        console.log('获取到的模型版本:', versions);
        
        // 保存当前值
        const currentValue = versionSelect.value;
        
        // 清空现有选项
        versionSelect.innerHTML = '';
        
        // 添加版本选项
        versions.forEach(version => {
            const option = document.createElement('option');
            option.value = version;
            option.textContent = version;
            versionSelect.appendChild(option);
            console.log('添加版本选项:', version);
        });
        
        console.log('版本下拉框当前选项数量:', versionSelect.options.length);
        
        // 尝试恢复之前的选择
        if (currentValue && versions.includes(currentValue)) {
            versionSelect.value = currentValue;
        }
        
        // 手动触发change事件（如果版本已选择）
        if (versionSelect.value && versions.includes(versionSelect.value)) {
            console.log('手动触发版本change事件');
            const changeEvent = new Event('change', { bubbles: true });
            versionSelect.dispatchEvent(changeEvent);
        }
    }
    
    // 动态加载模型字段 - 参考model-detail.js的inputs/outputs解析
    loadModelFields(modelName) {
        if (!modelName) return;
        
        console.log('加载模型字段:', modelName);
        // 获取当前选择的版本
        const versionSelect = this.shadowRoot.getElementById('version');
        const selectedVersion = versionSelect.value;
        
        if (!selectedVersion) {
            console.warn('请先选择模型版本');
            return;
        }
        
        // 这里需要调用模型详情接口获取inputs和outputs
        // 参考 model-detail.js 的 renderParamsTable 方法
        
        // 示例：调用模型详情接口
        fetch(window.AppConfig.api.baseURL + '/api/model/metas?name=' + encodeURIComponent(modelName) + '&version=' + encodeURIComponent(selectedVersion))
            .then(response => response.json())
            .then(result => {
                if (result.code === 200 && result.data) {
                    const modelData = result.data;
                    
                    // 解析inputs字段
                    let inputs = [];
                    if (modelData.inputs) {
                        try {
                            inputs = typeof modelData.inputs === 'string' ? JSON.parse(modelData.inputs) : modelData.inputs;
                        } catch (error) {
                            console.error('解析inputs参数数据失败:', error);
                        }
                    }
                    
                    // 解析outputs字段
                    let outputs = [];
                    if (modelData.outputs) {
                        try {
                            outputs = typeof modelData.outputs === 'string' ? JSON.parse(modelData.outputs) : modelData.outputs;
                        } catch (error) {
                            console.error('解析outputs参数数据失败:', error);
                        }
                    }
                    
                    console.log('模型字段:', { inputs, outputs });
                    
                    // 更新映射字段的下拉选项
                    this.updateMappingFieldOptions(inputs, outputs);
                }
            })
            .catch(error => {
                console.error('获取模型详情失败:', error);
            });
    }
    
    // 更新映射字段的下拉选项
    updateMappingFieldOptions(inputs, outputs) {
        // 如果没有传入inputs/outputs，则不更新
        if (!inputs || !outputs) {
            return;
        }
        
        // 更新输入映射的目标字段选项（模型参数）
        const mappingTargetFields = this.shadowRoot.querySelectorAll('.mapping-target-field');
        mappingTargetFields.forEach(select => {
            const currentValue = select.value;
            select.innerHTML = '<option value="">请选择参数</option>';
            inputs.forEach(input => {
                const option = document.createElement('option');
                option.value = input.name || input;
                option.textContent = `${input.name || input} (${input.type || 'string'})`;
                select.appendChild(option);
            });
            if (currentValue) select.value = currentValue;
        });
        
        // 更新输出映射的源字段选项（模型输出）
        const resultMappingSourceFields = this.shadowRoot.querySelectorAll('.result-mapping-source-field');
        resultMappingSourceFields.forEach(select => {
            const currentValue = select.value;
            select.innerHTML = '<option value="">请选择字段</option>';
            outputs.forEach(output => {
                const option = document.createElement('option');
                option.value = output.name || output;
                option.textContent = `${output.name || output} (${output.type || 'string'})`;
                select.appendChild(option);
            });
            if (currentValue) select.value = currentValue;
        });
    }
    
    // 为新添加的映射行更新字段选项
    updateMappingFieldOptionsForNewRow(sourceField, targetField) {
        // 更新数据源字段选项
        const dataSource = this.shadowRoot.getElementById('dataSource')?.value;
        if (dataSource) {
            const sourceSelect = sourceField.querySelector('.data-field-select');
            if (sourceSelect) {
                sourceSelect.innerHTML = '<option value="">请选择字段</option>';
                
                // 从左侧树中获取该表的字段
                const leftSidebarTree = document.querySelector('.left-sidebar .tree');
                if (leftSidebarTree) {
                    const allNodes = leftSidebarTree.querySelectorAll('.tree-node');
                    const fields = new Set();
                    
                    allNodes.forEach(node => {
                        const span = node.querySelector('span');
                        if (span) {
                            const nodeName = span.textContent.trim();
                            const isField = !node.querySelector('.tree-children');
                            if (isField) {
                                const parentNode = node.parentElement?.parentElement;
                                if (parentNode && parentNode.classList.contains('tree-node')) {
                                    const parentPath = this.getFullTablePath(parentNode);
                                    if (parentPath === dataSource) {
                                        fields.add(nodeName);
                                    }
                                }
                            }
                        }
                    });
                    
                    // 添加字段选项
                    Array.from(fields).forEach(field => {
                        const option = document.createElement('option');
                        option.value = field;
                        option.textContent = field;
                        sourceSelect.appendChild(option);
                    });
                }
            }
        }
        
        // 更新模型参数选项
        const targetModel = this.shadowRoot.getElementById('targetModel')?.value;
        const version = this.shadowRoot.getElementById('version')?.value;
        if (targetModel && version) {
            const targetSelect = targetField.querySelector('.mapping-target-field');
            if (targetSelect) {
                targetSelect.innerHTML = '<option value="">请选择参数</option>';
                
                // 调用API获取模型参数
                fetch(window.AppConfig.api.baseURL + '/api/model/metas?name=' + encodeURIComponent(targetModel) + '&version=' + encodeURIComponent(version))
                    .then(response => response.json())
                    .then(result => {
                        if (result.code === 200 && result.data) {
                            const modelData = result.data;
                            let inputs = [];
                            if (modelData.inputs) {
                                inputs = typeof modelData.inputs === 'string' ? JSON.parse(modelData.inputs) : modelData.inputs;
                            }
                            
                            // 添加模型参数选项
                            inputs.forEach(input => {
                                const option = document.createElement('option');
                                option.value = input.name || input;
                                option.textContent = `${input.name || input} (${input.type || 'string'})`;
                                targetSelect.appendChild(option);
                            });
                        }
                    })
                    .catch(error => {
                        console.error('获取模型参数失败:', error);
                    });
            }
        }
    }

    // 为新添加的回写映射行更新字段选项
    updateResultMappingFieldOptionsForNewRow(modelField) {
        // 更新模型输出选项
        const targetModel = this.shadowRoot.getElementById('targetModel')?.value;
        const version = this.shadowRoot.getElementById('version')?.value;
        if (targetModel && version) {
            const modelSelect = modelField.querySelector('.result-mapping-source-field');
            if (modelSelect) {
                modelSelect.innerHTML = '<option value="">请选择输出</option>';
                
                // 调用API获取模型输出
                fetch(window.AppConfig.api.baseURL + '/api/model/metas?name=' + encodeURIComponent(targetModel) + '&version=' + encodeURIComponent(version))
                    .then(response => response.json())
                    .then(result => {
                        if (result.code === 200 && result.data) {
                            const modelData = result.data;
                            let outputs = [];
                            if (modelData.outputs) {
                                outputs = typeof modelData.outputs === 'string' ? JSON.parse(modelData.outputs) : modelData.outputs;
                            }
                            
                            // 添加模型输出选项
                            outputs.forEach(output => {
                                const option = document.createElement('option');
                                option.value = output.name || output;
                                option.textContent = `${output.name || output} (${output.type || 'string'})`;
                                modelSelect.appendChild(option);
                            });
                        }
                    })
                    .catch(error => {
                        console.error('获取模型输出失败:', error);
                    });
            }
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
    
        
    initPagination() {
        const pagination = this.shadowRoot.getElementById('pagination');
        if (pagination) {
            // 监听分页变化事件
            pagination.addEventListener('pagination-change', (event) => {
                const { currentPage, pageSize } = event.detail;
                this.currentPage = currentPage;
                this.pageSize = pageSize;
                this.renderTable();
            });
            
            // 初始化分页
            this.updatePagination();
        }
    }

    updatePagination() {
        const pagination = this.shadowRoot.getElementById('pagination');
        if (pagination) {
            pagination.setPagination(this.currentPage, this.pageSize, this.data.length);
        }
    }

    hide() {
        console.log('AssociationRules.hide() called');
        this.removeAttribute('show');
        this.style.display = 'none';
    }
}

customElements.define('association-rules', AssociationRules);
