package com.tsinghua.program.catalog;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import lombok.Data;

import java.util.List;
import java.util.Map;

/** 业务组(图组):界面↔界面操作流程的组织单元,步骤标题即触发动作。 */
@Data
@JsonIgnoreProperties(ignoreUnknown = true)
public class BusinessGroup {
    private String id;
    private String title;
    private List<Map<String, Object>> steps;
}
