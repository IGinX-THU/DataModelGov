/**
 * 算法列表管理组件
 */
class AlgorithmList extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });
        this.data = [];
        this.pageSize = 10;
        this.currentPage = 1;
        this.totalCount = 0;
    }

    async connectedCallback() {
        await this.loadResources();
        setTimeout(() => {
            this.initPagination();
            this.bindEvents();
        }, 100);
    }

    async loadResources() {
        try {
            const cssLink = document.createElement('link');
            cssLink.rel = 'stylesheet';
            cssLink.href = './components/algorithm-list/algorithm-list.css';
            this.shadowRoot.appendChild(cssLink);
        } catch (error) {
            console.error('Failed to load CSS:', error);
        }

        if (window.location.protocol === 'file:') {
            this.shadowRoot.innerHTML += this.getFallbackHTML();
        } else {
            try {
                const response = await fetch('./components/algorithm-list/algorithm-list.html');
                if (!response.ok) {
                    throw new Error(`HTTP error! status: ${response.status}`);
                }
                const html = await response.text();
                this.shadowRoot.innerHTML += html;
            } catch (error) {
                console.error('Failed to load HTML template:', error);
                this.shadowRoot.innerHTML += this.getFallbackHTML();
            }
        }
    }

    getFallbackHTML() {
        return `
            <div class="parsing-rules">
                <div class="parsing-filter-card">
                    <div class="filter-header">筛选</div>
                    <div class="filter-rows">
                        <div class="filter-row">
                            <div class="filter-field">
                                <span class="filter-label">算法名称</span>
                                <input class="filter-input" type="text" placeholder="请输入算法名称" id="nameFilter" />
                            </div>
                            <div class="filter-field">
                                <span class="filter-label">算法类型</span>
                                <select class="filter-input" id="typeFilter">
                                    <option value="">全部</option>
                                    <option value="python">Python脚本</option>
                                    <option value="java">Java程序</option>
                                    <option value="shell">Shell脚本</option>
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

                <div class="parsing-table-card">
                    <div class="table-toolbar">
                        <button class="toolbar-btn green" type="button" id="uploadAlgorithmBtn">上传算法</button>
                    </div>
                    <div class="table-wrapper">
                        <table class="data-table">
                            <thead>
                                <tr>
                                    <th>算法名称</th>
                                    <th>版本</th>
                                    <th>类型</th>
                                    <th>开发者</th>
                                    <th>场景</th>
                                    <th>创建时间</th>
                                    <th>操作</th>
                                </tr>
                            </thead>
                            <tbody id="tableBody"></tbody>
                        </table>
                    </div>
                    <common-pagination id="pagination"></common-pagination>
                </div>
            </div>

            <algorithm-upload id="algorithmUpload"></algorithm-upload>
        `;
    }

    initPagination() {
        const pagination = this.shadowRoot.getElementById('pagination');
        if (pagination) {
            pagination.addEventListener('page-change', (e) => {
                this.currentPage = e.detail.page;
                this.loadAlgorithmsFromAPI();
            });
        }
    }

    bindEvents() {
        this.shadowRoot.getElementById('applyFilters')?.addEventListener('click', () => {
            this.currentPage = 1;
            this.loadAlgorithmsFromAPI();
        });

        this.shadowRoot.getElementById('resetFilters')?.addEventListener('click', () => {
            this.shadowRoot.getElementById('nameFilter').value = '';
            this.shadowRoot.getElementById('typeFilter').value = '';
            this.currentPage = 1;
            this.loadAlgorithmsFromAPI();
        });

        this.shadowRoot.getElementById('uploadAlgorithmBtn')?.addEventListener('click', () => {
            this.showUploadModal();
        });

        // 监听算法上传完成事件
        this.addEventListener('algorithm-uploaded', () => {
            this.loadAlgorithmsFromAPI();
        });

        // 表格操作按钮事件委托
        this.shadowRoot.addEventListener('click', (e) => {
            if (e.target.classList.contains('action-btn')) {
                const action = e.target.dataset.action;
                const id = e.target.dataset.id;
                
                switch (action) {
                    case 'download':
                        this.downloadAlgorithm(id);
                        break;
                    case 'delete':
                        this.deleteAlgorithm(id);
                        break;
                }
            }
        });
    }

    async loadAlgorithmsFromAPI() {
        try {
            if (window.showGlobalLoading) {
                window.showGlobalLoading('正在查询数据...');
            }

            const nameFilter = this.shadowRoot.getElementById('nameFilter')?.value.trim();
            const typeFilter = this.shadowRoot.getElementById('typeFilter')?.value;

            const requestBody = {
                name: nameFilter || null,
                algorithmType: typeFilter || null
            };

            const result = await window.AppConfig.post('algorithm', 'metas', requestBody);
            
            if (result.code === 200 && result.data) {
                this.data = [result.data];
                this.renderTable();
            } else {
                this.showToast('加载算法失败', 'error');
            }
        } catch (error) {
            console.error('加载算法失败:', error);
            this.showToast('网络错误，无法加载算法', 'error');
        } finally {
            if (window.hideGlobalLoading) {
                window.hideGlobalLoading();
            }
        }
    }

    renderTable() {
        const tbody = this.shadowRoot.getElementById('tableBody');
        if (!tbody) return;

        if (this.data.length === 0) {
            tbody.innerHTML = '<tr><td colspan="7" style="text-align:center;padding:40px;">暂无数据</td></tr>';
            return;
        }

        tbody.innerHTML = this.data.map(item => `
            <tr>
                <td>${item.name}</td>
                <td>${item.version}</td>
                <td>${this.getTypeLabel(item.algorithmType)}</td>
                <td>${item.author || '-'}</td>
                <td>${item.scene || '-'}</td>
                <td>${new Date(item.timestamp).toLocaleString('zh-CN')}</td>
                <td>
                    <div class="action-buttons">
                        <button class="action-btn edit" data-action="download" data-id="${item.name}_${item.version}">下载</button>
                        <button class="action-btn delete" data-action="delete" data-id="${item.name}_${item.version}">删除</button>
                    </div>
                </td>
            </tr>
        `).join('');
    }

    getTypeLabel(type) {
        const typeMap = {
            'python': 'Python脚本',
            'c': 'C程序',
            'cpp': 'C++程序',
            'matlab': 'MATLAB程序',
            'zip': '压缩包'
        };
        return typeMap[type] || type || '-';
    }

    showUploadModal() {
        const uploadComponent = this.shadowRoot.getElementById('algorithmUpload');
        if (uploadComponent) {
            uploadComponent.show();
        }
    }

    async downloadAlgorithm(id) {
        const [name, version] = id.split('_');
        
        try {
            if (window.showGlobalLoading) {
                window.showGlobalLoading('正在下载算法文件...');
            }

            const response = await fetch(`${window.AppConfig.baseUrl}/api/algorithm/download?name=${encodeURIComponent(name)}&version=${encodeURIComponent(version)}`, {
                method: 'POST',
                headers: {
                    'Authorization': `Bearer ${localStorage.getItem('jwtToken')}`
                }
            });

            if (response.ok) {
                const blob = await response.blob();
                const url = window.URL.createObjectURL(blob);
                const a = document.createElement('a');
                a.href = url;
                a.download = `${name}_${version}.zip`;
                document.body.appendChild(a);
                a.click();
                document.body.removeChild(a);
                window.URL.revokeObjectURL(url);
                this.showToast('下载成功');
            } else {
                this.showToast('下载失败', 'error');
            }
        } catch (error) {
            console.error('下载算法失败:', error);
            this.showToast('网络错误，下载失败', 'error');
        } finally {
            if (window.hideGlobalLoading) {
                window.hideGlobalLoading();
            }
        }
    }

    async deleteAlgorithm(id) {
        if (window.showConfirmDialog) {
            window.showConfirmDialog('确定要删除该算法吗？', () => {
                this.executeDeleteAlgorithm(id);
            });
        } else {
            // 降级处理
            if (!confirm('确定要删除该算法吗？')) {
                return;
            }
            this.executeDeleteAlgorithm(id);
        }
    }

    async executeDeleteAlgorithm(id) {
        const [name, version] = id.split('_');
        
        try {
            if (window.showGlobalLoading) {
                window.showGlobalLoading('正在删除算法...');
            }

            const result = await window.AppConfig.delete('algorithm', 'delete', { name, version });
            
            if (result.code === 200) {
                this.showToast('删除成功');
                await this.loadAlgorithmsFromAPI();
            } else {
                this.showToast(result.message || '删除失败', 'error');
            }
        } catch (error) {
            console.error('删除算法失败:', error);
            this.showToast('网络错误，删除失败', 'error');
        } finally {
            if (window.hideGlobalLoading) {
                window.hideGlobalLoading();
            }
        }
    }

    async show() {
        this.style.display = 'block';
        this.currentPage = 1;
        await this.loadAlgorithmsFromAPI();
    }

    hide() {
        this.style.display = 'none';
        this.removeAttribute('show');
    }

    showToast(message, type = 'success') {
        if (window.CommonUtils && window.CommonUtils.showToast) {
            window.CommonUtils.showToast(message, type);
        } else {
            console.log(`[${type}] ${message}`);
        }
    }
}

customElements.define('algorithm-list', AlgorithmList);
