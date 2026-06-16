package com.tsinghua.thrift;

import com.tsinghua.util.ProjectContext;
import com.tsinghua.dto.*;
import com.tsinghua.entity.AlgorithmMetaEntity;
import com.tsinghua.entity.AssociationRulesEntity;
import com.tsinghua.entity.DataArchiveEntity;
import com.tsinghua.entity.ModelMetaEntity;
import com.tsinghua.entity.ParsingRulesEntity;
import com.tsinghua.entity.ProjectEntity;
import com.tsinghua.entity.RunTaskEntity;
import com.tsinghua.entity.SimulationArchiveEntity;
import com.tsinghua.entity.SimulationExecutionEntity;
import com.tsinghua.service.*;
import com.tsinghua.auth.service.DataPermissionService;
import com.tsinghua.auth.service.RolePermissionService;
import com.tsinghua.auth.dto.DataPermissionQueryRequest;
import com.tsinghua.auth.dto.DataPermissionUpdateRequest;
import com.tsinghua.auth.entity.DataPermissionEntity;
import com.tsinghua.auth.entity.RoleEntity;
import com.tsinghua.auth.entity.UserEntity;
import com.tsinghua.auth.util.JwtUtil;
import com.tsinghua.thrift.api.*;
import lombok.extern.slf4j.Slf4j;
import org.apache.thrift.TException;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;
import java.nio.ByteBuffer;
import java.util.Map;

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

    @Autowired
    private AlgorithmFileService algorithmFileService;

    @Autowired
    private DataArchiveService dataArchiveService;

    @Autowired
    private ProjectService projectService;

    @Autowired
    private ProjectImportService projectImportService;

    @Autowired
    private ProjectExportService projectExportService;

    @Autowired
    private SimulationArchiveService simulationArchiveService;

    @Autowired
    private SimulationExecutionService simulationExecutionService;

    @Autowired
    private RolePermissionService rolePermissionService;

    @Autowired
    private DataPermissionService dataPermissionService;

    @Autowired
    private JwtUtil jwtUtil;

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
    public com.tsinghua.thrift.api.Result uploadReport(ByteBuffer file, long timestamp) throws TException {
        try {
            log.info("Thrift RPC: Upload report file for task {}", timestamp);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "File upload via Thrift not implemented, use HTTP endpoint");
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Upload report failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Upload failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result getTimeRange(com.tsinghua.thrift.api.TimeRangeRequest request) throws TException {
        try {
            log.info("Thrift RPC: Get time range for table {}", request.getTableName());
            com.tsinghua.dto.TimeRangeRequest dto = convertToTimeRangeRequest(request);
            com.tsinghua.dto.TimeRangeResponse response = runTaskService.getTimeRange(dto);
            String jsonData = convertEntityToJson(response);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "查询成功");
            result.setData(jsonData);
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Get time range failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Query failed: " + e.getMessage());
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
    public com.tsinghua.thrift.api.Result uploadModel(ByteBuffer file, String name, String version) throws TException {
        try {
            log.info("Thrift RPC: Upload model file {}@{}", name, version);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "File upload via Thrift not implemented, use HTTP endpoint");
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Upload model failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Upload failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result getModelTree(String projectName) throws TException {
        try {
            log.info("Thrift RPC: Get model tree for project {}", projectName);
            java.util.List<String> tree = modelFileService.queryModelTree(projectName);
            String jsonData = convertListToJson(tree);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "Query successful");
            result.setData(jsonData);
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Get model tree failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Query failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result queryModelArchives(com.tsinghua.thrift.api.ModelArchiveQueryRequest request) throws TException {
        try {
            log.info("Thrift RPC: Query model archives");
            String name = request.isSetName() ? request.getName() : null;
            String projectName = request.isSetProjectName() ? request.getProjectName() : null;
            String author = request.isSetAuthor() ? request.getAuthor() : null;
            java.util.List<ModelMetaEntity> archives = modelFileService.queryModelArchives(name, projectName, author, request.getPageNum(), request.getPageSize());
            String jsonData = convertListToJson(archives);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "Query successful");
            result.setData(jsonData);
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Query model archives failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Query failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result countModelArchives(com.tsinghua.thrift.api.ModelArchiveQueryRequest request) throws TException {
        try {
            log.info("Thrift RPC: Count model archives");
            String name = request.isSetName() ? request.getName() : null;
            String projectName = request.isSetProjectName() ? request.getProjectName() : null;
            String author = request.isSetAuthor() ? request.getAuthor() : null;
            java.util.List<ModelMetaEntity> archives = modelFileService.queryModelArchives(name, projectName, author, 1, Integer.MAX_VALUE);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "Count successful");
            result.setData(String.valueOf(archives.size()));
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Count model archives failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Count failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result downloadModel(String name, String version, String projectName) throws TException {
        try {
            log.info("Thrift RPC: Download model {}@{}, projectName: {}", name, version, projectName);
            
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
    public com.tsinghua.thrift.api.Result getModelHistory(String name, String projectName) throws TException {
        try {
            log.info("Thrift RPC: Get model history {}, projectName: {}", name, projectName);
            
            // Use provided projectName or fallback to current project
            String actualProjectName = (projectName != null && !projectName.isEmpty()) 
                ? projectName 
                : com.tsinghua.util.ProjectContext.getCurrentProject("unknown");
            
            // Call your existing service method directly
            java.util.List<ModelMetaEntity> history = modelFileService.queryMetaList(name, actualProjectName);
            
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
    public com.tsinghua.thrift.api.Result deleteModel(String name, String version, String projectName) throws TException {
        try {
            log.info("Thrift RPC: Delete model {}@{}, projectName: {}", name, version, projectName);
            
            // Use provided projectName or fallback to current project
            String actualProjectName = (projectName != null && !projectName.isEmpty()) 
                ? projectName 
                : com.tsinghua.util.ProjectContext.getCurrentProject("unknown");
            
            // Call your existing service method directly with projectName
            modelFileService.deleteModel(name, version, actualProjectName);
            
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "操作成功");
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Delete model failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Delete failed: " + e.getMessage());
            return result;
        }
    }

    // ========== Association Rules - New Methods ==========

    @Override
    public com.tsinghua.thrift.api.Result validateAssociationRuleName(String name) throws TException {
        try {
            log.info("Thrift RPC: Validate association rule name {}", name);
            associationRulesService.validateNameUniqueness(name);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "名称可用");
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Validate association rule name failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Validation failed: " + e.getMessage());
            return result;
        }
    }

    // ========== Parsing Rules - New Methods ==========

    @Override
    public com.tsinghua.thrift.api.Result validateParsingRuleName(String name) throws TException {
        try {
            log.info("Thrift RPC: Validate parsing rule name {}", name);
            parsingRulesService.validateNameUniqueness(name);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "名称可用");
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Validate parsing rule name failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Validation failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result autoParseSourceCode(com.tsinghua.thrift.api.AutoParseRequest request) throws TException {
        try {
            log.info("Thrift RPC: Auto parse source code, file={}", request.getFileName());
            com.tsinghua.dto.AutoParseRequest dto = convertToAutoParseRequest(request);
            Object parsedResult = parsingRulesService.headerScanner(
                dto.getFileContent(), dto.getFileName(), dto.getRegexPattern(),
                dto.getParseType() != null ? dto.getParseType() : "regex",
                dto.getMaxLines() != null ? dto.getMaxLines() : 50);
            String jsonData = convertEntityToJson(parsedResult);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "解析成功");
            result.setData(jsonData);
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Auto parse source code failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Parse failed: " + e.getMessage());
            return result;
        }
    }

    // ========== Algorithm File Interface - Match AlgorithmFileController ==========

    @Override
    public com.tsinghua.thrift.api.Result uploadAlgorithm(ByteBuffer file, String name, String version) throws TException {
        try {
            log.info("Thrift RPC: Upload algorithm file {}@{}", name, version);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "File upload via Thrift not implemented, use HTTP endpoint");
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Upload algorithm failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Upload failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result downloadAlgorithm(String name, String version, String projectName) throws TException {
        try {
            log.info("Thrift RPC: Download algorithm {}@{}, projectName: {}", name, version, projectName);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "File download via Thrift not implemented, use HTTP endpoint");
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Download algorithm failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Download failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result getAlgorithmMeta(String name, String version) throws TException {
        try {
            log.info("Thrift RPC: Get algorithm meta {}@{}", name, version);
            AlgorithmMetaEntity entity = algorithmFileService.queryMeta(name, version);
            if (entity == null) {
                com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Algorithm not found");
                return result;
            }
            String jsonData = convertEntityToJson(entity);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "Query successful");
            result.setData(jsonData);
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Get algorithm meta failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Query failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result saveAlgorithmMeta(com.tsinghua.thrift.api.AlgorithmMeta algorithmMeta) throws TException {
        try {
            log.info("Thrift RPC: Save algorithm meta {}", algorithmMeta.getName());
            AlgorithmMetaEntity entity = convertToAlgorithmMetaEntity(algorithmMeta);
            algorithmFileService.saveAlgorithmMetadata(entity);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "元数据保存成功");
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Save algorithm meta failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Save failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result getAlgorithmHistory(String name, String projectName) throws TException {
        try {
            log.info("Thrift RPC: Get algorithm history {}, projectName: {}", name, projectName);
            
            // Use provided projectName or fallback to current project
            String actualProjectName = (projectName != null && !projectName.isEmpty()) 
                ? projectName 
                : com.tsinghua.util.ProjectContext.getCurrentProject("unknown");
            
            java.util.List<AlgorithmMetaEntity> history = algorithmFileService.queryMetaList(name, actualProjectName);
            String jsonData = convertListToJson(history);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "Query successful");
            result.setData(jsonData);
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Get algorithm history failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Query failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result deleteAlgorithm(String name, String version, String projectName) throws TException {
        try {
            log.info("Thrift RPC: Delete algorithm {}@{}, projectName: {}", name, version, projectName);
            
            // Use provided projectName or fallback to current project
            String actualProjectName = (projectName != null && !projectName.isEmpty()) 
                ? projectName 
                : com.tsinghua.util.ProjectContext.getCurrentProject("unknown");
            
            algorithmFileService.deleteAlgorithm(name, version, actualProjectName);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "操作成功");
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Delete algorithm failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Delete failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result getAlgorithmTree(String projectName) throws TException {
        try {
            log.info("Thrift RPC: Get algorithm tree for project {}", projectName);
            java.util.List<String> tree = algorithmFileService.queryAlgorithmTree(projectName);
            String jsonData = convertListToJson(tree);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "Query successful");
            result.setData(jsonData);
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Get algorithm tree failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Query failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result queryAlgorithmArchives(com.tsinghua.thrift.api.AlgorithmArchiveQueryRequest request) throws TException {
        try {
            log.info("Thrift RPC: Query algorithm archives");
            String name = request.isSetName() ? request.getName() : null;
            String algorithmType = request.isSetAlgorithmType() ? request.getAlgorithmType() : null;
            String projectName = request.isSetProjectName() ? request.getProjectName() : null;
            String owner = request.isSetOwner() ? request.getOwner() : null;
            String author = request.isSetAuthor() ? request.getAuthor() : null;
            java.util.List<AlgorithmMetaEntity> archives = algorithmFileService.queryAlgorithmArchives(name, projectName, author, request.getPageNum(), request.getPageSize());
            String jsonData = convertListToJson(archives);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "Query successful");
            result.setData(jsonData);
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Query algorithm archives failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Query failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result countAlgorithmArchives(com.tsinghua.thrift.api.AlgorithmArchiveQueryRequest request) throws TException {
        try {
            log.info("Thrift RPC: Count algorithm archives");
            String name = request.isSetName() ? request.getName() : null;
            String projectName = request.isSetProjectName() ? request.getProjectName() : null;
            String author = request.isSetAuthor() ? request.getAuthor() : null;
            java.util.List<AlgorithmMetaEntity> archives = algorithmFileService.queryAlgorithmArchives(name, projectName, author, 1, Integer.MAX_VALUE);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "Count successful");
            result.setData(String.valueOf(archives.size()));
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Count algorithm archives failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Count failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result extractAlgorithmFile(com.tsinghua.thrift.api.ExtractAlgorithmFileRequest request) throws TException {
        try {
            log.info("Thrift RPC: Extract algorithm file {}@{}", request.getName(), request.getVersion());
            java.nio.file.Path tempDir = java.nio.file.Paths.get("temp", "algorithm-extract", System.currentTimeMillis() + "");
            java.nio.file.Files.createDirectories(tempDir);
            Object result = algorithmFileService.extractAlgorithmFile(request.getName(), request.getVersion(), tempDir);
            String jsonData = convertEntityToJson(result);
            com.tsinghua.thrift.api.Result thriftResult = new com.tsinghua.thrift.api.Result(true, "文件提取成功");
            thriftResult.setData(jsonData);
            return thriftResult;
        } catch (Exception e) {
            log.error("Thrift RPC: Extract algorithm file failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Extract failed: " + e.getMessage());
            return result;
        }
    }

    // ========== Data Archive Interface - Match DataArchiveController ==========

    @Override
    public com.tsinghua.thrift.api.Result queryDataArchives(com.tsinghua.thrift.api.DataArchiveQueryRequest request) throws TException {
        try {
            log.info("Thrift RPC: Query data archives");
            String name = request.isSetName() ? request.getName() : null;
            String type = request.isSetType() ? request.getType() : null;
            String projectName = request.isSetProjectName() ? request.getProjectName() : null;
            String owner = request.isSetOwner() ? request.getOwner() : null;
            java.util.List<DataArchiveEntity> archives = dataArchiveService.queryArchives(name, type, projectName, owner, request.getPageNum(), request.getPageSize());
            String jsonData = convertListToJson(archives);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "Query successful");
            result.setData(jsonData);
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Query data archives failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Query failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result getDataArchiveDetail(String name) throws TException {
        try {
            log.info("Thrift RPC: Get data archive detail {}", name);
            DataArchiveEntity entity = dataArchiveService.findByName(name);
            if (entity == null) {
                com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "未找到指定的数据档案");
                return result;
            }
            String jsonData = convertEntityToJson(entity);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "Query successful");
            result.setData(jsonData);
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Get data archive detail failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Query failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result countDataArchives(com.tsinghua.thrift.api.DataArchiveQueryRequest request) throws TException {
        try {
            log.info("Thrift RPC: Count data archives");
            String name = request.isSetName() ? request.getName() : null;
            String type = request.isSetType() ? request.getType() : null;
            String projectName = request.isSetProjectName() ? request.getProjectName() : null;
            String owner = request.isSetOwner() ? request.getOwner() : null;
            java.util.List<DataArchiveEntity> archives = dataArchiveService.queryArchives(name, type, projectName, owner, 1, Integer.MAX_VALUE);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "Count successful");
            result.setData(String.valueOf(archives.size()));
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Count data archives failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Count failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result deleteDataArchive(com.tsinghua.thrift.api.DataArchiveQueryRequest request) throws TException {
        try {
            log.info("Thrift RPC: Delete data archive");
            Long id = request.isSetId() ? request.getId() : null;
            if (id == null) {
                com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "ID不能为空");
                return result;
            }
            dataArchiveService.deleteArchive(id);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "操作成功");
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Delete data archive failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Delete failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result updateDataArchive(com.tsinghua.thrift.api.DataArchive archive) throws TException {
        try {
            log.info("Thrift RPC: Update data archive {}", archive.getName());
            DataArchiveEntity entity = convertToDataArchiveEntity(archive);
            dataArchiveService.saveArchive(entity);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "更新成功");
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Update data archive failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Update failed: " + e.getMessage());
            return result;
        }
    }

    // ========== Project Interface - Match ProjectController ==========

    @Override
    public com.tsinghua.thrift.api.Result createProject(com.tsinghua.thrift.api.Project project) throws TException {
        try {
            log.info("Thrift RPC: Create project {}", project.getName());
            ProjectEntity entity = convertToProjectEntity(project);
            projectService.createProject(entity);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "项目创建成功");
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Create project failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Create failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result queryProjects(com.tsinghua.thrift.api.ProjectsQueryRequest request) throws TException {
        try {
            log.info("Thrift RPC: Query projects");
            com.tsinghua.dto.ProjectsQueryRequest dto = convertToProjectsQueryRequest(request);
            java.util.List<ProjectEntity> projects = projectService.queryProjects(dto);
            String jsonData = convertListToJson(projects);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "Query successful");
            result.setData(jsonData);
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Query projects failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Query failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result countProjects(com.tsinghua.thrift.api.ProjectsQueryRequest request) throws TException {
        try {
            log.info("Thrift RPC: Count projects");
            com.tsinghua.dto.ProjectsQueryRequest dto = convertToProjectsQueryRequest(request);
            Object count = projectService.countProjects(dto);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "Count successful");
            result.setData(String.valueOf(count));
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Count projects failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Count failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result getProject(long createTime) throws TException {
        try {
            log.info("Thrift RPC: Get project detail {}", createTime);
            ProjectEntity entity = projectService.findById(createTime);
            if (entity == null) {
                com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "未找到指定的项目");
                return result;
            }
            String jsonData = convertEntityToJson(entity);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "Query successful");
            result.setData(jsonData);
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Get project detail failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Query failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result getProjectTree(String name) throws TException {
        try {
            log.info("Thrift RPC: Get project tree for {}", name);
            Object tree = projectService.buildProjectTree(name);
            String jsonData = convertEntityToJson(tree);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "Query successful");
            result.setData(jsonData);
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Get project tree failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Query failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result importProject(ByteBuffer file, String projectName) throws TException {
        try {
            log.info("Thrift RPC: Import project {}", projectName);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "File import via Thrift not implemented, use HTTP endpoint");
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Import project failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Import failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result exportProject(com.tsinghua.thrift.api.ProjectExportRequest request) throws TException {
        try {
            log.info("Thrift RPC: Export project {}", request.getProjectName());
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "File export via Thrift not implemented, use HTTP endpoint");
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Export project failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Export failed: " + e.getMessage());
            return result;
        }
    }

    // ========== Simulation Archive Interface - Match SimulationArchiveController ==========

    @Override
    public com.tsinghua.thrift.api.Result saveSimulationArchive(com.tsinghua.thrift.api.SimulationArchive archive) throws TException {
        try {
            log.info("Thrift RPC: Save simulation archive {}", archive.getName());
            SimulationArchiveEntity entity = convertToSimulationArchiveEntity(archive);
            simulationArchiveService.saveArchive(entity);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "仿真档案保存成功");
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Save simulation archive failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Save failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result querySimulationArchives(String name, String projectName, String owner, boolean status, int pageNum, int pageSize) throws TException {
        try {
            log.info("Thrift RPC: Query simulation archives");
            java.util.List<SimulationArchiveEntity> archives = simulationArchiveService.queryArchives(name, projectName, owner, status, pageNum, pageSize);
            String jsonData = convertListToJson(archives);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "Query successful");
            result.setData(jsonData);
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Query simulation archives failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Query failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result countSimulationArchives(String name, String projectName, String owner, boolean status) throws TException {
        try {
            log.info("Thrift RPC: Count simulation archives");
            Object count = simulationArchiveService.countArchives(name, projectName, owner, status);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "Count successful");
            result.setData(String.valueOf(count));
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Count simulation archives failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Count failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result getSimulationArchive(long createTime) throws TException {
        try {
            log.info("Thrift RPC: Get simulation archive detail {}", createTime);
            SimulationArchiveEntity entity = simulationArchiveService.queryArchive(createTime);
            if (entity == null) {
                com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "未找到指定的仿真档案");
                return result;
            }
            String jsonData = convertEntityToJson(entity);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "Query successful");
            result.setData(jsonData);
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Get simulation archive detail failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Query failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result deleteSimulationArchive(long createTime) throws TException {
        try {
            log.info("Thrift RPC: Delete simulation archive {}", createTime);
            simulationArchiveService.deleteArchive(createTime);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "操作成功");
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Delete simulation archive failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Delete failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result validateSimulationArchiveName(String name) throws TException {
        try {
            log.info("Thrift RPC: Validate simulation archive name {}", name);
            simulationArchiveService.validateNameUniqueness(name);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "名称可用");
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Validate simulation archive name failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Validation failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result copySimulationArchive(long createTime, String newName) throws TException {
        try {
            log.info("Thrift RPC: Copy simulation archive {} to {}", createTime, newName);
            SimulationArchiveEntity copied = simulationArchiveService.copyArchive(createTime, newName);
            String jsonData = convertEntityToJson(copied);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "复制成功");
            result.setData(jsonData);
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Copy simulation archive failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Copy failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result runSimulation(long createTime) throws TException {
        try {
            log.info("Thrift RPC: Run simulation {}", createTime);
            com.tsinghua.model.Result<Void> simResult = simulationExecutionService.runSimulation(createTime);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(simResult.getSuccess(), simResult.getMessage());
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Run simulation failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Run failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result runSimulationSelective(com.tsinghua.thrift.api.RunSimulationSelectiveRequest request) throws TException {
        try {
            log.info("Thrift RPC: Run simulation selective for {}", request.getCreateTime());
            java.util.List<String> selectedNodeIds = request.isSetSelectedNodeIds() ? request.getSelectedNodeIds() : null;
            com.tsinghua.model.Result<Void> simResult = simulationExecutionService.runSimulation(request.getCreateTime(), selectedNodeIds);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(simResult.getSuccess(), simResult.getMessage());
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Run simulation selective failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Run failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result stopSimulation(long createTime) throws TException {
        try {
            log.info("Thrift RPC: Stop simulation {}", createTime);
            com.tsinghua.model.Result<Void> simResult = simulationExecutionService.stopSimulation(createTime);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(simResult.getSuccess(), simResult.getMessage());
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Stop simulation failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Stop failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result getSimulationExecutionStatus(long createTime) throws TException {
        try {
            log.info("Thrift RPC: Get simulation execution status {}", createTime);
            com.tsinghua.model.Result<Map<String, Object>> simResult = simulationExecutionService.getExecutionStatus(createTime);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(simResult.getSuccess(), simResult.getMessage());
            if (simResult.getData() != null) {
                result.setData(convertEntityToJson(simResult.getData()));
            }
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Get simulation execution status failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Query failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result getSimulationExecutionLog(long timestamp) throws TException {
        try {
            log.info("Thrift RPC: Get simulation execution log {}", timestamp);
            com.tsinghua.model.Result<Map<String, Object>> simResult = simulationExecutionService.getExecutionLog(timestamp);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(simResult.getSuccess(), simResult.getMessage());
            if (simResult.getData() != null) {
                result.setData(convertEntityToJson(simResult.getData()));
            }
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Get simulation execution log failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Query failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result querySimulationExecutionRecords(com.tsinghua.thrift.api.ExecutionRecordQueryRequest request) throws TException {
        try {
            log.info("Thrift RPC: Query simulation execution records");
            com.tsinghua.dto.ExecutionRecordQueryDto dto = convertToExecutionRecordQueryDto(request);
            Object records;
            if (com.tsinghua.auth.util.AuthUtil.isAdmin()) {
                records = simulationExecutionService.queryExecutions(dto.getArchiveName(), null, dto.getStatus(), dto.getStartTime(), dto.getEndTime(), dto.getPageNum(), dto.getPageSize());
            } else {
                records = simulationExecutionService.queryExecutions(dto.getArchiveName(), null, dto.getStatus(), dto.getStartTime(), dto.getEndTime(), dto.getPageNum(), dto.getPageSize());
            }
            String jsonData = convertEntityToJson(records);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "Query successful");
            result.setData(jsonData);
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Query simulation execution records failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Query failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result countSimulationExecutionRecords(com.tsinghua.thrift.api.ExecutionRecordQueryRequest request) throws TException {
        try {
            log.info("Thrift RPC: Count simulation execution records");
            com.tsinghua.dto.ExecutionRecordQueryDto dto = convertToExecutionRecordQueryDto(request);
            Object count = simulationExecutionService.countExecutions(dto.getArchiveName(), dto.getStatus(), dto.getStartTime(), dto.getEndTime());
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "Count successful");
            result.setData(String.valueOf(count));
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Count simulation execution records failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Count failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result deleteSimulationExecutionRecord(long timestamp) throws TException {
        try {
            log.info("Thrift RPC: Delete simulation execution record {}", timestamp);
            simulationExecutionService.deleteExecution(timestamp);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "操作成功");
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Delete simulation execution record failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Delete failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result uploadSimulationReport(ByteBuffer file, long timestamp) throws TException {
        try {
            log.info("Thrift RPC: Upload simulation report for {}", timestamp);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "File upload via Thrift not implemented, use HTTP endpoint");
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Upload simulation report failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Upload failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result simulationPackageDownload(long timestamp) throws TException {
        try {
            log.info("Thrift RPC: Simulation package download {}", timestamp);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "File download via Thrift not implemented, use HTTP endpoint");
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Simulation package download failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Download failed: " + e.getMessage());
            return result;
        }
    }

    // ========== Auth Interface - Match AuthController ==========

    @Override
    public com.tsinghua.thrift.api.Result login(com.tsinghua.thrift.api.LoginRequest loginRequest) throws TException {
        try {
            log.info("Thrift RPC: Login user {}", loginRequest.getUsername());
            // Auth login is handled via Spring Security, Thrift RPC provides basic support
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Login via Thrift not supported, use HTTP endpoint");
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Login failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Login failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result refreshToken(com.tsinghua.thrift.api.RefreshTokenRequest request) throws TException {
        try {
            log.info("Thrift RPC: Refresh token");
            String newToken = jwtUtil.refreshToken(request.getRefreshToken());
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "Token刷新成功");
            result.setData(newToken);
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Refresh token failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Refresh failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result verifyToken(String token) throws TException {
        try {
            log.info("Thrift RPC: Verify token");
            boolean valid = jwtUtil.validateToken(token, "");
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "验证完成");
            result.setData(String.valueOf(valid));
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Verify token failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Verify failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result logout() throws TException {
        try {
            log.info("Thrift RPC: Logout");
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "登出成功");
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Logout failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Logout failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result getCurrentAuthUser() throws TException {
        try {
            log.info("Thrift RPC: Get current auth user");
            String username = com.tsinghua.auth.util.AuthUtil.getCurrentUsername();
            UserEntity user = rolePermissionService.getUser(username);
            if (user == null) {
                com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "未找到当前用户");
                return result;
            }
            String jsonData = convertEntityToJson(user);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "Query successful");
            result.setData(jsonData);
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Get current auth user failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Query failed: " + e.getMessage());
            return result;
        }
    }

    // ========== User Interface - Match UserController ==========

    @Override
    public com.tsinghua.thrift.api.Result saveUser(com.tsinghua.thrift.api.User user) throws TException {
        try {
            log.info("Thrift RPC: Save user {}", user.getUsername());
            UserEntity entity = convertToUserEntity(user);
            rolePermissionService.addUser(entity);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "用户创建成功");
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Save user failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Save failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result queryUsers(com.tsinghua.thrift.api.UserQueryRequest request) throws TException {
        try {
            log.info("Thrift RPC: Query users");
            String username = request.isSetUsername() ? request.getUsername() : null;
            String role = request.isSetRole() ? request.getRole() : null;
            String enabled = request.isSetEnabled() ? request.getEnabled() : null;
            java.util.List<UserEntity> users = rolePermissionService.queryUsers(username, role, enabled, request.getPage(), request.getPageSize());
            String jsonData = convertListToJson(users);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "Query successful");
            result.setData(jsonData);
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Query users failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Query failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result countUsers(com.tsinghua.thrift.api.UserQueryRequest request) throws TException {
        try {
            log.info("Thrift RPC: Count users");
            String username = request.isSetUsername() ? request.getUsername() : null;
            String role = request.isSetRole() ? request.getRole() : null;
            String enabled = request.isSetEnabled() ? request.getEnabled() : null;
            java.util.List<UserEntity> users = rolePermissionService.queryUsers(username, role, enabled, 1, Integer.MAX_VALUE);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "Count successful");
            result.setData(String.valueOf(users.size()));
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Count users failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Count failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result allUsers() throws TException {
        try {
            log.info("Thrift RPC: Get all users");
            java.util.List<UserEntity> users = rolePermissionService.queryUsers(null, null, null, 1, Integer.MAX_VALUE);
            java.util.List<String> usernames = new java.util.ArrayList<>();
            for (UserEntity u : users) {
                usernames.add(u.getUsername());
            }
            String jsonData = convertListToJson(usernames);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "Query successful");
            result.setData(jsonData);
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Get all users failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Query failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result getUser(String username) throws TException {
        try {
            log.info("Thrift RPC: Get user detail {}", username);
            UserEntity entity = rolePermissionService.getUser(username);
            if (entity == null) {
                com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "未找到指定用户");
                return result;
            }
            String jsonData = convertEntityToJson(entity);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "Query successful");
            result.setData(jsonData);
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Get user detail failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Query failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result deleteUser(String username) throws TException {
        try {
            log.info("Thrift RPC: Delete user {}", username);
            rolePermissionService.removeUser(username);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "操作成功");
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Delete user failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Delete failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result updateUser(com.tsinghua.thrift.api.User user) throws TException {
        try {
            log.info("Thrift RPC: Update user {}", user.getUsername());
            UserEntity entity = convertToUserEntity(user);
            rolePermissionService.updateUser(entity);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "用户更新成功");
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Update user failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Update failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result getRoles() throws TException {
        try {
            log.info("Thrift RPC: Get roles");
            java.util.List<RoleEntity> roles = rolePermissionService.getAllRoles();
            String jsonData = convertListToJson(roles);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "Query successful");
            result.setData(jsonData);
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Get roles failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Query failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result changePassword(com.tsinghua.thrift.api.ChangePasswordRequest request) throws TException {
        try {
            log.info("Thrift RPC: Change password for {}", request.getUsername());
            boolean success = rolePermissionService.changePassword(request.getUsername(), request.getOldPassword(), request.getNewPassword());
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(success, success ? "密码修改成功" : "旧密码不正确");
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Change password failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Change password failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result getCurrentUser() throws TException {
        try {
            log.info("Thrift RPC: Get current user");
            String username = com.tsinghua.auth.util.AuthUtil.getCurrentUsername();
            UserEntity user = rolePermissionService.getUser(username);
            if (user == null) {
                com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "未找到当前用户");
                return result;
            }
            String jsonData = convertEntityToJson(user);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "Query successful");
            result.setData(jsonData);
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Get current user failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Query failed: " + e.getMessage());
            return result;
        }
    }

    // ========== Data Permission Interface - Match DataPermissionController ==========

    @Override
    public com.tsinghua.thrift.api.Result listOwnerTables() throws TException {
        try {
            log.info("Thrift RPC: List owner tables");
            java.util.List<DataPermissionEntity> tables = dataPermissionService.getOwnerTables();
            String jsonData = convertListToJson(tables);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "Query successful");
            result.setData(jsonData);
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: List owner tables failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Query failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result queryDataPermissions(com.tsinghua.thrift.api.DataPermissionQueryRequest request) throws TException {
        try {
            log.info("Thrift RPC: Query data permissions");
            com.tsinghua.auth.dto.DataPermissionQueryRequest authDto = convertToAuthDataPermissionQueryRequest(request);
            java.util.List<DataPermissionEntity> permissions = dataPermissionService.queryOwnerTables(authDto);
            String jsonData = convertListToJson(permissions);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "Query successful");
            result.setData(jsonData);
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Query data permissions failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Query failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result countDataPermissions(com.tsinghua.thrift.api.DataPermissionQueryRequest request) throws TException {
        try {
            log.info("Thrift RPC: Count data permissions");
            com.tsinghua.auth.dto.DataPermissionQueryRequest authDto = convertToAuthDataPermissionQueryRequest(request);
            long count = dataPermissionService.countOwnerTables(authDto);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "Count successful");
            result.setData(String.valueOf(count));
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Count data permissions failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Count failed: " + e.getMessage());
            return result;
        }
    }

    @Override
    public com.tsinghua.thrift.api.Result updateDataPermission(com.tsinghua.thrift.api.DataPermissionUpdateRequest request) throws TException {
        try {
            log.info("Thrift RPC: Update data permission {}", request.getId());
            com.tsinghua.auth.dto.DataPermissionUpdateRequest authDto = convertToAuthDataPermissionUpdateRequest(request);
            dataPermissionService.updateOwnerPermission(authDto);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(true, "更新成功");
            return result;
        } catch (Exception e) {
            log.error("Thrift RPC: Update data permission failed", e);
            com.tsinghua.thrift.api.Result result = new com.tsinghua.thrift.api.Result(false, "Update failed: " + e.getMessage());
            return result;
        }
    }

    // ========== New Conversion Methods ==========

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

    private com.tsinghua.dto.TimeRangeRequest convertToTimeRangeRequest(com.tsinghua.thrift.api.TimeRangeRequest thriftRequest) {
        com.tsinghua.dto.TimeRangeRequest dto = new com.tsinghua.dto.TimeRangeRequest();
        dto.setTableName(thriftRequest.getTableName());
        if (thriftRequest.isSetInputsBind()) {
            java.util.List<com.tsinghua.dto.InputBindDto> inputs = new java.util.ArrayList<>();
            for (com.tsinghua.thrift.api.InputBindDto thriftInput : thriftRequest.getInputsBind()) {
                com.tsinghua.dto.InputBindDto input = new com.tsinghua.dto.InputBindDto();
                input.setSourceField(thriftInput.getSourceField());
                input.setTargetField(thriftInput.getTargetField());
                input.setOperator(thriftInput.getOperator());
                input.setConversionValue(thriftInput.getConversionValue());
                inputs.add(input);
            }
            dto.setInputsBind(inputs);
        }
        return dto;
    }

    private com.tsinghua.dto.AutoParseRequest convertToAutoParseRequest(com.tsinghua.thrift.api.AutoParseRequest thriftRequest) {
        com.tsinghua.dto.AutoParseRequest dto = new com.tsinghua.dto.AutoParseRequest();
        dto.setFileContent(thriftRequest.getFileContent());
        dto.setFileName(thriftRequest.getFileName());
        if (thriftRequest.isSetParseType()) dto.setParseType(thriftRequest.getParseType());
        if (thriftRequest.isSetRegexPattern()) dto.setRegexPattern(thriftRequest.getRegexPattern());
        if (thriftRequest.isSetPythonModule()) dto.setPythonModule(thriftRequest.getPythonModule());
        if (thriftRequest.isSetPythonFunction()) dto.setPythonFunction(thriftRequest.getPythonFunction());
        if (thriftRequest.isSetMaxLines()) dto.setMaxLines(thriftRequest.getMaxLines());
        return dto;
    }

    private AlgorithmMetaEntity convertToAlgorithmMetaEntity(com.tsinghua.thrift.api.AlgorithmMeta thriftMeta) {
        AlgorithmMetaEntity entity = new AlgorithmMetaEntity();
        entity.setName(thriftMeta.getName());
        entity.setVersion(thriftMeta.getVersion());
        entity.setFileName(thriftMeta.getFileName());
        if (thriftMeta.isSetFileSize()) entity.setFileSize(thriftMeta.getFileSize());
        if (thriftMeta.isSetChunkCount()) entity.setChunkCount(thriftMeta.getChunkCount());
        if (thriftMeta.isSetStoragePath()) entity.setStoragePath(thriftMeta.getStoragePath());
        if (thriftMeta.isSetFileMd5()) entity.setFileMd5(thriftMeta.getFileMd5());
        if (thriftMeta.isSetAuthor()) entity.setAuthor(thriftMeta.getAuthor());
        if (thriftMeta.isSetScene()) entity.setScene(thriftMeta.getScene());
        if (thriftMeta.isSetInputs()) entity.setInputs(thriftMeta.getInputs());
        if (thriftMeta.isSetOutputs()) entity.setOutputs(thriftMeta.getOutputs());
        if (thriftMeta.isSetTimestamp()) entity.setTimestamp(thriftMeta.getTimestamp());
        if (thriftMeta.isSetCmd()) entity.setCmd(thriftMeta.getCmd());
        if (thriftMeta.isSetInputCsvName()) entity.setInputCsvName(thriftMeta.getInputCsvName());
        if (thriftMeta.isSetOutputCsvName()) entity.setOutputCsvName(thriftMeta.getOutputCsvName());
        if (thriftMeta.isSetAlgorithmType()) entity.setAlgorithmType(thriftMeta.getAlgorithmType());
        if (thriftMeta.isSetDependencies()) entity.setDependencies(thriftMeta.getDependencies());
        if (thriftMeta.isSetProjectName()) entity.setProjectName(thriftMeta.getProjectName());
        if (thriftMeta.isSetDescription()) entity.setDescription(thriftMeta.getDescription());
        if (thriftMeta.isSetTableName()) entity.setTableName(thriftMeta.getTableName());
        if (thriftMeta.isSetInputData()) entity.setInputData(thriftMeta.getInputData());
        if (thriftMeta.isSetCalledModels()) entity.setCalledModels(thriftMeta.getCalledModels());
        if (thriftMeta.isSetOutputFormat()) entity.setOutputFormat(thriftMeta.getOutputFormat());
        if (thriftMeta.isSetInputsBind()) entity.setInputsBind(thriftMeta.getInputsBind());
        if (thriftMeta.isSetOutputsBind()) entity.setOutputsBind(thriftMeta.getOutputsBind());
        if (thriftMeta.isSetOutputTable()) entity.setOutputTable(thriftMeta.getOutputTable());
        return entity;
    }

    private DataArchiveEntity convertToDataArchiveEntity(com.tsinghua.thrift.api.DataArchive thriftArchive) {
        DataArchiveEntity entity = new DataArchiveEntity();
        entity.setId(thriftArchive.getId());
        entity.setName(thriftArchive.getName());
        if (thriftArchive.isSetDesc()) entity.setDesc(thriftArchive.getDesc());
        if (thriftArchive.isSetProjectName()) entity.setProjectName(thriftArchive.getProjectName());
        if (thriftArchive.isSetOwner()) entity.setOwner(thriftArchive.getOwner());
        if (thriftArchive.isSetCreateTime()) entity.setCreateTime(thriftArchive.getCreateTime());
        if (thriftArchive.isSetType()) entity.setType(thriftArchive.getType());
        if (thriftArchive.isSetConfig()) entity.setConfig(thriftArchive.getConfig());
        return entity;
    }

    private ProjectEntity convertToProjectEntity(com.tsinghua.thrift.api.Project thriftProject) {
        ProjectEntity entity = new ProjectEntity();
        entity.setId(thriftProject.getId());
        entity.setName(thriftProject.getName());
        if (thriftProject.isSetDesc()) entity.setDesc(thriftProject.getDesc());
        if (thriftProject.isSetAlgorithms()) entity.setAlgorithms(thriftProject.getAlgorithms());
        if (thriftProject.isSetModels()) entity.setModels(thriftProject.getModels());
        if (thriftProject.isSetDatas()) entity.setDatas(thriftProject.getDatas());
        if (thriftProject.isSetCreateTime()) entity.setCreateTime(thriftProject.getCreateTime());
        if (thriftProject.isSetOwner()) entity.setOwner(thriftProject.getOwner());
        return entity;
    }

    private com.tsinghua.dto.ProjectsQueryRequest convertToProjectsQueryRequest(com.tsinghua.thrift.api.ProjectsQueryRequest thriftRequest) {
        com.tsinghua.dto.ProjectsQueryRequest dto = new com.tsinghua.dto.ProjectsQueryRequest();
        dto.setPageNum(thriftRequest.getPageNum());
        dto.setPageSize(thriftRequest.getPageSize());
        if (thriftRequest.isSetName()) dto.setName(thriftRequest.getName());
        if (thriftRequest.isSetAlgorithm()) dto.setAlgorithm(thriftRequest.getAlgorithm());
        if (thriftRequest.isSetModel()) dto.setModel(thriftRequest.getModel());
        if (thriftRequest.isSetData()) dto.setData(thriftRequest.getData());
        return dto;
    }

    private SimulationArchiveEntity convertToSimulationArchiveEntity(com.tsinghua.thrift.api.SimulationArchive thriftArchive) {
        SimulationArchiveEntity entity = new SimulationArchiveEntity();
        entity.setName(thriftArchive.getName());
        if (thriftArchive.isSetDescription()) entity.setDescription(thriftArchive.getDescription());
        if (thriftArchive.isSetGraphJson()) entity.setGraphJson(thriftArchive.getGraphJson());
        if (thriftArchive.isSetStatus()) entity.setStatus(thriftArchive.isStatus());
        if (thriftArchive.isSetCreateTime()) entity.setCreateTime(thriftArchive.getCreateTime());
        if (thriftArchive.isSetUpdateTime()) entity.setUpdateTime(thriftArchive.getUpdateTime());
        if (thriftArchive.isSetOwner()) entity.setOwner(thriftArchive.getOwner());
        if (thriftArchive.isSetProjectName()) entity.setProjectName(thriftArchive.getProjectName());
        if (thriftArchive.isSetScheduleCron()) entity.setScheduleCron(thriftArchive.getScheduleCron());
        if (thriftArchive.isSetOutputApiConfig()) entity.setOutputApiConfig(thriftArchive.getOutputApiConfig());
        if (thriftArchive.isSetLastExecutionTime()) entity.setLastExecutionTime(thriftArchive.getLastExecutionTime());
        if (thriftArchive.isSetExecutionCount()) entity.setExecutionCount(thriftArchive.getExecutionCount());
        if (thriftArchive.isSetIsRunning()) entity.setIsRunning(thriftArchive.isIsRunning());
        return entity;
    }

    private com.tsinghua.dto.ExecutionRecordQueryDto convertToExecutionRecordQueryDto(com.tsinghua.thrift.api.ExecutionRecordQueryRequest thriftRequest) {
        com.tsinghua.dto.ExecutionRecordQueryDto dto = new com.tsinghua.dto.ExecutionRecordQueryDto();
        if (thriftRequest.isSetArchiveName()) dto.setArchiveName(thriftRequest.getArchiveName());
        if (thriftRequest.isSetStatus()) dto.setStatus(thriftRequest.getStatus());
        if (thriftRequest.isSetStartTime()) dto.setStartTime(thriftRequest.getStartTime());
        if (thriftRequest.isSetEndTime()) dto.setEndTime(thriftRequest.getEndTime());
        dto.setPageNum(thriftRequest.getPageNum());
        dto.setPageSize(thriftRequest.getPageSize());
        return dto;
    }

    private UserEntity convertToUserEntity(com.tsinghua.thrift.api.User thriftUser) {
        UserEntity entity = new UserEntity();
        entity.setUsername(thriftUser.getUsername());
        if (thriftUser.isSetPassword()) entity.setPassword(thriftUser.getPassword());
        if (thriftUser.isSetRole()) entity.setRole(thriftUser.getRole());
        if (thriftUser.isSetRoleId()) entity.setRoleId(thriftUser.getRoleId());
        entity.setEnabled(thriftUser.isEnabled());
        if (thriftUser.isSetTimestamp()) entity.setTimestamp(thriftUser.getTimestamp());
        return entity;
    }

    private com.tsinghua.auth.dto.DataPermissionQueryRequest convertToAuthDataPermissionQueryRequest(com.tsinghua.thrift.api.DataPermissionQueryRequest thriftRequest) {
        com.tsinghua.auth.dto.DataPermissionQueryRequest dto = new com.tsinghua.auth.dto.DataPermissionQueryRequest();
        dto.setPage(thriftRequest.getPage());
        dto.setPageSize(thriftRequest.getPageSize());
        if (thriftRequest.isSetTablePrefix()) dto.setTablePrefix(thriftRequest.getTablePrefix());
        return dto;
    }

    private com.tsinghua.auth.dto.DataPermissionUpdateRequest convertToAuthDataPermissionUpdateRequest(com.tsinghua.thrift.api.DataPermissionUpdateRequest thriftRequest) {
        com.tsinghua.auth.dto.DataPermissionUpdateRequest dto = new com.tsinghua.auth.dto.DataPermissionUpdateRequest();
        dto.setId(thriftRequest.getId());
        if (thriftRequest.isSetIsPublic()) dto.setIsPublic(thriftRequest.isIsPublic());
        if (thriftRequest.isSetVisibleUsers()) dto.setVisibleUsers(thriftRequest.getVisibleUsers());
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
