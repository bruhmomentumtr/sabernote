import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/google_drive/saber_syncer.dart';
import 'package:saber/data/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/test_mock_channel_handlers.dart';
import 'utils/test_random.dart';

const _envClientId = 'SABER_GDRIVE_CLIENT_ID';
const _envClientSecret = 'SABER_GDRIVE_CLIENT_SECRET';
const _envRefreshToken = 'SABER_GDRIVE_REFRESH_TOKEN';
const _envAccessToken = 'SABER_GDRIVE_ACCESS_TOKEN';
const _envAccessTokenExpiry = 'SABER_GDRIVE_ACCESS_TOKEN_EXPIRY';
const _envEmail = 'SABER_GDRIVE_EMAIL';
const _envEncPassword = 'SABER_GDRIVE_ENC_PASSWORD';

bool _hasRequiredEnv() {
  final env = Platform.environment;
  return env[_envClientId]?.isNotEmpty == true &&
      env[_envRefreshToken]?.isNotEmpty == true &&
      env[_envAccessToken]?.isNotEmpty == true &&
      env[_envAccessTokenExpiry]?.isNotEmpty == true &&
      env[_envEmail]?.isNotEmpty == true &&
      env[_envEncPassword]?.isNotEmpty == true;
}

void main() async {
  test(
    'Upload and download file',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      HttpOverrides.global = null; // enable http requests in test
      setupMockPathProvider();
      setupMockFlutterSecureStorage();
      SharedPreferences.setMockInitialValues({});

      FileManager.documentsDirectory =
          '$tmpDir/nc_upload_download_test/'
          '${FileManager.appRootDirectoryPrefix}';
      FlavorConfig.setup();
      await FileManager.init();

      final env = Platform.environment;
      stows.username.value = env[_envEmail]!;
      stows.googleDriveClientId.value = env[_envClientId]!;
      stows.googleDriveClientSecret.value = env[_envClientSecret] ?? '';
      stows.googleDriveRefreshToken.value = env[_envRefreshToken]!;
      stows.googleDriveAccessToken.value = env[_envAccessToken]!;
      stows.googleDriveAccessTokenExpiry.value = env[_envAccessTokenExpiry]!;
      stows.encPassword.value = env[_envEncPassword]!;

      final client = SaberSyncInterface.client!;
      await client.loadEncryptionKey();

      final localFile = FileManager.getFile(
        '/helloworld${randomString(10)}.txt',
      );
      final syncFile = await syncer.interface.getSyncFileFromLocalFile(
        localFile,
      );
      printOnFailure(syncFile.toString());
      expect(
        syncFile.remotePath,
        matches(RegExp(r'^Saber/[a-zA-Z0-9]+\.sbe$')),
      );

      // Create local file
      const content = 'Hello, world!';
      await localFile.create(recursive: true);
      await localFile.writeAsString(content);

      // Upload
      final upBytes = await syncer.interface.readLocalFile(syncFile);
      expect(upBytes.length, greaterThan(0));
      await syncer.interface.uploadRemoteFile(syncFile, upBytes);

      // Get the sync file again, this time starting with the remote file
      final remoteFile = await syncer.interface.getRemoteFile(
        syncFile.remotePath,
      );
      if (remoteFile == null) fail('Remote file not found after upload');
      final syncFile2 = await syncer.interface.getSyncFileFromRemoteFile(
        remoteFile,
      );
      expect(syncFile2, equals(syncFile));

      // Download
      final downBytes = await syncer.interface.downloadRemoteFile(syncFile);
      expect(downBytes.length, greaterThan(0));
      expect(downBytes, equals(upBytes));
      await syncer.interface.writeLocalFile(
        syncFile,
        downBytes,
        awaitWrite: true,
      );
      expect(await localFile.readAsString(), equals(content));
    },
    retry: 2,
    skip: !_hasRequiredEnv(),
  );
}
