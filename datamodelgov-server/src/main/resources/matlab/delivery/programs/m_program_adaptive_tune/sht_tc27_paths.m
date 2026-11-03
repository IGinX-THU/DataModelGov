function p=sht_tc27_paths(options)
%SHT_TC27_PATHS 三部件2.7的独立输入、中间结果和报告目录。
% 不读取旧六部件latest，不写入TC24结果；DLL仍在隔离目录中验收。
p.root=fileparts(mfilename('fullpath'));
if nargin<1,options=struct();end
p.middle=fullfile(p.root,'MiddleData','three_component','tc27');
p.legacyRuntime=fullfile(p.root,'MiddleData','three_component','tc27_runtime');
% 显式候选包只影响本次执行，不改正式选择JSON或历史运行包。
selection='selected';
if isfield(options,'runtimeDirectory')&&~isempty(options.runtimeDirectory)
    selection=options.runtimeDirectory;
end
package=sht_tc27_runtime_package(selection);p.runtime=package.directory;
p.report=fullfile(fileparts(p.root),'report_outputs','three_component','TC27_R006');
p.data=fullfile(p.root,'TestData','three_component');
p.trainingFile=fullfile(p.data,'tc27_training_history.xlsx');
p.testFile=fullfile(p.data,'tc27_test_history.xlsx');
p.thermalFile=package.thermalFile;
p.kurzkeFile=package.kurzkeFile;
p.legacyMiddle=p.middle;
% 新批次显式选择输出空间。上游测量及热资产仍只读，不搬运旧检查点。
if isfield(options,'outputBatch')&&~isempty(options.outputBatch)
    batch=char(options.outputBatch);
    assert(~isempty(regexp(batch,'^[A-Za-z0-9_]+$','once')), ...
        'TC27:Paths:Batch','outputBatch只能由字母、数字、下划线组成。');
    p.middle=fullfile(p.middle,batch);
    p.report=fullfile(fileparts(p.root),'report_outputs','three_component',batch);
end
if isfield(options,'outputDirectory')&&~isempty(options.outputDirectory)
    directory=sht_tc27_canonical_path(options.outputDirectory);
    assert(isfolder(fileparts(directory)),'TC27:Paths:Parent', ...
        '输出位置的父目录不存在：%s',fileparts(directory));
    reserved={p.root,p.data,p.runtime,p.legacyMiddle};
    for j=1:numel(reserved)
        root=sht_tc27_canonical_path(reserved{j});
        assert(~strcmpi(directory,root)&&~startsWith(lower(directory),lower([root,filesep])), ...
            'TC27:Paths:Reserved','独立运行输出不能写入程序、正式输入或运行包目录。');
    end
    p.middle=fullfile(directory,'MiddleData');
    p.report=fullfile(directory,'report_outputs');
end
for name={'middle','report','data'}
    if ~isfolder(p.(name{1})),mkdir(p.(name{1}));end
end
end
