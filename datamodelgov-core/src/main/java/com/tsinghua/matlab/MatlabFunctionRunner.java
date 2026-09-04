package com.tsinghua.matlab;

import com.mathworks.engine.MatlabEngine;
import lombok.extern.slf4j.Slf4j;

import java.io.BufferedWriter;
import java.io.Closeable;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.OutputStreamWriter;
import java.io.PrintWriter;
import java.io.Writer;
import java.util.Objects;
import java.util.concurrent.CancellationException;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.regex.Pattern;

import com.sun.jna.Native;
import com.sun.jna.Platform;
import com.sun.jna.win32.StdCallLibrary;
import com.sun.jna.win32.W32APIOptions;

import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;

/**
 * Standalone runner for a MATLAB function whose inputs and single output cross the
 * MATLAB Engine for Java boundary without being converted to MATLAB source text.
 *
 * <p>The entry point is restricted to a plain MATLAB identifier. Arguments are
 * forwarded, in order, to {@link MatlabEngine#fevalAsync(String, Writer, Writer, Object...)}.
 * The returned value is deliberately left as the Engine API's {@link Object}; this
 * class does not attempt to parse MATLAB structs or tables. Deployments needing
 * those types should expose a MATLAB adapter (for example {@code dmg_run_workflow})
 * that returns an Engine-supported scalar, String, or primitive array, and pass that
 * adapter's name as {@code entryPoint}.</p>
 *
 * <p>Cancellation is cooperative. A request is observed before and after every
 * MATLAB call. Once a native Engine call is in progress it is allowed to finish;
 * its Future is never cancelled and the borrowed engine is not returned early.</p>
 */
@Slf4j
public final class MatlabFunctionRunner {

    /** Optional bridge to a task's progress and cancellation mechanism. */
    public interface ProgressCancellationSink {
        /** Receives lifecycle messages and complete lines emitted by MATLAB. */
        void onProgress(String message);

        /** Return true when the surrounding task has requested cancellation. */
        boolean isCancellationRequested();
    }

    private static final Pattern SAFE_ENTRY_POINT =
            Pattern.compile("^[A-Za-z][A-Za-z0-9_]*$");
    private static final long ENGINE_BORROW_TIMEOUT_SECONDS = 300L;
    private static final long FUTURE_POLL_MILLIS = 250L;

    /** Win32 Kernel32 for DLL search path manipulation (Windows only). */
    private interface Kernel32 extends StdCallLibrary {
        Kernel32 INSTANCE = Native.load("kernel32", Kernel32.class, W32APIOptions.DEFAULT_OPTIONS);
        boolean SetDllDirectory(String path);
        boolean SetEnvironmentVariable(String name, String value);
    }

    private final File workspaceDirectory;
    private final String entryPoint;
    private final Object[] arguments;
    private final File logFile;
    private final MatlabEnginePool enginePool;
    private final ProgressCancellationSink sink;
    private final AtomicBoolean cancellationRequested = new AtomicBoolean(false);
    private final AtomicBoolean cancellationReported = new AtomicBoolean(false);

    private volatile MatlabEngine engine;
    private volatile String actualRelease;
    private volatile PrintWriter logWriter;

    public MatlabFunctionRunner(File workspaceDirectory, String entryPoint, Object[] arguments,
                                File logFile, MatlabEnginePool enginePool) {
        this(workspaceDirectory, entryPoint, arguments, logFile, enginePool, null);
    }

    public MatlabFunctionRunner(File workspaceDirectory, String entryPoint, Object[] arguments,
                                File logFile, MatlabEnginePool enginePool,
                                ProgressCancellationSink sink) {
        this.workspaceDirectory = validateWorkspace(workspaceDirectory);
        this.entryPoint = validateEntryPoint(entryPoint);
        this.arguments = arguments == null ? new Object[0] : arguments.clone();
        this.logFile = Objects.requireNonNull(logFile, "logFile");
        this.enginePool = Objects.requireNonNull(enginePool, "enginePool");
        this.sink = sink;
    }

    /** Set the cooperative cancellation flag. This method never interrupts MATLAB. */
    public void requestCancel() {
        cancellationRequested.set(true);
        reportCancellationOnce();
    }

    public boolean isCancellationRequested() {
        return cancellationRequested.get() || (sink != null && safeSinkCancellationCheck());
    }

    /** MATLAB release reported by {@code version('-release')} during the latest call. */
    public String getActualRelease() {
        return actualRelease;
    }

