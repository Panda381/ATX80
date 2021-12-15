// ATX80 - Import BASIC programs to FLASH memory file

#include <stdio.h>
#include <windows.h>

#pragma warning(disable : 4996) // warning - fopen may be unsafe

typedef signed char s8;
typedef unsigned char u8;
typedef signed short s16;
typedef unsigned short u16;
typedef signed long int s32;
typedef unsigned long int u32;

// BIN file
u8* Buf = NULL;
int BufSize;
int BufSlot0; // start of space
int BufSlot; // offset of current slot
int BufMax; // end offset of program slots
int PageSize; // ROM page size

// TEXT file
char* Buf2 = NULL;
int Buf2Size; // size of buffer
int Buf2Inx = 0; // buffer index
int Line = 1; // current text line

#define NEWLINE 0x76

typedef struct {
	char*	text;	// token text
	u8		code;	// token code
} sToken;

// tokens - commands
sToken TokensCmd[] = {
		{ " LIST ",		0xE6 },
		{ " LIST",		0xE6 },
		{ " RETURN",	0xE7 },
		{ " CLS",		0xE8 },
		{ " DIM ",		0xE9 },
		{ " SAVE ",		0xEA },
		{ " SAVE",		0xEA },
		{ " FOR ",		0xEB },
		{ " GO TO ",	0xEC },
		{ " POKE ",		0xED },
		{ " INPUT ",	0xEE },
		{ " RANDOMISE ", 0xEF },
		{ " RANDOMISE",	0xEF },
		{ " LET ",		0xF0 },
		{ " FAST",		0xF1 },
		{ " SLOW",		0xF2 },
		{ " NEXT ",		0xF3 },
		{ " PRINT ",	0xF4 },
		{ " PRINT",		0xF4 },
		{ " MEMORY",	0xF5 },
		{ " NEW",		0xF6 },
		{ " RUN ",		0xF7 },
		{ " RUN",		0xF7 },
		{ " STOP",		0xF8 },
		{ " CONTINUE",	0xF9 },
		{ " IF ",		0xFA },
		{ " GO SUB ",	0xFB },
		{ " LOAD ",		0xFC },
		{ " LOAD",		0xFC },
		{ " CLEAR",		0xFD },
		{ " REM ",		0xFE },
		{ " REM",		0xFE },
};

// tokens - code
sToken TokensCode[] = {
		{ " THEN",		0xD5 },
		{ " TO ",		0xD6 },
		{ ";",			0xD7 },
		{ ",",			0xD8 },
		{ ")",			0xD9 },
		{ "(",			0xDA },
		{ " NOT ",		0xDB },
		{ "NOT ",		0xDB },
		{ " NOT",		0xDB },
		{ "NOT",		0xDB },
		{ "-",			0xDC },
		{ "+",			0xDD },
		{ "**",			0xE2 },
		{ "*",			0xDE },
		{ "/",			0xDF },
		{ " AND ",		0xE0 },
		{ " OR ",		0xE1 },
		{ "=",			0xE3 },
		{ ">",			0xE4 },
		{ "<",			0xE5 },
};

// tokens - characters
sToken TokensChar[] = {
		{ " ",			0x00 },
		{ "*",			0xDE },
		{ "\"",			0x01 },
		{ "\\Q",		0x02 },
		{ "\\W",		0x03 },
		{ "\\E",		0x04 },
		{ "\\R",		0x05 },
		{ "\\D",		0x06 },
		{ "\\F",		0x07 },
		{ "\\S",		0x08 },
		{ "\\A",		0x09 },
		{ "\\T",		0x0A },
		{ "\\G",		0x0B },
		{ "&",			0x0C },	// pound
		{ "$",			0x0D },
		{ ":",			0x0E },
		{ "?",			0x0F },
		{ ".",			0x1B },
		{ "0",			0x1C },
		{ "1",			0x1D },
		{ "2",			0x1E },
		{ "3",			0x1F },
		{ "4",			0x20 },
		{ "5",			0x21 },
		{ "6",			0x22 },
		{ "7",			0x23 },
		{ "8",			0x24 },
		{ "9",			0x25 },
		{ "A",			0x26 },
		{ "B",			0x27 },
		{ "C",			0x28 },
		{ "D",			0x29 },
		{ "E",			0x2A },
		{ "F",			0x2B },
		{ "G",			0x2C },
		{ "H",			0x2D },
		{ "I",			0x2E },
		{ "J",			0x2F },
		{ "K",			0x30 },
		{ "L",			0x31 },
		{ "M",			0x32 },
		{ "N",			0x33 },
		{ "O",			0x34 },
		{ "P",			0x35 },
		{ "Q",			0x36 },
		{ "R",			0x37 },
		{ "S",			0x38 },
		{ "T",			0x39 },
		{ "U",			0x3A },
		{ "V",			0x3B },
		{ "W",			0x3C },
		{ "X",			0x3D },
		{ "Y",			0x3E },
		{ "Z",			0x3F },
};

