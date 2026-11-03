function view=Start_TC27_SteadyPredictionResultView_01(resultLocation,makePlot)
%START_TC27_STEADYPREDICTIONRESULTVIEW_01 仅从保存的Excel/身份查看预测。
% 不恢复估计MAT、不读取原模型或原输入、不构造配置、绝不调用DLL。
if nargin<2,makePlot=false;end
file=sht_tc27_canonical_path(resultLocation);
if isfolder(file),file=fullfile(file,'tc27_new_condition_prediction.xlsx');end
[directory,name]=fileparts(file);
identityFile=fullfile(directory,[name,'_identity.json']);
assert(isfile(file)&&isfile(identityFile),'TC27:PredictView:Missing','缺少预测Excel或身份文件。');
fid=fopen(identityFile,'r','n','UTF-8');assert(fid>=0,'TC27:PredictView:Identity','无法读取身份。');
cleanup=onCleanup(@()fclose(fid));id=jsondecode(fread(fid,Inf,'*char').');clear cleanup;
assert(strcmp(id.schema,'TC27_PREDICTION_IDENTITY_V1')&& ...
    strcmpi(id.resultSHA256,sht_tc27_file_identity(file)), ...
    'TC27:PredictView:Identity','预测Excel已改变或身份不匹配。');
m=readtable(file,'Sheet','PredictionManifest');p=readtable(file,'Sheet','Prediction');
inputs=readtable(file,'Sheet','Inputs');h=readtable(file,'Sheet','TransientCorrections');
bias=readtable(file,'Sheet','InheritedFuelBias');
assert(height(m)==1&&string(m.schema)=="TC27_STEADY_PREDICTION_EXCEL_V1"&& ...
    strcmpi(char(string(m.model_sha256)),id.modelSHA256)&& ...
    strcmpi(char(string(m.runtime_manifest_sha256)),id.runtimeManifestSHA256), ...
    'TC27:PredictView:Contract','预测保存合同与身份不一致。');
assert(height(p)==height(inputs)&&isequal(string(p.point_id),string(inputs.point_id))&& ...
    height(h)==13&&isequal(h.hIndex,(58:70).'), ...
    'TC27:PredictView:Contract','工况或13项参数保存不完整。');
view=struct('status',char(string(m.status)),'resultFile',file,'manifest',m, ...
    'conditions',inputs,'prediction',p,'transientParameters',h,'inheritedFuelBias',bias, ...
    'uqStatus',char(string(m.uq_status)),'elapsed_s',m.elapsed_s, ...
    'physicalEvaluationPerformed',false,'internalMatRead',false);
fprintf('读取已保存预测：%s；%d个工况；本次没有物理求值。\n',view.status,height(p));
disp(p);disp(h);
if makePlot
    figure('Name','TC27独立稳态预测','Position',[80,80,1000,650]);tiledlayout(2,2);
    channels={'Np_rpm','Ng_rpm','Pt3_Pa','Tt45_K'};
    for j=1:numel(channels)
        nexttile;bar(p.(channels{j}));grid on;title(channels{j},'Interpreter','none');
        xticks(1:height(p));xticklabels(string(p.point_id));
    end
end
end
