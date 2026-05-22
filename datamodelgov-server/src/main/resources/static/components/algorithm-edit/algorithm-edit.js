class AlgorithmEdit extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });
        this.currentAlgorithm = null;
        this.inputs = [];
        this.outputs = [];
        this._dataSourceFields = [];
        this._modelBindings = [];
    }

    async connectedCallback() {
        await this.loadResources();
        this.render();
        this.bindEvents();
        // 不在初始化时自动加载解析规则，只在显示时加载
        // await this.loadParsingRules();
        this.hide(); // 默认隐藏
    }

    async loadResources() {
        // 加载CSS
        try {
            const response = await fetch('./components/algorithm-edit/algorithm-edit.css');
            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }
            const css = await response.text();
            const style = document.createElement('style');
            style.textContent = css;
            this.shadowRoot.appendChild(style);
            console.log('Algorithm edit CSS loaded successfully');
        } catch (error) {
            console.error('Failed to load CSS:', error);
        }

        // 加载HTML模板
        try {
            const response = await fetch('./components/algorithm-edit/algorithm-edit.html');
            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }
            const html = await response.text();
            this.shadowRoot.innerHTML += html;
            console.log('Algorithm edit HTML template loaded successfully');
        } catch (error) {
            console.error('Failed to load HTML template:', error);
        }
    }

    render() {
        // HTML已通过loadResources加载
    }

    bindEvents() {
        // 关闭按钮
        const closeBtn = this.shadowRoot.getElementById('closeBtn');
        if (closeBtn) {
            closeBtn.addEventListener('click', (e) => {
                e.stopPropagation();
                this.hide();
            });
        }

        // 取消按钮
        const cancelBtn = this.shadowRoot.getElementById('cancelBtn');
        if (cancelBtn) {
            cancelBtn.addEventListener('click', (e) => {
                e.stopPropagation();
                this.hide();
            });
        }

        // 保存按钮
        const saveBtn = this.shadowRoot.getElementById('saveBtn');
        if (saveBtn) {
            saveBtn.addEventListener('click', (e) => {
                e.stopPropagation();
                this.save();
            });
        }

        // 添加输入参数按钮
        const addInputBtn = this.shadowRoot.getElementById('addInputBtn');
        if (addInputBtn) {
            addInputBtn.addEventListener('click', (e) => {
                e.stopPropagation();
                this.addInputParam();
            });
        }

        // 添加输出参数按钮
        const addOutputBtn = this.shadowRoot.getElementById('addOutputBtn');
        if (addOutputBtn) {
            addOutputBtn.addEventListener('click', (e) => {
                e.stopPropagation();
                this.addOutputParam();
            });
        }

        // 数据源变化事件 - 刷新参数表中的数据源字段下拉
        const dataSource = this.shadowRoot.getElementById('dataSource');
        if (dataSource) {
            dataSource.addEventListener('change', () => this.loadDataSourceFields());
        }

        // 添加模型绑定按钮
        const addModelBindBtn = this.shadowRoot.getElementById('addModelBindBtn');
        if (addModelBindBtn) {
            addModelBindBtn.addEventListener('click', () => this.addModelBindRow());
        }

        // 生成CSV表头按钮
        const genCsvHeaderBtn = this.shadowRoot.getElementById('genCsvHeaderBtn');
        if (genCsvHeaderBtn) {
            genCsvHeaderBtn.addEventListener('click', () => this.generateCsvHeader());
        }

        // 预览按钮
        const previewBtn = this.shadowRoot.getElementById('previewBtn');
        if (previewBtn) {
            previewBtn.addEventListener('click', (e) => {
                e.stopPropagation();
                this.refreshPreview();
            });
        }

        // 从代码自动解析按钮
        const autoParseBtn = this.shadowRoot.getElementById('autoParseBtn');
        if (autoParseBtn) {
            autoParseBtn.addEventListener('click', (e) => {
                e.stopPropagation();
                this.autoParseFromCode();
            });
        }

        // 高级规则配置按钮
        const advancedConfigBtn = this.shadowRoot.getElementById('advancedConfigBtn');
        if (advancedConfigBtn) {
            advancedConfigBtn.addEventListener('click', (e) => {
                e.stopPropagation();
                this.navigateToParsingRules();
            });
        }

        // 解析规则下拉选择
        const parseRulesSelect = this.shadowRoot.getElementById('parseRulesSelect');
        if (parseRulesSelect) {
            parseRulesSelect.addEventListener('change', (e) => {
                e.stopPropagation();
                this.onParseRulesChange(e.target.value);
            });
        }

        // 源文件下拉选择
        const sourceFileSelect = this.shadowRoot.getElementById('sourceFileSelect');
        if (sourceFileSelect) {
            sourceFileSelect.addEventListener('change', (e) => {
                e.stopPropagation();
                this.onSourceFileChange(e.target.value);
            });
        }

        // 强制覆盖复选框
        const forceOverrideCheck = this.shadowRoot.getElementById('forceOverrideCheck');
        if (forceOverrideCheck) {
            forceOverrideCheck.addEventListener('change', (e) => {
                e.stopPropagation();
                this.onForceOverrideChange(e.target.checked);
            });
        }

        // 阻止表单容器内的点击事件冒泡
        const formContainer = this.shadowRoot.querySelector('.form-container');
        if (formContainer) {
            formContainer.addEventListener('click', (e) => {
                e.stopPropagation();
            });
        }

        // ESC键关闭
        const handleEsc = (e) => {
            if (e.key === 'Escape') {
                this.hide();
                document.removeEventListener('keydown', handleEsc);
            }
        };
        document.addEventListener('keydown', handleEsc);
    }

    async show(algorithmInfo) {
        this.currentAlgorithm = algorithmInfo;
        this.removeAttribute('hidden');
        await this.loadAlgorithmData(algorithmInfo);
        await this.loadParsingRules(); // 确保加载解析规则
    }

    // 新增方法：直接接收algorithm-detail的数据，不重复调用接口
    async showWithAlgorithmData(algorithmInfo, algorithmDetailData) {
        this.currentAlgorithm = algorithmInfo;
        this.currentAlgorithmMeta = algorithmDetailData;
        this.removeAttribute('hidden');
        
        // 确保加载解析规则
        await this.loadParsingRules();
        
        // 加载源文件列表
        await this.loadSourceFiles();
        
        // 直接使用algorithm-detail的数据填充表单，完全使用接口数据
        const algorithmNameInput = this.shadowRoot.getElementById('algorithmName');
        const developerInput = this.shadowRoot.getElementById('developer');
        const versionInput = this.shadowRoot.getElementById('version');
        const sceneInput = this.shadowRoot.getElementById('scene');

        if (algorithmNameInput) algorithmNameInput.value = algorithmDetailData.name || '';
        if (developerInput) developerInput.value = algorithmDetailData.author || '';
        if (versionInput) versionInput.value = algorithmDetailData.version || '';
        if (sceneInput) sceneInput.value = algorithmDetailData.scene || '';

        // 加载档案描述字段
        const descriptionInput = this.shadowRoot.getElementById('description');
        const outputFormatInput = this.shadowRoot.getElementById('outputFormat');

        if (descriptionInput) descriptionInput.value = algorithmDetailData.description || '';
        if (outputFormatInput) outputFormatInput.value = algorithmDetailData.outputFormat || '';

        // 使用接口返回的inputs和outputs数据
        this.loadInterfaceParamsFromData(algorithmDetailData.inputs, algorithmDetailData.outputs);

        // 加载关联绑定数据
        this.loadBindingData(algorithmInfo);
    }

    hide() {
        this.setAttribute('hidden', '');
    }

    async loadAlgorithmData(algorithmInfo) {
        try {
            // 调用API获取完整的算法元数据
            const result = await window.AppConfig.get('algorithm', 'metas', {
                name: algorithmInfo.name,
                version: algorithmInfo.version
            });
            
            if (result.success && result.data) {
                this.currentAlgorithmMeta = result.data;
                console.log('获取到完整算法元数据:', this.currentAlgorithmMeta);
            } else {
                console.error('获取算法元数据失败:', result.message);
                // 如果获取失败，至少保存基本信息
                this.currentAlgorithmMeta = {
                    name: algorithmInfo.name,
                    version: algorithmInfo.version,
                    author: algorithmInfo.author,
                    scene: algorithmInfo.scene
                };
            }
        } catch (error) {
            console.error('获取算法元数据异常:', error);
            // 如果获取失败，至少保存基本信息
            this.currentAlgorithmMeta = {
                name: algorithmInfo.name,
                version: algorithmInfo.version,
                author: algorithmInfo.author,
                scene: algorithmInfo.scene
            };
        }
        
        // 加载基本信息到表单
        const algorithmNameInput = this.shadowRoot.getElementById('algorithmName');
        const developerInput = this.shadowRoot.getElementById('developer');
        const versionInput = this.shadowRoot.getElementById('version');
        const sceneInput = this.shadowRoot.getElementById('scene');

        if (algorithmNameInput) algorithmNameInput.value = algorithmInfo.name || '';
        if (developerInput) developerInput.value = algorithmInfo.author || '';
        if (versionInput) versionInput.value = algorithmInfo.version || '';
        if (sceneInput) sceneInput.value = algorithmInfo.scene || '';

        // 加载档案描述字段
        const descriptionInput = this.shadowRoot.getElementById('description');
        const outputFormatInput = this.shadowRoot.getElementById('outputFormat');

        if (descriptionInput) descriptionInput.value = this.currentAlgorithmMeta?.description || '';
        if (outputFormatInput) outputFormatInput.value = this.currentAlgorithmMeta?.outputFormat || '';

        // 加载接口参数（使用从API获取的数据）
        if (this.currentAlgorithmMeta && this.currentAlgorithmMeta.inputs) {
            this.loadInterfaceParamsFromData(this.currentAlgorithmMeta.inputs, this.currentAlgorithmMeta.outputs);
        } else {
            // 如果没有数据，使用默认参数
            this.loadInterfaceParams();
        }

        // 加载关联绑定数据
        this.loadBindingData(algorithmInfo);
    }

    loadInterfaceParamsFromData(inputsData, outputsData) {
        console.log('loadInterfaceParamsFromData - inputsData:', inputsData);
        console.log('loadInterfaceParamsFromData - outputsData:', outputsData);
        
        // 解析inputs数据
        let inputs = [];
        if (inputsData) {
            try {
                inputs = typeof inputsData === 'string' ? JSON.parse(inputsData) : inputsData;
                console.log('解析后的inputs:', inputs);
            } catch (error) {
                console.error('解析inputs参数数据失败:', error);
                inputs = [];
            }
        }
        
        // 解析outputs数据
        let outputs = [];
        if (outputsData) {
            try {
                outputs = typeof outputsData === 'string' ? JSON.parse(outputsData) : outputsData;
                console.log('解析后的outputs:', outputs);
            } catch (error) {
                console.error('解析outputs参数数据失败:', error);
                outputs = [];
            }
        }
        
        // 如果没有数据，使用空数组
        this.inputs = inputs || [];
        this.outputs = outputs || [];
        
        console.log('设置后的this.inputs:', this.inputs);
        console.log('设置后的this.outputs:', this.outputs);
        
        this.renderParams();
    }

    loadInterfaceParams() {
        // 默认输入参数
        this.inputs = [
            { name: 'temperature', type: 'float', unit: '°C', desc: '环境温度' },
            { name: 'pressure', type: 'float', unit: 'kPa', desc: '压力值' },
            { name: 'flow_rate', type: 'float', unit: 'm³/h', desc: '流量' }
        ];

        // 默认输出参数
        this.outputs = [
            { name: 'control_signal', type: 'float', unit: '%', desc: '控制信号' },
            { name: 'status', type: 'int', unit: '-', desc: '状态码' },
            { name: 'efficiency', type: 'float', unit: '%', desc: '效率' }
        ];

        this.renderParams();
    }

    renderParams() {
        console.log('renderParams - this.inputs:', this.inputs);
        console.log('renderParams - this.outputs:', this.outputs);
        
        // 数据类型选项（与association-rules保持一致）
        const dataTypes = ['Boolean', 'Integer', 'Long', 'Float', 'Double', 'String'];
        
        // 常用物理单位
        const commonUnits = [
            '-', '°C', '°F', 'K', 'Pa', 'kPa', 'MPa', 'bar', 'atm',
            'm/s', 'km/h', 'm/s²', 'km/h²', 'g', 'kg', 't', 'lb',
            'm', 'km', 'cm', 'mm', 'in', 'ft', 'm²', 'km²', 'ha', 'acre',
            'm³', 'L', 'mL', 'gal', 'W', 'kW', 'MW', 'hp', 'V', 'kV', 'MV',
            'A', 'mA', 'kA', 'Hz', 'kHz', 'MHz', 's', 'min', 'h', 'day',
            '%', 'ppm', 'ppb', 'pH', 'lux', 'cd', 'lm', 'N', 'kN', 'MN'
        ];
        
        // 渲染输入参数
        const inputsBody = this.shadowRoot.getElementById('inputsBody');
        if (inputsBody) {
            if (!this.inputs || this.inputs.length === 0) {
                inputsBody.innerHTML = '<div class="empty-params">暂无输入参数</div>';
            } else {
                inputsBody.innerHTML = this.inputs.map((input, index) => `
                    <div class="param-row" data-index="${index}">
                        <div class="col-name">
                            <input type="text" value="${input.name || ''}" data-field="name" data-type="input" placeholder="参数名">
                        </div>
                        <div class="col-type">
                            <select data-field="type" data-type="input">
                                ${dataTypes.map(type => 
                                    `<option value="${type}" ${input.type === type ? 'selected' : ''}>${type}</option>`
                                ).join('')}
                            </select>
                        </div>
                        <div class="col-unit">
                            <select data-field="unit" data-type="input">
                                ${commonUnits.map(unit => 
                                    `<option value="${unit}" ${input.unit === unit ? 'selected' : ''}>${unit}</option>`
                                ).join('')}
                            </select>
                        </div>
                        <div class="col-bind">
                            <select class="data-field-select" data-index="${index}">
                                <option value="">请选择字段</option>
                            </select>
                        </div>
                        <div class="col-desc">
                            <input type="text" value="${input.desc || ''}" data-field="desc" data-type="input" placeholder="说明">
                        </div>
                        <div class="col-action">
                            <button class="delete-btn" data-index="${index}" data-type="input">删除</button>
                        </div>
                    </div>
                `).join('');
            }
        }

        // 渲染输出参数
        const outputsBody = this.shadowRoot.getElementById('outputsBody');
        if (outputsBody) {
            if (!this.outputs || this.outputs.length === 0) {
                outputsBody.innerHTML = '<div class="empty-params">暂无输出参数</div>';
            } else {
                outputsBody.innerHTML = this.outputs.map((output, index) => `
                    <div class="param-row" data-index="${index}">
                        <div class="col-name">
                            <input type="text" value="${output.name || ''}" data-field="name" data-type="output" placeholder="参数名">
                        </div>
                        <div class="col-type">
                            <select data-field="type" data-type="output">
                                ${dataTypes.map(type => 
                                    `<option value="${type}" ${output.type === type ? 'selected' : ''}>${type}</option>`
                                ).join('')}
                            </select>
                        </div>
                        <div class="col-unit">
                            <select data-field="unit" data-type="output">
                                ${commonUnits.map(unit => 
                                    `<option value="${unit}" ${output.unit === unit ? 'selected' : ''}>${unit}</option>`
                                ).join('')}
                            </select>
                        </div>
                        <div class="col-bind">
                            <input type="text" class="result-target-input" value="${output.bindTarget || output.name || ''}" data-index="${index}" placeholder="回写目标字段">
                        </div>
                        <div class="col-desc">
                            <input type="text" value="${output.desc || ''}" data-field="desc" data-type="output" placeholder="说明">
                        </div>
                        <div class="col-action">
                            <button class="delete-btn" data-index="${index}" data-type="output">删除</button>
                        </div>
                    </div>
                `).join('');
            }
        }

        // 绑定删除按钮事件
        this.bindDeleteEvents();

        // 刷新数据源字段下拉选项
        this.updateBindFieldOptions();
    }

    bindDeleteEvents() {
        const deleteBtns = this.shadowRoot.querySelectorAll('.delete-btn');
        deleteBtns.forEach(btn => {
            btn.addEventListener('click', (e) => {
                e.stopPropagation();
                const index = parseInt(e.target.dataset.index);
                const type = e.target.dataset.type;
                
                // 保存所有当前用户输入
                this.saveAllCurrentValues();
                
                // 删除参数
                if (type === 'input') {
                    this.inputs.splice(index, 1);
                } else {
                    this.outputs.splice(index, 1);
                }
                
                this.renderParams();
            });
        });
    }

    addInputParam() {
        // 保存所有当前用户输入（inputs和outputs）
        this.saveAllCurrentValues();
        
        // 添加新的空参数
        this.inputs.push({
            name: '',
            type: '',
            unit: '',
            desc: ''
        });
        
        this.renderParams();
    }

    addOutputParam() {
        // 保存所有当前用户输入（inputs和outputs）
        this.saveAllCurrentValues();
        
        // 添加新的空参数
        this.outputs.push({
            name: '',
            type: '',
            unit: '',
            desc: ''
        });
        
        this.renderParams();
    }
    
    saveAllCurrentValues() {
        this.saveCurrentInputValues();
        this.saveCurrentOutputValues();
    }
    
    saveCurrentInputValues() {
        const inputsBody = this.shadowRoot.getElementById('inputsBody');
        if (!inputsBody) return;
        
        // 只处理inputsBody内的param-row
        const inputRows = inputsBody.querySelectorAll('.param-row');
        inputRows.forEach(row => {
            const index = parseInt(row.dataset.index);
            if (this.inputs[index]) {
                const nameInput = row.querySelector('input[data-field="name"][data-type="input"]');
                const typeSelect = row.querySelector('select[data-field="type"][data-type="input"]');
                const unitSelect = row.querySelector('select[data-field="unit"][data-type="input"]');
                const descInput = row.querySelector('input[data-field="desc"][data-type="input"]');
                
                if (nameInput) this.inputs[index].name = nameInput.value;
                if (typeSelect) this.inputs[index].type = typeSelect.value;
                if (unitSelect) this.inputs[index].unit = unitSelect.value;
                if (descInput) this.inputs[index].desc = descInput.value;
                const bindSelect = row.querySelector('.data-field-select');
                if (bindSelect) this.inputs[index].bindField = bindSelect.value;
                
                console.log(`保存输入参数[${index}]:`, this.inputs[index]);
            }
        });
    }
    
    saveCurrentOutputValues() {
        const outputsBody = this.shadowRoot.getElementById('outputsBody');
        if (!outputsBody) return;
        
        // 只处理outputsBody内的param-row
        const outputRows = outputsBody.querySelectorAll('.param-row');
        outputRows.forEach(row => {
            const index = parseInt(row.dataset.index);
            if (this.outputs[index]) {
                const nameInput = row.querySelector('input[data-field="name"][data-type="output"]');
                const typeSelect = row.querySelector('select[data-field="type"][data-type="output"]');
                const unitSelect = row.querySelector('select[data-field="unit"][data-type="output"]');
                const descInput = row.querySelector('input[data-field="desc"][data-type="output"]');
                
                if (nameInput) this.outputs[index].name = nameInput.value;
                if (typeSelect) this.outputs[index].type = typeSelect.value;
                if (unitSelect) this.outputs[index].unit = unitSelect.value;
                if (descInput) this.outputs[index].desc = descInput.value;
                const bindInput = row.querySelector('.result-target-input');
                if (bindInput) this.outputs[index].bindTarget = bindInput.value;
                
                console.log(`保存输出参数[${index}]:`, this.outputs[index]);
            }
        });
    }

    async autoParseFromCode() {
        // 获取当前选择的配置
        const parseRulesSelect = this.shadowRoot.getElementById('parseRulesSelect');
        const sourceFileSelect = this.shadowRoot.getElementById('sourceFileSelect');
        const forceOverrideCheck = this.shadowRoot.getElementById('forceOverrideCheck');
        
        const selectedRule = parseRulesSelect?.value || '';
        const selectedFile = sourceFileSelect?.value || '';
        const forceOverride = forceOverrideCheck?.checked || false;
        
        if (!selectedRule) {
            this.showErrorMessage('请先选择解析规则');
            return;
        }
        
        try {
            // 获取解析规则配置
            const parsingRule = this.getParsingRuleConfig(selectedRule);
            
            if (!parsingRule || !parsingRule.pattern) {
                this.showErrorMessage('解析规则配置无效');
                return;
            }
            
            console.log('开始解析代码文件，使用解析规则:', parsingRule);
            
            // 获取算法名称和版本
            const algorithmName = this.currentAlgorithm?.name || this.currentAlgorithmMeta?.name;
            const version = this.currentAlgorithm?.version || this.currentAlgorithmMeta?.version;
            
            console.log('使用的参数 - algorithmName:', algorithmName, 'version:', version);
            
            if (!algorithmName || !version) {
                this.showErrorMessage('算法名称或版本为空，无法解析代码');
                return;
            }
            
            // 调用AlgorithmFileService的extractAlgorithmFile方法
            const extractResponse = await window.AppConfig.post('algorithm', 'extractAlgorithmFile', {
                name: algorithmName,
                version: version
            });
            
            if (!extractResponse.success) {
                this.showErrorMessage('提取算法文件失败: ' + extractResponse.message);
                return;
            }
            
            console.log('算法文件提取成功:', extractResponse.data);
            
            // 动态填充源文件下拉选择框（每次点击都重新加载）
            this.populateSourceFileSelect(extractResponse.data);
            
            // 如果没有选择文件，提示用户选择
            if (!selectedFile) {
                this.showErrorMessage('请从下拉列表中选择源文件');
                return;
            }
            
            // 执行代码分析
            const codeAnalysis = this.performRealCodeAnalysis(selectedFile, parsingRule, extractResponse.data);
            
            if (!codeAnalysis || (!codeAnalysis.inputs || codeAnalysis.inputs.length === 0) && (!codeAnalysis.outputs || codeAnalysis.outputs.length === 0)) {
                this.showErrorMessage('未解析到数据，请确认代码注释是否符合规范');
                return;
            }
            
            // 处理强制覆盖逻辑
            if (forceOverride) {
                // 强制覆盖：完全替换现有参数
                this.inputs = codeAnalysis.inputs || [];
                this.outputs = codeAnalysis.outputs || [];
                this.showSuccessMessage(`已强制覆盖解析结果（${this.inputs.length}个输入，${this.outputs.length}个输出）`);
            } else {
                // 非强制覆盖：只填充未输入的内容
                this.mergeParameters(codeAnalysis);
                this.showSuccessMessage(`已智能合并解析结果（保留已有内容，填充空白项）`);
            }
            
            this.renderParams();
            
        } catch (error) {
            console.error('代码解析失败:', error);
            this.showErrorMessage('代码解析失败: ' + error.message);
        }
    }
    
    getParsingRuleConfig(ruleType) {
        // 从下拉选择框获取选中的解析规则配置
        const parseRulesSelect = this.shadowRoot.getElementById('parseRulesSelect');
        if (parseRulesSelect) {
            const selectedOption = parseRulesSelect.querySelector(`option[value="${ruleType}"]`);
            if (selectedOption) {
                const regexPattern = selectedOption.dataset.regexPattern;
                if (regexPattern) {
                    return {
                        type: 'regex',
                        pattern: regexPattern,
                        pythonModule: '',
                        pythonFunction: ''
                    };
                }
            }
        }
        
        // 默认返回空配置
        return {
            type: 'regex',
            pattern: '',
            pythonModule: '',
            pythonFunction: ''
        };
    }
    
    performRealCodeAnalysis(sourceFile, parsingRule, extractedFiles) {
        console.log('开始真实代码分析:', sourceFile, parsingRule, extractedFiles);
        
        const results = {
            inputs: [],
            outputs: []
        };
        
        try {
            // 查找选择的源文件
            const fileInfo = extractedFiles.find(file => file.name === sourceFile || file.path?.includes(sourceFile));
            
            console.log('查找的源文件:', sourceFile);
            console.log('提取的文件列表:', extractedFiles);
            console.log('找到的文件信息:', fileInfo);
            
            if (!fileInfo) {
                console.warn('未找到源文件:', sourceFile);
                return results;
            }
            
            // 获取文件内容（这里假设文件内容已提取，实际可能需要读取临时文件）
            let fileContent = '';
            
            console.log('fileInfo.content存在?', !!fileInfo.content);
            console.log('fileInfo.path存在?', !!fileInfo.path);
            
            // 如果是文本文件内容直接使用
            if (fileInfo.content) {
                fileContent = fileInfo.content;
                console.log('使用文件内容，长度:', fileContent.length);
            } else if (fileInfo.path) {
                // 否则尝试从临时路径读取（这里简化处理）
                console.log('文件路径:', fileInfo.path);
                fileContent = this.getMockFileContent(sourceFile); // 临时使用mock内容
                console.log('使用mock内容，长度:', fileContent.length);
            } else {
                console.warn('文件信息中没有content和path字段');
                fileContent = this.getMockFileContent(sourceFile); // 临时使用mock内容
                console.log('强制使用mock内容，长度:', fileContent.length);
            }
            
            if (!fileContent) {
                console.warn('无法获取文件内容');
                return results;
            }
            
            console.log('完整文件内容:');
            console.log(fileContent);
            
            // 按行分割文件内容，只读取前50行
            const lines = fileContent.split('\n').slice(0, 50);
            console.log('读取文件前50行，总行数:', lines.length);
            
            // 输出前10行内容用于调试
            console.log('文件前10行内容:');
            lines.slice(0, 10).forEach((line, index) => {
                console.log(`第${index + 1}行: "${line}"`);
            });
            
            // 创建正则表达式对象
            const regex = new RegExp(parsingRule.pattern, 'gm');
            console.log('使用的正则表达式:', parsingRule.pattern);
            
            // 遍历每一行，用正则表达式匹配
            lines.forEach((line, index) => {
                const matches = [...line.matchAll(regex)];
                
                if (matches.length > 0) {
                    console.log(`第${index + 1}行匹配到 ${matches.length} 个结果:`, matches);
                }
                
                matches.forEach(match => {
                    console.log('匹配详情:', match);
                    
                    // 由于JavaScript的matchAll不直接支持命名捕获组，我们手动提取
                    if (match.length >= 5) {
                        const paramType = match[1];      // Input/Output
                        const paramName = match[2];     // speed/gear/power
                        const dataType = match[3];      // float/int
                        const description = match[4];   // 车速/档位/功率
                        
                        console.log('提取的组:', { paramType, paramName, dataType, description });
                        
                        if (paramName && dataType) {
                            const param = {
                                name: paramName.trim(),
                                type: this.normalizeDataType(dataType.trim()),
                                unit: this.extractUnit(dataType.trim()),
                                desc: (description || '').trim(),
                                line: index + 1
                            };
                            
                            console.log('解析到参数:', param);
                            
                            // 根据类型分类
                            if (paramType.toLowerCase().includes('input') || paramType.toLowerCase().includes('param')) {
                                results.inputs.push(param);
                            } else if (paramType.toLowerCase().includes('output') || paramType.toLowerCase().includes('return')) {
                                results.outputs.push(param);
                            }
                        } else {
                            console.warn('参数名或数据类型为空:', { paramName, dataType });
                        }
                    } else {
                        console.warn('匹配结果长度不足:', match);
                    }
                });
            });
            
            console.log('解析结果:', results);
            
        } catch (error) {
            console.error('真实代码分析失败:', error);
        }
        
        return results;
    }
    
    normalizeDataType(dataType) {
        console.log('normalizeDataType 输入:', dataType);
        
        // UI中的数据类型选项（与association-rules保持一致）
        const uiDataTypes = ['Boolean', 'Integer', 'Long', 'Float', 'Double', 'String'];
        
        // 标准化数据类型映射
        const typeMap = {
            'float': 'Float',
            'double': 'Double', 
            'int': 'Integer',
            'integer': 'Integer',
            'long': 'Long',
            'bool': 'Boolean',
            'boolean': 'Boolean',
            'string': 'String',
            'str': 'String',
            'vector': 'String',  // 向量暂用String表示
            'array': 'String'   // 数组暂用String表示
        };
        
        const cleanType = dataType.toLowerCase().replace(/[\[\]()]/g, '');
        
        // 首先尝试精确匹配
        let result = typeMap[cleanType];
        
        if (!result) {
            // 如果精确匹配失败，尝试不区分大小写的模糊匹配
            result = uiDataTypes.find(uiType => 
                uiType.toLowerCase() === cleanType
            );
        }
        
        // 如果还是没匹配到，使用默认值
        if (!result) {
            result = 'String';
            console.warn(`未知数据类型 "${dataType}"，使用默认值 String`);
        }
        
        console.log('normalizeDataType 输出:', result);
        return result;
    }
    
    extractUnit(dataType) {
        // 从数据类型中提取物理单位
        const unitMatch = dataType.match(/\[([^\]]+)\]/);
        return unitMatch ? unitMatch[1] : '';
    }
    
    getMockFileContent(fileName) {
        // 临时mock文件内容，实际应该从提取的文件读取
        const mockContents = {
            'algorithm.py': `# @Input: speed (float) - 车速
# @Input: gear (int) - 档位
# @Input: temperature (float) - 发动机温度
# @Output: power (float) - 功率
# @Output: torque (float) - 扭矩

def calculate_engine_performance():
    pass`,
            'control.m': `% @Input: reference (double) - 参考值
% @Input: feedback (double) - 反馈值
% @Output: control_signal (double) - 控制信号

function control_signal = pid_controller(reference, feedback)
    % Implementation here`,
            'processor.cpp': `/**
 * @param input_data (vector<double>) - 输入数据向量
 * @param threshold (double) - 阈值参数
 * @Output: result (int) - 处理结果
 */
int process_data() {
    // Implementation here
    return 0;
}`
        };
        
        return mockContents[fileName] || '';
    }
    
    async loadSourceFiles() {
        try {
            console.log('开始加载源文件列表...');
            console.log('当前算法信息:', this.currentAlgorithm);
            console.log('当前算法元数据:', this.currentAlgorithmMeta);
            
            // 获取算法名称和版本
            const algorithmName = this.currentAlgorithm?.name || this.currentAlgorithmMeta?.name;
            const version = this.currentAlgorithm?.version || this.currentAlgorithmMeta?.version;
            
            console.log('使用的参数 - algorithmName:', algorithmName, 'version:', version);
            
            if (!algorithmName || !version) {
                console.warn('算法名称或版本为空，跳过源文件加载');
                return;
            }
            
            // 调用AlgorithmFileService的extractAlgorithmFile方法
            const extractResponse = await window.AppConfig.post('algorithm', 'extractAlgorithmFile', {
                name: algorithmName,
                version: version
            });
            
            if (extractResponse.success) {
                console.log('源文件加载成功:', extractResponse.data);
                this.populateSourceFileSelect(extractResponse.data);
            } else {
                console.warn('加载源文件失败:', extractResponse.message);
                // 不显示错误消息，只是不填充下拉框
            }
        } catch (error) {
            console.error('加载源文件时发生错误:', error);
            // 不显示错误消息，只是不填充下拉框
        }
    }
    
    populateSourceFileSelect(extractedFiles) {
        const sourceFileSelect = this.shadowRoot.getElementById('sourceFileSelect');
        if (!sourceFileSelect) {
            console.warn('未找到源文件选择框');
            return;
        }
        
        // 保存当前选择
        const currentSelection = sourceFileSelect.value;
        console.log('保存当前选择:', currentSelection);
        
        // 清空现有选项
        sourceFileSelect.innerHTML = '<option value="">请选择源文件</option>';
        
        if (!extractedFiles || !Array.isArray(extractedFiles)) {
            console.warn('提取的文件数据无效:', extractedFiles);
            return;
        }
        
        // 过滤出代码文件（常见的代码文件扩展名）
        const codeExtensions = ['.py', '.m', '.cpp', '.c', '.h', '.java', '.js', '.ts', '.sh'];
        const codeFiles = extractedFiles.filter(file => {
            const fileName = file.name || file.path || '';
            return codeExtensions.some(ext => fileName.toLowerCase().endsWith(ext));
        });
        
        console.log('找到代码文件:', codeFiles);
        
        // 添加代码文件选项
        codeFiles.forEach(file => {
            const option = document.createElement('option');
            option.value = file.name || file.path;
            option.textContent = `${file.name || file.path} (${file.size || 'unknown'} bytes)`;
            sourceFileSelect.appendChild(option);
        });
        
        if (codeFiles.length === 0) {
            console.warn('未找到可解析的代码文件');
            const noFileOption = document.createElement('option');
            noFileOption.value = '';
            noFileOption.textContent = '未找到可解析的代码文件';
            noFileOption.disabled = true;
            sourceFileSelect.appendChild(noFileOption);
        }
        
        // 恢复之前的选择（如果还存在的话）
        if (currentSelection) {
            const optionExists = Array.from(sourceFileSelect.options).some(option => option.value === currentSelection);
            if (optionExists) {
                sourceFileSelect.value = currentSelection;
                console.log('恢复之前的选择:', currentSelection);
            } else {
                console.log('之前的选择不再可用:', currentSelection);
            }
        }
    }
    
    mergeParameters(codeAnalysis) {
        // 先保存当前用户输入
        this.saveAllCurrentValues();
        
        const mergeArray = (existing, parsed) => {
            const result = [...existing];
            
            parsed.forEach((parsedParam, index) => {
                // 查找是否已存在同名参数
                const existingIndex = result.findIndex(p => p.name === parsedParam.name);
                
                if (existingIndex >= 0) {
                    // 存在同名参数，检查是否需要更新
                    const existingParam = result[existingIndex];
                    let needsUpdate = false;
                    
                    // 检查每个字段是否为空，如果为空则填充
                    ['type', 'unit', 'desc'].forEach(field => {
                        if (!existingParam[field] || existingParam[field].trim() === '') {
                            existingParam[field] = parsedParam[field];
                            needsUpdate = true;
                        }
                    });
                    
                    // 如果所有字段都已填写，可以选择跳过或提示
                    if (!needsUpdate) {
                        console.log(`参数 ${parsedParam.name} 已完整填写，跳过更新`);
                    }
                } else {
                    // 不存在同名参数，直接添加
                    result.push(parsedParam);
                }
            });
            
            return result;
        };
        
        this.inputs = mergeArray(this.inputs, codeAnalysis.inputs || []);
        this.outputs = mergeArray(this.outputs, codeAnalysis.outputs || []);
    }
    
    async loadParsingRules() {
        console.log('开始加载解析规则...');
        const parseRulesSelect = this.shadowRoot.getElementById('parseRulesSelect');
        if (!parseRulesSelect) {
            console.warn('未找到parseRulesSelect元素');
            return;
        }
        
        // 清空现有选项
        parseRulesSelect.innerHTML = '';
        console.log('已清空现有选项');
        
        // 添加默认选项
        const defaultOption = document.createElement('option');
        defaultOption.value = '';
        defaultOption.textContent = '请选择解析规则';
        parseRulesSelect.appendChild(defaultOption);
        
        try {
            // 通过API动态查询解析规则
            console.log('正在调用API查询解析规则...');
            const response = await window.AppConfig.post('parsingRules', 'query', {
                pageNum: 1,
                pageSize: 100 // 获取所有规则
            });
            
            console.log('API响应:', response);
            
            if (response.success && response.data) {
                console.log('解析规则数据:', response.data);
                response.data.forEach(rule => {
                    const option = document.createElement('option');
                    option.value = rule.createTime; // 使用createTime作为唯一标识
                    option.textContent = rule.name;
                    option.dataset.regexPattern = rule.regexPattern || ''; // 存储正则表达式模式
                    option.dataset.example = rule.example || ''; // 存储example字段
                    parseRulesSelect.appendChild(option);
                    console.log('添加解析规则选项:', rule.name, rule.createTime);
                });
                
                console.log('已加载解析规则:', response.data.length, '个规则');
            } else {
                console.warn('加载解析规则失败:', response.message);
            }
        } catch (error) {
            console.error('加载解析规则时发生错误:', error);
        }
    }

    onParseRulesChange(value) {
        console.log('解析规则变更:', value);
        
        // 获取选中的解析规则
        const parseRulesSelect = this.shadowRoot.getElementById('parseRulesSelect');
        const selectedOption = parseRulesSelect?.querySelector(`option[value="${value}"]`);
        
        // 显示或隐藏注释规范区域
        const annotationSpecSection = this.shadowRoot.getElementById('annotationSpecSection');
        const specContent = this.shadowRoot.getElementById('specContent');
        
        if (selectedOption && value) {
            // 只有当有example字段时才显示注释规范区域
            const example = selectedOption.dataset.example || '';
            
            if (example) {
                annotationSpecSection.style.display = 'block';
                specContent.innerHTML = `<pre>${this.escapeHtml(example)}</pre>`;
            } else {
                annotationSpecSection.style.display = 'none';
            }
        } else {
            annotationSpecSection.style.display = 'none';
        }
        
        // 根据选择的规则调整解析逻辑
        this.applyParseRules(value);
    }
    
    navigateToParsingRules() {
        // 隐藏当前弹窗
        this.hide();
        // 调用全局函数显示parsing-rules组件
        if (typeof window.showComponent === 'function') {
            window.showComponent('parsingRules');
        } else {
            console.error('全局showComponent函数未找到');
        }
    }

    escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }

    onSourceFileChange(value) {
        console.log('源文件变更:', value);
        // 不显示提示信息，避免干扰用户
    }

    onForceOverrideChange(checked) {
        console.log('强制覆盖变更:', checked);
        // 根据是否强制覆盖调整行为
        if (checked) {
            this.forceOverrideDropdowns();
        }
    }

    forceOverrideDropdowns() {
        // 强制覆盖所有下拉选择为推荐值
        const recommendations = {
            temperature: { type: 'Double', unit: '°C', desc: '环境温度' },
            pressure: { type: 'Double', unit: 'kPa', desc: '压力值' },
            flow_rate: { type: 'Double', unit: 'm³/h', desc: '流量' },
            control_signal: { type: 'Double', unit: '%', desc: '控制信号' },
            status: { type: 'Integer', unit: '-', desc: '状态码' },
            efficiency: { type: 'Double', unit: '%', desc: '效率' }
        };

        // 更新输入参数
        this.inputs = this.inputs.map(input => {
            const rec = recommendations[input.name];
            if (rec) {
                return {
                    ...input,
                    type: rec.type,
                    unit: rec.unit,
                    desc: rec.desc
                };
            }
            return input;
        });

        // 更新输出参数
        this.outputs = this.outputs.map(output => {
            const rec = recommendations[output.name];
            if (rec) {
                return {
                    ...output,
                    type: rec.type,
                    unit: rec.unit,
                    desc: rec.desc
                };
            }
            return output;
        });

        this.renderParams();
    }

    applyParseRules(ruleType) {
        // 根据规则类型应用不同的解析规则
        // 不再显示提示信息，避免干扰用户
        console.log('已应用解析规则:', ruleType);
    }

    // === 数据绑定 ===

    async loadDataSourceOptions() {
        const dataSource = this.shadowRoot.getElementById('dataSource');
        if (!dataSource) return;
        try {
            const result = await window.AppConfig.get('dataSource', 'list', {});
            if (result.success && result.data) {
                dataSource.innerHTML = '<option value="">请选择数据源</option>';
                result.data.forEach(ds => {
                    const option = document.createElement('option');
                    option.value = ds.name || ds.tableName || ds;
                    option.textContent = ds.name || ds.tableName || ds;
                    dataSource.appendChild(option);
                });
            }
        } catch (e) {
            console.error('加载数据源列表失败:', e);
        }
    }

    async loadDataSourceFields() {
        const dataSource = this.shadowRoot.getElementById('dataSource')?.value;
        this._dataSourceFields = [];
        if (dataSource) {
            try {
                const result = await window.AppConfig.get('dataSource', 'fields', { tableName: dataSource });
                if (result.success && result.data) {
                    this._dataSourceFields = result.data;
                }
            } catch (e) {
                console.error('加载数据源字段失败:', e);
            }
        }
        this.updateBindFieldOptions();
    }

    getModelNames() {
        const modelNames = [];
        const rightSidebarTree = document.querySelector('.right-sidebar .tree');
        if (!rightSidebarTree) return modelNames;
        const seen = new Set();
        rightSidebarTree.querySelectorAll('.tree-node').forEach(node => {
            const span = node.querySelector('span');
            if (!span) return;
            const name = span.textContent.trim();
            if (name === 'models_system' || name === 'models' || seen.has(name)) return;
            const hasChildren = node.querySelector('.tree-children');
            if (hasChildren) {
                const childNodes = hasChildren.querySelectorAll(':scope > .tree-node');
                const hasLeaf = Array.from(childNodes).some(c => !c.querySelector('.tree-children'));
                if (hasLeaf) { modelNames.push(name); seen.add(name); }
            }
        });
        return modelNames;
    }

    getModelVersions(modelName) {
        const versions = [];
        const rightSidebarTree = document.querySelector('.right-sidebar .tree');
        if (!rightSidebarTree) return versions;
        rightSidebarTree.querySelectorAll('.tree-node').forEach(node => {
            const span = node.querySelector('span');
            if (!span || span.textContent.trim() !== modelName) return;
            const children = node.querySelector('.tree-children');
            if (!children) return;
            children.querySelectorAll(':scope > .tree-node').forEach(child => {
                const childSpan = child.querySelector('span');
                if (childSpan && !child.querySelector('.tree-children')) {
                    versions.push(childSpan.textContent.trim());
                }
            });
        });
        return versions;
    }

    addModelBindRow(data = null) {
        const modelBindList = this.shadowRoot.getElementById('modelBindList');
        if (!modelBindList) return;

        const row = document.createElement('div');
        row.className = 'model-bind-row';

        const modelNames = this.getModelNames();
        const selectedModel = data?.modelName || '';
        const versions = selectedModel ? this.getModelVersions(selectedModel) : [];

        row.innerHTML = `
            <select class="model-bind-name">
                <option value="">请选择模型</option>
                ${modelNames.map(n => `<option value="${n}" ${n === selectedModel ? 'selected' : ''}>${n}</option>`).join('')}
            </select>
            <select class="model-bind-version">
                <option value="">请选择版本</option>
                ${versions.map(v => `<option value="${v}" ${v === data?.version ? 'selected' : ''}>${v}</option>`).join('')}
            </select>
            <button type="button" class="remove-model-bind">×</button>
        `;

        const nameSelect = row.querySelector('.model-bind-name');
        const versionSelect = row.querySelector('.model-bind-version');
        nameSelect.addEventListener('change', () => {
            const vers = this.getModelVersions(nameSelect.value);
            versionSelect.innerHTML = '<option value="">请选择版本</option>' +
                vers.map(v => `<option value="${v}">${v}</option>`).join('');
        });
        row.querySelector('.remove-model-bind').addEventListener('click', () => row.remove());

        modelBindList.appendChild(row);
    }

    getModelBindings() {
        const bindings = [];
        this.shadowRoot.querySelectorAll('#modelBindList .model-bind-row').forEach(row => {
            const modelName = row.querySelector('.model-bind-name')?.value;
            const version = row.querySelector('.model-bind-version')?.value;
            if (modelName) bindings.push({ modelName, version: version || '' });
        });
        return bindings;
    }

    generateCsvHeader() {
        this.saveAllCurrentValues();
        const headers = this.outputs.map(o => o.bindTarget || o.name || '').filter(h => h);
        const outputCsvName = this.shadowRoot.getElementById('outputCsvName');
        if (outputCsvName && headers.length > 0) {
            // Just show a toast/preview of the CSV header, not overwrite the filename
            const headerLine = headers.join(',');
            // Show as a temporary message
            const existing = outputCsvName.value;
            if (!existing) {
                outputCsvName.value = 'result.csv';
            }
            alert('CSV表头预览:\n' + headerLine);
        } else if (headers.length === 0) {
            alert('请先添加输出参数');
        }
    }

    updateBindFieldOptions() {
        const fields = this._dataSourceFields || [];
        // 更新输入参数表中的数据源字段下拉
        this.shadowRoot.querySelectorAll('.data-field-select').forEach(select => {
            const current = select.value;
            select.innerHTML = '<option value="">请选择字段</option>';
            fields.forEach(f => {
                const name = f.name || f.fieldName || f;
                const option = document.createElement('option');
                option.value = name;
                option.textContent = name;
                select.appendChild(option);
            });
            if (current) select.value = current;
        });
    }

    async loadBindingData(algorithmInfo) {
        // 加载数据源选项
        await this.loadDataSourceOptions();

        // 从关联规则API加载绑定数据
        try {
            const result = await window.AppConfig.post('associationRules', 'query', {
                pageNum: 1,
                pageSize: 100,
                algorithmName: algorithmInfo.name || algorithmInfo.author,
                algorithmVersion: algorithmInfo.version
            });
            if (result.success && result.data && result.data.length > 0) {
                // Use first rule for data binding config (dataSource, cmd, csv)
                const firstRule = result.data[0];
                const dataSource = this.shadowRoot.getElementById('dataSource');
                const ruleCmd = this.shadowRoot.getElementById('ruleCmd');
                const inputCsvName = this.shadowRoot.getElementById('inputCsvName');
                const outputCsvName = this.shadowRoot.getElementById('outputCsvName');

                if (dataSource) dataSource.value = firstRule.tableName || '';
                if (firstRule.tableName) await this.loadDataSourceFields();
                if (ruleCmd) ruleCmd.value = firstRule.cmd || '';
                if (inputCsvName) inputCsvName.value = firstRule.inputCsvName || '';
                if (outputCsvName) outputCsvName.value = firstRule.outputCsvName || '';

                // Load model bindings from all rules (each rule = one model binding)
                const modelBindList = this.shadowRoot.getElementById('modelBindList');
                if (modelBindList) modelBindList.innerHTML = '';
                result.data.forEach(rule => {
                    if (rule.algorithmName) {
                        this.addModelBindRow({ modelName: rule.algorithmName, version: rule.algorithmVersion || '' });
                    }
                });

                // Apply input/output mappings from first rule
                if (firstRule.inputsBind) {
                    try {
                        const mappings = typeof firstRule.inputsBind === 'string' ? JSON.parse(firstRule.inputsBind) : firstRule.inputsBind;
                        this._inputMappings = mappings;
                        this.applyInputMappings();
                    } catch (e) { this._inputMappings = []; }
                }
                if (firstRule.outputsBind) {
                    try {
                        const resultMappings = typeof firstRule.outputsBind === 'string' ? JSON.parse(firstRule.outputsBind) : firstRule.outputsBind;
                        this._outputMappings = resultMappings;
                        this.applyOutputMappings();
                    } catch (e) { this._outputMappings = []; }
                }
            }
        } catch (error) {
            console.error('加载绑定数据失败:', error);
        }
    }

    applyInputMappings() {
        if (!this._inputMappings) return;
        this._inputMappings.forEach(mapping => {
            const paramName = mapping.targetField;
            const rows = this.shadowRoot.querySelectorAll('#inputsBody .param-row');
            rows.forEach(row => {
                const nameInput = row.querySelector('input[data-field="name"]');
                if (nameInput && nameInput.value === paramName) {
                    const bindSelect = row.querySelector('.data-field-select');
                    if (bindSelect) bindSelect.value = mapping.sourceField || '';
                }
            });
        });
    }

    applyOutputMappings() {
        if (!this._outputMappings) return;
        this._outputMappings.forEach(mapping => {
            const paramName = mapping.modelOutput;
            const rows = this.shadowRoot.querySelectorAll('#outputsBody .param-row');
            rows.forEach(row => {
                const nameInput = row.querySelector('input[data-field="name"]');
                if (nameInput && nameInput.value === paramName) {
                    const bindInput = row.querySelector('.result-target-input');
                    if (bindInput) bindInput.value = mapping.resultTarget || '';
                }
            });
        });
    }

    getInputMappings() {
        const mappings = [];
        const rows = this.shadowRoot.querySelectorAll('#inputsBody .param-row');
        rows.forEach(row => {
            const paramName = row.querySelector('input[data-field="name"]')?.value;
            const sourceField = row.querySelector('.data-field-select')?.value;
            if (paramName && sourceField) {
                mappings.push({ sourceField, targetField: paramName });
            }
        });
        return mappings;
    }

    getOutputMappings() {
        const mappings = [];
        const rows = this.shadowRoot.querySelectorAll('#outputsBody .param-row');
        rows.forEach(row => {
            const paramName = row.querySelector('input[data-field="name"]')?.value;
            const resultTarget = row.querySelector('.result-target-input')?.value;
            if (paramName && resultTarget) {
                mappings.push({ modelOutput: paramName, resultTarget });
            }
        });
        return mappings;
    }

    // === 输出格式预览 ===
    refreshPreview() {
        const outputFormat = this.shadowRoot.getElementById('outputFormat')?.value || '';
        const previewContent = this.shadowRoot.getElementById('previewContent');
        if (!previewContent) return;

        if (!outputFormat.trim()) {
            previewContent.innerHTML = '<pre>请先填写输出格式模板</pre>';
            return;
        }

        // 收集当前数据用于预览
        const algorithmName = this.shadowRoot.getElementById('algorithmName')?.value || '';
        const version = this.shadowRoot.getElementById('version')?.value || '';
        const developer = this.shadowRoot.getElementById('developer')?.value || '';
        const scene = this.shadowRoot.getElementById('scene')?.value || '';
        const description = this.shadowRoot.getElementById('description')?.value || '';

        // 保存当前参数值
        this.saveAllCurrentValues();

        // 构建变量映射
        const context = {
            name: algorithmName,
            version: version,
            author: developer,
            scene: scene,
            description: description
        };

        // 添加输入参数
        this.inputs.forEach((input, i) => {
            context[`input.${input.name}`] = `${input.name}(${input.type}${input.unit ? ' ' + input.unit : ''})`;
            context[`input.${i}.name`] = input.name;
            context[`input.${i}.type`] = input.type;
            context[`input.${i}.unit`] = input.unit;
            context[`input.${i}.desc`] = input.desc;
        });

        // 添加输出参数
        this.outputs.forEach((output, i) => {
            context[`output.${output.name}`] = `${output.name}(${output.type}${output.unit ? ' ' + output.unit : ''})`;
            context[`output.${i}.name`] = output.name;
            context[`output.${i}.type`] = output.type;
            context[`output.${i}.unit`] = output.unit;
            context[`output.${i}.desc`] = output.desc;
        });

        // 替换模板变量 {{xxx}}
        let result = outputFormat;
        result = result.replace(/\{\{([^}]+)\}\}/g, (match, key) => {
            const trimmedKey = key.trim();
            return context[trimmedKey] !== undefined ? context[trimmedKey] : match;
        });

        previewContent.innerHTML = `<pre>${this.escapeHtml(result)}</pre>`;
    }

    escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }

    collectFormData() {
        // 收集基本信息
        const algorithmName = this.shadowRoot.getElementById('algorithmName').value.trim();
        const developer = this.shadowRoot.getElementById('developer').value.trim();
        const version = this.shadowRoot.getElementById('version').value.trim();
        const scene = this.shadowRoot.getElementById('scene').value.trim();

        // 收集输入参数
        const inputElements = this.shadowRoot.querySelectorAll('input[data-type="input"], select[data-type="input"]');
        const inputsData = [];
        let currentInput = {};
        
        inputElements.forEach(element => {
            const field = element.dataset.field;
            const value = element.value.trim();
            
            if (field === 'name') {
                if (currentInput.name) {
                    inputsData.push({...currentInput});
                }
                currentInput = { name: value };
            } else {
                currentInput[field] = value;
            }
        });
        
        if (currentInput.name) {
            inputsData.push({...currentInput});
        }

        // 收集输出参数
        const outputElements = this.shadowRoot.querySelectorAll('input[data-type="output"], select[data-type="output"]');
        const outputsData = [];
        let currentOutput = {};
        
        outputElements.forEach(element => {
            const field = element.dataset.field;
            const value = element.value.trim();
            
            if (field === 'name') {
                if (currentOutput.name) {
                    outputsData.push({...currentOutput});
                }
                currentOutput = { name: value };
            } else {
                currentOutput[field] = value;
            }
        });
        
        if (currentOutput.name) {
            outputsData.push({...currentOutput});
        }

        // 构建完整的表单数据对象，包含AlgorithmFileService.saveAlgorithmMetadata需要的所有字段
        const formData = {
            name: algorithmName,
            version: version,
            fileName: this.currentAlgorithmMeta?.fileName || '',
            fileSize: this.currentAlgorithmMeta?.fileSize || 0,
            chunkCount: this.currentAlgorithmMeta?.chunkCount || 0,
            storagePath: this.currentAlgorithmMeta?.storagePath || '',
            fileMd5: this.currentAlgorithmMeta?.fileMd5 || '',
            author: developer,
            scene: scene,
            inputs: JSON.stringify(inputsData),
            outputs: JSON.stringify(outputsData),
            timestamp: this.currentAlgorithmMeta?.timestamp || Date.now(),
            projectName: this.currentAlgorithmMeta?.projectName || '',
            description: this.shadowRoot.getElementById('description')?.value?.trim() || '',
            outputFormat: this.shadowRoot.getElementById('outputFormat')?.value?.trim() || '',
            dataSource: this.shadowRoot.getElementById('dataSource')?.value || '',
            modelBindings: JSON.stringify(this.getModelBindings()),
            cmd: this.shadowRoot.getElementById('ruleCmd')?.value?.trim() || '',
            inputCsvName: this.shadowRoot.getElementById('inputCsvName')?.value?.trim() || '',
            outputCsvName: this.shadowRoot.getElementById('outputCsvName')?.value?.trim() || '',
            inputsBind: JSON.stringify(this.getInputMappings()),
            outputsBind: JSON.stringify(this.getOutputMappings())
        };

        return formData;
    }

    validateParameterNames(formData) {
        try {
            // 解析inputs和outputs数据
            let inputs = [];
            let outputs = [];
            
            if (formData.inputs) {
                inputs = typeof formData.inputs === 'string' ? JSON.parse(formData.inputs) : formData.inputs;
            }
            
            if (formData.outputs) {
                outputs = typeof formData.outputs === 'string' ? JSON.parse(formData.outputs) : formData.outputs;
            }
            
            // 过滤出有参数名的项
            const inputNames = inputs
                .filter(input => input.name && input.name.trim())
                .map(input => input.name.trim());
            
            const outputNames = outputs
                .filter(output => output.name && output.name.trim())
                .map(output => output.name.trim());
            
            // 检查inputs内部是否有重复
            const inputDuplicates = this.findDuplicates(inputNames);
            if (inputDuplicates.length > 0) {
                return {
                    valid: false,
                    message: `输入参数中存在重复的参数名: ${inputDuplicates.join(', ')}`
                };
            }
            
            // 检查outputs内部是否有重复
            const outputDuplicates = this.findDuplicates(outputNames);
            if (outputDuplicates.length > 0) {
                return {
                    valid: false,
                    message: `输出参数中存在重复的参数名: ${outputDuplicates.join(', ')}`
                };
            }
            
            return { valid: true };
            
        } catch (error) {
            console.error('验证参数名时发生错误:', error);
            return {
                valid: false,
                message: '参数名验证失败，请检查参数格式'
            };
        }
    }

    findDuplicates(array) {
        const duplicates = [];
        const seen = new Set();
        
        for (const item of array) {
            if (seen.has(item)) {
                if (!duplicates.includes(item)) {
                    duplicates.push(item);
                }
            } else {
                seen.add(item);
            }
        }
        
        return duplicates;
    }

    async save() {
        try {
            const formData = this.collectFormData();
            
            // 验证必填字段
            if (!formData.name) {
                this.showErrorMessage('请输入算法名称');
                return;
            }
            
            if (!formData.version) {
                this.showErrorMessage('请输入版本号');
                return;
            }

            // 验证参数名重复
            const duplicateValidation = this.validateParameterNames(formData);
            if (!duplicateValidation.valid) {
                this.showErrorMessage(duplicateValidation.message);
                return;
            }

            console.log('保存算法数据:', formData);

            // 使用新的API配置
            const result = await window.AppConfig.post('algorithm', 'metas', formData);
            
            console.log('保存响应:', result);
            
            if (result.success) {
                this.showSuccessMessage('元数据保存成功');
                this.hide();
                
                // 重新加载右侧算法资产库
                console.log('🔄 算法编辑成功，准备调用 loadDataSourceTree');
                if (window.loadDataSourceTree) {
                    console.log('🔄 调用 window.loadDataSourceTree');
                    window.loadDataSourceTree();
                } else {
                    console.error('❌ window.loadDataSourceTree 不存在');
                }
                
                // 通知算法详情页面刷新数据
                this.dispatchEvent(new CustomEvent('algorithm-updated', {
                    detail: { 
                        algorithmName: formData.name,
                        version: formData.version,
                        formData: formData
                    },
                    bubbles: true,
                    composed: true
                }));
                
                // 刷新右侧树（如果需要）
                this.refreshAlgorithmTree();
            } else {
                this.showErrorMessage(result.message || '保存失败');
                }
        } catch (error) {
            console.error('保存元数据失败:', error);
            this.showErrorMessage('保存失败，请稍后重试');
        }
    }

    refreshAlgorithmTree() {
        // 这里可以添加刷新右侧树的逻辑
        console.log('刷新算法树');
    }

    showSuccessMessage(message) {
        if (window.CommonUtils && window.CommonUtils.showToast) {
            window.CommonUtils.showToast(message, 'success');
        } else {
            // 回退到原有的实现
            const messageHtml = `
                <div class="workspace-message success" style="
                    position: fixed;
                    top: 20px;
                    right: 20px;
                    background: #10b981;
                    color: white;
                    padding: 12px 20px;
                    border-radius: 4px;
                    box-shadow: 0 4px 12px rgba(16, 185, 129, 0.3);
                    z-index: 10001;
                ">
                    ${message}
                </div>
            `;
            
            document.body.insertAdjacentHTML('beforeend', messageHtml);
            
            const messageEl = document.querySelector('.workspace-message.success');
            setTimeout(() => {
                if (messageEl) messageEl.remove();
            }, 3000);
        }
    }

    showErrorMessage(message) {
        if (window.CommonUtils && window.CommonUtils.showToast) {
            window.CommonUtils.showToast(message, 'error');
        } else {
            // 回退到原有的实现
            const messageHtml = `
                <div class="workspace-message error" style="
                    position: fixed;
                    top: 20px;
                    right: 20px;
                    background: #ef4444;
                    color: white;
                    padding: 12px 20px;
                    border-radius: 4px;
                    box-shadow: 0 4px 12px rgba(239, 68, 68, 0.3);
                    z-index: 10001;
                ">
                    ${message}
                </div>
            `;
            
            document.body.insertAdjacentHTML('beforeend', messageHtml);
            
            const messageEl = document.querySelector('.workspace-message.error');
            setTimeout(() => {
                if (messageEl) messageEl.remove();
            }, 3000);
        }
    }
}

customElements.define('algorithm-edit', AlgorithmEdit);
