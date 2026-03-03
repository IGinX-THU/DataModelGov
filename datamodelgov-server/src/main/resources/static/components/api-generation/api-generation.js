// API代码生成页面JavaScript (原生JavaScript版本 - 不依赖jQuery)

document.addEventListener('DOMContentLoaded', function() {
    // 页面加载完成后检查系统状态
    // 延迟执行，确保DOM完全加载
    setTimeout(function() {
        var statusButton = document.querySelector('.btn-outline-primary');
        if (statusButton) {
            checkStatus(statusButton);
        }
    }, 100);
});

/**
 * 生成代码
 * @param {string} type - 代码类型 (java, go, python, restful, all)
 * @param {HTMLElement} buttonElement - 按钮元素
 */
function generateCode(type, buttonElement) {
    // 使用传入的按钮元素，而不是event.target
    var button = buttonElement || event.target;
    var originalText = button.innerHTML;
    var card = findClosest(button, '.generation-card');
    var statusContainer = card.querySelector('.status-container');
    
    // 禁用按钮并显示加载状态
    button.disabled = true;
    button.innerHTML = '<i class="fa fa-spinner fa-spin"></i> 生成中...';
    
    // 清除之前的状态
    statusContainer.innerHTML = '';
    hideProgress();
    hideLog();
    hideResult();
    
    // 显示进度条
    showProgress();
    updateProgress(0, '开始生成' + getTypeDisplayName(type) + '代码...');
    
    // 添加日志
    addLog('开始生成' + getTypeDisplayName(type) + '代码');
    addLog('使用Thrift版本: 0.22.0');
    
    // 发送API请求
    var apiUrl = '/api/generation/' + type;
    
    fetch(apiUrl, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        }
    })
    .then(function(response) {
        if (!response.ok) {
            throw new Error('HTTP ' + response.status);
        }
        return response.json();
    })
    .then(function(response) {
        updateProgress(100, '代码生成完成');
        addLog('代码生成成功完成');
        
        if (response.success) {
            showStatus(statusContainer, 'success', '生成成功');
            // 检查是否有数据字段，如果没有则使用message
            var outputInfo = response.data || response.message;
            addLog('输出目录: ' + outputInfo);
            showResult(type, response);
        } else {
            showStatus(statusContainer, 'error', '生成失败');
            addLog('错误: ' + response.message);
            showError(response.message);
        }
    })
    .catch(function(error) {
        updateProgress(0, '生成失败');
        addLog('请求失败: ' + error.message);
        showStatus(statusContainer, 'error', '请求失败');
        showError('请求失败: ' + error.message);
    })
    .finally(function() {
        // 恢复按钮状态
        button.disabled = false;
        button.innerHTML = originalText;
        
        // 延迟隐藏进度条
        setTimeout(function() {
            hideProgress();
        }, 2000);
    });
}

/**
 * 检查系统状态
 * @param {HTMLElement} buttonElement - 按钮元素
 */
function checkStatus(buttonElement) {
    var button = buttonElement || event.target;
    var card = findClosest(button, '.generation-card');
    var statusContainer = card.querySelector('.status-container');
    
    if (button) {
        button.disabled = true;
        var originalText = button.innerHTML;
        button.innerHTML = '<i class="fa fa-spinner fa-spin"></i> 检查中...';
    }
    
    // 添加日志
    addLog('检查系统状态和Thrift编译器...');
    
    fetch('/api/generation/status', {
        method: 'GET'
    })
    .then(function(response) {
        if (!response.ok) {
            throw new Error('HTTP ' + response.status);
        }
        return response.json();
    })
    .then(function(response) {
        if (response.success) {
            showStatus(statusContainer, 'success', '服务正常');
            addLog('系统状态检查: 正常');
            // 检查是否有数据字段，如果没有则使用message
            var detailInfo = response.data || response.message;
            addLog('详细信息: ' + detailInfo);
        } else {
            showStatus(statusContainer, 'error', '服务异常');
            addLog('系统状态检查: 异常 - ' + response.message);
        }
    })
    .catch(function(error) {
        showStatus(statusContainer, 'error', '连接失败');
        addLog('状态检查失败: ' + error.message);
    })
    .finally(function() {
        if (button) {
            button.disabled = false;
            button.innerHTML = '<i class="fa fa-heartbeat"></i> 检查状态';
        }
    });
}

