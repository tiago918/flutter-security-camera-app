@echo off
setlocal
cd /d "%~dp0"

where flutter >nul 2>&1
if errorlevel 1 (
  echo Erro: Flutter nao encontrado no PATH.
  echo Abra o PowerShell e execute manualmente: flutter build apk --release --split-per-abi
  pause
  exit /b 1
)

echo Iniciando build APK (release, split por ABI)...
flutter build apk --release --split-per-abi
if errorlevel 1 (
  echo.
  echo Build falhou. Confira as mensagens acima.
  pause
  exit /b 1
)

echo.
echo Build concluido com sucesso!
echo APKs gerados em:
echo   %cd%\build\app\outputs\flutter-apk\
echo     - app-arm64-v8a-release.apk
echo     - app-armeabi-v7a-release.apk
echo     - app-x86_64-release.apk
pause