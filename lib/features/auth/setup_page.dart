import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/company.dart';
import '../../core/i18n.dart';
import '../../router.dart' show kNeedsFirstRunSetup;

/// One-time first-run setup (fresh install only): pick the app language and
/// the industry. The industry pre-sets the unit names (Cartons/CB/Trays/…)
/// used across the whole app and on PDFs. After this screen the choice is
/// FIXED — Company details only displays it read-only.
class SetupPage extends StatefulWidget {
  const SetupPage({super.key});
  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  int step = 0; // 0 = language, 1 = industry
  String language = 'en';
  String? industry;
  bool saving = false;

  Future<void> _finish() async {
    if (industry == null) return;
    setState(() => saving = true);
    final row = CompanyProfile.industries.firstWhere((r) => r[0] == industry, orElse: () => CompanyProfile.industries.last);
    final p = CompanyProfile.current;
    await CompanyProfile.save(CompanyProfile(
      name: p.name,
      address: p.address,
      taxLine: p.taxLine,
      industry: row[0],
      cartonLabel: row[2],
      cartonShort: row[3],
      trayLabel: row[4],
      pieceLabel: row[5],
    ));
    await CompanyProfile.markSetupDone();
    kNeedsFirstRunSetup = false;
    if (!mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // brand
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(
                  width: 46, height: 46,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF0A6ED1), Color(0xFF0891B2)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: const Text('FF', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
                ),
                const SizedBox(width: 12),
                Text('FlavorFlow ERP', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: scheme.onSurface, letterSpacing: -0.3)),
              ]),
              const SizedBox(height: 8),
              Center(
                child: Text(step == 0 ? 'Welcome! · ਜੀ ਆਇਆਂ ਨੂੰ! · स्वागत है!' : 'One last step',
                    style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
              ),
              const SizedBox(height: 26),

              if (step == 0) ...[
                Text('Choose your language', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: scheme.onSurface)),
                const SizedBox(height: 4),
                Text('ਆਪਣੀ ਭਾਸ਼ਾ ਚੁਣੋ · अपनी भाषा चुनें', style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 14),
                for (final lang in L10n.languages)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _ChoiceTile(
                      selected: language == lang[0],
                      title: lang[1],
                      onTap: () => setState(() => language = lang[0]),
                    ),
                  ),
                const SizedBox(height: 14),
                FilledButton(
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: () async {
                    await L10n.instance.set(language);
                    setState(() => step = 1);
                  },
                  child: const Text('Continue'),
                ),
              ] else ...[
                Text(tr('Choose your industry'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: scheme.onSurface)),
                const SizedBox(height: 4),
                Text(
                  'Unit names (${CompanyProfile.industries.first[2]}, ${CompanyProfile.industries.first[4]}…) are set as per your industry. This cannot be changed later.',
                  style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: industry,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Industry *'),
                  hint: const Text('Select your industry'),
                  items: [
                    for (final r in CompanyProfile.industries)
                      DropdownMenuItem(value: r[0], child: Text(r[1], overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => industry = v),
                ),
                if (industry != null) ...[
                  const SizedBox(height: 10),
                  Builder(builder: (context) {
                    final r = CompanyProfile.industries.firstWhere((x) => x[0] == industry, orElse: () => CompanyProfile.industries.last);
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
                      ),
                      child: Text('Units: ${r[2]} (${r[3]}) · ${r[4]} · ${r[5]}',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: scheme.onSurface)),
                    );
                  }),
                ],
                const SizedBox(height: 14),
                Row(children: [
                  TextButton(onPressed: () => setState(() => step = 0), child: const Text('Back')),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      onPressed: (industry == null || saving) ? null : _finish,
                      child: Text(saving ? 'Setting up…' : 'Finish setup'),
                    ),
                  ),
                ]),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  final bool selected;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  const _ChoiceTile({required this.selected, required this.title, this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer.withValues(alpha: 0.45) : null,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 1.6 : 1),
        ),
        child: Row(children: [
          Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              size: 20, color: selected ? scheme.primary : scheme.outline),
          const SizedBox(width: 11),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: scheme.onSurface)),
              if (subtitle != null)
                Text(subtitle!, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            ]),
          ),
        ]),
      ),
    );
  }
}
