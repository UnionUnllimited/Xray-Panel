import { post } from '../api.js';
import { store, loadMe, sub, project } from '../store.js';
import { haptic, setMain, mainProgress, openLink } from '../tg.js';
import { $, esc, icon, avatarHTML, dateLong, daysWord, devicesWord, bytes, toast, toastError, plural } from '../ui.js';

// Карточка статуса: та же роль, что у hero в «Линзе», но про подписку клиента.
export function statusCardHTML(s, trial) {
  if (s && s.active) {
    const t = s.traffic;
    const unlimited = !t || !t.limit;
    const pct = unlimited ? 0 : Math.min(100, Math.round((t.used / t.limit) * 100));
    const left = s.days_left >= 1 ? daysWord(s.days_left) : `${s.hours_left} ${plural(s.hours_left, 'час', 'часа', 'часов')}`;
    return `
      <section class="hero status-hero">
        <span class="health good"><i aria-hidden="true"></i>Подписка активна</span>
        <h1>Осталось ${left}<br><span>до ${dateLong(s.end_at)}</span></h1>
        <div class="stats">
          <div class="card stat"><span class="k">Устройства</span><span class="v">${s.limit_ip ? `до ${s.limit_ip}` : '∞'}</span></div>
          <div class="card stat"><span class="k">Трафик</span><span class="v">${unlimited ? '∞' : bytes(t.limit)}</span></div>
          <div class="card stat"><span class="k">Использовано</span><span class="v">${t ? bytes(t.used) : '—'}</span></div>
        </div>
        ${unlimited ? '' : `<div class="bar" role="img" aria-label="Использовано ${pct}% трафика"><i style="width:${pct}%"></i></div>`}
      </section>`;
  }
  if (s) {
    return `
      <section class="hero status-hero">
        <span class="health bad"><i aria-hidden="true"></i>Подписка закончилась</span>
        <h1>Продлите доступ<br><span>срок истёк ${dateLong(s.end_at)}</span></h1>
        <p>Настройки на устройствах сохранятся — после оплаты всё заработает само.</p>
      </section>`;
  }
  return `
    <section class="hero status-hero">
      <h1>Стабильный доступ.<br><span>Без лишних настроек.</span></h1>
      <p>${trial?.available ? `Попробуйте бесплатно ${daysWord(trial.days)} — без карты и без обязательств.` : 'Выберите тариф, оплатите удобным способом и подключитесь за минуту.'}</p>
    </section>`;
}

export async function takeTrial(onDone) {
  haptic.impact('medium');
  mainProgress(true);
  try {
    const r = await post('/api/trial');
    haptic.notify('success');
    toast(`Готово! Пробный период на ${daysWord(r.days)}`);
    await loadMe();
    onDone?.();
  } catch (e) {
    mainProgress(false);
    if (e.code === 'channel' && store.me?.trial?.channel) {
      toast(e.message);
      openLink(store.me.trial.channel);
      return;
    }
    toastError(e);
  }
}

export default async function home(root, { navigate, refresh }) {
  const me = store.me;
  const s = sub();
  const p = project();
  root.innerHTML = `
    <div class="topbar">
      <span class="brand"><img src="img/logo.svg" alt="">${esc(p.name)}</span>
      <button type="button" class="press" data-nav="/profile" aria-label="Профиль" style="border-radius:50%">${avatarHTML(me.user)}</button>
    </div>
    ${statusCardHTML(s, me.trial)}
    <div class="tiles">
      <button type="button" class="card tile press" data-nav="/connect"><span class="lgs ico-sm">${icon.bolt}</span><span class="t">Подключить</span></button>
      <button type="button" class="card tile press" data-nav="/buy"><span class="lgs ico-sm">${icon.card}</span><span class="t">${s ? 'Продлить' : 'Тарифы'}</span></button>
      <button type="button" class="card tile press" data-nav="/friends"><span class="lgs ico-sm">${icon.gift}</span><span class="t">Пригласить друга</span></button>
      ${p.support_url ? `<button type="button" class="card tile press" id="supportTile"><span class="lgs ico-sm">${icon.support}</span><span class="t">Поддержка</span></button>` : ''}
    </div>
    ${s && s.active && s.days_left <= 3 ? `<div class="callout warn">Подписка закончится ${dateLong(s.end_at)}. Продлите заранее — дни добавятся к текущему сроку.</div>` : ''}
    ${me.features.devices ? `<div class="card group">
      <button type="button" class="row press" data-nav="/devices"><span class="row-flex">${icon.devices}<span>Мои устройства</span></span>${icon.chev}</button></div>` : ''}`;

  $('#supportTile', root)?.addEventListener('click', () => { haptic.impact('light'); openLink(p.support_url); });

  // Главное действие — нативная MainButton Telegram (вне Telegram — кнопка на странице).
  if (!s && me.trial.available) {
    setMain({ text: `Попробовать ${daysWord(me.trial.days)} бесплатно`, shine: true, onClick: () => takeTrial(refresh) });
  } else if (s && s.active) {
    setMain({ text: 'Подключить устройство', onClick: () => navigate('/connect') });
  } else {
    setMain({ text: s ? 'Продлить подписку' : 'Выбрать тариф', shine: true, onClick: () => navigate('/buy') });
  }
}

export { devicesWord };
