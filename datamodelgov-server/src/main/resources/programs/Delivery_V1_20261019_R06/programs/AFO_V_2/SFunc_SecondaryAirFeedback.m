function SFunc_SecondaryAirFeedback(block)
%SFUNC_SECONDARYAIRFEEDBACK 构造外部空气系统返回 DLL 的 50 维支路状态。
%
% 输入 1：发动机 S-Function 输出的 50 维支路状态模板。每 5 个元素依次为
%         [绝对流量, 焓, 总温, 总压, 油气比]，共 G01~G10 十组。
% 输入 2：外部空气系统计算得到的 G01~G08 八路绝对流量，单位 kg/s。
% 输出  ：保持输入 1 的全部状态，仅用输入 2 覆盖 G01~G08 的流量槽：
%         [1, 6, 11, 16, 21, 26, 31, 36]。
%
% 这样处理有三个目的：
%   1. HPC 使用外部系统计算的绝对引气流量；
%   2. GT/PT 继续读取发动机侧已有的总温、总压和油气比；
%   3. G09/G10 以及全部非流量状态保持原定义，不扩大本轮改造范围。
%
% 本块本身不含状态。其输出必须再经过 Delay_AirReturn50 后进入发动机
% S-Function，以切断发动机与外部空气系统之间的代数环。
setup(block);
end


function setup(block)
block.NumDialogPrms = 0;
block.NumInputPorts = 2;
block.NumOutputPorts = 1;

block.InputPort(1).Dimensions = 50;
block.InputPort(1).DatatypeID = 0;
block.InputPort(1).Complexity = 'Real';
block.InputPort(1).DirectFeedthrough = true;

block.InputPort(2).Dimensions = 8;
block.InputPort(2).DatatypeID = 0;
block.InputPort(2).Complexity = 'Real';
block.InputPort(2).DirectFeedthrough = true;

block.OutputPort(1).Dimensions = 50;
block.OutputPort(1).DatatypeID = 0;
block.OutputPort(1).Complexity = 'Real';

block.SampleTimes = [-1 0];
block.SimStateCompliance = 'DefaultSimState';
block.RegBlockMethod('Outputs', @Output);
end


function Output(block)
secondaryAirTemplate = block.InputPort(1).Data(:);
externalFlow = block.InputPort(2).Data(:);

if numel(secondaryAirTemplate) ~= 50 || ...
        any(~isfinite(secondaryAirTemplate))
    error('sht:secondaryAirFeedback:badTemplate', ...
        '发动机二次空气状态模板必须是 50 维有限实数向量。');
end
if numel(externalFlow) ~= 8 || any(~isfinite(externalFlow)) || ...
        any(externalFlow < 0)
    error('sht:secondaryAirFeedback:badExternalFlow', ...
        '外部空气系统 G01~G08 必须是 8 维有限非负绝对流量。');
end

feedback = secondaryAirTemplate;
flowIndices = 1:5:36;
feedback(flowIndices) = externalFlow;
block.OutputPort(1).Data = feedback;
end
