/// 🤖 Generated wholely or partially with GPT-5 Codex; OpenAI
/// 🤖 Modified with Claude Opus 4.6; Google Antigravity
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:saber/data/google_drive/google_drive_models.dart';
import 'package:url_launcher/url_launcher.dart';

class GoogleDriveLoginResult {
  const GoogleDriveLoginResult({
    required this.accessToken,
    required this.refreshToken,
    required this.accessTokenExpiresAt,
    required this.profile,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime accessTokenExpiresAt;
  final GoogleDriveProfile profile;
}

/// Implements OAuth2 PKCE login for Google Drive.
///
/// - **Desktop (Windows/macOS/Linux)**: Opens the system browser, catches the
///   callback on a local HTTP server (loopback redirect).
/// - **Mobile (Android/iOS)**: Opens a Chrome Custom Tab (or ASWebAuthSession)
///   via [FlutterWebAuth2], uses the reverse-client-ID custom URI scheme as the
///   redirect. No Firebase or `google-services.json` required.
class GoogleDriveLoginFlow {
  GoogleDriveLoginFlow({
    required this.clientId,
    required this.clientSecret,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  static final log = Logger('GoogleDriveLoginFlow');

  static const _oauthScopes = <String>[
    'openid',
    'email',
    'profile',
    'https://www.googleapis.com/auth/drive',
  ];

  final String clientId;
  final String clientSecret;
  final http.Client _httpClient;

  Future<GoogleDriveLoginResult> start({
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final isMobile = defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;

    final String codePayload;
    if (isMobile) {
      codePayload = await _openCustomTabAndWaitForCode();
    } else {
      codePayload = await _openBrowserAndWaitForCode(timeout: timeout);
    }

    final tokenPayload = await _exchangeCodeForTokens(codePayload);

    final accessToken = '${tokenPayload['access_token'] ?? ''}';
    final refreshToken = '${tokenPayload['refresh_token'] ?? ''}';
    final expiresIn =
        int.tryParse('${tokenPayload['expires_in'] ?? 3600}') ?? 3600;
    final expiresAt = DateTime.now().toUtc().add(Duration(seconds: expiresIn));

    if (accessToken.isEmpty) {
      throw const FormatException(
        'Google token endpoint returned no access token.',
      );
    }
    if (refreshToken.isEmpty) {
      log.warning(
        'Google token endpoint returned no refresh token. '
        'Token renewal will require re-authentication.',
      );
    }

    final profile = await _fetchProfile(accessToken);
    return GoogleDriveLoginResult(
      accessToken: accessToken,
      refreshToken: refreshToken,
      accessTokenExpiresAt: expiresAt,
      profile: profile,
    );
  }

  // ---------------------------------------------------------------------------
  // Mobile: Chrome Custom Tab via flutter_web_auth_2
  // ---------------------------------------------------------------------------

  /// Builds the reverse-client-ID redirect URI scheme that Google OAuth
  /// recognises for "installed app" clients on mobile.
  String get _mobileRedirectScheme {
    // Client ID: xxxx.apps.googleusercontent.com
    // Reverse:   com.googleusercontent.apps.xxxx
    final parts = clientId.split('.').reversed.toList();
    return parts.join('.');
  }

  /// Opens a Chrome Custom Tab (Android) or ASWebAuthSession (iOS) with
  /// Google's OAuth consent screen and waits for the redirect.
  Future<String> _openCustomTabAndWaitForCode() async {
    final redirectUri = '$_mobileRedirectScheme:/oauth2callback';
    final codeVerifier = _randomUrlSafe(64);
    final codeChallenge = _codeChallengeFromVerifier(codeVerifier);

    final authUri = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': _oauthScopes.join(' '),
      'access_type': 'offline',
      'prompt': 'consent',
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
    });

    log.info('Opening Google auth URI in Custom Tab: $authUri');

    final resultUri = await FlutterWebAuth2.authenticate(
      url: authUri.toString(),
      callbackUrlScheme: _mobileRedirectScheme,
    );

    final resultParams = Uri.parse(resultUri).queryParameters;
    final error = resultParams['error'];
    if (error != null) {
      throw StateError('Google OAuth failed: $error');
    }

    final code = resultParams['code'];
    if (code == null || code.isEmpty) {
      throw const FormatException('No authorization code in Google callback.');
    }

    // Pack the code, verifier, and redirect URI for token exchange.
    return '$code::$codeVerifier::$redirectUri';
  }

  // ---------------------------------------------------------------------------
  // Desktop: local loopback HTTP server
  // ---------------------------------------------------------------------------

  Future<String> _openBrowserAndWaitForCode({required Duration timeout}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirectUri = Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      path: '/oauth2callback',
    );
    final state = _randomUrlSafe(32);
    final codeVerifier = _randomUrlSafe(64);
    final codeChallenge = _codeChallengeFromVerifier(codeVerifier);

    final authUri = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': clientId,
      'redirect_uri': redirectUri.toString(),
      'response_type': 'code',
      'scope': _oauthScopes.join(' '),
      'access_type': 'offline',
      'prompt': 'consent',
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
      'state': state,
    });

    log.info('Opening Google auth URI: $authUri');
    final opened = await launchUrl(
      authUri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      await server.close(force: true);
      throw OSError('Failed to open browser for Google OAuth login.');
    }

    final codeCompleter = Completer<String>();
    late final StreamSubscription<HttpRequest> sub;
    sub = server.listen((request) async {
      final query = request.uri.queryParameters;
      final returnedState = query['state'];
      final error = query['error'];
      final code = query['code'];

      Future<void> sendPage(
        String html, {
        int statusCode = HttpStatus.ok,
      }) async {
        request.response
          ..statusCode = statusCode
          ..headers.contentType = ContentType.html
          ..write(html);
        await request.response.close();
      }

      if (error != null) {
        await sendPage(
          '<h1>Authorization failed</h1><p>$error</p>',
          statusCode: 400,
        );
        if (!codeCompleter.isCompleted) {
          codeCompleter.completeError(
            StateError('Google OAuth failed: $error'),
          );
        }
        return;
      }

      if (returnedState != state || code == null || code.isEmpty) {
        await sendPage('<h1>Invalid OAuth response</h1>', statusCode: 400);
        if (!codeCompleter.isCompleted) {
          codeCompleter.completeError(
            const FormatException('Invalid OAuth callback payload.'),
          );
        }
        return;
      }

      await sendPage('<h1>Login successful</h1><p>You can close this tab.</p>');
      if (!codeCompleter.isCompleted) {
        codeCompleter.complete('$code::$codeVerifier::$redirectUri');
      }
    });

    try {
      final payload = await codeCompleter.future.timeout(timeout);
      return payload;
    } finally {
      await sub.cancel();
      await server.close(force: true);
    }
  }

