function SFunc_AFO_Command(block)
%SFUNC_AFO_COMMAND 完整主时间步读取已接受命令；不改变发动机状态。
block.NumDialogPrms=1;block.NumInputPorts=0;block.NumOutputPorts=1;
block.OutputPort(1).Dimensions=1;block.OutputPort(1).SamplingMode='Sample';
block.OutputPort(1).DatatypeID=0;block.OutputPort(1).Complexity='Real';
block.SampleTimes=[0.025 0];
block.SimStateCompliance='DefaultSimState';
block.RegBlockMethod('Outputs',@outputs);
end
function outputs(block)
values=sht_afo_session('source',block.CurrentTime);
block.OutputPort(1).Data=values(block.DialogPrm(1).Data);
end
