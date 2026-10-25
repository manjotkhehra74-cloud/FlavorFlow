/// Aggregate-only opening balances transcribed from the production/dispatch
/// report PDF. The report's final balance rows are dated 22 October 2026.
/// These figures are not individual, dispatchable drum records.
class DrumOpeningBalance {
  final String productName;
  final int availableDrums;
  final double balanceKg;

  const DrumOpeningBalance({
    required this.productName,
    required this.availableDrums,
    required this.balanceKg,
  });
}

const String drumOpeningBalanceSnapshotLabel = '22 Oct 2026';

/// Pear Pulp appeared twice as the same image in the PDF and is included once.
/// Red Chilli Puree Salted appeared on two different sheets/serial ranges, so
/// both reported balances are retained and combined by product name in the UI.
const List<DrumOpeningBalance> drumOpeningBalances = <DrumOpeningBalance>[
  DrumOpeningBalance(
    productName: 'Green Chilli Puree Salt Mix (10%)',
    availableDrums: 5476,
    balanceKg: 1211015,
  ),
  DrumOpeningBalance(
    productName: 'Pear Pulp',
    availableDrums: 6,
    balanceKg: 1270,
  ),
  DrumOpeningBalance(
    productName: 'Tomato Paste',
    availableDrums: 5062,
    balanceKg: 1137216,
  ),
  DrumOpeningBalance(
    productName: 'Garlic Paste Salt Mix',
    availableDrums: 478,
    balanceKg: 91520.5,
  ),
  DrumOpeningBalance(
    productName: 'Carrot Paste Salt Mix (10%)',
    availableDrums: 4086,
    balanceKg: 903267,
  ),
  DrumOpeningBalance(
    productName: 'Carrot Pulp (10%)',
    availableDrums: 393,
    balanceKg: 84808,
  ),
  DrumOpeningBalance(
    productName: 'Apple Paste',
    availableDrums: 1655,
    balanceKg: 366951,
  ),
  DrumOpeningBalance(
    productName: 'Red Chilli Puree Salted',
    availableDrums: 1,
    balanceKg: 222,
  ),
  DrumOpeningBalance(
    productName: 'Apple Pulp',
    availableDrums: 9,
    balanceKg: 1722,
  ),
  DrumOpeningBalance(
    productName: 'Guava Pulp',
    availableDrums: 160,
    balanceKg: 33512,
  ),
  DrumOpeningBalance(
    productName: 'Pear Paste',
    availableDrums: 2826,
    balanceKg: 611688,
  ),
  DrumOpeningBalance(
    productName: 'Red Chilli Puree Salted',
    availableDrums: 127,
    balanceKg: 27968,
  ),
];

String drumProductBalanceKey(String productName) => productName.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
