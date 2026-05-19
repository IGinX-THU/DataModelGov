class DataArchiveDetail extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });
        this.currentArchive = null;
    }

    async connectedCallback() {
        await this.loadResources();
        this.bindEvents();
    }

    async loadResources() {
        const cssResponse = await fetch('/components/data-archive-detail/data-archive-detail.css');
        const cssContent = await cssResponse.text();
        const style = document.createElement('style');
        style.textContent = cssContent;
        this.shadowRoot.appendChild(style);

        const htmlResponse = await fetch('/components/data-archive-detail/data-archive-detail.html');
        const htmlContent = await htmlResponse.text();
        const template = document.createElement('template');
        template.innerHTML = htmlContent;
        this.shadowRoot.appendChild(template.content.cloneNode(true));
    }

    getTemplate() {
        return ''; // HTML is loaded via fetch
    }

    bindEvents() {
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
                this.saveDescription();
            });
        }

        const cancelBtn = this.shadowRoot.getElementById('cancelBtn');
        if (cancelBtn) {
            cancelBtn.addEventListener('click', () => {
                this.cancelEdit();
            });
        }
    }

    enableEdit() {
        const detailDesc = this.shadowRoot.getElementById('detailDesc');
        const detailDescInput = this.shadowRoot.getElementById('detailDescInput');
        const editActions = this.shadowRoot.getElementById('editActions');
        const editBtn = this.shadowRoot.getElementById('editBtn');

        if (detailDesc && detailDescInput && editActions && editBtn) {
            detailDesc.style.display = 'none';
            detailDescInput.style.display = 'block';
            detailDescInput.value = detailDesc.textContent === '-' ? '' : detailDesc.textContent;
            editActions.style.display = 'flex';
            editBtn.style.display = 'none';
        }
    }

    cancelEdit() {
        const detailDesc = this.shadowRoot.getElementById('detailDesc');
        const detailDescInput = this.shadowRoot.getElementById('detailDescInput');
        const editActions = this.shadowRoot.getElementById('editActions');
        const editBtn = this.shadowRoot.getElementById('editBtn');

        if (detailDesc && detailDescInput && editActions && editBtn) {
            detailDesc.style.display = 'inline';
            detailDescInput.style.display = 'none';
            editActions.style.display = 'none';
            editBtn.style.display = 'inline-block';
        }
    }

    async saveDescription() {
        if (!this.currentArchive) {
            this.showToast('没有可编辑的数据档案', 'error');
            return;
        }

        const detailDescInput = this.shadowRoot.getElementById('detailDescInput');
        if (!detailDescInput) return;

        const newDesc = detailDescInput.value.trim();

        try {
            if (window.showGlobalLoading) {
                window.showGlobalLoading('正在保存描述信息...');
            }

            // 直接修改对象的desc属性
            this.currentArchive.desc = newDesc;
            const result = await window.AppConfig.post('dataArchive', 'update', this.currentArchive);

            if (result.code === 200) {
                const detailDesc = this.shadowRoot.getElementById('detailDesc');
                if (detailDesc) {
                    detailDesc.textContent = newDesc || '-';
                }
                this.cancelEdit();
                this.showToast('描述信息更新成功');
            } else {
                this.showToast(result.message || '更新失败', 'error');
            }
        } catch (error) {
            console.error('更新描述信息失败:', error);
            this.showToast('更新描述信息失败', 'error');
        } finally {
            if (window.hideGlobalLoading) {
                window.hideGlobalLoading();
            }
        }
    }

    async showDetail(name) {
        try {
            if (window.showGlobalLoading) {
                window.showGlobalLoading('正在加载数据档案详情...');
            }

            // 调用后端接口获取数据档案详情
            const result = await window.AppConfig.get('dataArchive', 'detail', { name });
            
            console.log('数据档案详情API返回:', result);

            if (result.code === 200 && result.data) {
                this.currentArchive = result.data;
                const archive = result.data;
                
                const detailName = this.shadowRoot.getElementById('detailName');
                const detailType = this.shadowRoot.getElementById('detailType');
                const detailDesc = this.shadowRoot.getElementById('detailDesc');
                const detailProjectName = this.shadowRoot.getElementById('detailProjectName');
                const detailOwner = this.shadowRoot.getElementById('detailOwner');
                const detailCreateTime = this.shadowRoot.getElementById('detailCreateTime');
                
                console.log('元素检查:', {
                    detailName: !!detailName,
                    detailType: !!detailType,
                    detailDesc: !!detailDesc,
                    detailProjectName: !!detailProjectName,
                    detailOwner: !!detailOwner,
                    detailCreateTime: !!detailCreateTime
                });
                
                if (detailName) detailName.textContent = archive.name || '-';
                if (detailType) detailType.textContent = archive.type || '-';
                if (detailDesc) detailDesc.textContent = archive.desc || '-';
                if (detailProjectName) detailProjectName.textContent = archive.projectName || '-';
                if (detailOwner) detailOwner.textContent = archive.owner || '-';
                if (detailCreateTime) detailCreateTime.textContent = archive.createTime ? new Date(archive.createTime).toLocaleString('zh-CN') : '-';

                console.log('设置显示样式为block');
                this.style.display = 'block';
            } else {
                console.error('API返回失败或无数据:', result);
                this.showToast('未找到数据档案', 'error');
            }
        } catch (error) {
            console.error('加载数据档案详情失败:', error);
            this.showToast('加载数据档案详情失败', 'error');
        } finally {
            if (window.hideGlobalLoading) {
                window.hideGlobalLoading();
            }
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

customElements.define('data-archive-detail', DataArchiveDetail);
