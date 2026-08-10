package com.tsinghua.config;

import cn.edu.tsinghua.iginx.exception.SessionException;
import cn.edu.tsinghua.iginx.session.Session;
import cn.edu.tsinghua.iginx.session_v2.IginXClient;
import cn.edu.tsinghua.iginx.session_v2.IginXClientFactory;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * IGinX配置类 - 统一Session管理版本
 * 通过SessionProxy自动管理Session的打开和关闭，业务代码无需手动管理
 */
@Slf4j
@Configuration
public class IginxConfig {

    @Value("${iginx.ip}")
    private String ip;

    @Value("${iginx.port}")
    private int port;

    @Value("${iginx.username}")
    private String username;

    @Value("${iginx.password}")
    private String password;

    @Value("${iginx.max-retry:3}")
    private int maxRetry;

    // Session状态管理
    private static final ThreadLocal<Session> sessionHolder = new ThreadLocal<>();
    private static final ThreadLocal<Boolean> sessionOpen = new ThreadLocal<Boolean>() {
        @Override
        protected Boolean initialValue() {
            return false;
        }
    };

    @Bean
    public IginXClient iginxClient() {
        return IginXClientFactory.create(ip, port, username, password);
    }

    @Bean
    public Session iginxSession() {
        // 创建Session代理，自动管理生命周期
        Session originalSession = new Session(ip, port, username, password);
        SessionProxy proxy = new SessionProxy(originalSession);
        proxy.setMaxRetry(maxRetry);
        return proxy;
    }

    /**
     * Session代理类 - 自动管理open/close
     */
    public static class SessionProxy extends Session {
        private final Session delegate;
        private int maxRetry;

        public SessionProxy(Session delegate) {
            super(delegate.getHost(), delegate.getPort(), delegate.getUsername(), delegate.getPassword());
            this.delegate = delegate;
            this.maxRetry = 3; // 默认重试3次
            sessionHolder.set(this);
        }

        public void setMaxRetry(int maxRetry) {
            this.maxRetry = maxRetry;
        }

        @Override
        public void openSession() throws SessionException {
            if (sessionOpen.get()) {
                log.warn("⚠️ Session已经打开，跳过重复打开");
                return;
            }
            
            log.info("🔓 自动打开Session");
            delegate.openSession();
            sessionOpen.set(true);
        }

        @Override
        public void closeSession() throws SessionException {
            if (!sessionOpen.get()) {
                log.warn("⚠️ Session未打开，跳过关闭");
                return;
            }
            
            log.info("🔒 自动关闭Session");
            delegate.closeSession();
            sessionOpen.set(false);
        }

        @Override
        public cn.edu.tsinghua.iginx.session.QueryDataSet executeQuery(String sql) throws SessionException {
            return executeWithRetry("executeQuery", () -> delegate.executeQuery(sql));
        }

        @Override
        public cn.edu.tsinghua.iginx.session.SessionExecuteSqlResult executeSql(String sql) throws SessionException {
            return executeWithRetry("executeSql", () -> delegate.executeSql(sql));
        }

        @Override
        public java.util.List<cn.edu.tsinghua.iginx.session.Column> showColumns() throws SessionException {
            return executeWithRetry("showColumns", () -> delegate.showColumns());
        }

        @Override
        public cn.edu.tsinghua.iginx.session.ClusterInfo getClusterInfo() throws SessionException {
            return executeWithRetry("getClusterInfo", () -> delegate.getClusterInfo());
        }

        @Override
        public void addStorageEngine(String ip, int port, cn.edu.tsinghua.iginx.thrift.StorageEngineType type, java.util.Map<String, String> extraParams) throws SessionException {
            executeWithRetry("addStorageEngine", () -> {
                delegate.addStorageEngine(ip, port, type, extraParams);
                return null;
            });
        }

        @Override
        public void removeStorageEngine(java.util.List<cn.edu.tsinghua.iginx.thrift.RemovedStorageEngineInfo> removedStorageEngineList) throws SessionException {
            executeWithRetry("removeStorageEngine", () -> {
                delegate.removeStorageEngine(removedStorageEngineList);
                return null;
            });
        }

        @Override
        public cn.edu.tsinghua.iginx.utils.Pair<java.util.List<String>, Long> executeLoadCSV(String sql, String uploadedFileName) throws SessionException {
            return executeWithRetry("executeLoadCSV", () -> delegate.executeLoadCSV(sql, uploadedFileName));
        }

