import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pages/home_page.dart';
import 'services/app_state.dart';
import 'services/tracker_api.dart';
import 'theme/app_theme.dart';
import 'widgets/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load();
  } catch (_) {
    // No .env bundled: the app shows "not configured" instead of crashing.
  }
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  final state = AppState(api: TrackerApi(TrackerConfig.fromEnv()), prefs: await SharedPreferences.getInstance());
  runApp(PhamiTrackerApp(state: state));
}

class PhamiTrackerApp extends StatelessWidget {
  const PhamiTrackerApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: MaterialApp(
        title: 'PhamiTracker',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const HomePage(),
      ),
    );
  }
}
