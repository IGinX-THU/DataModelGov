package com.tsinghua.service;

import com.tsinghua.dto.Result;
import com.tsinghua.util.ThriftCodeGenerator;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.io.*;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.HashMap;
import java.util.Map;

/**
 * API代码生成服务
 * 支持基于Thrift IDL生成Java、Go、Python和RESTful API代码
 */
@Slf4j
@Service
public class ApiGenerationService {

    private static final String THRIFT_FILE_PATH = "src/main/resources/thrift/api.thrift";
    private static final String OUTPUT_BASE_DIR = "generated-api";

    /**
     * 生成Java代码
     */
    public Result<?> generateJavaCode() {
        try {
            String outputDir = OUTPUT_BASE_DIR + "/java";
            createOutputDirectory(outputDir);
            
            // 使用ThriftCodeGenerator工具类
            ThriftCodeGenerator.GenerationResult result = ThriftCodeGenerator.generateCode(
                "java", THRIFT_FILE_PATH, outputDir
            );
            
            if (result.isSuccess()) {
                return Result.success("Java代码生成成功，输出目录: " + outputDir, outputDir);
            } else {
                return Result.error("Java代码生成失败: " + result.getMessage());
            }
        } catch (Exception e) {
            log.error("生成Java代码失败", e);
            return Result.error("生成Java代码失败: " + e.getMessage());
        }
    }

    /**
     * 生成Go代码
     */
    public Result<?> generateGoCode() {
        try {
            String outputDir = OUTPUT_BASE_DIR + "/go";
            createOutputDirectory(outputDir);
            
            // 使用ThriftCodeGenerator工具类
            ThriftCodeGenerator.GenerationResult result = ThriftCodeGenerator.generateCode(
                "go", THRIFT_FILE_PATH, outputDir
            );
            
            if (result.isSuccess()) {
                // 生成Go模块文件
                generateGoModFile(outputDir);
                return Result.success("Go代码生成成功，输出目录: " + outputDir, outputDir);
            } else {
                return Result.error("Go代码生成失败: " + result.getMessage());
            }
        } catch (Exception e) {
            log.error("生成Go代码失败", e);
            return Result.error("生成Go代码失败: " + e.getMessage());
        }
    }

    /**
     * 生成Python代码
     */
    public Result<?> generatePythonCode() {
        try {
            String outputDir = OUTPUT_BASE_DIR + "/python";
            createOutputDirectory(outputDir);
            
            // 使用ThriftCodeGenerator工具类
            ThriftCodeGenerator.GenerationResult result = ThriftCodeGenerator.generateCode(
                "py", THRIFT_FILE_PATH, outputDir
            );
            
            if (result.isSuccess()) {
                // 生成Python requirements文件
                generatePythonRequirements(outputDir);
                return Result.success("Python代码生成成功，输出目录: " + outputDir, outputDir);
            } else {
                return Result.error("Python代码生成失败: " + result.getMessage());
            }
        } catch (Exception e) {
            log.error("生成Python代码失败", e);
            return Result.error("生成Python代码失败: " + e.getMessage());
        }
    }

    /**
     * 生成RESTful API代码
     */
    public Result<?> generateRestfulApiCode() {
        try {
            String outputDir = OUTPUT_BASE_DIR + "/restful";
            createOutputDirectory(outputDir);
            
            // 生成Spring Boot RESTful API
            generateSpringBootController(outputDir);
            generateOpenApiSpec(outputDir);
            
            return Result.success("RESTful API代码生成成功，输出目录: " + outputDir, outputDir);
        } catch (Exception e) {
            log.error("生成RESTful API代码失败", e);
            return Result.error("生成RESTful API代码失败: " + e.getMessage());
        }
    }

    /**
     * 生成所有语言的代码
     */
    public Result<Map<String, String>> generateAllCode() {
        Map<String, String> results = new HashMap<>();
        
        Result<?> javaResult = generateJavaCode();
        results.put("java", javaResult.getSuccess() ? "成功" : javaResult.getMessage());
        
        Result<?> goResult = generateGoCode();
        results.put("go", goResult.getSuccess() ? "成功" : goResult.getMessage());
        
        Result<?> pythonResult = generatePythonCode();
        results.put("python", pythonResult.getSuccess() ? "成功" : pythonResult.getMessage());
        
        Result<?> restfulResult = generateRestfulApiCode();
        results.put("restful", restfulResult.getSuccess() ? "成功" : restfulResult.getMessage());
        
        return Result.success(results);
    }

