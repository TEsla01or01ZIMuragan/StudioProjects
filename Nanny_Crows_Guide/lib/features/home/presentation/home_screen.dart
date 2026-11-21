import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nanny_crows_guide/core/providers.dart';
import 'package:nanny_crows_guide/features/auth/domain/user_profile.dart';
import 'package:nanny_crows_guide/features/school/data/school_repository.dart';
import 'package:nanny_crows_guide/features/school/domain/school_models.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _selectedIndex = 0;
  String? _tokenUserId;
  StreamSubscription<String>? _tokenRefreshSubscription;

  @override
  void dispose() {
    unawaited(_tokenRefreshSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider);
    return profile.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, stack) => Scaffold(
        appBar: AppBar(title: const Text('Профиль')),
        body: _ErrorView(
          message: error.toString(),
          action: TextButton(
            onPressed: () async {
              await ref.read(authRepositoryProvider).signOut();
              if (context.mounted) context.go('/login');
            },
            child: const Text('Выйти'),
          ),
        ),
      ),
      data: (user) {
        _saveNotificationToken(user.uid);
        final sections = _sectionsFor(user.role);
        final index = _selectedIndex.clamp(0, sections.length - 1);
        return Scaffold(
          appBar: AppBar(
            title: Text(sections[index].$1),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: Text(
                    user.fullName,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: IndexedStack(
              index: index,
              children: [for (final section in sections) section.$2(user, ref)],
            ),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (value) =>
                setState(() => _selectedIndex = value),
            destinations: [
              for (final section in sections)
                NavigationDestination(
                  icon: Icon(section.$3),
                  label: section.$1,
                ),
            ],
          ),
        );
      },
    );
  }

  void _saveNotificationToken(String uid) {
    if (_tokenUserId == uid) return;
    _tokenUserId = uid;
    const webVapidKey = String.fromEnvironment('FCM_VAPID_KEY');
    if (kIsWeb && webVapidKey.isEmpty) {
      _showMessage(
        context,
        'Веб-push не настроен: задайте FCM_VAPID_KEY при сборке приложения.',
      );
      return;
    }
    if (!kIsWeb &&
        !const {
          TargetPlatform.android,
          TargetPlatform.iOS,
          TargetPlatform.macOS,
        }.contains(defaultTargetPlatform)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await FirebaseMessaging.instance.requestPermission();
        // Cloud Functions sends to the registration token, not the FID.
        // ignore: deprecated_member_use
        final token = await FirebaseMessaging.instance.getToken(
          vapidKey: kIsWeb ? webVapidKey : null,
          serviceWorkerScriptPath: kIsWeb ? 'firebase-messaging-sw.js' : null,
        );
        if (token != null) {
          await _persistNotificationToken(uid, token);
        }
        // ignore: deprecated_member_use
        final tokenRefreshStream = FirebaseMessaging.instance.onTokenRefresh;
        _tokenRefreshSubscription ??= tokenRefreshStream.listen(
          (refreshedToken) => _persistNotificationToken(uid, refreshedToken),
          onError: (Object error, StackTrace stackTrace) {
            if (error is FirebaseException) {
              if (mounted) {
                _showMessage(
                  context,
                  error.message ?? 'Не удалось обновить токен уведомлений.',
                );
              }
            } else if (error is PlatformException) {
              if (mounted) {
                _showMessage(
                  context,
                  error.message ?? 'Не удалось обновить токен уведомлений.',
                );
              }
            } else {
              Error.throwWithStackTrace(error, stackTrace);
            }
          },
        );
      } on FirebaseException catch (error) {
        if (mounted) {
          _showMessage(
            context,
            error.message ?? 'Не удалось включить уведомления.',
          );
        }
      } on PlatformException catch (error) {
        if (mounted) {
          _showMessage(
            context,
            error.message ?? 'Уведомления недоступны на этом устройстве.',
          );
        }
      }
    });
  }

  Future<void> _persistNotificationToken(String uid, String token) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'fcmToken': token,
      });
    } on FirebaseException catch (error) {
      if (mounted) {
        _showMessage(
          context,
          error.message ?? 'Не удалось сохранить токен уведомлений.',
        );
      }
    } on PlatformException catch (error) {
      if (mounted) {
        _showMessage(
          context,
          error.message ?? 'Не удалось сохранить токен уведомлений.',
        );
      }
    }
  }

  List<(String, Widget Function(UserProfile, WidgetRef), IconData)>
  _sectionsFor(UserRole role) {
    final repository = ref.read(schoolRepositoryProvider);
    return switch (role) {
      UserRole.teacher => [
        ('Классы', (user, ref) => _TeacherClasses(user: user), Icons.groups),
        (
          'Задания',
          (user, ref) => _TeacherAssignments(user: user),
          Icons.assignment,
        ),
        (
          'Проверка',
          (user, ref) => _TeacherReviews(user: user, repository: repository),
          Icons.fact_check,
        ),
        ('Профиль', (user, ref) => _ProfilePage(user: user), Icons.person),
      ],
      UserRole.student => [
        (
          'Задания',
          (user, ref) => _StudentAssignments(user: user),
          Icons.assignment,
        ),
        ('Оценки', (user, ref) => _StudentGrades(user: user), Icons.grade),
        ('Профиль', (user, ref) => _ProfilePage(user: user), Icons.person),
      ],
      UserRole.parent => [
        ('Дневник', (user, ref) => _ParentDiary(user: user), Icons.menu_book),
        (
          'Предметы',
          (user, ref) => _ParentSubjects(user: user),
          Icons.auto_stories,
        ),
        ('Профиль', (user, ref) => _ProfilePage(user: user), Icons.person),
      ],
    };
  }
}

