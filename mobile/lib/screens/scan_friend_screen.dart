import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import 'add_friend_sheet.dart';

/// Scans a friend's QR code (Профиль -> QR: it holds their 9-digit ID),
/// shows who it is, and adds them only after "Добавить в друзья".
/// Pops `true` once a friend was added, or 'manual' to type the ID instead.
class ScanFriendScreen extends StatefulWidget {
  const ScanFriendScreen({super.key});

  @override
  State<ScanFriendScreen> createState() => _ScanFriendScreenState();
}

class _ScanFriendScreenState extends State<ScanFriendScreen> with SingleTickerProviderStateMixin {
  final MobileScannerController _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  late final AnimationController _line = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))
    ..repeat(reverse: true);
  bool _busy = false;
  bool _torch = false;
  String? _message;

  @override
  void dispose() {
    _line.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;
    final raw = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
    final id = raw == null ? null : int.tryParse(raw.trim());
    if (id == null) {
      setState(() => _message = tr('Это не QR-код GuYo'));
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    HapticFeedback.mediumImpact();
    try {
      final user = await ApiClient.instance.findUserByPublicId(id);
      if (!mounted) return;
      if (user.isMe) {
        setState(() {
          _busy = false;
          _message = tr('Это ваш собственный QR-код');
        });
        return;
      }
      final added = await confirmAndAddFriend(context, user);
      if (!mounted) return;
      if (added) {
        Navigator.of(context).pop(true);
      } else {
        // Give the camera a moment before it may read the same code again.
        await Future.delayed(const Duration(milliseconds: 700));
        if (mounted) setState(() => _busy = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = errorText(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const frame = 250.0;
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(tr('QR-код друга'), style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _NoCamera(onManual: () => Navigator.of(context).pop(false)),
          ),
          // Darken everything but the aiming frame.
          ColorFiltered(
            colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: 0.55), BlendMode.srcOut),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(decoration: const BoxDecoration(color: Colors.transparent, backgroundBlendMode: BlendMode.dstOut)),
                Center(
                  child: Container(
                    width: frame,
                    height: frame,
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30)),
                  ),
                ),
              ],
            ),
          ),
          Center(
            child: SizedBox(
              width: frame,
              height: frame,
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _line,
                    builder: (_, _) => Positioned(
                      left: 18,
                      right: 18,
                      top: 18 + (frame - 40) * _line.value,
                      child: Container(
                        height: 3,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          color: const Color(0xFF7C8CFF),
                          boxShadow: const [BoxShadow(color: Color(0xAA7C8CFF), blurRadius: 12, spreadRadius: 1)],
                        ),
                      ),
                    ),
                  ),
                  if (_busy) const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)),
                ],
              ),
            ),
          ),
          Positioned(
            left: 32,
            right: 32,
            top: MediaQuery.paddingOf(context).top + 72,
            child: Text(
              _message ?? tr('Наведите камеру на QR-код из профиля друга'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _message == null ? Colors.white : const Color(0xFFFFB4B4),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: MediaQuery.paddingOf(context).bottom + 32,
            child: Row(
              children: [
                _RoundButton(
                  icon: _torch ? Icons.flashlight_on_rounded : Icons.flashlight_off_rounded,
                  active: _torch,
                  onTap: () {
                    _controller.toggleTorch();
                    setState(() => _torch = !_torch);
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.16),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      icon: const Icon(Icons.keyboard_rounded),
                      label: Text(tr('Ввести ID вручную'), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _RoundButton({required this.icon, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? Colors.white : Colors.white.withValues(alpha: 0.16),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: 52, height: 52, child: Icon(icon, color: active ? Colors.black : Colors.white)),
      ),
    );
  }
}

/// Shown when the camera can't be opened (most often: no permission).
class _NoCamera extends StatelessWidget {
  final VoidCallback onManual;
  const _NoCamera({required this.onManual});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0E1230),
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: const Icon(Icons.no_photography_outlined, color: Colors.white, size: 40),
          ),
          const SizedBox(height: 18),
          Text(
            tr('Нет доступа к камере'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            tr('Разрешите доступ к камере в настройках телефона или введите ID друга вручную.'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14.5),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: onManual,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF101B63),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.keyboard_rounded),
            label: Text(tr('Ввести ID вручную'), style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
