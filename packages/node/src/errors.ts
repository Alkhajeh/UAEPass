/** The base class of every error a UAE PASS client reports for a provider request. */
export abstract class UaePassBaseError<Code extends string = string, Operation extends string = string> extends Error {
  constructor(
    readonly code: Code,
    readonly operation: Operation,
    message: string,
    readonly status?: number,
  ) {
    super(message);
  }
}
