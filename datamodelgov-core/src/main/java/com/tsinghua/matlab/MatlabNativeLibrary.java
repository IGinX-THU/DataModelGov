package com.tsinghua.matlab;

import com.sun.jna.Native;
import com.sun.jna.win32.StdCallLibrary;
import com.sun.jna.win32.W32APIOptions;
import lombok.extern.slf4j.Slf4j;

import java.awt.AWTEvent;
import java.awt.EventQueue;
import java.awt.HeadlessException;
import java.awt.Toolkit;
import java.io.File;
import java.lang.reflect.Field;
import java.util.Arrays;
import java.util.Comparator;

/**
 * MATLAB 原生库（Engine API 依赖的 nativemvm.dll 及其依赖）加载准备。
 *
 * MatlabEngine 通过 System.loadLibrary("nativemvm") 启动 MATLAB，这要求：
 * 1) java.library.path 中有 <MATLAB>/bin/win64——否则找不到 nativemvm.dll 本身；
 * 2) 进程 PATH 中有同一目录——否则 Windows 加载器找不到它依赖的一堆 MATLAB DLL
 *    （表现为 UnsatisfiedlinkError: Can't find dependent libraries）。
 *
 * 以往只能在启动脚本里预先设置 PATH。这里改为在进程内完成：用 Win32
 * SetEnvironmentVariable/SetDllDirectory 修改本进程环境，再反射重置 ClassLoader 的
 * 库搜索路径缓存，使服务无需依赖外部环境变量即可拉起 MATLAB 引擎。
 *
 * 注意：不能在这里自行 System.loadLibrary("nativemvm") 做探路——加载 nativemvm.dll
 * 会触发 MatlabExecutor.<clinit> → MvmImpl.loadLibrary，后者在依赖库缺失时会通过
 * SwingUtilities.invokeLater 弹 Swing 对话框，在 headless 的 Spring Boot 进程里
 * 抛 HeadlessException 刷屏。因此这里只做路径注入 + 文件存在性检查，真正的加载
 * 交给 MatlabEngine.startMatlab()，并通过 installHeadlessSuppressor() 静默吞掉
 * AWT 线程上的 HeadlessException。
 */
@Slf4j
public final class MatlabNativeLibrary {

    private interface Kernel32 extends StdCallLibrary {
        Kernel32 INSTANCE = Native.load("kernel32", Kernel32.class, W32APIOptions.DEFAULT_OPTIONS);

        boolean SetEnvironmentVariable(String name, String value);

        boolean SetDllDirectory(String path);
    }

    private static final String LIB_NAME = "nativemvm";
    private static Boolean ready;
    private static String resolvedHome;
    private static volatile boolean headlessSuppressorInstalled;

    private MatlabNativeLibrary() {
    }

    /**
     * 准备原生库环境（幂等，只在首次调用时真正执行）。
     * 只做路径注入 + 文件存在性检查，不实际加载 nativemvm.dll。
     *
     * @param configuredHome 配置的 MATLAB 安装根目录，为空则自动探测
     * @return true 表示 nativemvm.dll 文件存在且路径已注入，可以尝试 startMatlab
     */
    public static synchronized boolean prepare(String configuredHome) {
        if (ready != null) return ready;
        ready = doPrepare(configuredHome);
        return ready;
    }

    /** 实际生效的 MATLAB 安装根目录（prepare 之后可用） */
    public static String getMatlabHome() {
        return resolvedHome;
    }

    /**
     * 在 AWT 事件队列上安装 HeadlessException 抑制器。
     *
     * MATLAB 的 MvmImpl.loadLibrary 在某些原生库加载失败时会 SwingUtilities.invokeLater
     * 弹一个错误对话框。在 headless 的 Spring Boot 进程里，JDialog 构造会抛
     * HeadlessException，被 AWT 线程默认未捕获异常处理器打印到 stderr，造成刷屏。
     * 这里 push 一个自定义 EventQueue，在 dispatchEvent 中静默吞掉 HeadlessException。
     *
     * 必须在第一次触碰 MatlabEngine / nativemvm 之前调用。
     */
    public static void installHeadlessSuppressor() {
        if (headlessSuppressorInstalled) return;
        synchronized (MatlabNativeLibrary.class) {
            if (headlessSuppressorInstalled) return;
            try {
                // 用 invokeAndWait 确保 push 在 startMatlab 调用前完成，
                // 否则 MvmImpl 的 invokeLater 可能在抑制器安装前就派发
                EventQueue.invokeAndWait(() -> {
                    try {
                        EventQueue queue = Toolkit.getDefaultToolkit().getSystemEventQueue();
                        queue.push(new EventQueue() {
                            @Override
                            protected void dispatchEvent(AWTEvent event) {
                                try {
                                    super.dispatchEvent(event);
                                } catch (HeadlessException e) {
                                    // MATLAB MvmImpl 弹对话框失败，headless 下属预期行为，静默吞掉
                                }
                            }
                        });
                    } catch (Throwable t) {
                        log.debug("安装 AWT HeadlessException 抑制器失败（可忽略）: {}", t.toString());
                    }
                });
                headlessSuppressorInstalled = true;
                log.debug("已安装 AWT HeadlessException 抑制器");
            } catch (Throwable t) {
                log.debug("安装 AWT HeadlessException 抑制器失败（可忽略）: {}", t.toString());
            }
        }
    }

