/**
 * 按钮和菜单项ID映射配置
 * 用于将文本绑定改为ID绑定，提高代码的可维护性和国际化支持
 */

// 按钮ID到功能的映射
const BUTTON_ID_MAP = {
    'btn-new-project': {
        text: '新建',
        action: 'showProjectCreate'
    },
    'btn-open-project': {
        text: '打开',
        action: 'showProjectList'
    },
    'btn-analyze': {
        text: '分析',
        action: 'showVisualAnalysis'
    },
    'btn-add': {
        text: '接入',
        action: 'showRegisterEmbedded'
    },
    'btn-upload': {
        text: '上传',
        action: 'showModelUpload'
    },
    'btn-algorithm-upload': {
        text: '算法上传',
        action: 'showAlgorithmUpload'
    },
    'btn-import': {
        text: '导入',
        action: 'showImportData'
    },
    'btn-query': {
        text: '查询',
        action: 'showDataArchiveList'
    },
    'btn-download': {
        text: '下载',
        action: 'handleDownload'
    },
    'btn-algorithm-download': {
        text: '算法下载',
        action: 'handleAlgorithmDownload'
    },
    'btn-delete': {
        text: '删除',
        action: 'handleDeleteModel'
    },
    'btn-unload': {
        text: '卸载',
        action: 'handleRemoveDataSource'
    },
    'btn-manage': {
        text: '管理',
        action: 'showDataSourceList'
    },
    'btn-edit': {
        text: '编辑',
        action: 'handleEditModel'
    },
    'btn-algorithm-edit': {
        text: '算法编辑',
        action: 'handleEditAlgorithm'
    },
    'btn-algorithm-delete': {
        text: '删除',
        action: 'handleDeleteAlgorithm'
    },
    'btn-algorithm-search': {
        text: '搜索',
        action: 'showAlgorithmArchiveList'
    },
    'btn-parse': {
        text: '搜索',
        action: 'showModelArchiveList'
    },
    'btn-simulation': {
        text: '仿真',
        action: 'showSimulationArchive'
    },
    'btn-simulation-analyze': {
        text: '分析',
        action: 'showSimulationRecord'
    }
};

// 菜单项ID到功能的映射
const MENU_ID_MAP = {
    'menu-data-source-management': {
        text: '异构数据源管理',
        action: 'showDataSourceList'
    },
    'menu-data-archive-query': {
        text: '数据档案查询',
        action: 'showDataArchiveList'
    },
    'menu-register-heterogeneous-data-source': {
        text: '注册异构数据源',
        action: 'showRegisterEmbedded'
    },
    'menu-import-data': {
        text: '导入数据',
        action: 'showImportData'
    },
    'menu-upload-model-file': {
        text: '上传模型文件',
        action: 'showModelUpload'
    },
    'menu-upload-algorithm-file': {
        text: '上传算法文件',
        action: 'showAlgorithmUpload'
    },
    'menu-download-model-file': {
        text: '下载模型文件',
        action: 'handleDownload'
    },
    'menu-download-algorithm-file': {
        text: '下载算法文件',
        action: 'handleAlgorithmDownload'
    },
    'menu-remove-model-asset': {
        text: '移除模型资产',
        action: 'handleDeleteModel'
    },
    'menu-edit-meta-model-archive': {
        text: '编辑元模型档案',
        action: 'handleEditModel'
    },
    'menu-model-archive-query': {
        text: '搜索模型档案',
        action: 'showModelArchiveList'
    },
    'menu-edit-meta-algorithm-archive': {
        text: '编辑算法档案',
        action: 'handleEditAlgorithm'
    },
    'menu-algorithm-archive-query': {
        text: '搜索算法档案',
        action: 'showAlgorithmArchiveList'
    },
    'menu-remove-algorithm-asset': {
        text: '移除算法资产',
        action: 'handleDeleteAlgorithm'
    },
    'menu-configure-parsing-rules': {
        text: '配置解析规则',
        action: 'showParsingRules'
    },
    'menu-association-rule-configuration': {
        text: '关联规则配置',
        action: 'showAssociationRules'
    },
    'menu-simulation-archive': {
        text: '仿真档案管理',
        action: 'showSimulationArchive'
    },
    'menu-simulation-record': {
        text: '仿真记录',
        action: 'showSimulationRecord'
    },
    'menu-algorithm-list': {
        text: '算法管理',
        action: 'showAlgorithmList'
    },
    'menu-project-new': {
        text: '新建项目',
        action: 'showProjectCreate'
    },
    'menu-project-list': {
        text: '打开项目',
        action: 'showProjectList'
    },
    'menu-numerical-and-curve-analysis': {
        text: '数值与曲线分析',
        action: 'showVisualAnalysis'
    },
    'menu-clear-workspace': {
        text: '清空工作区',
        action: 'clearWorkspace'
    },
    'menu-light-mode': {
        text: '明亮模式',
        action: 'setLightMode'
    },
    'menu-dark-mode': {
        text: '暗黑模式',
        action: 'setDarkMode'
    },
    'menu-about': {
        text: '关于',
        action: 'showAbout'
    }
};

// 根据按钮ID获取对应的动作
function getButtonAction(buttonId) {
    const buttonConfig = BUTTON_ID_MAP[buttonId];
    return buttonConfig ? buttonConfig.action : null;
}

// 根据菜单ID获取对应的动作
function getMenuAction(menuId) {
    const menuConfig = MENU_ID_MAP[menuId];
    return menuConfig ? menuConfig.action : null;
}

// 根据按钮ID获取对应的文本
function getButtonText(buttonId) {
    const buttonConfig = BUTTON_ID_MAP[buttonId];
    return buttonConfig ? buttonConfig.text : '';
}

// 根据菜单ID获取对应的文本
function getMenuText(menuId) {
    const menuConfig = MENU_ID_MAP[menuId];
    return menuConfig ? menuConfig.text : '';
}
