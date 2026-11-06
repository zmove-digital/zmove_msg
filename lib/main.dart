import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/app_database.dart';
import 'state/app_state.dart';
import 'ui/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState(AppDatabase());
  state.init();
  runApp(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: const ZMoveApp(),
    ),
  );
}
