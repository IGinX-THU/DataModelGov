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
            this.initPagination();
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

    }

    getFallbackHTML() {
        return `
        <div class="visualization-container">
            <div class="visualization-header">
                <h3 class="visualization-title" id="analysisTitle">多任务对比分析</h3>
                <button class="close-btn" id="closeBtn">×</button>
            </div>
            
            <div class="content-area">
                <div class="chart-section">
                    <div class="chart-header">
                        <h4 class="chart-title">分析图表</h4>
                        <div class="chart-actions">
                            <button class="toggle-btn" id="toggleInputBtn" title="切换输入数据显示">
                                输入数据
                            </button>
                            <button class="toggle-btn" id="toggleOutputBtn" title="切换输出数据显示">
                                输出数据
                            </button>
                        </div>
                    </div>
                    <div class="chart-container" id="analysisChart">
                        <!-- ECharts图表将在这里渲染 -->
                    </div>
                </div>
                
                <!-- 数据表格区域 -->
                <div class="table-section">
                    <div class="table-header">
                        <h4 class="table-title">分析数据</h4>
                        <div class="table-controls">
                            <div class="filter-controls">
                                <label for="statusFilter">状态筛选:</label>
                                <select id="statusFilter" class="filter-select">
                                    <option value="">全部</option>
                                    <option value="running">运行中</option>
                                    <option value="stopped">已停止</option>
                                    <option value="pending">等待中</option>
                                    <option value="success">成功</option>
                                    <option value="failed">失败</option>
                                </select>
                                <label for="nameSearch">名称搜索:</label>
                                <input type="text" id="nameSearch" class="search-input" placeholder="搜索任务名称">
                                
                                <!-- Time Range Selection -->
                                <div class="time-range-container">
                                    <span class="time-range-label">时间范围:</span>
                                    <input type="datetime-local" id="startTime" class="datetime-input" aria-label="开始时间">
                                    <span class="time-range-separator">至</span>
                                    <input type="datetime-local" id="endTime" class="datetime-input" aria-label="结束时间">
                                </div>
                                <button class="toolbar-btn blue" id="searchBtn" title="搜索">
                                    <i class="search-icon">🔍</i> 搜索
                                </button>
                            </div>
                            <div class="table-actions">
                                <button class="toolbar-btn poor" id="compareBtn" title="对比选中任务">
                                    对比
                                </button>
                            </div>
                        </div>
                    </div>
                    <div class="table-wrapper">
                        <table class="data-table">
                            <thead>
                                <tr>
                                    <th style="width: 40px; text-align: center;">
                                        <input type="checkbox" id="selectAll" class="checkbox-all">
                                    </th>
                                    <th>ID</th>
                                    <th>名称</th>
                                    <th>运行状态</th>
                                    <th>时间</th>
                                    <th>操作</th>
                                </tr>
                            </thead>
                            <tbody id="tableBody">
                                <!-- 动态生成表格数据 -->
                            </tbody>
                        </table>
                    </div>
                    <common-pagination id="pagination"></common-pagination>
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
            this.initPagination();
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
        // 从API加载数据
        this.loadTasksFromAPI();
        
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
        // 搜索按钮
        const searchBtn = this.shadowRoot.getElementById('searchBtn');
        if (searchBtn) {
            searchBtn.addEventListener('click', () => {
                this.currentPage = 1;
                this.loadTasksFromAPI();
            });
        }
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
        // const nameSearch = this.shadowRoot.getElementById('nameSearch');
        // if (nameSearch) {
        //     nameSearch.addEventListener('input', (e) => {
        //         this.handleNameSearch(e.target.value);
        //     });
        // }

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
        const dataPoints = 100; // 生成100个任务以便测试滚动
        
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
            const timestamp = now - (dataPoints - i) * 60000; // 每分钟一个任务
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
                        result += `${param.seriesName}: ${(param.value[1] || 0).toFixed(2)}<br/>`;
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
                    return `时间: ${time}<br/>数值: ${(params[0].value[1] || 0).toFixed(2)}`;
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
                    return `时间: ${time}<br/>数值: ${(params[0].value[1] || 0).toFixed(2)}`;
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
                    return `时间: ${time}<br/>数值: ${(params[0].value[1] || 0).toFixed(2)}`;
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
                        result += `${param.seriesName}: ${(param.value[1] || 0).toFixed(2)}<br/>`;
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
        this.currentPage = 1;
        this.loadTasksFromAPI();
    }

    // 处理名称搜索
    handleNameSearch(searchValue) {
        this.currentFilter.name = searchValue.toLowerCase();
        this.currentPage = 1;
        this.loadTasksFromAPI();
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
    async handleAnalyze(record) {
        if (record.status !== 'success' && record.status !== 'stopped') {
            this.showToast('只能分析成功或已完成的任务', 'warning');
            return;
        }

        this.showToast(`正在分析单个任务: ${record.name}`, 'info');
        console.log('分析单个任务:', record);

        try {
            // 调用数据查询接口
            const queryData = await this.queryDataForAnalysis(record);

            if (queryData) {
                // 显示单个任务分析
                this.showSingleTaskAnalysis(record, queryData);
            } else {
                this.showToast('数据查询失败，无法进行分析', 'error');
            }
        } catch (error) {
            console.error('分析失败:', error);
            this.showToast('分析出现错误，请重试', 'error');
        }
    }

    // 查询分析数据
    async queryDataForAnalysis(record) {
        try {
            // 解析输入和输出测点路径
            let inputPaths = [];
            let outputPaths = [];

            try {
                inputPaths = JSON.parse(record.inputMeasurements || '[]');
            } catch (e) {
                console.warn('解析 inputMeasurements 失败:', e);
            }

            try {
                outputPaths = JSON.parse(record.outputMeasurements || '[]');
            } catch (e) {
                console.warn('解析 outputMeasurements 失败:', e);
            }

            // 合并所有测点路径
            const allPaths = [...inputPaths, ...outputPaths];

            if (allPaths.length === 0) {
                this.showToast('没有可用的测点路径，无法查询数据', 'warning');
                return null;
            }

            // 构建请求参数
            const requestBody = {
                paths: allPaths,
                startTime: record.startTime || record.timestamp,
                endTime: record.endTime || (record.timestamp + 86400000), // 默认24小时
                aggregateType: null, // 不使用聚合
                precision: 0, // 不使用时间间隔
                timePrecision: null // 不使用时间精度
            };

            console.log('查询数据参数:', requestBody);

            // 调用数据查询接口
            const result = await window.AppConfig.post('data', 'query', requestBody);

            if (result.success && result.data) {
                console.log('查询到的数据:', result.data);
                
                // 检查数据结构
                if (result.data.records && Array.isArray(result.data.records)) {
                    console.log('数据记录数量:', result.data.records.length);
                    if (result.data.records.length > 0) {
                        console.log('第一条记录示例:', result.data.records[0]);
                    }
                }

                // 处理查询结果，按路径分组并区分输入输出
                const processedData = this.processQueryData(result.data, inputPaths, outputPaths);

                return processedData;
            } else {
                console.error('数据查询失败:', result);
                return null;
            }
        } catch (error) {
            console.error('数据查询异常:', error);
            return null;
        }
    }

    // 处理查询数据，按路径分组并区分输入输出
    processQueryData(queryResult, inputPaths, outputPaths) {
        const pathData = {};

        // 初始化路径数据
        [...inputPaths, ...outputPaths].forEach(path => {
            pathData[path] = [];
        });

        // 处理查询结果 - API返回的数据结构是 {header: Array, records: Array}
        if (queryResult && queryResult.records && Array.isArray(queryResult.records)) {
            console.log('处理查询记录:', queryResult.records);
            
            queryResult.records.forEach(record => {
                // 使用 record.key 作为时间戳
                if (record.key) {
                    try {
                        const timestamp = new Date(record.key).getTime();
                        // 检查时间戳是否有效
                        if (isNaN(timestamp)) {
                            console.warn('时间解析失败，跳过数据:', record.key);
                            return; // 跳过这条数据
                        }

                        // 遍历所有测点路径
                        [...inputPaths, ...outputPaths].forEach(path => {
                            if (record[path] !== null && record[path] !== undefined) {
                                pathData[path].push({
                                    timestamp: timestamp,
                                    value: record[path]
                                });
                            }
                        });
                    } catch (error) {
                        console.warn('时间解析异常，跳过数据:', record.key, error);
                    }
                }
            });
        } else {
            console.warn('查询结果格式不正确:', queryResult);
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

        console.log('处理后的数据:', {
            inputData,
            outputData,
            pathData
        });

        return {
            inputData,
            outputData,
            allPathData: pathData
        };
    }

    // 显示单个任务分析
    showSingleTaskAnalysis(task, queryData = null) {
        this.currentAnalysisMode = 'single';

        let chartData;

        if (queryData) {
            // 使用查询到的真实数据
            chartData = this.processChartDataFromQuery(task, queryData);
        } else {
            // 回退到模拟数据
            chartData = this.generateSingleTaskData(task);
        }

        this.currentChartData = {
            type: 'single',
            data: chartData,
            task: task
        };

        // 确保图表初始化完成后再更新数据
        if (!this.chart) {
            this.initChart();
            // 等待图表初始化完成
            setTimeout(() => {
                this.updateChartWithData(chartData);
            }, 200);
        } else {
            this.updateChartWithData(chartData);
        }
    }

    // 从查询数据生成图表数据
    processChartDataFromQuery(task, queryData) {
        return {
            id: task.id,
            name: task.name,
            inputData: queryData.inputData,
            outputData: queryData.outputData
        };
    }

// 基于查询数据更新图表
    updateChartWithData(chartData) {
        if (!this.chart) return;

        const series = [];
        const colors = ['#1890ff', '#52c41a', '#faad14', '#f5222d', '#722ed1', '#13c2c2'];
        let colorIndex = 0;

        // 处理输入数据 - 使用虚线
        if (chartData.inputData && this.curveVisibility.input) {
            Object.keys(chartData.inputData).forEach(path => {
                const data = chartData.inputData[path].map(point => [
                    point.timestamp,
                    point.value
                ]);

                const color = colors[colorIndex % colors.length];
                series.push({
                    name: `${path} (输入)`,
                    type: 'line',
                    data: data,
                    smooth: true,
                    symbol: 'circle',
                    symbolSize: 4,
                    showSymbol: false,
                    lineStyle: {
                        width: 2,
                        color: color,
                        type: 'dashed' // 虚线
                    },
                    itemStyle: {
                        color: color
                    }
                });

                colorIndex++;
            });
        }

        // 处理输出数据 - 使用实线
        if (chartData.outputData && this.curveVisibility.output) {
            Object.keys(chartData.outputData).forEach(path => {
                const data = chartData.outputData[path].map(point => [
                    point.timestamp,
                    point.value
                ]);

                const color = colors[colorIndex % colors.length];
                series.push({
                    name: `${path} (输出)`,
                    type: 'line',
                    data: data,
                    smooth: true,
                    symbol: 'diamond',
                    symbolSize: 4,
                    showSymbol: false,
                    lineStyle: {
                        width: 2,
                        color: color,
                        type: 'solid' // 实线
                    },
                    itemStyle: {
                        color: color
                    }
                });

                colorIndex++;
            });
        }

        // 基于 data-visualization 的图表配置
        const option = {
            title: {
                text: `数据分析 - ${chartData.name}`,
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
                        // 检查数据是否存在且有效
                        if (param.value && param.value[1] !== undefined && param.value[1] !== null && !isNaN(param.value[1])) {
                            result += `${param.seriesName}: ${param.value[1].toFixed(2)}<br/>`;
                        } else {
                            result += `${param.seriesName}: 无数据<br/>`;
                        }
                    });
                    return result;
                }
            },
            legend: {
                data: series.map(s => s.name),
                top: 40,
                left: 'center',
                textStyle: {
                    fontSize: 12
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
            const relativeTime = i * 10; // 每10秒一个任务
            
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
                        result += `${param.seriesName}: ${(param.value[1] || 0).toFixed(2)}<br/>`;
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
                max: taskData.timePoints ? Math.max(...taskData.timePoints) : 100
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
            // 检查数据结构来决定使用哪个更新方法
            const chartData = this.currentChartData.data;
            
            // 如果有 inputData 和 outputData 对象（真实数据），使用 updateChartWithData
            if (chartData.inputData && chartData.outputData) {
                this.updateChartWithData(chartData);
            } else {
                // 否则使用模拟数据的更新方法
                this.updateSingleTaskChart(chartData);
            }
        }
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

        // 创建加载提示（参考previewFile的Loading.service）
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
            pdfGenerator.addText(`任务ID: ${record.id}`, 12);
            pdfGenerator.addText(`任务名称: ${record.name}`, 12);
            pdfGenerator.addText(`当前状态: ${this.getStatusText(record.status)}`, 12);
            pdfGenerator.addText(`数值: ${record.value || 'N/A'}`, 12);
            pdfGenerator.addText(`时间戳: ${new Date(record.timestamp).toLocaleString()}`, 12);
            
            // 3. 添加当前曲线图
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
                pdfGenerator.addImagePlaceholder('曲线图', '当前任务的的趋势分析图表');
            }
            
            // 4. 数据视图
            pdfGenerator.addSubtitle('三、数据视图');
            const allData = [];
            const pathInfo = {}; // 存储测点信息
            
            // 添加输入数据
            if (this.currentChartData && this.currentChartData.data && this.currentChartData.data.inputData) {
                Object.keys(this.currentChartData.data.inputData).forEach(path => {
                    const data = this.currentChartData.data.inputData[path];
                    if (data && data.length > 0) {
                        pathInfo[path] = { type: '输入数据', data: [] };
                        data.forEach(point => {
                            pathInfo[path].data.push({
                                timestamp: point.timestamp,
                                value: point.value
                            });
                        });
                    }
                });
            }
            
            // 添加输出数据
            if (this.currentChartData && this.currentChartData.data && this.currentChartData.data.outputData) {
                Object.keys(this.currentChartData.data.outputData).forEach(path => {
                    const data = this.currentChartData.data.outputData[path];
                    if (data && data.length > 0) {
                        pathInfo[path] = { type: '输出数据', data: [] };
                        data.forEach(point => {
                            pathInfo[path].data.push({
                                timestamp: point.timestamp,
                                value: point.value
                            });
                        });
                    }
                });
            }
            
            if (Object.keys(pathInfo).length > 0) {
                // 收集所有时间点
                const allTimestamps = new Set();
                Object.values(pathInfo).forEach(info => {
                    info.data.forEach(point => {
                        allTimestamps.add(point.timestamp);
                    });
                });
                
                const sortedTimestamps = Array.from(allTimestamps).sort((a, b) => a - b);
                
                // 构建表头：时间 + 每个测点（包含类型）
                const headers = ['时间'];
                Object.keys(pathInfo).forEach(path => {
                    headers.push(`${path} (${pathInfo[path].type})`);
                });
                
                // 构建数据行：每个时间点一行
                const rows = sortedTimestamps.map(timestamp => {
                    const row = [new Date(timestamp).toLocaleString()];
                    
                    Object.keys(pathInfo).forEach(path => {
                        const point = pathInfo[path].data.find(p => p.timestamp === timestamp);
                        row.push(point && point.value !== null && point.value !== undefined ? point.value.toFixed(2) : 'N/A');
                    });
                    
                    return row;
                });
                
                pdfGenerator.addTable(headers, rows);
            } else {
                pdfGenerator.addText('暂无数据', 12);
            }
            
            // 5. 统计分析
            pdfGenerator.addSubtitle('四、统计分析');
            if (this.currentChartData && this.currentChartData.data) {
                const statistics = this.calculateRealDataStatistics(this.currentChartData.data);
                const statsHeaders = ['统计指标', '输入数据', '输出数据', '说明'];
                const statsData = [
                    ['测点数量', statistics.inputPaths, statistics.outputPaths, '测点路径数量'],
                    ['任务数量', statistics.inputCount, statistics.resultCount, '有效任务个数'],
                    ['平均值', statistics.inputMean, statistics.resultMean, '数据平均值'],
                    ['标准差', statistics.inputStdDev, statistics.resultStdDev, '数据标准差']
                ];
                pdfGenerator.addTable(statsHeaders, statsData);
            } else {
                pdfGenerator.addText('暂无统计数据', 12);
            }
            
            // 生成并下载PDF
            const fileName = `任务分析报告_${record.name}_${new Date().getTime()}.pdf`;
            pdfGenerator.generateAndDownload(fileName);
            
            this.showToast('报告生成成功！', 'success');
            
        } catch (error) {
            console.error('生成报告失败:', error);
            this.showToast('生成报告出现错误，请联系管理员！', 'error');
        } finally {
            // 移除加载提示（参考previewFile的previewLoadingInstance.close()）
            if (loadingOverlay.parentNode) {
                loadingOverlay.remove();
            }
        }
    }
    
    // 获取输入数据
    getInputData(record) {
        // 模拟输入数据，实际应该从数据源获取
        const inputData = [];
        const now = Date.now();
        
        for (let i = 0; i < 10; i++) {
            const timestamp = now - (10 - i) * 60000; // 最近10个任务
            inputData.push({
                id: `INPUT-${String(i + 1).padStart(3, '0')}`,
                timestamp: timestamp,
                rawValue: 100 + Math.random() * 20 - 10, // 90-110范围
                dataSource: this.dataSource || 'X022-CQ-1',
                quality: Math.random() > 0.2 ? 'good' : 'fair' // 80%好质量
            });
        }
        
        return inputData;
    }

    // 获取计算结果
    getCalculationResults(record) {
        // 模拟计算结果数据，实际应该从计算引擎获取
        const resultData = [];
        const now = Date.now();
        const algorithms = ['标准算法', '优化算法', '机器学习', '深度学习'];
        
        for (let i = 0; i < 8; i++) {
            const timestamp = now - (8 - i) * 60000; // 最近8个结果
            const algorithm = algorithms[Math.floor(Math.random() * algorithms.length)];
            const baseValue = 100 + Math.random() * 20 - 10;
            
            resultData.push({
                id: `RESULT-${String(i + 1).padStart(3, '0')}`,
                timestamp: timestamp,
                calculatedValue: baseValue * (1 + (Math.random() - 0.5) * 0.1), // ±5%计算误差
                algorithm: algorithm,
                precision: 0.95 + Math.random() * 0.04, // 95%-99%精度
                processingTime: Math.floor(10 + Math.random() * 50) // 10-60ms处理时间
            });
        }
        
        return resultData;
    }

    // 获取质量状态文本
    getQualityStatus(quality) {
        const statusMap = {
            'excellent': '优秀',
            'good': '良好',
            'fair': '一般',
            'poor': '较差'
        };
        return statusMap[quality] || '未知';
    }

    // 计算真实数据的统计信息
    calculateRealDataStatistics(chartData) {
        const statistics = {
            inputPaths: 0,
            outputPaths: 0,
            inputCount: 0,
            resultCount: 0,
            inputMean: 0,
            resultMean: 0,
            inputStdDev: 0,
            resultStdDev: 0,
            accuracy: 'N/A',
            efficiency: 'N/A'
        };

        if (chartData && chartData.inputData) {
            statistics.inputPaths = Object.keys(chartData.inputData).length;
            
            // 计算输入数据统计
            const allInputValues = [];
            Object.values(chartData.inputData).forEach(dataArray => {
                dataArray.forEach(point => {
                    if (point.value !== null && point.value !== undefined) {
                        allInputValues.push(point.value);
                    }
                });
            });
            
            statistics.inputCount = allInputValues.length;
            if (allInputValues.length > 0) {
                const inputStats = this.calculateStatistics(allInputValues);
                statistics.inputMean = inputStats.mean;
                statistics.inputStdDev = inputStats.stdDev;
            }
        }

        if (chartData && chartData.outputData) {
            statistics.outputPaths = Object.keys(chartData.outputData).length;
            
            // 计算输出数据统计
            const allOutputValues = [];
            Object.values(chartData.outputData).forEach(dataArray => {
                dataArray.forEach(point => {
                    if (point.value !== null && point.value !== undefined) {
                        allOutputValues.push(point.value);
                    }
                });
            });
            
            statistics.resultCount = allOutputValues.length;
            if (allOutputValues.length > 0) {
                const outputStats = this.calculateStatistics(allOutputValues);
                statistics.resultMean = outputStats.mean;
                statistics.resultStdDev = outputStats.stdDev;
            }
        }

        return statistics;
    }

    // 计算基本统计信息
    calculateStatistics(values) {
        if (values.length === 0) {
            return { mean: 0, stdDev: 0 };
        }

        const mean = values.reduce((sum, val) => sum + val, 0) / values.length;
        const variance = values.reduce((sum, val) => sum + Math.pow(val - mean, 2), 0) / values.length;
        const stdDev = Math.sqrt(variance);

        return { mean, stdDev };
    }

    // 计算变化率
    calculateChangeRate(currentItem, previousItem = null) {
        if (!currentItem.value) return 'N/A';
        
        if (!previousItem) {
            // 查找前一个任务
            const currentIndex = this.displayData.findIndex(item => item.id === currentItem.id);
            if (currentIndex > 0) {
                previousItem = this.displayData[currentIndex - 1];
            }
        }
        
        if (!previousItem || !previousItem.value) return 'N/A';
        
        const changeRate = ((currentItem.value - previousItem.value) / previousItem.value * 100);
        return `${changeRate >= 0 ? '+' : ''}${changeRate.toFixed(2)}%`;
    }

    // 计算数据统计
    calculateDataStatistics(data) {
        const inputData = this.getInputData({ id: 'current' });
        const resultData = this.getCalculationResults({ id: 'current' });
        
        // 计算输入数据统计
        const inputStats = this.calculateBasicStatistics(inputData.map(item => item.rawValue));
        
        // 计算结果数据统计
        const resultStats = this.calculateBasicStatistics(resultData.map(item => item.calculatedValue));
        
        // 计算准确率
        let accuracy = 'N/A';
        if (inputData.length > 0 && resultData.length > 0) {
            const inputValues = inputData.map(item => item.rawValue);
            const resultValues = resultData.map(item => item.calculatedValue);
            const minLength = Math.min(inputValues.length, resultValues.length);
            
            let totalError = 0;
            for (let i = 0; i < minLength; i++) {
                if (inputValues[i] !== null && resultValues[i] !== null) {
                    const error = Math.abs(inputValues[i] - resultValues[i]) / inputValues[i];
                    totalError += error;
                }
            }
            
            if (minLength > 0) {
                accuracy = ((1 - totalError / minLength) * 100).toFixed(2) + '%';
            }
        }
        
        // 计算效率
        let efficiency = 'N/A';
        if (resultData.length > 0) {
            const avgProcessingTime = resultData.reduce((sum, item) => sum + item.processingTime, 0) / resultData.length;
            efficiency = (1000 / avgProcessingTime).toFixed(2) + ' ops/s';
        }
        
        return {
            inputCount: inputStats.count,
            resultCount: resultStats.count,
            inputMean: inputStats.mean,
            resultMean: resultStats.mean,
            inputStdDev: inputStats.stdDev,
            resultStdDev: resultStats.stdDev,
            accuracy: accuracy,
            efficiency: efficiency,
            trend: this.calculateTrend(data)
        };
    }
    
    // 计算基础统计信息
    calculateBasicStatistics(values) {
        const validValues = values.filter(val => val !== undefined && val !== null);
        
        if (validValues.length === 0) {
            return {
                count: 0,
                mean: 'N/A',
                stdDev: 'N/A'
            };
        }
        
        const count = validValues.length;
        const sum = validValues.reduce((acc, val) => acc + val, 0);
        const mean = sum / count;
        
        // 计算标准差
        const squaredDiffs = validValues.map(val => Math.pow(val - mean, 2));
        const avgSquaredDiff = squaredDiffs.reduce((acc, val) => acc + val, 0) / count;
        const stdDev = Math.sqrt(avgSquaredDiff);
        
        return {
            count,
            mean: mean.toFixed(2),
            stdDev: stdDev.toFixed(2)
        };
    }
    
    // 计算趋势
    calculateTrend(data) {
        if (!data || data.length < 2) return '数据不足';
        
        const values = data.filter(item => item.value !== undefined && item.value !== null)
                          .map(item => item.value);
        
        if (values.length < 2) return '数据不足';
        
        const firstHalf = values.slice(0, Math.floor(values.length / 2));
        const secondHalf = values.slice(Math.floor(values.length / 2));
        
        const firstMean = firstHalf.reduce((acc, val) => acc + val, 0) / firstHalf.length;
        const secondMean = secondHalf.reduce((acc, val) => acc + val, 0) / secondHalf.length;
        
        const change = (secondMean - firstMean) / firstMean * 100;
        
        if (change > 5) {
            return '上升';
        } else if (change < -5) {
            return '下降';
        } else {
            return '稳定';
        }
    }

    // 生成数据结论
    generateDataConclusions(record, statistics) {
        const conclusions = [];
        
        // 基于状态的结论
        if (record.status === 'success') {
            conclusions.push('任务状态正常，运行良好');
        } else if (record.status === 'failed') {
            conclusions.push('任务状态异常，需要关注');
        } else if (record.status === 'running') {
            conclusions.push('任务正在运行中，状态正常');
        } else {
            conclusions.push('任务状态待确认');
        }
        
        // 基于数值的结论
        if (record.value !== undefined && record.value !== null) {
            if (statistics.mean !== 'N/A') {
                const deviation = Math.abs(record.value - parseFloat(statistics.mean));
                const stdDev = parseFloat(statistics.stdDev);
                
                if (deviation > 2 * stdDev) {
                    conclusions.push('当前数值偏离平均值较大，可能存在异常');
                } else if (deviation > stdDev) {
                    conclusions.push('当前数值略有偏离，但在正常范围内');
                } else {
                    conclusions.push('当前数值处于正常波动范围');
                }
            }
        }
        
        // 基于趋势的结论
        if (statistics.trend === '上升') {
            conclusions.push('数据呈现上升趋势，建议持续关注');
        } else if (statistics.trend === '下降') {
            conclusions.push('数据呈现下降趋势，建议分析原因');
        } else {
            conclusions.push('数据趋势相对稳定');
        }
        
        // 基于数据质量的结论
        if (statistics.count > 0) {
            conclusions.push(`数据完整性良好，共分析${statistics.count}个任务`);
        }
        
        return conclusions;
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
    async handleCompareSelected() {
        const selectedCheckboxes = this.shadowRoot.querySelectorAll('.checkbox-item:checked');
        console.log('选中的复选框数量:', selectedCheckboxes.length);
        console.log('所有数据:', this.allData);
        
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
        console.log('选中的任务ID:', selectedIds);
        this.showToast(`正在对比 ${selectedIds.length} 个选中的任务`, 'success');
        
        // 显示对比图表
        await this.showComparisonChart(selectedIds);
    }

    // 显示对比图表
    async showComparisonChart(selectedIds) {
        // 将字符串ID转换为数字，确保类型匹配
        const numericSelectedIds = selectedIds.map(id => parseInt(id, 10));
        console.log('转换后的数字ID:', numericSelectedIds);
        
        // 筛选选中的任务数据
        const selectedTasks = this.allData.filter(record => numericSelectedIds.includes(record.id));
        console.log('筛选出的任务:', selectedTasks);
        
        if (selectedTasks.length === 0) {
            this.showToast('没有找到选中的任务数据', 'error');
            return;
        }
        
        try {
            // 为每个任务查询真实数据
            const tasksData = [];
            for (const task of selectedTasks) {
                const queryData = await this.queryDataForAnalysis(task);
                if (queryData) {
                    tasksData.push({
                        id: task.id,
                        name: task.name,
                        inputData: queryData.inputData,
                        outputData: queryData.outputData
                    });
                }
            }
            
            if (tasksData.length === 0) {
                this.showToast('没有获取到任何任务的数据', 'warning');
                return;
            }
            
            console.log('获取到的真实数据:', tasksData);
            
            // 生成对比图表数据
            const comparisonData = this.generateComparisonDataFromRealData(tasksData);
            console.log('生成的对比数据:', comparisonData);
            
            this.currentChartData = {
                type: 'comparison',
                data: comparisonData,
                selectedIds: selectedIds
            };
            
            // 确保图表初始化完成后再更新数据
            if (!this.chart) {
                console.log('图表未初始化，开始初始化...');
                this.initChart();
                // 等待图表初始化完成
                setTimeout(() => {
                    console.log('图表初始化完成，更新对比图表...');
                    this.updateComparisonChart(comparisonData);
                }, 200);
            } else {
                console.log('图表已初始化，直接更新对比图表...');
                this.updateComparisonChart(comparisonData);
            }
            
        } catch (error) {
            console.error('对比数据查询失败:', error);
            this.showToast('获取对比数据失败，请重试', 'error');
        }
    }

    // 从真实数据生成对比数据
    generateComparisonDataFromRealData(tasksData) {
        const comparisonData = {
            tasks: [],
            timePoints: [],
            frequencyInconsistent: false,
            targetFrequency: 10 // 默认目标频率：每10秒一个点
        };

        // 为每个任务处理真实数据
        tasksData.forEach((taskData, index) => {
            const task = {
                id: taskData.id,
                name: taskData.name,
                samplingInterval: 10, // 默认采样间隔
                inputData: [],
                calculationResult: []
            };

            // 处理输入数据
            if (taskData.inputData) {
                Object.keys(taskData.inputData).forEach(path => {
                    taskData.inputData[path].forEach(point => {
                        task.inputData.push([point.timestamp, point.value]);
                    });
                });
            }

            // 处理输出数据
            if (taskData.outputData) {
                Object.keys(taskData.outputData).forEach(path => {
                    taskData.outputData[path].forEach(point => {
                        task.calculationResult.push([point.timestamp, point.value]);
                    });
                });
            }

            comparisonData.tasks.push(task);
        });

        // 生成统一的时间点用于X轴
        const allTimePoints = new Set();
        comparisonData.tasks.forEach(task => {
            task.inputData.forEach(point => allTimePoints.add(point[0]));
            task.calculationResult.forEach(point => allTimePoints.add(point[0]));
        });
        
        comparisonData.timePoints = Array.from(allTimePoints).sort((a, b) => a - b);

        return comparisonData;
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

            // 根据采样间隔生成任务
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
            // 找到时间点前后的任务
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
            // 找到最接近目标时间的任务
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
                        result += `${param.seriesName}: ${(param.value[1] || 0).toFixed(2)}<br/>`;
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
        if (window.CommonUtils && window.CommonUtils.showToast) {
            window.CommonUtils.showToast(message, type);
        } else {
            console.warn('CommonUtils.showToast not available, falling back to console.log');
            console[type === 'error' ? 'error' : type === 'warning' ? 'warn' : 'log'](`[${type}] ${message}`);
        }
    }

    async loadTasksFromAPI() {
        try {
            // 获取筛选条件
            const nameFilter = this.shadowRoot.getElementById('nameSearch')?.value.trim();
            const statusFilter = this.shadowRoot.getElementById('statusFilter')?.value;
            const startTime = this.shadowRoot.getElementById('startTime')?.value;
            const endTime = this.shadowRoot.getElementById('endTime')?.value;

            // 构建请求对象
            const requestBody = {
                pageNum: this.currentPage || 1,
                pageSize: this.pageSize || 10,
                name: nameFilter || null,
                status: statusFilter || null,
                startTime: startTime ? new Date(startTime).getTime() : null,
                endTime: endTime ? new Date(endTime).getTime() : null
            };

            // 调用查询接口
            const result = await window.AppConfig.post('task', 'query', requestBody);

            if (result.success && result.data) {
                // 转换为前端所需格式
                this.displayData = result.data.map(task => ({
                    id: task.timestamp,
                    name: task.name,
                    status: task.status,
                    timestamp: task.timestamp,
                    startTime: task.startTime,
                    endTime: task.endTime,
                    ruleId: task.ruleId,
                    inputMeasurements: task.inputMeasurements,
                    outputMeasurements: task.outputMeasurements,
                    time: new Date(task.timestamp).toLocaleString('zh-CN')
                }));
                
                // 设置数据
                this.allData = this.displayData;

                // 获取总数用于分页
                if (this.currentPage === 1) {
                    await this.loadTasksCount(nameFilter, statusFilter, startTime, endTime);
                }

                this.updateTable();
            } else {
                // API失败时使用模拟数据
                const mockData = this.generateMultiTaskData();
                this.allData = mockData;
                this.displayData = mockData;
                this.updateTable();
            }
        } catch (error) {
            // 网络错误时使用模拟数据
            const mockData = this.generateMultiTaskData();
            this.allData = mockData;
            this.displayData = mockData;
            this.updateTable();
        }
    }

    async loadTasksCount(name, status, startTime, endTime) {
        try {
            const requestBody = {
                name: name || null,
                status: status || null,
                startTime: startTime ? new Date(startTime).getTime() : null,
                endTime: endTime ? new Date(endTime).getTime() : null
            };

            const result = await window.AppConfig.post('task', 'count', requestBody);

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
    
    // 添加图表图片（通过ECharts base64）
    async addChartImage(chartBase64, title, description) {
        try {
            this.addText(title, 12, true);
            this.addText(description, 10);
            
            // 创建图片元素
            const img = new Image();
            img.src = chartBase64;
            
            // 等待图片加载
            await new Promise((resolve, reject) => {
                img.onload = resolve;
                img.onerror = reject;
            });
            
            // 添加到内容数组
            this.content.push({
                type: 'image',
                imageData: chartBase64,
                title: title,
                description: description,
                width: img.width,
                height: img.height
            });
            
            this.addText(' ', 8); // 添加间距
            
        } catch (error) {
            console.error('添加图表图片失败:', error);
            // 如果添加失败，使用占位符
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
        // 生成HTML内容
        const htmlContent = this.generateHTML();
        
        // 创建新窗口
        const printWindow = window.open('', '_blank');
        printWindow.document.write(htmlContent);
        printWindow.document.close();
        
        // 等待内容加载完成后触发打印
        printWindow.onload = () => {
            // 显示提示信息
            alert('请在打印对话框中选择"保存为PDF"来下载报告');
            
            // 触发打印对话框，用户可以选择"保存为PDF"
            printWindow.print();
            
            // 打印完成后关闭窗口
            printWindow.onafterprint = () => {
                printWindow.close();
            };
            
            // 备用关闭方案（如果用户取消打印）
            setTimeout(() => {
                if (!printWindow.closed) {
                    printWindow.close();
                }
            }, 1000);
        };
    }
    
    // 生成PDF Blob（用于预览和下载）
    generatePDFBlob() {
        const htmlContent = this.generateHTML();
        
        // 创建一个隐藏的iframe来生成PDF
        const iframe = document.createElement('iframe');
        iframe.style.display = 'none';
        document.body.appendChild(iframe);
        
        const iframeDoc = iframe.contentDocument;
        iframeDoc.open();
        iframeDoc.write(htmlContent);
        iframeDoc.close();
        
        // 等待内容加载完成
        return new Promise((resolve) => {
            iframe.onload = () => {
                // 使用浏览器的打印功能生成PDF
                // 注意：这里我们创建一个包含HTML内容的Blob
                // 实际的PDF转换需要服务器端支持或使用专门的库
                const htmlBlob = new Blob([htmlContent], { type: 'text/html;charset=utf-8' });
                
                // 清理iframe
                document.body.removeChild(iframe);
                
                // 返回HTML Blob，浏览器会将其识别为可打印的内容
                resolve(htmlBlob);
            };
        });
    }
}

// 将 initPagination 和 updatePagination 方法添加回 VisualAnalysis 类
// 注意：这些方法原本应该在 VisualAnalysis 类中

// 临时解决方案：直接修改原型
VisualAnalysis.prototype.initPagination = function() {
        const pagination = this.shadowRoot.getElementById('pagination');
        if (pagination) {
            // 监听分页变化事件
            pagination.addEventListener('pagination-change', (event) => {
                const { currentPage, pageSize } = event.detail;
                this.currentPage = currentPage;
                this.pageSize = pageSize;
                this.updateTable();
            });
            
            // 初始化分页
            this.updatePagination();
        }
    };

VisualAnalysis.prototype.updatePagination = function() {
        const pagination = this.shadowRoot.getElementById('pagination');
        if (pagination) {
            pagination.setPagination(this.currentPage, this.pageSize, this.displayData.length);
        }
    };

// 注册组件
if (!customElements.get('visual-analysis')) {
    customElements.define('visual-analysis', VisualAnalysis);
}
