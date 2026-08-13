package com.tsinghua.matlab;

import com.mathworks.engine.MatlabEngine;
import lombok.extern.slf4j.Slf4j;

import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * MATLAB 引擎池：常驻一个 MatlabEngine 实例，避免每次仿真都重新启动 MATLAB（~2分钟）。
 *
 * Spring Boot 启动时由 init() 异步启动引擎；仿真时 borrow() 直接取已就绪的引擎。
 * Spring Boot 关闭时由 shutdown() 关闭引擎。
 * 由 ProgramService 通过 @PostConstruct/@PreDestroy 调用 init()/shutdown()。
 *
 * 单引擎串行：同一时刻只有一个仿真能使用引擎，第二个 borrow 会阻塞等待归还。
 * 这与 MATLAB Engine 本身的串行特性一致。
 */
@Slf4j
public class MatlabEnginePool {

    private final LinkedBlockingQueue<MatlabEngine> idle = new LinkedBlockingQueue<>(1);
    private final AtomicBoolean started = new AtomicBoolean(false);
    private volatile MatlabEngine engine;
    private volatile boolean startFailed = false;

    /**
     * 异步启动 MATLAB 引擎（不阻塞调用线程）。
     * 由 ProgramService @PostConstruct 调用。
     */
    public void init() {
        Thread t = new Thread(() -> {
            try {
                log.info("[MATLAB-POOL] Spring Boot 启动，正在启动 MATLAB 引擎...");
                MatlabNativeLibrary.prepare(null);
                MatlabNativeLibrary.installHeadlessSuppressor();
                long t0 = System.currentTimeMillis();
                MatlabEngine eng = MatlabEngine.startMatlab();
                long elapsed = System.currentTimeMillis() - t0;
                engine = eng;
                started.set(true);
                idle.offer(eng);
                log.info("[MATLAB-POOL] MATLAB 引擎已就绪，耗时 {} ms", elapsed);
            } catch (Exception e) {
                startFailed = true;
                log.error("[MATLAB-POOL] MATLAB 引擎启动失败，仿真将回退到 matlab -batch: {}", e.toString());
            }
        }, "matlab-engine-pool-init");
        t.setDaemon(true);
        t.start();
    }

    /**
     * 借出引擎，阻塞等待直到可用。
     * 引擎由 @PostConstruct 异步启动；如果启动尚未完成，会等待启动结束。
     */
    public MatlabEngine borrow(long timeoutSec) throws Exception {
        // 等待 @PostConstruct 启动完成（或失败）
        MatlabEngine eng = idle.poll(timeoutSec, TimeUnit.SECONDS);
        if (eng == null) {
            if (startFailed) {
                throw new Exception("MATLAB 引擎启动失败，请回退到 matlab -batch");
            }
            throw new Exception("等待 MATLAB 引擎超时(" + timeoutSec + "s)：引擎可能仍在启动中或上一个仿真仍在运行");
        }
        return eng;
    }

    /**
     * 归还引擎（不关闭），供下次仿真复用。
     */
    public void release(MatlabEngine eng) {
        if (eng != null) {
            idle.offer(eng);
        }
    }

    /**
     * 引擎是否已启动就绪。
     */
    public boolean isReady() {
        return started.get() && !startFailed;
    }

    /**
     * 引擎是否启动失败（确定不可用，应回退）。
     */
    public boolean isFailed() {
        return startFailed;
    }

    /**
     * 关闭引擎。由 ProgramService @PreDestroy 调用。
     */
    public void shutdown() {
        MatlabEngine eng = engine;
        if (eng == null) return;
        log.info("[MATLAB-POOL] Spring Boot 关闭，正在关闭 MATLAB 引擎...");
        try {
            eng.close();
            log.info("[MATLAB-POOL] 引擎已关闭");
        } catch (Exception e) {
            log.warn("[MATLAB-POOL] 关闭引擎异常: {}", e.toString());
            try { eng.disconnect(); } catch (Exception ignored) {}
        }
    }
}
