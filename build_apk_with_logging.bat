@echo off
setlocal enabledelayedexpansion
echo ========================================
echo    BUILD APK COM LOGGING DETALHADO
echo ========================================
echo Data/Hora: %date% %time%
echo.

REM Criar pasta logs se não existir
if not exist "logs" mkdir logs

REM Gerar nome do arquivo de log com timestamp
for /f "tokens=2 delims==" %%a in ('wmic OS Get localdatetime /value') do set "dt=%%a"
set "YY=%dt:~2,2%" & set "YYYY=%dt:~0,4%" & set "MM=%dt:~4,2%" & set "DD=%dt:~6,2%"
set "HH=%dt:~8,2%" & set "Min=%dt:~10,2%" & set "Sec=%dt:~12,2%"
set "timestamp=%YYYY%-%MM%-%DD%_%HH%-%Min%-%Sec%"

REM Definir arquivos de log
set "log_info=logs\build_info_%timestamp%.log"
set "log_errors=logs\build_errors_%timestamp%.log"
set "log_warnings=logs\build_warnings_%timestamp%.log"
set "log_full=logs\build_full_%timestamp%.log"

REM Inicializar contadores
set /a error_count=0
set /a warning_count=0
set start_time=%time%

echo Arquivos de log criados:
echo   - Informações: %log_info%
echo   - Erros: %log_errors%
echo   - Warnings: %log_warnings%
echo   - Log completo: %log_full%
echo.

REM ========================================
REM ETAPA 1: LIMPEZA DO BUILD ANTERIOR
REM ========================================
echo [ETAPA 1/4] Limpando build anterior...
echo [%time%] Iniciando flutter clean >> "%log_info%"
flutter clean > "%log_full%" 2>&1
if %errorlevel% neq 0 (
    echo ✗ ERRO: Falha na limpeza do build anterior
    echo [%time%] ERRO: flutter clean falhou >> "%log_errors%"
    set /a error_count+=1
) else (
    echo ✓ Build anterior limpo com sucesso
    echo [%time%] flutter clean executado com sucesso >> "%log_info%"
)
echo.

REM ========================================
REM ETAPA 2: OBTENÇÃO DE DEPENDÊNCIAS
REM ========================================
echo [ETAPA 2/4] Obtendo dependências...
echo [%time%] Iniciando flutter pub get >> "%log_info%"
flutter pub get >> "%log_full%" 2>&1
if %errorlevel% neq 0 (
    echo ✗ ERRO: Falha na obtenção de dependências
    echo [%time%] ERRO: flutter pub get falhou >> "%log_errors%"
    set /a error_count+=1
) else (
    echo ✓ Dependências obtidas com sucesso
    echo [%time%] flutter pub get executado com sucesso >> "%log_info%"
)
echo.

REM ========================================
REM ETAPA 3: BUILD DO APK
REM ========================================
echo [ETAPA 3/4] Executando build do APK...
echo Comando: flutter build apk --target-platform android-arm64 --release --verbose
echo [%time%] Iniciando build do APK >> "%log_info%"
echo.

REM Executar o build e capturar saída
flutter build apk --target-platform android-arm64 --release --verbose > temp_build.log 2>&1
set build_result=%errorlevel%

REM Processar logs e separar por tipo
for /f "delims=" %%i in (temp_build.log) do (
    echo %%i >> "%log_full%"
    echo %%i | findstr /i "error" >nul && (
        echo %%i >> "%log_errors%"
        set /a error_count+=1
    )
    echo %%i | findstr /i "warning" >nul && (
        echo %%i >> "%log_warnings%"
        set /a warning_count+=1
    )
    echo %%i | findstr /v /i "error warning" >nul && (
        echo %%i >> "%log_info%"
    )
)

REM Limpar arquivo temporário
del temp_build.log

if %build_result% neq 0 (
    echo ✗ ERRO: Falha no build do APK
    echo [%time%] ERRO: Build do APK falhou com código %build_result% >> "%log_errors%"
) else (
    echo ✓ Build do APK executado
    echo [%time%] Build do APK concluído >> "%log_info%"
)
echo.

REM ========================================
REM ETAPA 4: VERIFICAÇÃO E ESTATÍSTICAS
REM ========================================
echo [ETAPA 4/4] Verificando resultado do build...
set end_time=%time%

if exist "build\app\outputs\flutter-apk\app-release.apk" (
    echo ✓ APK GERADO COM SUCESSO!
    echo.
    echo Informações do APK:
    echo   Local: build\app\outputs\flutter-apk\app-release.apk
    for %%A in ("build\app\outputs\flutter-apk\app-release.apk") do (
        echo   Tamanho: %%~zA bytes
        echo   Data: %%~tA
    )
    echo [%time%] APK gerado com sucesso >> "%log_info%"
) else (
    echo ✗ FALHA NA GERAÇÃO DO APK
    echo [%time%] ERRO: APK não foi gerado >> "%log_errors%"
    set /a error_count+=1
)

echo.
echo ========================================
echo           RESUMO DO BUILD
echo ========================================
echo Horário de início: %start_time%
echo Horário de término: %end_time%
echo Total de erros: !error_count!
echo Total de warnings: !warning_count!
echo.
echo ARQUIVOS DE LOG GERADOS:
echo ----------------------------------------
echo 📄 Log completo:    %log_full%
echo 📋 Informações:     %log_info%
if !error_count! gtr 0 (
    echo ❌ Erros:           %log_errors% (!error_count! erros encontrados)
) else (
    echo ✅ Erros:           Nenhum erro encontrado
)
if !warning_count! gtr 0 (
    echo ⚠️  Warnings:       %log_warnings% (!warning_count! warnings encontrados)
) else (
    echo ✅ Warnings:       Nenhum warning encontrado
)
echo.
if !error_count! gtr 0 (
    echo ❌ BUILD CONCLUÍDO COM ERROS - Verifique o arquivo de erros
) else (
    if !warning_count! gtr 0 (
        echo ⚠️  BUILD CONCLUÍDO COM WARNINGS - Verifique o arquivo de warnings
    ) else (
        echo ✅ BUILD CONCLUÍDO COM SUCESSO - Sem erros ou warnings
    )
)
echo ========================================
pause