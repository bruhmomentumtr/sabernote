@echo off
chcp 65001 >nul

echo ========================================
echo    Saber Build Script (Windows + Android)
echo ========================================
echo.

REM --------------------------------------------------
REM 1. Pre-build cleanup
REM --------------------------------------------------
echo [1/6] Pre-build cleanup...

REM Stop stale Gradle daemons to avoid file lock errors
if exist "android\gradlew.bat" (
    echo   Stopping Gradle daemons...
    pushd android
    call gradlew.bat --stop 2>nul
    popd
    timeout /t 3 /nobreak >nul
)

REM Clear lint cache to prevent FileSystemException locks
if exist "build\app\intermediates\lint-cache" (
    echo   Clearing lint cache...
    rmdir /s /q "build\app\intermediates\lint-cache" 2>nul
)

REM Delete stale GeneratedPluginRegistrant to fix integration_test error
if exist "android\app\src\main\java\io\flutter\plugins\GeneratedPluginRegistrant.java" (
    echo   Removing stale GeneratedPluginRegistrant...
    del "android\app\src\main\java\io\flutter\plugins\GeneratedPluginRegistrant.java"
)
echo.

REM --------------------------------------------------
REM 2. Enable Windows desktop
REM --------------------------------------------------
echo [2/6] Enabling Windows desktop support...
call flutter config --enable-windows-desktop
echo.

REM --------------------------------------------------
REM 3. Dependencies
REM --------------------------------------------------
echo [3/6] Getting dependencies...
call flutter pub get
if errorlevel 1 (
    echo Pub get FAILED!
    exit /b 1
)
echo.

REM --------------------------------------------------
REM 4. Build Windows
REM --------------------------------------------------
echo [4/6] Building Windows (Release)...
call flutter build windows --release --no-pub
if errorlevel 1 (
    echo Windows build FAILED!
    exit /b 1
)
echo Windows build SUCCESS!
echo.

REM --------------------------------------------------
REM 5. Build Android
REM --------------------------------------------------
echo [5/6] Building Android (Signed Release APK)...
call flutter build apk --release --no-pub
if errorlevel 1 (
    echo.
    echo   Android build failed, retrying after clean...
    call flutter clean
    call flutter pub get
    call flutter build apk --release --no-pub
    if errorlevel 1 (
        echo Android signed release build FAILED!
        exit /b 1
    )
)
echo Android signed release build SUCCESS!
echo.

REM --------------------------------------------------
REM 6. Done
REM --------------------------------------------------
echo [6/6] Post-build cleanup...
pushd android
call gradlew.bat --stop 2>nul
popd

echo.
echo ========================================
echo           Build Complete!
echo ========================================
echo.
echo Windows:  build\windows\x64\runner\Release\saber.exe
echo Android:  build\app\outputs\flutter-apk\app-release.apk
echo.
exit /b 0