import { get } from './api.js';

// Профиль, подписка и настройки проекта — одним запросом /api/me.
export const store = { me: null, meError: null, lastTab: '/' };

export async function loadMe() {
  try {
    store.me = await get('/api/me');
    store.meError = null;
  } catch (e) {
    store.me = null;
    store.meError = e;
  }
  if (store.me?.project?.name) document.title = store.me.project.name;
  return store.me;
}

export const sub = () => store.me?.subscription || null;
export const project = () => store.me?.project || {};
