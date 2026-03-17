class ModelEdit extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });
        this.currentModel = null;
        this.inputs = [];
        this.outputs = [];
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
            const cssLink = document.createElement('link');
            cssLink.rel = 'stylesheet';
            cssLink.href = './components/model-edit/model-edit.css';
            this.shadowRoot.appendChild(cssLink);
        } catch (error) {
            console.error('Failed to load CSS:', error);
        }

        // 加载HTML模板
        try {
            const response = await fetch('./components/model-edit/model-edit.html');
            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }
            const html = await response.text();
            this.shadowRoot.innerHTML += html;
            console.log('Model edit HTML template loaded successfully');
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

        // 从代码自动解析按钮
        const autoParseBtn = this.shadowRoot.getElementById('autoParseBtn');
        if (autoParseBtn) {
            autoParseBtn.addEventListener('click', (e) => {
                e.stopPropagation();
                this.autoParseFromCode();
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

        // 点击遮罩关闭 - 只有点击背景才关闭
        this.addEventListener('click', (e) => {
            if (e.target === this) {
                this.hide();
            }
        });

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

    async show(modelInfo) {
        this.currentModel = modelInfo;
        this.removeAttribute('hidden');
        await this.loadModelData(modelInfo);
        await this.loadParsingRules(); // 确保加载解析规则
    }

    // 新增方法：直接接收model-detail的数据，不重复调用接口
    async showWithModelData(modelInfo, modelDetailData) {
        this.currentModel = modelInfo;
        this.currentModelMeta = modelDetailData;
        this.removeAttribute('hidden');
        
        // 确保加载解析规则
        await this.loadParsingRules();
        
        // 加载源文件列表
        await this.loadSourceFiles();
        
        // 直接使用model-detail的数据填充表单，完全使用接口数据
        const modelNameInput = this.shadowRoot.getElementById('modelName');
        const developerInput = this.shadowRoot.getElementById('developer');
        const versionInput = this.shadowRoot.getElementById('version');
        const sceneInput = this.shadowRoot.getElementById('scene');

        if (modelNameInput) modelNameInput.value = modelDetailData.name || '';
        if (developerInput) developerInput.value = modelDetailData.author || '';
        if (versionInput) versionInput.value = modelDetailData.version || '';
        if (sceneInput) sceneInput.value = modelDetailData.scene || '';

        // 使用接口返回的inputs和outputs数据
        this.loadInterfaceParamsFromData(modelDetailData.inputs, modelDetailData.outputs);
    }

    hide() {
        this.setAttribute('hidden', '');
    }

    async loadModelData(modelInfo) {
        try {
            // 调用API获取完整的模型元数据
            const result = await window.AppConfig.get('model', 'metas', {
                name: modelInfo.name,
                version: modelInfo.version
            });
            
            if (result.success && result.data) {
                this.currentModelMeta = result.data;
                console.log('获取到完整模型元数据:', this.currentModelMeta);
            } else {
                console.error('获取模型元数据失败:', result.message);
                // 如果获取失败，至少保存基本信息
                this.currentModelMeta = {
                    name: modelInfo.name,
                    version: modelInfo.version,
                    author: modelInfo.author,
                    scene: modelInfo.scene
                };
            }
        } catch (error) {
            console.error('获取模型元数据异常:', error);
            // 如果获取失败，至少保存基本信息
            this.currentModelMeta = {
                name: modelInfo.name,
                version: modelInfo.version,
                author: modelInfo.author,
                scene: modelInfo.scene
            };
        }
        
        // 加载基本信息到表单
        const modelNameInput = this.shadowRoot.getElementById('modelName');
        const developerInput = this.shadowRoot.getElementById('developer');
        const versionInput = this.shadowRoot.getElementById('version');
        const sceneInput = this.shadowRoot.getElementById('scene');

        if (modelNameInput) modelNameInput.value = modelInfo.name || '';
        if (developerInput) developerInput.value = modelInfo.author || '';
        if (versionInput) versionInput.value = modelInfo.version || '';
        if (sceneInput) sceneInput.value = modelInfo.scene || '';

        // 加载接口参数（使用从API获取的数据）
        if (this.currentModelMeta && this.currentModelMeta.inputs) {
            this.loadInterfaceParamsFromData(this.currentModelMeta.inputs, this.currentModelMeta.outputs);
        } else {
            // 如果没有数据，使用默认参数
            this.loadInterfaceParams();
        }
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
        
        // 数据类型选项
        const dataTypes = ['Double', 'Int32', 'String', 'Boolean', 'Float', 'Int64'];
        
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
                
                console.log(`保存输出参数[${index}]:`, this.outputs[index]);
            }
        });
    }

    showParseRules() {
        const rules = `
            <div class="parse-rules-dialog">
                <h4>解析规则说明</h4>
                <div class="rules-content">
                    <div class="rule-item">
                        <strong>参数命名规则：</strong>
                        <ul>
                            <li>使用驼峰命名法：temperature, pressure, flowRate</li>
                            <li>避免特殊字符和中文</li>
                            <li>参数名要有意义，见名知意</li>
                        </ul>
                    </div>
                    <div class="rule-item">
                        <strong>数据类型映射：</strong>
                        <ul>
                            <li>float/double → Double</li>
                            <li>int/integer → Int32</li>
                            <li>string/text → String</li>
                            <li>bool/boolean → Boolean</li>
                        </ul>
                    </div>
                    <div class="rule-item">
                        <strong>单位识别规则：</strong>
                        <ul>
                            <li>温度单位：°C, °F, K</li>
                            <li>压力单位：Pa, kPa, MPa, bar</li>
                            <li>速度单位：m/s, km/h</li>
                            <li>时间单位：s, min, h, day</li>
                        </ul>
                    </div>
                </div>
                <button class="close-rules-btn">确定</button>
            </div>
        `;
        
        this.showDialog(rules, 'close-rules-btn');
    }

    forceOverrideDropdowns() {
        // 强制覆盖所有下拉选择为推荐值
        const recommendations = {
            temperature: { type: 'Double', unit: '°C', desc: '环境温度' },
            pressure: { type: 'Double', unit: 'kPa', desc: '压力值' },
            flow_rate: { type: 'Double', unit: 'm³/h', desc: '流量' },
            control_signal: { type: 'Double', unit: '%', desc: '控制信号' },
            status: { type: 'Int32', unit: '-', desc: '状态码' },
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
        // 去掉提示信息，避免干扰用户
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
            
            // 获取模型名称和版本
            const modelName = this.currentModel?.name || this.currentModelMeta?.name;
            const version = this.currentModel?.version || this.currentModelMeta?.version;
            
            console.log('使用的参数 - modelName:', modelName, 'version:', version);
            
            if (!modelName || !version) {
                this.showErrorMessage('模型名称或版本为空，无法解析代码');
                return;
            }
            
            // 调用ModelFileService的extractModelFile方法
            const extractResponse = await window.AppConfig.post('model', 'extractModelFile', {
                name: modelName,
                version: version
            });
            
            if (!extractResponse.success) {
                this.showErrorMessage('提取模型文件失败: ' + extractResponse.message);
                return;
            }
            
            console.log('模型文件提取成功:', extractResponse.data);
            
            // 动态填充源文件下拉选择框（每次点击都重新加载）
            this.populateSourceFileSelect(extractResponse.data);
            
            // 如果没有选择文件，提示用户选择
            if (!selectedFile) {
                this.showErrorMessage('请从下拉列表中选择源文件');
                return;
            }
            
            // 执行代码分析
            const codeAnalysis = this.performRealCodeAnalysis(selectedFile, parsingRule, extractResponse.data);
            
            if (!codeAnalysis || (!codeAnalysis.inputs && !codeAnalysis.outputs)) {
                this.showErrorMessage('解析失败，请检查解析规则和源文件');
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
    
    performCodeAnalysis(sourceFile, parsingRule) {
        // 模拟从源文件扫描注释并解析Input/Output元数据
        const fileExt = sourceFile.substring(sourceFile.lastIndexOf('.'));
        
        // 模拟文件内容（实际应用中需要读取真实文件）
        const mockFileContents = {
            'model.py': `# @Input: speed (float) - 车速
# @Input: gear (int) - 档位
# @Input: temperature (float) - 发动机温度
# @Output: power (float) - 功率
# @Output: torque (float) - 扭矩
# @Output: efficiency (float) - 效率

def calculate_engine_performance():
    pass`,
            
            'control.m': `% @Input: reference (double) - 参考值
% @Input: feedback (double) - 反馈值
% @Input: gain (double) - 增益
% @Output: control_signal (double) - 控制信号
% @Output: error (double) - 误差

function control_signal = pid_controller(reference, feedback, gain)
    % Implementation here`,
            
            'processor.cpp': `/**
 * @param input_data (vector<double>) - 输入数据向量
 * @param threshold (double) - 阈值参数
 * @param mode (int) - 处理模式
 * @return result (bool) - 处理结果
 * @return processed (vector<double>) - 处理后数据
 */
bool processData() {
    // Implementation here`,
            
            'algorithm.java': `/**
 * @param values (double[]) - 输入数值数组
 * @param weights (double[]) - 权重数组
 * @return result (double) - 计算结果
 */
public double calculateWeightedAverage() {
    // Implementation here`,
            
            'generic.txt': `# @Input: data1 (string) - 第一个数据
# @Input: data2 (string) - 第二个数据
# @Output: result (string) - 处理结果
# @Output: status (int) - 状态码

Generic processing function`
        };
        
        // 获取文件内容（模拟）
        const fileContent = mockFileContents[sourceFile] || mockFileContents['model.py'];
        
        // 使用正则表达式解析注释中的Input/Output信息
        const results = { inputs: [], outputs: [] };
        
        if (parsingRule.type === 'regex' && parsingRule.pattern) {
            try {
                const regex = new RegExp(parsingRule.pattern, 'gm');
                let match;
                
                while ((match = regex.exec(fileContent)) !== null) {
                    const [, type, name, dataType, description] = match;
                    
                    const param = {
                        name: name.trim(),
                        type: dataType.trim(),
                        unit: this.inferUnit(dataType.trim(), description.trim()),
                        desc: description.trim()
                    };
                    
                    if (type.toLowerCase().includes('input') || type.toLowerCase().includes('param')) {
                        results.inputs.push(param);
                    } else if (type.toLowerCase().includes('output') || type.toLowerCase().includes('return')) {
                        results.outputs.push(param);
                    }
                }
            } catch (e) {
                console.error('Regex parsing error:', e);
                // 返回默认结果
                return this.getDefaultResults(parsingRule.pattern);
            }
        }
        
        // 如果没有找到匹配项，返回默认结果
        if (results.inputs.length === 0 && results.outputs.length === 0) {
            // 如果是Python反射类型，尝试反射分析
            if (parsingRule.type === 'python' && parsingRule.pythonModule && parsingRule.pythonFunction) {
                return this.performPythonReflection(parsingRule.pythonModule, parsingRule.pythonFunction);
            }
            return this.getDefaultResults(parsingRule.pattern);
        }
        
        return results;
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
        
        // UI中的数据类型选项
        const uiDataTypes = ['Double', 'Int32', 'String', 'Boolean', 'Float', 'Int64'];
        
        // 标准化数据类型映射
        const typeMap = {
            'float': 'Float',
            'double': 'Double', 
            'int': 'Int32',
            'integer': 'Int32',
            'long': 'Int64',
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
            'model.py': `# @Input: speed (float) - 车速
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
            console.log('当前模型信息:', this.currentModel);
            console.log('当前模型元数据:', this.currentModelMeta);
            
            // 获取模型名称和版本
            const modelName = this.currentModel?.name || this.currentModelMeta?.name;
            const version = this.currentModel?.version || this.currentModelMeta?.version;
            
            console.log('使用的参数 - modelName:', modelName, 'version:', version);
            
            if (!modelName || !version) {
                console.warn('模型名称或版本为空，跳过源文件加载');
                return;
            }
            
            // 调用ModelFileService的extractModelFile方法
            const extractResponse = await window.AppConfig.post('model', 'extractModelFile', {
                name: modelName,
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
        const codeExtensions = ['.py', '.m', '.cpp', '.c', '.h', '.java', '.js', '.ts'];
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
    
    performPythonReflection(moduleName, functionName) {
        // 模拟Python inspect模块的反射分析
        const standardModules = {
            'math': {
                'sqrt': {
                    inputs: [
                        { name: 'x', type: 'float', unit: '-', desc: '要计算平方根的数字' }
                    ],
                    outputs: [
                        { name: 'result', type: 'float', unit: '-', desc: 'x的平方根' }
                    ]
                },
                'sin': {
                    inputs: [
                        { name: 'x', type: 'float', unit: 'rad', desc: '角度（弧度）' }
                    ],
                    outputs: [
                        { name: 'result', type: 'float', unit: '-', desc: 'x的正弦值' }
                    ]
                },
                'log': {
                    inputs: [
                        { name: 'x', type: 'float', unit: '-', desc: '要计算对数的数字' },
                        { name: 'base', type: 'float', unit: '-', desc: '对数的底数（可选）' }
                    ],
                    outputs: [
                        { name: 'result', type: 'float', unit: '-', desc: 'x的对数' }
                    ]
                }
            },
            'datetime': {
                'datetime': {
                    inputs: [
                        { name: 'year', type: 'int', unit: '-', desc: '年份' },
                        { name: 'month', type: 'int', unit: '-', desc: '月份 (1-12)' },
                        { name: 'day', type: 'int', unit: '-', desc: '日期 (1-31)' },
                        { name: 'hour', type: 'int', unit: '-', desc: '小时 (0-23)' },
                        { name: 'minute', type: 'int', unit: '-', desc: '分钟 (0-59)' },
                        { name: 'second', type: 'int', unit: '-', desc: '秒 (0-59)' },
                        { name: 'microsecond', type: 'int', unit: '-', desc: '微秒 (0-999999)' },
                        { name: 'tzinfo', type: 'tzinfo', unit: '-', desc: '时区信息' }
                    ],
                    outputs: [
                        { name: 'datetime_obj', type: 'datetime', unit: '-', desc: 'datetime对象' }
                    ]
                }
            },
            're': {
                'match': {
                    inputs: [
                        { name: 'pattern', type: 'str', unit: '-', desc: '正则表达式模式' },
                        { name: 'string', type: 'str', unit: '-', desc: '要搜索的字符串' },
                        { name: 'flags', type: 'int', unit: '-', desc: '匹配标志' }
                    ],
                    outputs: [
                        { name: 'match_obj', type: 'MatchObject', unit: '-', desc: '匹配对象或None' }
                    ]
                },
                'search': {
                    inputs: [
                        { name: 'pattern', type: 'str', unit: '-', desc: '正则表达式模式' },
                        { name: 'string', type: 'str', unit: '-', desc: '要搜索的字符串' },
                        { name: 'flags', type: 'int', unit: '-', desc: '匹配标志' }
                    ],
                    outputs: [
                        { name: 'match_obj', type: 'MatchObject', unit: '-', desc: '匹配对象或None' }
                    ]
                }
            }
        };
        
        // 检查模块是否存在
        const module = standardModules[moduleName];
        if (!module) {
            return {
                inputs: [],
                outputs: [],
                error: `模块 '${moduleName}' 不存在或无法导入`
            };
        }
        
        // 检查函数是否存在
        const func = module[functionName];
        if (!func) {
            return {
                inputs: [],
                outputs: [],
                error: `函数 '${functionName}' 在模块 '${moduleName}' 中不存在`
            };
        }
        
        return func;
    }
    
    inferUnit(dataType, description) {
        // 根据数据类型和描述推断物理单位
        const unitMap = {
            'float': '°C',
            'double': 'V',
            'int': 'rpm',
            'string': '-',
            'bool': '-',
            'vector<double>': '-',
            'double[]': '-'
        };
        
        // 从描述中查找单位关键词
        const descLower = description.toLowerCase();
        if (descLower.includes('温度') || descLower.includes('temperature')) return '°C';
        if (descLower.includes('压力') || descLower.includes('pressure')) return 'Pa';
        if (descLower.includes('速度') || descLower.includes('speed')) return 'km/h';
        if (descLower.includes('转速') || descLower.includes('rpm')) return 'rpm';
        if (descLower.includes('功率') || descLower.includes('power')) return 'kW';
        if (descLower.includes('扭矩') || descLower.includes('torque')) return 'Nm';
        if (descLower.includes('电压') || descLower.includes('voltage')) return 'V';
        if (descLower.includes('电流') || descLower.includes('current')) return 'A';
        
        return unitMap[dataType] || '-';
    }
    
    getDefaultResults(pattern) {
        // 根据规则类型返回默认结果
        if (pattern.includes('#')) {
            // Python风格
            return {
                inputs: [
                    { name: 'input_param', type: 'float', unit: '°C', desc: '输入参数' }
                ],
                outputs: [
                    { name: 'output_result', type: 'float', unit: '-', desc: '输出结果' }
                ]
            };
        } else if (pattern.includes('%')) {
            // MATLAB风格
            return {
                inputs: [
                    { name: 'input_signal', type: 'double', unit: 'V', desc: '输入信号' }
                ],
                outputs: [
                    { name: 'output_signal', type: 'double', unit: 'V', desc: '输出信号' }
                ]
            };
        } else if (pattern.includes('/\\*\\*')) {
            // C++/Java风格
            return {
                inputs: [
                    { name: 'param', type: 'double', unit: '-', desc: '参数描述' }
                ],
                outputs: [
                    { name: 'result', type: 'bool', unit: '-', desc: '返回结果' }
                ]
            };
        }
        
        return { inputs: [], outputs: [] };
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
        
        try {
            // 通过API动态查询解析规则
            console.log('正在调用API查询解析规则...');
            const response = await window.AppConfig.post('data', 'parsing/rules/query', {
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
        // 根据选择的规则调整解析逻辑
        this.applyParseRules(value);
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

    applyParseRules(ruleType) {
        // 根据规则类型应用不同的解析规则
        const rules = {
            default: '使用默认解析规则',
            strict: '使用严格解析规则',
            custom: '使用自定义解析规则'
        };
        
        this.showSuccessMessage(`已应用${rules[ruleType]}`);
    }

    showDialog(content, closeBtnClass) {
        const dialogHtml = `
            <div class="dialog-overlay">
                <div class="dialog-content">
                    ${content}
                </div>
            </div>
        `;
        
        document.body.insertAdjacentHTML('beforeend', dialogHtml);
        
        const overlay = document.querySelector('.dialog-overlay');
        const closeBtn = overlay.querySelector(`.${closeBtnClass}`);
        
        const closeDialog = () => {
            overlay.remove();
        };
        
        closeBtn.addEventListener('click', closeDialog);
        // 移除点击遮罩关闭功能，避免误操作
        // overlay.addEventListener('click', (e) => {
        //     if (e.target === overlay) {
        //         closeDialog();
        //     }
        // });
    }

    collectFormData() {
        // 收集基本信息
        const modelName = this.shadowRoot.getElementById('modelName').value.trim();
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

        // 构建完整的表单数据对象，包含ModelFileService.saveModelMetadata需要的所有字段
        const formData = {
            name: modelName,
            version: version,
            fileName: this.currentModelMeta?.fileName || '',
            fileSize: this.currentModelMeta?.fileSize || 0,
            chunkCount: this.currentModelMeta?.chunkCount || 0,
            storagePath: this.currentModelMeta?.storagePath || '',
            fileMd5: this.currentModelMeta?.fileMd5 || '',
            author: developer,
            scene: scene,
            inputs: JSON.stringify(inputsData),
            outputs: JSON.stringify(outputsData),
            timestamp: this.currentModelMeta?.timestamp || Date.now()
        };

        return formData;
    }

    async save() {
        try {
            const formData = this.collectFormData();
            
            // 验证必填字段
            if (!formData.name) {
                this.showErrorMessage('请输入模型名称');
                return;
            }
            
            if (!formData.version) {
                this.showErrorMessage('请输入版本号');
                return;
            }

            console.log('保存模型数据:', formData);

            // 使用新的API配置
            const result = await window.AppConfig.post('model', 'metas', formData);
            
            console.log('保存响应:', result);
            
            if (result.success) {
                this.showSuccessMessage('元数据保存成功');
                this.hide();
                
                // 重新加载右侧模型资产库
                console.log('🔄 模型编辑成功，准备调用 loadDataSourceTree');
                if (window.loadDataSourceTree) {
                    console.log('🔄 调用 window.loadDataSourceTree');
                    window.loadDataSourceTree();
                } else {
                    console.error('❌ window.loadDataSourceTree 不存在');
                }
                
                // 通知模型详情页面刷新数据
                this.dispatchEvent(new CustomEvent('model-updated', {
                    detail: { 
                        modelName: formData.name,
                        version: formData.version,
                        formData: formData
                    },
                    bubbles: true,
                    composed: true
                }));
                
                // 刷新右侧树（如果需要）
                this.refreshModelTree();
            } else {
                this.showErrorMessage(result.message || '保存失败');
                }
        } catch (error) {
            console.error('保存元数据失败:', error);
            this.showErrorMessage('保存失败，请稍后重试');
        }
    }

    refreshModelTree() {
        // 这里可以添加刷新右侧树的逻辑
        console.log('刷新模型树');
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

customElements.define('model-edit', ModelEdit);
