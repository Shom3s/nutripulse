import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../models/market_item.dart';
import '../../../models/market_order.dart';
import '../../../services/market_service.dart';
import '../../chat/private_chat_screen.dart';
import 'add_market_item_screen.dart';

class SellerOrdersScreen extends StatefulWidget {
  const SellerOrdersScreen({super.key});

  static const Color bg = Color(0xFF0F140D);
  static const Color lime = Color(0xFFD6FF60);
  static const Color card = Color(0xFF1A1F17);
  static const Color card2 = Color(0xFF23291F);
  static const Color soft = Color(0xFFB7C2A8);

  @override
  State<SellerOrdersScreen> createState() => _SellerOrdersScreenState();
}

class _SellerOrdersScreenState extends State<SellerOrdersScreen>
    with AutomaticKeepAliveClientMixin {
  final ValueNotifier<int> _tab = ValueNotifier<int>(0);
  late final Stream<List<MarketItem>> _myItemsStream =
      MarketService.myItemsStream().asBroadcastStream();
  late final Stream<List<MarketOrder>> _sellerOrdersStream =
      MarketService.sellerOrdersStream().asBroadcastStream();

  static const Color bg = SellerOrdersScreen.bg;
  static const Color lime = SellerOrdersScreen.lime;
  static const Color card = SellerOrdersScreen.card;
  static const Color card2 = SellerOrdersScreen.card2;
  static const Color soft = SellerOrdersScreen.soft;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  void _push(Widget screen) {
    FocusScope.of(context).unfocus();
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 210),
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

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      backgroundColor: bg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF263919), bg, Color(0xFF060806)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              RepaintBoundary(child: _header(context)),
              RepaintBoundary(child: _tabs()),
              Expanded(
                child: ValueListenableBuilder<int>(
                  valueListenable: _tab,
                  builder: (context, index, _) {
                    return IndexedStack(
                      index: index,
                      children: [_productsList(), _ordersList()],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 20, 10),
      child: Row(
        children: [
          _circleButton(
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: () => Navigator.pop(context),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Seller Center',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 28,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Edit products and manage COD orders',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: soft,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          _circleButton(
            icon: Icons.add_rounded,
            onTap: () => _push(const AddMarketItemScreen()),
            filled: true,
          ),
        ],
      ),
    );
  }

  Widget _circleButton({
    required IconData icon,
    required VoidCallback onTap,
    bool filled = false,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: filled ? lime : card.withOpacity(0.92),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.07)),
        ),
        child: Icon(
          icon,
          color: filled ? Colors.black : Colors.white,
          size: 19,
        ),
      ),
    );
  }

  Widget _tabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
      child: ValueListenableBuilder<int>(
        valueListenable: _tab,
        builder: (context, index, _) {
          return Container(
            height: 48,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: card.withOpacity(0.92),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Row(
              children: [
                _tabButton(0, 'My Products', Icons.storefront_rounded, index),
                _tabButton(1, 'COD Orders', Icons.receipt_long_rounded, index),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _tabButton(int value, String label, IconData icon, int selected) {
    final active = selected == value;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _tab.value = value,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOutCubic,
          height: 38,
          decoration: BoxDecoration(
            color: active ? lime : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: active ? Colors.black : soft, size: 16),
              const SizedBox(width: 7),
              Text(
                label,
                style: GoogleFonts.outfit(
                  color: active ? Colors.black : soft,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _productsList() {
    return StreamBuilder<List<MarketItem>>(
      stream: _myItemsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return _productSkeleton();
        }

        final items = snapshot.data ?? const <MarketItem>[];
        if (items.isEmpty) {
          return _emptyState(
            icon: Icons.storefront_rounded,
            title: 'No products listed yet',
            subtitle:
                'Post food, fruits, drinks, or snacks. You can update stock, photo, name and price later.',
            actionLabel: 'Sell Food',
            onAction: () => _push(const AddMarketItemScreen()),
          );
        }

        return ListView.builder(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          cacheExtent: 420,
          itemCount: items.length,
          itemBuilder: (context, index) => RepaintBoundary(
            key: ValueKey('seller-product-${items[index].id}'),
            child: _ProductCard(
              item: items[index],
              onEdit: () => _push(AddMarketItemScreen(editItem: items[index])),
              onToggle: () => _toggleItem(items[index]),
              onDelete: () => _confirmDelete(items[index]),
            ),
          ),
        );
      },
    );
  }

  Widget _ordersList() {
    return StreamBuilder<List<MarketOrder>>(
      stream: _sellerOrdersStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return _orderSkeleton();
        }

        final orders = snapshot.data ?? const <MarketOrder>[];
        if (orders.isEmpty) {
          return _emptyState(
            icon: Icons.inventory_2_rounded,
            title: 'No seller orders yet',
            subtitle:
                'When someone orders your food with COD, it will appear here.',
          );
        }

        return ListView.builder(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          cacheExtent: 420,
          itemCount: orders.length,
          itemBuilder: (context, index) => RepaintBoundary(
            key: ValueKey('seller-order-${orders[index].id}'),
            child: _SellerOrderCard(order: orders[index]),
          ),
        );
      },
    );
  }

  Future<void> _toggleItem(MarketItem item) async {
    try {
      await MarketService.toggleItemStatus(item);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not update listing: $e')));
    }
  }

  Future<void> _confirmDelete(MarketItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF151B12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'Delete product?',
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Text(
          'This removes "${item.name}" from NutriMarket. Existing COD orders stay in your order history.',
          style: GoogleFonts.outfit(
            color: soft,
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.outfit(
                color: soft,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Delete',
              style: GoogleFonts.outfit(
                color: Colors.redAccent,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    try {
      await MarketService.deleteItem(item);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not delete listing: $e')));
    }
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                color: lime.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: lime, size: 36),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 21,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                color: soft,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: onAction,
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
                  actionLabel,
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _productSkeleton() {
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      itemCount: 5,
      itemBuilder: (_, index) => Container(
        height: 118,
        margin: const EdgeInsets.only(bottom: 13),
        decoration: BoxDecoration(
          color: card.withOpacity(0.70),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.white.withOpacity(0.04)),
        ),
      ),
    );
  }

  Widget _orderSkeleton() {
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      itemCount: 4,
      itemBuilder: (_, index) => Container(
        height: 154,
        margin: const EdgeInsets.only(bottom: 13),
        decoration: BoxDecoration(
          color: card.withOpacity(0.70),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.white.withOpacity(0.04)),
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.item,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  final MarketItem item;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  static const Color lime = SellerOrdersScreen.lime;
  static const Color card = SellerOrdersScreen.card;
  static const Color soft = SellerOrdersScreen.soft;

  bool get _paused => item.status == 'paused';

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 13),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: card.withOpacity(0.94),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Base64Thumb(base64: item.imageBase64, size: 78, radius: 22),
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
                              fontSize: 16.5,
                              height: 1.05,
                              fontWeight: FontWeight.w900,
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
                    Wrap(
                      spacing: 7,
                      runSpacing: 6,
                      children: [
                        _pill(
                          Icons.inventory_2_rounded,
                          '${item.quantity} stock',
                        ),
                        _pill(Icons.category_rounded, item.category),
                        _pill(Icons.info_rounded, _statusText(item.status)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
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
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Expanded(child: _action(Icons.edit_rounded, 'Edit', onEdit)),
              const SizedBox(width: 9),
              Expanded(
                child: _action(
                  _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  _paused ? 'Resume' : 'Pause',
                  onToggle,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _action(
                  Icons.delete_outline_rounded,
                  'Delete',
                  onDelete,
                  danger: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _pill(IconData icon, String label) {
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              color: Colors.white.withOpacity(0.82),
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  static Widget _action(
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool danger = false,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: danger ? Colors.redAccent.withOpacity(0.12) : lime,
          borderRadius: BorderRadius.circular(15),
          border: danger
              ? Border.all(color: Colors.redAccent.withOpacity(0.25))
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: danger ? Colors.redAccent : Colors.black,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.outfit(
                color: danger ? Colors.redAccent : Colors.black,
                fontSize: 12.3,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _statusText(String status) {
    switch (status) {
      case 'paused':
        return 'Paused';
      case 'sold_out':
        return 'Sold out';
      case 'active':
        return 'Active';
      default:
        return status.isEmpty ? 'Active' : status;
    }
  }
}

class _SellerOrderCard extends StatelessWidget {
  const _SellerOrderCard({required this.order});

  final MarketOrder order;

  static const Color lime = SellerOrdersScreen.lime;
  static const Color card = SellerOrdersScreen.card;
  static const Color soft = SellerOrdersScreen.soft;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 13),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: card.withOpacity(0.94),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _Base64Thumb(base64: order.itemImageBase64, size: 70, radius: 20),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.itemName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 16.5,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 7,
                      runSpacing: 6,
                      children: [
                        _pill(Icons.person_rounded, order.buyerName),
                        _pill(
                          Icons.shopping_bag_rounded,
                          '${order.quantity} item',
                        ),
                        _pill(Icons.info_rounded, _statusText(order.status)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'RM ${order.totalPrice.toStringAsFixed(2)}',
                style: GoogleFonts.outfit(
                  color: lime,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _line(Icons.location_on_rounded, 'Pickup', order.location),
          if (order.note.trim().isNotEmpty)
            _line(Icons.edit_note_rounded, 'Note', order.note),
          const SizedBox(height: 13),
          Row(
            children: [
              Expanded(child: _chatButton(context)),
              const SizedBox(width: 10),
              Expanded(child: _statusMenu(context)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chatButton(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Navigator.of(context).push(
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 300),
            pageBuilder: (_, animation, __) => FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ),
              child: PrivateChatScreen(
                friendUid: order.buyerId,
                friendName: order.buyerName,
                friendPhotoBase64: order.buyerPhotoBase64,
              ),
            ),
          ),
        );
      },
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.055),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.07)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.chat_bubble_rounded, color: lime, size: 17),
            const SizedBox(width: 7),
            Text(
              'Chat Buyer',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 12.8,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusMenu(BuildContext context) {
    return PopupMenuButton<String>(
      color: const Color(0xFF151B12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      onSelected: (value) =>
          MarketService.updateOrderStatus(order: order, status: value),
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'accepted', child: Text('Accept order')),
        PopupMenuItem(value: 'ready', child: Text('Ready for pickup')),
        PopupMenuItem(value: 'completed', child: Text('Completed')),
        PopupMenuItem(value: 'cancelled', child: Text('Cancel')),
      ],
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: lime,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.tune_rounded, color: Colors.black, size: 17),
            const SizedBox(width: 7),
            Text(
              'Update',
              style: GoogleFonts.outfit(
                color: Colors.black,
                fontSize: 12.8,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _pill(IconData icon, String label) {
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              color: Colors.white.withOpacity(0.82),
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  static Widget _line(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: soft.withOpacity(0.72), size: 15),
          const SizedBox(width: 7),
          Text(
            '$label: ',
            style: GoogleFonts.outfit(
              color: soft,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                color: Colors.white.withOpacity(0.84),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _statusText(String status) {
    switch (status) {
      case 'accepted':
        return 'Accepted';
      case 'ready':
        return 'Ready';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return 'Pending';
    }
  }
}

class _Base64Thumb extends StatefulWidget {
  const _Base64Thumb({
    required this.base64,
    required this.size,
    required this.radius,
  });

  final String base64;
  final double size;
  final double radius;

  @override
  State<_Base64Thumb> createState() => _Base64ThumbState();
}

class _Base64ThumbState extends State<_Base64Thumb> {
  static final Map<String, Uint8List?> _cache = <String, Uint8List?>{};
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = _decode(widget.base64);
  }

  @override
  void didUpdateWidget(covariant _Base64Thumb oldWidget) {
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

    if (_cache.length > 36) _cache.remove(_cache.keys.first);
    _cache[key] = decoded;
    return decoded;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.size,
      height: widget.size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: SellerOrdersScreen.card2,
        borderRadius: BorderRadius.circular(widget.radius),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: _bytes == null
          ? const Icon(
              Icons.restaurant_rounded,
              color: SellerOrdersScreen.lime,
              size: 30,
            )
          : Image.memory(
              _bytes!,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.low,
              cacheWidth: 190,
            ),
    );
  }
}
