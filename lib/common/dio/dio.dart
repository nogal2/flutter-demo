import 'package:actual/common/const/data.dart';
import 'package:actual/common/secure_storage/secure_storage.dart';
import 'package:actual/user/provider/auth_provider.dart';
import 'package:actual/user/provider/user_me_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio();

  final storage = ref.watch(secureStorageProvider);
  dio.interceptors.add(
    CustomInterceptor(storage: storage, ref: ref),
  );
  return dio;
});

class CustomInterceptor extends Interceptor {
  final FlutterSecureStorage storage;
  final Ref ref;

  CustomInterceptor({
    required this.storage,
    required this.ref,
  });

  // 1) 요청 보낼때
  // 만약 요청이 보내질 때마다
  // 만약에 요청의 Header에 accessToken: true 라는 값이 있다면
  // 실제 토큰을 가져와서 (storage에서) authorization: Bearer $token으로
  // 헤더를 변경 한다.
  // 토큰이 필요할 때마다 매번 집어넣을 수 없기 때문에!
  @override
  void onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    print('[REQ] [${options.method}] ${options.uri}');
    if (options.headers['accessToken'] == 'true') {
      // 헤더 삭제
      options.headers.remove('accessToken');
      final token = await storage.read(key: ACCESS_TOKEN_KEY);
      // print(token);
      // 실제 토큰으로 대체
      options.headers.addAll(
        {
          'authorization': 'Bearer $token',
        },
      );
    }

    if (options.headers['refreshToken'] == 'true') {
      // 헤더 삭제
      options.headers.remove('refreshToken');
      final token = await storage.read(key: REFRESH_TOKEN_KEY);
      // print(token);
      // 실제 토큰으로 대체
      options.headers.addAll(
        {
          'authorization': 'Bearer $token',
        },
      );
    }
    // return 전에는 보내기전이고, return 하면 보내짐
    return super.onRequest(options, handler);
  }

// 2) 응답 받을때
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    print(
        '[REP] [${response.requestOptions.method}] ${response.requestOptions.uri}');

    return super.onResponse(response, handler);
  }

  // 3) 에러가 났을때
  @override
  void onError(DioError err, ErrorInterceptorHandler handler) async {
    // 401에러가 났을때 (status code)
    // 토큰을 재발급 받는 시도를 하고 토큰이 재발급 되면
    // 다시 새로운 토큰으로 요청을 한다.
    print('[ERR] [${err.requestOptions.method}] ${err.requestOptions.uri}');
    final refreshToken = await storage.read(key: REFRESH_TOKEN_KEY);
    // refreshToken 아예 없으면
    // 당연히 에러를 던진다.
    if (refreshToken == null) {
      // 에러를 던질때는 handler.reject를 사용한다.
      return handler.reject(err);
    }

    final isStatus401 = err.response?.statusCode == 401;
    final isPathRefresh = err.requestOptions.path ==
        '/auth/token'; // true 면 토큰을 리프레시 하려다가 에러가 난것.

    if (isStatus401 && !isPathRefresh) {
      // 401에러인데, 토큰을 리프레시 하려는 의도가 아니었다면
      final dio = Dio();

      try {
        final resp = await dio.post(
          'http://$ip/auth/token',
          options: Options(
            headers: {
              'authorization': 'Bearer $refreshToken',
            },
          ),
        );

        final accessToken = resp.data['accessToken'];

        // 에러를 발생시킨 요청
        final options = err.requestOptions;

        // 토큰 변경하기
        options.headers.addAll({
          'authorization': 'Bearer $accessToken',
        });

        await storage.write(key: ACCESS_TOKEN_KEY, value: accessToken);

        // 에러가 나서 에러를 발생시킨 옵션들을 다 받아서 토큰만 받아서 다시 요청보냄
        final response = await dio.fetch(options);
        return handler.resolve(response);
      } on DioError catch (e) {
        // circular dependency error
        // A, B
        // A -> B의 친구
        // B -> A의 친구
        // 사람: A는 B의 친구구나
        // 기계: A -> B -> A -> B -> ....
        // userMeProvider -> dio -> userMeProvider -> dio ...
        // 순환참조
        ref.read(authProvider.notifier).logout();
        return handler.reject(e);
      }
    }
    // resolve 를 하면 에러가 안나는것처럼 할 수 있다.
    return handler.reject(err);
  }
}
