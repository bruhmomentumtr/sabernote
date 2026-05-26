/// 🤖 Generated wholely or partially with GPT-5 Codex; OpenAI
/// 🤖 Modified with Claude Opus 4.6; Google Antigravity
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';


import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/google_drive/google_drive_models.dart';
import 'package:saber/data/prefs.dart';

class GoogleDriveClient {
  GoogleDriveClient({
    required this.clientId,
    required this.clientSecret,
    required this.accessToken,
    required this.refreshToken,
    required this.accessTokenExpiresAt,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  static final log = Logger('GoogleDriveClient');

  static const appRootDirectoryPrefix = FileManager.appRootDirectoryPrefix;
  static const configFileName = 'config.sbc';
  static const reproducibleSalt = r'8MnPs64@R&mF8XjWeLrD';

  final String clientId;
  final String clientSecret;
  String accessToken;
  final String refreshToken;
  DateTime accessTokenExpiresAt;
  final http.Client _httpClient;

  String? _folderId;
  final Map<String, GoogleDriveRemoteFile> _fileCache = {};

  static GoogleDriveClient? withSavedDetails() {
    final hasAuth =
        stows.googleDriveClientId.value.isNotEmpty &&
        stows.googleDriveRefreshToken.value.isNotEmpty &&
        stows.googleDriveAccessToken.value.isNotEmpty &&
        stows.googleDriveAccessTokenExpiry.value.isNotEmpty;
    if (!hasAuth) return null;

    return GoogleDriveClient(
      clientId: stows.googleDriveClientId.value,
      clientSecret: stows.googleDriveClientSecret.value,
      accessToken: stows.googleDriveAccessToken.value,
      refreshToken: stows.googleDriveRefreshToken.value,
      accessTokenExpiresAt:
          DateTime.tryParse(stows.googleDriveAccessTokenExpiry.value)?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  Future<GoogleDriveQuota?> getStorageQuota() async {
    final json = await _requestJson(
      method: 'GET',
      uri: Uri.https('www.googleapis.com', '/drive/v3/about', {
        'fields': 'storageQuota',
      }),
    );
    final storageQuota = json['storageQuota'];
    if (storageQuota is! Map<String, dynamic>) return null;
    return GoogleDriveQuota.fromJson(storageQuota);
  }

  Future<GoogleDriveProfile> getProfile() async {
    final json = await _requestJson(
      method: 'GET',
      uri: Uri.https('www.googleapis.com', '/oauth2/v2/userinfo'),
    );
    final email = '${json['email'] ?? ''}';
    if (email.isEmpty) {
      throw const FormatException('Google profile payload did not include email.');
    }
    final pictureRaw = '${json['picture'] ?? ''}';
    return GoogleDriveProfile(
      email: email,
      displayName: json['name']?.toString(),
      pictureUrl: pictureRaw.isEmpty ? null : Uri.tryParse(pictureRaw),
    );
  }

  Future<Uint8List?> getProfilePictureBytes(Uri? pictureUrl) async {
    if (pictureUrl == null) return null;
    final response = await _request(method: 'GET', uri: pictureUrl);
    if (response.statusCode < 200 || response.statusCode >= 300) return null;
    return response.bodyBytes;
  }

  Future<String> getOrCreateAppFolderId() async {
    if (_folderId != null) return _folderId!;
    if (stows.googleDriveFolderId.value.isNotEmpty) {
      _folderId = stows.googleDriveFolderId.value;
      return _folderId!;
    }

    final escapedName = _escapeForDriveQuery(appRootDirectoryPrefix);
    final listJson = await _requestJson(
      method: 'GET',
      uri: Uri.https('www.googleapis.com', '/drive/v3/files', {
        'q':
            "name = '$escapedName' and "
            "mimeType = 'application/vnd.google-apps.folder' and "
            "'root' in parents and trashed = false",
        'fields': 'files(id,name,modifiedTime)',
        'spaces': 'drive',
        'pageSize': '10',
        'orderBy': 'modifiedTime desc',
      }),
    );

    final files = listJson['files'];
    if (files is List && files.isNotEmpty && files.first is Map<String, dynamic>) {
      _folderId = '${(files.first as Map<String, dynamic>)['id'] ?? ''}';
    }

    if (_folderId == null || _folderId!.isEmpty) {
      final createJson = await _requestJson(
        method: 'POST',
        uri: Uri.https('www.googleapis.com', '/drive/v3/files'),
        body: {
          'name': appRootDirectoryPrefix,
          'mimeType': 'application/vnd.google-apps.folder',
          'parents': ['root'],
        },
      );
      _folderId = '${createJson['id'] ?? ''}';
    }

    if (_folderId == null || _folderId!.isEmpty) {
      throw StateError('Failed to resolve Google Drive folder id.');
    }

    stows.googleDriveFolderId.value = _folderId!;
    return _folderId!;
  }

  Future<List<GoogleDriveRemoteFile>> listRemoteFiles() async {
    final folderId = await getOrCreateAppFolderId();
    final results = <GoogleDriveRemoteFile>[];
    String? nextPageToken;

    do {
      final json = await _requestJson(
        method: 'GET',
        uri: Uri.https('www.googleapis.com', '/drive/v3/files', {
          'q': "'$folderId' in parents and trashed = false",
          'fields': 'nextPageToken,files(id,name,size,modifiedTime,trashed)',
          'spaces': 'drive',
          'pageSize': '1000',
          if (nextPageToken != null) 'pageToken': nextPageToken,
        }),
      );

      final files = json['files'];
      if (files is List) {
        for (final file in files.whereType<Map<String, dynamic>>()) {
          final name = '${file['name'] ?? ''}';
          final id = '${file['id'] ?? ''}';
          if (name.isEmpty || id.isEmpty) continue;

          final remoteFile = GoogleDriveRemoteFile(
            id: id,
            name: name,
            remotePath: '$appRootDirectoryPrefix/$name',
            size: int.tryParse('${file['size'] ?? ''}'),
            lastModified: DateTime.tryParse('${file['modifiedTime'] ?? ''}')?.toUtc(),
            trashed: file['trashed'] == true,
          );
          _fileCache[remoteFile.remotePath] = remoteFile;
          results.add(remoteFile);
        }
      }
      nextPageToken = json['nextPageToken']?.toString();
    } while (nextPageToken != null && nextPageToken.isNotEmpty);

    return results;
  }

  Future<GoogleDriveRemoteFile?> getRemoteFileByRemotePath(String remotePath) async {
    final cached = _fileCache[remotePath];
    if (cached != null) return cached;

    final slashIndex = remotePath.lastIndexOf('/');
    if (slashIndex < 0 || slashIndex >= remotePath.length - 1) return null;
    final name = remotePath.substring(slashIndex + 1);
    return getRemoteFileByName(name);
  }

  Future<GoogleDriveRemoteFile?> getRemoteFileByName(String name) async {
    final folderId = await getOrCreateAppFolderId();
    final escapedName = _escapeForDriveQuery(name);

    final json = await _requestJson(
      method: 'GET',
      uri: Uri.https('www.googleapis.com', '/drive/v3/files', {
        'q': "name = '$escapedName' and '$folderId' in parents and trashed = false",
        'fields': 'files(id,name,size,modifiedTime,trashed)',
        'spaces': 'drive',
        'pageSize': '10',
        'orderBy': 'modifiedTime desc',
      }),
    );

    final files = json['files'];
    if (files is! List || files.isEmpty) return null;
    Map<String, dynamic>? file;
    for (final candidate in files) {
      if (candidate is Map<String, dynamic>) {
        file = candidate;
        break;
      }
    }
    if (file == null) return null;

    final id = '${file['id'] ?? ''}';
    final actualName = '${file['name'] ?? ''}';
    if (id.isEmpty || actualName.isEmpty) return null;

    final remoteFile = GoogleDriveRemoteFile(
      id: id,
      name: actualName,
      remotePath: '$appRootDirectoryPrefix/$actualName',
      size: int.tryParse('${file['size'] ?? ''}'),
      lastModified: DateTime.tryParse('${file['modifiedTime'] ?? ''}')?.toUtc(),
      trashed: file['trashed'] == true,
    );
    _fileCache[remoteFile.remotePath] = remoteFile;
    return remoteFile;
  }

  Future<Uint8List> downloadFileByRemotePath(String remotePath) async {
    final remoteFile = await getRemoteFileByRemotePath(remotePath);
    if (remoteFile == null) return Uint8List(0);
    return downloadFileById(remoteFile.id);
  }

  Future<Uint8List> downloadFileById(String fileId) async {
    final response = await _request(
      method: 'GET',
      uri: Uri.https('www.googleapis.com', '/drive/v3/files/$fileId', {
        'alt': 'media',
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Failed to download Google Drive file $fileId: ${response.body}');
    }
    return response.bodyBytes;
  }

  Future<void> uploadFileByRemotePath(
    String remotePath,
    Uint8List bytes, {
    required DateTime lastModified,
  }) async {
    final slashIndex = remotePath.lastIndexOf('/');
    if (slashIndex < 0 || slashIndex >= remotePath.length - 1) {
      throw FormatException('Invalid remote path: $remotePath');
    }
    final name = remotePath.substring(slashIndex + 1);
    final existing = await getRemoteFileByName(name);
    if (existing == null) {
      await _createFile(name: name, bytes: bytes, lastModified: lastModified);
    } else {
      await _updateFile(
        fileId: existing.id,
        name: name,
        bytes: bytes,
        lastModified: lastModified,
      );
    }
  }

  Future<Map<String, String>> getConfig() async {
    final remotePath = '$appRootDirectoryPrefix/$configFileName';
    final remoteFile = await getRemoteFileByRemotePath(remotePath);
    if (remoteFile == null) return {};

    final bytes = await downloadFileById(remoteFile.id);
    if (bytes.isEmpty) return {};
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) return {};
    return decoded.map((k, v) => MapEntry('$k', '$v'));
  }

  Future<void> setConfig(Map<String, String> config) async {
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(config)));
    await uploadFileByRemotePath(
      '$appRootDirectoryPrefix/$configFileName',
      bytes,
      lastModified: DateTime.now().toUtc(),
    );
  }

  Future<Map<String, String>> generateConfig({
    required Map<String, String> config,
    Encrypter? encrypter,
    IV? iv,
    Key? key,
  }) async {
    encrypter ??= this.encrypter;
    iv ??= IV.fromBase64(stows.iv.value);
    key ??= Key.fromBase64(stows.key.value);

    config[stows.key.key] = encrypter.encrypt(key.base64, iv: iv).base64;
    config[stows.iv.key] = iv.base64;
    return config;
  }

  Future<String> loadEncryptionKey({bool generateKeyIfMissing = true}) async {
    final encrypter = this.encrypter;

    final config = await getConfig();
    if (config.containsKey(stows.key.key) && config.containsKey(stows.iv.key)) {
      final iv = IV.fromBase64(config[stows.iv.key]!);
      final encryptedKey = config[stows.key.key]!;
      try {
        final key = encrypter.decrypt64(encryptedKey, iv: iv);
        stows.key.value = key;
        stows.iv.value = iv.base64;
        return key;
      } catch (_) {
        throw const FormatException('Encryption password is incorrect.');
      }
    }

    if (!generateKeyIfMissing) {
      throw const FormatException('Remote encryption config was not found.');
    }

    final key = Key.fromSecureRandom(32);
    final iv = IV.fromSecureRandom(16);
    await generateConfig(config: config, encrypter: encrypter, iv: iv, key: key);
    await setConfig(config);

    stows.key.value = key.base64;
    stows.iv.value = iv.base64;
    return key.base64;
  }

  Encrypter get encrypter {
    final encodedPassword = utf8.encode(stows.encPassword.value + reproducibleSalt);
    final hashedPasswordBytes = sha256.convert(encodedPassword).bytes;
    final passwordKey = Key(Uint8List.fromList(hashedPasswordBytes));
    return Encrypter(AES(passwordKey));
  }

  Future<void> refreshAccessTokenIfNeeded() async {
    final now = DateTime.now().toUtc();
    if (accessTokenExpiresAt.isAfter(now.add(const Duration(minutes: 1)))) return;
    await _refreshAccessToken();
  }

  Future<void> _refreshAccessToken() async {
    if (refreshToken.isEmpty) {
      throw StateError(
        'No refresh token available. Please sign in again.',
      );
    }

    final body = <String, String>{
      'client_id': clientId,
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
    };
    if (clientSecret.isNotEmpty) body['client_secret'] = clientSecret;

    final response = await _httpClient.post(
      Uri.https('oauth2.googleapis.com', '/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: body,
    );
    final decoded = jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Failed to refresh Google token: $decoded');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid token refresh response from Google.');
    }

    accessToken = '${decoded['access_token'] ?? ''}';
    final expiresIn = int.tryParse('${decoded['expires_in'] ?? 3600}') ?? 3600;
    accessTokenExpiresAt = DateTime.now().toUtc().add(Duration(seconds: expiresIn));

    stows.googleDriveAccessToken.value = accessToken;
    stows.googleDriveAccessTokenExpiry.value = accessTokenExpiresAt.toIso8601String();
  }

  Future<Map<String, dynamic>> _requestJson({
    required String method,
    required Uri uri,
    Object? body,
    Map<String, String>? headers,
  }) async {
    final response = await _request(method: method, uri: uri, body: body, headers: headers);
    final decoded = response.body.isEmpty ? {} : jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Google Drive request failed (${response.statusCode}): $decoded');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Expected JSON object response.');
    }
    return decoded;
  }

