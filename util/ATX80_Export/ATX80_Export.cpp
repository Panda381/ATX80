// ATX80 - Export BASIC programs from FLASH memory file

#include <stdio.h>
#include <windows.h>

#pragma warning(disable : 4996) // warning - fopen may be unsafe

typedef signed char s8;
typedef unsigned char u8;
typedef signed short s16;
typedef unsigned short u16;
typedef signed long int s32;
typedef unsigned long int u32;

u8* Buf = NULL;
int BufSlot; // offset of current slot
int BufMax; // end offset of program slots
int PageSize; // ROM page size

#define NEWLINE 0x76

// characters 0x00..0x3F ('\' = Shift prefix, '&' = pound character)
const char* Chars[] = {
		" ",		// 0x00
		"\"",		// 0x01
		"\\Q",		// 0x02
		"\\W",		// 0x03
		"\\E",		// 0x04
		"\\R",		// 0x05
		"\\D",		// 0x06
		"\\F",		// 0x07
		"\\S",		// 0x08
		"\\A",		// 0x09
		"\\T",		// 0x0A
		"\\G",		// 0x0B
		"&",		// 0x0C pound
		"$",		// 0x0D
		":",		// 0x0E
		"?",		// 0x0F
		"(",		// 0x10
		")",		// 0x11
		"-",		// 0x12
		"+",		// 0x13
		"*",		// 0x14
		"/",		// 0x15
		"=",		// 0x16
		">",		// 0x17
		"<",		// 0x18
		";",		// 0x19
		",",		// 0x1A
		".",		// 0x1B
		"0",		// 0x1C
		"1",		// 0x1D
		"2",		// 0x1E
		"3",		// 0x1F
		"4",		// 0x20
		"5",		// 0x21
		"6",		// 0x22
		"7",		// 0x23
		"8",		// 0x24
		"9",		// 0x25
		"A",		// 0x26
		"B",		// 0x27
		"C",		// 0x28
		"D",		// 0x29
		"E",		// 0x2A
		"F",		// 0x2B
		"G",		// 0x2C
		"H",		// 0x2D
		"I",		// 0x2E
		"J",		// 0x2F
		"K",		// 0x30
		"L",		// 0x31
		"M",		// 0x32
		"N",		// 0x33
		"O",		// 0x34
		"P",		// 0x35
		"Q",		// 0x36
		"R",		// 0x37
		"S",		// 0x38
		"T",		// 0x39
		"U",		// 0x3A
		"V",		// 0x3B
		"W",		// 0x3C
		"X",		// 0x3D
		"Y",		// 0x3E
		"Z",		// 0x3F
};

// tokens 0xD3..0xFF ('\' = Shift prefix, '&' = pound character)
const char* Tokens[] = {
		"\\?",		// 0xD3
		"\"",		// 0xD4
		" THEN",	// 0xD5
		" TO ",		// 0xD6
		";",		// 0xD7
		",",		// 0xD8
		")",		// 0xD9
		"(",		// 0xDA
		"NOT ",		// 0xDB
		"-",		// 0xDC
		"+",		// 0xDD
		"*",		// 0xDE
		"/",		// 0xDF
		" AND ",	// 0xE0
		" OR ",		// 0xE1
		"**",		// 0xE2
		"=",		// 0xE3
		">",		// 0xE4
		"<",		// 0xE5
		" LIST ",	// 0xE6
		" RETURN",	// 0xE7
		" CLS",		// 0xE8
		" DIM ",	// 0xE9
		" SAVE ",	// 0xEA
		" FOR ",	// 0xEB
		" GO TO ",	// 0xEC
		" POKE ",	// 0xED
		" INPUT ",	// 0xEE
		" RANDOMISE", // 0xEF
		" LET ",	// 0xF0
		" FAST",	// 0xF1
		" SLOW",	// 0xF2
		" NEXT ",	// 0xF3
		" PRINT",	// 0xF4
		" MEMORY",	// 0xF5
		" NEW",		// 0xF6
		" RUN ",	// 0xF7
		" STOP",	// 0xF8
		" CONTINUE", // 0xF9
		" IF ",		// 0xFA
		" GO SUB ",	// 0xFB
		" LOAD ",	// 0xFC
		" CLEAR",	// 0xFD
		" REM ",	// 0xFE
		"\\?",		// 0xFF
};

FILE* OutFile = NULL;

// output character to output file
void OutChar(char ch)
{
	fwrite(&ch, 1, 1, OutFile);
}

// output ASCIIZ text to output file
void OutText(const char* text)
{
	fprintf(OutFile, "%s", text);
}

// export program code
void ExportProg(const u8* buf, int num)
{
	while (num > 2)
	{
		// export line number
		int line = buf[0]*256 + buf[1];
		fprintf(OutFile, "%d", line);
		buf += 2;
		num -= 2;

		// export commands
		while (num > 0)
		{
			u8 ch = *buf++;
			num--;

			// end of line
			if (ch == NEWLINE) break;

			// print character
			if (ch < 0x40)
				OutText(Chars[ch]);
			else
				if (ch >= 0xd3)
				{
					OutText(Tokens[ch - 0xd3]);

					// space separator
					if ((*buf != NEWLINE) // not end of line
						&& ((ch == 0xF4) // PRINT
							|| (ch == 0xEF))) // RANDOMISE
						OutChar(' '); // space
				}
				else
					OutText("\\?");
		}		

		// end of line
		OutChar('\n');
	}
}

