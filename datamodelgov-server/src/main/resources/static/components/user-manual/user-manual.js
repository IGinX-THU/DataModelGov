/**
 * 用户手册组件 - 纯JavaScript逻辑
 * 支持在线预览 DOCX 文档和下载功能
 */
class UserManual extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });
    }

    async connectedCallback() {
        await this.loadResources();
        setTimeout(() => {
            this.bindEvents();
        }, 100);
    }

    async loadResources() {
        // 加载CSS
        try {
            const cssLink = document.createElement('link');
            cssLink.rel = 'stylesheet';
            cssLink.href = './components/user-manual/user-manual.css';
            this.shadowRoot.appendChild(cssLink);
        } catch (error) {
            console.error('Failed to load CSS:', error);
        }

        if (window.location.protocol === 'file:') {
            this.shadowRoot.innerHTML += this.getFallbackHTML();
        } else {
            // 加载HTML
            try {
                const response = await fetch('./components/user-manual/user-manual.html');
                const html = await response.text();
                this.shadowRoot.innerHTML += html;
            } catch (error) {
                console.error('Failed to load HTML:', error);
                this.shadowRoot.innerHTML += this.getFallbackHTML();
            }
        }
    }

    getFallbackHTML() {
        return `
        <div class="user-manual-container">
            <div class="user-manual-toolbar">
                <div class="user-manual-title">用户手册</div>
                <button type="button" class="user-manual-download-btn" id="downloadBtn">下载用户手册</button>
            </div>
            <div class="user-manual-content">
                <div class="user-manual-loading">正在加载用户手册...</div>
            </div>
        </div>`;
    }

    show() {
        console.log('显示用户手册');
        this.setAttribute('show', '');
        this.loadManual();
    }

    hide() {
        console.log('隐藏用户手册');
        this.removeAttribute('show');
    }

    loadManual() {
        if (!window.docx || typeof window.docx.renderAsync !== 'function') {
            const content = this.shadowRoot.querySelector('.user-manual-content');
            if (content) {
                content.innerHTML = `
                    <div class="user-manual-error">
                        <h3>用户手册预览插件加载失败</h3>
                        <p>请检查网络连接或将 docx-preview 插件放入本地静态资源目录。</p>
                    </div>
                `;
            }
            return;
        }

        const manualUrl = `${window.AppConfig.api.baseURL}/api/doc/user-manual/file`;
        const content = this.shadowRoot.querySelector('.user-manual-content');
        
        if (content) {
            content.innerHTML = '<div class="user-manual-loading">正在加载用户手册...</div>';
        }

        fetch(manualUrl, {
            headers: window.AppConfig.getAuthHeaders()
        })
            .then(response => {
                if (!response.ok) {
                    throw new Error(`无法加载用户手册，HTTP状态码：${response.status}`);
                }
                return response.arrayBuffer();
            })
            .then(arrayBuffer => {
                if (content) {
                    content.innerHTML = '';
                    return window.docx.renderAsync(arrayBuffer, content, null, {
                        className: 'user-manual-docx',
                        inWrapper: true,
                        ignoreWidth: false,
                        ignoreHeight: false,
                        ignoreFonts: false,
                        breakPages: true,
                        renderHeaders: true,
                        renderFooters: true,
                        renderFootnotes: true,
                        renderEndnotes: true
                    });
                }
            })
            .catch(error => {
                console.error('加载用户手册失败:', error);
                if (content) {
                    content.innerHTML = `
                        <div class="user-manual-error">
                            <h3>加载用户手册失败</h3>
                            <p>${error.message}</p>
                            <p>请确认已登录、后端已重启，并且 doc 目录下存在用户手册文档。</p>
                        </div>
                    `;
                }
            });
    }

    bindEvents() {
        // 下载按钮
        const downloadBtn = this.shadowRoot.getElementById('downloadBtn');
        if (downloadBtn) {
            downloadBtn.addEventListener('click', () => {
                this.downloadManual();
            });
        }

        // ESC键关闭
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape' && this.hasAttribute('show')) {
                this.hide();
            }
        });
    }

    downloadManual() {
        const manualUrl = `${window.AppConfig.api.baseURL}/api/doc/user-manual/file`;
        
        fetch(manualUrl, {
            headers: window.AppConfig.getAuthHeaders()
        })
            .then(response => {
                if (!response.ok) {
                    throw new Error(`下载用户手册失败，HTTP状态码：${response.status}`);
                }
                return response.blob();
            })
            .then(blob => {
                const url = URL.createObjectURL(blob);
                const link = document.createElement('a');
                link.href = url;
                link.download = '数据与模型一体化管理软件-用户手册.docx';
                document.body.appendChild(link);
                link.click();
                link.remove();
                URL.revokeObjectURL(url);
            })
            .catch(error => {
                console.error('下载用户手册失败:', error);
                alert(error.message);
            });
    }
}

// 注册自定义元素
if (!customElements.get('user-manual')) {
    customElements.define('user-manual', UserManual);
}
