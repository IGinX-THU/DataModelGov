document.addEventListener('DOMContentLoaded', function() {
    // 全局变量：跟踪当前选中的数据源
    let selectedDataSource = null;
    
    // 全局Loading功能
    window.showGlobalLoading = function(message = '正在加载...') {
        console.log('显示全局loading:', message);
        
        // 获取工作区容器
        const workspaceContent = document.querySelector('.workspace-content');
        if (!workspaceContent) {
            console.error('找不到workspace-content容器');
            return;
        }
        
        // 确保工作区容器有相对定位
        if (getComputedStyle(workspaceContent).position === 'static') {
            workspaceContent.style.position = 'relative';
        }
        
        // 检查是否已存在loading元素
        let loadingEl = workspaceContent.querySelector('.global-loading-overlay');
        if (!loadingEl) {
            loadingEl = document.createElement('div');
            loadingEl.className = 'global-loading-overlay';
            loadingEl.innerHTML = `
                <div class="global-loading-spinner">
                    <div class="global-spinner"></div>
                    <div class="global-loading-text">${message}</div>
                </div>
            `;
            workspaceContent.appendChild(loadingEl);
        } else {
            // 更新loading文字
            const textEl = loadingEl.querySelector('.global-loading-text');
            if (textEl) {
                textEl.textContent = message;
            }
        }
    };
    
    window.hideGlobalLoading = function() {
        console.log('隐藏全局loading');
        
        // 从工作区容器中移除loading元素
        const workspaceContent = document.querySelector('.workspace-content');
        if (workspaceContent) {
            const loadingEl = workspaceContent.querySelector('.global-loading-overlay');
            if (loadingEl) {
                loadingEl.remove();
            }
        }
    };
    
    // 0. 动态加载数据源树
    loadDataSourceTree();
    
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

    // 2.5. 右侧模型资产库树形节点点击事件
    const rightSidebarTree = document.querySelector('.right-sidebar .tree');
    if (rightSidebarTree) {
        const rightTreeNodes = rightSidebarTree.querySelectorAll('.tree-node');
        rightTreeNodes.forEach(node => {
            node.addEventListener('click', function(e) {
                e.stopPropagation();
                
                // 确保只处理右侧的节点
                if (!this.closest('.right-sidebar')) {
                    return;
                }
                
                // 先清除所有选中状态（仅限右侧）
                rightSidebarTree.querySelectorAll('.tree-node.active').forEach(n => n.classList.remove('active'));
                
                // 设置当前选中
                this.classList.add('active');
                
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
            
            // 检查是否点击了"数据源管理"
            if (menuItemText === '数据源管理') {
                console.log('数据源管理菜单被点击');
                showComponent('dataSourceList');
            }
            
            // 检查是否点击了"注册异构数据源"
            if (menuItemText === '注册异构数据源') {
                console.log('注册异构数据源菜单被点击');
                showComponent('registerEmbedded');
            }
            
            // 检查是否点击了"上传模型文件"
            if (menuItemText === '上传模型文件') {
                console.log('上传模型文件菜单被点击');
                showComponent('modelUpload');
            }
            
            // 检查是否点击了"下载模型文件"
            if (menuItemText === '下载模型文件') {
                console.log('下载模型文件菜单被点击');
                const selectedModel = getSelectedModel();
                showComponent('modelDownload', selectedModel);
            }
            
            // 检查是否点击了"移除模型资产"
            if (menuItemText === '移除模型资产') {
                console.log('移除模型资产菜单被点击');
                const selectedModel = getSelectedModel();
                if (selectedModel) {
                    showDeleteConfirmDialog(selectedModel);
                } else {
                    showWorkspaceMessage('请先选择要移除的模型资产', 'warning');
                }
            }
            
            // 检查是否点击了"编辑元模型档案"
            if (menuItemText === '编辑元模型档案') {
                console.log('编辑元模型档案菜单被点击');
                const selectedModel = getSelectedModel();
                if (selectedModel && selectedModel.version) {
                    showComponent('modelEdit', selectedModel);
                } else {
                    showWorkspaceMessage('请先选择要编辑的模型版本', 'warning');
                }
            }
            
            // 检查是否点击了"移除异构数据源"
            if (menuItemText === '移除异构数据源') {
                console.log('移除异构数据源菜单被点击');
                handleRemoveDataSource();
            }
            
            // 检查是否点击了"配置解析规则"
            if (menuItemText === '配置解析规则') {
                console.log('配置解析规则菜单被点击');
                showComponent('parsingRules');
            }
            
            // 检查是否点击了"关联规则配置"
            if (menuItemText === '关联规则配置') {
                console.log('关联规则配置菜单被点击');
                showComponent('associationRules');
            }

            // 数值与曲线分析 - 新增
            if (menuItemText === '数值与曲线分析') {
                console.log('✅ 数值与曲线分析菜单被点击');
                
                // 先清空工作区
                clearWorkspace();
                
                showVisualAnalysis();
                return;
            }

            // 清空工作区 - 新增
            if (menuItemText === '清空工作区') {
                console.log('✅ 清空工作区菜单被点击');
                clearWorkspace();
                return;
            }

        });
    });

    // 获取当前选中的模型
    function getSelectedModel() {
        const rightSidebarTree = document.querySelector('.right-sidebar .tree');
        if (!rightSidebarTree) return null;
        
        const activeNode = rightSidebarTree.querySelector('.tree-node.active');
        if (!activeNode) return null;
        
        const span = activeNode.querySelector('span');
        if (!span) return null;
        
        const nodeName = span.textContent.trim();
        console.log('选中的节点名称:', nodeName);
        
        // 检查是否是版本号节点
        if (nodeName.match(/^v\d+\.\d+\.\d+$/)) {
            // 如果是版本号节点，获取父节点的模型名称
            const parentNode = activeNode.closest('.tree-children')?.parentElement;
            const parentSpan = parentNode?.querySelector('span');
            if (parentSpan) {
                const modelName = parentSpan.textContent.trim();
                console.log('找到模型名称:', modelName, '版本号:', nodeName);
                return {
                    name: modelName,
                    version: nodeName
                };
            }
        } else {
            // 如果是模型名称节点，查找第一个版本号
            const childrenContainer = activeNode.querySelector('.tree-children');
            if (childrenContainer && childrenContainer.children.length > 0) {
                // 如果有子节点，返回模型名称（表示删除所有版本，不显示版本号）
                console.log('找到模型名称（有子节点）:', nodeName, '将删除所有版本');
                return {
                    name: nodeName,
                    version: null // null表示删除所有版本
                };
            } else {
                // 如果没有子节点，查找第一个版本号（用于下载功能）
                const firstVersion = childrenContainer?.querySelector('.tree-node span');
                if (firstVersion) {
                    const versionText = firstVersion.textContent.trim();
                    if (versionText.match(/^v\d+\.\d+\.\d+$/)) {
                        console.log('找到模型名称:', nodeName, '版本号:', versionText);
                        return {
                            name: nodeName,
                            version: versionText
                        };
                    }
                }
            }
            
            // 如果没有版本号，只返回模型名称
            console.log('只找到模型名称（无子节点）:', nodeName);
            return {
                name: nodeName,
                version: null
            };
        }
        
        console.log('未找到有效的模型信息');
        return null;
    }

    // 5. 右侧树节点单击事件 - 显示模型详情
    document.querySelectorAll('.right-sidebar .tree-node').forEach(node => {
        node.addEventListener('click', function() {
            console.log('单击节点:', this);
            const selectedModel = getSelectedModel();
            if (selectedModel && selectedModel.version) {
                // 只有当有版本信息时才显示详情页面
                console.log('显示模型详情:', selectedModel);
                showComponent('modelDetail', selectedModel);
            } else {
                console.log('未获取到版本信息或点击的是父节点，不显示详情页面');
            }
        });
    });

    // 6. 功能按钮点击事件
    const addBtns = document.querySelectorAll('.func-btn');
    console.log('找到的功能按钮数量:', addBtns.length);
    
    addBtns.forEach((btn, index) => {
        // 获取按钮文字，排除图标
        const spans = btn.querySelectorAll('span');
        let btnText = '';
        for (let span of spans) {
            const text = span.textContent.trim();
            // 跳过图标（单个字符或符号）
            if (text.length > 1) {
                btnText = text;
                break;
            }
        }
        console.log(`按钮 ${index}: "${btnText}"`);
        
        // 分析按钮 - 新增
        if (btnText === '分析') {
            console.log('✅ 找到分析按钮，绑定事件');
            btn.addEventListener('click', function() {
                console.log('分析按钮被点击');
                
                // 先清空工作区
                clearWorkspace();
                
                showVisualAnalysis();
            });
        }
        
        // 新增按钮
        if (btnText === '新增') {
            btn.addEventListener('click', function() {
                console.log('新增按钮被点击');
                showComponent('registerEmbedded');
            });
        }
        
        // 上传按钮
        if (btnText === '上传') {
            btn.addEventListener('click', function() {
                console.log('上传按钮被点击');
                showComponent('modelUpload');
            });
        }
        
        // 下载按钮
        if (btnText === '下载') {
            btn.addEventListener('click', function() {
                console.log('下载按钮被点击');
                const selectedModel = getSelectedModel();
                showComponent('modelDownload', selectedModel);
            });
        }
        
        // 删除按钮
        if (btnText === '删除') {
            console.log('绑定删除按钮事件');
            btn.addEventListener('click', function() {
                console.log('删除按钮被点击');
                try {
                    const selectedModel = getSelectedModel();
                    console.log('选中的模型:', selectedModel);
                    if (selectedModel) {
                        showDeleteConfirmDialog(selectedModel);
                    } else {
                        showWorkspaceMessage('请先选择要删除的模型资产', 'warning');
                    }
                } catch (error) {
                    console.error('删除按钮点击出错:', error);
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

        if (btnText === '管理') {
            btn.addEventListener('click', function() {
                console.log('卸载按钮被点击');
                showComponent('dataSourceList');
            });
        }
        
        // 编辑按钮
        if (btnText === '编辑') {
            btn.addEventListener('click', function() {
                console.log('编辑按钮被点击');
                try {
                    const selectedModel = getSelectedModel();
                    console.log('选中的模型:', selectedModel);
                    if (selectedModel && selectedModel.version) {
                        showComponent('modelEdit', selectedModel);
                    } else {
                        showWorkspaceMessage('请先选择要编辑的模型版本', 'warning');
                    }
                } catch (error) {
                    console.error('编辑按钮点击出错:', error);
                }
            });
        }
        
        // 解析按钮
        if (btnText === '解析') {
            btn.addEventListener('click', function() {
                console.log('解析按钮被点击');
                showComponent('parsingRules');
            });
        }
        
        // 关联按钮
        if (btnText === '关联') {
            btn.addEventListener('click', function() {
                console.log('关联按钮被点击');
                showComponent('associationRules');
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

    // 监听模型上传成功事件
    const modelUpload = document.getElementById('modelUpload');
    if (modelUpload) {
        modelUpload.addEventListener('upload-success', function(e) {
            console.log('模型上传成功:', e.detail);
            
            // 在工作区显示成功消息
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
                    font-size: 14px;
                `;
                successMsg.innerHTML = `
                    <strong>模型上传成功！</strong><br>
                    模型名称: ${e.detail.modelName}<br>
                    版本号: ${e.detail.version}
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

    // 监听模型下载成功事件
    const modelDownload = document.getElementById('modelDownload');
    if (modelDownload) {
        modelDownload.addEventListener('download-success', function(e) {
            console.log('模型下载成功:', e.detail);
            
            // 在工作区显示成功消息
            const workspaceContent = document.querySelector('.workspace-content');
            if (workspaceContent) {
                const successMsg = document.createElement('div');
                successMsg.style.cssText = `
                    padding: 20px;
                    background: #f0fdf4;
                    border: 1px solid #bbf7d0;
                    border-radius: 6px;
                    color: #166534;
                    margin: 20px;
                    font-size: 14px;
                `;
                successMsg.innerHTML = `
                    <strong>模型下载成功！</strong><br>
                    模型名称: ${e.detail.modelName}<br>
                    版本号: ${e.detail.modelVersion}
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

    // 显示删除确认对话框
    function showDeleteConfirmDialog(selectedModel) {
        // 创建对话框HTML
        const dialogHtml = `
            <div class="delete-confirm-dialog" style="
                position: fixed;
                top: 0;
                left: 0;
                width: 100%;
                height: 100%;
                background: rgba(0, 0, 0, 0.5);
                display: flex;
                align-items: center;
                justify-content: center;
                z-index: 2000;
            ">
                <div class="dialog-content" style="
                    background: white;
                    border-radius: 8px;
                    padding: 24px;
                    max-width: 400px;
                    width: 90%;
                    box-shadow: 0 4px 20px rgba(0, 0, 0, 0.15);
                ">
                    <h3 style="margin: 0 0 16px 0; font-size: 18px; color: #1f2329;">确认删除</h3>
                    <p style="margin: 0 0 24px 0; color: #646a73; line-height: 1.5;">
                        ${selectedModel.version ? 
                            `确定要删除模型资产 <strong>${selectedModel.name}</strong> (版本: ${selectedModel.version}) 吗？` :
                            `确定要删除模型资产 <strong>${selectedModel.name}</strong> 及其所有版本吗？`
                        }<br><br>
                        <span style="color: #f5222d;">此操作不可恢复！</span>
                    </p>
                    <div class="dialog-actions" style="display: flex; gap: 12px; justify-content: flex-end;">
                        <button class="cancel-btn" style="
                            padding: 8px 16px;
                            border: 1px solid #c9cdd4;
                            border-radius: 4px;
                            background: white;
                            color: #1f2329;
                            cursor: pointer;
                            font-size: 14px;
                        ">取消</button>
                        <button class="confirm-btn" style="
                            padding: 8px 16px;
                            border: 1px solid #f5222d;
                            border-radius: 4px;
                            background: #f5222d;
                            color: white;
                            cursor: pointer;
                            font-size: 14px;
                        ">确认删除</button>
                    </div>
                </div>
            </div>
        `;
        
        // 创建对话框元素
        const dialog = document.createElement('div');
        dialog.innerHTML = dialogHtml;
        document.body.appendChild(dialog);
        
        // 绑定事件
        const cancelBtn = dialog.querySelector('.cancel-btn');
        const confirmBtn = dialog.querySelector('.confirm-btn');
        
        const closeDialog = () => {
            document.body.removeChild(dialog);
        };
        
        cancelBtn.addEventListener('click', closeDialog);
        
        confirmBtn.addEventListener('click', () => {
            closeDialog();
            deleteModelAsset(selectedModel);
        });
        
        // 点击遮罩关闭
        dialog.addEventListener('click', (e) => {
            if (e.target === dialog) {
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
    }

    // 删除模型资产
    window.deleteModelAsset = async function(selectedModel) {
        try {
            console.log('删除模型资产:', selectedModel);
            
            // 调用删除API
            const response = await fetch('/api/models/delete', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({
                    modelName: selectedModel.name,
                    version: selectedModel.version || null // null表示删除所有版本
                })
            });
            
            if (response.ok) {
                const result = await response.json();
                console.log('删除响应:', result);
                
                if (result.code === 200) {
                    showWorkspaceMessage(`模型资产 "${selectedModel.name}" 删除成功`, 'success');
                    
                    // 从右侧树中移除该节点
                    removeModelFromTree(selectedModel);
                    
                    // 清除选中状态
                    const rightSidebarTree = document.querySelector('.right-sidebar .tree');
                    if (rightSidebarTree) {
                        const activeNodes = rightSidebarTree.querySelectorAll('.tree-node.active');
                        activeNodes.forEach(node => node.classList.remove('active'));
                    }
                } else {
                    showWorkspaceMessage(result.message || '删除失败', 'error');
                }
            } else {
                throw new Error(`HTTP error! status: ${response.status}`);
            }
        } catch (error) {
            console.error('删除模型资产失败:', error);
            showWorkspaceMessage('删除失败，请稍后重试', 'error');
        }
    }

    // 从树中移除模型节点
    function removeModelFromTree(selectedModel) {
        const rightSidebarTree = document.querySelector('.right-sidebar .tree');
        if (!rightSidebarTree) return;
        
        const allNodes = rightSidebarTree.querySelectorAll('.tree-node');
        
        allNodes.forEach(node => {
            const span = node.querySelector('span');
            if (span) {
                const nodeName = span.textContent.trim();
                
                // 如果匹配要删除的模型名称，删除整个模型（包括所有版本）
                if (nodeName === selectedModel.name) {
                    node.remove();
                }
                // 如果只匹配版本号，只删除该版本节点
                else if (selectedModel.version && nodeName === selectedModel.version) {
                    node.remove();
                }
            }
        });
    }

    // 其他功能函数...

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
            
            // 获取当前选中的数据源节点信息
            const leftSidebarTree = document.querySelector('.left-sidebar .tree');
            const activeNode = leftSidebarTree?.querySelector('.tree-node.active');
            
            if (!activeNode) {
                showWorkspaceMessage('请先选择要删除的数据源', 'warning');
                return;
            }
            
            // 构建请求体数据
            const dataSourceInfo = {
                id: activeNode.dataset.id || 0,
                ip: activeNode.dataset.ip || '',
                port: parseInt(activeNode.dataset.port) || 0,
                type: parseInt(activeNode.dataset.type) || 0,
                schemaPrefix: null,
                dataPrefix: null
            };
            
            console.log('发送删除请求:', dataSourceInfo);
            
            const response = await fetch(window.AppConfig.getApiUrl('datasource', 'remove'), {
                method: 'DELETE',
                headers: {
                    ...window.AppConfig.getAuthHeaders(),
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify(dataSourceInfo)
            });

            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }

            const result = await response.json();
            console.log('删除响应:', result);

            if (result.code === 200) {
                showWorkspaceMessage(`数据源 "${alias}" 删除成功`, 'success');
                // 重新加载数据源树
                loadDataSourceTree();
                // 清除选中状态
                selectedDataSource = null;
                if (leftSidebarTree) {
                    leftSidebarTree.querySelectorAll('.tree-node.active').forEach(node => node.classList.remove('active'));
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
        if (window.CommonUtils && window.CommonUtils.showToast) {
            // 使用统一的 showToast
            window.CommonUtils.showToast(message, type);
        } else {
            // 回退实现
            console.warn(`[${type}] ${message}`);
        }
    }

    // 全局变量存储选中的测点
window.selectedDataPoints = new Set();

// 隐藏所有组件
function hideAllComponents() {
    console.log('🔄 隐藏所有组件');
    
    // 隐藏所有可能的组件
    const components = [
        'registerEmbedded',
        'modelUpload', 
        'modelDownload',
        'modelEdit',
        'parsingRules',
        'associationRules',
        'databaseTable',
        'dataVisualization',
        'modelDetail',
        'dataSourceList'
    ];
    
    components.forEach(componentId => {
        const component = document.getElementById(componentId);
        if (component) {
            // 只调用组件的hide方法，让组件自己管理隐藏逻辑
            if (typeof component.hide === 'function') {
                component.hide();
                console.log(`✅ 已隐藏组件: ${componentId}`);
            } else {
                // 如果没有hide方法，使用基本的隐藏方式
                component.removeAttribute('show');
                component.setAttribute('hidden', '');
                console.log(`✅ 已隐藏组件(基本方式): ${componentId}`);
            }
        }
    });
    
    // 额外清理：移除所有可能残留的动态创建的组件
    const workspace = document.querySelector('.workspace-content');
    if (workspace) {
        // 查找所有动态创建的组件并移除
        const dynamicComponents = workspace.querySelectorAll('visual-analysis, data-visualization');
        dynamicComponents.forEach(comp => {
            console.log(`🗑️ 移除动态组件: ${comp.tagName}`);
            comp.remove();
        });
    }
}

// 清空工作区
    function clearWorkspace() {
        console.log('🧹 清空工作区');
        
        // 隐藏所有可能显示的组件
        hideAllComponents();
        
        // 清除选中的测点
        if (window.selectedDataPoints) {
            window.selectedDataPoints.clear();
        }
        
        // 不清除导航树选中状态，只重置工作区相关的数据源
        // selectedDataSource = null; // 注释掉，保留数据源选择
        
        console.log('✅ 工作区已清空');
    }

// 显示数值与曲线分析
function showVisualAnalysis() {
    console.log('🚀 showVisualAnalysis() 函数被调用');
    
    // 创建并添加visual-analysis组件
    const visualAnalysis = document.createElement('visual-analysis');
    console.log('创建visual-analysis组件:', visualAnalysis);
    
    const workspace = document.querySelector('.workspace-content');
    if (workspace) {
        workspace.appendChild(visualAnalysis);
        console.log('组件已添加到工作区');
    } else {
        console.error('❌ 未找到工作区元素');
        return;
    }
    
    // 显示组件
    setTimeout(() => {
        console.log('调用visual-analysis.show()');
        visualAnalysis.show();
    }, 100);
    
    // 添加关闭事件监听
    visualAnalysis.addEventListener('close', () => {
        workspace.removeChild(visualAnalysis);
    });
    
    // 滚动到工作区
    workspace.scrollIntoView({ behavior: 'smooth' });
}

// 显示数据可视化
    function showDataVisualization(dataSource) {
        console.log('显示数据可视化:', dataSource);

        // 获取或创建数据可视化组件
        let dataViz = document.getElementById('dataVisualization');
        let isFirstLoad = false;
        
        if (!dataViz) {
            // 先清空工作区
            clearWorkspace();

            dataViz = document.createElement('data-visualization');
            dataViz.id = 'dataVisualization';
            const workspaceContent = document.querySelector('.workspace-content');
            if (workspaceContent) {
                workspaceContent.appendChild(dataViz);
                console.log('创建了新的数据可视化组件');
                isFirstLoad = true;
            } else {
                console.error('找不到workspace-content容器');
                return;
            }
        } else {
            console.log('使用现有的数据可视化组件');
        }
        
        // 只有真正的测点才添加到已选测点列表
        console.log('检查节点是否为测点:', dataSource);
        const isDataPoint = isActualDataPoint(dataSource);
        console.log('是否为测点:', isDataPoint);
        
        if (isDataPoint) {
            window.selectedDataPoints.add(dataSource);
            console.log('添加测点到已选列表:', dataSource);
        } else {
            console.log('跳过非测点节点:', dataSource);
        }
        
        console.log('准备显示可视化组件，当前选中的测点:', Array.from(window.selectedDataPoints));
        
        // 如果组件已存在，同步其选中的测点
        if (dataViz.selectedPoints) {
            dataViz.selectedPoints = new Set(window.selectedDataPoints);
        }
        
        // 先显示组件，等待组件完全加载后再调用查询接口
        setTimeout(() => {
            console.log('调用dataViz.show()，是否第一次加载:', isFirstLoad);
            dataViz.show(dataSource, Array.from(window.selectedDataPoints), null, !isFirstLoad);
            // 不在这里调用queryAndDisplayData，让组件自己处理数据加载
        }, 100); // 等待100ms确保组件已添加到DOM
    }

    // 查询并显示数据
    async function queryAndDisplayData(currentPath, selectedPoints, dataViz) {
        try {
            console.log('开始查询数据，当前路径:', currentPath, '选中测点:', selectedPoints);
            
            // 显示全局loading
            window.showGlobalLoading('正在查询数据...');
            
            // 从data-visualization组件中获取筛选参数
            let startTime = null;
            let endTime = null;
            let aggregateType = null;
            let precision = null;
            let timePrecision = 7; // 默认毫秒
            
            const startTimeInput = dataViz.shadowRoot.getElementById('startTime');
            const endTimeInput = dataViz.shadowRoot.getElementById('endTime');
            const aggregationSelect = dataViz.shadowRoot.getElementById('aggregationFunction');
            const precisionInput = dataViz.shadowRoot.getElementById('precision');
            const timePrecisionSelect = dataViz.shadowRoot.getElementById('timePrecision');
            
            // 处理时间参数
            if (startTimeInput && startTimeInput.value) {
                startTime = new Date(startTimeInput.value).getTime();
            }
            if (endTimeInput && endTimeInput.value) {
                endTime = new Date(endTimeInput.value).getTime();
            }
            
            // 如果没有设置时间，但有快速选择的时间，使用快速选择的时间
            if (startTime === null && endTime === null) {
                const activeQuickBtn = dataViz.shadowRoot.querySelector('.quick-time-btn.active');
                if (activeQuickBtn) {
                    const range = activeQuickBtn.dataset.range;
                    const endTimeDate = new Date();
                    const startTimeDate = new Date();
                    
                    switch (range) {
                        case '1h':
                            startTimeDate.setHours(startTimeDate.getHours() - 1);
                            break;
                        case '6h':
                            startTimeDate.setHours(startTimeDate.getHours() - 6);
                            break;
                        case '24h':
                            startTimeDate.setHours(startTimeDate.getHours() - 24);
                            break;
                        case '7d':
                            startTimeDate.setDate(startTimeDate.getDate() - 7);
                            break;
                    }
                    
                    startTime = startTimeDate.getTime();
                    endTime = endTimeDate.getTime();
                }
            }
            
            // 处理聚合函数参数
            if (aggregationSelect && aggregationSelect.value) {
                aggregateType = parseInt(aggregationSelect.value);
            }
            
            // 处理时间间隔参数
            if (precisionInput && precisionInput.value) {
                precision = parseInt(precisionInput.value);
            }
            
            // 处理时间单位参数
            if (timePrecisionSelect && timePrecisionSelect.value) {
                timePrecision = parseInt(timePrecisionSelect.value);
            }
            
            // 构建请求体
            const requestBody = {
                paths: selectedPoints,
                startTime: startTime,
                endTime: endTime,
                aggregateType: aggregateType,
                timePrecision: timePrecision
            };
            
            // 只有当precision不为null时才添加precision参数
            if (precision !== null) {
                requestBody.precision = precision;
            }
            
            console.log('从筛选框获取的查询参数:', requestBody);
            
            // 调用数据查询接口
            const response = await fetch(window.AppConfig.getApiUrl('data', 'query'), {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify(requestBody)
            });
            
            const result = await response.json();
            
            if (result.code === 200 && result.data) {
                console.log('数据查询成功:', result.data);
                
                // 显示数据可视化组件，传递查询结果
                dataViz.show(currentPath, selectedPoints, result.data);
            } else if (result.code === 200 && (!result.data || !result.data.records || result.data.records.length === 0)) {
                // 接口成功但没有数据
                console.log('查询成功但没有数据');
                dataViz.show(currentPath, selectedPoints, null);
            } else {
                // 接口返回错误
                console.error('数据查询失败:', result.message);
                dataViz.showError('数据查询失败: ' + (result.message || '未知错误'));
            }
        } catch (error) {
            console.error('查询数据时发生错误:', error);
            dataViz.showError('网络错误，无法查询数据');
        } finally {
            // 隐藏全局loading
            window.hideGlobalLoading();
        }
    }

// 通用显示组件函数
    function showComponent(componentId, ...args) {
        console.log(`显示组件: ${componentId}`, args);
        
        // 先清空工作区
        clearWorkspace();
        
        const component = document.getElementById(componentId);
        if (component) {
            // 确保组件可见：清除所有可能的隐藏属性和样式
            component.removeAttribute('hidden');
            component.style.display = '';
            component.style.visibility = '';
            
            // 调用组件的show方法
            if (typeof component.show === 'function') {
                component.show(...args);
            }
            
            console.log(`✅ 组件 ${componentId} 已显示`);
        } else {
            console.error(`❌ 未找到组件: ${componentId}`);
        }
    }

    function showDatabaseTable(tableName) {
        showComponent('databaseTable', tableName);
    }

    // 从树中获取所有可用的测点
    function getAvailablePointsFromTree() {
        const points = [];
        const leftSidebarTree = document.querySelector('.left-sidebar .tree');
        if (!leftSidebarTree) return points;
        
        // 获取当前选中的数据源节点
        const activeDataSourceNode = leftSidebarTree.querySelector('.tree-node.active');
        if (!activeDataSourceNode) {
            console.log('没有选中的数据源');
            return points;
        }
        
        // 只在当前选中的数据源节点内查找测点
        const dataSourceChildren = activeDataSourceNode.querySelectorAll('.tree-node');
        dataSourceChildren.forEach(node => {
            const hasChildren = node.querySelector('.tree-children');
            const nodeText = node.querySelector('span')?.textContent?.trim();
            
            // 只添加最后一级节点且是真正的测点
            if (!hasChildren && isActualDataPoint(nodeText)) {
                points.push(nodeText);
                console.log('添加测点:', nodeText);
            } else {
                console.log('跳过节点:', {
                    nodeText,
                    hasChildren: !!hasChildren,
                    isDataPoint: isActualDataPoint(nodeText)
                });
            }
        });
        
        console.log('从当前选中数据源获取到的测点:', points);
        return points;
    }
    
    // 判断节点是否为真正的测点
    function isActualDataPoint(nodeText) {
        console.log('isActualDataPoint 检查:', nodeText);
        
        if (!nodeText) {
            console.log('-> 空字符串，返回 false');
            return false;
        }
        
        // 排除IP:port格式的数据源节点
        if (nodeText.includes(':')) {
            console.log('-> 包含冒号，返回 false');
            return false;
        }
        
        // 排除emoji图标（这些是数据源父节点的图标）
        const emojis = ['🔌', '📊', '📈', '📁', '🗄', '🍃', '⚡'];
        if (emojis.includes(nodeText)) {
            console.log('-> 是emoji图标，返回 false');
            return false;
        }
        
        // 排除常见的父节点名称
        const parentNodes = ['root', 'car', 'database', 'table', 'schema'];
        if (parentNodes.includes(nodeText.toLowerCase())) {
            console.log('-> 是父节点名称，返回 false');
            return false;
        }
        
        // 排除空字符串和纯数字
        if (!nodeText.trim() || /^\d+$/.test(nodeText.trim())) {
            console.log('-> 是空字符串或纯数字，返回 false');
            return false;
        }
        
        console.log('-> 通过所有检查，返回 true');
        return true;
    }
    
    // 判断节点是否为数据源父节点（有data-type属性的节点）
    function isDataSourceParentNode(node) {
        return node.hasAttribute('data-type') || 
               node.parentElement?.hasAttribute('data-type') ||
               node.closest('[data-type]') !== null;
    }

    // 根据数据源获取模拟测点数据
    function getMockPointsForDataSource(dataSource) {
        const pointMap = {
            'X022-CQ-1': ['speed', 'rpm', 'temperature', 'pressure'],
            'X022-CQ-2': ['voltage', 'current', 'power', 'frequency'],
            'X022-CQ-4': ['position_x', 'position_y', 'velocity', 'acceleration'],
            'table1': ['flow_rate', 'level', 'density', 'viscosity'],
            's1': ['speed', 'fuel_consumption', 'engine_temp', 'tire_pressure'],
            'g1': ['longitude', 'latitude', 'altitude', 'heading'],
            'root': ['humidity', 'air_pressure', 'wind_speed', 'temperature'],
            'car': ['throttle', 'brake', 'steering', 'gear'],
            'pg_meta': ['connections', 'query_time', 'cache_hit_rate', 'cpu_usage'],
            'influx_local': ['write_rate', 'read_rate', 'disk_usage', 'memory_usage']
        };
        
        // 如果是s1或g1，返回它们自己作为测点
        if (dataSource === 's1') {
            return ['s1_speed', 's1_temp', 's1_pressure', 's1_flow'];
        }
        if (dataSource === 'g1') {
            return ['g1_x', 'g1_y', 'g1_z', 'g1_angle'];
        }
        
        return pointMap[dataSource] || ['value1', 'value2', 'value3'];
    }
    
    // 动态加载数据源树
    async function loadDataSourceTree() {
        try {
            // 显示全局loading
            window.showGlobalLoading('正在加载数据源...');
            
            const response = await fetch(window.AppConfig.getApiUrl('datasource', 'tree'));
            const result = await response.json();
            
            if (result.code === 200 && result.data) {
                renderDataSourceTree(result.data);
            } else {
                console.error('加载数据源树失败:', result.message);
                document.getElementById('dataSourceTree').innerHTML = '<div class="error-placeholder">加载数据源失败</div>';
            }
        } catch (error) {
            console.error('加载数据源树异常:', error);
            document.getElementById('dataSourceTree').innerHTML = '<div class="error-placeholder">网络错误，无法加载数据源</div>';
        } finally {
            // 隐藏全局loading
            window.hideGlobalLoading();
        }
    }
    
    // 将字符串数组或对象数组转换为树结构
    function buildTreeFromStringArray(data) {
        const tree = {};
        
        // 判断数据格式：如果是对象数组，使用path和dataType字段；如果是字符串数组，使用字符串本身
        data.forEach(item => {
            const path = typeof item === 'string' ? item : item.path;
            const dataType = typeof item === 'string' ? null : item.dataType;
            
            const parts = path.split('.');
            let current = tree;
            
            parts.forEach((part, index) => {
                if (!current[part]) {
                    current[part] = {
                        name: part,
                        children: {},
                        fullPath: parts.slice(0, index + 1).join('.'),
                        isLeaf: index === parts.length - 1,
                        dataType: index === parts.length - 1 ? dataType : null
                    };
                }
                current = current[part].children;
            });
        });
        
        return tree;
    }
    
    // 渲染树节点HTML
    function renderTreeNodes(treeData, level = 0) {
        let html = '';
        
        Object.values(treeData).forEach(node => {
            const hasChildren = Object.keys(node.children).length > 0;
            const expandedClass = level < 2 ? 'expanded' : '';
            const nodeClass = `tree-node ${expandedClass}`;
            
            // 根据节点类型选择图标
            let iconHtml = '';
            if (hasChildren) {
                // 有子节点：显示文件夹图标
                iconHtml = `<i class="icon folder-icon"></i>`;
            } else {
                // 没有子节点的叶子节点：根据数据类型显示图标
                const dataTypeIcons = {
                    0: '🔘',      // BOOLEAN(0) - 开关
                    1: '📈',      // INTEGER(1) - 曲线图
                    2: '📈',      // LONG(2) - 曲线图
                    3: '📈',      // FLOAT(3) - 曲线图
                    4: '📈',      // DOUBLE(4) - 曲线图
                    5: '📦'       // BINARY(5) - 包裹
                };
                const icon = dataTypeIcons[node.dataType] || '📈';
                iconHtml = `<i class="folder-icon">${icon}</i>`;
            }
            
            html += `
                <div class="${nodeClass}" data-full-path="${node.fullPath}" data-is-leaf="${node.isLeaf}" data-type="${node.dataType || ''}">
                    ${iconHtml}
                    <span>${node.name}</span>
            `;
            
            if (hasChildren) {
                html += '<div class="tree-children">';
                html += renderTreeNodes(node.children, level + 1);
                html += '</div>';
            }
            
            html += '</div>';
        });
        
        return html;
    }
    
    // 渲染数据源树
    function renderDataSourceTree(dataSources) {
        const treeContainer = document.getElementById('dataSourceTree');
        if (!dataSources || dataSources.length === 0) {
            treeContainer.innerHTML = '<div class="empty-placeholder">暂无数据源</div>';
            return;
        }
        
        // 将字符串数组转换为树结构
        const treeData = buildTreeFromStringArray(dataSources);
        
        // 渲染树HTML
        const treeHTML = renderTreeNodes(treeData);
        
        treeContainer.innerHTML = treeHTML;
        
        // 重新绑定树节点点击事件
        bindTreeEvents();
    }
    
    // 根据存储引擎类型获取图标
    function getStorageEngineIcon(type) {
        // 返回文字标识而不是图标，更明显
        const textMap = {
            0: '🔌',      // unknown
            1: '📊',       // iotdb12
            2: '📈',      // influxdb
            3: '📁',        // filesystem
            4: '🗄️',          // relational (MySQL, PostgreSQL等)
            5: '🍃',       // mongodb
            6: '⚡'        // redis
        };
        const icon = textMap[type] || '🗄️';
        console.log(`🔍 getStorageEngineIcon(${type}) = ${icon}`);
        return icon;
    }
    
    // 重新绑定树节点事件
    function bindTreeEvents() {
        const leftSidebarTree = document.querySelector('.left-sidebar .tree');
        if (leftSidebarTree) {
            const treeNodes = leftSidebarTree.querySelectorAll('.tree-node');
            treeNodes.forEach(node => {
                node.addEventListener('click', function(e) {
                    e.stopPropagation();
                    
                    // 确保只处理左侧的节点
                    if (!this.closest('.left-sidebar')) {
                        return;
                    }
                    
                    // 先清除所有选中状态（仅限左侧）
                    leftSidebarTree.querySelectorAll('.tree-node.active').forEach(n => n.classList.remove('active'));
                    
                    // 设置当前选中
                    this.classList.add('active');
                    
                    // 获取节点的完整路径
                    const fullPath = this.getAttribute('data-full-path');
                    const isLeaf = this.getAttribute('data-is-leaf') === 'true';
                    if (fullPath && isLeaf) {
                        console.log('点击了叶子节点:', fullPath);
                        selectedDataSource = fullPath;
                        
                        // 使用 dataSource.type === 1 的逻辑跳转到 data-visualization 页面
                        showDataVisualization(fullPath);
                        
                                                                        
                                                
                        // 如果是最后一级节点且不是文件夹/数据库图标类数据源，则显示“选择数据源”按钮
                                                
                        
                                            }
                    
                    // 展开收起（如果有子节点）
                    if (this.querySelector('.tree-children')) {
                        this.classList.toggle('expanded');
                    }
                });
            });
        }
    }
});
