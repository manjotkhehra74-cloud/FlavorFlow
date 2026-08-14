import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
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

  void _reload() => setState(() => _future = _load());

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
            Expanded(child: Text('${users.length} accounts · each role has its own dashboard & permissions', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
            if (canManage)
              FilledButton.icon(
                onPressed: () async {
                  final saved = await showDialog<bool>(context: context, builder: (_) => UserFormDialog(roles: roles));
                  if (saved == true) _reload();
                },
                icon: const Icon(Icons.person_add_alt_rounded, size: 19),
                label: const Text('Add User'),
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
                    Text('${(roleMap[u['role']]?['permissions'] as List?)?.length ?? 0} permissions'),
                    if (canManage)
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 19),
                        tooltip: 'Edit user',
                        onPressed: () async {
                          final saved = await showDialog<bool>(context: context, builder: (_) => UserFormDialog(roles: roles, user: u));
                          if (saved == true) _reload();
                        },
                      ),
                  ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Role Permission Matrix',
            child: AppDataTable(
              columns: const ['Role', 'Permissions'],
              rows: [
                for (final r in roles)
                  [
                    _RoleChip(role: r),
                    Text((r['permissions'] as List).join(' · ')),
                  ],
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
  bool busy = false;

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
        });
      } else {
        await api.put('/users/${widget.user!['id']}', {
          'name': name.text.trim(),
          'role': role,
          'active': active,
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
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Full name *')),
          const SizedBox(height: 12),
          TextField(controller: email, enabled: !editing, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email *')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: role,
            decoration: const InputDecoration(labelText: 'Role *'),
            items: [
              for (final r in widget.roles)
                DropdownMenuItem(value: r['id'] as String, child: Text(r['label'] as String)),
            ],
            onChanged: (v) => setState(() => role = v ?? role),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: password,
            obscureText: true,
            decoration: InputDecoration(labelText: editing ? 'Reset password (leave blank to keep)' : 'Password *', hintText: 'min 6 characters'),
          ),
          if (editing) ...[
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Account active'),
              subtitle: const Text('Deactivated users lose access immediately'),
              value: active,
              onChanged: (v) => setState(() => active = v),
            ),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: busy ? null : _save, child: Text(busy ? 'Saving…' : 'Save')),
      ],
    );
  }
}
