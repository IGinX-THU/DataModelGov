function SFunc_AFO_Recorder(block)
%SFUNC_AFO_RECORDER 只读记录与安全点服务；不向物理模型写反馈。
block.NumDialogPrms=1;block.NumInputPorts=block.DialogPrm(1).Data;
block.NumOutputPorts=0;block.SetPreCompInpPortInfoToDynamic;
for k=1:block.NumInputPorts
    block.InputPort(k).DirectFeedthrough=true;block.InputPort(k).SamplingMode='Sample';
    block.InputPort(k).Dimensions=-1;block.InputPort(k).DatatypeID=0;
    block.InputPort(k).Complexity='Real';
end
block.SampleTimes=[0.025 0];block.SimStateCompliance='DefaultSimState';
block.RegBlockMethod('SetInputPortDimensions',@dimensions);
block.RegBlockMethod('Outputs',@outputs);
end
function dimensions(block,port,sz)
% 每个输入独立继承上游宽度，不能把首个标量端口的宽度推广到其余端口。
block.InputPort(port).Dimensions=sz;
end
function outputs(block)
values=cell(1,block.NumInputPorts);
for k=1:numel(values),values{k}=block.InputPort(k).Data(:).';end
sht_afo_session('record',block.CurrentTime,values);
end
