namespace java com.tsinghua.thrift.api
namespace go tsinghua.api
namespace py tsinghua.api

// 通用数据类型 - 匹配您的Result DTO
struct Result {
    1: bool success,
    2: string message,
    3: optional string data,
}

// ========== 关联规则相关 - 完全匹配您的AssociationRulesEntity ==========
struct AssociationRule {
    1: string name,
    2: string description,
    3: string tableName,
    4: string modelName,
    5: string modelVersion,
    6: bool status,
    7: i64 createTime,
    8: i64 updateTime,
    9: string inputsBind,
    10: string outputsBind,
}

// 关联规则查询请求 - 完全匹配您的AssociationRulesQueryRequest DTO
struct AssociationRulesQueryRequest {
    1: i32 pageNum = 1,
    2: i32 pageSize = 10,
    3: optional string name,
    4: optional string status,
}

// ========== 解析规则相关 - 完全匹配您的ParsingRulesEntity ==========
struct ParsingRule {
    1: string name,
    2: string regexPattern,
    3: optional string example,
    4: i64 createTime,
    5: i64 updateTime,
}

// 解析规则查询请求 - 完全匹配您的ParsingRulesQueryRequest DTO
struct ParsingRulesQueryRequest {
    1: i32 pageNum = 1,
    2: i32 pageSize = 6,
    3: optional string name,
}

// 自动解析源码请求 - 完全匹配您的AutoParseRequest DTO
struct AutoParseRequest {
    1: string fileContent,
    2: string fileName,
    3: optional string parseType,
    4: optional string regexPattern,
    5: optional string pythonModule,
    6: optional string pythonFunction,
    7: optional i32 maxLines,
}

// ========== 运行任务相关 - 完全匹配您的RunTaskEntity ==========
struct RunTask {
    1: string name,
    2: i64 startTime,
    3: i64 endTime,
    4: i64 ruleId,
    5: string ruleName,
    6: string modelName,
    7: string modelVersion,
    8: string inputMeasurements,
    9: string outputMeasurements,
    10: string outputTable,
    11: string status,
    12: i64 timestamp,
    13: optional i64 processId,
    14: optional string processLog,
}

// 运行任务请求 - 完全匹配您的RunTaskRequest DTO
struct RunTaskRequest {
    1: string name,
    2: i64 startTime,
    3: i64 endTime,
    4: string ruleName,
    5: i64 ruleId,
    6: optional string modelName,
    7: optional string modelVersion,
    8: optional string outputTable,
}

// 运行任务查询请求 - 完全匹配您的RunTaskQueryRequest DTO
struct RunTaskQueryRequest {
    1: i32 pageNum = 1,
    2: i32 pageSize = 10,
    3: optional string name,
    4: optional string status,
    5: optional i64 ruleId,
    6: optional i64 startTime,
    7: optional i64 endTime,
}

// 时间范围查询请求 - 完全匹配您的TimeRangeRequest DTO
struct TimeRangeRequest {
    1: string tableName,
    2: optional list<InputBindDto> inputsBind,
}

// 输入参数绑定 - 完全匹配您的InputBindDto DTO
struct InputBindDto {
    1: string sourceField,
    2: string targetField,
    3: string operator,
    4: string conversionValue,
}

// 时间范围查询响应 - 完全匹配您的TimeRangeResponse DTO
struct TimeRangeResponse {
    1: i64 minKey,
    2: i64 maxKey,
}

// ========== 数据源相关 - 完全匹配您的StorageEngineInfoDto ==========
struct StorageEngineInfo {
    1: i64 id,
    2: optional string ip,
    3: i32 port,
    4: i32 type,
    5: optional string schemaPrefix,
    6: optional string dataPrefix,
}

// ========== 数据查询相关 - 完全匹配您的DataQueryRequest DTO ==========
struct DataQueryRequest {
    1: list<string> paths,
    2: optional i64 startTime,
    3: optional i64 endTime,
    4: optional i32 aggregateType,
    5: optional i64 precision,
    6: optional i32 timePrecision,
}

// 数据导入请求 - 完全匹配您的DataImportRequest DTO
struct DataImportRequest {
    1: string tableName,
    2: optional string path,
    3: optional list<string> columns,
    4: optional i64 startTime,
    5: optional i64 endTime,
}

