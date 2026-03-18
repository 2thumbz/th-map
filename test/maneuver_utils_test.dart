import 'package:flutter_test/flutter_test.dart';
import 'package:my_nav_app/navigation/maneuver_models.dart';
import 'package:my_nav_app/navigation/maneuver_utils.dart';

void main() {
  test('classifyTurn returns null for small delta', () {
    expect(classifyTurn(10), isNull);
  });

  test('classifyTurn returns left/right/uTurn properly', () {
    expect(classifyTurn(-45), ManeuverType.left);
    expect(classifyTurn(45), ManeuverType.right);
    expect(classifyTurn(170), ManeuverType.uTurn);
  });

  test('maneuverLabel has user-facing Korean labels', () {
    expect(maneuverLabel(ManeuverType.left), '좌회전');
    expect(maneuverLabel(ManeuverType.right), '우회전');
    expect(maneuverLabel(ManeuverType.uTurn), '유턴');
  });
}
