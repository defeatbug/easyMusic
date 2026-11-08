import 'package:flutter/material.dart';

import 'sidebar.dart';
import 'theme.dart';

class _Tab {
  const _Tab(this.page, this.icon, this.activeIcon, this.label);

  final AppPage page;
  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// The phone layout's five destinations, picked from the sidebar's pages:
/// the ones a phone listener reaches for most. Daily recommendations,
/// charts, saved albums, FM and podcasts stay reachable from the home
/// page's own cards, as they are on desktop.
const _tabs = <_Tab>[
  _Tab(AppPage.home, Icons.home_outlined, Icons.home, '发现'),
  _Tab(AppPage.search, Icons.search, Icons.search, '搜索'),
  _Tab(AppPage.liked, Icons.favorite_border, Icons.favorite, '喜欢'),
  _Tab(AppPage.local, Icons.folder_outlined, Icons.folder, '本地'),
  _Tab(AppPage.settings, Icons.person_outline, Icons.person, '我的'),
];

/// The bottom tab bar of the phone layout (Material 3 [NavigationBar]).
/// It reads and writes the same page state as the desktop sidebar, so
/// switching layouts never loses the listener's place.
class MobileTabBar extends StatelessWidget {
  const MobileTabBar({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  final AppPage selected;
  final void Function(AppPage page) onSelect;

  @override
  Widget build(BuildContext context) {
    var index = _tabs.indexWhere((t) => t.page == selected);
    // Pages that are not tabs themselves (daily, charts, …) are opened
    // from the home page's cards, so they keep 发现 lit.
    if (index < 0) index = 0;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Palette.bg,
        border: Border(top: BorderSide(color: Palette.hairline)),
      ),
      child: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => onSelect(_tabs[i].page),
        backgroundColor: Palette.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 62,
        indicatorColor: Palette.accent.withValues(alpha: 0.12),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          for (final t in _tabs)
            NavigationDestination(
              icon: Icon(t.icon),
              selectedIcon: Icon(t.activeIcon, color: Palette.accent),
              label: t.label,
            ),
        ],
      ),
    );
  }
}
