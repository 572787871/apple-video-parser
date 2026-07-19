import 'package:flutter/material.dart';

import '../services/ui_state.dart';
import 'browser_screen.dart';
import 'downloads_screen.dart';
import 'library_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final pages = const [
    BrowserScreen(),
    DownloadsScreen(),
    LibraryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final state = UiStateScope.of(context);
    return Scaffold(
      body: AnimatedBuilder(
        animation: state,
        builder: (context, _) =>
            IndexedStack(index: state.selectedTab, children: pages),
      ),
      bottomNavigationBar: AnimatedBuilder(
        animation: state,
        builder: (context, _) => NavigationBar(
          selectedIndex: state.selectedTab,
          onDestinationSelected: state.selectTab,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.web_asset_outlined),
              selectedIcon: Icon(Icons.web_asset_rounded),
              label: '窗口',
            ),
            NavigationDestination(
              icon: Icon(Icons.downloading_outlined),
              selectedIcon: Icon(Icons.downloading_rounded),
              label: '下载中',
            ),
            NavigationDestination(
              icon: Icon(Icons.folder_outlined),
              selectedIcon: Icon(Icons.folder_rounded),
              label: '已下载',
            ),
          ],
        ),
      ),
    );
  }
}