        @Override
        public void uploadFileChunk(cn.edu.tsinghua.iginx.thrift.FileChunk chunk) throws SessionException {
            executeWithRetry("uploadFileChunk", () -> {
                delegate.uploadFileChunk(chunk);
                return null;
            });
        }

        @Override
        public long commitTransformJob(java.util.List<cn.edu.tsinghua.iginx.thrift.TaskInfo> taskInfoList, cn.edu.tsinghua.iginx.thrift.ExportType exportType, String filePath) throws SessionException {
            return executeWithRetry("commitTransformJob", () -> delegate.commitTransformJob(taskInfoList, exportType, filePath));
        }

        @Override
        public long commitTransformJob(java.util.List<cn.edu.tsinghua.iginx.thrift.TaskInfo> taskInfoList, cn.edu.tsinghua.iginx.thrift.ExportType exportType, String fileName, String schedule) throws SessionException {
            return executeWithRetry("commitTransformJob", () -> delegate.commitTransformJob(taskInfoList, exportType, fileName, schedule));
        }

        @Override
        public long commitTransformJob(java.util.List<cn.edu.tsinghua.iginx.thrift.TaskInfo> taskInfoList, cn.edu.tsinghua.iginx.thrift.ExportType exportType, String fileName, String schedule, boolean stopOnFailure) throws SessionException {
            return executeWithRetry("commitTransformJob", () -> delegate.commitTransformJob(taskInfoList, exportType, fileName, schedule, stopOnFailure));
        }

        @Override
        public long commitTransformJob(String statement) throws SessionException {
            return executeWithRetry("commitTransformJob", () -> delegate.commitTransformJob(statement));
        }

        @Override
        public long commitTransformJobByYaml(String filepath) throws SessionException {
            return executeWithRetry("commitTransformJobByYaml", () -> delegate.commitTransformJobByYaml(filepath));
        }

        @Override
        public cn.edu.tsinghua.iginx.thrift.JobState queryTransformJobStatus(long jobId) throws SessionException {
            return executeWithRetry("queryTransformJobStatus", () -> delegate.queryTransformJobStatus(jobId));
        }

        @Override
        public java.util.Map<cn.edu.tsinghua.iginx.thrift.JobState, java.util.List<Long>> showEligibleJob(cn.edu.tsinghua.iginx.thrift.JobState jobState) throws SessionException {
            return executeWithRetry("showEligibleJob", () -> delegate.showEligibleJob(jobState));
        }

        @Override
        public void cancelTransformJob(long jobId) throws SessionException {
            executeWithRetry("cancelTransformJob", () -> {
                delegate.cancelTransformJob(jobId);
                return null;
            });
        }

        @Override
        public cn.edu.tsinghua.iginx.session.QueryDataSet executeQuery(String statement, int fetchSize) throws SessionException {
            return executeWithRetry("executeQuery", () -> delegate.executeQuery(statement, fetchSize));
        }

        @Override
        public void addStorageEngines(java.util.List<cn.edu.tsinghua.iginx.thrift.StorageEngine> storageEngines) throws SessionException {
            executeWithRetry("addStorageEngines", () -> {
                delegate.addStorageEngines(storageEngines);
                return null;
            });
        }

        @Override
        public cn.edu.tsinghua.iginx.session.CurveMatchResult curveMatch(java.util.List<String> paths, long startKey, long endKey, java.util.List<Double> curveQuery, long curveUnit) throws SessionException {
            return executeWithRetry("curveMatch", () -> delegate.curveMatch(paths, startKey, endKey, curveQuery, curveUnit));
        }

        @Override
        public cn.edu.tsinghua.iginx.thrift.LoadUDFResp executeRegisterTask(String statement) throws SessionException {
            return executeWithRetry("executeRegisterTask", () -> delegate.executeRegisterTask(statement));
        }

        @Override
        public cn.edu.tsinghua.iginx.thrift.LoadUDFResp executeRegisterTask(String statement, boolean isRemote) throws SessionException {
            return executeWithRetry("executeRegisterTask", () -> delegate.executeRegisterTask(statement, isRemote));
        }

