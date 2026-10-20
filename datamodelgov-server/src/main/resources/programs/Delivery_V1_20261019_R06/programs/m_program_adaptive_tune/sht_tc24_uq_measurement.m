function value=sht_tc24_uq_measurement(action,arg)
% TC24公开测量误差先验，不读取造数实现、真实偏置或测试集。
spec=sht_tc24_measurement_specification();
flow=spec(1,:);flow.name="Wa2";flow.unit="kg/s";flow.designReference=6.7114;
flow.biasHalfWidth=.20;flow.noiseStd=.025;flow.engineeringScale=.20;
spec=[spec;flow];
switch action
    case 'sensors'
        [ok,idx]=ismember(string(arg),spec.name);
        assert(all(ok),'TC24:UQ:Sensor','未配置的测量通道。');
        value=struct('supported',ok(:),'noiseStd',spec.noiseStd(idx), ...
            'totalBiasHalfWidth',spec.biasHalfWidth(idx), ...
            'maxFlowDrift',zeros(numel(idx),1),'flowDriftEnabled',false(numel(idx),1));
    case 'model'
        value=struct('designFlow_kgps',6.7114,'idleFlow_kgps',2.18,'specification',spec);
    case 'role'
        route=char(arg);
        outputs={'Ptb3','Ttb3','Pt45','Tt45','Pt6','Tt6','Wa2'};
        inputs=struct('field',{'Wf_mean','Mkp_mean','Pt1_mean','Tt1_mean','Pamb_mean'}, ...
            'sensor',{'Wf','Mkp','Pt1','Tt1','Pamb'});
        if strcmp(route,'steady')
            outputs=[{'Np','Ng'},outputs];state={};derived={};order=outputs;
        else
            assert(strcmp(route,'transient_instant'),'未知推断路径。');
            state={'Np','Ng'};derived={'dNp_dt','dNg_dt'};order=[outputs,derived];
            inputs=[struct('field',{'Np_mean','Ng_mean'},'sensor',state),inputs];
        end
        value=struct('schemaVersion','TC24_UQ_MEASUREMENT_ROLE_V1','route',route, ...
            'residualOrder',{order},'stateInputSensors',{state}, ...
            'directOutputSensors',{outputs},'derivedConstraintOutputs',{derived}, ...
            'propagatedInputDefinition',{inputs},'outputPredictionRoute','steady', ...
            'inputFlowDriftPropagated',false, ...
            'npNgNumericalSeedIsPhysicalInput',strcmp(route,'transient_instant'));
    otherwise
        error('TC24:UQ:Action','未知测量合同动作。');
end
end
