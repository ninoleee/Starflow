import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/features/settings/data/aliyun_open_login_client.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';

class AliyunOpenLoginPage extends ConsumerStatefulWidget {
  const AliyunOpenLoginPage({super.key});

  @override
  ConsumerState<AliyunOpenLoginPage> createState() =>
      _AliyunOpenLoginPageState();
}

class _AliyunOpenLoginPageState extends ConsumerState<AliyunOpenLoginPage>
    with WidgetsBindingObserver {
  AliyunOpenQrToken? _token;
  String _status = '正在获取二维码';
  int _generation = 0;
  bool _loading = true;
  Timer? _timer;
  Timer? _clock;
  DateTime? _deadline;
  bool _foreground = true;
  int _failures = 0;
  int _seconds = 120;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    final token = _token;
    if (token != null) {
      try {
        unawaited(ref.read(aliyunOpenLoginClientProvider).logout(token));
      } catch (_) {
        // The server session expires on its own; local cleanup must not fail.
      }
    }
    _generation++;
    _timer?.cancel();
    _clock?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool _current(int generation) =>
      mounted &&
      generation == _generation &&
      _foreground &&
      ModalRoute.of(context)?.isCurrent != false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _generation++;
    _timer?.cancel();
    if (!_foreground) return;
    final token = _token;
    final deadline = _deadline;
    if (token != null && deadline != null) {
      unawaited(_poll(_generation, token, deadline));
    } else {
      unawaited(_start());
    }
  }

  void _fail(int generation, Object error) {
    if (!_current(generation)) return;
    _clock?.cancel();
    setState(() {
      _token = null;
      _loading = false;
      _status = error is AliyunOpenLoginException
          ? error.message
          : '阿里 Open 登录未完成，请重试';
    });
  }

  Future<void> _start() async {
    final generation = ++_generation;
    _timer?.cancel();
    _clock?.cancel();
    _failures = 0;
    setState(() {
      _token = null;
      _loading = true;
      _status = '正在获取二维码';
    });
    try {
      final token = await ref.read(aliyunOpenLoginClientProvider).createToken();
      if (!_current(generation)) return;
      final deadline = DateTime.now().add(token.expiresIn);
      setState(() {
        _token = token;
        _loading = false;
        _status = '等待阿里云盘 App 扫码';
        _seconds = token.expiresIn.inSeconds;
      });
      _deadline = deadline;
      _clock = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted ||
            !_foreground ||
            ModalRoute.of(context)?.isCurrent == false) {
          return;
        }
        final left = deadline.difference(DateTime.now()).inSeconds;
        setState(() => _seconds = left < 0 ? 0 : left);
        if (left <= 0) {
          _timer?.cancel();
          _fail(_generation, const AliyunOpenLoginException('二维码已过期'));
          _generation++;
        }
      });
      unawaited(_poll(generation, token, deadline));
    } catch (error) {
      _fail(generation, error);
    }
  }

  Future<void> _poll(
      int generation, AliyunOpenQrToken token, DateTime deadline) async {
    if (!mounted || generation != _generation || !_foreground) return;
    if (ModalRoute.of(context)?.isCurrent == false) {
      _timer = Timer(
          const Duration(seconds: 2), () => _poll(generation, token, deadline));
      return;
    }
    try {
      if (!DateTime.now().isBefore(deadline)) {
        throw const AliyunOpenLoginException('二维码已过期');
      }
      final client = ref.read(aliyunOpenLoginClientProvider);
      final result = await client.status(token);
      if (!mounted || generation != _generation || !_foreground) return;
      if (ModalRoute.of(context)?.isCurrent == false) {
        _timer = Timer(const Duration(seconds: 2),
            () => _poll(generation, token, deadline));
        return;
      }
      if (!DateTime.now().isBefore(deadline)) {
        throw const AliyunOpenLoginException('二维码已过期');
      }
      _failures = 0;
      switch (result.status) {
        case AliyunOpenQrStatus.confirmed:
          final credentials = await client.complete(token);
          if (!mounted || generation != _generation) return;
          _generation++;
          _clock?.cancel();
          Navigator.of(context).pop(credentials);
          return;
        case AliyunOpenQrStatus.expired:
          throw const AliyunOpenLoginException('二维码已过期');
        case AliyunOpenQrStatus.cancelled:
          throw const AliyunOpenLoginException('登录已取消');
        case AliyunOpenQrStatus.waiting:
        case AliyunOpenQrStatus.scanned:
          setState(() => _status = result.status == AliyunOpenQrStatus.scanned
              ? '已扫码，请在手机上确认'
              : '等待阿里云盘 App 扫码');
          _timer = Timer(const Duration(seconds: 2),
              () => _poll(generation, token, deadline));
      }
    } catch (error) {
      if (mounted &&
          generation == _generation &&
          _foreground &&
          ModalRoute.of(context)?.isCurrent == false) {
        _timer = Timer(const Duration(seconds: 2),
            () => _poll(generation, token, deadline));
        return;
      }
      if (_current(generation) &&
          error is AliyunOpenLoginException &&
          error.retryable &&
          ++_failures <= 3 &&
          DateTime.now().isBefore(deadline)) {
        setState(() => _status = '连接中断，正在重试（$_failures/3）');
        _timer = Timer(Duration(seconds: 2 * _failures),
            () => _poll(generation, token, deadline));
        return;
      }
      _fail(generation, error);
    }
  }

  @override
  Widget build(BuildContext context) => SettingsPageScaffold(
          onBack: () => Navigator.of(context).pop(),
          children: [
            Text('阿里开放平台扫码登录',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            Center(
                child: SizedBox(
                    width: ref.watch(isTelevisionProvider).value == true
                        ? 360
                        : 256,
                    height: ref.watch(isTelevisionProvider).value == true
                        ? 360
                        : 256,
                    child: _token != null
                        ? QrImageView(data: _token!.qrCodeUrl)
                        : const Center(child: CircularProgressIndicator()))),
            const SizedBox(height: 16),
            Text(_loading ? '正在获取二维码' : _status),
            const SizedBox(height: 8),
            Text('剩余 $_seconds 秒'),
            const SizedBox(height: 16),
            TextButton.icon(
                onPressed: _loading ? null : _start,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('刷新二维码')),
          ]);
}
