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
                
                // 确保只处理左侧的节点
                if (!this.closest('.left-sidebar')) {
                    return;
                }
                
                // 先清除所有选中状态（仅限左侧）
                leftSidebarTree.querySelectorAll('.tree-node.active').forEach(n => n.classList.remove('active'));
                
                // 设置当前选中
                this.classList.add('active');
                
                // 更新选中的数据源（仅限左侧数据资源库）
                const nodeText = this.querySelector('span')?.textContent?.trim();
                const nodeIcon = this.querySelector('i');
                if (nodeText) {
                    selectedDataSource = nodeText;
                    console.log('选中的数据源:', selectedDataSource);
                    
                    // 检查是否为最后一级节点（没有子节点）
                    const hasChildren = this.querySelector('.tree-children');
                    
                    // 检查是否属于文件夹/数据库图标类数据源
                    let isFromFolderDataSource = false;
                    let isFromDatabaseSource = false;
                    
                    // 向上查找最近的父节点，检查是否有文件夹图标
                    let currentParent = this.parentElement;
                    while (currentParent) {
                        if (currentParent.classList.contains('tree-children')) {
                            // 跳过tree-children，继续向上找tree-node
                            currentParent = currentParent.parentElement;
                        } else if (currentParent.classList.contains('tree-node')) {
                            // 找到tree-node，检查图标
                            const parentIcon = currentParent.querySelector('i');
                            const parentText = currentParent.querySelector('span')?.textContent?.trim();
                            
                            console.log('检查父节点:', parentText, '图标:', parentIcon?.className);
                            
                            if (parentIcon && (parentIcon.classList.contains('folder-icon') || parentIcon.classList.contains('folder-open-icon'))) {
                                isFromFolderDataSource = true;
                                console.log('找到文件夹图标父节点:', parentText);
                                break;
                            }
                            if (parentIcon && parentIcon.classList.contains('db-icon')) {
                                isFromDatabaseSource = true;
                                console.log('找到数据库图标父节点:', parentText);
                                break;
                            }
                            currentParent = currentParent.parentElement;
                        } else {
                            break;
                        }
                    }
                    
                    console.log('节点检查:', {
                        nodeText: selectedDataSource,
                        hasChildren: !!hasChildren,
                        isFromFolderDataSource: isFromFolderDataSource,
                        isFromDatabaseSource: isFromDatabaseSource,
                        shouldShow: !hasChildren && (isFromFolderDataSource || isFromDatabaseSource)
                    });
                    
                    // 只有点击文件夹图标类数据源的最后一级节点才显示可视化
                    if (!hasChildren && isFromFolderDataSource) {
                        console.log('点击了文件夹图标类数据源的最后一级节点，显示数据可视化');
                        showDataVisualization(selectedDataSource);
                    }

                    if (!hasChildren && isFromDatabaseSource) {
                        console.log('点击了数据库图标类数据源的最后一级节点，显示数据库表格');
                        showDatabaseTable(selectedDataSource);
                    }
                }
                
                // 展开收起（如果有子节点）
                if (this.querySelector('.tree-children')) {
                    this.classList.toggle('expanded');
                }
            });
        });
    }

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
            
            // 检查是否点击了"上传模型文件"
            if (menuItemText === '上传模型文件') {
                console.log('上传模型文件菜单被点击');
                const modelUpload = document.getElementById('modelUpload');
                console.log('找到组件:', modelUpload);
                if (modelUpload) {
                    console.log('调用show方法');
                    modelUpload.show();
                } else {
                    console.error('未找到modelUpload组件');
                }
            }
            
            // 检查是否点击了"下载模型文件"
            if (menuItemText === '下载模型文件') {
                console.log('下载模型文件菜单被点击');
                const modelDownload = document.getElementById('modelDownload');
                console.log('找到组件:', modelDownload);
                if (modelDownload) {
                    console.log('调用show方法');
                    // 获取当前选中的模型
                    const selectedModel = getSelectedModel();
                    modelDownload.show(selectedModel);
                } else {
                    console.error('未找到modelDownload组件');
                }
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
                    const modelEdit = document.getElementById('modelEdit');
                    if (modelEdit) {
                        modelEdit.show(selectedModel);
                    } else {
                        console.error('未找到modelEdit组件');
                    }
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
                const parsingRules = document.getElementById('parsingRules');
                if (parsingRules) {
                    parsingRules.show();
                } else {
                    console.error('未找到parsingRules组件');
                }
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
                const modelDetail = document.getElementById('modelDetail');
                if (modelDetail) {
                    modelDetail.show(selectedModel);
                } else {
                    console.error('未找到modelDetail组件');
                }
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
        
        // 上传按钮
        if (btnText === '上传') {
            btn.addEventListener('click', function() {
                console.log('上传按钮被点击');
                const modelUpload = document.getElementById('modelUpload');
                console.log('找到组件:', modelUpload);
                if (modelUpload) {
                    console.log('调用show方法');
                    modelUpload.show();
                } else {
                    console.error('未找到modelUpload组件');
                }
            });
        }
        
        // 下载按钮
        if (btnText === '下载') {
            btn.addEventListener('click', function() {
                console.log('下载按钮被点击');
                const modelDownload = document.getElementById('modelDownload');
                console.log('找到组件:', modelDownload);
                if (modelDownload) {
                    console.log('调用show方法');
                    // 获取当前选中的模型
                    const selectedModel = getSelectedModel();
                    modelDownload.show(selectedModel);
                } else {
                    console.error('未找到modelDownload组件');
                }
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
        
        // 编辑按钮
        if (btnText === '编辑') {
            btn.addEventListener('click', function() {
                console.log('编辑按钮被点击');
                try {
                    const selectedModel = getSelectedModel();
                    console.log('选中的模型:', selectedModel);
                    if (selectedModel && selectedModel.version) {
                        const modelEdit = document.getElementById('modelEdit');
                        if (modelEdit) {
                            modelEdit.show(selectedModel);
                        } else {
                            console.error('未找到modelEdit组件');
                        }
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
                const parsingRules = document.getElementById('parsingRules');
                if (parsingRules) {
                    parsingRules.show();
                } else {
                    console.error('未找到parsingRules组件');
                }
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

    // 全局变量存储选中的测点
window.selectedDataPoints = new Set();

// 显示数据可视化
    function showDataVisualization(dataSource) {
        console.log('显示数据可视化:', dataSource);
        
        // 隐藏其他组件
        const registerEmbedded = document.getElementById('registerEmbedded');
        if (registerEmbedded) {
            registerEmbedded.hide();
        }
        const databaseTable = document.getElementById('databaseTable');
        if (databaseTable) {
            databaseTable.hide();
        }
        
        // 获取或创建数据可视化组件
        let dataViz = document.getElementById('dataVisualization');
        if (!dataViz) {
            dataViz = document.createElement('data-visualization');
            dataViz.id = 'dataVisualization';
            const workspaceContent = document.querySelector('.workspace-content');
            if (workspaceContent) {
                workspaceContent.appendChild(dataViz);
                console.log('创建了新的数据可视化组件');
            } else {
                console.error('找不到workspace-content容器');
                return;
            }
        } else {
            console.log('使用现有的数据可视化组件');
        }
        
        // 将当前数据源添加到已选测点
        window.selectedDataPoints.add(dataSource);
        
        console.log('准备显示可视化组件，当前选中的测点:', Array.from(window.selectedDataPoints));
        
        // 如果组件已存在，同步其选中的测点
        if (dataViz.selectedPoints) {
            dataViz.selectedPoints = new Set(window.selectedDataPoints);
        }
        
        // 显示数据可视化
        dataViz.show(dataSource, Array.from(window.selectedDataPoints));
    }

    function showDatabaseTable(tableName) {
        console.log('显示数据库表格:', tableName);
        const registerEmbedded = document.getElementById('registerEmbedded');
        if (registerEmbedded) {
            registerEmbedded.hide();
        }
        const dataViz = document.getElementById('dataVisualization');
        if (dataViz) {
            dataViz.hide();
        }
        const databaseTable = document.getElementById('databaseTable');
        if (databaseTable) {
            databaseTable.show(tableName);
        }
    }

    // 从树中获取所有可用的测点
    function getAvailablePointsFromTree() {
        const points = [];
        const leftSidebarTree = document.querySelector('.left-sidebar .tree');
        if (!leftSidebarTree) return points;
        
        // 查找所有最后一级节点
        const allNodes = leftSidebarTree.querySelectorAll('.tree-node');
        allNodes.forEach(node => {
            const hasChildren = node.querySelector('.tree-children');
            const nodeText = node.querySelector('span')?.textContent?.trim();
            
            // 只添加最后一级节点
            if (!hasChildren && nodeText) {
                points.push(nodeText);
            }
        });
        
        console.log('从树中获取到的测点:', points);
        return points;
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
});
