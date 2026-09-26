import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/features/settings/data/aliyun_login_client.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';

class AliyunLoginPage extends ConsumerStatefulWidget {
  const AliyunLoginPage({super.key});
  @override
  ConsumerState<AliyunLoginPage> createState() => _AliyunLoginPageState();
}

class _AliyunLoginPageState extends ConsumerState<AliyunLoginPage>
    with WidgetsBindingObserver {
  AliyunQrToken? _token;
  String _status = '正在获取二维码';
  int _generation = 0;
  bool _loading = true;
  Timer? _timer;
  Timer? _clock;
  DateTime? _deadline;
  bool _foreground = true;
  int _failures = 0;
  int _seconds = 120;
  bool _exporting = false;

  Future<void> _saveQr() async {
    final token = _token;
    if (token == null || _exporting) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('保存登录二维码到相册？'),
                content: const Text('二维码属于临时登录凭据，请勿发送给他人；登录后请删除相册副本。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('保存'))
                ]));
    if (!mounted ||
        confirmed != true ||
        token != _token ||
        _deadline == null ||
        !DateTime.now().isBefore(_deadline!)) {
      return;
    }
    setState(() => _exporting = true);
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)
        ..drawColor(Colors.white, BlendMode.src)
        ..translate(32, 32);
      QrPainter(data: token.qrcode, version: QrVersions.auto)
          .paint(canvas, const Size(536, 536));
      final picture = recorder.endRecording();
      final image = await picture.toImage(600, 600);
      picture.dispose();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (!mounted ||
          token != _token ||
          bytes == null ||
          !DateTime.now().isBefore(_deadline!)) {
        return;
      }
      final saved = await const MethodChannel('starflow/platform')
          .invokeMethod<bool>('saveLoginQrImage', bytes.buffer.asUint8List());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(saved == true ? '二维码已保存到相册' : '未保存，请检查相册添加权限')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('二维码保存失败')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
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
      _status = error is AliyunLoginException ? error.message : '登录未完成，请重试';
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
      final token = await ref.read(aliyunLoginClientProvider).createToken();
      if (!_current(generation)) return;
      setState(() {
        _token = token;
        _loading = false;
        _status = '等待阿里云盘 App 扫码';
        _seconds = 120;
      });
      _deadline = DateTime.now().add(const Duration(minutes: 2));
      _clock = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted ||
            !_foreground ||
            ModalRoute.of(context)?.isCurrent == false) {
          return;
        }
        final left =
            _deadline!.difference(DateTime.now()).inSeconds.clamp(0, 120);
        setState(() => _seconds = left);
        if (left == 0) {
          _timer?.cancel();
          _fail(_generation, const AliyunLoginException('二维码已过期'));
          _generation++;
        }
      });
      unawaited(_poll(generation, token, _deadline!));
    } catch (error) {
      _fail(generation, error);
    }
  }

  Future<void> _poll(
      int generation, AliyunQrToken token, DateTime deadline) async {
    if (!mounted || generation != _generation || !_foreground) return;
    if (ModalRoute.of(context)?.isCurrent == false) {
      _timer = Timer(
          const Duration(seconds: 2), () => _poll(generation, token, deadline));
      return;
    }
    try {
      if (!DateTime.now().isBefore(deadline)) {
        throw const AliyunLoginException('二维码已过期');
      }
      final result = await ref.read(aliyunLoginClientProvider).status(token);
      if (!mounted || generation != _generation || !_foreground) return;
      if (ModalRoute.of(context)?.isCurrent == false) {
        _timer = Timer(const Duration(seconds: 2),
            () => _poll(generation, token, deadline));
        return;
      }
      if (!DateTime.now().isBefore(deadline)) {
        throw const AliyunLoginException('二维码已过期');
      }
      _failures = 0;
      switch (result.status) {
        case AliyunQrStatus.confirmed:
          if (result.refreshToken?.isNotEmpty != true) {
            throw const AliyunLoginException('阿里未返回登录凭据，请重新扫码');
          }
          _generation++;
          _clock?.cancel();
          Navigator.of(context).pop(result.refreshToken);
          return;
        case AliyunQrStatus.expired:
          throw const AliyunLoginException('二维码已过期');
        case AliyunQrStatus.cancelled:
          throw const AliyunLoginException('登录已取消');
        case AliyunQrStatus.waiting:
        case AliyunQrStatus.scanned:
          setState(() => _status = result.status == AliyunQrStatus.scanned
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
          error is AliyunLoginException &&
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
          Text('阿里扫码登录', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          Center(
              child: SizedBox(
                  width:
                      ref.watch(isTelevisionProvider).value == true ? 360 : 256,
                  height:
                      ref.watch(isTelevisionProvider).value == true ? 360 : 256,
                  child: _token != null
                      ? QrImageView(
                          data: _token!.qrcode,
                          backgroundColor: Colors.white,
                          size: ref.watch(isTelevisionProvider).value == true
                              ? 360
                              : 256)
                      : _loading
                          ? const Center(child: CircularProgressIndicator())
                          : const Icon(Icons.qr_code_rounded, size: 96))),
          const SizedBox(height: 16),
          Center(child: Text(_status)),
          if (_token != null) Center(child: Text('剩余 $_seconds 秒')),
          const SizedBox(height: 16),
          SettingsActionButton(
              label: '刷新二维码',
              icon: Icons.refresh_rounded,
              autofocus: true,
              onPressed: _loading ? null : _start),
          if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
            SettingsActionButton(
                label: '保存二维码到相册',
                icon: Icons.save_alt_rounded,
                onPressed: _token == null || _exporting ? null : _saveQr),
        ],
      );
}
