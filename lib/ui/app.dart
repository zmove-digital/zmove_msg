import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../services/notification_service.dart';
import '../state/app_state.dart';
import 'campaign/queue_screen.dart';
import 'shell.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

class ZMoveApp extends StatefulWidget {
  const ZMoveApp({super.key});

  @override
  State<ZMoveApp> createState() => _ZMoveAppState();
}

class _ZMoveAppState extends State<ZMoveApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _setupNotifications());
  }

  Future<void> _setupNotifications() async {
    final pending = await NotificationService.init(onOpen: _openCampaign);
    if (pending != null) _openCampaign(pending);
  }

  void _openCampaign(int campaignId) {
    if (!mounted) return;
    final state = context.read<AppState>();
    final campaign = state.campaignById(campaignId);
    if (campaign == null) return;
    rootNavigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => QueueScreen(campaign: campaign),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ready = context.select<AppState, bool>((s) => s.ready);

    return MaterialApp(
      title: 'ZMove Msg',
      debugShowCheckedModeBanner: false,
      navigatorKey: rootNavigatorKey,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: ready ? const AppShell() : const _Splash(),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.chat_bubble_rounded,
                color: Colors.white,
                size: 42,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'ZMove Msg',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.6,
                color: colors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
