import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/theme.dart';

/// Shared premium components (ARCHITECTURE.md §5). Every screen composes
/// these — no feature file hand-rolls cards/buttons/spinners.
///
/// SAFETY RULES (learned the hard way in 3.x — see ARCHITECTURE.md §7):
/// * never `Padding` with negative values (assertion crash),
/// * never both `Container(color:)` and `Container(decoration:)`,
/// * only `const` on const-constructible widgets,
/// * no PathMetric / addPolyline / FontFeature.tabularNumbers (Flutter 3.29).

/// Webapp card: white, 16 radius, 1px border, soft shadow; optional press.
class HrCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  const HrCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(14)});

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: HrBrand.card,
        borderRadius: BorderRadius.circular(HrBrand.radiusCard),
        border: Border.all(color: HrBrand.border),
        boxShadow: HrBrand.shadow,
      ),
      child: child,
    );
    if (onTap == null) return box;
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: BorderRadius.circular(HrBrand.radiusCard), onTap: onTap, child: box),
    );
  }
}

/// Primary emerald gradient action (webapp punch/submit buttons).
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
          duration: HrBrand.base,
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

/// Quick-action tile (webapp home tiles): tinted icon, label, value.
class QuickTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? sub; // optional second line under the value
  final Color color;
  final VoidCallback onTap;
  const QuickTile({super.key, required this.icon, required this.label, required this.value, this.sub, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => HrCard(
        onTap: onTap,
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 19, color: color),
          ),
          const SizedBox(height: 10),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: HrBrand.subInk)),
          const SizedBox(height: 2),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: HrBrand.ink)),
          if (sub != null && sub!.isNotEmpty) ...[
            const SizedBox(height: 1),
            Text(sub!, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: HrBrand.faint)),
          ],
        ]),
      );
}

/// KPI tile (webapp KPI grid): label, big value, optional progress bar.
class KpiTile extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final double? bar; // 0..1
  final Color color;
  const KpiTile({super.key, required this.label, required this.value, this.sub, this.bar, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: HrBrand.card,
          borderRadius: BorderRadius.circular(HrBrand.radiusCard),
          border: Border.all(color: HrBrand.border),
          boxShadow: HrBrand.shadow,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: HrBrand.subInk)),
          const SizedBox(height: 3),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: HrBrand.heading,
                  fontFeatures: [FontFeature('tnum')])),
          if (sub != null) ...[
            const SizedBox(height: 1),
            Text(sub!, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10.5, color: HrBrand.faint)),
          ],
          if (bar != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: bar!.clamp(0.0, 1.0).toDouble(),
                minHeight: 6,
                backgroundColor: HrBrand.lineSoft,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ],
        ]),
      );
}

/// Premium centered loading state.
class LoadingView extends StatelessWidget {
  final String? label;
  const LoadingView({super.key, this.label});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(width: 34, height: 34, child: CircularProgressIndicator(strokeWidth: 3)),
          if (label != null) ...[
            const SizedBox(height: 14),
            Text(label!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: HrBrand.subInk)),
          ],
        ]),
      );
}

/// Error + retry (webapp error rows).
class ErrorRetryView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const ErrorRetryView({super.key, required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(color: HrBrand.redContainer, shape: BoxShape.circle),
            child: const Icon(Icons.cloud_off_rounded, size: 26, color: HrBrand.redText),
          ),
          const SizedBox(height: 12),
          Text(tr('Something went wrong'), style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: HrBrand.ink)),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Text('$error', textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: HrBrand.subInk)),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded, size: 17), label: Text(tr('Retry'))),
        ]),
      );
}