  Future<http.Response> _request({
    required String method,
    required Uri uri,
    Object? body,
    Map<String, String>? headers,
  }) async {
    await refreshAccessTokenIfNeeded();
    final allHeaders = <String, String>{
      'Authorization': 'Bearer $accessToken',
      if (headers != null) ...headers,
    };

    final request = http.Request(method, uri);
    request.headers.addAll(allHeaders);

    if (body is String) {
      request.body = body;
    } else if (body is List<int>) {
      request.bodyBytes = body;
    } else if (body is Map<String, dynamic>) {
      request.headers.putIfAbsent('Content-Type', () => 'application/json');
      request.body = jsonEncode(body);
    } else if (body is Map<String, String>) {
      request.bodyFields = body;
    } else if (body != null) {
      throw ArgumentError('Unsupported request body type: ${body.runtimeType}');
    }

    final streamed = await _httpClient.send(request);
    return http.Response.fromStream(streamed);
  }

  Future<void> _createFile({
    required String name,
    required Uint8List bytes,
    required DateTime lastModified,
  }) async {
    final folderId = await getOrCreateAppFolderId();
    final metadata = <String, dynamic>{
      'name': name,
      'parents': [folderId],
      'modifiedTime': lastModified.toUtc().toIso8601String(),
    };
    final response = await _multipartUpload(
      uri: Uri.https('www.googleapis.com', '/upload/drive/v3/files', {
        'uploadType': 'multipart',
        'fields': 'id,name,size,modifiedTime,trashed',
      }),
      metadata: metadata,
      bytes: bytes,
    );
    _cacheFileFromUploadResponse(response);
  }

