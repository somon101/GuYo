// The per-answer stopwatch pauses while the app is in the background.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guyo_app/services/answer_signals.dart';

void main() {
  testWidgets('time in the background is not counted', (tester) async {
    AnswerSignals.init();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    AnswerSignals.itemShown();
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 1200)));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
    final ms = AnswerSignals.take()['duration_ms'] as int;
    expect(ms, inInclusiveRange(400, 1000), reason: 'only the ~500 ms in front, not the 1.2 s away');
  });

  test('no stopwatch, no duration', () {
    AnswerSignals.take();
    expect(AnswerSignals.take().containsKey('duration_ms'), isFalse);
  });
}