    /**
     * Execute the configured function and return the unmodified Engine API value.
     * The function is invoked with one output. Functions that naturally return a
     * struct/table should use a MATLAB adapter that converts it to a supported type.
     */
    public synchronized Object run() throws Exception {
        ensureNotRunning();
        openLog();
        MatlabEngine borrowed = null;
        try {
            checkCancelled("before borrowing a MATLAB engine");
            emit("Waiting for a MATLAB engine");
            borrowed = enginePool.borrow(ENGINE_BORROW_TIMEOUT_SECONDS);
            engine = borrowed;
            emit("MATLAB engine borrowed");

            checkCancelled("before workspace setup");
            actualRelease = queryRelease(borrowed);
            emit("MATLAB release: " + actualRelease);

            // 设置 MATLAB 字符集为 UTF-8（.m 文件为 UTF-8 编码，需 UTF-8 才能正确读取中文）
            // 解压时 ArchiveUtil 已将中文目录名替换为 u/u_2 等，路径不含中文，可以安全启用。
            try {
                invokeNoOutput(borrowed, "eval", "feature('DefaultCharacterSet', 'UTF-8')");
            } catch (Exception e) {
                log.debug("Failed to set MATLAB charset to UTF-8", e);
            }

            // 将工作目录加入 DLL 搜索路径和 PATH，确保 MATLAB loadlibrary 能找到用户 DLL 及其依赖
            injectDllSearchPath(workspaceDirectory);

            invokeNoOutput(borrowed, "cd", workspaceDirectory.getAbsolutePath());
            checkCancelled("after changing the MATLAB directory");
            // 将工作目录置于 MATLAB 搜索路径最前面，确保 mfilename('fullpath') 定位到
            // 工作区副本而非程序包原始解压目录；rehash 刷新函数调度缓存。
            invokeNoOutput(borrowed, "eval", "addpath('" + workspaceDirectory.getAbsolutePath().replace("'", "''") + "', '-begin')");
            checkCancelled("after addpath");
            invokeNoOutput(borrowed, "eval", "rehash");
            checkCancelled("after rehash");
            invokeNoOutput(borrowed, "eval", "clear functions");
            checkCancelled("after clear functions");

            emit("Invoking MATLAB function: " + entryPoint);
            Object result = await(borrowed.fevalAsync(entryPoint, matlabWriter("stdout"),
                    matlabWriter("stderr"), arguments));
            checkCancelled("after invoking " + entryPoint);
            emit("MATLAB function completed: " + entryPoint + " (result type: "
                    + (result == null ? "null" : result.getClass().getName()) + ")");
            return result;
        } finally {
            engine = null;
            if (borrowed != null) {
                // 归还引擎前切到 MATLAB tempdir，避免引擎 cwd 残留在已被清理的 subst 盘符上
                // （上一个任务 cleanupSubstDrive 后 Z: 消失，下一个任务借到引擎会报 "无法访问文件"）
                try {
                    invokeNoOutput(borrowed, "eval", "cd(tempdir)");
                } catch (Exception ignored) {}
                enginePool.release(borrowed);
                emit("MATLAB engine returned to pool");
            }
            closeLog();
        }
    }

    /**
     * Borrow an engine solely to query its actual release with
     * {@code version('-release')}. The engine is always returned to the pool.
     */
    public synchronized String queryActualRelease() throws Exception {
        ensureNotRunning();
        openLog();
        MatlabEngine borrowed = null;
        try {
            checkCancelled("before querying the MATLAB release");
            borrowed = enginePool.borrow(ENGINE_BORROW_TIMEOUT_SECONDS);
            engine = borrowed;
            actualRelease = queryRelease(borrowed);
            emit("MATLAB release: " + actualRelease);
            checkCancelled("after querying the MATLAB release");
            return actualRelease;
        } finally {
            engine = null;
            if (borrowed != null) {
                enginePool.release(borrowed);
                emit("MATLAB engine returned to pool");
            }
            closeLog();
        }
    }

    private String queryRelease(MatlabEngine matlabEngine) throws Exception {
        checkCancelled("before querying the MATLAB release");
        Object release = await(matlabEngine.fevalAsync("version", matlabWriter("stdout"),
                matlabWriter("stderr"), "-release"));
        checkCancelled("after querying the MATLAB release");
        return release == null ? "unknown" : String.valueOf(release);
    }

    private void invokeNoOutput(MatlabEngine matlabEngine, String function, Object... args)
            throws Exception {
        checkCancelled("before invoking MATLAB setup function " + function);
        Future<Void> future = matlabEngine.fevalAsync(0, function, matlabWriter("stdout"),
                matlabWriter("stderr"), args);
        await(future);
        checkCancelled("after invoking MATLAB setup function " + function);
    }

    /**
     * Wait without cancelling the native call. Interrupts become cooperative cancel
     * requests, but the engine is retained until MATLAB has actually completed.
     */
    private <T> T await(Future<T> future) throws Exception {
        boolean interrupted = false;
        for (;;) {
            try {
                T value = future.get(FUTURE_POLL_MILLIS, TimeUnit.MILLISECONDS);
                if (interrupted) {
                    Thread.currentThread().interrupt();
                    throw new InterruptedException("Interrupted while waiting for MATLAB; native call completed before engine release");
                }
                return value;
            } catch (TimeoutException ignored) {
                if (isCancellationRequested()) {
                    reportCancellationOnce();
                }
            } catch (InterruptedException e) {
                interrupted = true;
                cancellationRequested.set(true);
                reportCancellationOnce();
                // Do not cancel the Future: wait until the native call has returned.
            } catch (ExecutionException e) {
                if (interrupted) {
                    Thread.currentThread().interrupt();
                }
                Throwable cause = e.getCause() == null ? e : e.getCause();
                if (cause instanceof Exception) {
                    throw (Exception) cause;
                }
                throw new Exception("MATLAB call failed", cause);
            }
        }
    }

