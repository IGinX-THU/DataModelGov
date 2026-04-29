# 水印配置使用说明

## 概述
visual-analysis组件的水印文案已经调整到前端配置文件 `static/config/app-config.js` 中，可以通过修改配置文件来自定义水印效果。

## 配置位置
配置文件位置：`datamodelgov-server/src/main/resources/static/config/app-config.js`

## 配置参数
在 `window.AppConfig.watermark` 对象中可以配置以下参数：

```javascript
watermark: {
    text: '清华大学大数据系统软件国家工程研究中心', // 水印文本内容
    opacity: 0.1,                                        // 透明度 (0-1)
    fontSize: 48,                                        // 字体大小（像素）
    color: '#999',                                       // 水印颜色
    rotation: -45,                                       // 旋转角度（度）
    enable: true                                         // 是否启用水印
}
```

## 参数说明

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `text` | string | '清华大学大数据系统软件国家工程研究中心' | 水印显示的文本内容 |
| `opacity` | number | 0.1 | 水印透明度，范围0-1，0表示完全透明，1表示完全不透明 |
| `fontSize` | number | 48 | 水印字体大小，单位为像素 |
| `color` | string | '#999' | 水印颜色，支持CSS颜色值 |
| `rotation` | number | -45 | 水印旋转角度，单位为度，负数表示逆时针旋转 |
| `enable` | boolean | true | 是否启用水印功能，false则不显示水印 |

## 使用示例

### 1. 修改水印文本
```javascript
watermark: {
    text: '我的公司名称',
    // ... 其他配置保持不变
}
```

### 2. 调整水印透明度
```javascript
watermark: {
    // ... 其他配置保持不变
    opacity: 0.05,  // 更淡的水印
}
```

### 3. 修改水印颜色和大小
```javascript
watermark: {
    // ... 其他配置保持不变
    color: '#ff0000',  // 红色水印
    fontSize: 36,      // 更小的字体
}
```

### 4. 禁用水印
```javascript
watermark: {
    // ... 其他配置保持不变
    enable: false  // 禁用水印
}
```

### 5. 调整水印角度
```javascript
watermark: {
    // ... 其他配置保持不变
    rotation: -30,  // 调整旋转角度为-30度
}
```

## 注意事项

1. 修改配置后需要刷新页面才能生效
2. 水印配置对visual-analysis组件的PDF导出功能生效
3. 透明度建议设置在0.05-0.2之间，既能看到水印又不会影响内容阅读
4. 字体大小建议根据实际需要调整，过大的字体可能影响页面布局
5. 颜色建议使用浅色系，如#999、#ccc等，避免影响主要内容

## 配置文件修改步骤

1. 打开 `datamodelgov-server/src/main/resources/static/config/app-config.js`
2. 找到 `watermark` 配置对象
3. 修改相应的参数值
4. 保存文件
5. 刷新浏览器页面查看效果

## 向后兼容

如果配置文件中的watermark配置不存在或格式错误，系统会使用默认的水印配置：
- 文本：'清华大学大数据系统软件国家工程研究中心'
- 透明度：0.1
- 字体大小：48px
- 颜色：#999
- 旋转角度：-45度
- 启用状态：true
