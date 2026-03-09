package com.tsinghua.service;

import cn.edu.tsinghua.iginx.session.Session;
import cn.edu.tsinghua.iginx.session_v2.IginXClient;
import cn.edu.tsinghua.iginx.session_v2.write.Point;
import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import com.tsinghua.dto.InputBindDto;
import com.tsinghua.dto.OutputBindDto;
import com.tsinghua.dto.RunTaskRequest;
import com.tsinghua.entity.AssociationRulesEntity;
import com.tsinghua.entity.RunTaskEntity;
import com.tsinghua.enums.TaskStatus;
import com.tsinghua.util.ConvertUtil;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Lazy;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.stream.Collectors;

@Slf4j
@Service
public class RunTaskService {

    private static final String DATA_PREFIX = "relational_system.association_job";

    @Autowired
    private Session iginxSession;

    @Lazy
    @Autowired
    private AssociationRulesService associationRulesService;

    @Autowired
    private IginXClient iginxClient;


    public void runTask(RunTaskRequest runTaskRequest) {
        List<Point> metaPoints = new ArrayList<>();
        AssociationRulesEntity associationRulesEntity = associationRulesService.queryRule(runTaskRequest.getRuleId());
        long timestamp = System.currentTimeMillis();
        RunTaskEntity runTaskEntity = ConvertUtil.entityConvert(associationRulesEntity, RunTaskEntity.class);
        runTaskEntity.setTimestamp(timestamp);
        runTaskEntity.setStatus(TaskStatus.WAITING);
        List<InputBindDto> inputs = JSONArray.parseArray(associationRulesEntity.getInputsBind(), InputBindDto.class);
        runTaskEntity.setInputMeasurements(JSONArray.toJSONString(inputs.stream().map(InputBindDto::getSourceField).collect(Collectors.toList())));
        List<OutputBindDto> outputs = JSONArray.parseArray(associationRulesEntity.getOutputsBind(), OutputBindDto.class);
        runTaskEntity.setOutputMeasurements(JSONArray.toJSONString(outputs.stream().map(OutputBindDto::getResultTarget).collect(Collectors.toList())));

        String metaBasePath = DATA_PREFIX;

        // 创建各个字段的数据点
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "name", runTaskEntity.getName(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "startTime", runTaskEntity.getStartTime(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "endTime", runTaskEntity.getEndTime(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "ruleId", runTaskEntity.getRuleId(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "inputMeasurements", runTaskEntity.getInputMeasurements(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "outputMeasurements", runTaskEntity.getOutputMeasurements(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "status", runTaskEntity.getStatus(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "timestamp", runTaskEntity.getTimestamp(), timestamp));

        // 批量写入元数据
        iginxClient.getWriteClient().writePoints(metaPoints);
        log.info("关联规则已保存。名称: {}, 时间戳: {}", associationRulesEntity.getName(), timestamp);
    }
}
