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

    show(modelInfo) {
        this.currentModel = modelInfo;
        this.removeAttribute('hidden');
        this.loadModelData(modelInfo);
    }

    hide() {
        this.setAttribute('hidden', '');
    }

    loadModelData(modelInfo) {
        // 加载基本信息
        const modelNameInput = this.shadowRoot.getElementById('modelName');
        const developerInput = this.shadowRoot.getElementById('developer');
        const versionInput = this.shadowRoot.getElementById('version');
        const sceneInput = this.shadowRoot.getElementById('scene');

        if (modelNameInput) modelNameInput.value = modelInfo.name || '';
        if (developerInput) developerInput.value = '张三'; // 默认开发者
        if (versionInput) versionInput.value = modelInfo.version || '';
        if (sceneInput) sceneInput.value = '工业控制'; // 默认场景

        // 加载接口参数（使用静态数据）
        this.loadInterfaceParams();
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
            inputsBody.innerHTML = this.inputs.map((input, index) => `
                <div class="param-row" data-index="${index}">
                    <div class="col-name">
                        <input type="text" value="${input.name}" data-field="name" data-type="input" placeholder="参数名">
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
                        <input type="text" value="${input.desc}" data-field="desc" data-type="input" placeholder="说明">
                    </div>
                    <div class="col-action">
                        <button class="delete-btn" data-index="${index}" data-type="input">删除</button>
                    </div>
                </div>
            `).join('');
        }

        // 渲染输出参数
        const outputsBody = this.shadowRoot.getElementById('outputsBody');
        if (outputsBody) {
            outputsBody.innerHTML = this.outputs.map((output, index) => `
                <div class="param-row" data-index="${index}">
                    <div class="col-name">
                        <input type="text" value="${output.name}" data-field="name" data-type="output" placeholder="参数名">
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
                        <input type="text" value="${output.desc}" data-field="desc" data-type="output" placeholder="说明">
                    </div>
                    <div class="col-action">
                        <button class="delete-btn" data-index="${index}" data-type="output">删除</button>
                    </div>
                </div>
            `).join('');
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
        this.inputs.push({
            name: '',
            type: '',
            unit: '',
            desc: ''
        });
        this.renderParams();
    }

    addOutputParam() {
        this.outputs.push({
            name: '',
            type: '',
            unit: '',
            desc: ''
        });
        this.renderParams();
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
        this.showSuccessMessage('已强制覆盖为推荐值');
    }

    autoParseFromCode() {
        // 模拟从代码解析参数
        const mockCodeAnalysis = {
            inputs: [
                { name: 'ambient_temp', type: 'Double', unit: '°C', desc: '环境温度传感器读数' },
                { name: 'system_pressure', type: 'Double', unit: 'kPa', desc: '系统压力监测' },
                { name: 'flow_velocity', type: 'Double', unit: 'm/s', desc: '流体速度' },
                { name: 'valve_position', type: 'Double', unit: '%', desc: '阀门开度' }
            ],
            outputs: [
                { name: 'pump_speed', type: 'Double', unit: 'rpm', desc: '泵转速控制' },
                { name: 'heating_power', type: 'Double', unit: 'kW', desc: '加热功率' },
                { name: 'system_status', type: 'Int32', unit: '-', desc: '系统运行状态' },
                { name: 'efficiency_ratio', type: 'Double', unit: '%', desc: '能效比' }
            ]
        };

        this.inputs = mockCodeAnalysis.inputs;
        this.outputs = mockCodeAnalysis.outputs;
        this.renderParams();
        this.showSuccessMessage('已从代码自动解析参数');
    }

    onParseRulesChange(value) {
        console.log('解析规则变更:', value);
        // 根据选择的规则调整解析逻辑
        this.applyParseRules(value);
    }

    onSourceFileChange(value) {
        console.log('源文件变更:', value);
        // 根据选择的源文件调整解析
        if (value) {
            this.showSuccessMessage(`已选择源文件: ${value}`);
        }
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
        overlay.addEventListener('click', (e) => {
            if (e.target === overlay) {
                closeDialog();
            }
        });
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

        return {
            name: modelName,
            developer: developer,
            version: version,
            scene: scene,
            inputs: inputsData,
            outputs: outputsData
        };
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

            // 调用保存API
            const response = await fetch('/api/models/update', {
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
                    this.showSuccessMessage('模型保存成功');
                    this.hide();
                    
                    // 刷新右侧树（如果需要）
                    this.refreshModelTree();
                } else {
                    this.showErrorMessage(result.message || '保存失败');
                }
            } else {
                throw new Error(`HTTP error! status: ${response.status}`);
            }
        } catch (error) {
            console.error('保存模型失败:', error);
            this.showErrorMessage('保存失败，请稍后重试');
        }
    }

    refreshModelTree() {
        // 这里可以添加刷新右侧树的逻辑
        console.log('刷新模型树');
    }

    showSuccessMessage(message) {
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

    showErrorMessage(message) {
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

customElements.define('model-edit', ModelEdit);
