import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/feature_flags.dart';
import '../../l10n/fly_localizations.dart';
import 'local_license_service.dart';

class LocalLicenseGate extends StatefulWidget {
  const LocalLicenseGate({super.key, required this.child});
  final Widget child;
  @override
  State<LocalLicenseGate> createState() => _LocalLicenseGateState();
}

class _LocalLicenseGateState extends State<LocalLicenseGate>
    with WidgetsBindingObserver {
  final _service = LocalLicenseService(
    storage: WindowsLicenseStorage(),
    publicKey: localLicensePublicKey,
  );
  final _input = TextEditingController();
  LocalLicenseState? _state;
  Timer? _timer;
  bool _busy = false;
  bool _showActivation = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
    _timer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(_refresh()),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh({bool activate = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final next = await _service.refresh(
        activation: activate ? _input.text.trim() : null,
      );
      if (!mounted) return;
      setState(() {
        _state = next;
        if (activate) {
          _showActivation = false;
          _input.clear();
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is LicenseFailure ? e.key : 'licenseStorageError';
          // An invalid activation must not erase a still-valid session. Storage
          // failures, however, fail closed until the protected state can be read.
          if (!activate || _error == 'licenseStorageError') _state = null;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n.t;
    final allowed = _state?.allowed ?? false;
    final locked = !allowed || _showActivation;
    return Stack(
      children: [
        // Keep live editors mounted when time expires; do not discard drafts.
        Offstage(
          offstage: locked,
          child: ExcludeFocus(
            excluding: locked,
            child: IgnorePointer(
              ignoring: locked,
              child: TickerMode(enabled: !locked, child: widget.child),
            ),
          ),
        ),
        if (locked)
          Positioned.fill(
            child: Scaffold(
              body: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          t(allowed ? 'licenseActivate' : 'licenseLocked'),
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 12),
                        Text(t('licenseDataSafe')),
                        const SizedBox(height: 20),
                        Text(t('licenseMachine')),
                        SelectableText(_service.machineCode),
                        TextButton.icon(
                          onPressed: _service.machineCode.isEmpty
                              ? null
                              : () => Clipboard.setData(
                                  ClipboardData(text: _service.machineCode),
                                ),
                          icon: const Icon(Icons.copy_outlined),
                          label: Text(t('licenseCopyMachine')),
                        ),
                        TextField(
                          controller: _input,
                          minLines: 3,
                          maxLines: 6,
                          enabled: !_busy,
                          decoration: InputDecoration(
                            labelText: t('licenseKey'),
                          ),
                          onSubmitted: (_) => _refresh(activate: true),
                        ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              t(_error!),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _busy
                              ? null
                              : () => _refresh(activate: true),
                          child: Text(t('licenseActivate')),
                        ),
                        TextButton(
                          onPressed: _busy ? null : () => _refresh(),
                          child: Text(t('licenseRetry')),
                        ),
                        if (allowed)
                          TextButton(
                            onPressed: () =>
                                setState(() => _showActivation = false),
                            child: Text(t('licenseContinue')),
                          ),
                        if (_busy) const LinearProgressIndicator(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (!locked && _state!.isTrial)
          Positioned(
            right: 12,
            bottom: 8,
            child: Material(
              elevation: 2,
              borderRadius: BorderRadius.circular(8),
              child: TextButton(
                onPressed: () => setState(() => _showActivation = true),
                child: Text(
                  '${t('licenseTrialUntil')} ${_state!.expiresAt.toLocal().toString().substring(0, 16)} · ${t('licenseActivate')}',
                ),
              ),
            ),
          ),
      ],
    );
  }
}
