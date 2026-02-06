/**
 * 通用弹窗管理器
 */
class ModalManager {
    constructor() {
        this.currentModal = null;
    }

    /**
     * 显示弹窗
     * @param {HTMLElement} component - 要显示的组件
     * @param {Object} options - 弹窗选项
     */
    show(component, options = {}) {
        // 如果已有弹窗，先关闭
        if (this.currentModal) {
            this.hide();
        }

        // 创建遮罩层
        const overlay = document.createElement('div');
        overlay.className = 'modal-overlay';
        overlay.style.cssText = `
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: rgba(0, 0, 0, 0.5);
            display: flex;
            align-items: center;
            justify-content: center;
            z-index: 1000;
            opacity: 0;
            transition: opacity 0.3s ease;
        `;

        // 创建弹窗容器
        const modal = document.createElement('div');
        modal.className = 'modal-container';
        modal.style.cssText = `
            background: white;
            border-radius: 8px;
            box-shadow: 0 4px 20px rgba(0, 0, 0, 0.15);
            max-width: ${options.maxWidth || '600px'};
            width: 90%;
            max-height: 80vh;
            overflow: hidden;
            transform: scale(0.9);
            transition: transform 0.3s ease;
            position: relative;
            z-index: 1001;
            display: flex;
            flex-direction: column;
        `;

        // 克隆组件内容到弹窗中
        const componentClone = this.cloneComponentContent(component);
        modal.appendChild(componentClone);

        // 添加到页面
        overlay.appendChild(modal);
        document.body.appendChild(overlay);

        // 动画显示
        requestAnimationFrame(() => {
            overlay.style.opacity = '1';
            modal.style.transform = 'scale(1)';
        });

        // 绑定关闭事件
        const closeDialog = () => {
            overlay.style.opacity = '0';
            modal.style.transform = 'scale(0.9)';
            setTimeout(() => {
                if (overlay.parentNode) {
                    overlay.parentNode.removeChild(overlay);
                }
                this.currentModal = null;
            }, 300);
        };

        // 点击遮罩关闭
        overlay.addEventListener('click', (e) => {
            if (e.target === overlay) {
                closeDialog();
            }
        });

        // ESC键关闭
        const handleEsc = (e) => {
            if (e.key === 'Escape') {
                closeDialog();
                document.removeEventListener('keydown', handleEsc);
            }
        };
        document.addEventListener('keydown', handleEsc);

        // 保存当前弹窗引用
        this.currentModal = {
            overlay,
            modal,
            component,
            close: closeDialog
        };

        return this.currentModal;
    }

    /**
     * 隐藏当前弹窗
     */
    hide() {
        if (this.currentModal) {
            this.currentModal.close();
        }
    }

    /**
     * 克隆组件内容（处理Shadow DOM）
     * @param {HTMLElement} component 
     * @returns {DocumentFragment}
     */
    cloneComponentContent(component) {
        const fragment = document.createDocumentFragment();
        
        // 获取组件的Shadow DOM内容
        const shadowRoot = component.shadowRoot;
        if (shadowRoot) {
            // 直接遍历Shadow DOM中的所有子节点
            const children = Array.from(shadowRoot.childNodes);
            
            // 查找并处理template标签
            children.forEach(child => {
                if (child.nodeName === 'TEMPLATE') {
                    // 展开template内容
                    const tempDiv = document.createElement('div');
                    tempDiv.innerHTML = child.innerHTML;
                    
                    // 将template内容添加到fragment
                    while (tempDiv.firstChild) {
                        fragment.appendChild(tempDiv.firstChild);
                    }
                } else if (child.nodeName === 'STYLE') {
                    // 跳过样式标签，因为已经在modal中处理了
                    return;
                } else {
                    // 克隆其他节点
                    const clonedChild = child.cloneNode(true);
                    fragment.appendChild(clonedChild);
                }
            });
        }
        
        return fragment;
    }
}

// 创建全局弹窗管理器实例
const modalManager = new ModalManager();

// 导出给其他组件使用
window.ModalManager = ModalManager;
window.modalManager = modalManager;
