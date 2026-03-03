# DataModelGov API 测试脚本
Write-Host "=== DataModelGov API 测试 ===" -ForegroundColor Green

# 测试基础连接
Write-Host "`n1. 测试服务端连接..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "http://localhost:8080/actuator/health" -Method GET -TimeoutSec 5
    Write-Host "✅ HTTP服务正常 (端口8080)" -ForegroundColor Green
} catch {
    Write-Host "❌ HTTP服务连接失败: $($_.Exception.Message)" -ForegroundColor Red
}

# 测试数据源API
Write-Host "`n2. 测试数据源API..." -ForegroundColor Yellow
try {
    $body = @{
        ip = "127.0.0.1"
        port = 6667
        storageEngineType = "iotdb"
        hasData = $true
        isReadOnly = $false
        dataPrefix = "root.test"
        schemaPrefix = "root.test"
    } | ConvertTo-Json
    
    $response = Invoke-WebRequest -Uri "http://localhost:8080/api/datasource/register" -Method POST -Body $body -ContentType "application/json" -TimeoutSec 10
    Write-Host "✅ 数据源注册API正常" -ForegroundColor Green
} catch {
    Write-Host "❌ 数据源API失败: $($_.Exception.Message)" -ForegroundColor Red
}

# 测试模型API
Write-Host "`n3. 测试模型API..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "http://localhost:8080/api/model/metas" -Method GET -TimeoutSec 5
    Write-Host "✅ 模型查询API正常" -ForegroundColor Green
} catch {
    Write-Host "❌ 模型API失败: $($_.Exception.Message)" -ForegroundColor Red
}

# 测试Thrift端口
Write-Host "`n4. 测试Thrift端口..." -ForegroundColor Yellow
$tcpTest = Test-NetConnection -ComputerName localhost -Port 9090
if ($tcpTest.TcpTestSucceeded) {
    Write-Host "✅ Thrift服务正常 (端口9090)" -ForegroundColor Green
} else {
    Write-Host "❌ Thrift服务连接失败" -ForegroundColor Red
}

Write-Host "`n=== API 测试完成 ===" -ForegroundColor Green
