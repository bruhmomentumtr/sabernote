# <img src="https://github.com/saber-notes/saber/raw/main/assets/icon/icon.png" width="30" height="30" alt="Logo"> SaberNote

> **[saber-notes/saber](https://github.com/saber-notes/saber) fork'u — Nextcloud yerine Google Drive entegrasyonu.**

El yazısı not uygulaması Saber'ın, Google Drive ile senkronizasyon desteği eklenmiş topluluk fork'u.

## ✨ Bu fork'ta ne farklı?

| Özellik | Upstream Saber | Bu Fork |
|---------|---------------|---------|
| Bulut senkronizasyon | Nextcloud | **Google Drive** |
| Kimlik doğrulama | Nextcloud login | **Google OAuth2 (PKCE)** |
| Windows | ✅ | ✅ |
| Android | ✅ | ✅ Chrome Custom Tab ile native login |
| Linux | ✅ | ✅ |
| Firebase gerekli mi? | — | **Hayır** |

## 🚀 Kurulum

### Hazır Build İndir

[Releases](../../releases) sayfasından platformuna uygun dosyayı indir:

| Platform | Dosya |
|----------|-------|
| Windows | `SaberNote-Windows.zip` |
| Android | `SaberNote-Android.apk` |
| Linux | `SaberNote-Linux.tar.gz` |

### Kaynaktan Derleme

```bash
# Bağımlılıkları yükle
flutter pub get

# Windows
flutter build windows --release

# Android
flutter build apk --release

# Linux
flutter build linux --release
```

Windows + Android tek seferde:
```bash
# Windows'ta
build_all.bat
```

## 🔑 Google Drive Kurulumu

### 1. OAuth Credentials Oluştur

1. [Google Cloud Console](https://console.cloud.google.com/) → APIs & Services → Credentials
2. **OAuth 2.0 Client ID** oluştur → Tip: **Desktop app**
3. **Google Drive API**'yi etkinleştir (APIs & Services → Library → Google Drive API)
4. Client ID ve Client Secret'ı not al

### 2. Uygulamada Giriş Yap

1. Uygulamayı aç → Ayarlar → Giriş Yap
2. Client ID ve Client Secret'ı gir
3. **"Sign in with Google"** butonuna bas
4. Google hesabını seç ve izin ver

> **Not:** Aynı OAuth credentials hem Windows hem Android'de çalışır. Firebase veya `google-services.json` gerekmez.

### Android'de Nasıl Çalışır?

Android'de `localhost` redirect çalışmadığı için **Chrome Custom Tab** kullanılır:
- `flutter_web_auth_2` paketi ile Chrome Custom Tab açılır
- OAuth callback, reverse-client-ID scheme ile uygulamaya geri döner
- Tam refresh token desteği (native Google Sign-In SDK'sından farklı olarak)

## 🏗️ CI/CD

GitHub Actions ile otomatik build:

| Workflow | Açıklama | Tetikleyici |
|----------|----------|-------------|
| `build.yml` | Android + Windows + Linux | Push to main, manuel |
| Diğerleri (`[Legacy]`) | Upstream'den kalan workflow'lar | Sadece manuel |

### GitHub Secrets (Opsiyonel — İmzalı APK için)

| Secret | Açıklama |
|--------|----------|
| `ANDROID_KEYSTORE_BASE64` | Keystore dosyasının base64 hali |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore şifresi |
| `ANDROID_KEY_PASSWORD` | Key şifresi |
| `ANDROID_KEYSTORE_ALIAS` | Key alias |

Keystore oluşturmak için: `keystoreb64creator.ps1`

## 📁 Proje Yapısı (Değişen Dosyalar)

```
lib/
├── data/google_drive/
│   ├── login_flow.dart          # OAuth2 PKCE akışı (Desktop + Mobile)
│   ├── google_drive_client.dart # Drive API istemcisi + token yenileme
│   ├── google_drive_models.dart # Veri modelleri
│   └── saber_syncer.dart        # Senkronizasyon mantığı
├── components/cloud/
│   └── nc_login_step.dart       # Giriş ekranı UI
└── data/prefs.dart              # Kullanıcı tercihleri

android/app/src/main/AndroidManifest.xml  # OAuth callback scheme
```

## 🔗 Bağlantılar

- [Upstream Saber](https://github.com/saber-notes/saber)
- [Lisans](LICENSE.md)
- [Gizlilik Politikası](privacy_policy.md)

## 📝 Lisans

Bu proje, upstream Saber ile aynı lisans altındadır. Detaylar için [LICENSE.md](LICENSE.md) dosyasına bakın.
