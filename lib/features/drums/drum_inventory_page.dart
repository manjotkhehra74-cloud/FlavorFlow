import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/auth.dart';

class DrumInventoryPage extends StatefulWidget {
  const DrumInventoryPage({super.key});

  @override
  State<DrumInventoryPage> createState() => _DrumInventoryPageState();
}

class _DrumInventoryPageState extends State<DrumInventoryPage> {
  late Future<void> _loading;
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _plants = [];
  List<Map<String, dynamic>> _stock = [];
  List<Map<String, dynamic>> _fills = [];
  List<Map<String, dynamic>> _dispatches = [];
  final Set<int> _selectedFillIds = {};
  final TextEditingController _truckController = TextEditingController();
  int? _dispatchPlantId;
  DateTime _dispatchAt = DateTime.now();
  bool _submittingDispatch = false;

  @override
  void initState() {
    super.initState();
    _loading = _load();
  }

  @override
  void dispose() {
    _truckController.dispose();
    super.dispose();
  }

  bool _canViewDispatch(AuthController auth) => auth.can('dispatch.view') || auth.can('dispatch.manage');

  List<Map<String, dynamic>> _rows(dynamic json, String key) {
    if (json is! Map) return <Map<String, dynamic>>[];
    final value = json[key];
    if (value is! List) return <Map<String, dynamic>>[];
    return value.whereType<Map>().map((row) => row.cast<String, dynamic>()).toList();
  }

  Future<void> _load() async {
    final auth = context.read<AuthController>();
    final requests = <Future<dynamic>>[
      auth.api.get('/drums/products'),
      auth.api.get('/drums/plants'),
      auth.api.get('/drums/stock'),
      auth.api.get('/drums/fills?status=ALL'),
    ];
    final canViewDispatch = _canViewDispatch(auth);
    if (canViewDispatch) requests.add(auth.api.get('/drums/dispatches'));
    final values = await Future.wait(requests);
    _products = _rows(values[0], 'products');
    _plants = _rows(values[1], 'plants');
    _stock = _rows(values[2], 'stock');
    _fills = _rows(values[3], 'fills');
    _dispatches = canViewDispatch ? _rows(values[4], 'dispatches') : <Map<String, dynamic>>[];
    if (_dispatchPlantId == null && _plants.isNotEmpty) {
      _dispatchPlantId = _asInt(_plants.first['id']);
    }
    final availableIds = _fills
        .where((fill) => _upper(fill['status']) == 'AVAILABLE')
        .map((fill) => _asInt(fill['id']))
        .whereType<int>()
        .toSet();
    _selectedFillIds.removeWhere((id) => !availableIds.contains(id));
  }

  void _reload() {
    if (!mounted) return;
    setState(() => _loading = _load());
  }

