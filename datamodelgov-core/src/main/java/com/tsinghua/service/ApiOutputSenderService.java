package com.tsinghua.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.tsinghua.model.Result;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.*;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import java.util.HashMap;
import java.util.Map;

/**
 * API输出发送服务
 * 负责将仿真结果发送到指定API接口
 */
@Service
public class ApiOutputSenderService {

    @Autowired
    private RestTemplate restTemplate;

    private final ObjectMapper objectMapper = new ObjectMapper();

    /**
     * 发送仿真结果到指定API
     */
    public Result<Void> sendOutput(String apiUrl, Map<String, Object> outputData, Map<String, String> headers) {
        try {
            // 构建请求头
            HttpHeaders httpHeaders = new HttpHeaders();
            httpHeaders.setContentType(MediaType.APPLICATION_JSON);
            
            if (headers != null) {
                for (Map.Entry<String, String> entry : headers.entrySet()) {
                    httpHeaders.add(entry.getKey(), entry.getValue());
                }
            }

            // 构建请求体
            Map<String, Object> requestBody = new HashMap<>();
            requestBody.put("timestamp", System.currentTimeMillis());
            requestBody.put("data", outputData);

            // 发送请求
            HttpEntity<Map<String, Object>> requestEntity = new HttpEntity<>(requestBody, httpHeaders);
            
            ResponseEntity<String> response = restTemplate.exchange(
                apiUrl,
                HttpMethod.POST,
                requestEntity,
                String.class
            );

            if (response.getStatusCode().is2xxSuccessful()) {
                return Result.success(null);
            } else {
                return Result.error("发送失败: " + response.getStatusCode());
            }
        } catch (Exception e) {
            return Result.error("发送失败: " + e.getMessage());
        }
    }

    /**
     * 解析API配置
     */
    public Map<String, Object> parseApiConfig(String apiConfigJson) {
        try {
            @SuppressWarnings("unchecked")
            Map<String, Object> config = objectMapper.readValue(apiConfigJson, Map.class);
            return config;
        } catch (Exception e) {
            System.err.println("解析API配置失败: " + e.getMessage());
            return new HashMap<>();
        }
    }

    /**
     * 从配置中提取API URL
     */
    public String extractApiUrl(Map<String, Object> apiConfig) {
        Object url = apiConfig.get("url");
        return url != null ? url.toString() : null;
    }

    /**
     * 从配置中提取请求头
     */
    @SuppressWarnings("unchecked")
    public Map<String, String> extractHeaders(Map<String, Object> apiConfig) {
        Object headers = apiConfig.get("headers");
        if (headers instanceof Map) {
            return (Map<String, String>) headers;
        }
        return new HashMap<>();
    }
}
