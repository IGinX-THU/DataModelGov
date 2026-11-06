packageDir = fileparts(mfilename('fullpath'));
cd(packageDir);
addpath(packageDir);
run(fullfile(packageDir, 'RunCtrlSysModelSHT.m'));
packageDir = fileparts(mfilename('fullpath'));
modelName = 'Dll_Control_AFO_V8_2_R2019b';
load_system(fullfile(packageDir, [modelName '.slx']));
open_system(modelName);
