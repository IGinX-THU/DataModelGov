/**
 * Desktop Shell Controller
 * Manages the desktop application shell enhancements
 * Does NOT replace existing functionality
 */

class DesktopShell {
    constructor() {
        this.init();
    }

    init() {
        this.updateUserName();
        this.updateConnectionStatus();
        this.bindEvents();
    }

    bindEvents() {
        // Monitor online/offline status
        window.addEventListener('online', () => this.updateConnectionStatus());
        window.addEventListener('offline', () => this.updateConnectionStatus());
        
        // Bind left sidebar tabs
        document.querySelectorAll('.left-sidebar-tab').forEach(tab => {
            tab.addEventListener('click', () => {
                const tabName = tab.dataset.tab;
                this.switchLeftSidebarTab(tabName);
                
                // Expand sidebar when clicking tabs in collapsed state
                const leftSidebar = document.querySelector('.left-sidebar');
                if (leftSidebar && leftSidebar.classList.contains('collapsed')) {
                    leftSidebar.classList.remove('collapsed');
                }
            });
        });
        
        // Bind right sidebar tabs
        document.querySelectorAll('.right-sidebar-tab').forEach(tab => {
            tab.addEventListener('click', () => {
                const tabName = tab.dataset.tab;
                this.switchRightSidebarTab(tabName);
                
                // Expand sidebar when clicking tabs in collapsed state
                const rightSidebar = document.querySelector('.right-sidebar');
                if (rightSidebar && rightSidebar.classList.contains('collapsed')) {
                    rightSidebar.classList.remove('collapsed');
                }
            });
        });
        
        // Bind bottom sidebar icons
        document.querySelectorAll('.bottom-sidebar-icon').forEach(icon => {
            icon.addEventListener('click', () => {
                const target = icon.dataset.target;
                const panel = icon.dataset.panel;
                const sidebar = document.querySelector(`.${target}-sidebar`);

                // If clicking the already active icon, collapse the sidebar
                if (icon.classList.contains('active') && sidebar && !sidebar.classList.contains('collapsed')) {
                    sidebar.classList.add('collapsed');
                    return;
                }

                this.switchSidebarPanel(target, panel);

                // Expand sidebar when clicking icons in collapsed state
                if (sidebar && sidebar.classList.contains('collapsed')) {
                    sidebar.classList.remove('collapsed');
                }
            });
        });
        
        // Bind window menu items
        const menuToggleLeftSidebar = document.getElementById('menu-toggle-left-sidebar');
        if (menuToggleLeftSidebar) {
            menuToggleLeftSidebar.addEventListener('click', () => this.toggleLeftSidebar());
        }

        const menuToggleRightSidebar = document.getElementById('menu-toggle-right-sidebar');
        if (menuToggleRightSidebar) {
            menuToggleRightSidebar.addEventListener('click', () => this.toggleRightSidebar());
        }

        // Initialize window menu checkmark states
        this.initWindowMenuStates();

        // Bind home menu to toggle function bar
        const menuHome = document.getElementById('menu-home');
        if (menuHome) {
            menuHome.addEventListener('click', () => this.toggleFuncBar());
        }

        // Add hover to auto-expand dropdown menus (C-end desktop experience) - exclude home menu
        document.querySelectorAll('.tab.dropdown:not(#menu-home)').forEach(tab => {
            tab.addEventListener('mouseenter', () => {
                tab.classList.add('active');
                const dropdownMenu = tab.querySelector('.dropdown-menu');
                if (dropdownMenu) {
                    dropdownMenu.style.display = 'block';
                }
            });

            tab.addEventListener('mouseleave', () => {
                tab.classList.remove('active');
                const dropdownMenu = tab.querySelector('.dropdown-menu');
                if (dropdownMenu) {
                    dropdownMenu.style.display = 'none';
                }
            });
        });

        // Bind ribbon buttons to import/export wizards
        this.bindRibbonButtons();
    }

