import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../models/market_item.dart';
import '../../../services/market_service.dart';
import 'add_market_item_screen.dart';
import 'market_item_detail_screen.dart';
import 'my_market_orders_screen.dart';
import 'seller_orders_screen.dart';

class MarketHomeScreen extends StatefulWidget {
  const MarketHomeScreen({super.key, this.asSliver = false});

  final bool asSliver;

  @override
  State<MarketHomeScreen> createState() => _MarketHomeScreenState();
}

class _MarketHomeScreenState extends State<MarketHomeScreen>
    with AutomaticKeepAliveClientMixin {
  static const Color lime = Color(0xFFD6FF60);
  static const Color card = Color(0xFF1A1F17);
  static const Color card2 = Color(0xFF23291F);
  static const Color soft = Color(0xFFB7C2A8);

  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Keep one stable broadcast marketplace stream. This prevents the
  // StreamBuilder from crashing if the tab is rebuilt while returning from
  // detail/order pages. Category and search filters are applied locally for
  // zero extra Firestore queries during UI interaction.
  late final Stream<List<MarketItem>> _itemsStream =
      MarketService.activeItemsStream(category: 'All').asBroadcastStream();

  Timer? _searchDebounce;
  String _selectedCategory = 'All';
  String _searchText = '';

  static const List<_MarketCategory> _categories = [
    _MarketCategory('All', Icons.grid_view_rounded),
    _MarketCategory('Fruits', Icons.eco_rounded),
    _MarketCategory('Homemade', Icons.rice_bowl_rounded),
    _MarketCategory('Protein', Icons.fitness_center_rounded),
    _MarketCategory('Drinks', Icons.local_drink_rounded),
    _MarketCategory('Snacks', Icons.cookie_rounded),
  ];

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _push(Widget screen) {
    FocusScope.of(context).unfocus();
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ),
          child: screen,
        ),
      ),
    );
  }

  void _changeCategory(String value) {
    if (_selectedCategory == value) return;
    FocusScope.of(context).unfocus();
    setState(() => _selectedCategory = value);

    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 360), () {
      final next = value.trim().toLowerCase();
      if (!mounted || next == _searchText) return;
      setState(() => _searchText = next);
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchCtrl.clear();
    FocusScope.of(context).unfocus();
    if (_searchText.isEmpty) return;
    setState(() => _searchText = '');
  }

  List<MarketItem> _filterItems(List<MarketItem> source) {
    final q = _searchText;
    final category = _selectedCategory;

    return source
        .where((item) {
          final text =
              '${item.name} ${item.category} ${item.description} '
                      '${item.location} ${item.healthTag} ${item.sellerName}'
                  .toLowerCase();

          if (q.isNotEmpty && !text.contains(q)) return false;
          if (category == 'All') return true;

          final itemCategory = item.category.toLowerCase();
          final tag = item.healthTag.toLowerCase();

          switch (category) {
            case 'Fruits':
              return itemCategory.contains('fruit') ||
                  tag.contains('fruit') ||
                  text.contains('banana') ||
                  text.contains('apple') ||
                  text.contains('mango') ||
                  text.contains('orange') ||
                  text.contains('grape') ||
                  text.contains('watermelon');
            case 'Homemade':
              return itemCategory.contains('homemade') ||
                  text.contains('home') ||
                  text.contains('meal') ||
                  text.contains('rice') ||
                  text.contains('nasi') ||
                  text.contains('sandwich');
            case 'Protein':
              return itemCategory.contains('fitness') ||
                  itemCategory.contains('protein') ||
                  tag.contains('protein') ||
                  text.contains('egg') ||
                  text.contains('chicken') ||
                  text.contains('tuna') ||
                  text.contains('fish') ||
                  text.contains('protein');
            case 'Drinks':
              return itemCategory.contains('drink') ||
                  text.contains('juice') ||
                  text.contains('milk') ||
                  text.contains('smoothie') ||
                  text.contains('water');
            case 'Snacks':
              return itemCategory.contains('snack') ||
                  text.contains('snack') ||
                  text.contains('bar') ||
                  text.contains('nuts') ||
                  text.contains('biscuit') ||
                  text.contains('cookie');
            default:
              return true;
          }
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final slivers = _marketSlivers();

    if (widget.asSliver) {
      return SliverMainAxisGroup(slivers: slivers);
    }

    return RepaintBoundary(
      child: CustomScrollView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        cacheExtent: 420,
        slivers: slivers,
      ),
    );
  }

  List<Widget> _marketSlivers() {
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
        sliver: SliverList(
          delegate: SliverChildListDelegate.fixed([
            RepaintBoundary(child: _marketHero()),
            const SizedBox(height: 14),
            RepaintBoundary(child: _quickActions()),
            const SizedBox(height: 14),
            RepaintBoundary(child: _searchBar()),
            const SizedBox(height: 12),
            RepaintBoundary(child: _categoryChips()),
            const SizedBox(height: 16),
          ]),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 128),
        sliver: StreamBuilder<List<MarketItem>>(
          stream: _itemsStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return SliverFillRemaining(
                hasScrollBody: false,
                child: _marketError(),
              );
            }

            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return _loadingSliver();
            }

            final items = _filterItems(snapshot.data ?? const <MarketItem>[]);
            if (items.isEmpty) {
              return SliverFillRemaining(
                hasScrollBody: false,
                child: _emptyMarket(),
              );
            }

            return SliverList.builder(
              itemCount: items.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _sectionHeader(items.length);
                }

                final item = items[index - 1];
                return RepaintBoundary(
                  key: ValueKey('market-card-${item.id}'),
                  child: _marketCard(item),
                );
              },
            );
          },
        ),
      ),
    ];
  }

  Widget _marketHero() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Transform.translate(
        offset: Offset(0, 14 * (1 - t)),
        child: Opacity(opacity: t, child: child),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF33521F), Color(0xFF1A2415), Color(0xFF10150E)],
          ),
          border: Border.all(color: lime.withOpacity(0.22)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: lime,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.storefront_rounded,
                    color: Colors.black,
                    size: 31,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'NutriMarket',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 27,
                                height: 0.95,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.8,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _codBadge(),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Text(
                        'Buy and sell healthy food from your community. COD only for safe pickup.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          color: soft.withOpacity(0.82),
                          fontSize: 13.3,
                          height: 1.28,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _heroPill(Icons.verified_user_rounded, 'Verified COD'),
                const SizedBox(width: 9),
                _heroPill(Icons.health_and_safety_rounded, 'Health tags'),
                const SizedBox(width: 9),
                _heroPill(Icons.chat_bubble_rounded, 'Chat seller'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _codBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.24),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.09)),
      ),
      child: Text(
        'COD',
        style: GoogleFonts.outfit(
          color: lime,
          fontSize: 10.8,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _heroPill(IconData icon, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.20),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.07)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: lime, size: 14),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  color: Colors.white.withOpacity(0.86),
                  fontSize: 10.8,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickActions() {
    return Row(
      children: [
        Expanded(
          child: _actionCard(
            icon: Icons.add_business_rounded,
            title: 'Sell Food',
            subtitle: 'Post item',
            onTap: () => _push(const AddMarketItemScreen()),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _actionCard(
            icon: Icons.receipt_long_rounded,
            title: 'My Orders',
            subtitle: 'Buying',
            onTap: () => _push(const MyMarketOrdersScreen()),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _actionCard(
            icon: Icons.inventory_2_rounded,
            title: 'Seller',
            subtitle: 'Products',
            onTap: () => _push(const SellerOrdersScreen()),
          ),
        ),
      ],
    );
  }

  Widget _actionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: card.withOpacity(0.94),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: lime.withOpacity(0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: lime, size: 20),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 13.2,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                color: soft.withOpacity(0.68),
                fontSize: 10.8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchBar() {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: card.withOpacity(0.95),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 15),
          Icon(Icons.search_rounded, color: soft.withOpacity(0.76), size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'Search banana, oats, sandwich...',
                hintStyle: GoogleFonts.outfit(
                  color: soft.withOpacity(0.58),
                  fontWeight: FontWeight.w600,
                ),
              ),
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
            ),
          ),
          AnimatedBuilder(
            animation: _searchCtrl,
            builder: (_, __) {
              if (_searchCtrl.text.isEmpty) return const SizedBox(width: 10);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _clearSearch,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Icon(
                    Icons.close_rounded,
                    color: soft.withOpacity(0.76),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _categoryChips() {
    return SizedBox(
      height: 43,
      child: ListView.separated(
        physics: const BouncingScrollPhysics(),
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 9),
        itemBuilder: (_, index) {
          final item = _categories[index];
          final isSelected = _selectedCategory == item.label;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _changeCategory(item.label),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? lime : card.withOpacity(0.92),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: isSelected ? lime : Colors.white.withOpacity(0.06),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    item.icon,
                    size: 14,
                    color: isSelected ? Colors.black : soft,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    item.label,
                    style: GoogleFonts.outfit(
                      color: isSelected ? Colors.black : soft,
                      fontSize: 12.4,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _sectionHeader(int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedCategory == 'All'
                      ? 'Available near you'
                      : '$_selectedCategory picks',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Fresh community food • COD only',
                  style: GoogleFonts.outfit(
                    color: soft.withOpacity(0.70),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.055),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count items',
              style: GoogleFonts.outfit(
                color: soft,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _marketCard(MarketItem item) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _push(MarketItemDetailScreen(item: item)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 13),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: card.withOpacity(0.95),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MarketImage(base64: item.imageBase64, size: 88, radius: 23),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 17,
                            height: 1.05,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.25,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'RM ${item.price.toStringAsFixed(2)}',
                        style: GoogleFonts.outfit(
                          color: lime,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    'by ${item.sellerName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      color: soft.withOpacity(0.64),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 7,
                    runSpacing: 6,
                    children: [
                      _smallPill(Icons.payments_rounded, 'COD'),
                      _smallPill(
                        Icons.inventory_2_rounded,
                        '${item.quantity} left',
                      ),
                      _smallPill(Icons.category_rounded, item.category),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Icon(
                              Icons.location_on_rounded,
                              color: soft.withOpacity(0.62),
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                item.location,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                  color: soft.withOpacity(0.72),
                                  fontSize: 12.2,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _healthTag(item.healthTag),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: lime,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'View',
                        style: GoogleFonts.outfit(
                          color: Colors.black,
                          fontSize: 11.8,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _healthTag(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: lime.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.outfit(
          color: lime,
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _smallPill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.055),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: lime, size: 11),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.outfit(
              color: Colors.white.withOpacity(0.80),
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _loadingSliver() {
    return SliverList.builder(
      itemCount: 5,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Expanded(child: _skeletonBox(height: 18, radius: 999)),
                const SizedBox(width: 80),
                _skeletonBox(width: 70, height: 18, radius: 999),
              ],
            ),
          );
        }
        return const _MarketSkeletonCard();
      },
    );
  }

  Widget _skeletonBox({
    double? width,
    required double height,
    required double radius,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.055),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  Widget _marketError() {
    return Center(
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
        decoration: BoxDecoration(
          color: card.withOpacity(0.92),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.wifi_off_rounded,
                color: Colors.redAccent,
                size: 32,
              ),
            ),
            const SizedBox(height: 15),
            Text(
              'Market could not load',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Check your Firebase rules or internet connection, then pull down to refresh.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                color: soft,
                fontSize: 12.8,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyMarket() {
    return Center(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(22, 30, 22, 30),
        decoration: BoxDecoration(
          color: card.withOpacity(0.90),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                color: lime.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shopping_bag_rounded,
                color: lime,
                size: 34,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _searchText.isEmpty
                  ? 'No market items yet'
                  : 'No matching food found',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _searchText.isEmpty
                  ? 'Be the first to sell fruits, homemade food, drinks, or fitness snacks.'
                  : 'Try another food name or switch to All category.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                color: soft,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: () => _push(const AddMarketItemScreen()),
              style: ElevatedButton.styleFrom(
                backgroundColor: lime,
                foregroundColor: Colors.black,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 13,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              icon: const Icon(Icons.add_rounded),
              label: Text(
                'Sell Food',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarketCategory {
  const _MarketCategory(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _MarketSkeletonCard extends StatelessWidget {
  const _MarketSkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 13),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: _MarketHomeScreenState.card.withOpacity(0.70),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withOpacity(0.04)),
      ),
      child: Row(
        children: [
          _box(88, 88, 23),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _box(double.infinity, 15, 999),
                const SizedBox(height: 10),
                _box(150, 12, 999),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _box(54, 22, 999),
                    const SizedBox(width: 7),
                    _box(72, 22, 999),
                    const SizedBox(width: 7),
                    _box(62, 22, 999),
                  ],
                ),
                const SizedBox(height: 12),
                _box(double.infinity, 12, 999),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _box(double width, double height, double radius) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.055),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _MarketImage extends StatefulWidget {
  const _MarketImage({
    required this.base64,
    required this.size,
    required this.radius,
  });

  final String base64;
  final double size;
  final double radius;

  @override
  State<_MarketImage> createState() => _MarketImageState();
}

class _MarketImageState extends State<_MarketImage> {
  static final Map<String, Uint8List?> _cache = <String, Uint8List?>{};
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = _decode(widget.base64);
  }

  @override
  void didUpdateWidget(covariant _MarketImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.base64 != widget.base64) {
      _bytes = _decode(widget.base64);
    }
  }

  Uint8List? _decode(String value) {
    if (value.isEmpty) return null;
    final key = '${value.length}_${value.hashCode}';
    if (_cache.containsKey(key)) return _cache[key];

    Uint8List? decoded;
    try {
      decoded = base64Decode(value);
    } catch (_) {
      decoded = null;
    }

    if (_cache.length > 42) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = decoded;
    return decoded;
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        width: widget.size,
        height: widget.size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: _MarketHomeScreenState.card2,
          borderRadius: BorderRadius.circular(widget.radius),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: _bytes == null
            ? const Icon(
                Icons.restaurant_rounded,
                color: _MarketHomeScreenState.lime,
                size: 34,
              )
            : Image.memory(
                _bytes!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                filterQuality: FilterQuality.low,
                cacheWidth: 220,
              ),
      ),
    );
  }
}