#define countof(_arr) (sizeof(_arr)/sizeof(_arr[0])) 

// input character (returns 0=end)
char InChar()
{
	if (Buf2Inx >= Buf2Size) return 0;
	return Buf2[Buf2Inx++];
}

// check end of line
BOOL CheckEndLine()
{
	return (Buf2Inx >= Buf2Size) ||
			(Buf2[Buf2Inx] == 10) ||
			(Buf2[Buf2Inx] == 13);
}

// find start of next line
void InNextLine()
{
	while (Buf2Inx < Buf2Size)
	{
		Buf2Inx++;
		if (Buf2[Buf2Inx-1] == 10) break;
	}
	Line++;
}

// compare token
BOOL InToken(const char* token)
{
	int len = 0;
	while ((Buf2Inx+len < Buf2Size) && 
			(token[len] == Buf2[Buf2Inx+len]) &&
			(token[len] != 0))
				len++;
	if (token[len] != 0) return FALSE;
	Buf2Inx += len;
	return TRUE;
}

// get token (returns token code or -1 if not found)
int GetToken(const sToken* token, int num)
{
	int tok = -1;
	int i;
	for (i = 0; i < num; i++)
	{
		if (InToken(token[i].text))
		{
			tok = token[i].code;
			break;
		}
	}
	return tok;
}

// load signed word number
int InNum()
{
	int n = 0;
	BOOL sign = FALSE;
	while (Buf2Inx < Buf2Size)
	{
		char ch = Buf2[Buf2Inx];
		if (ch == '-')
		{
			Buf2Inx++;
			sign = TRUE;
		}
		else
		{
			if ((ch < '0') || (ch > '9')) break;
			Buf2Inx++;
			n = n*10 + (ch - '0');
		}
	}
	return sign ? (-n) : n;
}