    bindRibbonButtons() {
        // Data import/export
        const btnDataImport = document.getElementById('btn-data-import');
        if (btnDataImport) {
            btnDataImport.addEventListener('click', () => {
                if (typeof window.showProjectImportWizard === 'function') {
                    window.showProjectImportWizard('data');
                }
            });
        }

        const btnDataExport = document.getElementById('btn-data-export');
        if (btnDataExport) {
            btnDataExport.addEventListener('click', () => {
                if (typeof window.showProjectExportWizard === 'function') {
                    window.showProjectExportWizard('data');
                }
            });
        }

        // Model import/export
        const btnModelImport = document.getElementById('btn-model-import');
        if (btnModelImport) {
            btnModelImport.addEventListener('click', () => {
                if (typeof window.showProjectImportWizard === 'function') {
                    window.showProjectImportWizard('model');
                }
            });
        }

        const btnModelExport = document.getElementById('btn-model-export');
        if (btnModelExport) {
            btnModelExport.addEventListener('click', () => {
                if (typeof window.showProjectExportWizard === 'function') {
                    window.showProjectExportWizard('model');
                }
            });
        }

        // Algorithm import/export
        const btnAlgorithmImport = document.getElementById('btn-algorithm-import');
        if (btnAlgorithmImport) {
            btnAlgorithmImport.addEventListener('click', () => {
                if (typeof window.showProjectImportWizard === 'function') {
                    window.showProjectImportWizard('algorithm');
                }
            });
        }

        const btnAlgorithmExport = document.getElementById('btn-algorithm-export');
        if (btnAlgorithmExport) {
            btnAlgorithmExport.addEventListener('click', () => {
                if (typeof window.showProjectExportWizard === 'function') {
                    window.showProjectExportWizard('algorithm');
                }
            });
        }

        // Simulation import/export
        const btnSimulationImport = document.getElementById('btn-simulation-import');
        if (btnSimulationImport) {
            btnSimulationImport.addEventListener('click', () => {
                if (typeof window.showProjectImportWizard === 'function') {
                    window.showProjectImportWizard('simulation');
                }
            });
        }

        const btnSimulationExport = document.getElementById('btn-simulation-export');
        if (btnSimulationExport) {
            btnSimulationExport.addEventListener('click', () => {
                if (typeof window.showProjectExportWizard === 'function') {
                    window.showProjectExportWizard('simulation');
                }
            });
        }
    }

    updateUserName() {
        // Wait for main-menu-permission.js to set the username
        setTimeout(() => {
            const usernameEl = document.getElementById('username');
            const desktopUsernameEl = document.getElementById('desktop-username');
            
            if (usernameEl && desktopUsernameEl) {
                desktopUsernameEl.textContent = usernameEl.textContent;
            }
        }, 100);
    }

    updateConnectionStatus() {
        const statusEl = document.getElementById('connection-status');
        const indicator = document.querySelector('.status-indicator');
        
        if (statusEl && indicator) {
            if (navigator.onLine) {
                statusEl.textContent = '在线';
                indicator.classList.remove('offline');
                indicator.classList.add('online');
            } else {
                statusEl.textContent = '离线';
                indicator.classList.remove('online');
                indicator.classList.add('offline');
            }
        }
    }

    toggleSidebar() {
        const leftSidebar = document.querySelector('.left-sidebar');
        const rightSidebar = document.querySelector('.right-sidebar');
        
        if (leftSidebar) {
            leftSidebar.classList.toggle('collapsed');
        }
        if (rightSidebar) {
            rightSidebar.classList.toggle('collapsed');
        }
    }

