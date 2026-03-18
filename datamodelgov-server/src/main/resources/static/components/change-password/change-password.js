/**
 * 修改密码组件
 * 完全复制 register-embedded 模式
 */
class ChangePassword extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });
        this.currentUser = null;
    }

    async connectedCallback() {
        await this.loadResources();
        this.render();
        this.bindEvents();
        this.hide(); // 默认隐藏
        
        // 绑定用户头像点击事件
        setTimeout(() => {
            const userAvatar = document.querySelector('.user-avatar-icon');
            if (userAvatar) {
                userAvatar.addEventListener('click', () => {
                    this.show();
                });
            }

            // 绑定菜单项点击事件
            const changePasswordMenuItem = document.getElementById('changePasswordMenuItem');
            if (changePasswordMenuItem) {
                changePasswordMenuItem.addEventListener('click', () => {
                    this.show();
                });
            }
        }, 200);
    }

    async loadResources() {
        // 加载CSS
        try {
            const cssLink = document.createElement('link');
            cssLink.rel = 'stylesheet';
            cssLink.href = './components/change-password/change-password.css';
            this.shadowRoot.appendChild(cssLink);
        } catch (error) {
            console.error('Failed to load CSS:', error);
        }

        // 加载HTML模板
        try {
            const response = await fetch('./components/change-password/change-password.html');
            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }
            const html = await response.text();
            this.shadowRoot.innerHTML += html;
            console.log('Change password HTML template loaded successfully');
        } catch (error) {
            console.error('Failed to load HTML template:', error);
        }
    }

    render() {
        // HTML已通过loadResources加载
        this.loadCurrentUser();
    }

    bindEvents() {
        // 关闭按钮
        const closeBtn = this.shadowRoot.getElementById('closeChangePasswordModal');
        if (closeBtn) {
            closeBtn.addEventListener('click', (e) => {
                e.stopPropagation();
                this.hide();
            });
        }

        // 取消按钮
        const cancelBtn = this.shadowRoot.getElementById('cancelChangePassword');
        if (cancelBtn) {
            cancelBtn.addEventListener('click', (e) => {
                e.stopPropagation();
                this.hide();
            });
        }

        // 确认修改按钮
        const confirmBtn = this.shadowRoot.getElementById('confirmChangePassword');
        if (confirmBtn) {
            confirmBtn.addEventListener('click', () => {
                this.changePassword();
            });
        }

        // 移除点击遮罩关闭功能，避免误操作
        // const modalMask = this.shadowRoot.getElementById('changePasswordModal');
        // if (modalMask) {
        //     modalMask.addEventListener('click', (e) => {
        //         if (e.target === modalMask) {
        //             this.hide();
        //         }
        //     });
        // }
    }

    async loadCurrentUser() {
        try {
            // 使用和右上角相同的方式获取用户名
            const username = window.AppConfig.getUsername();
            
            if (username) {
                this.currentUser = { username: username };
                const currentUsername = this.shadowRoot.getElementById('currentUsername');
                if (currentUsername) {
                    currentUsername.value = username;
                }
            }
        } catch (error) {
            console.error('获取当前用户信息失败:', error);
        }
    }

    show() {
        // 完全复制 register-embedded 的 show 方法
        this.removeAttribute('hidden');
        this.style.display = 'flex';
        this.loadCurrentUser();
    }

    hide() {
        // 完全复制 register-embedded 的 hide 方法
        this.setAttribute('hidden', '');
        this.style.display = 'none';
        this.resetForm();
    }

    resetForm() {
        const form = this.shadowRoot.getElementById('changePasswordForm');
        if (form) {
            form.reset();
        }
        const currentUsername = this.shadowRoot.getElementById('currentUsername');
        if (currentUsername && this.currentUser) {
            currentUsername.value = this.currentUser.username;
        }
        // 清除所有错误提示
        this.clearAllErrors();
    }

    clearAllErrors() {
        const errorElements = this.shadowRoot.querySelectorAll('.error-message');
        const formGroups = this.shadowRoot.querySelectorAll('.form-group');
        
        errorElements.forEach(error => {
            error.textContent = '';
            error.classList.remove('show');
        });
        
        formGroups.forEach(group => {
            group.classList.remove('has-error');
        });
    }

    showError(fieldId, message) {
        const errorElement = this.shadowRoot.getElementById(fieldId + 'Error');
        const inputElement = this.shadowRoot.getElementById(fieldId);
        const formGroup = inputElement?.closest('.form-group');
        
        if (errorElement) {
            errorElement.textContent = message;
            errorElement.classList.add('show');
        }
        
        if (formGroup) {
            formGroup.classList.add('has-error');
        }
    }

    async changePassword() {
        console.log('changePassword 方法被调用');
        
        // 清除之前的错误提示
        this.clearAllErrors();
        
        const form = this.shadowRoot.getElementById('changePasswordForm');
        if (!form || !form.checkValidity()) {
            console.log('表单验证失败');
            if (form) form.reportValidity();
            return;
        }

        const oldPassword = this.shadowRoot.getElementById('oldPassword')?.value;
        const newPassword = this.shadowRoot.getElementById('newPassword')?.value;
        const confirmPassword = this.shadowRoot.getElementById('confirmPassword')?.value;


        // 验证新密码
        if (newPassword !== confirmPassword) {
            console.log('密码不一致，显示错误提示');
            this.showError('confirmPassword', '两次输入的新密码不一致');
            return;  // 验证失败不关闭弹窗，让用户重新输入
        }

        if (newPassword.length < 6) {
            console.log('密码长度不足，显示错误提示');
            this.showError('newPassword', '新密码长度至少为6位');
            return;  // 验证失败不关闭弹窗，让用户重新输入
        }

        if (!this.currentUser || !this.currentUser.username) {
            console.log('用户信息缺失，显示错误提示');
            this.showError('currentUsername', '用户信息缺失，请重新登录');
            return;  // 验证失败不关闭弹窗
        }

        console.log('密码验证通过，准备提交');

        try {
            // 使用正确的API端点：/api/user/change-password
            const result = await window.AppConfig.post('userManagement', 'change-password', {
                username: this.currentUser.username,
                oldPassword: oldPassword,
                newPassword: newPassword
            });

            if (result.success) {
                this.showMessage('密码修改成功', 'success');
                this.hide();
            } else {
                this.showMessage('密码修改失败: ' + result.message, 'error');
            }
            
            // 无论成功失败都关闭弹窗 - 完全复制 register-embedded 模式
            this.hide();
        } catch (error) {
            console.error('密码修改失败:', error);
            this.showMessage('密码修改失败', 'error');
            // 异常情况下也要关闭弹窗 - 完全复制 register-embedded 模式
            this.hide();
        }
    }

    showMessage(message, type = 'info') {
        console.log('showMessage 被调用:', message, type);
        // 完全复制 register-embedded 的 showMessage 方法
        if (window.CommonUtils && window.CommonUtils.showToast) {
            console.log('调用 window.CommonUtils.showToast');
            window.CommonUtils.showToast(message, type);
        } else {
            console.warn('CommonUtils.showToast not available');
        }
    }
}

// 注册自定义元素
customElements.define('change-password', ChangePassword);
