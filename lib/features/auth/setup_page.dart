import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/company.dart';
import '../../core/i18n.dart';
import '../../core/permissions.dart';
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
    // Ask ALL app permissions in one flow right after setup (like big apps).
    await AppPermissions.requestAllOnce();
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
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  clipBehavior: Clip.antiAlias,
                  alignment: Alignment.center,
                  child: Image.asset('assets/icon/app_icon.png', fit: BoxFit.cover),
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
                DropdownButtonFormField<String>(
                  initialValue: language,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: tr('Language / ਭਾਸ਼ਾ / भाषा *')),
                  items: [
                    for (final lang in L10n.languages)
                      DropdownMenuItem(value: lang[0], child: Text(lang[1])),
                  ],
                  onChanged: (v) => setState(() => language = v ?? 'en'),
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
                  decoration: InputDecoration(labelText: tr('Industry *')),
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

