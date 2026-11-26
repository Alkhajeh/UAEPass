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

export function page(response, status, body) {
  const document = html`<!doctype html><html lang="en"><meta charset="utf-8">\
<meta name="viewport" content="width=device-width, initial-scale=1">\
<title>UAE PASS staging signing</title><style>${new SafeHtml(styles)}</style>\
<main><h1>UAE PASS staging signing</h1>${body}</main></html>`;
  response.writeHead(status, { 'Content-Type': 'text/html; charset=utf-8' }).end(document.value);
}

export const backLink = html`<p><a href="${routes.root}">Return to signing</a></p>`;

const form = (action, label) => html`<form method="post" action="${action}"><button>${label}</button></form>`;
const status = (message) => html`<p role="status">${message}</p>`;

const terminalMessages = {
  canceled: 'Signing was canceled.',
  failed: 'UAE PASS did not produce a signed PDF.',
  'signature-unverified': 'The signed PDF did not pass signature verification.',
  'signer-unverified': 'The verified signature could not be matched to the signed-in account.',
};

function signedOut(notice) {
  const message = notice === 'canceled' ? status('Sign-in was canceled.') :
    notice === 'error' ? status('UAE PASS sign-in could not be completed.') : '';
  return html`${message}<p>Sign in to review a synthetic PDF and test qualified signing.</p>${form(routes.login, 'Sign in with UAE PASS')}`;
}

function ineligible(profile) {
  const message = profile.userType === 'SOP2'
    ? 'Your UAE PASS signature is not qualified. Follow the steps in the UAE PASS app to upgrade your account.'
    : 'This account is ineligible. Use an SOP3 staging account with a verified Emirates ID and a qualified certificate.';
  return html`<p>${message}</p>${form(routes.login, 'Sign in again')}`;
}

function review() {
  return html`<p>Review the synthetic PDF before continuing to UAE PASS.</p>\
<iframe title="Synthetic PDF for review" src="${routes.review}"></iframe>\
<p><a href="${routes.review}">Open the sample PDF</a></p>${form(routes.start, 'Sign with UAE PASS')}`;
}

function jobView(job) {
  if (job.state === 'signed') {
    const cleanup = job.cleanupPending
      ? html`<p>UAE PASS cleanup is pending.</p>${form(routes.check, 'Retry cleanup')}` : '';
    return html`${status('Signed PDF verified.')}<p><a href="${routes.download}">Download the signed PDF</a></p>\
${cleanup}${form(routes.login, 'Start a new signing session')}`;
  }
  if (Object.hasOwn(terminalMessages, job.state)) {
    const next = job.state === 'canceled' ? form(routes.start, 'Start again') : form(routes.login, 'Start a new signing session');
    return html`${status(terminalMessages[job.state])}${next}`;
  }
  if (job.state === 'start-failed') {
    return html`${status('UAE PASS is unavailable. Signing has yet to start.')}${form(routes.start, 'Try again')}`;
  }
  if (job.state === 'start-uncertain') {
    return status('The signing request could not be confirmed. Reconcile it with UAE PASS before starting again.');
  }
  if (!job.process) return status('Starting the signing request.');
  const message = job.finalizationFailed ? 'The signed PDF could not be verified. Check the result again.' :
    job.resultUnavailable ? 'The signing result is unavailable. Check again after approval.' :
    'Complete or cancel the hosted signing request, then check its result.';
  const resume = job.state === 'awaiting' && form(routes.start, 'Return to UAE PASS');
  return html`${status(message)}${resume}${form(routes.check, 'Check signing result')}`;
}

export function homePage(response, session, notice) {
  const body = !session?.profile ? signedOut(notice) :
    !eligible(session.profile) ? ineligible(session.profile) :
    !session.job ? review() :
    jobView(session.job);
  return page(response, 200, body);
}
