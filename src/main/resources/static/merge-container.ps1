$html = Get-Content "index.html" -Raw

# 修复剩余的图标引用
$html = $html -replace '<svg class="btn-icon"><use href="#icon-add"></use></svg>`n        <span>卸载</span>', '<svg class="btn-icon"><use href="#icon-unload"></use></svg>`n        <span>卸载</span>'
$html = $html -replace '<svg class="btn-icon"><use href="#icon-unload"></use></svg>`n        <span>上传</span>', '<svg class="btn-icon"><use href="#icon-upload"></use></svg>`n        <span>上传</span>'
$html = $html -replace '<svg class="btn-icon"><use href="#icon-import"></use></svg>`n        <span>下载</span>', '<svg class="btn-icon"><use href="#icon-download"></use></svg>`n        <span>下载</span>'
$html = $html -replace '<svg class="btn-icon"><use href="#icon-upload"></use></svg>`n        <span>编辑</span>', '<svg class="btn-icon"><use href="#icon-edit"></use></svg>`n        <span>编辑</span>'
$html = $html -replace '<svg class="btn-icon"><use href="#icon-edit"></use></svg>`n        <span>解析</span>', '<svg class="btn-icon"><use href="#icon-parse"></use></svg>`n        <span>解析</span>'
$html = $html -replace '<svg class="btn-icon"><use href="#icon-run"></use></svg>`n        <span>停止</span>', '<svg class="btn-icon"><use href="#icon-stop"></use></svg>`n        <span>停止</span>'

# 合并功能按钮栏和标签栏
$funcBtnSection = '<!-- 功能按钮栏和标签栏合并区域 -->
<div class="func-tab-container">
    <!-- 功能按钮栏 -->
    <div class="func-btn-bar">
        <button class="func-btn">
            <svg class="btn-icon"><use href="#icon-add"></use></svg>
            <span>新增</span>
        </button>
        <button class="func-btn">
            <svg class="btn-icon"><use href="#icon-unload"></use></svg>
            <span>卸载</span>
        </button>
        <button class="func-btn">
            <svg class="btn-icon"><use href="#icon-import"></use></svg>
            <span>导入</span>
        </button>
        <button class="func-btn">
            <svg class="btn-icon"><use href="#icon-export"></use></svg>
            <span>导出</span>
        </button>
        <button class="func-btn">
            <svg class="btn-icon"><use href="#icon-upload"></use></svg>
            <span>上传</span>
        </button>
        <button class="func-btn">
            <svg class="btn-icon"><use href="#icon-download"></use></svg>
            <span>下载</span>
        </button>
        <button class="func-btn">
            <svg class="btn-icon"><use href="#icon-edit"></use></svg>
            <span>编辑</span>
        </button>
        <button class="func-btn">
            <svg class="btn-icon"><use href="#icon-parse"></use></svg>
            <span>解析</span>
        </button>
        <button class="func-btn">
            <svg class="btn-icon"><use href="#icon-link"></use></svg>
            <span>关联</span>
        </button>
        <button class="func-btn">
            <svg class="btn-icon"><use href="#icon-run"></use></svg>
            <span>执行</span>
        </button>
        <button class="func-btn">
            <svg class="btn-icon"><use href="#icon-stop"></use></svg>
            <span>停止</span>
        </button>
        <button class="func-btn">
            <svg class="btn-icon"><use href="#icon-analyze"></use></svg>
            <span>分析</span>
        </button>
    </div>

    <!-- 二级标签栏 -->
    <div class="sub-tab-bar">
        <span class="sub-tab">数据资源管理</span>
        <span class="sub-tab">模型资产管理</span>
        <span class="sub-tab">关联调度引擎</span>
        <span class="sub-tab">可视化分析</span>
    </div>
</div>'

# 替换原有的功能按钮栏和标签栏
$html = $html -replace '(?s)<!-- 功能按钮栏 -->.*?<div class="sub-tab-bar">.*?</div>', $funcBtnSection

Set-Content "index.html" $html
