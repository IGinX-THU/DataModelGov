class SimulationArchiveDetail extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });
        this.currentArchive = null;
        
        // Graph data
        this.nodes = [];
        this.edges = [];
        this.selectedNode = null;
        this.selectedEdge = null;
        this.nodeCounter = 0;
        this.edgeCounter = 0;
        this.isAddingEdge = false;
        this.edgeStartNode = null;
        this.isEditMode = false;
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
        const backBtn = this.shadowRoot.getElementById('backBtn');
        if (backBtn) {
            backBtn.addEventListener('click', () => {
                this.hide();
                const simulationArchiveList = document.getElementById('simulationArchiveList');
                if (simulationArchiveList && simulationArchiveList.show) {
                    simulationArchiveList.show();
                }
            });
        }

        const closeBtn = this.shadowRoot.getElementById('closeBtn');
        if (closeBtn) {
            closeBtn.addEventListener('click', () => {
                this.hide();
            });
        }

        const editBtn = this.shadowRoot.getElementById('editBtn');
        if (editBtn) {
            editBtn.addEventListener('click', () => {
                this.enableEdit();
            });
        }

        const saveBtn = this.shadowRoot.getElementById('saveBtn');
        if (saveBtn) {
            saveBtn.addEventListener('click', () => {
                this.saveArchive();
            });
        }

        const cancelBtn = this.shadowRoot.getElementById('cancelBtn');
        if (cancelBtn) {
            cancelBtn.addEventListener('click', () => {
                this.cancelEdit();
            });
        }

        // Graph toolbar buttons
        this.shadowRoot.getElementById('addAlgorithmNode')?.addEventListener('click', () => this.addNode());
        this.shadowRoot.getElementById('deleteNode')?.addEventListener('click', () => this.deleteSelectedNode());
        this.shadowRoot.getElementById('addEdge')?.addEventListener('click', () => this.startAddEdge());
        this.shadowRoot.getElementById('deleteEdge')?.addEventListener('click', () => this.deleteSelectedEdge());
        this.shadowRoot.getElementById('clearGraph')?.addEventListener('click', () => this.clearGraph());

        // Node modal
        this.shadowRoot.getElementById('nodeModalClose')?.addEventListener('click', () => this.hideNodeModal());
        this.shadowRoot.getElementById('nodeCancelBtn')?.addEventListener('click', () => this.hideNodeModal());
        this.shadowRoot.getElementById('nodeSaveBtn')?.addEventListener('click', () => this.saveNodeConfig());
    }

    enableEdit() {
        this.isEditMode = true;

        // 确保节点配置弹窗是隐藏的
        const nodeModalMask = this.shadowRoot.getElementById('nodeModalMask');
        if (nodeModalMask) {
            nodeModalMask.hidden = true;
            nodeModalMask.style.display = 'none';
        }

        const fields = ['detailName', 'detailDesc', 'detailScheduleCron', 'detailOutputApiConfig', 'detailStatus'];
        fields.forEach(field => {
            const valueEl = this.shadowRoot.getElementById(field);
            const inputEl = this.shadowRoot.getElementById(field + 'Input');
            if (valueEl && inputEl) {
                valueEl.style.display = 'none';
                inputEl.style.display = 'inline-block';
                inputEl.value = valueEl.textContent === '-' ? '' : valueEl.textContent;
            }
        });

        const editActions = this.shadowRoot.getElementById('editActions');
        const editBtn = this.shadowRoot.getElementById('editBtn');
        if (editActions) editActions.style.display = 'flex';
        if (editBtn) editBtn.style.display = 'none';

        // 启用图编辑器工具栏按钮
        this.enableGraphToolbar(true);
    }

    cancelEdit() {
        this.isEditMode = false;
        
        const fields = ['detailName', 'detailDesc', 'detailScheduleCron', 'detailOutputApiConfig', 'detailStatus'];
        fields.forEach(field => {
            const valueEl = this.shadowRoot.getElementById(field);
            const inputEl = this.shadowRoot.getElementById(field + 'Input');
            if (valueEl && inputEl) {
                valueEl.style.display = 'inline';
                inputEl.style.display = 'none';
            }
        });

        const editActions = this.shadowRoot.getElementById('editActions');
        const editBtn = this.shadowRoot.getElementById('editBtn');
        if (editActions) editActions.style.display = 'none';
        if (editBtn) editBtn.style.display = 'inline-block';

        // 禁用图编辑器工具栏按钮
        this.enableGraphToolbar(false);
    }

    enableGraphToolbar(enabled) {
        const toolbarButtons = ['addAlgorithmNode', 'deleteNode', 'addEdge', 'deleteEdge', 'clearGraph'];
        toolbarButtons.forEach(btnId => {
            const btn = this.shadowRoot.getElementById(btnId);
            if (btn) {
                btn.disabled = !enabled;
                btn.style.opacity = enabled ? '1' : '0.5';
                btn.style.cursor = enabled ? 'pointer' : 'not-allowed';
            }
        });
    }

    async saveArchive() {
        const name = this.shadowRoot.getElementById('detailNameInput').value.trim();
        if (!name) {
            this.showToast('请输入档案名称', 'error');
            return;
        }

        try {
            if (window.showGlobalLoading) {
                window.showGlobalLoading('正在保存...');
            }

            // 获取当前项目信息
            const username = window.localStorage.getItem('username');
            const cachedProject = username ? JSON.parse(window.localStorage.getItem('currentProject_' + username) || 'null') : null;
            const projectName = cachedProject ? cachedProject.name : '';
            const owner = username || '';

            const archiveData = {
                createTime: this.currentArchive ? this.currentArchive.createTime : null,
                name: name,
                description: this.shadowRoot.getElementById('detailDescInput').value.trim(),
                projectName: projectName,
                owner: owner,
                graphJson: JSON.stringify({ nodes: this.nodes, edges: this.edges }),
                status: this.shadowRoot.getElementById('detailStatusInput').value === 'true',
                scheduleCron: this.shadowRoot.getElementById('detailScheduleCronInput').value.trim(),
                outputApiConfig: this.shadowRoot.getElementById('detailOutputApiConfigInput').value.trim()
            };

            const result = await window.AppConfig.post('simulationArchives', 'save', archiveData);

            if (result.code === 200) {
                this.showToast('仿真档案保存成功');
                this.currentArchive = { ...this.currentArchive, ...archiveData };
                this.updateDisplay();
                this.cancelEdit();
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

    showAdd() {
        this.currentArchive = null;
        this.isEditMode = true;
        
        // 获取当前项目信息
        const username = window.localStorage.getItem('username');
        const cachedProject = username ? JSON.parse(window.localStorage.getItem('currentProject_' + username) || 'null') : null;
        const projectName = cachedProject ? cachedProject.name : '-';
        const owner = username || '-';
        
        // 清空表单
        this.shadowRoot.getElementById('detailName').textContent = '-';
        this.shadowRoot.getElementById('detailDesc').textContent = '-';
        this.shadowRoot.getElementById('detailProjectName').textContent = projectName;
        this.shadowRoot.getElementById('detailOwner').textContent = owner;
        this.shadowRoot.getElementById('detailScheduleCron').textContent = '-';
        this.shadowRoot.getElementById('detailOutputApiConfig').textContent = '-';
        this.shadowRoot.getElementById('detailStatus').textContent = '启用';
        this.shadowRoot.getElementById('detailUpdateTime').textContent = '-';
        this.shadowRoot.getElementById('detailExecutionCount').textContent = '0';
        
        // 清空图数据但不调用clearGraph方法（避免触发弹窗）
        this.nodes = [];
        this.edges = [];
        this.selectedNode = null;
        this.selectedEdge = null;
        this.nodeCounter = 0;
        this.edgeCounter = 0;
        this.renderGraph();
        
        // 启用编辑模式
        const fields = ['detailName', 'detailDesc', 'detailScheduleCron', 'detailOutputApiConfig', 'detailStatus'];
        fields.forEach(field => {
            const valueEl = this.shadowRoot.getElementById(field);
            const inputEl = this.shadowRoot.getElementById(field + 'Input');
            if (valueEl && inputEl) {
                valueEl.style.display = 'none';
                inputEl.style.display = 'inline-block';
                inputEl.value = '';
            }
        });
        
        // 设置默认值
        this.shadowRoot.getElementById('detailStatusInput').value = 'true';
        
        const editActions = this.shadowRoot.getElementById('editActions');
        const editBtn = this.shadowRoot.getElementById('editBtn');
        const graphSection = this.shadowRoot.getElementById('graphSection');
        if (editActions) editActions.style.display = 'flex';
        if (editBtn) editBtn.style.display = 'none';
        if (graphSection) graphSection.style.display = 'block';
        
        // 确保节点配置弹窗是隐藏的
        const nodeModalMask = this.shadowRoot.getElementById('nodeModalMask');
        if (nodeModalMask) {
            nodeModalMask.hidden = true;
            nodeModalMask.style.display = 'none';
        }
        
        this.style.display = 'block';
    }

    async showDetail(createTime) {
        try {
            if (window.showGlobalLoading) {
                window.showGlobalLoading('正在加载仿真档案详情...');
            }

            // 确保节点配置弹窗是隐藏的
            const nodeModalMask = this.shadowRoot.getElementById('nodeModalMask');
            if (nodeModalMask) {
                nodeModalMask.hidden = true;
                nodeModalMask.style.display = 'none';
            }

            const result = await window.AppConfig.post('simulationArchives', 'query', { createTime });

            if (result.code === 200 && result.data && result.data.length > 0) {
                this.currentArchive = result.data[0];
                this.updateDisplay();
                this.style.display = 'block';
            } else {
                this.showToast('未找到仿真档案', 'error');
            }
        } catch (error) {
            console.error('加载仿真档案详情失败:', error);
            this.showToast('加载仿真档案详情失败', 'error');
        } finally {
            if (window.hideGlobalLoading) {
                window.hideGlobalLoading();
            }
        }
    }

    updateDisplay() {
        if (!this.currentArchive) return;

        const archive = this.currentArchive;
        
        this.shadowRoot.getElementById('detailName').textContent = archive.name || '-';
        this.shadowRoot.getElementById('detailDesc').textContent = archive.description || '-';
        this.shadowRoot.getElementById('detailProjectName').textContent = archive.projectName || '-';
        this.shadowRoot.getElementById('detailOwner').textContent = archive.owner || '-';
        this.shadowRoot.getElementById('detailScheduleCron').textContent = archive.scheduleCron || '-';
        this.shadowRoot.getElementById('detailOutputApiConfig').textContent = archive.outputApiConfig || '-';
        this.shadowRoot.getElementById('detailStatus').textContent = archive.status ? '启用' : '禁用';
        this.shadowRoot.getElementById('detailUpdateTime').textContent = archive.updateTime ? new Date(archive.updateTime).toLocaleString('zh-CN') : '-';
        this.shadowRoot.getElementById('detailExecutionCount').textContent = archive.executionCount || 0;

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

        // 查看详情时禁用图编辑器工具栏按钮
        this.enableGraphToolbar(false);
    }

    // Graph Editor Methods
    renderGraph() {
        const svg = this.shadowRoot.getElementById('graphSvg');
        if (!svg) return;

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
            g.setAttribute('class', 'graph-node' + (this.selectedNode === node.nodeId ? ' selected' : ''));
            g.setAttribute('data-node-id', node.nodeId);
            g.setAttribute('transform', `translate(${node.positionX || 100}, ${node.positionY || 100})`);

            const circle = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
            circle.setAttribute('r', '30');
            
            const text = document.createElementNS('http://www.w3.org/2000/svg', 'text');
            text.setAttribute('x', '0');
            text.setAttribute('y', '45');
            text.setAttribute('text-anchor', 'middle');
            text.textContent = node.nodeName || '算法节点';

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
                    if (!this.isAddingEdge && this.isEditMode) {
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

    addNode() {
        if (!this.isEditMode) {
            this.showToast('请先点击编辑按钮', 'warning');
            return;
        }

        const node = {
            nodeId: 'node_' + (++this.nodeCounter),
            nodeName: '算法节点' + this.nodeCounter,
            algorithmName: '',
            algorithmVersion: '',
            boundModelName: '',
            boundModelVersion: '',
            startTime: 0,
            endTime: 0,
            executionParams: '{}',
            enabled: true,
            positionX: 100 + Math.random() * 300,
            positionY: 100 + Math.random() * 200
        };
        
        this.nodes.push(node);
        this.renderGraph();
    }

    deleteSelectedNode() {
        if (!this.isEditMode) {
            this.showToast('请先点击编辑按钮', 'warning');
            return;
        }

        if (!this.selectedNode) {
            this.showToast('请先选择要删除的节点', 'error');
            return;
        }

        this.edges = this.edges.filter(e => 
            e.sourceNodeId !== this.selectedNode && e.targetNodeId !== this.selectedNode
        );
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
        if (!this.isEditMode) {
            this.showToast('请先点击编辑按钮', 'warning');
            return;
        }

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
        if (!this.isEditMode) {
            this.showToast('请先点击编辑按钮', 'warning');
            return;
        }

        if (!this.selectedEdge) {
            this.showToast('请先选择要删除的连线', 'error');
            return;
        }

        this.edges = this.edges.filter(e => e.edgeId !== this.selectedEdge);
        this.selectedEdge = null;
        
        this.renderGraph();
    }

    clearGraph() {
        if (!this.isEditMode) {
            this.showToast('请先点击编辑按钮', 'warning');
            return;
        }

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
            this.shadowRoot.getElementById('startTime').value = node.startTime || '';
            this.shadowRoot.getElementById('endTime').value = node.endTime || '';
            this.shadowRoot.getElementById('executionParams').value = node.executionParams || '{}';
            
            // Load algorithms
            await this.loadAlgorithms();
            this.shadowRoot.getElementById('algorithmSelect').value = node.algorithmName ? `${node.algorithmName}_${node.algorithmVersion}` : '';
            
            // Load models
            await this.loadModels();
            this.shadowRoot.getElementById('modelSelect').value = node.boundModelName ? `${node.boundModelName}_${node.boundModelVersion}` : '';
            
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
                if (Array.isArray(result.data)) {
                    result.data.forEach(algo => {
                        select.innerHTML += `<option value="${algo.name}_${algo.version}">${algo.name} (${algo.version})</option>`;
                    });
                } else {
                    select.innerHTML += `<option value="${result.data.name}_${result.data.version}">${result.data.name} (${result.data.version})</option>`;
                }
            }
        } catch (error) {
            console.error('加载算法列表失败:', error);
        }
    }

    async loadModels() {
        try {
            const result = await window.AppConfig.post('model', 'metas', {});
            const select = this.shadowRoot.getElementById('modelSelect');
            if (select && result.code === 200 && result.data) {
                select.innerHTML = '<option value="">不绑定模型</option>';
                if (Array.isArray(result.data)) {
                    result.data.forEach(model => {
                        select.innerHTML += `<option value="${model.name}_${model.version}">${model.name} (${model.version})</option>`;
                    });
                } else {
                    select.innerHTML += `<option value="${result.data.name}_${result.data.version}">${result.data.name} (${result.data.version})</option>`;
                }
            }
        } catch (error) {
            console.error('加载模型列表失败:', error);
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
        const algorithmSelect = this.shadowRoot.getElementById('algorithmSelect').value;
        const modelSelect = this.shadowRoot.getElementById('modelSelect').value;
        const startTime = this.shadowRoot.getElementById('startTime').value;
        const endTime = this.shadowRoot.getElementById('endTime').value;
        const executionParams = this.shadowRoot.getElementById('executionParams').value;

        const node = this.nodes.find(n => n.nodeId === nodeId);
        if (node) {
            node.nodeName = nodeName;
            
            if (algorithmSelect) {
                const [algorithmName, algorithmVersion] = algorithmSelect.split('_');
                node.algorithmName = algorithmName;
                node.algorithmVersion = algorithmVersion;
            }
            
            if (modelSelect) {
                const [modelName, modelVersion] = modelSelect.split('_');
                node.boundModelName = modelName;
                node.boundModelVersion = modelVersion;
            }
            
            node.startTime = startTime ? parseInt(startTime) : 0;
            node.endTime = endTime ? parseInt(endTime) : 0;
            node.executionParams = executionParams || '{}';
            
            this.renderGraph();
            this.hideNodeModal();
        }
    }

    hide() {
        this.style.display = 'none';
        this.cancelEdit();
    }

    showToast(message, type = 'success') {
        if (window.CommonUtils && window.CommonUtils.showToast) {
            window.CommonUtils.showToast(message, type);
        } else {
            console.log(`[${type}] ${message}`);
        }
    }
}

customElements.define('simulation-archive-detail', SimulationArchiveDetail);
