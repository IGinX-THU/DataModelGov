// 页面加载完成后初始化
document.addEventListener("DOMContentLoaded", function() {
    // 导航切换
    const navItems = document.querySelectorAll(".nav-item");
    const sections = document.querySelectorAll(".page-section");
    navItems.forEach(item => {
        item.addEventListener("click", function() {
            const target = this.getAttribute("href").substring(1);
            // 切换导航激活状态
            navItems.forEach(nav => nav.classList.remove("active"));
            this.classList.add("active");
            // 切换页面显示
            sections.forEach(section => section.classList.add("hidden"));
            document.getElementById(target).classList.remove("hidden");
        });
    });

    // 新增数据源按钮点击事件
    const addBtn = document.getElementById("addDataSourceBtn");
    const dataSourceForm = document.getElementById("dataSourceForm");
    const cancelBtn = document.getElementById("cancelForm");
    addBtn.addEventListener("click", () => {
        dataSourceForm.classList.remove("hidden");
    });
    cancelBtn.addEventListener("click", () => {
        dataSourceForm.classList.add("hidden");
    });

    // 数据源注册表单提交
    const sourceForm = document.getElementById("sourceForm");
    sourceForm.addEventListener("submit", async function(e) {
        e.preventDefault();
        const formData = new FormData(this);
        const data = {};
        formData.forEach((value, key) => {
            data[key] = value;
        });
        // 调用注册接口
        const result = await DataSourceApi.register(data);
        if (result) {
            alert("注册成功！");
            this.reset();
            dataSourceForm.classList.add("hidden");
            // 刷新数据源列表（实际项目需实现）
        }
    });

    // 初始化数据源列表（实际项目需调用接口加载）
    loadDataSourceList();
});

/**
 * 加载数据源列表
 */
async function loadDataSourceList() {
    const listContainer = document.getElementById("dataSourceList");
    const data = await DataSourceApi.list();
    if (data && data.length > 0) {
        listContainer.innerHTML = data.map(item => `
            <div class="source-item">
                <div class="source-name">${item.alias}</div>
                <div class="source-info">类型：${item.type} | IP：${item.ip}:${item.port}</div>
                <button class="remove-btn" data-alias="${item.alias}">移除</button>
            </div>
        `).join("");
        // 绑定移除按钮事件
        document.querySelectorAll(".remove-btn").forEach(btn => {
            btn.addEventListener("click", async function() {
                const alias = this.getAttribute("data-alias");
                if (confirm(`确定要移除数据源${alias}吗？`)) {
                    const result = await DataSourceApi.remove(alias);
                    if (result) {
                        alert("移除成功！");
                        loadDataSourceList();
                    }
                }
            });
        });
    } else {
        listContainer.innerHTML = "<div class='empty-tip'>暂无已注册的数据源</div>";
    }
}