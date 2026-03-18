package com.tsinghua.thrift;

import com.tsinghua.thrift.api.ApiService;
import lombok.extern.slf4j.Slf4j;
import org.apache.thrift.server.TServer;
import org.apache.thrift.server.TThreadPoolServer;
import org.apache.thrift.transport.TServerSocket;
import org.apache.thrift.transport.TTransportException;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.CommandLineRunner;
import org.springframework.stereotype.Component;

/**
 * DataModelGov Thrift服务器启动器
 * 在Spring Boot应用启动时自动启动Thrift服务器
 */
@Slf4j
@Component
public class ThriftServerRunner implements CommandLineRunner {

    @Autowired
    private ApiServiceImpl apiServiceImpl;

    private static final int THRIFT_PORT = 9090;

    @Override
    public void run(String... args) throws Exception {
        // 在后台线程中启动Thrift服务器，避免阻塞Spring Boot启动
        Thread thriftServerThread = new Thread(() -> {
            try {
                startThriftServer();
            } catch (Exception e) {
                log.error("Thrift服务器启动失败", e);
            }
        });
        
        thriftServerThread.setDaemon(false); // 设置为非守护线程，确保应用运行时服务器持续运行
        thriftServerThread.setName("thrift-server-thread");
        thriftServerThread.start();
        
        log.info("🚀 DataModelGov Thrift服务器启动线程已创建，将在后台启动...");
    }

    /**
     * 启动Thrift服务器
     */
    private void startThriftServer() {
        try {
            // 创建服务处理器
            ApiService.Processor processor = new ApiService.Processor(apiServiceImpl);
            
            // 创建服务器传输
            TServerSocket serverTransport = new TServerSocket(THRIFT_PORT);
            
            // 创建线程池服务器（支持多线程处理）
            TThreadPoolServer.Args serverArgs = new TThreadPoolServer.Args(serverTransport)
                    .processor(processor)
                    .minWorkerThreads(5)    // 最小工作线程数
                    .maxWorkerThreads(20);   // 最大工作线程数
            
            // 创建服务器
            TServer server = new TThreadPoolServer(serverArgs);
            
            log.info("🚀 DataModelGov Thrift服务器启动在端口 {}...", THRIFT_PORT);
            log.info("📡 DataModelGov Thrift服务已就绪，支持Go/Java/Python客户端连接...");
            log.info("🔧 线程池配置: 最小5线程，最大20线程");
            
            // 启动服务器（这会阻塞当前线程）
            server.serve();
            
        } catch (TTransportException e) {
            log.error("Thrift服务器传输异常", e);
        } catch (Exception e) {
            log.error("Thrift服务器运行异常", e);
        }
    }
}
