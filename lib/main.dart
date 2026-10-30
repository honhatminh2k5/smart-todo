import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/firebase_runtime_config.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/presentation/auth_screens.dart';
import 'features/boards/presentation/boards_screen.dart';

const bool _useFirebaseEmulators = bool.fromEnvironment(
  'USE_FIREBASE_EMULATORS',
  defaultValue: false,
);
const String _emulatorHost = String.fromEnvironment(
  'FIREBASE_EMULATOR_HOST',
  // Android Emulator accesses services on the host computer through 10.0.2.2.
  defaultValue: '10.0.2.2',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  String? firebaseSetupMessage;

  // For local emulator testing, use demo options. They are not production credentials.
  // For normal Firebase use, keep using the private firebase_config.json values.
  if (FirebaseRuntimeConfig.isConfigured || _useFirebaseEmulators) {
    try {
      final options = _useFirebaseEmulators
          ? const FirebaseOptions(
              apiKey: 'fake-api-key',
              appId: '1:1234567890:android:demo',
              messagingSenderId: '1234567890',
              projectId: 'demo-smart-todo',
            )
          : FirebaseRuntimeConfig.options;

      await Firebase.initializeApp(options: options);

      if (_useFirebaseEmulators) {
        await FirebaseAuth.instance.useAuthEmulator(_emulatorHost, 9099);
        FirebaseFirestore.instance.useFirestoreEmulator(_emulatorHost, 8080);
      }
    } catch (error) {
      firebaseSetupMessage = _useFirebaseEmulators
          ? 'Không kết nối được Firebase Emulator. Hãy kiểm tra cửa sổ Emulator và địa chỉ máy chủ. Chi tiết: $error'
          : 'Không khởi tạo được Firebase. Kiểm tra lại cấu hình trong docs/firebase-auth-setup.md. Chi tiết: $error';
    }
  } else {
    firebaseSetupMessage =
        'Chế độ xem trước: chưa có cấu hình Firebase. Để thử database cục bộ, chạy với --dart-define=USE_FIREBASE_EMULATORS=true. Để kết nối Firebase thật, làm theo docs/firebase-auth-setup.md.';
  }

  runApp(
    ProviderScope(
      child: SmartTodoApp(firebaseSetupMessage: firebaseSetupMessage),
    ),
  );
}

class SmartTodoApp extends StatelessWidget {
  const SmartTodoApp({required this.firebaseSetupMessage, super.key});

  final String? firebaseSetupMessage;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Todo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3157D5)),
        useMaterial3: true,
      ),
      home: _AuthGate(firebaseSetupMessage: firebaseSetupMessage),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate({required this.firebaseSetupMessage});

  final String? firebaseSetupMessage;

  @override
  Widget build(BuildContext context) {
    final auth = AuthRepository();
    if (firebaseSetupMessage != null) {
      return SignInScreen(
        auth: auth,
        firebaseSetupMessage: firebaseSetupMessage,
      );
    }

    return StreamBuilder<User?>(
      stream: auth.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return SignInScreen(
            auth: auth,
            firebaseSetupMessage:
                'Không đọc được phiên đăng nhập. Kiểm tra kết nối rồi khởi động lại ứng dụng.',
          );
        }
        final user = snapshot.data;
        return user == null
            ? SignInScreen(auth: auth, firebaseSetupMessage: null)
            : BoardsScreen(user: user, auth: auth);
      },
    );
  }
}
