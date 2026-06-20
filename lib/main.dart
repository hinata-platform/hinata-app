import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/api/api_client.dart';
import 'core/api/hinata_repository.dart';
import 'core/storage/app_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
