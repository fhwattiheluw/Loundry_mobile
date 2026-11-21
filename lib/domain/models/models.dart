import 'enums.dart';

/// Semua nominal uang disimpan sebagai int rupiah penuh, tanpa desimal.
/// Alasannya: double menimbulkan selisih pembulatan yang merusak laporan.

class AppUser {
  const AppUser({
    this.id,
    required this.name,
    required this.pinHash,
    required this.role,
    this.active = true,
  });

  final int? id;
  final String name;
  final String pinHash;
  final UserRole role;
  final bool active;

  bool get isOwner => role == UserRole.owner;

  factory AppUser.fromMap(Map<String, Object?> m) => AppUser(
        id: m['id'] as int?,
        name: m['name'] as String,
        pinHash: m['pin_hash'] as String,
        role: UserRole.fromDb(m['role'] as String),
        active: (m['active'] as int? ?? 1) == 1,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'pin_hash': pinHash,
        'role': role.name,
        'active': active ? 1 : 0,
      };
}

class Customer {
  const Customer({
    this.id,
    required this.name,
    required this.phone,
    this.address,
    this.note,
    this.notifyEnabled = true,
  });

  final int? id;
  final String name;

  /// Selalu disimpan dalam format internasional tanpa tanda plus, misalnya 62812...
  final String phone;
  final String? address;
  final String? note;
  final bool notifyEnabled;

  Customer copyWith({int? id, String? name, String? phone}) => Customer(
        id: id ?? this.id,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        address: address,
        note: note,
        notifyEnabled: notifyEnabled,
      );

  factory Customer.fromMap(Map<String, Object?> m) => Customer(
        id: m['id'] as int?,
        name: m['name'] as String,
        phone: m['phone'] as String,
        address: m['address'] as String?,
        note: m['note'] as String?,
        notifyEnabled: (m['notify_enabled'] as int? ?? 1) == 1,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'phone': phone,
        'address': address,
        'note': note,
        'notify_enabled': notifyEnabled ? 1 : 0,
      };
}

class LaundryService {
  const LaundryService({
    this.id,
    required this.name,
    required this.unit,
    required this.price,
    required this.durationHours,
    this.minQty = 0,
    this.roundingStep = 0,
    this.expressMultiplier = 2.0,
    this.expressDurationHours = 6,
    this.active = true,
  });

  final int? id;
  final String name;
  final ServiceUnit unit;

  /// Harga per satuan, rupiah penuh.
  final int price;
  final int durationHours;

  /// Minimum kuantitas yang ditagih, misalnya minimal 3 kg.
  final double minQty;

  /// Kelipatan pembulatan kuantitas, misalnya 0.1 kg. Nol berarti tanpa pembulatan.
  final double roundingStep;
  final double expressMultiplier;
  final int expressDurationHours;
  final bool active;

  factory LaundryService.fromMap(Map<String, Object?> m) => LaundryService(
        id: m['id'] as int?,
        name: m['name'] as String,
        unit: ServiceUnit.fromDb(m['unit'] as String),
        price: m['price'] as int,
        durationHours: m['duration_hours'] as int,
        minQty: (m['min_qty'] as num?)?.toDouble() ?? 0,
        roundingStep: (m['rounding_step'] as num?)?.toDouble() ?? 0,
        expressMultiplier:
            (m['express_multiplier'] as num?)?.toDouble() ?? 2.0,
        expressDurationHours: m['express_duration_hours'] as int? ?? 6,
        active: (m['active'] as int? ?? 1) == 1,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'unit': unit.name,
        'price': price,
        'duration_hours': durationHours,
        'min_qty': minQty,
        'rounding_step': roundingStep,
        'express_multiplier': expressMultiplier,
        'express_duration_hours': expressDurationHours,
        'active': active ? 1 : 0,
      };
}

/// Baris layanan di dalam satu nota.
///
/// Nama, satuan, dan harga sengaja DISALIN dari master saat transaksi dibuat.
/// Tanpa itu, kenaikan harga akan mengubah nilai nota lama dan merusak
/// laporan bulan-bulan sebelumnya.
class OrderItem {
  const OrderItem({
    this.id,
    this.orderId,
    required this.serviceId,
    required this.serviceName,
    required this.unit,
    required this.qty,
    required this.unitPrice,
    required this.subtotal,
    this.express = false,
    this.note,
    this.itemDetails,
  });

