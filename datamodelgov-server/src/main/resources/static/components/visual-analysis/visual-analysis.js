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
            
            // 规则名称列
            const ruleNameTd = document.createElement('td');
            ruleNameTd.textContent = record.ruleName || '-';
            tr.appendChild(ruleNameTd);
            
            // 模型名称列
            const modelNameTd = document.createElement('td');
            modelNameTd.textContent = record.modelName || '-';
            tr.appendChild(modelNameTd);
            
            // 版本号列
            const modelVersionTd = document.createElement('td');
            modelVersionTd.textContent = record.modelVersion || '-';
            tr.appendChild(modelVersionTd);
            
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
            
            // 操作列
            const actionTd = document.createElement('td');
            const actionButtons = document.createElement('div');
            actionButtons.className = 'action-buttons';
            
            // 分析按钮（仅成功状态显示）
            if (record.status === 'success') {
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
            
            // 停止按钮（运行中和等待中状态显示）
            if (record.status === 'running' || record.status === 'pending') {
                const stopBtn = document.createElement('button');
                stopBtn.className = 'action-btn stop';
                stopBtn.textContent = record.status === 'pending' ? '取消' : '停止';
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
            pdfGenerator.addText(`规则名称: ${record.ruleName || 'N/A'}`, 12);
            pdfGenerator.addText(`开始时间: ${record.startTime ? new Date(record.startTime).toLocaleString() : 'N/A'}`, 12);
            pdfGenerator.addText(`结束时间: ${record.endTime ? new Date(record.endTime).toLocaleString() : 'N/A'}`, 12);
            
            // 3. 模型信息部分
            pdfGenerator.addSubtitle('二、模型信息');
            pdfGenerator.addText(`模型名称: ${record.modelName || 'N/A'}`, 12);
            pdfGenerator.addText(`版本号: ${record.modelVersion || 'N/A'}`, 12);
            
            // 4. 添加当前曲线图
            pdfGenerator.addSubtitle('三、曲线图分析');
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
            
            // 5. 数据视图
            pdfGenerator.addSubtitle('四、数据视图');
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
            
            // 6. 统计分析
            pdfGenerator.addSubtitle('五、统计分析');
            if (this.currentChartData && this.currentChartData.data) {
                const statistics = this.calculateRealDataStatistics(this.currentChartData.data);
                const statsHeaders = ['统计指标', '数值', '说明'];
                const statsData = [
                    ['输入测点数量', statistics.inputPaths, '输入测点路径数量'],
                    ['输出测点数量', statistics.outputPaths, '输出测点路径数量'],
                    ['输入数据点数量', statistics.inputCount, '输入数据有效数据点个数'],
                    ['输出数据点数量', statistics.resultCount, '输出数据有效数据点个数'],
                    ['输入数据平均值', statistics.inputMean.toFixed(2), '所有输入数据的平均值'],
                    ['输出数据平均值', statistics.resultMean.toFixed(2), '所有输出数据的平均值'],
                    ['输入数据标准差', statistics.inputStdDev.toFixed(2), '输入数据的标准差'],
                    ['输出数据标准差', statistics.resultStdDev.toFixed(2), '输出数据的标准差']
                ];
                pdfGenerator.addTable(statsHeaders, statsData);
            } else {
                pdfGenerator.addText('暂无统计数据', 12);
            }
            
            // 生成HTML内容
            const htmlContent = pdfGenerator.generateHTML();
            
            // 上传HTML报告到任务目录（后端可以将其转换为PDF）
            try {
                const formData = new FormData();
                // 使用固定文件名，覆盖之前的报告
                const reportFileName = `任务分析报告.html`;
                formData.append('file', new Blob([htmlContent], { type: 'text/html;charset=utf-8' }), reportFileName);
                formData.append('timestamp', record.timestamp);

                const uploadResult = await window.AppConfig.upload('task', 'upload-report', formData);
                
                if (uploadResult.success) {
                    this.showToast('报告已上传到任务目录！', 'success');
                } else {
                    throw new Error(uploadResult.message || '上传失败');
                }
            } catch (uploadError) {
                console.warn('报告上传失败:', uploadError);
                this.showToast('报告上传失败：' + uploadError.message, 'error');
            }
            
            // 使用浏览器的打印功能生成PDF供用户下载
            const printWindow = window.open('', '_blank');
            printWindow.document.write(htmlContent);
            printWindow.document.close();
            
            // 等待内容加载完成后触发打印
            printWindow.onload = () => {
                // 触发打印对话框，用户可以选择"保存为PDF"
                printWindow.print();
                
                // 打印完成后关闭窗口
                printWindow.onafterprint = () => {
                    printWindow.close();
                };
                
                // 备用关闭方案
                setTimeout(() => {
                    if (!printWindow.closed) {
                        printWindow.close();
                    }
                }, 1000);
            };
            
            this.showToast('PDF报告生成成功！请在打印对话框中选择"保存为PDF"', 'success');
            
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
    async handleExport(record) {
        this.showToast(`正在导出任务数据: ${record.name}`, 'info');
        console.log('导出任务:', record);

        try {
            // 1. 先执行分析获取数据
            await this.handleAnalyze(record);
            
            // 等待分析完成
            await new Promise(resolve => setTimeout(resolve, 1000));

            // 2. 生成报告HTML内容
            const htmlContent = await this.generateReportHTML(record);
            
            // 3. 上传报告到任务目录
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
            // 使用固定文件名，覆盖之前的报告
            const reportFileName = `任务分析报告.html`;
            formData.append('file', new Blob([htmlContent], { type: 'text/html;charset=utf-8' }), reportFileName);
            formData.append('timestamp', record.timestamp);

            const uploadResult = await window.AppConfig.upload('task', 'upload-report', formData);
            
            if (!uploadResult.success) {
                this.showToast('上传报告失败：' + uploadResult.message, 'error');
            } else {
                this.showToast('报告上传成功！', 'success');
            }

            return uploadResult.data;
            
        } catch (error) {
            console.error('上传报告失败:', error);
            this.showToast('上传报告失败：' + error.message, 'error');
            throw error;
        }
    }

    // 生成报告HTML内容
    async generateReportHTML(record) {
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
            <div style="font-size: 16px;">正在生成报告内容，请稍候...</div>
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
            pdfGenerator.addText(`规则名称: ${record.ruleName || 'N/A'}`, 12);
            pdfGenerator.addText(`当前状态: ${this.getStatusText(record.status)}`, 12);
            pdfGenerator.addText(`开始时间: ${record.startTime ? new Date(record.startTime).toLocaleString() : 'N/A'}`, 12);
            pdfGenerator.addText(`结束时间: ${record.endTime ? new Date(record.endTime).toLocaleString() : 'N/A'}`, 12);
            
            // 3. 模型信息部分
            pdfGenerator.addSubtitle('二、模型信息');
            pdfGenerator.addText(`模型名称: ${record.modelName || 'N/A'}`, 12);
            pdfGenerator.addText(`版本号: ${record.modelVersion || 'N/A'}`, 12);
            
            // 4. 添加当前曲线图
            pdfGenerator.addSubtitle('三、曲线图分析');
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
            
            // 5. 数据视图
            pdfGenerator.addSubtitle('四、数据视图');
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
            
            // 6. 统计分析
            pdfGenerator.addSubtitle('五、统计分析');
            if (this.currentChartData && this.currentChartData.data) {
                const statistics = this.calculateRealDataStatistics(this.currentChartData.data);
                const statsHeaders = ['统计指标', '数值', '说明'];
                const statsData = [
                    ['输入测点数量', statistics.inputPaths, '输入测点路径数量'],
                    ['输出测点数量', statistics.outputPaths, '输出测点路径数量'],
                    ['输入数据点数量', statistics.inputCount, '输入数据有效数据点个数'],
                    ['输出数据点数量', statistics.resultCount, '输出数据有效数据点个数'],
                    ['输入数据平均值', statistics.inputMean.toFixed(2), '所有输入数据的平均值'],
                    ['输出数据平均值', statistics.resultMean.toFixed(2), '所有输出数据的平均值'],
                    ['输入数据标准差', statistics.inputStdDev.toFixed(2), '输入数据的标准差'],
                    ['输出数据标准差', statistics.resultStdDev.toFixed(2), '输出数据的标准差']
                ];
                pdfGenerator.addTable(statsHeaders, statsData);
            } else {
                pdfGenerator.addText('暂无统计数据', 12);
            }

            // 生成HTML内容
            const htmlContent = pdfGenerator.generateHTML();
            
            this.showToast('报告内容生成成功！', 'success');
            return htmlContent;
            
        } finally {
            // 移除加载提示
            if (loadingOverlay.parentNode) {
                loadingOverlay.remove();
            }
        }
    }

    // 生成PDF下载
    generatePDFDownload(record, htmlContent) {
        // 创建新窗口用于打印
        const printWindow = window.open('', '_blank');
        printWindow.document.write(htmlContent);
        printWindow.document.close();
        
        // 等待内容加载完成后触发打印
        printWindow.onload = () => {
            // 触发打印对话框，用户可以选择"保存为PDF"
            printWindow.print();
            
            // 打印完成后关闭窗口
            printWindow.onafterprint = () => {
                printWindow.close();
            };
            
            // 备用关闭方案
            setTimeout(() => {
                if (!printWindow.closed) {
                    printWindow.close();
                }
            }, 1000);
        };
    }

    // 打包并下载任务文件
    async packageAndDownloadTask(record) {
        try {
            this.showToast('正在打包任务文件...', 'info');

            // 构建URL，使用POST方法但参数通过URL传递
            const url = `/api/task/package-download?timestamp=${record.timestamp}`;
            
            // 获取token并构建认证头
            const token = localStorage.getItem('jwtToken');
            const headers = {
                'Authorization': token ? `Bearer ${token}` : ''
            };
            
            // 使用fetch发送请求
            const response = await fetch(url, {
                method: 'POST',
                headers: headers
            });

            if (!response.ok) {
                if (response.status === 401) {
                    throw new Error('认证失败，请重新登录');
                } else if (response.status === 403) {
                    throw new Error('权限不足');
                } else {
                    throw new Error(`HTTP ${response.status}: ${response.statusText}`);
                }
            }

            // 获取文件名
            const contentDisposition = response.headers.get('Content-Disposition');
            let fileName = `任务导出包_${record.name}_${new Date().getTime()}.zip`;
            if (contentDisposition) {
                const filenameMatch = contentDisposition.match(/filename="?([^"]+)"?/);
                if (filenameMatch) {
                    fileName = filenameMatch[1];
                }
            }

            // 创建下载链接
            const blob = await response.blob();
            const downloadUrl = window.URL.createObjectURL(blob);
            const downloadLink = document.createElement('a');
            downloadLink.href = downloadUrl;
            downloadLink.download = fileName;
            document.body.appendChild(downloadLink);
            downloadLink.click();
            document.body.removeChild(downloadLink);
            window.URL.revokeObjectURL(downloadUrl);
            
            this.showToast('任务导出包下载成功！', 'success');
            
        } catch (error) {
            console.error('打包下载失败:', error);
            this.showToast('打包下载失败：' + error.message, 'error');
            throw error;
        }
    }

    // 处理查看日志操作
    async handleViewLog(record) {
        try {
            console.log('开始查看日志，任务信息:', record);
            this.showToast(`正在获取任务日志: ${record.name}`, 'info');
            
            // 检查timestamp是否存在
            if (!record.timestamp) {
                console.error('任务缺少timestamp字段:', record);
                this.showToast('任务信息不完整，无法获取日志', 'error');
                return;
            }
            
            // 调用后端详情接口获取任务信息（包含日志）
            const result = await window.AppConfig.get('task', 'detail', {
                timestamp: record.timestamp
            });
            
            console.log('获取任务详情响应:', result);
            
            if (result.success && result.data) {
                // 从任务详情中获取日志信息
                const logContent = result.data.processLog || '暂无日志信息';
                
                // 显示日志弹窗
                this.showLogModal(record.name, logContent, record);
            } else {
                console.error('获取任务详情失败:', result);
                this.showToast(result.message || '获取任务详情失败', 'error');
            }
        } catch (error) {
            console.error('获取任务详情失败:', error);
            this.showToast('网络错误，获取任务详情失败', 'error');
        }
    }
    
    // 显示日志弹窗
    showLogModal(taskName, logContent, record) {
        console.log('显示日志弹窗，参数:', { taskName, logContentLength: logContent?.length, record });
        
        const modal = this.shadowRoot.getElementById('modalMask');
        const title = this.shadowRoot.getElementById('modalTitle');
        const modalBody = this.shadowRoot.getElementById('modalBody');
        const modalFooter = this.shadowRoot.getElementById('modalFooter');
        
        console.log('弹窗元素检查:', { modal: !!modal, title: !!title, modalBody: !!modalBody, modalFooter: !!modalFooter });
        
        if (modal && title && modalBody && modalFooter) {
            title.textContent = `任务日志 - ${taskName}`;
            
            // 根据任务状态决定是否显示自动刷新控制
            const isRunning = record.status === 'running';
            
            // 创建日志显示区域
            modalBody.innerHTML = `
                <div class="log-container">
                    <div class="log-header">
                        <h3>实时日志</h3>
                        <div class="log-controls">
                            <button class="btn btn-refresh" id="refreshLogBtn">刷新</button>
                            ${isRunning ? `
                                <button class="btn btn-auto-refresh active" id="autoRefreshBtn">自动刷新: 开启</button>
                                <span class="status-indicator running">任务运行中</span>
                            ` : `
                                <span class="status-indicator ${record.status}">任务${this.getStatusText(record.status)}</span>
                            `}
                        </div>
                    </div>
                    <div class="log-content" id="logContent">
                        <pre>${logContent}</pre>
                    </div>
                </div>
            `;
            
            // 设置弹窗按钮
            modalFooter.innerHTML = `
                <button type="button" class="btn btn-cancel" id="closeLogBtn">关闭</button>
            `;
            
            // 存储当前任务信息用于刷新
            this.currentLogTask = {
                name: taskName,
                timestamp: record.timestamp,
                status: record.status
            };
            
            console.log('设置currentLogTask:', this.currentLogTask);
            
            // 绑定事件
            this.bindLogModalEvents();
            
            // 如果任务正在运行，自动开启自动刷新
            if (isRunning) {
                this.startLogAutoRefresh();
            }
            
            this.showModal();
            
            console.log('日志弹窗显示完成');
        } else {
            console.error('弹窗元素缺失');
            this.showToast('弹窗元素缺失，无法显示日志', 'error');
        }
    }
    
    // 绑定日志弹窗事件
    bindLogModalEvents() {
        // 关闭按钮
        this.shadowRoot.getElementById('closeLogBtn')?.addEventListener('click', () => {
            this.hideModal();
            this.stopLogAutoRefresh();
        });
        
        // 弹窗右上角关闭按钮
        this.shadowRoot.getElementById('modalClose')?.addEventListener('click', () => {
            this.hideModal();
            this.stopLogAutoRefresh();
        });
        
        // 移除点击遮罩关闭功能，避免误操作
        // this.shadowRoot.getElementById('modalMask')?.addEventListener('click', (e) => {
        //     if (e.target.id === 'modalMask') {
        //         this.hideModal();
        //         this.stopLogAutoRefresh();
        //     }
        // });
        
        // 刷新按钮
        this.shadowRoot.getElementById('refreshLogBtn')?.addEventListener('click', () => {
            this.refreshLog();
        });
        
        // 自动刷新按钮
        this.shadowRoot.getElementById('autoRefreshBtn')?.addEventListener('click', () => {
            this.toggleLogAutoRefresh();
        });
    }
    
    // 刷新日志
    async refreshLog() {
        if (!this.currentLogTask) return;
        
        try {
            // 调用详情接口获取最新任务信息（包含日志）
            const result = await window.AppConfig.get('task', 'detail', {
                timestamp: this.currentLogTask.timestamp
            });
            
            if (result.success && result.data) {
                // 从任务详情中获取日志信息
                const logContent = this.shadowRoot.getElementById('logContent');
                if (logContent) {
                    const content = result.data.processLog || '暂无日志信息';
                    logContent.innerHTML = `<pre>${content}</pre>`;
                    // 滚动到底部
                    logContent.scrollTop = logContent.scrollHeight;
                }
                
                // 检查任务状态是否变化，如果任务结束则停止自动刷新
                if (this.logRefreshInterval) {
                    await this.checkTaskStatus();
                }
            }
        } catch (error) {
            console.error('刷新日志失败:', error);
        }
    }
    
    // 检查任务状态
    async checkTaskStatus() {
        if (!this.currentLogTask) return;
        
        try {
            // 获取最新的任务信息 - 使用GET方法
            const result = await window.AppConfig.get('task', 'detail', {
                timestamp: this.currentLogTask.timestamp
            });
            
            if (result.success && result.data) {
                const newStatus = result.data.status;
                const oldStatus = this.currentLogTask.status;
                
                // 如果状态从运行中变为其他状态，停止自动刷新
                if (oldStatus === 'running' && newStatus !== 'running') {
                    console.log(`任务状态从 ${oldStatus} 变为 ${newStatus}，停止自动刷新`);
                    this.stopLogAutoRefresh();
                    
                    // 更新状态显示
                    this.updateStatusDisplay(newStatus);
                    
                    // 显示完成提示
                    const statusText = this.getStatusText(newStatus);
                    this.showToast(`任务${statusText}`, newStatus === 'success' ? 'success' : 'warning');
                }
                
                // 更新当前任务状态
                this.currentLogTask.status = newStatus;
            }
        } catch (error) {
            console.error('检查任务状态失败:', error);
        }
    }
    
    // 更新状态显示
    updateStatusDisplay(status) {
        const statusIndicator = this.shadowRoot.querySelector('.status-indicator');
        const autoRefreshBtn = this.shadowRoot.getElementById('autoRefreshBtn');
        
        if (statusIndicator) {
            statusIndicator.className = `status-indicator ${status}`;
            statusIndicator.textContent = `任务${this.getStatusText(status)}`;
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
        }, 5000); // 每5秒刷新一次
    }
    
    // 停止自动刷新
    stopLogAutoRefresh() {
        if (this.logRefreshInterval) {
            clearInterval(this.logRefreshInterval);
            this.logRefreshInterval = null;
        }
    }
    
    // 隐藏弹窗
    hideModal() {
        const modal = this.shadowRoot.getElementById('modalMask');
        if (modal) {
            modal.hidden = true;
            modal.style.display = 'none';
        }
        // 清理状态
        this.currentLogTask = null;
        this.stopLogAutoRefresh();
    }
    
    // 显示弹窗
    showModal() {
        const modal = this.shadowRoot.getElementById('modalMask');
        if (modal) {
            modal.hidden = false;
            modal.style.display = 'flex';
        }
    }

    // 处理停止操作
    async handleStop(record) {
        try {
            this.showToast(`正在停止任务: ${record.name}`, 'warning');
            
            // 调用后端停止接口（使用GET方法传递参数）
            const result = await window.AppConfig.get('task', 'stop', {
                timestamp: record.timestamp
            });
            
            console.log('停止任务响应:', result);
            
            if (result.success) {
                this.showToast(`任务 ${record.name} 停止成功`, 'success');
                // 更新本地状态
                record.status = 'stopped';
                this.updateTable();
            } else {
                this.showToast(result.message || '停止任务失败', 'error');
            }
        } catch (error) {
            console.error('停止任务失败:', error);
            this.showToast('网络错误，停止任务失败', 'error');
        }
    }

    // 处理删除操作
    async handleDelete(record) {
        try {
            // 使用统一的弹窗样式显示确认对话框
            const modalTitle = this.shadowRoot.getElementById('modalTitle');
            const modalBody = this.shadowRoot.getElementById('modalBody');
            const modalFooter = this.shadowRoot.getElementById('modalFooter');
            
            modalTitle.textContent = '删除确认';
            modalBody.innerHTML = `
                <div style="padding: 20px 0;">
                    <p style="margin-bottom: 15px; color: #d32f2f; font-weight: 500;">
                        ⚠️ 确定要删除任务 "${record.name}" 吗？
                    </p>
                    <div style="background: #fef2f2; border: 1px solid #fecaca; border-radius: 6px; padding: 15px; margin-bottom: 15px;">
                        <p style="margin: 0 0 8px 0; font-weight: 500; color: #991b1b;">此操作将删除：</p>
                        <ul style="margin: 0; padding-left: 20px; color: #7f1d1d;">
                            <li>任务数据</li>
                            <li>任务文件目录</li>
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
            
            // 显示弹窗
            this.showModal();
            
            // 绑定事件
            const cancelBtn = this.shadowRoot.getElementById('cancelDelete');
            const confirmBtn = this.shadowRoot.getElementById('confirmDelete');
            const modalClose = this.shadowRoot.getElementById('modalClose');
            
            const closeModal = () => {
                this.hideModal();
            };
            
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
            this.showToast(`正在删除任务: ${record.name}`, 'warning');
            
            // 调用后端删除接口
            const result = await window.AppConfig.delete('task', 'delete', {
                timestamp: record.timestamp
            });
            
            console.log('删除任务响应:', result);
            
            if (result.success) {
                this.showToast(`任务 ${record.name} 删除成功`, 'success');
                
                // 从本地数据中移除
                const index = this.allData.findIndex(item => item.timestamp === record.timestamp);
                if (index > -1) {
                    this.allData.splice(index, 1);
                }
                
                // 重新加载和显示数据
                await this.loadTasksFromAPI();
                this.updateTable();
                
                // 如果当前显示的图表数据被删除，清空图表
                if (this.currentChartData && this.currentChartData.some(item => item.timestamp === record.timestamp)) {
                    this.currentChartData = this.currentChartData.filter(item => item.timestamp !== record.timestamp);
                    this.updateChart();
                }
                
            } else {
                this.showToast(result.message || '删除任务失败', 'error');
            }
        } catch (error) {
            console.error('删除任务失败:', error);
            this.showToast('网络错误，删除任务失败', 'error');
        }
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
        
        // 检查选中的任务状态
        const selectedTasks = this.allData.filter(record => selectedIds.includes(String(record.id)));
        const nonSuccessTasks = selectedTasks.filter(task => task.status !== 'success');
        
        if (nonSuccessTasks.length > 0) {
            const taskNames = nonSuccessTasks.map(task => `${task.name}(${this.getStatusText(task.status)})`).join(', ');
            this.showToast(`只能对比成功状态的任务，以下任务不符合条件：${taskNames}`, 'warning');
            return;
        }
        
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

        // 找到所有任务的最早时间作为基准时间（T=0）
        let baseTime = null;
        const taskFrequencies = []; // 记录每个任务的采样频率
        
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
                    intervals.push((timePoints[i] - timePoints[i-1]) / 1000); // 转换为秒
                }
                // 使用中位数作为采样间隔
                intervals.sort((a, b) => a - b);
                const medianInterval = intervals[Math.floor(intervals.length / 2)];
                taskFrequencies.push(medianInterval);
                
                // 更新全局基准时间
                if (baseTime === null || taskMinTime < baseTime) {
                    baseTime = taskMinTime;
                }
            }
        });

        if (baseTime === null) {
            baseTime = Date.now(); // 如果没有找到时间戳，使用当前时间
        }

        // 检查采样频率是否一致
        if (taskFrequencies.length > 1) {
            const uniqueFrequencies = [...new Set(taskFrequencies.map(f => Math.round(f)))];
            if (uniqueFrequencies.length > 1) {
                comparisonData.frequencyInconsistent = true;
                // 使用最低频率作为目标频率（降采样）
                comparisonData.targetFrequency = Math.max(...taskFrequencies);
                this.showToast('检测到采样频率不一致，系统将自动进行数据对齐处理', 'info');
            } else {
                comparisonData.targetFrequency = taskFrequencies[0];
            }
        }

        // 为每个任务处理真实数据
        tasksData.forEach((taskData, index) => {
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
                            const relativeTime = (point.timestamp - baseTime) / 1000; // 转换为秒，确保T=0对齐
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
                            const relativeTime = (point.timestamp - baseTime) / 1000; // 转换为秒，确保T=0对齐
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

        // 生成统一的相对时间点用于X轴（从0开始）
        const allTimePoints = comparisonData.tasks.flatMap(task => 
            [...task.inputData, ...task.calculationResult]
                .filter(point => point && point[0] !== undefined && point[0] !== null && !isNaN(point[0]))
                .map(point => point[0])
        );
        
        let maxTime = 0;
        if (allTimePoints.length > 0) {
            maxTime = Math.max(...allTimePoints);
        }
        
        // 确保maxTime是有效数值，如果无效则使用默认值
        if (!isFinite(maxTime) || maxTime < 0) {
            maxTime = 100; // 默认最大时间100秒
        }
        
        // 限制最大时间点数量，避免数组过长
        const maxPoints = 1000;
        const stepSize = comparisonData.targetFrequency;
        const estimatedPoints = Math.floor(maxTime / stepSize);
        
        if (estimatedPoints > maxPoints) {
            // 如果预计点数过多，调整步长
            const adjustedStep = Math.ceil(maxTime / maxPoints);
            comparisonData.targetFrequency = adjustedStep;
            this.showToast('数据点过多，已自动调整采样间隔以优化显示', 'info');
        }
        
        // 从0开始生成时间点，步长为目标频率
        for (let time = 0; time <= maxTime; time += comparisonData.targetFrequency) {
            comparisonData.timePoints.push(time);
        }

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

        // 为每个任务生成曲线，按路径分组并区分输入输出
        const pathSeriesMap = {}; // 用于按路径分组系列
        
        comparisonData.tasks.forEach(task => {
            const taskColor = colors[comparisonData.tasks.indexOf(task) % colors.length];
            
            // 处理输入数据曲线（虚线）- 按路径分组
            if (this.curveVisibility.input && task.inputData && task.inputData.length > 0 && task.inputPaths) {
                task.inputPaths.forEach((pathName, pathIndex) => {
                    // 计算每个路径的数据点数量
                    const pointsPerPath = Math.ceil(task.inputData.length / task.inputPaths.length);
                    const startIndex = pathIndex * pointsPerPath;
                    const endIndex = Math.min(startIndex + pointsPerPath, task.inputData.length);
                    const pathData = task.inputData.slice(startIndex, endIndex);
                    
                    if (pathData.length > 0) {
                        const seriesKey = `${pathName}_input_${task.name}`;
                        pathSeriesMap[seriesKey] = {
                            data: pathData,
                            color: taskColor,
                            pathName: pathName,
                            taskName: task.name,
                            type: 'input'
                        };
                    }
                });
            }

            // 处理输出数据曲线（实线）- 按路径分组
            if (this.curveVisibility.output && task.calculationResult && task.calculationResult.length > 0 && task.outputPaths) {
                task.outputPaths.forEach((pathName, pathIndex) => {
                    // 计算每个路径的数据点数量
                    const pointsPerPath = Math.ceil(task.calculationResult.length / task.outputPaths.length);
                    const startIndex = pathIndex * pointsPerPath;
                    const endIndex = Math.min(startIndex + pointsPerPath, task.calculationResult.length);
                    const pathData = task.calculationResult.slice(startIndex, endIndex);
                    
                    if (pathData.length > 0) {
                        const seriesKey = `${pathName}_output_${task.name}`;
                        pathSeriesMap[seriesKey] = {
                            data: pathData,
                            color: taskColor,
                            pathName: pathName,
                            taskName: task.name,
                            type: 'output'
                        };
                    }
                });
            }
        });

        // 生成系列数据
        Object.values(pathSeriesMap).forEach(seriesData => {
            // 验证数据有效性
            const validData = seriesData.data.filter(point => 
                point && 
                Array.isArray(point) && 
                point.length === 2 && 
                isFinite(point[0]) && 
                isFinite(point[1])
            );
            
            if (validData.length > 0) {
                if (seriesData.type === 'input') {
                    // 输入数据曲线（虚线）
                    series.push({
                        name: `${seriesData.pathName} (${seriesData.taskName}输入)`,
                        type: 'line',
                        data: validData,
                        smooth: true,
                        symbol: 'circle',
                        symbolSize: 3,
                        lineStyle: {
                            width: 2,
                            color: seriesData.color,
                            type: 'dashed'
                        },
                        itemStyle: {
                            color: seriesData.color
                        }
                    });
                } else {
                    // 输出数据曲线（实线）
                    series.push({
                        name: `${seriesData.pathName} (${seriesData.taskName}输出)`,
                        type: 'line',
                        data: validData,
                        smooth: true,
                        symbol: 'diamond',
                        symbolSize: 3,
                        lineStyle: {
                            width: 2,
                            color: seriesData.color,
                            type: 'solid'
                        },
                        itemStyle: {
                            color: seriesData.color
                        }
                    });
                }
            }
        });

        // 计算X轴最大值
        let xAxisMax = 0;
        if (comparisonData.timePoints.length > 0) {
            const maxTime = Math.max(...comparisonData.timePoints);
            xAxisMax = Math.ceil(maxTime / 10) * 10; // 向上取整到10的倍数
        }

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
                    let result = `相对时间: ${time.toFixed(1)}s<br/>`;
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
                min: 0, // 强制从0开始
                max: xAxisMax, // 设置计算出的最大值
                scale: true // 启用缩放
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
                    ruleName: task.ruleName,
                    modelName: task.modelName,
                    modelVersion: task.modelVersion,
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
        let html = '<!DOCTYPE HTML>' +
        '<html>' +
        '<head>' +
        '<meta http-equiv="Content-Type" content="text/html; charset=UTF-8"></meta>' +
        '<meta charset="UTF-8">' +
        '<title>实验报告</title>' +
        '<style type="text/css">' +
        'body { font-family: SimSun, Microsoft YaHei, SimHei, Arial, sans-serif; font-size: ' + this.fontSize + 'pt; line-height: 1.5; margin: 0; padding: 0; }' +
        '.header { text-align: center; font-size: 14pt; font-weight: bold; margin-bottom: 30px; border-bottom: 2px solid #333; padding-bottom: 10px; }' +
        '.footer { text-align: center; font-size: 10pt; margin-top: 30px; border-top: 1px solid #333; padding-top: 10px; }' +
        '.title { text-align: center; font-size: 18pt; font-weight: bold; margin: 20px 0; }' +
        '.subtitle { font-size: 14pt; font-weight: bold; margin: 15px 0 10px 0; }' +
        '.content { padding: 20px; }' +
        '.section { margin: 20px 0; }' +
        '.text { margin: 10px 0; text-align: justify; }' +
        '.table { width: 100%; border-collapse: collapse; margin: 10px 0; table-layout: fixed; }' +
        '.table th, .table td { border: 1px solid #ddd; padding: 8px; text-align: left; word-wrap: break-word; min-width: 0; }' +
        '.table th { background-color: #f2f2f2; font-weight: bold; }' +
        '.image-title { font-weight: bold; margin: 10px 0 5px 0; }' +
        '.report-image { max-width: 100%; height: auto; }' +
        '.separator { height: 1px; background-color: #ccc; margin: 20px 0; }' +
        '@page { size: A4; margin: 2cm; }' +
        '@media print { body { font-family: SimSun, Microsoft YaHei, SimHei, Arial, sans-serif !important; } }' +
        '</style>' +
        '</head>' +
        '<body>' +
        '<div class="header">实验报告</div>' +
        '<div class="content">';

        // 添加内容
        this.content.forEach(item => {
            switch(item.type) {
                case 'text':
                    if (item.bold) {
                        html += '<div style="font-weight: bold; font-size: ' + item.fontSize + 'pt; margin: 5px 0; font-family: SimSun, Microsoft YaHei, SimHei, Arial, sans-serif;">' + item.text + '</div>';
                    } else {
                        html += '<div style="font-size: ' + item.fontSize + 'pt; margin: 5px 0; font-family: SimSun, Microsoft YaHei, SimHei, Arial, sans-serif;">' + item.text + '</div>';
                    }
                    break;
                case 'title':
                    html += '<div class="title" style="font-family: SimSun, Microsoft YaHei, SimHei, Arial, sans-serif;">' + item.text + '</div>';
                    break;
                case 'subtitle':
                    html += '<div class="subtitle" style="font-family: SimSun, Microsoft YaHei, SimHei, Arial, sans-serif;">' + item.text + '</div>';
                    break;
                case 'table':
                    // 生成HTML表格
                    html += '<table class="table">';
                    // 表头
                    html += '<tr>';
                    item.headers.forEach(header => {
                        html += '<th style="font-family: SimSun, Microsoft YaHei, SimHei, Arial, sans-serif;">' + header + '</th>';
                    });
                    html += '</tr>';
                    // 数据行
                    item.data.forEach(row => {
                        html += '<tr>';
                        row.forEach(cell => {
                            html += '<td style="font-family: SimSun, Microsoft YaHei, SimHei, Arial, sans-serif;">' + cell + '</td>';
                        });
                        html += '</tr>';
                    });
                    html += '</table>';
                    break;
                case 'image':
                    // 生成图片
                    html += '<div class="image-title" style="font-family: SimSun, Microsoft YaHei, SimHei, Arial, sans-serif;">' + item.title + '</div>';
                    html += '<img src="' + item.imageData + '" alt="' + item.description + '" class="report-image"></img>';
                    html += '<div style="text-align: center; font-size: 10pt; color: #666; margin: 5px 0; font-family: SimSun, Microsoft YaHei, SimHei, Arial, sans-serif;">' + item.description + '</div>';
                    break;
                case 'separator':
                    html += '<div class="separator"></div>';
                    break;
                case 'newPage':
                    html += '<div style="page-break-before: always;"></div>';
                    break;
            }
        });

        html += '</div>' +
        '<div class="footer" style="font-family: SimSun, Microsoft YaHei, SimHei, Arial, sans-serif;">实验报告生成时间: ' + new Date().toLocaleString() + '</div>' +
        '</body>' +
        '</html>';

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