    private void checkCancelled(String location) {
        if (isCancellationRequested()) {
            reportCancellationOnce();
            throw new CancellationException("MATLAB function run cancelled " + location);
        }
    }

    private boolean safeSinkCancellationCheck() {
        try {
            return sink.isCancellationRequested();
        } catch (RuntimeException e) {
            log.warn("MATLAB progress sink cancellation check failed: {}", e.toString());
            return false;
        }
    }

    private void reportCancellationOnce() {
        if (cancellationReported.compareAndSet(false, true)) {
            emit("Cancellation requested; any in-progress MATLAB native call will be allowed to finish");
        }
    }

    private void ensureNotRunning() {
        if (engine != null) {
            throw new IllegalStateException("MatlabFunctionRunner is already running");
        }
    }

    /**
     * On Windows, MATLAB R2019b internally calls SetDefaultDllDirectories which restricts
     * DLL search. SetDefaultDllDirectories(0) cannot reset it (returns false, error 87).
     * AddDllDirectory doesn't help because MATLAB's loadlibrary uses LoadLibrary (not
     * LoadLibraryEx with LOAD_LIBRARY_SEARCH_USER_DIRS).
     *
     * The actual fix is in dmg_run_workflow.m: it pre-loads GTESS.dll via Java System.load()
     * with an absolute path, which puts the DLL in the process address space. Subsequent
     * LoadLibrary("GTESS.dll") calls then find the already-loaded module without searching.
     *
     * Here we just set PATH for good measure and log the situation.
     */
    private static void injectDllSearchPath(File workspaceDir) {
        if (!Platform.isWindows()) return;
        try {
            Kernel32 k32 = Kernel32.INSTANCE;
            String wsPath = workspaceDir.getAbsolutePath();
            String middleDataPath = new File(workspaceDir, "MiddleData").getAbsolutePath();
            String currentPath = System.getenv("PATH");
            if (currentPath == null || !currentPath.toLowerCase().contains(middleDataPath.toLowerCase())) {
                String newPath = middleDataPath + File.pathSeparator + wsPath + File.pathSeparator
                        + (currentPath == null ? "" : currentPath);
                k32.SetEnvironmentVariable("PATH", newPath);
            }
            log.info("DLL搜索路径: PATH已更新");
        } catch (Throwable t) {
            log.warn("注入DLL搜索路径失败", t);
        }
    }

    private void openLog() throws IOException {
        File parent = logFile.getAbsoluteFile().getParentFile();
        if (parent != null && !parent.isDirectory()) {
            throw new IOException("MATLAB log parent directory does not exist: " + parent);
        }
        logWriter = new PrintWriter(new BufferedWriter(
                new OutputStreamWriter(new FileOutputStream(logFile, true), java.nio.charset.StandardCharsets.UTF_8)), true);
    }

    private void closeLog() {
        PrintWriter writer = logWriter;
        logWriter = null;
        if (writer != null) {
            writer.close();
        }
    }

    private Writer matlabWriter(String streamName) {
        return new LineWriter(streamName);
    }

    private void emit(String message) {
        PrintWriter writer = logWriter;
        if (writer != null) {
            synchronized (writer) {
                writer.println(message);
            }
        }
        log.info("[MATLAB-FUNCTION] {}", message);
        if (sink != null) {
            try {
                sink.onProgress(message);
            } catch (RuntimeException e) {
                log.warn("MATLAB progress sink failed: {}", e.toString());
            }
        }
    }

    private static File validateWorkspace(File directory) {
        Objects.requireNonNull(directory, "workspaceDirectory");
        if (!directory.isDirectory()) {
            throw new IllegalArgumentException("MATLAB workspace/program directory does not exist: " + directory);
        }
        return directory.getAbsoluteFile();
    }

    private static String validateEntryPoint(String value) {
        if (value == null || !SAFE_ENTRY_POINT.matcher(value).matches()) {
            throw new IllegalArgumentException(
                    "MATLAB entryPoint must match ^[A-Za-z][A-Za-z0-9_]*$");
        }
        return value;
    }

    /** Writer that preserves MATLAB output in the log and reports complete lines. */
    private final class LineWriter extends Writer implements Closeable {
        private final String streamName;
        private final StringBuilder line = new StringBuilder();

        private LineWriter(String streamName) {
            this.streamName = streamName;
        }

        @Override
        public synchronized void write(char[] chars, int offset, int length) {
            for (int i = offset; i < offset + length; i++) {
                char c = chars[i];
                if (c == '\n') {
                    publishLine();
                } else if (c != '\r') {
                    line.append(c);
                }
            }
        }

        @Override
        public synchronized void flush() {
            if (line.length() > 0) {
                publishLine();
            }
            PrintWriter writer = logWriter;
            if (writer != null) {
                writer.flush();
            }
        }

        @Override
        public synchronized void close() {
            flush();
        }

        private void publishLine() {
            String text = "[" + streamName + "] " + line.toString();
            line.setLength(0);
            emit(text);
        }
    }
}