int main(int argc, char* argv[])
{
	int i;

	// check syntax
	if (argc != 4)
	{
		printf("Syntax: input.bin input.txt output.bin\n");
		return 1;
	}

// ===== load BIN file

	// open input BIN file
	FILE* f = fopen(argv[1], "rb");
	if (f == NULL)
	{
		printf("Error opening %s\n", argv[1]);
		return 1;
	}

	// size of input BIN file
	fseek(f, 0, SEEK_END);
	BufSize = ftell(f);
	fseek(f, 0, SEEK_SET);
	if (BufSize < 0x1F04)
	{
		printf("Incorrect size of %s\n", argv[1]);
		return 1;
	}

	// create buffer
	Buf = (u8*)malloc(BufSize + 200);
	if (Buf == NULL)
	{
		printf("Memory error\n");
		return 1;
	}

	// read file
	int size2 = (int)fread(Buf, 1, BufSize, f);
	fclose(f);
	if (size2 != BufSize)
	{
		printf("Error reading %s\n", argv[1]);
		return 1;
	}

	// prepare the end offset 
	PageSize = 64;
	if (BufSize > 24000)
	{
		BufMax = 0x7E00;	// ATmega328
		PageSize = 128;
	}
	else if (BufSize > 12000)
	{
		BufMax = 0x3F00;	// ATmega168
	}
	else
	{
		BufMax = 0x1F00;	// ATmega8, ATmega88
	}

	// parse file header
	BOOL err = (Buf[BufMax] != 'F') || (Buf[BufMax+1] != 'E');
	BufSlot = *(u16*)&Buf[BufMax+2];	// load start offset
	BufSlot0 = BufSlot;
	if (((BufSlot & (PageSize-1)) != 0) // alignment error
		|| (BufSlot >= BufMax)
		|| (BufSlot < 200))
			err = TRUE;
	if (err)
	{
		printf("Invalid structure of %s\n", argv[1]);
		return 1;
	}

	// clear slot buffer
	memset(&Buf[BufSlot], -1, BufMax - BufSlot);

// ===== load TEXT file

	// open input BIN file
	f = fopen(argv[2], "rb");
	if (f == NULL)
	{
		printf("Error opening %s\n", argv[2]);
		return 1;
	}

	// size of input TEXT file
	fseek(f, 0, SEEK_END);
	Buf2Size = ftell(f);
	fseek(f, 0, SEEK_SET);

	// create buffer
	Buf2 = (char*)malloc(Buf2Size);
	if (Buf2 == NULL)
	{
		printf("Memory error\n");
		return 1;
	}

	// read file
	size2 = (int)fread(Buf2, 1, Buf2Size, f);
	fclose(f);
	if (size2 != Buf2Size)
	{
		printf("Error reading %s\n", argv[1]);
		return 1;
	}

// ===== Parse slots

	while (Buf2Inx < Buf2Size)
	{
		// find slot header
		if (InToken("SLOT "))
		{
			// get slot index
			int slotinx = InNum();
			if ((slotinx < 1) || (slotinx > 64))
			{
				printf("Invalid SLOT %d on row %d\n", slotinx, Line);
				return 1;
			}
			printf("SLOT %d: ", slotinx);
			InNextLine();

			// store slot index
			Buf[BufSlot+2] = slotinx - 1;

// ========= parse program code

			// parse program rows
			int inx = BufSlot + 7; // store offset
			while (Buf2Inx < Buf2Size)
			{
				// load line number
				if ((Buf2[Buf2Inx] < '0') || (Buf2[Buf2Inx] > '9')) break;
				int line = InNum();
				if ((line < 1) || (line > 9999))
				{
					printf("Invalid program line %d on row %d\n", line, Line);
					return 1;
				}

				// save line number
				if (inx + 4 > BufMax)
				{
					printf("Insufficient storage space on row %d\n", Line);
					return 1;
				}
				Buf[inx++] = (u8)(line >> 8);
				Buf[inx++] = (u8)(line & 0xff);

				// process commands of this row
				BOOL cmd = TRUE; // flag - required command
				BOOL str = FALSE; // flag - required string
				BOOL rem = FALSE; // flag - required commend
				while (Buf2Inx < Buf2Size)
				{
					// end of line
					if ((Buf2[Buf2Inx] == 13) || (Buf2[Buf2Inx] == 10)) break;

					// find token
					int token;
					if (cmd)
					{
						// command
						token = GetToken(TokensCmd, countof(TokensCmd));
						if (token == 0xfe) rem = TRUE;
						cmd = FALSE;
					}
					else
					{
						if (str || rem)
						{
							// string
							token = GetToken(TokensChar, countof(TokensChar));
							if (token < 0) token = GetToken(TokensCode, countof(TokensCode));
							if (token == 1) str = FALSE; // end string
						}
						else
						{
							// code
							token = GetToken(TokensCode, countof(TokensCode));
							if (token < 0) token = GetToken(TokensChar, countof(TokensChar));
							if (token == 1) str = TRUE; // start string
							if (token == 0xD5) cmd = TRUE; // start command
						}
					}

					if (token < 0)
					{
						printf("Unknown character at row %d\n", Line);
						return 1;
					}

					// store token
					Buf[inx++] = (u8)token;
					if (inx + 2 > BufMax)
					{
						printf("Insufficient storage space on row %d\n", Line);
						return 1;
					}
				}
				Buf[inx++] = NEWLINE;

				// check end of line
				if (!CheckEndLine())
				{
					printf("Unknown character at end of row %d\n", Line);
					return 1;
				}

				// next row
				InNextLine();
			}

			// store program size
			i = inx - BufSlot - 7 + 4;
			Buf[BufSlot+3] = (u8)(i & 0xff);
			Buf[BufSlot+4] = (u8)(i >> 8);
			int j = i;
			printf("program %d bytes", i - 4);

// ======== parse variables

			// process variables
			while (Buf2Inx < Buf2Size)
			{
				if (inx > BufMax)
				{
					printf(" Insufficient storage space on row %d\n", Line);
					return 1;
				}

				// command LET
				if (InToken("LET "))
				{
					// get first character of the variable name
					char name = InChar();
					if ((name < 'A') || (name > 'Z'))
					{
						printf(" Invalid variable name at row %d\n", Line);
						return 1;
					}

					char ch = InChar();

					// long integer
					if (((ch >= 'A') && (ch <= 'Z')) || ((ch >= '0') && (ch <= '9')))
					{
						// store header
						Buf[inx++] = 0x40 + name - 'A' + 6;

						// store name
						do
						{
							if (ch >= 'A')
								ch = ch - 'A' + 0x26;
							else
								ch = ch - '0' + 0x1c;
							Buf[inx++] = ch;

							ch = InChar();
						} while (((ch >= 'A') && (ch <= 'Z')) || ((ch >= '0') && (ch <= '9')));

						// mark last character
						Buf[inx-1] |= 0x80;

						// read number
						int num = InNum();
						Buf[inx++] = (u8)(num & 0xff);
						Buf[inx++] = (u8)(num >> 8);
					}

					// short integer
					else if (ch == '=')
					{
						// store number header
						Buf[inx++] = 0x60 + name - 'A' + 6;

						// read number
						int num = InNum();
						Buf[inx++] = (u8)(num & 0xff);
						Buf[inx++] = (u8)(num >> 8);
					}

					// string
					else if (ch == '$')
					{
						// '='
						if (InChar() != '=')
						{
							printf(" Missing '=' at row %d\n", Line);
							return 1;
						}

						// '"'
						if (InChar() != '"')
						{
							printf(" Missing '\"' at row %d\n", Line);
							return 1;
						}

						// store string header
						Buf[inx++] = 0x80 + name - 'A' + 6;

						// load string
						while (Buf2Inx < Buf2Size)
						{
							if (inx+2 > BufMax)
							{
								printf(" Insufficient storage space on row %d\n", Line);
								return 1;
							}

							int token = GetToken(TokensChar, countof(TokensChar));
							if (token < 0) token = GetToken(TokensCode, countof(TokensCode));
							if ((token == 1) || (token < 0)) break; // end string
							Buf[inx++] = (u8)token;
						}

						// terminate string "
						Buf[inx++] = 0x01;
					}
					else
					{
						printf(" Incorrect syntax on row %d\n", Line);
						return 1;
					}

					// check end of line
					if (!CheckEndLine())
					{
						printf(" Incorrect end of row %d\n", Line);
						return 1;
					}
				}
				else
				{
					// command DIM
					if (InToken("DIM "))
					{
						// get first character of the variable name
						char name = InChar();
						if ((name < 'A') || (name > 'Z'))
						{
							printf(" Invalid variable name at row %d\n", Line);
							return 1;
						}

						// '('
						if (InChar() != '(')
						{
							printf(" Missing '(' at row %d\n", Line);
							return 1;
						}

						// array size
						int size = InNum();
						if ((size < 0) || (size > 255))
						{
							printf(" Invalid array size at row %d\n", Line);
							return 1;
						}

						// ')'
						if (InChar() != ')')
						{
							printf(" Missing ')' at row %d\n", Line);
							return 1;
						}

						// '='
						if (InChar() != '=')
						{
							printf(" Missing '=' at row %d\n", Line);
							return 1;
						}

						// store array header
						Buf[inx++] = 0xa0 + name - 'A' + 6;
						Buf[inx++] = (u8)size;

						// parse array elements
						for (; size >= 0; size--)
						{
							if (inx + 2 > BufMax)
							{
								printf(" Insufficient storage space on row %d\n", Line);
								return 1;
							}

							// read number
							int num = InNum();
							Buf[inx++] = (u8)(num & 0xff);
							Buf[inx++] = (u8)(num >> 8);

							// ','
							if (size >= 1)
							{
								if (InChar() != ',')
								{
									printf(" Missing ',' at row %d\n", Line);
									return 1;
								}
							}
						}

						// check end of line
						if (!CheckEndLine())
						{
							printf(" Incorrect end of row %d\n", Line);
							return 1;
						}
					}
					else
					{
						// command FOR
						if (InToken("FOR "))
						{
							// get first character of the variable name
							char name = InChar();
							if ((name < 'A') || (name > 'Z'))
							{
								printf(" Invalid variable name at row %d\n", Line);
								return 1;
							}

							// store number header
							Buf[inx++] = 0xe0 + name - 'A' + 6;

							// '='
							if (InChar() != '=')
							{
								printf(" Missing '=' at row %d\n", Line);
								return 1;
							}

							for (i = 3; i > 0; i--)
							{
								// read number
								int num = InNum();
								Buf[inx++] = (u8)(num & 0xff);
								Buf[inx++] = (u8)(num >> 8);

								if (i > 1)
								{
									if (InChar() != ',')
									{
										printf(" Missing ',' at row %d\n", Line);
										return 1;
									}
								}
							}

							// check end of line
							if (!CheckEndLine())
							{
								printf(" Incorrect end of row %d\n", Line);
								return 1;
							}
						}
						else
							break;
					}
				}

				// next row
				InNextLine();
			}

// ======== write end of this slot

			// store variables end-mark
			Buf[inx++] = 0x80;

			// store total size
			i = inx - BufSlot - 7 + 4;
			Buf[BufSlot+5] = (u8)(i & 0xff);
			Buf[BufSlot+6] = (u8)(i >> 8);
			i = i - j - 1;
			if (i > 0) printf(", variables %d bytes", i);

			// store slot size
			i = (inx - BufSlot + PageSize - 1) & ~(PageSize - 1);
			Buf[BufSlot] = (u8)(i & 0xff);
			Buf[BufSlot+1] = (u8)(i >> 8);
			BufSlot += i;
			if (BufSlot > BufMax)
			{
				printf("Insufficient storage space on row %d\n", Line);
				return 1;
			}

			printf("\n");
		}
		else
			InNextLine();
	}

// ===== Write output file

	// open output file
	f = fopen(argv[3], "wb");
	if (f == NULL)
	{
		printf("Error creating %s\n", argv[3]);
		return 1;
	}

	// write output file
	fwrite(Buf, 1, BufSize, f);
	fclose(f);

	printf("\tUsed %d bytes of %d\n", BufSlot - BufSlot0, BufMax - BufSlot0);

	free(Buf);
	return 0;
}

