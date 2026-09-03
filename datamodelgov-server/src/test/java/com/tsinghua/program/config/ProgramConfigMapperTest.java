package com.tsinghua.program.config;

import org.junit.jupiter.api.Test;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

class ProgramConfigMapperTest {

    @Test
    void existingAfoConfigDefaultsToSimulinkRealtime() throws Exception {
        ProgramConfig config = load("programs/AFO_V_1Disp/config.json");
        assertNotNull(config);
        assertTrue(config.getRuntime().getExecutionType() == null
                || config.getRuntime().getExecutionType().isEmpty());
        assertEquals(0, ProgramConfigMapper.validate(config, true).size());
    }

    @Test
    void steadyWorkflowPresetPassesStrictValidation() throws Exception {
        ProgramConfig config = load("programs/SteadyModelAdaptFromTestV1/config.json");
        assertNotNull(config);
        assertEquals("matlabWorkflow", config.getRuntime().getExecutionType());
        assertEquals(0, ProgramConfigMapper.validate(config, true).size());
    }

    @Test
    void workflowRejectsUnsafeEntryPoint() throws Exception {
        ProgramConfig config = load("programs/SteadyModelAdaptFromTestV1/config.json");
        config.getWorkflow().getActions().get(0).setEntryPoint("system('bad')");
        List<String> errors = ProgramConfigMapper.validate(config, true);
        assertFalse(errors.isEmpty());
        assertTrue(errors.stream().anyMatch(error -> error.contains("entryPoint")));
    }

    private ProgramConfig load(String resource) throws Exception {
        try (InputStream input = getClass().getClassLoader().getResourceAsStream(resource)) {
            assertNotNull(input, resource);
            ByteArrayOutputStream output = new ByteArrayOutputStream();
            byte[] buffer = new byte[4096];
            int count;
            while ((count = input.read(buffer)) != -1) output.write(buffer, 0, count);
            return ProgramConfigMapper.parse(new String(output.toByteArray(), StandardCharsets.UTF_8));
        }
    }
}
