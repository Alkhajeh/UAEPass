export { createUaePassClient, UaePassError } from './auth/client.js';
export type {
  UaePassClient,
  UaePassConfig,
  UaePassErrorCode,
  UaePassOperation,
  UaePassToken,
} from './auth/client.js';
export { UaePassGender, UaePassProfileType, UaePassUserType } from './auth/user-info.js';
export type { UaePassUserInfo } from './auth/user-info.js';

export {
  createUaePassSigningClient,
  UaePassSignatureAppearance,
  UaePassSignatureLevel,
  UaePassSigningError,
} from './signing/client.js';
export type {
  UaePassCreateSigningProcessInput,
  UaePassSigningClient,
  UaePassSigningConfig,
  UaePassSigningErrorCode,
  UaePassSigningOperation,
  UaePassSigningProcess,
  UaePassSigningResult,
  UaePassSigningStatus,
  UaePassSigningToken,
} from './signing/client.js';
export { createUaePassSigningValidationClient, UaePassSigningValidationError } from './signing/validation-client.js';
export type {
  UaePassFinalizedPdf,
  UaePassFinalizeSignedPdfOptions,
  UaePassSigningValidationClient,
  UaePassSigningValidationConfig,
  UaePassSigningValidationErrorCode,
  UaePassSigningValidationOperation,
  UaePassVerifiedPdfSignature,
} from './signing/validation-client.js';
