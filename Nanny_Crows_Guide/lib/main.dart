import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Роли и Задания',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const AuthGate(),
    );
  }
}

// Этот виджет слушает состояние авторизации и переключает экраны
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasData && snapshot.data != null) {
          return RoleBasedScreen(user: snapshot.data!);
        }
        return const LoginScreen();
      },
    );
  }
}

// Экран входа
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  Future<void> _signIn() async {
    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      // После успешного входа AuthGate сам переключит экран
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: ${e.message}')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Вход')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Пароль'),
              obscureText: true,
            ),
            const SizedBox(height: 24),
            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
              onPressed: _signIn,
              child: const Text('Войти'),
            ),
          ],
        ),
      ),
    );
  }
}

// Экран, который читает роль из Firestore и показывает нужный интерфейс
class RoleBasedScreen extends StatelessWidget {
  final User user;
  const RoleBasedScreen({super.key, required this.user});

  // Функция для выхода и возврата на экран логина
  Future<void> _signOutAndGoBack(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      // Возвращаемся на самый первый экран
      Navigator.of(context).popUntil((route) => route.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Профиль не найден в базе. Пожалуйста, войдите снова.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      // Читаем документ пользователя из коллекции 'users' по его uid
      future: FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        // Если документа нет или произошла ошибка — выкидываем на экран входа
        if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {

          // Вызываем выход через микро-задержку, чтобы не ломать сборку UI
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _signOutAndGoBack(context);
          });

          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Пользователь не найден в базе...'),
                ],
              ),
            ),
          );
        }

        final userData = snapshot.data!.data() as Map<String, dynamic>;
        final role = userData['role'];

        // В зависимости от роли возвращаем разные виджеты
        switch (role) {
          case 'child':
            return const ChildHome();
          case 'parent':
            return const ParentHome();
          case 'curator':
            return const CuratorHome();
          default:
            return const Scaffold(body: Center(child: Text('Неизвестная роль')));
        }
      },
    );
  }
}

// Заглушки для экранов
class ChildHome extends StatelessWidget {
  const ChildHome({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('Ребёнок')), body: const Center(child: Text('Тут будут задания')));
  }
}

class ParentHome extends StatelessWidget {
  const ParentHome({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('Родитель')), body: const Center(child: Text('Тут будет прогресс и чат')));
  }
}

class CuratorHome extends StatelessWidget {
  const CuratorHome({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('Куратор')), body: const Center(child: Text('Тут будут задания и чат')));
  }
}