import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'youtube_settings.dart';

class YouTubeAuthException implements Exception {
  YouTubeAuthException(this.message, {this.signedOut = false});

  final String message;

  /// True when Google rejected the stored sign-in and the user has to sign
  /// in again.
  final bool signedOut;

  @override
  String toString() => message;
}

/// Google OAuth for the YouTube Data API, read-only scope, using the desktop
/// "loopback" flow with PKCE. The user supplies their own OAuth client
/// (Google Cloud project, "Desktop app" client type) in the YouTube settings.
class YouTubeAuth {
  YouTubeAuth._();

  static final YouTubeAuth instance = YouTubeAuth._();

  /// Read access for the subscriptions plus force-ssl for rating videos and
  /// writing comments.
  static const scope =
      'https://www.googleapis.com/auth/youtube.readonly https://www.googleapis.com/auth/youtube.force-ssl';
  static final Uri _tokenUrl = Uri.parse('https://oauth2.googleapis.com/token');

  final http.Client _client = http.Client();
  String? _accessToken;
  DateTime? _expiresAt;

  void invalidateAccessToken() {
    _accessToken = null;
    _expiresAt = null;
  }

  /// Opens Google's consent page in the browser and waits for the redirect.
  Future<void> signIn() async {
    final settings = YouTubeSettings.instance;
    await settings.load();
    if (!settings.hasCredentials) throw YouTubeAuthException('No OAuth client ID set.');

    final verifier = _randomString(64);
    final challenge = base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');
    final state = _randomString(24);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirectUri = 'http://127.0.0.1:${server.port}';
    final completer = Completer<Map<String, String>>();

    final subscription = server.listen((request) async {
      final params = request.uri.queryParameters;
      final isCallback = params.containsKey('code') || params.containsKey('error');
      request.response
        ..statusCode = isCallback ? HttpStatus.ok : HttpStatus.notFound
        ..headers.contentType = ContentType.html;
      if (isCallback) {
        request.response.write(
          '<!doctype html><meta charset="utf-8"><title>Plezy Retrowave</title>'
          '<body style="font-family:sans-serif;background:#0b0618;color:#f4ecff;'
          'display:flex;align-items:center;justify-content:center;height:100vh;margin:0">'
          '<p>You can close this tab and return to Plezy Retrowave.</p></body>',
        );
      }
      await request.response.close();
      if (isCallback && !completer.isCompleted) completer.complete(params);
    });

    try {
      final authUrl = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': settings.clientId,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'scope': scope,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'access_type': 'offline',
        'prompt': 'consent',
        'state': state,
      });
      if (!await launchUrl(authUrl, mode: LaunchMode.externalApplication)) {
        throw YouTubeAuthException('Could not open the browser.');
      }

      final params = await completer.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () => throw YouTubeAuthException('Sign-in timed out.'),
      );
      if (params['state'] != state) throw YouTubeAuthException('Sign-in failed (state mismatch).');
      final code = params['code'];
      if (code == null) throw YouTubeAuthException('Sign-in cancelled: ${params['error'] ?? 'unknown'}');

      final response = await _client.post(
        _tokenUrl,
        body: {
          'client_id': settings.clientId,
          if (settings.clientSecret.isNotEmpty) 'client_secret': settings.clientSecret,
          'code': code,
          'code_verifier': verifier,
          'redirect_uri': redirectUri,
          'grant_type': 'authorization_code',
        },
      );
      if (response.statusCode != 200) {
        throw YouTubeAuthException('Google rejected the sign-in: ${_errorText(response.body)}');
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      _storeAccessToken(json);
      final refreshToken = json['refresh_token'] as String?;
      if (refreshToken == null || refreshToken.isEmpty) {
        throw YouTubeAuthException('Google returned no refresh token.');
      }
      await settings.setRefreshToken(refreshToken);
      await settings.setGrantedScopes(json['scope'] as String? ?? scope);
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  }

  Future<void> signOut() async {
    final settings = YouTubeSettings.instance;
    await settings.load();
    final token = settings.refreshToken;
    invalidateAccessToken();
    await settings.setRefreshToken('');
    await settings.setAccountName('');
    await settings.setAccountChannelId('');
    await settings.setGrantedScopes('');
    if (token.isNotEmpty) {
      try {
        await _client.post(Uri.https('oauth2.googleapis.com', '/revoke', {'token': token}));
      } catch (_) {
        // Best effort: the token is already forgotten locally.
      }
    }
  }

  /// A valid access token, refreshed when needed.
  Future<String> accessToken() async {
    final token = _accessToken;
    final expiresAt = _expiresAt;
    if (token != null && expiresAt != null && DateTime.now().isBefore(expiresAt)) return token;

    final settings = YouTubeSettings.instance;
    await settings.load();
    if (!settings.isSignedIn) throw YouTubeAuthException('Not signed in.', signedOut: true);

    final response = await _client.post(
      _tokenUrl,
      body: {
        'client_id': settings.clientId,
        if (settings.clientSecret.isNotEmpty) 'client_secret': settings.clientSecret,
        'refresh_token': settings.refreshToken,
        'grant_type': 'refresh_token',
      },
    );
    if (response.statusCode == 400 || response.statusCode == 401) {
      await settings.setRefreshToken('');
      throw YouTubeAuthException('Your YouTube sign-in expired. Please sign in again.', signedOut: true);
    }
    if (response.statusCode != 200) {
      throw YouTubeAuthException('Could not refresh the YouTube sign-in: ${_errorText(response.body)}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return _storeAccessToken(json);
  }

  String _storeAccessToken(Map<String, dynamic> json) {
    final token = json['access_token'] as String;
    final expiresIn = (json['expires_in'] as num?)?.toInt() ?? 3600;
    _accessToken = token;
    _expiresAt = DateTime.now().add(Duration(seconds: max(60, expiresIn - 60)));
    return token;
  }

  static String _errorText(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      return (json['error_description'] ?? json['error'] ?? body).toString();
    } catch (_) {
      return body;
    }
  }

  static String _randomString(int length) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final random = Random.secure();
    return List.generate(length, (_) => chars[random.nextInt(chars.length)]).join();
  }
}
