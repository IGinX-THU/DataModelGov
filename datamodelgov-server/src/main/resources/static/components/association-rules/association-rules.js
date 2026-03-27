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
            const result = await window.AppConfig.post('associationRules', 'query', requestBody);
            console.log('查询结果:', result);
            
            if (result.success && result.data) {
                // 后端直接返回List<AssociationRulesEntity>，转换为前端所需格式
                this.data = result.data.map(rule => ({
                    id: rule.createTime, // 使用createTime作为唯一标识
                    ruleName: rule.name,
                    ruleDesc: rule.description,
                    dataSource: rule.tableName,
                    targetModel: rule.modelName,
                    version: rule.modelVersion,
                    cmd: rule.cmd,
                    inputCsvName: rule.inputCsvName,
                    outputCsvName: rule.outputCsvName,
                    status: rule.status ? 'active' : 'inactive',
                    mappings: rule.inputsBind ? JSON.parse(rule.inputsBind) : [],
                    resultMappings: rule.outputsBind ? JSON.parse(rule.outputsBind) : [],
                    updateTime: new Date(rule.updateTime).toLocaleString('zh-CN'),
                    createTime: rule.createTime
                }));
                
                // 同时获取总数用于分页（仅在第一页时）
                if (this.currentPage === 1) {
                    await this.loadRulesCount(nameFilter, statusFilter);
                }
                
                console.log('加载的规则数据:', this.data);
                console.log('当前totalCount:', this.totalCount);
                
                // 渲染表格
                this.renderTable();
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
            
            // 使用新的API配置
            const result = await window.AppConfig.post('associationRules', 'count', requestBody);
            console.log('总量查询结果:', result);
            
            if (result.success && result.data !== undefined) {
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
            // 使用新的API配置
            const result = await window.AppConfig.delete('associationRules', 'delete', { createTime });
            
            if (result.success) {
                await this.loadRulesFromAPI();
                this.renderTable();
                this.showToast('规则已删除');
            } else {
                this.showToast(result.message || '删除失败', 'error');
            }
        } catch (error) {
            console.error('删除规则失败:', error);
            this.showToast('网络错误，删除失败', 'error');
        }
        
        // 无论成功还是失败，都关闭确认框
        this.hideModal();
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
            <div class="pagination-left">
                <button class="page-btn" id="prevPage">&lt;</button>
                <div class="page-list" id="pageList"></div>
                <button class="page-btn" id="nextPage">&gt;</button>
            </div>
            <div class="pagination-right">
                <span class="total-count">共 <span id="totalCount">0</span> 条</span>
                <select class="page-size-select" id="pageSizeSelect">
                    <option value="5">5条/页</option>
                    <option value="10">10条/页</option>
                    <option value="20">20条/页</option>
                    <option value="50">50条/页</option>
                </select>
            </div>
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
        this.shadowRoot.getElementById('modalClose')?.addEventListener('click', () => {
            console.log('🔴 右上角关闭按钮被点击');
            this.hideModal();
        });
        this.shadowRoot.getElementById('cancelBtn')?.addEventListener('click', () => this.hideModal());
        this.shadowRoot.getElementById('saveBtn')?.addEventListener('click', () => this.saveRule());
        
        // 添加映射按钮
        this.shadowRoot.getElementById('addMapping')?.addEventListener('click', async () => this.addMapping());
        this.shadowRoot.getElementById('addResultMapping')?.addEventListener('click', async () => this.addResultMapping());
        
        // 数据源和目标模型变化事件
        this.shadowRoot.getElementById('dataSource')?.addEventListener('change', () => this.updateMappingFieldOptions());
        this.shadowRoot.getElementById('targetModel')?.addEventListener('change', () => {
            this.updateMappingFieldOptions();
            this.updateResultMappingFieldOptions();
        });
        
        // 移除点击遮罩关闭功能，避免误操作
        // this.shadowRoot.getElementById('modalMask')?.addEventListener('click', (e) => {
        //     if (e.target === this.shadowRoot.getElementById('modalMask')) {
        //         console.log('🔴 点击遮罩层关闭');
        //         this.hideModal();
        //     }
        // });
        
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
                        // 不在这里更新按钮文本，等状态保存成功后由renderTable刷新
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
                        ${item.status === 'active' ? `<button class="action-btn run" data-action="run" data-id="${item.id}">运行</button>` : ''}
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

        // 使用后端分页数据，不再进行本地分页
        const pageData = this.data; // ✅ 直接使用后端返回的数据

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
                        ${item.status === 'active' ? `<button class="action-btn run" data-action="run" data-id="${item.id}">运行</button>` : ''}
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
            // 移除规则名称的readonly属性
            const ruleNameInput = this.shadowRoot.getElementById('ruleName');
            if (ruleNameInput) {
                ruleNameInput.removeAttribute('readonly');
            }
            modal.hidden = false;
            modal.style.display = 'flex';
            // 移除静态版本值，等待模型选择后加载
            this.shadowRoot.getElementById('version').innerHTML = '<option value="">请选择版本</option>';
            this.shadowRoot.querySelector('input[name="status"][value="active"]').checked = true;
            this.currentAction = 'add';
            
            // Restore form footer buttons
            this.restoreFormFooter();
            
            // Bind form events for new rule
            this.bindFormEvents();
            
            // Highlight external trees
            document.body.classList.add('association-rules-modal-open');
            
            // 初始化动态数据源和目标模型
            this.loadDataSourceOptions();
            this.loadTargetModelOptions();
            
            // Initialize empty mappings list
            this.initializeMappings();
            this.initializeResultMappings();
            
            // Bind form events for new rule
            this.bindFormEvents();
        }
    }

    async showEditModal(rule) {
        const modal = this.shadowRoot.getElementById('modalMask');
        const title = this.shadowRoot.getElementById('modalTitle');
        const form = this.shadowRoot.getElementById('ruleForm');
        
        if (modal && title && form && rule) {
            // Restore form content if it was replaced by showModal
            this.restoreFormContent();
            
            // Debug: Check if form elements exist after restoration
            setTimeout(() => {
                console.log('Form elements after restore:');
                console.log('cmd element:', this.shadowRoot.getElementById('cmd'));
                console.log('inputCsvName element:', this.shadowRoot.getElementById('inputCsvName'));
                console.log('outputCsvName element:', this.shadowRoot.getElementById('outputCsvName'));
                console.log('Form HTML:', this.shadowRoot.getElementById('ruleForm')?.innerHTML);
            }, 100);
            
            title.textContent = '编辑关联规则';
            form.reset();
            
            // Store the rule createTime for update - 参考模型元数据的timestamp
            form.dataset.ruleId = rule.createTime;
            this.currentAction = 'edit';
            
            // Initialize all dropdown options first
            this.loadDataSourceOptions();
            this.loadTargetModelOptions();
            
            // Wait for dropdowns to be initialized, then populate form data
            setTimeout(() => {
                console.log('回填编辑数据:', rule);
                
                // Populate form with rule data - 使用正确的字段映射
                this.shadowRoot.getElementById('ruleName').value = rule.ruleName || rule.name || '';
                this.shadowRoot.getElementById('ruleName').setAttribute('readonly', 'readonly');
                this.shadowRoot.getElementById('ruleDesc').value = rule.ruleDesc || rule.description || '';
                this.shadowRoot.getElementById('dataSource').value = rule.dataSource || rule.tableName || '';
                this.shadowRoot.getElementById('targetModel').value = rule.targetModel || rule.modelName || '';
                
                // Populate the three new fields with null checks
                const cmdElement = this.shadowRoot.getElementById('cmd');
                if (cmdElement) {
                    cmdElement.value = rule.cmd || '';
                } else {
                    console.warn('cmd element not found in form');
                }
                
                const inputCsvElement = this.shadowRoot.getElementById('inputCsvName');
                if (inputCsvElement) {
                    inputCsvElement.value = rule.inputCsvName || '';
                } else {
                    console.warn('inputCsvName element not found in form');
                }
                
                const outputCsvElement = this.shadowRoot.getElementById('outputCsvName');
                if (outputCsvElement) {
                    outputCsvElement.value = rule.outputCsvName || '';
                } else {
                    console.warn('outputCsvName element not found in form');
                }
                
                // 设置版本 - 需要先加载版本选项
                if (rule.modelName || rule.targetModel) {
                    const modelName = rule.modelName || rule.targetModel;
                    console.log('加载版本选项:', modelName);
                    this.loadModelVersions(modelName);
                    
                    // 等待版本加载完成后设置版本值
                    setTimeout(() => {
                        const versionSelect = this.shadowRoot.getElementById('version');
                        if (rule.version || rule.modelVersion) {
                            versionSelect.value = rule.version || rule.modelVersion;
                            console.log('设置版本值:', rule.version || rule.modelVersion);
                        }
                        
                        // 不在这里调用loadModelFields，等映射关系初始化后再调用
                    }, 100);
                }
                
                // Set status radio button - 参考模型元数据的status处理
                const statusValue = rule.status === 'active' || rule.status === true ? 'active' : 'inactive';
                const statusRadio = this.shadowRoot.querySelector(`input[name="status"][value="${statusValue}"]`);
                if (statusRadio) {
                    statusRadio.checked = true;
                }
                
                // Load data source fields for the selected table
                if (rule.tableName || rule.dataSource) {
                    const tableName = rule.tableName || rule.dataSource;
                    console.log('加载数据源字段:', tableName);
                    this.loadDataSourceFields(tableName);
                }
                
                // Restore form footer buttons
                this.restoreFormFooter();
                
                // Highlight external trees
                document.body.classList.add('association-rules-modal-open');
                
                // 等待字段加载完成后回填映射数据
                setTimeout(() => {
                    // 等待模型数据加载完成后再初始化映射关系
                    const waitForModelDataAndInitMappings = () => {
                        if (this.cachedModelData) {
                            console.log('模型数据已缓存，开始初始化映射关系');
                            
                            // 完全参考model-edit.js的loadInterfaceParamsFromData方法
                            // Initialize mappings with existing data if available - 参考inputs/outputs处理
                            if (rule.mappings && rule.mappings.length > 0) {
                                console.log('加载映射数据:', rule.mappings);
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
                                console.log('加载回写映射数据:', rule.resultMappings);
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
                        } else {
                            console.log('等待模型数据加载完成...');
                            setTimeout(waitForModelDataAndInitMappings, 100);
                        }
                    };
                    
                    // 开始等待模型数据
                    waitForModelDataAndInitMappings();
                }, 300); // 增加等待时间确保版本change事件完成
            }, 200); // 等待下拉选初始化完成
        }
    }

    hideModal() {
        console.log('🚪 hideModal被调用，停止轮询');
        const modal = this.shadowRoot.getElementById('modalMask');
        if (modal) {
            modal.hidden = true;
            modal.style.display = 'none';
            
            // Restore form content if it was replaced by showModal
            this.restoreFormContent();
            this.restoreFormFooter();
            
            // Remove highlight from external trees
            document.body.classList.remove('association-rules-modal-open');
            
            // Clear selections
            document.querySelectorAll('.left-sidebar .tree-node.selected, .right-sidebar .tree-node.selected').forEach(node => {
                node.classList.remove('selected');
            });
            
            this.selectedDataSource = null;
            this.selectedModel = null;
        }
        // 停止日志轮询
        this.stopInModalAutoRefresh();
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
            const result = await window.AppConfig.post('associationRules', 'save', formData);
            console.log('保存响应:', result);
            
            if (result.success) {
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
        const cmd = this.shadowRoot.getElementById('cmd').value.trim();
        const inputCsvName = this.shadowRoot.getElementById('inputCsvName').value.trim();
        const outputCsvName = this.shadowRoot.getElementById('outputCsvName').value.trim();
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
            cmd: cmd,               // 运行命令
            inputCsvName: inputCsvName,   // 输入数据CSV文件名
            outputCsvName: outputCsvName, // 输出结果CSV文件名
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
                    console.log('🔴 模态框关闭按钮被点击');
                    this.hideModal();
                    // 停止日志轮询
                    this.stopInModalAutoRefresh();
                    // Restore previous state
                    modalTitle.textContent = previousState.title;
                    modalBody.innerHTML = previousState.body;
                    modalFooter.innerHTML = previousState.footer;
                } else if (action === 'delete' && id) {
                    this.deleteRuleFromAPI(id);
                    // 删除操作后不需要恢复之前的状态，直接关闭弹窗
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

    /**
     * Initialize mappings list with one empty row
     */
    async initializeMappings() {
        const mappingsList = this.shadowRoot.getElementById('mappingsList');
        if (mappingsList) {
            mappingsList.innerHTML = '';
            this.addMapping();
        }
    }

    /**
     * Initialize result mappings list with one empty row
     */
    async initializeResultMappings() {
        const resultMappingsList = this.shadowRoot.getElementById('resultMappingsList');
        if (resultMappingsList) {
            resultMappingsList.innerHTML = '';
            this.addResultMapping();
        }
    }

    /**
     * Add a mapping row to the mappings list
     */
    async addMapping(mappingData = null) {
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
            <div class="mapping-field conversion-ops">
                <label>单位换算</label>
                <div class="conversion-formula">
                    <select class="conversion-operator">
                        <option value="none">无换算</option>
                        <option value="multiply">乘以</option>
                        <option value="divide">除以</option>
                    </select>
                    <select class="conversion-value" style="display: none;">
                        <option value="">选择数值</option>
                        <option value="1000">1000 (kg→t, m→km)</option>
                        <option value="3600">3600 (h→s)</option>
                        <option value="3.6">3.6 (km/h→m/s)</option>
                        <option value="0.2777777777777778">0.2778 (m/s→km/h)</option>
                        <option value="100">100 (cm→m, %→倍数)</option>
                        <option value="0.01">0.01 (m→cm)</option>
                        <option value="273.15">273.15 (°C→K)</option>
                        <option value="9/5">9/5 (°C→°F系数)</option>
                        <option value="32">32 (°C→°F偏移)</option>
                        <option value="custom">自定义数值</option>
                    </select>
                    <input type="number" class="conversion-custom-value" placeholder="自定义数值" step="any" style="display: none;">
                </div>
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

        // 添加转换类型变更事件处理
        const operatorSelect = conversion.querySelector('.conversion-operator');
        const valueSelect = conversion.querySelector('.conversion-value');
        const customValueInput = conversion.querySelector('.conversion-custom-value');
        
        operatorSelect.addEventListener('change', () => {
            const operator = operatorSelect.value;
            
            if (operator === 'none') {
                valueSelect.style.display = 'none';
                customValueInput.style.display = 'none';
                valueSelect.value = '';
                customValueInput.value = '';
            } else {
                valueSelect.style.display = 'inline-block';
                valueSelect.focus();
            }
        });
        
        valueSelect.addEventListener('change', () => {
            const selectedValue = valueSelect.value;
            
            if (selectedValue === 'custom') {
                customValueInput.style.display = 'inline-block';
                customValueInput.focus();
            } else {
                customValueInput.style.display = 'none';
                customValueInput.value = '';
            }
        });

        // Add field type validation
        const sourceSelect = sourceField.querySelector('.data-field-select');
        const targetSelect = targetField.querySelector('.mapping-target-field');
        
        // Add change event listeners for validation
        sourceSelect.addEventListener('change', () => this.validateMappingType(sourceSelect, targetSelect));
        targetSelect.addEventListener('change', () => this.validateMappingType(sourceSelect, targetSelect));

        // Update field options based on current selections
        this.updateMappingFieldOptionsForNewRow(sourceField, targetField);

        // If mapping data is provided, populate the fields
        if (mappingData) {
            const sourceSelect = sourceField.querySelector('.data-field-select');
            const targetSelect = targetField.querySelector('.mapping-target-field');
            const operatorSelect = conversion.querySelector('.conversion-operator');
            const valueSelect = conversion.querySelector('.conversion-value');
            const customValueInput = conversion.querySelector('.conversion-custom-value');
            
            if (mappingData.sourceField) sourceSelect.value = mappingData.sourceField;
            if (mappingData.targetField) targetSelect.value = mappingData.targetField;
            if (mappingData.operator) operatorSelect.value = mappingData.operator;
            
            // 处理转换值
            if (mappingData.conversionValue) {
                // 检查是否是预设值
                const presetValues = ['1000', '3600', '3.6', '0.2777777777777778', '100', '0.01', '273.15', '9/5', '32'];
                if (presetValues.includes(mappingData.conversionValue)) {
                    valueSelect.value = mappingData.conversionValue;
                    customValueInput.style.display = 'none';
                } else {
                    valueSelect.value = 'custom';
                    customValueInput.value = mappingData.conversionValue;
                    customValueInput.style.display = 'inline-block';
                }
                valueSelect.style.display = 'inline-block';
            }
            
            // 触发operator change事件来显示/隐藏value选择框
            if (mappingData.operator && mappingData.operator !== 'none') {
                valueSelect.style.display = 'inline-block';
            }
        }
    }

    /**
     * Add a result mapping row to the result mappings list
     */
    async addResultMapping(mappingData = null) {
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
            const targetField = row.querySelector('.mapping-target-field')?.value;
            const operator = row.querySelector('.conversion-operator')?.value;
            const valueSelect = row.querySelector('.conversion-value')?.value;
            const customValueInput = row.querySelector('.conversion-custom-value')?.value;
            
            if (sourceField && targetField) {
                // 确定最终的转换值
                let conversionValue = '';
                if (operator !== 'none') {
                    if (valueSelect === 'custom') {
                        conversionValue = customValueInput || '';
                    } else {
                        conversionValue = valueSelect || '';
                    }
                }
                
                mappings.push({ 
                    sourceField, 
                    targetField, 
                    operator: operator || 'none',
                    conversionValue: conversionValue
                });
            }
        });
        
        console.log('收集到的映射数据:', mappings);
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
        
        console.log('收集到的回写映射数据:', resultMappings);
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
        
        console.log('复制规则:', rule);
        
        // 构建复制后的规则数据
        const copiedRule = {
            createTime: new Date().getTime(), // 使用新的时间戳作为ID
            name: (rule.ruleName || rule.name) + ' - 副本',
            description: rule.ruleDesc || rule.description || '',
            tableName: rule.dataSource || rule.tableName || '',
            modelName: rule.targetModel || rule.modelName || '',
            modelVersion: rule.version || rule.modelVersion || '',
            cmd: rule.cmd || '',                           // 运行命令
            inputCsvName: rule.inputCsvName || '',         // 输入数据CSV文件名
            outputCsvName: rule.outputCsvName || '',       // 输出结果CSV文件名
            status: false, // 默认为禁用状态
            inputsBind: rule.mappings ? JSON.stringify(rule.mappings) : '[]',
            outputsBind: rule.resultMappings ? JSON.stringify(rule.resultMappings) : '[]'
        };
        
        console.log('保存复制的规则:', copiedRule);
        
        // 直接调用保存接口
        this.saveCopiedRule(copiedRule);
    }
    
    // 专门用于保存复制规则的方法
    async saveCopiedRule(ruleData) {
        try {
            console.log('保存复制规则:', ruleData);
            
            // 使用新的API配置
            const result = await window.AppConfig.post('associationRules', 'save', ruleData);
            
            if (result.success) {
                this.showToast('规则复制成功');
                // 重新加载规则列表
                await this.loadRulesFromAPI();
                this.renderTable();
            } else {
                this.showToast('规则复制失败: ' + (result.message || '未知错误'), 'error');
            }
        } catch (error) {
            console.error('保存复制规则失败:', error);
            this.showToast('规则复制失败，请稍后重试', 'error');
        }
    }
    
    async showCopyModal(rule) {
        const modal = this.shadowRoot.getElementById('modalMask');
        const title = this.shadowRoot.getElementById('modalTitle');
        const form = this.shadowRoot.getElementById('ruleForm');
        
        if (modal && title && form && rule) {
            // Restore form content if it was replaced by showModal
            this.restoreFormContent();
            
            title.textContent = '新增关联规则';
            form.reset();
            
            // Initialize all dropdown options first
            this.loadDataSourceOptions();
            this.loadTargetModelOptions();
            
            // Wait for dropdowns to be initialized, then populate form data
            setTimeout(() => {
                console.log('回填复制数据:', rule);
                
                // Fill the form with copied rule data - 使用正确的字段映射
                this.shadowRoot.getElementById('ruleName').value = rule.ruleName + ' - 副本';
                this.shadowRoot.getElementById('ruleDesc').value = rule.ruleDesc || rule.description || '';
                this.shadowRoot.getElementById('dataSource').value = rule.dataSource || rule.tableName || '';
                this.shadowRoot.getElementById('targetModel').value = rule.targetModel || rule.modelName || '';
                
                // 设置版本 - 需要先加载版本选项
                if (rule.modelName || rule.targetModel) {
                    const modelName = rule.modelName || rule.targetModel;
                    console.log('复制模式，加载版本选项:', modelName);
                    this.loadModelVersions(modelName);
                    
                    // 等待版本加载完成后设置版本值
                    setTimeout(() => {
                        const versionSelect = this.shadowRoot.getElementById('version');
                        if (rule.version || rule.modelVersion) {
                            versionSelect.value = rule.version || rule.modelVersion;
                            console.log('复制模式，设置版本值:', rule.version || rule.modelVersion);
                        }
                        
                        // 加载模型字段
                        if (versionSelect.value) {
                            console.log('复制模式，加载模型字段:', modelName, versionSelect.value);
                            this.loadModelFields(modelName);
                        }
                    }, 100);
                }
                
                // Set status radio button to active by default for new copy
                this.shadowRoot.querySelector('input[name="status"][value="active"]').checked = true;
                
                // Load data source fields for the selected table
                if (rule.tableName || rule.dataSource) {
                    const tableName = rule.tableName || rule.dataSource;
                    console.log('复制模式，加载数据源字段:', tableName);
                    this.loadDataSourceFields(tableName);
                }
                
                // Clear any rule ID to ensure this creates a new rule
                delete form.dataset.ruleId;
                this.currentAction = 'add';
                
                // Restore form footer buttons
                this.restoreFormFooter();
                
                // Highlight external trees
                document.body.classList.add('association-rules-modal-open');
                
                // 等待字段加载完成后回填映射数据
                setTimeout(() => {
                    // Initialize mappings with copied data if available
                    if (rule.mappings && rule.mappings.length > 0) {
                        console.log('复制映射数据:', rule.mappings);
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
                        console.log('复制回写映射数据:', rule.resultMappings);
                        this.initializeResultMappings();
                        // Clear existing result mappings and add copied ones
                        const resultMappingsList = this.shadowRoot.getElementById('resultMappingsList');
                        resultMappingsList.innerHTML = '';
                        
                        // 逐个添加回写映射，确保每个都有时间加载选项
                        rule.resultMappings.forEach((mapping, index) => {
                            setTimeout(() => {
                                console.log(`添加第${index + 1}个回写映射:`, mapping);
                                this.addResultMapping(mapping);
                            }, index * 300); // 每个映射间隔300ms
                        });
                    } else {
                        this.initializeResultMappings();
                    }
                    
                    // 延迟显示弹窗，确保所有映射都添加完成
                    setTimeout(() => {
                        modal.hidden = false;
                        modal.style.display = 'flex';
                    }, rule.resultMappings ? rule.resultMappings.length * 300 + 200 : 200);
                }, 600); // 增加等待时间确保所有字段加载完成
            }, 200); // 等待下拉选初始化完成
        }
    }
    
    restoreFormContent() {
        console.log('🔧 restoreFormContent called');
        const modalBody = this.shadowRoot.getElementById('modalBody');
        if (!modalBody) {
            console.warn('modalBody not found');
            return;
        }
        
        // Check if form content exists, if not, restore it
        const existingForm = modalBody.querySelector('#ruleForm');
        if (!existingForm) {
            console.log('Form not found, restoring form content');
            // Restore the original form content
            modalBody.innerHTML = `
                <form id="ruleForm" class="rule-form">
                    <div class="form-row">
                        <div class="form-group">
                            <label for="ruleName">规则名称</label>
                            <input type="text" id="ruleName" name="ruleName" required placeholder="请输入规则名称" ${this.currentAction === 'edit' ? 'readonly' : ''}>
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
                                    <label>数据源路径前缀</label>
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
                            <label for="cmd">运行命令</label>
                            <input type="text" id="cmd" name="cmd" placeholder="python3 model_runner.py   --input-file raw_data.csv   --output-file processed_results.csv">
                        </div>
                    </div>
                    
                    <div class="form-row">
                        <div class="form-group">
                            <label for="inputCsvName">输入数据CSV文件名</label>
                            <input type="text" id="inputCsvName" name="inputCsvName" placeholder="raw_data.csv">
                        </div>
                        <div class="form-group">
                            <label for="outputCsvName">输出结果CSV文件名</label>
                            <input type="text" id="outputCsvName" name="outputCsvName" placeholder="processed_results.csv">
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
        this.shadowRoot.getElementById('addMapping')?.addEventListener('click', async () => this.addMapping());
        this.shadowRoot.getElementById('addResultMapping')?.addEventListener('click', async () => this.addResultMapping());
        
        // Data source and target model change events
        this.shadowRoot.getElementById('dataSource')?.addEventListener('change', () => this.updateMappingFieldOptions());
        this.shadowRoot.getElementById('targetModel')?.addEventListener('change', () => {
            this.updateMappingFieldOptions();
            this.updateResultMappingFieldOptions();
        });
        
        // 添加规则名称唯一性校验
        const ruleNameInput = this.shadowRoot.getElementById('ruleName');
        if (ruleNameInput) {
            // 移除旧的事件监听器，避免重复绑定
            const newRuleNameInput = ruleNameInput.cloneNode(true);
            ruleNameInput.parentNode.replaceChild(newRuleNameInput, ruleNameInput);
            
            let lastValidatedName = '';
            const validateRuleName = async () => {
                const ruleName = newRuleNameInput.value.trim();
                // 只有新增时才进行校验，编辑时不校验，且避免重复校验相同名称
                if (ruleName && this.currentAction === 'add' && ruleName !== lastValidatedName) {
                    lastValidatedName = ruleName;
                    try {
                        const result = await window.AppConfig.get('associationRules', 'validate-name', {
                            name: ruleName
                        });
                        
                        if (!result.success) {
                            newRuleNameInput.style.borderColor = '#ff4d4f';
                            this.showToast(result.message || '规则名称已存在，请使用其他名称', 'error');
                        } else {
                            newRuleNameInput.style.borderColor = '#e2e6ef';
                        }
                    } catch (error) {
                        console.error('校验规则名称失败:', error);
                    }
                } else {
                    newRuleNameInput.style.borderColor = '#e2e6ef';
                }
            };
            
            newRuleNameInput.addEventListener('blur', validateRuleName);
        }
        
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
                            <input type="text" id="runName" name="runName" placeholder="请输入运行任务名称">
                        </div>
                        <div class="form-group">
                            <label for="ruleName">规则名称</label>
                            <input type="text" id="ruleName" name="ruleName" readonly value="${rule.ruleName}">
                        </div>
                    </div>
                    
                    <div class="form-row">
                        <div class="form-group">
                            <label for="modelName">模型名称</label>
                            <input type="text" id="modelName" name="modelName" readonly value="${rule.targetModel || 'N/A'}">
                        </div>
                        <div class="form-group">
                            <label for="modelVersion">版本号</label>
                            <input type="text" id="modelVersion" name="modelVersion" readonly value="${rule.version || 'N/A'}">
                        </div>
                    </div>
                    
                    <div class="form-row">
                        <div class="form-group">
                            <label for="startTime">开始时间</label>
                            <input type="datetime-local" id="startTime" name="startTime" required value="${new Date().toISOString().slice(0, 16)}" step="1">
                        </div>
                        <div class="form-group">
                            <label for="endTime">结束时间</label>
                            <input type="datetime-local" id="endTime" name="endTime" required value="${new Date().toISOString().slice(0, 16)}" step="1">
                        </div>
                    </div>
                    
                    <div class="form-row">
                        <div class="form-group">
                            <label for="outputTable">结果回写路径前缀 </label>
                            <input type="text" id="outputTable" name="outputTable" required placeholder="root.result.job01">
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
    
    async executeRule() {
        const runName = this.shadowRoot.getElementById('runName')?.value.trim();
        const startTime = this.shadowRoot.getElementById('startTime')?.value;
        const endTime = this.shadowRoot.getElementById('endTime')?.value;
        const modelName = this.shadowRoot.getElementById('modelName')?.value;
        const modelVersion = this.shadowRoot.getElementById('modelVersion')?.value;
        const outputTable = this.shadowRoot.getElementById('outputTable')?.value.trim();
        
        if (!runName) {
            this.showToast('请输入运行任务名称', 'error');
            return;
        }
        
        if (!startTime || !endTime) {
            this.showToast('请选择开始时间和结束时间', 'error');
            return;
        }
        
        if (!outputTable) {
            this.showToast('请输入结果回写路径前缀', 'error');
            return;
        }
        
        // 结果回写路径前缀不能包含"_system"
        if (outputTable.includes('_system')) {
            this.showToast('结果回写路径前缀不能包含"_system"', 'error');
            return;
        }
        
        if (new Date(startTime) > new Date(endTime)) {
            this.showToast('开始时间不能晚于结束时间', 'error');
            return;
        }
        
        const rule = this.data.find(item => item.id === this.currentRunRuleId);
        if (rule) {
            try {
                // 构建请求参数
                const requestBody = {
                    name: runName, // 使用用户输入的运行任务名称
                    ruleName: rule.ruleName, // 添加规则名称字段
                    modelName: modelName, // 添加模型名称字段
                    modelVersion: modelVersion, // 添加版本号字段
                    startTime: new Date(startTime).getTime(),
                    endTime: new Date(endTime).getTime(),
                    ruleId: rule.createTime, // 使用createTime作为ruleId
                    outputTable: outputTable // 添加结果回写路径前缀
                };
                
                console.log('运行规则参数:', requestBody);
                
                // 先校验唯一性
                console.log('开始校验任务时间段唯一性...');
                const validationResult = await window.AppConfig.post('task', 'validate-uniqueness', requestBody);
                console.log('唯一性校验结果:', validationResult);
                
                if (!validationResult.success || !validationResult.data) {
                    this.showToast(validationResult.message || '任务名称已存在或该规则在同一时间段已存在相同的任务', 'error');
                    return;
                }
                
                // 调用/api/task/run接口
                const result = await window.AppConfig.post('task', 'run', requestBody);
                console.log('运行规则响应:', result);
                
                if (result.success) {
                    this.showToast(`规则运行成功: ${rule.ruleName}`);
                    
                    // 直接在当前弹窗内显示日志内容
                    this.showTaskLogInModal(rule.ruleName, result.data.timestamp);
                } else {
                    this.showToast(result.message || '运行失败', 'error');
                }
            } catch (error) {
                console.error('运行规则失败:', error);
                this.showToast('网络错误，运行失败', 'error');
            }
        }
    }
    
    // 在同一个弹窗内显示任务日志
    async showTaskLogInModal(taskName, timestamp) {
        try {
            console.log('在弹窗内显示任务日志:', { taskName, timestamp });
            
            // 添加样式（如果还没有添加）
            this.addInModalLogStyles();
            
            // 调用后端详情接口获取任务信息（包含日志）
            const result = await window.AppConfig.get('task', 'detail', {
                timestamp: timestamp
            });
            
            console.log('获取任务详情响应:', result);
            
            if (result.success && result.data) {
                // 从任务详情中获取日志信息
                const logContent = result.data.processLog || '暂无日志信息';
                const taskStatus = result.data.status || 'running';
                
                // 在同一个弹窗内显示日志内容
                this.showModal('任务日志', `
                    <div class="log-display">
                        <div class="log-header">
                            <h4>任务: ${taskName}</h4>
                            <span class="status-indicator ${taskStatus}">${this.getStatusText(taskStatus)}</span>
                        </div>
                        <div class="log-content">
                            <pre>${logContent}</pre>
                        </div>
                        <div class="log-controls">
                            <button class="btn btn-refresh" id="inModalRefreshBtn">刷新日志</button>
                            ${taskStatus === 'running' ? `
                                <button class="btn btn-auto-refresh active" id="inModalAutoRefreshBtn">自动刷新: 开启</button>
                            ` : ''}
                        </div>
                    </div>
                `, [
                    { text: '关闭', class: 'modal-btn primary', action: 'close' }
                ]);
                
                // 存储当前任务信息用于刷新
                this.currentLogTask = {
                    name: taskName,
                    timestamp: timestamp,
                    status: taskStatus
                };
                
                // 绑定日志刷新事件
                this.bindInModalLogEvents();
                
                // 如果任务正在运行，自动开启刷新
                if (taskStatus === 'running') {
                    this.startInModalAutoRefresh();
                }
                
            } else {
                this.showToast(result.message || '获取任务详情失败', 'error');
            }
        } catch (error) {
            console.error('获取任务详情失败:', error);
            this.showToast('网络错误，获取任务详情失败', 'error');
        }
    }
    
    // 添加弹窗内日志样式
    addInModalLogStyles() {
        const styleId = 'in-modal-log-styles';
        if (!this.shadowRoot.getElementById(styleId)) {
            const style = document.createElement('style');
            style.id = styleId;
            style.textContent = `
                .success-message {
                    text-align: center;
                    padding: var(--spacing-xl) 0;
                }
                
                .success-icon {
                    font-size: 48px;
                    color: #4CAF50;
                    margin-bottom: var(--spacing-lg);
                }
                
                .success-message h3 {
                    color: var(--text-primary);
                    margin: 0 0 var(--spacing-md) 0;
                    font-size: var(--font-size-lg);
                }
                
                .success-message p {
                    color: var(--text-secondary);
                    margin: 0;
                    font-size: var(--font-size-base);
                }
                
                .log-display {
                    display: flex;
                    flex-direction: column;
                    height: 400px;
                }
                
                .log-display .log-header {
                    display: flex;
                    justify-content: space-between;
                    align-items: center;
                    margin-bottom: var(--spacing-md);
                    padding-bottom: var(--spacing-sm);
                    border-bottom: 1px solid var(--border-primary);
                }
                
                .log-display .log-header h4 {
                    margin: 0;
                    color: var(--text-primary);
                    font-size: var(--font-size-base);
                }
                
                .log-display .status-indicator {
                    padding: 4px 8px;
                    font-size: 12px;
                    font-weight: 500;
                    border-radius: 4px;
                    text-transform: uppercase;
                }
                
                .log-display .status-indicator.running {
                    background-color: #e3f2fd;
                    color: #1976d2;
                    border: 1px solid #bbdefb;
                }
                
                .log-display .status-indicator.success {
                    background-color: #e8f5e8;
                    color: #2e7d32;
                    border: 1px solid #c8e6c9;
                }
                
                .log-display .status-indicator.failed {
                    background-color: #ffebee;
                    color: #c62828;
                    border: 1px solid #ffcdd2;
                }
                
                .log-display .log-content {
                    flex: 1;
                    background-color: var(--bg-secondary);
                    border: 1px solid var(--border-primary);
                    border-radius: var(--radius-sm);
                    padding: var(--spacing-md);
                    overflow-y: auto;
                    margin-bottom: var(--spacing-md);
                }
                
                .log-display .log-content pre {
                    margin: 0;
                    font-family: 'Courier New', monospace;
                    font-size: 12px;
                    line-height: 1.4;
                    color: var(--text-primary);
                    white-space: pre-wrap;
                    word-wrap: break-word;
                }
                
                .log-display .log-controls {
                    display: flex;
                    gap: var(--spacing-sm);
                    justify-content: flex-end;
                }
                
                .log-display .btn {
                    padding: 6px 12px;
                    font-size: 12px;
                    border: 1px solid var(--border-primary);
                    border-radius: var(--radius-sm);
                    background-color: var(--bg-primary);
                    color: var(--text-primary);
                    cursor: pointer;
                    transition: all var(--transition-normal);
                }
                
                .log-display .btn:hover {
                    background-color: var(--bg-hover);
                    border-color: var(--border-secondary);
                }
                
                .log-display .btn-auto-refresh.active {
                    background-color: var(--color-primary);
                    color: white;
                    border-color: var(--color-primary);
                }
            `;
            this.shadowRoot.appendChild(style);
        }
    }
    
    // 绑定弹窗内日志事件
    bindInModalLogEvents() {
        // 刷新按钮
        this.shadowRoot.getElementById('inModalRefreshBtn')?.addEventListener('click', () => {
            this.refreshInModalLog();
        });
        
        // 自动刷新按钮
        this.shadowRoot.getElementById('inModalAutoRefreshBtn')?.addEventListener('click', () => {
            this.toggleInModalAutoRefresh();
        });
    }
    
    // 刷新弹窗内日志
    async refreshInModalLog() {
        if (!this.currentLogTask) return;
        
        try {
            const result = await window.AppConfig.get('task', 'detail', {
                timestamp: this.currentLogTask.timestamp
            });
            
            if (result.success && result.data) {
                const logContent = result.data.processLog || '暂无日志信息';
                const logElement = this.shadowRoot.querySelector('.log-content pre');
                if (logElement) {
                    logElement.textContent = logContent;
                    // 滚动到底部
                    logElement.scrollTop = logElement.scrollHeight;
                }
                
                // 更新状态显示
                const statusElement = this.shadowRoot.querySelector('.status-indicator');
                if (statusElement) {
                    const newStatus = result.data.status;
                    statusElement.className = `status-indicator ${newStatus}`;
                    statusElement.textContent = this.getStatusText(newStatus);
                    
                    // 检查任务状态变化
                    if (this.currentLogTask.status === 'running' && newStatus !== 'running') {
                        this.stopInModalAutoRefresh();
                        this.showToast(`任务${this.getStatusText(newStatus)}`, newStatus === 'success' ? 'success' : 'warning');
                    }
                    
                    this.currentLogTask.status = newStatus;
                }
            }
        } catch (error) {
            console.error('刷新日志失败:', error);
        }
    }
    
    // 开始弹窗内自动刷新
    startInModalAutoRefresh() {
        if (this.inModalRefreshInterval) return;
        
        this.inModalRefreshInterval = setInterval(() => {
            this.refreshInModalLog();
        }, 2000); // 每2秒刷新一次
    }
    
    // 停止弹窗内自动刷新
    stopInModalAutoRefresh() {
        if (this.inModalRefreshInterval) {
            clearInterval(this.inModalRefreshInterval);
            this.inModalRefreshInterval = null;
        }
    }
    
    // 切换弹窗内自动刷新
    toggleInModalAutoRefresh() {
        const btn = this.shadowRoot.getElementById('inModalAutoRefreshBtn');
        if (!btn) return;
        
        if (this.inModalRefreshInterval) {
            this.stopInModalAutoRefresh();
            btn.textContent = '自动刷新: 关闭';
            btn.classList.remove('active');
        } else {
            this.startInModalAutoRefresh();
            btn.textContent = '自动刷新: 开启';
            btn.classList.add('active');
        }
    }
    
    // 显示任务日志
    async showTaskLog(taskName, timestamp) {
        try {
            console.log('显示任务日志:', { taskName, timestamp });
            
            // 调用后端详情接口获取任务信息（包含日志）
            const result = await window.AppConfig.get('task', 'detail', {
                timestamp: timestamp
            });
            
            console.log('获取任务详情响应:', result);
            
            if (result.success && result.data) {
                // 从任务详情中获取日志信息
                const logContent = result.data.processLog || '暂无日志信息';
                
                // 显示日志弹窗
                this.showLogModal(taskName, logContent, {
                    timestamp: timestamp,
                    status: result.data.status || 'running'
                });
            } else {
                this.showToast(result.message || '获取任务详情失败', 'error');
            }
        } catch (error) {
            console.error('获取任务详情失败:', error);
            this.showToast('网络错误，获取任务详情失败', 'error');
        }
    }
    
    // 显示日志弹窗（复用visual-analysis的逻辑）
    showLogModal(taskName, logContent, record) {
        console.log('显示日志弹窗，参数:', { taskName, logContentLength: logContent?.length, record });
        
        // 检查是否有弹窗元素，如果没有则创建
        let modal = this.shadowRoot.getElementById('logModalMask');
        if (!modal) {
            // 创建弹窗HTML结构
            const modalHTML = `
                <div class="log-modal-mask" id="logModalMask" hidden>
                    <div class="log-modal-container">
                        <div class="log-modal-header">
                            <h3 class="log-modal-title" id="logModalTitle">标题</h3>
                            <button class="log-modal-close" id="logModalClose">×</button>
                        </div>
                        <div class="log-modal-body" id="logModalBody">
                            <!-- 动态内容 -->
                        </div>
                        <div class="log-modal-footer" id="logModalFooter">
                            <!-- 动态按钮 -->
                        </div>
                    </div>
                </div>
            `;
            
            // 添加到shadow DOM
            const container = document.createElement('div');
            container.innerHTML = modalHTML;
            this.shadowRoot.appendChild(container.firstElementChild);
            
            // 添加样式
            this.addLogModalStyles();
        }
        
        modal = this.shadowRoot.getElementById('logModalMask');
        const title = this.shadowRoot.getElementById('logModalTitle');
        const modalBody = this.shadowRoot.getElementById('logModalBody');
        const modalFooter = this.shadowRoot.getElementById('logModalFooter');
        
        console.log('弹窗元素检查:', { modal: !!modal, title: !!title, modalBody: !!modalBody, modalFooter: !!modalFooter });
        
        if (modal && title && modalBody && modalFooter) {
            title.textContent = `任务日志 - ${taskName}`;
            
            // 根据任务状态决定是否显示自动刷新控制
            const isRunning = record.status === 'running';
            
            // 创建日志显示区域
            modalBody.innerHTML = `
                <div class="log-container">
                    <div class="log-header">
                        <h3>实时日志</h3>
                        <div class="log-controls">
                            <button class="btn btn-refresh" id="logRefreshBtn">刷新</button>
                            ${isRunning ? `
                                <button class="btn btn-auto-refresh active" id="logAutoRefreshBtn">自动刷新: 开启</button>
                                <span class="status-indicator running">任务运行中</span>
                            ` : `
                                <span class="status-indicator ${record.status}">任务已结束</span>
                            `}
                        </div>
                    </div>
                    <div class="log-content" id="logContent">
                        <pre>${logContent}</pre>
                    </div>
                </div>
            `;
            
            // 设置弹窗按钮
            modalFooter.innerHTML = `
                <button type="button" class="btn btn-cancel" id="logCloseBtn">关闭</button>
            `;
            
            // 存储当前任务信息用于刷新
            this.currentLogTask = {
                name: taskName,
                timestamp: record.timestamp,
                status: record.status
            };
            
            console.log('设置currentLogTask:', this.currentLogTask);
            
            // 绑定事件
            this.bindLogModalEvents();
            
            // 如果任务正在运行，自动开启自动刷新
            if (isRunning) {
                this.startLogAutoRefresh();
            }
            
            // 显示弹窗
            modal.hidden = false;
            modal.style.display = 'flex';
            
            console.log('日志弹窗显示完成');
        } else {
            console.error('弹窗元素缺失');
            this.showToast('弹窗元素缺失，无法显示日志', 'error');
        }
    }
    
    // 添加日志弹窗样式
    addLogModalStyles() {
        const styleId = 'log-modal-styles';
        if (!this.shadowRoot.getElementById(styleId)) {
            const style = document.createElement('style');
            style.id = styleId;
            style.textContent = `
                .log-modal-mask {
                    position: fixed;
                    top: 0;
                    left: 0;
                    width: 100%;
                    height: 100%;
                    background-color: rgba(0, 0, 0, 0.5);
                    display: none;
                    justify-content: center;
                    align-items: center;
                    z-index: 1000;
                    animation: fadeIn 0.3s ease;
                }
                
                .log-modal-container {
                    background-color: var(--bg-primary);
                    border-radius: var(--radius-lg);
                    box-shadow: var(--shadow-lg);
                    max-width: 80%;
                    max-height: 80%;
                    width: 800px;
                    min-height: 400px;
                    display: flex;
                    flex-direction: column;
                    animation: slideIn 0.3s ease;
                }
                
                .log-modal-header {
                    display: flex;
                    justify-content: space-between;
                    align-items: center;
                    padding: var(--spacing-xl) var(--spacing-2xl);
                    border-bottom: 1px solid var(--border-primary);
                    background-color: var(--bg-secondary);
                    border-radius: var(--radius-lg) var(--radius-lg) 0 0;
                }
                
                .log-modal-title {
                    margin: 0;
                    font-size: var(--font-size-lg);
                    font-weight: 600;
                    color: var(--text-primary);
                }
                
                .log-modal-close {
                    background: none;
                    border: none;
                    font-size: 24px;
                    color: var(--text-tertiary);
                    cursor: pointer;
                    padding: 0;
                    width: 32px;
                    height: 32px;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    border-radius: var(--radius-sm);
                    transition: all var(--transition-normal);
                }
                
                .log-modal-close:hover {
                    background-color: var(--bg-hover);
                    color: var(--text-primary);
                }
                
                .log-modal-body {
                    flex: 1;
                    padding: var(--spacing-xl) var(--spacing-2xl);
                    overflow-y: auto;
                }
                
                .log-modal-footer {
                    padding: var(--spacing-lg) var(--spacing-2xl);
                    border-top: 1px solid var(--border-primary);
                    background-color: var(--bg-secondary);
                    border-radius: 0 0 var(--radius-lg) var(--radius-lg);
                    display: flex;
                    justify-content: flex-end;
                    gap: var(--spacing-md);
                }
                
                .log-container {
                    display: flex;
                    flex-direction: column;
                    height: 100%;
                    min-height: 300px;
                }
                
                .log-header {
                    display: flex;
                    justify-content: space-between;
                    align-items: center;
                    margin-bottom: var(--spacing-lg);
                    padding-bottom: var(--spacing-md);
                    border-bottom: 1px solid var(--border-primary);
                }
                
                .log-header h3 {
                    margin: 0;
                    font-size: var(--font-size-lg);
                    color: var(--text-primary);
                }
                
                .log-controls {
                    display: flex;
                    gap: var(--spacing-sm);
                }
                
                .log-content {
                    flex: 1;
                    background-color: var(--bg-secondary);
                    border: 1px solid var(--border-primary);
                    border-radius: var(--radius-md);
                    padding: var(--spacing-md);
                    overflow-y: auto;
                    max-height: 400px;
                }
                
                .log-content pre {
                    margin: 0;
                    font-family: 'Courier New', monospace;
                    font-size: var(--font-size-sm);
                    line-height: 1.4;
                    color: var(--text-primary);
                    white-space: pre-wrap;
                    word-wrap: break-word;
                }
                
                .btn-refresh, .btn-auto-refresh {
                    padding: var(--spacing-xs) var(--spacing-sm);
                    font-size: var(--font-size-sm);
                    border: 1px solid var(--border-primary);
                    border-radius: var(--radius-sm);
                    background-color: var(--bg-primary);
                    color: var(--text-primary);
                    cursor: pointer;
                    transition: all var(--transition-normal);
                }
                
                .btn-refresh:hover, .btn-auto-refresh:hover {
                    background-color: var(--bg-hover);
                    border-color: var(--border-secondary);
                }
                
                .btn-auto-refresh.active {
                    background-color: var(--color-primary);
                    color: white;
                    border-color: var(--color-primary);
                }
                
                .status-indicator {
                    padding: var(--spacing-xs) var(--spacing-sm);
                    font-size: var(--font-size-xs);
                    font-weight: 500;
                    border-radius: var(--radius-sm);
                    margin-left: var(--spacing-sm);
                    text-transform: uppercase;
                    letter-spacing: 0.5px;
                }
                
                .status-indicator.running {
                    background-color: #e3f2fd;
                    color: #1976d2;
                    border: 1px solid #bbdefb;
                    animation: pulse 2s infinite;
                }
                
                .status-indicator.success {
                    background-color: #e8f5e8;
                    color: #2e7d32;
                    border: 1px solid #c8e6c9;
                }
                
                .status-indicator.failed {
                    background-color: #ffebee;
                    color: #c62828;
                    border: 1px solid #ffcdd2;
                }
                
                @keyframes pulse {
                    0% { opacity: 1; }
                    50% { opacity: 0.7; }
                    100% { opacity: 1; }
                }
                
                @keyframes fadeIn {
                    from { opacity: 0; }
                    to { opacity: 1; }
                }
                
                @keyframes slideIn {
                    from { 
                        opacity: 0; 
                        transform: translateY(-10px); 
                    }
                    to { 
                        opacity: 1; 
                        transform: translateY(0); 
                    }
                }
            `;
            this.shadowRoot.appendChild(style);
        }
    }
    
    // 绑定日志弹窗事件
    bindLogModalEvents() {
        // 关闭按钮
        this.shadowRoot.getElementById('logCloseBtn')?.addEventListener('click', () => {
            console.log('🔴 点击关闭按钮');
            this.hideLogModal();
            this.stopLogAutoRefresh();
        });
        
        // 弹窗右上角关闭按钮
        this.shadowRoot.getElementById('logModalClose')?.addEventListener('click', () => {
            console.log('🔴 点击右上角关闭按钮');
            this.hideLogModal();
            this.stopLogAutoRefresh();
        });
        
        // 移除点击遮罩关闭功能，避免误操作
        // this.shadowRoot.getElementById('logModalMask')?.addEventListener('click', (e) => {
        //     if (e.target.id === 'logModalMask') {
        //         console.log('🔴 点击遮罩层关闭');
        //         this.hideLogModal();
        //         this.stopLogAutoRefresh();
        //     }
        // });
        
        // 刷新按钮
        this.shadowRoot.getElementById('logRefreshBtn')?.addEventListener('click', () => {
            this.refreshLog();
        });
        
        // 自动刷新按钮
        this.shadowRoot.getElementById('logAutoRefreshBtn')?.addEventListener('click', () => {
            this.toggleLogAutoRefresh();
        });
    }
    
    // 隐藏日志弹窗
    hideLogModal() {
        console.log('🚪 隐藏日志弹窗被调用');
        const modal = this.shadowRoot.getElementById('logModalMask');
        if (modal) {
            modal.hidden = true;
            modal.style.display = 'none';
            console.log('👁️ 弹窗已隐藏');
        }
        // 清理状态
        this.currentLogTask = null;
        this.stopLogAutoRefresh();
    }
    
    // 刷新日志
    async refreshLog() {
        if (!this.currentLogTask) return;
        
        try {
            // 调用详情接口获取最新任务信息（包含日志）
            const result = await window.AppConfig.get('task', 'detail', {
                timestamp: this.currentLogTask.timestamp
            });
            
            if (result.success && result.data) {
                // 从任务详情中获取日志信息
                const logContent = this.shadowRoot.getElementById('logContent');
                if (logContent) {
                    const content = result.data.processLog || '暂无日志信息';
                    logContent.innerHTML = `<pre>${content}</pre>`;
                    // 滚动到底部
                    logContent.scrollTop = logContent.scrollHeight;
                }
                
                // 检查任务状态是否变化，如果任务结束则停止自动刷新
                if (this.logRefreshInterval) {
                    await this.checkTaskStatus();
                }
            }
        } catch (error) {
            console.error('刷新日志失败:', error);
        }
    }
    
    // 检查任务状态
    async checkTaskStatus() {
        if (!this.currentLogTask) return;
        
        try {
            // 获取最新的任务信息 - 使用GET方法
            const result = await window.AppConfig.get('task', 'detail', {
                timestamp: this.currentLogTask.timestamp
            });
            
            if (result.success && result.data) {
                const newStatus = result.data.status;
                const oldStatus = this.currentLogTask.status;
                
                // 如果状态从运行中变为其他状态，停止自动刷新
                if (oldStatus === 'running' && newStatus !== 'running') {
                    console.log(`任务状态从 ${oldStatus} 变为 ${newStatus}，停止自动刷新`);
                    this.stopLogAutoRefresh();
                    
                    // 更新状态显示
                    this.updateStatusDisplay(newStatus);
                    
                    // 显示完成提示
                    const statusText = this.getStatusText(newStatus);
                    this.showToast(`任务${statusText}`, newStatus === 'success' ? 'success' : 'warning');
                }
                
                // 更新当前任务状态
                this.currentLogTask.status = newStatus;
            }
        } catch (error) {
            console.error('检查任务状态失败:', error);
        }
    }
    
    // 更新状态显示
    updateStatusDisplay(status) {
        const statusIndicator = this.shadowRoot.querySelector('.status-indicator');
        const autoRefreshBtn = this.shadowRoot.getElementById('logAutoRefreshBtn');
        
        if (statusIndicator) {
            statusIndicator.className = `status-indicator ${status}`;
            statusIndicator.textContent = status === 'running' ? '任务运行中' : `任务已结束`;
        }
        
        if (autoRefreshBtn && status !== 'running') {
            autoRefreshBtn.classList.remove('active');
            autoRefreshBtn.textContent = '自动刷新: 关闭';
        }
    }
    
    // 获取状态文本
    getStatusText(status) {
        const statusMap = {
            'running': '运行中',
            'stopped': '已停止',
            'pending': '等待中',
            'success': '成功',
            'failed': '失败'
        };
        return statusMap[status] || status;
    }
    
    // 开始自动刷新
    startLogAutoRefresh() {
        console.log('🚀 开始自动刷新被调用，当前interval:', this.logRefreshInterval);
        if (this.logRefreshInterval) {
            console.log('⚠️ 自动刷新已在运行，跳过启动');
            return;
        }
        
        this.logRefreshInterval = setInterval(() => {
            console.log('🔄 执行自动刷新');
            this.refreshLog();
        }, 5000); // 每5秒刷新一次
        console.log('✅ 自动刷新已启动，interval ID:', this.logRefreshInterval);
    }
    
    // 停止自动刷新
    stopLogAutoRefresh() {
        console.log('🛑 停止自动刷新被调用，当前interval:', this.logRefreshInterval);
        if (this.logRefreshInterval) {
            clearInterval(this.logRefreshInterval);
            this.logRefreshInterval = null;
            console.log('✅ 自动刷新已停止');
        } else {
            console.log('⚠️ 没有运行中的自动刷新');
        }
    }
    
    // 切换自动刷新
    toggleLogAutoRefresh() {
        const btn = this.shadowRoot.getElementById('logAutoRefreshBtn');
        if (!btn) return;
        
        if (this.logRefreshInterval) {
            this.stopLogAutoRefresh();
            btn.textContent = '自动刷新: 关闭';
            btn.classList.remove('active');
        } else {
            this.startLogAutoRefresh();
            btn.textContent = '自动刷新: 开启';
            btn.classList.add('active');
        }
    }
    
    toggleRuleStatus(id) {
        const rule = this.data.find(item => item.id === id);
        if (!rule) return;
        
        console.log('当前规则状态:', rule.status, rule.status === 'active');
        console.log('当前规则数据:', rule);
        
        // 修正状态切换逻辑 - 处理字符串和boolean两种情况
        let currentStatus = rule.status;
        let newStatus;
        
        if (typeof currentStatus === 'string') {
            newStatus = currentStatus === 'active' ? false : true;
        } else {
            newStatus = currentStatus ? false : true;
        }
        
        console.log('状态切换:', currentStatus, '->', newStatus);
        
        // 构建只包含状态更新的表单数据 - 使用正确的字段名
        const formData = {
            createTime: rule.createTime, // 使用createTime作为唯一标识
            status: newStatus, // 切换状态
            // 其他字段保持不变，使用正确的字段映射
            name: rule.ruleName,
            description: rule.ruleDesc,
            tableName: rule.dataSource,
            modelName: rule.targetModel,
            modelVersion: rule.version,
            inputsBind: rule.mappings ? JSON.stringify(rule.mappings) : '[]', // 使用mappings字段
            outputsBind: rule.resultMappings ? JSON.stringify(rule.resultMappings) : '[]' // 使用resultMappings字段
        };
        
        console.log('切换规则状态:', formData);
        
        // 直接调用保存接口
        this.saveRuleStatus(formData);
    }
    
    // 专门用于保存状态的方法
    async saveRuleStatus(formData) {
        try {
            console.log('保存规则状态:', formData);
            
            // 使用新的API配置
            const result = await window.AppConfig.post('associationRules', 'save', formData);
            
            if (result.success) {
                // 更新本地数据
                const rule = this.data.find(item => item.createTime === formData.createTime);
                if (rule) {
                    rule.status = formData.status ? 'active' : 'inactive'; // 转换为字符串格式
                    rule.updateTime = new Date().toLocaleString('zh-CN');
                    console.log('更新本地规则状态:', rule.status);
                }
                
                // 重新渲染表格（这会刷新按钮和状态）
                this.renderTable();
                
                // 显示成功消息
                const statusText = formData.status ? '启用' : '禁用';
                this.showToast(`规则 "${formData.name}" 已${statusText}`);
                
                // 通知其他组件刷新
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
                this.showToast(result.message || '状态更新失败', 'error');
            }
        } catch (error) {
            console.error('保存规则状态失败:', error);
            this.showToast('状态更新失败，请稍后重试', 'error');
        }
    }
    
    // 更新数据源选项，不绑定事件监听器
    updateDataSourceOptions() {
        const dataSourceSelect = this.shadowRoot.getElementById('dataSource');
        if (!dataSourceSelect) return;
        
        console.log('更新数据源选项（不绑定事件）');
        
        // 获取当前选中的值
        const currentValue = dataSourceSelect.value;
        
        // 清空现有选项
        dataSourceSelect.innerHTML = '<option value="">请选择数据源</option>';
        
        // 从左侧树中获取所有表名
        const leftSidebarTree = document.querySelector('.left-sidebar .tree');
        if (!leftSidebarTree) {
            console.warn('未找到左侧关系查询树');
            return;
        }
        
        const allNodes = leftSidebarTree.querySelectorAll('.tree-node');
        const tableNames = new Set(); // 使用Set避免重复
        
        allNodes.forEach(node => {
            const span = node.querySelector('span');
            if (span) {
                const nodeName = span.textContent.trim();
                
                // 排除明显的路径节点
                if (nodeName === 'relational_system') {
                    return;
                }
                
                // 只添加叶子节点（没有子节点的节点）
                const hasChildren = node.querySelector('.tree-children');
                if (!hasChildren) {
                    tableNames.add(nodeName);
                }
            }
        });
        
        console.log('获取到的数据源表名:', Array.from(tableNames));
        
        // 添加表名选项
        Array.from(tableNames).forEach(name => {
            const option = document.createElement('option');
            option.value = name;
            option.textContent = name;
            dataSourceSelect.appendChild(option);
        });
        
        // 恢复之前的选择
        if (currentValue && tableNames.has(currentValue)) {
            dataSourceSelect.value = currentValue;
        }
    }
    
    // 更新目标模型选项，不绑定事件监听器
    updateTargetModelOptions() {
        const targetModelSelect = this.shadowRoot.getElementById('targetModel');
        if (!targetModelSelect) return;
        
        console.log('更新目标模型选项（不绑定事件）');
        
        // 获取当前选中的值
        const currentValue = targetModelSelect.value;
        
        // 清空现有选项
        targetModelSelect.innerHTML = '<option value="">请选择目标模型</option>';
        
        // 从右侧树中获取所有模型名称
        const rightSidebarTree = document.querySelector('.right-sidebar .tree');
        if (!rightSidebarTree) {
            console.warn('右侧树不存在');
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
        
        // 添加模型名称选项
        Array.from(modelNames).forEach(name => {
            const option = document.createElement('option');
            option.value = name;
            option.textContent = name;
            targetModelSelect.appendChild(option);
        });
        
        // 恢复之前的选择
        if (currentValue && modelNames.has(currentValue)) {
            targetModelSelect.value = currentValue;
        }
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
                        // 只添加有字段子节点的表名（即最后一级表名）
                        tableNames.add(tablePath);
                    }
                }
                // 移除之前的逻辑，不再添加中间路径的节点
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
        if (!this.dataSourceEventBound) {
            dataSourceSelect.addEventListener('change', () => {
                this.loadDataSourceFields(dataSourceSelect.value);
            });
            
            // 标记事件已绑定
            this.dataSourceEventBound = true;
            console.log('数据源事件监听器已绑定');
        } else {
            console.log('数据源事件监听器已存在，跳过绑定');
        }
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
        
        // 只有当路径中包含relational_system时才确保包含根路径
        // 对于test.input、test.output等路径，不要强制添加relational_system前缀
        if (!foundRoot && parts.length > 0 && parts.some(part => part.includes('relational') || part.includes('association') || part.includes('models') || part.includes('users') || part.includes('roles') || part.includes('parsing'))) {
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
        const fields = new Map(); // 使用Map来存储字段名和类型
        
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
                            // 获取dataType属性（数值代码）
                            const dataTypeCode = node.getAttribute('data-type') || node.dataset.type || '1';
                            fields.set(nodeName, dataTypeCode);
                        }
                    }
                }
            }
        });
        
        console.log('获取到的字段和类型代码:', Array.from(fields.entries()));
        
        // 存储字段类型信息供验证使用
        this.dataSourceFieldTypes = fields;
        
        // 更新所有映射行中的数据源字段选项
        const mappingRows = this.shadowRoot.querySelectorAll('.mapping-row');
        mappingRows.forEach(row => {
            const sourceSelect = row.querySelector('.data-field-select');
            if (sourceSelect) {
                const currentValue = sourceSelect.value;
                sourceSelect.innerHTML = '<option value="">请选择字段</option>';
                
                // 添加字段选项，包含转换后的类型信息
                fields.forEach((typeCode, fieldName) => {
                    const readableType = this.convertDataTypeCode(typeCode);
                    const option = document.createElement('option');
                    option.value = fieldName;
                    option.textContent = `${fieldName} (${readableType})`;
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
        if (!this.targetModelEventBound) {
            targetModelSelect.addEventListener('change', () => {
                console.log('目标模型变化，加载版本');
                this.loadModelVersions(targetModelSelect.value);
                // 不在这里加载字段，等版本选择后再加载
            });
            
            // 标记事件已绑定
            this.targetModelEventBound = true;
            console.log('目标模型事件监听器已绑定');
        } else {
            console.log('目标模型事件监听器已存在，跳过绑定');
        }
        
        // 监听版本变化，加载模型字段 - 使用更可靠的方式
        const versionSelect = this.shadowRoot.getElementById('version');
        if (versionSelect) {
            // 只在第一次初始化时绑定事件监听器
            if (!this.versionEventBound) {
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
                
                // 添加监听器
                versionSelect.addEventListener('change', handleVersionChange);
                versionSelect.addEventListener('blur', handleVersionChange);
                
                // 标记事件已绑定
                this.versionEventBound = true;
                console.log('版本事件监听器已绑定');
            } else {
                console.log('版本事件监听器已存在，跳过绑定');
            }
        }
        
        // 如果是编辑模式且有选中的模型，自动加载版本
        if (this.currentAction === 'edit' && targetModelSelect.value) {
            console.log('编辑模式，自动加载版本:', targetModelSelect.value);
            this.loadModelVersions(targetModelSelect.value);
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
            console.log('手动触发版本change事件，当前模式:', this.currentAction);
            const changeEvent = new Event('change', { bubbles: true });
            versionSelect.dispatchEvent(changeEvent);
        }
    }
    
    // 动态加载模型字段 - 参考model-detail.js的inputs/outputs解析
    async loadModelFields(modelName) {
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
        try {
            const result = await window.AppConfig.get('model', 'metas', { name: modelName, version: selectedVersion });
            
            if (result.success && result.data) {
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
                
                // 缓存模型数据供后续使用
                this.cachedModelData = modelData;
                console.log('loadModelFields缓存模型数据:', modelData);
                
                // 更新映射字段的下拉选项
                this.updateMappingFieldOptions(inputs, outputs);
            }
        } catch (error) {
            console.error('获取模型详情失败:', error);
        }
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
    async updateMappingFieldOptionsForNewRow(sourceField, targetField) {
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
                    const fields = new Map(); // 使用Map来存储字段名和类型
                    
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
                                        // 获取dataType属性（数值代码）
                                        const dataTypeCode = node.getAttribute('data-type') || node.dataset.type || '5';
                                        fields.set(nodeName, dataTypeCode);
                                    }
                                }
                            }
                        }
                    });
                    
                    // 添加字段选项，包含转换后的类型信息
                    fields.forEach((typeCode, fieldName) => {
                        const readableType = this.convertDataTypeCode(typeCode);
                        const option = document.createElement('option');
                        option.value = fieldName;
                        option.textContent = `${fieldName} (${readableType})`;
                        sourceSelect.appendChild(option);
                    });
                    
                    // 存储字段类型信息供验证使用
                    this.dataSourceFieldTypes = fields;
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
                
                // 如果已有缓存的模型数据，直接使用
                if (this.cachedModelData) {
                    console.log('使用缓存数据更新模型参数选项');
                    let inputs = [];
                    if (this.cachedModelData.inputs) {
                        inputs = typeof this.cachedModelData.inputs === 'string' ? JSON.parse(this.cachedModelData.inputs) : this.cachedModelData.inputs;
                    }
                    
                    // 添加模型参数选项
                    inputs.forEach(input => {
                        const option = document.createElement('option');
                        option.value = input.name || input;
                        option.textContent = `${input.name || input} (${input.type || 'string'})`;
                        targetSelect.appendChild(option);
                    });
                } else {
                    console.log('缓存数据不存在，调用API获取模型参数');
                    // 调用API获取模型参数
                    try {
                        const result = await window.AppConfig.get('model', 'metas', { name: targetModel, version: version });
                        
                        if (result.success && result.data) {
                            const modelData = result.data;
                            // 缓存模型数据供后续使用
                            this.cachedModelData = modelData;
                            console.log('获取并缓存模型数据:', modelData);
                            
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
                    } catch (error) {
                        console.error('获取模型参数失败:', error);
                    }
                }
            }
        }
    }

    // 为新添加的回写映射行更新字段选项
    async updateResultMappingFieldOptionsForNewRow(modelField) {
        // 更新模型输出选项
        const targetModel = this.shadowRoot.getElementById('targetModel')?.value;
        const version = this.shadowRoot.getElementById('version')?.value;
        if (targetModel && version) {
            const modelSelect = modelField.querySelector('.result-mapping-source-field');
            if (modelSelect) {
                modelSelect.innerHTML = '<option value="">请选择输出</option>';
                
                // 如果已有缓存的模型数据，直接使用
                if (this.cachedModelData) {
                    console.log('使用缓存数据更新模型输出选项');
                    let outputs = [];
                    if (this.cachedModelData.outputs) {
                        outputs = typeof this.cachedModelData.outputs === 'string' ? JSON.parse(this.cachedModelData.outputs) : this.cachedModelData.outputs;
                    }
                    
                    // 添加模型输出选项
                    outputs.forEach(output => {
                        const option = document.createElement('option');
                        option.value = output.name || output;
                        option.textContent = `${output.name || output} (${output.type || 'string'})`;
                        modelSelect.appendChild(option);
                    });
                } else {
                    console.log('缓存数据不存在，调用API获取模型输出');
                    // 调用API获取模型输出
                    try {
                        const result = await window.AppConfig.get('model', 'metas', { name: targetModel, version: version });
                        
                        if (result.success && result.data) {
                            const modelData = result.data;
                            // 缓存模型数据供后续使用
                            if (!this.cachedModelData) {
                                this.cachedModelData = modelData;
                            }
                            console.log('获取并缓存模型数据:', modelData);
                            
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
                    } catch (error) {
                        console.error('获取模型输出失败:', error);
                    }
                }
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
            // 监听分页变化事件（如果有自定义分页组件）
            pagination.addEventListener('pagination-change', (event) => {
                const { currentPage, pageSize } = event.detail;
                this.currentPage = currentPage;
                this.pageSize = pageSize;
                this.loadRulesFromAPI(); // 重新调用API获取数据
            });
            
            // 为HTML分页按钮绑定事件
            const prevBtn = this.shadowRoot.getElementById('prevPage');
            const nextBtn = this.shadowRoot.getElementById('nextPage');
            const pageSizeSelect = this.shadowRoot.getElementById('pageSizeSelect');
            
            if (prevBtn) {
                prevBtn.onclick = () => {
                    if (this.currentPage > 1) {
                        this.currentPage--;
                        this.loadRulesFromAPI(); // 重新调用API获取数据
                    }
                };
            }
            
            if (nextBtn) {
                nextBtn.onclick = () => {
                    const totalPages = Math.ceil(this.totalCount / this.pageSize);
                    if (this.currentPage < totalPages) {
                        this.currentPage++;
                        this.loadRulesFromAPI(); // 重新调用API获取数据
                    }
                };
            }
            
            // 绑定页面大小选择器事件
            if (pageSizeSelect) {
                pageSizeSelect.value = this.pageSize.toString();
                pageSizeSelect.onchange = () => {
                    this.pageSize = parseInt(pageSizeSelect.value);
                    this.currentPage = 1; // 重置到第一页
                    this.loadRulesFromAPI(); // 重新调用API获取数据
                };
            }
            
            // 初始化分页
            this.updatePagination();
        }
    }

    updatePagination() {
        const pagination = this.shadowRoot.getElementById('pagination');
        if (pagination) {
            // 如果有自定义分页组件，使用它
            if (pagination.setPagination) {
                pagination.setPagination(this.currentPage, this.pageSize, this.totalCount);
            }
            
            // 更新HTML分页按钮状态
            const prevBtn = this.shadowRoot.getElementById('prevPage');
            const nextBtn = this.shadowRoot.getElementById('nextPage');
            const pageList = this.shadowRoot.getElementById('pageList');
            const totalCountSpan = this.shadowRoot.getElementById('totalCount');
            const pageSizeSelect = this.shadowRoot.getElementById('pageSizeSelect');
            
            if (prevBtn && nextBtn && pageList && totalCountSpan && pageSizeSelect) {
                const totalPages = Math.ceil(this.totalCount / this.pageSize);
                
                // 更新按钮状态
                prevBtn.disabled = this.currentPage === 1;
                nextBtn.disabled = this.currentPage === totalPages;
                
                // 更新页码列表
                pageList.innerHTML = '';
                for (let i = 1; i <= totalPages; i++) {
                    const pageBtn = document.createElement('button');
                    pageBtn.className = `page-number ${i === this.currentPage ? 'active' : ''}`;
                    pageBtn.textContent = i;
                    pageBtn.onclick = () => this.goToPage(i);
                    pageList.appendChild(pageBtn);
                }
                
                // 更新总数显示
                totalCountSpan.textContent = this.totalCount.toString();
                
                // 更新页面大小选择器
                pageSizeSelect.value = this.pageSize.toString();
            }
        }
    }
    
    // 跳转到指定页面
    goToPage(page) {
        this.currentPage = page;
        this.loadRulesFromAPI(); // 重新调用API获取数据
    }

    // 验证映射字段的数据类型匹配
    validateMappingType(sourceSelect, targetSelect) {
        const sourceValue = sourceSelect.value;
        const targetValue = targetSelect.value;
        
        // 如果两个字段都已选择，则进行类型验证
        if (sourceValue && targetValue) {
            const sourceType = this.getDataSourceFieldType(sourceValue);
            const targetType = this.getTargetModelFieldType(targetValue);
            
            console.log('验证类型匹配:', { sourceValue, sourceType, targetValue, targetType });
            
            // 检查类型是否兼容
            if (!this.areTypesCompatible(sourceType, targetType)) {
                // 显示错误提示
                this.showToast(`Cannot map ${sourceType} to ${targetType}`, 'error');
                
                // 清空目标选择
                targetSelect.value = '';
                
                // 添加错误样式
                targetSelect.style.borderColor = '#ff4444';
                setTimeout(() => {
                    targetSelect.style.borderColor = '';
                }, 3000);
            }
        }
    }

    // 将数值dataType转换为可读类型名称
    convertDataTypeCode(dataType) {
        const typeCode = parseInt(dataType);
        
        switch(typeCode) {
            case 0:
                return 'Boolean';
            case 1:
                return 'Integer';
            case 2:
                return 'Long';
            case 3:
                return 'Float';
            case 4:
                return 'Double';
            case 5:
                return 'String'; // Binary或String，统一按String处理
            default:
                console.warn('未知的dataType代码:', dataType);
                return 'String'; // 默认为String
        }
    }

    // 获取数据源字段的实际类型
    getDataSourceFieldType(fieldName) {
        // 从存储的字段类型Map中获取类型
        if (this.dataSourceFieldTypes && this.dataSourceFieldTypes.has(fieldName)) {
            const dataType = this.dataSourceFieldTypes.get(fieldName);
            return this.convertDataTypeCode(dataType);
        }
        
        // 如果没有找到，尝试从树节点中实时获取
        const leftSidebarTree = document.querySelector('.left-sidebar .tree');
        if (leftSidebarTree) {
            const allNodes = leftSidebarTree.querySelectorAll('.tree-node');
            for (const node of allNodes) {
                const span = node.querySelector('span');
                if (span && span.textContent.trim() === fieldName) {
                    const dataType = node.getAttribute('data-type') || node.dataset.type || '1';
                    return this.convertDataTypeCode(dataType);
                }
            }
        }
        
        // 默认返回Integer (dataType=1)
        return 'Integer';
    }

    // 获取目标模型字段的实际类型
    getTargetModelFieldType(targetValue) {
        // 从缓存的模型数据中获取类型信息
        if (this.cachedModelData && this.cachedModelData.inputs) {
            const inputs = typeof this.cachedModelData.inputs === 'string' 
                ? JSON.parse(this.cachedModelData.inputs) 
                : this.cachedModelData.inputs;
            
            const input = inputs.find(item => (item.name || item) === targetValue);
            if (input && input.type) {
                return input.type;
            }
        }
        
        // 如果没有找到类型信息，默认为String
        return 'String';
    }

    // 检查两种类型是否兼容
    areTypesCompatible(sourceType, targetType) {
        // 类型相同则兼容
        if (sourceType === targetType) {
            return true;
        }
        
        // 定义所有数值类型
        const numericTypes = ['Integer', 'Long', 'Float', 'Double'];
        
        // 所有数值类型之间可以互相转换
        if (numericTypes.includes(sourceType) && numericTypes.includes(targetType)) {
            return true;
        }
        
        // String类型与字节数组的转换（字节数组在系统中可能显示为String或Binary）
        if ((sourceType === 'String' && targetType === 'Binary') ||
            (sourceType === 'Binary' && targetType === 'String')) {
            return true;
        }
        
        // 其他情况不兼容
        return false;
    }

    hide() {
        console.log('AssociationRules.hide() called');
        this.removeAttribute('show');
        this.style.display = 'none';
    }
}

customElements.define('association-rules', AssociationRules);
