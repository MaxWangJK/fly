import 'dart:async';
import 'dart:convert';
import 'dart:io';

class AnalyticsState {
  const AnalyticsState({
    required this.deviceCode,
    this.installReported = false,
    this.lastOpenDate,
  });
  final String deviceCode;
  final bool installReported;
  final String? lastOpenDate;

  AnalyticsState copyWith({bool? installReported, String? lastOpenDate}) =>
      AnalyticsState(
        deviceCode: deviceCode,
        installReported: installReported ?? this.installReported,
        lastOpenDate: lastOpenDate ?? this.lastOpenDate,
      );

  Map<String, Object?> toJson() => {
    'analyticsDeviceCode': deviceCode,
    'analyticsInstallReported': installReported,
    'lastAnalyticsOpenDate': lastOpenDate,
  };

  factory AnalyticsState.fromJson(Map<String, dynamic> value) {
    final code = value['analyticsDeviceCode'];
    if (code is! String || !RegExp(r'^[A-Za-z0-9]{8,32}$').hasMatch(code)) {
      throw const FormatException(
        'Invalid anonymous installation configuration',
      );
    }
    return AnalyticsState(
      deviceCode: code,
      installReported: value['analyticsInstallReported'] == true,
      lastOpenDate: value['lastAnalyticsOpenDate'] as String?,
    );
  }
}

abstract interface class AnalyticsStorage {
  Future<AnalyticsState> loadOrCreate(String Function() generateCode);
  Future<void> markInstallReported(String code);
  Future<void> markDailyOpenReported(String code, String day);
}

/// Stored in application support, outside FlyData, backups and cloud sync.
class FileAnalyticsStorage implements AnalyticsStorage {
  FileAnalyticsStorage(this.file);
  final File file;
  static final _pending = <String, Future<void>>{};

  Future<T> _transaction<T>(Future<T> Function() action) async {
    final path = file.absolute.path;
    final previous = _pending[path] ?? Future<void>.value();
    final done = Completer<void>();
    _pending[path] = done.future;
    await previous;
    RandomAccessFile? lock;
    try {
      await file.parent.create(recursive: true);
      lock = await File('${file.path}.lock').open(mode: FileMode.append);
      await lock.lock(FileLock.blockingExclusive);
      return await action();
    } finally {
      try {
        await lock?.close();
      } finally {
        done.complete();
        if (identical(_pending[path], done.future)) _pending.remove(path);
      }
    }
  }

  Future<AnalyticsState> _read() async => AnalyticsState.fromJson(
    (jsonDecode(await file.readAsString()) as Map).cast<String, dynamic>(),
  );

  Future<void> _write(AnalyticsState state) async {
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(state.toJson()), flush: true);
    await temporary.rename(file.path);
  }

  @override
  Future<AnalyticsState> loadOrCreate(String Function() generateCode) =>
      _transaction(() async {
        if (await file.exists()) return _read();
        final state = AnalyticsState(deviceCode: generateCode());
        await _write(state); // Persist identity before any request is sent.
        return state;
      });

  @override
  Future<void> markInstallReported(String code) => _transaction(() async {
    final state = await _read();
    if (state.deviceCode == code) {
      await _write(state.copyWith(installReported: true));
    }
  });

  @override
  Future<void> markDailyOpenReported(String code, String day) =>
      _transaction(() async {
        final state = await _read();
        if (state.deviceCode == code) {
          await _write(state.copyWith(lastOpenDate: day));
        }
      });
}
