@echo off
chcp 65001 >nul

echo ========================================
echo    Saber Build Script (Windows + Android)
echo ========================================
echo.

echo [1/4] Enabling Windows desktop support...
call flutter config --enable-windows-desktop
echo.

echo [2/4] Getting dependencies...
call flutter pub get
if errorlevel 1 (
    echo Pub get FAILED!
    exit /b 1
)
echo.

echo [3/4] Building Windows (Release)...
call flutter build windows --release --no-pub
if errorlevel 1 (
    echo Windows build FAILED!
    exit /b 1
)
echo Windows build SUCCESS!
echo.

echo [4/4] Building Android (Signed Release APK)...
REM Delete stale GeneratedPluginRegistrant to fix integration_test error
if exist "android\app\src\main\java\io\flutter\plugins\GeneratedPluginRegistrant.java" (
    del "android\app\src\main\java\io\flutter\plugins\GeneratedPluginRegistrant.java"
)
call flutter build apk --release --no-pub
if errorlevel 1 (
    echo Android signed release build FAILED!
    exit /b 1
)
echo Android signed release build SUCCESS!
echo.

echo ========================================
echo           Build Complete!
echo ========================================
echo.
echo Windows:  build\windows\x64\runner\Release\saber.exe
echo Android:  build\app\outputs\apk\release\app-release.apk
echo.
exit /b 0