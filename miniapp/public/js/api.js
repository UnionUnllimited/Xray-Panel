import { tg } from './tg.js';

// Мини-апп живёт под путём (/miniapp/), API — рядом (/miniapp/api/...). Модуль лежит в
// <app>/js/, поэтому адреса считаем от родительского каталога, а не от корня домена.
const BASE = new URL('../', import.meta.url);
export const appUrl = (path) => new URL(String(path).replace(/^\//, ''), BASE).toString();

export class ApiError extends Error {
  constructor(status, message, code) { super(message); this.status = status; this.code = code; }
}

// Внутри Telegram — подписанный initData; вне Telegram API отвечает 401.
const authHeader = () => (tg ? `tma ${tg.initData}` : '');

export async function api(path, { method = 'GET', body } = {}) {
  let res;
  try {
    res = await fetch(appUrl(path), {
      method,
      headers: { authorization: authHeader(), ...(body !== undefined ? { 'content-type': 'application/json' } : {}) },
      body: body !== undefined ? JSON.stringify(body) : undefined
    });
  } catch {
    throw new ApiError(0, 'Нет соединения с сервером');
  }
  const data = await res.json().catch(() => ({}));
  if (!res.ok || data.ok === false) throw new ApiError(res.status, data.error || 'Ошибка сервера', data.code);
  return data;
}

export const get = (path) => api(path);
export const post = (path, body = {}) => api(path, { method: 'POST', body });
