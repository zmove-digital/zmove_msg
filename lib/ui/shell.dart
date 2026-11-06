import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'campaign/campaigns_screen.dart';
import 'contacts/contacts_screen.dart';
import 'home/home_screen.dart';
import 'settings/settings_screen.dart';
import 'templates/templates_screen.dart';

class ShellScope extends InheritedWidget {
  const ShellScope({
    super.key,
    required this.goToTab,
    required super.child,
  });

  final void Function(int index) goToTab;

  static ShellScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ShellScope>();
    assert(scope != null, 'ShellScope não encontrado');
    return scope!;
  }

  @override
  bool updateShouldNotify(ShellScope oldWidget) => false;
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _screens = <Widget>[
    HomeScreen(),
    ContactsScreen(),
    TemplatesScreen(),
    CampaignsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final pending = context.select<AppState, int>((s) {
      var total = 0;
      for (final stat in s.campaignStats.values) {
        total += stat.pending;
      }
      return total;
    });

    return ShellScope(
      goToTab: (index) => setState(() => _index = index),
      child: PopScope(
        canPop: _index == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _index != 0) {
            setState(() => _index = 0);
          }
        },
        child: Scaffold(
          body: IndexedStack(index: _index, children: _screens),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (index) => setState(() => _index = index),
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Início',
              ),
              const NavigationDestination(
                icon: Icon(Icons.people_outline),
                selectedIcon: Icon(Icons.people_rounded),
                label: 'Contatos',
              ),
              const NavigationDestination(
                icon: Icon(Icons.description_outlined),
                selectedIcon: Icon(Icons.description_rounded),
                label: 'Modelos',
              ),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: pending > 0,
                  label: Text('$pending'),
                  child: const Icon(Icons.send_outlined),
                ),
                selectedIcon: Badge(
                  isLabelVisible: pending > 0,
                  label: Text('$pending'),
                  child: const Icon(Icons.send_rounded),
                ),
                label: 'Envios',
              ),
              const NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings_rounded),
                label: 'Ajustes',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
