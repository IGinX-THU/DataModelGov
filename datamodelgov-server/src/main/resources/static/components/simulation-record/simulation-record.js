/**
 * 仿真记录组件 - 完全参照visual-analysis
 * 查询仿真档案执行记录，支持图表对比分析、生成报告、导出、查看日志、删除、停止
 */
class SimulationRecord extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });
        this.chart = null;
        this.allData = [];
        this.displayData = [];
        this.currentPage = 1;
        this.pageSize = 10;
        this.totalPages = 0;
        this.totalCount = 0;
        this.curveVisibility = {
            input: true,
            output: true
        };
        this.currentAnalysisMode = 'comparison';
        this.currentFilter = {
            status: '',
            name: '',
            time: ''
        };
        this.currentChartData = null;
        this.currentLogTask = null;
        this.logRefreshInterval = null;
    }

    async connectedCallback() {
        await this.loadResources();
        setTimeout(() => {
            this.bindEvents();
            this.initPagination();
        }, 100);
    }

    async loadResources() {
        try {
            const cssLink = document.createElement('link');
            cssLink.rel = 'stylesheet';
            cssLink.href = './components/simulation-record/simulation-record.css';
            this.shadowRoot.appendChild(cssLink);
        } catch (error) {
            console.error('Failed to load CSS:', error);
        }

        if (window.location.protocol === 'file:') {
            this.shadowRoot.innerHTML += this.getFallbackHTML();
        } else {
            try {
                const response = await fetch('./components/simulation-record/simulation-record.html');
                const html = await response.text();
                this.shadowRoot.innerHTML += html;
            } catch (error) {
                console.error('Failed to load HTML:', error);
                this.shadowRoot.innerHTML += this.getFallbackHTML();
            }
        }

        try {
            if (!window.echarts) {
                const script = document.createElement('script');
                script.src = './lib/echarts/echarts.min.js';
                document.head.appendChild(script);
                await new Promise((resolve) => { script.onload = resolve; });
            }
        } catch (error) {
            console.error('Failed to load ECharts:', error);
        }
    }

    getFallbackHTML() {
        return `
        <div class="visual-analysis-container">
            <div class="visualization-header">
                <h3 class="visualization-title" id="analysisTitle">仿真记录</h3>
                <button class="close-btn" id="closeBtn">×</button>
            </div>
            <div class="content-area">
                <div class="chart-section">
                    <div class="chart-header">
                        <h4 class="chart-title">分析图表</h4>
                        <div class="chart-actions">
                            <button class="toggle-btn" id="toggleInputBtn">输入数据</button>
                            <button class="toggle-btn" id="toggleOutputBtn">输出数据</button>
                        </div>
                    </div>
                    <div class="chart-container" id="analysisChart"></div>
                </div>
                <div class="table-section">
                    <div class="table-header">
                        <h4 class="table-title">仿真记录数据</h4>
                        <div class="table-controls">
                            <div class="filter-controls">
                                <label for="statusFilter">状态筛选:</label>
                                <select id="statusFilter" class="filter-select">
                                    <option value="">全部</option>
                                    <option value="running">运行中</option>
                                    <option value="stopped">已停止</option>
                                    <option value="completed">成功</option>
                                    <option value="failed">失败</option>
                                </select>
                                <label for="nameSearch">名称搜索:</label>
                                <input type="text" id="nameSearch" class="search-input" placeholder="搜索仿真名称">
                                <div class="time-range-container">
                                    <span class="time-range-label">时间范围:</span>
                                    <input type="datetime-local" id="startTime" class="datetime-input">
                                    <span class="time-range-separator">至</span>
                                    <input type="datetime-local" id="endTime" class="datetime-input">
                                </div>
                                <button class="toolbar-btn blue" id="searchBtn">🔍 搜索</button>
                            </div>
                            <div class="table-actions">
                                <button class="toolbar-btn poor" id="compareBtn">对比</button>
                                <div class="report-limit-container">
                                    <span class="report-limit-label">报告数据限制:</span>
                                    <input type="number" id="reportDataLimit" class="report-limit-input" min="1" max="10000" value="20">
                                    <span class="report-limit-unit">条</span>
                                </div>
                                <div class="sampling-algo-container">
                                    <span class="sampling-algo-label">采样算法:</span>
                                    <select id="samplingAlgorithm" class="sampling-algo-select">
                                        <option value="uniform">均匀采样</option>
                                        <option value="random">随机采样</option>
                                        <option value="first">取前N条</option>
                                        <option value="last">取后N条</option>
                                    </select>
                                </div>
                            </div>
                        </div>
                    </div>
                    <div class="table-wrapper">
                        <table class="data-table">
                            <thead>
                                <tr>
                                    <th style="width: 40px; text-align: center;"><input type="checkbox" id="selectAll" class="checkbox-all"></th>
                                    <th>档案名称</th>
                                    <th>开始时间</th>
                                    <th>结束时间</th>
                                    <th>运行状态</th>
                                    <th>错误信息</th>
                                    <th>操作</th>
                                </tr>
                            </thead>
                            <tbody id="tableBody"></tbody>
                        </table>
                    </div>
                    <common-pagination id="pagination"></common-pagination>
                </div>
            </div>
        </div>`;
    }

    show() {
        this.setAttribute('show', '');
        this.allData = [];
        this.displayData = [];
        this.currentPage = 1;
        this.pageSize = 10;
        setTimeout(() => {
            this.initPagination();
            this.initializeComponent();
        }, 100);
    }

    hide() {
        this.removeAttribute('show');
        this.stopLogAutoRefresh();
        if (this.chart) {
            this.chart.dispose();
            this.chart = null;
        }
    }

    initializeComponent() {
        this.loadRecordsFromAPI();
        this.showEmptyState();
    }

    bindEvents() {
        const searchBtn = this.shadowRoot.getElementById('searchBtn');
        if (searchBtn) {
            searchBtn.addEventListener('click', () => {
                this.currentPage = 1;
                this.loadRecordsFromAPI();
            });
        }

        const closeBtn = this.shadowRoot.getElementById('closeBtn');
        if (closeBtn) {
            closeBtn.addEventListener('click', () => this.hide());
        }

        const selectAll = this.shadowRoot.getElementById('selectAll');
        if (selectAll) {
            selectAll.addEventListener('change', (e) => this.handleSelectAll(e.target.checked));
        }

        const compareBtn = this.shadowRoot.getElementById('compareBtn');
        if (compareBtn) {
            compareBtn.addEventListener('click', () => this.handleCompareSelected());
        }

        const toggleInputBtn = this.shadowRoot.getElementById('toggleInputBtn');
        if (toggleInputBtn) {
            toggleInputBtn.addEventListener('click', () => this.toggleInputData());
        }

        const toggleOutputBtn = this.shadowRoot.getElementById('toggleOutputBtn');
        if (toggleOutputBtn) {
            toggleOutputBtn.addEventListener('click', () => this.toggleOutputData());
        }

        const statusFilter = this.shadowRoot.getElementById('statusFilter');
        if (statusFilter) {
            statusFilter.addEventListener('change', (e) => this.handleStatusFilter(e.target.value));
        }

        const reportLimitHelp = this.shadowRoot.getElementById('reportLimitHelp');
        if (reportLimitHelp) {
            reportLimitHelp.addEventListener('click', () => {
                this.showReportLimitHelp();
            });
        }

        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape' && this.hasAttribute('show')) this.hide();
        });
    }

    showEmptyState() {
        if (this.chart) {
            this.chart.dispose();
            this.chart = null;
        }
        const chartContainer = this.shadowRoot.getElementById('analysisChart');
        if (chartContainer) {
            chartContainer.innerHTML = `
                <div style="display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100%; color: #999;">
                    <div style="font-size: 48px; margin-bottom: 16px;">📈</div>
                    <div style="font-size: 14px; margin-bottom: 8px;">暂无分析数据</div>
                    <div style="font-size: 12px;">请选择仿真记录并点击"对比"</div>
                </div>`;
        }
    }

    initChart() {
        const chartContainer = this.shadowRoot.getElementById('analysisChart');
        if (chartContainer && window.echarts) {
            chartContainer.innerHTML = '';
            const tryInitChart = (attempt = 0) => {
                if (window.echarts && !this.chart) {
                    const rect = chartContainer.getBoundingClientRect();
                    if (rect.height < 100 && attempt < 5) {
                        setTimeout(() => tryInitChart(attempt + 1), 200);
                        return;
                    }
                    if (rect.height < 350) chartContainer.style.minHeight = '350px';
                    try {
                        this.chart = window.echarts.init(chartContainer);
                        this.updateChart();
                    } catch (error) {
                        setTimeout(() => tryInitChart(attempt + 1), 500);
                    }
                } else if (attempt < 10) {
                    setTimeout(() => tryInitChart(attempt + 1), 200);
                }
            };
            setTimeout(() => tryInitChart(), 100);
        }
    }

    updateChart() {
        if (!this.chart || !this.currentChartData) return;

        const series = [];
        const colors = ['#1890ff', '#52c41a', '#faad14', '#f5222d', '#722ed1', '#13c2c2'];

        // 计算数据范围用于自动缩放
        let allDataPoints = [];
        
        if (this.currentChartData.tasks) {
            this.currentChartData.tasks.forEach((task, idx) => {
                const taskColor = colors[idx % colors.length];

                // 输入数据 - 使用测点路径作为图例名称
                if (this.curveVisibility.input && task.inputData && task.inputData.length > 0) {
                    const filteredData = task.inputData.filter(p => p && isFinite(p[0]) && isFinite(p[1]));
                    
                    // 如果有inputPaths，使用路径作为图例名称
                    if (task.inputPaths && task.inputPaths.length > 0) {
                        task.inputPaths.forEach((path, pathIdx) => {
                            const pathColor = colors[(idx + pathIdx) % colors.length];
                            series.push({
                                name: `${path} (输入)`,
                                type: 'line',
                                data: filteredData,
                                smooth: true,
                                symbol: 'circle',
                                symbolSize: 3,
                                lineStyle: { width: 2, color: pathColor, type: 'dashed' },
                                itemStyle: { color: pathColor }
                            });
                            allDataPoints = allDataPoints.concat(filteredData);
                        });
                    } else {
                        // 备用方案：使用节点名称
                        series.push({
                            name: `${task.name} (输入)`,
                            type: 'line',
                            data: filteredData,
                            smooth: true,
                            symbol: 'circle',
                            symbolSize: 3,
                            lineStyle: { width: 2, color: taskColor, type: 'dashed' },
                            itemStyle: { color: taskColor }
                        });
                        allDataPoints = allDataPoints.concat(filteredData);
                    }
                }

                // 输出数据 - 使用CSV表头作为图例名称
                if (this.curveVisibility.output && task.calculationResult && task.calculationResult.length > 0) {
                    const filteredData = task.calculationResult.filter(p => p && isFinite(p[0]) && isFinite(p[1]));
                    
                    // 尝试从CSV表头获取列名
                    let csvHeaders = [];
                    let hasKeyColumn = false;
                    if (this.currentChartData.parsedResult && this.currentChartData.parsedResult.results) {
                        const firstNodeKey = Object.keys(this.currentChartData.parsedResult.results)[0];
                        if (firstNodeKey) {
                            const nodeResult = this.currentChartData.parsedResult.results[firstNodeKey];
                            if (nodeResult.outputCsv) {
                                // 解析CSV表头
                                const lines = nodeResult.outputCsv.split('\n');
                                if (lines.length > 0) {
                                    csvHeaders = lines[0].split(',').map(h => h.trim());
                                    // 检查是否有key列
                                    hasKeyColumn = csvHeaders.some(h => h.toLowerCase() === 'key');
                                }
                            }
                        }
                    }
                    
                    // 如果有CSV表头，使用表头作为图例名称
                    if (csvHeaders.length > 0) {
                        csvHeaders.forEach((header, headerIdx) => {
                            // 跳过key列（如果有）
                            if (hasKeyColumn && header.toLowerCase() === 'key') return;
                            // 如果没有key列，跳过第一列signal列
                            if (!hasKeyColumn && headerIdx === 0) return;
                            
                            const headerColor = colors[(idx + headerIdx) % colors.length];
                            series.push({
                                name: `${header} (输出)`,
                                type: 'line',
                                data: filteredData,
                                smooth: true,
                                symbol: 'diamond',
                                symbolSize: 3,
                                lineStyle: { width: 2, color: headerColor, type: 'solid' },
                                itemStyle: { color: headerColor }
                            });
                            allDataPoints = allDataPoints.concat(filteredData);
                        });
                    } else if (task.outputPaths && task.outputPaths.length > 0) {
                        // 备用方案：使用outputPaths
                        task.outputPaths.forEach((path, pathIdx) => {
                            const pathColor = colors[(idx + pathIdx) % colors.length];
                            const shortName = path.split('.').pop();
                            series.push({
                                name: `${shortName} (输出)`,
                                type: 'line',
                                data: filteredData,
                                smooth: true,
                                symbol: 'diamond',
                                symbolSize: 3,
                                lineStyle: { width: 2, color: pathColor, type: 'solid' },
                                itemStyle: { color: pathColor }
                            });
                            allDataPoints = allDataPoints.concat(filteredData);
                        });
                    } else {
                        // 备用方案：使用节点名称
                        series.push({
                            name: `${task.name} (输出)`,
                            type: 'line',
                            data: filteredData,
                            smooth: true,
                            symbol: 'diamond',
                            symbolSize: 3,
                            lineStyle: { width: 2, color: taskColor, type: 'solid' },
                            itemStyle: { color: taskColor }
                        });
                        allDataPoints = allDataPoints.concat(filteredData);
                    }
                }
            });
        }

        // 计算数据范围用于动态调整Y轴
        const dataRange = this.calculateDataRange({
            inputData: this.currentChartData.parsedResult ? null : null,
            outputData: null
        });
        
        // 对于单个分析，数据是扁平的数组格式，需要手动计算范围
        let yMin = Infinity, yMax = -Infinity;
        allDataPoints.forEach(point => {
            if (point[1] < yMin) yMin = point[1];
            if (point[1] > yMax) yMax = point[1];
        });
        if (yMin === Infinity) yMin = 0;
        if (yMax === -Infinity) yMax = 100;
        const yPadding = (yMax - yMin) * 0.1 || 1;

        // 计算x轴范围
        let xMin = Infinity, xMax = -Infinity;
        allDataPoints.forEach(point => {
            if (point[0] < xMin) xMin = point[0];
            if (point[0] > xMax) xMax = point[0];
        });
        if (xMin === Infinity) xMin = 0;
        if (xMax === -Infinity) xMax = 100;
        const xPadding = (xMax - xMin) * 0.05 || 1;

        const option = {
            title: { text: '仿真记录分析', left: 'center', top: 10, textStyle: { fontSize: 14, fontWeight: 'bold' } },
            tooltip: {
                trigger: 'axis',
                formatter: (params) => {
                    if (!params || params.length === 0) return '';
                    const xValue = params[0].value[0];
                    let xLabel = '';
                    if (this.isValidTimestamp(xValue)) {
                        xLabel = new Date(xValue).toLocaleString();
                    } else {
                        xLabel = this.formatTimeWithUnit(xValue);
                    }
                    let result = `相对时间: ${xLabel}<br/>`;
                    params.forEach(param => {
                        result += `${param.seriesName}: ${(param.value[1] || 0).toFixed(2)}<br/>`;
                    });
                    return result;
                }
            },
            legend: { data: series.map(s => s.name), top: 40, left: 'center', type: 'scroll' },
            grid: { left: '8%', right: '8%', bottom: '20%', top: '25%' },
            xAxis: {
                type: 'value',
                name: '相对时间 (秒)',
                nameLocation: 'middle',
                nameGap: 30,
                min: xMin - xPadding,
                max: xMax + xPadding,
                axisLabel: {
                    formatter: (value) => {
                        return value + 's';
                    }
                }
            },
            yAxis: {
                type: 'value',
                min: yMin - yPadding,
                max: yMax + yPadding,
                axisLabel: {
                    formatter: function(value) {
                        return value.toFixed(2);
                    }
                }
            },
            dataZoom: [{ type: 'inside', start: 0, end: 100 }, { start: 0, end: 100 }],
            toolbox: { right: 20, feature: { restore: {}, saveAsImage: {}, dataView: { readOnly: true } } },
            series: series
        };

        this.chart.setOption(option, true);
    }

    toggleInputData() {
        this.curveVisibility.input = !this.curveVisibility.input;
        const btn = this.shadowRoot.getElementById('toggleInputBtn');
        if (btn) btn.classList.toggle('inactive', !this.curveVisibility.input);
        // 根据当前图表类型调用正确的更新方法
        if (this.currentChartData && this.currentChartData.type === 'comparison') {
            this.updateComparisonChart(this.currentChartData.data);
        } else {
            this.updateChart();
        }
    }

    toggleOutputData() {
        this.curveVisibility.output = !this.curveVisibility.output;
        const btn = this.shadowRoot.getElementById('toggleOutputBtn');
        if (btn) btn.classList.toggle('inactive', !this.curveVisibility.output);
        // 根据当前图表类型调用正确的更新方法
        if (this.currentChartData && this.currentChartData.type === 'comparison') {
            this.updateComparisonChart(this.currentChartData.data);
        } else {
            this.updateChart();
        }
    }

    handleStatusFilter(value) {
        this.currentFilter.status = value;
        this.currentPage = 1;
        this.loadRecordsFromAPI();
    }

    showReportLimitHelp() {
        const modalTitle = this.shadowRoot.getElementById('modalTitle');
        const modalBody = this.shadowRoot.getElementById('modalBody');
        const modalFooter = this.shadowRoot.getElementById('modalFooter');

        modalTitle.textContent = '报告数据限制说明';
        modalBody.innerHTML = `
            <div style="padding: 20px 0; line-height: 1.8;">
                <p style="margin-bottom: 15px; font-weight: 500; color: #1f2329;">
                    📊 报告数据限制
                </p>
                <p style="margin-bottom: 15px; color: #646a73;">
                    为保证报告生成性能，报告仅显示用户指定数量的数据行（K条）。
                </p>

                <div style="background: #f0f7ff; border-left: 4px solid #2969ff; padding: 15px; margin: 20px 0; border-radius: 4px;">
                    <p style="margin: 0 0 10px 0; font-weight: 500; color: #2969ff;">
                        💡 如何访问完整数据集：
                    </p>
                    <ul style="margin: 0; padding-left: 20px; color: #646a73;">
                        <li style="margin-bottom: 8px;">使用"导出"功能下载完整数据集</li>
                        <li style="margin-bottom: 8px;">通过数据资源库查询直接获取完整数据</li>
                        <li style="margin-bottom: 8px;">调整报告数据限制参数以显示更多数据</li>
                        <li>选择合适的采样算法以优化数据展示</li>
                    </ul>
                </div>

                <p style="margin-bottom: 15px; font-weight: 500; color: #1f2329;">
                    📋 采样算法说明：
                </p>
                <ul style="margin: 0; padding-left: 20px; color: #646a73;">
                    <li style="margin-bottom: 8px;"><strong>均匀采样</strong>：在整个数据范围内均匀采样，保持数据分布特征</li>
                    <li style="margin-bottom: 8px;"><strong>随机采样</strong>：随机选择K条数据，适合大数据集的快速预览</li>
                    <li style="margin-bottom: 8px;"><strong>取前N条</strong>：选择数据集的前N条，适合查看最新数据</li>
                    <li><strong>取后N条</strong>：选择数据集的后N条，适合查看历史数据</li>
                </ul>
            </div>
        `;

        modalFooter.innerHTML = `
            <button class="modal-btn secondary" id="closeHelp">关闭</button>
        `;

        this.showModal();

        const closeBtn = this.shadowRoot.getElementById('closeHelp');
        const modalClose = this.shadowRoot.getElementById('modalClose');

        if (closeBtn) {
            closeBtn.addEventListener('click', () => this.hideModal());
        }
        if (modalClose) {
            modalClose.addEventListener('click', () => this.hideModal());
        }
    }

    handleSelectAll(checked) {
        const checkboxes = this.shadowRoot.querySelectorAll('.checkbox-item');
        checkboxes.forEach(cb => { cb.checked = checked; });
    }

    handleCompareSelected() {
        const selectedCheckboxes = this.shadowRoot.querySelectorAll('.checkbox-item:checked');

        if (selectedCheckboxes.length === 0) {
            this.showToast('请先选择要对比的仿真记录', 'warning');
            return;
        }

        if (selectedCheckboxes.length < 2) {
            this.showToast('请至少选择2条记录进行对比', 'warning');
            return;
        }

        if (selectedCheckboxes.length > 5) {
            this.showToast('对比记录数量不能超过5个，请重新选择', 'warning');
            return;
        }

        const selectedIds = Array.from(selectedCheckboxes).map(cb => cb.dataset.id);

        // 检查选中记录的状态
        const selectedRecords = this.allData.filter(record => selectedIds.includes(String(record.createTime)));
        const nonSuccessRecords = selectedRecords.filter(r => r.status !== 'completed' && r.status !== 'stopped');

        if (nonSuccessRecords.length > 0) {
            const names = nonSuccessRecords.map(r => `${r.name}(${this.getStatusText(r.status)})`).join(', ');
            this.showToast(`只能对比成功或已完成状态的记录，以下不符合条件：${names}`, 'warning');
            return;
        }

        this.showToast(`正在对比 ${selectedIds.length} 条选中的仿真记录`, 'success');
        this.showComparisonChart(selectedIds);
    }

    async showComparisonChart(selectedIds) {
        const selectedRecords = this.allData.filter(record => selectedIds.includes(String(record.createTime)));

        if (selectedRecords.length === 0) {
            this.showToast('没有找到选中的仿真记录数据', 'error');
            return;
        }

        try {
            if (window.showGlobalLoading) window.showGlobalLoading('正在加载对比数据...');

            const tasksData = [];
            for (const record of selectedRecords) {
                // 参考handleAnalyze的实现，从IginX查询输入数据，从CSV解析输出数据
                const taskData = await this.queryDataForComparison(record);
                if (taskData) {
                    tasksData.push(taskData);
                }
            }

            if (tasksData.length === 0) {
                this.showToast('没有获取到任何记录的数据', 'warning');
                return;
            }

            // 生成对比数据
            const comparisonData = this.generateComparisonDataFromQuery(tasksData);

            this.currentChartData = {
                type: 'comparison',
                data: comparisonData,
                selectedIds: selectedIds
            };

            if (!this.chart) {
                this.initChart();
                setTimeout(() => this.updateComparisonChart(comparisonData), 200);
            } else {
                this.updateComparisonChart(comparisonData);
            }

            this.showToast('对比数据加载完成');
        } catch (error) {
            console.error('对比仿真记录失败:', error);
            this.showToast('获取对比数据失败，请重试', 'error');
        } finally {
            if (window.hideGlobalLoading) window.hideGlobalLoading();
        }
    }

    // 查询对比数据 - 参考handleAnalyze的实现
    async queryDataForComparison(record) {
        try {
            let inputPaths = [];
            let outputPaths = [];
            let inputDataFromIginX = null;
            let outputDataFromCsv = null;
            let parsedResult = null;

            // 从record中获取测点路径
            if (record.inputMeasurements) {
                try {
                    inputPaths = JSON.parse(record.inputMeasurements);
                } catch (e) {
                    console.error('解析inputMeasurements失败:', e);
                }
            }

            if (record.outputMeasurements) {
                try {
                    outputPaths = JSON.parse(record.outputMeasurements);
                } catch (e) {
                    console.error('解析outputMeasurements失败:', e);
                }
            }

            // 解析result获取CSV表头信息
            if (record.result) {
                try {
                    parsedResult = typeof record.result === 'string' ? JSON.parse(record.result) : record.result;
                } catch (e) {
                    console.error('解析result失败:', e);
                }
            }

            // 查询输入数据（从IginX）
            if (inputPaths.length > 0) {
                try {
                    const requestBody = {
                        paths: inputPaths,
                        startTime: record.startTime,
                        endTime: record.endTime,
                        aggregateType: null,
                        precision: 0,
                        align: false
                    };
                    
                    const queryResult = await window.AppConfig.post('data', 'query', requestBody);
                    
                    if (queryResult.success && queryResult.data && queryResult.data.records) {
                        inputDataFromIginX = this.processQueryData(queryResult.data, inputPaths, []);
                    }
                } catch (e) {
                    console.error('从IginX查询输入数据失败:', e);
                }
            }

            // 输出数据从CSV解析
            if (parsedResult && parsedResult.results) {
                const firstNodeKey = Object.keys(parsedResult.results)[0];
                if (firstNodeKey) {
                    const nodeResult = parsedResult.results[firstNodeKey];
                    if (nodeResult.outputCsv) {
                        const outputCsvData = this.parseOutputCsv(nodeResult.outputCsv);
                        outputDataFromCsv = this.convertCsvToChartData(outputCsvData);
                    }
                }
            }

            // 构建任务数据 - 参考visual-analysis的格式，保留按路径分组的数据
            if (inputDataFromIginX || outputDataFromCsv) {
                return {
                    id: record.createTime,
                    name: record.name || '仿真任务',
                    inputData: inputDataFromIginX ? inputDataFromIginX.inputData : {},
                    outputData: outputDataFromCsv ? this.convertFlatToPathData(outputDataFromCsv, outputPaths) : {},
                    inputPaths: inputPaths,
                    outputPaths: outputPaths
                };
            }

            return null;
        } catch (error) {
            console.error('数据查询异常:', error);
            return null;
        }
    }

    // 将扁平化的CSV数据转换为按路径分组的数据
    convertFlatToPathData(flatData, paths) {
        const pathData = {};
        paths.forEach(path => {
            pathData[path] = [];
        });
        
        if (flatData && flatData.length > 0) {
            // 假设flatData是 [timestamp, value1, value2, ...] 格式
            flatData.forEach(point => {
                if (Array.isArray(point) && point.length >= 2) {
                    const timestamp = point[0];
                    paths.forEach((path, index) => {
                        if (point[index + 1] !== undefined && point[index + 1] !== null) {
                            pathData[path].push({
                                timestamp: timestamp,
                                value: point[index + 1]
                            });
                        }
                    });
                }
            });
        }
        
        return pathData;
    }

    // 从查询数据生成对比数据 - 参考visual-analysis的generateComparisonDataFromRealData
    generateComparisonDataFromQuery(tasksData) {
        const comparisonData = {
            tasks: [],
            timePoints: [],
            frequencyInconsistent: false,
            targetFrequency: 10
        };

        let baseTime = null;
        const taskFrequencies = [];

        tasksData.forEach((taskData) => {
            let taskMinTime = null;
            let taskMaxTime = null;
            let timePoints = [];

            // 收集任务的所有时间点
            [...Object.values(taskData.inputData || {}), ...Object.values(taskData.outputData || {})].forEach(pathData => {
                pathData.forEach(point => {
                    if (point.timestamp) {
                        timePoints.push(point.timestamp);
                        if (taskMinTime === null || point.timestamp < taskMinTime) {
                            taskMinTime = point.timestamp;
                        }
                        if (taskMaxTime === null || point.timestamp > taskMaxTime) {
                            taskMaxTime = point.timestamp;
                        }
                    }
                });
            });

            // 计算任务的采样频率
            if (timePoints.length > 1) {
                timePoints.sort((a, b) => a - b);
                const intervals = [];
                for (let i = 1; i < timePoints.length; i++) {
                    intervals.push((timePoints[i] - timePoints[i-1]) / 1000);
                }
                intervals.sort((a, b) => a - b);
                const medianInterval = intervals[Math.floor(intervals.length / 2)];
                taskFrequencies.push(medianInterval);

                if (baseTime === null || taskMinTime < baseTime) {
                    baseTime = taskMinTime;
                }
            }
        });

        if (baseTime === null) {
            baseTime = Date.now();
        }

        // 检查采样频率是否一致
        if (taskFrequencies.length > 1) {
            const uniqueFrequencies = [...new Set(taskFrequencies.map(f => Math.round(f)))];
            if (uniqueFrequencies.length > 1) {
                comparisonData.frequencyInconsistent = true;
                comparisonData.targetFrequency = Math.max(...taskFrequencies);
            } else {
                comparisonData.targetFrequency = taskFrequencies[0];
            }
        }

        // 为每个任务处理真实数据
        tasksData.forEach((taskData) => {
            const task = {
                id: taskData.id,
                name: taskData.name,
                samplingInterval: comparisonData.targetFrequency,
                inputData: [],
                calculationResult: [],
                inputPaths: [], // 保存输入路径信息
                outputPaths: []  // 保存输出路径信息
            };

            // 处理输入数据，转换为相对时间并保存路径信息
            if (taskData.inputData) {
                Object.keys(taskData.inputData).forEach(path => {
                    task.inputPaths.push(path); // 保存路径名
                    taskData.inputData[path].forEach(point => {
                        if (point && point.timestamp !== undefined && point.timestamp !== null && point.value !== undefined && point.value !== null) {
                            const relativeTime = (point.timestamp - baseTime) / 1000;
                            if (isFinite(relativeTime) && isFinite(point.value)) {
                                task.inputData.push([relativeTime, point.value]);
                            }
                        }
                    });
                });
            }

            // 处理输出数据，转换为相对时间并保存路径信息
            if (taskData.outputData) {
                Object.keys(taskData.outputData).forEach(path => {
                    task.outputPaths.push(path); // 保存路径名
                    taskData.outputData[path].forEach(point => {
                        if (point && point.timestamp !== undefined && point.timestamp !== null && point.value !== undefined && point.value !== null) {
                            const relativeTime = (point.timestamp - baseTime) / 1000;
                            if (isFinite(relativeTime) && isFinite(point.value)) {
                                task.calculationResult.push([relativeTime, point.value]);
                            }
                        }
                    });
                });
            }

            // 对数据进行频率对齐处理，并确保从0开始
            // 对输入数据进行对齐处理
            if (task.inputData && task.inputData.length > 0) {
                task.inputData.sort((a, b) => a[0] - b[0]);
                // 找到最小时间点
                const minTime = Math.min(...task.inputData.map(point => point[0]));
                // 将所有时间点对齐到0
                task.inputData = task.inputData.map(point => [point[0] - minTime, point[1]]);

                if (comparisonData.frequencyInconsistent) {
                    task.inputData = this.alignDataSeries(task.inputData, comparisonData.targetFrequency);
                }
            }

            // 对输出数据进行对齐处理
            if (task.calculationResult && task.calculationResult.length > 0) {
                task.calculationResult.sort((a, b) => a[0] - b[0]);
                // 找到最小时间点
                const minTime = Math.min(...task.calculationResult.map(point => point[0]));
                // 将所有时间点对齐到0
                task.calculationResult = task.calculationResult.map(point => [point[0] - minTime, point[1]]);

                if (comparisonData.frequencyInconsistent) {
                    task.calculationResult = this.alignDataSeries(task.calculationResult, comparisonData.targetFrequency);
                }
            }

            comparisonData.tasks.push(task);
        });

        return comparisonData;
    }

    generateComparisonData(tasksData) {
        const comparisonData = {
            tasks: [],
            timePoints: [],
            frequencyInconsistent: false,
            targetFrequency: 10
        };

        let baseTime = null;
        const taskFrequencies = [];

        tasksData.forEach(taskData => {
            let taskMinTime = null;
            let timePoints = [];

            taskData.nodes.forEach(node => {
                [...(node.inputData || []), ...(node.calculationResult || [])].forEach(point => {
                    if (point && point[0] !== undefined) {
                        timePoints.push(point[0]);
                        if (taskMinTime === null || point[0] < taskMinTime) taskMinTime = point[0];
                    }
                });
            });

            if (timePoints.length > 1) {
                timePoints.sort((a, b) => a - b);
                const intervals = [];
                for (let i = 1; i < timePoints.length; i++) {
                    intervals.push((timePoints[i] - timePoints[i - 1]) / 1000);
                }
                intervals.sort((a, b) => a - b);
                const medianInterval = intervals[Math.floor(intervals.length / 2)];
                taskFrequencies.push(medianInterval);
                if (baseTime === null || taskMinTime < baseTime) baseTime = taskMinTime;
            }
        });

        if (baseTime === null) baseTime = Date.now();

        if (taskFrequencies.length > 1) {
            const uniqueFrequencies = [...new Set(taskFrequencies.map(f => Math.round(f)))];
            if (uniqueFrequencies.length > 1) {
                comparisonData.frequencyInconsistent = true;
                comparisonData.targetFrequency = Math.max(...taskFrequencies);
                this.showToast('检测到采样频率不一致，系统将自动进行数据对齐处理', 'info');
            } else {
                comparisonData.targetFrequency = taskFrequencies[0];
            }
        }

        tasksData.forEach(taskData => {
            taskData.nodes.forEach(node => {
                const task = {
                    id: taskData.id,
                    name: node.name,
                    samplingInterval: comparisonData.targetFrequency,
                    inputData: [],
                    calculationResult: [],
                    inputPaths: node.inputPaths || [],
                    outputPaths: node.outputPaths || []
                };

                (node.inputData || []).forEach(point => {
                    if (point && isFinite(point[0]) && isFinite(point[1])) {
                        const relativeTime = (point[0] - baseTime) / 1000;
                        task.inputData.push([relativeTime, point[1]]);
                    }
                });

                (node.calculationResult || []).forEach(point => {
                    if (point && isFinite(point[0]) && isFinite(point[1])) {
                        const relativeTime = (point[0] - baseTime) / 1000;
                        task.calculationResult.push([relativeTime, point[1]]);
                    }
                });

                if (task.inputData.length > 0) {
                    const minTime = Math.min(...task.inputData.map(p => p[0]));
                    task.inputData = task.inputData.map(p => [p[0] - minTime, p[1]]);
                    if (comparisonData.frequencyInconsistent) {
                        task.inputData = this.alignDataSeries(task.inputData, comparisonData.targetFrequency);
                    }
                }

                if (task.calculationResult.length > 0) {
                    const minTime = Math.min(...task.calculationResult.map(p => p[0]));
                    task.calculationResult = task.calculationResult.map(p => [p[0] - minTime, p[1]]);
                    if (comparisonData.frequencyInconsistent) {
                        task.calculationResult = this.alignDataSeries(task.calculationResult, comparisonData.targetFrequency);
                    }
                }

                comparisonData.tasks.push(task);
            });
        });

        const allTimePoints = comparisonData.tasks.flatMap(task =>
            [...task.inputData, ...task.calculationResult]
                .filter(p => p && isFinite(p[0]))
                .map(p => p[0])
        );

        let maxTime = 0;
        if (allTimePoints.length > 0) maxTime = Math.max(...allTimePoints);
        if (!isFinite(maxTime) || maxTime < 0) maxTime = 100;

        const maxPoints = 1000;
        const estimatedPoints = Math.floor(maxTime / comparisonData.targetFrequency);
        if (estimatedPoints > maxPoints) {
            comparisonData.targetFrequency = Math.ceil(maxTime / maxPoints);
        }

        for (let time = 0; time <= maxTime; time += comparisonData.targetFrequency) {
            comparisonData.timePoints.push(time);
        }

        return comparisonData;
    }

    alignDataSeries(data, targetInterval) {
        if (!data || data.length === 0) return data;
        const alignedData = [];
        const maxTime = data[data.length - 1][0];
        for (let time = 0; time <= maxTime; time += targetInterval) {
            const interpolated = this.interpolateData(data, time);
            if (interpolated !== null) {
                alignedData.push([time, interpolated]);
            }
        }
        return alignedData;
    }

    interpolateData(data, time) {
        if (!data || data.length === 0) return null;
        let leftPoint = null;
        let rightPoint = null;
        for (let i = 0; i < data.length - 1; i++) {
            if (data[i][0] <= time && data[i + 1][0] >= time) {
                leftPoint = data[i];
                rightPoint = data[i + 1];
                break;
            }
        }
        if (leftPoint && rightPoint) {
            const ratio = (time - leftPoint[0]) / (rightPoint[0] - leftPoint[0]);
            return parseFloat((leftPoint[1] + ratio * (rightPoint[1] - leftPoint[1])).toFixed(2));
        } else if (leftPoint && leftPoint[0] === time) {
            return leftPoint[1];
        }
        return null;
    }

    updateComparisonChart(comparisonData) {
        if (!this.chart) return;

        const series = [];
        const colors = ['#1890ff', '#52c41a', '#faad14', '#f5222d', '#722ed1', '#13c2c2'];
        const pathSeriesMap = {};

        comparisonData.tasks.forEach((task, taskIdx) => {
            const taskColor = colors[taskIdx % colors.length];
            // 使用id字段作为唯一标识（id就是timestamp）
            const taskTimestamp = task.id || Date.now();
            const taskTimeLabel = new Date(taskTimestamp).toLocaleString();

            if (this.curveVisibility.input && task.inputData && task.inputData.length > 0 && task.inputPaths) {
                task.inputPaths.forEach((pathName, pathIndex) => {
                    const pointsPerPath = Math.ceil(task.inputData.length / task.inputPaths.length);
                    const startIndex = pathIndex * pointsPerPath;
                    const endIndex = Math.min(startIndex + pointsPerPath, task.inputData.length);
                    const pathData = task.inputData.slice(startIndex, endIndex);

                    const isNumeric = pathData.some(p => p && Array.isArray(p) && p.length === 2 && typeof p[1] === 'number');
                    if (!isNumeric) return;

                    if (pathData.length > 0) {
                        // 按时间排序，确保曲线连续（参考单个分析）
                        pathData.sort((a, b) => a[0] - b[0]);
                        const seriesKey = `${pathName}_input_${taskTimestamp}`;
                        pathSeriesMap[seriesKey] = { data: pathData, color: taskColor, pathName, taskName: task.name, taskTimeLabel, type: 'input' };
                    }
                });
            }

            if (this.curveVisibility.output && task.calculationResult && task.calculationResult.length > 0 && task.outputPaths) {
                task.outputPaths.forEach((pathName, pathIndex) => {
                    const pointsPerPath = Math.ceil(task.calculationResult.length / task.outputPaths.length);
                    const startIndex = pathIndex * pointsPerPath;
                    const endIndex = Math.min(startIndex + pointsPerPath, task.calculationResult.length);
                    const pathData = task.calculationResult.slice(startIndex, endIndex);

                    const isNumeric = pathData.some(p => p && Array.isArray(p) && p.length === 2 && typeof p[1] === 'number');
                    if (!isNumeric) return;

                    if (pathData.length > 0) {
                        // 按时间排序，确保曲线连续（参考单个分析）
                        pathData.sort((a, b) => a[0] - b[0]);
                        const seriesKey = `${pathName}_output_${taskTimestamp}`;
                        pathSeriesMap[seriesKey] = { data: pathData, color: taskColor, pathName, taskName: task.name, taskTimeLabel, type: 'output' };
                    }
                });
            }
        });

        Object.values(pathSeriesMap).forEach(seriesData => {
            const validData = seriesData.data.filter(p => p && Array.isArray(p) && p.length === 2 && isFinite(p[0]) && isFinite(p[1]));
            if (validData.length > 0) {
                if (seriesData.type === 'input') {
                    series.push({
                        name: `${seriesData.pathName} (${seriesData.taskName} ${seriesData.taskTimeLabel}输入)`,
                        type: 'line', data: validData, smooth: true, symbol: 'circle', symbolSize: 3,
                        lineStyle: { width: 2, color: seriesData.color, type: 'dashed' },
                        itemStyle: { color: seriesData.color }
                    });
                } else {
                    series.push({
                        name: `${seriesData.pathName} (${seriesData.taskName} ${seriesData.taskTimeLabel}输出)`,
                        type: 'line', data: validData, smooth: true, symbol: 'diamond', symbolSize: 3,
                        lineStyle: { width: 2, color: seriesData.color, type: 'solid' },
                        itemStyle: { color: seriesData.color }
                    });
                }
            }
        });

        // 动态计算x轴和y轴的范围（参考单个分析）
        let allDataPoints = [];
        series.forEach(s => {
            if (s.data) {
                allDataPoints = allDataPoints.concat(s.data);
            }
        });

        let xMin = Infinity, xMax = -Infinity;
        let yMin = Infinity, yMax = -Infinity;
        
        allDataPoints.forEach(point => {
            if (point[0] < xMin) xMin = point[0];
            if (point[0] > xMax) xMax = point[0];
            if (point[1] < yMin) yMin = point[1];
            if (point[1] > yMax) yMax = point[1];
        });

        if (xMin === Infinity) xMin = 0;
        if (xMax === -Infinity) xMax = 100;
        if (yMin === Infinity) yMin = 0;
        if (yMax === -Infinity) yMax = 100;

        const xPadding = (xMax - xMin) * 0.05 || 1;
        const yPadding = (yMax - yMin) * 0.1 || 1;

        const option = {
            title: { text: '多记录对比分析 - 相对时间', left: 'center', top: 10, textStyle: { fontSize: 14, fontWeight: 'bold' } },
            tooltip: {
                trigger: 'axis',
                formatter: function(params) {
                    if (!params || params.length === 0) return '';
                    const time = params[0].value[0];
                    let result = `相对时间: ${time.toFixed(1)}s<br/>`;
                    params.forEach(param => {
                        result += `${param.seriesName}: ${(param.value[1] || 0).toFixed(2)}<br/>`;
                    });
                    return result;
                }
            },
            legend: { data: series.map(s => s.name), top: 40, left: 'center', type: 'scroll' },
            grid: { left: '8%', right: '8%', bottom: '20%', top: '25%' },
            xAxis: {
                type: 'value',
                min: Math.max(0, xMin - xPadding),
                max: xMax + xPadding,
                name: '相对时间 (秒)',
                nameLocation: 'middle',
                nameGap: 30,
                axisLabel: {
                    formatter: function(value) {
                        return value + 's';
                    }
                }
            },
            yAxis: {
                type: 'value',
                min: yMin - yPadding,
                max: yMax + yPadding,
                axisLabel: { formatter: v => v.toFixed(2) }
            },
            dataZoom: [{ type: 'inside', start: 0, end: 100 }, { start: 0, end: 100 }],
            toolbox: { right: 20, feature: { restore: {}, saveAsImage: {}, dataView: { readOnly: true } } },
            series: series
        };

        this.chart.setOption(option, true);
    }

    async loadRecordsFromAPI() {
        try {
            if (window.showGlobalLoading) window.showGlobalLoading('正在查询仿真执行记录...');

            const nameFilter = this.shadowRoot.getElementById('nameSearch')?.value.trim();
            const statusFilter = this.shadowRoot.getElementById('statusFilter')?.value;
            const startTime = this.shadowRoot.getElementById('startTime')?.value;
            const endTime = this.shadowRoot.getElementById('endTime')?.value;

            const requestParams = {
                archiveName: nameFilter || null,
                status: statusFilter || null,
                startTime: startTime ? new Date(startTime).getTime() : null,
                endTime: endTime ? new Date(endTime).getTime() : null,
                pageNum: this.currentPage,
                pageSize: this.pageSize
            };

            const result = await window.AppConfig.post('simulationArchives', 'execution-records', requestParams);

            if (result.success && result.data) {
                this.displayData = result.data.map(execution => {
                    return {
                        createTime: execution.timestamp || execution.archiveId,
                        timestamp: execution.timestamp,
                        archiveId: execution.archiveId,
                        name: execution.archiveName || '-',
                        startTime: execution.startTime,
                        endTime: execution.endTime,
                        status: execution.status || 'unknown',
                        error: execution.error || '',
                        time: execution.startTime ? new Date(execution.startTime).toLocaleString() : '-',
                        inputMeasurements: execution.inputMeasurements,
                        outputMeasurements: execution.outputMeasurements,
                        result: execution.result
                    };
                });
                this.allData = this.displayData;

                if (this.currentPage === 1) {
                    await this.loadRecordsCount(nameFilter, statusFilter, startTime, endTime);
                }
                this.updateTable();
            } else {
                this.displayData = [];
                this.allData = [];
                this.updateTable();
            }
        } catch (error) {
            console.error('查询仿真执行记录失败:', error);
            this.displayData = [];
            this.allData = [];
            this.updateTable();
        } finally {
            if (window.hideGlobalLoading) window.hideGlobalLoading();
        }
    }

    async loadRecordsCount(name, status, startTime, endTime) {
        try {
            const requestParams = {
                archiveName: name || null,
                status: status || null,
                startTime: startTime ? new Date(startTime).getTime() : null,
                endTime: endTime ? new Date(endTime).getTime() : null
            };

            const result = await window.AppConfig.post('simulationArchives', 'execution-records-count', requestParams);
            if (result.success && result.data !== undefined) {
                this.totalCount = result.data;
                this.updatePagination();
            } else {
                this.totalCount = this.displayData.length;
            }
        } catch (error) {
            this.totalCount = this.displayData.length;
        }
    }

    updateTable() {
        const tbody = this.shadowRoot.getElementById('tableBody');
        if (!tbody) return;

        if (this.displayData.length === 0) {
            tbody.innerHTML = `<tr><td colspan="8" style="text-align: center; padding: 40px; color: #999;">暂无仿真执行记录</td></tr>`;
            return;
        }

        tbody.innerHTML = '';

        this.displayData.forEach(record => {
            const tr = document.createElement('tr');

            // 复选框列
            const checkboxTd = document.createElement('td');
            checkboxTd.style.textAlign = 'center';
            const checkbox = document.createElement('input');
            checkbox.type = 'checkbox';
            checkbox.className = 'checkbox-item';
            checkbox.dataset.id = record.timestamp || record.createTime;
            checkboxTd.appendChild(checkbox);
            tr.appendChild(checkboxTd);

            // 档案名称列
            const nameTd = document.createElement('td');
            nameTd.textContent = record.name || '-';
            tr.appendChild(nameTd);

            // 执行时间列（timestamp）
            const timestampTd = document.createElement('td');
            timestampTd.textContent = record.timestamp ? new Date(record.timestamp).toLocaleString() : '-';
            tr.appendChild(timestampTd);

            // 开始时间列
            const startTimeTd = document.createElement('td');
            startTimeTd.textContent = record.startTime ? new Date(record.startTime).toLocaleString() : '-';
            tr.appendChild(startTimeTd);

            // 结束时间列
            const endTimeTd = document.createElement('td');
            endTimeTd.textContent = record.endTime ? new Date(record.endTime).toLocaleString() : '-';
            tr.appendChild(endTimeTd);

            // 运行状态列
            const statusTd = document.createElement('td');
            const statusBadge = document.createElement('span');
            statusBadge.className = `status-badge ${record.status}`;
            statusBadge.textContent = this.getStatusText(record.status);
            statusTd.appendChild(statusBadge);
            tr.appendChild(statusTd);

            // 错误信息列
            const errorTd = document.createElement('td');
            errorTd.textContent = record.error || '-';
            errorTd.style.maxWidth = '200px';
            errorTd.style.overflow = 'hidden';
            errorTd.style.textOverflow = 'ellipsis';
            errorTd.style.whiteSpace = 'nowrap';
            errorTd.title = record.error || '';
            tr.appendChild(errorTd);

            // 操作列
            const actionTd = document.createElement('td');
            const actionButtons = document.createElement('div');
            actionButtons.className = 'action-buttons';

            // 分析按钮（仅成功/已停止/已完成状态显示）
            if (record.status === 'completed' || record.status === 'stopped') {
                const analyzeBtn = document.createElement('button');
                analyzeBtn.className = 'action-btn analyze';
                analyzeBtn.textContent = '分析';
                analyzeBtn.onclick = () => this.handleAnalyze(record);
                actionButtons.appendChild(analyzeBtn);

                // 生成报告按钮
                const reportBtn = document.createElement('button');
                reportBtn.className = 'action-btn report';
                reportBtn.textContent = '生成报告';
                reportBtn.onclick = () => this.handleGenerateReport(record);
                actionButtons.appendChild(reportBtn);

                // 导出按钮
                const exportBtn = document.createElement('button');
                exportBtn.className = 'action-btn export';
                exportBtn.textContent = '导出';
                exportBtn.onclick = () => this.handleExport(record);
                actionButtons.appendChild(exportBtn);
            }

            // 查看日志按钮
            const viewLogBtn = document.createElement('button');
            viewLogBtn.className = 'action-btn view-log';
            viewLogBtn.textContent = '查看日志';
            viewLogBtn.onclick = () => this.handleViewLog(record);
            actionButtons.appendChild(viewLogBtn);

            // 删除按钮
            const deleteBtn = document.createElement('button');
            deleteBtn.className = 'action-btn delete';
            deleteBtn.textContent = '删除';
            deleteBtn.onclick = () => this.handleDelete(record);
            actionButtons.appendChild(deleteBtn);

            // 停止按钮（运行中状态显示）
            if (record.status === 'running') {
                const stopBtn = document.createElement('button');
                stopBtn.className = 'action-btn stop';
                stopBtn.textContent = '停止';
                stopBtn.onclick = () => this.handleStop(record);
                actionButtons.appendChild(stopBtn);
            }

            actionTd.appendChild(actionButtons);
            tr.appendChild(actionTd);

            tbody.appendChild(tr);
        });
    }

    getStatusText(status) {
        const map = { running: '运行中', stopped: '已停止', completed: '成功', failed: '失败', pending: '等待中' };
        return map[status] || status;
    }

    // ==================== 六大操作按钮处理 ====================

    // 处理分析操作
    async handleAnalyze(record) {
        console.log('handleAnalyze被调用，record:', record);
        
        if (record.status !== 'completed' && record.status !== 'stopped') {
            this.showToast('只能分析成功或已完成的仿真记录', 'warning');
            return;
        }

        console.log('状态检查通过，开始分析');
        if (window.showGlobalLoading) window.showGlobalLoading('正在加载分析数据...');

        try {
            console.log('开始try块');
            const tasks = [];
            let inputDataFromIginX = null;
            let outputDataFromIginX = null;
            let inputPaths = [];
            let outputPaths = [];
            let parsedResult = null;

            console.log('record.inputMeasurements:', record.inputMeasurements);
            console.log('record.outputMeasurements:', record.outputMeasurements);
            console.log('record.result:', record.result);

            // 从record中获取测点路径
            if (record.inputMeasurements) {
                try {
                    inputPaths = JSON.parse(record.inputMeasurements);
                    console.log('从record.inputMeasurements解析:', inputPaths);
                } catch (e) {
                    console.error('解析inputMeasurements失败:', e);
                }
            }

            if (record.outputMeasurements) {
                try {
                    outputPaths = JSON.parse(record.outputMeasurements);
                    console.log('从record.outputMeasurements解析:', outputPaths);
                } catch (e) {
                    console.error('解析outputMeasurements失败:', e);
                }
            }

            console.log('inputPaths长度:', inputPaths.length);
            console.log('outputPaths长度:', outputPaths.length);

            // 解析result获取CSV表头信息
            if (record.result) {
                try {
                    parsedResult = typeof record.result === 'string' ? JSON.parse(record.result) : record.result;
                    console.log('解析后的result:', parsedResult);
                } catch (e) {
                    console.error('解析result失败:', e);
                }
            }

            // 查询输入数据
            if (inputPaths.length > 0) {
                try {
                    const requestBody = {
                        paths: inputPaths,
                        startTime: record.startTime,
                        endTime: record.endTime,
                        aggregateType: null,
                        precision: 0,
                        align: false
                    };
                    console.log('查询IginX输入数据参数:', requestBody);
                    
                    const queryResult = await window.AppConfig.post('data', 'query', requestBody);
                    console.log('IginX输入数据查询结果:', queryResult);
                    
                    if (queryResult.success && queryResult.data && queryResult.data.records) {
                        inputDataFromIginX = this.processQueryData(queryResult.data, inputPaths, []);
                        console.log('转换后的输入数据:', inputDataFromIginX);
                    }
                } catch (e) {
                    console.error('从IginX查询输入数据失败:', e);
                }
            }

            // 输出数据从CSV解析，不从IginX查询
            let outputDataFromCsv = null;
            let outputCsvData = null; // 保存CSV原始数据用于报告
            if (parsedResult && parsedResult.results) {
                const firstNodeKey = Object.keys(parsedResult.results)[0];
                if (firstNodeKey) {
                    const nodeResult = parsedResult.results[firstNodeKey];
                    if (nodeResult.outputCsv) {
                        outputCsvData = this.parseOutputCsv(nodeResult.outputCsv);
                        outputDataFromCsv = this.convertCsvToChartData(outputCsvData);
                        console.log('从CSV解析的输出数据:', outputDataFromCsv);
                        console.log('CSV原始数据:', outputCsvData);
                    }
                }
            }

            // 构建任务数据
            if (inputDataFromIginX || outputDataFromCsv) {
                const task = {
                    name: record.name || '仿真任务',
                    inputData: [],
                    calculationResult: [],
                    inputPaths: inputPaths,
                    outputPaths: outputPaths
                };

                // 处理输入数据
                if (inputDataFromIginX && inputDataFromIginX.inputData) {
                    const flatInputData = [];
                    Object.entries(inputDataFromIginX.inputData).forEach(([path, dataPoints]) => {
                        dataPoints.forEach(point => {
                            flatInputData.push([point.timestamp, point.value]);
                        });
                    });
                    flatInputData.sort((a, b) => a[0] - b[0]);
                    task.inputData = flatInputData;
                }

                // 处理输出数据（从CSV）
                if (outputDataFromCsv) {
                    task.calculationResult = outputDataFromCsv;
                }

                tasks.push(task);
            }

            this.currentChartData = { tasks, record, parsedResult, outputCsvData };

            if (!this.chart) {
                this.initChart();
            } else {
                this.updateChart();
            }
        } catch (error) {
            console.error('分析仿真记录失败:', error);
            this.showToast('分析出现错误，请重试', 'error');
        } finally {
            if (window.hideGlobalLoading) window.hideGlobalLoading();
        }
    }

    // 从查询结果中提取时间范围
    extractTimeRange(records) {
        if (!records || records.length === 0) return { startTime: null, endTime: null };
        
        let startTime = null;
        let endTime = null;
        
        records.forEach(record => {
            if (record.key) {
                try {
                    const timestamp = new Date(record.key).getTime();
                    if (!isNaN(timestamp)) {
                        if (startTime === null || timestamp < startTime) startTime = timestamp;
                        if (endTime === null || timestamp > endTime) endTime = timestamp;
                    }
                } catch (e) {
                    // 忽略时间解析错误
                }
            }
        });
        
        return { startTime, endTime };
    }

    // 处理查询数据（参考visual-analysis）
    processQueryData(queryResult, inputPaths, outputPaths) {
        const pathData = {};

        // 初始化路径数据
        [...inputPaths, ...outputPaths].forEach(path => {
            pathData[path] = [];
        });

        // 处理查询结果
        if (queryResult && queryResult.records && Array.isArray(queryResult.records)) {
            queryResult.records.forEach(record => {
                if (record.key) {
                    try {
                        const timestamp = new Date(record.key).getTime();
                        if (isNaN(timestamp)) return;

                        [...inputPaths, ...outputPaths].forEach(path => {
                            if (record[path] !== null && record[path] !== undefined) {
                                pathData[path].push({
                                    timestamp: timestamp,
                                    value: record[path]
                                });
                            }
                        });
                    } catch (error) {
                        console.warn('时间解析异常:', record.key, error);
                    }
                }
            });
        }

        // 区分输入和输出数据
        const inputData = {};
        const outputData = {};

        inputPaths.forEach(path => {
            inputData[path] = pathData[path] || [];
        });

        outputPaths.forEach(path => {
            outputData[path] = pathData[path] || [];
        });

        return { inputData, outputData, allPathData: pathData };
    }

    // 解析输出CSV数据
    parseOutputCsv(csvText) {
        if (!csvText) return { headers: [], rows: [] };
        
        const lines = csvText.trim().split('\n');
        if (lines.length < 2) return { headers: [], rows: [] };
        
        // 解析表头
        const headers = lines[0].split(',').map(h => h.trim());
        
        // 解析数据行
        const dataRows = [];
        for (let i = 1; i < lines.length; i++) {
            const line = lines[i].trim();
            if (!line) continue;
            
            const values = line.split(',').map(v => v.trim());
            if (values.length !== headers.length) continue;
            
            dataRows.push(values);
        }
        
        return { headers, rows: dataRows };
    }

    // 将CSV数据转换为图表数据格式
    convertCsvToChartData(csvData) {
        if (!csvData || !csvData.headers || csvData.headers.length === 0) return [];
        
        const { headers, rows } = csvData;
        
        // 检查是否有key列
        const hasKeyColumn = headers.some(h => h.toLowerCase() === 'key');
        
        // 转换为图表格式：每列作为一个系列
        const seriesData = [];
        
        headers.forEach((header, headerIdx) => {
            // 跳过key列（如果有）
            if (hasKeyColumn && header.toLowerCase() === 'key') return;
            // 如果没有key列，跳过第一列signal列
            if (!hasKeyColumn && headerIdx === 0) return;
            
            const series = [];
            rows.forEach((row, rowIdx) => {
                const value = parseFloat(row[headerIdx]);
                if (!isNaN(value)) {
                    // 使用索引作为x轴（因为没有时间戳）
                    series.push([rowIdx, value]);
                }
            });
            
            if (series.length > 0) {
                seriesData.push({
                    name: header,
                    data: series
                });
            }
        });
        
        // 如果只有一个系列，直接返回数据点
        if (seriesData.length === 1) {
            return seriesData[0].data;
        }
        
        // 如果有多个系列，返回第一个系列的数据（简化处理）
        return seriesData.length > 0 ? seriesData[0].data : [];
    }

    // 采样数据
    sampleData(data, maxRows = 20, samplingAlgorithm = 'uniform') {
        console.log(`sampleData调用: data.length=${data.length}, maxRows=${maxRows}, samplingAlgorithm=${samplingAlgorithm}`);
        
        if (!data || data.length === 0) {
            console.log('数据为空，直接返回');
            return data;
        }
        
        if (data.length <= maxRows) {
            console.log('数据行数在限制范围内，无需采样');
            return data;
        }
        
        const sampledData = [];
        
        switch (samplingAlgorithm) {
            case 'uniform':
                // 均匀采样 - 简化逻辑确保严格不超过maxRows
                console.log(`均匀采样计算: data.length=${data.length}, maxRows=${maxRows}`);
                
                // 计算采样间隔
                const interval = Math.ceil(data.length / maxRows);
                console.log(`采样间隔: ${interval}`);
                
                for (let i = 0; i < data.length; i += interval) {
                    if (sampledData.length >= maxRows) {
                        console.log(`达到maxRows ${maxRows}，停止采样`);
                        break;
                    }
                    sampledData.push(data[i]);
                    console.log(`添加索引 ${i}, 当前数量 ${sampledData.length}`);
                }
                
                // 强制截断到maxRows
                if (sampledData.length > maxRows) {
                    console.log(`截断前数量 ${sampledData.length}, 截断到 ${maxRows}`);
                    sampledData.length = maxRows;
                }
                console.log(`均匀采样完成：原始数据 ${data.length} 行，采样后 ${sampledData.length} 行`);
                break;
                
            case 'random':
                // 随机采样
                const indices = new Set();
                while (indices.size < maxRows) {
                    indices.add(Math.floor(Math.random() * data.length));
                }
                Array.from(indices).sort((a, b) => a - b).forEach(index => {
                    sampledData.push(data[index]);
                });
                console.log(`随机采样完成：原始数据 ${data.length} 行，采样后 ${sampledData.length} 行`);
                break;
                
            case 'first':
                // 取前N条
                for (let i = 0; i < maxRows; i++) {
                    sampledData.push(data[i]);
                }
                console.log(`取前N条采样完成：原始数据 ${data.length} 行，采样后 ${sampledData.length} 行`);
                break;
                
            case 'last':
                // 取后N条
                const startIndex = Math.max(0, data.length - maxRows);
                for (let i = startIndex; i < data.length; i++) {
                    sampledData.push(data[i]);
                }
                console.log(`取后N条采样完成：原始数据 ${data.length} 行，采样后 ${sampledData.length} 行`);
                break;
                
            default:
                console.log(`未知采样算法: ${samplingAlgorithm}，使用均匀采样`);
                const defaultInterval = Math.floor((data.length - 1) / (maxRows - 1));
                for (let i = 0; i < data.length; i += defaultInterval) {
                    if (sampledData.length >= maxRows) break;
                    sampledData.push(data[i]);
                }
                if (sampledData[sampledData.length - 1] !== data[data.length - 1] && sampledData.length < maxRows) {
                    sampledData.push(data[data.length - 1]);
                }
                if (sampledData.length > maxRows) {
                    sampledData.length = maxRows;
                }
        }
        
        return sampledData;
    }

    // 统一采样输入和输出数据
    sampleDataConsistently(inputData, outputData, maxRows = 100, samplingAlgorithm = 'uniform') {
        const result = {
            inputData: inputData ? {} : null,
            outputData: outputData ? {} : null
        };
        
        // 计算总数据量
        const totalInputCount = inputData ? Object.values(inputData).reduce((sum, data) => sum + (data ? data.length : 0), 0) : 0;
        const totalOutputCount = outputData ? Object.values(outputData).reduce((sum, data) => sum + (data ? data.length : 0), 0) : 0;
        const totalCount = totalInputCount + totalOutputCount;
        
        console.log(`准备采样 - 输入: ${totalInputCount}, 输出: ${totalOutputCount}, 总计: ${totalCount}`);
        
        if (totalCount > maxRows) {
            console.log(`数据量过大(${totalCount} > ${maxRows})，开始采样，算法: ${samplingAlgorithm}...`);
            
            // 对输入数据进行采样
            if (inputData) {
                Object.keys(inputData).forEach(path => {
                    const data = inputData[path];
                    if (data && data.length > 0) {
                        result.inputData[path] = this.sampleData(data, maxRows, samplingAlgorithm);
                    } else {
                        result.inputData[path] = data;
                    }
                });
            }
            
            // 对输出数据进行采样
            if (outputData) {
                Object.keys(outputData).forEach(path => {
                    const data = outputData[path];
                    if (data && data.length > 0) {
                        result.outputData[path] = this.sampleData(data, maxRows, samplingAlgorithm);
                    } else {
                        result.outputData[path] = data;
                    }
                });
            }
            
            const sampledInputCount = result.inputData ? Object.values(result.inputData).reduce((sum, data) => sum + (data ? data.length : 0), 0) : 0;
            const sampledOutputCount = result.outputData ? Object.values(result.outputData).reduce((sum, data) => sum + (data ? data.length : 0), 0) : 0;
            
            console.log(`统一采样完成 - 输入: ${totalInputCount} -> ${sampledInputCount}, 输出: ${totalOutputCount} -> ${sampledOutputCount}`);
        } else {
            // 数据量不大，直接使用原数据
            result.inputData = inputData;
            result.outputData = outputData;
            console.log('数据量在合理范围内，无需采样');
        }
        
        return result;
    }

    // 处理生成报告操作
    async handleGenerateReport(record) {
        // 先自动执行分析
        this.showToast('正在执行分析，请稍候...', 'info');

        // 执行分析
        await this.handleAnalyze(record);

        // 等待分析完成
        await new Promise(resolve => setTimeout(resolve, 1000));

        // 如果分析后仍然没有数据，显示错误
        if (!this.currentChartData) {
            this.showToast('分析失败，无法生成报告', 'error');
            return;
        }

        // 获取用户设置的数据限制和采样算法
        const reportDataLimitInput = this.shadowRoot.getElementById('reportDataLimit');
        const samplingAlgorithmSelect = this.shadowRoot.getElementById('samplingAlgorithm');
        
        const maxRows = reportDataLimitInput ? parseInt(reportDataLimitInput.value) || 20 : 20;
        const samplingAlgorithm = samplingAlgorithmSelect ? samplingAlgorithmSelect.value : 'uniform';
        
        console.log('报告数据限制设置:', maxRows, '采样算法:', samplingAlgorithm);

        // 对CSV输出数据进行采样
        let sampledOutputCsvData = this.currentChartData.outputCsvData;
        if (this.currentChartData.outputCsvData && this.currentChartData.outputCsvData.rows) {
            const originalRowCount = this.currentChartData.outputCsvData.rows.length;
            console.log('输出数据原始行数:', originalRowCount);
            if (originalRowCount > maxRows) {
                console.log(`输出数据行数过多(${originalRowCount} > ${maxRows})，开始采样...`);
                const sampledRows = this.sampleData(this.currentChartData.outputCsvData.rows, maxRows, samplingAlgorithm);
                console.log('输出数据采样后行数:', sampledRows.length);
                sampledOutputCsvData = {
                    headers: this.currentChartData.outputCsvData.headers,
                    rows: sampledRows
                };
                console.log(`输出数据采样完成：${originalRowCount} -> ${sampledRows.length} 行`);
            } else {
                console.log('输出数据行数在限制范围内，无需采样');
            }
        }

        // 创建加载提示
        const loadingOverlay = document.createElement('div');
        loadingOverlay.style.cssText = `
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: rgba(0, 0, 0, 0.7);
            color: white;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            z-index: 9999;
            font-family: Arial, sans-serif;
        `;
        loadingOverlay.innerHTML = `
            <div style="font-size: 24px; margin-bottom: 10px;">⏳</div>
            <div style="font-size: 16px;">正在生成报告，请稍候...</div>
        `;
        document.body.appendChild(loadingOverlay);

        try {
            // 确保图表完全渲染
            if (this.chart) {
                this.chart.resize();
                await new Promise(resolve => setTimeout(resolve, 500));
            }

            // 创建PDF生成器实例
            const pdfGenerator = new LocalPDFGenerator();

            // 1. 添加报告标题
            pdfGenerator.addTitle('任务分析报告');
            pdfGenerator.addText(`任务名称: ${record.name}`, 12);
            pdfGenerator.addText(`生成时间: ${new Date().toLocaleString()}`, 12);
            pdfGenerator.addSeparator();

            // 2. 任务详情部分
            pdfGenerator.addSubtitle('一、任务详情');
            pdfGenerator.addText(`档案ID: ${record.archiveId}`, 12);
            pdfGenerator.addText(`档案名称: ${record.name}`, 12);
            pdfGenerator.addText(`当前状态: ${record.status}`, 12);
            pdfGenerator.addText(`开始时间: ${record.startTime ? new Date(record.startTime).toLocaleString() : 'N/A'}`, 12);
            pdfGenerator.addText(`结束时间: ${record.endTime ? new Date(record.endTime).toLocaleString() : 'N/A'}`, 12);
            pdfGenerator.addSeparator();

            // 3. 曲线图分析
            pdfGenerator.addSubtitle('二、曲线图分析');
            const chartElement = this.shadowRoot.getElementById('analysisChart');
            if (chartElement && this.chart) {
                const chartImage = this.chart.getDataURL({
                    type: 'png',
                    pixelRatio: 2,
                    backgroundColor: '#fff'
                });
                await pdfGenerator.addChartImage(chartImage, '任务曲线图', `${record.name}的趋势分析图表`);
            } else {
                pdfGenerator.addImagePlaceholder('曲线图', '当前任务的趋势分析图表');
            }

            // 4. 数据视图
            pdfGenerator.addSubtitle('三、数据视图');

            // 4.1 输入数据表格 - 参照visual-analysis格式
            if (this.currentChartData && this.currentChartData.tasks) {
                this.currentChartData.tasks.forEach((task, taskIndex) => {
                    if (task.inputData && task.inputData.length > 0) {
                        pdfGenerator.addText('输入数据', 12, true);
                        
                        // 获取输入路径
                        const inputPaths = task.inputPaths || [];
                        
                        if (inputPaths.length > 0) {
                            // 按路径分组数据 - 参考visual-analysis格式
                            const inputPathInfo = {};
                            inputPaths.forEach((path, pathIdx) => {
                                const pointsPerPath = Math.ceil(task.inputData.length / inputPaths.length);
                                const startIndex = pathIdx * pointsPerPath;
                                const endIndex = Math.min(startIndex + pointsPerPath, task.inputData.length);
                                const pathData = task.inputData.slice(startIndex, endIndex);
                                
                                // 直接存储数组数据，符合sampleData的期望格式
                                inputPathInfo[path] = pathData.map(p => ({
                                    timestamp: p[0],
                                    value: p[1]
                                }));
                            });
                            
                            // 提取所有时间戳
                            const inputTimestamps = new Set();
                            Object.values(inputPathInfo).forEach(data => {
                                if (data && data.length > 0) {
                                    data.forEach(point => {
                                        inputTimestamps.add(point.timestamp);
                                    });
                                }
                            });
                            
                            const sortedInputTimestamps = Array.from(inputTimestamps).sort((a, b) => a - b);
                            console.log('输入数据时间戳原始数量:', sortedInputTimestamps.length);
                            
                            // 对时间戳进行采样
                            const sampledTimestamps = this.sampleData(sortedInputTimestamps, maxRows, samplingAlgorithm);
                            console.log('输入数据时间戳采样后数量:', sampledTimestamps.length);
                            
                            const inputHeaders = ['时间', ...inputPaths];
                            const inputRows = sampledTimestamps.map(timestamp => {
                                let timeLabel;
                                if (this.isValidTimestamp(timestamp)) {
                                    timeLabel = new Date(timestamp).toLocaleString();
                                } else {
                                    timeLabel = String(timestamp);
                                }
                                const row = [timeLabel];
                                inputPaths.forEach(path => {
                                    const data = inputPathInfo[path];
                                    const point = data?.find(p => p.timestamp === timestamp);
                                    if (point && point.value !== null && point.value !== undefined) {
                                        if (typeof point.value === 'number') {
                                            row.push(point.value.toFixed(2));
                                        } else {
                                            row.push(String(point.value));
                                        }
                                    } else {
                                        row.push('N/A');
                                    }
                                });
                                return row;
                            });
                            
                            // 检查列数是否过多
                            const maxColumnsPerTable = 11;
                            const totalInputColumns = inputHeaders.length;
                            
                            if (totalInputColumns <= maxColumnsPerTable) {
                                pdfGenerator.addTable(inputHeaders, inputRows);
                            } else {
                                const pathsPerTable = maxColumnsPerTable - 1;
                                const inputTableCount = Math.ceil(inputPaths.length / pathsPerTable);
                                
                                pdfGenerator.addText(`输入数据列数过多（共${inputPaths.length}列），已拆分为${inputTableCount}个表格显示：`, 10);
                                
                                for (let tableIndex = 0; tableIndex < inputTableCount; tableIndex++) {
                                    const startPathIndex = tableIndex * pathsPerTable;
                                    const endPathIndex = Math.min(startPathIndex + pathsPerTable, inputPaths.length);
                                    const currentPaths = inputPaths.slice(startPathIndex, endPathIndex);
                                    
                                    const currentHeaders = ['时间', ...currentPaths];
                                    const currentRows = inputRows.map(row => {
                                        const currentRow = [row[0]];
                                        currentPaths.forEach(path => {
                                            const originalPathIdx = inputPaths.indexOf(path);
                                            currentRow.push(row[originalPathIdx + 1]);
                                        });
                                        return currentRow;
                                    });
                                    
                                    pdfGenerator.addText(`输入数据表格 ${tableIndex + 1}/${inputTableCount} (列 ${startPathIndex + 1}-${endPathIndex})`, 11, true);
                                    pdfGenerator.addTable(currentHeaders, currentRows);
                                    
                                    if (tableIndex < inputTableCount - 1) {
                                        pdfGenerator.addSeparator();
                                    }
                                }
                            }
                        } else {
                            // 没有路径信息，使用简单格式
                            const inputHeaders = ['时间', '数值'];
                            const sampledInputData = this.sampleData(task.inputData, maxRows, samplingAlgorithm);
                            console.log('输入数据原始行数:', task.inputData.length, '采样后行数:', sampledInputData.length);
                            const inputRows = sampledInputData.map(p => [
                                this.isValidTimestamp(p[0]) ? new Date(p[0]).toLocaleString() : String(p[0]),
                                typeof p[1] === 'number' ? p[1].toFixed(2) : String(p[1])
                            ]);
                            
                            pdfGenerator.addTable(inputHeaders, inputRows);
                        }
                        
                        pdfGenerator.addSeparator();
                    }

                    // 4.2 输出数据表格 - 使用采样后的CSV原始数据
                    if (sampledOutputCsvData && sampledOutputCsvData.headers && sampledOutputCsvData.rows) {
                        pdfGenerator.addText('输出数据', 12, true);
                        
                        const outputHeaders = sampledOutputCsvData.headers;
                        const outputRows = sampledOutputCsvData.rows;
                        
                        pdfGenerator.addTable(outputHeaders, outputRows);
                        pdfGenerator.addSeparator();
                    }
                });
            }
            
            if ((!this.currentChartData || !this.currentChartData.tasks) && 
                (!this.currentChartData || !this.currentChartData.outputCsvData)) {
                pdfGenerator.addText('暂无数据', 12);
            }
            
            // 检查是否进行了采样
            pdfGenerator.addSeparator();
            pdfGenerator.addText(`如何访问完整数据集：`, 10, true);
            pdfGenerator.addText(`使用"导出"功能下载完整数据集（档案号：${record.archiveId}）`, 9, false);
            
            // 从record中获取输入和输出路径
            const inputPaths = record.inputMeasurements ? JSON.parse(record.inputMeasurements) : [];
            const outputPaths = record.outputMeasurements ? JSON.parse(record.outputMeasurements) : [];
            
            if (inputPaths.length > 0 || outputPaths.length > 0) {
                const pathInfo = [];
                if (inputPaths.length > 0) {
                    pathInfo.push(`输入路径：${inputPaths.join(', ')}`);
                }
                if (outputPaths.length > 0) {
                    pathInfo.push(`输出路径：${outputPaths.join(', ')}`);
                }
                pdfGenerator.addText(`通过数据资源库查询直接获取完整数据（${pathInfo.join('，')}）`, 9, false);
            }

            // 5. 统计分析
            pdfGenerator.addSubtitle('四、统计分析');
            if (this.currentChartData && this.currentChartData.tasks) {
                let totalInputCount = 0;
                let totalOutputCount = 0;
                
                this.currentChartData.tasks.forEach(task => {
                    if (task.inputData) {
                        totalInputCount += task.inputData.length;
                    }
                    if (task.calculationResult) {
                        totalOutputCount += task.calculationResult.length;
                    }
                });
                
                const statsHeaders = ['统计指标', '数值', '说明'];
                const statsData = [
                    ['输入数据点数量', totalInputCount, '输入数据有效数据点个数'],
                    ['输出数据点数量', totalOutputCount, '输出数据有效数据点个数'],
                    ['报告数据限制', maxRows, '报告中显示的最大数据行数'],
                    ['采样算法', samplingAlgorithm === 'uniform' ? '均匀采样' : samplingAlgorithm === 'random' ? '随机采样' : samplingAlgorithm === 'first' ? '取前N条' : '取后N条', '数据采样算法']
                ];
                
                pdfGenerator.addTable(statsHeaders, statsData);
            }

            // 6. 生成HTML内容
            const htmlContent = pdfGenerator.generateHTML();

            // 6. 上传报告到后端
            const formData = new FormData();
            formData.append('file', new Blob([htmlContent], { type: 'text/html;charset=utf-8' }), '仿真分析报告.html');
            formData.append('timestamp', record.timestamp || record.createTime);

            const uploadResult = await window.AppConfig.upload('simulationArchives', 'upload-report', formData);

            if (uploadResult.success) {
                this.showToast('报告生成并上传成功', 'success');
                
                // 7. 打开新窗口显示报告
                const reportWindow = window.open('', '_blank');
                if (reportWindow) {
                    reportWindow.document.write(htmlContent);
                    reportWindow.document.close();
                    // 自动弹出打印对话框
                    setTimeout(() => {
                        reportWindow.print();
                    }, 500);
                } else {
                    this.showToast('无法打开报告窗口，请检查浏览器弹窗设置', 'warning');
                }
            } else {
                this.showToast('报告上传失败: ' + (uploadResult.message || '未知错误'), 'error');
            }
        } catch (error) {
            console.error('生成报告失败:', error);
            this.showToast('生成报告出现错误，请重试', 'error');
        } finally {
            document.body.removeChild(loadingOverlay);
        }
    }

    // 处理导出操作
    async handleExport(record) {
        this.showToast(`正在导出仿真数据: ${record.name}`, 'info');

        try {
            // 1. 先执行分析获取数据
            await this.handleAnalyze(record);
            
            // 等待分析完成
            await new Promise(resolve => setTimeout(resolve, 1000));

            // 2. 生成报告HTML内容
            const htmlContent = await this.generateExportHTML(record);
            
            // 3. 上传报告到后端
            await this.uploadReportToTask(record, htmlContent);
            
            // 4. 打包并下载任务文件
            await this.packageAndDownloadTask(record);

        } catch (error) {
            console.error('导出失败:', error);
            this.showToast('导出失败，请重试', 'error');
        }
    }

    // 上传报告到任务目录
    async uploadReportToTask(record, htmlContent) {
        try {
            this.showToast('正在上传报告...', 'info');

            const formData = new FormData();
            const reportFileName = `仿真分析报告.html`;
            formData.append('file', new Blob([htmlContent], { type: 'text/html;charset=utf-8' }), reportFileName);
            formData.append('timestamp', record.timestamp || record.createTime);

            const uploadResult = await window.AppConfig.upload('simulationArchives', 'upload-report', formData);
            
            if (!uploadResult.success) {
                this.showToast('上传报告失败：' + (uploadResult.message || '未知错误'), 'error');
            } else {
                this.showToast('报告上传成功！', 'success');
            }

            return uploadResult.data;
            
        } catch (error) {
            console.error('上传报告失败:', error);
            throw error;
        }
    }

    // 打包并下载任务文件
    async packageAndDownloadTask(record) {
        try {
            this.showToast('正在打包下载...', 'info');

            const downloadResult = await window.AppConfig.get('simulationArchives', 'package-download', {
                timestamp: record.timestamp || record.createTime
            });

            if (downloadResult.success && downloadResult.data) {
                // 触发下载
                const blob = new Blob([downloadResult.data], { type: 'application/zip' });
                const url = URL.createObjectURL(blob);
                const a = document.createElement('a');
                a.href = url;
                a.download = `仿真导出_${record.name}_${new Date().getTime()}.zip`;
                document.body.appendChild(a);
                a.click();
                document.body.removeChild(a);
                URL.revokeObjectURL(url);

                this.showToast('导出成功！', 'success');
            } else {
                this.showToast('打包下载失败', 'error');
            }
        } catch (error) {
            console.error('打包下载失败:', error);
            throw error;
        }
    }

    // 生成导出报告HTML
    async generateExportHTML(record) {
        const pdfGenerator = new LocalPDFGenerator();

        pdfGenerator.addTitle('仿真分析报告（导出版）');
        pdfGenerator.addText(`仿真名称: ${record.name}`, 12);
        pdfGenerator.addText(`导出时间: ${new Date().toLocaleString()}`, 12);
        pdfGenerator.addSeparator();

        pdfGenerator.addSubtitle('一、仿真详情');
        pdfGenerator.addText(`档案名称: ${record.name}`, 12);
        pdfGenerator.addText(`当前状态: ${this.getStatusText(record.status)}`, 12);
        pdfGenerator.addText(`开始时间: ${record.startTime ? new Date(record.startTime).toLocaleString() : 'N/A'}`, 12);
        pdfGenerator.addText(`结束时间: ${record.endTime ? new Date(record.endTime).toLocaleString() : 'N/A'}`, 12);
        if (record.error) pdfGenerator.addText(`错误信息: ${record.error}`, 12);

        pdfGenerator.addSubtitle('二、曲线图分析');
        if (this.chart) {
            const chartImage = this.chart.getDataURL({ type: 'png', pixelRatio: 2, backgroundColor: '#fff' });
            await pdfGenerator.addChartImage(chartImage, '仿真曲线图', `${record.name}的趋势分析图表`);
        }

        pdfGenerator.addSubtitle('三、完整数据');
        if (this.currentChartData && this.currentChartData.tasks) {
            this.currentChartData.tasks.forEach(task => {
                pdfGenerator.addText(`节点: ${task.name}`, 12, true);

                if (task.inputData && task.inputData.length > 0) {
                    pdfGenerator.addText('输入数据', 11, true);
                    const inputHeaders = ['时间', '数值'];
                    const inputRows = task.inputData.map(p => [
                        this.isValidTimestamp(p[0]) ? new Date(p[0]).toLocaleString() : String(p[0]),
                        typeof p[1] === 'number' ? p[1].toFixed(4) : String(p[1])
                    ]);
                    pdfGenerator.addTable(inputHeaders, inputRows);
                }

                if (task.calculationResult && task.calculationResult.length > 0) {
                    pdfGenerator.addText('输出数据', 11, true);
                    const outputHeaders = ['时间', '数值'];
                    const outputRows = task.calculationResult.map(p => [
                        this.isValidTimestamp(p[0]) ? new Date(p[0]).toLocaleString() : String(p[0]),
                        typeof p[1] === 'number' ? p[1].toFixed(4) : String(p[1])
                    ]);
                    pdfGenerator.addTable(outputHeaders, outputRows);
                }

                pdfGenerator.addSeparator();
            });
        }

        pdfGenerator.addWatermark();
        return pdfGenerator.generateHTML();
    }

    // 处理查看日志操作
    async handleViewLog(record) {
        try {
            this.showToast(`正在获取仿真日志: ${record.name}`, 'info');

            if (!record.timestamp && !record.createTime) {
                this.showToast('记录信息不完整，无法获取日志', 'error');
                return;
            }

            const logTimestamp = record.timestamp || record.createTime;

            const result = await window.AppConfig.get('simulationArchives', 'execution-log', {
                timestamp: logTimestamp
            });

            if (result.success && result.data) {
                let logContent = '暂无日志信息';
                if (result.data.nodeLogs) {
                    const parts = [];
                    Object.entries(result.data.nodeLogs).forEach(([nodeId, log]) => {
                        parts.push(`=== 节点 ${nodeId} ===\n${log}`);
                    });
                    logContent = parts.join('\n\n') || '暂无日志信息';
                } else if (result.data.processLog) {
                    logContent = result.data.processLog;
                }

                this.showLogModal(record.name, logContent, record);
            } else {
                this.showToast(result.message || '获取仿真日志失败', 'error');
            }
        } catch (error) {
            console.error('获取仿真日志失败:', error);
            this.showToast('网络错误，获取仿真日志失败', 'error');
        }
    }

    // 显示日志弹窗
    showLogModal(taskName, logContent, record) {
        const modal = this.shadowRoot.getElementById('modalMask');
        const title = this.shadowRoot.getElementById('modalTitle');
        const modalBody = this.shadowRoot.getElementById('modalBody');
        const modalFooter = this.shadowRoot.getElementById('modalFooter');

        if (modal && title && modalBody && modalFooter) {
            title.textContent = `仿真日志 - ${taskName}`;

            const isRunning = record.status === 'running';

            modalBody.innerHTML = `
                <div class="log-container">
                    <div class="log-header">
                        <h3>实时日志</h3>
                        <div class="log-controls">
                            <button class="btn-refresh" id="refreshLogBtn">刷新</button>
                            ${isRunning ? `
                                <button class="btn-auto-refresh active" id="autoRefreshBtn">自动刷新: 开启</button>
                                <span class="status-indicator running">仿真运行中</span>
                            ` : `
                                <span class="status-indicator ${record.status}">仿真${this.getStatusText(record.status)}</span>
                            `}
                        </div>
                    </div>
                    <div class="log-content" id="logContent">
                        <pre>${logContent}</pre>
                    </div>
                </div>
            `;

            modalFooter.innerHTML = `
                <button type="button" class="modal-btn secondary" id="closeLogBtn">关闭</button>
            `;

            this.currentLogTask = {
                name: taskName,
                createTime: record.createTime,
                status: record.status
            };

            this.bindLogModalEvents();

            if (isRunning) {
                this.startLogAutoRefresh();
            }

            this.showModal();
        } else {
            this.showToast('弹窗元素缺失，无法显示日志', 'error');
        }
    }

    // 绑定日志弹窗事件
    bindLogModalEvents() {
        this.shadowRoot.getElementById('closeLogBtn')?.addEventListener('click', () => {
            this.hideModal();
            this.stopLogAutoRefresh();
        });

        this.shadowRoot.getElementById('modalClose')?.addEventListener('click', () => {
            this.hideModal();
            this.stopLogAutoRefresh();
        });

        this.shadowRoot.getElementById('refreshLogBtn')?.addEventListener('click', () => {
            this.refreshLog();
        });

        this.shadowRoot.getElementById('autoRefreshBtn')?.addEventListener('click', () => {
            this.toggleLogAutoRefresh();
        });
    }

    // 刷新日志
    async refreshLog() {
        if (!this.currentLogTask) return;

        try {
            const logTimestamp = this.currentLogTask.timestamp || this.currentLogTask.createTime;
            const result = await window.AppConfig.get('simulationArchives', 'execution-log', {
                timestamp: logTimestamp
            });

            if (result.success && result.data) {
                const logContent = this.shadowRoot.getElementById('logContent');
                if (logContent) {
                    let content = '暂无日志信息';
                    if (result.data.nodeLogs) {
                        const parts = [];
                        Object.entries(result.data.nodeLogs).forEach(([nodeId, log]) => {
                            parts.push(`=== 节点 ${nodeId} ===\n${log}`);
                        });
                        content = parts.join('\n\n') || '暂无日志信息';
                    } else if (result.data.processLog) {
                        content = result.data.processLog;
                    }
                    logContent.innerHTML = `<pre>${content}</pre>`;
                    logContent.scrollTop = logContent.scrollHeight;
                }

                if (this.logRefreshInterval) {
                    await this.checkRecordStatus();
                }
            }
        } catch (error) {
            console.error('刷新日志失败:', error);
        }
    }

    // 检查记录状态
    async checkRecordStatus() {
        if (!this.currentLogTask) return;

        try {
            const result = await window.AppConfig.get('simulationArchives', 'execution-status', {
                createTime: this.currentLogTask.createTime
            });

            if (result.success && result.data && result.data.result) {
                const newStatus = result.data.result.status;
                const oldStatus = this.currentLogTask.status;

                if (oldStatus === 'running' && newStatus !== 'running') {
                    this.stopLogAutoRefresh();
                    this.updateStatusDisplay(newStatus);
                    const statusText = this.getStatusText(newStatus);
                    this.showToast(`仿真${statusText}`, newStatus === 'completed' ? 'success' : 'warning');
                }

                this.currentLogTask.status = newStatus;
            }
        } catch (error) {
            console.error('检查记录状态失败:', error);
        }
    }

    // 更新状态显示
    updateStatusDisplay(status) {
        const statusIndicator = this.shadowRoot.querySelector('.status-indicator');
        const autoRefreshBtn = this.shadowRoot.getElementById('autoRefreshBtn');

        if (statusIndicator) {
            statusIndicator.className = `status-indicator ${status}`;
            statusIndicator.textContent = `仿真${this.getStatusText(status)}`;
        }

        if (autoRefreshBtn && status !== 'running') {
            autoRefreshBtn.classList.remove('active');
            autoRefreshBtn.textContent = '自动刷新: 关闭';
        }
    }

    // 切换自动刷新
    toggleLogAutoRefresh() {
        const btn = this.shadowRoot.getElementById('autoRefreshBtn');
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

    // 开始自动刷新
    startLogAutoRefresh() {
        this.logRefreshInterval = setInterval(() => {
            this.refreshLog();
        }, 5000);
    }

    // 停止自动刷新
    stopLogAutoRefresh() {
        if (this.logRefreshInterval) {
            clearInterval(this.logRefreshInterval);
            this.logRefreshInterval = null;
        }
    }

    // 显示弹窗
    showModal() {
        const modal = this.shadowRoot.getElementById('modalMask');
        if (modal) {
            modal.removeAttribute('hidden');
            modal.style.display = 'flex';
        }
    }

    // 隐藏弹窗
    hideModal() {
        const modal = this.shadowRoot.getElementById('modalMask');
        if (modal) {
            modal.setAttribute('hidden', '');
            modal.style.display = 'none';
        }
        this.currentLogTask = null;
        this.stopLogAutoRefresh();
    }

    // 处理停止操作
    async handleStop(record) {
        try {
            this.showToast(`正在停止仿真: ${record.name}`, 'warning');

            const baseUrl = window.AppConfig.getApiUrl('simulationArchives', 'stop');
            const url = baseUrl + '?createTime=' + record.createTime;
            const result = await window.AppConfig.request(url, { method: 'POST' });

            if (result.success) {
                this.showToast(`仿真 ${record.name} 停止成功`, 'success');
                record.status = 'stopped';
                this.updateTable();
            } else {
                this.showToast(result.message || '停止仿真失败', 'error');
            }
        } catch (error) {
            console.error('停止仿真失败:', error);
            this.showToast('网络错误，停止仿真失败', 'error');
        }
    }

    // 处理删除操作
    async handleDelete(record) {
        try {
            const modalTitle = this.shadowRoot.getElementById('modalTitle');
            const modalBody = this.shadowRoot.getElementById('modalBody');
            const modalFooter = this.shadowRoot.getElementById('modalFooter');

            modalTitle.textContent = '删除确认';
            modalBody.innerHTML = `
                <div style="padding: 20px 0;">
                    <p style="margin-bottom: 15px; color: #d32f2f; font-weight: 500;">
                        ⚠️ 确定要删除仿真记录 "${record.name}" 吗？
                    </p>
                    <div style="background: #fef2f2; border: 1px solid #fecaca; border-radius: 6px; padding: 15px; margin-bottom: 15px;">
                        <p style="margin: 0 0 8px 0; font-weight: 500; color: #991b1b;">此操作将删除：</p>
                        <ul style="margin: 0; padding-left: 20px; color: #7f1d1d;">
                            <li>仿真执行数据</li>
                            <li>仿真文件目录</li>
                            <li>相关日志和报告</li>
                        </ul>
                    </div>
                    <p style="margin: 0; color: #dc2626; font-size: 14px;">
                        ⚠️ 此操作不可恢复！
                    </p>
                </div>
            `;

            modalFooter.innerHTML = `
                <button class="modal-btn secondary" id="cancelDelete">取消</button>
                <button class="modal-btn danger" id="confirmDelete">确认删除</button>
            `;

            this.showModal();

            const cancelBtn = this.shadowRoot.getElementById('cancelDelete');
            const confirmBtn = this.shadowRoot.getElementById('confirmDelete');
            const modalClose = this.shadowRoot.getElementById('modalClose');

            const closeModal = () => { this.hideModal(); };

            const handleConfirmDelete = async () => {
                closeModal();
                await this.performDelete(record);
            };

            cancelBtn.addEventListener('click', closeModal);
            confirmBtn.addEventListener('click', handleConfirmDelete);
            modalClose.addEventListener('click', closeModal);

        } catch (error) {
            console.error('显示删除确认弹窗失败:', error);
            this.showToast('显示确认弹窗失败', 'error');
        }
    }

    // 执行删除操作
    async performDelete(record) {
        try {
            this.showToast(`正在删除仿真记录: ${record.name}`, 'warning');

            const result = await window.AppConfig.delete('simulationArchives', 'execution-record', {
                timestamp: record.timestamp
            });

            if (result.success) {
                this.showToast(`仿真记录 ${record.name} 删除成功`, 'success');

                const index = this.allData.findIndex(item => item.createTime === record.createTime);
                if (index > -1) {
                    this.allData.splice(index, 1);
                }

                await this.loadRecordsFromAPI();
                this.updateTable();

                if (this.currentChartData && this.currentChartData.tasks) {
                    this.currentChartData.tasks = this.currentChartData.tasks.filter(
                        t => !String(t.id).includes(String(record.createTime))
                    );
                    this.updateChart();
                }
            } else {
                this.showToast(result.message || '删除仿真记录失败', 'error');
            }
        } catch (error) {
            console.error('删除仿真记录失败:', error);
            this.showToast('网络错误，删除仿真记录失败', 'error');
        }
    }

    // ==================== 辅助方法 ====================

    isValidTimestamp(value) {
        if (typeof value !== 'number') return false;
        return value > 1e12 && value < 1e13;
    }

    formatTimeWithUnit(value) {
        if (value == null || isNaN(value)) {
            return String(value);
        }
        
        const absValue = Math.abs(value);
        
        // 根据数值大小自动选择合适的单位
        if (absValue >= 86400000) {
            return (value / 86400000).toFixed(1) + 'd';
        } else if (absValue >= 3600000) {
            return (value / 3600000).toFixed(1) + 'h';
        } else if (absValue >= 60000) {
            return (value / 60000).toFixed(1) + 'min';
        } else if (absValue >= 1000) {
            return (value / 1000).toFixed(1) + 's';
        } else {
            return value.toFixed(0) + 'ms';
        }
    }

    calculateDataRange(chartData) {
        let minValue = Infinity;
        let maxValue = -Infinity;
        let hasData = false;

        // 检查输入数据
        if (chartData && chartData.inputData) {
            Object.values(chartData.inputData).forEach(dataArray => {
                if (dataArray && dataArray.length > 0) {
                    dataArray.forEach(point => {
                        if (point.value !== null && point.value !== undefined && typeof point.value === 'number') {
                            minValue = Math.min(minValue, point.value);
                            maxValue = Math.max(maxValue, point.value);
                            hasData = true;
                        }
                    });
                }
            });
        }

        // 检查输出数据
        if (chartData && chartData.outputData) {
            Object.values(chartData.outputData).forEach(dataArray => {
                if (dataArray && dataArray.length > 0) {
                    dataArray.forEach(point => {
                        if (point.value !== null && point.value !== undefined && typeof point.value === 'number') {
                            minValue = Math.min(minValue, point.value);
                            maxValue = Math.max(maxValue, point.value);
                            hasData = true;
                        }
                    });
                }
            });
        }

        if (!hasData) {
            return { min: 0, max: 100 };
        }

        const range = maxValue - minValue;
        const padding = range * 0.1;
        
        return {
            min: minValue - padding,
            max: maxValue + padding
        };
    }

    calculateXAxisRange(chartData) {
        if (!chartData) {
            return { min: 0, max: 100 };
        }

        let minValue = Infinity;
        let maxValue = -Infinity;
        let hasData = false;

        const processArray = (dataArray) => {
            if (dataArray && dataArray.length > 0) {
                dataArray.forEach(point => {
                    if (point.timestamp !== null && point.timestamp !== undefined) {
                        const value = typeof point.timestamp === 'number' ? point.timestamp : parseFloat(point.timestamp);
                        if (!isNaN(value)) {
                            minValue = Math.min(minValue, value);
                            maxValue = Math.max(maxValue, value);
                            hasData = true;
                        }
                    }
                });
            }
        };

        if (chartData.inputData) {
            Object.values(chartData.inputData).forEach(processArray);
        }

        if (chartData.outputData) {
            Object.values(chartData.outputData).forEach(processArray);
        }

        if (!hasData) {
            return { min: 0, max: 100 };
        }

        const range = maxValue - minValue;
        const padding = range * 0.05;
        
        return {
            min: minValue - padding,
            max: maxValue + padding
        };
    }

    sampleData(data, maxRows = 20, samplingAlgorithm = 'uniform') {
        if (!data || data.length === 0 || data.length <= maxRows) return data;

        const sampledData = [];
        switch (samplingAlgorithm) {
            case 'uniform':
                const interval = Math.ceil(data.length / maxRows);
                for (let i = 0; i < data.length; i += interval) sampledData.push(data[i]);
                if (sampledData[sampledData.length - 1] !== data[data.length - 1]) sampledData.push(data[data.length - 1]);
                break;
            case 'random':
                const indices = new Set();
                while (indices.size < maxRows) indices.add(Math.floor(Math.random() * data.length));
                Array.from(indices).sort((a, b) => a - b).forEach(i => sampledData.push(data[i]));
                break;
            case 'first':
                for (let i = 0; i < maxRows; i++) sampledData.push(data[i]);
                break;
            case 'last':
                const start = Math.max(0, data.length - maxRows);
                for (let i = start; i < data.length; i++) sampledData.push(data[i]);
                break;
            default:
                const defInterval = Math.ceil(data.length / maxRows);
                for (let i = 0; i < data.length; i += defInterval) sampledData.push(data[i]);
                if (sampledData[sampledData.length - 1] !== data[data.length - 1]) sampledData.push(data[data.length - 1]);
                break;
        }
        return sampledData;
    }

    initPagination() {
        const pagination = this.shadowRoot.getElementById('pagination');
        if (pagination) {
            pagination.addEventListener('pagination-change', (event) => {
                const { currentPage, pageSize } = event.detail;
                this.currentPage = currentPage;
                this.pageSize = pageSize;
                this.loadRecordsFromAPI();
            });
            this.updatePagination();
        }
    }

    updatePagination() {
        const pagination = this.shadowRoot.getElementById('pagination');
        if (pagination) {
            pagination.setPagination(this.currentPage, this.pageSize, this.totalCount || this.displayData.length);
        }
    }

    showToast(message, type = 'success') {
        if (window.CommonUtils && window.CommonUtils.showToast) {
            window.CommonUtils.showToast(message, type);
        } else {
            console[type === 'error' ? 'error' : 'log'](`[${type}] ${message}`);
        }
    }
}

