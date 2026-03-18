# 通用样式系统使用指南

## 概述

本项目已建立统一的样式系统，将常用样式抽取到公共文件中，确保所有组件的视觉一致性和维护便利性。

## 文件结构

```
static/css/
├── variables.css          # CSS变量定义（颜色、间距、字体等）
├── base-components.css   # 基础组件样式（表格、按钮、分页等）
├── reset.css            # 样式重置
└── README.md           # 本文档

static/js/
└── common-utils.js      # 通用工具函数（消息显示、确认对话框等）
```

## 样式统一规范

### 1. 表格样式（Database Table 模式）

所有表格使用统一的样式，已在 `base-components.css` 中定义：

```css
.data-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 12px;
}

.data-table th {
  background: #f7f8fb;
  color: #6b7280;
  font-weight: 600;
  padding: 10px 8px;
  border-bottom: 1px solid #eef1f6;
}

.data-table td {
  color: #4b5563;
  padding: 10px 8px;
  border-bottom: 1px solid #eef1f6;
}

.data-table tr:hover {
  background: #f8fafc;
}
```

### 2. 工具栏按钮样式（Association Rules 模式）

统一的工具栏按钮颜色：

```css
.toolbar-btn.green  { background: #10b981; } /* 新增 */
.toolbar-btn.orange { background: #f59e0b; }  /* 导入 */
.toolbar-btn.blue   { background: #3b82f6; }  /* 导出 */
```

### 3. 操作按钮样式

表格内操作按钮使用统一的样式：

```css
.action-btn.edit    { color: #3b82f6; border-color: #3b82f6; }
.action-btn.delete  { color: #ef4444; border-color: #ef4444; }
.action-btn.copy    { color: #10b981; border-color: #10b981; }
.action-btn.run     { color: #7666EB; border-color: #7666EB; }
```

### 4. 分页样式

统一的分页组件样式：

```css
.page-number.active {
  background: #3b82f6;
  border-color: #3b82f6;
  color: white;
}
```

### 5. 消息提示样式

统一的消息提示，支持四种类型：

```css
.message.success { background: var(--color-success); }
.message.error   { background: var(--color-danger); }
.message.info    { background: var(--color-info); }
.message.warning { background: var(--color-warning); }
```

## JavaScript 工具函数

### 消息显示

```javascript
// 使用通用工具函数
window.CommonUtils.showSuccess('操作成功');
window.CommonUtils.showError('操作失败');
window.CommonUtils.showInfo('提示信息');
window.CommonUtils.showWarning('警告信息');
```

### 确认对话框

```javascript
const result = await window.CommonUtils.confirmDialog('确定删除吗？', '确认操作');
if (result) {
    // 用户点击确认
}
```

## 组件开发规范

### 1. CSS 文件结构

```css
/* Component Name - Using Common Styles */
@import url('../../css/variables.css');
@import url('../../css/base-components.css');

/* 组件特有样式 */
.component-specific {
  /* 只定义组件独有的样式 */
}

/* 通用样式已在 base-components.css 中定义，无需重复 */
```

### 2. 移除重复样式

以下样式已移至公共文件，组件中无需重复定义：

- ✅ `.data-table` 及相关样式
- ✅ `.toolbar-btn` 及颜色变体
- ✅ `.action-btn` 及类型变体
- ✅ `.pagination` 及分页样式
- ✅ `.message` 及消息样式
- ✅ `.table-wrapper` 表格容器样式

### 3. 引用通用工具

在组件的 `connectedCallback` 中加载通用工具：

```javascript
async loadResources() {
    // 加载通用工具
    if (!window.CommonUtils) {
        const script = document.createElement('script');
        script.src = './js/common-utils.js';  // 从组件目录的相对路径
        document.head.appendChild(script);
        await new Promise(resolve => {
            script.onload = resolve;
        });
    }
    // 加载其他资源...
}
```

## 已更新的组件

以下组件已更新为使用通用样式系统：

- ✅ `database-table` - 表格样式统一，消息系统集成
- ✅ `visual-analysis` - 移除重复表格样式
- ✅ `parsing-rules` - 移除重复样式，使用通用样式
- ✅ `data-visualization` - 移除重复按钮样式
- ✅ `model-detail` - 移除重复按钮样式
- ✅ `association-rules` - 作为样式参考标准

## 颜色规范

### 主色调
- 主色：`#3b82f6` (Blue)
- 成功：`#10b981` (Green)  
- 警告：`#f59e0b` (Orange)
- 危险：`#ef4444` (Red)

### 辅助色
- 信息：`#6b7280` (Gray)
- 边框：`#e2e6ef` (Light Gray)
- 背景：`#f8fafc` (Light Blue)

## 暗黑模式支持

所有样式通过 CSS 变量支持暗黑模式，自动适配主题切换。

## 维护指南

1. **新增样式**：优先考虑是否为通用样式，如是则添加到 `base-components.css`
2. **修改样式**：修改通用样式会影响所有组件，请谨慎操作
3. **组件特有样式**：只在组件 CSS 文件中定义组件独有的样式
4. **测试**：修改通用样式后需要测试所有使用该样式的组件

## 注意事项

- 组件 CSS 文件应保持简洁，只包含组件特有样式
- 使用通用工具函数替代重复的 JavaScript 代码
- 保持视觉一致性，遵循已建立的设计规范
- 新组件应优先使用现有通用样式，避免重复定义
