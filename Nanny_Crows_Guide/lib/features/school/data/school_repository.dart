import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:nanny_crows_guide/features/auth/domain/user_profile.dart';
import 'package:nanny_crows_guide/features/school/domain/school_models.dart';
import 'package:uuid/uuid.dart';

class SchoolRepository {
  SchoolRepository(this._firestore);

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  static const _uuid = Uuid();

  Stream<List<SchoolAssignment>> watchAssignmentsForClass(String classId) {
    return _firestore
        .collection('assignments')
        .where('classId', isEqualTo: classId)
        .orderBy('dueDate')
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(SchoolAssignment.fromSnapshot).toList(),
        );
  }

  Stream<List<SchoolAssignment>> watchAssignmentsForClasses(
    List<String> classIds,
  ) {
    if (classIds.isEmpty) return Stream.value(const []);
    if (classIds.length > 30) {
      return Stream.error(
        ArgumentError('Для одного запроса можно выбрать не более 30 классов.'),
      );
    }
    return _firestore
        .collection('assignments')
        .where('classId', whereIn: classIds)
        .orderBy('dueDate')
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(SchoolAssignment.fromSnapshot).toList(),
        );
  }

  Stream<List<SchoolAssignment>> watchTeacherAssignments(String teacherId) {
    return _firestore
        .collection('assignments')
        .where('teacherId', isEqualTo: teacherId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(SchoolAssignment.fromSnapshot).toList(),
        );
  }

  Stream<List<StudentSubmission>> watchStudentSubmissions(String studentId) {
    return _firestore
        .collection('submissions')
        .where('studentId', isEqualTo: studentId)
        .orderBy('submittedAt', descending: true)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(StudentSubmission.fromSnapshot).toList(),
        );
  }

  Stream<List<StudentSubmission>> watchTeacherReviews(String teacherId) {
    return _firestore
        .collection('submissions')
        .where('teacherId', isEqualTo: teacherId)
        .where('status', isEqualTo: 'submitted')
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(StudentSubmission.fromSnapshot).toList(),
        );
  }

  Stream<List<Map<String, dynamic>>> watchGradeSummaries(String studentId) {
    return _firestore
        .collection('gradeSummaries')
        .doc(studentId)
        .collection('subjects')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => {'id': doc.id, ...doc.data()})
              .toList(),
        );
  }

  Stream<List<Map<String, dynamic>>> watchTeacherClasses(String teacherId) {
    return _firestore
        .collection('classes')
        .where('teacherIds', arrayContains: teacherId)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => {'id': doc.id, ...doc.data()})
              .toList(),
        );
  }

  Stream<List<Map<String, dynamic>>> watchChildren(List<String> childIds) {
    if (childIds.isEmpty) return Stream.value(const []);
    if (childIds.length > 30) {
      return Stream.error(
        ArgumentError(
          'Можно одновременно загрузить не более 30 профилей детей.',
        ),
      );
    }
    return _firestore
        .collection('users')
        .where(FieldPath.documentId, whereIn: childIds)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => {'id': doc.id, ...doc.data()})
              .toList(),
        );
  }

  Future<void> createAssignment({
    required UserProfile teacher,
    required String classId,
    required String subjectId,
    required String subjectName,
    required String title,
    required String description,
    required DateTime dueDate,
    required List<({String name, Uint8List bytes})> files,
  }) async {
    _validateFiles(files);
    final reference = _firestore.collection('assignments').doc();
    await reference.set({
      'classId': classId.trim(),
      'subjectId': subjectId.trim(),
      'subjectName': subjectName.trim(),
      'teacherId': teacher.uid,
      'title': title.trim(),
      'description': description.trim(),
      'attachments': <String>[],
      'dueDate': Timestamp.fromDate(dueDate),
      'createdAt': FieldValue.serverTimestamp(),
    });
    final urls = await _uploadFiles(
      files,
      (index, name) => 'assignments/${reference.id}/${_uuid.v4()}_$name',
    );
    if (urls.isNotEmpty) {
      await reference.update({'attachments': urls});
    }
  }

  Future<void> submitAnswer({
    required SchoolAssignment assignment,
    required UserProfile student,
    required String answerText,
    required List<({String name, Uint8List bytes})> files,
  }) async {
    final id = '${assignment.id}_${student.uid}';
    final reference = _firestore.collection('submissions').doc(id);
    final existing = await reference.get();
    if (existing.data()?['status'] == 'graded') {
      throw StateError('Проверенную работу нельзя изменить.');
    }
    final urls = await _uploadFiles(
      files,
      (index, name) =>
          'submissions/${assignment.id}/${student.uid}/${_uuid.v4()}_$name',
    );
    await reference.set({
      'assignmentId': assignment.id,
      'studentId': student.uid,
      'studentName': student.fullName,
      'assignmentTitle': assignment.title,
      'subjectId': assignment.subjectId,
      'subjectName': assignment.subjectName,
      'classId': assignment.classId,
      'teacherId': assignment.teacherId,
      'status': 'submitted',
      'answerText': answerText.trim(),
      'answerFiles': urls,
      'submittedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> gradeSubmission({
    required StudentSubmission submission,
    required num grade,
    required String comment,
  }) async {
    if (grade < 1 || grade > 100) {
      throw ArgumentError.value(
        grade,
        'grade',
        'Оценка должна быть от 1 до 100.',
      );
    }
    await _firestore.collection('submissions').doc(submission.id).update({
      'grade': grade,
      'teacherComment': comment.trim(),
      'status': 'graded',
      'gradedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> linkChild(String inviteCode) async {
    await FirebaseFunctions.instance
        .httpsCallable('linkParentToStudent')
        .call<void>({'inviteCode': inviteCode.trim()});
  }

  Future<List<String>> _uploadFiles(
    List<({String name, Uint8List bytes})> files,
    String Function(int index, String name) pathFor,
  ) async {
    _validateFiles(files);
    final urls = <String>[];
    for (var index = 0; index < files.length; index++) {
      final file = files[index];
      final reference = _storage.ref(pathFor(index, file.name));
      final snapshot = await reference.putData(
        file.bytes,
        SettableMetadata(contentType: _contentType(file.name)),
      );
      urls.add(await snapshot.ref.getDownloadURL());
    }
    return urls;
  }

  void _validateFiles(List<({String name, Uint8List bytes})> files) {
    if (files.length > 10) {
      throw ArgumentError(
        'К одной работе можно прикрепить не более 10 файлов.',
      );
    }
    if (files.any((file) => file.bytes.lengthInBytes > 10 * 1024 * 1024)) {
      throw ArgumentError('Размер каждого файла не должен превышать 10 МБ.');
    }
  }

  String _contentType(String name) {
    final extension = name.split('.').last.toLowerCase();
    return switch (extension) {
      'pdf' => 'application/pdf',
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      _ => 'application/octet-stream',
    };
  }
}
