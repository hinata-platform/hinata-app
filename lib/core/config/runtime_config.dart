/// Runtime server resolution (no baked-in backend).
///
/// The shipped image/app bakes **no** backend. The hosted **web** build resolves
/// its default backend at *runtime* from a `window.hinataDefaultServer` global —
/// injected by `config.js`, which the Docker entrypoint regenerates from the
/// `HINATA_DEFAULT_SERVER` container env on every container start. The operator
/// therefore sets the backend purely at deployment, never at build time.
///
/// Native builds (and any platform without JS interop) always return '' so a
/// fresh install asks for the server URL on first launch.
library;

import 'runtime_config_stub.dart'
    if (dart.library.js_interop) 'runtime_config_web.dart';

String get runtimeDefaultServer => readRuntimeDefaultServer();
