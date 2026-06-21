@echo off
setlocal

if "%MSYS2_ROOT%"=="" set "MSYS2_ROOT=C:\msys64"
set "MSYS2_USR_BIN=%MSYS2_ROOT%\usr\bin"

if not exist "%MSYS2_USR_BIN%\zsh.exe" (
  echo dotfiles: MSYS2 zsh is not installed: %MSYS2_USR_BIN%\zsh.exe
  exit /b 1
)

set "PATH=%MSYS2_USR_BIN%;%PATH%"
set "MSYSTEM=MSYS"
set "CHERE_INVOKING=1"

"%MSYS2_USR_BIN%\bash.exe" "%USERPROFILE%\.local\bin\msys2-zsh.sh" %*
exit /b %ERRORLEVEL%
