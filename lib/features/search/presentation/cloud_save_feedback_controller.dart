import 'dart:async';

import 'package:flutter/material.dart';
import 'package:starflow/features/search/domain/cloud_save_feedback.dart';

class CloudSaveFeedbackController {
  CloudSaveFeedbackController(this._context, {required this.isActive});

  final BuildContext? Function() _context;
  final bool Function() isActive;
  final Set<ScaffoldFeatureController<SnackBar, SnackBarClosedReason>>
      _progressControllers = {};
  bool _disposed = false;

  CloudSaveFeedbackSession start() => CloudSaveFeedbackSession._(this);

  ScaffoldMessengerState? get _messenger {
    if (_disposed) return null;
    final context = _context();
    return context != null && context.mounted
        ? ScaffoldMessenger.of(context)
        : null;
  }

  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _replace(
      SnackBar snackBar) {
    final messenger = _messenger;
    if (messenger == null) return null;
    // Forget replaced owners synchronously, before their closed Futures run.
    _progressControllers.clear();
    messenger.clearSnackBars();
    messenger.removeCurrentSnackBar();
    return messenger.showSnackBar(snackBar);
  }

  void _close(
      ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? controller) {
    if (controller != null && _progressControllers.remove(controller)) {
      controller.close();
    }
  }

  void dispose() {
    _disposed = true;
    for (final controller in _progressControllers.toList()) {
      _close(controller);
    }
  }
}

class CloudSaveFeedbackSession {
  CloudSaveFeedbackSession._(this._owner);

  final CloudSaveFeedbackController _owner;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _progress;
  bool _finished = false;
  bool _succeeded = false;
  String? _pendingRefreshFailure;

  void showProgress(CloudSaveProgress progress) {
    if (_finished) return;
    closeProgress();
    final controller = _owner._replace(SnackBar(
      content: Text(progress.message),
      duration: const Duration(minutes: 2),
    ));
    if (controller == null) return;
    _progress = controller;
    _owner._progressControllers.add(controller);
    unawaited(controller.closed.whenComplete(
      () => _owner._progressControllers.remove(controller),
    ));
  }

  void complete(String message) => _finish(message, succeeded: true);

  void fail(String message) => _finish(message, succeeded: false);

  void _finish(String message, {required bool succeeded}) {
    if (_finished) return;
    _finished = true;
    _succeeded = succeeded;
    closeProgress();
    _owner._replace(SnackBar(content: Text(message)));
    final pending = _pendingRefreshFailure;
    _pendingRefreshFailure = null;
    if (pending != null) showRefreshFailure(pending);
  }

  void showRefreshFailure(String message) {
    final messenger = _owner._messenger;
    if (messenger == null || !_owner.isActive()) return;
    // A fast background failure can arrive before the save summary.
    if (!_finished) {
      _pendingRefreshFailure = message;
    } else if (_succeeded) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void closeProgress() {
    _owner._close(_progress);
    _progress = null;
  }
}
