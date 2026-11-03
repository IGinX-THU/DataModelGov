function [cfg,execution]=sht_tc27_uq_runtime(c,executionOptions)
%SHT_TC27_UQ_RUNTIME 新合同绑定执行包，旧合同默认仍用旧计算包。
% 独立冻结候选比较可显式指定新目录；只改变本次执行，不重签源合同。
if nargin<2,executionOptions=struct();end
explicit=isfield(executionOptions,'runtimeDirectory')&&~isempty(executionOptions.runtimeDirectory);
if explicit,directory=executionOptions.runtimeDirectory;
elseif isfield(c,'runtimeDirectory'),directory=c.runtimeDirectory;
else,directory='legacy';end
package=sht_tc27_runtime_package(directory);
if ~explicit
    if isfield(c,'runtimeIdentity')
        assert(isequaln(c.runtimeIdentity,package.identity), ...
            'TC27:UQ:RuntimeIdentity','合同执行包已改变，请建立新合同，不得重签旧检查点。');
    else
        assert(strcmpi(c.identity.dll,sht_tc27_file_identity(fullfile(package.directory,'GTESS.dll'))), ...
            'TC27:UQ:LegacyRuntime','历史合同DLL不匹配，不能默认用新包复现旧结果。');
    end
end
cfg=sht_tc27_config(3,'joint_full',package.directory);
execution=sht_tc27_execution_identity(cfg);
end
