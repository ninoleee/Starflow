import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:starflow/features/settings/data/cloud115_login_client.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';

class Cloud115LoginPage extends ConsumerStatefulWidget {
  const Cloud115LoginPage({super.key});
  @override
  ConsumerState<Cloud115LoginPage> createState() => _Cloud115LoginPageState();
}

class _Cloud115LoginPageState extends ConsumerState<Cloud115LoginPage> {
  Cloud115QrToken? _token;
  String _status = '正在获取二维码';
  int _generation = 0;
  bool _loading = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    super.dispose();
  }

  bool _current(int generation) => mounted && generation == _generation &&
      ModalRoute.of(context)?.isCurrent != false;

  Future<void> _start() async {
    final generation = ++_generation;
    _timer?.cancel();
    setState(() {
      _token = null;
      _loading = true;
      _status = '正在获取二维码';
    });
    try {
      final token = await ref.read(cloud115LoginClientProvider).createToken();
      if (!_current(generation)) return;
      setState(() {
        _token = token;
        _loading = false;
        _status = '等待 115 App 扫码';
      });
      _poll(generation, token, DateTime.now().add(const Duration(minutes: 2)));
    } catch (_) {
      if (_current(generation)) {
        setState(() {
          _loading = false;
          _status = '二维码获取失败，请重试';
        });
      }
    }
  }

  Future<void> _poll(
      int generation, Cloud115QrToken token, DateTime deadline) async {
    if (!_current(generation)) return;
    try {
      if (DateTime.now().isAfter(deadline)) {
        throw const Cloud115LoginException('二维码已过期');
      }
      final status = await ref.read(cloud115LoginClientProvider).status(token);
      if (!_current(generation)) return;
      switch (status) {
        case Cloud115QrStatus.confirmed:
          setState(() {
            _token = null;
            _loading = true;
            _status = '正在完成登录';
          });
          final cookie =
              await ref.read(cloud115LoginClientProvider).exchange(token);
          if (!mounted || !_current(generation)) return;
          Navigator.of(context).pop(cookie);
          return;
        case Cloud115QrStatus.expired:
          throw const Cloud115LoginException('二维码已过期');
        case Cloud115QrStatus.cancelled:
          throw const Cloud115LoginException('登录已取消');
        case Cloud115QrStatus.waiting:
        case Cloud115QrStatus.scanned:
          setState(() => _status = status == Cloud115QrStatus.scanned
              ? '已扫码，请在手机上确认'
              : '等待 115 App 扫码');
          _timer = Timer(const Duration(seconds: 2),
              () => _poll(generation, token, deadline));
      }
    } catch (error) {
      if (!_current(generation)) return;
      setState(() {
        _token = null;
        _loading = false;
        _status = error is Cloud115LoginException ? error.message : '登录未完成，请重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) => SettingsPageScaffold(
        onBack: () => Navigator.of(context).pop(),
        children: [
          Text('115 扫码登录', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          Center(
              child: SizedBox(
                  width: 256,
                  height: 256,
                  child: _token != null
                      ? QrImageView(
                          data: _token!.qrcode,
                          backgroundColor: Colors.white,
                          size: 256)
                      : _loading
                          ? const Center(child: CircularProgressIndicator())
                          : const Icon(Icons.qr_code_rounded, size: 96))),
          const SizedBox(height: 16),
          Center(child: Text(_status)),
          const SizedBox(height: 16),
          SettingsActionButton(
              label: '刷新二维码',
              icon: Icons.refresh_rounded,
              onPressed: _loading ? null : _start),
        ],
      );
}
