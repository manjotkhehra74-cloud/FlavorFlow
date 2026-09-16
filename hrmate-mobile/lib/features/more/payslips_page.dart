import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/cache.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';
import 'more_models.dart';

/// Payslips — `GET payslips` list; "Open" launches the server-signed URL in
/// the browser (the webapp already renders/serves the PDF — nothing is
/// rendered in the app). Hidden from More when the server returns 404.
class PayslipsPage extends StatefulWidget {
  const PayslipsPage({super.key});
  @override
  State<PayslipsPage> createState() => _PayslipsPageState();
}

class _PayslipsPageState extends State<PayslipsPage> {
  Cached<List<Payslip>>? _items;
  Object? _error;
  bool _loading = true;
  String? _opening;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthController>().api;
    try {
      final items = await cachedFetch('payslips', () => api.get('/payslips'), Payslip.listFromJson);
      if (!mounted) return;
      setState(() {
        _items = items;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// Opens the server-signed link in the browser / PDF viewer. The list is
  /// re-fetched every time this page opens, so the short-lived link is fresh.
  Future<void> _open(Payslip p) async {
    setState(() => _opening = p.id);
    try {
      final url = p.url;
      if (url == null || url.isEmpty) throw ApiException(404, tr('Payslip file is not available yet'));
      final uri = Uri.parse(url.startsWith('http') ? url : '${Uri.parse(ApiClient.base).origin}$url');
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) throw ApiException(-1, tr('Could not open the payslip'));
    } catch (e) {
      if (mounted) showErr(context, e);
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  void _retry() {
    setState(() {
      _loading = true;
      _error = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<L10n>();
    final t = Theme.of(context).textTheme;
    final cached = _items;
    final Widget body;
    if (_loading) {
      body = const LoadingView();
    } else if (cached == null) {
      body = ErrorRetryView(error: _error ?? tr('Something went wrong'), onRetry: _retry);
    } else if (cached.data.isEmpty) {
      body = EmptyView(icon: Icons.receipt_long_outlined, title: tr('No payslips yet'), subtitle: tr('Payslips appear here after payroll is processed'));
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            if (cached.staleSince != null) ...[
              Align(alignment: Alignment.centerLeft, child: OfflineChip(since: cached.staleSince!)),
              const SizedBox(height: 10),
            ],
            HrCard(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (var i = 0; i < cached.data.length; i++) ...[
                  if (i > 0) const Divider(),
                  ListTile(
                    leading: const Icon(Icons.receipt_long_rounded, color: HrBrand.blue),
                    title: Text(cached.data[i].label, style: t.titleMedium),
                    subtitle: cached.data[i].netPay == null ? null : Text('${tr('Net pay')} ${_money(cached.data[i])}', style: t.bodySmall),
                    trailing: _opening == cached.data[i].id
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2))
                        : const Icon(Icons.open_in_new_rounded, color: HrBrand.subInk),
                    onTap: _opening == null ? () => _open(cached.data[i]) : null,
                  ),
                ],
              ]),
            ),
          ],
        ),
      );
    }
    return Scaffold(appBar: AppBar(title: Text(tr('Payslips'))), body: body);
  }

  static String _money(Payslip p) {
    final v = p.netPay ?? 0;
    if (p.currency != 'INR') return '${p.currency} ${Fmt.compact(v)}';
    // Indian grouping: 1,23,456
    final n = v.round().abs().toString();
    if (n.length <= 3) return '₹$n';
    final last3 = n.substring(n.length - 3);
    var rest = n.substring(0, n.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    return '₹${parts.join(',')},$last3';
  }
}