        @Override
        public int getReplicaNum() throws SessionException {
            return executeWithRetry("getReplicaNum", () -> delegate.getReplicaNum());
        }

        @Override
        public cn.edu.tsinghua.iginx.session.SessionQueryDataSet queryLast(java.util.List<String> paths, long startKey, cn.edu.tsinghua.iginx.thrift.TimePrecision timePrecision) throws SessionException {
            return executeWithRetry("queryLast", () -> delegate.queryLast(paths, startKey, timePrecision));
        }

        @Override
        public cn.edu.tsinghua.iginx.session.SessionQueryDataSet queryLast(java.util.List<String> paths, long startKey) throws SessionException {
            return executeWithRetry("queryLast", () -> delegate.queryLast(paths, startKey));
        }

        @Override
        public cn.edu.tsinghua.iginx.session.SessionQueryDataSet queryLast(java.util.List<String> paths, long startKey, java.util.List<java.util.Map<String, java.util.List<String>>> tagsList) throws SessionException {
            return executeWithRetry("queryLast", () -> delegate.queryLast(paths, startKey, tagsList));
        }

        @Override
        public cn.edu.tsinghua.iginx.session.SessionQueryDataSet queryLast(java.util.List<String> paths, long startKey, java.util.List<java.util.Map<String, java.util.List<String>>> tagsList, cn.edu.tsinghua.iginx.thrift.TimePrecision timePrecision) throws SessionException {
            return executeWithRetry("queryLast", () -> delegate.queryLast(paths, startKey, tagsList, timePrecision));
        }

        @Override
        public cn.edu.tsinghua.iginx.session.SessionQueryDataSet queryData(java.util.List<String> paths, long startKey, long endKey) throws SessionException {
            return executeWithRetry("queryData", () -> delegate.queryData(paths, startKey, endKey));
        }

        @Override
        public cn.edu.tsinghua.iginx.session.SessionQueryDataSet queryData(java.util.List<String> paths, long startKey, long endKey, java.util.List<java.util.Map<String, java.util.List<String>>> tagsList) throws SessionException {
            return executeWithRetry("queryData", () -> delegate.queryData(paths, startKey, endKey, tagsList));
        }

        @Override
        public cn.edu.tsinghua.iginx.session.SessionQueryDataSet queryData(java.util.List<String> paths, long startKey, long endKey, java.util.List<java.util.Map<String, java.util.List<String>>> tagsList, cn.edu.tsinghua.iginx.thrift.TimePrecision timePrecision) throws SessionException {
            return executeWithRetry("queryData", () -> delegate.queryData(paths, startKey, endKey, tagsList, timePrecision));
        }

        @Override
        public cn.edu.tsinghua.iginx.session.SessionAggregateQueryDataSet aggregateQuery(java.util.List<String> paths, long startKey, long endKey, cn.edu.tsinghua.iginx.thrift.AggregateType aggregateType) throws SessionException {
            return executeWithRetry("aggregateQuery", () -> delegate.aggregateQuery(paths, startKey, endKey, aggregateType));
        }

        @Override
        public cn.edu.tsinghua.iginx.session.SessionAggregateQueryDataSet aggregateQuery(java.util.List<String> paths, long startKey, long endKey, cn.edu.tsinghua.iginx.thrift.AggregateType aggregateType, cn.edu.tsinghua.iginx.thrift.TimePrecision timePrecision) throws SessionException {
            return executeWithRetry("aggregateQuery", () -> delegate.aggregateQuery(paths, startKey, endKey, aggregateType, timePrecision));
        }

        @Override
        public cn.edu.tsinghua.iginx.session.SessionAggregateQueryDataSet aggregateQuery(java.util.List<String> paths, long startKey, long endKey, cn.edu.tsinghua.iginx.thrift.AggregateType aggregateType, java.util.List<java.util.Map<String, java.util.List<String>>> tagsList) throws SessionException {
            return executeWithRetry("aggregateQuery", () -> delegate.aggregateQuery(paths, startKey, endKey, aggregateType, tagsList));
        }

        @Override
        public cn.edu.tsinghua.iginx.session.SessionAggregateQueryDataSet aggregateQuery(java.util.List<String> paths, long startKey, long endKey, cn.edu.tsinghua.iginx.thrift.AggregateType aggregateType, java.util.List<java.util.Map<String, java.util.List<String>>> tagsList, cn.edu.tsinghua.iginx.thrift.TimePrecision timePrecision) throws SessionException {
            return executeWithRetry("aggregateQuery", () -> delegate.aggregateQuery(paths, startKey, endKey, aggregateType, tagsList, timePrecision));
        }

