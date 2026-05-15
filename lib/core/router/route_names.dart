class RouteNames {
  RouteNames._();

  static const String welcome = 'welcome';
  static const String login = 'login';
  static const String register = 'register';
  static const String forgotPassword = 'forgot_password';
  static const String passwordResetSent = 'password_reset_sent';
  static const String setNewPassword = 'set_new_password';
  static const String passwordUpdated = 'password_updated';
  static const String verifyEmailSent = 'verify_email_sent';
  static const String emailVerified = 'email_verified';
  static const String authCallback = 'auth_callback';
  static const String magicLink = 'magic_link';
  static const String magicLinkSent = 'magic_link_sent';
  static const String otpRequest = 'otp_request';
  static const String otpVerify = 'otp_verify';
  static const String mfaSetup = 'mfa_setup';
  static const String mfaChallenge = 'mfa_challenge';
  static const String home = 'home';
  static const String admin = 'admin';
  static const String adminFlags = 'admin_flags';
  static const String accountSettings = 'account_settings';
  static const String changePassword = 'change_password';
  static const String changePasswordDone = 'change_password_done';
  static const String changeEmail = 'change_email';
  static const String changeEmailSent = 'change_email_sent';
  static const String emailChanged = 'email_changed';
  static const String deleteAccount = 'delete_account';
  static const String passkeys = 'passkeys';
  static const String auditLog = 'audit_log';
  static const String team = 'team';
  static const String acceptInvite = 'accept_invite';
  static const String terms = 'terms';
  static const String privacy = 'privacy';
  static const String cookies = 'cookies';
  static const String notFound = 'not_found';
}

class RoutePaths {
  RoutePaths._();

  static const String welcome = '/';
  static const String login = '/login';
  static const String register = '/register';
  static const String forgotPassword = '/forgot-password';
  static const String passwordResetSent = '/password-reset-sent';
  static const String setNewPassword = '/set-new-password';
  static const String passwordUpdated = '/password-updated';
  static const String verifyEmailSent = '/verify-email-sent';
  static const String emailVerified = '/email-verified';
  static const String authCallback = '/auth/callback';
  static const String magicLink = '/magic-link';
  static const String magicLinkSent = '/magic-link-sent';
  static const String otpRequest = '/otp';
  // NO usar paths anidados sin GoRoute padre. go_router se confunde si
  // `/otp/verify` es ruta plana mientras existe `/otp` como ruta plana
  // independiente — dispara `assert(uri.path.startsWith(matchedLocation))`.
  static const String otpVerify = '/otp-verify';
  static const String mfaSetup = '/mfa-setup';
  static const String mfaChallenge = '/mfa-challenge';
  static const String home = '/home';
  static const String admin = '/admin';
  static const String adminFlags = '/admin/flags';
  static const String accountSettings = '/account-settings';
  static const String changePassword = '/change-password';
  static const String changePasswordDone = '/change-password-done';
  static const String changeEmail = '/change-email';
  static const String changeEmailSent = '/change-email-sent';
  static const String emailChanged = '/email-changed';
  static const String deleteAccount = '/delete-account';
  static const String passkeys = '/passkeys';
  static const String auditLog = '/audit-log';
  static const String team = '/team';
  static const String acceptInvite = '/accept-invite';
  static const String terms = '/terms';
  static const String privacy = '/privacy';
  static const String cookies = '/cookies';
}