    /**
     * 创建输出目录
     */
    private void createOutputDirectory(String dirPath) throws IOException {
        Path path = Paths.get(dirPath);
        if (!Files.exists(path)) {
            Files.createDirectories(path);
        }
    }

    /**
     * 生成Go模块文件
     */
    private void generateGoModFile(String outputDir) throws IOException {
        String goModContent = "module tsinghua-api\n\n" +
            "go 1.19\n\n" +
            "require (\n" +
            "    github.com/apache/thrift v0.22.0\n" +
            "    github.com/gorilla/mux v1.8.0\n" +
            ")\n";
        
        Files.write(Paths.get(outputDir, "go.mod"), goModContent.getBytes());
    }

    /**
     * 生成Python requirements文件
     */
    private void generatePythonRequirements(String outputDir) throws IOException {
        String requirementsContent = "thrift==0.22.0\n" +
            "flask==2.3.2\n" +
            "flask-restful==0.3.10\n";
        
        Files.write(Paths.get(outputDir, "requirements.txt"), requirementsContent.getBytes());
    }

    /**
     * 生成Spring Boot RESTful控制器
     */
    private void generateSpringBootController(String outputDir) throws IOException {
        String controllerContent = generateControllerTemplate();
        Files.write(Paths.get(outputDir, "ApiController.java"), controllerContent.getBytes());
    }

    /**
     * 生成OpenAPI规范文件
     */
    private void generateOpenApiSpec(String outputDir) throws IOException {
        String openApiContent = generateOpenApiTemplate();
        Files.write(Paths.get(outputDir, "openapi.yaml"), openApiContent.getBytes());
    }

