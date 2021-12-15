@echo off
rem Compilation...
call d.bat

call :c ATX80_8_Copy atmega8
if not exist ATX80_8_Copy.bin goto quit
if not exist ATX80_8_Copy.hex goto quit

call :c ATX80_88_Copy atmega88
if not exist ATX80_88_Copy.bin goto quit
if not exist ATX80_88_Copy.hex goto quit

call :c ATX80_168_Copy atmega168
if not exist ATX80_168_Copy.bin goto quit
if not exist ATX80_168_Copy.hex goto quit

call :c ATX80_328_Copy atmega328

:quit
exit /b

:c
if exist %1.hex del %1.hex
if exist %1.bin del %1.bin
echo Compile %1...
make -s all APPNAME=%1 MCU=%2 F_CPU=24000000
if errorlevel 1 goto err
if not exist %1.hex goto err
if not exist %1.bin goto err

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