  final int? id;
  final int? orderId;
  final int serviceId;
  final String serviceName;
  final ServiceUnit unit;
  final double qty;
  final int unitPrice;
  final int subtotal;
  final bool express;
  final String? note;

  /// Rincian isi cucian, misalnya "3 kemeja, 2 celana" (FR-32).
  /// Inilah yang menyelamatkan pemilik saat pelanggan mengaku ada yang hilang.
  final String? itemDetails;

  OrderItem copyWith({int? orderId}) => OrderItem(
        id: id,
        orderId: orderId ?? this.orderId,
        serviceId: serviceId,
        serviceName: serviceName,
        unit: unit,
        qty: qty,
        unitPrice: unitPrice,
        subtotal: subtotal,
        express: express,
        note: note,
        itemDetails: itemDetails,
      );

  factory OrderItem.fromMap(Map<String, Object?> m) => OrderItem(
        id: m['id'] as int?,
        orderId: m['order_id'] as int?,
        serviceId: m['service_id'] as int,
        serviceName: m['service_name'] as String,
        unit: ServiceUnit.fromDb(m['unit'] as String),
        qty: (m['qty'] as num).toDouble(),
        unitPrice: m['unit_price'] as int,
        subtotal: m['subtotal'] as int,
        express: (m['express'] as int? ?? 0) == 1,
        note: m['note'] as String?,
        itemDetails: m['item_details'] as String?,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'order_id': orderId,
        'service_id': serviceId,
        'service_name': serviceName,
        'unit': unit.name,
        'qty': qty,
        'unit_price': unitPrice,
        'subtotal': subtotal,
        'express': express ? 1 : 0,
        'note': note,
        'item_details': itemDetails,
      };
}

class LaundryOrder {
  const LaundryOrder({
    this.id,
    required this.orderNo,
    required this.customerId,
    required this.createdBy,
    required this.createdAt,
    required this.estimatedAt,
    required this.laundryStatus,
    required this.paymentStatus,
    required this.subtotal,
    required this.discount,
    required this.total,
    this.extraFee = 0,
    this.extraFeeNote,
    this.perfume,
    this.paid = 0,
    this.note,
    this.pickedUpAt,
    this.pickedUpBy,
    this.cancelledAt,
    this.cancelReason,
    this.items = const [],
    this.customerName = '',
    this.customerPhone = '',
  });

  final int? id;
  final String orderNo;
  final int customerId;
  final int createdBy;
  final DateTime createdAt;
  final DateTime estimatedAt;
  final LaundryStatus laundryStatus;
  final PaymentStatus paymentStatus;
  final int subtotal;
  final int discount;

  /// Biaya tambahan seperti antar-jemput atau kantong khusus (FR-51).
  final int extraFee;
  final String? extraFeeNote;

  /// Pewangi yang dipilih pelanggan (FR-12).
  final String? perfume;

  final int total;

  /// Dihitung dari tabel payments, bukan disimpan sebagai kolom.
  final int paid;
  final String? note;
  final DateTime? pickedUpAt;
  final String? pickedUpBy;
  final DateTime? cancelledAt;
  final String? cancelReason;

  final List<OrderItem> items;
  final String customerName;
  final String customerPhone;

  int get remaining => (total - paid).clamp(0, total);
  bool get isPaidOff => remaining <= 0;

  LaundryOrder copyWith({
    LaundryStatus? laundryStatus,
    PaymentStatus? paymentStatus,
    int? paid,
    List<OrderItem>? items,
  }) =>
      LaundryOrder(
        id: id,
        orderNo: orderNo,
        customerId: customerId,
        createdBy: createdBy,
        createdAt: createdAt,
        estimatedAt: estimatedAt,
        laundryStatus: laundryStatus ?? this.laundryStatus,
        paymentStatus: paymentStatus ?? this.paymentStatus,
        subtotal: subtotal,
        discount: discount,
        extraFee: extraFee,
        extraFeeNote: extraFeeNote,
        perfume: perfume,
        total: total,
        paid: paid ?? this.paid,
        note: note,
        pickedUpAt: pickedUpAt,
        pickedUpBy: pickedUpBy,
        cancelledAt: cancelledAt,
        cancelReason: cancelReason,
        items: items ?? this.items,
        customerName: customerName,
        customerPhone: customerPhone,
      );

