/**
 * 数据可视化组件 - 离线ECharts实现
 * 支持多测点对比、降采样、分页表格等功能
 */
class DataVisualization extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });
        this.chart = null;
        this.selectedPoints = new Set(); // 选中的测点
        this.allData = []; // 原始数据
        this.displayData = []; // 显示数据（可能经过降采样）
        this.currentPage = 1;
        this.pageSize = 50;
        this.totalPages = 0;
    }

    async connectedCallback() {
        await this.loadResources();
        this.render();
        setTimeout(() => {
            this.bindEvents();
            this.initChart();
        }, 100);
    }

    async loadResources() {
        // 加载CSS
        try {
            const cssLink = document.createElement('link');
            cssLink.rel = 'stylesheet';
            cssLink.href = './components/data-visualization/data-visualization.css';
            this.shadowRoot.appendChild(cssLink);
        } catch (error) {
            console.error('Failed to load CSS:', error);
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

    render() {
        this.shadowRoot.innerHTML = `
            <style>
                :host {
                    display: none;
                    width: 100%;
                    height: 100%;
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    flex: 1;
                    min-width: 0;
                    min-height: 1200px;
                }

                :host([show]) {
                    display: flex;
                    flex-direction: column;
                    flex: 1;
                    min-width: 0;
                    height: auto;
                }

                .visualization-container {
                    background: white;
                    border-radius: 8px;
                    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.1);
                    width: 100%;
                    min-height: 1200px;
                    overflow: visible;
                    display: flex;
                    flex-direction: column;
                    min-width: 0;
                }

                .content-area {
                    flex: 1;
                    display: flex;
                    flex-direction: column;
                    min-height: 0;
                }

                .visualization-header {
                    padding: 16px 20px;
                    border-bottom: 1px solid #e0e6ed;
                    display: flex;
                    justify-content: space-between;
                    align-items: center;
                    background: #f8f9fa;
                }

                .visualization-title {
                    font-size: 16px;
                    font-weight: 600;
                    color: #1f2329;
                    margin: 0;
                }

                .close-btn {
                    background: none;
                    border: none;
                    font-size: 18px;
                    cursor: pointer;
                    color: #646a73;
                    width: 24px;
                    height: 24px;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    border-radius: 4px;
                    transition: all 0.2s;
                }

                .close-btn:hover {
                    background: #e0e6ed;
                    color: #1f2329;
                }

                .content-area {
                    flex: 1;
                    display: flex;
                    flex-direction: column;
                    min-height: 0;
                }

                .chart-section {
                    flex: 0 0 350px;
                    padding: 16px;
                    border-bottom: 1px solid #e0e6ed;
                    position: relative;
                    display: flex;
                    flex-direction: column;
                }

                .chart-container {
                    width: 100%;
                    height: 100%;
                    min-height: 250px;
                    position: relative;
                    flex: 1;
                }

                .operations-section {
                    background: #fafbfc;
                    border-bottom: 1px solid #e0e6ed;
                    flex: 0 0 250px;
                    overflow: visible;
                }

                .operations-header {
                    padding: 12px 20px;
                    background: #f1f3f4;
                    border-bottom: 1px solid #e0e6ed;
                    display: flex;
                    justify-content: space-between;
                    align-items: center;
                }

                .operations-title {
                    font-size: 14px;
                    font-weight: 600;
                    color: #1f2329;
                    margin: 0;
                }

                .operations-actions {
                    display: flex;
                    gap: 8px;
                }

                .action-btn {
                    padding: 4px 12px;
                    border: 1px solid #d9d9d9;
                    background: white;
                    border-radius: 4px;
                    font-size: 12px;
                    cursor: pointer;
                    transition: all 0.2s;
                    color: #646a73;
                }

                .action-btn:hover {
                    border-color: #3370ff;
                    color: #3370ff;
                }

                .operations-content {
                    padding: 20px;
                    display: flex;
                    flex-direction: column;
                    gap: 24px;
                }

                .query-controls {
                    display: flex;
                    flex-direction: column;
                    gap: 20px;
                    padding: 16px;
                    background: #f8f9fa;
                    border-radius: 8px;
                    border: 1px solid #e0e6ed;
                }

                .query-row {
                    display: flex;
                    align-items: center;
                    gap: 20px;
                    flex-wrap: wrap;
                }

                .query-item {
                    display: flex;
                    align-items: center;
                    gap: 10px;
                    min-width: 0;
                }

                .query-label {
                    font-size: 13px;
                    font-weight: 500;
                    color: #1f2329;
                    white-space: nowrap;
                    min-width: 70px;
                }

                .query-input {
                    padding: 8px 12px;
                    border: 1px solid #d9d9d9;
                    border-radius: 4px;
                    font-size: 13px;
                    outline: none;
                    min-width: 140px;
                    max-width: 200px;
                }

                .query-input:focus {
                    border-color: #3370ff;
                    box-shadow: 0 0 0 2px rgba(51, 112, 255, 0.1);
                }

                .query-select {
                    padding: 8px 12px;
                    border: 1px solid #d9d9d9;
                    border-radius: 4px;
                    font-size: 13px;
                    outline: none;
                    background: white;
                    min-width: 140px;
                    max-width: 180px;
                }

                .query-select:focus {
                    border-color: #3370ff;
                    box-shadow: 0 0 0 2px rgba(51, 112, 255, 0.1);
                }

                .quick-time-buttons {
                    display: flex;
                    gap: 8px;
                    flex-wrap: wrap;
                }

                .quick-time-btn {
                    padding: 6px 12px;
                    border: 1px solid #d9d9d9;
                    background: white;
                    border-radius: 4px;
                    font-size: 12px;
                    cursor: pointer;
                    transition: all 0.2s;
                }

                .quick-time-btn:hover {
                    border-color: #3370ff;
                    color: #3370ff;
                }

                .quick-time-btn.active {
                    border-color: #3370ff;
                    background: #3370ff;
                    color: white;
                }

                .query-actions {
                    display: flex;
                    gap: 16px;
                    align-items: center;
                    margin-left: auto;
                }

                .query-btn {
                    padding: 10px 24px;
                    background: #3370ff;
                    color: white;
                    border: none;
                    border-radius: 4px;
                    font-size: 14px;
                    cursor: pointer;
                    transition: all 0.2s;
                    font-weight: 500;
                }

                .query-btn:hover {
                    background: #1e5fcc;
                }

                .query-btn:disabled {
                    background: #d9d9d9;
                    cursor: not-allowed;
                }

                .selected-points-panel {
                    padding: 16px;
                    background: #f8f9fa;
                    border-radius: 8px;
                    border: 1px solid #e0e6ed;
                }

                .selected-points-title {
                    font-size: 14px;
                    font-weight: 600;
                    color: #1f2329;
                    margin-bottom: 12px;
                }

                .selected-points-list {
                    display: flex;
                    flex-wrap: wrap;
                    gap: 8px;
                    min-height: 32px;
                }

                .selected-points-title {
                    font-size: 13px;
                    font-weight: 500;
                    color: #1f2329;
                    margin-bottom: 8px;
                }

                .selected-point-item {
                    display: inline-flex;
                    align-items: center;
                    gap: 6px;
                    padding: 6px 10px;
                    background: #e8f0fe;
                    border: 1px solid #3370ff;
                    border-radius: 16px;
                    font-size: 12px;
                    color: #3370ff;
                    font-weight: 500;
                    margin-bottom: 0;
                }

                .selected-point-name {
                    white-space: nowrap;
                    color: #3370ff;
                }

                .remove-point {
                    background: none;
                    border: none;
                    color: #3370ff;
                    cursor: pointer;
                    font-size: 14px;
                    font-weight: bold;
                    padding: 0;
                    width: 16px;
                    height: 16px;
                    border-radius: 50%;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    transition: all 0.2s;
                }

                .remove-point:hover {
                    background: #3370ff;
                    color: white;
                }

                .table-section {
                    flex: 1;
                    display: flex;
                    flex-direction: column;
                    background: white;
                    min-height: 400px;
                    position: relative;
                }

                .table-header {
                    padding: 12px 20px;
                    background: #f1f3f4;
                    border-bottom: 1px solid #e0e6ed;
                    display: flex;
                    justify-content: space-between;
                    align-items: center;
                }

                .table-title {
                    font-size: 14px;
                    font-weight: 500;
                    color: #1f2329;
                }

                .selected-points-in-header {
                    display: flex;
                    align-items: center;
                    gap: 12px;
                }

                .selected-points-label {
                    font-size: 13px;
                    color: #646a73;
                    white-space: nowrap;
                }

                .selected-points-compact {
                    display: flex;
                    flex-wrap: wrap;
                    gap: 6px;
                    max-width: 300px;
                }

                .table-wrapper {
                    flex: 1;
                    overflow: visible;
                    min-height: 200px;
                    position: relative;
                }

                .pagination {
                    display: flex;
                    justify-content: space-between;
                    align-items: center;
                    padding: 12px 20px;
                    background: #f8f9fa;
                    border-top: 1px solid #e0e6ed;
                }

                .pagination-left {
                    display: flex;
                    align-items: center;
                    gap: 16px;
                }

                .pagination-right {
                    display: flex;
                    align-items: center;
                    gap: 8px;
                }

                .page-size-selector {
                    display: flex;
                    align-items: center;
                    gap: 8px;
                    font-size: 13px;
                    color: #646a73;
                }

                .page-size-select {
                    padding: 4px 8px;
                    border: 1px solid #d9d9d9;
                    border-radius: 4px;
                    font-size: 12px;
                    outline: none;
                    background: white;
                }

                .page-size-select:focus {
                    border-color: #3370ff;
                    box-shadow: 0 0 0 2px rgba(51, 112, 255, 0.1);
                }

                .page-info {
                    font-size: 13px;
                    color: #646a73;
                    min-width: 120px;
                }

                .pagination button {
                    padding: 4px 8px;
                    border: 1px solid #d9d9d9;
                    background: white;
                    cursor: pointer;
                    border-radius: 4px;
                    font-size: 12px;
                    transition: all 0.2s;
                }

                .pagination button:hover:not(:disabled) {
                    border-color: #3370ff;
                    color: #3370ff;
                }

                .pagination button:disabled {
                    opacity: 0.5;
                    cursor: not-allowed;
                }

                .table-wrapper {
                    flex: 1;
                    overflow: visible;
                    min-height: 200px;
                    position: relative;
                }

                table {
                    width: 100%;
                    border-collapse: collapse;
                    font-size: 13px;
                }

                th, td {
                    padding: 8px 12px;
                    text-align: left;
                    border-bottom: 1px solid #f0f0f0;
                    white-space: nowrap;
                }

                th {
                    background: #fafbfc;
                    font-weight: 500;
                    color: #1f2329;
                    position: sticky;
                    top: 0;
                    z-index: 10;
                    border-bottom: 1px solid #e0e6ed;
                }

                td {
                    color: #646a73;
                }

                tr:hover td {
                    background: #f8f9fa;
                }

                /* 弹框样式 */
                .modal-overlay {
                    position: fixed;
                    top: 0;
                    left: 0;
                    right: 0;
                    bottom: 0;
                    background: rgba(0, 0, 0, 0.5);
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    z-index: 1000;
                }

                .modal {
                    background: white;
                    border-radius: 8px;
                    width: 500px;
                    max-width: 90%;
                    max-height: 80%;
                    overflow: hidden;
                    box-shadow: 0 4px 20px rgba(0, 0, 0, 0.15);
                }

                .modal-header {
                    padding: 16px 20px;
                    border-bottom: 1px solid #e0e6ed;
                    display: flex;
                    justify-content: space-between;
                    align-items: center;
                }

                .modal-title {
                    font-size: 16px;
                    font-weight: 600;
                    color: #1f2329;
                    margin: 0;
                }

                .modal-close {
                    background: none;
                    border: none;
                    font-size: 20px;
                    cursor: pointer;
                    color: #646a73;
                    width: 24px;
                    height: 24px;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    border-radius: 2px;
                    transition: all 0.2s;
                }

                .modal-close:hover {
                    background: #f0f0f0;
                }

                .modal-body {
                    padding: 20px;
                    max-height: 400px;
                    overflow-y: auto;
                }

                .modal-footer {
                    padding: 12px 20px;
                    border-top: 1px solid #e0e6ed;
                    display: flex;
                    justify-content: flex-end;
                    gap: 8px;
                }

                .modal-btn {
                    padding: 6px 16px;
                    border: 1px solid #d9d9d9;
                    background: white;
                    border-radius: 4px;
                    font-size: 13px;
                    cursor: pointer;
                    transition: all 0.2s;
                }

                .modal-btn.primary {
                    background: #3370ff;
                    color: white;
                    border-color: #3370ff;
                }

                .modal-btn:hover {
                    border-color: #3370ff;
                    color: #3370ff;
                }

                .modal-btn.primary:hover {
                    background: #1e5fcc;
                    border-color: #1e5fcc;
                }

                .loading {
                    position: absolute;
                    top: 50%;
                    left: 50%;
                    transform: translate(-50%, -50%);
                    text-align: center;
                    color: #646a73;
                    font-size: 14px;
                }

                .downsampling-info {
                    position: absolute;
                    top: 8px;
                    right: 8px;
                    background: rgba(255, 165, 0, 0.1);
                    border: 1px solid #ffa500;
                    border-radius: 4px;
                    padding: 4px 8px;
                    font-size: 11px;
                    color: #ff8c00;
                    z-index: 100;
                }
            </style>
            <div class="visualization-container">
                <div class="visualization-header">
                    <h3 class="visualization-title">数据可视化 - <span id="dataSourceName"></span></h3>
                    <button class="close-btn" id="closeBtn">&times;</button>
                </div>
                
                <div class="content-area">
                    <div class="chart-section">
                        <div class="chart-container" id="chartContainer">
                            <div class="loading">正在加载数据...</div>
                            <div class="downsampling-info" id="downsamplingInfo" style="display: none;"></div>
                        </div>
                    </div>

                    <div class="operations-section">
                        <div class="operations-header">
                            <h4 class="operations-title">操作</h4>
                            <div class="operations-actions">
                                <button class="action-btn" id="dataCleanBtn">数据清理</button>
                                <button class="action-btn" id="importBtn">导入数据</button>
                                <button class="action-btn" id="exportBtn">导出数据</button>
                            </div>
                        </div>
                        <div class="operations-content">
                            <div class="query-controls">
                                <div class="query-row">
                                    <div class="query-item">
                                        <label class="query-label">开始时间</label>
                                        <input type="datetime-local" class="query-input" id="startTime">
                                    </div>
                                    <div class="query-item">
                                        <label class="query-label">结束时间</label>
                                        <input type="datetime-local" class="query-input" id="endTime">
                                    </div>
                                    <div class="query-item">
                                        <label class="query-label">聚合函数</label>
                                        <select class="query-select" id="aggregationFunction">
                                            <option value="raw">原始数据</option>
                                            <option value="avg">平均值</option>
                                            <option value="max">最大值</option>
                                            <option value="min">最小值</option>
                                            <option value="sum">求和</option>
                                            <option value="count">计数</option>
                                        </select>
                                    </div>
                                </div>
                                
                                <div class="query-row">
                                    <div class="query-item">
                                        <label class="query-label">快速选择</label>
                                        <div class="quick-time-buttons">
                                            <button class="quick-time-btn" data-range="1h">最近1小时</button>
                                            <button class="quick-time-btn" data-range="6h">最近6小时</button>
                                            <button class="quick-time-btn" data-range="24h">最近24小时</button>
                                            <button class="quick-time-btn" data-range="7d">最近7天</button>
                                        </div>
                                    </div>
                                    <div class="query-actions">
                                        <button class="query-btn" id="queryBtn">查询数据</button>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>

                    <div class="table-section">
                        <div class="table-header">
                            <span class="table-title">数据列表</span>
                            <div class="selected-points-in-header">
                                <span class="selected-points-label">已选测点:</span>
                                <div class="selected-points-compact" id="selectedPointsList">
                                    <!-- 动态生成已选测点列表 -->
                                </div>
                            </div>
                        </div>
                        <div class="table-wrapper">
                            <table id="dataTable">
                                <thead>
                                    <tr>
                                        <th>时间</th>
                                        <!-- 动态生成测点列头 -->
                                    </tr>
                                </thead>
                                <tbody id="tableBody">
                                    <!-- 动态生成表格数据 -->
                                </tbody>
                            </table>
                            <div class="pagination">
                                <div class="pagination-left">
                                    <div class="page-size-selector">
                                        <span>每页显示</span>
                                        <select class="page-size-select" id="pageSizeSelect">
                                            <option value="10">10条</option>
                                            <option value="20" selected>20条</option>
                                            <option value="50">50条</option>
                                            <option value="100">100条</option>
                                        </select>
                                    </div>
                                    <span class="page-info" id="pageInfo">第 1 页 / 共 1 页</span>
                                </div>
                                <div class="pagination-right">
                                    <button id="prevBtn">上一页</button>
                                    <button id="nextBtn">下一页</button>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        `;
    }

    bindEvents() {
        // 关闭按钮
        const closeBtn = this.shadowRoot.getElementById('closeBtn');
        if (closeBtn) {
            closeBtn.addEventListener('click', () => {
                this.hide();
            });
        }

        // 数据清理按钮
        const dataCleanBtn = this.shadowRoot.getElementById('dataCleanBtn');
        if (dataCleanBtn) {
            dataCleanBtn.addEventListener('click', () => {
                this.showDataCleanModal();
            });
        }

        // 导入数据按钮
        const importBtn = this.shadowRoot.getElementById('importBtn');
        if (importBtn) {
            importBtn.addEventListener('click', () => {
                this.showImportModal();
            });
        }

        // 导出数据按钮
        const exportBtn = this.shadowRoot.getElementById('exportBtn');
        if (exportBtn) {
            exportBtn.addEventListener('click', () => {
                this.showExportModal();
            });
        }

        // 分页大小选择
        const pageSizeSelect = this.shadowRoot.getElementById('pageSizeSelect');
        if (pageSizeSelect) {
            pageSizeSelect.value = this.pageSize; // 确保选择器显示正确的值
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

    initChart() {
        const chartContainer = this.shadowRoot.getElementById('chartContainer');
        if (chartContainer && window.echarts) {
            // 清除加载提示
            const loadingEl = chartContainer.querySelector('.loading');
            if (loadingEl) {
                loadingEl.remove();
            }
            
            // 等待DOM完全渲染，使用更长的延迟和多次检查
            const tryInitChart = (attempt = 0) => {
                if (window.echarts && !this.chart) {
                    const rect = chartContainer.getBoundingClientRect();
                    console.log(`尝试初始化图表 (第${attempt + 1}次):`, rect);
                    
                    // 如果高度太小，继续等待
                    if (rect.height < 100 && attempt < 5) {
                        setTimeout(() => tryInitChart(attempt + 1), 200);
                        return;
                    }
                    
                    // 强制设置最小高度
                    if (rect.height < 350) {
                        chartContainer.style.height = '350px';
                        console.log('设置图表容器高度为350px');
                    }
                    
                    // 确保宽度正确
                    if (rect.width < 100) {
                        chartContainer.style.width = '100%';
                    }
                    
                    this.chart = window.echarts.init(chartContainer);
                    
                    // 监听窗口大小变化
                    window.addEventListener('resize', () => {
                        if (this.chart) {
                            this.chart.resize();
                        }
                    });
                    
                    this.updateChart();
                    console.log('图表初始化成功');
                }
            };
            
            // 开始尝试初始化
            setTimeout(() => tryInitChart(), 100);
        } else {
            console.error('ECharts not loaded or chart container not found');
        }
    }

    show(dataSource, points = []) {
        console.log('显示数据可视化:', dataSource, points);
        this.setAttribute('show', '');
        this.dataSource = dataSource;
        this.availablePoints = points;
        this.selectedPoints = new Set(points); // 直接使用传入的测点
        this.allData = [];
        this.displayData = [];
        this.currentPage = 1;
        this.pageSize = 20; // 与HTML默认值保持一致
        
        // 设置数据源名称
        const dataSourceNameEl = this.shadowRoot.getElementById('dataSourceName');
        if (dataSourceNameEl) {
            dataSourceNameEl.textContent = '多测点对比';
        }
        
        console.log('组件已显示，开始初始化...');
        
        // 强制重新计算布局
        setTimeout(() => {
            // 更新已选测点列表
            this.updateSelectedPointsList();
            
            // 绑定查询控件事件
            this.bindQueryEvents();
            
            // 加载数据
            this.loadData();
            
            // 强制触发重新布局
            this.updateLayout();
        }, 50);
    }

    hide() {
        console.log('隐藏数据可视化');
        this.removeAttribute('show');
        if (this.chart) {
            this.chart.dispose();
            this.chart = null;
        }
    }

    updateLayout() {
        // 强制重新计算布局
        const chartContainer = this.shadowRoot.getElementById('chartContainer');
        if (chartContainer) {
            // 强制重新计算尺寸
            chartContainer.style.display = 'none';
            chartContainer.offsetHeight; // 触发重排
            chartContainer.style.display = '';
            
            // 如果图表已存在，强制重新调整大小
            if (this.chart) {
                setTimeout(() => {
                    this.chart.resize();
                }, 100);
            }
        }
    }

    updateSelectedPointsList() {
        const selectedPointsList = this.shadowRoot.getElementById('selectedPointsList');
        if (!selectedPointsList) return;

        selectedPointsList.innerHTML = '';
        
        if (this.selectedPoints.size === 0) {
            selectedPointsList.innerHTML = '<span style="color: #999; font-size: 12px;">暂无选中的测点</span>';
            return;
        }

        this.selectedPoints.forEach(point => {
            const pointItem = document.createElement('div');
            pointItem.className = 'selected-point-item';
            pointItem.innerHTML = `
                <span class="selected-point-name">${point}</span>
                <button class="remove-point" data-point="${point}">×</button>
            `;
            
            // 绑定移除事件
            const removeBtn = pointItem.querySelector('.remove-point');
            removeBtn.addEventListener('click', () => {
                this.removeSelectedPoint(point);
            });
            
            selectedPointsList.appendChild(pointItem);
        });
    }

    removeSelectedPoint(point) {
        this.selectedPoints.delete(point);
        
        // 更新全局选中的测点
        if (window.selectedDataPoints) {
            window.selectedDataPoints.delete(point);
        }
        
        // 更新显示
        this.updateSelectedPointsList();
        
        // 重新加载数据
        this.loadData();
    }

    bindQueryEvents() {
        // 绑定快速时间按钮
        const quickTimeBtns = this.shadowRoot.querySelectorAll('.quick-time-btn');
        quickTimeBtns.forEach(btn => {
            btn.addEventListener('click', () => {
                // 移除其他按钮的active状态
                quickTimeBtns.forEach(b => b.classList.remove('active'));
                btn.classList.add('active');
                
                // 设置时间范围
                const range = btn.dataset.range;
                this.setTimeRange(range);
            });
        });

        // 绑定查询按钮
        const queryBtn = this.shadowRoot.getElementById('queryBtn');
        if (queryBtn) {
            queryBtn.addEventListener('click', () => {
                this.executeQuery();
            });
        }
    }

    setTimeRange(range) {
        const now = new Date();
        let startTime;
        
        switch (range) {
            case '1h':
                startTime = new Date(now.getTime() - 60 * 60 * 1000);
                break;
            case '6h':
                startTime = new Date(now.getTime() - 6 * 60 * 60 * 1000);
                break;
            case '24h':
                startTime = new Date(now.getTime() - 24 * 60 * 60 * 1000);
                break;
            case '7d':
                startTime = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
                break;
            default:
                return;
        }
        
        const startTimeInput = this.shadowRoot.getElementById('startTime');
        const endTimeInput = this.shadowRoot.getElementById('endTime');
        
        if (startTimeInput) {
            startTimeInput.value = this.formatDateTime(startTime);
        }
        if (endTimeInput) {
            endTimeInput.value = this.formatDateTime(now);
        }
    }

    formatDateTime(date) {
        const year = date.getFullYear();
        const month = String(date.getMonth() + 1).padStart(2, '0');
        const day = String(date.getDate()).padStart(2, '0');
        const hours = String(date.getHours()).padStart(2, '0');
        const minutes = String(date.getMinutes()).padStart(2, '0');
        
        return `${year}-${month}-${day}T${hours}:${minutes}`;
    }

    executeQuery() {
        console.log('执行查询，选中的测点:', Array.from(this.selectedPoints));
        
        if (this.selectedPoints.size === 0) {
            this.showMessage('请先选择测点');
            return;
        }
        
        // 重新加载数据
        this.loadData();
    }

    showMessage(message) {
        // 简单的消息提示
        const messageEl = document.createElement('div');
        messageEl.style.cssText = `
            position: fixed;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            background: rgba(0, 0, 0, 0.8);
            color: white;
            padding: 12px 20px;
            border-radius: 4px;
            z-index: 10000;
            font-size: 14px;
        `;
        messageEl.textContent = message;
        document.body.appendChild(messageEl);
        
        setTimeout(() => {
            messageEl.remove();
        }, 2000);
    }

    showDataCleanModal() {
        this.showModal('数据清理', `
            <div style="margin-bottom: 16px;">
                <label style="display: block; margin-bottom: 8px; font-size: 14px; color: #1f2329;">清理范围</label>
                <select style="width: 100%; padding: 8px; border: 1px solid #d9d9d9; border-radius: 4px;">
                    <option>当前选中的测点</option>
                    <option>所有数据</option>
                    <option>指定时间范围</option>
                </select>
            </div>
            <div style="margin-bottom: 16px;">
                <label style="display: block; margin-bottom: 8px; font-size: 14px; color: #1f2329;">清理规则</label>
                <div style="display: flex; flex-direction: column; gap: 8px;">
                    <label style="display: flex; align-items: center; gap: 8px;">
                        <input type="checkbox" checked> 删除异常值
                    </label>
                    <label style="display: flex; align-items: center; gap: 8px;">
                        <input type="checkbox"> 删除重复数据
                    </label>
                    <label style="display: flex; align-items: center; gap: 8px;">
                        <input type="checkbox"> 填充缺失值
                    </label>
                </div>
            </div>
        `, () => {
            this.showMessage('数据清理完成');
        });
    }

    showImportModal() {
        this.showModal('导入数据', `
            <div style="margin-bottom: 16px;">
                <label style="display: block; margin-bottom: 8px; font-size: 14px; color: #1f2329;">文件格式</label>
                <select style="width: 100%; padding: 8px; border: 1px solid #d9d9d9; border-radius: 4px;">
                    <option>CSV文件</option>
                    <option>Excel文件</option>
                    <option>JSON文件</option>
                </select>
            </div>
            <div style="margin-bottom: 16px;">
                <label style="display: block; margin-bottom: 8px; font-size: 14px; color: #1f2329;">选择文件</label>
                <input type="file" style="width: 100%; padding: 8px; border: 1px solid #d9d9d9; border-radius: 4px;">
            </div>
            <div style="margin-bottom: 16px;">
                <label style="display: block; margin-bottom: 8px; font-size: 14px; color: #1f2329;">导入选项</label>
                <div style="display: flex; flex-direction: column; gap: 8px;">
                    <label style="display: flex; align-items: center; gap: 8px;">
                        <input type="checkbox" checked> 覆盖重复数据
                    </label>
                    <label style="display: flex; align-items: center; gap: 8px;">
                        <input type="checkbox"> 自动识别数据类型
                    </label>
                </div>
            </div>
        `, () => {
            this.showMessage('数据导入成功');
        });
    }

    showExportModal() {
        this.showModal('导出数据', `
            <div style="margin-bottom: 16px;">
                <label style="display: block; margin-bottom: 8px; font-size: 14px; color: #1f2329;">导出格式</label>
                <select style="width: 100%; padding: 8px; border: 1px solid #d9d9d9; border-radius: 4px;">
                    <option>CSV文件</option>
                    <option>Excel文件</option>
                    <option>JSON文件</option>
                </select>
            </div>
            <div style="margin-bottom: 16px;">
                <label style="display: block; margin-bottom: 8px; font-size: 14px; color: #1f2329;">导出范围</label>
                <select style="width: 100%; padding: 8px; border: 1px solid #d9d9d9; border-radius: 4px;">
                    <option>当前页面数据</option>
                    <option>所有选中测点数据</option>
                    <option>指定时间范围</option>
                </select>
            </div>
            <div style="margin-bottom: 16px;">
                <label style="display: block; margin-bottom: 8px; font-size: 14px; color: #1f2329;">文件名</label>
                <input type="text" value="data_export" style="width: 100%; padding: 8px; border: 1px solid #d9d9d9; border-radius: 4px;">
            </div>
        `, () => {
            this.showMessage('数据导出成功');
        });
    }

    showModal(title, content, onConfirm) {
        // 创建弹框元素
        const modalOverlay = document.createElement('div');
        modalOverlay.className = 'modal-overlay';
        modalOverlay.innerHTML = `
            <div class="modal">
                <div class="modal-header">
                    <h3 class="modal-title">${title}</h3>
                    <button class="modal-close">&times;</button>
                </div>
                <div class="modal-body">
                    ${content}
                </div>
                <div class="modal-footer">
                    <button class="modal-btn" id="modalCancel">取消</button>
                    <button class="modal-btn primary" id="modalConfirm">确认</button>
                </div>
            </div>
        `;

        // 添加到页面
        document.body.appendChild(modalOverlay);

        // 绑定事件
        const closeBtn = modalOverlay.querySelector('.modal-close');
        const cancelBtn = modalOverlay.querySelector('#modalCancel');
        const confirmBtn = modalOverlay.querySelector('#modalConfirm');

        const closeModal = () => {
            modalOverlay.remove();
        };

        closeBtn.addEventListener('click', closeModal);
        cancelBtn.addEventListener('click', closeModal);
        confirmBtn.addEventListener('click', () => {
            if (onConfirm) onConfirm();
            closeModal();
        });

        // 点击遮罩关闭
        modalOverlay.addEventListener('click', (e) => {
            if (e.target === modalOverlay) {
                closeModal();
            }
        });
    }

    async loadData() {
        try {
            console.log('开始加载数据，选中的测点:', Array.from(this.selectedPoints));
            console.log('selectedPoints size:', this.selectedPoints.size);
            
            if (this.selectedPoints.size === 0) {
                console.log('没有选中的测点，显示空状态');
                this.showEmptyState();
                return;
            }
            
            // 模拟数据加载 - 实际项目中应该调用API
            console.log('开始生成模拟数据...');
            const mockData = this.generateMockData();
            console.log('生成的模拟数据:', mockData.length, '条记录');
            if (mockData.length > 0) {
                console.log('第一条数据:', mockData[0]);
            }
            
            this.allData = mockData;
            
            // 应用降采样
            console.log('应用降采样...');
            this.applyDownsampling();
            console.log('降采样后数据:', this.displayData.length, '条记录');
            
            // 初始化图表（如果还没有初始化）
            if (!this.chart) {
                console.log('初始化图表...');
                this.initChart();
            } else {
                console.log('更新可视化...');
                // 更新可视化
                this.updateVisualization();
            }
            
        } catch (error) {
            console.error('加载数据失败:', error);
            this.showError('加载数据失败，请稍后重试');
        }
    }

    showEmptyState() {
        const chartContainer = this.shadowRoot.getElementById('chartContainer');
        if (chartContainer) {
            chartContainer.innerHTML = `
                <div style="display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100%; color: #999;">
                    <div style="font-size: 48px; margin-bottom: 16px;">📊</div>
                    <div style="font-size: 14px; margin-bottom: 8px;">暂无数据</div>
                    <div style="font-size: 12px;">请在左侧选择测点后点击查询</div>
                </div>
            `;
        }
        
        // 确保表格区域显示并更新为空状态
        this.updateTable();
    }

    showError(message) {
        const chartContainer = this.shadowRoot.getElementById('chartContainer');
        if (chartContainer) {
            chartContainer.innerHTML = `
                <div style="display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100%; color: #ff4d4f;">
                    <div style="font-size: 48px; margin-bottom: 16px;">❌</div>
                    <div style="font-size: 14px;">${message}</div>
                </div>
            `;
        }
    }

    generateMockData() {
        const data = [];
        const now = Date.now();
        const selectedPointsArray = Array.from(this.selectedPoints);
        
        console.log('生成模拟数据，测点数量:', selectedPointsArray.length, '测点列表:', selectedPointsArray);
        
        if (selectedPointsArray.length === 0) {
            console.log('没有选中的测点，返回空数据');
            return [];
        }
        
        // 生成1000个数据点
        for (let i = 0; i < 1000; i++) {
            const record = {
                timestamp: now - (1000 - i) * 1000, // 每秒一个数据点
                values: {}
            };
            
            // 为每个选中的测点生成数据
            selectedPointsArray.forEach((pointName, index) => {
                // 为不同测点生成不同特征的数据
                const baseValue = 100 + index * 50;
                record.values[pointName] = baseValue + Math.sin(i * 0.01 + index) * 30 + Math.random() * 20;
            });
            
            data.push(record);
        }
        
        console.log('生成了', data.length, '条数据');
        console.log('第一条数据:', data[0]);
        return data;
    }

    applyDownsampling() {
        if (this.allData.length <= 2000) {
            this.displayData = this.allData;
            this.hideDownsamplingInfo();
            return;
        }

        // 使用LTTB (Largest Triangle Three Buckets) 降采样算法
        this.displayData = this.lttbDownsample(this.allData, 2000);
        this.showDownsamplingInfo();
    }

    lttbDownsample(data, threshold) {
        if (!data || data.length <= threshold) return data || [];

        const sampled = [];
        const bucketSize = (data.length - 2) / (threshold - 2);
        
        // 始终保留第一个点
        if (data[0]) {
            sampled.push(data[0]);
        }
        
        let a = 0;
        for (let i = 0; i < threshold - 2; i++) {
            // 计算桶的范围
            const avgRangeStart = Math.floor((i + 1) * bucketSize) + 1;
            const avgRangeEnd = Math.floor((i + 2) * bucketSize) + 1;
            const avgRangeLength = avgRangeEnd - avgRangeStart;
            
            if (avgRangeStart >= data.length) break;
            
            const avgBucket = this.calculateAverageBucket(data, avgRangeStart, avgRangeLength);
            
            // 获取下一个桶的范围
            const nextBucketStart = Math.floor((i + 2) * bucketSize) + 1;
            const nextBucketEnd = Math.floor((i + 3) * bucketSize) + 1;
            const nextBucketLength = nextBucketEnd - nextBucketStart;
            
            const nextBucket = this.calculateMaxPoint(data, nextBucketStart, nextBucketLength);
            
            // 选择面积最大的点
            const areaPoint = this.calculateMaxAreaPoint(data[a], avgBucket, nextBucket, avgRangeStart, avgRangeEnd);
            
            if (areaPoint && areaPoint.timestamp) {
                sampled.push(areaPoint);
                a = avgRangeStart + areaPoint.bucketIndex;
            }
        }
        
        // 始终保留最后一个点
        if (data.length > 1 && data[data.length - 1]) {
            sampled.push(data[data.length - 1]);
        }
        
        return sampled;
    }

    calculateAverageBucket(data, start, length) {
        const avg = { timestamp: 0, values: {} };
        let count = 0;
        
        for (let i = start; i < start + length && i < data.length; i++) {
            const point = data[i];
            if (!point || !point.timestamp || !point.values) continue;
            
            avg.timestamp += point.timestamp;
            for (const pointName in point.values) {
                if (!avg.values[pointName]) avg.values[pointName] = 0;
                avg.values[pointName] += (point.values[pointName] || 0);
            }
            count++;
        }
        
        if (count > 0) {
            avg.timestamp /= count;
            for (const pointName in avg.values) {
                avg.values[pointName] /= count;
            }
        }
        
        return avg;
    }

    calculateMaxPoint(data, start, length) {
        let maxPoint = data[start];
        let maxValue = -Infinity;
        
        for (let i = start; i < start + length && i < data.length; i++) {
            const point = data[i];
            if (!point || !point.values) continue;
            
            const totalValue = Object.values(point.values).reduce((sum, val) => sum + (val || 0), 0);
            if (totalValue > maxValue) {
                maxValue = totalValue;
                maxPoint = point;
            }
        }
        
        return maxPoint || { timestamp: Date.now(), values: {} };
    }

    calculateMaxAreaPoint(a, avg, b, start, end) {
        let maxArea = -Infinity;
        let maxPoint = a;
        let maxIndex = 0;
        
        for (let i = start; i < end && i < this.allData.length; i++) {
            const point = this.allData[i];
            if (!point || !point.timestamp) continue; // 跳过无效数据点
            
            const area = this.calculateTriangleArea(a, avg, b, point);
            if (area > maxArea) {
                maxArea = area;
                maxPoint = point;
                maxIndex = i - start;
            }
        }
        
        maxPoint.bucketIndex = maxIndex;
        return maxPoint;
    }

    calculateTriangleArea(a, avg, b, point) {
        // 参数验证
        if (!a || !avg || !b || !point || 
            !a.timestamp || !avg.timestamp || !b.timestamp || !point.timestamp ||
            !a.values || !avg.values || !b.values || !point.values) {
            return 0;
        }
        
        // 简化的三角形面积计算
        const timeDiff = b.timestamp - a.timestamp;
        const aValueSum = Object.values(a.values).reduce((sum, val) => sum + (val || 0), 0);
        const bValueSum = Object.values(b.values).reduce((sum, val) => sum + (val || 0), 0);
        const pointValueSum = Object.values(point.values).reduce((sum, val) => sum + (val || 0), 0);
        
        const valueDiff = bValueSum - aValueSum;
        const pointTimeDiff = point.timestamp - a.timestamp;
        const pointValueDiff = pointValueSum - aValueSum;
        
        return Math.abs(timeDiff * pointValueDiff - pointTimeDiff * valueDiff) / 2;
    }

    showDownsamplingInfo() {
        const info = this.shadowRoot.getElementById('downsamplingInfo');
        if (info) {
            info.style.display = 'block';
            info.textContent = `数据已降采样：${this.allData.length} → ${this.displayData.length} 点`;
        }
    }

    hideDownsamplingInfo() {
        const info = this.shadowRoot.getElementById('downsamplingInfo');
        if (info) {
            info.style.display = 'none';
        }
    }

    updateVisualization() {
        this.updateChart();
        this.updateTable();
    }

    updateChart() {
        if (!this.chart || !this.displayData.length || this.selectedPoints.size === 0) return;

        const series = [];
        const selectedPointsArray = Array.from(this.selectedPoints);
        
        selectedPointsArray.forEach((point, index) => {
            const data = this.displayData.map(record => [
                record.timestamp,
                record.values[point] || 0
            ]);
            
            series.push({
                name: point,
                type: 'line',
                data: data,
                smooth: true,
                symbol: 'none',
                lineStyle: {
                    width: 2
                },
                itemStyle: {
                    color: this.getColorForIndex(index)
                }
            });
        });

        const option = {
            title: {
                text: `${this.dataSource} - 数据趋势`,
                left: 'center',
                top: 10,
                textStyle: {
                    fontSize: 14,
                    fontWeight: 'normal',
                    color: '#1f2329'
                }
            },
            tooltip: {
                trigger: 'axis',
                formatter: (params) => {
                    const time = new Date(params[0].value[0]).toLocaleString();
                    let result = `时间: ${time}<br/>`;
                    params.forEach(param => {
                        result += `${param.seriesName}: ${param.value[1].toFixed(2)}<br/>`;
                    });
                    return result;
                }
            },
            legend: {
                data: selectedPointsArray,
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
                top: '20%',
                containLabel: true
            },
            xAxis: {
                type: 'time',
                axisLabel: {
                    formatter: (value) => {
                        return new Date(value).toLocaleTimeString();
                    },
                    fontSize: 11
                }
            },
            yAxis: {
                type: 'value',
                axisLabel: {
                    fontSize: 11
                }
            },
            dataZoom: [
                {
                    type: 'inside',
                    start: 0,
                    end: 100,
                    minSpan: 10
                },
                {
                    show: true,
                    start: 0,
                    end: 100,
                    minSpan: 10,
                    bottom: 10,
                    height: 25,
                    handleIcon: 'M10.7,11.9v-1.3H9.3v1.3c-4.9,0.3-8.8,4.4-8.8,9.4c0,5,3.9,9.1,8.8,9.4v1.3h1.3v-1.3c4.9-0.3,8.8-4.4,8.8-9.4C19.5,16.3,15.6,12.2,10.7,11.9z M13.3,24.4H6.7V23.1h6.6V24.4z M13.3,19.6H6.7v-1.4h6.6V19.6z',
                    handleSize: '80%',
                    handleStyle: {
                        color: '#fff',
                        shadowBlur: 3,
                        shadowColor: 'rgba(0, 0, 0, 0.6)',
                        shadowOffsetX: 2,
                        shadowOffsetY: 2
                    }
                }
            ],
            series: series
        };

        this.chart.setOption(option);
    }

    updateTable() {
        console.log('更新表格，displayData length:', this.displayData.length);
        console.log('selectedPoints:', Array.from(this.selectedPoints));
        
        const tableSection = this.shadowRoot.querySelector('.table-section');
        const table = this.shadowRoot.getElementById('dataTable');
        const tbody = this.shadowRoot.getElementById('tableBody');
        
        // 确保表格区域始终显示
        if (tableSection) {
            tableSection.style.display = 'flex';
        }
        
        // 更新表格头部
        if (!table) {
            console.error('找不到表格元素');
            return;
        }
        
        const headerRow = table.querySelector('thead tr');
        if (!headerRow) {
            console.error('找不到表格头部');
            return;
        }
        
        headerRow.innerHTML = '<th>时间</th>';
        
        const selectedPointsArray = Array.from(this.selectedPoints);
        selectedPointsArray.forEach(point => {
            const th = document.createElement('th');
            th.textContent = point;
            headerRow.appendChild(th);
        });
        
        console.log('表格头部更新完成，列数:', headerRow.children.length);

        // 更新表格数据
        if (!tbody) {
            console.error('找不到表格体');
            return;
        }
        
        tbody.innerHTML = '';
        
        if (!this.displayData.length || this.selectedPoints.size === 0) {
            console.log('没有显示数据或没有选中的测点，显示空状态提示');
            const tr = document.createElement('tr');
            const td = document.createElement('td');
            td.colSpan = Math.max(1, selectedPointsArray.length + 1);
            td.style.textAlign = 'center';
            td.style.color = '#999';
            td.style.padding = '60px 20px';
            td.style.fontSize = '14px';
            td.textContent = this.selectedPoints.size === 0 ? '请选择测点' : '暂无数据';
            tr.appendChild(td);
            tbody.appendChild(tr);
            
            // 更新分页信息为空状态
            this.totalPages = 0;
            this.currentPage = 1; // 重置当前页
            this.updatePagination();
            return;
        }

        // 计算分页
        this.totalPages = Math.ceil(this.displayData.length / this.pageSize);
        this.currentPage = Math.min(this.currentPage, this.totalPages);
        
        console.log('分页信息：当前页', this.currentPage, '总页数', this.totalPages);
        
        const startIndex = (this.currentPage - 1) * this.pageSize;
        const endIndex = Math.min(startIndex + this.pageSize, this.displayData.length);
        const pageData = this.displayData.slice(startIndex, endIndex);
        
        console.log('当前页数据范围:', startIndex, '-', endIndex, '实际数据量:', pageData.length);
        
        pageData.forEach((record, index) => {
            const tr = document.createElement('tr');
            
            // 时间列
            const timeTd = document.createElement('td');
            timeTd.textContent = new Date(record.timestamp).toLocaleString();
            tr.appendChild(timeTd);
            
            // 测点数据列
            selectedPointsArray.forEach(point => {
                const td = document.createElement('td');
                const value = record.values[point] || 0;
                td.textContent = value.toFixed(2);
                tr.appendChild(td);
            });
            
            tbody.appendChild(tr);
        });
        
        console.log('表格数据更新完成，行数:', tbody.children.length);

        // 更新分页信息
        this.updatePagination();
    }

    updatePagination() {
        const pageInfo = this.shadowRoot.getElementById('pageInfo');
        const prevBtn = this.shadowRoot.getElementById('prevBtn');
        const nextBtn = this.shadowRoot.getElementById('nextBtn');
        
        if (pageInfo) {
            if (this.totalPages === 0) {
                pageInfo.textContent = '暂无数据';
            } else {
                pageInfo.textContent = `第 ${this.currentPage} 页 / 共 ${this.totalPages} 页`;
            }
        }
        
        if (prevBtn) {
            prevBtn.disabled = this.totalPages === 0 || this.currentPage <= 1;
        }
        
        if (nextBtn) {
            nextBtn.disabled = this.totalPages === 0 || this.currentPage >= this.totalPages;
        }
    }

    getColorForIndex(index) {
        const colors = [
            '#3370ff', '#00b42a', '#ff7d00', '#f53f3f', '#722ed1',
            '#13c2c2', '#eb2f96', '#faad14', '#a0d911', '#f5222d'
        ];
        return colors[index % colors.length];
    }

    showError(message) {
        const chartContainer = this.shadowRoot.getElementById('chartContainer');
        if (chartContainer) {
            chartContainer.innerHTML = `
                <div style="text-align: center; color: #f53f3f; padding: 40px;">
                    <div style="font-size: 16px; margin-bottom: 8px;">❌ 加载失败</div>
                    <div style="font-size: 14px;">${message}</div>
                </div>
            `;
        }
    }
}

// 注册自定义元素
customElements.define('data-visualization', DataVisualization);
