/**
 * 通用工具函数库
 * 提供通用的消息显示、DOM操作等功能
 */

/**
 * 显示Toast消息（在工作区顶部显示）
 * @param {string} message - 消息内容
 * @param {string} type - 消息类型: 'success'（绿色）, 'error'（红色）, 'warning'（黄色）, 'info'（蓝色）
 * @param {number} duration - 显示时长（毫秒），默认3000
 */
function showToast(message, type = 'success', duration = 3000) {
    // Create toast container if it doesn't exist
    let toastContainer = document.querySelector('.global-toast-container');
    if (!toastContainer) {
        toastContainer = document.createElement('div');
        toastContainer.className = 'global-toast-container';
        toastContainer.style.cssText = `
            position: fixed;
            top: 140px;
            left: 50%;
            transform: translateX(-50%);
            z-index: 99999;
            display: flex;
            flex-direction: column;
            align-items: center;
            pointer-events: none;
            background: transparent;
        `;
        // Add to document body instead of workspace content
        document.body.appendChild(toastContainer);
    }

    // Create toast element
    const toast = document.createElement('div');
    toast.className = `toast toast-${type}`;
    toast.textContent = message;
    
    // Style toast with correct colors
    let backgroundColor;
    switch (type) {
        case 'success':
            backgroundColor = '#52c41a'; // 绿色
            break;
        case 'error':
            backgroundColor = '#ff4d4f'; // 红色
            break;
        case 'warning':
            backgroundColor = '#faad14'; // 黄色
            break;
        case 'info':
        default:
            backgroundColor = '#3b82f6'; // 蓝色
    }
    
    toast.style.cssText = `
        background: ${backgroundColor};
        color: white;
        padding: 12px 24px;
        margin-bottom: 10px;
        border-radius: 4px;
        box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
        font-size: 14px;
        text-align: center;
        animation: slideInDown 0.3s ease-out;
        pointer-events: auto;
    `;

    // Add toast to container
    toastContainer.appendChild(toast);
    
    // Add animation keyframes if not already added
    if (!document.querySelector('#toast-animations')) {
        const style = document.createElement('style');
        style.id = 'toast-animations';
        style.textContent = `
            @keyframes slideInDown {
                from {
                    transform: translateY(-20px);
                    opacity: 0;
                }
                to {
                    transform: translateY(0);
                    opacity: 1;
                }
            }
            @keyframes slideOutUp {
                from {
                    transform: translateY(0);
                    opacity: 1;
                }
                to {
                    transform: translateY(-20px);
                    opacity: 0;
                }
            }
        `;
        document.head.appendChild(style);
    }
    
    // Remove after specified duration
    setTimeout(() => {
        toast.style.animation = 'slideOutUp 0.3s ease-out';
        setTimeout(() => {
            if (toast.parentNode) {
                toast.parentNode.removeChild(toast);
            }
            // Remove container if empty
            if (toastContainer && toastContainer.children.length === 0) {
                toastContainer.parentNode.removeChild(toastContainer);
            }
        }, 300);
    }, duration);
}

/**
 * 显示消息提示
 * @param {string} message - 消息内容
 * @param {string} type - 消息类型: 'success', 'error', 'info', 'warning'
 * @param {number} duration - 显示时长（毫秒），默认3000
 */
function showMessage(message, type = 'info', duration = 3000) {
    // 移除已存在的消息
    const existingMessage = document.querySelector('.message');
    if (existingMessage) {
        existingMessage.remove();
    }

    // 创建消息元素
    const messageDiv = document.createElement('div');
    messageDiv.className = `message ${type}`;
    messageDiv.textContent = message;
    
    // 添加到页面
    document.body.appendChild(messageDiv);
    
    // 自动移除
    setTimeout(() => {
        if (messageDiv.parentNode) {
            messageDiv.remove();
        }
    }, duration);
}

/**
 * 显示成功消息
 * @param {string} message - 消息内容
 * @param {number} duration - 显示时长
 */
function showSuccess(message, duration = 3000) {
    showMessage(message, 'success', duration);
}

/**
 * 显示错误消息
 * @param {string} message - 消息内容
 * @param {number} duration - 显示时长
 */
function showError(message, duration = 5000) {
    showMessage(message, 'error', duration);
}

