document.addEventListener('DOMContentLoaded', function() {
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

    // 2. 树形节点展开/折叠
    const treeNodes = document.querySelectorAll('.tree-node');
    treeNodes.forEach(node => {
        if (node.querySelector('.tree-children')) {
            node.addEventListener('click', function(e) {
                e.stopPropagation();
                this.classList.toggle('expanded');
                const folderIcon = this.querySelector('.folder-icon, .folder-open-icon');
                if (folderIcon) {
                    if (this.classList.contains('expanded')) {
                        folderIcon.classList.remove('folder-icon');
                        folderIcon.classList.add('folder-open-icon');
                    } else {
                        folderIcon.classList.remove('folder-open-icon');
                        folderIcon.classList.add('folder-icon');
                    }
                }
            });
        }
        node.addEventListener('click', function(e) {
            e.stopPropagation();
            const siblings = Array.from(this.parentElement.children);
            siblings.forEach(sib => sib.classList.remove('active'));
            this.classList.add('active');
        });
    });

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

    // 5. 下拉菜单极简修复：直接绑定ID，强制切换active
    const toolDropdown = document.getElementById('toolDropdown');
    const windowDropdown = document.getElementById('windowDropdown');
    const helpDropdown = document.getElementById('helpDropdown');

    // 工具菜单
    toolDropdown.addEventListener('click', function(e) {
        e.stopPropagation();
        // 关闭其他菜单
        windowDropdown.classList.remove('active');
        helpDropdown.classList.remove('active');
        // 切换自身
        this.classList.toggle('active');
    });

    // 窗口菜单
    windowDropdown.addEventListener('click', function(e) {
        e.stopPropagation();
        toolDropdown.classList.remove('active');
        helpDropdown.classList.remove('active');
        this.classList.toggle('active');
    });

    // 帮助菜单
    helpDropdown.addEventListener('click', function(e) {
        e.stopPropagation();
        toolDropdown.classList.remove('active');
        windowDropdown.classList.remove('active');
        this.classList.toggle('active');
    });

    // 点击页面其他区域关闭所有下拉菜单
    document.addEventListener('click', function() {
        toolDropdown.classList.remove('active');
        windowDropdown.classList.remove('active');
        helpDropdown.classList.remove('active');
    });

    // 阻止菜单子项点击冒泡（点击子项不关闭菜单）
    const menuItems = document.querySelectorAll('.dropdown-menu li');
    menuItems.forEach(item => {
        item.addEventListener('click', function(e) {
            e.stopPropagation();
        });
    });
});