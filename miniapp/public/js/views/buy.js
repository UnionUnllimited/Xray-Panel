import { get, post } from '../api.js';
import { loadMe, sub } from '../store.js';
import { haptic, setMain, mainProgress, openLink, openInvoice, onReturn } from '../tg.js';
import {
  $, $$, esc, icon, money, fmt, plural, daysWord, devicesWord, dateLong, segHTML, bindSeg,
  emptyHTML, openSheet, closeSheet, toast, toastError
} from '../ui.js';

export function periodLabel(d) {
  if (d % 365 === 0) return d === 365 ? '1 год' : `${d / 365} ${plural(d / 365, 'год', 'года', 'лет')}`;
  if (d % 30 === 0) return `${d / 30} ${plural(d / 30, 'месяц', 'месяца', 'месяцев')}`;
  return daysWord(d);
}
const limitLabel = (n) => (n > 0 ? String(n) : '∞');
const limitText = (n) => (n > 0 ? `до ${devicesWord(n)}` : 'без лимита устройств');
const priceOf = (t) => (t.method === 'tgstar' ? `${fmt(t.stars)} ⭐` : money(t.price, t.currency));

const RULE_NOTE = {
  same: (cur) => `Сейчас можно продлить только с вашим лимитом — ${limitText(cur)}. Сменить его получится за 7 дней до конца подписки или после неё.`,
  same_or_higher: (cur) => `Можно оставить ${limitText(cur)} или выбрать больше. Понизить лимит — через поддержку.`
};

// Ожидание оплаты в браузере: после возврата сверяем срок подписки с тем, что был до оплаты.
function waitForPayment(before, navigate, { invoice = false } = {}) {
  let stop = null;
  let timer = null;
  let done = false;
  const finish = () => { done = true; clearTimeout(timer); stop?.(); };
  const check = async (manual) => {
    if (done) return;
    await loadMe();
    const now = sub();
    if (now && now.end_at !== before) {
      finish();
      closeSheet(true);
      haptic.notify('success');
      openSheet('Оплата прошла', `
        <div class="empty" style="padding:6px 0 0"><span class="lgs ico">${icon.check}</span>
          <p>Подписка активна до <b>${dateLong(now.end_at)}</b>. Если устройство ещё не подключено — это займёт минуту.</p></div>`,
      null, { main: { text: 'Подключить устройство', onClick: () => { closeSheet(true); navigate('/connect'); } } });
      return;
    }
    if (manual) toast('Оплата ещё не пришла. Обычно это занимает до минуты');
  };
  // Касса сообщает о платеже с задержкой — после возврата проверяем ещё 2 минуты.
  const poll = (n = 0) => { if (!done && n < 40) timer = setTimeout(async () => { await check(false); poll(n + 1); }, 3000); };
  stop = onReturn(() => { check(false); poll(); });
  if (invoice) poll();
  openSheet(invoice ? 'Продлеваем подписку' : 'Ждём оплату', `
    <p class="note" style="font-size:15px;color:var(--text-2)">${invoice
      ? 'Telegram принял оплату. Подписка продлится через несколько секунд — экран обновится сам.'
      : 'Страница оплаты открылась в браузере. Оплатите и вернитесь сюда — подписка продлится автоматически, обычно за минуту.'}</p>
    <p class="note">Бот тоже пришлёт сообщение, когда платёж пройдёт.</p>`,
  null, { main: { text: 'Я оплатил — проверить', onClick: () => check(true) }, onClose: finish });
}