  Future<void> _addProduct() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _DrumProductDialog(
        onSave: (name, code, months) async {
          await context.read<AuthController>().api.post('/drums/products', {
            'name': name,
            'code': code,
            'shelfLifeMonths': months,
          });
        },
      ),
    );
    if (saved == true) _reload();
  }

  Future<void> _editShelfLife(Map<String, dynamic> product) async {
    final id = _asInt(product['id']);
    if (id <= 0) return;
    final months = await showDialog<int>(
      context: context,
      builder: (_) => _ShelfLifeDialog(initialMonths: _asInt(product['shelf_life_months'])),
    );
    if (months == null) return;
    try {
      await context.read<AuthController>().api.put('/drums/products/$id', {'shelfLifeMonths': months});
      _reload();
      if (mounted) _showMessage('Shelf life updated for future batches. Existing batch expiry dates stay unchanged.');
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    }
  }

  Future<void> _addPlant() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _PlantDialog(
        onSave: (name) async {
          await context.read<AuthController>().api.post('/drums/plants', {'name': name});
        },
      ),
    );
    if (saved == true) _reload();
  }

  Future<void> _addFilledDrums() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _CreateDrumFillDialog(
        products: _products.where((p) => _asInt(p['active']) != 0).toList(),
        plants: _plants.where((p) => _asInt(p['active']) != 0).toList(),
        onSave: (body) async => context.read<AuthController>().api.post('/drums/fills', body),
      ),
    );
    if (saved == true) {
      _reload();
      if (mounted) _showMessage('Filled drum records saved.');
    }
  }

  Future<void> _chooseDispatchDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _dispatchAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _dispatchAt = DateTime(
        selected.year,
        selected.month,
        selected.day,
        _dispatchAt.hour,
        _dispatchAt.minute,
      );
    });
  }

  Future<void> _chooseDispatchTime() async {
    final selected = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_dispatchAt));
    if (selected == null || !mounted) return;
    setState(() {
      _dispatchAt = DateTime(
        _dispatchAt.year,
        _dispatchAt.month,
        _dispatchAt.day,
        selected.hour,
        selected.minute,
      );
    });
  }

  Future<void> _submitDispatch() async {
    final auth = context.read<AuthController>();
    final truck = _truckController.text.trim();
    if (_dispatchPlantId == null) {
      _showMessage('Add or select a source plant first.');
      return;
    }
    if (truck.isEmpty) {
      _showMessage('Enter the truck number.');
      return;
    }
    if (_selectedFillIds.isEmpty) {
      _showMessage('Select at least one available drum.');
      return;
    }
    setState(() => _submittingDispatch = true);
    try {
      await auth.api.post('/drums/dispatches', {
        'plantId': _dispatchPlantId,
        'truckNumber': truck,
        'dispatchDateTime': _isoWithOffset(_dispatchAt),
        'fillIds': _selectedFillIds.toList()..sort(),
      });
      _selectedFillIds.clear();
      _truckController.clear();
      _reload();
      if (mounted) _showMessage('Outbound dispatch to Neemrana recorded.');
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    } finally {
      if (mounted) setState(() => _submittingDispatch = false);
    }
  }

  Future<void> _showDispatchDetails(Map<String, dynamic> row) async {
    final id = _asInt(row['id']);
    final future = context.read<AuthController>().api.get('/drums/dispatches/$id');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Dispatch · ${_text(row['truck_number'])}'),
        content: SizedBox(
          width: 560,
          child: FutureBuilder<dynamic>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.hasError) return Text(snapshot.error.toString());
              if (!snapshot.hasData) return const SizedBox(height: 90, child: Center(child: CircularProgressIndicator()));
              final data = snapshot.data;
              final dispatch = data is Map && data['dispatch'] is Map
                  ? (data['dispatch'] as Map).cast<String, dynamic>()
                  : row;
              final drums = data is Map && data['drums'] is List
                  ? (data['drums'] as List).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList()
                  : <Map<String, dynamic>>[];
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${_text(dispatch['plant_name'])} → ${_text(dispatch['destination'])}'),
                    Text('Date/time: ${_dateTimeLabel(dispatch['dispatch_datetime'])}'),
                    Text('Drums: ${_text(dispatch['drum_count'])}  ·  Gross weight: ${_weightLabel(dispatch['gross_weight_kg'])}'),
                    const Divider(height: 24),
                    for (final drum in drums)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('Drum ${_text(drum['fill_number'])} · ${_text(drum['product_name'])}'),
                        subtitle: Text('Batch ${_text(drum['batch_code'])} · expires ${_dateLabel(drum['expiry_date'])}'),
                        trailing: Text(_weightLabel(drum['gross_weight_kg'])),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close'))],
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  List<Tab> _tabs(AuthController auth) => [
        const Tab(text: 'Available stock'),
        const Tab(text: 'Filled drums'),
        if (_canViewDispatch(auth)) const Tab(text: 'Outbound dispatch'),
        if (_canViewDispatch(auth)) const Tab(text: 'Dispatch history'),
      ];

  List<Widget> _tabViews(AuthController auth) => [
        _buildStockTab(),
        _buildFillsTab(auth),
        if (_canViewDispatch(auth)) _buildDispatchTab(auth),
        if (_canViewDispatch(auth)) _buildHistoryTab(),
      ];

  Widget _buildStockTab() {
    if (_stock.isEmpty) {
      return const _EmptyPanel(message: 'No filled drums are currently available at the source plant.');
    }
    final drumCount = _stock.fold<int>(0, (sum, row) => sum + _asInt(row['available_drums']));
    final grossTotal = _stock.fold<double>(0, (sum, row) => sum + _asDouble(row['gross_weight_kg']));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _MetricStrip(drumCount: drumCount, grossWeight: grossTotal, groupCount: _stock.length),
        const SizedBox(height: 12),
        for (final row in _stock)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.inventory_2_outlined),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_text(row['product_name']), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                      _CountPill(count: _asInt(row['available_drums'])),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text('Batch ${_text(row['batch_code'])}  ·  ${_packagingLabel(row['packaging_type'])}'),
                  Text('Plant: ${_text(row['plant_name'])}  ·  Gross weight: ${_weightLabel(row['gross_weight_kg'])}'),
                  Text('Manufactured ${_dateLabel(row['manufacturing_date'])}  ·  Expires ${_dateLabel(row['expiry_date'])}'),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFillsTab(AuthController auth) {
    final canManage = auth.can('inventory.manage');
    final fills = [..._fills]..sort((a, b) => _asInt(b['fill_number']).compareTo(_asInt(a['fill_number'])));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (canManage)
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _products.isEmpty || _plants.isEmpty ? null : _addFilledDrums,
              icon: const Icon(Icons.add),
              label: const Text('Record filled drums'),
            ),
          ),
        const Padding(
          padding: EdgeInsets.only(top: 8, bottom: 4),
          child: Text('The sticker number identifies this fill, not the reusable iron drum. A new number is assigned each time the drum is filled.'),
        ),
        if (canManage && (_products.isEmpty || _plants.isEmpty))
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Add a drum product and source plant before recording fills.'),
          ),
        if (canManage && _products.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(padding: EdgeInsets.only(top: 8), child: Text('Product shelf life', style: TextStyle(fontWeight: FontWeight.w700))),
                  for (final product in _products)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(_text(product['name'])),
                      subtitle: Text('${_asInt(product['shelf_life_months'])} months · applies to future batches'),
                      trailing: IconButton(
                        tooltip: 'Edit shelf life',
                        onPressed: () => _editShelfLife(product),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        if (fills.isEmpty)
          const _EmptyPanel(message: 'No drum fills have been recorded yet.')
        else
          for (final row in fills) _FillCard(row: row),
      ],
    );
  }

  Widget _buildDispatchTab(AuthController auth) {
    final canDispatch = auth.can('dispatch.manage');
    final plantFills = _fills.where((fill) =>
        _upper(fill['status']) == 'AVAILABLE' &&
        (_dispatchPlantId == null || _asInt(fill['plant_id']) == _dispatchPlantId)).toList()
      ..sort((a, b) => _asInt(a['fill_number']).compareTo(_asInt(b['fill_number'])));
    final selectedWeight = plantFills
        .where((fill) => _selectedFillIds.contains(_asInt(fill['id'])))
        .fold<double>(0, (sum, fill) => sum + _asDouble(fill['gross_weight_kg']));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Outbound transfer to Neemrana', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  value: _dispatchPlantId,
                  decoration: const InputDecoration(labelText: 'Source plant'),
                  items: [
                    for (final plant in _plants.where((p) => _asInt(p['active']) != 0))
                      DropdownMenuItem<int>(value: _asInt(plant['id']), child: Text(_text(plant['name']))),
                  ],
                  onChanged: canDispatch
                      ? (value) => setState(() {
                            _dispatchPlantId = value;
                            _selectedFillIds.clear();
                          })
                      : null,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _truckController,
                  enabled: canDispatch,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Truck number', hintText: 'Enter vehicle number'),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: canDispatch ? _chooseDispatchDate : null,
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text(_dateLabel(_ymd(_dispatchAt))),
                    ),
                    OutlinedButton.icon(
                      onPressed: canDispatch ? _chooseDispatchTime : null,
                      icon: const Icon(Icons.schedule),
                      label: Text(TimeOfDay.fromDateTime(_dispatchAt).format(context)),
                    ),
                    Chip(label: Text('${_selectedFillIds.length} drums · ${_weightLabel(selectedWeight)}')),
                  ],
                ),
                if (!canDispatch)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('You can view available drums, but your role cannot record a dispatch.'),
                  ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: canDispatch && !_submittingDispatch ? _submitDispatch : null,
                  icon: _submittingDispatch
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.local_shipping_outlined),
                  label: const Text('Record dispatch'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text('Select available drums', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        if (plantFills.isEmpty)
          const _EmptyPanel(message: 'There are no available drums at this plant to dispatch.')
        else
          for (final fill in plantFills)
            Card(
              child: CheckboxListTile(
                value: _selectedFillIds.contains(_asInt(fill['id'])),
                onChanged: canDispatch
                    ? (checked) => setState(() {
                          final id = _asInt(fill['id']);
                          if (id == 0) return;
                          if (checked == true) {
                            _selectedFillIds.add(id);
                          } else {
                            _selectedFillIds.remove(id);
                          }
                        })
                    : null,
                title: Text('Drum ${_text(fill['fill_number'])} · ${_text(fill['product_name'])}'),
                subtitle: Text('Batch ${_text(fill['batch_code'])} · ${_packagingLabel(fill['packaging_type'])} · expires ${_dateLabel(fill['expiry_date'])}'),
                secondary: Text(_weightLabel(fill['gross_weight_kg'])),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ),
      ],
    );
  }

  Widget _buildHistoryTab() {
    if (_dispatches.isEmpty) return const _EmptyPanel(message: 'No outbound drum dispatches have been recorded.');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final row in _dispatches)
          Card(
            child: ListTile(
              onTap: () => _showDispatchDetails(row),
              leading: const CircleAvatar(child: Icon(Icons.local_shipping_outlined)),
              title: Text('${_text(row['truck_number'])}  ·  ${_text(row['destination'])}'),
              subtitle: Text('${_text(row['plant_name'])}  ·  ${_dateTimeLabel(row['dispatch_datetime'])}'),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${_text(row['drum_count'])} drums', style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(_weightLabel(row['gross_weight_kg'])),
                ],
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    return FutureBuilder<void>(
      future: _loading,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_outlined, size: 42),
                  const SizedBox(height: 12),
                  Text('Could not load drum inventory: ${snapshot.error}', textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(onPressed: _reload, icon: const Icon(Icons.refresh), label: const Text('Retry')),
                ],
              ),
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        final tabs = _tabs(auth);
        final views = _tabViews(auth);
        return DefaultTabController(
          key: ValueKey(tabs.length),
          length: tabs.length,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final actions = <Widget>[
                      IconButton(tooltip: 'Refresh', onPressed: _reload, icon: const Icon(Icons.refresh)),
                      if (auth.can('inventory.manage')) ...[
                        OutlinedButton.icon(onPressed: _addProduct, icon: const Icon(Icons.category_outlined), label: const Text('Product')),
                        OutlinedButton.icon(onPressed: _addPlant, icon: const Icon(Icons.factory_outlined), label: const Text('Plant')),
                      ],
                    ];
                    if (constraints.maxWidth < 580) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(children: [
                            const Expanded(child: Text('Drum inventory & dispatch', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
                            actions.first,
                          ]),
                          if (actions.length > 1) Wrap(spacing: 8, children: actions.skip(1).toList()),
                        ],
                      );
                    }
                    return Row(children: [
                      const Expanded(child: Text('Drum inventory & dispatch', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
                      ...actions,
                    ]);
                  },
                ),
              ),
              Material(
                color: Theme.of(context).colorScheme.surface,
                child: TabBar(isScrollable: true, tabs: tabs),
              ),
              Expanded(child: TabBarView(children: views)),
            ],
          ),
        );
      },
    );
  }
}