// 关系数据查询请求 - 完全匹配您的RelationalQueryRequest DTO
struct RelationalQueryRequest {
    1: i32 pageNum = 1,
    2: i32 pageSize = 10,
    3: optional string tableName,
    4: optional list<FilterCondition> filters,
    5: optional string sortField,
    6: optional string sortDirection,
}

// 筛选条件 - 完全匹配您的RelationalQueryRequest.FilterCondition
struct FilterCondition {
    1: string field,
    2: string operator,
    3: string value,
    4: optional string logicOperator,
    5: optional bool startGroup,
    6: optional bool endGroup,
}

// 表数据传输对象 - 完全匹配您的TableDto DTO
struct TableDto {
    1: optional list<string> header,
    2: optional list<map<string, string>> records,
}

// ========== 模型文件相关 - 完全匹配您的ModelMetaEntity ==========
struct ModelMeta {
    1: string name,
    2: string version,
    3: string fileName,
    4: optional i64 fileSize,
    5: optional i32 chunkCount,
    6: optional string storagePath,
    7: optional string fileMd5,
    8: optional string author,
    9: optional string scene,
    10: optional string inputs,
    11: optional string outputs,
    12: optional i64 timestamp,
}

// ========== 模型文件提取请求 - 完全匹配您的ExtractModelFileRequest ==========
struct ExtractModelFileRequest {
    1: string name,
    2: string version,
}

// 模型档案查询请求 - 完全匹配您的ModelArchiveQueryRequest DTO
struct ModelArchiveQueryRequest {
    1: optional string name,
    2: optional string projectName,
    3: optional string author,
    4: i32 pageNum = 1,
    5: i32 pageSize = 10,
}

// ========== 算法文件相关 - 完全匹配您的AlgorithmMetaEntity ==========
struct AlgorithmMeta {
    1: string name,
    2: string version,
    3: string fileName,
    4: optional i64 fileSize,
    5: optional i32 chunkCount,
    6: optional string storagePath,
    7: optional string fileMd5,
    8: optional string author,
    9: optional string scene,
    10: optional string inputs,
    11: optional string outputs,
    12: optional i64 timestamp,
    13: optional string cmd,
    14: optional string inputCsvName,
    15: optional string outputCsvName,
    16: optional string algorithmType,
    17: optional string dependencies,
    18: optional string projectName,
    19: optional string description,
    20: optional string tableName,
    21: optional string inputData,
    22: optional string calledModels,
    23: optional string outputFormat,
    24: optional string inputsBind,
    25: optional string outputsBind,
    26: optional string outputTable,
}

// 算法文件提取请求 - 完全匹配您的ExtractAlgorithmFileRequest DTO
struct ExtractAlgorithmFileRequest {
    1: string name,
    2: string version,
    3: optional string projectName,
}

// 算法档案查询请求 - 完全匹配您的AlgorithmArchiveQueryRequest DTO
struct AlgorithmArchiveQueryRequest {
    1: optional string name,
    2: optional string algorithmType,
    3: optional string projectName,
    4: optional string owner,
    5: optional string author,
    6: i32 pageNum = 1,
    7: i32 pageSize = 10,
}

// ========== 数据档案相关 - 完全匹配您的DataArchiveEntity ==========
struct DataArchive {
    1: i64 id,
    2: string name,
    3: optional string desc,
    4: optional string projectName,
    5: optional string owner,
    6: optional i64 createTime,
    7: optional string type,
    8: optional string config,
}

// 数据档案查询请求 - 完全匹配您的DataArchiveQueryRequest DTO
struct DataArchiveQueryRequest {
    1: optional string name,
    2: optional string type,
    3: optional string projectName,
    4: optional string owner,
    5: i32 pageNum = 1,
    6: i32 pageSize = 10,
    7: optional i64 id,
}

// ========== 项目相关 - 完全匹配您的ProjectEntity ==========
struct Project {
    1: i64 id,
    2: string name,
    3: optional string desc,
    4: optional string algorithms,
    5: optional string models,
    6: optional string datas,
    7: optional i64 createTime,
    8: optional string owner,
}

