import 'dart:async';

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
  Timer? _splashTimer;
  bool _splashFinished = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _setupNotifications());
    _splashTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _splashFinished = true);
    });
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    super.dispose();
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
      MaterialPageRoute<void>(builder: (_) => QueueScreen(campaign: campaign)),
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
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 450),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: ready && _splashFinished
            ? const AppShell(key: ValueKey('shell'))
            : const _Splash(key: ValueKey('splash')),
      ),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08130F),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.15),
                radius: 0.95,
                colors: [Color(0xFF124A3E), Color(0xFF08130F)],
              ),
            ),
          ),
          Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 850),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.scale(
                    scale: 0.92 + 0.08 * value,
                    child: child,
                  ),
                );
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/splash_logo.png',
                    width: 260,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Envio assistido pelo WhatsApp',
                    style: TextStyle(
                      color: Color(0xFFB9D6CE),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 30),
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Color(0xFF25D366),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
