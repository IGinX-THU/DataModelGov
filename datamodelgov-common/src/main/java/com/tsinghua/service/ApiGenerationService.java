package com.tsinghua.service;

import com.tsinghua.model.Result;
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
            String serverOutputDir = OUTPUT_BASE_DIR + "/java/server";
            String clientOutputDir = OUTPUT_BASE_DIR + "/java/client";
            
            // 先创建父目录，再创建子目录
            createOutputDirectory(OUTPUT_BASE_DIR + "/java");
            createOutputDirectory(serverOutputDir);
            createOutputDirectory(clientOutputDir);
            
            // 生成Server端代码
            ThriftCodeGenerator.GenerationResult serverResult = ThriftCodeGenerator.generateJavaServer(
                THRIFT_FILE_PATH, serverOutputDir
            );
            
            // 生成Client端代码
            ThriftCodeGenerator.GenerationResult clientResult = ThriftCodeGenerator.generateJavaClient(
                THRIFT_FILE_PATH, clientOutputDir
            );
            
            // 生成Server端实现
            if (serverResult.isSuccess()) {
                generateJavaServerImplementation(serverOutputDir);
            }
            
            // 生成Client端示例
            if (clientResult.isSuccess()) {
                generateJavaClientExample(clientOutputDir);
            }
            
            if (serverResult.isSuccess() && clientResult.isSuccess()) {
                return Result.success("Java代码生成成功，Server端: " + serverOutputDir + ", Client端: " + clientOutputDir);
            } else {
                return Result.error("Java代码生成失败: " + 
                    (serverResult.isSuccess() ? "" : serverResult.getMessage() + "; ") +
                    (clientResult.isSuccess() ? "" : clientResult.getMessage()));
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
            String serverOutputDir = OUTPUT_BASE_DIR + "/go/server";
            String clientOutputDir = OUTPUT_BASE_DIR + "/go/client";
            
            // 先创建父目录，再创建子目录
            createOutputDirectory(OUTPUT_BASE_DIR + "/go");
            createOutputDirectory(serverOutputDir);
            createOutputDirectory(clientOutputDir);
            
            // 生成Server端代码
            ThriftCodeGenerator.GenerationResult serverResult = ThriftCodeGenerator.generateGoServer(
                THRIFT_FILE_PATH, serverOutputDir
            );
            
            // 生成Client端代码
            ThriftCodeGenerator.GenerationResult clientResult = ThriftCodeGenerator.generateGoClient(
                THRIFT_FILE_PATH, clientOutputDir
            );
            
            // 生成Go模块文件
            if (serverResult.isSuccess()) {
                generateGoModFile(serverOutputDir);
                generateGoServerImplementation(serverOutputDir);
            }
            
            if (clientResult.isSuccess()) {
                generateGoModFile(clientOutputDir);
                generateGoClientExample(clientOutputDir);
            }
            
            if (serverResult.isSuccess() && clientResult.isSuccess()) {
                return Result.success("Go代码生成成功，Server端: " + serverOutputDir + ", Client端: " + clientOutputDir);
            } else {
                return Result.error("Go代码生成失败: " + 
                    (serverResult.isSuccess() ? "" : serverResult.getMessage() + "; ") +
                    (clientResult.isSuccess() ? "" : clientResult.getMessage()));
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
            String serverOutputDir = OUTPUT_BASE_DIR + "/python/server";
            String clientOutputDir = OUTPUT_BASE_DIR + "/python/client";
            
            // 先创建父目录，再创建子目录
            createOutputDirectory(OUTPUT_BASE_DIR + "/python");
            createOutputDirectory(serverOutputDir);
            createOutputDirectory(clientOutputDir);
            
            // 生成Server端代码
            ThriftCodeGenerator.GenerationResult serverResult = ThriftCodeGenerator.generatePythonServer(
                THRIFT_FILE_PATH, serverOutputDir
            );
            
            // 生成Client端代码
            ThriftCodeGenerator.GenerationResult clientResult = ThriftCodeGenerator.generatePythonClient(
                THRIFT_FILE_PATH, clientOutputDir
            );
            
            // 生成Python requirements文件
            if (serverResult.isSuccess()) {
                generatePythonRequirements(serverOutputDir);
                generatePythonServerImplementation(serverOutputDir);
            }
            
            if (clientResult.isSuccess()) {
                generatePythonRequirements(clientOutputDir);
                generatePythonClientExample(clientOutputDir);
            }
            
            if (serverResult.isSuccess() && clientResult.isSuccess()) {
                return Result.success("Python代码生成成功，Server端: " + serverOutputDir + ", Client端: " + clientOutputDir);
            } else {
                return Result.error("Python代码生成失败: " + 
                    (serverResult.isSuccess() ? "" : serverResult.getMessage() + "; ") +
                    (clientResult.isSuccess() ? "" : clientResult.getMessage()));
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
            log.info("创建目录: {}", dirPath);
        }
    }

    /**
     * 生成Java Server端实现
     */
    private void generateJavaServerImplementation(String outputDir) throws IOException {
        String serverContent = "package com.tsinghua.thrift.server;\n\n" +
            "import com.tsinghua.thrift.api.*;\n" +
            "import org.apache.thrift.TException;\n\n" +
            "/**\n" +
            " * Thrift服务实现类\n" +
            " */\n" +
            "public class ApiServiceHandler implements ApiService.Iface {\n\n" +
            "    @Override\n" +
            "    public Result saveAssociationRule(AssociationRule rule) throws TException {\n" +
            "        // 实现关联规则保存逻辑\n" +
            "        return new Result(true, \"关联规则保存成功\", null);\n" +
            "    }\n\n" +
            "    @Override\n" +
            "    public Result listAssociationRules(AssociationRulesQueryRequest request) throws TException {\n" +
            "        // 实现关联规则查询逻辑\n" +
            "        return new Result(true, \"查询成功\", null);\n" +
            "    }\n\n" +
            "    @Override\n" +
            "    public Result getAssociationRule(long createTime) throws TException {\n" +
            "        // 实现关联规则详情查询逻辑\n" +
            "        return new Result(true, \"查询成功\", null);\n" +
            "    }\n\n" +
            "    @Override\n" +
            "    public Result deleteAssociationRule(long createTime) throws TException {\n" +
            "        // 实现关联规则删除逻辑\n" +
            "        return new Result(true, \"删除成功\", null);\n" +
            "    }\n\n" +
            "    @Override\n" +
            "    public Result countAssociationRules(AssociationRulesQueryRequest request) throws TException {\n" +
            "        // 实现关联规则计数逻辑\n" +
            "        return new Result(true, \"计数成功\", null);\n" +
            "    }\n\n" +
            "    @Override\n" +
            "    public Result saveDataSource(DataSource dataSource) throws TException {\n" +
            "        // 实现数据源保存逻辑\n" +
            "        return new Result(true, \"数据源保存成功\", null);\n" +
            "    }\n\n" +
            "    @Override\n" +
            "    public Result listDataSources(DataSourceQueryRequest request) throws TException {\n" +
            "        // 实现数据源查询逻辑\n" +
            "        return new Result(true, \"查询成功\", null);\n" +
            "    }\n\n" +
            "    @Override\n" +
            "    public Result getDataSource(String name) throws TException {\n" +
            "        // 实现数据源详情查询逻辑\n" +
            "        return new Result(true, \"查询成功\", null);\n" +
            "    }\n\n" +
            "    @Override\n" +
            "    public Result deleteDataSource(String name) throws TException {\n" +
            "        // 实现数据源删除逻辑\n" +
            "        return new Result(true, \"删除成功\", null);\n" +
            "    }\n\n" +
            "    @Override\n" +
            "    public Result testConnection(DataSource dataSource) throws TException {\n" +
            "        // 实现连接测试逻辑\n" +
            "        return new Result(true, \"连接测试成功\", null);\n" +
            "    }\n\n" +
            "    @Override\n" +
            "    public Result listTables(TableQueryRequest request) throws TException {\n" +
            "        // 实现数据表查询逻辑\n" +
            "        return new Result(true, \"查询成功\", null);\n" +
            "    }\n\n" +
            "    @Override\n" +
            "    public Result getTableInfo(String database, String tableName) throws TException {\n" +
            "        // 实现数据表详情查询逻辑\n" +
            "        return new Result(true, \"查询成功\", null);\n" +
            "    }\n\n" +
            "    @Override\n" +
            "    public Result getTableData(String database, String tableName, PageInfo pageInfo) throws TException {\n" +
            "        // 实现数据表数据查询逻辑\n" +
            "        return new Result(true, \"查询成功\", null);\n" +
            "    }\n\n" +
            "    @Override\n" +
            "    public Result saveModelFile(ModelFile modelFile) throws TException {\n" +
            "        // 实现模型文件保存逻辑\n" +
            "        return new Result(true, \"模型文件保存成功\", null);\n" +
            "    }\n\n" +
            "    @Override\n" +
            "    public Result listModelFiles(ModelFileQueryRequest request) throws TException {\n" +
            "        // 实现模型文件查询逻辑\n" +
            "        return new Result(true, \"查询成功\", null);\n" +
            "    }\n\n" +
            "    @Override\n" +
            "    public Result getModelFile(String name) throws TException {\n" +
            "        // 实现模型文件详情查询逻辑\n" +
            "        return new Result(true, \"查询成功\", null);\n" +
            "    }\n\n" +
            "    @Override\n" +
            "    public Result deleteModelFile(String name) throws TException {\n" +
            "        // 实现模型文件删除逻辑\n" +
            "        return new Result(true, \"删除成功\", null);\n" +
            "    }\n\n" +
            "    @Override\n" +
            "    public Result updateModelFile(ModelFile modelFile) throws TException {\n" +
            "        // 实现模型文件更新逻辑\n" +
            "        return new Result(true, \"更新成功\", null);\n" +
            "    }\n" +
            "}\n";
        
        Files.write(Paths.get(outputDir, "ApiServiceHandler.java"), serverContent.getBytes());
        
        // 生成Server启动类
        String serverMainContent = "package com.tsinghua.thrift.server;\n\n" +
            "import com.tsinghua.thrift.api.ApiService;\n" +
            "import org.apache.thrift.server.TServer;\n" +
            "import org.apache.thrift.server.TSimpleServer;\n" +
            "import org.apache.thrift.transport.TServerSocket;\n" +
            "import org.apache.thrift.transport.TTransportException;\n\n" +
            "/**\n" +
            " * Thrift服务器启动类\n" +
            " */\n" +
            "public class ApiServer {\n" +
            "    public static void main(String[] args) {\n" +
            "        try {\n" +
            "            ApiService.Processor processor = new ApiService.Processor(new ApiServiceHandler());\n" +
            "            TServerSocket serverTransport = new TServerSocket(9090);\n" +
            "            TServer server = new TSimpleServer(new TServer.Args(serverTransport).processor(processor));\n" +
            "            \n" +
            "            System.out.println(\"Starting the Thrift server on port 9090...\");\n" +
            "            server.serve();\n" +
            "        } catch (TTransportException e) {\n" +
            "            e.printStackTrace();\n" +
            "        }\n" +
            "    }\n" +
            "}\n";
        
        Files.write(Paths.get(outputDir, "ApiServer.java"), serverMainContent.getBytes());
    }

    /**
     * 生成Java Client端示例
     */
    private void generateJavaClientExample(String outputDir) throws IOException {
        String clientContent = "package com.tsinghua.thrift.client;\n\n" +
            "import com.tsinghua.thrift.api.*;\n" +
            "import org.apache.thrift.TException;\n" +
            "import org.apache.thrift.protocol.TBinaryProtocol;\n" +
            "import org.apache.thrift.transport.TSocket;\n" +
            "import org.apache.thrift.transport.TTransport;\n\n" +
            "/**\n" +
            " * Thrift客户端示例\n" +
            " */\n" +
            "public class ApiClient {\n" +
            "    public static void main(String[] args) {\n" +
            "        try {\n" +
            "            TTransport transport = new TSocket(\"localhost\", 9090);\n" +
            "            transport.open();\n" +
            "            \n" +
            "            TBinaryProtocol protocol = new TBinaryProtocol(transport);\n" +
            "            ApiService.Client client = new ApiService.Client(protocol);\n" +
            "            \n" +
            "            // 测试关联规则保存\n" +
            "            AssociationRule rule = new AssociationRule();\n" +
            "            rule.setCreateTime(System.currentTimeMillis());\n" +
            "            rule.setRuleName(\"测试规则\");\n" +
            "            rule.setRuleDescription(\"测试关联规则\");\n" +
            "            rule.setSourceTable(\"table1\");\n" +
            "            rule.setTargetTable(\"table2\");\n" +
            "            rule.setJoinCondition(\"table1.id = table2.id\");\n" +
            "            rule.setRuleType(\"INNER_JOIN\");\n" +
            "            rule.setEnabled(true);\n" +
            "            \n" +
            "            Result result = client.saveAssociationRule(rule);\n" +
            "            System.out.println(\"Save result: \" + result.isSuccess() + \", message: \" + result.getMessage());\n" +
            "            \n" +
            "            // 测试关联规则查询\n" +
            "            AssociationRulesQueryRequest request = new AssociationRulesQueryRequest();\n" +
            "            PageInfo pageInfo = new PageInfo();\n" +
            "            pageInfo.setPage(1);\n" +
            "            pageInfo.setSize(10);\n" +
            "            request.setPageInfo(pageInfo);\n" +
            "            \n" +
            "            Result listResult = client.listAssociationRules(request);\n" +
            "            System.out.println(\"List result: \" + listResult.isSuccess() + \", message: \" + listResult.getMessage());\n" +
            "            \n" +
            "            transport.close();\n" +
            "        } catch (TException e) {\n" +
            "            e.printStackTrace();\n" +
            "        }\n" +
            "    }\n" +
            "}\n";
        
        Files.write(Paths.get(outputDir, "ApiClient.java"), clientContent.getBytes());
    }

    /**
     * 生成Go Server端实现
     */
    private void generateGoServerImplementation(String outputDir) throws IOException {
        String serverContent = "package main\n\n" +
            "import (\n" +
            "    \"context\"\n" +
            "    \"fmt\"\n" +
            "    \"net\"\n" +
            "    \"tsinghua/api\"\n" +
            ")\n\n" +
            "// ApiServiceHandler 实现Thrift服务接口\n" +
            "type ApiServiceHandler struct{}\n\n" +
            "func (h *ApiServiceHandler) SaveAssociationRule(ctx context.Context, rule *api.AssociationRule) (*api.Result, error) {\n" +
            "    // 实现关联规则保存逻辑\n" +
            "    return &api.Result{Success: true, Message: \"关联规则保存成功\"}, nil\n" +
            "}\n\n" +
            "func (h *ApiServiceHandler) ListAssociationRules(ctx context.Context, request *api.AssociationRulesQueryRequest) (*api.Result, error) {\n" +
            "    // 实现关联规则查询逻辑\n" +
            "    return &api.Result{Success: true, Message: \"查询成功\"}, nil\n" +
            "}\n\n" +
            "func (h *ApiServiceHandler) GetAssociationRule(ctx context.Context, createTime int64) (*api.Result, error) {\n" +
            "    // 实现关联规则详情查询逻辑\n" +
            "    return &api.Result{Success: true, Message: \"查询成功\"}, nil\n" +
            "}\n\n" +
            "func (h *ApiServiceHandler) DeleteAssociationRule(ctx context.Context, createTime int64) (*api.Result, error) {\n" +
            "    // 实现关联规则删除逻辑\n" +
            "    return &api.Result{Success: true, Message: \"删除成功\"}, nil\n" +
            "}\n\n" +
            "func (h *ApiServiceHandler) CountAssociationRules(ctx context.Context, request *api.AssociationRulesQueryRequest) (*api.Result, error) {\n" +
            "    // 实现关联规则计数逻辑\n" +
            "    return &api.Result{Success: true, Message: \"计数成功\"}, nil\n" +
            "}\n\n" +
            "func (h *ApiServiceHandler) SaveDataSource(ctx context.Context, dataSource *api.DataSource) (*api.Result, error) {\n" +
            "    // 实现数据源保存逻辑\n" +
            "    return &api.Result{Success: true, Message: \"数据源保存成功\"}, nil\n" +
            "}\n\n" +
            "func (h *ApiServiceHandler) ListDataSources(ctx context.Context, request *api.DataSourceQueryRequest) (*api.Result, error) {\n" +
            "    // 实现数据源查询逻辑\n" +
            "    return &api.Result{Success: true, Message: \"查询成功\"}, nil\n" +
            "}\n\n" +
            "func (h *ApiServiceHandler) GetDataSource(ctx context.Context, name string) (*api.Result, error) {\n" +
            "    // 实现数据源详情查询逻辑\n" +
            "    return &api.Result{Success: true, Message: \"查询成功\"}, nil\n" +
            "}\n\n" +
            "func (h *ApiServiceHandler) DeleteDataSource(ctx context.Context, name string) (*api.Result, error) {\n" +
            "    // 实现数据源删除逻辑\n" +
            "    return &api.Result{Success: true, Message: \"删除成功\"}, nil\n" +
            "}\n\n" +
            "func (h *ApiServiceHandler) TestConnection(ctx context.Context, dataSource *api.DataSource) (*api.Result, error) {\n" +
            "    // 实现连接测试逻辑\n" +
            "    return &api.Result{Success: true, Message: \"连接测试成功\"}, nil\n" +
            "}\n\n" +
            "func (h *ApiServiceHandler) ListTables(ctx context.Context, request *api.TableQueryRequest) (*api.Result, error) {\n" +
            "    // 实现数据表查询逻辑\n" +
            "    return &api.Result{Success: true, Message: \"查询成功\"}, nil\n" +
            "}\n\n" +
            "func (h *ApiServiceHandler) GetTableInfo(ctx context.Context, database string, tableName string) (*api.Result, error) {\n" +
            "    // 实现数据表详情查询逻辑\n" +
            "    return &api.Result{Success: true, Message: \"查询成功\"}, nil\n" +
            "}\n\n" +
            "func (h *ApiServiceHandler) GetTableData(ctx context.Context, database string, tableName string, pageInfo *api.PageInfo) (*api.Result, error) {\n" +
            "    // 实现数据表数据查询逻辑\n" +
            "    return &api.Result{Success: true, Message: \"查询成功\"}, nil\n" +
            "}\n\n" +
            "func (h *ApiServiceHandler) SaveModelFile(ctx context.Context, modelFile *api.ModelFile) (*api.Result, error) {\n" +
            "    // 实现模型文件保存逻辑\n" +
            "    return &api.Result{Success: true, Message: \"模型文件保存成功\"}, nil\n" +
            "}\n\n" +
            "func (h *ApiServiceHandler) ListModelFiles(ctx context.Context, request *api.ModelFileQueryRequest) (*api.Result, error) {\n" +
            "    // 实现模型文件查询逻辑\n" +
            "    return &api.Result{Success: true, Message: \"查询成功\"}, nil\n" +
            "}\n\n" +
            "func (h *ApiServiceHandler) GetModelFile(ctx context.Context, name string) (*api.Result, error) {\n" +
            "    // 实现模型文件详情查询逻辑\n" +
            "    return &api.Result{Success: true, Message: \"查询成功\"}, nil\n" +
            "}\n\n" +
            "func (h *ApiServiceHandler) DeleteModelFile(ctx context.Context, name string) (*api.Result, error) {\n" +
            "    // 实现模型文件删除逻辑\n" +
            "    return &api.Result{Success: true, Message: \"删除成功\"}, nil\n" +
            "}\n\n" +
            "func (h *ApiServiceHandler) UpdateModelFile(ctx context.Context, modelFile *api.ModelFile) (*api.Result, error) {\n" +
            "    // 实现模型文件更新逻辑\n" +
            "    return &api.Result{Success: true, Message: \"更新成功\"}, nil\n" +
            "}\n\n" +
            "func main() {\n" +
            "    handler := &ApiServiceHandler{}\n" +
            "    processor := api.NewApiServiceProcessor(handler)\n" +
            "    \n" +
            "    listener, err := net.Listen(\"tcp\", \":9090\")\n" +
            "    if err != nil {\n" +
            "        fmt.Println(\"Error listening:\", err)\n" +
            "        return\n" +
            "    }\n" +
            "    \n" +
            "    fmt.Println(\"Starting the Thrift server on port 9090...\")\n" +
            "    // 这里需要根据具体的Go Thrift库来实现服务器逻辑\n" +
            "    for {\n" +
            "        conn, err := listener.Accept()\n" +
            "        if err != nil {\n" +
            "            fmt.Println(\"Error accepting:\", err)\n" +
            "            continue\n" +
            "        }\n" +
            "        go handleConnection(conn, processor)\n" +
            "    }\n" +
            "}\n\n" +
            "func handleConnection(conn net.Conn, processor *api.ApiServiceProcessor) {\n" +
            "    defer conn.Close()\n" +
            "    // 处理连接逻辑\n" +
            "    fmt.Println(\"New connection established\")\n" +
            "}\n";
        
        Files.write(Paths.get(outputDir, "server.go"), serverContent.getBytes());
    }

    /**
     * 生成Go Client端示例
     */
    private void generateGoClientExample(String outputDir) throws IOException {
        String clientContent = "package main\n\n" +
            "import (\n" +
            "    \"context\"\n" +
            "    \"fmt\"\n" +
            "    \"time\"\n" +
            "    \"tsinghua/api\"\n" +
            ")\n\n" +
            "func main() {\n" +
            "    // 创建客户端连接\n" +
            "    // 这里需要根据具体的Go Thrift库来实现客户端逻辑\n" +
            "    \n" +
            "    // 测试关联规则保存\n" +
            "    rule := &api.AssociationRule{\n" +
            "        CreateTime:     time.Now().Unix(),\n" +
            "        RuleName:       \"测试规则\",\n" +
            "        RuleDescription: \"测试关联规则\",\n" +
            "        SourceTable:    \"table1\",\n" +
            "        TargetTable:    \"table2\",\n" +
            "        JoinCondition:  \"table1.id = table2.id\",\n" +
            "        RuleType:       \"INNER_JOIN\",\n" +
            "        Enabled:        true,\n" +
            "    }\n" +
            "    \n" +
            "    // 调用服务（需要实际的客户端实现）\n" +
            "    fmt.Println(\"Creating association rule:\", rule.RuleName)\n" +
            "    \n" +
            "    // 测试关联规则查询\n" +
            "    request := &api.AssociationRulesQueryRequest{\n" +
            "        PageInfo: &api.PageInfo{\n" +
            "            Page: 1,\n" +
            "            Size: 10,\n" +
            "        },\n" +
            "    }\n" +
            "    \n" +
            "    fmt.Println(\"Querying association rules...\")\n" +
            "}\n";
        
        Files.write(Paths.get(outputDir, "client.go"), clientContent.getBytes());
    }

    /**
     * 生成Python Server端实现
     */
    private void generatePythonServerImplementation(String outputDir) throws IOException {
        String serverContent = "from api import ApiService\n" +
            "from thrift.transport import TSocket\n" +
            "from thrift.transport import TTransport\n" +
            "from thrift.protocol import TBinaryProtocol\n" +
            "from thrift.server import TServer\n" +
            "from thrift.server.TServer import TSimpleServer\n" +
            "import socket\n\n" +
            "class ApiServiceHandler:\n" +
            "    def saveAssociationRule(self, rule):\n" +
            "        # 实现关联规则保存逻辑\n" +
            "        return {'success': True, 'message': '关联规则保存成功', 'data': None}\n" +
            "    \n" +
            "    def listAssociationRules(self, request):\n" +
            "        # 实现关联规则查询逻辑\n" +
            "        return {'success': True, 'message': '查询成功', 'data': None}\n" +
            "    \n" +
            "    def getAssociationRule(self, createTime):\n" +
            "        # 实现关联规则详情查询逻辑\n" +
            "        return {'success': True, 'message': '查询成功', 'data': None}\n" +
            "    \n" +
            "    def deleteAssociationRule(self, createTime):\n" +
            "        # 实现关联规则删除逻辑\n" +
            "        return {'success': True, 'message': '删除成功', 'data': None}\n" +
            "    \n" +
            "    def countAssociationRules(self, request):\n" +
            "        # 实现关联规则计数逻辑\n" +
            "        return {'success': True, 'message': '计数成功', 'data': None}\n" +
            "    \n" +
            "    def saveDataSource(self, dataSource):\n" +
            "        # 实现数据源保存逻辑\n" +
            "        return {'success': True, 'message': '数据源保存成功', 'data': None}\n" +
            "    \n" +
            "    def listDataSources(self, request):\n" +
            "        # 实现数据源查询逻辑\n" +
            "        return {'success': True, 'message': '查询成功', 'data': None}\n" +
            "    \n" +
            "    def getDataSource(self, name):\n" +
            "        # 实现数据源详情查询逻辑\n" +
            "        return {'success': True, 'message': '查询成功', 'data': None}\n" +
            "    \n" +
            "    def deleteDataSource(self, name):\n" +
            "        # 实现数据源删除逻辑\n" +
            "        return {'success': True, 'message': '删除成功', 'data': None}\n" +
            "    \n" +
            "    def testConnection(self, dataSource):\n" +
            "        # 实现连接测试逻辑\n" +
            "        return {'success': True, 'message': '连接测试成功', 'data': None}\n" +
            "    \n" +
            "    def listTables(self, request):\n" +
            "        # 实现数据表查询逻辑\n" +
            "        return {'success': True, 'message': '查询成功', 'data': None}\n" +
            "    \n" +
            "    def getTableInfo(self, database, tableName):\n" +
            "        # 实现数据表详情查询逻辑\n" +
            "        return {'success': True, 'message': '查询成功', 'data': None}\n" +
            "    \n" +
            "    def getTableData(self, database, tableName, pageInfo):\n" +
            "        # 实现数据表数据查询逻辑\n" +
            "        return {'success': True, 'message': '查询成功', 'data': None}\n" +
            "    \n" +
            "    def saveModelFile(self, modelFile):\n" +
            "        # 实现模型文件保存逻辑\n" +
            "        return {'success': True, 'message': '模型文件保存成功', 'data': None}\n" +
            "    \n" +
            "    def listModelFiles(self, request):\n" +
            "        # 实现模型文件查询逻辑\n" +
            "        return {'success': True, 'message': '查询成功', 'data': None}\n" +
            "    \n" +
            "    def getModelFile(self, name):\n" +
            "        # 实现模型文件详情查询逻辑\n" +
            "        return {'success': True, 'message': '查询成功', 'data': None}\n" +
            "    \n" +
            "    def deleteModelFile(self, name):\n" +
            "        # 实现模型文件删除逻辑\n" +
            "        return {'success': True, 'message': '删除成功', 'data': None}\n" +
            "    \n" +
            "    def updateModelFile(self, modelFile):\n" +
            "        # 实现模型文件更新逻辑\n" +
            "        return {'success': True, 'message': '更新成功', 'data': None}\n\n" +
            "def main():\n" +
            "    handler = ApiServiceHandler()\n" +
            "    processor = ApiService.Processor(handler)\n" +
            "    \n" +
            "    transport = TSocket.TServerSocket(host='localhost', port=9090)\n" +
            "    tfactory = TTransport.TBufferedTransportFactory()\n" +
            "    pfactory = TBinaryProtocol.TBinaryProtocolFactory()\n" +
            "    \n" +
            "    server = TSimpleServer(processor, transport, tfactory, pfactory)\n" +
            "    \n" +
            "    print('Starting the Thrift server on port 9090...')\n" +
            "    server.serve()\n\n" +
            "if __name__ == '__main__':\n" +
            "    main()\n";
        
        Files.write(Paths.get(outputDir, "server.py"), serverContent.getBytes());
    }

    /**
     * 生成Python Client端示例
     */
    private void generatePythonClientExample(String outputDir) throws IOException {
        String clientContent = "from api import ApiService\n" +
            "from thrift.transport import TSocket\n" +
            "from thrift.transport import TTransport\n" +
            "from thrift.protocol import TBinaryProtocol\n" +
            "import time\n\n" +
            "def main():\n" +
            "    # 创建连接\n" +
            "    transport = TSocket.TSocket('localhost', 9090)\n" +
            "    transport = TTransport.TBufferedTransport(transport)\n" +
            "    protocol = TBinaryProtocol.TBinaryProtocol(transport)\n" +
            "    client = ApiService.Client(protocol)\n" +
            "    \n" +
            "    # 打开连接\n" +
            "    transport.open()\n" +
            "    \n" +
            "    try:\n" +
            "        # 测试关联规则保存\n" +
            "        rule = {\n" +
            "            'createTime': int(time.time()),\n" +
            "            'ruleName': '测试规则',\n" +
            "            'ruleDescription': '测试关联规则',\n" +
            "            'sourceTable': 'table1',\n" +
            "            'targetTable': 'table2',\n" +
            "            'joinCondition': 'table1.id = table2.id',\n" +
            "            'ruleType': 'INNER_JOIN',\n" +
            "            'enabled': True\n" +
            "        }\n" +
            "        \n" +
            "        result = client.saveAssociationRule(rule)\n" +
            "        print(f'Save result: {result}')\n" +
            "        \n" +
            "        # 测试关联规则查询\n" +
            "        request = {\n" +
            "            'pageInfo': {\n" +
            "                'page': 1,\n" +
            "                'size': 10,\n" +
            "                'total': 0\n" +
            "            }\n" +
            "        }\n" +
            "        \n" +
            "        list_result = client.listAssociationRules(request)\n" +
            "        print(f'List result: {list_result}')\n" +
            "        \n" +
            "    finally:\n" +
            "        # 关闭连接\n" +
            "        transport.close()\n\n" +
            "if __name__ == '__main__':\n" +
            "    main()\n";
        
        Files.write(Paths.get(outputDir, "client.py"), clientContent.getBytes());
    }
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