class _TeacherClasses extends ConsumerWidget {
  const _TeacherClasses({required this.user});
  final UserProfile user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _StreamContent<List<Map<String, dynamic>>>(
      stream: ref.watch(schoolRepositoryProvider).watchTeacherClasses(user.uid),
      builder: (context, classes) {
        if (classes.isEmpty) {
          return const _EmptyView('Пока нет назначенных классов.');
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final schoolClass in classes)
              Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.groups)),
                  title: Text(schoolClass['name'] as String? ?? 'Класс'),
                  subtitle: Text('Код: ${schoolClass['id']}'),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _TeacherAssignments extends ConsumerWidget {
  const _TeacherAssignments({required this.user});
  final UserProfile user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(schoolRepositoryProvider);
    return Scaffold(
      body: _StreamContent<List<SchoolAssignment>>(
        stream: repository.watchTeacherAssignments(user.uid),
        builder: (context, assignments) => assignments.isEmpty
            ? const _EmptyView('Создайте первое задание для своего класса.')
            : _AssignmentList(assignments: assignments),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateAssignment(context, repository, user),
        icon: const Icon(Icons.add),
        label: const Text('Новое задание'),
      ),
    );
  }
}

class _StudentAssignments extends ConsumerWidget {
  const _StudentAssignments({required this.user});
  final UserProfile user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classId = user.classId;
    if (classId == null || classId.isEmpty) {
      return const _EmptyView(
        'Класс не указан в профиле. Обратитесь к учителю.',
      );
    }
    final repository = ref.watch(schoolRepositoryProvider);
    return _StreamContent<List<SchoolAssignment>>(
      stream: repository.watchAssignmentsForClass(classId),
      builder: (context, assignments) =>
          _StreamContent<List<StudentSubmission>>(
            stream: repository.watchStudentSubmissions(user.uid),
            builder: (context, submissions) {
              final statuses = {
                for (final submission in submissions)
                  submission.assignmentId: submission.status,
              };
              return assignments.isEmpty
                  ? const _EmptyView('Активных заданий пока нет.')
                  : _AssignmentList(
                      assignments: assignments,
                      statuses: statuses,
                      onSubmit: (assignment) => _showSubmissionDialog(
                        context,
                        repository,
                        assignment,
                        user,
                      ),
                    );
            },
          ),
    );
  }
}

