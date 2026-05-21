package com.tsinghua.thrift;

import com.tsinghua.dto.*;
import com.tsinghua.entity.AssociationRulesEntity;
import com.tsinghua.entity.ModelMetaEntity;
import com.tsinghua.entity.ParsingRulesEntity;
import com.tsinghua.entity.RunTaskEntity;
import com.tsinghua.service.*;
import com.tsinghua.thrift.api.*;
import lombok.extern.slf4j.Slf4j;
import org.apache.thrift.TException;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;
import java.nio.ByteBuffer;

/**
 * DataModelGov Thrift API Service Implementation
 * Exposes your existing services as Thrift RPC interfaces
 * Completely matches your actual Controller methods and DTO structures
 * Includes ParsingRules and RunTask support
 */
@Slf4j
@Component
public class ApiServiceImpl implements ApiService.Iface {

    // Inject your existing services - reuse business logic directly
    @Autowired
    private AssociationRulesService associationRulesService;

    @Autowired
    private DataSourceService dataSourceService;

    @Autowired
    private DataTableService dataTableService;

    @Autowired
    private RelationalDataService relationalDataService;

    @Autowired
    private ModelFileService modelFileService;

    @Autowired
    private ParsingRulesService parsingRulesService;

    @Autowired
    private RunTaskService runTaskService;

    // ========== Association Rules Interface - Match AssociationRulesController ==========

