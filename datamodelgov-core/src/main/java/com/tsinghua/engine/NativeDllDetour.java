package com.tsinghua.engine;

import com.tsinghua.matlab.MatlabNativeLibrary;
import lombok.extern.slf4j.Slf4j;

import java.io.File;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

/**
 * 出错绕路:GTESS.dll / thunk 桥接生成失败时,在 Java 侧用绝对路径预加载原生 DLL。
 *
 * <p>生产机(保密机)不能装 VC++/UCRT 运行库,也不能改 MATLAB 源码。MATLAB R2019b 的
 * {@code loadlibrary} 受 SetDefaultDllDirectories 限制,按名字搜不到 DLL 依赖;
 * 用 {@link System#load(String)} 绝对路径把依赖先加载进进程地址空间后,
 * MATLAB 的 {@code loadlibrary('GTESS.dll')} 会直接命中已加载模块,不再触发搜索/thunk 生成。
 *
 * <p>只在失败处理里调用一次(正常路径优先),不改任何 MATLAB 源码。
 */
@Slf4j
public final class NativeDllDetour {

    private NativeDllDetour() {}

    /** GTESS.dll 本体候选相对位置(工作目录/程序目录)。 */
    private static final String[] GTESS_REL = {
            "GTESS.dll",
            "MiddleData/control_model_runtime/mode1/GTESS.dll",
            "C_runtime/x64/Release/GTESS.dll"
    };

    /** 依赖运行库候选(MATLAB 自带,优先;其次系统目录)。顺序:CRT 基础库在前。 */
    private static final String[] RUNTIME_NAMES = {
            "vcruntime140.dll", "msvcp140.dll",
            "concrt140.dll", "vccorlib140.dll"
    };

    /**
     * 预加载 GTESS.dll 及其依赖。失败只告警不抛出(让原错误照常写回)。
     *
     * @param workDirs 任务工作目录/适配器目录/程序副本目录(可能含 GTESS.dll)
     * @return 是否成功把 GTESS.dll 本体加载进进程
     */
    public static boolean preload(File... workDirs) {
        Set<String> loaded = new LinkedHashSet<>();
        boolean gtessLoaded = false;

        // 1) 先加载 MATLAB 自带的 VC++ 运行库(绝对路径,不经 PATH 搜索)
        String home = null;
        try {
            home = MatlabNativeLibrary.getMatlabHome();
        } catch (Throwable t) {
            log.warn("绕路预加载DLL:获取 MATLAB 安装目录失败 ({})", t.toString());
        }
        if (home != null && !home.trim().isEmpty()) {
            File bin = new File(home.replace('\\', '/'), "bin/win64");
            for (String name : RUNTIME_NAMES) {
                File f = new File(bin, name);
                if (!f.isFile()) continue;
                if (loadAbs(f, loaded)) {
                    log.info("绕路预加载DLL:运行库 {} 已加载", f.getAbsolutePath());
                }
            }
        }

        // 2) 加载 GTESS.dll 本体(第一个找到的即可)
        List<File> candidates = new ArrayList<>();
        if (workDirs != null) {
            for (File dir : workDirs) {
                if (dir == null) continue;
                for (String rel : GTESS_REL) {
                    candidates.add(new File(dir, rel));
                }
            }
        }
        for (File dll : candidates) {
            if (!dll.isFile()) continue;
            if (loadAbs(dll, loaded)) {
                gtessLoaded = true;
                log.warn("绕路预加载DLL:GTESS.dll 已用绝对路径加载进进程: {}", dll.getAbsolutePath());
                break;
            }
            log.warn("绕路预加载DLL:GTESS.dll 加载失败,尝试下一个候选: {} ({})",
                    dll.getAbsolutePath(), loaded.contains(dll.getAbsolutePath()) ? "已加载过" : "见日志");
        }
        return gtessLoaded;
    }

    /** 用绝对路径 System.load,失败只告警;同路径只尝试一次。 */
    private static boolean loadAbs(File file, Set<String> tried) {
        String path = file.getAbsolutePath().replace('\\', '/');
        if (!tried.add(path)) return false;
        try {
            System.load(path);
            return true;
        } catch (Throwable t) {
            log.warn("绕路预加载DLL失败: {} ({})", path, t.toString());
            return false;
        }
    }

    /** 是否为 GTESS/thunk/loadlibrary 类失败(失败处理用,宽匹配但限定锚点)。 */
    public static boolean isDllThunkFailure(String msg) {
        if (msg == null || msg.isEmpty()) return false;
        String s = msg.replace('\r', ' ').replace('\n', ' ');
        String low = s.toLowerCase();
        return low.contains("thunk") || low.contains("loadlibrary") || low.contains("loadlibrary")
                || low.contains("gte") || s.contains("生成GTESS") || s.contains("找不到指定的模块")
                || (low.contains("dll") && (low.contains("加载") || low.contains("failed")));
    }
}
