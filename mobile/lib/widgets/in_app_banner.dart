import 'dart:async';

import 'package:flutter/material.dart';

import '../screens/notifications_screen.dart';
import '../theme/app_colors.dart';

/// The app's one navigator, so a banner can appear over whatever screen is
/// open when a push arrives.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// A compact card that slides down from the top when a push arrives while
/// the app is open (Android shows nothing itself then), stays a moment and
/// slides back up. Tap opens the inbox; a swipe up dismisses it early.
class InAppBanner {
  InAppBanner._();

  static const Duration visibleFor = Duration(seconds: 4);
  static OverlayEntry? _current;

  static void show({String? title, required String body}) {
    final overlay = appNavigatorKey.currentState?.overlay;
    if (overlay == null) return;
    _current?.remove();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _BannerCard(
        title: title,
        body: body,
        onGone: () {
          if (_current == entry) _current = null;
          if (entry.mounted) entry.remove();
        },
      ),
    );
    _current = entry;
    overlay.insert(entry);
  }
}

class _BannerCard extends StatefulWidget {
  const _BannerCard({required this.title, required this.body, required this.onGone});

  final String? title;
  final String body;
  final VoidCallback onGone;

  @override
  State<_BannerCard> createState() => _BannerCardState();
}

class _BannerCardState extends State<_BannerCard> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    reverseDuration: const Duration(milliseconds: 260),
  );
  late final Animation<Offset> _slide = Tween<Offset>(begin: const Offset(0, -1.3), end: Offset.zero)
      .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn));
  Timer? _timer;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    _timer = Timer(InAppBanner.visibleFor, _hide);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _hide() async {
    if (_leaving || !mounted) return;
    _leaving = true;
    _timer?.cancel();
    await _controller.reverse();
    widget.onGone();
  }

  void _open() {
    _hide();
    appNavigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: SlideTransition(
          position: _slide,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: GestureDetector(
              key: const ValueKey('in-app-banner'),
              onTap: _open,
              onVerticalDragUpdate: (details) {
                if (details.delta.dy < -2) _hide();
              },
              child: Material(
                color: AppColors.surface,
                elevation: 10,
                shadowColor: Colors.black38,
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.asset('assets/icon/guyo_icon_foreground.png', width: 38, height: 38),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (title != null && title.isNotEmpty)
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: AppColors.primaryDark,
                                ),
                              ),
                            Text(
                              widget.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 14, color: AppColors.secondaryText),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