    @Override
    public com.tsinghua.thrift.api.Result saveAssociationRule(com.tsinghua.thrift.api.AssociationRule rule) throws TException {
        try {
            log.info("Thrift RPC: Save association rule {}", rule.getName());
            
            // Convert Thrift object to your Entity (perfect match)
            AssociationRulesEntity entity = convertToAssociationRulesEntity(rule);
            
            // Call your existing service method directly
            associationRulesService.saveRules(entity);
            
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "关联规则保存成功");
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Save association rule failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Save failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result queryAssociationRules(com.tsinghua.thrift.api.AssociationRulesQueryRequest request) throws TException {
        try {
            log.info("Thrift RPC: Query association rules");
            
            // Convert Thrift request to your DTO (perfect match)
            com.tsinghua.dto.AssociationRulesQueryRequest dtoRequest = convertToAssociationRulesQueryRequest(request);
            
            // Call your existing service method directly
            java.util.List<AssociationRulesEntity> entities = associationRulesService.queryRules(dtoRequest);
            
            // Convert result to JSON string
            String jsonData = convertListToJson(entities);
            
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "Query successful");
            result.setData(jsonData);
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Query association rules failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Query failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result countAssociationRules(com.tsinghua.thrift.api.AssociationRulesQueryRequest request) throws TException {
        try {
            log.info("Thrift RPC: Count association rules");
            
            // Convert request
            com.tsinghua.dto.AssociationRulesQueryRequest dtoRequest = convertToAssociationRulesQueryRequest(request);
            
            // Call your existing service method directly
            Object count = associationRulesService.countRules(dtoRequest);
            
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "Count successful");
            result.setData(String.valueOf(count));
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Count association rules failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Count failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result getAssociationRule(long createTime) throws TException {
        try {
            log.info("Thrift RPC: Get association rule detail {}", createTime);
            
            // Call your existing service method directly
            AssociationRulesEntity entity = associationRulesService.queryRule(createTime);
            
            if (entity == null) {
                com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "未找到指定的关联规则");
                return result;
            }
            
            // Convert to JSON string
            String jsonData = convertEntityToJson(entity);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "Query successful");
            result.setData(jsonData);
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Get association rule detail failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Query failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result deleteAssociationRule(long createTime) throws TException {
        try {
            log.info("Thrift RPC: Delete association rule {}", createTime);
            
            // Call your existing service method directly
            associationRulesService.deleteRule(createTime);
            
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "操作成功");
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Delete association rule failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Delete failed: " + e.getMessage());
            return result;
        }
    }

    // ========== Parsing Rules Interface - Match ParsingRulesController ==========

    @Override
    public com.tsinghua.thrift.api.Result saveParsingRule(com.tsinghua.thrift.api.ParsingRule rule) throws TException {
        try {
            log.info("Thrift RPC: Save parsing rule {}", rule.getName());
            
            // Convert Thrift object to your Entity (perfect match)
            ParsingRulesEntity entity = convertToParsingRulesEntity(rule);
            
            // Call your existing service method directly
            parsingRulesService.saveRules(entity);
            
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "解析规则保存成功");
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Save parsing rule failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Save failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result queryParsingRules(com.tsinghua.thrift.api.ParsingRulesQueryRequest request) throws TException {
        try {
            log.info("Thrift RPC: Query parsing rules");
            
            // Convert Thrift request to your DTO (perfect match)
            com.tsinghua.dto.ParsingRulesQueryRequest dtoRequest = convertToParsingRulesQueryRequest(request);
            
            // Call your existing service method directly
            java.util.List<ParsingRulesEntity> entities = parsingRulesService.queryRules(dtoRequest);
            
            // Convert result to JSON string
            String jsonData = convertListToJson(entities);
            
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "Query successful");
            result.setData(jsonData);
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Query parsing rules failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Query failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result countParsingRules(com.tsinghua.thrift.api.ParsingRulesQueryRequest request) throws TException {
        try {
            log.info("Thrift RPC: Count parsing rules");
            
            // Convert request
            com.tsinghua.dto.ParsingRulesQueryRequest dtoRequest = convertToParsingRulesQueryRequest(request);
            
            // Call your existing service method directly
            Object count = parsingRulesService.countRules(dtoRequest);
            
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "Count successful");
            result.setData(String.valueOf(count));
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Count parsing rules failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Count failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result getParsingRule(long createTime) throws TException {
        try {
            log.info("Thrift RPC: Get parsing rule detail {}", createTime);
            
            // Call your existing service method directly
            ParsingRulesEntity entity = parsingRulesService.queryRule(createTime);
            
            if (entity == null) {
                com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "未找到指定的解析规则");
                return result;
            }
            
            // Convert to JSON string
            String jsonData = convertEntityToJson(entity);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "Query successful");
            result.setData(jsonData);
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Get parsing rule detail failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Query failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result deleteParsingRule(long createTime) throws TException {
        try {
            log.info("Thrift RPC: Delete parsing rule {}", createTime);
            
            // Call your existing service method directly
            parsingRulesService.deleteRule(createTime);
            
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "操作成功");
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Delete parsing rule failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Delete failed: " + e.getMessage());
            return result;
        }
    }

    // ========== Run Task Interface - Match RunTaskController ==========

    @Override
    public com.tsinghua.thrift.api.Result runTask(com.tsinghua.thrift.api.RunTaskRequest runTaskRequest) throws TException {
        try {
            log.info("Thrift RPC: Run task {}", runTaskRequest.getName());
            
            // Convert Thrift request to your DTO (perfect match)
            com.tsinghua.dto.RunTaskRequest dto = convertToRunTaskRequest(runTaskRequest);
            
            // Call your existing service method directly
            RunTaskEntity task = runTaskService.runTask(dto);
            
            // Convert result to JSON string
            String jsonData = convertEntityToJson(task);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "任务运行成功");
            result.setData(jsonData);
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Run task failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Run task failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result validateTaskUniqueness(com.tsinghua.thrift.api.RunTaskRequest request) throws TException {
        try {
            log.info("Thrift RPC: Validate task uniqueness");
            
            // Convert Thrift request to your DTO (perfect match)
            com.tsinghua.dto.RunTaskRequest dto = convertToRunTaskRequest(request);
            
            // Call your existing service method directly
            boolean isUnique = runTaskService.validateTaskUniqueness(dto);
            
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "验证完成");
            result.setData(String.valueOf(isUnique));
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Validate task uniqueness failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Validation failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result stopTask(long timestamp) throws TException {
        try {
            log.info("Thrift RPC: Stop task {}", timestamp);
            
            // Call your existing service method directly
            runTaskService.stopTask(timestamp);
            
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "任务已停止");
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Stop task failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Stop task failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result getTaskLog(long timestamp) throws TException {
        try {
            log.info("Thrift RPC: Get task log {}", timestamp);
            
            // Call your existing service method directly
            String log = runTaskService.getTaskLog(timestamp);
            
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "获取日志成功");
            result.setData(log);
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Get task log failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Get log failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result queryTasks(com.tsinghua.thrift.api.RunTaskQueryRequest request) throws TException {
        try {
            log.info("Thrift RPC: Query tasks");
            
            // Convert Thrift request to your DTO (perfect match)
            com.tsinghua.dto.RunTaskQueryRequest dto = convertToRunTaskQueryRequest(request);
            
            // Call your existing service method directly
            java.util.List<RunTaskEntity> tasks = runTaskService.queryTasks(dto);
            
            // Convert result to JSON string
            String jsonData = convertListToJson(tasks);
            
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "Query successful");
            result.setData(jsonData);
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Query tasks failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Query failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result countTasks(com.tsinghua.thrift.api.RunTaskQueryRequest request) throws TException {
        try {
            log.info("Thrift RPC: Count tasks");
            
            // Convert Thrift request to your DTO (perfect match)
            com.tsinghua.dto.RunTaskQueryRequest dto = convertToRunTaskQueryRequest(request);
            
            // Call your existing service method directly
            Object count = runTaskService.countTasks(dto);
            
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "Count successful");
            result.setData(String.valueOf(count));
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Count tasks failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Count failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result getTask(long timestamp) throws TException {
        try {
            log.info("Thrift RPC: Get task detail {}", timestamp);
            
            // Call your existing service method directly
            Object task = runTaskService.queryTask(timestamp);
            
            // Convert result to JSON string
            String jsonData = convertEntityToJson(task);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "Query successful");
            result.setData(jsonData);
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Get task detail failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Query failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result deleteTask(long timestamp) throws TException {
        try {
            log.info("Thrift RPC: Delete task {}", timestamp);
            
            // Call your existing service method directly
            runTaskService.deleteTask(timestamp);
            
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "操作成功");
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Delete task failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Delete failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result uploadReport(ByteBuffer file) throws TException {
        try {
            log.info("Thrift RPC: Upload report file");
            
            // Note: Binary file upload via Thrift is complex, this is a placeholder
            // In practice, you might need to handle this differently or use HTTP for file upload
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "File upload via Thrift not implemented, use HTTP endpoint");
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Upload report failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Upload failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result packageDownload(long timestamp) throws TException {
        try {
            log.info("Thrift RPC: Package download {}", timestamp);
            
            // Note: File download via Thrift is complex, this is a placeholder
            // In practice, you might need to handle this differently or use HTTP for file download
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "File download via Thrift not implemented, use HTTP endpoint");
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Package download failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Download failed: " + e.getMessage());
            return result;
        }
    }

    // ========== Data Source Interface - Match DataSourceController ==========

    @Override
    public com.tsinghua.thrift.api.Result registerDataSource(String jsonBody) throws TException {
        try {
            log.info("Thrift RPC: Register data source");
            
            // Parse JSON and convert to BaseStorageEngineRequest (same logic as your Controller)
            com.fasterxml.jackson.databind.ObjectMapper mapper = new com.fasterxml.jackson.databind.ObjectMapper();
            mapper.configure(com.fasterxml.jackson.databind.DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false);
            com.fasterxml.jackson.databind.JsonNode rootNode = mapper.readTree(jsonBody);
            
            // Get storageEngineType
            com.fasterxml.jackson.databind.JsonNode storageEngineTypeNode = rootNode.get("storageEngineType");
            if (storageEngineTypeNode == null || !storageEngineTypeNode.isInt()) {
                com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "storageEngineType is required and must be an integer");
                return result;
            }
            
            int storageEngineType = storageEngineTypeNode.asInt();
            
            // Deserialize to specific request class based on storageEngineType
            com.tsinghua.dto.request.BaseStorageEngineRequest request;
            switch (storageEngineType) {
                case 1:
                    request = mapper.treeToValue(rootNode, com.tsinghua.dto.request.Iotdb12StorageRequest.class);
                    break;
                case 2:
                    request = mapper.treeToValue(rootNode, com.tsinghua.dto.request.InfluxdbStorageRequest.class);
                    break;
                case 3:
                    request = mapper.treeToValue(rootNode, com.tsinghua.dto.request.FilesystemStorageRequest.class);
                    break;
                case 4:
                    request = mapper.treeToValue(rootNode, com.tsinghua.dto.request.RelationalStorageRequest.class);
                    break;
                case 5:
                    request = mapper.treeToValue(rootNode, com.tsinghua.dto.request.MongodbStorageRequest.class);
                    break;
                case 6:
                    request = mapper.treeToValue(rootNode, com.tsinghua.dto.request.RedisStorageRequest.class);
                    break;
                default:
                    com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Unknown storage engine type: " + storageEngineType);
                    return result;
            }
            
            // Call your existing service method directly
            boolean success = dataSourceService.registerDataSource(request);
            
            if (success) {
                com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "数据源注册成功");
                return result;
            } else {
                com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "注册失败，请检查配置");
                return result;
            }
        } catch (Exception e) {
            log.error("Thrift RPC: Register data source failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Register failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result removeDataSource(com.tsinghua.thrift.api.StorageEngineInfo storageEngineInfo) throws TException {
        try {
            log.info("Thrift RPC: Remove data source");
            
            // Convert Thrift object to your DTO (perfect match)
            StorageEngineInfoDto dto = convertToStorageEngineInfoDto(storageEngineInfo);
            
            // Call your existing service method directly
            boolean success = dataSourceService.removeDataSource(dto);
            
            if (success) {
                com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "数据源移除成功");
                return result;
            } else {
                com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "移除失败，数据源可能被关联规则占用");
                return result;
            }
        } catch (Exception e) {
            log.error("Thrift RPC: Remove data source failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Remove failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result listDataSources() throws TException {
        try {
            log.info("Thrift RPC: List data sources");
            
            // Call your existing service method directly
            java.util.List<StorageEngineInfoDto> sources = dataSourceService.dataSourceList();
            
            // Convert result to JSON string
            String jsonData = convertListToJson(sources);
            
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "Query successful");
            result.setData(jsonData);
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: List data sources failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Query failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result getDataSourceTree() throws TException {
        try {
            log.info("Thrift RPC: Get data source tree");
            
            // Call your existing service method directly
            java.util.List<ColumnDto> tree = dataSourceService.dataSourceTree();
            
            // Convert result to JSON string
            String jsonData = convertListToJson(tree);
            
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "Query successful");
            result.setData(jsonData);
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Get data source tree failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Query failed: " + e.getMessage());
            return result;
        }
    }

    // ========== Data Query Interface - Match DataTableController ==========

    @Override
    public com.tsinghua.thrift.api.Result queryData(com.tsinghua.thrift.api.DataQueryRequest request) throws TException {
        try {
            log.info("Thrift RPC: Query data");
            
            // Convert Thrift request to your DTO (perfect match)
            com.tsinghua.dto.DataQueryRequest dto = convertToDataQueryRequest(request);
            
            // Call your existing service method directly
            com.tsinghua.dto.TableDto result = dataTableService.queryData(dto);
            
            // Convert result to JSON string
            String jsonData = convertTableDtoToJson(result);
            
            com.tsinghua.thrift.api.Result thriftResult = new com.tsinghua.thrift.api.Result(true, "Query successful");
            thriftResult.setData(jsonData);
            return thriftResult;
        } catch (Exception e) {
            log.error("Thrift RPC: Query data failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Query failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result deleteData(com.tsinghua.thrift.api.DataQueryRequest request) throws TException {
        try {
            log.info("Thrift RPC: Delete data");
            
            // Convert Thrift request to your DTO (perfect match)
            com.tsinghua.dto.DataQueryRequest dto = convertToDataQueryRequest(request);
            
            // Call your existing service method directly
            dataTableService.deleteData(dto);
            
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "删除成功");
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Delete data failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Delete failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result queryRelationalData(com.tsinghua.thrift.api.RelationalQueryRequest request) throws TException {
        try {
            log.info("Thrift RPC: Query relational data");
            
            // Convert Thrift request to your DTO (perfect match)
            com.tsinghua.dto.RelationalQueryRequest dto = convertToRelationalQueryRequest(request);
            
            // Call your existing service method directly
            com.tsinghua.dto.TableDto result = relationalDataService.queryData(dto);
            
            // Convert result to JSON string
            String jsonData = convertTableDtoToJson(result);
            
            com.tsinghua.thrift.api.Result thriftResult = new com.tsinghua.thrift.api.Result(true, "Query successful");
            thriftResult.setData(jsonData);
            return thriftResult;
        } catch (Exception e) {
            log.error("Thrift RPC: Query relational data failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Query failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result countRelationalData(com.tsinghua.thrift.api.RelationalQueryRequest request) throws TException {
        try {
            log.info("Thrift RPC: Count relational data");
            
            // Convert Thrift request to your DTO (perfect match)
            com.tsinghua.dto.RelationalQueryRequest dto = convertToRelationalQueryRequest(request);
            
            // Call your existing service method directly
            Object count = relationalDataService.countData(dto);
            
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "Count successful");
            result.setData(String.valueOf(count));
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Count relational data failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Count failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result importData(String config, ByteBuffer file) throws TException {
        try {
            log.info("Thrift RPC: Import data");
            
            // Note: File import via Thrift is complex, this is a placeholder
            // In practice, you might need to handle this differently or use HTTP for file upload
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Data import via Thrift not implemented, use HTTP endpoint");
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Import data failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Import failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result exportData(com.tsinghua.thrift.api.DataQueryRequest request) throws TException {
        try {
            log.info("Thrift RPC: Export data");
            
            // Note: File export via Thrift is complex, this is a placeholder
            // In practice, you might need to handle this differently or use HTTP for file download
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Data export via Thrift not implemented, use HTTP endpoint");
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Export data failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Export failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result exportRelationalData(com.tsinghua.thrift.api.RelationalQueryRequest request) throws TException {
        try {
            log.info("Thrift RPC: Export relational data");
            
            // Note: File export via Thrift is complex, this is a placeholder
            // In practice, you might need to handle this differently or use HTTP for file download
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Data export via Thrift not implemented, use HTTP endpoint");
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Export relational data failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Export failed: " + e.getMessage());
            return result;
        }
    }

    // ========== Model File Interface - Match ModelFileController ==========

    @Override
    public com.tsinghua.thrift.api.Result uploadModel(ByteBuffer file) throws TException {
        try {
            log.info("Thrift RPC: Upload model file");
            
            // Note: File upload via Thrift is complex, this is a placeholder
            // In practice, you might need to handle this differently or use HTTP for file upload
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "File upload via Thrift not implemented, use HTTP endpoint");
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Upload model failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Upload failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result downloadModel(String name, String version) throws TException {
        try {
            log.info("Thrift RPC: Download model {}@{}", name, version);
            
            // Note: File download via Thrift is complex, this is a placeholder
            // In practice, you might need to handle this differently or use HTTP for file download
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "File download via Thrift not implemented, use HTTP endpoint");
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Download model failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Download failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result extractModelFile(com.tsinghua.thrift.api.ExtractModelFileRequest request) throws TException {
        try {
            log.info("Thrift RPC: Extract model file {}@{}", request.getName(), request.getVersion());
            
            // Convert Thrift request to your DTO (perfect match)
            com.tsinghua.dto.ExtractModelFileRequest dto = convertToExtractModelFileRequest(request);
            
            // Call your existing service method directly - use extractModelFile instead of extractModelFileForParsing
            // Note: extractModelFile requires a Path parameter for the task directory
            // For Thrift RPC, we'll create a temporary directory or use a default path
            java.nio.file.Path tempDir = java.nio.file.Paths.get("temp", "model-extract", System.currentTimeMillis() + "");
            java.nio.file.Files.createDirectories(tempDir);
            
            Object result = modelFileService.extractModelFile(dto.getName(), dto.getVersion(), tempDir);
            
            // Convert result to JSON string
            String jsonData = convertEntityToJson(result);
            com.tsinghua.thrift.api.Result thriftResult = new com.tsinghua.thrift.api.Result(true, "文件提取成功");
            thriftResult.setData(jsonData);
            return thriftResult;
        } catch (Exception e) {
            log.error("Thrift RPC: Extract model file failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Extract failed: " + e.getMessage());
            return result;
        }
    }

    // ========== Existing Model File Interface Methods ==========

    @Override
    public com.tsinghua.thrift.api.Result saveModelMeta(com.tsinghua.thrift.api.ModelMeta modelMeta) throws TException {
        try {
            log.info("Thrift RPC: Save model meta {}", modelMeta.getName());
            
            // Convert Thrift object to your Entity (perfect match)
            ModelMetaEntity entity = convertToModelMetaEntity(modelMeta);
            
            // Call your existing service method directly
            modelFileService.saveModelMetadata(entity);
            
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "元数据保存成功");
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Save model meta failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Save failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result getModelMeta(String name, String version) throws TException {
        try {
            log.info("Thrift RPC: Get model meta {}@{}", name, version);
            
            // Call your existing service method directly
            ModelMetaEntity entity = modelFileService.queryMeta(name, version);
            
            if (entity == null) {
                com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Model not found");
                return result;
            }
            
            // Convert to JSON string
            String jsonData = convertEntityToJson(entity);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "Query successful");
            result.setData(jsonData);
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Get model meta failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Query failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result getModelHistory(String name) throws TException {
        try {
            log.info("Thrift RPC: Get model history {}", name);
            
            // Call your existing service method directly
            java.util.List<ModelMetaEntity> history = modelFileService.queryMetaList(name);
            
            // Convert result to JSON string
            String jsonData = convertListToJson(history);
            
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "Query successful");
            result.setData(jsonData);
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Get model history failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Query failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result deleteModel(String name, String version) throws TException {
        try {
            log.info("Thrift RPC: Delete model {}@{}", name, version);
            
            // Call your existing service method directly
            modelFileService.deleteModel(name, version);
            
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "操作成功");
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Delete model failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Delete failed: " + e.getMessage());
            return result;
        }
    }

    // ========== New Conversion Methods for ParsingRules and RunTask ==========

    private ParsingRulesEntity convertToParsingRulesEntity(com.tsinghua.thrift.api.ParsingRule thriftRule) {
        ParsingRulesEntity entity = new ParsingRulesEntity();
        entity.setName(thriftRule.getName());
        entity.setRegexPattern(thriftRule.getRegexPattern());
        if (thriftRule.isSetExample()) {
            entity.setExample(thriftRule.getExample());
        }
        entity.setCreateTime(thriftRule.getCreateTime());
        entity.setUpdateTime(thriftRule.getUpdateTime());
        return entity;
    }

    private com.tsinghua.dto.ParsingRulesQueryRequest convertToParsingRulesQueryRequest(com.tsinghua.thrift.api.ParsingRulesQueryRequest thriftRequest) {
        com.tsinghua.dto.ParsingRulesQueryRequest dto = new com.tsinghua.dto.ParsingRulesQueryRequest();
        dto.setPageNum(thriftRequest.getPageNum());
        dto.setPageSize(thriftRequest.getPageSize());
        if (thriftRequest.isSetName()) {
            dto.setName(thriftRequest.getName());
        }
        return dto;
    }

    private com.tsinghua.dto.RunTaskRequest convertToRunTaskRequest(com.tsinghua.thrift.api.RunTaskRequest thriftRequest) {
        com.tsinghua.dto.RunTaskRequest dto = new com.tsinghua.dto.RunTaskRequest();
        dto.setName(thriftRequest.getName());
        dto.setStartTime(thriftRequest.getStartTime());
        dto.setEndTime(thriftRequest.getEndTime());
        dto.setRuleName(thriftRequest.getRuleName());
        dto.setRuleId(thriftRequest.getRuleId());
        if (thriftRequest.isSetModelName()) {
            dto.setAlgorithmName(thriftRequest.getModelName());
        }
        if (thriftRequest.isSetModelVersion()) {
            dto.setAlgorithmVersion(thriftRequest.getModelVersion());
        }
        if (thriftRequest.isSetOutputTable()) {
            dto.setOutputTable(thriftRequest.getOutputTable());
        }
        return dto;
    }

    private com.tsinghua.dto.RunTaskQueryRequest convertToRunTaskQueryRequest(com.tsinghua.thrift.api.RunTaskQueryRequest thriftRequest) {
        com.tsinghua.dto.RunTaskQueryRequest dto = new com.tsinghua.dto.RunTaskQueryRequest();
        dto.setPageNum(thriftRequest.getPageNum());
        dto.setPageSize(thriftRequest.getPageSize());
        if (thriftRequest.isSetName()) {
            dto.setName(thriftRequest.getName());
        }
        if (thriftRequest.isSetStatus()) {
            dto.setStatus(thriftRequest.getStatus());
        }
        if (thriftRequest.isSetRuleId()) {
            dto.setRuleId(thriftRequest.getRuleId());
        }
        if (thriftRequest.isSetStartTime()) {
            dto.setStartTime(thriftRequest.getStartTime());
        }
        if (thriftRequest.isSetEndTime()) {
            dto.setEndTime(thriftRequest.getEndTime());
        }
        return dto;
    }

    private com.tsinghua.dto.ExtractModelFileRequest convertToExtractModelFileRequest(com.tsinghua.thrift.api.ExtractModelFileRequest thriftRequest) {
        com.tsinghua.dto.ExtractModelFileRequest dto = new com.tsinghua.dto.ExtractModelFileRequest();
        dto.setName(thriftRequest.getName());
        dto.setVersion(thriftRequest.getVersion());
        return dto;
    }

    // ========== Existing Data Conversion Utility Methods - Perfectly Match Your DTOs ==========

    private AssociationRulesEntity convertToAssociationRulesEntity(com.tsinghua.thrift.api.AssociationRule thriftRule) {
        AssociationRulesEntity entity = new AssociationRulesEntity();
        entity.setName(thriftRule.getName());
        entity.setDescription(thriftRule.getDescription());
        entity.setTableName(thriftRule.getTableName());
        entity.setAlgorithmName(thriftRule.getModelName());
        entity.setAlgorithmVersion(thriftRule.getModelVersion());
        entity.setStatus(thriftRule.isStatus());
        entity.setCreateTime(thriftRule.getCreateTime());
        entity.setUpdateTime(thriftRule.getUpdateTime());
        entity.setInputsBind(thriftRule.getInputsBind());
        entity.setOutputsBind(thriftRule.getOutputsBind());
        return entity;
    }

    private com.tsinghua.dto.AssociationRulesQueryRequest convertToAssociationRulesQueryRequest(com.tsinghua.thrift.api.AssociationRulesQueryRequest thriftRequest) {
        com.tsinghua.dto.AssociationRulesQueryRequest dto = new com.tsinghua.dto.AssociationRulesQueryRequest();
        dto.setPageNum(thriftRequest.getPageNum());
        dto.setPageSize(thriftRequest.getPageSize());
        if (thriftRequest.isSetName()) {
            dto.setName(thriftRequest.getName());
        }
        if (thriftRequest.isSetStatus()) {
            dto.setStatus(thriftRequest.getStatus());
        }
        return dto;
    }

    private StorageEngineInfoDto convertToStorageEngineInfoDto(com.tsinghua.thrift.api.StorageEngineInfo thriftInfo) {
        StorageEngineInfoDto dto = new StorageEngineInfoDto();
        if (thriftInfo.isSetId()) {
            dto.setId(thriftInfo.getId());
        }
        if (thriftInfo.isSetIp()) {
            dto.setIp(thriftInfo.getIp());
        }
        if (thriftInfo.isSetPort()) {
            dto.setPort(thriftInfo.getPort());
        }
        if (thriftInfo.isSetType()) {
            dto.setType(thriftInfo.getType());
        }
        if (thriftInfo.isSetSchemaPrefix()) {
            dto.setSchemaPrefix(thriftInfo.getSchemaPrefix());
        }
        if (thriftInfo.isSetDataPrefix()) {
            dto.setDataPrefix(thriftInfo.getDataPrefix());
        }
        return dto;
    }

    private com.tsinghua.dto.DataQueryRequest convertToDataQueryRequest(com.tsinghua.thrift.api.DataQueryRequest thriftRequest) {
        com.tsinghua.dto.DataQueryRequest dto = new com.tsinghua.dto.DataQueryRequest();
        if (thriftRequest.isSetPaths()) {
            dto.setPaths(thriftRequest.getPaths());
        }
        if (thriftRequest.isSetStartTime()) {
            dto.setStartTime(thriftRequest.getStartTime());
        }
        if (thriftRequest.isSetEndTime()) {
            dto.setEndTime(thriftRequest.getEndTime());
        }
        if (thriftRequest.isSetAggregateType()) {
            dto.setAggregateType(thriftRequest.getAggregateType());
        }
        if (thriftRequest.isSetPrecision()) {
            dto.setPrecision(thriftRequest.getPrecision());
        }
        if (thriftRequest.isSetTimePrecision()) {
            dto.setTimePrecision(thriftRequest.getTimePrecision());
        }
        return dto;
    }

    private com.tsinghua.dto.RelationalQueryRequest convertToRelationalQueryRequest(com.tsinghua.thrift.api.RelationalQueryRequest thriftRequest) {
        com.tsinghua.dto.RelationalQueryRequest dto = new com.tsinghua.dto.RelationalQueryRequest();
        dto.setPageNum(thriftRequest.getPageNum());
        dto.setPageSize(thriftRequest.getPageSize());
        if (thriftRequest.isSetTableName()) {
            dto.setTableName(thriftRequest.getTableName());
        }
        if (thriftRequest.isSetFilters()) {
            // Convert Thrift FilterCondition to DTO FilterCondition (perfect match)
            java.util.List<com.tsinghua.dto.RelationalQueryRequest.FilterCondition> dtoFilters = new java.util.ArrayList<>();
            for (com.tsinghua.thrift.api.FilterCondition thriftFilter : thriftRequest.getFilters()) {
                com.tsinghua.dto.RelationalQueryRequest.FilterCondition dtoFilter = new com.tsinghua.dto.RelationalQueryRequest.FilterCondition();
                dtoFilter.setField(thriftFilter.getField());
                dtoFilter.setOperator(thriftFilter.getOperator());
                dtoFilter.setValue(thriftFilter.getValue());
                if (thriftFilter.isSetLogicOperator()) {
                    dtoFilter.setLogicOperator(thriftFilter.getLogicOperator());
                }
                if (thriftFilter.isSetStartGroup()) {
                    dtoFilter.setStartGroup(thriftFilter.isStartGroup());
                }
                if (thriftFilter.isSetEndGroup()) {
                    dtoFilter.setEndGroup(thriftFilter.isEndGroup());
                }
                dtoFilters.add(dtoFilter);
            }
            dto.setFilters(dtoFilters);
        }
        if (thriftRequest.isSetSortField()) {
            dto.setSortField(thriftRequest.getSortField());
        }
        if (thriftRequest.isSetSortDirection()) {
            dto.setSortDirection(thriftRequest.getSortDirection());
        }
        return dto;
    }

    private ModelMetaEntity convertToModelMetaEntity(com.tsinghua.thrift.api.ModelMeta thriftMeta) {
        ModelMetaEntity entity = new ModelMetaEntity();
        entity.setName(thriftMeta.getName());
        entity.setVersion(thriftMeta.getVersion());
        entity.setFileName(thriftMeta.getFileName());
        if (thriftMeta.isSetFileSize()) {
            entity.setFileSize(thriftMeta.getFileSize());
        }
        if (thriftMeta.isSetChunkCount()) {
            entity.setChunkCount(thriftMeta.getChunkCount());
        }
        if (thriftMeta.isSetStoragePath()) {
            entity.setStoragePath(thriftMeta.getStoragePath());
        }
        if (thriftMeta.isSetFileMd5()) {
            entity.setFileMd5(thriftMeta.getFileMd5());
        }
        if (thriftMeta.isSetAuthor()) {
            entity.setAuthor(thriftMeta.getAuthor());
        }
        if (thriftMeta.isSetScene()) {
            entity.setScene(thriftMeta.getScene());
        }
        if (thriftMeta.isSetInputs()) {
            entity.setInputs(thriftMeta.getInputs());
        }
        if (thriftMeta.isSetOutputs()) {
            entity.setOutputs(thriftMeta.getOutputs());
        }
        if (thriftMeta.isSetTimestamp()) {
            entity.setTimestamp(thriftMeta.getTimestamp());
        }
        return entity;
    }

    // JSON conversion utility methods
    private String convertEntityToJson(Object entity) throws Exception {
        com.fasterxml.jackson.databind.ObjectMapper mapper = new com.fasterxml.jackson.databind.ObjectMapper();
        return mapper.writeValueAsString(entity);
    }

    private String convertListToJson(java.util.List<?> list) throws Exception {
        com.fasterxml.jackson.databind.ObjectMapper mapper = new com.fasterxml.jackson.databind.ObjectMapper();
        return mapper.writeValueAsString(list);
    }

    private String convertTableDtoToJson(com.tsinghua.dto.TableDto tableDto) throws Exception {
        com.fasterxml.jackson.databind.ObjectMapper mapper = new com.fasterxml.jackson.databind.ObjectMapper();
        // Your TableDto has header and records fields
        return mapper.writeValueAsString(tableDto);
    }
}
