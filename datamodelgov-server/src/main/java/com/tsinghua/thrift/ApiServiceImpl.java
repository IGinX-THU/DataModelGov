package com.tsinghua.thrift;

import com.tsinghua.dto.*;
import com.tsinghua.entity.AssociationRulesEntity;
import com.tsinghua.entity.ModelMetaEntity;
import com.tsinghua.service.*;
import com.tsinghua.thrift.api.*;
import lombok.extern.slf4j.Slf4j;
import org.apache.thrift.TException;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

/**
 * DataModelGov Thrift API Service Implementation
 * Exposes your existing services as Thrift RPC interfaces
 * Completely matches your actual Controller methods and DTO structures
 * Excludes ApiGenerationController as requested
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

    // ========== Model File Interface - Match ModelFileController ==========

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

    // ========== Data Conversion Utility Methods - Perfectly Match Your DTOs ==========

    private AssociationRulesEntity convertToAssociationRulesEntity(com.tsinghua.thrift.api.AssociationRule thriftRule) {
        AssociationRulesEntity entity = new AssociationRulesEntity();
        entity.setName(thriftRule.getName());
        entity.setDescription(thriftRule.getDescription());
        entity.setTableName(thriftRule.getTableName());
        entity.setModelName(thriftRule.getModelName());
        entity.setModelVersion(thriftRule.getModelVersion());
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
