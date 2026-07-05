import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/api/api_client.dart';
import 'core/api/hinata_repository.dart';
import 'core/notifications/fcm_service.dart';
import 'core/storage/app_storage.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Warm up the Lucide icon module on this shallow call stack. On Flutter web's
  // dev compiler (DDC) the first access to a symbol in this ~1600-icon library
  // triggers a deep `initializeAndLinkLibrary` link step. If that first access
  // happens deep inside the cold widget-mount stack (the login screen's very
  // first Icon, in ServerSelectorButton) the link recursion overflows the JS
  // stack — throwing a StackOverflowError that the widgets error boundary paints
  // as a red box. Linking the module here, before runApp, makes every later
  // access a cheap cache hit. Release builds (dart2js/wasm) have no such lazy
  // linker, so this is a no-op there; the read keeps it from being tree-shaken.
  if (LucideIcons.server.codePoint == 0) debugPrint('lucide warm-up');

  // Firebase (push). Skipped on web — no web Firebase app is configured — and
  // guarded so a misconfiguration never blocks app startup. The background
  // handler must be registered at the top level before runApp.
  if (!kIsWeb) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    } catch (e) {
      debugPrint('Firebase init skipped: $e');
    }
  }

  // Clean path-based URLs on the web (e.g. /invite instead of /#/invite). No-op
  // off the web. Email deep links and SSO callbacks rely on this.
  usePathUrlStrategy();

  HydratedBloc.storage = await HydratedStorage.build(
    storageDirectory: kIsWeb
        ? HydratedStorageDirectory.web
        : HydratedStorageDirectory(
            (await getApplicationDocumentsDirectory()).path),
  );

  // Pre-warm the liquid-glass shaders so the first frame of the bottom nav
  // doesn't flash. Guarded: a failure here must never block app startup.
  try {
    await LiquidGlassWidgets.initialize(enablePerformanceMonitor: false);
  } catch (_) {}

  final storage = await AppStorage.create();
  final apiClient = ApiClient(storage);
  final repository = HinataRepository(apiClient);

  runApp(HinataApp(
    storage: storage,
    apiClient: apiClient,
    repository: repository,
  ));
}
