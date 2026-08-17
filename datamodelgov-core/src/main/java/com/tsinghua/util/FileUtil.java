package com.tsinghua.util;

import lombok.extern.slf4j.Slf4j;

import java.io.BufferedReader;
import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.TimeUnit;
import java.util.stream.Collectors;

/**
 * 文件系统通用工具：目录删除、文件尾读取、MD5 校验、Windows 短路径、脚本目录查找。
 */
@Slf4j
public final class FileUtil {

    private FileUtil() {
    }

    /** 递归删除目录及其内容（静默忽略单文件删除失败） */
    public static void deleteDirectory(File dir) {
        if (dir == null || !dir.exists()) return;
        File[] files = dir.listFiles();
        if (files != null) {
            for (File f : files) {
                if (f.isDirectory()) deleteDirectory(f);
                else f.delete();
            }
        }
        dir.delete();
    }

    /** 读取文件最后 n 行（不足 n 行则返回全部），文件不存在返回空串 */
    public static String readLastLines(File f, int n) {
        if (!f.exists()) return "";
        List<String> lines = new ArrayList<>();
        try (BufferedReader br = Files.newBufferedReader(f.toPath(), StandardCharsets.UTF_8)) {
            String line;
            while ((line = br.readLine()) != null) {
                lines.add(line);
                if (lines.size() > n) lines.remove(0);
            }
        } catch (IOException e) { }
        return lines.stream().collect(Collectors.joining("\n"));
    }

    /** 计算字节数组的 MD5 校验和（十六进制小写），失败返回空串 */
    public static String calculateMD5(byte[] bytes) {
        try {
            java.security.MessageDigest md = java.security.MessageDigest.getInstance("MD5");
            byte[] digest = md.digest(bytes);
            StringBuilder sb = new StringBuilder();
            for (byte b : digest) {
                sb.append(String.format("%02x", b));
            }
            return sb.toString();
        } catch (Exception e) {
            log.warn("计算 MD5 失败", e);
            return "";
        }
    }

    /**
     * 取 Windows 短路径（8.3 命名），用于把含空格/中文的路径传给 MATLAB。
     * 非 Windows 或获取失败时返回原绝对路径。
     */
    public static String getShortPath(File file) {
        if (!file.exists()) return file.getAbsolutePath();
        try {
            Process p = new ProcessBuilder("cmd", "/c", "for %I in (\""
                    + file.getAbsolutePath() + "\") do @echo %~sI").redirectErrorStream(true).start();
            java.io.ByteArrayOutputStream baos = new java.io.ByteArrayOutputStream();
            byte[] buf = new byte[1024];
            int n;
            while ((n = p.getInputStream().read(buf)) != -1) baos.write(buf, 0, n);
            p.waitFor(5, TimeUnit.SECONDS);
            String output = new String(baos.toByteArray(), StandardCharsets.UTF_8).trim();
            if (!output.isEmpty() && output.matches("^[A-Za-z]:\\\\.*")) {
                return output;
            }
        } catch (Exception e) {
            log.warn("获取短路径失败: {}", file.getAbsolutePath(), e);
        }
        return file.getAbsolutePath();
    }

    /**
     * 在 dir 下递归查找名为 scriptName（自动补 .m 后缀）的脚本文件，返回其所在目录。
     * 找不到时返回 dir 的绝对路径。
     */
    public static String findProgramDir(File dir, String scriptName) throws IOException {
        String name = scriptName.toLowerCase().endsWith(".m") ? scriptName : scriptName + ".m";
        File base = dir.getAbsoluteFile();
        try (java.util.stream.Stream<Path> paths = Files.walk(base.toPath())) {
            Path found = paths.filter(p -> p.toFile().isFile() && p.getFileName().toString().equalsIgnoreCase(name))
                    .findFirst()
                    .orElse(null);
            return found != null ? found.getParent().toString() : base.getAbsolutePath();
        }
    }
}
