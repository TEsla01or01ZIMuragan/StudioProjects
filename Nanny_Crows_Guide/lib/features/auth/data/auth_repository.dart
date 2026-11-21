import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:nanny_crows_guide/features/auth/domain/user_profile.dart';

class AuthRepository {
  AuthRepository(this._auth, this._firestore);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  Future<void> signIn(String email, String password) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> register({
    required String email,
    required String password,
    required String fullName,
    required UserRole role,
  }) async {
    UserCredential credential;
    try {
      credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (error) {
      if (error.code != 'email-already-in-use') rethrow;

      credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final existingUser = credential.user;
      if (existingUser == null) {
        throw StateError('Firebase Auth не вернул пользователя.');
      }
      final existingProfile = await _firestore
          .collection('users')
          .doc(existingUser.uid)
          .get();
      if (existingProfile.exists) {
        await _auth.signOut();
        throw FirebaseAuthException(
          code: 'email-already-in-use',
          message: 'Аккаунт с этой почтой уже зарегистрирован. Войдите в него.',
        );
      }
    }

    final user = credential.user;
    if (user == null) {
      throw StateError('Firebase Auth не вернул созданного пользователя.');
    }
    await _firestore.collection('users').doc(user.uid).set({
      'uid': user.uid,
      'role': role.name,
      'fullName': fullName.trim(),
      'email': email.trim(),
      'childrenIds': <String>[],
      'childClassIds': <String>[],
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<UserProfile> watchProfile(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((snapshot) {
      if (!snapshot.exists) {
        throw StateError('Профиль пользователя ещё не создан.');
      }
      return UserProfile.fromMap(snapshot.id, snapshot.data()!);
    });
  }

  Future<void> signOut() => _auth.signOut();
}
