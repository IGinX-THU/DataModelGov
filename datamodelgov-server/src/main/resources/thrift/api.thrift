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

// ========== API服务接口 - 完全匹配4个Controller的方法 ==========
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
    
    // POST /api/data/delete -> deleteData(DataQueryRequest)
    Result deleteData(1: DataQueryRequest request),
    
    // POST /api/data/relational/query -> queryData(RelationalQueryRequest)
    Result queryRelationalData(1: RelationalQueryRequest request),
    
    // POST /api/data/relational/count -> countData(RelationalQueryRequest)
    Result countRelationalData(1: RelationalQueryRequest request),

    // ========== 模型文件接口 - 匹配ModelFileController ==========
    // POST /api/model/metas -> saveMeta(ModelMetaEntity)
    Result saveModelMeta(1: ModelMeta modelMeta),
    
    // GET /api/model/metas?name=xxx&version=xxx -> queryMeta(String name, String version)
    Result getModelMeta(1: string name, 2: string version),
    
    // GET /api/model/history?name=xxx -> queryMetaList(String name)
    Result getModelHistory(1: string name),
    
    // DELETE /api/model/delete?name=xxx&version=xxx -> deleteModel(String name, String version)
    Result deleteModel(1: string name, 2: string version),
}
