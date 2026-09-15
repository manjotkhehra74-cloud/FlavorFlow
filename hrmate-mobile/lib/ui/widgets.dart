import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/i18n.dart';
import '../core/theme.dart';

/// Shared building blocks. Every screen uses THESE for loading / empty /
/// error states (ARCHITECTURE.md §6) — never ad-hoc spinners.

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.6)),
          const SizedBox(height: 12),
          Text(tr('Loading…'), style: Theme.of(context).textTheme.bodySmall),
        ]),
      );
}

class EmptyView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  const EmptyView({super.key, this.icon = Icons.inbox_outlined, required this.title, this.subtitle});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(color: HrBrand.blueContainer, shape: BoxShape.circle),
              child: Icon(icon, size: 34, color: HrBrand.blue),
            ),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
            ],
          ]),
        ),
      );
}

class ErrorRetryView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const ErrorRetryView({super.key, required this.error, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    final offline = error is ApiException && (error as ApiException).network;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: offline ? HrBrand.amberContainer : HrBrand.redContainer, shape: BoxShape.circle),
            child: Icon(offline ? Icons.wifi_off_rounded : Icons.error_outline_rounded, size: 34, color: offline ? HrBrand.amber : HrBrand.red),
          ),
          const SizedBox(height: 16),
          Text(tr('Something went wrong'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(error.toString(), style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
          const SizedBox(height: 18),
          SizedBox(
            width: 160,
            child: FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: Text(tr('Retry'))),
          ),
        ]),
      ),
    );
  }
}

/// White rounded card with the webapp's border + soft shadow.
class HrCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  const HrCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap});
  @override
  Widget build(BuildContext context) {
    final box = Container(
      decoration: BoxDecoration(
        color: HrBrand.card,
        borderRadius: BorderRadius.circular(HrBrand.radiusCard),
        border: Border.all(color: HrBrand.border),
        boxShadow: HrBrand.shadow,
      ),
      padding: padding,
      child: child,
    );
    if (onTap == null) return box;
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: BorderRadius.circular(HrBrand.radiusCard), onTap: onTap, child: box),
    );
  }
}

/// Small status pill: present (green), absent (red), leave (amber), neutral.
class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final Color background;
  const StatusPill({super.key, required this.label, required this.color, required this.background});

  factory StatusPill.success(String label) => StatusPill(label: label, color: const Color(0xFF07945D), background: HrBrand.greenContainer);
  factory StatusPill.danger(String label) => StatusPill(label: label, color: HrBrand.red, background: HrBrand.redContainer);
  factory StatusPill.warning(String label) => StatusPill(label: label, color: const Color(0xFFB26A00), background: HrBrand.amberContainer);
  factory StatusPill.info(String label) => StatusPill(label: label, color: HrBrand.blueDeep, background: HrBrand.blueContainer);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
      );
}

/// Round avatar with initials (or network image when the server has one).
class Avatar extends StatelessWidget {
  final String name;
  final String? url;
  final double size;
  const Avatar({super.key, required this.name, this.url, this.size = 44});
  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().split(RegExp(r'\s+')).take(2).map((p) => p[0].toUpperCase()).join();
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: HrBrand.blueContainer,
      foregroundImage: (url != null && url!.isNotEmpty) ? NetworkImage(url!) : null,
      child: Text(initials, style: TextStyle(fontSize: size * 0.36, fontWeight: FontWeight.w700, color: HrBrand.blueDeep)),
    );
  }
}

void showErr(BuildContext context, Object e) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: HrBrand.red));
}

void showOk(BuildContext context, String msg) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), backgroundColor: const Color(0xFF07945D)));
}

/// "Offline · last updated hh:mm" — shown whenever a screen renders cached
/// data because the network call failed (ARCHITECTURE.md §6).
class OfflineChip extends StatelessWidget {
  final DateTime since;
  const OfflineChip({super.key, required this.since});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: HrBrand.amberContainer, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.wifi_off_rounded, size: 14, color: Color(0xFFB26A00)),
          const SizedBox(width: 6),
          Text(tr('Offline · last updated %s').arg(Fmt.time(since)),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFB26A00))),
        ]),
      );
}
