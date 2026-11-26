import { open, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { UaePassSignatureLevel, UaePassSigningValidationError } from '@alkhajeh/uaepass-server';
import { sampleDocument } from './config.mjs';
import { nonce } from './http.mjs';
import { matchesSignerIdn, normalizeSignerIdn } from './signer-idn.mjs';

/**
 * Job states:
 *   starting → awaiting → approved → signed
 *   starting → start-failed | start-uncertain
 *   awaiting → canceled | failed
 *   approved → signature-unverified | signer-unverified
 */

/** Keeps only the profile fields that signing needs. */
export function signingProfile({ uuid, idn, userType }) {
  return { uuid, idn, userType };
}

export function eligible(profile, level = UaePassSignatureLevel.Qualified) {
  const eligibleType = profile?.userType === 'SOP3' ||
    (level === UaePassSignatureLevel.Advanced && profile?.userType === 'SOP2');
  return eligibleType && typeof profile.uuid === 'string' &&
    profile.uuid.trim() !== '' && normalizeSignerIdn(profile.idn) !== undefined;
}

/** Maps a job state to the status reported to the Flutter example. */
export function appStatus(job) {
  switch (job.state) {
    case 'starting':
    case 'approved': return 'processing';
    case 'awaiting': return 'pending';
    case 'signed':
    case 'canceled': return job.state;
    default: return 'failed';
  }
}

async function writeSignedPdf(directory, pdf) {
  const path = join(directory, nonce() + '.pdf');
  const file = await open(path, 'wx', 0o600);
  try {
    try {
      await file.writeFile(pdf);
      await file.sync();
    } finally {
      await file.close();
    }
    return path;
  } catch (error) {
    await rm(path, { force: true }).catch(() => {});
    throw error;
  }
}

// Provider statuses that mean the process was never created.
const rejectedBeforeCreation = new Set([400, 403, 413, 415, 422]);

export function createSigningJobs({ signingClient, validationClient, pdf, directory }) {
  async function getToken(job) {
    if (!job.token || Date.now() >= job.token.validUntil) {
      const { accessToken, expiresInSeconds } = await signingClient.getAccessToken();
      job.token = { accessToken, validUntil: Date.now() + Math.max(0, expiresInSeconds - 15) * 1000 };
    }
    return job.token.accessToken;
  }

  async function withSigningToken(job, action) {
    try {
      return await action(await getToken(job));
    } catch (error) {
      if (error?.code !== 'invalid_token') throw error;
      job.token = undefined;
      return action(await getToken(job));
    }
  }

  /** Deletes the provider copy of the process. Leaves `cleanupPending` set on failure. */
  async function cleanup(job) {
    try {
      await withSigningToken(job, (token) => signingClient.deleteProcess(job.process.processId, token));
    } catch (error) {
      // A previous attempt may have succeeded before the response was lost.
      if (error?.status !== 404) return;
    }
    job.cleanupPending = false;
    job.token = undefined;
  }

  async function finalize(owner, job) {
    try {
      const signed = await withSigningToken(job, (token) => signingClient.downloadSignedPdf(job.process.documentId, token));
      const expectedIdn = owner.profile.idn;
      const { pdf: finalizedPdf } = await validationClient.finalizeSignedPdf(signed, {
        expectedSignatureFieldName: sampleDocument.signatureField.name,
        matchSigner: (signerSubject) => matchesSignerIdn(signerSubject, expectedIdn),
      });
      job.pdfPath = await writeSignedPdf(directory, finalizedPdf);
      job.finalizationFailed = false;
      job.state = 'signed';
      job.cleanupPending = true;
      return true;
    } catch (error) {
      if (error instanceof UaePassSigningValidationError &&
          (error.code === 'signer_unverified' || error.code === 'verification_failed')) {
        job.state = error.code === 'signer_unverified' ? 'signer-unverified' : 'signature-unverified';
        job.token = undefined;
      } else {
        job.finalizationFailed = true;
      }
      return false;
    }
  }

  /** Advances the owner's job as far as the provider allows. Concurrent calls are coalesced. */
  async function complete(owner) {
    const job = owner?.job;
    if (!job?.process || job.busy) return;
    job.busy = true;
    try {
      if (job.state === 'awaiting') {
        let result;
        try {
          result = await withSigningToken(job, (token) => signingClient.getProcessResult(job.process.processId, token));
        } catch {
          job.resultUnavailable = true;
          return;
        }
        job.resultUnavailable = false;
        if (result.status !== 'finished') {
          job.state = result.status === 'canceled' ? 'canceled' : 'failed';
          job.token = undefined;
          return;
        }
        job.state = 'approved';
      }
      if (job.state === 'approved' && !await finalize(owner, job)) return;
      if (job.cleanupPending) await cleanup(job);
    } finally {
      job.busy = false;
    }
  }

  /** Creates a provider signing process unless the owner already has a live job. */
  async function start(owner, surface, id = nonce()) {
    const current = owner.job;
    if (current && current.state !== 'start-failed' && current.state !== 'canceled') return current;

    const job = { id, surface, state: 'starting', busy: true };
    owner.job = job;
    try {
      let token;
      try {
        token = await getToken(job);
      } catch {
        job.state = 'start-failed';
        return job;
      }
      try {
        job.process = await signingClient.createProcess({
          ...sampleDocument,
          pdf,
          ...(owner.signatureLevel ? { signatureLevel: owner.signatureLevel } : {}),
        }, token);
      } catch (error) {
        const neverCreated = error?.code === 'invalid_token' ||
          (error?.code === 'rejected' && rejectedBeforeCreation.has(error.status));
        job.state = neverCreated ? 'start-failed' : 'start-uncertain';
        return job;
      }
      job.state = 'awaiting';
      return job;
    } finally {
      job.busy = false;
    }
  }

  return { start, complete, cleanup };
}
