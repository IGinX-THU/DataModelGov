/**
 * 浏览器兼容垫片校验(须最先加载,先于 app-config.js 与所有业务脚本)。
 *
 * 部分国产浏览器(奇安信可信浏览器等)会向页面注入自己的 Object.entries/values
 * 兼容垫片,个别版本实现有缺陷:对普通对象返回数组下标键(['0',...]),
 * 导致依赖 entries 的代码把 '0' 当属性名写入 DOM(setAttribute DOMException)、
 * 或把对象误构造成数组。此处自检:原生实现行为正确则不动;缺失或行为异常则
 * 用 ES5 实现覆盖,全站所有 Object.entries/values 调用点随之恢复正常。
 */
(function () {
    function entriesBroken(fn) {
        try {
            var t = fn({ a: 1, b: 2 });
            if (!t || t.length !== 2) return true;
            for (var i = 0; i < t.length; i++) {
                if (!(t[i] instanceof Array) || typeof t[i][0] !== 'string' || t[i][0] === '0') return true;
            }
            if (t[0][0] !== 'a' || t[0][1] !== 1 || t[1][0] !== 'b' || t[1][1] !== 2) return true;
            return false;
        } catch (e) { return true; }
    }

    if (typeof Object.entries !== 'function' || entriesBroken(Object.entries)) {
        Object.entries = function (obj) {
            var out = [];
            for (var k in obj) {
                if (Object.prototype.hasOwnProperty.call(obj, k)) out.push([k, obj[k]]);
            }
            return out;
        };
    }

    if (typeof Object.values !== 'function' || entriesBroken(Object.values)) {
        Object.values = function (obj) {
            var out = [];
            for (var k in obj) {
                if (Object.prototype.hasOwnProperty.call(obj, k)) out.push(obj[k]);
            }
            return out;
        };
    }
})();