/**
 * 验证Thrift文件
 */
function validateThriftFile() {
    addLog('验证Thrift文件语法...');
    
    fetch('/api/generation/validate', {
        method: 'GET'
    })
    .then(function(response) {
        if (!response.ok) {
            throw new Error('HTTP ' + response.status);
        }
        return response.json();
    })
    .then(function(response) {
        if (response.success) {
            addLog('✅ Thrift文件语法正确');
            // 检查是否有数据字段，如果没有则使用message
            var detailInfo = response.data || response.message;
            addLog('详细信息: ' + detailInfo);
        } else {
            addLog('❌ Thrift文件语法错误');
            addLog('错误信息: ' + response.message);
        }
    })
    .catch(function(error) {
        addLog('验证失败: ' + error.message);
    });
}

/**
 * 显示状态标签
 * @param {HTMLElement} container - 状态容器
 * @param {string} type - 状态类型 (success, error, pending)
 * @param {string} message - 状态消息
 */
function showStatus(container, type, message) {
    var badgeClass = 'status-' + type;
    var badge = document.createElement('span');
    badge.className = 'status-badge ' + badgeClass;
    badge.textContent = message;
    container.innerHTML = '';
    container.appendChild(badge);
}

/**
 * 显示进度条
 */
function showProgress() {
    var progressContainer = document.querySelector('.progress-container');
    if (progressContainer) {
        progressContainer.style.display = 'block';
    }
}

/**
 * 隐藏进度条
 */
function hideProgress() {
    var progressContainer = document.querySelector('.progress-container');
    if (progressContainer) {
        progressContainer.style.display = 'none';
    }
}

/**
 * 更新进度条
 * @param {number} percent - 进度百分比
 * @param {string} text - 进度文本
 */
function updateProgress(percent, text) {
    var progressBar = document.querySelector('.progress-bar');
    var progressText = document.querySelector('.progress-text');
    if (progressBar) {
        progressBar.style.width = percent + '%';
    }
    if (progressText) {
        progressText.textContent = text;
    }
}

/**
 * 显示日志容器
 */
function showLog() {
    var logContainer = document.querySelector('.log-container');
    if (logContainer) {
        logContainer.style.display = 'block';
    }
}

/**
 * 隐藏日志容器
 */
function hideLog() {
    var logContainer = document.querySelector('.log-container');
    var logContent = document.querySelector('.log-content');
    if (logContainer) {
        logContainer.style.display = 'none';
    }
    if (logContent) {
        logContent.innerHTML = '';
    }
}

/**
 * 添加日志
 * @param {string} message - 日志消息
 */
function addLog(message) {
    showLog();
    var timestamp = new Date().toLocaleTimeString();
    var logEntry = document.createElement('div');
    logEntry.textContent = '[' + timestamp + '] ' + message;
    var logContent = document.querySelector('.log-content');
    var logContainerElement = document.querySelector('.log-container');
    
    if (logContent) {
        logContent.appendChild(logEntry);
    }
    if (logContainerElement) {
        // 滚动到底部
        logContainerElement.scrollTop = logContainerElement.scrollHeight;
    }
}

/**
 * 显示结果
 * @param {string} type - 代码类型
 * @param {Object} response - API响应
 */
