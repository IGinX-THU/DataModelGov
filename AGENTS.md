# DataModelGov 开发说明

## 构建 / 运行

```powershell
mvn -o -pl datamodelgov-core -am compile -DskipTests   # 快速编译核心模块
mvn -o package -DskipTests                             # 打包（server 模块产出可执行 jar）
```

- JDK 8（`java.version=1.8`），Maven 3.9。
- 源码文件必须是**不带 BOM 的 UTF-8**，否则 javac 报 `非法字符: '\ufeff'`。

## MATLAB 集成（program-run 仿真）

仿真通过 **MATLAB Engine API for Java**（`com.mathworks.engine.MatlabEngine`）执行：
`ProgramService.doRun` → `MatlabSimulationRunner`（`com.tsinghua.matlab`，非 Spring bean，
每个仿真任务 new 一个，持有引擎会话，用完 `close()`）。

- 编译期依赖 `datamodelgov-core/src/main/resources/libs/matlab-engine-R2019b.jar`（从
  `<MATLAB>/extern/engines/java/jar/engine.jar` 拷来，随项目提供，构建机不装 MATLAB 也能编译）。
  该目录已在 core 的 `<resources>` 中 `exclude`，避免被当作资源重复打进 classes。
  换 MATLAB 版本时替换该 jar 并同步改 `datamodelgov-core/pom.xml` 里的 `systemPath`。
  `spring-boot-maven-plugin` 已开启 `includeSystemScope`，打包会带上该 jar。
- **运行期原生库加载**：服务启动后由 `MatlabNativeLibrary.prepare(...)` 用 JNA 调用
  Win32 `SetDllDirectory` / `SetEnvironmentVariable`，把 `<MATLAB>/bin/win64` 注入到
  本进程的 DLL 搜索路径与 `PATH`，并反射重置 `java.library.path` 缓存，
  随后自行 `System.loadLibrary("nativemvm")` 验证。**通常无需再手动改 PATH**。
  MATLAB 安装目录解析顺序：`matlab.engine.home`（application.yml）→ `MATLAB_ROOT` 环境变量
  → `PATH` 中的 `matlab.exe` 所在目录 → `C:\Program Files\MATLAB` 下最新版本。
  若探测失败（未装 MATLAB / 版本不匹配 / DLL 残缺），服务自动回退到 `matlab -batch`，
  功能降级（无真实暂停），不会弹 Swing 对话框。
- application.yml 关键项：
  - `matlab.engine.enabled`（默认 true）置 false 可强制回退；
  - `matlab.engine.home`（默认空）显式指定 MATLAB 安装根目录，避免自动探测选错版本。
- `MatlabSimulationRunner.isApiAvailable()` 用 `Class.forName(name, false, loader)`
  **不初始化** `MatlabEngine` 类——R2019b 的 `MvmImpl.<clinit>` 在原生库加载失败时会
  弹 Swing 对话框，在 headless Spring Boot 进程里会抛 `HeadlessException` 刷屏。
  真正的引擎启动放到 worker 线程的 `startMatlab()`，失败由 `run()` 抛出并回退。
- `MatlabNativeLibrary` 不再自行 `System.loadLibrary("nativemvm")` 做探路——加载
  nativemvm.dll 会触发 `MatlabExecutor.<clinit>` → `MvmImpl.loadLibrary`，后者在依赖库
  缺失时通过 `SwingUtilities.invokeLater` 弹 Swing 对话框。改为只检查文件存在性 +
  注入路径。`startEngine()` 调用 `installHeadlessSuppressor()` push 一个自定义
  `EventQueue`，在 `dispatchEvent` 中静默吞掉 `HeadlessException`，然后再调
  `startMatlab()`。如果 `startMatlab()` 仍然失败（`UnsatisfiedLinkError` /
  `ExceptionInInitializerError`），`ProgramService` 捕获后回退到 `matlab -batch`。

```powershell
# 通常直接启动即可（原生库路径由服务自行注入）：
java -jar datamodelgov-server\target\datamodelgov-server-1.0.0.jar
# 若自动探测失败，可在 yml 里设 matlab.engine.home，或回退到旧用法：
$env:PATH = "C:\Program Files\MATLAB\R2019b\bin\win64;" + $env:PATH
java -jar datamodelgov-server\target\datamodelgov-server-1.0.0.jar
```

### 关键实现要点（R2019b 实测）

- `set_param(model,'SimulationCommand','start')` 是**异步**的：命令返回时仿真已在后台运行，
  期间（编译+初始化，本机约 1-2 分钟）引擎调用会排队。
- 运行中取数：`set_param(model,'SimulationCommand','WriteDataLogs')` 把 `logsout` 刷进
  base workspace，再按游标取增量（运行中、暂停中都可用）。
- 真实暂停/恢复/停止：`SimulationCommand` 的 `pause` / `continue` / `stop`，
  暂停时 `get_param(model,'SimulationTime')` 冻结。
- 信号必须按 **BlockPath** 匹配 `logsout` 元素；只设 `DataLoggingName` 时按名字
  `getElement('Np')` 找不到（需要同时设 `DataLoggingNameMode='Custom'`）。
- 停止时间会对齐到固定步长的整数倍（`SimTimeUtil.alignToStep`），
  否则 Simulink 实际停在最近的步长边界，与界面显示对不上。
- 模型 `FixedStep` 常是表达式（如 `Ts`），需在 base workspace 里求值后才能拿到数值。

回退方案 `writeWrapper` + `progressiveReveal`（matlab -batch 跑完再回放）保留在
`ProgramService` 中，仅在引擎不可用时使用。