  factory LaundryOrder.fromMap(Map<String, Object?> m) => LaundryOrder(
        id: m['id'] as int?,
        orderNo: m['order_no'] as String,
        customerId: m['customer_id'] as int,
        createdBy: m['created_by'] as int,
        createdAt: DateTime.parse(m['created_at'] as String),
        estimatedAt: DateTime.parse(m['estimated_at'] as String),
        laundryStatus: LaundryStatus.fromDb(m['laundry_status'] as String),
        paymentStatus: PaymentStatus.fromDb(m['payment_status'] as String),
        subtotal: m['subtotal'] as int,
        discount: m['discount'] as int,
        extraFee: (m['extra_fee'] as num?)?.toInt() ?? 0,
        extraFeeNote: m['extra_fee_note'] as String?,
        perfume: m['perfume'] as String?,
        total: m['total'] as int,
        paid: (m['paid'] as num?)?.toInt() ?? 0,
        note: m['note'] as String?,
        pickedUpAt: _date(m['picked_up_at']),
        pickedUpBy: m['picked_up_by'] as String?,
        cancelledAt: _date(m['cancelled_at']),
        cancelReason: m['cancel_reason'] as String?,
        customerName: m['customer_name'] as String? ?? '',
        customerPhone: m['customer_phone'] as String? ?? '',
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'order_no': orderNo,
        'customer_id': customerId,
        'created_by': createdBy,
        'created_at': createdAt.toIso8601String(),
        'estimated_at': estimatedAt.toIso8601String(),
        'laundry_status': laundryStatus.name,
        'payment_status': paymentStatus.name,
        'subtotal': subtotal,
        'discount': discount,
        'extra_fee': extraFee,
        'extra_fee_note': extraFeeNote,
        'perfume': perfume,
        'total': total,
        'note': note,
        'picked_up_at': pickedUpAt?.toIso8601String(),
        'picked_up_by': pickedUpBy,
        'cancelled_at': cancelledAt?.toIso8601String(),
        'cancel_reason': cancelReason,
      };

  static DateTime? _date(Object? v) =>
      v == null ? null : DateTime.parse(v as String);
}

class Payment {
  const Payment({
    this.id,
    required this.orderId,
    this.shiftId,
    required this.paidAt,
    required this.amount,
    required this.method,
    required this.receivedBy,
    this.note,
  });

  final int? id;
  final int orderId;
  final int? shiftId;
  final DateTime paidAt;

  /// Negatif untuk refund. Laporan pendapatan menjumlahkan kolom ini apa adanya.
  final int amount;
  final String method;
  final int receivedBy;
  final String? note;

  bool get isRefund => amount < 0;

  factory Payment.fromMap(Map<String, Object?> m) => Payment(
        id: m['id'] as int?,
        orderId: m['order_id'] as int,
        shiftId: m['shift_id'] as int?,
        paidAt: DateTime.parse(m['paid_at'] as String),
        amount: m['amount'] as int,
        method: m['method'] as String,
        receivedBy: m['received_by'] as int,
        note: m['note'] as String?,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'order_id': orderId,
        'shift_id': shiftId,
        'paid_at': paidAt.toIso8601String(),
        'amount': amount,
        'method': method,
        'received_by': receivedBy,
        'note': note,
      };
}

class Shift {
  const Shift({
    this.id,
    required this.userId,
    required this.openedAt,
    this.closedAt,
    required this.openingCash,
    this.closingCash,
    this.expectedCash,
  });

  final int? id;
  final int userId;
  final DateTime openedAt;
  final DateTime? closedAt;
  final int openingCash;
  final int? closingCash;
  final int? expectedCash;

  bool get isOpen => closedAt == null;
  int? get difference =>
      (closingCash == null || expectedCash == null)
          ? null
          : closingCash! - expectedCash!;

  factory Shift.fromMap(Map<String, Object?> m) => Shift(
        id: m['id'] as int?,
        userId: m['user_id'] as int,
        openedAt: DateTime.parse(m['opened_at'] as String),
        closedAt: LaundryOrder._date(m['closed_at']),
        openingCash: m['opening_cash'] as int,
        closingCash: m['closing_cash'] as int?,
        expectedCash: m['expected_cash'] as int?,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'user_id': userId,
        'opened_at': openedAt.toIso8601String(),
        'closed_at': closedAt?.toIso8601String(),
        'opening_cash': openingCash,
        'closing_cash': closingCash,
        'expected_cash': expectedCash,
      };
}
