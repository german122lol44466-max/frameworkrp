@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
rem ============================================================================
rem  New-York Roleplay: компиляция всех моделей (.qc) через studiomdl из Garry's Mod.
rem  Даёт «полные» модели: анимации open/close у сумок, точная коллизия.
rem  Использование:  tools\compile_models.bat ["C:\...\steamapps\common\GarrysMod"]
rem ============================================================================
set "GMOD=%~1"
if "%GMOD%"=="" (
    for /f "tokens=2*" %%a in ('reg query "HKCU\Software\Valve\Steam" /v SteamPath 2^>nul') do set "STEAM=%%b"
    set "GMOD=!STEAM:/=\!\steamapps\common\GarrysMod"
)
set "STUDIOMDL=%GMOD%\bin\studiomdl.exe"
if not exist "%STUDIOMDL%" set "STUDIOMDL=%GMOD%\bin\win64\studiomdl.exe"
if not exist "%STUDIOMDL%" (
    echo [!] Не найден studiomdl.exe в "%GMOD%\bin".
    echo     Укажите папку игры: tools\compile_models.bat "D:\SteamLibrary\steamapps\common\GarrysMod"
    exit /b 1
)
set "ROOT=%~dp0.."
set "OK=0"
set "FAIL=0"
for /r "%ROOT%\tools\models\src" %%f in (*.qc) do (
    echo --- %%~nxf
    pushd "%%~dpf"
    "%STUDIOMDL%" -game "%GMOD%\garrysmod" -nop4 "%%~nxf" >"%%~dpnf.log" 2>&1
    if errorlevel 1 (set /a FAIL+=1 & echo     ошибка, см. %%~nf.log) else (set /a OK+=1)
    popd
)
echo.
echo Скомпилировано: !OK!, ошибок: !FAIL!
xcopy /e /y /i /q "%GMOD%\garrysmod\models\nyrp" "%ROOT%\gamemodes\newyorkrp\content\models\nyrp" >nul
echo Модели скопированы в gamemodes\newyorkrp\content\models\nyrp
endlocal