// 本地PDF生成器 - 无外网依赖
class LocalPDFGenerator {
    constructor() {
        this.content = [];
        this.yPosition = 50;
        this.pageHeight = 842;
        this.pageWidth = 595;
        this.margin = 50;
        this.fontSize = 12;
        this.lineHeight = 16;
    }

    addText(text, fontSize = 12, bold = false) {
        this.content.push({ type: 'text', text, fontSize, bold, y: this.yPosition });
        this.yPosition += this.lineHeight;
        this.checkPageBreak();
    }

    addTitle(text) {
        this.addText(text, 18, true);
        this.yPosition += 10;
    }

    addSubtitle(text) {
        this.addText(text, 14, true);
        this.yPosition += 5;
    }

    addTable(headers, data) {
        this.content.push({ type: 'table', headers, data });
        this.yPosition += 20 * (data.length + 2);
        this.checkPageBreak();
    }

    async addChartImage(chartBase64, title, description) {
        try {
            this.addText(title, 12, true);
            this.addText(description, 10);
            const img = new Image();
            img.src = chartBase64;
            await new Promise((resolve, reject) => { img.onload = resolve; img.onerror = reject; });
            this.content.push({ type: 'image', imageData: chartBase64, title, description, width: img.width, height: img.height });
            this.addText(' ', 8);
        } catch (error) {
            this.addImagePlaceholder(title, description);
        }
    }

