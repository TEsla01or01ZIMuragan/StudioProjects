import 'package:flutter_test/flutter_test.dart';
import 'package:nanny_crows_guide/features/auth/domain/user_profile.dart';

void main() {
  test('parses app roles including existing account aliases', () {
    expect(UserRole.parse('teacher'), UserRole.teacher);
    expect(UserRole.parse('curator'), UserRole.teacher);
    expect(UserRole.parse('student'), UserRole.student);
    expect(UserRole.parse('child'), UserRole.student);
    expect(UserRole.parse('parent'), UserRole.parent);
    expect(UserRole.parse('admin'), isNull);
  });

  test('maps profile fields and defaults optional collections', () {
    final profile = UserProfile.fromMap('student-1', {
      'role': 'student',
      'fullName': 'Иван Иванов',
      'email': 'ivan@example.com',
      'classId': 'class-5a',
      'childrenIds': <String>[],
    });

    expect(profile.uid, 'student-1');
    expect(profile.role, UserRole.student);
    expect(profile.fullName, 'Иван Иванов');
    expect(profile.classId, 'class-5a');
    expect(profile.childrenIds, isEmpty);
    expect(profile.childClassIds, isEmpty);
  });

  test('rejects unknown Firestore roles', () {
    expect(
      () => UserProfile.fromMap('invalid', {'role': 'admin'}),
      throwsFormatException,
    );
  });
}
