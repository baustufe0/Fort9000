@echo off
rem FORT 9000 training: collects the Forts log and retrains the strategy.
where py >nul 2>nul && (py "%~dp0train.py" %*) || (python "%~dp0train.py" %*)
pause