// 项目查询请求 - 完全匹配您的ProjectsQueryRequest DTO
struct ProjectsQueryRequest {
    1: i32 pageNum = 1,
    2: i32 pageSize = 6,
    3: optional string name,
    4: optional string algorithm,
    5: optional string model,
    6: optional string data,
}

// 项目导出请求 - 完全匹配您的ProjectExportRequest DTO
struct ProjectExportRequest {
    1: string projectName,
    2: optional bool includeAlgorithms = true,
    3: optional bool includeModels = true,
    4: optional bool includeDataCsv = true,
    5: optional bool includeSimulationArchives = false,
}

// 项目树 - 完全匹配您的ProjectTree DTO
struct ProjectTree {
    1: string name,
    2: optional list<string> algorithms,
    3: optional list<string> models,
    4: optional list<string> datas,
}

// ========== 仿真档案相关 - 完全匹配您的SimulationArchiveEntity ==========
struct SimulationArchive {
    1: string name,
    2: optional string description,
    3: optional string graphJson,
    4: optional bool status,
    5: optional i64 createTime,
    6: optional i64 updateTime,
    7: optional string owner,
    8: optional string projectName,
    9: optional string scheduleCron,
    10: optional string outputApiConfig,
    11: optional i64 lastExecutionTime,
    12: optional i64 executionCount,
    13: optional bool isRunning,
}

// 仿真执行实体 - 完全匹配您的SimulationExecutionEntity
struct SimulationExecution {
    1: i64 timestamp,
    2: optional i64 archiveId,
    3: optional string archiveName,
    4: optional i64 startTime,
    5: optional i64 endTime,
    6: optional string status,
    7: optional string inputMeasurements,
    8: optional string outputMeasurements,
    9: optional string outputTable,
    10: optional string result,
    11: optional string error,
    12: optional string processLog,
}

// 仿真执行记录查询 - 完全匹配您的ExecutionRecordQueryDto
struct ExecutionRecordQueryRequest {
    1: optional string archiveName,
    2: optional string status,
    3: optional i64 startTime,
    4: optional i64 endTime,
    5: i32 pageNum = 1,
    6: i32 pageSize = 10,
}

// 选择性运行仿真请求
struct RunSimulationSelectiveRequest {
    1: i64 createTime,
    2: optional list<string> selectedNodeIds,
}

// ========== 用户相关 - 完全匹配您的UserEntity ==========
struct User {
    1: string username,
    2: optional string password,
    3: optional string role,
    4: optional i64 roleId,
    5: bool enabled,
    6: optional i64 timestamp,
}

// 用户查询请求 - 完全匹配您的UserQueryRequest DTO
struct UserQueryRequest {
    1: i32 page = 1,
    2: i32 pageSize = 10,
    3: optional string username,
    4: optional string role,
    5: optional string enabled,
}

// 角色实体 - 完全匹配您的RoleEntity
struct Role {
    1: string role,
    2: optional string permissions,
    3: optional i64 timestamp,
}

// 登录请求
struct LoginRequest {
    1: string username,
    2: string password,
}

// 刷新Token请求
struct RefreshTokenRequest {
    1: string refreshToken,
}

// 修改密码请求
struct ChangePasswordRequest {
    1: string username,
    2: string oldPassword,
    3: string newPassword,
}

// ========== 数据权限相关 - 完全匹配您的DataPermissionEntity ==========
struct DataPermission {
    1: i64 id,
    2: optional string owner,
    3: optional string tablePrefix,
    4: optional string timestampSet,
    5: bool isPublic,
    6: optional string visibleUsers,
    7: optional i64 createTime,
}

// 数据权限查询请求 - 完全匹配您的DataPermissionQueryRequest DTO
struct DataPermissionQueryRequest {
    1: i32 page = 1,
    2: i32 pageSize = 10,
    3: optional string tablePrefix,
}

// 数据权限更新请求 - 完全匹配您的DataPermissionUpdateRequest DTO
struct DataPermissionUpdateRequest {
    1: i64 id,
    2: optional bool isPublic,
    3: optional string visibleUsers,
}

