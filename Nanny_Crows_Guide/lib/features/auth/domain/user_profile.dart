enum UserRole {
  teacher,
  student,
  parent;

  static UserRole? parse(Object? value) => switch (value) {
    'teacher' || 'curator' => UserRole.teacher,
    'student' || 'child' => UserRole.student,
    'parent' => UserRole.parent,
    _ => null,
  };

  String get label => switch (this) {
    UserRole.teacher => 'Учитель',
    UserRole.student => 'Ученик',
    UserRole.parent => 'Родитель',
  };
}

class UserProfile {
  const UserProfile({
    required this.uid,
    required this.role,
    required this.fullName,
    this.email = '',
    this.classId,
    this.childrenIds = const [],
    this.childClassIds = const [],
    this.inviteCode,
  });

  final String uid;
  final UserRole role;
  final String fullName;
  final String email;
  final String? classId;
  final List<String> childrenIds;
  final List<String> childClassIds;
  final String? inviteCode;

  factory UserProfile.fromMap(String uid, Map<String, dynamic> data) {
    final role = UserRole.parse(data['role']);
    if (role == null) {
      throw const FormatException('Неизвестная роль пользователя.');
    }
    return UserProfile(
      uid: uid,
      role: role,
      fullName: data['fullName'] as String? ?? '',
      email: data['email'] as String? ?? '',
      classId: data['classId'] as String?,
      childrenIds: List<String>.from(data['childrenIds'] as List? ?? const []),
      childClassIds: List<String>.from(
        data['childClassIds'] as List? ?? const [],
      ),
      inviteCode: data['inviteCode'] as String?,
    );
  }
}