/**
 * 显示信息消息
 * @param {string} message - 消息内容
 * @param {number} duration - 显示时长
 */
function showInfo(message, duration = 3000) {
    showMessage(message, 'info', duration);
}

/**
 * 显示警告消息
 * @param {string} message - 消息内容
 * @param {number} duration - 显示时长
 */
function showWarning(message, duration = 4000) {
    showMessage(message, 'warning', duration);
}

/**
 * 确认对话框
 * @param {string} message - 确认消息
 * @param {string} title - 对话框标题
 * @returns {Promise<boolean>} - 用户选择结果
 */
function confirmDialog(message, title = '确认操作') {
    return new Promise((resolve) => {
        // 创建模态框
        const modalMask = document.createElement('div');
        modalMask.className = 'modal-mask';
        modalMask.style.cssText = `
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: rgba(0, 0, 0, 0.5);
            display: flex;
            align-items: center;
            justify-content: center;
            z-index: 1000;
        `;

        const modal = document.createElement('div');
        modal.className = 'modal';
        modal.style.cssText = `
            background: white;
            border-radius: 8px;
            width: 90%;
            max-width: 400px;
            box-shadow: 0 20px 25px -5px rgba(0, 0, 0, 0.1);
        `;

        modal.innerHTML = `
            <div class="modal-header" style="padding: 16px 20px; border-bottom: 1px solid #e5e7eb; font-weight: 600; color: #1f2937;">
                ${title}
                <button class="modal-close" style="float: right; background: none; border: none; font-size: 18px; cursor: pointer; color: #6b7280;">&times;</button>
            </div>
            <div class="modal-body" style="padding: 20px; color: #374151;">
                ${message}
            </div>
            <div class="modal-footer" style="padding: 16px 20px; border-top: 1px solid #e5e7eb; display: flex; justify-content: flex-end; gap: 12px; background: #f9fafb;">
                <button class="modal-btn cancel-btn" style="padding: 8px 16px; border: 1px solid #d1d5db; border-radius: 4px; background: white; color: #6b7280; cursor: pointer;">取消</button>
                <button class="modal-btn confirm-btn" style="padding: 8px 16px; border: 1px solid #3b82f6; border-radius: 4px; background: #3b82f6; color: white; cursor: pointer;">确认</button>
            </div>
        `;

        modalMask.appendChild(modal);
        document.body.appendChild(modalMask);

        // 事件处理
        const closeModal = (result) => {
            modalMask.remove();
            resolve(result);
        };

        modal.querySelector('.modal-close').addEventListener('click', () => closeModal(false));
        modal.querySelector('.cancel-btn').addEventListener('click', () => closeModal(false));
        modal.querySelector('.confirm-btn').addEventListener('click', () => closeModal(true));
        // 移除点击遮罩关闭功能，避免误操作
        // modalMask.addEventListener('click', (e) => {
        //     if (e.target === modalMask) {
        //         closeModal(false);
        //     }
        // });
    });
}

/**
 * 格式化日期时间
 * @param {Date|string|number} date - 日期
 * @param {string} format - 格式化字符串
 * @returns {string} - 格式化后的日期
 */
function formatDate(date, format = 'YYYY-MM-DD HH:mm:ss') {
    const d = new Date(date);
    const year = d.getFullYear();
    const month = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    const hours = String(d.getHours()).padStart(2, '0');
    const minutes = String(d.getMinutes()).padStart(2, '0');
    const seconds = String(d.getSeconds()).padStart(2, '0');

    return format
        .replace('YYYY', year)
        .replace('MM', month)
        .replace('DD', day)
        .replace('HH', hours)
        .replace('mm', minutes)
        .replace('ss', seconds);
}

/**
 * 防抖函数
 * @param {Function} func - 要防抖的函数
 * @param {number} wait - 等待时间
 * @returns {Function} - 防抖后的函数
 */
function debounce(func, wait) {
    let timeout;
    return function executedFunction(...args) {
        const later = () => {
            clearTimeout(timeout);
            func(...args);
        };
        clearTimeout(timeout);
        timeout = setTimeout(later, wait);
    };
}