export default async function buy(root, { navigate }) {
  root.innerHTML = '<div class="topbar"><h1 class="title">Тарифы</h1></div><div class="skeleton"></div>';
  const data = await get('/api/tariffs');
  const tariffs = data.tariffs;
  if (!tariffs.length || !data.methods.length) {
    root.innerHTML = '<div class="topbar"><h1 class="title">Тарифы</h1></div>' +
      emptyHTML('Оплата сейчас недоступна. Напишите в поддержку — подскажем, как продлить.');
    return;
  }
  const rules = data.rules;
  const periods = [...new Set(tariffs.map((t) => t.days))].sort((a, b) => a - b);
  const sortLimits = (a, b) => (a <= 0) - (b <= 0) || a - b;
  const state = { days: periods[0], limit: null, method: null };

  root.innerHTML = `
    <div class="topbar"><h1 class="title">Тарифы</h1></div>
    ${rules.mode !== 'any' ? `<div class="callout">${esc(RULE_NOTE[rules.mode](rules.current))}</div>` : ''}
    <section class="stack-sm">
      <p class="label">Срок</p>
      <div id="periodBox">${segHTML(periods.map((d) => ({ id: d, name: periodLabel(d) })), state.days)}</div>
    </section>
    <section class="stack-sm">
      <p class="label">Устройства</p>
      <div class="chips" id="limitBox" role="radiogroup" aria-label="Количество устройств"></div>
    </section>
    <section class="stack-sm">
      <p class="label">Способ оплаты</p>
      <div class="card group" id="methodBox" role="radiogroup"></div>
    </section>
    <section class="card panel stack-sm" id="summary"></section>
    <p class="note">Дни добавляются к текущему сроку. Оплата проходит в защищённом окне кассы или Telegram.</p>`;

  const forPeriod = () => tariffs.filter((t) => t.days === state.days);
  const forLimit = () => forPeriod().filter((t) => t.limit_ip === state.limit);
  const current = () => forLimit().find((t) => t.method === state.method) || null;

  const drawLimits = () => {
    const limits = [...new Set(forPeriod().map((t) => t.limit_ip))].sort(sortLimits);
    const allowed = (n) => forPeriod().some((t) => t.limit_ip === n && t.allowed);
    if (state.limit === null || !limits.includes(state.limit) || !allowed(state.limit)) {
      state.limit = (limits.includes(rules.current) && allowed(rules.current)) ? rules.current : (limits.find(allowed) ?? limits[0]);
    }
    $('#limitBox', root).innerHTML = limits.map((n) => `
      <button type="button" class="${n === state.limit ? 'sel' : 'fill'} chip press" role="radio" aria-checked="${n === state.limit}"
        data-limit="${n}" ${allowed(n) ? '' : 'disabled'} aria-label="${esc(limitText(n))}">${limitLabel(n)}</button>`).join('');
  };

  const drawMethods = () => {
    const list = data.methods.map((m) => forLimit().find((t) => t.method === m.id)).filter(Boolean);
    if (!list.some((t) => t.method === state.method)) state.method = list[0]?.method || null;
    $('#methodBox', root).innerHTML = list.length ? list.map((t) => {
      const m = data.methods.find((x) => x.id === t.method);
      return `<button type="button" class="row press plan" role="radio" aria-checked="${t.method === state.method}" data-method="${esc(t.method)}">
        <span class="row-flex"><span class="radio" aria-hidden="true"></span><span>${esc(m.name)}${t.method === 'tgstar' ? `<span class="sub">≈ ${money(t.price)}</span>` : ''}</span></span>
        <b>${priceOf(t)}</b></button>`;
    }).join('') : '<div class="row"><span class="muted">Для этого варианта нет способа оплаты</span></div>';
  };

  const drawSummary = () => {
    const t = current();
    const box = $('#summary', root);
    if (!t) { box.hidden = true; setMain(null); return; }
    box.hidden = false;
    const perMonth = t.days >= 60 && t.method !== 'tgstar' ? Math.round((t.price / t.days) * 30) : 0;
    box.innerHTML = `
      <div class="row-flex between"><span class="label" style="margin:0;padding:0">Итого</span>${perMonth ? `<span class="tag good">${money(perMonth, t.currency)} / мес</span>` : ''}</div>
      <div class="price"><b>${priceOf(t)}</b> <small>за ${periodLabel(t.days)}</small></div>
      <div class="badges">
        <span class="tag neutral">${esc(limitText(t.limit_ip))}</span>
        <span class="tag neutral">${t.traffic_gb ? `${fmt(t.traffic_gb)} ГБ трафика` : 'безлимитный трафик'}</span>
      </div>
      ${t.description ? `<p class="note" style="padding:0">${esc(t.description)}</p>` : ''}`;
    setMain({ text: `Оплатить ${priceOf(t)}`, shine: true, onClick: () => pay(t) });
  };

  const redraw = () => { drawLimits(); drawMethods(); drawSummary(); };

  const pay = async (t) => {
    haptic.impact('medium');
    mainProgress(true);
    const before = sub()?.end_at || null;
    try {
      const r = await post('/api/pay', { tariff_id: t.id, method: t.method });
      mainProgress(false);
      if (r.kind === 'invoice') {
        const status = await openInvoice(r.url);
        if (status === 'paid') {
          haptic.notify('success');
          waitForPayment(before, navigate, { invoice: true });
        } else if (status === 'failed') {
          toast('Платёж не прошёл', 'error');
        }
        return;
      }
      openLink(r.url);
      waitForPayment(before, navigate);
    } catch (e) {
      mainProgress(false);
      toastError(e);
    }
  };

  bindSeg($('#periodBox .seg', root), (v) => { state.days = Number(v); redraw(); });
  $('#limitBox', root).addEventListener('click', (e) => {
    const b = e.target.closest('[data-limit]');
    if (!b || b.disabled) return;
    haptic.select();
    state.limit = Number(b.dataset.limit);
    redraw();
  });
  $('#methodBox', root).addEventListener('click', (e) => {
    const b = e.target.closest('[data-method]');
    if (!b) return;
    haptic.select();
    state.method = b.dataset.method;
    $$('[data-method]', root).forEach((x) => x.setAttribute('aria-checked', x === b));
    drawSummary();
  });
  redraw();
}
