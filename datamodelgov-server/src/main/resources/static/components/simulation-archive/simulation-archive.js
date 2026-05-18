class SimulationArchive extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });
        this.data = [];
        this.pageSize = 10;
        this.currentPage = 1;
        this.totalCount = 0;
        
        // Graph data
        this.nodes = [];
        this.edges = [];
        this.selectedNode = null;
        this.selectedEdge = null;
        this.nodeCounter = 0;
        this.edgeCounter = 0;
        this.isAddingEdge = false;
        this.edgeStartNode = null;
    }

    async loadArchivesFromAPI() {
        try {
            if (window.showGlobalLoading) {
                window.showGlobalLoading('正在查询数据...');
            }

            const nameFilter = this.shadowRoot.getElementById('nameFilter')?.value.trim();
            const statusFilter = this.shadowRoot.getElementById('statusFilter')?.value;

            const result = await window.AppConfig.post('simulationArchives', 'query', {
                name: nameFilter || null,
                status: statusFilter ? statusFilter === 'active' : null,
                pageNum: this.currentPage || 1,
                pageSize: this.pageSize || 10
            });
            
            if (result.code === 200 && result.data) {
                this.data = result.data.map(archive => ({
                    id: archive.createTime,
                    name: archive.name,
                    description: archive.description,
                    status: archive.status ? 'active' : 'inactive',
                    updateTime: new Date(archive.updateTime).toLocaleString('zh-CN'),
                    executionCount: archive.executionCount || 0,
                    isRunning: archive.isRunning || false,
                    createTime: archive.createTime
                }));
                
                if (this.currentPage === 1) {
                    await this.loadArchivesCount(nameFilter, statusFilter);
                }
                
                this.renderTable();
            } else {
                this.showToast(result.message || '加载仿真档案失败', 'error');
            }
        } catch (error) {
            console.error('加载仿真档案失败:', error);
            this.showToast('网络错误，无法加载仿真档案', 'error');
        } finally {
            if (window.hideGlobalLoading) {
                window.hideGlobalLoading();
            }
        }
    }

    async loadArchivesCount(name, status) {
        try {
            const result = await window.AppConfig.post('simulationArchives', 'count', {
                name: name || null,
                status: status ? status === 'active' : null
            });
            
            if (result.code === 200 && result.data !== undefined) {
                this.totalCount = result.data;
                this.updatePagination();
            } else {
                this.totalCount = this.data.length;
            }
        } catch (error) {
            console.error('获取数据总量失败:', error);
            this.totalCount = this.data.length;
        }
    }

    async deleteArchiveFromAPI(createTime) {
        try {
            const result = await window.AppConfig.delete('simulationArchives', 'delete', { createTime });
            
            if (result.code === 200) {
                await this.loadArchivesFromAPI();
                this.showToast('仿真档案已删除');
            } else {
                this.showToast(result.message || '删除失败', 'error');
            }
        } catch (error) {
            console.error('删除仿真档案失败:', error);
            this.showToast('网络错误，删除失败', 'error');
        }
        
        this.hideModal();
    }

    async connectedCallback() {
        await this.loadResources();
        
        this.initPagination();
        
        setTimeout(() => {
            const modalMask = this.shadowRoot.getElementById('modalMask');
            if (modalMask) {
                modalMask.hidden = true;
                modalMask.style.display = 'none';
            }
            const nodeModalMask = this.shadowRoot.getElementById('nodeModalMask');
            if (nodeModalMask) {
                nodeModalMask.hidden = true;
                nodeModalMask.style.display = 'none';
            }
            this.bindEvents();
        }, 100);
    }

    async show() {
        console.log('SimulationArchive show() 被调用');
        this.style.display = 'block';

        this.currentPage = 1;
        const nameFilter = this.shadowRoot.getElementById('nameFilter');
        if (nameFilter) {
            nameFilter.value = '';
        }
        const statusFilter = this.shadowRoot.getElementById('statusFilter');
        if (statusFilter) {
            statusFilter.value = '';
        }

        setTimeout(() => {
            this.loadArchivesFromAPI().then(() => {
                this.renderTable();
            });
        }, 100);
    }

    async loadResources() {
        try {
            const cssLink = document.createElement('link');
            cssLink.rel = 'stylesheet';
            cssLink.href = './components/simulation-archive/simulation-archive.css';
            this.shadowRoot.appendChild(cssLink);
        } catch (error) {
            console.error('Failed to load CSS:', error);
        }

        if (window.location.protocol === 'file:') {
            this.shadowRoot.innerHTML += this.getFallbackHTML();
        } else {
            try {
                const response = await fetch('./components/simulation-archive/simulation-archive.html');
                if (!response.ok) {
                    throw new Error(`HTTP error! status: ${response.status}`);
                }
                const html = await response.text();
                this.shadowRoot.innerHTML += html;
                console.log('Simulation archive HTML template loaded successfully');
            } catch (error) {
                console.error('Failed to load HTML template:', error);
                this.shadowRoot.innerHTML += this.getFallbackHTML();
            }
        }
    }

    getFallbackHTML() {
        return `
<div class="simulation-archive">
    <div class="simulation-filter-card">
        <div class="filter-header">筛选</div>
        <div class="filter-rows" id="filterRows">
            <div class="filter-row">
                <div class="filter-field">
                    <span class="filter-label">档案名称</span>
                    <input class="filter-input" type="text" placeholder="请输入档案名称" id="nameFilter" />
                </div>
                <div class="filter-field">
                    <span class="filter-label">状态</span>
                    <select class="filter-input" id="statusFilter">
                        <option value="">全部</option>
                        <option value="active">启用</option>
                        <option value="inactive">禁用</option>
                    </select>
                </div>
            </div>
        </div>
        <div class="filter-actions">
            <div class="filter-spacer"></div>
            <button class="filter-btn outline" type="button" id="resetFilters">重置</button>
            <button class="filter-btn solid" type="button" id="applyFilters">查询</button>
        </div>
    </div>

    <div class="simulation-table-card">
        <div class="table-toolbar">
            <button class="toolbar-btn green" type="button" id="addArchiveBtn">新增仿真档案</button>
        </div>
        <div class="table-wrapper">
            <table class="data-table">
                <thead>
                    <tr>
                        <th>档案名称</th>
                        <th>描述</th>
                        <th>状态</th>
                        <th>最后修改时间</th>
                        <th>执行次数</th>
                        <th>操作</th>
                    </tr>
                </thead>
                <tbody id="tableBody"></tbody>
            </table>
        </div>
        <div class="pagination">
            <div class="pagination-left">
                <button class="page-btn" id="prevPage">&lt;</button>
                <div class="page-list" id="pageList"></div>
                <button class="page-btn" id="nextPage">&gt;</button>
            </div>
            <div class="pagination-right">
                <span class="total-count">共 <span id="totalCount">0</span> 条</span>
                <select class="page-size-select" id="pageSizeSelect">
                    <option value="5">5条/页</option>
                    <option value="10" selected>10条/页</option>
                    <option value="20">20条/页</option>
                    <option value="50">50条/页</option>
                </select>
            </div>
        </div>
    </div>
</div>`;
    }

    bindEvents() {
        if (this._eventsBound) {
            return;
        }
        this._eventsBound = true;

        this.shadowRoot.getElementById('resetFilters')?.addEventListener('click', () => this.resetFilters());
        this.shadowRoot.getElementById('applyFilters')?.addEventListener('click', () => this.applyFilters());

        this.shadowRoot.addEventListener('click', (e) => {
            const btn = e.target.closest('.toolbar-btn');
            if (!btn) return;

            switch (btn.id) {
                case 'addArchiveBtn':
                    this.showAddModal();
                    break;
            }
        });

        this.shadowRoot.addEventListener('click', (e) => {
            if (e.target.id === 'modalClose' || e.target.closest('#modalClose')) {
                this.hideModal();
            }
            if (e.target.id === 'cancelBtn' || e.target.closest('#cancelBtn')) {
                this.hideModal();
            }
        });

        this.shadowRoot.getElementById('saveBtn')?.addEventListener('click', () => this.saveArchive());

        // Table action buttons
        this.shadowRoot.addEventListener('click', (e) => {
            if (e.target.classList.contains('action-btn')) {
                const action = e.target.dataset.action;
                const id = e.target.dataset.id;
                
                switch (action) {
                    case 'run':
                        this.runSimulation(id);
                        break;
                    case 'stop':
                        this.stopSimulation(id);
                        break;
                    case 'copy':
                        this.copyArchive(id);
                        break;
                    case 'edit':
                        this.editArchive(id);
                        break;
                    case 'delete':
                        this.deleteArchive(id);
                        break;
                }
            }
        });

        // Graph toolbar buttons
        this.shadowRoot.getElementById('addAlgorithmNode')?.addEventListener('click', () => this.addNode('algorithm'));
        this.shadowRoot.getElementById('addModelNode')?.addEventListener('click', () => this.addNode('model'));
        this.shadowRoot.getElementById('addDataNode')?.addEventListener('click', () => this.addNode('data'));
        this.shadowRoot.getElementById('deleteNode')?.addEventListener('click', () => this.deleteSelectedNode());
        this.shadowRoot.getElementById('addEdge')?.addEventListener('click', () => this.startAddEdge());
        this.shadowRoot.getElementById('deleteEdge')?.addEventListener('click', () => this.deleteSelectedEdge());
        this.shadowRoot.getElementById('clearGraph')?.addEventListener('click', () => this.clearGraph());

        // Node modal
        this.shadowRoot.getElementById('nodeModalClose')?.addEventListener('click', () => this.hideNodeModal());
        this.shadowRoot.getElementById('nodeCancelBtn')?.addEventListener('click', () => this.hideNodeModal());
        this.shadowRoot.getElementById('nodeSaveBtn')?.addEventListener('click', () => this.saveNodeConfig());
    }

    initPagination() {
        const pagination = this.shadowRoot.querySelector('#pagination');
        if (pagination && pagination.init) {
            pagination.init({
                pageSize: this.pageSize,
                total: this.totalCount,
                onPageChange: (page) => {
                    this.currentPage = page;
                    this.loadArchivesFromAPI();
                }
            });
        }
    }

    updatePagination() {
        const pagination = this.shadowRoot.querySelector('#pagination');
        if (pagination && pagination.update) {
            pagination.update({
                pageSize: this.pageSize,
                total: this.totalCount,
                current: this.currentPage
            });
        }
    }

    resetFilters() {
        const nameFilter = this.shadowRoot.getElementById('nameFilter');
        if (nameFilter) {
            nameFilter.value = '';
        }
        const statusFilter = this.shadowRoot.getElementById('statusFilter');
        if (statusFilter) {
            statusFilter.value = '';
        }
        this.currentPage = 1;
        this.loadArchivesFromAPI();
    }

    async applyFilters() {
        this.currentPage = 1;
        await this.loadArchivesFromAPI();
    }

    renderTable() {
        const tbody = this.shadowRoot.getElementById('tableBody');
        if (!tbody) return;

        tbody.innerHTML = this.data.map(item => `
            <tr>
                <td>${item.name}</td>
                <td>${item.description || '-'}</td>
                <td>
                    <span class="status-badge ${item.status}">
                        ${item.status === 'active' ? '启用' : '禁用'}
                    </span>
                </td>
                <td>${item.updateTime}</td>
                <td>${item.executionCount}</td>
                <td>
                    <div class="action-buttons">
                        ${item.isRunning ? 
                            `<button class="action-btn stop" data-action="stop" data-id="${item.id}">停止</button>` :
                            `<button class="action-btn run" data-action="run" data-id="${item.id}">运行</button>`
                        }
                        <button class="action-btn copy" data-action="copy" data-id="${item.id}">复制</button>
                        <button class="action-btn edit" data-action="edit" data-id="${item.id}">编辑</button>
                        <button class="action-btn delete" data-action="delete" data-id="${item.id}">删除</button>
                    </div>
                </td>
            </tr>
        `).join('');

        this.updatePagination();
    }

    showAddModal() {
        const modal = this.shadowRoot.getElementById('modalMask');
        const title = this.shadowRoot.getElementById('modalTitle');
        const form = this.shadowRoot.getElementById('archiveForm');
        
        if (modal && title && form) {
            title.textContent = '新增仿真档案';
            form.reset();
            this.clearGraph();
            modal.hidden = false;
            modal.style.display = 'flex';
        }
    }

    showEditModal(archive) {
        const modal = this.shadowRoot.getElementById('modalMask');
        const title = this.shadowRoot.getElementById('modalTitle');
        const form = this.shadowRoot.getElementById('archiveForm');
        
        if (modal && title && form) {
            title.textContent = '编辑仿真档案';
            
            this.shadowRoot.getElementById('archiveName').value = archive.name;
            this.shadowRoot.getElementById('archiveDesc').value = archive.description || '';
            this.shadowRoot.getElementById('scheduleCron').value = archive.scheduleCron || '';
            this.shadowRoot.getElementById('outputApiConfig').value = archive.outputApiConfig || '';
            
            this.shadowRoot.getElementById('status').value = archive.status === 'active' ? 'true' : 'false';

            // Load graph
            if (archive.graphJson) {
                try {
                    const graphData = JSON.parse(archive.graphJson);
                    this.nodes = graphData.nodes || [];
                    this.edges = graphData.edges || [];
                    this.renderGraph();
                } catch (e) {
                    console.error('Failed to parse graph JSON:', e);
                    this.clearGraph();
                }
            } else {
                this.clearGraph();
            }

            modal.hidden = false;
            modal.style.display = 'flex';
        }
    }

    hideModal() {
        const modal = this.shadowRoot.getElementById('modalMask');
        if (modal) {
            modal.hidden = true;
            modal.style.display = 'none';
        }
    }

    async saveArchive() {
        const form = this.shadowRoot.getElementById('archiveForm');
        const name = this.shadowRoot.getElementById('archiveName').value.trim();
        
        if (!name) {
            this.showToast('请输入档案名称', 'error');
            return;
        }

        const status = this.shadowRoot.getElementById('status').value === 'true';
        
        const archiveData = {
            name: name,
            description: this.shadowRoot.getElementById('archiveDesc').value.trim(),
            graphJson: JSON.stringify({ nodes: this.nodes, edges: this.edges }),
            status: status,
            scheduleCron: this.shadowRoot.getElementById('scheduleCron').value.trim(),
            outputApiConfig: this.shadowRoot.getElementById('outputApiConfig').value.trim()
        };

        try {
            if (window.showGlobalLoading) {
                window.showGlobalLoading('正在保存...');
            }

            const result = await window.AppConfig.post('simulationArchives', 'save', archiveData);
            
            if (result.code === 200) {
                this.showToast('仿真档案保存成功');
                this.hideModal();
                await this.loadArchivesFromAPI();
            } else {
                this.showToast(result.message || '保存失败', 'error');
            }
        } catch (error) {
            console.error('保存仿真档案失败:', error);
            this.showToast('网络错误，保存失败', 'error');
        } finally {
            if (window.hideGlobalLoading) {
                window.hideGlobalLoading();
            }
        }
    }

    editArchive(id) {
        const archive = this.data.find(a => a.id == id);
        if (archive) {
            this.showEditModal(archive);
        }
    }

    deleteArchive(id) {
        const archive = this.data.find(a => a.id == id);
        if (archive) {
            this.showConfirmModal('确认删除', `确定要删除仿真档案"${archive.name}"吗？`, () => {
                this.deleteArchiveFromAPI(id);
            });
        }
    }

    async runSimulation(id) {
        try {
            if (window.showGlobalLoading) {
                window.showGlobalLoading('正在启动仿真...');
            }

            const result = await window.AppConfig.post('simulationArchives', 'run', { createTime: id });
            
            if (result.code === 200) {
                this.showToast('仿真已开始运行');
                await this.loadArchivesFromAPI();
            } else {
                this.showToast(result.message || '启动失败', 'error');
            }
        } catch (error) {
            console.error('运行仿真失败:', error);
            this.showToast('网络错误，启动失败', 'error');
        } finally {
            if (window.hideGlobalLoading) {
                window.hideGlobalLoading();
            }
        }
    }

    async stopSimulation(id) {
        try {
            if (window.showGlobalLoading) {
                window.showGlobalLoading('正在停止仿真...');
            }

            const result = await window.AppConfig.post('simulationArchives', 'stop', { createTime: id });
            
            if (result.code === 200) {
                this.showToast('仿真已停止');
                await this.loadArchivesFromAPI();
            } else {
                this.showToast(result.message || '停止失败', 'error');
            }
        } catch (error) {
            console.error('停止仿真失败:', error);
            this.showToast('网络错误，停止失败', 'error');
        } finally {
            if (window.hideGlobalLoading) {
                window.hideGlobalLoading();
            }
        }
    }

    async copyArchive(id) {
        const archive = this.data.find(a => a.id == id);
        if (!archive) return;

        const newName = prompt('请输入新档案名称:', archive.name + ' (副本)');
        if (!newName) return;

        try {
            if (window.showGlobalLoading) {
                window.showGlobalLoading('正在复制...');
            }

            const result = await window.AppConfig.post('simulationArchives', 'copy', { 
                createTime: id, 
                newName: newName 
            });
            
            if (result.code === 200) {
                this.showToast('仿真档案复制成功');
                await this.loadArchivesFromAPI();
            } else {
                this.showToast(result.message || '复制失败', 'error');
            }
        } catch (error) {
            console.error('复制仿真档案失败:', error);
            this.showToast('网络错误，复制失败', 'error');
        } finally {
            if (window.hideGlobalLoading) {
                window.hideGlobalLoading();
            }
        }
    }

    // Graph Editor Methods
    initGraphEditor() {
        const svg = this.shadowRoot.getElementById('graphSvg');
        if (!svg) return;

        // Add zoom and pan support could be added here
        this.renderGraph();
    }

    renderGraph() {
        const svg = this.shadowRoot.getElementById('graphSvg');
        if (!svg) return;

        // Clear existing content
        svg.innerHTML = '';

        // Add defs for arrow markers
        const defs = document.createElementNS('http://www.w3.org/2000/svg', 'defs');
        const marker = document.createElementNS('http://www.w3.org/2000/svg', 'marker');
        marker.setAttribute('id', 'arrowhead');
        marker.setAttribute('markerWidth', '10');
        marker.setAttribute('markerHeight', '7');
        marker.setAttribute('refX', '10');
        marker.setAttribute('refY', '3.5');
        marker.setAttribute('orient', 'auto');
        const polygon = document.createElementNS('http://www.w3.org/2000/svg', 'polygon');
        polygon.setAttribute('points', '0 0, 10 3.5, 0 7');
        polygon.setAttribute('class', 'graph-edge-marker');
        marker.appendChild(polygon);
        defs.appendChild(marker);
        svg.appendChild(defs);

        // Render edges
        this.edges.forEach(edge => {
            const sourceNode = this.nodes.find(n => n.nodeId === edge.sourceNodeId);
            const targetNode = this.nodes.find(n => n.nodeId === edge.targetNodeId);
            
            if (sourceNode && targetNode) {
                const line = document.createElementNS('http://www.w3.org/2000/svg', 'line');
                line.setAttribute('x1', sourceNode.positionX || 100);
                line.setAttribute('y1', sourceNode.positionY || 100);
                line.setAttribute('x2', targetNode.positionX || 200);
                line.setAttribute('y2', targetNode.positionY || 100);
                line.setAttribute('class', 'graph-edge' + (this.selectedEdge === edge.edgeId ? ' selected' : ''));
                line.setAttribute('marker-end', 'url(#arrowhead)');
                line.setAttribute('data-edge-id', edge.edgeId);
                
                line.addEventListener('click', (e) => {
                    e.stopPropagation();
                    this.selectEdge(edge.edgeId);
                });
                
                svg.appendChild(line);
            }
        });

        // Render nodes
        this.nodes.forEach(node => {
            const g = document.createElementNS('http://www.w3.org/2000/svg', 'g');
            g.setAttribute('class', 'graph-node ' + node.nodeType + (this.selectedNode === node.nodeId ? ' selected' : ''));
            g.setAttribute('data-node-id', node.nodeId);
            g.setAttribute('transform', `translate(${node.positionX || 100}, ${node.positionY || 100})`);

            const circle = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
            circle.setAttribute('r', '30');
            
            const text = document.createElementNS('http://www.w3.org/2000/svg', 'text');
            text.setAttribute('x', '0');
            text.setAttribute('y', '45');
            text.setAttribute('text-anchor', 'middle');
            text.textContent = node.nodeName || node.nodeType;

            g.appendChild(circle);
            g.appendChild(text);

            // Make node draggable
            let isDragging = false;
            let startX, startY;

            g.addEventListener('mousedown', (e) => {
                if (this.isAddingEdge) {
                    this.handleEdgeClick(node.nodeId);
                    return;
                }
                
                isDragging = true;
                startX = e.clientX - (node.positionX || 100);
                startY = e.clientY - (node.positionY || 100);
                this.selectNode(node.nodeId);
                e.stopPropagation();
            });

            g.addEventListener('click', (e) => {
                if (!isDragging) {
                    this.selectNode(node.nodeId);
                    if (!this.isAddingEdge) {
                        this.showNodeModal(node);
                    }
                }
                e.stopPropagation();
            });

            svg.addEventListener('mousemove', (e) => {
                if (isDragging) {
                    node.positionX = e.clientX - startX;
                    node.positionY = e.clientY - startY;
                    g.setAttribute('transform', `translate(${node.positionX}, ${node.positionY})`);
                    this.renderGraph();
                }
            });

            svg.addEventListener('mouseup', () => {
                isDragging = false;
            });

            svg.appendChild(g);
        });

        // Update info
        this.shadowRoot.getElementById('nodeCount').textContent = this.nodes.length;
        this.shadowRoot.getElementById('edgeCount').textContent = this.edges.length;
    }

    addNode(type) {
        const node = {
            nodeId: 'node_' + (++this.nodeCounter),
            nodeName: type === 'algorithm' ? '算法' + this.nodeCounter : 
                     type === 'model' ? '模型' + this.nodeCounter : '数据' + this.nodeCounter,
            nodeType: type,
            resourceName: '',
            resourceVersion: '',
            positionX: 100 + Math.random() * 300,
            positionY: 100 + Math.random() * 200
        };
        
        this.nodes.push(node);
        this.renderGraph();
    }

    deleteSelectedNode() {
        if (!this.selectedNode) {
            this.showToast('请先选择要删除的节点', 'error');
            return;
        }

        // Remove edges connected to this node
        this.edges = this.edges.filter(e => 
            e.sourceNodeId !== this.selectedNode && e.targetNodeId !== this.selectedNode
        );

        // Remove node
        this.nodes = this.nodes.filter(n => n.nodeId !== this.selectedNode);
        this.selectedNode = null;
        
        this.renderGraph();
    }

    selectNode(nodeId) {
        this.selectedNode = nodeId;
        this.selectedEdge = null;
        this.renderGraph();
    }

    selectEdge(edgeId) {
        this.selectedEdge = edgeId;
        this.selectedNode = null;
        this.renderGraph();
    }

    startAddEdge() {
        this.isAddingEdge = true;
        this.edgeStartNode = null;
        this.showToast('请依次点击两个节点以创建连线', 'info');
    }

    handleEdgeClick(nodeId) {
        if (!this.edgeStartNode) {
            this.edgeStartNode = nodeId;
            this.showToast('请选择目标节点');
        } else {
            if (this.edgeStartNode === nodeId) {
                this.showToast('不能连接到自身', 'error');
                this.edgeStartNode = null;
                return;
            }

            // Check if edge already exists
            const exists = this.edges.some(e => 
                e.sourceNodeId === this.edgeStartNode && e.targetNodeId === nodeId
            );

            if (exists) {
                this.showToast('连线已存在', 'error');
            } else {
                const edge = {
                    edgeId: 'edge_' + (++this.edgeCounter),
                    sourceNodeId: this.edgeStartNode,
                    targetNodeId: nodeId,
                    dataMapping: '{}'
                };
                this.edges.push(edge);
                this.showToast('连线创建成功');
            }

            this.isAddingEdge = false;
            this.edgeStartNode = null;
            this.renderGraph();
        }
    }

    deleteSelectedEdge() {
        if (!this.selectedEdge) {
            this.showToast('请先选择要删除的连线', 'error');
            return;
        }

        this.edges = this.edges.filter(e => e.edgeId !== this.selectedEdge);
        this.selectedEdge = null;
        
        this.renderGraph();
    }

    clearGraph() {
        this.nodes = [];
        this.edges = [];
        this.selectedNode = null;
        this.selectedEdge = null;
        this.nodeCounter = 0;
        this.edgeCounter = 0;
        this.renderGraph();
    }

    async showNodeModal(node) {
        const modal = this.shadowRoot.getElementById('nodeModalMask');
        const form = this.shadowRoot.getElementById('nodeForm');
        
        if (modal && form) {
            this.shadowRoot.getElementById('nodeId').value = node.nodeId;
            this.shadowRoot.getElementById('nodeName').value = node.nodeName;
            this.shadowRoot.getElementById('nodeType').value = node.nodeType;
            this.shadowRoot.getElementById('resourceName').value = node.resourceName || '';
            this.shadowRoot.getElementById('resourceVersion').value = node.resourceVersion || '';
            
            // 根据节点类型显示不同的配置区域
            const algorithmSection = this.shadowRoot.getElementById('algorithmSection');
            const resourceSection = this.shadowRoot.getElementById('resourceSection');
            
            if (node.nodeType === 'algorithm') {
                algorithmSection.style.display = 'block';
                resourceSection.style.display = 'none';
                // 加载算法列表
                await this.loadAlgorithms();
                // 加载数据源列表
                await this.loadDataSources();
                // 设置已有值
                this.shadowRoot.getElementById('algorithmSelect').value = node.algorithmName || '';
                this.shadowRoot.getElementById('inputDataSource').value = node.inputDataSource || '';
                this.shadowRoot.getElementById('inputDataTable').value = node.inputDataTable || '';
            } else {
                algorithmSection.style.display = 'none';
                resourceSection.style.display = 'block';
            }
            
            modal.hidden = false;
            modal.style.display = 'flex';
        }
    }

    async loadAlgorithms() {
        try {
            const result = await window.AppConfig.post('algorithm', 'metas', {});
            const select = this.shadowRoot.getElementById('algorithmSelect');
            if (select && result.code === 200 && result.data) {
                select.innerHTML = '<option value="">请选择算法</option>';
                select.innerHTML += `<option value="${result.data.name}_${result.data.version}">${result.data.name} (${result.data.version})</option>`;
            }
        } catch (error) {
            console.error('加载算法列表失败:', error);
        }
    }

    async loadDataSources() {
        try {
            const result = await window.AppConfig.post('dataSource', 'list', {});
            const select = this.shadowRoot.getElementById('inputDataSource');
            if (select && result.code === 200 && result.data) {
                select.innerHTML = '<option value="">请选择数据源</option>';
                result.data.forEach(ds => {
                    select.innerHTML += `<option value="${ds.name}">${ds.name}</option>`;
                });
            }
        } catch (error) {
            console.error('加载数据源列表失败:', error);
        }
    }

    hideNodeModal() {
        const modal = this.shadowRoot.getElementById('nodeModalMask');
        if (modal) {
            modal.hidden = true;
            modal.style.display = 'none';
        }
    }

    saveNodeConfig() {
        const nodeId = this.shadowRoot.getElementById('nodeId').value;
        const nodeName = this.shadowRoot.getElementById('nodeName').value.trim();
        const nodeType = this.shadowRoot.getElementById('nodeType').value;
        const resourceName = this.shadowRoot.getElementById('resourceName').value.trim();
        const resourceVersion = this.shadowRoot.getElementById('resourceVersion').value.trim();

        const node = this.nodes.find(n => n.nodeId === nodeId);
        if (node) {
            node.nodeName = nodeName;
            node.nodeType = nodeType;
            
            if (nodeType === 'algorithm') {
                const algorithmSelect = this.shadowRoot.getElementById('algorithmSelect').value;
                const inputDataSource = this.shadowRoot.getElementById('inputDataSource').value;
                const inputDataTable = this.shadowRoot.getElementById('inputDataTable').value;
                
                if (algorithmSelect) {
                    const [algorithmName, algorithmVersion] = algorithmSelect.split('_');
                    node.algorithmName = algorithmName;
                    node.algorithmVersion = algorithmVersion;
                    node.resourceName = algorithmName;
                    node.resourceVersion = algorithmVersion;
                }
                node.inputDataSource = inputDataSource;
                node.inputDataTable = inputDataTable;
            } else {
                node.resourceName = resourceName;
                node.resourceVersion = resourceVersion;
            }
            
            this.renderGraph();
            this.hideNodeModal();
        }
    }

    showConfirmModal(title, message, onConfirm) {
        // Simple confirm dialog
        if (confirm(message)) {
            onConfirm();
        }
    }

    showToast(message, type = 'success') {
        if (window.CommonUtils && window.CommonUtils.showToast) {
            window.CommonUtils.showToast(message, type);
        } else {
            console.warn('CommonUtils.showToast not available, falling back to console.log');
            console[type === 'error' ? 'error' : type === 'warning' ? 'warn' : 'log'](`[${type}] ${message}`);
        }
    }

    hide() {
        this.style.display = 'none';
        this.removeAttribute('show');
        this.hideModal();
    }
}

customElements.define('simulation-archive', SimulationArchive);
