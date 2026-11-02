function cfg = sht_merge_config(defaultCfg, userCfg)
% 阅读说明：
%   本文件递归合并默认配置和用户覆盖配置。
%   规则是用户字段优先、结构体字段递归合并，避免测试脚本为了改一个参数而复制整棵 cfg。
%SHT_MERGE_CONFIG Recursively merge user config into defaults.
% 递归合并配置结构。
%
% 用户只需要给出想覆盖的字段，其余字段从 sht_default_config 继承。
% 这比在多个脚本中直接修改 base workspace 变量更清晰。

cfg = defaultCfg;
if isempty(userCfg)
    return;
end

fields = fieldnames(userCfg);
for i = 1:numel(fields)
    name = fields{i};
    if isstruct(userCfg.(name)) && isfield(cfg, name) && isstruct(cfg.(name))
        cfg.(name) = sht_merge_config(cfg.(name), userCfg.(name));
    else
        cfg.(name) = userCfg.(name);
    end
end

if isfield(cfg, 'Tctrl')
    cfg.controller.sampleTime = cfg.Tctrl;
end
end
