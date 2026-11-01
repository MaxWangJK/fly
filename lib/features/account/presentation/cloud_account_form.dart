import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/fly_localizations.dart';
import '../../sync/presentation/sync_controller.dart';
import '../data/auth_service.dart';

enum CloudAccountOperation { signIn, resetPassword, deleteAccount }

Future<void> showCloudAccountOperation(
  BuildContext context, {
  required SyncController controller,
  required Future<bool> Function() prepare,
  required CloudAccountOperation operation,
}) async {
  final zh = context.l10n.isZh;
  final deleted = operation == CloudAccountOperation.deleteAccount;
  final completed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: CloudAccountForm(
            controller: controller,
            prepare: prepare,
            operation: operation,
            initialEmail: controller.auth.email,
            onSuccess: () async {
              if (dialogContext.mounted) Navigator.pop(dialogContext, true);
            },
          ),
        ),
      ),
    ),
  );
  if (completed == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        content: Text(
          deleted
              ? (zh
                        ? '云端账号已注销，本机数据已保留。'
                        : 'Cloud account deleted. Local data is preserved.') +
                    (controller.accountFileCleanupPending
                        ? (zh
                              ? '旧云端文件正在后台清理。'
                              : 'Legacy cloud files are being cleaned up.')
                        : '')
              : (zh
                    ? '密码已重置，请重新登录。其他设备也需要重新登录。'
                    : 'Password reset. Sign in again on all devices.'),
        ),
      ),
    );
  }
}

class CloudAccountForm extends StatefulWidget {
  const CloudAccountForm({
    required this.controller,
    required this.prepare,
    required this.onSuccess,
    this.operation = CloudAccountOperation.signIn,
    this.initialEmail,
    super.key,
  });
  final SyncController controller;
  final Future<bool> Function() prepare;
  final Future<void> Function() onSuccess;
  final CloudAccountOperation operation;
  final String? initialEmail;
  @override
  State<CloudAccountForm> createState() => _CloudAccountFormState();
}