        @Override
        public cn.edu.tsinghua.iginx.session.SessionQueryDataSet downsampleQuery(java.util.List<String> paths, long startKey, long endKey, cn.edu.tsinghua.iginx.thrift.AggregateType aggregateType, long precision, cn.edu.tsinghua.iginx.thrift.TimePrecision timePrecision) throws SessionException {
            return executeWithRetry("downsampleQuery", () -> delegate.downsampleQuery(paths, startKey, endKey, aggregateType, precision, timePrecision));
        }

        @Override
        public cn.edu.tsinghua.iginx.session.SessionQueryDataSet downsampleQuery(java.util.List<String> paths, long startKey, long endKey, cn.edu.tsinghua.iginx.thrift.AggregateType aggregateType, long precision) throws SessionException {
            return executeWithRetry("downsampleQuery", () -> delegate.downsampleQuery(paths, startKey, endKey, aggregateType, precision));
        }

        @Override
        public cn.edu.tsinghua.iginx.session.SessionQueryDataSet downsampleQuery(java.util.List<String> paths, long startKey, long endKey, cn.edu.tsinghua.iginx.thrift.AggregateType aggregateType, long precision, java.util.List<java.util.Map<String, java.util.List<String>>> tagsList) throws SessionException {
            return executeWithRetry("downsampleQuery", () -> delegate.downsampleQuery(paths, startKey, endKey, aggregateType, precision, tagsList));
        }

        @Override
        public cn.edu.tsinghua.iginx.session.SessionQueryDataSet downsampleQuery(java.util.List<String> paths, long startKey, long endKey, cn.edu.tsinghua.iginx.thrift.AggregateType aggregateType, long precision, java.util.List<java.util.Map<String, java.util.List<String>>> tagsList, cn.edu.tsinghua.iginx.thrift.TimePrecision timePrecision) throws SessionException {
            return executeWithRetry("downsampleQuery", () -> delegate.downsampleQuery(paths, startKey, endKey, aggregateType, precision, tagsList, timePrecision));
        }

        @Override
        public void addUser(String username, String password, java.util.Set<cn.edu.tsinghua.iginx.thrift.AuthType> auths) throws SessionException {
            executeWithRetry("addUser", () -> {
                delegate.addUser(username, password, auths);
                return null;
            });
        }

        @Override
        public void updateUser(String username, String password, java.util.Set<cn.edu.tsinghua.iginx.thrift.AuthType> auths) throws SessionException {
            executeWithRetry("updateUser", () -> {
                delegate.updateUser(username, password, auths);
                return null;
            });
        }

        @Override
        public void deleteUser(String username) throws SessionException {
            executeWithRetry("deleteUser", () -> {
                delegate.deleteUser(username);
                return null;
            });
        }

        @Override
        public void deleteColumn(String path) throws SessionException {
            executeWithRetry("deleteColumn", () -> {
                delegate.deleteColumn(path);
                return null;
            });
        }

        @Override
        public void deleteColumns(java.util.List<String> paths) throws SessionException {
            executeWithRetry("deleteColumns", () -> {
                delegate.deleteColumns(paths);
                return null;
            });
        }

        @Override
        public void deleteColumns(java.util.List<String> paths, java.util.List<java.util.Map<String, java.util.List<String>>> tags, cn.edu.tsinghua.iginx.thrift.TagFilterType type) throws SessionException {
            executeWithRetry("deleteColumns", () -> {
                delegate.deleteColumns(paths, tags, type);
                return null;
            });
        }

        @Override
        public void deleteDataInColumn(String path, long startKey, long endKey) throws SessionException {
            executeWithRetry("deleteDataInColumn", () -> {
                delegate.deleteDataInColumn(path, startKey, endKey);
                return null;
            });
        }

        @Override
        public void deleteDataInColumns(java.util.List<String> paths, long startKey, long endKey) throws SessionException {
            executeWithRetry("deleteDataInColumns", () -> {
                delegate.deleteDataInColumns(paths, startKey, endKey);
                return null;
            });
        }

