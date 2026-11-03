function output=sht_tc27_uq_delivery(action,file,c,posterior)
%SHT_TC27_UQ_DELIVERY 下游只读Excel即可恢复联合后验调度，无MAT运行依赖。
% 模板、固定锚点、样本联合行关系、权重及附加参数条件矩均不可丢失。
switch action
    case 'write'
        assert(isvector(posterior.weights)&&numel(posterior.weights)==size(posterior.theta,2)&& ...
            all(isfinite(posterior.weights(:)))&&all(posterior.weights(:)>=0)&&sum(posterior.weights(:))>0, ...
            'TC27:UQ:DeliveryWeights','联合样本权重必须有限、非负且总和为正。');
        weights=posterior.weights(:)/sum(posterior.weights);
        if isfile(file)
            try
                existing=sht_tc27_uq_delivery('read',file);
                same=local_equal(existing.theta,posterior.theta)&&local_equal(existing.weights,weights);
                keys=string(existing.manifest.key);values=string(existing.manifest.value);
                same=same&&isequal(values(keys=="contract_sha256"),string(c.contractHash))&& ...
                    isequal(values(keys=="method"),string(posterior.method))&& ...
                    isequal(values(keys=="quality"),string(posterior.quality));
                hasConditional=isfield(posterior,'nuisanceConditionalMean');
                same=same&&(hasConditional==isfield(existing,'nuisanceConditionalMean'));
                hasJoint=isfield(posterior,'nuisanceSamples');
                same=same&&(hasJoint==isfield(existing,'nuisanceSamples'));
                if same&&hasJoint,same=local_equal(existing.nuisanceSamples,posterior.nuisanceSamples);end
                if same&&hasConditional
                    same=local_equal(existing.nuisanceConditionalMean,posterior.nuisanceConditionalMean)&& ...
                        local_equal(existing.nuisanceConditionalCovariance,posterior.nuisanceConditionalCovariance);
                end
                if same,output=sht_tc27_file_identity(file);return;end
            catch failure
                warning('TC27:UQ:DeliveryRebuild','已有UQ Excel读回失败，重建本次完整工作簿：%s',failure.message);
            end
        end
        d=struct('runId',['TC27_',c.options.tag,'_',posterior.method], ...
            'route',c.route,'method',c.method,'modelMode',0,'thermalMode',3, ...
            'finalSchedule',c.scheduleTemplate,'npBranchModel',c.npBranchModel);
        % 不复用上次中断遗留的临时工作簿，避免新样本较少时旧行残留。
        temporary=[tempname(fileparts(file)),'.xlsx'];sht_tc27_delivery('write',d,temporary);
        writetable(c.parameterTable,temporary,'Sheet','ParameterDictionary');
        names=cellstr(c.parameterTable.node_id);samples=array2table(posterior.theta.','VariableNames',names);
        samples=[table((1:numel(weights)).',weights,'VariableNames',{'sample_id','weight'}),samples];
        writetable(samples,temporary,'Sheet','PosteriorSamples');
        writetable(c.nuisance,temporary,'Sheet','NuisancePrior');
        manifest=table(["method";"quality";"contract_sha256";"source_model_sha256"; ...
            "source_model_identity_sha256";"source_model_route";"source_model_method"; ...
            "runtime_package_id";"runtime_manifest_sha256";"thermal_sha256"; ...
            "model_mode";"thermal_mode";"thermal_model";"transient_corrections"; ...
            "statistical_calibration_confirmed";"prediction_scope"], ...
            [string(posterior.method);string(posterior.quality);string(c.contractHash); ...
            string(c.identity.delivery);string(c.identity.modelIdentity); ...
            string(c.route);string(c.method);string(c.inputContract.modelIdentity.runtimePackageId); ...
            string(c.identity.runtimeManifest);string(c.identity.thermal); ...
            string(c.modelMode);string(c.thermalMode);"Visser16"; ...
            "13_fixed_zero";"false";"conditional_on_selected_steady_points_and_fixed_thermal_configuration"], ...
            'VariableNames',{'key','value'});
        writetable(manifest,temporary,'Sheet','UQManifest');
        if isfield(c,'observationMode')
            manifest=[manifest;table(["observation_mode";"inference_error_model"; ...
                "observation_count";"parameter_count"], ...
                [string(c.observationMode);string(c.options.errorModel); ...
                string(numel(c.observed));string(c.parameterCount)], ...
                'VariableNames',{'key','value'})];
            writetable(manifest,temporary,'Sheet','UQManifest');
        end
        settings={'integrationStep_s','nuisanceAnchorMode','historyDiscrepancy', ...
            'historyCorrelationTime_s','curveCorrelationLengthScale'};
        for j=1:numel(settings)
            name=settings{j};
            if isfield(c.options,name)
                manifest=[manifest;table(string(name),string(c.options.(name)), ...
                    'VariableNames',{'key','value'})]; %#ok<AGROW>
            end
        end
        if isfield(posterior,'samplingBackend')
            manifest=[manifest;table(["sampling_backend";"surrogate_used"], ...
                [string(posterior.samplingBackend);string(posterior.surrogateUsed)], ...
                'VariableNames',{'key','value'})];
        end
        writetable(manifest,temporary,'Sheet','UQManifest');
        if isfield(posterior,'nuisanceConditionalMean')
            t=array2table(posterior.nuisanceConditionalMean.','VariableNames',cellstr("h"+string(c.nuisance.c_index)));
            t=[table((1:height(t)).','VariableNames',{'sample_id'}),t];writetable(t,temporary,'Sheet','NuisanceConditionalMean');
            writematrix(posterior.nuisanceConditionalCovariance,temporary,'Sheet','NuisanceConditionalCov');
        end
        if isfield(posterior,'nuisanceSamples')
            t=array2table(posterior.nuisanceSamples.','VariableNames',cellstr("h"+string(c.nuisance.c_index)));
            t=[table((1:height(t)).','VariableNames',{'sample_id'}),t];
            writetable(t,temporary,'Sheet','NuisanceSamples');
            manifest=[manifest;table("nuisance_representation","bounded_joint_samples_local_affine_model", ...
                'VariableNames',{'key','value'})];
            writetable(manifest,temporary,'Sheet','UQManifest');
        end
        % 全部工作表写完后独立恢复；失败只留下候选临时文件，不触碰原交付。
        recovered=sht_tc27_uq_delivery('read',temporary);
        assert(local_equal(recovered.theta,posterior.theta)&&local_equal(recovered.weights,weights), ...
            'TC27:UQ:DeliveryRoundTrip','UQ Excel主参数或权重读回不一致，未发布。');
        if isfield(posterior,'nuisanceSamples')
            assert(local_equal(recovered.nuisanceSamples,posterior.nuisanceSamples), ...
                'TC27:UQ:DeliveryRoundTrip','附加联合样本读回不一致，未发布。');
        end
        if isfield(posterior,'nuisanceConditionalMean')
            assert(local_equal(recovered.nuisanceConditionalMean,posterior.nuisanceConditionalMean)&& ...
                local_equal(recovered.nuisanceConditionalCovariance,posterior.nuisanceConditionalCovariance), ...
                'TC27:UQ:DeliveryRoundTrip','附加条件矩读回不一致，未发布。');
        end
        movefile(temporary,file,'f');output=sht_tc27_file_identity(file);
    case 'read'
        base=sht_tc27_delivery('read',[],file);t=readtable(file,'Sheet','ParameterDictionary');
        samples=readtable(file,'Sheet','PosteriorSamples');manifest=readtable(file,'Sheet','UQManifest');
        weights=samples.weight(:);theta=samples{:,cellstr(string(t.node_id))}.';
        assert(all(isfinite(theta),'all')&&all(weights>=0)&&abs(sum(weights)-1)<1e-8);
        assert(isequal(samples.sample_id,(1:height(samples)).'),'联合样本行号不连续。');
        assert(all(theta>=t.lower_bound-1e-10 & theta<=t.upper_bound+1e-10,'all'), ...
            '主参数样本越出交付字典边界。');
        % m3nodestoschedule只使用此表及模板，不需要原确定性MAT或训练集。
        contract=struct('parameterCount',height(t),'parameterTable',t, ...
            'scheduleTemplate',base.finalSchedule,'lowerBound',t.lower_bound,'upperBound',t.upper_bound);
        output=struct('contract',contract,'theta',theta,'weights',weights, ...
            'npBranchModel',base.npBranchModel,'manifest',manifest,'internalMatRead',false);
        output.nuisancePrior=readtable(file,'Sheet','NuisancePrior');
        % Excel允许工程人员调整列顺序，参数身份必须按显式编号恢复。
        nuisanceNames=cellstr("h"+string(output.nuisancePrior.c_index));
        assert(numel(unique(nuisanceNames))==numel(nuisanceNames), ...
            'TC27:UQ:DeliveryDictionary','附加参数字典编号重复。');
        [~,sheets]=xlsfinfo(file);
        if any(strcmp(sheets,'NuisanceSamples'))
            joint=readtable(file,'Sheet','NuisanceSamples');
            assert(isequal(joint.sample_id,samples.sample_id),'附加参数联合行号不匹配。');
            assert(all(ismember(nuisanceNames,joint.Properties.VariableNames)), ...
                'TC27:UQ:DeliveryColumns','附加联合样本缺少字典指定的参数列。');
            output.nuisanceSamples=joint{:,nuisanceNames}.';n=output.nuisancePrior;
            assert(all(isfinite(output.nuisanceSamples),'all'), ...
                'TC27:UQ:DeliveryFinite','附加联合样本含非有限值。');
            assert(all(output.nuisanceSamples>=n.lower-1e-12 & output.nuisanceSamples<=n.upper+1e-12,'all'));
        end
        if any(strcmp(sheets,'NuisanceConditionalMean'))
            conditional=readtable(file,'Sheet','NuisanceConditionalMean');
            assert(isequal(conditional.sample_id,samples.sample_id),'附加参数条件均值的样本对应关系不一致。');
            assert(all(ismember(nuisanceNames,conditional.Properties.VariableNames)), ...
                'TC27:UQ:DeliveryColumns','附加条件均值缺少字典指定的参数列。');
            output.nuisanceConditionalMean=conditional{:,nuisanceNames}.';
            output.nuisanceConditionalCovariance=readmatrix(file,'Sheet','NuisanceConditionalCov');
            assert(size(output.nuisanceConditionalMean,1)==height(output.nuisancePrior));
            assert(all(isfinite(output.nuisanceConditionalMean),'all')&& ...
                all(isfinite(output.nuisanceConditionalCovariance),'all'));
            % 无列标题的协方差矩阵仍按NuisancePrior字典顺序解释。
            V=output.nuisanceConditionalCovariance;n=height(output.nuisancePrior);
            assert(isequal(size(V),[n,n]),'TC27:UQ:DeliveryCovariance', ...
                '附加条件协方差维数与字典不一致。');
            tolerance=1e-10*max(norm(V,'fro'),realmin);
            assert(norm(V-V.','fro')<=tolerance&& ...
                min(eig((V+V.')/2))>=-tolerance, ...
                'TC27:UQ:DeliveryCovariance','附加条件协方差不对称或非半正定。');
        end
    otherwise,error('未知UQ交付动作。');
end
end

function same=local_equal(a,b)
same=isequal(size(a),size(b))&&all(isfinite(a(:)))&&all(isfinite(b(:)))&& ...
    all(abs(a(:)-b(:))<=1e-12*max(1,max(abs(a(:)),abs(b(:)))));
end