class _DrumProductDialog extends StatefulWidget {
  final Future<void> Function(String name, String code, int months) onSave;
  const _DrumProductDialog({required this.onSave});

  @override
  State<_DrumProductDialog> createState() => _DrumProductDialogState();
}

class _DrumProductDialogState extends State<_DrumProductDialog> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _months = TextEditingController(text: '24');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _months.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final code = _code.text.trim();
    final months = int.tryParse(_months.text.trim());
    if (name.isEmpty || months == null || months < 1 || months > 240) {
      setState(() => _error = 'Enter a product name and shelf life in whole months (1–240).');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await widget.onSave(name, code, months);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Add drum product'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: _name, autofocus: true, decoration: const InputDecoration(labelText: 'Product name')),
              TextField(controller: _code, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Product code (optional)')),
              TextField(controller: _months, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Shelf life (months)', helperText: 'For example, 18 months or 24 months')),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: _saving ? null : _submit, child: Text(_saving ? 'Saving…' : 'Save product')),
        ],
      );
}

class _ShelfLifeDialog extends StatefulWidget {
  final int initialMonths;
  const _ShelfLifeDialog({required this.initialMonths});

  @override
  State<_ShelfLifeDialog> createState() => _ShelfLifeDialogState();
}

class _ShelfLifeDialogState extends State<_ShelfLifeDialog> {
  late final TextEditingController _months;
  String? _error;

