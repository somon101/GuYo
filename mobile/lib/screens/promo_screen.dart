import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../models/premium.dart';
import '../theme/app_colors.dart';
import '../widgets/guyo_ui.dart';

/// "Промокод": one field for a promo code or a link to a GuYo video.
///
/// Which one it is, whether it's valid and how many days it gives are all
/// decided by the backend (app/promo/service.py) -- this screen sends the
/// text and shows the answer.
class PromoScreen extends StatefulWidget {
  const PromoScreen({super.key});

  @override
  State<PromoScreen> createState() => _PromoScreenState();
}

class _PromoScreenState extends State<PromoScreen> {
  final _controller = TextEditingController();
  bool _isSubmitting = false;
  String? _error;
  PromoResult? _result;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    _controller.text = text;
    _controller.selection = TextSelection.collapsed(offset: text.length);
    setState(() => _error = null);
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Введите промокод или вставьте ссылку');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      final result = await ApiClient.instance.redeemPromo(text);
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _result = result;
        _controller.clear();
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = 'Не удалось проверить промокод. Проверьте интернет.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('Промокод'), backgroundColor: AppColors.canvas),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          if (_result != null) ...[
            _SuccessCard(result: _result!),
            const SizedBox(height: 14),
          ],
          GuyoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Промокод или ссылка',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Введите промокод или вставьте ссылку на видео GuYo и получите дни Premium.',
                  style: TextStyle(fontSize: 13, color: AppColors.secondaryText),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _controller,
                  enabled: !_isSubmitting,
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  enableSuggestions: false,
                  onSubmitted: (_) => _submit(),
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  decoration: InputDecoration(
                    hintText: 'GUYO2026 или https://youtu.be/…',
                    filled: true,
                    fillColor: AppColors.violetSurface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppShapes.rowRadius),
                      borderSide: BorderSide.none,
                    ),
                    errorText: _error,
                    errorMaxLines: 3,
                    suffixIcon: IconButton(
                      tooltip: 'Вставить',
                      icon: const Icon(Icons.content_paste_rounded, color: AppColors.primary),
                      onPressed: _isSubmitting ? null : _paste,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isSubmitting ? null : _submit,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppShapes.rowRadius)),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                          )
                        : const Text('Активировать', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const GuyoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Где взять',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
                ),
                SizedBox(height: 8),
                _Hint(
                  icon: Icons.smart_display_rounded,
                  text: 'Смотрите видео GuYo в соцсетях и вставляйте сюда их ссылки. '
                      'Первая ссылка даёт больше всего дней, каждая следующая — ещё немного.',
                ),
                _Hint(
                  icon: Icons.confirmation_number_rounded,
                  text: 'Промокоды мы публикуем в соцсетях и дарим на акциях. Каждый можно активировать один раз.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SuccessCard extends StatelessWidget {
  final PromoResult result;
  const _SuccessCard({required this.result});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF4D6), Color(0xFFFFE3A3)],
        ),
        borderRadius: BorderRadius.circular(AppShapes.bannerRadius),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: const Icon(Icons.celebration_rounded, size: 30, color: AppColors.rewardText),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '+${result.days} дн. Premium',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
                ),
                const SizedBox(height: 3),
                Text(
                  'Premium активен до ${formatPremiumDate(result.premiumUntil)}',
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.rewardText),
                ),
                if (result.isFirstLink) ...[
                  const SizedBox(height: 3),
                  const Text(
                    'Бонус за первую ссылку!',
                    style: TextStyle(fontSize: 12.5, color: AppColors.rewardText),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Hint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 13, height: 1.35, color: AppColors.secondaryText)),
          ),
        ],
      ),
    );
  }
}
