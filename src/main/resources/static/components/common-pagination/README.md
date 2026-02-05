# 通用分页组件 (Common Pagination)

## 功能特性

- ✅ 完整的分页功能：首页、上一页、页码、下一页、尾页
- ✅ 每页显示条数选择：10、20、50、100条
- ✅ 显示当前数据范围和总条数
- ✅ 智能页码省略显示
- ✅ 响应式设计，支持移动端
- ✅ 完整的事件系统
- ✅ 使用CSS变量，支持主题切换

## 使用方法

### 1. 引入组件

```html
<!-- 在index.html中添加 -->
<script src="./components/common-pagination/common-pagination.js"></script>
```

### 2. HTML中使用

```html
<common-pagination id="pagination"></common-pagination>
```

### 3. JavaScript控制

```javascript
const pagination = document.getElementById('pagination');

// 设置分页数据
pagination.setPagination(currentPage, pageSize, totalRecords);

// 监听分页变化事件
pagination.addEventListener('pagination-change', (event) => {
    const { currentPage, pageSize, totalRecords, totalPages } = event.detail;
    console.log('分页变化:', { currentPage, pageSize, totalRecords, totalPages });
    
    // 重新加载数据
    loadData(currentPage, pageSize);
});

// 获取分页信息
const info = pagination.getPaginationInfo();
console.log(info); // { currentPage, pageSize, totalRecords, totalPages, startIndex, endIndex }

// 重置分页
pagination.reset();
```

## API文档

### 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| currentPage | number | 1 | 当前页码 |
| pageSize | number | 10 | 每页显示条数 |
| totalRecords | number | 0 | 总记录数 |
| maxVisiblePages | number | 7 | 最大显示页码数 |

### 方法

| 方法 | 参数 | 返回值 | 说明 |
|------|------|--------|------|
| setPagination(currentPage, pageSize, totalRecords) | number, number, number | void | 设置分页数据 |
| goToPage(page) | number | void | 跳转到指定页 |
| goToPrevPage() | - | void | 上一页 |
| goToNextPage() | - | void | 下一页 |
| goToLastPage() | - | void | 尾页 |
| changePageSize(newPageSize) | number | void | 改变每页显示条数 |
| getPaginationInfo() | - | object | 获取分页信息 |
| reset() | - | void | 重置分页 |

### 事件

| 事件名 | 参数 | 说明 |
|--------|------|------|
| pagination-change | { currentPage, pageSize, totalRecords, totalPages } | 分页状态改变时触发 |

## 样式定制

组件使用CSS变量，可以通过修改变量来自定义样式：

```css
common-pagination {
    --pagination-padding: 16px 8px 4px;
    --pagination-gap: 24px;
    --pagination-button-height: 32px;
    --pagination-button-min-width: 32px;
}
```

## 完整示例

```html
<!DOCTYPE html>
<html>
<head>
    <title>分页组件示例</title>
</head>
<body>
    <div class="container">
        <h1>数据列表</h1>
        <table id="dataTable">
            <!-- 数据表格 -->
        </table>
        <common-pagination id="pagination"></common-pagination>
    </div>

    <script>
        let currentPage = 1;
        let pageSize = 10;
        let totalRecords = 156;

        const pagination = document.getElementById('pagination');
        
        // 初始化分页
        pagination.setPagination(currentPage, pageSize, totalRecords);
        
        // 监听分页变化
        pagination.addEventListener('pagination-change', (event) => {
            const { currentPage: newPage, pageSize: newSize } = event.detail;
            currentPage = newPage;
            pageSize = newSize;
            loadData();
        });
        
        // 加载数据
        function loadData() {
            const info = pagination.getPaginationInfo();
            console.log(`加载第${currentPage}页，每页${pageSize}条`);
            console.log(`数据范围：${info.startIndex + 1}-${info.endIndex + 1}`);
            
            // 这里调用API获取数据
            // fetch(`/api/data?page=${currentPage}&size=${pageSize}`)
            //     .then(response => response.json())
            //     .then(data => {
            //         renderTable(data.records);
            //         pagination.setPagination(currentPage, pageSize, data.total);
            //     });
        }
        
        // 初始加载
        loadData();
    </script>
</body>
</html>
```

## 响应式特性

- **桌面端**：显示完整的分页控件
- **平板端**：保持完整布局，调整间距
- **手机端**：
  - 隐藏"首页"和"尾页"按钮
  - 垂直布局信息区域
  - 调整按钮大小和间距

## 注意事项

1. 组件会自动处理边界情况（如总记录数为0、只有一页等）
2. 页码省略算法会根据当前页位置智能显示
3. 所有样式使用CSS变量，支持暗黑模式
4. 组件使用Shadow DOM，避免样式冲突