  @override
  void initState() {
    super.initState();
    _months = TextEditingController(text: '${widget.initialMonths}');
  }

  @override
  void dispose() {
    _months.dispose();
    super.dispose();
  }

  void _save() {
    final value = int.tryParse(_months.text.trim());
    if (value == null || value < 1 || value > 240) {
      setState(() => _error = 'Enter a whole number of months from 1 to 240.');
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Change product shelf life'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: _months, autofocus: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Shelf life (months)')),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
              const SizedBox(height: 6),
              const Text('This only changes expiry calculations for new batches.'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ],
      );
}

class _PlantDialog extends StatefulWidget {
  final Future<void> Function(String name) onSave;
  const _PlantDialog({required this.onSave});

  @override
  State<_PlantDialog> createState() => _PlantDialogState();
}

class _PlantDialogState extends State<_PlantDialog> {
  final _name = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a plant name.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await widget.onSave(name);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Add source plant'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: _name, autofocus: true, decoration: const InputDecoration(labelText: 'Plant name')),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: _saving ? null : _submit, child: Text(_saving ? 'Saving…' : 'Save plant')),
        ],
      );
}

class _CreateDrumFillDialog extends StatefulWidget {
  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> plants;
  final Future<dynamic> Function(Map<String, dynamic> body) onSave;
  const _CreateDrumFillDialog({required this.products, required this.plants, required this.onSave});