/**
 * 节流函数
 * @param {Function} func - 要节流的函数
 * @param {number} limit - 限制时间
 * @returns {Function} - 节流后的函数
 */
function throttle(func, limit) {
    let inThrottle;
    return function(...args) {
        if (!inThrottle) {
            func.apply(this, args);
            inThrottle = true;
            setTimeout(() => inThrottle = false, limit);
        }
    };
}

/**
 * 深拷贝对象
 * @param {any} obj - 要拷贝的对象
 * @returns {any} - 拷贝后的对象
 */
function deepClone(obj) {
    if (obj === null || typeof obj !== 'object') return obj;
    if (obj instanceof Date) return new Date(obj.getTime());
    if (obj instanceof Array) return obj.map(item => deepClone(item));
    if (typeof obj === 'object') {
        const clonedObj = {};
        for (const key in obj) {
            if (obj.hasOwnProperty(key)) {
                clonedObj[key] = deepClone(obj[key]);
            }
        }
        return clonedObj;
    }
}

/**
 * 生成唯一ID
 * @param {string} prefix - 前缀
 * @returns {string} - 唯一ID
 */
function generateId(prefix = 'id') {
    return `${prefix}_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
}

// 本地PDF生成器 - 无外网依赖
class LocalPDFGenerator {
    constructor() {
        this.content = [];
        this.yPosition = 50;
        this.pageHeight = 842; // A4高度 (点)
        this.pageWidth = 595; // A4宽度 (点)
        this.margin = 50;
        this.fontSize = 12;
        this.lineHeight = 16;
    }

    // 添加文本
    addText(text, fontSize = 12, bold = false) {
        this.content.push({
            type: 'text',
            text: text,
            fontSize: fontSize,
            bold: bold,
            y: this.yPosition
        });
        this.yPosition += this.lineHeight;
        this.checkPageBreak();
    }

    // 添加标题
    addTitle(text) {
        this.addText(text, 18, true);
        this.yPosition += 10;
    }

    // 添加小标题
    addSubtitle(text) {
        this.addText(text, 14, true);
        this.yPosition += 5;
    }

    // 添加表格
    addTable(headers, data) {
        this.content.push({
            type: 'table',
            headers: headers,
            data: data
        });
        this.yPosition += 20 * (data.length + 2); // 估算表格高度
        this.checkPageBreak();
    }

    // 添加图片（通过Canvas捕获）
    async addImage(element, title, description) {
        try {
            // 使用Canvas捕获元素
            const canvas = await this.captureElement(element);
            const imageData = canvas.toDataURL('image/png');
            
            this.content.push({
                type: 'image',
                title: title,
                description: description,
                imageData: imageData,
                width: canvas.width,
                height: canvas.height
            });
            
            this.yPosition += 250; // 估算图片高度
            this.checkPageBreak();
        } catch (error) {
            console.error('捕获图片失败:', error);
            // 如果捕获失败，使用占位符
            this.addImagePlaceholder(title, description);
        }
    }
    
    // 添加图表图片（通过ECharts base64）
    async addChartImage(chartBase64, title, description) {
        try {
            this.addText(title, 12, true);
            this.addText(description, 10);
            
            // 创建图片元素
            const img = new Image();
            img.src = chartBase64;
            
            // 等待图片加载
            await new Promise((resolve, reject) => {
                img.onload = resolve;
                img.onerror = reject;
            });
            
            // 添加到内容数组
            this.content.push({
                type: 'image',
                imageData: chartBase64,
                title: title,
                description: description,
                width: img.width,
                height: img.height
            });
            
            this.addText(' ', 8); // 添加间距
            
        } catch (error) {
            console.error('添加图表图片失败:', error);
            // 如果添加失败，使用占位符
            this.addImagePlaceholder(title, description);
        }
    }
    
    // 捕获表格内容
    async captureTable(shadowRoot) {
        const tableElement = shadowRoot.querySelector('.data-table');
        if (!tableElement) return null;
        
        try {
            // 创建Canvas
            const canvas = document.createElement('canvas');
            const ctx = canvas.getContext('2d');
            
            // 获取表格尺寸
            const rect = tableElement.getBoundingClientRect();
            canvas.width = rect.width;
            canvas.height = rect.height;
            
            // 简单的表格绘制
            ctx.fillStyle = '#ffffff';
            ctx.fillRect(0, 0, canvas.width, canvas.height);
            
            // 绘制表格边框
            ctx.strokeStyle = '#ddd';
            ctx.lineWidth = 1;
            
            // 获取表格数据
            const rows = tableElement.querySelectorAll('tr');
            let y = 0;
            
            rows.forEach((row, index) => {
                const cells = row.querySelectorAll('th, td');
                let x = 0;
                const cellHeight = 30;
                
                cells.forEach((cell, cellIndex) => {
                    const cellWidth = rect.width / cells.length;
                    
                    // 绘制单元格边框
                    ctx.strokeRect(x, y, cellWidth, cellHeight);
                    
                    // 绘制文本
                    ctx.fillStyle = cell.tagName === 'TH' ? '#333' : '#666';
                    ctx.font = cell.tagName === 'TH' ? 'bold 12px Arial' : '11px Arial';
                    ctx.textAlign = 'center';
                    ctx.textBaseline = 'middle';
                    ctx.fillText(cell.textContent, x + cellWidth / 2, y + cellHeight / 2);
                    
                    x += cellWidth;
                });
                
                y += cellHeight;
            });
            
            return canvas;
        } catch (error) {
            console.error('捕获表格失败:', error);
            return null;
        }
    }
    
    // 捕获元素为Canvas
    async captureElement(element, chart = null) {
        return new Promise((resolve, reject) => {
            // 创建Canvas
            const canvas = document.createElement('canvas');
            const ctx = canvas.getContext('2d');
            
            // 获取元素尺寸
            const rect = element.getBoundingClientRect();
            canvas.width = rect.width;
            canvas.height = rect.height;
            
            // 使用html2canvas的替代方案 - 简单的截图实现
            try {
                // 对于ECharts图表，可以直接获取图表的图片数据
                if (element.id === 'analysisChart' && chart) {
                    const chartImage = chart.getDataURL({
                        type: 'png',
                        pixelRatio: 2,
                        backgroundColor: '#fff'
                    });
                    
                    const img = new Image();
                    img.onload = () => {
                        ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
                        resolve(canvas);
                    };
                    img.onerror = () => reject(new Error('图表图片加载失败'));
                    img.src = chartImage;
                } else {
                    // 对于其他元素，使用简单的绘制方法
                    ctx.fillStyle = '#f5f5f5';
                    ctx.fillRect(0, 0, canvas.width, canvas.height);
                    ctx.fillStyle = '#666';
                    ctx.font = '14px Arial';
                    ctx.textAlign = 'center';
                    ctx.fillText('截图内容', canvas.width / 2, canvas.height / 2);
                    resolve(canvas);
                }
            } catch (error) {
                reject(error);
            }
        });
    }
    
    // 添加图片占位符
    addImagePlaceholder(title, description) {
        this.addText(title, 12, true);
        this.addText(`[图片: ${description}]`, 10);
        this.addText(`尺寸: 400x300 像素`, 9);
        this.yPosition += 20;
    }

    // 添加分隔线
    addSeparator() {
        this.addText(''.padEnd(50, '-'), 10);
        this.yPosition += 5;
    }

    // 检查是否需要换页
    checkPageBreak() {
        if (this.yPosition > this.pageHeight - this.margin) {
            this.yPosition = this.margin;
            this.content.push({ type: 'newPage' });
        }
    }

    // 添加页眉
    addHeader() {
        this.content.push({
            type: 'header',
            text: '清华大学大数据系统软件国家工程研究中心 - 实验报告',
            y: 30
        });
    }

    // 添加页脚
    addFooter(pageNumber) {
        this.content.push({
            type: 'footer',
            text: `第 ${pageNumber} 页`,
            y: this.pageHeight - 30
        });
    }

    // 添加水印
    addWatermark() {
        console.log('addWatermark 被调用了！');
        
        // 从配置文件读取水印设置
        const watermarkConfig = window.AppConfig && window.AppConfig.watermark ? window.AppConfig.watermark : {
            text: '清华大学大数据系统软件国家工程研究中心',
            opacity: 0.1
        };
        
        this.content.push({
            type: 'watermark',
            text: watermarkConfig.text,
            opacity: watermarkConfig.opacity,
            fontSize: watermarkConfig.fontSize || 48,
            color: watermarkConfig.color || '#999',
            rotation: watermarkConfig.rotation || -45,
            enable: watermarkConfig.enable !== false
        });
        console.log('水印已添加到content数组，当前content长度:', this.content.length);
    }

    // 生成HTML内容用于打印
    generateHTML() {
        let html = '<!DOCTYPE HTML>' +
        '<html>' +
        '<head>' +
        '<meta http-equiv="Content-Type" content="text/html; charset=UTF-8"></meta>' +
        '<meta charset="UTF-8">' +
        '<title>实验报告</title>' +
        '<style type="text/css">' +
        'body { font-family: SimSun, Microsoft YaHei, SimHei, Arial, sans-serif; font-size: ' + this.fontSize + 'pt; line-height: 1.5; margin: 0; padding: 0; position: relative; min-height: 100vh; }' +
        '.header { text-align: center; font-size: 14pt; font-weight: bold; margin-bottom: 30px; border-bottom: 2px solid #333; padding-bottom: 10px; }' +
        '.footer { text-align: center; font-size: 10pt; margin-top: 30px; border-top: 1px solid #333; padding-top: 10px; }' +
        '.title { text-align: center; font-size: 18pt; font-weight: bold; margin: 20px 0; }' +
        '.subtitle { font-size: 14pt; font-weight: bold; margin: 15px 0 10px 0; }' +
        '.content { padding: 20px; }' +
        '.section { margin: 20px 0; }' +
        '.text { margin: 10px 0; text-align: justify; }' +
        '.table { width: 100%; border-collapse: collapse; margin: 10px 0; table-layout: fixed; }' +
        '.table th, .table td { border: 1px solid #ddd; padding: 8px; text-align: left; word-wrap: break-word; min-width: 0; }' +
        '.table th { background-color: #f2f2f2; font-weight: bold; }' +
        '.image-title { font-weight: bold; margin: 10px 0 5px 0; }' +
        '.report-image { max-width: 100%; height: auto; }' +
        '.separator { height: 1px; background-color: #ccc; margin: 20px 0; }' +
        '@page { size: A4; margin: 2cm; }' +
        '@media print { body { font-family: SimSun, Microsoft YaHei, SimHei, Arial, sans-serif !important; } }' +
        '</style>' +
        '</head>' +
        '<body>' +
        '<div class="header">实验报告</div>' +
        '<div class="content">';

        // 添加内容
        console.log('开始生成HTML，content数组内容:', this.content);
        this.content.forEach(item => {
            console.log('处理item:', item.type, item);
            switch(item.type) {
                case 'text':
                    if (item.bold) {
                        html += '<div style="font-weight: bold; font-size: ' + item.fontSize + 'pt; margin: 5px 0; font-family: SimSun, Microsoft YaHei, SimHei, Arial, sans-serif;">' + item.text + '</div>';
                    } else {
                        html += '<div style="font-size: ' + item.fontSize + 'pt; margin: 5px 0; font-family: SimSun, Microsoft YaHei, SimHei, Arial, sans-serif;">' + item.text + '</div>';
                    }
                    break;
                case 'title':
                    html += '<div class="title" style="font-family: SimSun, Microsoft YaHei, SimHei, Arial, sans-serif;">' + item.text + '</div>';
                    break;
                case 'subtitle':
                    html += '<div class="subtitle" style="font-family: SimSun, Microsoft YaHei, SimHei, Arial, sans-serif;">' + item.text + '</div>';
                    break;
                case 'table':
                    // 生成HTML表格
                    html += '<table class="table">';
                    // 表头
                    html += '<tr>';
                    item.headers.forEach(header => {
                        html += '<th style="font-family: SimSun, Microsoft YaHei, SimHei, Arial, sans-serif;">' + header + '</th>';
                    });
                    html += '</tr>';
                    // 数据行
                    item.data.forEach(row => {
                        html += '<tr>';
                        row.forEach(cell => {
                            html += '<td style="font-family: SimSun, Microsoft YaHei, SimHei, Arial, sans-serif;">' + cell + '</td>';
                        });
                        html += '</tr>';
                    });
                    html += '</table>';
                    break;
                case 'image':
                    // 生成图片
                    html += '<div class="image-title" style="font-family: SimSun, Microsoft YaHei, SimHei, Arial, sans-serif;">' + item.title + '</div>';
                    html += '<img src="' + item.imageData + '" alt="' + item.description + '" class="report-image"></img>';
                    html += '<div style="text-align: center; font-size: 10pt; color: #666; margin: 5px 0; font-family: SimSun, Microsoft YaHei, SimHei, Arial, sans-serif;">' + item.description + '</div>';
                    break;
                case 'watermark':
                    // 生成水印 - 使用配置文件参数
                    console.log('正在生成水印，文本:', item.text);
                    
                    // 检查是否启用水印
                    if (item.enable === false) {
                        console.log('水印已禁用，跳过生成');
                        break;
                    }
                    
                    const watermarkStyle = `
                        position: absolute; 
                        top: 50%; 
                        left: 50%; 
                        transform: translate(-50%, -50%) rotate(${item.rotation || -45}deg); 
                        font-size: ${item.fontSize || 48}px; 
                        color: ${item.color || '#999'}; 
                        opacity: ${item.opacity || 0.15}; 
                        z-index: 999; 
                        white-space: nowrap; 
                        font-family: SimSun, Microsoft YaHei, SimHei, Arial, sans-serif; 
                        pointer-events: none; 
                        user-select: none; 
                        font-weight: bold;
                    `;
                    
                    html += `<div style="position: relative; width: 100%; height: 400px; margin: 20px 0;"><div style="${watermarkStyle}">${item.text}</div></div>`;
                    console.log('水印HTML已添加');
                    break;
                case 'separator':
                    html += '<div class="separator"></div>';
                    break;
                case 'newPage':
                    html += '<div style="page-break-before: always;"></div>';
                    break;
            }
        });

        html += '</div>' +
        '<div class="footer" style="font-family: SimSun, Microsoft YaHei, SimHei, Arial, sans-serif;">实验报告生成时间: ' + new Date().toLocaleString() + '</div>' +
        '</body>' +
        '</html>';

        return html;
    }

    // 生成并下载PDF（通过打印对话框）
    generateAndDownload(title = '实验报告') {
        // 生成HTML内容
        const htmlContent = this.generateHTML();
        
        // 创建新窗口
        const printWindow = window.open('', '_blank');
        printWindow.document.write(htmlContent);
        printWindow.document.close();
        
        // 等待内容加载完成后触发打印
        printWindow.onload = () => {
            // 触发打印对话框，用户可以选择"保存为PDF"
            printWindow.print();
            
            // 打印完成后关闭窗口
            printWindow.onafterprint = () => {
                printWindow.close();
            };
            
            // 备用关闭方案（如果用户取消打印）
            setTimeout(() => {
                if (!printWindow.closed) {
                    printWindow.close();
                }
            }, 1000);
        };
    }
    
    // 生成PDF Blob（用于预览和下载）
    generatePDFBlob() {
        const htmlContent = this.generateHTML();
        
        // 创建一个隐藏的iframe来生成PDF
        const iframe = document.createElement('iframe');
        iframe.style.display = 'none';
        document.body.appendChild(iframe);
        
        const iframeDoc = iframe.contentDocument;
        iframeDoc.open();
        iframeDoc.write(htmlContent);
        iframeDoc.close();
        
        // 等待内容加载完成
        return new Promise((resolve) => {
            iframe.onload = () => {
                // 使用浏览器的打印功能生成PDF
                // 注意：这里我们创建一个包含HTML内容的Blob
                // 实际的PDF转换需要服务器端支持或使用专门的库
                const htmlBlob = new Blob([htmlContent], { type: 'text/html;charset=utf-8' });
                
                // 清理iframe
                document.body.removeChild(iframe);
                
                // 返回HTML Blob，浏览器会将其识别为可打印的内容
                resolve(htmlBlob);
            };
        });
    }
}

// 导出到全局对象
window.CommonUtils = {
    showMessage,
    showToast,
    showSuccess,
    showError,
    showInfo,
    showWarning,
    confirmDialog,
    formatDate,
    debounce,
    throttle,
    deepClone,
    generateId,
    LocalPDFGenerator
};