  Future<void> _updateFile({
    required String fileId,
    required String name,
    required Uint8List bytes,
    required DateTime lastModified,
  }) async {
    final metadata = <String, dynamic>{
      'name': name,
      'modifiedTime': lastModified.toUtc().toIso8601String(),
    };
    final response = await _multipartUpload(
      uri: Uri.https('www.googleapis.com', '/upload/drive/v3/files/$fileId', {
        'uploadType': 'multipart',
        'fields': 'id,name,size,modifiedTime,trashed',
      }),
      metadata: metadata,
      bytes: bytes,
      method: 'PATCH',
    );
    _cacheFileFromUploadResponse(response);
  }

  Future<Map<String, dynamic>> _multipartUpload({
    required Uri uri,
    required Map<String, dynamic> metadata,
    required Uint8List bytes,
    String method = 'POST',
  }) async {
    await refreshAccessTokenIfNeeded();

    final boundary = '----saberBoundary${DateTime.now().microsecondsSinceEpoch}';
    final metadataJson = jsonEncode(metadata);
    final bodyBuilder = BytesBuilder(copy: false)
      ..add(utf8.encode('--$boundary\r\n'))
      ..add(utf8.encode('Content-Type: application/json; charset=UTF-8\r\n\r\n'))
      ..add(utf8.encode(metadataJson))
      ..add(utf8.encode('\r\n--$boundary\r\n'))
      ..add(utf8.encode('Content-Type: application/octet-stream\r\n\r\n'))
      ..add(bytes)
      ..add(utf8.encode('\r\n--$boundary--\r\n'));

    final request = http.Request(method, uri)
      ..headers['Authorization'] = 'Bearer $accessToken'
      ..headers['Content-Type'] = 'multipart/related; boundary=$boundary'
      ..bodyBytes = bodyBuilder.takeBytes();

    final streamed = await _httpClient.send(request);
    final response = await http.Response.fromStream(streamed);
    final decoded = response.body.isEmpty ? {} : jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Google Drive upload failed (${response.statusCode}): $decoded');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Upload response was not a JSON object.');
    }
    return decoded;
  }

  void _cacheFileFromUploadResponse(Map<String, dynamic> json) {
    final id = '${json['id'] ?? ''}';
    final name = '${json['name'] ?? ''}';
    if (id.isEmpty || name.isEmpty) return;

    final remoteFile = GoogleDriveRemoteFile(
      id: id,
      name: name,
      remotePath: '$appRootDirectoryPrefix/$name',
      size: int.tryParse('${json['size'] ?? ''}'),
      lastModified: DateTime.tryParse('${json['modifiedTime'] ?? ''}')?.toUtc(),
      trashed: json['trashed'] == true,
    );
    _fileCache[remoteFile.remotePath] = remoteFile;
  }

  static String _escapeForDriveQuery(String text) =>
      text.replaceAll('\\', '\\\\').replaceAll("'", "\\'");
}
