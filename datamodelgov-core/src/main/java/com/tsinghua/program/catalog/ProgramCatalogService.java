package com.tsinghua.program.catalog;

import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Service;

import javax.annotation.PostConstruct;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

/**
 * 公开功能注册表:加载 20 项公开入口(F-01~F-12)的结构化定义,
 * 作为界面接入层与 MATLAB 程序之间的稳定标识层。
 * 入口换版只改 catalog 资源文件,不改界面与调度代码。
 */
@Slf4j
@Service
public class ProgramCatalogService {

    private volatile List<ProgramFeature> features;
    private volatile List<BusinessGroup> groups;

    @PostConstruct
    void load() {
        try {
            ObjectMapper mapper = new ObjectMapper();
            Map<String, Object> root = mapper.readValue(
                    new ClassPathResource("programs/catalog/program-catalog.json").getInputStream(), Map.class);
            features = mapper.convertValue(root.get("features"),
                    mapper.getTypeFactory().constructCollectionType(List.class, ProgramFeature.class));
            groups = mapper.convertValue(root.get("groups"),
                    mapper.getTypeFactory().constructCollectionType(List.class, BusinessGroup.class));
            log.info("公开功能注册表加载完成:{} 项功能,{} 个业务组", features.size(), groups.size());
        } catch (Exception e) {
            log.error("公开功能注册表加载失败", e);
            features = Collections.emptyList();
            groups = Collections.emptyList();
        }
    }

    public List<ProgramFeature> list(String workbench, String module) {
        return features.stream()
                .filter(f -> workbench == null || workbench.trim().isEmpty() || workbench.equals(f.getWorkbench()))
                .filter(f -> module == null || module.trim().isEmpty() || module.equals(f.getModule()))
                .collect(Collectors.toList());
    }

    public ProgramFeature get(String id) {
        return features.stream()
                .filter(f -> f.getId().equalsIgnoreCase(id))
                .findFirst().orElse(null);
    }

    public List<BusinessGroup> listGroups() {
        return groups;
    }
}
