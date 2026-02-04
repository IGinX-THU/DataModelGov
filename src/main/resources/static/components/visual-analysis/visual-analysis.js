/**
 * 数值与曲线分析组件 - 基于ECharts和数据表格
 * 参考data-visualization的ECharts实现和association-rules的表格样式
 */
class VisualAnalysis extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });
        this.chart = null;
        this.allData = [];
        this.displayData = [];
        this.currentPage = 1;
        this.pageSize = 10;
        this.totalPages = 0;
        this.analysisType = 'trend';
        this.dataSource = '';
        // 添加曲线可见性状态管理
        this.curveVisibility = {
            input: true,
            output: true
        };
        // 当前分析模式：'comparison' 或 'single'
        this.currentAnalysisMode = 'comparison';
        // 当前筛选状态
        this.currentFilter = {
            status: '',
            name: '',
            time: ''
        };
        // 当前图表数据缓存
        this.currentChartData = null;
    }

    async connectedCallback() {
        await this.loadResources();
        setTimeout(() => {
            this.bindEvents();
            this.initializeComponent();
        }, 100);
    }

    async loadResources() {
        // 加载CSS
        try {
            const cssLink = document.createElement('link');
            cssLink.rel = 'stylesheet';
            cssLink.href = './components/visual-analysis/visual-analysis.css';
            this.shadowRoot.appendChild(cssLink);
        } catch (error) {
            console.error('Failed to load CSS:', error);
        }

        if (window.location.protocol === 'file:') {
            this.shadowRoot.innerHTML += this.getFallbackHTML();
        } else {
            // 加载HTML
            try {
                const response = await fetch('./components/visual-analysis/visual-analysis.html');
                const html = await response.text();
                this.shadowRoot.innerHTML += html;
            } catch (error) {
                console.error('Failed to load HTML:', error);
                this.shadowRoot.innerHTML += this.getFallbackHTML();
            }
        }

        // 加载ECharts到全局
        try {
            if (!window.echarts) {
                const script = document.createElement('script');
                script.src = './lib/echarts/echarts.min.js';
                document.head.appendChild(script);
                
                // 等待ECharts加载完成
                await new Promise((resolve) => {
                    script.onload = resolve;
                });
            }
        } catch (error) {
            console.error('Failed to load ECharts:', error);
        }
        
        // 加载Flatpickr到全局（如果存在）
        try {
            const flatpickrScript = document.createElement('script');
            flatpickrScript.src = '/static/lib/flatpickr/flatpickr.min.js';
            flatpickrScript.onerror = () => {
                console.warn('Flatpickr library not found, date picker will not be available');
            };
            document.head.appendChild(flatpickrScript);
            
            // 加载Flatpickr CSS（如果存在）
            const cssLink = document.createElement('link');
            cssLink.rel = 'stylesheet';
            cssLink.href = '/static/lib/flatpickr/flatpickr.min.css';
            cssLink.onerror = () => {
                console.warn('Flatpickr CSS not found');
            };
            document.head.appendChild(cssLink);
            
            // 等待Flatpickr加载完成
            await new Promise((resolve) => {
                flatpickrScript.onload = resolve;
                flatpickrScript.onerror = resolve; // 即使失败也继续
            });
        } catch (error) {
            console.warn('Flatpickr loading skipped:', error);
        }
    }

    getFallbackHTML() {
        return `
        <div class="visual-analysis-container">
            <div class="analysis-header">
                <h3 class="analysis-title">数值与曲线分析</h3>
                <button class="close-btn" id="closeBtn">×</button>
            </div>
            <div class="analysis-content">
                <div class="control-panel">
                    <div class="panel-section">
                        <h4 class="section-title">分析配置</h4>
                        <div class="control-actions">
                            <button class="action-btn primary" id="analyzeBtn">开始分析</button>
                        </div>
                    </div>
                </div>
                <div class="main-content">
                    <div class="chart-section">
                        <div class="chart-container" id="analysisChart"></div>
                    </div>
                    <div class="table-section">
                        <div class="table-wrapper">
                            <table class="data-table">
                                <tbody id="tableBody"></tbody>
                            </table>
                        </div>
                    </div>
                </div>
            </div>
        </div>`;
    }

    show() {
        console.log('显示数值与曲线分析');
        this.setAttribute('show', '');
        this.allData = [];
        this.displayData = [];
        this.currentPage = 1;
        this.pageSize = 10; // 减少每页显示数量以便测试滚动
        
        setTimeout(() => {
            this.initializeComponent();
        }, 50);
    }

    hide() {
        console.log('隐藏数值与曲线分析');
        this.removeAttribute('show');
        if (this.chart) {
            this.chart.dispose();
            this.chart = null;
        }
    }

    initializeComponent() {
        // 生成数据并显示表格，但图表显示空状态
        const mockData = this.generateMultiTaskData();
        this.allData = mockData;
        this.displayData = mockData;
        
        // 更新表格显示数据
        this.updateTable();
        
        // 图表显示空状态
        this.showEmptyState();
    }

    showMultiTaskAnalysis() {
        // 生成多任务对比数据
        const mockData = this.generateMultiTaskData();
        this.allData = mockData;
        this.displayData = mockData;
        
        // 初始化图表
        if (!this.chart) {
            this.initChart();
        } else {
            this.updateChart();
        }
        
        // 更新表格
        this.updateTable();
    }

    bindEvents() {
        // 关闭按钮
        const closeBtn = this.shadowRoot.getElementById('closeBtn');
        if (closeBtn) {
            closeBtn.addEventListener('click', () => {
                this.hide();
            });
        }

        // 全选复选框
        const selectAll = this.shadowRoot.getElementById('selectAll');
        if (selectAll) {
            selectAll.addEventListener('change', (e) => {
                this.handleSelectAll(e.target.checked);
            });
        }

        // 对比按钮
        const compareBtn = this.shadowRoot.getElementById('compareBtn');
        if (compareBtn) {
            compareBtn.addEventListener('click', () => {
                this.handleCompareSelected();
            });
        }

        // 输入数据切换按钮
        const toggleInputBtn = this.shadowRoot.getElementById('toggleInputBtn');
        if (toggleInputBtn) {
            toggleInputBtn.addEventListener('click', () => {
                this.toggleInputData();
            });
        }

        // 输出数据切换按钮
        const toggleOutputBtn = this.shadowRoot.getElementById('toggleOutputBtn');
        if (toggleOutputBtn) {
            toggleOutputBtn.addEventListener('click', () => {
                this.toggleOutputData();
            });
        }

        // 状态筛选下拉框
        const statusFilter = this.shadowRoot.getElementById('statusFilter');
        if (statusFilter) {
            statusFilter.addEventListener('change', (e) => {
                this.handleStatusFilter(e.target.value);
            });
        }

        // 名称搜索输入框
        const nameSearch = this.shadowRoot.getElementById('nameSearch');
        if (nameSearch) {
            nameSearch.addEventListener('input', (e) => {
                this.handleNameSearch(e.target.value);
            });
        }

        // 初始化日期范围选择器（如果Flatpickr可用）
        const dateRangePicker = this.shadowRoot.getElementById('dateRangePicker');
        if (dateRangePicker && window.flatpickr) {
            try {
                // 使用flatpickr初始化日期范围选择器
                this.flatpickrInstance = flatpickr(dateRangePicker, {
                    mode: 'range',
                    dateFormat: 'Y-m-d',
                    locale: 'zh',
                    allowInput: true,
                    onClose: (selectedDates, dateStr) => {
                        if (selectedDates.length === 2) {
                            const startDate = selectedDates[0];
                            const endDate = new Date(selectedDates[1]);
                            endDate.setHours(23, 59, 59, 999); // 设置为当天的最后一毫秒
                            this.handleTimeSearch({ start: startDate, end: endDate });
                        } else if (selectedDates.length === 0) {
                            this.handleTimeSearch(null);
                        }
                    }
                });
            } catch (error) {
                console.warn('Failed to initialize date range picker:', error);
            }
        } else if (!window.flatpickr) {
            console.warn('Flatpickr is not available. Date picker functionality will be limited.');
        }

        // 分页按钮
        const prevBtn = this.shadowRoot.getElementById('prevBtn');
        const nextBtn = this.shadowRoot.getElementById('nextBtn');
        
        if (prevBtn) {
            prevBtn.addEventListener('click', () => {
                if (this.currentPage > 1) {
                    this.currentPage--;
                    this.updateTable();
                }
            });
        }

        if (nextBtn) {
            nextBtn.addEventListener('click', () => {
                if (this.currentPage < this.totalPages) {
                    this.currentPage++;
                    this.updateTable();
                }
            });
        }

        // ESC键关闭
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape' && this.hasAttribute('show')) {
                this.hide();
            }
        });
    }

    generateMultiTaskData() {
        const data = [];
        const now = Date.now();
        const dataPoints = 100; // 生成100个数据点以便测试滚动
        
        // 生成分析任务数据
        const taskNames = [
            '数据质量分析',
            '性能监控分析', 
            '用户行为分析',
            '系统健康度分析',
            '业务指标分析',
            '安全风险评估',
            '资源使用分析',
            '网络流量分析',
            '数据库性能分析',
            'API调用分析',
            '错误日志分析',
            '用户访问分析'
        ];
        
        for (let i = 0; i < dataPoints; i++) {
            const timestamp = now - (dataPoints - i) * 60000; // 每分钟一个数据点
            const taskName = taskNames[i % taskNames.length];
            
            // 随机生成运行状态
            const statuses = ['running', 'stopped', 'pending', 'success', 'failed'];
            const statusWeights = [0.3, 0.25, 0.1, 0.25, 0.1]; // 运行中30%，停止25%，等待10%，成功25%，失败10%
            const random = Math.random();
            let status = 'running';
            let cumulativeWeight = 0;
            
            for (let j = 0; j < statuses.length; j++) {
                cumulativeWeight += statusWeights[j];
                if (random < cumulativeWeight) {
                    status = statuses[j];
                    break;
                }
            }
            
            const record = {
                id: `TASK-${String(i + 1).padStart(4, '0')}`,
                name: taskName,
                status: status,
                timestamp: timestamp,
                value: parseFloat((100 + Math.random() * 50).toFixed(2))
            };
            
            data.push(record);
        }
        
        return data;
    }

    showEmptyState() {
        // 清理ECharts实例
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
                    <div style="font-size: 12px;">请配置分析参数并点击"开始分析"</div>
                </div>
            `;
        }
        
        // 更新表格为空状态
        this.updateTable();
    }

    initChart() {
        const chartContainer = this.shadowRoot.getElementById('analysisChart');
        if (chartContainer && window.echarts) {
            // 清除空状态显示
            chartContainer.innerHTML = '';
            
            const tryInitChart = (attempt = 0) => {
                if (window.echarts && !this.chart) {
                    const rect = chartContainer.getBoundingClientRect();
                    console.log(`尝试初始化图表 (第${attempt + 1}次):`, rect);
                    
                    if (rect.height < 100 && attempt < 5) {
                        setTimeout(() => tryInitChart(attempt + 1), 200);
                        return;
                    }
                    
                    // 强制设置最小高度
                    if (rect.height < 350) {
                        chartContainer.style.minHeight = '350px';
                    }
                    
                    try {
                        this.chart = window.echarts.init(chartContainer);
                        console.log('图表初始化成功');
                        this.updateChart();
                    } catch (error) {
                        console.error('图表初始化失败:', error);
                        setTimeout(() => tryInitChart(attempt + 1), 500);
                    }
                } else if (attempt < 10) {
                    setTimeout(() => tryInitChart(attempt + 1), 200);
                } else {
                    console.error('ECharts not loaded or chart container not found');
                }
            };
            
            setTimeout(() => tryInitChart(), 100);
        }
    }

    updateChart() {
        if (!this.chart || !this.displayData.length) return;

        // 按任务分组数据
        const taskData = {};
        this.displayData.forEach(record => {
            if (!taskData[record.task]) {
                taskData[record.task] = [];
            }
            taskData[record.task].push([record.timestamp, record.value]);
        });

        // 生成系列数据
        const series = [];
        const colors = ['#1890ff', '#52c41a', '#faad14'];
        let colorIndex = 0;
        
        Object.keys(taskData).forEach(task => {
            series.push({
                name: task,
                type: 'line',
                data: taskData[task],
                smooth: true,
                symbol: 'circle',
                symbolSize: 4,
                lineStyle: {
                    width: 2,
                    color: colors[colorIndex % colors.length]
                },
                itemStyle: {
                    color: colors[colorIndex % colors.length]
                }
            });
            colorIndex++;
        });

        const option = {
            title: {
                text: '多任务对比分析',
                left: 'center',
                top: 10,
                textStyle: {
                    fontSize: 14,
                    fontWeight: 'bold'
                }
            },
            tooltip: {
                trigger: 'axis',
                formatter: function(params) {
                    if (!params || params.length === 0) return '';
                    const time = new Date(params[0].value[0]).toLocaleString();
                    let result = `时间: ${time}<br/>`;
                    params.forEach(param => {
                        result += `${param.seriesName}: ${param.value[1].toFixed(2)}<br/>`;
                    });
                    return result;
                }
            },
            legend: {
                data: Object.keys(taskData),
                top: 40,
                left: 'center'
            },
            grid: {
                left: '8%',
                right: '8%',
                bottom: '20%',
                top: '25%'
            },
            xAxis: {
                type: 'time',
                axisLabel: {
                    formatter: function(value) {
                        return new Date(value).toLocaleString();
                    }
                }
            },
            yAxis: {
                type: 'value',
                axisLabel: {
                    formatter: function(value) {
                        return value.toFixed(2);
                    }
                }
            },
            dataZoom: [
                {
                    type: 'inside',
                    start: 0,
                    end: 100
                },
                {
                    start: 0,
                    end: 100,
                    handleStyle: {
                        backgroundColor: '#1890ff'
                    }
                }
            ],
            toolbox: {
                right: 20,
                feature: {
                    restore: {},
                    saveAsImage: {},
                    dataView: {
                        readOnly: true,
                        title: '数据视图',
                        lang: ['数据视图', '关闭', '刷新']
                    }
                }
            },
            series: series
        };

        this.chart.setOption(option, true);
    }

    getTrendChartOption(data) {
        return {
            title: {
                text: '趋势分析',
                left: 'center',
                top: 10,
                textStyle: {
                    fontSize: 14,
                    fontWeight: 'bold'
                }
            },
            tooltip: {
                trigger: 'axis',
                formatter: function(params) {
                    if (!params || params.length === 0) return '';
                    const time = new Date(params[0].value[0]).toLocaleString();
                    return `时间: ${time}<br/>数值: ${params[0].value[1].toFixed(2)}`;
                }
            },
            grid: {
                left: '8%',
                right: '8%',
                bottom: '20%',
                top: '20%'
            },
            xAxis: {
                type: 'time',
                axisLabel: {
                    formatter: function(value) {
                        return new Date(value).toLocaleString();
                    }
                }
            },
            yAxis: {
                type: 'value',
                axisLabel: {
                    formatter: function(value) {
                        return value.toFixed(2);
                    }
                }
            },
            dataZoom: [
                {
                    type: 'inside',
                    start: 0,
                    end: 100
                },
                {
                    start: 0,
                    end: 100,
                    handleStyle: {
                        backgroundColor: '#3370ff'
                    }
                }
            ],
            toolbox: {
                right: 20,
                feature: {
                    restore: {},
                    saveAsImage: {},
                    dataView: {
                        readOnly: true,
                        title: '数据视图',
                        lang: ['数据视图', '关闭', '刷新']
                    }
                }
            },
            series: [{
                name: '数值',
                type: 'line',
                data: data,
                smooth: true,
                symbol: 'none',
                lineStyle: {
                    width: 2,
                    color: '#1890ff'
                },
                areaStyle: {
                    opacity: 0.3,
                    color: '#1890ff'
                }
            }]
        };
    }

    getCorrelationChartOption(data) {
        return {
            title: {
                text: '相关性分析',
                left: 'center',
                top: 10,
                textStyle: {
                    fontSize: 14,
                    fontWeight: 'bold'
                }
            },
            tooltip: {
                trigger: 'axis',
                formatter: function(params) {
                    if (!params || params.length === 0) return '';
                    const time = new Date(params[0].value[0]).toLocaleString();
                    return `时间: ${time}<br/>数值: ${params[0].value[1].toFixed(2)}`;
                }
            },
            grid: {
                left: '8%',
                right: '8%',
                bottom: '20%',
                top: '20%'
            },
            xAxis: {
                type: 'time',
                axisLabel: {
                    formatter: function(value) {
                        return new Date(value).toLocaleString();
                    }
                }
            },
            yAxis: {
                type: 'value',
                axisLabel: {
                    formatter: function(value) {
                        return value.toFixed(2);
                    }
                }
            },
            dataZoom: [
                {
                    type: 'inside',
                    start: 0,
                    end: 100
                },
                {
                    start: 0,
                    end: 100,
                    handleStyle: {
                        backgroundColor: '#52c41a'
                    }
                }
            ],
            toolbox: {
                right: 20,
                feature: {
                    restore: {},
                    saveAsImage: {},
                    dataView: {
                        readOnly: true,
                        title: '数据视图',
                        lang: ['数据视图', '关闭', '刷新']
                    }
                }
            },
            series: [{
                name: '数值',
                type: 'line',
                data: data,
                smooth: true,
                symbol: 'circle',
                symbolSize: 4,
                lineStyle: {
                    width: 2,
                    color: '#52c41a'
                }
            }]
        };
    }

    getAnomalyChartOption(data) {
        const normalData = [];
        const abnormalData = [];
        
        this.displayData.forEach((record, index) => {
            const point = [record.timestamp, record.value];
            if (record.status === 'abnormal') {
                abnormalData.push(point);
            } else {
                normalData.push(point);
            }
        });

        return {
            title: {
                text: '异常检测',
                left: 'center',
                top: 10,
                textStyle: {
                    fontSize: 14,
                    fontWeight: 'bold'
                }
            },
            tooltip: {
                trigger: 'axis',
                formatter: function(params) {
                    if (!params || params.length === 0) return '';
                    const time = new Date(params[0].value[0]).toLocaleString();
                    return `时间: ${time}<br/>数值: ${params[0].value[1].toFixed(2)}`;
                }
            },
            legend: {
                data: ['正常数据', '异常数据'],
                top: 40,
                left: 'center'
            },
            grid: {
                left: '8%',
                right: '8%',
                bottom: '20%',
                top: '25%'
            },
            xAxis: {
                type: 'time',
                axisLabel: {
                    formatter: function(value) {
                        return new Date(value).toLocaleString();
                    }
                }
            },
            yAxis: {
                type: 'value',
                axisLabel: {
                    formatter: function(value) {
                        return value.toFixed(2);
                    }
                }
            },
            dataZoom: [
                {
                    type: 'inside',
                    start: 0,
                    end: 100
                },
                {
                    start: 0,
                    end: 100,
                    handleStyle: {
                        backgroundColor: '#ff4d4f'
                    }
                }
            ],
            toolbox: {
                right: 20,
                feature: {
                    restore: {},
                    saveAsImage: {},
                    dataView: {
                        readOnly: true,
                        title: '数据视图',
                        lang: ['数据视图', '关闭', '刷新']
                    }
                }
            },
            series: [
                {
                    name: '正常数据',
                    type: 'line',
                    data: normalData,
                    smooth: true,
                    symbol: 'none',
                    lineStyle: {
                        width: 2,
                        color: '#1890ff'
                    }
                },
                {
                    name: '异常数据',
                    type: 'scatter',
                    data: abnormalData,
                    symbolSize: 8,
                    itemStyle: {
                        color: '#ff4d4f'
                    }
                }
            ]
        };
    }

    getPredictionChartOption(data) {
        // 模拟预测数据（实际项目中应该从后端获取）
        const predictData = [];
        const actualData = data.slice(0, Math.floor(data.length * 0.8)); // 前80%作为实际数据
        const predictStart = actualData.length;
        
        // 生成预测数据
        for (let i = predictStart; i < data.length; i++) {
            const lastValue = actualData[actualData.length - 1][1];
            const predictedValue = lastValue + (Math.random() - 0.5) * 10;
            predictData.push([data[i][0], predictedValue]);
        }

        return {
            title: {
                text: '预测分析',
                left: 'center',
                top: 10,
                textStyle: {
                    fontSize: 14,
                    fontWeight: 'bold'
                }
            },
            tooltip: {
                trigger: 'axis',
                formatter: function(params) {
                    if (!params || params.length === 0) return '';
                    const time = new Date(params[0].value[0]).toLocaleString();
                    let result = `时间: ${time}<br/>`;
                    params.forEach(param => {
                        result += `${param.seriesName}: ${param.value[1].toFixed(2)}<br/>`;
                    });
                    return result;
                }
            },
            legend: {
                data: ['实际数据', '预测数据'],
                top: 40,
                left: 'center'
            },
            grid: {
                left: '8%',
                right: '8%',
                bottom: '20%',
                top: '25%'
            },
            xAxis: {
                type: 'time',
                axisLabel: {
                    formatter: function(value) {
                        return new Date(value).toLocaleString();
                    }
                }
            },
            yAxis: {
                type: 'value',
                axisLabel: {
                    formatter: function(value) {
                        return value.toFixed(2);
                    }
                }
            },
            dataZoom: [
                {
                    type: 'inside',
                    start: 0,
                    end: 100
                },
                {
                    start: 0,
                    end: 100,
                    handleStyle: {
                        backgroundColor: '#722ed1'
                    }
                }
            ],
            toolbox: {
                right: 20,
                feature: {
                    restore: {},
                    saveAsImage: {},
                    dataView: {
                        readOnly: true,
                        title: '数据视图',
                        lang: ['数据视图', '关闭', '刷新']
                    }
                }
            },
            series: [
                {
                    name: '实际数据',
                    type: 'line',
                    data: actualData,
                    smooth: true,
                    symbol: 'none',
                    lineStyle: {
                        width: 2,
                        color: '#1890ff'
                    }
                },
                {
                    name: '预测数据',
                    type: 'line',
                    data: predictData,
                    smooth: true,
                    symbol: 'none',
                    lineStyle: {
                        width: 2,
                        color: '#722ed1',
                        type: 'dashed'
                    }
                }
            ]
        };
    }

    updateTable() {
        const tbody = this.shadowRoot.getElementById('tableBody');
        if (!tbody) return;

        tbody.innerHTML = '';
        
        if (!this.displayData.length) {
            const tr = document.createElement('tr');
            const td = document.createElement('td');
            td.colSpan = 6;
            td.style.textAlign = 'center';
            td.style.color = '#999';
            td.style.padding = '60px 20px';
            td.style.fontSize = '14px';
            td.textContent = '暂无数据';
            tr.appendChild(td);
            tbody.appendChild(tr);
            
            this.totalPages = 0;
            this.currentPage = 1;
            this.updatePagination();
            return;
        }

        // 计算分页
        this.totalPages = Math.ceil(this.displayData.length / this.pageSize);
        this.currentPage = Math.min(this.currentPage, this.totalPages);
        
        const startIndex = (this.currentPage - 1) * this.pageSize;
        const endIndex = Math.min(startIndex + this.pageSize, this.displayData.length);
        const pageData = this.displayData.slice(startIndex, endIndex);
        
        pageData.forEach((record, index) => {
            const tr = document.createElement('tr');
            
            // 复选框列
            const checkboxTd = document.createElement('td');
            checkboxTd.style.textAlign = 'center';
            const checkbox = document.createElement('input');
            checkbox.type = 'checkbox';
            checkbox.className = 'checkbox-item';
            checkbox.dataset.id = record.id;
            checkboxTd.appendChild(checkbox);
            tr.appendChild(checkboxTd);
            
            // ID列
            const idTd = document.createElement('td');
            idTd.textContent = record.id || '-';
            tr.appendChild(idTd);
            
            // 名称列
            const nameTd = document.createElement('td');
            nameTd.textContent = record.name || '-';
            tr.appendChild(nameTd);
            
            // 运行状态列
            const statusTd = document.createElement('td');
            const statusBadge = document.createElement('span');
            statusBadge.className = `status-badge ${record.status}`;
            statusBadge.textContent = this.getStatusText(record.status);
            statusTd.appendChild(statusBadge);
            tr.appendChild(statusTd);
            
            // 时间列
            const timeTd = document.createElement('td');
            timeTd.textContent = new Date(record.timestamp).toLocaleString();
            tr.appendChild(timeTd);
            
            // 操作列
            const actionTd = document.createElement('td');
            const actionButtons = document.createElement('div');
            actionButtons.className = 'action-buttons';
            
            // 分析按钮
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
            
            // 停止按钮（仅在运行中状态显示）
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
        
        this.updatePagination();
    }

    updatePagination() {
        const pageList = this.shadowRoot.getElementById('pageList');
        const prevBtn = this.shadowRoot.getElementById('prevBtn');
        const nextBtn = this.shadowRoot.getElementById('nextBtn');

        if (!pageList) return;

        pageList.innerHTML = '';
        
        if (this.totalPages <= 1) {
            prevBtn.disabled = true;
            nextBtn.disabled = true;
            return;
        }
        
        for (let i = 1; i <= this.totalPages; i++) {
            const pageBtn = document.createElement('button');
            pageBtn.className = `page-number ${i === this.currentPage ? 'active' : ''}`;
            pageBtn.textContent = i;
            pageBtn.onclick = () => this.goToPage(i);
            pageList.appendChild(pageBtn);
        }

        prevBtn.disabled = this.currentPage === 1;
        nextBtn.disabled = this.currentPage === this.totalPages;
    }

    goToPage(page) {
        this.currentPage = page;
        this.updateTable();
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

    // 处理状态筛选
    handleStatusFilter(filterValue) {
        this.currentFilter.status = filterValue;
        this.applyFilters();
    }

    // 处理名称搜索
    handleNameSearch(searchValue) {
        this.currentFilter.name = searchValue.toLowerCase();
        this.applyFilters();
    }

    // 处理时间范围搜索
    handleTimeSearch(dateRange) {
        this.currentFilter.time = dateRange;
        this.applyFilters();
    }

    // 应用所有筛选条件
    applyFilters() {
        this.currentPage = 1; // 重置到第一页
        
        // 从所有数据开始筛选
        let filteredData = [...this.allData];
        
        // 应用状态筛选
        if (this.currentFilter.status) {
            filteredData = filteredData.filter(record => record.status === this.currentFilter.status);
        }
        
        // 应用名称搜索
        if (this.currentFilter.name) {
            filteredData = filteredData.filter(record => 
                record.name.toLowerCase().includes(this.currentFilter.name)
            );
        }
        
        // 应用时间范围筛选
        if (this.currentFilter.time && this.currentFilter.time.start && this.currentFilter.time.end) {
            filteredData = filteredData.filter(record => {
                if (!record.timestamp) return false;
                const recordDate = new Date(record.timestamp);
                return recordDate >= this.currentFilter.time.start && 
                       recordDate <= this.currentFilter.time.end;
            });
        }
        
        // 更新显示数据
        this.displayData = filteredData;
        this.updateTable();
    }

    // 处理全选
    handleSelectAll(checked) {
        const checkboxes = this.shadowRoot.querySelectorAll('.checkbox-item');
        checkboxes.forEach(checkbox => {
            checkbox.checked = checked;
        });
    }

    // 处理分析操作
    handleAnalyze(record) {
        if (record.status !== 'success' && record.status !== 'stopped') {
            this.showToast('只能分析成功或已完成的任务', 'warning');
            return;
        }
        
        this.showToast(`正在分析单个任务: ${record.name}`, 'info');
        console.log('分析单个任务:', record);
        
        // 显示单个任务分析
        this.showSingleTaskAnalysis(record);
    }

    // 显示单个任务分析
    showSingleTaskAnalysis(task) {
        this.currentAnalysisMode = 'single';
        
        if (!this.chart) {
            this.initChart();
        }
        
        // 生成单个任务的数据并缓存
        const singleTaskData = this.generateSingleTaskData(task);
        this.currentChartData = {
            type: 'single',
            data: singleTaskData,
            task: task
        };
        
        this.updateSingleTaskChart(singleTaskData);
    }

    // 生成单个任务的数据
    generateSingleTaskData(task) {
        const taskData = {
            id: task.id,
            name: task.name,
            inputData: [],
            calculationResult: [],
            timePoints: []
        };

        // 生成单个任务的输入数据和计算结果数据
        const timePoints = 50;
        for (let i = 0; i < timePoints; i++) {
            const relativeTime = i * 10; // 每10秒一个数据点
            
            // 输入数据曲线
            const inputBaseValue = 100;
            const inputNoise = (Math.random() - 0.5) * 30;
            const inputValue = inputBaseValue + inputNoise + Math.sin(i * 0.2) * 15;
            
            // 计算结果曲线
            const resultBaseValue = inputValue * 1.2;
            const resultNoise = (Math.random() - 0.5) * 20;
            const resultValue = resultBaseValue + resultNoise + Math.cos(i * 0.15) * 10;
            
            taskData.inputData.push([relativeTime, parseFloat(inputValue.toFixed(2))]);
            taskData.calculationResult.push([relativeTime, parseFloat(resultValue.toFixed(2))]);
            taskData.timePoints.push(relativeTime);
        }

        return taskData;
    }

    // 更新单个任务图表
    updateSingleTaskChart(taskData) {
        if (!this.chart) return;

        const series = [];
        
        // 输入数据曲线（虚线）
        if (this.curveVisibility.input) {
            series.push({
                name: '输入数据',
                type: 'line',
                data: taskData.inputData,
                smooth: true,
                symbol: 'circle',
                symbolSize: 4,
                lineStyle: {
                    width: 2,
                    color: '#1890ff',
                    type: 'dashed'
                },
                itemStyle: {
                    color: '#1890ff'
                }
            });
        }

        // 计算结果曲线（实线）
        if (this.curveVisibility.output) {
            series.push({
                name: '计算结果',
                type: 'line',
                data: taskData.calculationResult,
                smooth: true,
                symbol: 'diamond',
                symbolSize: 4,
                lineStyle: {
                    width: 2,
                    color: '#52c41a',
                    type: 'solid'
                },
                itemStyle: {
                    color: '#52c41a'
                }
            });
        }

        const option = {
            title: {
                text: `单个任务分析 - ${taskData.name}`,
                left: 'center',
                top: 10,
                textStyle: {
                    fontSize: 14,
                    fontWeight: 'bold'
                }
            },
            tooltip: {
                trigger: 'axis',
                formatter: function(params) {
                    if (!params || params.length === 0) return '';
                    const time = params[0].value[0];
                    let result = `相对时间: ${time}s<br/>`;
                    params.forEach(param => {
                        result += `${param.seriesName}: ${param.value[1].toFixed(2)}<br/>`;
                    });
                    return result;
                }
            },
            legend: {
                data: series.map(s => s.name),
                top: 40,
                left: 'center',
                itemWidth: 25,
                itemHeight: 14
            },
            grid: {
                left: '8%',
                right: '8%',
                bottom: '20%',
                top: '25%'
            },
            xAxis: {
                type: 'value',
                name: '相对时间 (秒)',
                nameLocation: 'middle',
                nameGap: 30,
                axisLabel: {
                    formatter: function(value) {
                        return value + 's';
                    }
                },
                min: 0,
                max: Math.max(...taskData.timePoints)
            },
            yAxis: {
                type: 'value',
                name: '数值',
                nameLocation: 'middle',
                nameGap: 50,
                axisLabel: {
                    formatter: function(value) {
                        return value.toFixed(1);
                    }
                }
            },
            dataZoom: [
                {
                    type: 'inside',
                    start: 0,
                    end: 100
                },
                {
                    start: 0,
                    end: 100,
                    handleStyle: {
                        backgroundColor: '#1890ff'
                    }
                }
            ],
            toolbox: {
                right: 20,
                feature: {
                    restore: {},
                    saveAsImage: {},
                    dataView: {
                        readOnly: true,
                        title: '数据视图',
                        lang: ['数据视图', '关闭', '刷新']
                    }
                }
            },
            series: series
        };

        this.chart.setOption(option, true);
    }

    // 切换输入数据显示
    toggleInputData() {
        this.curveVisibility.input = !this.curveVisibility.input;
        this.updateToggleButtonState('toggleInputBtn', this.curveVisibility.input);
        this.refreshCurrentChart();
    }

    // 切换输出数据显示
    toggleOutputData() {
        this.curveVisibility.output = !this.curveVisibility.output;
        this.updateToggleButtonState('toggleOutputBtn', this.curveVisibility.output);
        this.refreshCurrentChart();
    }

    // 更新切换按钮状态
    updateToggleButtonState(buttonId, isActive) {
        const button = this.shadowRoot.getElementById(buttonId);
        if (button) {
            if (isActive) {
                button.classList.remove('inactive');
            } else {
                button.classList.add('inactive');
            }
        }
    }

    // 刷新当前图表
    refreshCurrentChart() {
        if (!this.currentChartData || !this.chart) return;
        
        if (this.currentChartData.type === 'comparison') {
            // 重新渲染对比图表，使用缓存的数据
            this.updateComparisonChart(this.currentChartData.data);
        } else if (this.currentChartData.type === 'single') {
            // 重新渲染单个任务图表，使用缓存的数据
            this.updateSingleTaskChart(this.currentChartData.data);
        }
    }

    // 处理生成报告操作
    async handleGenerateReport(record) {
        this.showToast('正在生成实验报告...', 'info');
        
        try {
            // 创建PDF生成器实例
            const pdfGenerator = new LocalPDFGenerator();
            
            // 1. 添加报告标题
            pdfGenerator.addTitle('数据分析实验报告');
            pdfGenerator.addText(`任务名称: ${record.name}`, 12);
            pdfGenerator.addText(`生成时间: ${new Date().toLocaleString()}`, 12);
            pdfGenerator.addSeparator();
            
            // 2. 任务详情部分
            pdfGenerator.addSubtitle('一、任务详情');
            pdfGenerator.addText(`任务ID: ${record.id}`, 12);
            pdfGenerator.addText(`任务名称: ${record.name}`, 12);
            pdfGenerator.addText(`运行状态: ${this.getStatusText(record.status)}`, 12);
            pdfGenerator.addText(`创建时间: ${record.createTime || '2024-01-01 10:00:00'}`, 12);
            pdfGenerator.addText(`更新时间: ${record.updateTime || '2024-01-01 10:30:00'}`, 12);
            pdfGenerator.addText(`任务描述: ${record.description || '这是一个数据分析任务，用于处理和分析相关数据。'}`, 12);
            
            // 3. 模型信息部分
            pdfGenerator.addSubtitle('二、模型信息');
            const modelInfo = this.getModelInfo(record);
            pdfGenerator.addText(`模型类型: ${modelInfo.type}`, 12);
            pdfGenerator.addText(`模型版本: ${modelInfo.version}`, 12);
            pdfGenerator.addText(`算法名称: ${modelInfo.algorithm}`, 12);
            pdfGenerator.addText(`参数配置: ${modelInfo.parameters}`, 12);
            pdfGenerator.addText(`训练数据集: ${modelInfo.dataset}`, 12);
            pdfGenerator.addText(`准确率: ${modelInfo.accuracy}`, 12);
            
            // 4. 添加实际图表
            pdfGenerator.addSubtitle('三、分析图表');
            
            // 捕获当前图表
            const chartElement = this.shadowRoot.getElementById('analysisChart');
            if (chartElement && this.chart) {
                await pdfGenerator.addImage(chartElement, '分析图表', '当前任务的数据分析图表');
            } else {
                pdfGenerator.addImagePlaceholder('分析图表', '当前任务的数据分析图表');
            }
            
            // 5. 添加数据表格
            pdfGenerator.addSubtitle('四、数据表格');
            
            // 直接使用表格数据生成PDF表格
            const tableHeaders = ['ID', '名称', '状态', '时间'];
            const tableData = this.displayData.slice(0, 10).map(item => [
                item.id,
                item.name,
                this.getStatusText(item.status),
                item.time || '2024-01-01 10:00:00'
            ]);
            pdfGenerator.addTable(tableHeaders, tableData);
            
            // 6. 统计指标部分
            pdfGenerator.addSubtitle('五、统计指标');
            const statistics = this.getStatistics(record);
            const statsHeaders = ['指标名称', '数值', '单位', '说明'];
            const statsData = [
                ['数据总量', statistics.totalData, '条', '处理的数据记录总数'],
                ['处理时间', statistics.processTime, '秒', '任务执行总时间'],
                ['内存使用', statistics.memoryUsage, 'MB', '峰值内存使用量'],
                ['CPU使用率', statistics.cpuUsage, '%', '平均CPU使用率'],
                ['准确率', statistics.accuracy, '%', '模型预测准确率'],
                ['召回率', statistics.recall, '%', '模型召回率'],
                ['F1分数', statistics.f1Score, '', '综合评价指标'],
                ['数据质量', statistics.dataQuality, '分', '数据质量评分']
            ];
            pdfGenerator.addTable(statsHeaders, statsData);
            
            // 7. 结论和建议
            pdfGenerator.addSubtitle('六、结论和建议');
            const conclusions = this.getConclusions(record);
            conclusions.forEach(conclusion => {
                pdfGenerator.addText(`• ${conclusion}`, 12);
            });
            
            pdfGenerator.addSeparator();
            pdfGenerator.addSubtitle('七、建议');
            const recommendations = this.getRecommendations(record);
            recommendations.forEach(recommendation => {
                pdfGenerator.addText(`• ${recommendation}`, 12);
            });
            
            // 8. 附录信息
            pdfGenerator.addSubtitle('八、附录');
            pdfGenerator.addText(`报告生成人: 系统自动生成`, 12);
            pdfGenerator.addText(`审核状态: 待审核`, 12);
            pdfGenerator.addText(`报告版本: v1.0`, 12);
            pdfGenerator.addText(`数据来源: 当前分析任务`, 12);
            pdfGenerator.addText(`图表类型: ${this.currentChartData?.type || 'trend'}`, 12);
            
            // 生成并下载报告
            const reportTitle = `实验报告_${record.name}_${new Date().getTime()}`;
            pdfGenerator.generateAndDownload(reportTitle);
            
            this.showToast('实验报告生成成功！', 'success');
            
        } catch (error) {
            console.error('生成报告失败:', error);
            this.showToast('生成报告失败，请稍后重试', 'error');
        }
    }
    
    // 获取模型信息
    getModelInfo(record) {
        // 模拟返回模型信息，实际应该从后端获取
        return {
            type: '深度学习模型',
            version: 'v2.1.0',
            algorithm: 'LSTM神经网络',
            parameters: 'hidden_units=128, epochs=100, batch_size=32',
            dataset: '训练集_2024Q1',
            accuracy: '95.6%'
        };
    }
    
    // 获取统计指标
    getStatistics(record) {
        // 模拟返回统计指标，实际应该从分析结果中获取
        return {
            totalData: '10,000',
            processTime: '120',
            memoryUsage: '512',
            cpuUsage: '75',
            accuracy: '95.6',
            recall: '93.2',
            f1Score: '0.944',
            dataQuality: '92'
        };
    }
    
    // 获取结论
    getConclusions(record) {
        return [
            '数据分析任务执行成功，各项指标均达到预期目标',
            '模型表现良好，准确率和召回率均超过90%',
            '数据处理效率较高，在合理时间内完成了分析任务',
            '数据质量整体良好，满足分析要求'
        ];
    }
    
    // 获取建议
    getRecommendations(record) {
        return [
            '建议定期更新模型，以保持预测准确性',
            '可以进一步优化数据处理流程，提高处理效率',
            '建议增加数据验证步骤，确保数据质量',
            '可以考虑引入更多特征，提升模型性能'
        ];
    }

    // 处理导出操作
    handleExport(record) {
        this.showToast(`正在导出任务数据: ${record.name}`, 'info');
        console.log('导出任务:', record);
    }

    // 处理停止操作
    handleStop(record) {
        this.showToast(`正在停止任务: ${record.name}`, 'warning');
        // 更新状态为停止
        record.status = 'stopped';
        this.updateTable();
        console.log('停止任务:', record);
    }

    // 处理批量对比选中项
    handleCompareSelected() {
        const selectedCheckboxes = this.shadowRoot.querySelectorAll('.checkbox-item:checked');
        if (selectedCheckboxes.length === 0) {
            this.showToast('请先选择要对比的任务', 'warning');
            return;
        }
        
        if (selectedCheckboxes.length < 2) {
            this.showToast('请至少选择2个任务进行对比', 'warning');
            return;
        }
        
        if (selectedCheckboxes.length > 5) {
            this.showToast('对比任务数量不能超过5个，请重新选择', 'warning');
            return;
        }
        
        const selectedIds = Array.from(selectedCheckboxes).map(cb => cb.dataset.id);
        this.showToast(`正在对比 ${selectedIds.length} 个选中的任务`, 'success');
        console.log('批量对比选中项:', selectedIds);
        
        // 显示对比图表
        this.showComparisonChart(selectedIds);
    }

    // 显示对比图表
    showComparisonChart(selectedIds) {
        // 筛选选中的任务数据
        const selectedTasks = this.allData.filter(record => selectedIds.includes(record.id));
        
        if (!this.chart) {
            this.initChart();
        }
        
        // 生成对比图表数据并缓存
        const comparisonData = this.generateComparisonData(selectedTasks);
        this.currentChartData = {
            type: 'comparison',
            data: comparisonData,
            selectedIds: selectedIds
        };
        
        this.updateComparisonChart(comparisonData);
    }

    // 生成对比数据（包含输入数据曲线和计算结果曲线）
    generateComparisonData(selectedTasks) {
        const comparisonData = {
            tasks: [],
            timePoints: [],
            frequencyInconsistent: false,
            targetFrequency: 10 // 默认目标频率：每10秒一个点
        };

        // 为每个任务生成不同采样频率的数据
        const taskFrequencies = [];
        selectedTasks.forEach((task, index) => {
            // 模拟不同的采样频率：5秒、10秒、15秒、20秒间隔
            const frequencies = [5, 10, 15, 20, 8]; // 不同的采样间隔（秒）
            const samplingInterval = frequencies[index % frequencies.length];
            taskFrequencies.push(samplingInterval);
            
            const taskData = {
                id: task.id,
                name: task.name,
                samplingInterval: samplingInterval,
                inputData: [],
                calculationResult: []
            };

            // 根据采样间隔生成数据点
            const maxTime = 490; // 最大时间490秒
            const numPoints = Math.floor(maxTime / samplingInterval) + 1;
            
            for (let i = 0; i < numPoints; i++) {
                const relativeTime = i * samplingInterval;
                
                // 输入数据曲线（模拟原始输入数据）
                const inputBaseValue = 100 + index * 20;
                const inputNoise = (Math.random() - 0.5) * 30;
                const inputValue = inputBaseValue + inputNoise + Math.sin(relativeTime * 0.02) * 15;
                
                // 计算结果曲线（模拟处理后的结果）
                const resultBaseValue = inputValue * 1.2 + index * 10;
                const resultNoise = (Math.random() - 0.5) * 20;
                const resultValue = resultBaseValue + resultNoise + Math.cos(relativeTime * 0.015) * 10;
                
                taskData.inputData.push([relativeTime, parseFloat(inputValue.toFixed(2))]);
                taskData.calculationResult.push([relativeTime, parseFloat(resultValue.toFixed(2))]);
            }

            comparisonData.tasks.push(taskData);
        });

        // 检查采样频率是否一致
        const uniqueFrequencies = [...new Set(taskFrequencies)];
        if (uniqueFrequencies.length > 1) {
            comparisonData.frequencyInconsistent = true;
            // 使用最低频率作为目标频率（降采样）
            comparisonData.targetFrequency = Math.max(...taskFrequencies);
            this.showToast('检测到采样频率不一致，系统将自动进行数据对齐处理', 'info');
        }

        // 频率对齐处理
        comparisonData.tasks = this.alignDataFrequency(comparisonData.tasks, comparisonData.targetFrequency);

        // 生成统一的时间点用于X轴
        const maxTime = 490;
        for (let i = 0; i <= maxTime; i += comparisonData.targetFrequency) {
            comparisonData.timePoints.push(i);
        }

        return comparisonData;
    }

    // 数据频率对齐处理
    alignDataFrequency(tasks, targetInterval) {
        return tasks.map(task => {
            const alignedTask = {
                ...task,
                originalInterval: task.samplingInterval,
                inputData: this.alignDataSeries(task.inputData, targetInterval),
                calculationResult: this.alignDataSeries(task.calculationResult, targetInterval)
            };
            alignedTask.samplingInterval = targetInterval;
            return alignedTask;
        });
    }

    // 对齐单个数据系列
    alignDataSeries(data, targetInterval) {
        if (data.length === 0) return [];
        
        const currentInterval = data[1] ? data[1][0] - data[0][0] : targetInterval;
        
        // 如果频率一致，直接返回
        if (Math.abs(currentInterval - targetInterval) < 0.1) {
            return data;
        }
        
        // 如果当前频率高于目标频率，进行降采样
        if (currentInterval < targetInterval) {
            return this.downsampleData(data, targetInterval);
        }
        // 如果当前频率低于目标频率，进行插值
        else {
            return this.interpolateData(data, targetInterval);
        }
    }

    // 线性插值处理
    interpolateData(data, targetInterval) {
        if (data.length < 2) return data;
        
        const interpolatedData = [];
        const maxTime = 490;
        
        for (let time = 0; time <= maxTime; time += targetInterval) {
            // 找到时间点前后的数据点
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
                // 线性插值计算
                const ratio = (time - leftPoint[0]) / (rightPoint[0] - leftPoint[0]);
                const interpolatedValue = leftPoint[1] + ratio * (rightPoint[1] - leftPoint[1]);
                interpolatedData.push([time, parseFloat(interpolatedValue.toFixed(2))]);
            } else if (leftPoint && leftPoint[0] === time) {
                // 精确匹配的时间点
                interpolatedData.push([time, leftPoint[1]]);
            }
        }
        
        return interpolatedData;
    }

    // 降采样处理
    downsampleData(data, targetInterval) {
        const downsampledData = [];
        const maxTime = 490;
        
        for (let time = 0; time <= maxTime; time += targetInterval) {
            // 找到最接近目标时间的数据点
            let closestPoint = null;
            let minDistance = Infinity;
            
            data.forEach(point => {
                const distance = Math.abs(point[0] - time);
                if (distance < minDistance) {
                    minDistance = distance;
                    closestPoint = point;
                }
            });
            
            if (closestPoint && minDistance <= targetInterval / 2) {
                downsampledData.push([time, closestPoint[1]]);
            }
        }
        
        return downsampledData;
    }

    // 更新对比图表
    updateComparisonChart(comparisonData) {
        if (!this.chart) return;

        const series = [];
        const colors = ['#1890ff', '#52c41a', '#faad14', '#f5222d', '#722ed1', '#13c2c2'];
        let colorIndex = 0;

        // 为每个任务生成两条曲线：输入数据曲线和计算结果曲线
        comparisonData.tasks.forEach(task => {
            const taskColor = colors[colorIndex % colors.length];
            
            // 输入数据曲线（虚线）
            if (this.curveVisibility.input) {
                series.push({
                    name: `${task.name} - 输入数据`,
                    type: 'line',
                    data: task.inputData,
                    smooth: true,
                    symbol: 'circle',
                    symbolSize: 3,
                    lineStyle: {
                        width: 2,
                        color: taskColor,
                        type: 'dashed'
                    },
                    itemStyle: {
                        color: taskColor
                    }
                });
            }

            // 计算结果曲线（实线）
            if (this.curveVisibility.output) {
                series.push({
                    name: `${task.name} - 计算结果`,
                    type: 'line',
                    data: task.calculationResult,
                    smooth: true,
                    symbol: 'diamond',
                    symbolSize: 3,
                    lineStyle: {
                        width: 2,
                        color: taskColor,
                        type: 'solid'
                    },
                    itemStyle: {
                        color: taskColor
                    }
                });
            }

            colorIndex++;
        });

        const option = {
            title: {
                text: '多任务对比分析 - 相对时间',
                left: 'center',
                top: 10,
                textStyle: {
                    fontSize: 14,
                    fontWeight: 'bold'
                }
            },
            tooltip: {
                trigger: 'axis',
                formatter: function(params) {
                    if (!params || params.length === 0) return '';
                    const time = params[0].value[0];
                    let result = `相对时间: ${time}s<br/>`;
                    params.forEach(param => {
                        result += `${param.seriesName}: ${param.value[1].toFixed(2)}<br/>`;
                    });
                    return result;
                }
            },
            legend: {
                data: series.map(s => s.name),
                top: 40,
                left: 'center',
                type: 'scroll',
                itemWidth: 25,
                itemHeight: 14,
                itemGap: 20,
                padding: [5, 10],
                textStyle: {
                    fontSize: 12,
                    padding: [3, 0]
                }
            },
            grid: {
                left: '8%',
                right: '8%',
                bottom: '20%',
                top: '25%'
            },
            xAxis: {
                type: 'value',
                name: '相对时间 (秒)',
                nameLocation: 'middle',
                nameGap: 30,
                axisLabel: {
                    formatter: function(value) {
                        return value + 's';
                    }
                },
                min: 0,
                max: Math.max(...comparisonData.timePoints)
            },
            yAxis: {
                type: 'value',
                name: '数值',
                nameLocation: 'middle',
                nameGap: 50,
                axisLabel: {
                    formatter: function(value) {
                        return value.toFixed(1);
                    }
                }
            },
            dataZoom: [
                {
                    type: 'inside',
                    start: 0,
                    end: 100
                },
                {
                    start: 0,
                    end: 100,
                    handleStyle: {
                        backgroundColor: '#1890ff'
                    }
                }
            ],
            toolbox: {
                right: 20,
                feature: {
                    restore: {},
                    saveAsImage: {},
                    dataView: {
                        readOnly: true,
                        title: '数据视图',
                        lang: ['数据视图', '关闭', '刷新']
                    }
                }
            },
            series: series
        };

        this.chart.setOption(option, true);
    }

    resetAnalysis() {
        this.allData = [];
        this.displayData = [];
        this.currentPage = 1;
        
        // 重置控件
        this.shadowRoot.getElementById('analysisType').value = 'trend';
        this.shadowRoot.getElementById('dataSourceSelect').value = '';
        this.setDefaultTimeRange();
        
        // 清除图表
        if (this.chart) {
            this.chart.dispose();
            this.chart = null;
        }
        
        // 显示空状态
        this.showEmptyState();
        
        this.showToast('已重置分析参数', 'info');
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
            background: ${type === 'success' ? '#52c41a' : type === 'warning' ? '#faad14' : type === 'error' ? '#ff4d4f' : '#3b82f6'};
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
        
        // Remove toast after 3 seconds
        setTimeout(() => {
            toast.style.animation = 'slideOutUp 0.3s ease-out';
            setTimeout(() => {
                if (toast.parentNode) {
                    toast.parentNode.removeChild(toast);
                }
            }, 300);
        }, 3000);
    }
}

// 本地PDF生成器 - 无外网依赖
class LocalPDFGenerator {
    constructor() {
        this.content = [];
        this.yPosition = 50;
        this.pageHeight = 842; // A4高度 (点)
        this.pageWidth = 595; // A4宽度 (点)
        this.margin = 50;
        this.fontSize = 12;
        this.lineHeight = 16;
    }

    // 添加文本
    addText(text, fontSize = 12, bold = false) {
        this.content.push({
            type: 'text',
            text: text,
            fontSize: fontSize,
            bold: bold,
            y: this.yPosition
        });
        this.yPosition += this.lineHeight;
        this.checkPageBreak();
    }

    // 添加标题
    addTitle(text) {
        this.addText(text, 18, true);
        this.yPosition += 10;
    }

    // 添加小标题
    addSubtitle(text) {
        this.addText(text, 14, true);
        this.yPosition += 5;
    }

    // 添加表格
    addTable(headers, data) {
        this.content.push({
            type: 'table',
            headers: headers,
            data: data
        });
        this.yPosition += 20 * (data.length + 2); // 估算表格高度
        this.checkPageBreak();
    }

    // 添加图片（通过Canvas捕获）
    async addImage(element, title, description) {
        try {
            // 使用Canvas捕获元素
            const canvas = await this.captureElement(element);
            const imageData = canvas.toDataURL('image/png');
            
            this.content.push({
                type: 'image',
                title: title,
                description: description,
                imageData: imageData,
                width: canvas.width,
                height: canvas.height
            });
            
            this.yPosition += 250; // 估算图片高度
            this.checkPageBreak();
        } catch (error) {
            console.error('捕获图片失败:', error);
            // 如果捕获失败，使用占位符
            this.addImagePlaceholder(title, description);
        }
    }
    
    // 捕获表格内容
    async captureTable() {
        const tableElement = this.shadowRoot.querySelector('.data-table');
        if (!tableElement) return null;
        
        try {
            // 创建Canvas
            const canvas = document.createElement('canvas');
            const ctx = canvas.getContext('2d');
            
            // 获取表格尺寸
            const rect = tableElement.getBoundingClientRect();
            canvas.width = rect.width;
            canvas.height = rect.height;
            
            // 简单的表格绘制
            ctx.fillStyle = '#ffffff';
            ctx.fillRect(0, 0, canvas.width, canvas.height);
            
            // 绘制表格边框
            ctx.strokeStyle = '#ddd';
            ctx.lineWidth = 1;
            
            // 获取表格数据
            const rows = tableElement.querySelectorAll('tr');
            let y = 0;
            
            rows.forEach((row, index) => {
                const cells = row.querySelectorAll('th, td');
                let x = 0;
                const cellHeight = 30;
                
                cells.forEach((cell, cellIndex) => {
                    const cellWidth = rect.width / cells.length;
                    
                    // 绘制单元格边框
                    ctx.strokeRect(x, y, cellWidth, cellHeight);
                    
                    // 绘制文本
                    ctx.fillStyle = cell.tagName === 'TH' ? '#333' : '#666';
                    ctx.font = cell.tagName === 'TH' ? 'bold 12px Arial' : '11px Arial';
                    ctx.textAlign = 'center';
                    ctx.textBaseline = 'middle';
                    ctx.fillText(cell.textContent, x + cellWidth / 2, y + cellHeight / 2);
                    
                    x += cellWidth;
                });
                
                y += cellHeight;
            });
            
            return canvas;
        } catch (error) {
            console.error('捕获表格失败:', error);
            return null;
        }
    }
    
    // 捕获元素为Canvas
    async captureElement(element) {
        return new Promise((resolve, reject) => {
            // 创建Canvas
            const canvas = document.createElement('canvas');
            const ctx = canvas.getContext('2d');
            
            // 获取元素尺寸
            const rect = element.getBoundingClientRect();
            canvas.width = rect.width;
            canvas.height = rect.height;
            
            // 使用html2canvas的替代方案 - 简单的截图实现
            try {
                // 对于ECharts图表，可以直接获取图表的图片数据
                if (element.id === 'analysisChart' && this.chart) {
                    const chartImage = this.chart.getDataURL({
                        type: 'png',
                        pixelRatio: 2,
                        backgroundColor: '#fff'
                    });
                    
                    const img = new Image();
                    img.onload = () => {
                        ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
                        resolve(canvas);
                    };
                    img.onerror = () => reject(new Error('图表图片加载失败'));
                    img.src = chartImage;
                } else {
                    // 对于其他元素，使用简单的绘制方法
                    ctx.fillStyle = '#f5f5f5';
                    ctx.fillRect(0, 0, canvas.width, canvas.height);
                    ctx.fillStyle = '#666';
                    ctx.font = '14px Arial';
                    ctx.textAlign = 'center';
                    ctx.fillText('截图内容', canvas.width / 2, canvas.height / 2);
                    resolve(canvas);
                }
            } catch (error) {
                reject(error);
            }
        });
    }
    
    // 添加图片占位符
    addImagePlaceholder(title, description) {
        this.addText(title, 12, true);
        this.addText(`[图片: ${description}]`, 10);
        this.addText(`尺寸: 400x300 像素`, 9);
        this.yPosition += 20;
    }

    // 添加分隔线
    addSeparator() {
        this.addText(''.padEnd(50, '-'), 10);
        this.yPosition += 5;
    }

    // 检查是否需要换页
    checkPageBreak() {
        if (this.yPosition > this.pageHeight - this.margin) {
            this.yPosition = this.margin;
            this.content.push({ type: 'newPage' });
        }
    }

    // 添加页眉
    addHeader() {
        this.content.push({
            type: 'header',
            text: '清华大学大数据系统软件国家工程研究中心 - 实验报告',
            y: 30
        });
    }

    // 添加页脚
    addFooter(pageNumber) {
        this.content.push({
            type: 'footer',
            text: `第 ${pageNumber} 页`,
            y: this.pageHeight - 30
        });
    }

    // 添加水印
    addWatermark() {
        this.content.push({
            type: 'watermark',
            text: '清华大学大数据系统软件国家工程研究中心',
            opacity: 0.1
        });
    }

    // 生成HTML内容用于打印
    generateHTML() {
        let html = `
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <title>实验报告</title>
            <style>
                @page {
                    size: A4;
                    margin: 1cm;
                }
                body {
                    font-family: 'SimSun', '宋体', serif;
                    font-size: ${this.fontSize}pt;
                    line-height: 1.5;
                    margin: 0;
                    padding: 0;
                }
                .header {
                    text-align: center;
                    font-size: 14pt;
                    font-weight: bold;
                    margin-bottom: 30px;
                    border-bottom: 2px solid #333;
                    padding-bottom: 10px;
                }
                .footer {
                    text-align: center;
                    font-size: 10pt;
                    margin-top: 30px;
                    border-top: 1px solid #333;
                    padding-top: 10px;
                }
                .title {
                    text-align: center;
                    font-size: 18pt;
                    font-weight: bold;
                    margin: 20px 0;
                }
                .subtitle {
                    font-size: 14pt;
                    font-weight: bold;
                    margin: 15px 0 10px 0;
                }
                .content {
                    margin: 20px;
                }
                .table {
                    width: 100%;
                    border-collapse: collapse;
                    margin: 15px 0;
                }
                .table th, .table td {
                    border: 1px solid #333;
                    padding: 8px;
                    text-align: left;
                }
                .table th {
                    background-color: #f0f0f0;
                    font-weight: bold;
                }
                .image-placeholder {
                    border: 1px dashed #666;
                    padding: 20px;
                    text-align: center;
                    margin: 15px 0;
                    background-color: #f9f9f9;
                }
                .report-image {
                    max-width: 100%;
                    height: auto;
                    margin: 15px 0;
                    border: 1px solid #ddd;
                    box-shadow: 0 2px 4px rgba(0,0,0,0.1);
                }
                .image-title {
                    font-weight: bold;
                    margin: 10px 0 5px 0;
                    text-align: center;
                }
                .watermark {
                    position: fixed;
                    top: 50%;
                    left: 50%;
                    transform: translate(-50%, -50%) rotate(-45deg);
                    font-size: 48pt;
                    color: #ccc;
                    opacity: 0.1;
                    z-index: -1;
                }
                .separator {
                    border-top: 1px solid #666;
                    margin: 20px 0;
                }
                @media print {
                    .watermark {
                        position: fixed;
                        top: 50%;
                        left: 50%;
                        transform: translate(-50%, -50%) rotate(-45deg);
                        font-size: 48pt;
                        color: #ccc;
                        opacity: 0.1;
                        z-index: -1;
                    }
                }
            </style>
        </head>
        <body>
            <div class="watermark">清华大学大数据系统软件国家工程研究中心</div>
            <div class="header">清华大学大数据系统软件国家工程研究中心 - 实验报告</div>
            <div class="content">
        `;

        // 添加内容
        this.content.forEach(item => {
            switch(item.type) {
                case 'text':
                    if (item.bold) {
                        html += `<div style="font-weight: bold; font-size: ${item.fontSize}pt; margin: 5px 0;">${item.text}</div>`;
                    } else {
                        html += `<div style="font-size: ${item.fontSize}pt; margin: 5px 0;">${item.text}</div>`;
                    }
                    break;
                case 'title':
                    html += `<div class="title">${item.text}</div>`;
                    break;
                case 'subtitle':
                    html += `<div class="subtitle">${item.text}</div>`;
                    break;
                case 'table':
                    // 生成HTML表格
                    html += '<table class="table">';
                    // 表头
                    html += '<tr>';
                    item.headers.forEach(header => {
                        html += `<th>${header}</th>`;
                    });
                    html += '</tr>';
                    // 数据行
                    item.data.forEach(row => {
                        html += '<tr>';
                        row.forEach(cell => {
                            html += `<td>${cell}</td>`;
                        });
                        html += '</tr>';
                    });
                    html += '</table>';
                    break;
                case 'image':
                    // 生成图片
                    html += `<div class="image-title">${item.title}</div>`;
                    html += `<img src="${item.imageData}" alt="${item.description}" class="report-image" />`;
                    html += `<div style="text-align: center; font-size: 10pt; color: #666; margin: 5px 0;">${item.description}</div>`;
                    break;
                case 'separator':
                    html += `<div class="separator"></div>`;
                    break;
                case 'newPage':
                    html += `<div style="page-break-before: always;"></div>`;
                    break;
            }
        });

        html += `
            </div>
            <div class="footer">实验报告生成时间: ${new Date().toLocaleString()}</div>
        </body>
        </html>`;

        return html;
    }

    // 生成并下载PDF（通过打印对话框）
    generateAndDownload(title = '实验报告') {
        const htmlContent = this.generateHTML();
        const newWindow = window.open('', '_blank');
        newWindow.document.write(htmlContent);
        newWindow.document.close();
        
        // 延迟触发打印对话框
        setTimeout(() => {
            newWindow.print();
        }, 500);
    }
}

// 注册组件
if (!customElements.get('visual-analysis')) {
    customElements.define('visual-analysis', VisualAnalysis);
}