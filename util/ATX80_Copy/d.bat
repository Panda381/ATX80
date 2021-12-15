@echo off
rem Delete...
call :d ATX80_8_Copy
call :d ATX80_88_Copy
call :d ATX80_168_Copy
call :d ATX80_328_Copy
exit /b

:d
if exist *.o del *.o
if exist src\*.o del src\*.o
if exist %1.lst del %1.lst
if exist %1.sym del %1.sym
if exist %1.elf del %1.elf
exit /b