    /**
     * Spring Boot控制器模板 - 按照现有Controller接口生成
     */
    private String generateControllerTemplate() {
        return "package com.tsinghua.api.controller;\n\n" +
            "import com.fasterxml.jackson.databind.JsonNode;\n" +
            "import com.fasterxml.jackson.databind.ObjectMapper;\n" +
            "import com.tsinghua.dto.*;\n" +
            "import com.tsinghua.dto.request.*;\n" +
            "import com.tsinghua.entity.AssociationRulesEntity;\n" +
            "import com.tsinghua.entity.ModelMetaEntity;\n" +
            "import com.tsinghua.service.*;\n" +
            "import io.swagger.annotations.Api;\n" +
            "import io.swagger.annotations.ApiOperation;\n" +
            "import lombok.extern.slf4j.Slf4j;\n" +
            "import org.springframework.beans.factory.annotation.Autowired;\n" +
            "import org.springframework.validation.annotation.Validated;\n" +
            "import org.springframework.web.bind.annotation.*;\n" +
            "import java.util.List;\n" +
            "import java.util.Map;\n\n" +
            "@Slf4j\n" +
            "@Api(tags = \"API接口\")\n" +
            "@RestController\n" +
            "@RequestMapping(\"/api/v1\")\n" +
            "public class ApiController {\n\n" +
            "    @Autowired\n" +
            "    private AssociationRulesService associationRulesService;\n\n" +
            "    @Autowired\n" +
            "    private DataSourceService dataSourceService;\n\n" +
            "    @Autowired\n" +
            "    private DataTableService dataTableService;\n\n" +
            "    @Autowired\n" +
            "    private RelationalDataService relationalDataService;\n\n" +
            "    @Autowired\n" +
            "    private ModelFileService modelFileService;\n\n" +
            "    // ========== 关联规则接口 ==========\n" +
            "    @ApiOperation(\"创建关联规则\")\n" +
            "    @PostMapping(\"/association/rules/save\")\n" +
            "    public Result<Void> saveRules(@RequestBody AssociationRulesEntity associationRulesEntity) throws Exception {\n" +
            "        associationRulesService.saveRules(associationRulesEntity);\n" +
            "        return Result.success(\"关联规则保存成功\");\n" +
            "    }\n\n" +
            "    @ApiOperation(\"分页查询关联规则\")\n" +
            "    @PostMapping(\"/association/rules/query\")\n" +
            "    public Result<List<AssociationRulesEntity>> queryRules(@RequestBody AssociationRulesQueryRequest request) {\n" +
            "        List<AssociationRulesEntity> result = associationRulesService.queryRules(request);\n" +
            "        return Result.success(result);\n" +
            "    }\n\n" +
            "    @ApiOperation(\"查询关联规则总数\")\n" +
            "    @PostMapping(\"/association/rules/count\")\n" +
            "    public Result<Object> countRules(@RequestBody AssociationRulesQueryRequest request) {\n" +
            "        Object count = associationRulesService.countRules(request);\n" +
            "        return Result.success(count);\n" +
            "    }\n\n" +
            "    @ApiOperation(\"关联规则详情\")\n" +
            "    @GetMapping(\"/association/rules/detail\")\n" +
            "    public Result<?> queryRule(@RequestParam(\"createTime\") Long createTime) {\n" +
            "        AssociationRulesEntity result = associationRulesService.queryRule(createTime);\n" +
            "        if (result == null) {\n" +
            "            return Result.error(\"未找到指定的关联规则\");\n" +
            "        }\n" +
            "        return Result.success(result);\n" +
            "    }\n\n" +
            "    @ApiOperation(\"删除关联规则\")\n" +
            "    @DeleteMapping(\"/association/rules/delete\")\n" +
            "    public Result<Void> deleteRule(@RequestParam(\"createTime\") Long createTime) throws Exception {\n" +
            "        associationRulesService.deleteRule(createTime);\n" +
            "        return Result.success(\"操作成功\");\n" +
            "    }\n\n" +
            "    // ========== 数据源接口 ==========\n" +
            "    @ApiOperation(\"注册异构数据源\")\n" +
            "    @PostMapping(\"/datasource/register\")\n" +
            "    public Result<Void> register(@RequestBody String jsonBody) throws Exception {\n" +
            "        log.info(\"jsonBody:{}\", jsonBody);\n" +
            "        ObjectMapper mapper = new ObjectMapper();\n" +
            "        mapper.configure(com.fasterxml.jackson.databind.DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false);\n" +
            "        JsonNode rootNode = mapper.readTree(jsonBody);\n" +
            "        \n" +
            "        JsonNode storageEngineTypeNode = rootNode.get(\"storageEngineType\");\n" +
            "        if (storageEngineTypeNode == null || !storageEngineTypeNode.isInt()) {\n" +
            "            return Result.error(\"storageEngineType is required and must be an integer\");\n" +
            "        }\n" +
            "        \n" +
            "        int storageEngineType = storageEngineTypeNode.asInt();\n" +
            "        \n" +
            "        BaseStorageEngineRequest request;\n" +
            "        switch (storageEngineType) {\n" +
            "            case 1:\n" +
            "                request = mapper.treeToValue(rootNode, Iotdb12StorageRequest.class);\n" +
            "                break;\n" +
            "            case 2:\n" +
            "                request = mapper.treeToValue(rootNode, InfluxdbStorageRequest.class);\n" +
            "                break;\n" +
            "            case 3:\n" +
            "                request = mapper.treeToValue(rootNode, FilesystemStorageRequest.class);\n" +
            "                break;\n" +
            "            case 4:\n" +
            "                request = mapper.treeToValue(rootNode, RelationalStorageRequest.class);\n" +
            "                break;\n" +
            "            case 5:\n" +
            "                request = mapper.treeToValue(rootNode, MongodbStorageRequest.class);\n" +
            "                break;\n" +
            "            case 6:\n" +
            "                request = mapper.treeToValue(rootNode, RedisStorageRequest.class);\n" +
            "                break;\n" +
            "            default:\n" +
            "                return Result.error(\"Unknown storage engine type: \" + storageEngineType);\n" +
            "        }\n" +
            "        \n" +
            "        boolean success = dataSourceService.registerDataSource(request);\n" +
            "        return success ? Result.success(\"数据源注册成功\") : Result.error(\"注册失败，请检查配置\");\n" +
            "    }\n\n" +
            "    @ApiOperation(\"移除异构数据源\")\n" +
            "    @PostMapping(\"/datasource/remove\")\n" +
            "    public Result<Void> remove(@Validated @RequestBody StorageEngineInfoDto removedStorageEngineInfo) throws Exception {\n" +
            "        boolean success = dataSourceService.removeDataSource(removedStorageEngineInfo);\n" +
            "        return success ? Result.success(\"数据源移除成功\") : Result.error(\"移除失败，数据源可能被关联规则占用\");\n" +
            "    }\n\n" +
            "    @ApiOperation(\"数据资源列表\")\n" +
            "    @GetMapping(\"/datasource/list\")\n" +
            "    public Result<List<StorageEngineInfoDto>> list() throws Exception {\n" +
            "        return Result.success(dataSourceService.dataSourceList());\n" +
            "    }\n\n" +
            "    // ========== 数据表接口 ==========\n" +
            "    @ApiOperation(\"数据查询\")\n" +
            "    @PostMapping(\"/data/query\")\n" +
            "    public Result<TableDto> queryData(@Validated @RequestBody DataQueryRequest request) {\n" +
            "        return Result.success(dataTableService.queryData(request));\n" +
            "    }\n\n" +
            "    @ApiOperation(\"关系数据查询\")\n" +
            "    @PostMapping(\"/data-tables/query\")\n" +
            "    public Result<List<TableDto>> query(@RequestBody RelationalQueryRequest request) throws Exception {\n" +
            "        List<TableDto> result = relationalDataService.queryTables(request);\n" +
            "        return Result.success(result);\n" +
            "    }\n\n" +
            "    // ========== 模型文件接口 ==========\n" +
            "    @ApiOperation(\"模型元数据详情\")\n" +
            "    @GetMapping(\"/model/metas\")\n" +
            "    public Result<ModelMetaEntity> queryMeta(@RequestParam(\"name\") String name, @RequestParam(\"version\") String version) throws Exception {\n" +
            "        ModelMetaEntity result = modelFileService.queryMeta(name, version);\n" +
            "        return Result.success(result);\n" +
            "    }\n\n" +
            "    @ApiOperation(\"保存模型元数据\")\n" +
            "    @PostMapping(\"/model/metas\")\n" +
            "    public Result<Void> saveMeta(@RequestBody ModelMetaEntity modelMetaDto) throws Exception {\n" +
            "        modelFileService.saveModelMetadata(modelMetaDto);\n" +
            "        return Result.success(\"模型元数据保存成功\");\n" +
            "    }\n\n" +
            "    @ApiOperation(\"模型文件删除\")\n" +
            "    @DeleteMapping(\"/model/delete\")\n" +
            "    public Result<Void> delete(@RequestParam String name, @RequestParam String version) throws Exception {\n" +
            "        modelFileService.deleteModel(name, version);\n" +
            "        return Result.success(\"模型文件删除成功\");\n" +
            "    }\n" +
            "}\n";
    }

