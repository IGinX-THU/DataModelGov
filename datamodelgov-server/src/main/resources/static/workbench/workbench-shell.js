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
            // 必须携带真实项目id(来自项目列表/新建接口),不再提供任何演示兜底
            if (!project || !project.id) {
                if (window.Workbench && window.Workbench.toast) window.Workbench.toast('项目缺少有效id,无法进入工作台。', 'error');
                return;
            }
            const p = project;
            this._ctx = {
                project: p,
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
            this.appendChild(WB().h('link', { rel: 'stylesheet', href: './workbench/workbench.css?v=r33' }));

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

            // 状态栏:MATLAB日志行滚动(左,同旧版program-run footer-log) + 引擎状态(右) + 固定说明
            app.appendChild(WB().h('footer', { class: 'wb-statusbar' },
                WB().h('span', {
                    class: 'wb-engine-log',
                    style: 'flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap',
                    title: '加载中...'
                }, 'MATLAB 日志加载中...'),
                WB().h('span', { class: 'wb-engine-status', style: 'flex-shrink:0' }, 'MATLAB 引擎状态查询中...'),
                WB().h('span', { style: 'flex-shrink:0' }, '界面结构依据 UI-R131 · 程序绑定以 R06 交付包为准')));
            this._startEngineStatusPolling();

            this.appendChild(app);
            this._app = app;
            const first = cfg.nav.find(n => !n.badge);
            if (first) this._navigate(first.key);
        }

        /** 状态栏轮询(单例):MATLAB日志尾(/engine-log)+引擎状态(/api/program/engine-status)。
         *  仅当工作台内有活动任务/会话时轮询(各页面通过 __WB_ENGINE_POLL_UNTIL__ 心跳续期);
         *  空闲时零请求。 */
        _startEngineStatusPolling() {
            const refresh = async () => {
                if ((window.__WB_ENGINE_POLL_UNTIL__ || 0) < Date.now()) return; // 空闲:不请求
                const logs = document.querySelectorAll('.wb-engine-log');
                const sts = document.querySelectorAll('.wb-engine-status');
                if (logs.length) {
                    try {
                        const resp = await window.AppConfig.request(
                            window.AppConfig.api.baseURL + '/api/engine/engine-log?n=20');
                        const rows = resp && (resp.success || resp.code === 200) && Array.isArray(resp.data)
                            ? resp.data : [];
                        if (rows.length) {
                            const last = rows[rows.length - 1];
                            logs.forEach(el => {
                                el.textContent = last;
                                el.title = rows.join('\n');
                            });
                        }
                    } catch (e) { /* 日志拉取容错 */ }
                }
                if (sts.length) {
                    let msg = 'MATLAB 引擎状态未知';
                    try {
                        const resp = await window.AppConfig.request(
                            window.AppConfig.getApiUrl('program', 'engine-status'));
                        if (resp && resp.code === 200 && resp.data && resp.data.message) msg = resp.data.message;
                    } catch (e) { /* 保持未知 */ }
                    sts.forEach(el => { el.textContent = msg; });
                }
            };
            refresh();
            if (window.__WB_ENGINE_TIMER__) clearInterval(window.__WB_ENGINE_TIMER__);
            window.__WB_ENGINE_TIMER__ = setInterval(() => {
                // 页面隐藏/切后台时不发请求;回到前台下一轮自动恢复
                if (document.hidden) return;
                refresh();
            }, 15000);
        }

        _navigate(key) {
            this._stopActivePage();
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
            this._stopActivePage();
            if (business && (business.id === 'flightSteady' || business.id === 'flightTransient' || business.id === 'evolution')) {
                this._navKey = 'tasks';
                this._app.querySelectorAll('.wb-nav-item').forEach(n =>
                    n.classList.toggle('active', n.dataset.nav === 'tasks'));
                const main = this._app.querySelector('.wb-main');
                main.innerHTML = '';
                const backFn = (gotoModels) => { this._navigate(gotoModels ? 'models' : 'tasks'); };
                if (business.id === 'evolution') {
                    main.appendChild(window.Workbench.renderEvolutionTask({
                        project: this._ctx.project, back: backFn,
                        navigate: (key) => this._navigate(key)
                    }));
                } else {
                    main.appendChild(window.Workbench.renderFlightTask({
                        project: this._ctx.project,
                        flightKind: business.id === 'flightSteady' ? 'flight_steady' : 'flight_transient',
                        back: backFn,
                        navigate: (key) => this._navigate(key)
                    }));
                }
                main.scrollTop = 0;
                return;
            }
            if (business && (business.id === 'steady' || business.id === 'steady_update' || business.id === 'transient')) {
                this._navKey = 'tasks';
                this._app.querySelectorAll('.wb-nav-item').forEach(n =>
                    n.classList.toggle('active', n.dataset.nav === 'tasks'));
                const main = this._app.querySelector('.wb-main');
                main.innerHTML = '';
                main.appendChild(window.Workbench.renderSteadyTask({
                    project: this._ctx.project,
                    updateMode: business.id === 'steady_update',
                    forceCreate: business.id === 'steady_update' && business.forceCreate === true,
                    transientMode: business.id === 'transient',
                    back: (gotoModels) => {
                        this._navigate(gotoModels ? 'models' : 'tasks');
                    },
                    navigate: (key) => this._navigate(key)
                }));
                main.scrollTop = 0;
            }
        }

        /* 切页前停掉旧页面轮询:旧任务的轮询定时器和共享轮询窗口若残留,
           会不断刷新全局 __WB_ENGINE_POLL_UNTIL__,让新页面被旧任务的状态"顶着"跑 */
        _stopActivePage() {
            if (typeof window.__WB_PAGE_STOP__ === 'function') {
                try { window.__WB_PAGE_STOP__(); } catch (e) { /* 忽略 */ }
            }
            window.__WB_PAGE_STOP__ = null;
            window.__WB_ENGINE_POLL_UNTIL__ = 0;
        }

        _switchProject() {
            this.hide();
            const root = document.getElementById('workbenchRoot');
            if (root && root.show) root.show();
        }
    }

    customElements.define('workbench-shell', WorkbenchShell);
})();
