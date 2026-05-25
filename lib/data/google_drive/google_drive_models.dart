/// 🤖 Generated wholely or partially with GPT-5 Codex; OpenAI
library;

class GoogleDriveQuota {
  const GoogleDriveQuota({
    required this.limit,
    required this.usage,
    required this.usageInDrive,
  });

  final int limit;
  final int usage;
  final int usageInDrive;

  int get used => usageInDrive;
  int get total => limit;
  int get free => (limit - usageInDrive).clamp(0, limit).toInt();
  double get relative => limit <= 0 ? 0 : (usageInDrive / limit) * 100;

  Map<String, Object?> toJson() => {
    'limit': limit,
    'usage': usage,
    'usageInDrive': usageInDrive,
  };

  factory GoogleDriveQuota.fromJson(Map<String, dynamic> json) {
    return GoogleDriveQuota(
      limit: int.tryParse('${json['limit'] ?? 0}') ?? 0,
      usage: int.tryParse('${json['usage'] ?? 0}') ?? 0,
      usageInDrive: int.tryParse('${json['usageInDrive'] ?? 0}') ?? 0,
    );
  }
}

class GoogleDriveRemoteFile {
  const GoogleDriveRemoteFile({
    required this.id,
    required this.name,
    required this.remotePath,
    this.size,
    this.lastModified,
    this.trashed = false,
  });

  final String id;
  final String name;
  final String remotePath;
  final int? size;
  final DateTime? lastModified;
  final bool trashed;

  bool get isDeletedMarker => (size ?? 0) <= 0;
}

class GoogleDriveProfile {
  const GoogleDriveProfile({
    required this.email,
    this.displayName,
    this.pictureUrl,
  });

  final String email;
  final String? displayName;
  final Uri? pictureUrl;
}
