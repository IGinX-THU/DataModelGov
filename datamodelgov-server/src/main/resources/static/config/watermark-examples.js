/**
 * 水印配置测试示例
 * 
 * 使用方法：
 * 1. 将以下配置复制到 app-config.js 的 watermark 对象中
 * 2. 刷新页面查看效果
 */

// 示例1：自定义公司水印
const companyWatermark = {
    text: '某某科技有限公司',
    opacity: 0.08,
    fontSize: 42,
    color: '#666',
    rotation: -30,
    enable: true
};

// 示例2：更淡的水印
const lightWatermark = {
    text: '清华大学大数据系统软件国家工程研究中心',
    opacity: 0.05,
    fontSize: 48,
    color: '#ccc',
    rotation: -45,
    enable: true
};

// 示例3：彩色水印
const colorWatermark = {
    text: '内部文档 请勿外传',
    opacity: 0.15,
    fontSize: 36,
    color: '#ff6b6b',
    rotation: -25,
    enable: true
};

// 示例4：禁用水印
const noWatermark = {
    text: '清华大学大数据系统软件国家工程研究中心',
    opacity: 0.1,
    fontSize: 48,
    color: '#999',
    rotation: -45,
    enable: false
};

// 示例5：大字体水印
const largeWatermark = {
    text: 'CONFIDENTIAL',
    opacity: 0.12,
    fontSize: 72,
    color: '#999',
    rotation: -45,
    enable: true
};

console.log('水印配置测试示例已加载');
console.log('请将上述任一配置对象复制到 app-config.js 的 watermark 配置中');
