import 'package:d_server/d_server.dart';

/// Controller for handling authentication-related actions
class AuthController extends DController with Authenticatable {
  /// GET /auth
  @override
  Future<Response> index() async {
    if (flashMessages.has('error')) {
      setFlash('error', flashMessages.get('error')!);
    }
    return render(
      'auth/index',
      locals: {
        'title': 'Auth Index',
      },
    );
  }

  /// POST /auth
  @override
  Future<Response> create() async {
    final body = await parseBody();
    if (!body.containsKey('username') || !body.containsKey('password')) {
      return redirectToLogin(message: 'Missing username or password');
    }

    return redirectAfterLogin();
  }
}
