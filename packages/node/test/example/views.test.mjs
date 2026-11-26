import assert from 'node:assert/strict';
import { test } from 'node:test';
import { html } from '../../example/views.mjs';

test('html escapes interpolated values and keeps nested html fragments', () => {
  const fragment = html`<b>${'safe & sound'}</b>`;
  const rendered = html`<p title="${'"quoted"'}">${'<script>'}${fragment}${['<i>', fragment]}${false}${undefined}</p>`;
  assert.equal(rendered.value,
    '<p title="&quot;quoted&quot;">&lt;script&gt;<b>safe &amp; sound</b>&lt;i&gt;<b>safe &amp; sound</b></p>');
});
