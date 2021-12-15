@echo off
rem Delete...
call :d ATX80_8
call :d ATX80_88
call :d ATX80_168
call :d ATX80_328
exit /b

:d
if exist *.o del *.o
if exist src\*.o del src\*.o
if exist %1.lst del %1.lst
if exist %1.sym del %1.sym
if exist %1.bin del %1.bin
if exist %1.elf del %1.elf
exit /b
