import { Buffer } from 'node:buffer';

export function normalizeSignerIdn(value) {
  if (typeof value !== 'string' || !/^(?:784[0-9]{12}|784-[0-9]{4}-[0-9]{7}-[0-9])$/.test(value)) {
    return undefined;
  }
  return value.replaceAll('-', '');
}

function subjectSerialNumber(subject) {
  const serialNumbers = [];
  let start = 0;
  for (let index = 0; index <= subject.length; index += 1) {
    const character = subject[index];
    if (character === '\\') {
      index += 1;
      continue;
    }
    if (character === '"' || character === ';') return undefined;
    if (character !== ',' && character !== '+' && character !== undefined) continue;

    const attribute = subject.slice(start, index).trim();
    const separator = attribute.indexOf('=');
    const name = attribute.slice(0, separator).trim().toLowerCase();
    if (separator <= 0 || !/^[a-z0-9][a-z0-9.-]*$/.test(name)) return undefined;
    if (name === 'serialnumber' || name === '2.5.4.5' || name === 'oid.2.5.4.5') {
      serialNumbers.push(attribute.slice(separator + 1).trim());
    }
    start = index + 1;
  }

  if (start !== subject.length + 1 || serialNumbers.length !== 1) return undefined;
  const [value] = serialNumbers;
  if (!value.startsWith('#')) return normalizeSignerIdn(value);

  const hex = value.slice(1);
  if (!/^(?:[0-9a-f]{2}){2,20}$/i.test(hex)) return undefined;
  const encoded = Buffer.from(hex, 'hex');
  // The published X.509 example encodes this attribute as a DER PrintableString.
  if (encoded[0] !== 0x13 || encoded[1] !== encoded.length - 2) return undefined;
  return normalizeSignerIdn(encoded.subarray(2).toString('latin1'));
}

export function matchesSignerIdn(signerSubject, expectedIdn) {
  const idn = normalizeSignerIdn(expectedIdn);
  return idn !== undefined && typeof signerSubject === 'string' && subjectSerialNumber(signerSubject) === idn;
}
