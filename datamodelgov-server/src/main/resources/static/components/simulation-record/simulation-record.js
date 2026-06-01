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
                        <div class="chart-controls">
                            <div class="chart-control-item">
                                <label class="chart-control-label">图表类型:</label>
                                <select class="chart-control-select" id="chartType">
                                    <option value="line">曲线图</option>
                                    <option value="bar">柱状图</option>
                                    <option value="scatter">散点图</option>
                                    <option value="histogram">直方图</option>
                                </select>
                            </div>
                            <div class="chart-control-item">
                                <label class="chart-control-label">X轴:</label>
                                <select class="chart-control-select" id="xAxisSelect">
                                    <option value="">自动选择</option>
                                </select>
                            </div>
                            <div class="chart-control-item">
                                <label class="chart-control-label">Y轴:</label>
                                <select class="chart-control-select" id="yAxisSelect">
                                    <option value="">自动选择</option>
                                </select>
                            </div>
                        </div>
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

        const chartTypeSelect = this.shadowRoot.getElementById('chartType');
        if (chartTypeSelect) {
            chartTypeSelect.addEventListener('change', () => this.updateChart());
        }

        const xAxisSelect = this.shadowRoot.getElementById('xAxisSelect');
        if (xAxisSelect) {
            xAxisSelect.addEventListener('change', () => this.updateChart());
        }

        const yAxisSelect = this.shadowRoot.getElementById('yAxisSelect');
        if (yAxisSelect) {
            yAxisSelect.addEventListener('change', () => this.updateChart());
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

        // 对比模式走单独的更新路径
        if (this.currentChartData.type === 'comparison') {
            this.updateComparisonChart(this.currentChartData.data);
            return;
        }

        // 更新轴下拉框选项
        this.updateAxisDropdowns();

        const chartTypeSelect = this.shadowRoot.getElementById('chartType');
        const selectedChartType = chartTypeSelect ? chartTypeSelect.value : 'line';

        // 根据图表类型分发到不同的渲染方法
        if (selectedChartType === 'histogram') {
            this.renderHistogram();
        } else if (selectedChartType === 'scatter') {
            this.renderScatter();
        } else {
            this.renderLineOrBarChart(selectedChartType);
        }
    }

    updateAxisDropdowns() {
        if (!this.currentChartData || !this.currentChartData.tasks) return;

        // 收集所有可用的列名
        const columns = ['key']; // key代表时间轴
        const columnSet = new Set(['key']);

        this.currentChartData.tasks.forEach(task => {
            // 从inputPaths获取列名
            if (task.inputPaths) {
                task.inputPaths.forEach(path => {
                    if (!columnSet.has(path)) {
                        columnSet.add(path);
                        columns.push(path);
                    }
                });
            }
            // 从outputPaths获取列名
            if (task.outputPaths) {
                task.outputPaths.forEach(path => {
                    if (!columnSet.has(path)) {
                        columnSet.add(path);
                        columns.push(path);
                    }
                });
            }
            // 从rawInputRecords的keys获取列名
            if (task.rawInputRecords && task.rawInputRecords.length > 0) {
                Object.keys(task.rawInputRecords[0]).forEach(key => {
                    if (!columnSet.has(key)) {
                        columnSet.add(key);
                        columns.push(key);
                    }
                });
            }
            // 从rawOutputRecords的keys获取列名
            if (task.rawOutputRecords && task.rawOutputRecords.length > 0) {
                Object.keys(task.rawOutputRecords[0]).forEach(key => {
                    if (!columnSet.has(key)) {
                        columnSet.add(key);
                        columns.push(key);
                    }
                });
            }
        });

        // 从CSV表头获取列名（备用）
        if (this.currentChartData.parsedResult && this.currentChartData.parsedResult.results) {
            Object.values(this.currentChartData.parsedResult.results).forEach(nodeResult => {
                if (nodeResult.outputCsv) {
                    const lines = nodeResult.outputCsv.split('\n');
                    if (lines.length > 0) {
                        lines[0].split(',').map(h => h.trim()).forEach(header => {
                            if (!columnSet.has(header)) {
                                columnSet.add(header);
                                columns.push(header);
                            }
                        });
                    }
                }
            });
        }

        // 检测哪些列是数值列
        const numericColumns = this.detectNumericColumns(columns);

        // 更新X轴下拉框（所有列都可以作为X轴，包括非数值列如signal用于分类）
        const xAxisSelect = this.shadowRoot.getElementById('xAxisSelect');
        if (xAxisSelect) {
            const currentValue = xAxisSelect.value;
            xAxisSelect.innerHTML = '<option value="">自动选择</option>';
            columns.forEach(col => {
                const option = document.createElement('option');
                option.value = col;
                option.textContent = col === 'key' ? '时间 (key)' : col;
                xAxisSelect.appendChild(option);
            });
            if (currentValue && columnSet.has(currentValue)) {
                xAxisSelect.value = currentValue;
            }
        }

        // 更新Y轴下拉框（只包含数值列，排除key和非数值列）
        const yAxisSelect = this.shadowRoot.getElementById('yAxisSelect');
        if (yAxisSelect) {
            const currentValue = yAxisSelect.value;
            yAxisSelect.innerHTML = '<option value="">自动选择</option>';
            numericColumns.forEach(col => {
                const option = document.createElement('option');
                option.value = col;
                option.textContent = col;
                yAxisSelect.appendChild(option);
            });
            if (currentValue && numericColumns.includes(currentValue)) {
                yAxisSelect.value = currentValue;
            }
        }
    }

    // 检测哪些列包含数值数据
    detectNumericColumns(columns) {
        const numericCols = [];
        columns.forEach(col => {
            if (col === 'key') return; // key是时间轴，不算数值列
            let hasNumeric = false;
            this.currentChartData.tasks.forEach(task => {
                if (task.rawInputRecords) {
                    task.rawInputRecords.forEach(r => {
                        if (r[col] != null && typeof r[col] === 'number') hasNumeric = true;
                    });
                }
                if (task.rawOutputRecords) {
                    task.rawOutputRecords.forEach(r => {
                        if (r[col] != null && typeof r[col] === 'number') hasNumeric = true;
                    });
                }
            });
            if (hasNumeric) numericCols.push(col);
        });
        return numericCols;
    }

    // 获取第一个数值列作为默认Y轴
    getFirstNumericColumn() {
        const numericCols = this.detectNumericColumns(
            this.currentChartData && this.currentChartData.tasks ?
                ['key', ...this.currentChartData.tasks.flatMap(t => [
                    ...(t.inputPaths || []),
                    ...(t.outputPaths || []),
                    ...(t.rawInputRecords && t.rawInputRecords[0] ? Object.keys(t.rawInputRecords[0]) : []),
                    ...(t.rawOutputRecords && t.rawOutputRecords[0] ? Object.keys(t.rawOutputRecords[0]) : [])
                ])] : []
        );
        return numericCols.length > 0 ? numericCols[0] : '';
    }

    // 获取指定task中输入/输出数据的所有数值列名
    getNumericColumnsForTask(task, type) {
        const records = type === 'input' ? task.rawInputRecords : task.rawOutputRecords;
        if (!records || records.length === 0) return [];
        const keys = Object.keys(records[0]);
        return keys.filter(key => {
            if (key === 'key') return false;
            return records.some(r => r[key] != null && typeof r[key] === 'number');
        });
    }

    // 智能Y轴分组（单个记录集）：按值域重叠分组，分配到左/右Y轴
    // 返回 { groups: [{ cols, min, max, yAxisIndex }], leftRange, rightRange }
    getSmartYAxisColumns(task, type) {
        const records = type === 'input' ? task.rawInputRecords : task.rawOutputRecords;
        if (!records || records.length === 0) return { groups: [], leftRange: null, rightRange: null };

        const colStats = {};
        Object.keys(records[0]).forEach(key => {
            if (key === 'key') return;
            const values = records.map(r => r[key]).filter(v => v != null && typeof v === 'number' && isFinite(v));
            if (values.length === 0) return;
            const min = Math.min(...values);
            const max = Math.max(...values);
            if (min === 0 && max === 0) return;
            colStats[key] = { min, max };
        });

        return this._groupColStatsByRange(colStats);
    }

    // 智能Y轴分组（全局）：汇总所有可见任务的输入+输出列一起分组
    // 这样不同来源但同量级的列会合并到同一轴，避免某轴量级跨度过大导致数据被压到底部
    getGlobalSmartYAxisColumns() {
        const colStats = {};
        const addRecords = (records) => {
            if (!records || records.length === 0) return;
            Object.keys(records[0]).forEach(key => {
                if (key === 'key') return;
                const values = records.map(r => r[key]).filter(v => v != null && typeof v === 'number' && isFinite(v));
                if (values.length === 0) return;
                const mn = Math.min(...values);
                const mx = Math.max(...values);
                if (mn === 0 && mx === 0) return;
                if (colStats[key]) {
                    colStats[key].min = Math.min(colStats[key].min, mn);
                    colStats[key].max = Math.max(colStats[key].max, mx);
                } else {
                    colStats[key] = { min: mn, max: mx };
                }
            });
        };

        const tasks = (this.currentChartData && this.currentChartData.tasks) ? this.currentChartData.tasks : [];
        tasks.forEach(task => {
            if (this.curveVisibility.input) addRecords(task.rawInputRecords);
            if (this.curveVisibility.output) addRecords(task.rawOutputRecords);
        });

        return this._groupColStatsByRange(colStats);
    }

    // 分组核心：将列统计按值域重叠分组、过滤不可见列，并仅保留列数最多的两组分配到左/右轴
    _groupColStatsByRange(colStats) {
        const colNames = Object.keys(colStats);
        if (colNames.length === 0) return { groups: [], leftRange: null, rightRange: null };

        colNames.forEach(k => {
            colStats[k].range = colStats[k].max - colStats[k].min;
            colStats[k].mid = (colStats[k].min + colStats[k].max) / 2;
        });

        // 按中值排序后按值域重叠分组
        const sorted = [...colNames].sort((a, b) => colStats[a].mid - colStats[b].mid);
        const groups = [];
        let currentGroup = [sorted[0]];
        let groupMin = colStats[sorted[0]].min;
        let groupMax = colStats[sorted[0]].max;

        for (let i = 1; i < sorted.length; i++) {
            const cMin = colStats[sorted[i]].min;
            const cMax = colStats[sorted[i]].max;
            const cMid = colStats[sorted[i]].mid;
            const groupMid = (groupMin + groupMax) / 2;
            const groupRange = groupMax - groupMin;
            const cRange = cMax - cMin;
            const largerRange = Math.max(groupRange, cRange);

            const shouldSplit = largerRange > 0
                ? Math.abs(cMid - groupMid) > largerRange * 0.5
                : (groupRange === 0 && cRange === 0 && Math.abs(cMid - groupMid) > 0);
            if (shouldSplit) {
                groups.push({ cols: currentGroup, min: groupMin, max: groupMax });
                currentGroup = [sorted[i]];
                groupMin = cMin;
                groupMax = cMax;
            } else {
                currentGroup.push(sorted[i]);
                groupMin = Math.min(groupMin, cMin);
                groupMax = Math.max(groupMax, cMax);
            }
        }
        groups.push({ cols: currentGroup, min: groupMin, max: groupMax });

        // 可见性过滤
        // 1. 排除常量列组（range=0，显示为水平线，无信息量）
        let visibleGroups = groups.filter(g => g.max > g.min);
        if (visibleGroups.length === 0) {
            // 全部为常量列：退回原始分组，至少能显示
            groups.forEach((g, i) => { g.yAxisIndex = i === 0 ? 0 : 1; });
            const lr = groups[0] ? { min: groups[0].min, max: groups[0].max } : null;
            return { groups, leftRange: lr, rightRange: null };
        }

        // 2. 以列数最多的组为参考，排除极端离群组（中值相差1000倍以上）
        visibleGroups.sort((a, b) => b.cols.length - a.cols.length);
        const refMid = (visibleGroups[0].min + visibleGroups[0].max) / 2;
        if (refMid > 0) {
            visibleGroups = visibleGroups.filter(g => {
                const gMid = (g.min + g.max) / 2;
                const ratio = Math.max(gMid / refMid, refMid / gMid);
                return ratio <= 1000;
            });
        }

        // 3. 仅保留列数最多的前两组（左/右轴各一）
        //    双轴最多承载两个量级，多余的组若强行塞入会压缩可见度，故排除
        visibleGroups.sort((a, b) => b.cols.length - a.cols.length);
        const keptGroups = visibleGroups.slice(0, 2);

        keptGroups[0].yAxisIndex = 0;
        const leftRange = { min: keptGroups[0].min, max: keptGroups[0].max };
        let rightRange = null;
        if (keptGroups.length > 1) {
            keptGroups[1].yAxisIndex = 1;
            rightRange = { min: keptGroups[1].min, max: keptGroups[1].max };
        }

        return { groups: keptGroups, leftRange, rightRange };
    }

    // 检测指定列是否为非数值列
    isNonNumericColumn(columnName) {
        if (!this.currentChartData || !this.currentChartData.tasks) return false;
        for (const task of this.currentChartData.tasks) {
            for (const records of [task.rawInputRecords, task.rawOutputRecords]) {
                if (records && records.length > 0 && records[0][columnName] !== undefined) {
                    return records.some(r => r[columnName] != null && typeof r[columnName] !== 'number');
                }
            }
        }
        return false;
    }

    // 智能X轴选择：自动选择最适合作为X轴的列
    // 优先选择分类列（如signal），其次选择key（时间轴）
    getSmartXAxisColumn() {
        if (!this.currentChartData || !this.currentChartData.tasks) return 'key';

        // 仅考虑当前可见的记录类型（输入/输出）
        const getVisibleRecordSets = (task) => {
            const sets = [];
            if (this.curveVisibility.input && task.rawInputRecords && task.rawInputRecords.length > 0) {
                sets.push(task.rawInputRecords);
            }
            if (this.curveVisibility.output && task.rawOutputRecords && task.rawOutputRecords.length > 0) {
                sets.push(task.rawOutputRecords);
            }
            return sets;
        };

        // 收集所有非key列（仅来自可见记录集）
        const colNames = new Set();
        this.currentChartData.tasks.forEach(task => {
            getVisibleRecordSets(task).forEach(records => {
                Object.keys(records[0]).forEach(k => {
                    if (k !== 'key') colNames.add(k);
                });
            });
        });

        // 找分类列（非数值列，且唯一值数量少）
        // 关键约束：分类列必须存在于所有将被绘制的可见记录集中，
        // 否则缺少该列的数据集（如时序输入数据没有signal列）会丢失全部数据点
        let bestCategory = null;
        let bestCategoryCount = Infinity;
        for (const col of colNames) {
            if (!this.isNonNumericColumn(col)) continue;

            // 检查该列是否存在于每个可见记录集中
            let existsInAll = true;
            const uniqueValues = new Set();
            this.currentChartData.tasks.forEach(task => {
                getVisibleRecordSets(task).forEach(records => {
                    if (records[0][col] === undefined) {
                        existsInAll = false;
                    } else {
                        records.forEach(r => {
                            if (r[col] != null) uniqueValues.add(String(r[col]));
                        });
                    }
                });
            });
            if (!existsInAll) continue;

            // 选择唯一值数量适中的分类列（2-20个唯一值最佳）
            const count = uniqueValues.size;
            if (count >= 2 && count <= 20 && count < bestCategoryCount) {
                bestCategory = col;
                bestCategoryCount = count;
            }
        }

        if (bestCategory) return bestCategory;
        return 'key';
    }

    renderLineOrBarChart(chartType) {
        const series = [];
        const colors = ['#1890ff', '#52c41a', '#faad14', '#f5222d', '#722ed1', '#13c2c2'];

        const xAxisSelect = this.shadowRoot.getElementById('xAxisSelect');
        const yAxisSelect = this.shadowRoot.getElementById('yAxisSelect');
        const selectedXAxis = xAxisSelect ? xAxisSelect.value : '';
        const selectedYAxis = yAxisSelect ? yAxisSelect.value : '';

        const xAxisColumn = selectedXAxis || this.getSmartXAxisColumn();
        const isXCategory = this.isNonNumericColumn(xAxisColumn);
        const isAutoY = !selectedYAxis;

        // 收集分类X轴的值
        let categoryData = [];
        if (isXCategory) {
            const categorySet = new Set();
            this.currentChartData.tasks.forEach(task => {
                for (const records of [task.rawInputRecords, task.rawOutputRecords]) {
                    if (records && records.length > 0) {
                        records.forEach(r => { if (r[xAxisColumn] != null) categorySet.add(String(r[xAxisColumn])); });
                    }
                }
            });
            categoryData = Array.from(categorySet);
        }

        // 智能Y轴：全局分组（输入+输出一起），确定左右轴列与范围
        let useDualY = false;
        let globalLeftCols = [];
        let globalRightCols = [];
        let globalLeftRange = null;
        let globalRightRange = null;
        let globalGroups = [];

        if (isAutoY) {
            const g = this.getGlobalSmartYAxisColumns();
            globalGroups = g.groups;
            g.groups.forEach(grp => {
                if (grp.yAxisIndex === 0) globalLeftCols.push(...grp.cols);
                else globalRightCols.push(...grp.cols);
            });
            globalLeftRange = g.leftRange;
            globalRightRange = g.rightRange;
            useDualY = globalRightCols.length > 0;
        }

        // 辅助函数：从全局分组中获取列的yAxisIndex；不在任何保留组中则返回-1（跳过）
        const getColYAxisIndex = (colName) => {
            for (const grp of globalGroups) {
                if (grp.cols.includes(colName)) return grp.yAxisIndex;
            }
            return -1;
        };

        // 全局保留的所有Y轴列（已过滤不可见列）
        const allKeptCols = globalGroups.flatMap(grp => grp.cols);

        if (this.currentChartData.tasks) {
            this.currentChartData.tasks.forEach((task, idx) => {
                const taskColor = colors[idx % colors.length];

                // 输入数据
                if (this.curveVisibility.input) {
                    if (task.rawInputRecords && task.rawInputRecords.length > 0) {
                        let allYCols;
                        if (isAutoY) {
                            allYCols = allKeptCols.filter(c => task.rawInputRecords[0][c] !== undefined);
                        } else {
                            allYCols = [selectedYAxis];
                        }

                        allYCols.forEach((col, colIdx) => {
                            if (!task.rawInputRecords[0] || task.rawInputRecords[0][col] === undefined) return;
                            const colColor = colors[(idx + colIdx) % colors.length];
                            const yIdx = isAutoY ? getColYAxisIndex(col) : 0;
                            if (yIdx === -1) return;
                            let data;
                            if (isXCategory) {
                                data = task.rawInputRecords
                                    .filter(r => r[col] != null && typeof r[col] === 'number' && r[xAxisColumn] != null)
                                    .map(r => [String(r[xAxisColumn]), r[col]]);
                            } else {
                                data = task.rawInputRecords
                                    .filter(r => r[col] != null && typeof r[col] === 'number')
                                    .map(r => {
                                        const xVal = xAxisColumn === 'key' ? r.key : (r[xAxisColumn] != null ? r[xAxisColumn] : r.key);
                                        return [xVal, r[col]];
                                    });
                            }
                            if (data.length === 0) return;
                            const isRight = yIdx === 1;
                            series.push({
                                name: `${col} (输入)`,
                                type: chartType,
                                yAxisIndex: yIdx,
                                data: data,
                                smooth: chartType === 'line',
                                symbol: 'circle',
                                symbolSize: 3,
                                lineStyle: chartType === 'line' ? { width: 2, color: colColor, type: isRight ? 'dotted' : 'dashed' } : undefined,
                                itemStyle: { color: colColor }
                            });
                        });
                    } else if (task.inputData && task.inputData.length > 0) {
                        const filteredData = task.inputData.filter(p => p && isFinite(p[0]) && isFinite(p[1]));
                        series.push({
                            name: `${task.name} (输入)`,
                            type: chartType,
                            yAxisIndex: 0,
                            data: filteredData,
                            smooth: chartType === 'line',
                            symbol: 'circle',
                            symbolSize: 3,
                            lineStyle: chartType === 'line' ? { width: 2, color: taskColor, type: 'dashed' } : undefined,
                            itemStyle: { color: taskColor }
                        });
                    }
                }

                // 输出数据
                if (this.curveVisibility.output) {
                    if (task.rawOutputRecords && task.rawOutputRecords.length > 0) {
                        let allYCols;
                        if (isAutoY) {
                            allYCols = allKeptCols.filter(c => task.rawOutputRecords[0][c] !== undefined);
                        } else {
                            allYCols = [selectedYAxis];
                        }

                        allYCols.forEach((col, colIdx) => {
                            if (!task.rawOutputRecords[0] || task.rawOutputRecords[0][col] === undefined) return;
                            const colColor = colors[(idx + colIdx) % colors.length];
                            const yIdx = isAutoY ? getColYAxisIndex(col) : 0;
                            if (yIdx === -1) return;
                            let data;
                            if (isXCategory) {
                                data = task.rawOutputRecords
                                    .filter(r => r[col] != null && typeof r[col] === 'number' && r[xAxisColumn] != null)
                                    .map(r => [String(r[xAxisColumn]), r[col]]);
                            } else {
                                data = task.rawOutputRecords
                                    .filter(r => r[col] != null && typeof r[col] === 'number')
                                    .map(r => {
                                        const csvKeys = Object.keys(task.rawOutputRecords[0]);
                                        const xVal = xAxisColumn === 'key' ? (r.key != null ? r.key : r[csvKeys[0]]) : (r[xAxisColumn] != null ? r[xAxisColumn] : 0);
                                        return [xVal, r[col]];
                                    });
                            }
                            if (data.length === 0) return;
                            const isRight = yIdx === 1;
                            series.push({
                                name: `${col} (输出)`,
                                type: chartType,
                                yAxisIndex: yIdx,
                                data: data,
                                smooth: chartType === 'line',
                                symbol: 'diamond',
                                symbolSize: 3,
                                lineStyle: chartType === 'line' ? { width: 2, color: colColor, type: isRight ? 'dotted' : 'solid' } : undefined,
                                itemStyle: { color: colColor }
                            });
                        });
                    } else if (task.calculationResult && task.calculationResult.length > 0) {
                        const filteredData = task.calculationResult.filter(p => p && isFinite(p[0]) && isFinite(p[1]));
                        series.push({
                            name: `${task.name} (输出)`,
                            type: chartType,
                            yAxisIndex: 0,
                            data: filteredData,
                            smooth: chartType === 'line',
                            symbol: 'diamond',
                            symbolSize: 3,
                            lineStyle: chartType === 'line' ? { width: 2, color: taskColor, type: 'solid' } : undefined,
                            itemStyle: { color: taskColor }
                        });
                    }
                }
            });
        }

        if (series.length === 0) return;

        // 计算主/副Y轴范围
        const primarySeries = series.filter(s => s.yAxisIndex === 0);
        const secondarySeries = series.filter(s => s.yAxisIndex === 1);

        let yMin = Infinity, yMax = -Infinity;
        primarySeries.forEach(s => {
            (s.data || []).forEach(point => {
                if (point[1] < yMin) yMin = point[1];
                if (point[1] > yMax) yMax = point[1];
            });
        });
        if (yMin === Infinity) yMin = 0;
        if (yMax === -Infinity) yMax = 100;
        const yPadding = (yMax - yMin) * 0.1 || 1;

        let y2Min = Infinity, y2Max = -Infinity;
        secondarySeries.forEach(s => {
            (s.data || []).forEach(point => {
                if (point[1] < y2Min) y2Min = point[1];
                if (point[1] > y2Max) y2Max = point[1];
            });
        });
        if (y2Min === Infinity) y2Min = 0;
        if (y2Max === -Infinity) y2Max = 100;
        const y2Padding = (y2Max - y2Min) * 0.1 || 1;

        const isTimeAxis = xAxisColumn === 'key';

        // X轴配置
        let xAxisConfig;
        if (isXCategory) {
            xAxisConfig = {
                type: 'category',
                data: categoryData,
                name: xAxisColumn,
                nameLocation: 'middle',
                nameGap: 30
            };
        } else {
            let xMin = Infinity, xMax = -Infinity;
            series.forEach(s => {
                (s.data || []).forEach(point => {
                    if (typeof point[0] === 'number') {
                        if (point[0] < xMin) xMin = point[0];
                        if (point[0] > xMax) xMax = point[0];
                    }
                });
            });
            if (xMin === Infinity) xMin = 0;
            if (xMax === -Infinity) xMax = 100;
            const xPadding = (xMax - xMin) * 0.05 || 1;
            xAxisConfig = {
                type: 'value',
                name: isTimeAxis ? '' : xAxisColumn,
                nameLocation: 'middle',
                nameGap: 30,
                min: xMin - xPadding,
                max: xMax + xPadding,
                axisLabel: {
                    formatter: (value) => {
                        if (isTimeAxis && this.isValidTimestamp(value)) {
                            return new Date(value).toLocaleString();
                        } else {
                            return String(value);
                        }
                    }
                }
            };
        }

        // Y轴配置：有右轴时用双Y轴
        const hasRightSeries = series.some(s => s.yAxisIndex === 1);
        const effectiveDualY = useDualY && hasRightSeries;
        const yAxisConfig = effectiveDualY ? [
            {
                type: 'value',
                name: globalLeftCols.join(', '),
                min: yMin - yPadding,
                max: yMax + yPadding,
                axisLabel: { formatter: v => v.toFixed(2) }
            },
            {
                type: 'value',
                name: globalRightCols.join(', '),
                min: y2Min - y2Padding,
                max: y2Max + y2Padding,
                axisLabel: { formatter: v => v.toFixed(2) }
            }
        ] : [
            {
                type: 'value',
                name: selectedYAxis || '',
                min: yMin - yPadding,
                max: yMax + yPadding,
                axisLabel: { formatter: v => v.toFixed(2) }
            }
        ];

        const option = {
            title: { text: chartType === 'bar' ? '仿真记录柱状图' : '仿真记录分析', left: 'center', top: 10, textStyle: { fontSize: 14, fontWeight: 'bold' } },
            tooltip: {
                trigger: 'axis',
                formatter: (params) => {
                    if (!params || params.length === 0) return '';
                    const xValue = params[0].value[0];
                    let xLabel;
                    if (isTimeAxis && this.isValidTimestamp(xValue)) {
                        xLabel = new Date(xValue).toLocaleString();
                    } else {
                        xLabel = String(xValue);
                    }
                    let result = `${isTimeAxis ? '时间' : xAxisColumn}: ${xLabel}<br/>`;
                    params.forEach(param => {
                        const axisLabel = param.seriesName;
                        result += `${axisLabel}: ${(param.value[1] || 0).toFixed(2)}<br/>`;
                    });
                    return result;
                }
            },
            legend: { data: series.map(s => s.name), top: 40, left: 'center', type: 'scroll' },
            grid: { left: effectiveDualY ? '10%' : '8%', right: effectiveDualY ? '10%' : '8%', bottom: '20%', top: '25%' },
            xAxis: xAxisConfig,
            yAxis: yAxisConfig,
            dataZoom: [{ type: 'inside', start: 0, end: 100 }, { start: 0, end: 100 }],
            toolbox: { right: 20, feature: { restore: {}, saveAsImage: {}, dataView: { readOnly: true } } },
            series: series
        };

        this.chart.setOption(option, true);
    }

    renderScatter() {
        if (!this.currentChartData || !this.currentChartData.tasks) return;

        const colors = ['#1890ff', '#52c41a', '#faad14', '#f5222d', '#722ed1', '#13c2c2'];
        const series = [];

        const xAxisSelect = this.shadowRoot.getElementById('xAxisSelect');
        const yAxisSelect = this.shadowRoot.getElementById('yAxisSelect');
        const selectedXAxis = xAxisSelect ? xAxisSelect.value : '';
        const selectedYAxis = yAxisSelect ? yAxisSelect.value : '';

        const xAxisColumn = selectedXAxis || this.getSmartXAxisColumn();
        const isXCategory = this.isNonNumericColumn(xAxisColumn);
        const isAutoY = !selectedYAxis;

        // 收集分类X轴的值
        let categoryData = [];
        if (isXCategory) {
            const categorySet = new Set();
            this.currentChartData.tasks.forEach(task => {
                for (const records of [task.rawInputRecords, task.rawOutputRecords]) {
                    if (records && records.length > 0) {
                        records.forEach(r => { if (r[xAxisColumn] != null) categorySet.add(String(r[xAxisColumn])); });
                    }
                }
            });
            categoryData = Array.from(categorySet);
        }

        // 智能Y轴：全局分组（输入+输出一起）
        let useDualY = false;
        let globalLeftCols = [];
        let globalRightCols = [];
        let globalGroups = [];

        if (isAutoY) {
            const g = this.getGlobalSmartYAxisColumns();
            globalGroups = g.groups;
            g.groups.forEach(grp => {
                if (grp.yAxisIndex === 0) globalLeftCols.push(...grp.cols);
                else globalRightCols.push(...grp.cols);
            });
            useDualY = globalRightCols.length > 0;
        }

        // 辅助函数：从全局分组中获取列的yAxisIndex；不在保留组中返回-1
        const getColYAxisIndex = (colName) => {
            for (const grp of globalGroups) {
                if (grp.cols.includes(colName)) return grp.yAxisIndex;
            }
            return -1;
        };

        const allKeptCols = globalGroups.flatMap(grp => grp.cols);

        this.currentChartData.tasks.forEach((task, idx) => {
            const taskColor = colors[idx % colors.length];

            // 输入数据
            if (this.curveVisibility.input) {
                if (task.rawInputRecords && task.rawInputRecords.length > 0) {
                    let yAxisColumns;
                    if (isAutoY) {
                        yAxisColumns = allKeptCols.filter(c => task.rawInputRecords[0][c] !== undefined);
                    } else {
                        yAxisColumns = [selectedYAxis];
                    }
                    yAxisColumns.forEach((col, colIdx) => {
                        if (!task.rawInputRecords[0] || task.rawInputRecords[0][col] === undefined) return;
                        const colColor = colors[(idx + colIdx) % colors.length];
                        const yIdx = isAutoY ? getColYAxisIndex(col) : 0;
                        if (yIdx === -1) return;
                        let data;
                        if (isXCategory) {
                            data = task.rawInputRecords
                                .filter(r => r[col] != null && typeof r[col] === 'number' && r[xAxisColumn] != null)
                                .map(r => [String(r[xAxisColumn]), r[col]]);
                        } else {
                            data = task.rawInputRecords
                                .filter(r => r[col] != null && typeof r[col] === 'number')
                                .map(r => {
                                    const xVal = xAxisColumn === 'key' ? r.key : (r[xAxisColumn] != null ? r[xAxisColumn] : r.key);
                                    return [xVal, r[col]];
                                });
                        }
                        if (data.length === 0) return;
                        series.push({
                            name: `${col} (输入)`,
                            type: 'scatter',
                            yAxisIndex: yIdx,
                            data: data,
                            symbolSize: 6,
                            itemStyle: { color: colColor }
                        });
                    });
                } else if (task.inputData && task.inputData.length > 0) {
                    const data = task.inputData.filter(p => p && isFinite(p[0]) && isFinite(p[1]));
                    series.push({
                        name: `${task.name} (输入)`,
                        type: 'scatter',
                        yAxisIndex: 0,
                        data: data,
                        symbolSize: 6,
                        itemStyle: { color: taskColor }
                    });
                }
            }

            // 输出数据
            if (this.curveVisibility.output) {
                if (task.rawOutputRecords && task.rawOutputRecords.length > 0) {
                    let yAxisColumns;
                    if (isAutoY) {
                        yAxisColumns = allKeptCols.filter(c => task.rawOutputRecords[0][c] !== undefined);
                    } else {
                        yAxisColumns = [selectedYAxis];
                    }
                    yAxisColumns.forEach((col, colIdx) => {
                        if (!task.rawOutputRecords[0] || task.rawOutputRecords[0][col] === undefined) return;
                        const colColor = colors[(idx + colIdx + 1) % colors.length];
                        const yIdx = isAutoY ? getColYAxisIndex(col) : 0;
                        if (yIdx === -1) return;
                        let data;
                        if (isXCategory) {
                            data = task.rawOutputRecords
                                .filter(r => r[col] != null && typeof r[col] === 'number' && r[xAxisColumn] != null)
                                .map(r => [String(r[xAxisColumn]), r[col]]);
                        } else {
                            data = task.rawOutputRecords
                                .filter(r => r[col] != null && typeof r[col] === 'number')
                                .map(r => {
                                    const csvKeys = Object.keys(task.rawOutputRecords[0]);
                                    const xVal = xAxisColumn === 'key' ? (r.key != null ? r.key : r[csvKeys[0]]) : (r[xAxisColumn] != null ? r[xAxisColumn] : 0);
                                    return [xVal, r[col]];
                                });
                        }
                        if (data.length === 0) return;
                        series.push({
                            name: `${col} (输出)`,
                            type: 'scatter',
                            yAxisIndex: yIdx,
                            data: data,
                            symbolSize: 6,
                            itemStyle: { color: colColor }
                        });
                    });
                } else if (task.calculationResult && task.calculationResult.length > 0) {
                    const data = task.calculationResult.filter(p => p && isFinite(p[0]) && isFinite(p[1]));
                    series.push({
                        name: `${task.name} (输出)`,
                        type: 'scatter',
                        yAxisIndex: 0,
                        data: data,
                        symbolSize: 6,
                        itemStyle: { color: colors[(idx + 1) % colors.length] }
                    });
                }
            }
        });

        if (series.length === 0) return;

        // 计算左/右Y轴范围
        const leftSeries = series.filter(s => s.yAxisIndex === 0);
        const rightSeries = series.filter(s => s.yAxisIndex === 1);

        let yMin = Infinity, yMax = -Infinity;
        leftSeries.forEach(s => {
            (s.data || []).forEach(p => {
                if (p[1] < yMin) yMin = p[1];
                if (p[1] > yMax) yMax = p[1];
            });
        });
        if (yMin === Infinity) yMin = 0;
        if (yMax === -Infinity) yMax = 100;
        const yPadding = (yMax - yMin) * 0.1 || 1;

        let y2Min = Infinity, y2Max = -Infinity;
        rightSeries.forEach(s => {
            (s.data || []).forEach(p => {
                if (p[1] < y2Min) y2Min = p[1];
                if (p[1] > y2Max) y2Max = p[1];
            });
        });
        if (y2Min === Infinity) y2Min = 0;
        if (y2Max === -Infinity) y2Max = 100;
        const y2Padding = (y2Max - y2Min) * 0.1 || 1;

        const isTimeAxis = xAxisColumn === 'key';
        const hasRightSeries = rightSeries.length > 0;
        const effectiveDualY = useDualY && hasRightSeries;

        // X轴配置
        let xAxisConfig;
        if (isXCategory) {
            xAxisConfig = {
                type: 'category',
                data: categoryData,
                name: xAxisColumn,
                nameLocation: 'middle',
                nameGap: 30
            };
        } else {
            let xMin = Infinity, xMax = -Infinity;
            series.forEach(s => {
                (s.data || []).forEach(p => {
                    if (typeof p[0] === 'number') {
                        if (p[0] < xMin) xMin = p[0];
                        if (p[0] > xMax) xMax = p[0];
                    }
                });
            });
            if (xMin === Infinity) xMin = 0;
            if (xMax === -Infinity) xMax = 100;
            const xPadding = (xMax - xMin) * 0.05 || 1;
            xAxisConfig = {
                type: 'value',
                name: isTimeAxis ? '' : xAxisColumn,
                nameLocation: 'middle',
                nameGap: 30,
                min: xMin - xPadding,
                max: xMax + xPadding,
                axisLabel: {
                    formatter: (value) => {
                        if (isTimeAxis && this.isValidTimestamp(value)) {
                            return new Date(value).toLocaleString();
                        } else {
                            return String(value);
                        }
                    }
                }
            };
        }

        // Y轴配置
        const yAxisConfig = effectiveDualY ? [
            {
                type: 'value',
                name: globalLeftCols.join(', '),
                nameLocation: 'middle',
                nameGap: 40,
                min: yMin - yPadding,
                max: yMax + yPadding,
                axisLabel: { formatter: v => v.toFixed(2) }
            },
            {
                type: 'value',
                name: globalRightCols.join(', '),
                nameLocation: 'middle',
                nameGap: 40,
                min: y2Min - y2Padding,
                max: y2Max + y2Padding,
                axisLabel: { formatter: v => v.toFixed(2) }
            }
        ] : [
            {
                type: 'value',
                name: selectedYAxis || '',
                nameLocation: 'middle',
                nameGap: 40,
                min: yMin - yPadding,
                max: yMax + yPadding,
                axisLabel: { formatter: v => v.toFixed(2) }
            }
        ];

        const option = {
            title: { text: '仿真记录散点图', left: 'center', top: 10, textStyle: { fontSize: 14, fontWeight: 'bold' } },
            tooltip: {
                trigger: 'item',
                formatter: (params) => {
                    let xLabel;
                    if (isTimeAxis && this.isValidTimestamp(params.value[0])) {
                        xLabel = new Date(params.value[0]).toLocaleString();
                    } else {
                        xLabel = String(params.value[0]);
                    }
                    return `${params.seriesName}<br/>${isTimeAxis ? '时间' : xAxisColumn}: ${xLabel}<br/>${selectedYAxis || '数值'}: ${params.value[1].toFixed(2)}`;
                }
            },
            legend: { data: series.map(s => s.name), top: 40, left: 'center' },
            grid: { left: effectiveDualY ? '10%' : '10%', right: effectiveDualY ? '10%' : '10%', bottom: '15%', top: '20%' },
            xAxis: xAxisConfig,
            yAxis: yAxisConfig,
            dataZoom: [{ type: 'inside', start: 0, end: 100 }, { start: 0, end: 100 }],
            toolbox: { right: 20, feature: { restore: {}, saveAsImage: {} } },
            series: series
        };

        this.chart.setOption(option, true);
    }

    renderHistogram() {
        if (!this.currentChartData || !this.currentChartData.tasks) return;

        const colors = ['#1890ff', '#52c41a', '#faad14', '#f5222d', '#722ed1', '#13c2c2'];
        const series = [];

        const yAxisSelect = this.shadowRoot.getElementById('yAxisSelect');
        const selectedYAxis = yAxisSelect ? yAxisSelect.value : '';
        const isAutoY = !selectedYAxis;

        this.currentChartData.tasks.forEach((task, idx) => {
            // 收集输出数据的直方图
            if (this.curveVisibility.output) {
                let targetColumns = [];

                if (task.rawOutputRecords && task.rawOutputRecords.length > 0) {
                    if (selectedYAxis) {
                        targetColumns = [selectedYAxis];
                    } else if (isAutoY) {
                        const smart = this.getSmartYAxisColumns(task, 'output');
                        // 为每个组的第一列生成直方图
                        targetColumns = smart.groups.map(g => g.cols[0]).filter(c => c);
                    } else {
                        const numericCols = this.getNumericColumnsForTask(task, 'output');
                        targetColumns = numericCols.length > 0 ? [numericCols[0]] : [];
                    }

                    targetColumns.forEach((targetColumn, colIdx) => {
                        if (!targetColumn || task.rawOutputRecords[0][targetColumn] === undefined) return;
                        const values = task.rawOutputRecords
                            .map(r => r[targetColumn])
                            .filter(v => v != null && typeof v === 'number');

                        if (values.length === 0) return;

                        const min = Math.min(...values);
                        const max = Math.max(...values);
                        const binCount = 20;
                        const binSize = (max - min) / binCount || 1;

                        const bins = new Array(binCount).fill(0);
                        values.forEach(value => {
                            const binIndex = Math.min(Math.floor((value - min) / binSize), binCount - 1);
                            bins[binIndex]++;
                        });

                        const data = bins.map((count, index) => ({
                            value: count,
                            binLabel: `${(min + index * binSize).toFixed(2)} ~ ${(min + (index + 1) * binSize).toFixed(2)}`
                        }));

                        series.push({
                            name: `${targetColumn} (输出)`,
                            type: 'bar',
                            data: data,
                            itemStyle: { color: colors[(idx + colIdx) % colors.length] }
                        });
                    });
                } else if (task.calculationResult && task.calculationResult.length > 0) {
                    const values = task.calculationResult.filter(p => p && isFinite(p[1])).map(p => p[1]);
                    const targetColumn = selectedYAxis || (task.outputPaths && task.outputPaths.length > 0 ? task.outputPaths[0].split('.').pop() : task.name);

                    if (values.length === 0) return;

                    const min = Math.min(...values);
                    const max = Math.max(...values);
                    const binCount = 20;
                    const binSize = (max - min) / binCount || 1;

                    const bins = new Array(binCount).fill(0);
                    values.forEach(value => {
                        const binIndex = Math.min(Math.floor((value - min) / binSize), binCount - 1);
                        bins[binIndex]++;
                    });

                    const data = bins.map((count, index) => ({
                        value: count,
                        binLabel: `${(min + index * binSize).toFixed(2)} ~ ${(min + (index + 1) * binSize).toFixed(2)}`
                    }));

                    series.push({
                        name: `${targetColumn} (输出)`,
                        type: 'bar',
                        data: data,
                        itemStyle: { color: colors[idx % colors.length] }
                    });
                }
            }

            // 输入数据直方图
            if (this.curveVisibility.input) {
                let targetColumns = [];

                if (task.rawInputRecords && task.rawInputRecords.length > 0) {
                    if (selectedYAxis) {
                        targetColumns = [selectedYAxis];
                    } else if (isAutoY) {
                        const smart = this.getSmartYAxisColumns(task, 'input');
                        targetColumns = smart.groups.map(g => g.cols[0]).filter(c => c);
                    } else {
                        targetColumns = task.inputPaths && task.inputPaths[0] ? [task.inputPaths[0]] : ['value'];
                    }

                    targetColumns.forEach((targetColumn, colIdx) => {
                        if (!targetColumn || task.rawInputRecords[0][targetColumn] === undefined) return;
                        const values = task.rawInputRecords
                            .map(r => r[targetColumn])
                            .filter(v => v != null && typeof v === 'number');

                        if (values.length === 0) return;

                        const min = Math.min(...values);
                        const max = Math.max(...values);
                        const binCount = 20;
                        const binSize = (max - min) / binCount || 1;

                        const bins = new Array(binCount).fill(0);
                        values.forEach(value => {
                            const binIndex = Math.min(Math.floor((value - min) / binSize), binCount - 1);
                            bins[binIndex]++;
                        });

                        const data = bins.map((count, index) => ({
                            value: count,
                            binLabel: `${(min + index * binSize).toFixed(2)} ~ ${(min + (index + 1) * binSize).toFixed(2)}`
                        }));

                        series.push({
                            name: `${targetColumn} (输入)`,
                            type: 'bar',
                            data: data,
                            itemStyle: { color: colors[(idx + colIdx + 3) % colors.length] }
                        });
                    });
                } else if (task.inputData && task.inputData.length > 0) {
                    const values = task.inputData.filter(p => p && isFinite(p[1])).map(p => p[1]);
                    const targetColumn = selectedYAxis || (task.inputPaths && task.inputPaths.length > 0 ? task.inputPaths[0] : task.name);

                    if (values.length === 0) return;

                    const min = Math.min(...values);
                    const max = Math.max(...values);
                    const binCount = 20;
                    const binSize = (max - min) / binCount || 1;

                    const bins = new Array(binCount).fill(0);
                    values.forEach(value => {
                        const binIndex = Math.min(Math.floor((value - min) / binSize), binCount - 1);
                        bins[binIndex]++;
                    });

                    const data = bins.map((count, index) => ({
                        value: count,
                        binLabel: `${(min + index * binSize).toFixed(2)} ~ ${(min + (index + 1) * binSize).toFixed(2)}`
                    }));

                    series.push({
                        name: `${targetColumn} (输入)`,
                        type: 'bar',
                        data: data,
                        itemStyle: { color: colors[(idx + 3) % colors.length] }
                    });
                }
            }
        });

        if (series.length === 0) return;

        // 使用按bin索引的分类X轴，使不同量级的分组各自占满整个宽度
        const binCount = 20;
        const categories = Array.from({ length: binCount }, (_, i) => String(i + 1));

        // 计算Y轴范围（频数）
        let yMax = -Infinity;
        series.forEach(s => {
            (s.data || []).forEach(d => {
                const count = typeof d === 'object' ? d.value : d;
                if (count > yMax) yMax = count;
            });
        });
        if (yMax === -Infinity) yMax = 10;
        const yPadding = yMax * 0.1 || 1;

        const option = {
            title: { text: '仿真记录直方图', left: 'center', top: 10, textStyle: { fontSize: 14, fontWeight: 'bold' } },
            tooltip: {
                trigger: 'item',
                formatter: (params) => {
                    const binLabel = params.data && params.data.binLabel ? params.data.binLabel : '';
                    return `${params.seriesName}<br/>区间: ${binLabel}<br/>频数: ${params.value}`;
                }
            },
            legend: { data: series.map(s => s.name), top: 40, left: 'center', type: 'scroll' },
            grid: { left: '10%', right: '10%', bottom: '15%', top: '20%' },
            xAxis: {
                type: 'category',
                data: categories,
                name: '区间',
                nameLocation: 'middle',
                nameGap: 30
            },
            yAxis: {
                type: 'value',
                name: '频数',
                nameLocation: 'middle',
                nameGap: 40,
                min: 0,
                max: yMax + yPadding
            },
            toolbox: { right: 20, feature: { restore: {}, saveAsImage: {} } },
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

        const chartTypeSelect = this.shadowRoot.getElementById('chartType');
        const selectedChartType = chartTypeSelect ? chartTypeSelect.value : 'line';

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

        // 直方图模式：收集所有输出值做频数分布
        if (selectedChartType === 'histogram') {
            let allValues = [];
            Object.values(pathSeriesMap).forEach(seriesData => {
                if (seriesData.type === 'output') {
                    seriesData.data.forEach(p => {
                        if (p && Array.isArray(p) && p.length === 2 && typeof p[1] === 'number') {
                            allValues.push(p[1]);
                        }
                    });
                }
            });
            if (allValues.length === 0) {
                // 如果没有输出数据，也收集输入数据
                Object.values(pathSeriesMap).forEach(seriesData => {
                    seriesData.data.forEach(p => {
                        if (p && Array.isArray(p) && p.length === 2 && typeof p[1] === 'number') {
                            allValues.push(p[1]);
                        }
                    });
                });
            }
            if (allValues.length === 0) return;

            const min = Math.min(...allValues);
            const max = Math.max(...allValues);
            const binCount = 20;
            const binSize = (max - min) / binCount || 1;
            const bins = new Array(binCount).fill(0);
            allValues.forEach(value => {
                const binIndex = Math.min(Math.floor((value - min) / binSize), binCount - 1);
                bins[binIndex]++;
            });

            const binData = bins.map((count, i) => {
                const binStart = min + i * binSize;
                const binEnd = binStart + binSize;
                return { name: `${binStart.toFixed(2)}-${binEnd.toFixed(2)}`, value: count };
            });

            const option = {
                title: { text: '多记录对比 - 直方图', left: 'center', top: 10, textStyle: { fontSize: 14, fontWeight: 'bold' } },
                tooltip: { trigger: 'axis' },
                grid: { left: '8%', right: '8%', bottom: '20%', top: '25%' },
                xAxis: { type: 'category', data: binData.map(b => b.name), axisLabel: { rotate: 45, fontSize: 10 } },
                yAxis: { type: 'value', name: '频数' },
                series: [{ type: 'bar', data: binData.map(b => b.value), itemStyle: { color: '#1890ff' } }],
                toolbox: { right: 20, feature: { restore: {}, saveAsImage: {} } }
            };
            this.chart.setOption(option, true);
            return;
        }

        const chartType = selectedChartType === 'scatter' ? 'scatter' : selectedChartType;

        Object.values(pathSeriesMap).forEach(seriesData => {
            const validData = seriesData.data.filter(p => p && Array.isArray(p) && p.length === 2 && isFinite(p[0]) && isFinite(p[1]));
            if (validData.length > 0) {
                if (seriesData.type === 'input') {
                    series.push({
                        name: `${seriesData.pathName} (${seriesData.taskName} ${seriesData.taskTimeLabel}输入)`,
                        type: chartType, data: validData, smooth: chartType === 'line', symbol: 'circle', symbolSize: chartType === 'scatter' ? 6 : 3,
                        lineStyle: chartType === 'line' ? { width: 2, color: seriesData.color, type: 'dashed' } : undefined,
                        itemStyle: { color: seriesData.color }
                    });
                } else {
                    series.push({
                        name: `${seriesData.pathName} (${seriesData.taskName} ${seriesData.taskTimeLabel}输出)`,
                        type: chartType, data: validData, smooth: chartType === 'line', symbol: 'diamond', symbolSize: chartType === 'scatter' ? 6 : 3,
                        lineStyle: chartType === 'line' ? { width: 2, color: seriesData.color, type: 'solid' } : undefined,
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
            title: { text: `多记录对比分析 - ${chartType === 'scatter' ? '散点图' : chartType === 'bar' ? '柱状图' : '相对时间'}`, left: 'center', top: 10, textStyle: { fontSize: 14, fontWeight: 'bold' } },
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
                // 使用执行顺序中的最后一个节点（最终输出节点）
                const executionOrder = parsedResult.executionOrder || Object.keys(parsedResult.results);
                const finalNodeKey = executionOrder[executionOrder.length - 1];
                if (finalNodeKey && parsedResult.results[finalNodeKey]) {
                    const nodeResult = parsedResult.results[finalNodeKey];
                    if (nodeResult.outputCsv) {
                        outputCsvData = this.parseOutputCsv(nodeResult.outputCsv);
                        outputDataFromCsv = this.convertCsvToChartData(outputCsvData);
                        console.log('从results.outputCsv解析的输出数据:', outputDataFromCsv);
                        console.log('CSV原始数据:', outputCsvData);
                    }
                }
            }

            // 如果results中没有outputCsv，尝试从nodeOutputs中提取
            if (!outputCsvData && parsedResult && parsedResult.nodeOutputs) {
                const nodeKeys = Object.keys(parsedResult.nodeOutputs);
                const lastNodeKey = nodeKeys[nodeKeys.length - 1];
                if (lastNodeKey && parsedResult.nodeOutputs[lastNodeKey]) {
                    const nodeOutput = parsedResult.nodeOutputs[lastNodeKey];
                    if (typeof nodeOutput === 'string') {
                        const csvMatch = nodeOutput.match(/=== 输出文件内容 \(output\.csv\) ===\s*\r?\n([\s\S]*?)(?=\r?\n\r?\n|$)/);
                        if (csvMatch && csvMatch[1]) {
                            outputCsvData = this.parseOutputCsv(csvMatch[1]);
                            outputDataFromCsv = this.convertCsvToChartData(outputCsvData);
                            console.log('从nodeOutputs解析的输出数据:', outputDataFromCsv);
                            console.log('CSV原始数据:', outputCsvData);
                        }
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

                    // 保存原始多列数据用于X/Y轴选择
                    task.rawInputRecords = this.buildRawRecords(inputDataFromIginX.inputData, inputPaths);
                }

                // 处理输出数据（从CSV）
                if (outputDataFromCsv) {
                    task.calculationResult = outputDataFromCsv;
                }

                // 保存CSV原始多列数据用于X/Y轴选择
                if (outputCsvData && outputCsvData.headers && outputCsvData.rows) {
                    task.rawOutputRecords = this.buildRawRecordsFromCsv(outputCsvData);
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

    // 将IginX按路径分组的输入数据转换为每行一条记录的格式（支持X/Y轴选择）
    buildRawRecords(inputDataByPath, paths) {
        // 收集所有时间戳
        const timestampSet = new Set();
        Object.values(inputDataByPath).forEach(dataPoints => {
            dataPoints.forEach(point => timestampSet.add(point.timestamp));
        });
        const timestamps = Array.from(timestampSet).sort((a, b) => a - b);

        // 构建每行记录: { key: timestamp, path1: value1, path2: value2, ... }
        return timestamps.map(ts => {
            const record = { key: ts };
            paths.forEach(path => {
                const dataPoints = inputDataByPath[path] || [];
                const point = dataPoints.find(p => p.timestamp === ts);
                record[path] = point ? point.value : null;
            });
            return record;
        });
    }

    // 将CSV数据转换为每行一条记录的格式（支持X/Y轴选择）
    buildRawRecordsFromCsv(csvData) {
        if (!csvData || !csvData.headers || !csvData.rows) return [];
        const { headers, rows } = csvData;

        return rows.map(row => {
            const record = {};
            headers.forEach((header, idx) => {
                const value = parseFloat(row[idx]);
                record[header] = isNaN(value) ? row[idx] : value;
            });
            return record;
        });
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
            // 生成报告HTML（与导出使用相同逻辑）
            const htmlContent = await this.generateReportHTML(record);

            // 上传报告到后端
            const formData = new FormData();
            formData.append('file', new Blob([htmlContent], { type: 'text/html;charset=utf-8' }), '仿真分析报告.html');
            formData.append('timestamp', record.timestamp || record.createTime);

            const uploadResult = await window.AppConfig.upload('simulationArchives', 'upload-report', formData);

            if (uploadResult.success) {
                this.showToast('报告生成并上传成功', 'success');
                
                // 打开新窗口显示报告
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

    // 生成报告HTML内容（生成报告和导出共用）
    async generateReportHTML(record) {
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
        
        // 添加算法节点信息
        if (this.currentChartData.parsedResult && this.currentChartData.parsedResult.results) {
            const nodeKeys = Object.keys(this.currentChartData.parsedResult.results);
            if (nodeKeys.length > 0) {
                pdfGenerator.addText('算法节点信息:', 12, true);
                nodeKeys.forEach(nodeKey => {
                    const nodeResult = this.currentChartData.parsedResult.results[nodeKey];
                    const nodeName = nodeResult.nodeName || nodeKey;
                    const algorithm = nodeResult.algorithm || 'N/A';
                    const version = nodeResult.version || 'N/A';
                    const calledModels = nodeResult.calledModels;
                    
                    let modelInfo = '';
                    if (calledModels) {
                        try {
                            const models = typeof calledModels === 'string' ? JSON.parse(calledModels) : calledModels;
                            if (Array.isArray(models) && models.length > 0) {
                                const modelNames = models.map(m => `${m.modelName || m.name} 版本: ${m.version}`).join(', ');
                                modelInfo = `, 模型: ${modelNames}`;
                            }
                        } catch (e) {
                            console.warn('解析calledModels失败:', e);
                        }
                    }
                    
                    pdfGenerator.addText(`  - 节点: ${nodeName}, 算法: ${algorithm}, 版本: ${version}${modelInfo}`, 12);
                });
            }
        }
        pdfGenerator.addSeparator();

        // 3. 图表分析 - 渲染所有图表类型
        pdfGenerator.addSubtitle('二、图表分析');
        const chartElement = this.shadowRoot.getElementById('analysisChart');
        const chartTypeSelect = this.shadowRoot.getElementById('chartType');
        const originalChartType = chartTypeSelect ? chartTypeSelect.value : 'line';
        const chartTypes = [
            { type: 'line', label: '折线图', desc: '趋势分析' },
            { type: 'bar', label: '柱状图', desc: '数值对比' },
            { type: 'scatter', label: '散点图', desc: '分布分析' },
            { type: 'histogram', label: '直方图', desc: '频数分布' }
        ];

        if (chartElement && this.chart) {
            for (const ct of chartTypes) {
                try {
                    // 切换图表类型并渲染
                    if (chartTypeSelect) chartTypeSelect.value = ct.type;
                    this.updateChart();
                    // 重新应用完整配置并关闭动画，强制立即完整渲染（修复散点入场动画未完成导致截图空白）
                    const fullOpt = this.chart.getOption();
                    fullOpt.animation = false;
                    this.chart.setOption(fullOpt, true);
                    await new Promise(resolve => setTimeout(resolve, 300));

                    const chartImage = this.chart.getDataURL({
                        type: 'png',
                        pixelRatio: 2,
                        backgroundColor: '#fff'
                    });
                    await pdfGenerator.addChartImage(chartImage, ct.label, `${record.name}的${ct.desc}`);
                } catch (e) {
                    console.warn(`渲染${ct.label}失败:`, e);
                    pdfGenerator.addImagePlaceholder(ct.label, `${record.name}的${ct.desc}`);
                }
            }
            // 恢复原始图表类型
            if (chartTypeSelect) chartTypeSelect.value = originalChartType;
            this.updateChart();
        } else {
            chartTypes.forEach(ct => {
                pdfGenerator.addImagePlaceholder(ct.label, `${record.name}的${ct.desc}`);
            });
        }

        // 4. 数据视图
        pdfGenerator.addSubtitle('三、数据视图');

        // 4.1 输入数据表格
        if (this.currentChartData && this.currentChartData.tasks) {
            this.currentChartData.tasks.forEach((task, taskIndex) => {
                if (task.inputData && task.inputData.length > 0) {
                    pdfGenerator.addText('输入数据', 12, true);
                    
                    const inputPaths = task.inputPaths || [];
                    
                    if (inputPaths.length > 0) {
                        // 按路径分组数据
                        const inputPathInfo = {};
                        inputPaths.forEach((path, pathIdx) => {
                            const pointsPerPath = Math.ceil(task.inputData.length / inputPaths.length);
                            const startIndex = pathIdx * pointsPerPath;
                            const endIndex = Math.min(startIndex + pointsPerPath, task.inputData.length);
                            const pathData = task.inputData.slice(startIndex, endIndex);
                            
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
                        const sampledTimestamps = this.sampleData(sortedInputTimestamps, maxRows, samplingAlgorithm);
                        
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
                        const inputRows = sampledInputData.map(p => [
                            this.isValidTimestamp(p[0]) ? new Date(p[0]).toLocaleString() : String(p[0]),
                            typeof p[1] === 'number' ? p[1].toFixed(2) : String(p[1])
                        ]);
                        
                        pdfGenerator.addTable(inputHeaders, inputRows);
                    }
                    
                    pdfGenerator.addSeparator();
                }

                // 4.2 输出数据表格
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

        pdfGenerator.addWatermark();
        return pdfGenerator.generateHTML();
    }

    // 处理导出操作
    async handleExport(record) {
        this.showToast(`正在导出仿真数据: ${record.name}`, 'info');

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
            <div style="font-size: 16px;">正在导出，请稍候...</div>
        `;
        document.body.appendChild(loadingOverlay);

        try {
            // 1. 先执行分析获取数据
            await this.handleAnalyze(record);
            
            // 等待分析完成
            await new Promise(resolve => setTimeout(resolve, 1000));

            if (!this.currentChartData) {
                this.showToast('分析失败，无法导出', 'error');
                return;
            }

            // 2. 使用与生成报告相同的逻辑生成HTML内容
            const htmlContent = await this.generateReportHTML(record);

            // 3. 上传报告到后端
            await this.uploadReportToTask(record, htmlContent);
            
            // 4. 打包并下载任务文件
            await this.packageAndDownloadTask(record);

        } catch (error) {
            console.error('导出失败:', error);
            this.showToast('导出失败，请重试', 'error');
        } finally {
            document.body.removeChild(loadingOverlay);
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

            const timestamp = record.timestamp || record.createTime;
            const url = `/api/simulation/archives/package-download?timestamp=${timestamp}`;

            // 获取token并构建认证头
            const token = localStorage.getItem('jwtToken');
            const headers = {
                'Authorization': token ? `Bearer ${token}` : ''
            };

            // 使用fetch发送请求（返回二进制数据）
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
            let fileName = `仿真导出_${record.name}_${new Date().getTime()}.zip`;
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

            this.showToast('仿真导出包下载成功！', 'success');

        } catch (error) {
            console.error('打包下载失败:', error);
            this.showToast('打包下载失败：' + error.message, 'error');
            throw error;
        }
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
