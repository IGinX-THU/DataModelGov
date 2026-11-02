package com.tsinghua.program.catalog;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import lombok.Data;

import java.util.List;

/**
 * 公开功能注册项,对应交付包 UI-R131 的 20 项公开入口(F-01~F-12 系列)。
 * 数据源 classpath:programs/catalog/program-catalog.json,
 * 由关联图 features 与《程序调用与独立使用手册》附录A 合成。
 */
@Data
@JsonIgnoreProperties(ignoreUnknown = true)
public class ProgramFeature {

    /** 功能标识,如 F-01、F-07-TC24 */
    private String id;

    /** 功能名称 */
    private String name;

    /** 所属工作台:modeling=发动机个性化建模,testbench=发动机数字试车台 */
    private String workbench;

    /** 程序模块:TC24/TC27/F3/Stage4/DesignPoint/StartStop/FullMode/AFO */
    private String module;

    /** 正式公开入口文件(相对交付包"程序"根目录) */
    private String entry;

    /** 离线孪生入口(如有) */
    private String offlineTwin;

    /** 配置权威脚本 */
    private String config;

    /** 配置字典 CSV(相对交付包"程序"根目录) */
    private String dictionary;

    /** 用户须提供/界面须确认的输入(手册口径) */
    private String inputs;

    /** 结果返回(手册口径) */
    private String outputs;

    /** 操作限制(手册口径) */
    private String limits;

    /** 支持的动作族(如 check/preview/confirm/estimate/run/status/requestPause/resume/readResult) */
    private List<String> actions;

    /** 关联效果图编号(图NN-NN) */
    private List<String> figures;

    /** 关联业务组(1~9) */
    private List<Integer> groups;
}