function showResult(type, response) {
    var resultContainer = document.getElementById('resultContainer');
    var resultContent = document.getElementById('resultContent');
    
    var content = '';
    
    if (type === 'all' && response.data) {
        // 显示所有语言的生成结果
        content = '<div class="row">';
        for (var lang in response.data) {
            var status = response.data[lang];
            var statusClass = status === '成功' ? 'success' : 'error';
            var icon = status === '成功' ? 'check-circle' : 'times-circle';
            content += '<div class="col-md-3">' +
                    '<div class="card mb-2">' +
                        '<div class="card-body text-center">' +
                            '<i class="fa fa-' + icon + ' text-' + statusClass + '"></i>' +
                            '<h6>' + getTypeDisplayName(lang) + '</h6>' +
                            '<span class="badge badge-' + statusClass + '">' + status + '</span>' +
                        '</div>' +
                    '</div>' +
                '</div>';
        }
        content += '</div>';
    } else {
        // 显示单个语言的生成结果
        content = '<div class="alert alert-success">' +
                '<h5><i class="fa fa-check-circle"></i> ' + getTypeDisplayName(type) + '代码生成成功</h5>' +
                '<p class="mb-0">' + (response.data || response.message) + '</p>' +
            '</div>' +
            '<div class="mt-3">' +
                '<h6>后续操作建议：</h6>' +
                '<ul>' +
                    '<li>检查生成的代码文件</li>' +
                    '<li>根据需要调整生成的代码</li>' +
                    '<li>运行测试确保代码正常工作</li>' +
                    '<li>集成到现有项目中</li>' +
                '</ul>' +
            '</div>';
    }
    
    if (resultContent) {
        resultContent.innerHTML = content;
        resultContainer.style.display = 'block';
    }
}

/**
 * 隐藏结果
 */
function hideResult() {
    var resultContainer = document.getElementById('resultContainer');
    if (resultContainer) {
        resultContainer.style.display = 'none';
    }
}

/**
 * 显示错误信息
 * @param {string} message - 错误消息
 */
function showError(message) {
    var resultContainer = document.getElementById('resultContainer');
    var resultContent = document.getElementById('resultContent');
    
    var content = '<div class="alert alert-danger">' +
            '<h5><i class="fa fa-times-circle"></i> 代码生成失败</h5>' +
            '<p class="mb-0">' + message + '</p>' +
        '</div>' +
        '<div class="mt-3">' +
            '<h6>可能的原因：</h6>' +
            '<ul>' +
                '<li>Thrift编译器未安装或版本不兼容（需要0.22.0+）</li>' +
                '<li>系统权限不足</li>' +
                '<li>磁盘空间不足</li>' +
                '<li>网络连接问题</li>' +
                '<li>Thrift IDL文件语法错误</li>' +
            '</ul>' +
            '<div class="mt-3">' +
                '<button class="btn btn-outline-primary" onclick="validateThriftFile()">' +
                    '<i class="fa fa-check"></i> 验证Thrift文件' +
                '</button>' +
                '<button class="btn btn-outline-info ml-2" onclick="checkStatus(document.querySelector(\'.btn-outline-primary\'))">' +
                    '<i class="fa fa-heartbeat"></i> 检查系统状态' +
                '</button>' +
            '</div>' +
            '<p class="mt-2">请检查系统环境并重试，或联系系统管理员。</p>' +
        '</div>';
    
    if (resultContent) {
        resultContent.innerHTML = content;
        resultContainer.style.display = 'block';
    }
}

/**
 * 获取代码类型的显示名称
 * @param {string} type - 代码类型
 * @returns {string} 显示名称
 */
function getTypeDisplayName(type) {
    var names = {
        'java': 'Java',
        'go': 'Go',
        'python': 'Python',
        'restful': 'RESTful API',
        'all': '全部'
    };
    return names[type] || type;
}

/**
 * 查找最近的父元素
 * @param {HTMLElement} element - 起始元素
 * @param {string} selector - CSS选择器
 * @returns {HTMLElement} 匹配的父元素
 */
function findClosest(element, selector) {
    while (element && element !== document) {
        if (element.matches && element.matches(selector)) {
            return element;
        }
        element = element.parentElement;
    }
    return null;
}

/**
 * 格式化文件大小
 * @param {number} bytes - 字节数
 * @returns {string} 格式化后的大小
 */
function formatFileSize(bytes) {
    if (bytes === 0) return '0 Bytes';
    var k = 1024;
    var sizes = ['Bytes', 'KB', 'MB', 'GB'];
    var i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
}

/**
 * 下载生成的代码
 * @param {string} type - 代码类型
 */
function downloadCode(type) {
    // 这里可以实现下载功能
    // 例如创建一个ZIP文件包含所有生成的代码
    addLog('准备下载' + getTypeDisplayName(type) + '代码...');
    // 实际实现需要后端支持
}