  @override
  State<_CreateDrumFillDialog> createState() => _CreateDrumFillDialogState();
}

class _CreateDrumFillDialogState extends State<_CreateDrumFillDialog> {
  final _batch = TextEditingController();
  final List<TextEditingController> _weights = [TextEditingController()];
  late DateTime _manufacturingDate;
  DateTime? _expiryOverride;
  int? _productId;
  int? _plantId;
  String _packagingType = 'aseptic_bag';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _manufacturingDate = DateTime.now();
    if (widget.products.isNotEmpty) _productId = _asInt(widget.products.first['id']);
    if (widget.plants.isNotEmpty) _plantId = _asInt(widget.plants.first['id']);
  }

  @override
  void dispose() {
    _batch.dispose();
    for (final weight in _weights) {
      weight.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic>? get _selectedProduct {
    for (final product in widget.products) {
      if (_asInt(product['id']) == _productId) return product;
    }
    return null;
  }

  DateTime? get _calculatedExpiry {
    final product = _selectedProduct;
    final months = product == null ? null : _asInt(product['shelf_life_months']);
    if (months == null || months < 1) return null;
    return _addMonths(_manufacturingDate, months);
  }

  Future<void> _pickManufacturingDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _manufacturingDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked != null && mounted) setState(() => _manufacturingDate = picked);
  }

  Future<void> _pickExpiryDate() async {
    final initial = _expiryOverride ?? _calculatedExpiry ?? _manufacturingDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: _manufacturingDate,
      lastDate: DateTime(_manufacturingDate.year + 25),
    );
    if (picked != null && mounted) setState(() => _expiryOverride = picked);
  }

  void _addWeightField() {
    if (_weights.length >= 500) return;
    setState(() => _weights.add(TextEditingController()));
  }

  void _removeWeightField(int index) {
    if (_weights.length <= 1) return;
    setState(() {
      final removed = _weights.removeAt(index);
      removed.dispose();
    });
  }

  Future<void> _submit() async {
    final batchCode = _batch.text.trim().toUpperCase();
    if (_plantId == null || _productId == null || batchCode.isEmpty) {
      setState(() => _error = 'Select a plant and product, and enter a batch code.');
      return;
    }
    final weights = <double>[];
    for (var i = 0; i < _weights.length; i++) {
      final weight = double.tryParse(_weights[i].text.trim());
      if (weight == null || !weight.isFinite || weight <= 0) {
        setState(() => _error = 'Enter a valid gross weight for drum ${i + 1}.');
        return;
      }
      weights.add(weight);
    }
    setState(() { _saving = true; _error = null; });
    try {
      await widget.onSave({
        'plantId': _plantId,
        'productId': _productId,
        'batchCode': batchCode,
        'manufacturingDate': _ymd(_manufacturingDate),
        'expiryDate': _expiryOverride == null ? null : _ymd(_expiryOverride!),
        'packagingType': _packagingType,
        'grossWeightsKg': weights,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final calculated = _calculatedExpiry;
    return AlertDialog(
      title: const Text('Record filled drums'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<int>(
                value: _plantId,
                decoration: const InputDecoration(labelText: 'Source plant'),
                items: [for (final plant in widget.plants) DropdownMenuItem<int>(value: _asInt(plant['id']), child: Text(_text(plant['name'])))],
                onChanged: _saving ? null : (value) => setState(() => _plantId = value),
              ),
              DropdownButtonFormField<int>(
                value: _productId,
                decoration: const InputDecoration(labelText: 'Drum product'),
                items: [
                  for (final product in widget.products)
                    DropdownMenuItem<int>(value: _asInt(product['id']), child: Text('${_text(product['name'])} · ${_asInt(product['shelf_life_months'])} months')),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(() {
                          _productId = value;
                          _expiryOverride = null;
                        }),
              ),
              TextField(controller: _batch, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Batch code')),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _packagingType,
                decoration: const InputDecoration(labelText: 'Inner bag packaging'),
                items: const [
                  DropdownMenuItem(value: 'aseptic_bag', child: Text('Aseptic bag')),
                  DropdownMenuItem(value: 'liner_bag', child: Text('Non-aseptic liner bag')),
                ],
                onChanged: _saving ? null : (value) => setState(() => _packagingType = value ?? 'aseptic_bag'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _saving ? null : _pickManufacturingDate,
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text('Manufacturing / packing date: ${_ymd(_manufacturingDate)}'),
              ),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Expiry: ${_ymd(_expiryOverride ?? calculated)}'),
                  TextButton(onPressed: _saving ? null : _pickExpiryDate, child: const Text('Change')),
                  if (_expiryOverride != null) TextButton(onPressed: _saving ? null : () => setState(() => _expiryOverride = null), child: const Text('Use product shelf life')),
                ],
              ),
              const Divider(height: 20),
              Text('Individual gross weights (including the iron drum)', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              for (var i = 0; i < _weights.length; i++)
                Row(
                  children: [
                    SizedBox(width: 72, child: Text('Drum ${i + 1}')),
                    Expanded(
                      child: TextField(
                        controller: _weights[i],
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Gross kg'),
                      ),
                    ),
                    IconButton(tooltip: 'Remove drum', onPressed: _saving || _weights.length == 1 ? null : () => _removeWeightField(i), icon: const Icon(Icons.remove_circle_outline)),
                  ],
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(onPressed: _saving ? null : _addWeightField, icon: const Icon(Icons.add), label: const Text('Add another drum')),
              ),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _submit, child: Text(_saving ? 'Saving…' : 'Save filled drums')),
      ],
    );
  }
}

class _MetricStrip extends StatelessWidget {
  final int drumCount;
  final double grossWeight;
  final int groupCount;
  const _MetricStrip({required this.drumCount, required this.grossWeight, required this.groupCount});

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _MetricCard(label: 'Available drums', value: '$drumCount', icon: Icons.inventory_2_outlined),
          _MetricCard(label: 'Gross weight', value: _weightLabel(grossWeight), icon: Icons.scale_outlined),
          _MetricCard(label: 'Stock groups', value: '$groupCount', icon: Icons.category_outlined),
        ],
      );
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _MetricCard({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 200,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label), Text(value, style: const TextStyle(fontWeight: FontWeight.w700))])),
              ],
            ),
          ),
        ),
      );
}

