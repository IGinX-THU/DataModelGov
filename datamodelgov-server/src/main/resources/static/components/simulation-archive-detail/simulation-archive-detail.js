class SimulationArchiveDetail extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });
        this.currentArchive = null;
        this.nodes = [];
        this.edges = [];
        this.selectedNode = null;
        this.selectedEdge = null;
        this.nodeCounter = 0;
        this.currentResultTab = 'text';
        this.currentCsvNodeId = null;
        this.currentTextNodeId = null;
        this.edgeCounter = 0;
        this.isAddingEdge = false;
        this.edgeStartNode = null;
        this.isEditMode = false;
        this.executionResult = null;
        this.isRunning = false;
    }

    async connectedCallback() {
        await this.loadResources();
        this.bindEvents();
    }

    async loadResources() {
        const cssResponse = await fetch('/components/simulation-archive-detail/simulation-archive-detail.css');
        const cssContent = await cssResponse.text();
        const style = document.createElement('style');
        style.textContent = cssContent;
        this.shadowRoot.appendChild(style);

        const htmlResponse = await fetch('/components/simulation-archive-detail/simulation-archive-detail.html');
        const htmlContent = await htmlResponse.text();
        const template = document.createElement('template');
        template.innerHTML = htmlContent;
        this.shadowRoot.appendChild(template.content.cloneNode(true));
    }

    bindEvents() {
        const $ = id => this.shadowRoot.getElementById(id);

        $('backBtn')?.addEventListener('click', () => {
            this.hide();
            const list = document.getElementById('simulationArchiveList');
            if (list && list.show) list.show();
        });
        $('closeBtn')?.addEventListener('click', () => this.hide());
        $('editBtn')?.addEventListener('click', () => this.startEdit());
        $('saveBtn')?.addEventListener('click', () => this.saveArchive());
        $('cancelBtn')?.addEventListener('click', () => this.cancelEdit());

        // Graph toolbar
        $('addAlgorithmNode')?.addEventListener('click', () => this.addNode());
        $('deleteNode')?.addEventListener('click', () => this.deleteSelectedNode());
        $('addEdge')?.addEventListener('click', () => this.startAddEdge());
        $('configEdgeMapping')?.addEventListener('click', () => this.configEdgeMapping());
        $('deleteEdge')?.addEventListener('click', () => this.deleteSelectedEdge());
        $('autoLayout')?.addEventListener('click', () => this.autoLayout());
        $('clearGraph')?.addEventListener('click', () => this.clearGraph());

        // Node modal
        $('nodeModalClose')?.addEventListener('click', () => this.hideNodeModal());
        $('nodeCancelBtn')?.addEventListener('click', () => this.hideNodeModal());
        $('nodeSaveBtn')?.addEventListener('click', () => this.saveNodeConfig());
        $('editAlgorithm')?.addEventListener('click', () => this.editAlgorithmArchive());
        $('algorithmSelect')?.addEventListener('change', async () => {
            const algorithmName = $('algorithmSelect').value;
            await this.loadAlgorithmVersions(algorithmName);
            // 切换算法后也自动加载时间范围
            const algorithmVersion = $('algorithmVersion').value;
            if (algorithmName && algorithmVersion) {
                this.loadTimeRangeForAlgorithm(algorithmName, algorithmVersion);
            }
        });
        $('algorithmVersion')?.addEventListener('change', () => {
            const algorithmName = $('algorithmSelect').value;
            const algorithmVersion = $('algorithmVersion').value;
            if (algorithmName && algorithmVersion) {
                this.loadTimeRangeForAlgorithm(algorithmName, algorithmVersion);
            }
        });
        $('nodeModalMask')?.addEventListener('click', e => {
            if (e.target.id === 'nodeModalMask') this.hideNodeModal();
        });

        // Edge modal
        $('edgeModalClose')?.addEventListener('click', () => this.hideEdgeModal());
        $('edgeCancelBtn')?.addEventListener('click', () => this.hideEdgeModal());
        $('edgeSaveBtn')?.addEventListener('click', () => this.saveEdgeConfig());
        $('edgeModalMask')?.addEventListener('click', e => {
            if (e.target.id === 'edgeModalMask') this.hideEdgeModal();
        });

        // Execution panel
        $('selectAllNodes')?.addEventListener('change', e => {
            this.shadowRoot.querySelectorAll('.node-check-item input[type="checkbox"]')
                .forEach(cb => { cb.checked = e.target.checked; });
        });
        $('runBtn')?.addEventListener('click', () => this.runSimulation());
        $('stopBtn')?.addEventListener('click', () => this.stopSimulation());
        $('downloadResult')?.addEventListener('click', () => this.downloadResult());
        $('copyResult')?.addEventListener('click', () => this.copyResult());
        $('refreshLogBtn')?.addEventListener('click', () => this.refreshLog());
        $('autoRefreshLogBtn')?.addEventListener('click', () => this.toggleAutoRefreshLog());

        // Result tab switching
        this.shadowRoot.querySelectorAll('.result-tab').forEach(tab => {
            tab.addEventListener('click', () => this.switchResultTab(tab.dataset.tab));
        });
    }

    // === Show / Display ===
    async show(archive) {
        this.currentArchive = archive;
        this.style.display = 'block';
        if (archive) this.loadArchiveData(archive);
    }

    showAdd() {
        this.currentArchive = null;
        this.isEditMode = true;
        if (!this.shadowRoot) { this.style.display = 'block'; return; }
        const $ = id => this.shadowRoot.getElementById(id);

        const username = window.localStorage.getItem('username');
        const cachedProject = username ? JSON.parse(window.localStorage.getItem('currentProject_' + username) || 'null') : null;

        const setText = (id, text) => { const el = $(id); if (el) el.textContent = text; };
        setText('detailTitle', '新建仿真档案');
        setText('detailName', '-');
        setText('detailDesc', '-');
        setText('detailProjectName', cachedProject ? cachedProject.name : '-');
        setText('detailOwner', username || '-');
        setText('detailScheduleCron', '-');
        setText('detailOutputApiConfig', '-');
        setText('detailStatus', '启用');
        setText('detailUpdateTime', '-');
        setText('detailExecutionCount', '0');

        this.nodes = [];
        this.edges = [];
        this.selectedNode = null;
        this.selectedEdge = null;
        this.nodeCounter = 0;
        this.edgeCounter = 0;
        this.executionResult = null;
        this.isRunning = false;
        this.renderGraph();
        this.updateNodeCheckList();
        this.updateExecStatus();

        const fields = ['detailName', 'detailDesc', 'detailScheduleCron', 'detailOutputApiConfig', 'detailStatus'];
        fields.forEach(field => {
            const v = $(field), i = $(field + 'Input');
            if (v && i) { v.style.display = 'none'; i.style.display = 'inline-block'; i.value = ''; }
        });
        const dsi = $('detailStatusInput'); if (dsi) dsi.value = 'true';
        const ea = $('editActions'), eb = $('editBtn');
        if (ea) ea.style.display = 'flex';
        if (eb) eb.style.display = 'none';

        // 编辑页显示工具栏
        const toolbar = $('graphToolbar');
        if (toolbar) toolbar.style.display = 'flex';

        // 编辑页隐藏执行面板
        const execPanel = this.shadowRoot.querySelector('.detail-section:nth-child(2)');
        if (execPanel) execPanel.style.display = 'none';

        // Hide modals
        const nmm = $('nodeModalMask');
        if (nmm) { nmm.hidden = true; nmm.style.display = 'none'; }

        this.style.display = 'block';
    }

    async showDetail(createTime) {
        try {
            if (window.showGlobalLoading) window.showGlobalLoading('正在加载...');
            const result = await window.AppConfig.get('simulationArchives', 'detail', { createTime });
            if (result.code === 200 && result.data) {
                this.currentArchive = result.data;
                this.loadArchiveData(this.currentArchive);
                this.style.display = 'block';
            } else {
                this.showToast('未找到仿真档案', 'error');
            }
        } catch (error) {
            this.showToast('加载失败', 'error');
        } finally {
            if (window.hideGlobalLoading) window.hideGlobalLoading();
        }
    }

    loadArchiveData(archive) {
        if (!this.shadowRoot) return;
        const $ = id => this.shadowRoot.getElementById(id);
        const setText = (id, text) => { const el = $(id); if (el) el.textContent = text; };
        setText('detailTitle', archive.name || '仿真档案详情');
        setText('detailName', archive.name || '-');
        setText('detailDesc', archive.description || '-');
        setText('detailProjectName', archive.projectName || '-');
        setText('detailOwner', archive.owner || '-');
        setText('detailScheduleCron', archive.scheduleCron || '未配置');

        // 特殊处理 outputApiConfig 显示
        const apiConfigEl = $('detailOutputApiConfig');
        if (apiConfigEl) {
            if (archive.outputApiConfig) {
                try {
                    const config = JSON.parse(archive.outputApiConfig);
                    apiConfigEl.textContent = `${config.method || 'POST'} ${config.url || '未配置'}`;
                } catch (e) {
                    apiConfigEl.textContent = '配置格式错误';
                }
            } else {
                apiConfigEl.textContent = '未配置';
            }
        }

        setText('detailStatus', archive.status ? '启用' : '禁用');
        setText('detailUpdateTime', archive.updateTime ? new Date(archive.updateTime).toLocaleString('zh-CN') : '-');
        setText('detailExecutionCount', archive.executionCount || 0);

        // 先清空旧数据，避免残留
        this.nodes = [];
        this.edges = [];
        this.nodeCounter = 0;
        this.edgeCounter = 0;

        if (archive.graphJson) {
            try {
                const graphData = JSON.parse(archive.graphJson);
                this.nodes = graphData.nodes || [];
                this.edges = graphData.edges || [];
                this.nodeCounter = this.nodes.reduce((max, n) => {
                    const num = parseInt((n.nodeId || '').replace('node_', '')) || 0;
                    return num > max ? num : max;
                }, 0);
                this.edgeCounter = this.edges.reduce((max, e) => {
                    const num = parseInt((e.edgeId || '').replace('edge_', '')) || 0;
                    return num > max ? num : max;
                }, 0);
            } catch (e) {
                console.error('解析图数据失败:', e);
                this.nodes = [];
                this.edges = [];
            }
        }

        this.isRunning = archive.isRunning || false;
        this.executionResult = null;
        this.isEditMode = false;
        this.renderGraph();
        this.updateNodeCheckList();
        this.updateExecStatus();

        // 详情页隐藏工具栏
        const toolbar = $('graphToolbar');
        if (toolbar) toolbar.style.display = 'none';

        // 详情页显示执行面板
        const execPanel = this.shadowRoot.querySelector('.detail-section:nth-child(2)');
        if (execPanel) execPanel.style.display = 'block';

        // Load latest execution record
        this.loadLatestExecution();
    }

    async loadLatestExecution() {
        if (!this.currentArchive) return;
        try {
            console.log('Loading latest execution for createTime:', this.currentArchive.createTime);
            const result = await window.AppConfig.get('simulationArchives', 'execution-status', { createTime: this.currentArchive.createTime });
            console.log('Execution status result:', result);
            if (result.code === 200 && result.data) {
                console.log('Execution data:', result.data.execution);
                if (result.data.execution && result.data.execution.result) {
                    console.log('Displaying execution result');
                    this.displayResult(result.data.execution.result);
                } else {
                    console.log('No execution result found');
                }
            }
            // Load execution log
            await this.refreshLog();
        } catch (e) {
            console.error('加载最新执行记录失败:', e);
        }
    }

    // === Edit Mode ===
    // Alias for backward compatibility with simulation-archive.js
    enableEdit() { this.startEdit(); }

    startEdit() {
        this.isEditMode = true;
        if (!this.shadowRoot) return;
        const $ = id => this.shadowRoot.getElementById(id);

        const nmm = $('nodeModalMask');
        if (nmm) { nmm.hidden = true; nmm.style.display = 'none'; }

        const fields = ['detailName', 'detailDesc', 'detailScheduleCron'];
        fields.forEach(field => {
            const v = $(field), i = $(field + 'Input');
            if (v && i) {
                v.style.display = 'none';
                i.style.display = 'inline-block';
                i.value = v.textContent === '-' || v.textContent === '未配置' ? '' : v.textContent;
            }
        });

        // 特殊处理 outputApiConfig
        const apiConfigV = $('detailOutputApiConfig'), apiConfigDiv = $('detailOutputApiConfigInput');
        if (apiConfigV && apiConfigDiv) {
            apiConfigV.style.display = 'none';
            apiConfigDiv.style.display = 'block';
            // 解析JSON配置
            let config = {};
            try {
                if (apiConfigV.textContent && apiConfigV.textContent !== '-' && apiConfigV.textContent !== '未配置') {
                    config = JSON.parse(apiConfigV.textContent);
                }
            } catch (e) {
                console.warn('解析API配置失败', e);
            }
            $('outputApiUrl').value = config.url || '';
            $('outputApiMethod').value = config.method || 'POST';
            $('outputApiHeaders').value = config.headers ? JSON.stringify(config.headers, null, 2) : '';
        }

        // 特殊处理 status
        const statusV = $('detailStatus'), statusI = $('detailStatusInput');
        if (statusV && statusI) {
            statusV.style.display = 'none';
            statusI.style.display = 'inline-block';
            statusI.value = statusV.textContent === '启用' ? 'true' : 'false';
        }

        const ea = $('editActions'), eb = $('editBtn');
        if (ea) ea.style.display = 'flex';
        if (eb) eb.style.display = 'none';

        // 编辑页显示工具栏
        const toolbar = $('graphToolbar');
        if (toolbar) toolbar.style.display = 'flex';

        // 编辑页隐藏执行面板
        const execPanel = this.shadowRoot.querySelector('.detail-section:nth-child(2)');
        if (execPanel) execPanel.style.display = 'none';
    }

    cancelEdit() {
        this.isEditMode = false;
        if (!this.shadowRoot) return;
        const $ = id => this.shadowRoot.getElementById(id);
        const fields = ['detailName', 'detailDesc', 'detailScheduleCron'];
        fields.forEach(field => {
            const v = $(field), i = $(field + 'Input');
            if (v && i) { v.style.display = 'inline'; i.style.display = 'none'; }
        });

        // 特殊处理 outputApiConfig
        const apiConfigV = $('detailOutputApiConfig'), apiConfigDiv = $('detailOutputApiConfigInput');
        if (apiConfigV && apiConfigDiv) {
            apiConfigV.style.display = 'inline';
            apiConfigDiv.style.display = 'none';
        }

        // 特殊处理 status
        const statusV = $('detailStatus'), statusI = $('detailStatusInput');
        if (statusV && statusI) {
            statusV.style.display = 'inline';
            statusI.style.display = 'none';
            statusV.textContent = statusI.value === 'true' ? '启用' : '禁用';
        }

        const ea = $('editActions'), eb = $('editBtn');
        if (ea) ea.style.display = 'none';
        if (eb) eb.style.display = 'inline-block';

        // 取消编辑时隐藏工具栏，显示执行面板
        const toolbar = $('graphToolbar');
        if (toolbar) toolbar.style.display = 'none';
        const execPanel = this.shadowRoot.querySelector('.detail-section:nth-child(2)');
        if (execPanel) execPanel.style.display = 'block';
    }

    async saveArchive() {
        const $ = id => this.shadowRoot.getElementById(id);
        const name = $('detailNameInput').value.trim();
        if (!name) { this.showToast('请输入档案名称', 'error'); return; }

        try {
            if (window.showGlobalLoading) window.showGlobalLoading('正在保存...');
            const username = window.localStorage.getItem('username');
            const cachedProject = username ? JSON.parse(window.localStorage.getItem('currentProject_' + username) || 'null') : null;

            const archiveData = {
                createTime: this.currentArchive ? this.currentArchive.createTime : null,
                name,
                description: $('detailDescInput').value.trim(),
                projectName: cachedProject ? cachedProject.name : '',
                owner: username || '',
                graphJson: JSON.stringify({ nodes: this.nodes, edges: this.edges }),
                status: $('detailStatusInput').value === 'true',
                scheduleCron: $('detailScheduleCronInput').value.trim(),
                outputApiConfig: JSON.stringify({
                    url: $('outputApiUrl').value.trim(),
                    method: $('outputApiMethod').value,
                    headers: $('outputApiHeaders').value.trim() ? JSON.parse($('outputApiHeaders').value.trim()) : {}
                })
            };

            const result = await window.AppConfig.post('simulationArchives', 'save', archiveData);
            if (result.code === 200) {
                this.showToast('保存成功');
                this.currentArchive = result.data; // 使用后端返回的数据，包含正确的createTime
                this.loadArchiveData(this.currentArchive);
                this.cancelEdit();
            } else {
                this.showToast(result.message || '保存失败', 'error');
            }
        } catch (error) {
            this.showToast('网络错误', 'error');
        } finally {
            if (window.hideGlobalLoading) window.hideGlobalLoading();
        }
    }

    // === Graph Editor ===
    renderGraph() {
        const svg = this.shadowRoot.getElementById('graphSvg');
        if (!svg) return;
        svg.innerHTML = '';

        // Click on canvas background to deselect and close context menu
        svg.addEventListener('click', e => {
            if (e.target === svg) {
                this.selectedNode = null;
                this.selectedEdge = null;
                this.hideContextMenu();
                this.renderGraph();
            }
        });
        svg.addEventListener('contextmenu', e => {
            e.preventDefault();
            this.hideContextMenu();
        });

        // Arrow marker
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

        // Global drag state
        let draggingNode = null;
        let dragStartX, dragStartY;

        // Global drag event handlers
        svg.addEventListener('mousemove', e => {
            if (draggingNode) {
                draggingNode.positionX = Math.max(30, e.clientX - dragStartX);
                draggingNode.positionY = Math.max(30, e.clientY - dragStartY);
                const g = svg.querySelector(`[data-node-id="${draggingNode.nodeId}"]`);
                if (g) {
                    g.setAttribute('transform', `translate(${draggingNode.positionX}, ${draggingNode.positionY})`);
                }
                this.refreshEdges(svg);
            }
        });

        svg.addEventListener('mouseup', () => {
            draggingNode = null;
        });

        svg.addEventListener('mouseleave', () => {
            draggingNode = null;
        });

        // Render edges
        this.edges.forEach(edge => {
            const sn = this.nodes.find(n => n.nodeId === edge.sourceNodeId);
            const tn = this.nodes.find(n => n.nodeId === edge.targetNodeId);
            if (!sn || !tn) return;

            const sx = sn.positionX || 100, sy = sn.positionY || 100;
            const tx = tn.positionX || 200, ty = tn.positionY || 100;
            const dx = tx - sx, dy = ty - sy;
            const dist = Math.sqrt(dx * dx + dy * dy) || 1;
            const r = 30;

            const line = document.createElementNS('http://www.w3.org/2000/svg', 'line');
            line.setAttribute('x1', sx + (dx / dist) * r);
            line.setAttribute('y1', sy + (dy / dist) * r);
            line.setAttribute('x2', tx - (dx / dist) * r);
            line.setAttribute('y2', ty - (dy / dist) * r);
            line.setAttribute('class', 'graph-edge' + (this.selectedEdge === edge.edgeId ? ' selected' : ''));
            line.setAttribute('marker-end', 'url(#arrowhead)');
            line.addEventListener('click', e => { e.stopPropagation(); this.selectEdge(edge.edgeId); });
            line.addEventListener('dblclick', e => {
                e.stopPropagation();
                if (this.isEditMode) this.showEdgeModal(edge);
            });
            line.addEventListener('contextmenu', e => {
                e.preventDefault();
                e.stopPropagation();
                this.selectEdge(edge.edgeId);
                this.showEdgeContextMenu(edge, e.clientX, e.clientY);
            });
            svg.appendChild(line);
        });

        // Render nodes
        this.nodes.forEach(node => {
            const g = document.createElementNS('http://www.w3.org/2000/svg', 'g');
            g.setAttribute('class', 'graph-node' + (this.selectedNode === node.nodeId ? ' selected' : ''));
            g.setAttribute('data-node-id', node.nodeId);
            g.setAttribute('transform', `translate(${node.positionX || 100}, ${node.positionY || 100})`);

            const circle = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
            circle.setAttribute('r', '30');

            const text = document.createElementNS('http://www.w3.org/2000/svg', 'text');
            text.setAttribute('x', '0');
            text.setAttribute('y', '5');
            text.setAttribute('text-anchor', 'middle');
            text.textContent = node.nodeName || '算法节点';

            const algoLabel = document.createElementNS('http://www.w3.org/2000/svg', 'text');
            algoLabel.setAttribute('class', 'algo-label');
            algoLabel.setAttribute('x', '0');
            algoLabel.setAttribute('y', '50');
            algoLabel.setAttribute('text-anchor', 'middle');
            algoLabel.textContent = node.algorithmName ? `${node.algorithmName}:${node.algorithmVersion || ''}` : '未配置';

            g.appendChild(circle);
            g.appendChild(text);
            g.appendChild(algoLabel);

            g.addEventListener('mousedown', e => {
                if (this.isAddingEdge) { this.handleEdgeClick(node.nodeId); return; }
                if (!this.isEditMode) { this.selectNode(node.nodeId); e.stopPropagation(); return; }
                draggingNode = node;
                dragStartX = e.clientX - (node.positionX || 100);
                dragStartY = e.clientY - (node.positionY || 100);
                this.selectNode(node.nodeId);
                e.stopPropagation();
            });

            g.addEventListener('click', e => {
                this.selectNode(node.nodeId);
                e.stopPropagation();
            });

            g.addEventListener('dblclick', e => {
                if (this.isEditMode) this.showNodeModal(node);
                e.stopPropagation();
            });

            g.addEventListener('contextmenu', e => {
                e.preventDefault();
                e.stopPropagation();
                this.selectNode(node.nodeId);
                this.showNodeContextMenu(node, e.clientX, e.clientY);
            });

            svg.appendChild(g);
        });

        const nc = this.shadowRoot.getElementById('nodeCount');
        const ec = this.shadowRoot.getElementById('edgeCount');
        if (nc) nc.textContent = this.nodes.length;
        if (ec) ec.textContent = this.edges.length;
    }

    refreshEdges(svg) {
        svg.querySelectorAll('.graph-edge').forEach(el => el.remove());
        this.edges.forEach(edge => {
            const sn = this.nodes.find(n => n.nodeId === edge.sourceNodeId);
            const tn = this.nodes.find(n => n.nodeId === edge.targetNodeId);
            if (!sn || !tn) return;
            const sx = sn.positionX || 100, sy = sn.positionY || 100;
            const tx = tn.positionX || 200, ty = tn.positionY || 100;
            const dx = tx - sx, dy = ty - sy;
            const dist = Math.sqrt(dx * dx + dy * dy) || 1;
            const r = 30;

            const line = document.createElementNS('http://www.w3.org/2000/svg', 'line');
            line.setAttribute('x1', sx + (dx / dist) * r);
            line.setAttribute('y1', sy + (dy / dist) * r);
            line.setAttribute('x2', tx - (dx / dist) * r);
            line.setAttribute('y2', ty - (dy / dist) * r);
            line.setAttribute('class', 'graph-edge' + (this.selectedEdge === edge.edgeId ? ' selected' : ''));
            line.setAttribute('marker-end', 'url(#arrowhead)');
            line.addEventListener('click', e => { e.stopPropagation(); this.selectEdge(edge.edgeId); });
            line.addEventListener('dblclick', e => {
                e.stopPropagation();
                if (this.isEditMode) this.showEdgeModal(edge);
            });
            line.addEventListener('contextmenu', e => {
                e.preventDefault();
                e.stopPropagation();
                this.selectEdge(edge.edgeId);
                this.showEdgeContextMenu(edge, e.clientX, e.clientY);
            });

            const firstNode = svg.querySelector('.graph-node');
            if (firstNode) svg.insertBefore(line, firstNode);
            else svg.appendChild(line);
        });
    }

    addNode() {
        if (!this.isEditMode) { this.showToast('请先点击编辑按钮', 'warning'); return; }
        const node = {
            nodeId: 'node_' + (++this.nodeCounter),
            nodeName: '算法节点' + this.nodeCounter,
            algorithmName: '',
            algorithmVersion: '',
            startTime: null,
            endTime: null,
            executionParams: '{}',
            enabled: true,
            positionX: 80 + (this.nodes.length % 5) * 120,
            positionY: 80 + Math.floor(this.nodes.length / 5) * 100
        };
        this.nodes.push(node);
        this.renderGraph();
        this.updateNodeCheckList();
        this.showNodeModal(node);
    }

    deleteSelectedNode() {
        if (!this.isEditMode) { this.showToast('请先点击编辑按钮', 'warning'); return; }
        if (!this.selectedNode) { this.showToast('请先选择要删除的节点', 'error'); return; }
        this.edges = this.edges.filter(e => e.sourceNodeId !== this.selectedNode && e.targetNodeId !== this.selectedNode);
        this.nodes = this.nodes.filter(n => n.nodeId !== this.selectedNode);
        this.selectedNode = null;
        this.renderGraph();
        this.updateNodeCheckList();
    }

    selectNode(nodeId) {
        this.selectedNode = nodeId;
        this.selectedEdge = null;
        this.renderGraph();

        // 详情模式下联动执行面板的节点选择
        if (!this.isEditMode) {
            const checkbox = this.shadowRoot.querySelector(`.node-check-item input[data-node-id="${nodeId}"]`);
            if (checkbox) {
                checkbox.checked = !checkbox.checked;
            }
        }
    }
    selectEdge(edgeId) {
        this.selectedEdge = edgeId;
        this.selectedNode = null;
        this.renderGraph();
    }

    startAddEdge() {
        if (!this.isEditMode) { this.showToast('请先点击编辑按钮', 'warning'); return; }
        this.isAddingEdge = true;
        this.edgeStartNode = null;
        this.showToast('请依次点击源节点和目标节点', 'info');
    }

    configEdgeMapping() {
        if (!this.isEditMode) { this.showToast('请先点击编辑按钮', 'warning'); return; }
        if (!this.selectedEdge) { this.showToast('请先选择一条连线', 'warning'); return; }
        const edge = this.edges.find(e => e.edgeId === this.selectedEdge);
        if (edge) {
            this.showEdgeModal(edge);
        }
    }

    handleEdgeClick(nodeId) {
        if (!this.edgeStartNode) {
            this.edgeStartNode = nodeId;
            const node = this.nodes.find(n => n.nodeId === nodeId);
            this.showToast(`已选择源节点: ${node ? node.nodeName : nodeId}，请点击目标节点`);
        } else {
            if (this.edgeStartNode === nodeId) { this.showToast('不能连接到自身', 'error'); this.edgeStartNode = null; return; }
            const exists = this.edges.some(e => e.sourceNodeId === this.edgeStartNode && e.targetNodeId === nodeId);
            if (exists) { this.showToast('连线已存在', 'error'); }
            else {
                this.edges.push({ edgeId: 'edge_' + (++this.edgeCounter), sourceNodeId: this.edgeStartNode, targetNodeId: nodeId, dataMapping: '{}' });
                this.showToast('连线创建成功');
            }
            this.isAddingEdge = false;
            this.edgeStartNode = null;
            this.renderGraph();
        }
    }

    deleteSelectedEdge() {
        if (!this.isEditMode) { this.showToast('请先点击编辑按钮', 'warning'); return; }
        if (!this.selectedEdge) { this.showToast('请先选择要删除的连线', 'error'); return; }
        this.edges = this.edges.filter(e => e.edgeId !== this.selectedEdge);
        this.selectedEdge = null;
        this.renderGraph();
    }

    autoLayout() {
        if (this.nodes.length === 0) return;
        const inDegree = {};
        this.nodes.forEach(n => inDegree[n.nodeId] = 0);
        this.edges.forEach(e => { if (inDegree[e.targetNodeId] !== undefined) inDegree[e.targetNodeId]++; });
        const sorted = [...this.nodes].sort((a, b) => (inDegree[a.nodeId] || 0) - (inDegree[b.nodeId] || 0));
        sorted.forEach((node, i) => {
            node.positionX = 80 + (i % 5) * 120;
            node.positionY = 60 + Math.floor(i / 5) * 100;
        });
        this.renderGraph();
        this.showToast('自动布局完成');
    }

    clearGraph() {
        if (!this.isEditMode) { this.showToast('请先点击编辑按钮', 'warning'); return; }
        this.nodes = [];
        this.edges = [];
        this.selectedNode = null;
        this.selectedEdge = null;
        this.nodeCounter = 0;
        this.edgeCounter = 0;
        this.renderGraph();
        this.updateNodeCheckList();
    }

    getBeijingTime() {
        const now = new Date();
        const beijingTime = new Date(now.getTime() + (8 * 60 * 60 * 1000));
        const year = beijingTime.getUTCFullYear();
        const month = String(beijingTime.getUTCMonth() + 1).padStart(2, '0');
        const day = String(beijingTime.getUTCDate()).padStart(2, '0');
        const hours = String(beijingTime.getUTCHours()).padStart(2, '0');
        const minutes = String(beijingTime.getUTCMinutes()).padStart(2, '0');
        return `${year}-${month}-${day}T${hours}:${minutes}`;
    }

    // === Node Modal ===
    async showNodeModal(node) {
        const $ = id => this.shadowRoot.getElementById(id);
        $('nodeId').value = node.nodeId;
        $('nodeName').value = node.nodeName || '';
        $('startTime').value = node.startTime ? this.msToDatetimeLocal(node.startTime) : '';
        $('endTime').value = node.endTime ? this.msToDatetimeLocal(node.endTime) : this.getBeijingTime();

        await this.loadAlgorithms();
        $('algorithmSelect').value = node.algorithmName || '';

        // Load versions for the selected algorithm
        if (node.algorithmName) {
            await this.loadAlgorithmVersions(node.algorithmName);
            $('algorithmVersion').value = node.algorithmVersion || '';
        }

        // Store current node for toolbar editAlgorithm button
        this._editingNode = node;

        $('nodeModalMask').hidden = false;
        $('nodeModalMask').style.display = 'flex';
    }

    async loadTimeRangeForAlgorithm(algorithmName, algorithmVersion) {
        try {
            console.log('开始获取算法时间范围:', algorithmName, algorithmVersion);
            
            // 获取算法元数据
            const metaResult = await window.AppConfig.get('algorithm', 'metas', {
                name: algorithmName,
                version: algorithmVersion
            });
            
            if (!metaResult.success || !metaResult.data) {
                console.warn('获取算法元数据失败');
                return;
            }
            
            const algorithmMeta = metaResult.data;
            const tableName = algorithmMeta.tableName;
            const inputsBind = algorithmMeta.inputsBind;
            
            if (!tableName) {
                console.warn('算法未配置数据源表名');
                return;
            }
            
            // 构建请求参数，inputsBind需要从字符串解析为JSON数组
            let parsedInputsBind = [];
            if (inputsBind) {
                try {
                    parsedInputsBind = typeof inputsBind === 'string' ? JSON.parse(inputsBind) : inputsBind;
                } catch (e) {
                    console.warn('解析inputsBind失败:', e);
                    parsedInputsBind = [];
                }
            }
            
            const requestBody = {
                tableName: tableName,
                inputsBind: parsedInputsBind
            };
            
            console.log('时间范围查询请求:', requestBody);
            
            // 调用API获取时间范围
            const result = await window.AppConfig.post('task', 'time-range', requestBody);
            console.log('时间范围查询结果:', result);
            
            if (result.success && result.data) {
                const timeRange = result.data;
                
                if (timeRange.minKey && timeRange.maxKey) {
                    const startDate = new Date(timeRange.minKey);
                    const endDate = new Date(timeRange.maxKey);
                    const startTime = `${startDate.getFullYear()}-${String(startDate.getMonth() + 1).padStart(2, '0')}-${String(startDate.getDate()).padStart(2, '0')}T${String(startDate.getHours()).padStart(2, '0')}:${String(startDate.getMinutes()).padStart(2, '0')}`;
                    const endTime = `${endDate.getFullYear()}-${String(endDate.getMonth() + 1).padStart(2, '0')}-${String(endDate.getDate()).padStart(2, '0')}T${String(endDate.getHours()).padStart(2, '0')}:${String(endDate.getMinutes()).padStart(2, '0')}`;
                    
                    const startTimeElement = this.shadowRoot.getElementById('startTime');
                    const endTimeElement = this.shadowRoot.getElementById('endTime');
                    
                    if (startTimeElement) {
                        startTimeElement.value = startTime;
                        console.log('设置开始时间:', startTime);
                    }
                    
                    if (endTimeElement) {
                        endTimeElement.value = endTime;
                        console.log('设置结束时间:', endTime);
                    }
                    
                    this.showToast('时间范围已自动设置为数据范围', 'success');
                } else {
                    console.warn('时间范围为空，使用默认值');
                    this.showToast('未找到数据时间范围，使用默认时间', 'warning');
                    const startTimeElement = this.shadowRoot.getElementById('startTime');
                    if (startTimeElement) {
                        startTimeElement.value = '1970-01-01T08:00';
                    }
                }
            } else {
                console.warn('获取时间范围失败:', result.message);
                this.showToast('获取时间范围失败，使用默认时间', 'warning');
                const startTimeElement = this.shadowRoot.getElementById('startTime');
                if (startTimeElement) {
                    startTimeElement.value = '1970-01-01T08:00';
                }
            }
        } catch (error) {
            console.error('获取时间范围异常:', error);
            this.showToast('获取时间范围异常，使用默认时间', 'warning');
            const startTimeElement = this.shadowRoot.getElementById('startTime');
            if (startTimeElement) {
                startTimeElement.value = '1970-01-01T08:00';
            }
        }
    }

    async loadAlgorithms() {
        try {
            const select = this.shadowRoot.getElementById('algorithmSelect');
            if (!select) return;

            // 从/api/algorithm/tree接口获取算法列表
            const result = await window.AppConfig.get('algorithm', 'tree', {});
            if (!result || !result.data) {
                console.warn('获取算法树失败');
                select.innerHTML = '<option value="">请选择算法</option>';
                return;
            }

            const paths = Array.isArray(result.data) ? result.data : [result.data];
            const algorithmNames = new Set();

            paths.forEach(path => {
                if (path && path.startsWith('algorithms_system.')) {
                    const parts = path.split('.');
                    if (parts.length >= 2) {
                        // 倒数第二级是算法名，最后一级是版本
                        const algorithmName = parts[parts.length - 2];
                        if (algorithmName) {
                            algorithmNames.add(algorithmName);
                        }
                    }
                }
            });

            select.innerHTML = '<option value="">请选择算法</option>';
            Array.from(algorithmNames).sort().forEach(name => {
                const option = document.createElement('option');
                option.value = name;
                option.textContent = name;
                select.appendChild(option);
            });
        } catch (e) { console.error('加载算法列表失败:', e); }
    }

    async loadAlgorithmVersions(algorithmName) {
        const versionSelect = this.shadowRoot.getElementById('algorithmVersion');
        if (!versionSelect) return;

        if (!algorithmName) {
            versionSelect.innerHTML = '<option value="">请先选择算法</option>';
            return;
        }

        try {
            // 从/api/algorithm/tree接口获取算法版本
            const result = await window.AppConfig.get('algorithm', 'tree', {});
            if (!result || !result.data) {
                console.warn('获取算法树失败');
                versionSelect.innerHTML = '<option value="">获取版本失败</option>';
                return;
            }

            const paths = Array.isArray(result.data) ? result.data : [result.data];
            const versions = [];

            paths.forEach(path => {
                if (path && path.startsWith('algorithms_system.')) {
                    const parts = path.split('.');
                    if (parts.length >= 2) {
                        // 倒数第二级是算法名，最后一级是版本
                        const pathAlgorithmName = parts[parts.length - 2];
                        const version = parts[parts.length - 1];
                        if (pathAlgorithmName === algorithmName && version && !versions.includes(version)) {
                            versions.push(version);
                        }
                    }
                }
            });

            versionSelect.innerHTML = '<option value="">请选择版本</option>';
            versions.sort().forEach(version => {
                const option = document.createElement('option');
                option.value = version;
                option.textContent = version;
                versionSelect.appendChild(option);
            });
        } catch (e) { console.error('加载算法版本失败:', e); }
    }

    hideNodeModal() {
        const m = this.shadowRoot.getElementById('nodeModalMask');
        if (m) { m.hidden = true; m.style.display = 'none'; }
    }

    msToDatetimeLocal(ms) {
        const d = new Date(ms);
        const pad = n => String(n).padStart(2, '0');
        return `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
    }

    datetimeLocalToMs(str) {
        return new Date(str).getTime();
    }

    saveNodeConfig() {
        const $ = id => this.shadowRoot.getElementById(id);
        const node = this.nodes.find(n => n.nodeId === $('nodeId').value);
        if (!node) return;

        node.nodeName = $('nodeName').value.trim() || node.nodeName;
        node.algorithmName = $('algorithmSelect').value || '';
        node.algorithmVersion = $('algorithmVersion').value || '';

        node.startTime = $('startTime').value ? this.datetimeLocalToMs($('startTime').value) : null;
        node.endTime = $('endTime').value ? this.datetimeLocalToMs($('endTime').value) : null;

        this.renderGraph();
        this.updateNodeCheckList();
        this.hideNodeModal();
    }

    editAlgorithmArchive() {
        if (!this.selectedNode) {
            this.showToast('请先在图中选择一个算法节点', 'warning');
            return;
        }
        const node = this.nodes.find(n => n.nodeId === this.selectedNode);
        if (!node || !node.algorithmName) {
            this.showToast('该节点未配置算法', 'warning');
            return;
        }
        // Open the algorithm-edit component
        const algoEdit = document.getElementById('algorithmEdit');
        if (algoEdit && typeof algoEdit.show === 'function') {
            algoEdit.show({ name: node.algorithmName, version: node.algorithmVersion });
        } else {
            this.showToast('算法编辑组件未加载', 'error');
        }
    }

    // === Context Menu ===
    hideContextMenu() {
        const existing = this.shadowRoot.querySelector('.context-menu');
        if (existing) existing.remove();
    }

    showNodeContextMenu(node, x, y) {
        if (!this.isEditMode) return; // 详情页不显示右键菜单
        this.hideContextMenu();
        const menu = document.createElement('div');
        menu.className = 'context-menu';
        menu.style.left = x + 'px';
        menu.style.top = y + 'px';

        const items = [
            { label: '配置节点', action: () => { if (this.isEditMode) this.showNodeModal(node); } },
            { label: '编辑算法档案', action: () => this.editAlgorithmArchive() },
            { separator: true },
            { label: '删除节点', danger: true, action: () => this.deleteSelectedNode() }
        ];

        items.forEach(item => {
            if (item.separator) {
                const sep = document.createElement('div');
                sep.className = 'context-menu-separator';
                menu.appendChild(sep);
                return;
            }
            const el = document.createElement('div');
            el.className = 'context-menu-item' + (item.danger ? ' danger' : '');
            el.textContent = item.label;
            el.addEventListener('click', () => { this.hideContextMenu(); item.action(); });
            menu.appendChild(el);
        });

        this.shadowRoot.appendChild(menu);

        // Close on click outside
        const closeHandler = e => {
            if (!menu.contains(e.target)) { this.hideContextMenu(); document.removeEventListener('click', closeHandler); }
        };
        setTimeout(() => document.addEventListener('click', closeHandler), 0);
    }

    showEdgeContextMenu(edge, x, y) {
        if (!this.isEditMode) return; // 详情页不显示右键菜单
        this.hideContextMenu();
        const menu = document.createElement('div');
        menu.className = 'context-menu';
        menu.style.left = x + 'px';
        menu.style.top = y + 'px';

        const items = [
            { label: '配置数据映射', action: () => { if (this.isEditMode) this.showEdgeModal(edge); } },
            { separator: true },
            { label: '删除连线', danger: true, action: () => this.deleteSelectedEdge() }
        ];

        items.forEach(item => {
            if (item.separator) {
                const sep = document.createElement('div');
                sep.className = 'context-menu-separator';
                menu.appendChild(sep);
                return;
            }
            const el = document.createElement('div');
            el.className = 'context-menu-item' + (item.danger ? ' danger' : '');
            el.textContent = item.label;
            el.addEventListener('click', () => { this.hideContextMenu(); item.action(); });
            menu.appendChild(el);
        });

        this.shadowRoot.appendChild(menu);

        const closeHandler = e => {
            if (!menu.contains(e.target)) { this.hideContextMenu(); document.removeEventListener('click', closeHandler); }
        };
        setTimeout(() => document.addEventListener('click', closeHandler), 0);
    }

    // === Edge Modal ===
    async showEdgeModal(edge) {
        const $ = id => this.shadowRoot.getElementById(id);
        $('edgeId').value = edge.edgeId;

        // 填充源节点和目标节点下拉列表
        const sourceSelect = $('edgeSourceNode');
        const targetSelect = $('edgeTargetNode');
        sourceSelect.innerHTML = '';
        targetSelect.innerHTML = '';
        this.nodes.forEach(n => {
            const label = n.nodeName || n.nodeId;
            sourceSelect.innerHTML += `<option value="${n.nodeId}">${label}</option>`;
            targetSelect.innerHTML += `<option value="${n.nodeId}">${label}</option>`;
        });
        sourceSelect.value = edge.sourceNodeId;
        targetSelect.value = edge.targetNodeId;

        let mapping = {};
        if (edge.dataMapping) {
            try { mapping = JSON.parse(edge.dataMapping); } catch (e) { /* ignore */ }
        }
        $('edgeSourceField').value = mapping.sourceOutput || '';
        $('edgeTargetField').value = mapping.targetInput || '';

        // 节点切换时自动填充CSV文件名
        const autoFillCsvNames = async () => {
            const srcId = sourceSelect.value;
            const tgtId = targetSelect.value;
            const srcNode = this.nodes.find(n => n.nodeId === srcId);
            const tgtNode = this.nodes.find(n => n.nodeId === tgtId);
            $('edgeSourceField').placeholder = srcNode ? `${srcNode.nodeName} 的输出字段` : '源节点输出文件名';
            $('edgeTargetField').placeholder = tgtNode ? `${tgtNode.nodeName} 的输入字段` : '目标节点输入文件名';

            if (srcNode && srcNode.algorithmName && srcNode.algorithmVersion) {
                try {
                    const sourceMeta = await window.AppConfig.get('algorithm', 'metas', {
                        name: srcNode.algorithmName,
                        version: srcNode.algorithmVersion
                    });
                    if (sourceMeta && sourceMeta.success && sourceMeta.data && sourceMeta.data.outputCsvName) {
                        if (!$('edgeSourceField').value) {
                            $('edgeSourceField').value = sourceMeta.data.outputCsvName;
                        }
                    }
                } catch (e) { console.warn('获取源节点算法元数据失败', e); }
            }
            if (tgtNode && tgtNode.algorithmName && tgtNode.algorithmVersion) {
                try {
                    const targetMeta = await window.AppConfig.get('algorithm', 'metas', {
                        name: tgtNode.algorithmName,
                        version: tgtNode.algorithmVersion
                    });
                    if (targetMeta && targetMeta.success && targetMeta.data && targetMeta.data.inputCsvName) {
                        if (!$('edgeTargetField').value) {
                            $('edgeTargetField').value = targetMeta.data.inputCsvName;
                        }
                    }
                } catch (e) { console.warn('获取目标节点算法元数据失败', e); }
            }
        };
        sourceSelect.onchange = autoFillCsvNames;
        targetSelect.onchange = autoFillCsvNames;
        await autoFillCsvNames();

        $('edgeModalMask').hidden = false;
        $('edgeModalMask').style.display = 'flex';
    }

    hideEdgeModal() {
        const m = this.shadowRoot.getElementById('edgeModalMask');
        if (m) { m.hidden = true; m.style.display = 'none'; }
    }

    saveEdgeConfig() {
        const $ = id => this.shadowRoot.getElementById(id);
        const edgeId = $('edgeId').value;
        const edge = this.edges.find(e => e.edgeId === edgeId);
        if (!edge) { this.hideEdgeModal(); return; }

        const newSourceId = $('edgeSourceNode').value;
        const newTargetId = $('edgeTargetNode').value;
        if (newSourceId === newTargetId) {
            this.showToast('源节点和目标节点不能相同', 'error');
            return;
        }
        // 检查是否与其他边重复（排除自身）
        const duplicate = this.edges.some(e =>
            e.edgeId !== edgeId && e.sourceNodeId === newSourceId && e.targetNodeId === newTargetId);
        if (duplicate) {
            this.showToast('该连线已存在', 'error');
            return;
        }

        edge.sourceNodeId = newSourceId;
        edge.targetNodeId = newTargetId;

        const sourceOutput = $('edgeSourceField').value.trim();
        const targetInput = $('edgeTargetField').value.trim();
        edge.dataMapping = JSON.stringify({ sourceOutput, targetInput });
        this.hideEdgeModal();
        this.renderGraph();
    }

    // === Execution Panel ===
    updateNodeCheckList() {
        const list = this.shadowRoot.getElementById('nodeCheckList');
        if (!list) return;
        if (this.nodes.length === 0) { list.innerHTML = '<div class="empty-hint">请先添加算法节点</div>'; return; }

        // 保存当前选择状态
        const currentSelection = this.getSelectedNodeIds();

        // 按拓扑排序显示节点
        const sortedNodes = this.getTopologicalSortedNodes();

        list.innerHTML = '';
        sortedNodes.forEach(node => {
            const item = document.createElement('div');
            item.className = 'node-check-item';
            const statusClass = node.executionStatus || 'pending';
            // 显示前驱节点信息
            const predecessors = this.edges
                .filter(e => e.targetNodeId === node.nodeId)
                .map(e => this.nodes.find(n => n.nodeId === e.sourceNodeId))
                .filter(n => n)
                .map(n => n.nodeName || n.nodeId);
            const predInfo = predecessors.length > 0 ? `<span class="node-pred-info">← ${predecessors.join(', ')}</span>` : '<span class="node-pred-info">（无前驱）</span>';
            // 如果之前有选择状态，恢复选择；否则默认全选
            const isChecked = currentSelection.length > 0 ? currentSelection.includes(node.nodeId) : true;
            item.innerHTML = `<label><input type="checkbox" data-node-id="${node.nodeId}" ${isChecked ? 'checked' : ''}><span class="node-status ${statusClass}"></span>${node.nodeName || node.nodeId}${predInfo}</label>`;
            list.appendChild(item);
        });

        // 同步全选checkbox的状态
        const selectAllCheckbox = this.shadowRoot.getElementById('selectAllNodes');
        if (selectAllCheckbox) {
            const allCheckboxes = this.shadowRoot.querySelectorAll('.node-check-item input[type="checkbox"]');
            const allChecked = allCheckboxes.length > 0 && Array.from(allCheckboxes).every(cb => cb.checked);
            selectAllCheckbox.checked = allChecked;
        }
    }

    getTopologicalSortedNodes() {
        const inDegree = {};
        const adj = {};
        this.nodes.forEach(n => { inDegree[n.nodeId] = 0; adj[n.nodeId] = []; });
        this.edges.forEach(e => {
            if (inDegree[e.targetNodeId] !== undefined) {
                inDegree[e.targetNodeId]++;
                if (adj[e.sourceNodeId]) adj[e.sourceNodeId].push(e.targetNodeId);
            }
        });
        const queue = [];
        for (const [id, deg] of Object.entries(inDegree)) {
            if (deg === 0) queue.push(id);
        }
        const sorted = [];
        while (queue.length > 0) {
            const id = queue.shift();
            sorted.push(id);
            (adj[id] || []).forEach(next => {
                inDegree[next]--;
                if (inDegree[next] === 0) queue.push(next);
            });
        }
        // 如果有环，把未排序的节点也加上
        this.nodes.forEach(n => { if (!sorted.includes(n.nodeId)) sorted.push(n.nodeId); });
        return sorted.map(id => this.nodes.find(n => n.nodeId === id)).filter(Boolean);
    }

    getSelectedNodeIds() {
        return Array.from(this.shadowRoot.querySelectorAll('.node-check-item input[type="checkbox"]:checked'))
            .map(cb => cb.dataset.nodeId);
    }

    async runSimulation() {
        if (!this.currentArchive) { this.showToast('请先选择仿真档案', 'error'); return; }
        if (!this.currentArchive.createTime) { this.showToast('仿真档案ID无效，请重新加载', 'error'); return; }
        if (this.isRunning) { this.showToast('仿正在运行中', 'warning'); return; }
        const selectedNodeIds = this.getSelectedNodeIds();
        console.log('选中的节点ID:', selectedNodeIds);
        if (selectedNodeIds.length === 0) { this.showToast('请至少选择一个节点', 'error'); return; }

        // 运行前自动保存图数据，确保后端读到最新的边/节点数据
        try {
            const saveData = {
                createTime: this.currentArchive.createTime,
                name: this.currentArchive.name,
                description: this.currentArchive.description || '',
                projectName: this.currentArchive.projectName || '',
                owner: this.currentArchive.owner || '',
                graphJson: JSON.stringify({ nodes: this.nodes, edges: this.edges }),
                status: this.currentArchive.status !== false,
                scheduleCron: this.currentArchive.scheduleCron || '',
                outputApiConfig: this.currentArchive.outputApiConfig || '{}'
            };
            await window.AppConfig.post('simulationArchives', 'save', saveData);
        } catch (e) {
            console.warn('运行前自动保存图数据失败:', e);
        }

        this.isRunning = true;
        this.updateExecStatus();
        this.shadowRoot.getElementById('runBtn').disabled = true;

        try {
            const baseUrl = window.AppConfig.getApiUrl('simulationArchives', 'run-selective');
            const url = baseUrl + '?createTime=' + this.currentArchive.createTime;
            const requestBody = { selectedNodeIds };
            console.log('发送到后端的请求体:', requestBody);
            const result = await window.AppConfig.request(url, {
                method: 'POST',
                body: JSON.stringify(requestBody)
            });
            console.log('后端返回结果:', result);
            if (result.code === 200) {
                this.showToast('仿真已开始运行');
                this.pollExecutionStatus();
            } else {
                this.showToast('运行失败: ' + (result.message || '未知错误'), 'error');
                this.isRunning = false;
                this.updateExecStatus();
                this.shadowRoot.getElementById('runBtn').disabled = false;
            }
        } catch (error) {
            this.showToast('运行失败: ' + error.message, 'error');
            this.isRunning = false;
            this.updateExecStatus();
            this.shadowRoot.getElementById('runBtn').disabled = false;
        }
    }

    async stopSimulation() {
        if (!this.isRunning) return;
        try {
            const baseUrl = window.AppConfig.getApiUrl('simulationArchives', 'stop');
            const url = baseUrl + '?createTime=' + this.currentArchive.createTime;
            const result = await window.AppConfig.request(url, { method: 'POST' });
            if (result.code === 200) {
                this.showToast('仿真已停止');
                this.isRunning = false;
                this.updateExecStatus();
                this.shadowRoot.getElementById('runBtn').disabled = false;
            }
        } catch (e) { this.showToast('停止失败', 'error'); }
    }

    async pollExecutionStatus() {
        const poll = async () => {
            if (!this.isRunning) return;
            try {
                const result = await window.AppConfig.get('simulationArchives', 'execution-status', { createTime: this.currentArchive.createTime });
                if (result.code === 200 && result.data && !result.data.isRunning) {
                    this.isRunning = false;
                    this.shadowRoot.getElementById('runBtn').disabled = false;
                    if (result.data.execution && result.data.execution.result) {
                        this.displayResult(result.data.execution.result);
                    }
                    this.updateExecStatus();
                    this.stopAutoRefreshLog();
                    this.refreshLog();
                    return;
                }
                // Poll logs while running
                this.refreshLog();
            } catch (e) { console.error('轮询失败:', e); }
            setTimeout(poll, 3000);
        };
        this.startAutoRefreshLog();
        setTimeout(poll, 2000);
    }

    updateExecStatus() {
        const sv = this.shadowRoot.getElementById('execStatusValue');
        if (!sv) return;
        if (this.isRunning) {
            sv.textContent = '运行中';
            sv.className = 'status-value running';
        } else if (this.executionResult) {
            const hasFailed = Object.values(this.executionResult.results || {}).some(r => r && r.status === 'failed');
            sv.textContent = hasFailed ? '执行失败' : '执行完成';
            sv.className = 'status-value ' + (hasFailed ? 'failed' : 'completed');
        } else {
            sv.textContent = '未运行';
            sv.className = 'status-value';
        }
        // Update node statuses
        if (this.executionResult && this.executionResult.results) {
            Object.entries(this.executionResult.results).forEach(([nodeId, r]) => {
                const n = this.nodes.find(n => n.nodeId === nodeId);
                if (n) n.executionStatus = r.status;
            });
            this.updateNodeCheckList();
        }
    }

    displayResult(result) {
        this.executionResult = result;
        const ract = this.shadowRoot.getElementById('resultActions');
        const rtabs = this.shadowRoot.getElementById('resultTabs');
        if (ract) ract.style.display = 'flex';
        if (rtabs) rtabs.style.display = 'flex';

        // Display text results in tabbed format
        this.displayTextResults(result);

        // Display CSV results
        this.displayCsvResults(result);

        // Ensure only text results are shown initially
        this.switchResultTab('text');

        this.updateExecStatus();
    }

    displayTextResults(result) {
        const textArea = this.shadowRoot.getElementById('textResultArea');
        const textTabs = this.shadowRoot.getElementById('textNodeTabs');
        const textWrapper = this.shadowRoot.getElementById('textContentWrapper');
        if (!textArea || !textTabs || !textWrapper) return;

        const textData = {};
        if (result.results) {
            Object.entries(result.results).forEach(([nodeId, nr]) => {
                if (nr.outputCsv) {
                    textData[nodeId] = { name: nr.nodeName || nodeId, output: nr.outputCsv };
                }
            });
        }

        const nodeIds = Object.keys(textData);
        if (nodeIds.length === 0) {
            textArea.style.display = 'none';
            return;
        }

        // Always hide initially, let tab switching control visibility
        textArea.style.display = 'none';
        textWrapper.innerHTML = '<div class="empty-hint">暂无输出数据</div>';
        textTabs.innerHTML = '';
        nodeIds.forEach((nodeId, idx) => {
            const tab = document.createElement('button');
            tab.type = 'button';
            tab.className = 'csv-node-tab' + (idx === 0 ? ' active' : '');
            tab.textContent = textData[nodeId].name;
            tab.dataset.nodeId = nodeId;
            tab.addEventListener('click', () => {
                textTabs.querySelectorAll('.csv-node-tab').forEach(t => t.classList.remove('active'));
                tab.classList.add('active');
                this.currentTextNodeId = nodeId;
                this.renderTextContent(textData[nodeId].output);
            });
            textTabs.appendChild(tab);
        });

        // Store data for later rendering
        this.textData = textData;
    }

    renderTextContent(text) {
        const wrapper = this.shadowRoot.getElementById('textContentWrapper');
        if (!wrapper) return;
        if (!text) {
            wrapper.innerHTML = '<div class="empty-hint">暂无输出数据</div>';
            return;
        }

        const lines = text.split('\n');
        const displayLines = lines.length > 20 ? lines.slice(0, 20) : lines;
        const displayText = displayLines.join('\n');

        let html = `<pre>${displayText}</pre>`;
        if (lines.length > 20) {
            html += '<div class="csv-hint">仅显示前20行数据</div>';
        }

        wrapper.innerHTML = html;
    }

    switchResultTab(tab) {
        this.currentResultTab = tab;
        const textArea = this.shadowRoot.getElementById('textResultArea');
        const csvArea = this.shadowRoot.getElementById('csvResultArea');
        this.shadowRoot.querySelectorAll('.result-tab').forEach(t => {
            t.classList.toggle('active', t.dataset.tab === tab);
        });
        if (tab === 'text') {
            if (textArea) textArea.style.display = 'block';
            if (csvArea) csvArea.style.display = 'none';
            // Render first text node content
            if (this.textData) {
                const firstNodeId = Object.keys(this.textData)[0];
                if (firstNodeId) {
                    this.renderTextContent(this.textData[firstNodeId].output);
                }
            }
        } else {
            if (textArea) textArea.style.display = 'none';
            if (csvArea) csvArea.style.display = 'block';
            // Render first CSV node content
            if (this.csvData) {
                const firstNodeId = Object.keys(this.csvData)[0];
                if (firstNodeId) {
                    this.renderCsvTable(this.csvData[firstNodeId].csv);
                }
            }
        }
    }

    displayCsvResults(result) {
        const csvArea = this.shadowRoot.getElementById('csvResultArea');
        const csvTabs = this.shadowRoot.getElementById('csvNodeTabs');
        const csvWrapper = this.shadowRoot.getElementById('csvTableWrapper');
        if (!csvArea || !csvTabs || !csvWrapper) return;

        const csvData = {};
        if (result.results) {
            Object.entries(result.results).forEach(([nodeId, nr]) => {
                if (nr.outputCsv) {
                    csvData[nodeId] = { name: nr.nodeName || nodeId, csv: nr.outputCsv };
                }
            });
        }

        const nodeIds = Object.keys(csvData);
        if (nodeIds.length === 0) {
            csvArea.style.display = 'none';
            return;
        }

        // Always hide initially, let tab switching control visibility
        csvArea.style.display = 'none';
        csvWrapper.innerHTML = '<div class="empty-hint">暂无CSV数据</div>';
        csvTabs.innerHTML = '';
        nodeIds.forEach((nodeId, idx) => {
            const tab = document.createElement('button');
            tab.type = 'button';
            tab.className = 'csv-node-tab' + (idx === 0 ? ' active' : '');
            tab.textContent = csvData[nodeId].name;
            tab.dataset.nodeId = nodeId;
            tab.addEventListener('click', () => {
                csvTabs.querySelectorAll('.csv-node-tab').forEach(t => t.classList.remove('active'));
                tab.classList.add('active');
                this.currentCsvNodeId = nodeId;
                this.renderCsvTable(csvData[nodeId].csv);
            });
            csvTabs.appendChild(tab);
        });

        // Store data for later rendering
        this.csvData = csvData;
    }

    renderCsvTable(csvText) {
        const wrapper = this.shadowRoot.getElementById('csvTableWrapper');
        if (!wrapper || !csvText) {
            if (wrapper) wrapper.innerHTML = '<div class="empty-hint">暂无CSV数据</div>';
            return;
        }

        const lines = csvText.trim().split('\n');
        if (lines.length === 0) {
            wrapper.innerHTML = '<div class="empty-hint">CSV数据为空</div>';
            return;
        }

        // 限制只显示前20行
        const displayLines = lines.length > 20 ? lines.slice(0, 20) : lines;

        let html = '<table>';
        displayLines.forEach((line, rowIdx) => {
            const cols = line.split(',');
            html += '<tr>';
            cols.forEach(col => {
                const tag = rowIdx === 0 ? 'th' : 'td';
                html += `<${tag}>${col.trim()}</${tag}>`;
            });
            html += '</tr>';
        });
        html += '</table>';

        // 如果数据被截断，添加提示
        if (lines.length > 20) {
            html += '<div class="csv-hint">仅显示前20行数据</div>';
        }

        wrapper.innerHTML = html;
    }


    async refreshLog() {
        if (!this.currentArchive) return;
        try {
            const result = await window.AppConfig.get('simulationArchives', 'execution-log', { createTime: this.currentArchive.createTime });
            if (result.code === 200 && result.data && result.data.nodeLogs) {
                const logEl = this.shadowRoot.querySelector('#logContent pre');
                if (logEl) {
                    const logs = result.data.nodeLogs;
                    let logText = '';
                    Object.entries(logs).forEach(([nodeId, log]) => {
                        const node = this.nodes.find(n => n.nodeId === nodeId);
                        const name = node ? node.nodeName : nodeId;
                        logText += `=== 节点 ${name} ===\n${log}\n\n`;
                    });
                    if (!logText) logText = '暂无日志信息';
                    logEl.textContent = logText;
                    // Auto scroll to bottom
                    const logContent = this.shadowRoot.getElementById('logContent');
                    if (logContent) logContent.scrollTop = logContent.scrollHeight;
                }
            }
        } catch (e) { console.error('刷新日志失败:', e); }
    }

    startAutoRefreshLog() {
        if (this.logRefreshInterval) return;
        this.logRefreshInterval = setInterval(() => this.refreshLog(), 2000);
        const btn = this.shadowRoot.getElementById('autoRefreshLogBtn');
        if (btn) { btn.textContent = '自动刷新: 开启'; btn.classList.add('active'); }
    }

    stopAutoRefreshLog() {
        if (this.logRefreshInterval) {
            clearInterval(this.logRefreshInterval);
            this.logRefreshInterval = null;
        }
        const btn = this.shadowRoot.getElementById('autoRefreshLogBtn');
        if (btn) { btn.textContent = '自动刷新: 关闭'; btn.classList.remove('active'); }
    }

    toggleAutoRefreshLog() {
        if (this.logRefreshInterval) {
            this.stopAutoRefreshLog();
        } else {
            this.startAutoRefreshLog();
        }
    }

    downloadResult() {
        let content = '';
        let mimeType = 'text/plain;charset=utf-8';
        let extension = 'txt';
        let nodeName = 'result';

        if (this.currentResultTab === 'text') {
            if (this.textData && this.currentTextNodeId) {
                content = this.textData[this.currentTextNodeId].output;
                nodeName = this.textData[this.currentTextNodeId].name;
            } else if (this.textData) {
                const firstNodeId = Object.keys(this.textData)[0];
                if (firstNodeId) {
                    content = this.textData[firstNodeId].output;
                    nodeName = this.textData[firstNodeId].name;
                }
            }
        } else {
            if (this.csvData && this.currentCsvNodeId) {
                content = this.csvData[this.currentCsvNodeId].csv;
                nodeName = this.csvData[this.currentCsvNodeId].name;
            } else if (this.csvData) {
                const firstNodeId = Object.keys(this.csvData)[0];
                if (firstNodeId) {
                    content = this.csvData[firstNodeId].csv;
                    nodeName = this.csvData[firstNodeId].name;
                }
            }
            mimeType = 'text/csv;charset=utf-8';
            extension = 'csv';
        }

        if (!content) {
            this.showToast('没有可下载的内容', 'error');
            return;
        }

        const blob = new Blob([content], { type: mimeType });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `simulation_${nodeName}_${Date.now()}.${extension}`;
        a.click();
        URL.revokeObjectURL(url);
    }

    copyResult() {
        let content = '';

        if (this.currentResultTab === 'text') {
            if (this.textData && this.currentTextNodeId) {
                content = this.textData[this.currentTextNodeId].output;
            } else if (this.textData) {
                const firstNodeId = Object.keys(this.textData)[0];
                if (firstNodeId) {
                    content = this.textData[firstNodeId].output;
                }
            }
        } else {
            if (this.csvData && this.currentCsvNodeId) {
                content = this.csvData[this.currentCsvNodeId].csv;
            } else if (this.csvData) {
                const firstNodeId = Object.keys(this.csvData)[0];
                if (firstNodeId) {
                    content = this.csvData[firstNodeId].csv;
                }
            }
        }

        if (!content) {
            this.showToast('没有可复制的内容', 'error');
            return;
        }
        navigator.clipboard.writeText(content).then(() => this.showToast('已复制')).catch(() => this.showToast('复制失败', 'error'));
    }

    hide() {
        this.style.display = 'none';
        this.isEditMode = false;
        this.isRunning = false;
        this.stopAutoRefreshLog();
        this.cancelEdit();
    }

    showToast(message, type = 'success') {
        if (window.CommonUtils && window.CommonUtils.showToast) window.CommonUtils.showToast(message, type);
        else console.log(`[${type}] ${message}`);
    }
}

customElements.define('simulation-archive-detail', SimulationArchiveDetail);
