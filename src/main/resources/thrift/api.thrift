namespace java com.tsinghua.thrift.api
namespace go tsinghua.api
namespace py tsinghua.api

// 通用数据类型
struct Result {
    1: bool success,
    2: string message,
    3: optional map<string, string> data,
}

struct PageInfo {
    1: i32 page = 1,
    2: i32 size = 10,
    3: i64 total = 0,
}

// 关联规则相关
struct AssociationRule {
    1: i64 createTime,
    2: string ruleName,
    3: string ruleDescription,
    4: string sourceTable,
    5: string targetTable,
    6: string joinCondition,
    7: string ruleType,
    8: bool enabled = true,
}

struct AssociationRulesQueryRequest {
    1: PageInfo pageInfo,
    2: optional string ruleName,
    3: optional string ruleType,
    4: optional bool enabled,
}

// 数据源相关
struct DataSource {
    1: string name,
    2: string type,
    3: string host,
    4: i32 port,
    5: string database,
    6: optional string username,
    7: optional map<string, string> properties,
}

struct DataSourceQueryRequest {
    1: PageInfo pageInfo,
    2: optional string name,
    3: optional string type,
}

// 数据表相关
struct TableInfo {
    1: string name,
    2: string database,
    3: string type,
    4: i64 rowCount,
    5: i64 size,
    6: string description,
    7: list<ColumnInfo> columns,
}

struct ColumnInfo {
    1: string name,
    2: string dataType,
    3: bool nullable = true,
    4: string defaultValue,
    5: string description,
}

struct TableQueryRequest {
    1: PageInfo pageInfo,
    2: optional string database,
    3: optional string tableName,
    4: optional string type,
}

// 模型文件相关
struct ModelFile {
    1: string name,
    2: string type,
    3: string content,
    4: string version,
    5: i64 createTime,
    6: i64 updateTime,
    7: string description,
    8: list<string> tags,
}

struct ModelFileQueryRequest {
    1: PageInfo pageInfo,
    2: optional string name,
    3: optional string type,
    4: optional list<string> tags,
}

// API服务接口
service ApiService {
    // 关联规则接口
    Result saveAssociationRule(1: AssociationRule rule),
    Result listAssociationRules(1: AssociationRulesQueryRequest request),
    Result getAssociationRule(1: i64 createTime),
    Result deleteAssociationRule(1: i64 createTime),
    Result countAssociationRules(1: AssociationRulesQueryRequest request),

    // 数据源接口
    Result saveDataSource(1: DataSource dataSource),
    Result listDataSources(1: DataSourceQueryRequest request),
    Result getDataSource(1: string name),
    Result deleteDataSource(1: string name),
    Result testConnection(1: DataSource dataSource),

    // 数据表接口
    Result listTables(1: TableQueryRequest request),
    Result getTableInfo(1: string database, 1: string tableName),
    Result getTableData(1: string database, 1: string tableName, 2: PageInfo pageInfo),

    // 模型文件接口
    Result saveModelFile(1: ModelFile modelFile),
    Result listModelFiles(1: ModelFileQueryRequest request),
    Result getModelFile(1: string name),
    Result deleteModelFile(1: string name),
    Result updateModelFile(1: ModelFile modelFile),
}
