@echo off
rem Installa omp Tiles in Tern: copia questa cartella nella cartella dei plugin di Tern.
rem Rilancialo per aggiornare il plugin.
setlocal

where tern >nul 2>nul
if errorlevel 1 (
	echo tern non trovato nel PATH: installa Tern ^(https://stencil.so/tern^) e riprova. 1>&2
	set "rc=1"
	goto done
)

tern plugin install "%~dp0." --force
set "rc=%errorlevel%"

:done
rem Aperto con doppio clic: lascia leggere il risultato prima di chiudere.
echo %cmdcmdline% | find /i "%~0" >nul && pause
exit /b %rc%
