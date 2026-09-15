import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/app_scope.dart';
import '../../../core/media/image_upload_policy.dart';
import '../../../core/network/api_exception.dart';
import '../domain/commerce_models.dart';

final class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

final class _OrdersPageState extends State<OrdersPage> {
  Future<List<CustomerOrder>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= AppScope.of(context).loadOrders();
  }

  Future<void> _reload() async {
    setState(() => _future = AppScope.of(context).loadOrders());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('طلباتي')),
    body: FutureBuilder<List<CustomerOrder>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) return _OrdersFailure(onRetry: _reload);
        final orders = snapshot.data ?? const <CustomerOrder>[];
        if (orders.isEmpty) return const _OrdersEmpty();
        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: orders.length,
            separatorBuilder: (_, _) => const SizedBox(height: 11),
            itemBuilder: (_, index) => _OrderCard(
              order: orders[index],
              onOpen: () async {
                final changed = await Navigator.of(context).push<bool>(
                  MaterialPageRoute<bool>(
                    builder: (_) => OrderDetailsPage(order: orders[index]),
                  ),
                );
                if (changed == true && mounted) _reload();
              },
            ),
          ),
        );
      },
    ),
  );
}

final class OrderDetailsPage extends StatefulWidget {
  const OrderDetailsPage({super.key, required this.order});
  final CustomerOrder order;

  @override
  State<OrderDetailsPage> createState() => _OrderDetailsPageState();
}

final class _OrderDetailsPageState extends State<OrderDetailsPage> {
  bool _submitting = false;

  bool get _canSubmitReceipt =>
      widget.order.paymentMethod == 'manual_transfer' &&
      [
        'awaiting_payment',
        'payment_rejected',
      ].contains(widget.order.orderStatus);
  bool get _canCancel => [
    'awaiting_payment',
    'payment_rejected',
    'payment_verified',
    'merchant_accepted',
  ].contains(widget.order.orderStatus);
  bool get _canConfirm => widget.order.orderStatus == 'delivered';