    /**
     * OpenAPI规范模板 - 按照现有接口生成
     */
    private String generateOpenApiTemplate() {
        return "openapi: 3.0.0\n" +
            "info:\n" +
            "  title: Data Model Gov API\n" +
            "  version: 1.0.0\n" +
            "  description: 数据与模型一体化管理API\n" +
            "servers:\n" +
            "  - url: http://localhost:8080/api/v1\n" +
            "    description: 本地开发服务器\n" +
            "paths:\n" +
            "  /association/rules/save:\n" +
            "    post:\n" +
            "      summary: 创建关联规则\n" +
            "      operationId: saveRules\n" +
            "      requestBody:\n" +
            "        required: true\n" +
            "        content:\n" +
            "          application/json:\n" +
            "            schema:\n" +
            "              $ref: '#/components/schemas/AssociationRule'\n" +
            "      responses:\n" +
            "        '200':\n" +
            "          description: 成功\n" +
            "          content:\n" +
            "            application/json:\n" +
            "              schema:\n" +
            "                $ref: '#/components/schemas/Result'\n" +
            "  /association/rules/query:\n" +
            "    post:\n" +
            "      summary: 分页查询关联规则\n" +
            "      operationId: queryRules\n" +
            "      requestBody:\n" +
            "        required: true\n" +
            "        content:\n" +
            "          application/json:\n" +
            "            schema:\n" +
            "              $ref: '#/components/schemas/AssociationRulesQueryRequest'\n" +
            "      responses:\n" +
            "        '200':\n" +
            "          description: 成功\n" +
            "  /association/rules/count:\n" +
            "    post:\n" +
            "      summary: 查询关联规则总数\n" +
            "      operationId: countRules\n" +
            "      requestBody:\n" +
            "        required: true\n" +
            "        content:\n" +
            "          application/json:\n" +
            "            schema:\n" +
            "              $ref: '#/components/schemas/AssociationRulesQueryRequest'\n" +
            "      responses:\n" +
            "        '200':\n" +
            "          description: 成功\n" +
            "  /association/rules/detail:\n" +
            "    get:\n" +
            "      summary: 关联规则详情\n" +
            "      operationId: queryRule\n" +
            "      parameters:\n" +
            "        - name: createTime\n" +
            "          in: query\n" +
            "          required: true\n" +
            "          schema:\n" +
            "            type: integer\n" +
            "      responses:\n" +
            "        '200':\n" +
            "          description: 成功\n" +
            "  /association/rules/delete:\n" +
            "    delete:\n" +
            "      summary: 删除关联规则\n" +
            "      operationId: deleteRule\n" +
            "      parameters:\n" +
            "        - name: createTime\n" +
            "          in: query\n" +
            "          required: true\n" +
            "          schema:\n" +
            "            type: integer\n" +
            "      responses:\n" +
            "        '200':\n" +
            "          description: 成功\n" +
            "  /datasource/register:\n" +
            "    post:\n" +
            "      summary: 注册异构数据源\n" +
            "      operationId: register\n" +
            "      requestBody:\n" +
            "        required: true\n" +
            "        content:\n" +
            "          application/json:\n" +
            "            schema:\n" +
            "              type: string\n" +
            "      responses:\n" +
            "        '200':\n" +
            "          description: 成功\n" +
            "  /datasource/remove:\n" +
            "    post:\n" +
            "      summary: 移除异构数据源\n" +
            "      operationId: remove\n" +
            "      requestBody:\n" +
            "        required: true\n" +
            "        content:\n" +
            "          application/json:\n" +
            "            schema:\n" +
            "              type: string\n" +
            "      responses:\n" +
            "        '200':\n" +
            "          description: 成功\n" +
            "  /datasource/list:\n" +
            "    get:\n" +
            "      summary: 数据资源列表\n" +
            "      operationId: list\n" +
            "      responses:\n" +
            "        '200':\n" +
            "          description: 成功\n" +
            "  /data-tables/query:\n" +
            "    post:\n" +
            "      summary: 数据表查询\n" +
            "      operationId: query\n" +
            "      requestBody:\n" +
            "        required: true\n" +
            "        content:\n" +
            "          application/json:\n" +
            "            schema:\n" +
            "              $ref: '#/components/schemas/RelationalQueryRequest'\n" +
            "      responses:\n" +
            "        '200':\n" +
            "          description: 成功\n" +
            "  /model/save:\n" +
            "    post:\n" +
            "      summary: 模型文件保存\n" +
            "      operationId: save\n" +
            "      requestBody:\n" +
            "        required: true\n" +
            "        content:\n" +
            "          application/json:\n" +
            "            schema:\n" +
            "              type: object\n" +
            "      responses:\n" +
            "        '200':\n" +
            "          description: 成功\n" +
            "  /model/query:\n" +
            "    get:\n" +
            "      summary: 模型文件查询\n" +
            "      operationId: query\n" +
            "      parameters:\n" +
            "        - name: name\n" +
            "          in: query\n" +
            "          schema:\n" +
            "            type: string\n" +
            "      responses:\n" +
            "        '200':\n" +
            "          description: 成功\n" +
            "  /model/delete:\n" +
            "    delete:\n" +
            "      summary: 模型文件删除\n" +
            "      operationId: delete\n" +
            "      parameters:\n" +
            "        - name: name\n" +
            "          in: query\n" +
            "          required: true\n" +
            "          schema:\n" +
            "            type: string\n" +
            "      responses:\n" +
            "        '200':\n" +
            "          description: 成功\n" +
            "components:\n" +
            "  schemas:\n" +
            "    Result:\n" +
            "      type: object\n" +
            "      properties:\n" +
            "        success:\n" +
            "          type: boolean\n" +
            "        message:\n" +
            "          type: string\n" +
            "        data:\n" +
            "          type: object\n" +
            "    AssociationRule:\n" +
            "      type: object\n" +
            "      properties:\n" +
            "        createTime:\n" +
            "          type: integer\n" +
            "        ruleName:\n" +
            "          type: string\n" +
            "        ruleDescription:\n" +
            "          type: string\n" +
            "        sourceTable:\n" +
            "          type: string\n" +
            "        targetTable:\n" +
            "          type: string\n" +
            "        joinCondition:\n" +
            "          type: string\n" +
            "        ruleType:\n" +
            "          type: string\n" +
            "        enabled:\n" +
            "          type: boolean\n" +
            "    AssociationRulesQueryRequest:\n" +
            "      type: object\n" +
            "      properties:\n" +
            "        pageInfo:\n" +
            "          $ref: '#/components/schemas/PageInfo'\n" +
            "        ruleName:\n" +
            "          type: string\n" +
            "        ruleType:\n" +
            "          type: string\n" +
            "        enabled:\n" +
            "          type: boolean\n" +
            "    RelationalQueryRequest:\n" +
            "      type: object\n" +
            "      properties:\n" +
            "        database:\n" +
            "          type: string\n" +
            "        table:\n" +
            "          type: string\n" +
            "    PageInfo:\n" +
            "      type: object\n" +
            "      properties:\n" +
            "        page:\n" +
            "          type: integer\n" +
            "          default: 1\n" +
            "        size:\n" +
            "          type: integer\n" +
            "          default: 10\n" +
            "        total:\n" +
            "          type: integer\n";
    }
}
