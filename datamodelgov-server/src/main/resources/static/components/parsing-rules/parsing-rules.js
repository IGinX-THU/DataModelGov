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
                    example: rule.example
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
            
            if (!formData.regexPattern) {
                this.showToast('请输入正则表达式', 'error');
                return;
            }
            
            // 验证正则表达式语法
            try {
                new RegExp(formData.regexPattern);
            } catch (e) {
                this.showToast('正则表达式无效', 'error');
                return;
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
        
        // 构建完整的表单数据对象，包含ParsingRulesEntity需要的所有字段
        const formData = {
            name: ruleName,
            regexPattern: regexValue,
            example: exampleValue,
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
            alert(message);
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
            example: defaults.example || ''
        };
        const isEdit = this.currentAction === 'edit';
        return `
            <div class="modal-form">
                <div class="modal-form-row">
                    <span class="modal-label">名称 :</span>
                    <input class="modal-input" id="ruleName" type="text" value="${values.name}" placeholder="请输入规则名称" ${isEdit ? 'readonly' : ''} />
                </div>
                
                <div class="modal-form-row">
                    <span class="modal-label">正则表达式 :</span>
                    <input class="modal-input" id="ruleRegex" type="text" value="${values.regex}" placeholder="请输入正则表达式" />
                    <div id="regexError" style="color: #ff4d4f; font-size: 12px; margin-top: 4px; display: none;">正则表达式无效</div>
                </div>

                <div class="modal-form-row">
                    <span class="modal-label">示例注释规范 :</span>
                    <textarea class="modal-textarea" id="ruleExample" placeholder="请输入示例注释规范，如：&#10;# @Input: speed (float) - 车速&#10;# @Output: power (double) - 功率" rows="4">${values.example}</textarea>
                </div>

                <div class="regex-tutorial">
                    <div class="tutorial-title">📖 正则表达式配置指南</div>
                    <div class="tutorial-content">
                        <p><strong>匹配规则：</strong>系统读取代码文件前50行，逐行用正则表达式匹配，提取出参数信息后分类到Inputs或Outputs。</p>
                        <p><strong>捕获组要求（必须严格按此顺序）：</strong></p>
                        <ol>
                            <li><strong>第1组 - 参数类型：</strong>用于分类，匹配到的文字如果包含"input"或"param"（不区分大小写）会归入Inputs；包含"output"或"return"（不区分大小写）会归入Outputs。常用写法：<code>(Input|Output|Param|Return)</code></li>
                            <li><strong>第2组 - 参数名称：</strong>参数变量名，如speed、gear。写法：<code>(\\w+)</code></li>
                            <li><strong>第3组 - 数据类型：</strong>系统支持的数据类型（自动映射）：Boolean、Integer、Long、Float、Double、String。代码中可写：bool/boolean、int/integer、long、float、double、string/str。写法：<code>([\\w\\[\\]]+)</code>或<code>([^\\)]+)</code></li>
                            <li><strong>第4组 - 参数说明：</strong>参数中文描述，如车速、档位。写法：<code>(.+)</code>或<code>([^\\n]*)</code></li>
                        </ol>
                        <p><strong>最简单的配置示例</strong></p>
                        <p>假设代码注释格式为：<code>Input speed float 车速</code>（类型 名称 数据类型 说明，用空格分隔）</p>
                        <p>对应的正则为：<code>(Input|Output)\\s+(\\w+)\\s+(\\w+)\\s+(.+)</code></p>
                        <p>拆解说明：</p>
                        <ol>
                            <li><code>(Input|Output)</code> - 第1组：参数类型，匹配"Input"或"Output"</li>
                            <li><code>\\s+</code> - 匹配一个或多个空格</li>
                            <li><code>(\\w+)</code> - 第2组：参数名称，如"speed"</li>
                            <li><code>\\s+</code> - 匹配一个或多个空格</li>
                            <li><code>(\\w+)</code> - 第3组：数据类型，如"float"</li>
                            <li><code>\\s+</code> - 匹配一个或多个空格</li>
                            <li><code>(.+)</code> - 第4组：参数说明，如"车速"</li>
                        </ol>
                        <p><strong>常见代码注释示例：</strong></p>
                        <ul>
                            <li><strong>Python:</strong> <code># Input speed float 车速</code> — 正则为：<code>(Input|Output)\\s+(\\w+)\\s+(\\w+)\\s+(.+)</code></li>
                            <li><strong>MATLAB:</strong> <code>% Output power double 功率</code> — 正则为：<code>(Input|Output)\\s+(\\w+)\\s+(\\w+)\\s+(.+)</code></li>
                            <li><strong>Java/C++:</strong> <code>// Input gear int 档位</code> — 正则为：<code>(Input|Output)\\s+(\\w+)\\s+(\\w+)\\s+(.+)</code></li>
                            <li><strong>Java/C++多行:</strong> <code>/* Output result float 结果 */</code> — 正则为：<code>/\\*\\s*(Input|Output)\\s+(\\w+)\\s+(\\w+)\\s+(.+?)\\s*\\*/</code></li>
                        </ul>
                    </div>
                </div>

                <div class="modal-test-area">
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

        tbody.innerHTML = pageData.map(item => `
            <tr>
                <td>${item.id}</td>
                <td>${item.name}</td>
                <td><code style="background: #f5f5f5; padding: 2px 4px; border-radius: 2px; font-size: 11px;">${item.regex}</code></td>
                <td>${item.createtime}</td>
                <td>${item.updatetime}</td>
                <td>
                    <div class="action-buttons">
                        <button class="action-btn edit" data-action="edit" data-id="${item.id}">编辑</button>
                        ${!item.name.includes('默认规则') ? `<button class="action-btn delete" data-action="delete" data-id="${item.id}">删除</button>` : ''}
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
                    
                    if (allMatches.length > 0) {
                        let resultHTML = `<div class="test-match-count">找到 ${allMatches.length} 个匹配项：</div>`;
                        
                        allMatches.forEach((match, index) => {
                            resultHTML += `<div style="margin-top: 8px; padding: 8px; background: #f0f9ff; border-radius: 4px;">`;
                            resultHTML += `<div style="font-weight: 500; color: #0369a1;">匹配 ${index + 1}（第${match.lineNum}行）</div>`;
                            resultHTML += `<div style="margin: 4px 0; padding: 4px 8px; background: #fff; border-radius: 3px; font-family: monospace;">${match.fullMatch}</div>`;
                            resultHTML += `<div style="font-size: 11px; color: #6b7280; margin-top: 4px;">捕获组：</div>`;
                            resultHTML += `<div style="margin-left: 12px; font-size: 11px;">`;
                            resultHTML += `<div>① 参数类型: <code style="background: #e0f2fe; padding: 1px 4px; border-radius: 2px;">${match.groups[0] || '空'}</code></div>`;
                            resultHTML += `<div>② 参数名称: <code style="background: #e0f2fe; padding: 1px 4px; border-radius: 2px;">${match.groups[1] || '空'}</code></div>`;
                            resultHTML += `<div>③ 数据类型: <code style="background: #e0f2fe; padding: 1px 4px; border-radius: 2px;">${match.groups[2] || '空'}</code></div>`;
                            resultHTML += `<div>④ 参数说明: <code style="background: #e0f2fe; padding: 1px 4px; border-radius: 2px;">${match.groups[3] || '空'}</code></div>`;
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
}

customElements.define('parsing-rules', ParsingRules);
