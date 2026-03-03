class ParsingRules extends HTMLElement {
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
        
        setTimeout(() => {
            const modalMask = this.shadowRoot.getElementById('modalMask');
            if (modalMask) {
                modalMask.hidden = true;
                modalMask.style.display = 'none';
            }
            this.bindEvents();
        }, 100);
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
</div>
        `;
    }

    buildFilterRow(nameValue = '', regexValue = '') {
        return `
            <div class="filter-row">
                <div class="filter-field">
                    <span class="filter-label">名称</span>
                    <input class="filter-input" type="text" value="${nameValue}" placeholder="请输入规则名称" />
                </div>
                <div class="filter-field">
                    <span class="filter-label">正则</span>
                    <input class="filter-input" type="text" value="${regexValue}" placeholder="请输入正则表达式" />
                </div>
            </div>
        `;
    }

    getFormModalBody(defaults = {}) {
        const values = {
            name: defaults.name || '',
            regex: defaults.regex || '',
            parsingType: defaults.parsingType || 'regex',
            pythonModule: defaults.pythonModule || '',
            pythonFunction: defaults.pythonFunction || ''
        };
        return `
            <div class="modal-form">
                <div class="modal-form-row">
                    <span class="modal-label">名称 :</span>
                    <input class="modal-input" id="ruleName" type="text" value="${values.name}" placeholder="请输入规则名称" />
                </div>
                
                <div class="parsing-type-selector">
                    <div class="parsing-type-option ${values.parsingType === 'regex' ? 'selected' : ''}" data-type="regex">
                        <input type="radio" name="parsingType" value="regex" id="typeRegex" ${values.parsingType === 'regex' ? 'checked' : ''}>
                        <label for="typeRegex">正则表达式</label>
                    </div>
                    <div class="parsing-type-option ${values.parsingType === 'python' ? 'selected' : ''}" data-type="python">
                        <input type="radio" name="parsingType" value="python" id="typePython" ${values.parsingType === 'python' ? 'checked' : ''}>
                        <label for="typePython">Python 反射</label>
                    </div>
                </div>
                
                <div class="regex-field">
                    <div class="modal-form-row">
                        <span class="modal-label">正则表达式 :</span>
                        <input class="modal-input" id="ruleRegex" type="text" value="${values.regex}" placeholder="请输入正则表达式" />
                        <div id="regexError" style="color: #ff4d4f; font-size: 12px; margin-top: 4px; display: none;">正则表达式无效</div>
                    </div>
                </div>
                
                <div class="python-options ${values.parsingType === 'python' ? 'show' : ''}" id="pythonOptions">
                    <div class="python-option-row">
                        <span class="modal-label" style="min-width: 80px;">模块名 :</span>
                        <input class="python-input" id="pythonModule" type="text" value="${values.pythonModule}" placeholder="如: math, re, datetime">
                    </div>
                    <div class="python-option-row">
                        <span class="modal-label" style="min-width: 80px;">函数名 :</span>
                        <input class="python-input" id="pythonFunction" type="text" value="${values.pythonFunction}" placeholder="如: sqrt, match, datetime">
                    </div>
                    <div style="font-size: 11px; color: #6b7280; margin-top: 8px;">
                        💡 系统将使用 Python inspect 模块读取函数签名和文档
                    </div>
                </div>
                
                <div class="modal-test-area">
                    <div class="test-header">
                        <span class="test-label">测试区</span>
                        <button class="test-clear-btn" id="clearTest">清空</button>
                    </div>
                    <textarea class="test-input" id="testInput" placeholder="在此输入测试文本或代码，系统将实时显示匹配结果..."></textarea>
                    <div class="test-results" id="testResults">
                        <div class="test-result-header">匹配结果：</div>
                        <div class="test-result-content" id="testResultContent">暂无匹配结果</div>
                    </div>
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
                    <input type="file" id="fileInput" accept=".json,.csv,.txt" style="display: none;">
                </div>
            </div>
        `;
    }

    seedData() {
        this.data = [
            {
                id: 1,
                name: 'Python标准',
                regex: '#\\s*@(Input|Output)\\s*:\\s*(\\w+)\\s*\\(([^)]+)\\)\\s*-\\s*([^\\n]+)',
                parsingType: 'regex',
                createtime: '2024-01-15',
                updatetime: '2024-01-20'
            },
            {
                id: 2,
                name: 'MATLAB标准',
                regex: '%\\s*@(Input|Output)\\s*:\\s*(\\w+)\\s*\\(([^)]+)\\)\\s*-\\s*([^\\n]+)',
                parsingType: 'regex',
                createtime: '2024-01-10',
                updatetime: '2024-01-18'
            },
            {
                id: 3,
                name: 'C++ Doxygen',
                regex: '\\/\\*\\*\\s*@(?:param|return|in|out)\\s+(\\w+)\\s+([^\\n]+)\\s*(?:\\*\\s*Type:\\s*([^\\n]+))?',
                parsingType: 'regex',
                createtime: '2024-01-08',
                updatetime: '2024-01-16'
            },
            {
                id: 4,
                name: 'JavaDoc',
                regex: '\\/\\*\\*\\s*@(?:param|return)\\s+(\\w+)\\s+([^\\n]+)\\s*(?:\\{[^}]*\\}\\s*([^\\n]+))?',
                parsingType: 'regex',
                createtime: '2024-01-05',
                updatetime: '2024-01-12'
            },
            {
                id: 5,
                name: '通用注释',
                regex: '[\\/\\#]\\s*@(Input|Output|Param|Return)\\s*[:=]\\s*(\\w+)\\s*\\[?([^\\]]*)\\]?\\s*-\\s*([^\\n]+)',
                parsingType: 'regex',
                createtime: '2024-01-03',
                updatetime: '2024-01-10'
            }
        ];
    }

    renderTable() {
        const tbody = this.shadowRoot.getElementById('tableBody');
        if (!tbody) return;

        const start = (this.currentPage - 1) * this.pageSize;
        const end = start + this.pageSize;
        const pageData = this.data.slice(start, end);

        tbody.innerHTML = pageData.map(row => `
            <tr>
                <td>${row.id}</td>
                <td>${row.name}</td>
                <td><code style="background: #f5f5f5; padding: 2px 4px; border-radius: 2px; font-size: 11px;">${row.regex}</code></td>
                <td>${row.createtime}</td>
                <td>${row.updatetime}</td>
                <td>
                    <div class="action-buttons">
                        <button class="action-btn edit" data-id="${row.id}">编辑</button>
                        <button class="action-btn delete" data-id="${row.id}">删除</button>
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
                filterRows.innerHTML = this.buildFilterRow('', '');
            });
        }

        if (applyFilters) {
            applyFilters.addEventListener('click', () => {
                this.showModal('查询结果', `找到 ${this.data.length} 条符合条件的记录`);
            });
        }

        if (addRuleBtn) {
            addRuleBtn.addEventListener('click', () => {
                this.showModal('新增解析规则', this.getFormModalBody(), [
                    { text: '取消', class: 'modal-btn secondary', action: 'close' },
                    { text: '确认', class: 'modal-btn primary', action: 'submit' }
                ]);
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

        const tbody = this.shadowRoot.getElementById('tableBody');
        if (tbody) {
            tbody.addEventListener('click', (event) => {
                if (event.target.classList.contains('action-btn')) {
                    const id = event.target.dataset.id;
                    if (event.target.classList.contains('delete')) {
                        this.showModal('删除确认', `确定要删除 ID 为 ${id} 的解析规则吗？`, [
                            { text: '取消', class: 'modal-btn secondary', action: 'close' },
                            { text: '删除', class: 'modal-btn primary', action: 'delete', id }
                        ]);
                    } else if (event.target.classList.contains('edit')) {
                        const id = event.target.dataset.id;
                        const rule = this.data.find(r => r.id == id);
                        if (rule) {
                            this.showModal('编辑解析规则', this.getFormModalBody(rule), [
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

            modalFooter.replaceWith(modalFooter.cloneNode(true));
            const newModalFooter = this.shadowRoot.getElementById('modalFooter');
            
            // 添加实时验证
            const regexInput = modalBody.querySelector('#ruleRegex');
            const regexError = modalBody.querySelector('#regexError');
            const testInput = modalBody.querySelector('#testInput');
            const testResultContent = modalBody.querySelector('#testResultContent');
            const clearTestBtn = modalBody.querySelector('#clearTest');
            const pythonOptions = modalBody.querySelector('#pythonOptions');
            const regexField = modalBody.querySelector('.regex-field');
            const pythonModule = modalBody.querySelector('#pythonModule');
            const pythonFunction = modalBody.querySelector('#pythonFunction');
            
            let currentParsingType = 'regex';
            
            // 处理解析类型切换
            const handleParsingTypeChange = () => {
                const selectedType = modalBody.querySelector('input[name="parsingType"]:checked')?.value || 'regex';
                currentParsingType = selectedType;
                
                // 更新选中状态
                modalBody.querySelectorAll('.parsing-type-option').forEach(option => {
                    option.classList.toggle('selected', option.dataset.type === selectedType);
                });
                
                // 显示/隐藏相应字段
                if (selectedType === 'python') {
                    regexField.classList.add('hidden');
                    pythonOptions.classList.add('show');
                } else {
                    regexField.classList.remove('hidden');
                    pythonOptions.classList.remove('show');
                }
                
                // 重新执行测试
                performTest();
            };
            
            // 绑定解析类型切换事件
            modalBody.querySelectorAll('.parsing-type-option').forEach(option => {
                option.addEventListener('click', () => {
                    const radio = option.querySelector('input[type="radio"]');
                    radio.checked = true;
                    handleParsingTypeChange();
                });
            });
            
            const performTest = () => {
                const testText = testInput?.value;
                
                if (!testText) {
                    testResultContent.innerHTML = '<span class="test-no-match">请输入测试文本或代码</span>';
                    return;
                }
                
                if (currentParsingType === 'regex') {
                    performRegexTest();
                } else if (currentParsingType === 'python') {
                    performPythonTest();
                }
            };
            
            const performRegexTest = () => {
                const regexValue = regexInput?.value.trim();
                
                if (!regexValue) {
                    testResultContent.innerHTML = '<span class="test-no-match">请输入正则表达式</span>';
                    return;
                }
                
                try {
                    const regex = new RegExp(regexValue, 'g');
                    const matches = testText.match(regex);
                    
                    if (matches && matches.length > 0) {
                        let resultHTML = `<div class="test-match-count">找到 ${matches.length} 个匹配项：</div>`;
                        
                        // 高亮显示匹配结果
                        let highlightedText = testText;
                        highlightedText = highlightedText.replace(regex, (match) => {
                            return `<span class="test-match">${match}</span>`;
                        });
                        
                        resultHTML += `<div>${highlightedText}</div>`;
                        
                        // 显示匹配列表
                        resultHTML += '<div style="margin-top: 8px; font-size: 11px; color: #6b7280;">匹配项：';
                        matches.forEach((match, index) => {
                            resultHTML += `<div style="margin-left: 16px; margin-top: 2px;">${index + 1}. "${match}"</div>`;
                        });
                        resultHTML += '</div>';
                        
                        testResultContent.innerHTML = resultHTML;
                    } else {
                        testResultContent.innerHTML = '<span class="test-no-match">未找到匹配项</span>';
                    }
                } catch (e) {
                    testResultContent.innerHTML = '<span class="test-no-match">正则表达式无效，无法测试</span>';
                }
            };
            
            const performPythonTest = () => {
                const moduleName = pythonModule?.value.trim();
                const functionName = pythonFunction?.value.trim();
                
                if (!moduleName || !functionName) {
                    testResultContent.innerHTML = '<span class="test-no-match">请输入模块名和函数名</span>';
                    return;
                }
                
                // 模拟Python inspect模块的反射分析
                const mockInspectResults = this.simulatePythonInspect(moduleName, functionName);
                
                if (mockInspectResults.error) {
                    testResultContent.innerHTML = `<span class="test-no-match">错误: ${mockInspectResults.error}</span>`;
                    return;
                }
                
                // 显示详细的反射分析结果
                let resultHTML = `
                    <div class="test-match-count">Python 反射分析结果：</div>
                    <div style="margin-bottom: 8px;">
                        <strong>模块:</strong> ${mockInspectResults.module}<br>
                        <strong>函数:</strong> ${mockInspectResults.name}
                    </div>
                `;
                
                // 函数签名
                resultHTML += `
                    <div style="background: #f8fafc; padding: 8px; border-radius: 4px; margin-bottom: 8px;">
                        <div style="color: #059669; font-weight: 600; margin-bottom: 4px;">🔍 函数签名:</div>
                        <code style="font-family: 'Courier New', monospace; font-size: 11px;">
                            ${mockInspectResults.signature}
                        </code>
                    </div>
                `;
                
                // 参数详情
                if (mockInspectResults.parameters && mockInspectResults.parameters.length > 0) {
                    resultHTML += `
                        <div style="background: #f8fafc; padding: 8px; border-radius: 4px; margin-bottom: 8px;">
                            <div style="color: #059669; font-weight: 600; margin-bottom: 4px;">⚙️ 参数列表:</div>
                    `;
                    
                    mockInspectResults.parameters.forEach((param, index) => {
                        const paramType = param.type || 'unknown';
                        const paramDefault = param.default ? ` = ${param.default}` : '';
                        const paramDesc = param.description || '无描述';
                        
                        resultHTML += `
                            <div style="margin-left: 16px; margin-top: 2px; font-size: 11px;">
                                <strong>${param.name}</strong>: ${paramType}${paramDefault}<br>
                                <span style="color: #6b7280;">${paramDesc}</span>
                            </div>
                        `;
                    });
                    
                    resultHTML += '</div>';
                }
                
                // 返回值信息
                if (mockInspectResults.returns) {
                    resultHTML += `
                        <div style="background: #f8fafc; padding: 8px; border-radius: 4px; margin-bottom: 8px;">
                            <div style="color: #059669; font-weight: 600; margin-bottom: 4px;">↩️ 返回值:</div>
                            <div style="margin-left: 16px; font-size: 11px;">
                                <strong>类型:</strong> ${mockInspectResults.returns.type || 'unknown'}<br>
                                <strong>描述:</strong> ${mockInspectResults.returns.description || '无描述'}
                            </div>
                        </div>
                    `;
                }
                
                // 文档字符串
                if (mockInspectResults.docstring) {
                    resultHTML += `
                        <div style="background: #f8fafc; padding: 8px; border-radius: 4px; margin-bottom: 8px;">
                            <div style="color: #059669; font-weight: 600; margin-bottom: 4px;">📝 文档字符串:</div>
                            <div style="margin-left: 16px; font-size: 11px; font-style: italic; color: #374151;">
                                ${mockInspectResults.docstring}
                            </div>
                        </div>
                    `;
                }
                
                // 源码位置
                resultHTML += `
                    <div style="font-size: 11px; color: #6b7280; margin-top: 8px;">
                        📍 位置: ${mockInspectResults.filename}:${mockInspectResults.lineno}
                    </div>
                `;
                
                testResultContent.innerHTML = resultHTML;
            };
            
            // 模拟Python inspect模块
            this.simulatePythonInspect = (moduleName, functionName) => {
                // 模拟标准库函数的inspect结果
                const standardModules = {
                    'math': {
                        'sqrt': {
                            name: 'sqrt',
                            module: 'math',
                            signature: 'sqrt(x, /)',
                            parameters: [
                                { name: 'x', type: 'float', default: '', description: '要计算平方根的数字' }
                            ],
                            returns: { type: 'float', description: 'x的平方根' },
                            docstring: 'Return the square root of x.',
                            filename: 'mathmodule.c',
                            lineno: 1234
                        },
                        'sin': {
                            name: 'sin',
                            module: 'math',
                            signature: 'sin(x, /)',
                            parameters: [
                                { name: 'x', type: 'float', default: '', description: '角度（弧度）' }
                            ],
                            returns: { type: 'float', description: 'x的正弦值' },
                            docstring: 'Return the sine of x (measured in radians).',
                            filename: 'mathmodule.c',
                            lineno: 5678
                        },
                        'log': {
                            name: 'log',
                            module: 'math',
                            signature: 'log(x, base=None, /)',
                            parameters: [
                                { name: 'x', type: 'float', default: '', description: '要计算对数的数字' },
                                { name: 'base', type: 'float', default: 'None', description: '对数的底数' }
                            ],
                            returns: { type: 'float', description: 'x的对数' },
                            docstring: 'Return the logarithm of x to the given base.',
                            filename: 'mathmodule.c',
                            lineno: 9012
                        }
                    },
                    'datetime': {
                        'datetime': {
                            name: 'datetime',
                            module: 'datetime',
                            signature: 'datetime(year, month, day, hour=0, minute=0, second=0, microsecond=0, tzinfo=None)',
                            parameters: [
                                { name: 'year', type: 'int', default: '', description: '年份' },
                                { name: 'month', type: 'int', default: '', description: '月份 (1-12)' },
                                { name: 'day', type: 'int', default: '', description: '日期 (1-31)' },
                                { name: 'hour', type: 'int', default: '0', description: '小时 (0-23)' },
                                { name: 'minute', type: 'int', default: '0', description: '分钟 (0-59)' },
                                { name: 'second', type: 'int', default: '0', description: '秒 (0-59)' },
                                { name: 'microsecond', type: 'int', default: '0', description: '微秒 (0-999999)' },
                                { name: 'tzinfo', type: 'tzinfo', default: 'None', description: '时区信息' }
                            ],
                            returns: { type: 'datetime', description: 'datetime对象' },
                            docstring: 'datetime(year, month, day[, hour[, minute[, second[, microsecond[, tzinfo]]]]]])',
                            filename: 'datetime.py',
                            lineno: 456
                        }
                    },
                    're': {
                        'match': {
                            name: 'match',
                            module: 're',
                            signature: 'match(pattern, string, flags=0)',
                            parameters: [
                                { name: 'pattern', type: 'str', default: '', description: '正则表达式模式' },
                                { name: 'string', type: 'str', default: '', description: '要搜索的字符串' },
                                { name: 'flags', type: 'int', default: '0', description: '匹配标志' }
                            ],
                            returns: { type: 'MatchObject', description: '匹配对象或None' },
                            docstring: 'Try to apply the pattern at the start of the string.',
                            filename: 're.py',
                            lineno: 789
                        },
                        'search': {
                            name: 'search',
                            module: 're',
                            signature: 'search(pattern, string, flags=0)',
                            parameters: [
                                { name: 'pattern', type: 'str', default: '', description: '正则表达式模式' },
                                { name: 'string', type: 'str', default: '', description: '要搜索的字符串' },
                                { name: 'flags', type: 'int', default: '0', description: '匹配标志' }
                            ],
                            returns: { type: 'MatchObject', description: '匹配对象或None' },
                            docstring: 'Search through string for a match to the pattern.',
                            filename: 're.py',
                            lineno: 1011
                        }
                    }
                };
                
                // 检查模块是否存在
                const module = standardModules[moduleName];
                if (!module) {
                    return { error: `模块 '${moduleName}' 不存在或无法导入` };
                }
                
                // 检查函数是否存在
                const func = module[functionName];
                if (!func) {
                    return { error: `函数 '${functionName}' 在模块 '${moduleName}' 中不存在` };
                }
                
                return func;
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
            
            if (pythonModule || pythonFunction) {
                pythonModule?.addEventListener('input', performTest);
                pythonFunction?.addEventListener('input', performTest);
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
                    const name = modalBody.querySelector('#ruleName')?.value.trim();
                    const regex = modalBody.querySelector('#ruleRegex')?.value.trim();
                    
                    if (!name || !regex) {
                        this.showModal('错误', '请填写完整的规则名称和正则表达式');
                        return;
                    }
                    
                    // 验证正则表达式语法
                    try {
                        new RegExp(regex);
                    } catch (e) {
                        this.showModal('错误', '正则表达式无效');
                        return;
                    }
                    
                    const newRule = {
                        id: this.data.length + 1,
                        name: name,
                        regex: regex,
                        createtime: new Date().toISOString().split('T')[0],
                        updatetime: new Date().toISOString().split('T')[0]
                    };
                    
                    this.data.unshift(newRule);
                    this.renderTable();
                    this.hideModal();
                    // 使用统一的消息系统
                    if (window.CommonUtils && window.CommonUtils.showToast) {
                        window.CommonUtils.showToast('解析规则已添加', 'success');
                    } else {
                        this.showModal('成功', '解析规则已添加');
                    }
                } else if (action === 'edit' && id) {
                    const name = modalBody.querySelector('#ruleName')?.value.trim();
                    const regex = modalBody.querySelector('#ruleRegex')?.value.trim();
                    
                    if (!name || !regex) {
                        this.showModal('错误', '请填写完整的规则名称和正则表达式');
                        return;
                    }
                    
                    // 验证正则表达式语法
                    try {
                        new RegExp(regex);
                    } catch (e) {
                        this.showModal('错误', '正则表达式无效');
                        return;
                    }
                    
                    const rule = this.data.find(r => r.id == id);
                    if (rule) {
                        rule.name = name;
                        rule.regex = regex;
                        rule.updatetime = new Date().toISOString().split('T')[0];
                        this.renderTable();
                        this.hideModal();
                        // 使用统一的消息系统
                        if (window.CommonUtils && window.CommonUtils.showToast) {
                            window.CommonUtils.showToast('解析规则已更新', 'success');
                        } else {
                            this.showModal('成功', '解析规则已更新');
                        }
                    }
                } else if (action === 'import') {
                    this.showModal('成功', '解析规则导入完成');
                } else if (action === 'delete' && id) {
                    this.data = this.data.filter(row => row.id != id);
                    this.renderTable();
                    this.hideModal();
                    // 使用统一的消息系统
                    if (window.CommonUtils && window.CommonUtils.showToast) {
                        window.CommonUtils.showToast('解析规则已删除', 'success');
                    } else {
                        this.showModal('成功', '解析规则已删除');
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

    show() {
        this.setAttribute('show', '');
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
        this.removeAttribute('show');
    }
}

customElements.define('parsing-rules', ParsingRules);
