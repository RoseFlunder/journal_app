/// Build-time Google OAuth configuration. Client IDs are public identifiers,
/// so they may be supplied with --dart-define and are never treated as
/// secrets.
class GoogleCloudConfig {
  const GoogleCloudConfig({
    this.webClientId,
    this.desktopClientId,
    this.serverClientId,
  });

  factory GoogleCloudConfig.fromEnvironment() => GoogleCloudConfig(
        webClientId: _value('GOOGLE_WEB_CLIENT_ID'),
        desktopClientId: _value('GOOGLE_DESKTOP_CLIENT_ID'),
        serverClientId: _value('GOOGLE_SERVER_CLIENT_ID'),
      );

  final String? webClientId;
  final String? desktopClientId;
  final String? serverClientId;

  bool get hasAnyClientId => webClientId != null || desktopClientId != null;

  static String? _value(String name) {
    const missing = String.fromEnvironment('COZY_BLOOM_MISSING');
    final value = String.fromEnvironment(name, defaultValue: missing);
    return value == missing || value.isEmpty ? null : value;
  }
}

const googleDriveAppDataScope = 'https://www.googleapis.com/auth/drive.appdata';
const googleIdentityScopes = <String>[
  'openid',
  'email',
  'profile',
];
const googleDriveScopes = <String>[
  ...googleIdentityScopes,
  googleDriveAppDataScope,
];
