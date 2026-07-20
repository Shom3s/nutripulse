import 'package:cloud_firestore/cloud_firestore.dart';

class MarketOrder {
  const MarketOrder({
    required this.id,
    required this.itemId,
    required this.itemName,
    required this.buyerId,
    required this.buyerName,
    this.buyerPhotoBase64 = '',
    required this.sellerId,
    required this.sellerName,
    this.sellerPhotoBase64 = '',
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
    required this.location,
    required this.status,
    this.note = '',
    this.itemImageBase64 = '',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String itemId;
  final String itemName;
  final String buyerId;
  final String buyerName;
  final String buyerPhotoBase64;
  final String sellerId;
  final String sellerName;
  final String sellerPhotoBase64;
  final int quantity;
  final double unitPrice;
  final double totalPrice;
  final String location;
  final String status;
  final String note;
  final String itemImageBase64;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  factory MarketOrder.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    return MarketOrder(
      id: doc.id,
      itemId: (data['itemId'] ?? '').toString(),
      itemName: (data['itemName'] ?? 'Food order').toString(),
      buyerId: (data['buyerId'] ?? '').toString(),
      buyerName: (data['buyerName'] ?? 'Buyer').toString(),
      buyerPhotoBase64: (data['buyerPhotoBase64'] ?? '').toString(),
      sellerId: (data['sellerId'] ?? '').toString(),
      sellerName: (data['sellerName'] ?? 'Seller').toString(),
      sellerPhotoBase64: (data['sellerPhotoBase64'] ?? '').toString(),
      quantity: _toInt(data['quantity']),
      unitPrice: _toDouble(data['unitPrice']),
      totalPrice: _toDouble(data['totalPrice']),
      location: (data['location'] ?? 'COD pickup').toString(),
      status: (data['status'] ?? 'pending').toString(),
      note: (data['note'] ?? '').toString(),
      itemImageBase64: (data['itemImageBase64'] ?? '').toString(),
      createdAt: data['createdAt'] is Timestamp
          ? data['createdAt'] as Timestamp
          : null,
      updatedAt: data['updatedAt'] is Timestamp
          ? data['updatedAt'] as Timestamp
          : null,
    );
  }

  static double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
