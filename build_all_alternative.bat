@echo off
chcp 65001 >nul

echo ===================================================
echo   Saber Alternative Build Script (Original Release Keys)
echo ===================================================
echo.

set RESTORE_KEY=0

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
REM 2. Switch to Original Release Keys
REM --------------------------------------------------
echo [2/6] Temporarily switching to original release key...
if exist "android\key.properties" (
    echo   Backing up custom key.properties...
    ren "android\key.properties" "key.properties.bak"
    set RESTORE_KEY=1
) else (
    echo   No custom key.properties found. Gradle will use fallback-key.properties automatically.
)
echo.

REM --------------------------------------------------
REM 3. Dependencies
REM --------------------------------------------------
echo [3/6] Getting dependencies...
call flutter pub get
if errorlevel 1 (
    echo Pub get FAILED!
    goto cleanup_failed
)
echo.

REM --------------------------------------------------
REM 4. Build Windows
REM --------------------------------------------------
echo [4/6] Building Windows (Release)...
call flutter build windows --release --tree-shake-icons
if errorlevel 1 (
    echo Windows build FAILED!
    goto cleanup_failed
)
echo Windows build SUCCESS!
echo.

REM --------------------------------------------------
REM 5. Build Android
REM --------------------------------------------------
echo [5/6] Building Android (Original Signed Release APK)...
call flutter build apk --release --obfuscate --split-debug-info=build/debug-info --tree-shake-icons
if errorlevel 1 (
    echo.
    echo   Android build failed, retrying after clean...
    call flutter clean
    call flutter pub get
    call flutter build apk --release --obfuscate --split-debug-info=build/debug-info --tree-shake-icons
    if errorlevel 1 (
        echo Android signed release build FAILED!
        goto cleanup_failed
    )
)
echo Android signed release build SUCCESS!
echo.

REM --------------------------------------------------
REM 6. Done & Restore
REM --------------------------------------------------
:cleanup_success
echo [6/6] Post-build cleanup...
pushd android
call gradlew.bat --stop 2>nul
popd

if "%RESTORE_KEY%"=="1" (
    echo   Restoring custom key.properties...
    ren "android\key.properties.bak" "key.properties"
    set RESTORE_KEY=0
)

echo.
echo ========================================
echo           Build Complete!
echo ========================================
echo.
echo Windows:  build\windows\x64\runner\Release\saber.exe
echo Android:  build\app\outputs\flutter-apk\app-release.apk
echo.
exit /b 0

:cleanup_failed
echo.
echo ========================================
echo           Build FAILED!
echo ========================================
echo.

if "%RESTORE_KEY%"=="1" (
    echo   Restoring custom key.properties...
    ren "android\key.properties.bak" "key.properties"
    set RESTORE_KEY=0
)

exit /b 1
