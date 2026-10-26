import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/auth.dart';

/// Drum-only outbound dispatch workflow, kept separate from carton dispatch.
/// Per-drum weights are read from the saved fill/register record and summed
/// from the exact drums selected for the truck.
class DrumDispatchPage extends StatefulWidget {
  const DrumDispatchPage({super.key});

  @override
  State<DrumDispatchPage> createState() => _DrumDispatchPageState();
}

class _DrumDispatchPageState extends State<DrumDispatchPage> {
  late Future<void> _loading;
  List<Map<String, dynamic>> _plants = [];
  List<Map<String, dynamic>> _availableFills = [];
  List<Map<String, dynamic>> _openingBalances = [];
  List<Map<String, dynamic>> _dispatches = [];
  List<Map<String, dynamic>> _aggregateDispatches = [];
  List<Map<String, dynamic>> _trucks = [];
  final Set<int> _selectedFillIds = {};
  final TextEditingController _truckController = TextEditingController();
  final TextEditingController _aggregateDrumsController = TextEditingController();
  final TextEditingController _aggregateKgController = TextEditingController();
  int? _dispatchPlantId;
  int? _selectedOpeningBalanceId;
  DateTime _dispatchAt = DateTime.now();
  bool _submittingDispatch = false;
  bool _submittingAggregateDispatch = false;
  bool _manualTruck = false;

  @override
  void initState() {
    super.initState();
    _loading = _load();
  }

  @override
  void dispose() {
    _truckController.dispose();
    _aggregateDrumsController.dispose();
    _aggregateKgController.dispose();
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
    final canViewDispatch = _canViewDispatch(auth);
    final values = await Future.wait(<Future<dynamic>>[
      auth.api.get('/drums/plants'),
      auth.api.get('/drums/fills?status=AVAILABLE'),
      auth.api.get('/drums/opening-balances'),
      if (canViewDispatch) auth.api.get('/drums/dispatches') else Future<dynamic>.value({'dispatches': <dynamic>[]}),
      if (canViewDispatch) auth.api.get('/drums/aggregate-dispatches') else Future<dynamic>.value({'dispatches': <dynamic>[]}),
    ]);

    _plants = _rows(values[0], 'plants');
    _availableFills = _rows(values[1], 'fills');
    _openingBalances = _rows(values[2], 'balances');
    _dispatches = canViewDispatch ? _rows(values[3], 'dispatches') : <Map<String, dynamic>>[];
    _aggregateDispatches = canViewDispatch ? _rows(values[4], 'dispatches') : <Map<String, dynamic>>[];
    final activePlants = _plants.where((plant) => _asInt(plant['active']) != 0).toList();
    if (!_plants.any((plant) => _asInt(plant['id']) == _dispatchPlantId && _asInt(plant['active']) != 0)) {
      _dispatchPlantId = activePlants.isEmpty ? null : _asInt(activePlants.first['id']);
    }

    // The same truck master used by carton dispatch is available here too.
    // Keep this request optional so a truck-list issue does not hide drum stock.
    try {
      _trucks = _rows(await auth.api.get('/dispatch/trucks'), 'trucks');
    } catch (_) {
      _trucks = <Map<String, dynamic>>[];
    }

    final availableIds = _availableFills
        .where((fill) => _upper(fill['status']) == 'AVAILABLE')
        .map((fill) => _asInt(fill['id']))
        .whereType<int>()
        .toSet();
    _selectedFillIds.removeWhere((id) => !availableIds.contains(id));
    final availableOpeningBalances = _openingBalances
        .where((balance) => _asInt(balance['available_drums']) > 0 && _asDouble(balance['available_kg']) > 0)
        .toList();
    if (!availableOpeningBalances.any((balance) => _asInt(balance['id']) == _selectedOpeningBalanceId)) {
      _selectedOpeningBalanceId = availableOpeningBalances.isEmpty ? null : _asInt(availableOpeningBalances.first['id']);
    }
  }

