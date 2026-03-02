package com.tsinghua.util;

import lombok.extern.slf4j.Slf4j;

import java.io.*;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.TimeUnit;

/**
 * Thrift代码生成工具类
 * 提供基于Thrift IDL文件生成多语言代码的工具方法
 */
@Slf4j
public class ThriftCodeGenerator {

    private static final int DEFAULT_TIMEOUT_SECONDS = 60;

    /**
     * 执行Thrift代码生成命令
     * @param generator 生成器类型 (java, go, py, etc.)
     * @param thriftFile Thrift IDL文件路径
     * @param outputDir 输出目录
     * @return 执行结果
     */
    public static GenerationResult generateCode(String generator, String thriftFile, String outputDir) {
        List<String> command = buildThriftCommand(generator, thriftFile, outputDir);
        return executeCommand(command, outputDir);
    }

    /**
     * 构建Thrift命令
     * @param generator 生成器类型
     * @param thriftFile Thrift文件路径
     * @param outputDir 输出目录
     * @return 命令列表
     */
    private static List<String> buildThriftCommand(String generator, String thriftFile, String outputDir) {
        List<String> command = new ArrayList<>();
        command.add("thrift");
        command.add("--gen");
        command.add(generator);
        command.add("-out");
        command.add(outputDir);
        command.add(thriftFile);
        return command;
    }

    /**
     * 执行命令
     * @param command 命令列表
     * @param workingDir 工作目录
     * @return 执行结果
     */
    private static GenerationResult executeCommand(List<String> command, String workingDir) {
        GenerationResult result = new GenerationResult();
        
        try {
            // 确保输出目录存在
            createDirectoryIfNotExists(workingDir);
            
            log.info("执行命令: {}", String.join(" ", command));
            
            ProcessBuilder pb = new ProcessBuilder(command);
            pb.directory(new File(workingDir));
            pb.redirectErrorStream(true);
            
            Process process = pb.start();
            
            // 读取输出
            StringBuilder output = new StringBuilder();
            try (BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    output.append(line).append("\n");
                    log.info("Thrift输出: {}", line);
                }
            }
            
            // 等待进程完成
            boolean finished = process.waitFor(DEFAULT_TIMEOUT_SECONDS, TimeUnit.SECONDS);
            
            if (!finished) {
                process.destroyForcibly();
                result.setSuccess(false);
                result.setMessage("命令执行超时");
                result.setOutput(output.toString());
                return result;
            }
            
            int exitCode = process.exitValue();
            result.setOutput(output.toString());
            
            if (exitCode == 0) {
                result.setSuccess(true);
                result.setMessage("代码生成成功");
                log.info("Thrift代码生成成功");
            } else {
                result.setSuccess(false);
                result.setMessage("代码生成失败，退出码: " + exitCode);
                log.error("Thrift代码生成失败，退出码: {}", exitCode);
            }
            
        } catch (Exception e) {
            result.setSuccess(false);
            result.setMessage("执行命令时发生异常: " + e.getMessage());
            log.error("执行Thrift命令时发生异常", e);
        }
        
        return result;
    }

    /**
     * 创建目录（如果不存在）
     * @param dirPath 目录路径
     * @throws IOException IO异常
     */
    private static void createDirectoryIfNotExists(String dirPath) throws IOException {
        Path path = Paths.get(dirPath);
        if (!Files.exists(path)) {
            Files.createDirectories(path);
            log.info("创建目录: {}", dirPath);
        }
    }

    /**
     * 检查Thrift编译器是否可用
     * @return 检查结果
     */
    public static boolean isThriftAvailable() {
        try {
            ProcessBuilder pb = new ProcessBuilder("thrift", "--version");
            Process process = pb.start();
            boolean finished = process.waitFor(10, TimeUnit.SECONDS);
            
            if (finished && process.exitValue() == 0) {
                log.info("Thrift编译器可用");
                return true;
            } else {
                log.warn("Thrift编译器不可用或版本检查失败");
                return false;
            }
        } catch (Exception e) {
            log.error("检查Thrift编译器时发生异常", e);
            return false;
        }
    }

    /**
     * 获取Thrift版本信息
     * @return 版本信息
     */
    public static String getThriftVersion() {
        try {
            ProcessBuilder pb = new ProcessBuilder("thrift", "--version");
            Process process = pb.start();
            
            StringBuilder output = new StringBuilder();
            try (BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    output.append(line);
                }
            }
            
            if (process.waitFor(10, TimeUnit.SECONDS) && process.exitValue() == 0) {
                return output.toString().trim();
            }
        } catch (Exception e) {
            log.error("获取Thrift版本信息时发生异常", e);
        }
        return "Unknown";
    }

    /**
     * 验证Thrift文件语法
     * @param thriftFile Thrift文件路径
     * @return 验证结果
     */
    public static ValidationResult validateThriftFile(String thriftFile) {
        ValidationResult result = new ValidationResult();
        
        try {
            if (!Files.exists(Paths.get(thriftFile))) {
                result.setValid(false);
                result.setMessage("Thrift文件不存在: " + thriftFile);
                return result;
            }
            
            // 使用thrift --gen dummy来验证语法
            List<String> command = new ArrayList<>();
            command.add("thrift");
            command.add("--gen");
            command.add("dummy");
            command.add(thriftFile);
            ProcessBuilder pb = new ProcessBuilder(command);
            Process process = pb.start();
            
            StringBuilder output = new StringBuilder();
            try (BufferedReader reader = new BufferedReader(new InputStreamReader(process.getErrorStream()))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    output.append(line).append("\n");
                }
            }
            
            boolean finished = process.waitFor(30, TimeUnit.SECONDS);
            
            if (!finished) {
                process.destroyForcibly();
                result.setValid(false);
                result.setMessage("验证超时");
                return result;
            }
            
            int exitCode = process.exitValue();
            if (exitCode == 0) {
                result.setValid(true);
                result.setMessage("Thrift文件语法正确");
            } else {
                result.setValid(false);
                result.setMessage("Thrift文件语法错误: " + output.toString());
            }
            
        } catch (Exception e) {
            result.setValid(false);
            result.setMessage("验证Thrift文件时发生异常: " + e.getMessage());
        }
        
        return result;
    }

    /**
     * 代码生成结果
     */
    public static class GenerationResult {
        private boolean success;
        private String message;
        private String output;
        
        public GenerationResult() {}
        
        public GenerationResult(boolean success, String message, String output) {
            this.success = success;
            this.message = message;
            this.output = output;
        }
        
        // Getters and Setters
        public boolean isSuccess() { return success; }
        public void setSuccess(boolean success) { this.success = success; }
        
        public String getMessage() { return message; }
        public void setMessage(String message) { this.message = message; }
        
        public String getOutput() { return output; }
        public void setOutput(String output) { this.output = output; }
    }

    /**
     * 验证结果
     */
    public static class ValidationResult {
        private boolean valid;
        private String message;
        
        public ValidationResult() {}
        
        public ValidationResult(boolean valid, String message) {
            this.valid = valid;
            this.message = message;
        }
        
        // Getters and Setters
        public boolean isValid() { return valid; }
        public void setValid(boolean valid) { this.valid = valid; }
        
        public String getMessage() { return message; }
        public void setMessage(String message) { this.message = message; }
    }
}
