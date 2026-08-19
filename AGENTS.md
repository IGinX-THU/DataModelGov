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
  若探测失败（未装 MATLAB / 版本不匹配 / DLL 残缺），引擎不可用，
  仿真任务直接标记 FAILED，不会弹 Swing 对话框。
- application.yml 关键项：
  - `matlab.engine.enabled`（默认 true）置 false 可禁用引擎（任务直接 FAILED）；
  - `matlab.engine.home`（默认空）显式指定 MATLAB 安装根目录，避免自动探测选错版本。
- `MatlabSimulationRunner.isApiAvailable()` 用 `Class.forName(name, false, loader)`
  **不初始化** `MatlabEngine` 类——R2019b 的 `MvmImpl.<clinit>` 在原生库加载失败时会
  弹 Swing 对话框，在 headless Spring Boot 进程里会抛 `HeadlessException` 刷屏。
  真正的引擎启动放到 worker 线程的 `startMatlab()`，失败由 `run()` 抛出，任务 FAILED。
- `MatlabNativeLibrary` 不再自行 `System.loadLibrary("nativemvm")` 做探路——加载
  nativemvm.dll 会触发 `MatlabExecutor.<clinit>` → `MvmImpl.loadLibrary`，后者在依赖库
  缺失时通过 `SwingUtilities.invokeLater` 弹 Swing 对话框。改为只检查文件存在性 +
  注入路径。`startEngine()` 调用 `installHeadlessSuppressor()` push 一个自定义
  `EventQueue`，在 `dispatchEvent` 中静默吞掉 `HeadlessException`，然后再调
  `startMatlab()`。如果 `startMatlab()` 仍然失败（`UnsatisfiedLinkError` /
  `ExceptionInInitializerError`），`ProgramService` 捕获后标记 FAILED，不再回退。

```powershell
# 通常直接启动即可（原生库路径由服务自行注入）：
java -jar datamodelgov-server\target\datamodelgov-server-1.0.0.jar
# 若自动探测失败，可在 yml 里设 matlab.engine.home，或手动注入 PATH：
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

回退方案 `writeWrapper` + `progressiveReveal`（matlab -batch 跑完再回放）已移除。
引擎不可用时任务直接标记 FAILED，不再降级运行。

## 仿真程序配置框架（ProgramConfig）

仿真程序的"怎么跑、怎么采信号、页面怎么显示"全部由 `ProgramConfig`
（`com.tsinghua.program.config.ProgramConfig`）描述，存于 `ProgramEntity.configJson`。

- 配置编辑：程序管理页"配置"按钮 → `GET/PUT /program/config`，可视化编辑 + JSON 上传下载。
- 运行时：`ProgramService.doRun` 解析配置 → `writeProgramConfig` 把 `setupScript` 内容写到
  `taskDir/dmg_setup.m` → `MatlabSimulationRunner` 按配置写参数、cd(taskDir)、调用 `dmg_setup`（须在
  base workspace 留下 `dmg_cols`）→ runner 读 `dmg_cols` 构造 CSV 表头。
- 参数：前端按 `parameters[]` 动态渲染表单，提交时除固定项（name/version/stopTime/
  fixedStep/modelFile/projectName）外全部作为动态参数透传，runner 按 `matlabVar` 写入
  base workspace。
- 信号采集：`setupScript` 存的是 MATLAB 源码内容（不是文件名），运行时写入 taskDir；
  `signals[]` 字段用于文档化/probe 草稿，runner 当前不直接消费。
- AFO 回归基线：`program-config-afo.json`（含完整的 `dmg_setup` 脚本内容）。
- 源码参考：`program-templates/dmg_setup_afo.m`（与配置 JSON 中内联的脚本内容一致）。
- `ProgramConfigMapper.parse/stringify/validate` 前后端共用校验。

## 前端插件/扩展系统

当标准 `ProgramConfig.ui` 不够用时，集成人员可上传可复用的前端插件（JS/CSS），
程序配置通过 `ui.extension` 引用。

- 后端：`PluginController`（`/api/program/plugin`）+ `PluginService`，文件存储在
  `${data.dir}/extensions/<pluginId>/`，元数据索引在 `extensions/index.json`。
- 前端管理：程序菜单 → 插件管理（`plugin-management` 组件），支持上传/编辑/删除。
  删除前检查引用计数（扫描所有 `ProgramConfig.ui.extension.entry`）。
- 运行时加载：`program-run.js` 的 `loadExtension(ext)` 按 `ext.mode` 挂载：
  - `slot`：挂到 `data-plugin-slot` 锚点或 chart-grid 之后（增量）。
  - `override`：隐藏 `main` 区域，插件接管整个运行区。
- 插件契约：ES module，`export default` 类或工厂函数，接收 `ctx`：
  - `ctx.mount` / `ctx.shadow`：Shadow DOM 隔离的挂载点。
  - `ctx.config` / `ctx.signals`：ProgramConfig 与信号元数据。
  - `ctx.getData()`：最新 CSV 数据（headers + rows）。
  - `ctx.onData(fn)`：订阅实时数据流（SSE 推送时回调）。
  - `ctx.controls.start()/pause()/resume()/stop()`：仿真控制。
  - `ctx.getStatus()`：当前仿真状态。
  - `ctx.echarts`：共享 ECharts 实例。
  - 可选 `async init(ctx)` / `destroy()`。
- 错误边界：插件加载/运行异常不破坏主页面，只在 footer 提示。
- 认证：插件 JS/CSS 通过 `?token=<jwt>` query 参数认证（`import()` 不支持自定义 header）。
- 示例插件：`program-templates/afo-extra.js`（实时扭矩监控面板）。
