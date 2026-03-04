package com.tsinghua;

import com.tsinghua.auth.config.JwtProperties;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.ComponentScan;

/**
 * 数据治理平台启动类
 */
@SpringBootApplication
@ComponentScan(basePackages = {"com.tsinghua", "com.tsinghua.auth"})
@EnableConfigurationProperties(JwtProperties.class)
public class DataModelGovApplication {

    public static void main(String[] args) {
        SpringApplication.run(DataModelGovApplication.class, args);
        System.out.println("=================================");
        System.out.println("  启动成功！");
        System.out.println("=================================");
    }
}