        @Override
        public void deleteDataInColumns(java.util.List<String> paths, long startKey, long endKey, java.util.List<java.util.Map<String, java.util.List<String>>> tagsList, cn.edu.tsinghua.iginx.thrift.TagFilterType type) throws SessionException {
            executeWithRetry("deleteDataInColumns", () -> {
                delegate.deleteDataInColumns(paths, startKey, endKey, tagsList, type);
                return null;
            });
        }

        @Override
        public void insertColumnRecords(java.util.List<String> paths, long[] keys, Object[] valuesList, java.util.List<cn.edu.tsinghua.iginx.thrift.DataType> dataTypeList) throws SessionException {
            executeWithRetry("insertColumnRecords", () -> {
                delegate.insertColumnRecords(paths, keys, valuesList, dataTypeList);
                return null;
            });
        }

        @Override
        public void insertColumnRecords(java.util.List<String> paths, long[] keys, Object[] valuesList, java.util.List<cn.edu.tsinghua.iginx.thrift.DataType> dataTypeList, java.util.List<java.util.Map<String, String>> tagsList) throws SessionException {
            executeWithRetry("insertColumnRecords", () -> {
                delegate.insertColumnRecords(paths, keys, valuesList, dataTypeList, tagsList);
                return null;
            });
        }

        @Override
        public void insertColumnRecords(java.util.List<String> paths, long[] keys, Object[] valuesList, java.util.List<cn.edu.tsinghua.iginx.thrift.DataType> dataTypeList, java.util.List<java.util.Map<String, String>> tagsList, cn.edu.tsinghua.iginx.thrift.TimePrecision precision) throws SessionException {
            executeWithRetry("insertColumnRecords", () -> {
                delegate.insertColumnRecords(paths, keys, valuesList, dataTypeList, tagsList, precision);
                return null;
            });
        }

        @Override
        public void insertNonAlignedColumnRecords(java.util.List<String> paths, long[] keys, Object[] valuesList, java.util.List<cn.edu.tsinghua.iginx.thrift.DataType> dataTypeList) throws SessionException {
            executeWithRetry("insertNonAlignedColumnRecords", () -> {
                delegate.insertNonAlignedColumnRecords(paths, keys, valuesList, dataTypeList);
                return null;
            });
        }

        @Override
        public void insertNonAlignedColumnRecords(java.util.List<String> paths, long[] keys, Object[] valuesList, java.util.List<cn.edu.tsinghua.iginx.thrift.DataType> dataTypeList, java.util.List<java.util.Map<String, String>> tagsList) throws SessionException {
            executeWithRetry("insertNonAlignedColumnRecords", () -> {
                delegate.insertNonAlignedColumnRecords(paths, keys, valuesList, dataTypeList, tagsList);
                return null;
            });
        }

        @Override
        public void insertNonAlignedColumnRecords(java.util.List<String> paths, long[] keys, Object[] valuesList, java.util.List<cn.edu.tsinghua.iginx.thrift.DataType> dataTypeList, java.util.List<java.util.Map<String, String>> tagsList, cn.edu.tsinghua.iginx.thrift.TimePrecision precision) throws SessionException {
            executeWithRetry("insertNonAlignedColumnRecords", () -> {
                delegate.insertNonAlignedColumnRecords(paths, keys, valuesList, dataTypeList, tagsList, precision);
                return null;
            });
        }

        @Override
        public void insertRowRecords(java.util.List<String> paths, long[] keys, Object[] valuesList, java.util.List<cn.edu.tsinghua.iginx.thrift.DataType> dataTypeList, java.util.List<java.util.Map<String, String>> tagsList) throws SessionException {
            executeWithRetry("insertRowRecords", () -> {
                delegate.insertRowRecords(paths, keys, valuesList, dataTypeList, tagsList);
                return null;
            });
        }

        @Override
        public void insertRowRecords(java.util.List<String> paths, long[] keys, Object[] valuesList, java.util.List<cn.edu.tsinghua.iginx.thrift.DataType> dataTypeList, java.util.List<java.util.Map<String, String>> tagsList, cn.edu.tsinghua.iginx.thrift.TimePrecision precision) throws SessionException {
            executeWithRetry("insertRowRecords", () -> {
                delegate.insertRowRecords(paths, keys, valuesList, dataTypeList, tagsList, precision);
                return null;
            });
        }

