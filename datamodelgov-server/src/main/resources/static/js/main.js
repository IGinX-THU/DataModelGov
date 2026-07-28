document.addEventListener('DOMContentLoaded', function() {
    // 0. 用户认证和登录状态管理
    function checkLoginStatus() {
        if (window.AppConfig.isLoggedIn()) {
            const username = window.AppConfig.getUsername();
            const usernameEl = document.getElementById('username');
            const logoutBtn = document.getElementById('logoutBtn');
            
            if (usernameEl) {
                usernameEl.textContent = username || '已登录';
                usernameEl.title = `当前用户: ${username || '已登录'}`;
            }
            if (logoutBtn) {
                logoutBtn.style.display = 'inline-block';
            }
        } else {
            // 未登录，跳转到登录页
            window.location.href = '/login.html';
        }
    }

    // 登出功能
    function logout() {
        window.AppConfig.logout();
    }

    // 页面加载时检查登录状态
    checkLoginStatus();

    // 绑定登出按钮
    const logoutBtn = document.getElementById('logoutBtn');
    if (logoutBtn) {
        logoutBtn.addEventListener('click', function(e) {
            e.preventDefault();
            logout();
        });
    }

    // 视图切换按钮
    const viewToggleBtn = document.getElementById('viewToggleBtn');
    if (viewToggleBtn) {
        viewToggleBtn.addEventListener('click', function() {
            // 切换视图模式
            currentViewMode = currentViewMode === 'visualization' ? 'table' : 'visualization';
            const viewIcon = this.querySelector('.view-icon');
            const viewText = this.querySelector('.view-text');
            
            if (currentViewMode === 'table') {
                viewIcon.textContent = '📋';
                viewText.textContent = '表格视图';
                // this.classList.add('active');
                
                // 如果有选中的数据源，重新加载为表格视图
                if (selectedDataSource) {
                    const pathParts = selectedDataSource.split('.');
                    const parentPath = pathParts.slice(0, -1).join('.');
                    showDatabaseTable(parentPath);
                }
            } else {
                viewIcon.textContent = '📊';
                viewText.textContent = '图表视图';
                // this.classList.remove('active');
                
                // 如果有选中的数据源，重新加载为可视化视图
                if (selectedDataSource) {
                    showDataVisualization(selectedDataSource);
                }
            }
            
            console.log('视图模式切换为:', currentViewMode);
        });
    }

    // 全局变量：跟踪当前选中的数据源
    let selectedDataSource = null;
    
    // 视图模式：'visualization' 或 'table'
    let currentViewMode = 'visualization';
    
    // 隐藏所有组件的函数
    function hideAllComponents() {
        console.log('🔄 隐藏所有组件');
        
        // 隐藏所有可能的组件
        const components = [
            'registerEmbedded',
            'modelUpload', 
            'modelDownload',
            'modelEdit',
            'algorithmUpload',
            'algorithmDownload',
            'algorithmEdit',
            'parsingRules',
            'associationRules',
            'simulationArchiveList',
            'simulationArchiveDetail',
            'algorithmList',
            'databaseTable',
            'dataVisualization',
            'modelDetail',
            'algorithmDetail',
            'dataSourceList',
            'dataArchiveList',
            'importData',
            'userManagement',
            'permissionManagement',
            'projectList',
            'projectDetail',
            'projectCreate',
            'projectExport',
            'projectImport',
            'dataArchiveDetail',
            'modelArchiveList',
            'algorithmArchiveList',
            'programManagement',
            'programRun',
            'userManual'
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
            // 查找所有动态创建的组件并移除（只移除没有ID的动态组件）
            const dynamicComponents = workspace.querySelectorAll('visual-analysis:not([id]), data-visualization:not([id]), data-archive-detail:not([id]), data-archive-list:not([id]), simulation-record');
            dynamicComponents.forEach(comp => {
                console.log(`🗑️ 移除动态组件: ${comp.tagName}`);
                comp.remove();
            });
        }
    }
    
    // 初始化时隐藏所有组件
    console.log('🏁 页面加载完成，初始化组件状态');
    hideAllComponents();
    
    // 将hideAllComponents暴露到全局作用域
    window.hideAllComponents = hideAllComponents;
    
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
    
    // 0. 动态加载数据源树和项目树
    // 显示全局loading
    window.showGlobalLoading('正在加载数据资源...');
    loadDataSourceTree();
    loadProjectTree();

    // 移除页面初始化Loading遮罩层
    const pageLoadingOverlay = document.getElementById('pageLoadingOverlay');
    if (pageLoadingOverlay) {
        pageLoadingOverlay.remove();
    }

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

    // 2. 字体大小设置
    function applyFontScale(scale) {
        console.log('Setting font scale to:', scale);
        
        // If scale is undefined, don't apply it
        if (scale === undefined || scale === null) {
            console.warn('Font scale is undefined, skipping');
            return;
        }
        
        // Remove all font scale classes
        document.documentElement.classList.remove('font-scale-1', 'font-scale-1-15', 'font-scale-1-3', 'font-scale-1-5');
        
        // Add the appropriate class based on scale
        const scaleClassMap = {
            '1': 'font-scale-1',
            '1.15': 'font-scale-1-15',
            '1.3': 'font-scale-1-3',
            '1.5': 'font-scale-1-5'
        };
        
        const className = scaleClassMap[scale] || 'font-scale-1';
        document.documentElement.classList.add(className);
        
        console.log('Added class:', className);
        
        // 使用用户名作为键的一部分，使字体设置按用户隔离
        const username = window.MenuPermission?.currentUser?.username || 'default';
        localStorage.setItem('fontScale_' + username, scale);
        
        // 更新子菜单选中状态（只针对字体菜单项）
        document.querySelectorAll('.dropdown-menu .submenu li[data-scale]').forEach(li => {
            li.classList.remove('active');
            if (parseFloat(li.dataset.scale) === parseFloat(scale)) {
                li.classList.add('active');
            }
        });
    }

    // 页面加载时恢复保存的字体大小和主题模式（在用户信息加载后调用）
    function restoreUserSettings() {
        const username = window.MenuPermission?.currentUser?.username || 'default';
        console.log('restoreUserSettings called for user:', username);
        
        // 恢复字体大小
        const savedFontScale = localStorage.getItem('fontScale_' + username);
        console.log('Saved font scale for user', username, ':', savedFontScale);
        if (savedFontScale) {
            applyFontScale(savedFontScale);
        } else {
            // 默认选中"小"
            console.log('No saved font scale, using default 1');
            applyFontScale(1);
        }

        // 恢复主题模式
        const savedThemeMode = localStorage.getItem('themeMode_' + username);
        console.log('Saved theme mode for user', username, ':', savedThemeMode);
        const html = document.documentElement;
        if (savedThemeMode === 'dark') {
            html.classList.add('dark-mode');
            // 更新主题菜单选中状态
            document.querySelectorAll('#menu-light-mode, #menu-dark-mode').forEach(li => {
                li.classList.remove('active');
            });
            document.getElementById('menu-dark-mode').classList.add('active');
        } else if (savedThemeMode === 'light') {
            html.classList.add('light-mode');
            // 更新主题菜单选中状态
            document.querySelectorAll('#menu-light-mode, #menu-dark-mode').forEach(li => {
                li.classList.remove('active');
            });
            document.getElementById('menu-light-mode').classList.add('active');
        }
    }

    // 将恢复设置函数暴露到全局，供main-menu-permission.js调用
    window.restoreUserSettings = restoreUserSettings;

    // 2.5. 右侧模型资产库树形节点点击事件
    const modelTree = document.getElementById('modelTree');
    if (modelTree) {
        const rightTreeNodes = modelTree.querySelectorAll('.tree-node');
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
    const simulationDropdown = document.getElementById('simulationDropdown');
    const projectDropdown = document.getElementById('projectDropdown');
    const analysisDropdown = document.getElementById('analysisDropdown');
    const toolDropdown = document.getElementById('toolDropdown');
    const helpDropdown = document.getElementById('helpDropdown');
    const userDropdown = document.getElementById('userDropdown');
    const settingsDropdown = document.getElementById('settingsDropdown');

    const allDropdowns = [dataDropdown, modelDropdown, scheduleDropdown, simulationDropdown, projectDropdown, analysisDropdown, toolDropdown, helpDropdown, userDropdown, settingsDropdown];

    function closeAllDropdowns(except = null) {
        allDropdowns.forEach(dropdown => {
            if (dropdown && dropdown !== except) {
                dropdown.classList.remove('active');
            }
        });
    }

    dataDropdown.addEventListener('click', function(e) {
        e.stopPropagation();
        closeAllDropdowns(this);
        this.classList.toggle('active');
    });

    modelDropdown.addEventListener('click', function(e) {
        e.stopPropagation();
        closeAllDropdowns(this);
        this.classList.toggle('active');
    });

    scheduleDropdown.addEventListener('click', function(e) {
        e.stopPropagation();
        closeAllDropdowns(this);
        this.classList.toggle('active');
    });

    simulationDropdown.addEventListener('click', function(e) {
        e.stopPropagation();
        closeAllDropdowns(this);
        this.classList.toggle('active');
    });

    projectDropdown.addEventListener('click', function(e) {
        e.stopPropagation();
        closeAllDropdowns(this);
        this.classList.toggle('active');
    });

    analysisDropdown.addEventListener('click', function(e) {
        e.stopPropagation();
        closeAllDropdowns(this);
        this.classList.toggle('active');
    });

    toolDropdown.addEventListener('click', function(e) {
        e.stopPropagation();
        closeAllDropdowns(this);
        this.classList.toggle('active');
    });

    helpDropdown.addEventListener('click', function(e) {
        e.stopPropagation();
        closeAllDropdowns(this);
        this.classList.toggle('active');
    });

    userDropdown.addEventListener('click', function(e) {
        e.stopPropagation();
        closeAllDropdowns(this);
        this.classList.toggle('active');
    });

    settingsDropdown.addEventListener('click', function(e) {
        e.stopPropagation();
        closeAllDropdowns(this);
        this.classList.toggle('active');
    });

    // 绑定字体大小子菜单点击事件
    document.querySelectorAll('.dropdown-menu .submenu li[data-scale]').forEach(li => {
        li.addEventListener('click', function(e) {
            e.stopPropagation();
            e.stopImmediatePropagation(); // Prevent other event handlers from firing
            const scale = this.dataset.scale;
            applyFontScale(scale);
            closeAllDropdowns();
        });
    });

    document.addEventListener('click', function() {
        closeAllDropdowns();
    });

    // 跟踪最后点击的菜单项，用于实现二次点击刷新
    let lastClickedMenuId = null;

    const menuItems = document.querySelectorAll('.dropdown-menu li');
    menuItems.forEach(item => {
        item.addEventListener('click', function(e) {
            e.stopPropagation();

            // Skip font size submenu items - they are handled separately
            if (this.hasAttribute('data-scale')) {
                return;
            }

            // Skip submenu parents (has-submenu class) - they don't have actions
            if (this.classList.contains('has-submenu')) {
                return;
            }

            const menuId = this.id;
            console.log(`菜单项被点击: ${menuId}`);

            // 根据菜单ID获取对应的动作
            const action = getMenuAction(menuId);

            // 检查是否是二次点击同一菜单项，如果是则清空工作区实现刷新
            const isSecondClick = (lastClickedMenuId === menuId);
            lastClickedMenuId = menuId;

            if (action) {
                // 关闭所有下拉菜单
                closeAllDropdowns();
                
                // 根据动作类型执行相应操作
                switch (action) {
                    case 'showProjectCreate':
                        console.log('新建项目菜单被点击');
                        showComponent('projectCreate');
                        break;
                    case 'showProjectList':
                        console.log('打开项目菜单被点击');
                        showComponent('projectList');
                        break;
                    case 'showProjectExport':
                        console.log('导出项目菜单被点击');
                        showComponent('projectExport');
                        break;
                    case 'showProjectImport':
                        console.log('导入项目菜单被点击');
                        showComponent('projectImport');
                        break;
                    case 'showDataSourceList':
                        console.log('异构数据源管理菜单被点击');
                        if (isSecondClick) clearWorkspace();
                        showComponent('dataSourceList');
                        break;
                    case 'showDataArchiveList':
                        console.log('数据档案查询菜单被点击');
                        if (isSecondClick) clearWorkspace();
                        showComponent('dataArchiveList');
                        break;
                    case 'showModelArchiveList':
                        console.log('模型档案查询菜单被点击');
                        if (isSecondClick) clearWorkspace();
                        showComponent('modelArchiveList');
                        break;
                    case 'showAlgorithmArchiveList':
                        console.log('算法档案查询菜单被点击');
                        if (isSecondClick) clearWorkspace();
                        showComponent('algorithmArchiveList');
                        break;
                    case 'showProjectImportData':
                        window.showProjectImportWizard('data');
                        break;
                    case 'showProjectImportModel':
                        window.showProjectImportWizard('model');
                        break;
                    case 'showProjectImportAlgorithm':
                        window.showProjectImportWizard('algorithm');
                        break;
                    case 'showProjectImportSimulation':
                        window.showProjectImportWizard('simulation');
                        break;
                    case 'showProjectExportData':
                        window.showProjectExportWizard('data');
                        break;
                    case 'showProjectExportModel':
                        window.showProjectExportWizard('model');
                        break;
                    case 'showProjectExportAlgorithm':
                        window.showProjectExportWizard('algorithm');
                        break;
                    case 'showProjectExportSimulation':
                        window.showProjectExportWizard('simulation');
                        break;
                    case 'console.log':
                        console.log('数据源管理被点击');
                        break;
                    case 'showRegisterEmbedded':
                        console.log('注册异构数据源菜单被点击');
                        showComponent('registerEmbedded');
                        break;
                    case 'showImportData':
                        console.log('导入数据菜单被点击');
                        showComponent('importData');
                        break;
                    case 'showModelUpload':
                        console.log('上传模型文件菜单被点击');
                        showComponent('modelUpload');
                        break;
                    case 'showAlgorithmUpload':
                        console.log('上传算法文件菜单被点击');
                        showComponent('algorithmUpload');
                        break;
                    case 'handleDownload':
                        console.log('下载模型文件菜单被点击');
                        // 检查模型侧边栏是否打开，如果未打开则自动打开
                        const activeModelIconDownloadMenu = document.querySelector('.bottom-sidebar-icon.right-sidebar-icon.active[data-panel="model"]');
                        if (!activeModelIconDownloadMenu) {
                            const modelIcon = document.querySelector('.bottom-sidebar-icon.right-sidebar-icon[data-panel="model"]');
                            if (modelIcon) {
                                modelIcon.click();
                            }
                        }
                        const selectedModel = getSelectedModel();
                        showComponent('modelDownload', selectedModel);
                        break;
                    case 'handleAlgorithmDownload':
                        console.log('下载算法文件菜单被点击');
                        // 检查算法侧边栏是否打开，如果未打开则自动打开
                        const activeAlgorithmIconDownloadMenu = document.querySelector('.bottom-sidebar-icon.right-sidebar-icon.active[data-panel="algorithm"]');
                        if (!activeAlgorithmIconDownloadMenu) {
                            const algorithmIcon = document.querySelector('.bottom-sidebar-icon.right-sidebar-icon[data-panel="algorithm"]');
                            if (algorithmIcon) {
                                algorithmIcon.click();
                            }
                        }
                        const selectedAlgorithm = getSelectedAlgorithm();
                        showComponent('algorithmDownload', selectedAlgorithm);
                        break;
                    case 'handleDeleteModel':
                        console.log('移除模型资产菜单被点击');
                        const activeModelIconDeleteMenu = document.querySelector('.bottom-sidebar-icon.right-sidebar-icon.active[data-panel="model"]');
                        if (!activeModelIconDeleteMenu) {
                            showWorkspaceMessage('请先打开模型侧边栏', 'warning');
                            break;
                        }
                        const selectedModelDelete = getSelectedModel();
                        if (selectedModelDelete) {
                            showDeleteConfirmDialog(selectedModelDelete);
                        } else {
                            showWorkspaceMessage('请先选择要移除的模型资产', 'warning');
                        }
                        break;
                    case 'handleEditModel':
                        console.log('编辑元模型档案菜单被点击');
                        const activeModelIconEditMenu = document.querySelector('.bottom-sidebar-icon.right-sidebar-icon.active[data-panel="model"]');
                        if (!activeModelIconEditMenu) {
                            showWorkspaceMessage('请先打开模型侧边栏', 'warning');
                            break;
                        }
                        const selectedModelEdit = getSelectedModel();
                        if (selectedModelEdit && selectedModelEdit.version) {
                            showComponent('modelEdit', selectedModelEdit);
                        } else {
                            showWorkspaceMessage('请先选择要编辑的模型版本', 'warning');
                        }
                        break;
                    case 'handleEditAlgorithm':
                        console.log('编辑元算法档案菜单被点击');
                        const activeAlgorithmIconEditMenu = document.querySelector('.bottom-sidebar-icon.right-sidebar-icon.active[data-panel="algorithm"]');
                        if (!activeAlgorithmIconEditMenu) {
                            showWorkspaceMessage('请先打开算法侧边栏', 'warning');
                            break;
                        }
                        const selectedAlgorithmEdit = getSelectedAlgorithm();
                        if (selectedAlgorithmEdit && selectedAlgorithmEdit.version) {
                            showComponent('algorithmEdit', selectedAlgorithmEdit);
                        } else {
                            showWorkspaceMessage('请先选择要编辑的算法版本', 'warning');
                        }
                        break;
                    case 'handleDeleteAlgorithm':
                        console.log('移除算法资产菜单被点击');
                        const activeAlgorithmIconDeleteMenu = document.querySelector('.bottom-sidebar-icon.right-sidebar-icon.active[data-panel="algorithm"]');
                        if (!activeAlgorithmIconDeleteMenu) {
                            showWorkspaceMessage('请先打开算法侧边栏', 'warning');
                            break;
                        }
                        const selectedAlgorithmDelete = getSelectedAlgorithm();
                        if (selectedAlgorithmDelete) {
                            showDeleteConfirmDialogAlgorithm(selectedAlgorithmDelete);
                        } else {
                            showWorkspaceMessage('请先选择要移除的算法资产', 'warning');
                        }
                        break;
                    case 'showParsingRules':
                        console.log('配置解析规则菜单被点击');
                        if (isSecondClick) clearWorkspace();
                        showComponent('parsingRules');
                        break;
                    case 'showAssociationRules':
                        console.log('关联规则配置菜单被点击');
                        if (isSecondClick) clearWorkspace();
                        showComponent('associationRules');
                        break;
                    case 'showSimulationArchive':
                        console.log('仿真档案管理菜单被点击');
                        clearWorkspace();
                        showComponent('simulationArchiveList');
                        break;
                    case 'showSimulationRecord':
                        console.log('仿真记录菜单被点击');
                        clearWorkspace();
                        showSimulationRecord();
                        return;
                    case 'showProgramUpload':
                        console.log('仿真程序上传菜单被点击');
                        clearWorkspace();
                        showComponent('programUpload');
                        return;
                    case 'showProgramManagement':
                        console.log('程序管理菜单被点击');
                        clearWorkspace();
                        showComponent('programManagement');
                        return;
                    case 'showProgramRun':
                        console.log('运行结果菜单被点击');
                        clearWorkspace();
                        showComponent('programRun');
                        return;
                    case 'showAlgorithmList':
                        console.log('算法管理菜单被点击');
                        if (isSecondClick) clearWorkspace();
                        showComponent('algorithmList');
                        break;
                    case 'showProjectList':
                        console.log('项目管理菜单被点击');
                        if (isSecondClick) clearWorkspace();
                        showComponent('projectList');
                        break;
                    case 'showProjectCreate':
                        console.log('新增项目菜单被点击');
                        if (isSecondClick) clearWorkspace();
                        showComponent('projectCreate');
                        break;
                    case 'showProjectExport':
                        console.log('导出项目菜单被点击');
                        if (isSecondClick) clearWorkspace();
                        showComponent('projectExport');
                        break;
                    case 'showProjectImport':
                        console.log('导入项目菜单被点击');
                        if (isSecondClick) clearWorkspace();
                        showComponent('projectImport');
                        break;
                    case 'showVisualAnalysis':
                        console.log('数值与曲线分析菜单被点击');
                        if (isSecondClick) clearWorkspace();
                        showComponent('visualAnalysis');
                        return;
                    case 'clearWorkspace':
                        console.log('清空工作区菜单被点击');
                        clearWorkspace();
                        return;
                    case 'setLightMode':
                        console.log('明亮模式菜单被点击');
                        const html = document.documentElement;
                        console.log('Before setLightMode, classes:', html.className);
                        html.classList.remove('dark-mode');
                        html.classList.add('light-mode');
                        console.log('After setLightMode, classes:', html.className);
                        // 保存主题模式到localStorage（按用户隔离）
                        const usernameLight = window.MenuPermission?.currentUser?.username || 'default';
                        localStorage.setItem('themeMode_' + usernameLight, 'light');
                        // 更新主题菜单选中状态
                        document.querySelectorAll('#menu-light-mode, #menu-dark-mode').forEach(li => {
                            li.classList.remove('active');
                        });
                        document.getElementById('menu-light-mode').classList.add('active');
                        break;
                    case 'setDarkMode':
                        console.log('暗黑模式菜单被点击');
                        const htmlDark = document.documentElement;
                        console.log('Before setDarkMode, classes:', htmlDark.className);
                        htmlDark.classList.remove('light-mode');
                        htmlDark.classList.add('dark-mode');
                        console.log('After setDarkMode, classes:', htmlDark.className);
                        // 保存主题模式到localStorage（按用户隔离）
                        const usernameDark = window.MenuPermission?.currentUser?.username || 'default';
                        localStorage.setItem('themeMode_' + usernameDark, 'dark');
                        // 更新主题菜单选中状态
                        document.querySelectorAll('#menu-light-mode, #menu-dark-mode').forEach(li => {
                            li.classList.remove('active');
                        });
                        document.getElementById('menu-dark-mode').classList.add('active');
                        break;
                    case 'showAbout':
                        console.log('关于菜单被点击');
                        showAbout();
                        break;
                    case 'showUserManual':
                        console.log('用户手册菜单被点击');
                        if (typeof window.showComponent === 'function') {
                            window.showComponent('userManual');
                        } else {
                            console.error('window.showComponent函数未找到');
                        }
                        break;
                    default:
                        console.warn(`未知的菜单动作: ${action}`);
                }
            } else {
                // 关闭所有下拉菜单
                closeAllDropdowns();
                
                // 处理特殊菜单项（用户管理和修改密码）
                if (menuId === 'userManagementMenuItem') {
                    console.log('用户管理菜单被点击');
                    if (isSecondClick) clearWorkspace();
                    showComponent('userManagement');
                } else if (menuId === 'permissionManagementMenuItem') {
                    console.log('权限管理菜单被点击');
                    if (isSecondClick) clearWorkspace();
                    showComponent('permissionManagement');
                } else if (menuId === 'changePasswordMenuItem') {
                    console.log('修改密码菜单被点击');
                    const changePasswordComponent = document.querySelector('change-password');
                    if (changePasswordComponent) {
                        changePasswordComponent.show();
                    }
                } else if (menuId === 'menu-project-list') {
                    console.log('项目管理菜单被点击');
                    if (isSecondClick) clearWorkspace();
                    showComponent('projectList');
                } else if (menuId === 'menu-project-new') {
                    console.log('新增项目菜单被点击');
                    if (isSecondClick) clearWorkspace();
                    showComponent('projectCreate');
                } else if (menuId === 'menu-project-export') {
                    console.log('导出项目菜单被点击');
                    if (isSecondClick) clearWorkspace();
                    showComponent('projectExport');
                } else if (menuId === 'menu-project-import') {
                    console.log('导入项目菜单被点击');
                    if (isSecondClick) clearWorkspace();
                    showComponent('projectImport');
                } else {
                    console.warn(`未找到菜单ID ${menuId} 的对应动作`);
                }
            }
        });
    });

    // 获取当前选中的模型
    function getSelectedModel() {
        const modelTree = document.getElementById('modelTree');
        if (!modelTree) return null;

        const activeNode = modelTree.querySelector('.tree-node.active');
        if (!activeNode) return null;

        const span = activeNode.querySelector('span');
        if (!span) return null;

        const nodeName = span.textContent.trim();
        console.log('选中的节点名称:', nodeName);

        // 排除明显的路径节点
        if (nodeName === 'filesystem' || nodeName === 'models') {
            console.log('选中的是路径节点，不是有效的模型节点');
            return null;
        }

        // 检查是否是最后一级叶子节点（没有子节点的节点）
        const childrenContainer = activeNode.querySelector('.tree-children');
        if (!childrenContainer || childrenContainer.children.length === 0) {
            // 如果是最后一级叶子节点，获取其直接父节点的模型名称
            const parentNode = activeNode.closest('.tree-children')?.parentElement;
            const parentSpan = parentNode?.querySelector('span');
            if (parentSpan) {
                let modelName = parentSpan.textContent.trim();
                // 去掉前缀（如 models_system.projectName.）
                modelName = stripStoragePrefix(modelName);
                // 再次检查父节点也不是路径节点
                if (modelName !== 'filesystem' && modelName !== 'models') {
                    console.log('找到模型名称（最后一级叶子节点的父节点）:', modelName, '版本号（最后一级叶子节点）:', nodeName);
                    // 从当前选中节点（版本号节点）的data-full-path属性获取完整路径
                    const fullPath = activeNode.getAttribute('data-full-path');
                    console.log('版本历史使用的完整路径:', fullPath);
                    return {
                        name: modelName,
                        version: nodeName,
                        fullPath: fullPath // 保存完整路径用于提取项目名称
                    };
                }
            }
        } else {
            // 如果是模型名称节点，检查是否有最后一级叶子节点子节点
            if (childrenContainer && childrenContainer.children.length > 0) {
                // 检查子节点是否包含最后一级叶子节点
                const childNodes = childrenContainer.querySelectorAll('.tree-node');
                let hasLeafChild = false;

                childNodes.forEach(childNode => {
                    const childChildrenContainer = childNode.querySelector('.tree-children');
                    if (!childChildrenContainer || childChildrenContainer.children.length === 0) {
                        hasLeafChild = true;
                    }
                });

                if (hasLeafChild) {
                    // 删除操作只针对最后一级节点，不返回模型名称节点
                    console.log('选中的是模型名称节点，删除操作只针对最后一级节点');
                    return null;
                } else {
                    // 如果没有最后一级叶子节点子节点，不返回有效信息
                    console.log('找到模型名称但无最后一级叶子节点子节点:', nodeName, '不是有效的模型结构');
                    return null;
                }
            } else {
                // 如果没有子节点，不返回有效信息
                console.log('找到模型名称但无子节点:', nodeName, '不是有效的模型结构');
                return null;
            }
        }

        console.log('未找到有效的模型信息');
        return null;
    }

    // 去掉存储路径前缀（如 models_system.projectName.）
    function stripStoragePrefix(path) {
        if (!path) return path;
        const prefixes = ['models_system.', 'algorithms_system.'];
        for (const prefix of prefixes) {
            if (path.startsWith(prefix)) {
                // 去掉前缀后，再去掉项目名部分
                const withoutPrefix = path.substring(prefix.length);
                const parts = withoutPrefix.split('.');
                if (parts.length > 1) {
                    // 返回去掉项目名后的部分（即模型/算法名称）
                    return parts.slice(1).join('.');
                }
                return withoutPrefix;
            }
        }
        return path;
    }

    // 从存储路径中提取项目名称
    function extractProjectNameFromPath(path) {
        if (!path) return null;
        const prefixes = ['models_system.', 'algorithms_system.'];
        for (const prefix of prefixes) {
            if (path.startsWith(prefix)) {
                // 去掉前缀后，第一部分就是项目名称
                const withoutPrefix = path.substring(prefix.length);
                const parts = withoutPrefix.split('.');
                if (parts.length > 0) {
                    return parts[0];
                }
            }
        }
        return null;
    }

    // 将提取项目名称的函数暴露到全局作用域
    window.extractProjectNameFromPath = extractProjectNameFromPath;

    // 5. 右侧树节点单击事件 - 显示模型详情
    document.querySelectorAll('#modelTree .tree-node').forEach(node => {
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

    // 获取当前选中的算法
    function getSelectedAlgorithm() {
        const algorithmTree = document.getElementById('algorithmTree');
        if (!algorithmTree) return null;

        const activeNode = algorithmTree.querySelector('.tree-node.active');
        if (!activeNode) return null;

        const span = activeNode.querySelector('span');
        if (!span) return null;

        const nodeName = span.textContent.trim();
        console.log('选中的算法节点名称:', nodeName);

        // 排除明显的路径节点
        if (nodeName === 'filesystem' || nodeName === 'algorithms') {
            console.log('选中的是路径节点，不是有效的算法节点');
            return null;
        }

        // 检查是否是最后一级叶子节点（没有子节点的节点）
        const childrenContainer = activeNode.querySelector('.tree-children');
        if (!childrenContainer || childrenContainer.children.length === 0) {
            // 如果是最后一级叶子节点，获取其直接父节点的算法名称
            const parentNode = activeNode.closest('.tree-children')?.parentElement;
            const parentSpan = parentNode?.querySelector('span');
            if (parentSpan) {
                let algorithmName = parentSpan.textContent.trim();
                // 去掉前缀（如 algorithms_system.projectName.）
                algorithmName = stripStoragePrefix(algorithmName);
                // 再次检查父节点也不是路径节点
                if (algorithmName !== 'filesystem' && algorithmName !== 'algorithms') {
                    console.log('找到算法名称（最后一级叶子节点的父节点）:', algorithmName, '版本号（最后一级叶子节点）:', nodeName);
                    // 从当前选中节点（版本号节点）的data-full-path属性获取完整路径
                    const fullPath = activeNode.getAttribute('data-full-path');
                    console.log('版本历史使用的完整路径:', fullPath);
                    return {
                        name: algorithmName,
                        version: nodeName,
                        fullPath: fullPath // 保存完整路径用于提取项目名称
                    };
                }
            }
        } else {
            // 如果是算法名称节点，检查是否有最后一级叶子节点子节点
            if (childrenContainer && childrenContainer.children.length > 0) {
                // 检查子节点是否包含最后一级叶子节点
                const childNodes = childrenContainer.querySelectorAll('.tree-node');
                let hasLeafChild = false;

                childNodes.forEach(childNode => {
                    const childChildrenContainer = childNode.querySelector('.tree-children');
                    if (!childChildrenContainer || childChildrenContainer.children.length === 0) {
                        hasLeafChild = true;
                    }
                });

                if (hasLeafChild) {
                    // 删除操作只针对最后一级节点，不返回算法名称节点
                    console.log('选中的是算法名称节点，删除操作只针对最后一级节点');
                    return null;
                } else {
                    // 如果没有最后一级叶子节点子节点，不返回有效信息
                    console.log('找到算法名称但无最后一级叶子节点子节点:', nodeName, '不是有效的算法结构');
                    return null;
                }
            } else {
                // 如果没有子节点，不返回有效信息
                console.log('找到算法名称但无子节点:', nodeName, '不是有效的算法结构');
                return null;
            }
        }

        console.log('未找到有效的算法信息');
        return null;
    }

    // 5.5 右侧算法树节点单击事件 - 显示算法详情
    document.querySelectorAll('#algorithmTree .tree-node').forEach(node => {
        node.addEventListener('click', function() {
            console.log('单击算法节点:', this);
            const selectedAlgorithm = getSelectedAlgorithm();
            if (selectedAlgorithm && selectedAlgorithm.version) {
                // 只有当有版本信息时才显示详情页面
                console.log('显示算法详情:', selectedAlgorithm);
                showComponent('algorithmDetail', selectedAlgorithm);
            } else {
                console.log('未获取到版本信息或点击的是父节点，不显示详情页面');
            }
        });
    });

    // 6. 功能按钮点击事件 - 使用ID绑定而非文本绑定
    const addBtns = document.querySelectorAll('.ribbon-btn');
    console.log('找到的功能按钮数量:', addBtns.length);
    
    addBtns.forEach((btn, index) => {
        const btnId = btn.id;
        console.log(`按钮 ${index}: "${btnId}"`);
        
        // 根据按钮ID获取对应的动作
        const action = getButtonAction(btnId);
        
        if (action) {
            console.log(`✅ 找到按钮 ${btnId}，绑定事件`);
            btn.addEventListener('click', function() {
                console.log(`${btnId} 按钮被点击`);
                
                // 根据动作类型执行相应操作
                switch (action) {
                    case 'showVisualAnalysis':
                        showComponent('visualAnalysis');
                        break;
                    case 'showRegisterEmbedded':
                        showComponent('registerEmbedded');
                        break;
                    case 'showModelUpload':
                        // 检查模型侧边栏是否打开，如果未打开则自动打开
                        const activeModelIconUpload = document.querySelector('.bottom-sidebar-icon.right-sidebar-icon.active[data-panel="model"]');
                        if (!activeModelIconUpload) {
                            const modelIcon = document.querySelector('.bottom-sidebar-icon.right-sidebar-icon[data-panel="model"]');
                            if (modelIcon) {
                                modelIcon.click();
                            }
                        }
                        showComponent('modelUpload');
                        break;
                    case 'showAlgorithmUpload':
                        // 检查算法侧边栏是否打开，如果未打开则自动打开
                        const activeAlgorithmIconUpload = document.querySelector('.bottom-sidebar-icon.right-sidebar-icon.active[data-panel="algorithm"]');
                        if (!activeAlgorithmIconUpload) {
                            const algorithmIcon = document.querySelector('.bottom-sidebar-icon.right-sidebar-icon[data-panel="algorithm"]');
                            if (algorithmIcon) {
                                algorithmIcon.click();
                            }
                        }
                        showComponent('algorithmUpload');
                        break;
                    case 'handleAlgorithmDownload':
                        // 检查算法侧边栏是否打开，如果未打开则自动打开
                        const activeAlgorithmIconDownload = document.querySelector('.bottom-sidebar-icon.right-sidebar-icon.active[data-panel="algorithm"]');
                        if (!activeAlgorithmIconDownload) {
                            const algorithmIcon = document.querySelector('.bottom-sidebar-icon.right-sidebar-icon[data-panel="algorithm"]');
                            if (algorithmIcon) {
                                algorithmIcon.click();
                            }
                        }
                        const selectedAlgorithmRibbon = getSelectedAlgorithm();
                        showComponent('algorithmDownload', selectedAlgorithmRibbon);
                        break;
                    case 'handleEditAlgorithm':
                        // 检查算法侧边栏是否打开
                        const activeAlgorithmIconEdit = document.querySelector('.bottom-sidebar-icon.right-sidebar-icon.active[data-panel="algorithm"]');
                        if (!activeAlgorithmIconEdit) {
                            showWorkspaceMessage('请先打开算法侧边栏', 'warning');
                            break;
                        }
                        const selectedAlgorithmEditRibbon = getSelectedAlgorithm();
                        if (selectedAlgorithmEditRibbon && selectedAlgorithmEditRibbon.version) {
                            showComponent('algorithmEdit', selectedAlgorithmEditRibbon);
                        } else {
                            showWorkspaceMessage('请先选择要编辑的算法版本', 'warning');
                        }
                        break;
                    case 'handleDeleteAlgorithm':
                        // 检查算法侧边栏是否打开
                        const activeAlgorithmIconDelete = document.querySelector('.bottom-sidebar-icon.right-sidebar-icon.active[data-panel="algorithm"]');
                        if (!activeAlgorithmIconDelete) {
                            showWorkspaceMessage('请先打开算法侧边栏', 'warning');
                            break;
                        }
                        const selectedAlgorithmDeleteRibbon = getSelectedAlgorithm();
                        if (selectedAlgorithmDeleteRibbon) {
                            showDeleteConfirmDialogAlgorithm(selectedAlgorithmDeleteRibbon);
                        } else {
                            showWorkspaceMessage('请先选择要删除的算法资产', 'warning');
                        }
                        break;
                    case 'showImportData':
                        showComponent('importData');
                        break;
                    case 'showProjectCreate':
                        showComponent('projectCreate');
                        break;
                    case 'showProjectList':
                        showComponent('projectList');
                        break;
                    case 'showProjectExport':
                        showComponent('projectExport');
                        break;
                    case 'showProjectImport':
                        showComponent('projectImport');
                        break;
                    case 'handleDownload':
                        // 检查模型侧边栏是否打开，如果未打开则自动打开
                        const activeModelIcon = document.querySelector('.bottom-sidebar-icon.right-sidebar-icon.active[data-panel="model"]');
                        if (!activeModelIcon) {
                            const modelIcon = document.querySelector('.bottom-sidebar-icon.right-sidebar-icon[data-panel="model"]');
                            if (modelIcon) {
                                modelIcon.click();
                            }
                        }
                        const selectedModel = getSelectedModel();
                        showComponent('modelDownload', selectedModel);
                        break;
                    case 'handleDeleteModel':
                        // 检查模型侧边栏是否打开
                        const activeModelIconDelete = document.querySelector('.bottom-sidebar-icon.right-sidebar-icon.active[data-panel="model"]');
                        if (!activeModelIconDelete) {
                            showWorkspaceMessage('请先打开模型侧边栏', 'warning');
                            break;
                        }
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
                        break;
                    case 'handleRemoveDataSource':
                        handleRemoveDataSource();
                        break;
                    case 'showDataSourceList':
                        showComponent('dataSourceList');
                        break;
                    case 'handleEditModel':
                        // 检查模型侧边栏是否打开
                        const activeModelIconEdit = document.querySelector('.bottom-sidebar-icon.right-sidebar-icon.active[data-panel="model"]');
                        if (!activeModelIconEdit) {
                            showWorkspaceMessage('请先打开模型侧边栏', 'warning');
                            break;
                        }
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
                        break;
                    case 'showParsingRules':
                        showComponent('parsingRules');
                        break;
                    case 'showAssociationRules':
                        showComponent('associationRules');
                        break;
                    case 'showDataArchiveList':
                        showComponent('dataArchiveList');
                        break;
                    case 'showModelArchiveList':
                        showComponent('modelArchiveList');
                        break;
                    case 'showAlgorithmArchiveList':
                        showComponent('algorithmArchiveList');
                        break;
                    case 'showProjectImport':
                        showComponent('projectImport');
                        break;
                    case 'showProjectExport':
                        showComponent('projectExport');
                        break;
                    case 'showProjectImportData':
                        window.showProjectImportWizard('data');
                        break;
                    case 'showProjectImportModel':
                        window.showProjectImportWizard('model');
                        break;
                    case 'showProjectImportAlgorithm':
                        window.showProjectImportWizard('algorithm');
                        break;
                    case 'showProjectImportSimulation':
                        window.showProjectImportWizard('simulation');
                        break;
                    case 'showProjectExportData':
                        window.showProjectExportWizard('data');
                        break;
                    case 'showProjectExportModel':
                        window.showProjectExportWizard('model');
                        break;
                    case 'showProjectExportAlgorithm':
                        window.showProjectExportWizard('algorithm');
                        break;
                    case 'showProjectExportSimulation':
                        window.showProjectExportWizard('simulation');
                        break;
                    case 'showSimulationArchive':
                        clearWorkspace();
                        showComponent('simulationArchiveList');
                        break;
                    case 'showSimulationRecord':
                        clearWorkspace();
                        showSimulationRecord();
                        return;
                    case 'showProgramUpload':
                        clearWorkspace();
                        showComponent('programUpload');
                        return;
                    case 'showProgramManagement':
                        clearWorkspace();
                        showComponent('programManagement');
                        return;
                    default:
                        console.warn(`未知的按钮动作: ${action}`);
                }
            });
        } else {
            console.warn(`未找到按钮ID ${btnId} 的对应动作`);
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
            
            // 只使用公共的toast提示，不在工作区显示HTML提示
            // 上传组件内部已经调用了showMessage，这里不需要重复显示
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
            
            // 构建查询参数
            const params = new URLSearchParams({
                name: selectedModel.name
            });
            
            // 如果有版本号，添加版本参数
            if (selectedModel.version) {
                params.append('version', selectedModel.version);
            }
            
            // 从树结构fullPath中提取projectName
            let projectName = null;
            if (selectedModel.fullPath && window.extractProjectNameFromPath) {
                projectName = window.extractProjectNameFromPath(selectedModel.fullPath);
            }
            
            // 使用新的API配置
            const result = await window.AppConfig.delete('model', 'delete', {
                name: selectedModel.name,
                version: selectedModel.version,
                projectName: projectName
            });
            
            console.log('删除响应:', result);
            
            if (result.success) {
                showWorkspaceMessage(`模型资产 "${selectedModel.name}" 删除成功`, 'success');
                
                // 从右侧树中移除该节点
                removeModelFromTree(selectedModel);
                
                // 重新加载project tree
                window.loadProjectTree();

                // 清除选中状态
                const modelTree = document.getElementById('modelTree');
                if (modelTree) {
                    const activeNodes = modelTree.querySelectorAll('.tree-node.active');
                    activeNodes.forEach(node => node.classList.remove('active'));
                }
            } else {
                showWorkspaceMessage(result.message || '删除失败', 'error');
            }
        } catch (error) {
            console.error('删除模型资产失败:', error);
            showWorkspaceMessage('删除失败，请稍后重试', 'error');
        }
    }

    // 从树中移除模型节点
    function removeModelFromTree(selectedModel) {
        const modelTree = document.getElementById('modelTree');
        if (!modelTree) return;

        const allNodes = modelTree.querySelectorAll('.tree-node');

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

    // 显示算法删除确认对话框
    function showDeleteConfirmDialogAlgorithm(selectedAlgorithm) {
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
                        ${selectedAlgorithm.version ?
                            `确定要删除算法资产 <strong>${selectedAlgorithm.name}</strong> (版本: ${selectedAlgorithm.version}) 吗？` :
                            `确定要删除算法资产 <strong>${selectedAlgorithm.name}</strong> 及其所有版本吗？`
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
            deleteAlgorithmAsset(selectedAlgorithm);
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

    // 删除算法资产
    window.deleteAlgorithmAsset = async function(selectedAlgorithm) {
        try {
            console.log('删除算法资产:', selectedAlgorithm);

            // 构建查询参数
            const params = new URLSearchParams({
                name: selectedAlgorithm.name
            });

            // 如果有版本号，添加版本参数
            if (selectedAlgorithm.version) {
                params.append('version', selectedAlgorithm.version);
            }

            // 从树结构fullPath中提取projectName
            let projectName = null;
            if (selectedAlgorithm.fullPath && window.extractProjectNameFromPath) {
                projectName = window.extractProjectNameFromPath(selectedAlgorithm.fullPath);
            }

            // 使用新的API配置
            const result = await window.AppConfig.delete('algorithm', 'delete', {
                name: selectedAlgorithm.name,
                version: selectedAlgorithm.version,
                projectName: projectName
            });

            console.log('删除响应:', result);

            if (result.success) {
                showWorkspaceMessage(`算法资产 "${selectedAlgorithm.name}" 删除成功`, 'success');

                // 从右侧树中移除该节点
                removeAlgorithmFromTree(selectedAlgorithm);
                
                // 重新加载project tree
                window.loadProjectTree();

                // 清除选中状态
                const algorithmTree = document.getElementById('algorithmTree');
                if (algorithmTree) {
                    const activeNodes = algorithmTree.querySelectorAll('.tree-node.active');
                    activeNodes.forEach(node => node.classList.remove('active'));
                }
            } else {
                showWorkspaceMessage(result.message || '删除失败', 'error');
            }
        } catch (error) {
            console.error('删除算法资产失败:', error);
            showWorkspaceMessage('删除失败，请稍后重试', 'error');
        }
    }

    // 从树中移除算法节点
    function removeAlgorithmFromTree(selectedAlgorithm) {
        const algorithmTree = document.getElementById('algorithmTree');
        if (!algorithmTree) return;

        const allNodes = algorithmTree.querySelectorAll('.tree-node');

        allNodes.forEach(node => {
            const span = node.querySelector('span');
            if (span) {
                const nodeName = span.textContent.trim();

                // 如果匹配要删除的算法名称，删除整个算法（包括所有版本）
                if (nodeName === selectedAlgorithm.name) {
                    node.remove();
                }
                // 如果只匹配版本号，只删除该版本节点
                else if (selectedAlgorithm.version && nodeName === selectedAlgorithm.version) {
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
    window.showConfirmDialog = function(title, message, onConfirm) {
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
                ">确定</button>
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
            
            // 使用新的API配置 - 后端接口是POST，需要传JSON body
            const result = await window.AppConfig.post('datasource', 'remove', dataSourceInfo);
            
            console.log('删除响应:', result);

            if (result.success) {
                showWorkspaceMessage(`数据源 "${alias}" 删除成功`, 'success');
                // 重新加载数据源树
                loadDataSourceTree();
                // 重新加载project tree
                window.loadProjectTree();
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

function showSimulationRecord() {
    console.log('showSimulationRecord() 函数被调用');

    // 检查是否已打开项目
    const username = window.localStorage.getItem('username');
    const cachedProject = username ? JSON.parse(window.localStorage.getItem('currentProject_' + username) || 'null') : null;
    if (!cachedProject) {
        if (window.CommonUtils && window.CommonUtils.showToast) {
            window.CommonUtils.showToast('请先选择或创建项目', 'error');
        }
        return;
    }

    const simulationRecord = document.createElement('simulation-record');
    
    const workspace = document.querySelector('.workspace-content');
    if (workspace) {
        workspace.appendChild(simulationRecord);
    } else {
        console.error('未找到工作区元素');
        return;
    }
    
    setTimeout(() => {
        simulationRecord.show();
    }, 100);
    
    simulationRecord.addEventListener('close', () => {
        workspace.removeChild(simulationRecord);
    });
    
    workspace.scrollIntoView({ behavior: 'smooth' });
}

// 显示数据可视化
    function showDataVisualization(dataSource) {
        console.log('显示数据可视化:', dataSource);

        // 获取或创建数据可视化组件
        let dataViz = document.getElementById('dataVisualization');
        let isFirstLoad = false;

        // 检查当前显示的组件是否是 data-visualization
        const currentActiveComponent = document.querySelector('.workspace-content > [show]:not([hidden])');
        const isCurrentDataViz = currentActiveComponent && currentActiveComponent.id === 'dataVisualization';
        console.log('当前活动组件:', currentActiveComponent?.id, '是否为data-visualization:', isCurrentDataViz);

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
                console.log('🚀 第一次加载，isFirstLoad设置为:', isFirstLoad);
            } else {
                console.error('找不到workspace-content容器');
                return;
            }
        } else {
            console.log('使用现有的数据可视化组件');
            // 只有从其他组件切换过来时才清空工作区
            if (!isCurrentDataViz) {
                clearWorkspace();
                console.log('从其他组件切换，清空工作区');
            } else {
                console.log('在data-visualization组件内切换，不清空工作区');
            }
            // 隐藏databaseTable组件
            const databaseTable = document.getElementById('databaseTable');
            if (databaseTable) {
                if (typeof databaseTable.hide === 'function') {
                    databaseTable.hide();
                } else {
                    databaseTable.removeAttribute('show');
                    databaseTable.setAttribute('hidden', '');
                }
                console.log('✅ 已隐藏databaseTable组件');
            }
            // 检查是否是清空工作区后的第一次操作（没有选中的测点）
            if (window.selectedDataPoints.size === 0) {
                console.log('🎯 检测到清空工作区后的第一次操作，设置为首次加载');
                isFirstLoad = true;
            }
            console.log('🔄 后续切换，isFirstLoad保持为:', isFirstLoad);
        }
        
        // 只有真正的测点才添加到已选测点列表
        console.log('检查节点是否为测点:', dataSource);
        const isDataPoint = isActualDataPoint(dataSource);
        console.log('是否为测点:', isDataPoint);
        
        if (isDataPoint) {
            // 直接替换为当前点击的测点，不累积
            window.selectedDataPoints.clear();
            window.selectedDataPoints.add(dataSource);
            console.log('设置当前测点:', dataSource);
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
            const keepQueryConditions = !isFirstLoad;
            console.log('调用dataViz.show()，参数详情:');
            console.log('  - isFirstLoad:', isFirstLoad);
            console.log('  - keepQueryConditions:', keepQueryConditions);
            console.log('  - dataSource:', dataSource);
            console.log('  - selectedPoints:', Array.from(window.selectedDataPoints));
            
            // 检查组件是否已完全加载
            if (typeof dataViz.show === 'function') {
                dataViz.show(dataSource, Array.from(window.selectedDataPoints), null, keepQueryConditions);
            } else {
                console.error('dataViz.show 方法不存在，组件可能未完全加载');
                // 等待更长时间后重试
                setTimeout(() => {
                    if (typeof dataViz.show === 'function') {
                        dataViz.show(dataSource, Array.from(window.selectedDataPoints), null, keepQueryConditions);
                    } else {
                        console.error('重试后仍然无法找到 dataViz.show 方法');
                    }
                }, 500);
            }
            // 不在这里调用queryAndDisplayData，让组件自己处理数据加载
        }, 200); // 增加等待时间到200ms
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
            
            // 使用新的API配置
            const result = await window.AppConfig.post('data', 'query', requestBody);
            
            if (result.success && result.data) {
                console.log('数据查询成功:', result.data);
                
                // 显示数据可视化组件，传递查询结果
                dataViz.show(currentPath, selectedPoints, result.data);
            } else if (result.success && (!result.data || !result.data.records || result.data.records.length === 0)) {
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

        // 需要检查项目的组件列表（除了数据档案查询外）
        const componentsRequiringProject = [
            'dataSourceList',
            'registerEmbedded',
            'importData',
            'modelUpload',
            'modelDownload',
            'modelEdit',
            'algorithmUpload',
            'algorithmDownload',
            'algorithmEdit',
            'parsingRules',
            'algorithmList',
            'associationRules',
            'visualAnalysis',
            'simulationArchiveList',
            'programUpload',
            'programRun'
        ];

        if (componentsRequiringProject.includes(componentId)) {
            const username = window.localStorage.getItem('username');
            const cachedProject = username ? JSON.parse(window.localStorage.getItem('currentProject_' + username) || 'null') : null;
            if (!cachedProject) {
                if (window.CommonUtils && window.CommonUtils.showToast) {
                    window.CommonUtils.showToast('请先选择或创建项目', 'error');
                }
                return;
            }
        }

        // 弹窗组件不需要清空工作区，但需要隐藏其他弹窗
        const modalComponents = ['registerEmbedded', 'importData', 'modelUpload', 'modelDownload', 'modelEdit', 'algorithmUpload', 'algorithmDownload', 'algorithmEdit', 'programUpload'];
        if (modalComponents.includes(componentId)) {
            // 隐藏其他弹窗组件
            modalComponents.forEach(modalId => {
                if (modalId !== componentId) {
                    const modal = document.getElementById(modalId);
                    if (modal && typeof modal.hide === 'function') {
                        modal.hide();
                    }
                }
            });
        } else {
            // 先清空工作区
            clearWorkspace();
        }

        // 特殊处理visualAnalysis组件（动态创建的组件）
        if (componentId === 'visualAnalysis') {
            showVisualAnalysis();
            return;
        }

        console.log(`🔍 尝试获取组件: ${componentId}`);
        const component = document.getElementById(componentId);
        console.log(`🔍 获取到的组件:`, component);
        console.log(`🔍 组件类型:`, component ? component.constructor.name : 'null');
        console.log(`🔍 组件是否有show方法:`, component ? typeof component.show : 'null');
        
        if (component && typeof component.show === 'function') {
            component.show(...args);
            console.log(`✅ 组件 ${componentId} 已显示`);
        } else {
            console.error(`❌ 未找到组件或show方法: ${componentId}`);
            console.error(`❌ 详细信息:`, {
                componentId,
                componentExists: !!component,
                componentType: component ? component.constructor.name : 'null',
                hasShowMethod: component ? typeof component.show : 'null',
                allElements: document.querySelectorAll('model-upload'),
                allCustomElements: window.customElements ? Array.from(window.customElements) : 'customElements not available'
            });
        }
    }

    // 将showComponent暴露到全局作用域
    window.showComponent = showComponent;
    window.showProjectImportWizard = function(resourceType) {
        showComponent('projectImport', { resourceType });
    };
    window.showProjectExportWizard = function(resourceType) {
        showComponent('projectExport', { resourceType });
    };

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
        console.log('🔄 loadDataSourceTree 开始执行');
        try {
            // 同时显示右侧loading
            const modelTree = document.getElementById('modelTree');
            if (modelTree) {
                modelTree.innerHTML = '<div class="loading-placeholder">正在加载模型资产...</div>';
            }
            
            const algorithmTree = document.getElementById('algorithmTree');
            if (algorithmTree) {
                algorithmTree.innerHTML = '<div class="loading-placeholder">正在加载算法资产...</div>';
            }

            const programTree = document.getElementById('programTree');
            if (programTree) {
                programTree.innerHTML = '<div class="loading-placeholder">正在加载仿真程序...</div>';
            }

            // 使用新的API配置
            const result = await window.AppConfig.get('datasource', 'tree');
            console.log('🔄 loadDataSourceTree API响应:', result);

            if (result.success && result.data) {
                renderDataSourceTree(result.data);
                // 同步filesystem数据到右侧模型资产库
                syncFilesystemToModelAssets(result.data);
                // 同步filesystem数据到右侧算法资产库
                syncFilesystemToAlgorithmAssets(result.data);
                // 同步filesystem数据到右侧仿真程序树
                syncFilesystemToProgramAssets(result.data);
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

    // 动态加载项目树（显示用户的所有项目，只展开当前项目）
    async function loadProjectTree() {
        console.log('🔄 loadProjectTree 开始执行');
        try {
            const username = window.AppConfig.getUsername();
            let cachedProject = null;
            if (username && window.localStorage) {
                cachedProject = JSON.parse(window.localStorage.getItem('currentProject_' + username) || 'null');
            }
            const currentProjectName = cachedProject ? cachedProject.name : null;

            // 获取用户的所有项目
            const queryRequest = { pageNum: 1, pageSize: 1000, name: null, algorithm: null, model: null, data: null };
            const result = await window.AppConfig.post('project', 'query', queryRequest);

            let allProjects = [];
            if (result.code === 200 && result.data) {
                allProjects = result.data.map(p => p.name);
            }

            const treeContainer = document.getElementById('projectTree');
            if (!treeContainer) return;

            if (allProjects.length === 0) {
                treeContainer.innerHTML = `
                    <div style="padding: 20px; text-align: center; color: #999;">
                        <div style="font-size: 48px; margin-bottom: 16px;">📂</div>
                        <div style="font-size: 14px; margin-bottom: 12px;">暂无项目</div>
                        <div style="font-size: 12px; color: #aaa;">请在项目管理中新建项目</div>
                    </div>
                `;
                const spacerElement = document.querySelector('.bottom-sidebar-spacer');
                if (spacerElement) { spacerElement.textContent = '当前项目：无'; }
                return;
            }

            // 获取当前项目的树结构
            let currentProjectTree = null;
            if (currentProjectName && allProjects.includes(currentProjectName)) {
                const treeResult = await window.AppConfig.get('project', 'tree', { name: currentProjectName });
                if (treeResult.code === 200 && treeResult.data) {
                    currentProjectTree = treeResult.data;
                }
            }

            // 渲染所有项目（当前项目展开，其他收起）
            treeContainer.innerHTML = renderAllProjectsTree(allProjects, currentProjectName, currentProjectTree);
            bindProjectTreeEvents();

            // 更新底部项目名称显示
            const spacerElement = document.querySelector('.bottom-sidebar-spacer');
            if (spacerElement) {
                if (currentProjectName && currentProjectTree) {
                    spacerElement.textContent = `当前项目：${currentProjectName}`;
                    spacerElement.style.cssText = `
                        text-align: center;
                        padding: 0 16px;
                        font-size: 14px;
                        font-weight: 500;
                        color: #333;
                        white-space: nowrap;
                        overflow: hidden;
                        text-overflow: ellipsis;
                    `;
                } else {
                    spacerElement.textContent = '当前项目：无';
                }
            }

            // 重新加载右侧边栏（算法库和模型资产库）
            if (typeof window.loadDataSourceTree === 'function') {
                window.loadDataSourceTree();
            }
        } catch (error) {
            console.error('加载项目树异常:', error);
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
        console.log(`🔄 renderTreeNodes 被调用，level=${level}, treeData keys:`, Object.keys(treeData));

        Object.values(treeData).forEach(node => {
            const hasChildren = Object.keys(node.children).length > 0;
            const expandedClass = level === 0 ? 'expanded' : '';
            const nodeClass = `tree-node ${expandedClass}`;

            // 根据节点类型选择图标 - 针对项目树使用不同的图标
            let iconHtml = '';
            const nodeType = node.type || '';

            if (hasChildren) {
                // 有子节点：根据类型选择图标
                if (nodeType === 'project') {
                    iconHtml = `<span class="tree-icon project-icon">📁</span>`;
                } else if (nodeType === 'folder') {
                    iconHtml = `<span class="tree-icon folder-icon">📂</span>`;
                } else {
                    iconHtml = `<span class="tree-icon folder-icon">📁</span>`;
                }
            } else {
                // 没有子节点的叶子节点：根据类型选择图标
                if (nodeType === 'algorithm') {
                    iconHtml = `<span class="tree-icon algorithm-icon">🧮</span>`;
                } else if (nodeType === 'model') {
                    iconHtml = `<span class="tree-icon model-icon">📦</span>`;
                } else if (nodeType === 'data') {
                    iconHtml = `<span class="tree-icon data-icon">📊</span>`;
                } else {
                    // 数据资源库的叶子节点：根据数据类型显示图标
                    const dataTypeIcons = {
                        0: '🔘',      // BOOLEAN(0) - 开关
                        1: '📈',      // INTEGER(1) - 曲线图
                        2: '📈',      // LONG(2) - 曲线图
                        3: '📈',      // FLOAT(3) - 曲线图
                        4: '📈',      // DOUBLE(4) - 曲线图
                        5: '📦'       // BINARY(5) - 包裹
                    };
                    const icon = dataTypeIcons[node.dataType] || '📈';
                    iconHtml = `<span class="tree-icon">${icon}</span>`;
                }
            }

            html += `
                <div class="${nodeClass}" data-full-path="${node.fullPath}" data-is-leaf="${node.isLeaf}" data-type="${node.dataType || ''}" data-node-type="${nodeType || ''}">
                    ${iconHtml}
                    <span class="tree-node-text">${node.name}</span>
            `;

            // 只有当子节点不为空时才渲染子节点容器
            if (hasChildren) {
                html += '<div class="tree-children">';
                html += renderTreeNodes(node.children, level + 1);
                html += '</div>';
            }

            html += '</div>';
        });

        return html;
    }

    // 暴露renderTreeNodes到全局作用域
    window.renderTreeNodesGlobal = renderTreeNodes;

    // 关闭项目功能
    window.closeProject = function() {
        // 清除缓存的项目（按用户隔离）
        if (window.localStorage) {
            const username = window.AppConfig.getUsername();
            if (username) {
                window.localStorage.removeItem('currentProject_' + username);
            }
        }

        // 刷新项目树（显示所有项目，不展开任何项目）
        loadProjectTree();

        // 清空工作区
        if (typeof window.hideAllComponents === 'function') {
            window.hideAllComponents();
        }

        // 清空左侧数据源树
        const dataSourceTree = document.getElementById('dataSourceTree');
        if (dataSourceTree) {
            dataSourceTree.innerHTML = `
                <div style="padding: 20px; text-align: center; color: #999;">
                    <div style="font-size: 48px; margin-bottom: 16px;">📊</div>
                    <div style="font-size: 14px; margin-bottom: 12px;">暂无数据源</div>
                    <div style="font-size: 12px; color: #aaa;">请在数据管理中注册或导入数据源</div>
                </div>
            `;
        }

        // 清空右侧模型资产库
        const modelTree = document.getElementById('modelTree');
        if (modelTree) {
            modelTree.innerHTML = `
                <div style="padding: 20px; text-align: center; color: #999;">
                    <div style="font-size: 48px; margin-bottom: 16px;">📦</div>
                    <div style="font-size: 14px; margin-bottom: 12px;">暂无模型资产</div>
                    <div style="font-size: 12px; color: #aaa;">请在模型管理中上传模型文件</div>
                </div>
            `;
        }

        // 清空右侧算法资产库
        const algorithmTree = document.getElementById('algorithmTree');
        if (algorithmTree) {
            algorithmTree.innerHTML = `
                <div style="padding: 20px; text-align: center; color: #999;">
                    <div style="font-size: 48px; margin-bottom: 16px;">🧮</div>
                    <div style="font-size: 14px; margin-bottom: 12px;">暂无算法资产</div>
                    <div style="font-size: 12px; color: #aaa;">请在算法管理中上传算法文件</div>
                </div>
            `;
        }

        // 清除选中的数据源
        selectedDataSource = null;
    };

    // 绑定关闭项目按钮事件
    const closeProjectBtn = document.getElementById('closeProjectBtn');
    if (closeProjectBtn) {
        closeProjectBtn.addEventListener('click', window.closeProject);
    }

    // 绑定项目树节点点击事件
    function bindProjectTreeEvents() {
        const projectTree = document.getElementById('projectTree');
        if (projectTree) {
            if (projectTree._projectTreeClickHandler) {
                projectTree.removeEventListener('click', projectTree._projectTreeClickHandler);
            }
            projectTree._projectTreeClickHandler = function(e) {
                const node = e.target.closest('.tree-node');
                if (node) {
                    e.stopPropagation();

                    // 获取节点信息
                    const nodeType = node.getAttribute('data-node-type');
                    const nodeName = node.querySelector('.tree-node-text')?.textContent;

                    console.log('点击项目树节点:', { nodeType, nodeName });

                    // 项目节点点击：当前项目切换展开/收起，其他项目弹出切换确认
                    if (nodeType === 'project') {
                        const projectName = node.getAttribute('data-project-name');
                        const username = window.AppConfig.getUsername();
                        let currentProjectName = null;
                        if (username && window.localStorage) {
                            const cached = JSON.parse(window.localStorage.getItem('currentProject_' + username) || 'null');
                            if (cached) currentProjectName = cached.name;
                        }
                        if (projectName === currentProjectName) {
                            // 当前项目：直接切换展开/收起
                            node.classList.toggle('expanded');
                        } else {
                            // 其他项目：弹出切换确认
                            showSwitchProjectConfirmDialog(projectName);
                        }
                        return;
                    }

                    // 检查是否有子节点，如果有则切换展开/收起状态
                    const hasChildren = node.querySelector('.tree-children');
                    if (hasChildren) {
                        node.classList.toggle('expanded');
                    }

                    // 清除所有选中状态
                    projectTree.querySelectorAll('.tree-node.active').forEach(n => n.classList.remove('active'));

                    // 设置当前选中
                    node.classList.add('active');

                    // 根据节点类型执行不同操作
                    if (nodeType === 'data') {
                        console.log('点击数据节点:', nodeName);
                        if (window.hideAllComponents) {
                            window.hideAllComponents();
                        }
                        const dataArchiveDetail = document.getElementById('dataArchiveDetail');
                        if (dataArchiveDetail) {
                            dataArchiveDetail.showDetail(nodeName);
                        }
                    } else if (nodeType === 'algorithm') {
                        console.log('点击算法节点:', nodeName);
                        if (window.hideAllComponents) {
                            window.hideAllComponents();
                        }
                        const algorithmDetail = document.getElementById('algorithmDetail');
                        if (algorithmDetail && algorithmDetail.show) {
                            const pathParts = nodeName.split('.');
                            if (pathParts.length >= 4) {
                                algorithmDetail.show({
                                    name: pathParts[2],
                                    version: pathParts[3],
                                    fullPath: nodeName
                                });
                            } else {
                                algorithmDetail.show({ name: nodeName, fullPath: nodeName });
                            }
                        }
                        expandAlgorithmNodeInRightSidebar(nodeName, true);
                    } else if (nodeType === 'model') {
                        console.log('点击模型节点:', nodeName);
                        if (window.hideAllComponents) {
                            window.hideAllComponents();
                        }
                        const modelDetail = document.getElementById('modelDetail');
                        if (modelDetail && modelDetail.show) {
                            const pathParts = nodeName.split('.');
                            if (pathParts.length >= 4) {
                                modelDetail.show({
                                    name: pathParts[2],
                                    version: pathParts[3],
                                    fullPath: nodeName
                                });
                            } else {
                                modelDetail.show({ name: nodeName, fullPath: nodeName });
                            }
                        }
                        expandModelNodeInRightSidebar(nodeName, true);
                    }
                }
            };
            projectTree.addEventListener('click', projectTree._projectTreeClickHandler);
        }
    }

    // 在项目树渲染后绑定事件
    const originalRenderTreeNodes = window.renderTreeNodesGlobal;
    window.renderTreeNodesGlobal = function(treeData, level) {
        const html = originalRenderTreeNodes(treeData, level);
        setTimeout(bindProjectTreeEvents, 100);
        return html;
    };
    
    // 渲染数据源树
    function renderDataSourceTree(dataSources) {
        console.log('🔄 renderDataSourceTree 被调用，数据源数量:', dataSources?.length);
        const treeContainer = document.getElementById('dataSourceTree');
        if (!treeContainer) {
            console.error('❌ dataSourceTree 容器不存在');
            return;
        }
        if (!dataSources || dataSources.length === 0) {
            treeContainer.innerHTML = '<div class="empty-placeholder">暂无数据资源</div>';
            return;
        }
        
        // 过滤掉 models_system 和 algorithms_system 开头的数据源（这些数据源会移动到右侧显示）
        const filteredDataSources = dataSources.filter(item => {
            const path = typeof item === 'string' ? item : item.path;
            return !path || (!path.startsWith('models_system') && !path.startsWith('algorithms_system') && !path.startsWith('programs_system'));
        });
        console.log('🔄 过滤后的数据源数量:', filteredDataSources.length);
        
        // 将过滤后的字符串数组转换为树结构
        const treeData = buildTreeFromStringArray(filteredDataSources);
        console.log('🔄 树结构数据:', treeData);
        
        // 渲染树HTML
        const treeHTML = renderTreeNodes(treeData);
        console.log('🔄 渲染的HTML长度:', treeHTML.length);
        
        treeContainer.innerHTML = treeHTML;
        console.log('🔄 容器innerHTML已设置');
        
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
        console.log('🔄 bindTreeEvents 被调用');
        const dataSourceTree = document.getElementById('dataSourceTree');
        console.log('🔄 dataSourceTree:', dataSourceTree);
        if (dataSourceTree) {
            console.log('🔄 dataSourceTree.innerHTML:', dataSourceTree.innerHTML.substring(0, 200));
            const treeNodes = dataSourceTree.querySelectorAll('.tree-node');
            console.log('🔄 找到的树节点数量:', treeNodes.length);
            treeNodes.forEach(node => {
                node.addEventListener('click', function(e) {
                    e.stopPropagation();

                    // 隐藏右键菜单
                    const contextMenu = document.getElementById('dataSourceContextMenu');
                    if (contextMenu) {
                        contextMenu.style.display = 'none';
                    }

                    // 确保只处理左侧的节点
                    if (!this.closest('.left-sidebar')) {
                        return;
                    }
                    
                    // 先清除所有选中状态（仅限左侧）
                    dataSourceTree.querySelectorAll('.tree-node.active').forEach(n => n.classList.remove('active'));
                    
                    // 设置当前选中
                    this.classList.add('active');
                    
                    // 获取节点的完整路径
                    const fullPath = this.getAttribute('data-full-path');
                    const isLeaf = this.getAttribute('data-is-leaf') === 'true';
                    if (fullPath && isLeaf) {
                        console.log('点击了叶子节点:', fullPath);
                        selectedDataSource = fullPath;
                        
                        // 根据视图模式决定使用哪个组件
                        if (currentViewMode === 'table') {
                            // 获取父节点路径作为tableName
                            const pathParts = fullPath.split('.');
                            const parentPath = pathParts.slice(0, -1).join('.');
                            showDatabaseTable(parentPath);
                        } else {
                            // 使用 data-visualization 页面
                            showDataVisualization(fullPath);
                        }
                        
                                                                        
                                                
                        // 如果是最后一级节点且不是文件夹/数据库图标类数据源，则显示“选择数据源”按钮
                                                
                        
                                            }
                    
                    // 展开收起（如果有子节点）
                    if (this.querySelector('.tree-children')) {
                        this.classList.toggle('expanded');
                    }
                });

                // 添加右键菜单事件
                node.addEventListener('contextmenu', function(e) {
                    e.preventDefault();
                    e.stopPropagation();

                    // 确保只处理左侧的节点
                    if (!this.closest('.left-sidebar')) {
                        return;
                    }

                    // 先隐藏现有的右键菜单
                    const existingMenu = document.getElementById('dataSourceContextMenu');
                    if (existingMenu) {
                        existingMenu.style.display = 'none';
                    }

                    const fullPath = this.getAttribute('data-full-path');
                    const isLeaf = this.getAttribute('data-is-leaf') === 'true';

                    // 禁止删除根节点（第一级节点）
                    const pathParts = fullPath.split('.');
                    if (pathParts.length === 1) {
                        return; // 根节点不显示右键菜单
                    }

                    // 显示右键菜单
                    const contextMenu = document.getElementById('dataSourceContextMenu');
                    if (contextMenu) {
                        contextMenu.style.display = 'block';
                        // 使用鼠标位置，添加偏移量避免菜单被鼠标遮挡
                        contextMenu.style.left = (e.clientX + 5) + 'px';
                        contextMenu.style.top = (e.clientY + 5) + 'px';

                        // 保存当前节点信息到菜单元素
                        contextMenu.dataset.fullPath = fullPath;
                        contextMenu.dataset.isLeaf = isLeaf;
                    }
                });
            });
        }

        // 点击其他地方隐藏右键菜单
        document.addEventListener('click', function(e) {
            const contextMenu = document.getElementById('dataSourceContextMenu');
            if (contextMenu && contextMenu.style.display === 'block') {
                // 如果点击的不是右键菜单本身，则隐藏
                if (!contextMenu.contains(e.target)) {
                    contextMenu.style.display = 'none';
                }
            }
        });

        // 绑定删除菜单项点击事件
        const deleteMenuItem = document.getElementById('deleteDataNode');
        if (deleteMenuItem) {
            deleteMenuItem.addEventListener('click', function() {
                const contextMenu = document.getElementById('dataSourceContextMenu');
                if (!contextMenu) return;

                const fullPath = contextMenu.dataset.fullPath;
                const isLeaf = contextMenu.dataset.isLeaf === 'true';

                if (!fullPath) return;

                // 构造删除路径
                let deletePath;
                if (isLeaf) {
                    // 叶子节点：全路径
                    deletePath = fullPath;
                } else {
                    // 非叶子节点：通配符
                    deletePath = fullPath + '.*';
                }

                // 隐藏菜单
                contextMenu.style.display = 'none';

                // 显示确认对话框
                window.showConfirmDialog('确认删除', `确定要删除 ${deletePath} 吗？`, () => {
                    deleteDataSourceData(deletePath);
                });
            });
        }
    }

    // 删除数据源数据
    async function deleteDataSourceData(path) {
        try {
            if (window.showGlobalLoading) window.showGlobalLoading('正在删除数据...');

            const url = `${window.AppConfig.api.baseURL}/api/data/deleteColumns/${encodeURIComponent(path)}`;
            const response = await fetch(url, {
                method: 'DELETE',
                headers: window.AppConfig.getAuthHeaders()
            });

            const result = await response.json();

            if (result.success || result.code === 200) {
                if (window.CommonUtils && window.CommonUtils.showToast) {
                    window.CommonUtils.showToast('删除成功', 'success');
                }
                // 重新加载数据源树
                if (window.loadDataSourceTree) {
                    window.loadDataSourceTree();
                }
                // 重新加载project tree
                if (window.loadProjectTree) {
                    window.loadProjectTree();
                }
            } else {
                if (window.CommonUtils && window.CommonUtils.showToast) {
                    window.CommonUtils.showToast('删除失败: ' + (result.message || '未知错误'), 'error');
                }
            }
        } catch (error) {
            console.error('删除数据失败:', error);
            if (window.CommonUtils && window.CommonUtils.showToast) {
                window.CommonUtils.showToast('删除失败: ' + error.message, 'error');
            }
        } finally {
            if (window.hideGlobalLoading) window.hideGlobalLoading();
        }
    }

    // 同步filesystem数据到右侧模型资产库
    function syncFilesystemToModelAssets(allData) {
        try {
            // 过滤出以"models_system"开头的路径数据
            const filesystemData = allData.filter(item => {
                const path = typeof item === 'string' ? item : item.path;
                return path && path.startsWith('models_system');
            });
            
            console.log('过滤出的models_system数据:', filesystemData);
            
            if (filesystemData.length > 0) {
                // 获取模型树容器
                const modelTree = document.getElementById('modelTree');
                if (!modelTree) return;
                
                // 构建树结构
                const treeMap = {};
                filesystemData.forEach(item => {
                    const path = typeof item === 'string' ? item : item.path;
                    const parts = path.split('.');
                    
                    let current = treeMap;
                    for (let i = 0; i < parts.length; i++) {
                        const part = parts[i];
                        if (!current[part]) {
                            current[part] = {
                                name: part,
                                children: {},
                                fullPath: parts.slice(0, i + 1).join('.'),
                                isLeaf: i === parts.length - 1,
                                level: i
                            };
                        }
                        current = current[part].children;
                    }
                });
                
                // 递归创建DOM树节点
                function createTreeNodes(nodes, container, level = 0) {
                    Object.values(nodes).forEach(node => {
                        const hasChildren = Object.keys(node.children).length > 0;
                        
                        // 创建树节点
                        const treeNode = document.createElement('div');
                        treeNode.className = hasChildren ? 'tree-node expanded' : 'tree-node';
                        treeNode.setAttribute('data-full-path', node.fullPath);
                        treeNode.setAttribute('data-is-leaf', node.isLeaf.toString());
                        
                        // 只有父节点（有子节点的）才有图标，子节点（版本号）没有图标
                        if (hasChildren) {
                            const icon = document.createElement('i');
                            icon.className = 'icon cube-icon';
                            treeNode.appendChild(icon);
                        }

                        // 添加节点名称
                        const span = document.createElement('span');
                        span.className = 'tree-node-text';
                        span.textContent = node.name;
                        treeNode.appendChild(span);

                        // 如果有子节点，创建子容器并递归
                        if (hasChildren) {
                            const childrenContainer = document.createElement('div');
                            childrenContainer.className = 'tree-children';
                            createTreeNodes(node.children, childrenContainer, level + 1);
                            treeNode.appendChild(childrenContainer);
                        }
                        
                        // 添加到容器
                        container.appendChild(treeNode);
                    });
                }
                
                // 清空容器并创建新树
                modelTree.innerHTML = '';
                createTreeNodes(treeMap, modelTree);

                // 重新绑定右侧树节点事件（保持原有逻辑）
                const rightTreeNodes = modelTree.querySelectorAll('.tree-node');
                rightTreeNodes.forEach(node => {
                    node.addEventListener('click', function(e) {
                        e.stopPropagation();

                        // 确保只处理右侧的节点
                        if (!this.closest('.right-sidebar')) {
                            return;
                        }

                        // 先清除所有选中状态（仅限右侧）
                        modelTree.querySelectorAll('.tree-node.active').forEach(n => n.classList.remove('active'));

                        // 设置当前选中
                        this.classList.add('active');

                        // 展开收起（如果有子节点）
                        if (this.querySelector('.tree-children')) {
                            this.classList.toggle('expanded');
                        }

                        // 调用原有的模型详情显示逻辑
                        const selectedModel = getSelectedModel();
                        if (selectedModel && selectedModel.version) {
                            console.log('显示模型详情:', selectedModel);
                            showComponent('modelDetail', selectedModel);
                        } else {
                            console.log('未获取到版本信息或点击的是父节点，不显示详情页面');
                        }
                    });
                });
                
            } else {
                // 如果没有filesystem数据，显示空状态
                const modelTree = document.getElementById('modelTree');
                if (modelTree) {
                    modelTree.innerHTML = '<div class="empty-placeholder">暂无模型资产</div>';
                }
            }
            
        } catch (error) {
            console.error('同步filesystem数据到模型资产库失败:', error);
            const modelTree = document.getElementById('modelTree');
            if (modelTree) {
                modelTree.innerHTML = '<div class="error-placeholder">同步模型资产失败</div>';
            }
        }
    }

    // 同步filesystem数据到算法资产库
    function syncFilesystemToAlgorithmAssets(allData) {
        try {
            // 过滤出以"algorithms_system"开头的路径数据
            const filesystemData = allData.filter(item => {
                const path = typeof item === 'string' ? item : item.path;
                return path && path.startsWith('algorithms_system');
            });

            console.log('过滤出的algorithms_system数据:', filesystemData);

            if (filesystemData.length > 0) {
                // 获取算法树容器
                const algorithmTree = document.getElementById('algorithmTree');
                if (!algorithmTree) return;

                // 构建树结构
                const treeMap = {};
                filesystemData.forEach(item => {
                    const path = typeof item === 'string' ? item : item.path;
                    const parts = path.split('.');

                    let current = treeMap;
                    for (let i = 0; i < parts.length; i++) {
                        const part = parts[i];
                        if (!current[part]) {
                            current[part] = {
                                name: part,
                                children: {},
                                fullPath: parts.slice(0, i + 1).join('.'),
                                isLeaf: i === parts.length - 1,
                                level: i
                            };
                        }
                        current = current[part].children;
                    }
                });

                // 递归创建DOM树节点
                function createTreeNodes(nodes, container, level = 0) {
                    Object.values(nodes).forEach(node => {
                        const hasChildren = Object.keys(node.children).length > 0;

                        // 创建树节点
                        const treeNode = document.createElement('div');
                        treeNode.className = hasChildren ? 'tree-node expanded' : 'tree-node';
                        treeNode.setAttribute('data-full-path', node.fullPath);
                        treeNode.setAttribute('data-is-leaf', node.isLeaf.toString());

                        // 只有父节点（有子节点的）才有图标，子节点（版本号）没有图标
                        if (hasChildren) {
                            const icon = document.createElement('i');
                            icon.className = 'icon algorithm-icon';
                            treeNode.appendChild(icon);
                        }

                        // 添加节点名称
                        const span = document.createElement('span');
                        span.className = 'tree-node-text';
                        span.textContent = node.name;
                        treeNode.appendChild(span);

                        // 如果有子节点，创建子容器并递归
                        if (hasChildren) {
                            const childrenContainer = document.createElement('div');
                            childrenContainer.className = 'tree-children';
                            createTreeNodes(node.children, childrenContainer, level + 1);
                            treeNode.appendChild(childrenContainer);
                        }

                        // 添加到容器
                        container.appendChild(treeNode);
                    });
                }

                // 清空容器并创建新树
                algorithmTree.innerHTML = '';
                createTreeNodes(treeMap, algorithmTree);

                // 重新绑定右侧算法树节点事件
                const rightTreeNodes = algorithmTree.querySelectorAll('.tree-node');
                rightTreeNodes.forEach(node => {
                    node.addEventListener('click', function(e) {
                        e.stopPropagation();

                        // 确保只处理右侧的节点
                        if (!this.closest('.right-sidebar')) {
                            return;
                        }

                        // 先清除所有选中状态（仅限右侧）
                        algorithmTree.querySelectorAll('.tree-node.active').forEach(n => n.classList.remove('active'));

                        // 设置当前选中
                        this.classList.add('active');

                        // 展开收起（如果有子节点）
                        if (this.querySelector('.tree-children')) {
                            this.classList.toggle('expanded');
                        }

                        // 调用算法详情显示逻辑
                        const selectedAlgorithm = getSelectedAlgorithm();
                        if (selectedAlgorithm && selectedAlgorithm.version) {
                            console.log('显示算法详情:', selectedAlgorithm);
                            showComponent('algorithmDetail', selectedAlgorithm);
                        } else {
                            console.log('未获取到版本信息或点击的是父节点，不显示详情页面');
                        }
                    });
                });

            } else {
                // 如果没有filesystem数据，显示空状态
                const algorithmTree = document.getElementById('algorithmTree');
                if (algorithmTree) {
                    algorithmTree.innerHTML = '<div class="empty-placeholder">暂无算法资产</div>';
                }
            }

        } catch (error) {
            console.error('同步filesystem数据到算法资产库失败:', error);
            const algorithmTree = document.getElementById('algorithmTree');
            if (algorithmTree) {
                algorithmTree.innerHTML = '<div class="error-placeholder">加载算法资产失败</div>';
            }
        }
    }

    // 同步filesystem数据到仿真程序树
    function syncFilesystemToProgramAssets(allData) {
        try {
            const filesystemData = allData.filter(item => {
                const path = typeof item === 'string' ? item : item.path;
                return path && path.startsWith('programs_system');
            });

            console.log('过滤出的programs_system数据:', filesystemData);

            const programTree = document.getElementById('programTree');
            if (!programTree) return;

            if (filesystemData.length > 0) {
                const treeMap = {};
                filesystemData.forEach(item => {
                    const path = typeof item === 'string' ? item : item.path;
                    const parts = path.split('.');

                    let current = treeMap;
                    for (let i = 0; i < parts.length; i++) {
                        const part = parts[i];
                        if (!current[part]) {
                            current[part] = {
                                name: part,
                                children: {},
                                fullPath: parts.slice(0, i + 1).join('.'),
                                isLeaf: i === parts.length - 1,
                                level: i
                            };
                        }
                        current = current[part].children;
                    }
                });

                function createTreeNodes(nodes, container, level = 0) {
                    Object.values(nodes).forEach(node => {
                        const hasChildren = Object.keys(node.children).length > 0;

                        const treeNode = document.createElement('div');
                        treeNode.className = hasChildren ? 'tree-node expanded' : 'tree-node';
                        treeNode.setAttribute('data-full-path', node.fullPath);
                        treeNode.setAttribute('data-is-leaf', node.isLeaf.toString());

                        if (hasChildren) {
                            const icon = document.createElement('i');
                            icon.className = 'icon folder-icon';
                            treeNode.appendChild(icon);
                        }

                        const span = document.createElement('span');
                        span.className = 'tree-node-text';
                        span.textContent = node.name;
                        treeNode.appendChild(span);

                        if (hasChildren) {
                            const childrenContainer = document.createElement('div');
                            childrenContainer.className = 'tree-children';
                            createTreeNodes(node.children, childrenContainer, level + 1);
                            treeNode.appendChild(childrenContainer);
                        }

                        container.appendChild(treeNode);
                    });
                }

                programTree.innerHTML = '';
                createTreeNodes(treeMap, programTree);

                const rightTreeNodes = programTree.querySelectorAll('.tree-node');
                rightTreeNodes.forEach(node => {
                    node.addEventListener('click', function(e) {
                        e.stopPropagation();

                        if (!this.closest('.right-sidebar')) {
                            return;
                        }

                        programTree.querySelectorAll('.tree-node.active').forEach(n => n.classList.remove('active'));
                        this.classList.add('active');

                        if (this.querySelector('.tree-children')) {
                            this.classList.toggle('expanded');
                        }

                        const fullPath = this.getAttribute('data-full-path');
                        const isLeaf = this.getAttribute('data-is-leaf') === 'true';
                        console.log('点击仿真程序节点:', fullPath, isLeaf);

                        if (isLeaf && fullPath) {
                            const parts = fullPath.split('.');
                            if (parts.length >= 4 && parts[0] === 'programs_system') {
                                const programName = parts[parts.length - 2];
                                const programVersion = parts[parts.length - 1].replace(/_/g, '.');
                                const programRun = document.getElementById('programRun');
                                if (programRun) {
                                    programRun.setAttribute('data-name', programName);
                                    programRun.setAttribute('data-version', programVersion);
                                }
                                clearWorkspace();
                                showComponent('programRun');
                            }
                        }
                    });
                });

            } else {
                programTree.innerHTML = '<div class="empty-placeholder">暂无仿真程序</div>';
            }

        } catch (error) {
            console.error('同步filesystem数据到仿真程序树失败:', error);
            const programTree = document.getElementById('programTree');
            if (programTree) {
                programTree.innerHTML = '<div class="error-placeholder">加载仿真程序失败</div>';
            }
        }
    }

    // 将loadDataSourceTree函数暴露到全局作用域，供其他组件调用
    window.loadDataSourceTree = loadDataSourceTree;
    // 将loadProjectTree函数暴露到全局作用域，供其他组件调用
    window.loadProjectTree = loadProjectTree;
});

// 确保函数在全局作用域可用
window.loadDataSourceTree = async function() {
    console.log('🔄 loadDataSourceTree 被调用，开始重新加载数据源树...');
    try {
        // 显示全局loading
        window.showGlobalLoading('正在加载数据资源...');
        
        // 同时显示右侧loading
        const modelTree = document.getElementById('modelTree');
        if (modelTree) {
            modelTree.innerHTML = '<div class="loading-placeholder">正在加载模型资产...</div>';
        }
        
        const algorithmTree = document.getElementById('algorithmTree');
        if (algorithmTree) {
            algorithmTree.innerHTML = '<div class="loading-placeholder">正在加载算法资产...</div>';
        }

        const programTree = document.getElementById('programTree');
        if (programTree) {
            programTree.innerHTML = '<div class="loading-placeholder">正在加载仿真程序...</div>';
        }

        console.log('🔄 调用接口:', window.AppConfig.getApiUrl('datasource', 'tree'));
        const result = await window.AppConfig.get('datasource', 'tree');
        
        console.log('🔄 接口响应:', result);
        
        if (result.success && result.data) {
            renderDataSourceTree(result.data);
            // 同步filesystem数据到右侧模型资产库
            syncFilesystemToModelAssets(result.data);
            // 同步filesystem数据到右侧算法资产库
            syncFilesystemToAlgorithmAssets(result.data);
            // 同步filesystem数据到右侧仿真程序树
            syncFilesystemToProgramAssets(result.data);
            console.log('🔄 数据源树重新加载完成');
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
};

// 全局函数：在右侧模型侧边栏展开对应节点
window.expandModelNodeInRightSidebar = function(storagePath, syncOnly = false) {
    console.log('尝试在右侧模型侧边栏展开节点:', storagePath, syncOnly ? '(仅同步选中)' : '');
    
    // 切换到右侧模型侧边栏
    const activeModelIcon = document.querySelector('.bottom-sidebar-icon.right-sidebar-icon.active[data-panel="model"]');
    const rightSidebar = document.querySelector('.right-sidebar');
    const isModelSidebarActive = !!activeModelIcon;
    const isSidebarExpanded = rightSidebar && !rightSidebar.classList.contains('collapsed');
    
    if (!isModelSidebarActive || !isSidebarExpanded) {
        const modelIcon = document.querySelector('.bottom-sidebar-icon.right-sidebar-icon[data-panel="model"]');
        if (modelIcon) {
            console.log('当前不是模型侧边栏或侧边栏未展开，点击切换');
            modelIcon.click();
        }
    }
    
    // 等待树加载完成后展开对应节点
    setTimeout(() => {
        const modelTree = document.getElementById('modelTree');
        if (!modelTree) return;
        
        const treeNodes = modelTree.querySelectorAll('.tree-node');
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
                if (syncOnly) {
                    // 仅同步选中状态，避免重复触发详情加载
                    modelTree.querySelectorAll('.tree-node.active').forEach(n => n.classList.remove('active'));
                    node.classList.add('active');
                } else {
                    node.click();
                }
                node.scrollIntoView({ behavior: 'smooth', block: 'center' });
            }
        });
        
        if (!found) {
            console.log('未找到匹配的模型树节点:', storagePath);
        }
    }, 500);
};

// 全局函数：在右侧算法侧边栏展开对应节点
window.expandAlgorithmNodeInRightSidebar = function(storagePath, syncOnly = false) {
    console.log('尝试在右侧算法侧边栏展开节点:', storagePath, syncOnly ? '(仅同步选中)' : '');

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
                if (syncOnly) {
                    // 仅同步选中状态，避免重复触发详情加载
                    algorithmTree.querySelectorAll('.tree-node.active').forEach(n => n.classList.remove('active'));
                    node.classList.add('active');
                } else {
                    node.click();
                }
                node.scrollIntoView({ behavior: 'smooth', block: 'center' });
            }
        });

        if (!found) {
            console.log('未找到匹配的算法树节点:', storagePath);
        }
    }, 500);
};

// 全局函数：显示修改密码弹窗
window.showChangePasswordModal = function() {
    const changePasswordComponent = document.querySelector('change-password');
    if (changePasswordComponent) {
        changePasswordComponent.show(); // 使用 show() 而不是 showModal()
    }
};

// 用户头像点击事件（修改密码）- 已移至 change-password 组件内部处理

// 全局函数：关闭关于对话框
window.closeAbout = function() {
    const modal = document.querySelector('.modal-overlay');
    if (modal) {
        modal.remove();
    }
};

// 全局函数：显示关于对话框
window.showAbout = function() {
    // 创建模态框
    const modalOverlay = document.createElement('div');
    modalOverlay.className = 'modal-overlay';
    modalOverlay.style.cssText = `
        position: fixed;
        top: 0;
        left: 0;
        width: 100%;
        height: 100%;
        background: rgba(0, 0, 0, 0.5);
        display: flex;
        align-items: center;
        justify-content: center;
        z-index: 10000;
    `;
    
    // 创建模态框内容容器
    const modalContainer = document.createElement('div');
    modalContainer.style.cssText = `
        width: 500px;
        max-width: 90vw;
        height: 600px;
        max-height: 90vh;
        background: white;
        border-radius: 12px;
        box-shadow: 0 8px 32px rgba(0, 0, 0, 0.2);
        overflow: hidden;
        position: relative;
    `;
    
    // 加载关于页面内容
    fetch('./components/about/about.html')
        .then(response => response.text())
        .then(html => {
            modalContainer.innerHTML = html;

            // 适配暗黑模式
            if (document.documentElement.classList.contains('dark-mode')) {
                modalContainer.querySelector('.about-container').classList.add('dark-mode');
            }
        })
        .catch(error => {
            console.error('加载关于页面失败:', error);
            modalContainer.innerHTML = `
                <div style="padding: 40px; text-align: center; height: 100%; display: flex; flex-direction: column; justify-content: center;">
                    <h3>加载失败</h3>
                    <p>无法加载关于页面</p>
                    <button onclick="this.closest('.modal-overlay').remove()" style="
                        padding: 8px 16px;
                        background: #1890ff;
                        color: white;
                        border: none;
                        border-radius: 4px;
                        cursor: pointer;
                        margin-top: 20px;
                    ">关闭</button>
                </div>
            `;
        });

    // 点击遮罩关闭
    modalOverlay.addEventListener('click', function(e) {
        if (e.target === modalOverlay) {
            modalOverlay.remove();
        }
    });

    // 添加到页面
    modalOverlay.appendChild(modalContainer);
    document.body.appendChild(modalOverlay);

    // ESC键关闭
    const escHandler = function(e) {
        if (e.key === 'Escape') {
            modalOverlay.remove();
            document.removeEventListener('keydown', escHandler);
        }
    };
    document.addEventListener('keydown', escHandler);
};

// 显示项目树形结构（更新当前项目并刷新左侧项目列表）
window.displayProjectTree = function(projectName) {
    console.log('🔄 displayProjectTree 被调用，项目名称:', projectName);

    if (!projectName || !projectName.trim()) {
        // 清除当前项目缓存，刷新列表
        if (window.localStorage) {
            const username = window.AppConfig.getUsername();
            if (username) {
                window.localStorage.removeItem('currentProject_' + username);
            }
        }
        return Promise.resolve(window.loadProjectTree && window.loadProjectTree());
    }

    // 更新当前项目缓存
    if (window.localStorage) {
        const username = window.AppConfig.getUsername();
        if (username) {
            window.localStorage.setItem('currentProject_' + username, JSON.stringify({
                name: projectName,
                createTime: Date.now()
            }));
        }
    }

    if (window.showGlobalLoading) {
        window.showGlobalLoading('正在加载项目树...');
    }

    return Promise.resolve(window.loadProjectTree && window.loadProjectTree())
        .finally(() => {
            if (window.hideGlobalLoading) {
                window.hideGlobalLoading();
            }
        });
};

// 绑定项目树节点点击事件
function bindProjectTreeEvents() {
    const projectTree = document.getElementById('projectTree');
    if (!projectTree) return;

    if (projectTree._projectTreeClickHandler) {
        projectTree.removeEventListener('click', projectTree._projectTreeClickHandler);
    }

    projectTree._projectTreeClickHandler = function(e) {
            const node = e.target.closest('.tree-node');
            if (node) {
                e.stopPropagation();

                // 获取节点信息
                const nodeType = node.getAttribute('data-node-type');
                const nodeName = node.querySelector('.tree-node-text')?.textContent;

                console.log('点击项目树节点:', { nodeType, nodeName });

                // 项目节点点击：当前项目切换展开/收起，其他项目弹出切换确认
                if (nodeType === 'project') {
                    const projectName = node.getAttribute('data-project-name');
                    const username = window.AppConfig.getUsername();
                    let currentProjectName = null;
                    if (username && window.localStorage) {
                        const cached = JSON.parse(window.localStorage.getItem('currentProject_' + username) || 'null');
                        if (cached) currentProjectName = cached.name;
                    }
                    if (projectName === currentProjectName) {
                        // 当前项目：直接切换展开/收起
                        node.classList.toggle('expanded');
                    } else {
                        showSwitchProjectConfirmDialog(projectName);
                    }
                    return;
                }

                // 检查是否有子节点，如果有则切换展开/收起状态
                const hasChildren = node.querySelector('.tree-children');
                if (hasChildren) {
                    node.classList.toggle('expanded');
                }

                // 清除所有选中状态
                projectTree.querySelectorAll('.tree-node.active').forEach(n => n.classList.remove('active'));

                // 设置当前选中
                node.classList.add('active');

                // 根据节点类型执行不同操作
                if (nodeType === 'data') {
                    console.log('点击数据节点:', nodeName);
                    if (window.hideAllComponents) {
                        window.hideAllComponents();
                    }
                    const dataArchiveDetail = document.getElementById('dataArchiveDetail');
                    if (dataArchiveDetail) {
                        dataArchiveDetail.showDetail(nodeName);
                    }
                } else if (nodeType === 'algorithm') {
                    console.log('点击算法节点:', nodeName);
                    if (window.hideAllComponents) {
                        window.hideAllComponents();
                    }
                    const algorithmDetail = document.getElementById('algorithmDetail');
                    if (algorithmDetail && algorithmDetail.show) {
                        const pathParts = nodeName.split('.');
                        if (pathParts.length >= 4) {
                            algorithmDetail.show({
                                name: pathParts[2],
                                version: pathParts[3],
                                fullPath: nodeName
                            });
                        } else {
                            algorithmDetail.show({ name: nodeName, fullPath: nodeName });
                        }
                    }
                    expandAlgorithmNodeInRightSidebar(nodeName, true);
                } else if (nodeType === 'model') {
                    console.log('点击模型节点:', nodeName);
                    if (window.hideAllComponents) {
                        window.hideAllComponents();
                    }
                    const modelDetail = document.getElementById('modelDetail');
                    if (modelDetail && modelDetail.show) {
                        const pathParts = nodeName.split('.');
                        if (pathParts.length >= 4) {
                            modelDetail.show({
                                name: pathParts[2],
                                version: pathParts[3],
                                fullPath: nodeName
                            });
                        } else {
                            modelDetail.show({ name: nodeName, fullPath: nodeName });
                        }
                    }
                    // 同步右侧模型侧边栏选中状态（不再模拟点击，避免重复加载）
                    expandModelNodeInRightSidebar(nodeName, true);
                }
            }
    };

    projectTree.addEventListener('click', projectTree._projectTreeClickHandler);
}

// 切换项目确认对话框
function showSwitchProjectConfirmDialog(projectName) {
    const modal = document.createElement('div');
    modal.style.cssText = `
        position: fixed; top: 0; left: 0; width: 100%; height: 100%;
        background: rgba(0,0,0,0.4); display: flex; align-items: center;
        justify-content: center; z-index: 10001;
    `;
    modal.innerHTML = `
        <div style="background: white; border-radius: 8px; padding: 24px; min-width: 360px; box-shadow: 0 4px 20px rgba(0,0,0,0.15);">
            <div style="font-size: 16px; font-weight: 600; margin-bottom: 16px;">打开项目</div>
            <div style="font-size: 14px; color: #666; margin-bottom: 24px;">确定要切换到项目「${projectName}」吗？</div>
            <div style="display: flex; justify-content: flex-end; gap: 12px;">
                <button type="button" style="padding: 8px 20px; border: 1px solid #ddd; border-radius: 4px; background: white; cursor: pointer; font-size: 14px;" id="switchProjectCancel">取消</button>
                <button type="button" style="padding: 8px 20px; border: none; border-radius: 4px; background: #0078d4; color: white; cursor: pointer; font-size: 14px;" id="switchProjectConfirm">确定</button>
            </div>
        </div>
    `;
    document.body.appendChild(modal);

    modal.querySelector('#switchProjectCancel').addEventListener('click', () => modal.remove());
    modal.querySelector('#switchProjectConfirm').addEventListener('click', () => {
        modal.remove();
        if (typeof window.hideAllComponents === 'function') {
            window.hideAllComponents();
        }
        window.displayProjectTree(projectName);
    });
    modal.addEventListener('click', (e) => {
        if (e.target === modal) modal.remove();
    });
}

// 渲染所有项目树（当前项目展开，其他收起）
function renderAllProjectsTree(allProjects, currentProjectName, currentProjectTree) {
    let html = '';

    allProjects.forEach(projectName => {
        const isCurrent = projectName === currentProjectName;
        const expandedClass = isCurrent ? 'expanded' : '';

        html += `
            <div class="tree-node ${expandedClass}" data-node-type="project" data-project-name="${projectName}" data-full-path="0">
                <span class="tree-icon project-icon">📁</span>
                <span class="tree-node-text">${projectName}</span>
        `;

        if (isCurrent && currentProjectTree) {
            html += `<div class="tree-children">`;

            if (currentProjectTree.algorithms && currentProjectTree.algorithms.length > 0) {
                html += `
                    <div class="tree-node expanded" data-node-type="folder" data-full-path="0-algorithms">
                        <span class="tree-icon folder-icon">📂</span>
                        <span class="tree-node-text">algorithms</span>
                        <div class="tree-children">
                `;
                currentProjectTree.algorithms.forEach(algo => {
                    html += `
                        <div class="tree-node" data-node-type="algorithm" data-full-path="${algo}">
                            <span class="tree-icon algorithm-icon">🧮</span>
                            <span class="tree-node-text">${algo}</span>
                        </div>
                    `;
                });
                html += `</div></div>`;
            }

            if (currentProjectTree.models && currentProjectTree.models.length > 0) {
                html += `
                    <div class="tree-node expanded" data-node-type="folder" data-full-path="0-models">
                        <span class="tree-icon folder-icon">📂</span>
                        <span class="tree-node-text">models</span>
                        <div class="tree-children">
                `;
                currentProjectTree.models.forEach(model => {
                    html += `
                        <div class="tree-node" data-node-type="model" data-full-path="${model}">
                            <span class="tree-icon model-icon">📦</span>
                            <span class="tree-node-text">${model}</span>
                        </div>
                    `;
                });
                html += `</div></div>`;
            }

            if (currentProjectTree.datas && currentProjectTree.datas.length > 0) {
                html += `
                    <div class="tree-node expanded" data-node-type="folder" data-full-path="0-datas">
                        <span class="tree-icon folder-icon">📂</span>
                        <span class="tree-node-text">datas</span>
                        <div class="tree-children">
                `;
                currentProjectTree.datas.forEach((data, index) => {
                    html += `
                        <div class="tree-node" data-node-type="data" data-full-path="0-datas-${index}">
                            <span class="tree-icon data-icon">📊</span>
                            <span class="tree-node-text">${data}</span>
                        </div>
                    `;
                });
                html += `</div></div>`;
            }

            html += `</div>`;
        }

        html += `</div>`;
    });

    return html;
}

// 渲染单个ProjectTree结构
function renderProjectTree(treeData) {
    let html = '';

    // 根节点：项目名
    html += `
        <div class="tree-node expanded" data-node-type="project" data-full-path="0">
            <span class="tree-icon project-icon">📁</span>
            <span class="tree-node-text">${treeData.name}</span>
            <div class="tree-children">
    `;

    // 渲染算法节点
    if (treeData.algorithms && treeData.algorithms.length > 0) {
        html += `
            <div class="tree-node expanded" data-node-type="folder" data-full-path="0-algorithms">
                <span class="tree-icon folder-icon">📂</span>
                <span class="tree-node-text">algorithms</span>
                <div class="tree-children">
        `;
        treeData.algorithms.forEach((algo, index) => {
            html += `
                <div class="tree-node" data-node-type="algorithm" data-full-path="${algo}">
                    <span class="tree-icon algorithm-icon">🧮</span>
                    <span class="tree-node-text">${algo}</span>
                </div>
            `;
        });
        html += `
                </div>
            </div>
        `;
    }

    // 渲染模型节点
    if (treeData.models && treeData.models.length > 0) {
        html += `
            <div class="tree-node expanded" data-node-type="folder" data-full-path="0-models">
                <span class="tree-icon folder-icon">📂</span>
                <span class="tree-node-text">models</span>
                <div class="tree-children">
        `;
        treeData.models.forEach((model, index) => {
            html += `
                <div class="tree-node" data-node-type="model" data-full-path="${model}">
                    <span class="tree-icon model-icon">📦</span>
                    <span class="tree-node-text">${model}</span>
                </div>
            `;
        });
        html += `
                </div>
            </div>
        `;
    }

    // 渲染数据节点
    if (treeData.datas && treeData.datas.length > 0) {
        html += `
            <div class="tree-node expanded" data-node-type="folder" data-full-path="0-datas">
                <span class="tree-icon folder-icon">📂</span>
                <span class="tree-node-text">datas</span>
                <div class="tree-children">
        `;
        treeData.datas.forEach((data, index) => {
            html += `
                <div class="tree-node" data-node-type="data" data-full-path="0-datas-${index}">
                    <span class="tree-icon data-icon">📊</span>
                    <span class="tree-node-text">${data}</span>
                </div>
            `;
        });
        html += `
                </div>
            </div>
        `;
    }

    html += `
            </div>
        </div>
    `;

    return html;
}
