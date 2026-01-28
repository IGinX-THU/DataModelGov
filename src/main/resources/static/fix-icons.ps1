$html = Get-Content "index.html" -Raw
$html = $html -replace '<svg class="btn-icon"><use href="#icon-add"></use></svg>`n        <span>卸载</span>', '<svg class="btn-icon"><use href="#icon-unload"></use></svg>`n        <span>卸载</span>'
$html = $html -replace '<svg class="btn-icon"><use href="#icon-unload"></use></svg>`n        <span>导入</span>', '<svg class="btn-icon"><use href="#icon-import"></use></svg>`n        <span>导入</span>'
$html = $html -replace '<svg class="btn-icon"><use href="#icon-import"></use></svg>`n        <span>导出</span>', '<svg class="btn-icon"><use href="#icon-export"></use></svg>`n        <span>导出</span>'
$html = $html -replace '<svg class="btn-icon"><use href="#icon-unload"></use></svg>`n        <span>上传</span>', '<svg class="btn-icon"><use href="#icon-upload"></use></svg>`n        <span>上传</span>'
$html = $html -replace '<svg class="btn-icon"><use href="#icon-import"></use></svg>`n        <span>下载</span>', '<svg class="btn-icon"><use href="#icon-download"></use></svg>`n        <span>下载</span>'
$html = $html -replace '<svg class="btn-icon"><use href="#icon-upload"></use></svg>`n        <span>编辑</span>', '<svg class="btn-icon"><use href="#icon-edit"></use></svg>`n        <span>编辑</span>'
$html = $html -replace '<svg class="btn-icon"><use href="#icon-edit"></use></svg>`n        <span>解析</span>', '<svg class="btn-icon"><use href="#icon-parse"></use></svg>`n        <span>解析</span>'
$html = $html -replace '<svg class="btn-icon"><use href="#icon-run"></use></svg>`n        <span>停止</span>', '<svg class="btn-icon"><use href="#icon-stop"></use></svg>`n        <span>停止</span>'
Set-Content "index.html" $html
