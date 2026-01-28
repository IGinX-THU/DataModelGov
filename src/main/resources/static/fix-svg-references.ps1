$html = Get-Content "index.html" -Raw
$html = $html -replace 'href="./icons/func-icons.svg#', 'href="#'
Set-Content "index.html" $html
