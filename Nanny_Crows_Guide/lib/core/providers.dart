import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nanny_crows_guide/features/auth/data/auth_repository.dart';
import 'package:nanny_crows_guide/features/auth/domain/user_profile.dart';
import 'package:nanny_crows_guide/features/school/data/school_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(FirebaseAuth.instance, FirebaseFirestore.instance),
);

final schoolRepositoryProvider = Provider<SchoolRepository>(
  (ref) => SchoolRepository(
    FirebaseFirestore.instance,
    FirebaseAuth.instance,
  ),
);

final currentUserProvider = StreamProvider<User?>(
  (ref) => FirebaseAuth.instance.authStateChanges(),
);

final userProfileProvider = StreamProvider<UserProfile>((ref) {
  final authState = ref.watch(currentUserProvider);
  return authState.when(
    data: (user) => user == null
        ? const Stream<UserProfile>.empty()
        : ref.watch(authRepositoryProvider).watchProfile(user.uid),
    loading: () => const Stream<UserProfile>.empty(),
    error: (error, stackTrace) => Stream<UserProfile>.error(error, stackTrace),
  );
});
