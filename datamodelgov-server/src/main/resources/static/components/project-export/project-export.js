class ProjectExport extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });
    }

    async connectedCallback() {
        await this.loadResources();
        setTimeout(() => this.bindEvents(), 100);
    }

    async loadResources() {
        const cssLink = document.createElement('link');
        cssLink.rel = 'stylesheet';
        cssLink.href = './components/project-export/project-export.css';
        this.shadowRoot.appendChild(cssLink);

        try {
            const response = await fetch('./components/project-export/project-export.html');
            if (response.ok) {
                const html = await response.text();
                this.shadowRoot.innerHTML += html;
            } else {
                this.shadowRoot.innerHTML += this.getFallbackHTML();
            }
        } catch (error) {
            console.error('Failed to load HTML template:', error);
            this.shadowRoot.innerHTML += this.getFallbackHTML();
        }
    }

    getFallbackHTML() {
        return `
<div class="project-export">
    <div class="export-card">
        <div class="export-header">导出项目</div>
        <div class="export-body">
            <div class="export-field">
                <span class="export-label">项目名称</span>
                <select class="export-select" id="projectSelect">
                    <option value="">请选择项目</option>
                </select>
            </div>
            <div class="export-section">
                <div class="export-section-title">选择导出资源类型</div>
                <div class="export-checkbox-group">
                    <label class="export-checkbox-label">
                        <input type="checkbox" id="includeAlgorithms" checked />
                        <span>算法文件</span>
                    </label>
                    <label class="export-checkbox-label">
                        <input type="checkbox" id="includeModels" checked />
                        <span>模型文件</span>
                    </label>
                    <label class="export-checkbox-label">
                        <input type="checkbox" id="includeDataCsv" checked />
                        <span>数据CSV文件</span>
                    </label>
<!--                    <label class="export-checkbox-label">-->
<!--                        <input type="checkbox" id="includeSimulationArchives" checked />-->
<!--                        <span>仿真档案及记录</span>-->
<!--                    </label>-->
                </div>
            </div>
        </div>
        <div class="export-actions">
            <button class="export-btn outline" type="button" id="cancelBtn">取消</button>
            <button class="export-btn solid" type="button" id="exportBtn">导出</button>
        </div>
    </div>
</div>`;
    }

    async show() {
        this.style.display = 'block';
        await this.loadProjectList();
    }

    hide() {
        this.style.display = 'none';
    }

    async loadProjectList() {
        try {
            const result = await window.AppConfig.post('project', 'query', {
                pageNum: 1,
                pageSize: 100
            });

            const select = this.shadowRoot.getElementById('projectSelect');
            if (!select) return;

            // Keep the first placeholder option, remove the rest
            while (select.options.length > 1) {
                select.remove(1);
            }

            if (result.code === 200 && result.data) {
                result.data.forEach(project => {
                    const option = document.createElement('option');
                    option.value = project.name;
                    option.textContent = project.name + (project.desc ? ' - ' + project.desc : '');
                    select.appendChild(option);
                });

                // Auto-select current project if available
                const username = window.AppConfig?.getUsername();
                const cached = window.localStorage?.getItem('currentProject_' + username);
                if (cached) {
                    try {
                        const current = JSON.parse(cached);
                        select.value = current.name;
                    } catch (e) {}
                }
            }
        } catch (error) {
            console.error('加载项目列表失败:', error);
            this.showToast('加载项目列表失败', 'error');
        }
    }

    bindEvents() {
        if (this._eventsBound) return;
        this._eventsBound = true;

        const root = this.shadowRoot;

        // Cancel button
        root.getElementById('cancelBtn')?.addEventListener('click', () => this.hide());

        // Export button
        root.getElementById('exportBtn')?.addEventListener('click', () => this.handleExport());
    }

    async handleExport() {
        const root = this.shadowRoot;
        const projectName = root.getElementById('projectSelect')?.value;
        if (!projectName) {
            if (window.CommonUtils && window.CommonUtils.showToast) {
                window.CommonUtils.showToast('请选择项目', 'error');
            } else {
                this.showToast('请选择项目', 'error');
            }
            return;
        }

        const includeAlgorithms = root.getElementById('includeAlgorithms')?.checked || false;
        const includeModels = root.getElementById('includeModels')?.checked || false;
        const includeDataCsv = root.getElementById('includeDataCsv')?.checked || false;
        const includeSimulationArchives = root.getElementById('includeSimulationArchives')?.checked || false;

        if (!includeAlgorithms && !includeModels && !includeDataCsv && !includeSimulationArchives) {
            if (window.CommonUtils && window.CommonUtils.showToast) {
                window.CommonUtils.showToast('请至少选择一种导出资源类型', 'error');
            } else {
                this.showToast('请至少选择一种导出资源类型', 'error');
            }
            return;
        }

        const requestBody = {
            projectName,
            includeAlgorithms,
            includeModels,
            includeDataCsv,
            includeSimulationArchives
        };

        try {
            if (window.showGlobalLoading) {
                window.showGlobalLoading('正在导出项目...');
            }

            const response = await fetch('/api/project/export', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    ...window.AppConfig?.getAuthHeaders?.()
                },
                body: JSON.stringify(requestBody)
            });

            if (response.ok) {
                // Download the ZIP file
                const blob = await response.blob();
                const url = window.URL.createObjectURL(blob);
                const a = document.createElement('a');
                a.href = url;
                const contentDisposition = response.headers.get('Content-Disposition');
                let fileName = projectName + '_export.zip';
                if (contentDisposition) {
                    const match = contentDisposition.match(/filename="?(.+?)"?$/);
                    if (match) fileName = match[1];
                }
                a.download = fileName;
                document.body.appendChild(a);
                a.click();
                window.URL.revokeObjectURL(url);
                document.body.removeChild(a);

                if (window.CommonUtils && window.CommonUtils.showToast) {
                    window.CommonUtils.showToast('导出成功');
                } else {
                    this.showToast('导出成功');
                }
                this.hide();
            } else {
                // Try to parse error response
                let errorMsg = '导出失败';
                try {
                    const errorData = await response.json();
                    errorMsg = errorData.message || errorMsg;
                } catch (e) {}
                if (window.CommonUtils && window.CommonUtils.showToast) {
                    window.CommonUtils.showToast(errorMsg, 'error');
                } else {
                    this.showToast(errorMsg, 'error');
                }
            }
        } catch (error) {
            console.error('导出项目失败:', error);
            if (window.CommonUtils && window.CommonUtils.showToast) {
                window.CommonUtils.showToast('网络错误，导出失败', 'error');
            } else {
                this.showToast('网络错误，导出失败', 'error');
            }
        } finally {
            if (window.hideGlobalLoading) {
                window.hideGlobalLoading();
            }
        }
    }

    showToast(message, type = 'success') {
        const toast = document.createElement('div');
        toast.className = `toast toast-${type}`;
        toast.textContent = message;
        toast.style.cssText = `
            position: fixed;
            top: 20px;
            right: 20px;
            padding: 12px 24px;
            background: ${type === 'success' ? '#67c23a' : '#f56c6c'};
            color: white;
            border-radius: 4px;
            z-index: 10000;
            animation: slideIn 0.3s ease;
        `;
        document.body.appendChild(toast);
        setTimeout(() => toast.remove(), 3000);
    }
}

customElements.define('project-export', ProjectExport);
