class DataArchiveList extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });
        this.currentPage = 1;
        this.pageSize = 10;
        this.totalCount = 0;
        this.data = [];
    }

    async connectedCallback() {
        await this.loadResources();
        this.bindEvents();
        // 不在初始化时自动加载数据，只在显示时加载
    }

    async loadResources() {
        const cssResponse = await fetch('/components/data-archive-list/data-archive-list.css');
        const cssContent = await cssResponse.text();
        const style = document.createElement('style');
        style.textContent = cssContent;
        this.shadowRoot.appendChild(style);

        const htmlResponse = await fetch('/components/data-archive-list/data-archive-list.html');
        const htmlContent = await htmlResponse.text();
        const template = document.createElement('template');
        template.innerHTML = htmlContent;
        this.shadowRoot.appendChild(template.content.cloneNode(true));
    }

    bindEvents() {
        this.shadowRoot.getElementById('importDataResourceBtn')?.addEventListener('click', () => {
            window.showProjectImportWizard?.('data');
        });
        this.shadowRoot.getElementById('exportDataResourceBtn')?.addEventListener('click', () => {
            window.showProjectExportWizard?.('data');
        });

        const searchBtn = this.shadowRoot.getElementById('searchBtn');
        if (searchBtn) {
            searchBtn.addEventListener('click', () => {
                this.currentPage = 1;
                this.loadData();
            });
        }

        const resetBtn = this.shadowRoot.getElementById('resetBtn');
        if (resetBtn) {
            resetBtn.addEventListener('click', () => {
                this.resetFilters();
                this.loadData();
            });
        }

        const prevBtn = this.shadowRoot.getElementById('prevBtn');
        if (prevBtn) {
            prevBtn.addEventListener('click', () => {
                if (this.currentPage > 1) {
                    this.currentPage--;
                    this.loadData();
                }
            });
        }

        const nextBtn = this.shadowRoot.getElementById('nextBtn');
        if (nextBtn) {
            nextBtn.addEventListener('click', () => {
                const totalPages = Math.ceil(this.totalCount / this.pageSize);
                if (this.currentPage < totalPages) {
                    this.currentPage++;
                    this.loadData();
                }
            });
        }
    }

    resetFilters() {
        const nameInput = this.shadowRoot.getElementById('nameInput');
        const typeSelect = this.shadowRoot.getElementById('typeSelect');
        const projectNameInput = this.shadowRoot.getElementById('projectNameInput');
        const ownerInput = this.shadowRoot.getElementById('ownerInput');

        if (nameInput) nameInput.value = '';
        if (typeSelect) typeSelect.value = '';
        if (projectNameInput) projectNameInput.value = '';
        if (ownerInput) ownerInput.value = '';
    }

    async loadData() {
        try {
            if (window.showGlobalLoading) {
                window.showGlobalLoading('正在加载数据档案...');
            }

            const nameInput = this.shadowRoot.getElementById('nameInput');
            const typeSelect = this.shadowRoot.getElementById('typeSelect');
            const projectNameInput = this.shadowRoot.getElementById('projectNameInput');
            const ownerInput = this.shadowRoot.getElementById('ownerInput');

            const request = {
                name: nameInput ? nameInput.value : '',
                type: typeSelect ? typeSelect.value : '',
                projectName: projectNameInput ? projectNameInput.value : '',
                owner: ownerInput ? ownerInput.value : '',
                pageNum: this.currentPage,
                pageSize: this.pageSize
            };

            const result = await window.AppConfig.post('dataArchive', 'query', request);

            if (result.code === 200 && result.data) {
                this.data = result.data;
                this.renderTable();
                
                // 获取总数
                const countResult = await window.AppConfig.post('dataArchive', 'count', request);
                if (countResult.code === 200) {
                    this.totalCount = countResult.data;
                    this.renderPagination();
                }
            } else {
                this.showToast('加载数据档案失败', 'error');
            }
        } catch (error) {
            console.error('加载数据档案失败:', error);
            this.showToast('加载数据档案失败', 'error');
        } finally {
            if (window.hideGlobalLoading) {
                window.hideGlobalLoading();
            }
        }
    }

    renderTable() {
        const tableBody = this.shadowRoot.getElementById('tableBody');
        if (!tableBody) return;

        tableBody.innerHTML = '';

        if (this.data.length === 0) {
            tableBody.innerHTML = '<tr><td colspan="7" style="text-align: center; padding: 20px;">暂无数据</td></tr>';
            return;
        }

        this.data.forEach(item => {
            const row = document.createElement('tr');
            row.innerHTML = `
                <td>${item.name || '-'}</td>
                <td>${item.type || '-'}</td>
                <td>${item.desc || '-'}</td>
                <td>${item.projectName || '-'}</td>
                <td>${item.owner || '-'}</td>
                <td>${item.createTime ? new Date(item.createTime).toLocaleString('zh-CN') : '-'}</td>
                <td></td>
            `;
            
            // 整行点击事件：切换到数据资源库左侧栏并展开对应的树节点
            row.style.cursor = 'pointer';
            row.addEventListener('click', () => {
                this.expandTreeByArchiveName(item.name);
            });
            
            const actionCell = row.querySelector('td:last-child');
            const detailBtn = document.createElement('button');
            detailBtn.className = 'btn-detail';
            detailBtn.textContent = '详情';
            detailBtn.addEventListener('click', (e) => {
                e.stopPropagation();
                this.showDetail(item.name);
            });
            actionCell.appendChild(detailBtn);
            
            const editBtn = document.createElement('button');
            editBtn.className = 'btn-edit';
            editBtn.textContent = '编辑';
            editBtn.addEventListener('click', (e) => {
                e.stopPropagation();
                this.showEdit(item.name);
            });
            actionCell.appendChild(editBtn);
            
            tableBody.appendChild(row);
        });
    }

    renderPagination() {
        const paginationInfo = this.shadowRoot.getElementById('paginationInfo');
        const prevBtn = this.shadowRoot.getElementById('prevBtn');
        const nextBtn = this.shadowRoot.getElementById('nextBtn');

        if (paginationInfo) {
            const totalPages = Math.ceil(this.totalCount / this.pageSize);
            paginationInfo.textContent = `第 ${this.currentPage} / ${totalPages || 1} 页，共 ${this.totalCount} 条`;
        }

        if (prevBtn) {
            prevBtn.disabled = this.currentPage <= 1;
        }

        if (nextBtn) {
            const totalPages = Math.ceil(this.totalCount / this.pageSize);
            nextBtn.disabled = this.currentPage >= totalPages;
        }
    }

    async showDetail(name) {
        this.hide();
        const dataArchiveDetail = document.getElementById('dataArchiveDetail');
        if (dataArchiveDetail && dataArchiveDetail.showDetail) {
            dataArchiveDetail.style.display = 'block';
            await dataArchiveDetail.showDetail(name);
        }
    }

    async showEdit(name) {
        this.hide();
        const dataArchiveDetail = document.getElementById('dataArchiveDetail');
        if (dataArchiveDetail && dataArchiveDetail.showDetail) {
            dataArchiveDetail.style.display = 'block';
            await dataArchiveDetail.showDetail(name);
            // 等待数据加载完成后启用编辑模式
            if (dataArchiveDetail.enableEdit) {
                dataArchiveDetail.enableEdit();
            }
        }
    }

    expandTreeByArchiveName(archiveName) {
        console.log('尝试展开树节点:', archiveName);
        
        // 检查当前是否已经是数据侧边栏且处于展开状态
        const activeDataIcon = document.querySelector('.bottom-sidebar-icon.left-sidebar-icon.active[data-panel="data"]');
        const leftSidebar = document.querySelector('.left-sidebar');
        const isDataSidebarActive = !!activeDataIcon;
        const isSidebarExpanded = leftSidebar && !leftSidebar.classList.contains('collapsed');
        
        if (!isDataSidebarActive || !isSidebarExpanded) {
            // 如果不是数据侧边栏或侧边栏未展开，点击切换
            const dataIcon = document.querySelector('.bottom-sidebar-icon.left-sidebar-icon[data-panel="data"]');
            if (dataIcon) {
                console.log('当前不是数据侧边栏或侧边栏未展开，点击切换');
                dataIcon.click();
            } else {
                console.log('未找到数据侧边栏图标');
            }
        } else {
            console.log('当前已是数据侧边栏且已展开，无需切换');
        }

        // 等待树加载完成后展开对应节点
        setTimeout(() => {
            const treeNodes = document.querySelectorAll('.tree-node');
            console.log('找到树节点数量:', treeNodes.length);
            
            let found = false;
            treeNodes.forEach(node => {
                // 获取节点的data-full-path属性
                const fullPath = node.getAttribute('data-full-path');
                console.log('检查节点path:', fullPath);
                
                // 精确匹配archiveName
                if (fullPath === archiveName) {
                    console.log('找到匹配的节点，模拟点击');
                    found = true;
                    
                    // 模拟点击节点，让树自己处理展开逻辑
                    node.click();
                    
                    // 滚动到视图中心
                    node.scrollIntoView({ behavior: 'smooth', block: 'center' });
                }
            });
            
            if (!found) {
                console.log('未找到匹配的树节点:', archiveName);
            }
        }, 500);
    }

    show() {
        this.style.display = 'block';
        if (!this.data || this.data.length === 0) {
            this.loadData();
        }
    }

    hide() {
        this.style.display = 'none';
    }

    showToast(message, type = 'success') {
        if (window.CommonUtils && window.CommonUtils.showToast) {
            window.CommonUtils.showToast(message, type);
        } else {
            console.log(`[${type}] ${message}`);
        }
    }
}

customElements.define('data-archive-list', DataArchiveList);