class _AssignmentList extends StatelessWidget {
  const _AssignmentList({
    required this.assignments,
    this.onSubmit,
    this.statuses = const {},
  });

  final List<SchoolAssignment> assignments;
  final ValueChanged<SchoolAssignment>? onSubmit;
  final Map<String, String> statuses;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
      children: [
        for (final assignment in assignments)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          assignment.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Chip(
                        label: Text(
                          statuses[assignment.id] == 'graded'
                              ? 'Проверено'
                              : statuses[assignment.id] == 'submitted'
                              ? 'На проверке'
                              : assignment.subjectName,
                        ),
                      ),
                    ],
                  ),
                  if (assignment.description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(assignment.description),
                  ],
                  if (assignment.dueDate != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Срок: ${_formatDate(assignment.dueDate!)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  for (final file in assignment.attachments)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.attach_file),
                      title: Text(
                        Uri.tryParse(file)?.pathSegments.last ?? 'Материал',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => _openLink(context, file),
                    ),
                  if (onSubmit != null) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.tonalIcon(
                        onPressed: statuses[assignment.id] == 'graded'
                            ? null
                            : () => onSubmit!(assignment),
                        icon: const Icon(Icons.upload_file),
                        label: Text(
                          statuses[assignment.id] == 'submitted'
                              ? 'Изменить ответ'
                              : statuses[assignment.id] == 'graded'
                              ? 'Проверено'
                              : 'Сдать работу',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _TeacherReviews extends ConsumerWidget {
  const _TeacherReviews({required this.user, required this.repository});
  final UserProfile user;
  final SchoolRepository repository;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _StreamContent<List<StudentSubmission>>(
      stream: repository.watchTeacherReviews(user.uid),
      builder: (context, submissions) => submissions.isEmpty
          ? const _EmptyView('Нет работ, ожидающих проверки.')
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final submission in submissions)
                  Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.assignment_turned_in),
                      ),
                      title: Text(
                        '${submission.studentName} · ${submission.assignmentTitle}',
                      ),
                      subtitle: Text(
                        [
                          if (submission.subjectName.isNotEmpty)
                            submission.subjectName,
                          if (submission.answerText.isNotEmpty)
                            submission.answerText
                          else
                            'Ответ сдан без текста',
                        ].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () =>
                          _showGradeDialog(context, repository, submission),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _StudentGrades extends ConsumerWidget {
  const _StudentGrades({required this.user});
  final UserProfile user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _StreamContent<List<StudentSubmission>>(
      stream: ref
          .watch(schoolRepositoryProvider)
          .watchStudentSubmissions(user.uid),
      builder: (context, submissions) {
        final graded = submissions.where(
          (submission) => submission.status == 'graded',
        );
        if (graded.isEmpty) return const _EmptyView('Оценок пока нет.');
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final submission in graded)
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(submission.grade?.toString() ?? '—'),
                  ),
                  title: Text(
                    submission.assignmentTitle.isEmpty
                        ? 'Задание'
                        : submission.assignmentTitle,
                  ),
                  subtitle: Text(
                    submission.teacherComment.isEmpty
                        ? 'Проверено'
                        : submission.teacherComment,
                  ),
                  trailing: Text('Предмет: ${submission.subjectId}'),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ParentDiary extends ConsumerStatefulWidget {
  const _ParentDiary({required this.user});
  final UserProfile user;

  @override
  ConsumerState<_ParentDiary> createState() => _ParentDiaryState();
}

class _ParentDiaryState extends ConsumerState<_ParentDiary> {
  String? _selectedChild;

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(schoolRepositoryProvider);
    return _StreamContent<List<Map<String, dynamic>>>(
      stream: repository.watchChildren(widget.user.childrenIds),
      builder: (context, children) {
        if (children.isEmpty) {
          return const _EmptyView(
            'Привяжите профиль ребёнка с помощью пригласительного кода.',
          );
        }
        final selected = children.any((child) => child['id'] == _selectedChild)
            ? _selectedChild!
            : children.first['id'] as String;
        final child = children.firstWhere((item) => item['id'] == selected);
        final classId = child['classId'] as String?;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: DropdownButtonFormField<String>(
                initialValue: selected,
                decoration: const InputDecoration(labelText: 'Ребёнок'),
                items: children
                    .map(
                      (item) => DropdownMenuItem(
                        value: item['id'] as String,
                        child: Text(item['fullName'] as String? ?? 'Ученик'),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _selectedChild = value),
              ),
            ),
            Expanded(
              child: classId == null
                  ? const _EmptyView('У ученика не указан класс.')
                  : !widget.user.childClassIds.contains(classId)
                  ? const _EmptyView(
                      'Нет доступа к классу ребёнка. Обратитесь к администратору.',
                    )
                  : _StreamContent<List<SchoolAssignment>>(
                      stream: repository.watchAssignmentsForClasses(
                        widget.user.childClassIds,
                      ),
                      builder: (context, assignments) {
                        final student = UserProfile.fromMap(selected, child);
                        return _ParentDiaryContent(
                          assignments: assignments
                              .where(
                                (assignment) => assignment.classId == classId,
                              )
                              .toList(),
                          student: student,
                          repository: repository,
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _ParentDiaryContent extends ConsumerWidget {
  const _ParentDiaryContent({
    required this.assignments,
    required this.student,
    required this.repository,
  });
  final List<SchoolAssignment> assignments;
  final UserProfile student;
  final SchoolRepository repository;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _StreamContent<List<StudentSubmission>>(
      stream: repository.watchStudentSubmissions(student.uid),
      builder: (context, submissions) {
        final submittedIds = submissions
            .where(
              (item) => item.status == 'submitted' || item.status == 'graded',
            )
            .map((item) => item.assignmentId)
            .toSet();
        final open = assignments
            .where((assignment) => !submittedIds.contains(assignment.id))
            .toList();
        final graded = submissions.where((item) => item.status == 'graded');
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Невыполненные задания (${open.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (open.isEmpty) const _EmptyView('Невыполненных заданий нет.'),
            for (final assignment in open)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.pending_actions),
                  title: Text(assignment.title),
                  subtitle: Text(assignment.subjectName),
                ),
              ),
            const SizedBox(height: 12),
            Text(
              'Последние оценки',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (graded.isEmpty) const Text('Оценок пока нет.'),
            for (final item in graded)
              Card(
                child: ListTile(
                  leading: CircleAvatar(child: Text('${item.grade ?? '—'}')),
                  title: Text(
                    item.subjectName.isEmpty
                        ? item.subjectId
                        : item.subjectName,
                  ),
                  subtitle: Text(item.teacherComment),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ParentSubjects extends ConsumerStatefulWidget {
  const _ParentSubjects({required this.user});
  final UserProfile user;

  @override
  ConsumerState<_ParentSubjects> createState() => _ParentSubjectsState();
}

class _ParentSubjectsState extends ConsumerState<_ParentSubjects> {
  String? _selectedChild;

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(schoolRepositoryProvider);
    return _StreamContent<List<Map<String, dynamic>>>(
      stream: repository.watchChildren(widget.user.childrenIds),
      builder: (context, children) {
        if (children.isEmpty) {
          return const _EmptyView('Сначала привяжите профиль ребёнка.');
        }
        final selected = children.any((child) => child['id'] == _selectedChild)
            ? _selectedChild!
            : children.first['id'] as String;
        final child = children.firstWhere((item) => item['id'] == selected);
        final classId = child['classId'] as String?;
        if (classId == null || classId.isEmpty) {
          return const _EmptyView('У ребёнка не указан класс.');
        }
        if (!widget.user.childClassIds.contains(classId)) {
          return const _EmptyView(
            'Нет доступа к классу ребёнка. Обратитесь к администратору.',
          );
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: DropdownButtonFormField<String>(
                initialValue: selected,
                decoration: const InputDecoration(labelText: 'Ребёнок'),
                items: children
                    .map(
                      (item) => DropdownMenuItem(
                        value: item['id'] as String,
                        child: Text(item['fullName'] as String? ?? 'Ученик'),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _selectedChild = value),
              ),
            ),
            Expanded(
              child: _StreamContent<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('subjects')
                    .where('classId', whereIn: widget.user.childClassIds)
                    .snapshots(),
                builder: (context, snapshot) =>
                    _StreamContent<List<Map<String, dynamic>>>(
                      stream: repository.watchGradeSummaries(selected),
                      builder: (context, summaries) {
                        final gradesBySubject = {
                          for (final summary in summaries)
                            summary['id'] as String: summary['average'] as num?,
                        };
                        return ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            for (final subject in snapshot.docs.where(
                              (subject) => subject.data()['classId'] == classId,
                            ))
                              Builder(
                                builder: (context) {
                                  final data = subject.data();
                                  final average = gradesBySubject[subject.id];
                                  return Card(
                                    child: ListTile(
                                      leading: const Icon(Icons.menu_book),
                                      title: Text(
                                        data['name'] as String? ?? 'Предмет',
                                      ),
                                      subtitle: Text(
                                        average == null
                                            ? 'Оценок пока нет'
                                            : 'Средний балл: ${average.toStringAsFixed(1)}',
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ],
                        );
                      },
                    ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ProfilePage extends ConsumerWidget {
  const _ProfilePage({required this.user});
  final UserProfile user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(schoolRepositoryProvider);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text(user.fullName),
            subtitle: Text('${user.role.label} · ${user.email}'),
          ),
        ),
        if (user.role == UserRole.student)
          Card(
            child: ListTile(
              title: const Text('Код для привязки родителя'),
              subtitle: Text(user.inviteCode ?? 'Код создаётся…'),
              trailing: IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Обновить профиль',
                onPressed: () => ref.invalidate(userProfileProvider),
              ),
            ),
          ),
        if (user.role == UserRole.parent)
          Card(
            child: ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Привязать ребёнка'),
              trailing: FilledButton.tonal(
                onPressed: () => _showLinkChildDialog(context, repository),
                child: const Text('Ввести код'),
              ),
            ),
          ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () async {
            await ref.read(authRepositoryProvider).signOut();
            if (context.mounted) context.go('/login');
          },
          icon: const Icon(Icons.logout),
          label: const Text('Выйти из аккаунта'),
        ),
      ],
    );
  }
}

class _StreamContent<T> extends StatelessWidget {
  const _StreamContent({required this.stream, required this.builder});
  final Stream<T> stream;
  final Widget Function(BuildContext, T) builder;

  @override
  Widget build(BuildContext context) => StreamBuilder<T>(
    stream: stream,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _ErrorView(
          message: 'Не удалось загрузить данные: ${snapshot.error}',
        );
      }
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      if (!snapshot.hasData) return const _EmptyView('Нет данных.');
      return builder(context, snapshot.data as T);
    },
  );
}

class _EmptyView extends StatelessWidget {
  const _EmptyView(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Text(message, textAlign: TextAlign.center),
    ),
  );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, this.action});
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          ?action,
        ],
      ),
    ),
  );
}

Future<List<({String name, Uint8List bytes})>> _pickFiles(
  BuildContext context,
) async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
  );
  final files = <({String name, Uint8List bytes})>[];
  for (final file in result) {
    final bytes = await file.readAsBytes();
    files.add((name: file.name, bytes: bytes));
  }
  return files;
}

Future<List<({String name, Uint8List bytes})>> _chooseFiles(
  BuildContext context,
) async {
  try {
    return await _pickFiles(context);
  } on PlatformException catch (error) {
    if (context.mounted) {
      _showMessage(
        context,
        error.message ?? 'Не удалось прочитать выбранные файлы.',
      );
    }
    return [];
  } on StateError catch (error) {
    if (context.mounted) _showMessage(context, error.message);
    return [];
  }
}

Future<void> _showCreateAssignment(
  BuildContext context,
  SchoolRepository repository,
  UserProfile teacher,
) async {
  final classId = TextEditingController();
  final subjectId = TextEditingController();
  final subjectName = TextEditingController();
  final title = TextEditingController();
  final description = TextEditingController();
  DateTime dueDate = DateTime.now().add(const Duration(days: 7));
  var files = <({String name, Uint8List bytes})>[];
  var loading = false;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Новое задание'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DialogField(controller: classId, label: 'Код класса'),
                _DialogField(controller: subjectId, label: 'Код предмета'),
                _DialogField(
                  controller: subjectName,
                  label: 'Название предмета',
                ),
                _DialogField(controller: title, label: 'Заголовок'),
                _DialogField(
                  controller: description,
                  label: 'Описание',
                  maxLines: 3,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Срок: ${_formatDate(dueDate)}'),
                  trailing: const Icon(Icons.calendar_month),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      initialDate: dueDate,
                    );
                    if (date != null) setState(() => dueDate = date);
                  },
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await _chooseFiles(context);
                    if (!context.mounted) return;
                    setState(() => files = picked);
                  },
                  icon: const Icon(Icons.attach_file),
                  label: Text(
                    files.isEmpty
                        ? 'Прикрепить файлы'
                        : 'Файлов: ${files.length}',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: loading ? null : () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: loading
                ? null
                : () async {
                    if (classId.text.trim().isEmpty ||
                        subjectId.text.trim().isEmpty ||
                        subjectName.text.trim().isEmpty ||
                        title.text.trim().isEmpty) {
                      _showMessage(
                        context,
                        'Заполните код класса, предмет и заголовок.',
                      );
                      return;
                    }
                    setState(() => loading = true);
                    try {
                      await repository.createAssignment(
                        teacher: teacher,
                        classId: classId.text,
                        subjectId: subjectId.text,
                        subjectName: subjectName.text,
                        title: title.text,
                        description: description.text,
                        dueDate: dueDate,
                        files: files,
                      );
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                    } on FirebaseException catch (error) {
                      if (!context.mounted) return;
                      _showMessage(
                        context,
                        error.message ?? 'Не удалось создать задание.',
                      );
                      setState(() => loading = false);
                    } on ArgumentError catch (error) {
                      if (!context.mounted) return;
                      _showMessage(
                        context,
                        error.message?.toString() ?? 'Проверьте файлы.',
                      );
                      setState(() => loading = false);
                    }
                  },
            child: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Создать'),
          ),
        ],
      ),
    ),
  );
  classId.dispose();
  subjectId.dispose();
  subjectName.dispose();
  title.dispose();
  description.dispose();
}

Future<void> _showSubmissionDialog(
  BuildContext context,
  SchoolRepository repository,
  SchoolAssignment assignment,
  UserProfile student,
) async {
  final answer = TextEditingController();
  var files = <({String name, Uint8List bytes})>[];
  var loading = false;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Сдать работу'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: answer,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'Текстовый ответ'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await _chooseFiles(context);
                if (!context.mounted) return;
                setState(() => files = picked);
              },
              icon: const Icon(Icons.attach_file),
              label: Text(
                files.isEmpty
                    ? 'Добавить фото или PDF'
                    : 'Файлов: ${files.length}',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: loading ? null : () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: loading
                ? null
                : () async {
                    if (answer.text.trim().isEmpty && files.isEmpty) {
                      _showMessage(
                        context,
                        'Добавьте текстовый ответ или файл.',
                      );
                      return;
                    }
                    setState(() => loading = true);
                    try {
                      await repository.submitAnswer(
                        assignment: assignment,
                        student: student,
                        answerText: answer.text,
                        files: files,
                      );
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                    } on FirebaseException catch (error) {
                      if (!context.mounted) return;
                      _showMessage(
                        context,
                        error.message ?? 'Не удалось отправить работу.',
                      );
                      setState(() => loading = false);
                    } on StateError catch (error) {
                      if (!context.mounted) return;
                      _showMessage(context, error.message);
                      setState(() => loading = false);
                    } on ArgumentError catch (error) {
                      if (!context.mounted) return;
                      _showMessage(
                        context,
                        error.message?.toString() ?? 'Проверьте файлы.',
                      );
                      setState(() => loading = false);
                    }
                  },
            child: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Отправить'),
          ),
        ],
      ),
    ),
  );
  answer.dispose();
}

