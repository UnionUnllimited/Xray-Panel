import { get } from '../api.js';
import { project } from '../store.js';
import { haptic, setMain, openLink, copyText, shareLink } from '../tg.js';
import { $, esc, icon, fmt, money, plural, daysWord, emptyHTML, toast } from '../ui.js';

const people = (n) => `${fmt(n)} ${plural(n, 'друг', 'друга', 'друзей')}`;

async function share(link, text) {
  haptic.impact('medium');
  const r = await shareLink(link, text);
  if (r === 'copied') toast('Ссылка скопирована');
  else if (r === 'failed') toast('Не удалось поделиться', 'error');
}

export default async function friends(root) {
  root.innerHTML = '<div class="topbar"><h1 class="title">Друзья</h1></div><div class="skeleton"></div>';
  const d = await get('/api/friends');
  const name = project().name;
  if (!d.link) {
    root.innerHTML = '<div class="topbar"><h1 class="title">Друзья</h1></div>' + emptyHTML('Реферальная программа сейчас недоступна.');
    return;
  }
  const bonuses = [
    d.join_days ? `<div class="row"><span>Друг подключился</span><b class="ok">+${daysWord(d.join_days)}</b></div>` : '',
    d.payment_days ? `<div class="row"><span>Друг впервые оплатил</span><b class="ok">+${daysWord(d.payment_days)}</b></div>` : ''
  ].join('');
  const p = d.partner;
  root.innerHTML = `
    <div class="topbar"><h1 class="title">Друзья</h1></div>
    <section class="hero">
      <h1>Приглашайте друзей.<br><span>Получайте дни бесплатно.</span></h1>
      <p>Отправьте ссылку — бонус начислится сам, как только друг подключится или оплатит.</p>
    </section>
    ${bonuses ? `<div class="card group">${bonuses}</div>` : ''}
    <section class="stack-sm">
      <p class="label">Ваша ссылка</p>
      <button type="button" class="card panel row-flex press" id="copyRef" style="text-align:left">
        <span class="grow code small" style="word-break:break-all;font-weight:500">${esc(d.link)}</span>${icon.copy}</button>
    </section>
    <div class="kpis">
      <div class="card kpi"><div class="k">Пришло по ссылке</div><div class="v">${fmt(d.invited)}</div></div>
      <div class="card kpi"><div class="k">Сегодня</div><div class="v">${fmt(d.today)}<span class="small muted"> / ${fmt(d.per_day)}</span></div></div>
    </div>
    <p class="note">В день засчитывается до ${people(d.per_day)} — лимит обновляется каждые сутки.</p>
    ${p ? `
    <section class="stack-sm">
      <p class="label">Партнёрская программа</p>
      <div class="card panel stack-sm">
        <div class="row-flex between"><span class="muted">Баланс</span><span class="tag">${fmt(p.percent)}% с оплат</span></div>
        <div class="price"><b>${money(p.balance)}</b></div>
        <div class="badges"><span class="tag neutral">${people(p.invited)}</span><span class="tag neutral">${fmt(p.payments)} ${plural(p.payments, 'оплата', 'оплаты', 'оплат')}</span></div>
        ${p.link ? `<button type="button" class="fill btn press" id="sharePartner">${icon.share} Партнёрская ссылка</button>` : ''}
        ${project().support_url ? `<button type="button" class="link-btn press" id="withdraw" style="align-self:flex-start;padding:0">Вывести${p.min_withdraw ? ` от ${money(p.min_withdraw)}` : ''} — через поддержку</button>` : ''}
      </div>
    </section>` : ''}`;

  const shareText = `Пользуюсь ${name} — работает стабильно. Попробуй по моей ссылке:`;
  $('#copyRef', root).addEventListener('click', async () => {
    haptic.impact('light');
    toast((await copyText(d.link)) ? 'Ссылка скопирована' : 'Не удалось скопировать');
  });
  $('#sharePartner', root)?.addEventListener('click', () => share(p.link, shareText));
  $('#withdraw', root)?.addEventListener('click', () => openLink(project().support_url));
  setMain({ text: 'Пригласить друга', onClick: () => share(d.link, shareText) });
}
