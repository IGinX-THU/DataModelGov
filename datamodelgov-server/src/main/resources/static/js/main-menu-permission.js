/**
 * 主页面菜单权限控制集成
 */
document.addEventListener('DOMContentLoaded', async function() {
    console.log('🚀 主页面加载完成');
    
    // 检查登录状态
    if (!window.AppConfig.isLoggedIn()) {
        window.location.href = '/login.html';
        return;
    }

    // 初始化菜单权限系统
    await initMenuPermission();
    
    // 绑定菜单权限检查到事件
    bindMenuPermissionChecks();
    
    // 显示用户信息
    displayUserInfo();
    
    // 恢复用户设置（字体大小和主题模式）
    if (window.restoreUserSettings) {
        window.restoreUserSettings();
    }
});

// 初始化菜单权限系统
async function initMenuPermission() {
    try {
        console.log('🔄 初始化菜单权限系统...');
        await window.MenuPermission.init();
        console.log('✅ 菜单权限系统初始化完成');
    } catch (error) {
        console.error('❌ 菜单权限系统初始化失败:', error);
    }
}

// 绑定菜单权限检查到事件
function bindMenuPermissionChecks() {
    // 菜单项点击事件
    document.querySelectorAll('.dropdown-menu li').forEach(item => {
        item.addEventListener('click', function(e) {
            const menuText = this.textContent.trim();
            const parentDropdown = this.closest('.dropdown');
            const dropdownId = parentDropdown ? parentDropdown.id : '';
            
            if (!checkMenuItemPermission(dropdownId, menuText)) {
                e.preventDefault();
                e.stopPropagation();
            }
        });
    });

    // 功能按钮点击事件
    document.querySelectorAll('.func-btn').forEach(btn => {
        btn.addEventListener('click', function(e) {
            const btnText = this.textContent.trim();
            const parentGroup = this.closest('.sub-tab-section');
            const groupIndex = Array.from(document.querySelectorAll('.sub-tab-section')).indexOf(parentGroup);
            
            if (!checkButtonPermission(groupIndex, btnText)) {
                e.preventDefault();
                e.stopPropagation();
            }
        });
    });
}

// 检查菜单项权限
function checkMenuItemPermission(dropdownId, menuText) {
    if (dropdownId === 'userDropdown' && menuText === '用户管理') {
        return window.MenuPermission.getCurrentRole() === 'ADMIN';
    }

    // 设置菜单（字体设置）不需要权限检查，所有用户都可访问
    if (dropdownId === 'settingsDropdown') {
        return true;
    }

    const menuAreaMapping = {
        'dataDropdown': 'data',
        'modelDropdown': 'model',
        'scheduleDropdown': 'schedule',
        'analysisDropdown': 'analysis',
        'userDropdown': 'user',
        'toolDropdown': 'tool',
        'windowDropdown': 'window',
        'settingsDropdown': 'settings',
        'helpDropdown': 'help'
    };

    const menuArea = menuAreaMapping[dropdownId];
    if (menuArea) {
        return window.MenuPermission.checkMenuPermission(menuArea, menuText);
    }
    
    return true; // 没有映射的菜单默认允许
}

// 检查按钮权限
function checkButtonPermission(groupIndex, btnText) {
    const groupMapping = {
        0: 'data',      // 数据资源管理按钮组
        1: 'model',     // 模型资产管理按钮组
        2: 'schedule',  // 关联调度引擎按钮组
        3: 'analysis'   // 可视化分析按钮组
    };

    const menuArea = groupMapping[groupIndex];
    if (menuArea) {
        return window.MenuPermission.checkMenuPermission(menuArea, btnText);
    }
    
    return true; // 没有映射的按钮默认允许
}

// 显示当前用户信息
function displayUserInfo() {
    const usernameEl = document.getElementById('username');
    if (usernameEl && window.MenuPermission.currentUser) {
        const user = window.MenuPermission.currentUser;
        const roleDesc = window.MenuPermission.getRoleDescription();
        const accessibleAreas = window.MenuPermission.getAccessibleMenuAreas();
        
        usernameEl.textContent = `${user.username} (${roleDesc})`;
        usernameEl.title = `当前用户: ${user.username}\n角色: ${roleDesc}\n可访问区域: ${accessibleAreas.join(', ')}`;
    }
}

// 页面加载完成后显示用户信息
setTimeout(displayUserInfo, 1500);

console.log('🔧 主页面菜单权限控制已加载');
