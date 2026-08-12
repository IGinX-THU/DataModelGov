class ProjectCreate extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });
        this.projectId = null;
        this.isEditMode = false;
    }

    async loadProjectFromAPI(projectId) {
        try {
            if (window.showGlobalLoading) {
                window.showGlobalLoading('正在加载项目...');
            }

            const result = await window.AppConfig.get('project', 'get', { projectId });
            
            if (result.code === 200 && result.data) {
                this.projectId = projectId;
                this.isEditMode = true;
                this.populateForm(result.data);
            } else {
                this.showToast(result.message || '加载项目失败', 'error');
            }
        } catch (error) {
            console.error('加载项目失败:', error);
            this.showToast('网络错误，无法加载项目', 'error');
        } finally {
            if (window.hideGlobalLoading) {
                window.hideGlobalLoading();
            }
        }
    }

    async loadAvailableResources() {
        // Simplified - no resource loading for modal version
    }

    async connectedCallback() {
        await this.loadResources();
        
        setTimeout(() => {
            this.bindEvents();
        }, 100);
    }

    async show(projectId = null) {
        console.log('ProjectCreate show() 被调用', projectId);
        
        if (projectId) {
            // Edit mode - not supported in modal version
            this.showToast('编辑模式暂不支持', 'error');
            return;
        }

        this.resetForm();
        this.isEditMode = false;
        this.projectId = null;
        
        // Show modal
        const modalMask = this.shadowRoot.getElementById('vsModalMask');
        if (modalMask) {
            modalMask.hidden = false;
            modalMask.style.display = 'flex';
        }
    }

    hide() {
        const modalMask = this.shadowRoot.getElementById('vsModalMask');
        if (modalMask) {
            modalMask.hidden = true;
            modalMask.style.display = 'none';
        }
    }

    async loadResources() {
        try {
            const cssLink = document.createElement('link');
            cssLink.rel = 'stylesheet';
            cssLink.href = './components/project-create/project-create.css';
            this.shadowRoot.appendChild(cssLink);
        } catch (error) {
            console.error('Failed to load CSS:', error);
        }

        if (window.location.protocol === 'file:') {
            this.shadowRoot.innerHTML += this.getFallbackHTML();
        } else {
            try {
                const response = await fetch('./components/project-create/project-create.html');
                if (!response.ok) {
                    throw new Error(`HTTP error! status: ${response.status}`);
                }
                const html = await response.text();
                this.shadowRoot.innerHTML += html;
                console.log('Project create HTML template loaded successfully');
            } catch (error) {
                console.error('Failed to load HTML template:', error);
                this.shadowRoot.innerHTML += this.getFallbackHTML();
            }
        }
    }

    getFallbackHTML() {
        return `
<div class="vs-modal-mask" id="vsModalMask" hidden>
    <div class="vs-modal">
        <div class="vs-modal-header">
            <div class="vs-modal-title">新建项目</div>
            <button class="vs-modal-close" id="vsModalClose">×</button>
        </div>
        <div class="vs-modal-body">
            <form id="projectForm" class="vs-project-form">
                <div class="vs-form-grid">
                    <div class="vs-form-left">
                        <div class="vs-form-section">
                            <h4>项目模板</h4>
                            <div class="vs-template-list">
                                <div class="vs-template-item active" data-type="simulation">
                                    <div class="vs-template-icon">📊</div>
                                    <div class="vs-template-info">
                                        <div class="vs-template-name">仿真项目</div>
                                        <div class="vs-template-desc">创建用于系统仿真的工程项目</div>
                                    </div>
                                </div>
                                <div class="vs-template-item" data-type="analysis">
                                    <div class="vs-template-icon">📈</div>
                                    <div class="vs-template-info">
                                        <div class="vs-template-name">分析项目</div>
                                        <div class="vs-template-desc">创建用于数据分析的工程项目</div>
                                    </div>
                                </div>
                                <div class="vs-template-item" data-type="research">
                                    <div class="vs-template-icon">🔬</div>
                                    <div class="vs-template-info">
                                        <div class="vs-template-name">研究项目</div>
                                        <div class="vs-template-desc">创建用于学术研究的工程项目</div>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                    <div class="vs-form-right">
                        <div class="vs-form-section">
                            <h4>项目详情</h4>
                            <div class="vs-form-row">
                                <label class="vs-form-label">项目名称 <span class="vs-required">*</span></label>
                                <input type="text" id="projectName" name="projectName" class="vs-form-input" required placeholder="输入项目名称">
                            </div>
                            <div class="vs-form-row">
                                <label class="vs-form-label">项目描述</label>
                                <textarea id="projectDescription" name="projectDescription" class="vs-form-textarea" rows="3" placeholder="输入项目描述"></textarea>
                            </div>
                            <input type="hidden" id="projectType" name="projectType" value="simulation">
                        </div>
                    </div>
                </div>
                <div class="vs-form-bottom">
                    <div class="vs-form-row-inline">
                        <label class="vs-form-label">位置:</label>
                        <input type="text" class="vs-form-input vs-location-input" value="C:\\Users\\Projects\\" readonly>
                    </div>
                    <div class="vs-form-actions">
                        <button type="button" class="vs-btn vs-btn-secondary" id="cancelBtn">取消</button>
                        <button type="submit" class="vs-btn vs-btn-primary" id="saveBtn">创建</button>
                    </div>
                </div>
            </form>
        </div>
    </div>
</div>`;
    }

    bindEvents() {
        if (this._eventsBound) {
            return;
        }
        this._eventsBound = true;

        this.shadowRoot.getElementById('vsModalClose')?.addEventListener('click', () => this.hide());
        this.shadowRoot.getElementById('cancelBtn')?.addEventListener('click', () => this.hide());
        this.shadowRoot.getElementById('projectForm')?.addEventListener('submit', (e) => this.handleSubmit(e));

        // Template selection
        this.shadowRoot.querySelectorAll('.vs-template-item').forEach(item => {
            item.addEventListener('click', () => {
                this.selectTemplate(item.dataset.type);
            });
        });
    }

    selectTemplate(type) {
        // Update active state
        this.shadowRoot.querySelectorAll('.vs-template-item').forEach(item => {
            item.classList.toggle('active', item.dataset.type === type);
        });

        // Update hidden field
        this.shadowRoot.getElementById('projectType').value = type;
    }

    populateForm(project) {
        // Not supported in modal version
    }

    resetForm() {
        this.shadowRoot.getElementById('projectForm').reset();
        // Reset template selection
        this.shadowRoot.querySelectorAll('.vs-template-item').forEach(item => {
            item.classList.toggle('active', item.dataset.type === 'simulation');
        });
        this.shadowRoot.getElementById('projectType').value = 'simulation';
    }

    async handleSubmit(e) {
        e.preventDefault();

        const name = this.shadowRoot.getElementById('projectName').value.trim();
        if (!name) {
            window.CommonUtils.showToast('请输入项目名称', 'error');
            return;
        }

        if (name.includes('.')) {
            window.CommonUtils.showToast('项目名称不允许包含点号(.)', 'error');
            return;
        }

        if (/^\d+$/.test(name)) {
            window.CommonUtils.showToast('项目名称不允许为纯数字', 'error');
            return;
        }

        if (/^_+$/.test(name)) {
            window.CommonUtils.showToast('项目名称不允许为纯下划线', 'error');
            return;
        }

        const projectData = {
            name: name,
            desc: this.shadowRoot.getElementById('projectDescription').value.trim()
        };

        try {
            if (window.showGlobalLoading) {
                window.showGlobalLoading('正在创建项目...');
            }

            const endpoint = this.isEditMode ? 'update' : 'create';
            const result = await window.AppConfig.post('project', endpoint, projectData);

            if (result.code === 200) {
                if (window.CommonUtils && window.CommonUtils.showToast) {
                    window.CommonUtils.showToast('项目创建成功');
                } else {
                    this.showToast('项目创建成功');
                }
                this.hide();

                // 保存项目信息到localStorage（按用户隔离）
                if (window.localStorage) {
                    const username = window.AppConfig.getUsername();
                    if (username) {
                        window.localStorage.setItem('currentProject_' + username, JSON.stringify({
                            name: name,
                            createTime: result.data?.createTime || Date.now()
                        }));
                    }
                }

                // 在项目侧边栏调用tree接口打开项目
                if (window.displayProjectTree) {
                    window.displayProjectTree(name);
                }
                // Refresh project list if visible
                const projectList = document.querySelector('project-list');
                if (projectList && projectList.style.display !== 'none') {
                    projectList.loadProjectsFromAPI();
                }
            } else {
                if (window.CommonUtils && window.CommonUtils.showToast) {
                    window.CommonUtils.showToast(result.message || '创建失败', 'error');
                } else {
                    this.showToast(result.message || '创建失败', 'error');
                }
            }
        } catch (error) {
            console.error('创建项目失败:', error);
            if (window.CommonUtils && window.CommonUtils.showToast) {
                window.CommonUtils.showToast('网络错误，创建失败', 'error');
            } else {
                this.showToast('网络错误，创建失败', 'error');
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
            background: ${type === 'success' ? '#0078d4' : '#d13438'};
            color: white;
            border-radius: 2px;
            z-index: 10001;
            font-size: 13px;
            font-family: inherit;
        `;
        document.body.appendChild(toast);
        setTimeout(() => toast.remove(), 3000);
    }
}

customElements.define('project-create', ProjectCreate);