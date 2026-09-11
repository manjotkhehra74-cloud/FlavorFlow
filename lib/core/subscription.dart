import 'package:flutter/foundation.dart';

import 'api.dart';

/// SaaS subscription state of THIS company (FlavorFlow cloud tenants only).
///
/// Source: gateway `GET /saas/billing/status` (served on the tenant path
/// `…/t/<code>/api/saas/billing/status`). Self-hosted / factory servers have
/// no such route → [SubscriptionStatus.none] and every banner stays hidden.
///
/// Payment is offline (cheque / NEFT) — the app only *shows* the plan, the
/// due invoice, bank details and the WhatsApp number; activation is done by
/// the FlavorFlow owner from the console, after which `paidUntil` moves.
class SubscriptionStatus {
  final bool available;
  final String company, code, state, until, graceUntil, trialEnds, paidUntil;
  final int? daysLeft;
  final bool suspended;
  final String suspendNote;
  final String planTier, planName, planCycle;
  final num planPrice;
  final int planUsers;
  final List<String> planFeatures;
  final bool planChosen;
  final Map<String, dynamic>? dueInvoice;
  final List<Map<String, dynamic>> invoices;
  final Map<String, dynamic> payment;
  final List<Map<String, dynamic>> plans;
  final int graceDays;

  const SubscriptionStatus._({
    required this.available, this.company = '', this.code = '', this.state = '', this.until = '', this.graceUntil = '', this.trialEnds = '', this.paidUntil = '',
    this.daysLeft, this.suspended = false, this.suspendNote = '', this.planTier = '', this.planName = '', this.planCycle = '', this.planPrice = 0, this.planUsers = 0,
    this.planFeatures = const [], this.planChosen = false, this.dueInvoice, this.invoices = const [], this.payment = const {}, this.plans = const [], this.graceDays = 0,
  });

  static const none = SubscriptionStatus._(available: false);

  factory SubscriptionStatus.fromJson(Map<String, dynamic> j) {
    final plan = (j['plan'] as Map?)?.cast<String, dynamic>() ?? const {};
    return SubscriptionStatus._(
      available: true,
      company: '${j['company'] ?? ''}', code: '${j['code'] ?? ''}', state: '${j['state'] ?? ''}', until: '${j['until'] ?? ''}', graceUntil: '${j['graceUntil'] ?? ''}',
      trialEnds: '${j['trialEnds'] ?? ''}', paidUntil: '${j['paidUntil'] ?? ''}', daysLeft: (j['daysLeft'] as num?)?.toInt(),
      suspended: j['suspended'] == true, suspendNote: '${j['suspendNote'] ?? ''}',
      planTier: '${plan['tier'] ?? ''}', planName: '${plan['name'] ?? plan['tier'] ?? ''}', planCycle: '${plan['cycle'] ?? ''}', planPrice: (plan['price'] as num?) ?? 0,
      planUsers: (plan['users'] as num?)?.toInt() ?? 0, planFeatures: ((plan['features'] as List?) ?? const []).map((e) => '$e').toList(), planChosen: plan['chosen'] == true,
      dueInvoice: (j['dueInvoice'] as Map?)?.cast<String, dynamic>(),
      invoices: ((j['invoices'] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList(),
      payment: (j['payment'] as Map?)?.cast<String, dynamic>() ?? const {},
      plans: ((j['plans'] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList(),
      graceDays: (j['graceDays'] as num?)?.toInt() ?? 0,
    );
  }

  bool get isDemo => state == 'demo';
  bool get isTrial => state == 'trial';
  bool get isActive => state == 'active';
  bool get isGrace => state == 'grace';
  bool get isBlocked => state == 'expired' || state == 'suspended';

  /// Show the dashboard banner: due invoice, grace, trial ending soon, blocked.
  bool get needsAttention {
    if (!available || isDemo) return false;
    if (isBlocked || isGrace || dueInvoice != null) return true;
    if (isTrial && daysLeft != null && daysLeft! <= 7) return true;
    return false;
  }

  String get whatsapp => '${payment['whatsapp'] ?? ''}';
}

/// Loads / caches the subscription status; also flipped to blocked by the
/// API client when any request comes back 402 (subscription ended).
class SubscriptionController extends ChangeNotifier {
  SubscriptionStatus status = SubscriptionStatus.none;
  String? blockMessage; // last 402 message from the gateway
  bool loading = false;

  Future<void> refresh(ApiClient api) async {
    loading = true;
    try {
      final j = await api.get('/saas/billing/status');
      status = SubscriptionStatus.fromJson((j as Map).cast<String, dynamic>());
      if (!status.isBlocked) blockMessage = null;
    } on ApiException catch (e) {
      if (e.status == 402) {
        // gateway blocks everything incl. status? no — status is served before the gate;
        // still, be defensive and keep the message.
        blockMessage = e.message;
      } else {
        status = SubscriptionStatus.none; // self-hosted / older gateway
      }
    } catch (_) {
      status = SubscriptionStatus.none;
    }
    loading = false;
    notifyListeners();
  }

  /// Called from ApiClient on any 402 response.
  void onPaymentRequired(String message, Map<String, dynamic>? billing) {
    blockMessage = message;
    if (billing != null) {
      try { status = SubscriptionStatus.fromJson(billing); } catch (_) {}
    }
    notifyListeners();
  }

  void clear() {
    status = SubscriptionStatus.none;
    blockMessage = null;
    notifyListeners();
  }
}
