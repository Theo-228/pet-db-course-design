import axios from "axios";

const client = axios.create({ baseURL: "/api", withCredentials: true });
let csrf = "";

export async function refreshCsrf() {
  csrf = (await client.get("/auth/csrf")).data.token;
}

client.interceptors.request.use(async (config) => {
  if (!["get", "head", "options"].includes(config.method?.toLowerCase())) {
    if (!csrf) await refreshCsrf();
    config.headers["X-CSRF-TOKEN"] = csrf;
  }
  return config;
});

export async function api(method, path, data) {
  try {
    const result = await client.request({ method, url: path, data });
    return result.data;
  } catch (error) {
    if (
      error.response?.status === 403 &&
      error.response?.data?.message == null
    ) {
      await refreshCsrf();
      const result = await client.request({ method, url: path, data });
      return result.data;
    }
    throw error;
  }
}

export function errorMessage(error) {
  return error.response?.data?.message || error.message || "操作失败";
}
