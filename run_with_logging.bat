@echo off
echo Iniciando Flutter com logging organizado...

REM Criar estrutura de pastas para logs organizados
if not exist "logs" mkdir logs
if not exist "logs\errors" mkdir logs\errors
if not exist "logs\info" mkdir logs\info
if not exist "logs\debug" mkdir logs\debug

REM Excluir todos os logs antigos de todas as pastas
echo Excluindo logs antigos...
if exist "logs\errors\*.log" del "logs\errors\*.log" /q
if exist "logs\info\*.log" del "logs\info\*.log" /q
if exist "logs\debug\*.log" del "logs\debug\*.log" /q
if exist "logs\*.log" del "logs\*.log" /q

REM Gerar nome do arquivo de log com timestamp
for /f "tokens=2 delims==" %%a in ('wmic OS Get localdatetime /value') do set "dt=%%a"
set "YY=%dt:~2,2%" & set "YYYY=%dt:~0,4%" & set "MM=%dt:~4,2%" & set "DD=%dt:~6,2%"
set "HH=%dt:~8,2%" & set "Min=%dt:~10,2%" & set "Sec=%dt:~12,2%"
set "datestamp=%YYYY%-%MM%-%DD%_%HH%-%Min%-%Sec%"

REM Definir arquivos de log separados
set "errorfile=logs\errors\flutter_errors_%datestamp%.log"
set "infofile=logs\info\flutter_info_%datestamp%.log"
set "debugfile=logs\debug\flutter_debug_%datestamp%.log"
set "fulllogfile=logs\flutter_complete_%datestamp%.log"

echo Executando flutter run --verbose...
echo Logs de erro serão salvos em: %errorfile%
echo Logs de info serão salvos em: %infofile%
echo Logs de debug serão salvos em: %debugfile%
echo Log completo será salvo em: %fulllogfile%
echo.

REM Executar flutter run com verbose e separar logs
REM Salvar log completo e separar erros
flutter run --verbose > "%fulllogfile%" 2> "%errorfile%"

REM Filtrar informações específicas do log completo
findstr /i "info built installing" "%fulllogfile%" > "%infofile%" 2>nul
findstr /i "debug verbose trace" "%fulllogfile%" > "%debugfile%" 2>nul

echo.
echo Flutter finalizado. Logs organizados salvos em:
echo - Erros: %errorfile%
echo - Info: %infofile%
echo - Debug: %debugfile%
echo - Completo: %fulllogfile%
echo Pressione qualquer tecla para continuar...
pause > nul