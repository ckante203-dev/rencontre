import 'package:flutter_test/flutter_test.dart';
import 'package:rencontre/features/chat/controller/position_direct.dart';

void main() {
  test('position simple et position en direct', () {
    final simple = PositionDirect.lire('5.345678,-4.012345');
    expect(simple?.$1, closeTo(5.345678, 1e-9));
    expect(simple?.$3, isNull);

    final direct = PositionDirect.lire('5.3,-4.0|live:1700000000000');
    expect(direct?.$2, closeTo(-4.0, 1e-9));
    expect(direct?.$3, DateTime.fromMillisecondsSinceEpoch(1700000000000));

    expect(PositionDirect.lire('pas une position'), isNull);
    expect(PositionDirect.lire(null), isNull);
  });
}
