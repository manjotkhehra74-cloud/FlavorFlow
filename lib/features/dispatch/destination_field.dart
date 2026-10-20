import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/industry_pack.dart';

/// Canonical form used for destinations sent to the ERP API and saved on the
/// device. The input itself stays in the user's casing while they type.
String normalizeDispatchDestination(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();

/// Destination input shared by dispatch entry, the loading calculator and the
/// truck master. Suggestions are conveniences only: users can always type a
/// new customer/company/location directly, without first choosing "Other".
class DispatchDestinationField extends StatelessWidget {
  final TextEditingController controller;
  final Iterable<String> suggestions;
  final ValueChanged<String>? onChanged;
  final bool required;
  final String? errorText;

  const DispatchDestinationField({
    super.key,
    required this.controller,
    this.suggestions = const [],
    this.onChanged,
    this.required = true,
    this.errorText,
  });

  List<String> _suggestionOptions() {
    final values = <String>{
      for (final value in IndustryPack.current.destinations)
        normalizeDispatchDestination(value),
      for (final value in suggestions) normalizeDispatchDestination(value),
    }..removeWhere((value) => value.isEmpty);
    return values.toList()..sort();
  }

  void _select(String value) {
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    onChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final options = _suggestionOptions();
    return TextField(
      controller: controller,
      textCapitalization: TextCapitalization.words,
      textInputAction: TextInputAction.next,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: required
            ? tr('Destination *')
            : tr('Destination *').replaceAll(' *', ''),
        hintText: tr('Enter customer, company or destination'),
        helperText: tr('You can type any destination manually.'),
        errorText: errorText == null ? null : tr(errorText!),
        suffixIcon: PopupMenuButton<String>(
          tooltip: tr('Saved destination suggestions'),
          icon: const Icon(Icons.arrow_drop_down_rounded),
          onSelected: _select,
          itemBuilder: (context) => [
            for (final value in options)
              PopupMenuItem<String>(value: value, child: Text(value)),
          ],
        ),
      ),
    );
  }
}