  void _reload() {
    if (!mounted) return;
    setState(() => _loading = _load());
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

  Future<void> _enterOtherTruck() async {
    final controller = TextEditingController(text: _truckController.text);
    final typed = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Truck number'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Truck / vehicle number'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim().toUpperCase()), child: const Text('Use truck')),
        ],
      ),
    );
    controller.dispose();
    if (typed == null || !mounted) return;
    setState(() {
      _truckController.text = typed;
      _manualTruck = true;
    });
  }

  Future<void> _submitDispatch() async {
    final auth = context.read<AuthController>();
    final truck = _truckController.text.trim().toUpperCase();
    if (_dispatchPlantId == null) {
      _showMessage('Add or select a source plant first.');
      return;
    }
    if (truck.isEmpty) {
      _showMessage('Enter or select the truck number.');
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
      _manualTruck = false;
      _reload();
      if (mounted) _showMessage('Drum dispatch to Neemrana recorded. Each drum number and its register weight are saved.');
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    } finally {
      if (mounted) setState(() => _submittingDispatch = false);
    }
  }

  Future<void> _submitAggregateDispatch() async {
    final auth = context.read<AuthController>();
    final truck = _truckController.text.trim().toUpperCase();
    final selectedBalances = _openingBalances.where((row) => _asInt(row['id']) == _selectedOpeningBalanceId);
    final balance = selectedBalances.isEmpty ? null : selectedBalances.first;
    final drumCount = int.tryParse(_aggregateDrumsController.text.trim());
    final grossWeightKg = double.tryParse(_aggregateKgController.text.trim().replaceAll(',', ''));

    if (_dispatchPlantId == null) {
      _showMessage('Add or select a source plant first.');
      return;
    }
    if (truck.isEmpty) {
      _showMessage('Enter or select the truck number.');
      return;
    }
    if (balance == null) {
      _showMessage('Select an aggregate stock product with drums remaining.');
      return;
    }
    if (drumCount == null || drumCount <= 0) {
      _showMessage('Enter a positive whole number of drums to dispatch.');
      return;
    }
    if (drumCount > _asInt(balance['available_drums'])) {
      _showMessage('Only ${_asInt(balance['available_drums'])} drums remain for this product.');
      return;
    }
    if (grossWeightKg == null || !grossWeightKg.isFinite || grossWeightKg <= 0) {
      _showMessage('Enter the actual total kg for these drums.');
      return;
    }
    if (grossWeightKg > _asDouble(balance['available_kg']) + 0.0005) {
      _showMessage('Entered kg is higher than this product’s remaining aggregate kg.');
      return;
    }

    setState(() => _submittingAggregateDispatch = true);
    try {
      await auth.api.post('/drums/aggregate-dispatches', {
        'openingBalanceId': _selectedOpeningBalanceId,
        'plantId': _dispatchPlantId,
        'truckNumber': truck,
        'dispatchDateTime': _isoWithOffset(_dispatchAt),
        'drumCount': drumCount,
        'grossWeightKg': grossWeightKg,
      });
      _aggregateDrumsController.clear();
      _aggregateKgController.clear();
      _reload();
      if (mounted) _showMessage('Aggregate drum dispatch saved; this count and kg were deducted from the product balance.');
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    } finally {
      if (mounted) setState(() => _submittingAggregateDispatch = false);
    }
  }

  Future<void> _showAggregateDispatchDetails(Map<String, dynamic> row) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Aggregate drum dispatch · ${_text(row['truck_number'])}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Product: ${_text(row['product_name'])}'),
            Text('${_text(row['plant_name'])} → ${_text(row['destination'])}'),
            Text('Date/time: ${_dateTimeLabel(row['dispatch_datetime'])}'),
            Text('Drums: ${_text(row['drum_count'])} · Total kg: ${_weightLabel(row['gross_weight_kg'])}'),
            const SizedBox(height: 8),
            const Text('This aggregate stock dispatch records product, drum count and total kg; it does not list individual drum numbers.'),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close'))],
      ),
    );
  }

  Future<void> _showDispatchDetails(Map<String, dynamic> row) async {
    final id = _asInt(row['id']);
    final future = context.read<AuthController>().api.get('/drums/dispatches/$id');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Drum dispatch · ${_text(row['truck_number'])}'),
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
                    Text('Drums: ${_text(dispatch['drum_count'])}  ·  Total gross weight: ${_weightLabel(dispatch['gross_weight_kg'])}'),
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

  List<String> get _neemranaTrucks => _trucks
      .where((truck) => _upper(truck['destination']) == 'NEEMRANA')
      .map((truck) => _text(truck['number']).trim().toUpperCase())
      .where((number) => number.isNotEmpty && number != '—')
      .toSet()
      .toList()
    ..sort();

  Widget _truckField(bool canManage) {
    final options = _neemranaTrucks;
    if (_manualTruck || options.isEmpty) {
      return TextField(
        controller: _truckController,
        enabled: canManage,
        textCapitalization: TextCapitalization.characters,
        decoration: InputDecoration(
          labelText: 'Truck / vehicle number',
          hintText: 'Enter the same truck used for carton dispatch',
          suffixIcon: options.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Choose a saved truck',
                  onPressed: canManage ? () => setState(() => _manualTruck = false) : null,
                  icon: const Icon(Icons.list_alt_outlined),
                ),
        ),
        onChanged: (_) => setState(() => _manualTruck = true),
      );
    }
    return DropdownButtonFormField<String>(
      key: ValueKey('drum-truck-${_truckController.text}'),
      initialValue: options.contains(_truckController.text) ? _truckController.text : null,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Truck / vehicle number'),
      items: [
        for (final number in options) DropdownMenuItem<String>(value: number, child: Text(number)),
        const DropdownMenuItem<String>(value: '__other__', child: Text('Other / new truck…')),
      ],
      onChanged: canManage
          ? (value) {
              if (value == '__other__') {
                setState(() => _manualTruck = true);
                _enterOtherTruck();
              } else if (value != null) {
                setState(() => _truckController.text = value);
              }
            }
          : null,
    );
  }

  Widget _buildEntry(AuthController auth) {
    final canManage = auth.can('dispatch.manage');
    final activePlants = _plants.where((plant) => _asInt(plant['active']) != 0).toList();
    final plantFills = _availableFills
        .where((fill) => _upper(fill['status']) == 'AVAILABLE' &&
            (_dispatchPlantId == null || _asInt(fill['plant_id']) == _dispatchPlantId))
        .toList()
      ..sort((a, b) => _asInt(a['fill_number']).compareTo(_asInt(b['fill_number'])));
    final aggregateBalances = _openingBalances
        .where((balance) => _asInt(balance['available_drums']) > 0 && _asDouble(balance['available_kg']) > 0)
        .toList();
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
                Text('Outbound drum dispatch to Neemrana', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                const Text('Drum dispatch is separate from CB dispatch; choose the same saved truck when both travel together.'),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: ValueKey('drum-source-$_dispatchPlantId'),
                  initialValue: activePlants.any((plant) => _asInt(plant['id']) == _dispatchPlantId) ? _dispatchPlantId : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Source plant'),
                  items: [
                    for (final plant in activePlants)
                      DropdownMenuItem<int>(value: _asInt(plant['id']), child: Text(_text(plant['name']))),
                  ],
                  onChanged: canManage && activePlants.isNotEmpty
                      ? (value) => setState(() {
                            _dispatchPlantId = value;
                            _selectedFillIds.clear();
                          })
                      : null,
                ),
                if (activePlants.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('Add an active source plant under Drum Stock before dispatching drums.'),
                  ),
                const SizedBox(height: 8),
                _truckField(canManage),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: canManage ? _chooseDispatchDate : null,
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text(_ymd(_dispatchAt)),
                    ),
                    OutlinedButton.icon(
                      onPressed: canManage ? _chooseDispatchTime : null,
                      icon: const Icon(Icons.schedule),
                      label: Text(TimeOfDay.fromDateTime(_dispatchAt).format(context)),
                    ),
                    Chip(label: Text('${_selectedFillIds.length} drums · ${_weightLabel(selectedWeight)}')),
                  ],
                ),
                if (!canManage)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('You can view available drums, but your role cannot record a dispatch.'),
                  ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: canManage && !_submittingDispatch ? _submitDispatch : null,
                  icon: _submittingDispatch
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.local_shipping_outlined),
                  label: const Text('Record drum dispatch'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text('Select available drums · weight from the fill register', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        if (plantFills.isEmpty)
          const _EmptyPanel(message: 'No individually tracked drums are available at this plant. Use aggregate stock below if any remains.')
        else
          for (final fill in plantFills)
            Card(
              child: CheckboxListTile(
                value: _selectedFillIds.contains(_asInt(fill['id'])),
                onChanged: canManage
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
                secondary: Text(_weightLabel(fill['gross_weight_kg']), style: const TextStyle(fontWeight: FontWeight.w700)),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Aggregate stock dispatch', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text('Dispatch part of a product balance. Enter the drum count and the actual total kg being sent; both are deducted from stock.'),
                if (aggregateBalances.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('No aggregate stock remains to dispatch.'),
                  )
                else ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    key: ValueKey('aggregate-balance-$_selectedOpeningBalanceId'),
                    initialValue: aggregateBalances.any((balance) => _asInt(balance['id']) == _selectedOpeningBalanceId) ? _selectedOpeningBalanceId : null,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Product · remaining aggregate balance'),
                    items: [
                      for (final balance in aggregateBalances)
                        DropdownMenuItem<int>(
                          value: _asInt(balance['id']),
                          child: Text('${_text(balance['product_name'])} · ${_asInt(balance['available_drums'])} drums · ${_weightLabel(balance['available_kg'])}'),
                        ),
                    ],
                    onChanged: canManage
                        ? (value) => setState(() {
                              _selectedOpeningBalanceId = value;
                              _aggregateDrumsController.clear();
                              _aggregateKgController.clear();
                            })
                        : null,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _aggregateDrumsController,
                          enabled: canManage,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Drums to dispatch'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _aggregateKgController,
                          enabled: canManage,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Total kg to dispatch'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: canManage && !_submittingAggregateDispatch ? _submitAggregateDispatch : null,
                    icon: _submittingAggregateDispatch
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.local_shipping_outlined),
                    label: const Text('Record aggregate dispatch'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHistory() {
    if (_dispatches.isEmpty && _aggregateDispatches.isEmpty) {
      return const _EmptyPanel(message: 'No outbound drum dispatches have been recorded.');
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_aggregateDispatches.isNotEmpty) ...[
          Text('Aggregate stock dispatches', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          for (final row in _aggregateDispatches)
            Card(
              child: ListTile(
                onTap: () => _showAggregateDispatchDetails(row),
                leading: const CircleAvatar(child: Icon(Icons.inventory_2_outlined)),
                title: Text('${_text(row['product_name'])} · ${_text(row['truck_number'])}'),
                subtitle: Text('${_text(row['plant_name'])} · ${_dateTimeLabel(row['dispatch_datetime'])}'),
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
        if (_dispatches.isNotEmpty) ...[
          Text('Individual drum dispatches', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          for (final row in _dispatches)
            Card(
              child: ListTile(
                onTap: () => _showDispatchDetails(row),
                leading: const CircleAvatar(child: Icon(Icons.local_shipping_outlined)),
                title: Text('${_text(row['truck_number'])} · ${_text(row['destination'])}'),
                subtitle: Text('${_text(row['plant_name'])} · ${_dateTimeLabel(row['dispatch_datetime'])}'),
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
                  Text('Could not load drum dispatch: ${snapshot.error}', textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(onPressed: _reload, icon: const Icon(Icons.refresh), label: const Text('Retry')),
                ],
              ),
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        return DefaultTabController(
          length: 2,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
                child: Row(
                  children: [
                    const Expanded(child: Text('Drum Dispatch · Neemrana', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
                    IconButton(tooltip: 'Refresh', onPressed: _reload, icon: const Icon(Icons.refresh)),
                  ],
                ),
              ),
              const TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [Tab(text: 'New drum dispatch'), Tab(text: 'Drum dispatch history')],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildEntry(auth),
                    _buildHistory(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
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
String _ymd(DateTime date) => '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

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
