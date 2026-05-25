import 'dart:async';
import 'dart:io';

import 'package:abstract_sync/abstract_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/google_drive/saber_syncer.dart';
import 'package:saber/data/google_drive/google_drive_client.dart';
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

void main() {
  test(
    'Test deleting a file and syncing it',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      HttpOverrides.global = null; // enable http requests in test
      setupMockPathProvider();
      setupMockFlutterSecureStorage();
      SharedPreferences.setMockInitialValues({});

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

      final client = GoogleDriveClient.withSavedDetails()!;
      await client.loadEncryptionKey();

      // Use a random file name to avoid conflicts with simultaneous tests
      final filePathLocal = '/test.deletion.${randomString(10)}';
      printOnFailure('File path local: $filePathLocal');

      const fileContent = <int>[1, 2, 3];
      final syncFile = await const SaberSyncInterface()
          .getSyncFileFromLocalFile(FileManager.getFile(filePathLocal));

      // Create a file (to delete later)
      await FileManager.writeFile(
        filePathLocal,
        fileContent,
        awaitWrite: true,
        alsoUpload: false,
      );

      // Upload file to Google Drive
      syncer.uploader.clearPending();
      syncer.uploader.enqueue(syncFile: syncFile);
      await syncer.uploader.waitUntilEmpty();

      // Check that the file exists on Google Drive
      printOnFailure(
        'Checking if ${syncFile.remotePath} exists on Google Drive',
      );
      final uploadedFile = await syncer.interface.getRemoteFile(
        syncFile.remotePath,
      );
      expect(
        uploadedFile,
        isNotNull,
        reason: 'File should exist on Google Drive',
      );

      // Delete the file
      FileManager.deleteFile(filePathLocal, alsoUpload: false);

      // Upload deletion marker to Google Drive
      syncer.uploader.clearPending();
      syncer.uploader.enqueue(syncFile: syncFile);
      await syncer.uploader.waitUntilEmpty();

      // Check that the file is now a deletion marker (0 bytes)
      final remoteAfterDelete = await syncer.interface.getRemoteFile(
        syncFile.remotePath,
        useCache: false,
      );
      expect(
        remoteAfterDelete?.size ?? -1,
        0,
        reason: 'File should be empty on Google Drive',
      );

      // Sync the file from Google Drive
      syncFile.remoteFile = remoteAfterDelete;
      syncer.downloader.clearPending();
      syncer.downloader.enqueue(syncFile: syncFile);
      await syncer.downloader.waitUntilEmpty();

      // Check that the file is deleted locally
      final exists = FileManager.doesFileExist(filePathLocal);
      expect(exists, false, reason: 'File is not deleted locally');
    },
    retry: 2,
    skip: !_hasRequiredEnv(),
  );
}

extension on SyncerComponent {
  Future<void> waitUntilEmpty() async {
    if (numPending <= 0) return;

    final completer = Completer<void>();
    late final StreamSubscription subscription;
    subscription = queueStream.listen((event) {
      if (numPending > 0) return;
      subscription.cancel();
      if (!completer.isCompleted) completer.complete();
    });
    return completer.future;
  }
}
