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
        constructor() {
            super();
            this._pageNum = 1;
            this._pageSize = 10;
            this._total = 0;
            this._nameFilter = '';
        }

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

            // 最近项目(分页,与旧版程序管理列表一致:筛选+每页条数+页码)
            const recent = WB().h('div', { id: 'wbProjectList', class: 'wb-card', style: 'padding:0;overflow:hidden' },
                WB().h('div', { class: 'wb-empty', style: 'border:none' }, '正在加载项目...'));

            // 新建面板(默认收起)
            const form = this._buildNewForm();

            const main = WB().h('div', { class: 'wb-root-main' },
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
            const locInput = WB().h('input', {
                id: 'wbNewLoc',
                placeholder: '(可选)相对路径,留空由系统生成并回显'
            });
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
                locInput.placeholder = '(可选)如 projects/' + (v || 'E001') + ',留空由系统生成';
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

        /** 项目分页列表:owner 隔离由后端 SQL 条件完成;交互仿旧版程序管理列表。 */
        async _loadProjects() {
            const holder = this.querySelector('#wbProjectList');
            if (!holder) return;
            holder.innerHTML = '';
            const paging = WB().h('div', { class: 'wb-root-pager' });

            // 工具行:名称筛选
            const nameInput = WB().h('input', {
                placeholder: '按项目名称筛选', value: this._nameFilter || '',
                style: 'width:220px'
            });
            nameInput.addEventListener('keydown', e => {
                if (e.key === 'Enter') { this._nameFilter = nameInput.value.trim(); this._pageNum = 1; this._loadProjects(); }
            });
            holder.appendChild(WB().h('div', { class: 'wb-filter-bar', style: 'padding:14px 16px;border-bottom:1px solid #e5e7eb' },
                WB().h('div', { class: 'wb-field' }, WB().h('label', null, '项目名称'), nameInput),
                WB().h('button', {
                    class: 'wb-btn wb-btn-outline',
                    onclick: () => { this._nameFilter = nameInput.value.trim(); this._pageNum = 1; this._loadProjects(); }
                }, '查询')));

            // 数据行
            const listHolder = WB().h('div', null, WB().h('div', { class: 'wb-empty', style: 'border:none' }, '正在加载项目...'));
            holder.appendChild(listHolder);
            holder.appendChild(paging);

            let projects = null;
            try {
                const resp = await window.AppConfig.engineGet('projects/list', {
                    name: this._nameFilter || '', pageNum: this._pageNum, pageSize: this._pageSize
                });
                if (resp && (resp.success || resp.code === 200) && Array.isArray(resp.data)) projects = resp.data;
            } catch (e) { console.warn('项目分页接口不可用', e); }

            // 总数(与列表同过滤口径;接口不可用时回退旧接口)
            try {
                const resp = await window.AppConfig.engineGet('projects/count', { name: this._nameFilter || '' });
                if (resp && (resp.success || resp.code === 200) && resp.data != null) {
                    this._total = parseInt(resp.data, 10) || 0;
                }
            } catch (e) {
                if (projects) this._total = projects.length;
            }

            if (!holder.isConnected) return;
            listHolder.innerHTML = '';
            if (!projects || !projects.length) {
                listHolder.style.padding = '';
                listHolder.appendChild(WB().h('div', { class: 'wb-empty', style: 'border:none' },
                    this._nameFilter ? '没有匹配的项目。' : '还没有项目。点击右上角"新建项目"创建第一个项目。'));
            } else {
                listHolder.appendChild(WB().h('table', { class: 'wb-table' },
                    WB().h('tr', null, ['项目', '发动机', '类型', '创建人', '位置', ''].map(t => WB().h('th', null, t))),
                    projects.map(p => WB().h('tr', {
                        class: 'clickable',
                        onclick: () => this._enter(TYPE_TO_WORKBENCH[p.type] || 'modeling', p)
                    },
                        WB().h('td', { style: 'font-weight:600;color:#111827' }, p.name),
                        WB().h('td', null, p.engineId || '—'),
                        WB().h('td', null, p.type
                            ? WB().h('span', { class: 'wb-tag wb-tag-' + (TYPE_TAG[p.type] || 'gray') }, p.type)
                            : WB().h('span', { class: 'wb-hint', style: 'margin:0' }, '未标注')),
                        WB().h('td', null, p.owner || '—'),
                        WB().h('td', { class: 'wb-hint', style: 'word-break:break-all' },
                            p.workdir || p.location || '系统默认目录'),
                        WB().h('td', { style: 'width:60px;text-align:right;color:#9ca3af' }, '进入 ›')))));
            }
            this._renderPager(paging);
        }

        /** 分页条:上一页 / 页码(当前±2) / 下一页 + 共N条第x/y页。 */
        _renderPager(paging) {
            paging.innerHTML = '';
            const maxPage = Math.max(1, Math.ceil(this._total / this._pageSize));
            if (this._pageNum > maxPage) this._pageNum = maxPage;
            const info = WB().h('span', { class: 'wb-hint' },
                '共 ' + this._total + ' 条,第 ' + this._pageNum + '/' + maxPage + ' 页');
            const prev = WB().h('button', { class: 'wb-btn wb-btn-outline' + (this._pageNum <= 1 ? ' disabled' : '') }, '上一页');
            prev.addEventListener('click', () => {
                if (this._pageNum > 1) { this._pageNum--; this._loadProjects(); }
            });
            const next = WB().h('button', { class: 'wb-btn wb-btn-outline' + (this._pageNum >= maxPage ? ' disabled' : '') }, '下一页');
            next.addEventListener('click', () => {
                if (this._pageNum < maxPage) { this._pageNum++; this._loadProjects(); }
            });
            const sizeSel = WB().h('select', { title: '每页条数' },
                [10, 20, 50].map(n => WB().h('option', Object.assign({ value: n }, n === this._pageSize ? { selected: '' } : {}), String(n))));
            sizeSel.addEventListener('change', () => { this._pageSize = parseInt(sizeSel.value, 10); this._pageNum = 1; this._loadProjects(); });
            paging.appendChild(info);
            paging.appendChild(prev);
            const start = Math.max(1, this._pageNum - 2);
            const end = Math.min(maxPage, this._pageNum + 2);
            for (let i = start; i <= end; i++) {
                const b = WB().h('button', {
                    class: 'wb-btn ' + (i === this._pageNum ? 'wb-btn-primary' : 'wb-btn-outline')
                }, String(i));
                b.addEventListener('click', () => { if (i !== this._pageNum) { this._pageNum = i; this._loadProjects(); } });
                paging.appendChild(b);
            }
            paging.appendChild(next);
            paging.appendChild(WB().h('span', { class: 'wb-hint', style: 'margin-left:8px' }, '每页'));
            paging.appendChild(sizeSel);
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
            let created = null;
            try {
                const resp = await window.AppConfig.enginePost('projects', { name, type, engineId, location });
                if (resp && (resp.success || resp.code === 200) && resp.data && resp.data.id) {
                    created = resp.data;
                } else {
                    throw new Error((resp && resp.message) || '创建接口返回异常');
                }
            } catch (e) {
                // 创建失败必须停在入口页,绝不带假id进入工作台,否则后续任务/数据全部失效
                WB().toast('创建项目失败: ' + (e.message || e), 'error');
                return;
            }
            this._enter(TYPE_TO_WORKBENCH[type] || 'modeling', created);
        }

        _enter(workbenchKey, project) {
            if (!project || !project.id) {
                WB().toast('项目缺少有效id,无法进入工作台。', 'error');
                return;
            }
            const p = {
                id: project.id,
                name: project.name,
                engineId: project.engineId || '',
                engineDesc: project.engineDesc || '',
                matlab: project.matlab || '',
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
