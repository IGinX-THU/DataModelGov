/**
 * 数据可视化组件 - 纯JavaScript逻辑
 * 支持多测点对比、降采样、分页表格等功能
 */
class DataVisualization extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });
        this.chart = null;
        this.selectedPoints = new Set();
        this.allData = [];
        this.displayData = [];
        this.currentPage = 1;
        this.pageSize = 20;
        this.totalPages = 0;
        this.dataSource = '';
        this.availablePoints = [];
    }

    async connectedCallback() {
        await this.loadResources();
        setTimeout(() => {
            this.bindEvents();
            this.setupSelectedPointsWatcher();
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

        if (window.location.protocol === 'file:') {
            this.shadowRoot.innerHTML += this.getFallbackHTML();
        } else {

            // 加载HTML
            try {
                const response = await fetch('./components/data-visualization/data-visualization.html');
                const html = await response.text();
                this.shadowRoot.innerHTML += html;
            } catch (error) {
                console.error('Failed to load HTML:', error);
                // 如果加载失败，使用内嵌HTML作为后备
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
                <h3 class="visualization-title" id="dataSourceName">时序数据查询</h3>
                <button class="close-btn" id="closeBtn">×</button>
            </div>
            
            <div class="content-area">
                <div class="chart-section">
                    <div class="chart-header">
                        <h4 class="chart-title">趋势图</h4>
                    </div>
                    <div class="chart-container" id="chartContainer">
                        <!-- ECharts图表将在这里渲染 -->
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
        </div>`;
    }

    getBeijingTime() {
        const now = new Date();
        const beijingTime = new Date(now.getTime() + (8 * 60 * 60 * 1000));
        const year = beijingTime.getUTCFullYear();
        const month = String(beijingTime.getUTCMonth() + 1).padStart(2, '0');
        const day = String(beijingTime.getUTCDate()).padStart(2, '0');
        const hours = String(beijingTime.getUTCHours()).padStart(2, '0');
        const minutes = String(beijingTime.getUTCMinutes()).padStart(2, '0');
        const seconds = String(beijingTime.getUTCSeconds()).padStart(2, '0');
        return `${year}-${month}-${day}T${hours}:${minutes}:${seconds}`;
    }

    async setDefaultTimeRange() {
        const startTimeElement = this.shadowRoot.getElementById('startTime');
        const endTimeElement = this.shadowRoot.getElementById('endTime');
        
        // 从选中的测点中提取父级路径作为tableName
        let tableName = null;
        if (this.selectedPoints && this.selectedPoints.size > 0) {
            const firstPoint = Array.from(this.selectedPoints)[0];
            const pathParts = firstPoint.split('.');
            // 去掉最后一级（测点名称），保留父级路径
            tableName = pathParts.slice(0, -1).join('.');
        }
        
        if (!tableName) {
            console.warn('无法从测点提取tableName，使用默认时间');
            this.setFallbackTimeRange(startTimeElement, endTimeElement);
            return;
        }

        try {
            // 调用接口获取数据源的时间范围
            const result = await window.AppConfig.post('task', 'time-range', {
                tableName: tableName,
                inputsBind: []
            });
            
            console.log('时间范围查询结果:', result);
            
            if (result.success && result.data) {
                const timeRange = result.data;
                
                if (timeRange.minKey && timeRange.maxKey) {
                    const startDate = new Date(timeRange.minKey);
                    const endDate = new Date(timeRange.maxKey);
                    const startTime = `${startDate.getFullYear()}-${String(startDate.getMonth() + 1).padStart(2, '0')}-${String(startDate.getDate()).padStart(2, '0')}T${String(startDate.getHours()).padStart(2, '0')}:${String(startDate.getMinutes()).padStart(2, '0')}:${String(startDate.getSeconds()).padStart(2, '0')}`;
                    const endTime = `${endDate.getFullYear()}-${String(endDate.getMonth() + 1).padStart(2, '0')}-${String(endDate.getDate()).padStart(2, '0')}T${String(endDate.getHours()).padStart(2, '0')}:${String(endDate.getMinutes()).padStart(2, '0')}:${String(endDate.getSeconds()).padStart(2, '0')}`;
                    
                    if (startTimeElement) {
                        startTimeElement.value = startTime;
                        console.log('设置开始时间:', startTime);
                    }
                    
                    if (endTimeElement) {
                        endTimeElement.value = endTime;
                        console.log('设置结束时间:', endTime);
                    }
                } else {
                    console.warn('时间范围为空，使用默认值');
                    this.setFallbackTimeRange(startTimeElement, endTimeElement);
                }
            } else {
                console.warn('获取时间范围失败:', result.message);
                this.setFallbackTimeRange(startTimeElement, endTimeElement);
            }
        } catch (error) {
            console.error('获取时间范围异常:', error);
            this.setFallbackTimeRange(startTimeElement, endTimeElement);
        }
    }

    setFallbackTimeRange(startTimeElement, endTimeElement) {
        if (startTimeElement) {
            // 开始时间设置为24小时前
            const now = new Date();
            const beijingTime = new Date(now.getTime() + (8 * 60 * 60 * 1000));
            const dayAgo = new Date(beijingTime.getTime() - (24 * 60 * 60 * 1000));
            const year = dayAgo.getUTCFullYear();
            const month = String(dayAgo.getUTCMonth() + 1).padStart(2, '0');
            const day = String(dayAgo.getUTCDate()).padStart(2, '0');
            const hours = String(dayAgo.getUTCHours()).padStart(2, '0');
            const minutes = String(dayAgo.getUTCMinutes()).padStart(2, '0');
            const seconds = String(dayAgo.getUTCSeconds()).padStart(2, '0');
            startTimeElement.value = `${year}-${month}-${day}T${hours}:${minutes}:${seconds}`;
        }
        
        if (endTimeElement) {
            // 结束时间设置为当前北京时间
            endTimeElement.value = this.getBeijingTime();
        }
    }

    show(dataSource, points = [], tableData = null, keepQueryConditions = false) {
        console.log('显示数据可视化:', dataSource, points, tableData, '保持查询条件:', keepQueryConditions);
        this.setAttribute('show', '');
        this.dataSource = dataSource;
        this.availablePoints = points;
        
        // 检查是否新增了测点
        this._oldSize = this.selectedPoints ? this.selectedPoints.size : 0;
        this._wasShowingInappropriate = this.isShowingInappropriateState();
        
        // 直接使用传入的测点，不累积添加
        // 点击哪个就展示哪个，而不是累积多个测点
        this.selectedPoints = new Set(points);

        // 设置数据源名称
        const dataSourceNameEl = this.shadowRoot.getElementById('dataSourceName');
        if (dataSourceNameEl) {
            dataSourceNameEl.textContent = '时序数据查询';
        }

        // 如果不保持查询条件，自动设置默认时间
        if (!keepQueryConditions) {
            this.setDefaultTimeRange();
        }

        console.log('组件已显示，开始初始化...');

        // 强制重新计算布局
        setTimeout(() => {
            // 更新已选测点列表
            this.updateSelectedPointsList();

            // 不设置默认时间范围，让用户手动选择
            console.log('🔍 不设置默认时间范围，等待用户手动选择');

            // 如果有传入的数据，处理它
            if (tableData) {
                console.log('处理传入的表格数据:', tableData);
                this.processTableData(tableData);
            } else {
                // 否则调用loadData获取数据
                this.loadData();
            }

            // 绑定查询控件事件
            this.bindQueryEvents();

            // 强制触发重新布局
            this.updateLayout();
        }, 50);
    }

    // 格式化本地时间为 datetime-local 输入框所需的格式 (YYYY-MM-DDTHH:mm)
    formatLocalDateTime(date) {
        const year = date.getFullYear();
        const month = String(date.getMonth() + 1).padStart(2, '0');
        const day = String(date.getDate()).padStart(2, '0');
        const hours = String(date.getHours()).padStart(2, '0');
        const minutes = String(date.getMinutes()).padStart(2, '0');
        return `${year}-${month}-${day}T${hours}:${minutes}`;
    }

    isValidTimestamp(timestamp) {
        if (timestamp == null || isNaN(timestamp)) {
            return false;
        }
        
        const numValue = Number(timestamp);
        
        // 检查是否是时间戳格式：
        // 毫秒级时间戳：13位数字（如 1704067200000）
        // 秒级时间戳：10位数字（如 1704067200）
        const timestampStr = String(Math.floor(Math.abs(numValue)));
        const isValidLength = timestampStr.length === 13 || timestampStr.length === 10;
        
        if (!isValidLength) {
            return false;
        }
        
        const date = new Date(numValue);
        if (isNaN(date.getTime())) {
            return false;
        }
        
        const year = date.getFullYear();
        return year >= 1970 && year <= 2100;
    }

    
    // 处理表格数据
    processTableData(tableData) {
        console.log('处理表格数据:', tableData);

        if (!tableData || !tableData.header || !tableData.records) {
            console.error('无效的表格数据格式');
            this.showEmptyState();
            return;
        }

        // 重置分页状态
        this.currentPage = 1;
        this.pageSize = 20;

        // 设置表头（每次接口调用都要更新）
        this.updateTableHeader(tableData.header);

        // 保存实际的数据列（用于表格显示）
        this.actualDataColumns = tableData.header.filter(col => col !== 'key');

        // 保存表头信息（用于时间列检测）
        this.tableHeader = tableData.header;

        // 处理数据记录
        this.allData = tableData.records.map(record => {
            const processedRecord = { ...record };

            // 如果有key列，尝试转换为时间戳
            if (record.key) {
                try {
                    const parsedTimestamp = new Date(record.key).getTime();
                    // 检查是否是有效时间戳
                    if (this.isValidTimestamp(parsedTimestamp)) {
                        processedRecord.timestamp = parsedTimestamp;
                    } else {
                        // 不是有效时间戳，保留原始值
                        processedRecord.timestamp = record.key;
                    }
                } catch (error) {
                    // 解析异常，保留原始值
                    processedRecord.timestamp = record.key;
                }
            }

            return processedRecord;
        });

        console.log('处理后的数据:', this.allData.length, '条记录');

        // 应用降采样
        this.applyDownsampling();

        // 更新表格
        this.updateTable();

        // 检查是否需要重新更新可视化（新增测点的情况）
        console.log('检查新增测点条件:', {
            wasShowingInappropriate: this._wasShowingInappropriate,
            oldSize: this._oldSize,
            currentSize: this.selectedPoints.size,
            hasData: this.allData.length > 0,
            shouldTrigger: this._wasShowingInappropriate && this._oldSize < this.selectedPoints.size && this.allData.length > 0
        });
        
        // 初始化图表
        if (!this.chart) {
            this.initChart();
        }
        
        // 如果是新增测点的情况，强制重新检查图表显示条件
        if (this._wasShowingInappropriate && this._oldSize < this.selectedPoints.size && this.allData.length > 0) {
            console.log('检测到新增测点且有数据，重新更新可视化');
            // 强制重新检查图表显示条件
            this.updateChart();
        } else {
            // 正常更新可视化
            this.updateVisualization();
        }

        // 更新已选测点列表
        this.updateSelectedPointsList();

        // 绑定查询控件事件（确保按钮可以点击）
        // 注意：不要在这里重复绑定，已经在show()中绑定了
        // this.bindQueryEvents();
    }

    // 更新表头
    updateTableHeader(header) {
        const table = this.shadowRoot.getElementById('dataTable');
        const tableHead = table ? table.querySelector('thead tr') : null;
        if (tableHead) {
            // 清空现有表头
            tableHead.innerHTML = '';

            // 添加所有列头，包括key列
            header.forEach(columnName => {
                const th = document.createElement('th');
                th.textContent = columnName;
                tableHead.appendChild(th);
            });
        }

        // 更新X轴和Y轴下拉框
        this.updateAxisDropdowns(header);
    }

    // 更新X轴和Y轴下拉框
    updateAxisDropdowns(header) {
        const xAxisSelect = this.shadowRoot.getElementById('xAxisSelect');
        const yAxisSelect = this.shadowRoot.getElementById('yAxisSelect');

        if (xAxisSelect) {
            // 保存当前选中的值
            const currentXValue = xAxisSelect.value;
            
            // 清空选项
            xAxisSelect.innerHTML = '<option value="">自动选择</option>';
            
            // 添加列选项
            header.forEach(columnName => {
                const option = document.createElement('option');
                option.value = columnName;
                option.textContent = columnName;
                xAxisSelect.appendChild(option);
            });

            // 恢复选中的值
            if (currentXValue && header.includes(currentXValue)) {
                xAxisSelect.value = currentXValue;
            }
        }

        if (yAxisSelect) {
            // 保存当前选中的值
            const currentYValue = yAxisSelect.value;
            
            // 清空选项
            yAxisSelect.innerHTML = '<option value="">自动选择</option>';
            
            // 添加列选项（排除时间列）
            header.forEach(columnName => {
                // 跳过key列（通常是时间列）
                if (columnName.toLowerCase() !== 'key' && columnName.toLowerCase() !== '时间') {
                    const option = document.createElement('option');
                    option.value = columnName;
                    option.textContent = columnName;
                    yAxisSelect.appendChild(option);
                }
            });

            // 恢复选中的值
            if (currentYValue && header.includes(currentYValue)) {
                yAxisSelect.value = currentYValue;
            }
        }
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
        // 强制重新计算尺寸
        const chartContainer = this.shadowRoot.getElementById('chartContainer');
        if (chartContainer) {
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

    bindEvents() {
        // 关闭按钮
        const closeBtn = this.shadowRoot.getElementById('closeBtn');
        if (closeBtn) {
            closeBtn.addEventListener('click', () => {
                this.hide();
            });
        }

        // 图表类型选择
        const chartTypeSelect = this.shadowRoot.getElementById('chartType');
        if (chartTypeSelect) {
            chartTypeSelect.addEventListener('change', () => {
                this.updateVisualization();
            });
        }

        // X轴选择
        const xAxisSelect = this.shadowRoot.getElementById('xAxisSelect');
        if (xAxisSelect) {
            xAxisSelect.addEventListener('change', () => {
                this.updateVisualization();
            });
        }

        // Y轴选择
        const yAxisSelect = this.shadowRoot.getElementById('yAxisSelect');
        if (yAxisSelect) {
            yAxisSelect.addEventListener('change', () => {
                this.updateVisualization();
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
                // 使用全局showComponent函数
                if (typeof window.showComponent === 'function') {
                    window.showComponent('importData');
                } else {
                    console.error('window.showComponent函数未找到');
                }
            });
        }

        // 导出数据按钮
        const exportBtn = this.shadowRoot.getElementById('exportBtn');
        if (exportBtn) {
            exportBtn.addEventListener('click', () => {
                this.exportData();
            });
        }

        // 添加测点按钮
        const addPointBtn = this.shadowRoot.getElementById('addPointBtn');
        if (addPointBtn) {
            addPointBtn.addEventListener('click', () => {
                this.showAddPointModal();
            });
        }

        // 分页按钮事件绑定
        const prevBtn = this.shadowRoot.getElementById('prevBtn');
        if (prevBtn) {
            prevBtn.addEventListener('click', () => {
                if (this.currentPage > 1) {
                    this.currentPage--;
                    this.updateTable();
                }
            });
        }

        const nextBtn = this.shadowRoot.getElementById('nextBtn');
        if (nextBtn) {
            nextBtn.addEventListener('click', () => {
                if (this.currentPage < this.totalPages) {
                    this.currentPage++;
                    this.updateTable();
                }
            });
        }

        // 每页显示选择框事件绑定
        const pageSizeSelect = this.shadowRoot.getElementById('pageSizeSelect');
        if (pageSizeSelect) {
            pageSizeSelect.addEventListener('change', (e) => {
                this.pageSize = parseInt(e.target.value);
                this.currentPage = 1; // 重置到第一页
                this.updateTable();
            });
        }

        // 分页组件
        const pagination = this.shadowRoot.getElementById('tablePagination');
        if (pagination) {
            pagination.addEventListener('pagination-change', (e) => {
                this.currentPage = e.detail.currentPage;
                this.pageSize = e.detail.pageSize;
                this.updateTable();
            });
        }

        // ESC键关闭
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape' && this.hasAttribute('show')) {
                this.hide();
            }
        });
    }

    bindQueryEvents() {
        console.log('绑定查询控件事件...');

        // 先移除可能存在的旧事件监听器
        const queryBtn = this.shadowRoot.getElementById('queryBtn');
        if (queryBtn) {
            // 克隆按钮来移除所有事件监听器
            const newQueryBtn = queryBtn.cloneNode(true);
            queryBtn.parentNode.replaceChild(newQueryBtn, queryBtn);
        }

        // 绑定快速时间按钮
        const quickTimeBtns = this.shadowRoot.querySelectorAll('.quick-time-btn');
        console.log('找到快速时间按钮:', quickTimeBtns.length);
        quickTimeBtns.forEach(btn => {
            // 克隆按钮来移除所有事件监听器
            const newBtn = btn.cloneNode(true);
            btn.parentNode.replaceChild(newBtn, btn);
            btn = newBtn;

            btn.addEventListener('click', () => {
                console.log('快速时间按钮被点击:', btn.dataset.range);
                // 重新获取所有按钮并移除active状态
                const allBtns = this.shadowRoot.querySelectorAll('.quick-time-btn');
                allBtns.forEach(b => b.classList.remove('active'));
                btn.classList.add('active');

                const range = btn.dataset.range;
                const endTime = new Date();
                const startTime = new Date();

                switch (range) {
                    case '1h':
                        startTime.setHours(startTime.getHours() - 1);
                        break;
                    case '6h':
                        startTime.setHours(startTime.getHours() - 6);
                        break;
                    case '24h':
                        startTime.setDate(startTime.getDate() - 1);
                        break;
                    case '7d':
                        startTime.setDate(startTime.getDate() - 7);
                        break;
                }

                const startTimeInput = this.shadowRoot.getElementById('startTime');
                const endTimeInput = this.shadowRoot.getElementById('endTime');

                if (startTimeInput) {
                    startTimeInput.value = this.formatLocalDateTime(startTime);
                }
                if (endTimeInput) {
                    endTimeInput.value = this.formatLocalDateTime(endTime);
                }
            });
        });

        // 绑定查询按钮
        const queryBtnNew = this.shadowRoot.getElementById('queryBtn');
        console.log('找到查询按钮:', queryBtnNew);
        if (queryBtnNew) {
            queryBtnNew.addEventListener('click', () => {
                console.log('查询按钮被点击');
                this.loadData();
            });
        }

        // 绑定重置按钮
        const resetBtn = this.shadowRoot.getElementById('resetBtn');
        console.log('找到重置按钮:', resetBtn);
        if (resetBtn) {
            resetBtn.addEventListener('click', () => {
                console.log('重置按钮被点击');
                this.resetQueryForm();
            });
        }
    }

    // 重置查询表单
    resetQueryForm() {
        console.log('重置查询表单');

        // 清空时间输入框
        const startTimeInput = this.shadowRoot.getElementById('startTime');
        const endTimeInput = this.shadowRoot.getElementById('endTime');

        if (startTimeInput) {
            startTimeInput.value = '';
        }
        if (endTimeInput) {
            endTimeInput.value = '';
        }

        // 重置聚合函数为原始数据
        const aggregationSelect = this.shadowRoot.getElementById('aggregationFunction');
        if (aggregationSelect) {
            aggregationSelect.value = '';
        }

        // 重置时间间隔为空
        const precisionInput = this.shadowRoot.getElementById('precision');
        if (precisionInput) {
            precisionInput.value = '';
        }

        // 重置时间单位为毫秒
        const timePrecisionSelect = this.shadowRoot.getElementById('timePrecision');
        if (timePrecisionSelect) {
            timePrecisionSelect.value = '7'; // 默认毫秒
        }

        // 清除快速选择按钮的选中状态
        const quickTimeBtns = this.shadowRoot.querySelectorAll('.quick-time-btn');
        quickTimeBtns.forEach(btn => {
            btn.classList.remove('active');
        });

        // 不重新设置默认时间，保持清空状态
        // 不自动加载数据，让用户手动点击查询
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
        console.log('移除测点:', point);
        this.selectedPoints.delete(point);

        // 更新全局选中的测点
        if (window.selectedDataPoints) {
            window.selectedDataPoints.delete(point);
        }

        // 更新显示
        this.updateSelectedPointsList();

        // 如果没有选中的测点了，显示空状态
        if (this.selectedPoints.size === 0) {
            console.log('没有选中的测点了，显示空状态');
            this.showEmptyState();
        } else {
            // 重置图表渲染标记，确保重新检查显示条件
            this._chartRendered = false;
            console.log('🔄 重置图表渲染标记为 false');
            
            // 清空现有图表，避免显示已删除测点的数据
            if (this.chart) {
                this.chart.clear();
                console.log('🧹 清空现有图表');
            }
            
            // 调用接口重新查询数据，确保表头和数据都是最新的
            // 添加小延迟确保UI更新完成
            setTimeout(() => {
                this.loadData();
            }, 50);
        }
    }

    setupSelectedPointsWatcher() {
        // 监听全局selectedDataPoints的变化
        if (!window.selectedDataPoints) {
            window.selectedDataPoints = new Set();
        }
        
        // 保存原始的add方法
        const originalAdd = window.selectedDataPoints.add;
        let isUpdating = false;
        
        // 重写add方法以监听变化
        window.selectedDataPoints.add = function(value) {
            const result = originalAdd.call(this, value);
            
            // 避免循环更新
            if (!isUpdating) {
                isUpdating = true;
                
                // 通知组件更新
                setTimeout(() => {
                    const dataViz = document.querySelector('data-visualization');
                    if (dataViz && dataViz.selectedPoints) {
                        const oldSize = dataViz.selectedPoints.size;
                        const wasShowingInappropriate = dataViz.isShowingInappropriateState();
                        
                        // 同步选中的测点
                        dataViz.selectedPoints = new Set(window.selectedDataPoints);
                        dataViz.updateSelectedPointsList();
                        
                        // 如果之前显示"数据不适合图表显示"且现在有新测点，则重新检查
                        if (wasShowingInappropriate && oldSize < window.selectedDataPoints.size) {
                            console.log('检测到新增测点，重新检查数据是否适合图表展示');
                            // 如果有数据，重新更新可视化；否则重新加载数据
                            if (dataViz.displayData.length > 0) {
                                dataViz.updateVisualization();
                            } else {
                                dataViz.loadData();
                            }
                        }
                    }
                    isUpdating = false;
                }, 50);
            }
            
            return result;
        };
    }

    // 显示覆盖层
    showChartOverlay(content) {
        const overlay = this.shadowRoot.getElementById('chartOverlay');
        if (overlay) {
            overlay.innerHTML = content;
            overlay.style.display = 'flex';
        }
    }

    // 隐藏覆盖层
    hideChartOverlay() {
        const overlay = this.shadowRoot.getElementById('chartOverlay');
        if (overlay) {
            overlay.style.display = 'none';
        }
    }

    // 显示添加测点模态框
    showAddPointModal() {
        // 获取数据源树中的所有测点
        const dataSourceTree = document.getElementById('dataSourceTree');
        if (!dataSourceTree) {
            console.error('数据源树不存在');
            return;
        }

        // 获取当前选中的测点
        const currentPoints = Array.from(this.selectedPoints);
        if (currentPoints.length === 0) {
            alert('当前没有选中的测点');
            return;
        }

        // 获取当前选中测点的父节点路径
        const currentPoint = currentPoints[0];
        const pathParts = currentPoint.split('.');
        const parentPath = pathParts.slice(0, -1).join('.');

        // 获取当前数据源下的所有测点
        const treeNodes = dataSourceTree.querySelectorAll('.tree-node');
        const allSiblingPoints = [];

        treeNodes.forEach(node => {
            const fullPath = node.getAttribute('data-full-path');
            const isLeaf = node.getAttribute('data-is-leaf') === 'true';
            if (fullPath && isLeaf) {
                // 检查是否是当前测点的兄弟节点（同一父节点）
                const nodePathParts = fullPath.split('.');
                const nodeParentPath = nodePathParts.slice(0, -1).join('.');
                if (nodeParentPath === parentPath) {
                    allSiblingPoints.push(fullPath);
                }
            }
        });

        if (allSiblingPoints.length === 0) {
            alert('当前测点没有兄弟测点');
            return;
        }

        // 创建模态框
        const modal = document.createElement('div');
        modal.className = 'modal-overlay';
        modal.innerHTML = `
            <div class="modal">
                <div class="modal-header">
                    <h3 class="modal-title">选择测点</h3>
                    <button class="modal-close" id="closeModal">×</button>
                </div>
                <div class="modal-body">
                    <div class="point-selector">
                        <label class="query-label">选择测点 (${parentPath}):</label>
                        <div class="select-all-container" style="padding: 8px 0; border-bottom: 1px solid #e8e8e8; margin-bottom: 8px;">
                            <label class="checkbox-item" style="display: flex; align-items: center; cursor: pointer;">
                                <input type="checkbox" id="selectAllCheckbox" style="margin-right: 8px;">
                                <span>全选</span>
                            </label>
                        </div>
                        <div class="checkbox-list" id="checkboxList" style="max-height: 300px; overflow-y: auto; border: 1px solid #d9d9d9; border-radius: 4px; padding: 12px;">
                            ${allSiblingPoints.map(point => `
                                <label class="checkbox-item" style="display: flex; align-items: center; padding: 8px 0; cursor: pointer;">
                                    <input type="checkbox" value="${point}" class="point-checkbox" ${this.selectedPoints.has(point) ? 'checked' : ''} style="margin-right: 8px;">
                                    <span>${point}</span>
                                </label>
                            `).join('')}
                        </div>
                    </div>
                </div>
                <div class="modal-footer">
                    <button class="modal-btn" id="cancelBtn">取消</button>
                    <button class="modal-btn primary" id="confirmBtn">确定</button>
                </div>
            </div>
        `;

        document.body.appendChild(modal);

        // 绑定事件
        const closeModal = modal.querySelector('#closeModal');
        const cancelBtn = modal.querySelector('#cancelBtn');
        const confirmBtn = modal.querySelector('#confirmBtn');
        const checkboxList = modal.querySelector('#checkboxList');
        const selectAllCheckbox = modal.querySelector('#selectAllCheckbox');
        const pointCheckboxes = modal.querySelectorAll('.point-checkbox');

        const closeModalHandler = () => {
            document.body.removeChild(modal);
        };

        closeModal.addEventListener('click', closeModalHandler);
        cancelBtn.addEventListener('click', closeModalHandler);

        // 全选功能
        selectAllCheckbox.addEventListener('change', (e) => {
            const isChecked = e.target.checked;
            pointCheckboxes.forEach(checkbox => {
                checkbox.checked = isChecked;
            });
        });

        // 当单个复选框变化时，更新全选复选框状态
        pointCheckboxes.forEach(checkbox => {
            checkbox.addEventListener('change', () => {
                const allChecked = Array.from(pointCheckboxes).every(cb => cb.checked);
                selectAllCheckbox.checked = allChecked;
            });
        });

        confirmBtn.addEventListener('click', () => {
            // 获取所有选中的复选框
            const checkedBoxes = checkboxList.querySelectorAll('input[type="checkbox"]:checked');
            const selectedPoints = Array.from(checkedBoxes).map(checkbox => checkbox.value);

            if (selectedPoints.length === 0) {
                alert('请至少选择一个测点');
                return;
            }

            // 更新选中的测点
            this.selectedPoints = new Set(selectedPoints);
            
            // 更新全局选中的测点
            if (window.selectedDataPoints) {
                window.selectedDataPoints.clear();
                selectedPoints.forEach(point => window.selectedDataPoints.add(point));
            }

            // 更新显示
            this.updateSelectedPointsList();
            
            // 重新加载数据
            this.loadData();
            
            closeModalHandler();
        });

        // 点击模态框外部关闭
        modal.addEventListener('click', (e) => {
            if (e.target === modal) {
                closeModalHandler();
            }
        });
    }

    // 检查是否正在显示"数据不适合图表展示"状态
    isShowingInappropriateState() {
        const overlay = this.shadowRoot.getElementById('chartOverlay');
        if (!overlay) return false;
        
        const innerHTML = overlay.innerHTML;
        return innerHTML.includes('数据不适合图表显示') || innerHTML.includes('测点数据为非数值类型');
    }

    // 重新计算显示数据，不调用接口
    recalculateDisplayData() {
        if (this.allData.length === 0) {
            return;
        }

        // 重新应用降采样和更新显示
        this.applyDownsampling();

        // 更新表格（包括表头）
        this.updateTable();

        // 更新图表
        if (this.chart) {
            this.updateVisualization();
        }
    }

    async loadData() {
        try {
            console.log('开始加载数据，选中的测点:', Array.from(this.selectedPoints));
            console.log('selectedPoints size:', this.selectedPoints.size);

            // 显示全局loading
            if (window.showGlobalLoading) {
                window.showGlobalLoading('正在查询数据...');
            }

            if (this.selectedPoints.size === 0) {
                console.log('没有选中的测点，显示空状态');
                if (window.hideGlobalLoading) {
                    window.hideGlobalLoading();
                }
                this.showEmptyState();
                return;
            }

            // 获取查询参数
            const startTimeInput = this.shadowRoot.getElementById('startTime');
            const endTimeInput = this.shadowRoot.getElementById('endTime');
            const aggregationSelect = this.shadowRoot.getElementById('aggregationFunction');
            const precisionInput = this.shadowRoot.getElementById('precision');
            const timePrecisionSelect = this.shadowRoot.getElementById('timePrecision');

            let startTime = null;
            let endTime = null;
            let aggregateType = null;
            let precision = null; // 不设置默认值，让后端处理
            let timePrecision = 7; // 默认毫秒

            // 处理时间参数
            if (startTimeInput && startTimeInput.value) {
                startTime = new Date(startTimeInput.value).getTime();
            }
            if (endTimeInput && endTimeInput.value) {
                endTime = new Date(endTimeInput.value).getTime();
            }

            // 如果没有设置时间，但有快速选择的时间，使用快速选择的时间
            if (startTime === null && endTime === null) {
                // 检查是否有快速选择按钮被选中
                const activeQuickBtn = this.shadowRoot.querySelector('.quick-time-btn.active');
                if (activeQuickBtn) {
                    const range = activeQuickBtn.dataset.range;
                    let endTime = new Date();
                    let startTime = new Date();

                    switch (range) {
                        case '1h':
                            startTime.setHours(startTime.getHours() - 1);
                            break;
                        case '6h':
                            startTime.setHours(startTime.getHours() - 6);
                            break;
                        case '24h':
                            startTime.setHours(startTime.getHours() - 24);
                            break;
                        case '7d':
                            startTime.setDate(startTime.getDate() - 7);
                            break;
                    }

                    startTime = startTime.getTime();
                    endTime = endTime.getTime();
                }
            }

            // 处理聚合函数参数
            if (aggregationSelect && aggregationSelect.value) {
                aggregateType = parseInt(aggregationSelect.value);
            }

            // 处理时间间隔参数
            if (precisionInput && precisionInput.value) {
                precision = parseInt(precisionInput.value);
            }

            // 处理时间单位参数
            if (timePrecisionSelect && timePrecisionSelect.value) {
                timePrecision = parseInt(timePrecisionSelect.value);
            }

            console.log('查询参数:', { startTime, endTime, aggregateType, precision, timePrecision });

            // 构建请求体
            const requestBody = {
                paths: Array.from(this.selectedPoints),
                startTime: startTime,
                endTime: endTime,
                aggregateType: aggregateType,
                timePrecision: timePrecision
            };

            // 只有当precision不为null时才添加precision参数
            if (precision !== null) {
                requestBody.precision = precision;
            }

            // 调用数据查询接口
            const result = await window.AppConfig.post('data', 'query', requestBody);
            
            if (result.success && result.data) {
                console.log('数据查询成功:', result.data);
                
                // 处理查询结果
                this.processTableData(result.data);
            } else if (result.success && (!result.data || !result.data.records || result.data.records.length === 0)) {
                // 接口成功但没有数据
                console.log('查询成功但没有数据');
                this.showEmptyState();
            } else {
                // 接口返回错误
                console.error('数据查询失败:', result.message);
                this.showError('数据查询失败: ' + (result.message || '未知错误'));
            }

        } catch (error) {
            console.error('加载数据失败:', error);
            this.showError('网络错误，无法查询数据');
        } finally {
            // 无论成功还是失败，都隐藏全局loading
            if (window.hideGlobalLoading) {
                window.hideGlobalLoading();
            }
        }
    }

    async exportData() {
        try {
            console.log('开始导出数据，选中的测点:', Array.from(this.selectedPoints));

            if (this.selectedPoints.size === 0) {
                this.showMessage('请先选择测点后再导出数据', 'warning');
                return;
            }

            // 显示全局loading
            if (window.showGlobalLoading) {
                window.showGlobalLoading('正在导出数据...');
            }

            // 获取与查询相同的参数
            const startTimeInput = this.shadowRoot.getElementById('startTime');
            const endTimeInput = this.shadowRoot.getElementById('endTime');
            const aggregationSelect = this.shadowRoot.getElementById('aggregationFunction');
            const precisionInput = this.shadowRoot.getElementById('precision');
            const timePrecisionSelect = this.shadowRoot.getElementById('timePrecision');

            let startTime = null;
            let endTime = null;
            let aggregateType = null;
            let precision = null;
            let timePrecision = 7;

            // 处理时间参数（与loadData方法相同的逻辑）
            if (startTimeInput && startTimeInput.value) {
                startTime = new Date(startTimeInput.value).getTime();
            }
            if (endTimeInput && endTimeInput.value) {
                endTime = new Date(endTimeInput.value).getTime();
            }

            // 如果没有设置时间，但有快速选择的时间，使用快速选择的时间
            if (startTime === null && endTime === null) {
                const activeQuickBtn = this.shadowRoot.querySelector('.quick-time-btn.active');
                if (activeQuickBtn) {
                    const range = activeQuickBtn.dataset.range;
                    let endTime = new Date();
                    let startTime = new Date();

                    switch (range) {
                        case '1h':
                            startTime.setHours(startTime.getHours() - 1);
                            break;
                        case '6h':
                            startTime.setHours(startTime.getHours() - 6);
                            break;
                        case '24h':
                            startTime.setHours(startTime.getHours() - 24);
                            break;
                        case '7d':
                            startTime.setDate(startTime.getDate() - 7);
                            break;
                    }

                    startTime = startTime.getTime();
                    endTime = endTime.getTime();
                }
            }

            // 处理聚合函数参数
            if (aggregationSelect && aggregationSelect.value) {
                aggregateType = parseInt(aggregationSelect.value);
            }

            // 处理时间间隔参数
            if (precisionInput && precisionInput.value) {
                precision = parseInt(precisionInput.value);
            }

            // 处理时间单位参数
            if (timePrecisionSelect && timePrecisionSelect.value) {
                timePrecision = parseInt(timePrecisionSelect.value);
            }

            console.log('导出参数:', { startTime, endTime, aggregateType, precision, timePrecision });

            // 构建请求体（与loadData方法相同的结构）
            const requestBody = {
                paths: Array.from(this.selectedPoints),
                startTime: startTime,
                endTime: endTime,
                aggregateType: aggregateType,
                timePrecision: timePrecision
            };

            // 只有当precision不为null时才添加precision参数
            if (precision !== null) {
                requestBody.precision = precision;
            }

            // 调用数据导出接口
            const result = await window.AppConfig.download('data', 'export', requestBody, 'data_export.csv');
            
            if (result.success) {
                this.showMessage('数据导出成功', 'success');
            } else {
                this.showMessage('数据导出失败: ' + (result.message || '未知错误'), 'error');
            }

        } catch (error) {
            console.error('导出数据失败:', error);
            this.showMessage('网络错误，无法导出数据', 'error');
        } finally {
            // 无论成功还是失败，都隐藏全局loading
            if (window.hideGlobalLoading) {
                window.hideGlobalLoading();
            }
        }
    }

    // 显示loading效果
    showLoading() {
        console.log('显示loading效果');

        // 在表格区域显示loading
        const tableSection = this.shadowRoot.querySelector('.table-section');
        if (tableSection) {
            tableSection.style.position = 'relative';

            // 检查是否已存在loading元素
            let loadingEl = tableSection.querySelector('.loading-overlay');
            if (!loadingEl) {
                loadingEl = document.createElement('div');
                loadingEl.className = 'loading-overlay';
                loadingEl.innerHTML = `
                    <div class="loading-spinner">
                        <div class="spinner"></div>
                        <div class="loading-text">正在加载数据...</div>
                    </div>
                `;
                tableSection.appendChild(loadingEl);
            }
        }

        // 禁用查询和重置按钮
        const queryBtn = this.shadowRoot.getElementById('queryBtn');
        const resetBtn = this.shadowRoot.getElementById('resetBtn');
        if (queryBtn) queryBtn.disabled = true;
        if (resetBtn) resetBtn.disabled = true;
    }

    // 隐藏loading效果
    hideLoading() {
        console.log('隐藏loading效果');

        // 移除loading元素
        const tableSection = this.shadowRoot.querySelector('.table-section');
        if (tableSection) {
            const loadingEl = tableSection.querySelector('.loading-overlay');
            if (loadingEl) {
                loadingEl.remove();
            }
        }

        // 启用查询和重置按钮
        const queryBtn = this.shadowRoot.getElementById('queryBtn');
        const resetBtn = this.shadowRoot.getElementById('resetBtn');
        if (queryBtn) queryBtn.disabled = false;
        if (resetBtn) resetBtn.disabled = false;
    }

    showEmptyState() {
        // 不销毁ECharts实例，只显示覆盖层
        const emptyContent = `
            <div style="display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100%; color: #999;">
                <div style="font-size: 48px; margin-bottom: 16px;">📊</div>
                <div style="font-size: 14px; margin-bottom: 8px;">暂无数据</div>
                <div style="font-size: 12px;">请在左侧选择测点后点击查询</div>
            </div>
        `;
        this.showChartOverlay(emptyContent);

        // 确保表格区域显示并更新为空状态
        this.updateTable();
    }

    showError(message) {
        const errorContent = `
            <div style="display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100%; color: #ff4d4f;">
                <div style="font-size: 48px; margin-bottom: 16px;">❌</div>
                <div style="font-size: 14px;">${message}</div>
            </div>
        `;
        this.showChartOverlay(errorContent);
    }

    showMessage(message, type = 'info') {
        // 使用全局的toast提示（如果存在）
        if (window.CommonUtils && window.CommonUtils.showToast) {
            window.CommonUtils.showToast(message, type);
            return;
        }

        console.log('使用降级方案显示toast');
        // 降级方案：在组件内显示临时提示
        const toast = document.createElement('div');
        toast.style.cssText = `
            position: fixed;
            top: 20px;
            right: 20px;
            padding: 12px 20px;
            border-radius: 4px;
            color: white;
            font-size: 14px;
            z-index: 10000;
            transition: opacity 0.3s ease;
            box-shadow: 0 2px 8px rgba(0, 0, 0, 0.15);
        `;

        // 根据类型设置背景色
        switch (type) {
            case 'success':
                toast.style.backgroundColor = '#52c41a';
                break;
            case 'error':
                toast.style.backgroundColor = '#ff4d4f';
                break;
            case 'warning':
                toast.style.backgroundColor = '#faad14';
                break;
            default:
                toast.style.backgroundColor = '#1890ff';
        }

        toast.textContent = message;
        document.body.appendChild(toast);

        // 3秒后自动消失
        setTimeout(() => {
            toast.style.opacity = '0';
            setTimeout(() => {
                if (document.body.contains(toast)) {
                    document.body.removeChild(toast);
                }
            }, 300);
        }, 3000);
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
        if (this.allData.length <= 100) {
            // 如果数据点太少，不进行降采样，但需要插值来显示曲线
            this.displayData = this.interpolateData(this.allData, 100);
            this.hideDownsamplingInfo();
            return;
        }

        if (this.allData.length <= 2000) {
            this.displayData = this.allData;
            this.hideDownsamplingInfo();
            return;
        }

        // 使用LTTB算法进行降采样
        const threshold = 1000; // 目标数据点数
        this.displayData = this.lttbDownsample(this.allData, threshold);
        this.showDownsamplingInfo(this.allData.length, this.displayData.length);
    }

    // 数据插值，用于数据点太少的情况
    interpolateData(data, targetPoints) {
        if (data.length <= 2) return data;

        const interpolated = [];
        const step = (data.length - 1) / (targetPoints - 1);

        for (let i = 0; i < targetPoints; i++) {
            const index = Math.round(i * step);
            if (index < data.length) {
                interpolated.push(data[index]);
            }
        }

        return interpolated;
    }

    lttbDownsample(data, threshold) {
        if (data.length <= threshold) {
            return data;
        }

        const sampled = [];
        const bucketSize = Math.floor(data.length / threshold);

        // 简化的降采样：均匀采样
        for (let i = 0; i < data.length; i += bucketSize) {
            sampled.push(data[i]);
        }

        // 确保包含最后一个点
        if (sampled[sampled.length - 1] !== data[data.length - 1]) {
            sampled.push(data[data.length - 1]);
        }

        return sampled;
    }

    showDownsamplingInfo(originalCount, sampledCount) {
        console.log(`数据降采样: ${originalCount} -> ${sampledCount}`);
    }

    hideDownsamplingInfo() {
        console.log('无需降采样');
    }

    initChart() {
        const chartContainer = this.shadowRoot.getElementById('chartContainer');
        if (chartContainer && window.echarts) {
            // 先销毁旧的图表实例
            if (this.chart) {
                try {
                    this.chart.dispose();
                    this.chart = null;
                } catch (error) {
                    console.warn('销毁旧图表实例时出错:', error);
                }
            }

            // 隐藏覆盖层，保留ECharts canvas
            this.hideChartOverlay();

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
                        chartContainer.style.minHeight = '350px';
                    }

                    try {
                        this.chart = window.echarts.init(chartContainer);
                        this._chartRendered = false; // 重置渲染标记
                        console.log('图表初始化成功，重置渲染标记');
                        this.updateChart();
                        console.log('图表初始化成功');
                    } catch (error) {
                        console.error('图表初始化失败:', error);
                        setTimeout(() => tryInitChart(attempt + 1), 500);
                    }
                } else if (attempt < 10) {
                    setTimeout(() => tryInitChart(attempt + 1), 200);
                } else {
                    console.error('图表初始化失败：ECharts未加载或容器未找到');
                }
            };

            // 开始尝试初始化
            setTimeout(() => tryInitChart(), 100);
        }
    }

    // 计算数据范围，用于动态调整坐标轴
    calculateDataRange() {
        let minValue = Infinity;
        let maxValue = -Infinity;
        let hasData = false;

        // 遍历显示数据中的所有数据点
        this.displayData.forEach(record => {
            this.selectedPoints.forEach(pointName => {
                if (record[pointName] !== null && record[pointName] !== undefined && typeof record[pointName] === 'number') {
                    minValue = Math.min(minValue, record[pointName]);
                    maxValue = Math.max(maxValue, record[pointName]);
                    hasData = true;
                }
            });
        });

        if (!hasData) {
            return { min: 0, max: 100 }; // 默认范围
        }

        // 添加10%的边距，避免数据贴边
        const range = maxValue - minValue;
        const padding = range * 0.1;
        
        return {
            min: minValue - padding,
            max: maxValue + padding
        };
    }

    // 计算x轴范围，用于动态调整x坐标轴
    calculateXAxisRange(xAxisColumn = 'key') {
        if (!this.displayData || this.displayData.length === 0) {
            return { min: 0, max: 100 };
        }

        let minValue = Infinity;
        let maxValue = -Infinity;

        this.displayData.forEach(record => {
            let value;
            if (xAxisColumn === 'key') {
                value = record.timestamp;
            } else {
                value = record[xAxisColumn] !== undefined ? record[xAxisColumn] : (record.values && record.values[xAxisColumn] !== undefined ? record.values[xAxisColumn] : null);
            }
            if (value !== null && value !== undefined) {
                const numValue = typeof value === 'number' ? value : parseFloat(value);
                if (!isNaN(numValue)) {
                    minValue = Math.min(minValue, numValue);
                    maxValue = Math.max(maxValue, numValue);
                }
            }
        });

        if (minValue === Infinity || maxValue === -Infinity) {
            return { min: 0, max: 100 };
        }

        // 添加5%的边距，避免数据贴边
        const range = maxValue - minValue;
        const padding = range * 0.05;
        
        return {
            min: minValue - padding,
            max: maxValue + padding
        };
    }

    updateVisualization() {
        this.updateChart();
        this.updateTable();
    }

    updateChart() {
        console.log('=== UPDATEChart 被调用 ===', Date.now());
        if (!this.chart || !this.displayData.length || this.selectedPoints.size === 0) {
            console.log('updateChart 提前退出:', {
                hasChart: !!this.chart,
                hasData: this.displayData.length > 0,
                hasSelectedPoints: this.selectedPoints.size > 0
            });
            return;
        }

        // 获取选中的图表类型和轴
        const chartTypeSelect = this.shadowRoot.getElementById('chartType');
        const xAxisSelect = this.shadowRoot.getElementById('xAxisSelect');
        const yAxisSelect = this.shadowRoot.getElementById('yAxisSelect');

        const selectedChartType = chartTypeSelect ? chartTypeSelect.value : 'line';
        const selectedXAxis = xAxisSelect ? xAxisSelect.value : '';
        const selectedYAxis = yAxisSelect ? yAxisSelect.value : '';

        console.log('选中的图表类型:', selectedChartType);
        console.log('选中的X轴:', selectedXAxis);
        console.log('选中的Y轴:', selectedYAxis);

        // 根据图表类型渲染不同的图表
        if (selectedChartType === 'histogram') {
            this.renderHistogram(selectedXAxis, selectedYAxis);
        } else if (selectedChartType === 'scatter') {
            this.renderScatter(selectedXAxis, selectedYAxis);
        } else {
            this.renderLineOrBarChart(selectedChartType, selectedXAxis, selectedYAxis);
        }
    }

    renderLineOrBarChart(chartType, selectedXAxis, selectedYAxis) {
        // 检查是否有key列和是否包含选中的测点数据
        const actualColumns = this.actualDataColumns || [];
        const hasTimeColumn = this.tableHeader && this.tableHeader.includes('key');
        
        // 检查选中的测点是否在表头中
        const hasSelectedColumns = this.selectedPoints.size > 0 && Array.from(this.selectedPoints).some(selectedPoint => {
            if (actualColumns.includes(selectedPoint)) {
                return true;
            }
            return actualColumns.some(column => column.includes(selectedPoint));
        });
        
        const hasNumericData = Array.from(this.selectedPoints).some(selectedPoint => {
            console.log('🔍 hasNumericData检查 - 测点:', selectedPoint);
            // 找到对应的实际数据列
            const matchedColumn = actualColumns.find(column => 
                column === selectedPoint || column.includes(selectedPoint)
            );
            
            console.log('🔍 hasNumericData检查 - 匹配列:', matchedColumn);
            if (!matchedColumn) return false;
            
            // 检查该列是否有数值数据
            const hasNumeric = this.displayData.some(record => {
                const value = record[matchedColumn] !== undefined ? record[matchedColumn] : record.values && record.values[matchedColumn] !== undefined ? record.values[matchedColumn] : null;
                console.log('🔍 hasNumericData检查 - 值:', value, '类型:', typeof value);
                return typeof value === 'number';
            });
            
            console.log('🔍 hasNumericData检查 - 测点', selectedPoint, '是否有数值:', hasNumeric);
            return hasNumeric;
        });

        // 如果没有key列、不包含选中测点或不是数值数据，显示提示信息
        if (!hasTimeColumn || !hasSelectedColumns || !hasNumericData) {
            console.log('图表显示条件检查失败:', { hasTimeColumn, hasSelectedColumns, hasNumericData });
            console.log('🔒 检查图表渲染标记:', this._chartRendered);
            
            // 如果图表已经成功渲染，不要覆盖显示
            if (this._chartRendered) {
                console.log('🛡️ 图表已渲染，跳过显示条件检查');
                return;
            }
            
            console.log('表头:', this.tableHeader);
            console.log('实际数据列:', actualColumns);
            console.log('选中测点:', Array.from(this.selectedPoints));
            let reason = '';
            if (!hasTimeColumn) {
                reason = '缺少时间列数据';
            } else if (!hasSelectedColumns) {
                reason = '表头不包含选中的测点数据';
            } else {
                reason = '测点数据为非数值类型';
            }
            const inappropriateContent = `
                <div style="display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100%; color: #999;">
                    <div style="font-size: 48px; margin-bottom: 16px;">📊</div>
                    <div style="font-size: 14px; margin-bottom: 8px;">数据不适合图表显示</div>
                    <div style="font-size: 12px;">${reason}</div>
                    <div style="font-size: 12px; margin-top: 8px; color: #666;">请选择包含时间列的数值型测点</div>
                </div>
            `;
            this.showChartOverlay(inappropriateContent);
            return;
        }

        const series = [];
        const selectedPointsArray = Array.from(this.selectedPoints);

        // 确定X轴列
        const xAxisColumn = selectedXAxis || 'key';
        
        // 确定Y轴列
        const yAxisColumns = selectedYAxis ? [selectedYAxis] : Array.from(this.selectedPoints);

        console.log('处理图表系列 - X轴列:', xAxisColumn);
        console.log('处理图表系列 - Y轴列:', yAxisColumns);

        // 计算X轴范围（根据选择的X轴列）
        let xAxisMin = Infinity;
        let xAxisMax = -Infinity;
        
        yAxisColumns.forEach((column, index) => {
            console.log('处理列:', column);
            
            // 检查该列是否为数值类型
            const isNumericColumn = this.displayData.some(record => {
                const value = record[column] !== undefined ? record[column] : record.values && record.values[column] !== undefined ? record.values[column] : null;
                return typeof value === 'number';
            });

            if (!isNumericColumn) {
                console.log('跳过非数值列:', column);
                return;
            }

            console.log('✅ 数值列检查通过:', column, '准备创建数据系列');
            const data = this.displayData.map(record => {
                let xValue;
                if (xAxisColumn === 'key') {
                    xValue = record.timestamp;
                } else {
                    xValue = record[xAxisColumn] !== undefined ? record[xAxisColumn] : record.values && record.values[xAxisColumn] !== undefined ? record.values[xAxisColumn] : 0;
                }
                const yValue = record[column] !== undefined ? record[column] : record.values && record.values[column] !== undefined ? record.values[column] : 0;
                
                // 收集X轴范围
                if (typeof xValue === 'number' && !isNaN(xValue)) {
                    xAxisMin = Math.min(xAxisMin, xValue);
                    xAxisMax = Math.max(xAxisMax, xValue);
                }
                
                return [xValue, yValue];
            });
            console.log('📊 创建的数据系列:', column, '数据长度:', data.length);

            const color = this.getColorForPoint(column);
            const seriesItem = {
                name: column,
                type: chartType,
                data: data,
                smooth: chartType === 'line',
                symbol: 'circle',
                symbolSize: 4,
                showSymbol: false,
                lineStyle: {
                    width: 2,
                    color: color
                },
                areaStyle: undefined
            };
            console.log('📈 准备推送系列:', seriesItem.name);
            series.push(seriesItem);
        });

        console.log('创建的图表系列数量:', series.length);

        // 计算数据范围
        const dataRange = this.calculateDataRange();
        
        // 使用计算得到的X轴范围，如果没有则使用默认值
        const xAxisRange = xAxisMin === Infinity ? this.calculateXAxisRange(xAxisColumn) : { min: xAxisMin, max: xAxisMax };
        console.log('X轴范围:', xAxisRange, 'X轴列:', xAxisColumn);

        const option = {
            title: {
                text: chartType === 'bar' ? '数据柱状图' : '数据趋势图',
                left: 'center',
                top: 10,
                textStyle: {
                    fontSize: 14,
                    fontWeight: 'bold'
                }
            },
            tooltip: {
                trigger: 'axis',
                formatter: (params) => {
                    if (!params || params.length === 0) return '';

                    const xValue = params[0].value[0];
                    let xLabel = '';
                    if (xAxisColumn === 'key' && this.isValidTimestamp(xValue)) {
                        xLabel = new Date(xValue).toLocaleString();
                    } else {
                        xLabel = String(xValue);
                    }
                    let result = `${xAxisColumn === 'key' ? '时间' : xAxisColumn}: ${xLabel}<br/>`;
                    params.forEach(param => {
                        if (param.value[1] !== null && param.value[1] !== undefined) {
                            result += `${param.seriesName}: ${param.value[1].toFixed(2)}<br/>`;
                        } else {
                            result += `${param.seriesName}: --<br/>`;
                        }
                    });
                    return result;
                }
            },
            legend: {
                data: yAxisColumns,
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
                type: 'value',
                min: xAxisRange.min,
                max: xAxisRange.max,
                name: xAxisColumn === 'key' ? '' : xAxisColumn,
                nameLocation: 'middle',
                nameGap: 30,
                axisLabel: {
                    formatter: (value) => {
                        if (xAxisColumn === 'key' && this.isValidTimestamp(value)) {
                            return new Date(value).toLocaleString();
                        } else {
                            return String(value);
                        }
                    }
                }
            },
            yAxis: {
                type: 'value',
                min: dataRange.min,
                max: dataRange.max,
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
            series: series
        };

        try {
            this.hideChartOverlay();
            this.chart.clear();
            this.chart.setOption(option, false);
            this._chartRendered = true;
            console.log('✅ 图表渲染完成');
        } catch (error) {
            console.error('图表渲染失败:', error);
        }
    }

    renderScatter(selectedXAxis, selectedYAxis) {
        const actualColumns = this.actualDataColumns || [];
        
        // 确定X轴和Y轴列
        const xAxisColumn = selectedXAxis || actualColumns[0];
        const yAxisColumn = selectedYAxis || (actualColumns.length > 1 ? actualColumns[1] : actualColumns[0]);

        if (!xAxisColumn || !yAxisColumn) {
            this.showChartOverlay(`
                <div style="display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100%; color: #999;">
                    <div style="font-size: 48px; margin-bottom: 16px;">📊</div>
                    <div style="font-size: 14px;">请选择X轴和Y轴列</div>
                </div>
            `);
            return;
        }

        const data = this.displayData.map(record => {
            let xValue;
            if (xAxisColumn === 'key') {
                xValue = record.timestamp;
            } else {
                xValue = record[xAxisColumn] !== undefined ? record[xAxisColumn] : (record.values && record.values[xAxisColumn] !== undefined ? record.values[xAxisColumn] : 0);
            }
            const yValue = record[yAxisColumn] !== undefined ? record[yAxisColumn] : (record.values && record.values[yAxisColumn] !== undefined ? record.values[yAxisColumn] : 0);
            return [xValue, yValue];
        });

        const option = {
            title: {
                text: '散点图',
                left: 'center',
                top: 10,
                textStyle: {
                    fontSize: 14,
                    fontWeight: 'bold'
                }
            },
            tooltip: {
                trigger: 'item',
                formatter: (params) => {
                    let xLabel;
                    if (xAxisColumn === 'key' && this.isValidTimestamp(params.value[0])) {
                        xLabel = new Date(params.value[0]).toLocaleString();
                    } else {
                        xLabel = params.value[0].toFixed(2);
                    }
                    return `${xAxisColumn === 'key' ? '时间' : xAxisColumn}: ${xLabel}<br/>${yAxisColumn}: ${params.value[1].toFixed(2)}`;
                }
            },
            grid: {
                left: '10%',
                right: '10%',
                bottom: '15%',
                top: '20%'
            },
            xAxis: {
                type: 'value',
                name: xAxisColumn === 'key' ? '' : xAxisColumn,
                nameLocation: 'middle',
                nameGap: 30,
                axisLabel: {
                    formatter: (value) => {
                        if (xAxisColumn === 'key' && this.isValidTimestamp(value)) {
                            return new Date(value).toLocaleString();
                        } else {
                            return String(value);
                        }
                    }
                }
            },
            yAxis: {
                type: 'value',
                name: yAxisColumn,
                nameLocation: 'middle',
                nameGap: 40
            },
            series: [{
                type: 'scatter',
                data: data,
                symbolSize: 6,
                itemStyle: {
                    color: '#3370ff'
                }
            }]
        };

        try {
            this.hideChartOverlay();
            this.chart.clear();
            this.chart.setOption(option, false);
            this._chartRendered = true;
            console.log('✅ 散点图渲染完成');
        } catch (error) {
            console.error('散点图渲染失败:', error);
        }
    }

    renderHistogram(selectedXAxis, selectedYAxis) {
        const actualColumns = this.actualDataColumns || [];
        
        // 确定要统计的列
        const targetColumn = selectedYAxis || actualColumns.find(col => col !== 'key') || actualColumns[0];

        if (!targetColumn) {
            this.showChartOverlay(`
                <div style="display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100%; color: #999;">
                    <div style="font-size: 48px; margin-bottom: 16px;">📊</div>
                    <div style="font-size: 14px;">请选择要统计的列</div>
                </div>
            `);
            return;
        }

        // 收集数值数据
        const values = this.displayData.map(record => record[targetColumn] !== undefined ? record[targetColumn] : 0).filter(v => typeof v === 'number');

        if (values.length === 0) {
            this.showChartOverlay(`
                <div style="display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100%; color: #999;">
                    <div style="font-size: 48px; margin-bottom: 16px;">📊</div>
                    <div style="font-size: 14px;">该列没有数值数据</div>
                </div>
            `);
            return;
        }

        // 计算直方图数据
        const min = Math.min(...values);
        const max = Math.max(...values);
        const binCount = 20;
        const binSize = (max - min) / binCount;
        
        const bins = new Array(binCount).fill(0);
        values.forEach(value => {
            const binIndex = Math.min(Math.floor((value - min) / binSize), binCount - 1);
            bins[binIndex]++;
        });

        const data = bins.map((count, index) => ({
            value: [min + index * binSize + binSize / 2, count],
            itemStyle: {
                color: '#3370ff'
            }
        }));

        const option = {
            title: {
                text: '直方图',
                left: 'center',
                top: 10,
                textStyle: {
                    fontSize: 14,
                    fontWeight: 'bold'
                }
            },
            tooltip: {
                trigger: 'item',
                formatter: (params) => {
                    const rangeStart = params.value[0] - binSize / 2;
                    const rangeEnd = params.value[0] + binSize / 2;
                    return `范围: ${rangeStart.toFixed(2)} - ${rangeEnd.toFixed(2)}<br/>频数: ${params.value[1]}`;
                }
            },
            grid: {
                left: '10%',
                right: '10%',
                bottom: '15%',
                top: '20%'
            },
            xAxis: {
                type: 'value',
                name: targetColumn,
                nameLocation: 'middle',
                nameGap: 30,
                min: min,
                max: max
            },
            yAxis: {
                type: 'value',
                name: '频数',
                nameLocation: 'middle',
                nameGap: 40
            },
            series: [{
                type: 'bar',
                data: data,
                barWidth: (max - min) / binCount * 0.8
            }]
        };

        try {
            this.hideChartOverlay();
            this.chart.clear();
            this.chart.setOption(option, false);
            this._chartRendered = true;
            console.log('✅ 直方图渲染完成');
        } catch (error) {
            console.error('直方图渲染失败:', error);
        }
    }

    updateTable() {
        console.log('更新表格，allData length:', this.allData.length, 'displayData length:', this.displayData.length);
        console.log('selectedPoints:', Array.from(this.selectedPoints));

        const tableSection = this.shadowRoot.querySelector('.table-section');
        const table = this.shadowRoot.getElementById('dataTable');
        const tbody = this.shadowRoot.getElementById('tableBody');

        // 确保表格区域始终显示
        if (tableSection) {
            tableSection.style.display = 'flex';
        }

        // 更新表格数据
        if (!tbody) {
            console.error('找不到表格体');
            return;
        }

        tbody.innerHTML = '';

        if (!this.allData.length || this.selectedPoints.size === 0) {
            console.log('没有原始数据或没有选中的测点，显示空状态提示');
            const tr = document.createElement('tr');
            const td = document.createElement('td');
            const actualColumns = this.actualDataColumns || Array.from(this.selectedPoints);
            td.colSpan = Math.max(1, actualColumns.length + 1); // 时间列 + 实际数据列
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

        // 计算分页 - 基于原始数据
        this.totalPages = Math.ceil(this.allData.length / this.pageSize);
        // 确保当前页在有效范围内
        if (this.currentPage > this.totalPages) {
            this.currentPage = this.totalPages;
        }
        if (this.currentPage < 1) {
            this.currentPage = 1;
        }

        console.log('分页信息：当前页', this.currentPage, '总页数', this.totalPages, '总数据', this.allData.length);

        const startIndex = (this.currentPage - 1) * this.pageSize;
        const endIndex = Math.min(startIndex + this.pageSize, this.allData.length);
        const pageData = this.allData.slice(startIndex, endIndex);

        console.log('当前页数据范围:', startIndex, '-', endIndex, '实际数据量:', pageData.length);

        const selectedPointsArray = Array.from(this.selectedPoints);
        const actualColumns = this.actualDataColumns || selectedPointsArray; // 优先使用实际数据列

        pageData.forEach((record, index) => {
            const tr = document.createElement('tr');

            // 时间列（key列）
            const timeTd = document.createElement('td');
            const originalKey = record.key;
            const parsedTimestamp = record.timestamp;
            
            // 判断是否是有效时间戳
            let displayContent = originalKey;
            if (this.isValidTimestamp(parsedTimestamp)) {
                displayContent = new Date(parsedTimestamp).toLocaleString();
            }
            
            timeTd.innerHTML = `<div>${displayContent}</div>`;
            tr.appendChild(timeTd);

            // 实际数据列（不是选中测点）
            actualColumns.forEach(column => {
                const td = document.createElement('td');
                const value = record[column] !== undefined ? record[column] : record.values && record.values[column] !== undefined ? record.values[column] : '-';
                td.textContent = typeof value === 'number' ? value.toFixed(2) : value;
                tr.appendChild(td);
            });

            tbody.appendChild(tr);
        });

        console.log('表格数据更新完成，行数:', tbody.children.length);

        // 更新分页信息
        this.updatePagination();
    }

    updatePagination() {
        // 更新页面信息文本 - 表格显示原始数据
        const pageInfo = this.shadowRoot.getElementById('pageInfo');
        if (pageInfo) {
            if (this.totalPages > 0) {
                // 检查是否进行了降采样（图表使用）
                const isDownsampled = this.allData.length !== this.displayData.length;
                if (isDownsampled) {
                    pageInfo.textContent = `第 ${this.currentPage} 页 / 共 ${this.totalPages} 页 (表格显示${this.allData.length}条，图表显示${this.displayData.length}条)`;
                } else {
                    pageInfo.textContent = `第 ${this.currentPage} 页 / 共 ${this.totalPages} 页 (总计${this.allData.length}条)`;
                }
            } else {
                pageInfo.textContent = '第 1 页 / 共 1 页 (总计0条)';
            }
        }

        // 更新分页按钮状态
        const prevBtn = this.shadowRoot.getElementById('prevBtn');
        const nextBtn = this.shadowRoot.getElementById('nextBtn');

        if (prevBtn) {
            prevBtn.disabled = this.currentPage <= 1 || this.totalPages <= 1;
        }

        if (nextBtn) {
            nextBtn.disabled = this.currentPage >= this.totalPages || this.totalPages <= 1;
        }

        // 更新每页显示选择框的值
        const pageSizeSelect = this.shadowRoot.getElementById('pageSizeSelect');
        if (pageSizeSelect) {
            pageSizeSelect.value = this.pageSize.toString();
        }

        // 分页组件（如果存在）
        const pagination = this.shadowRoot.getElementById('tablePagination');
        if (pagination) {
            // 设置分页组件的数据
            pagination.setAttribute('current-page', this.currentPage);
            pagination.setAttribute('page-size', this.pageSize);
            pagination.setAttribute('total-records', this.allData.length);
        }
    }

    getColorForPoint(pointName) {
        // 为每个测点名称生成固定的颜色
        const colors = [
            '#3370ff', '#00b42a', '#ff7d00', '#f53f3f', '#722ed1',
            '#13c2c2', '#eb2f96', '#faad14', '#a0d911', '#f5222d'
        ];

        // 使用测点名称的哈希值来确保颜色一致性
        let hash = 0;
        for (let i = 0; i < pointName.length; i++) {
            hash = pointName.charCodeAt(i) + ((hash << 5) - hash);
        }

        return colors[Math.abs(hash) % colors.length];
    }

    getColorForIndex(index) {
        const colors = [
            '#3370ff', '#00b42a', '#ff7d00', '#f53f3f', '#722ed1',
            '#13c2c2', '#eb2f96', '#faad14', '#a0d911', '#f5222d'
        ];
        return colors[index % colors.length];
    }

    // 模态框相关方法
    showDataCleanModal() {
        // 获取当前选中的测点和时间范围
        const selectedPointsArray = Array.from(this.selectedPoints);
        const startTimeInput = this.shadowRoot.getElementById('startTime');
        const endTimeInput = this.shadowRoot.getElementById('endTime');

        let startTime = '';
        let endTime = '';

        // 获取时间值
        if (startTimeInput && startTimeInput.value) {
            startTime = startTimeInput.value;
        }
        if (endTimeInput && endTimeInput.value) {
            endTime = endTimeInput.value;
        }

        // 如果没有设置时间，但有快速选择的时间，使用快速选择的时间
        if (!startTime && !endTime) {
            const activeQuickBtn = this.shadowRoot.querySelector('.quick-time-btn.active');
            if (activeQuickBtn) {
                const range = activeQuickBtn.dataset.range;
                const end = new Date();
                const start = new Date();

                switch (range) {
                    case '1h':
                        start.setHours(start.getHours() - 1);
                        break;
                    case '6h':
                        start.setHours(start.getHours() - 6);
                        break;
                    case '24h':
                        start.setDate(start.getDate() - 1);
                        break;
                    case '7d':
                        start.setDate(start.getDate() - 7);
                        break;
                }

                // 转换为本地时间的datetime-local格式 (YYYY-MM-DDTHH:mm)
                startTime = `${start.getFullYear()}-${String(start.getMonth() + 1).padStart(2, '0')}-${String(start.getDate()).padStart(2, '0')}T${String(start.getHours()).padStart(2, '0')}:${String(start.getMinutes()).padStart(2, '0')}`;
                endTime = `${end.getFullYear()}-${String(end.getMonth() + 1).padStart(2, '0')}-${String(end.getDate()).padStart(2, '0')}T${String(end.getHours()).padStart(2, '0')}:${String(end.getMinutes()).padStart(2, '0')}`;
                console.log('快速选择时间:', { startTime, endTime });
            }
        }

        console.log('最终填充的时间:', { startTime, endTime });

        this.showModal('数据清理', `
            <div class="form-group">
                <label>已选测点：</label>
                <div style="margin: 8px 0; padding: 8px; background: #f5f5f5; border-radius: 4px;">
                    ${selectedPointsArray.length > 0 ? selectedPointsArray.join(', ') : '未选择测点'}
                </div>
            </div>
            <div class="form-group">
                <label>开始时间：</label>
                <input type="datetime-local" id="deleteStartTime" value="${startTime}" />
            </div>
            <div class="form-group">
                <label>结束时间：</label>
                <input type="datetime-local" id="deleteEndTime" value="${endTime}" />
            </div>
            <div class="form-group" style="color: #ff4d4f; font-size: 12px;">
                <strong>警告：此操作将删除指定时间范围内的所有数据，且不可恢复！</strong><br>
                <strong>限制：单次删除时间跨度不能超过1年</strong>
            </div>
        `, async () => {
            return await this.deleteData();
        }, true); // 验证失败时不关闭弹窗
    }

    async deleteData() {
        console.log('deleteData方法开始执行');

        let shouldCloseModal = false;

        try {
            console.log('开始删除数据，选中的测点:', Array.from(this.selectedPoints));

            if (this.selectedPoints.size === 0) {
                this.showMessage('请先选择测点后再删除数据', 'error');
                shouldCloseModal = false; // 验证失败不关闭弹窗
            } else {
                // 检查已选测点是否包含"_system"
                const selectedPointsArray = Array.from(this.selectedPoints);
                const hasSystemPoint = selectedPointsArray.some(point => point.includes('_system'));
                if (hasSystemPoint) {
                    this.showMessage('已选测点不能包含"_system"', 'error');
                    shouldCloseModal = false; // 验证失败不关闭弹窗
                } else {
                    // 获取删除参数
                    const startTimeInput = this.shadowRoot.getElementById('deleteStartTime');
                    const endTimeInput = this.shadowRoot.getElementById('deleteEndTime');

                console.log('时间输入元素:', startTimeInput, endTimeInput);
                console.log('时间输入值:', startTimeInput?.value, endTimeInput?.value);

                let startTime = null;
                let endTime = null;

                // 处理时间参数
                if (startTimeInput && startTimeInput.value) {
                    startTime = new Date(startTimeInput.value).getTime();
                    console.log('解析的开始时间:', startTime);
                }
                if (endTimeInput && endTimeInput.value) {
                    endTime = new Date(endTimeInput.value).getTime();
                    console.log('解析的结束时间:', endTime);
                }

                if (!startTime || !endTime) {
                    this.showMessage('请选择删除的时间范围', 'error');
                    shouldCloseModal = false; // 验证失败不关闭弹窗
                } else if (startTime >= endTime) {
                    this.showMessage('开始时间必须早于结束时间', 'error');
                    shouldCloseModal = false; // 验证失败不关闭弹窗
                } else {
                    // 检查删除时间跨度限制（1年）
                    const oneYearMs = 365 * 24 * 60 * 60 * 1000; // 1年的毫秒数
                    const timeSpan = endTime - startTime;
                    if (timeSpan > oneYearMs) {
                        this.showMessage('删除时间跨度不能超过1年，请缩小时间范围', 'error');
                        shouldCloseModal = false; // 验证失败不关闭弹窗
                    } else {
                        // 验证通过，执行删除操作
                        shouldCloseModal = true; // 标记为可以关闭弹窗

                        // 显示全局loading
                        if (window.showGlobalLoading) {
                            window.showGlobalLoading('正在删除数据...');
                        }

                        // 构建请求体
                        const requestBody = {
                            paths: Array.from(this.selectedPoints),
                            startTime: startTime,
                            endTime: endTime
                        };

                        console.log('删除参数:', requestBody);

                        // 调用数据删除接口
                        const result = await window.AppConfig.post('data', 'delete', requestBody);

                        console.log('删除API响应:', result);

                        if (result.success) {
                            console.log('数据删除成功:', result.message);
                            this.showMessage('数据删除成功', 'success');

                            // 重新加载数据（不等待完成）
                            this.loadData();
                            console.log('数据重新加载已启动，关闭弹窗');
                        } else {
                            // 400参数错误或500系统错误
                            console.error('数据删除失败:', result.message);
                            this.showMessage('数据删除失败: ' + (result.message || '未知错误'), 'error');
                        }

                        console.log('准备关闭弹窗');
                    }
                }
            }
            }

        } catch (error) {
            console.error('删除数据失败:', error);
            this.showMessage('网络错误，无法删除数据', 'error');
            shouldCloseModal = true; // 网络异常是API调用结果，关闭弹窗
        }

        // 隐藏全局loading
        if (window.hideGlobalLoading) {
            window.hideGlobalLoading();
        }

        console.log('deleteData最终返回:', shouldCloseModal);
        return shouldCloseModal;
    }

    showImportModal() {
        this.showModal('导入数据', `
            <div class="form-group">
                <label class="form-label required">目标存储路径前缀：</label>
                <input type="text" id="targetPath" class="form-input" placeholder="例如：root.sg.device" required>
                <div class="form-hint">数据将导入到此路径下，例如：root.sg.device</div>
            </div>
            <div class="form-group">
                <label class="form-label required">选择CSV文件：</label>
                <input type="file" id="importFile" class="form-input" accept=".csv" required>
                <div class="form-hint">仅支持CSV格式文件，文件大小不超过1GB</div>
            </div>
        `, () => {
            this.handleImportData();
        });
    }

    async handleImportData() {
        const targetPath = this.shadowRoot.getElementById('targetPath').value.trim();
        const fileInput = this.shadowRoot.getElementById('importFile');
        const file = fileInput.files[0];

        // 验证输入
        if (!targetPath) {
            this.showMessage('请输入目标存储路径前缀', 'error');
            return;
        }

        if (!file) {
            this.showMessage('请选择要导入的CSV文件', 'error');
            return;
        }

        if (!file.name.toLowerCase().endsWith('.csv')) {
            this.showMessage('仅支持CSV格式文件', 'error');
            return;
        }

        // 检查文件大小（1GB）
        if (file.size > 1024 * 1024 * 1024) {
            this.showMessage('文件大小不能超过1GB', 'error');
            return;
        }

        try {
            // 显示loading
            if (window.showGlobalLoading) {
                window.showGlobalLoading('正在导入数据...');
            }

            // 创建FormData
            const formData = new FormData();

            // 添加配置参数作为JSON字符串
            const config = {
                targetPath: targetPath
            };
            formData.append('config', new Blob([JSON.stringify(config)], { type: 'application/json' }));

            // 添加文件
            formData.append('file', file);

            // 调用导入接口
            const result = await window.AppConfig.upload('data', 'import', formData);

            if (result.success) {
                this.showMessage(result.message || '数据导入成功', 'success');
                // 导入成功后刷新数据
                this.loadData();
            } else {
                this.showMessage(result.message || '数据导入失败', 'error');
            }
        } catch (error) {
            console.error('导入数据失败:', error);
            this.showMessage('导入失败，请稍后重试', 'error');
        } finally {
            // 隐藏loading
            if (window.hideGlobalLoading) {
                window.hideGlobalLoading();
            }
        }
    }

    showModal(title, content, onConfirm, keepOpenOnValidationError = false) {
        const modalOverlay = document.createElement('div');
        modalOverlay.className = 'modal-overlay';
        modalOverlay.innerHTML = `
            <div class="modal">
                <div class="modal-header">
                    <h3 class="modal-title">${title}</h3>
                    <button class="modal-close">×</button>
                </div>
                <div class="modal-body">
                    ${content}
                </div>
                <div class="modal-footer">
                    <button class="modal-btn">取消</button>
                    <button class="modal-btn primary">确定</button>
                </div>
            </div>
        `;

        this.shadowRoot.appendChild(modalOverlay);

        const closeModal = () => {
            this.shadowRoot.removeChild(modalOverlay);
        };

        // 绑定事件
        modalOverlay.querySelector('.modal-close').addEventListener('click', closeModal);
        modalOverlay.querySelector('.modal-btn:not(.primary)').addEventListener('click', closeModal);
        modalOverlay.querySelector('.modal-btn.primary').addEventListener('click', async () => {
            console.log('确定按钮被点击，开始执行onConfirm');
            if (onConfirm) {
                if (keepOpenOnValidationError) {
                    // 如果支持验证失败时不关闭弹窗，等待onConfirm返回结果
                    try {
                        console.log('准备调用onConfirm函数');
                        const result = await onConfirm();
                        console.log('onConfirm返回结果:', result);
                        // 只有返回true时才关闭弹窗
                        if (result === true) {
                            console.log('准备关闭弹窗');
                            closeModal();
                        } else {
                            console.log('验证失败或操作未成功，保持弹窗打开');
                        }
                    } catch (error) {
                        console.error('确认操作失败:', error);
                        // 发生错误时不关闭弹窗
                    }
                } else {
                    // 原有逻辑：直接执行并关闭弹窗
                    onConfirm();
                    closeModal();
                }
            } else {
                closeModal();
            }
        });

        // 移除点击遮罩关闭功能，避免误操作
        // modalOverlay.addEventListener('click', (e) => {
        //     if (e.target === modalOverlay) {
        //         closeModal();
        //     }
        // });
    }
}

// 注册自定义元素
customElements.define('data-visualization', DataVisualization);