    initWindowMenuStates() {
        // Initialize left sidebar menu state
        const leftSidebar = document.querySelector('.left-sidebar');
        const menuToggleLeftSidebar = document.getElementById('menu-toggle-left-sidebar');
        if (leftSidebar && menuToggleLeftSidebar) {
            if (!leftSidebar.classList.contains('collapsed')) {
                menuToggleLeftSidebar.classList.add('active');
            } else {
                menuToggleLeftSidebar.classList.remove('active');
            }
        }

        // Initialize right sidebar menu state
        const rightSidebar = document.querySelector('.right-sidebar');
        const menuToggleRightSidebar = document.getElementById('menu-toggle-right-sidebar');
        if (rightSidebar && menuToggleRightSidebar) {
            if (!rightSidebar.classList.contains('collapsed')) {
                menuToggleRightSidebar.classList.add('active');
            } else {
                menuToggleRightSidebar.classList.remove('active');
            }
        }
    }

    toggleLeftSidebar() {
        const leftSidebar = document.querySelector('.left-sidebar');
        if (leftSidebar) {
            leftSidebar.classList.toggle('collapsed');
            // 更新窗口菜单选中状态
            const menuToggleLeftSidebar = document.getElementById('menu-toggle-left-sidebar');
            if (menuToggleLeftSidebar) {
                menuToggleLeftSidebar.classList.toggle('active');
            }
        }
    }

    toggleRightSidebar() {
        const rightSidebar = document.querySelector('.right-sidebar');
        if (rightSidebar) {
            rightSidebar.classList.toggle('collapsed');
            // 更新窗口菜单选中状态
            const menuToggleRightSidebar = document.getElementById('menu-toggle-right-sidebar');
            if (menuToggleRightSidebar) {
                menuToggleRightSidebar.classList.toggle('active');
            }
        }
    }

    toggleFuncBar() {
        const funcTabContainer = document.querySelector('.func-tab-container');
        const menuHome = document.getElementById('menu-home');
        if (funcTabContainer) {
            const isCollapsed = funcTabContainer.style.display === 'none';
            funcTabContainer.style.display = isCollapsed ? 'flex' : 'none';

            // Toggle home menu active state (active when expanded, inactive when collapsed)
            if (menuHome) {
                if (isCollapsed) {
                    menuHome.classList.add('active');
                } else {
                    menuHome.classList.remove('active');
                }
            }
        }
    }

    switchLeftSidebarTab(tabName) {
        // Update tab active state
        document.querySelectorAll('.left-sidebar-tab').forEach(tab => {
            tab.classList.remove('active');
            if (tab.dataset.tab === tabName) {
                tab.classList.add('active');
            }
        });
        
        // Update panel visibility
        document.querySelectorAll('.left-sidebar-panel').forEach(panel => {
            panel.classList.remove('active');
            if (panel.dataset.panel === tabName) {
                panel.classList.add('active');
            }
        });
        
        // Update bottom toggle buttons
        this.updateBottomToggleButtons('left', tabName);
        
        // Don't auto-expand when clicking tabs - they're always visible
    }

    switchRightSidebarTab(tabName) {
        // Update tab active state
        document.querySelectorAll('.right-sidebar-tab').forEach(tab => {
            tab.classList.remove('active');
            if (tab.dataset.tab === tabName) {
                tab.classList.add('active');
            }
        });
        
        // Update panel visibility
        document.querySelectorAll('.right-sidebar-panel').forEach(panel => {
            panel.classList.remove('active');
            if (panel.dataset.panel === tabName) {
                panel.classList.add('active');
            }
        });
        
        // Update bottom toggle buttons
        this.updateBottomToggleButtons('right', tabName);
        
        // Don't auto-expand when clicking tabs - they're always visible
    }

    switchSidebarPanel(target, panel) {
        if (target === 'left') {
            this.switchLeftSidebarTab(panel);
        } else if (target === 'right') {
            this.switchRightSidebarTab(panel);
        }
    }

    updateBottomToggleButtons(target, panel) {
        document.querySelectorAll(`.bottom-sidebar-icon[data-target="${target}"]`).forEach(icon => {
            icon.classList.remove('active');
            if (icon.dataset.panel === panel) {
                icon.classList.add('active');
            }
        });
    }
}

// Initialize desktop shell when DOM is ready
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => {
        window.desktopShell = new DesktopShell();
    });
} else {
    window.desktopShell = new DesktopShell();
}
