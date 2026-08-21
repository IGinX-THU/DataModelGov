package com.tsinghua.matlab;

import com.mathworks.engine.MatlabEngine;
import lombok.extern.slf4j.Slf4j;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * MATLAB 引擎池：支持多引擎并发。
 *
 * 策略：1 个常驻引擎 + 按需创建（上限 maxEngines），超过上限的任务排队等待。
 * - 启动时异步预创建 1 个常驻引擎
 * - borrow 时优先取空闲引擎；无空闲且未达上限时新启一个；达上限时阻塞等待
 * - release 时归还到空闲队列，供其他任务复用
 *
 * 这与 MATLAB Engine 本身的特性一致：每个 MatlabEngine 是独立进程，可并发执行。
 */
@Slf4j
public class MatlabEnginePool {

    private final int maxEngines;
    private final LinkedBlockingQueue<MatlabEngine> idle = new LinkedBlockingQueue<>();
    private final Map<MatlabEngine, String> loadedModels = new ConcurrentHashMap<>();
    private final AtomicInteger totalEngines = new AtomicInteger(0);
    private final AtomicInteger waitingCount = new AtomicInteger(0);
    private final AtomicBoolean started = new AtomicBoolean(false);
    private final AtomicBoolean starting = new AtomicBoolean(false);
    private volatile boolean startFailed = false;

    /**
     * @param maxEngines 最大并发引擎数（含常驻引擎）
     */
    public MatlabEnginePool(int maxEngines) {
        this.maxEngines = Math.max(1, maxEngines);
    }

    /** 默认构造：1 个引擎（兼容旧调用） */
    public MatlabEnginePool() {
        this(1);
    }

    /**
     * 异步启动常驻 MATLAB 引擎（不阻塞调用线程）。
     * 由 ProgramService @PostConstruct 调用。
     */
    public void init() {
        startEngineAsync();
    }

    private void startEngineAsync() {
        starting.set(true);
        started.set(false);
        startFailed = false;
        Thread t = new Thread(() -> {
            try {
                log.info("[MATLAB-POOL] 正在启动常驻 MATLAB 引擎 (1/{})...", maxEngines);
                MatlabNativeLibrary.prepare(null);
                MatlabNativeLibrary.installHeadlessSuppressor();
                long t0 = System.currentTimeMillis();
                MatlabEngine eng = MatlabEngine.startMatlab();
                long elapsed = System.currentTimeMillis() - t0;
                totalEngines.incrementAndGet();
                started.set(true);
                starting.set(false);
                idle.offer(eng);
                log.info("[MATLAB-POOL] 常驻 MATLAB 引擎已就绪，耗时 {} ms", elapsed);
            } catch (Exception e) {
                startFailed = true;
                starting.set(false);
                log.error("[MATLAB-POOL] MATLAB 引擎启动失败，仿真将回退到 matlab -batch: {}", e.toString());
            }
        }, "matlab-engine-pool-init");
        t.setDaemon(true);
        t.start();
    }

    /**
     * 借出引擎，阻塞等待直到可用。
     * 优先取空闲引擎；无空闲且未达上限时新启一个；达上限时阻塞等待归还。
     *
     * @param timeoutSec 等待超时（秒）
     * @return 可用的 MatlabEngine
     */
    public MatlabEngine borrow(String preferredModel, long timeoutSec) throws Exception {
        if (preferredModel != null && !preferredModel.trim().isEmpty()) {
            int candidates = idle.size();
            for (int i = 0; i < candidates; i++) {
                MatlabEngine candidate = idle.poll();
                if (candidate == null) break;
                if (preferredModel.equals(loadedModels.get(candidate))) {
                    log.info("[MATLAB-POOL] 命中模型亲和引擎: {}", preferredModel);
                    return candidate;
                }
                idle.offer(candidate);
            }
        }
        return borrow(timeoutSec);
    }

    public void markLoadedModel(MatlabEngine eng, String modelName) {
        if (eng == null) return;
        if (modelName == null || modelName.trim().isEmpty()) loadedModels.remove(eng);
        else loadedModels.put(eng, modelName);
    }

