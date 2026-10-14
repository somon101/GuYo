import 'dart:async';

import 'package:flutter/material.dart';

import '../screens/notifications_screen.dart';
import '../theme/app_colors.dart';
import 'guyo_ui.dart';

/// The app's one navigator, so a banner can appear over whatever screen is
/// open when a push arrives.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// A compact card that springs down from the top, stays a moment and slides
/// back up. It is the app's ONE notice of this kind, so everything that
/// needs to tell the user something in passing uses it instead of a second,
/// near-identical banner:
///
/// - a push arriving while the app is open (Android shows nothing itself
///   then) -- the default look: the app's own mark, tap opens the inbox;
/// - a lesson exercise being skipped ([skipVisibleFor], `opensInbox: false`)
///   -- its own icon, a shorter stay, nothing to tap, since the lesson has
///   already moved on and the notice only confirms it.
///
/// A swipe up dismisses it early either way.
class InAppBanner {
  InAppBanner._();

  static const Duration visibleFor = Duration(seconds: 4);

  /// How long a lesson's "this exercise was skipped" notice stays: it only
  /// confirms that the run moved on, so it needs less time than a push.
  static const Duration skipVisibleFor = Duration(milliseconds: 2600);

  /// How long a quick acknowledgement of something the user just did stays --
  /// «Текст скопирован», or a setting they just changed. There is nothing to
  /// act on, so it is gone sooner than a push or a skip notice.
  static const Duration confirmationVisibleFor = Duration(milliseconds: 2000);

  static OverlayEntry? _current;

  static void show({
    String? title,
    String? body,
    IconData? icon,
    VoidCallback? onTap,
    Duration visibleFor = InAppBanner.visibleFor,
    bool opensInbox = true,
  }) {
    final overlay = appNavigatorKey.currentState?.overlay;
    if (overlay == null) return;
    _current?.remove();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _BannerCard(
        title: title,
        body: body,
        icon: icon,
        onTap: onTap,
        visibleFor: visibleFor,
        opensInbox: opensInbox,
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
  const _BannerCard({
    required this.title,
    required this.body,
    required this.icon,
    required this.onTap,
    required this.visibleFor,
    required this.opensInbox,
    required this.onGone,
  });

  final String? title;
  final String? body;
  final IconData? icon;
  final VoidCallback? onTap;
  final Duration visibleFor;
  final bool opensInbox;
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
  // A soft fade under the spring, so the card arrives rather than snapping
  // into place at the end of the slide.
  late final Animation<double> _fade =
      CurvedAnimation(parent: _controller, curve: Curves.easeOut, reverseCurve: Curves.easeIn);
  Timer? _timer;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    _timer = Timer(widget.visibleFor, _hide);
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
    final body = widget.body;
    final icon = widget.icon;
    final hasTitle = title != null && title.isNotEmpty;
    final hasBody = body != null && body.isNotEmpty;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: SlideTransition(
          position: _slide,
          child: FadeTransition(
            opacity: _fade,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: GestureDetector(
                key: const ValueKey('in-app-banner'),
                // A push (and an error notice) opens the inbox; a lesson's
                // skip notice has nothing to open, so it is left untappable
                // -- a swipe up still dismisses it early.
                onTap: widget.onTap ?? (widget.opensInbox ? _open : null),
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
                        if (icon == null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.asset('assets/icon/guyo_icon_foreground.png', width: 38, height: 38),
                          )
                        else
                          RoundIconChip(icon: icon, size: 38),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (hasTitle)
                                Text(
                                  title,
                                  // Three lines fit a whole sentence here, so a
                                  // skipped exercise is never cut off mid-word.
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                    color: AppColors.primaryDark,
                                  ),
                                ),
                              if (hasBody)
                                Padding(
                                  padding: EdgeInsets.only(top: hasTitle ? 2 : 0),
                                  child: Text(
                                    body,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 14, color: AppColors.secondaryText),
                                  ),
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
      ),
    );
  }
}
