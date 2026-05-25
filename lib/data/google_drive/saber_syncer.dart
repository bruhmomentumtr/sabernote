/// 🤖 Generated wholely or partially with GPT-5 Codex; OpenAI
library;

import 'dart:convert';
import 'dart:io';

import 'package:abstract_sync/abstract_sync.dart';
import 'package:encrypt/encrypt.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/google_drive/google_drive_client.dart';
import 'package:saber/data/google_drive/google_drive_models.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/pages/editor/editor.dart';
import 'package:worker_manager/worker_manager.dart';

final syncer =
    Syncer<SaberSyncInterface, SaberSyncFile, File, GoogleDriveRemoteFile>(
      const SaberSyncInterface(),
      failureTimeout: const Duration(seconds: 4),
    );

class SaberSyncInterface
    extends AbstractSyncInterface<SaberSyncFile, File, GoogleDriveRemoteFile> {
  const SaberSyncInterface();

  static final log = Logger('SaberSyncInterface');

  @override
  bool areRemoteFilesEqual(GoogleDriveRemoteFile a, GoogleDriveRemoteFile b) =>
      a.id == b.id;

  @override
  bool areLocalFilesEqual(File a, File b) => a.path == b.path;

  @override
  Future<List<SaberSyncFile>> findLocalChanges() async {
    for (var tries = 0; tries < 10 && remoteFiles.isEmpty; ++tries) {
      await Future.delayed(const Duration(milliseconds: 200));
    }

    final syncFiles = <SaberSyncFile>[];
    await for (final localFile in FileManager.getRootDirectory().list(
      recursive: true,
    )) {
      if (localFile is! File) continue;

      final syncFile = await getSyncFileFromLocalFile(localFile);
      final bestFile = await getBestFile(
        syncFile,
        onLocalFileNotFound: .local,
        onEqualFiles: .remote,
      );
      switch (bestFile) {
        case .local:
          syncFiles.add(syncFile);
        case .remote:
          break;
      }
    }
    return syncFiles;
  }

  @override
  Future<List<SaberSyncFile>> findRemoteChanges() async {
    final client = SaberSyncInterface.client;
    if (client == null) return const [];

    remoteFiles = await findRemoteFiles();
    if (remoteFiles.isEmpty) return const [];

    final changedFiles = await Future.wait(
      remoteFiles.map((remoteFile) async {
        final SaberSyncFile syncFile;
        try {
          syncFile = await getSyncFileFromRemoteFile(remoteFile);
        } catch (e, st) {
          log.warning('Failed to map remote file to local file: $e', e, st);
          return null;
        }

        final bestFile = await getBestFile(
          syncFile,
          onLocalFileNotFound: .remote,
          onEqualFiles: .local,
        );
        switch (bestFile) {
          case .local:
            return null;
          case .remote:
            final remotelyDeleted = syncFile.remoteFile?.isDeletedMarker ?? false;
            final locallyDeleted = stows.fileSyncAlreadyDeleted.value.contains(
              syncFile.relativeLocalPath,
            );
            if (remotelyDeleted && locallyDeleted) break;
            return syncFile;
        }
      }),
    ).then((list) => list.nonNulls.toList());

    // Prioritize preview file updates before the main note.
    final previewSyncFiles = changedFiles
        .where((syncFile) => syncFile.localFile.path.endsWith('.p'))
        .toList(growable: false);
    for (final previewSyncFile in previewSyncFiles) {
      final previewSyncFileIndex = changedFiles.indexOf(previewSyncFile);
      final mainSyncFileIndex = changedFiles.indexWhere(
        (syncFile) =>
            syncFile.localFile.path ==
            previewSyncFile.localFile.path.substring(
              0,
              previewSyncFile.localFile.path.length - 2,
            ),
      );
      if (previewSyncFileIndex <= -1 || mainSyncFileIndex <= -1) continue;

      if (previewSyncFileIndex >= mainSyncFileIndex) {
        changedFiles
          ..removeAt(previewSyncFileIndex)
          ..insert(mainSyncFileIndex, previewSyncFile);
      } else {
        changedFiles
          ..removeAt(previewSyncFileIndex)
          ..insert(mainSyncFileIndex - 1, previewSyncFile);
      }
    }

    return changedFiles;
  }

  @override
  Future<SaberSyncFile> getSyncFileFromLocalFile(File localFile) async {
    final relativePath = localFile.path
        .substring(FileManager.documentsDirectory.length)
        .replaceAll(Platform.pathSeparator, '/');

    assert(relativePath.startsWith('/'));
    final encryptedName = await encryptPath(client, relativePath);
    final remotePath =
        '${FileManager.appRootDirectoryPrefix}/$encryptedName$encExtension';

    final remoteFile = await getRemoteFile(remotePath);
    return SaberSyncFile(
      remoteFile: remoteFile,
      remotePath: remotePath,
      localFile: localFile,
    );
  }

  @override
  Future<SaberSyncFile> getSyncFileFromRemoteFile(
    GoogleDriveRemoteFile remoteFile,
  ) async {
    final relativeLocalPath = await decryptPath(client, remoteFile.remotePath);
    if (relativeLocalPath == null) {
      throw Exception('Decryption failed for ${remoteFile.remotePath}');
    }
    final localFile = FileManager.getFile(relativeLocalPath);
    return SaberSyncFile(remoteFile: remoteFile, localFile: localFile);
  }

  @override
  Future<Uint8List> downloadRemoteFile(SaberSyncFile file) async {
    if (file.localFile.path.endsWith(GoogleDriveClient.configFileName)) {
      try {
        await _client!.loadEncryptionKey(generateKeyIfMissing: false);
      } catch (_) {
        stows.encPassword.value = '';
        stows.key.value = '';
        stows.iv.value = '';
      }
      return Uint8List(0);
    } else if (file.remoteFile?.isDeletedMarker ?? false) {
      return Uint8List(0);
    }

    final client = SaberSyncInterface.client;
    if (client == null) {
      throw Exception('Tried to download file without logging in.');
    }
    return client.downloadFileByRemotePath(file.remotePath);
  }

  @override
  Future<void> writeLocalFile(
    SaberSyncFile file,
    Uint8List encryptedBytes, {
    @visibleForTesting bool awaitWrite = false,
  }) async {
    if (file.localFile.path.endsWith(GoogleDriveClient.configFileName)) {
      return;
    }

    if (encryptedBytes.isEmpty) {
      await FileManager.deleteFile(file.relativeLocalPath, alsoUpload: false);
      stows.fileSyncAlreadyDeleted.value.add(file.relativeLocalPath);
      stows.fileSyncAlreadyDeleted.notifyListeners();
      return;
    }

    final client = SaberSyncInterface.client;
    if (client == null) {
      throw Exception('Tried to decrypt file without logging in.');
    }

    final encrypter = client.encrypter;
    final iv = IV.fromBase64(stows.iv.value);

    final decryptedData = await workerManager.execute(
      file.localFile.path.endsWith(Editor.extensionOldJson)
          ? () async {
              final encrypted = utf8.decode(encryptedBytes.cast<int>());
              final decrypted = encrypter.decrypt64(encrypted, iv: iv);
              return utf8.encode(decrypted);
            }
          : () async {
              final encrypted = Encrypted(encryptedBytes);
              final decrypted = encrypter.decryptBytes(encrypted, iv: iv);
              return Uint8List.fromList(decrypted);
            },
      priority: WorkPriority.highRegular,
    );

    await FileManager.writeFile(
      file.relativeLocalPath,
      decryptedData,
      awaitWrite: awaitWrite,
      alsoUpload: false,
      lastModified: file.remoteFile?.lastModified,
    );
  }

  @override
  Future<Uint8List> readLocalFile(SaberSyncFile file) async {
    final decryptedBytes = file.localFile.existsSync()
        ? await file.localFile.readAsBytes()
        : Uint8List(0);
    if (decryptedBytes.isEmpty) return decryptedBytes;

    final client = SaberSyncInterface.client;
    if (client == null) {
      throw Exception('Tried to encrypt file without logging in.');
    }

    final encrypter = client.encrypter;
    final iv = IV.fromBase64(stows.iv.value);

    final encryptedData = await workerManager.execute(
      file.localFile.path.endsWith(Editor.extensionOldJson)
          ? () async {
              final decrypted = utf8.decode(decryptedBytes);
              final encrypted = encrypter.encrypt(decrypted, iv: iv);
              return utf8.encode(encrypted.base64);
            }
          : () async {
              final encrypted = encrypter.encryptBytes(decryptedBytes, iv: iv);
              return encrypted.bytes;
            },
      priority: WorkPriority.highRegular,
    );

    return encryptedData;
  }

  @override
  Future<void> uploadRemoteFile(SaberSyncFile file, Uint8List encryptedBytes) async {
    DateTime lastModified;
    try {
      lastModified = file.localFile.lastModifiedSync();
    } on FileSystemException {
      lastModified = DateTime.now();
    }
    if (lastModified.isBefore(stows.fileSyncResyncEverythingDate.value)) {
      lastModified = stows.fileSyncResyncEverythingDate.value;
    }

    final client = SaberSyncInterface.client;
    if (client == null) {
      throw Exception('Tried to upload file without logging in.');
    }

    await client.uploadFileByRemotePath(
      file.remotePath,
      encryptedBytes,
      lastModified: lastModified,
    );
  }

  static GoogleDriveClient? _client;
  static GoogleDriveClient? get client {
    _client ??= GoogleDriveClient.withSavedDetails();
    return _client;
  }

  static var remoteFiles = <GoogleDriveRemoteFile>{};

  static final _encryptMap = <String, String>{};
  static final _decryptMap = <String, String>{};

  static Future<Set<GoogleDriveRemoteFile>> findRemoteFiles() async {
    final client = SaberSyncInterface.client;
    if (client == null) return {};
    try {
      final files = await client.listRemoteFiles();
      return files.toSet();
    } on SocketException catch (e, st) {
      log.warning('findRemoteFiles: Network error: $e', e, st);
      return {};
    } catch (e, st) {
      log.severe('findRemoteFiles: Unknown error: $e', e, st);
      if (kDebugMode) rethrow;
      return {};
    }
  }

  static Future<String> encryptPath(GoogleDriveClient? client, String path) async {
    if (_encryptMap.containsKey(path)) return _encryptMap[path]!;
    if (client == null) {
      throw Exception('Tried to encrypt path without logging in.');
    }

    final encrypter = client.encrypter;
    final iv = IV.fromBase64(stows.iv.value);

    final encrypted = await workerManager.execute(
      () => encrypter.encrypt(path, iv: iv).base16,
      priority: WorkPriority.veryHigh,
    );

    _encryptMap[path] = encrypted;
    _decryptMap[encrypted] = path;
    return encrypted;
  }

  static Future<String?> decryptPath(GoogleDriveClient? client, String path) async {
    if (_ignoredFiles.any(path.endsWith)) return null;

    final String encryptedName;
    if (path.endsWith(encExtension)) {
      encryptedName = path.substring(
        path.lastIndexOf('/') + 1,
        path.length - encExtension.length,
      );
    } else if (path.endsWith('/${GoogleDriveClient.configFileName}')) {
      return '/${GoogleDriveClient.configFileName}';
    } else {
      log.info('remote file not in recognised encrypted format: $path');
      return null;
    }

    if (_decryptMap.containsKey(encryptedName)) return _decryptMap[encryptedName]!;
    if (client == null) {
      throw Exception('Tried to decrypt path without logging in.');
    }

    final encrypter = client.encrypter;
    final iv = IV.fromBase64(stows.iv.value);

    var decrypted = await workerManager.execute(
      () => encrypter.decrypt16(encryptedName, iv: iv),
      priority: WorkPriority.veryHigh,
    );

    if (decrypted.startsWith('null/')) {
      decrypted = decrypted.substring('null/'.length - 1);
    }

    _encryptMap[decrypted] = encryptedName;
    _decryptMap[encryptedName] = decrypted;
    return decrypted;
  }

  static Future<BestFile> getBestFile(
    SaberSyncFile file, {
    required BestFile onLocalFileNotFound,
    required BestFile onEqualFiles,
  }) async {
    if (!file.localFile.existsSync()) {
      return onLocalFileNotFound;
    }

    file.remoteFile ??= await _getRemoteFileStatic(file.remotePath, useCache: false);
    if (file.remoteFile == null) {
      return .local;
    }

    final lastModifiedRemote = file.remoteFile!.lastModified;
    if (lastModifiedRemote == null) {
      return .local;
    } else if (lastModifiedRemote.isBefore(stows.fileSyncResyncEverythingDate.value)) {
      return .local;
    }

    final lastModifiedLocal = file.localFile.lastModifiedSync();
    if (lastModifiedRemote.difference(lastModifiedLocal).abs() <
        const Duration(milliseconds: 500)) {
      return onEqualFiles;
    } else if (lastModifiedRemote.isAfter(lastModifiedLocal)) {
      return .remote;
    } else {
      return .local;
    }
  }

  Future<GoogleDriveRemoteFile?> getRemoteFile(
    String remotePath, {
    bool useCache = true,
  }) => _getRemoteFileStatic(remotePath, useCache: useCache);

  static Future<GoogleDriveRemoteFile?> _getRemoteFileStatic(
    String remotePath, {
    bool useCache = true,
  }) async {
    GoogleDriveRemoteFile? remoteFile;
    try {
      remoteFile = remoteFiles.firstWhere(
        (candidate) => candidate.remotePath == remotePath,
      );
      if (useCache) return remoteFile;
    } on StateError {
      log.fine('Remote file not cached for $remotePath');
    }

    remoteFile = await _getRemoteFileUncached(remotePath) ?? remoteFile;
    if (remoteFile != null) remoteFiles.add(remoteFile);
    return remoteFile;
  }

  static Future<GoogleDriveRemoteFile?> _getRemoteFileUncached(
    String remotePath,
  ) async {
    final client = SaberSyncInterface.client;
    if (client == null) return null;
    try {
      return await client.getRemoteFileByRemotePath(remotePath);
    } catch (e, st) {
      log.fine('Remote file not found for $remotePath: $e', e, st);
      return null;
    }
  }

  static const encExtension = '.sbe';
  static const _ignoredFiles = <String>['/Readme.md'];
}

