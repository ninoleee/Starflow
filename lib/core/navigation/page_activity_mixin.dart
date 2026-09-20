import 'package:flutter/widgets.dart';

mixin PageActivityMixin<T extends StatefulWidget> on State<T> {
  bool _isPageActive = false;
  bool _desiredPageActive = false;
  bool _activityDispatchScheduled = false;
  AppLifecycleListener? _appLifecycleListener;

  bool get isPageActive => _isPageActive;
  bool get isPageVisible => _desiredPageActive;

  @protected
  void onPageBecameActive() {}

  @protected
  void onPageBecameInactive() {}

  @protected
  void refreshPageActivity() {
    if (!mounted) {
      return;
    }
    final route = ModalRoute.of(context);
    final nextVisible = (route == null || route.isCurrent) &&
        TickerMode.of(context) &&
        _appAllowsPageActivity(WidgetsBinding.instance.lifecycleState);
    // Backgrounding can stop frames entirely. Cancel page work even if a
    // route-driven deactivation is already queued for the end of a frame.
    if (!_appAllowsPageActivity(WidgetsBinding.instance.lifecycleState)) {
      _desiredPageActive = false;
      _dispatchPageActivity();
      return;
    }
    if (_desiredPageActive == nextVisible &&
        (_activityDispatchScheduled || _isPageActive == nextVisible)) {
      return;
    }
    _desiredPageActive = nextVisible;
    _schedulePageActivityDispatch();
  }

  @override
  void initState() {
    super.initState();
    _appLifecycleListener = AppLifecycleListener(
      onStateChange: (_) => refreshPageActivity(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    refreshPageActivity();
  }

  @override
  void dispose() {
    _appLifecycleListener?.dispose();
    _appLifecycleListener = null;
    super.dispose();
  }

  bool _appAllowsPageActivity(AppLifecycleState? state) {
    return state == null || state == AppLifecycleState.resumed;
  }

  void _schedulePageActivityDispatch() {
    if (_activityDispatchScheduled) {
      return;
    }
    _activityDispatchScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _activityDispatchScheduled = false;
      _dispatchPageActivity();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _dispatchPageActivity() {
    if (!mounted || _isPageActive == _desiredPageActive) {
      return;
    }
    _isPageActive = _desiredPageActive;
    if (_isPageActive) {
      onPageBecameActive();
    } else {
      onPageBecameInactive();
    }
  }
}
