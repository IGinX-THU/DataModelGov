// 接口基础路径
const API_BASE_URL = "/api/v1";

/**
 * 统一请求封装
 * @param url 接口路径
 * @param method 请求方法
 * @param data 请求数据
 * @returns {Promise<any>}
 */
async function request(url, method, data = {}) {
    try {
        const options = {
            method,
            headers: {
                "Content-Type": "application/json"
            },
            credentials: "same-origin"
        };
        if (method !== "GET") {
            options.body = JSON.stringify(data);
        }
        const response = await fetch(`${API_BASE_URL}${url}`, options);
        const res = await response.json();
        if (res.code !== 200) {
            alert(`操作失败：${res.message}`);
            return null;
        }
        return res.data;
    } catch (error) {
        alert(`网络错误：${error.message || "请检查系统是否启动"}`);
        return null;
    }
}

// 数据源相关接口
const DataSourceApi = {
    register: (data) => request("/data/source/register", "POST", data),
    list: () => request("/data/source/list", "GET"),
    remove: (alias) => request(`/data/source/remove/${alias}`, "DELETE")
};