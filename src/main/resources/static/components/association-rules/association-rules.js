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

    applyFilters() {
        const filterInputs = this.shadowRoot.querySelectorAll('.filter-input');
        const filters = Array.from(filterInputs).map(input => input.value.trim());
        
        const [nameFilter, statusFilter] = filters;
        
        let filteredData = this.data.filter(item => {
            if (nameFilter && !item.ruleName.includes(nameFilter)) return false;
            if (statusFilter && item.status !== statusFilter) return false;
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
            this.shadowRoot.getElementById('version').value = 'v1.0.0';
            this.shadowRoot.querySelector('input[name="status"][value="active"]').checked = true;
            this.currentAction = 'add';
            
            // Restore form footer buttons
            this.restoreFormFooter();
            
            // Highlight external trees
            document.body.classList.add('association-rules-modal-open');
            
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
            
            // Fill the form with rule data
            this.shadowRoot.getElementById('ruleName').value = rule.ruleName || rule.name || '';
            this.shadowRoot.getElementById('ruleDesc').value = rule.ruleDesc || '';
            this.shadowRoot.getElementById('dataSource').value = rule.dataSource || '';
            this.shadowRoot.getElementById('targetModel').value = rule.targetModel || '';
            this.shadowRoot.getElementById('version').value = rule.version || 'v1.0.0';
            
            // Set status radio button
            const statusValue = rule.status || 'active';
            this.shadowRoot.querySelector(`input[name="status"][value="${statusValue}"]`).checked = true;
            
            // Store the rule ID for update
            form.dataset.ruleId = rule.id;
            this.currentAction = 'edit';
            
            // Restore form footer buttons
            this.restoreFormFooter();
            
            // Highlight external trees
            document.body.classList.add('association-rules-modal-open');
            
            // Initialize mappings with existing data if available
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

    saveRule() {
        const form = this.shadowRoot.getElementById('ruleForm');
        if (!form) return;

        const ruleId = form.dataset.ruleId;
        const ruleName = this.shadowRoot.getElementById('ruleName').value.trim();
        const ruleDesc = this.shadowRoot.getElementById('ruleDesc').value.trim();
        const dataSource = this.shadowRoot.getElementById('dataSource').value;
        const targetModel = this.shadowRoot.getElementById('targetModel').value;
        const version = this.shadowRoot.getElementById('version').value.trim();
        const status = this.shadowRoot.querySelector('input[name="status"]:checked')?.value || 'active';
        
        // Get mappings
        const mappings = this.getMappings();
        const resultMappings = this.getResultMappings();

        // Basic validation
        if (!ruleName) {
            this.showToast('请输入规则名称', 'error');
            return;
        }

        if (!dataSource) {
            this.showToast('请选择数据源', 'error');
            return;
        }

        if (!targetModel) {
            this.showToast('请选择目标模型', 'error');
            return;
        }

        if (mappings.length === 0) {
            this.showToast('请至少添加一个输入映射关系', 'error');
            return;
        }

        // Validate input mappings
        for (const mapping of mappings) {
            if (mapping.conversionType !== 'none' && !mapping.formula) {
                this.showToast(`输入映射 ${mapping.sourceField} → ${mapping.targetField} 的转换公式不能为空`, 'error');
                return;
            }
        }

        // No validation needed for result mappings since they don't have conversion

        const ruleData = {
            id: ruleId || Date.now(),
            ruleName,
            ruleDesc,
            dataSource,
            targetModel,
            version,
            status,
            mappings,
            resultMappings,
            updateTime: new Date().toISOString()
        };

        if (this.currentAction === 'edit' && ruleId) {
            // Update existing rule
            const index = this.data.findIndex(r => r.id === ruleId);
            if (index !== -1) {
                this.data[index] = { ...this.data[index], ...ruleData };
            }
        } else {
            // Add new rule
            ruleData.id = this.data.length > 0 ? Math.max(...this.data.map(r => r.id)) + 1 : 1;
            this.data.unshift(ruleData);
        }

        // Update the UI
        this.renderTable();
        this.hideModal();
        this.showToast(`规则已${ruleId ? '更新' : '添加'}成功`);
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
                    this.data = this.data.filter(item => item.id != id);
                    this.renderTable();
                    this.hideModal();
                    this.showToast('规则已删除');
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
            <select class="model-field-select">
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
        this.updateMappingFieldOptions();

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
            <select class="model-output-select">
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
            <select class="result-target-select">
                <option value="">请选择目标</option>
            </select>
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
        this.updateResultMappingFieldOptions();

        // If mapping data is provided, populate the fields
        if (mappingData) {
            const modelSelect = modelField.querySelector('.model-output-select');
            const resultSelect = resultField.querySelector('.result-target-select');
            
            if (mappingData.modelOutput) modelSelect.value = mappingData.modelOutput;
            if (mappingData.resultTarget) resultSelect.value = mappingData.resultTarget;
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
            const modelOutput = row.querySelector('.model-output-select')?.value;
            const resultTarget = row.querySelector('.result-target-select')?.value;
            
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
            const modelSelect = row.querySelector('.model-output-select');
            const resultSelect = row.querySelector('.result-target-select');
            
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
            
            // Update result target options
            if (resultSelect) {
                const currentValue = resultSelect.value;
                resultSelect.innerHTML = '<option value="">请选择目标</option>';
                resultTargets.forEach(target => {
                    const option = document.createElement('option');
                    option.value = target.id;
                    option.textContent = target.name;
                    if (target.id === currentValue) {
                        option.selected = true;
                    }
                    resultSelect.appendChild(option);
                });
            }
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
    
    showToast(message, type = 'success') {
        // Find the workspace-content container
        const workspaceContent = document.querySelector('.workspace-content');
        if (!workspaceContent) {
            console.warn('workspace-content element not found');
            return;
        }

        // Make sure workspace content has relative positioning and proper z-index
        workspaceContent.style.position = 'relative';
        workspaceContent.style.overflow = 'visible';
        workspaceContent.style.zIndex = '1';

        // Create toast container if it doesn't exist
        let toastContainer = workspaceContent.querySelector('.toast-container');
        if (!toastContainer) {
            toastContainer = document.createElement('div');
            toastContainer.className = 'toast-container';
            toastContainer.style.cssText = `
                position: absolute;
                top: 0;
                left: 0;
                right: 0;
                z-index: 9999;
                display: flex;
                flex-direction: column;
                align-items: center;
                padding: 20px 0;
                pointer-events: none;
                background: transparent;
            `;
            // Insert at the beginning of workspace content
            if (workspaceContent.firstChild) {
                workspaceContent.insertBefore(toastContainer, workspaceContent.firstChild);
            } else {
                workspaceContent.appendChild(toastContainer);
            }
        }

        // Create toast element
        const toast = document.createElement('div');
        toast.className = `toast toast-${type}`;
        toast.textContent = message;
        
        // Style the toast
        toast.style.cssText = `
            background: ${type === 'success' ? '#52c41a' : '#ff4d4f'};
            color: white;
            padding: 12px 24px;
            margin-bottom: 10px;
            border-radius: 4px;
            box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
            font-size: 14px;
            text-align: center;
            animation: slideInDown 0.3s ease-out;
            pointer-events: auto;
        `;

        // Add toast to container
        toastContainer.appendChild(toast);
        
        // Add animation keyframes if not already added
        if (!document.querySelector('#toast-animations')) {
            const style = document.createElement('style');
            style.id = 'toast-animations';
            style.textContent = `
                @keyframes slideInDown {
                    from {
                        transform: translateY(-20px);
                        opacity: 0;
                    }
                    to {
                        transform: translateY(0);
                        opacity: 1;
                    }
                }
                @keyframes slideOutUp {
                    from {
                        transform: translateY(0);
                        opacity: 1;
                    }
                    to {
                        transform: translateY(-20px);
                        opacity: 0;
                    }
                }
            `;
            document.head.appendChild(style);
        }
        
        // Remove after 3 seconds
        setTimeout(() => {
            toast.style.animation = 'slideOutUp 0.3s ease-out';
            setTimeout(() => {
                if (toast.parentNode) {
                    toast.parentNode.removeChild(toast);
                }
                // Remove container if empty
                if (toastContainer && toastContainer.children.length === 0) {
                    toastContainer.parentNode.removeChild(toastContainer);
                }
            }, 300);
        }, 3000);
    }
    
    show() {
        console.log('AssociationRules.show() called');
        this.setAttribute('show', '');
        console.log('AssociationRules: show attribute set');
        
        // 直接设置样式作为备用方案
        this.style.display = 'block';
        console.log('AssociationRules: style.display set to:', this.style.display);
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
