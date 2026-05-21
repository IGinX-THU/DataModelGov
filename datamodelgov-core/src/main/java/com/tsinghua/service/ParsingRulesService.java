package com.tsinghua.service;

import cn.edu.tsinghua.iginx.session.Session;
import cn.edu.tsinghua.iginx.session.SessionExecuteSqlResult;
import cn.edu.tsinghua.iginx.session_v2.IginXClient;
import cn.edu.tsinghua.iginx.session_v2.write.Point;
import com.tsinghua.auth.util.AuthUtil;
import com.tsinghua.dto.ParsingRulesQueryRequest;
import com.tsinghua.entity.ParsingRulesEntity;
import com.tsinghua.util.ConvertUtil;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import javax.annotation.PostConstruct;
import java.util.*;
import java.util.stream.Collectors;

@Slf4j
@Service
public class ParsingRulesService {

    private static final String DATA_PREFIX = "relational_system.parsing_rules";

    @Autowired
    private Session iginxSession;

    @Autowired
    private IginXClient iginxClient;

    @PostConstruct
    private void init() {
        try {
            // 1. Python标准规则（# @Input/@Output注释）
            ParsingRulesEntity pythonRuleEntity = new ParsingRulesEntity();
            pythonRuleEntity.setCreateTime(1776676648997L);
            pythonRuleEntity.setName("Python标准规则");
            pythonRuleEntity.setRegexPattern("^#\\s*@(Input|Output)\\s*:?\\s*(\\w+)\\s*[\\(\\[]?\\s*(\\w+)\\s*[\\)\\]]?\\s*-?\\s*(.*)$");
            pythonRuleEntity.setExample(
                    "# @Input: speed (float) - 车速\n" +
                    "# @Input: gear (int) - 档位\n" +
                    "# @Output: power (float) - 功率");
            pythonRuleEntity.setParseType("regex");
            pythonRuleEntity.setLanguage("python");
            pythonRuleEntity.setIsReadonly(true);
            saveRules(pythonRuleEntity);

            // 2. MATLAB标准规则（% @Input/@Output注释）
            ParsingRulesEntity matlabRuleEntity = new ParsingRulesEntity();
            matlabRuleEntity.setCreateTime(1776159194994L);
            matlabRuleEntity.setName("MATLAB标准规则");
            matlabRuleEntity.setRegexPattern("^%\\s*@(Input|Output)\\s*:?\\s*(\\w+)\\s*[\\(\\[]?\\s*(\\w+)\\s*[\\)\\]]?\\s*-?\\s*(.*)$");
            matlabRuleEntity.setExample(
                    "% @Input: speed (float) - 车速\n" +
                    "% @Input: gear (int) - 档位\n" +
                    "% @Output: power (float) - 功率");
            matlabRuleEntity.setParseType("regex");
            matlabRuleEntity.setLanguage("matlab");
            matlabRuleEntity.setIsReadonly(true);
            saveRules(matlabRuleEntity);

            // 3. C++ Doxygen规则（@param/@return注释）
            ParsingRulesEntity cppRuleEntity = new ParsingRulesEntity();
            cppRuleEntity.setCreateTime(1776159194995L);
            cppRuleEntity.setName("C++ Doxygen规则");
            cppRuleEntity.setRegexPattern("^\\s*\\*\\s*@(param|return)\\s+(?:\\[([^\\]]+)\\]\\s+)?(\\w+)(?:\\s*\\(([^)]+)\\))?\\s*-?\\s*(.*)$");
            cppRuleEntity.setExample(
                    "/**\n" +
                    " * @param[in] speed (float) - 车速\n" +
                    " * @param[in] gear (int) - 档位\n" +
                    " * @return power (float) - 功率\n" +
                    " */");
            cppRuleEntity.setParseType("regex");
            cppRuleEntity.setLanguage("cpp");
            cppRuleEntity.setIsReadonly(true);
            saveRules(cppRuleEntity);

            // 4. Python TypeHint规则（def run(a: float) -> float签名）
            ParsingRulesEntity typehintRuleEntity = new ParsingRulesEntity();
            typehintRuleEntity.setCreateTime(1776159194996L);
            typehintRuleEntity.setName("Python TypeHint规则");
            typehintRuleEntity.setRegexPattern("^\\s*def\\s+(\\w+)\\s*\\(([^)]*)\\)\\s*->\\s*([^:]+):\\s*(?:#.*)?$");
            typehintRuleEntity.setExample(
                    "def run(speed: float, gear: int) -> float:\n" +
                    "    \"\"\"计算功率\"\"\"\n" +
                    "def init(temp: float, pressure: float) -> None:");
            typehintRuleEntity.setParseType("typehint");
            typehintRuleEntity.setLanguage("python");
            typehintRuleEntity.setIsReadonly(true);
            saveRules(typehintRuleEntity);

            // 5. Python Inspect规则（基于inspect模块反射解析）
            ParsingRulesEntity inspectRuleEntity = new ParsingRulesEntity();
            inspectRuleEntity.setCreateTime(1776159194997L);
            inspectRuleEntity.setName("Python Inspect规则");
            inspectRuleEntity.setParseType("inspect");
            inspectRuleEntity.setLanguage("python");
            inspectRuleEntity.setIsReadonly(true);
            inspectRuleEntity.setPythonModule("");
            inspectRuleEntity.setPythonFunction("");
            inspectRuleEntity.setExample(
                    "# 使用Python inspect模块自动解析函数签名\n" +
                    "# 需要指定模块名和函数名\n" +
                    "# 例如: module=my_module, function=run");
            saveRules(inspectRuleEntity);

            // 6. Python Google Style规则（Args/Returns段注释）
            ParsingRulesEntity googleRuleEntity = new ParsingRulesEntity();
            googleRuleEntity.setCreateTime(1776159194998L);
            googleRuleEntity.setName("Python Google Style规则");
            googleRuleEntity.setRegexPattern("^\\s+(\\w+)\\s*\\(([^)]+)\\)\\s*:\\s*(.+)$");
            googleRuleEntity.setExample(
                    "def run(speed, gear):\n" +
                    "    \"\"\"计算功率.\n" +
                    "    Args:\n" +
                    "        speed (float): 车速\n" +
                    "        gear (int): 档位\n" +
                    "    Returns:\n" +
                    "        power (float): 功率\n" +
                    "    \"\"\"");
            googleRuleEntity.setParseType("regex");
            googleRuleEntity.setLanguage("python");
            googleRuleEntity.setIsReadonly(true);
            saveRules(googleRuleEntity);

            // 7. Python Sphinx/reST Style规则（:param/:type/:returns注释）
            ParsingRulesEntity sphinxRuleEntity = new ParsingRulesEntity();
            sphinxRuleEntity.setCreateTime(1776159194999L);
            sphinxRuleEntity.setName("Python Sphinx Style规则");
            sphinxRuleEntity.setRegexPattern("^\\s*:(param|type|returns?|rtype)\\s+([^:]*):\\s*(.*)$");
            sphinxRuleEntity.setExample(
                    "def run(speed, gear):\n" +
                    "    \"\"\"计算功率.\n" +
                    "    :param float speed: 车速\n" +
                    "    :param int gear: 档位\n" +
                    "    :returns: 功率\n" +
                    "    :rtype: float\n" +
                    "    \"\"\"");
            sphinxRuleEntity.setParseType("regex");
            sphinxRuleEntity.setLanguage("python");
            sphinxRuleEntity.setIsReadonly(true);
            saveRules(sphinxRuleEntity);

            // 8. MATLAB Help Text规则（标准MATLAB函数帮助注释）
            ParsingRulesEntity matlabHelpRuleEntity = new ParsingRulesEntity();
            matlabHelpRuleEntity.setCreateTime(1776159194200L);
            matlabHelpRuleEntity.setName("MATLAB Help Text规则");
            matlabHelpRuleEntity.setRegexPattern("^%\\s*(\\w+)\\s*-\\s*(.+)$");
            matlabHelpRuleEntity.setExample(
                    "function power = run(speed, gear)\n" +
                    "%RUN 计算功率\n" +
                    "%   speed - 车速 (float)\n" +
                    "%   gear - 档位 (int)\n" +
                    "%   power - 功率 (float)");
            matlabHelpRuleEntity.setParseType("regex");
            matlabHelpRuleEntity.setLanguage("matlab");
            matlabHelpRuleEntity.setIsReadonly(true);
            saveRules(matlabHelpRuleEntity);
        } catch (Exception e) {
            log.error(e.getMessage());
        }

    }

