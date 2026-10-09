import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../state/auth.dart';
import 'api.dart';

/// Where an offline-captured entry is in its life.
enum SyncState { pending, failed, synced }

/// One data-entry request that could not reach the server. It is kept on this
/// phone (encrypted storage) until the server accepts it. The entry id is sent
/// as the `Idempotency-Key`, so re-sending after a lost reply cannot create a
/// second record on a server that has the ff-idempotency patch.
class QueuedEntry {
  final String id;
  final String owner; // account email that captured it — only that account syncs it
  final String label;
  final String method;
  final String path;
  final Map<String, dynamic> body;
  final DateTime createdAt;
  SyncState state;
  int attempts;
  DateTime? nextAttemptAt;
  String? lastError;
  DateTime? syncedAt;
  String? serverRef;

  QueuedEntry({
    required this.id,
    required this.owner,
    required this.label,
    required this.method,
    required this.path,
    required this.body,
    required this.createdAt,
    this.state = SyncState.pending,
    this.attempts = 0,
    this.nextAttemptAt,
    this.lastError,
    this.syncedAt,
    this.serverRef,
  });

  /// Short hint for the list: the code / destination / product the user typed.
  String get summary {
    for (final k in const ['code', 'destination', 'productName', 'reference', 'remark', 'note']) {
      final v = body[k];
      if (v != null && '$v'.trim().isNotEmpty) return '$v';
    }
    return '';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'owner': owner,
        'label': label,
        'method': method,
        'path': path,
        'body': body,
        'createdAt': createdAt.toIso8601String(),
        'state': state.name,
        'attempts': attempts,
        'nextAttemptAt': nextAttemptAt?.toIso8601String(),
        'lastError': lastError,
        'syncedAt': syncedAt?.toIso8601String(),
        'serverRef': serverRef,
      };

  factory QueuedEntry.fromJson(Map<String, dynamic> j) => QueuedEntry(
        id: '${j['id']}',
        owner: '${j['owner'] ?? ''}',
        label: '${j['label'] ?? 'Entry'}',
        method: '${j['method'] ?? 'POST'}',
        path: '${j['path'] ?? ''}',
        body: (j['body'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{},
        createdAt: DateTime.tryParse('${j['createdAt'] ?? ''}') ?? DateTime.now(),
        state: SyncState.values.firstWhere((s) => s.name == j['state'], orElse: () => SyncState.pending),
        attempts: (j['attempts'] as num?)?.toInt() ?? 0,
        nextAttemptAt: DateTime.tryParse('${j['nextAttemptAt'] ?? ''}'),
        lastError: j['lastError'] as String?,
        syncedAt: DateTime.tryParse('${j['syncedAt'] ?? ''}'),
        serverRef: j['serverRef'] as String?,
      );
}

/// Result of [OfflineQueue.submit]: either the server's reply, or `queued`
/// when the entry was kept on this phone for later sync.
class SubmitResult {
  final dynamic json;
  final bool queued;
  final String id;
  const SubmitResult({required this.json, required this.queued, required this.id});
}

/// Offline entry queue (MAN-13).
///
/// - Supported entries are sent straight away. If the server cannot be reached
///   (no network, timeout, 502–504) the entry is stored on the phone and sent
///   automatically when the connection returns (retry loop, app resume, Sync now).
/// - Entries are sent oldest first, once each thanks to the Idempotency-Key.
/// - A real rejection from the server (validation, permission, stock rule) marks
///   the entry "needs review" — it is never sent again without the user's Retry.
/// - Entries belong to the account that captured them; another account on the
///   same phone will not send them.
/// - Storage uses encrypted storage (Android Keystore-backed).
class OfflineQueue extends ChangeNotifier {
  OfflineQueue._();
  static final OfflineQueue instance = OfflineQueue._();

  static const _storageKey = 'ff_offline_queue_v1';
  static const _storage = FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));
  static const _keepSynced = 25;
  static final math.Random _rng = math.Random();

  final List<QueuedEntry> _items = [];
  ApiClient? _api;
  String? _owner;
  Timer? _timer;
  bool _flushing = false;
  bool _loaded = false;
  bool _readOnly = false; // storage was unreadable — never overwrite it
  bool online = true;

  List<QueuedEntry> get entries => List.unmodifiable(_items);
  List<QueuedEntry> get pending => _items.where((e) => e.state == SyncState.pending).toList();
  List<QueuedEntry> get failed => _items.where((e) => e.state == SyncState.failed).toList();
  List<QueuedEntry> get synced {
    final list = _items.where((e) => e.state == SyncState.synced).toList();
    list.sort((a, b) => (b.syncedAt ?? b.createdAt).compareTo(a.syncedAt ?? a.createdAt));
    return list;
  }

  int get pendingCount => pending.length;

  String _newId() {
    final t = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final r1 = _rng.nextInt(1 << 31).toRadixString(36);
    final r2 = _rng.nextInt(1 << 31).toRadixString(36);
    return '$t-$r1$r2';
  }

