@echo off
rem Compilation...
call d.bat

call :c ATX80_8 atmega8
if not exist ATX80_8.hex goto quit

call :c ATX80_88 atmega88
if not exist ATX80_88.hex goto quit

call :c ATX80_168 atmega168
if not exist ATX80_168.hex goto quit

call :c ATX80_328 atmega328

:quit
exit /b

:c
if exist %1.hex del %1.hex
echo Compile %1...
make -s all APPNAME=%1 MCU=%2 F_CPU=24000000
if errorlevel 1 goto err
if not exist %1.hex goto err

avr-nm -n %1.elf > %1.sym
avr-size -C --mcu=%2 %1.elf
avr-objdump -d -S -m avr %1.elf > %1.lst
goto ok

:err
echo.
pause

:ok
if exist *.o del *.o
if exist src\*.o del src\*.o

exit /b
