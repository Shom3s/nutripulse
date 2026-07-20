import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/market_item.dart';
import '../models/market_order.dart';
import 'notification_service.dart';

class MarketService {
  MarketService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static String get currentUid {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not logged in');
    return user.uid;
  }

  static CollectionReference<Map<String, dynamic>> get _items =>
      _db.collection('market_items');

  static CollectionReference<Map<String, dynamic>> get _orders =>
      _db.collection('market_orders');

  static Future<Map<String, String>> _currentUserProfile() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not logged in');

    String name = user.displayName ?? 'NutriPulse User';
    String photoBase64 = '';

    try {
      final doc = await _db.collection('users').doc(user.uid).get();
      final data = doc.data() ?? {};
      final savedName = (data['name'] ?? data['username'] ?? '')
          .toString()
          .trim();
      if (savedName.isNotEmpty) name = savedName;
      photoBase64 = (data['photoBase64'] ?? data['userImageBase64'] ?? '')
          .toString();
    } catch (_) {}

    return {'uid': user.uid, 'name': name, 'photoBase64': photoBase64};
  }

  static Stream<List<MarketItem>> activeItemsStream({String category = 'All'}) {
    // Read newest marketplace items with a simple orderBy, then filter in app.
    // This avoids Firestore composite-index errors during presentation/demo.
    return _items
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snap) {
          final items = snap.docs
              .map(MarketItem.fromFirestore)
              .where((item) => item.status == 'active' && item.quantity > 0)
              .where((item) => category == 'All' || item.category == category)
              .toList();
          items.sort((a, b) {
            final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
            final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
            return bt.compareTo(at);
          });
          return items;
        });
  }

  static Stream<List<MarketItem>> myItemsStream() {
    return _items
        .where('sellerId', isEqualTo: currentUid)
        .limit(80)
        .snapshots()
        .map((snap) {
          final items = snap.docs.map(MarketItem.fromFirestore).toList();
          items.sort(
            (a, b) => (b.createdAt?.millisecondsSinceEpoch ?? 0).compareTo(
              a.createdAt?.millisecondsSinceEpoch ?? 0,
            ),
          );
          return items;
        });
  }

  static Stream<List<MarketOrder>> buyerOrdersStream() {
    return _orders
        .where('buyerId', isEqualTo: currentUid)
        .limit(80)
        .snapshots()
        .map((snap) {
          final orders = snap.docs.map(MarketOrder.fromFirestore).toList();
          orders.sort(
            (a, b) => (b.createdAt?.millisecondsSinceEpoch ?? 0).compareTo(
              a.createdAt?.millisecondsSinceEpoch ?? 0,
            ),
          );
          return orders;
        });
  }

  static Stream<List<MarketOrder>> sellerOrdersStream() {
    return _orders
        .where('sellerId', isEqualTo: currentUid)
        .limit(80)
        .snapshots()
        .map((snap) {
          final orders = snap.docs.map(MarketOrder.fromFirestore).toList();
          orders.sort(
            (a, b) => (b.createdAt?.millisecondsSinceEpoch ?? 0).compareTo(
              a.createdAt?.millisecondsSinceEpoch ?? 0,
            ),
          );
          return orders;
        });
  }

  static Future<String> imageFileToBase64(File file) async {
    final bytes = await file.readAsBytes();
    return base64Encode(bytes);
  }

  static String healthTagFor({
    required String name,
    required String category,
    required String description,
  }) {
    final text = '$name $category $description'.toLowerCase();

    if (text.contains('banana') ||
        text.contains('fruit') ||
        text.contains('mango') ||
        text.contains('apple') ||
        text.contains('orange') ||
        text.contains('grape') ||
        text.contains('watermelon')) {
      return 'Fruit Energy';
    }
    if (text.contains('egg') ||
        text.contains('chicken') ||
        text.contains('tuna') ||
        text.contains('protein') ||
        text.contains('fish')) {
      return 'High Protein';
    }
    if (text.contains('oat') ||
        text.contains('salad') ||
        text.contains('yogurt') ||
        text.contains('low sugar')) {
      return 'Healthy Choice';
    }
    if (text.contains('juice') ||
        text.contains('smoothie') ||
        text.contains('water') ||
        text.contains('drink')) {
      return 'Hydration';
    }
    return 'Community Food';
  }

  static Future<void> createItem({
    required String name,
    required String description,
    required String category,
    required double price,
    required int quantity,
    required String location,
    String expiryDate = '',
    String imageBase64 = '',
  }) async {
    final profile = await _currentUserProfile();
    final cleanName = name.trim();
    final cleanDescription = description.trim();
    final cleanCategory = category.trim().isEmpty ? 'Food' : category.trim();

    if (cleanName.isEmpty) throw Exception('Food name is required');
    if (price <= 0) throw Exception('Price must be more than RM0');
    if (quantity <= 0) throw Exception('Quantity must be at least 1');
    if (location.trim().isEmpty) throw Exception('COD location is required');

    final item = MarketItem(
      id: '',
      sellerId: profile['uid']!,
      sellerName: profile['name']!,
      sellerPhotoBase64: profile['photoBase64']!,
      name: cleanName,
      description: cleanDescription,
      category: cleanCategory,
      price: price,
      quantity: quantity,
      location: location.trim(),
      healthTag: healthTagFor(
        name: cleanName,
        category: cleanCategory,
        description: cleanDescription,
      ),
      imageBase64: imageBase64,
      expiryDate: expiryDate,
    );

    await _items.add(item.toCreateMap());
  }

  static Future<void> updateItem({
    required MarketItem item,
    required String name,
    required String description,
    required String category,
    required double price,
    required int quantity,
    required String location,
    String expiryDate = '',
    String imageBase64 = '',
  }) async {
    if (item.sellerId != currentUid)
      throw Exception('Only seller can edit this listing');

    final cleanName = name.trim();
    final cleanDescription = description.trim();
    final cleanCategory = category.trim().isEmpty ? 'Food' : category.trim();
    final cleanLocation = location.trim();

    if (cleanName.isEmpty) throw Exception('Food name is required');
    if (price <= 0) throw Exception('Price must be more than RM0');
    if (quantity < 0) throw Exception('Quantity cannot be negative');
    if (cleanLocation.isEmpty) throw Exception('COD location is required');

    final nextStatus = item.status == 'paused'
        ? 'paused'
        : (quantity > 0 ? 'active' : 'sold_out');

    await _items.doc(item.id).set({
      'name': cleanName,
      'description': cleanDescription,
      'category': cleanCategory,
      'price': price,
      'quantity': quantity,
      'location': cleanLocation,
      'healthTag': healthTagFor(
        name: cleanName,
        category: cleanCategory,
        description: cleanDescription,
      ),
      'imageBase64': imageBase64,
      'expiryDate': expiryDate.trim(),
      'status': nextStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<String> createOrder({
    required MarketItem item,
    required int quantity,
    String note = '',
  }) async {
    if (item.sellerId == currentUid) {
      throw Exception('You cannot order your own food listing');
    }
    if (quantity <= 0) throw Exception('Quantity must be at least 1');

    final buyer = await _currentUserProfile();
    final itemRef = _items.doc(item.id);
    final orderRef = _orders.doc();

    await _db.runTransaction((transaction) async {
      final itemSnap = await transaction.get(itemRef);
      final itemData = itemSnap.data();
      if (itemData == null) throw Exception('Food listing no longer exists');

      final available = _safeInt(itemData['quantity']);
      final status = (itemData['status'] ?? 'active').toString();
      if (status != 'active')
        throw Exception('This food listing is not active');
      if (available < quantity)
        throw Exception('Only $available left in stock');

      final unitPrice = _safeDouble(itemData['price']);
      final totalPrice = unitPrice * quantity;

      transaction.set(orderRef, {
        'itemId': item.id,
        'itemName': item.name,
        'itemImageBase64': item.imageBase64,
        'buyerId': buyer['uid'],
        'buyerName': buyer['name'],
        'buyerPhotoBase64': buyer['photoBase64'],
        'sellerId': item.sellerId,
        'sellerName': item.sellerName,
        'sellerPhotoBase64': item.sellerPhotoBase64,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'totalPrice': totalPrice,
        'location': item.location,
        'paymentMethod': 'COD',
        'codOnly': true,
        'status': 'pending',
        'note': note.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      transaction.update(itemRef, {
        'quantity': FieldValue.increment(-quantity),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    await NotificationService.instance.createUserNotification(
      receiverUid: item.sellerId,
      type: 'market_order',
      title: 'New COD order for ${item.name}',
      body:
          '${buyer['name']} ordered $quantity item(s). Prepare for COD pickup.',
      screen: 'market_seller_orders',
      notificationId: 'market_order_${orderRef.id}',
      extraData: {
        'orderId': orderRef.id,
        'itemId': item.id,
        'itemName': item.name,
      },
    );

    return orderRef.id;
  }

  static Future<void> updateOrderStatus({
    required MarketOrder order,
    required String status,
  }) async {
    if (currentUid != order.sellerId && currentUid != order.buyerId) {
      throw Exception('You are not part of this order');
    }

    final allowed = ['pending', 'accepted', 'ready', 'completed', 'cancelled'];
    if (!allowed.contains(status)) throw Exception('Invalid order status');

    await _orders.doc(order.id).set({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final receiverUid = currentUid == order.sellerId
        ? order.buyerId
        : order.sellerId;
    final statusText = _statusTitle(status);

    await NotificationService.instance.createUserNotification(
      receiverUid: receiverUid,
      type: 'market_order_update',
      title: 'COD order updated',
      body: '${order.itemName} is now $statusText.',
      screen: 'market_orders',
      notificationId:
          'market_order_update_${order.id}_${DateTime.now().millisecondsSinceEpoch}',
      extraData: {
        'orderId': order.id,
        'itemId': order.itemId,
        'itemName': order.itemName,
        'status': status,
      },
    );
  }

  static Future<void> toggleItemStatus(MarketItem item) async {
    if (item.sellerId != currentUid)
      throw Exception('Only seller can update item');
    await _items.doc(item.id).set({
      'status': item.status == 'active' ? 'paused' : 'active',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> deleteItem(MarketItem item) async {
    if (item.sellerId != currentUid)
      throw Exception('Only seller can delete item');
    await _items.doc(item.id).delete();
  }

  static String _statusTitle(String status) {
    switch (status) {
      case 'accepted':
        return 'accepted';
      case 'ready':
        return 'ready for pickup';
      case 'completed':
        return 'completed';
      case 'cancelled':
        return 'cancelled';
      default:
        return 'pending';
    }
  }

  static int _safeInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _safeDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }
}