class SaberSyncFile extends AbstractSyncFile<File, GoogleDriveRemoteFile> {
  late final relativeLocalPath = localFile.path.substring(
    FileManager.documentsDirectory.length,
  );

  late String remotePath;

  SaberSyncFile({
    required super.remoteFile,
    String? remotePath,
    required super.localFile,
  }) : assert(
         remotePath != null || remoteFile != null,
         'At least one of remotePath or remoteFile must be provided',
       ) {
    this.remotePath = remotePath ?? remoteFile!.remotePath;
  }

  static Future<SaberSyncFile> relative(String relativeFilePath) {
    final localFile = FileManager.getFile(relativeFilePath);
    return const SaberSyncInterface().getSyncFileFromLocalFile(localFile);
  }

  @override
  String toString() =>
      'SaberSyncFile(local: $relativeLocalPath, remote: $remotePath)';

  @override
  bool operator ==(Object other) =>
      other is SaberSyncFile && other.localFile.path == localFile.path;

  @override
  int get hashCode => localFile.path.hashCode;
}

extension SaberSyncerComponent on SyncerComponent {
  Future<bool> enqueueRel(String relativeFilePath) async {
    if (!stows.loggedIn) return false;

    final syncFile = await SaberSyncFile.relative(relativeFilePath);
    return enqueue(syncFile: syncFile);
  }
}

enum BestFile { local, remote }
