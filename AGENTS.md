# UAE PASS repository guide

## Packages

- `packages/flutter` is the Android, iOS, and Web plugin. Keep `package:uaepass/uaepass.dart` as the public entry point. [Flutter integration guide](packages/flutter/README.md)
- `packages/flutter/example` is the runnable Flutter demo. It uses the local plugin and can opt in to the local Node staging backend. [Flutter demo guide](packages/flutter/example/README.md)
- `packages/node` is the server-only TypeScript SDK. Use Node.js 22+ and npm from this directory, with its own lockfile. The staging backend example lives in `packages/node/example`. [Node SDK guide](packages/node/README.md)

## Development checks

For Flutter changes, use the Flutter version pinned in CI and run these commands from both `packages/flutter` and `packages/flutter/example`. [Flutter CI workflow](.github/workflows/flutter.yml)

```sh
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub
```

For Node changes, run these commands from `packages/node`. The test script also builds the TypeScript SDK.

```sh
npm ci
npm test
```

When the optional demo's exchange interface changes, run both sets of checks and verify the exchange end to end. [Staging demo setup](README.md#optional-end-to-end-staging-demo)

## Integration boundaries

- Preserve Flutter's authorization-state validation, registered redirect checks, and native callback cleanup. The host backend exchanges the authorization code and owns eligibility, account linking, and app sessions.
- Keep live provider secrets and access tokens on the backend. Use only the UAE PASS public staging credentials in the demos. Use synthetic test fixtures and keep authorization codes, tokens, and profile data out of logs.
- Validate provider responses, keep `uuid` and `sub` distinct, and preserve sanitized, typed errors. Use the exact registered redirect URI and exchange each code once.
- Keep bundled artwork traceable to [the artwork manifest](packages/flutter/assets/button-artwork.json). When changing artwork, run the complete variant matrix in the existing button tests and verify English and Arabic in the demo.

## Documentation and releases

- Document host integration in the relevant SDK README and demo setup in the example README. Use the GitHub repository root for package repository URLs. Set npm's `repository.directory` to `packages/node`.
- When checking release contents, run `flutter pub publish --dry-run` from `packages/flutter` or `npm pack --dry-run` from `packages/node`, as applicable.
- Flutter release tags use `flutter-v<version>` on the merged release commit. Match the tag version to the Flutter pubspec and changelog, and follow the package release checklist. Pushing the tag starts the pub.dev workflow. [Flutter release checks](packages/flutter/README.md#release-checks) · [Publish workflow](.github/workflows/publish-flutter.yml)
- Node release tags use `node-v<version>` on the merged release commit, matching `packages/node/package.json`. Set up `publish-node.yml` as a GitHub Actions Trusted Publisher with direct publish permission on npm before pushing the first Node release tag. [Node publish workflow](.github/workflows/publish-node.yml) · [npm Trusted Publishing](https://docs.npmjs.com/trusted-publishers/)
- Use a locally packed tarball for Node install checks.