  Future<void> _cancel() async {
    final reason = await _askCancellationReason();
    if (reason == null || !mounted) return;
    setState(() => _submitting = true);
    try {
      await AppScope.of(context)
          .cancelOrder(orderId: widget.order.publicId, reason: reason);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<String?> _askCancellationReason() async {
    final text = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إلغاء الطلب'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: text,
            maxLength: 1000,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'سبب الإلغاء (اختياري)',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('رجوع'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(text.text),
            child: const Text('تأكيد الإلغاء'),
          ),
        ],
      ),
    );
    text.dispose();
    return result;
  }

  Future<void> _confirmDelivery() async {
    setState(() => _submitting = true);
    try {
      await AppScope.of(context).confirmOrderDelivery(widget.order.publicId);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _openPayment() async {
    final submitted = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ManualPaymentPage(order: widget.order),
      ),
    );
    if (submitted == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    return Scaffold(
      appBar: AppBar(title: Text(order.orderNumber)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    order.storeName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _StatusPill(status: order.orderStatus),
                  const SizedBox(height: 14),
                  _InfoRow(
                    label: 'طريقة الدفع',
                    value: order.paymentMethod == 'cash_on_delivery'
                        ? 'الدفع عند الاستلام'
                        : 'تحويل يدوي',
                  ),
                  _InfoRow(
                    label: 'رسوم التوصيل',
                    value: order.deliveryDistanceKm == null
                        ? _money(order.deliveryFee, order.currencyCode)
                        : '${_money(order.deliveryFee, order.currencyCode)} · ${order.deliveryDistanceKm!.toStringAsFixed(1)} كم',
                  ),
                  _InfoRow(
                    label: 'الإجمالي',
                    value: _money(order.total, order.currencyCode),
                  ),
                  if (order.placedAt != null)
                    _InfoRow(label: 'تاريخ الطلب', value: order.placedAt!),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'المنتجات',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: order.items
                  .map(
                    (item) => ListTile(
                      title: Text(
                        item.name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text('${item.quantity} قطعة'),
                      trailing: Text(
                        _money(item.lineTotal, order.currencyCode),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
          if (order.history.isNotEmpty) ...[
            const SizedBox(height: 22),
            Text(
              'سجل الطلب',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: order.history
                      .map(
                        (event) => Padding(
                          padding: const EdgeInsets.only(bottom: 13),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.check_circle_outline_rounded,
                                size: 19,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  '${_statusLabel(event.toStatus)}${event.note?.isNotEmpty == true ? '\n${event.note}' : ''}',
                                  style: const TextStyle(height: 1.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
            ),
          ],
          const SizedBox(height: 23),
          if (_canSubmitReceipt)
            FilledButton.icon(
              onPressed: _submitting ? null : _openPayment,
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('إرفاق سند التحويل'),
            ),
          if (_canConfirm) ...[
            if (_canSubmitReceipt) const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _submitting ? null : _confirmDelivery,
              icon: const Icon(Icons.check_circle_outline_rounded),
              label: const Text('تأكيد استلام الطلب'),
            ),
          ],
          if (_canCancel) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _submitting ? null : _cancel,
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('إلغاء الطلب'),
            ),
          ],
        ],
      ),
    );
  }
}

final class ManualPaymentPage extends StatefulWidget {
  const ManualPaymentPage({super.key, required this.order});
  final CustomerOrder order;

  @override
  State<ManualPaymentPage> createState() => _ManualPaymentPageState();
}

final class _ManualPaymentPageState extends State<ManualPaymentPage> {
  final _reference = TextEditingController();
  XFile? _receipt;
  bool _submitting = false;

  @override
  void dispose() {
    _reference.dispose();
    super.dispose();
  }

  Future<void> _pickReceipt() async {
    final file = await ImageUploadPolicy.pick(ImageSource.gallery);
    if (file != null && mounted) setState(() => _receipt = file);
  }

  Future<void> _submit() async {
    if (_reference.text.trim().length < 2 || _receipt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل مرجع التحويل واختر صورة السند.')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await AppScope.of(context).submitManualPayment(
        orderId: widget.order.publicId,
        transferReference: _reference.text,
        receipt: _receipt!,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('سند التحويل اليدوي')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'الطلب ${widget.order.orderNumber}\nالمبلغ ${_money(widget.order.total, widget.order.currencyCode)}',
              style: const TextStyle(height: 1.7, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _reference,
          maxLength: 120,
          decoration: const InputDecoration(labelText: 'مرجع التحويل'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _submitting ? null : _pickReceipt,
          icon: const Icon(Icons.photo_library_outlined),
          label: Text(
            _receipt == null
                ? 'اختيار صورة سند التحويل'
                : 'تم اختيار: ${_receipt!.name}',
          ),
        ),
        if (_receipt != null) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AspectRatio(
              aspectRatio: 16 / 10,
              child: Image.file(
                File(_receipt!.path),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const ColoredBox(
                  color: Color(0xFFF0F2F4),
                  child: Center(child: Icon(Icons.broken_image_outlined)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text('معاينة السند المختار', textAlign: TextAlign.center),
        ],
        const SizedBox(height: 10),
        const Text(
          'سيُرفع السند كملف خاص ولا يظهر للعامة. الصيغ المدعومة: JPG وPNG وWebP، حتى 8 MiB.',
        ),
        const SizedBox(height: 25),
        FilledButton.icon(
          onPressed: _submitting ? null : _submit,
          icon: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Icon(Icons.lock_outline_rounded),
          label: const Text('إرسال السند للمراجعة'),
        ),
      ],
    ),
  );
}

final class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.onOpen});
  final CustomerOrder order;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      leading: CircleAvatar(
        child: Icon(
          Icons.receipt_long_outlined,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      title: Text(
        order.storeName,
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      subtitle: Text(
        '${order.orderNumber}\n${_money(order.total, order.currencyCode)}',
      ),
      isThreeLine: true,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _StatusPill(status: order.orderStatus),
          const Icon(Icons.chevron_left_rounded),
        ],
      ),
      onTap: onOpen,
    ),
  );
}

final class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) => Chip(
    label: Text(
      _statusLabel(status),
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
    ),
    backgroundColor: status == 'cancelled'
        ? const Color(0xFFFDEBE8)
        : const Color(0xFFE5F4ED),
    side: BorderSide.none,
  );
}

final class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Row(
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.left,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    ),
  );
}

final class _OrdersEmpty extends StatelessWidget {
  const _OrdersEmpty();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.receipt_long_outlined,
                size: 45,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 12),
              const Text(
                'لا توجد طلبات حتى الآن',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              const Text(
                'ستظهر طلبات المتاجر هنا عند إتمامها.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

final class _OrdersFailure extends StatelessWidget {
  const _OrdersFailure({required this.onRetry});
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: FilledButton.icon(
      onPressed: onRetry,
      icon: const Icon(Icons.refresh_rounded),
      label: const Text('تعذر تحميل الطلبات — إعادة المحاولة'),
    ),
  );
}

String _money(num amount, String currency) =>
    '${amount.toStringAsFixed(2)} $currency';

String _statusLabel(String status) => switch (status) {
  'awaiting_payment' => 'بانتظار الدفع',
  'payment_submitted' => 'السند قيد المراجعة',
  'payment_rejected' => 'إعادة إرسال السند',
  'payment_verified' => 'تم اعتماد الدفع',
  'merchant_accepted' => 'قبله المتجر',
  'preparing' => 'جارٍ التحضير',
  'ready_for_pickup' => 'جاهز للاستلام',
  'delivery_assigned' => 'تم تعيين التوصيل',
  'delivered' => 'تم التسليم',
  'completed' => 'مكتمل',
  'cancelled' => 'ملغي',
  _ => 'قيد المعالجة',
};
