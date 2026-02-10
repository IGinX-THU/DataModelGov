package com.tsinghua.config;

import cn.edu.tsinghua.iginx.session.Session;
import cn.edu.tsinghua.iginx.session_v2.IginXClient;
import cn.edu.tsinghua.iginx.session_v2.IginXClientFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * IGinX配置类
 */
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

    @Bean
    public IginXClient iginxClient() {
        // 创建IGinX客户端连接
        return IginXClientFactory.create(ip, port, username, password);
    }

    @Bean
    public Session iginxSession() {
        // 创建IGinX客户端连接
        return new Session(ip, port, username, password);
    }

}
