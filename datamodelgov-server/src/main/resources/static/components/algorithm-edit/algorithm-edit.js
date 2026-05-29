class AlgorithmEdit extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });
        this.currentAlgorithm = null;
        this.inputs = [];
        this.outputs = [];
        this._dataSourceFields = [];
        this._modelBindings = [];
        this.parsingRulesData = [];
        this.extractedFileList = [];
        this.cachedDataSourceData = null;
        this.dataSourceEventBound = false;
        this._isInitializingEdit = false;
        this.dataSourceFieldTypes = new Map();
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

        // 添加模型绑定按钮
        const addModelBindBtn = this.shadowRoot.getElementById('addModelBindBtn');
        if (addModelBindBtn) {
            addModelBindBtn.addEventListener('click', () => this.addModelBindRow());
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

        if (descriptionInput) descriptionInput.value = algorithmDetailData.description || '';

        // 使用接口返回的inputs和outputs数据
        this.loadInterfaceParamsFromData(algorithmDetailData.inputs, algorithmDetailData.outputs);

        // 加载关联绑定数据
        this.loadBindingData(algorithmInfo);

        // 自动填充运行命令和CSV文件名（根据当前算法元数据）
        this.autoFillCommandAndCsvFields();

        // 加载结果回写路径前缀
        const outputTableInput = this.shadowRoot.getElementById('outputTable');
        if (outputTableInput) outputTableInput.value = algorithmDetailData.outputTable || '';
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

        if (descriptionInput) descriptionInput.value = this.currentAlgorithmMeta?.description || '';

        // 加载接口参数（使用从API获取的数据）
        if (this.currentAlgorithmMeta && this.currentAlgorithmMeta.inputs) {
            this.loadInterfaceParamsFromData(this.currentAlgorithmMeta.inputs, this.currentAlgorithmMeta.outputs);
        } else {
            // 如果没有数据，使用默认参数
            this.loadInterfaceParams();
        }

        // 加载关联绑定数据
        this.loadBindingData(algorithmInfo);

        // 自动填充运行命令和CSV文件名
        this.autoFillCommandAndCsvFields();

        // 加载结果回写路径前缀
        const outputTableInput = this.shadowRoot.getElementById('outputTable');
        if (outputTableInput) outputTableInput.value = this.currentAlgorithmMeta?.outputTable || '';
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
                            <select class="data-field-select" data-index="${index}" data-bind-field="${input.bindField || ''}">
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
        const parseRulesSelect = this.shadowRoot.getElementById('parseRulesSelect');
        const sourceFileSelect = this.shadowRoot.getElementById('sourceFileSelect');
        const forceOverrideCheck = this.shadowRoot.getElementById('forceOverrideCheck');

        const selectedRuleId = parseRulesSelect?.value || '';
        const selectedFile = sourceFileSelect?.value || '';
        const forceOverride = forceOverrideCheck?.checked || false;

        if (!selectedRuleId) {
            this.showErrorMessage('请先选择解析规则');
            return;
        }

        if (!selectedFile) {
            this.showErrorMessage('请从下拉列表中选择源文件');
            return;
        }

        try {
            // 获取解析规则配置
            const ruleData = this.parsingRulesData.find(r => String(r.createTime) === String(selectedRuleId));
            const parseType = ruleData?.parseType || 'regex';
            const regexPattern = ruleData?.regexPattern || '';
            const pythonModule = ruleData?.pythonModule || '';
            const pythonFunction = ruleData?.pythonFunction || '';

            // 获取算法名称和版本
            const algorithmName = this.currentAlgorithm?.name || this.currentAlgorithmMeta?.name;
            const version = this.currentAlgorithm?.version || this.currentAlgorithmMeta?.version;

            if (!algorithmName || !version) {
                this.showErrorMessage('算法名称或版本为空，无法解析代码');
                return;
            }

            // 从fileList中查找目标文件内容
            const targetFile = (this.extractedFileList || []).find(f => {
                const path = f.path || '';
                const name = f.name || '';
                return selectedFile === path || selectedFile === name || path.endsWith(selectedFile);
            });

            if (!targetFile || !targetFile.content) {
                this.showErrorMessage('未找到文件内容: ' + selectedFile);
                return;
            }

            // 调用后端autoParse端点
            if (window.showGlobalLoading) window.showGlobalLoading('正在解析代码...');

            const parseResponse = await window.AppConfig.post('parsingRules', 'autoParse', {
                fileContent: targetFile.content,
                fileName: targetFile.name,
                parseType: parseType,
                regexPattern: regexPattern,
                pythonModule: pythonModule,
                pythonFunction: pythonFunction,
                maxLines: 50
            });

            if (window.hideGlobalLoading) window.hideGlobalLoading();

            console.log('解析响应:', parseResponse);

            if (!parseResponse.success || !parseResponse.data) {
                this.showErrorMessage('代码解析失败: ' + (parseResponse.message || '未知错误'));
                return;
            }

            const parseResult = parseResponse.data;
            console.log('解析结果数据:', parseResult);

            const parsedApis = parseResult.apis || [];

            if (parsedApis.length === 0) {
                this.showErrorMessage('未解析到数据，请确认代码注释是否符合规范');
                return;
            }

            // 从第一个 API 获取 inputs/outputs（与模型编辑保持一致）
            const firstApi = parsedApis[0];
            const parsedInputs = (firstApi.inputs || []).map(p => ({
                name: p.name || '',
                type: this.normalizeDataType(p.type || ''),
                unit: p.unit || '',
                desc: p.desc || ''
            }));
            const parsedOutputs = (firstApi.outputs || []).map(p => ({
                name: p.name || '',
                type: this.normalizeDataType(p.type || ''),
                unit: p.unit || '',
                desc: p.desc || ''
            }));

            console.log('解析到的输入参数:', parsedInputs);
            console.log('解析到的输出参数:', parsedOutputs);

            // 处理强制覆盖逻辑
            if (forceOverride) {
                // 强制覆盖：完全替换现有参数
                this.inputs = parsedInputs;
                this.outputs = parsedOutputs;
                this.showSuccessMessage(`已强制覆盖解析结果（${this.inputs.length}个输入，${this.outputs.length}个输出）`);
            } else {
                // 非强制覆盖：只填充未输入的内容
                this.mergeParameters({ inputs: parsedInputs, outputs: parsedOutputs });
                this.showSuccessMessage(`已智能合并解析结果（保留已有内容，填充空白项）`);
            }

            this.renderParams();

            // 自动刷新CSV预览
            this.refreshPreview();

        } catch (error) {
            console.error('代码解析失败:', error);
            this.showErrorMessage('代码解析失败: ' + error.message);
        }
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

    // 自动填充运行命令和CSV文件名（根据当前算法元数据）
    async autoFillCommandAndCsvFields() {
        try {
            // 获取当前算法名称和版本
            const algorithmName = this.currentAlgorithm?.name || this.currentAlgorithmMeta?.name;
            const version = this.currentAlgorithm?.version || this.currentAlgorithmMeta?.version;

            if (!algorithmName || !version) {
                console.warn('算法名称或版本为空，无法自动填充');
                return;
            }

            console.log('自动填充运行命令和CSV文件名:', algorithmName, version);

            // 调用算法元数据API获取fileName
            const result = await window.AppConfig.get('algorithm', 'metas', { name: algorithmName, version: version });

            if (result.success && result.data) {
                const algorithmData = result.data;
                console.log('获取算法元数据成功:', algorithmData);

                // 获取fileName，如果没有则使用algorithmName作为默认值
                const fileName = algorithmData.fileName || `${algorithmName}.py`;
                console.log('使用fileName:', fileName);

                // 自动填充运行命令（仅在字段为空时填充）
                const ruleCmd = this.shadowRoot.getElementById('ruleCmd');
                if (ruleCmd && !ruleCmd.value) {
                    // 判断文件类型，生成对应的运行命令
                    let command;
                    if (fileName.endsWith('.m')) {
                        command = 'matlab';
                    } else if (fileName.endsWith('.py')) {
                        command = 'python';
                    } else {
                        // C/C++ 可执行文件或其他类型，直接执行
                        command = '';
                    }
                    ruleCmd.value = command ? `${command} ${fileName} -i input.csv -o output.csv` : `${fileName} -i input.csv -o output.csv`;
                    console.log('自动填充运行命令:', ruleCmd.value);
                }

                // 自动填充输入CSV文件名（仅在字段为空时填充）
                const inputCsvName = this.shadowRoot.getElementById('inputCsvName');
                if (inputCsvName && !inputCsvName.value) {
                    inputCsvName.value = 'input.csv';
                    console.log('自动填充输入CSV文件名:', inputCsvName.value);
                }

                // 自动填充输出CSV文件名（仅在字段为空时填充）
                const outputCsvName = this.shadowRoot.getElementById('outputCsvName');
                if (outputCsvName && !outputCsvName.value) {
                    outputCsvName.value = 'output.csv';
                    console.log('自动填充输出CSV文件名:', outputCsvName.value);
                }
            }
        } catch (error) {
            console.error('自动填充运行命令和CSV文件名失败:', error);
        }
    }

    // 清空自动填充的字段
    clearAutoFilledFields() {
        // 清空运行命令
        const ruleCmd = this.shadowRoot.getElementById('ruleCmd');
        if (ruleCmd) {
            ruleCmd.value = '';
        }

        // 清空输入CSV文件名
        const inputCsvName = this.shadowRoot.getElementById('inputCsvName');
        if (inputCsvName) {
            inputCsvName.value = '';
        }

        // 清空输出CSV文件名
        const outputCsvName = this.shadowRoot.getElementById('outputCsvName');
        if (outputCsvName) {
            outputCsvName.value = '';
        }

        console.log('已清空自动填充的字段');
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

            // 调用extractAlgorithmFile接口获取文件列表
            const extractResponse = await window.AppConfig.post('algorithm', 'extractAlgorithmFile', {
                name: algorithmName,
                version: version
            });

            if (extractResponse.success) {
                // 保存fileList供autoParse使用
                this.extractedFileList = extractResponse.data || [];
                console.log('源文件加载成功:', extractResponse.data);
                this.populateSourceFileSelect(this.extractedFileList);
            } else {
                console.warn('加载源文件失败:', extractResponse.message);
            }
        } catch (error) {
            console.error('加载源文件时发生错误:', error);
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
                this.parsingRulesData = response.data;
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

        // 调用tree接口获取数据源数据（与association-rules保持一致）
        try {
            const data = await window.AppConfig.get('datasource', 'tree');
            if (!data || !data.data) {
                console.warn('未获取到数据源树数据');
                return;
            }

            // 缓存数据供后续使用
            this.cachedDataSourceData = data.data;

            const tableNames = new Set();

            // 处理扁平的路径列表数据
            data.data.forEach(item => {
                if (item.path) {
                    // 过滤掉算法系统和模型系统的路径
                    if (!item.path.startsWith('algorithms_system.') && !item.path.startsWith('models_system.')) {
                        // 提取表名（最后一部分）
                        const parts = item.path.split('.');
                        const tableName = parts[parts.length - 1];
                        // 提取表路径（去掉字段名）
                        const tablePath = parts.slice(0, -1).join('.');
                        tableNames.add(tablePath);
                    }
                }
            });

            console.log('获取到的数据源表名:', Array.from(tableNames));

            // 清空现有选项
            dataSource.innerHTML = '<option value="">请选择数据源</option>';

            // 添加表名选项
            Array.from(tableNames).forEach(tableName => {
                const option = document.createElement('option');
                option.value = tableName;
                option.textContent = tableName;
                dataSource.appendChild(option);
            });

            // 监听数据源变化，加载字段
            if (!this.dataSourceEventBound) {
                dataSource.addEventListener('change', () => {
                    this.loadDataSourceFields(dataSource.value);
                });
                this.dataSourceEventBound = true;
            }
        } catch (error) {
            console.error('加载数据源列表失败:', error);
        }
    }

    async loadDataSourceFields() {
        const dataSource = this.shadowRoot.getElementById('dataSource')?.value;
        this._dataSourceFields = [];

        if (!dataSource) {
            this.updateBindFieldOptions();
            return;
        }

        console.log('加载表字段:', dataSource);

        // 使用缓存的数据源数据（与association-rules保持一致）
        if (!this.cachedDataSourceData) {
            console.warn('数据源数据未缓存，请先加载数据源选项');
            return;
        }

        const fields = new Map();

        // 处理扁平的路径列表数据，提取字段
        this.cachedDataSourceData.forEach(item => {
            if (item.path) {
                // 过滤掉算法系统和模型系统的路径
                if (!item.path.startsWith('algorithms_system.') && !item.path.startsWith('models_system.')) {
                    // 提取表路径和字段名
                    const parts = item.path.split('.');
                    const fieldPath = parts.slice(0, -1).join('.');
                    const fieldName = parts[parts.length - 1];

                    // 如果表路径匹配选择的表名，添加字段
                    if (fieldPath === dataSource) {
                        fields.set(fieldName, item.dataType);
                    }
                }
            }
        });

        console.log('获取到的字段和类型代码:', Array.from(fields.entries()));

        // 存储字段类型信息供验证使用
        this.dataSourceFieldTypes = fields;

        // 转换为数组格式
        this._dataSourceFields = Array.from(fields.entries()).map(([name, typeCode]) => ({
            name: name,
            dataType: typeCode,
            readableType: this.convertDataTypeCode(typeCode)
        }));

        console.log('设置_dataSourceFields:', this._dataSourceFields);

        // 更新绑定字段选项
        this.updateBindFieldOptions();
    }

    getModelNames() {
        const modelNames = [];
        // 从模型树获取数据，而不是算法树
        const modelTree = document.getElementById('modelTree');
        if (!modelTree) {
            console.warn('未找到模型树');
            return modelNames;
        }
        const seen = new Set();
        modelTree.querySelectorAll('.tree-node').forEach(node => {
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
        // 从模型树获取数据，而不是右侧边栏树
        const modelTree = document.getElementById('modelTree');
        if (!modelTree) return versions;
        modelTree.querySelectorAll('.tree-node').forEach(node => {
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

        // 如果是手动添加（没有传入data），清除初始化标志
        if (!data) {
            this._isInitializingEdit = false;
        }

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
        versionSelect.addEventListener('change', () => {
            if (!this._isInitializingEdit) {
                this.loadModelStoragePath(nameSelect.value, versionSelect.value, row);
            }
        });
        row.querySelector('.remove-model-bind').addEventListener('click', () => row.remove());

        modelBindList.appendChild(row);
        return row;
    }

    getModelBindings() {
        const bindings = [];
        this.shadowRoot.querySelectorAll('#modelBindList .model-bind-row').forEach(row => {
            const modelName = row.querySelector('.model-bind-name')?.value;
            const version = row.querySelector('.model-bind-version')?.value;
            const storagePath = row.dataset.storagePath || '';
            if (modelName) bindings.push({ modelName, version: version || '', storagePath });
        });
        return bindings;
    }

    async loadModelStoragePath(modelName, version, row) {
        try {
            console.log('加载模型storagePath:', modelName, version);
            const result = await window.AppConfig.get('model', 'metas', { name: modelName, version: version });
            if (result.success && result.data) {
                const modelData = result.data;
                row.dataset.storagePath = modelData.storagePath || '';
                console.log('模型storagePath:', modelData.storagePath);
            }
        } catch (error) {
            console.error('加载模型storagePath失败:', error);
        }
    }

    updateBindFieldOptions() {
        const fields = this._dataSourceFields || [];
        // 更新输入参数表中的数据源字段下拉
        this.shadowRoot.querySelectorAll('.data-field-select').forEach(select => {
            const current = select.dataset.bindField || select.value;
            select.innerHTML = '<option value="">请选择字段</option>';
            fields.forEach(f => {
                const name = f.name || f.fieldName || f;
                const readableType = f.readableType || this.convertDataTypeCode(f.dataType);
                const option = document.createElement('option');
                option.value = name;
                option.textContent = `${name} (${readableType})`;
                select.appendChild(option);
            });
            if (current) {
                select.value = current;
                select.dataset.bindField = current;
            }

            // 添加类型校验事件
            if (!select.dataset.validationBound) {
                select.addEventListener('change', () => {
                    this.validateFieldTypeCompatibility(select);
                    select.dataset.bindField = select.value;
                });
                select.dataset.validationBound = 'true';
            }
        });
    }

    // 验证字段类型与参数类型的兼容性
    validateFieldTypeCompatibility(fieldSelect) {
        const fieldName = fieldSelect.value;
        if (!fieldName) return;

        // 获取数据源字段类型
        const sourceType = this.getDataSourceFieldType(fieldName);

        // 获取对应的输入参数类型
        const row = fieldSelect.closest('.param-row');
        if (!row) return;

        const typeSelect = row.querySelector('select[data-field="type"][data-type="input"]');
        if (!typeSelect) return;

        const targetType = typeSelect.value;

        // 检查类型兼容性
        if (!this.areTypesCompatible(sourceType, targetType)) {
            // 显示错误提示
            this.showErrorMessage(`数据源字段类型 ${sourceType} 与参数类型 ${targetType} 不兼容`);

            // 添加错误样式
            fieldSelect.style.borderColor = '#ff4444';
            setTimeout(() => {
                fieldSelect.style.borderColor = '';
            }, 3000);
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

    async loadBindingData(algorithmInfo) {
        // 设置初始化标志，防止自动填充覆盖已有数据
        this._isInitializingEdit = true;

        // 加载数据源选项
        await this.loadDataSourceOptions();

        // 从算法元数据加载绑定数据
        try {
            const result = await window.AppConfig.get('algorithm', 'metas', {
                name: algorithmInfo.name,
                version: algorithmInfo.version
            });

            if (result.success && result.data) {
                const algorithmData = result.data;

                // 加载数据源
                const dataSource = this.shadowRoot.getElementById('dataSource');
                if (dataSource && algorithmData.tableName) {
                    dataSource.value = algorithmData.tableName;
                    await this.loadDataSourceFields();
                }

                // 加载运行配置
                const ruleCmd = this.shadowRoot.getElementById('ruleCmd');
                const inputCsvName = this.shadowRoot.getElementById('inputCsvName');
                const outputCsvName = this.shadowRoot.getElementById('outputCsvName');
                if (ruleCmd && algorithmData.cmd) ruleCmd.value = algorithmData.cmd;
                if (inputCsvName && algorithmData.inputCsvName) inputCsvName.value = algorithmData.inputCsvName;
                if (outputCsvName && algorithmData.outputCsvName) outputCsvName.value = algorithmData.outputCsvName;

                // 加载模型绑定
                const modelBindList = this.shadowRoot.getElementById('modelBindList');
                if (modelBindList) modelBindList.innerHTML = '';
                if (algorithmData.calledModels) {
                    try {
                        const modelBindings = typeof algorithmData.calledModels === 'string'
                            ? JSON.parse(algorithmData.calledModels)
                            : algorithmData.calledModels;
                        const loadPromises = modelBindings.map(async (binding) => {
                            const row = this.addModelBindRow({ modelName: binding.modelName, version: binding.version || '' });
                            if (binding.storagePath) {
                                row.dataset.storagePath = binding.storagePath;
                            } else if (binding.modelName && binding.version) {
                                await this.loadModelStoragePath(binding.modelName, binding.version, row);
                            }
                        });
                        await Promise.all(loadPromises);
                    } catch (e) {
                        console.error('解析模型绑定数据失败:', e);
                    }
                }

                // 加载输入输出映射
                if (algorithmData.inputData) {
                    try {
                        const mappings = typeof algorithmData.inputData === 'string'
                            ? JSON.parse(algorithmData.inputData)
                            : algorithmData.inputData;
                        this._inputMappings = mappings;
                        this.applyInputMappings();
                    } catch (e) { this._inputMappings = []; }
                }
                if (algorithmData.inputsBind) {
                    try {
                        const mappings = typeof algorithmData.inputsBind === 'string'
                            ? JSON.parse(algorithmData.inputsBind)
                            : algorithmData.inputsBind;
                        this._inputMappings = mappings;
                        this.applyInputMappings();
                    } catch (e) { this._inputMappings = []; }
                }
                if (algorithmData.outputsBind) {
                    try {
                        const resultMappings = typeof algorithmData.outputsBind === 'string'
                            ? JSON.parse(algorithmData.outputsBind)
                            : algorithmData.outputsBind;
                        this._outputMappings = resultMappings;
                        this.applyOutputMappings();
                    } catch (e) { this._outputMappings = []; }
                }
            }
        } catch (error) {
            console.error('加载绑定数据失败:', error);
        }

        // 延迟清除初始化标志，确保所有数据加载完成
        setTimeout(() => {
            this._isInitializingEdit = false;
        }, 500);
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

    getInputFieldPaths() {
        const paths = [];
        const dataSource = this.shadowRoot.getElementById('dataSource')?.value;
        const rows = this.shadowRoot.querySelectorAll('#inputsBody .param-row');
        rows.forEach(row => {
            const sourceField = row.querySelector('.data-field-select')?.value;
            if (sourceField && dataSource) {
                paths.push(`${dataSource}.${sourceField}`);
            }
        });
        return paths;
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
        const previewContent = this.shadowRoot.getElementById('previewContent');
        if (!previewContent) return;

        // 保存当前参数值
        this.saveAllCurrentValues();

        // 从输出参数的回写目标生成CSV表头
        const headers = this.outputs.map(o => o.bindTarget || o.name || '').filter(h => h);

        if (headers.length === 0) {
            previewContent.innerHTML = '<pre>请先添加输出参数并设置回写目标</pre>';
            return;
        }

        // 生成CSV表头
        const csvHeader = headers.join(',');

        // 生成模拟数据行（3行）
        const mockRows = [];
        for (let i = 0; i < 3; i++) {
            const row = headers.map(header => {
                // 根据数据类型生成模拟值
                const output = this.outputs.find(o => (o.bindTarget || o.name) === header);
                if (!output) return '';

                const type = (output.type || 'string').toLowerCase();
                switch (type) {
                    case 'int':
                    case 'integer':
                        return Math.floor(Math.random() * 100);
                    case 'float':
                    case 'double':
                        return (Math.random() * 100).toFixed(2);
                    case 'bool':
                    case 'boolean':
                        return Math.random() > 0.5 ? 'true' : 'false';
                    default:
                        return `sample_${i + 1}`;
                }
            });
            mockRows.push(row.join(','));
        }

        const csvContent = csvHeader + '\n' + mockRows.join('\n');
        previewContent.innerHTML = `<pre>${csvContent}</pre>`;
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
            tableName: this.shadowRoot.getElementById('dataSource')?.value || '',
            inputData: JSON.stringify(this.getInputFieldPaths()),
            calledModels: JSON.stringify(this.getModelBindings()),
            cmd: this.shadowRoot.getElementById('ruleCmd')?.value?.trim() || '',
            inputCsvName: this.shadowRoot.getElementById('inputCsvName')?.value?.trim() || '',
            outputCsvName: this.shadowRoot.getElementById('outputCsvName')?.value?.trim() || '',
            inputsBind: JSON.stringify(this.getInputMappings()),
            outputsBind: JSON.stringify(this.getOutputMappings()),
            outputTable: this.shadowRoot.getElementById('outputTable')?.value?.trim() || ''
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