Future<void> _showGradeDialog(
  BuildContext context,
  SchoolRepository repository,
  StudentSubmission submission,
) async {
  final grade = TextEditingController();
  final comment = TextEditingController();
  var loading = false;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('Работа: ${submission.studentName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (submission.answerText.isNotEmpty) Text(submission.answerText),
            for (final file in submission.answerFiles)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.image_outlined),
                title: const Text('Открыть файл ответа'),
                onTap: () => _openLink(context, file),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: grade,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Оценка (1–100)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: comment,
              decoration: const InputDecoration(labelText: 'Комментарий'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: loading ? null : () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: loading
                ? null
                : () async {
                    final value = num.tryParse(grade.text.trim());
                    if (value == null || value < 1 || value > 100) {
                      _showMessage(context, 'Введите оценку от 1 до 100.');
                      return;
                    }
                    setState(() => loading = true);
                    try {
                      await repository.gradeSubmission(
                        submission: submission,
                        grade: value,
                        comment: comment.text,
                      );
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                    } on FirebaseException catch (error) {
                      if (!context.mounted) return;
                      _showMessage(
                        context,
                        error.message ?? 'Не удалось сохранить оценку.',
                      );
                      setState(() => loading = false);
                    }
                  },
            child: const Text('Сохранить оценку'),
          ),
        ],
      ),
    ),
  );
  grade.dispose();
  comment.dispose();
}

