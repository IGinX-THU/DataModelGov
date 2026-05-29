class AlgorithmArchiveList extends HTMLElement {
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
        this.loadData();
    }

    async loadResources() {
        const cssResponse = await fetch('/components/algorithm-archive-list/algorithm-archive-list.css');
        const cssContent = await cssResponse.text();
        const style = document.createElement('style');
        style.textContent = cssContent;
        this.shadowRoot.appendChild(style);

        const htmlResponse = await fetch('/components/algorithm-archive-list/algorithm-archive-list.html');
        const htmlContent = await htmlResponse.text();
        const template = document.createElement('template');
        template.innerHTML = htmlContent;
        this.shadowRoot.appendChild(template.content.cloneNode(true));
    }

    bindEvents() {
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
        const projectNameInput = this.shadowRoot.getElementById('projectNameInput');
        const authorInput = this.shadowRoot.getElementById('authorInput');

        if (nameInput) nameInput.value = '';
        if (projectNameInput) projectNameInput.value = '';
        if (authorInput) authorInput.value = '';
    }

    async loadData() {
        try {
            if (window.showGlobalLoading) {
                window.showGlobalLoading('正在加载算法档案...');
            }

            const nameInput = this.shadowRoot.getElementById('nameInput');
            const projectNameInput = this.shadowRoot.getElementById('projectNameInput');
            const authorInput = this.shadowRoot.getElementById('authorInput');

            const request = {
                name: nameInput ? nameInput.value : '',
                projectName: projectNameInput ? projectNameInput.value : '',
                author: authorInput ? authorInput.value : '',
                pageNum: this.currentPage,
                pageSize: this.pageSize
            };

            const result = await window.AppConfig.post('algorithm', 'archive/query', request);

            if (result.code === 200 && result.data) {
                this.data = result.data;
                this.renderTable();

                // 获取总数
                const countResult = await window.AppConfig.post('algorithm', 'archive/count', request);
                if (countResult.code === 200) {
                    this.totalCount = countResult.data;
                    this.renderPagination();
                }
            } else {
                this.showToast('加载算法档案失败', 'error');
            }
        } catch (error) {
            console.error('加载算法档案失败:', error);
            this.showToast('加载算法档案失败', 'error');
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
                <td>${item.version || '-'}</td>
                <td>${item.fileName || '-'}</td>
                <td>${item.projectName || '-'}</td>
                <td>${item.author || '-'}</td>
                <td>${item.timestamp ? new Date(item.timestamp).toLocaleString('zh-CN') : '-'}</td>
                <td></td>
            `;

            // 整行点击事件：切换到右侧算法侧边栏并展开对应的树节点
            row.style.cursor = 'pointer';
            row.addEventListener('click', () => {
                this.expandAlgorithmNode(item);
            });

            const actionCell = row.querySelector('td:last-child');
            const detailBtn = document.createElement('button');
            detailBtn.className = 'btn-detail';
            detailBtn.textContent = '详情';
            detailBtn.addEventListener('click', (e) => {
                e.stopPropagation();
                this.showDetail(item);
            });
            actionCell.appendChild(detailBtn);

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

    showDetail(item) {
        // 显示算法详情
        if (window.hideAllComponents) {
            window.hideAllComponents();
        }
        const algorithmDetail = document.getElementById('algorithmDetail');
        if (algorithmDetail && algorithmDetail.show) {
            algorithmDetail.show({ name: item.name, version: item.version });
        }
    }

    expandAlgorithmNode(item) {
        console.log('尝试展开算法节点:', item);

        const storagePath = item.storagePath;
        if (!storagePath) {
            console.warn('算法档案缺少storagePath，无法展开树节点');
            return;
        }

        // 切换到右侧算法侧边栏
        const activeAlgorithmIcon = document.querySelector('.bottom-sidebar-icon.right-sidebar-icon.active[data-panel="algorithm"]');
        const rightSidebar = document.querySelector('.right-sidebar');
        const isAlgorithmSidebarActive = !!activeAlgorithmIcon;
        const isSidebarExpanded = rightSidebar && !rightSidebar.classList.contains('collapsed');

        if (!isAlgorithmSidebarActive || !isSidebarExpanded) {
            const algorithmIcon = document.querySelector('.bottom-sidebar-icon.right-sidebar-icon[data-panel="algorithm"]');
            if (algorithmIcon) {
                console.log('当前不是算法侧边栏或侧边栏未展开，点击切换');
                algorithmIcon.click();
            }
        }

        // 等待树加载完成后展开对应节点
        setTimeout(() => {
            const algorithmTree = document.getElementById('algorithmTree');
            if (!algorithmTree) return;

            const treeNodes = algorithmTree.querySelectorAll('.tree-node');
            let found = false;
            treeNodes.forEach(node => {
                const fullPath = node.getAttribute('data-full-path');
                if (fullPath === storagePath) {
                    found = true;
                    // 展开父节点
                    let parent = node.closest('.tree-children')?.parentElement;
                    while (parent && parent.classList.contains('tree-node')) {
                        parent.classList.add('expanded');
                        parent = parent.closest('.tree-children')?.parentElement;
                    }
                    // 模拟点击节点
                    node.click();
                    node.scrollIntoView({ behavior: 'smooth', block: 'center' });
                }
            });

            if (!found) {
                console.log('未找到匹配的算法树节点:', storagePath);
            }
        }, 500);
    }

    show() {
        this.style.display = 'block';
        this.loadData();
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

customElements.define('algorithm-archive-list', AlgorithmArchiveList);
