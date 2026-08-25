window.ProgramLauncher = (() => {
    const components = {
        simulinkRealtime: { id: 'programRun', tag: 'program-run' },
        matlabWorkflow: { id: 'programWorkflow', tag: 'program-workflow' }
    };

    async function loadConfig(name, version, projectName) {
        const params = { name, version };
        if (projectName) params.projectName = projectName;
        const response = await window.AppConfig.get('program', 'config', params);
        if (!response || !(response.success || response.code === 200)) {
            throw new Error((response && response.message) || '加载程序配置失败');
        }
        const data = response.data;
        return typeof data === 'string' ? JSON.parse(data) : (data || {});
    }

    function resolveExecutionType(config) {
        const executionType = config && config.runtime && config.runtime.executionType;
        return executionType || 'simulinkRealtime';
    }

    function recreateComponent(definition) {
        const current = document.getElementById(definition.id);
        if (!current || !current.parentElement) return current;
        if (typeof current.destroy === 'function') current.destroy();
        const replacement = document.createElement(definition.tag);
        replacement.id = definition.id;
        replacement.style.display = 'none';
        current.parentElement.replaceChild(replacement, current);
        return replacement;
    }

    async function open({ name, version, projectName } = {}) {
        if (!name || !version) throw new Error('程序名称和版本不能为空');
        const config = await loadConfig(name, version, projectName);
        const executionType = resolveExecutionType(config);
        const definition = components[executionType];
        if (!definition) throw new Error(`不支持的程序执行类型: ${executionType}`);

        if (window.hideAllComponents) window.hideAllComponents();
        const component = recreateComponent(definition);
        if (!component) throw new Error(`未找到程序组件: ${definition.id}`);

        component.setAttribute('data-name', name);
        component.setAttribute('data-version', version);
        if (projectName) component.setAttribute('data-project', projectName);
        component.programConfig = config;

        if (typeof component.show === 'function') {
            await component.show({ name, version, projectName, config });
        } else if (window.showComponent) {
            window.showComponent(definition.id);
        } else {
            component.style.display = '';
        }
        return component;
    }

    return { open, loadConfig, resolveExecutionType };
})();
