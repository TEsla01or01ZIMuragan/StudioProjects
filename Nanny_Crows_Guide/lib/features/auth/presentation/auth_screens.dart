import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nanny_crows_guide/core/auth_flow.dart';
import 'package:nanny_crows_guide/core/providers.dart';
import 'package:nanny_crows_guide/features/auth/domain/user_profile.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  UserRole _role = UserRole.student;
  bool _isRegistering = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isLoading) return;
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty ||
        password.isEmpty ||
        (_isRegistering && _name.text.trim().isEmpty)) {
      _showMessage('Заполните обязательные поля.');
      return;
    }

    setState(() => _isLoading = true);
    final registering = _isRegistering;
    var clearRegistrationPending = true;
    if (registering) AuthFlow.registrationPending = true;
    try {
      final repository = ref.read(authRepositoryProvider);
      if (registering) {
        await repository.register(
          email: email,
          password: password,
          fullName: _name.text,
          role: _role,
        );
      } else {
        await repository.signIn(email, password);
      }
      if (registering) AuthFlow.registrationPending = false;
      if (mounted) context.go('/home');
    } on FirebaseAuthException catch (error) {
      clearRegistrationPending = await _finishFailedRegistration(
        registering,
        error,
      );
      if (clearRegistrationPending) {
        _showMessage(error.message ?? 'Не удалось выполнить вход.');
      }
    } on FirebaseException catch (error) {
      clearRegistrationPending = await _finishFailedRegistration(
        registering,
        error,
      );
      if (clearRegistrationPending) {
        _showMessage(_firebaseErrorMessage(error));
      }
    } on StateError catch (error) {
      clearRegistrationPending = await _finishFailedRegistration(
        registering,
        error,
      );
      if (clearRegistrationPending) _showMessage(error.message);
    } finally {
      if (registering && clearRegistrationPending) {
        AuthFlow.registrationPending = false;
      }
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _finishFailedRegistration(
    bool registering,
    Object originalError,
  ) async {
    if (!registering) return true;
    try {
      await ref.read(authRepositoryProvider).signOut();
      return true;
    } on FirebaseAuthException catch (error) {
      AuthFlow.registrationPending = true;
      _showMessage(
        'Ошибка регистрации: $originalError. '
        'Не удалось завершить выход: ${error.message ?? error.code}.',
      );
      return false;
    } on FirebaseException catch (error) {
      AuthFlow.registrationPending = true;
      _showMessage(
        'Ошибка регистрации: $originalError. '
        'Не удалось завершить выход: ${error.message ?? error.code}.',
      );
      return false;
    }
  }

  String _firebaseErrorMessage(FirebaseException error) {
    if (error.code == 'permission-denied') {
      return 'Firebase запретил создать профиль. Опубликуйте актуальные '
          'firestore.rules в Firebase Console. Подробности: ${error.message}';
    }
    return error.message ?? 'Не удалось сохранить профиль.';
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.school_rounded, size: 52, color: colors.primary),
                    const SizedBox(height: 12),
                    Text(
                      'Nanny Crows',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isRegistering ? 'Создайте аккаунт' : 'Войдите в аккаунт',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    if (_isRegistering) ...[
                      TextField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(labelText: 'ФИО'),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<UserRole>(
                        initialValue: _role,
                        decoration: const InputDecoration(labelText: 'Роль'),
                        items: UserRole.values
                            .map(
                              (role) => DropdownMenuItem(
                                value: role,
                                child: Text(role.label),
                              ),
                            )
                            .toList(),
                        onChanged: (role) {
                          if (role != null) setState(() => _role = role);
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(labelText: 'Email'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      decoration: const InputDecoration(labelText: 'Пароль'),
                    ),
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: _isLoading ? null : _submit,
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              _isRegistering ? 'Зарегистрироваться' : 'Войти',
                            ),
                    ),
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () => setState(
                              () => _isRegistering = !_isRegistering,
                            ),
                      child: Text(
                        _isRegistering
                            ? 'Уже есть аккаунт? Войти'
                            : 'Создать аккаунт',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
