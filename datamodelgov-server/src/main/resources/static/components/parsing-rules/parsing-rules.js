class ParsingRules extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });
        this.data = [];
        this.pageSize = 10;
        this.currentPage = 1;
    }

    async loadRulesFromAPI() {
        try {
            // 显示全局loading
            if (window.showGlobalLoading) {
                window.showGlobalLoading('正在查询数据...');
            }

            // 获取筛选条件
            const nameFilter = this.shadowRoot.querySelector('.filter-input[type="text"]')?.value.trim();

            // 构建请求对象
            const requestBody = {
                pageNum: this.currentPage || 1,
                pageSize: this.pageSize || 6,
                name: nameFilter || null
            };

            console.log('查询参数:', requestBody);

            // 调用查询接口
            const result = await window.AppConfig.post('parsingRules', 'query', requestBody);
            console.log('查询结果:', result);
            
            if (result.success && result.data) {
                // 后端直接返回List<ParsingRulesEntity>，转换为前端所需格式
                this.data = result.data.map(rule => ({
                    id: rule.createTime, // 使用createTime作为唯一标识
                    name: rule.name,
                    regex: rule.regexPattern,
                    parseType: rule.parseType || 'regex',
                    language: rule.language || '',
                    isReadonly: rule.isReadonly || false,
                    pythonModule: rule.pythonModule || '',
                    pythonFunction: rule.pythonFunction || '',
                    example: rule.example || '',
                    createTime: rule.createTime,
                    createtime: new Date(rule.createTime).toLocaleString('zh-CN'),
                    updatetime: new Date(rule.updateTime).toLocaleString('zh-CN')
                }));
                
                // 同时获取总数用于分页（仅在第一页时）
                if (this.currentPage === 1) {
                    await this.loadRulesCount(nameFilter);
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
        } finally {
            // 隐藏全局loading
            if (window.hideGlobalLoading) {
                window.hideGlobalLoading();
            }
        }
    }

    async loadRulesCount(name) {
        try {
            // 构建请求对象
            const requestBody = {
                name: name || null
            };
            
            console.log('查询总量参数:', requestBody);
            
            // 使用新的API配置
            const result = await window.AppConfig.post('parsingRules', 'count', requestBody);
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
            const result = await window.AppConfig.delete('parsingRules', 'delete', { createTime });
            
            if (result.success) {
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

    showAddModal() {
        // 直接调用showModal显示新增表单
        this.currentAction = 'add';
        this.showModal('新增解析规则', this.getFormModalBody(), [
            { text: '取消', class: 'modal-btn secondary', action: 'close' },
            { text: '确认', class: 'modal-btn primary', action: 'submit' }
        ]);
        
        // 移除规则名称的readonly属性
        setTimeout(() => {
            const ruleNameInput = this.shadowRoot.getElementById('ruleName');
            if (ruleNameInput) {
                ruleNameInput.removeAttribute('readonly');
            }
        }, 100);
    }

    async editRule(id) {
        try {
            // 从API获取规则详情
            const result = await window.AppConfig.get('parsingRules', 'detail', { createTime: id });
            
            if (result.success && result.data) {
                const rule = result.data;
                const frontendRule = {
                    id: rule.createTime,
                    name: rule.name,
                    regex: rule.regexPattern,
                    parseType: rule.parseType || 'regex',
                    language: rule.language || '',
                    isReadonly: rule.isReadonly || false,
                    pythonModule: rule.pythonModule || '',
                    pythonFunction: rule.pythonFunction || '',
                    example: rule.example || ''
                };
                
                // 设置当前操作为编辑模式
                this.currentAction = 'edit';
                
                this.showModal('编辑解析规则', this.getFormModalBody(frontendRule), [
                    { text: '取消', class: 'modal-btn secondary', action: 'close' },
                    { text: '保存', class: 'modal-btn primary', action: 'edit', id }
                ]);
            } else {
                this.showToast('获取规则详情失败', 'error');
            }
        } catch (error) {
            console.error('获取规则详情失败:', error);
            this.showToast('网络错误，无法获取规则详情', 'error');
        }
    }

    deleteRule(id) {
        this.showModal('删除确认', `确定要删除 "${this.getRuleNameByCreateTime(id)}" 解析规则吗？`, [
            { text: '取消', class: 'modal-btn secondary', action: 'close' },
            { text: '删除', class: 'modal-btn primary', action: 'delete', id }
        ]);
    }

    async saveRule() {
        try {
            const formData = this.collectFormData();
            
            // 验证必填字段
            if (!formData.name) {
                this.showToast('请输入规则名称', 'error');
                return;
            }
            
            // regex和typehint模式需要正则表达式
            if ((formData.parseType === 'regex' || formData.parseType === 'typehint') && !formData.regexPattern) {
                this.showToast('请输入正则表达式', 'error');
                return;
            }
            
            // 验证正则表达式语法
            if (formData.regexPattern) {
                try {
                    new RegExp(formData.regexPattern);
                } catch (e) {
                    this.showToast('正则表达式无效', 'error');
                    return;
                }
            }

            console.log('保存解析规则数据:', formData);

            // 调用保存API
            const result = await window.AppConfig.post('parsingRules', 'save', formData);
            console.log('保存响应:', result);
            
            if (result.success) {
                this.showToast(`规则已${this.currentAction === 'edit' ? '更新' : '添加'}成功`);
                this.hideModal();
                
                // 重新加载规则列表
                await this.loadRulesFromAPI();
                this.renderTable();
                
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
                this.showToast(result.message || '保存失败', 'error');
            }
        } catch (error) {
            console.error('保存规则失败:', error);
            this.showToast('保存失败，请稍后重试', 'error');
        }
    }

    collectFormData() {
        // 收集基本信息
        const ruleName = this.shadowRoot.getElementById('ruleName')?.value.trim() || '';
        const regexValue = this.shadowRoot.getElementById('ruleRegex')?.value.trim() || '';
        const exampleValue = this.shadowRoot.getElementById('ruleExample')?.value.trim() || '';
        const parseTypeValue = this.shadowRoot.getElementById('ruleParseType')?.value || 'regex';
        const languageValue = this.shadowRoot.getElementById('ruleLanguage')?.value || '';
        const pythonModuleValue = this.shadowRoot.getElementById('rulePythonModule')?.value.trim() || '';
        const pythonFunctionValue = this.shadowRoot.getElementById('rulePythonFunction')?.value.trim() || '';
        
        // 构建完整的表单数据对象，包含ParsingRulesEntity需要的所有字段
        const formData = {
            name: ruleName,
            regexPattern: regexValue,
            example: exampleValue,
            parseType: parseTypeValue,
            language: languageValue,
            pythonModule: pythonModuleValue,
            pythonFunction: pythonFunctionValue,
            createTime: this.currentAction === 'edit' && this.currentEditId 
                ? parseInt(this.currentEditId) 
                : null
        };

        return formData;
    }

    // Toast消息提示方法
    showToast(message, type = 'success') {
        // 使用统一的消息系统
        if (window.CommonUtils && window.CommonUtils.showToast) {
            window.CommonUtils.showToast(message, type);
        } else {
            // 降级处理
            console.log(`[${type.toUpperCase()}] ${message}`);
        }
    }

    getRuleNameByCreateTime(createTime) {
        const rule = this.data.find(r => r.id == createTime);
        return rule ? rule.name : '';
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
            
            // 不在初始化时自动加载数据，只在显示时加载
            // this.loadRulesFromAPI(); // 移除这行
        }, 100);
    }

    // 添加show方法供main.js调用 - 参考数据源管理的实现
    async show(...args) {
        console.log('ParsingRules show() 被调用', args);
        this.style.display = 'block';

        // 重置筛选条件和分页
        this.currentPage = 1;
        const filterInput = this.shadowRoot.querySelector('.filter-input[type="text"]');
        if (filterInput) {
            filterInput.value = '';
        }

        // 每次显示时刷新数据
        await this.loadRulesFromAPI();
        this.renderTable();
    }

    async loadResources() {
        try {
            const cssLink = document.createElement('link');
            cssLink.rel = 'stylesheet';
            cssLink.href = './components/parsing-rules/parsing-rules.css';
            this.shadowRoot.appendChild(cssLink);
        } catch (error) {
            console.error('Failed to load CSS:', error);
        }

        if (window.location.protocol === 'file:') {
            this.shadowRoot.innerHTML += this.getFallbackHTML();
        } else {
            try {
                const response = await fetch('./components/parsing-rules/parsing-rules.html');
                if (!response.ok) {
                    throw new Error(`HTTP error! status: ${response.status}`);
                }
                const html = await response.text();
                this.shadowRoot.innerHTML += html;
                console.log('Parsing rules HTML template loaded successfully');
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
            ${this.buildFilterRow('')}
        </div>
        <div class="filter-actions">
            <div class="filter-spacer"></div>
            <button class="filter-btn outline" type="button" id="resetFilters">重置</button>
            <button class="filter-btn solid" type="button" id="applyFilters">查询</button>
        </div>
    </div>

    <div class="parsing-table-card">
        <div class="table-toolbar">
            <button class="toolbar-btn green" type="button" id="addRuleBtn">新增</button>
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
</div>
        `;
    }

    buildFilterRow(nameValue = '') {
        return `
            <div class="filter-row">
                <div class="filter-field">
                    <span class="filter-label">名称</span>
                    <input class="filter-input" type="text" value="${nameValue}" placeholder="请输入规则名称" />
                </div>
            </div>
        `;
    }

    getFormModalBody(defaults = {}) {
        const values = {
            name: defaults.name || '',
            regex: defaults.regex || '',
            example: defaults.example || '',
            parseType: defaults.parseType || 'regex',
            language: defaults.language || '',
            pythonModule: defaults.pythonModule || '',
            pythonFunction: defaults.pythonFunction || ''
        };
        const isEdit = this.currentAction === 'edit';
        const isReadonly = defaults.isReadonly || false;
        const parseTypeOptions = [
            { value: 'regex', label: '正则表达式' },
            { value: 'typehint', label: 'Python TypeHint' },
            { value: 'inspect', label: 'Python Inspect' }
        ];
        const languageOptions = [
            { value: 'python', label: 'Python' },
            { value: 'matlab', label: 'MATLAB' },
            { value: 'cpp', label: 'C/C++' },
            { value: 'generic', label: '通用' }
        ];
        return `
            <div class="modal-form">
                <div class="modal-form-row">
                    <span class="modal-label">名称 :</span>
                    <input class="modal-input" id="ruleName" type="text" value="${values.name}" placeholder="请输入规则名称" ${isEdit || isReadonly ? 'readonly' : ''} />
                </div>

                <div class="modal-form-row">
                    <span class="modal-label">解析类型 :</span>
                    <select class="modal-input" id="ruleParseType" ${isReadonly ? 'disabled' : ''}>
                        ${parseTypeOptions.map(opt => `<option value="${opt.value}" ${values.parseType === opt.value ? 'selected' : ''}>${opt.label}</option>`).join('')}
                    </select>
                </div>

                <div class="modal-form-row">
                    <span class="modal-label">适用语言 :</span>
                    <select class="modal-input" id="ruleLanguage" ${isReadonly ? 'disabled' : ''}>
                        <option value="">请选择</option>
                        ${languageOptions.map(opt => `<option value="${opt.value}" ${values.language === opt.value ? 'selected' : ''}>${opt.label}</option>`).join('')}
                    </select>
                </div>
                
                <div class="modal-form-row" id="regexRow">
                    <span class="modal-label">正则表达式 :</span>
                    <input class="modal-input" id="ruleRegex" type="text" value="${values.regex}" placeholder="请输入正则表达式" ${isReadonly ? 'readonly' : ''} />
                    <div id="regexError" style="color: #ff4d4f; font-size: 12px; margin-top: 4px; display: none;">正则表达式无效</div>
                </div>

                <div class="modal-form-row" id="pythonModuleRow" style="display: ${values.parseType === 'inspect' ? 'flex' : 'none'};">
                    <span class="modal-label">Python模块名 :</span>
                    <input class="modal-input" id="rulePythonModule" type="text" value="${values.pythonModule}" placeholder="例如: my_module" />
                </div>

                <div class="modal-form-row" id="pythonFunctionRow" style="display: ${values.parseType === 'inspect' ? 'flex' : 'none'};">
                    <span class="modal-label">Python函数名 :</span>
                    <input class="modal-input" id="rulePythonFunction" type="text" value="${values.pythonFunction}" placeholder="例如: run" />
                </div>

                <div class="modal-form-row">
                    <span class="modal-label">示例注释规范 :</span>
                    <textarea class="modal-textarea" id="ruleExample" placeholder="请输入示例注释规范，如：&#10;# @Input: speed (float) - 车速&#10;# @Output: power (double) - 功率" rows="4" ${isReadonly ? 'readonly' : ''}>${values.example}</textarea>
                </div>

                <div class="regex-tutorial" id="regexTutorial" style="display: ${values.parseType === 'regex' ? 'block' : 'none'};">
                    <div class="tutorial-title">📖 配置指南</div>
                    <div class="tutorial-content" id="tutorialContent">
                        <!-- 由updateTutorial动态填充 -->
                    </div>
                </div>

                <div class="modal-test-area" style="display: ${values.parseType === 'regex' ? 'block' : 'none'};">
                    <div class="test-header">
                        <span class="test-label">测试区</span>
                        <button class="test-clear-btn" id="clearTest">清空</button>
                    </div>
                    <textarea class="test-input" id="testInput" placeholder="在此输入测试文本，系统将实时显示匹配结果..."></textarea>
                    <div class="test-results" id="testResults">
                        <div class="test-result-header">匹配结果：</div>
                        <div class="test-result-content" id="testResultContent">暂无匹配结果</div>
                    </div>
                </div>
            </div>
        `;
    }

    renderTable() {
        const tbody = this.shadowRoot.getElementById('tableBody');
        if (!tbody) return;

        // 使用后端分页数据，不再进行本地分页
        const pageData = this.data; // ✅ 直接使用后端返回的数据

        const parseTypeLabels = { regex: '正则', typehint: 'TypeHint', inspect: 'Inspect' };
        const languageLabels = { python: 'Python', matlab: 'MATLAB', cpp: 'C/C++', generic: '通用' };
        tbody.innerHTML = pageData.map(item => `
            <tr>
                <td>${item.id}</td>
                <td>${item.name}</td>
                <td>${parseTypeLabels[item.parseType] || item.parseType || '正则'}</td>
                <td>${languageLabels[item.language] || item.language || '-'}</td>
                <td><code style="background: #f5f5f5; padding: 2px 4px; border-radius: 2px; font-size: 11px;">${item.regex || '-'}</code></td>
                <td>${item.isReadonly ? '<span style="color: #f59e0b;">是</span>' : '否'}</td>
                <td>${item.createtime}</td>
                <td>${item.updatetime}</td>
                <td>
                    <div class="action-buttons">
                        <button class="action-btn edit" data-action="edit" data-id="${item.id}">编辑</button>
                        ${!item.isReadonly ? `<button class="action-btn delete" data-action="delete" data-id="${item.id}">删除</button>` : ''}
                    </div>
                </td>
            </tr>
        `).join('');

        this.updatePagination();
    }

    bindEvents() {
        const filterRows = this.shadowRoot.getElementById('filterRows');
        const resetFilters = this.shadowRoot.getElementById('resetFilters');
        const applyFilters = this.shadowRoot.getElementById('applyFilters');
        const addRuleBtn = this.shadowRoot.getElementById('addRuleBtn');
        const modalMask = this.shadowRoot.getElementById('modalMask');
        const modalClose = this.shadowRoot.getElementById('modalClose');

        if (resetFilters && filterRows) {
            resetFilters.addEventListener('click', () => {
                filterRows.innerHTML = this.buildFilterRow('');
                this.currentPage = 1;
                this.loadRulesFromAPI();
            });
        }

        if (applyFilters) {
            applyFilters.addEventListener('click', () => {
                this.currentPage = 1; // 重置到第一页
                this.loadRulesFromAPI();
            });
        }

        if (addRuleBtn) {
            addRuleBtn.addEventListener('click', () => {
                this.showAddModal();
            });
        }

        if (modalClose && modalMask) {
            modalClose.addEventListener('click', () => {
                this.hideModal();
            });
        }

        // 移除点击遮罩关闭功能，避免误操作
        // if (modalMask) {
        //     modalMask.addEventListener('click', (event) => {
        //         if (event.target === modalMask) {
        //             this.hideModal();
        //         }
        //     });
        // }

        const tbody = this.shadowRoot.getElementById('tableBody');
        if (tbody) {
            tbody.addEventListener('click', (event) => {
                if (event.target.classList.contains('action-btn')) {
                    const id = event.target.dataset.id;
                    if (event.target.classList.contains('delete')) {
                        this.deleteRule(id);
                    } else if (event.target.classList.contains('edit')) {
                        this.editRule(id);
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

            modalFooter.replaceWith(modalFooter.cloneNode(true));
            const newModalFooter = this.shadowRoot.getElementById('modalFooter');
            
            // 添加实时验证
            const regexInput = modalBody.querySelector('#ruleRegex');
            const regexError = modalBody.querySelector('#regexError');
            const testInput = modalBody.querySelector('#testInput');
            const testResultContent = modalBody.querySelector('#testResultContent');
            const clearTestBtn = modalBody.querySelector('#clearTest');
            
            // 解析类型切换事件
            const parseTypeSelect = modalBody.querySelector('#ruleParseType');
            const languageSelect = modalBody.querySelector('#ruleLanguage');
            if (parseTypeSelect) {
                parseTypeSelect.addEventListener('change', () => {
                    const selectedType = parseTypeSelect.value;
                    const regexRow = modalBody.querySelector('#regexRow');
                    const regexTutorial = modalBody.querySelector('#regexTutorial');
                    const testArea = modalBody.querySelector('.modal-test-area');
                    const pythonModuleRow = modalBody.querySelector('#pythonModuleRow');
                    const pythonFunctionRow = modalBody.querySelector('#pythonFunctionRow');
                    
                    if (selectedType === 'inspect') {
                        if (regexRow) regexRow.style.display = 'none';
                        if (regexTutorial) regexTutorial.style.display = 'none';
                        if (testArea) testArea.style.display = 'none';
                        if (pythonModuleRow) pythonModuleRow.style.display = 'flex';
                        if (pythonFunctionRow) pythonFunctionRow.style.display = 'flex';
                    } else {
                        if (regexRow) regexRow.style.display = 'flex';
                        if (regexTutorial) regexTutorial.style.display = 'block';
                        if (testArea) testArea.style.display = 'block';
                        if (pythonModuleRow) pythonModuleRow.style.display = 'none';
                        if (pythonFunctionRow) pythonFunctionRow.style.display = 'none';
                        this.updateTutorial(modalBody, selectedType, languageSelect?.value || '');
                    }
                });
            }
            if (languageSelect) {
                languageSelect.addEventListener('change', () => {
                    this.updateTutorial(modalBody, parseTypeSelect?.value || 'regex', languageSelect.value);
                });
            }
            // 初始填充教程
            const initParseType = parseTypeSelect?.value || 'regex';
            const initLanguage = languageSelect?.value || '';
            this.updateTutorial(modalBody, initParseType, initLanguage);
            
            const performTest = () => {
                const testText = testInput?.value;
                const regexValue = regexInput?.value.trim();
                
                if (!testText || !regexValue) {
                    testResultContent.innerHTML = '<span class="test-no-match">请输入测试文本和正则表达式</span>';
                    return;
                }
                
                try {
                    const regex = new RegExp(regexValue, 'gm');
                    const lines = testText.split('\n');
                    let allMatches = [];
                    
                    lines.forEach((line, lineIndex) => {
                        const lineMatches = [...line.matchAll(regex)];
                        lineMatches.forEach(match => {
                            allMatches.push({
                                lineNum: lineIndex + 1,
                                fullMatch: match[0],
                                groups: match.slice(1)
                            });
                        });
                    });
                    
                    // 获取当前捕获组标签
                    const currentParseType = parseTypeSelect?.value || 'regex';
                    const currentLanguage = languageSelect?.value || '';
                    const currentRuleName = modalBody.querySelector('#ruleName')?.value || '';
                    const groupLabels = this.getGroupLabels(currentParseType, currentLanguage, regexValue, currentRuleName);
                    
                    if (allMatches.length > 0) {
                        let resultHTML = `<div class="test-match-count">找到 ${allMatches.length} 个匹配项：</div>`;
                        
                        allMatches.forEach((match, index) => {
                            resultHTML += `<div style="margin-top: 8px; padding: 8px; background: #f0f9ff; border-radius: 4px;">`;
                            resultHTML += `<div style="font-weight: 500; color: #0369a1;">匹配 ${index + 1}（第${match.lineNum}行）</div>`;
                            resultHTML += `<div style="margin: 4px 0; padding: 4px 8px; background: #fff; border-radius: 3px; font-family: monospace;">${match.fullMatch}</div>`;
                            resultHTML += `<div style="font-size: 11px; color: #6b7280; margin-top: 4px;">捕获组：</div>`;
                            resultHTML += `<div style="margin-left: 12px; font-size: 11px;">`;
                            match.groups.forEach((g, gi) => {
                                const label = groupLabels[gi] || `第${gi + 1}组`;
                                const value = g !== undefined ? g : '空';
                                const isClassified = this.classifyGroup(currentParseType, gi, value);
                                const style = isClassified ? 'background: #dcfce7; color: #166534;' : 'background: #e0f2fe; padding: 1px 4px; border-radius: 2px;';
                                resultHTML += `<div>${['①','②','③','④','⑤','⑥','⑦','⑧'][gi] || (gi+1)} ${label}: <code style="${style}">${value}</code></div>`;
                            });
                            resultHTML += `</div></div>`;
                        });
                        
                        testResultContent.innerHTML = resultHTML;
                    } else {
                        testResultContent.innerHTML = '<span class="test-no-match">未找到匹配项，请检查正则表达式和测试文本格式是否匹配</span>';
                    }
                } catch (e) {
                    testResultContent.innerHTML = '<span class="test-no-match">正则表达式无效，无法测试</span>';
                }
            };
            
            if (regexInput && regexError) {
                const validateRegex = () => {
                    const regexValue = regexInput.value.trim();
                    if (regexValue) {
                        try {
                            new RegExp(regexValue);
                            regexError.style.display = 'none';
                            regexInput.style.borderColor = '#e2e6ef';
                            performTest(); // 重新执行测试
                        } catch (e) {
                            regexError.style.display = 'block';
                            regexInput.style.borderColor = '#ff4d4f';
                        }
                    } else {
                        regexError.style.display = 'none';
                        regexInput.style.borderColor = '#e2e6ef';
                        performTest(); // 重新执行测试
                    }
                };
                
                regexInput.addEventListener('input', validateRegex);
                regexInput.addEventListener('blur', validateRegex);
            }
            
            if (testInput) {
                testInput.addEventListener('input', performTest);
            }
            
            // 添加规则名称唯一性校验
            const ruleNameInput = modalBody.querySelector('#ruleName');
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
                            const result = await window.AppConfig.get('parsingRules', 'validate-name', {
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
            
            if (clearTestBtn) {
                clearTestBtn.addEventListener('click', () => {
                    testInput.value = '';
                    testResultContent.innerHTML = '暂无匹配结果';
                });
            }
            
            newModalFooter.addEventListener('click', (event) => {
                const action = event.target.dataset.action;
                const id = event.target.dataset.id;

                if (action === 'close') {
                    this.hideModal();
                } else if (action === 'submit') {
                    this.currentAction = 'add';
                    this.saveRule();
                } else if (action === 'edit' && id) {
                    this.currentAction = 'edit';
                    this.currentEditId = id;
                    this.saveRule();
                } else if (action === 'import') {
                    this.showToast('导入功能开发中', 'info');
                } else if (action === 'delete' && id) {
                    this.deleteRuleFromAPI(id);
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
        this.style.display = 'none';
        this.removeAttribute('show');
    }

    // ========== 动态教程与捕获组标签 ==========

    updateTutorial(modalBody, parseType, language) {
        const tutorialContent = modalBody.querySelector('#tutorialContent');
        if (!tutorialContent) return;

        // 根据规则名匹配教程（从当前编辑的规则名或正则推断）
        const ruleName = modalBody.querySelector('#ruleName')?.value || '';
        const regexValue = modalBody.querySelector('#ruleRegex')?.value || '';

        const tutorials = {
            // ===== Python 规则 =====
            'Python标准规则': `
                <p><strong>匹配规则：</strong>系统读取代码文件前50行，逐行用正则表达式匹配 <code># @Input</code>/<code># @Output</code> 注释行。</p>
                <p><strong>格式（4个捕获组）：</strong></p>
                <ol>
                    <li><strong>① 参数类型：</strong>匹配 <code>Input</code> 或 <code>Output</code>，用于分类。写法：<code>(Input|Output)</code></li>
                    <li><strong>② 参数名称：</strong>变量名，如speed、gear。写法：<code>(\\w+)</code></li>
                    <li><strong>③ 数据类型：</strong>如float、int、double。写法：<code>(\\w+)</code></li>
                    <li><strong>④ 参数说明：</strong>中文描述。写法：<code>(.*)</code></li>
                </ol>
                <p><strong>示例：</strong></p>
                <div style="background:#f8fafc; padding:8px; border-radius:4px; font-family:monospace; font-size:12px;">
                    # @Input: speed (float) - 车速<br>
                    # @Input: gear (int) - 档位<br>
                    # @Output: power (float) - 功率
                </div>
                <p style="margin-top:6px;">对应正则：<code>^#\\s*@(Input|Output)\\s*:?\\s*(\\w+)\\s*[\\(\\[]?\\s*(\\w+)\\s*[\\)\\]]?\\s*-?\\s*(.*)$</code></p>`,
            'Python Google Style规则': `
                <p><strong>Google Style</strong>是Python最流行的文档注释规范，Sphinx原生支持。</p>
                <p><strong>格式（3个捕获组）：</strong></p>
                <ol>
                    <li><strong>① 参数名称：</strong>如speed、gear。写法：<code>(\\w+)</code></li>
                    <li><strong>② 数据类型：</strong>括号中的类型，如float、int。写法：<code>([^)]+)</code></li>
                    <li><strong>③ 参数说明：</strong>冒号后的描述。写法：<code>(.+)</code></li>
                </ol>
                <p><strong>分类逻辑：</strong>在 <code>Args:</code> 段下的归入Inputs；在 <code>Returns:</code> 段下的归入Outputs。</p>
                <p><strong>示例：</strong></p>
                <div style="background:#f8fafc; padding:8px; border-radius:4px; font-family:monospace; font-size:12px;">
                    def run(speed, gear):<br>
                    &nbsp;&nbsp;&nbsp;&nbsp;"""计算功率.<br>
                    &nbsp;&nbsp;&nbsp;&nbsp;Args:<br>
                    &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;speed (float): 车速<br>
                    &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;gear (int): 档位<br>
                    &nbsp;&nbsp;&nbsp;&nbsp;Returns:<br>
                    &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;power (float): 功率<br>
                    &nbsp;&nbsp;&nbsp;&nbsp;"""
                </div>
                <p style="margin-top:6px;">对应正则：<code>^\\s+(\\w+)\\s*\\(([^)]+)\\)\\s*:\\s*(.+)$</code></p>
                <p style="color:#2563eb; font-size:12px;">💡 Google Style中，Args段下的参数自动归为Inputs，Returns段下的自动归为Outputs。</p>`,
            'Python Sphinx Style规则': `
                <p><strong>Sphinx/reST Style</strong>是Sphinx文档生成器原生支持的格式，广泛用于科学计算项目。</p>
                <p><strong>格式（3个捕获组）：</strong></p>
                <ol>
                    <li><strong>① 标记类型：</strong>匹配 <code>param</code>/<code>type</code>/<code>return</code>/<code>returns</code>/<code>rtype</code>。<code>param</code>/<code>type</code>归入Inputs，<code>return</code>/<code>returns</code>/<code>rtype</code>归入Outputs。写法：<code>(param|type|returns?|rtype)</code></li>
                    <li><strong>② 类型+名称 或 类型：</strong><code>:param float speed:</code> 中为 <code>float speed</code>；<code>:rtype:</code> 中为空。写法：<code>([^:]*)</code></li>
                    <li><strong>③ 说明：</strong>冒号后的描述文字。写法：<code>(.*)</code></li>
                </ol>
                <p><strong>示例：</strong></p>
                <div style="background:#f8fafc; padding:8px; border-radius:4px; font-family:monospace; font-size:12px;">
                    def run(speed, gear):<br>
                    &nbsp;&nbsp;&nbsp;&nbsp;"""计算功率.<br>
                    &nbsp;&nbsp;&nbsp;&nbsp;:param float speed: 车速<br>
                    &nbsp;&nbsp;&nbsp;&nbsp;:param int gear: 档位<br>
                    &nbsp;&nbsp;&nbsp;&nbsp;:returns: 功率<br>
                    &nbsp;&nbsp;&nbsp;&nbsp;:rtype: float<br>
                    &nbsp;&nbsp;&nbsp;&nbsp;"""
                </div>
                <p style="margin-top:6px;">对应正则：<code>^\\s*:(param|type|returns?|rtype)\\s+([^:]*):\\s*(.*)$</code></p>`,
            // ===== MATLAB 规则 =====
            'MATLAB标准规则': `
                <p><strong>匹配规则：</strong>系统读取代码文件前50行，逐行匹配 <code>% @Input</code>/<code>% @Output</code> 注释行。</p>
                <p><strong>格式（4个捕获组）：</strong></p>
                <ol>
                    <li><strong>① 参数类型：</strong>匹配 <code>Input</code> 或 <code>Output</code>。写法：<code>(Input|Output)</code></li>
                    <li><strong>② 参数名称：</strong>变量名。写法：<code>(\\w+)</code></li>
                    <li><strong>③ 数据类型：</strong>如double、single。写法：<code>(\\w+)</code></li>
                    <li><strong>④ 参数说明：</strong>中文描述。写法：<code>(.*)</code></li>
                </ol>
                <p><strong>示例：</strong></p>
                <div style="background:#f8fafc; padding:8px; border-radius:4px; font-family:monospace; font-size:12px;">
                    % @Input: speed (double) - 车速<br>
                    % @Output: power (double) - 功率
                </div>
                <p style="margin-top:6px;">对应正则：<code>^%\\s*@(Input|Output)\\s*:?\\s*(\\w+)\\s*[\\(\\[]?\\s*(\\w+)\\s*[\\)\\]]?\\s*-?\\s*(.*)$</code></p>`,
            'MATLAB Help Text规则': `
                <p><strong>MATLAB Help Text</strong>是MATLAB Editor自动补全支持的标准函数注释格式。</p>
                <p><strong>格式（2个捕获组）：</strong></p>
                <ol>
                    <li><strong>① 参数名称：</strong>变量名，如speed、gear、power。写法：<code>(\\w+)</code></li>
                    <li><strong>② 说明+类型：</strong>短横线后的描述（含括号中的类型）。写法：<code>(.+)</code></li>
                </ol>
                <p><strong>分类逻辑：</strong>系统根据参数名与函数签名对比：函数输入参数归入Inputs，函数输出变量归入Outputs。</p>
                <p><strong>示例：</strong></p>
                <div style="background:#f8fafc; padding:8px; border-radius:4px; font-family:monospace; font-size:12px;">
                    function power = run(speed, gear)<br>
                    %RUN 计算功率<br>
                    %   speed - 车速 (float)<br>
                    %   gear - 档位 (int)<br>
                    %   power - 功率 (float)
                </div>
                <p style="margin-top:6px;">对应正则：<code>^%\\s*(\\w+)\\s*-\\s*(.+)$</code></p>
                <p style="color:#b45309; font-size:12px;">⚠️ 此格式只有2个捕获组，系统需结合函数签名自动判断Input/Output分类。</p>`,
            // ===== C++ 规则 =====
            'C++ Doxygen规则': `
                <p><strong>匹配规则：</strong>系统读取C/C++头文件注释，通过Doxygen风格的@param/@return标记提取参数。</p>
                <p><strong>C++ Doxygen格式（5个捕获组，第2组可选）：</strong></p>
                <ol>
                    <li><strong>① 标记类型：</strong>匹配 <code>param</code> 或 <code>return</code>。<code>param</code>归入Inputs，<code>return</code>归入Outputs。写法：<code>(param|return)</code></li>
                    <li><strong>② 传参方向（可选）：</strong>匹配 <code>in</code>/<code>out</code>/<code>in,out</code>。<code>in</code>归入Inputs，<code>out</code>归入Outputs，<code>in,out</code>同时归入两者。写法：<code>(?:\\[([^\\]]+)\\]\\s+)?</code> — 注意这是可选组，可能为空</li>
                    <li><strong>③ 参数名称：</strong>变量名。写法：<code>(\\w+)</code></li>
                    <li><strong>④ 数据类型（可选）：</strong>括号中的类型。写法：<code>(?:\\(([^)]+)\\))?</code> — 可选组，可能为空</li>
                    <li><strong>⑤ 参数说明：</strong>描述文字。写法：<code>(.*)</code></li>
                </ol>
                <p><strong>示例：</strong></p>
                <div style="background:#f8fafc; padding:8px; border-radius:4px; font-family:monospace; font-size:12px;">
                    /**<br>
                    &nbsp;* @param[in] speed (float) - 车速<br>
                    &nbsp;* @param[in] gear (int) - 档位<br>
                    &nbsp;* @return power (float) - 功率<br>
                    */
                </div>
                <p style="margin-top:6px;">对应正则：<code>^\\s*\\*\\s*@(param|return)\\s+(?:\\[([^\\]]+)\\]\\s+)?(\\w+)(?:\\s*\\(([^)]+)\\))?\\s*-?\\s*(.*)$</code></p>
                <p style="color:#b45309; font-size:12px;">⚠️ 注意：C++ Doxygen正则有5个捕获组，第2组和第4组是可选的，匹配时可能为空值。</p>`,
            // ===== 通用 =====
            '_generic': `
                <p><strong>匹配规则：</strong>系统读取代码文件前50行，逐行用正则表达式匹配，提取出参数信息后分类到Inputs或Outputs。</p>
                <p><strong>通用注释格式（4个捕获组）：</strong></p>
                <ol>
                    <li><strong>① 参数类型：</strong>匹配 <code>Input</code>/<code>Output</code>/<code>Param</code>/<code>Return</code>，用于分类。写法：<code>(Input|Output|Param|Return)</code></li>
                    <li><strong>② 参数名称：</strong>变量名。写法：<code>(\\w+)</code></li>
                    <li><strong>③ 数据类型：</strong>如float、int。写法：<code>([\\w\\[\\]]+)</code></li>
                    <li><strong>④ 参数说明：</strong>描述文字。写法：<code>(.*)</code></li>
                </ol>
                <p><strong>分类逻辑：</strong>包含"input"或"param"→Inputs；包含"output"或"return"→Outputs</p>`,
            '_typehint': `
                <p><strong>TypeHint解析模式：</strong>直接解析Python函数签名中的类型注解，无需注释。</p>
                <p><strong>Python TypeHint格式（3个捕获组）：</strong></p>
                <ol>
                    <li><strong>① 函数名称：</strong>如 <code>run</code>、<code>init</code>。系统将函数名作为API名称。写法：<code>(\\w+)</code></li>
                    <li><strong>② 参数列表：</strong>括号中的参数签名，如 <code>speed: float, gear: int</code>。系统自动拆分为多个Input。写法：<code>([^)]*)</code></li>
                    <li><strong>③ 返回类型：</strong>箭头后的类型，如 <code>float</code>、<code>None</code>。系统将其作为Output的数据类型。写法：<code>([^:]+)</code></li>
                </ol>
                <p><strong>示例：</strong></p>
                <div style="background:#f8fafc; padding:8px; border-radius:4px; font-family:monospace; font-size:12px;">
                    def run(speed: float, gear: int) -> float:<br>
                    &nbsp;&nbsp;&nbsp;&nbsp;"""计算功率"""<br>
                    def init(temp: float, pressure: float) -> None:
                </div>
                <p style="margin-top:6px;">对应正则：<code>^\\s*def\\s+(\\w+)\\s*\\(([^)]*)\\)\\s*->\\s*([^:]+):\\s*(?:#.*)?$</code></p>
                <p style="color:#2563eb; font-size:12px;">💡 TypeHint模式下，系统自动从参数列表提取Input参数名和类型，从返回类型提取Output。</p>`,
            '_inspect': `
                <p><strong>Python Inspect模式：</strong>使用Python inspect模块自动反射解析函数签名，无需正则表达式。</p>
                <p><strong>使用方式：</strong></p>
                <ol>
                    <li>在"Python模块名"中输入模块路径，如 <code>my_module</code> 或 <code>package.module</code></li>
                    <li>在"Python函数名"中输入函数名，如 <code>run</code></li>
                    <li>系统将自动导入模块并使用 <code>inspect.signature()</code> 提取参数信息</li>
                </ol>
                <p style="color:#2563eb; font-size:12px;">💡 此模式无需配置正则表达式，但需要模型文件中包含可导入的Python模块。</p>`
        };

        // 优先按规则名匹配，否则按parseType匹配
        let content = tutorials[ruleName];
        if (!content) {
            if (parseType === 'typehint') content = tutorials._typehint;
            else if (parseType === 'inspect') content = tutorials._inspect;
            else content = tutorials._generic;
        }
        tutorialContent.innerHTML = content;
    }

    getGroupLabels(parseType, language, regexValue, ruleName) {
        // 优先按规则名匹配
        if (ruleName) {
            const nameLabels = {
                'C++ Doxygen规则': ['标记类型(param/return)', '传参方向(可选)', '参数名称', '数据类型(可选)', '参数说明'],
                'Python Google Style规则': ['参数名称', '数据类型', '参数说明'],
                'Python Sphinx Style规则': ['标记类型(param/return/rtype)', '类型+名称', '参数说明'],
                'MATLAB Help Text规则': ['参数名称', '说明+类型'],
                'Python TypeHint规则': ['函数名称(API名)', '参数列表(自动拆分)', '返回类型'],
            };
            if (nameLabels[ruleName]) return nameLabels[ruleName];
        }
        // 按parseType+language推断
        if (parseType === 'typehint') {
            return ['函数名称(API名)', '参数列表(自动拆分)', '返回类型'];
        }
        if (parseType === 'regex' && language === 'cpp') {
            return ['标记类型(param/return)', '传参方向(可选)', '参数名称', '数据类型(可选)', '参数说明'];
        }
        // 默认4组: Python标准/MATLAB标准/Generic
        return ['参数类型(Input/Output)', '参数名称', '数据类型', '参数说明'];
    }

    classifyGroup(parseType, groupIndex, value) {
        // 判断该捕获组的值是否已被系统成功分类（用于测试区高亮）
        if (!value || value === '空') return false;
        const lowerVal = value.toLowerCase().trim();
        // 第1组（参数类型/标记类型）分类判断
        if (groupIndex === 0) {
            if (parseType === 'typehint') return true; // 函数名总是有效的
            if (['input', 'output', 'param', 'return'].some(k => lowerVal.includes(k))) return true;
        }
        return false;
    }
}

customElements.define('parsing-rules', ParsingRules);
