/**
 * 示例插件：AFO 扩展面板
 *
 * 插件契约：
 * - 导出 default 类或工厂函数，构造/调用时接收 ctx
 * - 可选实现 async init(ctx)
 * - 可选实现 destroy()
 * - 所有 DOM 操作应在 ctx.mount 或 ctx.shadow 内，保持 Shadow DOM 隔离
 * - 通过 ctx.onData(fn) 订阅实时数据流
 * - 通过 ctx.controls.start()/pause()/resume()/stop() 控制仿真
 * - 通过 ctx.getStatus() 获取当前状态
 * - 通过 ctx.getData() 获取最新 CSV 数据
 * - 通过 ctx.config 读取 ProgramConfig
 * - 通过 ctx.signals 读取信号元数据
 * - 通过 ctx.echarts 访问 ECharts 实例（共享）
 *
 * 错误边界：插件抛异常不会破坏主页面，只在 footer 显示提示。
 */
class AfoExtraPanel {
  constructor(ctx) {
    this.ctx = ctx;
    this.chart = null;
    this.dataHandler = null;
  }

  async init(ctx) {
    const { mount, echarts } = ctx;
    mount.innerHTML = `
      <style>
        .extra-panel { padding: 16px; font-family: sans-serif; color: #e5e7eb; }
        .extra-panel h3 { margin: 0 0 12px; font-size: 16px; }
        .extra-chart { width: 100%; height: 300px; }
        .extra-info { margin-top: 12px; font-size: 13px; color: #9ca3af; }
      </style>
      <div class="extra-panel">
        <h3>扩展面板 - 实时扭矩监控</h3>
        <div class="extra-chart"></div>
        <div class="extra-info">本面板由插件 afo-extra-v1 提供，展示 Mkp 信号的实时曲线。</div>
      </div>
    `;
    const chartDom = mount.querySelector('.extra-chart');
    if (chartDom && echarts) {
      this.chart = echarts.init(chartDom, null, { renderer: 'canvas', backgroundColor: 'transparent' });
      this.chart.setOption({
        backgroundColor: 'transparent',
        tooltip: { trigger: 'axis' },
        xAxis: { type: 'value', name: '时间 (s)' },
        yAxis: { type: 'value', name: 'N·m' },
        series: [{ name: 'Mkp', type: 'line', smooth: true, data: [] }]
      });
    }
    // 订阅数据流
    this.dataHandler = (data) => this.updateChart(data);
    ctx.onData(this.dataHandler);
  }

  updateChart({ headers, rows }) {
    if (!this.chart || !rows || !rows.length) return;
    const mkpIdx = headers.indexOf('Mkp');
    const timeIdx = headers.indexOf('time') != null ? headers.indexOf('time') : 0;
    if (mkpIdx < 0) return;
    const seriesData = rows.map(r => [parseFloat(r[timeIdx]), parseFloat(r[mkpIdx])]);
    this.chart.setOption({ series: [{ data: seriesData }] });
  }

  destroy() {
    if (this.chart) {
      this.chart.dispose();
      this.chart = null;
    }
    this.dataHandler = null;
  }
}

export default AfoExtraPanel;
