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
        this.pageSize = 20;
        this.totalPages = 0;
        this.analysisType = 'trend';
        this.dataSource = '';
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
        this.pageSize = 20;
        
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
        // 直接显示多任务对比分析
        this.showMultiTaskAnalysis();
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

        // 分页大小选择
        const pageSizeSelect = this.shadowRoot.getElementById('pageSizeSelect');
        if (pageSizeSelect) {
            pageSizeSelect.value = this.pageSize;
            pageSizeSelect.addEventListener('change', (e) => {
                this.pageSize = parseInt(e.target.value);
                this.currentPage = 1;
                this.updateTable();
            });
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
        const dataPoints = 200; // 生成200个数据点
        
        // 生成多个任务的数据
        const tasks = ['任务A', '任务B', '任务C'];
        
        for (let i = 0; i < dataPoints; i++) {
            const timestamp = now - (dataPoints - i) * 60000; // 每分钟一个数据点
            
            tasks.forEach(task => {
                let value = 100;
                let status = 'normal';
                let trend = 'stable';
                
                // 为不同任务生成不同特征的数据
                switch (task) {
                    case '任务A':
                        value = 100 + Math.sin(i * 0.05) * 30 + Math.random() * 10;
                        break;
                    case '任务B':
                        value = 90 + Math.cos(i * 0.03) * 25 + Math.random() * 15;
                        break;
                    case '任务C':
                        value = 110 + Math.sin(i * 0.04) * 20 + Math.random() * 8;
                        // 随机生成异常值
                        if (Math.random() < 0.03) {
                            value += (Math.random() - 0.5) * 80;
                            status = 'abnormal';
                        }
                        break;
                }
                
                trend = i > 0 && data.length > 0 ? 
                    (value > data[data.length - 1]?.value || value ? 'up' : 'down') : 'stable';
                
                const record = {
                    timestamp,
                    task,
                    value: parseFloat(value.toFixed(2)),
                    status,
                    trend,
                    remark: status === 'abnormal' ? '异常数据点' : (trend === 'up' ? '上升趋势' : trend === 'down' ? '下降趋势' : '平稳')
                };
                
                data.push(record);
            });
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
                    saveAsImage: {}
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
                    saveAsImage: {}
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
                    saveAsImage: {}
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
                    saveAsImage: {}
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
                    saveAsImage: {}
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
            
            // 任务列
            const taskTd = document.createElement('td');
            taskTd.textContent = record.task || '-';
            tr.appendChild(taskTd);
            
            // 时间列
            const timeTd = document.createElement('td');
            timeTd.textContent = new Date(record.timestamp).toLocaleString();
            tr.appendChild(timeTd);
            
            // 数值列
            const valueTd = document.createElement('td');
            valueTd.textContent = record.value.toFixed(2);
            tr.appendChild(valueTd);
            
            // 状态列
            const statusTd = document.createElement('td');
            const statusBadge = document.createElement('span');
            statusBadge.className = `status-badge ${record.status}`;
            statusBadge.textContent = record.status === 'normal' ? '正常' : '异常';
            statusTd.appendChild(statusBadge);
            tr.appendChild(statusTd);
            
            // 趋势列
            const trendTd = document.createElement('td');
            const trendBadge = document.createElement('span');
            trendBadge.className = `trend-badge ${record.trend}`;
            trendBadge.textContent = record.trend === 'up' ? '↑ 上升' : record.trend === 'down' ? '↓ 下降' : '→ 平稳';
            trendTd.appendChild(trendBadge);
            tr.appendChild(trendTd);
            
            // 备注列
            const remarkTd = document.createElement('td');
            remarkTd.textContent = record.remark || '-';
            tr.appendChild(remarkTd);
            
            tbody.appendChild(tr);
        });
        
        this.updatePagination();
    }

    updatePagination() {
        const pageList = this.shadowRoot.getElementById('pageList');
        const prevBtn = this.shadowRoot.getElementById('prevBtn');
        const nextBtn = this.shadowRoot.getElementById('nextBtn');
        const pageInfo = this.shadowRoot.getElementById('pageInfo');

        if (!pageList) return;

        pageList.innerHTML = '';
        
        if (this.totalPages <= 1) {
            prevBtn.disabled = true;
            nextBtn.disabled = true;
            if (pageInfo) {
                pageInfo.textContent = `第 1 页 / 共 1 页`;
            }
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
        
        if (pageInfo) {
            pageInfo.textContent = `第 ${this.currentPage} 页 / 共 ${this.totalPages} 页`;
        }
    }

    goToPage(page) {
        this.currentPage = page;
        this.updateTable();
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
        
        this.showMessage('已重置分析参数', 'info');
    }

    showMessage(message, type = 'info') {
        // 创建消息提示
        const messageDiv = document.createElement('div');
        messageDiv.className = `message-toast ${type}`;
        messageDiv.textContent = message;
        messageDiv.style.cssText = `
            position: fixed;
            top: 20px;
            right: 20px;
            padding: 12px 20px;
            border-radius: 4px;
            color: white;
            font-size: 14px;
            z-index: 10000;
            transition: all 0.3s;
            box-shadow: 0 2px 8px rgba(0,0,0,0.15);
        `;
        
        // 设置背景色
        switch (type) {
            case 'success':
                messageDiv.style.backgroundColor = '#52c41a';
                break;
            case 'warning':
                messageDiv.style.backgroundColor = '#faad14';
                break;
            case 'error':
                messageDiv.style.backgroundColor = '#ff4d4f';
                break;
            default:
                messageDiv.style.backgroundColor = '#1890ff';
        }
        
        document.body.appendChild(messageDiv);
        
        // 3秒后自动移除
        setTimeout(() => {
            if (messageDiv.parentNode) {
                messageDiv.parentNode.removeChild(messageDiv);
            }
        }, 3000);
    }
}

// 注册组件
if (!customElements.get('visual-analysis')) {
    customElements.define('visual-analysis', VisualAnalysis);
}