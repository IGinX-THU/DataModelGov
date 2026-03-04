package com.tsinghua;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.autoconfigure.domain.EntityScan;

/**
 * 数据治理平台启动类
 */
@SpringBootApplication
@EntityScan(basePackages = {"com.tsinghua"})
public class DataModelGovApplication {

    public static void main(String[] args) {
        SpringApplication.run(DataModelGovApplication.class, args);
        System.out.println("=================================");
        System.out.println("  数据治理平台启动成功！");
        System.out.println("  访问地址: http://localhost:8080");
        System.out.println("  登录页面: http://localhost:8080/login.html");
        System.out.println("=================================");
    }
}