Future<void> _showLinkChildDialog(
  BuildContext context,
  SchoolRepository repository,
) async {
  final code = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Привязать ребёнка'),
      content: TextField(
        controller: code,
        keyboardType: TextInputType.number,
        maxLength: 6,
        decoration: const InputDecoration(labelText: '6-значный код'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () async {
            if (!RegExp(r'^\d{6}$').hasMatch(code.text.trim())) {
              _showMessage(context, 'Введите корректный 6-значный код.');
              return;
            }
            try {
              await repository.linkChild(code.text);
              if (!dialogContext.mounted || !context.mounted) return;
              Navigator.pop(dialogContext);
              _showMessage(context, 'Профиль ребёнка привязан.');
            } on FirebaseFunctionsException catch (error) {
              if (!context.mounted) return;
              _showMessage(
                context,
                error.message ?? 'Не удалось привязать профиль.',
              );
            }
          },
          child: const Text('Привязать'),
        ),
      ],
    ),
  );
  code.dispose();
}

class _DialogField extends StatelessWidget {
  const _DialogField({
    required this.controller,
    required this.label,
    this.maxLines = 1,
  });
  final TextEditingController controller;
  final String label;
  final int maxLines;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: label),
    ),
  );
}

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<void> _openLink(BuildContext context, String link) async {
  try {
    final opened = await launchUrl(
      Uri.parse(link),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      _showMessage(context, 'Не удалось открыть файл.');
    }
  } on PlatformException catch (error) {
    if (context.mounted) {
      _showMessage(context, error.message ?? 'Не удалось открыть файл.');
    }
  } on FormatException {
    if (context.mounted) _showMessage(context, 'Ссылка на файл некорректна.');
  }
}

String _formatDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
