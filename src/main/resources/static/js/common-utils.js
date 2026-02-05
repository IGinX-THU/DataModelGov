/**
 * 通用工具函数库
 * 提供通用的消息显示、DOM操作等功能
 */

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
        modalMask.addEventListener('click', (e) => {
            if (e.target === modalMask) {
                closeModal(false);
            }
        });
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

// 导出到全局对象
window.CommonUtils = {
    showMessage,
    showSuccess,
    showError,
    showInfo,
    showWarning,
    confirmDialog,
    formatDate,
    debounce,
    throttle,
    deepClone,
    generateId
};
