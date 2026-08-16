import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';

/// Icon registry — server sends icon names, client maps to Material icons.
IconData iconFor(String? name) {
  switch (name) {
    case 'dashboard': return Icons.dashboard_outlined;
    case 'inventory_2': return Icons.inventory_2_outlined;
    case 'warehouse': return Icons.warehouse_outlined;
    case 'tune': return Icons.tune_rounded;
    case 'fact_check': return Icons.fact_check_outlined;
    case 'manufacturing': return Icons.precision_manufacturing_outlined;
    case 'event_note': return Icons.event_note_outlined;
    case 'local_shipping': return Icons.local_shipping_outlined;
    case 'bar_chart': return Icons.bar_chart_rounded;
    case 'group': return Icons.group_outlined;
    case 'history': return Icons.history_rounded;
    case 'add_circle': return Icons.add_circle_outline_rounded;
    case 'calculate': return Icons.calculate_outlined;
    case 'add_box': return Icons.add_box_outlined;
    case 'widgets': return Icons.widgets_outlined;
    case 'science': return Icons.science_outlined;
    case 'settings': return Icons.settings_outlined;
    case 'liquor': return Icons.liquor_outlined;
    case 'dinner_dining': return Icons.dinner_dining_outlined;
    case 'category': return Icons.category_outlined;
    case 'account_balance_wallet': return Icons.account_balance_wallet_outlined;
    case 'warning': return Icons.warning_amber_rounded;
    case 'pending': return Icons.pending_outlined;
    case 'pending_actions': return Icons.pending_actions_outlined;
    case 'alarm': return Icons.alarm_rounded;
    case 'check_circle': return Icons.check_circle_outlined;
    case 'scale': return Icons.scale_outlined;
    case 'notifications': return Icons.notifications_outlined;
    default: return Icons.circle_outlined;
  }
}

/// Notification type → icon & color.
IconData notifIcon(String type) {
  switch (type) {
    case 'low_stock': return Icons.inventory_rounded;
    case 'approval_pending': return Icons.fact_check_outlined;
    case 'approval_decision': return Icons.rule_rounded;
    case 'production_completed': return Icons.precision_manufacturing_outlined;
    case 'dispatch_alert': return Icons.local_shipping_outlined;
    case 'packing_low': return Icons.widgets_outlined;
    default: return Icons.notifications_outlined;
  }
}

Color notifColor(String type) {
  switch (type) {
    case 'low_stock': return AppColors.red;
    case 'approval_pending': return AppColors.amber;
    case 'approval_decision': return AppColors.blue;
    case 'production_completed': return AppColors.teal;
    case 'dispatch_alert': return AppColors.orange;
    case 'packing_low': return AppColors.violet;
    default: return AppColors.slate;
  }
}

String notifLabel(String type) {
  switch (type) {
    case 'low_stock': return 'Low stock';
    case 'approval_pending': return 'Approval';
    case 'approval_decision': return 'Decision';
    case 'production_completed': return 'Production';
    case 'dispatch_alert': return 'Dispatch';
    case 'packing_low': return 'Packing low';
    default: return 'Info';
  }
}

/// SAP-style object status: subtle tinted pill with hairline border.
class StatusChip extends StatelessWidget {
  final String status;
  const StatusChip(this.status, {super.key});

  static const Map<String, (Color, Color)> _palette = {
    'PENDING': (Color(0xFFB45309), Color(0xFFFEF6E7)),
    'APPROVED': (Color(0xFF047857), Color(0xFFE7F6EF)),
    'REJECTED': (Color(0xFFB91C1C), Color(0xFFFBEAEA)),
    'PLANNED': (Color(0xFF1D4ED8), Color(0xFFE9F0FC)),
    'IN_PROGRESS': (Color(0xFF0F766E), Color(0xFFE6F5F3)),
    'COMPLETED': (Color(0xFF047857), Color(0xFFE7F6EF)),
    'IN STOCK': (Color(0xFF047857), Color(0xFFE7F6EF)),
    'DISPATCHED': (Color(0xFFC2410C), Color(0xFFFBEFE6)),
    'DRAFT': (Color(0xFF475569), Color(0xFFEFF2F6)),
    'CANCELLED': (Color(0xFF475569), Color(0xFFEFF2F6)),
    'HIGH': (Color(0xFFB91C1C), Color(0xFFFBEAEA)),
    'MEDIUM': (Color(0xFFB45309), Color(0xFFFEF6E7)),
    'LOW': (Color(0xFF047857), Color(0xFFE7F6EF)),
    'OK': (Color(0xFF047857), Color(0xFFE7F6EF)),
    'IN': (Color(0xFF047857), Color(0xFFE7F6EF)),
    'OUT': (Color(0xFFB91C1C), Color(0xFFFBEAEA)),
    'ACTIVE': (Color(0xFF047857), Color(0xFFE7F6EF)),
    'INACTIVE': (Color(0xFF475569), Color(0xFFEFF2F6)),
    'LOGIN': (Color(0xFF1D4ED8), Color(0xFFE9F0FC)),
    'LOGOUT': (Color(0xFF475569), Color(0xFFEFF2F6)),
    'CREATE': (Color(0xFF047857), Color(0xFFE7F6EF)),
    'UPDATE': (Color(0xFFB45309), Color(0xFFFEF6E7)),
    'APPROVE': (Color(0xFF047857), Color(0xFFE7F6EF)),
    'REJECT': (Color(0xFFB91C1C), Color(0xFFFBEAEA)),
    'DISPATCH': (Color(0xFFC2410C), Color(0xFFFBEFE6)),
    'START': (Color(0xFF0F766E), Color(0xFFE6F5F3)),
    'COMPLETE': (Color(0xFF047857), Color(0xFFE7F6EF)),
    'RECEIPT': (Color(0xFF0891B2), Color(0xFFE5F6FA)),
    'EXPORT': (Color(0xFF1D4ED8), Color(0xFFE9F0FC)),
    'SEED': (Color(0xFF475569), Color(0xFFEFF2F6)),
  };

