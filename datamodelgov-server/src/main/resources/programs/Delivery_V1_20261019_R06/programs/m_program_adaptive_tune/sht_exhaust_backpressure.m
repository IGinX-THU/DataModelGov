function pressure = sht_exhaust_backpressure(ambientPressure, shaftPower, model)
%SHT_EXHAUST_BACKPRESSURE 按当前模型轴功率计算排气绝对背压，单位Pa。
% 背压不是测量输入。稳态求解传入候选转速形成的功率；历程求值传入
% 当前积分状态形成的功率。标定仍沿用原功率平方代理关系，不改动物理假设。
% ambientPressure为实测/给定环境静压；shaftPower单位W；model只含
% designRise_Pa与designPower_W等固定工程参数，不能传入冻结背压历程。
if ~isstruct(model) || ~isscalar(model) || ...
        ~all(isfield(model,{'designRise_Pa','designPower_W'}))
    error('SHT:Exhaust:Model','缺少排气背压模型标定参数。');
end
validateattributes(model.designRise_Pa,{'numeric'},{'real','scalar','finite','nonnegative'});
validateattributes(model.designPower_W,{'numeric'},{'real','scalar','finite','positive'});
validateattributes(ambientPressure,{'numeric'},{'real','finite','positive'});
validateattributes(shaftPower,{'numeric'},{'real','finite'});
pressure=ambientPressure+model.designRise_Pa.* ...
    (max(shaftPower,0)./model.designPower_W).^2;
end
