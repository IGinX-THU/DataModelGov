function result=Start_TC27_RequestStop_01(outputDirectory)
%START_TC27_REQUESTSTOP_01 Request a safe stop from another MATLAB process.
% The calculation finishes its current DLL/Jacobian work before confirming
% stopped. This entry never force-kills the worker or changes its checkpoint.
assert(nargin==1&&(ischar(outputDirectory)||isstring(outputDirectory)), ...
    'TC27:Stop:Directory','Pass the complete TC27 task directory.');
directory=sht_tc27_canonical_path(outputDirectory);
assert(isfolder(fullfile(directory,'run_control')), ...
    'TC27:Stop:Missing','No run-control session exists in this directory.');
result=sht_tc24_run_control('requeststop',directory);
result.directory=directory;
result.controlState=sht_tc24_run_control('state',directory);
end