    /**
     * 保存解析规则（新增或编辑）
     * 完全参考ModelFileService.saveModelMetadata逻辑
     * 每个字段作为独立的时序序列存储，使用相同的时间戳对齐
     */
    public void saveRules(ParsingRulesEntity parsingRulesEntity) throws Exception {
        List<Point> metaPoints = new ArrayList<>();
        ParsingRulesEntity queryRule = queryRule(parsingRulesEntity.getCreateTime());
        long timestamp;
        String owner = AuthUtil.getCurrentUsername();
        if (queryRule != null && queryRule.getCreateTime() != null) {
            // 编辑情况
            timestamp = queryRule.getCreateTime();

            if (!AuthUtil.isAdmin() && !Objects.equals(owner, queryRule.getOwner())){
                throw new IllegalArgumentException("只能操作自己的规则！");
            }
            owner = queryRule.getOwner();
        } else {
            // 新增情况
            validateNameUniqueness(parsingRulesEntity.getName());
            timestamp = parsingRulesEntity.getCreateTime() == null ? System.currentTimeMillis() : parsingRulesEntity.getCreateTime();
            parsingRulesEntity.setCreateTime(timestamp);
        }
        parsingRulesEntity.setUpdateTime(System.currentTimeMillis());
        parsingRulesEntity.setOwner(owner);
        String metaBasePath = DATA_PREFIX;

        // 完全参考ModelFileService.saveModelMetadata的字段创建方式
        // 创建各个字段的数据点
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "name", parsingRulesEntity.getName(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "regexPattern", parsingRulesEntity.getRegexPattern(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "example", parsingRulesEntity.getExample(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "parseType", parsingRulesEntity.getParseType(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "language", parsingRulesEntity.getLanguage(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "isReadonly", parsingRulesEntity.getIsReadonly(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "pythonModule", parsingRulesEntity.getPythonModule(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "pythonFunction", parsingRulesEntity.getPythonFunction(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "createTime", parsingRulesEntity.getCreateTime(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "updateTime", parsingRulesEntity.getUpdateTime(), timestamp));
        metaPoints.add(ConvertUtil.createFieldPoint(metaBasePath, "owner", parsingRulesEntity.getOwner(), timestamp));

        // 批量写入元数据 - 完全参考ModelFileService的写入方式
        iginxClient.getWriteClient().writePoints(metaPoints.stream().filter(Objects::nonNull).collect(Collectors.toList()));
        log.info("解析规则已保存。名称: {}, 时间戳: {}", parsingRulesEntity.getName(), timestamp);
    }

    /**
     * 分页查询解析规则
     */
    public List<ParsingRulesEntity> queryRules(ParsingRulesQueryRequest request) {
        try {
            // 构建基础SQL
            StringBuilder sql = new StringBuilder("SELECT * FROM relational_system.parsing_rules WHERE 1=1");
            
            // 添加筛选条件
            if (request.getName() != null && !request.getName().trim().isEmpty()) {
                sql.append(" AND name LIKE '^.*").append(request.getName().trim()).append(".*'");
            }
            
            // 添加排序和分页
            sql.append(" ORDER BY updateTime DESC");
            sql.append(" LIMIT ").append(request.getPageSize());
            sql.append(" OFFSET ").append((request.getPageNum() - 1) * request.getPageSize());
            sql.append(";");
            
            log.info("执行SQL: {}", sql);
            
            SessionExecuteSqlResult res = iginxSession.executeSql(sql.toString());
            List<Map<String, Object>> records = ConvertUtil.getRecords(res);
            
            // 转换为ParsingRulesEntity列表 - 参考ModelFileService的转换方式
            List<ParsingRulesEntity> result = records.stream().map(record -> {
                ParsingRulesEntity entity = new ParsingRulesEntity();
                // 使用ConvertUtil的通用方法设置字段值 - 参考ModelFileService.queryMeta
                record.forEach((k, v) -> {
                    String fieldName = k.replace(DATA_PREFIX + ".", "");
                    ConvertUtil.setEntityField(entity, DATA_PREFIX, fieldName, v);
                });
                return entity;
            }).collect(Collectors.toList());
            
            log.info("查询结果: records={}", result.size());
            return result;
        } catch (Exception e) {
            log.error("查询失败", e);
            return new ArrayList<>();
        }
    }

    /**
     * 查询解析规则总数
     */
    public Object countRules(ParsingRulesQueryRequest request) {
        try {
            // 构建COUNT查询SQL
            StringBuilder sql = new StringBuilder("SELECT COUNT(1) FROM relational_system.parsing_rules WHERE 1=1");
            
            // 添加筛选条件
            if (request.getName() != null && !request.getName().trim().isEmpty()) {
                sql.append(" AND name LIKE '%").append(request.getName().trim()).append("%'");
            }
            sql.append(";");
            
            log.info("执行COUNT SQL: {}", sql);
            
            SessionExecuteSqlResult res = iginxSession.executeSql(sql.toString());
            
            return res.getValues().get(0).get(0);
        } catch (Exception e) {
            log.error("查询失败", e);
            return 0;
        }
    }

    /**
     * 查询解析规则详情
     * 参考queryMeta逻辑，只用createTime作为唯一标识
     */
    public ParsingRulesEntity queryRule(Long createTime) {
        try {
            String sql = "select * from %s where createTime = %s;";
            String metaBasePath = DATA_PREFIX;
            SessionExecuteSqlResult res = iginxSession.executeSql(String.format(sql, metaBasePath, createTime));
            List<Map<String, Object>> records = ConvertUtil.getRecords(res);

            if (records.isEmpty()) {
                return null;
            }

            ParsingRulesEntity entity = new ParsingRulesEntity();
            Map<String, Object> rs = records.get(0);
            // 使用ConvertUtil的通用方法设置字段值
            rs.forEach((k, v) -> {
                String fieldName = k.replace(DATA_PREFIX + ".", "");
                ConvertUtil.setEntityField(entity, DATA_PREFIX, fieldName, v);
            });
            return entity;
        } catch (Exception e) {
            log.error("查询解析规则失败", e);
            return null;
        }
    }

    /**
     * 删除解析规则
     * 参考deleteModel逻辑，只用createTime作为唯一标识
     */
    public void deleteRule(Long createTime) throws Exception {
        ParsingRulesEntity queryRule = queryRule(createTime);
        if (queryRule == null) {
            throw new IllegalArgumentException("规则不存在");
        }
        // 禁止删除只读预置规则
        if (queryRule.getIsReadonly() != null && queryRule.getIsReadonly()) {
            throw new IllegalArgumentException("系统预置规则不可删除");
        }
        if (!AuthUtil.isAdmin()) {
            String owner = AuthUtil.getCurrentUsername();
            if (!Objects.equals(owner, queryRule.getOwner())) {
                throw new IllegalArgumentException("只能操作自己的规则！");
            }
        }
        List<String> measurements = ConvertUtil.iginxFieldNamesConvert(ParsingRulesEntity.class, DATA_PREFIX);
        // 删除指定时间戳的数据
        iginxClient.getDeleteClient().deleteMeasurementsData(measurements, createTime - 1, createTime + 1);
        log.info("已删除解析规则: createTime: {}", createTime);
    }

    /**
     * 校验名称唯一性（仅用于新增）
     * @param name 规则名称
     * @throws Exception 如果名称已存在则抛出异常
     */
    public void validateNameUniqueness(String name) throws Exception {
        if (name == null || name.trim().isEmpty()) {
            throw new Exception("规则名称不能为空");
        }

        // 查询是否存在同名规则
        StringBuilder sql = new StringBuilder("SELECT createTime FROM relational_system.parsing_rules WHERE name = '");
        sql.append(name.trim()).append("' LIMIT 1;");
        
        log.info("执行名称唯一性校验SQL: {}", sql);
        
        SessionExecuteSqlResult res = iginxSession.executeSql(sql.toString());
        List<Map<String, Object>> records = ConvertUtil.getRecords(res);
        
        if (!records.isEmpty()) {
            throw new Exception("规则名称 '" + name + "' 已存在，请使用其他名称");
        }
    }

    // ========== 通用源码解析 ==========

    /**
     * 轻量级源码扫描器：按行读取文件前N行，匹配特定前缀
     * 支持regex、typehint、inspect三种解析模式
     *
     * @param fileContent 文件内容
     * @param fileName    文件名（用于判断语言）
     * @param regexPattern 正则表达式（regex模式使用）
     * @param parseType   解析类型：regex / typehint / inspect
     * @param maxLines    最大扫描行数
     * @return 解析结果，包含apis列表
     */
    public Map<String, Object> headerScanner(String fileContent, String fileName,
                                                 String regexPattern, String parseType,
                                                 int maxLines) {
        Map<String, Object> result = new HashMap<>();
        List<Map<String, Object>> apis = new ArrayList<>();

        if (fileContent == null || fileContent.trim().isEmpty()) {
            result.put("apis", apis);
            result.put("message", "文件内容为空");
            return result;
        }

        String[] lines = fileContent.split("\n");
        int scanLines = Math.min(lines.length, maxLines > 0 ? maxLines : 50);

        switch (parseType != null ? parseType : "regex") {
            case "regex":
                apis = parseWithRegex(lines, scanLines, regexPattern, fileName);
                break;
            case "typehint":
                apis = parseWithTypeHint(lines, scanLines, fileName);
                break;
            case "inspect":
                Map<String, Object> inspectApi = new HashMap<>();
                inspectApi.put("name", "inspect_parse_pending");
                inspectApi.put("description", "Python inspect模式需要在Python运行环境中执行");
                inspectApi.put("inputs", new ArrayList<>());
                inspectApi.put("outputs", new ArrayList<>());
                apis.add(inspectApi);
                break;
            default:
                apis = parseWithRegex(lines, scanLines, regexPattern, fileName);
        }

        result.put("apis", apis);
        result.put("fileName", fileName);
        result.put("parseType", parseType);
        result.put("scannedLines", scanLines);
        return result;
    }

    private List<Map<String, Object>> parseWithRegex(String[] lines, int scanLines,
                                                      String regexPattern, String fileName) {
        List<Map<String, Object>> apis = new ArrayList<>();
        if (regexPattern == null || regexPattern.trim().isEmpty()) {
            return apis;
        }

        List<Map<String, Object>> inputs = new ArrayList<>();
        List<Map<String, Object>> outputs = new ArrayList<>();
        java.util.regex.Pattern pattern;
        try {
            pattern = java.util.regex.Pattern.compile(regexPattern);
        } catch (Exception e) {
            log.warn("正则表达式编译失败: {}", regexPattern, e);
            return apis;
        }

        int groupCount = 0;
        try {
            java.util.regex.Matcher testMatcher = pattern.matcher("");
            groupCount = testMatcher.groupCount();
        } catch (Exception ignored) {}

        for (int i = 0; i < scanLines; i++) {
            String line = lines[i];
            try {
                java.util.regex.Matcher matcher = pattern.matcher(line);
                if (matcher.find()) {
                    Map<String, Object> param = new HashMap<>();
                    String paramType = "";
                    String paramName = "";
                    String dataType = "";
                    String desc = "";

                    if (groupCount == 2) {
                        paramName = nvl(matcher.group(1));
                        String descWithType = nvl(matcher.group(2));
                        java.util.regex.Matcher typeInDesc = java.util.regex.Pattern.compile("\\(([^)]+)\\)").matcher(descWithType);
                        if (typeInDesc.find()) {
                            dataType = typeInDesc.group(1).trim();
                            desc = descWithType.replace(typeInDesc.group(0), "").replace("-", "").trim();
                        } else {
                            desc = descWithType;
                        }
                        paramType = "input";
                    } else if (groupCount == 3) {
                        String g1 = nvl(matcher.group(1));
                        String g2 = nvl(matcher.group(2));
                        String g3 = nvl(matcher.group(3));
                        if (isTypeMarker(g1)) {
                            paramType = g1;
                            java.util.regex.Matcher nameType = java.util.regex.Pattern.compile("(\\w+)\\s+(\\w+)").matcher(g2);
                            if (nameType.find()) {
                                dataType = nameType.group(1).trim();
                                paramName = nameType.group(2).trim();
                            } else {
                                paramName = g2.trim();
                            }
                            desc = g3.trim();
                        } else {
                            paramName = g1.trim();
                            dataType = g2.trim();
                            desc = g3.trim();
                            paramType = "input";
                        }
                    } else if (groupCount == 5) {
                        paramType = nvl(matcher.group(1));
                        String direction = nvl(matcher.group(2));
                        paramName = nvl(matcher.group(3));
                        dataType = nvl(matcher.group(4));
                        desc = nvl(matcher.group(5));
                        if (!direction.isEmpty()) {
                            paramType = direction;
                        }
                    } else {
                        paramType = nvl(matcher.group(1));
                        paramName = nvl(matcher.group(2));
                        dataType = nvl(matcher.group(3));
                        desc = nvl(matcher.group(4));
                    }

                    param.put("name", paramName.trim());
                    param.put("type", normalizeDataType(dataType.trim()));
                    param.put("unit", "");
                    param.put("desc", desc.trim());
                    param.put("line", i + 1);

                    String pt = paramType.toLowerCase();
                    if (pt.contains("input") || pt.contains("param") || pt.contains("in") || pt.contains("arg")) {
                        inputs.add(param);
                    } else if (pt.contains("output") || pt.contains("return") || pt.contains("out") || pt.contains("rtype")) {
                        outputs.add(param);
                    } else {
                        inputs.add(param);
                    }
                }
            } catch (Exception e) {
                log.debug("第{}行正则匹配异常: {}", i + 1, e.getMessage());
            }
        }

        if (!inputs.isEmpty() || !outputs.isEmpty()) {
            Map<String, Object> api = new HashMap<>();
            api.put("name", extractApiName(fileName));
            api.put("description", "从" + fileName + "自动提取的API");
            api.put("inputs", inputs);
            api.put("outputs", outputs);
            apis.add(api);
        }
        return apis;
    }

    private List<Map<String, Object>> parseWithTypeHint(String[] lines, int scanLines, String fileName) {
        List<Map<String, Object>> apis = new ArrayList<>();
        java.util.regex.Pattern funcPattern;
        try {
            funcPattern = java.util.regex.Pattern.compile(
                "^\\s*def\\s+(\\w+)\\s*\\(([^)]*)\\)\\s*(?:->\\s*([^:]+))?\\s*:\\s*(?:#.*)?$");
        } catch (Exception e) {
            log.warn("TypeHint正则编译失败", e);
            return apis;
        }

        java.util.regex.Pattern paramPattern;
        try {
            paramPattern = java.util.regex.Pattern.compile(
                "\\s*(\\w+)\\s*(?::\\s*([^,=]+?))?\\s*(?:=[^,]*)?\\s*(?:,|$)");
        } catch (Exception e) {
            log.warn("参数正则编译失败", e);
            return apis;
        }

        for (int i = 0; i < scanLines; i++) {
            String line = lines[i];
            java.util.regex.Matcher funcMatcher = funcPattern.matcher(line);
            if (funcMatcher.find()) {
                String funcName = funcMatcher.group(1);
                String paramsStr = funcMatcher.group(2);
                String returnType = funcMatcher.group(3);

                List<Map<String, Object>> inputs = new ArrayList<>();
                List<Map<String, Object>> outputs = new ArrayList<>();

                if (paramsStr != null && !paramsStr.trim().isEmpty()) {
                    java.util.regex.Matcher paramMatcher = paramPattern.matcher(paramsStr);
                    while (paramMatcher.find()) {
                        String pName = paramMatcher.group(1);
                        String pType = paramMatcher.group(2);
                        if (pName != null && !pName.equals("self") && !pName.equals("cls")) {
                            Map<String, Object> param = new HashMap<>();
                            param.put("name", pName.trim());
                            param.put("type", normalizeDataType(pType != null ? pType.trim() : ""));
                            param.put("unit", "");
                            param.put("desc", "");
                            inputs.add(param);
                        }
                    }
                }

                if (returnType != null && !returnType.trim().isEmpty() && !returnType.trim().equals("None")) {
                    Map<String, Object> outParam = new HashMap<>();
                    outParam.put("name", "result");
                    outParam.put("type", normalizeDataType(returnType.trim()));
                    outParam.put("unit", "");
                    outParam.put("desc", "");
                    outputs.add(outParam);
                }

                if (!inputs.isEmpty() || !outputs.isEmpty()) {
                    Map<String, Object> api = new HashMap<>();
                    api.put("name", funcName);
                    api.put("description", "函数 " + funcName);
                    api.put("inputs", inputs);
                    api.put("outputs", outputs);
                    apis.add(api);
                }
            }
        }
        return apis;
    }

    private boolean isTypeMarker(String value) {
        if (value == null || value.trim().isEmpty()) return false;
        String lower = value.toLowerCase().trim();
        return lower.equals("param") || lower.equals("return") || lower.equals("returns")
                || lower.equals("type") || lower.equals("rtype");
    }

    private String nvl(String value) {
        return value != null ? value : "";
    }

    private String extractApiName(String fileName) {
        if (fileName == null) return "unknown";
        int dotIdx = fileName.lastIndexOf('.');
        return dotIdx > 0 ? fileName.substring(0, dotIdx) : fileName;
    }

    private String normalizeDataType(String dataType) {
        if (dataType == null || dataType.trim().isEmpty()) return "String";
        String lower = dataType.toLowerCase().replaceAll("[\\[\\](){}]", "");
        switch (lower) {
            case "float": return "Float";
            case "double": return "Double";
            case "int": case "integer": return "Integer";
            case "long": return "Long";
            case "bool": case "boolean": return "Boolean";
            case "str": case "string": return "String";
            case "list": case "dict": case "tuple":
            case "vector": case "array": return "String";
            case "none": return "String";
            default: return "String";
        }
    }

}
