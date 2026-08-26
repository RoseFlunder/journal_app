@echo off
setlocal

set "TARGET=%~1"
if "%TARGET%"=="" set "TARGET=web"

set "DEFINES_FILE=%~2"
if "%DEFINES_FILE%"=="" set "DEFINES_FILE=%USERPROFILE%\.config\cozy_bloom\build-defines.json"

if not exist "%DEFINES_FILE%" (
  echo Defines file was not found: %DEFINES_FILE% 1>&2
  exit /b 1
)

flutter build %TARGET% --release --dart-define-from-file="%DEFINES_FILE%"
exit /b %ERRORLEVEL%