    private static boolean doPrepare(String configuredHome) {
        if (!System.getProperty("os.name", "").toLowerCase().contains("win")) {
            // 非 Windows 无法在进程内改动态库搜索路径，依赖外部 LD_LIBRARY_PATH
            return nativeFileExists(null);
        }
        File home = resolveHome(configuredHome);
        if (home == null) {
            log.warn("未找到 MATLAB 安装目录，无法使用 Engine API（可通过 matlab.engine.home 配置指定）");
            return false;
        }
        resolvedHome = home.getAbsolutePath();
        File binDir = new File(home, "bin/win64");
        if (!new File(binDir, LIB_NAME + ".dll").isFile()) {
            log.warn("MATLAB 原生库缺失: {}", new File(binDir, LIB_NAME + ".dll").getAbsolutePath());
            return false;
        }
        try {
            String bin = binDir.getAbsolutePath();
            // 1) 让 Windows 加载器能解析 nativemvm.dll 的依赖库
            Kernel32.INSTANCE.SetDllDirectory(bin);
            String path = System.getenv("PATH");
            if (path == null || !path.toLowerCase().contains(bin.toLowerCase())) {
                Kernel32.INSTANCE.SetEnvironmentVariable("PATH", bin + File.pathSeparator + (path == null ? "" : path));
            }
            // 2) 让 System.loadLibrary 能定位 nativemvm.dll
            appendLibraryPath(bin);
        } catch (Throwable t) {
            log.warn("注入 MATLAB 原生库路径失败: {}", t.toString());
        }
        // 不自行 loadLibrary——那会触发 MatlabExecutor.<clinit> → MvmImpl 弹 Swing 对话框。
        // 只检查文件存在性，真正的加载交给 MatlabEngine.startMatlab()
        log.info("MATLAB 原生库路径已就绪: {}", binDir.getAbsolutePath());
        return true;
    }

    /** 非 Windows 下检查 LD_LIBRARY_PATH 中是否有 nativemvm（仅文件存在性） */
    private static boolean nativeFileExists(String dir) {
        if (dir != null) {
            return new File(dir, LIB_NAME + ".dll").isFile()
                    || new File(dir, "lib" + LIB_NAME + ".so").isFile();
        }
        // 无法确定目录，返回 true 让 startMatlab 自行尝试
        return true;
    }

    /** 追加 java.library.path 并清空 ClassLoader 的路径缓存（JDK 8 生效） */
    private static void appendLibraryPath(String dir) throws Exception {
        String current = System.getProperty("java.library.path", "");
        if (current.toLowerCase().contains(dir.toLowerCase())) return;
        System.setProperty("java.library.path", dir + File.pathSeparator + current);
        Field sysPaths = ClassLoader.class.getDeclaredField("sys_paths");
        sysPaths.setAccessible(true);
        sysPaths.set(null, null);
    }

    /** 依次尝试：配置项 → MATLAB_ROOT 环境变量 → PATH 中的 matlab.exe → 默认安装目录下最新版本 */
    private static File resolveHome(String configuredHome) {
        File home = validHome(configuredHome);
        if (home != null) return home;
        home = validHome(System.getenv("MATLAB_ROOT"));
        if (home != null) return home;

        String path = System.getenv("PATH");
        if (path != null) {
            for (String entry : path.split(File.pathSeparator)) {
                if (entry.trim().isEmpty()) continue;
                if (new File(entry, "matlab.exe").isFile()) {
                    // <MATLAB>/bin 或 <MATLAB>/bin/win64
                    File dir = new File(entry).getParentFile();
                    if (dir != null && "bin".equalsIgnoreCase(dir.getName())) dir = dir.getParentFile();
                    File candidate = validHome(dir == null ? null : dir.getAbsolutePath());
                    if (candidate != null) return candidate;
                }
            }
        }

        File base = new File("C:/Program Files/MATLAB");
        File[] versions = base.listFiles(File::isDirectory);
        if (versions != null && versions.length > 0) {
            return Arrays.stream(versions)
                    .filter(f -> new File(f, "bin/win64/" + LIB_NAME + ".dll").isFile())
                    .max(Comparator.comparing(File::getName))
                    .orElse(null);
        }
        return null;
    }

    private static File validHome(String path) {
        if (path == null || path.trim().isEmpty()) return null;
        File dir = new File(path.trim());
        return new File(dir, "bin/win64").isDirectory() ? dir : null;
    }
}
