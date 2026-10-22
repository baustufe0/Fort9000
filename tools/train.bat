@echo off
rem FORT 9000 Training: sammelt das Forts-Log und trainiert die Strategie neu.
where py >nul 2>nul && (py "%~dp0train.py" %*) || (python "%~dp0train.py" %*)
pause
