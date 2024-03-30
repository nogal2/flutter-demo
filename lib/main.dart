import 'package:actual/common/component/custom_text_form_field.dart';
import 'package:actual/common/provider/go_router.dart';
import 'package:actual/common/secure_storage/secure_storage.dart';
import 'package:actual/common/view/splash_screen.dart';
import 'package:actual/user/view/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() {
  runApp(
    ProviderScope(
      child: _App(),
    ),
  );
}

class _App extends ConsumerWidget {
  const _App({super.key});


  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // watch - 값이 변경될때마다 다시빌드
    // read - 한번만 읽고 값이 변경돼도 다시 빌드하지 않음
    final router = ref.read(routerProvider);

    return MaterialApp.router(
      theme: ThemeData(
        fontFamily: 'NotoSans',
      ),
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      // home: Scaffold(
      //   backgroundColor: Colors.white,
      //   body: SplashScreen(),
      // ),
    );
  }
}
