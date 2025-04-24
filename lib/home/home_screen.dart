import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_triple/flutter_triple.dart';
import 'package:pref/pref.dart';
import 'package:provider/provider.dart';
import 'package:quacker/constants.dart';
import 'package:quacker/generated/l10n.dart';
import 'package:quacker/group/group_screen.dart';
import 'package:quacker/home/_feed.dart';
import 'package:quacker/home/_missing.dart';
import 'package:quacker/home/_saved.dart';
import 'package:quacker/home/home_model.dart';
import 'package:quacker/search/search.dart';
import 'package:quacker/subscriptions/subscriptions.dart';
import 'package:quacker/trends/trends_screen.dart';
import 'package:quacker/ui/errors.dart';

typedef NavigationTitleBuilder = String Function(BuildContext context);

class NavigationPage {
  final String id;
  final NavigationTitleBuilder titleBuilder;
  final Widget icon;
  final Widget selectedIcon;

  NavigationPage(this.id, this.titleBuilder, this.icon, this.selectedIcon);
}

List<Widget> createCommonAppBarActions(BuildContext context) {
  return [
    IconButton(
      icon: const Icon(Icons.search),
      onPressed: () => Navigator.pushNamed(context, routeSearch, arguments: SearchArguments(0, focusInputOnOpen: true)),
    ),
    IconButton(
      icon: const Icon(Icons.settings),
      onPressed: () => Navigator.pushNamed(context, routeSettings),
    )
  ];
}

final List<NavigationPage> defaultHomePages = [
  NavigationPage('feed', (c) => L10n.of(c).feed, const Icon(Icons.rss_feed), const Icon(Icons.rss_feed)),
  NavigationPage('subscriptions', (c) => L10n.of(c).subscriptions, const Icon(Icons.subscriptions_outlined),
      const Icon(Icons.subscriptions)),
  NavigationPage('trending', (c) => L10n.of(c).trending, const Icon(Icons.trending_up), const Icon(Icons.trending_up)),
  NavigationPage(
      'saved', (c) => L10n.of(c).saved, const Icon(Icons.bookmark_border_outlined), const Icon(Icons.bookmark)),
];

class HomeScreen extends StatelessWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var prefs = PrefService.of(context);
    var model = context.read<HomeModel>();

    return _HomeScreen(prefs: prefs, model: model);
  }
}

class _HomeScreen extends StatefulWidget {
  final BasePrefService prefs;
  final HomeModel model;

  const _HomeScreen({Key? key, required this.prefs, required this.model}) : super(key: key);

  @override
  State<_HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<_HomeScreen> {
  int _initialPage = 0;
  List<NavigationPage> _pages = [];

  @override
  void initState() {
    super.initState();

    _buildPages(widget.model.state);
    widget.model.observer(onState: _buildPages);
  }

  void _buildPages(List<HomePage> state) {
    var pages = state.where((element) => element.selected).map((e) => e.page).toList();

    if (widget.prefs.getKeys().contains(optionHomeInitialTab)) {
      _initialPage = max(0, pages.indexWhere((element) => element.id == widget.prefs.get(optionHomeInitialTab)));
    }

    setState(() {
      _pages = pages;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ScopedBuilder<HomeModel, List<HomePage>>.transition(
      store: widget.model,
      onError: (_, e) => ScaffoldErrorWidget(
        prefix: L10n.current.unable_to_load_home_pages,
        error: e,
        stackTrace: null,
        onRetry: () async => await widget.model.resetPages(),
        retryText: L10n.current.reset_home_pages,
      ),
      onLoading: (_) => const Center(child: CircularProgressIndicator()),
      onState: (_, state) {
        return ScaffoldWithBottomNavigation(
          pages: _pages,
          prefs: widget.prefs,
          initialPage: _initialPage,
          builder: (scrollControllers) {
            return List.generate(_pages.length, (index) {
              final page = _pages[index];
              if (page.id.startsWith('group-')) {
                return SubscriptionGroupScreen(
                  scrollController: scrollControllers[index]!,
                  id: page.id.replaceAll('group-', ''),
                  actions: createCommonAppBarActions(context),
                  name: '',
                );
              }
              switch (page.id) {
                case 'feed':
                  return FeedScreen(
                    scrollController: scrollControllers[index]!,
                    id: '-1',
                    name: L10n.current.feed,
                  );
                case 'subscriptions':
                  return SubscriptionsScreen(
                    scrollController: scrollControllers[index]!,
                  );
                case 'trending':
                  return TrendsScreen(
                    scrollController: scrollControllers[index]!,
                  );
                case 'saved':
                  return SavedScreen(
                    scrollController: scrollControllers[index]!,
                  );
                default:
                  return const MissingScreen();
              }
            });
          },
        );
      },
    );
  }
}

class ScaffoldWithBottomNavigation extends StatefulWidget {
  final List<NavigationPage> pages;
  final BasePrefService prefs;
  final int initialPage;
  final List<Widget> Function(Map<int, ScrollController> scrollControllers) builder; // changed here

  const ScaffoldWithBottomNavigation(
      {Key? key, required this.pages, required this.prefs, required this.initialPage, required this.builder})
      : super(key: key);

  @override
  State<ScaffoldWithBottomNavigation> createState() => _ScaffoldWithBottomNavigationState();
}

class _ScaffoldWithBottomNavigationState extends State<ScaffoldWithBottomNavigation> {
  late PageController _pageController;
  late int _currentPage;
  final Map<int, ScrollController> _scrollControllers = {};

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;
    _pageController = PageController(initialPage: widget.initialPage);
    for (int i = 0; i < widget.pages.length; i++) {
      _scrollControllers[i] = ScrollController();
    }
  }

  @override
  void didUpdateWidget(covariant ScaffoldWithBottomNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pages.length != oldWidget.pages.length) {
      // Dispose controllers that are no longer needed.
      _scrollControllers.keys.where((k) => k >= widget.pages.length).toList().forEach((k) {
        _scrollControllers[k]?.dispose();
        _scrollControllers.remove(k);
      });
      // Create controllers for new pages.
      for (int i = 0; i < widget.pages.length; i++) {
        if (!_scrollControllers.containsKey(i)) {
          _scrollControllers[i] = ScrollController();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: (page) {
          setState(() {
            _currentPage = page;
          });
        },
        children: widget.builder(_scrollControllers),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentPage,
        labelBehavior: widget.prefs.get(optionShowNavigationLabels)
            ? NavigationDestinationLabelBehavior.alwaysShow
            : NavigationDestinationLabelBehavior.alwaysHide,
        destinations: widget.pages
            .map(
              (e) => NavigationDestination(
                icon: e.icon,
                selectedIcon: e.selectedIcon,
                label: e.titleBuilder(context),
              ),
            )
            .toList(),
        onDestinationSelected: (index) {
          _pageController.jumpToPage(index);
        },
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final controller in _scrollControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }
}
