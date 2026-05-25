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
     * 发送结果到API（JSON格式）
     */
    public boolean sendResult(String apiConfig, Object result) {
        try {
            Map<String, Object> config = objectMapper.readValue(apiConfig, Map.class);
            String url = (String) config.get("url");
            String method = (String) config.getOrDefault("method", "POST");

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

            // 发送请求
            log.info("发送结果到API: {} (方法: {}) 数据：{}", url, method, result);
            ResponseEntity<String> response;

            if ("GET".equalsIgnoreCase(method)) {
                // GET请求，结果作为查询参数
                String jsonResult = objectMapper.writeValueAsString(result);
                String urlWithParams = url + (url.contains("?") ? "&" : "?") + "data=" + java.net.URLEncoder.encode(jsonResult, "UTF-8");
                HttpEntity<Void> requestEntity = new HttpEntity<>(headers);
                response = restTemplate.exchange(urlWithParams, HttpMethod.GET, requestEntity, String.class);
            } else {
                // POST请求，结果作为请求体
                HttpEntity<Object> requestEntity = new HttpEntity<>(result, headers);
                response = restTemplate.postForEntity(url, requestEntity, String.class);
            }

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