  /// Load the saved queue (called once at app start).
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await _storage.read(key: _storageKey);
      if (raw != null && raw.isNotEmpty) {
        final list = (jsonDecode(raw) as List).whereType<Map>();
        _items
          ..clear()
          ..addAll(list.map((m) => QueuedEntry.fromJson(m.cast<String, dynamic>())));
      }
    } catch (_) {
      _readOnly = true;
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    if (_readOnly) return;
    try {
      await _storage.write(key: _storageKey, value: jsonEncode([for (final e in _items) e.toJson()]));
    } catch (_) {/* storage unavailable — entries stay in memory */}
  }

  /// Keep every waiting/failed entry, but only the latest synced ones.
  void _prune() {
    final done = _items.where((e) => e.state == SyncState.synced).toList()
      ..sort((a, b) => (b.syncedAt ?? b.createdAt).compareTo(a.syncedAt ?? a.createdAt));
    for (final old in done.skip(_keepSynced)) {
      _items.remove(old);
    }
  }

  /// Called when the app shell opens for a signed-in account.
  void attach(ApiClient api, String? owner) {
    _api = api;
    _owner = (owner == null || owner.isEmpty) ? null : owner;
    _timer ??= Timer.periodic(const Duration(seconds: 20), (_) => _tick());
    unawaited(flush());
  }

  /// Called when the account signs out. Waiting entries stay on the phone.
  void detach() {
    _timer?.cancel();
    _timer = null;
    _api = null;
    _owner = null;
  }

  Future<void> _tick() async {
    if (!online) await _probe();
    await flush();
  }

  Future<void> _probe() async {
    final api = _api;
    if (api == null) return;
    try {
      await api.get('/health');
      if (!online) {
        online = true;
        notifyListeners();
      }
    } on ApiException catch (e) {
      final up = !(e.isNetworkError || e.status >= 500);
      if (up != online) {
        online = up;
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Sends one entry now. When the server cannot be reached the entry is kept
  /// on this phone. Real rejections from the server are thrown unchanged.
  Future<SubmitResult> submit(
    AuthController auth, {
    required String method,
    required String path,
    required Map<String, dynamic> body,
    required String label,
  }) async {
    final api = auth.api;
    final owner = auth.session?.email ?? '';
    final id = _newId();
    try {
      final json = method == 'PUT' ? await api.put(path, body, id) : await api.post(path, body, id);
      online = true;
      return SubmitResult(json: json, queued: false, id: id);
    } on ApiException catch (e) {
      final unreachable = e.isNetworkError || e.status == 502 || e.status == 503 || e.status == 504;
      if (!unreachable) rethrow;
      online = !e.isNetworkError;
      final entry = QueuedEntry(
        id: id,
        owner: owner,
        label: label,
        method: method,
        path: path,
        body: body,
        createdAt: DateTime.now(),
      )..nextAttemptAt = DateTime.now().add(const Duration(seconds: 20));
      _items.add(entry);
      await _persist();
      notifyListeners();
      return SubmitResult(json: null, queued: true, id: id);
    }
  }

  Duration _backoff(int attempts) {
    final secs = 15 * math.pow(2, math.min(attempts, 6)).toInt();
    return Duration(seconds: math.min(secs, 300));
  }

  String? _refOf(dynamic json) {
    if (json is! Map) return null;
    final v = json['code'] ?? json['challan'] ?? json['batchCode'] ?? json['id'];
    return v?.toString();
  }

  /// Sends every due entry of the signed-in account, oldest first. Stops at the
  /// first temporary failure so the order of entries is kept.
  Future<void> flush() async {
    final api = _api;
    final owner = _owner;
    if (_flushing || api == null || owner == null || api.token == null) return;
    if (!_items.any((e) => e.state == SyncState.pending && e.owner == owner)) return;
    _flushing = true;
    var changed = false;
    try {
      for (final e in List<QueuedEntry>.from(_items)) {
        if (e.state != SyncState.pending || e.owner != owner) continue;
        final due = e.nextAttemptAt;
        if (due != null && DateTime.now().isBefore(due)) continue;
        try {
          final json = e.method == 'PUT'
              ? await api.put(e.path, e.body, e.id)
              : await api.post(e.path, e.body, e.id);
          e.state = SyncState.synced;
          e.syncedAt = DateTime.now();
          e.lastError = null;
          e.nextAttemptAt = null;
          e.serverRef = _refOf(json);
          online = true;
          changed = true;
        } on ApiException catch (err) {
          e.attempts++;
          e.lastError = err.message;
          changed = true;
          if (err.unauthenticated) break; // session ended — wait for the next login
          final temporary = err.isNetworkError || err.status >= 500 || err.status == 409 || err.status == 429;
          if (temporary) {
            if (err.isNetworkError) online = false;
            e.nextAttemptAt = DateTime.now().add(_backoff(e.attempts));
            break; // server or network is down — keep the order, try later
          }
          // A real rejection (validation, permission, stock rule) needs a person.
          e.state = SyncState.failed;
          e.nextAttemptAt = null;
        } catch (err) {
          e.attempts++;
          e.lastError = '$err';
          e.nextAttemptAt = DateTime.now().add(_backoff(e.attempts));
          changed = true;
          break;
        }
      }
    } finally {
      _flushing = false;
      if (changed) {
        _prune();
        await _persist();
        notifyListeners();
      }
    }
  }

  /// "Sync now": check the server first, then send everything waiting.
  Future<void> syncNow() async {
    await _probe();
    for (final e in _items) {
      if (e.state == SyncState.pending) e.nextAttemptAt = null;
    }
    await flush();
  }

  /// Re-queue a rejected entry (after the user fixed the cause) and send it now.
  Future<void> retry(QueuedEntry e) async {
    e.state = SyncState.pending;
    e.attempts = 0;
    e.nextAttemptAt = null;
    e.lastError = null;
    await _persist();
    notifyListeners();
    await flush();
  }

  /// Remove an entry the user chose not to send.
  Future<void> discard(QueuedEntry e) async {
    _items.remove(e);
    await _persist();
    notifyListeners();
  }
}
