class SessionService {
  static final SessionService _instance = SessionService._internal();

  factory SessionService() {
    return _instance;
  }

  SessionService._internal();

  String? token;
  String? uid;
  String? role;

  void setSession({
    required String token,
    required String uid,
    required String role,
  }) {
    this.token = token;
    this.uid = uid;
    this.role = role;
  }

  void clear() {
    token = null;
    uid = null;
    role = null;
  }
}
