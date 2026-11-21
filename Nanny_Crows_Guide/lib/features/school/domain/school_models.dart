import 'package:cloud_firestore/cloud_firestore.dart';

class SchoolAssignment {
  const SchoolAssignment({
    required this.id,
    required this.classId,
    required this.subjectId,
    required this.subjectName,
    required this.teacherId,
    required this.title,
    required this.description,
    required this.attachments,
    required this.dueDate,
  });

  final String id;
  final String classId;
  final String subjectId;
  final String subjectName;
  final String teacherId;
  final String title;
  final String description;
  final List<String> attachments;
  final DateTime? dueDate;

  factory SchoolAssignment.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data()!;
    return SchoolAssignment(
      id: snapshot.id,
      classId: data['classId'] as String? ?? '',
      subjectId: data['subjectId'] as String? ?? '',
      subjectName: data['subjectName'] as String? ?? '',
      teacherId: data['teacherId'] as String? ?? '',
      title: data['title'] as String? ?? '',
      description: data['description'] as String? ?? '',
      attachments: List<String>.from(data['attachments'] as List? ?? const []),
      dueDate: (data['dueDate'] as Timestamp?)?.toDate(),
    );
  }
}

class StudentSubmission {
  const StudentSubmission({
    required this.id,
    required this.assignmentId,
    required this.studentId,
    required this.studentName,
    required this.assignmentTitle,
    required this.subjectId,
    required this.subjectName,
    required this.classId,
    required this.teacherId,
    required this.status,
    required this.answerText,
    required this.answerFiles,
    this.grade,
    this.teacherComment = '',
  });

  final String id;
  final String assignmentId;
  final String studentId;
  final String studentName;
  final String assignmentTitle;
  final String subjectId;
  final String subjectName;
  final String classId;
  final String teacherId;
  final String status;
  final String answerText;
  final List<String> answerFiles;
  final num? grade;
  final String teacherComment;

  factory StudentSubmission.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data()!;
    return StudentSubmission(
      id: snapshot.id,
      assignmentId: data['assignmentId'] as String? ?? '',
      studentId: data['studentId'] as String? ?? '',
      studentName: data['studentName'] as String? ?? '',
      assignmentTitle: data['assignmentTitle'] as String? ?? '',
      subjectId: data['subjectId'] as String? ?? '',
      subjectName: data['subjectName'] as String? ?? '',
      classId: data['classId'] as String? ?? '',
      teacherId: data['teacherId'] as String? ?? '',
      status: data['status'] as String? ?? 'pending',
      answerText: data['answerText'] as String? ?? '',
      answerFiles: List<String>.from(data['answerFiles'] as List? ?? const []),
      grade: data['grade'] as num?,
      teacherComment: data['teacherComment'] as String? ?? '',
    );
  }
}
