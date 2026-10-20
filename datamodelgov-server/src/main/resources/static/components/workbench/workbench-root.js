/**
 * <workbench-root> 项目入口(参考图 01-23 概念,交互按实际功能设计):
 * - 最近项目列表即"打开项目"入口,行点击进入对应工作台;
 * - "新建项目"展开表单(名称/发动机/类型/保存位置),校验通过后创建并进入;
 * - 一个项目绑定同一台发动机(副标题一句话说明,不堆叠提示文字)。
 */
(function () {
    const WB = () => window.Workbench;

    const TYPE_TO_WORKBENCH = { '个性化自适应建模': 'modeling', '系统联合仿真': 'testbench' };
    const TYPE_TAG = { '个性化自适应建模': 'teal', '系统联合仿真': 'blue' };

    class WorkbenchRoot extends HTMLElement {
        show() {
            this._render();
            this.style.display = '';
            this._loadProjects();
        }

        hide() { this.style.display = 'none'; }

        _render() {
            this.innerHTML = '';
            this.appendChild(WB().h('link', { rel: 'stylesheet', href: './components/workbench/workbench.css?v=r4' }));
            const username = localStorage.getItem('username') || '';

            const rootEl = WB().h('div', { class: 'wb-root' },
                WB().h('header', { class: 'wb-topbar' },
                    WB().h('div', { class: 'wb-brand' },
                        WB().h('span', { class: 'wb-brand-icon', html: WB().ICONS.logo }),
                        WB().h('span', { class: 'wb-app-name' }, '数据与模型一体化管理软件')),
                    WB().h('div', { class: 'wb-topbar-right' },
                        WB().h('span', { class: 'wb-hint', style: 'margin:0' }, username ? '当前用户:' + username : ''),
                        WB().h('button', {
                            class: 'wb-btn wb-btn-outline', title: '进入旧的资产管理工作界面',
                            onclick: () => {
                                if (window.__WB_STANDALONE__) window.location.href = '/index.html?legacy=1';
                                else this.hide();
                            }
                        }, '旧版界面'),
                        WB().h('button', {
                            class: 'wb-btn wb-btn-outline', title: '退出登录',
                            onclick: () => window.AppConfig && window.AppConfig.logout()
                        }, '登出'))));

            // 页头:标题 + 新建按钮
            const newBtn = WB().h('button', { class: 'wb-btn wb-btn-primary', onclick: () => this._toggleNewForm() },
                '＋ 新建项目');
            const header = WB().h('div', { class: 'wb-entry-head' },
                WB().h('div', null,
                    WB().h('div', { class: 'wb-page-title' }, '项目'),
                    WB().h('div', { class: 'wb-page-sub' },
                        '一个项目对应一台发动机;选择最近项目继续工作,或新建一个项目。')),
                newBtn);

            // 最近项目
            const recent = WB().h('div', { id: 'wbProjectList', class: 'wb-card', style: 'padding:0;overflow:hidden' },
                WB().h('div', { class: 'wb-empty', style: 'border:none' }, '正在加载项目...'));

            // 新建面板(默认收起)
            const form = this._buildNewForm();

            const main = WB().h('main', { class: 'wb-root-main' },
                WB().h('div', { class: 'wb-root-inner' }, header, recent, form));
            rootEl.appendChild(main);
            this.appendChild(rootEl);
        }

        _buildNewForm() {
            const nameInput = WB().h('input', { id: 'wbNewName', placeholder: '例如:台架标定项目' });
            const engineInput = WB().h('input', { id: 'wbNewEngine', value: 'E-001' });
            const typeSelect = WB().h('select', { id: 'wbNewType' },
                WB().h('option', null, '个性化自适应建模'),
                WB().h('option', null, '系统联合仿真'));
            const locInput = WB().h('input', { id: 'wbNewLoc', value: 'D:/EngineProjects/E001' });
            const nameErr = WB().h('div', { class: 'wb-field-err', style: 'display:none' }, '请填写项目名称');
            const createBtn = WB().h('button', {
                class: 'wb-btn wb-btn-primary disabled',
                onclick: () => this._createAndEnter()
            }, '创建并进入项目');

            nameInput.addEventListener('input', () => {
                const ok = nameInput.value.trim().length > 0;
                nameInput.classList.toggle('wb-invalid', !ok);
                nameErr.style.display = ok || !nameInput.value ? 'none' : 'block';
                createBtn.classList.toggle('disabled', !ok);
            });
            engineInput.addEventListener('input', () => {
                const v = engineInput.value.trim().toUpperCase();
                locInput.value = 'D:/EngineProjects/' + (v || 'E001');
            });

            const panel = WB().h('div', {
                id: 'wbNewForm', class: 'wb-card wb-newform', style: 'display:none;margin-top:22px'
            },
                WB().h('div', { class: 'wb-form-grid' },
                    WB().h('div', { class: 'wb-field' }, WB().h('label', null, '项目名称 *'), nameInput, nameErr),
                    WB().h('div', { class: 'wb-field' }, WB().h('label', null, '发动机标识'), engineInput),
                    WB().h('div', { class: 'wb-field' }, WB().h('label', null, '项目类型'), typeSelect),
                    WB().h('div', { class: 'wb-field' }, WB().h('label', null, '项目保存位置'), locInput)),
                WB().h('div', { class: 'wb-actions-row', style: 'margin-top:18px' },
                    createBtn,
                    WB().h('button', {
                        class: 'wb-btn wb-btn-outline',
                        onclick: () => this._toggleNewForm(false)
                    }, '取消')));
            return panel;
        }

        _toggleNewForm(show) {
            const panel = this.querySelector('#wbNewForm');
            if (!panel) return;
            const visible = show !== undefined ? show : panel.style.display === 'none';
            panel.style.display = visible ? 'block' : 'none';
            if (visible) {
                panel.scrollIntoView({ behavior: 'smooth', block: 'center' });
                const name = this.querySelector('#wbNewName');
                if (name) setTimeout(() => name.focus(), 250);
            }
        }

        async _loadProjects() {
            const holder = this.querySelector('#wbProjectList');
            if (!holder) return;
            let projects = null;
            try {
                const resp = await window.AppConfig.engineGet('projects');
                if (resp && (resp.success || resp.code === 200) && Array.isArray(resp.data) && resp.data.length) {
                    projects = resp.data;
                }
            } catch (e) { console.warn('工作台项目列表不可用,回退旧项目接口', e); }
            if (!projects) {
                try {
                    const resp = await window.AppConfig.post('project', 'query', { pageNum: 1, pageSize: 50 });
                    if (resp && (resp.success || resp.code === 200)) projects = (resp.data || []).map(p => Object.assign({}, p, { type: p.type || (p.desc || '').split(' · ')[0] || '', engineId: p.engineId || (p.desc || '').split(' · ')[1] || '' }));
                } catch (e) { console.warn('项目列表加载失败', e); }
            }
            if (!holder.isConnected) return;
            holder.innerHTML = '';

            if (!projects || !projects.length) {
                holder.style.padding = '';
                holder.appendChild(WB().h('div', { class: 'wb-empty', style: 'border:none' },
                    '还没有项目。点击右上角"新建项目"创建第一个项目。'));
                return;
            }
            holder.style.padding = '';
            const table = WB().h('table', { class: 'wb-table' },
                WB().h('tr', null, ['项目', '发动机', '类型', '位置', ''].map(t => WB().h('th', null, t))),
                projects.map(p => {
                    const wbKey = TYPE_TO_WORKBENCH[p.type] || null;
                    const tag = TYPE_TAG[p.type];
                    return WB().h('tr', {
                        class: 'clickable',
                        onclick: () => this._enter(wbKey || 'modeling', p)
                    },
                        WB().h('td', { style: 'font-weight:600;color:#111827' }, p.name),
                        WB().h('td', null, p.engineId || '—'),
                        WB().h('td', null, p.type
                            ? WB().h('span', { class: 'wb-tag wb-tag-' + (tag || 'gray') }, p.type)
                            : WB().h('span', { class: 'wb-hint', style: 'margin:0' }, '未标注')),
                        WB().h('td', { class: 'wb-hint', style: 'margin:0' }, p.location || '已保存'),
                        WB().h('td', { style: 'width:60px;text-align:right;color:#9ca3af' }, '进入 ›'));
                }));
            holder.appendChild(table);
        }

        async _createAndEnter() {
            const name = this.querySelector('#wbNewName').value.trim();
            const engineId = this.querySelector('#wbNewEngine').value.trim().toUpperCase() || 'E-001';
            const type = this.querySelector('#wbNewType').value;
            const location = this.querySelector('#wbNewLoc').value.trim();
            if (!name) {
                this._toggleNewForm(true);
                return;
            }
            const created = { name, engineId, type, location };
            try {
                const resp = await window.AppConfig.enginePost('projects', { name, type, engineId, location });
                if (resp && (resp.success || resp.code === 200) && resp.data) {
                    created.id = resp.data.id;
                } else {
                    throw new Error('engine create failed');
                }
            } catch (e) {
                try {
                    await window.AppConfig.post('project', 'create', { name, desc: type + ' · ' + engineId });
                } catch (e2) { console.warn('项目创建接口不可用,仅本地进入', e2); }
            }
            this._enter(TYPE_TO_WORKBENCH[type] || 'modeling', created);
        }

        _enter(workbenchKey, project) {
            const p = {
                id: project.id || '',
                name: project.name,
                engineId: project.engineId || 'E-001',
                engineDesc: project.engineDesc || WB().DEMO.project.engineDesc,
                matlab: WB().DEMO.project.matlab,
                type: project.type || '',
                location: project.location || ''
            };
            this.hide();
            const shell = document.getElementById('workbenchShell');
            if (shell && shell.show) shell.show({ workbench: workbenchKey, project: p });
        }
    }

    customElements.define('workbench-root', WorkbenchRoot);
})();