        @Override
        public void insertNonAlignedRowRecords(java.util.List<String> paths, long[] keys, Object[] valuesList, java.util.List<cn.edu.tsinghua.iginx.thrift.DataType> dataTypeList) throws SessionException {
            executeWithRetry("insertNonAlignedRowRecords", () -> {
                delegate.insertNonAlignedRowRecords(paths, keys, valuesList, dataTypeList);
                return null;
            });
        }

        @Override
        public void insertNonAlignedRowRecords(java.util.List<String> paths, long[] keys, Object[] valuesList, java.util.List<cn.edu.tsinghua.iginx.thrift.DataType> dataTypeList, java.util.List<java.util.Map<String, String>> tagsList) throws SessionException {
            executeWithRetry("insertNonAlignedRowRecords", () -> {
                delegate.insertNonAlignedRowRecords(paths, keys, valuesList, dataTypeList, tagsList);
                return null;
            });
        }

        @Override
        public void insertNonAlignedRowRecords(java.util.List<String> paths, long[] keys, Object[] valuesList, java.util.List<cn.edu.tsinghua.iginx.thrift.DataType> dataTypeList, java.util.List<java.util.Map<String, String>> tagsList, cn.edu.tsinghua.iginx.thrift.TimePrecision precision) throws SessionException {
            executeWithRetry("insertNonAlignedRowRecords", () -> {
                delegate.insertNonAlignedRowRecords(paths, keys, valuesList, dataTypeList, tagsList, precision);
                return null;
            });
        }

        /**
         * 确保Session已打开
         */
        private void ensureSessionOpen() throws SessionException {
            if (!sessionOpen.get()) {
                log.info("🔓 检测到Session未打开，自动打开");
                delegate.openSession();
                sessionOpen.set(true);
            }
        }

        /**
         * 带重试机制的操作执行
         * 检测到连接异常时自动重连并重试
         */
        private <T> T executeWithRetry(String operation, SessionOperation<T> op) throws SessionException {
            int retryCount = 0;
            SessionException lastException = null;

            while (retryCount <= maxRetry) {
                try {
                    ensureSessionOpen();
                    return op.execute();
                } catch (SessionException e) {
                    lastException = e;
                    
                    // 检查是否是连接相关的异常
                    if (isConnectionError(e)) {
                        retryCount++;
                        if (retryCount <= maxRetry) {
                            log.warn("⚠️ 检测到连接异常: {} - 尝试重连 (第 {}/{})", 
                                    e.getMessage(), retryCount, maxRetry);
                            
                            // 关闭旧连接
                            try {
                                delegate.closeSession();
                            } catch (Exception closeEx) {
                                log.warn("关闭旧连接时异常: {}", closeEx.getMessage());
                            }
                            sessionOpen.set(false);
                            
                            // 短暂等待后重试
                            try {
                                Thread.sleep(100 * retryCount);
                            } catch (InterruptedException ie) {
                                Thread.currentThread().interrupt();
                                throw new SessionException("重试被中断", ie);
                            }
                            
                            continue;
                        }
                    }
                    
                    // 不是连接错误或重试次数用尽，直接抛出异常
                    throw e;
                }
            }
            
            log.error("❌ 操作失败，已达最大重试次数: {}", maxRetry);
            throw lastException;
        }

        /**
         * 判断是否是连接相关的异常
         */
        private boolean isConnectionError(SessionException e) {
            if (e == null) {
                return false;
            }
            
            String message = e.getMessage();
            if (message == null) {
                return false;
            }
            
            // 检查常见的连接错误特征
            return message.contains("Connection reset") ||
                   message.contains("socket write error") ||
                   message.contains("SocketException") ||
                   message.contains("TTransportException") ||
                   message.contains("Connection refused") ||
                   message.contains("Broken pipe") ||
                   message.contains("Connection timed out");
        }

        @FunctionalInterface
        private interface SessionOperation<T> {
            T execute() throws SessionException;
        }

        // 委托其他方法
        @Override
        public String getHost() {
            return delegate.getHost();
        }

        @Override
        public int getPort() {
            return delegate.getPort();
        }

        @Override
        public String getUsername() {
            return delegate.getUsername();
        }

        @Override
        public String getPassword() {
            return delegate.getPassword();
        }
    }

}
