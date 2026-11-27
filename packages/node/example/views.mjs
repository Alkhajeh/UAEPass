import { routes } from './config.mjs';
import { eligible } from './signing-jobs.mjs';

class SafeHtml {
  constructor(value) { this.value = value; }
  toString() { return this.value; }
}

const escapes = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };

function render(value) {
  if (value instanceof SafeHtml) return value.value;
  if (Array.isArray(value)) return value.map(render).join('');
  if (value === undefined || value === null || value === false) return '';
  return String(value).replace(/[&<>"']/g, (character) => escapes[character]);
}

/** Tagged template that escapes every interpolated value unless it is already `html`. */
export function html(strings, ...values) {
  return new SafeHtml(strings.reduce((out, string, index) =>
    out + string + (index < values.length ? render(values[index]) : ''), ''));
}

const styles = 'body{background:#f3f6f4;color:#152924;font:1rem/1.6 system-ui,sans-serif;margin:0}' +
  'main{background:white;max-width:48rem;margin:clamp(1rem,5vw,4rem) auto;padding:clamp(1rem,5vw,3rem);border:1px solid #d7e3dd;border-radius:1rem}' +
  'h1{line-height:1.2;margin:0 0 .75rem}a{color:#0b624b}iframe{width:100%;height:25rem;border:1px solid #d7e3dd;border-radius:.5rem}' +
  'button{border:0;border-radius:.5rem;padding:.7rem 1.1rem;background:#075945;color:white;font:inherit;font-weight:600;cursor:pointer}' +
  'form{margin-top:1rem}:focus-visible{outline:3px solid #337ca0;outline-offset:3px}';

export function page(response, status, body, locale = 'en') {
  const arabic = locale === 'ar';
  const title = arabic ? 'التوقيع التجريبي بالهوية الرقمية' : 'UAE PASS staging signing';
  const document = html`<!doctype html><html lang="${locale}" dir="${arabic ? 'rtl' : 'ltr'}"><meta charset="utf-8">\
<meta name="viewport" content="width=device-width, initial-scale=1">\
<title>${title}</title><style>${new SafeHtml(styles)}</style>\
<main><h1>${title}</h1>${body}</main></html>`;
  response.writeHead(status, { 'Content-Type': 'text/html; charset=utf-8' }).end(document.value);
}

export const backLink = html`<p><a href="${routes.root}">Return to signing</a></p>`;

const form = (action, label) => html`<form method="post" action="${action}"><button>${label}</button></form>`;
const status = (message) => html`<p role="status">${message}</p>`;

const terminalMessages = {
  canceled: ['Signing was canceled.', 'تم إلغاء التوقيع.'],
  failed: ['UAE PASS did not produce a signed PDF.', 'تعذّر الحصول على مستند موقّع من الهوية الرقمية.'],
  'signature-unverified': ['The signed PDF did not pass signature verification.', 'تعذّر التحقق من توقيع المستند.'],
  'signer-unverified': ['The verified signature could not be matched to the signed-in account.', 'تعذّرت مطابقة التوقيع مع الحساب المستخدم لتسجيل الدخول.'],
};

function signedOut(notice, locale, t) {
  const message = notice === 'canceled' ? status(t('Sign-in was canceled.', 'تم إلغاء تسجيل الدخول.')) :
    notice === 'error' ? status(t('UAE PASS sign-in could not be completed.', 'تعذّر إكمال تسجيل الدخول بالهوية الرقمية.')) : '';
  const login = locale === 'ar' ? routes.login + '?locale=ar' : routes.login;
  const languageLink = locale === 'ar'
    ? html`<a href="${routes.root}" lang="en" hreflang="en">English</a>`
    : html`<a href="${routes.root}?locale=ar" lang="ar" hreflang="ar">العربية</a>`;
  return html`${languageLink}${message}<p>${t('Sign in to review a synthetic PDF and test qualified signing.', 'سجّل الدخول لمراجعة مستند تجريبي واختبار التوقيع المؤهل.')}</p>\
${form(login, t('Sign in with UAE PASS', 'تسجيل الدخول بالهوية الرقمية'))}`;
}

function ineligible(profile, t) {
  const message = profile.userType === 'SOP2'
    ? t('Your UAE PASS signature is not qualified. Follow the steps in the UAE PASS app to upgrade your account.', 'توقيعك بالهوية الرقمية غير مؤهل. اتّبع تعليمات التطبيق لترقية حسابك.')
    : t('This account is ineligible. Use an SOP3 staging account with a verified Emirates ID and a qualified certificate.', 'استخدم حسابًا تجريبيًا من المستوى الثالث مع هوية إماراتية موثقة وشهادة توقيع مؤهلة.');
  return html`<p>${message}</p>${form(routes.login, t('Sign in again', 'إعادة تسجيل الدخول'))}`;
}

function review(t) {
  return html`<p>${t('Review the synthetic PDF before continuing to UAE PASS.', 'راجع المستند التجريبي قبل المتابعة إلى الهوية الرقمية.')}</p>\
<iframe title="${t('Synthetic PDF for review', 'مستند تجريبي للمراجعة')}" src="${routes.review}"></iframe>\
<p><a href="${routes.review}">${t('Open the sample PDF', 'فتح المستند التجريبي')}</a></p>\
${form(routes.start, t('Sign with UAE PASS', 'التوقيع بالهوية الرقمية'))}`;
}

function jobView(job, t) {
  const newSession = form(routes.login, t('Start a new signing session', 'بدء جلسة توقيع جديدة'));
  if (job.state === 'signed') {
    const cleanup = job.cleanupPending
      ? html`<p>${t('UAE PASS cleanup is pending.', 'لم يكتمل حذف النسخة المحفوظة لدى الهوية الرقمية.')}</p>${form(routes.check, t('Retry cleanup', 'إعادة محاولة الحذف'))}` : '';
    return html`${status(t('Signed PDF verified.', 'تم التحقق من المستند الموقّع.'))}\
<p><a href="${routes.download}">${t('Download the signed PDF', 'تنزيل المستند الموقّع')}</a></p>${cleanup}${newSession}`;
  }
  if (Object.hasOwn(terminalMessages, job.state)) {
    const next = job.state === 'canceled' ? form(routes.start, t('Start again', 'البدء من جديد')) : newSession;
    return html`${status(t(...terminalMessages[job.state]))}${next}`;
  }
  if (job.state === 'start-failed') {
    return html`${status(t('UAE PASS is unavailable. Signing has yet to start.', 'الهوية الرقمية غير متاحة حاليًا. لم تبدأ عملية التوقيع.'))}\
${form(routes.start, t('Try again', 'إعادة المحاولة'))}`;
  }
  if (job.state === 'start-uncertain') {
    return status(t('The signing request could not be confirmed. Reconcile it with UAE PASS before starting again.', 'تعذّر تأكيد طلب التوقيع. تحقّق من حالته لدى الهوية الرقمية قبل البدء من جديد.'));
  }
  if (!job.process) return status(t('Starting the signing request.', 'جارٍ بدء طلب التوقيع.'));
  const message = job.finalizationFailed
    ? t('The signed PDF could not be verified. Check the result again.', 'تعذّر التحقق من المستند الموقّع. تحقّق من النتيجة مرة أخرى.')
    : job.resultUnavailable
      ? t('The signing result is unavailable. Check again after approval.', 'نتيجة التوقيع غير متاحة. تحقّق منها بعد الموافقة.')
      : t('Complete or cancel the hosted signing request, then check its result.', 'أكمل طلب التوقيع أو ألغِه في الهوية الرقمية، ثم تحقّق من النتيجة.');
  const resume = job.state === 'awaiting' && form(routes.start, t('Return to UAE PASS', 'العودة إلى الهوية الرقمية'));
  return html`${status(message)}${resume}${form(routes.check, t('Check signing result', 'التحقّق من نتيجة التوقيع'))}`;
}

export function homePage(response, session, notice, locale) {
  const t = (english, arabic) => locale === 'ar' ? arabic : english;
  const body = !session?.profile ? signedOut(notice, locale, t) :
    !eligible(session.profile) ? ineligible(session.profile, t) :
    !session.job ? review(t) :
    jobView(session.job, t);
  return page(response, 200, body, locale);
}
