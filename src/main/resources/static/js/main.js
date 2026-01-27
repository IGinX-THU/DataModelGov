document.addEventListener('DOMContentLoaded', () => {
    // 顶部导航切换
    const tabs = document.querySelectorAll('.nav-tabs .tab');
    tabs.forEach(tab => {
        tab.addEventListener('click', () => {
            tabs.forEach(t => t.classList.remove('active'));
            tab.classList.add('active');
        });
    });

    // 树形节点展开/折叠
    const treeNodes = document.querySelectorAll('.tree-node');
    treeNodes.forEach(node => {
        // 只有包含子节点的才可以展开
        if (node.querySelector('.tree-children')) {
            node.addEventListener('click', (e) => {
                e.stopPropagation();
                node.classList.toggle('expanded');
            });
        }
    });
});