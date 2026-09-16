import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/cache.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';
import 'more_models.dart';

/// Holidays — `GET holidays?year=`; upcoming first, past ones greyed below.
class HolidaysPage extends StatefulWidget {
  const HolidaysPage({super.key});
  @override
  State<HolidaysPage> createState() => _HolidaysPageState();
}

class _HolidaysPageState extends State<HolidaysPage> {
  int _year = DateTime.now().year;
  Cached<List<Holiday>>? _items;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AuthController>().api;
    try {
      final items = await cachedFetch('holidays:$_year', () => api.get('/holidays', query: {'year': '$_year'}), Holiday.listFromJson);
      if (!mounted) return;
      setState(() {
        _items = items;
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

  void _setYear(int y) {
    setState(() {
      _year = y;
      _items = null;
      _loading = true;
      _error = null;
    });
    _load();
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
    } else {
      final upcoming = cached.data.where((h) => !h.past).toList();
      final past = cached.data.where((h) => h.past).toList();
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
            if (cached.data.isEmpty)
              EmptyView(icon: Icons.celebration_outlined, title: tr('No holidays published for %s').arg(_year))
            else ...[
              if (upcoming.isNotEmpty) ...[
                Text(tr('Upcoming'), style: t.titleMedium),
                const SizedBox(height: 10),
                HrCard(padding: EdgeInsets.zero, child: Column(children: [for (var i = 0; i < upcoming.length; i++) ...[if (i > 0) const Divider(), _HolidayRow(holiday: upcoming[i])]])),
                const SizedBox(height: 20),
              ],
              if (past.isNotEmpty) ...[
                Text(tr('Past'), style: t.titleMedium),
                const SizedBox(height: 10),
                Opacity(
                  opacity: 0.6,
                  child: HrCard(padding: EdgeInsets.zero, child: Column(children: [for (var i = 0; i < past.length; i++) ...[if (i > 0) const Divider(), _HolidayRow(holiday: past[i])]])),
                ),
              ],
            ],
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Holidays')),
        actions: [
          IconButton(onPressed: () => _setYear(_year - 1), icon: const Icon(Icons.chevron_left_rounded)),
          Center(child: Text('$_year', style: t.titleMedium)),
          IconButton(onPressed: _year >= DateTime.now().year + 1 ? null : () => _setYear(_year + 1), icon: const Icon(Icons.chevron_right_rounded)),
          const SizedBox(width: 4),
        ],
      ),
      body: body,
    );
  }
}

class _HolidayRow extends StatelessWidget {
  final Holiday holiday;
  const _HolidayRow({required this.holiday});

  @override
  Widget build(BuildContext context) {
    final h = holiday;
    final t = Theme.of(context).textTheme;
    return ListTile(
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(color: HrBrand.blueContainer, borderRadius: BorderRadius.circular(10)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('${h.date.day}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: HrBrand.blueDeep, height: 1.1)),
          Text(Fmt.dateShort(h.date).split(' ').last.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: HrBrand.blueDeep)),
        ]),
      ),
      title: Text(h.name, style: t.titleMedium),
      subtitle: Text(Fmt.weekday(h.date), style: t.bodySmall),
      trailing: h.optional ? StatusPill.warning(tr('Optional')) : null,
    );
  }
}
