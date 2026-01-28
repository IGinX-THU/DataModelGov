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

    // 2. 树形节点点击事件
    const treeNodes = document.querySelectorAll('.tree-node');
    treeNodes.forEach(node => {
        node.addEventListener('click', function(e) {
            e.stopPropagation();
            
            // 先清除所有选中状态
            treeNodes.forEach(n => n.classList.remove('active'));
            
            // 设置当前选中
            this.classList.add('active');
            
            // 展开收起（如果有子节点）
            if (this.querySelector('.tree-children')) {
                this.classList.toggle('expanded');
            }
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
        });
    });
});
