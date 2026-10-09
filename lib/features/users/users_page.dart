import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/company.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/i18n.dart';
import '../../core/app_permissions.dart';
import '../../state/auth.dart';
import '../../ui/widgets.dart';

/// User Management — Super Admin & Admin. Create/edit users, assign roles,
/// deactivate accounts. Server enforces additional safeguards.
class UsersPage extends StatefulWidget {
  const UsersPage({super.key});
  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final json = await context.read<AuthController>().api.get('/users');
    return (json as Map).cast<String, dynamic>();
  }

  /// Show the user's OWN custom permissions when the server returns a
  /// non-empty list — otherwise the role defaults. Compares the stored set
  /// with the role defaults so "custom" really means different-from-default.
  Widget _permsCell(Map<String, dynamic> u, Map<String, dynamic>? role) {
    final own = u['permissions'];
    final rolePerms = (role?['permissions'] as List?) ?? const [];
    final bool isCustom;
    final List<String> list;
    if (own is List && own.isNotEmpty) {
      list = own.map((x) => x.toString()).toList()..sort();
      final ownSet = list.toSet();
      final defSet = rolePerms.map((x) => x.toString()).toSet();
      isCustom = ownSet.length != defSet.length || !ownSet.containsAll(defSet);
    } else {
      list = List<String>.from(rolePerms);
      isCustom = false;
    }
    return Tooltip(
      message: list.isEmpty ? 'no permissions' : list.join('\n'),
      child: Text(
        isCustom ? '${list.length} custom' : '${list.length} default',
        style: TextStyle(color: isCustom ? AppColors.violet : AppColors.slate, fontWeight: FontWeight.w600),
      ),
    );
  }

  void _reload() { _future = _load(); setState(() {}); }

  Future<void> _deleteUser(Map<String, dynamic> u) async {
    // Safely extract values first, before any async gap
    final uid = u['id'];
    final name = (u['name'] ?? 'User').toString();
    final email = (u['email'] ?? '').toString();
    if (uid == null) {
      if (mounted) showErr(context, 'Invalid user id.');
      return;
    }
    if (!mounted) return;
    bool ok = false;
    try {
      ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(tr('Delete user permanently?')),
              content: Text('$name ($email) will be permanently deleted.\n\nReports and audit entries will be kept with name shown as "[deleted]".'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.red),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Delete permanently'),
                ),
              ],
            ),
          ) ??
          false;
    } catch (_) {
      ok = false;
    }
    if (!ok || !mounted) return;
    try {
      await context.read<AuthController>().api.delete('/users/$uid');
      if (!mounted) return;
      _reload();
      if (mounted) {
        try {
          showOk(context, 'User "$name" deleted.');
        } catch (_) {}
      }
    } catch (e, st) {
      print('DELETE ERR: $e\n$st');
      if (!mounted) return;
      try {
        showErr(context, e is Exception ? e : Exception('$e'));
      } catch (_) {
        try {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Delete failed: $e'), backgroundColor: AppColors.red, duration: const Duration(seconds: 4)),
          );
        } catch (_) {}
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final canManage = auth.can('users.manage');
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return ErrorState(snap.error!, onRetry: _reload);
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final users = (snap.data!['users'] as List).cast<Map<String, dynamic>>();
        final roles = (snap.data!['roles'] as List).cast<Map<String, dynamic>>();
        final roleMap = {for (final r in roles) r['id'] as String: r};
        return ListView(padding: const EdgeInsets.all(20), children: [
          Row(children: [
            Expanded(child: Text('${users.length} ${tr('accounts · each role has its own dashboard & permissions')}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
            if (canManage)
              FilledButton.icon(
                onPressed: () async {
                  final saved = await showDialog<bool>(context: context, builder: (_) => UserFormDialog(roles: roles));
                  if (saved == true) _reload();
                },
                icon: const Icon(Icons.person_add_alt_rounded, size: 19),
                label: Text(tr('Add User')),
              ),
          ]),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Users & Roles',
            child: AppDataTable(
              columns: ['User', 'Email', 'Role', 'Status', 'Created', 'Permissions', if (canManage) ''],
              rows: [
                for (final u in users)
                  [
                    Text(u['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                    u['email'],
                    _RoleChip(role: roleMap[u['role']]),
                    (u['active'] as int) == 1 ? const StatusChip('ACTIVE') : const StatusChip('INACTIVE'),
                    fmtDate(u['created_at']),
                    _permsCell(u, roleMap[u['role']]),
                    if (canManage)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 19),
                          tooltip: 'Edit user',
                          onPressed: () async {
                            final saved = await showDialog<bool>(context: context, builder: (_) => UserFormDialog(roles: roles, user: u));
                            if (saved == true) _reload();
                          },
                        ),
                        // Don't let a user delete themselves (would lock super admin out)
                        if (u['id'] != context.read<AuthController>().session?.id)
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, size: 19, color: AppColors.red),
                            tooltip: 'Delete permanently',
                            onPressed: () => _deleteUser(u),
                          ),
                      ]),
                  ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Role Permission Matrix',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Grouped by module for better readability — auto-registers new permissions
                for (final group in kPermissionGroups) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                    child: Row(children: [
                      Icon(_iconForGroup(group.icon), size: 16, color: AppColors.slate),
                      const SizedBox(width: 6),
                      Text(group.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                      const SizedBox(width: 8),
                      Text('(${group.permissions.length} perms)', style: TextStyle(fontSize: 11, color: AppColors.slate)),
                    ]),
                  ),
                  AppDataTable(
                    columns: const ['Role', 'Permissions'],
                    rows: [
                      for (final r in roles)
                        [
                          _RoleChip(role: r),
                          Builder(builder: (_) {
                            final rolePerms = (r['permissions'] as List).map((e) => e.toString()).toSet();
                            final groupPerms = group.permissions.where((p) => rolePerms.contains(p.key)).map((p) => p.key).toList();
                            if (groupPerms.isEmpty) return Text('—', style: TextStyle(color: AppColors.slate));
                            return Wrap(
                              spacing: 4,
                              runSpacing: 2,
                              children: groupPerms.map((k) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: AppColors.green.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                                child: Text(k.split('.').last, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
                              )).toList(),
                            );
                          }),
                        ],
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                const Divider(),
                const SizedBox(height: 8),
                Text('All Permissions (flat):', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.slate)),
                const SizedBox(height: 4),
                AppDataTable(
                  columns: const ['Role', 'Permissions'],
                  rows: [
                    for (final r in roles)
                      [
                        _RoleChip(role: r),
                        Text((r['permissions'] as List).where((p) => CompanyProfile.usesLossPct || !'$p'.startsWith('loss.')).join(' · ')),
                      ],
                  ],
                ),
              ],
            ),
          ),
        ]);
      },
    );
  }
}

