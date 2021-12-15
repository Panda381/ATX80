@echo off
ATX80_Import.exe ..\ATX80_Copy\ATX80_8_Copy.bin ..\Programs_1.txt 8_1.bin
if errorlevel 1 goto err

ATX80_Import.exe ..\ATX80_Copy\ATX80_8_Copy.bin ..\Programs_2.txt 8_2.bin
if errorlevel 1 goto err

ATX80_Import.exe ..\ATX80_Copy\ATX80_8_Copy.bin ..\Programs_3.txt 8_3.bin
if errorlevel 1 goto err


ATX80_Import.exe ..\ATX80_Copy\ATX80_88_Copy.bin ..\Programs_1.txt 88_1.bin
if errorlevel 1 goto err

ATX80_Import.exe ..\ATX80_Copy\ATX80_88_Copy.bin ..\Programs_2.txt 88_2.bin
if errorlevel 1 goto err

ATX80_Import.exe ..\ATX80_Copy\ATX80_88_Copy.bin ..\Programs_3.txt 88_3.bin
if errorlevel 1 goto err


ATX80_Import.exe ..\ATX80_Copy\ATX80_168_Copy.bin ..\Programs_1.txt 168_1.bin
if errorlevel 1 goto err

ATX80_Import.exe ..\ATX80_Copy\ATX80_168_Copy.bin ..\Programs_2.txt 168_2.bin
if errorlevel 1 goto err

ATX80_Import.exe ..\ATX80_Copy\ATX80_168_Copy.bin ..\Programs_3.txt 168_3.bin
if errorlevel 1 goto err


ATX80_Import.exe ..\ATX80_Copy\ATX80_328_Copy.bin ..\Programs_1.txt 328_1.bin
if errorlevel 1 goto err

ATX80_Import.exe ..\ATX80_Copy\ATX80_328_Copy.bin ..\Programs_2.txt 328_2.bin
if errorlevel 1 goto err

ATX80_Import.exe ..\ATX80_Copy\ATX80_328_Copy.bin ..\Programs_3.txt 328_3.bin
if not errorlevel 1 goto ok

:err
pause
:ok
