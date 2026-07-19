import 'package:flutter/material.dart';

import '../services/ui_state.dart';
import 'downloads_screen.dart';
import 'home_screen.dart';
import 'library_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final pages = const [
    HomeScreen(),
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
              icon: Icon(Icons.link_outlined),
              selectedIcon: Icon(Icons.link_rounded),
              label: '解析',
            ),
            NavigationDestination(
              icon: Icon(Icons.downloading_outlined),
              selectedIcon: Icon(Icons.downloading_rounded),
              label: '下载',
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
