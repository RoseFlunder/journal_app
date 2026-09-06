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

rem JDK 24+ restricts Gradle's native-platform library access by default.
rem Preserve caller-provided JVM options while granting the documented access.
set "JAVA_OPTS=%JAVA_OPTS% --enable-native-access=ALL-UNNAMED"

flutter build %TARGET% --release --dart-define-from-file="%DEFINES_FILE%"
exit /b %ERRORLEVEL%
