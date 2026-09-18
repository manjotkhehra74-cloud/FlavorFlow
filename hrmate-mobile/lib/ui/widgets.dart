import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/i18n.dart';
import '../core/theme.dart';

/// Shared building blocks. Every screen uses THESE for loading / empty /
/// error states (ARCHITECTURE.md §6) — never ad-hoc spinners.
/// Phase 7: webapp card style (radius 16, soft blue-tinted shadow), badge
/// tones, dashed empty state, page header, emerald gradient button.

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

/// Webapp-style empty state: dashed rounded-16 box, icon, title, subtitle.
class EmptyView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  const EmptyView({super.key, this.icon = Icons.inbox_outlined, required this.title, this.subtitle});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Stack(children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
                decoration: BoxDecoration(color: HrBrand.card, borderRadius: BorderRadius.circular(HrBrand.radiusCard)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(color: HrBrand.blueContainer, borderRadius: BorderRadius.circular(16)),
                    child: Icon(icon, size: 26, color: HrBrand.blue),
                  ),
                  const SizedBox(height: 14),
                  Text(title, style: Theme.of(context).textTheme.titleSmall, textAlign: TextAlign.center),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(subtitle!, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
                  ],
                ]),
              ),
              const Positioned.fill(child: const CustomPaint(painter: const _DashedRect(radius: HrBrand.radiusCard))),
            ]),
          ),
        ),
      );
}

class _DashedRect extends CustomPainter {
  final double radius;
  const _DashedRect({required this.radius});
  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 1.4;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = HrBrand.inputBorder;
    final w = size.width;
    final h = size.height;
    final x0 = stroke / 2;
    final y0 = stroke / 2;
    final x1 = w - stroke / 2;
    final y1 = h - stroke / 2;
    if (x1 <= x0 || y1 <= y0) return;
    final r = radius.clamp(0.0, math.min(w, h) / 2);
    const dash = 6.0;
    const gap = 6.0;
    final step = dash + gap;
    void dashH(double y, double xFrom, double xTo) {
      var x = math.min(xFrom, xTo);
      final to = math.max(xFrom, xTo);
      while (x < to) {
        final xe = math.min(x + dash, to);
        canvas.drawLine(Offset(x, y), Offset(xe, y), paint);
        x += step;
      }
    }

    void dashV(double x, double yFrom, double yTo) {
      var y = math.min(yFrom, yTo);
      final to = math.max(yFrom, yTo);
      while (y < to) {
        final ye = math.min(y + dash, to);
        canvas.drawLine(Offset(x, y), Offset(x, ye), paint);
        y += step;
      }
    }

    // Straight edges as dashes, corners as solid quarter arcs.
    dashH(y0, x0 + r, x1 - r);
    dashH(y1, x0 + r, x1 - r);
    dashV(x0, y0 + r, y1 - r);
    dashV(x1, y0 + r, y1 - r);
    canvas.drawArc(Rect.fromCircle(center: Offset(x0 + r, y0 + r), radius: r), math.pi, math.pi / 2, false, paint);
    canvas.drawArc(Rect.fromCircle(center: Offset(x1 - r, y0 + r), radius: r), math.pi * 1.5, math.pi / 2, false, paint);
    canvas.drawArc(Rect.fromCircle(center: Offset(x1 - r, y1 - r), radius: r), 0, math.pi / 2, false, paint);
    canvas.drawArc(Rect.fromCircle(center: Offset(x0 + r, y1 - r), radius: r), math.pi / 2, math.pi / 2, false, paint);
  }

  @override
  bool shouldRepaint(covariant _DashedRect old) => old.radius != radius;
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

/// Small status pill — the webapp's badge tones
/// (green #E1F8EF/#06613E · amber #FFF4E0/#D98200 · red #FDECEC/#C52B35 · blue #E7F1FF/#1556B8).
class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final Color background;
  const StatusPill({super.key, required this.label, required this.color, required this.background});

  factory StatusPill.success(String label) => StatusPill(label: label, color: HrBrand.greenText, background: HrBrand.greenContainer);
  factory StatusPill.danger(String label) => StatusPill(label: label, color: HrBrand.redText, background: HrBrand.redContainer);
  factory StatusPill.warning(String label) => StatusPill(label: label, color: HrBrand.amberText, background: HrBrand.amberContainer);
  factory StatusPill.info(String label) => StatusPill(label: label, color: HrBrand.blueDeep, background: HrBrand.blueContainer);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999)),
        child: Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
      );
}