// export variables
void ExportVar(const u8* buf, int num)
{
	int n;
	while (num > 1)
	{
		// load character
		u8 ch = *buf++;
		num--;

		switch (ch >> 5)
		{
		// short integer number
		case 3:
			fprintf(OutFile, "LET %c=%d\n", (ch & 0x1f) - 6 + 'A', *(s16*)buf);
			buf += 2;
			num -= 2;
			break;

		// long integer number
		case 2:
			OutText("LET ");
			ch &= 0x1f;
			for (;;)	// print long name
			{
				OutChar((ch & 0x1f) - 6 + 'A');
				if ((ch & 0x80) > 0) break;
				ch = *buf++;
				num--;
			}
			fprintf(OutFile, "=%d\n", *(s16*)buf);
			buf += 2;
			num -= 2;
			break;

		// text
		case 4:
			fprintf(OutFile, "LET %c$=", (ch & 0x1f) - 6 + 'A');
			OutChar('"');
			for (;;)
			{
				ch = *buf++;
				num--;
				if (ch == 1) break;
				if (ch >= 0xd3)
					OutText(Tokens[ch - 0xd3]);
				else
					OutText(Chars[ch & 0x3f]);
			}
			OutChar('"');
			OutChar('\n');
			break;

		// array
		case 5:
			n = *buf++;
			num--;
			fprintf(OutFile, "DIM %c(%d)=", (ch & 0x1f) - 6 + 'A', n);
			for (; n >= 0; n--)
			{
				fprintf(OutFile, "%d", *(s16*)buf);
				buf += 2;
				num -= 2;
				if (n > 0) OutChar(',');
			}
			OutChar('\n');
			break;

		// FOR loop
		case 7:
			fprintf(OutFile, "FOR %c=%d,%d,%d\n", (ch & 0x1f) - 6 + 'A',
					*(s16*)buf, *(s16*)&buf[2], *(s16*)&buf[4]);
			buf += 6;
			num -= 6;
			break;
		}
	}
}

int main(int argc, char* argv[])
{
	// check syntax
	if (argc != 3)
	{
		printf("Syntax: input.bin output.txt\n");
		return 1;
	}

	// open input file
	FILE* f = fopen(argv[1], "rb");
	if (f == NULL)
	{
		printf("Error opening %s\n", argv[1]);
		return 1;
	}

	// size of input file
	fseek(f, 0, SEEK_END);
	int size = ftell(f);
	fseek(f, 0, SEEK_SET);
	if (size < 0x1F04)
	{
		printf("Incorrect size of %s\n", argv[1]);
		return 1;
	}

	// create buffer
	Buf = (u8*)malloc(size);
	if (Buf == NULL)
	{
		printf("Memory error\n");
		return 1;
	}

	// read file
	int size2 = (int)fread(Buf, 1, size, f);
	fclose(f);
	if (size2 != size)
	{
		printf("Error reading %s\n", argv[1]);
		return 1;
	}

	// prepare the end offset 
	PageSize = 64;
	if (size >= 0x7F00)
	{
		BufMax = 0x7E00;	// ATmega328
		PageSize = 128;
	}
	else if (size >= 0x3F80)
		BufMax = 0x3F00;	// ATmega168
	else
		BufMax = 0x1F00;	// ATmega8, ATmega88

	// parse file header
	BOOL err = (Buf[BufMax] != 'F') || (Buf[BufMax+1] != 'E');
	BufSlot = *(u16*)&Buf[BufMax+2];	// load start offset
	if (((BufSlot & (PageSize-1)) != 0) // alignment error
		|| (BufSlot >= BufMax)
		|| (BufSlot < 100))
			err = TRUE;
	if (err)
	{
		printf("Invalid structure of %s\n", argv[1]);
		return 1;
	}

	// open output file
	OutFile = fopen(argv[2], "wb");
	if (OutFile == NULL)
	{
		printf("Error creating %s\n", argv[2]);
		return 1;
	}

	// export slots
	while (BufSlot < BufMax)
	{
		// load slot header
		int slotsize = *(u16*)&Buf[BufSlot]; // size of this slot
		int slotinx = *(u8*)&Buf[BufSlot+2]; // slot index
		int progsize = *(u16*)&Buf[BufSlot+3]; // program size
		int totalsize = *(u16*)&Buf[BufSlot+5]; // total size

		// check slot header
		if ((slotsize < PageSize) ||			// minimal 1 page
			(slotsize > 1024) ||				// maximal slot size (= RAM size of ATX80)
			((slotsize & (PageSize-1)) != 0) ||	// need alignment to the page
			(slotinx > 100) ||					// max. slot index
			(progsize > slotsize-3) ||			// max. program size
			(totalsize > slotsize-3) ||			// max. total size
			(totalsize <= progsize))			// min. total size
				break;

		// export program size
		OutText("-------------------------------------------------\n");
		fprintf(OutFile, "%d) \n", slotinx+1);
		int varsize = totalsize-progsize-1;
		progsize -= 4;
		if (varsize > 0)
			fprintf(OutFile, "program %d bytes, variables %d bytes\n\n", progsize, varsize);
		else
			fprintf(OutFile, "program %d bytes\n\n", progsize);

		// export slot index
		fprintf(OutFile, "SLOT %u\n", slotinx+1);

		// export program code
		ExportProg(&Buf[BufSlot+7], progsize);

		// export variables
		ExportVar(&Buf[BufSlot+7+progsize], varsize);

		OutChar('\n');

		// shift to next slot
		BufSlot += slotsize;
	}

	// close output file
	fclose(OutFile);

	free(Buf);
	return 0;
}

