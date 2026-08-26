import 'package:flutter_test/flutter_test.dart';
import 'package:paper_suitecase/providers/app_state.dart';

void main() {
  test('recentInitialLimit shows at least the minimum, else the week count', () {
    // Quiet week → fall back to the minimum window.
    expect(recentInitialLimit(0), 9);
    expect(recentInitialLimit(5), 9);
    // Exactly the minimum.
    expect(recentInitialLimit(9), 9);
    // Busy week → show everything from the week.
    expect(recentInitialLimit(20), 20);
    // Custom minimum honored.
    expect(recentInitialLimit(3, minCount: 5), 5);
    expect(recentInitialLimit(30, minCount: 5), 30);
  });
}