class _CountPill extends StatelessWidget {
  final int count;
  const _CountPill({required this.count});
  @override
  Widget build(BuildContext context) => Chip(avatar: const Icon(Icons.inventory_2, size: 15), label: Text('$count available'));
}

class _FillCard extends StatelessWidget {
  final Map<String, dynamic> row;
  const _FillCard({required this.row});

  @override
  Widget build(BuildContext context) {
    final dispatched = _upper(row['status']) == 'DISPATCHED';
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text('${row['fill_number'] ?? '—'}')),
        title: Text('${_text(row['product_name'])} · ${_packagingLabel(row['packaging_type'])}'),
        subtitle: Text('Batch ${_text(row['batch_code'])} · ${_text(row['plant_name'])}\nMade ${_dateLabel(row['manufacturing_date'])} · Expires ${_dateLabel(row['expiry_date'])} · ${_weightLabel(row['gross_weight_kg'])}'),
        isThreeLine: true,
        trailing: Chip(label: Text(dispatched ? 'Dispatched' : 'Available')),
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  final String message;
  const _EmptyPanel({required this.message});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: Text(message, textAlign: TextAlign.center)),
      );
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

double _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}

String _text(dynamic value) => value == null ? '—' : value.toString();
String _upper(dynamic value) => (value ?? '').toString().toUpperCase();
String _weightLabel(dynamic value) => '${_asDouble(value).toStringAsFixed(2)} kg';
String _dateLabel(dynamic value) => value == null || value.toString().isEmpty ? '—' : value.toString().split('T').first;
String _ymd(DateTime? date) => date == null ? '—' : '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String _isoWithOffset(DateTime date) {
  final offset = date.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final minutes = offset.inMinutes.abs();
  final hoursPart = (minutes ~/ 60).toString().padLeft(2, '0');
  final minutesPart = (minutes % 60).toString().padLeft(2, '0');
  return '${_ymd(date)}T${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:00$sign$hoursPart:$minutesPart';
}

String _packagingLabel(dynamic value) => value == 'liner_bag' ? 'Non-aseptic liner bag' : 'Aseptic bag';

String _dateTimeLabel(dynamic value) {
  if (value == null) return '—';
  final date = DateTime.tryParse(value.toString());
  if (date == null) return value.toString();
  final local = date.toLocal();
  return '${_ymd(local)} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

DateTime? _addMonths(DateTime date, int months) {
  final monthIndex = date.month - 1 + months;
  final year = date.year + monthIndex ~/ 12;
  final month = monthIndex % 12 + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, date.day > lastDay ? lastDay : date.day);
}
