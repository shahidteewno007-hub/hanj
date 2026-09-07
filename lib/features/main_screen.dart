import 'package:flutter/material.dart';
import '../services/connectivity_service.dart';
import '../core/theme/app_theme.dart';
import '../core/responsive.dart';
import 'home/home_screen.dart';
import 'search/search_screen.dart';
import 'discovery/discovery_screen.dart';
import 'pulse/pulse_screen.dart';
import 'my_list/my_list_screen.dart';
import 'profile/profile_screen.dart';

/// One definition of the five destinations, so the bottom bar and the desktop
/// rail cannot drift into different information architectures (WEB.md §9.4).
/// Order, icons and labels are exactly what the bottom bar shipped with.
class _Destination {
  const _Destination(this.icon, this.selectedIcon, this.label);
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

const List<_Destination> _destinations = [
  _Destination(Icons.home_outlined, Icons.home_rounded, 'HOME'),
  _Destination(Icons.explore_outlined, Icons.explore_rounded, 'DISCOVER'),
  _Destination(Icons.bolt_outlined, Icons.bolt_rounded, 'PULSE'),
  _Destination(Icons.format_list_bulleted_rounded,
      Icons.format_list_bulleted_rounded, 'LIST'),
  _Destination(Icons.person_outline_rounded, Icons.person_rounded, 'PROFILE'),
];

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = const [
    HomeScreen(),
    DiscoveryScreen(),
    PulseScreen(),
    MyListScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    // The rail replaces the bottom bar from 1024 up. A phone never reaches it:
    // the CPH2573 is 360 px wide in portrait and 792 in landscape (WEB.md
    // §9.2), so Android keeps taking the branch it always took — which is why
    // the breakpoint is 1024 and not 600.
    final useRail = Responsive.isDesktop(context);

    // Still no IndexedStack: switching tabs destroys and rebuilds the tab root,
    // and the static caches in Home and Discovery exist to cover exactly that.
    // Indexing _screens here keeps that contract unchanged.
    //
    // PageWidth caps the tab root alone. The rail is its sibling inside the
    // Row, so the rail stays flush to the window edge and full height while the
    // cap applies only to the content beside it — the Row is never wrapped.
    final content = OfflineBanner(
      child: PageWidth(child: _screens[_selectedIndex]),
    );

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: useRail
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildRail(),
                Expanded(child: content),
              ],
            )
          : content,
      bottomNavigationBar: useRail ? null : _buildBottomBar(),
    );
  }

  void _select(int i) => setState(() => _selectedIndex = i);

  Widget _buildRail() {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(right: BorderSide(color: AppTheme.border, width: 1)),
      ),
      child: NavigationRail(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _select,
        backgroundColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        labelType: NavigationRailLabelType.all,
        destinations: [
          for (final d in _destinations)
            NavigationRailDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: Text(d.label),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.border, width: 1)),
      ),
      child: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _select,
        backgroundColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 64,
        destinations: [
          for (final d in _destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
            ),
        ],
      ),
    );
  }
}
