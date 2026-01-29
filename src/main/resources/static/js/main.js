document.addEventListener('DOMContentLoaded', function() {
    // 全局变量：跟踪当前选中的数据源
    let selectedDataSource = null;
    // 1. 明暗模式切换
    const themeToggle = document.getElementById('themeToggle');
    const html = document.documentElement;

    themeToggle.addEventListener('click', function() {
        if (html.classList.contains('light-mode')) {
            html.classList.remove('light-mode');
            html.classList.add('dark-mode');
        } else {
            html.classList.remove('dark-mode');
            html.classList.add('light-mode');
        }
    });

    // 2. 树形节点点击事件（仅限左侧数据资源库）
    const leftSidebarTree = document.querySelector('.left-sidebar .tree');
    if (leftSidebarTree) {
        const treeNodes = leftSidebarTree.querySelectorAll('.tree-node');
        treeNodes.forEach(node => {
            node.addEventListener('click', function(e) {
                e.stopPropagation();
                
                // 先清除所有选中状态
                treeNodes.forEach(n => n.classList.remove('active'));
                
                // 设置当前选中
                this.classList.add('active');
                
                // 更新选中的数据源（仅限左侧数据资源库）
                const nodeText = this.querySelector('span')?.textContent?.trim();
                if (nodeText) {
                    selectedDataSource = nodeText;
                    console.log('选中的数据源:', selectedDataSource);
                }
                
                // 展开收起（如果有子节点）
                if (this.querySelector('.tree-children')) {
                    this.classList.toggle('expanded');
                }
            });
        });
    }

    // 3. 顶部选项卡切换
    const topTabs = document.querySelectorAll('.nav-tabs .tab:not(.dropdown)');
    topTabs.forEach(tab => {
        tab.addEventListener('click', function(e) {
            e.stopPropagation();
            topTabs.forEach(t => t.classList.remove('active'));
            this.classList.add('active');
        });
    });

    // 4. 二级选项卡切换
    const subTabs = document.querySelectorAll('.sub-tab-bar .sub-tab');
    subTabs.forEach(tab => {
        tab.addEventListener('click', function() {
            subTabs.forEach(t => t.classList.remove('active'));
            this.classList.add('active');
        });
    });

    // 5. 下拉菜单
    const dataDropdown = document.getElementById('dataDropdown');
    const modelDropdown = document.getElementById('modelDropdown');
    const scheduleDropdown = document.getElementById('scheduleDropdown');
    const analysisDropdown = document.getElementById('analysisDropdown');
    const toolDropdown = document.getElementById('toolDropdown');
    const windowDropdown = document.getElementById('windowDropdown');
    const helpDropdown = document.getElementById('helpDropdown');

    dataDropdown.addEventListener('click', function(e) {
        e.stopPropagation();
        modelDropdown.classList.remove('active');
        scheduleDropdown.classList.remove('active');
        analysisDropdown.classList.remove('active');
        toolDropdown.classList.remove('active');
        windowDropdown.classList.remove('active');
        helpDropdown.classList.remove('active');
        this.classList.toggle('active');
    });

    modelDropdown.addEventListener('click', function(e) {
        e.stopPropagation();
        dataDropdown.classList.remove('active');
        scheduleDropdown.classList.remove('active');
        analysisDropdown.classList.remove('active');
        toolDropdown.classList.remove('active');
        windowDropdown.classList.remove('active');
        helpDropdown.classList.remove('active');
        this.classList.toggle('active');
    });

    scheduleDropdown.addEventListener('click', function(e) {
        e.stopPropagation();
        dataDropdown.classList.remove('active');
        modelDropdown.classList.remove('active');
        analysisDropdown.classList.remove('active');
        toolDropdown.classList.remove('active');
        windowDropdown.classList.remove('active');
        helpDropdown.classList.remove('active');
        this.classList.toggle('active');
    });

    analysisDropdown.addEventListener('click', function(e) {
        e.stopPropagation();
        dataDropdown.classList.remove('active');
        modelDropdown.classList.remove('active');
        scheduleDropdown.classList.remove('active');
        toolDropdown.classList.remove('active');
        windowDropdown.classList.remove('active');
        helpDropdown.classList.remove('active');
        this.classList.toggle('active');
    });

    toolDropdown.addEventListener('click', function(e) {
        e.stopPropagation();
        dataDropdown.classList.remove('active');
        modelDropdown.classList.remove('active');
        scheduleDropdown.classList.remove('active');
        analysisDropdown.classList.remove('active');
        windowDropdown.classList.remove('active');
        helpDropdown.classList.remove('active');
        this.classList.toggle('active');
    });

    windowDropdown.addEventListener('click', function(e) {
        e.stopPropagation();
        dataDropdown.classList.remove('active');
        modelDropdown.classList.remove('active');
        scheduleDropdown.classList.remove('active');
        analysisDropdown.classList.remove('active');
        toolDropdown.classList.remove('active');
        helpDropdown.classList.remove('active');
        this.classList.toggle('active');
    });

    helpDropdown.addEventListener('click', function(e) {
        e.stopPropagation();
        dataDropdown.classList.remove('active');
        modelDropdown.classList.remove('active');
        scheduleDropdown.classList.remove('active');
        analysisDropdown.classList.remove('active');
        toolDropdown.classList.remove('active');
        windowDropdown.classList.remove('active');
        this.classList.toggle('active');
    });

    document.addEventListener('click', function() {
        dataDropdown.classList.remove('active');
        modelDropdown.classList.remove('active');
        scheduleDropdown.classList.remove('active');
        analysisDropdown.classList.remove('active');
        toolDropdown.classList.remove('active');
        windowDropdown.classList.remove('active');
        helpDropdown.classList.remove('active');
    });

    const menuItems = document.querySelectorAll('.dropdown-menu li');
    menuItems.forEach(item => {
        item.addEventListener('click', function(e) {
            e.stopPropagation();
            
            const menuItemText = this.textContent.trim();
            
            // 检查是否点击了"注册异构数据源"
            if (menuItemText === '注册异构数据源') {
                console.log('注册异构数据源菜单被点击');
                const embedded = document.getElementById('registerEmbedded');
                console.log('找到组件:', embedded);
                if (embedded) {
                    console.log('调用show方法');
                    embedded.show();
                } else {
                    console.error('未找到registerEmbedded组件');
                }
            }
            
            // 检查是否点击了"移除异构数据源"
            if (menuItemText === '移除异构数据源') {
                console.log('移除异构数据源菜单被点击');
                handleRemoveDataSource();
            }
        });
    });

    // 6. 功能按钮点击事件
    const addBtns = document.querySelectorAll('.func-btn');
    addBtns.forEach(btn => {
        const btnText = btn.querySelector('span')?.textContent?.trim();
        
        // 新增按钮
        if (btnText === '新增') {
            btn.addEventListener('click', function() {
                console.log('新增按钮被点击');
                const embedded = document.getElementById('registerEmbedded');
                console.log('找到组件:', embedded);
                if (embedded) {
                    console.log('调用show方法');
                    embedded.show();
                } else {
                    console.error('未找到registerEmbedded组件');
                }
            });
        }
        
        // 卸载按钮
        if (btnText === '卸载') {
            btn.addEventListener('click', function() {
                console.log('卸载按钮被点击');
                handleRemoveDataSource();
            });
        }
    });

    // 7. 监听内嵌页面提交事件
    const embedded = document.getElementById('registerEmbedded');
    if (embedded) {
        embedded.addEventListener('submit-success', function(e) {
            console.log('数据源注册成功:', e.detail);
            
            // 在工作区显示成功消息，但保留组件
            const workspaceContent = document.querySelector('.workspace-content');
            if (workspaceContent) {
                const successMsg = document.createElement('div');
                successMsg.style.cssText = `
                    padding: 20px;
                    background: #f0f9ff;
                    border: 1px solid #bfdbfe;
                    border-radius: 6px;
                    color: #1e40af;
                    margin: 20px;
                    text-align: center;
                `;
                successMsg.innerHTML = `
                    <h4 style="margin: 0 0 8px 0;">✅ 数据源注册成功</h4>
                    <p style="margin: 0; color: #64748b;">数据源 "${e.detail.formData.alias}" 已成功注册</p>
                `;
                
                // 在工作区开头插入成功消息，不清空整个工作区
                workspaceContent.insertBefore(successMsg, workspaceContent.firstChild);
                
                setTimeout(() => {
                    if (successMsg.parentNode) {
                        successMsg.remove();
                    }
                }, 5000);
            }
        });
    }

    // 删除数据源的处理函数
    function handleRemoveDataSource() {
        if (!selectedDataSource) {
            showWorkspaceMessage('请先选择要删除的数据源', 'warning');
            return;
        }

        // 获取最父级数据源名称
        const parentDataSource = getParentDataSource(selectedDataSource);
        
        showConfirmDialog(
            `确定要删除数据源 "${parentDataSource}" 吗？`,
            '删除后无法恢复，请谨慎操作。',
            () => {
                removeDataSource(parentDataSource);
            }
        );
    }

    // 获取最父级数据源名称（仅限左侧数据资源库）
    function getParentDataSource(selectedNode) {
        const leftSidebarTree = document.querySelector('.left-sidebar .tree');
        if (!leftSidebarTree) return selectedNode;
        
        const activeNode = leftSidebarTree.querySelector('.tree-node.active');
        if (!activeNode) return selectedNode;
        
        // 向上遍历找到最顶层的父节点
        let parentNode = activeNode;
        while (parentNode.parentElement && parentNode.parentElement.classList.contains('tree-children')) {
            parentNode = parentNode.parentElement.parentElement;
        }
        
        const parentText = parentNode.querySelector('span')?.textContent?.trim();
        return parentText || selectedNode;
    }

    // 显示确认对话框
    function showConfirmDialog(title, message, onConfirm) {
        // 移除已存在的对话框
        const existingDialog = document.querySelector('.confirm-dialog-overlay');
        if (existingDialog) {
            existingDialog.remove();
        }

        const overlay = document.createElement('div');
        overlay.className = 'confirm-dialog-overlay';
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

        const dialog = document.createElement('div');
        dialog.className = 'confirm-dialog';
        dialog.style.cssText = `
            background: white;
            border-radius: 8px;
            padding: 24px;
            max-width: 400px;
            width: 90%;
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.3);
            transform: scale(0.9);
            transition: transform 0.3s ease;
        `;

        dialog.innerHTML = `
            <h3 style="margin: 0 0 12px 0; font-size: 18px; font-weight: 600; color: #1f2329;">${title}</h3>
            <p style="margin: 0 0 24px 0; color: #646a73; line-height: 1.5;">${message}</p>
            <div style="display: flex; justify-content: flex-end; gap: 12px;">
                <button class="confirm-btn cancel" style="
                    padding: 8px 16px;
                    border: 1px solid #c9cdd4;
                    border-radius: 4px;
                    background: white;
                    color: #1f2329;
                    cursor: pointer;
                    font-size: 14px;
                    transition: all 0.2s;
                ">取消</button>
                <button class="confirm-btn confirm" style="
                    padding: 8px 16px;
                    border: 1px solid #f53f3f;
                    border-radius: 4px;
                    background: #f53f3f;
                    color: white;
                    cursor: pointer;
                    font-size: 14px;
                    transition: all 0.2s;
                ">确认删除</button>
            </div>
        `;

        overlay.appendChild(dialog);
        document.body.appendChild(overlay);

        // 动画显示
        setTimeout(() => {
            overlay.style.opacity = '1';
            dialog.style.transform = 'scale(1)';
        }, 10);

        // 绑定事件
        const cancelBtn = dialog.querySelector('.cancel');
        const confirmBtn = dialog.querySelector('.confirm');

        cancelBtn.addEventListener('click', () => {
            closeDialog();
        });

        confirmBtn.addEventListener('click', () => {
            closeDialog();
            onConfirm();
        });

        // 点击遮罩关闭
        overlay.addEventListener('click', (e) => {
            if (e.target === overlay) {
                closeDialog();
            }
        });

        // ESC键关闭
        const escHandler = (e) => {
            if (e.key === 'Escape') {
                closeDialog();
                document.removeEventListener('keydown', escHandler);
            }
        };
        document.addEventListener('keydown', escHandler);

        function closeDialog() {
            overlay.style.opacity = '0';
            dialog.style.transform = 'scale(0.9)';
            setTimeout(() => {
                if (overlay.parentNode) {
                    overlay.remove();
                }
            }, 300);
        }
    }

    // 删除数据源的API调用
    async function removeDataSource(alias) {
        try {
            console.log('开始删除数据源:', alias);
            
            const response = await fetch(window.AppConfig.getApiUrl('datasource', 'remove') + '/' + encodeURIComponent(alias), {
                method: 'DELETE',
                headers: window.AppConfig.getAuthHeaders()
            });

            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }

            const result = await response.json();
            console.log('删除响应:', result);

            if (result.code === 200) {
                showWorkspaceMessage(`数据源 "${alias}" 删除成功`, 'success');
                // 清除选中状态（仅限左侧数据资源库）
                selectedDataSource = null;
                const leftSidebarTree = document.querySelector('.left-sidebar .tree');
                if (leftSidebarTree) {
                    const activeNodes = leftSidebarTree.querySelectorAll('.tree-node.active');
                    activeNodes.forEach(node => node.classList.remove('active'));
                }
            } else {
                showWorkspaceMessage(result.message || '删除失败', 'error');
            }
        } catch (error) {
            console.error('删除数据源失败:', error);
            showWorkspaceMessage('删除失败，请稍后重试', 'error');
        }
    }

    // 在工作区显示消息提示
    function showWorkspaceMessage(message, type = 'info') {
        const workspaceContent = document.querySelector('.workspace-content');
        if (!workspaceContent) {
            console.error('未找到工作区容器');
            return;
        }

        // 移除已存在的消息
        const existingMessage = workspaceContent.querySelector('.workspace-message');
        if (existingMessage) {
            existingMessage.remove();
        }

        const messageEl = document.createElement('div');
        messageEl.className = 'workspace-message';
        
        // 根据消息类型设置样式和图标
        let bgColor, borderColor, textColor, icon;
        switch (type) {
            case 'success':
                bgColor = '#f0f9ff';
                borderColor = '#bfdbfe';
                textColor = '#1e40af';
                icon = '✅';
                break;
            case 'error':
                bgColor = '#fef2f2';
                borderColor = '#fecaca';
                textColor = '#dc2626';
                icon = '❌';
                break;
            case 'warning':
                bgColor = '#fffbeb';
                borderColor = '#fed7aa';
                textColor = '#ea580c';
                icon = '⚠️';
                break;
            default:
                bgColor = '#f0f9ff';
                borderColor = '#bfdbfe';
                textColor = '#1e40af';
                icon = 'ℹ️';
        }

        messageEl.style.cssText = `
            padding: 20px;
            background: ${bgColor};
            border: 1px solid ${borderColor};
            border-radius: 6px;
            color: ${textColor};
            margin: 20px;
            text-align: center;
            animation: slideIn 0.3s ease;
        `;

        let titleText = '';
        switch (type) {
            case 'success':
                titleText = '操作成功';
                break;
            case 'error':
                titleText = '操作失败';
                break;
            case 'warning':
                titleText = '警告';
                break;
            default:
                titleText = '提示';
        }

        messageEl.innerHTML = `
            <h4 style="margin: 0 0 8px 0;">${icon} ${titleText}</h4>
            <p style="margin: 0; color: ${type === 'success' ? '#64748b' : textColor};">${message}</p>
        `;

        // 在工作区开头插入消息
        workspaceContent.insertBefore(messageEl, workspaceContent.firstChild);

        // 根据消息类型设置不同的显示时间
        const duration = type === 'success' ? 5000 : 3000;

        setTimeout(() => {
            if (messageEl.parentNode) {
                messageEl.style.opacity = '0';
                messageEl.style.transform = 'translateY(-10px)';
                setTimeout(() => {
                    if (messageEl.parentNode) {
                        messageEl.remove();
                    }
                }, 300);
            }
        }, duration);
    }
});
