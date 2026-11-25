# UAE PASS SDKs

Use either SDK independently to integrate UAE PASS sign-in.

## SDKs

| SDK | Supported platforms | Get started |
| --- | --- | --- |
| Flutter | Android, iOS, Web | [Integration guide](packages/flutter/README.md) · [Example app](packages/flutter/example/README.md) |
| Node.js | Backend, Node.js 22+ | [Integration guide](packages/node/README.md) |

## Optional end-to-end staging demo

Run the Flutter example with the Node staging server from the same repository checkout to test authorization, code exchange, and profile retrieval together.

1. Start the sample server from `packages/node`. Set its `UAEPASS_REDIRECT_URI` to `http://localhost:8000` for local web or `https://localhost:8000` for the default mobile demo. [Staging server setup](packages/node/README.md#optional-staging-server)
2. From `packages/flutter/example`, run `flutter pub get`, then run the command below. For Android or iOS, use `flutter run --dart-define=UAEPASS_LOCAL_BACKEND=true` and follow the device networking steps. [Flutter demo backend setup](packages/flutter/example/README.md#optional-backend-exchange)

   ```sh
   flutter run -d chrome --dart-define=UAEPASS_WEB_REDIRECT_URI=http://localhost:8000 --dart-define=UAEPASS_LOCAL_BACKEND=true
   ```

Select **Try sign-in** and approve in the UAE PASS staging app. **Backend exchange complete** confirms that the server exchanged the code and fetched the profile.

## Development

See each package’s instructions for local tests and release checks. [Flutter checks](packages/flutter/README.md#development) · [Node.js checks](packages/node/README.md#development-checks)