/// Round avatar with initials (or network image when the server has one).
/// `online` adds the webapp's green presence dot.
class Avatar extends StatelessWidget {
  final String name;
  final String? url;
  final double size;
  final bool online;
  const Avatar({super.key, required this.name, this.url, this.size = 44, this.online = false});
  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().split(RegExp(r'\s+')).take(2).map((p) => p[0].toUpperCase()).join();
    final circle = CircleAvatar(
      radius: size / 2,
      backgroundColor: HrBrand.blueContainer,
      foregroundImage: (url != null && url!.isNotEmpty) ? NetworkImage(url!) : null,
      child: Text(initials, style: TextStyle(fontSize: size * 0.36, fontWeight: FontWeight.w700, color: HrBrand.blueDeep)),
    );
    if (!online) return circle;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        circle,
        Positioned(
          bottom: 0,
          right: 0,
          child: Container(
            width: size * 0.3,
            height: size * 0.3,
            decoration: BoxDecoration(color: HrBrand.emerald, shape: BoxShape.circle, border: Border.all(color: HrBrand.card, width: 2)),
          ),
        ),
      ],
    );
  }
}

/// Webapp page header: tinted icon square + bold title + muted subtitle.
class PageHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  const PageHeader({super.key, required this.icon, required this.title, this.subtitle});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: HrBrand.blueContainer, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 20, color: HrBrand.blueDeep),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: HrBrand.heading)),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 1),
                Text(subtitle!, style: const TextStyle(fontSize: 12.5, color: HrBrand.subInk)),
              ],
            ]),
          ),
        ]),
      );
}

/// Full-width emerald gradient action (punch card, login biometric, home
/// "Apply Leave") — the webapp's primary gradient button.
class HrGradientButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final double height;
  const HrGradientButton({super.key, required this.label, this.icon, this.onPressed, this.height = 50});

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: enabled ? onPressed : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: enabled ? 1 : 0.45,
          child: Container(
            height: height,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: HrBrand.punchButtonGradient, begin: Alignment.centerLeft, end: Alignment.centerRight),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: HrBrand.emeraldLight.withValues(alpha: 0.3)),
              boxShadow: HrBrand.shadowPunch,
            ),
            child: Center(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) Icon(icon, size: 19, color: Colors.white),
                if (icon != null) const SizedBox(width: 8),
                Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Blurred-look ambient glow on navy surfaces (radial fade, no filters).
class NavyGlow extends StatelessWidget {
  final Color color;
  final double size;
  final double? top;
  final double? right;
  final double? bottom;
  final double? left;
  const NavyGlow({super.key, required this.color, required this.size, this.top, this.right, this.bottom, this.left});
  @override
  Widget build(BuildContext context) => Positioned(
        top: top,
        right: right,
        bottom: bottom,
        left: left,
        child: IgnorePointer(
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [color.withValues(alpha: 0.16), color.withValues(alpha: 0)]),
            ),
          ),
        ),
      );
}

/// Translucent pill on navy surfaces (facility "geofence verified", clock).
class NavyPill extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  final Color background;
  final Color border;
  final Color? iconColor;
  final double iconSize;
  const NavyPill({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
    required this.background,
    required this.border,
    this.iconColor,
    this.iconSize = 12,
  });
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(999), border: Border.all(color: border)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: iconSize, color: iconColor ?? color),
          const SizedBox(width: 5),
          Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ]),
      );
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
          const Icon(Icons.wifi_off_rounded, size: 14, color: HrBrand.amberText),
          const SizedBox(width: 6),
          Text(tr('Offline · last updated %s').arg(Fmt.time(since)),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: HrBrand.amberText)),
        ]),
      );
}