  // ---------------------------------------------------------------------------
  // Token exchange & profile (shared by both flows)
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _exchangeCodeForTokens(
    String codePayload,
  ) async {
    final parts = codePayload.split('::');
    if (parts.length != 3) {
      throw const FormatException('OAuth payload format is invalid.');
    }

    final code = parts[0];
    final codeVerifier = parts[1];
    final redirectUri = parts[2];

    final body = <String, String>{
      'code': code,
      'client_id': clientId,
      'grant_type': 'authorization_code',
      'redirect_uri': redirectUri,
      'code_verifier': codeVerifier,
    };
    if (clientSecret.isNotEmpty) body['client_secret'] = clientSecret;

    final response = await _httpClient.post(
      Uri.https('oauth2.googleapis.com', '/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: body,
    );

    final decoded = jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Google token exchange failed: $decoded');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid token response from Google.');
    }
    return decoded;
  }

  Future<GoogleDriveProfile> _fetchProfile(String accessToken) async {
    final response = await _httpClient.get(
      Uri.https('www.googleapis.com', '/oauth2/v2/userinfo'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    final decoded = jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Failed to fetch Google profile: $decoded');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid profile response from Google.');
    }

    final email = '${decoded['email'] ?? ''}';
    if (email.isEmpty) {
      throw const FormatException(
        'Google profile response did not include email.',
      );
    }

    final pictureRaw = '${decoded['picture'] ?? ''}';
    return GoogleDriveProfile(
      email: email,
      displayName: decoded['name']?.toString(),
      pictureUrl: pictureRaw.isEmpty ? null : Uri.tryParse(pictureRaw),
    );
  }

  static String _randomUrlSafe(int bytesCount) {
    final random = Random.secure();
    final bytes = Uint8List.fromList(
      List<int>.generate(bytesCount, (_) => random.nextInt(256)),
    );
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static String _codeChallengeFromVerifier(String codeVerifier) {
    final hash = sha256.convert(utf8.encode(codeVerifier)).bytes;
    return base64UrlEncode(hash).replaceAll('=', '');
  }
}
