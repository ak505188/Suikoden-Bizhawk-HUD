local Names = require "lib.Characters.Names"

local Growths = {
	[Names.ALEN] = {
    PWR = 6,
    SKL = 3,
    DEF = 5,
    SPD = 4,
    MGC = 5,
    LUK = 4
  },
	[Names.ANJI] = {
    PWR = 6,
    SKL = 5,
    DEF = 3,
    SPD = 5,
    MGC = 2,
    LUK = 2
  },
	[Names.ANTONIO] = {
    PWR = 3,
    SKL = 3,
    DEF = 3,
    SPD = 4,
    MGC = 1,
    LUK = 3
  },
	[Names.BLACKMAN] = {
    PWR = 5,
    SKL = 3,
    DEF = 6,
    SPD = 3,
    MGC = 1,
    LUK = 3
  },
	[Names.CAMILLE] = {
    PWR = 5,
    SKL = 8,
    DEF = 4,
    SPD = 5,
    MGC = 5,
    LUK = 3
  },
	[Names.CLEO] = {
    PWR = 5,
    SKL = 6,
    DEF = 5,
    SPD = 6,
    MGC = 6,
    LUK = 2
  },
	[Names.CLIVE] = {
    PWR = 6,
    SKL = 8,
    DEF = 3,
    SPD = 6,
    MGC = 2,
    LUK = 1
  },
	[Names.CROWLEY] = {
    PWR = 2,
    SKL = 3,
    DEF = 1,
    SPD = 5,
    MGC = 8,
    LUK = 3
  },
	[Names.EIKEI] = {
    PWR = 5,
    SKL = 4,
    DEF = 5,
    SPD = 2,
    MGC = 0,
    LUK = 3
  },
	[Names.EILEEN] = {
    PWR = 2,
    SKL = 4,
    DEF = 2,
    SPD = 6,
    MGC = 7,
    LUK = 5
  },
	[Names.FLIK] = {
    PWR = 6,
    SKL = 6,
    DEF = 4,
    SPD = 6,
    MGC = 5,
    LUK = 4
  },
	[Names.FUKIEN] = {
    PWR = 2,
    SKL = 3,
    DEF = 4,
    SPD = 4,
    MGC = 6,
    LUK = 5
  },
	[Names.FUMA] = {
    PWR = 5,
    SKL = 5,
    DEF = 5,
    SPD = 6,
    MGC = 1,
    LUK = 3
  },
	[Names.FUTCH] = {
    PWR = 5,
    SKL = 4,
    DEF = 5,
    SPD = 6,
    MGC = 2,
    LUK = 6
  },
	[Names.FU_SU_LU] = {
    PWR = 8,
    SKL = 1,
    DEF = 6,
    SPD = 1,
    MGC = 0,
    LUK = 1
  },
	[Names.GEN] = {
    PWR = 6,
    SKL = 5,
    DEF = 4,
    SPD = 4,
    MGC = 2,
    LUK = 4
  },
	[Names.GON] = {
    PWR = 4,
    SKL = 4,
    DEF = 5,
    SPD = 3,
    MGC = 2,
    LUK = 8
  },
	[Names.GREMIO] = {
    PWR = 13,
    SKL = 5,
    DEF = 6,
    SPD = 3,
    MGC = 2,
    LUK = 5
  },
	[Names.GRENSEAL] = {
    PWR = 5,
    SKL = 4,
    DEF = 5,
    SPD = 5,
    MGC = 6,
    LUK = 3
  },
	[Names.GRIFFITH] = {
    PWR = 5,
    SKL = 3,
    DEF = 4,
    SPD = 3,
    MGC = 2,
    LUK = 3
  },
	[Names.HELLION] = {
    PWR = 1,
    SKL = 1,
    DEF = 3,
    SPD = 3,
    MGC = 7,
    LUK = 4
  },
	[Names.HERO] = {
    PWR = 6,
    SKL = 7,
    DEF = 5,
    SPD = 7,
    MGC = 6,
    LUK = 6
  },
	[Names.HIX] = {
    PWR = 5,
    SKL = 5,
    DEF = 4,
    SPD = 5,
    MGC = 3,
    LUK = 7
  },
	[Names.HUMPHREY] = {
    PWR = 6,
    SKL = 3,
    DEF = 7,
    SPD = 2,
    MGC = 1,
    LUK = 3
  },
	[Names.JUPPO] = {
    PWR = 3,
    SKL = 7,
    DEF = 4,
    SPD = 4,
    MGC = 4,
    LUK = 6
  },
	[Names.KAGE] = {
    PWR = 4,
    SKL = 6,
    DEF = 5,
    SPD = 7,
    MGC = 3,
    LUK = 3
  },
	[Names.KAI] = {
    PWR = 6,
    SKL = 3,
    DEF = 4,
    SPD = 2,
    MGC = 1,
    LUK = 3
  },
	[Names.KAMANDOL] = {
    PWR = 4,
    SKL = 7,
    DEF = 2,
    SPD = 3,
    MGC = 3,
    LUK = 2
  },
	[Names.KANAK] = {
    PWR = 5,
    SKL = 5,
    DEF = 4,
    SPD = 6,
    MGC = 0,
    LUK = 2
  },
	[Names.KASIM] = {
    PWR = 7,
    SKL = 4,
    DEF = 6,
    SPD = 3,
    MGC = 1,
    LUK = 2
  },
	[Names.KASUMI] = {
    PWR = 5,
    SKL = 6,
    DEF = 4,
    SPD = 8,
    MGC = 4,
    LUK = 3
  },
	[Names.KESSLER] = {
    PWR = 5,
    SKL = 5,
    DEF = 4,
    SPD = 3,
    MGC = 2,
    LUK = 3
  },
	[Names.KIMBERLY] = {
    PWR = 4,
    SKL = 6,
    DEF = 4,
    SPD = 5,
    MGC = 2,
    LUK = 5
  },
	[Names.KIRKE] = {
    PWR = 5,
    SKL = 4,
    DEF = 4,
    SPD = 3,
    MGC = 2,
    LUK = 0
  },
	[Names.KIRKIS] = {
    PWR = 5,
    SKL = 8,
    DEF = 5,
    SPD = 6,
    MGC = 5,
    LUK = 3
  },
	[Names.KREUTZ] = {
    PWR = 6,
    SKL = 3,
    DEF = 6,
    SPD = 1,
    MGC = 1,
    LUK = 1
  },
	[Names.KRIN] = {
    PWR = 3,
    SKL = 6,
    DEF = 2,
    SPD = 8,
    MGC = 1,
    LUK = 1
  },
	[Names.KUROMIMI] = {
    PWR = 5,
    SKL = 4,
    DEF = 5,
    SPD = 5,
    MGC = 2,
    LUK = 5
  },
	[Names.KWANDA] = {
    PWR = 6,
    SKL = 3,
    DEF = 8,
    SPD = 2,
    MGC = 1,
    LUK = 3
  },
	[Names.LEONARDO] = {
    PWR = 6,
    SKL = 3,
    DEF = 4,
    SPD = 4,
    MGC = 1,
    LUK = 1
  },
	[Names.LEPANT] = {
    PWR = 5,
    SKL = 5,
    DEF = 4,
    SPD = 4,
    MGC = 3,
    LUK = 4
  },
	[Names.LESTER] = {
    PWR = 4,
    SKL = 4,
    DEF = 3,
    SPD = 5,
    MGC = 1,
    LUK = 5
  },
	[Names.LIUKAN] = {
    PWR = 3,
    SKL = 7,
    DEF = 3,
    SPD = 4,
    MGC = 3,
    LUK = 5
  },
	[Names.LORELAI] = {
    PWR = 5,
    SKL = 7,
    DEF = 4,
    SPD = 3,
    MGC = 2,
    LUK = 2
  },
	[Names.LOTTE] = {
    PWR = 3,
    SKL = 4,
    DEF = 3,
    SPD = 5,
    MGC = 6,
    LUK = 4
  },
	[Names.LUC] = {
    PWR = 0,
    SKL = 5,
    DEF = 1,
    SPD = 5,
    MGC = 8,
    LUK = 1
  },
	[Names.MAAS] = {
    PWR = 4,
    SKL = 5,
    DEF = 4,
    SPD = 4,
    MGC = 2,
    LUK = 4
  },
	[Names.MACE] = {
    PWR = 6,
    SKL = 6,
    DEF = 6,
    SPD = 5,
    MGC = 3,
    LUK = 5
  },
	[Names.MEESE] = {
    PWR = 4,
    SKL = 5,
    DEF = 4,
    SPD = 4,
    MGC = 2,
    LUK = 4
  },
	[Names.MEG] = {
    PWR = 4,
    SKL = 5,
    DEF = 4,
    SPD = 4,
    MGC = 3,
    LUK = 8
  },
	[Names.MILIA] = {
    PWR = 6,
    SKL = 3,
    DEF = 6,
    SPD = 3,
    MGC = 1,
    LUK = 4
  },
	[Names.MILICH] = {
    PWR = 5,
    SKL = 4,
    DEF = 5,
    SPD = 4,
    MGC = 6,
    LUK = 1
  },
	[Names.MINA] = {
    PWR = 2,
    SKL = 4,
    DEF = 4,
    SPD = 4,
    MGC = 6,
    LUK = 6
  },
	[Names.MOOSE] = {
    PWR = 4,
    SKL = 6,
    DEF = 4,
    SPD = 4,
    MGC = 2,
    LUK = 4
  },
	[Names.MORGAN] = {
    PWR = 6,
    SKL = 3,
    DEF = 5,
    SPD = 2,
    MGC = 0,
    LUK = 1
  },
	[Names.MOSE] = {
    PWR = 5,
    SKL = 5,
    DEF = 5,
    SPD = 4,
    MGC = 1,
    LUK = 3
  },
	[Names.ODESSA] = {
    PWR = 5,
    SKL = 8,
    DEF = 5,
    SPD = 8,
    MGC = 7,
    LUK = 6
  },
	[Names.PAHN] = {
    PWR = 7,
    SKL = 5,
    DEF = 6,
    SPD = 2,
    MGC = 0,
    LUK = 4
  },
	[Names.PESMERGA] = {
    PWR = 8,
    SKL = 2,
    DEF = 6,
    SPD = 3,
    MGC = 1,
    LUK = 0
  },
	[Names.QUINCY] = {
    PWR = 4,
    SKL = 8,
    DEF = 5,
    SPD = 5,
    MGC = 1,
    LUK = 5
  },
	[Names.RONNIE] = {
    PWR = 6,
    SKL = 4,
    DEF = 6,
    SPD = 4,
    MGC = 0,
    LUK = 3
  },
	[Names.RUBI] = {
    PWR = 5,
    SKL = 6,
    DEF = 4,
    SPD = 6,
    MGC = 6,
    LUK = 0
  },
	[Names.SANSUKE] = {
    PWR = 3,
    SKL = 5,
    DEF = 5,
    SPD = 4,
    MGC = 1,
    LUK = 4
  },
	[Names.SARAH] = {
    PWR = 5,
    SKL = 3,
    DEF = 5,
    SPD = 3,
    MGC = 4,
    LUK = 2
  },
	[Names.SERGEI] = {
    PWR = 2,
    SKL = 6,
    DEF = 6,
    SPD = 3,
    MGC = 2,
    LUK = 2
  },
	[Names.SHEENA] = {
    PWR = 5,
    SKL = 4,
    DEF = 5,
    SPD = 6,
    MGC = 6,
    LUK = 6
  },
	[Names.SONYA] = {
    PWR = 6,
    SKL = 5,
    DEF = 4,
    SPD = 7,
    MGC = 5,
    LUK = 3
  },
	[Names.STALLION] = {
    PWR = 3,
    SKL = 6,
    DEF = 5,
    SPD = 8,
    MGC = 4,
    LUK = 4
  },
	[Names.SYDONIA] = {
    PWR = 4,
    SKL = 6,
    DEF = 3,
    SPD = 6,
    MGC = 3,
    LUK = 2
  },
	[Names.SYLVINA] = {
    PWR = 3,
    SKL = 5,
    DEF = 4,
    SPD = 6,
    MGC = 5,
    LUK = 6
  },
	[Names.TAI_HO] = {
    PWR = 6,
    SKL = 7,
    DEF = 3,
    SPD = 5,
    MGC = 1,
    LUK = 4
  },
	[Names.TENGAAR] = {
    PWR = 3,
    SKL = 6,
    DEF = 4,
    SPD = 5,
    MGC = 7,
    LUK = 2
  },
	[Names.TED] = {
    PWR = 5,
    SKL = 7,
    DEF = 4,
    SPD = 6,
    MGC = 7,
    LUK = 4
  },
	[Names.VALERIA] = {
    PWR = 6,
    SKL = 4,
    DEF = 6,
    SPD = 3,
    MGC = 3,
    LUK = 4
  },
	[Names.VARKAS] = {
    PWR = 6,
    SKL = 3,
    DEF = 5,
    SPD = 3,
    MGC = 1,
    LUK = 2
  },
	[Names.VIKTOR] = {
    PWR = 9,
    SKL = 2,
    DEF = 7,
    SPD = 5,
    MGC = 3,
    LUK = 4
  },
	[Names.WARREN] = {
    PWR = 5,
    SKL = 4,
    DEF = 5,
    SPD = 3,
    MGC = 2,
    LUK = 3
  },
	[Names.YAM_KOO] = {
    PWR = 5,
    SKL = 6,
    DEF = 3,
    SPD = 6,
    MGC = 2,
    LUK = 4
  },
}

return Growths
