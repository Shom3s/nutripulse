import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../models/market_order.dart';
import '../../../services/market_service.dart';
import '../../chat/private_chat_screen.dart';

class MyMarketOrdersScreen extends StatefulWidget {
  const MyMarketOrdersScreen({super.key});

  static const Color bg = Color(0xFF0F140D);
  static const Color lime = Color(0xFFD6FF60);
  static const Color card = Color(0xFF1A1F17);
  static const Color card2 = Color(0xFF23291F);
  static const Color soft = Color(0xFFB7C2A8);

  @override
  State<MyMarketOrdersScreen> createState() => _MyMarketOrdersScreenState();
}

class _MyMarketOrdersScreenState extends State<MyMarketOrdersScreen>
    with AutomaticKeepAliveClientMixin {
  late final Stream<List<MarketOrder>> _ordersStream =
      MarketService.buyerOrdersStream().asBroadcastStream();

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      backgroundColor: MyMarketOrdersScreen.bg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF263919),
              MyMarketOrdersScreen.bg,
              Color(0xFF060806),
            ],
          ),
        ),
        child: SafeArea(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            cacheExtent: 420,
            slivers: [
              SliverToBoxAdapter(
                child: RepaintBoundary(child: _header(context)),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                sliver: StreamBuilder<List<MarketOrder>>(
                  stream: _ordersStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        !snapshot.hasData) {
                      return const _OrdersLoadingSliver();
                    }

                    final orders = snapshot.data ?? const <MarketOrder>[];
                    if (orders.isEmpty) {
                      return SliverFillRemaining(
                        hasScrollBody: false,
                        child: _emptyState(
                          'No COD orders yet',
                          'Orders you place in NutriMarket will appear here.',
                          Icons.receipt_long_rounded,
                        ),
                      );
                    }

                    return SliverList.builder(
                      itemCount: orders.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return _summaryCard(orders);
                        }
                        final order = orders[index - 1];
                        return RepaintBoundary(
                          key: ValueKey('buyer-order-${order.id}'),
                          child: _OrderCard(order: order, buyerView: true),
                        );
                      },
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
            context,
            Icons.arrow_back_ios_new_rounded,
            () => Navigator.pop(context),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'My Orders',
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
                  'Track your COD buying requests',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: MyMarketOrdersScreen.soft.withOpacity(0.72),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(List<MarketOrder> orders) {
    final active = orders
        .where((o) => o.status != 'cancelled' && o.status != 'completed')
        .length;
    final completed = orders.where((o) => o.status == 'completed').length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
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
          border: Border.all(
            color: MyMarketOrdersScreen.lime.withOpacity(0.22),
          ),
        ),
        child: Row(
          children: [
            _summaryTile(
              Icons.receipt_long_rounded,
              '${orders.length}',
              'Total',
            ),
            const SizedBox(width: 10),
            _summaryTile(Icons.timelapse_rounded, '$active', 'Active'),
            const SizedBox(width: 10),
            _summaryTile(Icons.check_circle_rounded, '$completed', 'Done'),
          ],
        ),
      ),
    );
  }

  Widget _summaryTile(IconData icon, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.18),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.07)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: MyMarketOrdersScreen.lime, size: 18),
            const SizedBox(height: 8),
            Text(
              value,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              label,
              style: GoogleFonts.outfit(
                color: MyMarketOrdersScreen.soft.withOpacity(0.72),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(String title, String subtitle, IconData icon) {
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
                color: MyMarketOrdersScreen.lime.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: MyMarketOrdersScreen.lime, size: 36),
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
                color: MyMarketOrdersScreen.soft,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleButton(
    BuildContext context,
    IconData icon,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: MyMarketOrdersScreen.card.withOpacity(0.92),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.07)),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.buyerView});

  final MarketOrder order;
  final bool buyerView;

  static const Color lime = MyMarketOrdersScreen.lime;
  static const Color card = MyMarketOrdersScreen.card;
  static const Color card2 = MyMarketOrdersScreen.card2;
  static const Color soft = MyMarketOrdersScreen.soft;

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
              _OrderImage(base64: order.itemImageBase64),
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
                        _pill(Icons.payments_rounded, 'COD'),
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
          _line(
            Icons.person_rounded,
            buyerView ? 'Seller' : 'Buyer',
            buyerView ? order.sellerName : order.buyerName,
          ),
          _line(Icons.location_on_rounded, 'Pickup', order.location),
          if (order.note.trim().isNotEmpty)
            _line(Icons.edit_note_rounded, 'Note', order.note),
          const SizedBox(height: 13),
          Row(
            children: [
              Expanded(
                child: _outlineButton(
                  icon: Icons.chat_bubble_rounded,
                  label: buyerView ? 'Chat Seller' : 'Chat Buyer',
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
                            friendUid: buyerView
                                ? order.sellerId
                                : order.buyerId,
                            friendName: buyerView
                                ? order.sellerName
                                : order.buyerName,
                            friendPhotoBase64: buyerView
                                ? order.sellerPhotoBase64
                                : order.buyerPhotoBase64,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (buyerView &&
                  order.status != 'cancelled' &&
                  order.status != 'completed') ...[
                const SizedBox(width: 10),
                Expanded(
                  child: _outlineButton(
                    icon: Icons.cancel_rounded,
                    label: 'Cancel',
                    onTap: () => MarketService.updateOrderStatus(
                      order: order,
                      status: 'cancelled',
                    ),
                  ),
                ),
              ],
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
        children: [
          Icon(icon, color: lime, size: 15),
          const SizedBox(width: 7),
          Text(
            '$label: ',
            style: GoogleFonts.outfit(
              color: Colors.white.withOpacity(0.84),
              fontSize: 12.4,
              fontWeight: FontWeight.w900,
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                color: soft,
                fontSize: 12.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _outlineButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.055),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: lime, size: 17),
            const SizedBox(width: 7),
            Text(
              label,
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

  static String _statusText(String value) {
    switch (value) {
      case 'pending':
        return 'Pending';
      case 'accepted':
        return 'Accepted';
      case 'ready':
        return 'Ready';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return value.isEmpty ? 'Pending' : value;
    }
  }
}

class _OrderImage extends StatefulWidget {
  const _OrderImage({required this.base64});

  final String base64;

  @override
  State<_OrderImage> createState() => _OrderImageState();
}

class _OrderImageState extends State<_OrderImage> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = _decode(widget.base64);
  }

  @override
  void didUpdateWidget(covariant _OrderImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.base64 != widget.base64) _bytes = _decode(widget.base64);
  }

  Uint8List? _decode(String value) {
    if (value.isEmpty) return null;
    try {
      return base64Decode(value);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 70,
      height: 70,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: MyMarketOrdersScreen.card2,
        borderRadius: BorderRadius.circular(20),
      ),
      child: _bytes == null
          ? const Icon(
              Icons.restaurant_rounded,
              color: MyMarketOrdersScreen.lime,
              size: 30,
            )
          : Image.memory(
              _bytes!,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.low,
              cacheWidth: 180,
              gaplessPlayback: true,
            ),
    );
  }
}

class _OrdersLoadingSliver extends StatelessWidget {
  const _OrdersLoadingSliver();

  @override
  Widget build(BuildContext context) {
    return SliverList.builder(
      itemCount: 4,
      itemBuilder: (context, index) => Container(
        margin: const EdgeInsets.only(bottom: 13),
        height: index == 0 ? 120 : 118,
        decoration: BoxDecoration(
          color: MyMarketOrdersScreen.card.withOpacity(0.70),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.white.withOpacity(0.04)),
        ),
      ),
    );
  }
}
