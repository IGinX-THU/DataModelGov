package com.tsinghua.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.*;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import java.util.HashMap;
import java.util.Map;

/**
 * 输出API发送服务
 * 用于将仿真结果发送到指定的API接口
 */
@Slf4j
@Service
public class OutputApiSenderService {

    private final RestTemplate restTemplate = new RestTemplate();
    private final ObjectMapper objectMapper = new ObjectMapper();

    /**
     * 发送结果到API
     */
    public boolean sendResult(String apiConfig, Object result) {
        try {
            Map<String, Object> config = objectMapper.readValue(apiConfig, Map.class);
            String url = (String) config.get("url");
            
            if (url == null || url.isEmpty()) {
                log.error("API URL为空");
                return false;
            }

            // 构建请求头
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            
            if (config.containsKey("headers")) {
                Map<String, String> configHeaders = (Map<String, String>) config.get("headers");
                configHeaders.forEach(headers::add);
            }

            // 构建请求体
            Map<String, Object> requestBody = new HashMap<>();
            requestBody.put("result", result);
            requestBody.put("timestamp", System.currentTimeMillis());
            
            if (config.containsKey("additionalData")) {
                requestBody.putAll((Map<String, Object>) config.get("additionalData"));
            }

            HttpEntity<Map<String, Object>> requestEntity = new HttpEntity<>(requestBody, headers);

            // 发送请求
            log.info("发送结果到API: {}", url);
            ResponseEntity<String> response = restTemplate.postForEntity(url, requestEntity, String.class);

            if (response.getStatusCode() == HttpStatus.OK) {
                log.info("结果发送成功: {}", response.getBody());
                return true;
            } else {
                log.error("结果发送失败: {}", response.getStatusCode());
                return false;
            }

        } catch (Exception e) {
            log.error("发送结果到API失败", e);
            return false;
        }
    }
}
