$html = Get-Content "index.html" -Raw
$html = $html -replace 'href="#', 'href="./icons/func-icons.svg#'
Set-Content "index.html" $html
