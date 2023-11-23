local names = require "lib.Enums.CharacterNames"

local growths = {
	[names.ALEN] = {
    PWR = 6,
    SKL = 3,
    DEF = 5,
    SPD = 4,
    MGC = 5,
    LUK = 4
  },
	[names.ANJI] = {
    PWR = 6,
    SKL = 5,
    DEF = 3,
    SPD = 5,
    MGC = 2,
    LUK = 2
  },
	[names.ANTONIO] = {
    PWR = 3,
    SKL = 3,
    DEF = 3,
    SPD = 4,
    MGC = 1,
    LUK = 3
  },
	[names.BLACKMAN] = {
    PWR = 5,
    SKL = 3,
    DEF = 6,
    SPD = 3,
    MGC = 1,
    LUK = 3
  },
	[names.CAMILLE] = {
    PWR = 5,
    SKL = 8,
    DEF = 4,
    SPD = 5,
    MGC = 5,
    LUK = 3
  },
	[names.CLEO] = {
    PWR = 5,
    SKL = 6,
    DEF = 5,
    SPD = 6,
    MGC = 6,
    LUK = 2
  },
	[names.CLIVE] = {
    PWR = 6,
    SKL = 8,
    DEF = 3,
    SPD = 6,
    MGC = 2,
    LUK = 1
  },
	[names.CROWLEY] = {
    PWR = 2,
    SKL = 3,
    DEF = 1,
    SPD = 5,
    MGC = 8,
    LUK = 3
  },
	[names.EIKEI] = {
    PWR = 5,
    SKL = 4,
    DEF = 5,
    SPD = 2,
    MGC = 0,
    LUK = 3
  },
	[names.EILEEN] = {
    PWR = 2,
    SKL = 4,
    DEF = 2,
    SPD = 6,
    MGC = 7,
    LUK = 5
  },
	[names.FLIK] = {
    PWR = 6,
    SKL = 6,
    DEF = 4,
    SPD = 6,
    MGC = 5,
    LUK = 4
  },
	[names.FUKIEN] = {
    PWR = 2,
    SKL = 3,
    DEF = 4,
    SPD = 4,
    MGC = 6,
    LUK = 5
  },
	[names.FUMA] = {
    PWR = 5,
    SKL = 5,
    DEF = 5,
    SPD = 6,
    MGC = 1,
    LUK = 3
  },
	[names.FUTCH] = {
    PWR = 5,
    SKL = 4,
    DEF = 5,
    SPD = 6,
    MGC = 2,
    LUK = 6
  },
	[names.FU_SU_LU] = {
    PWR = 8,
    SKL = 1,
    DEF = 6,
    SPD = 1,
    MGC = 0,
    LUK = 1
  },
	[names.GEN] = {
    PWR = 6,
    SKL = 5,
    DEF = 4,
    SPD = 4,
    MGC = 2,
    LUK = 4
  },
	[names.GON] = {
    PWR = 4,
    SKL = 4,
    DEF = 5,
    SPD = 3,
    MGC = 2,
    LUK = 8
  },
	[names.GREMIO] = {
    PWR = 13,
    SKL = 5,
    DEF = 6,
    SPD = 3,
    MGC = 2,
    LUK = 5
  },
	[names.GRENSEAL] = {
    PWR = 5,
    SKL = 4,
    DEF = 5,
    SPD = 5,
    MGC = 6,
    LUK = 3
  },
	[names.GRIFFITH] = {
    PWR = 5,
    SKL = 3,
    DEF = 4,
    SPD = 3,
    MGC = 2,
    LUK = 3
  },
	[names.HELLION] = {
    PWR = 1,
    SKL = 1,
    DEF = 3,
    SPD = 3,
    MGC = 7,
    LUK = 4
  },
	[names.HERO] = {
    PWR = 6,
    SKL = 7,
    DEF = 5,
    SPD = 7,
    MGC = 6,
    LUK = 6
  },
	[names.HIX] = {
    PWR = 5,
    SKL = 5,
    DEF = 4,
    SPD = 5,
    MGC = 3,
    LUK = 7
  },
	[names.HUMPHREY] = {
    PWR = 6,
    SKL = 3,
    DEF = 7,
    SPD = 2,
    MGC = 1,
    LUK = 3
  },
	[names.JUPPO] = {
    PWR = 3,
    SKL = 7,
    DEF = 4,
    SPD = 4,
    MGC = 4,
    LUK = 6
  },
	[names.KAGE] = {
    PWR = 4,
    SKL = 6,
    DEF = 5,
    SPD = 7,
    MGC = 3,
    LUK = 3
  },
	[names.KAI] = {
    PWR = 6,
    SKL = 3,
    DEF = 4,
    SPD = 2,
    MGC = 1,
    LUK = 3
  },
	[names.KAMANDOL] = {
    PWR = 4,
    SKL = 7,
    DEF = 2,
    SPD = 3,
    MGC = 3,
    LUK = 2
  },
	[names.KANAK] = {
    PWR = 5,
    SKL = 5,
    DEF = 4,
    SPD = 6,
    MGC = 0,
    LUK = 2
  },
	[names.KASIM] = {
    PWR = 7,
    SKL = 4,
    DEF = 6,
    SPD = 3,
    MGC = 1,
    LUK = 2
  },
	[names.KASUMI] = {
    PWR = 5,
    SKL = 6,
    DEF = 4,
    SPD = 8,
    MGC = 4,
    LUK = 3
  },
	[names.KESSLER] = {
    PWR = 5,
    SKL = 5,
    DEF = 4,
    SPD = 3,
    MGC = 2,
    LUK = 3
  },
	[names.KIMBERLY] = {
    PWR = 4,
    SKL = 6,
    DEF = 4,
    SPD = 5,
    MGC = 2,
    LUK = 5
  },
	[names.KIRKE] = {
    PWR = 5,
    SKL = 4,
    DEF = 4,
    SPD = 3,
    MGC = 2,
    LUK = 0
  },
	[names.KIRKIS] = {
    PWR = 5,
    SKL = 8,
    DEF = 5,
    SPD = 6,
    MGC = 5,
    LUK = 3
  },
	[names.KREUTZ] = {
    PWR = 6,
    SKL = 3,
    DEF = 6,
    SPD = 1,
    MGC = 1,
    LUK = 1
  },
	[names.KRIN] = {
    PWR = 3,
    SKL = 6,
    DEF = 2,
    SPD = 8,
    MGC = 1,
    LUK = 1
  },
	[names.KUROMIMI] = {
    PWR = 5,
    SKL = 4,
    DEF = 5,
    SPD = 5,
    MGC = 2,
    LUK = 5
  },
	[names.KWANDA] = {
    PWR = 6,
    SKL = 3,
    DEF = 8,
    SPD = 2,
    MGC = 1,
    LUK = 3
  },
	[names.LEONARDO] = {
    PWR = 6,
    SKL = 3,
    DEF = 4,
    SPD = 4,
    MGC = 1,
    LUK = 1
  },
	[names.LEPANT] = {
    PWR = 5,
    SKL = 5,
    DEF = 4,
    SPD = 4,
    MGC = 3,
    LUK = 4
  },
	[names.LESTER] = {
    PWR = 4,
    SKL = 4,
    DEF = 3,
    SPD = 5,
    MGC = 1,
    LUK = 5
  },
	[names.LIUKAN] = {
    PWR = 3,
    SKL = 7,
    DEF = 3,
    SPD = 4,
    MGC = 3,
    LUK = 5
  },
	[names.LORELAI] = {
    PWR = 5,
    SKL = 7,
    DEF = 4,
    SPD = 3,
    MGC = 2,
    LUK = 2
  },
	[names.LOTTE] = {
    PWR = 3,
    SKL = 4,
    DEF = 3,
    SPD = 5,
    MGC = 6,
    LUK = 4
  },
	[names.LUC] = {
    PWR = 0,
    SKL = 5,
    DEF = 1,
    SPD = 5,
    MGC = 8,
    LUK = 1
  },
	[names.MAAS] = {
    PWR = 4,
    SKL = 5,
    DEF = 4,
    SPD = 4,
    MGC = 2,
    LUK = 4
  },
	[names.MACE] = {
    PWR = 6,
    SKL = 6,
    DEF = 6,
    SPD = 5,
    MGC = 3,
    LUK = 5
  },
	[names.MEESE] = {
    PWR = 4,
    SKL = 5,
    DEF = 4,
    SPD = 4,
    MGC = 2,
    LUK = 4
  },
	[names.MEG] = {
    PWR = 4,
    SKL = 5,
    DEF = 4,
    SPD = 4,
    MGC = 3,
    LUK = 8
  },
	[names.MILIA] = {
    PWR = 6,
    SKL = 3,
    DEF = 6,
    SPD = 3,
    MGC = 1,
    LUK = 4
  },
	[names.MILICH] = {
    PWR = 5,
    SKL = 4,
    DEF = 5,
    SPD = 4,
    MGC = 6,
    LUK = 1
  },
	[names.MINA] = {
    PWR = 2,
    SKL = 4,
    DEF = 4,
    SPD = 4,
    MGC = 6,
    LUK = 6
  },
	[names.MOOSE] = {
    PWR = 4,
    SKL = 6,
    DEF = 4,
    SPD = 4,
    MGC = 2,
    LUK = 4
  },
	[names.MORGAN] = {
    PWR = 6,
    SKL = 3,
    DEF = 5,
    SPD = 2,
    MGC = 0,
    LUK = 1
  },
	[names.MOSE] = {
    PWR = 5,
    SKL = 5,
    DEF = 5,
    SPD = 4,
    MGC = 1,
    LUK = 3
  },
	[names.ODESSA] = {
    PWR = 5,
    SKL = 8,
    DEF = 5,
    SPD = 8,
    MGC = 7,
    LUK = 6
  },
	[names.PAHN] = {
    PWR = 7,
    SKL = 5,
    DEF = 6,
    SPD = 2,
    MGC = 0,
    LUK = 4
  },
	[names.PESMERGA] = {
    PWR = 8,
    SKL = 2,
    DEF = 6,
    SPD = 3,
    MGC = 1,
    LUK = 0
  },
	[names.QUINCY] = {
    PWR = 4,
    SKL = 8,
    DEF = 5,
    SPD = 5,
    MGC = 1,
    LUK = 5
  },
	[names.RONNIE] = {
    PWR = 6,
    SKL = 4,
    DEF = 6,
    SPD = 4,
    MGC = 0,
    LUK = 3
  },
	[names.RUBI] = {
    PWR = 5,
    SKL = 6,
    DEF = 4,
    SPD = 6,
    MGC = 6,
    LUK = 0
  },
	[names.SANSUKE] = {
    PWR = 3,
    SKL = 5,
    DEF = 5,
    SPD = 4,
    MGC = 1,
    LUK = 4
  },
	[names.SARAH] = {
    PWR = 5,
    SKL = 3,
    DEF = 5,
    SPD = 3,
    MGC = 4,
    LUK = 2
  },
	[names.SERGEI] = {
    PWR = 2,
    SKL = 6,
    DEF = 6,
    SPD = 3,
    MGC = 2,
    LUK = 2
  },
	[names.SHEENA] = {
    PWR = 5,
    SKL = 4,
    DEF = 5,
    SPD = 6,
    MGC = 6,
    LUK = 6
  },
	[names.SONYA] = {
    PWR = 6,
    SKL = 5,
    DEF = 4,
    SPD = 7,
    MGC = 5,
    LUK = 3
  },
	[names.STALLION] = {
    PWR = 3,
    SKL = 6,
    DEF = 5,
    SPD = 8,
    MGC = 4,
    LUK = 4
  },
	[names.SYDONIA] = {
    PWR = 4,
    SKL = 6,
    DEF = 3,
    SPD = 6,
    MGC = 3,
    LUK = 2
  },
	[names.SYLVINA] = {
    PWR = 3,
    SKL = 5,
    DEF = 4,
    SPD = 6,
    MGC = 5,
    LUK = 6
  },
	[names.TAI_HO] = {
    PWR = 6,
    SKL = 7,
    DEF = 3,
    SPD = 5,
    MGC = 1,
    LUK = 4
  },
	[names.TENGAAR] = {
    PWR = 3,
    SKL = 6,
    DEF = 4,
    SPD = 5,
    MGC = 7,
    LUK = 2
  },
	[names.TED] = {
    PWR = 5,
    SKL = 7,
    DEF = 4,
    SPD = 6,
    MGC = 7,
    LUK = 4
  },
	[names.VALERIA] = {
    PWR = 6,
    SKL = 4,
    DEF = 6,
    SPD = 3,
    MGC = 3,
    LUK = 4
  },
	[names.VARKAS] = {
    PWR = 6,
    SKL = 3,
    DEF = 5,
    SPD = 3,
    MGC = 1,
    LUK = 2
  },
	[names.VIKTOR] = {
    PWR = 9,
    SKL = 2,
    DEF = 7,
    SPD = 5,
    MGC = 3,
    LUK = 4
  },
	[names.WARREN] = {
    PWR = 5,
    SKL = 4,
    DEF = 5,
    SPD = 3,
    MGC = 2,
    LUK = 3
  },
	[names.YAM_KOO] = {
    PWR = 5,
    SKL = 6,
    DEF = 3,
    SPD = 6,
    MGC = 2,
    LUK = 4
  },
}

return growths
