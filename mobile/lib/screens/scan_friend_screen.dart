import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';

/// Scans a friend's QR code (Профиль -> QR: it holds their 9-digit ID)
/// and adds them as a friend. Pops `true` once a friend was added.
class ScanFriendScreen extends StatefulWidget {
  const ScanFriendScreen({super.key});

  @override
  State<ScanFriendScreen> createState() => _ScanFriendScreenState();
}

class _ScanFriendScreenState extends State<ScanFriendScreen> {
  final MobileScannerController _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
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
    try {
      await ApiClient.instance.addFriend(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Друг добавлен'))));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(tr('QR-код друга')),
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  tr('Нет доступа к камере. Разрешите его в настройках телефона.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
              ),
            ),
          ),
          // The aiming frame.
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white, width: 3),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(16),
              ),
              child: _busy
                  ? const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                  : Text(
                      _message ?? tr('Наведите камеру на QR-код из профиля друга'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _message == null ? Colors.white : const Color(0xFFFFB4B4),
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
