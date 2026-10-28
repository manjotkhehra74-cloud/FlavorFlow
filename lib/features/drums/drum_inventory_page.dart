import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/platform_support.dart';
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
  List<Map<String, dynamic>> _openingBalances = [];
  List<Map<String, dynamic>> _stockAdjustments = [];

  @override
  void initState() {
    super.initState();
    _loading = _load();
  }

  List<Map<String, dynamic>> _rows(dynamic json, String key) {
    if (json is! Map) return <Map<String, dynamic>>[];
    final value = json[key];
    if (value is! List) return <Map<String, dynamic>>[];
    return value.whereType<Map>().map((row) => row.cast<String, dynamic>()).toList();
  }

  Future<void> _load() async {
    final auth = context.read<AuthController>();
    final values = await Future.wait(<Future<dynamic>>[
      auth.api.get('/drums/products'),
      auth.api.get('/drums/plants'),
      auth.api.get('/drums/stock'),
      auth.api.get('/drums/fills?status=ALL'),
      auth.api.get('/drums/opening-balances'),
      auth.api.get('/drums/stock-adjustments'),
    ]);
    _products = _rows(values[0], 'products');
    _plants = _rows(values[1], 'plants');
    _stock = _rows(values[2], 'stock');
    _fills = _rows(values[3], 'fills');
    _openingBalances = _rows(values[4], 'balances');
    _stockAdjustments = _rows(values[5], 'adjustments');
  }

  void _reload() {
    if (!mounted) return;
    setState(() => _loading = _load());
  }

  Future<bool> _showAddProductDialog() async {
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
    return saved == true;
  }

  Future<void> _reloadAndWait() async {
    if (!mounted) return;
    await _load();
    if (mounted) setState(() {});
  }

  Future<void> _addProduct() async {
    if (!await _showAddProductDialog()) return;
    try {
      await _reloadAndWait();
      if (mounted) _showMessage('Drum product added. You can now add filled drums for it.');
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    }
  }

  Future<void> _editStockBalance(_ProductBalance balance, List<_ProductBalance> balances) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _DrumStockAdjustDialog(
        initialBalance: balance,
        balances: balances,
        onSave: (productName, targetDrums, targetKg, reason) async {
          await context.read<AuthController>().api.post('/drums/stock-adjustments', {
            'productName': productName,
            'targetDrums': targetDrums,
            'targetKg': targetKg,
            'reason': reason,
          });
        },
      ),
    );
    if (saved != true) return;
    try {
      await _reloadAndWait();
      if (mounted) _showMessage('Stock correction recorded. Individual fill and dispatch history was not changed.');
    } catch (error) {
      if (mounted) _showMessage('Correction saved, but the current balance could not be refreshed: $error');
    }
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

  Future<bool> _showAddPlantDialog() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _PlantDialog(
        onSave: (name) async {
          await context.read<AuthController>().api.post('/drums/plants', {'name': name});
        },
      ),
    );
    return saved == true;
  }

  Future<void> _addPlant() async {
    if (!await _showAddPlantDialog()) return;
    try {
      await _reloadAndWait();
      if (mounted) _showMessage('Source plant added.');
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    }
  }

  Future<void> _addFilledDrums() async {
    if (_products.where((product) => _asInt(product['active']) != 0).isEmpty) {
      final productAdded = await _showAddProductDialog();
      if (!productAdded || !mounted) return;
      try {
        await _reloadAndWait();
      } catch (error) {
        if (mounted) _showMessage(error.toString());
        return;
      }
    }
    if (_plants.where((plant) => _asInt(plant['active']) != 0).isEmpty) {
      final plantAdded = await _showAddPlantDialog();
      if (!plantAdded || !mounted) return;
      try {
        await _reloadAndWait();
      } catch (error) {
        if (mounted) _showMessage(error.toString());
        return;
      }
    }
    if (!mounted) return;
    final products = _products.where((product) => _asInt(product['active']) != 0).toList();
    final plants = _plants.where((plant) => _asInt(plant['active']) != 0).toList();
    if (products.isEmpty || plants.isEmpty) {
      _showMessage('Add an active drum product and source plant before recording fills.');
      return;
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _CreateDrumFillDialog(
        products: products,
        plants: plants,
        onSave: (body) async => context.read<AuthController>().api.post('/drums/fills', body),
      ),
    );
    if (saved == true) {
      try {
        await _reloadAndWait();
        if (mounted) _showMessage('Filled drum records saved.');
      } catch (error) {
        if (mounted) _showMessage('Drums were saved, but stock could not be refreshed: $error');
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  List<Tab> _tabs() => const [
        Tab(text: 'Available stock'),
        Tab(text: 'Filled drums'),
      ];

  List<Widget> _tabViews(AuthController auth) => [
        _buildStockTab(auth),
        _buildFillsTab(auth),
      ];

  Widget _buildStockTab(AuthController auth) {
    if (_stock.isEmpty && _openingBalances.isEmpty && _products.isEmpty) {
      return const _EmptyPanel(message: 'No drum balances are currently available.');
    }

    final productBalances = <String, _ProductBalance>{};
    _ProductBalance balanceFor(String name) {
      final key = name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      return productBalances.putIfAbsent(key, () => _ProductBalance(productName: name));
    }

    for (final product in _products.where((row) => _asInt(row['active']) != 0)) {
      balanceFor(_text(product['name']));
    }
    for (final opening in _openingBalances) {
      final balance = balanceFor(_text(opening['product_name']));
      balance.openingDrums += _asInt(opening['available_drums']);
      balance.openingKg += _asDouble(opening['available_kg']);
    }
    for (final row in _stock) {
      final balance = balanceFor(_text(row['product_name']));
      balance.trackedDrums += _asInt(row['available_drums']);
      balance.trackedKg += _asDouble(row['gross_weight_kg']);
    }

    final sortedBalances = productBalances.values.toList()
      ..sort((a, b) => a.productName.compareTo(b.productName));
    final drumCount = sortedBalances.fold<int>(0, (sum, balance) => sum + balance.totalDrums);
    final balanceKg = sortedBalances.fold<double>(0, (sum, balance) => sum + balance.totalKg);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _MetricStrip(drumCount: drumCount, balanceKg: balanceKg, productCount: productBalances.length),
        const SizedBox(height: 12),
        Text('Current balance by product', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const Padding(
          padding: EdgeInsets.only(top: 4, bottom: 8),
          child: Text('Current balance combines official aggregate stock with available, individually tracked fills. A correction changes only aggregate availability; saved fill and dispatch records remain unchanged.'),
        ),
        for (final balance in sortedBalances)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(balance.productName, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                      if (auth.can('inventory.manage'))
                        IconButton(
                          tooltip: 'Correct product stock',
                          onPressed: () => _editStockBalance(balance, sortedBalances),
                          icon: const Icon(Icons.edit_note_outlined),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(child: _BalanceValue(label: 'Balance in drums', value: '${balance.totalDrums}')),
                      const SizedBox(width: 12),
                      Expanded(child: _BalanceValue(label: 'Balance in kg', value: _weightLabel(balance.totalKg))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Official aggregate stock remaining: ${balance.openingDrums} drums · ${_weightLabel(balance.openingKg)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (balance.trackedDrums > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Individually tracked available: ${balance.trackedDrums} drums · ${_weightLabel(balance.trackedKg)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
        if (_stockAdjustments.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Recent stock corrections', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          for (final adjustment in _stockAdjustments.take(10))
            Card(
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.history_rounded),
                title: Text('${_text(adjustment['product_name'])} · ${_asInt(adjustment['previous_drums'])} drums / ${_weightLabel(adjustment['previous_kg'])} → ${_asInt(adjustment['corrected_drums'])} drums / ${_weightLabel(adjustment['corrected_kg'])}'),
                subtitle: Text('${_text(adjustment['reason'])} · ${_text(adjustment['created_by_name'])} · ${_dateLabel(adjustment['created_at'])}'),
              ),
            ),
        ],
        if (_stock.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Tracked drum details: batch, packaging & plant', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
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
        ] else
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('No individually tracked drums are currently available. Aggregate stock can still be dispatched by entering a product, drum count and total kg.'),
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
              onPressed: _addFilledDrums,
              icon: const Icon(Icons.add),
              label: const Text('Add filled drums'),
            ),
          ),
        const Padding(
          padding: EdgeInsets.only(top: 8, bottom: 4),
          child: Text('The sticker number identifies this fill, not the reusable iron drum. A new number is assigned each time the drum is filled.'),
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 4),
          child: Text('This list contains drum-fill products only. Bottle-line products stay separate; products with aggregate drum stock are available automatically.'),
        ),
        if (canManage && (_products.isEmpty || _plants.isEmpty))
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Tap Add filled drums; if a product or source plant is missing, the app will ask you to add it first.'),
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
        final tabs = _tabs();
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
                    final canManage = auth.can('inventory.manage');
                    final actions = <Widget>[
                      IconButton(tooltip: 'Refresh', onPressed: _reload, icon: const Icon(Icons.refresh)),
                      if (canManage) ...[
                        OutlinedButton.icon(onPressed: _addProduct, icon: const Icon(Icons.category_outlined), label: const Text('Add drum product')),
                        OutlinedButton.icon(onPressed: _addPlant, icon: const Icon(Icons.factory_outlined), label: const Text('Add plant')),
                        OutlinedButton.icon(
                          onPressed: _addFilledDrums,
                          icon: const Icon(Icons.inventory_2_outlined),
                          label: const Text('Add filled drums'),
                        ),
                      ],
                    ];
                    if (constraints.maxWidth < 760) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(children: [
                            const Expanded(child: Text('Drum Stock', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
                            actions.first,
                          ]),
                          if (actions.length > 1) Wrap(spacing: 8, runSpacing: 8, children: actions.skip(1).toList()),
                        ],
                      );
                    }
                    return Row(children: [
                      const Expanded(child: Text('Drum Stock', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
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

class _ProductBalance {
  final String productName;
  int openingDrums = 0;
  double openingKg = 0;
  int trackedDrums = 0;
  double trackedKg = 0;

  _ProductBalance({required this.productName});

  int get totalDrums => openingDrums + trackedDrums;
  double get totalKg => openingKg + trackedKg;
}

class _DrumStockAdjustDialog extends StatefulWidget {
  final _ProductBalance initialBalance;
  final List<_ProductBalance> balances;
  final Future<void> Function(String productName, int targetDrums, double targetKg, String reason) onSave;

  const _DrumStockAdjustDialog({
    required this.initialBalance,
    required this.balances,
    required this.onSave,
  });

  @override
  State<_DrumStockAdjustDialog> createState() => _DrumStockAdjustDialogState();
}

class _DrumStockAdjustDialogState extends State<_DrumStockAdjustDialog> {
  late String _productName;
  late final TextEditingController _drums;
  late final TextEditingController _kg;
  final TextEditingController _reason = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _productName = widget.initialBalance.productName;
    _drums = TextEditingController(text: '${widget.initialBalance.totalDrums}');
    _kg = TextEditingController(text: widget.initialBalance.totalKg.toStringAsFixed(3));
  }

  @override
  void dispose() {
    _drums.dispose();
    _kg.dispose();
    _reason.dispose();
    super.dispose();
  }

  _ProductBalance _balanceFor(String name) => widget.balances.firstWhere(
        (balance) => balance.productName == name,
        orElse: () => widget.initialBalance,
      );

  void _selectProduct(String? name) {
    if (name == null) return;
    final balance = _balanceFor(name);
    setState(() {
      _productName = name;
      _drums.text = '${balance.totalDrums}';
      _kg.text = balance.totalKg.toStringAsFixed(3);
      _error = null;
    });
  }

  Future<void> _save() async {
    final drums = int.tryParse(_drums.text.trim());
    final kg = double.tryParse(_kg.text.trim().replaceAll(',', '.'));
    final reason = _reason.text.trim();
    if (drums == null || drums < 0 || kg == null || !kg.isFinite || kg < 0) {
      setState(() => _error = 'Enter a non-negative whole drum count and a valid total kg.');
      return;
    }
    if (reason.length < 3) {
      setState(() => _error = 'Enter why this stock correction is needed.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await widget.onSave(_productName, drums, kg, reason);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final balance = _balanceFor(_productName);
    return AlertDialog(
      title: const Text('Correct drum stock balance'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                value: _productName,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Product'),
                items: [
                  for (final item in widget.balances)
                    DropdownMenuItem<String>(value: item.productName, child: Text(item.productName, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: _saving ? null : _selectProduct,
              ),
              const SizedBox(height: 10),
              Text('Current official aggregate: ${balance.openingDrums} drums · ${_weightLabel(balance.openingKg)}'),
              Text('Current individually tracked available: ${balance.trackedDrums} drums · ${_weightLabel(balance.trackedKg)}'),
              const SizedBox(height: 12),
              TextField(
                controller: _drums,
                enabled: !_saving,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Correct total available drums'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _kg,
                enabled: !_saving,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Correct total available kg'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _reason,
                enabled: !_saving,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Correction reason *', hintText: 'e.g. verified physical count'),
              ),
              const SizedBox(height: 8),
              const Text('This adjusts only aggregate stock. The target cannot be lower than available tracked drums or their saved gross kg; fill and dispatch history is never rewritten.'),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save correction')),
      ],
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
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Product name'),
                ),
                TextField(controller: _code, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Product code (optional)')),
                TextField(controller: _months, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Shelf life (months)', helperText: 'For example, 18 months or 24 months')),
                if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
              ],
            ),
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
  final _numberFrom = TextEditingController();
  final _numberTo = TextEditingController();
  final List<TextEditingController> _weights = [TextEditingController()];
  late DateTime _manufacturingDate;
  DateTime? _expiryOverride;
  int? _productId;
  int? _plantId;
  int _lastValidStartNumber = 1;
  int _lastValidEndNumber = 1;
  String _packagingType = 'aseptic_bag';
  bool _saving = false;
  bool _checkingRegisterPhoto = false;
  bool _registerOcrUsed = false;
  bool _confirmedOcrReview = false;
  String? _registerPhotoName;
  String? _registerOcrMessage;
  final Set<int> _uncertainOcrNumbers = {};
  String? _error;
  String? _rangeError;

  @override
  void initState() {
    super.initState();
    _manufacturingDate = DateTime.now();
    if (widget.products.isNotEmpty) _productId = _asInt(widget.products.first['id']);
    if (widget.plants.isNotEmpty) {
      final firstPlant = widget.plants.first;
      _plantId = _asInt(firstPlant['id']);
      _lastValidStartNumber = _nextFillNumber(firstPlant);
    }
    _lastValidEndNumber = _lastValidStartNumber;
    _numberFrom.text = '$_lastValidStartNumber';
    _numberTo.text = '$_lastValidEndNumber';
  }

  int _nextFillNumber(Map<String, dynamic> plant) {
    final value = _asInt(plant['next_fill_number']);
    return value > 0 ? value : 1;
  }

  @override
  void dispose() {
    _batch.dispose();
    _numberFrom.dispose();
    _numberTo.dispose();
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

  void _resizeWeightFields(int count) {
    while (_weights.length > count) {
      _weights.removeLast().dispose();
    }
    while (_weights.length < count) {
      _weights.add(TextEditingController());
    }
  }

  void _clearOcrDraft() {
    _registerOcrUsed = false;
    _confirmedOcrReview = false;
    _registerPhotoName = null;
    _registerOcrMessage = null;
    _uncertainOcrNumbers.clear();
  }

  void _updateWeightRows() {
    final from = int.tryParse(_numberFrom.text.trim());
    final to = int.tryParse(_numberTo.text.trim());
    const maxSafeInteger = 9007199254740991;
    if (from == null || to == null || from <= 0 || to < from || from > maxSafeInteger || to > maxSafeInteger) {
      setState(() => _rangeError = 'Enter a valid positive drum number range.');
      return;
    }
    final count = to - from + 1;
    if (count > 500) {
      setState(() => _rangeError = 'Add up to 500 drums in one batch.');
      return;
    }
    setState(() {
      if (from != _lastValidStartNumber || to != _lastValidEndNumber) {
        for (final weight in _weights) {
          weight.clear();
        }
        _lastValidStartNumber = from;
        _lastValidEndNumber = to;
        _clearOcrDraft();
      }
      _resizeWeightFields(count);
      _rangeError = null;
    });
  }

  void _selectPlant(int? plantId) {
    if (plantId == null) return;
    final plant = widget.plants.firstWhere(
      (row) => _asInt(row['id']) == plantId,
      orElse: () => <String, dynamic>{'next_fill_number': 1},
    );
    final nextNumber = _nextFillNumber(plant);
    setState(() {
      _plantId = plantId;
      _numberFrom.text = '$nextNumber';
      _numberTo.text = '$nextNumber';
      _lastValidStartNumber = nextNumber;
      _lastValidEndNumber = nextNumber;
      _rangeError = null;
      _clearOcrDraft();
      for (final weight in _weights) {
        weight.clear();
      }
      _resizeWeightFields(1);
    });
  }

  Future<void> _scanRegisterPhoto(ImageSource source) async {
    final from = int.tryParse(_numberFrom.text.trim());
    final to = int.tryParse(_numberTo.text.trim());
    if (from == null || to == null || from <= 0 || to < from || to - from + 1 != _weights.length) {
      setState(() => _rangeError = 'Set a valid drum-number range before checking a register photo.');
      return;
    }
    try {
      final photo = await ImagePicker().pickImage(source: source, maxWidth: 2200, imageQuality: 80);
      if (photo == null || !mounted) return;
      final bytes = await photo.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) {
        setState(() => _error = 'Choose a register photo under 5 MB.');
        return;
      }
      setState(() {
        _checkingRegisterPhoto = true;
        _registerOcrUsed = false;
        _confirmedOcrReview = false;
        _registerPhotoName = photo.name;
        _registerOcrMessage = null;
        _uncertainOcrNumbers.clear();
        _error = null;
      });
      final result = await context.read<AuthController>().api.postWithTimeout(
        '/drums/register-ocr',
        {
          'imageBase64': base64Encode(bytes),
          'fillNumberFrom': from,
          'fillNumberTo': to,
        },
        const Duration(seconds: 120),
      );
      final readings = result is Map && result['readings'] is List
          ? (result['readings'] as List).whereType<Map>().map((row) => row.cast<String, dynamic>()).toList()
          : <Map<String, dynamic>>[];
      var recognized = 0;
      final uncertain = <int>{};
      for (final reading in readings) {
        final number = _asInt(reading['fill_number']);
        final weight = _asDouble(reading['gross_weight_kg']);
        final index = number - from;
        if (index < 0 || index >= _weights.length || weight <= 0) continue;
        _weights[index].text = weight.toString();
        recognized++;
        if (reading['uncertain'] == true) uncertain.add(number);
      }
      final missingNumbers = result is Map && result['missing_numbers'] is List
          ? (result['missing_numbers'] as List).map(_asInt).where((number) => number > 0).toList()
          : <int>[];
      if (!mounted) return;
      setState(() {
        _registerOcrUsed = true;
        _confirmedOcrReview = false;
        _uncertainOcrNumbers
          ..clear()
          ..addAll(uncertain);
        final caution = uncertain.isEmpty ? '' : ' · ${uncertain.length} uncertain';
        final gaps = missingNumbers.isEmpty ? '' : ' · ${missingNumbers.length} not read';
        _registerOcrMessage = 'OCR draft: $recognized of ${_weights.length} weights suggested$caution$gaps. Check every number and weight below; nothing is saved until you confirm and press Save.';
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Photo OCR failed. You can enter the weights manually. $error');
    } finally {
      if (mounted) setState(() => _checkingRegisterPhoto = false);
    }
  }

  Future<void> _submit() async {
    final batchCode = _batch.text.trim().toUpperCase();
    final firstNumber = int.tryParse(_numberFrom.text.trim());
    final lastNumber = int.tryParse(_numberTo.text.trim());
    const maxSafeInteger = 9007199254740991;
    if (_plantId == null || _productId == null || batchCode.isEmpty) {
      setState(() => _error = 'Select a plant and product, and enter a batch code.');
      return;
    }
    if (firstNumber == null || lastNumber == null || firstNumber <= 0 || lastNumber < firstNumber || firstNumber > maxSafeInteger || lastNumber > maxSafeInteger || lastNumber - firstNumber + 1 != _weights.length) {
      setState(() => _rangeError = 'Enter a valid range and one weight field for every drum number.');
      return;
    }
    if (_registerOcrUsed && !_confirmedOcrReview) {
      setState(() => _error = 'Review every OCR suggestion and confirm the draft before saving.');
      return;
    }
    final weights = <double>[];
    for (var i = 0; i < _weights.length; i++) {
      final weight = double.tryParse(_weights[i].text.trim());
      if (weight == null || !weight.isFinite || weight <= 0) {
        setState(() => _error = 'Enter the actual gross kg for drum ${firstNumber + i}.');
        return;
      }
      weights.add(weight);
    }
    setState(() { _saving = true; _error = null; _rangeError = null; });
    try {
      await widget.onSave({
        'plantId': _plantId,
        'productId': _productId,
        'batchCode': batchCode,
        'manufacturingDate': _ymd(_manufacturingDate),
        'expiryDate': _expiryOverride == null ? null : _ymd(_expiryOverride!),
        'packagingType': _packagingType,
        'fillNumberFrom': firstNumber,
        'fillNumberTo': lastNumber,
        'grossWeightsKg': weights,
        'registerOcrChecked': _registerOcrUsed && _confirmedOcrReview,
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
      title: const Text('Add filled drums'),
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
                onChanged: _saving || _checkingRegisterPhoto ? null : _selectPlant,
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
              Text('Drum number range', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _numberFrom,
                      enabled: !_saving && !_checkingRegisterPhoto,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'From number'),
                      onChanged: (_) => _updateWeightRows(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _numberTo,
                      enabled: !_saving && !_checkingRegisterPhoto,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'To number'),
                      onChanged: (_) => _updateWeightRows(),
                    ),
                  ),
                ],
              ),
              if (_rangeError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_rangeError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _saving || _checkingRegisterPhoto ? null : () => _scanRegisterPhoto(ImageSource.gallery),
                    icon: _checkingRegisterPhoto
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.document_scanner_outlined),
                    label: Text(_checkingRegisterPhoto ? 'Checking photo…' : 'Upload register photo & check'),
                  ),
                  if (isPhonePlatform)
                    OutlinedButton.icon(
                      onPressed: _saving || _checkingRegisterPhoto ? null : () => _scanRegisterPhoto(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Take photo'),
                    ),
                ],
              ),
              if (_registerPhotoName != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Register photo: $_registerPhotoName', style: Theme.of(context).textTheme.bodySmall),
                ),
              if (_registerOcrMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_registerOcrMessage!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
                ),
              if (_registerOcrUsed)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _confirmedOcrReview,
                  onChanged: _saving ? null : (checked) => setState(() { _confirmedOcrReview = checked == true; _error = null; }),
                  title: const Text('I checked/corrected every drum number and gross weight above.'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              const SizedBox(height: 8),
              Text(
                'One weight field appears for each number. Weigh each filled drum and enter its actual gross kg, including the iron drum. Stock kg is the sum of these saved weights; changing the number range clears values so they cannot be attached to the wrong drum.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < _weights.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 104,
                        child: Row(
                          children: [
                            Expanded(child: Text('Drum ${_lastValidStartNumber + i}')),
                            if (_uncertainOcrNumbers.contains(_lastValidStartNumber + i))
                              Tooltip(
                                message: 'OCR reading is uncertain — verify this value',
                                child: Icon(Icons.warning_amber_rounded, size: 18, color: Theme.of(context).colorScheme.error),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _weights[i],
                          enabled: !_saving && !_checkingRegisterPhoto,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Actual gross kg'),
                          onChanged: (_) {
                            if (_registerOcrUsed && _confirmedOcrReview) {
                              setState(() => _confirmedOcrReview = false);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _saving || _checkingRegisterPhoto ? null : _submit, child: Text(_saving ? 'Saving…' : 'Save filled drums')),
      ],
    );
  }
}

class _MetricStrip extends StatelessWidget {
  final int drumCount;
  final double balanceKg;
  final int productCount;
  const _MetricStrip({required this.drumCount, required this.balanceKg, required this.productCount});

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _MetricCard(label: 'Balance in drums', value: '$drumCount', icon: Icons.inventory_2_outlined),
          _MetricCard(label: 'Balance in kg', value: _weightLabel(balanceKg), icon: Icons.scale_outlined),
          _MetricCard(label: 'Products', value: '$productCount', icon: Icons.category_outlined),
        ],
      );
}

class _BalanceValue extends StatelessWidget {
  final String label;
  final String value;
  const _BalanceValue({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(value, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
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


String _packagingLabel(dynamic value) => value == 'liner_bag' ? 'Non-aseptic liner bag' : 'Aseptic bag';


DateTime? _addMonths(DateTime date, int months) {
  final monthIndex = date.month - 1 + months;
  final year = date.year + monthIndex ~/ 12;
  final month = monthIndex % 12 + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, date.day > lastDay ? lastDay : date.day);
}