// ========== API服务接口 - 完全匹配所有Controller的方法 ==========
service ApiService {
    // ========== 关联规则接口 - 匹配AssociationRulesController ==========
    // POST /api/association/rules/save -> saveRules(AssociationRulesEntity)
    Result saveAssociationRule(1: AssociationRule rule),

    // POST /api/association/rules/query -> queryRules(AssociationRulesQueryRequest)
    Result queryAssociationRules(1: AssociationRulesQueryRequest request),

    // POST /api/association/rules/count -> countRules(AssociationRulesQueryRequest)
    Result countAssociationRules(1: AssociationRulesQueryRequest request),

    // GET /api/association/rules/detail?createTime=xxx -> queryRule(Long createTime)
    Result getAssociationRule(1: i64 createTime),

    // DELETE /api/association/rules/delete?createTime=xxx -> deleteRule(Long createTime)
    Result deleteAssociationRule(1: i64 createTime),

    // GET /api/association/rules/validate-name?name=xxx -> validateNameUniqueness(String name)
    Result validateAssociationRuleName(1: string name),

    // ========== 解析规则接口 - 匹配ParsingRulesController ==========
    // POST /api/parsing/rules/save -> saveRules(ParsingRulesEntity)
    Result saveParsingRule(1: ParsingRule rule),

    // POST /api/parsing/rules/query -> queryRules(ParsingRulesQueryRequest)
    Result queryParsingRules(1: ParsingRulesQueryRequest request),

    // POST /api/parsing/rules/count -> countRules(ParsingRulesQueryRequest)
    Result countParsingRules(1: ParsingRulesQueryRequest request),

    // GET /api/parsing/rules/detail?createTime=xxx -> queryRule(Long createTime)
    Result getParsingRule(1: i64 createTime),

    // DELETE /api/parsing/rules/delete?createTime=xxx -> deleteRule(Long createTime)
    Result deleteParsingRule(1: i64 createTime),

    // GET /api/parsing/rules/validate-name?name=xxx -> validateNameUniqueness(String name)
    Result validateParsingRuleName(1: string name),

    // POST /api/parsing/autoParse -> autoParseSourceCode(AutoParseRequest)
    Result autoParseSourceCode(1: AutoParseRequest request),

    // ========== 运行任务接口 - 匹配RunTaskController ==========
    // POST /api/task/run -> runTask(RunTaskRequest)
    Result runTask(1: RunTaskRequest runTaskRequest),

    // POST /api/task/validate-uniqueness -> validateTaskUniqueness(RunTaskRequest)
    Result validateTaskUniqueness(1: RunTaskRequest request),

    // GET /api/task/stop?timestamp=xxx -> stopTask(Long timestamp)
    Result stopTask(1: i64 timestamp),

    // GET /api/task/log?timestamp=xxx -> getTaskLog(Long timestamp)
    Result getTaskLog(1: i64 timestamp),

    // POST /api/task/query -> queryTasks(RunTaskQueryRequest)
    Result queryTasks(1: RunTaskQueryRequest request),

    // POST /api/task/count -> countTasks(RunTaskQueryRequest)
    Result countTasks(1: RunTaskQueryRequest request),

    // GET /api/task/detail?timestamp=xxx -> queryTask(Long timestamp)
    Result getTask(1: i64 timestamp),

    // DELETE /api/task/delete?timestamp=xxx -> deleteTask(Long timestamp)
    Result deleteTask(1: i64 timestamp),

    // POST /api/task/upload-report -> uploadReport(MultipartFile, Long timestamp)
    Result uploadReport(1: binary file, 2: i64 timestamp),

    // POST /api/task/package-download?timestamp=xxx -> packageAndDownload(Long timestamp)
    Result packageDownload(1: i64 timestamp),

    // POST /api/task/time-range -> getTimeRange(TimeRangeRequest)
    Result getTimeRange(1: TimeRangeRequest request),

    // ========== 数据源接口 - 匹配DataSourceController ==========
    // POST /api/datasource/register -> register(String jsonBody)
    Result registerDataSource(1: string jsonBody),

    // POST /api/datasource/remove -> remove(StorageEngineInfoDto)
    Result removeDataSource(1: StorageEngineInfo storageEngineInfo),

    // GET /api/datasource/list -> list()
    Result listDataSources(),

    // GET /api/datasource/tree -> tree()
    Result getDataSourceTree(),

    // ========== 数据查询接口 - 匹配DataTableController ==========
    // POST /api/data/query -> queryData(DataQueryRequest)
    Result queryData(1: DataQueryRequest request),

    // POST /api/data/import -> importData(DataImportRequest, MultipartFile)
    Result importData(1: string config, 2: binary file),

    // POST /api/data/export -> exportData(DataQueryRequest) - Note: Returns file, not suitable for Thrift
    // Result exportData(1: DataQueryRequest request),

    // POST /api/data/delete -> deleteData(DataQueryRequest)
    Result deleteData(1: DataQueryRequest request),

    // POST /api/data/relational/query -> queryData(RelationalQueryRequest)
    Result queryRelationalData(1: RelationalQueryRequest request),

    // POST /api/data/relational/count -> countData(RelationalQueryRequest)
    Result countRelationalData(1: RelationalQueryRequest request),

    // POST /api/data/relational/export -> exportRelationalDataToExcel(RelationalQueryRequest) - Note: Returns file, not suitable for Thrift
    // Result exportRelationalData(1: RelationalQueryRequest request),

    // DELETE /api/data/deleteColumns/{path} -> deleteColumns(String path)
    Result deleteColumns(1: string path),

    // ========== 文档接口 - 匹配DocController ==========
    // GET /api/doc/user-manual/file -> getUserManualFile()
    Result getUserManualFile(),

    // ========== 模型文件接口 - 匹配ModelFileController ==========
    // POST /api/model/upload -> handleFileUpload(MultipartFile, name, version)
    Result uploadModel(1: binary file, 2: string name, 3: string version),

    // POST /api/model/download -> handleFileDownload(String name, String version)
    Result downloadModel(1: string name, 2: string version, 3: string projectName),

    // GET /api/model/metas?name=xxx&version=xxx -> queryMeta(String name, String version, String projectName)
    Result getModelMeta(1: string name, 2: string version, 3: string projectName),

    // POST /api/model/metas -> saveMeta(ModelMetaEntity)
    Result saveModelMeta(1: ModelMeta modelMeta),

    // GET /api/model/history?name=xxx -> queryMetaList(String name)
    Result getModelHistory(1: string name, 2: string projectName),

    // DELETE /api/model/delete?name=xxx&version=xxx -> deleteModel(String name, String version)
    Result deleteModel(1: string name, 2: string version, 3: string projectName),

    // GET /api/model/tree?projectName=xxx -> queryModelTree(String projectName)
    Result getModelTree(1: string projectName),

    // POST /api/model/archive/query -> queryModelArchives(ModelArchiveQueryRequest)
    Result queryModelArchives(1: ModelArchiveQueryRequest request),

    // POST /api/model/archive/count -> countModelArchives(ModelArchiveQueryRequest)
    Result countModelArchives(1: ModelArchiveQueryRequest request),

    // POST /api/model/extractModelFile -> extractModelFileForParsing(ExtractModelFileRequest)
    Result extractModelFile(1: ExtractModelFileRequest request),

    // ========== 算法文件接口 - 匹配AlgorithmFileController ==========
    // POST /api/algorithm/upload -> handleFileUpload(MultipartFile, name, version)
    Result uploadAlgorithm(1: binary file, 2: string name, 3: string version),

    // POST /api/algorithm/download -> handleFileDownload(String name, String version)
    Result downloadAlgorithm(1: string name, 2: string version, 3: string projectName),

    // GET /api/algorithm/metas?name=xxx&version=xxx -> queryMeta(String name, String version, String projectName)
    Result getAlgorithmMeta(1: string name, 2: string version, 3: string projectName),

    // POST /api/algorithm/metas -> saveMeta(AlgorithmMetaEntity)
    Result saveAlgorithmMeta(1: AlgorithmMeta algorithmMeta),

    // GET /api/algorithm/history?name=xxx -> queryMetaList(String name)
    Result getAlgorithmHistory(1: string name, 2: string projectName),

    // DELETE /api/algorithm/delete?name=xxx&version=xxx -> deleteAlgorithm(String name, String version)
    Result deleteAlgorithm(1: string name, 2: string version, 3: string projectName),

    // GET /api/algorithm/tree?projectName=xxx -> queryAlgorithmTree(String projectName)
    Result getAlgorithmTree(1: string projectName),

    // POST /api/algorithm/archive/query -> queryAlgorithmArchives(AlgorithmArchiveQueryRequest)
    Result queryAlgorithmArchives(1: AlgorithmArchiveQueryRequest request),

    // POST /api/algorithm/archive/count -> countAlgorithmArchives(AlgorithmArchiveQueryRequest)
    Result countAlgorithmArchives(1: AlgorithmArchiveQueryRequest request),

    // POST /api/algorithm/extractAlgorithmFile -> extractAlgorithmFileForParsing(ExtractAlgorithmFileRequest)
    Result extractAlgorithmFile(1: ExtractAlgorithmFileRequest request),

    // ========== 数据档案接口 - 匹配DataArchiveController ==========
    // POST /api/dataArchive/query -> queryArchives(DataArchiveQueryRequest)
    Result queryDataArchives(1: DataArchiveQueryRequest request),

    // GET /api/dataArchive/detail?name=xxx -> queryArchiveDetail(String name)
    Result getDataArchiveDetail(1: string name),

    // POST /api/dataArchive/count -> countArchives(DataArchiveQueryRequest)
    Result countDataArchives(1: DataArchiveQueryRequest request),

    // POST /api/dataArchive/delete -> deleteArchive(DataArchiveQueryRequest)
    Result deleteDataArchive(1: DataArchiveQueryRequest request),

    // POST /api/dataArchive/update -> updateArchive(DataArchiveEntity)
    Result updateDataArchive(1: DataArchive archive),

    // ========== 项目接口 - 匹配ProjectController ==========
    // POST /api/project/create -> createProject(ProjectEntity)
    Result createProject(1: Project project),

    // POST /api/project/query -> queryProjects(ProjectsQueryRequest)
    Result queryProjects(1: ProjectsQueryRequest request),

    // POST /api/project/count -> countProjects(ProjectsQueryRequest)
    Result countProjects(1: ProjectsQueryRequest request),

    // GET /api/project/detail?createTime=xxx -> queryProject(Long createTime)
    Result getProject(1: i64 createTime),

    // GET /api/project/tree?name=xxx -> getProjectTree(String name)
    Result getProjectTree(1: string name),

    // POST /api/project/import -> importProject(MultipartFile, projectName)
    Result importProject(1: binary file, 2: string projectName),

    // POST /api/project/import/{resourceType} -> importProjectResource(MultipartFile, projectName, resourceType)
    Result importProjectResource(1: binary file, 2: string projectName, 3: string resourceType),

    // POST /api/project/export -> exportProject(ProjectExportRequest) - Note: Returns file, not suitable for Thrift
    // Result exportProject(1: ProjectExportRequest request),

    // POST /api/project/export/{resourceType} -> exportProjectResource(projectName, resourceType) - Note: Returns file, not suitable for Thrift
    // Result exportProjectResource(1: string projectName, 2: string resourceType),

    // ========== 仿真档案接口 - 匹配SimulationArchiveController ==========
    // POST /api/simulation/archives/save -> saveArchive(SimulationArchiveEntity)
    Result saveSimulationArchive(1: SimulationArchive archive),

    // POST /api/simulation/archives/query -> queryArchives(name, projectName, owner, status, pageNum, pageSize)
    Result querySimulationArchives(1: string name, 2: string projectName, 3: string owner, 4: bool status, 5: i32 pageNum, 6: i32 pageSize),

    // POST /api/simulation/archives/count -> countArchives(name, projectName, owner, status)
    Result countSimulationArchives(1: string name, 2: string projectName, 3: string owner, 4: bool status),

    // GET /api/simulation/archives/detail?createTime=xxx -> getArchive(Long createTime)
    Result getSimulationArchive(1: i64 createTime),

    // DELETE /api/simulation/archives/delete?createTime=xxx -> deleteArchive(Long createTime)
    Result deleteSimulationArchive(1: i64 createTime),

    // GET /api/simulation/archives/validate-name?name=xxx -> validateNameUniqueness(String name)
    Result validateSimulationArchiveName(1: string name),

    // POST /api/simulation/archives/copy?createTime=xxx&newName=xxx -> copyArchive(Long createTime, String newName)
    Result copySimulationArchive(1: i64 createTime, 2: string newName),

    // POST /api/simulation/archives/run?createTime=xxx -> runSimulation(Long createTime)
    Result runSimulation(1: i64 createTime),

    // POST /api/simulation/archives/run-selective -> runSimulationSelective(Long createTime, Map<String, Object> params)
    Result runSimulationSelective(1: i64 createTime, 2: map<string, string> params),

    // POST /api/simulation/archives/stop?createTime=xxx -> stopSimulation(Long createTime)
    Result stopSimulation(1: i64 createTime),

    // GET /api/simulation/archives/execution-status?createTime=xxx -> getExecutionStatus(Long createTime)
    Result getSimulationExecutionStatus(1: i64 createTime),

    // GET /api/simulation/archives/execution-log?timestamp=xxx&createTime=xxx -> getExecutionLog(Long timestamp, Long createTime)
    Result getSimulationExecutionLog(1: optional i64 timestamp, 2: optional i64 createTime),

    // POST /api/simulation/archives/execution-records -> queryExecutionRecords(ExecutionRecordQueryDto)
    Result querySimulationExecutionRecords(1: ExecutionRecordQueryRequest request),

    // POST /api/simulation/archives/execution-records-count -> countExecutionRecords(ExecutionRecordQueryDto)
    Result countSimulationExecutionRecords(1: ExecutionRecordQueryRequest request),

    // DELETE /api/simulation/archives/execution-record?timestamp=xxx -> deleteExecutionRecord(Long timestamp)
    Result deleteSimulationExecutionRecord(1: i64 timestamp),

    // POST /api/simulation/archives/upload-report -> uploadReport(MultipartFile, Long timestamp)
    Result uploadSimulationReport(1: binary file, 2: i64 timestamp),

    // POST /api/simulation/archives/package-download?timestamp=xxx -> packageAndDownload(Long timestamp) - Note: Returns file, not suitable for Thrift
    // Result simulationPackageDownload(1: i64 timestamp),

    // ========== 认证接口 - 匹配AuthController ==========
    // POST /api/auth/login -> login(username, password)
    Result login(1: LoginRequest loginRequest),

    // POST /api/auth/refresh -> refreshToken(refreshToken)
    Result refreshToken(1: RefreshTokenRequest request),

    // GET /api/auth/verify -> verifyToken(token)
    Result verifyToken(1: string token),

    // POST /api/auth/logout -> logout()
    Result logout(),

    // GET /api/auth/user -> getCurrentUser()
    Result getCurrentAuthUser(),

    // ========== 用户管理接口 - 匹配UserController ==========
    // POST /api/user/save -> saveUser(UserEntity)
    Result saveUser(1: User user),

    // POST /api/user/query -> queryUsers(UserQueryRequest)
    Result queryUsers(1: UserQueryRequest request),

    // POST /api/user/count -> countUsers(UserQueryRequest)
    Result countUsers(1: UserQueryRequest request),

    // GET /api/user/all -> allUsers()
    Result allUsers(),

    // GET /api/user/detail?username=xxx -> queryUser(String username)
    Result getUser(1: string username),

    // DELETE /api/user/delete?username=xxx -> deleteUser(String username)
    Result deleteUser(1: string username),

    // POST /api/user/update -> updateUser(UserEntity)
    Result updateUser(1: User user),

    // GET /api/user/roles -> getRoles()
    Result getRoles(),

    // POST /api/user/change-password -> changePassword(username, oldPassword, newPassword)
    Result changePassword(1: ChangePasswordRequest request),

    // GET /api/user/current -> getCurrentUser()
    Result getCurrentUser(),

    // ========== 数据权限接口 - 匹配DataPermissionController ==========
    // GET /api/data-permission/owner-tables -> listOwnerTables()
    Result listOwnerTables(),

    // POST /api/data-permission/query -> query(DataPermissionQueryRequest)
    Result queryDataPermissions(1: DataPermissionQueryRequest request),

    // POST /api/data-permission/count -> count(DataPermissionQueryRequest)
    Result countDataPermissions(1: DataPermissionQueryRequest request),

    // POST /api/data-permission/update -> update(DataPermissionUpdateRequest)
    Result updateDataPermission(1: DataPermissionUpdateRequest request),
}
