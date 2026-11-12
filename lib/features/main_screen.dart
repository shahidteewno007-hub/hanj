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
/// Order and icons are exactly what the bottom bar shipped with. The labels
/// are in Title case since question 81, as hanko.html sets them; they were
/// capitals.
class _Destination {
  const _Destination(this.icon, this.selectedIcon, this.label);
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

const List<_Destination> _destinations = [
  _Destination(Icons.home_outlined, Icons.home_rounded, 'Home'),
  _Destination(Icons.explore_outlined, Icons.explore_rounded, 'Discover'),
  _Destination(Icons.bolt_outlined, Icons.bolt_rounded, 'Pulse'),
  _Destination(Icons.format_list_bulleted_rounded,
      Icons.format_list_bulleted_rounded, 'List'),
  _Destination(Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
];

/// The labels' size: 12, as hanko.html sets them (question 81), in place of
/// the theme's 10 and the tracking that capitals need; mixed case needs
/// none. The bottom bar still holds its labels at 1.3x at most, its own
/// limit.
const double _labelSize = 12;

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
    //
    // The page and the bottom bar are each a traversal group (question 156),
    // so Tab walks the whole page before it reaches the bar. In one reading
    // order, a page item lower than the bar's top came after the bar's tabs,
    // and Tab alternated between them.
    final content = FocusTraversalGroup(
      child: OfflineBanner(
        child: PageWidth(child: _screens[_selectedIndex]),
      ),
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
      bottomNavigationBar:
          useRail ? null : FocusTraversalGroup(child: _buildBottomBar()),
    );
  }

  void _select(int i) => setState(() => _selectedIndex = i);

  // Where you are, in Hanko (hanko.html's tab bar): the selected tab in washi
  // with its filled icon, the others in stone. Coral marks only your own
  // verdicts now, so it no longer also says "you are here" (one meaning per
  // colour). The selected label keeps its heavier weight, so List, whose two
  // icons are the same, isn't told apart by colour alone. The size is
  // _labelSize, with no tracking (question 81); everything else the app
  // theme sets for the bar's labels is kept.
  WidgetStateProperty<TextStyle?> _barLabelStyle() {
    final theme = NavigationBarTheme.of(context).labelTextStyle;
    return WidgetStateProperty.resolveWith((states) {
      final style = (theme?.resolve(states) ?? const TextStyle())
          .copyWith(fontSize: _labelSize, letterSpacing: 0);
      if (!states.contains(WidgetState.selected)) return style;
      return style.copyWith(color: AppTheme.hankoWashi);
    });
  }

  Widget _buildRail() {
    // The rail says it the same way. Its labels were washi whether selected
    // or not, so on a wide window only an icon's fill showed where you were,
    // and on List nothing did. Its labels match the bar's: Title case at
    // _labelSize, with no tracking.
    final label = (Theme.of(context).textTheme.labelMedium ?? const TextStyle())
        .copyWith(fontSize: _labelSize, letterSpacing: 0);
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
        selectedIconTheme: const IconThemeData(color: AppTheme.hankoWashi),
        unselectedIconTheme: const IconThemeData(color: AppTheme.hankoStone),
        selectedLabelTextStyle: label.copyWith(
            color: AppTheme.hankoWashi, fontWeight: FontWeight.w600),
        unselectedLabelTextStyle: label.copyWith(color: AppTheme.hankoStone),
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
        labelTextStyle: _barLabelStyle(),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 64,
        destinations: [
          for (final d in _destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon, color: AppTheme.hankoWashi),
              label: d.label,
            ),
        ],
      ),
    );
  }
}
