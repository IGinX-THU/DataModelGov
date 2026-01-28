$html = Get-Content "index.html" -Raw
$svg = Get-Content "icons\func-icons.svg" -Raw
$html = $html -replace "<body>", "<body>`n$svg"
Set-Content "index.html" $html