    public MatlabEngine borrow(long timeoutSec) throws Exception {
        // 1. 先尝试取空闲引擎（非阻塞）
        MatlabEngine eng = idle.poll();
        if (eng != null) {
            return eng;
        }
        // 2. 常驻引擎启动失败
        if (startFailed) {
            throw new Exception("MATLAB 引擎启动失败，请回退到 matlab -batch");
        }
        // 3. 等待常驻引擎启动完成（首次启动时）
        if (starting.get()) {
            waitingCount.incrementAndGet();
            try {
                eng = idle.poll(timeoutSec, TimeUnit.SECONDS);
            } finally {
                waitingCount.decrementAndGet();
            }
            if (eng != null) return eng;
            if (startFailed) {
                throw new Exception("MATLAB 引擎启动失败，请回退到 matlab -batch");
            }
            throw new Exception("等待 MATLAB 引擎超时(" + timeoutSec + "s)：引擎可能仍在启动中");
        }
        // 4. 无空闲引擎，尝试按需创建新引擎（未达上限时）
        if (totalEngines.get() < maxEngines) {
            synchronized (this) {
                if (totalEngines.get() < maxEngines) {
                    int idx = totalEngines.incrementAndGet();
                    log.info("[MATLAB-POOL] 按需创建第 {}/{} 个 MATLAB 引擎...", idx, maxEngines);
                    try {
                        long t0 = System.currentTimeMillis();
                        MatlabEngine newEng = MatlabEngine.startMatlab();
                        long elapsed = System.currentTimeMillis() - t0;
                        log.info("[MATLAB-POOL] 第 {} 个引擎已就绪，耗时 {} ms", idx, elapsed);
                        return newEng;
                    } catch (Exception e) {
                        totalEngines.decrementAndGet();
                        log.error("[MATLAB-POOL] 按需创建引擎失败: {}", e.toString());
                        throw e;
                    }
                }
            }
        }
        // 5. 达上限，阻塞等待空闲引擎
        waitingCount.incrementAndGet();
        try {
            log.info("[MATLAB-POOL] 已达并发上限 {}，排队等待空闲引擎...", maxEngines);
            eng = idle.poll(timeoutSec, TimeUnit.SECONDS);
            if (eng == null) {
                throw new Exception("等待 MATLAB 引擎超时(" + timeoutSec + "s)：已达并发上限 " + maxEngines + "，所有引擎都在使用中");
            }
            return eng;
        } finally {
            waitingCount.decrementAndGet();
        }
    }

    /**
     * 归还引擎（不关闭），供下次仿真复用。
     */
    public void release(MatlabEngine eng) {
        if (eng != null) {
            idle.offer(eng);
        }
    }

    /** 引擎是否已启动就绪（至少常驻引擎已就绪） */
    public boolean isReady() {
        return started.get() && !startFailed;
    }

    /** 引擎是否正在启动中 */
    public boolean isStarting() {
        return starting.get();
    }

    /** 引擎是否启动失败（确定不可用，应回退） */
    public boolean isFailed() {
        return startFailed;
    }

    /** 当前空闲引擎数 */
    public int idleCount() {
        return idle.size();
    }

    /** 当前总引擎数（含使用中） */
    public int totalCount() {
        return totalEngines.get();
    }

    /** 正在排队等待引擎的任务数 */
    public int waitingCount() {
        return waitingCount.get();
    }

    /** 最大并发引擎数 */
    public int maxEngines() {
        return maxEngines;
    }

    /**
     * 重启引擎池：关闭所有引擎，重新异步启动常驻引擎。
     * 用于引擎卡在"启动中"或异常状态时，用户点击运行触发重启。
     */
    public void restart() {
        log.info("[MATLAB-POOL] 用户请求重启 MATLAB 引擎池");
        // 关闭所有引擎
        MatlabEngine eng;
        while ((eng = idle.poll()) != null) {
            try { eng.close(); } catch (Exception e) {
                try { eng.disconnect(); } catch (Exception ignored) {}
            }
        }
        loadedModels.clear();
        totalEngines.set(0);
        started.set(false);
        startFailed = false;
        starting.set(false);
        // 重新启动常驻引擎
        startEngineAsync();
    }

    /**
     * 关闭所有引擎。由 ProgramService @PreDestroy 调用。
     */
    public void shutdown() {
        log.info("[MATLAB-POOL] Spring Boot 关闭，正在关闭所有 MATLAB 引擎...");
        MatlabEngine eng;
        while ((eng = idle.poll()) != null) {
            try {
                eng.close();
                log.info("[MATLAB-POOL] 引擎已关闭");
            } catch (Exception e) {
                log.warn("[MATLAB-POOL] 关闭引擎异常: {}", e.toString());
                try { eng.disconnect(); } catch (Exception ignored) {}
            }
        }
        loadedModels.clear();
        totalEngines.set(0);
    }
}