class _CloudAccountFormState extends State<CloudAccountForm> {
  final email = TextEditingController(),
      password = TextEditingController(),
      confirm = TextEditingController(),
      graphic = TextEditingController(),
      code = TextEditingController();
  bool registering = false, busy = false, reveal = false, confirmDelete = false;
  bool get recovering =>
      widget.operation == CloudAccountOperation.resetPassword;
  bool get deleting => widget.operation == CloudAccountOperation.deleteAccount;
  int step = 0;
  String? error, ticket, proofServer;
  EmailCaptcha? captcha;
  DateTime? nextSend;
  Timer? timer;
  bool get binding =>
      !recovering && !deleting && widget.controller.auth.userId != null;
  int get remaining => nextSend == null
      ? 0
      : (nextSend!.difference(DateTime.now()).inMilliseconds / 1000)
            .ceil()
            .clamp(0, 3600);
  String t(String cn, String en) => context.l10n.isZh ? cn : en;
  @override
  void initState() {
    super.initState();
    registering = recovering || deleting;
    email.text = widget.initialEmail ?? '';
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && nextSend != null) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    for (final c in [email, password, confirm, graphic, code]) {
      c.dispose();
    }
    super.dispose();
  }

  void resetProof() {
    step = 0;
    captcha = null;
    ticket = null;
    proofServer = null;
    graphic.clear();
    code.clear();
    password.clear();
    confirm.clear();
    confirmDelete = false;
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy || widget.controller.busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = failure is EmailAuthException
              ? (context.l10n.isZh
                    ? failure.message.split(' / ').first
                    : failure.message.split(' / ').last)
              : failure.toString().replaceFirst(
                  RegExp(r'^(Bad state: |Invalid argument\(s\): )'),
                  '',
                ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<AuthService> prepare() async {
    if (!await widget.prepare()) {
      throw StateError(
        widget.controller.error ?? t('无法连接服务器', 'Cannot connect to server'),
      );
    }
    final auth = widget.controller.auth;
    if (proofServer != null && proofServer != auth.server) {
      resetProof();
      throw EmailAuthException(
        t('服务器已改变，请重新验证邮箱', 'Server changed. Verify your email again.'),
      );
    }
    return auth;
  }

  void validateEmail() {
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.text.trim())) {
      throw EmailAuthException(t('请填写有效的邮箱地址', 'Enter a valid email address'));
    }
  }

  Future<void> loadCaptcha() => run(() async {
    validateEmail();
    final auth = await prepare();
    final result = await auth.registrationCaptcha(
      email.text,
      bind: binding,
      purpose: recovering
          ? 'reset'
          : deleting
          ? 'delete'
          : null,
    );
    if (!mounted) return;
    setState(() {
      captcha = result;
      proofServer = auth.server;
      graphic.clear();
      step = 0;
    });
  });
  Future<void> sendCode() => run(() async {
    validateEmail();
    if (captcha == null || graphic.text.trim().length != 4) {
      throw EmailAuthException(
        t('请输入四位图形验证码', 'Enter the four-character graphical code'),
      );
    }
    final auth = await prepare();
    final seconds = await auth.sendRegistrationCode(captcha!.id, graphic.text);
    if (mounted) {
      setState(() {
        nextSend = DateTime.now().add(Duration(seconds: seconds));
        step = 1;
        code.clear();
      });
    }
  });
  Future<void> verifyCode() => run(() async {
    if (!RegExp(r'^\d{6}$').hasMatch(code.text)) {
      throw EmailAuthException(
        t('请输入六位邮箱验证码', 'Enter the six-digit email code'),
      );
    }
    final auth = await prepare();
    final value = await auth.verifyRegistrationCode(captcha!.id, code.text);
    if (mounted) {
      setState(() {
        ticket = value;
        step = 2;
      });
    }
  });
  Future<void> submit() => run(() async {
    validateEmail();
    if (password.text.runes.length < 10 ||
        (registering && !deleting && password.text.runes.length > 128)) {
      throw EmailAuthException(
        t('密码需为 10–128 个字符', 'Use a password of 10–128 characters'),
      );
    }
    if (registering && !deleting && password.text != confirm.text) {
      throw EmailAuthException(t('两次输入的密码不一致', 'The passwords do not match'));
    }
    await prepare();
    if (deleting) {
      if (!confirmDelete) {
        throw EmailAuthException(t('请确认注销范围', 'Confirm what will be deleted'));
      }
      await widget.controller.deleteAccount(
        password: password.text,
        verificationTicket: ticket!,
      );
    } else if (recovering) {
      await widget.controller.resetPassword(
        email: email.text,
        password: password.text,
        confirm: confirm.text,
        verificationTicket: ticket!,
      );
    } else {
      await widget.controller.login(
        registering,
        email.text,
        password.text,
        confirm.text,
        verificationTicket: ticket,
        bindEmail: registering && binding,
      );
    }
    if (widget.controller.error != null) {
      throw StateError(widget.controller.error!);
    }
    if (mounted) {
      password.clear();
      confirm.clear();
    }
    await widget.onSuccess();
  });
  Widget field(
    TextEditingController c,
    String label,
    String key, {
    bool secret = false,
    TextInputType? keyboard,
    List<TextInputFormatter>? formatters,
    int? maxLength,
    Iterable<String>? autofillHints,
    ValueChanged<String>? onChanged,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextField(
      key: ValueKey(key),
      controller: c,
      enabled: !busy && !widget.controller.busy,
      readOnly: deleting && c == email,
      obscureText: secret && !reveal,
      enableSuggestions: !secret,
      autocorrect: false,
      keyboardType: keyboard,
      inputFormatters: formatters,
      maxLength: maxLength,
      autofillHints: autofillHints,
      onChanged: onChanged,
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        suffixIcon: secret
            ? IconButton(
                tooltip: reveal
                    ? t('隐藏密码', 'Hide password')
                    : t('显示密码', 'Show password'),
                onPressed: () => setState(() => reveal = !reveal),
                icon: Icon(
                  reveal
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              )
            : null,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final disabled = busy || widget.controller.busy;
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !busy && !widget.controller.busy,
      child: AutofillGroup(
        child: Card(
          margin: const EdgeInsets.only(top: 16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  deleting
                      ? t('注销云同步账号', 'Delete cloud account')
                      : recovering
                      ? t('找回或修改密码', 'Reset password')
                      : binding
                      ? t('为当前同步空间绑定邮箱', 'Add email to this sync space')
                      : registering
                      ? t('创建云同步账号', 'Create a cloud account')
                      : t('登录云同步', 'Sign in to cloud sync'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                if (deleting || recovering) ...[
                  Text(
                    deleting
                        ? t(
                            '永久删除云端账号、任务、客户、订单、复盘及其他同步数据，所有设备退出登录。本机数据和文件保留，局域网同步仍可使用。新账号请使用独立数据目录。',
                            'Permanently delete this cloud account and all synced records. All devices will be signed out. Local data and files are kept; local sync remains available. Use a separate data folder for a new account.',
                          )
                        : t(
                            '验证邮箱后设置新密码。云端数据保留，所有设备均需重新登录。',
                            'Verify your email and set a new password. Cloud data is preserved. All devices must sign in again.',
                          ),
                  ),
                  const SizedBox(height: 14),
                ],
                if (binding && !registering) ...[
                  Text(
                    t(
                      '验证邮箱并设置密码后，其他设备可用同一邮箱登录，现有数据和同步空间保持不变。',
                      'Verify an email and set a password to sign in on other devices while keeping this space and its data.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    key: const ValueKey('cloud-bind-email'),
                    onPressed: disabled
                        ? null
                        : () => setState(() => registering = true),
                    child: Text(
                      t('绑定邮箱并设置密码', 'Verify email and set password'),
                    ),
                  ),
                ] else ...[
                  if (registering) ...[
                    Text(
                      t(
                        '${step + 1} / 3 · ${['邮箱与图形验证', '验证邮箱', deleting ? '确认注销' : '设置密码'][step]}',
                        '${step + 1} / 3 · ${['Email and graphical check', 'Verify email', deleting ? 'Confirm deletion' : 'Set password'][step]}',
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (!registering || step == 0)
                    field(
                      email,
                      t('邮箱地址', 'Email address'),
                      'cloud-email',
                      keyboard: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      onChanged: registering
                          ? (_) => setState(resetProof)
                          : null,
                    )
                  else
                    Text(
                      email.text.trim(),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  if (!registering) ...[
                    field(
                      password,
                      t('登录密码', 'Password'),
                      'cloud-password',
                      secret: true,
                      autofillHints: const [AutofillHints.password],
                    ),
                    FilledButton(
                      key: const ValueKey('cloud-login'),
                      onPressed: disabled ? null : submit,
                      child: Text(t('登录并开启云同步', 'Sign in and sync')),
                    ),
                    TextButton(
                      key: const ValueKey('cloud-forgot-password'),
                      onPressed: disabled
                          ? null
                          : () => showCloudAccountOperation(
                              context,
                              controller: widget.controller,
                              prepare: widget.prepare,
                              operation: CloudAccountOperation.resetPassword,
                            ),
                      child: Text(t('忘记密码？', 'Forgot password?')),
                    ),
                    TextButton(
                      key: const ValueKey('cloud-show-register'),
                      onPressed: disabled
                          ? null
                          : () => setState(() {
                              registering = true;
                              resetProof();
                            }),
                      child: Text(
                        t('没有账号？创建账号', 'New here? Create an account'),
                      ),
                    ),
                  ] else if (step == 0) ...[
                    if (captcha == null)
                      OutlinedButton.icon(
                        key: const ValueKey('cloud-load-captcha'),
                        onPressed: disabled ? null : loadCaptcha,
                        icon: const Icon(Icons.verified_user_outlined),
                        label: Text(t('获取图形验证码', 'Get graphical verification')),
                      )
                    else ...[
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Image.memory(
                            captcha!.image,
                            width: 200,
                            height: 72,
                            semanticLabel: t(
                              '图形验证码，输入图片中的四个字符',
                              'Graphical verification: enter the four characters',
                            ),
                            errorBuilder: (_, _, _) => Text(
                              t('图形加载失败，请刷新', 'Image failed. Please refresh.'),
                            ),
                          ),
                          TextButton.icon(
                            key: const ValueKey('cloud-refresh-captcha'),
                            onPressed: disabled ? null : loadCaptcha,
                            icon: const Icon(Icons.refresh),
                            label: Text(t('换一张', 'Refresh')),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      field(
                        graphic,
                        t('图形验证码（不区分大小写）', 'Graphical code (case-insensitive)'),
                        'cloud-captcha',
                        maxLength: 4,
                        formatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp('[a-zA-Z0-9]'),
                          ),
                        ],
                      ),
                      FilledButton(
                        key: const ValueKey('cloud-send-code'),
                        onPressed: disabled || remaining > 0 ? null : sendCode,
                        child: Text(
                          remaining > 0
                              ? t('$remaining 秒后可发送', 'Send in $remaining s')
                              : t('发送六位邮箱验证码', 'Send six-digit email code'),
                        ),
                      ),
                    ],
                  ] else if (step == 1) ...[
                    const SizedBox(height: 14),
                    Text(
                      t(
                        '验证码已发送，5 分钟内有效。请检查垃圾邮件，并核对邮件中的操作用途。',
                        'Code sent, valid for 5 minutes. Check spam and confirm the action shown in the email.',
                      ),
                    ),
                    const SizedBox(height: 14),
                    field(
                      code,
                      t('六位邮箱验证码', 'Six-digit email code'),
                      'cloud-email-code',
                      keyboard: TextInputType.number,
                      maxLength: 6,
                      formatters: [FilteringTextInputFormatter.digitsOnly],
                      autofillHints: const [AutofillHints.oneTimeCode],
                    ),
                    FilledButton(
                      key: const ValueKey('cloud-verify-code'),
                      onPressed: disabled ? null : verifyCode,
                      child: Text(t('验证并继续', 'Verify and continue')),
                    ),
                    TextButton(
                      key: const ValueKey('cloud-resend-code'),
                      onPressed: disabled || remaining > 0
                          ? null
                          : () {
                              setState(() => step = 0);
                              loadCaptcha();
                            },
                      child: Text(
                        remaining > 0
                            ? t('$remaining 秒后可重新发送', 'Resend in $remaining s')
                            : t(
                                '重新发送（需再次图形验证）',
                                'Resend with a new graphical check',
                              ),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 14),
                    Text(
                      t(
                        deleting
                            ? '邮箱已验证。输入当前密码，并确认删除范围。'
                            : '邮箱已验证。设置 10–128 个字符的密码。',
                        deleting
                            ? 'Email verified. Enter your current password and confirm deletion.'
                            : 'Email verified. Use a password of 10–128 characters.',
                      ),
                    ),
                    const SizedBox(height: 14),
                    field(
                      password,
                      deleting
                          ? t('当前登录密码', 'Current password')
                          : t('设置登录密码', 'Create password'),
                      'cloud-password',
                      secret: true,
                      autofillHints: [
                        deleting
                            ? AutofillHints.password
                            : AutofillHints.newPassword,
                      ],
                    ),
                    if (!deleting)
                      field(
                        confirm,
                        t('确认登录密码', 'Confirm password'),
                        'cloud-confirm-password',
                        secret: true,
                        autofillHints: const [AutofillHints.newPassword],
                      ),
                    if (deleting)
                      CheckboxListTile(
                        key: const ValueKey('cloud-confirm-delete'),
                        contentPadding: EdgeInsets.zero,
                        value: confirmDelete,
                        onChanged: disabled
                            ? null
                            : (v) => setState(() => confirmDelete = v ?? false),
                        title: Text(
                          t(
                            '我理解云端数据将永久删除，本机数据保留',
                            'I understand cloud data will be permanently deleted and local data kept',
                          ),
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    FilledButton(
                      key: ValueKey(
                        deleting
                            ? 'cloud-delete-account'
                            : recovering
                            ? 'cloud-reset-password'
                            : 'cloud-complete-register',
                      ),
                      style: deleting
                          ? FilledButton.styleFrom(
                              backgroundColor: colors.error,
                              foregroundColor: colors.onError,
                            )
                          : null,
                      onPressed: disabled || (deleting && !confirmDelete)
                          ? null
                          : submit,
                      child: Text(
                        deleting
                            ? t('永久注销账号', 'Permanently delete account')
                            : recovering
                            ? t('重置密码', 'Reset password')
                            : binding
                            ? t('完成绑定并同步', 'Link email and sync')
                            : t('完成注册并同步', 'Create account and sync'),
                      ),
                    ),
                  ],
                  if (registering)
                    TextButton(
                      key: const ValueKey('cloud-auth-back'),
                      onPressed: disabled
                          ? null
                          : () => setState(() {
                              if (step > 0) {
                                resetProof();
                              } else if (recovering || deleting) {
                                Navigator.maybePop(context);
                              } else {
                                registering = false;
                                resetProof();
                              }
                            }),
                      child: Text(
                        step > 0
                            ? t('更换邮箱或重新验证', 'Change email or verify again')
                            : recovering || deleting
                            ? t('取消', 'Cancel')
                            : binding
                            ? t('暂不绑定', 'Not now')
                            : t('已有账号，返回登录', 'Already registered? Sign in'),
                      ),
                    ),
                ],
                if (busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(),
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(error!, style: TextStyle(color: colors.error)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