    addImagePlaceholder(title, description) {
        this.addText(title, 12, true);
        this.addText(`[图片: ${description}]`, 10);
        this.addText(`尺寸: 400x300 像素`, 9);
        this.yPosition += 20;
    }

    addSeparator() {
        this.addText(''.padEnd(50, '-'), 10);
        this.yPosition += 5;
    }

    checkPageBreak() {
        if (this.yPosition > this.pageHeight - this.margin) {
            this.yPosition = this.margin;
            this.content.push({ type: 'newPage' });
        }
    }

    addWatermark() {
        const watermarkConfig = window.AppConfig && window.AppConfig.watermark ? window.AppConfig.watermark : {
            text: '清华大学大数据系统软件国家工程研究中心',
            opacity: 0.1
        };
        this.content.push({
            type: 'watermark',
            text: watermarkConfig.text,
            opacity: watermarkConfig.opacity,
            fontSize: watermarkConfig.fontSize || 48,
            color: watermarkConfig.color || '#999',
            rotation: watermarkConfig.rotation || -45,
            enable: watermarkConfig.enable !== false
        });
    }

    generateHTML() {
        let html = '<!DOCTYPE HTML><html><head>' +
            '<meta http-equiv="Content-Type" content="text/html; charset=UTF-8"></meta>' +
            '<meta charset="UTF-8"><title>仿真报告</title>' +
            '<style type="text/css">' +
            'body { font-family: SimSun, Microsoft YaHei, SimHei, Arial, sans-serif; font-size: ' + this.fontSize + 'pt; line-height: 1.5; margin: 0; padding: 0; position: relative; min-height: 100vh; }' +
            '.header { text-align: center; font-size: 14pt; font-weight: bold; margin-bottom: 30px; border-bottom: 2px solid #333; padding-bottom: 10px; }' +
            '.footer { text-align: center; font-size: 10pt; margin-top: 30px; border-top: 1px solid #333; padding-top: 10px; }' +
            '.title { text-align: center; font-size: 18pt; font-weight: bold; margin: 20px 0; }' +
            '.subtitle { font-size: 14pt; font-weight: bold; margin: 15px 0 10px 0; }' +
            '.content { padding: 20px; }' +
            '.table { width: 100%; border-collapse: collapse; margin: 10px 0; table-layout: fixed; }' +
            '.table th, .table td { border: 1px solid #ddd; padding: 8px; text-align: left; word-wrap: break-word; min-width: 0; }' +
            '.table th { background-color: #f2f2f2; font-weight: bold; }' +
            '.report-image { max-width: 100%; height: auto; }' +
            '.separator { height: 1px; background-color: #ccc; margin: 20px 0; }' +
            '@page { size: A4; margin: 2cm; }' +
            '@media print { body { font-family: SimSun, Microsoft YaHei, SimHei, Arial, sans-serif !important; } }' +
            '</style></head><body>' +
            '<div class="header">仿真报告</div><div class="content">';

        this.content.forEach(item => {
            const fontFamily = 'font-family: SimSun, Microsoft YaHei, SimHei, Arial, sans-serif;';
            switch (item.type) {
                case 'text':
                    html += item.bold
                        ? `<div style="font-weight: bold; font-size: ${item.fontSize}pt; margin: 5px 0; ${fontFamily}">${item.text}</div>`
                        : `<div style="font-size: ${item.fontSize}pt; margin: 5px 0; ${fontFamily}">${item.text}</div>`;
                    break;
                case 'table':
                    html += '<table class="table"><tr>';
                    item.headers.forEach(h => { html += `<th style="${fontFamily}">${h}</th>`; });
                    html += '</tr>';
                    item.data.forEach(row => {
                        html += '<tr>';
                        row.forEach(cell => { html += `<td style="${fontFamily}">${cell}</td>`; });
                        html += '</tr>';
                    });
                    html += '</table>';
                    break;
                case 'image':
                    html += `<div style="font-weight: bold; ${fontFamily}">${item.title}</div>`;
                    html += `<img src="${item.imageData}" alt="${item.description}" class="report-image"></img>`;
                    html += `<div style="text-align: center; font-size: 10pt; color: #666; margin: 5px 0; ${fontFamily}">${item.description}</div>`;
                    break;
                case 'watermark':
                    if (item.enable === false) break;
                    const wmStyle = `position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%) rotate(${item.rotation || -45}deg); font-size: ${item.fontSize || 48}px; color: ${item.color || '#999'}; opacity: ${item.opacity || 0.15}; z-index: 999; white-space: nowrap; ${fontFamily} pointer-events: none; user-select: none; font-weight: bold;`;
                    html += `<div style="position: relative; width: 100%; height: 400px; margin: 20px 0;"><div style="${wmStyle}">${item.text}</div></div>`;
                    break;
                case 'separator':
                    html += '<div class="separator"></div>';
                    break;
                case 'newPage':
                    html += '<div style="page-break-before: always;"></div>';
                    break;
            }
        });

        html += '</div><div class="footer" style="font-family: SimSun, Microsoft YaHei, SimHei, Arial, sans-serif;">仿真报告生成时间: ' + new Date().toLocaleString() + '</div></body></html>';
        return html;
    }
}

if (!customElements.get('simulation-record')) {
    customElements.define('simulation-record', SimulationRecord);
}
