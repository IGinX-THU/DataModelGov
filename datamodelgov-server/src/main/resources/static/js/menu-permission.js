/**
 * 基于父级菜单的权限控制系统
 * 按照用户角色控制整个菜单区域的显示
 */
class MenuPermission {
    constructor() {
        this.currentUser = null;
        this.userRole = null;
        this.isReady = false;
    }

    // 初始化权限系统
    async init() {
        try {
            await this.loadUserRole();
            this.isReady = true;
            console.log(`✅ 菜单权限系统初始化完成 - 角色: ${this.userRole}`);
            this.applyMenuPermissions();
        } catch (error) {
            console.error('❌ 菜单权限系统初始化失败:', error);
        }
    }

    // 加载用户角色
    async loadUserRole() {
        try {
            const response = await fetch('/api/user/current', {
                headers: {
                    'Authorization': 'Bearer ' + localStorage.getItem('jwtToken')
                }
            });
            
            if (response.ok) {
                const data = await response.json();
                this.currentUser = data.data;
                this.userRole = this.currentUser.role;
            } else {
                // 获取用户失败，跳转到登录页面
                console.error('获取用户信息失败，跳转到登录页面');
                window.location.href = '/login.html';
                throw new Error('获取用户信息失败');
            }
        } catch (error) {
            console.error('获取用户角色失败，跳转到登录页面:', error);
            window.location.href = '/login.html';
            throw error;
        }
    }

    // 检查菜单权限
    hasMenuPermission(menuArea) {
        if (!this.isReady) return false;

        // 根据角色定义可访问的菜单区域
        const menuPermissions = {
            // ADMIN - 所有菜单区域
            'ADMIN': ['data', 'model', 'schedule', 'analysis', 'user', 'tool', 'window', 'help'],
            // DATA_ENGINEER - 含「用户」父菜单；其中「用户管理」子项仅管理员可见，由 applyUserDropdownSubmenuVisibility 控制
            'DATA_ENGINEER': ['data', 'model', 'schedule', 'analysis', 'user', 'tool', 'window', 'help']
        };

        return menuPermissions[this.userRole]?.includes(menuArea) || false;
    }

    // 应用菜单权限控制
    applyMenuPermissions() {
        if (!this.isReady) return;

        // 控制菜单标签显示
        this.controlMenuTabs();

        // 「用户」下拉内：仅管理员可见「用户管理」
        this.applyUserDropdownSubmenuVisibility();
        
        // 控制功能按钮组显示
        this.controlFunctionButtonGroups();
    }

    /** 「用户管理」仅 ADMIN；「权限管理」「修改密码」对所有已登录角色可见 */
    applyUserDropdownSubmenuVisibility() {
        const el = document.getElementById('userManagementMenuItem');
        if (!el) {
            return;
        }
        el.style.display = this.userRole === 'ADMIN' ? '' : 'none';
    }

    // 控制菜单标签
    controlMenuTabs() {
        const menuAreaMapping = {
            'dataDropdown': 'data',
            'modelDropdown': 'model', 
            'scheduleDropdown': 'schedule',
            'analysisDropdown': 'analysis',
            'userDropdown': 'user',
            'toolDropdown': 'tool',
            'windowDropdown': 'window',
            'helpDropdown': 'help'
        };

        Object.entries(menuAreaMapping).forEach(([dropdownId, menuArea]) => {
            const menuTab = document.querySelector(`#${dropdownId}.tab.dropdown`);
            if (menuTab && !this.hasMenuPermission(menuArea)) {
                menuTab.style.display = 'none';
            }
        });
    }

    // 控制功能按钮组
    controlFunctionButtonGroups() {
        // 按钮组与菜单区域的对应关系
        const buttonGroupMapping = {
            'data': 0,    // 数据资源管理按钮组
            'model': 1,   // 模型资产管理按钮组
            'schedule': 2, // 关联调度引擎按钮组
            'analysis': 3  // 可视化分析按钮组
        };

        const buttonGroups = document.querySelectorAll('.sub-tab-section');
        
        Object.entries(buttonGroupMapping).forEach(([menuArea, groupIndex]) => {
            if (buttonGroups[groupIndex] && !this.hasMenuPermission(menuArea)) {
                buttonGroups[groupIndex].style.display = 'none';
            }
        });
    }

    // 权限检查装饰器
    checkMenuPermission(menuArea, actionName) {
        if (!this.hasMenuPermission(menuArea)) {
            this.showPermissionError(actionName);
            return false;
        }
        return true;
    }

    // 显示权限错误
    showPermissionError(actionName) {
        const roleNames = {
            'ADMIN': '管理员',
            'DATA_ENGINEER': '数据工程师'
        };
        
        const message = `权限不足：${actionName}需要相应权限\n当前角色：${roleNames[this.userRole] || this.userRole}`;
        
        // 尝试使用CommonUtils显示错误，否则使用alert
        if (window.CommonUtils && window.CommonUtils.showError) {
            window.CommonUtils.showError(message, 5000);
        } else {
            alert(message);
        }
    }

    // 获取当前角色
    getCurrentRole() {
        return this.userRole;
    }

    // 获取角色描述
    getRoleDescription() {
        const descriptions = {
            'ADMIN': '管理员',
            'DATA_ENGINEER': '数据工程师'
        };
        return descriptions[this.userRole] || this.userRole;
    }

    // 获取可访问的菜单区域
    getAccessibleMenuAreas() {
        const allAreas = ['data', 'model', 'schedule', 'analysis', 'user', 'tool', 'window', 'help'];
        return allAreas.filter(area => this.hasMenuPermission(area));
    }
}

// 创建全局实例
window.MenuPermission = new MenuPermission();

// 便捷函数
window.hasMenuPermission = (menuArea) => window.MenuPermission.hasMenuPermission(menuArea);
window.checkMenuPermission = (menuArea, action) => window.MenuPermission.checkMenuPermission(menuArea, action);
window.getCurrentRole = () => window.MenuPermission.getCurrentRole();

console.log('🔐 菜单权限系统已加载');
