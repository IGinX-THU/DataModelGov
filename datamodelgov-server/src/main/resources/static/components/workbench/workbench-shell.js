/**
 * <workbench-shell> 公共壳:顶栏(应用名+项目身份+切换项目)+ 左侧业务导航 + 主区 + 底部状态栏。
 * 用法:document.getElementById('workbenchShell').show({ workbench: 'modeling', project: {...} })
 */
(function () {
    const WB = () => window.Workbench;

    class WorkbenchShell extends HTMLElement {
        constructor() {
            super();
            this._ctx = null;
            this._config = null;
            this._navKey = null;
        }

        show({ workbench, project } = {}) {
            this._config = WB().WORKBENCHES[workbench];
            if (!this._config) { console.error('未知工作台:', workbench); return; }
            this._ctx = {
                project: project || WB().DEMO.project,
                navigate: (key) => this._navigate(key),
                enterTask: (b) => this._enterTask(b)
            };
            this._render();
            this.style.display = '';
        }

        hide() { this.style.display = 'none'; }

        _render() {
            const cfg = this._config;
            const p = this._ctx.project;
            this.innerHTML = '';
            this.appendChild(WB().h('link', { rel: 'stylesheet', href: './components/workbench/workbench.css?v=r2' }));

            const app = WB().h('div', { class: 'wb-app' });

            // 顶栏
            app.appendChild(WB().h('header', { class: 'wb-topbar' },
                WB().h('div', { class: 'wb-brand' },
                    WB().h('span', { class: 'wb-brand-icon', html: WB().ICONS.logo }),
                    WB().h('span', { class: 'wb-app-name' }, cfg.appName)),
                WB().h('div', { class: 'wb-topbar-divider' }),
                WB().h('div', { class: 'wb-project-name' }, p.name),
                WB().h('div', { class: 'wb-topbar-right' },
                    WB().h('button', { class: 'wb-btn wb-btn-outline', onclick: () => this._switchProject() }, '切换项目'))));

            // 左导航
            const nav = WB().h('nav', { class: 'wb-nav' },
                cfg.nav.map(item => {
                    const n = WB().h('div', {
                        class: 'wb-nav-item' + (item.badge ? ' disabled' : ''),
                        'data-nav': item.key,
                        onclick: () => { if (!item.badge) this._navigate(item.key); }
                    },
                        WB().h('span', { class: 'wb-nav-icon', html: WB().ICONS[item.icon] || WB().ICONS.gauge }),
                        WB().h('span', null, item.label),
                        item.badge ? WB().h('span', { class: 'wb-nav-badge' }, item.badge) : null);
                    return n;
                }));
            app.appendChild(WB().h('div', { class: 'wb-body' },
                WB().h('aside', { class: 'wb-sidebar' },
                    WB().h('div', { class: 'wb-nav-group-label' }, cfg.groupLabel),
                    nav,
                    WB().h('div', { class: 'wb-identity' },
                        WB().h('div', { class: 'wb-identity-label' }, '当前发动机'),
                        WB().h('div', { class: 'wb-identity-name' }, p.engineId || '—'),
                        WB().h('div', { class: 'wb-identity-meta' }, p.engineDesc || ''),
                        WB().h('div', { class: 'wb-identity-meta' }, p.matlab || 'MATLAB R2019b'),
                        WB().h('div', { class: 'wb-identity-meta' }, '本地项目'))),
                WB().h('main', { class: 'wb-main' })));

            // 状态栏
            app.appendChild(WB().h('footer', { class: 'wb-statusbar' },
                WB().h('span', null, '引擎: MATLAB R2019b · 本地运行'),
                WB().h('span', null, '界面结构依据 UI-R131 · 程序绑定以 R06 交付包为准 · 页面示例数据仅作展示')));

            this.appendChild(app);
            this._app = app;
            const first = cfg.nav.find(n => !n.badge);
            if (first) this._navigate(first.key);
        }

        _navigate(key) {
            this._navKey = key;
            this._app.querySelectorAll('.wb-nav-item').forEach(n => {
                n.classList.toggle('active', n.dataset.nav === key);
            });
            const main = this._app.querySelector('.wb-main');
            main.innerHTML = '';
            main.appendChild(WB().renderPage(this._config.key, key, this._ctx));
            main.scrollTop = 0;
        }

        _enterTask(business) {
            if (business && business.id === 'steady') {
                this._navKey = 'tasks';
                this._app.querySelectorAll('.wb-nav-item').forEach(n =>
                    n.classList.toggle('active', n.dataset.nav === 'tasks'));
                const main = this._app.querySelector('.wb-main');
                main.innerHTML = '';
                main.appendChild(window.Workbench.renderSteadyTask({
                    project: this._ctx.project,
                    back: (gotoModels) => {
                        this._navigate(gotoModels ? 'models' : 'tasks');
                    }
                }));
                main.scrollTop = 0;
            }
        }

        _switchProject() {
            this.hide();
            const root = document.getElementById('workbenchRoot');
            if (root && root.show) root.show();
        }
    }

    customElements.define('workbench-shell', WorkbenchShell);
})();