/// Honest "arriving in Phase N" body — NO fake data, NO dead buttons.
/// Pages wrap it in their own Scaffold. Replaced (not rewritten) when that
/// phase lands, keeping the tab wired end-to-end from day one.
class PhaseScreen extends StatelessWidget {
  final String title;
  final IconData icon;
  final int phase;
  final List<String> lines;
  const PhaseScreen({super.key, required this.title, required this.icon, required this.phase, this.lines = const []});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 76,
              height: 76,
              decoration: const BoxDecoration(color: HrBrand.blueContainer, shape: BoxShape.circle),
              child: Icon(icon, size: 36, color: HrBrand.blue),
            ),
            const SizedBox(height: 18),
            Text(tr(title), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: HrBrand.heading)),
            const SizedBox(height: 6),
            Text(tr('Coming in Phase %s').arg(phase), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: HrBrand.subInk)),
            if (lines.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(color: HrBrand.tile, borderRadius: BorderRadius.circular(12), border: Border.all(color: HrBrand.lineSoft)),
                child: Column(children: [
                  for (var i = 0; i < lines.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Icon(Icons.check_rounded, size: 14, color: HrBrand.green),
                        const SizedBox(width: 7),
                        Flexible(child: Text(tr(lines[i]), style: const TextStyle(fontSize: 12.5, color: HrBrand.subInk))),
                      ]),
                    ),
                ]),
              ),
            ],
          ]),
        ),
      );
}

/// Initials avatar with optional online dot (webapp user pill).
class Avatar extends StatelessWidget {
  final String name;
  final String? url;
  final double size;
  final bool online;
  const Avatar({super.key, required this.name, this.url, this.size = 32, this.online = false});

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isEmpty
        ? '?'
        : (name.trim().split(RegExp(r'\s+')).map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join('')).substring(0, 2);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [HrBrand.blue, HrBrand.blueDeep], begin: Alignment.topLeft, end: Alignment.bottomRight),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(initials,
              style: TextStyle(fontSize: size * 0.38, fontWeight: FontWeight.w800, color: Colors.white, height: 1)),
        ),
        if (online)
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: size * 0.32,
              height: size * 0.32,
              decoration: const BoxDecoration(color: HrBrand.green, shape: BoxShape.circle, border: Border.all(width: 2, color: Colors.white)),
            ),
          ),
      ]),
    );
  }
}

/// "Offline · last updated hh:mm" chip (ARCHITECTURE §6 offline rule).
class OfflineChip extends StatelessWidget {
  final DateTime since;
  const OfflineChip({super.key, required this.since});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: HrBrand.amberContainer,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: HrBrand.amber.withValues(alpha: 0.35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_rounded, size: 12, color: HrBrand.amberText),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              tr('Offline · last updated %s').arg(
                '${since.hour.toString().padLeft(2, '0')}:${since.minute.toString().padLeft(2, '0')}',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: HrBrand.amberText),
            ),
          ),
        ]),
      );
}

/// Ambient radial glows used on navy surfaces (punch card, login).
class NavyGlow extends StatelessWidget {
  final double size;
  final Color color;
  final Alignment alignment;
  const NavyGlow({super.key, required this.size, required this.color, required this.alignment});

  @override
  Widget build(BuildContext context) => Align(
        alignment: alignment,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [color.withValues(alpha: 0.5), Colors.transparent]),
          ),
        ),
      );
}

/// Shimmer for skeleton loaders — premium touch for first paint.
class Shimmer extends StatefulWidget {
  final double width;
  final double height;
  final double radius;
  const Shimmer({super.key, required this.width, required this.height, this.radius = 10});

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween<double>(begin: 0.35, end: 0.9).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(color: const Color(0xFFE4EAF2), borderRadius: BorderRadius.circular(widget.radius)),
        ),
      );
}

/// Pulse dot for "live" indicators (punch card, team).
class LiveDot extends StatelessWidget {
  const LiveDot({super.key});

  @override
  Widget build(BuildContext context) => const _Pulsing(color: HrBrand.emerald);
}

class _Pulsing extends StatefulWidget {
  final Color color;
  const _Pulsing({required this.color});
  @override
  State<_Pulsing> createState() => _PulsingState();
}

class _PulsingState extends State<_Pulsing> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat(reverse: true);
  late final CurvedAnimation _a = CurvedAnimation(parent: _c, curve: Curves.easeOut);

  @override
  void dispose() {
    _a.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(
        scale: Tween<double>(begin: 0.7, end: 1).animate(_a),
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.5), blurRadius: 6)]),
        ),
      );
}

/// Tabular-nums style for clocks/times (Flutter 3.29-safe: raw feature tag).
const kTnum = [FontFeature('tnum')];

double lerpClamp(double a, double b, double t) => a + (b - a) * t.clamp(0.0, 1.0);

double angleOf(double t) => -math.pi / 2 + t * 2 * math.pi;
