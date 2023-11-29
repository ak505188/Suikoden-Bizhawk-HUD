local Names = require "lib.Characters.Names"

local Addresses = {
	[Names.ALEN] = {
    RecruitmentState = 0x1B9B24,
    Stats = 0x1B9234,
    Id = 48,
  },
	[Names.ANJI] = {
    RecruitmentState = 0x1B9AFF,
    Stats = 0x1B91E4,
    Id = 11,
  },
	[Names.ANTONIO] = {
    RecruitmentState = 0x1B9B59,
    Stats = 0x1B8F64,
    Id = 101,
  },
	[Names.APPLE] = {
    RecruitmentState = 0x1B9B30,
  },
	[Names.BLACKMAN] = {
    RecruitmentState = 0x1B9B3D,
    Stats = 0x1B8E74,
    Id = 73,
  },
	[Names.CAMILLE] = {
    RecruitmentState = 0x1B9AF7,
    Stats = 0x1B84C4,
    Id = 3,
  },
	[Names.CHANDLER] = {
    RecruitmentState = 0x1B9B5D,
  },
	[Names.CHAPMAN] = {
    RecruitmentState = 0x1B9B5C,
  },
	[Names.CLEO] = {
    RecruitmentState = 0x1B9AF6,
    Stats = 0x1B8384,
    Id = 1,
  },
	[Names.CLIVE] = {
    RecruitmentState = 0x1B9B29,
    Stats = 0x1B9004,
    Id = 53,
  },
	[Names.CROWLEY] = {
    RecruitmentState = 0x1B9B34,
    Stats = 0x1B9054,
    Id = 64,
  },
	[Names.EIKEI] = {
    RecruitmentState = 0x1B9B36,
    Stats = 0x1B9324,
    Id = 66,
  },
	[Names.EILEEN] = {
    RecruitmentState = 0x1B9AF5,
    Stats = 0x1B8654,
    Id = 0,
  },
	[Names.ESMERALDA] = {
    RecruitmentState = 0x1B9B2D,
  },
	[Names.FLIK] = {
    RecruitmentState = 0x1B9B05,
    Stats = 0x1B90A4,
    Id = 17,
  },
	[Names.FUKIEN] = {
    RecruitmentState = 0x1B9B06,
    Stats = 0x1B8B04,
    Id = 18,
  },
	[Names.FUMA] = {
    RecruitmentState = 0x1B9B2B,
    Stats = 0x1B8DD4,
    Id = 55,
  },
	[Names.FUTCH] = {
    RecruitmentState = 0x1B9B07,
    Stats = 0x1B9194,
    Id = 19,
  },
	[Names.FU_SU_LU] = {
    RecruitmentState = 0x1B9B35,
    Stats = 0x1B8D84,
    Id = 65,
  },
	[Names.GASPAR] = {
    RecruitmentState = 0x1B9B4C,
  },
	[Names.GEN] = {
    RecruitmentState = 0x1B9B08,
    Stats = 0x1B8BA4,
    Id = 20,
  },
	[Names.GEORGES] = {
    RecruitmentState = 0x1B9B48,
  },
	[Names.GIOVANNI] = {
    RecruitmentState = 0x1B9B20,
  },
	[Names.GON] = {
    RecruitmentState = 0x1B9B44,
    Stats = 0x1B9374,
    Id = 80,
  },
	[Names.GREMIO] = {
    RecruitmentState = 0x1B9AF4,
    Stats = 0x1B82E4,
    Id = 2,
  },
	[Names.GRENSEAL] = {
    RecruitmentState = 0x1B9B25,
    Stats = 0x1B9414,
    Id = 49,
  },
	[Names.GRIFFITH] = {
    RecruitmentState = 0x1B9B1E,
    Stats = 0x1B93C4,
    Id = 42,
  },
	[Names.HELLION] = {
    RecruitmentState = 0x1B9B2F,
    Stats = 0x1B9464,
    Id = 59,
  },
	[Names.HERO] = {
    RecruitmentState = 0x1B9AFC,
    Stats = 0x1B8294,
    Id = 8,
  },
	[Names.HIX] = {
    RecruitmentState = 0x1B9B33,
    Stats = 0x1B8A14,
    Id = 63,
  },
	[Names.HUGO] = {
    RecruitmentState = 0x1B9B51,
  },
	[Names.HUMPHREY] = {
    RecruitmentState = 0x1B9B09,
    Stats = 0x1B88D4,
    Id = 21,
  },
	[Names.IVANOV] = {
    RecruitmentState = 0x1B9B52,
  },
	[Names.JABBA] = {
    RecruitmentState = 0x1B9B54,
  },
	[Names.JEANE] = {
    RecruitmentState = 0x1B9B57,
  },
	[Names.JOSHUA] = {
    RecruitmentState = 0x1B9B41,
  },
	[Names.JUPPO] = {
    RecruitmentState = 0x1B9B1B,
    Stats = 0x1B8834,
    Id = 39,
  },
	[Names.KAGE] = {
    RecruitmentState = 0x1B9B0A,
    Stats = 0x1B8D34,
    Id = 22,
  },
	[Names.KAI] = {
    RecruitmentState = 0x1B9B4F,
    Stats = 0x1B8A64,
    Id = 91,
  },
	[Names.KAMANDOL] = {
    RecruitmentState = 0x1B9B37,
    Stats = 0x1B92D4,
    Id = 67,
  },
	[Names.KANAK] = {
    RecruitmentState = 0x1B9B1F,
    Stats = 0x1B9554,
    Id = 43,
  },
	[Names.KASIM] = {
    RecruitmentState = 0x1B9B04,
    Stats = 0x1B90F4,
    Id = 16,
  },
	[Names.KASIOS] = {
    RecruitmentState = 0x1B9B58,
  },
	[Names.KASUMI] = {
    RecruitmentState = 0x1B9B0B,
    Stats = 0x1B94B4,
    Id = 23,
  },
	[Names.KESSLER] = {
    RecruitmentState = 0x1B9B1C,
    Stats = 0x1B9504,
    Id = 40,
  },
	[Names.KIMBERLY] = {
    RecruitmentState = 0x1B9B21,
    Stats = 0x1B8884,
    Id = 45,
  },
	[Names.KIRKE] = {
    RecruitmentState = 0x1B9B45,
    Stats = 0x1B8EC4,
    Id = 81,
  },
	[Names.KIRKIS] = {
    RecruitmentState = 0x1B9AF8,
    Stats = 0x1B85B4,
    Id = 4,
  },
	[Names.KREUTZ] = {
    RecruitmentState = 0x1B9B3E,
    Stats = 0x1B8924,
    Id = 74,
  },
	[Names.KRIN] = {
    RecruitmentState = 0x1B9B03,
    Stats = 0x1B87E4,
    Id = 15,
  },
	[Names.KUN_TO] = {
    RecruitmentState = 0x1B9B0C,
  },
	[Names.KUROMIMI] = {
    RecruitmentState = 0x1B9B02,
    Stats = 0x1B8564,
    Id = 14,
  },
	[Names.KWANDA] = {
    RecruitmentState = 0x1B9B0D,
    Stats = 0x1B95A4,
    Id = 25,
  },
	[Names.LEDON] = {
    RecruitmentState = 0x1B9B42,
  },
	[Names.LEONARDO] = {
    RecruitmentState = 0x1B9B1D,
    Stats = 0x1B95F4,
    Id = 41,
  },
	[Names.LEON] = {
    RecruitmentState = 0x1B9B5E,
  },
	[Names.LEPANT] = {
    RecruitmentState = 0x1B9B12,
    Stats = 0x1B8794,
    Id = 30,
  },
	[Names.LESTER] = {
    RecruitmentState = 0x1B9B5A,
    Stats = 0x1B8FB4,
    Id = 102,
  },
	[Names.LIUKAN] = {
    RecruitmentState = 0x1B9AFB,
    Stats = 0x1B8C94,
    Id = 7,
  },
	[Names.LORELAI] = {
    RecruitmentState = 0x1B9B23,
    Stats = 0x1B86A4,
    Id = 47,
  },
	[Names.LOTTE] = {
    RecruitmentState = 0x1B9B2C,
    Stats = 0x1B9644,
    Id = 56,
  },
	[Names.LUC] = {
    RecruitmentState = 0x1B9B0E,
    Stats = 0x1B8C44,
    Id = 26,
  },
	[Names.MAAS] = {
    RecruitmentState = 0x1B9B3A,
    Stats = 0x1B96E4,
    Id = 70,
  },
	[Names.MACE] = {
    RecruitmentState = 0x1B9B3B,
    Stats = 0x1B9734,
    Id = 71,
  },
	[Names.MARCO] = {
    RecruitmentState = 0x1B9B5B,
  },
	[Names.MARIE] = {
    RecruitmentState = 0x1B9B22,
  },
	[Names.MATHIU] = {
    RecruitmentState = 0x1B9B0F,
  },
	[Names.MAX] = {
    RecruitmentState = 0x1B9B46,
  },
	[Names.MEESE] = {
    RecruitmentState = 0x1B9B39,
    Stats = 0x1B97D4,
    Id = 69,
  },
	[Names.MEG] = {
    RecruitmentState = 0x1B9B40,
    Stats = 0x1B8BF4,
    Id = 76,
  },
	[Names.MELODYE] = {
    RecruitmentState = 0x1B9B4A,
  },
	[Names.MILIA] = {
    RecruitmentState = 0x1B9B11,
    Stats = 0x1B9874,
    Id = 29,
  },
	[Names.MILICH] = {
    RecruitmentState = 0x1B9B10,
    Stats = 0x1B9784,
    Id = 28,
  },
	[Names.MINA] = {
    RecruitmentState = 0x1B9B31,
    Stats = 0x1B8E24,
    Id = 61,
  },
	[Names.MOOSE] = {
    RecruitmentState = 0x1B9B3C,
    Stats = 0x1B98C4,
    Id = 72,
  },
	[Names.MORGAN] = {
    RecruitmentState = 0x1B9B28,
    Stats = 0x1B9824,
    Id = 52,
  },
	[Names.MOSE] = {
    RecruitmentState = 0x1B9AF9,
    Stats = 0x1B8974,
    Id = 5,
  },
	[Names.ODESSA] = {
    Stats = 0x1B8474,
    Id = 109,
  },
	[Names.ONIL] = {
    RecruitmentState = 0x1B9B4D,
  },
	[Names.PAHN] = {
    RecruitmentState = 0x1B9AFA,
    Stats = 0x1B8334,
    Id = 6,
  },
	[Names.PESMERGA] = {
    RecruitmentState = 0x1B9B5F,
    Stats = 0x1B9914,
    Id = 107,
  },
	[Names.QLON] = {
    RecruitmentState = 0x1B9B56,
  },
	[Names.QUINCY] = {
    RecruitmentState = 0x1B9B38,
    Stats = 0x1B9964,
    Id = 68,
  },
	[Names.ROCK] = {
    RecruitmentState = 0x1B9B49,
  },
	[Names.RONNIE] = {
    RecruitmentState = 0x1B9B01,
    Stats = 0x1B8CE4,
    Id = 13,
  },
	[Names.RUBI] = {
    RecruitmentState = 0x1B9B27,
    Stats = 0x1B9694,
    Id = 51,
  },
	[Names.SANCHO] = {
    RecruitmentState = 0x1B9B47,
  },
	[Names.SANSUKE] = {
    RecruitmentState = 0x1B9B53,
    Stats = 0x1B99B4,
    Id = 95,
  },
	[Names.SARAH] = {
    RecruitmentState = 0x1B9B2A,
    Stats = 0x1B8F14,
    Id = 54,
  },
	[Names.SERGEI] = {
    RecruitmentState = 0x1B9B50,
    Stats = 0x1B9A04,
    Id = 92,
  },
	[Names.SHEENA] = {
    RecruitmentState = 0x1B9B32,
    Stats = 0x1B89C4,
    Id = 62,
  },
	[Names.SONYA] = {
    RecruitmentState = 0x1B9AFE,
    Stats = 0x1B9144,
    Id = 10,
  },
	[Names.STALLION] = {
    RecruitmentState = 0x1B9B3F,
    Stats = 0x1B86F4,
    Id = 75,
  },
	[Names.SYDONIA] = {
    RecruitmentState = 0x1B9B13,
    Stats = 0x1B8AB4,
    Id = 31,
  },
	[Names.SYLVINA] = {
    RecruitmentState = 0x1B9AFD,
    Stats = 0x1B8B54,
    Id = 9,
  },
	[Names.TAGGART] = {
    RecruitmentState = 0x1B9B43,
  },
	[Names.TAI_HO] = {
    RecruitmentState = 0x1B9B14,
    Stats = 0x1B8514,
    Id = 32,
  },
	[Names.TED] = {
    Stats = 0x1B83D4,
    Id = 108,
  },
	[Names.TEMPLETON] = {
    RecruitmentState = 0x1B9B2E,
  },
	[Names.TENGAAR] = {
    RecruitmentState = 0x1B9B15,
    Stats = 0x1B9A54,
    Id = 33,
  },
	[Names.TESLA] = {
    RecruitmentState = 0x1B9B16,
  },
	[Names.VALERIA] = {
    RecruitmentState = 0x1B9B18,
    Stats = 0x1B8604,
    Id = 36,
  },
	[Names.VARKAS] = {
    RecruitmentState = 0x1B9B00,
    Stats = 0x1B9284,
    Id = 12,
  },
	[Names.VIKI] = {
    RecruitmentState = 0x1B9B55,
  },
	[Names.VIKTOR] = {
    RecruitmentState = 0x1B9B17,
    Stats = 0x1B8424,
    Id = 35,
  },
	[Names.VINCENT] = {
    RecruitmentState = 0x1B9B26,
  },
	[Names.WARREN] = {
    RecruitmentState = 0x1B9B19,
    Stats = 0x1B9AA4,
    Id = 37,
  },
	[Names.WINDOW] = {
    RecruitmentState = 0x1B9B4B,
  },
	[Names.YAM_KOO] = {
    RecruitmentState = 0x1B9B1A,
    Stats = 0x1B8744,
    Id = 38,
  },
	[Names.ZEN] = {
    RecruitmentState = 0x1B9B4E,
  },
}

return Addresses