class _RoleChip extends StatelessWidget {
  final Map<String, dynamic>? role;
  const _RoleChip({this.role});
  @override
  Widget build(BuildContext context) {
    if (role == null) return const Text('—');
    final color = hexColor(role!['color'] as String?);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(7)),
      child: Text(role!['label'] as String, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
    );
  }
}

class UserFormDialog extends StatefulWidget {
  final List<Map<String, dynamic>> roles;
  final Map<String, dynamic>? user;
  const UserFormDialog({super.key, required this.roles, this.user});
  @override
  State<UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<UserFormDialog> {
  late final TextEditingController name = TextEditingController(text: widget.user?['name']?.toString() ?? '');
  late final TextEditingController email = TextEditingController(text: widget.user?['email']?.toString() ?? '');
  final password = TextEditingController();
  late String role = widget.user?['role']?.toString() ?? 'store_keeper';
  late bool active = (widget.user?['active'] as int? ?? 1) == 1;
  late Set<String> customPerms = _defaultPermsFor(role);
  bool busy = false;

  Set<String> _defaultPermsFor(String roleId) {
    final r = widget.roles.firstWhere((x) => x['id'] == roleId, orElse: () => <String, dynamic>{});
    return Set<String>.from((r['permissions'] as List?) ?? const []);
  }

  @override
  void initState() {
    super.initState();
    if (widget.user != null) {
      // Editing: load existing user's custom permissions if present (server returns JSON array)
      final up = widget.user!['permissions'];
      if (up is List && up.isNotEmpty) {
        customPerms = Set<String>.from(up.map((x) => x.toString()));
      }
    }
  }

  Future<void> _save() async {
    setState(() => busy = true);
    final api = context.read<AuthController>().api;
    try {
      if (widget.user == null) {
        await api.post('/users', {
          'name': name.text.trim(),
          'email': email.text.trim(),
          'password': password.text,
          'role': role,
          'permissions': customPerms.toList(),
        });
      } else {
        await api.put('/users/${widget.user!['id']}', {
          'name': name.text.trim(),
          'role': role,
          'active': active,
          'permissions': customPerms.toList(),
          if (password.text.isNotEmpty) 'password': password.text,
        });
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showErr(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.user != null;
    return AlertDialog(
      title: Text(editing ? 'Edit User' : 'Add User'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: InputDecoration(labelText: tr('Full name *'))),
          const SizedBox(height: 12),
          TextField(controller: email, enabled: !editing, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: tr('Email *'))),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: role,
            decoration: InputDecoration(labelText: tr('Role *')),
            items: [
              for (final r in widget.roles)
                DropdownMenuItem(value: r['id'] as String, child: Text(r['label'] as String)),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() {
                role = v;
                customPerms = _defaultPermsFor(v);
              });
            },
          ),
          const SizedBox(height: 8),
          // Permissions — grouped by module, auto-registers new permissions from kPermissionGroups
          // Super Admin gets all, others default-deny for new perms until explicitly granted
          Builder(
            builder: (ctx) {
              final r = widget.roles.firstWhere((x) => x['id'] == role, orElse: () => <String, dynamic>{});
              final color = hexColor(r['color'] as String? ?? '#4f46e5');
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      _RoleChip(role: r),
                      const SizedBox(width: 8),
                      const Expanded(child: Text(
                        'permissions (tap to toggle, grouped by module):',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                        softWrap: true,
                      )),
                      TextButton(
                        onPressed: () => setState(() => customPerms = _defaultPermsFor(role)),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          minimumSize: const Size(0, 28),
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text('Reset', style: TextStyle(fontSize: 11)),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    // Grouped by module — auto-registers new sections
                    for (final group in kPermissionGroups) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 10, bottom: 4),
                        child: Row(children: [
                          Icon(_iconForGroup(group.icon), size: 14, color: color),
                          const SizedBox(width: 5),
                          Text(group.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color)),
                          const SizedBox(width: 6),
                          Text('(${group.permissions.length})', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                          if (group.id == 'super_admin' || role == 'super_admin')
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(color: AppColors.green.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(3)),
                                child: const Text('ALL', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: AppColors.green)),
                              ),
                            ),
                        ]),
                      ),
                      Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: [
                          for (final perm in group.permissions.where((p) => CompanyProfile.usesLossPct || !p.key.startsWith('loss.')))
                            FilterChip(
                              label: Tooltip(
                                message: perm.description,
                                child: Text(perm.key.split('.').last, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600)),
                              ),
                              selected: customPerms.contains(perm.key),
                              onSelected: (v) => setState(() {
                                if (v) { customPerms.add(perm.key); } else { customPerms.remove(perm.key); }
                              }),
                              selectedColor: color.withValues(alpha: 0.25),
                              checkmarkColor: color,
                              labelStyle: TextStyle(color: customPerms.contains(perm.key) ? color : Colors.grey[700], fontSize: 10.5, fontWeight: FontWeight.w600),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: password,
            obscureText: true,
            decoration: InputDecoration(labelText: editing ? 'Reset password (leave blank to keep)' : 'Password *', hintText: 'min 6 characters'),
          ),
          if (editing) ...[
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Account active')),
              subtitle: Text(tr('Deactivated users lose access immediately')),
              value: active,
              onChanged: (v) => setState(() => active = v),
            ),
          ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: busy ? null : _save, child: Text(busy ? 'Saving…' : 'Save')),
      ],
    );
  }
}

IconData _iconForGroup(String name) {
  switch (name) {
    case 'dashboard': return Icons.dashboard_outlined;
    case 'inventory_2': return Icons.inventory_2_outlined;
    case 'warehouse': return Icons.warehouse_outlined;
    case 'history': return Icons.history_outlined;
    case 'widgets': return Icons.widgets_outlined;
    case 'science': return Icons.science_outlined;
    case 'percent': return Icons.percent_rounded;
    case 'manufacturing': return Icons.precision_manufacturing_outlined;
    case 'local_shipping': return Icons.local_shipping_outlined;
    case 'tune': return Icons.tune_outlined;
    case 'fact_check': return Icons.fact_check_outlined;
    case 'bar_chart': return Icons.bar_chart_rounded;
    case 'analytics': return Icons.analytics_outlined;
    case 'receipt_long': return Icons.receipt_long_outlined;
    case 'group': return Icons.group_outlined;
    case 'settings': return Icons.settings_outlined;
    case 'notifications': return Icons.notifications_outlined;
    default: return Icons.widgets_outlined;
  }
}