  @override
  Widget build(BuildContext context) {
    final p = _palette[status.toUpperCase()] ?? (AppColors.slate, const Color(0xFFEFF2F6));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: p.$2,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: p.$1.withValues(alpha: 0.30)),
      ),
      child: Text(
        status.replaceAll('_', ' '),
        style: TextStyle(color: p.$1, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.4),
      ),
    );
  }
}

/// Flat white panel with a header row separated by a hairline — the ERP workhorse.
class SectionCard extends StatelessWidget {
  final String? title;
  final Widget child;
  final Widget? trailing;
  final EdgeInsets padding;
  const SectionCard({super.key, this.title, required this.child, this.trailing, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        if (title != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 11),
            child: Row(children: [
              Expanded(child: Text(title!, style: const TextStyle(fontSize: 13.6, fontWeight: FontWeight.w700, letterSpacing: -0.1))),
              if (trailing != null) trailing!,
            ]),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
        ],
        Padding(padding: padding, child: child),
      ]),
    );
  }
}

/// Flat enterprise KPI tile: caps label, big tabular figure, quiet icon.
class KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color tint;
  final String? sub;
  const KpiCard({super.key, required this.label, required this.value, required this.icon, required this.tint, this.sub});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 13, 15, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Row(children: [
            Expanded(
              child: Text(label.toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.9, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
            Icon(icon, size: 16, color: tint),
          ]),
          const SizedBox(height: 7),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: TextStyle(
                    fontSize: 23, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: Theme.of(context).colorScheme.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ),
        ]),
      ),
    );
  }
}

/// Responsive table that scrolls horizontally on narrow screens.
/// Numbers render right-aligned with tabular figures — classic ERP grid.
class AppDataTable extends StatelessWidget {
  final List<String> columns;
  final List<List<dynamic>> rows;
  final Set<int> moneyColumns;
  final void Function(int rowIndex)? onRowTap;
  final bool Function(int rowIndex)? highlight;
  const AppDataTable({super.key, required this.columns, required this.rows, this.moneyColumns = const {}, this.onRowTap, this.highlight});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: [for (final c in columns) DataColumn(label: Text(c.toUpperCase()))],
        rows: [
          for (var i = 0; i < rows.length; i++)
            DataRow(
              color: (highlight?.call(i) ?? false)
                  ? WidgetStatePropertyAll(AppColors.amber.withValues(alpha: 0.07))
                  : null,
              onSelectChanged: onRowTap == null ? null : (_) => onRowTap!(i),
              cells: [
                for (var c = 0; c < rows[i].length; c++)
                  DataCell(_cell(rows[i][c], c, scheme)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _cell(dynamic v, int col, ColorScheme scheme) {
    if (v is Widget) return v;
    if (moneyColumns.contains(col)) {
      return Text(inr(v), style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()]));
    }
    if (v is num) {
      return Align(
        alignment: Alignment.centerRight,
        widthFactor: 1,
        child: Text(qty(v), style: TextStyle(fontFeatures: const [FontFeature.tabularFigures()], color: scheme.onSurface)),
      );
    }
    return ConstrainedBox(constraints: const BoxConstraints(maxWidth: 340), child: Text('${v ?? '—'}', overflow: TextOverflow.ellipsis));
  }
}

class EmptyState extends StatelessWidget {
  final String message;
  final IconData icon;
  const EmptyState(this.message, {super.key, this.icon = Icons.inbox_outlined});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 36),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 38, color: scheme.outline),
          const SizedBox(height: 10),
          Text(message, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
        ]),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const ErrorState(this.error, {super.key, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.cloud_off_rounded, size: 40, color: scheme.error),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Text('$error', textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Retry')),
        ]),
      ),
    );
  }
}

void showErr(BuildContext context, Object e) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(backgroundColor: Theme.of(context).colorScheme.error, content: Text('$e')));
}

void showOk(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}
